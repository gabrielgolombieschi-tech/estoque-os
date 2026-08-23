"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { useSessionReady } from "@/lib/auth/useSessionReady";
import { getOsListAccess } from "@/lib/auth/osAccess";
import { getHorasTrabalhadasEfetivas, getValorTotalEfetivo } from "@/lib/hh/hhLancamentosCalc";
import { fetchFaturadoByOs } from "@/lib/os/faturadoPorOs";
import ResponsavelAprovacaoSelect from "@/components/os/ResponsavelAprovacaoSelect";

type Cliente = { id: number; nome: string; ativo: boolean; habilita_hh: boolean };

type UsuarioVendedor = {
  id: string;
  auth_user_id: string;
  nome: string;
  email: string;
};

type UsuariosSolicitantesApiResponse = { usuarios?: UsuarioVendedor[]; error?: string };

type OS = {
  id: number;
  numero_os: string;
  pedido_compra: string | null;
  cliente_nome: string;
  cliente_id: number | null;
  status: string;
  criado_por?: string | null;
  responsavel_aprovacao_id?: string | null;
  descricao_servico: string | null;
  data_abertura: string;
  valor_total: number;
  orcado: number | null;
  custo: number | null;
  tipo_pedido?: string | null;
  usa_relatorio_hh?: boolean | null;
};

type OsItemTotalRow = {
  os_id: number;
  valor_total: number | null;
  itens?: { tipo?: string | null } | { tipo?: string | null }[] | null;
};

type MaoObraRow = {
  os_id: number;
  custo_mao_obra: number | null;
};

type HHTotalRow = {
  os_id: number;
  total_hh: number | null;
};

type HhLancamentoTotalRow = {
  os_id: number;
  entrada_1: string | null;
  saida_1: string | null;
  entrada_2: string | null;
  saida_2: string | null;
  hora_entrada: string | null;
  hora_saida: string | null;
  horas_trabalhadas: number | null;
  valor_hora: number | null;
  valor_total: number | null;
};

type OsClienteRow = {
  cliente_id: number | null;
  cliente_nome: string | null;
};

type OsClienteFiltroRow = {
  cliente_nome: string | null;
  tipo_pedido?: string | null;
  usa_relatorio_hh?: boolean | null;
};

type TipoFiltro = "todos_sem_hh" | "todas" | "hh" | "servico" | "material";

function normalizeSearchTerm(s: unknown) {
  return String(s ?? "")
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

const statusBadge: Record<string, string> = {
  aberta: "bg-blue-500/15 text-blue-300 border-blue-500/30",
  em_andamento: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  concluida: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  cancelada: "bg-red-500/15 text-red-300 border-red-500/30",
};

type GestaoTipo = "projeto" | "execucao";
type GestaoArea = "eletrico" | "mecanico" | "seguranca" | "software";

type GestaoItem = {
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
const buildGestaoDefaults = (): GestaoItem[] =>
  gestaoDefs.map((def) => ({
    item_tipo: def.item_tipo,
    area: def.area,
    habilitado: false,
    responsavel_id: null,
    data_prevista: null,
    progresso_percent: 0,
  }));

export default function OsListPage() {
  const router = useRouter();
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { has } = usePermissions();
  const te = useTenantEmpresa();
  const { tenantId, empresaId, loading: tenantLoading } = te;
  const { session, sessionReady } = useSessionReady();
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

  const canReadOs = Boolean(has("os.read"));
  const canWriteOs = Boolean(has("os.write"));

  const isApontamentoRh = useMemo(
    () => String(empresaPapel ?? "").toUpperCase() === "APONTAMENTO_RH",
    [empresaPapel]
  );

  const canGestaoWrite = (has("os_gestao.write") ?? true) || 
    (empresaPapel && ["ADMIN", "DIRETOR", "FINANCEIRO", "COORDENACAO", "FATURAMENTO"].includes(String(empresaPapel).toUpperCase()));

  const osAccess = useMemo(() => getOsListAccess(empresaPapel), [empresaPapel]);
  const canView = canReadOs || osAccess.canView;
  const readOnly = !canWriteOs;
  const hideValorPedido = osAccess.hideValorPedido;
  const debugEnabled = process.env.NODE_ENV !== "production";
  const clientesReqIdRef = useRef(0);
  const osReqIdRef = useRef(0);
  const [loading, setLoading] = useState(true);
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [usuariosVendedores, setUsuariosVendedores] = useState<UsuarioVendedor[]>([]);
  const [usuariosVendedoresLoading, setUsuariosVendedoresLoading] = useState(false);
  const [usuariosVendedoresError, setUsuariosVendedoresError] = useState<string | null>(null);
  const [rows, setRows] = useState<OS[]>([]);
  const [status, setStatus] = useState("em_andamento");
  const [clienteFiltro, setClienteFiltro] = useState<string>("");
  const [clienteFiltroOptions, setClienteFiltroOptions] = useState<string[]>([]);
  const [tipoFiltro, setTipoFiltro] = useState<TipoFiltro>("todos_sem_hh");
  const [err, setErr] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [maoObraPorOs, setMaoObraPorOs] = useState<Record<number, number>>({});
  const [materiaisPorOs, setMateriaisPorOs] = useState<Record<number, number>>({});
  const [hhTotalPorOs, setHhTotalPorOs] = useState<Record<number, number>>({});
  const [hhPedidoPorOs, setHhPedidoPorOs] = useState<Record<number, number>>({});
  const [faturadoPorOs, setFaturadoPorOs] = useState<Record<number, number>>({});

  // criacao
  const [creating, setCreating] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [clienteId, setClienteId] = useState<number | null>(null);
  const [descricao, setDescricao] = useState("");
  const [pedidoCompra, setPedidoCompra] = useState("");
  const [tipoPedido, setTipoPedido] = useState<"servico" | "material">("servico");
  const [vendedor, setVendedor] = useState("");
  const [responsavelAprovacaoId, setResponsavelAprovacaoId] = useState<string | null>(null);
  const [orcado, setOrcado] = useState("");
  const [temGestao, setTemGestao] = useState(false);
  const [usaRelatorioHH, setUsaRelatorioHH] = useState(false);
  const [gestaoItems, setGestaoItems] = useState<GestaoItem[]>(() => buildGestaoDefaults());

  const formatMoney = (value: number) =>
    Number(value || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  const clienteHabilitaHH = useMemo(() => {
    if (!clienteId) return false;
    return Boolean(clientes.find((c) => c.id === clienteId)?.habilita_hh);
  }, [clienteId, clientes]);
  const clientesNovaOsHh = useMemo(
    () => (isApontamentoRh ? clientes : clientes.filter((cliente) => cliente.habilita_hh)),
    [clientes, isApontamentoRh]
  );
  const clienteSelecionadoNaoHabilitaHH = Boolean(clienteId && !clienteHabilitaHH && !isApontamentoRh);

  const logDebug = (...args: unknown[]) => {
    if (debugEnabled) console.debug(...args);
  };

  const shouldShowRowForTipoFiltro = (row: OS, filtro: TipoFiltro) => {
    const isHh = Boolean(row.usa_relatorio_hh);

    if (filtro === "todos_sem_hh") return !isHh;
    if (filtro === "hh") return isHh;
    if (filtro === "servico") return row.tipo_pedido === "servico" && !isHh;
    if (filtro === "material") return row.tipo_pedido === "material";
    return true;
  };

  async function loadClientes() {
    if (!sessionReady || !session?.access_token) return;
    const reqId = ++clientesReqIdRef.current;
    logDebug("[OS] loadClientes:start", {
      tenantId,
      empresaId,
      effectiveTenantId,
      effectiveEmpresaId,
      sessionReady,
      hasSession: !!session?.access_token,
    });

    const loadFromOs = async () => {
      const { data: osData, error: osErr } = await applyTenantEmpresa(
        supabase
          .from("ordens_servico")
          .select("cliente_id,cliente_nome")
          .order("id", { ascending: false })
          .limit(1000),
        effectiveTenantId,
        effectiveEmpresaId
      );
      if (reqId !== clientesReqIdRef.current) return;
      if (osErr) {
        logDebug("[OS] loadClientes:fallback:error", { message: osErr.message });
        return;
      }

      const unique = new Map<number, Cliente>();
      ((osData ?? []) as unknown as OsClienteRow[]).forEach((r) => {
        const id = r.cliente_id;
        const nome = (r.cliente_nome ?? "").trim();
        if (!id) {
          return;
        }
        if (!unique.has(id)) {
          unique.set(id, {
            id,
            nome: (nome || `Cliente ${id}`).trim(),
            ativo: true,
            habilita_hh: false,
          });
        }
      });

      const list = Array.from(unique.values()).sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
      logDebug("[OS] loadClientes:fallback:ok", { count: list.length });
      setClientes(list);
    };

    const { data, error } = await applyTenantEmpresa(
      supabase.from("clientes").select("id,nome,ativo,habilita_hh").eq("ativo", true).order("nome", { ascending: true }).limit(500),
      effectiveTenantId,
      effectiveEmpresaId
    );
    if (reqId !== clientesReqIdRef.current) return;

    if (error) {
      // Para alguns papéis (ex.: APONTAMENTO_RH), a RLS de clientes pode bloquear via can(),
      // enquanto ordens_servico usa can__legacy_40734. Nesses casos, não quebrar a tela:
      // montar a lista a partir das OS visíveis.
      logDebug("[OS] loadClientes:error (fallback to ordens_servico)", { message: error.message });
      await loadFromOs();
      return;
    }

    const next = (data ?? []) as unknown as Cliente[];
    if (next.length === 0) {
      logDebug("[OS] loadClientes:empty (fallback to ordens_servico)");
      await loadFromOs();
      return;
    }

    setClientes(next);
  }

  async function loadClienteFiltroOptions() {
    if (!sessionReady || !session?.access_token) return;

    let query = applyTenantEmpresa(
      supabase
        .from("ordens_servico")
        .select("cliente_nome,tipo_pedido,usa_relatorio_hh")
        .order("cliente_nome", { ascending: true }),
      effectiveTenantId,
      effectiveEmpresaId
    );

    if (status !== "todas") query = query.eq("status", status);

    const { data, error } = await query;
    if (error) {
      logDebug("[OS] loadClienteFiltroOptions:error", { message: error.message });
      return;
    }

    const options = new Set<string>();
    ((data ?? []) as unknown as OsClienteFiltroRow[])
      .filter((row) => shouldShowRowForTipoFiltro(row as OS, tipoFiltro))
      .forEach((row) => {
        const nome = String(row.cliente_nome ?? "").trim();
        if (nome) options.add(nome);
      });

    setClienteFiltroOptions(Array.from(options.values()).sort((a, b) => a.localeCompare(b, "pt-BR")));
  }

  async function load() {
    if (!sessionReady || !session?.access_token) {
      logDebug("[OS] load:return early (sessionReady or session missing)", {
        sessionReady,
        hasSession: !!session?.access_token,
      });
      return;
    }

    const reqId = ++osReqIdRef.current;
    setLoading(true);
    setErr(null);
    setMaoObraPorOs({});
    setMateriaisPorOs({});
    setHhTotalPorOs({});
    setHhPedidoPorOs({});
    logDebug("[OS] load:start", {
      tenantId,
      empresaId,
      effectiveTenantId,
      effectiveEmpresaId,
      sessionReady,
      hasSession: !!session?.access_token,
      status,
      clienteFiltro,
      tipoFiltro,
      reqId,
    });

    let q = applyTenantEmpresa(
      supabase
        .from("ordens_servico")
        .select(
          "id,numero_os,pedido_compra,cliente_nome,cliente_id,status,criado_por,responsavel_aprovacao_id,descricao_servico,data_abertura,valor_total,orcado,custo,tipo_pedido,usa_relatorio_hh"
        )
        .order("id", { ascending: false }),
      effectiveTenantId,
      effectiveEmpresaId
    );

    if (status !== "todas") q = q.eq("status", status);
    if (tipoFiltro === "hh") q = q.eq("usa_relatorio_hh", true);
    if (tipoFiltro === "servico") q = q.eq("tipo_pedido", "servico");
    if (tipoFiltro === "material") q = q.eq("tipo_pedido", "material");
    const clienteTerm = clienteFiltro.trim();
    if (clienteTerm) {
      const normalizedTerm = normalizeSearchTerm(clienteTerm);
      const matchingClienteIds = clientes
        .filter((c) => normalizeSearchTerm(c.nome).includes(normalizedTerm))
        .map((c) => c.id)
        .filter((id) => Number.isFinite(id));

      const clauses = [`cliente_nome.ilike.%${clienteTerm}%`];
      if (matchingClienteIds.length > 0) {
        clauses.unshift(`cliente_id.in.(${matchingClienteIds.join(",")})`);
      }
      q = q.or(clauses.join(","));
    }

    const { data, error } = await q;
    if (reqId !== osReqIdRef.current) {
      logDebug("[OS] load:stale request after initial query");
      return;
    }
    if (error) {
      logDebug("[OS] load:error", { error: error.message });
      setErr(error.message);
      setLoading(false);
      return;
    }

    const osList = ((data ?? []) as unknown as OS[]).filter((row) => shouldShowRowForTipoFiltro(row, tipoFiltro));
    setRows(osList);
    logDebug("[OS] load:rows", { count: osList.length, reqId });

    const osIds = osList.map((r) => r.id);
    if (osIds.length > 0) {
      const { data: itensData } = await applyTenantEmpresa(
        supabase.from("os_itens").select("os_id,valor_total,itens(tipo)").in("os_id", osIds),
        effectiveTenantId,
        effectiveEmpresaId
      );
      if (reqId !== osReqIdRef.current) return;

      const materiaisTotals: Record<number, number> = {};
      const itemRows = (itensData ?? []) as OsItemTotalRow[];
      itemRows.forEach((row) => {
        const osId = Number(row.os_id);
        if (!Number.isFinite(osId)) return;
        const valor = Number(row.valor_total ?? 0);
        const itensTipo = Array.isArray(row.itens)
          ? row.itens[0]?.tipo
          : row.itens?.tipo;
        if (itensTipo === "produto") {
          const prevMat = materiaisTotals[osId] ?? 0;
          materiaisTotals[osId] = prevMat + valor;
        }
      });
      setMateriaisPorOs(materiaisTotals);

      // View sem tenant/empresa; não aplicar scope para evitar erro de coluna inexistente.
      const { data: maoData } = await supabase
        .from("vw_custo_mao_obra_os")
        .select("os_id,custo_mao_obra")
        .in("os_id", osIds);
      if (reqId !== osReqIdRef.current) return;

      const maoTotals: Record<number, number> = {};
      const maoRows = (maoData ?? []) as MaoObraRow[];
      maoRows.forEach((row) => {
        const osId = Number(row.os_id);
        if (!Number.isFinite(osId)) return;
        maoTotals[osId] = Number(row.custo_mao_obra ?? 0);
      });
      setMaoObraPorOs(maoTotals);

      // Totais de HH por OS
      const { data: hhData } = await supabase.from("vw_hh_total_os").select("os_id,total_hh").in("os_id", osIds);
      if (reqId !== osReqIdRef.current) return;

      const hhTotals: Record<number, number> = {};
      const hhRows = (hhData ?? []) as HHTotalRow[];
      hhRows.forEach((row) => {
        const osId = Number(row.os_id);
        if (!Number.isFinite(osId)) return;
        hhTotals[osId] = Number(row.total_hh ?? 0);
      });
      setHhTotalPorOs(hhTotals);

      // Valor do pedido HH calculado (para bater com PDF): soma(valor_hora * horas_efetivas)
      // horas_efetivas segue a mesma regra do PDF (2 períodos ou entrada/saída; fallback horas_trabalhadas).
      try {
        const hhOsIds = osList
          .filter((r) => Boolean(r.usa_relatorio_hh))
          .map((r) => Number(r.id))
          .filter((v) => Number.isFinite(v) && v > 0);

        if (hhOsIds.length === 0) {
          setHhPedidoPorOs({});
        } else {
          const { data: hhCalcData, error: hhCalcErr } = await applyTenantEmpresa(
            supabase
              .from("hh_lancamentos")
              .select(
                "os_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,horas_trabalhadas,valor_hora,valor_total"
              )
              .in("os_id", hhOsIds),
            effectiveTenantId,
            effectiveEmpresaId
          );
          if (reqId !== osReqIdRef.current) return;
          if (hhCalcErr) throw hhCalcErr;

          const pedidoTotals: Record<number, number> = {};
          ((hhCalcData ?? []) as HhLancamentoTotalRow[]).forEach((row) => {
            const osId = Number(row.os_id);
            if (!Number.isFinite(osId)) return;

            const horasEfetivas = getHorasTrabalhadasEfetivas(row);
            const total = getValorTotalEfetivo(row, horasEfetivas);
            pedidoTotals[osId] = (pedidoTotals[osId] ?? 0) + (Number.isFinite(total) ? total : 0);
          });

          Object.keys(pedidoTotals).forEach((k) => {
            const osId = Number(k);
            const v = pedidoTotals[osId] ?? 0;
            pedidoTotals[osId] = Math.round(v * 100) / 100;
          });

          setHhPedidoPorOs(pedidoTotals);
        }
      } catch (e) {
        console.warn("[OS] hhPedidoPorOs: fallback", e);
        setHhPedidoPorOs({});
      }

      try {
        const faturado = await fetchFaturadoByOs({
          supabase,
          tenantId: effectiveTenantId,
          empresaId: effectiveEmpresaId,
          osIds,
        });
        if (reqId !== osReqIdRef.current) return;
        setFaturadoPorOs(faturado);
      } catch (e) {
        console.warn("[OS] faturadoPorOs: fallback", e);
        setFaturadoPorOs({});
      }
    }
    if (reqId === osReqIdRef.current) {
      logDebug("[OS] load:end", { reqId, rowsCount: (data ?? []).length, hasItens: osIds.length > 0 });
      setLoading(false);
    } else {
      logDebug("[OS] load:stale request (not updating)", { reqId, currentReqId: osReqIdRef.current });
    }
  }

  useEffect(() => {
    logDebug("[OS] useEffect:triggered", {
      tenantLoading,
      sessionReady,
      hasSession: !!session?.access_token,
      tenantId,
      empresaId,
      effectiveTenantId,
      effectiveEmpresaId,
      status,
    });

    // NÃO aguardar tenantLoading ficar false.
    // Sempre usar effectiveTenantId/effectiveEmpresaId (com fallback).
    if (!sessionReady || !session?.access_token) {
      logDebug("[OS] useEffect:return (sessionReady or session missing)", {
        sessionReady,
        hasSession: !!session?.access_token,
      });
      return;
    }

    if (!canView) return;

    logDebug("[OS] useEffect:calling loadClientes and load");
    void loadClientes();
    void loadClienteFiltroOptions();
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canView, tenantId, empresaId, sessionReady, session?.access_token, status, clienteFiltro, tipoFiltro]);

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!sessionReady || !session?.access_token || !canWriteOs) {
        if (!active) return;
        setUsuariosVendedores([]);
        setUsuariosVendedoresError(null);
        setUsuariosVendedoresLoading(false);
        return;
      }

      setUsuariosVendedoresLoading(true);
      setUsuariosVendedoresError(null);

      try {
        const { data: sess } = await supabase.auth.getSession();
        const token = sess.session?.access_token ?? null;
        if (!token) throw new Error("Sessao expirada. Faca login novamente.");

        const query = `tenantId=${encodeURIComponent(effectiveTenantId)}&empresaId=${encodeURIComponent(effectiveEmpresaId)}`;
        const res = await fetch(`/api/estoque/usuarios-solicitantes?${query}`, {
          headers: { authorization: `Bearer ${token}` },
        });

        const json = (await res.json().catch(() => null)) as UsuariosSolicitantesApiResponse | null;
        if (!active) return;

        if (!res.ok) {
          const msg = typeof json?.error === "string" ? json.error : "Erro ao carregar usuarios.";
          setUsuariosVendedores([]);
          setUsuariosVendedoresError(msg);
          setUsuariosVendedoresLoading(false);
          return;
        }

        const next = (Array.isArray(json?.usuarios) ? json.usuarios : [])
          .map((row) => ({
            id: String(row.id ?? ""),
            auth_user_id: String((row as UsuarioVendedor & { auth_user_id?: string | null }).auth_user_id ?? "").trim(),
            nome: String(row.nome ?? "").trim(),
            email: String(row.email ?? "").trim(),
          }))
          .filter((row) => row.id && row.auth_user_id && row.nome);

        setUsuariosVendedores(next);
        setUsuariosVendedoresLoading(false);
        setVendedor((prev) => (prev && !next.some((row) => row.nome === prev) ? "" : prev));
      } catch (e: unknown) {
        if (!active) return;
        const message = e instanceof Error ? e.message : "Erro ao carregar usuarios.";
        setUsuariosVendedores([]);
        setUsuariosVendedoresError(message);
        setUsuariosVendedoresLoading(false);
      }
    };

    void run();
    return () => {
      active = false;
    };
  }, [canWriteOs, effectiveEmpresaId, effectiveTenantId, session?.access_token, sessionReady, supabase]);

  useEffect(() => {
    if (!canGestaoWrite && temGestao) setTemGestao(false);
  }, [canGestaoWrite, temGestao]);

  async function gerarNumeroOs(tenant: string, empresa: string): Promise<string> {
    const { data } = await applyTenantEmpresa(
      supabase.from("ordens_servico").select("numero_os").order("id", { ascending: false }).limit(1).maybeSingle(),
      tenant,
      empresa
    );

    const last = Number(data?.numero_os ?? 0);
    const proximo = Number.isFinite(last) && last > 0 ? last + 1 : 1;
    return String(proximo);
  }

  async function createOS() {
    setErr(null);
    setOkMsg(null);

    if (!canWriteOs) return setErr("Sem permissão para criar OS.");
    if (!clienteId) return setErr("Selecione um cliente.");
    if (!clienteHabilitaHH && !isApontamentoRh) {
      return setErr("Cliente nao habilitado para HH. Crie OS comum a partir do orcamento.");
    }

    const orcadoValor = Number(orcado || 0);
    if (!Number.isFinite(orcadoValor) || orcadoValor < 0) return setErr("Informe um valor orcado valido.");

    const gestaoPayload = temGestao
      ? gestaoItems.map((it) => {
          const progress = Number(it.progresso_percent ?? 0);
          return {
            item_tipo: it.item_tipo,
            area: it.area,
            habilitado: !!it.habilitado,
            responsavel_id: it.responsavel_id?.trim() ? it.responsavel_id.trim() : null,
            data_prevista: it.data_prevista ? it.data_prevista : null,
            progresso_percent: Number.isFinite(progress) ? Math.max(0, Math.min(100, Math.trunc(progress))) : NaN,
          };
        })
      : [];

    if (temGestao && gestaoPayload.some((p) => !Number.isFinite(p.progresso_percent))) {
      return setErr("Progresso deve estar entre 0 e 100.");
    }

    if (temGestao && !canGestaoWrite) {
      return setErr("Sem permissao para habilitar gestao nesta OS.");
    }

    setCreating(true);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const clienteSelecionado = clientes.find((c) => c.id === clienteId) ?? null;
    const clienteNomeFinal = (clienteSelecionado?.nome ?? "").trim();
    if (!clienteNomeFinal) {
      setCreating(false);
      setErr("Cliente selecionado invalido.");
      return;
    }

    if (tenantLoading) {
      setCreating(false);
      setErr("Tenant ativo nao encontrado.");
      return;
    }

    const numeroGerado = await gerarNumeroOs(effectiveTenantId, effectiveEmpresaId);
    const usaRelatorioHHFinal = true;

    const { data, error } = await supabase
      .from("ordens_servico")
      .insert({
        tenant_id: effectiveTenantId,
        empresa_id: effectiveEmpresaId,
        numero_os: numeroGerado,
        cliente_id: clienteId,
        cliente_nome: clienteNomeFinal,
        descricao_servico: descricao.trim() ? descricao.trim().toLocaleUpperCase("pt-BR") : null,
        pedido_compra: pedidoCompra.trim() || null,
        tipo_pedido: "servico",
        vendedor: vendedor.trim() || null,
        orcado: orcadoValor,
        tem_gestao: temGestao,
        usa_relatorio_hh: usaRelatorioHHFinal,
        status: "em_andamento",
        criado_por: userEmail,
        responsavel_aprovacao_id: responsavelAprovacaoId,
      })
      .select("id")
      .single();

    if (error) {
      setCreating(false);
      return setErr(error.message);
    }

    const newOsId = data?.id;

    if (temGestao && newOsId) {
      const baseRows = gestaoPayload.map((it) => ({
        ...it,
        os_id: newOsId,
        tenant_id: effectiveTenantId,
        empresa_id: effectiveEmpresaId,
      }));

      const { error: gestaoErr } = await supabase
        .from("os_gestao_itens")
        .upsert(baseRows, { onConflict: "os_id,item_tipo,area" });

      if (gestaoErr) {
        setCreating(false);
        await load();
        setShowCreate(false);
        setErr(`OS criada, mas a gestao nao foi salva: ${gestaoErr.message}`);
        return;
      }
    }

    setCreating(false);

    setOkMsg("OS criada!");
    setClienteId(null);
    setDescricao("");
    setPedidoCompra("");
    setTipoPedido("servico");
    setVendedor("");
    setResponsavelAprovacaoId(null);
    setOrcado("");
    setTemGestao(false);
    setUsaRelatorioHH(false);
    setGestaoItems(buildGestaoDefaults());
    setShowCreate(false);

    await load();

    if (data?.id) window.location.href = `/os/${data.id}`;
  }

  function updateGestaoItem(item_tipo: GestaoTipo, area: GestaoArea, patch: Partial<GestaoItem>) {
    setGestaoItems((prev) => {
      const exists = prev.some((it) => it.item_tipo === item_tipo && it.area === area);
      if (!exists) return prev;
      return prev.map((it) => (it.item_tipo === item_tipo && it.area === area ? { ...it, ...patch } : it));
    });
  }

  const renderGestaoRow = (def: (typeof gestaoDefs)[number]) => {
    const item = gestaoItems.find((it) => it.item_tipo === def.item_tipo && it.area === def.area);
    if (!item) return null;

    const fieldsDisabled = creating || !item.habilitado;

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
              disabled={creating}
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
            aria-label={`${def.label}: responsavel`}
            title={`${def.label}: responsavel`}
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
            aria-label={`${def.label}: data prevista`}
            title={`${def.label}: data prevista`}
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
            aria-label={`${def.label}: progresso (percentual)`}
            title={`${def.label}: progresso (percentual)`}
          />
        </div>
      </div>
    );
  };

  if (!tenantLoading && sessionReady && !canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 px-4">
        Sem permissão para visualizar OS.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Ordens de Serviço</h1>
          <p className="text-sm text-zinc-400 mt-1">Criar, filtrar e acessar OS.</p>
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          <input
            list="os-cliente-options"
            value={clienteFiltro}
            onChange={(e) => setClienteFiltro(e.target.value)}
            className="px-3 py-2 min-w-[220px]"
            aria-label="Filtrar por cliente"
            title="Filtrar por cliente"
            placeholder="Todos os clientes"
          />
          <datalist id="os-cliente-options">
            {clienteFiltroOptions.map((nome) => (
              <option key={nome} value={nome} />
            ))}
          </datalist>

          <select
            value={tipoFiltro}
            onChange={(e) => setTipoFiltro(e.target.value as typeof tipoFiltro)}
            className="px-3 py-2"
            aria-label="Filtrar por tipo"
            title="Filtrar por tipo"
          >
            <option value="todos_sem_hh">Todos - HH</option>
            <option value="todas">Todos</option>
            <option value="hh">HH</option>
            <option value="servico">Serviço</option>
            <option value="material">Material</option>
          </select>

          <select
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            className="px-3 py-2"
            aria-label="Filtrar por status"
            title="Filtrar por status"
          >
            <option value="todas">Todas</option>
            <option value="aberta">Aberta</option>
            <option value="em_andamento">Em andamento</option>
            <option value="concluida">Concluída</option>
            <option value="cancelada">Cancelada</option>
          </select>

          <button onClick={load} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
            Atualizar
          </button>

          {!readOnly && (
            <button
              onClick={() => {
                setShowCreate(true);
                setErr(null);
                setOkMsg(null);
                setClienteId(null);
                setTipoPedido("servico");
                setUsaRelatorioHH(true);
                setResponsavelAprovacaoId(session?.user?.id ?? null);
              }}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              Nova OS HH
            </button>
          )}
        </div>
      </div>

      {err && !showCreate && <div className="text-sm text-red-400">{err}</div>}
      {okMsg && !showCreate && <div className="text-sm text-emerald-300">{okMsg}</div>}

      {/* Lista */}
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">OS</th>
              <th className="px-4 py-3 text-left">Pedido</th>
              <th className="px-4 py-3 text-left">Cliente</th>
              <th className="px-4 py-3 text-left">Status</th>
              <th className="px-4 py-3 text-left">Descrição</th>
              <th className="px-4 py-3 text-right">Custo</th>
              {!hideValorPedido && <th className="px-4 py-3 text-right">Valor pedido</th>}
              {!hideValorPedido && <th className="px-4 py-3 text-right">Faturado</th>}
            </tr>
          </thead>

          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => (
              <tr
                key={r.id}
                className="hover:bg-zinc-900/40 cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-amber-400/60"
                tabIndex={0}
                role="button"
                onClick={() => router.push(`/os/${r.id}`)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    router.push(`/os/${r.id}`);
                  }
                }}
              >
                <td className="px-4 py-3">
                  <span className="underline decoration-zinc-600 hover:decoration-zinc-300">{r.numero_os}</span>
                </td>

                <td className="px-4 py-3 text-zinc-300">{r.pedido_compra?.trim() ? r.pedido_compra : "-"}</td>

                <td className="px-4 py-3">
                  <div className="font-medium">{r.cliente_nome}</div>
                  {r.cliente_id && <div className="text-xs text-zinc-400">cliente_id={r.cliente_id}</div>}
                </td>

                <td className="px-4 py-3">
                  <span className={["inline-flex items-center px-2 py-1 rounded-md border text-xs", statusBadge[r.status] ?? ""].join(" ")}>
                    {r.status}
                  </span>
                  <div className="mt-1 text-xs text-zinc-400">Aberta por: {r.criado_por?.trim() || "-"}</div>
                  <div className="text-xs text-zinc-400">
                    Responsável: {usuariosVendedores.find((usuario) => usuario.auth_user_id === r.responsavel_aprovacao_id)?.nome ?? "-"}
                  </div>
                </td>

                <td className="px-4 py-3 text-zinc-300">
                  {r.descricao_servico ? r.descricao_servico.toLocaleUpperCase("pt-BR") : "Sem descrição"}
                </td>

                {(() => {
                  // HH deve depender da flag da OS; alguns perfis podem não ter SELECT em `clientes`.
                  const hhEnabled = Boolean(r.usa_relatorio_hh);
                  const materiais = materiaisPorOs[r.id] ?? 0;
                  const maoObraExtra = maoObraPorOs[r.id] ?? 0;
                  const hhBruto = hhTotalPorOs[r.id] ?? 0;
                  const hhPedido = hhPedidoPorOs[r.id] ?? hhBruto;
                  const pedidoCadastro = Number(r.orcado ?? 0);
                  const tipoPedidoAtual = r.tipo_pedido === "material" ? "material" : "servico";

                  let impostos = 0;
                  if (hhEnabled) {
                    impostos = hhPedido * 0.15;
                  } else if (tipoPedidoAtual === "material") {
                    impostos = pedidoCadastro * 0.27;
                  } else {
                    impostos = pedidoCadastro * 0.15;
                  }

                  const custo = materiais + maoObraExtra + impostos;
                  const pedidoCalculado = hhEnabled ? hhPedido : pedidoCadastro;
                  const pedido = hideValorPedido ? 0 : pedidoCalculado;

                  let custoClass = "text-emerald-300 border-emerald-500/40";
                  if (!hideValorPedido && custo > 0) {
                    const perc = (pedido - custo) / custo;
                    if (perc < 0) custoClass = "text-red-300 border-red-500/40";
                    else if (perc < 0.15) custoClass = "text-amber-300 border-amber-500/40";
                    else custoClass = "text-emerald-300 border-emerald-500/40";
                  }
                  return (
                    <>
                      <td className="px-4 py-3 text-right tabular-nums">
                        <span className={`inline-flex items-center px-2 py-1 rounded-md border text-xs ${custoClass}`}>
                          R$ {formatMoney(custo)}
                        </span>
                      </td>
                      {!hideValorPedido && (
                        <td className="px-4 py-3 text-right tabular-nums text-zinc-200">R$ {formatMoney(pedido)}</td>
                      )}
                      {!hideValorPedido && (
                        <td className="px-4 py-3 text-right tabular-nums text-zinc-200">
                          R$ {formatMoney(faturadoPorOs[r.id] ?? 0)}
                        </td>
                      )}
                    </>
                  );
                })()}
              </tr>
            ))}

            {loading && (
              <tr>
                <td colSpan={hideValorPedido ? 6 : 8} className="px-4 py-6 text-zinc-400">
                  Carregando...
                </td>
              </tr>
            )}

            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={hideValorPedido ? 6 : 8} className="px-4 py-6 text-zinc-400">
                  Nenhuma OS encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {showCreate && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4 overflow-y-auto z-50">
          <div className="w-full max-w-5xl max-h-[90vh] overflow-y-auto bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4 my-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">Nova OS HH</div>
                <div className="text-sm text-zinc-400">Crie aqui somente OS de HH. As demais OS devem nascer pelo orçamento.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setShowCreate(false)}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={createOS}
                  disabled={creating}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                >
                  {creating ? "Criando..." : "Criar OS HH"}
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
                  disabled
                  aria-label="Tipo de pedido"
                  title="Tipo de pedido"
                >
                  <option value="servico">Serviço HH</option>
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
                    setUsaRelatorioHH(true);
                  }}
                  aria-label="Cliente (cadastro)"
                  title="Cliente (cadastro)"
                >
                  <option value="">-</option>
                  {clientesNovaOsHh.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nome}
                    </option>
                  ))}
                </select>
                {!isApontamentoRh && clientesNovaOsHh.length === 0 && (
                  <div className="text-xs text-amber-300">Nenhum cliente habilitado para HH.</div>
                )}
              </div>

              <div className="md:col-span-3 border border-emerald-900/60 rounded-lg p-3 bg-emerald-950/20">
                <label className="flex items-center gap-2 text-sm text-emerald-100">
                  <input type="checkbox" className="h-4 w-4" checked={usaRelatorioHH} readOnly disabled />
                  <span className="font-medium">OS HH</span>
                </label>
                {clienteSelecionadoNaoHabilitaHH && (
                  <div className="mt-2 text-xs text-amber-300">
                    Este cliente não está habilitado para HH. OS comum deve ser criada pelo orçamento.
                  </div>
                )}
              </div>

              {clienteSelecionadoNaoHabilitaHH && (
                <div className="md:col-span-3 text-sm text-amber-300">
                  Selecione um cliente habilitado para HH para criar esta OS por aqui.
                </div>
              )}

              <div className="space-y-1">
                <ResponsavelAprovacaoSelect
                  tenantId={effectiveTenantId}
                  empresaId={effectiveEmpresaId}
                  value={responsavelAprovacaoId}
                  onChange={(userId) => setResponsavelAprovacaoId(userId)}
                  defaultToCurrentUser
                  disabled={creating}
                  label="Responsável da OS"
                />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Vendedor</div>
                <select
                  className="w-full px-3 py-2"
                  value={vendedor}
                  onChange={(e) => setVendedor(e.target.value)}
                  disabled={creating || usuariosVendedoresLoading}
                  aria-label="Vendedor"
                  title="Vendedor"
                >
                  <option value="">
                    {usuariosVendedoresLoading
                      ? "Carregando usuarios..."
                      : usuariosVendedoresError
                        ? "Erro ao carregar usuarios"
                        : "-"}
                  </option>
                  {usuariosVendedores.map((usuario) => (
                    <option key={usuario.id} value={usuario.nome}>
                      {usuario.nome}
                      {usuario.email ? ` (${usuario.email})` : ""}
                    </option>
                  ))}
                </select>
                {usuariosVendedoresError && <div className="text-xs text-amber-300">{usuariosVendedoresError}</div>}
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Valor pedido</div>
                <input
                  type="number"
                  className="w-full px-3 py-2"
                  value={orcado}
                  onChange={(e) => setOrcado(e.target.value)}
                  placeholder="0.00"
                  aria-label="Valor pedido"
                  title="Valor pedido"
                />
              </div>

              <div className="space-y-1 md:col-span-3">
                <div className="text-xs text-zinc-400">Descrição (opcional)</div>
                <textarea
                  className="w-full px-3 py-2 min-h-[80px]"
                  value={descricao}
                  onChange={(e) => setDescricao(e.target.value.toLocaleUpperCase("pt-BR"))}
                  aria-label="Descrição"
                  title="Descrição"
                />
              </div>
            </div>

            <div className="border-t border-zinc-800 pt-4 space-y-4">
              <div>
                <div className="text-lg font-semibold">Gestao de Projetos e Execucao</div>
                <div className="text-sm text-zinc-400">Configure responsaveis, datas e progresso.</div>
              </div>

              <div className="border border-zinc-800 rounded-lg px-4 py-3 bg-zinc-900/40 flex items-center justify-between flex-wrap gap-3">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    className="h-4 w-4"
                    checked={temGestao}
                    onChange={(e) => setTemGestao(e.target.checked)}
                    disabled={creating || !canGestaoWrite}
                  />
                  <span>Habilitar gestao nesta OS</span>
                </label>
                <div className={canGestaoWrite ? "text-xs text-zinc-400" : "text-xs text-amber-300"}>
                  {canGestaoWrite
                    ? "Salve para atualizar o status da gestao."
                    : "Seu usuario nao tem permissao para gestao (os_gestao.write)."}
                </div>
              </div>

              {!temGestao && (
                <div className="text-sm text-zinc-300">
                  Gestao desabilitada para esta OS. Ative o controle acima para editar os itens. Valores existentes serao mantidos.
                </div>
              )}

              {temGestao && (
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

            {err && <div className="text-sm text-red-400">{err}</div>}
            {okMsg && <div className="text-sm text-emerald-300">{okMsg}</div>}
          </div>
        </div>
      )}
    </div>
  );
}

