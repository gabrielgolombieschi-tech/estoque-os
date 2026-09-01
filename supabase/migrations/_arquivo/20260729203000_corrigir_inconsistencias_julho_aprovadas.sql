-- Classifica as 46 pendencias de julho aprovadas pelo responsavel em
-- 2026-07-29. O reembolso de cartao de Gabriel (R$ 7.048,28) fica fora do
-- escopo porque depende do rateio entre ADM_FIN e COMERCIAL.
--
-- Decisoes confirmadas:
-- - materia-prima em estoque para processo: EST_MAT_PRIMA / PRODUCAO;
-- - locacao e manutencao de veiculos: FROTA;
-- - alimentacao, diaria e passagem para cliente: CAMPO;
-- - consumos operacionais e ferramentas: PRODUCAO;
-- - aluguel de apoio em Tijucas: CAMPO;
-- - fretes gerais: EST_LOG;
-- - beneficios e treinamentos administrativos: PESSOAS;
-- - estrutura, limpeza, residuos e monitoramento: ESTRUTURA.
--
-- Valores, vencimentos, pagamentos, documentos fiscais e vinculos de OS
-- permanecem inalterados.

do $corrigir_inconsistencias_julho_aprovadas$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_plano_treinamento_id uuid;
  v_plano_id uuid;
  v_centro_id uuid;
  v_motivo_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_resultado jsonb;
  v_caso record;
  v_definicao record;
  v_titulo f.titulo%rowtype;
  v_motivo_efetivo_codigo text;
  v_rateio_count integer;
  v_documento_fiscal_id uuid;
  v_nf_entrada_id bigint;
  v_corrigidos integer := 0;
  v_valor_corrigido numeric := 0;
begin
  select pc.id
    into v_plano_treinamento_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_TREINAMENTO'
    and pc.deleted_at is null
  limit 1;

  if v_plano_treinamento_id is null then
    insert into f.plano_contas (
      tenant_id,
      codigo,
      nome,
      tipo,
      ativo,
      created_at,
      updated_at
    )
    values (
      v_tenant_id,
      'DESP_TREINAMENTO',
      'DESPESA - TREINAMENTOS E CAPACITACAO',
      'ANALITICA',
      true,
      now(),
      now()
    )
    returning id into v_plano_treinamento_id;
  else
    update f.plano_contas pc
    set
      nome = 'DESPESA - TREINAMENTOS E CAPACITACAO',
      tipo = 'ANALITICA',
      ativo = true,
      updated_at = now(),
      deleted_at = null
    where pc.id = v_plano_treinamento_id
      and pc.tenant_id = v_tenant_id;
  end if;

  -- Motivos especificos impedem que regras de fornecedor misturem, por
  -- exemplo, multas da locadora com locacao de veiculos.
  for v_definicao in
    select *
    from (
      values
        (
          'LOCACAO_VEICULOS'::text,
          'LOCACAO - VEICULOS'::text,
          'DESP_LOCACAO'::text,
          'SERVICO'::text,
          850::integer
        ),
        (
          'MANUTENCAO_VEICULOS',
          'MANUTENCAO - VEICULOS DA FROTA',
          'DESP_MANUT_VEICULO',
          'SERVICO',
          851
        ),
        (
          'BENEF_SAUDE_OCUPACIONAL',
          'BENEFICIO - SAUDE OCUPACIONAL / ASO',
          'DESP_BENEFICIOS',
          'SERVICO',
          852
        ),
        (
          'BENEF_SEGURO_VIDA',
          'BENEFICIO - SEGURO DE VIDA',
          'DESP_BENEFICIOS',
          'SERVICO',
          853
        ),
        (
          'CONSUMO_ESTRUTURA',
          'CONSUMO - ESTRUTURA E UTILIDADES',
          'CONSUMO_GERAL',
          'PRODUTO',
          854
        ),
        (
          'CONSUMO_PRODUCAO',
          'CONSUMO - PRODUCAO E ENGENHARIA',
          'CONSUMO_GERAL',
          'PRODUTO',
          855
        ),
        (
          'MANUTENCAO_PRODUCAO',
          'MANUTENCAO - MAQUINAS E FERRAMENTAS DA PRODUCAO',
          'DESP_MANUTENCAO',
          'AMBOS',
          856
        ),
        (
          'MULTA_VEICULO',
          'NAO DEDUTIVEL - MULTA DE VEICULO',
          'ND_MULTAS',
          'AMBOS',
          857
        ),
        (
          'SERV_COLETA_RESIDUOS',
          'SERVICO - COLETA DE RESIDUOS',
          'DESP_SERV_TERCEIROS',
          'SERVICO',
          858
        ),
        (
          'TREINAMENTO_PESSOAS',
          'TREINAMENTO - PESSOAS',
          'DESP_TREINAMENTO',
          'SERVICO',
          859
        ),
        (
          'TREINAMENTO_PRODUCAO',
          'TREINAMENTO - MAQUINAS E PRODUCAO',
          'DESP_TREINAMENTO',
          'SERVICO',
          860
        ),
        (
          'VIAGEM_PASSAGEM_AEREA',
          'VIAGEM - PASSAGEM AEREA PARA SERVICO EM CLIENTE',
          'DESP_VIAGEM',
          'SERVICO',
          861
        ),
        (
          'SERV_MONITORAMENTO_PATRIMONIAL',
          'SERVICO - MONITORAMENTO, CAMERAS E ALARME',
          'DESP_SERV_TERCEIROS',
          'SERVICO',
          862
        )
    ) as definicoes(
      motivo_codigo,
      motivo_nome,
      plano_codigo,
      aplica_em,
      ordem
    )
  loop
    select pc.id
      into strict v_plano_id
    from f.plano_contas pc
    where pc.tenant_id = v_tenant_id
      and pc.codigo = v_definicao.plano_codigo
      and pc.tipo = 'ANALITICA'
      and pc.ativo
      and pc.deleted_at is null;

    insert into f.motivo_compra (
      tenant_id,
      codigo,
      nome,
      requires_text,
      requires_os,
      ativo,
      aplica_em,
      plano_contas_id,
      favorito,
      ordem,
      visivel_import_nfe
    )
    values (
      v_tenant_id,
      v_definicao.motivo_codigo,
      v_definicao.motivo_nome,
      false,
      false,
      true,
      v_definicao.aplica_em,
      v_plano_id,
      true,
      v_definicao.ordem,
      false
    )
    on conflict (tenant_id, codigo)
    do update set
      nome = excluded.nome,
      requires_text = excluded.requires_text,
      requires_os = excluded.requires_os,
      ativo = excluded.ativo,
      aplica_em = excluded.aplica_em,
      plano_contas_id = excluded.plano_contas_id,
      favorito = excluded.favorito,
      ordem = excluded.ordem,
      visivel_import_nfe = excluded.visivel_import_nfe,
      updated_at = now(),
      deleted_at = null;
  end loop;

  -- Cria ou valida as regras. A regra EST_MATERIA_PRIMA e deliberadamente
  -- alterada de EST_LOG para PRODUCAO conforme a decisao do responsavel:
  -- mesmo entrando primeiro em estoque, o material atende ao processo.
  for v_definicao in
    select *
    from (
      values
        ('EST_MATERIA_PRIMA'::text, 'PRODUCAO'::text),
        ('LOCACAO_VEICULOS', 'FROTA'),
        ('OPEX_ALUGUEL_APOIO_CAMPO', 'CAMPO'),
        ('ALIM_EQUIPE_CAMPO', 'CAMPO'),
        ('SERV_FRETE', 'EST_LOG'),
        ('MANUTENCAO_VEICULOS', 'FROTA'),
        ('BENEF_SAUDE_OCUPACIONAL', 'PESSOAS'),
        ('BENEF_SEGURO_VIDA', 'PESSOAS'),
        ('ESCRITORIO', 'ADM_FIN'),
        ('CONSUMO_ESTRUTURA', 'ESTRUTURA'),
        ('CONSUMO_PRODUCAO', 'PRODUCAO'),
        ('CONSUMO_FERRAMENTAS', 'PRODUCAO'),
        ('MANUTENCAO_PRODUCAO', 'PRODUCAO'),
        ('MULTA_VEICULO', 'FROTA'),
        ('SERV_COLETA_RESIDUOS', 'ESTRUTURA'),
        ('TREINAMENTO_PESSOAS', 'PESSOAS'),
        ('TREINAMENTO_PRODUCAO', 'PRODUCAO'),
        ('VIAGEM_PASSAGEM_AEREA', 'CAMPO'),
        ('SERV_MONITORAMENTO_PATRIMONIAL', 'ESTRUTURA')
    ) as regras(motivo_codigo, centro_codigo)
  loop
    select mc.id, mc.plano_contas_id
      into strict v_motivo_id, v_plano_id
    from f.motivo_compra mc
    join f.plano_contas pc
      on pc.tenant_id = mc.tenant_id
     and pc.id = mc.plano_contas_id
     and pc.tipo = 'ANALITICA'
     and pc.ativo
     and pc.deleted_at is null
    where mc.tenant_id = v_tenant_id
      and mc.codigo = v_definicao.motivo_codigo
      and mc.ativo
      and mc.deleted_at is null;

    select cc.id
      into strict v_centro_id
    from f.centro_custo cc
    where cc.tenant_id = v_tenant_id
      and cc.empresa_id = v_empresa_id
      and cc.codigo = v_definicao.centro_codigo
      and cc.ativo
      and cc.deleted_at is null;

    select rr.id
      into v_regra_id
    from f.regra_rateio rr
    where rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_id
      and rr.ativo
      and rr.deleted_at is null
    limit 1;

    if v_regra_id is null
       or not exists (
         select 1
         from f.regra_rateio_item rri
         where rri.tenant_id = v_tenant_id
           and rri.regra_rateio_id = v_regra_id
           and rri.plano_contas_id = v_plano_id
           and rri.centro_custo_id = v_centro_id
           and abs(rri.percentual - 100.0000) <= 0.0001
           and rri.deleted_at is null
           and not exists (
             select 1
             from f.regra_rateio_item outro
             where outro.tenant_id = rri.tenant_id
               and outro.regra_rateio_id = rri.regra_rateio_id
               and outro.id <> rri.id
               and outro.deleted_at is null
           )
       )
    then
      v_regra_resultado := f.salvar_regra_rateio(
        v_tenant_id,
        v_empresa_id,
        v_regra_id,
        v_motivo_id,
        true,
        jsonb_build_array(jsonb_build_object(
          'plano_contas_id', v_plano_id,
          'centro_custo_id', v_centro_id,
          'percentual', 100.0000
        ))
      );
      v_regra_id := (v_regra_resultado ->> 'id')::uuid;
    end if;
  end loop;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  for v_caso in
    select *
    from (
      values
        (
          '0c19f468-dcd0-49d8-8837-c2e6eca94162'::uuid,
          623::integer,
          2000.00::numeric,
          'TREINAMENTO MAQUINA'::text,
          null::text,
          'SERV_TERCEIROS'::text,
          'DESP_SERV_TERCEIROS'::text,
          'TREINAMENTO_PRODUCAO'::text,
          'Treinamento de maquina para o processo produtivo.'::text
        ),
        (
          '5909dee7-4943-4e9e-a60a-0ab8cfb1eaf9',
          448,
          1650.00,
          'ALUGUEL CASA TIJUCAS',
          null,
          'OPEX_ALUGUEL',
          'DESP_ALUGUEL',
          'OPEX_ALUGUEL_APOIO_CAMPO',
          'Casa de apoio para funcionarios em servicos de campo em Tijucas.'
        ),
        (
          '826043a5-60b4-4ec0-a8a6-2ac8546ff160',
          3,
          1610.83,
          null,
          '377524',
          'EST_MATERIA_PRIMA',
          'EST_MAT_PRIMA',
          'EST_MATERIA_PRIMA',
          'Materia-prima para processo produtivo, com entrada inicial em estoque.'
        ),
        (
          '3eb30ab5-f1be-4d39-973b-f721d22fa4eb',
          465,
          1580.56,
          'LOCAÇÃO',
          null,
          'SERV_LOCACAO',
          'DESP_LOCACAO',
          'LOCACAO_VEICULOS',
          'Locacao de veiculo da frota.'
        ),
        (
          '769be575-9b74-456e-a490-f07bdb489629',
          430,
          1502.52,
          'REEMBOLSO DIOGO',
          null,
          'REEMBOLSO',
          'DESP_GERAL',
          'VIAGEM_PASSAGEM_AEREA',
          'Passagem aerea para executar servico no cliente.'
        ),
        (
          '1fd8479d-2bf9-4c84-a4e3-ba6cfcd315f8',
          3,
          1366.44,
          null,
          '377878',
          'EST_MATERIA_PRIMA',
          'EST_MAT_PRIMA',
          'EST_MATERIA_PRIMA',
          'Materia-prima para processo produtivo, com entrada inicial em estoque.'
        ),
        (
          '6e53619b-cbff-449e-97cd-c933606e76fb',
          42,
          1190.00,
          'REFEIÇÕES',
          null,
          'ALIM_FUNC',
          'DESP_VIAGEM',
          'ALIM_EQUIPE_CAMPO',
          'Alimentacao de equipe em servicos de campo.'
        ),
        (
          '67fe6d22-603a-4f60-b0e9-fec9106c9440',
          465,
          1100.97,
          'LOCAÇÃO',
          null,
          'SERV_LOCACAO',
          'DESP_LOCACAO',
          'LOCACAO_VEICULOS',
          'Locacao de veiculo da frota.'
        ),
        (
          'b3214a9e-2d83-4692-8205-9c8607267e92',
          465,
          983.19,
          'LOCAÇÃO',
          null,
          'SERV_LOCACAO',
          'DESP_LOCACAO',
          'LOCACAO_VEICULOS',
          'Locacao de veiculo da frota.'
        ),
        (
          '13988a81-0595-49a8-b407-61cea6ce33ff',
          416,
          806.34,
          null,
          '232384',
          'ESTOQUE',
          '4.01',
          'EST_MATERIA_PRIMA',
          'Materia-prima para processo produtivo, com entrada inicial em estoque.'
        ),
        (
          'cc51aa4b-348e-4c6b-96a5-98358beadc2d',
          538,
          800.00,
          'ASSISTENCIA TECNICA',
          null,
          'SERV_TERCEIROS',
          'DESP_SERV_TERCEIROS',
          'MANUTENCAO_PRODUCAO',
          'Manutencao da maquina de corte a laser da empresa.'
        ),
        (
          '6f1e3d9c-160f-4cba-8cfe-be447a28d3dc',
          267,
          700.00,
          'MATERIAIS',
          null,
          'OUTROS',
          'DESP_GERAL',
          'CONSUMO_PRODUCAO',
          'Gases para solda MIG utilizados na producao.'
        ),
        (
          '38f28b21-5ce6-414d-a69e-05e12ed60931',
          125,
          600.00,
          'MANUTENÇÃO FROTA',
          null,
          'SERV_MANUTENCAO',
          'DESP_MANUTENCAO',
          'MANUTENCAO_VEICULOS',
          'Manutencao de veiculo da frota.'
        ),
        (
          '5718577b-cd9e-4c8d-8cb0-c5f3c06c70f5',
          465,
          573.23,
          'LOCAÇÃO',
          null,
          'SERV_LOCACAO',
          'DESP_LOCACAO',
          'LOCACAO_VEICULOS',
          'Locacao de veiculo da frota.'
        ),
        (
          'e332a472-9471-4285-bf56-1d4862f86701',
          572,
          538.00,
          null,
          '63459',
          'CONSUMO',
          'CONSUMO_GERAL',
          'ESCRITORIO',
          'Papel A4 para uso administrativo.'
        ),
        (
          '2e5a3668-3b99-4a46-9e97-a5ebb1d3f5a8',
          541,
          516.00,
          null,
          '90953',
          'CONSUMO_GERAL',
          'CONSUMO_GERAL',
          'CONSUMO_PRODUCAO',
          'Oleo industrial utilizado no processo produtivo.'
        ),
        (
          'e32de6d5-1481-47aa-a3a2-a7a0f56ef81f',
          398,
          495.00,
          'DIARIA REGIONAL',
          null,
          'ALIM_VIAG',
          'DESP_VIAGEM',
          'ALIM_EQUIPE_CAMPO',
          'Diaria de funcionario em servico de campo.'
        ),
        (
          '121ccba8-c7ea-4ee1-b52b-1d775df526f7',
          38,
          460.65,
          null,
          '382187',
          'CONSUMO',
          'CONSUMO_GERAL',
          'CONSUMO_FERRAMENTAS',
          'Brocas e machos utilizados pela producao.'
        ),
        (
          'ae33b357-32e2-4bb0-8ca0-48081a92c10b',
          573,
          400.00,
          'CURSO LARISSA E DEYVISON',
          null,
          'SERV_CONSULTORIA',
          'DESP_CONSULTORIA',
          'TREINAMENTO_PESSOAS',
          'Curso de capacitacao de funcionarios.'
        ),
        (
          '841ab81d-f454-45a8-a780-44b215724f36',
          391,
          382.83,
          null,
          '77034',
          'CONSUMO',
          'CONSUMO_GERAL',
          'MANUTENCAO_PRODUCAO',
          'Peca de manutencao da maquina de solda laser.'
        ),
        (
          '5e718f49-9032-4a9a-abe3-db3d167555f5',
          326,
          380.35,
          null,
          '3931',
          'CONSUMO_GERAL',
          'CONSUMO_GERAL',
          'CONSUMO_ESTRUTURA',
          'Cafe, higiene e limpeza para a estrutura da empresa.'
        ),
        (
          'd5923f1c-0e70-48d0-b37f-f47ce362f958',
          276,
          335.33,
          'FRETE',
          null,
          'SERV_FRETE',
          'DESP_FRETE',
          'SERV_FRETE',
          'Frete geral sem vinculo registrado com OS.'
        ),
        (
          'f61d007b-a6d6-4846-9afc-d91fe25cf7b8',
          131,
          328.13,
          null,
          '4441278',
          'EST_MATERIA_PRIMA',
          'EST_MAT_PRIMA',
          'EST_MATERIA_PRIMA',
          'Materia-prima para processo produtivo, com entrada inicial em estoque.'
        ),
        (
          '692d94bd-7e6f-4f72-bc6b-63e9faed07b8',
          442,
          319.90,
          null,
          '3094543',
          'CONSUMO_GERAL',
          'CONSUMO_GERAL',
          'CONSUMO_FERRAMENTAS',
          'Alicate amperimetro utilizado pela producao.'
        ),
        (
          '6fdb33be-2985-4156-b029-1a26d7c91efd',
          576,
          300.00,
          'EXAMES OCUPACIONAIS',
          null,
          'SERV_CONSULTORIA',
          'DESP_CONSULTORIA',
          'BENEF_SAUDE_OCUPACIONAL',
          'Exames periodicos, ASO e saude ocupacional.'
        ),
        (
          '1bc725ac-370c-45f7-891f-36a18aa82a7c',
          668,
          266.72,
          null,
          '59821',
          'CONSUMO',
          'CONSUMO_GERAL',
          'CONSUMO_PRODUCAO',
          'Abracadeiras utilizadas no processo produtivo.'
        ),
        (
          '5ca80cb7-c049-4327-8c22-4d4033971156',
          373,
          250.00,
          'SERVIÇO DE SEGURANÇA',
          null,
          'SERV_TERCEIROS',
          'DESP_SERV_TERCEIROS',
          'SERV_MONITORAMENTO_PATRIMONIAL',
          'Monitoramento mensal da empresa, cameras e alarme.'
        ),
        (
          '0aea578c-8074-4c3d-b54f-589c0b538ef5',
          279,
          241.00,
          null,
          '35822',
          'OS',
          '4.05',
          'CONSUMO_PRODUCAO',
          'Thinner utilizado no processo produtivo, sem vinculo com OS.'
        ),
        (
          'ef5d9eab-4738-4601-a091-1f9526eb024b',
          40,
          240.00,
          'REFEIÇOES',
          null,
          'ALIM_FUNC',
          'DESP_VIAGEM',
          'ALIM_EQUIPE_CAMPO',
          'Alimentacao de equipe em servicos de campo.'
        ),
        (
          'db0be744-f478-429f-922b-70b3af4ae286',
          132,
          234.11,
          null,
          '14290',
          'CONSUMO',
          'CONSUMO_GERAL',
          'CONSUMO_PRODUCAO',
          'Filme stretch utilizado pelo processo produtivo.'
        ),
        (
          'aa846941-8d47-4275-a2be-06f303a4c368',
          474,
          230.00,
          'NFS DE MANUTENÇÃO',
          null,
          'OPEX_MANUTENCAO',
          'DESP_MANUTENCAO',
          'MANUTENCAO_VEICULOS',
          'Manutencao de veiculo da frota.'
        ),
        (
          '0bf57150-ec5f-40e0-8893-532211fc968a',
          276,
          206.43,
          'FRETE',
          null,
          'SERV_FRETE',
          'DESP_FRETE',
          'SERV_FRETE',
          'Frete geral sem vinculo registrado com OS.'
        ),
        (
          '1caf7175-45df-47d8-a34d-506394c582b5',
          334,
          178.10,
          'SEGURO DE VIDA',
          null,
          'OPEX_SEGURO',
          'DESP_SEGURO',
          'BENEF_SEGURO_VIDA',
          'Seguro de vida de funcionarios.'
        ),
        (
          'd9968abf-6858-4876-9295-7dd2c65923be',
          682,
          159.95,
          null,
          '4187',
          'CONSUMO',
          'CONSUMO_GERAL',
          'CONSUMO_PRODUCAO',
          'Filamento 3D utilizado pela producao e engenharia.'
        ),
        (
          'ee8b2779-6114-452f-8731-a925f7d78201',
          4,
          157.71,
          null,
          '709524',
          'CONSUMO_GERAL',
          'CONSUMO_GERAL',
          'CONSUMO_FERRAMENTAS',
          'Ferramentas utilizadas pela producao.'
        ),
        (
          '0a2d2592-7459-4936-9316-ce02d011edf5',
          622,
          156.19,
          'MULTA FRANK NO LOGAN',
          null,
          'ND_MULTAS',
          'ND_MULTAS',
          'MULTA_VEICULO',
          'Multa nao dedutivel de veiculo da frota.'
        ),
        (
          'aadf7746-bfea-4323-9342-42dd5d15be0a',
          511,
          126.00,
          'REFEIÇOES',
          null,
          'ALIM_FUNC',
          'DESP_VIAGEM',
          'ALIM_EQUIPE_CAMPO',
          'Alimentacao de equipe em servicos de campo.'
        ),
        (
          'b72fca7a-aa6d-459e-a02c-6820ce533a86',
          4,
          118.23,
          null,
          '707538',
          'CONSUMO',
          'CONSUMO_GERAL',
          'CONSUMO_FERRAMENTAS',
          'Ferramentas utilizadas pela producao.'
        ),
        (
          'b6c6974b-c6f9-4b8d-9e57-d1ddb739ab89',
          299,
          110.76,
          'COLETA DE LIXO',
          null,
          'SERV_TERCEIROS',
          'DESP_SERV_TERCEIROS',
          'SERV_COLETA_RESIDUOS',
          'Coleta mensal de residuos da estrutura da empresa.'
        ),
        (
          '13253eef-fe1a-4d65-a5ef-5482fb6b9eb9',
          683,
          102.72,
          null,
          '149681',
          'CONSUMO',
          'CONSUMO_GERAL',
          'CONSUMO_PRODUCAO',
          'Filamento 3D utilizado pela producao e engenharia.'
        ),
        (
          '821002de-ae50-475b-9259-270637a33710',
          125,
          100.00,
          'MANUTENÇÃO',
          null,
          'SERV_MANUTENCAO',
          'DESP_MANUTENCAO',
          'MANUTENCAO_VEICULOS',
          'Manutencao de veiculo da frota.'
        ),
        (
          'bcd3fcaa-1395-4bc0-8b91-0d22e3a5c778',
          375,
          99.00,
          'FRETE',
          null,
          'SERV_FRETE',
          'DESP_FRETE',
          'SERV_FRETE',
          'Frete geral sem vinculo registrado com OS.'
        ),
        (
          'f6e92448-dca4-47a4-b673-b8a818dbb7fb',
          422,
          70.00,
          null,
          '36155',
          'OUTROS',
          'DESP_GERAL',
          'MANUTENCAO_PRODUCAO',
          'Conjunto de reparo para ferramenta da producao.'
        ),
        (
          'e093b689-7ad9-4b08-8800-041ec625ee4d',
          666,
          54.90,
          null,
          '57355',
          'CONSUMO_GERAL',
          'CONSUMO_GERAL',
          'CONSUMO_ESTRUTURA',
          'Copos descartaveis para a estrutura da empresa.'
        ),
        (
          'ec891036-773e-4544-bfbc-3b305fabddef',
          680,
          28.99,
          null,
          '1829',
          'CONSUMO',
          'CONSUMO_GERAL',
          'CONSUMO_ESTRUTURA',
          'Utensilios para a estrutura da empresa.'
        ),
        (
          'b128db0f-1b87-41ca-bb6a-1be5f98cccc1',
          258,
          23.70,
          null,
          '121880',
          'CONSUMO_GERAL',
          'CONSUMO_GERAL',
          'CONSUMO_ESTRUTURA',
          'Pulverizador para limpeza da estrutura da empresa.'
        )
    ) as casos(
      titulo_id,
      fornecedor_id,
      valor_total,
      descricao,
      documento,
      motivo_anterior_codigo,
      plano_anterior_codigo,
      motivo_destino_codigo,
      justificativa
    )
  loop
    select t.*
      into strict v_titulo
    from f.titulo t
    where t.id = v_caso.titulo_id
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.tipo = 'AP'
      and t.status <> 'CANCELADO'
      and t.deleted_at is null
      and t.fornecedor_id = v_caso.fornecedor_id
      and t.valor_total = v_caso.valor_total
      and coalesce(t.competencia_date, t.emissao_date) =
        '2026-07-01'::date
      and (
        v_caso.descricao is null
        or upper(btrim(t.descricao)) = v_caso.descricao
      )
      and not f.titulo_eh_legado_implantacao(
        t.tenant_id,
        t.empresa_id,
        t.id
      )
    for update;

    select mc.codigo
      into strict v_motivo_efetivo_codigo
    from f.motivo_compra mc
    where mc.tenant_id = v_tenant_id
      and mc.id = coalesce(
        (
          select ta.motivo_compra_id
          from f.titulo_aprovacao ta
          where ta.tenant_id = v_tenant_id
            and ta.titulo_id = v_caso.titulo_id
            and ta.deleted_at is null
          order by ta.aprovado_em desc, ta.id desc
          limit 1
        ),
        v_titulo.motivo_compra_id
      )
      and mc.ativo
      and mc.deleted_at is null;

    if v_motivo_efetivo_codigo is distinct from
       v_caso.motivo_anterior_codigo
    then
      raise exception
        'Motivo original do titulo % divergiu: esperado %, encontrado %.',
        v_caso.titulo_id,
        v_caso.motivo_anterior_codigo,
        v_motivo_efetivo_codigo;
    end if;

    select count(*)::integer
      into v_rateio_count
    from f.titulo_rateio tr
    join f.plano_contas pc
      on pc.tenant_id = tr.tenant_id
     and pc.id = tr.plano_contas_id
     and pc.codigo = v_caso.plano_anterior_codigo
     and pc.deleted_at is null
    where tr.tenant_id = v_tenant_id
      and tr.titulo_id = v_caso.titulo_id
      and tr.centro_custo_id is null
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = v_caso.valor_total
      and tr.deleted_at is null;

    if v_rateio_count <> 1 then
      raise exception
        'Rateio original do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    v_documento_fiscal_id := null;
    v_nf_entrada_id := null;

    if v_caso.documento is not null then
      select df.id, df.source_nf_entrada_id
        into strict v_documento_fiscal_id, v_nf_entrada_id
      from f.documento_fiscal df
      join public.nf_entrada nf
        on nf.id = df.source_nf_entrada_id
       and nf.tenant_id = df.tenant_id
       and nf.empresa_id = df.empresa_id
       and nf.numero = v_caso.documento
       and nf.fornecedor_id = v_caso.fornecedor_id
       and nf.valor_total = v_caso.valor_total
       and nf.deleted_at is null
      where df.id = v_titulo.documento_fiscal_id
        and df.tenant_id = v_tenant_id
        and df.empresa_id = v_empresa_id
        and df.numero = v_caso.documento
        and df.deleted_at is null;
    end if;

    select mc.id, mc.plano_contas_id
      into strict v_motivo_id, v_plano_id
    from f.motivo_compra mc
    join f.plano_contas pc
      on pc.tenant_id = mc.tenant_id
     and pc.id = mc.plano_contas_id
     and pc.tipo = 'ANALITICA'
     and pc.ativo
     and pc.deleted_at is null
    where mc.tenant_id = v_tenant_id
      and mc.codigo = v_caso.motivo_destino_codigo
      and mc.ativo
      and mc.deleted_at is null;

    select rri.centro_custo_id
      into strict v_centro_id
    from f.regra_rateio rr
    join f.regra_rateio_item rri
      on rri.tenant_id = rr.tenant_id
     and rri.regra_rateio_id = rr.id
     and rri.plano_contas_id = v_plano_id
     and abs(rri.percentual - 100.0000) <= 0.0001
     and rri.deleted_at is null
    where rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_id
      and rr.ativo
      and rr.deleted_at is null;

    update f.titulo t
    set
      motivo_compra_id = v_motivo_id,
      updated_at = now()
    where t.id = v_caso.titulo_id
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id;

    update f.titulo_aprovacao ta
    set
      motivo_compra_id = v_motivo_id,
      change_reason = v_caso.justificativa,
      updated_at = now()
    where ta.tenant_id = v_tenant_id
      and ta.titulo_id = v_caso.titulo_id
      and ta.deleted_at is null;

    if v_nf_entrada_id is not null then
      update public.nf_entrada nf
      set
        motivo_compra_id = v_motivo_id,
        updated_at = now()
      where nf.id = v_nf_entrada_id
        and nf.tenant_id = v_tenant_id
        and nf.empresa_id = v_empresa_id;

      update public.consumo_itens ci
      set
        motivo_compra_id = v_motivo_id,
        centro_custo = (
          select cc.codigo
          from f.centro_custo cc
          where cc.id = v_centro_id
            and cc.tenant_id = v_tenant_id
            and cc.empresa_id = v_empresa_id
        ),
        local_uso = case (
          select cc.codigo
          from f.centro_custo cc
          where cc.id = v_centro_id
            and cc.tenant_id = v_tenant_id
            and cc.empresa_id = v_empresa_id
        )
          when 'PRODUCAO' then 'PRODUCAO'
          when 'ESTRUTURA' then 'SEDE'
          when 'ADM_FIN' then 'ADMINISTRATIVO'
          when 'EST_LOG' then 'ESTOQUE E LOGISTICA'
          when 'FROTA' then 'FROTA'
          when 'PESSOAS' then 'PESSOAS'
          when 'CAMPO' then 'SERVICOS EM CAMPO'
          else null
        end,
        observacoes = v_caso.justificativa,
        updated_at = now()
      where ci.tenant_id = v_tenant_id
        and ci.empresa_id = v_empresa_id
        and ci.nf_entrada_id = v_nf_entrada_id
        and ci.deleted_at is null;
    end if;

    -- A troca do motivo pode aplicar automaticamente a regra de rateio pelo
    -- trigger. Nesses casos a pendencia ja esta resolvida e a RPC, corretamente,
    -- rejeita uma segunda correcao do mesmo titulo.
    if exists (
      select 1
      from f.detectar_inconsistencias_financeiras(
        v_tenant_id,
        v_empresa_id,
        null,
        null
      ) inconsistencia
      where inconsistencia.titulo_id = v_caso.titulo_id
    ) then
      v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
        v_tenant_id,
        v_empresa_id,
        array[v_caso.titulo_id]::uuid[],
        v_plano_id,
        v_centro_id,
        v_caso.justificativa,
        false
      );

      if coalesce(
        (v_correcao_resultado ->> 'corrigidos')::integer,
        0
      ) <> 1 then
        raise exception
          'Correcao do titulo % retornou resultado inesperado: %.',
          v_caso.titulo_id,
          v_correcao_resultado;
      end if;
    end if;

    if not exists (
      select 1
      from f.titulo t
      join f.titulo_rateio tr
        on tr.tenant_id = t.tenant_id
       and tr.titulo_id = t.id
       and tr.deleted_at is null
      where t.id = v_caso.titulo_id
        and t.tenant_id = v_tenant_id
        and t.empresa_id = v_empresa_id
        and t.motivo_compra_id = v_motivo_id
        and t.valor_total = v_caso.valor_total
        and tr.plano_contas_id = v_plano_id
        and tr.centro_custo_id = v_centro_id
        and tr.os_id is null
        and abs(tr.percentual - 100.0000) <= 0.0001
        and tr.valor = v_caso.valor_total
        and not exists (
          select 1
          from f.titulo_rateio outro
          where outro.tenant_id = tr.tenant_id
            and outro.titulo_id = tr.titulo_id
            and outro.id <> tr.id
            and outro.deleted_at is null
        )
    ) then
      raise exception
        'Classificacao final do titulo % nao passou na validacao.',
        v_caso.titulo_id;
    end if;

    v_corrigidos := v_corrigidos + 1;
    v_valor_corrigido := v_valor_corrigido + v_caso.valor_total;
  end loop;

  if v_corrigidos <> 46 or v_valor_corrigido <> 24074.78 then
    raise exception
      'Resumo da correcao divergiu: titulos %, valor %.',
      v_corrigidos,
      v_valor_corrigido;
  end if;

  -- Padroes seguros para fornecedores de finalidade unica. Fornecedores que
  -- tambem possuem multas, locacoes ou materiais de naturezas diferentes nao
  -- recebem motivo padrao.
  update public.fornecedores fornecedor
  set
    motivo_compra_padrao_id = case fornecedor.id
      when 448 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'OPEX_ALUGUEL_APOIO_CAMPO'
          and mc.deleted_at is null
      )
      when 42 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'ALIM_EQUIPE_CAMPO'
          and mc.deleted_at is null
      )
      when 40 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'ALIM_EQUIPE_CAMPO'
          and mc.deleted_at is null
      )
      when 511 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'ALIM_EQUIPE_CAMPO'
          and mc.deleted_at is null
      )
      when 576 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'BENEF_SAUDE_OCUPACIONAL'
          and mc.deleted_at is null
      )
      when 334 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'BENEF_SEGURO_VIDA'
          and mc.deleted_at is null
      )
      when 572 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'ESCRITORIO'
          and mc.deleted_at is null
      )
      when 299 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'SERV_COLETA_RESIDUOS'
          and mc.deleted_at is null
      )
      when 573 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'TREINAMENTO_PESSOAS'
          and mc.deleted_at is null
      )
      when 623 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'TREINAMENTO_PRODUCAO'
          and mc.deleted_at is null
      )
      when 538 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'MANUTENCAO_PRODUCAO'
          and mc.deleted_at is null
      )
      when 373 then (
        select mc.id from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.codigo = 'SERV_MONITORAMENTO_PATRIMONIAL'
          and mc.deleted_at is null
      )
      else fornecedor.motivo_compra_padrao_id
    end,
    atualizado_em = now()
  where fornecedor.tenant_id = v_tenant_id
    and fornecedor.empresa_id = v_empresa_id
    and fornecedor.id in (
      448,
      42,
      40,
      511,
      576,
      334,
      572,
      299,
      573,
      623,
      538,
      373
    );

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload
  )
  values (
    v_tenant_id,
    v_empresa_id,
    'INCONSISTENCIAS_JULHO_APROVADAS_CLASSIFICADAS',
    'f.plano_contas',
    v_plano_treinamento_id,
    jsonb_build_object(
      'titulosCorrigidos', v_corrigidos,
      'valorCorrigido', v_valor_corrigido,
      'competencia', '2026-07-01',
      'planoTreinamentoCriado', 'DESP_TREINAMENTO',
      'regraMateriaPrimaCentro', 'PRODUCAO',
      'tituloCartaoPendente',
        '91cc6dde-7721-4ea9-84cc-c5bc34c3259f',
      'valorCartaoPendente', 7048.28,
      'motivoPendenciaCartao',
        'Aguardando valores ou percentuais entre ADM_FIN e COMERCIAL.',
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouDocumentos', true,
      'preservouOs', true
    )
  );
end;
$corrigir_inconsistencias_julho_aprovadas$;
