export type HHSegment = { data: string; horas: number };

function assertISODate(dateISO: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateISO)) {
    throw new Error(`Data inválida: "${dateISO}". Use YYYY-MM-DD.`);
  }
}

export function parseHHMMToMinutes(hhmm: string): number {
  const raw = String(hhmm ?? "").trim();
  const m = raw.match(/^(\d{2}):(\d{2})$/);
  if (!m) throw new Error(`Hora inválida: "${raw}". Use HH:MM.`);
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) throw new Error(`Hora inválida: "${raw}".`);
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) throw new Error(`Hora inválida: "${raw}".`);
  return hh * 60 + mm;
}

export function minutesToHours2(min: number): number {
  const n = Number(min ?? 0);
  if (!Number.isFinite(n)) throw new Error(`Minutos inválidos: "${String(min)}".`);
  return Math.round((n / 60) * 100) / 100;
}

export function addDaysISO(dateISO: string, days: number): string {
  assertISODate(dateISO);
  const d = new Date(`${dateISO}T00:00:00`);
  d.setDate(d.getDate() + Number(days ?? 0));
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

/**
 * Divide um período (inicio->fim) em 1 ou 2 segmentos quando há virada do dia.
 * - se fim >= inicio => [{data: dateISO, horas}]
 * - se fim < inicio => [{dateISO, horas: inicio->00:00}, {dateISO+1, horas: 00:00->fim}]
 */
export function splitPeriodo(dateISO: string, inicio: string, fim: string): HHSegment[] {
  assertISODate(dateISO);
  const ini = parseHHMMToMinutes(inicio);
  const end = parseHHMMToMinutes(fim);

  if (end >= ini) {
    const horas = minutesToHours2(end - ini);
    return horas > 0 ? [{ data: dateISO, horas }] : [];
  }

  const seg1Min = 1440 - ini;
  const seg2Min = end;
  const seg1 = minutesToHours2(seg1Min);
  const seg2 = minutesToHours2(seg2Min);
  const nextDate = addDaysISO(dateISO, 1);

  const out: HHSegment[] = [];
  if (seg1 > 0) out.push({ data: dateISO, horas: seg1 });
  if (seg2 > 0) out.push({ data: nextDate, horas: seg2 });
  return out;
}

function toNull(v: string | null | undefined): string | null {
  const s = String(v ?? "").trim();
  return s ? s : null;
}

/**
 * Calcula os segmentos (por dia) a partir de 1..N períodos (entrada/saida).
 * - ignora períodos incompletos (sem entrada ou sem saida)
 * - soma (merge) por data e ordena por data
 */
export function computeHHSegments(
  dateISO: string,
  periodos: Array<{ entrada?: string | null; saida?: string | null }>
): HHSegment[] {
  assertISODate(dateISO);

  const merged = new Map<string, number>();
  for (const p of periodos ?? []) {
    const entrada = toNull(p?.entrada ?? null);
    const saida = toNull(p?.saida ?? null);
    if (!entrada || !saida) continue;

    for (const seg of splitPeriodo(dateISO, entrada, saida)) {
      merged.set(seg.data, (merged.get(seg.data) ?? 0) + Number(seg.horas ?? 0));
    }
  }

  return Array.from(merged.entries())
    .map(([data, horas]) => ({ data, horas: Math.round(horas * 100) / 100 }))
    .filter((s) => s.horas > 0)
    .sort((a, b) => a.data.localeCompare(b.data));
}

