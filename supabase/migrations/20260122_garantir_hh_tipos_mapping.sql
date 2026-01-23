-- Migration: Garantir mapeamentos corretos em hh_tipos_mapping
-- Data: 2026-01-22
-- Descrição: Verifica e insere (se não existirem) os 3 mapeamentos necessários
--            entre tipos_horas (UUID) e hh_lancamentos.hh_tipo_id (BIGINT)

BEGIN;

-- Garantir mapeamento para NORMAL (0%)
INSERT INTO public.hh_tipos_mapping (tipo_hora_id, hh_tipo_id, tenant_id, ativo)
SELECT 
  '6e46a91d-8e57-4118-a244-ec18c2bdb1f5'::uuid,
  10,
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.hh_tipos_mapping 
  WHERE tipo_hora_id = '6e46a91d-8e57-4118-a244-ec18c2bdb1f5'
    AND tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
);

-- Garantir mapeamento para EXTRA_50 (50%)
INSERT INTO public.hh_tipos_mapping (tipo_hora_id, hh_tipo_id, tenant_id, ativo)
SELECT 
  '635795d6-274b-4510-9aea-84aa27f217dc'::uuid,
  13,
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.hh_tipos_mapping 
  WHERE tipo_hora_id = '635795d6-274b-4510-9aea-84aa27f217dc'
    AND tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
);

-- Garantir mapeamento para EXTRA_100 (100%)
INSERT INTO public.hh_tipos_mapping (tipo_hora_id, hh_tipo_id, tenant_id, ativo)
SELECT 
  '151be039-ed58-45f4-99f1-1d9a037b34bf'::uuid,
  11,
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.hh_tipos_mapping 
  WHERE tipo_hora_id = '151be039-ed58-45f4-99f1-1d9a037b34bf'
    AND tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
);

COMMIT;

NOTIFY pgrst, 'reload schema';
