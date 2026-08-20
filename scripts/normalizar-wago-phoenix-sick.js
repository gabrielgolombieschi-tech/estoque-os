/* eslint-disable @typescript-eslint/no-require-imports */
/*
 * Lote aprovado de normalização por fornecedor: Phoenix, SICK e WAGO.
 *
 * Uso:
 *   node scripts/normalizar-wago-phoenix-sick.js          # diagnóstico, sem gravar
 *   node scripts/normalizar-wago-phoenix-sick.js --apply  # cria grupos e atualiza nomes/grupos
 *
 * O script não altera códigos, fornecedor, fabricante, preços ou status de ativo.
 */
const fs = require("fs");
const { createClient } = require("@supabase/supabase-js");

const APPLY = process.argv.includes("--apply");
const TENANT_ID = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const EMPRESA_ID = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const FORNECEDORES = new Map([
  [1, "PHOENIX"],
  [14, "SICK"],
  [510, "WAGO"],
]);

function loadEnv(file) {
  return Object.fromEntries(
    fs
      .readFileSync(file, "utf8")
      .split(/\r?\n/)
      .filter((line) => line && !line.trim().startsWith("#") && line.includes("="))
      .map((line) => {
        const index = line.indexOf("=");
        return [line.slice(0, index), line.slice(index + 1)];
      })
  );
}

const env = loadEnv(fs.existsSync(".env.local") ? ".env.local" : ".env");
const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const GRUPOS_NOVOS = [
  { codigo: "MONTAGEM_PAINEIS", nome: "MONTAGEM DE PAINÉIS", pai: null },
  { codigo: "CANALETAS_PARA_PAINEIS", nome: "CANALETAS PARA PAINÉIS", pai: "MONTAGEM_PAINEIS" },
  { codigo: "TRILHOS_DIN", nome: "TRILHOS DIN", pai: "MONTAGEM_PAINEIS" },
  { codigo: "PRENSA_CABOS", nome: "PRENSA-CABOS", pai: "MONTAGEM_PAINEIS" },
  { codigo: "IDENTIFICACAO_PARA_PAINEIS", nome: "IDENTIFICAÇÃO PARA PAINÉIS", pai: "MONTAGEM_PAINEIS" },
  { codigo: "FERRAMENTAS_MONTAGEM_PAINEIS", nome: "FERRAMENTAS PARA MONTAGEM DE PAINÉIS", pai: "MONTAGEM_PAINEIS" },
  { codigo: "SENSORES_INDUSTRIAIS", nome: "SENSORES INDUSTRIAIS", pai: null },
  { codigo: "SENSORES_FOTOELETRICOS", nome: "SENSORES FOTOELÉTRICOS", pai: "SENSORES_INDUSTRIAIS" },
  { codigo: "SENSORES_INDUTIVOS", nome: "SENSORES INDUTIVOS", pai: "SENSORES_INDUSTRIAIS" },
  { codigo: "SENSORES_TIPO_GARFO", nome: "SENSORES TIPO GARFO", pai: "SENSORES_INDUSTRIAIS" },
  { codigo: "CABOS_PARA_SENSORES", nome: "CABOS PARA SENSORES E ATUADORES", pai: "SENSORES_INDUSTRIAIS" },
  { codigo: "CONECTORES_PARA_SENSORES", nome: "CONECTORES PARA SENSORES", pai: "SENSORES_INDUSTRIAIS" },
  { codigo: "ACESSORIOS_PARA_SENSORES", nome: "ACESSÓRIOS PARA SENSORES", pai: "SENSORES_INDUSTRIAIS" },
  { codigo: "SENSORES_NIVEL", nome: "SENSORES DE NÍVEL", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "SENSORES_ULTRASSONICOS", nome: "SENSORES ULTRASSÔNICOS", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "SENSORES_FLUXO", nome: "SENSORES DE FLUXO", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "SENSORES_TEMPERATURA", nome: "SENSORES DE TEMPERATURA", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "SENSORES_PRESSAO", nome: "SENSORES DE PRESSÃO", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "ENCODERS", nome: "ENCODERS", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "ACESSORIOS_ENCODERS", nome: "ACESSÓRIOS PARA ENCODERS", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "CONDICIONADORES_SINAL", nome: "CONDICIONADORES DE SINAL", pai: "MEDICAO_INSTRUMENTACAO" },
  { codigo: "BLOCOS_DISTRIBUICAO", nome: "BLOCOS DE DISTRIBUIÇÃO", pai: "CONEXOES_ELETRICAS" },
  { codigo: "ACESSORIOS_BLOCOS_DISTRIBUICAO", nome: "ACESSÓRIOS PARA BLOCOS DE DISTRIBUIÇÃO", pai: "CONEXOES_ELETRICAS" },
  { codigo: "CONECTORES_INDUSTRIAIS", nome: "CONECTORES INDUSTRIAIS", pai: "CONEXOES_ELETRICAS" },
  { codigo: "CONECTORES_INDUSTRIAIS_MULTIPOLARES", nome: "CONECTORES INDUSTRIAIS MULTIPOLARES", pai: "CONECTORES_INDUSTRIAIS" },
  { codigo: "TOMADAS_TRILHO_DIN", nome: "TOMADAS PARA TRILHO DIN", pai: "CONEXOES_ELETRICAS" },
  { codigo: "ACESSORIOS_PARA_BORNES", nome: "ACESSÓRIOS PARA BORNES", pai: "CONEXOES_ELETRICAS" },
  { codigo: "CORTINAS_LUZ_SEGURANCA", nome: "CORTINAS DE LUZ DE SEGURANÇA", pai: "SEGURANCA_MAQUINAS" },
  { codigo: "ACESSORIOS_CORTINAS_LUZ", nome: "ACESSÓRIOS PARA CORTINAS DE LUZ", pai: "SEGURANCA_MAQUINAS" },
  { codigo: "CONTROLADORES_SEGURANCA", nome: "CONTROLADORES DE SEGURANÇA", pai: "SEGURANCA_MAQUINAS" },
  { codigo: "DISPOSITIVOS_HABILITACAO", nome: "DISPOSITIVOS DE HABILITAÇÃO", pai: "SEGURANCA_MAQUINAS" },
  { codigo: "DISJUNTORES_ELETRONICOS", nome: "DISJUNTORES ELETRÔNICOS", pai: "PROTECAO_E_SECCIONAMENTO" },
  { codigo: "MODULOS_REDUNDANCIA", nome: "MÓDULOS DE REDUNDÂNCIA", pai: "ALIMENTACAO_E_ENERGIA" },
];

function upper(value) {
  return String(value ?? "")
    .normalize("NFC")
    .replace(/PEDIDO DE COMPRA\s*:\s*[^\n]+/gi, "")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();
}

function section(text) {
  const match = text.match(/(\d+(?:[,.]\d+)?)\s*MM(?:²|2)?\b/i);
  return match ? `${match[1].replace(".", ",")}MM²` : null;
}

function length(text) {
  const medidaDireta = text.match(/\b(\d+(?:[,.]\d+)?)M\b/i);
  if (medidaDireta) return `${medidaDireta[1].replace(".", ",")}M`;
  const match = text.match(/(?:-|\s)(\d{1,3}),0(?:\D|$)/);
  return match ? `${Number(match[1])}M` : null;
}

function poles(text) {
  const match = text.match(/(?:-|\s)([458])\s*(?:POLOS?|PL|P|CON)\b/i);
  return match ? `${match[1]} POLOS` : null;
}

function joinName(...parts) {
  return parts.filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
}

function proposal(group, nome, pendencia = null) {
  return { grupo: group, nome: upper(nome), pendencia };
}

function normalizarWago(item) {
  const raw = upper(item.nome);
  const secao = section(raw);
  if (/^REL[ÉE] DE INTERFACE/.test(raw)) return proposal("RELES_INTERFACE", raw);
  if (/^PENTE DE LIGAÇÃO.*REL[ÉE] DE INTERFACE/.test(raw)) return proposal("ACESSORIOS_RELES_INTERFACE", raw);
  if (/^PENTE DE LIGAÇÃO PARA BORNES/.test(raw)) return proposal("CONEXOES_PENTES_PARA_BORNES", raw);
  if (/^TAMPA FINAL PARA BORNE/.test(raw)) return proposal("CONEXOES_TAMPAS_FINAIS_PARA_BORNES", raw);
  if (/^PLACA SEPARADORA PARA BORNE/.test(raw)) return proposal("ACESSORIOS_PARA_BORNES", raw);
  if (/^BORNE DE PROTEÇÃO/.test(raw)) return proposal("CONEXOES_BORNES_PROTECAO", raw);
  if (/^BORNE DE PASSAGEM|^TERMINAL SEM PARAFUSO/.test(raw)) return proposal("CONEXOES_BORNES_PASSAGEM", raw);
  if (/^CHAVE (?:ALLEN )?PARA BORNE|^DESENCAPADOR/.test(raw)) return proposal("FERRAMENTAS_MONTAGEM_PAINEIS", raw);
  if (/^MATERIAL DE IDENTIFICAÇÃO/.test(raw)) return proposal("IDENTIFICACAO_PARA_PAINEIS", raw);
  if (/^SWITCH DE REDE INDUSTRIAL/.test(raw)) return proposal("SWITCHES_REDE_INDUSTRIAL", raw);
  if (/^TOMADA PARA TRILHO DIN/.test(raw)) return proposal("TOMADAS_TRILHO_DIN", raw);
  if (/BARRA DE JUMPERS/.test(raw)) return proposal("ACESSORIOS_RELES_INTERFACE", "PENTE DE LIGAÇÃO 10 VIAS 18A PARA RELÉ DE INTERFACE");
  if (/^JUMPER/.test(raw)) {
    const cor = raw.match(/\b(AZUL|VERMELHO)\b/)?.[1];
    return proposal("CONEXOES_PENTES_PARA_BORNES", joinName("PENTE DE LIGAÇÃO PARA BORNES", cor ? `COR ${cor}` : null, "10 POLOS", secao));
  }
  if (/PLACA FINAL/.test(raw)) return proposal("CONEXOES_TAMPAS_FINAIS_PARA_BORNES", joinName("TAMPA FINAL PARA BORNE", secao));
  if (/PLACA TERMINAL/.test(raw)) return proposal("CONEXOES_TAMPAS_FINAIS_PARA_BORNES", "TAMPA FINAL PARA BORNE");
  if (/PLACA BORNE/.test(raw)) return proposal("ACESSORIOS_PARA_BORNES", joinName("PLACA SEPARADORA PARA BORNE", /3 ANDARES/.test(raw) ? "3 NÍVEIS" : null, secao));
  if (/^BORNE/.test(raw) || /^TERMINAL SEM PARAFUSO/.test(raw)) {
    const protecao = /\b(TERRA|PE|PROTEÇÃO)\b/.test(raw);
    const niveis = raw.match(/(\d)\s*(?:ANDARES|NÍVEIS)/)?.[1];
    const condutores = raw.match(/(\d)\s*(?:PONTOS|CONDUTORES)/)?.[1];
    return proposal(
      protecao ? "CONEXOES_BORNES_PROTECAO" : "CONEXOES_BORNES_PASSAGEM",
      joinName(protecao ? "BORNE DE PROTEÇÃO" : "BORNE DE PASSAGEM", niveis ? `${niveis} NÍVEIS` : null, condutores ? `${condutores} CONDUTORES` : null, secao)
    );
  }
  if (/^CHAVE ALLEN/.test(raw)) return proposal("FERRAMENTAS_MONTAGEM_PAINEIS", "CHAVE ALLEN PARA BORNE");
  if (/^CHAVE DE BORNES/.test(raw)) {
    const medida = raw.match(/\d+(?:,\d+)?\s*X\s*\d+(?:,\d+)?\s*MM/)?.[0]?.replace(/\s+/g, "");
    return proposal("FERRAMENTAS_MONTAGEM_PAINEIS", joinName("CHAVE PARA BORNE", medida));
  }
  if (/DESENCAPADOR/.test(raw)) return proposal("FERRAMENTAS_MONTAGEM_PAINEIS", "DESENCAPADOR DE FIOS");
  if (/ETIQUETA|FITA DE IMPRESSORA|ROLO DE IDENTIFICAÇÃO|WMB INLINE|IDENTIFICADOR/.test(raw)) {
    const medida = raw.match(/\d+(?:,\d+)?\s*X\s*\d+(?:,\d+)?\s*MM/)?.[0]?.replace(/\s+/g, "");
    return proposal("IDENTIFICACAO_PARA_PAINEIS", joinName("MATERIAL DE IDENTIFICAÇÃO PARA PAINEL", medida));
  }
  if (/SWITCH INDUSTRIAL/.test(raw)) return proposal("SWITCHES_REDE_INDUSTRIAL", "SWITCH DE REDE INDUSTRIAL NÃO GERENCIÁVEL 5 PORTAS 100BASE-TX");
  if (/^TOMADA/.test(raw)) return proposal("TOMADAS_TRILHO_DIN", "TOMADA PARA TRILHO DIN 2P+T 10A");
  return proposal(null, raw, "Descrição sem função técnica confirmada para normalização automática.");
}

function normalizarPhoenix(item) {
  const raw = upper(item.nome);
  const secaoCodigo = raw.match(/(?:PTTB|PTIO|PTPOWER|PT|UK)\s*([0-9]+(?:,[0-9]+)?)/)?.[1];
  const secao = section(raw) ?? (secaoCodigo ? `${secaoCodigo}MM²` : null);
  if (/^MÓDULO DE REDUNDÂNCIA/.test(raw)) return proposal("MODULOS_REDUNDANCIA", raw);
  if (/^TRILHO DIN/.test(raw)) return proposal("TRILHOS_DIN", raw);
  if (/^SWITCH (?:DE REDE|ETHERNET) INDUSTRIAL/.test(raw)) return proposal("SWITCHES_REDE_INDUSTRIAL", raw);
  if (/^PENTE DE LIGAÇÃO.*REL[ÉE] DE INTERFACE/.test(raw)) return proposal("ACESSORIOS_RELES_INTERFACE", raw);
  if (/^PENTE DE LIGAÇÃO PARA BORNES/.test(raw)) return proposal("CONEXOES_PENTES_PARA_BORNES", raw);
  if (/^TAMPA FINAL PARA BORNE/.test(raw)) return proposal("CONEXOES_TAMPAS_FINAIS_PARA_BORNES", raw);
  if (/^(SUPORTE|ADAPTADOR) PARA BLOCO DE DISTRIBUIÇÃO/.test(raw)) return proposal("ACESSORIOS_BLOCOS_DISTRIBUICAO", raw);
  if (/^PRENSA-CABO/.test(raw)) return proposal("PRENSA_CABOS", raw);
  if (/^BLOCO DE DISTRIBUIÇÃO/.test(raw)) return proposal("BLOCOS_DISTRIBUICAO", raw);
  if (/^FONTE DE ALIMENTAÇÃO/.test(raw)) return proposal("FONTES_ALIMENTACAO", raw);
  if (/^(BATERIA PARA UPS CC|UPS CC)/.test(raw)) return proposal("UPS_CC", raw);
  if (/^REL[ÉE] DE INTERFACE/.test(raw)) return proposal("RELES_INTERFACE", raw);
  if (/^(SOQUETE|BASE) .*REL[ÉE]|^BASE PARA REL[ÉE]/.test(raw)) return proposal("ACESSORIOS_RELES_INTERFACE", raw);
  if (/^CONECTOR DE FIBRA ÓPTICA/.test(raw)) return proposal("CONECTORES_REDE_INDUSTRIAL", raw);
  if (/^CONECTOR RJ45 PARA REDE INDUSTRIAL/.test(raw)) return proposal("CONECTORES_REDE_INDUSTRIAL", raw);
  if (/^BASE PARA CONECTOR INDUSTRIAL MULTIPOLAR|^CONECTOR INDUSTRIAL MULTIPOLAR/.test(raw)) return proposal("CONECTORES_INDUSTRIAIS_MULTIPOLARES", raw);
  if (/^CONECTOR M(?:8|12)\b/.test(raw)) return proposal("CONECTORES_PARA_SENSORES", raw);
  if (/^CABO COM CONECTOR/.test(raw)) return proposal("CABOS_PARA_SENSORES", raw);
  if (/^CABO DE REDE INDUSTRIAL/.test(raw)) return proposal("CABOS_REDE_INDUSTRIAL", raw);
  if (/^BORNE DE PROTEÇÃO/.test(raw)) return proposal("CONEXOES_BORNES_PROTECAO", raw);
  if (/^BORNE DE PASSAGEM/.test(raw)) return proposal("CONEXOES_BORNES_PASSAGEM", raw);
  if (/^CONDICIONADOR DE SINAL/.test(raw)) return proposal("CONDICIONADORES_SINAL", raw);
  if (/^DISJUNTOR ELETRÔNICO/.test(raw)) return proposal("DISJUNTORES_ELETRONICOS", raw);
  if (/^MATERIAL DE IDENTIFICAÇÃO/.test(raw)) return proposal("IDENTIFICACAO_PARA_PAINEIS", raw);
  if (/^GRAMPO FINAL PARA BORNES/.test(raw)) return proposal("ACESSORIOS_PARA_BORNES", raw);
  if (/M[ÓO]DULO DE REDUND/.test(raw)) {
    const tensao = raw.match(/\d+-\d+DC/i)?.[0]?.replace("DC", "VCC");
    return proposal("MODULOS_REDUNDANCIA", joinName("MÓDULO DE REDUNDÂNCIA", tensao));
  }
  if (/PERFIL DE A[CÇ]O.*NS\s*35/.test(raw)) return proposal("TRILHOS_DIN", "TRILHO DIN 35X7,5MM PERFURADO 2m");
  if (/^SWITCH INDUSTRIAL ETHERNET.*FL NAT 2008/.test(raw)) return proposal("SWITCHES_REDE_INDUSTRIAL", "SWITCH ETHERNET INDUSTRIAL GERENCIÁVEL COM NAT 8 PORTAS RJ45 10/100MBPS");
  if (/^SWITCH INDUSTRIAL/.test(raw)) return proposal("SWITCHES_REDE_INDUSTRIAL", "SWITCH DE REDE INDUSTRIAL NÃO GERENCIÁVEL");
  if (/^PENTE DE CONEX.*REL[ÉE]/.test(raw)) return proposal("ACESSORIOS_RELES_INTERFACE", "PENTE DE LIGAÇÃO PARA RELÉ DE INTERFACE");
  if (/^JUMPER|^PENTE DE CONEX/.test(raw)) {
    const polos = raw.match(/FBSR?\s*(\d+)-/)?.[1];
    return proposal("CONEXOES_PENTES_PARA_BORNES", joinName("PENTE DE LIGAÇÃO PARA BORNES", polos ? `${polos} POLOS` : null, secao, /\bBU\b/.test(raw) ? "COR AZUL" : null));
  }
  if (/^TAMPA P\/ CONECTOR/.test(raw)) return proposal("CONEXOES_TAMPAS_FINAIS_PARA_BORNES", joinName("TAMPA FINAL PARA BORNE", secao));
  if (/PTFIX-(?:NS35|NS35A)/.test(raw)) return proposal("ACESSORIOS_BLOCOS_DISTRIBUICAO", /ADAPTADOR/.test(raw) ? "ADAPTADOR PARA BLOCO DE DISTRIBUIÇÃO EM TRILHO DIN" : "SUPORTE PARA BLOCO DE DISTRIBUIÇÃO EM TRILHO DIN");
  if (/PRENSA[ -]?CABO/.test(raw)) return proposal("PRENSA_CABOS", /MET[ÁA]L/.test(raw) ? "PRENSA-CABO METÁLICO" : /PL[ÁA]STICO/.test(raw) ? "PRENSA-CABO PLÁSTICO" : "PRENSA-CABO");
  if (/^FONTE DE ALIMENTAÇÃO/.test(raw)) return proposal("FONTES_ALIMENTACAO", raw);
  if (/\bUPS\b|ACUMULADOR.*UPS/.test(raw)) return proposal("UPS_CC", raw.replace(/^ACUMULADOR ELÉTRICO\s*-\s*/, "BATERIA PARA UPS CC "));
  if (/^REL[ÉE] DE INTERFACE/.test(raw)) return proposal("RELES_INTERFACE", raw);
  if (/\b(SOQUETE|BASE)\b.*REL[ÉE]|^BASE PARA REL[ÉE]/.test(raw)) return proposal("ACESSORIOS_RELES_INTERFACE", raw);
  if (/^BLOCO DE DISTRIBUI/.test(raw)) {
    const conexoes = raw.match(/\/(\d+)X/)?.[1];
    return proposal("BLOCOS_DISTRIBUICAO", joinName("BLOCO DE DISTRIBUIÇÃO", conexoes ? `${conexoes} CONEXÕES` : null, secao, /\bBK\b/.test(raw) ? "PRETO" : null));
  }
  if (/CANALETA/.test(raw)) {
    const dimensao = raw.match(/\d+\s*X\s*\d+/)?.[0]?.replace(/\s+/g, "") || null;
    return proposal("CANALETAS_PARA_PAINEIS", joinName("CANALETA PARA PAINEL", dimensao ? `${dimensao}MM` : null, /PERF|PRF|ABERTA/.test(raw) ? "PERFURADA" : null));
  }
  if (/CARCA[CÇ]A|INSERTO DE CONTATO|INSERTO P\//.test(raw)) return proposal("CONECTORES_INDUSTRIAIS_MULTIPOLARES", /INSERTO/.test(raw) ? "INSERTO DE CONTATO PARA CONECTOR INDUSTRIAL MULTIPOLAR" : "CARCAÇA PARA CONECTOR INDUSTRIAL MULTIPOLAR");
  if (/^(BASE|TOMADA).*\bHC-/.test(raw) || /TOMADA POLARIZADA MONTADA/.test(raw)) return proposal("CONECTORES_INDUSTRIAIS_MULTIPOLARES", /BASE/.test(raw) ? "BASE PARA CONECTOR INDUSTRIAL MULTIPOLAR" : "CONECTOR INDUSTRIAL MULTIPOLAR MONTADO");
  if (/CONECTOR DE FO/.test(raw)) return proposal("CONECTORES_REDE_INDUSTRIAL", "CONECTOR DE FIBRA ÓPTICA MULTIMODO");
  if (/VS-08-RJ45|CUC-IND/.test(raw)) return proposal("CONECTORES_REDE_INDUSTRIAL", "CONECTOR RJ45 PARA REDE INDUSTRIAL");
  if (!/^CABO/.test(raw) && /\b(SACC|SAC)-.*M(?:8|12)|CONECTOR.*M(?:8|12)/.test(raw)) return proposal("CONECTORES_PARA_SENSORES", joinName("CONECTOR", raw.includes("M12") ? "M12" : "M8", poles(raw)));
  if (/^CABO COM CONECTOR|CABO COM CONECTOR$/.test(raw)) {
    const material = raw.match(/\b(PVC|PUR)\b/)?.[1];
    return proposal("CABOS_PARA_SENSORES", joinName("CABO COM CONECTOR", raw.includes("M12") ? "M12" : raw.includes("M8") ? "M8" : null, poles(raw), length(raw), material));
  }
  if (/^CABO SEM CONECTOR/.test(raw)) {
    if (/VS-OE-OE-93A/.test(raw)) return proposal("CABOS_REDE_INDUSTRIAL", "CABO DE REDE INDUSTRIAL PROFINET CAT5 BLINDADO 100m");
    if (/VS-OE-OE-94B/.test(raw)) return proposal("CABOS_REDE_INDUSTRIAL", "CABO DE REDE INDUSTRIAL ETHERNET CAT5E 1GBIT/S BLINDADO 100m");
    return proposal("CABOS_PARA_SENSORES", joinName("CABO PARA SENSOR", length(raw)));
  }
  if (/^BORNE PASSAGEM/.test(raw) || /^PTPOWER/.test(raw) || /CONECTOR .*?-\s*(?:PTTB|PTIO|PTPOWER|PT|UK)/.test(raw)) {
    const protecao = /(?:-PE\b|\bTERRA\b)/.test(raw);
    return proposal(protecao ? "CONEXOES_BORNES_PROTECAO" : "CONEXOES_BORNES_PASSAGEM", joinName(protecao ? "BORNE DE PROTEÇÃO" : "BORNE DE PASSAGEM", secao));
  }
  if (/CONVERSOR DE SINAIS/.test(raw)) return proposal("CONDICIONADORES_SINAL", "CONDICIONADOR DE SINAL");
  if (/DISJUNTOR ELETRÔNICO/.test(raw)) {
    const faixa = raw.match(/\d+\s*(?:DC|VCC)\s*\/\s*\d+-\d+\s*A/i)?.[0]?.replace(/\s+/g, "")?.replace("DC", "VCC");
    return proposal("DISJUNTORES_ELETRONICOS", joinName("DISJUNTOR ELETRÔNICO", faixa));
  }
  if (/ETIQUETA|FOLHA PL[ÁA]STICA|IDENTIFICADOR|THERMOMARK.*FITA/.test(raw)) return proposal("IDENTIFICACAO_PARA_PAINEIS", "MATERIAL DE IDENTIFICAÇÃO PARA PAINEL");
  if (/^E\/UK/.test(raw)) return proposal("ACESSORIOS_PARA_BORNES", "GRAMPO FINAL PARA BORNES EM TRILHO DIN");
  if (/SUPORTE.*CONECTOR/.test(raw)) return proposal("ACESSORIOS_PARA_BORNES", "SUPORTE PARA BORNE");
  return proposal(null, raw, "Descrição sem função técnica confirmada para normalização automática.");
}

const SICK_POR_CODIGO = new Map([
  ["1085351", ["CONTROLADORES_SEGURANCA", "CONTROLADOR DE SEGURANÇA FLEXI COMPACT 20DI 4DO"]],
  ["1085354", ["MODULOS_SEGURANCA_MODULARES", "MÓDULO DE E/S DE SEGURANÇA FLEXI COMPACT 8DI/8DO"]],
  ["1091946", ["CHAVES_SEGURANCA", "SENSOR DE SEGURANÇA INDUTIVO M12 4MM 2OSSD"]],
  ["5321176", ["ATUADORES_CHAVES_SEGURANCA", "ATUADOR RETO PARA CHAVE DE SEGURANÇA RFID TR110"]],
  ["5334663", ["ATUADORES_CHAVES_SEGURANCA", "ATUADOR ANGULAR PARA CHAVE DE SEGURANÇA RFID TR110"]],
  ["6025077", ["CHAVES_SEGURANCA", "CHAVE DE SEGURANÇA POR CABO DE TRAÇÃO 2NF+2NA"]],
  ["6025105", ["CHAVES_SEGURANCA", "CHAVE DE SEGURANÇA ELETROMECÂNICA COM ÊMBOLO DE ROLETE 2NF+2NA"]],
  ["5311138", ["ACESSORIOS_CHAVES_SEGURANCA", "KIT DE CABO 20M PARA CHAVE DE SEGURANÇA POR TRAÇÃO"]],
  ["6022880", ["DISPOSITIVOS_HABILITACAO", "DISPOSITIVO DE HABILITAÇÃO DE SEGURANÇA 2NF+2NA CABO 10M"]],
  ["1220126", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA TRANSMISSORA 750MM RESOLUÇÃO 30MM ALCANCE 30M"]],
  ["1220140", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA RECEPTORA 750MM RESOLUÇÃO 30MM ALCANCE 30M"]],
  ["1211462", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA TRANSMISSORA 300MM RESOLUÇÃO 30MM ALCANCE 15M"]],
  ["1211464", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA RECEPTORA 300MM RESOLUÇÃO 30MM ALCANCE 15M"]],
  ["1211492", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA TRANSMISSORA 450MM RESOLUÇÃO 30MM ALCANCE 15M"]],
  ["1211493", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA RECEPTORA 450MM RESOLUÇÃO 30MM ALCANCE 15M"]],
  ["1211501", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA TRANSMISSORA 1200MM RESOLUÇÃO 30MM ALCANCE 15M"]],
  ["1211502", ["CORTINAS_LUZ_SEGURANCA", "CORTINA DE LUZ DE SEGURANÇA RECEPTORA 1200MM RESOLUÇÃO 30MM ALCANCE 15M"]],
  ["2093097", ["ACESSORIOS_CORTINAS_LUZ", "MÓDULO DE CONEXÃO SP2 PARA CORTINA DE LUZ M12 5 PINOS SEM EXTENSÃO"]],
  ["2076832", ["ACESSORIOS_CORTINAS_LUZ", "MÓDULO DE CONEXÃO SP1 PARA CORTINA DE LUZ M12 5 PINOS SEM EXTENSÃO"]],
  ["1044448", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M12 4MM PNP NA CABO 5M"]],
  ["1040779", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M12 8MM PNP NA CORPO CURTO"]],
  ["1040763", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M12 4MM PNP NA CORPO CURTO"]],
  ["1040780", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M12 8MM PNP NA CORPO PADRÃO"]],
  ["1040764", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M12 4MM PNP NA CORPO PADRÃO"]],
  ["1071277", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M18 20MM PNP NA"]],
  ["1040966", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M18 8MM PNP NA"]],
  ["1041014", ["SENSORES_INDUTIVOS", "SENSOR INDUTIVO M30 15MM PNP NA"]],
  ["6037496", ["SENSORES_FOTOELETRICOS", "SENSOR FOTOELÉTRICO RETRORREFLEXIVO M18 0,05-6M"]],
  ["1041412", ["SENSORES_FOTOELETRICOS", "SENSOR FOTOELÉTRICO COM SUPRESSÃO DE FUNDO 20-350MM"]],
  ["6026216", ["SENSORES_FOTOELETRICOS", "SENSOR FOTOELÉTRICO ENERGÉTICO M12 2-300MM"]],
  ["6041811", ["SENSORES_FOTOELETRICOS", "SENSOR FOTOELÉTRICO ENERGÉTICO M18 1-800MM"]],
  ["1058249", ["SENSORES_FOTOELETRICOS", "SENSOR FOTOELÉTRICO TIPO BARREIRA A LASER 0-50M"]],
  ["6043870", ["SENSORES_FOTOELETRICOS", "SENSOR FOTOELÉTRICO COM SUPRESSÃO DE FUNDO M18 30-200MM"]],
  ["6043946", ["SENSORES_FOTOELETRICOS", "SENSOR FOTOELÉTRICO ENERGÉTICO M18 1-350MM"]],
  ["1003865", ["ACESSORIOS_PARA_SENSORES", "REFLETOR RETANGULAR PARA SENSOR FOTOELÉTRICO 84X84MM"]],
  ["2095653", ["CABOS_PARA_SENSORES", "CABO PARA SENSOR/ATUADOR M12 FÊMEA 8 PINOS 5M PUR"]],
  ["2095617", ["CABOS_PARA_SENSORES", "CABO PARA SENSOR/ATUADOR M12 FÊMEA 5 PINOS 2M PUR"]],
  ["2096236", ["CABOS_PARA_SENSORES", "CABO PARA SENSOR/ATUADOR M12 FÊMEA 4 PINOS 10M PVC"]],
  ["2095619", ["CABOS_PARA_SENSORES", "CABO PARA SENSOR/ATUADOR M12 FÊMEA 5 PINOS 10M PUR"]],
  ["1106555", ["SENSORES_TIPO_GARFO", "SENSOR FOTOELÉTRICO TIPO GARFO ABERTURA 50MM PROFUNDIDADE 60MM OBJETO MÍNIMO 0,5MM"]],
  ["1057091", ["SENSORES_NIVEL", "SENSOR DE NÍVEL CONTÍNUO PARA LÍQUIDOS HASTE 2000MM"]],
  ["6053354", ["SENSORES_NIVEL", "SENSOR DE NÍVEL VIBRATÓRIO PARA LÍQUIDOS"]],
  ["1036721", ["ENCODERS", "ENCODER INCREMENTAL DFS60 10000PPR TTL/HTL"]],
  ["6054712", ["SENSORES_ULTRASSONICOS", "SENSOR ULTRASSÔNICO 350-3400MM SAÍDA ANALÓGICA"]],
  ["6054716", ["SENSORES_ULTRASSONICOS", "SENSOR ULTRASSÔNICO 600-6000MM SAÍDA ANALÓGICA"]],
  ["1114954", ["SENSORES_FLUXO", "SENSOR DE FLUXO CALORIMÉTRICO PARA LÍQUIDOS IO-LINK"]],
  ["6081749", ["SENSORES_TEMPERATURA", "SENSOR DE TEMPERATURA PT1000 4-20MA HASTE 150MM"]],
  ["6042673", ["SENSORES_PRESSAO", "TRANSMISSOR DE PRESSÃO -1 A 9BAR 4-20MA 2 FIOS"]],
]);

function normalizarSick(item) {
  const raw = upper(item.nome);
  const codigo = upper(item.codigo_interno);
  if (codigo === "2066614-COPIA") {
    return proposal("ACESSORIOS_ENCODERS", raw, "Código do cadastro diverge da identificação técnica originalmente contida na descrição.");
  }
  if (codigo === "2066614-COPIA-COPIA") {
    return proposal("ACESSORIOS_ENCODERS", raw, "Código do cadastro diverge da identificação técnica originalmente contida na descrição.");
  }
  if (/PGT-10-PRO/.test(raw)) {
    return proposal("ACESSORIOS_ENCODERS", "FERRAMENTA DE PROGRAMAÇÃO PARA ENCODERS DFS60/DFV60", "Código do cadastro diverge da identificação técnica contida na descrição.");
  }
  if (/DSL-3D08/.test(raw)) {
    return proposal("ACESSORIOS_ENCODERS", "CABO ADAPTADOR DE PROGRAMAÇÃO PARA ENCODERS M23 12 PINOS PARA D-SUB 9 PINOS 0,5M", "Código do cadastro diverge da identificação técnica contida na descrição.");
  }
  if (/\bBEF-|BRACKET.*LIGHT|SUPORTE PARA CORTINA/.test(raw)) return proposal("ACESSORIOS_CORTINAS_LUZ", "SUPORTE PARA CORTINA DE LUZ DE SEGURANÇA");
  const encontrada = SICK_POR_CODIGO.get(codigo.replace(/-DUP\d+$/, ""));
  if (encontrada) return proposal(encontrada[0], encontrada[1]);
  return proposal(null, raw, "Descrição sem função técnica confirmada para normalização automática.");
}

function normalizar(item) {
  if (item.fornecedor_id === 1) return normalizarPhoenix(item);
  if (item.fornecedor_id === 14) return normalizarSick(item);
  if (item.fornecedor_id === 510) return normalizarWago(item);
  return proposal(null, item.nome);
}

async function buscarGrupos() {
  const { data, error } = await supabase
    .from("item_grupos")
    .select("id,codigo,nome,grupo_pai_id")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID);
  if (error) throw error;
  return new Map((data ?? []).map((grupo) => [grupo.codigo, grupo]));
}

async function criarGrupos(grupos) {
  for (const grupoNovo of GRUPOS_NOVOS) {
    if (grupos.has(grupoNovo.codigo)) continue;
    const pai = grupoNovo.pai ? grupos.get(grupoNovo.pai) : null;
    if (grupoNovo.pai && !pai) throw new Error(`Grupo pai ausente: ${grupoNovo.pai}`);
    const { data, error } = await supabase
      .from("item_grupos")
      .insert({
        tenant_id: TENANT_ID,
        empresa_id: EMPRESA_ID,
        codigo: grupoNovo.codigo,
        nome: grupoNovo.nome,
        grupo_pai_id: pai?.id ?? null,
        descricao: "Grupo aprovado para normalização de cadastros WAGO, Phoenix e SICK.",
        ativo: true,
      })
      .select("id,codigo,nome,grupo_pai_id")
      .single();
    if (error) throw error;
    grupos.set(data.codigo, data);
  }
  return grupos;
}

async function main() {
  const { data: itens, error } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,fornecedor_id,grupo_id,ativo")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .in("fornecedor_id", [...FORNECEDORES.keys()])
    .order("fornecedor_id")
    .order("id");
  if (error) throw error;

  let grupos = await buscarGrupos();
  const codigosDeGrupo = new Set([...grupos.keys(), ...GRUPOS_NOVOS.map((grupo) => grupo.codigo)]);
  const paisAusentes = GRUPOS_NOVOS.filter((grupo) => grupo.pai && !codigosDeGrupo.has(grupo.pai)).map((grupo) => grupo.pai);
  if (paisAusentes.length > 0) throw new Error(`Grupos pai ausentes: ${[...new Set(paisAusentes)].join(", ")}`);
  const propostas = itens.map((item) => ({ item, ...normalizar(item) }));
  const pendentes = propostas.filter((item) => item.pendencia);
  const porFornecedor = {};
  const porGrupo = {};
  for (const proposta of propostas) {
    const fornecedor = FORNECEDORES.get(proposta.item.fornecedor_id);
    porFornecedor[fornecedor] = (porFornecedor[fornecedor] ?? 0) + 1;
    porGrupo[proposta.grupo ?? "SEM_ALTERACAO_SEGURA"] = (porGrupo[proposta.grupo ?? "SEM_ALTERACAO_SEGURA"] ?? 0) + 1;
  }
  const alteracoesNecessarias = propostas.filter((proposta) => {
    if (!proposta.grupo) return false;
    const grupo = grupos.get(proposta.grupo);
    return !grupo || proposta.nome !== upper(proposta.item.nome) || String(proposta.item.grupo_id ?? "") !== String(grupo.id);
  });

  console.log(JSON.stringify({
    modo: APPLY ? "APLICAR" : "DIAGNOSTICO",
    total: propostas.length,
    porFornecedor,
    porGrupo,
    itensSemGrupoNoBanco: itens.filter((item) => !item.grupo_id).length,
    alteracoesNecessarias: alteracoesNecessarias.map((proposta) => ({
      id: proposta.item.id,
      codigo: proposta.item.codigo_interno,
      nomeAtual: proposta.item.nome,
      nomeProposto: proposta.nome,
      grupoProposto: proposta.grupo,
    })),
    pendentes: pendentes.map((p) => ({ id: p.item.id, codigo: p.item.codigo_interno, nome: p.item.nome, motivo: p.pendencia })),
  }, null, 2));

  if (!APPLY) return;
  grupos = await criarGrupos(grupos);
  let atualizados = 0;
  for (const proposta of propostas) {
    if (!proposta.grupo) continue;
    const grupo = grupos.get(proposta.grupo);
    if (!grupo) throw new Error(`Grupo não encontrado: ${proposta.grupo}`);
    const alteracoes = {};
    if (proposta.nome && proposta.nome !== upper(proposta.item.nome)) alteracoes.nome = proposta.nome;
    if (String(proposta.item.grupo_id ?? "") !== String(grupo.id)) alteracoes.grupo_id = grupo.id;
    if (Object.keys(alteracoes).length === 0) continue;
    const { error: updateError } = await supabase
      .from("itens")
      .update(alteracoes)
      .eq("id", proposta.item.id)
      .eq("tenant_id", TENANT_ID)
      .eq("empresa_id", EMPRESA_ID);
    if (updateError) throw new Error(`Item ${proposta.item.id}: ${updateError.message}`);
    atualizados += 1;
  }
  console.log(JSON.stringify({ resultado: "concluido", gruposNovos: GRUPOS_NOVOS.length, itensAtualizados: atualizados, itensPendentes: pendentes.length }, null, 2));
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
