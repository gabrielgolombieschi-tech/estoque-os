"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "next/navigation";
import { supabaseBrowser } from "../../../lib/supabase/client";
import { parseDecimalBR, formatDecimalBR } from "../../../lib/decimal";
import MaoObraCard from "../../components/os/MaoObraCard";
import RelatorioHHSection from "./components/RelatorioHHSection";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { getOsDetailAccess } from "@/lib/auth/osAccess";
import { calcHhPedidoTotal, getHorasTrabalhadasEfetivas, getValorTotalEfetivo } from "@/lib/hh/hhLancamentosCalc";
import ResponsavelAprovacaoSelect from "@/components/os/ResponsavelAprovacaoSelect";
import { createOrcamento } from "@/lib/comercial/orcamentos.service";
import { ensureConfig } from "@/src/services/configOrcamento";
import { getOsStatusLabel, isOsStatusLocked, normalizeOsStatusFluxo } from "@/lib/os/statusFluxo";

type Cliente = { id: number; nome: string; ativo: boolean; habilita_hh?: boolean | null };
type ClienteUnidade = { id: number; cliente_id: number; nome: string; codigo: string | null };

type OsClienteRow = {
  cliente_id: number | null;
  cliente_nome: string | null;
};

type OS = {
  id: number;
  numero_os: string;
  cliente_nome: string;
  cliente_id?: number | null;
  unidade_id?: number | null;
  status: "aberta" | "em_andamento" | "concluida" | "cancelada";
  status_fluxo?: string | null;
  faturado_em?: string | null;
  faturada_presumida_legado?: boolean | null;
  garantia_motivo?: string | null;
  descricao_servico: string | null;
  valor_total: number;
  data_abertura: string;
  orcado: number | null;
  tipo_pedido?: string | null;
  tem_gestao?: boolean | null;
  pedido_compra?: string | null;
  vendedor?: string | null;
  usa_relatorio_hh?: boolean | null;
  responsavel_aprovacao_id?: string | null;
  is_fiado?: boolean | null;
  orcamento_gerado_id?: string | null;
};

type OsItemRow = {
  id: number;
  item_id: number;
  quantidade: number;
  valor_unitario: number;
  valor_total: number;
  baixa_estoque: boolean;
  quantidade_baixada?: number | null;
  desconto_percentual?: number | null;
  desconto_valor?: number | null;
  criado_em?: string | null;
  registrado_em?: string | null;
  registrado_por_nome?: string | null;
  itens: { nome: string; codigo_interno: string; tipo: string } | null;
};

type ItemPick = {
  id: number;
  codigo_interno: string;
  nome: string;
  fabricante?: string | null;
  tipo: string;
  finalidade?: string | null;
  preco_unitario: number;
  aliquota_ipi?: number | null;
  controla_estoque?: boolean | null;
};

type ItemLookupRow = ItemPick & {
  fornecedor: string | null;
  ultima_entrada: string | null;
  estoque_atual?: number | null;
};

type ItemLookupBaseRow = ItemPick & {
  fornecedor: string | null;
  ultima_entrada: string | null;
  estoque_atual: number | null;
};

type AddMode = "item" | "despesa";

type HhLancamentoCalcRow = {
  entrada_1: string | null;
  saida_1: string | null;
  entrada_2: string | null;
  saida_2: string | null;
  hora_entrada: string | null;
  hora_saida: string | null;
  horas_trabalhadas: number | null;
  tem_extra_50?: boolean | null;
  horas_extra_50?: number | null;
  tem_extra_100?: boolean | null;
  horas_extra_100?: number | null;
  percentual_aplicado?: number | null;
  valor_hora: number | null;
  valor_total: number | null;
};

type HhPrintRow = HhLancamentoCalcRow & {
  id: number | string;
  data: string | null;
  colaborador_id: string | null;
  observacao: string | null;
  hh_especialidade_id?: string | null;
  hh_servico_id?: string | null;
  colaborador_nome?: string | null;
  especialidade_descricao?: string | null;
};

type ApontamentoPrintBaseRow = {
  id: string;
  os_id: number;
  colaborador_id: string;
  data: string;
  horas: number | null;
  tipo_hora_id: string | null;
  fator_aplicado?: number | null;
  descricao: string | null;
  status: string;
  criado_em: string;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
};

type ApontamentoPrintRow = ApontamentoPrintBaseRow & {
  colaborador_nome: string;
  tipo_hora_codigo: string | null;
  tipo_hora_descricao: string | null;
  fator: number;
  valor_hora: number;
  custo_lancamento: number;
};

type SortValue = string | number | null;

type SortKey = "id" | "codigo" | "descricao" | "fornecedor" | "ultima" | "preco" | "estoque";
type SortDir = "asc" | "desc";

type LookupSearchTerm = {
  raw: string;
  normalized: string;
};

const statusBadge: Record<string, string> = {
  aberta: "bg-blue-500/15 text-blue-300 border-blue-500/30",
  em_andamento: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  concluida: "bg-sky-500/15 text-sky-300 border-sky-500/30",
  faturada: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  em_andamento_garantia: "bg-violet-500/15 text-violet-300 border-violet-500/30",
  concluida_garantia: "bg-violet-500/15 text-violet-300 border-violet-500/30",
  cancelada: "bg-red-500/15 text-red-300 border-red-500/30",
};

const DESPESA_ITEM_ID_MIN = 1;
const DESPESA_ITEM_ID_MAX = 99;
const LOOKUP_FETCH_LIMIT = 150;
const LOOKUP_RESULT_LIMIT = 50;

function normalizeLookupText(value: string | null | undefined): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function parseLookupTerms(value: string | null | undefined): LookupSearchTerm[] {
  return String(value ?? "")
    .trim()
    .split(/\s+/)
    .map((raw) => raw.trim())
    .filter(Boolean)
    .map((raw) => ({
      raw,
      normalized: normalizeLookupText(raw),
    }))
    .filter((term) => term.normalized.length > 0);
}

function pickLookupSeedTerm(terms: LookupSearchTerm[]): string {
  return [...terms].sort((a, b) => b.normalized.length - a.normalized.length)[0]?.raw ?? "";
}

function matchesLookupTerms(values: Array<string | null | undefined>, terms: LookupSearchTerm[]): boolean {
  if (terms.length === 0) return true;
  const haystack = values.map((value) => normalizeLookupText(value)).join(" ");
  return terms.every((term) => haystack.includes(term.normalized));
}

function isDespesaItemId(itemId: number | null | undefined) {
  const value = Number(itemId ?? NaN);
  return Number.isFinite(value) && value >= DESPESA_ITEM_ID_MIN && value <= DESPESA_ITEM_ID_MAX;
}

type BaixaStatus = "completa" | "parcial" | "nenhuma";

const BAIXA_EPSILON = 0.0005;

function getQuantidadeBaixada(row: Pick<OsItemRow, "quantidade" | "baixa_estoque" | "quantidade_baixada">) {
  const quantidade = Number(row.quantidade ?? 0);
  const raw = Number(row.quantidade_baixada ?? NaN);

  if (Number.isFinite(raw)) {
    return Math.max(0, Math.min(raw, quantidade));
  }

  return row.baixa_estoque ? Math.max(quantidade, 0) : 0;
}

function getBaixaStatus(row: Pick<OsItemRow, "quantidade" | "baixa_estoque" | "quantidade_baixada">): BaixaStatus {
  const quantidade = Number(row.quantidade ?? 0);
  const baixada = getQuantidadeBaixada(row);

  if (quantidade > 0 && baixada >= quantidade - BAIXA_EPSILON) return "completa";
  if (baixada > BAIXA_EPSILON) return "parcial";
  return "nenhuma";
}

type GestaoTipo = "projeto" | "execucao";
type GestaoArea = "eletrico" | "mecanico" | "seguranca" | "software";

type GestaoItem = {
  id?: number;
  os_id?: number;
  item_tipo: GestaoTipo;
  area: GestaoArea;
  habilitado: boolean;
  responsavel_id: string | null;
  data_prevista: string | null;
  progresso_percent: number;
};

const gestaoDefs: Array<{ item_tipo: GestaoTipo; area: GestaoArea; label: string; grupo: "projetos" | "execucoes" }> =
  [
    { item_tipo: "projeto", area: "eletrico", label: "Projeto Eletrico", grupo: "projetos" },
    { item_tipo: "projeto", area: "mecanico", label: "Projeto Mecanico", grupo: "projetos" },
    { item_tipo: "projeto", area: "seguranca", label: "Projeto Seguranca", grupo: "projetos" },
    { item_tipo: "projeto", area: "software", label: "Projeto Software", grupo: "projetos" },
    { item_tipo: "execucao", area: "eletrico", label: "Execucao Eletrica", grupo: "execucoes" },
    { item_tipo: "execucao", area: "mecanico", label: "Execucao Mecanica", grupo: "execucoes" },
  ];

const gestaoKey = (it: { item_tipo: GestaoTipo; area: GestaoArea }) => `${it.item_tipo}-${it.area}`;
const gestaoOrder = gestaoDefs.map((d) => gestaoKey(d));

function orderGestaoItems(items: GestaoItem[]): GestaoItem[] {
  const map = new Map(items.map((it) => [gestaoKey(it), it]));
  return gestaoOrder.map((key) => map.get(key)).filter(Boolean) as GestaoItem[];
}

function formatHoursBR(value: number | null | undefined) {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0,00";
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatTimeHHMM(value: string | null | undefined): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  if (/^\d{2}:\d{2}/.test(raw)) return raw.slice(0, 5);
  return raw;
}

function formatDateBR(value: string | null | undefined) {
  const raw = String(value ?? "").trim();
  if (!raw) return "-";
  const iso = raw.slice(0, 10);
  if (/^\d{4}-\d{2}-\d{2}$/.test(iso)) {
    const [year, month, day] = iso.split("-");
    return `${day}/${month}/${year}`;
  }
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? raw : date.toLocaleDateString("pt-BR");
}

function formatPeriodoHH(row: HhLancamentoCalcRow) {
  const entrada1 = formatTimeHHMM(row.entrada_1) || formatTimeHHMM(row.hora_entrada);
  const saida1 = formatTimeHHMM(row.saida_1) || formatTimeHHMM(row.hora_saida);
  const entrada2 = formatTimeHHMM(row.entrada_2);
  const saida2 = formatTimeHHMM(row.saida_2);
  const periodos: string[] = [];

  if (entrada1 || saida1) periodos.push(`${entrada1 || "--"}-${saida1 || "--"}`);
  if (entrada2 || saida2) periodos.push(`${entrada2 || "--"}-${saida2 || "--"}`);

  return periodos.length > 0 ? periodos.join(" / ") : "-";
}

function roundMoney(value: number) {
  return Math.round((Number(value) || 0) * 100) / 100;
}

function formatPeriodoApontamento(row: {
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
}) {
  const entrada1 = formatTimeHHMM(row.entrada_1);
  const saida1 = formatTimeHHMM(row.saida_1);
  const entrada2 = formatTimeHHMM(row.entrada_2);
  const saida2 = formatTimeHHMM(row.saida_2);
  const periodos: string[] = [];

  if (entrada1 || saida1) periodos.push(`${entrada1 || "--"}-${saida1 || "--"}`);
  if (entrada2 || saida2) periodos.push(`${entrada2 || "--"}-${saida2 || "--"}`);

  return periodos.length > 0 ? periodos.join(" / ") : "-";
}

export default function OsDetailPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const { tenantId, empresaId } = te;
  const { has } = usePermissions();
  const params = useParams();
  const osId = Number(params.id);

  const fixedTenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
  const fixedEmpresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
  const effectiveTenantId = useMemo(() => tenantId ?? fixedTenantId, [tenantId]);
  const effectiveEmpresaId = useMemo(() => empresaId ?? fixedEmpresaId, [empresaId]);

  const empresaPapel = useMemo(() => {
    const byId = (te.empresas ?? []).find((e) => e.id === effectiveEmpresaId) ?? null;
    if (byId?.papel) return byId.papel;
    if (te.empresa?.id === effectiveEmpresaId) return te.empresa?.papel ?? null;
    return null;
  }, [effectiveEmpresaId, te.empresa, te.empresas]);

  const detailAccess = useMemo(() => getOsDetailAccess(empresaPapel), [empresaPapel]);
  const canReadOs = Boolean(has("os.read"));
  const canWriteOs = Boolean(has("os.write"));
  const canView = canReadOs || detailAccess.canView;
  const readOnly = !canWriteOs;
  const hideCustos = detailAccess.hideCustos;
  const hideTotais = detailAccess.hideTotais;
  const papelNormalizado = String(empresaPapel ?? "").trim().toUpperCase();
  const canConcluirFluxo = ["ADMIN", "DIRETOR", "COORDENACAO"].includes(papelNormalizado);
  const canFaturarFluxo = papelNormalizado === "FINANCEIRO";

  const [os, setOs] = useState<OS | null>(null);
  const [rows, setRows] = useState<OsItemRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showEditItem, setShowEditItem] = useState(false);
  const [editItem, setEditItem] = useState<OsItemRow | null>(null);
  const [editItemQty, setEditItemQty] = useState<string>("1");
  const [editItemVunit, setEditItemVunit] = useState<number>(0);
  const [editItemSaving, setEditItemSaving] = useState(false);
  const [editItemErr, setEditItemErr] = useState<string | null>(null);
  const [baixaEditValues, setBaixaEditValues] = useState<Record<number, string>>({});
  const [baixaSavingId, setBaixaSavingId] = useState<number | null>(null);
  const [printingItens, setPrintingItens] = useState(false);
  const [printingOs, setPrintingOs] = useState(false);
  const [isConcluding, setIsConcluding] = useState(false);
  const [isFaturando, setIsFaturando] = useState(false);
  const [showGestaoModal, setShowGestaoModal] = useState(false);
  const [temGestao, setTemGestao] = useState(false);
  const [gestaoItems, setGestaoItems] = useState<GestaoItem[]>([]);
  const [gestaoLoading, setGestaoLoading] = useState(false);
  const [gestaoSaving, setGestaoSaving] = useState(false);
  const [gestaoErr, setGestaoErr] = useState<string | null>(null);
  const [maoObraExtra, setMaoObraExtra] = useState<number>(0);
  const [hhTotal, setHhTotal] = useState<number>(0);
  const [hhPedido, setHhPedido] = useState<number>(0);
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [clienteUnidades, setClienteUnidades] = useState<ClienteUnidade[]>([]);
  const [clienteHabilitaHH, setClienteHabilitaHH] = useState(false);

  const [showEdit, setShowEdit] = useState(false);
  const [editSaving, setEditSaving] = useState(false);
  const [editErr, setEditErr] = useState<string | null>(null);
  const [clienteId, setClienteId] = useState<number | null>(null);
  const [unidadeId, setUnidadeId] = useState<number | null>(null);
  const [clienteNomeLivre, setClienteNomeLivre] = useState("");
  const [descricao, setDescricao] = useState("");
  const [pedidoCompra, setPedidoCompra] = useState("");
  const [tipoPedido, setTipoPedido] = useState<"servico" | "material">("servico");
  const [vendedor, setVendedor] = useState("");
  const [responsavelAprovacaoId, setResponsavelAprovacaoId] = useState<string | null>(null);
  const [orcadoInput, setOrcadoInput] = useState("");
  const [usaRelatorioHH, setUsaRelatorioHH] = useState(false);

  useEffect(() => {
    if (!clienteId || !effectiveTenantId || !effectiveEmpresaId) {
      return;
    }
    let active = true;
    void (async () => {
      const { data, error } = await applyTenantEmpresa(
        supabase.from("cliente_unidades").select("id,cliente_id,nome,codigo").eq("cliente_id", clienteId).eq("ativo", true).order("nome"),
        effectiveTenantId,
        effectiveEmpresaId
      );
      if (!active) return;
      if (error) { setClienteUnidades([]); setUnidadeId(null); return; }
      const next = (data ?? []) as ClienteUnidade[];
      setClienteUnidades(next);
      setUnidadeId((current) => current && next.some((row) => row.id === current) ? current : null);
    })();
    return () => { active = false; };
  }, [clienteId, effectiveEmpresaId, effectiveTenantId, supabase]);

  // Gerar/atualizar orcamento a partir de OS Fiado
  const [showGerarOrcamento, setShowGerarOrcamento] = useState(false);
  const [gerarOrcamentoLoading, setGerarOrcamentoLoading] = useState(false);
  const [gerarOrcamentoBusy, setGerarOrcamentoBusy] = useState(false);
  const [gerarOrcamentoErr, setGerarOrcamentoErr] = useState<string | null>(null);
  const [gerarOrcamentoResumo, setGerarOrcamentoResumo] = useState<{
    orcamentoId: string;
    itensMateriaisCriados: number;
    gruposMaoObraCriados: number;
    hhValorAdicionado: number;
    cargosSemMapeamento: string[];
  } | null>(null);
  const [margemMateriais, setMargemMateriais] = useState("0");
  const [margemMaoObra, setMargemMaoObra] = useState("0");
  const [vendedoresOrcamento, setVendedoresOrcamento] = useState<Array<{ id: string; nome: string; email: string }>>([]);
  const [vendedorOrcamentoId, setVendedorOrcamentoId] = useState("");
  const [servicoItensOrcamento, setServicoItensOrcamento] = useState<
    Array<{ id: number; nome: string; codigo_interno: string }>
  >([]);
  const [itemServicoHHId, setItemServicoHHId] = useState<number | null>(null);

  const [activeTab, setActiveTab] = useState<"itens" | "hh">("itens");
  const [addMode, setAddMode] = useState<AddMode>("item");

  // adicionar item
  const [q, setQ] = useState("");
  const [searching, setSearching] = useState(false);
  const [found, setFound] = useState<ItemPick[]>([]);
  const [pick, setPick] = useState<ItemPick | null>(null);
  const [qty, setQty] = useState<string>("1");
  const [vunit, setVunit] = useState<number>(0);
  const [estoqueAtual, setEstoqueAtual] = useState<number | null>(null);
  const [baixaDireta, setBaixaDireta] = useState(true);
  const qtyRef = useRef<HTMLInputElement | null>(null);
  const searchRef = useRef<HTMLInputElement | null>(null);
  const [showLookup, setShowLookup] = useState(false);
  const [lookupNome, setLookupNome] = useState("");
  const [lookupFornecedor, setLookupFornecedor] = useState("");
  const [lookupRows, setLookupRows] = useState<ItemLookupRow[]>([]);
  const [lookupBusy, setLookupBusy] = useState(false);
  const [lookupErr, setLookupErr] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("id");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const isDespesaMode = addMode === "despesa";
  const isMateriaPrimaBase = (pick?.finalidade ?? "") === "materia_prima";
  const isMateriaPrima = isDespesaMode || isMateriaPrimaBase;
  const isDespesaPick = isDespesaItemId(pick?.id) || String(pick?.tipo ?? "").toLowerCase() === "despesa";
  const canAddPickedItem = isDespesaMode ? isDespesaPick : isMateriaPrima;
  const addSectionTitle = isDespesaMode ? "Adicionar despesa" : "Adicionar item";
  const addSectionDescription = isDespesaMode
    ? "Selecione despesas cadastradas entre os itens 1 e 99. O preco pode ser ajustado na inclusao."
    : 'Inclusao sem baixa por padrao. Marque "Baixa direta" para baixar no ato quando houver saldo.';
  const addSearchLabel = isDespesaMode ? "Buscar despesa" : "Buscar item";
  const addSearchPlaceholder = isDespesaMode
    ? "ID da despesa (1 a 99). Enter abre localizacao se nao souber."
    : "ID do item (ex: 123). Enter abre localizacao se nao souber.";
  const lookupTitle = isDespesaMode ? "Localizar despesa" : "Localizar item";
  const lookupDescription = isDespesaMode
    ? "Filtre por nome, codigo ou fornecedor para localizar despesas entre os itens 1 e 99."
    : "Filtre por nome, codigo ou fabricante para localizar o ID.";
  const isDespesaRow = useCallback(
    (row: OsItemRow) => isDespesaItemId(row.item_id) || String(row.itens?.tipo ?? "").toLowerCase() === "despesa",
    []
  );

  const statusExibicao = normalizeOsStatusFluxo(os?.status_fluxo, os?.status);
  const locked = readOnly || isOsStatusLocked(statusExibicao);
  const formatMoney = (v: number) =>
    Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  const toNum = (v: unknown) => {
    if (v == null) return 0;
    if (typeof v === "number") return v;
    if (typeof v === "string") return Number(v.replace(",", ".")) || 0;
    return 0;
  };

  const osIsHH = Boolean(os?.usa_relatorio_hh);
  const isFiado = Boolean(os?.is_fiado);
  const hhClientEnabled = clienteHabilitaHH || osIsHH;
  // IMPORTANTE: a OS já carrega usa_relatorio_hh. Para perfis sem acesso a `clientes` (RLS),
  // não bloquear a UI de HH baseada em `habilita_hh` do cliente.
  const hhEnabled = osIsHH;

  async function printOsItens() {
    if (!os) return;
    setErr(null);

    if (rows.length === 0) {
      setErr("Esta OS não tem itens para imprimir.");
      return;
    }

    setPrintingItens(true);

    try {
      const [{ jsPDF }, autoTableMod] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
      const autoTable = autoTableMod.default;

      const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
      const marginX = 40;
      let y = 42;

      doc.setFontSize(14);
      doc.text(`Itens da OS ${os.numero_os ?? os.id}`, marginX, y);
      y += 16;

      doc.setFontSize(10);
      doc.text(`Cliente: ${os.cliente_nome ?? "-"}`, marginX, y);
      y += 14;

      doc.text(`Emissão: ${new Date().toLocaleString("pt-BR")}`, marginX, y);
      y += 10;

      const sorted = [...rows].sort((a, b) => a.id - b.id);
      const body = sorted.map((r) => {
        const codigo = r.itens?.codigo_interno ?? "";
        const nome = r.itens?.nome ?? "";
        const qtd = formatDecimalBR(Number(r.quantidade ?? 0), 3);
        const vUnit = formatMoney(Number(r.valor_unitario ?? 0));
        const total = formatMoney(Number(r.valor_total ?? 0));
        return [String(r.item_id ?? ""), String(codigo), String(nome), String(qtd), String(vUnit), String(total)];
      });

      autoTable(doc, {
        startY: y + 12,
        head: [["Item ID", "Código", "Nome", "Qtd", "V.Unit", "Total"]],
        body,
        styles: { fontSize: 9, cellPadding: 4 },
        headStyles: { fillColor: [30, 41, 59] },
        columnStyles: {
          0: { cellWidth: 56 },
          1: { cellWidth: 70 },
          2: { cellWidth: 240 },
          3: { cellWidth: 50, halign: "right" },
          4: { cellWidth: 60, halign: "right" },
          5: { cellWidth: 60, halign: "right" },
        },
      });

      const totalItens = sorted.reduce((sum, r) => sum + Number(r.valor_total ?? 0), 0);
      const finalY = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY;
      const footerY = typeof finalY === "number" ? finalY + 18 : 760;
      doc.setFontSize(11);
      doc.text(`Total itens: R$ ${formatMoney(totalItens)}`, marginX, footerY);

      doc.autoPrint();
      const url = doc.output("bloburl");
      const w = window.open(url, "_blank");
      if (!w) {
        doc.save(`OS_${os.numero_os ?? os.id}_itens.pdf`);
      }
    } catch (e) {
      console.error(e);
      setErr("Falha ao gerar impressão dos itens.");
    } finally {
      setPrintingItens(false);
    }
  }

  async function loadHhRowsForPrint(): Promise<HhPrintRow[]> {
    const result = await applyTenantEmpresa(
      supabase
        .from("hh_lancamentos")
        .select(
          "id,data,colaborador_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,horas_trabalhadas,percentual_aplicado,tem_extra_50,horas_extra_50,tem_extra_100,horas_extra_100,observacao,valor_hora,valor_total,hh_especialidade_id,hh_servico_id"
        )
        .eq("os_id", osId)
        .order("data", { ascending: true })
        .order("id", { ascending: true }),
      effectiveTenantId,
      effectiveEmpresaId
    );

    if (result.error) throw result.error;

    const baseRows = Array.isArray(result.data) ? (result.data as unknown as HhPrintRow[]) : [];
    if (baseRows.length === 0) return [];

    const colaboradorIds = Array.from(
      new Set(baseRows.map((row) => String(row.colaborador_id ?? "").trim()).filter(Boolean))
    );
    const servicoIds = Array.from(
      new Set(
        baseRows
          .map((row) => {
            const servicoId = String(row.hh_servico_id ?? "").trim();
            if (/^\d+$/.test(servicoId)) return servicoId;
            const especialidadeId = String(row.hh_especialidade_id ?? "").trim();
            return /^\d+$/.test(especialidadeId) ? especialidadeId : "";
          })
          .filter(Boolean)
      )
    );

    const colaboradorMap = new Map<string, string>();
    if (colaboradorIds.length > 0) {
      const colaboradoresResult = await applyTenantEmpresa(
        supabase.from("colaboradores").select("id,nome").in("id", colaboradorIds),
        effectiveTenantId,
        effectiveEmpresaId
      );

      if (colaboradoresResult.error) {
        console.warn("[OS detail] colaboradores print", colaboradoresResult.error);
      } else {
        ((colaboradoresResult.data ?? []) as Array<{ id: string; nome: string }>).forEach((colaborador) => {
          colaboradorMap.set(String(colaborador.id), colaborador.nome);
        });
      }
    }

    const servicoMap = new Map<string, string>();
    if (servicoIds.length > 0) {
      const servicosResult = await applyTenantEmpresa(
        supabase.from("cliente_hh_servicos").select("id,nome").in("id", servicoIds),
        effectiveTenantId,
        effectiveEmpresaId
      );

      if (servicosResult.error) {
        console.warn("[OS detail] servicos HH print", servicosResult.error);
      } else {
        ((servicosResult.data ?? []) as Array<{ id: string; nome: string }>).forEach((servico) => {
          servicoMap.set(String(servico.id), servico.nome);
        });
      }
    }

    return baseRows.map((row) => {
      const servicoId = String(row.hh_servico_id ?? "").trim();
      const especialidadeId = String(row.hh_especialidade_id ?? "").trim();
      const lookupId = /^\d+$/.test(servicoId) ? servicoId : /^\d+$/.test(especialidadeId) ? especialidadeId : "";

      return {
        ...row,
        colaborador_nome: colaboradorMap.get(String(row.colaborador_id ?? "")) ?? "-",
        especialidade_descricao: lookupId ? servicoMap.get(lookupId) ?? "-" : "-",
      };
    });
  }

  async function loadApontamentosRowsForPrint(): Promise<ApontamentoPrintRow[]> {
    const result = await applyTenantEmpresa(
      supabase
        .from("apontamentos_horas")
        .select(
          "id,os_id,colaborador_id,data,horas,tipo_hora_id,fator_aplicado,descricao,status,criado_em,entrada_1:hora_entrada_1,saida_1:hora_saida_1,entrada_2:hora_entrada_2,saida_2:hora_saida_2"
        )
        .eq("os_id", osId)
        .order("data", { ascending: true })
        .order("criado_em", { ascending: true }),
      effectiveTenantId,
      effectiveEmpresaId
    );

    if (result.error) throw result.error;

    const baseRows = Array.isArray(result.data) ? (result.data as unknown as ApontamentoPrintBaseRow[]) : [];
    if (baseRows.length === 0) return [];

    const apontamentoIds = baseRows.map((row) => String(row.id));
    const custosMap = new Map<
      string,
      {
        colaborador_nome: string | null;
        tipo_hora_codigo: string | null;
        tipo_hora_descricao: string | null;
        fator: number | null;
        valor_hora: number | null;
        custo_lancamento: number | null;
      }
    >();

    const custosResult = await supabase
      .from("vw_apontamentos_horas_custo")
      .select(
        "apontamento_id,colaborador_nome,tipo_hora_codigo,tipo_hora_descricao,fator,valor_hora,custo_lancamento"
      )
      .in("apontamento_id", apontamentoIds);

    if (!custosResult.error) {
      (
        (custosResult.data ?? []) as Array<{
          apontamento_id: string;
          colaborador_nome: string | null;
          tipo_hora_codigo: string | null;
          tipo_hora_descricao: string | null;
          fator: number | null;
          valor_hora: number | null;
          custo_lancamento: number | null;
        }>
      ).forEach((row) => {
        custosMap.set(String(row.apontamento_id), row);
      });
    } else {
      console.warn("[OS detail] apontamentos custo print", custosResult.error);
    }

    const missingRows = baseRows.filter((row) => !custosMap.has(String(row.id)));
    if (missingRows.length === 0) {
      return baseRows.map((row) => {
        const custo = custosMap.get(String(row.id));
        return {
          ...row,
          colaborador_nome: String(custo?.colaborador_nome ?? "-").trim() || "-",
          tipo_hora_codigo: custo?.tipo_hora_codigo ?? null,
          tipo_hora_descricao: custo?.tipo_hora_descricao ?? null,
          fator: Number(custo?.fator ?? row.fator_aplicado ?? 1) || 1,
          valor_hora: Number(custo?.valor_hora ?? 0) || 0,
          custo_lancamento: roundMoney(Number(custo?.custo_lancamento ?? 0)),
        };
      });
    }

    const colaboradorIds = Array.from(new Set(baseRows.map((row) => String(row.colaborador_id)).filter(Boolean)));
    const tipoHoraIds = Array.from(new Set(baseRows.map((row) => String(row.tipo_hora_id ?? "")).filter(Boolean)));

    const [colaboradoresResult, tiposResult, taxasResult] = await Promise.all([
      colaboradorIds.length > 0
        ? applyTenantEmpresa(
            supabase.from("colaboradores").select("id,nome").in("id", colaboradorIds),
            effectiveTenantId,
            effectiveEmpresaId
          )
        : Promise.resolve({ data: [], error: null }),
      tipoHoraIds.length > 0
        ? applyTenantEmpresa(
            supabase.from("tipos_horas").select("id,codigo,descricao,fator").in("id", tipoHoraIds),
            effectiveTenantId,
            effectiveEmpresaId
          )
        : Promise.resolve({ data: [], error: null }),
      colaboradorIds.length > 0
        ? applyTenantEmpresa(
            supabase
              .from("colaborador_taxas")
              .select("colaborador_id,valor_hora,vigencia_inicio,vigencia_fim,criado_em")
              .in("colaborador_id", colaboradorIds)
              .order("vigencia_inicio", { ascending: false })
              .order("criado_em", { ascending: false }),
            effectiveTenantId,
            effectiveEmpresaId
          )
        : Promise.resolve({ data: [], error: null }),
    ]);

    if (colaboradoresResult.error) console.warn("[OS detail] colaboradores apontamentos print", colaboradoresResult.error);
    if (tiposResult.error) console.warn("[OS detail] tipos horas print", tiposResult.error);
    if (taxasResult.error) console.warn("[OS detail] taxas print", taxasResult.error);

    const colaboradoresMap = new Map<string, string>();
    ((colaboradoresResult.data ?? []) as Array<{ id: string; nome: string }>).forEach((row) => {
      colaboradoresMap.set(String(row.id), row.nome);
    });

    const tiposMap = new Map<string, { codigo: string | null; descricao: string | null; fator: number | null }>();
    ((tiposResult.data ?? []) as Array<{ id: string; codigo: string | null; descricao: string | null; fator: number | null }>).forEach(
      (row) => {
        tiposMap.set(String(row.id), {
          codigo: row.codigo ?? null,
          descricao: row.descricao ?? null,
          fator: row.fator ?? null,
        });
      }
    );

    const taxasByColaborador = new Map<
      string,
      Array<{ valor_hora: number; vigencia_inicio: string; vigencia_fim: string | null; criado_em: string }>
    >();
    (
      (taxasResult.data ?? []) as Array<{
        colaborador_id: string;
        valor_hora: number;
        vigencia_inicio: string;
        vigencia_fim: string | null;
        criado_em: string;
      }>
    ).forEach((row) => {
      const key = String(row.colaborador_id);
      const list = taxasByColaborador.get(key) ?? [];
      list.push(row);
      taxasByColaborador.set(key, list);
    });

    const pickValorHora = (colaboradorId: string, dataISO: string) => {
      const taxas = taxasByColaborador.get(colaboradorId) ?? [];
      const dataRef = String(dataISO ?? "").slice(0, 10);
      const found = taxas.find((row) => {
        const inicio = String(row.vigencia_inicio ?? "").slice(0, 10);
        const fim = row.vigencia_fim ? String(row.vigencia_fim).slice(0, 10) : null;
        return inicio <= dataRef && (!fim || dataRef <= fim);
      });
      return Number(found?.valor_hora ?? 0) || 0;
    };

    return baseRows.map((row) => {
      const cached = custosMap.get(String(row.id));
      if (cached) {
        return {
          ...row,
          colaborador_nome: String(cached.colaborador_nome ?? "-").trim() || "-",
          tipo_hora_codigo: cached.tipo_hora_codigo ?? null,
          tipo_hora_descricao: cached.tipo_hora_descricao ?? null,
          fator: Number(cached.fator ?? row.fator_aplicado ?? 1) || 1,
          valor_hora: Number(cached.valor_hora ?? 0) || 0,
          custo_lancamento: roundMoney(Number(cached.custo_lancamento ?? 0)),
        };
      }

      const tipo = row.tipo_hora_id ? tiposMap.get(String(row.tipo_hora_id)) : null;
      const fator = Number(row.fator_aplicado ?? tipo?.fator ?? 1) || 1;
      const valorHora = pickValorHora(String(row.colaborador_id), row.data);
      const horas = Number(row.horas ?? 0) || 0;

      return {
        ...row,
        colaborador_nome: colaboradoresMap.get(String(row.colaborador_id)) ?? "-",
        tipo_hora_codigo: tipo?.codigo ?? null,
        tipo_hora_descricao: tipo?.descricao ?? null,
        fator,
        valor_hora: valorHora,
        custo_lancamento: roundMoney(horas * valorHora * fator),
      };
    });
  }

  async function printOsCompleta() {
    if (!os) return;
    setErr(null);
    setPrintingOs(true);

    try {
      const apontamentosRows = await loadApontamentosRowsForPrint();
      const hhRows = apontamentosRows.length === 0 ? await loadHhRowsForPrint() : [];
      const hasItens = rows.length > 0;
      const hasApontamentos = apontamentosRows.length > 0;
      const hasHoras = hasApontamentos || hhRows.length > 0;

      if (!hasItens && !hasHoras) {
        setErr("Esta OS nao tem itens nem horas para imprimir.");
        return;
      }

      const [{ jsPDF }, autoTableMod] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
      const autoTable = autoTableMod.default;

      const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
      const marginX = 40;
      let y = 42;

      const itensOrdenados = [...rows].sort((a, b) => a.id - b.id);
      const itensMateriais = itensOrdenados.filter((row) => !isDespesaRow(row));
      const itensDespesas = itensOrdenados.filter((row) => isDespesaRow(row));
      const hasItensMateriais = itensMateriais.length > 0;
      const hasItensDespesas = itensDespesas.length > 0;
      const totalMaterial = roundMoney(totais.materiais);
      const totalDespesas = roundMoney(totais.despesas);
      const totalHoras = hasApontamentos
        ? roundMoney(apontamentosRows.reduce((sum, row) => sum + Number(row.horas ?? 0), 0))
        : roundMoney(hhRows.reduce((sum, row) => sum + getHorasTrabalhadasEfetivas(row), 0));
      const totalHorasValor = hasApontamentos
        ? roundMoney(apontamentosRows.reduce((sum, row) => sum + Number(row.custo_lancamento ?? 0), 0))
        : calcHhPedidoTotal(hhRows);
      const valorHorasResumo = hhEnabled ? roundMoney(totalHorasValor) : roundMoney(Number(maoObraExtra || totalHorasValor || 0));
      const totalImpostos = roundMoney(totais.impostos);
      const totalGeral = roundMoney(totais.total);
      const valorPedido = Number(os.orcado ?? 0);
      const margem = roundMoney(valorPedido - totalGeral);
      const margemLabel = margem >= 0 ? "Margem de lucro" : "Margem de prejuizo";
      const formatSignedMoney = (value: number) =>
        value < 0 ? `-R$ ${formatMoney(Math.abs(value))}` : `R$ ${formatMoney(value)}`;

      doc.setFontSize(14);
      doc.text(`OS ${os.numero_os ?? os.id}`, marginX, y);
      y += 16;

      doc.setFontSize(10);
      doc.text(`Cliente: ${os.cliente_nome ?? "-"}`, marginX, y);
      y += 14;

      doc.text(`Emissao: ${new Date().toLocaleString("pt-BR")}`, marginX, y);
      y += 14;

      const descricao = String(os.descricao_servico ?? "").trim();
      if (descricao) {
        const descricaoLinhas = doc.splitTextToSize(`Servico: ${descricao}`, 515);
        doc.text(descricaoLinhas, marginX, y);
        y += descricaoLinhas.length * 12;
      }

      doc.setFontSize(11);
      doc.text("Itens", marginX, y);

      if (hasItensMateriais) {
        const itensBody = itensMateriais.map((row) => {
          const codigo = row.itens?.codigo_interno ?? "";
          const nome = row.itens?.nome ?? "";
          const quantidade = formatDecimalBR(Number(row.quantidade ?? 0), 3);
          const valorUnitario = formatMoney(Number(row.valor_unitario ?? 0));
          const total = formatMoney(Number(row.valor_total ?? 0));
          return [
            String(row.item_id ?? ""),
            String(codigo),
            String(nome),
            String(quantidade),
            String(valorUnitario),
            String(total),
          ];
        });

        autoTable(doc, {
          startY: y + 12,
          margin: { left: marginX, right: marginX },
          head: [["Item ID", "Codigo", "Nome", "Qtd", "V.Unit", "Total"]],
          body: itensBody,
          styles: { fontSize: 9, cellPadding: 4, overflow: "linebreak" },
          headStyles: { fillColor: [30, 41, 59] },
          columnStyles: {
            0: { cellWidth: 56 },
            1: { cellWidth: 70 },
            2: { cellWidth: 240 },
            3: { cellWidth: 50, halign: "right" },
            4: { cellWidth: 60, halign: "right" },
            5: { cellWidth: 60, halign: "right" },
          },
        });
      } else {
        doc.setFontSize(10);
        doc.text("Nenhum item lancado nesta OS.", marginX, y + 16);
      }

      const itensFinalY = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY;
      let nextY = typeof itensFinalY === "number" ? itensFinalY + 22 : y + 36;

      doc.setFontSize(11);
      doc.text("Despesas", marginX, nextY);

      if (hasItensDespesas) {
        const despesasBody = itensDespesas.map((row) => {
          const codigo = row.itens?.codigo_interno ?? "";
          const nome = row.itens?.nome ?? "";
          const quantidade = formatDecimalBR(Number(row.quantidade ?? 0), 3);
          const valorUnitario = formatMoney(Number(row.valor_unitario ?? 0));
          const total = formatMoney(Number(row.valor_total ?? 0));
          return [
            String(row.item_id ?? ""),
            String(codigo),
            String(nome),
            String(quantidade),
            String(valorUnitario),
            String(total),
          ];
        });

        autoTable(doc, {
          startY: nextY + 12,
          margin: { left: marginX, right: marginX },
          head: [["Item ID", "Codigo", "Despesa", "Qtd", "V.Unit", "Total"]],
          body: despesasBody,
          styles: { fontSize: 9, cellPadding: 4, overflow: "linebreak" },
          headStyles: { fillColor: [30, 41, 59] },
          columnStyles: {
            0: { cellWidth: 56 },
            1: { cellWidth: 70 },
            2: { cellWidth: 240 },
            3: { cellWidth: 50, halign: "right" },
            4: { cellWidth: 60, halign: "right" },
            5: { cellWidth: 60, halign: "right" },
          },
        });
        const despesasFinalY = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY;
        nextY = typeof despesasFinalY === "number" ? despesasFinalY + 22 : nextY + 36;
      } else {
        doc.setFontSize(10);
        doc.text("Nenhuma despesa lancada nesta OS.", marginX, nextY + 16);
        nextY += 36;
      }

      doc.setFontSize(11);
      doc.text("Horas lancadas", marginX, nextY);

      if (hasApontamentos) {
        const horasBody = apontamentosRows.map((row) => {
          const colaborador = String(row.colaborador_nome ?? "-").trim() || "-";
          const descricao = String(row.descricao ?? "").trim();
          const pessoa = descricao ? `${colaborador}\n${descricao}` : colaborador;
          const tipo =
            String(row.tipo_hora_codigo ?? "").trim() ||
            String(row.tipo_hora_descricao ?? "").trim() ||
            (Number(row.fator ?? 1) !== 1 ? `Fator ${formatDecimalBR(Number(row.fator ?? 1), 3)}` : "NORMAL");

          return [
            formatDateBR(row.data),
            pessoa,
            formatPeriodoApontamento(row),
            tipo,
            formatHoursBR(Number(row.horas ?? 0)),
            formatMoney(Number(row.valor_hora ?? 0)),
            formatMoney(Number(row.custo_lancamento ?? 0)),
          ];
        });

        autoTable(doc, {
          startY: nextY + 12,
          margin: { left: marginX, right: marginX },
          head: [["Data", "Colaborador / Descricao", "Horario", "Tipo", "Horas", "V.Hora", "Total"]],
          body: horasBody,
          styles: { fontSize: 9, cellPadding: 4, overflow: "linebreak", valign: "top" },
          headStyles: { fillColor: [30, 41, 59] },
          columnStyles: {
            0: { cellWidth: 52 },
            1: { cellWidth: 160 },
            2: { cellWidth: 78 },
            3: { cellWidth: 70 },
            4: { cellWidth: 42, halign: "right" },
            5: { cellWidth: 50, halign: "right" },
            6: { cellWidth: 52, halign: "right" },
          },
        });
        const horasFinalY = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY;
        nextY = typeof horasFinalY === "number" ? horasFinalY + 22 : nextY + 36;
      } else if (hasHoras) {
        const horasBody = hhRows.map((row) => {
          const colaborador = String(row.colaborador_nome ?? "-").trim() || "-";
          const funcao = String(row.especialidade_descricao ?? "-").trim() || "-";
          const horas = getHorasTrabalhadasEfetivas(row);
          const total = getValorTotalEfetivo(row, horas);
          const pessoa = funcao && funcao !== "-" ? `${colaborador}\n${funcao}` : colaborador;

          return [
            formatDateBR(row.data),
            pessoa,
            formatPeriodoHH(row),
            formatHoursBR(horas),
            formatMoney(Number(row.valor_hora ?? 0)),
            formatMoney(total),
          ];
        });

        autoTable(doc, {
          startY: nextY + 12,
          margin: { left: marginX, right: marginX },
          head: [["Data", "Colaborador / Funcao", "Horario", "Horas", "V.Hora", "Total"]],
          body: horasBody,
          styles: { fontSize: 9, cellPadding: 4, overflow: "linebreak", valign: "top" },
          headStyles: { fillColor: [30, 41, 59] },
          columnStyles: {
            0: { cellWidth: 58 },
            1: { cellWidth: 205 },
            2: { cellWidth: 110 },
            3: { cellWidth: 50, halign: "right" },
            4: { cellWidth: 60, halign: "right" },
            5: { cellWidth: 60, halign: "right" },
          },
        });
        const horasFinalY = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY;
        nextY = typeof horasFinalY === "number" ? horasFinalY + 22 : nextY + 36;
      } else {
        doc.setFontSize(10);
        doc.text("Nenhuma hora lancada nesta OS.", marginX, nextY + 16);
        nextY += 36;
      }

      autoTable(doc, {
        startY: nextY,
        margin: { left: marginX, right: marginX },
        head: [["Resumo", "Valor"]],
        body: [
          ["Total horas", `${formatHoursBR(totalHoras)} h`],
          ["Valor horas", `R$ ${formatMoney(valorHorasResumo)}`],
          ["Total material", `R$ ${formatMoney(totalMaterial)}`],
          ["Total despesas", `R$ ${formatMoney(totalDespesas)}`],
          ["Impostos", `R$ ${formatMoney(totalImpostos)}`],
          ["Total geral", `R$ ${formatMoney(totalGeral)}`],
        ],
        styles: { fontSize: 10, cellPadding: 4 },
        headStyles: { fillColor: [30, 41, 59] },
        columnStyles: {
          0: { cellWidth: 220 },
          1: { cellWidth: 140, halign: "right" },
        },
      });

      const resumoFinalY = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY;
      const analiticoStartY = typeof resumoFinalY === "number" ? resumoFinalY + 18 : nextY + 90;

      autoTable(doc, {
        startY: analiticoStartY,
        margin: { left: marginX, right: marginX },
        head: [["Analitico", "Valor"]],
        body: [
          ["Valor pedido", `R$ ${formatMoney(valorPedido)}`],
          ["Valor execucao", `R$ ${formatMoney(totalGeral)}`],
          [margemLabel, formatSignedMoney(margem)],
        ],
        styles: { fontSize: 10, cellPadding: 4 },
        headStyles: { fillColor: [30, 41, 59] },
        columnStyles: {
          0: { cellWidth: 220 },
          1: { cellWidth: 140, halign: "right" },
        },
      });

      doc.autoPrint();
      const url = doc.output("bloburl");
      const w = window.open(url, "_blank");
      if (!w) {
        doc.save(`OS_${os.numero_os ?? os.id}_completa.pdf`);
      }
    } catch (e) {
      console.error(e);
      setErr("Falha ao gerar impressao da OS.");
    } finally {
      setPrintingOs(false);
    }
  }

  const editClienteHabilitaHH = useMemo(() => {
    if (!clienteId) return false;
    const found = clientes.find((c) => c.id === clienteId);
    if (found) return Boolean(found.habilita_hh);
    if (clienteId === (os?.cliente_id ?? null)) return hhClientEnabled;
    return false;
  }, [clienteId, clientes, hhClientEnabled, os?.cliente_id]);
  // canReadOs já é calculado acima (usado para guard de visualização)

  useEffect(() => {
    if (!hhEnabled && activeTab !== "itens") {
      setActiveTab("itens");
    }
  }, [activeTab, hhEnabled]);

  useEffect(() => {
    setFound([]);
    setPick(null);
    setQ("");
    setQty("1");
    setVunit(0);
    setEstoqueAtual(null);
    setBaixaDireta(addMode !== "despesa");
    setErr(null);
  }, [addMode]);

  const orcado = toNum(os?.orcado);
  const hhPedidoTotal = Number(hhPedido || 0) || Number(hhTotal || 0);

  const totais = (() => {
    const despesas = rows
      .filter((r) => isDespesaRow(r))
      .reduce((sum, r) => sum + Number(r.valor_total ?? 0), 0);

    const materiais = rows
      .filter((r) => !isDespesaRow(r) && r.itens?.tipo === "produto")
      .reduce((sum, r) => sum + Number(r.valor_total ?? 0), 0);

    // Mão de obra é CUSTO (vw_custo_mao_obra_os)
    const maoObra = Number(maoObraExtra || 0);

    // Cálculo de impostos:
    // - Se usa HH: 19% do total de HH
    // - Se material: 21% do valor de material
    // - Se serviço normal: 19% do total
    const tipoPedidoAtual = os?.tipo_pedido === "material" ? "material" : "servico";

    let impostos = 0;
    let total = 0;
    if (hhEnabled) {
      // HH: 19% sobre o total de HH
      // O total operacional segue a mesma composição exibida na tela:
      // material + mão de obra + despesas + impostos.
      impostos = hhPedidoTotal * 0.15;
      total = materiais + despesas + maoObra + impostos;
    } else if (tipoPedidoAtual === "material") {
      // Tem material: 21% sobre material
      impostos = orcado * 0.27;
      total = materiais + despesas + maoObra + impostos;
    } else {
      // Serviço normal: 19% sobre total (material + mão de obra)
      impostos = orcado * 0.15;
      total = materiais + despesas + maoObra + impostos;
    }

    // Total:
    // - Se HH habilitado: total de HH (que já inclui mão de obra HH)
    // - Senão: Material + Despesas + Mão de obra + Impostos
    return { materiais, despesas, maoObra, impostos, total };
  })();

  const totalAlert = !hhEnabled && orcado > 0 && totais.total >= orcado * 0.9;
  const totalClass = totalAlert ? "text-red-300 border-red-500/40" : "text-emerald-300 border-emerald-500/40";

  const calculateUnitPriceWithTaxes = (item: { preco_unitario?: number | null; aliquota_ipi?: number | null }) => {
    const base = Number(item.preco_unitario ?? 0);
    const ipi = Number(item.aliquota_ipi ?? 0);
    const ipiPerc = Number.isFinite(ipi) ? ipi : 0;
    const final = base * (1 + ipiPerc / 100);
    return Math.round(final * 100) / 100;
  };

  async function fetchVendedoresOrcamento(): Promise<Array<{ id: string; nome: string; email: string }>> {
    const { data: sess } = await supabase.auth.getSession();
    const token = sess.session?.access_token ?? null;
    if (!token) throw new Error("Sessao expirada. Faca login novamente.");

    const res = await fetch(`/api/comercial/vendedores?tenantId=${effectiveTenantId}&empresaId=${effectiveEmpresaId}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    const json = (await res.json().catch(() => null)) as
      | { vendedores?: Array<{ id?: string | null; nome?: string | null; email?: string | null }>; error?: string }
      | null;
    if (!res.ok) throw new Error(typeof json?.error === "string" ? json.error : "Erro ao carregar vendedores.");

    return (Array.isArray(json?.vendedores) ? json.vendedores : [])
      .map((row) => ({
        id: String(row?.id ?? "").trim(),
        nome: String(row?.nome ?? "").trim(),
        email: String(row?.email ?? "").trim(),
      }))
      .filter((row) => row.id && row.nome);
  }

  async function abrirGerarOrcamento() {
    setGerarOrcamentoErr(null);
    setGerarOrcamentoResumo(null);
    setItemServicoHHId(null);
    setShowGerarOrcamento(true);
    setGerarOrcamentoLoading(true);
    try {
      const cfg = await ensureConfig(supabase, { tenantId: effectiveTenantId, empresaId: effectiveEmpresaId });
      setMargemMateriais(String(cfg.margem_lucro_padrao_percent ?? 0));
      setMargemMaoObra(String(cfg.margem_mao_obra_padrao_percent ?? 0));

      if (!os?.orcamento_gerado_id) {
        const vends = await fetchVendedoresOrcamento();
        setVendedoresOrcamento(vends);
        setVendedorOrcamentoId((prev) => prev || vends[0]?.id || "");
      }

      if (hhEnabled) {
        const { data, error } = await applyTenantEmpresa(
          supabase.from("itens").select("id,nome,codigo_interno").eq("tipo", "servico").eq("ativo", true).order("nome", { ascending: true }),
          effectiveTenantId,
          effectiveEmpresaId
        );
        if (error) throw error;
        setServicoItensOrcamento((data ?? []) as Array<{ id: number; nome: string; codigo_interno: string }>);
      }
    } catch (e: unknown) {
      setGerarOrcamentoErr(e instanceof Error ? e.message : String(e));
    } finally {
      setGerarOrcamentoLoading(false);
    }
  }

  async function submitGerarOrcamento() {
    if (!os) return;
    setGerarOrcamentoErr(null);

    const margemMat = Number(margemMateriais || 0);
    const margemMo = Number(margemMaoObra || 0);
    if (!Number.isFinite(margemMat) || margemMat < 0) return setGerarOrcamentoErr("Margem de materiais invalida.");
    if (!Number.isFinite(margemMo) || margemMo < 0) return setGerarOrcamentoErr("Margem de mao de obra invalida.");

    setGerarOrcamentoBusy(true);
    try {
      let orcamentoId = os.orcamento_gerado_id ?? null;

      if (!orcamentoId) {
        if (!vendedorOrcamentoId) throw new Error("Selecione o vendedor do orcamento.");
        if (!os.cliente_id) throw new Error("Esta OS nao tem um cliente valido vinculado.");

        const created = await createOrcamento(supabase, {
          tenantId: effectiveTenantId,
          empresaId: effectiveEmpresaId,
          titulo: os.descricao_servico?.trim() || `OS ${os.numero_os}`,
          clienteId: os.cliente_id,
          vendedorUsuarioId: vendedorOrcamentoId,
        });
        orcamentoId = created.id;
      }

      const { data, error } = await supabase.rpc("fn_gerar_ou_atualizar_orcamento_de_os", {
        p_tenant_id: effectiveTenantId,
        p_empresa_id: effectiveEmpresaId,
        p_os_id: osId,
        p_orcamento_id: orcamentoId,
        p_margem_materiais_percent: margemMat,
        p_margem_mao_obra_percent: margemMo,
        p_item_servico_hh_id: itemServicoHHId,
      });
      if (error) throw error;

      const row = (Array.isArray(data) ? data[0] : data) as
        | {
            itens_materiais_criados?: number;
            grupos_mao_obra_criados?: number;
            hh_valor_adicionado?: number;
            cargos_sem_mapeamento?: string[];
          }
        | undefined;

      setGerarOrcamentoResumo({
        orcamentoId,
        itensMateriaisCriados: Number(row?.itens_materiais_criados ?? 0),
        gruposMaoObraCriados: Number(row?.grupos_mao_obra_criados ?? 0),
        hhValorAdicionado: Number(row?.hh_valor_adicionado ?? 0),
        cargosSemMapeamento: Array.isArray(row?.cargos_sem_mapeamento) ? row!.cargos_sem_mapeamento! : [],
      });

      await load();
    } catch (e: unknown) {
      setGerarOrcamentoErr(e instanceof Error ? e.message : String(e));
    } finally {
      setGerarOrcamentoBusy(false);
    }
  }

  async function loadClientes() {
    const { data, error } = await applyTenant(
      supabase.from("clientes").select("id,nome,ativo,habilita_hh").eq("ativo", true).order("nome", { ascending: true }).limit(500),
      effectiveTenantId
    );

    if (!error && (data ?? []).length > 0) {
      setClientes((data ?? []) as Cliente[]);
      return;
    }

    // Fallback: alguns papéis (ex.: APONTAMENTO_RH) podem ler OS, mas não conseguem SELECT em clientes (RLS/can()).
    // Para não deixar o campo vazio, monta a lista pelos clientes já referenciados nas OS visíveis.
    const { data: osData, error: osErr } = await applyTenant(
      supabase.from("ordens_servico").select("cliente_id,cliente_nome").order("id", { ascending: false }).limit(1000),
      effectiveTenantId
    );
    if (osErr) {
      setClientes([]);
      return;
    }

    const unique = new Map<number, Cliente>();
    ((osData ?? []) as unknown as OsClienteRow[]).forEach((r) => {
      const id = r.cliente_id;
      if (!id) return;
      if (unique.has(id)) return;
      unique.set(id, {
        id,
        nome: (r.cliente_nome ?? `Cliente ${id}`).trim(),
        ativo: true,
        habilita_hh: false,
      });
    });

    const list = Array.from(unique.values()).sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
    setClientes(list);
  }

  async function loadGestaoItens() {
    if (!Number.isFinite(osId)) return;

    setGestaoErr(null);
    setGestaoLoading(true);

    const { data, error } = await applyTenant(
      supabase
        .from("os_gestao_itens")
        .select("id,os_id,item_tipo,area,habilitado,responsavel_id,data_prevista,progresso_percent"),
      effectiveTenantId
    )
      .eq("os_id", osId);

    if (error) {
      setGestaoErr(error.message);
      setGestaoItems([]);
      setGestaoLoading(false);
      return;
    }

    let items = (data ?? []) as GestaoItem[];

    const missing = gestaoDefs
      .filter((def) => !items.some((it) => it.item_tipo === def.item_tipo && it.area === def.area))
      .map((def) => ({
        os_id: osId,
        item_tipo: def.item_tipo,
        area: def.area,
        habilitado: false,
        responsavel_id: null,
        data_prevista: null,
        progresso_percent: 0,
        tenant_id: effectiveTenantId,
      }));

    if (missing.length > 0) {
      const { error: missingErr } = await supabase
        .from("os_gestao_itens")
        .upsert(missing, { onConflict: "os_id,item_tipo,area" });

      if (missingErr) {
        setGestaoErr(missingErr.message);
        setGestaoItems(orderGestaoItems(items));
        setGestaoLoading(false);
        return;
      }

      const { data: reload, error: reloadErr } = await applyTenant(
        supabase
          .from("os_gestao_itens")
          .select("id,os_id,item_tipo,area,habilitado,responsavel_id,data_prevista,progresso_percent"),
        effectiveTenantId
      )
        .eq("os_id", osId);

      if (!reloadErr) {
        items = (reload ?? []) as GestaoItem[];
      } else {
        setGestaoErr(reloadErr.message);
      }
    }

    setGestaoItems(orderGestaoItems(items));
    setGestaoLoading(false);
  }

  async function load() {
    setErr(null);

    const { data, error } = await supabase.rpc("get_os_detail_operacional", {
      p_tenant_id: effectiveTenantId,
      p_empresa_id: effectiveEmpresaId,
      p_os_id: osId,
    });

    if (error) {
      setErr(error.message);
      return;
    }

    const payload = (data ?? {}) as Record<string, unknown>;
    const osRow = payload.os as OS | undefined;
    if (!osRow?.id) {
      setErr("Ordem de serviço não encontrada para a empresa ativa.");
      return;
    }

    const { data: responsavelData } = await applyTenantEmpresa(
      supabase
        .from("ordens_servico")
        .select("responsavel_aprovacao_id,status_fluxo,faturado_em,faturada_presumida_legado,garantia_motivo,unidade_id")
        .eq("id", osRow.id)
        .maybeSingle(),
      effectiveTenantId,
      effectiveEmpresaId
    );
    const responsavelAprovacaoId = String(responsavelData?.responsavel_aprovacao_id ?? "").trim() || null;
    setOs({
      ...osRow,
      responsavel_aprovacao_id: responsavelAprovacaoId,
      status_fluxo: responsavelData?.status_fluxo ?? null,
      faturado_em: responsavelData?.faturado_em ?? null,
      faturada_presumida_legado: responsavelData?.faturada_presumida_legado ?? false,
      garantia_motivo: responsavelData?.garantia_motivo ?? null,
      unidade_id: responsavelData?.unidade_id ?? null,
    });
    setTemGestao(Boolean(osRow.tem_gestao));

    setClienteHabilitaHH(Boolean(payload.cliente_habilita_hh));

    const nextRows = Array.isArray(payload.itens) ? (payload.itens as unknown as OsItemRow[]) : [];
    setRows(nextRows);
    setBaixaEditValues(
      Object.fromEntries(nextRows.map((row) => [row.id, formatDecimalBR(getQuantidadeBaixada(row), 3)]))
    );

    setMaoObraExtra(Number(payload.custo_mao_obra ?? 0));
    setHhTotal(Number(payload.total_hh ?? 0));

    // Valor do pedido HH (para bater com PDF): soma(valor_hora * horas_efetivas)
    // horas_efetivas segue a mesma regra do PDF (2 períodos ou entrada/saída; fallback horas_trabalhadas).
    const hhRows = Array.isArray(payload.hh_lancamentos)
      ? (payload.hh_lancamentos as unknown as HhLancamentoCalcRow[])
      : [];
    setHhPedido(calcHhPedidoTotal(hhRows));
  }

  useEffect(() => {
    if (!canView) return;
    void loadClientes();
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canView, osId, tenantId, empresaId]);

  useEffect(() => {
    setBaixaDireta(true);
  }, [osId]);

  const closeGestaoModal = useCallback(
    (reset = true) => {
      setShowGestaoModal(false);
      if (reset && os) setTemGestao(Boolean(os.tem_gestao));
    },
    [os]
  );

  const openEditModal = useCallback(() => {
    if (!canWriteOs) return;
    if (!os) return;
    setShowEdit(true);
    setClienteId(os.cliente_id ?? null);
    setUnidadeId(os.unidade_id ?? null);
    setClienteNomeLivre(os.cliente_nome ?? "");
    setDescricao((os.descricao_servico ?? "").toLocaleUpperCase("pt-BR"));
    setPedidoCompra(os.pedido_compra ?? "");
    // Avoid React warning: <select value> must not be null.
    setTipoPedido(os.tipo_pedido === "material" ? "material" : "servico");
    setVendedor(os.vendedor ?? "");
    setResponsavelAprovacaoId(os.responsavel_aprovacao_id ?? null);
    setOrcadoInput(String(os.orcado ?? ""));
    setUsaRelatorioHH(Boolean(os.usa_relatorio_hh) && hhClientEnabled);
    setEditErr(null);
  }, [canWriteOs, hhClientEnabled, os]);

  const closeEditModal = useCallback(() => {
    setShowEdit(false);
    setEditErr(null);
  }, []);

  async function saveEdit() {
    if (!canWriteOs) return;
    if (!os) return;
    if (!clienteId && !clienteNomeLivre.trim()) {
      setEditErr("Selecione um cliente ou informe um nome.");
      return;
    }

    const orcadoValor = Number(orcadoInput || 0);
    if (!Number.isFinite(orcadoValor)) {
      setEditErr("Valor orcado invalido.");
      return;
    }

    setEditSaving(true);
    setEditErr(null);

    const clienteNomeFinal =
      clienteId ? (clientes.find((c) => c.id === clienteId)?.nome ?? clienteNomeLivre.trim()) : clienteNomeLivre.trim();

    const usaRelatorioHHFinal = editClienteHabilitaHH ? usaRelatorioHH : false;

    const { error } = await applyTenant(
      supabase.from("ordens_servico").update({
        cliente_id: clienteId,
        unidade_id: unidadeId,
        cliente_nome: clienteNomeFinal,
        descricao_servico: descricao.trim() ? descricao.trim().toLocaleUpperCase("pt-BR") : null,
        pedido_compra: pedidoCompra.trim() || null,
        tipo_pedido: tipoPedido,
        vendedor: vendedor.trim() || null,
        responsavel_aprovacao_id: responsavelAprovacaoId,
        orcado: orcadoValor,
        usa_relatorio_hh: usaRelatorioHHFinal,
        atualizado_em: new Date().toISOString(),
      }),
      effectiveTenantId
    ).eq("id", os.id);

    setEditSaving(false);

    if (error) {
      setEditErr(error.message);
      return;
    }

    closeEditModal();
    await load();
  }

  useEffect(() => {
    if (!showGestaoModal) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") closeGestaoModal();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [closeGestaoModal, showGestaoModal]);

  async function removeItem(osItemId: number) {
    const ok = confirm("Remover este item da OS?\nSe baixou estoque, será devolvido.");
    if (!ok) return;

    setBusy(true);
    setErr(null);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const { error } = await supabase.rpc("remove_os_item_reverte_estoque", {
      p_os_item_id: osItemId,
      p_realizado_por: userEmail,
      p_motivo: "Remoção pelo app (devolução automática)",
      p_empresa_id: effectiveEmpresaId,
    });

    setBusy(false);

    if (error) return setErr(error.message);

    await load();
  }

  function openEditItemModal(row: OsItemRow) {
    if (locked) return;
    setEditItemErr(null);
    setEditItem(row);
    setEditItemQty(formatDecimalBR(Number(row.quantidade ?? 0), 3));
    setEditItemVunit(Number(row.valor_unitario ?? 0));
    setShowEditItem(true);
  }

  function closeEditItemModal() {
    setShowEditItem(false);
    setEditItem(null);
    setEditItemErr(null);
    setEditItemQty("1");
    setEditItemVunit(0);
  }

  async function saveEditItem() {
    if (!editItem) return;

    const qtyNumber = parseDecimalBR(editItemQty);
    if (!Number.isFinite(qtyNumber) || qtyNumber <= 0) return setEditItemErr("Quantidade inválida.");
    if (!Number.isFinite(editItemVunit) || editItemVunit < 0) return setEditItemErr("Valor unitário inválido.");

    // Para manter a consistência do estoque (baixa imediata), editamos como:
    // remove (reverte estoque) + add (baixa novamente com os novos valores).
    setEditItemSaving(true);
    setEditItemErr(null);
    setErr(null);
    setOkMsg(null);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const { error: rmErr } = await supabase.rpc("remove_os_item_reverte_estoque", {
      p_os_item_id: editItem.id,
      p_realizado_por: userEmail,
      p_motivo: "Edição pelo app (recriação do item)",
      p_empresa_id: effectiveEmpresaId,
    });

    if (rmErr) {
      setEditItemSaving(false);
      setEditItemErr(rmErr.message);
      return;
    }

    const { error: addErr } = await supabase.rpc("add_os_item_baixa_imediata", {
      p_os_id: osId,
      p_item_id: editItem.item_id,
      p_quantidade: qtyNumber,
      p_valor_unitario: Number(editItemVunit),
      p_desconto_percentual: Number(editItem.desconto_percentual ?? 0),
      p_desconto_valor: Number(editItem.desconto_valor ?? 0),
      p_baixa_estoque: getQuantidadeBaixada(editItem) > BAIXA_EPSILON || Boolean(editItem.baixa_estoque),
      p_realizado_por: userEmail,
      p_motivo: "Edição pela tela da OS (baixa imediata)",
      p_empresa_id: effectiveEmpresaId,
    });

    setEditItemSaving(false);
    if (addErr) {
      setEditItemErr(addErr.message);
      return;
    }

    closeEditItemModal();
    setOkMsg("Item atualizado.");
    await load();
  }

  async function setStatus(newStatus: OS["status"]) {
    if (!os) return;

    if (newStatus === "cancelada") {
      const ok = confirm("Cancelar esta OS? Depois disso, a edição será bloqueada.");
      if (!ok) return;
    }

    setBusy(true);
    setErr(null);

    if (newStatus === "em_andamento") {
      const { error } = await supabase.rpc("os_reabrir_correcao", { p_os_id: os.id });
      setBusy(false);
      if (error) return setErr(error.message);
      await load();
      return;
    }

    const patch: { status: OS["status"]; atualizado_em: string; data_conclusao?: string } = {
      status: newStatus,
      atualizado_em: new Date().toISOString(),
    };
    if (newStatus === "concluida") patch.data_conclusao = new Date().toISOString();

    const { error } = await applyTenantEmpresa(
      supabase
        .from("ordens_servico")
        .update(patch)
        .eq("id", os.id),
      effectiveTenantId,
      effectiveEmpresaId
    );

    setBusy(false);
    if (error) return setErr(error.message);

    await load();
  }

  async function concluirOs() {
    if (!os) return;
    const emGarantia = statusExibicao === "em_andamento_garantia";
    const ok = confirm(
      emGarantia
        ? "Concluir a garantia desta OS?"
        : "Concluir OS? Ela ficará aguardando faturamento e projetos e execução serão marcados como 100%."
    );
    if (!ok) return;

    setIsConcluding(true);
    setErr(null);
    setOkMsg(null);

    const osIdNumber = Number(os.id);
    const { error } = await supabase.rpc("os_concluir", { p_os_id: osIdNumber });

    setIsConcluding(false);

    if (error) {
      setErr(error.message);
      return;
    }

    setOkMsg(emGarantia ? "Garantia concluída." : "OS concluída e aguardando faturamento.");
    await load();
  }

  async function faturarOs() {
    if (!os) return;
    const ok = confirm("Faturar esta OS? É necessário haver NF-e ou NFS-e emitida e vinculada.");
    if (!ok) return;

    setIsFaturando(true);
    setErr(null);
    setOkMsg(null);

    const { error } = await supabase.rpc("os_faturar", { p_os_id: Number(os.id) });

    setIsFaturando(false);
    if (error) {
      setErr(error.message);
      return;
    }

    setOkMsg("OS faturada.");
    await load();
  }

  function updateGestaoItem(item_tipo: GestaoTipo, area: GestaoArea, patch: Partial<GestaoItem>) {
    setGestaoItems((prev) => {
      const exists = prev.some((it) => it.item_tipo === item_tipo && it.area === area);
      if (!exists) return prev;
      return prev.map((it) => (it.item_tipo === item_tipo && it.area === area ? { ...it, ...patch } : it));
    });
  }

  async function saveGestao() {
    if (!os) return;

    setGestaoErr(null);
    setGestaoSaving(true);
    setOkMsg(null);

    if (gestaoItems.length === 0) {
      setGestaoSaving(false);
      setGestaoErr("Itens de gestao nao carregados. Tente novamente.");
      return;
    }

    const payload = gestaoItems.map((it) => {
      const progress = Number(it.progresso_percent ?? 0);
      return {
        os_id: os.id,
        item_tipo: it.item_tipo,
        area: it.area,
        habilitado: !!it.habilitado,
        responsavel_id: it.responsavel_id?.trim() ? it.responsavel_id.trim() : null,
        data_prevista: it.data_prevista ? it.data_prevista : null,
        progresso_percent: Number.isFinite(progress) ? Math.max(0, Math.min(100, Math.trunc(progress))) : NaN,
      };
    });

    if (payload.some((p) => !Number.isFinite(p.progresso_percent) || p.progresso_percent < 0 || p.progresso_percent > 100)) {
      setGestaoSaving(false);
      setGestaoErr("Progresso deve estar entre 0 e 100.");
      return;
    }

    const { error: osErr } = await supabase
      .from("ordens_servico")
      .update({ tem_gestao: temGestao, atualizado_em: new Date().toISOString() })
      .eq("id", os.id);

    if (osErr) {
      setGestaoSaving(false);
      setGestaoErr(osErr.message);
      return;
    }

    const { error: upsertErr } = await supabase
      .from("os_gestao_itens")
      .upsert(
        payload.map((row) => ({
          ...row,
          tenant_id: effectiveTenantId,
        })),
        { onConflict: "os_id,item_tipo,area" }
      );

    setGestaoSaving(false);

    if (upsertErr) {
      setGestaoErr(upsertErr.message);
      return;
    }

    closeGestaoModal(false);
    setOkMsg("Gestao atualizada.");
    await load();
  }

  function openGestaoModal() {
    if (readOnly) return;
    if (os) setTemGestao(Boolean(os.tem_gestao));
    setGestaoErr(null);
    setShowGestaoModal(true);
    loadGestaoItens();
  }

  async function handleSearch(nextNome?: string, nextFornecedor?: string) {
    setLookupErr(null);
    setLookupBusy(true);

    const nomeTerm = (nextNome ?? lookupNome).trim();
    const fornecedorTerm = (nextFornecedor ?? lookupFornecedor).trim();
    const nomeTerms = parseLookupTerms(nomeTerm);
    const fornecedorTerms = parseLookupTerms(fornecedorTerm);
    const nomeSeedTerm = pickLookupSeedTerm(nomeTerms);
    const fornecedorSeedTerm = pickLookupSeedTerm(fornecedorTerms);

    const { data: itemData, error: itemError } = await supabase.rpc("search_os_itens", {
      p_tenant_id: effectiveTenantId,
      p_empresa_id: effectiveEmpresaId,
      p_term: nomeSeedTerm || null,
      p_fornecedor: fornecedorSeedTerm || null,
      p_despesa_only: isDespesaMode,
      p_limit: LOOKUP_FETCH_LIMIT,
    });
    if (itemError) {
      setLookupErr(itemError.message);
      setLookupRows([]);
      setLookupBusy(false);
      return;
    }

    const baseRows = ((itemData ?? []) as ItemLookupBaseRow[])
      .filter((row) => matchesLookupTerms([row.nome, row.codigo_interno, row.fabricante], nomeTerms))
      .filter((row) => matchesLookupTerms([row.fornecedor], fornecedorTerms))
      .sort((a, b) => String(a.nome ?? "").localeCompare(String(b.nome ?? ""), "pt-BR", { sensitivity: "base" }))
      .slice(0, LOOKUP_RESULT_LIMIT);

    setLookupRows(
      baseRows.map((r) => ({
        id: r.id,
        codigo_interno: r.codigo_interno,
        nome: r.nome,
        tipo: r.tipo,
        finalidade: r.finalidade ?? null,
        preco_unitario: r.preco_unitario,
        aliquota_ipi: r.aliquota_ipi,
        controla_estoque: r.controla_estoque ?? null,
        fornecedor: r.fornecedor,
        ultima_entrada: r.ultima_entrada,
        estoque_atual: r.estoque_atual === null ? null : Number(r.estoque_atual),
      }))
    );

    setLookupBusy(false);
  }

  function sortRows(rows: ItemLookupRow[], key: SortKey, dir: SortDir): ItemLookupRow[] {
    const factor = dir === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const val = (k: SortKey): SortValue => {
        switch (k) {
          case "id":
            return a.id;
          case "codigo":
            return a.codigo_interno?.toLowerCase() ?? "";
          case "descricao":
            return a.nome?.toLowerCase() ?? "";
          case "fornecedor":
            return a.fornecedor?.toLowerCase() ?? "";
          case "ultima":
            return a.ultima_entrada ? new Date(a.ultima_entrada).getTime() : null;
          case "preco":
            return typeof a.preco_unitario === "number" ? a.preco_unitario : null;
          case "estoque":
            return typeof a.estoque_atual === "number" ? a.estoque_atual : null;
        }
      };
      const va = val(key);
      const vb = (() => {
        switch (key) {
          case "id":
            return b.id;
          case "codigo":
            return b.codigo_interno?.toLowerCase() ?? "";
          case "descricao":
            return b.nome?.toLowerCase() ?? "";
          case "fornecedor":
            return b.fornecedor?.toLowerCase() ?? "";
          case "ultima":
            return b.ultima_entrada ? new Date(b.ultima_entrada).getTime() : null;
          case "preco":
            return typeof b.preco_unitario === "number" ? b.preco_unitario : null;
          case "estoque":
            return typeof b.estoque_atual === "number" ? b.estoque_atual : null;
        }
      })();

      // Nulls sempre no final
      const aNull = va === null || va === undefined || va === "";
      const bNull = vb === null || vb === undefined || vb === "";
      if (aNull && bNull) return 0;
      if (aNull) return 1;
      if (bNull) return -1;

      if (va < vb) return -1 * factor;
      if (va > vb) return 1 * factor;
      return 0;
    });
  }

  function handleSort(key: SortKey) {
    if (sortKey === key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDir("asc");
    }
  }

  const sortedRows = useMemo(() => sortRows(lookupRows, sortKey, sortDir), [lookupRows, sortKey, sortDir]);

  const renderGestaoRow = (def: (typeof gestaoDefs)[number]) => {
    const item = gestaoItems.find((it) => it.item_tipo === def.item_tipo && it.area === def.area);
    if (!item) return null;

    const fieldsDisabled = gestaoSaving || gestaoLoading || !item.habilitado;

    return (
      <div
        key={gestaoKey(def)}
        className="grid grid-cols-1 md:grid-cols-[200px_1fr_1fr_140px] gap-3 items-start border border-zinc-800 rounded-lg px-3 py-3 bg-zinc-900/40"
      >
        <div className="space-y-2">
          <div className="text-sm font-medium">{def.label}</div>
          <label className="inline-flex items-center gap-2 text-xs text-zinc-200">
            <input
              type="checkbox"
              className="h-4 w-4"
              checked={item.habilitado}
              onChange={(e) => updateGestaoItem(def.item_tipo, def.area, { habilitado: e.target.checked })}
              disabled={gestaoSaving || gestaoLoading}
              aria-label="Habilitado"
              title="Habilitado"
            />
            Habilitado
          </label>
        </div>

        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Responsavel</div>
          <input
            className="w-full px-3 py-2"
            value={item.responsavel_id ?? ""}
            onChange={(e) => updateGestaoItem(def.item_tipo, def.area, { responsavel_id: e.target.value })}
            disabled={fieldsDisabled}
            placeholder="responsavel (texto livre)"
            aria-label="Responsavel"
            title="Responsavel"
          />
        </div>

        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Data prevista</div>
          <input
            type="date"
            className="w-full px-3 py-2"
            value={item.data_prevista ? item.data_prevista.slice(0, 10) : ""}
            onChange={(e) => updateGestaoItem(def.item_tipo, def.area, { data_prevista: e.target.value || null })}
            disabled={fieldsDisabled}
            aria-label="Data prevista"
            title="Data prevista"
          />
        </div>

        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Progresso %</div>
          <input
            type="number"
            min={0}
            max={100}
            className="w-full px-3 py-2"
            value={item.progresso_percent ?? 0}
            onChange={(e) =>
              updateGestaoItem(def.item_tipo, def.area, {
                progresso_percent: Math.max(0, Math.min(100, Number(e.target.value) || 0)),
              })
            }
            disabled={fieldsDisabled}
            aria-label="Progresso percentual"
            title="Progresso percentual"
          />
        </div>
      </div>
    );
  };

  function openLookupModal(initialNome?: string) {
    const nome = (initialNome ?? "").trim();

    setShowLookup(true);
    setLookupErr(null);
    setLookupRows([]);
    setLookupNome(nome);
    setLookupFornecedor("");

    if (nome) {
      void handleSearch(nome, "");
    } else {
      void handleSearch("", "");
    }
  }

  async function searchItems() {
    setErr(null);
    setFound([]);

    const term = q.trim();
    const id = Number(term);
    if (!term || !Number.isFinite(id) || id <= 0) {
      openLookupModal(term);
      return;
    }

    if (isDespesaMode && !isDespesaItemId(id)) {
      setErr(`Selecione uma despesa entre os itens ${DESPESA_ITEM_ID_MIN} e ${DESPESA_ITEM_ID_MAX}.`);
      openLookupModal(term);
      return;
    }

    setSearching(true);

    const { data, error } = await supabase.rpc("search_os_itens", {
      p_tenant_id: effectiveTenantId,
      p_empresa_id: effectiveEmpresaId,
      p_term: term,
      p_fornecedor: null,
      p_despesa_only: isDespesaMode,
      p_limit: 1,
    });
    const item = ((data ?? []) as ItemLookupBaseRow[])[0] ?? null;

    setSearching(false);

    if (error || !item) {
      setErr(
        isDespesaMode
          ? "Despesa nao encontrada pelo ID informado. Use a busca por nome/fornecedor."
          : "Item nao encontrado pelo ID informado. Use a busca por nome/fabricante."
      );
      openLookupModal();
      return;
    }

    pickItem(item);
  }

  function pickItem(it: ItemPick) {
    setPick(it);
    setFound([]);
    setQ(`${it.codigo_interno} - ${it.nome}`);
    setQty("1");
    setVunit(calculateUnitPriceWithTaxes(it));
    if (isDespesaMode) {
      setEstoqueAtual(null);
      setBaixaDireta(false);
    } else {
      setEstoqueAtual(
        typeof (it as ItemLookupRow).estoque_atual === "number"
          ? Number((it as ItemLookupRow).estoque_atual ?? 0)
          : null
      );
    }
    if (!isDespesaMode && typeof (it as ItemLookupRow).estoque_atual !== "number" && Number.isFinite(it.id) && it.id > 0) {
      void (async () => {
        const { data } = await applyTenantEmpresa(
          supabase.from("estoque").select("quantidade_atual").eq("item_id", it.id).maybeSingle(),
          effectiveTenantId,
          effectiveEmpresaId
        );
        setEstoqueAtual(data?.quantidade_atual ?? null);
      })();
    }
    setTimeout(() => {
      qtyRef.current?.focus();
      qtyRef.current?.select();
    }, 0);
  }

  async function addItem() {
    if (!pick) return setErr(isDespesaMode ? "Selecione uma despesa." : "Selecione um item.");
    if (!empresaId) return setErr("Selecione uma empresa antes de adicionar itens.");
    if (isDespesaMode) {
      if (!isDespesaItemId(pick.id)) {
        return setErr(`Selecione uma despesa entre os itens ${DESPESA_ITEM_ID_MIN} e ${DESPESA_ITEM_ID_MAX}.`);
      }
    } else if ((pick.finalidade ?? "") !== "materia_prima") {
      return setErr("Apenas itens de materia-prima podem ser adicionados.");
    }
    const qtyNumber = parseDecimalBR(qty);
    if (!Number.isFinite(qtyNumber) || qtyNumber <= 0) return setErr("Quantidade invalida.");
    if (vunit < 0) return setErr("Valor unitario invalido.");
    const baixaNaInclusao = !isDespesaMode && baixaDireta && Boolean(pick.controla_estoque);

    setBusy(true);
    setErr(null);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    // RPC FINAL: baixa imediata
    const { error } = await supabase.rpc("add_os_item_baixa_imediata", {
      p_os_id: osId,
      p_item_id: pick.id,
      p_quantidade: qtyNumber,
      p_valor_unitario: Number(vunit),
      p_baixa_estoque: baixaNaInclusao,
      p_realizado_por: userEmail,
      p_motivo: baixaNaInclusao
        ? "Adicao pela tela da OS (baixa imediata)"
        : isDespesaMode
          ? "Adicao de despesa pela tela da OS"
          : "Adicao pela tela da OS (sem baixa)",
      p_empresa_id: empresaId,
    });

    setBusy(false);

    if (error) return setErr(error.message);

    // limpa form
    setPick(null);
    setQ("");
    setFound([]);
    setQty("1");
    setVunit(0);
    setEstoqueAtual(null);

    await load();
    setTimeout(() => searchRef.current?.focus(), 0);
  }

  function resetBaixaEditValue(row: OsItemRow) {
    setBaixaEditValues((prev) => ({
      ...prev,
      [row.id]: formatDecimalBR(getQuantidadeBaixada(row), 3),
    }));
  }

  async function saveBaixaQuantidade(row: OsItemRow) {
    if (!empresaId) return setErr("Selecione uma empresa antes de atualizar baixa de estoque.");

    const qtyNumber = Number(row.quantidade ?? 0);
    if (!Number.isFinite(qtyNumber) || qtyNumber <= 0) {
      return setErr("Quantidade invalida para atualizar baixa.");
    }

    const nextQuantidade = parseDecimalBR(baixaEditValues[row.id] ?? formatDecimalBR(getQuantidadeBaixada(row), 3));
    if (!Number.isFinite(nextQuantidade)) {
      return setErr("Quantidade baixada invalida.");
    }
    if (nextQuantidade < 0 || nextQuantidade > qtyNumber) {
      return setErr(`Quantidade baixada deve ficar entre 0 e ${formatDecimalBR(qtyNumber, 3)}.`);
    }

    const atual = getQuantidadeBaixada(row);
    if (Math.abs(nextQuantidade - atual) <= BAIXA_EPSILON) {
      resetBaixaEditValue(row);
      return;
    }

    setBaixaSavingId(row.id);
    setErr(null);
    setOkMsg(null);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const { error } = await supabase.rpc("set_os_item_quantidade_baixada", {
      p_os_item_id: row.id,
      p_quantidade_baixada: nextQuantidade,
      p_realizado_por: userEmail,
      p_motivo: "Edicao da quantidade baixada pela tela da OS",
      p_empresa_id: effectiveEmpresaId,
    });

    setBaixaSavingId(null);
    if (error) return setErr(error.message);

    setOkMsg("Quantidade baixada atualizada.");
    await load();
  }

  if (te.loading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando...</div>;
  }

  if (!canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 px-4">
        Sem permissão para visualizar OS.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div className="space-y-2">
          <Link href="/os" className="text-sm text-zinc-300 hover:text-zinc-100">
            ← Voltar
          </Link>

          <div className="flex items-center gap-2 flex-wrap">
            <h1 className="text-2xl font-semibold">
              {os
                ? `OS ${os.numero_os} - ${os.cliente_nome}${os.descricao_servico ? ` - ${os.descricao_servico}` : ""}`
                : "Carregando..."}
            </h1>

            {os && (
              <span
                className={[
                  "inline-flex items-center px-2 py-1 rounded-md border text-xs",
                  statusBadge[statusExibicao ?? ""] ?? "bg-zinc-500/10 text-zinc-300 border-zinc-500/30",
                ].join(" ")}
              >
                {getOsStatusLabel(statusExibicao)}
              </span>
            )}
          </div>

          {os && (
            <div className="text-sm text-zinc-400 space-y-1">
              <div>Abertura: {new Date(os.data_abertura).toLocaleString("pt-BR")}</div>
              <div className="flex flex-wrap items-center gap-2 text-xs md:text-sm">
                <span>
                  Material:{" "}
                  <span className="text-zinc-200 tabular-nums">{hideTotais ? "—" : `R$ ${formatMoney(totais.materiais)}`}</span>
                </span>
                <span>
                  - Mao de obra:{" "}
                  <span className="text-zinc-200 tabular-nums">{hideTotais ? "—" : `R$ ${formatMoney(totais.maoObra)}`}</span>
                </span>
                <span>
                  - Despesas:{" "}
                  <span className="text-zinc-200 tabular-nums">{hideTotais ? "—" : `R$ ${formatMoney(totais.despesas)}`}</span>
                </span>
                <span>
                  - Impostos:{" "}
                  <span className="text-zinc-200 tabular-nums">{hideTotais ? "—" : `R$ ${formatMoney(totais.impostos)}`}</span>
                </span>
                <span className="text-base md:text-lg font-semibold text-zinc-100">
                  - Total:{" "}
                  {hideTotais ? (
                    <span className="text-zinc-200 tabular-nums">—</span>
                  ) : (
                    <span className={`inline-flex items-center px-2 py-1 rounded-md border tabular-nums ${totalClass}`}>
                      R$ {formatMoney(totais.total)}
                    </span>
                  )}
                </span>
              </div>
            </div>
          )}
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={load}
            disabled={busy}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>

          <button
            onClick={openEditModal}
            disabled={busy || readOnly}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Editar
          </button>

          <button
            onClick={openGestaoModal}
            disabled={busy || readOnly}
            className={[
              "px-3 py-2 rounded-md font-medium",
              temGestao
                ? "bg-emerald-300 text-emerald-950 hover:bg-emerald-200"
                : "border border-zinc-700 bg-zinc-900 text-zinc-100 hover:bg-zinc-800",
            ].join(" ")}
          >
            Projetos
          </button>

          {(statusExibicao === "em_andamento" || statusExibicao === "em_andamento_garantia") && canConcluirFluxo && (
            <button
              onClick={concluirOs}
              disabled={busy || isConcluding}
              className="px-3 py-2 rounded-md bg-sky-300 text-sky-950 hover:bg-sky-200 font-medium"
            >
              {isConcluding
                ? "Concluindo..."
                : statusExibicao === "em_andamento_garantia"
                  ? "Concluir garantia"
                  : "Concluir OS"}
            </button>
          )}

          {statusExibicao === "concluida" && canConcluirFluxo && (
            <button
              onClick={() => setStatus("em_andamento")}
              disabled={busy || isConcluding}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Reabrir para correção
            </button>
          )}

          {statusExibicao === "concluida" && canFaturarFluxo && (
            <button
              onClick={faturarOs}
              disabled={busy || isFaturando}
              className="px-3 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
            >
              {isFaturando ? "Faturando..." : "Faturar OS"}
            </button>
          )}

          {!locked && (
            <button
              onClick={() => setStatus("cancelada")}
              disabled={busy || isConcluding}
              className="px-3 py-2 rounded-md bg-red-300 text-red-950 hover:bg-red-200 font-medium"
            >
              Cancelar
            </button>
          )}

          {isFiado && canWriteOs && (
            <button
              onClick={abrirGerarOrcamento}
              disabled={busy}
              className="px-3 py-2 rounded-md bg-amber-200 text-amber-950 hover:bg-amber-100 font-medium"
            >
              {os?.orcamento_gerado_id ? "Atualizar Orçamento" : "Gerar Orçamento"}
            </button>
          )}
        </div>
      </div>

      {locked && (
        <div className="border border-zinc-800 rounded-xl p-3 bg-zinc-950 text-sm text-zinc-300">
          Esta OS está <b>{getOsStatusLabel(statusExibicao)}</b>. Edição bloqueada.
        </div>
      )}

      {!hideCustos && (
        <MaoObraCard
          osId={osId}
          effectiveTenantId={effectiveTenantId}
          effectiveEmpresaId={effectiveEmpresaId}
        />
      )}

      {err && <div className="text-sm text-red-400">{err}</div>}
      {okMsg && <div className="text-sm text-emerald-300">{okMsg}</div>}

      {hhEnabled && canReadOs && (
        <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-950">
          <div className="text-lg font-semibold text-emerald-300">Apontamento HH</div>
          <div className="text-sm text-zinc-400 mt-1">
            Gestão de horas trabalhadas e cobrança de mão de obra.
          </div>
        </div>
      )}

      {(!hhEnabled || isFiado) && (
        <>
          {/* Adicionar item / despesa */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="mb-4 flex items-end gap-2 border-b border-zinc-800">
          <button
            type="button"
            onClick={() => setAddMode("item")}
            className={[
              "px-4 py-2 rounded-t-md border border-b-0 text-sm font-medium transition-colors",
              !isDespesaMode
                ? "border-zinc-700 bg-zinc-900 text-zinc-100"
                : "border-transparent bg-transparent text-zinc-400 hover:text-zinc-200",
            ].join(" ")}
          >
            Adicionar item
          </button>
          <button
            type="button"
            onClick={() => setAddMode("despesa")}
            className={[
              "px-4 py-2 rounded-t-md border border-b-0 text-sm font-medium transition-colors",
              isDespesaMode
                ? "border-zinc-700 bg-zinc-900 text-zinc-100"
                : "border-transparent bg-transparent text-zinc-400 hover:text-zinc-200",
            ].join(" ")}
          >
            Adicionar despesa
          </button>
        </div>

        <div className="flex items-center justify-between flex-wrap gap-2">
          <div>
            <div className="font-medium">{addSectionTitle}</div>
            <div className="text-sm text-zinc-400 mt-1">{addSectionDescription}</div>
          </div>

          <div className="flex items-center gap-2">
            {!isDespesaMode && (
              <label className="inline-flex items-center gap-2 text-sm text-zinc-200 select-none">
                <input
                  type="checkbox"
                  checked={baixaDireta}
                  onChange={(e) => setBaixaDireta(e.target.checked)}
                  disabled={locked}
                />
                Baixa direta
              </label>
            )}
            <button
              onClick={addItem}
              disabled={busy || locked || !canAddPickedItem}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              {busy ? "Aguarde..." : "Adicionar"}
            </button>

            <button
              type="button"
              onClick={() => void printOsItens()}
              disabled={printingItens || rows.length === 0}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 font-medium"
              title={rows.length === 0 ? "Sem itens para imprimir" : "Imprimir itens da OS"}
            >
              {printingItens ? "Imprimindo..." : "Imprimir itens"}
            </button>

            <button
              type="button"
              onClick={() => void printOsCompleta()}
              disabled={printingOs || !os}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 font-medium"
              title={!os ? "Carregando OS" : "Imprimir OS completa"}
            >
              {printingOs ? "Imprimindo OS..." : "Imprimir OS"}
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-6 gap-3 mt-4">
          <div className={`space-y-1 relative ${isDespesaMode ? "md:col-span-4" : "md:col-span-3"}`}>
            <div className="text-xs text-zinc-400">{addSearchLabel}</div>
            <div className="flex gap-2">
              <input
                ref={searchRef}
                className="w-full px-3 py-2"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder={addSearchPlaceholder}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    searchItems();
                  }
                }}
                disabled={locked}
                aria-label={addSearchLabel}
                title={addSearchLabel}
              />
              <button
                onClick={searchItems}
                disabled={searching || locked}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                {searching ? "..." : "Buscar"}
              </button>
            </div>

            {found.length > 0 && (
              <div className="absolute z-20 mt-2 w-full border border-zinc-800 rounded-lg bg-zinc-950 overflow-hidden">
                {found.map((it) => (
                  <button
                    key={it.id}
                    onClick={() => pickItem(it)}
                    className="w-full text-left px-3 py-2 hover:bg-zinc-900"
                  >
                    <div className="text-sm font-medium">
                      [{it.codigo_interno}] {it.nome}
                    </div>
                    <div className="text-xs text-zinc-400">{it.tipo}</div>
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">Qtd</div>
            <input
              type="text"
              inputMode="decimal"
              ref={qtyRef}
              className="w-full px-3 py-2"
              value={qty}
              onChange={(e) => setQty(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  addItem();
                }
              }}
              disabled={locked}
              aria-label="Quantidade"
              title="Quantidade"
            />
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">V.Unit</div>
            <input
              type="number"
              className="w-full px-3 py-2"
              value={vunit}
              onChange={(e) => setVunit(Number(e.target.value))}
              disabled={locked}
              aria-label="Valor unitario"
              title="Valor unitario"
            />
            {pick && (
              <div className="text-[11px] text-zinc-400">
                Base: R$ {formatMoney(Number(pick.preco_unitario ?? 0))} | IPI: {(Number(pick.aliquota_ipi ?? 0) || 0).toFixed(2)}%
              </div>
            )}
          </div>

          {!isDespesaMode && (
            <div className="md:col-span-1 space-y-1">
              <div className="text-xs text-zinc-400">Estoque</div>
              <div className="w-full px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-zinc-200">
                {typeof estoqueAtual === "number" ? formatDecimalBR(estoqueAtual, 3) : "-"}
              </div>
            </div>
          )}
        </div>

        {pick && (
          <div className="text-sm text-zinc-300 mt-3">
            Selecionado: <b>[{pick.codigo_interno}] {pick.nome}</b> ({isDespesaMode ? "despesa" : pick.tipo})
            {isDespesaMode && !isDespesaPick && (
              <span className="text-amber-300"> | Apenas despesas entre os itens 1 e 99</span>
            )}
            {!isMateriaPrima && <span className="text-amber-300"> · Apenas materia-prima</span>}
          </div>
        )}
      </div>
        </>
      )}

      {showEdit && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-4xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">Editar OS</div>
                <div className="text-sm text-zinc-400">Atualize os dados da ordem de servico.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setShowEdit(false)}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={saveEdit}
                  disabled={editSaving}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                >
                  {editSaving ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Pedido de compra</div>
                <input
                  className="w-full px-3 py-2"
                  value={pedidoCompra}
                  onChange={(e) => setPedidoCompra(e.target.value)}
                  placeholder="Alfanumerico conforme cliente"
                  aria-label="Pedido de compra"
                  title="Pedido de compra"
                />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Tipo de pedido</div>
                <select
                  className="w-full px-3 py-2"
                  value={tipoPedido}
                  onChange={(e) => setTipoPedido(e.target.value as "servico" | "material")}
                  aria-label="Tipo de pedido"
                  title="Tipo de pedido"
                >
                  <option value="servico">Servico</option>
                  <option value="material">Material</option>
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Cliente (cadastro)</div>
                <select
                  className="w-full px-3 py-2"
                  value={clienteId ?? ""}
                  onChange={(e) => {
                    const nextId = e.target.value ? Number(e.target.value) : null;
                    setClienteId(nextId);
                    setUnidadeId(null);

                    let nextHabilita = false;
                    if (nextId) {
                      const found = clientes.find((c) => c.id === nextId);
                      if (found) nextHabilita = Boolean(found.habilita_hh);
                      else if (nextId === (os?.cliente_id ?? null)) nextHabilita = hhClientEnabled;
                    }

                    if (!nextHabilita) setUsaRelatorioHH(false);
                  }}
                  aria-label="Cliente cadastro"
                  title="Cliente cadastro"
                >
                  <option value="">-</option>
                  {clientes.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nome}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Unidade / fábrica</div>
                <select
                  className="w-full px-3 py-2"
                  value={unidadeId ?? ""}
                  onChange={(e) => setUnidadeId(e.target.value ? Number(e.target.value) : null)}
                  disabled={!clienteId || clienteUnidades.length === 0}
                  aria-label="Unidade ou fábrica do cliente"
                >
                  <option value="">Sem unidade</option>
                  {clienteUnidades.map((unidade) => <option key={unidade.id} value={unidade.id}>{unidade.nome}{unidade.codigo ? ` (${unidade.codigo})` : ""}</option>)}
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Cliente (nome livre)</div>
                <input
                  className="w-full px-3 py-2"
                  value={clienteNomeLivre}
                  onChange={(e) => setClienteNomeLivre(e.target.value)}
                  placeholder="Se nao estiver cadastrado"
                  aria-label="Cliente nome livre"
                  title="Cliente nome livre"
                />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Vendedor</div>
                <input
                  className="w-full px-3 py-2"
                  value={vendedor}
                  onChange={(e) => setVendedor(e.target.value)}
                  aria-label="Vendedor"
                  title="Vendedor"
                />
              </div>

              {!hideTotais && (
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Valor pedido</div>
                  <input
                    type="number"
                    className="w-full px-3 py-2"
                    value={orcadoInput}
                    onChange={(e) => setOrcadoInput(e.target.value)}
                    placeholder="0.00"
                    aria-label="Valor pedido"
                    title="Valor pedido"
                  />
                </div>
              )}

              <div className="space-y-1 md:col-span-3">
                <div className="text-xs text-zinc-400">Descricao (opcional)</div>
                <textarea
                  className="w-full px-3 py-2 min-h-[80px]"
                  value={descricao}
                  onChange={(e) => setDescricao(e.target.value.toLocaleUpperCase("pt-BR"))}
                  aria-label="Descricao da OS"
                  title="Descricao da OS"
                />
              </div>
            </div>

            {editClienteHabilitaHH && (
              <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-900/40">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    className="h-4 w-4"
                    checked={usaRelatorioHH}
                    onChange={(e) => setUsaRelatorioHH(e.target.checked)}
                  />
                  <span className="font-medium">Esta OS é de HH?</span>
                </label>
              </div>
            )}

            {editErr && <div className="text-sm text-red-400">{editErr}</div>}
          </div>
        </div>
      )}

      {showGestaoModal && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50"
          onClick={(e) => {
            if (e.target === e.currentTarget) closeGestaoModal();
          }}
        >
          <div
            className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl flex flex-col max-h-[calc(100dvh-2rem)] min-h-0 overflow-hidden"
            role="dialog"
            aria-modal="true"
            aria-labelledby="gestao-title"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between gap-3 shrink-0">
              <div>
                <div id="gestao-title" className="text-lg font-semibold">
                  Gestao de Projetos e Execucao
                </div>
                <div className="text-sm text-zinc-400">Configure responsaveis, datas e progresso.</div>
              </div>
              <button
                onClick={() => closeGestaoModal()}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 overflow-y-auto min-h-0 space-y-4">
              <div className="border border-zinc-800 rounded-lg px-4 py-3 bg-zinc-900/40 flex items-center justify-between flex-wrap gap-3">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    className="h-4 w-4"
                    checked={temGestao}
                    onChange={(e) => setTemGestao(e.target.checked)}
                    disabled={gestaoSaving || gestaoLoading}
                    aria-label="Habilitar gestao nesta OS"
                    title="Habilitar gestao nesta OS"
                  />
                  <span>Habilitar gestao nesta OS</span>
                </label>
                <div className="text-xs text-zinc-400">Salve para atualizar o status da gestao.</div>
              </div>

              {gestaoErr && <div className="text-sm text-red-400">{gestaoErr}</div>}

              {gestaoLoading && <div className="text-sm text-zinc-300">Carregando dados de gestao...</div>}

              {!gestaoLoading && !temGestao && (
                <div className="text-sm text-zinc-300">
                  Gestao desabilitada para esta OS. Ative o controle acima para editar os itens. Valores existentes serao
                  mantidos.
                </div>
              )}

              {!gestaoLoading && temGestao && (
                <div className="space-y-5">
                  <div className="space-y-3">
                    <div className="text-sm font-semibold text-zinc-200">Projetos (Engenharia)</div>
                    {gestaoDefs.filter((d) => d.grupo === "projetos").map((def) => renderGestaoRow(def))}
                  </div>

                  <div className="space-y-3">
                    <div className="text-sm font-semibold text-zinc-200">Execucoes (Campo)</div>
                    {gestaoDefs.filter((d) => d.grupo === "execucoes").map((def) => renderGestaoRow(def))}
                  </div>
                </div>
              )}
            </div>

            <div className="px-5 py-4 border-t border-zinc-800 flex items-center justify-end gap-2 shrink-0">
              <button
                onClick={() => closeGestaoModal()}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                disabled={gestaoSaving}
              >
                Cancelar
              </button>
              <button
                onClick={saveGestao}
                disabled={gestaoSaving || gestaoLoading}
                className="px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
              >
                {gestaoSaving ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}

      {(!hhEnabled || isFiado) && (
        <>
          {showLookup && (
            <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto">
              <div className="min-h-full w-full flex items-start justify-center p-4 md:items-center">
                <div className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl flex flex-col gap-4 max-h-[90dvh] h-[90dvh] min-h-0 overflow-hidden">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <div className="text-lg font-semibold">{lookupTitle}</div>
                      <div className="text-sm text-zinc-400">{lookupDescription}</div>
                    </div>
                    <button
                      onClick={() => setShowLookup(false)}
                      className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                    >
                      Fechar
                    </button>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Nome</div>
                      <input
                        className="w-full px-3 py-2"
                        value={lookupNome}
                        onChange={(e) => setLookupNome(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") {
                            e.preventDefault();
                            handleSearch(e.currentTarget.value, lookupFornecedor);
                          }
                        }}
                        aria-label="Buscar item por nome"
                        title="Buscar item por nome"
                      />
                    </div>

                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Fornecedor</div>
                      <input
                        className="w-full px-3 py-2"
                        value={lookupFornecedor}
                        onChange={(e) => setLookupFornecedor(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") {
                            e.preventDefault();
                            handleSearch(lookupNome, e.currentTarget.value);
                          }
                        }}
                        aria-label="Buscar item por fornecedor"
                        title="Buscar item por fornecedor"
                      />
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleSearch()}
                      disabled={lookupBusy}
                      className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                    >
                      {lookupBusy ? "Buscando..." : "Buscar"}
                    </button>
                    <button
                      onClick={() => {
                        setLookupNome("");
                        setLookupFornecedor("");
                        setLookupRows([]);
                        setLookupErr(null);
                        handleSearch("", "");
                      }}
                      className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                    >
                      Limpar
                    </button>
                  </div>

                  {lookupErr && <div className="text-sm text-red-400">{lookupErr}</div>}

                  <div className="border border-zinc-800 rounded-xl bg-zinc-950 flex-1 min-h-0 overflow-auto overscroll-contain">
                    <table className="w-full text-sm min-w-[980px]">
                      <thead className="bg-zinc-900/70 sticky top-0 z-10">
                      <tr className="text-left text-zinc-200">
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("id")}>
                          ID {sortKey === "id" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("codigo")}>
                          Codigo {sortKey === "codigo" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("descricao")}>
                          Descricao {sortKey === "descricao" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("fornecedor")}>
                          Fornecedor {sortKey === "fornecedor" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("ultima")}>
                          Ultima entrada {sortKey === "ultima" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer" onClick={() => handleSort("preco")}>
                          Preco {sortKey === "preco" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer" onClick={() => handleSort("estoque")}>
                          Saldo {sortKey === "estoque" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {sortedRows.map((it) => (
                        <tr
                          key={it.id}
                          className="hover:bg-zinc-900/40 cursor-pointer"
                          onClick={() => {
                            pickItem(it);
                            setShowLookup(false);
                          }}
                        >
                          <td className="px-4 py-3 tabular-nums">{it.id}</td>
                          <td className="px-4 py-3">{it.codigo_interno}</td>
                          <td className="px-4 py-3">{it.nome}</td>
                          <td className="px-4 py-3 text-zinc-300">{it.fornecedor ?? "—"}</td>
                          <td className="px-4 py-3 text-zinc-300">
                            {it.ultima_entrada ? new Date(it.ultima_entrada).toLocaleDateString("pt-BR") : "—"}
                          </td>
                          <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoney(Number(it.preco_unitario ?? 0))}</td>
                          <td className="px-4 py-3 text-right tabular-nums">
                            {typeof it.estoque_atual === "number" ? formatDecimalBR(Number(it.estoque_atual), 3) : "—"}
                          </td>
                        </tr>
                      ))}

                      {lookupRows.length === 0 && (
                        <tr>
                          <td colSpan={7} className="px-4 py-6 text-zinc-400 text-center">
                            Nenhum resultado ainda. Informe filtros e busque.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
          )}

          {/* Tabela itens */}
          <div className="border border-zinc-800 rounded-xl overflow-x-auto bg-zinc-950">
            <table className="w-full min-w-[1120px] text-sm">
              <thead className="bg-zinc-900/60">
                <tr className="text-left text-zinc-200">
                  <th className="px-4 py-3">ID</th>
                  <th className="px-4 py-3">Item</th>
                  <th className="px-4 py-3 text-right">Qtd</th>
                  <th className="px-4 py-3 text-right">V.Unit</th>
                  <th className="px-4 py-3 text-right">Total</th>
                  <th className="px-4 py-3 text-center">Baixa</th>
                  <th className="px-4 py-3 text-center">Ações</th>
                  <th className="px-4 py-3 whitespace-nowrap">Data</th>
                  <th className="px-4 py-3">Nome</th>
                </tr>
              </thead>

              <tbody className="divide-y divide-zinc-800">
                {rows.map((r) => {
                  const quantidadeBaixada = getQuantidadeBaixada(r);
                  const statusBaixa = getBaixaStatus(r);
                  const baixaClass =
                    statusBaixa === "completa"
                      ? "border-emerald-500/50 bg-emerald-500/15 text-emerald-300"
                      : statusBaixa === "parcial"
                        ? "border-amber-500/50 bg-amber-500/15 text-amber-300"
                        : "border-red-500/50 bg-red-500/15 text-red-300";
                  const baixaTitle =
                    statusBaixa === "completa"
                      ? "Baixa completa"
                      : statusBaixa === "parcial"
                        ? "Baixa parcial"
                        : "Nenhuma baixa registrada";
                  const baixaValue = baixaEditValues[r.id] ?? formatDecimalBR(quantidadeBaixada, 3);
                  const isSavingBaixa = baixaSavingId === r.id;
                  const baixaDisabled = locked || busy || baixaSavingId !== null || isDespesaRow(r);

                  return (
              <tr
                key={r.id}
                className={[
                  "hover:bg-zinc-900/40",
                  locked ? "" : "cursor-pointer",
                ].join(" ")}
                onClick={() => openEditItemModal(r)}
              >
                <td className="px-4 py-3 tabular-nums">{r.item_id}</td>
                <td className="px-4 py-3">
                  {r.itens ? (
                    <>
                      <div className="font-medium">
                        [{r.itens.codigo_interno}] {r.itens.nome}
                      </div>
                      <div className="text-xs text-zinc-400">{r.itens.tipo}</div>
                    </>
                  ) : (
                    <span className="text-zinc-400">Item {r.item_id}</span>
                  )}
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  {formatDecimalBR(Number(r.quantidade ?? 0), 3)}
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  R$ {formatMoney(Number(r.valor_unitario))}
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  R$ {formatMoney(Number(r.valor_total))}
                </td>

                <td className="px-4 py-3 text-center">
                  <input
                    type="text"
                    inputMode="decimal"
                    value={baixaValue}
                    onClick={(e) => e.stopPropagation()}
                    onFocus={(e) => {
                      e.stopPropagation();
                      e.currentTarget.select();
                    }}
                    onChange={(e) => {
                      setBaixaEditValues((prev) => ({ ...prev, [r.id]: e.target.value }));
                    }}
                    onKeyDown={(e) => {
                      e.stopPropagation();
                      if (e.key === "Enter") {
                        e.preventDefault();
                        if (!baixaDisabled) void saveBaixaQuantidade(r);
                      }
                      if (e.key === "Escape") {
                        e.preventDefault();
                        resetBaixaEditValue(r);
                        e.currentTarget.blur();
                      }
                    }}
                    disabled={baixaDisabled}
                    aria-label="Quantidade baixada"
                    title={`${baixaTitle}. Baixado: ${formatDecimalBR(quantidadeBaixada, 3)} de ${formatDecimalBR(
                      Number(r.quantidade ?? 0),
                      3
                    )}. Pressione Enter para salvar.`}
                    className={[
                      "w-[5.5rem] rounded border px-2 py-1 text-right text-xs font-medium tabular-nums outline-none",
                      baixaClass,
                      isSavingBaixa ? "opacity-70" : "",
                      baixaDisabled ? "cursor-not-allowed opacity-70" : "focus:ring-2 focus:ring-zinc-400/40",
                    ].join(" ")}
                  />
                </td>

                <td className="px-4 py-3 text-center">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      void removeItem(r.id);
                    }}
                    disabled={busy || locked}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  >
                    Remover
                  </button>
                </td>
                <td className="px-4 py-3 whitespace-nowrap tabular-nums text-zinc-300">
                  {r.registrado_em || r.criado_em
                    ? new Date(r.registrado_em ?? r.criado_em ?? "").toLocaleString("pt-BR")
                    : "—"}
                </td>
                <td className="px-4 py-3 text-zinc-300">
                  {r.registrado_por_nome?.trim() || "Não identificado"}
                </td>
              </tr>
                  );
                })}

            {rows.length === 0 && (
              <tr>
                <td className="px-4 py-6 text-zinc-400" colSpan={9}>
                  Nenhum item ainda.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Modal de edição do item */}
      {showEditItem && editItem && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50 overflow-y-auto">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl my-4">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Editar item</div>
                <div className="text-sm text-zinc-400">
                  {editItem.itens ? (
                    <>
                      [{editItem.itens.codigo_interno}] {editItem.itens.nome}
                    </>
                  ) : (
                    <>Item {editItem.item_id}</>
                  )}
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={closeEditItemModal}
                  disabled={editItemSaving}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={() => void saveEditItem()}
                  disabled={editItemSaving || locked}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                >
                  {editItemSaving ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4">
              {editItemErr && <div className="text-sm text-red-400">{editItemErr}</div>}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Qtd</div>
                  <input
                    type="text"
                    inputMode="decimal"
                    className="w-full px-3 py-2"
                    value={editItemQty}
                    onChange={(e) => setEditItemQty(e.target.value)}
                    disabled={locked}
                    aria-label="Quantidade"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">V.Unit</div>
                  <input
                    type="number"
                    className="w-full px-3 py-2"
                    value={editItemVunit}
                    onChange={(e) => setEditItemVunit(Number(e.target.value))}
                    disabled={locked}
                    aria-label="Valor unitário"
                  />
                </div>
              </div>

              <div className="text-sm text-zinc-300">
                Total: <b>R$ {formatMoney((parseDecimalBR(editItemQty) || 0) * (Number(editItemVunit) || 0))}</b>
                <span className="text-zinc-500">
                  {" "}
                  - Baixa: {formatDecimalBR(getQuantidadeBaixada(editItem), 3)} de{" "}
                  {formatDecimalBR(Number(editItem.quantidade ?? 0), 3)}
                </span>
              </div>

              <div className="text-xs text-zinc-500">
                Observacao: quando houver quantidade baixada, a edicao recria o item para ajustar estoque corretamente.
              </div>
            </div>
          </div>
        </div>
      )}
        </>
      )}

      {/* Modal de edição */}
      {showEdit && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50 overflow-y-auto">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl my-4">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Editar OS</div>
                <div className="text-sm text-zinc-400">Atualize os dados da ordem de serviço</div>
              </div>
              <button
                onClick={closeEditModal}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-4 max-h-[70vh] overflow-y-auto">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Cliente (cadastro)</div>
                  <select
                    aria-label="Cliente (cadastro)"
                    className="w-full px-3 py-2"
                    value={clienteId ?? ""}
                    onChange={(e) => {
                      const nextId = e.target.value ? Number(e.target.value) : null;
                      setClienteId(nextId);
                      setUnidadeId(null);

                      let nextHabilita = false;
                      if (nextId) {
                        const found = clientes.find((c) => c.id === nextId);
                        if (found) nextHabilita = Boolean(found.habilita_hh);
                        else if (nextId === (os?.cliente_id ?? null)) nextHabilita = hhClientEnabled;
                      }

                      if (!nextHabilita) setUsaRelatorioHH(false);
                    }}
                  >
                    <option value="">-</option>
                    {clientes.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.nome}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Unidade / fábrica</div>
                  <select
                    aria-label="Unidade ou fábrica do cliente"
                    className="w-full px-3 py-2"
                    value={unidadeId ?? ""}
                    onChange={(e) => setUnidadeId(e.target.value ? Number(e.target.value) : null)}
                    disabled={!clienteId || clienteUnidades.length === 0}
                  >
                    <option value="">Sem unidade</option>
                    {clienteUnidades.map((unidade) => <option key={unidade.id} value={unidade.id}>{unidade.nome}{unidade.codigo ? ` (${unidade.codigo})` : ""}</option>)}
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Cliente (nome livre)</div>
                  <input
                    aria-label="Cliente (nome livre)"
                    className="w-full px-3 py-2"
                    value={clienteNomeLivre}
                    onChange={(e) => setClienteNomeLivre(e.target.value)}
                    placeholder="Se nao estiver cadastrado"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Pedido de compra</div>
                  <input
                    aria-label="Pedido de compra"
                    className="w-full px-3 py-2"
                    value={pedidoCompra}
                    onChange={(e) => setPedidoCompra(e.target.value)}
                    placeholder="Pedido de compra"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Tipo de pedido</div>
                  <select
                    aria-label="Tipo de pedido"
                    className="w-full px-3 py-2"
                    value={tipoPedido}
                    onChange={(e) => setTipoPedido(e.target.value as "servico" | "material")}
                  >
                    <option value="servico">Serviço</option>
                    <option value="material">Material</option>
                  </select>
                </div>

                <div className="space-y-1">
                  <ResponsavelAprovacaoSelect
                    tenantId={effectiveTenantId}
                    empresaId={effectiveEmpresaId}
                    value={responsavelAprovacaoId}
                    onChange={(userId) => setResponsavelAprovacaoId(userId)}
                    disabled={editSaving || locked}
                    label="Responsável da OS"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Vendedor</div>
                  <input
                    aria-label="Vendedor"
                    className="w-full px-3 py-2"
                    value={vendedor}
                    onChange={(e) => setVendedor(e.target.value)}
                    placeholder="Vendedor"
                  />
                </div>

                {!hideTotais && (
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Valor orcado</div>
                    <input
                      type="number"
                      aria-label="Valor orcado"
                      className="w-full px-3 py-2"
                      value={orcadoInput}
                      onChange={(e) => setOrcadoInput(e.target.value)}
                      placeholder="0.00"
                    />
                  </div>
                )}

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Descrição</div>
                  <textarea
                    aria-label="Descrição"
                    className="w-full px-3 py-2 min-h-[80px]"
                    value={descricao}
                    onChange={(e) => setDescricao(e.target.value.toLocaleUpperCase("pt-BR"))}
                    placeholder="Descrição da OS"
                  />
                </div>
              </div>

              {editClienteHabilitaHH && (
                <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-900/40">
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      className="h-4 w-4"
                      checked={usaRelatorioHH}
                      onChange={(e) => setUsaRelatorioHH(e.target.checked)}
                    />
                    <span className="font-medium">Esta OS é de HH?</span>
                  </label>
                </div>
              )}

              {editErr && <div className="text-sm text-red-400">{editErr}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 flex justify-end gap-2">
              <button
                onClick={closeEditModal}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={saveEdit}
                disabled={editSaving || locked}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {editSaving ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}

      {(osIsHH || clienteHabilitaHH) && (
        <RelatorioHHSection
          osId={osId}
          osDetail={{ cliente_id: os?.cliente_id ?? null }}
          osStatus={os?.status ?? null}
          usaRelatorioHh={os?.usa_relatorio_hh ?? null}
          enabled={hhEnabled}
          clienteHabilitaHH={clienteHabilitaHH || osIsHH}
          effectiveTenantId={effectiveTenantId}
          effectiveEmpresaId={effectiveEmpresaId}
        />
      )}

      {showGerarOrcamento && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4 overflow-y-auto z-50">
          <div className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4 my-4">
            <div>
              <div className="text-lg font-semibold">
                {os?.orcamento_gerado_id ? "Atualizar Orçamento" : "Gerar Orçamento"}
              </div>
              <div className="text-sm text-zinc-400 mt-1">
                {os?.orcamento_gerado_id
                  ? "Adiciona ao orçamento já vinculado apenas o que foi lançado nesta OS desde a última geração. Edições manuais no orçamento não são alteradas."
                  : "Cria um orçamento a partir do que já foi lançado nesta OS, aplicando margem sobre o custo de materiais e mão de obra por apontamento. Valor de HH entra sem markup (já é preço de venda)."}
              </div>
            </div>

            {gerarOrcamentoLoading ? (
              <div className="text-sm text-zinc-400">Carregando...</div>
            ) : gerarOrcamentoResumo ? (
              <div className="space-y-3">
                <div className="text-sm text-emerald-300">Orçamento sincronizado com sucesso.</div>
                <ul className="text-sm text-zinc-300 space-y-1">
                  <li>Itens de material/despesa criados: {gerarOrcamentoResumo.itensMateriaisCriados}</li>
                  <li>Grupos de mão de obra (apontamento) criados: {gerarOrcamentoResumo.gruposMaoObraCriados}</li>
                  <li>Valor de HH adicionado: R$ {formatMoney(gerarOrcamentoResumo.hhValorAdicionado)}</li>
                </ul>
                {gerarOrcamentoResumo.cargosSemMapeamento.length > 0 && (
                  <div className="text-xs text-amber-300 border border-amber-900/60 rounded-lg p-3 bg-amber-950/20">
                    Cargos sem serviço vinculado (horas não incluídas, configure em Cadastros → Cargos e gere de novo):{" "}
                    {gerarOrcamentoResumo.cargosSemMapeamento.join(", ")}
                  </div>
                )}
                <div className="flex items-center justify-end gap-2 pt-2">
                  <a
                    href={`/comercial/orcamentos/${gerarOrcamentoResumo.orcamentoId}`}
                    className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                  >
                    Ver orçamento
                  </a>
                  <button
                    onClick={() => setShowGerarOrcamento(false)}
                    className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm"
                  >
                    Fechar
                  </button>
                </div>
              </div>
            ) : (
              <div className="space-y-3">
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Margem materiais (%)</div>
                    <input
                      type="number"
                      className="w-full px-3 py-2"
                      value={margemMateriais}
                      onChange={(e) => setMargemMateriais(e.target.value)}
                      disabled={gerarOrcamentoBusy}
                    />
                  </div>
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Margem mão de obra (%)</div>
                    <input
                      type="number"
                      className="w-full px-3 py-2"
                      value={margemMaoObra}
                      onChange={(e) => setMargemMaoObra(e.target.value)}
                      disabled={gerarOrcamentoBusy}
                    />
                  </div>
                </div>

                {!os?.orcamento_gerado_id && (
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Vendedor do orçamento</div>
                    <select
                      className="w-full px-3 py-2"
                      value={vendedorOrcamentoId}
                      onChange={(e) => setVendedorOrcamentoId(e.target.value)}
                      disabled={gerarOrcamentoBusy}
                    >
                      <option value="">-</option>
                      {vendedoresOrcamento.map((v) => (
                        <option key={v.id} value={v.id}>
                          {v.nome}
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                {hhEnabled && (
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Serviço para faturar HH (se houver valor pendente)</div>
                    <select
                      className="w-full px-3 py-2"
                      value={itemServicoHHId ?? ""}
                      onChange={(e) => setItemServicoHHId(e.target.value ? Number(e.target.value) : null)}
                      disabled={gerarOrcamentoBusy}
                    >
                      <option value="">-</option>
                      {servicoItensOrcamento.map((it) => (
                        <option key={it.id} value={it.id}>
                          {it.codigo_interno} — {it.nome}
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                {gerarOrcamentoErr && <div className="text-sm text-red-400">{gerarOrcamentoErr}</div>}

                <div className="flex items-center justify-end gap-2 pt-2">
                  <button
                    onClick={() => setShowGerarOrcamento(false)}
                    disabled={gerarOrcamentoBusy}
                    className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  >
                    Cancelar
                  </button>
                  <button
                    onClick={submitGerarOrcamento}
                    disabled={gerarOrcamentoBusy}
                    className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                  >
                    {gerarOrcamentoBusy ? "Gerando..." : os?.orcamento_gerado_id ? "Atualizar" : "Gerar"}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
