/**
 * Rotulos em linguagem simples para codigos fiscais (decisao do Gabriel, 18/09/2026, valida para o
 * ERP todo): codigo fiscal nunca aparece sozinho. Toda opcao tem texto simples, um exemplo curto e o
 * codigo pequeno ao lado; onde da, a pessoa escolhe a situacao e o sistema deriva o codigo.
 *
 * Este e o unico lugar dos textos. Quando existe perfil fiscal para a opcao,
 * f.perfil_operacao.rotulo_usuario / legenda_usuario prevalecem (rotuloDoPerfil).
 * Nada aqui muda regra fiscal, calculo ou payload: sao textos de tela.
 */

export type OpcaoFiscal = { codigo: string; rotulo: string; exemplo?: string };

/** "Texto simples (codigo)" para <option>, onde nao da para estilizar o codigo. */
export function textoOpcao(o: OpcaoFiscal) {
  return `${o.rotulo} (${o.codigo})`;
}

/** Rotulo/legenda do perfil quando preenchidos; senao os padroes daqui. */
export function rotuloDoPerfil(
  perfil: { rotulo_usuario?: string | null; legenda_usuario?: string | null } | null | undefined,
  padrao: { rotulo: string; exemplo?: string },
) {
  return {
    rotulo: perfil?.rotulo_usuario?.trim() || padrao.rotulo,
    exemplo: perfil?.legenda_usuario?.trim() || padrao.exemplo || "",
  };
}

// ---------------------------------------------------------------- CFOP das operacoes fora do faturamento

/** Remessa com controle de retorno (aba REMESSA_OUTRAS): o banco (f.fn_remessa_criar) so aceita estes CFOPs por finalidade. */
export const CFOPS_REMESSA_POR_FINALIDADE: Record<string, OpcaoFiscal[]> = {
  INDUSTRIALIZACAO: [
    { codigo: "5901", rotulo: "Mandamos material para alguém industrializar por nós, dentro de SC", exemplo: "Ex.: chapas para dobrar ou pintar em terceiro; volta como produto." },
  ],
  CONSERTO: [
    { codigo: "5915", rotulo: "Mandamos algo nosso para conserto, dentro de SC", exemplo: "Ex.: equipamento ou peça que vai reparar e volta." },
    { codigo: "6915", rotulo: "Mandamos algo nosso para conserto, fora de SC", exemplo: "Ex.: sensor enviado ao fabricante em outro estado." },
  ],
  SIMPLES: [
    { codigo: "5949", rotulo: "Outra remessa sem venda, dentro de SC", exemplo: "Ex.: demonstração, teste, comodato." },
    { codigo: "6949", rotulo: "Outra remessa sem venda, fora de SC", exemplo: "Ex.: demonstração ou teste em outro estado." },
  ],
  CONTA_ORDEM: [
    { codigo: "6923", rotulo: "Entrega por conta e ordem (venda à ordem), fora de SC", exemplo: "Ex.: entregamos para o cliente do nosso cliente." },
  ],
};

export const FINALIDADES_REMESSA: OpcaoFiscal[] = [
  { codigo: "INDUSTRIALIZACAO", rotulo: "Industrialização em terceiro", exemplo: "Material nosso que outra empresa transforma." },
  { codigo: "CONSERTO", rotulo: "Conserto ou reparo", exemplo: "Algo nosso que vai consertar e volta." },
  { codigo: "SIMPLES", rotulo: "Remessa simples (sem venda)", exemplo: "Demonstração, teste, comodato." },
  { codigo: "CONTA_ORDEM", rotulo: "Venda à ordem (entrega ao cliente do cliente)", exemplo: "Faturamos para um e entregamos a outro." },
];

/** Estorno espelhado (aba ESTORNO): o banco (f.fn_estorno_criar) so aceita estes cinco. */
export const CFOPS_ESTORNO: OpcaoFiscal[] = [
  { codigo: "1201", rotulo: "Estorno de venda de produto nosso (fabricado), dentro de SC", exemplo: "A nota original era 5101." },
  { codigo: "1202", rotulo: "Estorno de venda de mercadoria revendida, dentro de SC", exemplo: "A nota original era 5102." },
  { codigo: "2202", rotulo: "Estorno de venda de mercadoria revendida, fora de SC", exemplo: "A nota original era 6102." },
  { codigo: "1915", rotulo: "Estorno de remessa para conserto, dentro de SC", exemplo: "A nota original era 5915." },
  { codigo: "1102", rotulo: "Entrada de compra para revenda (estorno por entrada), dentro de SC", exemplo: "Uso raro; combine com o responsável fiscal." },
];

// ---------------------------------------------------------------- Faturar OS

/**
 * Destinacao declarada pelo cliente. Aliquota e IPI na base seguem a regra do montador
 * (supabase/functions/_shared/fiscal/icms-sc-destinacao.ts): so ha 12% e IPI fora da base quando o
 * destinatario e contribuinte E a mercadoria segue em operacao tributada; do contrario 17% com o IPI
 * dentro da base. A tela so mostra o efeito; quem aplica e a conferencia.
 */
export type DestinacaoOpcao = OpcaoFiscal & { segueEmOperacaoTributada: boolean };
export const DESTINACOES_CLIENTE: DestinacaoOpcao[] = [
  { codigo: "REVENDA", rotulo: "Vai revender", exemplo: "Ex.: distribuidor que coloca o painel no estoque para vender.", segueEmOperacaoTributada: true },
  { codigo: "INSUMO", rotulo: "Vai usar como peça/insumo na produção dele", exemplo: "Ex.: painel que entra na máquina que ele fabrica.", segueEmOperacaoTributada: true },
  { codigo: "CONSIGNADO", rotulo: "Recebe em consignação", exemplo: "Ex.: fica com ele para vender e acerta depois.", segueEmOperacaoTributada: true },
  { codigo: "MANUTENCAO", rotulo: "Vai usar na manutenção", exemplo: "Ex.: peça de reposição para a máquina dele.", segueEmOperacaoTributada: false },
  { codigo: "USO_CONSUMO", rotulo: "Uso e consumo", exemplo: "Ex.: material que ele gasta no dia a dia, sem revender.", segueEmOperacaoTributada: false },
  { codigo: "ATIVO_IMOBILIZADO", rotulo: "Vai virar equipamento/patrimônio dele (ativo)", exemplo: "Ex.: painel instalado na fábrica dele, imobilizado.", segueEmOperacaoTributada: false },
];

/** Efeito que a conferencia vai aplicar, em uma linha. Mesma regra de efeitosDaDestinacao() no montador. */
export function efeitoDestinacao(codigo: string, destinatarioContribuinte: boolean) {
  const d = DESTINACOES_CLIENTE.find((x) => x.codigo === codigo);
  if (!d) return null;
  const subsequente = destinatarioContribuinte && d.segueEmOperacaoTributada;
  return subsequente
    ? { aliquota: 12, ipiNaBase: false, texto: "ICMS 12%, IPI fora da base" }
    : { aliquota: 17, ipiNaBase: true, texto: "ICMS 17%, IPI dentro da base" };
}

/** Origem da mercadoria (orig do item). Codigos 4, 6 e 7 sao casos raros e ficam no fim. */
export const ORIGENS_MERCADORIA: OpcaoFiscal[] = [
  { codigo: "0", rotulo: "Nacional", exemplo: "Ex.: fabricado no Brasil, sem componente importado relevante." },
  { codigo: "1", rotulo: "Importado por nós (direto ou por conta e ordem)", exemplo: "Ex.: veio do exterior em nosso nome, com DI ou DIR." },
  { codigo: "2", rotulo: "Importado, comprado de distribuidor no Brasil", exemplo: "Ex.: peça importada que compramos de um revendedor nacional." },
  { codigo: "5", rotulo: "Fabricação nossa com componentes importados (CI até 40%)", exemplo: "Conforme a ficha de conteúdo de importação (FCI)." },
  { codigo: "3", rotulo: "Fabricação nossa com componentes importados (CI de 40% a 70%)", exemplo: "Conforme a FCI." },
  { codigo: "8", rotulo: "Fabricação nossa com componentes importados (CI acima de 70%)", exemplo: "Conforme a FCI." },
  { codigo: "4", rotulo: "Nacional com processo produtivo básico (PPB)", exemplo: "Caso raro: informática/eletrônicos com PPB." },
  { codigo: "6", rotulo: "Importado por nós, sem similar nacional (lista CAMEX)", exemplo: "Caso raro." },
  { codigo: "7", rotulo: "Importado, comprado no Brasil, sem similar nacional (lista CAMEX)", exemplo: "Caso raro." },
];

/** Modalidade do frete (modFrete). Cada tela filtra os codigos que aceita. */
export const MODALIDADES_FRETE: OpcaoFiscal[] = [
  { codigo: "0", rotulo: "Segau paga o frete (CIF)", exemplo: "Por conta do emitente." },
  { codigo: "1", rotulo: "O destinatário paga o frete (FOB)", exemplo: "Por conta de quem recebe." },
  { codigo: "2", rotulo: "Outra empresa paga o frete", exemplo: "Por conta de terceiros." },
  { codigo: "3", rotulo: "Segau leva com veículo próprio", exemplo: "Transporte próprio, por conta do remetente." },
  { codigo: "4", rotulo: "O destinatário busca com veículo próprio", exemplo: "Transporte próprio, por conta do destinatário." },
  { codigo: "9", rotulo: "Sem frete", exemplo: "Não há transporte na nota." },
];
export function modalidadesFrete(codigos: string[]) {
  return codigos.map((c) => MODALIDADES_FRETE.find((m) => m.codigo === c)).filter((m): m is OpcaoFiscal => Boolean(m));
}

/** Forma de pagamento da NF-e / NFS-e (tPag). */
export const FORMAS_PAGAMENTO_NFE: OpcaoFiscal[] = [
  { codigo: "15", rotulo: "Boleto bancário" },
  { codigo: "17", rotulo: "PIX" },
  { codigo: "18", rotulo: "Transferência bancária" },
  { codigo: "01", rotulo: "Dinheiro" },
  { codigo: "03", rotulo: "Cartão de crédito" },
  { codigo: "04", rotulo: "Cartão de débito" },
  { codigo: "05", rotulo: "Crédito em loja" },
  { codigo: "99", rotulo: "Outros (descrever)" },
];
export function formasPagamentoNfe(codigos: string[]) {
  return codigos.map((c) => FORMAS_PAGAMENTO_NFE.find((f) => f.codigo === c)).filter((f): f is OpcaoFiscal => Boolean(f));
}

/** Forma de pagamento do contas a pagar (texto do ERP, nao e tPag). */
export const FORMAS_PAGAMENTO_AP: OpcaoFiscal[] = [
  { codigo: "BOLETO", rotulo: "Boleto" },
  { codigo: "PIX", rotulo: "PIX" },
  { codigo: "TRANSFERENCIA", rotulo: "Transferência" },
  { codigo: "CARTAO", rotulo: "Cartão" },
  { codigo: "DINHEIRO", rotulo: "Dinheiro" },
  { codigo: "OUTROS", rotulo: "Outros" },
];
