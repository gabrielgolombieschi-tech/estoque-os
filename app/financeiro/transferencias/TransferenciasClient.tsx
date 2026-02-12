"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";

type ContaBancariaRow = { id: string; codigo: string; nome: string; tipo: string | null };

type ExtratoLinhaRow = {
  id: string;
  conta_bancaria_id: string;
  data_movimento: string;
  descricao: string | null;
  documento: string | null;
  valor: number | string;
  status: string;
};

type EventoRow = { id: string; evento: string; created_at: string; payload: unknown };

type TransferPair = {
  key: string;
  data: string;
  valorAbs: number;
  saida: ExtratoLinhaRow;
  entrada: ExtratoLinhaRow;
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

function buildTransferPairs(lines: ExtratoLinhaRow[], dayWindow: number): TransferPair[] {
  // Detect likely internal transfers: same abs value, opposite signs, different accounts, within ±dayWindow days.
  const byAbs = new Map<number, ExtratoLinhaRow[]>();
  for (const l of lines) {
    const abs = Math.round(Math.abs(n(l.valor)) * 100) / 100;
    if (!abs) continue;
    const arr = byAbs.get(abs) ?? [];
    arr.push(l);
    byAbs.set(abs, arr);
  }

  const pairs: TransferPair[] = [];
  const used = new Set<string>();

  const toDay = (iso: string) => {
    const t = Date.parse(`${iso}T00:00:00`);
    return Number.isFinite(t) ? Math.floor(t / 86400000) : null;
  };

  for (const [abs, arr] of byAbs.entries()) {
    const neg = arr.filter((l) => n(l.valor) < 0);
    const pos = arr.filter((l) => n(l.valor) > 0);

    for (const s of neg) {
      const sd = toDay(s.data_movimento);
      if (sd === null) continue;

      const candidates = pos
        .filter((e) => e.conta_bancaria_id !== s.conta_bancaria_id)
        .map((e) => ({ e, d: toDay(e.data_movimento) }))
        .filter((x) => x.d !== null && Math.abs((x.d as number) - sd) <= dayWindow)
        .sort((a, b) => Math.abs((a.d as number) - sd) - Math.abs((b.d as number) - sd));

      const best = candidates[0]?.e;
      if (!best) continue;

      const key = `${s.id}:${best.id}`;
      if (used.has(s.id) || used.has(best.id)) continue;

      used.add(s.id);
      used.add(best.id);

      pairs.push({
        key,
        data: s.data_movimento,
        valorAbs: abs,
        saida: s,
        entrada: best,
      });
    }
  }

  // Most recent first
  pairs.sort((a, b) => String(b.data).localeCompare(String(a.data)));
  return pairs;
}

export default function TransferenciasClient() {
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
  const [startDate, setStartDate] = useState<string>("");
  const [endDate, setEndDate] = useState<string>("");
  const [dayWindow, setDayWindow] = useState<0 | 1 | 2>(1);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [lines, setLines] = useState<ExtratoLinhaRow[]>([]);
  const [pairs, setPairs] = useState<TransferPair[]>([]);
  const [events, setEvents] = useState<EventoRow[]>([]);

  // Create transfer form
  const [open, setOpen] = useState(false);
  const [origemId, setOrigemId] = useState<string>("");
  const [destinoId, setDestinoId] = useState<string>("");
  const [dataMov, setDataMov] = useState<string>("");
  const [valor, setValor] = useState<string>("");
  const [descricao, setDescricao] = useState<string>("");
  const [saving, setSaving] = useState(false);

  const reload = async () => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!te.empresaId && te.empresas.length !== 1) return;
    if (canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    const supabase = getSupabaseBrowser();

    try {
      const { data: contasData, error: contasErr } = await supabase
        .schema("f")
        .from("conta_bancaria")
        .select("id,codigo,nome,tipo")
        .eq("tenant_id", te.tenantId)
        .eq("ativo", true)
        .is("deleted_at", null)
        .order("nome", { ascending: true });

      if (contasErr) throw contasErr;
      const contasMapped = (contasData ?? []).map((r: unknown) => {
        const row = r as Record<string, unknown>;
        return {
          id: String(row.id ?? ""),
          codigo: String(row.codigo ?? ""),
          nome: String(row.nome ?? ""),
          tipo: row.tipo ? String(row.tipo) : null,
        } satisfies ContaBancariaRow;
      });
      setContas(contasMapped);

      // Load last N extrato lines with possible transfer markers.
      let q = supabase
        .schema("f")
        .from("extrato_bancario_linha")
        .select("id,conta_bancaria_id,data_movimento,descricao,documento,valor,status")
        .is("deleted_at", null)
        .order("data_movimento", { ascending: false })
        .limit(1200);

      if (startDate) q = q.gte("data_movimento", startDate);
      if (endDate) q = q.lte("data_movimento", endDate);

      // We can't rely on a dedicated transfer table in schema; use a pragmatic filter.
      q = q.or(["descricao.ilike.%transfer%", "documento.ilike.%transfer%"].join(","));

      const { data: linesData, error: linesErr } = await q;
      if (linesErr) throw linesErr;

      const mappedLines = (linesData ?? []) as unknown as ExtratoLinhaRow[];
      setLines(mappedLines);
      setPairs(buildTransferPairs(mappedLines, dayWindow));

      // Also show last transfer events (if your DB uses f.evento_financeiro for auditing).
      const { data: evData } = await supabase
        .schema("f")
        .from("evento_financeiro")
        .select("id,evento,created_at,payload")
        .eq("evento", "TRANSFERENCIA")
        .order("created_at", { ascending: false })
        .limit(50);

      setEvents((evData ?? []) as unknown as EventoRow[]);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao carregar transferências.");
      setContas([]);
      setLines([]);
      setPairs([]);
      setEvents([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canFinanceiro, te.sessionUserId, te.tenantId, te.empresaId, te.empresas.length]);

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [startDate, endDate, dayWindow]);

  const ensureManualExtrato = async (contaBancariaId: string, referencia: string) => {
    if (!te.tenantId || !te.empresaId) throw new Error("Contexto (tenant/empresa) não carregado.");
    const supabase = getSupabaseBrowser();

    // Create a new manual extrato for the day/reference (simple + safe).
    const { data, error } = await supabase
      .schema("f")
      .from("extrato_bancario")
      .insert({
        tenant_id: te.tenantId,
        empresa_id: te.empresaId,
        conta_bancaria_id: contaBancariaId,
        fonte: "MANUAL",
        referencia,
        periodo_inicio: null,
        periodo_fim: null,
        observacoes: "Gerado pelo módulo Transferências.",
      })
      .select("id")
      .single();

    if (error) throw error;
    return String(data.id);
  };

  const criarTransferencia = async () => {
    if (!te.tenantId || !te.empresaId) return;

    const v = Number(valor.replace(".", "").replace(",", "."));
    if (!origemId || !destinoId) {
      setError("Selecione conta de origem e destino.");
      return;
    }
    if (origemId === destinoId) {
      setError("Origem e destino devem ser diferentes.");
      return;
    }
    if (!dataMov) {
      setError("Data é obrigatória.");
      return;
    }
    if (!Number.isFinite(v) || v <= 0) {
      setError("Valor inválido.");
      return;
    }

    setSaving(true);
    setError(null);
    try {
      const supabase = getSupabaseBrowser();

      const origem = contas.find((c) => c.id === origemId);
      const destino = contas.find((c) => c.id === destinoId);
      const ref = `TRANSFERENCIA ${dataMov}`;

      const extratoOrigemId = await ensureManualExtrato(origemId, ref);
      const extratoDestinoId = await ensureManualExtrato(destinoId, ref);

      const descBase = descricao.trim() || `Transferência entre contas`;

      const { error: l1Err } = await supabase
        .schema("f")
        .from("extrato_bancario_linha")
        .insert({
          tenant_id: te.tenantId,
          extrato_bancario_id: extratoOrigemId,
          conta_bancaria_id: origemId,
          data_movimento: dataMov,
          descricao: `${descBase} — SAÍDA p/ ${destino?.codigo ?? ""} ${destino?.nome ?? ""}`.trim(),
          documento: "TRANSFERENCIA",
          valor: -v,
          status: "PENDENTE",
          observacoes: null,
        });
      if (l1Err) throw l1Err;

      const { error: l2Err } = await supabase
        .schema("f")
        .from("extrato_bancario_linha")
        .insert({
          tenant_id: te.tenantId,
          extrato_bancario_id: extratoDestinoId,
          conta_bancaria_id: destinoId,
          data_movimento: dataMov,
          descricao: `${descBase} — ENTRADA de ${origem?.codigo ?? ""} ${origem?.nome ?? ""}`.trim(),
          documento: "TRANSFERENCIA",
          valor: v,
          status: "PENDENTE",
          observacoes: null,
        });
      if (l2Err) throw l2Err;

      // Audit trail (optional but helpful)
      await supabase.schema("f").from("evento_financeiro").insert({
        tenant_id: te.tenantId,
        empresa_id: te.empresaId,
        evento: "TRANSFERENCIA",
        ref_table: "f.extrato_bancario_linha",
        ref_id: null,
        payload: {
          data_movimento: dataMov,
          valor: v,
          origem_id: origemId,
          destino_id: destinoId,
          origem: origem ? { codigo: origem.codigo, nome: origem.nome } : null,
          destino: destino ? { codigo: destino.codigo, nome: destino.nome } : null,
          descricao: descBase,
        },
      });

      setOpen(false);
      setOrigemId("");
      setDestinoId("");
      setDataMov("");
      setValor("");
      setDescricao("");

      await reload();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao criar transferência.");
    } finally {
      setSaving(false);
    }
  };

  const contaName = (id: string) => {
    const c = contas.find((x) => x.id === id);
    if (!c) return id;
    return `${c.codigo} — ${c.nome}`;
  };

  const totals = useMemo(() => {
    const totalPairs = pairs.reduce((acc, p) => acc + p.valorAbs, 0);
    return { totalPairs, countPairs: pairs.length, countLines: lines.length };
  }, [lines.length, pairs]);

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Transferências</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Movimentações entre contas (não afetam DRE; afetam somente caixa/banco e conciliação).
          </p>
          <p className="text-xs text-zinc-500 mt-1">
            Como o schema não tem uma tabela dedicada de transferências, esta tela usa linhas de extrato + auditoria em f.evento_financeiro.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/extratos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Extratos
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
            Janela (dias)
            <select
              value={dayWindow}
              onChange={(e) => {
                const v = e.target.value;
                setDayWindow(v === "0" ? 0 : v === "1" ? 1 : 2);
              }}
              aria-label="Janela de dias"
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            >
              <option value={0}>0</option>
              <option value={1}>1</option>
              <option value={2}>2</option>
            </select>
          </label>

          <button
            type="button"
            onClick={() => setOpen(true)}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
            disabled={!te.empresaId}
          >
            Nova transferência
          </button>

          <button
            type="button"
            onClick={() => {
              setStartDate("");
              setEndDate("");
              setDayWindow(1);
            }}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Limpar
          </button>

          {loading && <div className="text-xs text-zinc-400">Carregando…</div>}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Pares detectados</div>
            <div className="text-lg font-semibold">{totals.countPairs}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Total transferido (pares)</div>
            <div className="text-lg font-semibold text-zinc-100">{formatDecimalBR(totals.totalPairs, 2)}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Linhas analisadas</div>
            <div className="text-lg font-semibold">{totals.countLines}</div>
          </div>
        </div>
      </div>

      {error && <div className="text-sm text-red-300">{error}</div>}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="px-4 py-3 border-b border-zinc-800">
            <div className="font-semibold">Transferências detectadas (extrato)</div>
            <div className="text-xs text-zinc-500 mt-1">Pareamento por valor absoluto e datas próximas.</div>
          </div>
          <div className="overflow-auto">
            <table className="min-w-[980px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Data</th>
                  <th className="px-4 py-3">Origem (saída)</th>
                  <th className="px-4 py-3">Destino (entrada)</th>
                  <th className="px-4 py-3 text-right">Valor</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {!loading && pairs.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={5}>
                      Nenhuma transferência detectada. Dica: use o documento &quot;TRANSFERENCIA&quot; ao lançar manualmente.
                    </td>
                  </tr>
                )}
                {pairs.map((p) => (
                  <tr key={p.key} className="border-t border-zinc-900 hover:bg-zinc-900/40">
                    <td className="px-4 py-3 whitespace-nowrap">{formatDateBR(p.data)}</td>
                    <td className="px-4 py-3">
                      <div className="text-zinc-100">{contaName(p.saida.conta_bancaria_id)}</div>
                      <div className="text-xs text-zinc-500 mt-1">{p.saida.descricao ?? "-"}</div>
                    </td>
                    <td className="px-4 py-3">
                      <div className="text-zinc-100">{contaName(p.entrada.conta_bancaria_id)}</div>
                      <div className="text-xs text-zinc-500 mt-1">{p.entrada.descricao ?? "-"}</div>
                    </td>
                    <td className="px-4 py-3 text-right font-medium text-zinc-100">{formatDecimalBR(p.valorAbs, 2)}</td>
                    <td className="px-4 py-3">
                      <div className="flex gap-2 flex-wrap">
                        <span className="inline-flex items-center rounded-full border px-2 py-0.5 text-xs border-zinc-700 bg-zinc-900">
                          Saída: {String(p.saida.status).toUpperCase()}
                        </span>
                        <span className="inline-flex items-center rounded-full border px-2 py-0.5 text-xs border-zinc-700 bg-zinc-900">
                          Entrada: {String(p.entrada.status).toUpperCase()}
                        </span>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="px-4 py-3 border-b border-zinc-800">
            <div className="font-semibold">Auditoria (evento_financeiro)</div>
            <div className="text-xs text-zinc-500 mt-1">
              Eventos &quot;TRANSFERENCIA&quot; gerados por esta tela (quando permitido pela RLS).
            </div>
          </div>
          <div className="overflow-auto">
            <table className="min-w-[860px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Quando</th>
                  <th className="px-4 py-3">Origem</th>
                  <th className="px-4 py-3">Destino</th>
                  <th className="px-4 py-3 text-right">Valor</th>
                  <th className="px-4 py-3">Descrição</th>
                </tr>
              </thead>
              <tbody>
                {!loading && events.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={5}>
                      Nenhum evento registrado.
                    </td>
                  </tr>
                )}
                {events.map((e) => {
                  const payload = (e.payload && typeof e.payload === "object" ? (e.payload as Record<string, unknown>) : {}) as Record<
                    string,
                    unknown
                  >;
                  const origem =
                    payload.origem && typeof payload.origem === "object" ? (payload.origem as Record<string, unknown>) : null;
                  const destino =
                    payload.destino && typeof payload.destino === "object" ? (payload.destino as Record<string, unknown>) : null;

                  const origemCodigo = origem?.codigo ? String(origem.codigo) : "";
                  const origemNome = origem?.nome ? String(origem.nome) : "";
                  const origemId = payload.origem_id != null ? String(payload.origem_id) : null;

                  const destinoCodigo = destino?.codigo ? String(destino.codigo) : "";
                  const destinoNome = destino?.nome ? String(destino.nome) : "";
                  const destinoId = payload.destino_id != null ? String(payload.destino_id) : null;

                  const valor = payload.valor;
                  const descricao = payload.descricao != null ? String(payload.descricao) : "-";

                  return (
                    <tr key={e.id} className="border-t border-zinc-900 hover:bg-zinc-900/40">
                      <td className="px-4 py-3 whitespace-nowrap">{new Date(e.created_at).toLocaleString("pt-BR")}</td>
                      <td className="px-4 py-3">{origemCodigo ? `${origemCodigo} — ${origemNome}` : origemId ?? "-"}</td>
                      <td className="px-4 py-3">{destinoCodigo ? `${destinoCodigo} — ${destinoNome}` : destinoId ?? "-"}</td>
                      <td className="px-4 py-3 text-right font-medium">{formatDecimalBR(n(valor), 2)}</td>
                      <td className="px-4 py-3 text-zinc-300">{descricao}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {open && (
        <div className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4">
          <div className="w-full max-w-2xl rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">Nova transferência</div>
                <div className="text-xs text-zinc-400 mt-1">
                  Lança 2 linhas de extrato (saída na origem e entrada no destino) em extratos MANUAL.
                </div>
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
                Origem
                <select
                  value={origemId}
                  onChange={(e) => setOrigemId(e.target.value)}
                  aria-label="Conta origem"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
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
                Destino
                <select
                  value={destinoId}
                  onChange={(e) => setDestinoId(e.target.value)}
                  aria-label="Conta destino"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
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
                Data
                <input
                  type="date"
                  value={dataMov}
                  onChange={(e) => setDataMov(e.target.value)}
                  aria-label="Data"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Valor
                <input
                  value={valor}
                  onChange={(e) => setValor(e.target.value)}
                  aria-label="Valor"
                  placeholder="Ex: 2500,00"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 sm:col-span-2">
                Descrição
                <input
                  value={descricao}
                  onChange={(e) => setDescricao(e.target.value)}
                  aria-label="Descrição"
                  placeholder="Ex: Transferência p/ aplicação, reforço de caixa, etc."
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
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
                onClick={criarTransferencia}
                disabled={saving}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
              >
                {saving ? "Salvando…" : "Lançar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
