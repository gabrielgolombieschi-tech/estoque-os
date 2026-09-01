begin;

-- A versao security_invoker executava a RLS de cada relacao associada para
-- cada linha e estourava o statement_timeout no PostgREST. A view continua
-- fechada pelo contexto autenticado, mas o owner resolve as juncoes uma vez.
create or replace view r.r_venda_credito
with (security_invoker = false)
as
select
  g.tenant_id,
  g.empresa_id,
  g.id as credito_id,
  g.os_id,
  os.numero_os,
  os.status as os_status,
  os.status_fluxo as os_status_fluxo,
  g.cliente_id,
  c.nome as cliente_nome,
  c.documento,
  c.documento_norm,
  c.documento_raiz,
  coalesce(c.documento_raiz, 'CLIENTE:' || g.cliente_id::text) as grupo_cliente,
  g.unidade_id,
  u.nome as unidade_nome,
  g.status,
  g.origem,
  coalesce(g.descricao, os.descricao_servico) as descricao,
  g.data_competencia,
  g.pedido_compra_cliente,
  g.pedido_recebido_em,
  g.faturado_em,
  g.documento_fiscal_id,
  df.modelo as documento_modelo,
  df.serie as documento_serie,
  df.numero as documento_numero,
  g.titulo_ar_id,
  g.responsavel_id,
  au.nome as responsavel_nome,
  g.responsavel_cliente_nome,
  g.proximo_contato_date,
  g.observacao,
  g.valor_estimado,
  g.valor_confirmado,
  coalesce(g.valor_confirmado,g.valor_estimado,0)::numeric(15,2) as valor_exposicao,
  g.valor_origem,
  g.valor_calculado_em,
  (current_date - coalesce(g.data_competencia,g.created_at::date))::integer as dias_em_aberto,
  g.created_at,
  g.updated_at
from f.gestao_cobranca_os g
left join public.ordens_servico os
  on os.id=g.os_id and os.tenant_id=g.tenant_id and os.empresa_id=g.empresa_id
left join public.clientes c
  on c.id=g.cliente_id and c.tenant_id=g.tenant_id and c.empresa_id=g.empresa_id
left join public.cliente_unidades u
  on u.id=g.unidade_id and u.tenant_id=g.tenant_id and u.empresa_id=g.empresa_id
left join f.documento_fiscal df
  on df.id=g.documento_fiscal_id and df.tenant_id=g.tenant_id and df.empresa_id=g.empresa_id
left join a.usuario au
  on au.id=g.responsavel_id
where g.deleted_at is null
  and (
    auth.role() = 'service_role'
    or (
      g.tenant_id = public.current_tenant_id()
      and g.empresa_id = public.current_empresa_id__by_tenant(g.tenant_id)
      and f.has_cobranca_access(g.tenant_id,g.empresa_id)
    )
  );

grant select on r.r_venda_credito to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
