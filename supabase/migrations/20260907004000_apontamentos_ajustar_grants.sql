-- As funcoes criadas hoje nasceram com o EXECUTE padrao do Postgres (PUBLIC) e
-- com anon junto. Nenhuma delas roda sem sessao — todas param em auth.uid() —
-- mas o resto do schema segue o padrao apertado (postgres + authenticated, como
-- em app_cancelar_apontamento), e helper interno nao fica exposto na API.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

-- Helper interno: so as funcoes SECURITY DEFINER precisam dele, igual ao
-- fn_usuario_pode_editar_apontamento.
revoke all on function public.fn_usuario_pode_alterar_apontamento(uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;

-- RPCs do app: sessao autenticada e so.
revoke all on function public.app_sou_responsavel_os(integer) from public, anon;
revoke all on function public.app_lancar_apontamentos_lote(integer, date, uuid, jsonb, text, boolean) from public, anon;
revoke all on function public.app_editar_apontamento(uuid, numeric, uuid, text, boolean, text) from public, anon;

grant execute on function public.app_sou_responsavel_os(integer) to authenticated;
grant execute on function public.app_lancar_apontamentos_lote(integer, date, uuid, jsonb, text, boolean) to authenticated;
grant execute on function public.app_editar_apontamento(uuid, numeric, uuid, text, boolean, text) to authenticated;

do $assert$
declare
  v_acl text;
begin
  for v_acl in
    select coalesce(p.proacl::text, '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('app_sou_responsavel_os', 'app_lancar_apontamentos_lote', 'app_editar_apontamento', 'fn_usuario_pode_alterar_apontamento')
  loop
    if v_acl like '%anon=%' or v_acl like '{=X%' then
      raise exception 'grant_ainda_aberto: %', v_acl;
    end if;
  end loop;
end;
$assert$;

notify pgrst, 'reload schema';

commit;
