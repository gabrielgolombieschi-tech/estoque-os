-- A origem da compra e a origem da venda sao dois fatos, e estavam num campo so.
--
-- Diagnostico do Gabriel em 11/09/2026: "quando eu compro e a origem e 1, quem esta me
-- vendendo e que esta com origem 1 — ela teria que ter uma origem de compra e uma de
-- saida, que nao e a mesma". Exato, e e a raiz de tudo que apareceu esta semana.
--
-- A origem e declarada do ponto de vista de quem emite. O fornecedor dizendo "1 -
-- importacao direta" esta dizendo que ELE importou. Copiar esse 1 para o nosso cadastro
-- faz a nossa nota de saida afirmar uma importacao que nao houve — e, pior, e da origem
-- que sai a equiparacao a industrial, entao o erro virou IPI cobrado indevidamente na
-- revenda (NF-e 2/50).
--
-- Levantamento que sustenta a conversao, conferido contra o xml_raw das 2.103 notas de
-- entrada:
--
--   603 itens com origem 1 no cadastro
--   602 tem nota de fornecedor declarando <orig>1</orig>   -> viram origem 2
--     0 entraram SEM nota de fornecedor
--     1 e a CHAVE SEG ACIONAM. CORDA (item 2308), sem nota de compra
--
-- O zero e a prova: importacao direta entra por DI, sem NF-e de fornecedor. Nenhum
-- desses 602 foi importado pela Segau. E o unico item sem nota de compra e justamente a
-- chave, que o Gabriel confirmou ter importado e que ja foi para origem 1 com
-- equiparacao na 20260911130000. A regra se valida na propria excecao.
--
-- Por fornecedor (os maiores): Siemens Brasil 161, Pafer 104, WEG Drives 46, Wago 40,
-- Phoenix Contact 37, Proauto 35.
--
-- A REGRA. So o par 1/2 (e 6/7) muda de dono, porque so ele fala de quem nacionalizou.
-- As demais origens sao caracteristica da mercadoria e atravessam sem mudanca:
--
--   fornecedor 1 -> nossa 2      fornecedor 6 -> nossa 7
--   fornecedor 2 -> nossa 2      fornecedor 7 -> nossa 7
--   fornecedor 0, 3, 4, 5, 8 -> igual
--   sem nota de fornecedor (DI) -> 1, declarado a mao, com a equiparacao junto
--
-- Os FAB-* ficam de fora desta regra: se sao industrializados com componente importado,
-- a origem deles e 3, 5 ou 8 conforme o Conteudo de Importacao, que exige calculo por
-- produto. Segue pendente com a contabilidade.

alter table public.fiscal_itens
  add column if not exists origem_entrada smallint;

comment on column public.fiscal_itens.origem_entrada is
  'Origem que o FORNECEDOR declarou na nota de entrada. Guardada para auditoria e para redderivar a origem de saida se a regra mudar; nao vai para a NF-e. A origem que sai na nossa nota e a coluna origem.';

comment on column public.fiscal_itens.origem is
  'Origem declarada na NOSSA nota de saida, do nosso ponto de vista. Derivada de origem_entrada: o 1 do fornecedor (ele importou) vira 2 para nos (adquirida no mercado interno); 6 vira 7; o resto atravessa igual. Origem 1 aqui significa que a Segau importou, e so nesse caso ha equiparacao a industrial.';

do $converter$
declare
  v_convertidos integer;
  v_preservados integer;
begin
  -- 1. O que esta hoje em `origem` e, para todo mundo que veio de XML, o que o
  --    fornecedor declarou. Vira o lastro antes de derivar.
  update public.fiscal_itens
     set origem_entrada = origem
   where origem_entrada is null
     and origem is not null;

  -- 2. A conversao, so para quem tem nota de compra — quem nao tem entrou por DI e a
  --    origem 1 e legitima.
  with com_nota as (
    select distinct nei.item_id
    from public.nf_entrada_itens nei
    where nei.item_id is not null
  )
  update public.fiscal_itens fi
     set origem = case fi.origem when 1 then 2 when 6 then 7 else fi.origem end,
         atualizado_em = now()
    from com_nota
   where com_nota.item_id = fi.item_id
     and fi.origem in (1, 6)
     and fi.equiparado_industrial is not true;
  get diagnostics v_convertidos = row_count;

  select count(*) into v_preservados
  from public.fiscal_itens
  where origem in (1, 6);

  raise notice '% itens convertidos para a origem de saida; % seguem com origem 1 ou 6 (importacao propria).',
    v_convertidos, v_preservados;

  -- A trava do montador recusa origem 1 sem equiparacao. Depois da conversao, os que
  -- sobrarem em 1 ou 6 tem de estar todos marcados — senao a emissao deles para.
  if exists (
    select 1 from public.fiscal_itens
    where origem in (1, 6) and equiparado_industrial is not true
  ) then
    raise exception 'Sobrou item com origem de importacao propria sem a equiparacao declarada; a emissao recusaria.';
  end if;
end
$converter$;
