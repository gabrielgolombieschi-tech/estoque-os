-- FAB-OS288-01 volta para a posicao 8537.10: e quadro de comando, nao instrumento.
--
-- Gabriel em 09/09/2026, revendo a troca feita horas antes (20260909230000). O pedido
-- de compra descreve "PAINEL ELETRICO CONFORME PROJETO / IHM E CLP PAINEL DE ENCHENTE",
-- 1 pc, com entrega no almoxarifado MRO: e quadro munido de dois ou mais aparelhos das
-- posicoes 8535/8536, o que o coloca na 8537.10 — nao no capitulo 90, que e de
-- instrumentos de medicao. O 90328989 tinha sido escolhido por leitura da descricao
-- interna ("controle de nivel"), antes do pedido do cliente entrar na conversa.
--
-- A troca nao mexe em imposto: 8537.10.20 tem os mesmos 9,75% de IPI da TIPI, entao a
-- trava criada em 20260909220000 continua valendo igual.
--
-- Entram tambem 85371020 e 85371090 na tabela, para a familia ficar coberta.

insert into f.tipi_ncm (ncm, aliquota, descricao, fonte) values
  ('85371020', 9.7500, 'Quadros, paineis e comandos para tensao nao superior a 1000 V - comando numerico', 'Contabilidade da Segau, 09/09/2026'),
  ('85371090', 9.7500, 'Quadros, paineis e comandos para tensao nao superior a 1000 V - outros', 'Contabilidade da Segau, 09/09/2026')
on conflict (ncm) do nothing;

update public.fiscal_itens fi
   set ncm = '85371020',
       atualizado_em = now()
  from public.itens i
 where i.id = fi.item_id
   and i.codigo_interno = 'FAB-OS288-01'
   and fi.ncm = '90328989';

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
  if v.ncm <> '85371020' or v.cst_ipi <> '50' or v.aliq_ipi <> 9.7500 then
    raise exception 'FAB-OS288-01 ficou com ncm=%, cst_ipi=%, aliq_ipi=%; esperado 85371020 / 50 / 9.7500.',
      v.ncm, v.cst_ipi, v.aliq_ipi;
  end if;
  raise notice 'FAB-OS288-01: NCM 85371020, CST IPI 50, aliquota 9,75%%.';
end
$conferir$;
