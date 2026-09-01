"use client";

import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { useSessionReady } from "@/lib/auth/useSessionReady";
import { getOsListAccess } from "@/lib/auth/osAccess";
import { getHorasTrabalhadasEfetivas, getValorTotalEfetivo } from "@/lib/hh/hhLancamentosCalc";
import { fetchFaturadoByOs } from "@/lib/os/faturadoPorOs";
import { getOsStatusLabel, normalizeOsStatusFluxo } from "@/lib/os/statusFluxo";
import ResponsavelAprovacaoSelect from "@/components/os/ResponsavelAprovacaoSelect";

type Cliente = { id: number; nome: string; ativo: boolean; habilita_hh: boolean };
type ClienteUnidade = { id: number; cliente_id: number; nome: string; codigo: string | null };

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
  unidade_id?: number | null;
  status: string;
  status_fluxo?: string | null;
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

type CustoOperacionalRow = {
  os_id: number;
  custo_total: number | null;
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
type VistaOs = "lista" | "cliente";
type OrdemGrupo = "valor" | "recente" | "nome";

type ClienteGroup = {
  key: string;
  clienteId: number | null;
  clienteNome: string;
  rows: OS[];
  totalPedido: number;
  totalFaturado: number;
  semOc: number;
  responsaveis: string[];
  maisRecente: number;
};

function normalizeSearchTerm(s: unknown) {
  return String(s ?? "")
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

const statusColor: Record<string, string> = {
  aberta: "var(--carteira-blue)",
  em_andamento: "var(--carteira-amber)",
  concluida: "var(--carteira-green)",
  faturada: "var(--carteira-faint)",
  em_andamento_garantia: "var(--carteira-amber)",
  concluida_garantia: "var(--carteira-green)",
  cancelada: "var(--carteira-red)",
};

function csvCell(value: unknown) {
  return `"${String(value ?? "").replace(/"/g, '""')}"`;
}

function parseOpenGroups(value: string | null) {
  return new Set(
    String(value ?? "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean)
  );
}

function statusFilterLabel(status: string) {
  const labels: Record<string, string> = {
    todas: "OS no filtro",
    aberta: "Abertas",
    em_andamento: "Em andamento",
    concluida: "Concluídas",
    faturada: "Faturadas",
    cancelada: "Canceladas",
  };
  return labels[status] ?? "OS no filtro";
}

function compactNames(names: string[]) {
  if (names.length <= 3) return names.join(", ");
  return `${names.slice(0, 3).join(", ")} +${names.length - 3}`;
}

function HighlightText({ text, query }: { text: string; query: string }) {
  const cleanQuery = query.trim();
  if (!cleanQuery) return <>{text}</>;

  const escaped = cleanQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const parts = text.split(new RegExp(`(${escaped})`, "ig"));
  return (
    <>
      {parts.map((part, index) =>
        part.toLocaleLowerCase("pt-BR") === cleanQuery.toLocaleLowerCase("pt-BR") ? (
          <mark
            key={`${part}-${index}`}
            className="rounded-sm bg-[var(--carteira-blue-soft)] px-0.5 text-[var(--carteira-blue)]"
          >
            {part}
          </mark>
        ) : (
          <Fragment key={`${part}-${index}`}>{part}</Fragment>
        )
      )}
    </>
  );
}

function oneYearAgoISO(): string {
  const date = new Date();
  date.setFullYear(date.getFullYear() - 1);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

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
  const searchParams = useSearchParams();
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
  const [clienteUnidades, setClienteUnidades] = useState<ClienteUnidade[]>([]);
  const [unidadeNomePorId, setUnidadeNomePorId] = useState<Record<number, string>>({});
  const [usuariosVendedores, setUsuariosVendedores] = useState<UsuarioVendedor[]>([]);
  const [usuariosVendedoresLoading, setUsuariosVendedoresLoading] = useState(false);
  const [usuariosVendedoresError, setUsuariosVendedoresError] = useState<string | null>(null);
  const [rows, setRows] = useState<OS[]>([]);
  const statusFromUrl = searchParams.get("status");
  const [status, setStatus] = useState(
    ["todas", "aberta", "em_andamento", "concluida", "faturada", "cancelada"].includes(String(statusFromUrl))
      ? String(statusFromUrl)
      : "em_andamento"
  );
  const [idadeFiltro, setIdadeFiltro] = useState(searchParams.get("idade") === "mais_de_1_ano");
  const [clienteFiltro, setClienteFiltro] = useState<string>(searchParams.get("cliente") ?? "");
  const [clienteFiltroOptions, setClienteFiltroOptions] = useState<string[]>([]);
  const tipoFromUrl = searchParams.get("tipo");
  const [tipoFiltro, setTipoFiltro] = useState<TipoFiltro>(
    ["todos_sem_hh", "todas", "hh", "servico", "material"].includes(String(tipoFromUrl))
      ? (tipoFromUrl as TipoFiltro)
      : "todos_sem_hh"
  );
  const vistaFromUrl = searchParams.get("vista");
  const [vista, setVista] = useState<VistaOs>(vistaFromUrl === "lista" ? "lista" : "cliente");
  const ordemFromUrl = searchParams.get("ordem");
  const [ordem, setOrdem] = useState<OrdemGrupo>(
    ["valor", "recente", "nome"].includes(String(ordemFromUrl)) ? (ordemFromUrl as OrdemGrupo) : "valor"
  );
  const [busca, setBusca] = useState(searchParams.get("q") ?? "");
  const [responsavelFiltro, setResponsavelFiltro] = useState(searchParams.get("responsavel") ?? "");
  const [semOcFiltro, setSemOcFiltro] = useState(searchParams.get("sem_oc") === "1");
  const [gruposAbertos, setGruposAbertos] = useState<Set<string>>(() => parseOpenGroups(searchParams.get("aberto")));
  const [err, setErr] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [custoPorOs, setCustoPorOs] = useState<Record<number, number>>({});
  const [hhTotalPorOs, setHhTotalPorOs] = useState<Record<number, number>>({});
  const [hhPedidoPorOs, setHhPedidoPorOs] = useState<Record<number, number>>({});
  const [faturadoPorOs, setFaturadoPorOs] = useState<Record<number, number>>({});

  // criacao
  const [creating, setCreating] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [createMode, setCreateMode] = useState<"hh" | "fiado">("hh");
  const [clienteId, setClienteId] = useState<number | null>(null);
  const [unidadeId, setUnidadeId] = useState<number | null>(null);
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

  function updateUrlParams(patch: Record<string, string | null>) {
    const next = new URLSearchParams(searchParams.toString());
    Object.entries(patch).forEach(([key, value]) => {
      if (value == null || value === "") next.delete(key);
      else next.set(key, value);
    });
    const query = next.toString();
    router.replace(query ? `/os?${query}` : "/os", { scroll: false });
  }

  function changeVista(nextVista: VistaOs) {
    setVista(nextVista);
    updateUrlParams({ vista: nextVista });
    try {
      window.localStorage.setItem(`estoque-os:vista-os:${session?.user?.id ?? "anonimo"}`, nextVista);
    } catch {
      // Preferência visual: falha de storage não deve bloquear a tela.
    }
  }

  useEffect(() => {
    if (!sessionReady || searchParams.get("vista")) return;
    let nextVista: VistaOs = "cliente";
    try {
      const saved = window.localStorage.getItem(`estoque-os:vista-os:${session?.user?.id ?? "anonimo"}`);
      if (saved === "lista" || saved === "cliente") nextVista = saved;
    } catch {
      // Mantém o padrão por cliente quando storage não estiver disponível.
    }
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setVista(nextVista);
    updateUrlParams({ vista: nextVista, ordem: ordem === "valor" ? null : ordem });
    // A leitura ocorre apenas quando a sessão fica pronta; mudanças posteriores são feitas pelos controles.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionReady, session?.user?.id]);

  const clienteHabilitaHH = useMemo(() => {
    if (!clienteId) return false;
    return Boolean(clientes.find((c) => c.id === clienteId)?.habilita_hh);
  }, [clienteId, clientes]);
  const clientesNovaOsHh = useMemo(
    () => (isApontamentoRh ? clientes : clientes.filter((cliente) => cliente.habilita_hh)),
    [clientes, isApontamentoRh]
  );
  const clientesParaModal = createMode === "fiado" ? clientes : clientesNovaOsHh;
  const clienteSelecionadoNaoHabilitaHH =
    createMode === "hh" && Boolean(clienteId && !clienteHabilitaHH && !isApontamentoRh);

  useEffect(() => {
    if (!sessionReady || !session?.access_token || !clienteId) {
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
      if (error) {
        setClienteUnidades([]);
        setUnidadeId(null);
        return;
      }
      const next = (data ?? []) as ClienteUnidade[];
      setClienteUnidades(next);
      setUnidadeId((current) => (current && next.some((row) => row.id === current) ? current : null));
    })();
    return () => { active = false; };
  }, [clienteId, effectiveEmpresaId, effectiveTenantId, session?.access_token, sessionReady, supabase]);

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
          .eq("tipo_documento", "OS")
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
        .select("cliente_nome,tipo_pedido,usa_relatorio_hh,status,status_fluxo")
        .eq("tipo_documento", "OS")
        .order("cliente_nome", { ascending: true }),
      effectiveTenantId,
      effectiveEmpresaId
    );

    if (status === "aberta" || status === "cancelada") query = query.eq("status", status);
    if (status === "em_andamento") query = query.in("status_fluxo", ["em_andamento", "em_andamento_garantia"]);
    if (status === "concluida") query = query.in("status_fluxo", ["concluida", "concluida_garantia"]);
    if (status === "faturada") query = query.eq("status_fluxo", "faturada");
    if (idadeFiltro) query = query.lt("data_abertura", oneYearAgoISO());

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
    setCustoPorOs({});
    setHhTotalPorOs({});
    setHhPedidoPorOs({});
    setUnidadeNomePorId({});
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
          "id,numero_os,pedido_compra,cliente_nome,cliente_id,unidade_id,status,status_fluxo,criado_por,responsavel_aprovacao_id,descricao_servico,data_abertura,valor_total,orcado,custo,tipo_pedido,usa_relatorio_hh"
        )
        .eq("tipo_documento", "OS")
        .order("id", { ascending: false }),
      effectiveTenantId,
      effectiveEmpresaId
    );

    if (status === "aberta" || status === "cancelada") q = q.eq("status", status);
    if (status === "em_andamento") q = q.in("status_fluxo", ["em_andamento", "em_andamento_garantia"]);
    if (status === "concluida") q = q.in("status_fluxo", ["concluida", "concluida_garantia"]);
    if (status === "faturada") q = q.eq("status_fluxo", "faturada");
    if (idadeFiltro) q = q.lt("data_abertura", oneYearAgoISO());
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

    const unidadeIds = Array.from(
      new Set(
        osList
          .map((row) => Number(row.unidade_id))
          .filter((id) => Number.isFinite(id) && id > 0)
      )
    );
    if (unidadeIds.length > 0) {
      const { data: unidadesData, error: unidadesError } = await applyTenantEmpresa(
        supabase.from("cliente_unidades").select("id,nome").in("id", unidadeIds),
        effectiveTenantId,
        effectiveEmpresaId
      );
      if (reqId !== osReqIdRef.current) return;
      if (unidadesError) {
        logDebug("[OS] load:units-error", { error: unidadesError.message, reqId });
        setUnidadeNomePorId({});
      } else {
        const nomes: Record<number, string> = {};
        ((unidadesData ?? []) as Array<{ id: number; nome: string | null }>).forEach((unidade) => {
          const id = Number(unidade.id);
          if (Number.isFinite(id) && unidade.nome?.trim()) nomes[id] = unidade.nome.trim();
        });
        setUnidadeNomePorId(nomes);
      }
    } else {
      setUnidadeNomePorId({});
    }

    const osIds = osList.map((r) => r.id);
    if (osIds.length > 0) {
      const { data: custosData, error: custosError } = await supabase.rpc("get_os_lista_custos_operacionais", {
        p_tenant_id: effectiveTenantId,
        p_empresa_id: effectiveEmpresaId,
        p_os_ids: osIds,
      });
      if (reqId !== osReqIdRef.current) return;

      if (custosError) {
        logDebug("[OS] load:costs-error", { error: custosError.message, reqId });
        setErr("Não foi possível calcular o custo operacional das ordens de serviço. Tente atualizar a tela.");
        setLoading(false);
        return;
      }

      const custosTotals: Record<number, number> = {};
      const custosRows = (custosData ?? []) as CustoOperacionalRow[];
      custosRows.forEach((row) => {
        const osId = Number(row.os_id);
        if (!Number.isFinite(osId)) return;
        custosTotals[osId] = Number(row.custo_total ?? 0);
      });
      setCustoPorOs(custosTotals);

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
    // As cargas assíncronas sincronizam a tela com o banco quando o escopo ou os filtros mudam.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadClientes();
    void loadClienteFiltroOptions();
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canView, tenantId, empresaId, sessionReady, session?.access_token, status, clienteFiltro, tipoFiltro, idadeFiltro]);

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!sessionReady || !session?.access_token || !canView) {
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
  }, [canView, effectiveEmpresaId, effectiveTenantId, session?.access_token, sessionReady, supabase]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
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
    if (createMode === "hh" && !clienteHabilitaHH && !isApontamentoRh) {
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
    const usaRelatorioHHFinal = createMode === "hh" ? true : clienteHabilitaHH;

    const { data, error } = await supabase
      .from("ordens_servico")
      .insert({
        tenant_id: effectiveTenantId,
        empresa_id: effectiveEmpresaId,
        tipo_documento: "OS",
        numero_os: numeroGerado,
        cliente_id: clienteId,
        unidade_id: unidadeId,
        cliente_nome: clienteNomeFinal,
        descricao_servico: descricao.trim() ? descricao.trim().toLocaleUpperCase("pt-BR") : null,
        pedido_compra: pedidoCompra.trim() || null,
        tipo_pedido: createMode === "fiado" ? tipoPedido : "servico",
        vendedor: vendedor.trim() || null,
        orcado: orcadoValor,
        tem_gestao: temGestao,
        usa_relatorio_hh: usaRelatorioHHFinal,
        is_fiado: createMode === "fiado",
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
    setUnidadeId(null);
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

  function pedidoDaOs(row: OS) {
    if (row.usa_relatorio_hh) return hhPedidoPorOs[row.id] ?? hhTotalPorOs[row.id] ?? 0;
    return Number(row.orcado ?? 0);
  }

  function responsavelDaOs(row: OS) {
    const responsavel = usuariosVendedores.find((usuario) => usuario.auth_user_id === row.responsavel_aprovacao_id)?.nome;
    if (responsavel) return responsavel;
    const email = String(row.criado_por ?? "").trim();
    if (!email) return "—";
    const nomeEmail = email.split("@")[0]?.replace(/[._-]+/g, " ").trim();
    return nomeEmail ? nomeEmail.replace(/\b\p{L}/gu, (letter) => letter.toLocaleUpperCase("pt-BR")) : "—";
  }

  function unidadeDaOs(row: OS) {
    const unidadeIdAtual = Number(row.unidade_id);
    return Number.isFinite(unidadeIdAtual) ? unidadeNomePorId[unidadeIdAtual] ?? "" : "";
  }

  function getFilteredRows() {
    const normalizedQuery = normalizeSearchTerm(busca);
    return rows.filter((row) => {
      if (semOcFiltro && row.pedido_compra?.trim()) return false;
      if (responsavelFiltro && responsavelDaOs(row) !== responsavelFiltro) return false;
      if (!normalizedQuery) return true;

      const haystack = normalizeSearchTerm(
        [row.numero_os, row.pedido_compra, row.cliente_nome, row.descricao_servico].filter(Boolean).join(" ")
      );
      return haystack.includes(normalizedQuery);
    });
  }

  const filteredRows = getFilteredRows();
  const responsaveisDisponiveis = Array.from(
    new Set(rows.map((row) => responsavelDaOs(row)).filter((nome) => nome && nome !== "—"))
  ).sort((a, b) => a.localeCompare(b, "pt-BR"));

  const gruposMap = new Map<string, ClienteGroup>();
  for (const row of filteredRows) {
    const clienteIdAtual = Number(row.cliente_id);
    const hasClienteId = Number.isFinite(clienteIdAtual) && clienteIdAtual > 0;
    const key = hasClienteId ? String(clienteIdAtual) : "sem-cliente";
    const current = gruposMap.get(key) ?? {
      key,
      clienteId: hasClienteId ? clienteIdAtual : null,
      clienteNome: hasClienteId ? row.cliente_nome?.trim() || "Cliente sem nome" : "Sem cliente identificado",
      rows: [],
      totalPedido: 0,
      totalFaturado: 0,
      semOc: 0,
      responsaveis: [],
      maisRecente: 0,
    };

    const responsavel = responsavelDaOs(row);
    current.rows.push(row);
    current.totalPedido += pedidoDaOs(row);
    current.totalFaturado += faturadoPorOs[row.id] ?? 0;
    current.semOc += row.pedido_compra?.trim() ? 0 : 1;
    current.maisRecente = Math.max(current.maisRecente, new Date(row.data_abertura).getTime() || row.id);
    if (responsavel !== "—" && !current.responsaveis.includes(responsavel)) current.responsaveis.push(responsavel);
    gruposMap.set(key, current);
  }

  const grupos = Array.from(gruposMap.values()).sort((a, b) => {
    if (a.clienteId == null) return 1;
    if (b.clienteId == null) return -1;
    if (ordem === "nome") return a.clienteNome.localeCompare(b.clienteNome, "pt-BR");
    if (ordem === "recente") return b.maisRecente - a.maisRecente;
    return b.totalPedido - a.totalPedido || a.clienteNome.localeCompare(b.clienteNome, "pt-BR");
  });

  const totalPedidoFiltrado = filteredRows.reduce((sum, row) => sum + pedidoDaOs(row), 0);
  const totalCustoFiltrado = filteredRows.reduce((sum, row) => sum + (custoPorOs[row.id] ?? 0), 0);
  const totalAFaturar = filteredRows.reduce(
    (sum, row) => sum + Math.max(0, pedidoDaOs(row) - (faturadoPorOs[row.id] ?? 0)),
    0
  );
  const osSemNota = filteredRows.filter((row) => (faturadoPorOs[row.id] ?? 0) <= 0).length;
  const osSemOc = filteredRows.filter((row) => !row.pedido_compra?.trim());
  const totalSemOc = osSemOc.reduce((sum, row) => sum + pedidoDaOs(row), 0);
  const filtroAtivo = Boolean(
    busca.trim() ||
      clienteFiltro.trim() ||
      responsavelFiltro ||
      semOcFiltro ||
      idadeFiltro ||
      tipoFiltro !== "todos_sem_hh" ||
      status !== "em_andamento"
  );

  function toggleGrupo(key: string) {
    const next = new Set(gruposAbertos);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    setGruposAbertos(next);
    updateUrlParams({ aberto: next.size ? Array.from(next).join(",") : null });
  }

  function limparFiltros() {
    setBusca("");
    setClienteFiltro("");
    setResponsavelFiltro("");
    setSemOcFiltro(false);
    setIdadeFiltro(false);
    setTipoFiltro("todos_sem_hh");
    setStatus("em_andamento");
    const next = new URLSearchParams();
    next.set("vista", vista);
    if (ordem !== "valor") next.set("ordem", ordem);
    if (gruposAbertos.size) next.set("aberto", Array.from(gruposAbertos).join(","));
    router.replace(`/os?${next.toString()}`, { scroll: false });
  }

  function abrirNovaOs(mode: "hh" | "fiado") {
    setCreateMode(mode);
    setShowCreate(true);
    setErr(null);
    setOkMsg(null);
    setClienteId(null);
    setUnidadeId(null);
    setTipoPedido("servico");
    setUsaRelatorioHH(mode === "hh");
    setResponsavelAprovacaoId(session?.user?.id ?? null);
  }

  function exportarCsv() {
    const header = ["OS", "Pedido", "Descrição", "Cliente", "Unidade", "Status", "Responsável", "Abertura", "Custo"];
    if (!hideValorPedido) header.push("Valor pedido", "Faturado");

    const body = filteredRows.map((row) => {
      const statusExibicao = normalizeOsStatusFluxo(row.status_fluxo, row.status);
      const values: unknown[] = [
        row.numero_os,
        row.pedido_compra?.trim() ?? "",
        row.descricao_servico ?? "",
        row.cliente_nome,
        unidadeDaOs(row),
        getOsStatusLabel(statusExibicao),
        responsavelDaOs(row),
        row.data_abertura?.slice(0, 10) ?? "",
        formatMoney(custoPorOs[row.id] ?? 0),
      ];
      if (!hideValorPedido) {
        values.push(formatMoney(pedidoDaOs(row)), formatMoney(faturadoPorOs[row.id] ?? 0));
      }
      return values.map(csvCell).join(";");
    });

    const blob = new Blob(["\uFEFF" + [header.map(csvCell).join(";"), ...body].join("\r\n")], {
      type: "text/csv;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `ordens-servico-${new Date().toISOString().slice(0, 10)}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
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
    <div className="carteira-theme mx-auto w-full max-w-[1680px] space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <div className="carteira-blue font-mono text-[10px] font-semibold uppercase tracking-[0.13em]">
            Operação <span className="carteira-faint px-1">›</span> Ordens de Serviço
          </div>
          <h1 className="carteira-text mt-1.5 text-[23px] font-bold tracking-[-0.02em]">Ordens de Serviço</h1>
          <p className="carteira-muted mt-1 text-[12px]">
            {loading
              ? "Carregando a carteira de OS..."
              : `${filteredRows.length} ${filteredRows.length === 1 ? "OS" : "OS"} em ${grupos.length} ${grupos.length === 1 ? "cliente" : "clientes"}.`}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <div className="carteira-surface flex items-center rounded-lg border p-0.5" aria-label="Modo de visualização">
            <button
              type="button"
              onClick={() => changeVista("lista")}
              aria-pressed={vista === "lista"}
              className={`rounded-md px-3 py-1.5 text-[11px] font-semibold transition ${
                vista === "lista"
                  ? "bg-[var(--carteira-elevated)] text-[var(--carteira-text)] shadow-sm"
                  : "text-[var(--carteira-muted)] hover:text-[var(--carteira-text)]"
              }`}
            >
              Lista
            </button>
            <button
              type="button"
              onClick={() => changeVista("cliente")}
              aria-pressed={vista === "cliente"}
              className={`rounded-md px-3 py-1.5 text-[11px] font-semibold transition ${
                vista === "cliente"
                  ? "bg-[var(--carteira-elevated)] text-[var(--carteira-text)] shadow-sm"
                  : "text-[var(--carteira-muted)] hover:text-[var(--carteira-text)]"
              }`}
            >
              Por cliente
            </button>
          </div>
          <button
            type="button"
            onClick={exportarCsv}
            disabled={loading || filteredRows.length === 0}
            className="carteira-button rounded-lg px-3 py-2 text-xs font-medium"
          >
            Exportar CSV
          </button>
          <button
            type="button"
            onClick={load}
            disabled={loading}
            className="carteira-button rounded-lg px-3 py-2 text-xs font-medium"
          >
            {loading ? "Atualizando..." : "Atualizar"}
          </button>

          {!readOnly && (
            <details className="group relative">
              <summary className="carteira-button carteira-button-amber flex cursor-pointer list-none items-center gap-2 rounded-lg px-3.5 py-2 text-xs font-semibold [&::-webkit-details-marker]:hidden">
                Nova OS <span className="text-[10px] transition group-open:rotate-180">▼</span>
              </summary>
              <div className="carteira-surface absolute right-0 z-30 mt-2 min-w-44 overflow-hidden rounded-lg border shadow-xl shadow-black/20">
                <button
                  type="button"
                  onClick={(event) => {
                    abrirNovaOs("hh");
                    event.currentTarget.closest("details")?.removeAttribute("open");
                  }}
                  className="carteira-text block w-full px-3.5 py-2.5 text-left text-xs font-medium hover:bg-[var(--carteira-hover)]"
                >
                  Nova OS HH
                </button>
                <button
                  type="button"
                  onClick={(event) => {
                    abrirNovaOs("fiado");
                    event.currentTarget.closest("details")?.removeAttribute("open");
                  }}
                  className="carteira-text block w-full border-t border-[var(--carteira-border)] px-3.5 py-2.5 text-left text-xs font-medium hover:bg-[var(--carteira-hover)]"
                >
                  Nova OS Fiado
                </button>
              </div>
            </details>
          )}
        </div>
      </div>

      <section className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-4" aria-label="Indicadores da carteira de OS">
        <article className="carteira-surface min-h-[96px] rounded-xl border px-4 py-3.5">
          <div className="carteira-muted font-mono text-[9px] font-bold uppercase tracking-[0.11em]">
            {statusFilterLabel(status)}
          </div>
          <div className="carteira-text mt-3 font-mono text-[22px] font-bold leading-none tabular-nums">
            {filteredRows.length}
          </div>
          <div className="carteira-muted mt-2 text-[10px]">
            {grupos.length} {grupos.length === 1 ? "cliente" : "clientes"}
          </div>
        </article>

        <article className="carteira-surface min-h-[96px] rounded-xl border px-4 py-3.5">
          <div className="carteira-muted font-mono text-[9px] font-bold uppercase tracking-[0.11em]">Valor em aberto</div>
          <div className="carteira-text mt-3 font-mono text-[20px] font-bold leading-none tabular-nums">
            {hideValorPedido ? "—" : `R$ ${formatMoney(totalPedidoFiltrado)}`}
          </div>
          <div className="carteira-muted mt-2 text-[10px]">
            {hideValorPedido ? "Valores restritos para este perfil" : `custo lançado R$ ${formatMoney(totalCustoFiltrado)}`}
          </div>
        </article>

        <article className="carteira-surface min-h-[96px] rounded-xl border px-4 py-3.5">
          <div className="carteira-muted font-mono text-[9px] font-bold uppercase tracking-[0.11em]">A faturar</div>
          <div className="carteira-text mt-3 font-mono text-[20px] font-bold leading-none tabular-nums">
            {hideValorPedido ? "—" : `R$ ${formatMoney(totalAFaturar)}`}
          </div>
          <div className="carteira-muted mt-2 text-[10px]">
            {osSemNota} {osSemNota === 1 ? "OS sem nota" : "OS sem nota"}
          </div>
        </article>

        <button
          type="button"
          onClick={() => router.push("/financeiro/venda-a-credito?status=ABERTO&sem_oc=1")}
          className="min-h-[96px] rounded-xl border border-[var(--carteira-amber)] bg-[var(--carteira-amber-soft)] px-4 py-3.5 text-left transition hover:brightness-105 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--carteira-amber)]"
          title="Abrir estas OS na Venda a Crédito"
        >
          <div className="font-mono text-[9px] font-bold uppercase tracking-[0.11em] text-[var(--carteira-amber)]">
            Sem pedido de compra
          </div>
          <div className="mt-3 font-mono text-[20px] font-bold leading-none tabular-nums text-[var(--carteira-amber)]">
            {hideValorPedido ? "—" : `R$ ${formatMoney(totalSemOc)}`}
          </div>
          <div className="mt-2 text-[10px] text-[var(--carteira-amber)]">
            {osSemOc.length} {osSemOc.length === 1 ? "OS" : "OS"} · abrir na Venda a Crédito ›
          </div>
        </button>
      </section>

      <div className="carteira-surface rounded-xl border p-2.5">
        <div className="grid grid-cols-1 gap-2 md:grid-cols-2 xl:grid-cols-[minmax(250px,1.4fr)_160px_180px_minmax(170px,0.7fr)_145px_150px_auto]">
          <input
            value={busca}
            onChange={(event) => {
              setBusca(event.target.value);
              updateUrlParams({ q: event.target.value.trim() || null });
            }}
            className="carteira-control min-w-0 rounded-lg px-3 py-2 text-xs"
            aria-label="Buscar OS, pedido, cliente ou descrição"
            placeholder="Buscar OS, cliente ou descrição"
          />

          <select
            value={status}
            onChange={(e) => {
              const nextStatus = e.target.value;
              setStatus(nextStatus);
              if (nextStatus !== "em_andamento") setIdadeFiltro(false);
              updateUrlParams({
                status: nextStatus === "em_andamento" ? null : nextStatus,
                idade: nextStatus === "em_andamento" && idadeFiltro ? "mais_de_1_ano" : null,
              });
            }}
            className="carteira-control rounded-lg px-3 py-2 text-xs"
            aria-label="Filtrar por status"
            title="Filtrar por status"
          >
            <option value="todas">Todas</option>
            <option value="aberta">Aberta</option>
            <option value="em_andamento">Em andamento</option>
            <option value="concluida">Concluída</option>
            <option value="faturada">Faturada</option>
            <option value="cancelada">Cancelada</option>
          </select>

          <select
            value={responsavelFiltro}
            onChange={(event) => {
              setResponsavelFiltro(event.target.value);
              updateUrlParams({ responsavel: event.target.value || null });
            }}
            className="carteira-control rounded-lg px-3 py-2 text-xs"
            aria-label="Filtrar por responsável"
          >
            <option value="">Todos os responsáveis</option>
            {responsaveisDisponiveis.map((nome) => (
              <option key={nome} value={nome}>{nome}</option>
            ))}
          </select>

          <input
            list="os-cliente-options"
            value={clienteFiltro}
            onChange={(event) => {
              setClienteFiltro(event.target.value);
              updateUrlParams({ cliente: event.target.value.trim() || null });
            }}
            className="carteira-control min-w-0 rounded-lg px-3 py-2 text-xs"
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
            onChange={(event) => {
              const nextTipo = event.target.value as TipoFiltro;
              setTipoFiltro(nextTipo);
              updateUrlParams({ tipo: nextTipo === "todos_sem_hh" ? null : nextTipo });
            }}
            className="carteira-control rounded-lg px-3 py-2 text-xs"
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
            value={idadeFiltro ? "mais_de_1_ano" : "todas"}
            onChange={(event) => {
              const nextIdade = event.target.value === "mais_de_1_ano";
              setIdadeFiltro(nextIdade);
              updateUrlParams({ idade: nextIdade ? "mais_de_1_ano" : null });
            }}
            disabled={status !== "em_andamento"}
            className="carteira-control rounded-lg px-3 py-2 text-xs disabled:cursor-not-allowed disabled:opacity-50"
            aria-label="Filtrar por data de abertura"
          >
            <option value="todas">Qualquer abertura</option>
            <option value="mais_de_1_ano">Mais de 1 ano</option>
          </select>

          <button
            type="button"
            onClick={() => {
              const nextSemOc = !semOcFiltro;
              setSemOcFiltro(nextSemOc);
              updateUrlParams({ sem_oc: nextSemOc ? "1" : null });
            }}
            aria-pressed={semOcFiltro}
            className={`rounded-lg border px-3 py-2 text-xs font-semibold transition ${
              semOcFiltro
                ? "border-[var(--carteira-amber)] bg-[var(--carteira-amber-soft)] text-[var(--carteira-amber)]"
                : "border-[var(--carteira-border-2)] bg-[var(--carteira-surface)] text-[var(--carteira-muted)] hover:text-[var(--carteira-text)]"
            }`}
          >
            Sem OC
          </button>
        </div>

        <div className="mt-2 flex min-h-5 flex-wrap items-center justify-between gap-2 border-t border-[var(--carteira-border)] px-1 pt-2 text-[10px]">
          <span className="carteira-faint">
            {filtroAtivo ? `${filteredRows.length} OS após os filtros` : "Nenhum filtro adicional ativo"}
          </span>
          {filtroAtivo ? (
            <button type="button" onClick={limparFiltros} className="carteira-blue font-semibold hover:underline">
              Limpar filtros
            </button>
          ) : null}
        </div>
      </div>

      {err && !showCreate && <div className="text-sm text-red-400">{err}</div>}
      {okMsg && !showCreate && <div className="text-sm text-emerald-300">{okMsg}</div>}

      {vista === "cliente" ? (
        <section className="space-y-2" aria-label="Ordens de serviço agrupadas por cliente">
          <div className="flex flex-wrap items-center justify-between gap-3 px-1">
            <label className="flex items-center gap-2 text-[10px] text-[var(--carteira-muted)]">
              <span className="font-mono font-semibold uppercase tracking-[0.1em]">Ordem</span>
              <select
                value={ordem}
                onChange={(event) => {
                  const nextOrdem = event.target.value as OrdemGrupo;
                  setOrdem(nextOrdem);
                  updateUrlParams({ ordem: nextOrdem === "valor" ? null : nextOrdem });
                }}
                className="carteira-control rounded-lg px-2.5 py-1.5 text-[11px]"
                aria-label="Ordenar clientes"
              >
                <option value="valor">Maior valor em aberto</option>
                <option value="recente">OS mais recente</option>
                <option value="nome">Nome A–Z</option>
              </select>
            </label>
            <div className="carteira-muted text-[10.5px]">
              {grupos.length} {grupos.length === 1 ? "cliente" : "clientes"} · {filteredRows.length} OS
              {busca.trim() ? (
                <button
                  type="button"
                  onClick={() => {
                    setBusca("");
                    updateUrlParams({ q: null });
                  }}
                  className="carteira-blue ml-2 font-semibold hover:underline"
                >
                  limpar busca
                </button>
              ) : null}
            </div>
          </div>

          {grupos.map((grupo) => {
            const isOpen = Boolean(busca.trim()) || gruposAbertos.has(grupo.key);
            const percentualFaturado = grupo.totalPedido > 0
              ? Math.max(0, Math.min(100, (grupo.totalFaturado / grupo.totalPedido) * 100))
              : 0;
            return (
              <article
                key={grupo.key}
                className={`carteira-surface overflow-hidden rounded-[10px] border ${grupo.clienteId == null ? "opacity-70" : ""}`}
              >
                <button
                  type="button"
                  onClick={() => toggleGrupo(grupo.key)}
                  aria-expanded={isOpen}
                  className="grid w-full grid-cols-[16px_minmax(0,1fr)_auto] items-center gap-3 px-4 py-3 text-left transition hover:bg-[var(--carteira-hover)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-[var(--carteira-blue)]"
                >
                  <span
                    aria-hidden="true"
                    className={`carteira-faint text-[10px] transition-transform duration-150 ${isOpen ? "rotate-90 text-[var(--carteira-text)]" : ""}`}
                  >
                    ▶
                  </span>
                  <span className="min-w-0">
                    <span className="flex flex-wrap items-center gap-2">
                      <span className="carteira-text max-w-full text-[13.5px] font-[650] leading-5 tracking-[0.01em]">
                        <HighlightText text={grupo.clienteNome} query={busca} />
                      </span>
                      {grupo.semOc > 0 ? (
                        <span className="rounded border border-[var(--carteira-amber)] bg-[var(--carteira-amber-soft)] px-1.5 py-0.5 font-mono text-[9px] font-bold uppercase tracking-[0.08em] text-[var(--carteira-amber)]">
                          {grupo.semOc} sem OC
                        </span>
                      ) : null}
                    </span>
                    <span className="carteira-muted mt-0.5 block text-[11.5px]">
                      {grupo.rows.length} {grupo.rows.length === 1 ? "OS" : "OS"}
                      {grupo.responsaveis.length ? ` · ${compactNames(grupo.responsaveis)}` : ""}
                    </span>
                  </span>
                  <span className="min-w-[170px] text-right">
                    <span className="carteira-text block font-mono text-[15px] font-bold tabular-nums">
                      {hideValorPedido ? "—" : `R$ ${formatMoney(grupo.totalPedido)}`}
                    </span>
                    <span className={`mt-0.5 block text-[10.5px] ${grupo.totalFaturado > 0 ? "carteira-green" : "carteira-faint"}`}>
                      {hideValorPedido
                        ? "valores restritos"
                        : grupo.totalFaturado > 0
                          ? `R$ ${formatMoney(grupo.totalFaturado)} faturado · ${Math.round(percentualFaturado)}%`
                          : "nada faturado"}
                    </span>
                  </span>
                </button>

                {isOpen ? (
                  <div className="overflow-x-auto border-t border-[var(--carteira-border)] bg-[var(--carteira-surface-2)]">
                    <div className="min-w-[760px]">
                      {grupo.rows.map((row) => {
                        const statusExibicao = normalizeOsStatusFluxo(row.status_fluxo, row.status);
                        const responsavel = responsavelDaOs(row);
                        return (
                          <button
                            key={row.id}
                            type="button"
                            onClick={() => router.push(`/os/${row.id}`)}
                            className="grid w-full grid-cols-[8px_72px_minmax(220px,1fr)_minmax(170px,0.7fr)_125px] items-center gap-3 border-b border-[var(--carteira-border)] py-2.5 pr-4 pl-[42px] text-left transition last:border-b-0 hover:bg-[var(--carteira-hover)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-[var(--carteira-blue)]"
                          >
                            <span
                              className="h-1.5 w-1.5 rounded-full"
                              style={{ background: statusColor[statusExibicao ?? ""] ?? "var(--carteira-faint)" }}
                              title={getOsStatusLabel(statusExibicao)}
                              aria-hidden="true"
                            />
                            <span className="carteira-blue font-mono text-[12.5px] font-bold tabular-nums">
                              <HighlightText text={row.numero_os} query={busca} />
                            </span>
                            <span className="carteira-text min-w-0 truncate text-[12.5px] font-medium" title={row.descricao_servico ?? "Sem descrição"}>
                              <HighlightText text={row.descricao_servico || "Sem descrição"} query={busca} />
                            </span>
                            <span className="carteira-muted min-w-0 truncate text-[11px]">
                              {responsavel}
                              {row.pedido_compra?.trim() ? (
                                <> · OC <HighlightText text={row.pedido_compra} query={busca} /></>
                              ) : (
                                <span className="text-[var(--carteira-amber)]"> · sem OC</span>
                              )}
                            </span>
                            {!hideValorPedido ? (
                              <span className="carteira-text text-right font-mono text-[12.5px] font-semibold tabular-nums">
                                R$ {formatMoney(pedidoDaOs(row))}
                              </span>
                            ) : <span />}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                ) : null}
              </article>
            );
          })}

          {!loading && grupos.length === 0 ? (
            <div className="carteira-surface carteira-muted rounded-xl border px-4 py-10 text-center text-sm">
              Nenhuma OS corresponde aos filtros atuais.
            </div>
          ) : null}
          {loading ? (
            <div className="carteira-surface carteira-muted rounded-xl border px-4 py-8 text-center text-sm">Carregando...</div>
          ) : null}
        </section>
      ) : (
      <div className="carteira-table-shell rounded-xl overflow-x-auto">
        <table className="w-full min-w-[920px] table-fixed text-sm">
          <thead>
            <tr className="carteira-table-head">
              <th className="w-[118px] px-4 py-3 text-left">OS / Pedido</th>
              <th className="px-4 py-3 text-left">Descrição / Cliente</th>
              <th className="w-[190px] px-4 py-3 text-left">Situação</th>
              <th className="w-[130px] px-4 py-3 text-right">Custo</th>
              {!hideValorPedido && <th className="w-[145px] px-4 py-3 text-right">Valor pedido</th>}
              {!hideValorPedido && <th className="w-[145px] px-4 py-3 text-right">Faturado</th>}
            </tr>
          </thead>

          <tbody>
            {filteredRows.map((r) => {
              const statusExibicao = normalizeOsStatusFluxo(r.status_fluxo, r.status);
              const custo = custoPorOs[r.id] ?? 0;
              const pedido = pedidoDaOs(r);
              const faturado = faturadoPorOs[r.id] ?? 0;
              const progressoFaturado = pedido > 0 ? Math.max(0, Math.min(100, (faturado / pedido) * 100)) : 0;
              const unidade = unidadeDaOs(r);
              return (
              <tr
                key={r.id}
                className="carteira-table-row cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-[var(--carteira-blue)]"
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
                <td className="px-4 py-3 align-middle">
                  <div className="carteira-text font-mono text-[14px] font-semibold tabular-nums">{r.numero_os}</div>
                  {r.pedido_compra?.trim() ? (
                    <div className="carteira-muted mt-1 font-mono text-[10px] tabular-nums" title={`Pedido ${r.pedido_compra}`}>
                      OC {r.pedido_compra}
                    </div>
                  ) : (
                    <div
                      className="mt-1 inline-flex rounded border px-1.5 py-0.5 font-mono text-[9px] font-semibold uppercase tracking-[0.08em]"
                      style={{ color: "var(--carteira-amber)", borderColor: "var(--carteira-amber)", background: "var(--carteira-amber-soft)" }}
                    >
                      sem OC
                    </div>
                  )}
                </td>

                <td className="min-w-0 px-4 py-3 align-middle">
                  <div className="carteira-text truncate text-[13.5px] font-[620] leading-5" title={r.descricao_servico ?? "Sem descrição"}>
                    {r.descricao_servico || "Sem descrição"}
                  </div>
                  <div className="carteira-muted mt-0.5 truncate text-[11.5px]">
                    <span className="font-semibold">{r.cliente_nome || "Sem cliente identificado"}</span>
                    {unidade && <span> · {unidade}</span>}
                  </div>
                </td>

                <td className="px-4 py-3 align-middle">
                  <div className="flex items-center gap-2">
                    <span
                      className="h-1.5 w-1.5 shrink-0 rounded-full"
                      style={{ background: statusColor[statusExibicao ?? ""] ?? "var(--carteira-faint)" }}
                      aria-hidden="true"
                    />
                    <span className="carteira-text text-xs font-medium">{getOsStatusLabel(statusExibicao)}</span>
                  </div>
                  <div className="carteira-muted mt-1 pl-3.5 text-[10.5px]">{responsavelDaOs(r)}</div>
                </td>

                <td className="carteira-muted px-4 py-3 text-right align-middle font-mono text-xs tabular-nums">
                  R$ {formatMoney(custo)}
                </td>
                {!hideValorPedido && (
                  <td className="carteira-text px-4 py-3 text-right align-middle font-mono text-[13px] font-semibold tabular-nums">
                    R$ {formatMoney(pedido)}
                  </td>
                )}
                {!hideValorPedido && (
                  <td className="px-4 py-3 text-right align-middle">
                    <div className="carteira-text font-mono text-[13px] font-semibold tabular-nums">R$ {formatMoney(faturado)}</div>
                    <div
                      className="mt-2 ml-auto h-[3px] w-full overflow-hidden rounded-full bg-[var(--carteira-border)]"
                      title={`${Math.round(progressoFaturado)}% faturado`}
                    >
                      <div className="h-full rounded-full bg-[var(--carteira-green)]" style={{ width: `${progressoFaturado}%` }} />
                    </div>
                  </td>
                )}
              </tr>
              );
            })}

            {loading && (
              <tr>
                <td colSpan={hideValorPedido ? 4 : 6} className="carteira-muted px-4 py-6">
                  Carregando...
                </td>
              </tr>
            )}

            {!loading && filteredRows.length === 0 && (
              <tr>
                <td colSpan={hideValorPedido ? 4 : 6} className="carteira-muted px-4 py-6">
                  Nenhuma OS encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      )}

      {showCreate && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4 overflow-y-auto z-50">
          <div className="w-full max-w-5xl max-h-[90vh] overflow-y-auto bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4 my-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">{createMode === "hh" ? "Nova OS HH" : "Nova OS Fiado"}</div>
                <div className="text-sm text-zinc-400">
                  {createMode === "hh"
                    ? "Crie aqui somente OS de HH. As demais OS devem nascer pelo orçamento."
                    : "OS híbrida: aberta direto, sem orçamento prévio. Permite lançar material/despesa e mão de obra (HH ou apontamento) ao mesmo tempo. Depois dá para gerar um orçamento a partir do que foi executado."}
                </div>
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
                  {creating ? "Criando..." : createMode === "hh" ? "Criar OS HH" : "Criar OS Fiado"}
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
                  disabled={createMode === "hh"}
                  aria-label="Tipo de pedido"
                  title="Tipo de pedido"
                >
                  {createMode === "hh" ? (
                    <option value="servico">Serviço HH</option>
                  ) : (
                    <>
                      <option value="servico">Serviço</option>
                      <option value="material">Material</option>
                    </>
                  )}
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
                    setUsaRelatorioHH(
                      createMode === "hh" ? true : Boolean(clientes.find((c) => c.id === nextId)?.habilita_hh)
                    );
                  }}
                  aria-label="Cliente (cadastro)"
                  title="Cliente (cadastro)"
                >
                  <option value="">-</option>
                  {clientesParaModal.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nome}
                    </option>
                  ))}
                </select>
                {createMode === "hh" && !isApontamentoRh && clientesNovaOsHh.length === 0 && (
                  <div className="text-xs text-amber-300">Nenhum cliente habilitado para HH.</div>
                )}
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Unidade / fábrica</div>
                <select
                  className="w-full px-3 py-2"
                  value={unidadeId ?? ""}
                  onChange={(e) => setUnidadeId(e.target.value ? Number(e.target.value) : null)}
                  disabled={!clienteId || clienteUnidades.length === 0}
                  aria-label="Unidade ou fábrica do cliente"
                  title="Unidade ou fábrica do cliente"
                >
                  <option value="">Sem unidade</option>
                  {clienteUnidades.map((unidade) => (
                    <option key={unidade.id} value={unidade.id}>
                      {unidade.nome}{unidade.codigo ? ` (${unidade.codigo})` : ""}
                    </option>
                  ))}
                </select>
                {clienteId && clienteUnidades.length === 0 && (
                  <div className="text-xs text-zinc-500">Este cliente não possui unidades cadastradas.</div>
                )}
              </div>

              <div className="md:col-span-3 border border-emerald-900/60 rounded-lg p-3 bg-emerald-950/20">
                <label className="flex items-center gap-2 text-sm text-emerald-100">
                  <input type="checkbox" className="h-4 w-4" checked={usaRelatorioHH} readOnly disabled />
                  <span className="font-medium">OS HH</span>
                </label>
                {createMode === "hh" && clienteSelecionadoNaoHabilitaHH && (
                  <div className="mt-2 text-xs text-amber-300">
                    Este cliente não está habilitado para HH. OS comum deve ser criada pelo orçamento.
                  </div>
                )}
                {createMode === "fiado" && clienteId && !usaRelatorioHH && (
                  <div className="mt-2 text-xs text-zinc-400">
                    Este cliente não usa HH — a mão de obra desta OS será registrada por apontamento (por cargo).
                  </div>
                )}
              </div>

              {createMode === "hh" && clienteSelecionadoNaoHabilitaHH && (
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

