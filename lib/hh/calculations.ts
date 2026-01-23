/**
 * Funções de cálculo de horas para HH (Hora-Homem)
 * Padrão brasileiro: valores decimais (ex: 1.5h = 1h 30min)
 */

export type HHPeriodo = {
  entrada: string; // "HH:mm"
  saida: string;   // "HH:mm"
};

/**
 * Converte string "HH:mm" para minutos desde meia-noite
 */
function horaParaMinutos(hora: string): number {
  const [h, m] = hora.split(':').map(Number);
  if (isNaN(h) || isNaN(m)) return 0;
  return h * 60 + m;
}

/**
 * Calcula diferença de minutos entre dois horários, considerando virada de dia
 */
function calcularDiferencaMinutos(entrada: string, saida: string): number {
  const entradaMin = horaParaMinutos(entrada);
  const saidaMin = horaParaMinutos(saida);
  
  // Se saída é menor que entrada, houve virada de dia
  if (saidaMin < entradaMin) {
    // Ex: entrada 22:00 (1320min), saída 02:00 (120min)
    // Período 1: 22:00 até 23:59 = 1440 - 1320 = 120min
    // Período 2: 00:00 até 02:00 = 120min
    // Total = 120 + 120 = 240min
    return (1440 - entradaMin) + saidaMin;
  }
  
  return saidaMin - entradaMin;
}

/**
 * Calcula total de horas trabalhadas baseado em 2 períodos (manhã/tarde)
 * 
 * @param entrada1 - Entrada período 1 (ex: "08:00")
 * @param saida1 - Saída período 1 (ex: "12:00")
 * @param entrada2 - Entrada período 2 (ex: "13:00")
 * @param saida2 - Saída período 2 (ex: "17:00")
 * @returns Total de horas em decimal (ex: 8.00)
 */
export function calcularHoras(
  entrada1: string,
  saida1: string,
  entrada2: string,
  saida2: string
): number {
  if (!entrada1 || !saida1 || !entrada2 || !saida2) {
    return 0;
  }

  const minutosPeriodo1 = calcularDiferencaMinutos(entrada1, saida1);
  const minutosPeriodo2 = calcularDiferencaMinutos(entrada2, saida2);
  
  const totalMinutos = minutosPeriodo1 + minutosPeriodo2;
  const totalHoras = totalMinutos / 60;
  
  // Retornar com 2 casas decimais
  return Number(totalHoras.toFixed(2));
}

/**
 * Formata horas decimais para exibição em português BR
 * 
 * @param horas - Horas em decimal (ex: 1.5)
 * @returns String formatada (ex: "1h 30min")
 */
export function formatHorasBR(horas: number): string {
  if (!Number.isFinite(horas) || horas < 0) return "0h";
  
  const horasInteiras = Math.floor(horas);
  const minutos = Math.round((horas - horasInteiras) * 60);
  
  if (minutos === 0) {
    return `${horasInteiras}h`;
  }
  
  return `${horasInteiras}h ${minutos}min`;
}

/**
 * Valida se os horários estão no formato correto e são consistentes
 */
export function validarHorarios(
  entrada1: string,
  saida1: string,
  entrada2: string,
  saida2: string
): { valid: boolean; error?: string } {
  // Regex para validar formato HH:mm
  const timeRegex = /^([0-1][0-9]|2[0-3]):[0-5][0-9]$/;
  
  if (!timeRegex.test(entrada1)) return { valid: false, error: "Entrada 1 inválida" };
  if (!timeRegex.test(saida1)) return { valid: false, error: "Saída 1 inválida" };
  if (!timeRegex.test(entrada2)) return { valid: false, error: "Entrada 2 inválida" };
  if (!timeRegex.test(saida2)) return { valid: false, error: "Saída 2 inválida" };
  
  // Validar que saída1 <= entrada2 (não pode haver sobreposição)
  const saida1Min = horaParaMinutos(saida1);
  const entrada2Min = horaParaMinutos(entrada2);
  
  if (saida1Min > entrada2Min) {
    return { valid: false, error: "Saída 1 deve ser antes ou igual à Entrada 2" };
  }
  
  return { valid: true };
}

/**
 * Converte minutos para horas decimais
 */
export function minutosParaHoras(minutos: number): number {
  return Number((minutos / 60).toFixed(2));
}

/**
 * Converte horas decimais para minutos
 */
export function horasParaMinutos(horas: number): number {
  return Math.round(horas * 60);
}
