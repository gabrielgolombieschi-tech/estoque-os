-- Cadastro fiscal do FAB-OS288-01: IPI tributado e NCM da familia certa.
--
-- Contabilidade em 09/09/2026, sobre a NF-e 2/33 (homologacao, OS 288):
--
--   IPI  - 9032.89 e tributado a 9,75% na TIPI. O item estava com cst_ipi 51 e sem
--          aliquota, e a nota saiu com vIPI 0,00 (R$ 877,50 a menos). Passa a CST 50
--          com 9,7500.
--   NCM  - "SISTEMA DE CONTROLE DE NIVEL PARA ENCHENTE" mede nivel, que e grandeza nao
--          eletrica: a familia 9032.89.8 e literalmente isso, e o .90 e residual. Vai
--          de 90328990 para 90328989. A aliquota de IPI e a mesma nos dois.
--
-- Fica so neste item, por decisao explicita: o FAB-OS282-01 (8479.81.90) tem TIPI zero
-- e CST 51 e o correto para ele — nao tocar.
--
-- Em aberto, sem alterar nada aqui: se o que sai for quadro de comando, o NCM muda para
-- 8537.10 e o Gabriel avisa. E o CEST nao entra: 9032.89.90 so aparece no Convenio
-- 142/2018 nos anexos de autopecas e porta a porta, e a clausula setima, §1º, exige NCM
-- e descricao cumulativamente.

update public.fiscal_itens fi
   set ncm = '90328989',
       cst_ipi = '50',
       aliq_ipi = 9.7500,
       atualizado_em = now()
  from public.itens i
 where i.id = fi.item_id
   and i.codigo_interno = 'FAB-OS288-01'
   and fi.ncm = '90328990';

do $conferir$
declare
  v record;
begin
  select fi.ncm, fi.cst_ipi, fi.aliq_ipi into v
  from public.fiscal_itens fi
  join public.itens i on i.id = fi.item_id
  where i.codigo_interno = 'FAB-OS288-01';

  if not found then
    raise notice 'FAB-OS288-01 nao existe neste banco; nada a fazer.';
    return;
  end if;
  if v.ncm <> '90328989' or v.cst_ipi <> '50' or v.aliq_ipi <> 9.7500 then
    raise exception 'FAB-OS288-01 ficou com ncm=%, cst_ipi=%, aliq_ipi=%; esperado 90328989 / 50 / 9.7500.',
      v.ncm, v.cst_ipi, v.aliq_ipi;
  end if;
  raise notice 'FAB-OS288-01: NCM 90328989, CST IPI 50, aliquota 9,75%%.';
end
$conferir$;
