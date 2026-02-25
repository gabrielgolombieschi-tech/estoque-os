-- Auditoria e reparo de Contas a Pagar por NF-e de entrada.

create or replace function public.fn_auditar_ap_por_nf_entrada_range(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_comp_ini date,
  p_comp_fim date
) returns table(
  tenant_id uuid,
  empresa_id uuid,
  source_nf_entrada_id bigint,
  documento_fiscal_id uuid,
  competencia_date date,
  emissao_date date,
  chave_acesso text,
  doc_valor_total numeric,
  titulo_id uuid,
  titulo_status text,
  titulo_origem text,
  titulo_valor_total numeric,
  titulo_valor_aberto numeric,
  titulo_deleted_at timestamptz,
  parcelas_count bigint,
  parcelas_total numeric,
  has_issue boolean,
  issue_codes text
)
language sql
security definer
set search_path to 'public', 'f', 'a', 'c'
set row_security to 'off'
as $$
with docs as (
  select
    df.tenant_id,
    df.empresa_id,
    df.source_nf_entrada_id,
    df.id as documento_fiscal_id,
    df.competencia_date,
    df.emissao_date,
    df.chave_acesso,
    coalesce(df.valor_total, 0)::numeric as doc_valor_total
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.deleted_at is null
    and df.operacao = 'ENTRADA'
    and df.natureza = 'PRODUTO'
    and df.source_nf_entrada_id is not null
    and df.competencia_date >= p_comp_ini
    and df.competencia_date < p_comp_fim
),
t as (
  select
    d.documento_fiscal_id,
    t.id as titulo_id,
    t.status as titulo_status,
    t.origem as titulo_origem,
    coalesce(t.valor_total, 0)::numeric as titulo_valor_total,
    coalesce(t.valor_aberto, 0)::numeric as titulo_valor_aberto,
    t.deleted_at as titulo_deleted_at
  from docs d
  left join lateral (
    select x.*
    from f.titulo x
    where x.tenant_id = d.tenant_id
      and x.empresa_id = d.empresa_id
      and x.tipo = 'AP'
      and x.documento_fiscal_id = d.documento_fiscal_id
    order by (x.deleted_at is null) desc, x.created_at desc
    limit 1
  ) t on true
),
p as (
  select
    t.documento_fiscal_id,
    count(tp.*)::bigint as parcelas_count,
    coalesce(sum(tp.valor), 0)::numeric as parcelas_total
  from t
  left join f.titulo_parcela tp
    on tp.titulo_id = t.titulo_id
   and tp.tenant_id = p_tenant_id
   and tp.deleted_at is null
  group by t.documento_fiscal_id
)
select
  d.tenant_id,
  d.empresa_id,
  d.source_nf_entrada_id,
  d.documento_fiscal_id,
  d.competencia_date,
  d.emissao_date,
  d.chave_acesso,
  d.doc_valor_total,
  t.titulo_id,
  t.titulo_status,
  t.titulo_origem,
  t.titulo_valor_total,
  t.titulo_valor_aberto,
  t.titulo_deleted_at,
  coalesce(p.parcelas_count, 0) as parcelas_count,
  coalesce(p.parcelas_total, 0) as parcelas_total,
  (
    t.titulo_id is null
    or t.titulo_deleted_at is not null
    or coalesce(p.parcelas_count, 0) = 0
    or abs(coalesce(p.parcelas_total, 0) - coalesce(d.doc_valor_total, 0)) > 0.05
  ) as has_issue,
  concat_ws(
    ',',
    case when t.titulo_id is null then 'MISSING_TITULO' end,
    case when t.titulo_deleted_at is not null then 'TITULO_SOFT_DELETED' end,
    case when t.titulo_id is not null and coalesce(p.parcelas_count, 0) = 0 then 'MISSING_PARCELAS' end,
    case when t.titulo_id is not null and abs(coalesce(p.parcelas_total, 0) - coalesce(d.doc_valor_total, 0)) > 0.05 then 'PARCELAS_TOTAL_DIFF' end
  ) as issue_codes
from docs d
left join t on t.documento_fiscal_id = d.documento_fiscal_id
left join p on p.documento_fiscal_id = d.documento_fiscal_id
order by d.competencia_date asc, d.documento_fiscal_id asc;
$$;

create or replace function public.fn_reparar_ap_por_nf_entrada_range(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_comp_ini date,
  p_comp_fim date,
  p_force_regen_parcelas boolean default false
) returns table(
  source_nf_entrada_id bigint,
  documento_fiscal_id uuid,
  titulo_id uuid,
  status text,
  details text
)
language plpgsql
security definer
set search_path to 'public', 'f', 'a', 'c'
set row_security to 'off'
as $$
declare
  r record;
  v_titulo_id uuid;
begin
  for r in
    select *
    from public.fn_auditar_ap_por_nf_entrada_range(
      p_tenant_id,
      p_empresa_id,
      p_comp_ini,
      p_comp_fim
    )
    where has_issue
  loop
    begin
      v_titulo_id := public.fn_ensure_titulo_ap_from_nf_entrada(
        r.source_nf_entrada_id,
        p_force_regen_parcelas,
        null::jsonb
      );

      source_nf_entrada_id := r.source_nf_entrada_id;
      documento_fiscal_id := r.documento_fiscal_id;
      titulo_id := v_titulo_id;
      status := 'ok';
      details := coalesce(r.issue_codes, 'REPAIRED');
      return next;
    exception
      when others then
        source_nf_entrada_id := r.source_nf_entrada_id;
        documento_fiscal_id := r.documento_fiscal_id;
        titulo_id := null;
        status := 'error';
        details := SQLERRM;
        return next;
    end;
  end loop;
end;
$$;

revoke all on function public.fn_auditar_ap_por_nf_entrada_range(uuid, uuid, date, date) from public;
grant execute on function public.fn_auditar_ap_por_nf_entrada_range(uuid, uuid, date, date) to authenticated;
grant execute on function public.fn_auditar_ap_por_nf_entrada_range(uuid, uuid, date, date) to service_role;

revoke all on function public.fn_reparar_ap_por_nf_entrada_range(uuid, uuid, date, date, boolean) from public;
grant execute on function public.fn_reparar_ap_por_nf_entrada_range(uuid, uuid, date, date, boolean) to authenticated;
grant execute on function public.fn_reparar_ap_por_nf_entrada_range(uuid, uuid, date, date, boolean) to service_role;
