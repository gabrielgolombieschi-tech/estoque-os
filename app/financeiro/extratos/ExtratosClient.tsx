"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";

type ContaBancariaRow = { id: string; codigo: string; nome: string; tipo: string | null };

type ExtratoRow = {
  id: string;
  conta_bancaria_id: string;
  fonte: string;
  referencia: string | null;
  periodo_inicio: string | null;
  periodo_fim: string | null;
  observacoes: string | null;
  created_at: string;
};

type ExtratoLinhaRow = {
  id: string;
  extrato_bancario_id: string;
  conta_bancaria_id: string;
  data_movimento: string;
  descricao: string | null;
  documento: string | null;
  fit_id: string | null;
  valor: number | string;
  status: "PENDENTE" | "CONCILIADO" | "IGNORADO" | string;
  observacoes: string | null;
  created_at: string;
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

function pillForStatus(status: string) {
  const s = String(status || "").toUpperCase();
  if (s === "CONCILIADO") return "bg-emerald-500/15 text-emerald-200 border-emerald-500/30";
  if (s === "IGNORADO") return "bg-zinc-700/40 text-zinc-200 border-zinc-700";
  return "bg-amber-500/15 text-amber-200 border-amber-500/30";
}

function StatusPill({ status }: { status: string }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${pillForStatus(status)}`}>
      {String(status || "").toUpperCase() || "-"}
    </span>
  );
}

export default function ExtratosClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [contas, setContas] = useState<ContaBancariaRow[]>([]);
  const [contaId, setContaId] = useState<string>("");

  const [extratos, setExtratos] = useState<ExtratoRow[]>([]);
  const [extratoId, setExtratoId] = useState<string>("");

  const [startDate, setStartDate] = useState<string>("");
  const [endDate, setEndDate] = useState<string>("");
  const [status, setStatus] = useState<"" | "PENDENTE" | "CONCILIADO" | "IGNORADO">("");
  const [q, setQ] = useState<string>("");

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [linhas, setLinhas] = useState<ExtratoLinhaRow[]>([]);

  // Create manual extrato
  const [createOpen, setCreateOpen] = useState(false);
  const [createReferencia, setCreateReferencia] = useState<string>("");
  const [createIni, setCreateIni] = useState<string>("");
  const [createFim, setCreateFim] = useState<string>("");
  const [createObs, setCreateObs] = useState<string>("");
  const [creating, setCreating] = useState(false);

  // Add manual line
  const [lineOpen, setLineOpen] = useState(false);
  const [lineDate, setLineDate] = useState<string>("");
  const [lineDesc, setLineDesc] = useState<string>("");
  const [lineDoc, setLineDoc] = useState<string>("");
  const [lineFit, setLineFit] = useState<string>("");
  const [lineValor, setLineValor] = useState<string>("");
  const [lineObs, setLineObs] = useState<string>("");
  const [lineSaving, setLineSaving] = useState(false);

  const resumo = useMemo(() => {
    const total = linhas.reduce((acc, l) => acc + n(l.valor), 0);
    const entradas = linhas.filter((l) => n(l.valor) > 0).reduce((acc, l) => acc + n(l.valor), 0);
    const saidas = linhas.filter((l) => n(l.valor) < 0).reduce((acc, l) => acc + n(l.valor), 0);
    const pendentes = linhas.filter((l) => String(l.status).toUpperCase() === "PENDENTE").length;
    return { total, entradas, saidas, pendentes, count: linhas.length };
  }, [linhas]);

  const reloadAll = async (opts?: { keepSelected?: boolean }) => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!te.empresaId && te.empresas.length !== 1) return;
    if (canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    const supabase = getSupabaseBrowser();
    const tenantId = te.tenantId;

    try {
      const { data: contasData, error: contasErr } = await supabase
        .schema("f")
        .from("conta_bancaria")
        .select("id,codigo,nome,tipo")
        .eq("tenant_id", tenantId)
        .eq("ativo", true)
        .is("deleted_at", null)
        .order("nome", { ascending: true });

      if (contasErr) throw contasErr;
      const contasMapped = (contasData ?? []).map((r: any) => ({
        id: String(r.id),
        codigo: String(r.codigo),
        nome: String(r.nome),
        tipo: r.tipo ? String(r.tipo) : null,
      })) as ContaBancariaRow[];
      setContas(contasMapped);

      const effectiveContaId = opts?.keepSelected ? contaId : contaId || (contasMapped.length === 1 ? contasMapped[0].id : "");
      if (!opts?.keepSelected) setContaId(effectiveContaId);

      if (!effectiveContaId) {
        setExtratos([]);
        setExtratoId("");
        setLinhas([]);
        return;
      }

      const { data: extratosData, error: extratosErr } = await supabase
        .schema("f")
        .from("extrato_bancario")
        .select("id,conta_bancaria_id,fonte,referencia,periodo_inicio,periodo_fim,observacoes,created_at")
        .eq("conta_bancaria_id", effectiveContaId)
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(50);

      if (extratosErr) throw extratosErr;
      const extratosMapped = (extratosData ?? []) as unknown as ExtratoRow[];
      setExtratos(extratosMapped);

      const effectiveExtratoId = opts?.keepSelected ? extratoId : extratoId || (extratosMapped[0]?.id ?? "");
      if (!opts?.keepSelected) setExtratoId(effectiveExtratoId);

      // Load lines
      let qLines = supabase
        .schema("f")
        .from("extrato_bancario_linha")
        .select(
          "id,extrato_bancario_id,conta_bancaria_id,data_movimento,descricao,documento,fit_id,valor,status,observacoes,created_at"
        )
        .eq("conta_bancaria_id", effectiveContaId)
        .is("deleted_at", null)
        .order("data_movimento", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(500);

      if (effectiveExtratoId) qLines = qLines.eq("extrato_bancario_id", effectiveExtratoId);
      if (startDate) qLines = qLines.gte("data_movimento", startDate);
      if (endDate) qLines = qLines.lte("data_movimento", endDate);
      if (status) qLines = qLines.eq("status", status);
      const term = q.trim();
      if (term) {
        qLines = qLines.or([`descricao.ilike.%${term}%`, `documento.ilike.%${term}%`, `fit_id.ilike.%${term}%`].join(","));
      }

      const { data: linesData, error: linesErr } = await qLines;
      if (linesErr) throw linesErr;
      setLinhas((linesData ?? []) as unknown as ExtratoLinhaRow[]);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao carregar extratos.");
      setContas([]);
      setExtratos([]);
      setExtratoId("");
      setLinhas([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void reloadAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canFinanceiro, te.sessionUserId, te.tenantId, te.empresaId, te.empresas.length]);

  useEffect(() => {
    // filters reload
    void reloadAll({ keepSelected: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [contaId, extratoId, startDate, endDate, status, q]);

  const onCreateExtrato = async () => {
    if (!te.tenantId) return;
    if (!te.empresaId) return;
    if (!contaId) return;

    setCreating(true);
    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { data, error: insErr } = await supabase
        .schema("f")
        .from("extrato_bancario")
        .insert({
          tenant_id: te.tenantId,
          empresa_id: te.empresaId,
          conta_bancaria_id: contaId,
          fonte: "MANUAL",
          referencia: createReferencia.trim() ? createReferencia.trim() : null,
          periodo_inicio: createIni || null,
          periodo_fim: createFim || null,
          observacoes: createObs.trim() ? createObs.trim() : null,
        })
        .select("id")
        .single();

      if (insErr) throw insErr;
      const id = data?.id ? String(data.id) : "";
      setCreateOpen(false);
      setCreateReferencia("");
      setCreateIni("");
      setCreateFim("");
      setCreateObs("");

      await reloadAll({ keepSelected: true });
      if (id) setExtratoId(id);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao criar extrato manual.");
    } finally {
      setCreating(false);
    }
  };

  const onAddLine = async () => {
    if (!te.tenantId) return;
    if (!contaId) return;
    if (!extratoId) {
      setError("Selecione (ou crie) um extrato antes de adicionar linhas.");
      return;
    }
    if (!lineDate) {
      setError("Data do movimento é obrigatória.");
      return;
    }
    const valorNum = Number(lineValor.replace(".", "").replace(",", "."));
    if (!Number.isFinite(valorNum) || valorNum === 0) {
      setError("Valor inválido (use positivo para entrada e negativo para saída).");
      return;
    }

    setLineSaving(true);
    setError(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error: insErr } = await supabase
        .schema("f")
        .from("extrato_bancario_linha")
        .insert({
          tenant_id: te.tenantId,
          extrato_bancario_id: extratoId,
          conta_bancaria_id: contaId,
          data_movimento: lineDate,
          descricao: lineDesc.trim() ? lineDesc.trim() : null,
          documento: lineDoc.trim() ? lineDoc.trim() : null,
          fit_id: lineFit.trim() ? lineFit.trim() : null,
          valor: valorNum,
          status: "PENDENTE",
          observacoes: lineObs.trim() ? lineObs.trim() : null,
        });

      if (insErr) throw insErr;

      setLineOpen(false);
      setLineDate("");
      setLineDesc("");
      setLineDoc("");
      setLineFit("");
      setLineValor("");
      setLineObs("");

      await reloadAll({ keepSelected: true });
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao adicionar linha.");
    } finally {
      setLineSaving(false);
    }
  };

  const selectedConta = contas.find((c) => c.id === contaId) ?? null;

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Extratos Bancários</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Base da conciliação: extratos e linhas (f.extrato_bancario + f.extrato_bancario_linha).
          </p>
          <p className="text-xs text-zinc-500 mt-1">
            No Lucro Real, extrato/caixa é controle financeiro (não define competência); use a competência no título.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/conciliacao"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Conciliação
          </Link>
          <Link
            href="/financeiro"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="flex flex-wrap items-end gap-2">
          <label className="block text-xs text-zinc-400">
            Conta bancária
            <select
              value={contaId}
              onChange={(e) => {
                setContaId(e.target.value);
                setExtratoId("");
              }}
              aria-label="Conta bancária"
              className="mt-1 w-[320px] max-w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            >
              <option value="">Selecione…</option>
              {contas.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.codigo} — {c.nome}
                </option>
              ))}
            </select>
          </label>

          <label className="block text-xs text-zinc-400">
            Extrato
            <select
              value={extratoId}
              onChange={(e) => setExtratoId(e.target.value)}
              aria-label="Extrato"
              className="mt-1 w-[420px] max-w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
              disabled={!contaId}
            >
              <option value="">(todos / selecione)</option>
              {extratos.map((ex) => {
                const labelParts = [
                  ex.fonte,
                  ex.referencia ? ex.referencia : null,
                  ex.periodo_inicio || ex.periodo_fim
                    ? `${formatDateBR(ex.periodo_inicio)} → ${formatDateBR(ex.periodo_fim)}`
                    : null,
                ].filter(Boolean);
                return (
                  <option key={ex.id} value={ex.id}>
                    {labelParts.join(" — ")}
                  </option>
                );
              })}
            </select>
          </label>

          <button
            type="button"
            onClick={() => setCreateOpen(true)}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
            disabled={!contaId || !te.empresaId}
          >
            Criar extrato manual
          </button>

          <button
            type="button"
            onClick={() => setLineOpen(true)}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
            disabled={!contaId || !extratoId}
          >
            Adicionar linha
          </button>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar em descrição/documento/fit_id…"
            aria-label="Buscar"
            className="w-full sm:w-[420px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />
          <label className="block text-xs text-zinc-400">
            De
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              aria-label="Data inicial"
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-xs text-zinc-400">
            Até
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              aria-label="Data final"
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-xs text-zinc-400">
            Status
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value as any)}
              aria-label="Status"
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            >
              <option value="">Todos</option>
              <option value="PENDENTE">PENDENTE</option>
              <option value="CONCILIADO">CONCILIADO</option>
              <option value="IGNORADO">IGNORADO</option>
            </select>
          </label>
          <button
            type="button"
            onClick={() => {
              setQ("");
              setStartDate("");
              setEndDate("");
              setStatus("");
            }}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Limpar filtros
          </button>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Linhas</div>
            <div className="text-lg font-semibold">{resumo.count}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Entradas</div>
            <div className="text-lg font-semibold text-emerald-200">{formatDecimalBR(resumo.entradas, 2)}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Saídas</div>
            <div className="text-lg font-semibold text-amber-200">{formatDecimalBR(resumo.saidas, 2)}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Pendentes</div>
            <div className="text-lg font-semibold">{resumo.pendentes}</div>
          </div>
        </div>

        {selectedConta && (
          <div className="text-xs text-zinc-500">
            Conta selecionada: <span className="text-zinc-300">{selectedConta.codigo}</span> — {selectedConta.nome}
          </div>
        )}
      </div>

      {error && <div className="text-sm text-red-300">{error}</div>}

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
        <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
          <div className="font-semibold">Linhas do extrato</div>
          {loading && <div className="text-xs text-zinc-400">Carregando…</div>}
        </div>

        <div className="overflow-auto">
          <table className="min-w-[980px] w-full text-sm">
            <thead className="bg-zinc-950/60">
              <tr className="text-left text-xs text-zinc-400">
                <th className="px-4 py-3">Data</th>
                <th className="px-4 py-3">Descrição</th>
                <th className="px-4 py-3">Documento</th>
                <th className="px-4 py-3">FitId</th>
                <th className="px-4 py-3 text-right">Valor</th>
                <th className="px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {!loading && linhas.length === 0 && (
                <tr>
                  <td className="px-4 py-6 text-zinc-400" colSpan={6}>
                    Nenhuma linha encontrada.
                  </td>
                </tr>
              )}
              {linhas.map((l) => (
                <tr key={l.id} className="border-t border-zinc-900 hover:bg-zinc-900/40">
                  <td className="px-4 py-3 whitespace-nowrap">{formatDateBR(l.data_movimento)}</td>
                  <td className="px-4 py-3">
                    <div className="text-zinc-100">{l.descricao ?? "-"}</div>
                    {l.observacoes && <div className="text-xs text-zinc-500 mt-1">{l.observacoes}</div>}
                  </td>
                  <td className="px-4 py-3">{l.documento ?? "-"}</td>
                  <td className="px-4 py-3">{l.fit_id ?? "-"}</td>
                  <td className={`px-4 py-3 text-right font-medium ${n(l.valor) < 0 ? "text-amber-200" : "text-emerald-200"}`}>
                    {formatDecimalBR(n(l.valor), 2)}
                  </td>
                  <td className="px-4 py-3">
                    <StatusPill status={l.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Create extrato modal */}
      {createOpen && (
        <div className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4">
          <div className="w-full max-w-xl rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">Criar extrato manual</div>
                <div className="text-xs text-zinc-400 mt-1">Cria um registro em f.extrato_bancario (fonte=MANUAL).</div>
              </div>
              <button
                type="button"
                onClick={() => setCreateOpen(false)}
                className="px-2 py-1 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Fechar
              </button>
            </div>

            <div className="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-3">
              <label className="block text-xs text-zinc-400">
                Referência
                <input
                  value={createReferencia}
                  onChange={(e) => setCreateReferencia(e.target.value)}
                  aria-label="Referência"
                  placeholder="Ex: Jan/2026"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <div />

              <label className="block text-xs text-zinc-400">
                Período início
                <input
                  type="date"
                  value={createIni}
                  onChange={(e) => setCreateIni(e.target.value)}
                  aria-label="Período início"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Período fim
                <input
                  type="date"
                  value={createFim}
                  onChange={(e) => setCreateFim(e.target.value)}
                  aria-label="Período fim"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Observações
                <textarea
                  value={createObs}
                  onChange={(e) => setCreateObs(e.target.value)}
                  aria-label="Observações"
                  className="mt-1 w-full min-h-[80px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
            </div>

            <div className="mt-4 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setCreateOpen(false)}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={onCreateExtrato}
                disabled={creating || !contaId || !te.empresaId}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
              >
                {creating ? "Criando…" : "Criar"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Add line modal */}
      {lineOpen && (
        <div className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4">
          <div className="w-full max-w-2xl rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">Adicionar linha manual</div>
                <div className="text-xs text-zinc-400 mt-1">
                  Cria um registro em f.extrato_bancario_linha (status=PENDENTE).
                </div>
              </div>
              <button
                type="button"
                onClick={() => setLineOpen(false)}
                className="px-2 py-1 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Fechar
              </button>
            </div>

            <div className="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-3">
              <label className="block text-xs text-zinc-400">
                Data do movimento
                <input
                  type="date"
                  value={lineDate}
                  onChange={(e) => setLineDate(e.target.value)}
                  aria-label="Data do movimento"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Valor (use negativo para saída)
                <input
                  value={lineValor}
                  onChange={(e) => setLineValor(e.target.value)}
                  aria-label="Valor"
                  placeholder="Ex: -1500,00"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Descrição
                <input
                  value={lineDesc}
                  onChange={(e) => setLineDesc(e.target.value)}
                  aria-label="Descrição"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Documento
                <input
                  value={lineDoc}
                  onChange={(e) => setLineDoc(e.target.value)}
                  aria-label="Documento"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-xs text-zinc-400">
                Fit ID
                <input
                  value={lineFit}
                  onChange={(e) => setLineFit(e.target.value)}
                  aria-label="Fit ID"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Observações
                <textarea
                  value={lineObs}
                  onChange={(e) => setLineObs(e.target.value)}
                  aria-label="Observações"
                  className="mt-1 w-full min-h-[80px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
            </div>

            <div className="mt-4 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setLineOpen(false)}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={onAddLine}
                disabled={lineSaving}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
              >
                {lineSaving ? "Salvando…" : "Adicionar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
