"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatMoneyBR } from "@/lib/decimal";

type ApuracaoRow = {
  tenant_id: string;
  empresa_id: string;
  competencia_date: string;
  operacao: string;
  imposto: string;
  natureza: string;
  base_total: number | string | null;
  valor_total_calculado: number | string | null;
  valor_total_ajustado: number | string | null;
  qtd_documentos: number | string | null;
};

type ApuracaoAggRow = {
  imposto: string;
  natureza: string;
  base_total: number;
  valor_total_calculado: number;
  valor_total_ajustado: number;
  qtd_documentos: number;
};

type DocumentoImpostoRow = {
  documento_fiscal_id: string;
  chave_acesso: string;
  emissao_date: string | null;
  competencia_date: string;
  operacao: string;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  valor_documento: number | string | null;
  valor_imposto: number | string | null;
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function toISODate(d: Date): string {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function monthStartISO(year: number, month1to12: number): string {
  return toISODate(new Date(year, month1to12 - 1, 1));
}

function nextMonthStartISO(year: number, month1to12: number): string {
  return toISODate(new Date(year, month1to12, 1));
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

const MONTH_LABELS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"] as const;

function StatCard({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-400">{title}</div>
      <div className="mt-2 text-2xl font-semibold text-zinc-100 tabular-nums">{value}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
    </div>
  );
}

function normalizeApuracaoRows(rows: ApuracaoRow[]): ApuracaoRow[] {
  return (rows ?? [])
    .map((r) => ({
      ...r,
      imposto: String(r.imposto ?? "").trim(),
      natureza: String(r.natureza ?? "").trim(),
      operacao: String(r.operacao ?? "").trim(),
      competencia_date: String(r.competencia_date ?? "").slice(0, 10),
    }))
    .filter((r) => r.imposto && r.natureza && r.competencia_date);
}

function aggregateForTable(rows: ApuracaoRow[]): ApuracaoAggRow[] {
  const byKey = new Map<string, ApuracaoAggRow>();
  for (const r of rows) {
    const imposto = String(r.imposto ?? "").trim();
    const natureza = String(r.natureza ?? "").trim();
    if (!imposto || !natureza) continue;
    const key = `${imposto}::${natureza}`;
    const cur = byKey.get(key) ?? {
      imposto,
      natureza,
      base_total: 0,
      valor_total_calculado: 0,
      valor_total_ajustado: 0,
      qtd_documentos: 0,
    };
    cur.base_total += n(r.base_total);
    cur.valor_total_calculado += n(r.valor_total_calculado);
    cur.valor_total_ajustado += n(r.valor_total_ajustado);
    cur.qtd_documentos += n(r.qtd_documentos);
    byKey.set(key, cur);
  }
  return Array.from(byKey.values()).sort((a, b) => {
    const imp = a.imposto.localeCompare(b.imposto);
    if (imp !== 0) return imp;
    return a.natureza.localeCompare(b.natureza);
  });
}

function sumByNatureza(rows: Array<{ natureza: string; valor_total_calculado: number; qtd_documentos: number }>) {
  const debitos = rows.filter((r) => r.natureza === "DEBITO").reduce((acc, r) => acc + r.valor_total_calculado, 0);
  const creditos = rows.filter((r) => r.natureza === "CREDITO").reduce((acc, r) => acc + r.valor_total_calculado, 0);
  const retencoes = rows.filter((r) => r.natureza === "RETENCAO").reduce((acc, r) => acc + r.valor_total_calculado, 0);
  const qtdDocs = rows.reduce((acc, r) => acc + r.qtd_documentos, 0);
  const resultado = debitos - creditos - retencoes;
  return { debitos, creditos, retencoes, resultado, qtdDocs };
}

export default function ImpostosPageClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canImpostos = useMemo(() => {
    const v = te.has("impostos.view");
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (v === undefined || r === undefined || w === undefined) return undefined;
    // Prefer "impostos.view" when configured; fallback to Financeiro read/write.
    return Boolean(v || r || w);
  }, [te]);

  useEffect(() => {
    if (canImpostos === false) router.replace("/forbidden");
  }, [canImpostos, router]);

  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1) &&
    canImpostos === true;

  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const empresaNome = useMemo(() => {
    const byState = te.empresa?.nome_fantasia ?? te.empresa?.razao_social ?? null;
    if (byState && String(byState).trim()) return String(byState).trim();
    const found = te.empresas.find((e) => e.id === empresaId) ?? te.empresas[0] ?? null;
    return String(found?.nome_fantasia ?? found?.razao_social ?? "—");
  }, [empresaId, te.empresa?.nome_fantasia, te.empresa?.razao_social, te.empresas]);

  const now = useMemo(() => new Date(), []);
  const [tab, setTab] = useState<"mes" | "ano">("mes");
  const [ano, setAno] = useState<number>(() => now.getFullYear());
  const [mes, setMes] = useState<number>(() => now.getMonth() + 1);
  const [operacao, setOperacao] = useState<"" | "ENTRADA" | "SAIDA">("");
  const [natureza, setNatureza] = useState<"" | "DEBITO" | "CREDITO" | "RETENCAO">("");

  const compIni = useMemo(() => monthStartISO(ano, mes), [ano, mes]);
  const compFim = useMemo(() => nextMonthStartISO(ano, mes), [ano, mes]);
  const anoIni = useMemo(() => `${ano}-01-01`, [ano]);
  const anoFim = useMemo(() => `${ano + 1}-01-01`, [ano]);

  const [mesRows, setMesRows] = useState<ApuracaoRow[]>([]);
  const [anoRows, setAnoRows] = useState<ApuracaoRow[]>([]);
  const [loadingMes, setLoadingMes] = useState(false);
  const [loadingAno, setLoadingAno] = useState(false);
  const [errorMes, setErrorMes] = useState<string | null>(null);
  const [errorAno, setErrorAno] = useState<string | null>(null);

  useEffect(() => {
    if (!ready) return;
    let cancelled = false;

    const run = async () => {
      setLoadingMes(true);
      setErrorMes(null);
      try {
        const supabase = getSupabaseBrowser();
        const { data, error } = await supabase.schema("f").rpc("fn_imposto_apuracao_range", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_comp_ini: compIni,
          p_comp_fim: compFim,
          p_operacao: operacao || null,
          p_natureza: natureza || null,
        });
        if (error) throw error;
        if (cancelled) return;
        setMesRows(normalizeApuracaoRows((data ?? []) as unknown as ApuracaoRow[]));
      } catch (e: unknown) {
        if (cancelled) return;
        setMesRows([]);
        setErrorMes(e instanceof Error ? e.message : "Erro ao carregar apuração do mês.");
      } finally {
        if (!cancelled) setLoadingMes(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [compFim, compIni, empresaId, natureza, operacao, ready, tenantId]);

  useEffect(() => {
    if (!ready) return;
    let cancelled = false;

    const run = async () => {
      setLoadingAno(true);
      setErrorAno(null);
      try {
        const supabase = getSupabaseBrowser();
        const { data, error } = await supabase.schema("f").rpc("fn_imposto_apuracao_range", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_comp_ini: anoIni,
          p_comp_fim: anoFim,
          p_operacao: operacao || null,
          p_natureza: natureza || null,
        });
        if (error) throw error;
        if (cancelled) return;
        setAnoRows(normalizeApuracaoRows((data ?? []) as unknown as ApuracaoRow[]));
      } catch (e: unknown) {
        if (cancelled) return;
        setAnoRows([]);
        setErrorAno(e instanceof Error ? e.message : "Erro ao carregar apuração do ano.");
      } finally {
        if (!cancelled) setLoadingAno(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [anoFim, anoIni, empresaId, natureza, operacao, ready, tenantId]);

  const mesTableRows = useMemo(() => aggregateForTable(mesRows), [mesRows]);
  const mesTotals = useMemo(() => sumByNatureza(mesTableRows.map((r) => ({ natureza: r.natureza, valor_total_calculado: r.valor_total_calculado, qtd_documentos: r.qtd_documentos }))), [mesTableRows]);

  const anoByCompetencia = useMemo(() => {
    const by = new Map<string, ApuracaoAggRow[]>();
    for (const r of anoRows) {
      const key = String(r.competencia_date ?? "").slice(0, 10);
      if (!key) continue;
      const arr = by.get(key) ?? [];
      arr.push({
        imposto: String(r.imposto ?? ""),
        natureza: String(r.natureza ?? ""),
        base_total: n(r.base_total),
        valor_total_calculado: n(r.valor_total_calculado),
        valor_total_ajustado: n(r.valor_total_ajustado),
        qtd_documentos: n(r.qtd_documentos),
      });
      by.set(key, arr);
    }
    return by;
  }, [anoRows]);

  const anoMonthRows = useMemo(() => {
    return Array.from({ length: 12 }).map((_, idx) => {
      const month = idx + 1;
      const competencia = monthStartISO(ano, month);
      const rows = anoByCompetencia.get(competencia) ?? [];
      const totals = sumByNatureza(rows.map((r) => ({ natureza: r.natureza, valor_total_calculado: r.valor_total_calculado, qtd_documentos: r.qtd_documentos })));
      return {
        month,
        competencia,
        ...totals,
      };
    });
  }, [ano, anoByCompetencia]);

  const anoTotals = useMemo(() => {
    const rows = anoMonthRows.map((m) => ({
      natureza: "__",
      valor_total_calculado: 0,
      qtd_documentos: 0,
      debitos: m.debitos,
      creditos: m.creditos,
      retencoes: m.retencoes,
      resultado: m.resultado,
      qtdDocs: m.qtdDocs,
    }));
    const debitos = rows.reduce((acc, r) => acc + r.debitos, 0);
    const creditos = rows.reduce((acc, r) => acc + r.creditos, 0);
    const retencoes = rows.reduce((acc, r) => acc + r.retencoes, 0);
    const resultado = rows.reduce((acc, r) => acc + r.resultado, 0);
    const qtdDocs = rows.reduce((acc, r) => acc + r.qtdDocs, 0);
    return { debitos, creditos, retencoes, resultado, qtdDocs };
  }, [anoMonthRows]);

  const [docsOpen, setDocsOpen] = useState(false);
  const [docsKey, setDocsKey] = useState<{ imposto: string; natureza: string } | null>(null);
  const [docs, setDocs] = useState<DocumentoImpostoRow[]>([]);
  const [docsLoading, setDocsLoading] = useState(false);
  const [docsError, setDocsError] = useState<string | null>(null);

  const openDocs = (imposto: string, nat: string) => {
    setDocsKey({ imposto, natureza: nat });
    setDocsOpen(true);
  };

  const closeDocs = () => {
    setDocsOpen(false);
    setDocsKey(null);
    setDocs([]);
    setDocsError(null);
    setDocsLoading(false);
  };

  useEffect(() => {
    if (!docsOpen) return;
    if (!docsKey) return;
    if (!ready) return;

    let cancelled = false;

    const run = async () => {
      setDocsLoading(true);
      setDocsError(null);
      try {
        const supabase = getSupabaseBrowser();
        const { data, error } = await supabase.schema("f").rpc("fn_imposto_documentos_do_mes", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_competencia: compIni,
          p_imposto: docsKey.imposto,
          p_nat: docsKey.natureza,
          p_operacao: operacao || null,
        });
        if (error) throw error;
        if (cancelled) return;
        setDocs(((data ?? []) as unknown as DocumentoImpostoRow[]).map((r) => ({ ...r, documento_fiscal_id: String(r.documento_fiscal_id) })));
      } catch (e: unknown) {
        if (cancelled) return;
        setDocs([]);
        setDocsError(e instanceof Error ? e.message : "Erro ao carregar documentos do imposto.");
      } finally {
        if (!cancelled) setDocsLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [compIni, docsKey, docsOpen, empresaId, operacao, ready, tenantId]);

  const years = useMemo(() => {
    const cur = now.getFullYear();
    return [cur - 2, cur - 1, cur, cur + 1];
  }, [now]);

  if (canImpostos !== true) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Impostos</h1>
          <p className="text-sm text-zinc-400 mt-1">Apuração mensal e visão anual.</p>
          <p className="text-xs text-zinc-500 mt-1">Empresa: {empresaNome}</p>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
          <div>
            <label className="text-xs text-zinc-400" htmlFor="imp-ano">
              Ano
            </label>
            <select
              id="imp-ano"
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
              value={String(ano)}
              onChange={(e) => setAno(Number(e.target.value))}
              disabled={!ready}
            >
              {years.map((y) => (
                <option key={y} value={String(y)}>
                  {y}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="imp-mes">
              Mês
            </label>
            <select
              id="imp-mes"
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
              value={String(mes)}
              onChange={(e) => setMes(Number(e.target.value))}
              disabled={!ready}
            >
              {MONTH_LABELS.map((label, idx) => (
                <option key={label} value={String(idx + 1)}>
                  {label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="imp-op">
              Operação
            </label>
            <select
              id="imp-op"
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
              value={operacao}
              onChange={(e) => setOperacao((e.target.value as "" | "ENTRADA" | "SAIDA") ?? "")}
              disabled={!ready}
            >
              <option value="">Todos</option>
              <option value="ENTRADA">ENTRADA</option>
              <option value="SAIDA">SAÍDA</option>
            </select>
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="imp-nat">
              Natureza
            </label>
            <select
              id="imp-nat"
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
              value={natureza}
              onChange={(e) => setNatureza((e.target.value as "" | "DEBITO" | "CREDITO" | "RETENCAO") ?? "")}
              disabled={!ready}
            >
              <option value="">Todos</option>
              <option value="DEBITO">DÉBITO</option>
              <option value="CREDITO">CRÉDITO</option>
              <option value="RETENCAO">RETENÇÃO</option>
            </select>
          </div>

          <div className="text-xs text-zinc-500">
            <div>Competência (mês): {formatDateBR(compIni)}</div>
            <div className="mt-1">
              {tab === "mes" ? (loadingMes ? "Carregando mês..." : errorMes ? "Erro no mês" : "OK") : null}
              {tab === "ano" ? (loadingAno ? "Carregando ano..." : errorAno ? "Erro no ano" : "OK") : null}
            </div>
          </div>
        </div>

        <div className="mt-3 text-xs text-zinc-500">
          <span className="text-zinc-400">Permissão:</span> impostos.view (preferencial) ou financeiro.read/write.
          {/* TODO: quando existir regra/role para "impostos.view", tornar obrigatório e remover fallback. */}
        </div>
      </div>

      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => setTab("mes")}
          className={`px-3 py-2 rounded-md border text-sm ${
            tab === "mes" ? "bg-zinc-900 border-zinc-700 text-zinc-100" : "bg-zinc-950 border-zinc-800 text-zinc-300 hover:bg-zinc-900"
          }`}
        >
          Mês
        </button>
        <button
          type="button"
          onClick={() => setTab("ano")}
          className={`px-3 py-2 rounded-md border text-sm ${
            tab === "ano" ? "bg-zinc-900 border-zinc-700 text-zinc-100" : "bg-zinc-950 border-zinc-800 text-zinc-300 hover:bg-zinc-900"
          }`}
        >
          Ano
        </button>
      </div>

      {tab === "mes" ? (
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
            <StatCard title="Total Débitos" value={formatMoneyBR(mesTotals.debitos)} />
            <StatCard title="Total Créditos" value={formatMoneyBR(mesTotals.creditos)} />
            <StatCard title="Total Retenções" value={formatMoneyBR(mesTotals.retencoes)} />
            <StatCard title="Resultado do mês" value={formatMoneyBR(mesTotals.resultado)} subtitle="Débitos - Créditos - Retenções" />
            <StatCard title="Qtd. docs (aprox.)" value={String(mesTotals.qtdDocs)} subtitle="Soma de qtd_documentos" />
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-end justify-between gap-3 flex-wrap">
              <div>
                <div className="text-sm font-medium text-zinc-100">Apuração por imposto</div>
                <div className="text-xs text-zinc-500 mt-1">Agrupado por imposto + natureza (competência {formatDateBR(compIni)}).</div>
              </div>
            </div>

            {errorMes ? <div className="mt-3 text-sm text-rose-200">{errorMes}</div> : null}

            <div className="mt-3 overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-zinc-400">
                  <tr className="border-b border-zinc-800">
                    <th className="text-left py-2 pr-3 font-medium">Imposto</th>
                    <th className="text-left py-2 pr-3 font-medium">Natureza</th>
                    <th className="text-right py-2 pr-3 font-medium">Base</th>
                    <th className="text-right py-2 pr-3 font-medium">Valor</th>
                    <th className="text-right py-2 pr-3 font-medium">Ajuste</th>
                    <th className="text-right py-2 pr-3 font-medium">Qtd</th>
                    <th className="text-right py-2 font-medium">Ações</th>
                  </tr>
                </thead>
                <tbody className="text-zinc-100">
                  {loadingMes ? (
                    <tr>
                      <td className="py-3 text-zinc-400" colSpan={7}>
                        Carregando...
                      </td>
                    </tr>
                  ) : mesTableRows.length ? (
                    mesTableRows.map((r) => (
                      <tr key={`${r.imposto}-${r.natureza}`} className="border-b border-zinc-900/60 hover:bg-zinc-900/30">
                        <td className="py-2 pr-3">{r.imposto}</td>
                        <td className="py-2 pr-3 text-zinc-300">{r.natureza}</td>
                        <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(r.base_total)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(r.valor_total_calculado)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(r.valor_total_ajustado)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums">{r.qtd_documentos}</td>
                        <td className="py-2 text-right">
                          <button
                            type="button"
                            onClick={() => openDocs(r.imposto, r.natureza)}
                            className="rounded-md border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-zinc-100 hover:bg-zinc-800"
                          >
                            Ver documentos
                          </button>
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td className="py-3 text-zinc-400" colSpan={7}>
                        Nenhum dado para o período/filtros.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
            <StatCard title="Total Débitos (ano)" value={formatMoneyBR(anoTotals.debitos)} />
            <StatCard title="Total Créditos (ano)" value={formatMoneyBR(anoTotals.creditos)} />
            <StatCard title="Total Retenções (ano)" value={formatMoneyBR(anoTotals.retencoes)} />
            <StatCard title="Resultado (ano)" value={formatMoneyBR(anoTotals.resultado)} subtitle="Débitos - Créditos - Retenções" />
            <StatCard title="Qtd. docs (aprox.)" value={String(anoTotals.qtdDocs)} subtitle="Soma de qtd_documentos" />
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-end justify-between gap-3 flex-wrap">
              <div>
                <div className="text-sm font-medium text-zinc-100">Visão anual</div>
                <div className="text-xs text-zinc-500 mt-1">Clique em um mês para abrir a aba “Mês”.</div>
              </div>
            </div>

            {errorAno ? <div className="mt-3 text-sm text-rose-200">{errorAno}</div> : null}

            <div className="mt-3 overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-zinc-400">
                  <tr className="border-b border-zinc-800">
                    <th className="text-left py-2 pr-3 font-medium">Mês</th>
                    <th className="text-right py-2 pr-3 font-medium">Débitos</th>
                    <th className="text-right py-2 pr-3 font-medium">Créditos</th>
                    <th className="text-right py-2 pr-3 font-medium">Retenções</th>
                    <th className="text-right py-2 pr-3 font-medium">Resultado</th>
                    <th className="text-right py-2 font-medium">Qtd</th>
                  </tr>
                </thead>
                <tbody className="text-zinc-100">
                  {loadingAno ? (
                    <tr>
                      <td className="py-3 text-zinc-400" colSpan={6}>
                        Carregando...
                      </td>
                    </tr>
                  ) : (
                    anoMonthRows.map((m) => (
                      <tr key={m.competencia} className="border-b border-zinc-900/60 hover:bg-zinc-900/30">
                        <td className="py-2 pr-3">
                          <button
                            type="button"
                            onClick={() => {
                              setMes(m.month);
                              setTab("mes");
                            }}
                            className="text-left text-zinc-100 hover:underline"
                          >
                            {MONTH_LABELS[m.month - 1]} / {ano}
                          </button>
                        </td>
                        <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(m.debitos)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(m.creditos)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(m.retencoes)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(m.resultado)}</td>
                        <td className="py-2 text-right tabular-nums">{m.qtdDocs}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {docsOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={(e) => e.target === e.currentTarget && closeDocs()}>
          <div className="w-full max-w-5xl rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl">
            <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
              <div>
                <div className="text-sm font-medium text-zinc-100">
                  Documentos — {docsKey?.imposto} / {docsKey?.natureza}
                </div>
                <div className="text-xs text-zinc-500">
                  Competência: {formatDateBR(compIni)} {operacao ? `• Operação: ${operacao}` : ""}
                </div>
              </div>
              <button type="button" onClick={closeDocs} className="text-sm text-zinc-300 hover:text-zinc-100">
                Fechar
              </button>
            </div>

            <div className="p-4">
              {docsError ? <div className="rounded-md border border-rose-900/60 bg-rose-950/20 px-3 py-2 text-sm text-rose-200">{docsError}</div> : null}

              <div className="mt-3 overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-zinc-400">
                    <tr className="border-b border-zinc-800">
                      <th className="text-left py-2 pr-3 font-medium">Emissão</th>
                      <th className="text-left py-2 pr-3 font-medium">Documento</th>
                      <th className="text-left py-2 pr-3 font-medium">Operação</th>
                      <th className="text-right py-2 pr-3 font-medium">Valor doc</th>
                      <th className="text-right py-2 font-medium">Valor imposto</th>
                    </tr>
                  </thead>
                  <tbody className="text-zinc-100">
                    {docsLoading ? (
                      <tr>
                        <td className="py-3 text-zinc-400" colSpan={5}>
                          Carregando...
                        </td>
                      </tr>
                    ) : docs.length ? (
                      docs.map((d) => {
                        const modelo = String(d.modelo ?? "").trim().toUpperCase();
                        const href =
                          modelo === "NFSE"
                            ? `/faturamento/nfse/${d.documento_fiscal_id}`
                            : `/faturamento/nfe/${d.documento_fiscal_id}`;
                        const docLabel = d.chave_acesso
                          ? String(d.chave_acesso)
                          : `${String(d.serie ?? "").trim()}/${String(d.numero ?? "").trim()}`;

                        return (
                          <tr key={d.documento_fiscal_id} className="border-b border-zinc-900/60 hover:bg-zinc-900/30">
                            <td className="py-2 pr-3 text-zinc-300">{formatDateBR(d.emissao_date)}</td>
                            <td className="py-2 pr-3">
                              <Link href={href} className="hover:underline">
                                {docLabel}
                              </Link>
                              <div className="text-xs text-zinc-500">ID: {d.documento_fiscal_id}</div>
                            </td>
                            <td className="py-2 pr-3 text-zinc-300">{d.operacao}</td>
                            <td className="py-2 pr-3 text-right tabular-nums">{formatMoneyBR(n(d.valor_documento))}</td>
                            <td className="py-2 text-right tabular-nums">{formatMoneyBR(n(d.valor_imposto))}</td>
                          </tr>
                        );
                      })
                    ) : (
                      <tr>
                        <td className="py-3 text-zinc-400" colSpan={5}>
                          Nenhum documento encontrado.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

