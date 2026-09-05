begin;

alter table c.empresa_fiscal
  add column if not exists serie_nfe smallint,
  add column if not exists email_fisco text,
  add column if not exists certificado_validade_em date;

alter table c.empresa_fiscal
  drop constraint if exists empresa_fiscal_serie_nfe_ck,
  drop constraint if exists empresa_fiscal_email_fisco_ck,
  add constraint empresa_fiscal_serie_nfe_ck
    check (serie_nfe is null or serie_nfe between 1 and 999),
  add constraint empresa_fiscal_email_fisco_ck
    check (email_fisco is null or email_fisco ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$');

comment on column c.empresa_fiscal.serie_nfe is
  'Serie usada pelo ERP. A Focus controla o proximo numero dentro da serie; o ERP nao mantem contador.';
comment on column c.empresa_fiscal.email_fisco is
  'Email fiscal dedicado da empresa. Nao e o email do destinatario da NF-e.';
comment on column c.empresa_fiscal.certificado_validade_em is
  'Validade do certificado A1 da empresa; a aplicacao alerta a partir de 30 dias antes.';

-- A serie 2 foi definida para o ERP novo. Os demais dados continuam nulos
-- ate serem obtidos de fonte documental ou confirmados pelo responsavel.
insert into c.empresa_fiscal (empresa_id, serie_nfe)
select e.id, 2
from c.empresa e
where e.codigo in ('SEG', 'SGU')
  and e.ativo is true
  and e.deleted_at is null
on conflict (empresa_id) where deleted_at is null
do update set serie_nfe = coalesce(c.empresa_fiscal.serie_nfe, excluded.serie_nfe);

alter table public.clientes
  add column if not exists indicador_ie_sugerido text,
  add column if not exists indicador_ie_sugerido_regra text,
  add column if not exists indicador_ie_sugerido_em timestamptz;

alter table public.clientes
  drop constraint if exists clientes_indicador_ie_sugerido_ck,
  drop constraint if exists clientes_codigo_ibge_municipio_ck,
  add constraint clientes_indicador_ie_sugerido_ck
    check (indicador_ie_sugerido is null or indicador_ie_sugerido in ('1', '2', '9')),
  add constraint clientes_codigo_ibge_municipio_ck
    check (codigo_ibge_municipio is null or codigo_ibge_municipio ~ '^[0-9]{7}$');

comment on column public.clientes.indicador_ie_sugerido is
  'Sugestao mecanica para indIEDest; nunca substitui o campo indicador_ie sem confirmacao humana.';
comment on column public.clientes.indicador_ie_sugerido_regra is
  'Regra objetiva que originou a sugestao de indIEDest.';

create or replace function public.normalizar_nome_municipio(p_nome text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $function$
  select nullif(
    btrim(
      regexp_replace(
        translate(
          lower(coalesce(p_nome, '')),
          'áàâãäéèêëíìîïóòôõöúùûüçñ',
          'aaaaaeeeeiiiiooooouuuucn'
        ),
        '[^a-z0-9]+', ' ', 'g'
      )
    ),
    ''
  );
$function$;

create or replace function public.normalizar_unidade_xml(p_unidade text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $function$
  select case upper(btrim(coalesce(p_unidade, '')))
    when '' then null
    when 'ST' then 'PC'
    when 'PÇ' then 'PC'
    when 'PÇS' then 'PC'
    when 'PCS' then 'PC'
    when 'UND' then 'UN'
    when 'UNID' then 'UN'
    else upper(btrim(p_unidade))
  end;
$function$;

create table public.municipios_ibge (
  codigo_ibge text primary key,
  nome text not null,
  nome_normalizado text not null,
  uf text not null,
  fonte text not null default 'IBGE API Localidades',
  fonte_versao text,
  atualizado_em timestamptz not null default now(),
  constraint municipios_ibge_codigo_ck check (codigo_ibge ~ '^[0-9]{7}$'),
  constraint municipios_ibge_uf_ck check (uf ~ '^[A-Z]{2}$'),
  constraint municipios_ibge_nome_normalizado_ck
    check (nome_normalizado = public.normalizar_nome_municipio(nome))
);

create index municipios_ibge_nome_uf_idx
  on public.municipios_ibge (uf, nome_normalizado);

alter table public.municipios_ibge enable row level security;
create policy municipios_ibge_select
  on public.municipios_ibge
  for select
  to authenticated
  using (true);

grant select on public.municipios_ibge to authenticated;
grant select, insert, update on public.municipios_ibge to service_role;

create table public.fiscal_backfill_lote (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references c.tenant(id),
  data_referencia date not null,
  itens_prioritarios integer not null default 0,
  origem_propostas integer not null default 0,
  ncm_propostas integer not null default 0,
  cest_propostas integer not null default 0,
  unidade_propostas integer not null default 0,
  origem_aplicadas integer not null default 0,
  ncm_aplicadas integer not null default 0,
  cest_aplicadas integer not null default 0,
  unidade_aplicadas integer not null default 0,
  preparado_em timestamptz not null default now(),
  aplicado_em timestamptz
);

create table public.fiscal_backfill_item (
  lote_id uuid not null references public.fiscal_backfill_lote(id) on delete cascade,
  tenant_id uuid not null,
  empresa_id uuid not null,
  item_id integer not null,
  documentos_evidencia integer not null default 0,
  origem_antes smallint,
  origem_proposta smallint,
  origem_conflito boolean not null default false,
  origem_aplicada boolean not null default false,
  ncm_antes text,
  ncm_proposta text,
  ncm_conflito boolean not null default false,
  ncm_aplicada boolean not null default false,
  cest_antes text,
  cest_proposta text,
  cest_conflito boolean not null default false,
  cest_aplicada boolean not null default false,
  unidade_antes text,
  unidade_proposta text,
  unidade_conflito boolean not null default false,
  unidade_aplicada boolean not null default false,
  primary key (lote_id, tenant_id, empresa_id, item_id),
  foreign key (tenant_id, empresa_id, item_id)
    references public.fiscal_itens(tenant_id, empresa_id, item_id)
);

create index fiscal_backfill_item_pendencias_idx
  on public.fiscal_backfill_item (lote_id, origem_conflito, ncm_conflito, unidade_conflito);

alter table public.fiscal_backfill_lote enable row level security;
alter table public.fiscal_backfill_item enable row level security;
grant select, insert, update on public.fiscal_backfill_lote to service_role;
grant select, insert, update on public.fiscal_backfill_item to service_role;

create or replace function public.fn_fiscal_xml_backfill_preparar(
  p_tenant_id uuid,
  p_data_referencia date default current_date
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $function$
declare
  v_lote_id uuid;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Apenas service_role pode preparar o backfill fiscal.';
  end if;
  if p_tenant_id is null or p_data_referencia is null then
    raise exception 'tenant_id e data_referencia sao obrigatorios.';
  end if;

  insert into public.fiscal_backfill_lote (tenant_id, data_referencia)
  values (p_tenant_id, p_data_referencia)
  returning id into v_lote_id;

  with prioridade as materialized (
    select distinct i.tenant_id, i.empresa_id, i.id as item_id
    from public.itens i
    join public.os_itens oi
      on oi.tenant_id = i.tenant_id
     and oi.empresa_id = i.empresa_id
     and oi.item_id = i.id
    join public.ordens_servico os
      on os.id = oi.os_id
     and os.tenant_id = oi.tenant_id
     and os.empresa_id = oi.empresa_id
    where i.tenant_id = p_tenant_id
      and i.ativo is true
      and os.data_abertura >= p_data_referencia - interval '12 months'
      and os.data_abertura < p_data_referencia + interval '1 day'
      and lower(coalesce(os.status, '')) <> 'cancelada'
      and coalesce(os.tipo_documento, 'OS') in ('OS', 'OV')
  ), entrada_notas as materialized (
    select ne.id, ne.tenant_id, ne.empresa_id,
           xmlparse(document ne.xml_raw) as doc
    from public.nf_entrada ne
    where ne.tenant_id = p_tenant_id
      and ne.deleted_at is null
      and nullif(btrim(ne.xml_raw), '') is not null
  ), entrada_itens as materialized (
    select ni.tenant_id, ni.empresa_id, ni.nf_entrada_id,
           ni.item_id::integer as item_id,
           row_number() over (partition by ni.nf_entrada_id order by ni.id)::integer as ord
    from public.nf_entrada_itens ni
    join entrada_notas n
      on n.id = ni.nf_entrada_id
     and n.tenant_id = ni.tenant_id
     and n.empresa_id = ni.empresa_id
    where ni.item_id is not null
  ), evidencia as materialized (
    select ei.tenant_id, ei.empresa_id, ei.item_id, n.id as documento_id,
           nullif(regexp_replace(x.ncm, '[^0-9]', '', 'g'), '') as ncm,
           case when btrim(x.origem) ~ '^[0-8]$' then btrim(x.origem)::smallint end as origem,
           case when length(regexp_replace(x.cest, '[^0-9]', '', 'g')) = 7
                then regexp_replace(x.cest, '[^0-9]', '', 'g') end as cest,
           public.normalizar_unidade_xml(x.utrib) as unidade
    from entrada_notas n
    cross join lateral xmltable(
      xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
      '//n:det' passing n.doc columns
        ord for ordinality,
        ncm text path 'string(.//n:NCM)',
        origem text path 'string(.//n:ICMS/*/n:orig)',
        cest text path 'string(.//n:CEST)',
        utrib text path 'string(.//n:uTrib)'
    ) x
    join entrada_itens ei
      on ei.nf_entrada_id = n.id
     and ei.ord = x.ord
    join prioridade p
      on p.tenant_id = ei.tenant_id
     and p.empresa_id = ei.empresa_id
     and p.item_id = ei.item_id
  ), agregado as materialized (
    select tenant_id, empresa_id, item_id,
      count(distinct documento_id)::integer as documentos,
      count(distinct origem) as origem_valores,
      min(origem) as origem_unica,
      count(distinct ncm) filter (where length(ncm) = 8) as ncm_valores,
      min(ncm) filter (where length(ncm) = 8) as ncm_unico,
      count(distinct cest) as cest_valores,
      min(cest) as cest_unico,
      count(distinct unidade) as unidade_valores,
      min(unidade) as unidade_unica
    from evidencia
    group by tenant_id, empresa_id, item_id
  )
  insert into public.fiscal_backfill_item (
    lote_id, tenant_id, empresa_id, item_id, documentos_evidencia,
    origem_antes, origem_proposta, origem_conflito,
    ncm_antes, ncm_proposta, ncm_conflito,
    cest_antes, cest_proposta, cest_conflito,
    unidade_antes, unidade_proposta, unidade_conflito
  )
  select v_lote_id, p.tenant_id, p.empresa_id, p.item_id,
    coalesce(a.documentos, 0),
    fi.origem,
    case when a.origem_valores = 1 then a.origem_unica end,
    coalesce(a.origem_valores > 1, false),
    nullif(btrim(fi.ncm), ''),
    case when a.ncm_valores = 1 then a.ncm_unico end,
    coalesce(a.ncm_valores > 1, false),
    nullif(btrim(fi.cest), ''),
    case when a.cest_valores = 1 then a.cest_unico end,
    coalesce(a.cest_valores > 1, false),
    nullif(btrim(fi.unidade_tributavel), ''),
    case when a.unidade_valores = 1 then a.unidade_unica end,
    coalesce(a.unidade_valores > 1, false)
  from prioridade p
  join public.fiscal_itens fi
    on fi.tenant_id = p.tenant_id
   and fi.empresa_id = p.empresa_id
   and fi.item_id = p.item_id
  left join agregado a
    on a.tenant_id = p.tenant_id
   and a.empresa_id = p.empresa_id
   and a.item_id = p.item_id;

  update public.fiscal_backfill_lote l
  set itens_prioritarios = s.total,
      origem_propostas = s.origem,
      ncm_propostas = s.ncm,
      cest_propostas = s.cest,
      unidade_propostas = s.unidade
  from (
    select lote_id, count(*)::integer as total,
      count(*) filter (where origem_antes is null and origem_proposta is not null)::integer as origem,
      count(*) filter (where ncm_antes is null and ncm_proposta is not null)::integer as ncm,
      count(*) filter (where cest_antes is null and cest_proposta is not null)::integer as cest,
      count(*) filter (where unidade_antes is null and unidade_proposta is not null)::integer as unidade
    from public.fiscal_backfill_item
    where lote_id = v_lote_id
    group by lote_id
  ) s
  where l.id = s.lote_id;

  return v_lote_id;
end;
$function$;

create or replace function public.fn_fiscal_xml_backfill_aplicar(p_lote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $function$
declare
  v_origem integer := 0;
  v_ncm integer := 0;
  v_cest integer := 0;
  v_unidade integer := 0;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Apenas service_role pode aplicar o backfill fiscal.';
  end if;
  if not exists (select 1 from public.fiscal_backfill_lote where id = p_lote_id) then
    raise exception 'Lote de backfill nao encontrado.';
  end if;

  update public.fiscal_itens fi
     set origem = bi.origem_proposta,
         atualizado_em = now()
    from public.fiscal_backfill_item bi
   where bi.lote_id = p_lote_id
     and bi.tenant_id = fi.tenant_id
     and bi.empresa_id = fi.empresa_id
     and bi.item_id = fi.item_id
     and fi.origem is null
     and bi.origem_proposta is not null;
  get diagnostics v_origem = row_count;

  update public.fiscal_itens fi
     set ncm = bi.ncm_proposta,
         atualizado_em = now()
    from public.fiscal_backfill_item bi
   where bi.lote_id = p_lote_id
     and bi.tenant_id = fi.tenant_id
     and bi.empresa_id = fi.empresa_id
     and bi.item_id = fi.item_id
     and nullif(btrim(fi.ncm), '') is null
     and bi.ncm_proposta is not null;
  get diagnostics v_ncm = row_count;

  update public.fiscal_itens fi
     set cest = bi.cest_proposta,
         atualizado_em = now()
    from public.fiscal_backfill_item bi
   where bi.lote_id = p_lote_id
     and bi.tenant_id = fi.tenant_id
     and bi.empresa_id = fi.empresa_id
     and bi.item_id = fi.item_id
     and nullif(btrim(fi.cest), '') is null
     and bi.cest_proposta is not null;
  get diagnostics v_cest = row_count;

  update public.fiscal_itens fi
     set unidade_tributavel = bi.unidade_proposta,
         atualizado_em = now()
    from public.fiscal_backfill_item bi
   where bi.lote_id = p_lote_id
     and bi.tenant_id = fi.tenant_id
     and bi.empresa_id = fi.empresa_id
     and bi.item_id = fi.item_id
     and nullif(btrim(fi.unidade_tributavel), '') is null
     and bi.unidade_proposta is not null;
  get diagnostics v_unidade = row_count;

  update public.fiscal_backfill_item bi
     set origem_aplicada = bi.origem_antes is null and bi.origem_proposta is not null and fi.origem = bi.origem_proposta,
         ncm_aplicada = bi.ncm_antes is null and bi.ncm_proposta is not null and fi.ncm = bi.ncm_proposta,
         cest_aplicada = bi.cest_antes is null and bi.cest_proposta is not null and fi.cest = bi.cest_proposta,
         unidade_aplicada = bi.unidade_antes is null and bi.unidade_proposta is not null and fi.unidade_tributavel = bi.unidade_proposta
    from public.fiscal_itens fi
   where bi.lote_id = p_lote_id
     and fi.tenant_id = bi.tenant_id
     and fi.empresa_id = bi.empresa_id
     and fi.item_id = bi.item_id;

  update public.fiscal_backfill_lote
     set origem_aplicadas = v_origem,
         ncm_aplicadas = v_ncm,
         cest_aplicadas = v_cest,
         unidade_aplicadas = v_unidade,
         aplicado_em = now()
   where id = p_lote_id;

  return jsonb_build_object(
    'lote_id', p_lote_id,
    'origem', v_origem,
    'ncm', v_ncm,
    'cest', v_cest,
    'unidade_tributavel', v_unidade
  );
end;
$function$;

create or replace function public.fn_clientes_cadastro_candidatos(
  p_tenant_id uuid,
  p_data_referencia date default current_date
)
returns table (
  id integer,
  tenant_id uuid,
  empresa_id uuid,
  nome text,
  documento text,
  cidade text,
  uf text,
  codigo_ibge_municipio text,
  ibge_matches integer,
  ibge_sugerido text,
  indicador_ie text,
  indicador_sugerido text,
  indicador_regra text
)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $function$
  with movimento as (
    select os.tenant_id, os.empresa_id, os.cliente_id
    from public.ordens_servico os
    where os.tenant_id = p_tenant_id
      and os.cliente_id is not null
      and os.data_abertura >= p_data_referencia - interval '12 months'
      and os.data_abertura < p_data_referencia + interval '1 day'
      and lower(coalesce(os.status, '')) <> 'cancelada'
      and coalesce(os.tipo_documento, 'OS') in ('OS', 'OV')
    union
    select df.tenant_id, df.empresa_id, df.cliente_id
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id
      and df.cliente_id is not null
      and df.deleted_at is null
      and df.operacao = 'SAIDA'
      and df.emissao_date >= p_data_referencia - interval '12 months'
      and df.emissao_date < p_data_referencia + interval '1 day'
  ), base as (
    select c.id, c.tenant_id, c.empresa_id, c.nome, c.documento,
      c.cidade, c.uf, c.inscricao_estadual, c.indicador_ie,
      c.codigo_ibge_municipio,
      public.normalizar_nome_municipio(c.cidade) as cidade_normalizada,
      upper(btrim(coalesce(c.uf, ''))) as uf_normalizada,
      regexp_replace(coalesce(c.documento, ''), '[^0-9]', '', 'g') as documento_digitos,
      btrim(coalesce(c.inscricao_estadual, '')) as ie_normalizada
    from public.clientes c
    join movimento m
      on m.tenant_id = c.tenant_id
     and m.empresa_id = c.empresa_id
     and m.cliente_id = c.id
    where c.tenant_id = p_tenant_id
      and c.ativo is true
  )
  select b.id, b.tenant_id, b.empresa_id, b.nome, b.documento, b.cidade, b.uf,
    b.codigo_ibge_municipio,
    count(mi.codigo_ibge)::integer as ibge_matches,
    min(mi.codigo_ibge) as ibge_sugerido,
    b.indicador_ie,
    case
      when b.ie_normalizada ~ '^[0-9]+$' then '1'
      when upper(b.ie_normalizada) = 'ISENTO' then '2'
      when length(b.documento_digitos) = 11 and b.ie_normalizada = '' then '9'
      else null
    end as indicador_sugerido,
    case
      when b.ie_normalizada ~ '^[0-9]+$' then 'IE numerica preenchida'
      when upper(b.ie_normalizada) = 'ISENTO' then 'IE literal ISENTO'
      when length(b.documento_digitos) = 11 and b.ie_normalizada = '' then 'Pessoa fisica sem IE'
      else null
    end as indicador_regra
  from base b
  left join public.municipios_ibge mi
    on mi.uf = b.uf_normalizada
   and mi.nome_normalizado = b.cidade_normalizada
  group by b.id, b.tenant_id, b.empresa_id, b.nome, b.documento,
    b.cidade, b.uf, b.codigo_ibge_municipio, b.indicador_ie,
    b.documento_digitos, b.ie_normalizada;
$function$;

create or replace function public.fn_clientes_cadastro_sem_contador(
  p_tenant_id uuid,
  p_data_referencia date default current_date,
  p_aplicar boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $function$
declare
  v_resultado jsonb;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Apenas service_role pode executar o saneamento de clientes.';
  end if;

  if p_aplicar then
    update public.clientes c
       set codigo_ibge_municipio = t.ibge_sugerido,
           atualizado_em = now()
      from public.fn_clientes_cadastro_candidatos(p_tenant_id, p_data_referencia) t
     where c.id = t.id
       and c.tenant_id = t.tenant_id
       and c.empresa_id = t.empresa_id
       and c.codigo_ibge_municipio is null
       and t.ibge_matches = 1;

    update public.clientes c
       set indicador_ie_sugerido = t.indicador_sugerido,
           indicador_ie_sugerido_regra = t.indicador_regra,
           indicador_ie_sugerido_em = case when t.indicador_sugerido is null then null else now() end,
           atualizado_em = now()
      from public.fn_clientes_cadastro_candidatos(p_tenant_id, p_data_referencia) t
     where c.id = t.id
       and c.tenant_id = t.tenant_id
       and c.empresa_id = t.empresa_id
       and c.indicador_ie is null;
  end if;

  select jsonb_build_object(
    'clientes_movimentados', count(*),
    'ibge_match_unico', count(*) filter (where ibge_matches = 1),
    'ibge_ambiguos', count(*) filter (where ibge_matches > 1),
    'ibge_sem_match', count(*) filter (where ibge_matches = 0),
    'indicador_1_sugerido', count(*) filter (where indicador_sugerido = '1'),
    'indicador_2_sugerido', count(*) filter (where indicador_sugerido = '2'),
    'indicador_9_sugerido', count(*) filter (where indicador_sugerido = '9'),
    'indicador_sem_sugestao', count(*) filter (where indicador_sugerido is null),
    'excecoes_ibge', coalesce(jsonb_agg(
      jsonb_build_object(
        'cliente_id', id, 'empresa_id', empresa_id, 'nome', nome,
        'cidade', cidade, 'uf', uf, 'matches', ibge_matches
      ) order by nome
    ) filter (where ibge_matches <> 1), '[]'::jsonb)
  ) into v_resultado
  from public.fn_clientes_cadastro_candidatos(p_tenant_id, p_data_referencia);

  return v_resultado || jsonb_build_object('aplicado', p_aplicar);
end;
$function$;

create or replace function public.empresa_certificado_alerta()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $function$
  select jsonb_build_object(
    'empresa_id', e.id,
    'serie_nfe', ef.serie_nfe,
    'certificado_validade_em', ef.certificado_validade_em,
    'dias_para_vencer',
      case
        when ef.certificado_validade_em is null then null
        else ef.certificado_validade_em - current_date
      end
  )
  from c.empresa e
  left join lateral (
    select x.serie_nfe, x.certificado_validade_em
    from c.empresa_fiscal x
    where x.empresa_id = e.id
      and x.deleted_at is null
    order by x.updated_at desc
    limit 1
  ) ef on true
  where e.tenant_id = public.current_tenant_id()
    and e.id = public.current_empresa_id()
    and e.ativo is true
    and e.deleted_at is null;
$function$;

revoke all on function public.fn_fiscal_xml_backfill_preparar(uuid, date) from public, anon, authenticated;
revoke all on function public.fn_fiscal_xml_backfill_aplicar(uuid) from public, anon, authenticated;
revoke all on function public.fn_clientes_cadastro_candidatos(uuid, date) from public, anon, authenticated;
revoke all on function public.fn_clientes_cadastro_sem_contador(uuid, date, boolean) from public, anon, authenticated;
revoke all on function public.empresa_certificado_alerta() from public, anon;
grant execute on function public.fn_fiscal_xml_backfill_preparar(uuid, date) to service_role;
grant execute on function public.fn_fiscal_xml_backfill_aplicar(uuid) to service_role;
grant execute on function public.fn_clientes_cadastro_candidatos(uuid, date) to service_role;
grant execute on function public.fn_clientes_cadastro_sem_contador(uuid, date, boolean) to service_role;
grant execute on function public.empresa_certificado_alerta() to authenticated, service_role;

commit;
