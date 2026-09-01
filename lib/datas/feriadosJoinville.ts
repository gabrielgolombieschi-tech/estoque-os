export type FeriadoCalendario = {
  data: string;
  descricao: string;
  abrangencia: "NACIONAL" | "ESTADUAL" | "MUNICIPAL";
};

function isoDate(year: number, month: number, day: number) {
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function dateToISO(date: Date) {
  return isoDate(date.getFullYear(), date.getMonth() + 1, date.getDate());
}

function addDays(date: Date, amount: number) {
  const next = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12);
  next.setDate(next.getDate() + amount);
  return next;
}

// Algoritmo de Meeus/Jones/Butcher para o domingo de Páscoa no calendário gregoriano.
function easterSunday(year: number) {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(year, month - 1, day, 12);
}

/**
 * Feriados que afetam a operação de Joinville/SC.
 *
 * Fontes oficiais verificadas em 30/08/2026:
 * - Prefeitura de Joinville: calendário municipal de feriados de 2026.
 * - Portaria MGI 11.460/2025: feriados nacionais de 2026.
 * - Decreto SC 1.374/2026: calendário estadual; a Data Magna de 11/08 é
 *   transferida para o domingo subsequente e, portanto, não reduz dia útil.
 *
 * Pontos facultativos não entram no cálculo. As datas móveis são derivadas da
 * Páscoa; as leis citadas nos calendários tornam 09/03, Paixão de Cristo e
 * Corpus Christi feriados municipais recorrentes em Joinville.
 */
export function getFeriadosJoinville(year: number): FeriadoCalendario[] {
  const easter = easterSunday(year);
  const holidays: FeriadoCalendario[] = [
    { data: isoDate(year, 1, 1), descricao: "Confraternização Universal", abrangencia: "NACIONAL" },
    { data: isoDate(year, 3, 9), descricao: "Aniversário de Joinville", abrangencia: "MUNICIPAL" },
    { data: dateToISO(addDays(easter, -2)), descricao: "Sexta-Feira da Paixão", abrangencia: "MUNICIPAL" },
    { data: isoDate(year, 4, 21), descricao: "Tiradentes", abrangencia: "NACIONAL" },
    { data: isoDate(year, 5, 1), descricao: "Dia do Trabalhador", abrangencia: "NACIONAL" },
    { data: dateToISO(addDays(easter, 60)), descricao: "Corpus Christi", abrangencia: "MUNICIPAL" },
    { data: isoDate(year, 9, 7), descricao: "Independência do Brasil", abrangencia: "NACIONAL" },
    { data: isoDate(year, 10, 12), descricao: "Nossa Senhora Aparecida", abrangencia: "NACIONAL" },
    { data: isoDate(year, 11, 2), descricao: "Finados", abrangencia: "NACIONAL" },
    { data: isoDate(year, 11, 15), descricao: "Proclamação da República", abrangencia: "NACIONAL" },
    { data: isoDate(year, 11, 20), descricao: "Dia Nacional de Zumbi e da Consciência Negra", abrangencia: "NACIONAL" },
    { data: isoDate(year, 12, 25), descricao: "Natal", abrangencia: "NACIONAL" },
  ];

  return holidays.sort((a, b) => a.data.localeCompare(b.data));
}

export function getDiasUteisJoinville(year: number, month1to12: number, throughDay?: number) {
  const lastDay = new Date(year, month1to12, 0, 12).getDate();
  const limit = throughDay == null ? lastDay : Math.max(0, Math.min(lastDay, throughDay));
  const holidays = new Set(getFeriadosJoinville(year).map((holiday) => holiday.data));
  const days: string[] = [];

  for (let day = 1; day <= limit; day += 1) {
    const date = new Date(year, month1to12 - 1, day, 12);
    const weekday = date.getDay();
    const iso = isoDate(year, month1to12, day);
    if (weekday === 0 || weekday === 6 || holidays.has(iso)) continue;
    days.push(iso);
  }

  return days;
}
