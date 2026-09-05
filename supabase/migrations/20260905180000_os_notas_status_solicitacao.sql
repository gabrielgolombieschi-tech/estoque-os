-- fn_os_notas passa a expor o status da solicitacao, para a tela distinguir
-- homologacao viva (reserva saldo) de homologacao abandonada (saldo devolvido,
-- NF-e de teste continua autorizada na SEFAZ). Sem isso o botao "abandonar
-- homologacao" continuava visivel depois do abandono.
--
-- Baseline (producao, 2026-09-05, migration 20260905170000):
--   f.fn_os_notas(uuid,uuid,integer) returns table(documento_fiscal_id uuid,
--   solicitacao_id uuid, ambiente text, emissao_status text, nfe_status text,
--   serie text, numero text, chave_acesso text, valor_total numeric,
--   autorizado_em timestamptz, danfe_path text, xml_path text,
--   referencia_externa text, created_at timestamptz); language sql stable
--   security definer; grant execute to authenticated, service_role.

drop function if exists f.fn_os_notas(uuid, uuid, integer);

create function f.fn_os_notas(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  solicitacao_status text,
  ambiente text,
  emissao_status text,
  nfe_status text,
  serie text,
  numero text,
  chave_acesso text,
  valor_total numeric,
  autorizado_em timestamptz,
  danfe_path text,
  xml_path text,
  referencia_externa text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select d.id, e.solicitacao_id, s.status, e.ambiente, e.status, d.nfe_status,
         d.serie, d.numero, d.chave_acesso, d.valor_total, e.autorizado_em,
         e.danfe_path, e.xml_path, e.referencia_externa, e.created_at
  from f.documento_fiscal d
  join f.documento_fiscal_emissao e
    on e.tenant_id = d.tenant_id and e.empresa_id = d.empresa_id and e.documento_fiscal_id = d.id
  left join f.solicitacao_faturamento s
    on s.tenant_id = e.tenant_id and s.empresa_id = e.empresa_id and s.id = e.solicitacao_id
  where d.tenant_id = p_tenant_id and d.empresa_id = p_empresa_id
    and d.os_id_import = p_os_id and d.operacao = 'SAIDA' and d.deleted_at is null
    and (session_user = 'postgres' or coalesce(auth.jwt()->>'role', '') = 'service_role'
         or (public.current_tenant_id() = p_tenant_id and public.current_empresa_id() = p_empresa_id and f.has_finance_access()))
  order by e.created_at desc;
$$;

revoke all on function f.fn_os_notas(uuid, uuid, integer) from public;
grant execute on function f.fn_os_notas(uuid, uuid, integer) to authenticated, service_role;
