-- Excecao "ICMS 12% por exigencia do destinatario".
--
-- Pedido do Gabriel em 16/09/2026, para a PORTOBELLO (PBG S/A): mercadoria de manutencao
-- vai a 17% (Lei 10.297/96, art. 19, § 3º), e a emissao para em "destinacao manutencao
-- exige aliquota interna de 17%, e a nota esta com 12%". O cliente contribuinte exige 12%
-- pela OC; o RICMS/SC-01, art. 26, III, "n", aplicado por determinacao dele, com a
-- responsabilidade solidaria pela diferenca do art. 26, § 6º.
--
-- Regras:
--   1. So para destinatario contribuinte (indIEDest = 1), operacao interna e destinacao
--      manutencao, uso e consumo ou ativo imobilizado.
--   2. Ativar exige numero da OC e evidencia (texto ou anexo do e-mail do cliente); grava
--      quem ativou e quando.
--   3. Com a excecao ativa: item sem cBenef SC820006 sai CST 00 a 12% sobre a base
--      integral; item com SC820006 segue a regra dele (CST 20, pRedBC 29,412); indFinal 1;
--      IPI nao muda (na manutencao continua dentro da base do ICMS).
--   4. O texto das informacoes complementares e a trava que vira confirmacao ficam no
--      montador (supabase/functions/_shared/nfe-payload.ts), que le a excecao do snapshot.
--   5. Relatorio mensal: f.fn_nfe_excecao_aliquota_relatorio.
--
-- A excecao e da SOLICITACAO (uma nota), nunca do cliente: cada OC precisa da propria
-- exigencia. O anexo fica no banco (bytea, ate 5 MB) porque o site nao tem upload para o
-- storage e o bucket nfe-documentos nao tem politica para o navegador.

create table if not exists f.nfe_excecao_aliquota_destinatario (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  solicitacao_id uuid not null references f.solicitacao_faturamento(id) on delete cascade,
  numero_oc text not null check (btrim(numero_oc) <> ''),
  evidencia_texto text,
  evidencia_arquivo_nome text,
  evidencia_arquivo_tipo text,
  evidencia_arquivo bytea,
  ativada_por uuid,
  ativada_em timestamptz not null default now(),
  desativada_por uuid,
  desativada_em timestamptz,
  constraint nfe_excecao_aliquota_evidencia check (
    nullif(btrim(coalesce(evidencia_texto, '')), '') is not null or evidencia_arquivo is not null
  ),
  constraint nfe_excecao_aliquota_arquivo_tamanho check (
    evidencia_arquivo is null or octet_length(evidencia_arquivo) <= 5242880
  ),
  constraint nfe_excecao_aliquota_arquivo_nome check (
    evidencia_arquivo is null or nullif(btrim(coalesce(evidencia_arquivo_nome, '')), '') is not null
  )
);

comment on table f.nfe_excecao_aliquota_destinatario is
  'Excecao ICMS 12% por exigencia do destinatario (RICMS/SC-01, art. 26, III, "n"), por solicitacao de NF-e. Uma ativa por solicitacao; desativar preserva o historico.';

create unique index if not exists nfe_excecao_aliquota_destinatario_ativa
  on f.nfe_excecao_aliquota_destinatario (solicitacao_id)
  where desativada_em is null;

alter table f.nfe_excecao_aliquota_destinatario enable row level security;
drop policy if exists nfe_excecao_aliquota_destinatario_leitura on f.nfe_excecao_aliquota_destinatario;
create policy nfe_excecao_aliquota_destinatario_leitura on f.nfe_excecao_aliquota_destinatario
  for select to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access(tenant_id, empresa_id)
  );
revoke all on f.nfe_excecao_aliquota_destinatario from anon, authenticated;
-- O arquivo fica fora do select direto: baixa-se pela funcao de evidencia.
grant select (id, tenant_id, empresa_id, solicitacao_id, numero_oc, evidencia_texto,
  evidencia_arquivo_nome, evidencia_arquivo_tipo, ativada_por, ativada_em, desativada_por, desativada_em)
  on f.nfe_excecao_aliquota_destinatario to authenticated;
grant all on f.nfe_excecao_aliquota_destinatario to service_role;

-- Por que a excecao nao cabe, ou null quando cabe. A mesma regra de
-- excecaoAliquota12Indisponivel no montador.
create or replace function f.fn_nfe_excecao_aliquota_indisponivel(
  p_indicador_ie text,
  p_destinacao text,
  p_interna boolean
)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case
    when coalesce(btrim(p_indicador_ie), '') <> '1' then
      format('Excecao de ICMS 12%% por exigencia do destinatario indisponivel: destinatario nao contribuinte (indIEDest %s).', coalesce(nullif(btrim(p_indicador_ie), ''), 'nao informado'))
    when not coalesce(p_interna, false) then
      'Excecao de ICMS 12% por exigencia do destinatario indisponivel: so vale em operacao interna.'
    when upper(coalesce(btrim(p_destinacao), '')) not in ('MANUTENCAO', 'USO_CONSUMO', 'ATIVO_IMOBILIZADO') then
      format('Excecao de ICMS 12%% por exigencia do destinatario indisponivel: vale so para manutencao, uso e consumo ou ativo imobilizado (destinacao %s).', coalesce(nullif(btrim(p_destinacao), ''), 'nao informada'))
    else null
  end;
$$;

-- Carrega a solicitacao para as funcoes de ativar e desativar: permissao, estado editavel
-- e emissao ainda corrigivel. Uso interno.
create or replace function f.fn_nfe_excecao_aliquota_solicitacao_editavel(p_solicitacao_id uuid)
returns f.solicitacao_faturamento
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao_status text;
begin
  select * into v_sf from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para alterar a excecao de ICMS desta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s: a excecao de ICMS nao pode mais ser alterada.', v_sf.status);
  end if;
  -- Homologacao autorizada nao trava: mudar a excecao so obriga a homologar de novo.
  -- Producao ja enviada, ou qualquer envio em andamento, trava.
  select e.status into v_emissao_status
  from f.documento_fiscal_emissao e
  where e.tenant_id = v_sf.tenant_id and e.empresa_id = v_sf.empresa_id and e.solicitacao_id = v_sf.id
    and (
      (e.ambiente = 'PRODUCAO' and e.status not in ('RASCUNHO', 'REJEITADA', 'ERRO'))
      or e.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'AUTORIZADA', 'CANCELADA')
    )
  order by e.created_at desc
  limit 1;
  if v_emissao_status is not null then
    raise exception using errcode = '55000', message = format('A NF-e desta solicitacao esta em %s; a excecao de ICMS nao pode mais ser alterada.', v_emissao_status);
  end if;
  return v_sf;
end;
$$;
revoke all on function f.fn_nfe_excecao_aliquota_solicitacao_editavel(uuid) from public, anon, authenticated;

create or replace function f.fn_nfe_excecao_aliquota_ativar(
  p_solicitacao_id uuid,
  p_numero_oc text,
  p_evidencia_texto text default null,
  p_arquivo_nome text default null,
  p_arquivo_tipo text default null,
  p_arquivo_base64 text default null,
  p_destinacao text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_sf f.solicitacao_faturamento%rowtype;
  v_cliente public.clientes%rowtype;
  v_uf_emitente text;
  v_destinacao text;
  v_motivo text;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_arquivo bytea;
  v_id uuid;
begin
  v_sf := f.fn_nfe_excecao_aliquota_solicitacao_editavel(p_solicitacao_id);

  if v_usuario_id is null and session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Usuario sem cadastro: a ativacao da excecao precisa registrar quem ativou.';
  end if;

  select c.* into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Destinatario da solicitacao nao encontrado.';
  end if;
  select upper(ee.uf::text) into v_uf_emitente
  from c.empresa_endereco ee
  where ee.empresa_id = v_sf.empresa_id and ee.tipo = 'FISCAL' and ee.deleted_at is null
  order by ee.created_at limit 1;

  -- A destinacao ainda pode estar so na tela (a conferencia da OV grava ao emitir); vale a
  -- informada, e o congelamento confere de novo contra a gravada.
  v_destinacao := upper(coalesce(nullif(btrim(p_destinacao), ''), v_sf.destinacao_mercadoria, ''));
  v_motivo := f.fn_nfe_excecao_aliquota_indisponivel(
    v_cliente.indicador_ie,
    v_destinacao,
    upper(coalesce(nullif(btrim(v_sf.destino_uf_confirmada), ''), v_cliente.uf, '')) = coalesce(v_uf_emitente, '')
  );
  if v_motivo is not null then
    raise exception using errcode = '22023', message = v_motivo;
  end if;

  if nullif(btrim(coalesce(p_numero_oc, '')), '') is null then
    raise exception using errcode = '22023', message = 'Informe o numero da OC do cliente: a nota cita a OC que determinou os 12%.';
  end if;
  if length(btrim(p_numero_oc)) > 60 then
    raise exception using errcode = '22023', message = 'Numero da OC com mais de 60 caracteres.';
  end if;
  if nullif(btrim(coalesce(p_arquivo_base64, '')), '') is not null then
    begin
      v_arquivo := decode(regexp_replace(p_arquivo_base64, '\s', '', 'g'), 'base64');
    exception when others then
      raise exception using errcode = '22023', message = 'O anexo da evidencia nao e um arquivo valido.';
    end;
    if octet_length(v_arquivo) > 5242880 then
      raise exception using errcode = '22023', message = 'O anexo da evidencia passa de 5 MB.';
    end if;
    if nullif(btrim(coalesce(p_arquivo_nome, '')), '') is null then
      raise exception using errcode = '22023', message = 'Informe o nome do anexo da evidencia.';
    end if;
  end if;
  if nullif(btrim(coalesce(p_evidencia_texto, '')), '') is null and v_arquivo is null then
    raise exception using errcode = '22023', message = 'Informe a evidencia: cole o texto do e-mail do cliente ou anexe o arquivo.';
  end if;

  update f.nfe_excecao_aliquota_destinatario ex
  set desativada_em = now(), desativada_por = v_usuario_id
  where ex.solicitacao_id = v_sf.id and ex.desativada_em is null;

  insert into f.nfe_excecao_aliquota_destinatario (
    tenant_id, empresa_id, solicitacao_id, numero_oc, evidencia_texto,
    evidencia_arquivo_nome, evidencia_arquivo_tipo, evidencia_arquivo, ativada_por
  ) values (
    v_sf.tenant_id, v_sf.empresa_id, v_sf.id, btrim(p_numero_oc),
    nullif(btrim(coalesce(p_evidencia_texto, '')), ''),
    case when v_arquivo is null then null else btrim(p_arquivo_nome) end,
    case when v_arquivo is null then null else nullif(btrim(coalesce(p_arquivo_tipo, '')), '') end,
    v_arquivo, v_usuario_id
  )
  returning id into v_id;

  -- A OC da excecao tambem e o pedido de compra da nota quando ele ainda nao existe.
  -- Snapshot invalidado: a conferencia precisa congelar de novo, agora com a excecao.
  update f.solicitacao_faturamento sf
  set pedido_cliente = coalesce(nullif(btrim(sf.pedido_cliente), ''), btrim(p_numero_oc)),
      emitente_snapshot = null, destinatario_snapshot = null,
      operacao_snapshot = null, snapshot_cadastro_em = null,
      updated_at = now()
  where sf.id = v_sf.id;

  return f.fn_nfe_excecao_aliquota_consultar(v_sf.id);
end;
$$;

create or replace function f.fn_nfe_excecao_aliquota_desativar(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_sf f.solicitacao_faturamento%rowtype;
  v_usuario_id uuid := a.fn_current_usuario_id();
begin
  v_sf := f.fn_nfe_excecao_aliquota_solicitacao_editavel(p_solicitacao_id);
  update f.nfe_excecao_aliquota_destinatario ex
  set desativada_em = now(), desativada_por = v_usuario_id
  where ex.solicitacao_id = v_sf.id and ex.desativada_em is null;
  if found then
    update f.solicitacao_faturamento sf
    set emitente_snapshot = null, destinatario_snapshot = null,
        operacao_snapshot = null, snapshot_cadastro_em = null,
        updated_at = now()
    where sf.id = v_sf.id;
  end if;
  return jsonb_build_object('ativa', false, 'solicitacao_id', v_sf.id);
end;
$$;

-- Estado da excecao para a tela: disponibilidade (sem a destinacao da tela, o que der para
-- dizer pelo cadastro) e a excecao ativa, sem o conteudo do anexo.
create or replace function f.fn_nfe_excecao_aliquota_consultar(p_solicitacao_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_indicador text;
  v_ativa jsonb;
begin
  select * into v_sf from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar esta NF-e.';
  end if;
  select c.indicador_ie into v_indicador
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id;

  select jsonb_build_object(
    'id', ex.id, 'numero_oc', ex.numero_oc, 'evidencia_texto', ex.evidencia_texto,
    'evidencia_arquivo_nome', ex.evidencia_arquivo_nome,
    'evidencia_arquivo_tamanho', octet_length(ex.evidencia_arquivo),
    'ativada_em', ex.ativada_em, 'ativada_por', ex.ativada_por,
    'ativada_por_nome', coalesce(u.nome, u.email)
  ) into v_ativa
  from f.nfe_excecao_aliquota_destinatario ex
  left join a.usuario u on u.id = ex.ativada_por
  where ex.solicitacao_id = v_sf.id and ex.desativada_em is null;

  return jsonb_build_object(
    'solicitacao_id', v_sf.id,
    'indicador_ie', v_indicador,
    'destinatario_contribuinte', coalesce(btrim(v_indicador), '') = '1',
    'pedido_cliente', v_sf.pedido_cliente,
    'ativa', v_ativa is not null,
    'excecao', v_ativa
  );
end;
$$;

-- Baixa o anexo da evidencia (qualquer versao, ativa ou nao) em base64.
create or replace function f.fn_nfe_excecao_aliquota_evidencia(p_excecao_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_ex f.nfe_excecao_aliquota_destinatario%rowtype;
begin
  select * into v_ex from f.nfe_excecao_aliquota_destinatario ex where ex.id = p_excecao_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Excecao de ICMS nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_ex.tenant_id
    or public.current_empresa_id() is distinct from v_ex.empresa_id
    or not f.has_finance_access(v_ex.tenant_id, v_ex.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para baixar esta evidencia.';
  end if;
  return jsonb_build_object(
    'nome', v_ex.evidencia_arquivo_nome,
    'tipo', coalesce(v_ex.evidencia_arquivo_tipo, 'application/octet-stream'),
    'base64', case when v_ex.evidencia_arquivo is null then null else encode(v_ex.evidencia_arquivo, 'base64') end,
    'texto', v_ex.evidencia_texto
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Congelamento: a excecao ativa vai para o snapshot da operacao, e vira pendencia
-- quando nao cabe mais (destinatario, destinacao ou UF mudaram).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
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
  v_excecao_motivo text;
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
    if v_fiscal.id is null or v_fiscal.serie_nfe is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','serie_nfe','mensagem','Serie da NF-e do emitente nao informada.','rota','/configuracoes'));
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
  if nullif(btrim(v_sf.destinacao_mercadoria), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','destinacao_mercadoria','mensagem','Destinacao da mercadoria nao confirmada; ela decide a aliquota interna de ICMS.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if nullif(btrim(v_sf.pagamento_forma), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_forma','mensagem','Forma de pagamento nao confirmada; sem ela o provedor assume dinheiro.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.pagamento_indicador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_indicador','mensagem','Indicador de pagamento (a vista ou a prazo) nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;

  -- Excecao ICMS 12% por exigencia do destinatario: continua cabendo nesta nota?
  if exists (
    select 1 from f.nfe_excecao_aliquota_destinatario ex
    where ex.solicitacao_id = v_sf.id and ex.desativada_em is null
  ) then
    v_excecao_motivo := f.fn_nfe_excecao_aliquota_indisponivel(
      v_cliente.indicador_ie,
      v_sf.destinacao_mercadoria,
      upper(coalesce(v_sf.destino_uf_confirmada, v_cliente.uf, '')) = upper(coalesce(v_endereco.uf::text, ''))
    );
    if v_excecao_motivo is not null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','excecao_aliquota_destinatario','mensagem',v_excecao_motivo || ' Desative a excecao ou corrija a conferencia.','rota','/faturamento/solicitacoes/' || v_sf.id));
    end if;
  end if;

  if jsonb_array_length(v_pendencias) = 0 then
    update f.solicitacao_faturamento
    set emitente_snapshot = jsonb_build_object(
          'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
          'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
          'telefone', v_empresa.telefone, 'inscricao_estadual', v_fiscal.inscricao_estadual,
          'crt', v_fiscal.crt, 'serie_nfe', v_fiscal.serie_nfe,
          'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero,
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
          'valor_seguro', valor_seguro, 'valor_outras_despesas', valor_outras_despesas,
          'destinacao_mercadoria', destinacao_mercadoria,
          'pagamento', jsonb_build_object(
            'forma', pagamento_forma,
            'indicador', pagamento_indicador,
            'descricao', pagamento_descricao,
            'parcelas', case when pagamento_indicador = 1 then pagamento_parcelas else null end,
            'fatura_numero', (
              select os.codigo
              from f.solicitacao_item si
              join public.ordens_servico os on os.id::text = si.origem_id
              where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id
                and si.solicitacao_id = v_sf.id and si.origem_tipo = 'OV'
              order by si.ordem limit 1
            )
          )
        ) || coalesce((
          -- Chave so existe com a excecao ativa: snapshot de nota sem excecao nao muda.
          select jsonb_build_object('excecao_aliquota_destinatario', jsonb_build_object(
            'id', ex.id, 'numero_oc', ex.numero_oc, 'ativada_em', ex.ativada_em
          ))
          from f.nfe_excecao_aliquota_destinatario ex
          where ex.solicitacao_id = v_sf.id and ex.desativada_em is null
        ), '{}'::jsonb),
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

-- ---------------------------------------------------------------------------
-- Conferencia da OV: com a excecao, ICMS dos itens sem SC820006 e o indFinal deixam
-- de ser campos travados pelo perfil e passam a ter o valor fixo da excecao.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_salvar_conferencia(p_solicitacao_id uuid, p_operacao jsonb, p_itens jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_item record;
  v_total_itens integer;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_destino_uf text := upper(btrim(coalesce(p_operacao->>'destino_uf_confirmada', '')));
  v_resolucao jsonb;
  v_resolvido jsonb;
  v_perfil f.perfil_operacao%rowtype;
  v_fiscal_item public.fiscal_itens%rowtype;
  v_perfil_esperado uuid;
  v_cfop_esperado text;
  v_ambito text;
  v_perfis_distintos integer;
  v_perfil_unico uuid;
  v_cst_ipi text;
  v_cenq_ipi text;
  v_aliquota_ipi numeric;
  v_ipi_fonte text;
  v_parcelas jsonb;
  v_excecao boolean;
  v_item_excecao boolean;
  v_excecao_motivo text;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Rascunho de NF-e nao encontrado.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Esta solicitacao nao pode mais ser alterada.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
  order by case when dfe.ambiente = 'PRODUCAO' then 0 else 1 end,
           dfe.created_at desc, dfe.documento_fiscal_id
  limit 1
  for update;
  if found and v_emissao.status not in ('REJEITADA', 'ERRO', 'RASCUNHO') then
    raise exception using errcode = '22023', message = 'Somente uma emissao rejeitada, com erro ou ainda em rascunho pode ser corrigida.';
  end if;
  if jsonb_typeof(p_operacao) <> 'object' or jsonb_typeof(p_itens) <> 'array' then
    raise exception using errcode = '22023', message = 'Operacao e itens da conferencia sao obrigatorios.';
  end if;
  if v_destino_uf !~ '^[A-Z]{2}$' then
    raise exception using errcode = '22023', message = 'A UF de destino precisa ser confirmada antes da conferencia fiscal.';
  end if;
  if nullif(btrim(p_operacao->>'finalidade_emissao'), '') is null
     or nullif(btrim(p_operacao->>'consumidor_final'), '') is null
     or nullif(btrim(p_operacao->>'presenca_comprador'), '') is null
     or nullif(btrim(p_operacao->>'modalidade_frete'), '') is null
     or nullif(btrim(p_operacao->>'valor_frete'), '') is null
     or nullif(btrim(p_operacao->>'valor_seguro'), '') is null
     or nullif(btrim(p_operacao->>'valor_outras_despesas'), '') is null then
    raise exception using errcode = '22023', message = 'Finalidade, consumidor, presenca, frete, seguro e outras despesas devem ser confirmados explicitamente.';
  end if;

  -- Forma de pagamento (grupo YA / detPag). Sem ela o provedor preenchia o
  -- default dele, e a nota saia declarando tPag 01 (dinheiro) para venda a
  -- prazo. Agora e confirmacao explicita, como frete e transportadora.
  -- Destinacao declarada pelo destinatario (vem da OC do cliente). Decide a
  -- aliquota interna e vai para as informacoes complementares da nota.
  if nullif(btrim(p_operacao->>'destinacao_mercadoria'), '') is null then
    raise exception using errcode = '22023', message = 'Informe a destinacao da mercadoria: ela decide a aliquota interna de ICMS.';
  end if;

  if nullif(btrim(p_operacao->>'pagamento_forma'), '') is null
     or nullif(btrim(p_operacao->>'pagamento_indicador'), '') is null then
    raise exception using errcode = '22023', message = 'A forma de pagamento e o indicador (a vista ou a prazo) devem ser confirmados em cada nota.';
  end if;
  if btrim(p_operacao->>'pagamento_forma') !~ '^(0[1-5]|1[0-9]|2[0-4]|9[019])$' then
    raise exception using errcode = '22023', message = 'Forma de pagamento fora da tabela da NF-e (tPag).';
  end if;
  if (p_operacao->>'pagamento_indicador')::smallint not in (0, 1) then
    raise exception using errcode = '22023', message = 'Indicador de pagamento deve ser 0 (a vista) ou 1 (a prazo).';
  end if;
  -- Parcelas (grupo cobr/dup da NF-e e parcelas do titulo AR). Cada parcela
  -- e "dias apos a emissao" + valor; a data absoluta so existe na emissao.
  -- A prazo sem parcelas informadas recebe o padrao historico do AR: 1 parcela
  -- em 15 dias com o total. Valor nulo em parcela unica significa "o total".
  if (p_operacao->>'pagamento_indicador')::smallint = 1 then
    v_parcelas := f.fn_nfe_normalizar_parcelas(p_operacao->'pagamento_parcelas');
  else
    v_parcelas := null;
  end if;

  -- xPag e obrigatorio quando tPag = 99 (outros).
  if btrim(p_operacao->>'pagamento_forma') = '99'
     and nullif(btrim(p_operacao->>'pagamento_descricao'), '') is null then
    raise exception using errcode = '22023', message = 'Descreva a forma de pagamento quando escolher 99 (outros).';
  end if;

  v_resolucao := f.fn_solicitacao_nfe_resolver_perfis(
    v_sf.id, v_destino_uf, btrim(p_operacao->>'destinacao_mercadoria')
  );
  if not coalesce((v_resolucao->>'ok')::boolean, false) then
    raise exception using errcode = '22023', message = coalesce(v_resolucao->>'bloqueio', 'Destino fiscal invalido.');
  end if;
  v_ambito := v_resolucao->>'ambito';

  -- Excecao ICMS 12% por exigencia do destinatario: itens sem SC820006 saem CST 00 a 12%
  -- sobre a base integral, e o indFinal fica 1 mesmo que o perfil diga outra coisa.
  v_excecao := exists (
    select 1 from f.nfe_excecao_aliquota_destinatario ex
    where ex.solicitacao_id = v_sf.id and ex.desativada_em is null
  );
  if v_excecao then
    v_excecao_motivo := f.fn_nfe_excecao_aliquota_indisponivel(
      (select c.indicador_ie from public.clientes c where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id),
      btrim(p_operacao->>'destinacao_mercadoria'),
      v_ambito = 'INTERNA'
    );
    if v_excecao_motivo is not null then
      raise exception using errcode = '22023', message = v_excecao_motivo || ' Desative a excecao ou corrija a conferencia.';
    end if;
    if nullif(btrim(p_operacao->>'consumidor_final'), '')::smallint is distinct from 1 then
      raise exception using errcode = '22023', message = 'A excecao de ICMS 12% por exigencia do destinatario mantem o consumidor final = 1.';
    end if;
  end if;

  select count(*) into v_total_itens
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;
  if v_total_itens = 0
     or jsonb_array_length(p_itens) <> v_total_itens
     or (select count(distinct x.id) from jsonb_to_recordset(p_itens) x(id uuid)) <> v_total_itens then
    raise exception using errcode = '22023', message = 'A conferencia deve conter todas as linhas da solicitacao, sem duplicidade.';
  end if;

  update f.solicitacao_faturamento
  set finalidade_emissao = nullif(p_operacao->>'finalidade_emissao', '')::smallint,
      consumidor_final = nullif(p_operacao->>'consumidor_final', '')::smallint,
      presenca_comprador = nullif(p_operacao->>'presenca_comprador', '')::smallint,
      modalidade_frete = nullif(p_operacao->>'modalidade_frete', '')::smallint,
      valor_frete = nullif(p_operacao->>'valor_frete', '')::numeric,
      valor_seguro = nullif(p_operacao->>'valor_seguro', '')::numeric,
      valor_outras_despesas = nullif(p_operacao->>'valor_outras_despesas', '')::numeric,
      destinacao_mercadoria = btrim(p_operacao->>'destinacao_mercadoria'),
      pagamento_forma = btrim(p_operacao->>'pagamento_forma'),
      pagamento_indicador = (p_operacao->>'pagamento_indicador')::smallint,
      pagamento_descricao = nullif(btrim(p_operacao->>'pagamento_descricao'), ''),
      pagamento_parcelas = v_parcelas,
      destino_uf_confirmada = v_destino_uf,
      destino_confirmado_em = now(),
      destino_confirmado_por = v_usuario_id,
      perfil_aplicado_em = now(),
      perfil_aplicado_por = v_usuario_id,
      revisao_fiscal_confirmada_em = case when v_usuario_id is null then null else now() end,
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null, destinatario_snapshot = null,
      operacao_snapshot = null, snapshot_cadastro_em = null,
      status = 'PREVIA', updated_at = now()
  where tenant_id = v_sf.tenant_id
    and empresa_id = v_sf.empresa_id
    and id = v_sf.id;

  for v_item in
    select *
    from jsonb_to_recordset(p_itens) as x(
      id uuid, perfil_operacao_id uuid, cfop text, cst_icms text, csosn text,
      cst_ipi text, ipi_codigo_enquadramento_legal text, cst_pis text,
      cst_cofins text, cbenef text, reducao_base_icms_percentual numeric,
      icms_modalidade_base_calculo text, aliquota_icms numeric, aliquota_ipi numeric,
      aliquota_pis numeric, aliquota_cofins numeric, cst_ibs_cbs text,
      cclass_trib text, cclass_trib_versao text, ibs_cbs_json jsonb,
      numero_fci text
    )
  loop
    select x.value into v_resolvido
    from jsonb_array_elements(v_resolucao->'itens') x(value)
    where x.value->>'solicitacao_item_id' = v_item.id::text;
    if v_resolvido is null then
      raise exception using errcode = '22023', message = format('Item %s nao pertence a esta solicitacao.', v_item.id);
    end if;
    if v_resolvido->>'status' is distinct from 'RESOLVIDO' then
      raise exception using errcode = '22023', message = coalesce(
        v_resolvido->>'motivo',
        format('O perfil fiscal do item %s nao foi resolvido pelo servidor.', v_item.id)
      );
    end if;

    v_perfil_esperado := nullif(v_resolvido->>'perfil_id', '')::uuid;
    if v_item.perfil_operacao_id is distinct from v_perfil_esperado then
      raise exception using errcode = '22023', message = format('O perfil fiscal do item %s nao corresponde ao perfil resolvido pelo servidor.', v_item.id);
    end if;

    select fi.* into v_fiscal_item
    from f.solicitacao_item si
    join public.fiscal_itens fi
      on fi.tenant_id = si.tenant_id
     and fi.empresa_id = si.empresa_id
     and fi.item_id = si.item_id
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item.id;
    if not found then
      raise exception using errcode = '22023', message = format('O item %s nao possui cadastro fiscal do produto.', v_item.id);
    end if;
    if nullif(btrim(v_item.numero_fci), '') is distinct from nullif(btrim(v_fiscal_item.numero_fci), '') then
      raise exception using errcode = '22023', message = format('O numero da FCI do item %s deve vir do cadastro fiscal do produto.', v_item.id);
    end if;

    v_cst_ipi := nullif(btrim(v_resolvido#>>'{ipi_operacao,cst}'), '');
    v_cenq_ipi := nullif(regexp_replace(coalesce(v_resolvido#>>'{ipi_operacao,c_enq}', ''), '[^0-9]', '', 'g'), '');
    v_aliquota_ipi := nullif(v_resolvido#>>'{ipi_operacao,aliquota}', '')::numeric;
    v_ipi_fonte := nullif(v_resolvido#>>'{ipi_operacao,fonte}', '');
    if not f.fn_nfe_cenq_compativel(v_cst_ipi, v_cenq_ipi) then
      raise exception using errcode = '22023', message = format(
        'Item %s: cEnq %s incompativel com CST IPI %s (rejeicao 388).',
        v_item.id, coalesce(v_cenq_ipi, '<vazio>'), coalesce(v_cst_ipi, '<vazio>')
      );
    end if;
    if nullif(btrim(v_item.cst_ipi), '') is distinct from v_cst_ipi
       or nullif(regexp_replace(coalesce(v_item.ipi_codigo_enquadramento_legal, ''), '[^0-9]', '', 'g'), '') is distinct from v_cenq_ipi
       or v_item.aliquota_ipi is distinct from v_aliquota_ipi then
      raise exception using errcode = '22023', message = format(
        'Item %s: CST IPI, cEnq e aliquota devem vir do perfil de operacao ou da fixture provisoria de homologacao.',
        v_item.id
      );
    end if;

    v_perfil := null;
    if v_perfil_esperado is not null then
      select * into v_perfil
      from f.perfil_operacao po
      where po.tenant_id = v_sf.tenant_id
        and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
        and po.id = v_perfil_esperado;
    end if;
    v_item_excecao := v_excecao and not (
      coalesce(v_perfil.cbenef_aplicacao, '') = 'COM_BENEFICIO' and coalesce(v_perfil.cbenef, '') = 'SC820006'
    );
    if v_item_excecao and (
      nullif(btrim(v_item.cst_icms), '') is distinct from '00'
      or nullif(btrim(v_item.csosn), '') is not null
      or v_item.aliquota_icms is distinct from 12
      or v_item.reducao_base_icms_percentual is distinct from 0
      or nullif(btrim(v_item.cbenef), '') is not null
    ) then
      raise exception using errcode = '22023', message = format(
        'Item %s: com a excecao de ICMS 12%% por exigencia do destinatario, o item sem cBenef SC820006 sai com CST 00 a 12%% sem reducao e sem cBenef.',
        v_item.id);
    end if;
    if v_perfil_esperado is not null then
      select * into v_perfil
      from f.perfil_operacao po
      where po.tenant_id = v_sf.tenant_id
        and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
        and po.id = v_perfil_esperado;
      v_cfop_esperado := case when v_ambito = 'INTERNA' then v_perfil.cfop_interno else v_perfil.cfop_externo end;

      if nullif(regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g'), '') is distinct from v_cfop_esperado
         or (not v_item_excecao and nullif(btrim(v_item.cst_icms), '') is distinct from v_perfil.cst_icms)
         or nullif(btrim(v_item.csosn), '') is distinct from v_perfil.csosn
         or (v_perfil.icms_modalidade_base_calculo is not null and nullif(btrim(v_item.icms_modalidade_base_calculo), '') is distinct from v_perfil.icms_modalidade_base_calculo)
         or (not v_item_excecao and v_perfil.aliquota_icms is not null and v_item.aliquota_icms is distinct from v_perfil.aliquota_icms)
         or (not v_item_excecao and v_perfil.reducao_base_icms_percentual is not null and v_item.reducao_base_icms_percentual is distinct from v_perfil.reducao_base_icms_percentual)
         or (v_perfil.cst_pis is not null and nullif(btrim(v_item.cst_pis), '') is distinct from v_perfil.cst_pis)
         or (v_perfil.cst_cofins is not null and nullif(btrim(v_item.cst_cofins), '') is distinct from v_perfil.cst_cofins)
         or (v_perfil.aliquota_pis is not null and v_item.aliquota_pis is distinct from v_perfil.aliquota_pis)
         or (v_perfil.aliquota_cofins is not null and v_item.aliquota_cofins is distinct from v_perfil.aliquota_cofins)
         or (v_perfil.cbenef_aplicacao = 'SEM_BENEFICIO' and nullif(btrim(v_item.cbenef), '') is not null)
         or (not v_item_excecao and v_perfil.cbenef_aplicacao = 'COM_BENEFICIO' and nullif(btrim(v_item.cbenef), '') is distinct from v_perfil.cbenef)
         or (v_perfil.cst_ibs_cbs is not null and nullif(regexp_replace(coalesce(v_item.cst_ibs_cbs, ''), '[^0-9]', '', 'g'), '') is distinct from v_perfil.cst_ibs_cbs)
         or (v_perfil.cclass_trib is not null and nullif(regexp_replace(coalesce(v_item.cclass_trib, ''), '[^0-9]', '', 'g'), '') is distinct from v_perfil.cclass_trib)
         or (v_perfil.cclass_trib_versao is not null and nullif(btrim(v_item.cclass_trib_versao), '') is distinct from v_perfil.cclass_trib_versao)
         or (v_perfil.ibs_cbs_json ? 'ibs_uf_aliquota' and (v_item.ibs_cbs_json->>'ibs_uf_aliquota')::numeric is distinct from (v_perfil.ibs_cbs_json->>'ibs_uf_aliquota')::numeric)
         or (v_perfil.ibs_cbs_json ? 'ibs_mun_aliquota' and (v_item.ibs_cbs_json->>'ibs_mun_aliquota')::numeric is distinct from (v_perfil.ibs_cbs_json->>'ibs_mun_aliquota')::numeric)
         or (v_perfil.ibs_cbs_json ? 'cbs_aliquota' and (v_item.ibs_cbs_json->>'cbs_aliquota')::numeric is distinct from (v_perfil.ibs_cbs_json->>'cbs_aliquota')::numeric) then
        raise exception using errcode = '22023', message = format('Um campo bloqueado do perfil %s foi alterado no item %s.', v_perfil.codigo, v_item.id);
      end if;
      if v_perfil.finalidade_emissao is not null
         and (p_operacao->>'finalidade_emissao')::smallint is distinct from v_perfil.finalidade_emissao then
        raise exception using errcode = '22023', message = format('A finalidade deve permanecer igual ao perfil %s.', v_perfil.codigo);
      end if;
      if v_perfil.consumidor_final is not null
         and not v_excecao
         and (p_operacao->>'consumidor_final')::smallint is distinct from v_perfil.consumidor_final then
        raise exception using errcode = '22023', message = format('O consumidor final deve permanecer igual ao perfil %s.', v_perfil.codigo);
      end if;
    end if;

    if v_item.reducao_base_icms_percentual is null then
      raise exception using errcode = '22023', message = 'A reducao da base de ICMS deve ser confirmada em cada item; informe zero quando nao houver reducao.';
    end if;
    if v_item.reducao_base_icms_percentual not between 0 and 100 then
      raise exception using errcode = '22023', message = 'Reducao da base de ICMS deve estar entre 0 e 100.';
    end if;
    if nullif(btrim(v_item.cst_ibs_cbs), '') is null
       or nullif(btrim(v_item.cclass_trib), '') is null
       or nullif(btrim(v_item.cclass_trib_versao), '') is null
       or jsonb_typeof(v_item.ibs_cbs_json) is distinct from 'object'
       or v_item.ibs_cbs_json->>'ibs_uf_aliquota' is null
       or v_item.ibs_cbs_json->>'ibs_mun_aliquota' is null
       or v_item.ibs_cbs_json->>'cbs_aliquota' is null then
      raise exception using errcode = '22023', message = 'CST, cClassTrib, versao e aliquotas de IBS/CBS sao obrigatorios em cada item.';
    end if;

    update f.solicitacao_item si
    set perfil_operacao_id = v_perfil_esperado,
        perfil_aplicado_em = now(),
        perfil_aplicado_por = v_usuario_id,
        ncm = nullif(regexp_replace(coalesce(v_fiscal_item.ncm, ''), '[^0-9]', '', 'g'), ''),
        cest = nullif(regexp_replace(coalesce(v_fiscal_item.cest, ''), '[^0-9]', '', 'g'), ''),
        origem_mercadoria = v_fiscal_item.origem,
        unidade_tributavel = nullif(btrim(v_fiscal_item.unidade_tributavel), ''),
        cfop = nullif(regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g'), ''),
        cst_icms = nullif(btrim(v_item.cst_icms), ''),
        csosn = nullif(btrim(v_item.csosn), ''),
        cst_ipi = v_cst_ipi,
        ipi_codigo_enquadramento_legal = v_cenq_ipi,
        ipi_fonte = v_ipi_fonte,
        cst_pis = nullif(btrim(v_item.cst_pis), ''),
        cst_cofins = nullif(btrim(v_item.cst_cofins), ''),
        cbenef = nullif(btrim(v_item.cbenef), ''),
        reducao_base_icms_percentual = v_item.reducao_base_icms_percentual,
        icms_modalidade_base_calculo = nullif(btrim(v_item.icms_modalidade_base_calculo), ''),
        aliquota_icms = v_item.aliquota_icms,
        aliquota_ipi = v_aliquota_ipi,
        aliquota_pis = v_item.aliquota_pis,
        aliquota_cofins = v_item.aliquota_cofins,
        numero_fci = nullif(btrim(v_fiscal_item.numero_fci), ''),
        cst_ibs_cbs = nullif(regexp_replace(coalesce(v_item.cst_ibs_cbs, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib = nullif(regexp_replace(coalesce(v_item.cclass_trib, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib_versao = nullif(btrim(v_item.cclass_trib_versao), ''),
        ibs_cbs_json = v_item.ibs_cbs_json
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item.id;
  end loop;

  select count(distinct si.perfil_operacao_id),
         (array_agg(distinct si.perfil_operacao_id) filter (where si.perfil_operacao_id is not null))[1]
    into v_perfis_distintos, v_perfil_unico
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  update f.solicitacao_faturamento sf
  set perfil_operacao_id = case
        when v_perfis_distintos = 1
         and not exists (
           select 1 from f.solicitacao_item x
           where x.tenant_id = sf.tenant_id
             and x.empresa_id = sf.empresa_id
             and x.solicitacao_id = sf.id
             and x.perfil_operacao_id is null
         ) then v_perfil_unico
        else null
      end
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  if v_emissao.documento_fiscal_id is not null then
    update f.documento_fiscal_emissao
    set status = 'RASCUNHO', codigo_status = null, mensagem = null, updated_at = now()
    where tenant_id = v_sf.tenant_id
      and empresa_id = v_sf.empresa_id
      and documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'solicitacao_id', v_sf.id, 'itens', v_total_itens,
    'destino_uf_confirmada', v_destino_uf,
    'perfil_operacao_id', case when v_perfis_distintos = 1 then v_perfil_unico else null end
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Conferencia da OS (itens FAB, CFOP 5101).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f.fn_os_nfe_conferir_homologacao(p_solicitacao_id uuid, p_operacao jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_tipi_aliquota numeric;
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_os public.ordens_servico%rowtype;
  v_cliente public.clientes%rowtype;
  v_uf_emitente text;
  v_ambito text;
  v_cfop text;
  v_natureza text;
  v_fx f.tributacao_provisoria_homologacao%rowtype;
  v_destinacao text;
  v_destino_uf text;
  v_consumidor_final smallint;
  v_aliquota numeric;
  v_item record;
  v_fi public.fiscal_itens%rowtype;
  v_item_cad public.itens%rowtype;
  v_total numeric(14,2);
  v_saldo record;
  v_reserva_propria numeric(14,2);
  v_parcelas jsonb;
  v_transportador jsonb;
  v_volumes jsonb;
  v_volume jsonb;
  v_indice integer := 0;
  v_modalidade smallint;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_emissao_status text;
  v_linhas integer := 0;
  v_po f.perfil_operacao%rowtype;
  v_po_id uuid;
  v_po_unico uuid;
  v_po_misto boolean := false;
  v_crt text;
  v_fonte text;
  v_excecao boolean;
  v_excecao_motivo text;
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
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s nao pode ser conferida.', v_sf.status);
  end if;

  select e.status into v_emissao_status
  from f.documento_fiscal_emissao e
  where e.tenant_id = v_sf.tenant_id and e.empresa_id = v_sf.empresa_id and e.solicitacao_id = v_sf.id
  order by e.created_at desc limit 1;
  if v_emissao_status is not null and v_emissao_status not in ('RASCUNHO', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '55000', message = format('A NF-e desta solicitacao ja esta em %s; a conferencia nao pode mais ser alterada.', v_emissao_status);
  end if;

  -- Origem: todas as linhas de uma OS (nao OV).
  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id
    and os.tipo_documento = 'OS'
    and os.id::text = (
      select si.origem_id from f.solicitacao_item si
      where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
        and si.origem_tipo = 'OS'
      order by si.ordem limit 1
    );
  if not found then
    raise exception using errcode = '22023', message = 'Esta conferencia e exclusiva de solicitacoes originadas de OS.';
  end if;
  if lower(coalesce(v_os.status_fluxo, v_os.status, '')) = 'cancelada' then
    raise exception using errcode = '22023', message = format('A OS %s esta cancelada e nao pode ser faturada.', coalesce(v_os.numero_os, v_os.id::text));
  end if;

  select c.* into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Destinatario da OS nao encontrado nesta empresa.';
  end if;
  if exists (
    select 1 from public.empresas e
    where e.tenant_id = v_sf.tenant_id
      and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') <> ''
      and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') = regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g')
  ) then
    raise exception using errcode = '22023', message = 'OS interna (cliente e uma empresa do grupo) nao emite NF-e por este fluxo.';
  end if;

  select upper(ee.uf::text) into v_uf_emitente
  from c.empresa_endereco ee
  where ee.empresa_id = v_sf.empresa_id and ee.tipo = 'FISCAL' and ee.deleted_at is null
  order by ee.created_at limit 1;
  if v_uf_emitente is null then
    raise exception using errcode = '22023', message = 'A UF fiscal do emitente nao esta cadastrada.';
  end if;

  -- Destino confirmado pela pessoa, conferido contra o cadastro do cliente.
  v_destino_uf := upper(btrim(coalesce(p_operacao->>'destino_uf_confirmada', '')));
  if v_destino_uf = '' then
    raise exception using errcode = '22023', message = 'Confirme a UF de destino da mercadoria.';
  end if;
  if v_destino_uf is distinct from upper(btrim(coalesce(v_cliente.uf, ''))) then
    raise exception using errcode = '22023', message = format(
      'UF confirmada (%s) diverge da UF do cadastro do cliente (%s). Corrija em /clientes/cadastro-fiscal?cliente_id=%s.',
      v_destino_uf, coalesce(v_cliente.uf, '<vazia>'), v_cliente.id);
  end if;
  v_ambito := case when v_destino_uf = v_uf_emitente then 'INTERNA' else 'INTERESTADUAL' end;
  select ef.crt::text into v_crt from c.empresa_fiscal ef where ef.empresa_id = v_sf.empresa_id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  v_cfop := case when v_ambito = 'INTERNA' then '5101' else '6101' end;
  v_natureza := case when v_ambito = 'INTERNA' then 'VENDA_INDUSTRIALIZACAO_INTERNA' else 'VENDA_INDUSTRIALIZACAO_INTERESTADUAL' end;
  if v_ambito = 'INTERESTADUAL' and coalesce(v_cliente.indicador_ie, '') <> '1' then
    raise exception using errcode = '22023', message = 'Operacao interestadual para nao contribuinte exige perfil proprio de DIFAL; nao ha fixture para isso.';
  end if;

  select * into v_fx
  from f.tributacao_provisoria_homologacao t
  where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.cfop = v_cfop and t.ativo;
  -- Sem fixture nao e erro se todas as linhas resolverem um perfil vigente (validado por linha).

  -- Destinacao declarada pelo destinatario: decide a aliquota interna.
  v_destinacao := upper(btrim(coalesce(p_operacao->>'destinacao_mercadoria', '')));
  if v_destinacao not in ('REVENDA', 'INSUMO', 'MANUTENCAO', 'CONSIGNADO', 'USO_CONSUMO', 'ATIVO_IMOBILIZADO') then
    raise exception using errcode = '22023', message = 'Informe a destinacao da mercadoria: ela decide a aliquota interna de ICMS.';
  end if;
  v_consumidor_final := case when v_destinacao in ('USO_CONSUMO', 'ATIVO_IMOBILIZADO') then 1 else 0 end;

  -- Operacao: presenca, frete, pagamento e parcelas (mesmas regras da OV).
  if nullif(btrim(coalesce(p_operacao->>'presenca_comprador', '')), '') is null
     or (p_operacao->>'presenca_comprador')::smallint not in (1, 2, 3, 4, 5, 9) then
    raise exception using errcode = '22023', message = 'Presenca do comprador deve ser 1 a 5 ou 9 em venda normal.';
  end if;
  if nullif(btrim(coalesce(p_operacao->>'pagamento_forma', '')), '') is null
     or btrim(p_operacao->>'pagamento_forma') !~ '^(0[1-5]|1[0-9]|2[0-4]|9[019])$' then
    raise exception using errcode = '22023', message = 'Forma de pagamento (tPag) invalida ou nao confirmada.';
  end if;
  if nullif(btrim(coalesce(p_operacao->>'pagamento_indicador', '')), '') is null
     or (p_operacao->>'pagamento_indicador')::smallint not in (0, 1) then
    raise exception using errcode = '22023', message = 'Indicador de pagamento deve ser 0 (a vista) ou 1 (a prazo).';
  end if;
  if btrim(p_operacao->>'pagamento_forma') = '99'
     and nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), '') is null then
    raise exception using errcode = '22023', message = 'Descreva a forma de pagamento quando escolher 99 (outros).';
  end if;
  v_parcelas := case when (p_operacao->>'pagamento_indicador')::smallint = 1
    then f.fn_nfe_normalizar_parcelas(p_operacao->'pagamento_parcelas') else null end;

  -- Transporte. A tela de faturar a OS ja coletava transportadora e volumes, mas esta
  -- funcao os descartava (transportador_dados = null, volumes_dados = null) e so gravava
  -- a modalidade. O montador do payload, sem transportadora, rebaixa a nota para
  -- modalidade 9 — entao a NF-e saia "sem frete" mesmo com a transportadora na tela, sem
  -- avisar ninguem. Foi o que aconteceu na homologacao 2/46 da OS 319 (10/09/2026).
  --
  -- As regras sao as mesmas de f.fn_solicitacao_nfe_salvar_transporte, para os dois
  -- caminhos (OV e OS) gravarem a mesma coisa do mesmo jeito.
  v_modalidade := coalesce(nullif(p_operacao->>'modalidade_frete', '')::smallint, 9);
  v_transportador := p_operacao->'transportador';
  v_volumes := p_operacao->'volumes';
  if v_modalidade = 9 then
    v_transportador := null;
    v_volumes := null;
  else
    if v_transportador is null
       or jsonb_typeof(v_transportador) is distinct from 'object'
       or nullif(btrim(coalesce(v_transportador->>'nome', '')), '') is null then
      raise exception using errcode = '22023',
        message = 'Quando houver transporte, informe a transportadora.';
    end if;
    if jsonb_typeof(v_volumes) is distinct from 'array' or jsonb_array_length(v_volumes) = 0 then
      raise exception using errcode = '22023',
        message = 'Informe ao menos um volume quando houver transporte.';
    end if;
    for v_volume in select value from jsonb_array_elements(v_volumes)
    loop
      v_indice := v_indice + 1;
      -- especie, marca e numero sao opcionais (grupo vol X26 da NF-e).
      if jsonb_typeof(v_volume) is distinct from 'object'
         or nullif(btrim(coalesce(v_volume->>'quantidade', '')), '') is null
         or nullif(btrim(coalesce(v_volume->>'peso_liquido', '')), '') is null
         or nullif(btrim(coalesce(v_volume->>'peso_bruto', '')), '') is null then
        raise exception using errcode = '22023',
          message = format('Volume %s incompleto: quantidade e pesos sao obrigatorios.', v_indice);
      end if;
      if (v_volume->>'quantidade')::numeric <= 0
         or trunc((v_volume->>'quantidade')::numeric) <> (v_volume->>'quantidade')::numeric
         or (v_volume->>'peso_liquido')::numeric < 0
         or (v_volume->>'peso_bruto')::numeric < (v_volume->>'peso_liquido')::numeric then
        raise exception using errcode = '22023',
          message = format('Volume %s possui quantidade ou pesos invalidos.', v_indice);
      end if;
    end loop;
  end if;

  -- Linhas: total contra o saldo (a reserva desta propria solicitacao conta a favor).
  select round(coalesce(sum(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0)), 0), 2), count(*)
    into v_total, v_linhas
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id;
  if v_linhas = 0 then
    raise exception using errcode = '22023', message = 'A solicitacao nao tem linhas.';
  end if;
  if v_total <= 0 then
    raise exception using errcode = '22023', message = 'O total da nota precisa ser maior que zero.';
  end if;
  select * into v_saldo from f.fn_os_saldo_a_faturar(v_sf.tenant_id, v_sf.empresa_id, v_os.id);
  v_reserva_propria := case when v_sf.status <> 'CANCELADA' then v_total else 0 end;
  if v_saldo.valor_pedido > 0 and v_total > v_saldo.saldo + v_reserva_propria + 0.005 then
    raise exception using errcode = '22023', message = format(
      'Total das linhas R$ %s acima do saldo da OS R$ %s.',
      to_char(v_total, 'FM999G999G990D00'), to_char(v_saldo.saldo + v_reserva_propria, 'FM999G999G990D00'));
  end if;

  -- Cada linha: produto fabricado com cadastro fiscal completo. Nada deduzido.
  for v_item in
    select si.* from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
    order by si.ordem
  loop
    if v_item.quantidade is null or v_item.quantidade <= 0 or v_item.valor_unitario is null or v_item.valor_unitario <= 0 then
      raise exception using errcode = '22023', message = format('Linha %s: quantidade e valor unitario precisam ser positivos.', v_item.ordem);
    end if;
    if v_item.item_id is null then
      raise exception using errcode = '22023', message = format('Linha %s: vincule um produto fabricado (campo produto).', v_item.ordem);
    end if;
    select * into v_item_cad from public.itens i where i.tenant_id = v_sf.tenant_id and i.id = v_item.item_id;
    if not found then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s nao encontrado.', v_item.ordem, v_item.item_id);
    end if;
    select * into v_fi from public.fiscal_itens fi
    where fi.tenant_id = v_sf.tenant_id and fi.empresa_id = v_sf.empresa_id and fi.item_id = v_item.item_id;
    if not found or regexp_replace(coalesce(v_fi.ncm, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem NCM (campo ncm em /itens).', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if v_fi.origem is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem origem da mercadoria (campo origem em /itens). Nao e deduzida.', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if nullif(btrim(coalesce(v_fi.unidade_tributavel, '')), '') is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem unidade tributavel (campo unidade_tributavel em /itens).', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if nullif(btrim(coalesce(v_fi.cst_ipi, '')), '') is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem CST de IPI (campo cst_ipi em /itens); a fixture 5101 nao presume IPI.', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if v_fi.cst_ipi in ('00', '49', '50', '99') and v_fi.aliq_ipi is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s com IPI tributado (CST %s) sem aliquota (campo aliq_ipi em /itens).', v_item.ordem, v_item_cad.codigo_interno, v_fi.cst_ipi);
    end if;

    -- TIPI: NCM com aliquota positiva nao pode sair sem IPI destacado numa venda de
    -- producao propria. A NF-e 2/33 saiu com CST 51 e vIPI 0 num NCM tributado a 9,75%
    -- porque o cadastro do produto dizia isso e o motor obedeceu (contabilidade,
    -- 09/09/2026). So trava NCM que esteja em f.tipi_ncm: sem registro nao ha o que
    -- afirmar, e a linha passa.
    select t.aliquota into v_tipi_aliquota
    from f.tipi_ncm t
    where t.ncm = regexp_replace(coalesce(v_fi.ncm, ''), '[^0-9]', '', 'g')
      and t.vigencia_inicio <= current_date
      and (t.vigencia_fim is null or t.vigencia_fim >= current_date)
    order by t.vigencia_inicio desc
    limit 1;
    if coalesce(v_tipi_aliquota, 0) > 0
       and v_cfop in ('5101', '6101')
       and (v_fi.cst_ipi not in ('00', '49', '50', '99') or coalesce(v_fi.aliq_ipi, 0) = 0) then
      raise exception using errcode = '22023', message = format(
        'Linha %s: produto %s tem NCM %s tributado a %s%% na TIPI e sairia sem IPI (CST %s). Corrija o cadastro fiscal do item.',
        v_item.ordem, v_item_cad.codigo_interno, v_fi.ncm, v_tipi_aliquota, v_fi.cst_ipi);
    end if;

    select po.* into v_po from f.perfil_operacao po
    where po.tenant_id = v_sf.tenant_id and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
      and po.modelo = 'NFE' and po.natureza_operacao = v_natureza and po.ambito_destino = v_ambito
      and po.ufs_destino is not null and v_destino_uf = any(po.ufs_destino)
      and coalesce(po.indicador_ie_destinatario, '') = coalesce(v_cliente.indicador_ie, '')
      and po.origem_mercadoria = v_fi.origem
      and (po.destinacoes_mercadoria is null or v_destinacao = any(po.destinacoes_mercadoria))
      and (po.crt is null or po.crt = v_crt)
      and po.faixa_automacao <> 'BLOQUEADO' and po.vigencia_inicio <= current_date and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
      and po.revisao_fiscal_em is not null and po.cst_icms is not null and po.aliquota_icms is not null
      -- Perfil com lista de NCM so vale para os NCMs dele; sem lista, e o generico da
      -- operacao. Foi o que faltou para a maquina industrial do Convenio 52/91: dois
      -- perfis eram elegiveis para 5101 + ativo imobilizado e o desempate por
      -- habilitado_producao escolhia o CST 00, que o builder depois recusava.
      and (po.ncms is null or cardinality(po.ncms) = 0 or regexp_replace(coalesce(v_fi.ncm, ''), '[^0-9]', '', 'g') = any(po.ncms))
    order by (po.ncms is not null and cardinality(po.ncms) > 0) desc, po.habilitado_producao desc, po.revisao_fiscal_em desc limit 1;
    if found then
      v_po_id := v_po.id; v_fonte := 'PERFIL';
      if v_po_unico is null then v_po_unico := v_po.id; elsif v_po_unico <> v_po.id then v_po_misto := true; end if;
      update f.solicitacao_item si
      set cfop = coalesce(case when v_ambito = 'INTERNA' then v_po.cfop_interno else v_po.cfop_externo end, v_cfop),
          cst_icms = v_po.cst_icms, csosn = v_po.csosn,
          icms_modalidade_base_calculo = coalesce(v_po.icms_modalidade_base_calculo, '3'),
          aliquota_icms = v_po.aliquota_icms,
          reducao_base_icms_percentual = coalesce(v_po.reducao_base_icms_percentual, 0),
          cbenef = case when v_po.cbenef_aplicacao = 'COM_BENEFICIO' then v_po.cbenef else null end,
          cst_pis = v_po.cst_pis, aliquota_pis = v_po.aliquota_pis,
          cst_cofins = v_po.cst_cofins, aliquota_cofins = v_po.aliquota_cofins,
          cst_ipi = v_fi.cst_ipi,
          aliquota_ipi = case when v_fi.cst_ipi in ('00', '49', '50', '99') then v_fi.aliq_ipi else null end,
        ipi_tipi_aliquota = v_tipi_aliquota,
          ipi_codigo_enquadramento_legal = coalesce(nullif(btrim(v_fi.ipi_codigo_enquadramento_legal), ''), v_po.ipi_codigo_enquadramento_legal, '999'),
          ipi_fonte = 'PERFIL_OPERACAO',
          ncm = regexp_replace(v_fi.ncm, '[^0-9]', '', 'g'),
          cest = nullif(regexp_replace(coalesce(v_fi.cest, ''), '[^0-9]', '', 'g'), ''),
          origem_mercadoria = v_fi.origem,
          unidade_tributavel = upper(btrim(v_fi.unidade_tributavel)),
          codigo_produto = coalesce(nullif(btrim(v_item_cad.codigo_interno), ''), v_item_cad.id::text),
          numero_fci = v_fi.numero_fci,
          cst_ibs_cbs = v_po.cst_ibs_cbs, cclass_trib = v_po.cclass_trib,
          ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_po.ibs_cbs_json, 'ibs_uf_aliquota'), 'ibs_mun_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_po.ibs_cbs_json, 'ibs_mun_aliquota'), 'cbs_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_po.ibs_cbs_json, 'cbs_aliquota')),
          perfil_operacao_id = v_po.id, perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id,
          tributacao_fonte = 'PERFIL'
      where si.id = v_item.id;
      continue;
    end if;
    if v_fx.cfop is null then
      raise exception using errcode = '22023', message = format('Linha %s: nenhum perfil vigente para %s/%s (origem %s, destinacao %s) e sem fixture de homologacao para o CFOP %s.', v_item.ordem, v_natureza, v_ambito, v_fi.origem, v_destinacao, v_cfop);
    end if;
    v_fonte := coalesce(v_fonte, 'FIXTURE_HOMOLOGACAO');
    v_aliquota := case
      when v_ambito = 'INTERNA' then
        case when v_destinacao in ('USO_CONSUMO', 'ATIVO_IMOBILIZADO') then v_fx.aliquota_icms_consumo else v_fx.aliquota_icms_contribuinte end
      when v_fi.origem in (1, 2, 6) then v_fx.aliquota_icms_importado
      when v_destino_uf in ('PR', 'RS', 'SP', 'RJ', 'MG') then v_fx.aliquota_icms_interestadual_sul_sudeste
      else v_fx.aliquota_icms_interestadual_demais
    end;
    if v_aliquota is null then
      raise exception using errcode = '22023', message = format('Fixture %s sem aliquota de ICMS para o ambito %s.', v_cfop, v_ambito);
    end if;

    update f.solicitacao_item si
    set cfop = v_cfop,
        cst_icms = v_fx.cst_icms,
        csosn = null,
        icms_modalidade_base_calculo = '3',
        aliquota_icms = v_aliquota,
        reducao_base_icms_percentual = 0,
        cbenef = null,
        cst_pis = v_fx.cst_pis, aliquota_pis = v_fx.aliquota_pis,
        cst_cofins = v_fx.cst_cofins, aliquota_cofins = v_fx.aliquota_cofins,
        cst_ipi = v_fi.cst_ipi,
        aliquota_ipi = case when v_fi.cst_ipi in ('00', '49', '50', '99') then v_fi.aliq_ipi else null end,
        ipi_tipi_aliquota = v_tipi_aliquota,
        ipi_codigo_enquadramento_legal = coalesce(nullif(btrim(v_fi.ipi_codigo_enquadramento_legal), ''), v_fx.c_enq, '999'),
        ipi_fonte = 'FIXTURE_HOMOLOGACAO',
        ncm = regexp_replace(v_fi.ncm, '[^0-9]', '', 'g'),
        cest = nullif(regexp_replace(coalesce(v_fi.cest, ''), '[^0-9]', '', 'g'), ''),
        origem_mercadoria = v_fi.origem,
        unidade_tributavel = upper(btrim(v_fi.unidade_tributavel)),
        codigo_produto = coalesce(nullif(btrim(v_item_cad.codigo_interno), ''), v_item_cad.id::text),
        numero_fci = v_fi.numero_fci,
        cst_ibs_cbs = '000',
        cclass_trib = '000001',
        ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', 0.1000, 'ibs_mun_aliquota', 0.0000, 'cbs_aliquota', 0.9000),
        perfil_operacao_id = null,
        perfil_aplicado_em = now(),
        perfil_aplicado_por = v_usuario_id,
        tributacao_fonte = 'FIXTURE_HOMOLOGACAO'
    where si.id = v_item.id;
  end loop;

  -- Excecao ICMS 12% por exigencia do destinatario: o perfil foi aplicado pela destinacao
  -- (17% na manutencao); a excecao troca so o ICMS dos itens sem SC820006 e o indFinal.
  -- IPI e base (IPI dentro, pela destinacao) nao mudam.
  v_excecao := exists (
    select 1 from f.nfe_excecao_aliquota_destinatario ex
    where ex.solicitacao_id = v_sf.id and ex.desativada_em is null
  );
  if v_excecao then
    v_excecao_motivo := f.fn_nfe_excecao_aliquota_indisponivel(v_cliente.indicador_ie, v_destinacao, v_ambito = 'INTERNA');
    if v_excecao_motivo is not null then
      raise exception using errcode = '22023', message = v_excecao_motivo || ' Desative a excecao ou corrija a conferencia.';
    end if;
    update f.solicitacao_item si
    set cst_icms = '00', csosn = null, aliquota_icms = 12,
        reducao_base_icms_percentual = 0, cbenef = null
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
      and coalesce(btrim(si.cbenef), '') <> 'SC820006';
    v_consumidor_final := 1;
  end if;

  update f.solicitacao_faturamento sf
  set natureza_operacao = v_natureza,
      finalidade_emissao = 1,
      consumidor_final = v_consumidor_final,
      presenca_comprador = (p_operacao->>'presenca_comprador')::smallint,
      modalidade_frete = v_modalidade,
      valor_frete = coalesce(nullif(p_operacao->>'valor_frete', '')::numeric, 0),
      valor_seguro = coalesce(nullif(p_operacao->>'valor_seguro', '')::numeric, 0),
      valor_outras_despesas = coalesce(nullif(p_operacao->>'valor_outras_despesas', '')::numeric, 0),
      destinacao_mercadoria = v_destinacao,
      pagamento_forma = btrim(p_operacao->>'pagamento_forma'),
      pagamento_indicador = (p_operacao->>'pagamento_indicador')::smallint,
      pagamento_descricao = nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''),
      pagamento_parcelas = v_parcelas,
      transportador_dados = v_transportador,
      volumes_dados = v_volumes,
      pedido_cliente = coalesce(nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), ''), sf.pedido_cliente, v_os.pedido_compra),
      observacao = coalesce(nullif(btrim(coalesce(p_operacao->>'observacao', '')), ''), sf.observacao),
      destino_uf_confirmada = v_destino_uf,
      destino_confirmado_em = now(),
      destino_confirmado_por = v_usuario_id,
      perfil_operacao_id = case when v_po_unico is not null and not v_po_misto and v_fonte = 'PERFIL' then v_po_unico else null end,
      perfil_aplicado_em = now(),
      perfil_aplicado_por = v_usuario_id,
      revisao_fiscal_confirmada_em = now(),
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null, destinatario_snapshot = null,
      operacao_snapshot = null, snapshot_cadastro_em = null,
      updated_at = now()
  where sf.id = v_sf.id;

  if v_fonte = 'PERFIL' and exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and si.tributacao_fonte is distinct from 'PERFIL') then
    raise exception using errcode = '22023', message = 'Linhas com perfil vigente e linhas na fixture na mesma nota: cadastre o perfil que falta ou separe as notas.';
  end if;

  -- Pedido de compra digitado na tela de faturar grava na OS.
  if nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is not null
     and nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is distinct from v_os.pedido_compra then
    update public.ordens_servico set pedido_compra = btrim(p_operacao->>'pedido_cliente'), atualizado_em = now()
    where id = v_os.id and tenant_id = v_sf.tenant_id and empresa_id = v_sf.empresa_id;
  end if;

  -- Congela emitente, destinatario, operacao e itens; devolve as pendencias de cadastro.
  return f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id)
    || jsonb_build_object('natureza_operacao', v_natureza, 'cfop', v_cfop, 'ambito', v_ambito,
                          'tributacao_fonte', coalesce(v_fonte, 'FIXTURE_HOMOLOGACAO'), 'perfil_operacao_id', case when v_po_misto then null else v_po_unico end, 'total', v_total, 'saldo_os', v_saldo.saldo);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Prontidao de producao: indFinal da nota com excecao e 1, nao o do perfil.
-- ---------------------------------------------------------------------------
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
             and not (v_sf.operacao_snapshot ? 'excecao_aliquota_destinatario')
             and po.consumidor_final is distinct from (v_sf.operacao_snapshot->>'consumidor_final')::smallint)
         -- Com a excecao o indFinal e 1 por forca dela, nao do perfil.
         or ((v_sf.operacao_snapshot ? 'excecao_aliquota_destinatario')
             and (v_sf.operacao_snapshot->>'consumidor_final')::smallint is distinct from 1)
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
-- Relatorio mensal das notas emitidas com a excecao.
--
-- Uma linha por nota AUTORIZADA no mes (data de autorizacao em Sao Paulo). vBC e ICMS
-- somam so os itens que usaram a excecao — CST 00 a 12% sem cBenef SC820006 no payload
-- enviado —, e a diferenca para 17% e item a item: round(vBC x 17%) - ICMS destacado.
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfe_excecao_aliquota_relatorio(
  p_mes date,
  p_ambiente text default 'PRODUCAO'
)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  ambiente text,
  serie integer,
  numero integer,
  chave_acesso text,
  autorizado_em timestamptz,
  destinatario text,
  destinatario_documento text,
  numero_oc text,
  itens text,
  valor_base_calculo numeric,
  valor_icms numeric,
  valor_icms_17 numeric,
  diferenca_17 numeric
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
#variable_conflict use_column
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_inicio date := date_trunc('month', coalesce(p_mes, (now() at time zone 'America/Sao_Paulo')::date))::date;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role'
     and not f.has_finance_access(v_tenant, v_empresa) then
    raise exception using errcode = '42501', message = 'Sem permissao para o relatorio de excecoes de ICMS.';
  end if;
  if upper(coalesce(p_ambiente, '')) not in ('PRODUCAO', 'HOMOLOGACAO') then
    raise exception using errcode = '22023', message = 'Ambiente deve ser PRODUCAO ou HOMOLOGACAO.';
  end if;

  return query
  select
    dfe.documento_fiscal_id,
    sf.id,
    dfe.ambiente,
    dfe.serie,
    dfe.numero,
    dfe.chave_acesso,
    dfe.autorizado_em,
    sf.destinatario_snapshot->>'nome',
    sf.destinatario_snapshot->>'documento',
    sf.operacao_snapshot#>>'{excecao_aliquota_destinatario,numero_oc}',
    string_agg(it.item->>'numero_item', ', ' order by (it.item->>'numero_item')::integer),
    coalesce(sum((it.item->>'icms_base_calculo')::numeric), 0),
    coalesce(sum((it.item->>'icms_valor')::numeric), 0),
    coalesce(sum(round((it.item->>'icms_base_calculo')::numeric * 0.17, 2)), 0),
    coalesce(sum(round((it.item->>'icms_base_calculo')::numeric * 0.17, 2) - (it.item->>'icms_valor')::numeric), 0)
  from f.documento_fiscal_emissao dfe
  join f.solicitacao_faturamento sf
    on sf.id = dfe.solicitacao_id and sf.tenant_id = dfe.tenant_id and sf.empresa_id = dfe.empresa_id
  cross join lateral jsonb_array_elements(dfe.payload_enviado->'items') it(item)
  where (session_user = 'postgres' or coalesce(auth.jwt()->>'role', '') = 'service_role'
         or (dfe.tenant_id = v_tenant and dfe.empresa_id = v_empresa))
    and dfe.ambiente = upper(p_ambiente)
    and dfe.status = 'AUTORIZADA'
    and dfe.autorizado_em >= (v_inicio::timestamp at time zone 'America/Sao_Paulo')
    and dfe.autorizado_em < ((v_inicio + interval '1 month')::timestamp at time zone 'America/Sao_Paulo')
    and sf.operacao_snapshot ? 'excecao_aliquota_destinatario'
    and it.item->>'icms_situacao_tributaria' = '00'
    and (it.item->>'icms_aliquota')::numeric = 12
    and coalesce(it.item->>'codigo_beneficio_fiscal', '') <> 'SC820006'
  group by dfe.documento_fiscal_id, sf.id
  order by dfe.autorizado_em, dfe.numero;
end;
$$;

revoke all on function f.fn_nfe_excecao_aliquota_indisponivel(text, text, boolean) from public, anon;
revoke all on function f.fn_nfe_excecao_aliquota_ativar(uuid, text, text, text, text, text, text) from public, anon;
revoke all on function f.fn_nfe_excecao_aliquota_desativar(uuid) from public, anon;
revoke all on function f.fn_nfe_excecao_aliquota_consultar(uuid) from public, anon;
revoke all on function f.fn_nfe_excecao_aliquota_evidencia(uuid) from public, anon;
revoke all on function f.fn_nfe_excecao_aliquota_relatorio(date, text) from public, anon;
grant execute on function f.fn_nfe_excecao_aliquota_indisponivel(text, text, boolean) to authenticated, service_role;
grant execute on function f.fn_nfe_excecao_aliquota_ativar(uuid, text, text, text, text, text, text) to authenticated, service_role;
grant execute on function f.fn_nfe_excecao_aliquota_desativar(uuid) to authenticated, service_role;
grant execute on function f.fn_nfe_excecao_aliquota_consultar(uuid) to authenticated, service_role;
grant execute on function f.fn_nfe_excecao_aliquota_evidencia(uuid) to authenticated, service_role;
grant execute on function f.fn_nfe_excecao_aliquota_relatorio(date, text) to authenticated, service_role;
