begin;

-- A liberacao de um perfil fica vinculada a uma solicitacao e ao documento
-- efetivamente autorizado em homologacao. Uma revisao posterior revoga essa
-- liberacao e obriga uma nova passagem pelo ambiente de testes.
alter table f.perfil_operacao
  add column producao_decisao_justificativa text,
  add column producao_homologacao_solicitacao_id uuid,
  add column producao_homologacao_documento_id uuid;

alter table f.perfil_operacao
  add constraint perfil_operacao_producao_justificativa_ck
    check (
      producao_decisao_justificativa is null
      or char_length(btrim(producao_decisao_justificativa)) between 15 and 1000
    ),
  add constraint perfil_operacao_producao_solicitacao_escopo_fk
    foreign key (tenant_id, empresa_id, producao_homologacao_solicitacao_id)
    references f.solicitacao_faturamento (tenant_id, empresa_id, id),
  add constraint perfil_operacao_producao_documento_escopo_fk
    foreign key (tenant_id, empresa_id, producao_homologacao_documento_id)
    references f.documento_fiscal (tenant_id, empresa_id, id);

comment on column f.perfil_operacao.producao_decisao_justificativa is
  'Justificativa da ultima decisao de producao ou da revogacao causada por nova revisao.';
comment on column f.perfil_operacao.producao_homologacao_solicitacao_id is
  'Solicitacao cuja NF-e autorizada em homologacao fundamentou a liberacao atual.';
comment on column f.perfil_operacao.producao_homologacao_documento_id is
  'Documento fiscal autorizado em homologacao que fundamentou a liberacao atual.';

create unique index if not exists perfil_operacao_tenant_empresa_id_ux
  on f.perfil_operacao (tenant_id, empresa_id, id);

create table f.perfil_operacao_revisao_evento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  perfil_operacao_id uuid not null,
  tipo text not null check (tipo in ('REVISAO', 'LIBERACAO', 'DESABILITACAO')),
  antes jsonb not null check (jsonb_typeof(antes) = 'object'),
  depois jsonb not null check (jsonb_typeof(depois) = 'object'),
  homologacao_solicitacao_id uuid,
  homologacao_documento_id uuid,
  justificativa text not null
    check (char_length(btrim(justificativa)) between 15 and 1000),
  criado_por uuid references a.usuario(id),
  created_at timestamptz not null default now(),
  constraint perfil_operacao_revisao_evento_perfil_fk
    foreign key (tenant_id, empresa_id, perfil_operacao_id)
    references f.perfil_operacao (tenant_id, empresa_id, id),
  constraint perfil_operacao_revisao_evento_empresa_fk
    foreign key (tenant_id, empresa_id)
    references c.empresa (tenant_id, id),
  constraint perfil_operacao_revisao_evento_solicitacao_fk
    foreign key (tenant_id, empresa_id, homologacao_solicitacao_id)
    references f.solicitacao_faturamento (tenant_id, empresa_id, id),
  constraint perfil_operacao_revisao_evento_documento_fk
    foreign key (tenant_id, empresa_id, homologacao_documento_id)
    references f.documento_fiscal (tenant_id, empresa_id, id),
  constraint perfil_operacao_revisao_evento_homologacao_par_ck
    check (
      (homologacao_solicitacao_id is null) = (homologacao_documento_id is null)
    )
);

create index perfil_operacao_revisao_evento_busca_idx
  on f.perfil_operacao_revisao_evento
  (tenant_id, empresa_id, perfil_operacao_id, created_at desc);

comment on table f.perfil_operacao_revisao_evento is
  'Trilha append-only das revisoes, liberacoes e desabilitacoes de perfis fiscais.';

create or replace function f.fn_perfil_operacao_revisao_evento_append_only()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception using
    errcode = '55000',
    message = 'A trilha de revisao fiscal e append-only; grave um novo evento.';
end;
$function$;

create trigger perfil_operacao_revisao_evento_append_only
  before update or delete on f.perfil_operacao_revisao_evento
  for each row execute function f.fn_perfil_operacao_revisao_evento_append_only();

revoke all on function f.fn_perfil_operacao_revisao_evento_append_only()
  from public, anon, authenticated, service_role;

alter table f.perfil_operacao_revisao_evento enable row level security;
create policy perfil_operacao_revisao_evento_select
  on f.perfil_operacao_revisao_evento
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access(tenant_id, empresa_id)
    and public.has_active_empresa_access(tenant_id, empresa_id)
  );

revoke all on table f.perfil_operacao_revisao_evento
  from public, anon, authenticated, service_role;
grant select on table f.perfil_operacao_revisao_evento to authenticated;
grant select, insert on table f.perfil_operacao_revisao_evento to service_role;

-- Revoga flags legadas dentro da propria trilha append-only. O ator fica nulo
-- porque esta e uma decisao de migracao, nao uma revisao feita por usuario.
do $block$
begin
  if exists (
    select 1 from f.perfil_operacao
    where habilitado_producao and empresa_id is null
  ) then
    raise exception 'Perfil global habilitado exige saneamento explicito antes da migracao auditavel.';
  end if;
end;
$block$;

insert into f.perfil_operacao_revisao_evento (
  tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois,
  justificativa, criado_por
)
select
  po.tenant_id,
  po.empresa_id,
  po.id,
  'DESABILITACAO',
  to_jsonb(po),
  to_jsonb(po) || jsonb_build_object(
    'habilitado_producao', false,
    'producao_decidida_em', now(),
    'producao_decidida_por', null,
    'producao_decisao_justificativa', 'Flag legada revogada pela migracao do fluxo homologado auditavel.',
    'producao_homologacao_solicitacao_id', null,
    'producao_homologacao_documento_id', null
  ),
  'Flag legada revogada pela migracao do fluxo homologado auditavel.',
  null
from f.perfil_operacao po
where po.habilitado_producao
  and po.empresa_id is not null;

update f.perfil_operacao
set habilitado_producao = false,
    producao_decidida_em = now(),
    producao_decidida_por = null,
    producao_decisao_justificativa = 'Flag legada revogada pela migracao do fluxo homologado auditavel.',
    producao_homologacao_solicitacao_id = null,
    producao_homologacao_documento_id = null
where habilitado_producao;

alter table f.perfil_operacao
  add constraint perfil_operacao_producao_auditoria_completa_ck
    check (
      not habilitado_producao
      or (
        revisao_fiscal_em is not null
        and producao_decidida_em is not null
        and producao_decidida_em >= revisao_fiscal_em
        and producao_decidida_por is not null
        and producao_homologacao_solicitacao_id is not null
        and producao_homologacao_documento_id is not null
        and nullif(btrim(producao_decisao_justificativa), '') is not null
      )
    );

create or replace function f.fn_perfil_operacao_jsonb_numeric_seguro(
  p_payload jsonb,
  p_chave text
)
returns numeric
language plpgsql
immutable
set search_path = pg_catalog
as $function$
declare
  v_valor text;
begin
  if jsonb_typeof(p_payload) is distinct from 'object' then
    return null;
  end if;
  v_valor := p_payload->>p_chave;
  if v_valor is null or v_valor !~ '^[0-9]+([.][0-9]+)?$' then
    return null;
  end if;
  return v_valor::numeric;
exception
  when numeric_value_out_of_range or invalid_text_representation then
    return null;
end;
$function$;

revoke all on function f.fn_perfil_operacao_jsonb_numeric_seguro(jsonb, text)
  from public, anon, authenticated;

create or replace function f.fn_perfil_operacao_nfe_homologacoes_listar(
  p_perfil_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_homologacoes jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select po.* into v_perfil
  from f.perfil_operacao po
  where po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
    and po.id = p_perfil_id
    and po.modelo = 'NFE';

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Perfil NF-e nao encontrado no tenant e empresa ativos.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'solicitacao_id', h.solicitacao_id,
        'documento_fiscal_id', h.documento_fiscal_id,
        'referencia_externa', h.referencia_externa,
        'autorizado_em', h.autorizado_em,
        'cancelamento_em_andamento', h.cancelamento_em_andamento,
        'apos_ultima_revisao', (
          v_perfil.revisao_fiscal_em is not null
          and h.autorizado_em > v_perfil.revisao_fiscal_em
        )
      )
      order by h.autorizado_em desc
    ),
    '[]'::jsonb
  ) into v_homologacoes
  from (
    select distinct on (sf.id)
      sf.id as solicitacao_id,
      dfe.documento_fiscal_id,
      dfe.referencia_externa,
      dfe.autorizado_em,
      coalesce((
        select ev.status = 'ENVIANDO'
        from f.documento_fiscal_evento ev
        where ev.tenant_id = dfe.tenant_id
          and ev.empresa_id = dfe.empresa_id
          and ev.documento_fiscal_id = dfe.documento_fiscal_id
          and ev.tipo = 'CANCELAMENTO'
        order by ev.created_at desc, ev.id desc
        limit 1
      ), false) as cancelamento_em_andamento
    from f.solicitacao_faturamento sf
    join f.solicitacao_item si
      on si.tenant_id = sf.tenant_id
     and si.empresa_id = sf.empresa_id
     and si.solicitacao_id = sf.id
     and si.perfil_operacao_id = v_perfil.id
    join f.documento_fiscal_emissao dfe
      on dfe.tenant_id = sf.tenant_id
     and dfe.empresa_id = sf.empresa_id
     and dfe.solicitacao_id = sf.id
     and dfe.ambiente = 'HOMOLOGACAO'
     and dfe.status = 'AUTORIZADA'
     and dfe.autorizado_em is not null
    where sf.tenant_id = v_scope.tenant_id
      and sf.empresa_id = v_scope.empresa_id
      and sf.status <> 'CANCELADA'
    order by sf.id, dfe.autorizado_em desc, dfe.updated_at desc, dfe.documento_fiscal_id desc
  ) h;

  return jsonb_build_object(
    'tenant_id', v_scope.tenant_id,
    'empresa_id', v_scope.empresa_id,
    'perfil_id', v_perfil.id,
    'homologacoes', v_homologacoes
  );
end;
$function$;

-- Remove o contrato da migration anterior, que aceitava revisar e habilitar
-- producao no mesmo ato.
drop function if exists f.fn_perfil_operacao_nfe_revisar(
  uuid, text, text, text, numeric, numeric, numeric, text, boolean, boolean
);

create or replace function f.fn_perfil_operacao_nfe_revisar(
  p_perfil_id uuid,
  p_cst_ibs_cbs text,
  p_cclass_trib text,
  p_cclass_trib_versao text,
  p_ibs_uf_aliquota numeric,
  p_ibs_mun_aliquota numeric,
  p_cbs_aliquota numeric,
  p_justificativa text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_cst text := btrim(coalesce(p_cst_ibs_cbs, ''));
  v_cclass text := btrim(coalesce(p_cclass_trib, ''));
  v_versao text := btrim(coalesce(p_cclass_trib_versao, ''));
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '')
       in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao de escrita para revisar perfis fiscais.';
  end if;

  select po.* into v_perfil
  from f.perfil_operacao po
  where po.id = p_perfil_id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
    and po.modelo = 'NFE'
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Perfil NF-e nao encontrado no tenant e empresa ativos.';
  end if;
  if v_cst !~ '^[0-9]{3}$' then
    raise exception using errcode = '22023', message = 'CST IBS/CBS deve conter exatamente 3 digitos.';
  end if;
  if v_cclass !~ '^[0-9]{6}$' then
    raise exception using errcode = '22023', message = 'cClassTrib deve conter exatamente 6 digitos.';
  end if;
  if left(v_cclass, 3) <> v_cst then
    raise exception using errcode = '22023', message = 'Os 3 primeiros digitos do cClassTrib devem coincidir com o CST IBS/CBS.';
  end if;
  if char_length(v_versao) < 3 or char_length(v_versao) > 100 then
    raise exception using errcode = '22023', message = 'Informe a versao da tabela cClassTrib (3 a 100 caracteres).';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then
    raise exception using errcode = '22023', message = 'A justificativa da revisao deve ter entre 15 e 1000 caracteres.';
  end if;
  if p_ibs_uf_aliquota is null or p_ibs_uf_aliquota < 0 or p_ibs_uf_aliquota > 100
     or p_ibs_uf_aliquota <> round(p_ibs_uf_aliquota, 4) then
    raise exception using errcode = '22023', message = 'Aliquota IBS UF deve estar entre 0 e 100, com ate 4 casas decimais.';
  end if;
  if p_ibs_mun_aliquota is null or p_ibs_mun_aliquota < 0 or p_ibs_mun_aliquota > 100
     or p_ibs_mun_aliquota <> round(p_ibs_mun_aliquota, 4) then
    raise exception using errcode = '22023', message = 'Aliquota IBS municipal deve estar entre 0 e 100, com ate 4 casas decimais.';
  end if;
  if p_cbs_aliquota is null or p_cbs_aliquota < 0 or p_cbs_aliquota > 100
     or p_cbs_aliquota <> round(p_cbs_aliquota, 4) then
    raise exception using errcode = '22023', message = 'Aliquota CBS deve estar entre 0 e 100, com ate 4 casas decimais.';
  end if;

  update f.perfil_operacao po
  set cst_ibs_cbs = v_cst,
      cclass_trib = v_cclass,
      cclass_trib_versao = v_versao,
      ibs_cbs_json = jsonb_build_object(
        'ibs_uf_aliquota', p_ibs_uf_aliquota,
        'ibs_mun_aliquota', p_ibs_mun_aliquota,
        'cbs_aliquota', p_cbs_aliquota
      ),
      habilitado_producao = false,
      revisao_fiscal_em = now(),
      revisao_fiscal_por = v_scope.usuario_id,
      revisao_fiscal_justificativa = v_justificativa,
      producao_decidida_em = now(),
      producao_decidida_por = v_scope.usuario_id,
      producao_decisao_justificativa = 'Liberacao de producao revogada automaticamente por nova revisao fiscal.',
      producao_homologacao_solicitacao_id = null,
      producao_homologacao_documento_id = null
  where po.id = v_perfil.id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
  returning po.* into v_depois;

  insert into f.perfil_operacao_revisao_evento (
    tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois,
    justificativa, criado_por
  ) values (
    v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'REVISAO',
    to_jsonb(v_perfil), to_jsonb(v_depois), v_justificativa, v_scope.usuario_id
  );

  if v_perfil.habilitado_producao then
    insert into f.perfil_operacao_revisao_evento (
      tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois,
      homologacao_solicitacao_id, homologacao_documento_id,
      justificativa, criado_por
    ) values (
      v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'DESABILITACAO',
      to_jsonb(v_perfil), to_jsonb(v_depois),
      v_perfil.producao_homologacao_solicitacao_id,
      v_perfil.producao_homologacao_documento_id,
      'Liberacao de producao revogada automaticamente por nova revisao fiscal.',
      v_scope.usuario_id
    );
  end if;

  return jsonb_build_object(
    'perfil_id', v_perfil.id,
    'codigo', v_perfil.codigo,
    'habilitado_producao', false,
    'revisao_fiscal_em', now(),
    'mensagem', 'Revisao salva. A producao foi desabilitada ate uma nova homologacao autorizada.'
  );
end;
$function$;

create or replace function f.fn_perfil_operacao_nfe_liberar_producao(
  p_perfil_id uuid,
  p_solicitacao_id uuid,
  p_justificativa text,
  p_confirmacao boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_solicitacao f.solicitacao_faturamento%rowtype;
  v_homologacao f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_itens integer;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '')
       in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao de escrita para liberar perfis fiscais.';
  end if;
  if p_perfil_id is null or p_solicitacao_id is null then
    raise exception using errcode = '22023', message = 'Perfil e solicitacao de homologacao sao obrigatorios.';
  end if;
  if not coalesce(p_confirmacao, false) then
    raise exception using errcode = '22023', message = 'Confirme explicitamente a liberacao para producao.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then
    raise exception using errcode = '22023', message = 'A justificativa da liberacao deve ter entre 15 e 1000 caracteres.';
  end if;

  select po.* into v_perfil
  from f.perfil_operacao po
  where po.id = p_perfil_id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
    and po.modelo = 'NFE'
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Perfil NF-e nao encontrado no tenant e empresa ativos.';
  end if;
  if v_perfil.revisao_fiscal_em is null
     or v_perfil.revisao_fiscal_por is null
     or nullif(btrim(v_perfil.revisao_fiscal_justificativa), '') is null then
    raise exception using errcode = '22023', message = 'O perfil precisa ser revisado antes da homologacao e da liberacao.';
  end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' then
    raise exception using errcode = '22023', message = 'Perfil bloqueado nao pode ser liberado para producao.';
  end if;
  if v_perfil.vigencia_inicio > current_date
     or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date) then
    raise exception using errcode = '22023', message = 'Somente perfil vigente pode ser liberado para producao.';
  end if;
  if v_perfil.evidencia_id is null then
    raise exception using errcode = '22023', message = 'A evidencia fiscal do perfil precisa estar vinculada antes da producao.';
  end if;
  if v_perfil.ambito_destino is null
     or v_perfil.ufs_destino is null
     or cardinality(v_perfil.ufs_destino) = 0 then
    raise exception using errcode = '22023', message = 'Ambito e UFs de destino precisam estar confirmados antes da producao.';
  end if;
  if v_perfil.ambito_destino = 'INTERNA' and coalesce(v_perfil.cfop_interno, '') !~ '^[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'CFOP interno valido e obrigatorio para este perfil.';
  end if;
  if v_perfil.ambito_destino = 'INTERESTADUAL' and coalesce(v_perfil.cfop_externo, '') !~ '^[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'CFOP interestadual valido e obrigatorio para este perfil.';
  end if;
  if v_perfil.origem_mercadoria is null then
    raise exception using errcode = '22023', message = 'Origem da mercadoria precisa estar confirmada antes da producao.';
  end if;
  if coalesce(v_perfil.crt, '') !~ '^[123]$' then
    raise exception using errcode = '22023', message = 'CRT precisa estar confirmado antes da producao.';
  end if;
  if v_perfil.crt = '3' and coalesce(v_perfil.cst_icms, '') !~ '^[0-9]{2}$' then
    raise exception using errcode = '22023', message = 'CST ICMS valido e obrigatorio para regime normal.';
  end if;
  if v_perfil.crt in ('1', '2') and coalesce(v_perfil.csosn, '') !~ '^[0-9]{3}$' then
    raise exception using errcode = '22023', message = 'CSOSN valido e obrigatorio para Simples Nacional.';
  end if;
  if v_perfil.cbenef_aplicacao = 'NAO_CONFIRMADO' then
    raise exception using errcode = '22023', message = 'A aplicacao de cBenef precisa estar confirmada antes da producao.';
  end if;
  if coalesce(v_perfil.cst_pis, '') !~ '^[0-9]{2}$'
     or coalesce(v_perfil.cst_cofins, '') !~ '^[0-9]{2}$' then
    raise exception using errcode = '22023', message = 'CST de PIS e COFINS precisam estar confirmados antes da producao.';
  end if;
  if v_perfil.finalidade_emissao is null or v_perfil.consumidor_final is null then
    raise exception using errcode = '22023', message = 'Finalidade da emissao e consumidor final precisam estar confirmados antes da producao.';
  end if;
  if v_perfil.cst_ibs_cbs !~ '^[0-9]{3}$'
     or v_perfil.cclass_trib !~ '^[0-9]{6}$'
     or left(v_perfil.cclass_trib, 3) <> v_perfil.cst_ibs_cbs
     or nullif(btrim(v_perfil.cclass_trib_versao), '') is null
     or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota') is null
     or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota') is null
     or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota') is null then
    raise exception using errcode = '22023', message = 'Os seis campos IBS/CBS precisam estar completos antes da liberacao.';
  end if;
  if not exists (
    select 1
    from f.perfil_operacao_revisao_evento re
    where re.tenant_id = v_scope.tenant_id
      and re.empresa_id = v_scope.empresa_id
      and re.perfil_operacao_id = v_perfil.id
      and re.tipo = 'REVISAO'
      and re.created_at = v_perfil.revisao_fiscal_em
      and re.criado_por is not distinct from v_perfil.revisao_fiscal_por
      and re.justificativa = v_perfil.revisao_fiscal_justificativa
      and re.depois->>'habilitado_producao' = 'false'
      and re.depois->>'cst_ibs_cbs' is not distinct from v_perfil.cst_ibs_cbs
      and re.depois->>'cclass_trib' is not distinct from v_perfil.cclass_trib
      and re.depois->>'cclass_trib_versao' is not distinct from v_perfil.cclass_trib_versao
      and f.fn_perfil_operacao_jsonb_numeric_seguro(
        re.depois->'ibs_cbs_json', 'ibs_uf_aliquota'
      ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
        v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'
      )
      and f.fn_perfil_operacao_jsonb_numeric_seguro(
        re.depois->'ibs_cbs_json', 'ibs_mun_aliquota'
      ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
        v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'
      )
      and f.fn_perfil_operacao_jsonb_numeric_seguro(
        re.depois->'ibs_cbs_json', 'cbs_aliquota'
      ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
        v_perfil.ibs_cbs_json, 'cbs_aliquota'
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'A ultima revisao do perfil nao possui evento de auditoria equivalente.';
  end if;

  select sf.* into v_solicitacao
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_scope.tenant_id
    and sf.empresa_id = v_scope.empresa_id
    and sf.id = p_solicitacao_id
    and sf.status <> 'CANCELADA';

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao ativa nao encontrada no tenant e empresa atuais.';
  end if;
  if v_solicitacao.natureza_operacao is distinct from v_perfil.natureza_operacao then
    raise exception using errcode = '22023', message = 'A natureza da solicitacao nao corresponde ao perfil selecionado.';
  end if;

  select dfe.* into v_homologacao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_scope.tenant_id
    and dfe.empresa_id = v_scope.empresa_id
    and dfe.solicitacao_id = v_solicitacao.id
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.status = 'AUTORIZADA'
    and dfe.autorizado_em is not null
    and dfe.autorizado_em > v_perfil.revisao_fiscal_em
  order by dfe.autorizado_em desc, dfe.updated_at desc, dfe.documento_fiscal_id desc
  limit 1;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'A solicitacao precisa de NF-e AUTORIZADA em homologacao depois da ultima revisao do perfil.';
  end if;
  if coalesce((
    select ev.status = 'ENVIANDO'
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_scope.tenant_id
      and ev.empresa_id = v_scope.empresa_id
      and ev.documento_fiscal_id = v_homologacao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
    order by ev.created_at desc, ev.id desc
    limit 1
  ), false) then
    raise exception using
      errcode = '55000',
      message = 'A NF-e de homologacao selecionada possui cancelamento em andamento.';
  end if;
  if jsonb_typeof(v_homologacao.payload_enviado) is distinct from 'object'
     or jsonb_typeof(v_homologacao.payload_enviado->'items') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'O payload autorizado em homologacao nao permite conferir os itens.';
  end if;

  select count(*) into v_itens
  from f.solicitacao_item si
  where si.tenant_id = v_scope.tenant_id
    and si.empresa_id = v_scope.empresa_id
    and si.solicitacao_id = v_solicitacao.id
    and si.perfil_operacao_id = v_perfil.id;

  if v_itens = 0 then
    raise exception using errcode = '22023', message = 'A solicitacao homologada nao possui item ligado a este perfil.';
  end if;

  if exists (
    select 1
    from f.solicitacao_item si
    left join f.documento_fiscal_item dfi
      on dfi.tenant_id = si.tenant_id
     and dfi.empresa_id = si.empresa_id
     and dfi.documento_fiscal_id = v_homologacao.documento_fiscal_id
     and dfi.item_n = si.ordem
    left join lateral (
      select p.item
      from jsonb_array_elements(v_homologacao.payload_enviado->'items') p(item)
      where p.item->>'numero_item' = si.ordem::text
      limit 1
    ) hp on true
    where si.tenant_id = v_scope.tenant_id
      and si.empresa_id = v_scope.empresa_id
      and si.solicitacao_id = v_solicitacao.id
      and si.perfil_operacao_id = v_perfil.id
      and (
        si.cst_ibs_cbs is distinct from v_perfil.cst_ibs_cbs
        or si.cclass_trib is distinct from v_perfil.cclass_trib
        or si.cclass_trib_versao is distinct from v_perfil.cclass_trib_versao
        or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_uf_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_mun_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'cbs_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota')
        or dfi.id is null
        or dfi.cst_ibs_cbs is distinct from v_perfil.cst_ibs_cbs
        or dfi.cclass_trib is distinct from v_perfil.cclass_trib
        or dfi.cclass_trib_versao is distinct from v_perfil.cclass_trib_versao
        or f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_uf_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_mun_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'cbs_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota')
        or hp.item is null
        or hp.item->>'ibs_cbs_situacao_tributaria' is distinct from v_perfil.cst_ibs_cbs
        or hp.item->>'ibs_cbs_classificacao_tributaria' is distinct from v_perfil.cclass_trib
        or f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_uf_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_mun_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'cbs_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota')
      )
  ) then
    raise exception using
      errcode = '22023',
      message = 'Os seis campos IBS/CBS nao coincidem exatamente entre perfil, solicitacao, snapshot e payload homologado.';
  end if;

  update f.perfil_operacao po
  set habilitado_producao = true,
      producao_decidida_em = now(),
      producao_decidida_por = v_scope.usuario_id,
      producao_decisao_justificativa = v_justificativa,
      producao_homologacao_solicitacao_id = v_solicitacao.id,
      producao_homologacao_documento_id = v_homologacao.documento_fiscal_id
  where po.id = v_perfil.id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
  returning po.* into v_depois;

  insert into f.perfil_operacao_revisao_evento (
    tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois,
    homologacao_solicitacao_id, homologacao_documento_id,
    justificativa, criado_por
  ) values (
    v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'LIBERACAO',
    to_jsonb(v_perfil), to_jsonb(v_depois),
    v_solicitacao.id, v_homologacao.documento_fiscal_id,
    v_justificativa, v_scope.usuario_id
  );

  return jsonb_build_object(
    'perfil_id', v_perfil.id,
    'solicitacao_id', v_solicitacao.id,
    'homologacao_documento_fiscal_id', v_homologacao.documento_fiscal_id,
    'habilitado_producao', true,
    'mensagem', 'Perfil liberado para esta solicitacao apos equivalencia exata com a NF-e homologada.'
  );
end;
$function$;

-- O portao final tambem exige a vinculacao auditada ao documento de
-- homologacao selecionado. Assim, flags legadas ou uma homologacao mais nova
-- nao reaproveitam automaticamente uma liberacao anterior.
create or replace function f.fn_nfe_producao_pronta(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
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
             and le.depois->>'cclass_trib_versao' is not distinct from po.cclass_trib_versao
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
         or si.cclass_trib_versao is distinct from po.cclass_trib_versao
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_uf_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_uf_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_mun_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_mun_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'cbs_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'cbs_aliquota')
         or dfi.id is null
         or dfi.cst_ibs_cbs is distinct from po.cst_ibs_cbs
         or dfi.cclass_trib is distinct from po.cclass_trib
         or dfi.cclass_trib_versao is distinct from po.cclass_trib_versao
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

comment on function f.fn_nfe_producao_pronta(uuid) is
  'Libera producao somente quando cada perfil possui evento auditavel de liberacao para a homologacao autorizada mais recente e os seis campos IBS/CBS coincidem em todas as camadas.';

-- Escrita direta estava concedida por ACL (arwd). A partir daqui o cliente
-- consulta a tabela, mas toda mutacao passa por RPC SECURITY DEFINER.
revoke insert, update, delete on table f.perfil_operacao from authenticated;
grant select on table f.perfil_operacao to authenticated;

create or replace function f.trg_perfil_operacao_bloquear_escrita_direta()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  if current_user = 'authenticated' then
    raise exception using
      errcode = '42501',
      message = 'Campos do perfil fiscal so podem ser alterados pelas RPCs controladas.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_perfil_operacao_bloquear_escrita_direta
  on f.perfil_operacao;
create trigger trg_perfil_operacao_bloquear_escrita_direta
  before update of
    cst_ibs_cbs,
    cclass_trib,
    cclass_trib_versao,
    ibs_cbs_json,
    habilitado_producao,
    revisao_fiscal_em,
    revisao_fiscal_por,
    revisao_fiscal_justificativa,
    producao_decidida_em,
    producao_decidida_por,
    producao_decisao_justificativa,
    producao_homologacao_solicitacao_id,
    producao_homologacao_documento_id
  on f.perfil_operacao
  for each row execute function f.trg_perfil_operacao_bloquear_escrita_direta();

revoke all on function f.trg_perfil_operacao_bloquear_escrita_direta()
  from public, anon, authenticated;
revoke all on function f.fn_perfil_operacao_nfe_homologacoes_listar(uuid)
  from public, anon, authenticated;
grant execute on function f.fn_perfil_operacao_nfe_homologacoes_listar(uuid)
  to authenticated, service_role;
revoke all on function f.fn_perfil_operacao_nfe_revisar(
  uuid, text, text, text, numeric, numeric, numeric, text
) from public, anon, authenticated;
grant execute on function f.fn_perfil_operacao_nfe_revisar(
  uuid, text, text, text, numeric, numeric, numeric, text
) to authenticated, service_role;
revoke all on function f.fn_perfil_operacao_nfe_liberar_producao(uuid, uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function f.fn_perfil_operacao_nfe_liberar_producao(uuid, uuid, text, boolean)
  to authenticated, service_role;
revoke all on function f.fn_nfe_producao_pronta(uuid) from public, anon;
grant execute on function f.fn_nfe_producao_pronta(uuid) to authenticated, service_role;

-- Falha a migration se uma heranca inesperada ainda deixar escrita direta.
do $block$
begin
  if has_table_privilege('authenticated', 'f.perfil_operacao', 'INSERT')
     or has_table_privilege('authenticated', 'f.perfil_operacao', 'UPDATE')
     or has_table_privilege('authenticated', 'f.perfil_operacao', 'DELETE') then
    raise exception 'ACL insegura: authenticated ainda possui escrita direta em f.perfil_operacao.';
  end if;
  if not has_table_privilege('authenticated', 'f.perfil_operacao', 'SELECT') then
    raise exception 'ACL invalida: authenticated precisa manter SELECT em f.perfil_operacao.';
  end if;
end;
$block$;

notify pgrst, 'reload schema';

commit;
