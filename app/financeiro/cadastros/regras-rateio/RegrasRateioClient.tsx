"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type MotivoRow = {
  id: string;
  codigo: string;
  nome: string;
  plano_contas_id: string | null;
};

type PlanoRow = {
  id: string;
  codigo: string;
  nome: string;
};

type CentroRow = {
  id: string;
  codigo: string;
  nome: string;
};

type RegraItem = {
  id: string | null;
  plano_contas_id: string;
  plano_codigo: string;
  plano_nome: string;
  centro_custo_id: string;
  centro_codigo: string;
  centro_nome: string;
  percentual: number;
};

type RegraRow = {
  id: string;
  motivo_compra_id: string | null;
  motivo_codigo: string | null;
  motivo_nome: string | null;
  ativo: boolean;
  itens: RegraItem[];
  updated_at: string | null;
};

type FormItem = {
  key: string;
  plano_contas_id: string;
  centro_custo_id: string;
  percentual: string;
};

type OperationResult = {
  rateios_criados?: number;
  centros_preenchidos?: number;
  titulos_analisados?: number;
  ignorados?: number;
  limite?: number;
  truncado?: boolean;
  pendentes_restantes?: number;
  [key: string]: unknown;
};

let formSequence = 0;

function nextFormKey() {
  formSequence += 1;
  return `rateio-${formSequence}`;
}

function normalizeText(value: unknown) {
  return String(value ?? "").trim();
}

function parsePercent(value: string) {
  const trimmed = value.trim();
  const normalized = trimmed.includes(",")
    ? trimmed.replace(/\./g, "").replace(",", ".")
    : trimmed;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatPercent(value: number) {
  return new Intl.NumberFormat("pt-BR", {
    minimumFractionDigits: value % 1 === 0 ? 0 : 2,
    maximumFractionDigits: 4,
  }).format(value);
}

function formatDateTime(value: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(date);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function parseRuleItem(value: unknown): RegraItem | null {
  const row = asRecord(value);
  if (!row) return null;

  const planoId = normalizeText(row.plano_contas_id);
  const centroId = normalizeText(row.centro_custo_id);
  if (!planoId || !centroId) return null;

  const percentual = Number(row.percentual ?? 0);
  return {
    id: normalizeText(row.id) || null,
    plano_contas_id: planoId,
    plano_codigo: normalizeText(row.plano_codigo),
    plano_nome: normalizeText(row.plano_nome),
    centro_custo_id: centroId,
    centro_codigo: normalizeText(row.centro_codigo),
    centro_nome: normalizeText(row.centro_nome),
    percentual: Number.isFinite(percentual) ? percentual : 0,
  };
}

function parseRule(value: unknown): RegraRow | null {
  const row = asRecord(value);
  if (!row) return null;
  const id = normalizeText(row.id);
  if (!id) return null;

  const rawItems = Array.isArray(row.itens) ? row.itens : [];
  const itens = rawItems.map(parseRuleItem).filter((item): item is RegraItem => Boolean(item));

  return {
    id,
    motivo_compra_id: normalizeText(row.motivo_compra_id) || null,
    motivo_codigo: normalizeText(row.motivo_codigo) || null,
    motivo_nome: normalizeText(row.motivo_nome) || null,
    ativo: row.ativo !== false,
    itens,
    updated_at: normalizeText(row.updated_at) || null,
  };
}

function parseRules(value: unknown): RegraRow[] {
  const payload = asRecord(value);
  const raw = Array.isArray(value)
    ? value
    : Array.isArray(payload?.regras)
      ? payload.regras
      : [];

  return raw
    .map(parseRule)
    .filter((rule): rule is RegraRow => Boolean(rule))
    .sort((a, b) => {
      if (a.motivo_compra_id === null && b.motivo_compra_id !== null) return -1;
      if (a.motivo_compra_id !== null && b.motivo_compra_id === null) return 1;
      return `${a.motivo_codigo ?? ""} ${a.motivo_nome ?? ""}`.localeCompare(
        `${b.motivo_codigo ?? ""} ${b.motivo_nome ?? ""}`,
        "pt-BR",
      );
    });
}

function emptyItem(planoId = "", percentual = "100") {
  return {
    key: nextFormKey(),
    plano_contas_id: planoId,
    centro_custo_id: "",
    percentual,
  } satisfies FormItem;
}

export default function RegrasRateioClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const canFinanceiro = useMemo(() => {
    const read = te.has("financeiro.read");
    const write = te.has("financeiro.write");
    if (read === undefined || write === undefined) return undefined;
    return Boolean(read || write);
  }, [te]);

  const canWrite = useMemo(() => {
    const write = te.has("financeiro.write");
    if (write === undefined) return undefined;
    return Boolean(write);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [rules, setRules] = useState<RegraRow[]>([]);
  const [motivos, setMotivos] = useState<MotivoRow[]>([]);
  const [planos, setPlanos] = useState<PlanoRow[]>([]);
  const [centros, setCentros] = useState<CentroRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const [modalOpen, setModalOpen] = useState(false);
  const [formId, setFormId] = useState<string | null>(null);
  const [formMotivoId, setFormMotivoId] = useState("");
  const [formAtivo, setFormAtivo] = useState(true);
  const [formItems, setFormItems] = useState<FormItem[]>([emptyItem()]);
  const [saving, setSaving] = useState(false);
  const [archivingId, setArchivingId] = useState<string | null>(null);
  const [applying, setApplying] = useState(false);

  const query = searchParams.get("q")?.trim() ?? "";
  const status = searchParams.get("status") === "todas" ? "todas" : "ativas";

  const setUrlFilter = useCallback(
    (key: "q" | "status", value: string) => {
      const params = new URLSearchParams(searchParams.toString());
      if (!value || (key === "status" && value === "ativas")) params.delete(key);
      else params.set(key, value);
      const next = params.toString();
      router.replace(next ? `${pathname}?${next}` : pathname, { scroll: false });
    },
    [pathname, router, searchParams],
  );

  const empresaNome =
    te.empresa?.nome_fantasia?.trim() ||
    te.empresa?.razao_social?.trim() ||
    "empresa selecionada";

  const reload = useCallback(async () => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId || !te.empresaId || canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();
      const [rulesResult, motivosResult, planosResult, centrosResult] = await Promise.all([
        supabase.schema("f").rpc("listar_regras_rateio", {
          p_tenant_id: te.tenantId,
          p_empresa_id: te.empresaId,
        }),
        supabase
          .schema("f")
          .from("motivo_compra")
          .select("id,codigo,nome,plano_contas_id")
          .eq("tenant_id", te.tenantId)
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("codigo", { ascending: true }),
        supabase
          .schema("f")
          .from("plano_contas")
          .select("id,codigo,nome")
          .eq("tenant_id", te.tenantId)
          .eq("tipo", "ANALITICA")
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("codigo", { ascending: true }),
        supabase
          .schema("f")
          .from("centro_custo")
          .select("id,codigo,nome")
          .eq("tenant_id", te.tenantId)
          .eq("empresa_id", te.empresaId)
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("codigo", { ascending: true }),
      ]);

      if (rulesResult.error) throw rulesResult.error;
      if (motivosResult.error) throw motivosResult.error;
      if (planosResult.error) throw planosResult.error;
      if (centrosResult.error) throw centrosResult.error;

      setRules(parseRules(rulesResult.data));
      setMotivos((motivosResult.data ?? []) as MotivoRow[]);
      setPlanos((planosResult.data ?? []) as PlanoRow[]);
      setCentros((centrosResult.data ?? []) as CentroRow[]);
    } catch (cause: unknown) {
      setRules([]);
      setMotivos([]);
      setPlanos([]);
      setCentros([]);
      setError(cause instanceof Error ? cause.message : "Erro ao carregar as regras de rateio.");
    } finally {
      setLoading(false);
    }
  }, [
    canFinanceiro,
    te.empresaId,
    te.sessionUserId,
    te.tenantId,
  ]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void reload();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [reload]);

  const filteredRules = useMemo(() => {
    const term = query.toLocaleLowerCase("pt-BR");
    return rules.filter((rule) => {
      if (status === "ativas" && !rule.ativo) return false;
      if (!term) return true;
      const destinations = rule.itens
        .map(
          (item) =>
            `${item.plano_codigo} ${item.plano_nome} ${item.centro_codigo} ${item.centro_nome}`,
        )
        .join(" ");
      return `${rule.motivo_codigo ?? "PADRAO"} ${rule.motivo_nome ?? ""} ${destinations}`
        .toLocaleLowerCase("pt-BR")
        .includes(term);
    });
  }, [query, rules, status]);

  const motivoById = useMemo(
    () => new Map(motivos.map((motivo) => [motivo.id, motivo])),
    [motivos],
  );
  const planoById = useMemo(
    () => new Map(planos.map((plano) => [plano.id, plano])),
    [planos],
  );

  const stats = useMemo(() => {
    const active = rules.filter((rule) => rule.ativo);
    return {
      ativas: active.length,
      motivos: active.filter((rule) => rule.motivo_compra_id !== null).length,
      divisoes: active.filter((rule) => rule.itens.length > 1).length,
      semPlano: motivos.filter(
        (motivo) =>
          !motivo.plano_contas_id || !planoById.has(motivo.plano_contas_id),
      ).length,
    };
  }, [motivos, planoById, rules]);

  const totalPercentual = useMemo(
    () => formItems.reduce((sum, item) => sum + parsePercent(item.percentual), 0),
    [formItems],
  );

  const openNew = () => {
    if (canWrite !== true) return;
    setError(null);
    setNotice(null);
    setFormId(null);
    setFormMotivoId("");
    setFormAtivo(true);
    setFormItems([emptyItem()]);
    setModalOpen(true);
  };

  const openEdit = (rule: RegraRow) => {
    if (canWrite !== true) return;
    setError(null);
    setNotice(null);
    setFormId(rule.id);
    setFormMotivoId(rule.motivo_compra_id ?? "");
    setFormAtivo(rule.ativo);
    setFormItems(
      rule.itens.length > 0
        ? rule.itens.map((item) => ({
            key: nextFormKey(),
            plano_contas_id: item.plano_contas_id,
            centro_custo_id: item.centro_custo_id,
            percentual: String(item.percentual).replace(".", ","),
          }))
        : [emptyItem()],
    );
    setModalOpen(true);
  };

  const changeMotivo = (motivoId: string) => {
    const nextMotivo = motivoById.get(motivoId);
    setFormMotivoId(motivoId);
    setFormItems((current) =>
      current.map((item) => ({
        ...item,
        plano_contas_id: nextMotivo?.plano_contas_id ?? "",
      })),
    );
  };

  const updateItem = (
    key: string,
    field: "plano_contas_id" | "centro_custo_id" | "percentual",
    value: string,
  ) => {
    setFormItems((current) =>
      current.map((item) => (item.key === key ? { ...item, [field]: value } : item)),
    );
  };

  const addItem = () => {
    const remaining = Math.max(0, 100 - totalPercentual);
    setFormItems((current) => [
      ...current,
      emptyItem(
        motivoById.get(formMotivoId)?.plano_contas_id ?? "",
        remaining > 0 ? String(remaining).replace(".", ",") : "",
      ),
    ]);
  };

  const removeItem = (key: string) => {
    setFormItems((current) =>
      current.length === 1 ? current : current.filter((item) => item.key !== key),
    );
  };

  const saveRule = async () => {
    if (canWrite !== true || !te.tenantId || !te.empresaId) return;

    const selectedMotivo = motivoById.get(formMotivoId);
    if (!selectedMotivo) {
      setError("Selecione um motivo de compra para a regra.");
      return;
    }
    if (
      !selectedMotivo.plano_contas_id ||
      !planoById.has(selectedMotivo.plano_contas_id)
    ) {
      setError("Este motivo ainda não possui um plano de contas analítico válido.");
      return;
    }
    if (centros.length === 0) {
      setError("Cadastre ao menos um centro de custo ativo para esta empresa.");
      return;
    }
    if (formItems.some((item) => !item.plano_contas_id || !item.centro_custo_id)) {
      setError("Informe o plano de contas e o centro de custo em todos os destinos.");
      return;
    }
    if (
      formItems.some(
        (item) => item.plano_contas_id !== selectedMotivo.plano_contas_id,
      )
    ) {
      setError("O plano de contas dos destinos deve ser o plano definido no motivo.");
      return;
    }
    if (formItems.some((item) => parsePercent(item.percentual) <= 0)) {
      setError("Todos os percentuais devem ser maiores que zero.");
      return;
    }
    if (Math.abs(totalPercentual - 100) > 0.0001) {
      setError(`A soma dos percentuais deve ser 100%. Soma atual: ${formatPercent(totalPercentual)}%.`);
      return;
    }

    const dimensions = new Set<string>();
    for (const item of formItems) {
      const dimension = `${item.plano_contas_id}:${item.centro_custo_id}`;
      if (dimensions.has(dimension)) {
        setError("O mesmo plano e centro de custo não podem aparecer duas vezes na regra.");
        return;
      }
      dimensions.add(dimension);
    }

    setSaving(true);
    setError(null);
    setNotice(null);

    try {
      const supabase = getSupabaseBrowser();
      const { error: saveError } = await supabase.schema("f").rpc("salvar_regra_rateio", {
        p_tenant_id: te.tenantId,
        p_empresa_id: te.empresaId,
        p_regra_id: formId,
        p_motivo_compra_id: formMotivoId || null,
        p_ativo: formAtivo,
        p_itens: formItems.map((item) => ({
          plano_contas_id: item.plano_contas_id,
          centro_custo_id: item.centro_custo_id,
          percentual: parsePercent(item.percentual),
        })),
      });
      if (saveError) throw saveError;

      setModalOpen(false);
      setNotice(
        formId
          ? "Regra atualizada. Os próximos lançamentos usarão a nova configuração."
          : "Regra criada. Ela já está disponível para os próximos lançamentos.",
      );
      await reload();
    } catch (cause: unknown) {
      setError(cause instanceof Error ? cause.message : "Erro ao salvar a regra.");
    } finally {
      setSaving(false);
    }
  };

  const archiveRule = async (rule: RegraRow) => {
    if (canWrite !== true || !te.tenantId || !te.empresaId) return;
    const label = rule.motivo_codigo
      ? `${rule.motivo_codigo} — ${rule.motivo_nome ?? ""}`
      : "Padrão da empresa";
    if (!window.confirm(`Arquivar a regra “${label}”? O histórico não será alterado.`)) return;

    setArchivingId(rule.id);
    setError(null);
    setNotice(null);
    try {
      const supabase = getSupabaseBrowser();
      const { error: archiveError } = await supabase.schema("f").rpc("arquivar_regra_rateio", {
        p_tenant_id: te.tenantId,
        p_empresa_id: te.empresaId,
        p_regra_id: rule.id,
      });
      if (archiveError) throw archiveError;
      setNotice("Regra arquivada. Os rateios já gravados foram preservados.");
      await reload();
    } catch (cause: unknown) {
      setError(cause instanceof Error ? cause.message : "Erro ao arquivar a regra.");
    } finally {
      setArchivingId(null);
    }
  };

  const applyPending = async () => {
    if (canWrite !== true || !te.tenantId || !te.empresaId) return;
    const confirmed = window.confirm(
      "Aplicar as regras aos lançamentos pendentes desta empresa? O processo não altera planos, valores, OS ou rateios manuais existentes.",
    );
    if (!confirmed) return;

    setApplying(true);
    setError(null);
    setNotice(null);
    try {
      const supabase = getSupabaseBrowser();
      const { data, error: applyError } = await supabase
        .schema("f")
        .rpc("aplicar_regras_rateio_pendentes", {
          p_tenant_id: te.tenantId,
          p_empresa_id: te.empresaId,
          p_limite: 2000,
        });
      if (applyError) throw applyError;

      const result = (asRecord(data) ?? {}) as OperationResult;
      const created = Number(result.rateios_criados ?? 0);
      const centers = Number(result.centros_preenchidos ?? 0);
      const analyzed = Number(result.titulos_analisados ?? 0);
      const ignored = Number(result.ignorados ?? 0);
      const limit = Number(result.limite ?? 0);
      const remaining = Number(result.pendentes_restantes ?? 0);
      const partial = Boolean(result.truncado) || remaining > 0;
      const hasAnotherBatch =
        partial && limit > 0 && analyzed >= limit && remaining > ignored;
      setNotice(
        `Lote processado: ${analyzed} título(s), ${created} rateio(s) criado(s) e ${centers} centro(s) preenchido(s), sem sobrescrever classificações existentes.${
          ignored > 0
            ? ` ${ignored} lançamento(s) ficaram para revisão por não atenderem aos critérios seguros.`
            : ""
        }${
          hasAnotherBatch
            ? ` Ainda há ${remaining} lançamento(s) para o próximo lote; execute novamente para continuar.`
            : ""
        }`,
      );
      await reload();
    } catch (cause: unknown) {
      setError(cause instanceof Error ? cause.message : "Erro ao aplicar as regras pendentes.");
    } finally {
      setApplying(false);
    }
  };

  if (canFinanceiro !== true) return null;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold text-zinc-100">
            Regras Automáticas de Rateio
          </h1>
          <p className="mt-1 max-w-4xl text-sm text-zinc-400">
            Classifique contas a pagar por motivo, plano e centro de custo na empresa{" "}
            <span className="font-medium text-zinc-200">{empresaNome}</span>. A OS continua
            sendo uma dimensão separada e os rateios explícitos são preservados.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link
            href="/financeiro/cadastros/centro-custo"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm hover:bg-zinc-900"
          >
            Centros de custo
          </Link>
          <Link
            href="/financeiro"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm hover:bg-zinc-900"
          >
            Voltar
          </Link>
          <button
            type="button"
            onClick={openNew}
            disabled={canWrite !== true || !te.empresaId || centros.length === 0}
            className="rounded-md bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-900 hover:bg-white disabled:opacity-50"
          >
            Nova regra
          </button>
        </div>
      </div>

      {!te.empresaId ? (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
          Selecione uma empresa no topo para configurar suas regras.
        </div>
      ) : null}

      {!loading && te.empresaId && centros.length === 0 ? (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
          Esta empresa ainda não possui centros de custo ativos.{" "}
          <Link
            href="/financeiro/cadastros/centro-custo"
            className="font-semibold underline underline-offset-2"
          >
            Cadastre a estrutura
          </Link>{" "}
          antes de criar regras.
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <SummaryCard label="Regras ativas" value={stats.ativas} />
        <SummaryCard label="Motivos automatizados" value={stats.motivos} />
        <SummaryCard label="Regras com divisão" value={stats.divisoes} />
        <SummaryCard
          label="Motivos sem plano"
          value={stats.semPlano}
          tone={stats.semPlano === 0 ? "emerald" : "neutral"}
        />
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div className="flex flex-1 flex-wrap items-end gap-2">
            <label className="block min-w-[260px] flex-1 text-xs text-zinc-400">
              Buscar
              <input
                value={query}
                onChange={(event) => setUrlFilter("q", event.target.value)}
                placeholder="Motivo, plano ou centro de custo…"
                className="mt-1 w-full rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm text-zinc-100"
              />
            </label>
            <label className="block text-xs text-zinc-400">
              Status
              <select
                value={status}
                onChange={(event) => setUrlFilter("status", event.target.value)}
                className="mt-1 rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm text-zinc-100"
              >
                <option value="ativas">Somente ativas</option>
                <option value="todas">Ativas e inativas</option>
              </select>
            </label>
          </div>
          <button
            type="button"
            onClick={() => void applyPending()}
            disabled={canWrite !== true || applying || stats.ativas === 0}
            className="rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-200 hover:bg-emerald-500/15 disabled:opacity-50"
          >
            {applying ? "Aplicando…" : "Aplicar aos pendentes"}
          </button>
        </div>
        <p className="mt-3 text-xs text-zinc-500">
          No histórico, o sistema somente preenche um centro quando existe uma única
          linha de 100%, com o mesmo plano da regra. Divisões percentuais valem para
          novos rateios automáticos.
        </p>
      </div>

      {error ? (
        <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">
          {error}
        </div>
      ) : null}
      {notice ? (
        <div className="rounded-lg border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-200">
          {notice}
        </div>
      ) : null}

      <div className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
        <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
          <div>
            <div className="font-semibold text-zinc-100">Configuração por motivo</div>
            <div className="mt-0.5 text-xs text-zinc-500">
              Uma regra vigente por motivo e empresa.
            </div>
          </div>
          <div className="text-xs text-zinc-500">
            {loading ? "Carregando…" : `${filteredRules.length} regra(s)`}
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="min-w-[980px] w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800 text-left text-xs uppercase tracking-wide text-zinc-500">
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Motivo</th>
                <th className="px-4 py-3">Destinos do rateio</th>
                <th className="px-4 py-3 text-right">Total</th>
                <th className="px-4 py-3">Atualização</th>
                <th className="px-4 py-3 text-right">Ações</th>
              </tr>
            </thead>
            <tbody>
              {!loading && filteredRules.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-10 text-center text-zinc-400">
                    {rules.length === 0
                      ? "Nenhuma regra configurada para esta empresa."
                      : "Nenhuma regra encontrada com os filtros atuais."}
                  </td>
                </tr>
              ) : null}
              {filteredRules.map((rule) => {
                const total = rule.itens.reduce(
                  (sum, item) => sum + item.percentual,
                  0,
                );
                return (
                  <tr key={rule.id} className="border-t border-zinc-900 align-top">
                    <td className="px-4 py-3">
                      <StatusBadge active={rule.ativo} />
                    </td>
                    <td className="px-4 py-3">
                      {rule.motivo_compra_id ? (
                        <>
                          <div className="font-semibold text-zinc-100">
                            {rule.motivo_codigo}
                          </div>
                          <div className="mt-0.5 max-w-[300px] text-xs text-zinc-400">
                            {rule.motivo_nome}
                          </div>
                        </>
                      ) : (
                        <>
                          <div className="font-semibold text-amber-200">
                            REGRA SEM MOTIVO
                          </div>
                          <div className="mt-0.5 max-w-[300px] text-xs text-zinc-500">
                            Configuração antiga; revise antes de usar.
                          </div>
                        </>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="space-y-2">
                        {rule.itens.map((item) => (
                          <div
                            key={item.id ?? `${item.plano_contas_id}:${item.centro_custo_id}`}
                            className="rounded-md border border-zinc-800 bg-black/40 px-3 py-2"
                          >
                            <div className="flex items-start justify-between gap-3">
                              <div className="min-w-0">
                                <div className="truncate text-xs text-zinc-300">
                                  {item.plano_codigo} — {item.plano_nome}
                                </div>
                                <div className="mt-0.5 truncate text-xs font-medium text-zinc-100">
                                  {item.centro_codigo} — {item.centro_nome}
                                </div>
                              </div>
                              <div className="shrink-0 text-right font-mono text-xs text-zinc-200">
                                {formatPercent(item.percentual)}%
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-zinc-100">
                      {formatPercent(total)}%
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-xs text-zinc-400">
                      {formatDateTime(rule.updated_at)}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-2">
                        <button
                          type="button"
                          onClick={() => openEdit(rule)}
                          disabled={canWrite !== true}
                          className="rounded-md border border-zinc-800 px-3 py-1.5 text-xs hover:bg-zinc-900 disabled:opacity-50"
                        >
                          Editar
                        </button>
                        <button
                          type="button"
                          onClick={() => void archiveRule(rule)}
                          disabled={canWrite !== true || archivingId === rule.id}
                          className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-1.5 text-xs text-amber-200 hover:bg-amber-500/15 disabled:opacity-50"
                        >
                          {archivingId === rule.id ? "Arquivando…" : "Arquivar"}
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
        <InfoCard
          title="1. Motivo"
          text="O motivo identifica a natureza da compra e determina o plano de contas. Motivos sem plano ficam pendentes para revisão."
        />
        <InfoCard
          title="2. Plano + centro"
          text="O plano mostra o que foi gasto; o centro mostra onde o gasto ocorreu. A OS permanece vinculada separadamente."
        />
        <InfoCard
          title="3. Percentual"
          text="Use 100% em um único destino ou divida entre áreas. A soma é validada obrigatoriamente em 100%."
        />
      </div>

      {modalOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4">
          <div className="max-h-[92vh] w-full max-w-5xl overflow-y-auto rounded-xl border border-zinc-800 bg-zinc-950 shadow-2xl">
            <div className="sticky top-0 z-10 flex items-start justify-between gap-3 border-b border-zinc-800 bg-zinc-950 px-5 py-4">
              <div>
                <h2 className="text-lg font-semibold text-zinc-100">
                  {formId ? "Editar regra" : "Nova regra"}
                </h2>
                <p className="mt-1 text-xs text-zinc-400">
                  Empresa: {empresaNome}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                className="rounded-md border border-zinc-800 px-3 py-1.5 text-sm hover:bg-zinc-900"
              >
                Fechar
              </button>
            </div>

            <div className="space-y-5 p-5">
              {error ? (
                <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">
                  {error}
                </div>
              ) : null}

              <div className="grid grid-cols-1 gap-3 md:grid-cols-[1fr_auto]">
                <label className="block text-xs text-zinc-400">
                  Motivo de compra
                  <select
                    value={formMotivoId}
                    onChange={(event) => changeMotivo(event.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm text-zinc-100"
                  >
                    <option value="">Selecione um motivo…</option>
                    {motivos
                      .filter(
                        (motivo) =>
                          motivo.plano_contas_id !== null &&
                          planoById.has(motivo.plano_contas_id),
                      )
                      .map((motivo) => (
                        <option key={motivo.id} value={motivo.id}>
                          {motivo.codigo} — {motivo.nome}
                        </option>
                      ))}
                  </select>
                  {stats.semPlano > 0 ? (
                    <span className="mt-1 block text-[11px] text-amber-300">
                      {stats.semPlano} motivo(s) sem plano não aparecem nesta lista.
                    </span>
                  ) : null}
                </label>
                <label className="flex items-end pb-2">
                  <span className="inline-flex items-center gap-2 text-sm text-zinc-200">
                    <input
                      type="checkbox"
                      checked={formAtivo}
                      onChange={(event) => setFormAtivo(event.target.checked)}
                      className="accent-zinc-100"
                    />
                    Regra ativa
                  </span>
                </label>
              </div>

              <div>
                <div className="flex flex-wrap items-end justify-between gap-3">
                  <div>
                    <h3 className="font-semibold text-zinc-100">Destinos</h3>
                    <p className="mt-0.5 text-xs text-zinc-500">
                      Selecione uma conta analítica e um centro ativo em cada linha.
                    </p>
                  </div>
                  <div
                    className={`rounded-md border px-3 py-2 text-sm font-semibold ${
                      Math.abs(totalPercentual - 100) <= 0.0001
                        ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-200"
                        : "border-amber-500/30 bg-amber-500/10 text-amber-200"
                    }`}
                  >
                    Soma: {formatPercent(totalPercentual)}%
                  </div>
                </div>

                <div className="mt-3 space-y-3">
                  {formItems.map((item, index) => (
                    <div
                      key={item.key}
                      className="rounded-lg border border-zinc-800 bg-black/30 p-3"
                    >
                      <div className="grid grid-cols-1 gap-3 lg:grid-cols-[1.35fr_1fr_150px_auto]">
                        <div className="block text-xs text-zinc-400">
                          Plano de contas
                          <div className="mt-1 min-h-[38px] w-full rounded-md border border-zinc-800 bg-zinc-900/60 px-3 py-2 text-sm text-zinc-300">
                            {planoById.get(item.plano_contas_id)
                              ? `${planoById.get(item.plano_contas_id)?.codigo} — ${
                                  planoById.get(item.plano_contas_id)?.nome
                                }`
                              : "Selecione o motivo para definir o plano"}
                          </div>
                        </div>

                        <label className="block text-xs text-zinc-400">
                          Centro de custo
                          <select
                            value={item.centro_custo_id}
                            onChange={(event) =>
                              updateItem(item.key, "centro_custo_id", event.target.value)
                            }
                            className="mt-1 w-full rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm text-zinc-100"
                          >
                            <option value="">Selecione…</option>
                            {centros.map((centro) => (
                              <option key={centro.id} value={centro.id}>
                                {centro.codigo} — {centro.nome}
                              </option>
                            ))}
                          </select>
                        </label>

                        <label className="block text-xs text-zinc-400">
                          Percentual
                          <div className="relative mt-1">
                            <input
                              value={item.percentual}
                              onChange={(event) =>
                                updateItem(item.key, "percentual", event.target.value)
                              }
                              inputMode="decimal"
                              aria-label={`Percentual do destino ${index + 1}`}
                              className="w-full rounded-md border border-zinc-800 bg-black px-3 py-2 pr-8 text-right font-mono text-sm text-zinc-100"
                            />
                            <span className="pointer-events-none absolute right-3 top-2 text-sm text-zinc-500">
                              %
                            </span>
                          </div>
                        </label>

                        <div className="flex items-end">
                          <button
                            type="button"
                            onClick={() => removeItem(item.key)}
                            disabled={formItems.length === 1}
                            className="w-full rounded-md border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200 hover:bg-red-500/15 disabled:opacity-30 lg:w-auto"
                          >
                            Remover
                          </button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                <button
                  type="button"
                  onClick={addItem}
                  className="mt-3 rounded-md border border-zinc-700 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
                >
                  + Adicionar destino
                </button>
              </div>

              <div className="rounded-lg border border-zinc-800 bg-black/30 p-3 text-xs text-zinc-400">
                Alterar uma regra afeta somente novos rateios automáticos. Rateios manuais,
                documentos fiscais e lançamentos históricos já classificados permanecem intactos.
              </div>
            </div>

            <div className="sticky bottom-0 flex items-center justify-end gap-2 border-t border-zinc-800 bg-zinc-950 px-5 py-4">
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                className="rounded-md border border-zinc-800 px-3 py-2 text-sm hover:bg-zinc-900"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void saveRule()}
                disabled={saving}
                className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 hover:bg-white disabled:opacity-50"
              >
                {saving ? "Salvando…" : "Salvar regra"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function SummaryCard({
  label,
  value,
  tone = "neutral",
}: {
  label: string;
  value: string | number;
  tone?: "neutral" | "emerald";
}) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-500">{label}</div>
      <div
        className={`mt-1 text-xl font-semibold ${
          tone === "emerald" ? "text-emerald-300" : "text-zinc-100"
        }`}
      >
        {value}
      </div>
    </div>
  );
}

function StatusBadge({ active }: { active: boolean }) {
  return (
    <span
      className={`inline-flex rounded-full border px-2 py-0.5 text-xs font-medium ${
        active
          ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-200"
          : "border-zinc-700 bg-zinc-900 text-zinc-300"
      }`}
    >
      {active ? "ATIVA" : "INATIVA"}
    </span>
  );
}

function InfoCard({ title, text }: { title: string; text: string }) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-sm font-semibold text-zinc-100">{title}</div>
      <p className="mt-1 text-xs leading-5 text-zinc-400">{text}</p>
    </div>
  );
}
