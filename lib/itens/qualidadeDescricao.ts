/** D-033: critérios compartilhados pelo cadastro assistido e pela importação. */
export const REGRAS_SENSORES_SEGURANCA = [
  "Para sensores e itens de segurança, confirme o código exato e a variante no fabricante. Termos fiscais em inglês não definem a função: safety switch é chave de segurança, não switch Ethernet; TR4/STR1 RFID não são travas mecânicas. Acessório não é sensor completo.",
  "Sensores fotoelétricos exigem princípio (barreira, retrorreflexivo, difuso/supressão de fundo), alcance de trabalho, saída (PNP/NPN ou outra), alimentação e conexão. Em barreiras, distinguir emissor, receptor e conjunto somente quando confirmado. Indutivos e ultrassônicos exigem faixa/distância, saída, alimentação, conexão e dimensões confirmadas. Não substituir faixa de trabalho pelo alcance máximo limite.",
  "Cortinas de segurança exigem família/referência exata, emissor ou receptor, altura protegida, resolução, alcance e tipo de segurança confirmados. Não herdar o alcance de outra variante: C4-RD de 4,5m não equivale a deTec4 Core de 15m. Altura protegida não é alcance.",
  "Distinguir sensor radar de segurança e seu controlador. Informar alcance no sensor e protocolos no controlador; declarar compatibilidade e alimentação quando confirmadas. Chaves RFID exigem tipo de codificação, saídas OSSD, distância assegurada de acionamento (Sao), alimentação, conexão e presença de atuador confirmados; não confundir com contatos mecânicos ou bloqueio físico.",
  "Cabos montados exigem função, referência, comprimento, conectores de cada ponta (macho/fêmea, pinos, orientação e codificação), ou ponta livre, materiais, formação/seção, blindagem e tensão nominal do conjunto quando confirmados. A tensão do cabo isolado não é necessariamente a do conjunto com conectores. Não aplicar a conversão obrigatória para metros dos cabos sem terminação a cordões/conjuntos montados.",
  "Acessórios exigem função e compatibilidade: kit de corda de tração é acessório da chave de segurança; cabo de programação e acoplamento são acessórios de encoder. Acoplamento exige diâmetros dos dois eixos, construção/material e comprimento confirmados. Terminador exige protocolo/conector e resistência somente se confirmada; nunca presumir 120ohms pelo protocolo.",
  "Exija dados faltantes em dados_pendentes com confiança baixa. Não complete lacunas usando um produto similar, trecho de referência ou regra provável de família. Código copiado/divergente exige revisão humana, sem inventar um novo código.",
].join(" ");

const simplificar = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toUpperCase();

/** Validação de completude, não certificação da veracidade das especificações. */
export function pendenciasDescricaoTecnica(input: {
  descricao: string;
  codigo?: string;
  modeloReferencia?: string | null;
  grupoCodigo?: string | null;
  origem?: string;
}): string[] {
  const nome = simplificar(input.descricao);
  const contexto = simplificar(`${input.descricao} ${input.origem ?? ""}`);
  const modelo = simplificar(input.modeloReferencia ?? "");
  const tecnico = modelo ? nome.replace(modelo, "") : nome;
  const pendencias: string[] = [];
  const exigir = (presente: boolean, atributo: string) => {
    if (!presente) pendencias.push(`Confirmar e informar ${atributo} na descrição técnica.`);
  };
  const distancia = /\d+(?:[.,]\d+)?\s*(?:MM|CM|M)\b/.test(tecnico);
  const tensao = /\d+(?:[.,]\d+)?\s*V(?:CC|CA|DC|AC)(?:\b|\/)/.test(tecnico);
  const conexao = /\b(?:CABO|M8|M12|M23|BORNE|CONECTOR)\b/.test(tecnico);
  const saida = /\b(?:PNP|NPN|TTL|HTL|IO-LINK|OSSD)\b|\d+OSSD|\d+(?:-\d+)?MA\b|\bSAIDA\b/.test(tecnico);

  if (/^SENSOR(?:ES)? INDUSTRIA(?:L|IS)\b/.test(nome)) exigir(false, "o princípio e a função do sensor, sem usar apenas SENSOR INDUSTRIAL");
  if (/^SENSOR(?:ES)? (?:FOTOELETRICO|INDUTIVO|ULTRASSONICO)/.test(nome)) {
    if (/^SENSOR(?:ES)? FOTOELETRICO/.test(nome)) {
      exigir(/BARREIRA|RETROR?REFLEX|DIFUS|SUPRESSAO DE FUNDO|ENERGETICO/.test(tecnico), "o princípio fotoelétrico");
    }
    exigir(distancia, "a distância/faixa de trabalho do sensor");
    exigir(saida, "o tipo de saída do sensor");
    exigir(tensao, "a tensão de alimentação do sensor");
    exigir(conexao, "a conexão do sensor");
  }
  if (/^CORTINA DE LUZ/.test(nome)) {
    exigir(/TRANSMISSOR|EMISSOR|RECEPTOR|CONJUNTO|PAR\b/.test(tecnico), "se a cortina é emissora, receptora ou conjunto");
    exigir(/ALTURA\s+\d+(?:[.,]\d+)?\s*(?:MM|CM|M)\b/.test(tecnico), "a altura protegida da cortina");
    exigir(/RESOLUCAO\s+\d+(?:[.,]\d+)?\s*MM\b/.test(tecnico), "a resolução da cortina");
    exigir(/ALCANCE\s+\d+(?:[.,]\d+)?\s*M\b/.test(tecnico), "o alcance da variante da cortina");
    exigir(/TIPO\s+[24]\b/.test(tecnico), "o tipo de segurança da cortina");
  }
  if (/^SENSOR RADAR DE SEGURANCA/.test(nome)) exigir(/ALCANCE\b/.test(tecnico) && distancia, "o alcance do radar de segurança");
  if (/^(?:CHAVE|SENSOR) DE SEGURANCA RFID/.test(nome)) {
    exigir(/\d+\s*OSSD/.test(tecnico), "as saídas seguras OSSD");
    exigir(/SAO\s+\d+(?:[.,]\d+)?\s*MM\b/.test(tecnico), "a distância assegurada de acionamento Sao");
    exigir(tensao, "a alimentação da chave RFID");
    exigir(conexao, "a conexão da chave RFID");
  }
  if ((/^SWITCH\b/.test(nome) || input.grupoCodigo === "SWITCHES_REDE_INDUSTRIAL") && /SAFETY.?SWITCH|SAF\.?\s*SWITCH|STR1-|TR4-|RFID/.test(contexto)) {
    exigir(false, "a classificação: chave RFID/safety switch não é switch de rede");
  }
  // No cadastro assistido a referência vem em campo próprio; o importador
  // não fornece esse campo. Não tentar inferi-la de medidas como M12/24VCC.
  if (/^\d+$/.test(input.codigo ?? "") && input.modeloReferencia !== undefined) {
    exigir(Boolean(modelo && /[A-Z]/.test(modelo) && /\d/.test(modelo) && nome.includes(modelo)), "a referência alfanumérica oficial confirmada para o código numérico");
  }
  return pendencias;
}
