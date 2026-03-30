"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type MotivoCompraRow = {
  id: string;
  tenant_id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
  ativo: boolean;
  created_at?: string;
  updated_at?: string;
  deleted_at: string | null;
};

function normalize(value: unknown): string {
  return String(value ?? "").trim();
}

function upper(value: unknown): string {
  return normalize(value).toUpperCase();
}

function isProtectedCodigo(codigo: string) {
  // Common seed/default used across dashboards/queries.
  return upper(codigo) === "NAO_CLASSIFICADO";
}

export default function MotivosCompraClient() {
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

  const [rows, setRows] = useState<MotivoCompraRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [q, setQ] = useState("");
  const [includeInativos, setIncludeInativos] = useState(false);
  const [onlyRequiresText, setOnlyRequiresText] = useState(false);
  const [onlyRequiresOs, setOnlyRequiresOs] = useState(false);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const selected = useMemo(() => (selectedId ? rows.find((r) => r.id === selectedId) ?? null : null), [rows, selectedId]);

  const totals = useMemo(() => {
    const base = rows.filter((r) => !r.deleted_at);
    const ativos = base.filter((r) => r.ativo).length;
    const inativos = base.filter((r) => !r.ativo).length;
    const reqText = base.filter((r) => r.requires_text).length;
    const reqOs = base.filter((r) => r.requires_os).length;
    return { total: base.length, ativos, inativos, reqText, reqOs };
  }, [rows]);

  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase();
    return rows
      .filter((r) => !r.deleted_at)
      .filter((r) => (includeInativos ? true : r.ativo))
      .filter((r) => (onlyRequiresText ? r.requires_text : true))
      .filter((r) => (onlyRequiresOs ? r.requires_os : true))
      .filter((r) => {
        if (!term) return true;
        const hay = `${r.codigo} ${r.nome}`.toLowerCase();
        return hay.includes(term);
      })
      .sort((a, b) => a.codigo.localeCompare(b.codigo, "pt-BR", { numeric: true }) || a.nome.localeCompare(b.nome, "pt-BR"));
  }, [rows, includeInativos, onlyRequiresOs, onlyRequiresText, q]);

  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"novo" | "editar">("novo");
  const [formCodigo, setFormCodigo] = useState("");
  const [formNome, setFormNome] = useState("");
  const [formRequiresText, setFormRequiresText] = useState(false);
  const [formRequiresOs, setFormRequiresOs] = useState(false);
  const [formAtivo, setFormAtivo] = useState(true);
  const [saving, setSaving] = useState(false);

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
        .from("motivo_compra")
        .select("id,tenant_id,codigo,nome,requires_text,requires_os,ativo,created_at,updated_at,deleted_at")
        .eq("tenant_id", te.tenantId)
        .is("deleted_at", null)
        .order("codigo", { ascending: true })
        .limit(5000);

      if (error) throw error;
      setRows((data ?? []) as unknown as MotivoCompraRow[]);
      setSelectedId((prev) => {
        if (!prev) return prev;
        return (data ?? []).some((r: unknown) => {
          const row = r as Record<string, unknown>;
          return String(row.id ?? "") === prev;
        })
          ? prev
          : null;
      });
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao carregar motivos de compra.");
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

  const openNew = () => {
    if (canWrite !== true) return;
    setMode("novo");
    setFormCodigo("");
    setFormNome("");
    setFormRequiresText(false);
    setFormRequiresOs(false);
    setFormAtivo(true);
    setOpen(true);
  };

  const openEdit = (r: MotivoCompraRow) => {
    if (canWrite !== true) return;
    setMode("editar");
    setSelectedId(r.id);
    setFormCodigo(upper(r.codigo));
    setFormNome(upper(r.nome));
    setFormRequiresText(Boolean(r.requires_text));
    setFormRequiresOs(Boolean(r.requires_os));
    setFormAtivo(Boolean(r.ativo));
    setOpen(true);
  };

  const save = async () => {
    if (canWrite !== true) return;
    if (!te.tenantId) return;

    const codigo = upper(formCodigo);
    const nome = upper(formNome);

    if (!codigo) {
      setError("Código é obrigatório.");
      return;
    }
    if (!nome) {
      setError("Nome é obrigatório.");
      return;
    }
    if (isProtectedCodigo(codigo)) {
      setError("O código NAO_CLASSIFICADO é reservado.");
      return;
    }

    setSaving(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();

      if (mode === "novo") {
        const { error } = await supabase
          .schema("f")
          .from("motivo_compra")
          .insert({
            tenant_id: te.tenantId,
            codigo,
            nome,
            requires_text: formRequiresText,
            requires_os: formRequiresOs,
            ativo: formAtivo,
          });
        if (error) throw error;
      } else if (mode === "editar" && selectedId) {
        const current = rows.find((r) => r.id === selectedId) ?? null;
        if (current && isProtectedCodigo(current.codigo)) {
          setError("Não é permitido editar o motivo reservado NAO_CLASSIFICADO.");
          return;
        }

        const { error } = await supabase
          .schema("f")
          .from("motivo_compra")
          .update({
            codigo,
            nome,
            requires_text: formRequiresText,
            requires_os: formRequiresOs,
            ativo: formAtivo,
            updated_at: new Date().toISOString(),
          })
          .eq("id", selectedId);
        if (error) throw error;
      }

      setOpen(false);
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao salvar motivo de compra.");
    } finally {
      setSaving(false);
    }
  };

  const toggleAtivo = async (r: MotivoCompraRow) => {
    if (canWrite !== true) return;
    if (isProtectedCodigo(r.codigo)) {
      setError("Não é permitido alterar status do motivo reservado NAO_CLASSIFICADO.");
      return;
    }

    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("motivo_compra")
        .update({ ativo: !r.ativo, updated_at: new Date().toISOString() })
        .eq("id", r.id);
      if (error) throw error;
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao alterar status.");
    }
  };

  const arquivar = async (r: MotivoCompraRow) => {
    if (canWrite !== true) return;
    if (isProtectedCodigo(r.codigo)) {
      setError("Não é permitido arquivar o motivo reservado NAO_CLASSIFICADO.");
      return;
    }

    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("motivo_compra")
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
          <h1 className="text-2xl font-semibold">Motivos / Classificação de Compra</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Cadastro de motivos usados na aprovação de AP e importação de XML (f.motivo_compra). No Lucro Real, reforça consistência de
            classificação e justificativas.
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
            onClick={openNew}
            disabled={canWrite !== true}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
          >
            Novo motivo
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
          <label className="inline-flex items-center gap-2 text-sm text-zinc-200">
            <input
              type="checkbox"
              checked={onlyRequiresText}
              onChange={(e) => setOnlyRequiresText(e.target.checked)}
              aria-label="Somente requires_text"
              className="accent-zinc-200"
            />
            Exige texto
          </label>
          <label className="inline-flex items-center gap-2 text-sm text-zinc-200">
            <input
              type="checkbox"
              checked={onlyRequiresOs}
              onChange={(e) => setOnlyRequiresOs(e.target.checked)}
              aria-label="Somente requires_os"
              className="accent-zinc-200"
            />
            Exige OS
          </label>
          <button
            type="button"
            onClick={() => {
              setQ("");
              setIncludeInativos(false);
              setOnlyRequiresText(false);
              setOnlyRequiresOs(false);
            }}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Limpar
          </button>
          {loading && <div className="text-xs text-zinc-400">Carregando…</div>}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-5 gap-3">
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
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Exige texto</div>
            <div className="text-lg font-semibold">{totals.reqText}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Exige OS</div>
            <div className="text-lg font-semibold">{totals.reqOs}</div>
          </div>
        </div>

        <div className="text-xs text-zinc-500">
          Os flags <span className="text-zinc-300">requires_text</span> e <span className="text-zinc-300">requires_os</span> ajudam a
          padronizar justificativas e amarrações operacionais.
        </div>
      </div>

      {error && <div className="text-sm text-red-300">{error}</div>}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
            <div className="font-semibold">Motivos</div>
            <div className="text-xs text-zinc-500">{filtered.length} itens</div>
          </div>
          <div className="overflow-auto">
            <table className="min-w-[860px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Código</th>
                  <th className="px-4 py-3">Nome</th>
                  <th className="px-4 py-3">Regras</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {!loading && filtered.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={4}>
                      Nenhum motivo encontrado.
                    </td>
                  </tr>
                )}
                {filtered.map((r) => {
                  const isSelected = r.id === selectedId;
                  return (
                    <tr
                      key={r.id}
                      className={`border-t border-zinc-900 hover:bg-zinc-900/40 cursor-pointer ${isSelected ? "bg-zinc-900/50" : ""}`}
                      onClick={() => setSelectedId(r.id)}
                    >
                      <td className="px-4 py-3 text-zinc-100 font-semibold">{r.codigo}</td>
                      <td className="px-4 py-3 text-zinc-200">{r.nome}</td>
                      <td className="px-4 py-3">
                        <div className="flex flex-wrap items-center gap-2">
                          {r.requires_text && (
                            <span className="inline-flex items-center rounded-full border px-2 py-0.5 text-xs border-sky-500/30 bg-sky-500/10 text-sky-200">
                              TEXTO
                            </span>
                          )}
                          {r.requires_os && (
                            <span className="inline-flex items-center rounded-full border px-2 py-0.5 text-xs border-emerald-500/30 bg-emerald-500/10 text-emerald-200">
                              OS
                            </span>
                          )}
                          {!r.requires_text && !r.requires_os && (
                            <span className="text-xs text-zinc-500">—</span>
                          )}
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${
                            r.ativo
                              ? "border-emerald-500/30 bg-emerald-500/15 text-emerald-200"
                              : "border-zinc-700 bg-zinc-900 text-zinc-200"
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
              <div className="text-xs text-zinc-400 mt-1">Selecione um motivo para ver/editar.</div>
            </div>
            {selected && (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => openEdit(selected)}
                  disabled={canWrite !== true || isProtectedCodigo(selected.codigo)}
                  className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                >
                  Editar
                </button>
              </div>
            )}
          </div>

          {!selected && <div className="mt-6 text-sm text-zinc-400">Nenhum motivo selecionado.</div>}

          {selected && (
            <div className="mt-4 space-y-3">
              {isProtectedCodigo(selected.codigo) && (
                <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-amber-200 text-sm">
                  Este motivo é reservado (<span className="font-semibold">NAO_CLASSIFICADO</span>) e é usado para apontar títulos ainda
                  não classificados.
                </div>
              )}

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
                  <div className="text-xs text-zinc-400">Exige texto</div>
                  <div className="text-zinc-100">{selected.requires_text ? "SIM" : "NÃO"}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Exige OS</div>
                  <div className="text-zinc-100">{selected.requires_os ? "SIM" : "NÃO"}</div>
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
                  disabled={canWrite !== true || isProtectedCodigo(selected.codigo)}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
                >
                  {selected.ativo ? "Desativar" : "Ativar"}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    const ok = window.confirm("Arquivar motivo? Ele ficará com deleted_at e não aparecerá nas listas.");
                    if (ok) void arquivar(selected);
                  }}
                  disabled={canWrite !== true || isProtectedCodigo(selected.codigo)}
                  className="px-3 py-2 rounded-md border border-amber-500/30 bg-amber-500/10 hover:bg-amber-500/15 text-amber-200 text-sm disabled:opacity-60"
                >
                  Arquivar
                </button>
              </div>

              <div className="text-xs text-zinc-500">
                Usado em: aprovação de títulos AP (RPC <span className="text-zinc-300">f.aprovar_titulo_ap</span>) e gatilhos de validação
                para importação de XML.
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
                <div className="text-lg font-semibold">{mode === "novo" ? "Novo motivo" : "Editar motivo"}</div>
                <div className="text-xs text-zinc-400 mt-1">Cadastro em f.motivo_compra.</div>
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
                  placeholder="Ex: MAT_PROD"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Nome
                <input
                  value={formNome}
                  onChange={(e) => setFormNome(upper(e.target.value))}
                  aria-label="Nome"
                  placeholder="Ex: Materiais para produção"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="inline-flex items-center gap-2 text-sm text-zinc-200 sm:col-span-2">
                <input
                  type="checkbox"
                  checked={formRequiresText}
                  onChange={(e) => setFormRequiresText(e.target.checked)}
                  aria-label="requires_text"
                  className="accent-zinc-200"
                />
                Exigir texto complementar (ex: justificativa / detalhe)
              </label>

              <label className="inline-flex items-center gap-2 text-sm text-zinc-200 sm:col-span-2">
                <input
                  type="checkbox"
                  checked={formRequiresOs}
                  onChange={(e) => setFormRequiresOs(e.target.checked)}
                  aria-label="requires_os"
                  className="accent-zinc-200"
                />
                Exigir OS vinculada
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

              <div className="sm:col-span-2 text-xs text-zinc-500">
                Dica: mantenha códigos estáveis para facilitar dashboards e regras automáticas. Use &quot;Exigir OS&quot; para compras diretamente
                ligadas a execução.
              </div>
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
