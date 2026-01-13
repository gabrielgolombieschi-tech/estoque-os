"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { applyTenant } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { formatDecimalBR } from "@/lib/decimal";

type TituloStatus = "ABERTO" | "BAIXADO" | "CANCELADO";
type TituloNatureza = "PAGAR" | "RECEBER";

type TituloRow = {
  id: string;
  natureza: TituloNatureza;
  status: TituloStatus;
  descricao: string;
  documento_ref: string | null;
  vencimento: string;
  valor_original: number;
  total_baixado: number;
  saldo: number;
  atrasado: boolean;
  categoria_id: string | null;
  fornecedor_nome: string | null;
};

type CategoriaRow = {
  id: string;
  nome: string;
  tipo: "DESPESA" | "RECEITA";
};

type FornecedorRow = { id: string; nome: string };

type Resumo = {
  saldoHoje: number;
  recebimentosPeriodo: number;
  pagarAtrasado: number;
  saldoFinal: number;
  pagamentosPeriodo: number;
  receberAtrasado: number;
};

type ModalMode = "novo" | "editar" | "baixar" | null;

const statusBadge: Record<TituloStatus, string> = {
  ABERTO: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
  BAIXADO: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30",
  CANCELADO: "bg-zinc-500/15 text-zinc-300 border border-zinc-500/30",
};

function rowTint(natureza: TituloNatureza) {
  return natureza === "RECEBER" ? "bg-emerald-900/5" : "bg-red-900/5";
}

function todayISO() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function isMissingRelation(error: unknown, tableName: string): boolean {
  const msg = typeof error === "object" && error && "message" in error ? String((error as any).message).toLowerCase() : "";
  const code = typeof error === "object" && error && "code" in error ? String((error as any).code) : "";
  return code === "42P01" || msg.includes(`relation \"${tableName}\"`) || msg.includes(tableName);
}

function firstLastDayOfCurrentMonth() {
  const now = new Date();
  const first = new Date(now.getFullYear(), now.getMonth(), 1);
  const last = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  const toISO = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  return { iniISO: toISO(first), fimISO: toISO(last) };
}

export default function ContasPagarReceberPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, loading: tenantLoading } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("financeiro.read");

  const [rows, setRows] = useState<TituloRow[]>([]);
  const [categorias, setCategorias] = useState<CategoriaRow[]>([]);
  const [fornecedores, setFornecedores] = useState<FornecedorRow[]>([]);
  const [resumo, setResumo] = useState<Resumo | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [q, setQ] = useState("");
  const [natureza, setNatureza] = useState<"todas" | TituloNatureza>("todas");
  const [status, setStatus] = useState<"todos" | TituloStatus>("todos");
  const [categoriaId, setCategoriaId] = useState("todas");
  const [fornecedorId, setFornecedorId] = useState("todos");
  const [{ iniISO, fimISO }] = useState(firstLastDayOfCurrentMonth());
  const [dataIni, setDataIni] = useState("");
  const [dataFim, setDataFim] = useState("");

  // Modal para novo/editar/baixar
  const [modalMode, setModalMode] = useState<ModalMode>(null);
  const [tituloSelecionado, setTituloSelecionado] = useState<TituloRow | null>(null);
  
  // Form do modal
  const [formDescricao, setFormDescricao] = useState("");
  const [formDocumento, setFormDocumento] = useState("");
  const [formVencimento, setFormVencimento] = useState("");
  const [formValor, setFormValor] = useState("");
  const [formNatureza, setFormNatureza] = useState<TituloNatureza>("RECEBER");
  const [formCategoria, setFormCategoria] = useState("");
  
  // Baixa
  const [formValorBaixa, setFormValorBaixa] = useState("");
  const [formJuros, setFormJuros] = useState("");
  const [formMulta, setFormMulta] = useState("");
  const [formDesconto, setFormDesconto] = useState("");
  const [formDataBaixa, setFormDataBaixa] = useState("");

  useEffect(() => {
    // Inicializa datas com mês vigente
    setDataIni(iniISO);
    setDataFim(fimISO);
  }, [iniISO, fimISO]);

  async function loadFornecedores() {
    if (!tenantId) return;
    try {
      const { data, error } = await applyTenant(
        supabase.from("fornecedores").select("id,nome").eq("ativo", true),
        tenantId
      );
      if (error) {
        if (isMissingRelation(error, "fornecedores")) {
          const { data: pessoas, error: pessoasErr } = await applyTenant(
            supabase.from("pessoas").select("id,nome"),
            tenantId
          );
          if (pessoasErr) throw pessoasErr;
          setFornecedores((pessoas ?? []).map((p: any) => ({ id: String(p.id), nome: p.nome })));
        } else {
          throw error;
        }
      } else {
        setFornecedores((data ?? []).map((f: any) => ({ id: String(f.id), nome: f.nome })));
      }
    } catch (e: any) {
      // Fallback: vazio
      setFornecedores([]);
    }
  }

  async function loadCategorias() {
    if (!tenantId) return;
    const { data, error } = await applyTenant(
      supabase.from("financeiro_categorias").select("id,nome,tipo").eq("ativo", true),
      tenantId
    ).order("nome", { ascending: true });
    if (!error) setCategorias((data ?? []) as CategoriaRow[]);
  }

  async function loadResumo() {
    if (!tenantId) return;
    try {
      const { data, error } = await supabase.rpc("financeiro_dashboard_resumo", {
        p_tenant_id: tenantId,
        p_data_ini: dataIni || iniISO,
        p_data_fim: dataFim || fimISO,
        p_status: status === "todos" ? null : status,
        p_natureza: natureza === "todas" ? null : natureza,
        p_categoria_id: categoriaId === "todas" ? null : categoriaId,
        p_fornecedor_id: fornecedorId === "todos" ? null : fornecedorId,
        p_q: q || null,
      });
      if (error) throw error;
      setResumo((data ?? null) as Resumo | null);
    } catch (e: any) {
      // Fallback simples usando dados carregados
      const hoje = new Date();
      const parseISO = (s: string) => new Date(s + "T00:00:00");
      const fim = parseISO(dataFim || fimISO);
      const receberAtrasado = rows.filter(r => r.natureza === "RECEBER" && r.status === "ABERTO" && new Date(r.vencimento) < hoje).reduce((a, r) => a + Number(r.saldo || 0), 0);
      const pagarAtrasado = rows.filter(r => r.natureza === "PAGAR" && r.status === "ABERTO" && new Date(r.vencimento) < hoje).reduce((a, r) => a + Number(r.saldo || 0), 0);
      const recebimentosPeriodo = rows.filter(r => r.natureza === "RECEBER").reduce((a, r) => a + Number(r.total_baixado || 0), 0);
      const pagamentosPeriodo = rows.filter(r => r.natureza === "PAGAR").reduce((a, r) => a + Math.abs(Number(r.total_baixado || 0)), 0);
      setResumo({
        saldoHoje: 0,
        recebimentosPeriodo,
        pagarAtrasado,
        saldoFinal: 0 + (receberAtrasado - pagarAtrasado),
        pagamentosPeriodo,
        receberAtrasado,
      });
    }
  }

  async function loadTitulos() {
    setErr(null);
    if (tenantLoading) return;
    if (!tenantId) {
      setErr("Tenant nao carregado.");
      return;
    }

    // Tenta RPC com filtros
    try {
      const { data, error } = await supabase.rpc("financeiro_titulos_listar", {
        p_tenant_id: tenantId,
        p_data_ini: dataIni || iniISO,
        p_data_fim: dataFim || fimISO,
        p_status: status === "todos" ? null : status,
        p_natureza: natureza === "todas" ? null : natureza,
        p_categoria_id: categoriaId === "todas" ? null : categoriaId,
        p_fornecedor_id: fornecedorId === "todos" ? null : fornecedorId,
        p_q: q || null,
        p_limit: 500,
        p_offset: 0,
      });
      if (error) throw error;
      setRows((data ?? []) as TituloRow[]);
      return;
    } catch (e: any) {
      // Fallback: usar view básica
      const { data: titulos, error: titulosErr } = await applyTenant(
        supabase
          .from("vw_financeiro_titulos_com_saldo")
          .select("*"),
        tenantId
      ).order("vencimento", { ascending: true }).limit(500);
      if (titulosErr) {
        setErr(titulosErr.message);
        return;
      }
      setRows((titulos ?? []).map((t: any) => ({
        id: t.id,
        natureza: t.natureza,
        status: t.status,
        descricao: t.descricao,
        documento_ref: t.documento_ref,
        vencimento: t.vencimento,
        valor_original: t.valor_original,
        total_baixado: t.total_baixado,
        saldo: t.saldo,
        atrasado: t.atrasado,
        categoria_id: t.categoria_id,
        fornecedor_nome: t.fornecedor_nome || null,
      })) as TituloRow[]);
    }
  }

  async function loadAll() {
    setBusy(true);
    await Promise.all([loadCategorias(), loadFornecedores(), loadTitulos(), loadResumo()]);
    setBusy(false);
  }

  useEffect(() => {
    void loadAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, tenantLoading, dataIni, dataFim, natureza, status, categoriaId, fornecedorId, q]);

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissoes...
      </div>
    );
  }

  if (!canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  const categoriasMap = new Map(categorias.map((c) => [c.id, c]));

  // Filtros client-side (aplicados também no fallback)
  let filtered = rows.filter((r) => {
    const term = q.trim().toLowerCase();
    const matchQ = !term || r.descricao.toLowerCase().includes(term) || (r.documento_ref ?? "").toLowerCase().includes(term);
    const matchNatureza = natureza === "todas" || r.natureza === natureza;
    const matchStatus = status === "todos" || r.status === status;
    const matchCategoria = categoriaId === "todas" || r.categoria_id === categoriaId;
    const matchFornecedor = fornecedorId === "todos" || String(r.fornecedor_nome ?? "").toLowerCase().includes(String(term)) || false;
    const d = new Date(r.vencimento);
    const ini = dataIni ? new Date(dataIni) : null;
    const fim = dataFim ? new Date(dataFim) : null;
    const matchPeriodo = (!ini || d >= ini) && (!fim || d <= new Date(fim.getFullYear(), fim.getMonth(), fim.getDate(), 23, 59, 59, 999));
    return matchQ && matchNatureza && matchStatus && matchCategoria && matchPeriodo && matchFornecedor;
  });

  const totalReceber = filtered.filter((r) => r.natureza === "RECEBER");
  const totalPagar = filtered.filter((r) => r.natureza === "PAGAR");
  const resumoReceber = {
    count: totalReceber.length,
    valor: totalReceber.reduce((acc, r) => acc + Number(r.valor_original || 0), 0),
    baixado: totalReceber.reduce((acc, r) => acc + Number(r.total_baixado || 0), 0),
    saldo: totalReceber.reduce((acc, r) => acc + Number(r.saldo || 0), 0),
  };
  const resumoPagar = {
    count: totalPagar.length,
    valor: totalPagar.reduce((acc, r) => acc + Number(r.valor_original || 0), 0),
    baixado: totalPagar.reduce((acc, r) => acc + Number(r.total_baixado || 0), 0),
    saldo: totalPagar.reduce((acc, r) => acc + Number(r.saldo || 0), 0),
  };

  const hoje = new Date();
  const daysLate = (vencISO: string) => {
    const d = new Date(vencISO);
    const diff = Math.floor((hoje.getTime() - d.getTime()) / (1000 * 60 * 60 * 24));
    return diff > 0 ? diff : 0;
  };

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Painel Financeiro</h1>
          <p className="text-sm text-zinc-400 mt-1">Visão de caixa com KPIs e filtros.</p>
        </div>

        <div className="flex gap-2">
          <button
            onClick={() => {
              setFormNatureza("PAGAR");
              setFormDescricao("");
              setFormDocumento("");
              setFormVencimento(todayISO());
              setFormValor("");
              setFormCategoria("");
              setTituloSelecionado(null);
              setModalMode("novo");
            }}
            className="px-3 py-2 rounded-md border border-red-600/50 bg-red-900/20 hover:bg-red-900/30 text-red-300 text-sm"
          >
            + A Pagar
          </button>
          <button
            onClick={() => {
              setFormNatureza("RECEBER");
              setFormDescricao("");
              setFormDocumento("");
              setFormVencimento(todayISO());
              setFormValor("");
              setFormCategoria("");
              setTituloSelecionado(null);
              setModalMode("novo");
            }}
            className="px-3 py-2 rounded-md border border-emerald-600/50 bg-emerald-900/20 hover:bg-emerald-900/30 text-emerald-300 text-sm"
          >
            + A Receber
          </button>
          <button
            onClick={loadAll}
            disabled={busy}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      {/* Cards 2 linhas com 4 colunas */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
        {/* Linha 1 */}
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="text-xs text-zinc-400">Saldo bancário hoje</div>
          <div className="text-2xl font-semibold text-sky-300 mt-1">R$ {formatDecimalBR(resumo?.saldoHoje ?? 0, 2)}</div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="text-xs text-zinc-400">Recebimento (no período)</div>
          <div className="text-2xl font-semibold text-emerald-300 mt-1">R$ {formatDecimalBR(resumo?.recebimentosPeriodo ?? 0, 2)}</div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-gradient-to-br from-emerald-900/20 to-emerald-900/10 border-emerald-600/30">
          <div className="text-xs text-emerald-400 font-semibold">A RECEBER (no período)</div>
          <div className="text-2xl font-bold text-emerald-300 mt-2">R$ {formatDecimalBR(resumoReceber.saldo, 2)}</div>
          <div className="text-xs text-emerald-200/70 mt-2">{resumoReceber.count} títulos</div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-gradient-to-br from-emerald-900/20 to-emerald-900/10 border-emerald-600/30">
          <div className="text-xs text-emerald-400 font-semibold">A receber atrasado</div>
          <div className="text-2xl font-bold text-emerald-300 mt-2">R$ {formatDecimalBR(resumo?.receberAtrasado ?? 0, 2)}</div>
        </div>

        {/* Linha 2 */}
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="text-xs text-zinc-400">Saldo final (No periodo)</div>
          <div className="text-2xl font-semibold text-sky-300 mt-1">R$ {formatDecimalBR(resumo?.saldoFinal ?? 0, 2)}</div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="text-xs text-zinc-400">Pagamentos (no período)</div>
          <div className="text-2xl font-semibold text-red-300 mt-1">R$ {formatDecimalBR(Math.abs(resumo?.pagamentosPeriodo ?? 0), 2)}</div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-gradient-to-br from-red-900/20 to-red-900/10 border-red-600/30">
          <div className="text-xs text-red-400 font-semibold">A PAGAR (No periodo)</div>
          <div className="text-2xl font-bold text-red-300 mt-2">R$ {formatDecimalBR(resumoPagar.saldo, 2)}</div>
          <div className="text-xs text-red-200/70 mt-2">{resumoPagar.count} títulos</div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-gradient-to-br from-red-900/20 to-red-900/10 border-red-600/30">
          <div className="text-xs text-red-400 font-semibold">A pagar atrasado</div>
          <div className="text-2xl font-bold text-red-300 mt-2">R$ {formatDecimalBR(resumo?.pagarAtrasado ?? 0, 2)}</div>
        </div>
      </div>

      {/* Filtros principais */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Descrição / Documento</div>
            <input
              className="w-full px-3 py-2"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Descrição ou documento"
              aria-label="Buscar por descricao ou documento"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor/Pessoa</div>
            <select
              className="w-full px-3 py-2"
              value={fornecedorId}
              onChange={(e) => setFornecedorId(e.target.value)}
              aria-label="Fornecedor/Pessoa"
            >
              <option value="todos">Todos</option>
              {fornecedores.map((f) => (
                <option key={f.id} value={f.id}>{f.nome}</option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Natureza</div>
            <select
              className="w-full px-3 py-2"
              value={natureza}
              onChange={(e) => setNatureza(e.target.value as "todas" | TituloNatureza)}
              aria-label="Natureza"
            >
              <option value="todas">Todas</option>
              <option value="PAGAR">Pagar</option>
              <option value="RECEBER">Receber</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Status</div>
            <select
              className="w-full px-3 py-2"
              value={status}
              onChange={(e) => setStatus(e.target.value as "todos" | TituloStatus)}
              aria-label="Status"
            >
              <option value="todos">Todos</option>
              <option value="ABERTO">Aberto</option>
              <option value="BAIXADO">Baixado</option>
              <option value="CANCELADO">Cancelado</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Categoria</div>
            <select
              className="w-full px-3 py-2"
              value={categoriaId}
              onChange={(e) => setCategoriaId(e.target.value)}
              aria-label="Categoria"
            >
              <option value="todas">Todas</option>
              {categorias.map((cat) => (
                <option key={cat.id} value={cat.id}>{cat.nome}</option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Data início</div>
            <input
              className="w-full px-3 py-2"
              type="date"
              value={dataIni}
              onChange={(e) => setDataIni(e.target.value)}
              aria-label="Data início"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Data fim</div>
            <input
              className="w-full px-3 py-2"
              type="date"
              value={dataFim}
              onChange={(e) => setDataFim(e.target.value)}
              aria-label="Data fim"
            />
          </div>

          <div className="flex items-end">
            <div className="flex gap-2 w-full">
              <button
                onClick={loadAll}
                disabled={busy}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 w-full"
              >
                Aplicar
              </button>
              <button
                onClick={() => {
                  setQ("");
                  setNatureza("todas");
                  setStatus("todos");
                  setCategoriaId("todas");
                  setFornecedorId("todos");
                  const { iniISO: dIni, fimISO: dFim } = firstLastDayOfCurrentMonth();
                  setDataIni(dIni);
                  setDataFim(dFim);
                  void loadAll();
                }}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 w-full"
              >
                Limpar
              </button>
            </div>
          </div>
        </div>
        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
      </div>

      {/* Tabela */}
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Vencimento</th>
              <th className="px-4 py-3 text-left">Descrição</th>
              <th className="px-4 py-3 text-center">Status</th>
              <th className="px-4 py-3 text-right">Valor</th>
              <th className="px-4 py-3 text-right">Baixado</th>
              <th className="px-4 py-3 text-right">Saldo</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {filtered.map((r) => (
              <tr
                key={r.id}
                onClick={() => {
                  setTituloSelecionado(r);
                  setFormDescricao(r.descricao);
                  setFormDocumento(r.documento_ref ?? "");
                  setFormVencimento(r.vencimento);
                  setFormValor(String(r.valor_original ?? 0));
                  setFormNatureza(r.natureza);
                  setFormCategoria(r.categoria_id ?? "");
                  setFormValorBaixa(String(r.saldo ?? 0));
                  setFormJuros("");
                  setFormMulta("");
                  setFormDesconto("");
                  setFormDataBaixa(todayISO());
                  setModalMode("editar");
                }}
                className={`hover:bg-zinc-900/60 cursor-pointer transition-colors ${rowTint(r.natureza)}`}
              >
                <td className="px-4 py-3 text-zinc-300">
                  <div>{new Date(r.vencimento).toLocaleDateString("pt-BR")}</div>
                  {r.atrasado && r.status === "ABERTO" && (
                    <div className="text-xs text-red-300">Atrasado {daysLate(r.vencimento)} d</div>
                  )}
                </td>
                <td className="px-4 py-3">
                  <div className="font-medium">{r.descricao}</div>
                  <div className="text-xs text-zinc-400">{r.documento_ref ?? "Sem documento"}</div>
                </td>
                <td className="px-4 py-3 text-center">
                  <span className={`inline-flex items-center px-2 py-1 rounded-md text-xs ${statusBadge[r.status]}`}>{r.status}</span>
                </td>
                <td className="px-4 py-3 text-right tabular-nums">R$ {formatDecimalBR(Number(r.valor_original ?? 0), 2)}</td>
                <td className="px-4 py-3 text-right tabular-nums text-zinc-300">R$ {formatDecimalBR(Number(r.total_baixado ?? 0), 2)}</td>
                <td className="px-4 py-3 text-right tabular-nums">R$ {formatDecimalBR(Number(r.saldo ?? 0), 2)}</td>
              </tr>
            ))}

            {filtered.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-zinc-400">Nenhum título encontrado.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Linhas de resumo */}
      <div className="space-y-2">
        <div className="rounded-lg p-3 bg-gradient-to-r from-emerald-900/30 to-emerald-700/20 border border-emerald-600/30">
          <div className="flex items-center justify-between">
            <div className="font-semibold text-emerald-300">A RECEBER</div>
            <div className="text-sm text-emerald-200">{resumoReceber.count} títulos</div>
          </div>
          <div className="mt-2 grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
            <div className="text-emerald-200">Total Valor: R$ {formatDecimalBR(resumoReceber.valor, 2)}</div>
            <div className="text-emerald-200">Total Baixado: R$ {formatDecimalBR(resumoReceber.baixado, 2)}</div>
            <div className="text-emerald-200">Total Saldo: R$ {formatDecimalBR(resumoReceber.saldo, 2)}</div>
          </div>
        </div>
        <div className="rounded-lg p-3 bg-gradient-to-r from-red-900/30 to-red-700/20 border border-red-600/30">
          <div className="flex items-center justify-between">
            <div className="font-semibold text-red-300">A PAGAR</div>
            <div className="text-sm text-red-200">{resumoPagar.count} títulos</div>
          </div>
          <div className="mt-2 grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
            <div className="text-red-200">Total Valor: R$ {formatDecimalBR(resumoPagar.valor, 2)}</div>
            <div className="text-red-200">Total Baixado: R$ {formatDecimalBR(resumoPagar.baixado, 2)}</div>
            <div className="text-red-200">Total Saldo: R$ {formatDecimalBR(resumoPagar.saldo, 2)}</div>
          </div>
        </div>
      </div>

      {/* Modal de Novo/Editar/Baixar */}
      {modalMode && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70" onClick={() => setModalMode(null)}>
          <div
            className="bg-zinc-900 border border-zinc-700 rounded-xl shadow-2xl max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-6 border-b border-zinc-700 flex items-center justify-between">
              <h2 className="text-xl font-semibold">
                {modalMode === "novo"
                  ? `Novo Título - ${formNatureza === "PAGAR" ? "A Pagar" : "A Receber"}`
                  : modalMode === "editar"
                  ? "Editar / Baixar Título"
                  : "Dar Baixa"}
              </h2>
              <button
                onClick={() => setModalMode(null)}
                className="text-zinc-400 hover:text-zinc-200"
              >
                ✕
              </button>
            </div>

            <div className="p-6 space-y-4">
              {/* Descrição */}
              <div>
                <label className="text-xs text-zinc-400">Descrição</label>
                <input
                  type="text"
                  value={formDescricao}
                  onChange={(e) => setFormDescricao(e.target.value)}
                  className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                  placeholder="Descrição do título"
                />
              </div>

              {/* Documento */}
              <div>
                <label className="text-xs text-zinc-400">Documento / Referência</label>
                <input
                  type="text"
                  value={formDocumento}
                  onChange={(e) => setFormDocumento(e.target.value)}
                  className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                  placeholder="NF, Cheque, etc."
                />
              </div>

              {/* Vencimento */}
              <div>
                <label className="text-xs text-zinc-400">Vencimento</label>
                <input
                  type="date"
                  value={formVencimento}
                  onChange={(e) => setFormVencimento(e.target.value)}
                  className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                />
              </div>

              {/* Valor Original */}
              <div>
                <label className="text-xs text-zinc-400">Valor Original</label>
                <input
                  type="text"
                  value={formValor}
                  onChange={(e) => setFormValor(e.target.value)}
                  className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                  placeholder="0,00"
                />
              </div>

              {/* Categoria */}
              <div>
                <label className="text-xs text-zinc-400">Categoria</label>
                <select
                  value={formCategoria}
                  onChange={(e) => setFormCategoria(e.target.value)}
                  className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                >
                  <option value="">Selecione...</option>
                  {categorias.map((cat) => (
                    <option key={cat.id} value={cat.id}>
                      {cat.nome}
                    </option>
                  ))}
                </select>
              </div>

              {/* Seção de Baixa (apenas se for editar e tiver saldo) */}
              {modalMode === "editar" && tituloSelecionado && tituloSelecionado.saldo > 0 && (
                <>
                  <hr className="border-zinc-700 my-4" />
                  <div className="text-sm font-semibold text-zinc-300">Registrar Baixa</div>

                  {/* Data da Baixa */}
                  <div>
                    <label className="text-xs text-zinc-400">Data da Baixa</label>
                    <input
                      type="date"
                      value={formDataBaixa}
                      onChange={(e) => setFormDataBaixa(e.target.value)}
                      className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                    />
                  </div>

                  {/* Valor da Baixa */}
                  <div>
                    <label className="text-xs text-zinc-400">Valor da Baixa</label>
                    <input
                      type="text"
                      value={formValorBaixa}
                      onChange={(e) => setFormValorBaixa(e.target.value)}
                      className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                      placeholder="0,00"
                    />
                  </div>

                  {/* Juros */}
                  <div>
                    <label className="text-xs text-zinc-400">Juros</label>
                    <input
                      type="text"
                      value={formJuros}
                      onChange={(e) => setFormJuros(e.target.value)}
                      className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                      placeholder="0,00"
                    />
                  </div>

                  {/* Multa */}
                  <div>
                    <label className="text-xs text-zinc-400">Multa</label>
                    <input
                      type="text"
                      value={formMulta}
                      onChange={(e) => setFormMulta(e.target.value)}
                      className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                      placeholder="0,00"
                    />
                  </div>

                  {/* Desconto */}
                  <div>
                    <label className="text-xs text-zinc-400">Desconto</label>
                    <input
                      type="text"
                      value={formDesconto}
                      onChange={(e) => setFormDesconto(e.target.value)}
                      className="w-full mt-1 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                      placeholder="0,00"
                    />
                  </div>
                </>
              )}
            </div>

            {/* Botões */}
            <div className="p-6 border-t border-zinc-700 flex gap-2 justify-end">
              <button
                onClick={() => setModalMode(null)}
                className="px-4 py-2 rounded border border-zinc-600 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              {modalMode === "editar" && tituloSelecionado && tituloSelecionado.saldo > 0 && (
                <button
                  onClick={async () => {
                    if (!tenantId) return;
                    setBusy(true);
                    try {
                      const valorBaixa = parseFloat(formValorBaixa.replace(",", ".")) || 0;
                      const juros = parseFloat(formJuros.replace(",", ".")) || 0;
                      const multa = parseFloat(formMulta.replace(",", ".")) || 0;
                      const desconto = parseFloat(formDesconto.replace(",", ".")) || 0;

                      const { error: movErr } = await supabase.from("financeiro_movimentos").insert({
                        tenant_id: tenantId,
                        titulo_id: tituloSelecionado.id,
                        data_movimento: formDataBaixa,
                        valor: valorBaixa,
                        juros,
                        multa,
                        desconto,
                      });
                      if (movErr) throw movErr;

                      setModalMode(null);
                      await loadAll();
                    } catch (e) {
                      alert(`Erro ao registrar baixa: ${e instanceof Error ? e.message : String(e)}`);
                    } finally {
                      setBusy(false);
                    }
                  }}
                  className="px-4 py-2 rounded bg-emerald-600 hover:bg-emerald-700 text-white"
                >
                  Registrar Baixa
                </button>
              )}
              <button
                onClick={async () => {
                  if (!tenantId) return;
                  if (!formDescricao.trim()) {
                    alert("Descrição é obrigatória");
                    return;
                  }
                  setBusy(true);
                  try {
                    const valor = parseFloat(formValor.replace(",", ".")) || 0;
                    if (valor <= 0) {
                      alert("Valor deve ser maior que zero");
                      return;
                    }

                    if (modalMode === "novo") {
                      const { error: tituloErr } = await supabase.from("financeiro_titulos").insert({
                        tenant_id: tenantId,
                        natureza: formNatureza,
                        status: "ABERTO",
                        descricao: formDescricao,
                        documento_ref: formDocumento || null,
                        vencimento: formVencimento,
                        valor_original: valor,
                        categoria_id: formCategoria || null,
                      });
                      if (tituloErr) throw tituloErr;
                    } else if (modalMode === "editar" && tituloSelecionado) {
                      const { error: tituloErr } = await supabase
                        .from("financeiro_titulos")
                        .update({
                          descricao: formDescricao,
                          documento_ref: formDocumento || null,
                          vencimento: formVencimento,
                          valor_original: valor,
                          categoria_id: formCategoria || null,
                        })
                        .eq("id", tituloSelecionado.id);
                      if (tituloErr) throw tituloErr;
                    }

                    setModalMode(null);
                    await loadAll();
                  } catch (e) {
                    alert(`Erro ao salvar: ${e instanceof Error ? e.message : String(e)}`);
                  } finally {
                    setBusy(false);
                  }
                }}
                className="px-4 py-2 rounded bg-blue-600 hover:bg-blue-700 text-white"
              >
                {modalMode === "novo" ? "Criar Título" : "Salvar Edição"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
