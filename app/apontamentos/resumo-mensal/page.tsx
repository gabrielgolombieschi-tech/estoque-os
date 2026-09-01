"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { getDiasUteisJoinville } from "@/lib/datas/feriadosJoinville";
import { supabaseBrowser } from "@/lib/supabase/client";

type Colaborador = {
  id: string;
  nome: string;
  ativo: boolean;
};

type ApontamentoRow = {
  data: string;
  os_id: number;
  colaborador_id: string;
  horas: number | string | null;
};

type OsInfo = {
  id: number;
  numero_os: string;
  cliente_nome: string;
  descricao_servico: string;
  usa_relatorio_hh: boolean;
};

type TipoOsFilter = "todos" | "os_hh";
type ActiveTab = "resumo" | "extrato";
type SortOrder = "horas" | "nome" | "dias";

type LancamentoDia = {
  data: string;
  os_id: number;
  numero_os: string;
  cliente_nome: string;
  descricao_servico: string;
  total_horas: number;
};

type TimelineDia = {
  data: string;
  sem_apontamento: boolean;
  total_horas: number;
  lancamentos: LancamentoDia[];
};

type ResumoRow = {
  colaborador_id: string;
  colaborador_nome: string;
  total_horas: number;
  dias_apontados: number;
  media_dia: number;
  dias_sem_apontamento: number;
  os_distintas: number;
  timeline: TimelineDia[];
};

const MONTHS = [
  "Janeiro",
  "Fevereiro",
  "Março",
  "Abril",
  "Maio",
  "Junho",
  "Julho",
  "Agosto",
  "Setembro",
  "Outubro",
  "Novembro",
  "Dezembro",
];

const TITLE_CASE_LOWER = new Set(["da", "das", "de", "do", "dos", "e"]);

function numeric(value: unknown) {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function round2(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function startOfMonthISO(year: number, month: number) {
  return `${year}-${String(month).padStart(2, "0")}-01`;
}

function endOfMonthISO(year: number, month: number) {
  return `${year}-${String(month).padStart(2, "0")}-${String(new Date(year, month, 0, 12).getDate()).padStart(2, "0")}`;
}

function describeSupabaseError(error: unknown) {
  if (!error) return "sem detalhes";
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (typeof error !== "object") return String(error);
  const candidate = error as { message?: unknown; details?: unknown; hint?: unknown; code?: unknown };
  return [candidate.message, candidate.details, candidate.hint, candidate.code ? `code=${candidate.code}` : null]
    .filter(Boolean)
    .map(String)
    .join(" | ");
}

function titleCase(value: string) {
  return value
    .trim()
    .toLocaleLowerCase("pt-BR")
    .split(/(\s+|-)/)
    .map((part, index) => {
      if (/^(\s+|-)$/.test(part)) return part;
      if (index > 0 && TITLE_CASE_LOWER.has(part)) return part;
      return part ? `${part.charAt(0).toLocaleUpperCase("pt-BR")}${part.slice(1)}` : part;
    })
    .join("");
}

function normalizeSearch(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("pt-BR")
    .trim();
}

function formatHoras(value: number) {
  return new Intl.NumberFormat("pt-BR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

function formatHoraMinuto(value: number) {
  const totalMinutes = Math.round(value * 60);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h${String(minutes).padStart(2, "0")}`;
}

function formatDateShort(value: string) {
  return new Date(`${value}T12:00:00`).toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
  });
}

function formatDayHeader(value: string) {
  const date = new Date(`${value}T12:00:00`);
  const weekday = date.toLocaleDateString("pt-BR", { weekday: "long" });
  return `${formatDateShort(value)} · ${weekday}`;
}

function parseOpenIds(value: string | null) {
  return new Set((value ?? "").split(",").map((item) => item.trim()).filter(Boolean));
}

function downloadCsv(filename: string, lines: Array<Array<string | number>>) {
  const csv = lines
    .map((line) =>
      line
        .map((cell) => `"${String(cell ?? "").replace(/"/g, '""')}"`)
        .join(";")
    )
    .join("\r\n");
  const blob = new Blob(["\ufeff", csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
}

function buildTimeline(
  apontamentos: ApontamentoRow[],
  osById: Map<number, OsInfo>,
  businessDates: string[]
): TimelineDia[] {
  const grouped = new Map<string, LancamentoDia>();

  for (const apontamento of apontamentos) {
    const date = String(apontamento.data ?? "").slice(0, 10);
    const osId = Number(apontamento.os_id);
    if (!date || !Number.isFinite(osId)) continue;
    const os = osById.get(osId);
    if (!os) continue;
    const key = `${date}|${osId}`;
    const current = grouped.get(key);
    grouped.set(key, {
      data: date,
      os_id: osId,
      numero_os: os.numero_os || String(osId),
      cliente_nome: os.cliente_nome || "—",
      descricao_servico: os.descricao_servico || "—",
      total_horas: round2((current?.total_horas ?? 0) + numeric(apontamento.horas)),
    });
  }

  const recordsByDate = new Map<string, LancamentoDia[]>();
  for (const row of grouped.values()) {
    const current = recordsByDate.get(row.data) ?? [];
    current.push(row);
    recordsByDate.set(row.data, current);
  }

  const dates = new Set([...businessDates, ...recordsByDate.keys()]);
  return Array.from(dates)
    .sort((a, b) => a.localeCompare(b))
    .map((date) => {
      const lancamentos = (recordsByDate.get(date) ?? []).sort((a, b) =>
        a.numero_os.localeCompare(b.numero_os, "pt-BR", { numeric: true })
      );
      return {
        data: date,
        sem_apontamento: lancamentos.length === 0,
        total_horas: round2(lancamentos.reduce((sum, row) => sum + row.total_horas, 0)),
        lancamentos,
      };
    });
}

function ExtratoContent({
  row,
  fullPage = false,
  onFullPage,
  onExport,
}: {
  row: ResumoRow;
  fullPage?: boolean;
  onFullPage?: () => void;
  onExport: () => void;
}) {
  const [showAll, setShowAll] = useState(fullPage);
  const visible = fullPage || showAll ? row.timeline : row.timeline.slice(0, 5);
  const remaining = Math.max(0, row.timeline.length - visible.length);

  return (
    <div className={fullPage ? "rh-extract-full" : "rh-extract-inline"}>
      <div className="grid grid-cols-2 gap-2 p-3 sm:grid-cols-5">
        {[
          ["Dias apontados", String(row.dias_apontados)],
          ["Total no mês", `${formatHoras(row.total_horas)} h`],
          ["Média por dia", `${formatHoras(row.media_dia)} h`],
          ["Dias úteis sem apontamento", String(row.dias_sem_apontamento)],
          ["OS distintas", String(row.os_distintas)],
        ].map(([label, value], index) => (
          <div key={label} className={`rh-mini-stat ${index === 3 && row.dias_sem_apontamento > 0 ? "is-warning" : ""}`}>
            <span>{label}</span>
            <strong>{value}</strong>
          </div>
        ))}
      </div>

      <div className="rh-timeline">
        {visible.length === 0 ? (
          <div className="rh-empty">Nenhum apontamento encontrado no período.</div>
        ) : (
          visible.map((day) => (
            <section key={day.data} className={`rh-day ${day.sem_apontamento ? "is-missing" : ""}`}>
              <div className="rh-day-header">
                <span>{formatDayHeader(day.data)}</span>
                {day.sem_apontamento ? (
                  <strong>Sem apontamento</strong>
                ) : (
                  <span className="rh-hour-pair is-inline">
                    <strong>{formatHoras(day.total_horas)}</strong>
                    <small>{formatHoraMinuto(day.total_horas)}</small>
                  </span>
                )}
              </div>
              {!day.sem_apontamento && (
                <div className="rh-day-lines">
                  {day.lancamentos.map((entry) => (
                    <div key={`${day.data}-${entry.os_id}`} className="rh-day-line">
                      <Link href={`/os/${entry.os_id}`} onClick={(event) => event.stopPropagation()}>
                        OS {entry.numero_os}
                      </Link>
                      <span title={entry.cliente_nome}>{entry.cliente_nome}</span>
                      <span title={entry.descricao_servico}>{entry.descricao_servico}</span>
                      <span className="rh-hour-pair">
                        <strong>{formatHoras(entry.total_horas)}</strong>
                        <small>{formatHoraMinuto(entry.total_horas)}</small>
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </section>
          ))
        )}
      </div>

      <div className="rh-extract-footer">
        {!fullPage && row.timeline.length > 5 && (
          <button type="button" onClick={() => setShowAll((current) => !current)}>
            {showAll ? "Mostrar menos" : `Ver os outros ${remaining} dias`}
          </button>
        )}
        {!fullPage && onFullPage && (
          <button type="button" onClick={onFullPage}>Abrir folha completa</button>
        )}
        <button type="button" onClick={onExport}>Exportar</button>
        {fullPage && <button type="button" onClick={() => window.print()}>Imprimir</button>}
      </div>
    </div>
  );
}

export default function ApontamentosResumoMensalPage() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;
  const supabase = useMemo(() => supabaseBrowser(), []);
  const today = useMemo(() => new Date(), []);

  const parsedYear = Number(searchParams.get("ano"));
  const parsedMonth = Number(searchParams.get("mes"));
  const [year, setYear] = useState(Number.isInteger(parsedYear) && parsedYear > 2000 ? parsedYear : today.getFullYear());
  const [month, setMonth] = useState(parsedMonth >= 1 && parsedMonth <= 12 ? parsedMonth : today.getMonth() + 1);
  const [colaboradorId, setColaboradorId] = useState(searchParams.get("colaborador") ?? "");
  const [tipo, setTipo] = useState<TipoOsFilter>(searchParams.get("tipo") === "os_hh" ? "os_hh" : "todos");
  const [order, setOrder] = useState<SortOrder>(
    searchParams.get("ordem") === "nome" || searchParams.get("ordem") === "dias"
      ? (searchParams.get("ordem") as SortOrder)
      : "horas"
  );
  const [activeTab, setActiveTab] = useState<ActiveTab>(searchParams.get("aba") === "extrato" ? "extrato" : "resumo");
  const [search, setSearch] = useState(searchParams.get("q") ?? "");
  const [openIds, setOpenIds] = useState<Set<string>>(() => parseOpenIds(searchParams.get("aberto")));

  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [apontamentos, setApontamentos] = useState<ApontamentoRow[]>([]);
  const [osById, setOsById] = useState<Map<number, OsInfo>>(new Map());
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("ano", String(year));
    params.set("mes", String(month));
    params.set("tipo", tipo);
    params.set("ordem", order);
    params.set("aba", activeTab);
    if (colaboradorId) params.set("colaborador", colaboradorId);
    else params.delete("colaborador");
    if (search.trim()) params.set("q", search.trim());
    else params.delete("q");
    if (openIds.size) params.set("aberto", Array.from(openIds).join(","));
    else params.delete("aberto");
    const next = params.toString();
    if (next !== searchParams.toString()) router.replace(`${pathname}?${next}`, { scroll: false });
  }, [activeTab, colaboradorId, month, openIds, order, pathname, router, search, searchParams, tipo, year]);

  const ensureContext = useCallback(async () => {
    if (!tenantId || !empresaId) return;
    const tenantContext = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
    if (tenantContext.error) throw tenantContext.error;
    const empresaContext = await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
    if (empresaContext.error) throw empresaContext.error;
  }, [empresaId, supabase, tenantId]);

  const load = useCallback(async () => {
    if (!tenantId || !empresaId) return;
    setLoading(true);
    setError(null);
    try {
      await ensureContext();
      const start = startOfMonthISO(year, month);
      const end = endOfMonthISO(year, month);

      const collaboratorsPromise = applyTenantEmpresa(
        supabase
          .from("colaboradores")
          .select("id,nome,ativo")
          .eq("empresa_id", empresaId)
          .order("nome"),
        tenantId,
        empresaId
      );

      const allPoints: ApontamentoRow[] = [];
      let page = 0;
      const pageSize = 1000;
      while (true) {
        const response = await applyTenantEmpresa(
          supabase
            .from("apontamentos_horas")
            .select("data,os_id,colaborador_id,horas")
            .eq("empresa_id", empresaId)
            .gte("data", start)
            .lte("data", end)
            .order("data", { ascending: true })
            .order("colaborador_id", { ascending: true })
            .order("os_id", { ascending: true })
            .range(page * pageSize, page * pageSize + pageSize - 1),
          tenantId,
          empresaId
        );
        if (response.error) throw response.error;
        const batch = (response.data ?? []) as unknown as ApontamentoRow[];
        allPoints.push(...batch);
        if (batch.length < pageSize) break;
        page += 1;
      }

      const collaboratorsResponse = await collaboratorsPromise;
      if (collaboratorsResponse.error) throw collaboratorsResponse.error;

      const uniqueOsIds = Array.from(new Set(allPoints.map((row) => Number(row.os_id)).filter(Number.isFinite)));
      const loadedOs = new Map<number, OsInfo>();
      for (let index = 0; index < uniqueOsIds.length; index += 200) {
        const ids = uniqueOsIds.slice(index, index + 200);
        const response = await applyTenantEmpresa(
          supabase
            .from("ordens_servico")
            .select("id,numero_os,cliente_nome,descricao_servico,usa_relatorio_hh")
            .eq("empresa_id", empresaId)
            .eq("tipo_documento", "OS")
            .in("id", ids),
          tenantId,
          empresaId
        );
        if (response.error) throw response.error;
        for (const raw of response.data ?? []) {
          loadedOs.set(Number(raw.id), {
            id: Number(raw.id),
            numero_os: String(raw.numero_os ?? raw.id),
            cliente_nome: String(raw.cliente_nome ?? "—"),
            descricao_servico: String(raw.descricao_servico ?? "—"),
            usa_relatorio_hh: Boolean(raw.usa_relatorio_hh),
          });
        }
      }

      setColaboradores((collaboratorsResponse.data ?? []) as Colaborador[]);
      setApontamentos(allPoints);
      setOsById(loadedOs);
    } catch (loadError) {
      console.error("[Resumo de horas] falha ao carregar", loadError);
      setColaboradores([]);
      setApontamentos([]);
      setOsById(new Map());
      setError(`Erro ao carregar o resumo de horas: ${describeSupabaseError(loadError)}`);
    } finally {
      setLoading(false);
    }
  }, [empresaId, ensureContext, month, supabase, tenantId, year]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const isCurrentMonth = year === today.getFullYear() && month === today.getMonth() + 1;
  const isPastMonth = year < today.getFullYear() || (year === today.getFullYear() && month < today.getMonth() + 1);
  const elapsedThrough = isCurrentMonth ? today.getDate() : isPastMonth ? undefined : 0;
  const businessDates = useMemo(
    () => getDiasUteisJoinville(year, month, elapsedThrough),
    [elapsedThrough, month, year]
  );
  const fullBusinessDates = useMemo(() => getDiasUteisJoinville(year, month), [month, year]);

  const filteredPoints = useMemo(() => {
    if (tipo === "todos") return apontamentos.filter((row) => osById.has(Number(row.os_id)));
    return apontamentos.filter((row) => osById.get(Number(row.os_id))?.usa_relatorio_hh);
  }, [apontamentos, osById, tipo]);

  const allResumoRows = useMemo(() => {
    const nameById = new Map(colaboradores.map((row) => [row.id, row.nome]));
    const pointsByCollaborator = new Map<string, ApontamentoRow[]>();
    for (const point of filteredPoints) {
      const current = pointsByCollaborator.get(point.colaborador_id) ?? [];
      current.push(point);
      pointsByCollaborator.set(point.colaborador_id, current);
    }

    return Array.from(pointsByCollaborator.entries()).map(([id, points]) => {
      const timeline = buildTimeline(points, osById, businessDates);
      const pointedDates = new Set(points.map((point) => String(point.data).slice(0, 10)));
      const total = round2(points.reduce((sum, point) => sum + numeric(point.horas), 0));
      const pointedDays = pointedDates.size;
      return {
        colaborador_id: id,
        colaborador_nome: nameById.get(id) ?? id,
        total_horas: total,
        dias_apontados: pointedDays,
        media_dia: pointedDays ? round2(total / pointedDays) : 0,
        dias_sem_apontamento: timeline.filter((day) => day.sem_apontamento).length,
        os_distintas: new Set(points.map((point) => Number(point.os_id))).size,
        timeline,
      } satisfies ResumoRow;
    });
  }, [businessDates, colaboradores, filteredPoints, osById]);

  const visibleRows = useMemo(() => {
    const normalized = normalizeSearch(search);
    const rows = allResumoRows.filter((row) => {
      if (colaboradorId && row.colaborador_id !== colaboradorId) return false;
      return !normalized || normalizeSearch(row.colaborador_nome).includes(normalized);
    });
    return rows.sort((a, b) => {
      if (order === "nome") return a.colaborador_nome.localeCompare(b.colaborador_nome, "pt-BR");
      if (order === "dias") return b.dias_apontados - a.dias_apontados || b.total_horas - a.total_horas;
      return b.total_horas - a.total_horas || a.colaborador_nome.localeCompare(b.colaborador_nome, "pt-BR");
    });
  }, [allResumoRows, colaboradorId, order, search]);

  const totalHours = useMemo(() => round2(visibleRows.reduce((sum, row) => sum + row.total_horas, 0)), [visibleRows]);
  const averageHours = visibleRows.length ? round2(totalHours / visibleRows.length) : 0;
  const maxHours = Math.max(0, ...visibleRows.map((row) => row.total_horas));
  const visibleCollaboratorIds = useMemo(
    () => new Set(visibleRows.map((row) => row.colaborador_id)),
    [visibleRows]
  );
  const distinctOs = useMemo(
    () => new Set(filteredPoints.filter((row) => visibleCollaboratorIds.has(row.colaborador_id)).map((row) => row.os_id)).size,
    [filteredPoints, visibleCollaboratorIds]
  );
  const selectedRow = useMemo(
    () => allResumoRows.find((row) => row.colaborador_id === colaboradorId) ?? null,
    [allResumoRows, colaboradorId]
  );

  const years = useMemo(() => {
    const values: number[] = [];
    for (let value = today.getFullYear() - 6; value <= today.getFullYear() + 1; value += 1) values.push(value);
    return values;
  }, [today]);

  const updateMonth = (value: string) => {
    const [nextYear, nextMonth] = value.split("-").map(Number);
    setYear(nextYear);
    setMonth(nextMonth);
  };

  const toggleRow = (id: string) => {
    setOpenIds((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const openFullPage = (id: string) => {
    setColaboradorId(id);
    setActiveTab("extrato");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const exportCollaborator = (row: ResumoRow) => {
    const lines: Array<Array<string | number>> = [["Data", "OS", "Cliente", "Serviço", "Horas decimais", "Horas (h:min)"]];
    for (const day of row.timeline) {
      if (day.sem_apontamento) {
        lines.push([day.data, "", "", "Sem apontamento", "", ""]);
      } else {
        for (const entry of day.lancamentos) {
          lines.push([
            day.data,
            entry.numero_os,
            entry.cliente_nome,
            entry.descricao_servico,
            formatHoras(entry.total_horas),
            formatHoraMinuto(entry.total_horas),
          ]);
        }
      }
    }
    downloadCsv(`extrato-horas-${normalizeSearch(row.colaborador_nome).replace(/\s+/g, "-")}-${year}-${String(month).padStart(2, "0")}.csv`, lines);
  };

  const exportCurrent = () => {
    if (activeTab === "extrato" && selectedRow) {
      exportCollaborator(selectedRow);
      return;
    }
    downloadCsv(
      `resumo-horas-${year}-${String(month).padStart(2, "0")}.csv`,
      [
        ["Colaborador", "Dias apontados", "Dias úteis decorridos", "Total (h)", "Média por dia", "OS distintas"],
        ...visibleRows.map((row) => [
          row.colaborador_nome,
          row.dias_apontados,
          businessDates.length,
          formatHoras(row.total_horas),
          formatHoras(row.media_dia),
          row.os_distintas,
        ]),
        ["Total da equipe", "", "", formatHoras(totalHours), "", distinctOs],
      ]
    );
  };

  const monthLabel = `${MONTHS[month - 1]} de ${year}`;

  return (
    <div className="carteira-theme resumo-horas-page w-full space-y-3">
      <header className="rh-page-header">
        <div>
          <div className="rh-breadcrumb"><span>Apontamentos</span><b>›</b><strong>Resumo de horas</strong></div>
          <h1>Resumo de horas</h1>
          <p>
            {monthLabel} · {businessDates.length} de {fullBusinessDates.length} dias úteis transcorridos · horas aplicadas em OS
          </p>
        </div>
        <div className="rh-page-actions">
          <button type="button" className="carteira-button" onClick={exportCurrent}>Exportar CSV</button>
          <button type="button" className="carteira-button" onClick={() => void load()} disabled={loading}>
            {loading ? "Atualizando..." : "Atualizar"}
          </button>
        </div>
      </header>

      <nav className="rh-tabs" aria-label="Visões do resumo de horas">
        <button type="button" className={activeTab === "resumo" ? "is-active" : ""} onClick={() => setActiveTab("resumo")}>Resumo</button>
        <button type="button" className={activeTab === "extrato" ? "is-active" : ""} onClick={() => setActiveTab("extrato")}>Extrato</button>
      </nav>

      <div className="rh-filter-bar">
        <label className="rh-search-pill">
          <span aria-hidden="true">⌕</span>
          <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar colaborador" />
        </label>
        <select className="carteira-control rh-filter-pill" value={`${year}-${month}`} onChange={(event) => updateMonth(event.target.value)} aria-label="Mês e ano">
          {years.flatMap((optionYear) => MONTHS.map((name, index) => (
            <option key={`${optionYear}-${index + 1}`} value={`${optionYear}-${index + 1}`}>{name} {optionYear}</option>
          )))}
        </select>
        <select className="carteira-control rh-filter-pill" value={colaboradorId} onChange={(event) => setColaboradorId(event.target.value)} aria-label="Colaborador">
          <option value="">Todos os colaboradores</option>
          {colaboradores.map((collaborator) => <option key={collaborator.id} value={collaborator.id}>{titleCase(collaborator.nome)}</option>)}
        </select>
        <select className="carteira-control rh-filter-pill" value={tipo} onChange={(event) => setTipo(event.target.value as TipoOsFilter)} aria-label="Tipo de OS">
          <option value="todos">Todos os tipos de OS</option>
          <option value="os_hh">Somente OS HH</option>
        </select>
        <select className="carteira-control rh-filter-pill rh-order-pill" value={order} onChange={(event) => setOrder(event.target.value as SortOrder)} aria-label="Ordenação">
          <option value="horas">Ordenar: horas</option>
          <option value="nome">Ordenar: nome A–Z</option>
          <option value="dias">Ordenar: dias apontados</option>
        </select>
      </div>

      {error && <div className="rh-error" role="alert">{error}</div>}

      <section className="rh-stats" aria-label="Indicadores do período">
        <article>
          <span>Horas apontadas</span>
          <strong>{formatHoras(totalHours)} h</strong>
          <small>{visibleRows.length} colaborador(es) · média {formatHoras(averageHours)} h</small>
        </article>
        <article>
          <span>Dias úteis oficiais</span>
          <strong>{businessDates.length} / {fullBusinessDates.length}</strong>
          <small>{isCurrentMonth ? `Até ${today.toLocaleDateString("pt-BR")}` : isPastMonth ? "Período fechado" : "Período futuro"}</small>
        </article>
        <article>
          <span>Colaboradores com registro</span>
          <strong>{visibleRows.length}</strong>
          <small>No recorte atual</small>
        </article>
        <article>
          <span>OS distintas</span>
          <strong>{distinctOs}</strong>
          <small>Horas aplicadas em OS · cobertura não calculada</small>
        </article>
      </section>

      <div className="rh-scope-note">
        Este painel confere horas vinculadas a ordens de serviço. Não compara os registros com a jornada contratual, férias ou afastamentos.
      </div>

      {activeTab === "resumo" ? (
        <section className="rh-list-shell">
          <div className="rh-list-scroll">
            <div className="rh-list-grid rh-list-head">
              <button type="button" onClick={() => setOrder("nome")}>Colaborador</button>
              <button type="button" onClick={() => setOrder("dias")}>Dias apontados</button>
              <span>Horas no período</span>
              <button type="button" onClick={() => setOrder("horas")}>Total (h)</button>
              <span aria-hidden="true" />
            </div>

            {loading ? (
              <div className="rh-empty">Carregando resumo de horas...</div>
            ) : visibleRows.length === 0 ? (
              <div className="rh-empty">Nenhum apontamento encontrado para os filtros selecionados.</div>
            ) : (
              visibleRows.map((row) => {
                const open = openIds.has(row.colaborador_id);
                const percentage = maxHours > 0 ? Math.max(2, (row.total_horas / maxHours) * 100) : 0;
                return (
                  <div key={row.colaborador_id} className="rh-person-block">
                    <button
                      type="button"
                      className={`rh-list-grid rh-person-row ${open ? "is-open" : ""}`}
                      onClick={() => toggleRow(row.colaborador_id)}
                      aria-expanded={open}
                    >
                      <strong title={row.colaborador_nome}>{titleCase(row.colaborador_nome)}</strong>
                      <span className="rh-days-value"><b>{row.dias_apontados}</b><i>/ {businessDates.length}</i></span>
                      <span className="rh-hours-track"><i style={{ width: `${percentage}%` }} /></span>
                      <span className="rh-hour-pair">
                        <strong>{formatHoras(row.total_horas)}</strong>
                        <small>{formatHoraMinuto(row.total_horas)}</small>
                      </span>
                      <span className={`rh-chevron ${open ? "is-open" : ""}`}>›</span>
                    </button>
                    {open && (
                      <ExtratoContent
                        row={row}
                        onFullPage={() => openFullPage(row.colaborador_id)}
                        onExport={() => exportCollaborator(row)}
                      />
                    )}
                  </div>
                );
              })
            )}
          </div>

          {!loading && visibleRows.length > 0 && (
            <footer className="rh-team-total">
              <span>Total da equipe · {visibleRows.length} colaborador(es)</span>
              <strong>{formatHoras(totalHours)} h</strong>
            </footer>
          )}
        </section>
      ) : !colaboradorId ? (
        <section className="rh-select-empty">
          <strong>Selecione um colaborador</strong>
          <span>Use a busca ou o filtro acima para abrir a folha completa do período.</span>
        </section>
      ) : loading ? (
        <div className="rh-empty rh-bordered">Carregando extrato...</div>
      ) : selectedRow ? (
        <section className="rh-full-sheet">
          <div className="rh-full-sheet-head">
            <div>
              <span>Folha de apontamentos</span>
              <h2>{titleCase(selectedRow.colaborador_nome)}</h2>
              <p>{monthLabel} · {tipo === "os_hh" ? "Somente OS HH" : "Todos os tipos de OS"}</p>
            </div>
          </div>
          <ExtratoContent row={selectedRow} fullPage onExport={() => exportCollaborator(selectedRow)} />
        </section>
      ) : (
        <section className="rh-select-empty">
          <strong>Sem apontamentos no recorte</strong>
          <span>O colaborador selecionado não possui horas nos filtros atuais.</span>
        </section>
      )}
    </div>
  );
}
