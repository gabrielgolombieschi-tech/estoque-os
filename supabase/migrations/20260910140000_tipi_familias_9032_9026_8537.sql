-- TIPI: familias 90.32, 9026.10 e 85.37 inteiras, lidas da planilha oficial da RFB.
--
-- Motivo: a NF-e 2/37 (homologacao, OS 319, 10/09/2026) saiu com vIPI 0,00 sobre
-- R$ 18.166,99 porque o FAB-OS319-01 esta com CST 51 sem aliquota. A trava criada em
-- 20260909220000 nao disparou por um detalhe: o NCM dele, 9032.89.29, nao estava em
-- f.tipi_ncm — e o que nao esta cadastrado nao trava nada. E o mesmo erro que a
-- contabilidade apontou na 2/33 em 09/09, na mesma familia 9032.89.
--
-- Fonte, conferida linha a linha em 10/09/2026: planilha oficial
-- https://www.gov.br/receitafederal/pt-br/acesso-a-informacao/legislacao/documentos-e-arquivos/tipi.xlsx
-- ("TIPI 2022", Decreto 11.158/2022, atualizada ate o ADE RFB nº 1, de 30/01/2026).
-- Baixada duas vezes, de forma independente, com o mesmo MD5 06f611ee3e2d741d89776931e1073890.
--
-- Entram as familias inteiras, e nao so o NCM do dia, porque o valor da tabela esta em
-- cobrir o vizinho antes de ele virar nota. Note que a familia NAO e homogenea:
--   9032.81.00 (hidraulicos ou pneumaticos)      = 0
--   9026.10.21 / .29 (medida de NIVEL)           = 0
--   8537.20.10 / .90 (tensao superior a 1.000 V) = 0
-- e por isso esses tambem entram: sem eles, a trava passaria a exigir IPI onde a TIPI
-- nao manda, se o item for reclassificado para um deles.
--
-- Efeito imediato e desejado: a conferencia passa a RECUSAR o FAB-OS319-01 enquanto ele
-- estiver com CST 51 sem aliquota, porque 9032.89.29 e tributado a 9,75%. A correcao do
-- cadastro nao entra aqui de proposito — o NCM atual e "controlador eletronico do tipo
-- utilizado em veiculos automoveis" (item 9032.89.2, irmaos: ABS, suspensao, transmissao,
-- ignicao, injecao), o que nao descreve um quadro de comando montado pela Segau. A
-- classificacao correta e decisao do Gabriel com a contabilidade.

insert into f.tipi_ncm (ncm, aliquota, descricao, fonte) values
  -- 90.32 Instrumentos e aparelhos para regulacao ou controle, automaticos
  ('90321010', 9.7500, 'Termostatos - com dispositivo de partida/parada', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90321090', 9.7500, 'Termostatos - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90322000', 9.7500, 'Manostatos (pressostatos)', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328100', 0.0000, 'Outros instrumentos e aparelhos - hidraulicos ou pneumaticos', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328911', 9.7500, 'Reguladores de voltagem - eletronicos', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328919', 9.7500, 'Reguladores de voltagem - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328921', 9.7500, 'Controladores eletronicos de veiculos automoveis - ABS', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328922', 9.7500, 'Controladores eletronicos de veiculos automoveis - suspensao', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328923', 9.7500, 'Controladores eletronicos de veiculos automoveis - transmissao', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328924', 9.7500, 'Controladores eletronicos de veiculos automoveis - ignicao', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328925', 9.7500, 'Controladores eletronicos de veiculos automoveis - injecao', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328929', 9.7500, 'Controladores eletronicos de veiculos automoveis - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328930', 9.7500, 'Equipamentos digitais para controle de veiculos ferroviarios', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328981', 9.7500, 'Regulacao/controle de grandezas nao eletricas - de pressao', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328982', 9.7500, 'Regulacao/controle de grandezas nao eletricas - de temperatura', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328983', 9.7500, 'Regulacao/controle de grandezas nao eletricas - de umidade', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90328984', 9.7500, 'Regulacao/controle de grandezas nao eletricas - velocidade de motores por variacao de frequencia', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90329010', 9.7500, 'Partes e acessorios de circuitos impressos com componentes', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90329091', 9.7500, 'Partes e acessorios - de manostatos', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90329099', 9.7500, 'Partes e acessorios - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  -- 9026.10 Instrumentos para medida ou controle da vazao ou do nivel de liquidos
  ('90261011', 9.7500, 'Vazao - medidores-transmissores eletronicos por inducao eletromagnetica', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90261019', 9.7500, 'Vazao - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90261021', 0.0000, 'Nivel - de metais, mediante correntes parasitas', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('90261029', 0.0000, 'Nivel - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  -- 85.37 Quadros, paineis e comandos
  ('85371011', 9.7500, 'Ate 1.000 V - comando numerico computadorizado com microprocessador', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('85371030', 9.7500, 'Ate 1.000 V - controladores de demanda de energia eletrica', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('85372010', 0.0000, 'Superior a 1.000 V - blindados para tensao superior a 72,5 kV', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('85372090', 0.0000, 'Superior a 1.000 V - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB')
on conflict (ncm) do nothing;

-- 8537.10.20 e "Controladores programaveis"; comando numerico computadorizado e o
-- item 8537.10.1. A descricao gravada na 20260909250000 trocou os dois.
update f.tipi_ncm
   set descricao = 'Ate 1.000 V - controladores programaveis',
       fonte = 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'
 where ncm = '85371020';

do $conferir$
declare
  v_aliq numeric;
  v_bloqueados text;
begin
  select aliquota into v_aliq from f.tipi_ncm where ncm = '90328929';
  if v_aliq is distinct from 9.7500 then
    raise exception '90328929 ficou com aliquota %; esperado 9,7500.', v_aliq;
  end if;

  select string_agg(i.codigo_interno || ' (' || fi.ncm || ', CST ' || coalesce(fi.cst_ipi, '-') || ')', ', ' order by i.codigo_interno)
    into v_bloqueados
  from public.fiscal_itens fi
  join public.itens i on i.id = fi.item_id
  join f.tipi_ncm t on t.ncm = fi.ncm
  where i.fabricado is true
    and i.ativo is true
    and t.aliquota > 0
    and (coalesce(fi.cst_ipi, '') not in ('00', '49', '50', '99') or coalesce(fi.aliq_ipi, 0) <= 0);

  if v_bloqueados is null then
    raise notice 'Nenhum produto fabricado fica travado pela TIPI.';
  else
    raise notice 'A partir de agora a conferencia recusa, ate o cadastro fiscal ser corrigido: %', v_bloqueados;
  end if;
end
$conferir$;
