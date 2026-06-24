-- Decisões do financeiro:
--   1. INSS Sicredi duplicado -> remove a cópia, renomeia "PARCELAMENTO INSS - SICREDI 36x"
--      (finaliza 03/2028, N=36) e renumera.
--   2. "PARCELAMENTO PIS COFINS" (R$2.293,99) -> duplicata: cancelar (soft delete).
--   3. Virtus/Polo -> fornecedor correto = Banco Volkswagen (414); completar até 60x.
--   4. Grenke -> cria fornecedor "A GC LOCACAO DE EQUIPAMENTOS LTDA (GRENKE)",
--      repõe os títulos "Centro de Usinagem CNC" (estavam em MEKANODRILL), renomeia
--      "LEASING GRENKE - CENTRO DE USINAGEM CNC 60x" (finaliza 06/2030, N=60) e renumera.

do $$
declare
  v_tenant  uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_invest uuid;
  v_invest_plano uuid := 'f522e24e-1d79-4125-adee-b76d1b7b8818';
  v_grenke_id integer;
  v_titulo_id uuid;
  m date;
  v_num int;
begin
  select id into v_invest from f.motivo_compra where codigo='INVESTIMENTO' and tenant_id=v_tenant and deleted_at is null limit 1;

  -- ════════════════════════════════════════════════════════════════════════
  -- 1. INSS SICREDI — remover duplicata (mantém 1 por mês)
  -- ════════════════════════════════════════════════════════════════════════
  create temp table _inss_dup on commit drop as
  select titulo_id from (
    select t.id as titulo_id,
      row_number() over (partition by tp.vencimento_date order by t.created_at, t.id) as rn
    from f.titulo t
    join f.titulo_parcela tp on tp.titulo_id=t.id and tp.deleted_at is null
    where t.tenant_id=v_tenant and t.descricao='DARF' and t.fornecedor_id=298
      and t.valor_total=1658.81 and t.origem='XML'
      and t.deleted_at is null and t.status<>'CANCELADO'
  ) x where rn > 1;

  update f.titulo_rateio  set deleted_at=now() where titulo_id in (select titulo_id from _inss_dup) and deleted_at is null;
  update f.titulo_parcela set deleted_at=now() where titulo_id in (select titulo_id from _inss_dup) and deleted_at is null;
  update f.titulo set deleted_at=now(), status='CANCELADO', updated_at=now() where id in (select titulo_id from _inss_dup);

  -- renumerar remanescentes (finaliza 2028-03, N=36)
  update f.titulo_parcela tp
  set numero = (36 - ((extract(year from date '2028-03-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2028-03-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='DARF' and t.fornecedor_id=298
    and t.valor_total=1658.81 and t.status<>'CANCELADO';

  update f.titulo set descricao='PARCELAMENTO INSS - SICREDI 36x', total_parcelas_serie=36, updated_at=now()
  where tenant_id=v_tenant and descricao='DARF' and fornecedor_id=298 and valor_total=1658.81
    and status<>'CANCELADO' and deleted_at is null;

  -- ════════════════════════════════════════════════════════════════════════
  -- 2. Cancelar duplicata "PARCELAMENTO PIS COFINS" (R$2.293,99)
  -- ════════════════════════════════════════════════════════════════════════
  create temp table _pc_dup on commit drop as
  select id as titulo_id from f.titulo
  where tenant_id=v_tenant and descricao='PARCELAMENTO PIS COFINS' and fornecedor_id=298
    and deleted_at is null;

  update f.titulo_rateio  set deleted_at=now() where titulo_id in (select titulo_id from _pc_dup) and deleted_at is null;
  update f.titulo_parcela set deleted_at=now() where titulo_id in (select titulo_id from _pc_dup) and deleted_at is null;
  update f.titulo set deleted_at=now(), status='CANCELADO', updated_at=now() where id in (select titulo_id from _pc_dup);

  -- ════════════════════════════════════════════════════════════════════════
  -- 3. Virtus / Polo — fornecedor = Banco Volkswagen (414) + completar 24..60
  -- ════════════════════════════════════════════════════════════════════════
  update f.titulo set fornecedor_id=414, updated_at=now()
  where tenant_id=v_tenant
    and descricao in ('FINANCIAMENTO VEÍCULO - VW VIRTUS 60x','FINANCIAMENTO VEÍCULO - VW POLO 60x')
    and status<>'CANCELADO' and deleted_at is null;

  -- VIRTUS: parcelas 24..60 (abr/2027 a abr/2030), dia 23, R$2.468,72
  v_num := 24;
  for m in select generate_series(date '2027-04-01', date '2030-04-01', interval '1 month')::date loop
    insert into f.titulo (tenant_id, empresa_id, tipo, status, origem, fornecedor_id, descricao,
      emissao_date, competencia_date, valor_total, valor_aberto, motivo_compra_id, total_parcelas_serie, created_at, updated_at)
    values (v_tenant, v_empresa, 'AP','PENDENTE','MANUAL', 414, 'FINANCIAMENTO VEÍCULO - VW VIRTUS 60x',
      m, m, 2468.72, 2468.72, v_invest, 60, now(), now())
    returning id into v_titulo_id;
    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_num::text, date_trunc('month',m)::date + 22, 2468.72, 2468.72, now(), now());
    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_invest_plano, 100, 2468.72, now(), now());
    v_num := v_num + 1;
  end loop;

  -- POLO: parcelas 24..60 (abr/2027 a abr/2030), dia 23, R$2.275,33
  v_num := 24;
  for m in select generate_series(date '2027-04-01', date '2030-04-01', interval '1 month')::date loop
    insert into f.titulo (tenant_id, empresa_id, tipo, status, origem, fornecedor_id, descricao,
      emissao_date, competencia_date, valor_total, valor_aberto, motivo_compra_id, total_parcelas_serie, created_at, updated_at)
    values (v_tenant, v_empresa, 'AP','PENDENTE','MANUAL', 414, 'FINANCIAMENTO VEÍCULO - VW POLO 60x',
      m, m, 2275.33, 2275.33, v_invest, 60, now(), now())
    returning id into v_titulo_id;
    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_num::text, date_trunc('month',m)::date + 22, 2275.33, 2275.33, now(), now());
    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor, created_at, updated_at)
    values (v_tenant, v_titulo_id, v_invest_plano, 100, 2275.33, now(), now());
    v_num := v_num + 1;
  end loop;

  -- ════════════════════════════════════════════════════════════════════════
  -- 4. Grenke — cria fornecedor e repõe os títulos de leasing
  -- ════════════════════════════════════════════════════════════════════════
  select id into v_grenke_id from public.fornecedores
  where tenant_id=v_tenant and documento_norm='14262033000114' limit 1;

  if v_grenke_id is null then
    insert into public.fornecedores (nome, documento, cnpj, endereco, email, telefone,
      tenant_id, empresa_id, ativo, gerar_contas_pagar_auto)
    values ('A GC LOCACAO DE EQUIPAMENTOS LTDA (GRENKE)', '14.262.033/0001-14', '14.262.033/0001-14',
      'Rua Surubim, 504, cj. 51, Brooklin Novo - São Paulo/SP', 'service@grenke.com.br', '+55 11 4302 2310',
      v_tenant, v_empresa, true, false)
    returning id into v_grenke_id;
  end if;

  -- renumerar (finaliza 2030-06, N=60)
  update f.titulo_parcela tp
  set numero = (60 - ((extract(year from date '2030-06-01')::int - extract(year from tp.vencimento_date)::int)*12
                    + (extract(month from date '2030-06-01')::int - extract(month from tp.vencimento_date)::int)))::text,
      updated_at = now()
  from f.titulo t
  where tp.titulo_id=t.id and tp.deleted_at is null and t.deleted_at is null
    and t.tenant_id=v_tenant and t.descricao='Centro de Usinagem CNC' and t.valor_total=10706.16 and t.status<>'CANCELADO';

  update f.titulo set fornecedor_id=v_grenke_id,
    descricao='LEASING GRENKE - CENTRO DE USINAGEM CNC 60x', total_parcelas_serie=60, updated_at=now()
  where tenant_id=v_tenant and descricao='Centro de Usinagem CNC' and valor_total=10706.16
    and status<>'CANCELADO' and deleted_at is null;

end$$;
