"use client";

import { Fragment, useCallback, useMemo, useRef, useState, type ChangeEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { formatDecimalBR } from "@/lib/decimal";

type AssistenteIARequiredColumnKey = "qtd" | "componente" | "codigo" | "marca";
type AssistenteIAColumnKey = "id" | AssistenteIARequiredColumnKey;
type AssistenteIAColumnIndexes = Record<AssistenteIARequiredColumnKey, number> & { id: number | null };

type AssistenteIARawRow = {
  linha: number;
  cells: string[];
};

type AssistenteIAItemPlanilha = {
  linha: number;
  itemId: number | null;
  qtd: number;
  componente: string;
  codigo: string;
  marca: string;
  importStatus?: AssistenteIAImportStatus;
  importMessage?: string;
  erro?: string;
};

type AssistenteIAImportStatus = "pendente" | "importado" | "ignorado" | "erro";
type AssistenteIAStatusPreco = "preco_atualizado" | "preco_antigo" | "preco_muito_antigo" | "sem_historico";
type AssistenteIADecisao = "aceitar" | "revisar" | "cotar_cadastrar" | "ignorar";
type AssistenteIATipoResultado = "produto_unico" | "composicao" | "equivalente" | "nao_encontrado" | "precisa_revisao";
type AssistenteIAPapelProduto =
  | "produto_principal"
  | "lateral"
  | "base_soleira"
  | "acessorio"
  | "equivalente"
  | "alternativa"
  | "outro";
type AssistenteIAGrupoDiagnostico =
  | "codigo_exato"
  | "codigo_parcial"
  | "mesma_familia"
  | "mesma_categoria"
  | "equivalente_tecnico"
  | "alternativa_fabricante"
  | "produto_principal"
  | "lateral"
  | "base_soleira"
  | "acessorio"
  | "equivalente"
  | "geral";

type AssistenteIAEspecificacoesDetectadas = {
  familia?: string;
  correnteA?: number;
  correnteMotorA?: number;
  tensaoV?: number;
  tensaoMinV?: number;
  tensaoMaxV?: number;
  potenciaW?: number;
};

type AssistenteIAPlanoBuscaEspecificacoes = {
  tensaoV?: number;
  correnteA?: number;
  potenciaW?: number;
  familia?: string;
  modelo?: string;
};

type AssistenteIAPlanoBuscaGrupo = {
  papel: "produto_principal" | "lateral" | "base_soleira" | "acessorio" | "equivalente" | "alternativa";
  termosObrigatorios: string[];
  termosDesejaveis: string[];
  termosProibidos: string[];
  marcaPreferencial?: string;
  observacao: string;
};

type AssistenteIAPlanoBusca = {
  linha: number;
  categoriaTecnica:
    | "armario_painel"
    | "soft_starter"
    | "rele_estado_solido"
    | "fonte_24v"
    | "borne"
    | "disjuntor"
    | "contator"
    | "clp"
    | "ihm"
    | "seguranca"
    | "sinalizacao"
    | "ventilacao"
    | "desconhecida";
  itemComposto: boolean;
  marcaPreferencial?: string;
  fabricantesAlternativos?: string[];
  dimensoes?: string[];
  especificacoes?: AssistenteIAPlanoBuscaEspecificacoes;
  gruposBusca: AssistenteIAPlanoBuscaGrupo[];
};

type AssistenteIAProdutoSelecionado = {
  produtoId: string;
  codigo: string;
  descricao: string;
  marca?: string;
  fornecedorNome?: string;
  qtdSugerida: number;
  papelNaComposicao: AssistenteIAPapelProduto;
  justificativa: string;
  origem?: AssistenteIAOrigemProdutoRevisado;
  ultimaCompraData?: string;
  ultimaCompraValorUnitario?: number;
  estoque?: number;
  statusPreco: AssistenteIAStatusPreco;
};

type AssistenteIAStatusRevisaoProduto = "pendente" | "confirmado" | "removido";
type AssistenteIAOrigemProdutoRevisado = "ia" | "manual" | "planilha";

type AssistenteIAProdutoRevisado = {
  produtoId: string;
  codigo: string;
  descricao: string;
  marca?: string;
  fornecedorNome?: string;
  qtdSugerida: number;
  papelNaComposicao: AssistenteIAPapelProduto;
  origem: AssistenteIAOrigemProdutoRevisado;
  statusRevisao: AssistenteIAStatusRevisaoProduto;
};

type AssistenteIARevisaoLinha = {
  linha: number;
  decisao: AssistenteIADecisao;
  produtos: AssistenteIAProdutoRevisado[];
  observacaoUsuario?: string;
  revisado: boolean;
};

type AssistenteIACandidatoDiagnostico = {
  produtoId: string;
  codigo: string;
  descricao: string;
  fornecedorNome?: string;
  grupo: string;
  pontuacaoBackend: number;
  scoreFinal: number;
  categoriaCandidatoDetectada?: string;
  motivos: string[];
  penalidades?: string[];
};

type AssistenteIADiagnostico = {
  planoBusca?: AssistenteIAPlanoBusca;
  termosExtraidos: string[];
  dimensoesDetectadas: string[];
  codigoNormalizado?: string;
  marcaPriorizada?: string;
  categoriaTecnicaDetectada?: string;
  especificacoesDetectadas?: AssistenteIAEspecificacoesDetectadas;
  gruposDetectados: AssistenteIAGrupoDiagnostico[];
  candidatosResumo: AssistenteIACandidatoDiagnostico[];
  candidatosEnviadosParaIA: number;
  candidatosBancoAntesFiltro?: number;
  candidatosAposCategoriaBase?: number;
  candidatosRemovidosPorValidacao: number;
  candidatosRemovidosPorIncompatibilidade?: number;
  candidatosRemovidosPorTermosProibidos?: number;
  candidatosRemovidosPorScore?: number;
  fallbackAcionado?: boolean;
};

type AssistenteIAResultadoAnalise = {
  linha: number;
  qtdOriginal: number;
  componenteOriginal: string;
  codigoOriginal: string;
  marcaOriginal: string;
  tipoResultado: AssistenteIATipoResultado;
  produtosSelecionados: AssistenteIAProdutoSelecionado[];
  confianca: number;
  decisaoSugerida: AssistenteIADecisao;
  resumoIA: string;
  alertaTecnico?: string;
  termosBuscaUsados: string[];
  categoriaTecnicaDetectada?: string;
  especificacoesDetectadas?: AssistenteIAEspecificacoesDetectadas;
  diagnostico?: AssistenteIADiagnostico;
};

type AssistenteIAModalProps = {
  open: boolean;
  idParam: string;
  supabase: SupabaseClient | null;
  tenantId: string | null;
  empresaId: string | null;
  onClose: () => void;
  onImported?: () => void | Promise<void>;
};

type AssistenteIAAdicionarItemResposta = {
  adicionados?: Array<{ linha: number; produtoId: string; itemOrcamentoId?: string; mensagem: string }>;
  ignorados?: Array<{ linha: number; produtoId?: string; motivo: string }>;
  erros?: Array<{ linha: number; produtoId?: string; erro: string }>;
  avisos?: Array<{ linha: number; produtoId?: string; aviso: string }>;
  resumo?: {
    totalSolicitado: number;
    totalAdicionado: number;
    totalIgnorado: number;
    totalErro: number;
  };
  error?: string;
};

const ASSISTENTE_IA_REQUIRED_COLUMNS_MESSAGE =
  "A planilha precisa conter as colunas: Qtd, Componente, Código e Marca. A coluna ID é opcional para itens já cadastrados.";
const ASSISTENTE_IA_FILE_READ_ERROR_MESSAGE =
  "Não foi possível ler o arquivo selecionado. Tente selecionar a planilha novamente ou feche o arquivo caso ele esteja aberto em outro programa.";

const ASSISTENTE_IA_COLUMN_VARIANTS: Record<AssistenteIAColumnKey, string[]> = {
  id: ["id", "itemid", "produtoid", "codigoitem", "codigoiteminterno"],
  qtd: ["qtd", "quantidade", "qtde"],
  componente: ["componente", "item", "descricao"],
  codigo: ["codigo", "cod", "codigoreferencia", "referencia"],
  marca: ["marca", "fabricante"],
};

const ASSISTENTE_IA_PAPEIS_PRODUTO: AssistenteIAPapelProduto[] = [
  "produto_principal",
  "lateral",
  "base_soleira",
  "acessorio",
  "equivalente",
  "alternativa",
  "outro",
];

function normalizeAssistenteIAColumnName(value: string | null | undefined): string {
  return String(value ?? "")
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function getAssistenteIAColumnIndexes(headers: string[]): AssistenteIAColumnIndexes | null {
  const normalizedHeaders = headers.map((header) => normalizeAssistenteIAColumnName(header));
  const findColumnIndex = (key: AssistenteIAColumnKey) => {
    const variants = new Set(ASSISTENTE_IA_COLUMN_VARIANTS[key].map((variant) => normalizeAssistenteIAColumnName(variant)));
    return normalizedHeaders.findIndex((header) => variants.has(header));
  };

  const id = findColumnIndex("id");
  const qtd = findColumnIndex("qtd");
  const componente = findColumnIndex("componente");
  const codigo = findColumnIndex("codigo");
  const marca = findColumnIndex("marca");

  if (qtd < 0 || componente < 0 || codigo < 0 || marca < 0) return null;
  return { id: id >= 0 ? id : null, qtd, componente, codigo, marca };
}

function isAssistenteIARowEmpty(cells: string[]): boolean {
  return cells.every((cell) => !String(cell ?? "").trim());
}

function getAssistenteIACell(cells: string[], index: number): string {
  return String(cells[index] ?? "").trim();
}

function parseAssistenteIAQtd(value: string): number {
  const cleaned = value
    .trim()
    .replace(/\s+/g, "")
    .replace(/[^\d,.-]/g, "");
  if (!cleaned) return NaN;
  const normalized = cleaned.includes(",") ? cleaned.replace(/\./g, "").replace(",", ".") : cleaned;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function parseAssistenteIAItemId(value: string): number | null {
  const raw = value.trim();
  if (!raw) return null;

  const normalized = raw.replace(/\s+/g, "").replace(/\./g, "").replace(",", ".");
  const parsed = Number(normalized);
  if (Number.isFinite(parsed) && parsed > 0) return Math.trunc(parsed);

  const digitsOnly = raw.replace(/\D/g, "");
  if (!digitsOnly) return null;
  const parsedDigits = Number(digitsOnly);
  return Number.isFinite(parsedDigits) && parsedDigits > 0 ? parsedDigits : null;
}

function buildAssistenteIAPreview(rows: AssistenteIARawRow[]): AssistenteIAItemPlanilha[] {
  const headerIndex = rows.findIndex((row) => !isAssistenteIARowEmpty(row.cells));
  if (headerIndex < 0) throw new Error(ASSISTENTE_IA_REQUIRED_COLUMNS_MESSAGE);

  const columns = getAssistenteIAColumnIndexes(rows[headerIndex].cells);
  if (!columns) throw new Error(ASSISTENTE_IA_REQUIRED_COLUMNS_MESSAGE);

  return rows
    .slice(headerIndex + 1)
    .filter((row) => !isAssistenteIARowEmpty(row.cells))
    .map((row) => {
      const itemIdRaw = columns.id === null ? "" : getAssistenteIACell(row.cells, columns.id);
      const itemId = parseAssistenteIAItemId(itemIdRaw);
      const qtdRaw = getAssistenteIACell(row.cells, columns.qtd);
      const qtd = parseAssistenteIAQtd(qtdRaw);
      const componente = getAssistenteIACell(row.cells, columns.componente);
      const codigo = getAssistenteIACell(row.cells, columns.codigo);
      const marca = getAssistenteIACell(row.cells, columns.marca);
      const errors: string[] = [];

      if (itemIdRaw && itemId === null) errors.push("ID deve ser numérico quando preenchido.");
      if (!Number.isFinite(qtd) || qtd <= 0) errors.push("Qtd deve ser numérica e maior que zero.");
      if (!componente) errors.push("Componente obrigatório.");

      return {
        linha: row.linha,
        itemId,
        qtd,
        componente,
        codigo,
        marca,
        erro: errors.length ? errors.join(" ") : undefined,
      };
    });
}

function countCsvDelimiterOutsideQuotes(line: string, delimiter: string): number {
  let count = 0;
  let inQuotes = false;

  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') i += 1;
      else inQuotes = !inQuotes;
    } else if (!inQuotes && ch === delimiter) {
      count += 1;
    }
  }

  return count;
}

function detectAssistenteIACsvDelimiter(text: string): string {
  const source = text.replace(/^\uFEFF/, "");
  const firstLine = source.split(/\r\n|\n|\r/)[0]?.trim() ?? "";
  if (/^sep\s*=/i.test(firstLine)) return firstLine.split("=")[1]?.trim().charAt(0) || ";";

  const sampleLine =
    source
      .split(/\r\n|\n|\r/)
      .find((line) => line.trim().length > 0) ?? "";
  const candidates = [";", ",", "\t"];

  return candidates
    .map((delimiter) => ({ delimiter, count: countCsvDelimiterOutsideQuotes(sampleLine, delimiter) }))
    .sort((a, b) => b.count - a.count)[0]?.delimiter ?? ",";
}

function stripCsvSeparatorLine(text: string): { source: string; rowOffset: number } {
  const source = text.replace(/^\uFEFF/, "");
  const firstLine = source.split(/\r\n|\n|\r/)[0] ?? "";
  if (!/^sep\s*=/i.test(firstLine.trim())) return { source, rowOffset: 0 };

  let nextStart = firstLine.length;
  if (source.slice(nextStart, nextStart + 2) === "\r\n") nextStart += 2;
  else if (source[nextStart] === "\n" || source[nextStart] === "\r") nextStart += 1;
  return { source: source.slice(nextStart), rowOffset: 1 };
}

function parseAssistenteIACsvRows(text: string): AssistenteIARawRow[] {
  const { source, rowOffset } = stripCsvSeparatorLine(text);
  const delimiter = detectAssistenteIACsvDelimiter(text);
  const rows: AssistenteIARawRow[] = [];
  let row: string[] = [];
  let cell = "";
  let linha = 1 + rowOffset;
  let inQuotes = false;

  const pushCell = () => {
    row.push(cell.trim());
    cell = "";
  };

  const pushRow = () => {
    rows.push({ linha, cells: row });
    row = [];
    linha += 1;
  };

  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];
    if (ch === '"') {
      if (inQuotes && source[i + 1] === '"') {
        cell += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (!inQuotes && ch === delimiter) {
      pushCell();
    } else if (!inQuotes && (ch === "\n" || ch === "\r")) {
      pushCell();
      pushRow();
      if (ch === "\r" && source[i + 1] === "\n") i += 1;
    } else {
      cell += ch;
    }
  }

  const endedWithLineBreak = source.endsWith("\n") || source.endsWith("\r");
  if (cell.length > 0 || row.length > 0 || !endedWithLineBreak) {
    pushCell();
    pushRow();
  }

  return rows;
}

function toAssistenteIACellText(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value).trim();
}

function isAssistenteIAFileReadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error ?? "");
  const normalized = message.toLowerCase();
  return (
    normalized.includes("could not be read") ||
    normalized.includes("permission") ||
    normalized.includes("notreadable") ||
    normalized.includes("not readable")
  );
}

function readFileAsArrayBufferFallback(file: File): Promise<ArrayBuffer> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      if (reader.result instanceof ArrayBuffer) {
        resolve(reader.result);
        return;
      }
      reject(new Error(ASSISTENTE_IA_FILE_READ_ERROR_MESSAGE));
    };
    reader.onerror = () => reject(new Error(ASSISTENTE_IA_FILE_READ_ERROR_MESSAGE));
    reader.readAsArrayBuffer(file);
  });
}

async function readFileAsArrayBuffer(file: File): Promise<ArrayBuffer> {
  try {
    return await file.arrayBuffer();
  } catch {
    return readFileAsArrayBufferFallback(file);
  }
}

function readFileAsText(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result ?? ""));
    reader.onerror = () => reject(new Error(ASSISTENTE_IA_FILE_READ_ERROR_MESSAGE));
    reader.readAsText(file, "utf-8");
  });
}

async function parseAssistenteIAXlsxRows(file: File): Promise<AssistenteIARawRow[]> {
  const XLSX = await import("xlsx");
  const arrayBuffer = await readFileAsArrayBuffer(file);
  const workbook = XLSX.read(arrayBuffer, { type: "array" });
  const firstSheetName = workbook.SheetNames[0];
  if (!firstSheetName) throw new Error("A planilha não possui abas.");

  const sheet = workbook.Sheets[firstSheetName];
  const rows = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: "", raw: false, blankrows: false });
  return rows.map((cells, index) => ({
    linha: index + 1,
    cells: cells.map(toAssistenteIACellText),
  }));
}

async function parseAssistenteIAFileRows(file: File): Promise<AssistenteIARawRow[]> {
  const name = file.name.toLowerCase();
  if (name.endsWith(".csv")) return parseAssistenteIACsvRows(await readFileAsText(file));
  if (name.endsWith(".xlsx")) return parseAssistenteIAXlsxRows(file);
  throw new Error("Selecione uma planilha .xlsx ou .csv.");
}

function assistenteIATipoResultadoLabel(tipo: AssistenteIATipoResultado): string {
  switch (tipo) {
    case "produto_unico":
      return "Produto único";
    case "composicao":
      return "Composição";
    case "equivalente":
      return "Equivalente para revisão";
    case "nao_encontrado":
      return "Não encontrado";
    case "precisa_revisao":
      return "Precisa revisão";
  }
}

function assistenteIATipoResultadoClass(tipo: AssistenteIATipoResultado): string {
  if (tipo === "produto_unico") return "text-emerald-300";
  if (tipo === "composicao") return "text-cyan-300";
  if (tipo === "equivalente") return "text-amber-300";
  if (tipo === "nao_encontrado") return "text-orange-300";
  return "text-zinc-300";
}

function assistenteIATipoResultadoVisivel(item: AssistenteIAResultadoAnalise): AssistenteIATipoResultado {
  if (item.tipoResultado === "nao_encontrado" && item.produtosSelecionados.length > 0) return "equivalente";
  return item.tipoResultado;
}

function assistenteIAPapelLabel(papel: AssistenteIAPapelProduto): string {
  switch (papel) {
    case "produto_principal":
      return "Produto principal";
    case "lateral":
      return "Lateral";
    case "base_soleira":
      return "Base soleira";
    case "acessorio":
      return "Acessório";
    case "equivalente":
      return "Equivalente";
    case "alternativa":
      return "Alternativa";
    case "outro":
      return "Outro";
  }
}

function assistenteIAGrupoDiagnosticoLabel(grupo: string): string {
  switch (grupo) {
    case "codigo_exato":
      return "Código exato";
    case "codigo_parcial":
      return "Código parcial";
    case "mesma_familia":
      return "Mesma família";
    case "mesma_categoria":
      return "Mesma categoria";
    case "equivalente_tecnico":
      return "Equivalente técnico";
    case "alternativa_fabricante":
      return "Alternativa fabricante";
    case "produto_principal":
      return "Produto principal";
    case "lateral":
      return "Lateral";
    case "base_soleira":
      return "Base soleira";
    case "acessorio":
      return "Acessório";
    case "equivalente":
      return "Equivalente";
    case "geral":
      return "Geral";
    default:
      return grupo.replace(/_/g, " ");
  }
}

function assistenteIAGrupoResumoLabel(grupo: string): string {
  return grupo
    .split(",")
    .map((part) => assistenteIAGrupoDiagnosticoLabel(part.trim()))
    .filter(Boolean)
    .join(", ");
}

function assistenteIADecisaoLabel(decisao: AssistenteIADecisao): string {
  switch (decisao) {
    case "aceitar":
      return "Aceitar";
    case "revisar":
      return "Revisar";
    case "cotar_cadastrar":
      return "Cotar/Cadastrar";
    case "ignorar":
      return "Ignorar";
  }
}

function assistenteIADecisaoClass(decisao: AssistenteIADecisao): string {
  if (decisao === "aceitar") return "text-emerald-300";
  if (decisao === "revisar") return "text-amber-300";
  if (decisao === "cotar_cadastrar") return "text-orange-300";
  return "text-zinc-400";
}

function assistenteIAStatusRevisaoLabel(status: AssistenteIAStatusRevisaoProduto): string {
  switch (status) {
    case "confirmado":
      return "Confirmado";
    case "removido":
      return "Removido";
    case "pendente":
      return "Pendente";
  }
}

function assistenteIAStatusRevisaoClass(status: AssistenteIAStatusRevisaoProduto): string {
  if (status === "confirmado") return "text-emerald-300 border-emerald-500/30 bg-emerald-500/10";
  if (status === "removido") return "text-orange-300 border-orange-500/30 bg-orange-500/10";
  return "text-amber-300 border-amber-500/30 bg-amber-500/10";
}

function assistenteIAOrigemProdutoLabel(origem: AssistenteIAOrigemProdutoRevisado): string {
  if (origem === "manual") return "Manual";
  if (origem === "planilha") return "Planilha";
  return "IA";
}

function formatAssistenteIANumber(value: number): string {
  return Number.isInteger(value) ? String(value) : formatDecimalBR(value, 3);
}

function isAssistenteIAPreviewValid(item: AssistenteIAItemPlanilha): boolean {
  return !item.erro;
}

function isAssistenteIAImportavel(item: AssistenteIAItemPlanilha): boolean {
  return isAssistenteIAPreviewValid(item) && Boolean(item.itemId) && item.importStatus !== "importado" && item.importStatus !== "ignorado";
}

function isAssistenteIAPendenteImportacao(item: AssistenteIAItemPlanilha): boolean {
  return isAssistenteIAPreviewValid(item) && Boolean(item.itemId) && !item.importStatus;
}

function isAssistenteIAElegivelAnalise(item: AssistenteIAItemPlanilha): boolean {
  if (!isAssistenteIAPreviewValid(item)) return false;
  if (item.importStatus === "importado" || item.importStatus === "ignorado") return false;
  if (item.itemId && item.importStatus !== "erro") return false;
  return true;
}

function assistenteIAPreviewStatusLabel(item: AssistenteIAItemPlanilha): string {
  if (item.erro) return item.erro;
  if (item.importStatus === "importado") return item.importMessage || "Importado";
  if (item.importStatus === "ignorado") return item.importMessage || "Ignorado";
  if (item.importStatus === "erro") return item.importMessage || "Não importado";
  if (item.itemId) return "Cadastrado";
  return "Pendente IA";
}

function assistenteIAPreviewStatusClass(item: AssistenteIAItemPlanilha): string {
  const base = "px-3 py-2 min-w-[220px] whitespace-normal break-words";
  if (item.erro || item.importStatus === "erro") return `${base} text-amber-300`;
  if (item.importStatus === "importado") return `${base} text-emerald-300`;
  if (item.importStatus === "ignorado") return `${base} text-zinc-400`;
  if (item.itemId) return `${base} text-cyan-300`;
  return `${base} text-amber-300`;
}

function assistenteIACategoriaTecnicaLabel(value?: string): string {
  switch (value) {
    case "soft_starter":
      return "Soft-starter";
    case "rele_estado_solido":
      return "Relé de estado sólido";
    case "fonte_alimentacao":
    case "fonte_24v":
      return "Fonte de alimentação";
    case "armario_painel":
      return "Armário/Painel";
    case "borne":
      return "Borne";
    case "disjuntor":
      return "Disjuntor";
    case "contator":
      return "Contator";
    case "clp":
      return "CLP";
    case "ihm":
      return "IHM";
    case "seguranca":
      return "Segurança";
    case "sinalizacao":
      return "Sinalização";
    case "ventilacao":
      return "Ventilação";
    case "desconhecida":
      return "Desconhecida";
    default:
      return value ? value.replace(/_/g, " ") : "-";
  }
}

function assistenteIAEspecificacoesPills(specs?: AssistenteIAEspecificacoesDetectadas): string[] {
  if (!specs) return [];
  const values: string[] = [];
  if (specs.familia) values.push(`Família ${specs.familia}`);
  if (typeof specs.correnteA === "number") values.push(`Corrente ${formatAssistenteIANumber(specs.correnteA)}A`);
  if (typeof specs.correnteMotorA === "number") values.push(`Motor ${formatAssistenteIANumber(specs.correnteMotorA)}A`);
  if (typeof specs.tensaoV === "number") values.push(`Tensão ${formatAssistenteIANumber(specs.tensaoV)}V`);
  if (typeof specs.tensaoMinV === "number" && typeof specs.tensaoMaxV === "number") {
    values.push(`Tensão ${formatAssistenteIANumber(specs.tensaoMinV)}-${formatAssistenteIANumber(specs.tensaoMaxV)}V`);
  }
  if (typeof specs.potenciaW === "number") values.push(`Potência ${formatAssistenteIANumber(specs.potenciaW)}W`);
  return values;
}

function buildAssistenteIADecisoesSugeridas(results: AssistenteIAResultadoAnalise[]): Record<number, AssistenteIADecisao> {
  return results.reduce<Record<number, AssistenteIADecisao>>((acc, item) => {
    acc[item.linha] = item.decisaoSugerida;
    return acc;
  }, {});
}

function buildAssistenteIAProdutoRevisadoFromIA(produto: AssistenteIAProdutoSelecionado): AssistenteIAProdutoRevisado {
  return {
    produtoId: produto.produtoId,
    codigo: produto.codigo,
    descricao: produto.descricao,
    marca: produto.marca,
    fornecedorNome: produto.fornecedorNome,
    qtdSugerida: produto.qtdSugerida > 0 ? produto.qtdSugerida : 1,
    papelNaComposicao: produto.papelNaComposicao,
    origem: produto.origem ?? "ia",
    statusRevisao: "pendente",
  };
}

function buildAssistenteIARevisoesIniciais(results: AssistenteIAResultadoAnalise[]): Record<number, AssistenteIARevisaoLinha> {
  return results.reduce<Record<number, AssistenteIARevisaoLinha>>((acc, item) => {
    acc[item.linha] = {
      linha: item.linha,
      decisao: item.decisaoSugerida,
      produtos: item.produtosSelecionados.map(buildAssistenteIAProdutoRevisadoFromIA),
      revisado: false,
    };
    return acc;
  }, {});
}

function buildAssistenteIARevisaoSummary(revisoes: Record<number, AssistenteIARevisaoLinha>, totalLinhas: number) {
  const linhas = Object.values(revisoes);
  const linhasRevisadas = linhas.filter((linha) => linha.revisado).length;
  const produtos = linhas.flatMap((linha) => linha.produtos);

  return {
    linhasRevisadas,
    linhasPendentes: Math.max(0, totalLinhas - linhasRevisadas),
    produtosConfirmados: produtos.filter((produto) => produto.statusRevisao === "confirmado").length,
    produtosRemovidos: produtos.filter((produto) => produto.statusRevisao === "removido").length,
    linhasCotacaoCadastro: linhas.filter((linha) => linha.decisao === "cotar_cadastrar").length,
    linhasIgnoradas: linhas.filter((linha) => linha.decisao === "ignorar").length,
  };
}

async function readAssistenteIAJson<T extends { error?: string }>(res: Response, fallback: string): Promise<T> {
  const text = await res.text();
  let json: T | null = null;

  if (text) {
    try {
      json = JSON.parse(text) as T;
    } catch {
      json = null;
    }
  }

  if (!res.ok) {
    const responseError = typeof json?.error === "string" && json.error.trim() ? json.error.trim() : "";
    const textError = text && !text.trim().startsWith("<") ? text.trim().slice(0, 300) : "";
    throw new Error(responseError || textError || `${fallback} (HTTP ${res.status}).`);
  }

  return json ?? ({} as T);
}

function AssistenteIADiagnosticoPills({ values, emptyLabel }: { values: string[]; emptyLabel: string }) {
  if (values.length === 0) return <span className="text-zinc-500">{emptyLabel}</span>;
  return (
    <div className="flex flex-wrap gap-1.5">
      {values.map((value) => (
        <span key={value} className="rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-[11px] text-zinc-200">
          {value}
        </span>
      ))}
    </div>
  );
}

function AssistenteIADiagnosticoDetalhe({ item }: { item: AssistenteIAResultadoAnalise }) {
  const diagnostico = item.diagnostico;
  if (!diagnostico) {
    return <div className="rounded-md border border-zinc-800 bg-zinc-950 p-3 text-sm text-zinc-500">Diagnóstico não disponível.</div>;
  }

  const produtosSelecionados = item.produtosSelecionados;
  const categoriaTecnica = item.categoriaTecnicaDetectada ?? diagnostico.categoriaTecnicaDetectada;
  const especificacoesDetectadas = item.especificacoesDetectadas ?? diagnostico.especificacoesDetectadas;
  const especificacoesPills = assistenteIAEspecificacoesPills(especificacoesDetectadas);
  const candidatoResumoById = new Map(diagnostico.candidatosResumo.map((candidato) => [candidato.produtoId, candidato]));
  const planoBusca = diagnostico.planoBusca;
  const planoEspecificacoesPills = assistenteIAEspecificacoesPills(planoBusca?.especificacoes);
  const termosProibidosAplicados = Array.from(new Set(planoBusca?.gruposBusca.flatMap((grupo) => grupo.termosProibidos) ?? []));

  return (
    <div className="max-h-80 overflow-y-auto rounded-md border border-zinc-800 bg-zinc-950/80 p-3 text-[11px] text-zinc-300">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
        <div className="space-y-2">
          <div>
            <div className="text-zinc-500">Item original</div>
            <div className="mt-1 text-sm text-zinc-100">{item.componenteOriginal || "-"}</div>
            <div className="mt-1 text-zinc-500">
              Qtd {formatDecimalBR(item.qtdOriginal, 3)} · Código {item.codigoOriginal || "-"} · Marca {item.marcaOriginal || "-"}
            </div>
          </div>

          <div>
            <div className="text-zinc-500">Categoria técnica detectada</div>
            <div className="mt-1 text-sm text-zinc-100">{assistenteIACategoriaTecnicaLabel(categoriaTecnica)}</div>
          </div>

          <div>
            <div className="text-zinc-500">Especificações detectadas</div>
            <div className="mt-1">
              <AssistenteIADiagnosticoPills values={especificacoesPills} emptyLabel="Nenhuma especificação técnica detectada." />
            </div>
          </div>

          <div>
            <div className="text-zinc-500">Plano de busca</div>
            {planoBusca ? (
              <div className="mt-1 rounded border border-zinc-800 bg-zinc-900/60 px-2 py-1.5">
                <div className="text-zinc-100">{assistenteIACategoriaTecnicaLabel(planoBusca.categoriaTecnica)}</div>
                <div className="mt-0.5 text-zinc-500">
                  {planoBusca.itemComposto ? "Item composto" : "Produto único"} · Marca {planoBusca.marcaPreferencial || "-"}
                </div>
                {planoBusca.dimensoes?.length ? (
                  <div className="mt-1">
                    <AssistenteIADiagnosticoPills values={planoBusca.dimensoes} emptyLabel="Nenhuma dimensão no plano." />
                  </div>
                ) : null}
                {planoEspecificacoesPills.length ? (
                  <div className="mt-1">
                    <AssistenteIADiagnosticoPills values={planoEspecificacoesPills} emptyLabel="Nenhuma especificação no plano." />
                  </div>
                ) : null}
              </div>
            ) : (
              <div className="mt-1 text-zinc-500">Plano não disponível.</div>
            )}
          </div>

          <div>
            <div className="text-zinc-500">Termos extraídos</div>
            <div className="mt-1">
              <AssistenteIADiagnosticoPills values={diagnostico.termosExtraidos} emptyLabel="Nenhum termo extraído." />
            </div>
          </div>

          <div>
            <div className="text-zinc-500">Dimensões detectadas</div>
            <div className="mt-1">
              <AssistenteIADiagnosticoPills values={diagnostico.dimensoesDetectadas} emptyLabel="Nenhuma dimensão detectada." />
            </div>
          </div>

          <div>
            <div className="text-zinc-500">Grupos detectados</div>
            <div className="mt-1">
              <AssistenteIADiagnosticoPills
                values={diagnostico.gruposDetectados.map((grupo) => assistenteIAGrupoDiagnosticoLabel(grupo))}
                emptyLabel="Nenhum grupo detectado."
              />
            </div>
          </div>
        </div>

        <div className="space-y-2">
          <div>
            <div className="text-zinc-500">Campos normalizados</div>
            <div className="mt-1 text-zinc-300">
              Código {diagnostico.codigoNormalizado || "-"} · Marca priorizada {diagnostico.marcaPriorizada || "-"}
            </div>
          </div>

          <div>
            <div className="text-zinc-500">Grupos de busca</div>
            <div className="mt-1 space-y-1.5">
              {planoBusca?.gruposBusca.length ? (
                planoBusca.gruposBusca.map((grupo, index) => (
                  <div key={`plano-grupo-${item.linha}-${grupo.papel}-${index}`} className="rounded border border-zinc-800 bg-zinc-900/60 px-2 py-1.5">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-cyan-300">{assistenteIAPapelLabel(grupo.papel)}</span>
                      <span className="text-zinc-500">{grupo.marcaPreferencial || planoBusca.marcaPreferencial || "-"}</span>
                    </div>
                    <div className="mt-1 text-zinc-500">{grupo.observacao || "-"}</div>
                    <div className="mt-1 text-zinc-400">Obrigatórios</div>
                    <div className="mt-1">
                      <AssistenteIADiagnosticoPills values={grupo.termosObrigatorios} emptyLabel="Nenhum termo obrigatório." />
                    </div>
                    <div className="mt-1 text-zinc-400">Desejáveis</div>
                    <div className="mt-1">
                      <AssistenteIADiagnosticoPills values={grupo.termosDesejaveis} emptyLabel="Nenhum termo desejável." />
                    </div>
                    <div className="mt-1 text-orange-300">Proibidos</div>
                    <div className="mt-1">
                      <AssistenteIADiagnosticoPills values={grupo.termosProibidos} emptyLabel="Nenhum termo proibido." />
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-zinc-500">Nenhum grupo de busca disponível.</div>
              )}
            </div>
          </div>

          <div>
            <div className="text-zinc-500">Produtos selecionados pela IA</div>
            <div className="mt-1 space-y-1.5">
              {produtosSelecionados.length > 0 ? (
                produtosSelecionados.map((produto) => (
                  <div key={`diag-produto-${item.linha}-${produto.produtoId}`} className="rounded border border-zinc-800 bg-zinc-900/60 px-2 py-1.5">
                    <div className="text-cyan-300">{assistenteIAPapelLabel(produto.papelNaComposicao)}</div>
                    <div className="mt-0.5 text-zinc-100">
                      #{produto.produtoId} {produto.codigo ? `${produto.codigo} - ` : ""}
                      {produto.descricao}
                    </div>
                    <div className="mt-0.5 text-zinc-500">{produto.justificativa || "-"}</div>
                    {candidatoResumoById.get(produto.produtoId)?.motivos.length ? (
                      <div className="mt-1 text-zinc-400">
                        Motivos: {candidatoResumoById.get(produto.produtoId)?.motivos.join(", ")}
                      </div>
                    ) : null}
                  </div>
                ))
              ) : (
                <div className="text-zinc-500">Nenhum produto selecionado.</div>
              )}
            </div>
          </div>

          <div>
            <div className="text-zinc-500">Validação</div>
            <div className="mt-1 text-zinc-300">
              Banco antes do filtro: {diagnostico.candidatosBancoAntesFiltro ?? 0}
            </div>
            <div className="mt-1 text-zinc-300">
              Após categoria base: {diagnostico.candidatosAposCategoriaBase ?? 0}
            </div>
            <div className={diagnostico.candidatosRemovidosPorValidacao > 0 ? "mt-1 text-amber-300" : "mt-1 text-zinc-300"}>
              Removidos por validação: {diagnostico.candidatosRemovidosPorValidacao}
            </div>
            <div className={(diagnostico.candidatosRemovidosPorIncompatibilidade ?? 0) > 0 ? "mt-1 text-orange-300" : "mt-1 text-zinc-300"}>
              Removidos por incompatibilidade: {diagnostico.candidatosRemovidosPorIncompatibilidade ?? 0}
            </div>
            <div className={(diagnostico.candidatosRemovidosPorTermosProibidos ?? 0) > 0 ? "mt-1 text-orange-300" : "mt-1 text-zinc-300"}>
              Removidos por termos proibidos: {diagnostico.candidatosRemovidosPorTermosProibidos ?? 0}
            </div>
            <div className={(diagnostico.candidatosRemovidosPorScore ?? 0) > 0 ? "mt-1 text-orange-300" : "mt-1 text-zinc-300"}>
              Removidos por score: {diagnostico.candidatosRemovidosPorScore ?? 0}
            </div>
            <div className={diagnostico.fallbackAcionado ? "mt-1 text-amber-300" : "mt-1 text-zinc-300"}>
              Fallback por categoria: {diagnostico.fallbackAcionado ? "acionado" : "não acionado"}
            </div>
            <div className="mt-2 text-zinc-500">Termos proibidos aplicados</div>
            <div className="mt-1">
              <AssistenteIADiagnosticoPills values={termosProibidosAplicados} emptyLabel="Nenhum termo proibido aplicado." />
            </div>
          </div>
        </div>
      </div>

      <div className="mt-3">
        <div className="mb-1 flex items-center justify-between gap-2 text-zinc-500">
          <span>Candidatos enviados para a IA</span>
          <span className="tabular-nums">{diagnostico.candidatosEnviadosParaIA}</span>
        </div>
        {diagnostico.candidatosEnviadosParaIA === 0 ? (
          <div className="mb-2 rounded border border-orange-500/30 bg-orange-500/10 px-2 py-1.5 text-orange-200">
            Falha na geração de candidatos: nenhum item da categoria foi enviado para IA. Ver diagnóstico.
          </div>
        ) : null}
        <div className="overflow-auto rounded-md border border-zinc-800 max-h-56">
          <table className="w-full min-w-[760px] text-[11px]">
            <thead className="bg-zinc-900/80 sticky top-0 text-zinc-300">
              <tr>
                <th className="px-2 py-2 text-right whitespace-nowrap">Score</th>
                <th className="px-2 py-2 text-right whitespace-nowrap">Final</th>
                <th className="px-2 py-2 text-left whitespace-nowrap">Grupo</th>
                <th className="px-2 py-2 text-left whitespace-nowrap">Categoria</th>
                <th className="px-2 py-2 text-left min-w-[280px]">Produto</th>
                <th className="px-2 py-2 text-left min-w-[260px]">Motivos</th>
                <th className="px-2 py-2 text-left min-w-[220px]">Penalidades</th>
              </tr>
            </thead>
            <tbody>
              {diagnostico.candidatosResumo.length > 0 ? (
                diagnostico.candidatosResumo.map((candidato) => (
                  <tr key={`diag-candidato-${item.linha}-${candidato.produtoId}`} className="border-t border-zinc-900/80">
                    <td className="px-2 py-2 text-right tabular-nums whitespace-nowrap">{candidato.pontuacaoBackend}</td>
                    <td className="px-2 py-2 text-right tabular-nums whitespace-nowrap">{candidato.scoreFinal}</td>
                    <td className="px-2 py-2 whitespace-nowrap text-cyan-300">{assistenteIAGrupoResumoLabel(candidato.grupo)}</td>
                    <td className="px-2 py-2 whitespace-nowrap text-zinc-300">{assistenteIACategoriaTecnicaLabel(candidato.categoriaCandidatoDetectada)}</td>
                    <td className="px-2 py-2 min-w-[280px] whitespace-normal break-words">
                      <div className="text-zinc-100">
                        #{candidato.produtoId} {candidato.codigo ? `${candidato.codigo} - ` : ""}
                        {candidato.descricao}
                      </div>
                      {candidato.fornecedorNome && <div className="mt-0.5 text-zinc-500">{candidato.fornecedorNome}</div>}
                    </td>
                    <td className="px-2 py-2 min-w-[260px] whitespace-normal break-words text-zinc-400">
                      {candidato.motivos.length > 0 ? candidato.motivos.join(", ") : "-"}
                    </td>
                    <td className="px-2 py-2 min-w-[220px] whitespace-normal break-words text-orange-300">
                      {candidato.penalidades?.length ? candidato.penalidades.join(", ") : "-"}
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={7} className="px-2 py-3 text-center text-zinc-500">
                    Nenhum candidato foi enviado para a IA.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

export default function AssistenteIAModal({ open, idParam, supabase, tenantId, empresaId, onClose, onImported }: AssistenteIAModalProps) {
  const [fileName, setFileName] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [preview, setPreview] = useState<AssistenteIAItemPlanilha[]>([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [importLoading, setImportLoading] = useState(false);
  const [analiseResults, setAnaliseResults] = useState<AssistenteIAResultadoAnalise[]>([]);
  const [analiseLoading, setAnaliseLoading] = useState(false);
  const [decisoes, setDecisoes] = useState<Record<number, AssistenteIADecisao>>({});
  const [revisoesPorLinha, setRevisoesPorLinha] = useState<Record<number, AssistenteIARevisaoLinha>>({});
  const [diagnosticoLinha, setDiagnosticoLinha] = useState<number | null>(null);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const previewSummary = useMemo(() => {
    const total = preview.length;
    const validas = preview.filter(isAssistenteIAPreviewValid).length;
    const cadastrados = preview.filter((item) => isAssistenteIAPreviewValid(item) && Boolean(item.itemId)).length;
    const importaveis = preview.filter(isAssistenteIAImportavel).length;
    const importados = preview.filter((item) => item.importStatus === "importado").length;
    const pendentesImportacao = preview.filter(isAssistenteIAPendenteImportacao).length;
    const pendentesIA = preview.filter(isAssistenteIAElegivelAnalise).length;
    return { total, validas, erros: total - validas, cadastrados, importaveis, importados, pendentesImportacao, pendentesIA };
  }, [preview]);

  const revisaoSummary = useMemo(
    () => buildAssistenteIARevisaoSummary(revisoesPorLinha, analiseResults.length),
    [analiseResults.length, revisoesPorLinha]
  );

  const resetFlow = useCallback(() => {
    setFileName(null);
    setError(null);
    setInfo(null);
    setPreview([]);
    setAnalyzing(false);
    setImportLoading(false);
    setAnaliseResults([]);
    setAnaliseLoading(false);
    setDecisoes({});
    setRevisoesPorLinha({});
    setDiagnosticoLinha(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  }, []);

  const close = useCallback(() => {
    resetFlow();
    onClose();
  }, [onClose, resetFlow]);

  const handleFileChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setFileName(e.currentTarget.files?.[0]?.name ?? null);
    setError(null);
    setInfo(null);
    setPreview([]);
    setAnaliseResults([]);
    setImportLoading(false);
    setDecisoes({});
    setRevisoesPorLinha({});
    setDiagnosticoLinha(null);
  }, []);

  const clearPreview = useCallback(() => {
    resetFlow();
  }, [resetFlow]);

  const handleAnalisarPlanilha = useCallback(async () => {
    const file = fileInputRef.current?.files?.[0] ?? null;
    if (!file) {
      setError("Selecione uma planilha .xlsx ou .csv.");
      setInfo(null);
      setPreview([]);
      return;
    }

    setFileName(file.name);
    setAnalyzing(true);
    setImportLoading(false);
    setError(null);
    setInfo(null);
    setAnaliseResults([]);
    setDecisoes({});
    setRevisoesPorLinha({});
    setDiagnosticoLinha(null);

    try {
      const rows = await parseAssistenteIAFileRows(file);
      const nextPreview = buildAssistenteIAPreview(rows);
      const validas = nextPreview.filter((item) => !item.erro).length;

      setPreview(nextPreview);
      setInfo(
        nextPreview.length > 0
          ? `Prévia gerada para revisão: ${validas} linha(s) válida(s) e ${nextPreview.length - validas} com erro.`
          : "Nenhuma linha de item foi encontrada na planilha."
      );
    } catch (e: unknown) {
      const message = isAssistenteIAFileReadError(e)
        ? ASSISTENTE_IA_FILE_READ_ERROR_MESSAGE
        : e instanceof Error
          ? e.message
          : "Erro ao ler a planilha.";
      setPreview([]);
      setError(message);
    } finally {
      setAnalyzing(false);
    }
  }, []);

  const handleImportarCadastrados = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) {
      setError("Tenant/empresa não carregados.");
      return;
    }
    if (preview.length === 0 || previewSummary.erros > 0) {
      setError("Revise a planilha antes de importar itens cadastrados.");
      return;
    }

    const itensCadastrados = preview
      .filter(isAssistenteIAImportavel)
      .map((item) => ({
        linha: item.linha,
        produtoId: String(item.itemId),
        qtd: item.qtd,
      }));

    if (itensCadastrados.length === 0) {
      setInfo("Nenhum item cadastrado pendente para importar.");
      setError(null);
      return;
    }

    setImportLoading(true);
    setError(null);
    setInfo(null);
    setAnaliseResults([]);
    setDecisoes({});
    setRevisoesPorLinha({});
    setDiagnosticoLinha(null);

    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData.session?.access_token ?? null;
      if (!token) throw new Error("Sessão expirada. Faça login novamente.");

      const res = await fetch(`/api/comercial/orcamentos/${encodeURIComponent(idParam)}/assistente-ia/adicionar-itens`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          tenantId,
          empresaId,
          itens: itensCadastrados,
        }),
      });

      const json = await readAssistenteIAJson<AssistenteIAAdicionarItemResposta>(res, "Erro ao importar itens já cadastrados.");
      const adicionados = Array.isArray(json.adicionados) ? json.adicionados : [];
      const ignorados = Array.isArray(json.ignorados) ? json.ignorados : [];
      const erros = Array.isArray(json.erros) ? json.erros : [];
      const avisos = Array.isArray(json.avisos) ? json.avisos : [];
      const avisoByLinha = new Map(avisos.map((aviso) => [Number(aviso.linha), aviso.aviso]));
      const adicionadosByLinha = new Map(adicionados.map((item) => [Number(item.linha), item]));
      const ignoradosByLinha = new Map(ignorados.map((item) => [Number(item.linha), item]));
      const errosByLinha = new Map(erros.map((item) => [Number(item.linha), item]));

      setPreview((prev) =>
        prev.map((item) => {
          const adicionado = adicionadosByLinha.get(item.linha);
          if (adicionado) {
            const aviso = avisoByLinha.get(item.linha);
            return {
              ...item,
              importStatus: "importado",
              importMessage: aviso ? `Importado. ${aviso}` : "Importado",
            };
          }

          const ignorado = ignoradosByLinha.get(item.linha);
          if (ignorado) {
            const jaExistia = /existe/i.test(ignorado.motivo);
            return {
              ...item,
              importStatus: jaExistia ? "importado" : "ignorado",
              importMessage: jaExistia ? "Importado (já estava no orçamento)" : ignorado.motivo,
            };
          }

          const erroImportacao = errosByLinha.get(item.linha);
          if (erroImportacao) {
            return {
              ...item,
              importStatus: "erro",
              importMessage: erroImportacao.erro,
            };
          }

          return item;
        })
      );

      const totalJaExistia = ignorados.filter((item) => /existe/i.test(item.motivo)).length;
      const totalImportado = adicionados.length + totalJaExistia;
      const linhasNaoImportadas = itensCadastrados.length - totalImportado;
      setInfo(
        `${totalImportado} item(ns) importado(s). ${linhasNaoImportadas} não importado(s). ${erros.length} erro(s) de importação.`
      );

      if (adicionados.length > 0) await onImported?.();
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao importar itens já cadastrados.";
      setError(message);
    } finally {
      setImportLoading(false);
    }
  }, [empresaId, idParam, onImported, preview, previewSummary.erros, supabase, tenantId]);

  const handleAnalisarComIA = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) {
      setError("Tenant/empresa não carregados.");
      return;
    }
    if (preview.length === 0 || previewSummary.erros > 0) {
      setError("Revise a planilha antes de analisar com IA.");
      return;
    }
    if (previewSummary.pendentesImportacao > 0) {
      setError("Importe os itens já cadastrados antes de analisar com IA.");
      return;
    }

    const itensValidos = preview
      .filter(isAssistenteIAElegivelAnalise)
      .map((item) => ({
        linha: item.linha,
        itemId: item.itemId,
        qtd: item.qtd,
        componente: item.componente,
        codigo: item.codigo,
        marca: item.marca,
      }));

    if (itensValidos.length === 0) {
      setError("Nenhuma linha restante para analisar com IA.");
      return;
    }

    setAnaliseLoading(true);
    setError(null);
    setInfo(null);
    setAnaliseResults([]);
    setDecisoes({});
    setRevisoesPorLinha({});
    setDiagnosticoLinha(null);

    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData.session?.access_token ?? null;
      if (!token) throw new Error("Sessão expirada. Faça login novamente.");

      const res = await fetch(`/api/comercial/orcamentos/${encodeURIComponent(idParam)}/assistente-ia/analisar-itens`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          tenantId,
          empresaId,
          itens: itensValidos,
        }),
      });

      const json = await readAssistenteIAJson<{
        resultados?: AssistenteIAResultadoAnalise[];
        aviso?: string;
        error?: string;
      }>(res, "Erro ao analisar itens com IA.");

      const resultados = Array.isArray(json.resultados) ? json.resultados : [];
      setAnaliseResults(resultados);
      setDecisoes(buildAssistenteIADecisoesSugeridas(resultados));
      setRevisoesPorLinha(buildAssistenteIARevisoesIniciais(resultados));
      setInfo(json.aviso || "Análise IA gerada para revisão técnica. Nenhum item foi adicionado ao orçamento.");
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao analisar itens com IA.";
      setError(message);
    } finally {
      setAnaliseLoading(false);
    }
  }, [empresaId, idParam, preview, previewSummary.erros, previewSummary.pendentesImportacao, supabase, tenantId]);

  const updateRevisaoLinha = useCallback((linha: number, updater: (current: AssistenteIARevisaoLinha) => AssistenteIARevisaoLinha) => {
    setRevisoesPorLinha((prev) => {
      const current = prev[linha];
      if (!current) return prev;
      return { ...prev, [linha]: updater(current) };
    });
  }, []);

  const setDecisaoLinha = useCallback(
    (linha: number, decisao: AssistenteIADecisao) => {
      setDecisoes((prev) => ({ ...prev, [linha]: decisao }));
      updateRevisaoLinha(linha, (current) => ({ ...current, decisao, revisado: true }));
    },
    [updateRevisaoLinha]
  );

  const confirmarSugestaoLinha = useCallback(
    (linha: number) => {
      updateRevisaoLinha(linha, (current) => ({
        ...current,
        revisado: true,
        produtos: current.produtos.map((produto) =>
          produto.statusRevisao === "removido" ? produto : { ...produto, statusRevisao: "confirmado" }
        ),
      }));
    },
    [updateRevisaoLinha]
  );

  const marcarLinhaParaCotacao = useCallback(
    (linha: number) => {
      setDecisoes((prev) => ({ ...prev, [linha]: "cotar_cadastrar" }));
      updateRevisaoLinha(linha, (current) => ({ ...current, decisao: "cotar_cadastrar", revisado: true }));
    },
    [updateRevisaoLinha]
  );

  const ignorarLinha = useCallback(
    (linha: number) => {
      setDecisoes((prev) => ({ ...prev, [linha]: "ignorar" }));
      updateRevisaoLinha(linha, (current) => ({ ...current, decisao: "ignorar", revisado: true }));
    },
    [updateRevisaoLinha]
  );

  const updateProdutoRevisado = useCallback(
    (linha: number, produtoId: string, updater: (produto: AssistenteIAProdutoRevisado) => AssistenteIAProdutoRevisado) => {
      updateRevisaoLinha(linha, (current) => ({
        ...current,
        revisado: true,
        produtos: current.produtos.map((produto) => (produto.produtoId === produtoId ? updater(produto) : produto)),
      }));
    },
    [updateRevisaoLinha]
  );

  const confirmarProdutoRevisado = useCallback(
    (linha: number, produtoId: string) => {
      updateProdutoRevisado(linha, produtoId, (produto) => ({ ...produto, statusRevisao: "confirmado" }));
    },
    [updateProdutoRevisado]
  );

  const removerProdutoRevisado = useCallback(
    (linha: number, produtoId: string) => {
      updateProdutoRevisado(linha, produtoId, (produto) => ({ ...produto, statusRevisao: "removido" }));
    },
    [updateProdutoRevisado]
  );

  const alterarQuantidadeProdutoRevisado = useCallback(
    (linha: number, produtoId: string, value: string) => {
      const parsed = Number(value.replace(",", "."));
      if (!Number.isFinite(parsed) || parsed <= 0) return;
      updateProdutoRevisado(linha, produtoId, (produto) => ({ ...produto, qtdSugerida: parsed }));
    },
    [updateProdutoRevisado]
  );

  const alterarPapelProdutoRevisado = useCallback(
    (linha: number, produtoId: string, papel: AssistenteIAPapelProduto) => {
      updateProdutoRevisado(linha, produtoId, (produto) => ({ ...produto, papelNaComposicao: papel }));
    },
    [updateProdutoRevisado]
  );

  const alterarObservacaoLinha = useCallback(
    (linha: number, observacaoUsuario: string) => {
      updateRevisaoLinha(linha, (current) => ({ ...current, observacaoUsuario, revisado: true }));
    },
    [updateRevisaoLinha]
  );

  const toggleDiagnosticoLinha = useCallback((linha: number) => {
    setDiagnosticoLinha((prev) => (prev === linha ? null : linha));
  }, []);

  const marcarNaoEncontradosParaCotacao = useCallback(() => {
    setDecisoes((prev) => {
      const next = { ...prev };
      for (const item of analiseResults) {
        if (assistenteIATipoResultadoVisivel(item) === "nao_encontrado") next[item.linha] = "cotar_cadastrar";
      }
      return next;
    });
    setRevisoesPorLinha((prev) => {
      const next = { ...prev };
      for (const item of analiseResults) {
        if (assistenteIATipoResultadoVisivel(item) !== "nao_encontrado" || !next[item.linha]) continue;
        next[item.linha] = { ...next[item.linha], decisao: "cotar_cadastrar", revisado: true };
      }
      return next;
    });
  }, [analiseResults]);

  const ignorarTodos = useCallback(() => {
    setDecisoes(
      analiseResults.reduce<Record<number, AssistenteIADecisao>>((acc, item) => {
        acc[item.linha] = "ignorar";
        return acc;
      }, {})
    );
    setRevisoesPorLinha((prev) => {
      const next = { ...prev };
      for (const item of analiseResults) {
        if (!next[item.linha]) continue;
        next[item.linha] = { ...next[item.linha], decisao: "ignorar", revisado: true };
      }
      return next;
    });
  }, [analiseResults]);

  const restaurarDecisoesSugeridas = useCallback(() => {
    setDecisoes(buildAssistenteIADecisoesSugeridas(analiseResults));
    setRevisoesPorLinha(buildAssistenteIARevisoesIniciais(analiseResults));
  }, [analiseResults]);

  if (!open) return null;

  const busy = analyzing || importLoading || analiseLoading;

  return (
    <div
      className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4 md:items-center"
      onClick={(e) => {
        if (busy) return;
        if (e.target === e.currentTarget) close();
      }}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Assistente de IA"
        className="w-full max-w-none max-h-[90dvh] bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
          <div className="font-semibold text-zinc-100">Assistente de IA</div>
          <div className="text-xs text-zinc-400 mt-1">
            Envie uma planilha organizada com os itens do painel elétrico. O assistente irá analisar os itens, buscar
            correspondências no banco e preparar uma prévia para revisão.
          </div>
        </div>

        <div className="p-5 space-y-4 overflow-y-auto">
          <label className="block text-xs text-zinc-400">
            Planilha
            <input
              ref={fileInputRef}
              type="file"
              accept=".xlsx,.csv"
              onChange={handleFileChange}
              disabled={busy}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200"
            />
          </label>

          <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3 text-sm">
            <div className="font-medium text-zinc-200">Formato esperado da planilha</div>
            <div className="mt-2 text-xs text-zinc-400">Colunas obrigatórias:</div>
            <ul className="mt-2 list-disc pl-5 text-sm text-zinc-300 space-y-1">
              <li>Qtd</li>
              <li>Componente</li>
              <li>Código</li>
              <li>Marca</li>
            </ul>
            <div className="mt-3 text-xs text-zinc-400">Coluna opcional: ID do item cadastrado.</div>
          </div>

          {fileName && <div className="text-xs text-zinc-400">Arquivo selecionado: {fileName}</div>}
          {error && <div className="text-sm text-red-400">{error}</div>}
          {info && <div className="text-sm text-emerald-300">{info}</div>}

          {preview.length > 0 && (
            <div className="space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-3 xl:grid-cols-6 gap-2 text-sm">
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Total de linhas lidas</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-zinc-100">{previewSummary.total}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Linhas válidas</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-300">{previewSummary.validas}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Linhas com erro</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-amber-300">{previewSummary.erros}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Já cadastrados</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-cyan-300">{previewSummary.cadastrados}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Importados</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-300">{previewSummary.importados}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Restantes IA</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-amber-300">{previewSummary.pendentesIA}</div>
                </div>
              </div>

              <div className="rounded-lg border border-zinc-800 overflow-auto max-h-80">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/70 sticky top-0">
                    <tr className="text-zinc-200">
                      <th className="px-3 py-3 text-left whitespace-nowrap">Linha</th>
                      <th className="px-3 py-3 text-right whitespace-nowrap">ID</th>
                      <th className="px-3 py-3 text-right whitespace-nowrap">Qtd</th>
                      <th className="px-3 py-3 text-left min-w-[220px]">Componente</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap">Código</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap">Marca</th>
                      <th className="px-3 py-3 text-left min-w-[220px]">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {preview.map((item) => (
                      <tr key={`${item.linha}-${item.codigo}-${item.componente}`} className="border-t border-zinc-900/60">
                        <td className="px-3 py-2 tabular-nums whitespace-nowrap">{item.linha}</td>
                        <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{item.itemId ?? "-"}</td>
                        <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">
                          {Number.isFinite(item.qtd) ? formatDecimalBR(item.qtd, 3) : "-"}
                        </td>
                        <td className="px-3 py-2 min-w-[220px] whitespace-normal break-words">{item.componente || "-"}</td>
                        <td className="px-3 py-2 whitespace-nowrap">{item.codigo || "-"}</td>
                        <td className="px-3 py-2 whitespace-nowrap">{item.marca || "-"}</td>
                        <td className={assistenteIAPreviewStatusClass(item)}>{assistenteIAPreviewStatusLabel(item)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {analiseResults.length > 0 && (
            <div className="space-y-3">
              <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-100">
                A IA sugere correspondências, mas a revisão técnica é obrigatória antes de adicionar ao orçamento.
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-6 gap-2 text-sm">
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Linhas revisadas</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-300">{revisaoSummary.linhasRevisadas}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Linhas pendentes</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-amber-300">{revisaoSummary.linhasPendentes}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Produtos confirmados</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-300">{revisaoSummary.produtosConfirmados}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Produtos removidos</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-orange-300">{revisaoSummary.produtosRemovidos}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Linhas para cotação</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-orange-300">{revisaoSummary.linhasCotacaoCadastro}</div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">Linhas ignoradas</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-zinc-400">{revisaoSummary.linhasIgnoradas}</div>
                </div>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={marcarNaoEncontradosParaCotacao}
                  disabled={busy}
                  className="px-3 py-2 rounded-md border border-orange-500/30 bg-orange-500/10 hover:bg-orange-500/15 text-orange-200 text-sm disabled:opacity-60"
                >
                  Marcar não encontrados para cotação
                </button>
                <button
                  type="button"
                  onClick={ignorarTodos}
                  disabled={busy}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-300 text-sm disabled:opacity-60"
                >
                  Ignorar todos
                </button>
                <button
                  type="button"
                  onClick={restaurarDecisoesSugeridas}
                  disabled={busy}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 hover:bg-zinc-900 text-zinc-200 text-sm disabled:opacity-60"
                >
                  Restaurar decisões sugeridas
                </button>
                <button
                  type="button"
                  disabled
                  title="A inclusão será liberada após todas as linhas aceitas estarem revisadas."
                  className="max-w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-400 text-sm disabled:opacity-70 whitespace-normal text-left"
                >
                  Preparar inclusão no orçamento · A inclusão será liberada após todas as linhas aceitas estarem revisadas.
                </button>
              </div>

              <div className="rounded-lg border border-zinc-800 overflow-auto max-h-96">
                <table className="w-full text-xs">
                  <thead className="bg-zinc-900/70 sticky top-0">
                    <tr className="text-zinc-200">
                      <th className="px-3 py-3 text-left whitespace-nowrap">Linha</th>
                      <th className="px-3 py-3 text-left min-w-[260px]">Item original</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap">Tipo resultado</th>
                      <th className="px-3 py-3 text-left min-w-[320px]">Produtos selecionados</th>
                      <th className="px-3 py-3 text-right whitespace-nowrap">Confiança</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap">Diagnóstico</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap">Decisão sugerida</th>
                      <th className="px-3 py-3 text-left min-w-[280px]">Revisão manual</th>
                      <th className="px-3 py-3 text-left min-w-[260px]">Observação</th>
                      <th className="px-3 py-3 text-left min-w-[280px]">Resumo IA</th>
                      <th className="px-3 py-3 text-left min-w-[260px]">Alerta técnico</th>
                    </tr>
                  </thead>
                  <tbody>
                    {analiseResults.map((item) => {
                      const revisaoLinha = revisoesPorLinha[item.linha];
                      const produtosRevisados = revisaoLinha?.produtos ?? [];
                      const decisao = revisaoLinha?.decisao ?? decisoes[item.linha] ?? item.decisaoSugerida;
                      const diagnostico = item.diagnostico;
                      const diagnosticoAberto = Boolean(diagnostico) && diagnosticoLinha === item.linha;
                      const candidatosEnviados = diagnostico?.candidatosEnviadosParaIA ?? 0;
                      const removidosPorValidacao = diagnostico?.candidatosRemovidosPorValidacao ?? 0;
                      const removidosPorIncompatibilidade = diagnostico?.candidatosRemovidosPorIncompatibilidade ?? 0;
                      const tipoResultadoVisivel = assistenteIATipoResultadoVisivel(item);
                      return (
                        <Fragment key={`analise-${item.linha}-${item.codigoOriginal}-${item.componenteOriginal}`}>
                          <tr className="border-t border-zinc-900/60">
                            <td className="px-3 py-2 tabular-nums whitespace-nowrap">{item.linha}</td>
                            <td className="px-3 py-2 min-w-[260px] whitespace-normal break-words">
                              <div className="text-zinc-100">{item.componenteOriginal || "-"}</div>
                              <div className="mt-1 text-[11px] text-zinc-500">
                                Qtd {formatDecimalBR(item.qtdOriginal, 3)} · Código {item.codigoOriginal || "-"} · Marca {item.marcaOriginal || "-"}
                              </div>
                            </td>
                            <td className={`px-3 py-2 whitespace-nowrap ${assistenteIATipoResultadoClass(tipoResultadoVisivel)}`}>
                              {assistenteIATipoResultadoLabel(tipoResultadoVisivel)}
                            </td>
                            <td className="px-3 py-2 min-w-[320px] whitespace-normal break-words">
                              {produtosRevisados.length > 0 ? (
                                <div className="space-y-2">
                                  {produtosRevisados.map((produto) => (
                                    <div
                                      key={`${item.linha}-${produto.produtoId}`}
                                      className={`rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 ${
                                        produto.statusRevisao === "removido" ? "opacity-60" : ""
                                      }`}
                                    >
                                      <div className="flex flex-wrap items-center gap-1.5">
                                        <span className="text-[11px] font-medium text-cyan-300">{assistenteIAPapelLabel(produto.papelNaComposicao)}</span>
                                        <span className={`rounded border px-1.5 py-0.5 text-[10px] ${assistenteIAStatusRevisaoClass(produto.statusRevisao)}`}>
                                          {assistenteIAStatusRevisaoLabel(produto.statusRevisao)}
                                        </span>
                                        <span className="rounded border border-zinc-700 bg-zinc-900 px-1.5 py-0.5 text-[10px] text-zinc-300">
                                          {assistenteIAOrigemProdutoLabel(produto.origem)}
                                        </span>
                                      </div>
                                      <div className="mt-1 text-zinc-100">
                                        {produto.codigo ? `${produto.codigo} - ` : ""}
                                        {produto.descricao}
                                      </div>
                                      <div className="mt-1 text-[11px] text-zinc-500">
                                        ID {produto.produtoId}
                                        {produto.marca ? ` · ${produto.marca}` : ""}
                                        {produto.fornecedorNome ? ` · ${produto.fornecedorNome}` : ""}
                                      </div>
                                      <div className="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-2">
                                        <label className="text-[11px] text-zinc-500">
                                          Quantidade
                                          <input
                                            type="number"
                                            min="0.001"
                                            step="0.001"
                                            value={produto.qtdSugerida}
                                            disabled={busy || produto.statusRevisao === "removido"}
                                            onChange={(e) => alterarQuantidadeProdutoRevisado(item.linha, produto.produtoId, e.currentTarget.value)}
                                            className="mt-1 w-full rounded border border-zinc-800 bg-zinc-900 px-2 py-1 text-xs text-zinc-100 disabled:opacity-60"
                                          />
                                        </label>
                                        <label className="text-[11px] text-zinc-500">
                                          Papel
                                          <select
                                            value={produto.papelNaComposicao}
                                            disabled={busy || produto.statusRevisao === "removido"}
                                            onChange={(e) => alterarPapelProdutoRevisado(item.linha, produto.produtoId, e.currentTarget.value as AssistenteIAPapelProduto)}
                                            className="mt-1 w-full rounded border border-zinc-800 bg-zinc-900 px-2 py-1 text-xs text-zinc-100 disabled:opacity-60"
                                          >
                                            {ASSISTENTE_IA_PAPEIS_PRODUTO.map((papel) => (
                                              <option key={papel} value={papel}>
                                                {assistenteIAPapelLabel(papel)}
                                              </option>
                                            ))}
                                          </select>
                                        </label>
                                      </div>
                                      <div className="mt-2 flex flex-wrap gap-1.5">
                                        <button
                                          type="button"
                                          onClick={() => confirmarProdutoRevisado(item.linha, produto.produtoId)}
                                          disabled={busy || produto.statusRevisao === "removido"}
                                          className="rounded border border-emerald-500/30 bg-emerald-500/10 px-2 py-1 text-[11px] text-emerald-200 hover:bg-emerald-500/15 disabled:opacity-50"
                                        >
                                          Confirmar produto
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() => removerProdutoRevisado(item.linha, produto.produtoId)}
                                          disabled={busy}
                                          className="rounded border border-orange-500/30 bg-orange-500/10 px-2 py-1 text-[11px] text-orange-200 hover:bg-orange-500/15 disabled:opacity-50"
                                        >
                                          Remover
                                        </button>
                                        <button
                                          type="button"
                                          disabled
                                          title="A troca manual de produto será implementada no próximo passo."
                                          className="rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-[11px] text-zinc-500 disabled:opacity-70"
                                        >
                                          Trocar produto (próximo passo)
                                        </button>
                                      </div>
                                    </div>
                                  ))}
                                </div>
                              ) : (
                                <span className="text-zinc-500">Nenhum produto selecionado.</span>
                              )}
                            </td>
                            <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{item.confianca}%</td>
                            <td className="px-3 py-2 whitespace-nowrap">
                              <button
                                type="button"
                                onClick={() => toggleDiagnosticoLinha(item.linha)}
                                disabled={!diagnostico}
                                className="rounded-md border border-zinc-700 bg-zinc-950 px-2 py-1.5 text-xs text-zinc-200 hover:bg-zinc-900 disabled:opacity-50"
                              >
                                {diagnosticoAberto ? "Ocultar diagnóstico" : "Ver diagnóstico"}
                              </button>
                              <div className="mt-1 text-[11px] text-zinc-500 tabular-nums">Candidatos IA: {candidatosEnviados}</div>
                              {removidosPorValidacao > 0 && (
                                <div className="mt-0.5 text-[11px] text-amber-300 tabular-nums">Removidos: {removidosPorValidacao}</div>
                              )}
                              {removidosPorIncompatibilidade > 0 && (
                                <div className="mt-0.5 text-[11px] text-orange-300 tabular-nums">Incompatíveis: {removidosPorIncompatibilidade}</div>
                              )}
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap">
                              <select
                                value={decisao}
                                disabled={busy}
                                onChange={(e) => setDecisaoLinha(item.linha, e.target.value as AssistenteIADecisao)}
                                className={`w-40 rounded-md border border-zinc-800 bg-zinc-950 px-2 py-1.5 text-xs disabled:opacity-60 ${assistenteIADecisaoClass(
                                  decisao
                                )}`}
                              >
                                <option value="aceitar">{assistenteIADecisaoLabel("aceitar")}</option>
                                <option value="revisar">{assistenteIADecisaoLabel("revisar")}</option>
                                <option value="cotar_cadastrar">{assistenteIADecisaoLabel("cotar_cadastrar")}</option>
                                <option value="ignorar">{assistenteIADecisaoLabel("ignorar")}</option>
                              </select>
                            </td>
                            <td className="px-3 py-2 min-w-[280px] whitespace-normal">
                              <div className="space-y-2">
                                <div className={revisaoLinha?.revisado ? "text-emerald-300" : "text-amber-300"}>
                                  {revisaoLinha?.revisado ? "Linha revisada" : "Revisão pendente"}
                                </div>
                                <div className="flex flex-wrap gap-1.5">
                                  <button
                                    type="button"
                                    onClick={() => confirmarSugestaoLinha(item.linha)}
                                    disabled={busy || !revisaoLinha}
                                    className="rounded border border-emerald-500/30 bg-emerald-500/10 px-2 py-1 text-[11px] text-emerald-200 hover:bg-emerald-500/15 disabled:opacity-50"
                                  >
                                    Confirmar sugestão
                                  </button>
                                  <button
                                    type="button"
                                    onClick={() => marcarLinhaParaCotacao(item.linha)}
                                    disabled={busy || !revisaoLinha}
                                    className="rounded border border-orange-500/30 bg-orange-500/10 px-2 py-1 text-[11px] text-orange-200 hover:bg-orange-500/15 disabled:opacity-50"
                                  >
                                    Cotar/Cadastrar
                                  </button>
                                  <button
                                    type="button"
                                    onClick={() => ignorarLinha(item.linha)}
                                    disabled={busy || !revisaoLinha}
                                    className="rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-[11px] text-zinc-300 hover:bg-zinc-800 disabled:opacity-50"
                                  >
                                    Ignorar linha
                                  </button>
                                  <button
                                    type="button"
                                    disabled
                                    title="A troca manual de produto será implementada no próximo passo."
                                    className="rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-[11px] text-zinc-500 disabled:opacity-70"
                                  >
                                    Trocar produto (próximo passo)
                                  </button>
                                </div>
                              </div>
                            </td>
                            <td className="px-3 py-2 min-w-[260px]">
                              <textarea
                                value={revisaoLinha?.observacaoUsuario ?? ""}
                                disabled={busy || !revisaoLinha}
                                onChange={(e) => alterarObservacaoLinha(item.linha, e.currentTarget.value)}
                                rows={4}
                                placeholder="Observação da revisão"
                                className="w-full resize-y rounded-md border border-zinc-800 bg-zinc-950 px-2 py-1.5 text-xs text-zinc-200 placeholder:text-zinc-600 disabled:opacity-60"
                              />
                            </td>
                            <td className="px-3 py-2 min-w-[280px] whitespace-normal break-words text-zinc-300">
                              <div>{item.resumoIA || "-"}</div>
                              {item.termosBuscaUsados.length > 0 && (
                                <div className="mt-2 text-[11px] text-zinc-500">
                                  Termos: {item.termosBuscaUsados.slice(0, 8).join(", ")}
                                </div>
                              )}
                            </td>
                            <td className="px-3 py-2 min-w-[260px] whitespace-normal break-words">
                              {item.alertaTecnico ? (
                                <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-2 py-1.5 text-amber-100">
                                  {item.alertaTecnico}
                                </div>
                              ) : (
                                <span className="text-zinc-500">-</span>
                              )}
                            </td>
                          </tr>
                          {diagnosticoAberto && (
                            <tr className="border-t border-zinc-900/60">
                              <td colSpan={11} className="px-3 py-3 bg-zinc-950">
                                <AssistenteIADiagnosticoDetalhe item={item} />
                              </td>
                            </tr>
                          )}
                        </Fragment>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>

        <div className="px-5 py-4 border-t border-zinc-900/80 flex flex-col-reverse sm:flex-row sm:items-center sm:justify-end gap-2">
          {preview.length > 0 && (
            <button
              type="button"
              onClick={clearPreview}
              disabled={busy}
              className="w-full sm:w-auto px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-60"
            >
              Limpar prévia
            </button>
          )}
          {preview.length > 0 && (
            <button
              type="button"
              onClick={() => void handleImportarCadastrados()}
              disabled={previewSummary.importaveis === 0 || previewSummary.erros > 0 || busy}
              className="w-full sm:w-auto px-4 py-2 rounded-md border border-cyan-500/30 bg-cyan-500/10 hover:bg-cyan-500/15 text-cyan-200 font-medium disabled:opacity-60"
            >
              {importLoading ? "Importando..." : `Importar já cadastrados (${previewSummary.importaveis})`}
            </button>
          )}
          {preview.length > 0 && (
            <button
              type="button"
              onClick={() => void handleAnalisarComIA()}
              disabled={previewSummary.pendentesIA === 0 || previewSummary.pendentesImportacao > 0 || previewSummary.erros > 0 || busy}
              className="w-full sm:w-auto px-4 py-2 rounded-md border border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/15 text-emerald-200 font-medium disabled:opacity-60"
            >
              {analiseLoading ? "Analisando com IA..." : analiseResults.length > 0 ? "Reanalisar restantes com IA" : "Analisar restantes com IA"}
            </button>
          )}
          <button
            type="button"
            onClick={close}
            disabled={busy}
            className="w-full sm:w-auto px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
          >
            Cancelar
          </button>
          <button
            type="button"
            onClick={() => void handleAnalisarPlanilha()}
            disabled={busy}
            className="w-full sm:w-auto px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
          >
            {analyzing ? "Analisando..." : preview.length > 0 ? "Reanalisar planilha" : "Analisar planilha"}
          </button>
        </div>
      </div>
    </div>
  );
}
