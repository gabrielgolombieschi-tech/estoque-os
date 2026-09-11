-- O valor de cada nota em "Notas desta OS" passa a ser o mesmo que o saldo abate.
--
-- Depois da 20260911170000 a NFS-e importada da OS 139 apareceu na lista com R$ 81.812,50
-- (o liquido), enquanto o quadro de saldo, logo acima, dizia faturado R$ 87.500,00 (o
-- bruto, 20260911160000). Dois numeros para a mesma nota, na mesma tela. A lista agora usa
-- f.fn_documento_valor_faturado: NFS-e pelo bruto do servico, NF-e pelo vNF — e a soma da
-- lista fecha com o "ja faturado".

CREATE OR REPLACE FUNCTION f.fn_os_notas(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
 RETURNS TABLE(documento_fiscal_id uuid, solicitacao_id uuid, solicitacao_status text, modelo text, ambiente text, emissao_status text, nfe_status text, serie text, numero text, chave_acesso text, valor_total numeric, autorizado_em timestamp with time zone, danfe_path text, xml_path text, referencia_externa text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
  select d.id, e.solicitacao_id, s.status,
         case when upper(coalesce(d.modelo, '')) = 'NFSE' then 'NFSE' else 'NFE' end,
         coalesce(e.ambiente, 'PRODUCAO'),
         coalesce(e.status, 'IMPORTADA'),
         case when upper(coalesce(d.modelo, '')) = 'NFSE' then d.nfse_status else d.nfe_status end,
         coalesce(e.dps_serie::text, d.serie), coalesce(e.nfse_numero, d.numero),
         coalesce(e.chave_nfse, d.chave_acesso),
         f.fn_documento_valor_faturado(d.modelo, d.valor_total, d.valor_servicos, d.valor_produtos),
         e.autorizado_em,
         e.danfe_path, e.xml_path, e.referencia_externa, coalesce(e.created_at, d.created_at)
  from f.documento_fiscal d
  left join f.documento_fiscal_emissao e
    on e.tenant_id = d.tenant_id and e.empresa_id = d.empresa_id and e.documento_fiscal_id = d.id
  left join f.solicitacao_faturamento s
    on s.tenant_id = e.tenant_id and s.empresa_id = e.empresa_id and s.id = e.solicitacao_id
  where d.tenant_id = p_tenant_id and d.empresa_id = p_empresa_id
    and d.operacao = 'SAIDA' and d.deleted_at is null
    and (
      d.os_id_import = p_os_id
      or exists (
        select 1 from f.solicitacao_item si
        where si.tenant_id = e.tenant_id and si.empresa_id = e.empresa_id and si.solicitacao_id = e.solicitacao_id
          and si.origem_tipo = 'OS' and si.origem_id = p_os_id::text
      )
    )
    and (session_user = 'postgres' or coalesce(auth.jwt()->>'role', '') = 'service_role'
         or (public.current_tenant_id() = p_tenant_id and public.current_empresa_id() = p_empresa_id and f.has_finance_access()))
  order by coalesce(e.created_at, d.created_at) desc;
$function$;
