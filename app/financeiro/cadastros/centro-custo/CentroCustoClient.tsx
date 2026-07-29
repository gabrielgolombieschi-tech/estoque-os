"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { upper, upperTrim } from "@/lib/text";

type CentroCustoRow = {
  id: string;
  tenant_id: string;
  empresa_id: string;
  codigo: string;
  nome: string;
  parent_id: string | null;
  ativo: boolean;
  deleted_at: string | null;
  created_at?: string;
  updated_at?: string;
};

type Node = CentroCustoRow & { depth: number; hasChildren: boolean };

const INDENTS = [
  "pl-0",
  "pl-4",
  "pl-8",
  "pl-12",
  "pl-16",
  "pl-20",
  "pl-24",
  "pl-28",
  "pl-32",
] as const;

function indentClass(depth: number) {
  const idx = Math.max(0, Math.min(depth, INDENTS.length - 1));
  return INDENTS[idx];
}

function collectDescendantIds(rows: CentroCustoRow[], rootId: string) {
  const childrenByParent = new Map<string, string[]>();
  for (const row of rows) {
    if (row.deleted_at || !row.parent_id) continue;
    const children = childrenByParent.get(row.parent_id) ?? [];
    children.push(row.id);
    childrenByParent.set(row.parent_id, children);
  }

  const descendants = new Set<string>();
  const visited = new Set<string>([rootId]);
  const pending = [rootId];

  while (pending.length > 0) {
    const currentId = pending.pop();
    if (!currentId) continue;

    for (const childId of childrenByParent.get(currentId) ?? []) {
      if (visited.has(childId)) continue;
      visited.add(childId);
      descendants.add(childId);
      pending.push(childId);
    }
  }

  return descendants;
}

function activeDescendantsLabel(count: number) {
  return count === 1
    ? "1 centro subordinado ativo"
    : `${count} centros subordinados ativos`;
}

function buildFlatTree(rows: CentroCustoRow[], opts: { includeInativos: boolean; q: string; empresaId: string | null }) {
  const q = opts.q.trim().toLowerCase();

  const base = rows.filter((r) => {
    if (r.deleted_at) return false;
    if (opts.empresaId && r.empresa_id !== opts.empresaId) return false;
    if (!opts.includeInativos && !r.ativo) return false;
    if (!q) return true;
    return r.codigo.toLowerCase().includes(q) || r.nome.toLowerCase().includes(q);
  });

  const byId = new Map<string, CentroCustoRow>();
  for (const r of base) byId.set(r.id, r);

  // Show parents for matched nodes.
  if (q) {
    const allById = new Map(rows.filter((r) => !r.deleted_at).map((r) => [r.id, r]));
    for (const r of base) {
      let pid = r.parent_id;
      while (pid) {
        const p = allById.get(pid);
        if (!p) break;
        if (opts.empresaId && p.empresa_id !== opts.empresaId) break;
        if (!opts.includeInativos && !p.ativo) break;
        byId.set(p.id, p);
        pid = p.parent_id;
      }
    }
  }

  const children = new Map<string | null, CentroCustoRow[]>();
  for (const r of byId.values()) {
    const list = children.get(r.parent_id ?? null) ?? [];
    list.push(r);
    children.set(r.parent_id ?? null, list);
  }
  for (const list of children.values()) {
    list.sort((a, b) => a.codigo.localeCompare(b.codigo, "pt-BR", { numeric: true }) || a.nome.localeCompare(b.nome));
  }

  const out: Node[] = [];
  const walk = (parentId: string | null, depth: number) => {
    const list = children.get(parentId) ?? [];
    for (const r of list) {
      const hasChildren = (children.get(r.id) ?? []).length > 0;
      out.push({ ...r, depth, hasChildren });
      walk(r.id, depth + 1);
    }
  };
  walk(null, 0);

  return out;
}

export default function CentroCustoClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  const canWrite = useMemo(() => {
    const w = te.has("financeiro.write");
    if (w === undefined) return undefined;
    return Boolean(w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const empresaId = te.empresaId;
  const empresaNome =
    te.empresa?.nome_fantasia?.trim() ||
    te.empresa?.razao_social?.trim() ||
    "Empresa atual";

  const [rows, setRows] = useState<CentroCustoRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [q, setQ] = useState("");
  const [includeInativos, setIncludeInativos] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"novo" | "editar">("novo");
  const [formCodigo, setFormCodigo] = useState("");
  const [formNome, setFormNome] = useState("");
  const [formParentId, setFormParentId] = useState("");
  const [formAtivo, setFormAtivo] = useState(true);
  const [saving, setSaving] = useState(false);

  const selected = useMemo(() => (selectedId ? rows.find((r) => r.id === selectedId) ?? null : null), [rows, selectedId]);
  const selectedDescendantIds = useMemo(
    () => (selectedId ? collectDescendantIds(rows, selectedId) : new Set<string>()),
    [rows, selectedId]
  );
  const selectedActiveDescendants = useMemo(
    () =>
      selected
        ? rows.filter(
            (row) =>
              !row.deleted_at &&
              row.ativo &&
              selectedDescendantIds.has(row.id)
          ).length
        : 0,
    [rows, selected, selectedDescendantIds]
  );

  const flat = useMemo(
    () => buildFlatTree(rows, { includeInativos, q, empresaId: empresaId ?? null }),
    [rows, includeInativos, q, empresaId]
  );

  const totals = useMemo(() => {
    const scoped = rows.filter((r) => !r.deleted_at && (!empresaId || r.empresa_id === empresaId));
    const ativos = scoped.filter((r) => r.ativo).length;
    const inativos = scoped.filter((r) => !r.ativo).length;
    return { total: scoped.length, ativos, inativos };
  }, [rows, empresaId]);

  const reload = async () => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!empresaId) return;
    if (canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();

      // Note: per project conventions, empresa scoping should be via RLS/current_empresa_id.
      // However this table has empresa_id column, and center-cost is inherently empresa-specific.
      // We still keep a local filter, but the DB should enforce it.
      const { data, error } = await supabase
        .schema("f")
        .from("centro_custo")
        .select("id,tenant_id,empresa_id,codigo,nome,parent_id,ativo,deleted_at,created_at,updated_at")
        .eq("tenant_id", te.tenantId)
        .eq("empresa_id", empresaId)
        .order("codigo", { ascending: true })
        .limit(5000);

      if (error) throw error;
      setRows((data ?? []) as unknown as CentroCustoRow[]);
      setSelectedId((prev) => {
        if (!prev) return prev;
        return (data ?? []).some((row) => {
          const r = row as Record<string, unknown>;
          return String(r.id) === prev;
        })
          ? prev
          : null;
      });
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao carregar centros de custo.");
      setRows([]);
      setSelectedId(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void reload();
    }, 0);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canFinanceiro, te.sessionUserId, te.tenantId, empresaId]);

  const openNew = (parentId?: string | null) => {
    if (canWrite !== true) return;
    setMode("novo");
    setFormCodigo("");
    setFormNome("");
    setFormParentId(parentId ? String(parentId) : "");
    setFormAtivo(true);
    setOpen(true);
  };

  const openEdit = (r: CentroCustoRow) => {
    if (canWrite !== true) return;
    setMode("editar");
    setSelectedId(r.id);
    setFormCodigo(upper(r.codigo));
    setFormNome(upper(r.nome));
    setFormParentId(r.parent_id ?? "");
    setFormAtivo(Boolean(r.ativo));
    setOpen(true);
  };

  const save = async () => {
    if (canWrite !== true) return;
    if (!te.tenantId) return;
    if (!empresaId) {
      setError("Empresa não definida.");
      return;
    }

    const codigo = upperTrim(formCodigo);
    const nome = upperTrim(formNome);

    if (!codigo) {
      setError("Código é obrigatório.");
      return;
    }
    if (!nome) {
      setError("Nome é obrigatório.");
      return;
    }
    if (
      mode === "editar" &&
      selected?.ativo &&
      !formAtivo &&
      selectedActiveDescendants > 0
    ) {
      setError(
        `Este centro possui ${activeDescendantsLabel(selectedActiveDescendants)}. Desative ou mova os centros subordinados antes de desativar o centro principal.`
      );
      return;
    }

    setSaving(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();
      if (mode === "novo") {
        const { error } = await supabase
          .schema("f")
          .from("centro_custo")
          .insert({
            tenant_id: te.tenantId,
            empresa_id: empresaId,
            codigo,
            nome,
            parent_id: formParentId ? formParentId : null,
            ativo: formAtivo,
          });
        if (error) throw error;
      } else if (mode === "editar" && selectedId) {
        const { error } = await supabase
          .schema("f")
          .from("centro_custo")
          .update({
            codigo,
            nome,
            parent_id: formParentId ? formParentId : null,
            ativo: formAtivo,
            updated_at: new Date().toISOString(),
          })
          .eq("id", selectedId)
          .eq("tenant_id", te.tenantId)
          .eq("empresa_id", empresaId);
        if (error) throw error;
      }

      setOpen(false);
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao salvar centro de custo.");
    } finally {
      setSaving(false);
    }
  };

  const toggleAtivo = async (r: CentroCustoRow) => {
    if (canWrite !== true) return;
    if (!te.tenantId || !empresaId) {
      setError("Selecione uma empresa antes de alterar o centro de custo.");
      return;
    }

    const descendantIds = collectDescendantIds(rows, r.id);
    const activeDescendants = rows.filter(
      (row) => !row.deleted_at && row.ativo && descendantIds.has(row.id)
    ).length;
    if (r.ativo && activeDescendants > 0) {
      setError(
        `Este centro possui ${activeDescendantsLabel(activeDescendants)}. Desative ou mova os centros subordinados antes de desativar o centro principal.`
      );
      return;
    }

    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("centro_custo")
        .update({ ativo: !r.ativo, updated_at: new Date().toISOString() })
        .eq("id", r.id)
        .eq("tenant_id", te.tenantId)
        .eq("empresa_id", empresaId);
      if (error) throw error;
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao alterar status.");
    }
  };

  const arquivar = async (r: CentroCustoRow) => {
    if (canWrite !== true) return;
    if (!te.tenantId || !empresaId) {
      setError("Selecione uma empresa antes de arquivar o centro de custo.");
      return;
    }

    const descendantIds = collectDescendantIds(rows, r.id);
    const activeDescendants = rows.filter(
      (row) => !row.deleted_at && row.ativo && descendantIds.has(row.id)
    ).length;
    if (activeDescendants > 0) {
      setError(
        `Este centro possui ${activeDescendantsLabel(activeDescendants)}. Desative ou mova os centros subordinados antes de arquivar o centro principal.`
      );
      return;
    }

    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("centro_custo")
        .update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", r.id)
        .eq("tenant_id", te.tenantId)
        .eq("empresa_id", empresaId);
      if (error) throw error;
      setSelectedId(null);
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao arquivar.");
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Centros de Custo</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Organize receitas e despesas por área para acompanhar custos, resultados e responsabilidades.
          </p>
          {empresaId && (
            <div className="mt-2 text-xs text-zinc-500">
              Empresa atual: <span className="font-medium text-zinc-300">{empresaNome}</span>
            </div>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
          <button
            type="button"
            onClick={() => openNew(null)}
            disabled={canWrite !== true || !empresaId}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
          >
            Novo centro
          </button>
        </div>
      </div>

      {!empresaId && (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-amber-200 text-sm">
          Empresa não definida. Selecione uma empresa no topo antes de editar centros de custo.
        </div>
      )}

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="flex flex-wrap items-end gap-2">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por código ou nome…"
            aria-label="Buscar"
            className="w-full sm:w-[420px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />
          <label className="inline-flex items-center gap-2 text-sm text-zinc-200">
            <input
              type="checkbox"
              checked={includeInativos}
              onChange={(e) => setIncludeInativos(e.target.checked)}
              aria-label="Incluir inativos"
              className="accent-zinc-200"
            />
            Incluir inativos
          </label>
          <button
            type="button"
            onClick={() => {
              setQ("");
              setIncludeInativos(false);
            }}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Limpar
          </button>
          {loading && <div className="text-xs text-zinc-400">Carregando…</div>}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Total (empresa)</div>
            <div className="text-lg font-semibold">{totals.total}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Ativos</div>
            <div className="text-lg font-semibold">{totals.ativos}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Inativos</div>
            <div className="text-lg font-semibold">{totals.inativos}</div>
          </div>
        </div>
      </div>

      {error && <div className="text-sm text-red-300">{error}</div>}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
            <div className="font-semibold">Estrutura</div>
            <div className="text-xs text-zinc-500">{flat.length} itens visíveis</div>
          </div>
          <div className="overflow-auto">
            <table className="min-w-[760px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Centro</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {!loading && flat.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={2}>
                      Nenhum centro de custo encontrado.
                    </td>
                  </tr>
                )}
                {flat.map((r) => {
                  const isSelected = r.id === selectedId;
                  return (
                    <tr
                      key={r.id}
                      className={`border-t border-zinc-900 hover:bg-zinc-900/40 cursor-pointer ${isSelected ? "bg-zinc-900/50" : ""}`}
                      onClick={() => setSelectedId(r.id)}
                    >
                      <td className="px-4 py-3">
                        <div className={`flex items-center gap-2 ${indentClass(r.depth)}`}>
                          <span className="text-zinc-100 font-semibold">{r.codigo}</span>
                          <span className="text-zinc-300">{r.nome}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${
                            r.ativo ? "border-emerald-500/30 bg-emerald-500/15 text-emerald-200" : "border-zinc-700 bg-zinc-900 text-zinc-200"
                          }`}
                        >
                          {r.ativo ? "ATIVO" : "INATIVO"}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-lg font-semibold">Detalhes</div>
              <div className="text-xs text-zinc-400 mt-1">Selecione um centro para ver/editar.</div>
            </div>
            {selected && (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => openNew(selected.id)}
                  disabled={canWrite !== true || !empresaId}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
                >
                  Novo filho
                </button>
                <button
                  type="button"
                  onClick={() => openEdit(selected)}
                  disabled={canWrite !== true}
                  className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                >
                  Editar
                </button>
              </div>
            )}
          </div>

          {!selected && <div className="mt-6 text-sm text-zinc-400">Nenhum centro selecionado.</div>}

          {selected && (
            <div className="mt-4 space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Código</div>
                  <div className="text-zinc-100 font-semibold">{selected.codigo}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Nome</div>
                  <div className="text-zinc-100">{selected.nome}</div>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Empresa</div>
                  <div className="text-zinc-100">{empresaNome}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Status</div>
                  <div className="text-zinc-100">{selected.ativo ? "ATIVO" : "INATIVO"}</div>
                </div>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => toggleAtivo(selected)}
                  disabled={canWrite !== true || (selected.ativo && selectedActiveDescendants > 0)}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
                >
                  {selected.ativo ? "Desativar" : "Ativar"}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    const ok = window.confirm("Arquivar centro de custo? Ele deixará de aparecer nas listas, mas o histórico será preservado.");
                    if (ok) void arquivar(selected);
                  }}
                  disabled={canWrite !== true || selectedActiveDescendants > 0}
                  className="px-3 py-2 rounded-md border border-amber-500/30 bg-amber-500/10 hover:bg-amber-500/15 text-amber-200 text-sm disabled:opacity-60"
                >
                  Arquivar
                </button>
              </div>

              {selectedActiveDescendants > 0 && (
                <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-200">
                  Este centro possui {activeDescendantsLabel(selectedActiveDescendants)}. Desative ou mova os centros subordinados antes de
                  desativar ou arquivar o centro principal.
                </div>
              )}

              <div className="text-xs text-zinc-500">
                Boas práticas: mantenha uma estrutura simples, alinhada às áreas responsáveis pelos gastos e receitas.
              </div>
            </div>
          )}
        </div>
      </div>

      {open && (
        <div className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4">
          <div className="w-full max-w-2xl rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">{mode === "novo" ? "Novo centro" : "Editar centro"}</div>
                <div className="text-xs text-zinc-400 mt-1">O centro será utilizado somente na empresa selecionada.</div>
              </div>
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="px-2 py-1 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Fechar
              </button>
            </div>

            <div className="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-3">
              <label className="block text-xs text-zinc-400">
                Código
                <input
                  value={formCodigo}
                  onChange={(e) => setFormCodigo(upper(e.target.value))}
                  aria-label="Código"
                  placeholder="Ex: 01.01"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Nome
                <input
                  value={formNome}
                  onChange={(e) => setFormNome(upper(e.target.value))}
                  aria-label="Nome"
                  placeholder="Ex: Administrativo"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Centro pai
                <select
                  value={formParentId}
                  onChange={(e) => setFormParentId(e.target.value)}
                  aria-label="Centro pai"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                >
                  <option value="">(raiz)</option>
                  {rows
                    .filter(
                      (r) =>
                        !r.deleted_at &&
                        r.empresa_id === (empresaId ?? "") &&
                        (includeInativos || r.ativo) &&
                        (mode !== "editar" ||
                          (r.id !== selectedId && !selectedDescendantIds.has(r.id)))
                    )
                    .sort((a, b) => a.codigo.localeCompare(b.codigo, "pt-BR", { numeric: true }))
                    .map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.codigo} — {r.nome}
                      </option>
                    ))}
                </select>
              </label>

              <label className="inline-flex items-center gap-2 text-sm text-zinc-200 sm:col-span-2">
                <input
                  type="checkbox"
                  checked={formAtivo}
                  onChange={(e) => setFormAtivo(e.target.checked)}
                  disabled={mode === "editar" && Boolean(selected?.ativo) && selectedActiveDescendants > 0}
                  aria-label="Ativo"
                  className="accent-zinc-200 disabled:opacity-60"
                />
                Ativo
              </label>
              {mode === "editar" && selected?.ativo && selectedActiveDescendants > 0 && (
                <div className="text-xs text-amber-300 sm:col-span-2">
                  Para desativar este centro, primeiro desative ou mova os centros subordinados ativos.
                </div>
              )}
            </div>

            <div className="mt-4 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={save}
                disabled={saving}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
              >
                {saving ? "Salvando…" : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
