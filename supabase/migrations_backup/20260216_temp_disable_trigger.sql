BEGIN;

-- Temporarily disable the trigger that's causing the "column v.user_id" error
DROP TRIGGER IF EXISTS trigger_validate_apontamento_colaborador ON public.apontamentos_horas;

-- Keep the function for reference but don't use it
-- DROP FUNCTION IF EXISTS public.validate_apontamento_colaborador_contrato();

COMMIT;

NOTIFY pgrst, 'reload schema';
