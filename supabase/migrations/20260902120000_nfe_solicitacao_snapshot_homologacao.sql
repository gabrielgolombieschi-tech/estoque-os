begin;

-- A emissao fiscal nao consulta cadastro nem perfil no momento do envio.
-- Tudo que entra no payload precisa estar materializado na solicitacao.
alter table f.solicitacao_faturamento
  add column emitente_snapshot jsonb,
  add column destinatario_snapshot jsonb,
  add column operacao_snapshot jsonb,
  add column snapshot_cadastro_em timestamptz,
  add column finalidade_emissao smallint,
  add column consumidor_final smallint,
  add column presenca_comprador smallint,
  add column modalidade_frete smallint,
  add column valor_frete numeric(15,2),
  add column valor_seguro numeric(15,2),
  add column valor_outras_despesas numeric(15,2),
  add constraint solicitacao_faturamento_emitente_snapshot_ck
    check (emitente_snapshot is null or jsonb_typeof(emitente_snapshot) = 'object'),
  add constraint solicitacao_faturamento_destinatario_snapshot_ck
    check (destinatario_snapshot is null or jsonb_typeof(destinatario_snapshot) = 'object'),
  add constraint solicitacao_faturamento_operacao_snapshot_ck
    check (operacao_snapshot is null or jsonb_typeof(operacao_snapshot) = 'object'),
  add constraint solicitacao_faturamento_finalidade_emissao_ck
    check (finalidade_emissao is null or finalidade_emissao in (1, 2, 3, 4)),
  add constraint solicitacao_faturamento_consumidor_final_ck
    check (consumidor_final is null or consumidor_final in (0, 1)),
  add constraint solicitacao_faturamento_presenca_comprador_ck
    check (presenca_comprador is null or presenca_comprador in (0, 1, 2, 3, 4, 5, 9)),
  add constraint solicitacao_faturamento_modalidade_frete_ck
    check (modalidade_frete is null or modalidade_frete in (0, 1, 2, 3, 4, 9)),
  add constraint solicitacao_faturamento_valores_operacao_ck
    check (
      (valor_frete is null or valor_frete >= 0)
      and (valor_seguro is null or valor_seguro >= 0)
      and (valor_outras_despesas is null or valor_outras_despesas >= 0)
    );

alter table f.solicitacao_item
  add column codigo_produto text,
  add column cest text,
  add column origem_mercadoria smallint,
  add column unidade_tributavel text,
  add column valor_desconto numeric(15,2),
  add column icms_modalidade_base_calculo text,
  add column aliquota_icms numeric(7,4),
  add column aliquota_ipi numeric(7,4),
  add column aliquota_pis numeric(7,4),
  add column aliquota_cofins numeric(7,4),
  add constraint solicitacao_item_codigo_produto_ck
    check (codigo_produto is null or nullif(btrim(codigo_produto), '') is not null),
  add constraint solicitacao_item_cest_ck
    check (cest is null or regexp_replace(cest, '[^0-9]', '', 'g') ~ '^[0-9]{7}$'),
  add constraint solicitacao_item_origem_mercadoria_ck
    check (origem_mercadoria is null or origem_mercadoria between 0 and 8),
  add constraint solicitacao_item_valor_desconto_ck
    check (valor_desconto is null or valor_desconto >= 0),
  add constraint solicitacao_item_aliquotas_ck
    check (
      (aliquota_icms is null or aliquota_icms between 0 and 100)
      and (aliquota_ipi is null or aliquota_ipi between 0 and 100)
      and (aliquota_pis is null or aliquota_pis between 0 and 100)
      and (aliquota_cofins is null or aliquota_cofins between 0 and 100)
    );

comment on column f.solicitacao_faturamento.emitente_snapshot is
  'Dados do emitente congelados antes da emissao; unica fonte do payload da Focus.';
comment on column f.solicitacao_faturamento.destinatario_snapshot is
  'Dados do destinatario congelados antes da emissao; inclui indIEDest confirmado por pessoa.';
comment on column f.solicitacao_faturamento.operacao_snapshot is
  'Dados operacionais explicitamente confirmados na solicitacao; nao recebe fallback de perfil.';
comment on column f.solicitacao_item.origem_mercadoria is
  'orig da NF-e. Atributo do produto copiado para a solicitacao e separado do CST/CSOSN.';

create unique index uq_documento_fiscal_emissao_solicitacao
  on f.documento_fiscal_emissao (tenant_id, empresa_id, solicitacao_id)
  where solicitacao_id is not null;

create or replace function public.cpf_valido(p_documento text)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $function$
declare
  v_cpf text := regexp_replace(coalesce(p_documento, ''), '[^0-9]', '', 'g');
  v_soma integer;
  v_resto integer;
  v_i integer;
begin
  if length(v_cpf) <> 11 or v_cpf ~ '^([0-9])\1{10}$' then
    return false;
  end if;
  v_soma := 0;
  for v_i in 1..9 loop
    v_soma := v_soma + substring(v_cpf from v_i for 1)::integer * (11 - v_i);
  end loop;
  v_resto := (v_soma * 10) % 11;
  if v_resto = 10 then v_resto := 0; end if;
  if v_resto <> substring(v_cpf from 10 for 1)::integer then return false; end if;

  v_soma := 0;
  for v_i in 1..10 loop
    v_soma := v_soma + substring(v_cpf from v_i for 1)::integer * (12 - v_i);
  end loop;
  v_resto := (v_soma * 10) % 11;
  if v_resto = 10 then v_resto := 0; end if;
  return v_resto = substring(v_cpf from 11 for 1)::integer;
end;
$function$;

revoke all on function public.cpf_valido(text) from public, anon;
grant execute on function public.cpf_valido(text) to authenticated, service_role;

create or replace function f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_cliente public.clientes%rowtype;
  v_item record;
  v_documento text;
  v_pendencias jsonb := '[]'::jsonb;
  v_rota_cliente text;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para validar esta solicitacao.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Somente solicitacao ainda nao emitida pode congelar cadastro.';
  end if;

  select * into v_empresa
  from c.empresa e
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null
    and e.ativo;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object(
      'entidade', 'empresa', 'id', v_sf.empresa_id, 'campo', 'empresa',
      'mensagem', 'Empresa ativa nao encontrada no cadastro corporativo.', 'rota', '/configuracoes'
    ));
  else
    select * into v_fiscal
    from c.empresa_fiscal ef
    where ef.empresa_id = v_empresa.id and ef.deleted_at is null
    order by ef.updated_at desc
    limit 1;
    select * into v_endereco
    from c.empresa_endereco ee
    where ee.empresa_id = v_empresa.id and ee.deleted_at is null
    order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc
    limit 1;

    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14
       or not public.cnpj_valido(v_empresa.cnpj) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cnpj','mensagem','CNPJ do emitente e invalido.','rota','/configuracoes'));
    end if;
    if nullif(btrim(v_empresa.razao_social), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','razao_social','mensagem','Razao social do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or nullif(btrim(v_fiscal.inscricao_estadual), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','inscricao_estadual','mensagem','IE do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.crt is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','crt','mensagem','CRT do emitente nao informado.','rota','/configuracoes'));
    end if;
    if v_endereco.id is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','endereco_fiscal','mensagem','Endereco fiscal do emitente nao informado.','rota','/configuracoes'));
    else
      if nullif(btrim(v_endereco.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','logradouro','mensagem','Logradouro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.numero), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','numero','mensagem','Numero do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','bairro','mensagem','Bairro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cidade','mensagem','Municipio do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.uf::text), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','uf','mensagem','UF do emitente nao informada.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cep','mensagem','CEP do emitente deve ter 8 digitos.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','codigo_municipio_ibge','mensagem','Codigo IBGE do emitente deve ter 7 digitos.','rota','/configuracoes')); end if;
    end if;
  end if;

  v_rota_cliente := '/clientes/cadastro-fiscal?cliente_id=' || coalesce(v_sf.cliente_id::text, '');
  select * into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id
    and c.empresa_id = v_sf.empresa_id
    and c.id = v_sf.cliente_id
    and c.ativo is true;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_sf.cliente_id,'campo','cliente','mensagem','Destinatario ativo nao encontrado nesta empresa.','rota',v_rota_cliente));
  else
    v_documento := regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g');
    if not ((length(v_documento) = 14 and public.cnpj_valido(v_documento)) or (length(v_documento) = 11 and public.cpf_valido(v_documento))) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','CPF/CNPJ do destinatario e invalido.','rota',v_rota_cliente));
    end if;
    if nullif(btrim(v_cliente.razao_social), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','razao_social','mensagem','Razao social ou nome completo nao informado.','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie is null or v_cliente.indicador_ie not in ('1','2','9') then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','indicador_ie','mensagem','Confirme manualmente o indicador de IE (1, 2 ou 9).','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie = '1' and nullif(btrim(v_cliente.inscricao_estadual), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','inscricao_estadual','mensagem','Contribuinte do ICMS deve ter IE informada.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','logradouro','mensagem','Logradouro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.numero_endereco), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','numero_endereco','mensagem','Numero do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','bairro','mensagem','Bairro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cidade','mensagem','Municipio do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if coalesce(v_cliente.uf, '') !~ '^[A-Za-z]{2}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','uf','mensagem','UF do destinatario deve ter 2 letras.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cep','mensagem','CEP do destinatario deve ter 8 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','codigo_ibge_municipio','mensagem','Codigo IBGE do destinatario deve ter 7 digitos.','rota',v_rota_cliente)); end if;
  end if;

  -- Copia apenas atributos permanentes do produto. CFOP, CST/CSOSN e aliquotas
  -- continuam exclusivamente sob responsabilidade da solicitacao.
  update f.solicitacao_item si
  set codigo_produto = coalesce(si.codigo_produto, nullif(btrim(i.codigo_interno), '')),
      ncm = coalesce(si.ncm, nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '')),
      cest = coalesce(si.cest, nullif(regexp_replace(coalesce(fi.cest, ''), '[^0-9]', '', 'g'), '')),
      origem_mercadoria = coalesce(si.origem_mercadoria, fi.origem),
      unidade_tributavel = coalesce(si.unidade_tributavel, nullif(btrim(fi.unidade_tributavel), ''), nullif(btrim(si.unidade), '')),
      valor_desconto = coalesce(si.valor_desconto, 0)
  from public.itens i
  left join public.fiscal_itens fi
    on fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id and fi.item_id = i.id
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
    and i.tenant_id = si.tenant_id
    and i.empresa_id = si.empresa_id
    and i.id = si.item_id;

  if not exists (select 1 from f.solicitacao_item si where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id) then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','itens','mensagem','A solicitacao nao possui itens.','rota','/faturamento/solicitacoes/' || v_sf.id));
  end if;

  for v_item in
    select si.*
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
    order by si.ordem, si.id
  loop
    if nullif(btrim(v_item.codigo_produto), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','codigo_produto','mensagem',format('Linha %s: codigo do produto nao informado.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.descricao), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','descricao','mensagem',format('Linha %s: descricao nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.ncm, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','ncm','mensagem',format('Linha %s: NCM deve ter 8 digitos.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g') !~ '^[0-9]{4}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cfop','mensagem',format('Linha %s: CFOP nao confirmado na solicitacao.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.origem_mercadoria is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','origem_mercadoria','mensagem',format('Linha %s: origem da mercadoria nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.unidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','unidade','mensagem',format('Linha %s: unidade comercial nao informada.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.unidade_tributavel), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','unidade_tributavel','mensagem',format('Linha %s: unidade tributavel nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if v_item.quantidade <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','quantidade','mensagem',format('Linha %s: quantidade deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.valor_unitario <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_unitario','mensagem',format('Linha %s: valor unitario deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if (case when nullif(btrim(v_item.cst_icms), '') is null then 0 else 1 end + case when nullif(btrim(v_item.csosn), '') is null then 0 else 1 end) <> 1 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms_csosn','mensagem',format('Linha %s: informe CST de ICMS ou CSOSN, nunca ambos.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt = 1 and nullif(btrim(v_item.csosn), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','csosn','mensagem',format('Linha %s: emitente do Simples exige CSOSN.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt is not null and v_fiscal.crt <> 1 and nullif(btrim(v_item.cst_icms), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms','mensagem',format('Linha %s: regime normal exige CST de ICMS.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_ipi), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_ipi','mensagem',format('Linha %s: CST de IPI nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_pis), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_pis','mensagem',format('Linha %s: CST de PIS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_cofins), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_cofins','mensagem',format('Linha %s: CST de COFINS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  end loop;

  if v_sf.finalidade_emissao is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','finalidade_emissao','mensagem','Finalidade de emissao nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.consumidor_final is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','consumidor_final','mensagem','Indicador de consumidor final nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.presenca_comprador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','presenca_comprador','mensagem','Indicador de presenca do comprador nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.modalidade_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','modalidade_frete','mensagem','Modalidade do frete nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_frete','mensagem','Valor do frete nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_seguro is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_seguro','mensagem','Valor do seguro nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_outras_despesas is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_outras_despesas','mensagem','Outras despesas nao confirmadas; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;

  if jsonb_array_length(v_pendencias) = 0 then
    update f.solicitacao_faturamento
    set emitente_snapshot = jsonb_build_object(
          'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
          'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
          'telefone', v_empresa.telefone, 'inscricao_estadual', v_fiscal.inscricao_estadual,
          'crt', v_fiscal.crt, 'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero,
          'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro,
          'cidade', v_endereco.cidade, 'uf', upper(v_endereco.uf::text),
          'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')
        ),
        destinatario_snapshot = jsonb_build_object(
          'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social,
          'inscricao_estadual', nullif(btrim(v_cliente.inscricao_estadual), ''),
          'indicador_ie', v_cliente.indicador_ie, 'email', v_cliente.email,
          'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro,
          'numero_endereco', v_cliente.numero_endereco, 'complemento', v_cliente.complemento,
          'bairro', v_cliente.bairro, 'cidade', v_cliente.cidade, 'uf', upper(v_cliente.uf),
          'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')
        ),
        operacao_snapshot = jsonb_build_object(
          'natureza_operacao', natureza_operacao, 'finalidade_emissao', finalidade_emissao,
          'consumidor_final', consumidor_final, 'presenca_comprador', presenca_comprador,
          'modalidade_frete', modalidade_frete, 'valor_frete', valor_frete,
          'valor_seguro', valor_seguro, 'valor_outras_despesas', valor_outras_despesas
        ),
        snapshot_cadastro_em = now(), updated_at = now()
    where id = v_sf.id;
  else
    update f.solicitacao_faturamento
    set emitente_snapshot = null, destinatario_snapshot = null,
        operacao_snapshot = null, snapshot_cadastro_em = null, updated_at = now()
    where id = v_sf.id;
  end if;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_pendencias) = 0,
    'solicitacao_id', v_sf.id,
    'cliente_id', v_sf.cliente_id,
    'rota_cliente', v_rota_cliente,
    'pendencias', v_pendencias
  );
end;
$function$;

comment on function f.fn_solicitacao_nfe_congelar_cadastro(uuid) is
  'Valida cliente, emitente, produto e dados fiscais/operacionais da solicitacao. Congela snapshots somente quando tudo estiver completo.';
revoke all on function f.fn_solicitacao_nfe_congelar_cadastro(uuid) from public, anon;
grant execute on function f.fn_solicitacao_nfe_congelar_cadastro(uuid) to authenticated, service_role;

create or replace function f.fn_nfe_preparar_documento_solicitacao(p_solicitacao_id uuid)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  referencia_externa text,
  status text,
  criado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_documento_id uuid := gen_random_uuid();
  v_referencia text;
  v_total_produtos numeric(15,2);
  v_total_desconto numeric(15,2);
  v_total_nota numeric(15,2);
  v_os_id integer;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para emitir esta solicitacao.';
  end if;

  v_referencia := 'NFEH-' || v_sf.id;
  perform pg_advisory_xact_lock(hashtextextended(v_referencia, 0));

  return query
  select dfe.documento_fiscal_id, dfe.solicitacao_id, dfe.referencia_externa, dfe.status, false
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id and dfe.empresa_id = v_sf.empresa_id and dfe.solicitacao_id = v_sf.id;
  if found then return; end if;

  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Solicitacao nao esta disponivel para emissao.';
  end if;
  if v_sf.snapshot_cadastro_em is null
     or jsonb_typeof(v_sf.emitente_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.destinatario_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.operacao_snapshot) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'Cadastro ainda nao foi validado e congelado nesta solicitacao.';
  end if;

  select
    round(coalesce(sum(si.quantidade * si.valor_unitario), 0), 2),
    round(coalesce(sum(si.valor_desconto), 0), 2),
    round(coalesce(sum(si.quantidade * si.valor_unitario - si.valor_desconto), 0), 2)
      + coalesce(v_sf.valor_frete, 0) + coalesce(v_sf.valor_seguro, 0) + coalesce(v_sf.valor_outras_despesas, 0),
    min(case when si.origem_tipo in ('OS','OV') and si.origem_id ~ '^[0-9]+$' then si.origem_id::integer end)
  into v_total_produtos, v_total_desconto, v_total_nota, v_os_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id;

  if not exists (select 1 from f.solicitacao_item si where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id) then
    raise exception using errcode = '22023', message = 'Solicitacao sem itens.';
  end if;

  insert into f.documento_fiscal (
    id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date,
    valor_total, valor_produtos, valor_frete, valor_seguro, valor_desconto, valor_outros,
    operacao, natureza, cliente_id, os_id_import, nfe_status, origem
  ) values (
    v_documento_id, v_sf.tenant_id, v_sf.empresa_id, 'PENDENTE:' || v_referencia, '55', current_date,
    v_total_nota, v_total_produtos, v_sf.valor_frete, v_sf.valor_seguro, v_total_desconto, v_sf.valor_outras_despesas,
    'SAIDA', 'PRODUTO', v_sf.cliente_id, v_os_id, 'RASCUNHO', 'EMITIDO'
  );

  insert into f.documento_fiscal_item (
    tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo,
    codigo, descricao, ncm, cfop, quantidade, unidade, valor_unitario,
    valor_total, item_id
  )
  select
    si.tenant_id, si.empresa_id, v_documento_id, si.ordem, 'PRODUTO',
    si.codigo_produto, si.descricao, si.ncm, si.cfop, si.quantidade, si.unidade, si.valor_unitario,
    round(si.quantidade * si.valor_unitario - si.valor_desconto, 2), si.item_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
  order by si.ordem, si.id;

  insert into f.documento_fiscal_emissao (
    documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
    referencia_externa, ambiente, status
  ) values (
    v_documento_id, v_sf.id, v_sf.tenant_id, v_sf.empresa_id,
    v_referencia, 'HOMOLOGACAO', 'RASCUNHO'
  );

  update f.solicitacao_faturamento set status = 'APROVADA', updated_at = now() where id = v_sf.id;
  return query select v_documento_id, v_sf.id, v_referencia, 'RASCUNHO'::text, true;
end;
$function$;

revoke all on function f.fn_nfe_preparar_documento_solicitacao(uuid) from public, anon;
grant execute on function f.fn_nfe_preparar_documento_solicitacao(uuid) to authenticated, service_role;

-- Contexto deliberadamente pequeno: nenhuma consulta ao cadastro, item fiscal
-- ou perfil pode alterar o JSON depois que a solicitacao foi congelada.
create or replace function f.fn_nfe_contexto_emissao_impl(p_documento_fiscal_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select jsonb_build_object(
    'emissao', to_jsonb(dfe),
    'documento', to_jsonb(df),
    'solicitacao', to_jsonb(sf),
    'itens', coalesce(it.itens, '[]'::jsonb)
  )
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id and df.empresa_id = dfe.empresa_id and df.id = dfe.documento_fiscal_id
  join f.solicitacao_faturamento sf
    on sf.tenant_id = dfe.tenant_id and sf.empresa_id = dfe.empresa_id and sf.id = dfe.solicitacao_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object('documento_item', to_jsonb(dfi), 'solicitacao_item', to_jsonb(si))
      order by si.ordem, si.id
    ) as itens
    from f.solicitacao_item si
    left join f.documento_fiscal_item dfi
      on dfi.tenant_id = si.tenant_id and dfi.empresa_id = si.empresa_id
     and dfi.documento_fiscal_id = df.id and dfi.item_n = si.ordem and dfi.deleted_at is null
    where si.tenant_id = sf.tenant_id and si.empresa_id = sf.empresa_id and si.solicitacao_id = sf.id
  ) it on true
  where dfe.documento_fiscal_id = p_documento_fiscal_id;
$function$;

drop function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text);

create function f.fn_nfe_aplicar_retorno(
  p_referencia_externa text,
  p_resposta jsonb,
  p_status text,
  p_chave_acesso text default null,
  p_protocolo text default null,
  p_numero integer default null,
  p_serie integer default null,
  p_codigo_status integer default null,
  p_mensagem text default null,
  p_xml_path text default null,
  p_danfe_path text default null,
  p_xml_raw text default null,
  p_origem_retorno text default 'CALLBACK'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_xml_hash text;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode aplicar retorno.';
  end if;
  if v_status not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'CANCELADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de retorno invalido.';
  end if;
  select * into v_emissao
  from f.documento_fiscal_emissao
  where referencia_externa = p_referencia_externa
  for update;
  if not found then raise exception using errcode = 'P0002', message = format('Referencia %s nao encontrada.', p_referencia_externa); end if;
  if v_emissao.ambiente <> 'HOMOLOGACAO' then
    raise exception using errcode = '42501', message = 'Este pipeline aplica retorno somente de HOMOLOGACAO.';
  end if;
  if v_emissao.status = 'AUTORIZADA' and v_status <> 'AUTORIZADA' then return v_emissao.documento_fiscal_id; end if;

  if v_status = 'AUTORIZADA' then
    if nullif(p_chave_acesso, '') is null or p_chave_acesso !~ '^[0-9]{44}$' then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem chave de acesso valida.';
    end if;
    if nullif(btrim(coalesce(p_xml_raw, '')), '') is null then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem XML para f.documento_fiscal_xml.';
    end if;
    v_xml_hash := encode(extensions.digest(convert_to(p_xml_raw, 'utf8'), 'sha256'), 'hex');
  end if;

  update f.documento_fiscal_emissao
  set status = v_status, resposta = coalesce(p_resposta, resposta),
      chave_acesso = coalesce(nullif(p_chave_acesso, ''), chave_acesso),
      protocolo = coalesce(nullif(p_protocolo, ''), protocolo),
      numero = coalesce(p_numero, numero), serie = coalesce(p_serie, serie),
      codigo_status = coalesce(p_codigo_status, codigo_status),
      mensagem = coalesce(nullif(p_mensagem, ''), mensagem),
      xml_path = coalesce(nullif(p_xml_path, ''), xml_path),
      danfe_path = coalesce(nullif(p_danfe_path, ''), danfe_path),
      callback_recebido_em = case when upper(p_origem_retorno) = 'CALLBACK' then now() else callback_recebido_em end,
      reconciliado_em = case when upper(p_origem_retorno) = 'RECONCILIACAO' then now() else reconciliado_em end,
      autorizado_em = case when v_status = 'AUTORIZADA' then coalesce(autorizado_em, now()) else autorizado_em end,
      updated_at = now()
  where documento_fiscal_id = v_emissao.documento_fiscal_id;

  if v_status = 'AUTORIZADA' then
    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_emissao.tenant_id, v_emissao.documento_fiscal_id, p_chave_acesso, p_xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id)
    do update set chave_acesso = excluded.chave_acesso, xml_raw = excluded.xml_raw,
                  xml_hash = excluded.xml_hash, deleted_at = null;

    -- A conversao integer -> text de numero/serie existe somente aqui.
    -- Em homologacao o documento permanece RASCUNHO para nao criar financeiro.
    update f.documento_fiscal
    set chave_acesso = p_chave_acesso,
        numero = coalesce(p_numero::text, numero),
        serie = coalesce(p_serie::text, serie),
        nfe_status = 'RASCUNHO',
        emissao_date = coalesce(emissao_date, current_date),
        updated_at = now()
    where tenant_id = v_emissao.tenant_id and empresa_id = v_emissao.empresa_id and id = v_emissao.documento_fiscal_id;

    update f.solicitacao_faturamento
    set status = 'EMITIDA', updated_at = now()
    where tenant_id = v_emissao.tenant_id and empresa_id = v_emissao.empresa_id and id = v_emissao.solicitacao_id;

    update f.documento_fiscal_item dfi
    set ncm = coalesce(dfi.ncm, nullif(x.item->>'codigo_ncm', '')),
        cfop = coalesce(nullif(x.item->>'cfop', ''), dfi.cfop),
        cst_icms = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 2 then x.item->>'icms_situacao_tributaria' else null end,
        csosn = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 3 then x.item->>'icms_situacao_tributaria' else null end,
        cst_ipi = nullif(x.item->>'ipi_situacao_tributaria', ''),
        cst_pis = nullif(x.item->>'pis_situacao_tributaria', ''),
        cst_cofins = nullif(x.item->>'cofins_situacao_tributaria', ''),
        cbenef = nullif(x.item->>'codigo_beneficio_fiscal', ''),
        reducao_base_icms_percentual = nullif(x.item->>'icms_reducao_base_calculo', '')::numeric,
        unidade_tributavel = nullif(x.item->>'unidade_tributavel', ''),
        snapshot_fiscal_em = coalesce(dfi.snapshot_fiscal_em, now()), updated_at = now()
    from jsonb_array_elements(coalesce((select payload_enviado from f.documento_fiscal_emissao where documento_fiscal_id = v_emissao.documento_fiscal_id)->'items', '[]'::jsonb)) x(item)
    where dfi.tenant_id = v_emissao.tenant_id and dfi.empresa_id = v_emissao.empresa_id
      and dfi.documento_fiscal_id = v_emissao.documento_fiscal_id
      and dfi.item_n = (x.item->>'numero_item')::integer;
  end if;
  return v_emissao.documento_fiscal_id;
end;
$function$;

revoke all on function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text) from public, anon, authenticated;
grant execute on function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text) to service_role;

create or replace function f.fn_nfe_emissoes_pendentes_reconciliacao(p_limite integer default 50)
returns table (documento_fiscal_id uuid, referencia_externa text, ambiente text)
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select dfe.documento_fiscal_id, dfe.referencia_externa, dfe.ambiente
  from f.documento_fiscal_emissao dfe
  where dfe.status = 'PROCESSANDO'
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.updated_at < now() - interval '10 minutes'
  order by dfe.updated_at
  limit least(greatest(coalesce(p_limite, 50), 1), 200);
$function$;

revoke all on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer) from public, anon, authenticated;
grant execute on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer) to service_role;

create or replace function f.fn_os_itens_saldo_a_faturar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns table (
  os_item_id integer,
  item_id integer,
  descricao text,
  quantidade_total numeric,
  quantidade_faturada numeric,
  saldo numeric,
  unidade text
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS/OV sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar o faturamento desta empresa.';
  end if;
  if not exists (
    select 1 from public.ordens_servico os
    where os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id
      and os.id = p_os_id and os.tipo_documento in ('OS', 'OV')
  ) then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  return query
  with reservado as (
    select si.origem_item_id, sum(si.quantidade) as quantidade
    from f.solicitacao_item si
    join f.solicitacao_faturamento sf
      on sf.tenant_id = si.tenant_id and sf.empresa_id = si.empresa_id and sf.id = si.solicitacao_id
    where si.tenant_id = p_tenant_id and si.empresa_id = p_empresa_id
      and si.origem_tipo in ('OS', 'OV') and si.origem_id = p_os_id::text
      and sf.status <> 'CANCELADA'
      and not exists (
        select 1
        from f.documento_fiscal_emissao dfe
        where dfe.tenant_id = sf.tenant_id and dfe.empresa_id = sf.empresa_id
          and dfe.solicitacao_id = sf.id
          and dfe.ambiente = 'HOMOLOGACAO' and dfe.status = 'AUTORIZADA'
      )
    group by si.origem_item_id
  )
  select
    oi.id,
    oi.item_id,
    coalesce(nullif(btrim(i.nome), ''), nullif(btrim(i.descricao), ''), format('Item %s', oi.item_id)),
    oi.quantidade::numeric,
    coalesce(r.quantidade, 0)::numeric,
    greatest(oi.quantidade - coalesce(r.quantidade, 0), 0)::numeric,
    nullif(btrim(i.unidade_medida), '')
  from public.os_itens oi
  join public.itens i
    on i.tenant_id = oi.tenant_id and i.empresa_id = oi.empresa_id and i.id = oi.item_id
  left join reservado r on r.origem_item_id = oi.id::text
  where oi.tenant_id = p_tenant_id and oi.empresa_id = p_empresa_id and oi.os_id = p_os_id
    and (oi.finalidade = 'venda' or oi.finalidade is null)
  order by oi.id;
end;
$function$;

comment on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) is
  'Reserva rascunhos/erros reais, mas uma NF-e AUTORIZADA em HOMOLOGACAO nao consome o saldo comercial da OS/OV.';

revoke all on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) from public, anon;
grant execute on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) to authenticated, service_role;

commit;
