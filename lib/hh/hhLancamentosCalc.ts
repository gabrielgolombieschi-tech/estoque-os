export type HhLancamentoCalcRow = {
  os_id?: number | string | null;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  hora_entrada?: string | null;
  hora_saida?: string | null;
  horas_trabalhadas?: number | string | null;
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

export function getValorTotalEfetivo(row: HhLancamentoCalcRow, horasEfetivas: number): number {
  const valorHora = Number(row.valor_hora ?? 0);
  if (Number.isFinite(valorHora) && valorHora > 0 && Number.isFinite(horasEfetivas) && horasEfetivas > 0) {
    return Number((valorHora * horasEfetivas).toFixed(2));
  }
  const total = Number(row.valor_total ?? 0);
  return Number.isFinite(total) ? total : 0;
}

export function calcHhPedidoTotal(rows: HhLancamentoCalcRow[]): number {
  const sum = (rows ?? []).reduce((acc, r) => {
    const horas = getHorasTrabalhadasEfetivas(r);
    const total = getValorTotalEfetivo(r, horas);
    return acc + (Number.isFinite(total) ? total : 0);
  }, 0);
  return Math.round(sum * 100) / 100;
}
