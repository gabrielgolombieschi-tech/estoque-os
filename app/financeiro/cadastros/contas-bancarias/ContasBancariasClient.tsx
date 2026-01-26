"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type ContaBancariaRow = {
  id: string;
  tenant_id: string;
  empresa_id: string;
  codigo: string;
  nome: string;
  tipo: "BANCO" | "CAIXA" | string;
  banco: string | null;
  agencia: string | null;
  conta: string | null;
  pix_chave: string | null;
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

function classForTipo(tipo: string | null | undefined) {
  const t = upper(tipo);
  if (t === "BANCO") return "border-sky-500/30 bg-sky-500/10 text-sky-200";
  if (t === "CAIXA") return "border-emerald-500/30 bg-emerald-500/10 text-emerald-200";
  return "border-zinc-700 bg-zinc-900 text-zinc-200";
}

export default function ContasBancariasClient() {
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

  const effectiveEmpresaId = useMemo(() => {
    if (te.empresaId) return te.empresaId;
    if (te.empresas.length === 1) return te.empresas[0].id;
    return null;
  }, [te.empresaId, te.empresas]);

  const [rows, setRows] = useState<ContaBancariaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [q, setQ] = useState("");
  const [includeInativos, setIncludeInativos] = useState(false);
  const [tipo, setTipo] = useState<"" | "BANCO" | "CAIXA">("");

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const selected = useMemo(() => (selectedId ? rows.find((r) => r.id === selectedId) ?? null : null), [rows, selectedId]);

  const totals = useMemo(() => {
    const base = rows.filter((r) => !r.deleted_at);
    const ativos = base.filter((r) => r.ativo).length;
    const inativos = base.filter((r) => !r.ativo).length;
    return { total: base.length, ativos, inativos };
  }, [rows]);

  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase();
    return rows
      .filter((r) => !r.deleted_at)
      .filter((r) => (includeInativos ? true : r.ativo))
      .filter((r) => (tipo ? upper(r.tipo) === tipo : true))
      .filter((r) => {
        if (!term) return true;
        const hay = `${r.codigo} ${r.nome} ${r.banco ?? ""} ${r.agencia ?? ""} ${r.conta ?? ""} ${r.pix_chave ?? ""}`.toLowerCase();
        return hay.includes(term);
      })
      .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR") || a.codigo.localeCompare(b.codigo, "pt-BR"));
  }, [rows, includeInativos, q, tipo]);

  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"novo" | "editar">("novo");
  const [formCodigo, setFormCodigo] = useState("");
  const [formNome, setFormNome] = useState("");
  const [formTipo, setFormTipo] = useState<"BANCO" | "CAIXA">("BANCO");
  const [formBanco, setFormBanco] = useState("");
  const [formAgencia, setFormAgencia] = useState("");
  const [formConta, setFormConta] = useState("");
  const [formPix, setFormPix] = useState("");
  const [formAtivo, setFormAtivo] = useState(true);
  const [saving, setSaving] = useState(false);

  const reload = async () => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!effectiveEmpresaId) return;
    if (canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();

      const { data, error } = await supabase
        .schema("f")
        .from("conta_bancaria")
        .select("id,tenant_id,empresa_id,codigo,nome,tipo,banco,agencia,conta,pix_chave,ativo,created_at,updated_at,deleted_at")
        .eq("tenant_id", te.tenantId)
        .is("deleted_at", null)
        .order("nome", { ascending: true })
        .limit(5000);

      if (error) throw error;
      setRows((data ?? []) as unknown as ContaBancariaRow[]);
      setSelectedId((prev) => {
        if (!prev) return prev;
        return (data ?? []).some((r: any) => String(r.id) === prev) ? prev : null;
      });
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao carregar contas bancárias.");
      setRows([]);
      setSelectedId(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canFinanceiro, te.sessionUserId, te.tenantId, effectiveEmpresaId]);

  const openNew = () => {
    if (canWrite !== true) return;
    if (!effectiveEmpresaId) return;
    setMode("novo");
    setFormCodigo("");
    setFormNome("");
    setFormTipo("BANCO");
    setFormBanco("");
    setFormAgencia("");
    setFormConta("");
    setFormPix("");
    setFormAtivo(true);
    setOpen(true);
  };

  const openEdit = (r: ContaBancariaRow) => {
    if (canWrite !== true) return;
    setMode("editar");
    setSelectedId(r.id);
    setFormCodigo(r.codigo);
    setFormNome(r.nome);
    setFormTipo(upper(r.tipo) === "CAIXA" ? "CAIXA" : "BANCO");
    setFormBanco(r.banco ?? "");
    setFormAgencia(r.agencia ?? "");
    setFormConta(r.conta ?? "");
    setFormPix(r.pix_chave ?? "");
    setFormAtivo(Boolean(r.ativo));
    setOpen(true);
  };

  const save = async () => {
    if (canWrite !== true) return;
    if (!te.tenantId) return;
    if (!effectiveEmpresaId) {
      setError("Empresa não definida.");
      return;
    }

    const codigo = normalize(formCodigo);
    const nome = normalize(formNome);
    const banco = normalize(formBanco) || null;
    const agencia = normalize(formAgencia) || null;
    const conta = normalize(formConta) || null;
    const pix_chave = normalize(formPix) || null;

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
          .from("conta_bancaria")
          .insert({
            tenant_id: te.tenantId,
            empresa_id: effectiveEmpresaId,
            codigo,
            nome,
            tipo: formTipo,
            banco,
            agencia,
            conta,
            pix_chave,
            ativo: formAtivo,
          });
        if (error) throw error;
      } else if (mode === "editar" && selectedId) {
        const { error } = await supabase
          .schema("f")
          .from("conta_bancaria")
          .update({
            codigo,
            nome,
            tipo: formTipo,
            banco,
            agencia,
            conta,
            pix_chave,
            ativo: formAtivo,
            updated_at: new Date().toISOString(),
          })
          .eq("id", selectedId);
        if (error) throw error;
      }

      setOpen(false);
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao salvar conta bancária.");
    } finally {
      setSaving(false);
    }
  };

  const toggleAtivo = async (r: ContaBancariaRow) => {
    if (canWrite !== true) return;
    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("conta_bancaria")
        .update({ ativo: !r.ativo, updated_at: new Date().toISOString() })
        .eq("id", r.id);
      if (error) throw error;
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao alterar status.");
    }
  };

  const arquivar = async (r: ContaBancariaRow) => {
    if (canWrite !== true) return;
    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase
        .schema("f")
        .from("conta_bancaria")
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
          <h1 className="text-2xl font-semibold">Contas Bancárias</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Cadastro de contas para pagamentos/recebimentos, extratos e conciliação (f.conta_bancaria). No Lucro Real, isso sustenta o
            fluxo de caixa e a rastreabilidade.
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
            disabled={canWrite !== true || !effectiveEmpresaId}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
          >
            Nova conta
          </button>
        </div>
      </div>

      {!effectiveEmpresaId && (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-amber-200 text-sm">
          Empresa não definida. Selecione uma empresa no topo antes de cadastrar contas bancárias.
        </div>
      )}

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="flex flex-wrap items-end gap-2">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por código, nome, banco, conta ou PIX…"
            aria-label="Buscar"
            className="w-full sm:w-[460px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />
          <label className="block text-xs text-zinc-400">
            Tipo
            <select
              value={tipo}
              onChange={(e) => setTipo(e.target.value as any)}
              aria-label="Tipo"
              className="mt-1 w-full sm:w-[180px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            >
              <option value="">Todos</option>
              <option value="BANCO">BANCO</option>
              <option value="CAIXA">CAIXA</option>
            </select>
          </label>
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
              setTipo("");
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
            <div className="text-xs text-zinc-400">Ativas</div>
            <div className="text-lg font-semibold">{totals.ativos}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Inativas</div>
            <div className="text-lg font-semibold">{totals.inativos}</div>
          </div>
        </div>

        <div className="text-xs text-zinc-500">
          Dica: use <span className="text-zinc-300">CAIXA</span> para caixa físico e <span className="text-zinc-300">BANCO</span> para
          contas bancárias/contas digitais.
        </div>
      </div>

      {error && <div className="text-sm text-red-300">{error}</div>}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
            <div className="font-semibold">Contas</div>
            <div className="text-xs text-zinc-500">{filtered.length} itens</div>
          </div>
          <div className="overflow-auto">
            <table className="min-w-[980px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Código</th>
                  <th className="px-4 py-3">Nome</th>
                  <th className="px-4 py-3">Tipo</th>
                  <th className="px-4 py-3">Banco</th>
                  <th className="px-4 py-3">Agência</th>
                  <th className="px-4 py-3">Conta</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {!loading && filtered.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={7}>
                      Nenhuma conta encontrada.
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
                        <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${classForTipo(r.tipo)}`}>
                          {upper(r.tipo) || "—"}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-zinc-300">{r.banco ?? "—"}</td>
                      <td className="px-4 py-3 text-zinc-300">{r.agencia ?? "—"}</td>
                      <td className="px-4 py-3 text-zinc-300">{r.conta ?? "—"}</td>
                      <td className="px-4 py-3">
                        <span
                          className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${
                            r.ativo
                              ? "border-emerald-500/30 bg-emerald-500/15 text-emerald-200"
                              : "border-zinc-700 bg-zinc-900 text-zinc-200"
                          }`}
                        >
                          {r.ativo ? "ATIVA" : "INATIVA"}
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
                  <div className="text-xs text-zinc-400">Tipo</div>
                  <div className="text-zinc-100">{upper(selected.tipo) || "—"}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Banco</div>
                  <div className="text-zinc-100">{selected.banco ?? "—"}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">PIX</div>
                  <div className="text-zinc-100 break-all">{selected.pix_chave ?? "—"}</div>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Agência</div>
                  <div className="text-zinc-100">{selected.agencia ?? "—"}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                  <div className="text-xs text-zinc-400">Conta</div>
                  <div className="text-zinc-100">{selected.conta ?? "—"}</div>
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
                    const ok = window.confirm("Arquivar conta bancária? Ela ficará com deleted_at e não aparecerá nas listas.");
                    if (ok) void arquivar(selected);
                  }}
                  disabled={canWrite !== true}
                  className="px-3 py-2 rounded-md border border-amber-500/30 bg-amber-500/10 hover:bg-amber-500/15 text-amber-200 text-sm disabled:opacity-60"
                >
                  Arquivar
                </button>
              </div>

              <div className="text-xs text-zinc-500">
                Observação: extratos e conciliações referenciam esta conta via <span className="text-zinc-300">conta_bancaria_id</span>.
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
                <div className="text-xs text-zinc-400 mt-1">Cadastro em f.conta_bancaria.</div>
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
                  placeholder="Ex: ITAU-001"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Nome
                <input
                  value={formNome}
                  onChange={(e) => setFormNome(e.target.value)}
                  aria-label="Nome"
                  placeholder="Ex: Itaú PJ - Principal"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Tipo
                <select
                  value={formTipo}
                  onChange={(e) => setFormTipo(e.target.value as any)}
                  aria-label="Tipo"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                >
                  <option value="BANCO">BANCO</option>
                  <option value="CAIXA">CAIXA</option>
                </select>
              </label>

              <label className="block text-xs text-zinc-400">
                Banco (texto)
                <input
                  value={formBanco}
                  onChange={(e) => setFormBanco(e.target.value)}
                  aria-label="Banco"
                  placeholder="Ex: Itaú"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Agência
                <input
                  value={formAgencia}
                  onChange={(e) => setFormAgencia(e.target.value)}
                  aria-label="Agência"
                  placeholder="Ex: 1234"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Conta
                <input
                  value={formConta}
                  onChange={(e) => setFormConta(e.target.value)}
                  aria-label="Conta"
                  placeholder="Ex: 12345-6"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Chave PIX
                <input
                  value={formPix}
                  onChange={(e) => setFormPix(e.target.value)}
                  aria-label="Chave PIX"
                  placeholder="Ex: cnpj@banco.com / telefone / EVP"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="inline-flex items-center gap-2 text-sm text-zinc-200 sm:col-span-2">
                <input
                  type="checkbox"
                  checked={formAtivo}
                  onChange={(e) => setFormAtivo(e.target.checked)}
                  aria-label="Ativo"
                  className="accent-zinc-200"
                />
                Ativa
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
