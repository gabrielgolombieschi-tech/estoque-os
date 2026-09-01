-- Importa mais 3 NFS-e de saida da SGU AUTOMACAO LTDA (35.739.220/0001-16),
-- complementando a migration 20260706120000_importar_notas_saida_sgu.sql:
--
--   NFS-e 202600000000005  12/05/2026  TERRA E MAR (cliente 214)  R$ 19.935,11  comp. Mai/2026
--   NFS-e 202600000000006  15/05/2026  JAMEC       (cliente 153)  R$  4.306,67  comp. Mai/2026
--   NFS-e 202600000000007  23/06/2026  JAMEC       (cliente 153)  R$  5.724,76  comp. Jun/2026
--
-- Nenhuma das notas informa parcelas; lancadas a vista (vencimento = emissao),
-- como as demais do lote anterior.
--
-- Diferente da migration anterior, esta NAO insere o titulo AR manualmente:
-- o trigger de f.documento_fiscal ja cria o titulo (com vencimento padrao
-- emissao+15); aqui apenas ajustamos a parcela gerada para vencer na emissao.
-- Se o trigger nao criar o titulo, criamos manualmente como fallback.
--
-- Idempotente: cada nota so e inserida se a chave_acesso ainda nao existir.

do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'; -- tenant "Segau"
  v_empresa_id uuid;
  v_plano_contas_id uuid;
  v_nota record;
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

  for v_nota in
    select * from (values
      ('202600000000005', date '2026-05-12', date '2026-05-01', 214, 19935.11::numeric(15,2),
       'FWSFW8RF1', 'Servico Painel Ponte Rolante P400'),
      ('202600000000006', date '2026-05-15', date '2026-05-01', 153, 4306.67::numeric(15,2),
       'FOZPQMNWP', 'Painel Maquina de Inserir Registro'),
      ('202600000000007', date '2026-06-23', date '2026-06-01', 153, 5724.76::numeric(15,2),
       'VWLOZGRGA', 'Painel Esteira')
    ) as t(numero, emissao, competencia, cliente_id, valor, cod_verificacao, discriminacao)
  loop
    if exists (
      select 1 from f.documento_fiscal
      where tenant_id = v_tenant_id
        and chave_acesso = 'NFSE:35739220000116:UNICA:' || v_nota.numero
        and deleted_at is null
    ) then
      raise notice 'NFS-e % ja existia - pulando', v_nota.numero;
      continue;
    end if;

    insert into f.documento_fiscal (
      tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo, serie, numero,
      emissao_date, competencia_date, cliente_id,
      valor_servicos, valor_total,
      nfse_codigo_verificacao, nfse_status, servico_discriminacao
    ) values (
      v_tenant_id, v_empresa_id, 'NFSE:35739220000116:UNICA:' || v_nota.numero,
      'SAIDA', 'SERVICO', 'NFSE', 'UNICA', v_nota.numero,
      v_nota.emissao, v_nota.competencia, v_nota.cliente_id,
      v_nota.valor, v_nota.valor,
      v_nota.cod_verificacao, 'EMITIDA', v_nota.discriminacao
    ) returning id into v_df_id;

    -- Titulo criado pelo trigger de documento_fiscal (venc padrao +15d)
    select t.id into v_titulo_id
    from f.titulo t
    where t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.tipo = 'AR'
      and t.documento_fiscal_id = v_df_id
      and t.deleted_at is null
    limit 1;

    if v_titulo_id is not null then
      -- ajusta a parcela gerada para a vista (vencimento = emissao)
      update f.titulo_parcela
      set vencimento_date = v_nota.emissao, updated_at = now()
      where tenant_id = v_tenant_id
        and titulo_id = v_titulo_id
        and deleted_at is null;
    else
      -- fallback: trigger nao criou o titulo; cria manualmente
      insert into f.titulo (
        tenant_id, empresa_id, tipo, status, origem, cliente_id, documento_fiscal_id,
        descricao, emissao_date, competencia_date, valor_total, valor_aberto
      ) values (
        v_tenant_id, v_empresa_id, 'AR', 'PENDENTE', 'FATURAMENTO', v_nota.cliente_id, v_df_id,
        'NFSE ' || v_nota.numero, v_nota.emissao, v_nota.competencia, v_nota.valor, v_nota.valor
      ) returning id into v_titulo_id;

      insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
      values (v_tenant_id, v_titulo_id, '001', v_nota.emissao, v_nota.valor, v_nota.valor);

      insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
      values (v_tenant_id, v_titulo_id, v_plano_contas_id, null, 100.0000, v_nota.valor);
    end if;

    raise notice 'NFS-e % importada (df=%, titulo=%)', v_nota.numero, v_df_id, v_titulo_id;
  end loop;
end $$;
