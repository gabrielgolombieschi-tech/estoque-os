-- Importa as notas de saida da SGU AUTOMACAO LTDA (CNPJ 35.739.220/0001-16)
-- a partir dos DANFEs/NFS-e fornecidos, ja que nao ha XML disponivel para o
-- fluxo de import da tela. Segue as mesmas convencoes de
-- f.fn_upsert_ar_from_nfe_venda / import_nfse_saida:
--   documento_fiscal (SAIDA) + titulo AR PENDENTE origem FATURAMENTO
--   + titulo_parcela (duplicatas) + titulo_rateio 100% no plano 3.01.
--
-- Notas:
--   NF-e  134  21/01/2026  PAJOARA (cliente 143)  R$ 95.892,33   EMITIDA, 1 parcela a vista
--   NFS-e 202600000000001 07/01/2026 CRANES (cliente 74) R$ 1.688,18 EMITIDA, a vista
--   NF-e  136  26/02/2026  ELETRICA SEGAU (cliente 39) R$ 2.053.736,00 CANCELADA (substituida pela 137) - sem AR
--   NF-e  137  27/02/2026  ELETRICA SEGAU (cliente 39) R$ 2.053.736,00 EMITIDA, 12 duplicatas
--
-- Idempotente: cada nota so e inserida se a chave_acesso ainda nao existir.

do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'; -- tenant "Segau"
  v_empresa_id uuid;                                          -- SGU AUTOMACAO
  v_plano_contas_id uuid;
  v_df_id uuid;
  v_titulo_id uuid;
begin
  select id into v_empresa_id
  from c.empresa
  where tenant_id = v_tenant_id and codigo = 'SGU' and deleted_at is null
  limit 1;
  if v_empresa_id is null then
    raise exception 'empresa SGU nao encontrada - abortando';
  end if;

  select pc.id into v_plano_contas_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id and pc.codigo = '3.01' and pc.deleted_at is null
  limit 1;
  if v_plano_contas_id is null then
    raise exception 'plano de contas 3.01 nao encontrado - abortando';
  end if;

  ---------------------------------------------------------------------------
  -- NF-e 134 - PAJOARA - EMITIDA - 1 parcela a vista (21/01/2026)
  ---------------------------------------------------------------------------
  if not exists (
    select 1 from f.documento_fiscal
    where tenant_id = v_tenant_id
      and chave_acesso = '42260135739220000116550010000001341000002370'
      and deleted_at is null
  ) then
    insert into f.documento_fiscal (
      tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo, serie, numero,
      emissao_date, competencia_date, cliente_id,
      valor_produtos, valor_total, nfe_status
    ) values (
      v_tenant_id, v_empresa_id, '42260135739220000116550010000001341000002370',
      'SAIDA', 'PRODUTO', '55', '1', '134',
      date '2026-01-21', date '2026-01-01', 143,
      95892.33, 95892.33, 'EMITIDA'
    ) returning id into v_df_id;

    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem, cliente_id, documento_fiscal_id,
      descricao, emissao_date, competencia_date, valor_total, valor_aberto
    ) values (
      v_tenant_id, v_empresa_id, 'AR', 'PENDENTE', 'FATURAMENTO', 143, v_df_id,
      'NFE 134/1', date '2026-01-21', date '2026-01-01', 95892.33, 95892.33
    ) returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_tenant_id, v_titulo_id, '001', date '2026-01-21', 95892.33, 95892.33);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_tenant_id, v_titulo_id, v_plano_contas_id, null, 100.0000, 95892.33);

    raise notice 'NF-e 134 importada (df=%)', v_df_id;
  else
    raise notice 'NF-e 134 ja existia - pulando';
  end if;

  ---------------------------------------------------------------------------
  -- NFS-e 202600000000001 - CRANES - EMITIDA - a vista (07/01/2026)
  ---------------------------------------------------------------------------
  if not exists (
    select 1 from f.documento_fiscal
    where tenant_id = v_tenant_id
      and chave_acesso = 'NFSE:35739220000116:UNICA:202600000000001'
      and deleted_at is null
  ) then
    insert into f.documento_fiscal (
      tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo, serie, numero,
      emissao_date, competencia_date, cliente_id,
      valor_servicos, valor_total,
      nfse_codigo_verificacao, nfse_status, servico_discriminacao
    ) values (
      v_tenant_id, v_empresa_id, 'NFSE:35739220000116:UNICA:202600000000001',
      'SAIDA', 'SERVICO', 'NFSE', 'UNICA', '202600000000001',
      date '2026-01-07', date '2026-01-01', 74,
      1688.18, 1688.18,
      'Z8HWUEIF8', 'EMITIDA', 'Mao de obra projetos'
    ) returning id into v_df_id;

    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem, cliente_id, documento_fiscal_id,
      descricao, emissao_date, competencia_date, valor_total, valor_aberto
    ) values (
      v_tenant_id, v_empresa_id, 'AR', 'PENDENTE', 'FATURAMENTO', 74, v_df_id,
      'NFSE 202600000000001', date '2026-01-07', date '2026-01-01', 1688.18, 1688.18
    ) returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_tenant_id, v_titulo_id, '001', date '2026-01-07', 1688.18, 1688.18);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_tenant_id, v_titulo_id, v_plano_contas_id, null, 100.0000, 1688.18);

    raise notice 'NFS-e 202600000000001 importada (df=%)', v_df_id;
  else
    raise notice 'NFS-e 202600000000001 ja existia - pulando';
  end if;

  ---------------------------------------------------------------------------
  -- NF-e 136 - ELETRICA SEGAU - CANCELADA (substituida pela NF-e 137)
  -- Registrada apenas para historico fiscal; nao gera contas a receber.
  ---------------------------------------------------------------------------
  if not exists (
    select 1 from f.documento_fiscal
    where tenant_id = v_tenant_id
      and chave_acesso = '42260235739220000116550010000001361000002408'
      and deleted_at is null
  ) then
    insert into f.documento_fiscal (
      tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo, serie, numero,
      emissao_date, competencia_date, cliente_id,
      valor_produtos, valor_total, nfe_status
    ) values (
      v_tenant_id, v_empresa_id, '42260235739220000116550010000001361000002408',
      'SAIDA', 'PRODUTO', '55', '1', '136',
      date '2026-02-26', date '2026-02-01', 39,
      2053736.00, 2053736.00, 'CANCELADA'
    ) returning id into v_df_id;

    raise notice 'NF-e 136 importada como CANCELADA (df=%)', v_df_id;
  else
    raise notice 'NF-e 136 ja existia - pulando';
  end if;

  ---------------------------------------------------------------------------
  -- NF-e 137 - ELETRICA SEGAU - EMITIDA - 12 duplicatas mensais
  ---------------------------------------------------------------------------
  if not exists (
    select 1 from f.documento_fiscal
    where tenant_id = v_tenant_id
      and chave_acesso = '42260235739220000116550010000001371000002421'
      and deleted_at is null
  ) then
    insert into f.documento_fiscal (
      tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo, serie, numero,
      emissao_date, competencia_date, cliente_id,
      valor_produtos, valor_total, nfe_status
    ) values (
      v_tenant_id, v_empresa_id, '42260235739220000116550010000001371000002421',
      'SAIDA', 'PRODUTO', '55', '1', '137',
      date '2026-02-27', date '2026-02-01', 39,
      2053736.00, 2053736.00, 'EMITIDA'
    ) returning id into v_df_id;

    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem, cliente_id, documento_fiscal_id,
      descricao, emissao_date, competencia_date, valor_total, valor_aberto
    ) values (
      v_tenant_id, v_empresa_id, 'AR', 'PENDENTE', 'FATURAMENTO', 39, v_df_id,
      'NFE 137/1', date '2026-02-27', date '2026-02-01', 2053736.00, 2053736.00
    ) returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values
      (v_tenant_id, v_titulo_id, '001', date '2026-03-29', 171144.63, 171144.63),
      (v_tenant_id, v_titulo_id, '002', date '2026-04-28', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '003', date '2026-05-28', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '004', date '2026-06-27', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '005', date '2026-07-27', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '006', date '2026-08-26', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '007', date '2026-09-25', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '008', date '2026-10-25', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '009', date '2026-11-24', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '010', date '2026-12-24', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '011', date '2027-01-23', 171144.67, 171144.67),
      (v_tenant_id, v_titulo_id, '012', date '2027-02-22', 171144.67, 171144.67);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_tenant_id, v_titulo_id, v_plano_contas_id, null, 100.0000, 2053736.00);

    raise notice 'NF-e 137 importada (df=%)', v_df_id;
  else
    raise notice 'NF-e 137 ja existia - pulando';
  end if;
end $$;
