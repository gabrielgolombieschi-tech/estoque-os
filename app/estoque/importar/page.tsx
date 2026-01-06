"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { formatDecimalBR, parseDecimalBR } from "../../../lib/decimal";
import { supabaseBrowser } from "../../../lib/supabase/client";

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

export default function ImportarXmlPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);

  const [xmlText, setXmlText] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [isReading, setIsReading] = useState(false);
  const readReqIdRef = useRef(0);
  const [nfeInfo, setNfeInfo] = useState<ParsedNfe | null>(null);
  const [parsedItens, setParsedItens] = useState<ParsedItem[]>([]);
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

  function parseXml(raw: string): { nfe: ParsedNfe; itens: ParsedItem[] } {
    const parser = new DOMParser();
    const doc = parser.parseFromString(raw, "application/xml");
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
      const codigo = prod.querySelector("cProd")?.textContent ?? "";
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
    if (!cnpj) return;
    const { data, error } = await supabase
      .from("fornecedores")
      .select("id,nome,documento")
      .eq("documento", cnpj)
      .maybeSingle();
    if (!error && data?.id) {
      setFornecedorId(data.id as number);
      setFornecedorNome((data as any).nome ?? null);
    }
  }

  async function criarFornecedor(cnpj: string, nome: string) {
    setImportErr(null);
    const { data, error } = await supabase
      .from("fornecedores")
      .insert({ nome, documento: cnpj, ativo: true })
      .select("id,nome")
      .single();
    if (error) {
      setImportErr(error.message);
      return null;
    }
    setFornecedorId(data.id as number);
    setFornecedorNome((data as any).nome ?? null);
    return data.id as number;
  }

  async function carregarItensPorCodigo(codigos: string[]) {
    if (codigos.length === 0) return new Map<string, number>();
    const { data, error } = await supabase.from("itens").select("id,codigo_interno").in("codigo_interno", codigos);
    if (error) {
      setImportErr(error.message);
      return new Map();
    }
    const map = new Map<string, number>();
    (data ?? []).forEach((r: any) => map.set(r.codigo_interno, r.id));
    return map;
  }

  async function carregarFiscalPorItens(itemIds: number[]) {
    if (itemIds.length === 0) return new Map<number, FiscalPerfil>();

    const { data, error } = await supabase
      .from("fiscal_itens")
      .select(
        "item_id,ncm,cst_icms,cst_pis,cst_cofins,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins,credita_icms,credita_pis,credita_cofins,ipi_entra_no_custo"
      )
      .in("item_id", itemIds);

    if (error) {
      setImportErr(error.message);
      return new Map();
    }

    const map = new Map<number, FiscalPerfil>();
    (data ?? []).forEach((r: any) => map.set(r.item_id, r as FiscalPerfil));
    return map;
  }

  async function upsertFiscalItem(itemId: number, fiscal: Partial<FiscalPerfil>) {
    const payload: any = {
      item_id: itemId,
      ncm: fiscal.ncm ?? null,
      cst_icms: fiscal.cst_icms ?? null,
      cst_pis: fiscal.cst_pis ?? null,
      cst_cofins: fiscal.cst_cofins ?? null,
      aliq_icms: fiscal.aliq_icms ?? null,
      aliq_ipi: fiscal.aliq_ipi ?? null,
      aliq_pis: fiscal.aliq_pis ?? null,
      aliq_cofins: fiscal.aliq_cofins ?? null,
      credita_icms: fiscal.credita_icms ?? true,
      credita_pis: fiscal.credita_pis ?? true,
      credita_cofins: fiscal.credita_cofins ?? true,
      ipi_entra_no_custo: fiscal.ipi_entra_no_custo ?? true,
    };

    const { error } = await supabase.from("fiscal_itens").upsert(payload, { onConflict: "item_id" });
    if (error) setImportErr(error.message);
  }

  async function criarItemRapido(it: ParsedItem, fornecedorId?: number | null, dataEmissao?: string | null) {
    setImportErr(null);
    const nomeFinal = it.overrideNome?.trim() || it.nome || `Item ${it.codigo}`;
    const dataCompra = dataEmissao || new Date().toISOString();
    const margem = 52;
    const aliq = (v?: number | null) => (Number.isFinite(v as number) ? Number(v) : null);
    const { data, error } = await supabase
      .from("itens")
      .insert({
        codigo_interno: it.codigo,
        nome: nomeFinal,
        tipo: "produto",
        controla_estoque: true,
        unidade_medida: "UN",
        custo_ultima_compra: it.valorUnit,
        custo_medio: it.valorUnit,
        preco_unitario: it.valorUnit,
        fornecedor_id: fornecedorId ?? null,
        data_atualizacao_preco: dataCompra,
        data_ultima_compra: dataCompra,
        margem_lucro_percentual: margem,
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
    await upsertFiscalItem(createdId, {
      ncm: it.ncm ?? null,
      aliq_icms: aliq(it.aliquotaIcms),
      aliq_ipi: aliq(it.aliquotaIpi),
      aliq_pis: aliq(it.aliquotaPis),
      aliq_cofins: aliq(it.aliquotaCofins),
    });

    return createdId;
  }

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    setImportErr(null);
    setImportOk(null);
    const files = Array.from(e.target.files ?? []);
    setSelectedFile(files[0] ?? null);
    setIsReading(false);
  }

  function newJobId() {
    return `job-${Math.random().toString(36).slice(2)}`;
  }

  async function addJobFromRaw(xml: string, fileName: string) {
    const parsed = parseXml(xml);
    const cnpj = parsed.nfe.cnpjEmitente ?? null;
    let status: ImportJob["status"] = "ok";
    let error: string | undefined;
    let selected = true;

    const chave = parsed.nfe.chave ?? null;
    if (chave) {
      const { count: nfExiste } = await supabase
        .from("nf_entrada")
        .select("id", { count: "exact" })
        .eq("chave", chave)
        .limit(1);
      if (typeof nfExiste === "number" && nfExiste > 0) {
        status = "importado";
        selected = false;
        error = "NF ja importada";
      }
    }

    if (!fornecedorCnpjBase && cnpj) {
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

    setJobs((prev) => [...prev, job]);
    if (selected) setSelectedJobId(job.id);
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

  async function parseXmlAndCheck() {
    if (isReading || importBusy) return;
    setImportErr(null);
    setImportOk(null);
    setIsReading(true);
    const reqId = ++readReqIdRef.current;

    try {
      if (!selectedFile && !xmlText.trim()) throw new Error("Selecione um XML para ler.");
      setFornecedorId(null);
      setFornecedorNome(null);
      setNfeInfo(null);
      setParsedItens([]);
      setItemMap(new Map());

      if (selectedFile) await addJobFromFile(selectedFile);
      if (xmlText.trim()) await addJobFromRaw(xmlText, "xml-painel");

      if (reqId === readReqIdRef.current) setImportOk("XML lido e validado.");
    } catch (e: any) {
      if (reqId === readReqIdRef.current) setImportErr(typeof e?.message === "string" ? e.message : "Erro ao ler XML.");
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
  }

  async function cadastrarFornecedorEItens() {
    setImportErr(null);
    setImportOk(null);
    setCadBusy(true);

    try {
      const jobsToUse = jobs.filter((j) => j.selected && j.status === "ok" && j.itens.length > 0);
      if (jobsToUse.length === 0) throw new Error("Nenhum XML selecionado.");

      const baseCnpj = fornecedorCnpjBase ?? jobsToUse.find((j) => j.nfeInfo?.cnpjEmitente)?.nfeInfo?.cnpjEmitente ?? null;
      let fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;
      if (!fornecedorFinal && baseCnpj) {
        const { data: found } = await supabase.from("fornecedores").select("id").eq("documento", baseCnpj).maybeSingle();
        fornecedorFinal = found?.id ?? null;
      }
      if (!fornecedorFinal) {
        const first = jobsToUse.find((j) => j.nfeInfo?.emitente && j.nfeInfo?.cnpjEmitente);
        if (first?.nfeInfo?.cnpjEmitente && first.nfeInfo.emitente) {
          fornecedorFinal = await criarFornecedor(first.nfeInfo.cnpjEmitente, first.nfeInfo.emitente);
        }
      }

      const todosItens = jobsToUse.flatMap((j) => j.itens);
      const codigos = Array.from(new Set(todosItens.map((i) => i.codigo)));
      let map = await carregarItensPorCodigo(codigos);

      for (const job of jobsToUse) {
        const dataCompra = job.nfeInfo?.dataEmissao ?? new Date().toISOString();
        for (const it of job.itens) {
          if (!map.has(it.codigo)) {
            const created = await criarItemRapido(it, fornecedorFinal ?? null, dataCompra);
            if (created) map.set(it.codigo, created);
          }
        }
      }

      setItemMap(map);
      setFornecedorIdBase(fornecedorFinal ?? null);
      setImportOk("Fornecedor e itens cadastrados para os XMLs selecionados.");
    } catch (e: any) {
      setImportErr(typeof e?.message === "string" ? e.message : "Erro ao cadastrar.");
    } finally {
      setCadBusy(false);
    }
  }

  async function importarNfe() {
    if (isReading || importBusy) return;
    setImportErr(null);
    setImportOk(null);
    setImportBusy(true);

    const round6 = (n: number) => (Number.isFinite(n) ? Number(n.toFixed(6)) : 0);

    try {
      const jobsToImport = jobs.filter((j) => j.selected && j.status === "ok");
      if (jobsToImport.length === 0) throw new Error("Nenhum XML selecionado para importar.");

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
            results.push(`${job.fileName}: chave não encontrada.`);
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: "Chave ausente" } : j)));
            continue;
          }

          setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importando", error: undefined } : j)));

          const { count: nfJaExiste } = await supabase
            .from("nf_entrada")
            .select("id", { count: "exact" })
            .eq("chave", info.chave)
            .limit(1);
          if (typeof nfJaExiste === "number" && nfJaExiste > 0) {
            results.push(`${job.fileName}: NF já existente, pulada.`);
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: "NF já existia" } : j)));
            continue;
          }

          const codes = Array.from(new Set(job.itens.map((i) => i.codigo)));
          const map = await carregarItensPorCodigo(codes);
          const itemIds = Array.from(map.values());
          const fiscalMap = await carregarFiscalPorItens(itemIds);

          const { data: sess } = await supabase.auth.getSession();
          const userEmail = sess.session?.user?.email ?? null;

          const itemRowsToCreate: ParsedItem[] = [];
          for (const it of job.itens) {
            if (!map.get(it.codigo)) itemRowsToCreate.push(it);
          }
          if (itemRowsToCreate.length > 0) {
            for (const it of itemRowsToCreate) {
              const created = await criarItemRapido(it, fornecedorIdBase ?? fornecedorId ?? null, info.dataEmissao ?? null);
              if (created) map.set(it.codigo, created);
            }
          }

          const nfPayload: any = {
            chave: info.chave,
            numero: info.numero,
            serie: info.serie,
            emitente: info.emitente,
            cnpj_emitente: info.cnpjEmitente,
            valor_produtos: info.valorProdutos ?? 0,
            valor_frete: info.valorFrete ?? 0,
            valor_seguro: info.valorSeguro ?? 0,
            valor_outros: info.valorOutros ?? 0,
            valor_desconto: info.valorDesconto ?? 0,
            valor_total: info.valorTotal ?? 0,
            fornecedor_id: fornecedorIdBase ?? fornecedorId ?? null,
            data_emissao: info.dataEmissao ?? new Date().toISOString(),
            xml_raw: job.xmlText ?? xmlText,
          };

          const { data: nfCreated, error: nfErr } = await supabase.from("nf_entrada").insert(nfPayload).select("id").single();
          if (nfErr) throw nfErr;
          const nfId = nfCreated?.id as number;

          const itemsToImport = job.itens;
          const totalProdutos = itemsToImport.reduce((sum, it) => sum + Number(it.valorProd ?? 0), 0);
          const totalFrete =
            Number(info.valorFrete ?? 0) > 0
              ? Number(info.valorFrete ?? 0)
              : itemsToImport.reduce((sum, it) => sum + Number(it.vFrete ?? 0), 0);
          const totalSeguro =
            Number(info.valorSeguro ?? 0) > 0
              ? Number(info.valorSeguro ?? 0)
              : itemsToImport.reduce((sum, it) => sum + Number(it.vSeguro ?? 0), 0);
          const totalOutros =
            Number(info.valorOutros ?? 0) > 0
              ? Number(info.valorOutros ?? 0)
              : itemsToImport.reduce((sum, it) => sum + Number(it.vOutro ?? 0), 0);
          const totalDesconto =
            Number(info.valorDesconto ?? 0) > 0
              ? Number(info.valorDesconto ?? 0)
              : itemsToImport.reduce((sum, it) => sum + Number(it.vDesc ?? 0), 0);
          const valorTotalNF =
            Number(info.valorTotal ?? 0) || totalProdutos + totalFrete + totalOutros + totalSeguro - totalDesconto;

          const itensRows: any[] = [];
          const movimentacoesRows: any[] = [];

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
            const custoTotal = baseLiquida + Number(it.vOutro ?? 0) + Number(it.vSeguro ?? 0) + freteRateado + custoImpostos;
            const custoUnitBruto = qtd > 0 ? custoTotal / qtd : null;
            const custoUnitReal = custoUnitBruto !== null ? custoUnitBruto - (creditoIcms + creditoPis + creditoCofins) / (qtd || 1) : null;

            itensRows.push({
              nf_entrada_id: nfId,
              item_id: itemId,
              codigo: it.codigo,
              descricao: it.overrideNome ?? it.nome,
              quantidade: round6(qtd),
              valor_unitario: round6(Number(it.valorUnit ?? 0)),
              valor_total: round6(baseLiquida),
              v_desc: round6(Number(it.vDesc ?? 0)),
              v_frete: round6(freteRateado),
              v_seguro: round6(Number(it.vSeguro ?? 0)),
              v_outro: round6(Number(it.vOutro ?? 0)),
              v_ipi: round6(vIpi),
              v_icms: round6(vIcms),
              v_pis: round6(vPis),
              v_cofins: round6(vCofins),
              aliq_icms: fiscal?.aliq_icms ?? it.aliquotaIcms ?? null,
              aliq_ipi: fiscal?.aliq_ipi ?? it.aliquotaIpi ?? null,
              aliq_pis: fiscal?.aliq_pis ?? it.aliquotaPis ?? null,
              aliq_cofins: fiscal?.aliq_cofins ?? it.aliquotaCofins ?? null,
            });

            if (itemId) {
              movimentacoesRows.push({
                item_id: itemId,
                tipo: "entrada",
                quantidade: round6(qtd),
                motivo: `NF ${info.numero ?? ""}/${info.serie ?? ""} chave ${info.chave ?? ""} emitente ${info.emitente ?? ""}`,
                realizado_por: userEmail,
                data_movimentacao: info.dataEmissao ?? new Date().toISOString(),
                custo_unitario_bruto: custoUnitBruto !== null ? round6(custoUnitBruto) : null,
                custo_unitario_real: custoUnitReal !== null ? round6(custoUnitReal) : null,
                v_ipi: round6(vIpi),
                v_icms: round6(vIcms),
                v_pis: round6(vPis),
                v_cofins: round6(vCofins),
                v_frete_rateado: round6(freteRateado),
                credito_icms: round6(creditoIcms),
                credito_pis: round6(creditoPis),
                credito_cofins: round6(creditoCofins),
                origem_nf_entrada_id: nfId,
              });
            }
          }

          if (itensRows.length > 0) {
            const { error: itensErr } = await supabase.from("nf_entrada_itens").insert(itensRows);
            if (itensErr) throw itensErr;
          }
          if (movimentacoesRows.length > 0) {
            const { error: movErr } = await supabase.from("movimentacoes").insert(movimentacoesRows);
            if (movErr) throw movErr;
          }

          setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: undefined } : j)));
          results.push(`${job.fileName}: importado com sucesso.`);
        } catch (err: any) {
          results.push(`${job.fileName}: erro - ${err?.message ?? err}`);
          setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: err?.message ?? "Erro" } : j)));
          continue;
        }
      }

      setJobs((prev) => prev.filter((j) => j.status !== "importado"));
      setImportOk(results.join(" "));
    } catch (e: any) {
      setImportErr(typeof e?.message === "string" ? e.message : "Erro ao importar.");
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
  const hasSelectedOkJobs = jobs.some((j) => j.selected && j.status === "ok");

  useEffect(() => {
    const loadMap = async () => {
      if (!selectedJob || selectedJob.itens.length === 0) {
        setItemMap(new Map());
        return;
      }
      const codes = Array.from(new Set(selectedJob.itens.map((i) => i.codigo)));
      const map = await carregarItensPorCodigo(codes);
      setItemMap(map);
    };
    void loadMap();
  }, [selectedJob]);

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
                setImportErr(null);
                setImportOk(null);
                setFornecedorId(null);
                setFornecedorNome(null);
              }}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Limpar
            </button>
            <button
              onClick={importarNfe}
              disabled={isReading || importBusy || !hasSelectedOkJobs}
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
                onChange={handleFile}
                className="text-sm text-zinc-200"
                disabled={isReading || importBusy}
              />
              <button
                onClick={() => parseXmlAndCheck()}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                disabled={isReading || (!selectedFile && !xmlText) || importBusy}
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
                        <input type="radio" name="job-view" checked={selectedJobId === j.id} onChange={() => selectJob(j.id)} />
                      </td>
                      <td className="px-2 py-1 text-center">
                        <input type="checkbox" checked={j.selected} onChange={() => toggleJobSelected(j.id)} />
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
                Emitente: {selectedJob.nfeInfo.emitente ?? "?"} {selectedJob.nfeInfo.cnpjEmitente ? `(CNPJ ${selectedJob.nfeInfo.cnpjEmitente})` : ""}
              </div>
              <div>Data emissao: {selectedJob.nfeInfo.dataEmissao ?? "?"}</div>
            </div>
          )}

          <div className="border border-zinc-800 rounded-lg p-3 text-sm text-zinc-300 space-y-2">
            <div className="flex items-center justify-between">
              <div>
                <div className="font-semibold text-zinc-100">Fornecedor</div>
                <div className="text-xs text-zinc-400">Valida por CNPJ</div>
              </div>
              {selectedJob?.nfeInfo?.cnpjEmitente && !fornecedorId && (
                <button
                  onClick={() => criarFornecedor(selectedJob.nfeInfo!.cnpjEmitente!, selectedJob.nfeInfo!.emitente ?? "Fornecedor NF")}
                  disabled={importBusy}
                  className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                >
                  Cadastrar fornecedor
                </button>
              )}
            </div>
            {selectedJob?.nfeInfo?.cnpjEmitente && (
              <div className="text-sm">
                CNPJ: {selectedJob.nfeInfo.cnpjEmitente} {fornecedorNome ? `Encontrado: ${fornecedorNome}` : "Nao cadastrado"}
              </div>
            )}
          </div>

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
                    {itensParaTabela.map((it) => {
                      const foundId = itemMap.get(it.codigo);
                      return (
                        <tr key={it.codigo} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2 font-medium">{it.codigo}</td>
                          <td className="px-3 py-2 align-top">
                            <textarea
                              className="w-full px-2 py-2 bg-zinc-900 border border-zinc-700 rounded min-h-[64px] text-sm leading-snug"
                              value={it.overrideNome ?? it.nome}
                              onChange={(e) => {
                                const value = e.target.value;
                                setJobs((prev) =>
                                  prev.map((j) =>
                                    j.id === selectedJobId
                                      ? {
                                          ...j,
                                          itens: j.itens.map((p) =>
                                            p.codigo === it.codigo ? { ...p, overrideNome: value } : p
                                          ),
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
                              <button
                                onClick={() => criarItemRapido(it)}
                                className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                              >
                                Cadastrar item
                              </button>
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
            onClick={cadastrarFornecedorEItens}
            disabled={cadBusy || importBusy || isReading || !hasSelectedOkJobs}
            className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-100"
          >
            {cadBusy ? "Cadastrando..." : "Cadastrar fornecedor e itens"}
          </button>
          <button
            onClick={importarNfe}
            disabled={isReading || importBusy || !hasSelectedOkJobs}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            {importBusy ? "Importando..." : "Importar"}
          </button>
        </div>
      </div>
    </div>
  );
}
