-- Fix: ambiguous RPC resolution for remove_os_item_reverte_estoque
--
-- Some databases may still have a legacy overloaded function with a different signature
-- (e.g. empresa_id as integer and os_item_id as text). When PostgREST/Supabase calls
-- the RPC with JSON payload, Postgres can fail to pick the best overload.
--
-- Keep the canonical signature used by the app:
--   remove_os_item_reverte_estoque(p_os_item_id integer, p_realizado_por text, p_motivo text, p_empresa_id uuid)
--
-- Drop the legacy overload (if present).
DROP FUNCTION IF EXISTS public.remove_os_item_reverte_estoque(integer, text, text, text);
-- Ensure PostgREST schema cache refresh.
notify pgrst, 'reload schema';
