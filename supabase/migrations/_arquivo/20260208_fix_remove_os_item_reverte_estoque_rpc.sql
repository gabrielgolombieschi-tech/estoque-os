-- Fix: Supabase/PostgREST RPC ambiguity for remove_os_item_reverte_estoque
--
-- Root cause:
-- Postgres allows function overloading. PostgREST resolves RPC calls using the JSON payload,
-- but when multiple overloads exist with compatible casts (e.g. legacy (integer,text,text,text)
-- and canonical (integer,text,text,uuid)), PostgreSQL can fail with:
--   "Could not choose the best candidate function"
--
-- Goal:
-- Ensure there is ONLY ONE public RPC endpoint exposed as:
--   /rpc/remove_os_item_reverte_estoque
-- with the canonical signature used by the app:
--   (p_os_item_id integer, p_realizado_por text, p_motivo text, p_empresa_id uuid)

begin;
-- 1) Remove the legacy overload (if it still exists).
-- Legacy signature seen in the error:
--   public.remove_os_item_reverte_estoque(
--     p_empresa_id => integer,
--     p_motivo => text,
--     p_os_item_id => text,
--     p_realizado_por => text
--   )
-- Types-only signature:
--   (integer, text, text, text)
DROP FUNCTION IF EXISTS public.remove_os_item_reverte_estoque(integer, text, text, text);
-- 2) (Re)create the canonical function with SECURITY DEFINER and a safe search_path.
CREATE OR REPLACE FUNCTION public.remove_os_item_reverte_estoque(
  p_os_item_id integer,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_item record;
  v_row record;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.can('os_rpcs','execute') then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  select *
    into v_row
  from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item da OS nao encontrado';
  end if;

  select *
    into v_item
  from public.itens
  where id = v_row.item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item invalido ou fora do tenant atual';
  end if;

  delete from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if coalesce(v_row.baixa_estoque, false)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque','write') or public.can('os_rpcs','execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'entrada',
      v_row.quantidade,
      coalesce(p_motivo, 'Estorno baixa OS ' || v_row.os_id),
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = v_row.os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant;
end;
$function$;
-- 3) Explicit privileges (avoid relying on environment defaults).
REVOKE ALL ON FUNCTION public.remove_os_item_reverte_estoque(integer, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_os_item_reverte_estoque(integer, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_os_item_reverte_estoque(integer, text, text, uuid) TO service_role;
-- 4) Ensure PostgREST schema cache refresh.
NOTIFY pgrst, 'reload schema';
commit;
