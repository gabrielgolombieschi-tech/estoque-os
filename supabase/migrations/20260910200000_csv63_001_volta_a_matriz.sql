-- CSV63-001 volta para BLOQUEADO: e linha de matriz, nao perfil operacional.
--
-- Erro meu na 20260910190000. Liberei o CSV63-001 achando que era o perfil do
-- beneficio de automacao pronto para uso — os numeros dele batem com a NF-e 3607
-- (CST 20, 17% com base reduzida em 29,412%, cBenef SC820006, origem 2). Só que a
-- familia CSV63-* e o catalogo das 63 combinacoes do estudo, nao perfil que o
-- resolvedor consegue escolher: natureza_operacao e 'MATRIZ_CSV63_001', e
-- ambito_destino, ufs_destino, indicador_ie_destinatario e destinacoes_mercadoria
-- estao todos nulos. O filtro de f.fn_solicitacao_nfe_resolver_perfis exige os
-- quatro, entao esse registro nunca seria candidato a linha nenhuma — liberar so
-- desalinhava o catalogo e sujava a tela de perfis.
--
-- A coluna ncms_elegiveis e o criterio de NCM no resolvedor, da mesma migration,
-- ficam: sao a peca que faltava para um perfil de automacao de verdade conviver
-- com o generico sem cair em AMBIGUO. O perfil operacional em si ainda precisa
-- ser criado, com a decisao do Gabriel e do contador.

update f.perfil_operacao
   set faixa_automacao = 'BLOQUEADO',
       justificativa_faixa = 'Linha da matriz das 63 combinacoes (estudo), nao perfil operacional: natureza MATRIZ_CSV63_001, sem ambito, UF, indicador de IE e destinacao. Serve de referencia para o perfil de automacao (Anexo 2, Art. 7o, VII) que ainda sera criado.'
 where codigo = 'CSV63-001';

do $conferir$
declare
  v_faixa text;
begin
  select faixa_automacao into v_faixa from f.perfil_operacao where codigo = 'CSV63-001';
  if not found then
    raise notice 'CSV63-001 nao existe neste banco; nada a fazer.';
    return;
  end if;
  if v_faixa <> 'BLOQUEADO' then
    raise exception 'CSV63-001 ficou em %; esperado BLOQUEADO.', v_faixa;
  end if;
  raise notice 'CSV63-001 de volta a BLOQUEADO, como as outras linhas da matriz.';
end
$conferir$;
