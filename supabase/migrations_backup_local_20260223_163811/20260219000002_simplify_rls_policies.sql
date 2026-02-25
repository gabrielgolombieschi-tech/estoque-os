BEGIN;

-- Drop existing policies for OS tables
DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.ordens_servico') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='ordens_servico' LOOP
      EXECUTE format('drop policy if exists %I on public.ordens_servico', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.os_itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='os_itens' LOOP
      EXECUTE format('drop policy if exists %I on public.os_itens', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.os_gestao_itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='os_gestao_itens' LOOP
      EXECUTE format('drop policy if exists %I on public.os_gestao_itens', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='itens' LOOP
      EXECUTE format('drop policy if exists %I on public.itens', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.fornecedores') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='fornecedores' LOOP
      EXECUTE format('drop policy if exists %I on public.fornecedores', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.clientes') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='clientes' LOOP
      EXECUTE format('drop policy if exists %I on public.clientes', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.estoque') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='estoque' LOOP
      EXECUTE format('drop policy if exists %I on public.estoque', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.movimentacoes') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='movimentacoes' LOOP
      EXECUTE format('drop policy if exists %I on public.movimentacoes', r.policyname);
    END LOOP;
  END IF;
END$$;

ALTER TABLE public.ordens_servico ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_gestao_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fornecedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimentacoes ENABLE ROW LEVEL SECURITY;

-- Simplified policies: rely on applyTenant() to inject .eq("tenant_id", ...) filter
-- Permission checks still via can()

CREATE POLICY ordens_servico_select
ON public.ordens_servico
FOR SELECT
TO authenticated
USING (public.can('os','read'));

CREATE POLICY ordens_servico_insert
ON public.ordens_servico
FOR INSERT
TO authenticated
WITH CHECK (public.can('os','write'));

CREATE POLICY ordens_servico_update
ON public.ordens_servico
FOR UPDATE
TO authenticated
USING (public.can('os','write'))
WITH CHECK (public.can('os','write'));

CREATE POLICY ordens_servico_delete
ON public.ordens_servico
FOR DELETE
TO authenticated
USING (public.can('os','delete'));

CREATE POLICY os_itens_select
ON public.os_itens
FOR SELECT
TO authenticated
USING (public.can('os','read'));

CREATE POLICY os_itens_insert
ON public.os_itens
FOR INSERT
TO authenticated
WITH CHECK (public.can('os_itens','write'));

CREATE POLICY os_itens_update
ON public.os_itens
FOR UPDATE
TO authenticated
USING (public.can('os_itens','write'))
WITH CHECK (public.can('os_itens','write'));

CREATE POLICY os_itens_delete
ON public.os_itens
FOR DELETE
TO authenticated
USING (public.can('os_itens','write'));

CREATE POLICY os_gestao_itens_select
ON public.os_gestao_itens
FOR SELECT
TO authenticated
USING (public.can('os','read'));

CREATE POLICY os_gestao_itens_insert
ON public.os_gestao_itens
FOR INSERT
TO authenticated
WITH CHECK (public.can('os_gestao','write'));

CREATE POLICY os_gestao_itens_update
ON public.os_gestao_itens
FOR UPDATE
TO authenticated
USING (public.can('os_gestao','write'))
WITH CHECK (public.can('os_gestao','write'));

CREATE POLICY os_gestao_itens_delete
ON public.os_gestao_itens
FOR DELETE
TO authenticated
USING (public.can('os_gestao','write'));

CREATE POLICY itens_select
ON public.itens
FOR SELECT
TO authenticated
USING (
  public.can('estoque','read')
  OR public.can('os','read')
  OR public.can('cad_itens','write')
);

CREATE POLICY itens_insert
ON public.itens
FOR INSERT
TO authenticated
WITH CHECK (
  public.can('cad_itens','write')
  OR public.can('estoque','write')
);

CREATE POLICY itens_update
ON public.itens
FOR UPDATE
TO authenticated
USING (
  public.can('cad_itens','write')
  OR public.can('estoque','write')
)
WITH CHECK (
  public.can('cad_itens','write')
  OR public.can('estoque','write')
);

CREATE POLICY itens_delete
ON public.itens
FOR DELETE
TO authenticated
USING (
  public.can('cad_itens','write')
  OR public.can('estoque','write')
);

CREATE POLICY fornecedores_select
ON public.fornecedores
FOR SELECT
TO authenticated
USING (
  public.can('estoque','read')
  OR public.can('cad_fornecedores','write')
);

CREATE POLICY fornecedores_insert
ON public.fornecedores
FOR INSERT
TO authenticated
WITH CHECK (
  public.can('cad_fornecedores','write')
  OR public.can('estoque','write')
);

CREATE POLICY fornecedores_update
ON public.fornecedores
FOR UPDATE
TO authenticated
USING (
  public.can('cad_fornecedores','write')
  OR public.can('estoque','write')
)
WITH CHECK (
  public.can('cad_fornecedores','write')
  OR public.can('estoque','write')
);

CREATE POLICY fornecedores_delete
ON public.fornecedores
FOR DELETE
TO authenticated
USING (
  public.can('cad_fornecedores','write')
  OR public.can('estoque','write')
);

CREATE POLICY clientes_select
ON public.clientes
FOR SELECT
TO authenticated
USING (
  public.can('os','read')
  OR public.can('cad_clientes','write')
);

CREATE POLICY clientes_insert
ON public.clientes
FOR INSERT
TO authenticated
WITH CHECK (public.can('cad_clientes','write'));

CREATE POLICY clientes_update
ON public.clientes
FOR UPDATE
TO authenticated
USING (public.can('cad_clientes','write'))
WITH CHECK (public.can('cad_clientes','write'));

CREATE POLICY clientes_delete
ON public.clientes
FOR DELETE
TO authenticated
USING (public.can('cad_clientes','write'));

CREATE POLICY estoque_select
ON public.estoque
FOR SELECT
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND public.can('estoque','read')
);

CREATE POLICY estoque_insert
ON public.estoque
FOR INSERT
TO authenticated
WITH CHECK (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
);

CREATE POLICY estoque_update
ON public.estoque
FOR UPDATE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
)
WITH CHECK (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
);

CREATE POLICY estoque_delete
ON public.estoque
FOR DELETE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
);

CREATE POLICY movimentacoes_select
ON public.movimentacoes
FOR SELECT
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND public.can('estoque','read')
);

CREATE POLICY movimentacoes_insert
ON public.movimentacoes
FOR INSERT
TO authenticated
WITH CHECK (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
);

CREATE POLICY movimentacoes_update
ON public.movimentacoes
FOR UPDATE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
)
WITH CHECK (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
);

CREATE POLICY movimentacoes_delete
ON public.movimentacoes
FOR DELETE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND public.can('estoque','write')
);

NOTIFY pgrst, 'reload schema';

COMMIT;
