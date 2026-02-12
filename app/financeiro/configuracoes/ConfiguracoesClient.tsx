"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { formatDecimalBR, parseDecimalBR } from "@/lib/decimal";

type Diagnostics = {
  planoContasCount: number | null;
  centroCustoCount: number | null;
  contasBancariasCount: number | null;
  motivosCompraCount: number | null;
};

type Preferences = {
  cashflowDefaultDaysAhead: number;
  cashflowDefaultDaysBack: number;
  agingBuckets: "0-30|31-60|61-90|90+" | "0-15|16-30|31-60|60+";
  highlightOverdueDays: number;
  defaultMoneyDecimals: 2 | 3;
  showCompetenciaHint: boolean;
};

const DEFAULT_PREFS: Preferences = {
  cashflowDefaultDaysAhead: 90,
  cashflowDefaultDaysBack: 30,
  agingBuckets: "0-30|31-60|61-90|90+",
  highlightOverdueDays: 15,
  defaultMoneyDecimals: 2,
  showCompetenciaHint: true,
};

function clampInt(n: number, min: number, max: number) {
  const v = Math.trunc(Number.isFinite(n) ? n : min);
  return Math.max(min, Math.min(max, v));
}

function prefsKey(userId: string, tenantId: string, empresaId: string) {
  return `financeiro:config_prefs:${userId}:${tenantId}:${empresaId}`;
}

function readPrefs(key: string): Preferences {
  if (typeof window === "undefined") return DEFAULT_PREFS;
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) return DEFAULT_PREFS;
    const parsed = JSON.parse(raw) as Partial<Preferences>;

    return {
      cashflowDefaultDaysAhead: clampInt(Number(parsed.cashflowDefaultDaysAhead ?? DEFAULT_PREFS.cashflowDefaultDaysAhead), 7, 365),
      cashflowDefaultDaysBack: clampInt(Number(parsed.cashflowDefaultDaysBack ?? DEFAULT_PREFS.cashflowDefaultDaysBack), 0, 365),
      agingBuckets: parsed.agingBuckets === "0-15|16-30|31-60|60+" ? parsed.agingBuckets : DEFAULT_PREFS.agingBuckets,
      highlightOverdueDays: clampInt(Number(parsed.highlightOverdueDays ?? DEFAULT_PREFS.highlightOverdueDays), 0, 180),
      defaultMoneyDecimals: parsed.defaultMoneyDecimals === 3 ? 3 : 2,
      showCompetenciaHint: typeof parsed.showCompetenciaHint === "boolean" ? parsed.showCompetenciaHint : DEFAULT_PREFS.showCompetenciaHint,
    };
  } catch {
    return DEFAULT_PREFS;
  }
}

function writePrefs(key: string, prefs: Preferences) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(key, JSON.stringify(prefs));
  } catch {
    // ignore
  }
}

function Stat({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-400">{title}</div>
      <div className="mt-2 text-2xl font-semibold text-zinc-100 tabular-nums">{value}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
    </div>
  );
}

function SectionTitle({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div>
      <div className="text-sm font-semibold text-zinc-100">{title}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
    </div>
  );
}

function CardLink({ href, title, desc }: { href: string; title: string; desc: string }) {
  return (
    <Link
      href={href}
      className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 hover:bg-zinc-900 transition-colors"
    >
      <div className="text-sm font-semibold text-zinc-100">{title}</div>
      <div className="mt-1 text-sm text-zinc-400">{desc}</div>
      <div className="mt-3 text-xs text-zinc-500">Abrir →</div>
    </Link>
  );
}

export default function ConfiguracoesClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canAccess = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    const c = te.has("financeiro.config");
    if (r === undefined || w === undefined || c === undefined) return undefined;
    return Boolean(c || w || r);
  }, [te]);

  useEffect(() => {
    if (canAccess === false) router.replace("/forbidden");
  }, [canAccess, router]);

  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1) &&
    canAccess === true;

  const effectiveEmpresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0].id : null);
  const prefsStorageKey =
    typeof te.sessionUserId === "string" && te.tenantId && effectiveEmpresaId
      ? prefsKey(te.sessionUserId, te.tenantId, effectiveEmpresaId)
      : null;

  const [diagnostics, setDiagnostics] = useState<Diagnostics>({
    planoContasCount: null,
    centroCustoCount: null,
    contasBancariasCount: null,
    motivosCompraCount: null,
  });
  const [diagLoading, setDiagLoading] = useState(false);
  const [diagError, setDiagError] = useState<string | null>(null);

  const [prefs, setPrefs] = useState<Preferences>(() => (prefsStorageKey ? readPrefs(prefsStorageKey) : DEFAULT_PREFS));

  useEffect(() => {
    if (!prefsStorageKey) return;
    setPrefs(readPrefs(prefsStorageKey));
  }, [prefsStorageKey]);

  useEffect(() => {
    if (!prefsStorageKey) return;
    writePrefs(prefsStorageKey, prefs);
  }, [prefs, prefsStorageKey]);

  useEffect(() => {
    if (!ready) return;
    if (!te.tenantId) return;

    let cancelled = false;

    const run = async () => {
      setDiagLoading(true);
      setDiagError(null);

      const supabase = getSupabaseBrowser();

      const safeCount = async (table: string) => {
        try {
          const res = await supabase
            .schema("f")
            .from(table)
            .select("id", { count: "exact", head: true })
            .eq("tenant_id", te.tenantId as string);
          if (res.error) return null;
          return typeof res.count === "number" ? res.count : null;
        } catch {
          return null;
        }
      };

      try {
        const [planoContasCount, centroCustoCount, contasBancariasCount, motivosCompraCount] = await Promise.all([
          safeCount("plano_contas"),
          safeCount("centro_custo"),
          safeCount("conta_bancaria"),
          safeCount("motivo_compra"),
        ]);

        if (cancelled) return;
        setDiagnostics({ planoContasCount, centroCustoCount, contasBancariasCount, motivosCompraCount });
      } catch (e: unknown) {
        if (cancelled) return;
        setDiagError(e instanceof Error ? e.message : "Erro ao carregar diagnóstico.");
      } finally {
        if (!cancelled) setDiagLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [ready, te.tenantId]);

  const moneyExample = useMemo(() => {
    const v = parseDecimalBR("1234,56");
    const decimals = prefs.defaultMoneyDecimals;
    return formatDecimalBR(v, decimals);
  }, [prefs.defaultMoneyDecimals]);

  if (canAccess !== true) return null;

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Configurações — Financeiro</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Cadastros, integrações e preferências dos relatórios (Fluxo de Caixa / Aging), com foco em gestão no regime do Lucro Real.
          </p>
        </div>
        <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
          Voltar
        </Link>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
        <Stat
          title="Plano de contas"
          value={diagnostics.planoContasCount === null ? "—" : String(diagnostics.planoContasCount)}
          subtitle="Estrutura contábil"
        />
        <Stat
          title="Centros de custo"
          value={diagnostics.centroCustoCount === null ? "—" : String(diagnostics.centroCustoCount)}
          subtitle="Gestão por área/projeto"
        />
        <Stat
          title="Contas bancárias"
          value={diagnostics.contasBancariasCount === null ? "—" : String(diagnostics.contasBancariasCount)}
          subtitle="Extratos/caixa"
        />
        <Stat
          title="Motivos de compra"
          value={diagnostics.motivosCompraCount === null ? "—" : String(diagnostics.motivosCompraCount)}
          subtitle="Classificações"
        />
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex items-center justify-between gap-2">
          <SectionTitle title="Diagnóstico" subtitle="Contagens via Supabase (best-effort)." />
          <div className="text-xs text-zinc-500">{diagLoading ? "Atualizando…" : ""}</div>
        </div>
        {diagError ? <div className="mt-3 text-sm text-red-400">{diagError}</div> : null}
        <div className="mt-3 text-xs text-zinc-500">
          Se alguma contagem aparecer como “—”, pode ser falta de permissão/RLS, tabela ausente no schema atual, ou ambiente sem dados.
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <SectionTitle title="Cadastros (estrutura)" subtitle="Base para conciliação, classificações e relatórios." />
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <CardLink href="/financeiro/cadastros/plano-contas" title="Plano de Contas" desc="Natureza, hierarquia e códigos (Sintética/Analítica)." />
          <CardLink href="/financeiro/cadastros/centro-custo" title="Centros de Custo" desc="Organize despesas/receitas por área, contrato ou projeto." />
          <CardLink href="/financeiro/cadastros/contas-bancarias" title="Contas Bancárias" desc="Bancos/contas para extratos, conciliação e transferências." />
          <CardLink href="/financeiro/cadastros/motivos-compra" title="Motivos / Classificação" desc="Classificação gerencial para compras e despesas." />
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <SectionTitle title="Operação" subtitle="Fluxo diário (caixa) e rotinas." />
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <CardLink href="/financeiro/extratos" title="Extratos Bancários" desc="Importação/visualização de extratos para base do realizado." />
          <CardLink href="/financeiro/conciliacao" title="Conciliação" desc="Vincule lançamentos e ajuste divergências (controle de caixa)." />
          <CardLink href="/financeiro/transferencias" title="Transferências" desc="Movimente valores entre contas com rastreabilidade." />
          <CardLink href="/financeiro/relatorios/fluxo-caixa" title="Relatórios: Fluxo de Caixa" desc="Previsto vs Realizado vs Diário (planejamento e controle)." />
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-4">
        <SectionTitle title="Preferências (Lucro Real)" subtitle="Preferências do usuário (armazenadas no navegador)." />

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-sm font-semibold text-zinc-100">Fluxo de Caixa — horizonte padrão</div>
            <div className="mt-2 grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs text-zinc-400" htmlFor="daysBack">Dias para trás</label>
                <input
                  id="daysBack"
                  type="number"
                  min={0}
                  max={365}
                  value={prefs.cashflowDefaultDaysBack}
                  onChange={(e) =>
                    setPrefs((p) => ({ ...p, cashflowDefaultDaysBack: clampInt(Number(e.target.value), 0, 365) }))
                  }
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </div>
              <div>
                <label className="text-xs text-zinc-400" htmlFor="daysAhead">Dias para frente</label>
                <input
                  id="daysAhead"
                  type="number"
                  min={7}
                  max={365}
                  value={prefs.cashflowDefaultDaysAhead}
                  onChange={(e) =>
                    setPrefs((p) => ({ ...p, cashflowDefaultDaysAhead: clampInt(Number(e.target.value), 7, 365) }))
                  }
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </div>
            </div>
            <div className="mt-2 text-xs text-zinc-500">
              Sugestão Lucro Real: mantenha competência separada do caixa; use o previsto/realizado para planejamento e controle.
            </div>
          </div>

          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-sm font-semibold text-zinc-100">Aging — faixas padrão</div>
            <div className="mt-2">
              <label className="text-xs text-zinc-400" htmlFor="agingBuckets">Faixas</label>
              <select
                id="agingBuckets"
                value={prefs.agingBuckets}
                onChange={(e) =>
                  setPrefs((p) => ({
                    ...p,
                    agingBuckets:
                      e.target.value === "0-15|16-30|31-60|60+" ? "0-15|16-30|31-60|60+" : "0-30|31-60|61-90|90+",
                  }))
                }
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
              >
                <option value="0-30|31-60|61-90|90+">0–30 / 31–60 / 61–90 / 90+</option>
                <option value="0-15|16-30|31-60|60+">0–15 / 16–30 / 31–60 / 60+</option>
              </select>
              <div className="mt-2 text-xs text-zinc-500">Faixas menores ajudam a priorizar cobrança/renegociação.</div>
            </div>
          </div>

          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-sm font-semibold text-zinc-100">Alertas</div>
            <div className="mt-2">
              <label className="text-xs text-zinc-400" htmlFor="overdue">Destacar atraso a partir de (dias)</label>
              <input
                id="overdue"
                type="number"
                min={0}
                max={180}
                value={prefs.highlightOverdueDays}
                onChange={(e) => setPrefs((p) => ({ ...p, highlightOverdueDays: clampInt(Number(e.target.value), 0, 180) }))}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
              />
              <div className="mt-2 text-xs text-zinc-500">Útil para gestão de risco e follow-up com cliente/fornecedor.</div>
            </div>
          </div>

          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-sm font-semibold text-zinc-100">Formatação</div>
            <div className="mt-2 grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs text-zinc-400" htmlFor="decimals">Casas decimais</label>
                <select
                  id="decimals"
                  value={String(prefs.defaultMoneyDecimals)}
                  onChange={(e) => setPrefs((p) => ({ ...p, defaultMoneyDecimals: e.target.value === "3" ? 3 : 2 }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                >
                  <option value="2">2</option>
                  <option value="3">3</option>
                </select>
              </div>
              <div className="text-xs text-zinc-500 flex items-end">Exemplo: {moneyExample}</div>
            </div>

            <div className="mt-3 flex items-center gap-2">
              <input
                id="competenciaHint"
                type="checkbox"
                checked={prefs.showCompetenciaHint}
                onChange={(e) => setPrefs((p) => ({ ...p, showCompetenciaHint: e.target.checked }))}
                className="h-4 w-4"
              />
              <label htmlFor="competenciaHint" className="text-sm text-zinc-200 select-none">
                Mostrar dica “competência vs caixa” nos relatórios
              </label>
            </div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setPrefs(DEFAULT_PREFS)}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Restaurar padrões
          </button>
          <button
            type="button"
            onClick={() => {
              const payload = {
                scope: { userId: te.sessionUserId, tenantId: te.tenantId, empresaId: effectiveEmpresaId },
                prefs,
              };
              const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
              const url = URL.createObjectURL(blob);
              const a = document.createElement("a");
              a.href = url;
              a.download = "financeiro_config_prefs.json";
              a.click();
              setTimeout(() => URL.revokeObjectURL(url), 1000);
            }}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Exportar preferências
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-300">
        <div className="font-semibold text-zinc-100">Guia rápido (Lucro Real)</div>
        <ul className="mt-2 list-disc list-inside space-y-1 text-zinc-300">
          <li>Use competência para apurar resultado; use caixa para liquidez (não confundir).</li>
          <li>Plano de contas + centro de custo sustentam DRE gerencial e análises.</li>
          <li>Aging (AR/AP) é risco por vencimento; fluxo de caixa é planejamento/execução.</li>
        </ul>
      </div>
    </div>
  );
}
