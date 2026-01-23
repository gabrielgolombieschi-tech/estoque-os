"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "next/navigation";
import { supabaseBrowser } from "../../../lib/supabase/client";
import { parseDecimalBR, formatDecimalBR } from "../../../lib/decimal";
import MaoObraCard from "../../components/os/MaoObraCard";
import RelatorioHHSection from "./components/RelatorioHHSection";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { getOsDetailAccess } from "@/lib/auth/osAccess";

type Cliente = { id: number; nome: string; ativo: boolean; habilita_hh?: boolean | null };

type OS = {
  id: number;
  numero_os: string;
  cliente_nome: string;
  cliente_id?: number | null;
  status: "aberta" | "em_andamento" | "concluida" | "cancelada";
  descricao_servico: string | null;
  valor_total: number;
  data_abertura: string;
  orcado: number | null;
  tipo_pedido?: string | null;
  tem_gestao?: boolean | null;
  pedido_compra?: string | null;
  vendedor?: string | null;
  usa_relatorio_hh?: boolean | null;
};

type OsItemRow = {
  id: number;
  item_id: number;
  quantidade: number;
  valor_unitario: number;
  valor_total: number;
  baixa_estoque: boolean;
  itens: { nome: string; codigo_interno: string; tipo: string } | null;
};

type ItemPick = {
  id: number;
  codigo_interno: string;
  nome: string;
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
  fornecedores?: { nome?: string | null } | null;
};

type MovRow = {
  item_id: number;
  data_movimentacao: string;
};

type EstoqueRow = {
  item_id: number;
  quantidade_atual: number | null;
};

type SortValue = string | number | null;

type SortKey = "id" | "codigo" | "descricao" | "fornecedor" | "ultima" | "preco" | "estoque";
type SortDir = "asc" | "desc";

const statusBadge: Record<string, string> = {
  aberta: "bg-blue-500/15 text-blue-300 border-blue-500/30",
  em_andamento: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  concluida: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  cancelada: "bg-red-500/15 text-red-300 border-red-500/30",
};

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
  const readOnly = detailAccess.readOnly;
  const hideCustos = detailAccess.hideCustos;
  const hideTotais = detailAccess.hideTotais;

  const [os, setOs] = useState<OS | null>(null);
  const [rows, setRows] = useState<OsItemRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [isConcluding, setIsConcluding] = useState(false);
  const [showGestaoModal, setShowGestaoModal] = useState(false);
  const [temGestao, setTemGestao] = useState(false);
  const [gestaoItems, setGestaoItems] = useState<GestaoItem[]>([]);
  const [gestaoLoading, setGestaoLoading] = useState(false);
  const [gestaoSaving, setGestaoSaving] = useState(false);
  const [gestaoErr, setGestaoErr] = useState<string | null>(null);
  const [maoObraExtra, setMaoObraExtra] = useState<number>(0);
  const [hhTotal, setHhTotal] = useState<number>(0);
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [clienteHabilitaHH, setClienteHabilitaHH] = useState(false);

  const [showEdit, setShowEdit] = useState(false);
  const [editSaving, setEditSaving] = useState(false);
  const [editErr, setEditErr] = useState<string | null>(null);
  const [clienteId, setClienteId] = useState<number | null>(null);
  const [clienteNomeLivre, setClienteNomeLivre] = useState("");
  const [descricao, setDescricao] = useState("");
  const [pedidoCompra, setPedidoCompra] = useState("");
  const [tipoPedido, setTipoPedido] = useState<"servico" | "material">("servico");
  const [vendedor, setVendedor] = useState("");
  const [orcadoInput, setOrcadoInput] = useState("");
  const [usaRelatorioHH, setUsaRelatorioHH] = useState(false);

  const [activeTab, setActiveTab] = useState<"itens" | "hh">("itens");

  // adicionar item
  const [q, setQ] = useState("");
  const [searching, setSearching] = useState(false);
  const [found, setFound] = useState<ItemPick[]>([]);
  const [pick, setPick] = useState<ItemPick | null>(null);
  const [qty, setQty] = useState<string>("1");
  const [vunit, setVunit] = useState<number>(0);
  const [estoqueAtual, setEstoqueAtual] = useState<number | null>(null);
  const qtyRef = useRef<HTMLInputElement | null>(null);
  const [showLookup, setShowLookup] = useState(false);
  const [lookupNome, setLookupNome] = useState("");
  const [lookupFornecedor, setLookupFornecedor] = useState("");
  const [lookupRows, setLookupRows] = useState<ItemLookupRow[]>([]);
  const [lookupBusy, setLookupBusy] = useState(false);
  const [lookupErr, setLookupErr] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("id");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const isMateriaPrima = (pick?.finalidade ?? "") === "materia_prima";

  const locked = readOnly || os?.status === "concluida" || os?.status === "cancelada";
  const formatMoney = (v: number) =>
    Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  const toNum = (v: unknown) => {
    if (v == null) return 0;
    if (typeof v === "number") return v;
    if (typeof v === "string") return Number(v.replace(",", ".")) || 0;
    return 0;
  };

  const hhClientEnabled = clienteHabilitaHH;
  const hhEnabled = hhClientEnabled && Boolean(os?.usa_relatorio_hh);

  const editClienteHabilitaHH = useMemo(() => {
    if (!clienteId) return false;
    const found = clientes.find((c) => c.id === clienteId);
    if (found) return Boolean(found.habilita_hh);
    if (clienteId === (os?.cliente_id ?? null)) return hhClientEnabled;
    return false;
  }, [clienteId, clientes, hhClientEnabled, os?.cliente_id]);
  const canReadOs = Boolean(has("os.read"));

  useEffect(() => {
    if (!hhEnabled && activeTab !== "itens") {
      setActiveTab("itens");
    }
  }, [activeTab, hhEnabled]);

  const totais = (() => {
    const materiais = rows
      .filter((r) => r.itens?.tipo === "produto")
      .reduce((sum, r) => sum + Number(r.valor_total ?? 0), 0);

    // Mão de obra é CUSTO (vw_custo_mao_obra_os)
    const maoObra = Number(maoObraExtra || 0);

    // Cálculo de impostos:
    // - Se usa HH: 19% do total de HH
    // - Se material: 21% do valor de material
    // - Se serviço normal: 19% do total
    let impostos = 0;
    if (hhEnabled) {
      // HH: 19% sobre o total de HH
      impostos = Number(hhTotal || 0) * 0.19;
    } else if (rows.some((r) => r.itens?.tipo === "produto")) {
      // Tem material: 21% sobre material
      impostos = materiais * 0.21;
    } else {
      // Serviço normal: 19% sobre total (material + mão de obra)
      impostos = (materiais + maoObra) * 0.19;
    }

    // Total:
    // - Se HH habilitado: total de HH (que já inclui mão de obra HH)
    // - Senão: Material + Mão de obra + Impostos
    const total = hhEnabled ? Number(hhTotal || 0) : materiais + maoObra + impostos;

    return { materiais, maoObra, impostos, total };
  })();

  const orcado = toNum(os?.orcado);
  const totalAlert = orcado > 0 && totais.total >= orcado * 0.9;
  const totalClass = totalAlert ? "text-red-300 border-red-500/40" : "text-emerald-300 border-emerald-500/40";

  const calculateUnitPriceWithTaxes = (item: { preco_unitario?: number | null; aliquota_ipi?: number | null }) => {
    const base = Number(item.preco_unitario ?? 0);
    const ipi = Number(item.aliquota_ipi ?? 0);
    const ipiPerc = Number.isFinite(ipi) ? ipi : 0;
    const final = base * (1 + ipiPerc / 100);
    return Math.round(final * 100) / 100;
  };

  async function loadClientes() {
    const { data } = await supabase
      .from("clientes")
      .select("id,nome,ativo,habilita_hh")
      .eq("ativo", true)
      .order("nome", { ascending: true })
      .limit(500);

    setClientes((data ?? []) as Cliente[]);
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

    const { data: osData, error: osErr } = await applyTenant(
      supabase
        .from("ordens_servico")
        .select(
          "id,numero_os,cliente_nome,cliente_id,status,descricao_servico,valor_total,data_abertura,orcado,tipo_pedido,tem_gestao,pedido_compra,vendedor,usa_relatorio_hh"
        ),
      effectiveTenantId
    )
      .eq("id", osId)
      .single();

    if (osErr) {
      setErr(osErr.message);
      return;
    }
    const osRow = osData as OS;
    setOs(osRow);
    setTemGestao(Boolean(osRow.tem_gestao));
    await loadGestaoItens();

    // Carregar flag habilita_hh do cliente
    if (osRow.cliente_id) {
      const { data: clienteData } = await applyTenant(
        supabase.from("clientes").select("habilita_hh").eq("id", osRow.cliente_id).single(),
        effectiveTenantId
      );
      setClienteHabilitaHH(Boolean(clienteData?.habilita_hh));
    } else {
      setClienteHabilitaHH(false);
    }

    const { data: itemsData, error: itemsErr } = await applyTenant(
      supabase
        .from("os_itens")
        .select("id,item_id,quantidade,valor_unitario,valor_total,baixa_estoque,itens(nome,codigo_interno,tipo)"),
      effectiveTenantId
    )
      .eq("os_id", osId)
      .order("id", { ascending: false });

    if (itemsErr) setErr(itemsErr.message);
    else setRows((itemsData ?? []) as unknown as OsItemRow[]);

    const { data: maoData, error: maoErr } = await supabase
      .from("vw_custo_mao_obra_os")
      .select("custo_mao_obra")
      .eq("os_id", osId)
      .maybeSingle();

    if (maoErr) {
      console.error(maoErr);
      setMaoObraExtra(0);
    } else {
      setMaoObraExtra(Number(maoData?.custo_mao_obra ?? 0));
    }

    const { data: hhData, error: hhErr } = await supabase
      .from("vw_hh_total_os")
      .select("total_hh")
      .eq("os_id", osId)
      .maybeSingle();

    if (hhErr) {
      console.error(hhErr);
      setHhTotal(0);
    } else {
      setHhTotal(Number((hhData as { total_hh?: number | null } | null)?.total_hh ?? 0));
    }
  }

  useEffect(() => {
    if (!detailAccess.canView) return;
    void loadClientes();
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detailAccess.canView, osId, tenantId, empresaId]);

  const closeGestaoModal = useCallback(
    (reset = true) => {
      setShowGestaoModal(false);
      if (reset && os) setTemGestao(Boolean(os.tem_gestao));
    },
    [os]
  );

  const openEditModal = useCallback(() => {
    if (readOnly) return;
    if (!os) return;
    setShowEdit(true);
    setClienteId(os.cliente_id ?? null);
    setClienteNomeLivre(os.cliente_nome ?? "");
    setDescricao(os.descricao_servico ?? "");
    setPedidoCompra(os.pedido_compra ?? "");
    setTipoPedido(os.tipo_pedido as "servico" | "material");
    setVendedor(os.vendedor ?? "");
    setOrcadoInput(String(os.orcado ?? ""));
    setUsaRelatorioHH(Boolean(os.usa_relatorio_hh) && hhClientEnabled);
    setEditErr(null);
  }, [hhClientEnabled, os, readOnly]);

  const closeEditModal = useCallback(() => {
    setShowEdit(false);
    setEditErr(null);
  }, []);

  async function saveEdit() {
    if (readOnly) return;
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
        cliente_nome: clienteNomeFinal,
        descricao_servico: descricao.trim() || null,
        pedido_compra: pedidoCompra.trim() || null,
        tipo_pedido: tipoPedido,
        vendedor: vendedor.trim() || null,
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

  async function setStatus(newStatus: OS["status"]) {
    if (!os) return;

    if (newStatus === "cancelada") {
      const ok = confirm("Cancelar esta OS? Depois disso, a edição será bloqueada.");
      if (!ok) return;
    }

    setBusy(true);
    setErr(null);

    const patch: { status: OS["status"]; atualizado_em: string; data_conclusao?: string } = {
      status: newStatus,
      atualizado_em: new Date().toISOString(),
    };
    if (newStatus === "concluida") patch.data_conclusao = new Date().toISOString();

    const { error } = await supabase
      .from("ordens_servico")
      .update(patch)
      .eq("id", os.id);

    setBusy(false);
    if (error) return setErr(error.message);

    await load();
  }

  async function concluirOs() {
    if (!os) return;
    const ok = confirm("Concluir OS? Isso marcará projetos e execução como 100%.");
    if (!ok) return;

    setIsConcluding(true);
    setErr(null);
    setOkMsg(null);

    const osIdNumber = Number(os.id);
    const { error } = await supabase.rpc("concluir_os", { os_id_param: osIdNumber });

    setIsConcluding(false);

    if (error) {
      setErr(error.message);
      return;
    }

    setOkMsg("OS concluída");
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

    const baseSelect = fornecedorTerm
      ? "id,codigo_interno,nome,tipo,finalidade,preco_unitario,aliquota_ipi,controla_estoque,fornecedores!itens_tenant_empresa_fornecedor_fk!inner(nome)"
      : "id,codigo_interno,nome,tipo,finalidade,preco_unitario,aliquota_ipi,controla_estoque,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)";

    let query = supabase.from("itens").select(baseSelect).eq("ativo", true);

    if (nomeTerm) query = query.ilike("nome", `%${nomeTerm}%`);
    if (fornecedorTerm) query = query.ilike("fornecedores.nome", `%${fornecedorTerm}%`);

    const { data, error } = await query.order("nome", { ascending: true }).limit(50);

    if (error) {
      setLookupErr(error.message);
      setLookupRows([]);
      setLookupBusy(false);
      return;
    }

    const baseRows = (data ?? []) as ItemLookupBaseRow[];
    const ids = baseRows.map((r) => r.id);
    const ultimaMap = new Map<number, string>();

    const stockMap = new Map<number, number>();

    if (ids.length > 0) {
      const { data: movData, error: movErr } = await supabase
        .from("movimentacoes")
        .select("item_id,data_movimentacao")
        .eq("tipo", "entrada")
        .in("item_id", ids)
        .order("data_movimentacao", { ascending: false });

      if (!movErr) {
        const movRows = (movData ?? []) as MovRow[];
        movRows.forEach((m) => {
          if (!ultimaMap.has(m.item_id)) ultimaMap.set(m.item_id, m.data_movimentacao);
        });
      }

      const { data: estData } = await supabase
        .from("estoque")
        .select("item_id,quantidade_atual")
        .in("item_id", ids);
      const estoqueRows = (estData ?? []) as EstoqueRow[];
      estoqueRows.forEach((e) => {
        stockMap.set(e.item_id, Number(e.quantidade_atual ?? 0));
      });
    }

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
        fornecedor: r.fornecedores?.nome ?? null,
        ultima_entrada: ultimaMap.get(r.id) ?? null,
        estoque_atual: stockMap.has(r.id) ? stockMap.get(r.id)! : null,
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

  function openLookupModal() {
    setShowLookup(true);
    setLookupErr(null);
    setLookupRows([]);
    setLookupNome("");
    setLookupFornecedor("");
    handleSearch("", "");
  }

  async function searchItems() {
    setErr(null);
    setFound([]);

    const term = q.trim();
    const id = Number(term);
    if (!term || !Number.isFinite(id) || id <= 0) {
      openLookupModal();
      return;
    }

    setSearching(true);

    const { data, error } = await supabase
      .from("itens")
      .select("id,codigo_interno,nome,tipo,finalidade,preco_unitario,aliquota_ipi,controla_estoque")
      .eq("id", id)
      .maybeSingle();

    setSearching(false);

    if (error || !data) {
      setErr("Item nao encontrado pelo ID informado. Use a busca por nome/fabricante.");
      openLookupModal();
      return;
    }

    pickItem(data as ItemPick);
  }

  function pickItem(it: ItemPick) {
    setPick(it);
    setFound([]);
    setQ(`${it.codigo_interno} - ${it.nome}`);
    setQty("1");
    setVunit(calculateUnitPriceWithTaxes(it));
    setEstoqueAtual(
      typeof (it as ItemLookupRow).estoque_atual === "number"
        ? Number((it as ItemLookupRow).estoque_atual ?? 0)
        : null
    );
    if (Number.isFinite(it.id) && it.id > 0) {
      void (async () => {
        const { data } = await supabase
          .from("estoque")
          .select("quantidade_atual")
          .eq("item_id", it.id)
          .maybeSingle();
        setEstoqueAtual(data?.quantidade_atual ?? null);
      })();
    }
    setTimeout(() => {
      qtyRef.current?.focus();
      qtyRef.current?.select();
    }, 0);
  }

  async function addItem() {
    if (!pick) return setErr("Selecione um item.");
    if (!empresaId) return setErr("Selecione uma empresa antes de adicionar itens.");
    if ((pick.finalidade ?? "") !== "materia_prima") return setErr("Apenas itens de materia-prima podem ser adicionados.");
    const qtyNumber = parseDecimalBR(qty);
    if (!Number.isFinite(qtyNumber) || qtyNumber <= 0) return setErr("Quantidade invalida.");
    if (vunit < 0) return setErr("Valor unitario invalido.");

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
      p_baixa_estoque: Boolean(pick.controla_estoque),
      p_realizado_por: userEmail,
      p_motivo: "Adicao pela tela da OS (baixa imediata)",
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
  }

  if (te.loading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando...</div>;
  }

  if (!detailAccess.canView) {
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

            {os?.status && (
              <span
                className={[
                  "inline-flex items-center px-2 py-1 rounded-md border text-xs",
                  statusBadge[os.status] ?? "bg-zinc-500/10 text-zinc-300 border-zinc-500/30",
                ].join(" ")}
              >
                {os.status}
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

          <button
            onClick={concluirOs}
            disabled={busy || locked || isConcluding}
            className="px-3 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
          >
            {isConcluding ? "Concluindo..." : "Concluir"}
          </button>

          <button
            onClick={() => setStatus("em_andamento")}
            disabled={busy || readOnly || isConcluding}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Em andamento
          </button>

          <button
            onClick={() => setStatus("cancelada")}
            disabled={busy || locked || isConcluding}
            className="px-3 py-2 rounded-md bg-red-300 text-red-950 hover:bg-red-200 font-medium"
          >
            Cancelar
          </button>
        </div>
      </div>

      {locked && (
        <div className="border border-zinc-800 rounded-xl p-3 bg-zinc-950 text-sm text-zinc-300">
          Esta OS está <b>{os?.status}</b>. Edição bloqueada.
        </div>
      )}

      {!hideCustos && <MaoObraCard osId={osId} />}

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

      {!hhEnabled && (
        <>
          {/* Adicionar item */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div>
            <div className="font-medium">Adicionar item</div>
            <div className="text-sm text-zinc-400 mt-1">
              Produto/servico/despesa. Baixa de estoque segue o cadastro do item.
            </div>
          </div>

          <button
            onClick={addItem}
            disabled={busy || locked || !isMateriaPrima}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            {busy ? "Aguarde..." : "Adicionar"}
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-6 gap-3 mt-4">
          <div className="md:col-span-3 space-y-1 relative">
            <div className="text-xs text-zinc-400">Buscar item</div>
            <div className="flex gap-2">
              <input
                className="w-full px-3 py-2"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="ID do item (ex: 123). Enter abre localizacao se nao souber."
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    searchItems();
                  }
                }}
                disabled={locked}
                aria-label="Buscar item"
                title="Buscar item"
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
              aria-label="Quantidade do item"
              title="Quantidade do item"
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

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">Estoque</div>
            <div className="w-full px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-zinc-200">
              {typeof estoqueAtual === "number" ? formatDecimalBR(estoqueAtual, 3) : "-"}
            </div>
          </div>
        </div>

        {pick && (
          <div className="text-sm text-zinc-300 mt-3">
            Selecionado: <b>[{pick.codigo_interno}] {pick.nome}</b> ({pick.tipo})
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
                  onChange={(e) => setDescricao(e.target.value)}
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
            className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4"
            role="dialog"
            aria-modal="true"
            aria-labelledby="gestao-title"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between gap-3">
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
                Gestao desabilitada para esta OS. Ative o controle acima para editar os itens. Valores existentes serao mantidos.
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

            <div className="flex items-center justify-end gap-2 pt-2">
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

      {!hhEnabled && (
        <>
          {showLookup && (
            <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto">
              <div className="min-h-full w-full flex items-start justify-center p-4 md:items-center">
                <div className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl flex flex-col gap-4 max-h-[90dvh] h-[90dvh] min-h-0 overflow-hidden">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <div className="text-lg font-semibold">Localizar item</div>
                      <div className="text-sm text-zinc-400">Filtre por nome ou fabricante para localizar o ID.</div>
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
          <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
            <table className="w-full text-sm">
              <thead className="bg-zinc-900/60">
                <tr className="text-left text-zinc-200">
                  <th className="px-4 py-3">ID</th>
                  <th className="px-4 py-3">Item</th>
                  <th className="px-4 py-3 text-right">Qtd</th>
                  <th className="px-4 py-3 text-right">V.Unit</th>
                  <th className="px-4 py-3 text-right">Total</th>
                  <th className="px-4 py-3 text-center">Baixa</th>
                  <th className="px-4 py-3 text-center">Ações</th>
                </tr>
              </thead>

              <tbody className="divide-y divide-zinc-800">
                {rows.map((r) => (
              <tr key={r.id} className="hover:bg-zinc-900/40">
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

                <td className="px-4 py-3 text-center">{r.baixa_estoque ? "✅" : "—"}</td>

                <td className="px-4 py-3 text-center">
                  <button
                    onClick={() => removeItem(r.id)}
                    disabled={busy || locked}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  >
                    Remover
                  </button>
                </td>
              </tr>
            ))}

            {rows.length === 0 && (
              <tr>
                <td className="px-4 py-6 text-zinc-400" colSpan={7}>
                  Nenhum item ainda.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
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
                    onChange={(e) => setDescricao(e.target.value)}
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

      {clienteHabilitaHH && (
        <RelatorioHHSection
          osId={osId}
          osDetail={{ cliente_id: os?.cliente_id ?? null }}
          osStatus={os?.status ?? null}
          usaRelatorioHh={os?.usa_relatorio_hh ?? null}
          enabled={hhEnabled}
          clienteHabilitaHH={clienteHabilitaHH}
          effectiveTenantId={effectiveTenantId}
          effectiveEmpresaId={effectiveEmpresaId}
        />
      )}
    </div>
  );
}

