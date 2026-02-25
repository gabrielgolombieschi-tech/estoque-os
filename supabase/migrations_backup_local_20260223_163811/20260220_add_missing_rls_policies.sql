BEGIN;

-- Drop existing policies for apontamentos, colaboradores, tipos_horas
DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.apontamentos_horas') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='apontamentos_horas' LOOP
      EXECUTE format('drop policy if exists %I on public.apontamentos_horas', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.colaboradores') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='colaboradores' LOOP
      EXECUTE format('drop policy if exists %I on public.colaboradores', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.tipos_horas') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='tipos_horas' LOOP
      EXECUTE format('drop policy if exists %I on public.tipos_horas', r.policyname);
    END LOOP;
  END IF;
END$$;

ALTER TABLE public.apontamentos_horas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipos_horas ENABLE ROW LEVEL SECURITY;

-- apontamentos_horas policies
CREATE POLICY apontamentos_select
ON public.apontamentos_horas
FOR SELECT
TO authenticated
USING (public.can('apontamentos','read'));

CREATE POLICY apontamentos_insert
ON public.apontamentos_horas
FOR INSERT
TO authenticated
WITH CHECK (public.can('apontamentos','write'));

CREATE POLICY apontamentos_update
ON public.apontamentos_horas
FOR UPDATE
TO authenticated
USING (public.can('apontamentos','write'))
WITH CHECK (public.can('apontamentos','write'));

CREATE POLICY apontamentos_delete
ON public.apontamentos_horas
FOR DELETE
TO authenticated
USING (public.can('apontamentos','delete'));

-- colaboradores policies
CREATE POLICY colaboradores_select
ON public.colaboradores
FOR SELECT
TO authenticated
USING (
  public.can('apontamentos','read')
);

CREATE POLICY colaboradores_insert
ON public.colaboradores
FOR INSERT
TO authenticated
WITH CHECK (public.can('apontamentos','config'));

CREATE POLICY colaboradores_update
ON public.colaboradores
FOR UPDATE
TO authenticated
USING (public.can('apontamentos','config'))
WITH CHECK (public.can('apontamentos','config'));

CREATE POLICY colaboradores_delete
ON public.colaboradores
FOR DELETE
TO authenticated
USING (public.can('apontamentos','config'));

-- tipos_horas policies
CREATE POLICY tipos_horas_select
ON public.tipos_horas
FOR SELECT
TO authenticated
USING (
  public.can('apontamentos','read')
);

CREATE POLICY tipos_horas_insert
ON public.tipos_horas
FOR INSERT
TO authenticated
WITH CHECK (public.can('apontamentos','config'));

CREATE POLICY tipos_horas_update
ON public.tipos_horas
FOR UPDATE
TO authenticated
USING (public.can('apontamentos','config'))
WITH CHECK (public.can('apontamentos','config'));

CREATE POLICY tipos_horas_delete
ON public.tipos_horas
FOR DELETE
TO authenticated
USING (public.can('apontamentos','config'));

NOTIFY pgrst, 'reload schema';

COMMIT;
