"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";
import { formatDecimalBR } from "../../lib/decimal";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny } from "@/lib/auth/capabilities";

type MovTipo = "entrada" | "saida" | "ajuste";

type Fornecedor = { id: number; nome: string; ativo: boolean };

type MovRow = {
  id: number;
  item_id: number;
  tipo: MovTipo;
  quantidade: number;
  motivo: string | null;
  realizado_por: string | null;
  data_movimentacao: string;
  origem_nf_entrada_id: number | null;
  itens: {
    codigo_interno: string;
    nome: string;
    unidade_medida: string | null;
  } | null;
  nf: {
    criado_em: string;
    fornecedor_id: number | null;
    fornecedores?: { nome: string | null } | null;
  } | null;
};

const tipoBadge: Record<MovTipo, string> = {
  entrada: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30",
  saida: "bg-red-500/15 text-red-300 border border-red-500/30",
  ajuste: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
};

export default function MovimentacoesPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId, loading: tenantEmpresaLoading } = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = requireAny(capabilities, ["estoque.read", "estoque.write"]);
  const canAccessPage = canView;

  const [rows, setRows] = useState<MovRow[]>([]);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);
  const [err, setErr] = useState<string | null>(null);

  // filtros
  const [q, setQ] = useState("");
  const [tipo, setTipo] = useState<"todos" | MovTipo>("todos");
  const [motivoFiltro, setMotivoFiltro] = useState("");
  const [usuarioFiltro, setUsuarioFiltro] = useState("");
  const [fornecedorFiltroId, setFornecedorFiltroId] = useState("");
  const [dataInicio, setDataInicio] = useState("");
  const [dataFim, setDataFim] = useState("");

  function dataReferencia(r: MovRow) {
    return r.nf?.criado_em ?? r.data_movimentacao;
  }

  async function loadFornecedores() {
    if (tenantEmpresaLoading) return;
    if (!tenantId) return;
    const { data, error } = await applyTenant(supabase.from("fornecedores").select("id,nome,ativo"), tenantId)
      .eq("ativo", true)
      .order("nome", { ascending: true })
      .limit(500);
    if (!error) setFornecedores((data ?? []) as unknown as Fornecedor[]);
  }

  async function load() {
    setErr(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setErr("Tenant ou empresa nao carregados.");
      return;
    }

    const { data, error } = await applyTenantEmpresa(
      supabase
        .from("movimentacoes")
        .select(
          "id,item_id,tipo,quantidade,motivo,realizado_por,data_movimentacao,origem_nf_entrada_id,itens:itens!movimentacoes_item_id_fkey(codigo_interno,nome,unidade_medida),nf:nf_entrada!movimentacoes_origem_nf_entrada_id_fkey(criado_em,fornecedor_id,fornecedores(nome))"
        ),
      tenantId,
      empresaId
    )
      .order("id", { ascending: false })
      .limit(1000);

    if (error) return setErr(error.message);

    let list = (data ?? []) as unknown as MovRow[];

    const fornecedorIdRaw = fornecedorFiltroId.trim();
    if (fornecedorIdRaw) {
      const fornecedorId = Number.parseInt(fornecedorIdRaw, 10);
      if (!Number.isFinite(fornecedorId)) {
        setErr("Fornecedor invÃ¡lido.");
        setRows([]);
        return;
      }
      list = list.filter((r) => Number(r.nf?.fornecedor_id ?? 0) === fornecedorId);
    }

    const term = q.trim().toLowerCase();
    if (term) {
      list = list.filter((r) => {
        const cod = (r.itens?.codigo_interno ?? "").toLowerCase();
        const nome = (r.itens?.nome ?? "").toLowerCase();
        const mot = (r.motivo ?? "").toLowerCase();
        const forn = (r.nf?.fornecedores?.nome ?? "").toLowerCase();
        return cod.includes(term) || nome.includes(term) || mot.includes(term) || forn.includes(term);
      });
    }

    if (tipo !== "todos") list = list.filter((r) => r.tipo === tipo);

    const motTerm = motivoFiltro.trim().toLowerCase();
    if (motTerm) {
      list = list.filter((r) => (r.motivo ?? "").toLowerCase().includes(motTerm));
    }

    const usuarioTerm = usuarioFiltro.trim().toLowerCase();
    if (usuarioTerm) {
      list = list.filter((r) => (r.realizado_por ?? "").toLowerCase().includes(usuarioTerm));
    }

    const ini = dataInicio ? new Date(dataInicio) : null;
    const fim = dataFim ? new Date(dataFim) : null;
    if (ini || fim) {
      list = list.filter((r) => {
        const d = new Date(dataReferencia(r));
        if (ini && d < ini) return false;
        if (fim) {
          const f = new Date(fim);
          f.setHours(23, 59, 59, 999);
          if (d > f) return false;
        }
        return true;
      });
    }

    list = list.sort((a, b) => {
      const da = new Date(dataReferencia(a)).getTime();
      const db = new Date(dataReferencia(b)).getTime();
      if (db !== da) return db - da;
      return b.id - a.id;
    });

    setRows(list);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tipo, tenantId, empresaId, tenantEmpresaLoading]);

  useEffect(() => {
    void loadFornecedores();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, tenantEmpresaLoading]);

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissoes...
      </div>
    );
  }

  if (!canAccessPage) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Movimentações</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Histórico completo de entradas, saídas e ajustes.
          </p>
        </div>

        <button
          onClick={load}
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          Atualizar
        </button>
      </div>

      {/* Filtros */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-4 lg:grid-cols-7 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input
              className="w-full px-3 py-2"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Código, nome ou motivo"
              aria-label="Buscar movimentacoes"
              title="Buscar movimentacoes"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Tipo</div>
            <select
              className="w-full px-3 py-2"
              value={tipo}
              onChange={(e) => setTipo(e.target.value as "todos" | MovTipo)}
              aria-label="Filtrar por tipo"
              title="Filtrar por tipo"
            >
              <option value="todos">Todos</option>
              <option value="entrada">Entrada</option>
              <option value="saida">Saída</option>
              <option value="ajuste">Ajuste</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor</div>
            <select
              className="w-full px-3 py-2"
              value={fornecedorFiltroId}
              onChange={(e) => setFornecedorFiltroId(e.target.value)}
              aria-label="Filtrar por fornecedor"
              title="Filtrar por fornecedor"
            >
              <option value="">Todos</option>
              {fornecedores.map((f) => (
                <option key={f.id} value={String(f.id)}>
                  {f.nome}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Motivo</div>
            <input
              className="w-full px-3 py-2"
              value={motivoFiltro}
              onChange={(e) => setMotivoFiltro(e.target.value)}
              placeholder="Ex: compra, ajuste..."
              aria-label="Filtrar por motivo"
              title="Filtrar por motivo"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Usuário</div>
            <input
              className="w-full px-3 py-2"
              value={usuarioFiltro}
              onChange={(e) => setUsuarioFiltro(e.target.value)}
              placeholder="Email ou nome"
              aria-label="Filtrar por usuario"
              title="Filtrar por usuario"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Data início</div>
            <input
              className="w-full px-3 py-2"
              type="date"
              value={dataInicio}
              onChange={(e) => setDataInicio(e.target.value)}
              aria-label="Data inicio"
              title="Data inicio"
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
              title="Data fim"
            />
          </div>

          <div className="flex items-end">
            <div className="flex gap-2 w-full">
              <button
                onClick={load}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 w-full"
              >
                Aplicar
              </button>
              <button
                onClick={() => {
                  setQ("");
                  setTipo("todos");
                  setFornecedorFiltroId("");
                  setMotivoFiltro("");
                  setUsuarioFiltro("");
                  setDataInicio("");
                  setDataFim("");
                  void load();
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
              <th className="px-4 py-3 text-left">Data</th>
              <th className="px-4 py-3 text-left">Item</th>
              <th className="px-4 py-3 text-center">Tipo</th>
              <th className="px-4 py-3 text-right">Qtd</th>
              <th className="px-4 py-3 text-left">Motivo</th>
              <th className="px-4 py-3 text-left">Usuário</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => (
              <tr key={r.id} className="hover:bg-zinc-900/40">
                <td className="px-4 py-3 text-zinc-300">
                  {new Date(dataReferencia(r)).toLocaleString("pt-BR")}
                </td>

                <td className="px-4 py-3">
                  {r.itens ? (
                    <>
                      <div className="font-medium">
                        [{r.itens.codigo_interno}] {r.itens.nome}
                      </div>
                      <div className="text-xs text-zinc-400">
                        {r.itens.unidade_medida ?? "UN"}
                      </div>
                    </>
                  ) : (
                    <span className="text-zinc-400">Item {r.item_id}</span>
                  )}
                </td>

                <td className="px-4 py-3 text-center">
                  <span className={`inline-flex items-center px-2 py-1 rounded-md text-xs ${tipoBadge[r.tipo]}`}>
                    {r.tipo}
                  </span>
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  {r.tipo === "saida" ? "-" : "+"}
                  {formatDecimalBR(Number(r.quantidade ?? 0), 3)}
                </td>

                <td className="px-4 py-3 text-zinc-300">{r.motivo ?? "—"}</td>

                <td className="px-4 py-3 text-zinc-400">{r.realizado_por ?? "—"}</td>
              </tr>
            ))}

            {rows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-zinc-400">
                  Nenhuma movimentação encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
