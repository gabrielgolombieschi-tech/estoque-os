"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type PlanoContaRow = {
  id: string;
  tenant_id: string;
  codigo: string;
  nome: string;
  parent_id: string | null;
  natureza: "DEBITO" | "CREDITO" | string;
  tipo: "SINTETICA" | "ANALITICA" | string;
  ativo: boolean;
  deleted_at: string | null;
  created_at?: string;
  updated_at?: string;
};

type Node = PlanoContaRow & { depth: number; hasChildren: boolean };

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

function normalize(s: unknown): string {
  return String(s ?? "").trim();
}

function buildFlatTree(rows: PlanoContaRow[], opts: { includeInativos: boolean; q: string }): Node[] {
  const q = opts.q.trim().toLowerCase();

  const visibleBase = rows.filter((r) => {
    if (r.deleted_at) return false;
    if (!opts.includeInativos && !r.ativo) return false;
    if (!q) return true;
    return (
      r.codigo.toLowerCase().includes(q) ||
      r.nome.toLowerCase().includes(q) ||
      `${r.codigo} ${r.nome}`.toLowerCase().includes(q)
    );
  });

  const byId = new Map<string, PlanoContaRow>();
  for (const r of visibleBase) byId.set(r.id, r);

  // Ensure that parents of a matched node also show up (so the hierarchy makes sense).
  if (q) {
    const allById = new Map(rows.filter((r) => !r.deleted_at).map((r) => [r.id, r]));
    for (const r of visibleBase) {
      let pid = r.parent_id;
      while (pid) {
        const p = allById.get(pid);
        if (!p) break;
        if (!opts.includeInativos && !p.ativo) break;
        byId.set(p.id, p);
        pid = p.parent_id;
      }
    }
  }

  const children = new Map<string | null, PlanoContaRow[]>();
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

export default function PlanoContasClient() {
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

  const [rows, setRows] = useState<PlanoContaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [q, setQ] = useState<string>("");
  const [includeInativos, setIncludeInativos] = useState(false);

  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Modal state
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"novo" | "editar">("novo");
  const [formCodigo, setFormCodigo] = useState<string>("");
  const [formNome, setFormNome] = useState<string>("");
  const [formParentId, setFormParentId] = useState<string>("");
  const [formNatureza, setFormNatureza] = useState<"DEBITO" | "CREDITO">("DEBITO");
  const [formTipo, setFormTipo] = useState<"SINTETICA" | "ANALITICA">("ANALITICA");
  const [formAtivo, setFormAtivo] = useState(true);
  const [saving, setSaving] = useState(false);

  const selected = useMemo(() => (selectedId ? rows.find((r) => r.id === selectedId) ?? null : null), [rows, selectedId]);

  const flat = useMemo(() => buildFlatTree(rows, { includeInativos, q }), [rows, includeInativos, q]);

  const totals = useMemo(() => {
    const ativos = rows.filter((r) => !r.deleted_at && r.ativo).length;
    const inativos = rows.filter((r) => !r.deleted_at && !r.ativo).length;
    const total = rows.filter((r) => !r.deleted_at).length;
    return { total, ativos, inativos };
  }, [rows]);

  const reload = async () => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();
      const { data, error } = await supabase
        .schema("f")
        .from("plano_contas")
        .select("id,tenant_id,codigo,nome,parent_id,natureza,tipo,ativo,deleted_at,created_at,updated_at")
        .eq("tenant_id", te.tenantId)
        .order("codigo", { ascending: true })
        .limit(5000);

      if (error) throw error;
      setRows((data ?? []) as unknown as PlanoContaRow[]);

      // Maintain selection if possible
      setSelectedId((prev) => {
        if (!prev) return prev;
        return (data ?? []).some((r: any) => String(r.id) === prev) ? prev : null;
      });
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao carregar plano de contas.");
      setRows([]);
      setSelectedId(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canFinanceiro, te.sessionUserId, te.tenantId]);

  const openNew = (parentId?: string | null) => {
    if (canWrite !== true) return;
    setMode("novo");
    setFormCodigo("");
    setFormNome("");
    setFormParentId(parentId ? String(parentId) : "");
    setFormNatureza("DEBITO");
    setFormTipo("ANALITICA");
    setFormAtivo(true);
    setOpen(true);
  };

  const openEdit = (r: PlanoContaRow) => {
    if (canWrite !== true) return;
    setMode("editar");
    setSelectedId(r.id);
    setFormCodigo(r.codigo);
    setFormNome(r.nome);
    setFormParentId(r.parent_id ?? "");
    setFormNatureza((r.natureza as any) === "CREDITO" ? "CREDITO" : "DEBITO");
    setFormTipo((r.tipo as any) === "SINTETICA" ? "SINTETICA" : "ANALITICA");
    setFormAtivo(Boolean(r.ativo));
    setOpen(true);
  };

  const save = async () => {
    if (canWrite !== true) return;
    if (!te.tenantId) return;

    const codigo = normalize(formCodigo);
    const nome = normalize(formNome);

    if (!codigo) {
      setError("Código é obrigatório.");
      return;
    }
    if (!nome) {
      setError("Nome é obrigatório.");
      return;
    }

    setSaving(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();

      if (mode === "novo") {
        const { error } = await supabase
          .schema("f")
          .from("plano_contas")
          .insert({
            tenant_id: te.tenantId,
            codigo,
            nome,
            parent_id: formParentId ? formParentId : null,
            natureza: formNatureza,
            tipo: formTipo,
            ativo: formAtivo,
          });
        if (error) throw error;
      } else if (mode === "editar" && selectedId) {
        const { error } = await supabase
          .schema("f")
          .from("plano_contas")
          .update({
            codigo,
            nome,
            parent_id: formParentId ? formParentId : null,
            natureza: formNatureza,
            tipo: formTipo,
            ativo: formAtivo,
            updated_at: new Date().toISOString(),
          })
          .eq("id", selectedId);
        if (error) throw error;
      }

      setOpen(false);
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao salvar plano de contas.");
    } finally {
      setSaving(false);
    }
  };

  const toggleAtivo = async (r: PlanoContaRow) => {
    if (canWrite !== true) return;
    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("plano_contas")
        .update({ ativo: !r.ativo, updated_at: new Date().toISOString() })
        .eq("id", r.id);
      if (error) throw error;
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao alterar status.");
    }
  };

  const arquivar = async (r: PlanoContaRow) => {
    if (canWrite !== true) return;
    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("plano_contas")
        .update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", r.id);
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
          <h1 className="text-2xl font-semibold">Plano de Contas</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Estrutura hierárquica para classificação contábil/gerencial (f.plano_contas). No Lucro Real, isso sustenta relatórios e rateios.
          </p>
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
            onClick={() => openNew(selected?.id ?? null)}
            disabled={canWrite !== true}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
          >
            Nova conta
          </button>
        </div>
      </div>

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
            <div className="text-xs text-zinc-400">Total</div>
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

        <div className="text-xs text-zinc-500">
          Dica: use contas <span className="text-zinc-300">SINTÉTICAS</span> como agrupadores e <span className="text-zinc-300">ANALÍTICAS</span> para lançamentos/rateios.
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
            <table className="min-w-[780px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Conta</th>
                  <th className="px-4 py-3">Natureza</th>
                  <th className="px-4 py-3">Tipo</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {!loading && flat.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={4}>
                      Nenhuma conta encontrada.
                    </td>
                  </tr>
                )}
                {flat.map((r) => {
                  const selected = r.id === selectedId;
                  return (
                    <tr
                      key={r.id}
                      className={`border-t border-zinc-900 hover:bg-zinc-900/40 cursor-pointer ${selected ? "bg-zinc-900/50" : ""}`}
                      onClick={() => setSelectedId(r.id)}
                    >
                      <td className="px-4 py-3">
                        <div className={`flex items-center gap-2 ${indentClass(r.depth)}`}>
                          <span className={`text-zinc-100 ${r.tipo === "SINTETICA" ? "font-semibold" : ""}`}>{r.codigo}</span>
                          <span className="text-zinc-300">{r.nome}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span className="inline-flex items-center rounded-full border px-2 py-0.5 text-xs border-zinc-800 bg-zinc-950">
                          {String(r.natureza).toUpperCase()}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className="inline-flex items-center rounded-full border px-2 py-0.5 text-xs border-zinc-800 bg-zinc-950">
                          {String(r.tipo).toUpperCase()}
                        </span>
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
              <div className="text-xs text-zinc-400 mt-1">Selecione uma conta para ver/editar.</div>
            </div>
            {selected && (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => openNew(selected.id)}
                  disabled={canWrite !== true}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
                >
                  Nova filha
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

          {!selected && <div className="mt-6 text-sm text-zinc-400">Nenhuma conta selecionada.</div>}

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

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Natureza</div>
                  <div className="text-zinc-100">{String(selected.natureza).toUpperCase()}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Tipo</div>
                  <div className="text-zinc-100">{String(selected.tipo).toUpperCase()}</div>
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
                  disabled={canWrite !== true}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
                >
                  {selected.ativo ? "Desativar" : "Ativar"}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    const ok = window.confirm("Arquivar conta? Ela ficará com deleted_at e não aparecerá nas listas.");
                    if (ok) void arquivar(selected);
                  }}
                  disabled={canWrite !== true}
                  className="px-3 py-2 rounded-md border border-amber-500/30 bg-amber-500/10 hover:bg-amber-500/15 text-amber-200 text-sm disabled:opacity-60"
                >
                  Arquivar
                </button>
              </div>

              <div className="text-xs text-zinc-500">
                Observação: a tela não impõe regras fiscais (isso fica no uso em títulos/rateios), mas garante organização e trilha de manutenção.
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
                <div className="text-lg font-semibold">{mode === "novo" ? "Nova conta" : "Editar conta"}</div>
                <div className="text-xs text-zinc-400 mt-1">Cadastro em f.plano_contas.</div>
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
                  onChange={(e) => setFormCodigo(e.target.value)}
                  aria-label="Código"
                  placeholder="Ex: 3.01.01"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Nome
                <input
                  value={formNome}
                  onChange={(e) => setFormNome(e.target.value)}
                  aria-label="Nome"
                  placeholder="Ex: Despesas Administrativas"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Natureza
                <select
                  value={formNatureza}
                  onChange={(e) => setFormNatureza(e.target.value as any)}
                  aria-label="Natureza"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                >
                  <option value="DEBITO">DÉBITO</option>
                  <option value="CREDITO">CRÉDITO</option>
                </select>
              </label>
              <label className="block text-xs text-zinc-400">
                Tipo
                <select
                  value={formTipo}
                  onChange={(e) => setFormTipo(e.target.value as any)}
                  aria-label="Tipo"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                >
                  <option value="SINTETICA">SINTÉTICA</option>
                  <option value="ANALITICA">ANALÍTICA</option>
                </select>
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Conta pai
                <select
                  value={formParentId}
                  onChange={(e) => setFormParentId(e.target.value)}
                  aria-label="Conta pai"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                >
                  <option value="">(raiz)</option>
                  {rows
                    .filter((r) => !r.deleted_at && (includeInativos || r.ativo))
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
                  aria-label="Ativo"
                  className="accent-zinc-200"
                />
                Ativo
              </label>
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
