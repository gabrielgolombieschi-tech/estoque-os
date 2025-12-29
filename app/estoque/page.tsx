"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";

type EstoqueRow = {
  id: number;
  item_id: number;
  quantidade_atual: number;
  atualizado_em: string;
  localizacao: string | null;
  itens: {
    codigo_interno: string;
    nome: string;
    tipo: string;
    unidade_medida: string | null;
    controla_estoque: boolean | null;
    estoque_minimo: number | null;
    estoque_ideal: number | null;
    estoque_maximo: number | null;
    ativo: boolean;
  } | null;
};

type ParsedItem = {
  codigo: string;
  nome: string;
  quantidade: number;
  valorUnit: number;
  total: number;
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
};

export default function EstoquePage() {
  const supabase = useMemo(() => supabaseBrowser(), []);

  const [rows, setRows] = useState<EstoqueRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // filtros
  const [q, setQ] = useState("");
  const [soAbaixoMin, setSoAbaixoMin] = useState(false);
  const [ativos, setAtivos] = useState<"ativos" | "todos">("ativos");

  // ajuste rápido
  const [ajusteItemId, setAjusteItemId] = useState<number | null>(null);
  const [ajusteQuantidade, setAjusteQuantidade] = useState<number>(0);
  const [ajusteMotivo, setAjusteMotivo] = useState<string>("Ajuste manual");

  // importação XML
  const [showImport, setShowImport] = useState(false);
  const [xmlText, setXmlText] = useState("");
  const [nfeInfo, setNfeInfo] = useState<ParsedNfe | null>(null);
  const [parsedItens, setParsedItens] = useState<ParsedItem[]>([]);
  const [fornecedorId, setFornecedorId] = useState<number | null>(null);
  const [fornecedorNome, setFornecedorNome] = useState<string | null>(null);
  const [importErr, setImportErr] = useState<string | null>(null);
  const [importOk, setImportOk] = useState<string | null>(null);
  const [importBusy, setImportBusy] = useState(false);
  const [itemMap, setItemMap] = useState<Map<string, number>>(new Map());
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  async function load() {
    setErr(null);

    let query = supabase
      .from("estoque")
      .select(
        "id,item_id,quantidade_atual,atualizado_em,localizacao,itens(codigo_interno,nome,tipo,unidade_medida,controla_estoque,estoque_minimo,estoque_ideal,estoque_maximo,ativo)"
      )
      .order("id", { ascending: false })
      .limit(500);

    // filtra apenas produtos com controle de estoque
    // (não dá pra filtrar forte no relacionamento sem view; fazemos no front também)
    const { data, error } = await query;

    if (error) return setErr(error.message);

    let list: EstoqueRow[] = (data ?? []) as unknown as EstoqueRow[];

    // front filters (garante consistência)
    list = list.filter((r) => r.itens?.tipo === "produto" && r.itens?.controla_estoque);

    if (ativos === "ativos") list = list.filter((r) => r.itens?.ativo);

    const term = q.trim().toLowerCase();
    if (term) {
      list = list.filter((r) => {
        const cod = (r.itens?.codigo_interno ?? "").toLowerCase();
        const nome = (r.itens?.nome ?? "").toLowerCase();
        return cod.includes(term) || nome.includes(term);
      });
    }

    if (soAbaixoMin) {
      list = list.filter((r) => (r.quantidade_atual ?? 0) < Number(r.itens?.estoque_minimo ?? 0));
    }

    setRows(list);
  }

  function parseXml(raw: string): { nfe: ParsedNfe; itens: ParsedItem[] } {
    const parser = new DOMParser();
    const doc = parser.parseFromString(raw, "application/xml");
    const num = (n: string | null | undefined) => {
      const v = Number(n ?? 0);
      return Number.isFinite(v) ? v : 0;
    };
    const numOrNull = (n: string | null | undefined) => {
      const v = Number(n ?? 0);
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
        num(prod.querySelector("IPI > IPITrib > vIPI")?.textContent) ||
        num(prod.querySelector("IPI > IPI > vIPI")?.textContent);
      const vST = num(prod.querySelector("ICMS > * > vICMSST")?.textContent);
      const vOutro = num(prod.querySelector("vOutro")?.textContent);
      const vFrete = num(prod.querySelector("vFrete")?.textContent);
      const vDesc = num(prod.querySelector("vDesc")?.textContent);
      // total = produto + frete + outros + IPI + ST + tributos declarados - desconto
      const totalBase = vProd + vFrete + vOutro + vIPI + vST + vTotTrib - vDesc;
      const total = totalBase > 0 ? totalBase : vProd || quantidade * valorUnit;
      const ncm = prod.querySelector("NCM")?.textContent ?? null;

      // Alíquotas (melhor esforço)
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
        total,
        overrideNome: nome,
        ncm,
        aliquotaIcms,
        aliquotaIpi,
        aliquotaPis,
        aliquotaCofins,
      });
    });

    return {
      nfe: { chave, numero, serie, emitente, dataEmissao, cnpjEmitente },
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
    const { data, error } = await supabase
      .from("itens")
      .select("id,codigo_interno")
      .in("codigo_interno", codigos);
    if (error) {
      setImportErr(error.message);
      return new Map();
    }
    const map = new Map<string, number>();
    (data ?? []).forEach((r: any) => map.set(r.codigo_interno, r.id));
    return map;
  }

  async function criarItemRapido(it: ParsedItem, fornecedorId?: number | null, dataEmissao?: string | null) {
    setImportErr(null);
    const nomeFinal = it.overrideNome?.trim() || it.nome || `Item ${it.codigo}`;
    const dataCompra = dataEmissao || new Date().toISOString();
    const margem = 52; // 52% conforme requisitado
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
        atualizado_em: dataCompra,
        ativo: true,
      })
      .select("id")
      .single();

    if (error) {
      setImportErr(error.message);
      return null;
    }

    // cria estoque se precisar
    await supabase.from("estoque").insert({
      item_id: data.id,
      quantidade_atual: 0,
      atualizado_em: new Date().toISOString(),
    });

    setItemMap((m) => {
      const next = new Map(m);
      next.set(it.codigo, data.id as number);
      return next;
    });

    return data.id as number;
  }

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => setXmlText(String(reader.result || ""));
    reader.readAsText(file);
  }

  async function parseXmlAndCheck() {
    setImportErr(null);
    setImportOk(null);
    setNfeInfo(null);
    setParsedItens([]);
    setFornecedorId(null);
    setFornecedorNome(null);

    if (!xmlText.trim()) {
      setImportErr("Cole ou selecione um XML.");
      return;
    }
    try {
      const parsed = parseXml(xmlText);
      setNfeInfo(parsed.nfe);
      setParsedItens(parsed.itens);
      await checkFornecedor(parsed.nfe.cnpjEmitente);
      const map = await carregarItensPorCodigo(parsed.itens.map((i) => i.codigo));
      setItemMap(map);
      setParsedItens((itens) =>
        itens.map((it) => {
          if (map.has(it.codigo)) return { ...it, overrideNome: it.overrideNome };
          return it;
        })
      );
    } catch (e: any) {
      setImportErr(`Falha ao ler XML: ${e?.message ?? e}`);
    }
  }

  async function importarNfe() {
    setImportErr(null);
    setImportOk(null);
    setImportBusy(true);

    try {
      if (!nfeInfo || parsedItens.length === 0) {
        throw new Error("Nenhum XML processado.");
      }

      // bloqueia duplicidade por chave (ou numero/serie + CNPJ)
      if (nfeInfo.chave) {
        const { count } = await supabase
          .from("movimentacoes")
          .select("id", { count: "exact" })
          .ilike("motivo", `%${nfeInfo.chave}%`)
          .limit(1);
        if (typeof count === "number" && count > 0) {
          throw new Error("NF já importada (chave encontrada em movimentações).");
        }
      } else if (nfeInfo.numero && nfeInfo.serie && nfeInfo.cnpjEmitente) {
        const { count } = await supabase
          .from("movimentacoes")
          .select("id", { count: "exact" })
          .ilike("motivo", `%NF ${nfeInfo.numero}/${nfeInfo.serie}%${nfeInfo.cnpjEmitente}%`)
          .limit(1);
        if (typeof count === "number" && count > 0) {
          throw new Error("NF já importada (número/série + CNPJ encontrados em movimentações).");
        }
      }

      // garante fornecedor
      let fornecedorFinal = fornecedorId;
      if (!fornecedorFinal && nfeInfo.cnpjEmitente && nfeInfo.emitente) {
        const criado = await criarFornecedor(nfeInfo.cnpjEmitente, nfeInfo.emitente);
        fornecedorFinal = criado;
      }

      // recarrega itens existentes
      let map = await carregarItensPorCodigo(parsedItens.map((i) => i.codigo));
      const itemsToImport = [...parsedItens];
      const dataCompra = nfeInfo.dataEmissao ?? new Date().toISOString();

      // se o item já existir sem fornecedor_id, atribui o fornecedor encontrado/criado
      if (fornecedorFinal) {
        const ids = Array.from(map.values());
        if (ids.length > 0) {
          const { data: itensExist, error: itensErr } = await supabase
            .from("itens")
            .select("id,fornecedor_id")
            .in("id", ids);
          if (!itensErr) {
            const semFornecedor = (itensExist ?? []).filter((r: any) => !r.fornecedor_id).map((r: any) => r.id);
            if (semFornecedor.length > 0) {
              await supabase.from("itens").update({ fornecedor_id: fornecedorFinal }).in("id", semFornecedor);
            }
          }
        }
      }

      // cria itens faltantes
      for (const it of itemsToImport) {
        if (!map.has(it.codigo)) {
          const createdId = await criarItemRapido(it, fornecedorFinal ?? null, dataCompra);
          if (createdId) map.set(it.codigo, createdId);
        }
      }

      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      // registra movimentaÇõÇœes
      for (const it of itemsToImport) {
        const itemId = map.get(it.codigo);
        if (!itemId) continue;
        await supabase.from("movimentacoes").insert({
          item_id: itemId,
          tipo: "entrada",
          quantidade: Math.trunc(it.quantidade),
          motivo: `NF ${nfeInfo.numero ?? ""}/${nfeInfo.serie ?? ""} chave ${nfeInfo.chave ?? ""} emitente ${
            nfeInfo.emitente ?? ""
          }`,
          realizado_por: userEmail,
          data_movimentacao: nfeInfo.dataEmissao ?? new Date().toISOString(),
        });
      }

      setItemMap(map);
      setImportOk("ImportaÇõÇœo concluÇðda.");
      await load();
    } catch (e: any) {
      setImportErr(typeof e?.message === "string" ? e.message : "Erro ao importar.");
    } finally {
      setImportBusy(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [soAbaixoMin, ativos]);

  function startAjuste(item_id: number, atual: number) {
    setOk(null);
    setErr(null);
    setAjusteItemId(item_id);
    setAjusteQuantidade(atual); // default: coloca o atual pra você editar pro novo saldo desejado
    setAjusteMotivo("Ajuste manual");
  }

  async function aplicarAjuste() {
    setOk(null);
    setErr(null);

    if (!ajusteItemId) return setErr("Selecione um item para ajustar.");
    if (!Number.isFinite(ajusteQuantidade)) return setErr("Quantidade inválida.");
    const novoSaldo = Math.trunc(ajusteQuantidade);

    setBusy(true);

    // precisamos do saldo atual pra gerar ajuste como diferença (entrada/saida)
    const atualRow = rows.find((r) => r.item_id === ajusteItemId);
    const saldoAtual = Math.trunc(Number(atualRow?.quantidade_atual ?? 0));
    const diff = novoSaldo - saldoAtual;

    if (diff === 0) {
      setBusy(false);
      return setErr("Nada a ajustar (novo saldo igual ao atual).");
    }

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const tipoMov = diff > 0 ? "entrada" : "saida";
    const qtdMov = Math.abs(diff);

    // registra movimentação; trigger atualiza estoque
    const { error } = await supabase.from("movimentacoes").insert({
      item_id: ajusteItemId,
      tipo: tipoMov,
      quantidade: qtdMov,
      motivo: `${ajusteMotivo} (ajuste para ${novoSaldo})`,
      realizado_por: userEmail,
      data_movimentacao: new Date().toISOString(),
    });

    setBusy(false);

    if (error) return setErr(error.message);

    setOk(`Ajuste aplicado. Saldo: ${saldoAtual} → ${novoSaldo}`);
    setAjusteItemId(null);
    setAjusteQuantidade(0);
    await load();
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Estoque</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Saldo atual por produto (com controle de estoque).
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
          <button
            onClick={() => {
              setShowImport(true);
              setImportErr(null);
              setImportOk(null);
            }}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            Importar XML
          </button>
        </div>
      </div>

      {/* Filtros */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input
              className="w-full px-3 py-2"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Código ou nome"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Ativos</div>
            <select className="w-full px-3 py-2" value={ativos} onChange={(e) => setAtivos(e.target.value as any)}>
              <option value="ativos">Somente ativos</option>
              <option value="todos">Ativos + inativos</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Abaixo do mínimo</div>
            <select
              className="w-full px-3 py-2"
              value={soAbaixoMin ? "sim" : "nao"}
              onChange={(e) => setSoAbaixoMin(e.target.value === "sim")}
            >
              <option value="nao">Não</option>
              <option value="sim">Sim</option>
            </select>
          </div>
        </div>

        <div className="flex items-center gap-2 mt-3">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Aplicar filtros
          </button>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </div>

      {showImport && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-3">
            <div className="flex items-center justify-between gap-2">
              <div>
                <div className="text-lg font-semibold">Importar NF-e (XML)</div>
                <div className="text-sm text-zinc-400">Fornecedor por CNPJ, itens por código do produto.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setShowImport(false)}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
                <button
                  onClick={importarNfe}
                  disabled={importBusy || parsedItens.length === 0}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                >
                  {importBusy ? "Importando..." : "Importar"}
                </button>
              </div>
            </div>

            <div className="space-y-2">
              <div className="flex gap-2 items-center">
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".xml"
                  onChange={handleFile}
                  className="text-sm text-zinc-200"
                />
                <button
                  onClick={parseXmlAndCheck}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  disabled={importBusy}
                >
                  Ler XML
                </button>
              </div>
              <textarea
                className="w-full px-3 py-2 min-h-[120px] bg-zinc-900 border border-zinc-700 rounded-lg text-sm"
                placeholder="Cole o XML aqui"
                value={xmlText}
                onChange={(e) => setXmlText(e.target.value)}
              />
            </div>

            {nfeInfo && (
              <div className="border border-zinc-800 rounded-lg p-3 text-sm text-zinc-300 space-y-1">
                <div className="font-semibold text-zinc-100">NF-e</div>
                <div>Chave: {nfeInfo.chave ?? "?"}</div>
                <div>Número/Série: {nfeInfo.numero ?? "?"}/{nfeInfo.serie ?? "?"}</div>
                <div>Emitente: {nfeInfo.emitente ?? "?"} {nfeInfo.cnpjEmitente ? `(CNPJ ${nfeInfo.cnpjEmitente})` : ""}</div>
                <div>Data emissão: {nfeInfo.dataEmissao ?? "?"}</div>
              </div>
            )}

            <div className="border border-zinc-800 rounded-lg p-3 text-sm text-zinc-300 space-y-2">
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-semibold text-zinc-100">Fornecedor</div>
                  <div className="text-xs text-zinc-400">Valida por CNPJ</div>
                </div>
                {nfeInfo?.cnpjEmitente && !fornecedorId && (
                  <button
                    onClick={() => criarFornecedor(nfeInfo.cnpjEmitente!, nfeInfo.emitente ?? "Fornecedor NF")}
                    disabled={importBusy}
                    className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                  >
                    Cadastrar fornecedor
                  </button>
                )}
              </div>
              {nfeInfo?.cnpjEmitente && (
                <div className="text-sm">
                  CNPJ: {nfeInfo.cnpjEmitente} {fornecedorNome ? `• Encontrado: ${fornecedorNome}` : "• Não cadastrado"}
                </div>
              )}
            </div>

            <div className="border border-zinc-800 rounded-lg p-3">
              <div className="flex items-center justify-between mb-2">
                <div className="font-semibold text-zinc-100">Itens da NF</div>
                <div className="text-xs text-zinc-400">Confirme códigos e cadastre os faltantes.</div>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/60 text-zinc-200">
                    <tr>
                      <th className="px-3 py-2 text-left">Código</th>
                      <th className="px-3 py-2 text-left">Descrição NF</th>
                      <th className="px-3 py-2 text-right">Qtd</th>
                      <th className="px-3 py-2 text-right">V.Unit</th>
                      <th className="px-3 py-2 text-right">Total</th>
                      <th className="px-3 py-2 text-center">Status</th>
                      <th className="px-3 py-2 text-center">Ações</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-800">
                    {parsedItens.map((it) => {
                      const foundId = itemMap.get(it.codigo);
                      return (
                        <tr key={it.codigo} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2 font-medium">{it.codigo}</td>
                          <td className="px-3 py-2">
                            <input
                              className="w-full px-2 py-1 bg-zinc-900 border border-zinc-700 rounded"
                              value={it.overrideNome ?? it.nome}
                              onChange={(e) =>
                                setParsedItens((prev) =>
                                  prev.map((p) =>
                                    p.codigo === it.codigo ? { ...p, overrideNome: e.target.value } : p
                                  )
                                )
                              }
                            />
                          </td>
                          <td className="px-3 py-2 text-right tabular-nums">{it.quantidade}</td>
                          <td className="px-3 py-2 text-right tabular-nums">R$ {it.valorUnit.toFixed(2)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">R$ {it.total.toFixed(2)}</td>
                          <td className="px-3 py-2 text-center">
                            {foundId ? (
                              <span className="inline-flex items-center px-2 py-1 rounded-md border border-emerald-500/40 text-emerald-300 text-xs">
                                Cadastrado (id {foundId})
                              </span>
                            ) : (
                              <span className="inline-flex items-center px-2 py-1 rounded-md border border-amber-500/40 text-amber-300 text-xs">
                                Não encontrado
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
                    {parsedItens.length === 0 && (
                      <tr>
                        <td colSpan={8} className="px-3 py-4 text-zinc-400 text-center">
                          Nenhum item lido ainda.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
              {importErr && <div className="text-sm text-red-400 mt-3">{importErr}</div>}
              {importOk && <div className="text-sm text-emerald-300 mt-3">{importOk}</div>}
            </div>
          </div>
        </div>
      )}

      {/* Ajuste rÇ­pido */}

      {/* Ajuste rápido */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="font-medium">Ajuste rápido</div>
        <div className="text-sm text-zinc-400 mt-1">
          Clique em “Ajustar” em um item para definir o novo saldo.
        </div>

        <div className="grid grid-cols-1 md:grid-cols-6 gap-3 mt-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Item selecionado</div>
            <input
              className="w-full px-3 py-2"
              value={ajusteItemId ? `item_id=${ajusteItemId}` : ""}
              disabled
              placeholder="Clique em Ajustar na tabela"
            />
          </div>

          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Novo saldo desejado</div>
            <input
              type="number"
              className="w-full px-3 py-2"
              value={ajusteQuantidade}
              onChange={(e) => setAjusteQuantidade(Number(e.target.value))}
              disabled={!ajusteItemId}
            />
          </div>

          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Motivo</div>
            <input
              className="w-full px-3 py-2"
              value={ajusteMotivo}
              onChange={(e) => setAjusteMotivo(e.target.value)}
              disabled={!ajusteItemId}
            />
          </div>
        </div>

        <div className="mt-3">
          <button
            onClick={aplicarAjuste}
            disabled={busy || !ajusteItemId}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            {busy ? "Aplicando..." : "Aplicar ajuste"}
          </button>
        </div>
      </div>

      {/* Tabela */}
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">ID</th>
              <th className="px-4 py-3 text-left">Código</th>
              <th className="px-4 py-3 text-left">Produto</th>
              <th className="px-4 py-3 text-right">Saldo</th>
              <th className="px-4 py-3 text-right">Mín</th>
              <th className="px-4 py-3 text-right">Ideal</th>
              <th className="px-4 py-3 text-right">Máx</th>
              <th className="px-4 py-3 text-center">Ações</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => {
              const min = Number(r.itens?.estoque_minimo ?? 0);
              const ideal = Number(r.itens?.estoque_ideal ?? 0);
              const max = Number(r.itens?.estoque_maximo ?? 0);
              const saldo = Number(r.quantidade_atual ?? 0);
              const abaixo = saldo < min;

              return (
                <tr key={r.id} className={abaixo ? "bg-red-500/10" : "hover:bg-zinc-900/40"}>
                  <td className="px-4 py-3 text-zinc-300">{r.item_id}</td>
                  <td className="px-4 py-3 font-medium">{r.itens?.codigo_interno}</td>
                  <td className="px-4 py-3">
                    <div className="font-medium">{r.itens?.nome}</div>
                    <div className="text-xs text-zinc-400">
                      {r.itens?.unidade_medida ?? "UN"} • {abaixo ? "Abaixo do mínimo" : "OK"}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">{saldo}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{min}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{ideal}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{max}</td>
                  <td className="px-4 py-3 text-center">
                    <button
                      onClick={() => startAjuste(r.item_id, saldo)}
                      className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                    >
                      Ajustar
                    </button>
                  </td>
                </tr>
              );
            })}

            {rows.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-6 text-zinc-400">
                  Nenhum produto com estoque encontrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
