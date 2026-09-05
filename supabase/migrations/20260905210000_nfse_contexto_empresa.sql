-- NFS-e: leitura, pela tela, dos dados fiscais da empresa que ficam no schema c
-- (nao exposto pela API): IBGE do endereco fiscal, serie da DPS, prazo de
-- cancelamento, IM, opcao Simples, id do webhook. Somente leitura, escopo do
-- usuario (tenant/empresa ativos + acesso financeiro). Objeto novo; sem baseline.
create or replace function f.fn_nfse_contexto_empresa(p_empresa_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select jsonb_build_object(
    'empresa_id', e.id,
    'cnpj', regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g'),
    'codigo_municipio_ibge', (
      select regexp_replace(coalesce(ee.codigo_municipio_ibge, ''), '[^0-9]', '', 'g')
      from c.empresa_endereco ee
      where ee.empresa_id = e.id and ee.deleted_at is null
      order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1
    ),
    'serie_dps', ef.serie_dps,
    'proximo_numero_dps', ef.proximo_numero_dps,
    'inscricao_municipal', ef.inscricao_municipal,
    'codigo_opcao_simples_nacional', ef.codigo_opcao_simples_nacional,
    'regime_especial_tributacao', ef.regime_especial_tributacao,
    'prazo_cancelamento_nfse_horas', ef.prazo_cancelamento_nfse_horas,
    'focus_webhook_nfsen_id', ef.focus_webhook_nfsen_id
  )
  from c.empresa e
  left join c.empresa_fiscal ef on ef.empresa_id = e.id and ef.deleted_at is null
  where e.id = p_empresa_id and e.deleted_at is null
    and (session_user = 'postgres' or coalesce(auth.jwt()->>'role', '') = 'service_role'
         or (public.current_tenant_id() = e.tenant_id and public.current_empresa_id() = e.id and f.has_finance_access()));
$$;
revoke all on function f.fn_nfse_contexto_empresa(uuid) from public;
grant execute on function f.fn_nfse_contexto_empresa(uuid) to authenticated, service_role;
