export type HhLancamentoCalcRow = {
  os_id?: number | string | null;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  hora_entrada?: string | null;
  hora_saida?: string | null;
  horas_trabalhadas?: number | string | null;
  percentual_aplicado?: number | string | null;
  tem_extra_50?: boolean | null;
  horas_extra_50?: number | string | null;
  tem_extra_100?: boolean | null;
  horas_extra_100?: number | string | null;
  valor_hora?: number | string | null;
  valor_total?: number | string | null;
};

function formatTimeHHMM(value: string | null | undefined): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  if (/^\d{2}:\d{2}/.test(raw)) return raw.slice(0, 5);
  return raw;
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

function calcHorasDecimalFromMinutes(inicioMin: number, fimMin: number): number {
  let diff = fimMin - inicioMin;
  if (diff < 0) diff = 1440 - inicioMin + fimMin;
  return Number((diff / 60).toFixed(2));
}

export function getHorasTrabalhadasEfetivas(row: HhLancamentoCalcRow): number {
  const e1 = formatTimeHHMM(row.entrada_1) || formatTimeHHMM(row.hora_entrada);
  const s1 = formatTimeHHMM(row.saida_1) || formatTimeHHMM(row.hora_saida);
  const e2 = formatTimeHHMM(row.entrada_2);
  const s2 = formatTimeHHMM(row.saida_2);

  if (e1 && s1 && e2 && s2) {
    const e1Min = parseHHMM(e1);
    const s1Min = parseHHMM(s1);
    const e2Min = parseHHMM(e2);
    const s2Min = parseHHMM(s2);
    if (e1Min !== null && s1Min !== null && e2Min !== null && s2Min !== null) {
      return Number(
        (calcHorasDecimalFromMinutes(e1Min, s1Min) + calcHorasDecimalFromMinutes(e2Min, s2Min)).toFixed(2)
      );
    }
  }

  if (e1 && s1) {
    const e1Min = parseHHMM(e1);
    const s1Min = parseHHMM(s1);
    if (e1Min !== null && s1Min !== null) return calcHorasDecimalFromMinutes(e1Min, s1Min);
  }

  const fallback = Number(row.horas_trabalhadas ?? 0);
  return Number.isFinite(fallback) ? fallback : 0;
}

function hasManualExtra(row: HhLancamentoCalcRow): boolean {
  return Boolean(row.tem_extra_50 || row.tem_extra_100) || Number(row.horas_extra_50 ?? 0) > 0 || Number(row.horas_extra_100 ?? 0) > 0;
}

function normalizeHoras(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Number(Math.max(0, value).toFixed(2));
}

export function getHorasSplitEfetivo(row: HhLancamentoCalcRow, horasEfetivas: number) {
  const total = normalizeHoras(horasEfetivas);
  const manualExtra = hasManualExtra(row);
  const percentual = Number(row.percentual_aplicado ?? 0);

  if (manualExtra) {
    const extra50 = normalizeHoras(Number(row.horas_extra_50 ?? 0));
    const extra100 = normalizeHoras(Number(row.horas_extra_100 ?? 0));
    const normais = normalizeHoras(total - extra50 - extra100);
    return { normais, extra50, extra100 };
  }

  if (percentual === 50) return { normais: 0, extra50: total, extra100: 0 };
  if (percentual === 100) return { normais: 0, extra50: 0, extra100: total };
  return { normais: total, extra50: 0, extra100: 0 };
}

export function getValorTotalEfetivo(row: HhLancamentoCalcRow, horasEfetivas: number): number {
  const totalDb = Number(row.valor_total ?? 0);
  const percentual = Number(row.percentual_aplicado ?? 0);
  if ((hasManualExtra(row) || percentual === 50 || percentual === 100) && Number.isFinite(totalDb) && totalDb > 0) {
    return totalDb;
  }

  const valorHora = Number(row.valor_hora ?? 0);
  if (Number.isFinite(valorHora) && valorHora > 0 && Number.isFinite(horasEfetivas) && horasEfetivas > 0) {
    const split = getHorasSplitEfetivo(row, horasEfetivas);
    return Number(
      (split.normais * valorHora + split.extra50 * valorHora * 1.5 + split.extra100 * valorHora * 2).toFixed(2)
    );
  }
  return Number.isFinite(totalDb) ? totalDb : 0;
}

export function calcHhPedidoTotal(rows: HhLancamentoCalcRow[]): number {
  const sum = (rows ?? []).reduce((acc, r) => {
    const horas = getHorasTrabalhadasEfetivas(r);
    const total = getValorTotalEfetivo(r, horas);
    return acc + (Number.isFinite(total) ? total : 0);
  }, 0);
  return Math.round(sum * 100) / 100;
}
