-- Add motivo_compra_id to public.itens (used by /itens UI).
-- This matches the "Classificação / Motivo" selection used in XML import (f.motivo_compra).

DO $$
BEGIN
  IF to_regclass('public.itens') IS NULL THEN
    RAISE NOTICE 'public.itens not found; skipping.';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'itens'
      AND column_name = 'motivo_compra_id'
  ) THEN
    ALTER TABLE public.itens
      ADD COLUMN motivo_compra_id uuid;
  END IF;

  -- Optional FK (best-effort) if f.motivo_compra exists.
  IF to_regclass('f.motivo_compra') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'itens_motivo_compra_fk'
        AND conrelid = 'public.itens'::regclass
    ) THEN
      ALTER TABLE public.itens
        ADD CONSTRAINT itens_motivo_compra_fk
        FOREIGN KEY (motivo_compra_id)
        REFERENCES f.motivo_compra(id)
        ON DELETE SET NULL;
    END IF;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS itens_tenant_empresa_motivo_compra_idx
  ON public.itens (tenant_id, empresa_id, motivo_compra_id);
