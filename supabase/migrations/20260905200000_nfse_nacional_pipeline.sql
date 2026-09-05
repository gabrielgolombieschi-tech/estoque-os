-- NFS-e Padrao Nacional a partir da OS, pela Focus. Parte 2: pipeline (05/09/2026).
-- Fundacao: 20260905190000_nfse_nacional_fundacao.sql. Inventario:
-- docs/faturamento/nfse-inventario.md.
--
-- Funcoes novas (prefixo fn_nfse_ / *_os_servico), nenhuma altera o pipeline
-- de NF-e em producao:
--   f.fn_nfse_discriminacao            texto da DPS (<=1000), mesma ordem das NFS-e reais
--   f.fn_solicitacao_faturamento_criar_os_servico  linhas de servico por valor, uma OS por linha
--   f.fn_os_nfse_conferir_homologacao  validacao local + fixture + snapshots (bloqueios com campo e rota)
--   f.fn_nfse_preparar_documento_solicitacao  documento RASCUNHO + emissao + DPS numerada na mesma transacao
--   f.fn_nfse_homologacao_claimar      claim duravel; retry apos rejeicao troca so o numero da DPS
--   f.fn_nfse_renumerar_dps            numero novo depois de rejeicao (o antigo fica queimado no log)
--   f.fn_nfse_aplicar_retorno          autorizado/erro/cancelado/substituido; HOM mantem documento RASCUNHO;
--                                      PROD grava EMITIDA, titulo liquido e f.titulo_retencao
--   f.fn_nfse_titulo_liquido_sincronizar / f.fn_nfse_titulo_cancelar
--   f.fn_nfse_cancelamento_claim / f.fn_nfse_cancelamento_finalizar (prazo em empresa_fiscal)
--   f.fn_nfse_substituir_preparar      clona a solicitacao para a NFS-e substituta
--   f.fn_nfse_abandonar_homologacao    abandono (reaproveita o fluxo da NF-e) + log da DPS
--   f.fn_nfse_emissoes_pendentes_reconciliacao
--   f.fn_nfse_producao_pronta          portao de producao para perfil de servico
--   f.fn_nfse_registrar_webhook
--
-- Objetos de producao alterados (baseline 05/09/2026):
--   f.fn_nfe_producao_pronta(uuid): corpo original reproduzido abaixo; a unica
--     mudanca e o desvio no inicio para solicitacoes com linha modelo='NFSE'.
--   f.trg_nfse_sync_piscofins_from_doc(): original chamava
--     fn_nfse_sync_piscofins_debito_doc para todo documento NFSE/SAIDA/SERVICO
--     nao excluido; passa a ignorar nfse_status='RASCUNHO' (documento de
--     homologacao, que nunca existiu antes desta data). Nao e trigger de NF-e.

-- ---------------------------------------------------------------------------
-- Discriminacao
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_discriminacao(
  p_linhas jsonb,              -- [{descricao, os_numero}]
  p_pedido text,
  p_pedido_item text,
  p_parcelas jsonb,            -- [{numero, dias, valor}] ou null (a vista)
  p_base_date date,
  p_iss_retido boolean,
  p_texto_retencao text,
  p_observacao text
) returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_partes text[] := array[]::text[];
  v_linha jsonb;
  v_dias text[] := array[]::text[];
  v_datas text[] := array[]::text[];
  v_p jsonb;
  v_texto text;
begin
  for v_linha in select * from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) loop
    v_partes := array_append(v_partes, upper(btrim(coalesce(v_linha->>'descricao', ''))) || ' - OS ' || coalesce(v_linha->>'os_numero', '?') || '.');
  end loop;
  if nullif(btrim(coalesce(p_pedido, '')), '') is not null then
    v_partes := array_append(v_partes, 'PEDIDO DE COMPRA: ' || btrim(p_pedido)
      || case when nullif(btrim(coalesce(p_pedido_item, '')), '') is not null then ' ITEM ' || btrim(p_pedido_item) else '' end || '.');
  end if;
  if p_parcelas is null or jsonb_typeof(p_parcelas) <> 'array' or jsonb_array_length(p_parcelas) = 0 then
    v_partes := array_append(v_partes, 'PAGAMENTO A VISTA.');
  else
    for v_p in select * from jsonb_array_elements(p_parcelas) loop
      v_dias := array_append(v_dias, v_p->>'dias');
      v_datas := array_append(v_datas, to_char(p_base_date + (v_p->>'dias')::integer, 'DD/MM/YYYY'));
    end loop;
    v_partes := array_append(v_partes, case when array_length(v_dias, 1) > 1 then 'VENCIMENTOS: ' else 'VENCIMENTO: ' end
      || array_to_string(v_dias, '/') || ' DDL (' || array_to_string(v_datas, ', ') || ').');
  end if;
  v_partes := array_append(v_partes, case when p_iss_retido then 'ISS RETIDO PELO TOMADOR.' else 'ISS RECOLHIDO PELO PRESTADOR.' end);
  if nullif(btrim(coalesce(p_texto_retencao, '')), '') is not null then
    v_partes := array_append(v_partes, btrim(p_texto_retencao) || case when right(btrim(p_texto_retencao), 1) in ('.', '"') then '' else '.' end);
  end if;
  if nullif(btrim(coalesce(p_observacao, '')), '') is not null then
    v_partes := array_append(v_partes, btrim(p_observacao));
  end if;
  v_texto := regexp_replace(array_to_string(v_partes, ' '), '\s+', ' ', 'g');
  return left(v_texto, 1000);
end;
$$;
revoke all on function f.fn_nfse_discriminacao(jsonb, text, text, jsonb, date, boolean, text, text) from public;
grant execute on function f.fn_nfse_discriminacao(jsonb, text, text, jsonb, date, boolean, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Solicitacao de servico (uma OS por linha)
-- ---------------------------------------------------------------------------
create or replace function f.fn_solicitacao_faturamento_criar_os_servico(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_perfil_operacao_id uuid,
  p_linhas jsonb   -- [{os_id, descricao_servico, valor_servico}]
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_perfil f.perfil_operacao%rowtype;
  v_solicitacao_id uuid := gen_random_uuid();
  v_linha record;
  v_os public.ordens_servico%rowtype;
  v_cliente_id integer;
  v_pedido text;
  v_ordem integer := 0;
  v_total integer;
  v_os_ids integer[] := array[]::integer[];
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using errcode = '22023', message = 'Tenant e empresa sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para faturar nesta empresa.';
  end if;
  if jsonb_typeof(p_linhas) <> 'array' then
    raise exception using errcode = '22023', message = 'As linhas de servico precisam ser uma lista.';
  end if;
  select count(*) into v_total from jsonb_array_elements(p_linhas);
  if v_total = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos uma linha de servico.';
  end if;

  select po.* into v_perfil
  from f.perfil_operacao po
  where po.id = p_perfil_operacao_id and po.tenant_id = p_tenant_id and (po.empresa_id = p_empresa_id or po.empresa_id is null);
  if not found then
    raise exception using errcode = '22023', message = 'Perfil de servico nao encontrado nesta empresa.';
  end if;
  if v_perfil.modelo <> 'NFSE' then
    raise exception using errcode = '22023', message = format('O perfil %s e de NF-e, nao de servico.', v_perfil.codigo);
  end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' then
    raise exception using errcode = '22023', message = format('Perfil %s bloqueado: %s', v_perfil.codigo, coalesce(v_perfil.justificativa_faixa, 'aguarda o contador.'));
  end if;

  for v_linha in
    select x.os_id, x.descricao_servico, x.valor_servico
    from jsonb_to_recordset(p_linhas) as x(os_id integer, descricao_servico text, valor_servico numeric)
  loop
    v_ordem := v_ordem + 1;
    if v_linha.os_id is null then
      raise exception using errcode = '22023', message = format('Linha %s: informe a OS.', v_ordem);
    end if;
    perform pg_advisory_xact_lock(hashtextextended(format('faturamento-parcial:%s:%s:%s', p_tenant_id, p_empresa_id, v_linha.os_id), 0));
    select os.* into v_os
    from public.ordens_servico os
    where os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id and os.id = v_linha.os_id and os.tipo_documento = 'OS'
    for share;
    if not found then
      raise exception using errcode = 'P0002', message = format('Linha %s: OS %s nao encontrada nesta empresa.', v_ordem, v_linha.os_id);
    end if;
    if lower(coalesce(v_os.status_fluxo, v_os.status::text, '')) = 'cancelada' then
      raise exception using errcode = '22023', message = format('Linha %s: a OS %s esta cancelada.', v_ordem, coalesce(v_os.numero_os, v_os.id::text));
    end if;
    if v_os.cliente_id is null then
      raise exception using errcode = '23502', message = format('Linha %s: a OS %s nao tem cliente.', v_ordem, coalesce(v_os.numero_os, v_os.id::text));
    end if;
    if v_cliente_id is null then
      v_cliente_id := v_os.cliente_id;
      v_pedido := v_os.pedido_compra;
    elsif v_cliente_id <> v_os.cliente_id then
      raise exception using errcode = '22023', message = format('Linha %s: a OS %s e de outro tomador; uma NFS-e tem um unico tomador.', v_ordem, coalesce(v_os.numero_os, v_os.id::text));
    end if;
    if nullif(btrim(coalesce(v_linha.descricao_servico, '')), '') is null then
      raise exception using errcode = '22023', message = format('Linha %s: descricao do servico obrigatoria.', v_ordem);
    end if;
    if v_linha.valor_servico is null or v_linha.valor_servico <= 0 then
      raise exception using errcode = '22023', message = format('Linha %s: valor do servico deve ser maior que zero.', v_ordem);
    end if;
    if v_ordem = 1 then
      insert into f.solicitacao_faturamento (id, tenant_id, empresa_id, cliente_id, status, pedido_cliente, observacao, natureza_operacao, perfil_operacao_id)
      values (v_solicitacao_id, p_tenant_id, p_empresa_id, v_cliente_id, 'RASCUNHO', v_pedido,
              format('NFS-e de servico da OS %s.', coalesce(v_os.numero_os, v_os.id::text)), 'PRESTACAO_SERVICO', v_perfil.id);
    end if;
    insert into f.solicitacao_item (
      solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, item_id, descricao, quantidade, unidade,
      valor_unitario, ordem, modelo, descricao_servico, valor_servico, perfil_operacao_id
    ) values (
      v_solicitacao_id, p_tenant_id, p_empresa_id, 'OS', v_linha.os_id::text, null, btrim(v_linha.descricao_servico), 1, 'UN',
      round(v_linha.valor_servico, 2), v_ordem, 'NFSE', btrim(v_linha.descricao_servico), round(v_linha.valor_servico, 2), v_perfil.id
    );
    v_os_ids := v_os_ids || v_linha.os_id;
  end loop;
  return v_solicitacao_id;
end;
$$;
revoke all on function f.fn_solicitacao_faturamento_criar_os_servico(uuid, uuid, uuid, jsonb) from public;
grant execute on function f.fn_solicitacao_faturamento_criar_os_servico(uuid, uuid, uuid, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Conferencia de homologacao (fixture + cadastro), com bloqueios nomeados
-- ---------------------------------------------------------------------------
create or replace function f.fn_os_nfse_conferir_homologacao(p_solicitacao_id uuid, p_operacao jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_perfil f.perfil_operacao%rowtype;
  v_fx f.tributacao_provisoria_nfse_homologacao%rowtype;
  v_cliente public.clientes%rowtype;
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_item record;
  v_os public.ordens_servico%rowtype;
  v_pend jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
  v_rota_cliente text;
  v_rota_perfil text := '/faturamento/perfis';
  v_documento text;
  v_municipio text;
  v_competencia date;
  v_iss_retido boolean;
  v_pcc boolean;
  v_irrf boolean;
  v_inss boolean;
  v_iss_override boolean;
  v_pcc_override boolean;
  v_irrf_override boolean;
  v_inss_override boolean;
  v_justificativa text;
  v_bruto numeric(15,2) := 0;
  v_valor_iss numeric(15,2) := 0;
  v_v_irrf numeric(15,2) := 0;
  v_v_pcc numeric(15,2) := 0;
  v_v_inss numeric(15,2) := 0;
  v_liquido numeric(15,2);
  v_retencoes jsonb := '[]'::jsonb;
  v_parcelas jsonb;
  v_pag_forma text;
  v_pag_indicador smallint;
  v_saldo record;
  v_reserva_propria numeric(15,2);
  v_reserva_substituida numeric(15,2);
  v_os_total record;
  v_linhas_desc jsonb := '[]'::jsonb;
  v_os_numeros text[] := array[]::text[];
  v_discriminacao text;
  v_texto_retencao text;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_emissao_status text;
  v_linhas integer := 0;
  v_consumidor_final smallint;
  v_dias_pagamento integer;
  v_pedido text;
  v_pedido_item text;
  v_observacao text;
  v_tem_federal boolean;
begin
  select * into v_sf from f.solicitacao_faturamento where id = p_solicitacao_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NFS-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s nao pode ser conferida.', v_sf.status);
  end if;
  select e.status into v_emissao_status
  from f.documento_fiscal_emissao e
  where e.tenant_id = v_sf.tenant_id and e.empresa_id = v_sf.empresa_id and e.solicitacao_id = v_sf.id
  order by e.created_at desc limit 1;
  if v_emissao_status is not null and v_emissao_status not in ('RASCUNHO') then
    raise exception using errcode = '55000', message = format('A NFS-e desta solicitacao ja esta em %s; a conferencia nao pode mais ser alterada. Para refazer, descarte e crie outra.', v_emissao_status);
  end if;
  if exists (select 1 from f.solicitacao_item si where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id and si.modelo <> 'NFSE') then
    raise exception using errcode = '22023', message = 'Esta conferencia e exclusiva de linhas de servico (NFS-e).';
  end if;

  v_rota_cliente := '/clientes/cadastro-fiscal?cliente_id=' || coalesce(v_sf.cliente_id::text, '');

  -- Perfil de servico escolhido e fixture provisoria correspondente.
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = coalesce(nullif(p_operacao->>'perfil_operacao_id', '')::uuid, v_sf.perfil_operacao_id)
    and po.tenant_id = v_sf.tenant_id and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null);
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','campo','perfil_operacao_id','mensagem','Escolha o perfil de servico da NFS-e.','rota',v_rota_perfil));
  else
    if v_perfil.modelo <> 'NFSE' then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','modelo','mensagem',format('Perfil %s nao e de servico.', v_perfil.codigo),'rota',v_rota_perfil));
    end if;
    if v_perfil.faixa_automacao = 'BLOQUEADO' then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','faixa_automacao','mensagem',format('Perfil %s bloqueado: %s', v_perfil.codigo, coalesce(v_perfil.justificativa_faixa, 'aguarda o contador.')),'rota',v_rota_perfil));
    end if;
    if v_perfil.vigencia_inicio > current_date or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','vigencia','mensagem',format('Perfil %s fora da vigencia.', v_perfil.codigo),'rota',v_rota_perfil));
    end if;
    select t.* into v_fx from f.tributacao_provisoria_nfse_homologacao t
    where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.item_servico = v_perfil.item_servico and t.ativo;
    if not found then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','item_servico','mensagem',format('Sem fixture provisoria de homologacao para o item %s.', coalesce(v_perfil.item_servico, '?')),'rota',v_rota_perfil));
    elsif v_fx.aliquota_iss is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','aliquota_iss','mensagem',format('Fixture do item %s sem aliquota de ISS: %s', v_fx.item_servico, v_fx.pendencia_contador),'rota',v_rota_perfil));
    end if;
  end if;

  -- Emitente (prestador).
  select e.* into v_empresa from c.empresa e where e.tenant_id = v_sf.tenant_id and e.id = v_sf.empresa_id and e.deleted_at is null and e.ativo;
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','empresa','mensagem','Empresa ativa nao encontrada.','rota','/configuracoes'));
  else
    select ef.* into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
    select ee.* into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','cnpj','mensagem','CNPJ do prestador invalido.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.serie_dps is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','serie_dps','mensagem','Serie da DPS nao configurada no cadastro fiscal da empresa.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.codigo_opcao_simples_nacional is null or v_fiscal.regime_especial_tributacao is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_opcao_simples_nacional','mensagem','Opcao pelo Simples e regime especial nao informados no cadastro fiscal da empresa.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or nullif(btrim(v_fiscal.inscricao_municipal), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','inscricao_municipal','mensagem','Inscricao municipal do prestador vazia; a DPS sai sem IM.'));
    end if;
    if v_endereco.id is null or regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_municipio_ibge','mensagem','Codigo IBGE do endereco fiscal do prestador deve ter 7 digitos.','rota','/configuracoes'));
    end if;
  end if;

  -- Tomador.
  select c.* into v_cliente from public.clientes c where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id and c.ativo is true;
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_sf.cliente_id,'campo','cliente','mensagem','Tomador ativo nao encontrado nesta empresa.','rota',v_rota_cliente));
  else
    v_documento := regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g');
    if not ((length(v_documento) = 14 and public.cnpj_valido(v_documento)) or (length(v_documento) = 11 and public.cpf_valido(v_documento))) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','CNPJ/CPF do tomador invalido.','rota',v_rota_cliente));
    end if;
    if exists (
      select 1 from public.empresas e
      where e.tenant_id = v_sf.tenant_id
        and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') <> ''
        and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') = v_documento
    ) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','OS interna (tomador e uma empresa do grupo) nao emite NFS-e por este fluxo.'));
    end if;
    if nullif(btrim(v_cliente.razao_social), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','razao_social','mensagem','Razao social do tomador nao informada.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.logradouro), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','logradouro','mensagem','Logradouro do tomador nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.numero_endereco), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','numero_endereco','mensagem','Numero do endereco do tomador nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.bairro), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','bairro','mensagem','Bairro do tomador nao informado.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cep','mensagem','CEP do tomador deve ter 8 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','codigo_ibge_municipio','mensagem','Codigo IBGE do tomador deve ter 7 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') = '4209102'
       and nullif(btrim(v_cliente.inscricao_municipal), '') is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','inscricao_municipal','mensagem','Tomador de Joinville sem inscricao municipal.','rota',v_rota_cliente));
    end if;
    if nullif(btrim(coalesce(v_cliente.email_nfse, '')), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','email_nfse','mensagem','Tomador sem e-mail de NFS-e; a nota nao sera enviada por e-mail.','rota',v_rota_cliente));
    end if;
  end if;

  -- Municipio de prestacao e competencia.
  v_municipio := regexp_replace(coalesce(p_operacao->>'municipio_prestacao_ibge', ''), '[^0-9]', '', 'g');
  if v_municipio = '' and v_fx.item_servico is not null then
    v_municipio := case when v_fx.local_prestacao_regra = 'SEDE'
      then regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g')
      else regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') end;
  end if;
  if v_municipio !~ '^[0-9]{7}$' then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','municipio_prestacao_ibge','mensagem','Municipio de prestacao vazio ou invalido (7 digitos IBGE).'));
  end if;
  begin
    v_competencia := coalesce(nullif(btrim(coalesce(p_operacao->>'data_competencia', '')), '')::date, current_date);
  exception when others then
    v_competencia := null;
  end;
  if v_competencia is null then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Data de competencia invalida.'));
  elsif v_competencia > current_date then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Competencia no futuro nao e aceita.'));
  end if;

  -- Retencoes: override da tela (com justificativa) > cadastro do tomador > regra do perfil/fixture.
  v_justificativa := nullif(btrim(coalesce(p_operacao->>'retencao_justificativa', '')), '');
  v_iss_override := case when jsonb_typeof(p_operacao->'iss_retido') = 'boolean' then (p_operacao->>'iss_retido')::boolean end;
  v_pcc_override := case when jsonb_typeof(p_operacao->'retem_pcc') = 'boolean' then (p_operacao->>'retem_pcc')::boolean end;
  v_irrf_override := case when jsonb_typeof(p_operacao->'retem_irrf') = 'boolean' then (p_operacao->>'retem_irrf')::boolean end;
  v_inss_override := case when jsonb_typeof(p_operacao->'retem_inss') = 'boolean' then (p_operacao->>'retem_inss')::boolean end;
  if v_fx.item_servico is not null and v_cliente.id is not null then
    v_iss_retido := coalesce(v_iss_override, case v_fx.iss_retido_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.iss_retido end);
    v_pcc := coalesce(v_pcc_override, case v_fx.retencao_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end);
    v_irrf := coalesce(v_irrf_override, case v_fx.retencao_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end);
    v_inss := coalesce(v_inss_override, case v_fx.retencao_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end);
    if v_iss_retido is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','iss_retido','mensagem','ISS retido indefinido para este tomador: decida no cadastro fiscal do cliente ou aqui, com justificativa.','rota',v_rota_cliente));
    end if;
    if v_pcc is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_pcc','mensagem','Retencao de PIS/COFINS/CSLL indefinida para este tomador.','rota',v_rota_cliente));
    end if;
    if v_irrf is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_irrf','mensagem','Retencao de IRRF indefinida para este tomador.','rota',v_rota_cliente));
    end if;
    if v_inss is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_inss','mensagem','Retencao de INSS indefinida para este tomador.','rota',v_rota_cliente));
    end if;
    if ((v_iss_override is not null and v_iss_override is distinct from case v_fx.iss_retido_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.iss_retido end)
        or (v_pcc_override is not null and v_pcc_override is distinct from case v_fx.retencao_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end)
        or (v_irrf_override is not null and v_irrf_override is distinct from case v_fx.retencao_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end)
        or (v_inss_override is not null and v_inss_override is distinct from case v_fx.retencao_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end))
       and (v_justificativa is null or char_length(v_justificativa) < 15) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','retencao_justificativa','mensagem','Retencao diferente do cadastro do tomador exige justificativa (15 caracteres ou mais), gravada na observacao.'));
    end if;
  end if;

  -- Pagamento e parcelas (mesma normalizacao da NF-e).
  v_pag_forma := nullif(btrim(coalesce(p_operacao->>'pagamento_forma', '')), '');
  if v_pag_forma is null or v_pag_forma !~ '^(0[1-5]|1[0-9]|2[0-4]|9[019])$' then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_forma','mensagem','Forma de pagamento invalida ou nao confirmada.'));
  end if;
  begin
    v_pag_indicador := nullif(btrim(coalesce(p_operacao->>'pagamento_indicador', '')), '')::smallint;
  exception when others then v_pag_indicador := null; end;
  if v_pag_indicador is null or v_pag_indicador not in (0, 1) then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_indicador','mensagem','Indique a vista (0) ou a prazo (1).'));
  end if;
  begin
    v_parcelas := case when v_pag_indicador = 1 then f.fn_nfe_normalizar_parcelas(p_operacao->'pagamento_parcelas') else null end;
  exception when others then
    v_parcelas := null;
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_parcelas','mensagem',sqlerrm));
  end;

  -- Linhas: OS de cada linha, tomador unico, valor por OS contra o saldo.
  for v_item in
    select si.* from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
    order by si.ordem
  loop
    v_linhas := v_linhas + 1;
    if v_item.valor_servico is null or v_item.valor_servico <= 0 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_servico','mensagem',format('Linha %s: valor do servico deve ser maior que zero.', v_item.ordem)));
      continue;
    end if;
    if nullif(btrim(coalesce(v_item.descricao_servico, '')), '') is null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','descricao_servico','mensagem',format('Linha %s: descricao do servico obrigatoria.', v_item.ordem)));
    end if;
    select os.* into v_os from public.ordens_servico os
    where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id and os.tipo_documento = 'OS' and os.id::text = v_item.origem_id;
    if not found then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','origem_id','mensagem',format('Linha %s: OS %s nao encontrada.', v_item.ordem, v_item.origem_id)));
      continue;
    end if;
    if lower(coalesce(v_os.status_fluxo, v_os.status::text, '')) = 'cancelada' then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','status','mensagem',format('Linha %s: a OS %s esta cancelada.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id));
    end if;
    if v_os.cliente_id is distinct from v_sf.cliente_id then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','cliente_id','mensagem',format('Linha %s: a OS %s e de outro tomador.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id));
    end if;
    if lower(coalesce(v_os.status_fluxo, '')) = 'em_andamento' then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','status_fluxo','mensagem',format('OS %s ainda em andamento.', coalesce(v_os.numero_os, v_os.id::text))));
    end if;
    v_bruto := v_bruto + v_item.valor_servico;
    v_linhas_desc := v_linhas_desc || jsonb_build_object('descricao', coalesce(v_item.descricao_servico, v_fx.descricao_servico_padrao), 'os_numero', coalesce(v_os.numero_os, v_os.id::text));
    if not (coalesce(v_os.numero_os, v_os.id::text) = any(v_os_numeros)) then
      v_os_numeros := v_os_numeros || coalesce(v_os.numero_os, v_os.id::text);
    end if;
  end loop;
  if v_linhas = 0 then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','itens','mensagem','A solicitacao nao tem linhas.'));
  end if;

  for v_os_total in
    select si.origem_id::integer as os_id, round(sum(si.valor_servico), 2) as total
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id and si.origem_id ~ '^[0-9]+$'
    group by si.origem_id
  loop
    begin
      select * into v_saldo from f.fn_os_saldo_a_faturar(v_sf.tenant_id, v_sf.empresa_id, v_os_total.os_id);
    exception when others then
      v_saldo := null;
    end;
    if v_saldo is null then continue; end if;
    v_reserva_propria := case when v_sf.status <> 'CANCELADA' then v_os_total.total else 0 end;
    v_reserva_substituida := 0;
    if v_sf.substitui_solicitacao_id is not null then
      select coalesce(round(sum(si.valor_servico), 2), 0) into v_reserva_substituida
      from f.solicitacao_item si join f.solicitacao_faturamento s on s.id = si.solicitacao_id
      where si.solicitacao_id = v_sf.substitui_solicitacao_id and si.origem_id = v_os_total.os_id::text and s.status <> 'CANCELADA'
        and not exists (
          select 1 from f.documento_fiscal_emissao e join f.documento_fiscal d on d.id = e.documento_fiscal_id
          where e.solicitacao_id = s.id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA'
        );
      -- Em producao a nota substituida ja esta em "faturado"; conta a favor tambem.
      select v_reserva_substituida + coalesce(sum(d.valor_total), 0) into v_reserva_substituida
      from f.documento_fiscal d
      where d.id = v_sf.substitui_documento_fiscal_id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA' and d.os_id_import = v_os_total.os_id;
    end if;
    if v_saldo.valor_pedido > 0 and v_os_total.total > v_saldo.saldo + v_reserva_propria + v_reserva_substituida + 0.005 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os_total.os_id,'campo','valor_servico','mensagem',format(
        'OS %s: total das linhas R$ %s acima do saldo da OS R$ %s.', v_os_total.os_id,
        to_char(v_os_total.total, 'FM999G999G990D00'), to_char(v_saldo.saldo + v_reserva_propria + v_reserva_substituida, 'FM999G999G990D00')),'rota','/os/' || v_os_total.os_id));
    end if;
  end loop;

  v_pedido := coalesce(nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), ''), v_sf.pedido_cliente);
  v_pedido_item := nullif(btrim(coalesce(p_operacao->>'pedido_item', '')), '');
  v_observacao := nullif(btrim(coalesce(p_operacao->>'observacao', '')), '');
  if v_pedido is null then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','pedido_cliente','mensagem','Sem pedido de compra do tomador.'));
  end if;

  if jsonb_array_length(v_pend) > 0 then
    update f.solicitacao_faturamento
    set emitente_snapshot = null, destinatario_snapshot = null, operacao_snapshot = null, snapshot_cadastro_em = null,
        revisao_fiscal_confirmada_em = null, revisao_fiscal_confirmada_por = null, updated_at = now()
    where id = v_sf.id;
    return jsonb_build_object('ok', false, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente,
                              'pendencias', v_pend, 'avisos', v_avisos);
  end if;

  -- Valores.
  v_valor_iss := round(v_bruto * v_fx.aliquota_iss / 100, 2);
  v_v_irrf := case when v_irrf then round(v_bruto * coalesce(v_fx.aliquota_irrf, 0) / 100, 2) else 0 end;
  v_v_pcc := case when v_pcc then round(v_bruto * coalesce(v_fx.aliquota_pcc, 0) / 100, 2) else 0 end;
  v_v_inss := case when v_inss then round(v_bruto * coalesce(v_fx.aliquota_inss, 0) / 100, 2) else 0 end;
  v_liquido := v_bruto - (case when v_iss_retido then v_valor_iss else 0 end) - v_v_irrf - v_v_pcc - v_v_inss;
  if v_iss_retido then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'ISS', 'base', v_bruto, 'aliquota', v_fx.aliquota_iss, 'valor', v_valor_iss); end if;
  if v_irrf then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'IRRF', 'base', v_bruto, 'aliquota', v_fx.aliquota_irrf, 'valor', v_v_irrf); end if;
  if v_pcc then
    v_retencoes := v_retencoes
      || jsonb_build_object('tributo', 'PIS', 'base', v_bruto, 'aliquota', 0.65, 'valor', round(v_bruto * 0.65 / 100, 2))
      || jsonb_build_object('tributo', 'COFINS', 'base', v_bruto, 'aliquota', 3.00, 'valor', round(v_bruto * 3.00 / 100, 2))
      || jsonb_build_object('tributo', 'CSLL', 'base', v_bruto, 'aliquota', 1.00, 'valor', v_v_pcc - round(v_bruto * 0.65 / 100, 2) - round(v_bruto * 3.00 / 100, 2));
  end if;
  if v_inss then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'INSS', 'base', v_bruto, 'aliquota', v_fx.aliquota_inss, 'valor', v_v_inss); end if;
  v_tem_federal := v_irrf or v_pcc or v_inss;
  v_texto_retencao := case
    when v_tem_federal then
      'RETENCOES FEDERAIS: ' || concat_ws('; ',
        case when v_irrf then 'IRRF ' || replace(to_char(v_fx.aliquota_irrf, 'FM990D00'), '.', ',') || '%' end,
        case when v_pcc then 'PIS/COFINS/CSLL ' || replace(to_char(v_fx.aliquota_pcc, 'FM990D00'), '.', ',') || '% (PIS 0,65%; COFINS 3,00%; CSLL 1,00%)' end,
        case when v_inss then 'INSS ' || replace(to_char(v_fx.aliquota_inss, 'FM990D00'), '.', ',') || '%' end) || '.'
    else coalesce(v_perfil.texto_complementar, v_fx.texto_sem_retencao) end;
  v_consumidor_final := coalesce(v_perfil.consumidor_final, v_fx.consumidor_final, 0);
  v_discriminacao := f.fn_nfse_discriminacao(v_linhas_desc, v_pedido, v_pedido_item, v_parcelas, current_date, v_iss_retido, v_texto_retencao,
    concat_ws(' ', v_observacao, case when v_justificativa is not null then 'RETENCAO AJUSTADA: ' || v_justificativa end));

  update f.solicitacao_item si
  set codigo_tributacao_nacional = v_fx.codigo_tributacao_nacional,
      codigo_tributacao_municipal = v_fx.codigo_tributacao_municipal,
      codigo_nbs = v_fx.codigo_nbs,
      tributacao_iss = v_fx.tributacao_iss,
      aliquota_iss = v_fx.aliquota_iss,
      iss_retido = v_iss_retido,
      aliquota_irrf = case when v_irrf then v_fx.aliquota_irrf end,
      aliquota_pcc = case when v_pcc then v_fx.aliquota_pcc end,
      aliquota_inss = case when v_inss then v_fx.aliquota_inss end,
      local_prestacao_ibge = v_municipio,
      cst_pis = v_fx.cst_pis_cofins, aliquota_pis = v_fx.aliquota_pis,
      cst_cofins = v_fx.cst_pis_cofins, aliquota_cofins = v_fx.aliquota_cofins,
      cst_ibs_cbs = v_fx.cst_ibs_cbs, cclass_trib = v_fx.cclass_trib,
      ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', v_fx.ibs_uf_aliquota, 'ibs_mun_aliquota', v_fx.ibs_mun_aliquota, 'cbs_aliquota', v_fx.cbs_aliquota),
      perfil_operacao_id = v_perfil.id,
      perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id,
      tributacao_fonte = 'FIXTURE_HOMOLOGACAO',
      descricao = coalesce(si.descricao_servico, si.descricao)
  where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id;

  update f.solicitacao_faturamento sf
  set perfil_operacao_id = v_perfil.id,
      natureza_operacao = 'PRESTACAO_SERVICO',
      consumidor_final = v_consumidor_final,
      municipio_prestacao_ibge = v_municipio,
      data_competencia = v_competencia,
      iss_retido = v_iss_retido, retem_pcc = v_pcc, retem_irrf = v_irrf, retem_inss = v_inss,
      retencao_justificativa = v_justificativa,
      pagamento_forma = v_pag_forma, pagamento_indicador = v_pag_indicador,
      pagamento_descricao = nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''),
      pagamento_parcelas = v_parcelas,
      pedido_cliente = v_pedido, pedido_item = v_pedido_item,
      observacao = coalesce(v_observacao, sf.observacao),
      modalidade_frete = null, transportador_dados = null, volumes_dados = null,
      destino_uf_confirmada = upper(v_cliente.uf), destino_confirmado_em = now(), destino_confirmado_por = v_usuario_id,
      perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id,
      revisao_fiscal_confirmada_em = now(), revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = jsonb_build_object(
        'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
        'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
        'telefone', v_empresa.telefone, 'email', v_empresa.email,
        'inscricao_municipal', nullif(btrim(coalesce(v_fiscal.inscricao_municipal, '')), ''),
        'codigo_opcao_simples_nacional', v_fiscal.codigo_opcao_simples_nacional,
        'regime_especial_tributacao', v_fiscal.regime_especial_tributacao,
        'serie_dps', v_fiscal.serie_dps,
        'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero, 'complemento', v_endereco.complemento,
        'bairro', v_endereco.bairro, 'cidade', v_endereco.cidade, 'uf', upper(v_endereco.uf::text),
        'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'),
        'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')
      ),
      destinatario_snapshot = jsonb_build_object(
        'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social,
        'inscricao_municipal', nullif(btrim(coalesce(v_cliente.inscricao_municipal, '')), ''),
        'email', coalesce(nullif(btrim(coalesce(v_cliente.email_nfse, '')), ''), nullif(btrim(coalesce(v_cliente.email_financeiro, '')), '')),
        'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro, 'numero_endereco', v_cliente.numero_endereco,
        'complemento', v_cliente.complemento, 'bairro', v_cliente.bairro, 'cidade', v_cliente.cidade, 'uf', upper(v_cliente.uf),
        'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'),
        'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')
      ),
      operacao_snapshot = jsonb_build_object(
        'natureza_operacao', 'PRESTACAO_SERVICO',
        'modelo', 'NFSE',
        'tributacao_fonte', 'FIXTURE_HOMOLOGACAO',
        'consumidor_final', v_consumidor_final,
        'servico', jsonb_build_object(
          'perfil_operacao_id', v_perfil.id, 'perfil_codigo', v_perfil.codigo, 'item_servico', v_fx.item_servico,
          'codigo_tributacao_nacional', v_fx.codigo_tributacao_nacional,
          'codigo_tributacao_municipal', v_fx.codigo_tributacao_municipal,
          'codigo_nbs', v_fx.codigo_nbs,
          'municipio_prestacao_ibge', v_municipio, 'data_competencia', v_competencia,
          'tributacao_iss', v_fx.tributacao_iss, 'aliquota_iss', v_fx.aliquota_iss, 'iss_retido', v_iss_retido,
          'retem_pcc', v_pcc, 'retem_irrf', v_irrf, 'retem_inss', v_inss,
          'valor_bruto', v_bruto, 'valor_iss', v_valor_iss, 'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss,
          'valor_liquido', v_liquido, 'retencoes', v_retencoes,
          'cst_pis_cofins', v_fx.cst_pis_cofins, 'aliquota_pis', v_fx.aliquota_pis, 'aliquota_cofins', v_fx.aliquota_cofins,
          'cst_ibs_cbs', v_fx.cst_ibs_cbs, 'cclass_trib', v_fx.cclass_trib,
          'ibs_uf_aliquota', v_fx.ibs_uf_aliquota, 'ibs_mun_aliquota', v_fx.ibs_mun_aliquota, 'cbs_aliquota', v_fx.cbs_aliquota,
          'descricao_servico', v_discriminacao, 'texto_retencao', v_texto_retencao,
          'os_numeros', to_jsonb(v_os_numeros)
        ),
        'pedido', jsonb_build_object('pedido_cliente', v_pedido, 'pedido_item', v_pedido_item),
        'substituicao', case when v_sf.substitui_documento_fiscal_id is null then null else jsonb_build_object(
          'documento_fiscal_id', v_sf.substitui_documento_fiscal_id, 'solicitacao_id', v_sf.substitui_solicitacao_id,
          'codigo', v_sf.substituicao_codigo, 'motivo', v_sf.substituicao_motivo,
          'chave', (select e.chave_nfse from f.documento_fiscal_emissao e where e.documento_fiscal_id = v_sf.substitui_documento_fiscal_id limit 1)) end,
        'pagamento', jsonb_build_object('forma', v_pag_forma, 'indicador', v_pag_indicador,
          'descricao', nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''), 'parcelas', v_parcelas, 'fatura_numero', null)
      ),
      snapshot_cadastro_em = now(), updated_at = now()
  where sf.id = v_sf.id;

  -- Pedido digitado na tela grava na OS de cada linha (como na NF-e).
  if nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is not null then
    update public.ordens_servico os set pedido_compra = btrim(p_operacao->>'pedido_cliente'), atualizado_em = now()
    where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id
      and os.id::text in (select si.origem_id from f.solicitacao_item si where si.solicitacao_id = v_sf.id)
      and os.pedido_compra is distinct from btrim(p_operacao->>'pedido_cliente');
  end if;

  return jsonb_build_object(
    'ok', true, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente,
    'pendencias', '[]'::jsonb, 'avisos', v_avisos,
    'previa', jsonb_build_object(
      'item_servico', v_fx.item_servico, 'codigo_tributacao_nacional', v_fx.codigo_tributacao_nacional, 'codigo_nbs', v_fx.codigo_nbs,
      'municipio_prestacao_ibge', v_municipio, 'data_competencia', v_competencia,
      'valor_bruto', v_bruto, 'aliquota_iss', v_fx.aliquota_iss, 'valor_iss', v_valor_iss, 'iss_retido', v_iss_retido,
      'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss, 'valor_liquido', v_liquido,
      'retencoes', v_retencoes, 'parcelas', v_parcelas, 'descricao_servico', v_discriminacao,
      'tributacao_fonte', 'FIXTURE_HOMOLOGACAO'
    )
  );
end;
$$;
revoke all on function f.fn_os_nfse_conferir_homologacao(uuid, jsonb) from public;
grant execute on function f.fn_os_nfse_conferir_homologacao(uuid, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Documento RASCUNHO + emissao + DPS numerada, na mesma transacao
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_preparar_documento_solicitacao(p_solicitacao_id uuid)
returns table (documento_fiscal_id uuid, solicitacao_id uuid, referencia_externa text, status text, criado boolean, dps_serie smallint, dps_numero bigint)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_documento_id uuid := gen_random_uuid();
  v_referencia text;
  v_serv jsonb;
  v_bruto numeric(15,2);
  v_liquido numeric(15,2);
  v_os_id integer;
  v_dps record;
begin
  select * into v_sf from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para emitir esta solicitacao.';
  end if;

  v_referencia := 'NFSH-' || v_sf.id;
  perform pg_advisory_xact_lock(hashtextextended(v_referencia, 0));

  return query
  select dfe.documento_fiscal_id, dfe.solicitacao_id, dfe.referencia_externa, dfe.status, false, dfe.dps_serie, dfe.dps_numero
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id and dfe.empresa_id = v_sf.empresa_id and dfe.solicitacao_id = v_sf.id;
  if found then return; end if;

  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Solicitacao nao esta disponivel para emissao.';
  end if;
  if v_sf.snapshot_cadastro_em is null
     or jsonb_typeof(v_sf.emitente_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.destinatario_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.operacao_snapshot->'servico') is distinct from 'object' then
    raise exception using errcode = '22023', message = 'Conferencia da NFS-e ainda nao foi salva nesta solicitacao.';
  end if;
  if exists (select 1 from f.solicitacao_item si where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id and si.modelo <> 'NFSE') then
    raise exception using errcode = '22023', message = 'Solicitacao com linha de mercadoria; use o pipeline de NF-e.';
  end if;
  v_serv := v_sf.operacao_snapshot->'servico';
  v_bruto := round((v_serv->>'valor_bruto')::numeric, 2);
  v_liquido := round((v_serv->>'valor_liquido')::numeric, 2);
  if v_bruto is null or v_bruto <= 0 or v_liquido is null or v_liquido <= 0 then
    raise exception using errcode = '22023', message = 'Valores da NFS-e invalidos na conferencia.';
  end if;
  select min(si.origem_id::integer) into v_os_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id and si.origem_tipo = 'OS' and si.origem_id ~ '^[0-9]+$';

  insert into f.documento_fiscal (
    id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date, competencia_date,
    valor_total, valor_servicos, operacao, natureza, cliente_id, os_id_import, nfse_status, origem,
    nfse_municipio_codigo, servico_discriminacao
  ) values (
    v_documento_id, v_sf.tenant_id, v_sf.empresa_id, 'PENDENTE:' || v_referencia, 'NFSE', current_date,
    date_trunc('month', coalesce((v_serv->>'data_competencia')::date, current_date))::date,
    v_liquido, v_bruto, 'SAIDA', 'SERVICO', v_sf.cliente_id, v_os_id, 'RASCUNHO', 'EMITIDO',
    v_serv->>'municipio_prestacao_ibge', v_serv->>'descricao_servico'
  );

  insert into f.documento_fiscal_item (
    tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo, codigo, codigo_servico, descricao,
    quantidade, unidade, valor_unitario, valor_total, item_id, cst_pis, cst_cofins, cst_ibs_cbs, cclass_trib, ibs_cbs_json
  )
  select si.tenant_id, si.empresa_id, v_documento_id, si.ordem, 'SERVICO', si.codigo_tributacao_nacional, si.codigo_tributacao_nacional,
         coalesce(si.descricao_servico, si.descricao), 1, 'UN', si.valor_servico, si.valor_servico, null,
         si.cst_pis, si.cst_cofins, si.cst_ibs_cbs, si.cclass_trib, si.ibs_cbs_json
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
  order by si.ordem, si.id;

  -- Numero da DPS dentro da transacao do rascunho: nunca reutilizado.
  select * into v_dps from f.fn_proximo_numero_dps(v_sf.empresa_id);

  insert into f.documento_fiscal_emissao (
    documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status, modelo,
    dps_serie, dps_numero, municipio_prestacao_ibge, iss_retido, valor_iss, valor_deducoes, retencoes, valor_liquido,
    chave_nfse_substituida, substituicao_codigo, substituicao_motivo
  ) values (
    v_documento_id, v_sf.id, v_sf.tenant_id, v_sf.empresa_id, v_referencia, 'HOMOLOGACAO', 'RASCUNHO', 'NFSE',
    v_dps.serie, v_dps.numero, v_serv->>'municipio_prestacao_ibge', (v_serv->>'iss_retido')::boolean,
    round((v_serv->>'valor_iss')::numeric, 2), 0, coalesce(v_serv->'retencoes', '[]'::jsonb), v_liquido,
    v_sf.operacao_snapshot->'substituicao'->>'chave', v_sf.substituicao_codigo, v_sf.substituicao_motivo
  );
  insert into f.dps_numero_log (tenant_id, empresa_id, serie, numero, documento_fiscal_id, referencia_externa, resultado, mensagem)
  values (v_sf.tenant_id, v_sf.empresa_id, v_dps.serie, v_dps.numero, v_documento_id, v_referencia, 'RESERVADO', 'Reservado na preparacao do rascunho.');

  update f.solicitacao_faturamento set status = 'APROVADA', updated_at = now() where id = v_sf.id;
  return query select v_documento_id, v_sf.id, v_referencia, 'RASCUNHO'::text, true, v_dps.serie, v_dps.numero;
end;
$$;
revoke all on function f.fn_nfse_preparar_documento_solicitacao(uuid) from public;
grant execute on function f.fn_nfse_preparar_documento_solicitacao(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Claim durável de homologacao (retry troca so o numero da DPS)
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_homologacao_claimar(p_documento_fiscal_id uuid, p_payload jsonb, p_reconciliacao_confirmada boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_tinha_claim boolean;
  v_payload_congelado jsonb;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o envio de homologacao.';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'O payload da NFS-e deve ser um objeto JSON.';
  end if;
  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.ambiente = 'HOMOLOGACAO' and dfe.modelo = 'NFSE'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de NFS-e em homologacao nao encontrada.';
  end if;
  if v_emissao.status in ('AUTORIZADA', 'PROCESSANDO', 'CANCELADA') then
    return jsonb_build_object('deve_enviar', false, 'aguardar', v_emissao.status = 'PROCESSANDO',
      'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
  end if;
  v_tinha_claim := v_emissao.status = 'ENVIANDO' or v_emissao.tentativa_count > 0 or v_emissao.payload_enviado is not null or v_emissao.enviado_em is not null;
  if v_emissao.status = 'ENVIANDO' and v_emissao.ultima_tentativa_em >= now() - interval '2 minutes' then
    return jsonb_build_object('deve_enviar', false, 'aguardar', true,
      'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
  end if;
  if v_tinha_claim and not coalesce(p_reconciliacao_confirmada, false) then
    raise exception using errcode = '55000', message = 'A referencia de homologacao ja possui tentativa; consulte a Focus antes de qualquer novo POST.';
  end if;
  if (p_payload->>'numero_dps')::bigint is distinct from v_emissao.dps_numero
     or (p_payload->>'serie_dps')::smallint is distinct from v_emissao.dps_serie then
    raise exception using errcode = '22023', message = 'O payload nao traz a serie/numero de DPS reservados para esta emissao.';
  end if;
  if v_emissao.status in ('REJEITADA', 'ERRO') then
    -- DPS rejeitada fica queimada; o retry leva o numero novo (fn_nfse_renumerar_dps) e, fora dele, o mesmo payload.
    v_payload_congelado := p_payload;
    if v_emissao.payload_enviado is not null
       and (v_emissao.payload_enviado - 'numero_dps' - 'data_emissao') is distinct from (p_payload - 'numero_dps' - 'data_emissao') then
      raise exception using errcode = '22023', message = 'O retry da NFS-e diverge do payload congelado (so numero_dps e data_emissao podem mudar).';
    end if;
  else
    if v_emissao.payload_enviado is not null and v_emissao.payload_enviado is distinct from p_payload then
      raise exception using errcode = '22023', message = 'O retry de homologacao diverge do payload congelado no primeiro claim.';
    end if;
    v_payload_congelado := coalesce(v_emissao.payload_enviado, p_payload);
  end if;
  if v_emissao.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'ENVIANDO') then
    raise exception using errcode = '55000', message = format('Status %s nao aceita claim de homologacao.', v_emissao.status);
  end if;
  update f.documento_fiscal_emissao dfe
  set status = 'ENVIANDO', payload_enviado = v_payload_congelado, tentativa_count = dfe.tentativa_count + 1,
      ultima_tentativa_em = now(), enviado_em = coalesce(dfe.enviado_em, now()), codigo_status = null, mensagem = null, updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id and dfe.empresa_id = v_emissao.empresa_id and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;
  insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa)
  values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'ENVIO', 'ENVIANDO',
          jsonb_build_object('claim_duravel', true, 'ambiente', 'HOMOLOGACAO', 'modelo', 'NFSE', 'tentativa', v_emissao.tentativa_count,
                             'dps_serie', v_emissao.dps_serie, 'dps_numero', v_emissao.dps_numero,
                             'reconciliacao_previa', coalesce(p_reconciliacao_confirmada, false)),
          v_emissao.referencia_externa);
  return jsonb_build_object('deve_enviar', true, 'aguardar', false,
    'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
end;
$$;
revoke all on function f.fn_nfse_homologacao_claimar(uuid, jsonb, boolean) from public;
grant execute on function f.fn_nfse_homologacao_claimar(uuid, jsonb, boolean) to service_role;

create or replace function f.fn_nfse_renumerar_dps(p_documento_fiscal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_dps record;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal renumera a DPS.';
  end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE' for update;
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  if v_emissao.status not in ('REJEITADA', 'ERRO') then
    return jsonb_build_object('dps_serie', v_emissao.dps_serie, 'dps_numero', v_emissao.dps_numero, 'renumerada', false);
  end if;
  update f.dps_numero_log set resultado = case when resultado = 'RESERVADO' then 'REJEITADO' else resultado end,
         mensagem = coalesce(mensagem, 'DPS queimada por rejeicao.'), updated_at = now()
  where documento_fiscal_id = v_emissao.documento_fiscal_id and serie = v_emissao.dps_serie and numero = v_emissao.dps_numero;
  select * into v_dps from f.fn_proximo_numero_dps(v_emissao.empresa_id);
  update f.documento_fiscal_emissao set dps_serie = v_dps.serie, dps_numero = v_dps.numero, updated_at = now()
  where documento_fiscal_id = v_emissao.documento_fiscal_id;
  insert into f.dps_numero_log (tenant_id, empresa_id, serie, numero, documento_fiscal_id, referencia_externa, resultado, mensagem)
  values (v_emissao.tenant_id, v_emissao.empresa_id, v_dps.serie, v_dps.numero, v_emissao.documento_fiscal_id, v_emissao.referencia_externa, 'RESERVADO',
          format('Retry apos %s da DPS %s/%s.', v_emissao.status, v_emissao.dps_serie, v_emissao.dps_numero));
  return jsonb_build_object('dps_serie', v_dps.serie, 'dps_numero', v_dps.numero, 'renumerada', true);
end;
$$;
revoke all on function f.fn_nfse_renumerar_dps(uuid) from public;
grant execute on function f.fn_nfse_renumerar_dps(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Titulo liquido (producao)
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_titulo_liquido_sincronizar(p_documento_fiscal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_df f.documento_fiscal%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_titulo_id uuid;
  v_parcelas jsonb;
  v_p jsonb;
  v_n integer := 0;
  v_total integer;
  v_soma numeric(15,2) := 0;
  v_valor numeric(15,2);
  v_ret jsonb;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal sincroniza o titulo.';
  end if;
  select * into v_df from f.documento_fiscal where id = p_documento_fiscal_id and deleted_at is null;
  if not found or v_df.nfse_status <> 'EMITIDA' then
    raise exception using errcode = '22023', message = 'Titulo liquido exige NFS-e EMITIDA.';
  end if;
  select * into v_emissao from f.documento_fiscal_emissao where documento_fiscal_id = v_df.id;
  select * into v_sf from f.solicitacao_faturamento where id = v_emissao.solicitacao_id;
  select t.id into v_titulo_id from f.titulo t
  where t.tenant_id = v_df.tenant_id and t.empresa_id = v_df.empresa_id and t.tipo = 'AR' and t.documento_fiscal_id = v_df.id and t.deleted_at is null
  limit 1;
  if v_titulo_id is null then
    v_titulo_id := f.fn_upsert_ar_from_documento_fiscal_v2(v_df.id, null);
  end if;
  if v_titulo_id is null then
    raise exception using errcode = '22023', message = 'Nao foi possivel gerar o titulo a receber da NFS-e.';
  end if;
  if exists (
    select 1 from f.titulo_parcela tp join f.pagamento_item pi on pi.titulo_parcela_id = tp.id and pi.deleted_at is null
    where tp.titulo_id = v_titulo_id and tp.deleted_at is null
  ) then
    raise exception using errcode = '55000', message = 'Titulo ja possui recebimentos; parcelas nao podem ser refeitas.';
  end if;

  -- Parcelas sobre o liquido, a partir da data de emissao.
  update f.titulo_parcela set deleted_at = now(), updated_at = now() where titulo_id = v_titulo_id and deleted_at is null;
  v_parcelas := coalesce(v_sf.pagamento_parcelas, jsonb_build_array(jsonb_build_object('numero', '001', 'dias', 15, 'valor', null)));
  select count(*) into v_total from jsonb_array_elements(v_parcelas);
  for v_p in select * from jsonb_array_elements(v_parcelas) loop
    v_n := v_n + 1;
    v_valor := case
      when v_n = v_total then round(v_df.valor_total - v_soma, 2)
      else round(coalesce(nullif(v_p->>'valor', '')::numeric, v_df.valor_total), 2) end;
    if v_valor <= 0 then
      raise exception using errcode = '22023', message = format('Parcela %s da NFS-e com valor invalido.', v_n);
    end if;
    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_df.tenant_id, v_titulo_id, lpad(v_n::text, 3, '0'), coalesce(v_df.emissao_date, current_date) + coalesce((v_p->>'dias')::integer, 15), v_valor, v_valor);
    v_soma := v_soma + v_valor;
  end loop;
  update f.titulo t set valor_total = v_df.valor_total, valor_aberto = v_soma, os_id = coalesce(t.os_id, v_df.os_id_import), updated_at = now()
  where t.id = v_titulo_id;

  delete from f.titulo_retencao where titulo_id = v_titulo_id;
  for v_ret in select * from jsonb_array_elements(coalesce(v_emissao.retencoes, '[]'::jsonb)) loop
    insert into f.titulo_retencao (tenant_id, empresa_id, titulo_id, documento_fiscal_id, tributo, base, aliquota, valor)
    values (v_df.tenant_id, v_df.empresa_id, v_titulo_id, v_df.id, v_ret->>'tributo', (v_ret->>'base')::numeric, (v_ret->>'aliquota')::numeric, (v_ret->>'valor')::numeric);
  end loop;
  return v_titulo_id;
end;
$$;
revoke all on function f.fn_nfse_titulo_liquido_sincronizar(uuid) from public;
grant execute on function f.fn_nfse_titulo_liquido_sincronizar(uuid) to service_role;

create or replace function f.fn_nfse_titulo_cancelar(p_documento_fiscal_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_titulo_id uuid;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal cancela o titulo.';
  end if;
  select t.id into v_titulo_id from f.titulo t
  where t.tipo = 'AR' and t.documento_fiscal_id = p_documento_fiscal_id and t.deleted_at is null limit 1;
  if v_titulo_id is null then return; end if;
  if exists (
    select 1 from f.titulo_parcela tp join f.pagamento_item pi on pi.titulo_parcela_id = tp.id and pi.deleted_at is null
    where tp.titulo_id = v_titulo_id and tp.deleted_at is null
  ) then
    raise exception using errcode = '55000', message = 'Titulo com recebimento aplicado nao pode ser cancelado automaticamente.';
  end if;
  update f.titulo_parcela set valor_aberto = 0, updated_at = now() where titulo_id = v_titulo_id and deleted_at is null;
  update f.titulo set status = 'CANCELADO', valor_aberto = 0, descricao = concat_ws(' · ', descricao, p_motivo), updated_at = now() where id = v_titulo_id;
end;
$$;
revoke all on function f.fn_nfse_titulo_cancelar(uuid, text) from public;
grant execute on function f.fn_nfse_titulo_cancelar(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- Retorno da Focus (callback, reconciliacao ou resposta do POST)
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_aplicar_retorno(
  p_referencia_externa text,
  p_resposta jsonb,
  p_status text,
  p_chave_nfse text default null,
  p_nfse_numero text default null,
  p_codigo_verificacao text default null,
  p_protocolo text default null,
  p_codigo_status integer default null,
  p_mensagem text default null,
  p_xml_path text default null,
  p_danfse_path text default null,
  p_xml_raw text default null,
  p_origem_retorno text default 'CALLBACK'
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_xml_hash text;
  v_antiga f.documento_fiscal_emissao%rowtype;
  v_titulo_id uuid;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode aplicar retorno.';
  end if;
  if v_status not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'CANCELADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de retorno invalido.';
  end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.referencia_externa = p_referencia_externa for update;
  if not found then
    raise exception using errcode = 'P0002', message = format('Referencia %s nao encontrada.', p_referencia_externa);
  end if;
  if v_emissao.modelo <> 'NFSE' then
    raise exception using errcode = '22023', message = 'Esta funcao aplica retorno somente de NFS-e.';
  end if;

  -- Estados terminais: registra incidente e nao mexe.
  if v_emissao.status = 'CANCELADA' then
    if v_status <> 'CANCELADA' then
      insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa)
      values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'CONSULTA', 'INCIDENTE_RETORNO_TARDIO',
              jsonb_strip_nulls(jsonb_build_object('origem_retorno', upper(coalesce(p_origem_retorno, '')), 'status_recebido', v_status, 'resposta', p_resposta)),
              v_emissao.referencia_externa);
    end if;
    return v_emissao.documento_fiscal_id;
  end if;
  if v_status = 'CANCELADA' then
    -- Cancelamento chega pelo fluxo proprio (claim/finalizar). Fora dele e incidente.
    insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa)
    values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'CONSULTA', 'INCIDENTE_CANCELAMENTO_FORA_DO_FLUXO',
            jsonb_strip_nulls(jsonb_build_object('origem_retorno', upper(coalesce(p_origem_retorno, '')), 'resposta', p_resposta, 'estado_preservado', v_emissao.status)),
            v_emissao.referencia_externa);
    return v_emissao.documento_fiscal_id;
  end if;
  if v_emissao.status = 'AUTORIZADA' then
    -- Webhook duplicado / consulta tardia: idempotente.
    return v_emissao.documento_fiscal_id;
  end if;

  if v_status = 'AUTORIZADA' then
    if nullif(btrim(coalesce(p_chave_nfse, '')), '') is null or char_length(btrim(p_chave_nfse)) > 50 then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem chave de NFS-e valida.';
    end if;
    if nullif(btrim(coalesce(p_xml_raw, '')), '') is null then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem XML para f.documento_fiscal_xml.';
    end if;
    v_xml_hash := encode(extensions.digest(convert_to(p_xml_raw, 'utf8'), 'sha256'), 'hex');
  end if;

  update f.documento_fiscal_emissao dfe
  set status = v_status,
      resposta = coalesce(p_resposta, dfe.resposta),
      chave_nfse = coalesce(nullif(btrim(p_chave_nfse), ''), dfe.chave_nfse),
      chave_acesso = coalesce(nullif(btrim(p_chave_nfse), ''), dfe.chave_acesso),
      nfse_numero = coalesce(nullif(btrim(p_nfse_numero), ''), dfe.nfse_numero),
      numero = coalesce(case when p_nfse_numero ~ '^[0-9]{1,9}$' then p_nfse_numero::integer end, dfe.numero),
      serie = coalesce(dfe.serie, dfe.dps_serie::integer),
      codigo_verificacao = coalesce(nullif(btrim(p_codigo_verificacao), ''), dfe.codigo_verificacao),
      protocolo = coalesce(nullif(p_protocolo, ''), dfe.protocolo),
      codigo_status = coalesce(p_codigo_status, dfe.codigo_status),
      mensagem = coalesce(nullif(p_mensagem, ''), dfe.mensagem),
      xml_path = coalesce(nullif(p_xml_path, ''), dfe.xml_path),
      danfe_path = coalesce(nullif(p_danfse_path, ''), dfe.danfe_path),
      callback_recebido_em = case when upper(p_origem_retorno) = 'CALLBACK' then now() else dfe.callback_recebido_em end,
      reconciliado_em = case when upper(p_origem_retorno) = 'RECONCILIACAO' then now() else dfe.reconciliado_em end,
      autorizado_em = case when v_status = 'AUTORIZADA' then coalesce(dfe.autorizado_em, now()) else dfe.autorizado_em end,
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id and dfe.empresa_id = v_emissao.empresa_id and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;

  if v_status in ('REJEITADA', 'ERRO') then
    update f.dps_numero_log set resultado = case when v_status = 'ERRO' then 'ERRO' else 'REJEITADO' end,
           mensagem = left(coalesce(p_mensagem, 'Rejeitada pelo ambiente nacional.'), 1000), updated_at = now()
    where documento_fiscal_id = v_emissao.documento_fiscal_id and serie = v_emissao.dps_serie and numero = v_emissao.dps_numero;
    insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa)
    values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'REJEICAO', v_status,
            jsonb_strip_nulls(jsonb_build_object('origem_retorno', upper(coalesce(p_origem_retorno, '')), 'codigo_status', p_codigo_status, 'mensagem', p_mensagem,
                                                 'dps_serie', v_emissao.dps_serie, 'dps_numero', v_emissao.dps_numero, 'dps_queimada', true, 'resposta', p_resposta)),
            v_emissao.referencia_externa);
    -- O saldo volta sozinho: emissao REJEITADA/ERRO nao reserva (f.fn_os_saldo_a_faturar).
    return v_emissao.documento_fiscal_id;
  end if;

  if v_status = 'AUTORIZADA' then
    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_emissao.tenant_id, v_emissao.documento_fiscal_id, v_emissao.chave_nfse, p_xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id)
    do update set chave_acesso = excluded.chave_acesso, xml_raw = excluded.xml_raw, xml_hash = excluded.xml_hash, deleted_at = null;

    update f.documento_fiscal df
    set chave_acesso = v_emissao.chave_nfse,
        numero = coalesce(v_emissao.nfse_numero, df.numero),
        serie = coalesce(df.serie, v_emissao.dps_serie::text),
        nfse_codigo_verificacao = coalesce(v_emissao.codigo_verificacao, df.nfse_codigo_verificacao),
        emissao_date = coalesce(df.emissao_date, current_date),
        -- Homologacao nao fatura: o documento continua RASCUNHO (decisao A de 02/09/2026).
        nfse_status = case when v_emissao.ambiente = 'PRODUCAO' then 'EMITIDA' else df.nfse_status end,
        updated_at = now()
    where df.tenant_id = v_emissao.tenant_id and df.empresa_id = v_emissao.empresa_id and df.id = v_emissao.documento_fiscal_id;

    update f.solicitacao_faturamento sf set status = 'EMITIDA', updated_at = now()
    where sf.tenant_id = v_emissao.tenant_id and sf.empresa_id = v_emissao.empresa_id and sf.id = v_emissao.solicitacao_id;

    update f.dps_numero_log set resultado = 'AUTORIZADO', mensagem = format('NFS-e %s autorizada.', v_emissao.nfse_numero), updated_at = now()
    where documento_fiscal_id = v_emissao.documento_fiscal_id and serie = v_emissao.dps_serie and numero = v_emissao.dps_numero;

    insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, protocolo, resposta, referencia_externa)
    values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'AUTORIZACAO', 'AUTORIZADA', p_protocolo,
            jsonb_strip_nulls(jsonb_build_object('origem_retorno', upper(coalesce(p_origem_retorno, '')), 'ambiente', v_emissao.ambiente,
                                                 'nfse_numero', v_emissao.nfse_numero, 'chave_nfse', v_emissao.chave_nfse,
                                                 'codigo_verificacao', v_emissao.codigo_verificacao, 'dps_serie', v_emissao.dps_serie, 'dps_numero', v_emissao.dps_numero)),
            v_emissao.referencia_externa);

    if v_emissao.ambiente = 'PRODUCAO' then
      v_titulo_id := f.fn_nfse_titulo_liquido_sincronizar(v_emissao.documento_fiscal_id);
    end if;

    -- Substituicao: a antiga vira SUBSTITUIDA; saldo e titulo migram nesta transacao.
    if nullif(btrim(coalesce(v_emissao.chave_nfse_substituida, '')), '') is not null then
      select a.* into v_antiga from f.documento_fiscal_emissao a
      where a.tenant_id = v_emissao.tenant_id and a.empresa_id = v_emissao.empresa_id and a.modelo = 'NFSE'
        and a.chave_nfse = v_emissao.chave_nfse_substituida and a.documento_fiscal_id <> v_emissao.documento_fiscal_id
      for update;
      if found then
        update f.documento_fiscal set nfse_status = 'SUBSTITUIDA', updated_at = now()
        where id = v_antiga.documento_fiscal_id and tenant_id = v_antiga.tenant_id and empresa_id = v_antiga.empresa_id;
        update f.solicitacao_faturamento set status = 'CANCELADA',
          observacao = concat_ws(E'\n', nullif(btrim(observacao), ''), format('Substituida pela NFS-e %s (%s): %s', v_emissao.nfse_numero, v_emissao.substituicao_codigo, v_emissao.substituicao_motivo)),
          updated_at = now()
        where id = v_antiga.solicitacao_id and tenant_id = v_antiga.tenant_id and empresa_id = v_antiga.empresa_id;
        update f.dps_numero_log set resultado = 'SUBSTITUIDO', mensagem = format('Substituida pela NFS-e %s.', v_emissao.nfse_numero), updated_at = now()
        where documento_fiscal_id = v_antiga.documento_fiscal_id and serie = v_antiga.dps_serie and numero = v_antiga.dps_numero;
        insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, justificativa, resposta, referencia_externa, codigo_motivo, chave_nova, chave_substituida)
        values
          (v_antiga.documento_fiscal_id, v_antiga.tenant_id, v_antiga.empresa_id, 'SUBSTITUICAO', 'SUBSTITUIDA', v_emissao.substituicao_motivo,
           jsonb_build_object('papel', 'SUBSTITUIDA', 'nova_referencia', v_emissao.referencia_externa), v_antiga.referencia_externa,
           v_emissao.substituicao_codigo, v_emissao.chave_nfse, v_emissao.chave_nfse_substituida),
          (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'SUBSTITUICAO', 'AUTORIZADA', v_emissao.substituicao_motivo,
           jsonb_build_object('papel', 'SUBSTITUTA', 'antiga_referencia', v_antiga.referencia_externa), v_emissao.referencia_externa,
           v_emissao.substituicao_codigo, v_emissao.chave_nfse, v_emissao.chave_nfse_substituida);
        if v_antiga.ambiente = 'PRODUCAO' then
          perform f.fn_nfse_titulo_cancelar(v_antiga.documento_fiscal_id, format('Substituida pela NFS-e %s', v_emissao.nfse_numero));
        end if;
      end if;
    end if;
  end if;
  return v_emissao.documento_fiscal_id;
end;
$$;
revoke all on function f.fn_nfse_aplicar_retorno(text, jsonb, text, text, text, text, text, integer, text, text, text, text, text) from public;
grant execute on function f.fn_nfse_aplicar_retorno(text, jsonb, text, text, text, text, text, integer, text, text, text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- Cancelamento (claim duravel + finalizacao), prazo em empresa_fiscal
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_cancelamento_claim(p_documento_fiscal_id uuid, p_justificativa text, p_reconciliacao_claim_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_prazo integer;
  v_ult record;
  v_evento_claim_id uuid;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o cancelamento.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa deve ter entre 15 e 255 caracteres.';
  end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE';
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  perform 1 from f.solicitacao_faturamento sf where sf.id = v_emissao.solicitacao_id for update;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id for update;

  select ef.prazo_cancelamento_nfse_horas into v_prazo from c.empresa_fiscal ef where ef.empresa_id = v_emissao.empresa_id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  if v_emissao.ambiente = 'PRODUCAO' and v_prazo is null then
    raise exception using errcode = '55000', message = 'Prazo de cancelamento da NFS-e nao confirmado pelo contador; em producao use a substituicao.';
  end if;
  if v_prazo is not null and v_emissao.autorizado_em is not null and now() > v_emissao.autorizado_em + make_interval(hours => v_prazo) then
    raise exception using errcode = '55000', message = format('Prazo de cancelamento (%s h) encerrado; use a substituicao.', v_prazo);
  end if;

  select ev.id, ev.status, ev.created_at, ev.justificativa into v_ult
  from f.documento_fiscal_evento ev
  where ev.tenant_id = v_emissao.tenant_id and ev.empresa_id = v_emissao.empresa_id and ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.tipo = 'CANCELAMENTO'
  order by ev.created_at desc, ev.id desc limit 1;
  if v_ult.status = 'ENVIANDO' and v_ult.created_at >= now() - interval '2 minutes' then
    return jsonb_build_object('deve_cancelar', false, 'aguardar', true, 'deve_reconciliar', false, 'evento_claim_id', v_ult.id,
      'justificativa_claim', v_ult.justificativa, 'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa, 'status', 'ENVIANDO');
  end if;
  if v_ult.status = 'ENVIANDO' then
    if p_reconciliacao_claim_id is distinct from v_ult.id then
      return jsonb_build_object('deve_cancelar', false, 'aguardar', false, 'deve_reconciliar', true, 'evento_claim_id', v_ult.id,
        'justificativa_claim', v_ult.justificativa, 'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa, 'status', 'ENVIANDO');
    end if;
    if v_ult.justificativa is distinct from v_justificativa then
      raise exception using errcode = '22023', message = 'A justificativa do retry deve ser a mesma do claim reconciliado.';
    end if;
  elsif p_reconciliacao_claim_id is not null then
    raise exception using errcode = '55000', message = 'O claim informado ja nao e o cancelamento pendente mais recente.';
  end if;
  if v_emissao.status <> 'AUTORIZADA' then
    raise exception using errcode = '55000', message = format('Status %s nao permite cancelamento.', v_emissao.status);
  end if;
  insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, status, resposta, referencia_externa)
  values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'CANCELAMENTO', v_justificativa, 'ENVIANDO',
          jsonb_build_object('claim_duravel', true, 'modelo', 'NFSE', 'ambiente', v_emissao.ambiente, 'prazo_horas', v_prazo), v_emissao.referencia_externa)
  returning id into v_evento_claim_id;
  return jsonb_build_object('deve_cancelar', true, 'aguardar', false, 'deve_reconciliar', false, 'evento_claim_id', v_evento_claim_id,
    'justificativa_claim', v_justificativa, 'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa, 'status', 'ENVIANDO');
end;
$$;
revoke all on function f.fn_nfse_cancelamento_claim(uuid, text, uuid) from public;
grant execute on function f.fn_nfse_cancelamento_claim(uuid, text, uuid) to service_role;

create or replace function f.fn_nfse_cancelamento_finalizar(p_documento_fiscal_id uuid, p_evento_claim_id uuid, p_status text, p_justificativa text, p_protocolo text default null, p_resposta jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_claim record;
  v_ult record;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode concluir o cancelamento.';
  end if;
  if v_status not in ('AUTORIZADA', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status final de cancelamento invalido.';
  end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE';
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  perform 1 from f.solicitacao_faturamento sf where sf.id = v_emissao.solicitacao_id for update;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id for update;
  if p_evento_claim_id is null then
    raise exception using errcode = '22023', message = 'O identificador do claim de cancelamento e obrigatorio.';
  end if;
  if v_emissao.status = 'CANCELADA' and v_status = 'AUTORIZADA' then
    if exists (select 1 from f.documento_fiscal_evento ev where ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.tipo = 'CANCELAMENTO' and ev.status = 'AUTORIZADA' and ev.resposta->>'claim_evento_id' = p_evento_claim_id::text) then
      return jsonb_build_object('ok', true, 'idempotente', true, 'status', 'CANCELADA');
    end if;
    raise exception using errcode = '55000', message = 'Resposta tardia pertence a outro claim de cancelamento.';
  end if;
  select ev.id, ev.status into v_ult from f.documento_fiscal_evento ev
  where ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.tipo = 'CANCELAMENTO' order by ev.created_at desc, ev.id desc limit 1;
  if v_emissao.status <> 'AUTORIZADA' or v_ult.status is distinct from 'ENVIANDO' or v_ult.id is distinct from p_evento_claim_id then
    raise exception using errcode = '55000', message = 'Cancelamento sem claim duravel correspondente.';
  end if;
  select ev.id, ev.justificativa into v_claim from f.documento_fiscal_evento ev
  where ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.id = p_evento_claim_id and ev.tipo = 'CANCELAMENTO' and ev.status = 'ENVIANDO';
  if not found or v_claim.justificativa is distinct from v_justificativa then
    raise exception using errcode = '22023', message = 'Justificativa ou claim de cancelamento nao corresponde a reserva original.';
  end if;
  insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, protocolo, status, resposta, referencia_externa)
  values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'CANCELAMENTO', v_justificativa, nullif(btrim(p_protocolo), ''), v_status,
          coalesce(p_resposta, '{}'::jsonb) || jsonb_build_object('claim_evento_id', p_evento_claim_id, 'modelo', 'NFSE'), v_emissao.referencia_externa);
  if v_status = 'AUTORIZADA' then
    update f.documento_fiscal_emissao dfe set status = 'CANCELADA', protocolo = coalesce(nullif(btrim(p_protocolo), ''), dfe.protocolo),
      resposta = coalesce(p_resposta, dfe.resposta), mensagem = 'Cancelamento autorizado.', updated_at = now()
    where dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
    update f.solicitacao_faturamento sf set status = 'CANCELADA', updated_at = now() where sf.id = v_emissao.solicitacao_id;
    update f.dps_numero_log set resultado = 'CANCELADO', mensagem = v_justificativa, updated_at = now()
    where documento_fiscal_id = v_emissao.documento_fiscal_id and serie = v_emissao.dps_serie and numero = v_emissao.dps_numero;
    if v_emissao.ambiente = 'PRODUCAO' then
      update f.documento_fiscal set nfse_status = 'CANCELADA', updated_at = now() where id = v_emissao.documento_fiscal_id;
      perform f.fn_nfse_titulo_cancelar(v_emissao.documento_fiscal_id, 'NFS-e cancelada: ' || v_justificativa);
    end if;
    -- Homologacao: documento continua RASCUNHO; o saldo volta porque a emissao esta CANCELADA.
  else
    update f.documento_fiscal_emissao dfe set resposta = coalesce(p_resposta, dfe.resposta),
      mensagem = 'Cancelamento nao autorizado; NFS-e permanece autorizada.', updated_at = now()
    where dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;
  return jsonb_build_object('ok', v_status = 'AUTORIZADA', 'idempotente', false, 'status', case when v_status = 'AUTORIZADA' then 'CANCELADA' else 'AUTORIZADA' end);
end;
$$;
revoke all on function f.fn_nfse_cancelamento_finalizar(uuid, uuid, text, text, text, jsonb) from public;
grant execute on function f.fn_nfse_cancelamento_finalizar(uuid, uuid, text, text, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Substituicao: clona a solicitacao para a NFS-e substituta
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_substituir_preparar(p_documento_fiscal_id uuid, p_codigo text, p_motivo text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_df f.documento_fiscal%rowtype;
  v_novo_id uuid := gen_random_uuid();
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE';
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_emissao.tenant_id
    or public.current_empresa_id() is distinct from v_emissao.empresa_id
    or not f.has_finance_access(v_emissao.tenant_id, v_emissao.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para substituir esta NFS-e.';
  end if;
  if p_codigo not in ('01', '02', '03', '04', '05', '99') then
    raise exception using errcode = '22023', message = 'Codigo de justificativa da substituicao invalido (01-05 ou 99).';
  end if;
  if char_length(v_motivo) < 15 or char_length(v_motivo) > 255 then
    raise exception using errcode = '22023', message = 'O motivo da substituicao deve ter entre 15 e 255 caracteres.';
  end if;
  if v_emissao.status <> 'AUTORIZADA' or nullif(btrim(coalesce(v_emissao.chave_nfse, '')), '') is null then
    raise exception using errcode = '55000', message = 'Somente NFS-e autorizada pode ser substituida.';
  end if;
  select * into v_df from f.documento_fiscal where id = v_emissao.documento_fiscal_id;
  if v_df.nfse_status in ('CANCELADA', 'SUBSTITUIDA') then
    raise exception using errcode = '55000', message = format('NFS-e ja %s.', lower(v_df.nfse_status));
  end if;
  if exists (select 1 from f.solicitacao_faturamento s where s.substitui_documento_fiscal_id = v_df.id and s.status <> 'CANCELADA') then
    raise exception using errcode = '55000', message = 'Ja existe uma substituicao em andamento para esta NFS-e.';
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_emissao.solicitacao_id;

  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, pedido_cliente, pedido_item, observacao, natureza_operacao, perfil_operacao_id,
    municipio_prestacao_ibge, data_competencia, iss_retido, retem_pcc, retem_irrf, retem_inss, retencao_justificativa,
    pagamento_forma, pagamento_indicador, pagamento_descricao, pagamento_parcelas, consumidor_final,
    substitui_solicitacao_id, substitui_documento_fiscal_id, substituicao_codigo, substituicao_motivo
  ) values (
    v_novo_id, v_sf.tenant_id, v_sf.empresa_id, v_sf.cliente_id, 'RASCUNHO', v_sf.pedido_cliente, v_sf.pedido_item,
    format('Substituicao da NFS-e %s (%s): %s', coalesce(v_emissao.nfse_numero, v_emissao.referencia_externa), p_codigo, v_motivo),
    'PRESTACAO_SERVICO', v_sf.perfil_operacao_id,
    v_sf.municipio_prestacao_ibge, v_sf.data_competencia, v_sf.iss_retido, v_sf.retem_pcc, v_sf.retem_irrf, v_sf.retem_inss, v_sf.retencao_justificativa,
    v_sf.pagamento_forma, v_sf.pagamento_indicador, v_sf.pagamento_descricao, v_sf.pagamento_parcelas, v_sf.consumidor_final,
    v_sf.id, v_df.id, p_codigo, v_motivo
  );
  insert into f.solicitacao_item (
    solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, item_id, descricao, quantidade, unidade, valor_unitario, ordem,
    modelo, descricao_servico, valor_servico, perfil_operacao_id
  )
  select v_novo_id, si.tenant_id, si.empresa_id, si.origem_tipo, si.origem_id, null, si.descricao, 1, 'UN', si.valor_servico, si.ordem,
         'NFSE', si.descricao_servico, si.valor_servico, si.perfil_operacao_id
  from f.solicitacao_item si where si.solicitacao_id = v_sf.id order by si.ordem;
  return v_novo_id;
end;
$$;
revoke all on function f.fn_nfse_substituir_preparar(uuid, text, text) from public;
grant execute on function f.fn_nfse_substituir_preparar(uuid, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Abandono de homologacao (reaproveita a NF-e) + log da DPS
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_abandonar_homologacao(p_solicitacao_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_resultado jsonb;
begin
  v_resultado := f.fn_solicitacao_nfe_abandonar_homologacao(p_solicitacao_id, p_motivo);
  update f.dps_numero_log l set resultado = 'ABANDONADO', mensagem = 'Homologacao abandonada; NFS-e de teste continua no ambiente nacional de homologacao.', updated_at = now()
  from f.documento_fiscal_emissao e
  where e.solicitacao_id = p_solicitacao_id and e.modelo = 'NFSE' and l.documento_fiscal_id = e.documento_fiscal_id and l.resultado in ('RESERVADO', 'AUTORIZADO');
  return v_resultado;
end;
$$;
revoke all on function f.fn_nfse_abandonar_homologacao(uuid, text) from public;
grant execute on function f.fn_nfse_abandonar_homologacao(uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Reconciliacao
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_emissoes_pendentes_reconciliacao(p_limite integer default 50)
returns table (documento_fiscal_id uuid, referencia_externa text, ambiente text)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select dfe.documento_fiscal_id, dfe.referencia_externa, dfe.ambiente
  from f.documento_fiscal_emissao dfe
  where dfe.modelo = 'NFSE'
    and dfe.status in ('ENVIANDO', 'PROCESSANDO')
    and coalesce(dfe.ultima_tentativa_em, dfe.updated_at) < now() - interval '10 minutes'
  order by coalesce(dfe.ultima_tentativa_em, dfe.updated_at)
  limit least(greatest(coalesce(p_limite, 50), 1), 200);
$$;
revoke all on function f.fn_nfse_emissoes_pendentes_reconciliacao(integer) from public;
grant execute on function f.fn_nfse_emissoes_pendentes_reconciliacao(integer) to service_role;

create or replace function f.fn_nfse_registrar_webhook(p_empresa_id uuid, p_hook_id text)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal registra o webhook.';
  end if;
  update c.empresa_fiscal set focus_webhook_nfsen_id = p_hook_id, focus_webhook_nfsen_registrado_em = now(), updated_at = now()
  where empresa_id = p_empresa_id and deleted_at is null;
end;
$$;
revoke all on function f.fn_nfse_registrar_webhook(uuid, text) from public;
grant execute on function f.fn_nfse_registrar_webhook(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- Portao de producao para perfil de servico
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_producao_pronta(p_solicitacao_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_perfil f.perfil_operacao%rowtype;
  v_hom_doc uuid;
  v_hom_autorizado_em timestamptz;
  v_certificado date;
begin
  select * into v_sf from f.solicitacao_faturamento where id = p_solicitacao_id;
  if not found then return jsonb_build_object('pronta', false, 'motivo', 'Solicitacao nao encontrada.'); end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;
  if v_sf.status = 'CANCELADA' then return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao esta cancelada.'); end if;
  select dfe.documento_fiscal_id, dfe.autorizado_em into v_hom_doc, v_hom_autorizado_em
  from f.documento_fiscal_emissao dfe
  where dfe.solicitacao_id = v_sf.id and dfe.ambiente = 'HOMOLOGACAO' and dfe.status = 'AUTORIZADA' and dfe.modelo = 'NFSE'
  order by dfe.autorizado_em desc nulls last limit 1;
  if v_hom_doc is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.');
  end if;
  select ef.certificado_validade_em into v_certificado from c.empresa_fiscal ef where ef.empresa_id = v_sf.empresa_id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  if v_certificado is null then return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.'); end if;
  if v_certificado < current_date then return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.'); end if;
  if v_sf.snapshot_cadastro_em is null or jsonb_typeof(v_sf.operacao_snapshot->'servico') is distinct from 'object' then
    return jsonb_build_object('pronta', false, 'motivo', 'A conferencia da NFS-e ainda nao foi salva.');
  end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and (si.tributacao_fonte is distinct from 'PERFIL' or si.perfil_operacao_id is null)) then
    return jsonb_build_object('pronta', false, 'motivo', 'Linhas de servico com valores da fixture de homologacao; producao exige perfil de servico liberado.');
  end if;
  select po.* into v_perfil from f.perfil_operacao po where po.id = v_sf.perfil_operacao_id;
  if not found or v_perfil.modelo <> 'NFSE' then return jsonb_build_object('pronta', false, 'motivo', 'Perfil de servico nao encontrado.'); end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' or not v_perfil.habilitado_producao
     or v_perfil.vigencia_inicio > current_date or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date)
     or v_perfil.revisao_fiscal_em is null or v_perfil.producao_decidida_em is null
     or v_perfil.producao_homologacao_solicitacao_id is distinct from v_sf.id
     or v_perfil.producao_homologacao_documento_id is distinct from v_hom_doc
     or v_hom_autorizado_em <= v_perfil.revisao_fiscal_em
     or v_perfil.codigo_tributacao_nacional is null or v_perfil.aliquota_iss is null or v_perfil.iss_retido_regra is null
     or v_perfil.cst_ibs_cbs is null or v_perfil.cclass_trib is null
     or not exists (
       select 1 from f.perfil_operacao_revisao_evento le
       where le.perfil_operacao_id = v_perfil.id and le.tipo = 'LIBERACAO'
         and le.homologacao_solicitacao_id = v_sf.id and le.homologacao_documento_id = v_hom_doc
         and le.depois->>'habilitado_producao' = 'true'
     ) then
    return jsonb_build_object('pronta', false, 'motivo', 'Perfil de servico precisa estar liberado para esta homologacao, com codigo de tributacao, ISS, retencoes e cClassTrib preenchidos.');
  end if;
  return jsonb_build_object('pronta', true, 'tenant_id', v_sf.tenant_id, 'empresa_id', v_sf.empresa_id,
    'homologacao_documento_fiscal_id', v_hom_doc, 'perfil_operacao_id', v_perfil.id, 'perfil_operacao_ids', jsonb_build_array(v_perfil.id));
end;
$$;
revoke all on function f.fn_nfse_producao_pronta(uuid) from public;
grant execute on function f.fn_nfse_producao_pronta(uuid) to authenticated, service_role;

-- f.fn_nfe_producao_pronta: corpo original (baseline 05/09/2026) + desvio para NFS-e.
CREATE OR REPLACE FUNCTION f.fn_nfe_producao_pronta(p_solicitacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_certificado_validade date;
  v_crt text;
  v_ambito text;
  v_homologacao_documento_id uuid;
  v_homologacao_payload jsonb;
  v_homologacao_autorizado_em timestamptz;
  v_total_itens integer;
  v_invalidos integer;
  v_perfis jsonb;
  v_perfil_unico uuid;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id;

  if not found then
    return jsonb_build_object('pronta', false, 'motivo', 'Solicitacao nao encontrada.');
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;
  if v_sf.status = 'CANCELADA' then
    return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao esta cancelada.');
  end if;
  -- NFS-e (05/09/2026): solicitacao com linha de servico usa o portao proprio.
  if exists (
    select 1 from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id and si.modelo = 'NFSE'
  ) then
    return f.fn_nfse_producao_pronta(p_solicitacao_id);
  end if;

  select dfe.documento_fiscal_id, dfe.payload_enviado, dfe.autorizado_em
    into v_homologacao_documento_id, v_homologacao_payload, v_homologacao_autorizado_em
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.status = 'AUTORIZADA'
  order by dfe.autorizado_em desc nulls last, dfe.updated_at desc, dfe.documento_fiscal_id desc
  limit 1;

  if v_homologacao_documento_id is null then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.'
    );
  end if;
  if coalesce((
    select ev.status = 'ENVIANDO'
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_sf.tenant_id
      and ev.empresa_id = v_sf.empresa_id
      and ev.documento_fiscal_id = v_homologacao_documento_id
      and ev.tipo = 'CANCELAMENTO'
    order by ev.created_at desc, ev.id desc
    limit 1
  ), false) then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A NF-e de homologacao vinculada possui cancelamento em andamento.'
    );
  end if;
  if jsonb_typeof(v_homologacao_payload) is distinct from 'object'
     or jsonb_typeof(v_homologacao_payload->'items') is distinct from 'array' then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A homologacao autorizada nao possui o payload fiscal enviado para comparacao.'
    );
  end if;

  select ef.certificado_validade_em, ef.crt::text
    into v_certificado_validade, v_crt
  from c.empresa e
  join c.empresa_fiscal ef
    on ef.empresa_id = e.id
   and ef.deleted_at is null
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null;

  if not found or v_certificado_validade is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.');
  end if;
  if v_certificado_validade < current_date then
    return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.');
  end if;
  if v_sf.destino_uf_confirmada is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A UF de destino ainda nao foi confirmada.');
  end if;
  if v_sf.revisao_fiscal_confirmada_em is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A conferencia fiscal desta solicitacao ainda nao foi confirmada.');
  end if;
  if v_sf.snapshot_cadastro_em is null
     or jsonb_typeof(v_sf.emitente_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.destinatario_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.operacao_snapshot) is distinct from 'object' then
    return jsonb_build_object('pronta', false, 'motivo', 'O cadastro fiscal ainda nao foi validado e congelado.');
  end if;
  if upper(nullif(btrim(v_sf.destinatario_snapshot->>'uf'), '')) is distinct from v_sf.destino_uf_confirmada
     or nullif(btrim(v_sf.emitente_snapshot->>'uf'), '') is null then
    return jsonb_build_object('pronta', false, 'motivo', 'As UFs do snapshot fiscal nao correspondem ao destino confirmado.');
  end if;
  v_ambito := case
    when upper(btrim(v_sf.emitente_snapshot->>'uf')) = v_sf.destino_uf_confirmada then 'INTERNA'
    else 'INTERESTADUAL'
  end;

  select
    count(*),
    count(*) filter (
      where si.perfil_operacao_id is null
         or po.id is null
         or po.modelo <> 'NFE'
         or po.natureza_operacao <> v_sf.natureza_operacao
         or (po.crt is not null and po.crt is distinct from v_crt)
         or po.ambito_destino is distinct from v_ambito
         or not po.habilitado_producao
         or po.faixa_automacao = 'BLOQUEADO'
         or po.vigencia_inicio > current_date
         or (po.vigencia_fim is not null and po.vigencia_fim < current_date)
         or po.ufs_destino is null
         or not (v_sf.destino_uf_confirmada = any(po.ufs_destino))
         or po.revisao_fiscal_em is null
         or v_homologacao_autorizado_em is null
         or v_homologacao_autorizado_em <= po.revisao_fiscal_em
         or po.producao_decidida_em is null
         or po.producao_decidida_em < po.revisao_fiscal_em
         or po.producao_homologacao_solicitacao_id is distinct from v_sf.id
         or po.producao_homologacao_documento_id is distinct from v_homologacao_documento_id
         or nullif(btrim(po.producao_decisao_justificativa), '') is null
         or not exists (
           select 1
           from f.perfil_operacao_revisao_evento le
           where le.tenant_id = po.tenant_id
             and le.empresa_id = po.empresa_id
             and le.perfil_operacao_id = po.id
             and le.tipo = 'LIBERACAO'
             and le.homologacao_solicitacao_id = v_sf.id
             and le.homologacao_documento_id = v_homologacao_documento_id
             and le.created_at = po.producao_decidida_em
             and le.criado_por is not distinct from po.producao_decidida_por
             and le.justificativa = po.producao_decisao_justificativa
             and le.depois->>'habilitado_producao' = 'true'
             and le.depois->>'producao_homologacao_solicitacao_id' = v_sf.id::text
             and le.depois->>'producao_homologacao_documento_id' = v_homologacao_documento_id::text
             and le.depois->>'cst_ibs_cbs' is not distinct from po.cst_ibs_cbs
             and le.depois->>'cclass_trib' is not distinct from po.cclass_trib
             and f.fn_perfil_operacao_jsonb_numeric_seguro(
               le.depois->'ibs_cbs_json', 'ibs_uf_aliquota'
             ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
               po.ibs_cbs_json, 'ibs_uf_aliquota'
             )
             and f.fn_perfil_operacao_jsonb_numeric_seguro(
               le.depois->'ibs_cbs_json', 'ibs_mun_aliquota'
             ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
               po.ibs_cbs_json, 'ibs_mun_aliquota'
             )
             and f.fn_perfil_operacao_jsonb_numeric_seguro(
               le.depois->'ibs_cbs_json', 'cbs_aliquota'
             ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
               po.ibs_cbs_json, 'cbs_aliquota'
             )
         )
         or (po.indicador_ie_destinatario is not null
             and po.indicador_ie_destinatario is distinct from v_sf.destinatario_snapshot->>'indicador_ie')
         or (po.origem_mercadoria is not null
             and po.origem_mercadoria is distinct from si.origem_mercadoria)
         or (v_ambito = 'INTERNA' and po.cfop_interno is distinct from si.cfop)
         or (v_ambito = 'INTERESTADUAL' and po.cfop_externo is distinct from si.cfop)
         or (po.finalidade_emissao is not null
             and po.finalidade_emissao is distinct from (v_sf.operacao_snapshot->>'finalidade_emissao')::smallint)
         or (po.consumidor_final is not null
             and po.consumidor_final is distinct from (v_sf.operacao_snapshot->>'consumidor_final')::smallint)
         or si.cst_ibs_cbs is distinct from po.cst_ibs_cbs
         or si.cclass_trib is distinct from po.cclass_trib
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_uf_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_uf_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_mun_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_mun_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'cbs_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'cbs_aliquota')
         or dfi.id is null
         or dfi.cst_ibs_cbs is distinct from po.cst_ibs_cbs
         or dfi.cclass_trib is distinct from po.cclass_trib
         or f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_uf_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_uf_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_mun_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_mun_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'cbs_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'cbs_aliquota')
         or hp.item is null
         or hp.item->>'ibs_cbs_situacao_tributaria' is distinct from po.cst_ibs_cbs
         or hp.item->>'ibs_cbs_classificacao_tributaria' is distinct from po.cclass_trib
         or f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_uf_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_uf_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_mun_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_mun_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'cbs_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'cbs_aliquota')
    ),
    coalesce(jsonb_agg(distinct po.id) filter (where po.id is not null), '[]'::jsonb)
  into v_total_itens, v_invalidos, v_perfis
  from f.solicitacao_item si
  left join f.perfil_operacao po
    on po.tenant_id = si.tenant_id
   and (po.empresa_id = si.empresa_id or po.empresa_id is null)
   and po.id = si.perfil_operacao_id
  left join f.documento_fiscal_item dfi
    on dfi.tenant_id = si.tenant_id
   and dfi.empresa_id = si.empresa_id
   and dfi.documento_fiscal_id = v_homologacao_documento_id
   and dfi.item_n = si.ordem
  left join lateral (
    select p.item
    from jsonb_array_elements(v_homologacao_payload->'items') p(item)
    where p.item->>'numero_item' = si.ordem::text
    limit 1
  ) hp on true
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if v_total_itens = 0 then
    return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao nao possui itens fiscais.');
  end if;
  if v_invalidos > 0 then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'Perfis precisam estar liberados para esta homologacao e coincidir exatamente com os campos fiscais autorizados.'
    );
  end if;

  if jsonb_array_length(v_perfis) = 1 then
    v_perfil_unico := (v_perfis->>0)::uuid;
  end if;

  return jsonb_build_object(
    'pronta', true,
    'tenant_id', v_sf.tenant_id,
    'empresa_id', v_sf.empresa_id,
    'homologacao_documento_fiscal_id', v_homologacao_documento_id,
    'perfil_operacao_id', v_perfil_unico,
    'perfil_operacao_ids', v_perfis
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Debito de PIS/COFINS da NFS-e: ignora documento de homologacao (RASCUNHO)
-- ---------------------------------------------------------------------------
create or replace function f.trg_nfse_sync_piscofins_from_doc()
returns trigger
language plpgsql
security definer
set search_path = f, public
set row_security = off
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;
  if new.deleted_at is null
     and coalesce(new.modelo, '') = 'NFSE'
     and coalesce(new.operacao, '') = 'SAIDA'
     and coalesce(new.natureza, '') = 'SERVICO'
     and coalesce(new.nfse_status, '') <> 'RASCUNHO' then
    perform f.fn_nfse_sync_piscofins_debito_doc(new.id);
  end if;
  return new;
end;
$$;
