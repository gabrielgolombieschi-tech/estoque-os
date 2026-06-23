-- Lança fornecedores e parcelas pendentes de dois imobilizados no cartão:
--   NAPORT - Porta de Correr Seccional (10x R$1.150,00) → parcelas 6-10 pendentes
--   Regional Telhas - Cobertura (6x R$3.909,68) → parcelas 1-6 pendentes
-- Classificação: IMOB_AQUISICAO → IMOBILIZADO - AQUISICAO DE ATIVO
-- Vencimento: todo dia 09 do mês (fatura cartão de crédito)

do $$
declare
  v_tenant  uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_motivo  uuid := '277b1782-9231-4fd1-9d44-0c7dce6aabe9'; -- IMOB_AQUISICAO
  v_plano   uuid := 'a18c88a3-441c-4a2b-acf9-0a7c470c31e4'; -- IMOBILIZADO - AQUISICAO DE ATIVO

  v_naport_id   integer;
  v_regional_id integer;
  v_titulo_id   uuid;
  v_mes_inicio  date;
  v_venc        date;
  v_competencia date;
  i             integer;
begin

  -- ── Fornecedor 1: NAPORT ────────────────────────────────────────────────────
  insert into public.fornecedores (
    nome, documento, cnpj,
    tenant_id, empresa_id, ativo, gerar_contas_pagar_auto
  ) values (
    'NAPORT INDUSTRIA DE PORTAS E PORTOES LTDA',
    '26.301.490/0001-50',
    '26.301.490/0001-50',
    v_tenant, v_empresa, true, false
  ) returning id into v_naport_id;

  -- ── Fornecedor 2: Regional Telhas ───────────────────────────────────────────
  insert into public.fornecedores (
    nome, documento, cnpj,
    endereco, tenant_id, empresa_id, ativo, gerar_contas_pagar_auto
  ) values (
    'REGIONAL TELHAS IND COM PRODS SIDERURGICOS LTDA',
    '01.332.001/0003-68',
    '01.332.001/0003-68',
    'Rod. BR 267 Km 15 - Bataguassu - MS - CEP 79780-000',
    v_tenant, v_empresa, true, false
  ) returning id into v_regional_id;

  -- ── NAPORT: parcelas 6 a 10 (Julho a Novembro 2026) ────────────────────────
  -- Compra realizada em 02/2026 (10x), 5 parcelas já liquidadas no cartão.
  for i in 6..10 loop
    v_mes_inicio := ('2026-07-01'::date + ((i - 6) * interval '1 month'))::date;
    v_venc       := date_trunc('month', v_mes_inicio)::date + 8; -- dia 09
    v_competencia := v_mes_inicio;

    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem,
      fornecedor_id, descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto,
      motivo_compra_id, total_parcelas_serie,
      created_at, updated_at
    ) values (
      v_tenant, v_empresa,
      'AP', 'PENDENTE', 'MANUAL',
      v_naport_id,
      'NAPORT - Porta de Correr Seccional 10x (Cartao) — Parc. ' || i || '/10',
      '2026-02-09', v_competencia,
      1150.00, 1150.00,
      v_motivo, 10,
      now(), now()
    ) returning id into v_titulo_id;

    insert into f.titulo_parcela (
      tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto,
      created_at, updated_at
    ) values (
      v_tenant, v_titulo_id, i::text, v_venc, 1150.00, 1150.00,
      now(), now()
    );

    insert into f.titulo_rateio (
      tenant_id, titulo_id, plano_contas_id, percentual, valor,
      created_at, updated_at
    ) values (
      v_tenant, v_titulo_id, v_plano, 100, 1150.00,
      now(), now()
    );
  end loop;

  -- ── Regional Telhas: parcelas 1 a 6 (Julho a Dezembro 2026) ────────────────
  -- NF ainda não recebida. Primeira fatura vence 09/07/2026.
  for i in 1..6 loop
    v_mes_inicio := ('2026-07-01'::date + ((i - 1) * interval '1 month'))::date;
    v_venc       := date_trunc('month', v_mes_inicio)::date + 8; -- dia 09
    v_competencia := v_mes_inicio;

    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem,
      fornecedor_id, descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto,
      motivo_compra_id, total_parcelas_serie,
      created_at, updated_at
    ) values (
      v_tenant, v_empresa,
      'AP', 'PENDENTE', 'MANUAL',
      v_regional_id,
      'REGIONAL TELHAS - Cobertura 6x (Cartao) — Parc. ' || i || '/6',
      '2026-06-23', v_competencia,
      3909.68, 3909.68,
      v_motivo, 6,
      now(), now()
    ) returning id into v_titulo_id;

    insert into f.titulo_parcela (
      tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto,
      created_at, updated_at
    ) values (
      v_tenant, v_titulo_id, i::text, v_venc, 3909.68, 3909.68,
      now(), now()
    );

    insert into f.titulo_rateio (
      tenant_id, titulo_id, plano_contas_id, percentual, valor,
      created_at, updated_at
    ) values (
      v_tenant, v_titulo_id, v_plano, 100, 3909.68,
      now(), now()
    );
  end loop;

end$$;
