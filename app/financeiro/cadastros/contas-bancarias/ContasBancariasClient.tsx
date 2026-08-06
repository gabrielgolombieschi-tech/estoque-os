"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatMoneyBR, parseMoneyBR } from "@/lib/decimal";

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
  saldo_referencia: number | null;
  saldo_referencia_data: string | null;
  saldo_referencia_motivo: string | null;
  saldo_atual: number | null;
  saldo_inicial_periodo: number | null;
  configurada: boolean;
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
    const configuradas = base.filter((r) => r.configurada).length;
    const saldoAtual = base.reduce((acc, r) => acc + (r.saldo_atual ?? 0), 0);
    return { total: base.length, ativos, inativos, configuradas, saldoAtual };
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

  const [balanceOpen, setBalanceOpen] = useState(false);
  const [balanceValue, setBalanceValue] = useState("");
  const [balanceDate, setBalanceDate] = useState("");
  const [balanceReason, setBalanceReason] = useState("");
  const [balanceSaving, setBalanceSaving] = useState(false);

  const reload = async () => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!effectiveEmpresaId) return;
    if (canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();

      const today = new Date();
      const todayIso = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
      const [contasRes, saldosRes] = await Promise.all([
        supabase
          .schema("f")
          .from("conta_bancaria")
          .select(
            "id,tenant_id,empresa_id,codigo,nome,tipo,banco,agencia,conta,pix_chave,ativo,created_at,updated_at,deleted_at,saldo_referencia,saldo_referencia_data,saldo_referencia_motivo"
          )
          .eq("tenant_id", te.tenantId)
          .eq("empresa_id", effectiveEmpresaId)
          .is("deleted_at", null)
          .order("nome", { ascending: true })
          .limit(5000),
        supabase.schema("f").rpc("contas_bancarias_saldos", {
          p_tenant_id: te.tenantId,
          p_empresa_ids: [effectiveEmpresaId],
          p_data_inicio: todayIso,
          p_data_fim: todayIso,
          p_data_referencia: todayIso,
        }),
      ]);

      if (contasRes.error) throw contasRes.error;
      if (saldosRes.error) throw saldosRes.error;

      type SaldoRpcRow = {
        conta_bancaria_id: unknown;
        configurada: unknown;
        saldo_atual: unknown;
        saldo_inicial_periodo: unknown;
      };
      const saldoByConta = new Map(
        ((saldosRes.data ?? []) as SaldoRpcRow[]).map((saldo) => [String(saldo.conta_bancaria_id), saldo])
      );
      const data = (contasRes.data ?? []).map((raw) => {
        const conta = raw as unknown as Omit<ContaBancariaRow, "saldo_atual" | "saldo_inicial_periodo" | "configurada">;
        const saldo = saldoByConta.get(String(conta.id));
        return {
          ...conta,
          saldo_atual: saldo?.saldo_atual === null || saldo?.saldo_atual === undefined ? null : Number(saldo.saldo_atual),
          saldo_inicial_periodo:
            saldo?.saldo_inicial_periodo === null || saldo?.saldo_inicial_periodo === undefined
              ? null
              : Number(saldo.saldo_inicial_periodo),
          configurada: Boolean(saldo?.configurada),
        } satisfies ContaBancariaRow;
      });

      setRows(data);
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
      setError(e instanceof Error ? e.message : "Erro ao carregar contas bancárias.");
      setRows([]);
      setSelectedId(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
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
    setFormCodigo(upper(r.codigo));
    setFormNome(upper(r.nome));
    setFormTipo(upper(r.tipo) === "CAIXA" ? "CAIXA" : "BANCO");
    setFormBanco(upper(r.banco ?? ""));
    setFormAgencia(upper(r.agencia ?? ""));
    setFormConta(upper(r.conta ?? ""));
    setFormPix(upper(r.pix_chave ?? ""));
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

    const codigo = upper(formCodigo);
    const nome = upper(formNome);
    const banco = upper(formBanco) || null;
    const agencia = upper(formAgencia) || null;
    const conta = upper(formConta) || null;
    const pix_chave = upper(formPix) || null;

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
          .eq("id", selectedId)
          .eq("tenant_id", te.tenantId)
          .eq("empresa_id", effectiveEmpresaId);
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
        .eq("id", r.id)
        .eq("tenant_id", r.tenant_id)
        .eq("empresa_id", r.empresa_id);
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
        .eq("id", r.id)
        .eq("tenant_id", r.tenant_id)
        .eq("empresa_id", r.empresa_id);
      if (error) throw error;
      setSelectedId(null);
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao arquivar.");
    }
  };

  const openBalance = (r: ContaBancariaRow) => {
    if (canWrite !== true) return;
    const today = new Date();
    setSelectedId(r.id);
    setBalanceValue(r.saldo_atual === null ? "" : formatMoneyBR(r.saldo_atual));
    setBalanceDate(
      `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`
    );
    setBalanceReason("");
    setBalanceOpen(true);
  };

  const saveBalance = async () => {
    if (canWrite !== true || !te.tenantId || !effectiveEmpresaId || !selected) return;

    const parsed = parseMoneyBR(balanceValue);
    if (!Number.isFinite(parsed)) {
      setError("Informe um saldo válido.");
      return;
    }
    if (!balanceDate) {
      setError("Informe a data da posição bancária.");
      return;
    }
    if (balanceReason.trim().length < 3) {
      setError("Informe o motivo do ajuste.");
      return;
    }

    setBalanceSaving(true);
    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error } = await supabase.schema("f").rpc("conta_bancaria_ajustar_saldo", {
        p_tenant_id: te.tenantId,
        p_empresa_id: effectiveEmpresaId,
        p_conta_bancaria_id: selected.id,
        p_saldo_atual: parsed.toFixed(2),
        p_data_referencia: balanceDate,
        p_motivo: balanceReason.trim(),
      });
      if (error) throw error;
      setBalanceOpen(false);
      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao ajustar saldo da conta.");
    } finally {
      setBalanceSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Contas bancárias</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Cadastre as contas usadas nos pagamentos e recebimentos e mantenha a posição de caixa conferida.
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
              onChange={(e) => setTipo(e.target.value as "" | "BANCO" | "CAIXA")}
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

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">
          <div className="rounded-lg border border-zinc-800 bg-black/20 p-3">
            <div className="text-xs text-zinc-400">Total</div>
            <div className="text-lg font-semibold">{totals.total}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-black/20 p-3">
            <div className="text-xs text-zinc-400">Ativas</div>
            <div className="text-lg font-semibold">{totals.ativos}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-black/20 p-3">
            <div className="text-xs text-zinc-400">Saldos configurados</div>
            <div className="text-lg font-semibold">{totals.configuradas} de {totals.total}</div>
          </div>
          <div className="rounded-lg border border-emerald-500/20 bg-emerald-500/5 p-3">
            <div className="text-xs text-emerald-300/80">Saldo atual consolidado</div>
            <div className={`text-lg font-semibold text-right ${totals.saldoAtual < 0 ? "text-red-300" : "text-emerald-300"}`}>
              {formatMoneyBR(totals.saldoAtual)}
            </div>
          </div>
        </div>

        <div className="text-xs text-zinc-500">
          O saldo atual considera a última posição confirmada, as baixas de AP/AR e as transferências registradas.
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
            <table className="min-w-[1080px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Código</th>
                  <th className="px-4 py-3">Nome</th>
                  <th className="px-4 py-3">Tipo</th>
                  <th className="px-4 py-3">Banco</th>
                  <th className="px-4 py-3">Agência</th>
                  <th className="px-4 py-3">Conta</th>
                  <th className="px-4 py-3 text-right">Saldo atual</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {!loading && filtered.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={8}>
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
                      <td className={`px-4 py-3 text-right font-medium ${r.saldo_atual !== null && r.saldo_atual < 0 ? "text-red-300" : "text-zinc-100"}`}>
                        {r.saldo_atual === null ? (
                          <span className="text-amber-300 text-xs">Configurar</span>
                        ) : (
                          formatMoneyBR(r.saldo_atual)
                        )}
                      </td>
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
              <div className="text-xs text-zinc-400 mt-1">
                {selected ? "Dados bancários e posição financeira da conta." : "Selecione uma conta para ver ou editar."}
              </div>
            </div>
            {selected && (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => openBalance(selected)}
                  disabled={canWrite !== true}
                  className="px-3 py-2 rounded-md border border-emerald-500/30 bg-emerald-500/10 text-emerald-200 hover:bg-emerald-500/15 text-sm font-medium disabled:opacity-60"
                >
                  Ajustar saldo
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
              <div className="rounded-xl border border-emerald-500/20 bg-gradient-to-br from-emerald-500/10 to-transparent p-4">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="text-xs uppercase tracking-wide text-emerald-300/80">Saldo atual</div>
                    <div className={`mt-1 text-2xl font-semibold ${selected.saldo_atual !== null && selected.saldo_atual < 0 ? "text-red-300" : "text-zinc-50"}`}>
                      {selected.saldo_atual === null ? "Não configurado" : formatMoneyBR(selected.saldo_atual)}
                    </div>
                  </div>
                  <span className={`rounded-full border px-2.5 py-1 text-xs ${selected.configurada ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-200" : "border-amber-500/30 bg-amber-500/10 text-amber-200"}`}>
                    {selected.configurada ? "CONFERIDO" : "PENDENTE"}
                  </span>
                </div>
                <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
                  <div>
                    <div className="text-xs text-zinc-500">Última posição confirmada</div>
                    <div className="text-zinc-200">
                      {selected.saldo_referencia === null ? "—" : formatMoneyBR(selected.saldo_referencia)}
                      {selected.saldo_referencia_data ? ` em ${selected.saldo_referencia_data.split("-").reverse().join("/")}` : ""}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-500">Motivo</div>
                    <div className="text-zinc-200">{selected.saldo_referencia_motivo ?? "—"}</div>
                  </div>
                </div>
              </div>

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
                  onChange={(e) => setFormCodigo(upper(e.target.value))}
                  aria-label="Código"
                  placeholder="Ex: ITAU-001"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Nome
                <input
                  value={formNome}
                  onChange={(e) => setFormNome(upper(e.target.value))}
                  aria-label="Nome"
                  placeholder="Ex: Itaú PJ - Principal"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Tipo
                <select
                  value={formTipo}
                  onChange={(e) => setFormTipo(e.target.value as "BANCO" | "CAIXA")}
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
                  onChange={(e) => setFormBanco(upper(e.target.value))}
                  aria-label="Banco"
                  placeholder="Ex: Itaú"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Agência
                <input
                  value={formAgencia}
                  onChange={(e) => setFormAgencia(upper(e.target.value))}
                  aria-label="Agência"
                  placeholder="Ex: 1234"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Conta
                <input
                  value={formConta}
                  onChange={(e) => setFormConta(upper(e.target.value))}
                  aria-label="Conta"
                  placeholder="Ex: 12345-6"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Chave PIX
                <input
                  value={formPix}
                  onChange={(e) => setFormPix(upper(e.target.value))}
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

      {balanceOpen && selected && (
        <div className="fixed inset-0 z-50 bg-black/75 flex items-center justify-center p-4">
          <div className="w-full max-w-lg rounded-xl border border-zinc-700 bg-zinc-950 shadow-2xl">
            <div className="flex items-start justify-between gap-3 border-b border-zinc-800 p-5">
              <div>
                <div className="text-lg font-semibold">Ajustar saldo atual</div>
                <div className="mt-1 text-sm text-zinc-400">{selected.codigo} · {selected.nome}</div>
              </div>
              <button
                type="button"
                onClick={() => setBalanceOpen(false)}
                className="rounded-md border border-zinc-800 px-2.5 py-1.5 text-sm text-zinc-300 hover:bg-zinc-900"
              >
                Fechar
              </button>
            </div>

            <div className="space-y-4 p-5">
              <div className="rounded-lg border border-sky-500/20 bg-sky-500/5 p-3 text-sm text-sky-100/80">
                Informe o saldo conferido no banco. Os pagamentos, recebimentos e transferências registrados depois dessa posição passam a atualizar o valor automaticamente.
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <label className="block text-xs text-zinc-400">
                  Saldo conferido
                  <input
                    value={balanceValue}
                    onChange={(e) => setBalanceValue(e.target.value)}
                    aria-label="Saldo conferido"
                    inputMode="decimal"
                    placeholder="0,00"
                    className="mt-1 w-full rounded-md border border-zinc-700 bg-black px-3 py-2.5 text-right text-lg font-semibold text-zinc-50"
                  />
                </label>
                <label className="block text-xs text-zinc-400">
                  Data da posição
                  <input
                    type="date"
                    value={balanceDate}
                    max={new Date().toISOString().slice(0, 10)}
                    onChange={(e) => setBalanceDate(e.target.value)}
                    aria-label="Data da posição"
                    className="mt-1 w-full rounded-md border border-zinc-700 bg-black px-3 py-2.5 text-zinc-100"
                  />
                </label>
              </div>
              <label className="block text-xs text-zinc-400">
                Motivo do ajuste <span className="text-red-300">*</span>
                <input
                  value={balanceReason}
                  onChange={(e) => setBalanceReason(e.target.value)}
                  aria-label="Motivo do ajuste"
                  required
                  placeholder="Ex.: Conferência do extrato bancário"
                  className="mt-1 w-full rounded-md border border-zinc-700 bg-black px-3 py-2.5 text-sm text-zinc-100"
                />
                <span className="mt-1 block text-[11px] text-zinc-500">Obrigatório. Este motivo ficará visível no resumo financeiro.</span>
              </label>
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-zinc-800 p-5">
              <button
                type="button"
                onClick={() => setBalanceOpen(false)}
                className="rounded-md border border-zinc-800 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void saveBalance()}
                disabled={balanceSaving || balanceReason.trim().length < 3}
                className="rounded-md bg-emerald-400 px-4 py-2 text-sm font-semibold text-emerald-950 hover:bg-emerald-300 disabled:opacity-60"
              >
                {balanceSaving ? "Salvando…" : "Confirmar saldo"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
