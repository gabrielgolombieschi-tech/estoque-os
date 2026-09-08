// Calculos e formatacao do relatorio de horas (HH).
//
// Movido de app/os/[id]/components/RelatorioHHSection.tsx sem alteracao de
// comportamento. Ficou aqui porque o gerador do PDF agora roda tambem no
// servidor (para o aplicativo baixar o arquivo pronto), e tela e servidor
// precisam somar as horas do mesmo jeito — senao o PDF do celular sai
// diferente do PDF do navegador.

export type HhLancamentoViewRow = {
  id: string | number;
  os_id: number;
  data: string;
  colaborador_nome: string | null;
  especialidade_descricao: string | null;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  hora_entrada: string | null;
  hora_saida: string | null;
  horas_trabalhadas: number | null;
  hh_tipo_descricao?: string | null;
  hh_tipo_id?: string | number | null;
  hh_servico_id?: string | number | null;
  percentual_aplicado?: number | null;
  tem_extra_50?: boolean | null;
  horas_extra_50?: number | null;
  tem_extra_100?: boolean | null;
  horas_extra_100?: number | null;
  valor_hora: number | null;
  valor_total: number | null;
  observacao: string | null;
  criado_em: string | null;
};

export function formatHoursBR(value: number | null | undefined) {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0,00";
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function formatTimeHHMM(value: string | null | undefined): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  // Pode vir "HH:MM" ou "HH:MM:SS".
  if (/^\d{2}:\d{2}/.test(raw)) return raw.slice(0, 5);
  return raw;
}

export function formatDateBR(isoDate: string | null | undefined) {
  if (!isoDate) return "--";
  const d = new Date(isoDate + "T00:00:00");
  return d.toLocaleDateString("pt-BR");
}

export function formatDateDDMMAA(isoDate: string | null | undefined): string {
  const raw = String(isoDate ?? "").trim();
  if (!raw) return "--";

  // Prefer ISO yyyy-mm-dd (avoid timezone issues)
  const m = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) {
    const yy = m[1].slice(-2);
    return `${m[3]}/${m[2]}/${yy}`;
  }

  const d = new Date(raw);
  if (!Number.isFinite(d.getTime())) return "--";
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yy = String(d.getFullYear()).slice(-2);
  return `${dd}/${mm}/${yy}`;
}

export function formatCurrencyBRL(value: number): string {
  const v = Number(value ?? 0);
  const safe = Number.isFinite(v) ? v : 0;
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(safe);
}

export function getPercentualFromDate(dateISO: string): 0 | 50 | 100 {
  const raw = String(dateISO ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return 0;
  const d = new Date(raw + "T00:00:00");
  const dow = d.getDay();
  if (dow === 0) return 100;
  if (dow === 6) return 50;
  return 0;
}

export function getTipoHHLabel(percentual: number): string {
  if (percentual === 50) return "Extra 50%";
  if (percentual === 100) return "Extra 100%";
  return "Normal";
}

export function parseHHMM(value: string): number | null {
  const raw = String(value ?? "").trim();
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(raw);
  if (!m) return null;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  return hh * 60 + mm;
}

export function calcHorasDecimalFromMinutes(inicioMin: number, fimMin: number): number {
  let diff = fimMin - inicioMin;
  if (diff < 0) diff = 1440 - inicioMin + fimMin; // virada de dia
  return Number((diff / 60).toFixed(2));
}

export function getHorasTrabalhadasEfetivas(row: HhLancamentoViewRow): number {
  const e1 = formatTimeHHMM(row.entrada_1) || formatTimeHHMM(row.hora_entrada);
  const s1 = formatTimeHHMM(row.saida_1) || formatTimeHHMM(row.hora_saida);
  const e2 = formatTimeHHMM(row.entrada_2);
  const s2 = formatTimeHHMM(row.saida_2);

  // Se houver 2 períodos completos, soma os dois (não conta almoço).
  if (e1 && s1 && e2 && s2) {
    const e1Min = parseHHMM(e1);
    const s1Min = parseHHMM(s1);
    const e2Min = parseHHMM(e2);
    const s2Min = parseHHMM(s2);
    if (e1Min !== null && s1Min !== null && e2Min !== null && s2Min !== null) {
      return Number((calcHorasDecimalFromMinutes(e1Min, s1Min) + calcHorasDecimalFromMinutes(e2Min, s2Min)).toFixed(2));
    }
  }

  // Fallback: 1 período (entrada/saída)
  if (e1 && s1) {
    const e1Min = parseHHMM(e1);
    const s1Min = parseHHMM(s1);
    if (e1Min !== null && s1Min !== null) return calcHorasDecimalFromMinutes(e1Min, s1Min);
  }

  const fallback = Number(row.horas_trabalhadas ?? 0);
  return Number.isFinite(fallback) ? fallback : 0;
}

export function normalizeHorasNumber(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Number(Math.max(0, value).toFixed(2));
}

export function hasManualExtra(row: HhLancamentoViewRow): boolean {
  return Boolean(row.tem_extra_50 || row.tem_extra_100) || Number(row.horas_extra_50 ?? 0) > 0 || Number(row.horas_extra_100 ?? 0) > 0;
}

export function getHorasSplitEfetivo(row: HhLancamentoViewRow, horasEfetivas: number) {
  const total = normalizeHorasNumber(horasEfetivas);
  const percentualAplicado = Number(row.percentual_aplicado ?? 0);

  if (hasManualExtra(row)) {
    const extra50 = normalizeHorasNumber(Number(row.horas_extra_50 ?? 0));
    const extra100 = normalizeHorasNumber(Number(row.horas_extra_100 ?? 0));
    const normais = normalizeHorasNumber(total - extra50 - extra100);
    return { normais, extra50, extra100 };
  }

  if (percentualAplicado === 50) return { normais: 0, extra50: total, extra100: 0 };
  if (percentualAplicado === 100) return { normais: 0, extra50: 0, extra100: total };
  return { normais: total, extra50: 0, extra100: 0 };
}

export function getTipoHHLabelFromSplit(row: HhLancamentoViewRow, horasEfetivas: number): string {
  const split = getHorasSplitEfetivo(row, horasEfetivas);
  const parts: string[] = [];
  if (split.normais > 0) parts.push("Normal");
  if (split.extra50 > 0) parts.push("Extra 50%");
  if (split.extra100 > 0) parts.push("Extra 100%");
  return parts.length > 0 ? parts.join(" + ") : getTipoHHLabel(Number(row.percentual_aplicado ?? 0));
}

export function getValorTotalEfetivo(row: HhLancamentoViewRow, horasEfetivas: number): number {
  const totalDb = Number(row.valor_total ?? 0);
  const percentualAplicado = Number(row.percentual_aplicado ?? 0);
  if ((hasManualExtra(row) || percentualAplicado === 50 || percentualAplicado === 100) && Number.isFinite(totalDb) && totalDb > 0) {
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
