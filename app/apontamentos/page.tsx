"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";

type Colaborador = { id: string; nome: string; ativo: boolean };
type TipoHora = { id: string; codigo: string; descricao: string; fator: number; ativo: boolean };

type OSRow = {
  id: number;
  numero_os: string | null;
  cliente_nome: string | null;
  descricao_servico?: string | null;
  status: string | null;
};

type ApontamentoRow = {
  id: string;
  os_id: number;
  colaborador_id: string;
  data: string; // yyyy-mm-dd
  horas: number | null;
  horas_trabalhadas?: number | null;
  tipo_hora_id: string | null;
  fator_aplicado?: number | null;
  hh_especialidade_id?: string | null;
  tenant_id?: string;
  // Horarios (modo novo). Alguns bancos usam entrada_1/saida_1; outros hora_entrada_1/hora_saida_1.
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  descricao: string | null;
  status: string;
  criado_em: string;
};

const feriadosCache = new Map<number, Set<string>>();
const feriadosPending = new Map<number, Promise<Set<string>>>();

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

function describeSupabaseError(err: unknown): string {
  if (!err) return "(sem detalhes)";
  if (err instanceof Error) return err.message || "(erro sem mensagem)";
  if (typeof err === "string") return err;
  if (typeof err !== "object") return String(err);

  const anyErr = err as {
    message?: unknown;
    details?: unknown;
    hint?: unknown;
    code?: unknown;
    status?: unknown;
  };

  const parts = [
    anyErr.message,
    anyErr.details,
    anyErr.hint,
    anyErr.code ? `code=${String(anyErr.code)}` : null,
    anyErr.status ? `status=${String(anyErr.status)}` : null,
  ]
    .filter((p) => typeof p === "string" ? p.trim() !== "" : p != null)
    .map((p) => String(p));

  if (parts.length) return parts.join(" | ");
  // Next dev overlay costuma serializar objetos/Errors como {}.
  try {
    return JSON.stringify(err);
  } catch {
    return "(erro não serializável)";
  }
}

function todayISO() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function toNumberBR(v: string): number | null {
  const s = v.trim();
  if (!s) return null;
  const noCurrency = s.replace(/R\$\s?/gi, "").replace(/\s/g, "");
  const hasDot = noCurrency.includes(".");
  const hasComma = noCurrency.includes(",");
  let normalized = noCurrency;

  if (hasDot && hasComma) {
    const lastDot = noCurrency.lastIndexOf(".");
    const lastComma = noCurrency.lastIndexOf(",");
    if (lastComma > lastDot) {
      normalized = noCurrency.replace(/\./g, "").replace(",", ".");
    } else {
      normalized = noCurrency.replace(/,/g, "");
    }
  } else if (hasComma) {
    normalized = noCurrency.replace(",", ".");
  } else if (hasDot) {
    const dotCount = (noCurrency.match(/\./g) || []).length;
    normalized = dotCount > 1 ? noCurrency.replace(/\./g, "") : noCurrency;
  }

  const n = Number(normalized);
  return Number.isFinite(n) ? n : null;
}

function isWeekend(dateISO: string): "SAT" | "SUN" | null {
  const d = new Date(`${dateISO}T00:00:00`);
  const day = d.getDay();
  if (day === 6) return "SAT";
  if (day === 0) return "SUN";
  return null;
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

function isTimeRangeValid(e1: number, s1: number, e2: number, s2: number): boolean {
  if (!(s1 > e1)) return false;
  if (!(s2 > e2)) return false;
  if (s1 > e2) return false;
  return true;
}

function isMissingColumnError(err: unknown): boolean {
  const message =
    err && typeof err === "object" && "message" in err ? String((err as { message?: unknown }).message ?? "") : "";
  return (
    /column\s+"?\w+"?\s+does not exist/i.test(message) ||
    /could not find the '\w+' column/i.test(message)
  );
}

function normalizeApontamentoRow(raw: unknown): ApontamentoRow {
  const r = raw as Record<string, unknown>;
  const entrada_1 = (r.entrada_1 ?? r.hora_entrada_1 ?? null) as string | null;
  const saida_1 = (r.saida_1 ?? r.hora_saida_1 ?? null) as string | null;
  const entrada_2 = (r.entrada_2 ?? r.hora_entrada_2 ?? null) as string | null;
  const saida_2 = (r.saida_2 ?? r.hora_saida_2 ?? null) as string | null;
  return {
    ...(r as unknown as ApontamentoRow),
    entrada_1,
    saida_1,
    entrada_2,
    saida_2,
  };
}

async function getNationalHolidays(year: number): Promise<Set<string>> {
  if (feriadosCache.has(year)) return feriadosCache.get(year)!;
  if (feriadosPending.has(year)) return feriadosPending.get(year)!;

  const promise = (async () => {
    try {
      const res = await fetch(`https://brasilapi.com.br/api/feriados/v1/${year}`);
      if (!res.ok) throw new Error(`BrasilAPI status ${res.status}`);
      const data = (await res.json()) as Array<{ date: string }>;
      const set = new Set<string>((data ?? []).map((f) => f.date));
      feriadosCache.set(year, set);
      return set;
    } catch {
      return new Set<string>();
    } finally {
      feriadosPending.delete(year);
    }
  })();

  feriadosPending.set(year, promise);
  return promise;
}

async function isNationalHoliday(dateISO: string): Promise<boolean> {
  const year = Number(dateISO.slice(0, 4));
  if (!Number.isFinite(year)) return false;
  const set = await getNationalHolidays(year);
  return set.has(dateISO);
}

type HourPolicy =
  | { mode: "SINGLE"; items: Array<{ tipoCodigo: string; horas: number }> }
  | { mode: "SPLIT"; items: Array<{ tipoCodigo: string; horas: number }> };

async function computeHourPolicy(dateISO: string, horas: number): Promise<HourPolicy> {
  const weekend = isWeekend(dateISO);
  const holiday = await isNationalHoliday(dateISO);

  if (weekend === "SUN" || holiday) {
    return { mode: "SINGLE", items: [{ tipoCodigo: "EXTRA_100", horas }] };
  }

  if (weekend === "SAT") {
    return { mode: "SINGLE", items: [{ tipoCodigo: "EXTRA_50", horas }] };
  }

  if (horas > 9) {
    return {
      mode: "SPLIT",
      items: [
        { tipoCodigo: "NORMAL", horas: 9 },
        { tipoCodigo: "EXTRA_50", horas: Number((horas - 9).toFixed(2)) },
      ],
    };
  }

  return { mode: "SINGLE", items: [{ tipoCodigo: "NORMAL", horas }] };
}

export default function ApontamentosPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId: ctxEmpresaId } = useTenantEmpresa();
  const searchParams = useSearchParams();

  const fixedTenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
  const forcedEmpresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
  const effectiveTenantId = useMemo(() => tenantId ?? fixedTenantId, [tenantId]);
  const effectiveEmpresaId = useMemo(() => forcedEmpresaId ?? ctxEmpresaId, [ctxEmpresaId]);
  const effectiveLoading = !effectiveTenantId || !effectiveEmpresaId;

  const ensureContext = useCallback(async () => {
    if (!effectiveTenantId || !effectiveEmpresaId) return;
    try {
      await supabase.rpc("set_current_tenant", { p_tenant_id: effectiveTenantId });
      await supabase.rpc("set_current_empresa", { p_empresa_id: effectiveEmpresaId });
    } catch {
      // best-effort
    }
  }, [effectiveEmpresaId, effectiveTenantId, supabase]);
  
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  // filtros
  const [filtroOsId, setFiltroOsId] = useState<string>(""); // string p/ select
  const [filtroColabId, setFiltroColabId] = useState<string>("");

  // combos
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [tiposHoras, setTiposHoras] = useState<TipoHora[]>([]);
  const [osList, setOsList] = useState<OSRow[]>([]);
  const [combosLoaded, setCombosLoaded] = useState(false);

  // formulario novo apontamento
  const [osNumero, setOsNumero] = useState<string>("");
  const [osDbId, setOsDbId] = useState<number | null>(null);
  const [osDescricao, setOsDescricao] = useState<string>("");
  const [osDescLoading, setOsDescLoading] = useState(false);
  const [osDescError, setOsDescError] = useState<string | null>(null);
  const [osCliente, setOsCliente] = useState<string>("");
  const [osStatus, setOsStatus] = useState<string>("");
  const [showOsModal, setShowOsModal] = useState(false);
  const [osSearch, setOsSearch] = useState("");
  const [osSearchLoading, setOsSearchLoading] = useState(false);
  const [osSearchError, setOsSearchError] = useState<string | null>(null);
  const [osSearchResults, setOsSearchResults] = useState<OSRow[]>([]);
  const [colabId, setColabId] = useState<string>("");
  const [colabInput, setColabInput] = useState<string>("");
  const [data, setData] = useState<string>(todayISO());
  const [horasText, setHorasText] = useState<string>("");
  const [tipoHoraId, setTipoHoraId] = useState<string>(""); // empty = null
  const [tipoHoraTouched, setTipoHoraTouched] = useState(false);
  const [descricao, setDescricao] = useState<string>("");
  const [tipoSugerido, setTipoSugerido] = useState<string>("");
  const [tipoSugeridoLoading, setTipoSugeridoLoading] = useState(false);
  const osDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const osSearchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const horasInputRef = useRef<HTMLInputElement | null>(null);

  const [editing, setEditing] = useState<ApontamentoRow | null>(null);
  const [editHasTimes, setEditHasTimes] = useState(false);
  const [editData, setEditData] = useState<string>(todayISO());
  const [editHorasText, setEditHorasText] = useState<string>("");
  const [editTipoHoraId, setEditTipoHoraId] = useState<string>("");
  const [editDescricao, setEditDescricao] = useState<string>("");
  const [editHoraE1, setEditHoraE1] = useState("07:30");
  const [editHoraS1, setEditHoraS1] = useState("12:00");
  const [editHoraE2, setEditHoraE2] = useState("13:00");
  const [editHoraS2, setEditHoraS2] = useState("17:00");

  const [apontamentos, setApontamentos] = useState<ApontamentoRow[]>([]);

  const carregarCombos = useCallback(async () => {
    if (effectiveLoading) return;
    await ensureContext();
    const [{ data: c, error: e1 }, { data: th, error: e2 }, { data: os, error: e3 }] =
      await Promise.all([
        applyTenantEmpresa(
          supabase.from("colaboradores").select("id,nome,ativo").eq("ativo", true).order("nome"),
          effectiveTenantId,
          effectiveEmpresaId
        ),
        applyTenant(
          supabase.from("tipos_horas").select("id,codigo,descricao,fator,ativo").eq("ativo", true).order("codigo"),
          effectiveTenantId
        ),
        applyTenantEmpresa(
          supabase
            .from("ordens_servico")
            .select("id,numero_os,cliente_nome,descricao_servico,status")
            .in("status", ["aberta", "em_andamento"])
            .order("id", { ascending: false })
            .limit(200),
          effectiveTenantId,
          effectiveEmpresaId
        ),
      ]);

    if (e1) throw e1;
    if (e2) throw e2;
    if (e3) throw e3;

    setColaboradores((c ?? []) as Colaborador[]);
    setTiposHoras((th ?? []) as TipoHora[]);
    setOsList((os ?? []) as OSRow[]);
    setCombosLoaded(true);
  }, [effectiveEmpresaId, effectiveTenantId, supabase, effectiveLoading, ensureContext]);

  const carregarApontamentos = useCallback(async () => {
    setLoading(true);
    setMsg(null);
    try {
      if (effectiveLoading) return;
      await ensureContext();
      
      const build = (selectStr: string) => {
        const q = applyTenantEmpresa(
          supabase
            .from("apontamentos_horas")
            .select(selectStr)
            .order("data", { ascending: false })
            .order("criado_em", { ascending: false }),
          effectiveTenantId,
          effectiveEmpresaId
        );
        if (osDbId) q.eq("os_id", osDbId);
        else if (filtroOsId) q.eq("os_id", Number(filtroOsId));
        if (filtroColabId) q.eq("colaborador_id", filtroColabId);
        return q;
      };

      // A tabela apontamentos_horas possui: horas, hora_entrada_1, hora_saida_1, hora_entrada_2, hora_saida_2
      const baseFields =
        "id,os_id,colaborador_id,data,horas,tipo_hora_id,fator_aplicado,descricao,status,criado_em,tenant_id,hh_especialidade_id";
      
      const timeFields = "hora_entrada_1,hora_saida_1,hora_entrada_2,hora_saida_2";
      const timeFieldsAlias =
        "entrada_1:hora_entrada_1,saida_1:hora_saida_1,entrada_2:hora_entrada_2,saida_2:hora_saida_2";

      const candidates = [`${baseFields},${timeFieldsAlias}`, `${baseFields},${timeFields}`];

      const errors: string[] = [];
      for (const sel of candidates) {
        const res = await build(sel);
        if (!res.error) {
          const normalized = (res.data ?? []).map(normalizeApontamentoRow);
          setApontamentos(normalized);
          return;
        }
        errors.push(describeSupabaseError(res.error));
      }

      console.error("Erro na query apontamentos_horas (todas as tentativas falharam):", errors);
      throw new Error(`Erro ao carregar apontamentos_horas. Tentativas: ${errors.join(" || ")}`);
    } catch (e: unknown) {
      console.error("Erro em carregarApontamentos:", e);
      setMsg(getErrorMessage(e, "Erro ao carregar apontamentos."));
    } finally {
      setLoading(false);
    }
  }, [effectiveEmpresaId, effectiveTenantId, filtroColabId, filtroOsId, osDbId, supabase, effectiveLoading, ensureContext]);

  useEffect(() => {
    (async () => {
      try {
        setLoading(true);
        await carregarCombos();
        await carregarApontamentos();
      } catch (e: unknown) {
        setMsg(getErrorMessage(e, "Erro ao iniciar tela."));
      } finally {
        setLoading(false);
      }
    })();
  }, [carregarApontamentos, carregarCombos]);

  useEffect(() => {
    if (osDbId) {
      setFiltroOsId(String(osDbId));
      carregarApontamentos();
    }
  }, [carregarApontamentos, osDbId]);

  const fetchOsDescricao = useCallback(async (osDigitada: string) => {
    if (effectiveLoading) return;
    await ensureContext();
    const trimmed = osDigitada.trim();

    if (!trimmed) {
      setOsDescricao("");
      setOsDbId(null);
      setOsDescError(null);
      setOsCliente("");
      setOsStatus("");
      return;
    }

    setOsDescLoading(true);
    setOsDescError(null);

    try {
      const isNumeric = /^\d+$/.test(trimmed);
      let found: (OSRow & { cliente_id?: number | null }) | null = null;

      const base = applyTenantEmpresa(
        supabase
          .from("ordens_servico")
          .select("id,numero_os,descricao_servico,cliente_nome,cliente_id,status"),
        effectiveTenantId,
        effectiveEmpresaId
      );
      const byNumero = await base.eq("numero_os", trimmed).maybeSingle();
      if (byNumero.error) throw byNumero.error;
      found = byNumero.data ?? null;

      if (!found) {
        const { data: list, error: listErr } = await base
          .ilike("numero_os", `%${trimmed}%`)
          .limit(50);
        if (listErr) throw listErr;
        const rows = (list ?? []) as (OSRow & { cliente_id?: number | null })[];
        if (isNumeric) {
          found =
            rows.find((o) => {
              const num = String(o?.numero_os ?? "").replace(/\D/g, "").replace(/^0+/, "");
              return num === trimmed;
            }) ?? null;
        } else {
          found = rows[0] ?? null;
        }
      }

      if (!found) {
        setOsDescricao("");
        setOsDbId(null);
        setOsDescError("OS nao encontrada");
        setOsCliente("");
        setOsStatus("");
        return;
      }

      const desc = found?.descricao_servico ?? "";
      setOsDescricao(desc || "");
      setOsDbId(found?.id ?? null);
      setOsCliente(found?.cliente_nome ?? "");
      setOsStatus(found?.status ?? "");
    } catch {
      setOsDescricao("");
      setOsDbId(null);
      setOsDescError("Erro ao buscar OS");
      setOsCliente("");
      setOsStatus("");
    } finally {
      setOsDescLoading(false);
    }
  }, [effectiveEmpresaId, effectiveTenantId, supabase, effectiveLoading, ensureContext]);

  const fetchOsById = useCallback(
    async (id: number) => {
      if (effectiveLoading) return false;
      await ensureContext();
      if (!Number.isFinite(id)) return false;
      setOsDescLoading(true);
      setOsDescError(null);

      try {
        const { data, error } = await applyTenantEmpresa(
          supabase
            .from("ordens_servico")
            .select("id,numero_os,descricao_servico,cliente_nome,status"),
          effectiveTenantId,
          effectiveEmpresaId
        )
          .eq("id", id)
          .maybeSingle();
        if (error) throw error;
        if (!data) return false;

        const numero = data.numero_os ?? String(data.id);
        setOsNumero(numero);
        setOsDescricao(data.descricao_servico ?? "");
        setOsDbId(data.id ?? null);
        setOsCliente(data.cliente_nome ?? "");
        setOsStatus(data.status ?? "");
        setOsDescError(null);

        return true;
      } catch {
        setOsDescError("Erro ao buscar OS");
        setOsDescricao("");
        setOsDbId(null);
        setOsCliente("");
        setOsStatus("");
        return false;
      } finally {
        setOsDescLoading(false);
      }
    },
    [effectiveEmpresaId, effectiveTenantId, supabase, effectiveLoading, ensureContext]
  );

  useEffect(() => {
    const osParam = searchParams.get("os");
    if (!osParam) return;
    const normalized = osParam.trim();
    if (!normalized) return;
    const timer = setTimeout(() => {
      const isNumeric = /^\d+$/.test(normalized);
      if (isNumeric) {
        void fetchOsById(Number(normalized)).then((found) => {
          if (!found) {
            fetchOsDescricao(normalized);
          }
        });
        return;
      }
      fetchOsDescricao(normalized);
    }, 0);
    return () => clearTimeout(timer);
  }, [fetchOsById, fetchOsDescricao, searchParams]);

  const buscarOs = async (term: string) => {
    if (effectiveLoading) return;
    await ensureContext();
    const trimmed = term.trim();
    if (!trimmed) {
      setOsSearchResults([]);
      setOsSearchError(null);
      return;
    }

    setOsSearchLoading(true);
    setOsSearchError(null);
    try {
      const { data, error } = await applyTenantEmpresa(
        supabase
          .from("ordens_servico")
          .select("id,numero_os,cliente_nome,descricao_servico,status"),
        effectiveTenantId,
        effectiveEmpresaId
      )
        .or(`numero_os.ilike.%${trimmed}%,cliente_nome.ilike.%${trimmed}%`)
        .eq("status", "em_andamento")
        .order("id", { ascending: false })
        .limit(50);
      if (error) throw error;
      setOsSearchResults((data ?? []) as OSRow[]);
    } catch (e: unknown) {
      setOsSearchError(getErrorMessage(e, "Erro ao buscar OS."));
    } finally {
      setOsSearchLoading(false);
    }
  };

  useEffect(() => {
    if (!effectiveTenantId || !effectiveEmpresaId) return;
    void ensureContext();
  }, [effectiveEmpresaId, effectiveTenantId, ensureContext]);

  useEffect(() => {
    return () => {
      if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
      if (osSearchDebounceRef.current) clearTimeout(osSearchDebounceRef.current);
    };
  }, []);

  const totalHoras = apontamentos.reduce(
    (acc, a) => acc + (Number(a.horas ?? a.horas_trabalhadas ?? 0) || 0),
    0
  );
  const osMap = useMemo(() => new Map(osList.map((o) => [o.id, o])), [osList]);
  const colMap = useMemo(() => new Map(colaboradores.map((c) => [String(c.id), c])), [colaboradores]);
  const tipoMap = useMemo(() => new Map(tiposHoras.map((t) => [t.id, t])), [tiposHoras]);
  const tipoByCodigo = useMemo(
    () => new Map(tiposHoras.map((t) => [t.codigo.toUpperCase(), t.id])),
    [tiposHoras]
  );

  const normalTipoId = useMemo(
    () => (tiposHoras.find((t) => t.codigo?.toUpperCase() === "NORMAL")?.id ?? ""),
    [tiposHoras]
  );

  useEffect(() => {
    if (!combosLoaded || tiposHoras.length === 0) return;
    if (tipoHoraTouched) return;
    if (!tipoHoraId && normalTipoId) setTipoHoraId(normalTipoId);
  }, [combosLoaded, tiposHoras.length, tipoHoraId, normalTipoId, tipoHoraTouched]);

  useEffect(() => {
    if (editing && !editTipoHoraId && normalTipoId) setEditTipoHoraId(normalTipoId);
  }, [editing, editTipoHoraId, normalTipoId]);

  const colabOptions = useMemo(
    () =>
      colaboradores.map((c, idx) => ({
        id: c.id,
        seq: String(idx + 1),
        nome: c.nome,
      })),
    [colaboradores]
  );

  useEffect(() => {
    if (!combosLoaded || tiposHoras.length === 0) return;
    if (tipoHoraTouched) return;
    let active = true;
    (async () => {
      const policy = await computeHourPolicy(data, 1);
      if (!active) return;
      const codigo = policy.items[0]?.tipoCodigo ?? "";
      const id = codigo ? tipoByCodigo.get(codigo) : undefined;
      if (id) setTipoHoraId(id);
      if (codigo) setTipoSugerido(codigo);
    })();
    return () => {
      active = false;
    };
  }, [combosLoaded, data, tipoByCodigo, tipoHoraTouched, tiposHoras.length]);

  useEffect(() => {
    let active = true;
    const horas = toNumberBR(horasText);

    if (!data || horas == null || horas <= 0) {
      setTipoSugerido("");
      return;
    }

    setTipoSugeridoLoading(true);
    (async () => {
      const policy = await computeHourPolicy(data, horas);
      if (!active) return;
      const label =
        policy.mode === "SPLIT"
          ? policy.items.map((i) => i.tipoCodigo).join(" + ")
          : policy.items[0]?.tipoCodigo ?? "";
      setTipoSugerido(label);

      const first = policy.items[0]?.tipoCodigo ?? "";
      const tipoId = tipoByCodigo.get(first);
      if (!tipoHoraTouched && tipoId) setTipoHoraId(tipoId);
      setTipoSugeridoLoading(false);
    })();

    return () => {
      active = false;
    };
  }, [data, horasText, tipoByCodigo, tipoHoraTouched]);

  async function updateApontamentoWithTimes(id: string, payloadBase: Record<string, unknown>, times: { e1: string; s1: string; e2: string; s2: string }) {
    const tryPayload = {
      ...payloadBase,
      hora_entrada_1: times.e1,
      hora_saida_1: times.s1,
      hora_entrada_2: times.e2,
      hora_saida_2: times.s2,
    };
    if (!effectiveTenantId || !effectiveEmpresaId) throw new Error("Tenant/empresa não definido.");
    const first = await applyTenantEmpresa(
      supabase.from("apontamentos_horas").update(tryPayload).eq("id", id),
      effectiveTenantId,
      effectiveEmpresaId
    );
    if (!first.error) return;
    if (!isMissingColumnError(first.error)) throw first.error;

    const fallbackPayload = {
      ...payloadBase,
      entrada_1: times.e1,
      saida_1: times.s1,
      entrada_2: times.e2,
      saida_2: times.s2,
    };
    const second = await applyTenantEmpresa(
      supabase
        .from("apontamentos_horas")
        .update(fallbackPayload as Record<string, unknown>)
        .eq("id", id),
      effectiveTenantId,
      effectiveEmpresaId
    );
    if (second.error) throw second.error;
  }

  async function salvarApontamento(options?: { preserveHoras?: boolean; advanceDate?: boolean; keepFocus?: boolean }) {
    setMsg(null);

    if (!osDbId) return alert("Selecione uma OS.");
    if (osStatus !== "em_andamento") return alert("OS nao esta em andamento.");
    if (!colabId) return alert("Selecione um colaborador.");
    if (!data) return alert("Informe a data.");
    if (tiposHoras.length === 0) {
      return alert("Tipos de horas não carregaram. Recarregue a página.");
    }
    const horas = toNumberBR(horasText);
    if (horas == null || horas <= 0 || horas > 24) return alert("Horas invalidas (0 a 24).");

    setLoading(true);

    if (!effectiveTenantId || !effectiveEmpresaId) {
      setLoading(false);
      return alert("Tenant/empresa não encontrado. Recarregue a página.");
    }

    try {
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: effectiveTenantId });
      if (tenantErr) throw tenantErr;
      try {
        await supabase.rpc("set_current_empresa", { p_empresa_id: effectiveEmpresaId });
      } catch {
        // best-effort
      }

      const descricaoBase = descricao.trim();
      const payloadBase = {
        tenant_id: effectiveTenantId,
        empresa_id: effectiveEmpresaId,
        os_id: osDbId,
        colaborador_id: colabId,
        data,
        status: "lancado",
      };

      const policy = await computeHourPolicy(data, horas);
      const payloads = policy.items.map((item) => {
        const tipoId = tipoByCodigo.get(item.tipoCodigo);
        if (!tipoId) {
          throw new Error(`Tipo de hora nao encontrado: ${item.tipoCodigo}`);
        }
        const descFinal =
          policy.mode === "SPLIT" && descricaoBase
            ? `${descricaoBase} (${item.tipoCodigo})`
            : descricaoBase || null;
        return {
          ...payloadBase,
          horas: item.horas,
          tipo_hora_id: tipoId,
          descricao: descFinal,
        };
      });

      const { error } = await applyTenantEmpresa(
        supabase.from("apontamentos_horas").insert(payloads),
        effectiveTenantId,
        effectiveEmpresaId
      );
      if (error) throw error;

      if (!options?.preserveHoras) {
        setHorasText("");
      }
      setDescricao("");
      setTipoHoraId("");
      if (options?.advanceDate && data) {
        const base = new Date(`${data}T00:00:00`);
        base.setDate(base.getDate() + 1);
        const yyyy = base.getFullYear();
        const mm = String(base.getMonth() + 1).padStart(2, "0");
        const dd = String(base.getDate()).padStart(2, "0");
        setData(`${yyyy}-${mm}-${dd}`);
      }
      if (options?.keepFocus) {
        setTimeout(() => {
          horasInputRef.current?.focus();
          horasInputRef.current?.select();
        }, 0);
      }
      await carregarApontamentos();
      setMsg("Apontamento lancado com sucesso.");
    } catch (e: unknown) {
      alert(getErrorMessage(e, "Erro ao salvar apontamento."));
    } finally {
      setLoading(false);
    }
  }

  async function excluirApontamento(id: string) {
    if (!confirm("Excluir este apontamento?")) return;
    setLoading(true);
    try {
      if (!effectiveTenantId || !effectiveEmpresaId) throw new Error("Tenant/empresa não definido.");
      const { error } = await applyTenantEmpresa(
        supabase.from("apontamentos_horas").delete().eq("id", id),
        effectiveTenantId,
        effectiveEmpresaId
      );
      if (error) throw error;
      await carregarApontamentos();
    } catch (e: unknown) {
      alert(getErrorMessage(e, "Erro ao excluir."));
    } finally {
      setLoading(false);
    }
  }

  function openEdit(ap: ApontamentoRow) {
    setEditing(ap);
    setEditData(ap.data);
    setEditDescricao(ap.descricao ?? "");
    setEditTipoHoraId(ap.tipo_hora_id ?? normalTipoId ?? "");

    const hasTimes = Boolean(ap.entrada_1 || ap.saida_1 || ap.entrada_2 || ap.saida_2);
    setEditHasTimes(hasTimes);
    if (hasTimes) {
      setEditHoraE1(ap.entrada_1 ?? "07:30");
      setEditHoraS1(ap.saida_1 ?? "12:00");
      setEditHoraE2(ap.entrada_2 ?? "13:00");
      setEditHoraS2(ap.saida_2 ?? "17:00");
      setEditHorasText("");
    } else {
      setEditHorasText(String(ap.horas ?? ap.horas_trabalhadas ?? ""));
      setEditHoraE1("07:30");
      setEditHoraS1("12:00");
      setEditHoraE2("13:00");
      setEditHoraS2("17:00");
    }
  }

  async function salvarEdicao() {
    if (!editing) return;
    if (!effectiveTenantId || !effectiveEmpresaId) return alert("Tenant/empresa não encontrado. Recarregue a página.");

    setLoading(true);
    try {
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: effectiveTenantId });
      if (tenantErr) throw tenantErr;
      try {
        await supabase.rpc("set_current_empresa", { p_empresa_id: effectiveEmpresaId });
      } catch {
        // best-effort
      }

      const base: Record<string, unknown> = {
        data: editData,
        tipo_hora_id: editTipoHoraId || null,
        descricao: editDescricao.trim() || null,
      };

      if (!editHasTimes) {
        const horas = toNumberBR(editHorasText);
        if (horas == null || horas <= 0 || horas > 24) throw new Error("Horas invalidas (0 a 24).");

        const payload = {
          ...base,
          horas,
          hora_entrada_1: null,
          hora_saida_1: null,
          hora_entrada_2: null,
          hora_saida_2: null,
        };
        const { error } = await applyTenantEmpresa(
          supabase
            .from("apontamentos_horas")
            .update(payload as Record<string, unknown>)
            .eq("id", editing.id),
          effectiveTenantId,
          effectiveEmpresaId
        );
        if (error) throw error;
      } else {
        const tipoFinal = editTipoHoraId || normalTipoId;
        if (!tipoFinal) throw new Error("Tipos de horas ainda não carregaram.");
        const e1 = parseHHMM(editHoraE1);
        const s1 = parseHHMM(editHoraS1);
        const e2 = parseHHMM(editHoraE2);
        const s2 = parseHHMM(editHoraS2);
        if (e1 === null || s1 === null || e2 === null || s2 === null) throw new Error("Horários inválidos.");
        if (!isTimeRangeValid(e1, s1, e2, s2)) {
          throw new Error("Horários inválidos. Regras: Saída 1 > Entrada 1, Saída 2 > Entrada 2 e Saída 1 <= Entrada 2.");
        }

        const payloadBase: Record<string, unknown> = {
          ...base,
          tipo_hora_id: tipoFinal,
          horas: null,
        };
        await updateApontamentoWithTimes(editing.id, payloadBase, {
          e1: editHoraE1,
          s1: editHoraS1,
          e2: editHoraE2,
          s2: editHoraS2,
        });
      }

      setEditing(null);
      await carregarApontamentos();
      setMsg("Apontamento atualizado.");
    } catch (e: unknown) {
      alert(getErrorMessage(e, "Erro ao salvar edição."));
    } finally {
      setLoading(false);
    }
  }

  const formatDateBR = (iso: string) => {
    if (!iso) return "-";
    const [yyyy, mm, dd] = iso.split("-");
    if (!yyyy || !mm || !dd) return iso;
    return `${dd}/${mm}/${yyyy}`;
  };

  return (
    <div style={{ padding: 16 }}>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginTop: 0 }}>Apontamento de horas</h1>

      {msg && (
        <div
          style={{
            marginTop: 10,
            padding: 10,
            border: "1px solid #333",
            borderRadius: 8,
            background: "rgba(255,255,255,0.04)",
          }}
        >
          {msg}
        </div>
      )}

      {/* FORM */}
      <div style={{ marginTop: 12, border: "1px solid #333", borderRadius: 10, padding: 12 }}>
        <div style={{ fontWeight: 700, marginBottom: 10 }}>Novo lancamento</div>

        <div style={{ display: "grid", gridTemplateColumns: "2fr 3fr 2fr 1fr", gap: 10 }}>
          <label>
            OS
            <input
              value={osNumero}
              onChange={(e) => {
                const value = e.target.value;
                setOsNumero(value);
                if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
                osDebounceRef.current = setTimeout(() => {
                  fetchOsDescricao(value);
                }, 300);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !osNumero.trim()) {
                  e.preventDefault();
                  setShowOsModal(true);
                  setOsSearch("");
                  setOsSearchResults([]);
                  setOsSearchError(null);
                }
              }}
              onBlur={(e) => fetchOsDescricao(e.target.value)}
              placeholder="Digite o numero da OS"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Descricao OS
            <input
              value={osDescLoading ? "Buscando..." : osDescError ? osDescError : osDescricao || "-"}
              readOnly
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Cliente
            <input
              value={osDescLoading ? "Buscando..." : osDescError ? "-" : osCliente || "-"}
              readOnly
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Status
            <input
              value={osDescLoading ? "Buscando..." : osDescError ? "-" : osStatus || "-"}
              readOnly
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr 2fr", gap: 10, marginTop: 10 }}>
          <label>
            Colaborador

            <input
              value={colabInput}
              onChange={(e) => {
                const value = e.target.value;
                setColabInput(value);
                const trimmed = value.trim();
                if (!trimmed) {
                  setColabId("");
                  return;
                }
                const seqMatch = trimmed.match(/^\d+/);
                const seq = seqMatch ? seqMatch[0] : "";
                const bySeq = colabOptions.find((c) => c.seq === seq);
                if (bySeq) {
                  setColabId(bySeq.id);
                  return;
                }
                setColabId("");
              }}
              list="colaborador-options"
              placeholder="Digite o ID sequencial do colaborador"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100 disabled:opacity-50 disabled:cursor-not-allowed"
            />
            <datalist id="colaborador-options">
              {colabOptions.map((c) => (
                <option key={c.id} value={`${c.seq} - ${c.nome}`} />
              ))}
            </datalist>
          </label>

          <label>
            Data
            <input
              type="date"
              value={data}
              onChange={(e) => setData(e.target.value)}
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Tipo
            <select
              value={tipoHoraId}
              onChange={(e) => {
                setTipoHoraId(e.target.value);
                setTipoHoraTouched(true);
              }}
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            >
              {!combosLoaded ? (
                <option value="" disabled>
                  Carregando tipos...
                </option>
              ) : tiposHoras.length === 0 ? (
                <option value="" disabled>
                  Nenhum tipo ativo encontrado
                </option>
              ) : (
                tiposHoras.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.codigo} - {t.descricao} (x{Number(t.fator).toFixed(2)})
                  </option>
                ))
              )}
            </select>
            <div className="text-xs text-zinc-400 mt-1">
              Tipo sugerido: {tipoSugeridoLoading ? "calculando..." : tipoSugerido || "-"}
            </div>
            {combosLoaded && tiposHoras.length === 0 && (
              <div className="text-xs text-red-400 mt-1">
                Nenhum tipo de hora ativo encontrado para este tenant.
              </div>
            )}
          </label>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 10, marginTop: 10 }}>
          <label>
            Horas
            <input
              ref={horasInputRef}
              value={horasText}
              onChange={(e) => setHorasText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  salvarApontamento({ preserveHoras: true, advanceDate: true, keepFocus: true });
                }
              }}
              placeholder="Ex: 8,00"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>
        </div>

        <div style={{ marginTop: 10, display: "grid", gridTemplateColumns: "1fr auto", gap: 10 }}>
          <label>
            Descricao
            <input
              value={descricao}
              onChange={(e) => setDescricao(e.target.value)}
              placeholder="Ex: Montagem painel, passagem de cabos..."
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <button
            onClick={() => salvarApontamento()}
            disabled={loading || osStatus !== "em_andamento" || !combosLoaded || tiposHoras.length === 0}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            style={{ alignSelf: "end", height: 36 }}
          >
            Salvar
          </button>
        </div>
      </div>

      {/* FILTROS + LISTA */}
      <div style={{ marginTop: 14, border: "1px solid #333", borderRadius: 10, padding: 12 }}>
        <div style={{ display: "flex", gap: 10, alignItems: "end", flexWrap: "wrap" }}>
          <label className="flex flex-col gap-1">
            <span>Filtrar OS</span>
            <select
              value={filtroOsId}
              onChange={(e) => setFiltroOsId(e.target.value)}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            >
              <option value="">Todas</option>
              {osList.map((o) => (
                <option key={o.id} value={String(o.id)}>
                  {o.numero_os}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1">
            <span>Filtrar Colaborador</span>
            <select
              value={filtroColabId}
              onChange={(e) => setFiltroColabId(e.target.value)}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            >
              <option value="">Todos</option>
              {colaboradores.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nome}
                </option>
              ))}
            </select>
          </label>

          <button
            onClick={carregarApontamentos}
            disabled={loading}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>

          <div style={{ marginLeft: "auto", opacity: 0.9 }}>
            Total horas no filtro: <b>{totalHoras.toFixed(2)}</b>
          </div>
        </div>

        <div style={{ marginTop: 12, border: "1px solid #222", borderRadius: 8, overflow: "hidden" }}>
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ textAlign: "left" }}>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Data</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Colaborador</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Horas</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Horários</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Tipo</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>OS / Descricao</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Cliente</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Ações</th>
                </tr>
              </thead>
              <tbody>
                {apontamentos.map((a) => {
                  const os = osMap.get(a.os_id);
                  const col = colMap.get(a.colaborador_id);
                  const tipo = a.tipo_hora_id ? tipoMap.get(a.tipo_hora_id) : null;
                  const osDesc = os?.descricao_servico ?? "-";
                  const clienteNome = os?.cliente_nome ?? "-";
                  const horasNum = Number(a.horas ?? a.horas_trabalhadas ?? 0);
                  const hasTimes = Boolean(a.entrada_1 || a.saida_1 || a.entrada_2 || a.saida_2);
                  const horariosLabel = hasTimes
                    ? `${a.entrada_1 ?? "--"}-${a.saida_1 ?? "--"} / ${a.entrada_2 ?? "--"}-${a.saida_2 ?? "--"}`
                    : "—";

                  return (
                    <tr key={a.id} className="hover:bg-zinc-900/40">
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{formatDateBR(a.data)}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{col?.nome || "-"}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{horasNum.toFixed(2)}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{horariosLabel}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{tipo ? tipo.codigo : "NORMAL"}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                        {os?.numero_os || a.os_id} - {osDesc}
                      </td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{clienteNome}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                        <div className="flex items-center gap-2">
                          <button
                            type="button"
                            onClick={() => openEdit(a)}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            Editar
                          </button>
                          <button
                            type="button"
                            onClick={() => excluirApontamento(a.id)}
                            className="px-3 py-1.5 rounded-md border border-red-700/50 bg-red-950/40 hover:bg-red-950 text-red-200"
                          >
                            Excluir
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}

                {apontamentos.length === 0 && (
                  <tr>
                    <td style={{ padding: 10 }} colSpan={8}>
                      Nenhum apontamento no periodo.
                    </td>
                  </tr>
                )}
            </tbody>
          </table>
        </div>
      </div>

      {editing && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Editar apontamento</div>
                <div className="text-sm text-zinc-400">OS #{editing.os_id} · Colaborador {editing.colaborador_id}</div>
              </div>
              <button
                onClick={() => setEditing(null)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                <label className="space-y-1">
                  <div className="text-xs text-zinc-400">Data</div>
                  <input
                    type="date"
                    value={editData}
                    onChange={(e) => setEditData(e.target.value)}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                  />
                </label>

                <label className="space-y-1 md:col-span-2">
                  <div className="text-xs text-zinc-400">Tipo</div>
                  <select
                    value={editTipoHoraId}
                    onChange={(e) => setEditTipoHoraId(e.target.value)}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                  >
                    {!combosLoaded ? (
                      <option value="" disabled>
                        Carregando tipos...
                      </option>
                    ) : tiposHoras.length === 0 ? (
                      <option value="" disabled>
                        Nenhum tipo ativo encontrado
                      </option>
                    ) : (
                      tiposHoras.map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.codigo} - {t.descricao} (x{Number(t.fator).toFixed(2)})
                        </option>
                      ))
                    )}
                  </select>
                </label>
              </div>

              {!editHasTimes ? (
                <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                  <label className="space-y-1 md:col-span-1">
                    <div className="text-xs text-zinc-400">Horas</div>
                    <input
                      value={editHorasText}
                      onChange={(e) => setEditHorasText(e.target.value)}
                      placeholder="Ex: 8,00"
                      className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    />
                  </label>
                  <div className="md:col-span-2 text-xs text-zinc-500 flex items-center">
                    No modo manual, os horários ficam vazios.
                  </div>
                </div>
              ) : (
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                  <label className="space-y-1">
                    <div className="text-xs text-zinc-400">Entrada 1</div>
                    <input
                      type="time"
                      value={editHoraE1}
                      onChange={(e) => setEditHoraE1(e.target.value)}
                      className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    />
                  </label>
                  <label className="space-y-1">
                    <div className="text-xs text-zinc-400">Saída 1</div>
                    <input
                      type="time"
                      value={editHoraS1}
                      onChange={(e) => setEditHoraS1(e.target.value)}
                      className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    />
                  </label>
                  <label className="space-y-1">
                    <div className="text-xs text-zinc-400">Entrada 2</div>
                    <input
                      type="time"
                      value={editHoraE2}
                      onChange={(e) => setEditHoraE2(e.target.value)}
                      className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    />
                  </label>
                  <label className="space-y-1">
                    <div className="text-xs text-zinc-400">Saída 2</div>
                    <input
                      type="time"
                      value={editHoraS2}
                      onChange={(e) => setEditHoraS2(e.target.value)}
                      className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    />
                  </label>
                </div>
              )}

              <label className="space-y-1">
                <div className="text-xs text-zinc-400">Descrição</div>
                <input
                  value={editDescricao}
                  onChange={(e) => setEditDescricao(e.target.value)}
                  placeholder="Ex: Montagem painel, passagem de cabos..."
                  className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                />
              </label>
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
              <button
                onClick={() => setEditing(null)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={salvarEdicao}
                disabled={loading}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {loading ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}

      {showOsModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Buscar OS</div>
                <div className="text-sm text-zinc-400">Digite numero da OS ou cliente para buscar.</div>
              </div>
              <button
                onClick={() => setShowOsModal(false)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Buscar</div>
                <input
                  value={osSearch}
                  onChange={(e) => {
                    const value = e.target.value;
                    setOsSearch(value);
                    if (osSearchDebounceRef.current) clearTimeout(osSearchDebounceRef.current);
                    osSearchDebounceRef.current = setTimeout(() => {
                      buscarOs(value);
                    }, 300);
                  }}
                  placeholder="Ex: 43 ou nome do cliente"
                  className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                />
              </div>

              {osSearchLoading && <div className="text-sm text-zinc-400">Buscando...</div>}
              {osSearchError && <div className="text-sm text-red-400">{osSearchError}</div>}

              <div className="border border-zinc-800 rounded-lg overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/70">
                    <tr className="text-zinc-200">
                      <th className="px-3 py-2 text-left">OS</th>
                      <th className="px-3 py-2 text-left">Cliente</th>
                      <th className="px-3 py-2 text-left">Descricao</th>
                      <th className="px-3 py-2 text-center">Acao</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-800">
                    {osSearchResults.map((o) => (
                      <tr key={o.id} className="hover:bg-zinc-900/40">
                        <td className="px-3 py-2">{o.numero_os}</td>
                        <td className="px-3 py-2">{o.cliente_nome || "-"}</td>
                        <td className="px-3 py-2">{o.descricao_servico || "-"}</td>
                        <td className="px-3 py-2 text-center">
                          <button
                            onClick={() => {
                              const numero = o.numero_os ?? String(o.id);
                              setOsNumero(numero);
                              setShowOsModal(false);
                              if (o.numero_os) {
                                fetchOsDescricao(o.numero_os);
                              } else {
                                fetchOsById(o.id);
                              }
                            }}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            Selecionar
                          </button>
                        </td>
                      </tr>
                    ))}
                    {!osSearchLoading && osSearchResults.length === 0 && osSearch.trim() !== "" && (
                      <tr>
                        <td colSpan={4} className="px-3 py-4 text-zinc-400">
                          Nenhuma OS encontrada.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
