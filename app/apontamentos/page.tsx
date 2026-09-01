"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { getFeriadosJoinville } from "@/lib/datas/feriadosJoinville";
import { normalizeOsStatusFluxo, type OsStatusExibicao } from "@/lib/os/statusFluxo";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { supabaseBrowser } from "@/lib/supabase/client";

type Colaborador = { id: string; nome: string; ativo: boolean; cargo?: string | null; user_id?: string | null };
type TipoHora = { id: string; codigo: string; descricao: string; fator: number; ativo: boolean };

type OSRow = {
  id: number;
  numero_os: string | null;
  cliente_nome: string | null;
  descricao_servico: string | null;
  status: string | null;
  status_fluxo: string | null;
};

type ApontamentoRow = {
  id: string;
  os_id: number;
  numero_os: string | null;
  cliente_nome: string | null;
  descricao_servico: string | null;
  colaborador_id: string;
  colaborador_nome: string;
  data: string;
  horas: number;
  tipo_hora_id: string | null;
  tipo_codigo: string | null;
  tipo_descricao: string | null;
  fator_aplicado: number | null;
  descricao: string | null;
  status: string;
  status_aprovacao: string | null;
  criado_em: string;
  criado_por_user_id: string | null;
  criado_por_nome: string | null;
  gerado_por_hh: boolean;
  hh_lancamento_id: number | null;
  entrada_1: string | null;
  saida_1: string | null;
  entrada_2: string | null;
  saida_2: string | null;
};

type DuplicateWarning = {
  id: string;
  colaborador_id: string;
  colaborador_nome: string;
  horas: number;
  tipo_codigo: string | null;
};

type Suggestion = {
  codigo: string;
  reason: string;
  split?: Array<{ codigo: string; horas: number }>;
};

type DateValidation = { fechada: boolean; motivo: string | null };

const GESTAO_MAP: Record<string, { item_tipo: string; area: string }> = {
  projeto_eletrico: { item_tipo: "projeto", area: "eletrico" },
  projeto_mecanico: { item_tipo: "projeto", area: "mecanico" },
  projeto_seguranca: { item_tipo: "projeto", area: "seguranca" },
  projeto_software: { item_tipo: "projeto", area: "software" },
  execucao_eletrica: { item_tipo: "execucao", area: "eletrico" },
  execucao_mecanica: { item_tipo: "execucao", area: "mecanico" },
};

const PAPEIS_GESTAO_HORAS = new Set(["ADMIN", "DIRETOR", "COORDENACAO"]);

function podeEditarApontamento(row: ApontamentoRow, papelEmpresa: string, meuColaboradorId: string | null) {
  if (row.gerado_por_hh || row.status.toLowerCase() === "fechado") return false;
  if (row.status_aprovacao === "aprovado") return PAPEIS_GESTAO_HORAS.has(papelEmpresa);
  return Boolean(meuColaboradorId) && row.colaborador_id === meuColaboradorId;
}

function podeExcluirApontamento(row: ApontamentoRow, meuColaboradorId: string | null) {
  return !row.gerado_por_hh
    && row.status.toLowerCase() !== "fechado"
    && row.status_aprovacao !== "aprovado"
    && Boolean(meuColaboradorId)
    && row.colaborador_id === meuColaboradorId;
}

const monthFormatter = new Intl.DateTimeFormat("pt-BR", { month: "long", year: "numeric" });
const weekdayFormatter = new Intl.DateTimeFormat("pt-BR", { weekday: "long" });
const dateLongFormatter = new Intl.DateTimeFormat("pt-BR", {
  day: "2-digit",
  month: "long",
  weekday: "long",
});

function localDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(year, month - 1, day, 12);
}

function todayISO() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

function monthStartISO(iso = todayISO()) {
  return `${iso.slice(0, 7)}-01`;
}

function dateBR(iso: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return iso || "—";
  const [year, month, day] = iso.split("-");
  return `${day}/${month}/${year}`;
}

function dateMask(value: string) {
  const digits = value.replace(/\D/g, "").slice(0, 8);
  if (digits.length <= 2) return digits;
  if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`;
  return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`;
}

function dateFromBR(value: string) {
  const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value.trim());
  if (!match) return null;
  const iso = `${match[3]}-${match[2]}-${match[1]}`;
  const parsed = localDate(iso);
  return parsed.getFullYear() === Number(match[3]) && parsed.getMonth() + 1 === Number(match[2]) && parsed.getDate() === Number(match[1])
    ? iso
    : null;
}

function parseHours(value: string) {
  const raw = value.trim().toLowerCase().replace(/\s/g, "");
  if (!raw) return null;
  const timeMatch = /^(\d{1,2})(?::|h)(\d{0,2})$/.exec(raw);
  if (timeMatch) {
    const hours = Number(timeMatch[1]);
    const minutes = Number(timeMatch[2] || 0);
    if (minutes > 59) return null;
    return hours + minutes / 60;
  }
  const normalized = raw.includes(",") ? raw.replace(/\./g, "").replace(",", ".") : raw;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function formatHours(value: number) {
  return Number(value || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatHoursClock(value: number) {
  let totalMinutes = Math.round(Number(value || 0) * 60);
  const hours = Math.floor(totalMinutes / 60);
  totalMinutes -= hours * 60;
  return `${hours}h${String(totalMinutes).padStart(2, "0")}`;
}

function getErrorMessage(error: unknown, fallback: string) {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === "string" && error.trim()) return error;
  if (error && typeof error === "object" && "message" in error) {
    const message = String((error as { message?: unknown }).message ?? "");
    if (message.trim()) return message;
  }
  return fallback;
}

function osStatus(row: OSRow | null): OsStatusExibicao | null {
  if (!row) return null;
  return normalizeOsStatusFluxo(row.status_fluxo, row.status);
}

function statusLabel(status: OsStatusExibicao | null) {
  switch (status) {
    case "aberta": return "Aberta";
    case "em_andamento": return "Em andamento";
    case "concluida": return "Concluída";
    case "faturada": return "Faturada";
    case "em_andamento_garantia": return "Em andamento · garantia";
    case "concluida_garantia": return "Concluída · garantia";
    case "cancelada": return "Cancelada";
    default: return "Sem status";
  }
}

function isClosedOs(status: OsStatusExibicao | null) {
  return status === "concluida" || status === "faturada" || status === "concluida_garantia";
}

function isAllowedOs(status: OsStatusExibicao | null) {
  return status === "em_andamento" || status === "em_andamento_garantia" || isClosedOs(status);
}

function suggestionFor(dateISO: string, hours: number | null): Suggestion {
  const date = localDate(dateISO);
  const weekday = date.getDay();
  const holiday = getFeriadosJoinville(date.getFullYear()).find((item) => item.data === dateISO);
  const shortDate = dateBR(dateISO).slice(0, 5);

  if (holiday) return { codigo: "EXTRA_100", reason: `Sugerido porque ${shortDate} é feriado (${holiday.descricao}).` };
  if (weekday === 0) return { codigo: "EXTRA_100", reason: `Sugerido porque ${shortDate} é domingo.` };
  if (weekday === 6) return { codigo: "EXTRA_50", reason: `Sugerido porque ${shortDate} é sábado.` };
  if (hours != null && hours > 9) {
    return {
      codigo: "NORMAL",
      reason: "Sugerido dividir 9,00 h normais e o excedente em hora extra 50%.",
      split: [
        { codigo: "NORMAL", horas: 9 },
        { codigo: "EXTRA_50", horas: Number((hours - 9).toFixed(2)) },
      ],
    };
  }
  return { codigo: "NORMAL", reason: `Sugerido porque ${shortDate} é dia útil.` };
}

function DateInputBR({ value, onChange, disabled, ariaLabel }: { value: string; onChange: (value: string) => void; disabled?: boolean; ariaLabel: string }) {
  const [text, setText] = useState(dateBR(value));

  useEffect(() => {
    // Mantém a máscara sincronizada quando a data muda pelo calendário nativo.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setText(dateBR(value));
  }, [value]);

  return (
    <div className="ah-date-input">
      <input
        aria-label={ariaLabel}
        value={text}
        inputMode="numeric"
        placeholder="dd/mm/aaaa"
        disabled={disabled}
        onChange={(event) => {
          const masked = dateMask(event.target.value);
          setText(masked);
          const parsed = dateFromBR(masked);
          if (parsed) onChange(parsed);
        }}
        onBlur={() => setText(dateBR(value))}
      />
      <span aria-hidden="true">▣</span>
      <input
        className="ah-native-date"
        type="date"
        tabIndex={-1}
        aria-hidden="true"
        value={value}
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
      />
    </div>
  );
}

export default function ApontamentosPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId, sessionUserId, empresa: empresaAtual } = useTenantEmpresa();
  const { has } = usePermissions();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const canWrite = Boolean(has("apontamentos.write"));
  const papelEmpresa = String(empresaAtual?.papel ?? "").trim().toUpperCase();
  const tenant = tenantId ?? "";
  const empresa = empresaId ?? "";

  const initialFrom = searchParams.get("de") || monthStartISO();
  const initialTo = searchParams.get("ate") || todayISO();
  const [dateFrom, setDateFrom] = useState(initialFrom);
  const [dateTo, setDateTo] = useState(initialTo);
  const [filterOs, setFilterOs] = useState(searchParams.get("os") || "");
  const [filterColab, setFilterColab] = useState(searchParams.get("colaborador") || "");
  const [filterType, setFilterType] = useState(searchParams.get("tipo") || "");
  const [filterSearch, setFilterSearch] = useState(searchParams.get("busca") || "");
  const [filterSearchInput, setFilterSearchInput] = useState(searchParams.get("busca") || "");

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ tone: "ok" | "error" | "info"; text: string } | null>(null);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [tiposHoras, setTiposHoras] = useState<TipoHora[]>([]);
  const [filterOsOptions, setFilterOsOptions] = useState<OSRow[]>([]);
  const [apontamentos, setApontamentos] = useState<ApontamentoRow[]>([]);

  const [osQuery, setOsQuery] = useState("");
  const [osResults, setOsResults] = useState<OSRow[]>([]);
  const [osSearching, setOsSearching] = useState(false);
  const [selectedOs, setSelectedOs] = useState<OSRow | null>(null);
  const [colabQuery, setColabQuery] = useState("");
  const [selectedColabs, setSelectedColabs] = useState<string[]>([]);
  const [date, setDate] = useState(todayISO());
  const [hoursText, setHoursText] = useState("");
  const [typeId, setTypeId] = useState("");
  const [typeTouched, setTypeTouched] = useState(false);
  const [description, setDescription] = useState("");
  const [validationAttempted, setValidationAttempted] = useState(false);
  const [duplicates, setDuplicates] = useState<DuplicateWarning[]>([]);
  const [dateValidation, setDateValidation] = useState<DateValidation>({ fechada: false, motivo: null });
  const [newIds, setNewIds] = useState<Set<string>>(new Set());

  const [editing, setEditing] = useState<ApontamentoRow | null>(null);
  const [editDate, setEditDate] = useState(todayISO());
  const [editHours, setEditHours] = useState("");
  const [editType, setEditType] = useState("");
  const [editDescription, setEditDescription] = useState("");
  const [deleteTarget, setDeleteTarget] = useState<ApontamentoRow | null>(null);
  const osSearchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const osInputRef = useRef<HTMLInputElement | null>(null);
  const collaboratorInputRef = useRef<HTMLInputElement | null>(null);
  const hoursInputRef = useRef<HTMLInputElement | null>(null);
  const typeSelectRef = useRef<HTMLSelectElement | null>(null);
  const descriptionInputRef = useRef<HTMLInputElement | null>(null);
  const submitLock = useRef(false);

  const ensureContext = useCallback(async () => {
    if (!tenant || !empresa) throw new Error("Tenant ou empresa não encontrados. Recarregue a página.");
    const { error: tenantError } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenant });
    if (tenantError) throw tenantError;
    const { error: empresaError } = await supabase.rpc("set_current_empresa", { p_empresa_id: empresa });
    if (empresaError) throw empresaError;
  }, [empresa, supabase, tenant]);

  const typeMap = useMemo(() => new Map(tiposHoras.map((item) => [item.id, item])), [tiposHoras]);
  const typeByCode = useMemo(() => new Map(tiposHoras.map((item) => [item.codigo.toUpperCase(), item])), [tiposHoras]);
  const collaboratorMap = useMemo(() => new Map(colaboradores.map((item) => [item.id, item])), [colaboradores]);
  const meuColaboradorId = useMemo(
    () => colaboradores.find((item) => item.user_id === sessionUserId)?.id ?? null,
    [colaboradores, sessionUserId]
  );
  const hours = useMemo(() => parseHours(hoursText), [hoursText]);
  const suggestion = useMemo(() => suggestionFor(date, hours), [date, hours]);
  const selectedType = typeMap.get(typeId) ?? null;
  const selectedStatus = osStatus(selectedOs);
  const typeIsSpecial = (selectedType?.codigo ?? suggestion.codigo).toUpperCase() !== "NORMAL";

  const filteredCollaborators = useMemo(() => {
    const term = colabQuery.trim().toLocaleLowerCase("pt-BR");
    if (!term) return [];
    return colaboradores
      .filter((item) => !selectedColabs.includes(item.id) && item.nome.toLocaleLowerCase("pt-BR").includes(term))
      .slice(0, 8);
  }, [colabQuery, colaboradores, selectedColabs]);

  const loadCombos = useCallback(async () => {
    await ensureContext();
    const [collaboratorResult, typeResult, osResult] = await Promise.all([
      applyTenantEmpresa(
        supabase.from("colaboradores").select("id,nome,ativo,cargo,user_id").eq("ativo", true).order("nome"),
        tenant,
        empresa
      ),
      applyTenant(supabase.from("tipos_horas").select("id,codigo,descricao,fator,ativo").eq("ativo", true).order("codigo"), tenant),
      applyTenantEmpresa(
        supabase
          .from("ordens_servico")
          .select("id,numero_os,cliente_nome,descricao_servico,status,status_fluxo")
          .eq("tipo_documento", "OS")
          .order("id", { ascending: false })
          .limit(500),
        tenant,
        empresa
      ),
    ]);
    if (collaboratorResult.error) throw collaboratorResult.error;
    if (typeResult.error) throw typeResult.error;
    if (osResult.error) throw osResult.error;
    setColaboradores((collaboratorResult.data ?? []) as Colaborador[]);
    setTiposHoras((typeResult.data ?? []) as TipoHora[]);
    setFilterOsOptions((osResult.data ?? []) as OSRow[]);
  }, [empresa, ensureContext, supabase, tenant]);

  const loadEntries = useCallback(async () => {
    if (!tenant || !empresa) return;
    setLoading(true);
    try {
      await ensureContext();
      const { data: rows, error } = await supabase.rpc("web_listar_apontamentos_horas", {
        p_data_inicio: dateFrom,
        p_data_fim: dateTo,
        p_os_id: filterOs ? Number(filterOs) : null,
        p_colaborador_id: filterColab || null,
        p_tipo_hora_id: filterType || null,
        p_busca: filterSearch.trim() || null,
        p_limite: 5000,
      });
      if (error) throw error;
      setApontamentos((rows ?? []) as ApontamentoRow[]);
    } catch (error) {
      setMessage({ tone: "error", text: getErrorMessage(error, "Erro ao carregar apontamentos.") });
      setApontamentos([]);
    } finally {
      setLoading(false);
    }
  }, [dateFrom, dateTo, empresa, ensureContext, filterColab, filterOs, filterSearch, filterType, supabase, tenant]);

  useEffect(() => {
    if (!tenant || !empresa) return;
    const timer = setTimeout(() => {
      void loadCombos().catch((error: unknown) => {
        setMessage({ tone: "error", text: getErrorMessage(error, "Erro ao carregar os campos de apoio.") });
      });
    }, 0);
    return () => clearTimeout(timer);
  }, [empresa, loadCombos, tenant]);

  useEffect(() => {
    if (!tenant || !empresa) return;
    const timer = setTimeout(() => void loadEntries(), 0);
    return () => clearTimeout(timer);
  }, [empresa, loadEntries, tenant]);

  useEffect(() => {
    const timer = setTimeout(() => setFilterSearch(filterSearchInput), 350);
    return () => clearTimeout(timer);
  }, [filterSearchInput]);

  useEffect(() => {
    const next = new URLSearchParams();
    next.set("de", dateFrom);
    next.set("ate", dateTo);
    if (filterOs) next.set("os", filterOs);
    if (filterColab) next.set("colaborador", filterColab);
    if (filterType) next.set("tipo", filterType);
    if (filterSearch.trim()) next.set("busca", filterSearch.trim());
    router.replace(`${pathname}?${next.toString()}`, { scroll: false });
  }, [dateFrom, dateTo, filterColab, filterOs, filterSearch, filterType, pathname, router]);

  useEffect(() => {
    if (!tiposHoras.length || typeTouched) return;
    const suggested = typeByCode.get(suggestion.codigo);
    // O tipo sugerido acompanha a data até o usuário escolher manualmente.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (suggested) setTypeId(suggested.id);
  }, [suggestion.codigo, typeByCode, typeTouched, tiposHoras.length]);

  useEffect(() => {
    if (!tenant || !empresa || !date) return;
    let active = true;
    void (async () => {
      try {
        await ensureContext();
        const { data: result, error } = await supabase.rpc("web_validar_data_apontamento", { p_data: date });
        if (error) throw error;
        if (active) {
          const value = (result ?? {}) as { fechada?: boolean; motivo?: string | null };
          setDateValidation({ fechada: Boolean(value.fechada), motivo: value.motivo ?? null });
        }
      } catch {
        if (active) setDateValidation({ fechada: false, motivo: null });
      }
    })();
    return () => { active = false; };
  }, [date, empresa, ensureContext, supabase, tenant]);

  useEffect(() => {
    if (!selectedOs || !selectedColabs.length || !date || !tenant || !empresa) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setDuplicates([]);
      return;
    }
    let active = true;
    void (async () => {
      try {
        await ensureContext();
        const result = await applyTenantEmpresa(
          supabase
            .from("apontamentos_horas")
            .select("id,colaborador_id,horas,tipo_hora_id")
            .eq("os_id", selectedOs.id)
            .eq("data", date)
            .in("colaborador_id", selectedColabs),
          tenant,
          empresa
        );
        if (result.error) throw result.error;
        if (!active) return;
        setDuplicates((result.data ?? []).map((item) => ({
          id: String(item.id),
          colaborador_id: String(item.colaborador_id),
          colaborador_nome: collaboratorMap.get(String(item.colaborador_id))?.nome ?? "Colaborador",
          horas: Number(item.horas ?? 0),
          tipo_codigo: typeMap.get(String(item.tipo_hora_id ?? ""))?.codigo ?? null,
        })));
      } catch {
        if (active) setDuplicates([]);
      }
    })();
    return () => { active = false; };
  }, [collaboratorMap, date, empresa, ensureContext, selectedColabs, selectedOs, supabase, tenant, typeMap]);

  const searchOs = useCallback((term: string) => {
    const clean = term.trim().replace(/[,%()]/g, " ").trim();
    if (!clean) {
      setOsResults([]);
      return;
    }
    setOsSearching(true);
    const normalized = clean.toLocaleLowerCase("pt-BR");
    setOsResults(filterOsOptions.filter((item) =>
      String(item.numero_os ?? item.id).toLocaleLowerCase("pt-BR").includes(normalized)
      || String(item.cliente_nome ?? "").toLocaleLowerCase("pt-BR").includes(normalized)
      || String(item.descricao_servico ?? "").toLocaleLowerCase("pt-BR").includes(normalized)
    ).slice(0, 12));
    setOsSearching(false);
  }, [filterOsOptions]);

  function handleOsQuery(value: string) {
    setOsQuery(value);
    setSelectedOs(null);
    if (osSearchTimer.current) clearTimeout(osSearchTimer.current);
    osSearchTimer.current = setTimeout(() => searchOs(value), 150);
  }

  function chooseOs(item: OSRow) {
    setSelectedOs(item);
    setOsQuery(item.numero_os || String(item.id));
    setOsResults([]);
    setMessage(null);
  }

  function addCollaborator(id: string) {
    setSelectedColabs((current) => current.includes(id) ? current : [...current, id]);
    setColabQuery("");
    requestAnimationFrame(() => collaboratorInputRef.current?.focus());
  }

  const entriesToCreate = useMemo(() => {
    if (hours == null || hours <= 0) return [];
    if (!typeTouched && suggestion.split) return suggestion.split;
    const currentType = selectedType?.codigo || suggestion.codigo;
    return [{ codigo: currentType, horas: hours }];
  }, [hours, selectedType?.codigo, suggestion.codigo, suggestion.split, typeTouched]);

  const totalHoursToCreate = useMemo(
    () => entriesToCreate.reduce((sum, item) => sum + item.horas, 0) * selectedColabs.length,
    [entriesToCreate, selectedColabs.length]
  );

  const missingReason = useMemo(() => {
    if (!selectedOs) return "Selecione a OS";
    if (!isAllowedOs(selectedStatus)) return selectedStatus === "cancelada" ? "OS cancelada" : "A OS não está disponível";
    if (!selectedColabs.length) return "Selecione ao menos um colaborador";
    if (!date) return "Informe a data";
    if (dateValidation.fechada) return dateValidation.motivo || "Competência fechada";
    if (hours == null || hours <= 0 || hours > 24) return "Informe horas entre 0 e 24";
    if (!typeId) return "Selecione o tipo de hora";
    if (!description.trim()) return "Falta a descrição";
    return null;
  }, [date, dateValidation, description, hours, selectedColabs.length, selectedOs, selectedStatus, typeId]);

  async function autoEnableGestao(osId: number, collaboratorId: string) {
    try {
      const collaboratorResult = await applyTenantEmpresa(
        supabase.from("colaboradores").select("cargo").eq("id", collaboratorId),
        tenant,
        empresa
      ).maybeSingle();
      const cargo = (collaboratorResult.data as { cargo?: string | null } | null)?.cargo;
      if (!cargo) return;
      const cargoResult = await applyTenant(
        supabase.from("cargos").select("tipo_gestao").eq("nome", cargo),
        tenant
      ).maybeSingle();
      const tipoGestao = (cargoResult.data as { tipo_gestao?: string | null } | null)?.tipo_gestao;
      const target = tipoGestao ? GESTAO_MAP[tipoGestao] : null;
      if (!target) return;
      const current = await applyTenantEmpresa(
        supabase
          .from("os_gestao_itens")
          .select("id,habilitado")
          .eq("os_id", osId)
          .eq("item_tipo", target.item_tipo)
          .eq("area", target.area),
        tenant,
        empresa
      ).maybeSingle();
      if ((current.data as { habilitado?: boolean } | null)?.habilitado) return;
      const forecast = new Date();
      forecast.setDate(forecast.getDate() + 30);
      await supabase.from("os_gestao_itens").upsert({
        tenant_id: tenant,
        empresa_id: empresa,
        os_id: osId,
        item_tipo: target.item_tipo,
        area: target.area,
        habilitado: true,
        data_prevista: forecast.toISOString().slice(0, 10),
        responsavel_id: null,
        progresso_percent: 0,
      }, { onConflict: "os_id,item_tipo,area" });
      await applyTenantEmpresa(
        supabase.from("ordens_servico").update({ tem_gestao: true, atualizado_em: new Date().toISOString() }).eq("id", osId),
        tenant,
        empresa
      );
    } catch {
      // Gestão é complementar e nunca deve interromper o apontamento principal.
    }
  }

  function attemptSaveEntry() {
    if (saving || submitLock.current) return;
    if (!missingReason) {
      setValidationAttempted(false);
      void saveEntry();
      return;
    }

    setValidationAttempted(true);
    const text = missingReason === "Falta a descrição"
      ? "Informe a descrição do trabalho realizado antes de salvar."
      : `${missingReason}. Revise o campo indicado antes de salvar.`;
    setMessage({ tone: "error", text });

    const target = missingReason === "Selecione a OS"
      ? osInputRef.current
      : missingReason === "Selecione ao menos um colaborador"
        ? collaboratorInputRef.current
        : missingReason === "Informe horas entre 0 e 24"
          ? hoursInputRef.current
          : missingReason === "Selecione o tipo de hora"
            ? typeSelectRef.current
            : missingReason === "Falta a descrição"
              ? descriptionInputRef.current
              : null;

    requestAnimationFrame(() => {
      target?.scrollIntoView({ behavior: "smooth", block: "center" });
      target?.focus({ preventScroll: true });
    });
  }

  async function saveEntry() {
    if (submitLock.current || missingReason || !selectedOs || hours == null) return;
    if (date > todayISO() && !window.confirm(`A data ${dateBR(date)} está no futuro. Deseja continuar?`)) return;
    if (hours > 12 && !window.confirm(`O lançamento é de ${formatHours(hours)} h por colaborador. Confirma esse total?`)) return;
    const closed = isClosedOs(selectedStatus);
    if (closed && !window.confirm(`A OS ${selectedOs.numero_os || selectedOs.id} está ${statusLabel(selectedStatus).toLowerCase()}. Este lançamento pode alterar um período já concluído ou faturado. Deseja continuar?`)) return;

    submitLock.current = true;
    setSaving(true);
    setMessage(null);
    try {
      await ensureContext();
      const payload: Record<string, unknown>[] = [];
      for (const collaboratorId of selectedColabs) {
        for (const entry of entriesToCreate) {
          const type = typeByCode.get(entry.codigo);
          if (!type) throw new Error(`O tipo ${entry.codigo} não está cadastrado ou está inativo.`);
          payload.push({
            os_id: selectedOs.id,
            colaborador_id: collaboratorId,
            data: date,
            horas: Number(entry.horas.toFixed(2)),
            tipo_hora_id: type.id,
            fator_aplicado: Number(type.fator),
            descricao: description.trim(),
            confirmar_os_encerrada: closed,
          });
        }
      }
      const { data: result, error } = await supabase.rpc("web_criar_apontamentos_horas", { p_lancamentos: payload });
      if (error) throw error;
      const value = (result ?? {}) as { ids?: string[]; gravados?: number };
      setNewIds(new Set(value.ids ?? []));
      await Promise.all(selectedColabs.map((id) => autoEnableGestao(selectedOs.id, id)));
      const count = value.gravados ?? payload.length;
      setSelectedColabs([]);
      setColabQuery("");
      setHoursText("");
      setDescription("");
      setValidationAttempted(false);
      setTypeTouched(false);
      setDuplicates([]);
      setMessage({ tone: "ok", text: `${count} lançamento${count === 1 ? "" : "s"} salvo${count === 1 ? "" : "s"}. A OS e a data foram mantidas para o próximo lançamento.` });
      await loadEntries();
      requestAnimationFrame(() => collaboratorInputRef.current?.focus());
    } catch (error) {
      setMessage({ tone: "error", text: getErrorMessage(error, "Erro ao salvar apontamento.") });
    } finally {
      submitLock.current = false;
      setSaving(false);
    }
  }

  function openEdit(row: ApontamentoRow) {
    if (row.gerado_por_hh) {
      setMessage({ tone: "info", text: "Este lançamento é gerado pelo módulo HH e deve ser alterado na OS de origem." });
      return;
    }
    setEditing(row);
    setEditDate(row.data);
    setEditHours(String(row.horas).replace(".", ","));
    setEditType(row.tipo_hora_id ?? "");
    setEditDescription(row.descricao ?? "");
  }

  async function saveEdit() {
    if (!editing || submitLock.current) return;
    const parsedHours = parseHours(editHours);
    if (parsedHours == null || parsedHours <= 0 || parsedHours > 24) {
      setMessage({ tone: "error", text: "Informe horas entre 0 e 24." });
      return;
    }
    if (!editDescription.trim()) {
      setMessage({ tone: "error", text: "Informe a descrição do trabalho realizado." });
      return;
    }
    if (editDate > todayISO() && !window.confirm(`A data ${dateBR(editDate)} está no futuro. Deseja continuar?`)) return;
    if (parsedHours > 12 && !window.confirm(`O lançamento é de ${formatHours(parsedHours)} h. Confirma esse total?`)) return;
    submitLock.current = true;
    setSaving(true);
    try {
      await ensureContext();
      const { error } = await supabase.rpc("web_atualizar_apontamento_horas", {
        p_apontamento_id: editing.id,
        p_dados: {
          data: editDate,
          horas: Number(parsedHours.toFixed(2)),
          tipo_hora_id: editType,
          descricao: editDescription.trim(),
        },
      });
      if (error) throw error;
      setEditing(null);
      setMessage({ tone: "ok", text: "Apontamento atualizado." });
      await loadEntries();
    } catch (error) {
      setMessage({ tone: "error", text: getErrorMessage(error, "Erro ao atualizar apontamento.") });
    } finally {
      submitLock.current = false;
      setSaving(false);
    }
  }

  async function deleteEntry() {
    if (!deleteTarget || submitLock.current) return;
    submitLock.current = true;
    setSaving(true);
    try {
      await ensureContext();
      const { error } = await supabase.rpc("web_excluir_apontamento_horas", { p_apontamento_id: deleteTarget.id });
      if (error) throw error;
      setDeleteTarget(null);
      setMessage({ tone: "ok", text: "Apontamento excluído. O responsável pela exclusão foi registrado na auditoria." });
      await loadEntries();
    } catch (error) {
      setMessage({ tone: "error", text: getErrorMessage(error, "Erro ao excluir apontamento.") });
    } finally {
      submitLock.current = false;
      setSaving(false);
    }
  }

  const groupedEntries = useMemo(() => {
    const groups = new Map<string, ApontamentoRow[]>();
    for (const row of apontamentos) {
      const list = groups.get(row.data) ?? [];
      list.push(row);
      groups.set(row.data, list);
    }
    return Array.from(groups.entries());
  }, [apontamentos]);

  const totalPeriod = useMemo(() => apontamentos.reduce((sum, row) => sum + Number(row.horas || 0), 0), [apontamentos]);
  const periodLabel = dateFrom.slice(0, 7) === dateTo.slice(0, 7)
    ? monthFormatter.format(localDate(dateFrom))
    : `${dateBR(dateFrom)} a ${dateBR(dateTo)}`;

  function setCurrentMonth() {
    setDateFrom(monthStartISO());
    setDateTo(todayISO());
  }

  return (
    <main className="carteira-theme apontamentos-page">
      <header className="ah-page-header">
        <div>
          <nav className="ah-breadcrumb" aria-label="Navegação estrutural"><span>Apontamentos</span><b>›</b><strong>Lançar horas</strong></nav>
          <h1>Apontamento de horas</h1>
          <p>Registre as horas trabalhadas por OS e colaborador com conferência antes de salvar.</p>
        </div>
        <div className="ah-header-actions">
          <button type="button" className="ah-button" onClick={() => setMessage({ tone: "info", text: "A importação por planilha será disponibilizada em uma etapa dedicada, com validação e prévia antes da gravação." })}>Importar planilha</button>
          <Link href="/apontamentos/resumo-mensal" className="ah-button ah-button-primary">Resumo do mês</Link>
        </div>
      </header>

      {message && <div className={`ah-message is-${message.tone}`} role={message.tone === "error" ? "alert" : "status"}><span>{message.text}</span><button type="button" onClick={() => setMessage(null)} aria-label="Fechar mensagem">×</button></div>}
      {!canWrite && <div className="ah-message is-info">Consulta somente leitura. Seu perfil não pode incluir, editar ou excluir apontamentos.</div>}

      {canWrite && (
        <section className="ah-card ah-form-card" aria-labelledby="new-entry-title">
          <div className="ah-section-title">
            <div><span>NOVO LANÇAMENTO</span><h2 id="new-entry-title">Quem trabalhou, onde e por quanto tempo?</h2></div>
            <small>As horas são lançadas separadamente para cada colaborador.</small>
          </div>

          <div className="ah-field ah-os-field">
            <label htmlFor="ah-os-search">Ordem de serviço</label>
            <div className="ah-autocomplete">
              <input ref={osInputRef} id="ah-os-search" value={osQuery} onChange={(event) => handleOsQuery(event.target.value)} placeholder="Número, cliente ou trecho da descrição" autoComplete="off" />
              {osSearching && <span className="ah-input-status">Buscando…</span>}
              {!osSearching && osQuery.trim() && !selectedOs && osResults.length === 0 && <div className="ah-not-found">Nenhuma OS encontrada para “{osQuery}”.</div>}
              {osResults.length > 0 && !selectedOs && (
                <div className="ah-options" role="listbox">
                  {osResults.map((item) => (
                    <button type="button" key={item.id} onClick={() => chooseOs(item)} role="option" aria-selected="false">
                      <b>OS {item.numero_os || item.id}</b><span>{item.cliente_nome || "Cliente não informado"}</span><small>{item.descricao_servico || "Sem descrição"} · {statusLabel(osStatus(item))}</small>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {selectedOs && (
            <div className={`ah-os-confirmation ${isClosedOs(selectedStatus) ? "is-warning" : "is-ok"}`}>
              <span className="ah-confirm-icon">{isClosedOs(selectedStatus) ? "!" : "✓"}</span>
              <div><b>OS {selectedOs.numero_os || selectedOs.id} · {selectedOs.cliente_nome || "Cliente não informado"}</b><p>{selectedOs.descricao_servico || "Sem descrição cadastrada"} · {statusLabel(selectedStatus)}</p></div>
              <button type="button" onClick={() => { setSelectedOs(null); setOsQuery(""); }}>Trocar</button>
            </div>
          )}

          <div className="ah-field ah-collaborator-field">
            <label htmlFor="ah-collaborator-search">Colaboradores</label>
            <div className="ah-chip-input">
              {selectedColabs.map((id) => (
                <span className="ah-chip" key={id}>{collaboratorMap.get(id)?.nome ?? "Colaborador"}<button type="button" onClick={() => setSelectedColabs((current) => current.filter((item) => item !== id))} aria-label={`Remover ${collaboratorMap.get(id)?.nome ?? "colaborador"}`}>×</button></span>
              ))}
              <input ref={collaboratorInputRef} id="ah-collaborator-search" value={colabQuery} onChange={(event) => setColabQuery(event.target.value)} placeholder={selectedColabs.length ? "Adicionar outra pessoa…" : "Busque pelo nome"} autoComplete="off" />
              {filteredCollaborators.length > 0 && (
                <div className="ah-options ah-collaborator-options" role="listbox">
                  {filteredCollaborators.map((item) => <button type="button" key={item.id} onClick={() => addCollaborator(item.id)} role="option" aria-selected="false"><b>{item.nome}</b><small>{item.cargo || "Colaborador ativo"}</small></button>)}
                </div>
              )}
            </div>
            <small>Selecione uma ou várias pessoas. O total informado será aplicado a cada uma.</small>
          </div>

          <div className="ah-form-grid">
            <div className="ah-field">
              <label>Data</label>
              <DateInputBR value={date} onChange={setDate} ariaLabel="Data do apontamento" />
              <small className={dateValidation.fechada ? "is-danger" : ""}>{dateValidation.fechada ? dateValidation.motivo : weekdayFormatter.format(localDate(date))}</small>
            </div>
            <div className="ah-field">
              <label htmlFor="ah-hours">Horas por colaborador</label>
              <input ref={hoursInputRef} id="ah-hours" value={hoursText} onChange={(event) => setHoursText(event.target.value)} placeholder="Ex.: 8,5 ou 8h30" inputMode="decimal" />
              <small>{hours != null && hours > 0 ? `${formatHours(hours)} h · ${formatHoursClock(hours)}` : "Aceita decimal ou h:min"}</small>
            </div>
            <div className={`ah-field ah-type-field ${typeIsSpecial ? "is-special" : ""}`}>
              <label htmlFor="ah-type">Tipo de hora</label>
              <select ref={typeSelectRef} id="ah-type" value={typeId} onChange={(event) => { setTypeId(event.target.value); setTypeTouched(true); }}>
                {tiposHoras.map((item) => <option key={item.id} value={item.id}>{item.codigo} — {item.descricao} (×{Number(item.fator).toLocaleString("pt-BR", { minimumFractionDigits: 2 })})</option>)}
              </select>
              <small>{suggestion.reason}{typeTouched ? " Tipo alterado manualmente." : ""}</small>
            </div>
          </div>

          {duplicates.length > 0 && (
            <div className="ah-duplicate-warning">
              <b>Possível duplicidade</b>
              {duplicates.map((item) => <p key={item.id}>{item.colaborador_nome} já tem {formatHours(item.horas)} h lançadas nesta OS em {dateBR(date)}{item.tipo_codigo ? ` (${item.tipo_codigo})` : ""}. <a href={`#apontamento-${item.id}`}>Ver lançamento</a></p>)}
              <small>O aviso não impede salvar, mas confirme se o trabalho não foi lançado antes.</small>
            </div>
          )}

          <div className={`ah-field ${validationAttempted && !description.trim() ? "is-invalid" : ""}`}>
            <label htmlFor="ah-description">Descrição do trabalho</label>
            <input
              ref={descriptionInputRef}
              id="ah-description"
              value={description}
              onChange={(event) => {
                setDescription(event.target.value);
                if (event.target.value.trim()) {
                  setValidationAttempted(false);
                  setMessage(null);
                }
              }}
              placeholder="Ex.: Montagem do painel e passagem de cabos"
              aria-required="true"
              aria-invalid={validationAttempted && !description.trim()}
              aria-describedby={validationAttempted && !description.trim() ? "ah-description-error" : undefined}
              onKeyDown={(event) => {
                if (event.key !== "Enter") return;
                event.preventDefault();
                attemptSaveEntry();
              }}
            />
            {validationAttempted && !description.trim() && <small id="ah-description-error" className="is-danger" role="alert">Informe a descrição do trabalho realizado.</small>}
          </div>

          <div className="ah-save-bar">
            <div>
              <span>RESUMO</span>
              <strong>{selectedColabs.length || 0} colaborador{selectedColabs.length === 1 ? "" : "es"} × {formatHours(hours || 0)} h = {formatHours(totalHoursToCreate)} h</strong>
              <small>{entriesToCreate.length > 1 ? entriesToCreate.map((item) => `${formatHours(item.horas)} h ${item.codigo}`).join(" + ") : selectedType ? `${selectedType.descricao} · ×${Number(selectedType.fator).toLocaleString("pt-BR", { minimumFractionDigits: 2 })}` : "Selecione o tipo de hora"}</small>
            </div>
            <div className="ah-save-action"><span className={missingReason ? "is-missing" : ""} aria-live="polite">{missingReason || "Tudo pronto para salvar"}</span><button type="button" className="ah-button ah-button-primary" disabled={saving} onClick={attemptSaveEntry}>{saving ? "Salvando…" : `Salvar${selectedColabs.length > 1 ? ` ${selectedColabs.length} lançamentos` : ""}`}</button></div>
          </div>
        </section>
      )}

      <section className="ah-card ah-list-card" aria-labelledby="entries-title">
        <div className="ah-list-head">
          <div><span>LANÇAMENTOS</span><h2 id="entries-title">Horas no período</h2><p>{periodLabel} · {formatHours(totalPeriod)} h · {apontamentos.length} lançamento{apontamentos.length === 1 ? "" : "s"}</p></div>
          <button type="button" className="ah-button" onClick={() => void loadEntries()} disabled={loading}>{loading ? "Atualizando…" : "Atualizar"}</button>
        </div>

        <div className="ah-filters">
          <div className="ah-quick-period"><button type="button" onClick={() => { const now = todayISO(); setDateFrom(now); setDateTo(now); }}>Hoje</button><button type="button" onClick={setCurrentMonth}>Este mês</button></div>
          <label><span>De</span><DateInputBR value={dateFrom} onChange={setDateFrom} ariaLabel="Data inicial" /></label>
          <label><span>Até</span><DateInputBR value={dateTo} onChange={setDateTo} ariaLabel="Data final" /></label>
          <label><span>OS</span><select value={filterOs} onChange={(event) => setFilterOs(event.target.value)}><option value="">Todas</option>{filterOsOptions.map((item) => <option key={item.id} value={item.id}>{item.numero_os || item.id}</option>)}</select></label>
          <label><span>Colaborador</span><select value={filterColab} onChange={(event) => setFilterColab(event.target.value)}><option value="">Todos</option>{colaboradores.map((item) => <option key={item.id} value={item.id}>{item.nome}</option>)}</select></label>
          <label><span>Tipo</span><select value={filterType} onChange={(event) => setFilterType(event.target.value)}><option value="">Todos</option>{tiposHoras.map((item) => <option key={item.id} value={item.id}>{item.codigo}</option>)}</select></label>
          <label className="ah-search-filter"><span>Buscar</span><input value={filterSearchInput} onChange={(event) => setFilterSearchInput(event.target.value)} placeholder="OS, cliente ou descrição" /></label>
        </div>

        <div className="ah-entry-list" aria-busy={loading}>
          {loading && apontamentos.length === 0 && <div className="ah-empty">Carregando apontamentos…</div>}
          {!loading && groupedEntries.length === 0 && <div className="ah-empty"><b>Nenhum apontamento no período.</b><span>Ajuste os filtros ou registre um novo lançamento acima.</span></div>}
          {groupedEntries.map(([groupDate, rows]) => {
            const groupTotal = rows.reduce((sum, row) => sum + Number(row.horas || 0), 0);
            return (
              <div className="ah-day-group" key={groupDate}>
                <div className="ah-day-header"><strong>{dateLongFormatter.format(localDate(groupDate))}</strong><span>{formatHours(groupTotal)} h · {rows.length} lançamento{rows.length === 1 ? "" : "s"}</span></div>
                {rows.map((row) => {
                  const podeEditar = canWrite && podeEditarApontamento(row, papelEmpresa, meuColaboradorId);
                  const podeExcluir = canWrite && podeExcluirApontamento(row, meuColaboradorId);
                  return <article id={`apontamento-${row.id}`} className={`ah-entry ${newIds.has(row.id) ? "is-new" : ""}`} key={row.id}>
                    <div className="ah-entry-person"><b>{row.colaborador_nome}</b><small>{row.criado_por_nome ? `Lançado por ${row.criado_por_nome}` : "Autor não identificado"}{row.gerado_por_hh ? " · Origem HH" : ""}</small></div>
                    <div className="ah-entry-hours"><b>{formatHours(row.horas)} h</b><small>{formatHoursClock(row.horas)}</small></div>
                    <div className="ah-entry-type"><span className={(row.tipo_codigo || "NORMAL") === "NORMAL" ? "is-normal" : "is-extra"}>{row.tipo_codigo || "NORMAL"}</span><small>×{Number(row.fator_aplicado || 1).toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</small></div>
                    <div className="ah-entry-work"><b>OS {row.numero_os || row.os_id} · {row.cliente_nome || "Cliente não informado"}</b><small>{row.descricao || row.descricao_servico || "Sem descrição"}</small></div>
                    <div className="ah-entry-status"><span>{row.status_aprovacao === "aprovado" ? "Aprovado" : row.status_aprovacao === "rejeitado" ? "Devolvido" : "Pendente"}</span></div>
                    {canWrite && (row.gerado_por_hh || podeEditar || podeExcluir) && <div className="ah-row-actions">{row.gerado_por_hh ? <Link href={`/os/${row.os_id}`}>Abrir OS</Link> : <>{podeEditar && <button type="button" onClick={() => openEdit(row)}>Editar</button>}{podeExcluir && <button type="button" onClick={() => setDeleteTarget(row)}>Excluir</button>}</>}</div>}
                  </article>
                })}
              </div>
            );
          })}
        </div>
      </section>

      {editing && (
        <div className="ah-dialog-backdrop" role="presentation">
          <div className="ah-dialog" role="dialog" aria-modal="true" aria-labelledby="edit-title">
            <div className="ah-dialog-head"><div><span>EDITAR LANÇAMENTO</span><h2 id="edit-title">{editing.colaborador_nome} · OS {editing.numero_os || editing.os_id}</h2></div><button type="button" onClick={() => setEditing(null)} aria-label="Fechar">×</button></div>
            <div className="ah-dialog-body">
              <div className="ah-form-grid">
                <div className="ah-field"><label>Data</label><DateInputBR value={editDate} onChange={setEditDate} ariaLabel="Data do apontamento em edição" /></div>
                <div className="ah-field"><label htmlFor="edit-hours">Horas</label><input id="edit-hours" value={editHours} onChange={(event) => setEditHours(event.target.value)} /></div>
                <div className="ah-field"><label htmlFor="edit-type">Tipo</label><select id="edit-type" value={editType} onChange={(event) => setEditType(event.target.value)}>{tiposHoras.map((item) => <option key={item.id} value={item.id}>{item.codigo} — {item.descricao}</option>)}</select></div>
              </div>
              <div className="ah-field"><label htmlFor="edit-description">Descrição</label><input id="edit-description" value={editDescription} onChange={(event) => setEditDescription(event.target.value)} /></div>
              {(editing.entrada_1 || editing.saida_1 || editing.entrada_2 || editing.saida_2) && <div className="ah-message is-info">Este registro possui horários de entrada e saída históricos. Esta edição altera o total, a data, o tipo e a descrição; os horários originais são preservados.</div>}
            </div>
            <div className="ah-dialog-actions"><button type="button" className="ah-button" onClick={() => setEditing(null)}>Cancelar</button><button type="button" className="ah-button ah-button-primary" disabled={saving} onClick={() => void saveEdit()}>{saving ? "Salvando…" : "Salvar alterações"}</button></div>
          </div>
        </div>
      )}

      {deleteTarget && (
        <div className="ah-dialog-backdrop" role="presentation">
          <div className="ah-dialog" role="dialog" aria-modal="true" aria-labelledby="delete-title">
            <div className="ah-dialog-head"><div><span>CONFIRMAR EXCLUSÃO</span><h2 id="delete-title">Excluir este apontamento?</h2></div><button type="button" onClick={() => setDeleteTarget(null)} aria-label="Fechar">×</button></div>
            <div className="ah-dialog-body"><p>Será excluído o lançamento de <b>{formatHours(deleteTarget.horas)} h</b> de <b>{deleteTarget.colaborador_nome}</b>, na OS <b>{deleteTarget.numero_os || deleteTarget.os_id}</b>, em <b>{dateBR(deleteTarget.data)}</b>.</p><small>A exclusão registra usuário, data e conteúdo anterior na auditoria.</small></div>
            <div className="ah-dialog-actions"><button type="button" className="ah-button" onClick={() => setDeleteTarget(null)}>Cancelar</button><button type="button" className="ah-button ah-button-primary" disabled={saving} onClick={() => void deleteEntry()}>{saving ? "Excluindo…" : "Confirmar exclusão"}</button></div>
          </div>
        </div>
      )}
    </main>
  );
}
