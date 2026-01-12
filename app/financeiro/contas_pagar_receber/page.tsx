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
  competencia: string;
  vencimento: string;
  valor_original: number;
  total_baixado: number;
  saldo: number;
  atrasado: boolean;
  categoria_id: string;
};

type CategoriaRow = {
  id: string;
  nome: string;
  tipo: "DESPESA" | "RECEITA";
};

const statusBadge: Record<TituloStatus, string> = {
  ABERTO: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
  BAIXADO: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30",
  CANCELADO: "bg-zinc-500/15 text-zinc-300 border border-zinc-500/30",
};

const naturezaBadge: Record<TituloNatureza, string> = {
  PAGAR: "bg-red-500/15 text-red-300 border border-red-500/30",
  RECEBER: "bg-sky-500/15 text-sky-300 border border-sky-500/30",
};

export default function ContasPagarReceberPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, loading: tenantLoading } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready, permissions } = usePermissions();
  const canView =
    has("financeiro.gerenciar") || (permissions ?? []).some((perm) => perm.startsWith("financeiro."));

  const [rows, setRows] = useState<TituloRow[]>([]);
  const [categorias, setCategorias] = useState<CategoriaRow[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const [q, setQ] = useState("");
  const [natureza, setNatureza] = useState<"todas" | TituloNatureza>("todas");
  const [status, setStatus] = useState<"todos" | TituloStatus>("todos");
  const [categoriaId, setCategoriaId] = useState("todas");
  const [vencimentoInicio, setVencimentoInicio] = useState("");
  const [vencimentoFim, setVencimentoFim] = useState("");

  async function load() {
    setErr(null);
    if (tenantLoading) return;
    if (!tenantId) {
      setErr("Tenant nao carregado.");
      return;
    }

    const { data: titulos, error: titulosErr } = await applyTenant(
      supabase
        .from("vw_financeiro_titulos_com_saldo")
        .select(
          "id,natureza,status,descricao,documento_ref,competencia,vencimento,valor_original,total_baixado,saldo,atrasado,categoria_id"
        ),
      tenantId
    )
      .order("vencimento", { ascending: true })
      .limit(500);
    if (titulosErr) {
      setErr(titulosErr.message);
      return;
    }

    const { data: categoriasData, error: categoriasErr } = await applyTenant(
      supabase
        .from("financeiro_categorias")
        .select("id,nome,tipo")
        .eq("ativo", true),
      tenantId
    ).order("nome", { ascending: true });
    if (categoriasErr) {
      setErr(categoriasErr.message);
      return;
    }

    setRows((titulos ?? []) as TituloRow[]);
    setCategorias((categoriasData ?? []) as CategoriaRow[]);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, tenantLoading]);

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

  let filtered = rows;
  const term = q.trim().toLowerCase();
  if (term) {
    filtered = filtered.filter((r) => {
      const desc = r.descricao.toLowerCase();
      const doc = (r.documento_ref ?? "").toLowerCase();
      return desc.includes(term) || doc.includes(term);
    });
  }

  if (natureza !== "todas") {
    filtered = filtered.filter((r) => r.natureza === natureza);
  }

  if (status !== "todos") {
    filtered = filtered.filter((r) => r.status === status);
  }

  if (categoriaId !== "todas") {
    filtered = filtered.filter((r) => r.categoria_id === categoriaId);
  }

  const ini = vencimentoInicio ? new Date(vencimentoInicio) : null;
  const fim = vencimentoFim ? new Date(vencimentoFim) : null;
  if (ini || fim) {
    filtered = filtered.filter((r) => {
      const d = new Date(r.vencimento);
      if (ini && d < ini) return false;
      if (fim) {
        const f = new Date(fim);
        f.setHours(23, 59, 59, 999);
        if (d > f) return false;
      }
      return true;
    });
  }

  const totalAbertoPagar = filtered
    .filter((r) => r.natureza === "PAGAR" && r.status === "ABERTO")
    .reduce((acc, r) => acc + Number(r.saldo ?? 0), 0);
  const totalAbertoReceber = filtered
    .filter((r) => r.natureza === "RECEBER" && r.status === "ABERTO")
    .reduce((acc, r) => acc + Number(r.saldo ?? 0), 0);
  const totalAtrasado = filtered
    .filter((r) => r.status === "ABERTO" && r.atrasado)
    .reduce((acc, r) => acc + Number(r.saldo ?? 0), 0);

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Contas a pagar/receber</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Controle de titulos financeiros com saldo, vencimento e status.
          </p>
        </div>

        <button
          onClick={load}
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          Atualizar
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="text-xs text-zinc-400">Aberto a pagar</div>
          <div className="text-lg font-semibold text-red-300 mt-1">
            R$ {formatDecimalBR(totalAbertoPagar, 2)}
          </div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="text-xs text-zinc-400">Aberto a receber</div>
          <div className="text-lg font-semibold text-sky-300 mt-1">
            R$ {formatDecimalBR(totalAbertoReceber, 2)}
          </div>
        </div>
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="text-xs text-zinc-400">Atrasado</div>
          <div className="text-lg font-semibold text-amber-300 mt-1">
            R$ {formatDecimalBR(totalAtrasado, 2)}
          </div>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input
              className="w-full px-3 py-2"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Descricao ou documento"
              aria-label="Buscar por descricao ou documento"
            />
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
                <option key={cat.id} value={cat.id}>
                  {cat.nome}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Vencimento inicio</div>
            <input
              className="w-full px-3 py-2"
              type="date"
              value={vencimentoInicio}
              onChange={(e) => setVencimentoInicio(e.target.value)}
              aria-label="Vencimento inicio"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Vencimento fim</div>
            <input
              className="w-full px-3 py-2"
              type="date"
              value={vencimentoFim}
              onChange={(e) => setVencimentoFim(e.target.value)}
              aria-label="Vencimento fim"
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
                  setNatureza("todas");
                  setStatus("todos");
                  setCategoriaId("todas");
                  setVencimentoInicio("");
                  setVencimentoFim("");
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

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Vencimento</th>
              <th className="px-4 py-3 text-left">Descricao</th>
              <th className="px-4 py-3 text-left">Categoria</th>
              <th className="px-4 py-3 text-center">Natureza</th>
              <th className="px-4 py-3 text-center">Status</th>
              <th className="px-4 py-3 text-right">Valor</th>
              <th className="px-4 py-3 text-right">Baixado</th>
              <th className="px-4 py-3 text-right">Saldo</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {filtered.map((r) => {
              const categoria = categoriasMap.get(r.categoria_id);
              return (
                <tr key={r.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 text-zinc-300">
                    <div>{new Date(r.vencimento).toLocaleDateString("pt-BR")}</div>
                    {r.atrasado && r.status === "ABERTO" && (
                      <div className="text-xs text-red-300">Atrasado</div>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <div className="font-medium">{r.descricao}</div>
                    <div className="text-xs text-zinc-400">
                      {r.documento_ref ?? "Sem documento"}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-zinc-300">
                    {categoria?.nome ?? "-"}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <span className={`inline-flex items-center px-2 py-1 rounded-md text-xs ${naturezaBadge[r.natureza]}`}>
                      {r.natureza}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-center">
                    <span className={`inline-flex items-center px-2 py-1 rounded-md text-xs ${statusBadge[r.status]}`}>
                      {r.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">
                    R$ {formatDecimalBR(Number(r.valor_original ?? 0), 2)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-300">
                    R$ {formatDecimalBR(Number(r.total_baixado ?? 0), 2)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">
                    R$ {formatDecimalBR(Number(r.saldo ?? 0), 2)}
                  </td>
                </tr>
              );
            })}

            {filtered.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-6 text-zinc-400">
                  Nenhum titulo encontrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
