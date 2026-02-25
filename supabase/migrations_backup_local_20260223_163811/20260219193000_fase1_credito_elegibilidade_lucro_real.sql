-- Fase 1 (Lucro Real): elegibilidade de credito por item + conferencia provisionado x efetivo

alter table public.nf_entrada_itens
  add column if not exists icms_credito_modo text,
  add column if not exists pis_credito_modo text,
  add column if not exists cofins_credito_modo text,
  add column if not exists icms_credito_valor_elegivel numeric(14,2),
  add column if not exists pis_credito_valor_elegivel numeric(14,2),
  add column if not exists cofins_credito_valor_elegivel numeric(14,2),
  add column if not exists credito_classificado_em timestamptz,
  add column if not exists credito_classificacao_fonte text;

update public.nf_entrada_itens
set
  icms_credito_modo = coalesce(icms_credito_modo, 'PENDENTE_REVISAO'),
  pis_credito_modo = coalesce(pis_credito_modo, 'PENDENTE_REVISAO'),
  cofins_credito_modo = coalesce(cofins_credito_modo, 'PENDENTE_REVISAO'),
  icms_credito_valor_elegivel = coalesce(icms_credito_valor_elegivel, 0),
  pis_credito_valor_elegivel = coalesce(pis_credito_valor_elegivel, 0),
  cofins_credito_valor_elegivel = coalesce(cofins_credito_valor_elegivel, 0)
where
  icms_credito_modo is null
  or pis_credito_modo is null
  or cofins_credito_modo is null
  or icms_credito_valor_elegivel is null
  or pis_credito_valor_elegivel is null
  or cofins_credito_valor_elegivel is null;

alter table public.nf_entrada_itens
  alter column icms_credito_modo set default 'PENDENTE_REVISAO',
  alter column pis_credito_modo set default 'PENDENTE_REVISAO',
  alter column cofins_credito_modo set default 'PENDENTE_REVISAO',
  alter column icms_credito_valor_elegivel set default 0,
  alter column pis_credito_valor_elegivel set default 0,
  alter column cofins_credito_valor_elegivel set default 0;

alter table public.nf_entrada_itens
  alter column icms_credito_modo set not null,
  alter column pis_credito_modo set not null,
  alter column cofins_credito_modo set not null,
  alter column icms_credito_valor_elegivel set not null,
  alter column pis_credito_valor_elegivel set not null,
  alter column cofins_credito_valor_elegivel set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'nf_entrada_itens_icms_credito_modo_ck'
      and conrelid = 'public.nf_entrada_itens'::regclass
  ) then
    alter table public.nf_entrada_itens
      add constraint nf_entrada_itens_icms_credito_modo_ck
      check (icms_credito_modo in ('NAO_CREDITA','CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'nf_entrada_itens_pis_credito_modo_ck'
      and conrelid = 'public.nf_entrada_itens'::regclass
  ) then
    alter table public.nf_entrada_itens
      add constraint nf_entrada_itens_pis_credito_modo_ck
      check (pis_credito_modo in ('NAO_CREDITA','CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'nf_entrada_itens_cofins_credito_modo_ck'
      and conrelid = 'public.nf_entrada_itens'::regclass
  ) then
    alter table public.nf_entrada_itens
      add constraint nf_entrada_itens_cofins_credito_modo_ck
      check (cofins_credito_modo in ('NAO_CREDITA','CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO'));
  end if;
end $$;

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
  select n.id, n.tenant_id, n.empresa_id, n.finalidade_contexto
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

  update public.nf_entrada_itens ni
  set
    icms_credito_modo = case
      when coalesce(ni.v_icms,0) <= 0 then 'NAO_CREDITA'
      when coalesce(fi.credita_icms,false) is not true then 'NAO_CREDITA'
      when coalesce(i.finalidade, v_nf.finalidade_contexto)::text = 'materia_prima' then 'CREDITA_IMEDIATO'
      when coalesce(i.finalidade, v_nf.finalidade_contexto)::text = 'imobilizado' then 'CREDITA_PARCELADO'
      else 'PENDENTE_REVISAO'
    end,
    pis_credito_modo = case
      when coalesce(ni.v_pis,0) <= 0 then 'NAO_CREDITA'
      when coalesce(fi.credita_pis,false) is not true then 'NAO_CREDITA'
      when coalesce(i.finalidade, v_nf.finalidade_contexto)::text = 'materia_prima' then 'CREDITA_IMEDIATO'
      when coalesce(i.finalidade, v_nf.finalidade_contexto)::text = 'imobilizado' then 'CREDITA_PARCELADO'
      else 'PENDENTE_REVISAO'
    end,
    cofins_credito_modo = case
      when coalesce(ni.v_cofins,0) <= 0 then 'NAO_CREDITA'
      when coalesce(fi.credita_cofins,false) is not true then 'NAO_CREDITA'
      when coalesce(i.finalidade, v_nf.finalidade_contexto)::text = 'materia_prima' then 'CREDITA_IMEDIATO'
      when coalesce(i.finalidade, v_nf.finalidade_contexto)::text = 'imobilizado' then 'CREDITA_PARCELADO'
      else 'PENDENTE_REVISAO'
    end,
    icms_credito_valor_elegivel = case
      when coalesce(ni.v_icms,0) <= 0 then 0
      when coalesce(fi.credita_icms,false) is not true then 0
      else round(coalesce(ni.v_icms,0)::numeric,2)
    end,
    pis_credito_valor_elegivel = case
      when coalesce(ni.v_pis,0) <= 0 then 0
      when coalesce(fi.credita_pis,false) is not true then 0
      else round(coalesce(ni.v_pis,0)::numeric,2)
    end,
    cofins_credito_valor_elegivel = case
      when coalesce(ni.v_cofins,0) <= 0 then 0
      when coalesce(fi.credita_cofins,false) is not true then 0
      else round(coalesce(ni.v_cofins,0)::numeric,2)
    end,
    credito_classificado_em = now(),
    credito_classificacao_fonte = coalesce(nullif(trim(p_fonte),''), 'AUTO_IMPORT')
  from public.itens i
  left join public.fiscal_itens fi
    on fi.tenant_id = v_nf.tenant_id
   and fi.empresa_id = v_nf.empresa_id
   and fi.item_id = i.id
  where ni.nf_entrada_id = v_nf.id
    and i.id = ni.item_id
    and i.tenant_id = v_nf.tenant_id
    and i.empresa_id = v_nf.empresa_id;

  get diagnostics v_count = row_count;

  status := 'ok';
  message := 'Classificacao de credito fiscal concluida (Fase 1).';
  itens_atualizados := coalesce(v_count,0);
  return next;
end;
$$;

create or replace function public.trg_nf_entrada_itens__classificar_credito_fiscal()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_nf_id bigint;
begin
  v_nf_id := coalesce(new.nf_entrada_id, old.nf_entrada_id);
  if v_nf_id is not null then
    perform 1
    from public.fn_classificar_credito_fiscal_nf_entrada(v_nf_id, 'TRIGGER_NF_ITEM');
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_nf_entrada_itens__classificar_credito_fiscal on public.nf_entrada_itens;

create trigger trg_nf_entrada_itens__classificar_credito_fiscal
after insert or update of item_id, v_icms, v_pis, v_cofins, nf_entrada_id
on public.nf_entrada_itens
for each row
execute function public.trg_nf_entrada_itens__classificar_credito_fiscal();

create or replace function f.fn_imposto_credito_conferencia_range(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_comp_ini date,
  p_comp_fim date
) returns table(
  competencia_date date,
  imposto text,
  valor_provisionado numeric,
  valor_efetivo numeric,
  valor_pendente_revisao numeric,
  valor_nao_creditavel numeric,
  qtd_itens_pendentes bigint,
  qtd_nfs bigint
)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to off
as $$
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id e obrigatorio.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id e obrigatorio.'; end if;
  if p_comp_ini is null or p_comp_fim is null then raise exception 'Informe p_comp_ini e p_comp_fim'; end if;
  if p_comp_fim <= p_comp_ini then raise exception 'Intervalo invalido: p_comp_fim deve ser > p_comp_ini'; end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from p_tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if public.current_empresa_id() is distinct from p_empresa_id then
      raise exception 'Empresa mismatch';
    end if;
    if not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  return query
  with docs as (
    select
      df.id as documento_fiscal_id,
      df.source_nf_entrada_id,
      df.competencia_date
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and df.deleted_at is null
      and df.operacao = 'ENTRADA'
      and df.competencia_date >= p_comp_ini
      and df.competencia_date < p_comp_fim
      and df.source_nf_entrada_id is not null
  ),
  itens as (
    select
      d.competencia_date,
      d.documento_fiscal_id,
      ni.icms_credito_modo,
      ni.pis_credito_modo,
      ni.cofins_credito_modo,
      coalesce(ni.icms_credito_valor_elegivel,0)::numeric as icms_elegivel,
      coalesce(ni.pis_credito_valor_elegivel,0)::numeric as pis_elegivel,
      coalesce(ni.cofins_credito_valor_elegivel,0)::numeric as cofins_elegivel
    from docs d
    join public.nf_entrada_itens ni
      on ni.nf_entrada_id = d.source_nf_entrada_id
  ),
  itens_unpivot as (
    select it.competencia_date, it.documento_fiscal_id, 'ICMS'::text as imposto, it.icms_credito_modo as modo, it.icms_elegivel as valor from itens it
    union all
    select it.competencia_date, it.documento_fiscal_id, 'PIS'::text as imposto, it.pis_credito_modo as modo, it.pis_elegivel as valor from itens it
    union all
    select it.competencia_date, it.documento_fiscal_id, 'COFINS'::text as imposto, it.cofins_credito_modo as modo, it.cofins_elegivel as valor from itens it
  ),
  prov as (
    select
      i.competencia_date,
      i.imposto,
      sum(case when i.modo in ('CREDITA_IMEDIATO','CREDITA_PARCELADO') then i.valor else 0 end)::numeric as valor_provisionado,
      sum(case when i.modo = 'PENDENTE_REVISAO' then i.valor else 0 end)::numeric as valor_pendente_revisao,
      sum(case when i.modo = 'NAO_CREDITA' then i.valor else 0 end)::numeric as valor_nao_creditavel,
      count(*) filter (where i.modo = 'PENDENTE_REVISAO')::bigint as qtd_itens_pendentes,
      count(distinct i.documento_fiscal_id)::bigint as qtd_nfs
    from itens_unpivot i
    group by i.competencia_date, i.imposto
  ),
  efet as (
    select
      df.competencia_date,
      dfi.imposto,
      sum(coalesce(dfi.valor_ajustado, dfi.valor_calculado, 0))::numeric as valor_efetivo
    from f.documento_fiscal_imposto dfi
    join f.documento_fiscal df
      on df.id = dfi.documento_fiscal_id
     and df.tenant_id = dfi.tenant_id
    where dfi.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and dfi.deleted_at is null
      and df.deleted_at is null
      and df.operacao = 'ENTRADA'
      and dfi.natureza = 'CREDITO'
      and dfi.imposto in ('ICMS','PIS','COFINS')
      and df.competencia_date >= p_comp_ini
      and df.competencia_date < p_comp_fim
    group by df.competencia_date, dfi.imposto
  )
  select
    coalesce(p.competencia_date, e.competencia_date) as competencia_date,
    coalesce(p.imposto, e.imposto) as imposto,
    coalesce(p.valor_provisionado, 0)::numeric as valor_provisionado,
    coalesce(e.valor_efetivo, 0)::numeric as valor_efetivo,
    coalesce(p.valor_pendente_revisao, 0)::numeric as valor_pendente_revisao,
    coalesce(p.valor_nao_creditavel, 0)::numeric as valor_nao_creditavel,
    coalesce(p.qtd_itens_pendentes, 0)::bigint as qtd_itens_pendentes,
    coalesce(p.qtd_nfs, 0)::bigint as qtd_nfs
  from prov p
  full outer join efet e
    on e.competencia_date = p.competencia_date
   and e.imposto = p.imposto
  order by 1 asc, 2 asc;
end;
$$;

revoke all on function public.fn_classificar_credito_fiscal_nf_entrada(bigint, text) from public;
grant execute on function public.fn_classificar_credito_fiscal_nf_entrada(bigint, text) to authenticated;
grant execute on function public.fn_classificar_credito_fiscal_nf_entrada(bigint, text) to service_role;

revoke all on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) from public;
grant execute on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) to authenticated;
grant execute on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) to service_role;

-- Backfill para base atual
select
  r.status,
  r.message,
  r.itens_atualizados
from public.nf_entrada ne
cross join lateral public.fn_classificar_credito_fiscal_nf_entrada(ne.id, 'BACKFILL_FASE1') r
where ne.deleted_at is null;
