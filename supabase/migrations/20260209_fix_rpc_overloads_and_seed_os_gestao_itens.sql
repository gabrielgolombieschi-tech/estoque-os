-- Fix definitivo (Supabase/PostgREST RPC + RLS)
--
-- (1) remove_os_item_reverte_estoque: elimina ambiguidade de overloads
--     Mantém APENAS a assinatura canônica:
--       (p_os_item_id integer, p_realizado_por text, p_motivo text, p_empresa_id uuid)
--     e remove qualquer outra overload existente automaticamente (via catálogo pg_proc).
--
-- (2) os_gestao_itens: corrige falha de RLS ao criar OS
--     Cria RPC SECURITY DEFINER para fazer UPSERT dos itens de gestão
--     preenchendo tenant_id (e empresa_id se a coluna existir), evitando depender
--     do frontend mandar campos de escopo.

BEGIN;

--------------------------------------------------------------------------------
-- (1) RPC overloads: keep only canonical signature
--------------------------------------------------------------------------------
DO $do$
DECLARE
  r record;
  canonical_types text := 'integer, text, text, uuid';
  args_types text;
BEGIN
  FOR r IN (
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'remove_os_item_reverte_estoque'
  ) LOOP
    args_types := oidvectortypes((SELECT proargtypes FROM pg_proc WHERE oid = r.oid));

    -- Drop everything that isn't the canonical (types-only) signature.
    IF args_types IS DISTINCT FROM canonical_types THEN
      EXECUTE format(
        'DROP FUNCTION IF EXISTS public.%I(%s);',
        'remove_os_item_reverte_estoque',
        args_types
      );
    END IF;
  END LOOP;
END;
$do$;

-- Recreate canonical function (idempotent) + safe search_path.
CREATE OR REPLACE FUNCTION public.remove_os_item_reverte_estoque(
  p_os_item_id integer,
  p_realizado_por text DEFAULT NULL,
  p_motivo text DEFAULT NULL,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_item public.itens;
  v_row public.os_itens;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Nao autenticado';
  END IF;

  v_tenant := public.current_tenant_id();
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Tenant atual nao definido';
  END IF;

  IF NOT public.can('os_rpcs','execute') THEN
    RAISE EXCEPTION 'Sem permissao para executar operacao de OS';
  END IF;

  v_empresa := COALESCE(p_empresa_id, public.current_empresa_id());
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  END IF;

  PERFORM public.set_current_empresa(v_empresa);

  v_realizado_por := COALESCE(p_realizado_por, auth.uid()::text);

  SELECT *
    INTO v_row
  FROM public.os_itens
  WHERE id = p_os_item_id
    AND tenant_id = v_tenant;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item da OS nao encontrado';
  END IF;

  SELECT *
    INTO v_item
  FROM public.itens
  WHERE id = v_row.item_id
    AND tenant_id = v_tenant;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item invalido ou fora do tenant atual';
  END IF;

  DELETE FROM public.os_itens
  WHERE id = p_os_item_id
    AND tenant_id = v_tenant;

  IF COALESCE(v_row.baixa_estoque, false)
     AND v_item.tipo = 'produto'
     AND COALESCE(v_item.controla_estoque, false) = true
  THEN
    IF NOT (public.can('estoque','write') OR public.can('os_rpcs','execute')) THEN
      RAISE EXCEPTION 'Sem permissao para movimentar estoque';
    END IF;

    INSERT INTO public.movimentacoes (
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
    VALUES (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'entrada',
      v_row.quantidade,
      COALESCE(p_motivo, 'Estorno baixa OS ' || v_row.os_id),
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  END IF;

  UPDATE public.ordens_servico os
  SET valor_total = COALESCE((
        SELECT sum(oi.valor_total)
        FROM public.os_itens oi
        WHERE oi.os_id = v_row.os_id
          AND oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  WHERE os.id = v_row.os_id
    AND os.tenant_id = v_tenant;
END;
$function$;

REVOKE ALL ON FUNCTION public.remove_os_item_reverte_estoque(integer, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_os_item_reverte_estoque(integer, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_os_item_reverte_estoque(integer, text, text, uuid) TO service_role;

--------------------------------------------------------------------------------
-- (2) Robust upsert for os_gestao_itens via SECURITY DEFINER RPC
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seed_os_gestao_itens(
  p_os_id integer,
  p_items jsonb,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_tenant uuid;
  v_empresa uuid;
  v_has_empresa_col boolean;
  v_sql text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Nao autenticado';
  END IF;

  v_tenant := public.current_tenant_id();
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Tenant atual nao definido';
  END IF;

  IF NOT public.can('os_gestao','write') THEN
    RAISE EXCEPTION 'Sem permissao para editar gestao da OS';
  END IF;

  IF p_os_id IS NULL OR p_os_id <= 0 THEN
    RAISE EXCEPTION 'p_os_id invalido';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items deve ser um array JSON';
  END IF;

  v_empresa := COALESCE(p_empresa_id, public.current_empresa_id());
  IF v_empresa IS NOT NULL THEN
    PERFORM public.set_current_empresa(v_empresa);
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'os_gestao_itens'
      AND column_name = 'empresa_id'
  ) INTO v_has_empresa_col;

  IF v_has_empresa_col AND v_empresa IS NULL THEN
    RAISE EXCEPTION 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  END IF;

  IF v_has_empresa_col THEN
    v_sql := $sql$
      INSERT INTO public.os_gestao_itens (
        tenant_id,
        empresa_id,
        os_id,
        item_tipo,
        area,
        habilitado,
        responsavel_id,
        data_prevista,
        progresso_percent
      )
      SELECT
        $1::uuid AS tenant_id,
        $2::uuid AS empresa_id,
        $3::integer AS os_id,
        x.item_tipo,
        x.area,
        COALESCE(x.habilitado, false) AS habilitado,
        NULLIF(btrim(COALESCE(x.responsavel_id, '')), '') AS responsavel_id,
        x.data_prevista,
        COALESCE(x.progresso_percent, 0) AS progresso_percent
      FROM jsonb_to_recordset($4::jsonb) AS x(
        item_tipo text,
        area text,
        habilitado boolean,
        responsavel_id text,
        data_prevista date,
        progresso_percent integer
      )
      ON CONFLICT (os_id, item_tipo, area)
      DO UPDATE SET
        habilitado = EXCLUDED.habilitado,
        responsavel_id = EXCLUDED.responsavel_id,
        data_prevista = EXCLUDED.data_prevista,
        progresso_percent = EXCLUDED.progresso_percent
    $sql$;

    EXECUTE v_sql USING v_tenant, v_empresa, p_os_id, p_items;
  ELSE
    v_sql := $sql$
      INSERT INTO public.os_gestao_itens (
        tenant_id,
        os_id,
        item_tipo,
        area,
        habilitado,
        responsavel_id,
        data_prevista,
        progresso_percent
      )
      SELECT
        $1::uuid AS tenant_id,
        $2::integer AS os_id,
        x.item_tipo,
        x.area,
        COALESCE(x.habilitado, false) AS habilitado,
        NULLIF(btrim(COALESCE(x.responsavel_id, '')), '') AS responsavel_id,
        x.data_prevista,
        COALESCE(x.progresso_percent, 0) AS progresso_percent
      FROM jsonb_to_recordset($3::jsonb) AS x(
        item_tipo text,
        area text,
        habilitado boolean,
        responsavel_id text,
        data_prevista date,
        progresso_percent integer
      )
      ON CONFLICT (os_id, item_tipo, area)
      DO UPDATE SET
        habilitado = EXCLUDED.habilitado,
        responsavel_id = EXCLUDED.responsavel_id,
        data_prevista = EXCLUDED.data_prevista,
        progresso_percent = EXCLUDED.progresso_percent
    $sql$;

    EXECUTE v_sql USING v_tenant, p_os_id, p_items;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.seed_os_gestao_itens(integer, jsonb, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seed_os_gestao_itens(integer, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seed_os_gestao_itens(integer, jsonb, uuid) TO service_role;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
