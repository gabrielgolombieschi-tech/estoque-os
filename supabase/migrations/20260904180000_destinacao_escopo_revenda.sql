-- Recorte do campo de destinacao: esta e a nota de REVENDA.
--
-- A tela de NF-e da OV emite uma unica natureza: VENDA MERCADORIA ADQ. REC. DE
-- TERCEIROS, CFOP 5102. Isso ja era garantido por
-- f.fn_solicitacao_nfe_salvar_conferencia_2026, que recusa qualquer outra
-- natureza e qualquer CFOP diferente de 5102. Industrializacao sai pelas OS, e
-- simples remessa, conserto e afins terao lugar proprio.
--
-- A destinacao continua sendo campo necessario aqui, e nao decoracao: ela e o
-- que o CLIENTE faz com a mercadoria, nao o que a SEGAU faz. Nas NF-e reais de
-- agosto/2026, o mesmo NCM 8537.10.20 em CFOP 5102 aparece 8 vezes a 12% e 23
-- vezes a 17% — ou seja, venda de mercadoria de terceiros para destinatario
-- final acontece, e e ela que exige os 17%.
--
-- O que sai daqui e 'INDUSTRIALIZACAO': o termo descrevia o cliente
-- industrializando, mas colide com a industrializacao da SEGAU (que e OS) e era
-- redundante com 'INSUMO', que diz a mesma coisa sem ambiguidade. Nenhuma
-- solicitacao usou o valor, entao apertar o check e seguro.

alter table f.solicitacao_faturamento
  drop constraint if exists solicitacao_faturamento_destinacao_mercadoria_check;

alter table f.solicitacao_faturamento
  add constraint solicitacao_faturamento_destinacao_mercadoria_check
  check (destinacao_mercadoria is null or destinacao_mercadoria in (
    -- 12%: destinatario contribuinte (Lei 10.297/96, art. 19, III, "n")
    'REVENDA', 'INSUMO', 'MANUTENCAO', 'CONSIGNADO',
    -- 17%: destinatario final (RICMS/SC, art. 26, I)
    'USO_CONSUMO', 'ATIVO_IMOBILIZADO'
  ));

update f.perfil_operacao
set destinacoes_mercadoria = array['REVENDA', 'INSUMO', 'MANUTENCAO', 'CONSIGNADO']::text[]
where codigo in (
  'SEG-VENDA-TERCEIROS-SC-5102-O0-CST00',
  'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00'
);

comment on column f.solicitacao_faturamento.destinacao_mercadoria is
  'O que o CLIENTE faz com a mercadoria, declarado na OC dele. Decide a aliquota interna de ICMS (12% contribuinte x 17% destinatario final) e vai para as informacoes complementares da NF-e. Nao confundir com a natureza da operacao da empresa, que nesta tela e sempre venda de mercadoria de terceiros.';
