"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { syncHhToApontamentos } from "@/lib/hh/syncHhToApontamentos";
import type { SupabaseClient } from "@supabase/supabase-js";

function getSbErrorMessage(err: unknown): string {
  if (!err || typeof err !== "object") return "";
  const e = err as Record<string, unknown>;
  return typeof e.message === "string" ? e.message : "";
}

// Helper para resolver o mapping correto de hh_tipo_id
async function resolveHhTipoMappingId(
  supabase: SupabaseClient,
  tenantId: string,
  percentual: 0 | 50 | 100
): Promise<number> {
  const codigoTipo = percentual === 0 ? "NORMAL" : percentual === 50 ? "EXTRA_50" : "EXTRA_100";
  // 1. Buscar tipo_horas.id
  const { data: tipoHoras, error: tipoHorasErr } = await supabase
    .from("tipos_horas")
    .select("id")
    .eq("codigo", codigoTipo)
    .eq("ativo", true)
    .maybeSingle<{ id: number }>();
  if (tipoHorasErr || !tipoHoras?.id) throw new Error(`Não foi possível resolver tipo_horas para ${codigoTipo}`);
  const tipoHorasId = tipoHoras.id;

  // 2. Buscar mapping em hh_tipos_mapping
  let mapping: { id?: number } | null = null;
  let mappingErr: unknown = null;
  try {
    const { data, error } = await supabase
      .from("hh_tipos_mapping")
      .select("id")
      .eq("tipo_id", tipoHorasId)
      .eq("tenant_id", tenantId)
      .maybeSingle<{ id: number }>();
    mapping = data;
    mappingErr = error;
  } catch (e: unknown) {
    mapping = null;
    mappingErr = e;
  }

  // Fallback para tipo_hora_id se coluna não existir
  if (mappingErr && /column.*tipo_id.*does not exist/i.test(getSbErrorMessage(mappingErr))) {
    const { data, error } = await supabase
      .from("hh_tipos_mapping")
      .select("id")
      .eq("tipo_hora_id", tipoHorasId)
      .eq("tenant_id", tenantId)
      .maybeSingle<{ id: number }>();
    mapping = data;
    mappingErr = error;
    if (mapping && mapping.id) return mapping.id;

    // upsert com tipo_hora_id
    const { data: inserted, error: insertErr } = await supabase
      .from("hh_tipos_mapping")
      .upsert(
        { tenant_id: tenantId, tipo_hora_id: tipoHorasId, ativo: true },
        { onConflict: "tenant_id,tipo_hora_id" }
      )
      .select("id")
      .single<{ id: number }>();
    if (insertErr || !inserted?.id) throw insertErr ?? new Error("Falha ao criar mapping (tipo_hora_id)");
    return inserted.id;
  }

  if (mapping && mapping.id) return mapping.id;

  // 3. Se não existir, upsert idempotente
  const { data: inserted, error: insertErr } = await supabase
    .from("hh_tipos_mapping")
    .upsert(
      { tenant_id: tenantId, tipo_id: tipoHorasId, ativo: true },
      { onConflict: "tenant_id,tipo_id" }
    )
    .select("id")
    .single<{ id: number }>();
  if (insertErr || !inserted?.id) throw insertErr ?? new Error("Falha ao criar mapping");
  return inserted.id;
}

type Option = { value: string; label: string };

type Props = {
  osId: number;
  clienteId: number;
  tenantId: string | null;
  empresaId: string | null;
  osStatus: "aberta" | "em_andamento" | "concluida" | "cancelada" | null;
  enabled: boolean;
  canWrite: boolean;
  onCreated?: () => void | Promise<void>;
};

function todayISO() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function parseHHMM(value: string): number | null {
  const raw = String(value ?? "").trim();
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(raw);
  if (!m) return null;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  return hh * 60 + mm;
}

function getPercentualFromDate(dateISO: string): 0 | 50 | 100 {
  const raw = String(dateISO ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return 0;
  const d = new Date(raw + "T00:00:00");
  const dow = d.getDay();
  if (dow === 0) return 100;
  if (dow === 6) return 50;
  return 0;
}

function formatSupabaseError(err: unknown, fallback: string): string {
  if (!err || typeof err !== "object") return fallback;
  const e = err as { message?: string; details?: string; hint?: string };
  const parts = [e.message ?? fallback, e.details, e.hint].filter(Boolean);
  return parts.join(" | ");
}

function isMissingRelation(error: unknown, tableName: string): boolean {
  const msg =
    typeof error === "object" && error && "message" in error
      ? String((error as { message?: unknown }).message ?? "").toLowerCase()
      : "";
  const code =
    typeof error === "object" && error && "code" in error ? String((error as { code?: unknown }).code ?? "") : "";
  return code === "42P01" || msg.includes(`relation \"${tableName}\"`) || msg.includes(tableName.toLowerCase());
}

function isMissingColumn(error: unknown, columnName: string): boolean {
  const msg =
    typeof error === "object" && error && "message" in error
      ? String((error as { message?: unknown }).message ?? "").toLowerCase()
      : "";
  return msg.includes(`column \"${columnName.toLowerCase()}\"`) && msg.includes("does not exist");
}

export default function NovoLancamentoHHCard({
  osId,
  clienteId,
  tenantId,
  empresaId,
  osStatus,
  enabled,
  canWrite,
  onCreated,
}: Props) {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const canShow = enabled && osStatus === "em_andamento";

  const [servicos, setServicos] = useState<Option[]>([]);
  const [servicosLoading, setServicosLoading] = useState(false);
  const [servicosError, setServicosError] = useState<string | null>(null);

  const [colaboradores, setColaboradores] = useState<Option[]>([]);
  const [colaboradoresLoading, setColaboradoresLoading] = useState(false);
  const [colaboradoresError, setColaboradoresError] = useState<string | null>(null);

  const [form, setForm] = useState({
    servicoId: "",
    colaboradorId: "",
    data: todayISO(),
    entrada1: "07:30",
    saida1: "12:00",
    entrada2: "13:00",
    saida2: "17:00",
    observacao: "",
  });

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const didInitFocusRef = useRef(false);
  const serviceReqIdRef = useRef(0);
  const colabReqIdRef = useRef(0);
  const serviceSelectRef = useRef<HTMLSelectElement | null>(null);

  useEffect(() => {
    if (!canShow) return;
    if (didInitFocusRef.current) return;
    didInitFocusRef.current = true;
    setTimeout(() => serviceSelectRef.current?.focus(), 0);
  }, [canShow]);

  useEffect(() => {
    if (!canShow) return;
    if (!tenantId || !empresaId || !clienteId) return;

    const reqId = ++serviceReqIdRef.current;
    setServicosLoading(true);
    setServicosError(null);

    (async () => {
      try {
        const base = supabase
          .from("cliente_hh_servicos")
          .select("id,nome")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .order("nome", { ascending: true });

        const q = empresaId ? applyTenantEmpresa(base, tenantId, empresaId) : applyTenant(base, tenantId);
        const { data, error } = await q;
        if (reqId !== serviceReqIdRef.current) return;
        if (error) throw error;

        const rows = (data ?? []) as Array<{ id: string | number; nome?: string | null }>;
        const options: Option[] = rows.map((r) => ({
          value: String(r.id),
          label: String(r.nome ?? `Serviço ${r.id}`),
        }));

        setServicos(options);
        setServicosLoading(false);

        if (options.length === 1) {
          setForm((prev) => ({ ...prev, servicoId: options[0].value }));
        }
      } catch (e: unknown) {
        if (reqId !== serviceReqIdRef.current) return;
        setServicos([]);
        setServicosLoading(false);
        setServicosError(formatSupabaseError(e, "Erro ao carregar serviços HH."));
      }
    })();
  }, [canShow, clienteId, empresaId, supabase, tenantId]);

  useEffect(() => {
    if (!canShow) return;
    if (!tenantId || !empresaId || !clienteId) return;

    const servicoId = String(form.servicoId ?? "").trim();
    setColaboradores([]);
    setColaboradoresError(null);
    setForm((prev) => (prev.colaboradorId ? { ...prev, colaboradorId: "" } : prev));

    if (!servicoId) return;
    if (!/^[0-9]+$/.test(servicoId)) {
      setColaboradoresError("Serviço HH inválido.");
      return;
    }

    const reqId = ++colabReqIdRef.current;
    setColaboradoresLoading(true);

    (async () => {
      try {
        const base1 = supabase
          .from("colaborador_cliente_funcao")
          .select("colaborador_id,colaboradores:colaborador_id(nome)")
          .eq("cliente_id", clienteId)
          .eq("hh_servico_id", servicoId)
          .eq("ativo", true);

        const q1 = empresaId ? applyTenantEmpresa(base1, tenantId, empresaId) : applyTenant(base1, tenantId);
        let { data, error } = await q1;

        if (error && (isMissingRelation(error, "colaborador_cliente_funcao") || isMissingColumn(error, "hh_servico_id"))) {
          const base2 = supabase
            .from("colaborador_funcao_hh")
            .select("colaborador_id,colaboradores:colaborador_id(nome)")
            .eq("cliente_id", clienteId)
            .eq("servico_hh_id", servicoId)
            .eq("ativo", true);
          const q2 = empresaId ? applyTenantEmpresa(base2, tenantId, empresaId) : applyTenant(base2, tenantId);
          const retry = await q2;
          data = retry.data;
          error = retry.error;
        }

        if (reqId !== colabReqIdRef.current) return;
        if (error) throw error;

        const rows = (data ?? []) as Array<{
          colaborador_id?: string | null;
          colaboradores?: { nome?: string | null } | Array<{ nome?: string | null }> | null;
        }>;

        const options: Option[] = rows
          .map((r) => {
            const id = typeof r.colaborador_id === "string" ? r.colaborador_id : "";
            const join = r.colaboradores;
            const nome =
              join && Array.isArray(join) ? (join[0]?.nome ?? null) : join && typeof join === "object" ? join.nome ?? null : null;
            if (!id) return null;
            return { value: id, label: String(nome ?? id) } as Option;
          })
          .filter((v): v is Option => Boolean(v));

        options.sort((a, b) => a.label.localeCompare(b.label, "pt-BR", { sensitivity: "base" }));

        setColaboradores(options);
        setColaboradoresLoading(false);

        if (options.length === 1) {
          setForm((prev) => ({ ...prev, colaboradorId: options[0].value }));
        }
      } catch (e: unknown) {
        if (reqId !== colabReqIdRef.current) return;
        setColaboradores([]);
        setColaboradoresLoading(false);
        setColaboradoresError(formatSupabaseError(e, "Erro ao carregar colaboradores."));
      }
    })();
  }, [canShow, clienteId, empresaId, form.servicoId, supabase, tenantId]);

  async function submit() {
    if (busy) return;
    setErr(null);
    setOk(null);

    if (!canShow) return;
    if (!canWrite) {
      setErr("Sem permissão para lançar HH.");
      return;
    }
    if (!tenantId || !empresaId) {
      setErr("Tenant/empresa não carregados.");
      return;
    }
    if (!clienteId) {
      setErr("Cliente não identificado na OS.");
      return;
    }

    const servicoId = String(form.servicoId ?? "").trim();
    const colaboradorId = String(form.colaboradorId ?? "").trim();
    const data = String(form.data ?? "").trim();
    const entrada1Str = String(form.entrada1 ?? "").trim();
    const saida1Str = String(form.saida1 ?? "").trim();
    const entrada2Str = String(form.entrada2 ?? "").trim();
    const saida2Str = String(form.saida2 ?? "").trim();

    if (!servicoId) {
      setErr("Selecione o Serviço HH.");
      return;
    }
    if (!colaboradorId) {
      setErr("Selecione o Colaborador.");
      return;
    }
    if (!data || !/^\d{4}-\d{2}-\d{2}$/.test(data)) {
      setErr("Informe uma data válida.");
      return;
    }
    if (!entrada1Str || !saida1Str || !entrada2Str || !saida2Str) {
      setErr("Informe todos os horários (Entrada 1/Saída 1/Entrada 2/Saída 2).");
      return;
    }

    const e1 = parseHHMM(entrada1Str);
    const s1 = parseHHMM(saida1Str);
    const e2 = parseHHMM(entrada2Str);
    const s2 = parseHHMM(saida2Str);

    if (e1 === null || s1 === null || e2 === null || s2 === null) {
      setErr("Horários inválidos. Use o formato HH:MM.");
      return;
    }
    if (s1 <= e1) {
      setErr("Saída 1 deve ser maior que Entrada 1.");
      return;
    }
    if (s2 <= e2) {
      setErr("Saída 2 deve ser maior que Entrada 2.");
      return;
    }
    if (s1 > e2) {
      setErr("Saída 1 deve ser menor ou igual a Entrada 2 (sem sobreposição).");
      return;
    }

    setBusy(true);
    try {
      const percentual = getPercentualFromDate(data) as 0 | 50 | 100;
      // Resolve mapping correto para hh_tipo_id
      const hhTipoMappingId = await resolveHhTipoMappingId(supabase, tenantId, percentual);
      console.warn("[NovoLancamentoHHCard] mappingId/hh_tipo_id:", hhTipoMappingId, "servicoId:", servicoId);

      const { data: svcData, error: svcErr } = await applyTenantEmpresa(
        supabase
          .from("cliente_hh_servicos")
          .select("preco_base,preco_50,preco_100")
          .eq("id", servicoId)
          .maybeSingle(),
        tenantId,
        empresaId
      );
      if (svcErr) throw svcErr;

      const svc = (svcData ?? {}) as Record<string, unknown>;
      const precoBase = Number(svc.preco_base ?? 0);
      const preco50 = Number(svc.preco_50 ?? 0);
      const preco100 = Number(svc.preco_100 ?? 0);
      const valorHoraAplicado = percentual === 0 ? precoBase : percentual === 50 ? preco50 : preco100;

      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      const basePayload: Record<string, unknown> = {
        tenant_id: tenantId,
        empresa_id: empresaId,
        os_id: osId,
        colaborador_id: colaboradorId,
        hh_tipo_id: hhTipoMappingId,
        data,
        entrada_1: entrada1Str,
        saida_1: saida1Str,
        entrada_2: entrada2Str,
        saida_2: saida2Str,
        hora_entrada: entrada1Str,
        hora_saida: saida2Str,
        percentual_aplicado: percentual,
        valor_hora: valorHoraAplicado,
        observacao: String(form.observacao ?? "").trim() || null,
        criado_por: userEmail,
      };
      // Estratégia de fallback de colunas
      let payloadFinal: Record<string, unknown> = { ...basePayload, hh_especialidade_id: String(servicoId) };
      let insertError: unknown | null = null;
      try {
        let { error } = await supabase.from("hh_lancamentos").insert(payloadFinal);
        if (error) {
          if (isMissingColumn(error, "hh_especialidade_id")) {
            payloadFinal = { ...basePayload, hh_servico_id: String(servicoId) };
            ({ error } = await supabase.from("hh_lancamentos").insert(payloadFinal));
            if (error) {
              if (isMissingColumn(error, "empresa_id")) {
                const { empresa_id: _empresa_id, ...payloadNoEmpresa } = payloadFinal;
                ({ error } = await supabase.from("hh_lancamentos").insert(payloadNoEmpresa));
                if (error) throw error;
              } else {
                throw error;
              }
            }
          } else if (isMissingColumn(error, "empresa_id")) {
            const { empresa_id: _empresa_id, ...payloadNoEmpresa } = payloadFinal;
            ({ error } = await supabase.from("hh_lancamentos").insert(payloadNoEmpresa));
            if (error) throw error;
          } else {
            throw error;
          }
        }
      } catch (e) {
        insertError = e;
      }
      if (insertError) throw insertError;
      setOk("Lançamento HH salvo com sucesso!");

      try {
        await syncHhToApontamentos({
          supabase,
          tenantId,
          empresaId,
          osId,
          colaboradorId,
          dataISO: data,
          periodos: [
            { entrada: entrada1Str, saida: saida1Str },
            { entrada: entrada2Str, saida: saida2Str },
          ],
          descricao: String(form.observacao ?? "").trim() || "HH lançado na OS",
        });
      } catch (syncErr: unknown) {
        console.error("[HH] Falha ao sincronizar apontamentos_horas (gerado_por_hh)", syncErr);
        setErr("Lançamento HH salvo, mas falhou ao sincronizar apontamentos. Tente novamente ou contate o admin.");
      }

      if (onCreated) await onCreated();

      setForm((prev) => ({
        ...prev,
        colaboradorId: "",
        data: todayISO(),
        entrada1: "07:30",
        saida1: "12:00",
        entrada2: "13:00",
        saida2: "17:00",
        observacao: "",
      }));
    } catch (e: unknown) {
      setErr(formatSupabaseError(e, "Erro ao salvar lançamento HH."));
    } finally {
      setBusy(false);
    }
  }

  if (!canShow) return null;

  return (
    <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-4 space-y-3">
      <div>
        <h3 className="text-lg font-semibold">Novo lançamento HH</h3>
        <p className="text-sm text-zinc-400 mt-1">Preencha os dados e clique em Lançar para registrar as horas.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label className="space-y-1">
          <span className="text-xs text-zinc-400">Serviço HH *</span>
          <select
            ref={serviceSelectRef}
            value={form.servicoId}
            onChange={(e) => setForm((prev) => ({ ...prev, servicoId: e.target.value }))}
            disabled={busy || servicosLoading}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
          >
            <option value="">{servicosLoading ? "Carregando..." : "Selecione..."}</option>
            {servicos.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
          {servicosError && <div className="text-xs text-red-400">{servicosError}</div>}
          {!servicosLoading && !servicosError && servicos.length === 0 && (
            <div className="text-xs text-amber-300">Nenhum serviço HH ativo para este cliente.</div>
          )}
        </label>

        <label className="space-y-1">
          <span className="text-xs text-zinc-400">Colaborador *</span>
          <select
            value={form.colaboradorId}
            onChange={(e) => setForm((prev) => ({ ...prev, colaboradorId: e.target.value }))}
            disabled={busy || colaboradoresLoading || !form.servicoId}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
          >
            <option value="">
              {!form.servicoId ? "Selecione um serviço primeiro..." : colaboradoresLoading ? "Carregando..." : "Selecione..."}
            </option>
            {colaboradores.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
          {colaboradoresError && <div className="text-xs text-red-400">{colaboradoresError}</div>}
          {!colaboradoresLoading && !colaboradoresError && form.servicoId && colaboradores.length === 0 && (
            <div className="text-xs text-amber-300">Nenhum colaborador vinculado a este serviço.</div>
          )}
        </label>

        <label className="space-y-1">
          <span className="text-xs text-zinc-400">Data *</span>
          <input
            type="date"
            value={form.data}
            onChange={(e) => setForm((prev) => ({ ...prev, data: e.target.value }))}
            disabled={busy}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
          />
          <div className="text-[11px] text-zinc-500">
            {(() => {
              const p = getPercentualFromDate(form.data);
              if (p === 50) return "Sábado (50%)";
              if (p === 100) return "Domingo (100%)";
              return "Dias de semana (0%)";
            })()}
          </div>
        </label>

        <label className="space-y-1 md:col-span-2">
          <span className="text-xs text-zinc-400">Observação</span>
          <textarea
            value={form.observacao}
            onChange={(e) => setForm((prev) => ({ ...prev, observacao: e.target.value }))}
            disabled={busy}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm min-h-[64px]"
            placeholder="Opcional..."
          />
        </label>

        <label className="space-y-1">
          <span className="text-xs text-zinc-400">Entrada 1 *</span>
          <input
            type="time"
            value={form.entrada1}
            onChange={(e) => setForm((prev) => ({ ...prev, entrada1: e.target.value }))}
            disabled={busy}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
          />
        </label>

        <label className="space-y-1">
          <span className="text-xs text-zinc-400">Saída 1 *</span>
          <input
            type="time"
            value={form.saida1}
            onChange={(e) => setForm((prev) => ({ ...prev, saida1: e.target.value }))}
            disabled={busy}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
          />
        </label>

        <label className="space-y-1">
          <span className="text-xs text-zinc-400">Entrada 2 *</span>
          <input
            type="time"
            value={form.entrada2}
            onChange={(e) => setForm((prev) => ({ ...prev, entrada2: e.target.value }))}
            disabled={busy}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
          />
        </label>

        <label className="space-y-1">
          <span className="text-xs text-zinc-400">Saída 2 *</span>
          <input
            type="time"
            value={form.saida2}
            onChange={(e) => setForm((prev) => ({ ...prev, saida2: e.target.value }))}
            disabled={busy}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
          />
        </label>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      <div className="flex items-center justify-end">
        <button
          type="button"
          onClick={() => void submit()}
          disabled={busy || servicosLoading || colaboradoresLoading || !form.servicoId || !form.colaboradorId}
          className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
        >
          {busy ? "Lançando..." : "Lançar"}
        </button>
      </div>
    </div>
  );
}

