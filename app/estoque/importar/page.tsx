"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatDecimalBR, parseDecimalBR } from "../../../lib/decimal";
import { supabaseBrowser } from "../../../lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";

type ParsedItem = {
  codigo: string;
  nome: string;
  quantidade: number;
  valorUnit: number;
  valorProd: number;
  total: number;
  vIcms: number;
  vIpi: number;
  vPis: number;
  vCofins: number;
  vSt: number;
  vFrete: number;
  vDesc: number;
  vOutro: number;
  vSeguro: number;
  overrideNome?: string;
  fornecedorId?: number | null;
  ncm?: string | null;
  aliquotaIcms?: number | null;
  aliquotaIpi?: number | null;
  aliquotaPis?: number | null;
  aliquotaCofins?: number | null;
};

type ParsedNfe = {
  chave: string | null;
  numero: string | null;
  serie: string | null;
  emitente: string | null;
  dataEmissao: string | null;
  cnpjEmitente: string | null;
  valorProdutos: number;
  valorFrete: number;
  valorSeguro: number;
  valorDesconto: number;
  valorOutros: number;
  valorTotal: number;
};

type FiscalPerfil = {
  item_id: number;
  ncm: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean;
  credita_pis: boolean;
  credita_cofins: boolean;
  ipi_entra_no_custo: boolean;
};

type ImportJob = {
  id: string;
  fileName: string;
  xmlText: string;
  nfeInfo: ParsedNfe | null;
  itens: ParsedItem[];
  fornecedorCnpj: string | null;
  status: "ok" | "erro" | "importando" | "importado";
  error?: string;
  selected: boolean;
};

type ItemFinalidade = "consumo" | "materia_prima" | "revenda" | "imobilizado" | "outros";

type FornecedorRow = {
  id: number;
  nome: string | null;
  documento_norm?: string | null;
  finalidade_padrao?: ItemFinalidade | null;
};

type ItemCodigoRow = {
  id: number;
  codigo_interno: string;
};

type DbError = {
  code?: string;
  message?: string;
};

type FiscalPayload = {
  tenant_id: string;
  empresa_id: string;
  item_id: number;
  ncm: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean;
  credita_pis: boolean;
  credita_cofins: boolean;
  ipi_entra_no_custo: boolean;
};

type ImportItemPayload = {
  tenant_id: string;
  item_id: number | null;
  codigo_fornecedor: string;
  descricao: string;
  ncm: string | null;
  qtd: number;
  v_unit: number;
  v_prod: number;
  v_icms: number;
  v_ipi: number;
  v_pis: number;
  v_cofins: number;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  quantidade: number;
  tipo: "entrada";
  motivo: string;
  realizado_por: string | null;
  data_movimentacao: string;
  custo_unitario_bruto: number | null;
  custo_unitario_real: number | null;
  v_frete_rateado: number;
  credito_icms: number;
  credito_pis: number;
  credito_cofins: number;
};

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

function normalizeDocumento(doc: string | null): string | null {
  if (!doc) return null;
  const onlyDigits = doc.replace(/\D/g, "");
  return onlyDigits || null;
}

export default function ImportarXmlPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);

  const [xmlText, setXmlText] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isReading, setIsReading] = useState(false);
  const readReqIdRef = useRef(0);

  const [fornecedorId, setFornecedorId] = useState<number | null>(null);
  const [fornecedorNome, setFornecedorNome] = useState<string | null>(null);

  const [importErr, setImportErr] = useState<string | null>(null);
  const [importOk, setImportOk] = useState<string | null>(null);
  const [importBusy, setImportBusy] = useState(false);
  const [cadBusy, setCadBusy] = useState(false);

  const [itemMap, setItemMap] = useState<Map<string, number>>(new Map());
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);

  const [fornecedorCnpjBase, setFornecedorCnpjBase] = useState<string | null>(null);
  const [fornecedorIdBase, setFornecedorIdBase] = useState<number | null>(null);

  const [finalidadeLote, setFinalidadeLote] = useState<ItemFinalidade | "">("");
  const [salvarPadraoFornecedor, setSalvarPadraoFornecedor] = useState(false);

  const [loteMissing, setLoteMissing] = useState<string[]>([]);

  const { tenantId, empresaId } = useTenantEmpresa();
  const { has, loading: permissionsLoading, refreshing, ready } = usePermissions();

  const canImport = has("fiscal.nf_entrada");
  const canCreateFornecedor = has("cadastros.fornecedores");
  const canCreateItem = has("itens.create");
  const canAccessPage = canImport || canCreateFornecedor || canCreateItem;

  function parseXml(raw: string): { nfe: ParsedNfe; itens: ParsedItem[] } {
    const parser = new DOMParser();
    const doc = parser.parseFromString(raw, "application/xml");

    // se houver erro de parse do XML, o navegador cria uma tag parsererror em alguns engines
    const parseErr = doc.querySelector("parsererror");
    if (parseErr) {
      throw new Error("XML inválido (erro de parse).");
    }

    const num = (n: string | null | undefined) => {
      const v = parseDecimalBR(n ?? "0");
      return Number.isFinite(v) ? v : 0;
    };
    const numOrNull = (n: string | null | undefined) => {
      const v = parseDecimalBR(n ?? "0");
      return Number.isFinite(v) ? v : null;
    };

    const inf = doc.querySelector("infNFe");
    const chaveRaw = inf?.getAttribute("Id") || null;
    const chave = chaveRaw ? chaveRaw.replace(/^NFe/i, "") : null;

    const numero = doc.querySelector("ide > nNF")?.textContent ?? null;
    const serie = doc.querySelector("ide > serie")?.textContent ?? null;
    const emitente = doc.querySelector("emit > xNome")?.textContent ?? null;
    const cnpjEmitente = doc.querySelector("emit > CNPJ")?.textContent ?? null;
    const dataEmissao = doc.querySelector("ide > dhEmi")?.textContent ?? null;

    const totalNode = doc.querySelector("total > ICMSTot");
    const valorFreteNF = num(totalNode?.querySelector("vFrete")?.textContent);
    const valorProdutosNF = num(totalNode?.querySelector("vProd")?.textContent);
    const valorSeguroNF = num(totalNode?.querySelector("vSeg")?.textContent);
    const valorDescontoNF = num(totalNode?.querySelector("vDesc")?.textContent);
    const valorOutrosNF = num(totalNode?.querySelector("vOutro")?.textContent);
    const valorTotalNF = num(totalNode?.querySelector("vNF")?.textContent);

    const itens: ParsedItem[] = [];
    doc.querySelectorAll("det").forEach((det) => {
      const prod = det.querySelector("prod");
      if (!prod) return;

      const codigo = (prod.querySelector("cProd")?.textContent ?? "").trim().replace(/^0+(?=\d)/, "");
      const nome = prod.querySelector("xProd")?.textContent ?? "";
      const quantidade = num(prod.querySelector("qCom")?.textContent);
      const valorUnit = num(prod.querySelector("vUnCom")?.textContent);
      const vProd = num(prod.querySelector("vProd")?.textContent);
      const vTotTrib = num(prod.querySelector("vTotTrib")?.textContent);

      const vIPI =
        num(det.querySelector("IPI > IPITrib > vIPI")?.textContent) ||
        num(det.querySelector("IPI > IPI > vIPI")?.textContent);

      const vICMS = num(det.querySelector("ICMS > * > vICMS")?.textContent);
      const vPIS = num(det.querySelector("PIS > * > vPIS")?.textContent);
      const vCOFINS = num(det.querySelector("COFINS > * > vCOFINS")?.textContent);
      const vST = num(det.querySelector("ICMS > * > vICMSST")?.textContent);

      const vOutro = num(prod.querySelector("vOutro")?.textContent);
      const vFrete = num(prod.querySelector("vFrete")?.textContent);
      const vDesc = num(prod.querySelector("vDesc")?.textContent);
      const vSeguro = num(prod.querySelector("vSeg")?.textContent);

      const totalBase = vProd + vFrete + vOutro + vIPI + vST + vTotTrib - vDesc;
      const total = totalBase > 0 ? totalBase : vProd || quantidade * valorUnit;

      const ncm = prod.querySelector("NCM")?.textContent ?? null;

      const icmsNode = det.querySelector("ICMS");
      let aliquotaIcms: number | null = null;
      icmsNode?.querySelectorAll("*").forEach((node) => {
        if (aliquotaIcms !== null) return;
        const p = numOrNull(node.querySelector("pICMS")?.textContent);
        if (p !== null) aliquotaIcms = p;
      });

      const aliquotaIpi =
        numOrNull(det.querySelector("IPI > IPITrib > pIPI")?.textContent) ??
        numOrNull(det.querySelector("IPI > IPI > pIPI")?.textContent);

      const aliquotaPis = numOrNull(det.querySelector("PIS > * > pPIS")?.textContent);
      const aliquotaCofins = numOrNull(det.querySelector("COFINS > * > pCOFINS")?.textContent);

      if (!codigo) return;

      itens.push({
        codigo,
        nome,
        quantidade,
        valorUnit,
        valorProd: vProd,
        total,
        vIcms: vICMS,
        vIpi: vIPI,
        vPis: vPIS,
        vCofins: vCOFINS,
        vSt: vST,
        vFrete,
        vDesc,
        vOutro,
        vSeguro,
        overrideNome: nome,
        ncm,
        aliquotaIcms,
        aliquotaIpi,
        aliquotaPis,
        aliquotaCofins,
      });
    });

    return {
      nfe: {
        chave,
        numero,
        serie,
        emitente,
        dataEmissao,
        cnpjEmitente,
        valorProdutos: valorProdutosNF,
        valorFrete: valorFreteNF,
        valorSeguro: valorSeguroNF,
        valorDesconto: valorDescontoNF,
        valorOutros: valorOutrosNF,
        valorTotal: valorTotalNF,
      },
      itens,
    };
  }

  async function checkFornecedor(cnpj: string | null) {
    setFornecedorId(null);
    setFornecedorNome(null);

    const cnpjNormalizado = normalizeDocumento(cnpj);
    if (!cnpjNormalizado) return;

    if (!tenantId) {
      setImportErr("Tenant nao carregado.");
      return;
    }

    const { data, error } = await applyTenant(
      supabase.from("fornecedores").select("id,nome,documento_norm,finalidade_padrao"),
      tenantId
    )
      .eq("documento_norm", cnpjNormalizado)
      .maybeSingle();

    if (error) {
      setImportErr(error.message);
      return;
    }

    const fornecedor = (data ?? null) as FornecedorRow | null;
    if (fornecedor?.id) {
      setFornecedorId(fornecedor.id);
      setFornecedorNome(fornecedor.nome ?? null);
      // Auto-preenche finalidade pelo padrão do fornecedor
      if (fornecedor.finalidade_padrao && !finalidadeLote) {
        setFinalidadeLote(fornecedor.finalidade_padrao);
      }
    }
  }

  async function criarFornecedor(cnpj: string, nome: string, finalidadePadrao?: ItemFinalidade | null) {
    setImportErr(null);

    if (!finalidadeLote) {
      setImportErr("Selecione a finalidade antes de cadastrar fornecedor.");
      return null;
    }

    if (!canCreateFornecedor) {
      setImportErr("Sem permissao para cadastrar fornecedor.");
      return null;
    }

    const documento = normalizeDocumento(cnpj);
    if (!documento) {
      setImportErr("Documento do fornecedor invalido.");
      return null;
    }

    if (!tenantId) {
      setImportErr("Tenant nao carregado.");
      return null;
    }

    // Regras: fornecedor já deve nascer com finalidade_padrao = finalidade do lote
    const finalidadeParaSalvar = (finalidadePadrao ?? (finalidadeLote as ItemFinalidade)) ?? null;

    const payload: Record<string, unknown> = {
      tenant_id: tenantId,
      nome: nome?.trim() || "Fornecedor NF",
      documento,
      ativo: true,
      finalidade_padrao: finalidadeParaSalvar,
    };

    const { data, error } = await supabase
      .from("fornecedores")
      .insert(payload)
      .select("id,nome,documento_norm,finalidade_padrao")
      .single();

    if (error) {
      const err = (error && typeof error === "object" ? (error as DbError) : null);

      // se já existe, tenta update (mantém robusto)
      if (err?.code === "23505") {
        const { data: updated, error: updateErr } = await applyTenant(
          supabase.from("fornecedores").update(payload).select("id,nome,documento_norm,finalidade_padrao"),
          tenantId
        )
          .eq("documento_norm", documento)
          .maybeSingle();

        if (updateErr) {
          setImportErr(updateErr.message);
          return null;
        }

        const updatedRow = (updated ?? null) as FornecedorRow | null;
        if (!updatedRow?.id) {
          setImportErr("Fornecedor ja cadastrado para este documento.");
          return null;
        }

        setFornecedorId(updatedRow.id);
        setFornecedorNome(updatedRow.nome ?? null);
        return updatedRow.id;
      }

      setImportErr(error.message);
      return null;
    }

    const created = (data ?? null) as FornecedorRow | null;
    if (!created?.id) return null;

    setFornecedorId(created.id);
    setFornecedorNome(created.nome ?? null);

    // garante que o padrão fica setado
    if (created.finalidade_padrao && !finalidadeLote) {
      setFinalidadeLote(created.finalidade_padrao);
    }

    return created.id;
  }

  async function atualizarFinalidadePadraoFornecedor(fornecedorIdToUpdate: number, finalidade: ItemFinalidade) {
    if (!tenantId) return;
    const { error } = await applyTenant(
      supabase.from("fornecedores").update({ finalidade_padrao: finalidade }),
      tenantId
    ).eq("id", fornecedorIdToUpdate);

    if (error) setImportErr(error.message);
  }

  const carregarItensPorCodigo = useCallback(
    async (codigos: string[], tenantIdLocal: string) => {
      if (codigos.length === 0) return new Map<string, number>();

      const { data, error } = await applyTenant(
        supabase.from("itens").select("id,codigo_interno"),
        tenantIdLocal
      ).in("codigo_interno", codigos);

      if (error) {
        setImportErr(error.message);
        return new Map();
      }

      const map = new Map<string, number>();
      const rows = (data ?? []) as ItemCodigoRow[];
      rows.forEach((r) => map.set(r.codigo_interno, r.id));
      return map;
    },
    [supabase]
  );

  async function carregarFiscalPorItens(itemIds: number[], tenantIdLocal: string, empresaIdLocal: string) {
    if (itemIds.length === 0) return new Map<number, FiscalPerfil>();

    const { data, error } = await applyTenantEmpresa(
      supabase
        .from("fiscal_itens")
        .select(
          "item_id,ncm,cst_icms,cst_pis,cst_cofins,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins,credita_icms,credita_pis,credita_cofins,ipi_entra_no_custo"
        ),
      tenantIdLocal,
      empresaIdLocal
    ).in("item_id", itemIds);

    if (error) {
      setImportErr(error.message);
      return new Map();
    }

    const map = new Map<number, FiscalPerfil>();
    const rows = (data ?? []) as FiscalPerfil[];
    rows.forEach((r) => map.set(r.item_id, r));
    return map;
  }

  async function upsertFiscalItem(itemId: number, fiscal: Partial<FiscalPerfil>, tenantIdLocal: string, empresaIdLocal: string) {
    const normCst = (v?: string | null) => {
      const t = (v ?? "").trim();
      return t.length > 0 ? t : null;
    };

    const cstIcms = normCst(fiscal.cst_icms ?? null);
    const cstPis = normCst(fiscal.cst_pis ?? null);
    const cstCofins = normCst(fiscal.cst_cofins ?? null);

    const creditaIcms =
      typeof fiscal.credita_icms === "boolean" ? fiscal.credita_icms : Boolean(cstIcms);
    const creditaPis =
      typeof fiscal.credita_pis === "boolean" ? fiscal.credita_pis : Boolean(cstPis);
    const creditaCofins =
      typeof fiscal.credita_cofins === "boolean" ? fiscal.credita_cofins : Boolean(cstCofins);

    const payload: FiscalPayload = {
      tenant_id: tenantIdLocal,
      empresa_id: empresaIdLocal,
      item_id: itemId,
      ncm: fiscal.ncm ?? null,
      cst_icms: cstIcms,
      cst_pis: cstPis,
      cst_cofins: cstCofins,
      aliq_icms: fiscal.aliq_icms ?? null,
      aliq_ipi: fiscal.aliq_ipi ?? null,
      aliq_pis: fiscal.aliq_pis ?? null,
      aliq_cofins: fiscal.aliq_cofins ?? null,
      credita_icms: creditaIcms,
      credita_pis: creditaPis,
      credita_cofins: creditaCofins,
      ipi_entra_no_custo: fiscal.ipi_entra_no_custo ?? true,
    };

    const { error } = await supabase.from("fiscal_itens").upsert(payload, { onConflict: "tenant_id,empresa_id,item_id" });

    // Com as policies do SQL, isso deve parar de acontecer
    if (error) {
      setImportErr(error.message);
    }
  }

  async function criarItemRapido(
    it: ParsedItem,
    fornecedorIdLocal: number | null | undefined,
    dataEmissao: string | null | undefined,
    finalidade: ItemFinalidade
  ) {
    setImportErr(null);

    if (!finalidadeLote) {
      setImportErr("Selecione a finalidade antes de cadastrar itens.");
      return null;
    }

    const nomeFinal = it.overrideNome?.trim() || it.nome || `Item ${it.codigo}`;
    const dataCompra = dataEmissao || new Date().toISOString();
    const margem = 52;

    const aliq = (v?: number | null) => (Number.isFinite(v as number) ? Number(v) : null);

    if (!tenantId || !empresaId) {
      setImportErr("Tenant ou empresa nao carregados.");
      return null;
    }

    const { data, error } = await supabase
      .from("itens")
      .insert({
        tenant_id: tenantId,
        codigo_interno: it.codigo,
        nome: nomeFinal,
        tipo: "produto",
        controla_estoque: true,
        unidade_medida: "UN",
        custo_ultima_compra: it.valorUnit,
        custo_medio: it.valorUnit,
        preco_unitario: it.valorUnit,
        fornecedor_id: fornecedorIdLocal ?? null,
        data_atualizacao_preco: dataCompra,
        data_ultima_compra: dataCompra,
        margem_lucro_percentual: margem,
        finalidade,
        ncm: it.ncm ?? null,
        aliquota_icms: aliq(it.aliquotaIcms),
        aliquota_ipi: aliq(it.aliquotaIpi),
        aliquota_pis: aliq(it.aliquotaPis),
        aliquota_cofins: aliq(it.aliquotaCofins),
      })
      .select("id")
      .single();

    if (error) {
      setImportErr(error.message);
      return null;
    }

    const createdId = data.id as number;

    // tenta gravar fiscal (se policy não existir, pode falhar — mas item já foi criado)
    await upsertFiscalItem(
      createdId,
      {
        ncm: it.ncm ?? null,
        aliq_icms: aliq(it.aliquotaIcms),
        aliq_ipi: aliq(it.aliquotaIpi),
        aliq_pis: aliq(it.aliquotaPis),
        aliq_cofins: aliq(it.aliquotaCofins),
      },
      tenantId,
      empresaId
    );

    return createdId;
  }

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    setImportErr(null);
    setImportOk(null);

    const files = Array.from(e.target.files ?? []);
    const file = files[0] ?? null;

    setSelectedFile(file);
    setSelectedFiles(files);
    setIsReading(false);

    if (files.length > 0) {
      setTimeout(() => {
        void parseXmlAndCheck(files);
      }, 0);
    }
  }

  function newJobId() {
    return `job-${Math.random().toString(36).slice(2)}`;
  }

  async function addJobFromRaw(xml: string, fileName: string) {
    const parsed = parseXml(xml);
    const cnpjRaw = parsed.nfe.cnpjEmitente ?? null;
    const cnpj = normalizeDocumento(cnpjRaw);

    let status: ImportJob["status"] = "ok";
    let error: string | undefined;
    let selected = true;

    if (!tenantId || !empresaId) {
      status = "erro";
      error = "Tenant ou empresa nao carregados.";
    }

    const chave = parsed.nfe.chave ?? null;

    if (chave && status === "ok" && tenantId && empresaId) {
      const { count: nfExiste } = await applyTenantEmpresa(
        supabase.from("nf_entrada").select("id", { count: "exact" }),
        tenantId,
        empresaId
      )
        .eq("chave", chave)
        .limit(1);

      if (typeof nfExiste === "number" && nfExiste > 0) {
        status = "importado";
        selected = false;
        error = "NF ja importada";
      }
    }

    // regra do lote: todos devem ser do mesmo fornecedor
    if (!fornecedorCnpjBase && cnpj && status === "ok") {
      setFornecedorCnpjBase(cnpj);
    } else if (fornecedorCnpjBase && cnpj && fornecedorCnpjBase !== cnpj) {
      status = "erro";
      error = "Fornecedor diferente do lote";
      selected = false;
    }

    const job: ImportJob = {
      id: newJobId(),
      fileName,
      xmlText: xml,
      nfeInfo: parsed.nfe,
      itens: parsed.itens,
      fornecedorCnpj: cnpj,
      status,
      error,
      selected,
    };

    const alreadyExists = !!(chave && jobs.some((j) => j.nfeInfo?.chave === chave));
    setJobs((prev) => {
      if (alreadyExists) return prev;
      return [...prev, job];
    });

    if (selected && !alreadyExists) setSelectedJobId(job.id);

    if (selected && cnpj && status === "ok") {
      await checkFornecedor(cnpj);
    }
  }

  async function addJobFromFile(file: File) {
    const text = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error("Falha ao ler o arquivo."));
      reader.onload = () => resolve(String(reader.result || ""));
      reader.readAsText(file);
    });

    await addJobFromRaw(text, file.name);
  }

  async function parseXmlAndCheck(filesOverride?: File[] | null) {
    if (isReading || importBusy) return;

    setImportErr(null);
    setImportOk(null);

    setIsReading(true);
    const reqId = ++readReqIdRef.current;

    try {
      const fileList = filesOverride ?? selectedFiles;

      if ((!fileList || fileList.length === 0) && !xmlText.trim()) {
        throw new Error("Selecione um XML para ler.");
      }

      // reset do contexto do lote
      setFornecedorId(null);
      setFornecedorNome(null);
      setFornecedorIdBase(null);
      setFornecedorCnpjBase(null);

      setItemMap(new Map());
      setJobs([]);
      setSelectedJobId(null);

      if (fileList && fileList.length > 0) {
        for (const file of fileList) {
          await addJobFromFile(file);
        }
      }

      if (xmlText.trim()) await addJobFromRaw(xmlText, "xml-painel");

      if (reqId === readReqIdRef.current) setImportOk("XML lido e validado.");
    } catch (e: unknown) {
      if (reqId === readReqIdRef.current) setImportErr(getErrorMessage(e, "Erro ao ler XML."));
    } finally {
      if (reqId === readReqIdRef.current) setIsReading(false);
    }
  }

  function selectJob(id: string) {
    setSelectedJobId(id);
  }

  function toggleJobSelected(id: string) {
    setJobs((prev) => prev.map((j) => (j.id === id ? { ...j, selected: !j.selected } : j)));
  }

  function removeJob(id: string) {
    setJobs((prev) => {
      const next = prev.filter((j) => j.id !== id);
      if (selectedJobId === id) {
        setSelectedJobId(next[0]?.id ?? null);
      }
      return next;
    });
  }

  function clearQueue() {
    setJobs([]);
    setSelectedJobId(null);
    setFornecedorCnpjBase(null);
    setFornecedorIdBase(null);
    setFornecedorId(null);
    setFornecedorNome(null);
    setItemMap(new Map());
    setImportErr(null);
    setImportOk(null);
  }

  async function cadastrarFornecedorEItens() {
    setImportErr(null);
    setImportOk(null);
    setCadBusy(true);

    try {
      if (!finalidadeLote) throw new Error("Selecione a finalidade antes de cadastrar/importar.");

      const jobsToUse = jobs.filter((j) => j.selected && j.status === "ok" && j.itens.length > 0);
      if (jobsToUse.length === 0) throw new Error("Nenhum XML selecionado.");

      if (!tenantId || !empresaId) throw new Error("Tenant ou empresa nao carregados.");

      // resolve fornecedor do lote via CNPJ base
      const baseCnpj =
        fornecedorCnpjBase ??
        normalizeDocumento(jobsToUse.find((j) => j.nfeInfo?.cnpjEmitente)?.nfeInfo?.cnpjEmitente ?? null);

      let fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;

      if (!fornecedorFinal && baseCnpj) {
        const { data: found, error: findErr } = await applyTenant(supabase.from("fornecedores").select("id"), tenantId)
          .eq("documento_norm", baseCnpj)
          .maybeSingle();

        if (findErr) throw findErr;
        fornecedorFinal = found?.id ?? null;
      }

      if (!fornecedorFinal) {
        const first = jobsToUse.find((j) => j.nfeInfo?.emitente && j.nfeInfo?.cnpjEmitente);

        if (first?.nfeInfo?.cnpjEmitente && first.nfeInfo.emitente) {
          if (!canCreateFornecedor) throw new Error("Sem permissao para cadastrar fornecedor.");
          fornecedorFinal = await criarFornecedor(
            first.nfeInfo.cnpjEmitente,
            first.nfeInfo.emitente,
            // regra: fornecedor já nasce com finalidade do lote
            (finalidadeLote as ItemFinalidade)
          );
        }
      }

      if (!fornecedorFinal) throw new Error("Fornecedor nao cadastrado.");

      // se marcou checkbox, garante atualização
      if (salvarPadraoFornecedor) {
        await atualizarFinalidadePadraoFornecedor(fornecedorFinal, finalidadeLote as ItemFinalidade);
      }

      // agora itens
      const todosItens = jobsToUse.flatMap((j) => j.itens);
      const codigos = Array.from(new Set(todosItens.map((i) => i.codigo)));

      const map = await carregarItensPorCodigo(codigos, tenantId);

      // regra: só cria item se tiver permissão
      const missing = codigos.filter((c) => !map.has(c));
      if (missing.length > 0 && !canCreateItem) {
        throw new Error(`Sem permissao para cadastrar itens. Faltantes: ${missing.join(", ")}`);
      }

      for (const job of jobsToUse) {
        const dataCompra = job.nfeInfo?.dataEmissao ?? new Date().toISOString();
        for (const it of job.itens) {
          if (!map.has(it.codigo)) {
            const created = await criarItemRapido(it, fornecedorFinal ?? null, dataCompra, finalidadeLote as ItemFinalidade);
            if (created) map.set(it.codigo, created);
          }
        }
      }

      setItemMap(map);
      setFornecedorIdBase(fornecedorFinal ?? null);
      setImportOk("Fornecedor e itens cadastrados para os XMLs selecionados.");
    } catch (e: unknown) {
      setImportErr(getErrorMessage(e, "Erro ao cadastrar."));
    } finally {
      setCadBusy(false);
    }
  }

  async function cadastrarItemManual(it: ParsedItem) {
    setImportErr(null);

    if (!canCreateItem) {
      setImportErr("Sem permissao para cadastrar itens.");
      return;
    }

    if (!finalidadeLote) {
      setImportErr("Selecione a finalidade antes de cadastrar itens.");
      return;
    }

    const dataCompra = selectedJob?.nfeInfo?.dataEmissao ?? null;

    const created = await criarItemRapido(
      it,
      fornecedorIdBase ?? fornecedorId ?? null,
      dataCompra,
      finalidadeLote as ItemFinalidade
    );

    if (created) {
      setItemMap((prev) => {
        const next = new Map(prev);
        next.set(it.codigo, created);
        return next;
      });
    }
  }

  async function importarNfe() {
    if (isReading || importBusy) return;

    setImportErr(null);
    setImportOk(null);
    setImportBusy(true);

    const round6 = (n: number) => (Number.isFinite(n) ? Number(n.toFixed(6)) : 0);

    try {
      if (!canImport) throw new Error("Sem permissao para importar NF.");
      if (!finalidadeLote) throw new Error("Selecione a finalidade antes de importar.");

      const jobsToImport = jobs.filter((j) => j.selected && j.status === "ok");
      if (jobsToImport.length === 0) throw new Error("Nenhum XML selecionado para importar.");

      if (!tenantId || !empresaId) throw new Error("Tenant ou empresa nao carregados.");

      // regra: não importa se tiver itens faltando
      if (loteMissing.length > 0) throw new Error(`Itens nao cadastrados: ${loteMissing.join(", ")}`);

      // resolve fornecedor final (tem que existir)
      let fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;

      if (!fornecedorFinal) {
        const baseCnpj =
          fornecedorCnpjBase ??
          normalizeDocumento(jobsToImport.find((j) => j.nfeInfo?.cnpjEmitente)?.nfeInfo?.cnpjEmitente ?? null);

        if (baseCnpj) {
          const { data: found, error: fornecedorErr } = await applyTenant(
            supabase.from("fornecedores").select("id"),
            tenantId
          )
            .eq("documento_norm", baseCnpj)
            .maybeSingle();

          if (fornecedorErr) throw fornecedorErr;
          fornecedorFinal = found?.id ?? null;
        }
      }

      if (!fornecedorFinal) throw new Error("Fornecedor nao cadastrado.");

      if (salvarPadraoFornecedor) {
        await atualizarFinalidadePadraoFornecedor(fornecedorFinal, finalidadeLote as ItemFinalidade);
      }

      const results: string[] = [];

      for (const job of jobsToImport) {
        try {
          const info = job.nfeInfo;

          if (!info || job.itens.length === 0) {
            results.push(`${job.fileName}: sem dados de NF ou itens.`);
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: "Sem dados" } : j)));
            continue;
          }

          if (!info.chave) {
            results.push(`${job.fileName}: chave nao encontrada.`);
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: "Chave ausente" } : j)));
            continue;
          }

          setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importando", error: undefined } : j)));

          // evita duplicidade
          const { count: nfJaExiste } = await applyTenantEmpresa(
            supabase.from("nf_entrada").select("id", { count: "exact" }),
            tenantId,
            empresaId
          )
            .eq("chave", info.chave)
            .limit(1);

          if (typeof nfJaExiste === "number" && nfJaExiste > 0) {
            results.push(`${job.fileName}: NF ja existente, pulada.`);
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: "NF ja existia" } : j)));
            continue;
          }

          // valida itens (tem que existir)
          const codes = Array.from(new Set(job.itens.map((i) => i.codigo)));
          const map = await carregarItensPorCodigo(codes, tenantId);

          const missingCodes = job.itens.filter((it) => !map.get(it.codigo)).map((it) => it.codigo);
          if (missingCodes.length > 0) {
            throw new Error(`Itens nao cadastrados: ${missingCodes.join(", ")}`);
          }

          const itemIds = Array.from(map.values());
          const fiscalMap = await carregarFiscalPorItens(itemIds, tenantId, empresaId);

          const { data: sess } = await supabase.auth.getSession();
          const userEmail = sess.session?.user?.email ?? null;

          const itemsToImport = job.itens;

          const totalProdutos = itemsToImport.reduce((sum, it) => sum + Number(it.valorProd ?? 0), 0);

          const totalFrete =
            Number(info.valorFrete ?? 0) > 0
              ? Number(info.valorFrete ?? 0)
              : itemsToImport.reduce((sum, it) => sum + Number(it.vFrete ?? 0), 0);

          const itensPayload: ImportItemPayload[] = [];

          for (const it of itemsToImport) {
            const itemId = map.get(it.codigo) ?? null;
            const fiscal = itemId ? fiscalMap.get(itemId) : null;

            const qtd = Number(it.quantidade ?? 0);
            const baseProd = Number(it.valorProd ?? 0);
            const baseLiquida = Math.max(0, baseProd - Number(it.vDesc ?? 0));

            const vIcms = Number(it.vIcms ?? 0);
            const vIpi = Number(it.vIpi ?? 0);
            const vPis = Number(it.vPis ?? 0);
            const vCofins = Number(it.vCofins ?? 0);
            const vSt = Number(it.vSt ?? 0);

            const creditoIcms = fiscal?.credita_icms ? vIcms : 0;
            const creditoPis = fiscal?.credita_pis ? vPis : 0;
            const creditoCofins = fiscal?.credita_cofins ? vCofins : 0;

            const freteRateado = totalProdutos > 0 ? (Number(it.valorProd ?? 0) / totalProdutos) * totalFrete : 0;

            const custoImpostos = (fiscal?.ipi_entra_no_custo ?? true) ? vIpi + vSt : 0;

            const custoTotal =
              baseLiquida + Number(it.vOutro ?? 0) + Number(it.vSeguro ?? 0) + freteRateado + custoImpostos;

            const custoUnitBruto = qtd > 0 ? custoTotal / qtd : null;
            const custoUnitReal =
              custoUnitBruto !== null ? custoUnitBruto - (creditoIcms + creditoPis + creditoCofins) / (qtd || 1) : null;

            itensPayload.push({
              tenant_id: tenantId,
              item_id: itemId,
              codigo_fornecedor: it.codigo,
              descricao: it.overrideNome ?? it.nome,
              ncm: it.ncm ?? null,
              qtd: round6(qtd),
              v_unit: round6(Number(it.valorUnit ?? 0)),
              v_prod: round6(baseProd),
              v_icms: round6(vIcms),
              v_ipi: round6(vIpi),
              v_pis: round6(vPis),
              v_cofins: round6(vCofins),
              aliq_icms: fiscal?.aliq_icms ?? it.aliquotaIcms ?? null,
              aliq_ipi: fiscal?.aliq_ipi ?? it.aliquotaIpi ?? null,
              aliq_pis: fiscal?.aliq_pis ?? it.aliquotaPis ?? null,
              aliq_cofins: fiscal?.aliq_cofins ?? it.aliquotaCofins ?? null,
              quantidade: round6(qtd),
              tipo: "entrada",
              motivo: `NF ${info.numero ?? ""}/${info.serie ?? ""} chave ${info.chave ?? ""} emitente ${info.emitente ?? ""}`,
              realizado_por: userEmail,
              data_movimentacao: info.dataEmissao ?? new Date().toISOString(),
              custo_unitario_bruto: custoUnitBruto !== null ? round6(custoUnitBruto) : null,
              custo_unitario_real: custoUnitReal !== null ? round6(custoUnitReal) : null,
              v_frete_rateado: round6(freteRateado),
              credito_icms: round6(creditoIcms),
              credito_pis: round6(creditoPis),
              credito_cofins: round6(creditoCofins),
            });
          }

          const nfJson = {
            chave: info.chave,
            numero: info.numero,
            serie: info.serie,
            emitente_nome: info.emitente,
            emitente_cnpj: info.cnpjEmitente,
            valor_produtos: info.valorProdutos ?? 0,
            valor_frete: info.valorFrete ?? 0,
            valor_seguro: info.valorSeguro ?? 0,
            valor_outros: info.valorOutros ?? 0,
            valor_desconto: info.valorDesconto ?? 0,
            valor_total: info.valorTotal ?? 0,
            data_emissao: info.dataEmissao ?? new Date().toISOString(),
          };

          const { data: importData, error: importErr } = await supabase.rpc("import_nf_entrada", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_fornecedor_id: fornecedorFinal,
            p_nf_json: nfJson,
            p_itens_json: itensPayload,
            p_xml_raw: job.xmlText,
            p_finalidade_contexto: finalidadeLote,
          });

          if (importErr) throw importErr;

          const result = Array.isArray(importData) ? importData[0] : importData;
          const status = result?.status ?? "ok";
          const message = result?.message ?? null;

          if (status === "ja_importada") {
            setJobs((prev) =>
              prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: message ?? "NF ja importada" } : j))
            );
            results.push(`${job.fileName}: NF ja importada.`);
          } else {
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: undefined } : j)));
            results.push(`${job.fileName}: importado com sucesso.`);
          }
        } catch (err: unknown) {
          const msg = getErrorMessage(err, "Erro");
          results.push(`${job.fileName}: erro - ${msg}`);
          setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: msg } : j)));
        }
      }

      setJobs((prev) => prev.filter((j) => j.status !== "importado"));
      setImportOk(results.join(" "));
    } catch (e: unknown) {
      setImportErr(getErrorMessage(e, "Erro ao importar."));
    } finally {
      setImportBusy(false);
    }
  }

  useEffect(() => {
    if (jobs.length === 0) {
      setSelectedJobId(null);
      return;
    }
    const exists = selectedJobId && jobs.some((j) => j.id === selectedJobId);
    if (!exists) {
      setSelectedJobId(jobs[0].id);
    }
  }, [jobs, selectedJobId]);

  const selectedJob = selectedJobId ? jobs.find((j) => j.id === selectedJobId) ?? jobs[0] ?? null : jobs[0] ?? null;
  const itensParaTabela = selectedJob?.itens ?? [];

  const selectedOkJobs = useMemo(() => jobs.filter((j) => j.selected && j.status === "ok"), [jobs]);
  const hasSelectedOkJobs = selectedOkJobs.length > 0;

  useEffect(() => {
    const loadMap = async () => {
      if (!selectedJob || selectedJob.itens.length === 0) {
        setItemMap(new Map());
        return;
      }
      if (!tenantId) {
        setImportErr("Tenant nao carregado.");
        return;
      }
      try {
        const codes = Array.from(new Set(selectedJob.itens.map((i) => i.codigo)));
        const map = await carregarItensPorCodigo(codes, tenantId);
        setItemMap(map);
      } catch (e: unknown) {
        setImportErr(getErrorMessage(e, "Erro ao carregar itens."));
      }
    };
    void loadMap();
  }, [selectedJob, tenantId, carregarItensPorCodigo]);

  useEffect(() => {
    let active = true;

    const loadLoteMap = async () => {
      const clearMissing = () => setLoteMissing((prev) => (prev.length === 0 ? prev : []));

      if (!tenantId) {
        clearMissing();
        return;
      }

      if (selectedOkJobs.length === 0) {
        clearMissing();
        return;
      }

      const codes = Array.from(new Set(selectedOkJobs.flatMap((j) => j.itens.map((it) => it.codigo))));
      if (codes.length === 0) {
        clearMissing();
        return;
      }

      try {
        const map = await carregarItensPorCodigo(codes, tenantId);
        if (!active) return;

        const nextMissing = codes.filter((c) => !map.has(c));

        setLoteMissing((prev) => {
          if (prev.length !== nextMissing.length) return nextMissing;
          for (let i = 0; i < prev.length; i += 1) {
            if (prev[i] !== nextMissing[i]) return nextMissing;
          }
          return prev;
        });
      } catch (e: unknown) {
        if (!active) return;
        setImportErr(getErrorMessage(e, "Erro ao carregar itens."));
      }
    };

    void loadLoteMap();
    return () => {
      active = false;
    };
  }, [selectedOkJobs, tenantId, carregarItensPorCodigo]);

  const fornecedorResolvido = Boolean(fornecedorIdBase ?? fornecedorId);
  const finalidadeSelecionada = Boolean(finalidadeLote);
  const itensFaltantes = loteMissing.length > 0;

  const requisitosChecklist = {
    xml: hasSelectedOkJobs,
    finalidade: finalidadeSelecionada,
    fornecedor: fornecedorResolvido,
    itens: !itensFaltantes || canCreateItem,
  };

  // regra: importar só se tudo estiver ok e itens sem faltantes
  const bloqueiaImportacao =
    !hasSelectedOkJobs || !finalidadeSelecionada || !fornecedorResolvido || itensFaltantes || !tenantId || !empresaId;

  const precisaCriarFornecedor = !fornecedorResolvido;
  const podeCriarFornecedor = !precisaCriarFornecedor || canCreateFornecedor;
  const podeCriarItens = !itensFaltantes || canCreateItem;

  const bloqueiaCadastro =
    !hasSelectedOkJobs || !finalidadeSelecionada || !tenantId || !empresaId || !podeCriarFornecedor || !podeCriarItens;

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  }

  if (!canAccessPage) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Sem permissao para acessar esta pagina.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Importar XML</h1>
          <p className="text-sm text-zinc-400 mt-1">Importe NF-e (XML) para criar fornecedor, itens e movimentações.</p>
        </div>
        <Link href="/estoque" className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
          Voltar para estoque
        </Link>
      </div>

      <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-4 space-y-4">
        {!canImport && (
          <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
            Voce nao tem permissao para importar NF-e. Voce ainda pode ler XML e cadastrar fornecedor/itens.
          </div>
        )}

        <div className="grid gap-4 md:grid-cols-2">
          <div className="border border-zinc-800 rounded-lg p-3 space-y-3">
            <div>
              <div className="text-lg font-semibold">Finalidade do lote</div>
              <div className="text-sm text-zinc-400">Obrigatorio para cadastrar itens e importar NF.</div>
            </div>

            <div className="grid gap-4">
              <label className="flex flex-col gap-1">
                <span className="text-sm text-zinc-200">Finalidade</span>
                <select
                  value={finalidadeLote}
                  onChange={(e) => setFinalidadeLote(e.target.value as ItemFinalidade | "")}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                >
                  <option value="">Selecione...</option>
                  <option value="consumo">Consumo</option>
                  <option value="materia_prima">Materia-prima</option>
                  <option value="revenda">Revenda</option>
                  <option value="imobilizado">Imobilizado</option>
                  <option value="outros">Outros</option>
                </select>
              </label>

              {(fornecedorResolvido || (fornecedorCnpjBase && canCreateFornecedor)) && (
                <label className="flex items-center gap-2 text-sm text-zinc-200">
                  <input type="checkbox" checked={salvarPadraoFornecedor} onChange={(e) => setSalvarPadraoFornecedor(e.target.checked)} />
                  Tornar esta finalidade padrao do fornecedor
                </label>
              )}
            </div>
          </div>

          <div className="border border-zinc-800 rounded-lg p-3">
            <div className="text-sm font-semibold text-zinc-100">Requisitos</div>
            <div className="mt-2 space-y-1 text-sm">
              <div className={requisitosChecklist.xml ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.xml ? "OK" : "Pendente"} - XML lido e validado
              </div>
              <div className={requisitosChecklist.finalidade ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.finalidade ? "OK" : "Pendente"} - Finalidade selecionada
              </div>
              <div className={requisitosChecklist.fornecedor ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.fornecedor ? "OK" : "Pendente"} - Fornecedor encontrado/cadastrado
              </div>
              <div className={requisitosChecklist.itens ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.itens ? "OK" : "Pendente"} - Itens cadastrados
                {itensFaltantes ? ` (${loteMissing.length} faltante${loteMissing.length > 1 ? "s" : ""})` : ""}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl bg-zinc-950">
        <div className="flex items-center justify-between gap-2 px-5 py-4 border-b border-zinc-800">
          <div>
            <div className="text-lg font-semibold">Importar NF-e (XML)</div>
            <div className="text-sm text-zinc-400">Fornecedor por CNPJ, itens por codigo do produto.</div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => {
                setXmlText("");
                setSelectedFile(null);
                clearQueue();
              }}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Limpar
            </button>

            <button
              onClick={importarNfe}
              disabled={isReading || importBusy || bloqueiaImportacao || !canImport}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              {importBusy ? "Importando..." : "Importar"}
            </button>
          </div>
        </div>

        <div className="px-5 py-4 space-y-3">
          <div className="space-y-2">
            <div className="flex gap-2 items-center">
              <input
                ref={fileInputRef}
                type="file"
                accept=".xml"
                multiple
                aria-label="Selecionar arquivos XML"
                title="Selecionar arquivos XML"
                onChange={handleFile}
                className="text-sm text-zinc-200"
                disabled={isReading || importBusy}
              />

              <button
                onClick={() => void parseXmlAndCheck()}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                disabled={isReading || ((selectedFiles.length === 0 && !selectedFile) && !xmlText) || importBusy}
              >
                {isReading ? "Lendo..." : "Ler XML"}
              </button>
            </div>
          </div>

          <div className="border border-zinc-800 rounded-lg p-3 space-y-2">
            <div className="flex items-center justify-between">
              <div className="font-semibold text-zinc-100">Fila de XMLs</div>
              <div className="flex items-center gap-2">
                <span className="text-xs text-zinc-400">{jobs.length} arquivos na fila</span>
                <button
                  onClick={clearQueue}
                  disabled={jobs.length === 0}
                  className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                >
                  Limpar fila
                </button>
              </div>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-zinc-900/60 text-zinc-200 sticky top-0">
                  <tr>
                    <th className="px-2 py-1 text-center">Ver</th>
                    <th className="px-2 py-1 text-center">Importar</th>
                    <th className="px-2 py-1 text-left">Chave</th>
                    <th className="px-2 py-1 text-left">Numero/Serie</th>
                    <th className="px-2 py-1 text-left">Emissao</th>
                    <th className="px-2 py-1 text-left">Emitente</th>
                    <th className="px-2 py-1 text-left">Status</th>
                    <th className="px-2 py-1 text-center">Acoes</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {jobs.map((j) => (
                    <tr key={j.id} className="hover:bg-zinc-900/40">
                      <td className="px-2 py-1 text-center">
                        <input
                          type="radio"
                          name="job-view"
                          aria-label={`Selecionar XML ${j.nfeInfo?.chave ?? j.id}`}
                          title={`Selecionar XML ${j.nfeInfo?.chave ?? j.id}`}
                          checked={selectedJobId === j.id}
                          onChange={() => selectJob(j.id)}
                        />
                      </td>
                      <td className="px-2 py-1 text-center">
                        <input
                          type="checkbox"
                          aria-label={`Marcar XML ${j.nfeInfo?.chave ?? j.id} para importar`}
                          title={`Marcar XML ${j.nfeInfo?.chave ?? j.id} para importar`}
                          checked={j.selected}
                          onChange={() => toggleJobSelected(j.id)}
                        />
                      </td>
                      <td className="px-2 py-1">{j.nfeInfo?.chave ?? "?"}</td>
                      <td className="px-2 py-1">
                        {j.nfeInfo?.numero ?? "?"}/{j.nfeInfo?.serie ?? "?"}
                      </td>
                      <td className="px-2 py-1">{j.nfeInfo?.dataEmissao ?? "?"}</td>
                      <td className="px-2 py-1">
                        {j.nfeInfo?.emitente ?? "?"}
                        {j.nfeInfo?.cnpjEmitente ? ` (${j.nfeInfo.cnpjEmitente})` : ""}
                      </td>
                      <td className="px-2 py-1">
                        {j.status === "ok" && <span className="text-emerald-300">OK</span>}
                        {j.status === "erro" && <span className="text-red-400">Erro {j.error ? `- ${j.error}` : ""}</span>}
                        {j.status === "importando" && <span className="text-amber-300">Importando...</span>}
                        {j.status === "importado" && (
                          <span className="text-emerald-300">{j.error ? `Importada (${j.error})` : "Importada"}</span>
                        )}
                      </td>
                      <td className="px-2 py-1 text-center">
                        <button
                          onClick={() => removeJob(j.id)}
                          className="px-2 py-1 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                        >
                          Remover
                        </button>
                      </td>
                    </tr>
                  ))}
                  {jobs.length === 0 && (
                    <tr>
                      <td colSpan={8} className="px-2 py-3 text-center text-zinc-400">
                        Nenhum XML na fila.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>

          {selectedJob?.nfeInfo && (
            <div className="border border-zinc-800 rounded-lg p-3 text-sm text-zinc-300 space-y-1">
              <div className="font-semibold text-zinc-100">NF-e</div>
              <div>Chave: {selectedJob.nfeInfo.chave ?? "?"}</div>
              <div>
                Numero/Serie: {selectedJob.nfeInfo.numero ?? "?"}/{selectedJob.nfeInfo.serie ?? "?"}
              </div>
              <div>
                Emitente: {selectedJob.nfeInfo.emitente ?? "?"}{" "}
                {selectedJob.nfeInfo.cnpjEmitente ? `(CNPJ ${selectedJob.nfeInfo.cnpjEmitente})` : ""}
              </div>
              <div>Data emissao: {selectedJob.nfeInfo.dataEmissao ?? "?"}</div>
            </div>
          )}

          {!fornecedorResolvido && (
            <div className="border border-zinc-800 rounded-lg p-3 text-sm text-zinc-300 space-y-2">
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-semibold text-zinc-100">Fornecedor</div>
                  <div className="text-xs text-zinc-400">Valida por CNPJ</div>
                </div>

                {selectedJob?.nfeInfo?.cnpjEmitente && (
                  <Can perm="cadastros.fornecedores">
                    <button
                      onClick={() => {
                        if (!finalidadeLote) {
                          setImportErr("Selecione a finalidade antes de cadastrar fornecedor.");
                          return;
                        }
                        void criarFornecedor(
                          selectedJob.nfeInfo!.cnpjEmitente!,
                          selectedJob.nfeInfo!.emitente ?? "Fornecedor NF",
                          (finalidadeLote as ItemFinalidade)
                        );
                      }}
                      disabled={importBusy}
                      className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                    >
                      Cadastrar fornecedor
                    </button>
                  </Can>
                )}
              </div>

              {selectedJob?.nfeInfo?.cnpjEmitente && (
                <div className="text-sm">
                  CNPJ: {selectedJob.nfeInfo.cnpjEmitente}{" "}
                  {fornecedorNome ? `Encontrado: ${fornecedorNome}` : "Nao cadastrado"}
                </div>
              )}
            </div>
          )}

          <div className="border border-zinc-800 rounded-lg p-3 flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <div className="font-semibold text-zinc-100">Itens da NF</div>
              <div className="text-xs text-zinc-400">Confirme codigos e cadastre os faltantes.</div>
            </div>

            <div className="overflow-x-auto">
              <div className="max-h-[55vh] overflow-auto rounded-lg border border-zinc-800">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/60 text-zinc-200 sticky top-0">
                    <tr>
                      <th className="px-3 py-2 text-left">Codigo</th>
                      <th className="px-3 py-2 text-left">Descricao NF</th>
                      <th className="px-3 py-2 text-right">Qtd</th>
                      <th className="px-3 py-2 text-right">V.Unit</th>
                      <th className="px-3 py-2 text-right">Total</th>
                      <th className="px-3 py-2 text-center">Status</th>
                      <th className="px-3 py-2 text-center">Acoes</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-800">
                    {itensParaTabela.map((it, idx) => {
                      const foundId = itemMap.get(it.codigo);
                      return (
                        <tr key={`${it.codigo}-${idx}`} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2 font-medium">{it.codigo}</td>
                          <td className="px-3 py-2 align-top">
                            <textarea
                              className="w-full px-2 py-2 bg-zinc-900 border border-zinc-700 rounded min-h-[64px] text-sm leading-snug"
                              aria-label={`Descricao NF do item ${it.codigo}`}
                              title={`Descricao NF do item ${it.codigo}`}
                              value={it.overrideNome ?? it.nome}
                              onChange={(e) => {
                                const value = e.target.value;
                                setJobs((prev) =>
                                  prev.map((j) =>
                                    j.id === selectedJobId
                                      ? {
                                          ...j,
                                          itens: j.itens.map((p) => (p.codigo === it.codigo ? { ...p, overrideNome: value } : p)),
                                        }
                                      : j
                                  )
                                );
                              }}
                            />
                          </td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(it.quantidade, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">R$ {it.valorUnit.toFixed(2)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">R$ {it.total.toFixed(2)}</td>
                          <td className="px-3 py-2 text-center">
                            {foundId ? (
                              <span className="inline-flex items-center px-2 py-1 rounded-md border border-emerald-500/40 text-emerald-300 text-xs">
                                Cadastrado (id {foundId})
                              </span>
                            ) : (
                              <span className="inline-flex items-center px-2 py-1 rounded-md border border-amber-500/40 text-amber-300 text-xs">
                                Nao encontrado
                              </span>
                            )}
                          </td>
                          <td className="px-3 py-2 text-center">
                            {!foundId && (
                              <Can perm="itens.create">
                                <button
                                  onClick={() => void cadastrarItemManual(it)}
                                  className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                                >
                                  Cadastrar item
                                </button>
                              </Can>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                    {itensParaTabela.length === 0 && (
                      <tr>
                        <td colSpan={8} className="px-3 py-4 text-zinc-400 text-center">
                          Nenhum item lido ainda.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            {importErr && <div className="text-sm text-red-400">{importErr}</div>}
            {importOk && <div className="text-sm text-emerald-300">{importOk}</div>}
          </div>
        </div>

        <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
          <button
            onClick={() => void cadastrarFornecedorEItens()}
            disabled={cadBusy || importBusy || isReading || bloqueiaCadastro}
            className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-100"
          >
            {cadBusy ? "Cadastrando..." : "Cadastrar fornecedor e itens"}
          </button>

          <button
            onClick={importarNfe}
            disabled={isReading || importBusy || bloqueiaImportacao || !canImport}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            {importBusy ? "Importando..." : "Importar"}
          </button>
        </div>
      </div>
    </div>
  );
}

