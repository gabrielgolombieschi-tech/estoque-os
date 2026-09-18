-- Schemas public, a e m: as 24 RPCs app_*/fn_* (25 assinaturas: fn_hh_sync_apontamento_key tem duas
-- sobrecargas) que o anon conseguia executar em 18/09/2026 ficam fechadas para anon e PUBLIC;
-- authenticated e service_role continuam. Mesmo desenho da 20260918070000 (schema f). Pedido do
-- Gabriel em 18/09/2026; mapa em docs/faturamento/seguranca-grants-2026-09-18.md.
--
-- Quem chama (todas com sessao): app mobile — app_listar_os / app_listar_os_fluxo (tela inicial),
-- app_listar_apontamentos / app_resumo_materiais_os (detalhe da OS), app_lancar_material_os /
-- app_lancar_material_os_por_item_id (lancar material), app_orcamento_do_cliente /
-- app_orcamento_agrupado_cliente (aba Orcamento). As demais sao helpers chamadas dentro do banco
-- (gatilhos e funcoes; colunas geradas documento_key de fornecedores/clientes usam fn_documento_key
-- e sao avaliadas como o usuario que grava, que continua com EXECUTE). A unica policy RLS que
-- passa por elas (empresas_select_a, via a_is_tenant_role SECURITY DEFINER) e so para authenticated.
-- Nao ha link publico: o site-segau nao usa Supabase.

revoke execute on function a.fn_map_papel_empresa_to_role(text) from public, anon;
grant execute on function a.fn_map_papel_empresa_to_role(text) to authenticated, service_role;
revoke execute on function a.fn_map_papel_empresa(text) from public, anon;
grant execute on function a.fn_map_papel_empresa(text) to authenticated, service_role;
revoke execute on function a.fn_map_papel_tenant_to_role(text) from public, anon;
grant execute on function a.fn_map_papel_tenant_to_role(text) to authenticated, service_role;
revoke execute on function a.fn_map_papel_tenant(text) from public, anon;
grant execute on function a.fn_map_papel_tenant(text) to authenticated, service_role;
revoke execute on function public.app_lancar_material_os_por_item_id(integer,integer,numeric,text) from public, anon;
grant execute on function public.app_lancar_material_os_por_item_id(integer,integer,numeric,text) to authenticated, service_role;
revoke execute on function public.app_lancar_material_os(integer,text,numeric,text) from public, anon;
grant execute on function public.app_lancar_material_os(integer,text,numeric,text) to authenticated, service_role;
revoke execute on function public.app_listar_apontamentos(date,date,integer,uuid) from public, anon;
grant execute on function public.app_listar_apontamentos(date,date,integer,uuid) to authenticated, service_role;
revoke execute on function public.app_listar_os_fluxo(text,text) from public, anon;
grant execute on function public.app_listar_os_fluxo(text,text) to authenticated, service_role;
revoke execute on function public.app_listar_os(boolean,text) from public, anon;
grant execute on function public.app_listar_os(boolean,text) to authenticated, service_role;
revoke execute on function public.app_orcamento_agrupado_cliente(text,text) from public, anon;
grant execute on function public.app_orcamento_agrupado_cliente(text,text) to authenticated, service_role;
revoke execute on function public.app_orcamento_do_cliente(integer,text,text) from public, anon;
grant execute on function public.app_orcamento_do_cliente(integer,text,text) to authenticated, service_role;
revoke execute on function public.app_resumo_materiais_os(integer) from public, anon;
grant execute on function public.app_resumo_materiais_os(integer) to authenticated, service_role;
revoke execute on function public.fn_calc_horas_2_periodos(time without time zone,time without time zone,time without time zone,time without time zone) from public, anon;
grant execute on function public.fn_calc_horas_2_periodos(time without time zone,time without time zone,time without time zone,time without time zone) to authenticated, service_role;
revoke execute on function public.fn_calc_horas_periodos(time without time zone,time without time zone,time without time zone,time without time zone) from public, anon;
grant execute on function public.fn_calc_horas_periodos(time without time zone,time without time zone,time without time zone,time without time zone) to authenticated, service_role;
revoke execute on function public.fn_documento_key(text) from public, anon;
grant execute on function public.fn_documento_key(text) to authenticated, service_role;
revoke execute on function public.fn_fix_nf_entrada_pos_import(bigint) from public, anon;
grant execute on function public.fn_fix_nf_entrada_pos_import(bigint) to authenticated, service_role;
revoke execute on function public.fn_fornecedor_upsert_por_documento(uuid,text,text) from public, anon;
grant execute on function public.fn_fornecedor_upsert_por_documento(uuid,text,text) to authenticated, service_role;
revoke execute on function public.fn_hh_sync_apontamento_key(uuid,uuid,bigint,uuid,date,bigint) from public, anon;
grant execute on function public.fn_hh_sync_apontamento_key(uuid,uuid,bigint,uuid,date,bigint) to authenticated, service_role;
revoke execute on function public.fn_hh_sync_apontamento_key(uuid,uuid,integer,uuid,date,bigint) from public, anon;
grant execute on function public.fn_hh_sync_apontamento_key(uuid,uuid,integer,uuid,date,bigint) to authenticated, service_role;
revoke execute on function public.fn_nf_entrada_sync_estoque_df(bigint) from public, anon;
grant execute on function public.fn_nf_entrada_sync_estoque_df(bigint) to authenticated, service_role;
revoke execute on function public.fn_normalize_documento(text) from public, anon;
grant execute on function public.fn_normalize_documento(text) to authenticated, service_role;
revoke execute on function public.fn_percentual_por_data(date) from public, anon;
grant execute on function public.fn_percentual_por_data(date) to authenticated, service_role;
revoke execute on function public.fn_regerar_parcelas_titulo_from_xml(bigint,uuid) from public, anon;
grant execute on function public.fn_regerar_parcelas_titulo_from_xml(bigint,uuid) to authenticated, service_role;
revoke execute on function public.fn_xml_strip_default_namespace(text) from public, anon;
grant execute on function public.fn_xml_strip_default_namespace(text) to authenticated, service_role;
revoke execute on function m.fn_orcamento_item_calcular(numeric,numeric,numeric,numeric,numeric) from public, anon;
grant execute on function m.fn_orcamento_item_calcular(numeric,numeric,numeric,numeric,numeric) to authenticated, service_role;

-- Conferencia: nenhuma das assinaturas acima pode ficar executavel pelo anon. (So elas: o banco local
-- recriado do zero tem outras RPCs de public abertas ao anon que no online foram fechadas fora das
-- migrations; isso fica registrado no levantamento, nao neste assert.)
do $$
declare
  v_abertas text;
begin
  select string_agg(a.assinatura, ', ' order by a.assinatura)
    into v_abertas
  from unnest(array[
    'a.fn_map_papel_empresa_to_role(text)',
    'a.fn_map_papel_empresa(text)',
    'a.fn_map_papel_tenant_to_role(text)',
    'a.fn_map_papel_tenant(text)',
    'public.app_lancar_material_os_por_item_id(integer,integer,numeric,text)',
    'public.app_lancar_material_os(integer,text,numeric,text)',
    'public.app_listar_apontamentos(date,date,integer,uuid)',
    'public.app_listar_os_fluxo(text,text)',
    'public.app_listar_os(boolean,text)',
    'public.app_orcamento_agrupado_cliente(text,text)',
    'public.app_orcamento_do_cliente(integer,text,text)',
    'public.app_resumo_materiais_os(integer)',
    'public.fn_calc_horas_2_periodos(time without time zone,time without time zone,time without time zone,time without time zone)',
    'public.fn_calc_horas_periodos(time without time zone,time without time zone,time without time zone,time without time zone)',
    'public.fn_documento_key(text)',
    'public.fn_fix_nf_entrada_pos_import(bigint)',
    'public.fn_fornecedor_upsert_por_documento(uuid,text,text)',
    'public.fn_hh_sync_apontamento_key(uuid,uuid,bigint,uuid,date,bigint)',
    'public.fn_hh_sync_apontamento_key(uuid,uuid,integer,uuid,date,bigint)',
    'public.fn_nf_entrada_sync_estoque_df(bigint)',
    'public.fn_normalize_documento(text)',
    'public.fn_percentual_por_data(date)',
    'public.fn_regerar_parcelas_titulo_from_xml(bigint,uuid)',
    'public.fn_xml_strip_default_namespace(text)',
    'm.fn_orcamento_item_calcular(numeric,numeric,numeric,numeric,numeric)'
  ]) as a(assinatura)
  where has_function_privilege('anon', a.assinatura::regprocedure, 'EXECUTE');
  if v_abertas is not null then
    raise exception 'RPCs ainda abertas ao anon: %', v_abertas;
  end if;
end $$;

notify pgrst, 'reload schema';

-- Reversao: grant execute ... to public (a, m) e to anon (public) nas assinaturas acima.
