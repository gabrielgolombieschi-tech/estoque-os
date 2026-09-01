create or replace function public.validar_reimportacao_nfe_521977()
returns jsonb
language sql
security definer
set search_path = public, f, m, pg_temp
as $$
  with documento as (
    select df.id, df.source_nf_entrada_id, df.chave_acesso, df.nfe_status,
           df.valor_total, df.deleted_at
    from f.documento_fiscal df
    where df.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
      and df.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
      and df.source_nf_entrada_id = 2004
  ), titulo as (
    select t.id, t.documento_fiscal_id, t.tipo, t.status,
           t.valor_total, t.valor_aberto, t.deleted_at
    from f.titulo t
    join documento d on d.id = t.documento_fiscal_id
    where t.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
      and t.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
  ), parcelas as (
    select tp.id, tp.titulo_id, tp.numero, tp.vencimento_date,
           tp.valor, tp.valor_aberto, tp.deleted_at
    from f.titulo_parcela tp
    join titulo t on t.id = tp.titulo_id
    where tp.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  )
  select jsonb_build_object(
    'documentos', coalesce((select jsonb_agg(to_jsonb(d)) from documento d), '[]'::jsonb),
    'titulos', coalesce((select jsonb_agg(to_jsonb(t)) from titulo t), '[]'::jsonb),
    'parcelas', coalesce((select jsonb_agg(to_jsonb(p) order by p.numero) from parcelas p), '[]'::jsonb),
    'pedido', (
      select to_jsonb(p)
      from (
        select pc.id, pc.codigo, pc.status
        from m.pedido_compra pc
        where pc.id = 'df29f6af-8cc3-435f-b20a-6a6a214171df'
          and pc.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
          and pc.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
      ) p
    )
  );
$$;

revoke all on function public.validar_reimportacao_nfe_521977() from public, anon, authenticated;
grant execute on function public.validar_reimportacao_nfe_521977() to service_role;

