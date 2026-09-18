-- 48 RPCs app_*/fn_* de public que no online estao fechadas ao anon (ACLs abaixo, lidas do online em
-- 18/09/2026) mas que um banco recriado do zero pelas migrations deixa abertas: o baseline faz
-- "REVOKE ... FROM PUBLIC" e "GRANT ... TO authenticated", e o privilegio padrao do Supabase em public da
-- anon (e service_role) explicitamente na criacao, que o revoke do PUBLIC nao tira. Esta migration
-- espelha o online (revoke de tudo, grant so do que o online tem): no online e um no-op; no rebuild
-- deixa o local igual. Pedido do Gabriel em 18/09/2026. Reversao: nao se aplica (estado do online).

revoke all on function public.app_buscar_materiais(text,text,integer) from public, anon, authenticated, service_role;
grant execute on function public.app_buscar_materiais(text,text,integer) to authenticated;
revoke all on function public.app_buscar_material_por_codigo(text) from public, anon, authenticated, service_role;
grant execute on function public.app_buscar_material_por_codigo(text) to authenticated;
revoke all on function public.app_contar_aprovacoes_pendentes() from public, anon, authenticated, service_role;
grant execute on function public.app_contar_aprovacoes_pendentes() to authenticated;
revoke all on function public.app_contar_notificacoes_nao_lidas() from public, anon, authenticated, service_role;
grant execute on function public.app_contar_notificacoes_nao_lidas() to authenticated, service_role;
revoke all on function public.app_criar_os_hh(integer,text) from public, anon, authenticated, service_role;
grant execute on function public.app_criar_os_hh(integer,text) to authenticated;
revoke all on function public.app_desativar_dispositivo_push(text) from public, anon, authenticated, service_role;
grant execute on function public.app_desativar_dispositivo_push(text) to authenticated, service_role;
revoke all on function public.app_editar_material_os(integer,numeric,text) from public, anon, authenticated, service_role;
grant execute on function public.app_editar_material_os(integer,numeric,text) to authenticated;
revoke all on function public.app_lancar_apontamentos_lote_unfiltered_ov_20260829(integer,date,uuid,jsonb,text,boolean) from public, anon, authenticated, service_role;
revoke all on function public.app_lancar_hh_lote(integer,date,time without time zone,time without time zone,time without time zone,time without time zone,smallint,text,jsonb) from public, anon, authenticated, service_role;
grant execute on function public.app_lancar_hh_lote(integer,date,time without time zone,time without time zone,time without time zone,time without time zone,smallint,text,jsonb) to authenticated;
revoke all on function public.app_lancar_hh(integer,uuid,date,bigint,time without time zone,time without time zone,time without time zone,time without time zone,smallint,numeric,numeric,text) from public, anon, authenticated, service_role;
grant execute on function public.app_lancar_hh(integer,uuid,date,bigint,time without time zone,time without time zone,time without time zone,time without time zone,smallint,numeric,numeric,text) to authenticated;
revoke all on function public.app_lancar_material_os_por_item_id_unfiltered_ov_20260829(integer,integer,numeric,text) from public, anon, authenticated, service_role;
revoke all on function public.app_lancar_material_os_unfiltered_ov_20260829(integer,text,numeric,text) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_apontamentos_unfiltered_ov_20260829(date,date,integer,uuid) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_aprovacoes_pendentes() from public, anon, authenticated, service_role;
grant execute on function public.app_listar_aprovacoes_pendentes() to authenticated;
revoke all on function public.app_listar_clientes_hh() from public, anon, authenticated, service_role;
grant execute on function public.app_listar_clientes_hh() to authenticated;
revoke all on function public.app_listar_colaboradores() from public, anon, authenticated, service_role;
grant execute on function public.app_listar_colaboradores() to authenticated;
revoke all on function public.app_listar_especialidades_hh(integer,uuid) from public, anon, authenticated, service_role;
grant execute on function public.app_listar_especialidades_hh(integer,uuid) to authenticated;
revoke all on function public.app_listar_materiais_os_unfiltered_ov_20260829(integer) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_notificacoes(integer,timestamp with time zone) from public, anon, authenticated, service_role;
grant execute on function public.app_listar_notificacoes(integer,timestamp with time zone) to authenticated, service_role;
revoke all on function public.app_listar_os_fluxo_unfiltered_ov_20260829(text,text) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_os_unfiltered_ov_20260829(boolean,text) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_tipos_horas() from public, anon, authenticated, service_role;
grant execute on function public.app_listar_tipos_horas() to authenticated;
revoke all on function public.app_marcar_notificacao_lida(uuid) from public, anon, authenticated, service_role;
grant execute on function public.app_marcar_notificacao_lida(uuid) to authenticated, service_role;
revoke all on function public.app_meu_papel_empresa() from public, anon, authenticated, service_role;
grant execute on function public.app_meu_papel_empresa() to authenticated;
revoke all on function public.app_minhas_horas_ano(integer) from public, anon, authenticated, service_role;
grant execute on function public.app_minhas_horas_ano(integer) to authenticated;
revoke all on function public.app_minhas_horas_mes(integer,integer) from public, anon, authenticated, service_role;
grant execute on function public.app_minhas_horas_mes(integer,integer) to authenticated;
revoke all on function public.app_mobile_pode_ver_valores_os(uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.app_mobile_pode_ver_valores_os(uuid,uuid) to authenticated, service_role;
revoke all on function public.app_mobile_status_os_compativel(text,text,text[]) from public, anon, authenticated, service_role;
grant execute on function public.app_mobile_status_os_compativel(text,text,text[]) to authenticated, service_role;
revoke all on function public.app_notificacao_contexto_valido() from public, anon, authenticated, service_role;
grant execute on function public.app_notificacao_contexto_valido() to service_role;
revoke all on function public.app_notificar_usuarios_por_papel(uuid,uuid,text[],text,text,text,jsonb,text) from public, anon, authenticated, service_role;
grant execute on function public.app_notificar_usuarios_por_papel(uuid,uuid,text[],text,text,text,jsonb,text) to service_role;
revoke all on function public.app_papel_pode_lancar_horas(text) from public, anon, authenticated, service_role;
revoke all on function public.app_registrar_dispositivo_push(text,text) from public, anon, authenticated, service_role;
grant execute on function public.app_registrar_dispositivo_push(text,text) to authenticated, service_role;
revoke all on function public.app_remover_material_os(integer) from public, anon, authenticated, service_role;
grant execute on function public.app_remover_material_os(integer) to authenticated;
revoke all on function public.app_resumo_materiais_os_unfiltered_ov_20260829(integer) from public, anon, authenticated, service_role;
revoke all on function public.app_resumo_mes() from public, anon, authenticated, service_role;
grant execute on function public.app_resumo_mes() to authenticated;
revoke all on function public.app_verificar_feriado(date) from public, anon, authenticated, service_role;
grant execute on function public.app_verificar_feriado(date) to authenticated;
revoke all on function public.fn_arrendamento_gerar_ap(uuid,uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.fn_arrendamento_gerar_ap(uuid,uuid,uuid) to authenticated, service_role;
revoke all on function public.fn_auditar_ap_por_nf_entrada_range(uuid,uuid,date,date) from public, anon, authenticated, service_role;
grant execute on function public.fn_auditar_ap_por_nf_entrada_range(uuid,uuid,date,date) to authenticated, service_role;
revoke all on function public.fn_backfill_movimentacoes_nf_entrada(bigint) from public, anon, authenticated, service_role;
grant execute on function public.fn_backfill_movimentacoes_nf_entrada(bigint) to authenticated, service_role;
revoke all on function public.fn_ensure_titulo_ap_from_nf_entrada(bigint,boolean,jsonb) from public, anon, authenticated, service_role;
grant execute on function public.fn_ensure_titulo_ap_from_nf_entrada(bigint,boolean,jsonb) to authenticated, service_role;
revoke all on function public.fn_gerar_ou_atualizar_orcamento_de_os(uuid,uuid,integer,uuid,numeric,numeric,integer) from public, anon, authenticated, service_role;
grant execute on function public.fn_gerar_ou_atualizar_orcamento_de_os(uuid,uuid,integer,uuid,numeric,numeric,integer) to authenticated, service_role;
revoke all on function public.fn_importacao_xml__itens_auto_cadastrar_finalidades(uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.fn_importacao_xml__itens_auto_cadastrar_finalidades(uuid,uuid) to authenticated, service_role;
revoke all on function public.fn_importacao_xml__itens_vincular_finalidades(uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.fn_importacao_xml__itens_vincular_finalidades(uuid,uuid) to authenticated, service_role;
revoke all on function public.fn_preco_venda_item_unscoped(uuid,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.fn_preco_venda_item_valores(numeric,numeric,numeric,numeric) from public, anon, authenticated, service_role;
grant execute on function public.fn_preco_venda_item_valores(numeric,numeric,numeric,numeric) to service_role;
revoke all on function public.fn_reparar_ap_por_nf_entrada_range(uuid,uuid,date,date,boolean) from public, anon, authenticated, service_role;
grant execute on function public.fn_reparar_ap_por_nf_entrada_range(uuid,uuid,date,date,boolean) to authenticated, service_role;
revoke all on function public.fn_sync_titulo_aprovacao_from_nf_entrada(bigint,uuid,uuid,integer,uuid) from public, anon, authenticated, service_role;
grant execute on function public.fn_sync_titulo_aprovacao_from_nf_entrada(bigint,uuid,uuid,integer,uuid) to authenticated, service_role;
revoke all on function public.fn_usuario_pode_editar_apontamento(uuid,uuid,uuid,uuid) from public, anon, authenticated, service_role;

-- Conferencia: nenhuma funcao app_*/fn_* dos schemas expostos pode ficar executavel pelo anon.
do $$
declare
  v_abertas text;
begin
  select string_agg(p.oid::regprocedure::text, ', ' order by n.nspname, p.proname)
    into v_abertas
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_type t on t.oid = p.prorettype
  where n.nspname in ('public', 'graphql_public', 'f', 'm', 'c', 'a')
    and (p.proname like 'app\_%' or p.proname like 'fn\_%')
    and p.prokind = 'f'
    and t.typname <> 'trigger'
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_abertas is not null then
    raise exception 'RPCs app_*/fn_* ainda abertas ao anon nos schemas expostos: %', v_abertas;
  end if;
  raise notice 'schemas expostos: nenhuma RPC app_*/fn_* executavel pelo anon';
end $$;

notify pgrst, 'reload schema';
