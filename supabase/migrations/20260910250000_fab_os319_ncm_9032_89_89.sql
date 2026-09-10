-- FAB-OS319-01 sai do NCM de controlador de veiculo e passa a pagar o IPI que deve.
--
-- O "SISTEMA DE CONTROLE DE FLUXO" da OS 319 estava cadastrado no NCM 9032.89.29, que
-- na TIPI e "controladores eletronicos de veiculos automoveis - outros". Nao e o que o
-- equipamento e: e um kit de sensor/fluxometro para controle de fluxo em processo
-- industrial. Junto vinha o CST de IPI 51 (saida tributada a aliquota zero), e ai a nota
-- saia sem IPI nenhum — foi assim nas 2/4 e 2/5, as duas canceladas.
--
-- O NCM certo, decidido pelo Gabriel em 10/09/2026, e o 9032.89.89: "instrumentos e
-- aparelhos para regulacao ou controle automaticos - outros". Continua na mesma posicao
-- 9032.89, so que no residual em vez do subitem de veiculos. A aliquota nao muda por
-- causa disso: todo 9032.89 e 9,75% na TIPI — o unico zero da posicao e o 9032.81.00,
-- dos hidraulicos e pneumaticos. Ou seja, o IPI sempre foi devido; o CST 51 e que estava
-- errado, e o NCM de veiculos escondia isso.
--
-- Com CST 50 e 9,75%, f.fn_os_nfe_conferir_homologacao passa a destacar o IPI e a trava
-- da TIPI (mesma funcao, "NCM tributado saindo sem IPI") para de acusar a linha.

do $corrigir$
declare
  v_item_id integer;
  v_aliquota numeric;
  v_fi public.fiscal_itens%rowtype;
begin
  select i.id into v_item_id from public.itens i where i.codigo_interno = 'FAB-OS319-01';
  if not found then
    raise notice 'FAB-OS319-01 nao existe neste banco; nada a fazer.';
    return;
  end if;

  -- A aliquota nao e digitada: vem da TIPI, para o cadastro nao poder discordar dela.
  select t.aliquota into v_aliquota from f.tipi_ncm t where t.ncm = '90328989';
  if not found then
    raise exception 'NCM 90328989 nao esta em f.tipi_ncm; carregue a TIPI antes.';
  end if;
  if v_aliquota is null or v_aliquota <= 0 then
    raise exception 'NCM 90328989 esta em f.tipi_ncm com aliquota %; esperado tributado.', v_aliquota;
  end if;

  update public.fiscal_itens fi
     set ncm = '90328989',
         cst_ipi = '50',
         aliq_ipi = v_aliquota
   where fi.item_id = v_item_id;
  if not found then
    raise exception 'FAB-OS319-01 (item %) nao tem linha em public.fiscal_itens.', v_item_id;
  end if;

  select * into v_fi from public.fiscal_itens where item_id = v_item_id;
  if v_fi.ncm <> '90328989' or v_fi.cst_ipi <> '50' or v_fi.aliq_ipi is distinct from v_aliquota then
    raise exception 'O cadastro fiscal do FAB-OS319-01 nao ficou como esperado: NCM %, CST %, aliquota %.',
      v_fi.ncm, v_fi.cst_ipi, v_fi.aliq_ipi;
  end if;
  raise notice 'FAB-OS319-01 agora e NCM 90328989, CST de IPI 50 a %%%.', v_aliquota;
end
$corrigir$;
