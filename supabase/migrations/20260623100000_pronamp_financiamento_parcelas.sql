-- Adiciona total_parcelas na view de AP aging para exibir "X/Y" na coluna Parcela.
-- Cria classificação DESP_FINANCIAMENTO e motivo FINANCIAMENTO_RURAL.
-- Registra as 2 parcelas restantes do PRONAMP (47/48 e 48/48).

-- ─── 1. Atualiza view r_ap_aging_detalhe ────────────────────────────────────
do $$
begin
  if to_regclass('f.titulo') is not null
    and to_regclass('f.titulo_parcela') is not null then
    execute $v$
      create or replace view f.r_ap_aging_detalhe as
      select
        t.tenant_id,
        t.empresa_id,
        t.id                                              as titulo_id,
        tp.id                                             as parcela_id,
        tp.numero                                         as parcela_numero,
        t.fornecedor_id,
        coalesce(forn.nome, 'SEM FORNECEDOR')             as fornecedor_nome,
        coalesce(mc.codigo, 'NAO_CLASSIFICADO')           as motivo_codigo,
        coalesce(mc.nome,   'NAO CLASSIFICADO')           as motivo_nome,
        tp.vencimento_date,
        (current_date - tp.vencimento_date)               as dias_atraso,
        tp.valor                                          as valor_parcela,
        tp.valor_aberto,
        t.status,
        t.emissao_date,
        t.competencia_date,
        (select count(*)
           from f.titulo_parcela tp2
          where tp2.titulo_id = t.id
            and tp2.deleted_at is null)                   as total_parcelas
      from f.titulo_parcela tp
      join f.titulo t on t.id = tp.titulo_id
      left join f.titulo_aprovacao ta
        on  ta.tenant_id  = t.tenant_id
        and ta.titulo_id  = t.id
        and ta.deleted_at is null
      left join f.motivo_compra mc
        on  mc.id         = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
        and mc.deleted_at is null
      left join public.fornecedores forn on forn.id = t.fornecedor_id
      where tp.deleted_at  is null
        and t.deleted_at   is null
        and t.tipo         = 'AP'
        and tp.valor_aberto > 0
    $v$;
  end if;
end$$;

-- ─── 2. Plano de contas — DESP_FINANCIAMENTO ────────────────────────────────
insert into f.plano_contas (
  id, tenant_id, codigo, nome, tipo, ativo, created_at, updated_at
)
values (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid,
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7',
  'DESP_FINANCIAMENTO',
  'DESPESA - FINANCIAMENTOS / EMPRÉSTIMOS',
  'ANALITICA',
  true,
  now(), now()
)
on conflict (id) do nothing;

-- ─── 3. Motivo de compra — FINANCIAMENTO_RURAL ──────────────────────────────
insert into f.motivo_compra (
  id, tenant_id, codigo, nome, aplica_em, plano_contas_id,
  requires_text, requires_os, ativo, favorito, ordem, visivel_import_nfe,
  created_at, updated_at
)
values (
  'b2c3d4e5-f6a7-8901-bcde-f01234567891'::uuid,
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7',
  'FINANCIAMENTO_RURAL',
  'FINANCIAMENTO RURAL / PRONAMP',
  'AMBOS',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid,
  false, false, true, false, 99, false,
  now(), now()
)
on conflict (id) do nothing;

-- ─── 4. Título AP — PRONAMP Parc. 47/48 (julho 2026) ───────────────────────
with t47 as (
  insert into f.titulo (
    tenant_id, empresa_id, tipo, status, origem,
    fornecedor_id, descricao, emissao_date, competencia_date,
    valor_total, valor_aberto, motivo_compra_id,
    created_at, updated_at
  ) values (
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7',
    'f0e74f49-a127-46b4-901b-f7b37e43c690',
    'AP', 'PENDENTE', 'MANUAL',
    607,
    'PRONAMP 48x — Parc. 47/48',
    '2026-07-01', '2026-07-01',
    7462.09, 7462.09,
    'b2c3d4e5-f6a7-8901-bcde-f01234567891'::uuid,
    now(), now()
  ) returning id, tenant_id
),
p47 as (
  insert into f.titulo_parcela (
    tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto, created_at, updated_at
  )
  select tenant_id, id, '1', '2026-07-15', 7462.09, 7462.09, now(), now()
  from t47
  returning titulo_id, tenant_id
)
insert into f.titulo_rateio (
  tenant_id, titulo_id, plano_contas_id, percentual, valor, created_at, updated_at
)
select tenant_id, titulo_id,
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid,
  100, 7462.09,
  now(), now()
from p47;

-- ─── 5. Título AP — PRONAMP Parc. 48/48 (agosto 2026) ──────────────────────
with t48 as (
  insert into f.titulo (
    tenant_id, empresa_id, tipo, status, origem,
    fornecedor_id, descricao, emissao_date, competencia_date,
    valor_total, valor_aberto, motivo_compra_id,
    created_at, updated_at
  ) values (
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7',
    'f0e74f49-a127-46b4-901b-f7b37e43c690',
    'AP', 'PENDENTE', 'MANUAL',
    607,
    'PRONAMP 48x — Parc. 48/48',
    '2026-08-01', '2026-08-01',
    7462.09, 7462.09,
    'b2c3d4e5-f6a7-8901-bcde-f01234567891'::uuid,
    now(), now()
  ) returning id, tenant_id
),
p48 as (
  insert into f.titulo_parcela (
    tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto, created_at, updated_at
  )
  select tenant_id, id, '1', '2026-08-15', 7462.09, 7462.09, now(), now()
  from t48
  returning titulo_id, tenant_id
)
insert into f.titulo_rateio (
  tenant_id, titulo_id, plano_contas_id, percentual, valor, created_at, updated_at
)
select tenant_id, titulo_id,
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid,
  100, 7462.09,
  now(), now()
from p48;
