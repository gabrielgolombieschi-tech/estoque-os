create table if not exists f.credito_fiscal_politica (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid,
  imposto text not null,
  modo text not null,
  prioridade integer not null default 100,
  ativo boolean not null default true,
  finalidade public.item_finalidade,
  motivo_compra_id uuid,
  cfop_like text,
  cst_like text,
  requer_credit_flag boolean not null default true,
  observacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  constraint credito_fiscal_politica_imposto_ck check (upper(imposto) in ('ICMS','PIS','COFINS')),
  constraint credito_fiscal_politica_modo_ck check (modo in ('NAO_CREDITA','CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO')),
  constraint credito_fiscal_politica_prioridade_ck check (prioridade between 1 and 9999),
  constraint credito_fiscal_politica_cfop_like_ck check (cfop_like is null or length(trim(cfop_like)) > 0),
  constraint credito_fiscal_politica_cst_like_ck check (cst_like is null or length(trim(cst_like)) > 0)
);

create index if not exists idx_credito_fiscal_politica_tenant_empresa
  on f.credito_fiscal_politica (tenant_id, empresa_id, imposto, ativo, prioridade)
  where deleted_at is null;

create index if not exists idx_credito_fiscal_politica_motivo
  on f.credito_fiscal_politica (tenant_id, motivo_compra_id)
  where deleted_at is null;

create or replace function f.fn_pick_credito_fiscal_politica(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_imposto text,
  p_finalidade public.item_finalidade,
  p_motivo_compra_id uuid,
  p_cfop text,
  p_cst text,
  p_credit_flag boolean,
  p_valor numeric
) returns table(
  modo text,
  fonte text
)
language plpgsql
security definer
set search_path to 'f', 'public'
set row_security to off
as $$
declare
  v_modo text;
begin
  if coalesce(p_valor,0) <= 0 then
    modo := 'NAO_CREDITA';
    fonte := 'VALOR_ZERADO';
    return next;
    return;
  end if;

  select r.modo
    into v_modo
  from f.credito_fiscal_politica r
  where r.tenant_id = p_tenant_id
    and (r.empresa_id is null or r.empresa_id = p_empresa_id)
    and r.deleted_at is null
    and r.ativo = true
    and upper(r.imposto) = upper(p_imposto)
    and (r.finalidade is null or r.finalidade = p_finalidade)
    and (r.motivo_compra_id is null or r.motivo_compra_id = p_motivo_compra_id)
    and (r.cfop_like is null or coalesce(p_cfop,'') like r.cfop_like)
    and (r.cst_like is null or coalesce(p_cst,'') like r.cst_like)
    and (r.requer_credit_flag is false or coalesce(p_credit_flag,false) is true)
  order by
    r.prioridade asc,
    (case when r.empresa_id is null then 1 else 0 end) asc,
    (case when r.motivo_compra_id is null then 1 else 0 end) asc,
    (case when r.finalidade is null then 1 else 0 end) asc,
    (case when r.cfop_like is null then 1 else 0 end) asc,
    (case when r.cst_like is null then 1 else 0 end) asc,
    r.created_at asc
  limit 1;

  if v_modo is not null then
    modo := v_modo;
    fonte := 'POLITICA';
    return next;
    return;
  end if;

  if coalesce(p_credit_flag, false) is not true then
    modo := 'NAO_CREDITA';
    fonte := 'FALLBACK_SEM_FLAG';
    return next;
    return;
  end if;

  if p_finalidade = 'materia_prima'::public.item_finalidade then
    modo := 'CREDITA_IMEDIATO';
    fonte := 'FALLBACK_MATERIA_PRIMA';
    return next;
    return;
  end if;

  if p_finalidade = 'imobilizado'::public.item_finalidade then
    modo := 'CREDITA_PARCELADO';
    fonte := 'FALLBACK_IMOBILIZADO';
    return next;
    return;
  end if;

  modo := 'PENDENTE_REVISAO';
  fonte := 'FALLBACK_PENDENTE';
  return next;
end;
$$;

create or replace function public.fn_classificar_credito_fiscal_nf_entrada(
  p_nf_entrada_id bigint,
  p_fonte text default 'AUTO_IMPORT'
) returns table(
  status text,
  message text,
  itens_atualizados integer
)
language plpgsql
security definer
set search_path to 'public', 'f', 'a', 'c'
set row_security to off
as $$
declare
  v_nf record;
  v_count integer := 0;
begin
  select n.id, n.tenant_id, n.empresa_id, n.finalidade_contexto, n.motivo_compra_id
    into v_nf
  from public.nf_entrada n
  where n.id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from v_nf.tenant_id then
      raise exception 'Tenant mismatch';
    end if;

    if not (
      public.can('xml_import','execute', v_nf.tenant_id)
      or public.can('financeiro','write', v_nf.tenant_id)
      or public.can('financeiro','config', v_nf.tenant_id)
    ) then
      raise exception 'Sem permissao para classificar elegibilidade de credito';
    end if;
  end if;

  with base as (
    select
      ni.id,
      coalesce(i.finalidade, v_nf.finalidade_contexto) as finalidade_aplicada,
      coalesce(ni.cfop, fi.cfop_padrao) as cfop_aplicado,
      fi.cst_icms,
      fi.cst_pis,
      fi.cst_cofins,
      coalesce(fi.credita_icms,false) as credita_icms,
      coalesce(fi.credita_pis,false) as credita_pis,
      coalesce(fi.credita_cofins,false) as credita_cofins,
      coalesce(ni.v_icms,0)::numeric as v_icms,
      coalesce(ni.v_pis,0)::numeric as v_pis,
      coalesce(ni.v_cofins,0)::numeric as v_cofins
    from public.nf_entrada_itens ni
    left join public.itens i
      on i.id = ni.item_id
     and i.tenant_id = v_nf.tenant_id
     and i.empresa_id = v_nf.empresa_id
    left join public.fiscal_itens fi
      on fi.tenant_id = v_nf.tenant_id
     and fi.empresa_id = v_nf.empresa_id
     and fi.item_id = ni.item_id
    where ni.nf_entrada_id = v_nf.id
  ),
  picked as (
    select
      b.id,
      pic_icms.modo as icms_modo,
      pic_icms.fonte as icms_fonte,
      pic_pis.modo as pis_modo,
      pic_pis.fonte as pis_fonte,
      pic_cofins.modo as cofins_modo,
      pic_cofins.fonte as cofins_fonte,
      b.v_icms,
      b.v_pis,
      b.v_cofins,
      b.credita_icms,
      b.credita_pis,
      b.credita_cofins
    from base b
    cross join lateral f.fn_pick_credito_fiscal_politica(
      v_nf.tenant_id,
      v_nf.empresa_id,
      'ICMS',
      b.finalidade_aplicada,
      v_nf.motivo_compra_id,
      b.cfop_aplicado,
      b.cst_icms,
      b.credita_icms,
      b.v_icms
    ) pic_icms
    cross join lateral f.fn_pick_credito_fiscal_politica(
      v_nf.tenant_id,
      v_nf.empresa_id,
      'PIS',
      b.finalidade_aplicada,
      v_nf.motivo_compra_id,
      b.cfop_aplicado,
      b.cst_pis,
      b.credita_pis,
      b.v_pis
    ) pic_pis
    cross join lateral f.fn_pick_credito_fiscal_politica(
      v_nf.tenant_id,
      v_nf.empresa_id,
      'COFINS',
      b.finalidade_aplicada,
      v_nf.motivo_compra_id,
      b.cfop_aplicado,
      b.cst_cofins,
      b.credita_cofins,
      b.v_cofins
    ) pic_cofins
  )
  update public.nf_entrada_itens ni
  set
    icms_credito_modo = p.icms_modo,
    pis_credito_modo = p.pis_modo,
    cofins_credito_modo = p.cofins_modo,
    icms_credito_valor_elegivel = case when p.icms_modo in ('CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO') then round(p.v_icms,2) else 0 end,
    pis_credito_valor_elegivel = case when p.pis_modo in ('CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO') then round(p.v_pis,2) else 0 end,
    cofins_credito_valor_elegivel = case when p.cofins_modo in ('CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO') then round(p.v_cofins,2) else 0 end,
    credito_classificado_em = now(),
    credito_classificacao_fonte = concat_ws(';', coalesce(nullif(trim(p_fonte),''), 'AUTO_IMPORT'), p.icms_fonte, p.pis_fonte, p.cofins_fonte)
  from picked p
  where ni.id = p.id;

  get diagnostics v_count = row_count;

  status := 'ok';
  message := 'Classificacao de credito fiscal concluida (Fase 2/politica).';
  itens_atualizados := coalesce(v_count,0);
  return next;
end;
$$;

create or replace function f.upsert_credito_fiscal_politica(
  p_id uuid default null,
  p_tenant_id uuid default null,
  p_empresa_id uuid default null,
  p_imposto text default null,
  p_modo text default null,
  p_prioridade integer default 100,
  p_ativo boolean default true,
  p_finalidade public.item_finalidade default null,
  p_motivo_compra_id uuid default null,
  p_cfop_like text default null,
  p_cst_like text default null,
  p_requer_credit_flag boolean default true,
  p_observacao text default null
) returns uuid
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to off
as $$
declare
  v_id uuid;
  v_tenant_id uuid;
  v_exists boolean;
begin
  v_tenant_id := coalesce(p_tenant_id, public.current_tenant_id());
  if v_tenant_id is null then
    raise exception 'tenant_id obrigatorio';
  end if;
  if coalesce(trim(p_imposto),'') = '' then
    raise exception 'imposto obrigatorio';
  end if;
  if coalesce(trim(p_modo),'') = '' then
    raise exception 'modo obrigatorio';
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from v_tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if not f.has_finance_access(v_tenant_id, coalesce(p_empresa_id, public.current_empresa_id())) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  if p_id is not null then
    select exists(
      select 1
      from f.credito_fiscal_politica x
      where x.id = p_id
        and x.tenant_id = v_tenant_id
    ) into v_exists;
  else
    v_exists := false;
  end if;

  if v_exists then
    update f.credito_fiscal_politica
       set empresa_id = p_empresa_id,
           imposto = upper(trim(p_imposto)),
           modo = p_modo,
           prioridade = coalesce(p_prioridade, 100),
           ativo = coalesce(p_ativo, true),
           finalidade = p_finalidade,
           motivo_compra_id = p_motivo_compra_id,
           cfop_like = nullif(trim(coalesce(p_cfop_like,'')),''),
           cst_like = nullif(trim(coalesce(p_cst_like,'')),''),
           requer_credit_flag = coalesce(p_requer_credit_flag, true),
           observacao = p_observacao,
           updated_at = now(),
           updated_by = a.fn_current_usuario_id(),
           deleted_at = null
     where id = p_id
       and tenant_id = v_tenant_id
    returning id into v_id;
  else
    insert into f.credito_fiscal_politica(
      tenant_id, empresa_id, imposto, modo, prioridade, ativo, finalidade,
      motivo_compra_id, cfop_like, cst_like, requer_credit_flag, observacao,
      created_by, updated_by
    ) values (
      v_tenant_id, p_empresa_id, upper(trim(p_imposto)), p_modo, coalesce(p_prioridade,100),
      coalesce(p_ativo,true), p_finalidade, p_motivo_compra_id,
      nullif(trim(coalesce(p_cfop_like,'')),''), nullif(trim(coalesce(p_cst_like,'')),''),
      coalesce(p_requer_credit_flag,true), p_observacao,
      a.fn_current_usuario_id(), a.fn_current_usuario_id()
    ) returning id into v_id;
  end if;

  return v_id;
end;
$$;

create or replace function f.list_credito_fiscal_politica(
  p_tenant_id uuid,
  p_empresa_id uuid default null,
  p_imposto text default null
) returns table(
  id uuid,
  tenant_id uuid,
  empresa_id uuid,
  imposto text,
  modo text,
  prioridade integer,
  ativo boolean,
  finalidade public.item_finalidade,
  motivo_compra_id uuid,
  motivo_codigo text,
  motivo_nome text,
  cfop_like text,
  cst_like text,
  requer_credit_flag boolean,
  observacao text,
  updated_at timestamptz
)
language sql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to off
as $$
  select
    r.id,
    r.tenant_id,
    r.empresa_id,
    r.imposto,
    r.modo,
    r.prioridade,
    r.ativo,
    r.finalidade,
    r.motivo_compra_id,
    mc.codigo as motivo_codigo,
    mc.nome as motivo_nome,
    r.cfop_like,
    r.cst_like,
    r.requer_credit_flag,
    r.observacao,
    r.updated_at
  from f.credito_fiscal_politica r
  left join f.motivo_compra mc
    on mc.id = r.motivo_compra_id
   and mc.tenant_id = r.tenant_id
  where r.tenant_id = p_tenant_id
    and r.deleted_at is null
    and (p_empresa_id is null or r.empresa_id is null or r.empresa_id = p_empresa_id)
    and (p_imposto is null or upper(r.imposto) = upper(p_imposto))
  order by r.imposto, r.prioridade, r.updated_at desc;
$$;

alter table f.credito_fiscal_politica enable row level security;

drop policy if exists credito_fiscal_politica_all on f.credito_fiscal_politica;
create policy credito_fiscal_politica_all
  on f.credito_fiscal_politica
  to authenticated
  using (tenant_id = public.current_tenant_id() and f.has_finance_access())
  with check (tenant_id = public.current_tenant_id() and f.has_finance_access());

revoke all on table f.credito_fiscal_politica from public;
grant select, insert, update, delete on table f.credito_fiscal_politica to authenticated;
grant select on table f.credito_fiscal_politica to service_role;

revoke all on function f.fn_pick_credito_fiscal_politica(uuid, uuid, text, public.item_finalidade, uuid, text, text, boolean, numeric) from public;
grant execute on function f.fn_pick_credito_fiscal_politica(uuid, uuid, text, public.item_finalidade, uuid, text, text, boolean, numeric) to authenticated;
grant execute on function f.fn_pick_credito_fiscal_politica(uuid, uuid, text, public.item_finalidade, uuid, text, text, boolean, numeric) to service_role;

revoke all on function f.upsert_credito_fiscal_politica(uuid, uuid, uuid, text, text, integer, boolean, public.item_finalidade, uuid, text, text, boolean, text) from public;
grant execute on function f.upsert_credito_fiscal_politica(uuid, uuid, uuid, text, text, integer, boolean, public.item_finalidade, uuid, text, text, boolean, text) to authenticated;
grant execute on function f.upsert_credito_fiscal_politica(uuid, uuid, uuid, text, text, integer, boolean, public.item_finalidade, uuid, text, text, boolean, text) to service_role;

revoke all on function f.list_credito_fiscal_politica(uuid, uuid, text) from public;
grant execute on function f.list_credito_fiscal_politica(uuid, uuid, text) to authenticated;
grant execute on function f.list_credito_fiscal_politica(uuid, uuid, text) to service_role;

-- Regras padrao (conservadoras + suporte basico por tipo de gasto/finalidade)
insert into f.credito_fiscal_politica(
  tenant_id, empresa_id, imposto, modo, prioridade, ativo, finalidade, cfop_like, requer_credit_flag, observacao
)
select
  e.tenant_id,
  e.id as empresa_id,
  imp.imposto,
  imp.modo,
  imp.prioridade,
  true,
  imp.finalidade,
  imp.cfop_like,
  true,
  imp.observacao
from public.empresas e
cross join (
  values
    ('ICMS','CREDITA_PARCELADO',10,'imobilizado'::public.item_finalidade,'1%', 'ICMS de imobilizado (entrada interna) - CIAP'),
    ('ICMS','CREDITA_PARCELADO',10,'imobilizado'::public.item_finalidade,'2%', 'ICMS de imobilizado (entrada interestadual) - CIAP'),
    ('ICMS','CREDITA_IMEDIATO',30,'materia_prima'::public.item_finalidade,'1%', 'ICMS materia-prima entrada interna'),
    ('ICMS','CREDITA_IMEDIATO',30,'materia_prima'::public.item_finalidade,'2%', 'ICMS materia-prima entrada interestadual'),
    ('PIS','CREDITA_PARCELADO',10,'imobilizado'::public.item_finalidade,null, 'PIS imobilizado - via apropriacao/depreciacao'),
    ('COFINS','CREDITA_PARCELADO',10,'imobilizado'::public.item_finalidade,null, 'COFINS imobilizado - via apropriacao/depreciacao'),
    ('PIS','CREDITA_IMEDIATO',30,'materia_prima'::public.item_finalidade,null, 'PIS nao-cumulativo sobre insumo elegivel'),
    ('COFINS','CREDITA_IMEDIATO',30,'materia_prima'::public.item_finalidade,null, 'COFINS nao-cumulativo sobre insumo elegivel'),
    ('ICMS','PENDENTE_REVISAO',900,null,'%', 'Fallback pendente (ICMS)'),
    ('PIS','PENDENTE_REVISAO',900,null,'%', 'Fallback pendente (PIS)'),
    ('COFINS','PENDENTE_REVISAO',900,null,'%', 'Fallback pendente (COFINS)')
) as imp(imposto, modo, prioridade, finalidade, cfop_like, observacao)
where coalesce(e.ativo, true) = true
  and not exists (
    select 1
    from f.credito_fiscal_politica x
    where x.tenant_id = e.tenant_id
      and x.empresa_id = e.id
      and x.imposto = imp.imposto
      and x.modo = imp.modo
      and x.prioridade = imp.prioridade
      and coalesce(x.finalidade::text,'') = coalesce(imp.finalidade::text,'')
      and coalesce(x.cfop_like,'') = coalesce(imp.cfop_like,'')
      and x.deleted_at is null
  );

-- Reclassifica historico com a politica
select r.status, r.message, r.itens_atualizados
from public.nf_entrada ne
cross join lateral public.fn_classificar_credito_fiscal_nf_entrada(ne.id, 'BACKFILL_FASE2') r
where ne.deleted_at is null;
