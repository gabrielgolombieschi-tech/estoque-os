import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";

export const runtime = "nodejs";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message || fallback;
  if (typeof err === "string") return err.trim() ? err : fallback;
  if (err && typeof err === "object") {
    const obj = err as Record<string, unknown>;
    const msg = typeof obj.message === "string" ? obj.message : null;
    if (msg && msg.trim()) return msg.trim();
    const details = typeof obj.details === "string" ? obj.details : null;
    if (details && details.trim()) return details.trim();
    const hint = typeof obj.hint === "string" ? obj.hint : null;
    if (hint && hint.trim()) return hint.trim();
  }
  return fallback;
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function normalizeDigits(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

function firstText(xml: string, tag: string): string | null {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, "i");
  const m = re.exec(xml);
  if (!m) return null;
  const v = String(m[1] ?? "").trim();
  return v ? v : null;
}

function firstAttr(xml: string, tag: string, attr: string): string | null {
  const re = new RegExp(`<${tag}[^>]*\\s${attr}=\"([^\"]+)\"`, "i");
  const m = re.exec(xml);
  if (!m) return null;
  const v = String(m[1] ?? "").trim();
  return v ? v : null;
}


function extractMissingCodigosFromMessage(message: string): string[] {
  const msg = String(message ?? "");
  const marker = "Itens não cadastrados para os códigos:";
  const idx = msg.toLowerCase().indexOf(marker.toLowerCase());
  if (idx < 0) return [];
  const tail = msg.slice(idx + marker.length);
  const rawCodes = tail
    .split(",")
    .map((s) => String(s).trim())
    .filter(Boolean);
  const codes = rawCodes
    .map((c) => c.replace(/^0+(?=\d)/, ""))
    .filter(Boolean);
  return Array.from(new Set(codes));
}

function toNum(value: string | null | undefined): number {
  const v = String(value ?? "").trim().replace(",", ".");
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function toDateOnly(value: string | null | undefined): string | null {
  const v = String(value ?? "").trim();
  if (!v) return null;
  if (/^\d{4}-\d{2}-\d{2}/.test(v)) return v.slice(0, 10);
  return null;
}

function yyyymmdd(value: string | null): string {
  const d = value ? new Date(`${value}T00:00:00`) : new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}${m}${day}`;
}

function buildChaveAcessoNFE(opts: { serie: string; numero: string; emissaoDate: string | null }): string {
  const serie = String(opts.serie ?? "").trim() || "0";
  const numero = String(opts.numero ?? "").trim() || "0";
  const d = yyyymmdd(opts.emissaoDate);
  return `NFE-${serie}-${numero}-${d}`;
}

type ParsedItem = {
  codigo: string;
  nome: string;
  ncm: string | null;
  cfop: string | null;
  unidade: string | null;
  quantidade: number;
  valorUnit: number;
  valorProd: number;
  total: number;
  vIcms: number;
  vIpi: number;
  vPis: number;
  vCofins: number;
  aliqIcms: number | null;
  aliqIpi: number | null;
  aliqPis: number | null;
  aliqCofins: number | null;
};

type ParsedNfe = {
  chave: string | null;
  numero: string | null;
  serie: string | null;
  emitente: string | null;
  cnpjEmitente: string | null;
  dataEmissao: string | null;
  valorProdutos: number;
  valorFrete: number;
  valorSeguro: number;
  valorDesconto: number;
  valorOutros: number;
  valorTotal: number;
};

function parseNfeXmlServer(xmlRaw: string): { nfe: ParsedNfe; itens: ParsedItem[] } {
  const xml = String(xmlRaw ?? "");
  if (!xml.trim()) throw new Error("XML vazio.");

  const idAttr = firstAttr(xml, "infNFe", "Id");
  const chave = idAttr ? idAttr.replace(/^NFe/i, "") : null;

  const numero = firstText(xml, "nNF");
  const serie = firstText(xml, "serie");
  const dataEmissao = firstText(xml, "dhEmi") ?? firstText(xml, "dEmi");

  const emitBlockRe = /<emit[^>]*>([\s\S]*?)<\/emit>/i;
  const emitBlock = emitBlockRe.exec(xml)?.[1] ?? "";
  const emitente = firstText(emitBlock, "xNome");
  const cnpjEmitente = firstText(emitBlock, "CNPJ") ?? firstText(emitBlock, "CPF");

  const totBlockRe = /<ICMSTot[^>]*>([\s\S]*?)<\/ICMSTot>/i;
  const totBlock = totBlockRe.exec(xml)?.[1] ?? "";
  const valorFrete = toNum(firstText(totBlock, "vFrete"));
  const valorProdutos = toNum(firstText(totBlock, "vProd"));
  const valorSeguro = toNum(firstText(totBlock, "vSeg"));
  const valorDesconto = toNum(firstText(totBlock, "vDesc"));
  const valorOutros = toNum(firstText(totBlock, "vOutro"));
  const valorTotal = toNum(firstText(totBlock, "vNF"));

  const itens: ParsedItem[] = [];
  const detRe = /<det\b[^>]*>([\s\S]*?)<\/det>/gi;
  let detMatch: RegExpExecArray | null;
  while ((detMatch = detRe.exec(xml)) !== null) {
    const det = detMatch[1] ?? "";

    const prodBlockRe = /<prod[^>]*>([\s\S]*?)<\/prod>/i;
    const prodBlock = prodBlockRe.exec(det)?.[1] ?? "";

    const codigo = String(firstText(prodBlock, "cProd") ?? "")
      .trim()
      .replace(/^0+(?=\d)/, "");
    if (!codigo) continue;

    const nome = String(firstText(prodBlock, "xProd") ?? "").trim();
    const ncm = firstText(prodBlock, "NCM");
    const cfop = firstText(prodBlock, "CFOP");
    const unidade = (firstText(prodBlock, "uCom") ?? firstText(prodBlock, "uTrib") ?? null)?.trim() || null;
    const quantidade = toNum(firstText(prodBlock, "qCom"));
    const valorUnit = toNum(firstText(prodBlock, "vUnCom"));
    const valorProd = toNum(firstText(prodBlock, "vProd"));
    const vFrete = toNum(firstText(prodBlock, "vFrete"));
    const vOutro = toNum(firstText(prodBlock, "vOutro"));
    const vDesc = toNum(firstText(prodBlock, "vDesc"));

    const icmsBlockRe = /<ICMS[^>]*>([\s\S]*?)<\/ICMS>/i;
    const icmsBlock = icmsBlockRe.exec(det)?.[1] ?? "";
    const vIcms = toNum(firstText(icmsBlock, "vICMS"));
    const aliqIcmsRaw = firstText(icmsBlock, "pICMS");
    const aliqIcms = aliqIcmsRaw ? toNum(aliqIcmsRaw) : null;

    const ipiBlockRe = /<IPI[^>]*>([\s\S]*?)<\/IPI>/i;
    const ipiBlock = ipiBlockRe.exec(det)?.[1] ?? "";
    const vIpi = toNum(firstText(ipiBlock, "vIPI"));
    const aliqIpiRaw = firstText(ipiBlock, "pIPI");
    const aliqIpi = aliqIpiRaw ? toNum(aliqIpiRaw) : null;

    const pisBlockRe = /<PIS[^>]*>([\s\S]*?)<\/PIS>/i;
    const pisBlock = pisBlockRe.exec(det)?.[1] ?? "";
    const vPis = toNum(firstText(pisBlock, "vPIS"));
    const aliqPisRaw = firstText(pisBlock, "pPIS");
    const aliqPis = aliqPisRaw ? toNum(aliqPisRaw) : null;

    const cofinsBlockRe = /<COFINS[^>]*>([\s\S]*?)<\/COFINS>/i;
    const cofinsBlock = cofinsBlockRe.exec(det)?.[1] ?? "";
    const vCofins = toNum(firstText(cofinsBlock, "vCOFINS"));
    const aliqCofinsRaw = firstText(cofinsBlock, "pCOFINS");
    const aliqCofins = aliqCofinsRaw ? toNum(aliqCofinsRaw) : null;

    const totalBase = valorProd + vFrete + vOutro + vIpi - vDesc;
    const total = totalBase > 0 ? totalBase : valorProd || quantidade * valorUnit;

    itens.push({
      codigo,
      nome: nome || codigo,
      ncm,
      cfop,
      unidade,
      quantidade,
      valorUnit,
      valorProd,
      total,
      vIcms,
      vIpi,
      vPis,
      vCofins,
      aliqIcms,
      aliqIpi,
      aliqPis,
      aliqCofins,
    });
  }

  return {
    nfe: {
      chave,
      numero,
      serie,
      emitente,
      cnpjEmitente: normalizeDigits(cnpjEmitente) || null,
      dataEmissao,
      valorProdutos,
      valorFrete,
      valorSeguro,
      valorDesconto,
      valorOutros,
      valorTotal,
    },
    itens,
  };
}

async function resolveFornecedorInternoFaturamento(opts: { tenantId: string; empresaId: string }): Promise<number> {
  const admin = supabaseAdmin();
  const tenantId = opts.tenantId;
  const empresaId = opts.empresaId;
  const nome = "FATURAMENTO (EMITENTE)";

  const { data: existing, error: exErr } = await admin
    .from("fornecedores")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("nome", nome)
    .order("id", { ascending: true })
    .limit(1)
    .maybeSingle<{ id: number }>();
  if (!exErr && existing?.id) return Number(existing.id);

  const { data: created, error: insErr } = await admin
    .from("fornecedores")
    .insert({
      tenant_id: tenantId,
      empresa_id: empresaId,
      nome,
      cnpj: null,
      documento: null,
      ativo: true,
    })
    .select("id")
    .single<{ id: number }>();
  if (insErr) throw insErr;
  return Number(created.id);
}

async function getCurrentUsuarioId(opts: { authUserId: string }): Promise<string | null> {
  const admin = supabaseAdmin();
  const { data, error } = await admin
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", opts.authUserId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle<{ id: string }>();

  if (error) return null;
  return data?.id ? String(data.id) : null;
}

async function resolveMotivoCompraId(opts: { tenantId: string }): Promise<string | null> {
  const admin = supabaseAdmin();
  const { data, error } = await admin
    .schema("f")
    .from("motivo_compra")
    .select("id,codigo,ativo,deleted_at,aplica_em")
    .eq("tenant_id", opts.tenantId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .in("aplica_em", ["PRODUTO", "AMBOS"])
    .order("codigo", { ascending: true })
    .limit(50)
    .returns<Array<{ id: string; codigo: string | null }>>();

  if (error) return null;
  const rows = Array.isArray(data) ? data : [];
  const chosen =
    rows.find((r) => String(r.codigo ?? "").trim().toUpperCase() !== "NAO_CLASSIFICADO") ?? rows[0] ?? null;
  return chosen?.id ? String(chosen.id) : null;
}

async function createPlaceholderItens(opts: {
  tenantId: string;
  empresaId: string;
  missingCodigos: string[];
  parsedItens: ParsedItem[];
  criadoPor?: string | null;
}) {
  const admin = supabaseAdmin();
  const { tenantId, empresaId, missingCodigos, parsedItens } = opts;

  const codigos = Array.from(new Set(missingCodigos.map((c) => String(c).trim()).filter(Boolean)));
  if (!codigos.length) return;

  const { data: existing, error: exErr } = await admin
    .from("itens")
    .select("codigo_interno")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .in("codigo_interno", codigos)
    .limit(codigos.length)
    .returns<Array<{ codigo_interno: string | null }>>();
  if (exErr) throw exErr;

  const existingSet = new Set((existing ?? []).map((r) => String(r.codigo_interno ?? "")).filter(Boolean));
  const toCreate = codigos.filter((c) => !existingSet.has(c));
  if (!toCreate.length) return;

  const byCodigo = new Map<string, ParsedItem>();
  for (const it of parsedItens) {
    const key = String(it.codigo ?? "").trim();
    if (!key) continue;
    if (!byCodigo.has(key)) byCodigo.set(key, it);
  }

  const criadoPor = opts.criadoPor ? String(opts.criadoPor) : null;
  const rows = toCreate.map((codigo) => {
    const it = byCodigo.get(codigo) ?? null;
    const nomeRaw = it?.nome ? String(it.nome) : `ITEM IMPORTADO ${codigo}`;
    const nome = nomeRaw.replace(/\s+/g, " ").trim().toUpperCase().slice(0, 255) || `ITEM IMPORTADO ${codigo}`;
    const unidade = (it?.unidade ? String(it.unidade) : "UN").replace(/\s+/g, "").trim().toUpperCase().slice(0, 10) || "UN";

    return {
      tenant_id: tenantId,
      empresa_id: empresaId,
      codigo_interno: String(codigo).trim().slice(0, 50),
      nome,
      tipo: "produto",
      unidade_medida: unidade,
      controla_estoque: false,
      ativo: true,
      observacoes: "IMPORT_XML (PLACEHOLDER) - REVISAR",
      finalidade: "revenda",
      criado_por: criadoPor,
      atualizado_por: criadoPor,
    };
  });

  const { error: insErr } = await admin.from("itens").insert(rows as unknown as Record<string, unknown>[]);
  if (insErr) {
    const code = typeof insErr.code === "string" ? insErr.code : "";
    if (code !== "23505") throw insErr;
  }

  const { data: placeholderItens, error: placeholderItensErr } = await admin
    .from("itens")
    .select("id,codigo_interno")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .in("codigo_interno", toCreate)
    .returns<Array<{ id: number; codigo_interno: string }>>();
  if (placeholderItensErr) throw placeholderItensErr;

  const fiscalRows = (placeholderItens ?? []).flatMap((item) => {
    const ncm = byCodigo.get(String(item.codigo_interno))?.ncm;
    const ncmNormalizado = ncm ? String(ncm).trim().slice(0, 12) : "";
    if (!ncmNormalizado) return [];

    return [{
      tenant_id: tenantId,
      empresa_id: empresaId,
      item_id: Number(item.id),
      ncm: ncmNormalizado,
    }];
  });

  if (fiscalRows.length > 0) {
    const { error: fiscalErr } = await admin
      .from("fiscal_itens")
      .upsert(fiscalRows, { onConflict: "tenant_id,empresa_id,item_id" });
    if (fiscalErr) throw fiscalErr;
  }
}

export async function POST(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Não autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Não autenticado.");

    const form = await req.formData();
    const file = form.get("file");
    const clienteIdRaw = String(form.get("cliente_id") ?? "").trim();
    const osIdRaw = String(form.get("os_id") ?? "").trim();
    const pagamentosRaw = String(form.get("pagamentos_json") ?? "").trim();
    if (!clienteIdRaw) return jerr(422, "cliente_id é obrigatório.");
    if (!osIdRaw) return jerr(422, "os_id é obrigatório. Vincule a OS antes de importar.");
    const clienteIdNum = Number(clienteIdRaw);
    const osIdNum = Number(osIdRaw);
    let pagamentos: Array<{ numero: string; vencimento: string; valor: number }> | null = null;
    if (!Number.isFinite(osIdNum) || osIdNum <= 0) return jerr(400, "os_id invalido.");
    if (!Number.isFinite(clienteIdNum) || clienteIdNum <= 0) return jerr(400, "cliente_id inválido.");

    if (!file || typeof file !== "object" || !("text" in file)) return jerr(422, "Arquivo XML é obrigatório (file).");
    if (pagamentosRaw) {
      try {
        const pagamentosUnknown = JSON.parse(pagamentosRaw) as unknown;
        if (!Array.isArray(pagamentosUnknown) || pagamentosUnknown.length === 0) {
          return jerr(422, "pagamentos_json invalido.");
        }

        pagamentos = pagamentosUnknown.map((row, idx) => {
          const obj = row && typeof row === "object" ? (row as Record<string, unknown>) : {};
          const numero = String(obj.numero ?? "").trim() || String(idx + 1).padStart(3, "0");
          const vencimento = toDateOnly(String(obj.vencimento ?? obj.data ?? "").trim());
          const valor = Math.round(toNum(String(obj.valor ?? 0)) * 100) / 100;
          if (!vencimento) throw new Error(`Parcela ${idx + 1}: vencimento invalido.`);
          if (valor <= 0) throw new Error(`Parcela ${idx + 1}: valor invalido.`);
          return { numero, vencimento, valor };
        });
      } catch (parseErr: unknown) {
        return jerr(422, getErrorMessage(parseErr, "pagamentos_json invalido."));
      }
    }

    const xmlRaw = await (file as File).text();
    if (!xmlRaw.trim()) return jerr(422, "XML vazio.");


    // This endpoint is used by the Faturamento NF-e flow.
    // Accept any NF-e XML payload and let the downstream import/parser handle variations.
    const tenantHint = String(form.get("tenant_id") ?? form.get("tenantId") ?? "").trim();
    const empresaHint = String(form.get("empresa_id") ?? form.get("empresaId") ?? "").trim();

    // Resolve tenant/empresa from DB-side context when possible.
    let tenantId: string | null = null;
    try {
      const { data: t, error: tErr } = await supabase.rpc("current_tenant_id");
      if (tErr) throw tErr;
      tenantId = t ? String(t) : null;
    } catch {
      tenantId = null;
    }
    if (!tenantId && tenantHint && UUID_REGEX.test(tenantHint)) {
      try {
        await supabase.rpc("set_current_tenant", { p_tenant_id: tenantHint });
        const { data: t2 } = await supabase.rpc("current_tenant_id");
        tenantId = t2 ? String(t2) : null;
      } catch {
        tenantId = null;
      }
    }
    if (!tenantId) return jerr(400, "Tenant não carregado.");

    let empresaId: string | null = null;
    try {
      const { data: e, error: eErr } = await supabase.rpc("current_empresa_id");
      if (eErr) throw eErr;
      empresaId = e ? String(e) : null;
    } catch {
      empresaId = null;
    }
    if (!empresaId && empresaHint && UUID_REGEX.test(empresaHint)) {
      try {
        await supabase.rpc("set_current_empresa", { p_empresa_id: empresaHint });
        const { data: e2 } = await supabase.rpc("current_empresa_id");
        empresaId = e2 ? String(e2) : null;
      } catch {
        empresaId = null;
      }
    }
    if (!empresaId) return jerr(400, "Empresa não carregada.");

    if (osIdNum) {
      const { data: osRow, error: osErr } = await applyTenantEmpresa(
        supabase.from("ordens_servico").select("id").eq("id", osIdNum).limit(1),
        tenantId,
        empresaId
      ).maybeSingle<{ id: number }>();

      if (osErr) return jerr(400, osErr.message ?? "Erro ao validar OS.");
      if (!osRow?.id) return jerr(422, `OS nao encontrada para este tenant/empresa: ${osIdNum}.`);
    }

    // Permissions source: align with client by using the same full permissions JSON.
    // Authorize if user has ANY of the required keys.
    const requiredAny = [
      "faturamento.nfe.import_xml",
      "xml_import.execute",
      "financeiro.write",
      "faturamento.write",
    ];

    const { data: fullPerms, error: permsErr } = await supabase.rpc("get_full_permissions", {
      p_tenant_id: tenantId,
      p_empresa_id: empresaId,
    });

    const permsObj: Record<string, unknown> =
      fullPerms && typeof fullPerms === "object" ? (fullPerms as Record<string, unknown>) : {};

    const permsTrueKeys = Object.entries(permsObj)
      .filter(([, v]) => Boolean(v))
      .map(([k]) => k);

    const hasAny = requiredAny.some((k) => Boolean(permsObj[k]));

    if (permsErr || !hasAny) {
      console.warn("[FATURAMENTO][NFE_IMPORT] permission denied", {
        userId: userData.user.id,
        email: userData.user.email ?? null,
        tenantId,
        empresaId,
        requiredAny,
        gotKeys: permsTrueKeys,
      });
      return jerr(403, "Sem permissão para importar XML de faturamento.");
    }

    const allowed = await getAllowedEmpresas(supabase, tenantId);
    if (!allowed.some((e) => e.id === empresaId)) return jerr(403, "Sem acesso a esta empresa.");

    const solicitanteUsuarioId = await getCurrentUsuarioId({ authUserId: userData.user.id });
    if (!solicitanteUsuarioId || !UUID_REGEX.test(solicitanteUsuarioId)) {
      return jerr(422, "Solicitante (usuario) é obrigatório para importar (a.usuario não encontrado/ativo).");
    }

    const motivoCompraId = await resolveMotivoCompraId({ tenantId });
    if (!motivoCompraId || !UUID_REGEX.test(motivoCompraId)) {
      return jerr(422, "Classificação/Motivo é obrigatório para importar (f.motivo_compra não encontrado/ativo).");
    }

    const parsed = parseNfeXmlServer(xmlRaw);
    const info = parsed.nfe;
    if (!info.chave) return jerr(422, "Chave não encontrada no XML.");

    {
      const { data: saldoRows, error: saldoErr } = await supabase
        .schema("f")
        .rpc("fn_os_saldo_a_faturar", { p_tenant_id: tenantId, p_empresa_id: empresaId, p_os_id: osIdNum });
      if (saldoErr) return jerr(400, getErrorMessage(saldoErr, "Erro ao validar saldo da OS."));

      const saldoRow = (Array.isArray(saldoRows) ? saldoRows[0] : saldoRows) as { saldo?: unknown } | null;
      const saldo = Number(saldoRow?.saldo ?? 0);
      const valorNota = Math.round((Number(info.valorTotal ?? 0) || 0) * 100) / 100;
      if (valorNota > saldo + 0.01) {
        return jerr(
          422,
          `Valor da NF-e (R$ ${valorNota.toFixed(2)}) excede o saldo a faturar da OS (R$ ${saldo.toFixed(2)}). Ajuste o valor orçado da OS ou o valor da nota antes de importar.`
        );
      }
    }

    if (pagamentos && pagamentos.length > 0) {
      const somaPagamentos = Math.round(pagamentos.reduce((acc, pagamento) => acc + pagamento.valor, 0) * 100) / 100;
      const totalDocumento = Math.round((Number(info.valorTotal ?? 0) || 0) * 100) / 100;
      if (totalDocumento > 0 && Math.abs(somaPagamentos - totalDocumento) > 0.05) {
        return jerr(422, `Soma das parcelas (R$ ${somaPagamentos.toFixed(2)}) difere do total da NF-e (R$ ${totalDocumento.toFixed(2)}).`);
      }
    }

    // Prevent duplicate imports: if a documento_fiscal with the same chave already exists,
    // block this request (client can redirect to the existing document).
    {
      const chaveDigitsEarly = normalizeDigits(info.chave);
      if (chaveDigitsEarly.length === 44) {
        const { data: existingDoc } = await applyTenantEmpresa(
          supabase
            .schema("f")
            .from("documento_fiscal")
            .select("id")
            .eq("chave_acesso", chaveDigitsEarly)
            .is("deleted_at", null)
            .limit(1),
          tenantId,
          empresaId
        ).maybeSingle<{ id: string }>();

        if (existingDoc?.id) {
          return NextResponse.json(
            {
              error: "Este XML já foi importado.",
              documento_fiscal_id: String(existingDoc.id),
              chave_acesso: chaveDigitsEarly,
            },
            { status: 409 }
          );
        }
      }
    }

    const fornecedorId = await resolveFornecedorInternoFaturamento({ tenantId, empresaId });

    const codes = Array.from(new Set((parsed.itens ?? []).map((it) => it.codigo).filter(Boolean)));
    const loadItemMap = async () => {
      const { data: itemsData, error: itemsErr } = await applyTenantEmpresa(
        supabase
          .schema("public")
          .from("itens")
          .select("id,codigo_interno")
          .eq("empresa_id", empresaId)
          .in("codigo_interno", codes),
        tenantId,
        empresaId
      ).returns<Array<{ id: number; codigo_interno: string }>>();
      if (itemsErr) throw itemsErr;
      const itemIdByCodigo = new Map<string, number>();
      (itemsData ?? []).forEach((r) => itemIdByCodigo.set(String(r.codigo_interno), Number(r.id)));
      const missing = codes.filter((c) => !itemIdByCodigo.get(c));
      return { itemIdByCodigo, missing };
    };

    let itemMap = await loadItemMap();
    if (itemMap.missing.length) {
      await createPlaceholderItens({
        tenantId,
        empresaId,
        missingCodigos: itemMap.missing,
        parsedItens: parsed.itens ?? [],
        criadoPor: userData.user.email ?? null,
      });
      itemMap = await loadItemMap();
    }

    if (itemMap.missing.length) {
      return jerr(
        422,
        `Itens não cadastrados para os códigos: ${itemMap.missing.slice(0, 12).join(", ")}${itemMap.missing.length > 12 ? "..." : ""}`
      );
    }

    const dataMov = info.dataEmissao ?? new Date().toISOString();
    const motivoStr = `NF ${info.numero ?? ""}/${info.serie ?? ""} chave ${info.chave ?? ""} emitente ${info.emitente ?? ""}`.trim();

    const itensJson = (parsed.itens ?? []).map((it) => ({
      tenant_id: tenantId,
      item_id: itemMap.itemIdByCodigo.get(it.codigo) ?? null,
      codigo: it.codigo,
      nome: it.nome,
      ncm: it.ncm ?? null,
      cfop: it.cfop ?? null,
      quantidade: it.quantidade ?? 0,
      qtd: it.quantidade ?? 0,
      valorUnit: it.valorUnit ?? 0,
      v_unit: it.valorUnit ?? 0,
      total: it.total ?? it.valorProd ?? 0,
      v_prod: it.valorProd ?? it.total ?? 0,
      v_icms: it.vIcms ?? 0,
      v_ipi: it.vIpi ?? 0,
      v_pis: it.vPis ?? 0,
      v_cofins: it.vCofins ?? 0,
      aliq_icms: it.aliqIcms ?? null,
      aliq_ipi: it.aliqIpi ?? null,
      aliq_pis: it.aliqPis ?? null,
      aliq_cofins: it.aliqCofins ?? null,
      tipo: "saida",
      motivo: motivoStr,
      data_movimentacao: dataMov,
    }));

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

    const callImport = async () =>
      supabase.rpc("import_nf_entrada", {
        p_empresa_id: empresaId,
        p_fornecedor_id: fornecedorId,
        p_finalidade_contexto: null,
        p_itens_json: itensJson,
        p_nf_json: nfJson,
        p_tenant_id: tenantId,
        p_xml_raw: xmlRaw,
        p_gerar_contas_pagar: false,
        p_parcelas_json: null,
        // A OS pertence ao faturamento (f.documento_fiscal.os_id_import), nao
        // aos materiais consumidos. Repassar a OS para import_nf_entrada faz
        // os produtos vendidos virarem os_itens e infla o custo da ordem.
        p_os_id: null,
        p_baixar_os: false,
        p_motivo_compra_id: motivoCompraId,
        p_solicitante_usuario_id: solicitanteUsuarioId,
      });

    let importData: unknown = null;
    let importErr: { message?: string } | null = null;

    {
      const res = await callImport();
      importData = res.data as unknown;
      importErr = (res.error as unknown as { message?: string } | null) ?? null;
    }

    // Auto-criar placeholders e re-tentar uma vez (sem loop infinito).
    if (importErr?.message) {
      const missingFromMsg = extractMissingCodigosFromMessage(importErr.message);
      if (missingFromMsg.length) {
        try {
          await createPlaceholderItens({
            tenantId,
            empresaId,
            missingCodigos: missingFromMsg,
            parsedItens: parsed.itens ?? [],
            criadoPor: userData.user.email ?? null,
          });
          const res2 = await callImport();
          importData = res2.data as unknown;
          importErr = (res2.error as unknown as { message?: string } | null) ?? null;
        } catch {
          // keep original error
        }
      }
    }

    if (importErr) return jerr(400, importErr.message ?? "Erro ao importar NF.");

    const resultUnknown = Array.isArray(importData) ? (importData[0] as unknown) : (importData as unknown);
    const result = (resultUnknown ?? null) as { nf_entrada_id?: unknown; nf_id?: unknown } | null;
    const nfEntradaIdRaw = result?.nf_entrada_id ?? result?.nf_id ?? null;
    const nfEntradaId = nfEntradaIdRaw ? Number(nfEntradaIdRaw) || null : null;
    if (!nfEntradaId) return jerr(500, "Importação não retornou nf_entrada_id.");

    const { data: dfId, error: ensureErr } = await supabase
      .schema("f")
      .rpc("fn_ensure_documento_fiscal_from_nf_entrada", { p_nf_entrada_id: nfEntradaId });

    if (ensureErr || !dfId) {
      return Response.json({ error: "Importado, mas não foi possível localizar o documento fiscal.", details: ensureErr?.message }, { status: 500 });
    }

    const documentoFiscalId = String(dfId);

    const { data: docRow, error: docErr } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id,chave_acesso,emissao_date,serie,numero")
        .eq("id", documentoFiscalId)
        .is("deleted_at", null),
      tenantId,
      empresaId
    ).maybeSingle<{ id: string; chave_acesso: string; emissao_date: string | null; serie: string | null; numero: string | null }>();
    if (docErr) return jerr(400, docErr.message ?? "Erro ao carregar documento fiscal.");

    const emissaoDate = docRow?.emissao_date ?? toDateOnly(info.dataEmissao) ?? toDateOnly(String(nfJson.data_emissao ?? ""));
    if (!emissaoDate) {
      return Response.json({ error: "Não foi possível resolver emissao_date/competencia_date.", details: info.dataEmissao ?? null }, { status: 422 });
    }
    const competenciaDate = `${emissaoDate.slice(0, 7)}-01`;

    const serieDoc = String(docRow?.serie ?? info.serie ?? "").trim();
    const numeroDoc = String(docRow?.numero ?? info.numero ?? "").trim();
    const chaveAcessoHint = info.chave ? String(info.chave) : "";
    let chaveAcessoFinal = docRow?.chave_acesso ? String(docRow.chave_acesso) : chaveAcessoHint;
    if (!chaveAcessoFinal) {
      chaveAcessoFinal = info.chave || buildChaveAcessoNFE({ serie: serieDoc, numero: numeroDoc, emissaoDate });
    }
    const chaveDigits = normalizeDigits(chaveAcessoFinal);
    if (chaveDigits.length !== 44) {
      return Response.json({ error: "Chave de acesso inválida (esperado 44 dígitos).", details: chaveAcessoFinal || null }, { status: 422 });
    }

    const nowIso = new Date().toISOString();
    const { error: updErr } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .update({
          cliente_id: clienteIdNum,
          operacao: "SAIDA",
          natureza: "PRODUTO",
          nfe_status: "EMITIDA",
          competencia_date: competenciaDate,
          chave_acesso: chaveDigits,
          os_id_import: osIdNum,
          updated_at: nowIso,
        })
        .eq("id", documentoFiscalId)
        .is("deleted_at", null),
      tenantId,
      empresaId
    );
    if (updErr) return jerr(400, updErr.message ?? "Erro ao atualizar documento fiscal.");

    const { error: impErr } = await supabase
      .schema("f")
      .rpc("nfe_gravar_impostos_do_documento", { p_documento_fiscal_id: documentoFiscalId });
    if (impErr) {
      return Response.json({ error: "Falha ao gravar impostos do documento.", details: impErr.message }, { status: 500 });
    }

    if (pagamentos && pagamentos.length > 0) {
      const { error: parcelasErr } = await supabase.rpc("faturamento_sync_titulo_ar_parcelas", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_documento_fiscal_id: documentoFiscalId,
        p_parcelas_json: pagamentos,
      });
      if (parcelasErr) {
        return Response.json(
          { error: "Falha ao sincronizar parcelas do contas a receber.", details: parcelasErr.message },
          { status: 422 }
        );
      }
    }

    const { data: arRow } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("titulo")
        .select("id")
        .eq("documento_fiscal_id", documentoFiscalId)
        .eq("tipo", "AR")
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(1),
      tenantId,
      empresaId
    ).maybeSingle<{ id: string }>();

    return NextResponse.json({
      documento_fiscal_id: documentoFiscalId,
      ...(arRow?.id ? { titulo_ar_id: String(arRow.id) } : {}),
    });
  } catch (e: unknown) {
    const message = getErrorMessage(e, "Erro inesperado.");
    console.error("[FATURAMENTO][NFE_IMPORT] Erro no endpoint importar-xml", { message });
    return jerr(500, message);
  }
}
