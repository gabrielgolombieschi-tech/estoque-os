-- Renomeia, renumera (X/Y) e reclassifica os parcelamentos que estavam com
-- nomes genéricos sob "SECRETARIA DE ESTADO DA FAZENDA", e completa as séries
-- de Consórcio Onix (36x) e Financiamento Caminhão VW (48x).
--
-- Descobertas tratadas aqui (NÃO destrutivas):
--   * "parcelamento do icms" / "parcelamento icms"  -> ICMS Série 1 / Série 2
--   * "PIS COFINS" (SEFAZ)                           -> PIS/COFINS SANTANDER 60x
--   * "DARF" motivo OPEX_INTERNET (SEFAZ)            -> PIS/COFINS SICREDI 60x (+ motivo p/ TRIB)
--   * "darf débito automático" R$2.468,72 / R$2.275,33 -> Financiamento VIRTUS / POLO
--   * "CONSORCIO ONIX"     -> Consórcio Chevrolet Onix 36x (+ completa 24..36)
--   * "financiamento"/"finan caminhao" (Banco VW) -> Financiamento Caminhão VW 48x (+ completa 28..48)
--
-- NÃO tratados aqui (aguardando decisão): duplicata INSS SICREDI, duplicata
-- "PARCELAMENTO PIS COFINS" (R$2.293,99), fornecedor correto de Virtus/Polo, Grenke.

do $$
declare
  v_tenant  uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_trib   uuid;
  v_invest uuid;
  v_opex_internet uuid;
  v_invest_plano uuid := 'f522e24e-1d79-4125-adee-b76d1b7b8818'; -- INVESTIMENTOS (4.02)
  v_titulo_id uuid;
  m date;
  v_num int;
begin
  select id into v_trib  from f.motivo_compra where codigo='TRIB_DIVERSOS' and tenant_id=v_tenant and deleted_at is null limit 1;
  select id into v_invest from f.motivo_compra where codigo='INVESTIMENTO'  and tenant_id=v_tenant and deleted_at is null limit 1;
  select id into v_opex_internet from f.motivo_compra where codigo='OPEX_INTERNET' and tenant_id=v_tenant and deleted_at is null limit 1;

  -- ════════════════════════════════════════════════════════════════════════
  -- PARTE 1 — RENUMERAR parcelas (numero = posição real X na série de N meses)
  -- formula: numero = N - meses_entre(venc, finaliza)
  -- ════════════════════════════════════════════════════════════════════════

  -- ICMS Série 1 (finaliza 2027-03, N=12)
  update f.titulo_parcela tp
  set numero = (12 - ((extract(year from date '2027-03-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2027-03-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='parcelamento do icms' and t.fornecedor_id=298 and t.status<>'CANCELADO';

  -- ICMS Série 2 (finaliza 2027-02, N=12)
  update f.titulo_parcela tp
  set numero = (12 - ((extract(year from date '2027-02-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2027-02-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='parcelamento icms' and t.fornecedor_id=298 and t.status<>'CANCELADO';

  -- PIS/COFINS SANTANDER (finaliza 2031-02, N=60)
  update f.titulo_parcela tp
  set numero = (60 - ((extract(year from date '2031-02-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2031-02-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='PIS COFINS' and t.fornecedor_id=298 and t.status<>'CANCELADO';

  -- PIS/COFINS SICREDI (finaliza 2030-08, N=60) — identificado por motivo OPEX_INTERNET
  update f.titulo_parcela tp
  set numero = (60 - ((extract(year from date '2030-08-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2030-08-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='DARF' and t.fornecedor_id=298
    and t.motivo_compra_id=v_opex_internet and t.status<>'CANCELADO';

  -- VIRTUS (finaliza 2030-04, N=60) — R$2.468,72
  update f.titulo_parcela tp
  set numero = (60 - ((extract(year from date '2030-04-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2030-04-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='darf débito automático' and t.valor_total=2468.72 and t.status<>'CANCELADO';

  -- POLO (finaliza 2030-04, N=60) — R$2.275,33
  update f.titulo_parcela tp
  set numero = (60 - ((extract(year from date '2030-04-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2030-04-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='darf débito automático' and t.valor_total=2275.33 and t.status<>'CANCELADO';

  -- CONSÓRCIO ONIX (finaliza 2028-07, N=36)
  update f.titulo_parcela tp
  set numero = (36 - ((extract(year from date '2028-07-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2028-07-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='CONSORCIO ONIX' and t.fornecedor_id=590 and t.status<>'CANCELADO';

  -- CAMINHÃO VW (finaliza 2029-02, N=48)
  update f.titulo_parcela tp
  set numero = (48 - ((extract(year from date '2029-02-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2029-02-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao in ('financiamento','finan caminhao') and t.fornecedor_id=414 and t.status<>'CANCELADO';

  -- ════════════════════════════════════════════════════════════════════════
  -- PARTE 2 — RENOMEAR + total_parcelas_serie + motivo
  -- ════════════════════════════════════════════════════════════════════════

  update f.titulo set descricao='PARCELAMENTO ICMS - SEFAZ/SC (Série 1)', total_parcelas_serie=12, updated_at=now()
  where tenant_id=v_tenant and descricao='parcelamento do icms' and fornecedor_id=298 and status<>'CANCELADO' and deleted_at is null;

  update f.titulo set descricao='PARCELAMENTO ICMS - SEFAZ/SC (Série 2)', total_parcelas_serie=12, updated_at=now()
  where tenant_id=v_tenant and descricao='parcelamento icms' and fornecedor_id=298 and status<>'CANCELADO' and deleted_at is null;

  update f.titulo set descricao='PARCELAMENTO PIS/COFINS - SANTANDER 60x', total_parcelas_serie=60, updated_at=now()
  where tenant_id=v_tenant and descricao='PIS COFINS' and fornecedor_id=298 and status<>'CANCELADO' and deleted_at is null;

  update f.titulo set descricao='PARCELAMENTO PIS/COFINS - SICREDI 60x', total_parcelas_serie=60, motivo_compra_id=v_trib, updated_at=now()
  where tenant_id=v_tenant and descricao='DARF' and fornecedor_id=298 and motivo_compra_id=v_opex_internet and status<>'CANCELADO' and deleted_at is null;

  update f.titulo set descricao='FINANCIAMENTO VEÍCULO - VW VIRTUS 60x', total_parcelas_serie=60, motivo_compra_id=v_invest, updated_at=now()
  where tenant_id=v_tenant and descricao='darf débito automático' and valor_total=2468.72 and status<>'CANCELADO' and deleted_at is null;

  update f.titulo set descricao='FINANCIAMENTO VEÍCULO - VW POLO 60x', total_parcelas_serie=60, motivo_compra_id=v_invest, updated_at=now()
  where tenant_id=v_tenant and descricao='darf débito automático' and valor_total=2275.33 and status<>'CANCELADO' and deleted_at is null;

  update f.titulo set descricao='CONSÓRCIO - CHEVROLET ONIX 36x', total_parcelas_serie=36, updated_at=now()
  where tenant_id=v_tenant and descricao='CONSORCIO ONIX' and fornecedor_id=590 and status<>'CANCELADO' and deleted_at is null;

  update f.titulo set descricao='FINANCIAMENTO VEÍCULO - VW CAMINHÃO 48x', total_parcelas_serie=48, updated_at=now()
  where tenant_id=v_tenant and descricao in ('financiamento','finan caminhao') and fornecedor_id=414 and status<>'CANCELADO' and deleted_at is null;

  -- ════════════════════════════════════════════════════════════════════════
  -- PARTE 3 — COMPLETAR séries faltantes
  -- ════════════════════════════════════════════════════════════════════════

  -- Onix: parcelas 24..36 (jul/2027 a jul/2028), dia 12, R$2.002,07
  v_num := 24;
  for m in select generate_series(date '2027-07-01', date '2028-07-01', interval '1 month')::date loop
    insert into f.titulo (tenant_id, empresa_id, tipo, status, origem, fornecedor_id, descricao,
      emissao_date, competencia_date, valor_total, valor_aberto, motivo_compra_id, total_parcelas_serie, created_at, updated_at)
    values (v_tenant, v_empresa, 'AP','PENDENTE','MANUAL', 590, 'CONSÓRCIO - CHEVROLET ONIX 36x',
      m, m, 2002.07, 2002.07, v_invest, 36, now(), now())
    returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_num::text, date_trunc('month',m)::date + 11, 2002.07, 2002.07, now(), now());

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_invest_plano, 100, 2002.07, now(), now());

    v_num := v_num + 1;
  end loop;

  -- Caminhão VW: parcelas 28..48 (jun/2027 a fev/2029), dia 28, R$10.411,83
  v_num := 28;
  for m in select generate_series(date '2027-06-01', date '2029-02-01', interval '1 month')::date loop
    insert into f.titulo (tenant_id, empresa_id, tipo, status, origem, fornecedor_id, descricao,
      emissao_date, competencia_date, valor_total, valor_aberto, motivo_compra_id, total_parcelas_serie, created_at, updated_at)
    values (v_tenant, v_empresa, 'AP','PENDENTE','MANUAL', 414, 'FINANCIAMENTO VEÍCULO - VW CAMINHÃO 48x',
      m, m, 10411.83, 10411.83, v_invest, 48, now(), now())
    returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_num::text, date_trunc('month',m)::date + 27, 10411.83, 10411.83, now(), now());

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_invest_plano, 100, 10411.83, now(), now());

    v_num := v_num + 1;
  end loop;

end$$;
