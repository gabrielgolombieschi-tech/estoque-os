"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR } from "@/lib/decimal";
import { isNfseSerieCompatible, normalizeNfseNumeroIdentity } from "@/lib/nfse/identity";
import NfseItensEditor, { type NfseServicoForm } from "./NfseItensEditor";
import NfseIssCard from "./NfseIssCard";
import OsVinculoField from "@/app/faturamento/components/OsVinculoField";
import { fetchOsSelectionById, type OsSelection } from "@/lib/os-vinculo";

type DocumentoFiscalRow = {
  id: string;
  emissao_date: string | null;
  competencia_date: string | null;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string;
  cliente_id: number | string | null;
  valor_total: number | string | null;
  valor_servicos: number | string | null;
  nfse_status: string | null;
  material_percent: number | string | null;
  material_valor: number | string | null;
  os_id_import: number | null;
  created_at: string;
};

type ItemRow = {
  id: string;
  item_n: number;
  item_tipo: "PRODUTO" | "SERVICO" | string;
  codigo: string | null;
  descricao: string;
  codigo_servico: string | null;
  quantidade: number | string;
  valor_unitario: number | string;
  valor_total: number | string;
};

type ImpostoRow = {
  id: string;
  imposto: string;
  natureza: string;
  base_original: number | string;
  deducoes: number | string;
  base_calculo: number | string;
  aliquota: number | string;
  valor_calculado: number | string;
  valor_ajustado: number | string | null;
};

type ClienteRow = { id: number; nome: string };

type LinkedTituloRow = {
  id: string;
  status: string | null;
  valor_total: number | string | null;
  valor_aberto: number | string | null;
};

type DuplicateNfseRow = {
  id: string;
  emissao_date: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string | null;
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function round2(v: number): number {
  return Math.round((v + Number.EPSILON) * 100) / 100;
}

function round4(v: number): number {
  return Math.round((v + Number.EPSILON) * 10000) / 10000;
}

function round2Str(v: number): string {
  return round2(v).toFixed(2);
}

function round4Str(v: number): string {
  return round4(v).toFixed(4);
}

function toISODate(d: Date): string {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function competenciaFromEmissao(emissaoDate: string): string {
  const d = new Date(`${emissaoDate}T00:00:00`);
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  return `${yyyy}-${mm}-01`;
}

function buildChaveAcessoNFSE(serie: string, numero: string, emissaoDate: string): string {
  const yyyymmdd = emissaoDate.replaceAll("-", "");
  const s = String(serie || "").trim().toUpperCase();
  const n = String(numero || "").trim().toUpperCase();
  return `NFSE-${s}-${n}-${yyyymmdd}`;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

export default function NfseForm({ mode, id }: { mode: "new" | "edit"; id?: string }) {
  const te = useTenantEmpresa();
  const router = useRouter();

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO";

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (isFinanceiroEmpresaRole) return true;
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [isFinanceiroEmpresaRole, te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1) &&
    canFinanceiro === true;

  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const today = useMemo(() => toISODate(new Date()), []);

  const [docId, setDocId] = useState<string | null>(mode === "edit" ? String(id || "") : null);
  const [status, setStatus] = useState<string>("RASCUNHO");

  const [emissaoDate, setEmissaoDate] = useState<string>(today);
  const [serie, setSerie] = useState<string>("");
  const [numero, setNumero] = useState<string>("");

  const [clienteId, setClienteId] = useState<number | null>(null);
  const [clienteNome, setClienteNome] = useState<string>("");
  const [clienteQ, setClienteQ] = useState<string>("");
  const [clienteResults, setClienteResults] = useState<ClienteRow[]>([]);
  const [osSelection, setOsSelection] = useState<OsSelection | null>(null);

  const [servico, setServico] = useState<NfseServicoForm>({
    descricao: "Prestação de serviço",
    codigo_servico: "",
    quantidade: 1,
    valor_unitario: 0,
  });

  const [materialPercent, setMaterialPercent] = useState<number>(0);
  const [materialValor, setMaterialValor] = useState<number>(0);
  const [aliquotaIss, setAliquotaIss] = useState<number>(2);

  const valorServicos = useMemo(() => round2((servico.quantidade || 0) * (servico.valor_unitario || 0)), [servico]);
  const materialValorClamped = useMemo(() => Math.min(round2(materialValor || 0), valorServicos), [materialValor, valorServicos]);
  const valorTotal = useMemo(() => round2(valorServicos), [valorServicos]);

  const readOnly = useMemo(() => String(status || "").toUpperCase() === "EMITIDA", [status]);

  const [loading, setLoading] = useState<boolean>(mode === "edit");
  const [saving, setSaving] = useState<boolean>(false);
  const [savingOsLink, setSavingOsLink] = useState<boolean>(false);
  const [emitting, setEmitting] = useState<boolean>(false);
  const [deleting, setDeleting] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const loadClienteNome = async (cId: number) => {
    if (!ready) return;
    const supabase = supabaseBrowser();
    const { data, error } = await applyTenantEmpresa(supabase.from("clientes").select("id,nome").eq("id", cId), tenantId, empresaId)
      .maybeSingle<ClienteRow>();
    if (error) throw error;
    const nome = data?.nome ? String(data.nome) : "";
    setClienteNome(nome);
    setClienteQ(nome);
  };

  const searchClientes = async (q: string) => {
    if (!ready) return;
    const term = q.trim();
    if (!term) return setClienteResults([]);

    const supabase = supabaseBrowser();
    let query = applyTenantEmpresa(
      supabase.from("clientes").select("id,nome").order("nome", { ascending: true }).limit(20),
      tenantId,
      empresaId
    );

    const maybeId = Number(term);
    if (Number.isFinite(maybeId) && maybeId > 0) {
      query = query.or(`id.eq.${maybeId},nome.ilike.%${term}%`);
    } else {
      query = query.ilike("nome", `%${term}%`);
    }

    const { data, error } = await query.returns<ClienteRow[]>();
    if (error) throw error;
    setClienteResults(data ?? []);
  };

  useEffect(() => {
    if (!ready) return;
    const t = setTimeout(() => {
      void searchClientes(clienteQ);
    }, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clienteQ, ready]);

  const loadDoc = async (docIdToLoad: string) => {
    if (!ready) return;
    setLoading(true);
    setError(null);
    setOk(null);

    const supabase = supabaseBrowser();

    try {
      const base = supabase.schema("f").from("documento_fiscal");
      const { data: doc, error: docErr } = await applyTenantEmpresa(
        base
          .select(
            "id,emissao_date,competencia_date,modelo,serie,numero,chave_acesso,cliente_id,valor_total,valor_servicos,nfse_status,material_percent,material_valor,os_id_import,created_at"
          )
          .eq("id", docIdToLoad)
          .eq("operacao", "SAIDA")
          .eq("natureza", "SERVICO")
          .is("deleted_at", null),
        tenantId,
        empresaId
      ).maybeSingle<DocumentoFiscalRow>();
      if (docErr) throw docErr;
      if (!doc?.id) throw new Error("NFS-e não encontrada.");

      setDocId(String(doc.id));
      setStatus(String(doc.nfse_status ?? "RASCUNHO"));
      setEmissaoDate(doc.emissao_date ? String(doc.emissao_date) : today);
      setSerie(doc.serie ? String(doc.serie) : "");
      setNumero(doc.numero ? String(doc.numero) : "");

      const cId = doc.cliente_id === null || doc.cliente_id === undefined ? null : Number(doc.cliente_id) || null;
      setClienteId(cId);
      const osIdImport = doc.os_id_import === null || doc.os_id_import === undefined ? null : Number(doc.os_id_import) || null;
      if (osIdImport) {
        const resolvedOs = await fetchOsSelectionById({
          supabase,
          tenantId,
          empresaId,
          osId: osIdImport,
        });
        setOsSelection(resolvedOs);
      } else {
        setOsSelection(null);
      }

      const vServ = n(doc.valor_servicos);
      const mVal = round2(n(doc.material_valor));
      const mPct = round4(n(doc.material_percent));
      setMaterialValor(mVal);
      setMaterialPercent(mPct);

      setServico((prev) => ({
        ...prev,
        quantidade: 1,
        valor_unitario: vServ,
      }));

      const { data: items, error: itemsErr } = await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal_item")
          .select("id,item_n,item_tipo,codigo,descricao,codigo_servico,quantidade,valor_unitario,valor_total")
          .eq("documento_fiscal_id", docIdToLoad)
          .is("deleted_at", null)
          .order("item_n", { ascending: true }),
        tenantId,
        empresaId
      ).returns<ItemRow[]>();
      if (itemsErr) throw itemsErr;

      const serv = (items ?? []).find((r) => String(r.item_tipo).toUpperCase() === "SERVICO") ?? null;
      if (serv) {
        setServico({
          descricao: String(serv.descricao ?? ""),
          codigo_servico: serv.codigo_servico ? String(serv.codigo_servico) : "",
          quantidade: round4(n(serv.quantidade)),
          valor_unitario: round2(n(serv.valor_unitario)),
        });
      }
      const materialItem = (items ?? []).find((r) => String(r.item_tipo).toUpperCase() === "PRODUTO") ?? null;
      if (materialItem && mVal <= 0) {
        const mv = round2(n(materialItem.valor_total));
        setMaterialValor(mv);
        if (vServ > 0) setMaterialPercent(round4((mv / vServ) * 100));
      }

      const { data: iss, error: issErr } = await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal_imposto")
          .select("id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,valor_ajustado")
          .eq("documento_fiscal_id", docIdToLoad)
          .eq("imposto", "ISS")
          .is("deleted_at", null),
        tenantId,
        empresaId
      ).maybeSingle<ImpostoRow>();
      if (issErr) throw issErr;
      if (iss?.aliquota !== undefined && iss?.aliquota !== null) {
        setAliquotaIss(round4(n(iss.aliquota)));
      }

      if (cId) {
        await loadClienteNome(cId);
      } else {
        setClienteNome("");
        setClienteQ("");
      }
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!ready) return;
    if (mode !== "edit") return;
    if (!id) return;
    void loadDoc(String(id));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, mode, id]);

  const onMaterialPercent = (pct: number) => {
    const safePct = Math.max(0, pct);
    setMaterialPercent(safePct);
    if (valorServicos > 0) {
      setMaterialValor(round2((valorServicos * safePct) / 100));
    } else {
      setMaterialValor(0);
    }
  };

  const onMaterialValor = (mv: number) => {
    const safeVal = Math.max(0, mv);
    setMaterialValor(safeVal);
    if (valorServicos > 0) {
      const pct = round4((safeVal / valorServicos) * 100);
      setMaterialPercent(Number.isFinite(pct) ? pct : 0);
    } else {
      setMaterialPercent(0);
    }
  };

  const validateBasic = () => {
    if (!emissaoDate) return "Emissão é obrigatória.";
    if (!serie.trim()) return "Série é obrigatória.";
    if (!numero.trim()) return "Número é obrigatório.";
    return null;
  };

  const findDuplicateForNewDoc = async ({
    clienteIdToCheck,
    emissao,
    serieValue,
    numeroValue,
    chaveValue,
  }: {
    clienteIdToCheck: number | null;
    emissao: string;
    serieValue: string;
    numeroValue: string;
    chaveValue: string;
  }) => {
    if (!clienteIdToCheck) return null;

    const year = emissao.slice(0, 4);
    if (!/^\d{4}$/.test(year)) return null;

    const numeroIdentidade = normalizeNfseNumeroIdentity(numeroValue, emissao);
    if (!numeroIdentidade) return null;

    const supabase = supabaseBrowser();
    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id,emissao_date,serie,numero,chave_acesso")
        .eq("operacao", "SAIDA")
        .eq("natureza", "SERVICO")
        .eq("modelo", "NFSE")
        .eq("cliente_id", clienteIdToCheck)
        .gte("emissao_date", `${year}-01-01`)
        .lte("emissao_date", `${year}-12-31`)
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(50),
      tenantId,
      empresaId
    ).returns<DuplicateNfseRow[]>();
    if (error) throw error;

    return (
      (data ?? []).find((row) => {
        if (!row?.id) return false;

        const existingKey = String(row.chave_acesso ?? "").trim();
        if (existingKey && existingKey === chaveValue) return true;

        const existingNumeroIdentidade = normalizeNfseNumeroIdentity(row.numero, row.emissao_date);
        if (!existingNumeroIdentidade || existingNumeroIdentidade !== numeroIdentidade) return false;

        return isNfseSerieCompatible(row.serie, serieValue);
      }) ?? null
    );
  };

  const buildPayload = (forceStatus: string) => {
    const serieTrim = serie.trim();
    const numeroTrim = numero.trim();
    const emissao = emissaoDate || today;
    const competencia = competenciaFromEmissao(emissao);

    const chave = buildChaveAcessoNFSE(serieTrim, numeroTrim, emissao);

    const baseOriginal = round2(valorServicos);
    const deducoes = round2(materialValorClamped);
    const baseCalculo = round2(Math.max(0, baseOriginal - deducoes));
    const aliquota = round4(aliquotaIss);
    const valorIss = round2((baseCalculo * aliquota) / 100);

    const docPayload = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      operacao: "SAIDA",
      natureza: "SERVICO",
      modelo: "NFSE",
      serie: serieTrim,
      numero: numeroTrim,
      chave_acesso: chave,
      emissao_date: emissao,
      competencia_date: competencia,
      cliente_id: clienteId ?? null,
      os_id_import: osSelection?.id ?? null,
      valor_servicos: round2Str(baseOriginal),
      valor_total: round2Str(baseOriginal),
      material_percent: round4Str(materialPercent || 0),
      material_valor: round2Str(deducoes),
      nfse_status: forceStatus,
    };

    const itemsPayload = [
      {
        tenant_id: tenantId,
        documento_fiscal_id: docId ?? undefined,
        item_n: 1,
        item_tipo: "SERVICO",
        codigo: null,
        descricao: servico.descricao.trim() || "Prestação de serviço",
        codigo_servico: servico.codigo_servico.trim() || null,
        quantidade: round4Str(servico.quantidade || 0),
        valor_unitario: round2Str(servico.valor_unitario || 0),
        valor_total: round2Str(baseOriginal),
      },
      ...(deducoes > 0
        ? [
            {
              tenant_id: tenantId,
              documento_fiscal_id: docId ?? undefined,
              item_n: 2,
              item_tipo: "PRODUTO",
              codigo: null,
              descricao: "MATERIAL (dedução)",
              codigo_servico: null,
              quantidade: round4Str(1),
              valor_unitario: round2Str(deducoes),
              valor_total: round2Str(deducoes),
            },
          ]
        : []),
    ];

    const issPayload = {
      tenant_id: tenantId,
      documento_fiscal_id: docId ?? undefined,
      imposto: "ISS",
      natureza: "RETENCAO",
      base_original: round2Str(baseOriginal),
      deducoes: round2Str(deducoes),
      base_calculo: round2Str(baseCalculo),
      aliquota: round4Str(aliquota),
      valor_calculado: round2Str(valorIss),
      valor_ajustado: null,
    };

    return { docPayload, itemsPayload, issPayload, chave };
  };

  const saveAll = async (forceStatus: string, opts?: { redirect?: boolean }) => {
    if (!ready) return { ok: false as const, id: null as string | null };

    setSaving(true);
    setError(null);
    setOk(null);

    const basicErr = validateBasic();
    if (basicErr) {
      setSaving(false);
      setError(basicErr);
      return { ok: false as const, id: null as string | null };
    }

    const nowIso = new Date().toISOString();
    const supabase = supabaseBrowser();

    try {
      const { docPayload, itemsPayload, issPayload } = buildPayload(forceStatus);

      if (!docId) {
        const duplicate = await findDuplicateForNewDoc({
          clienteIdToCheck: clienteId,
          emissao: String(docPayload.emissao_date ?? ""),
          serieValue: String(docPayload.serie ?? ""),
          numeroValue: String(docPayload.numero ?? ""),
          chaveValue: String(docPayload.chave_acesso ?? ""),
        });
        if (duplicate) {
          const serieDup = String(duplicate.serie ?? "").trim() || "-";
          const numeroDup = String(duplicate.numero ?? "").trim() || "-";
          throw new Error(`Ja existe uma NFS-e potencialmente duplicada: ${serieDup}/${numeroDup} (ID ${duplicate.id}).`);
        }
      }

      const baseDoc = supabase.schema("f").from("documento_fiscal");
      const qDoc = docId
        ? applyTenantEmpresa(baseDoc.update({ ...docPayload, updated_at: nowIso }).eq("id", docId).select("id,nfse_status"), tenantId, empresaId)
        : applyTenantEmpresa(baseDoc.insert({ ...docPayload }).select("id,nfse_status"), tenantId, empresaId);

      const { data: docData, error: docErr } = await qDoc.maybeSingle<{ id: string; nfse_status?: string | null }>();
      if (docErr) throw docErr;
      const savedId = docId ?? (docData?.id ? String(docData.id) : "");
      if (!savedId) throw new Error("Falha ao salvar NFS-e (sem id).");

      setDocId(savedId);
      setStatus(String(docData?.nfse_status ?? forceStatus));

      await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal_item")
          .update({ deleted_at: nowIso, updated_at: nowIso })
          .eq("documento_fiscal_id", savedId)
          .is("deleted_at", null),
        tenantId,
        empresaId
      );

      const itemsToInsert = itemsPayload.map((it) => ({ ...it, documento_fiscal_id: savedId }));
      const { error: insItemsErr } = await applyTenantEmpresa(
        supabase.schema("f").from("documento_fiscal_item").insert(itemsToInsert),
        tenantId,
        empresaId
      );
      if (insItemsErr) throw insItemsErr;

      await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal_imposto")
          .update({ deleted_at: nowIso, updated_at: nowIso })
          .eq("documento_fiscal_id", savedId)
          .eq("imposto", "ISS")
          .is("deleted_at", null),
        tenantId,
        empresaId
      );

      const { error: insIssErr } = await applyTenantEmpresa(
        supabase.schema("f").from("documento_fiscal_imposto").insert({ ...issPayload, documento_fiscal_id: savedId }),
        tenantId,
        empresaId
      );
      if (insIssErr) throw insIssErr;

      setOk("Salvo.");
      if (mode === "new" && opts?.redirect !== false) router.replace(`/faturamento/nfse/${savedId}`);
      return { ok: true as const, id: savedId };
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao salvar NFS-e.");
      return { ok: false as const, id: null as string | null };
    } finally {
      setSaving(false);
    }
  };

  const emit = async () => {
    if (!ready) return;
    if (readOnly) return;

    setEmitting(true);
    setError(null);
    setOk(null);

    const basicErr = validateBasic();
    if (basicErr) {
      setEmitting(false);
      setError(basicErr);
      return;
    }
    if (!clienteId) {
      setEmitting(false);
      setError("Cliente é obrigatório para emitir.");
      return;
    }
    if (valorServicos <= 0) {
      setEmitting(false);
      setError("Valor de serviços deve ser maior que zero para emitir.");
      return;
    }

    try {
      const saved = await saveAll("RASCUNHO", { redirect: false });
      const savedId = saved.id ?? docId;
      if (!saved.ok || !savedId) throw new Error("Falha ao salvar antes de emitir.");

      const nowIso = new Date().toISOString();
      const emissao = emissaoDate || today;
      const chave = buildChaveAcessoNFSE(serie.trim(), numero.trim(), emissao);

      const supabase = supabaseBrowser();
      const { error: updErr } = await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal")
          .update({ nfse_status: "EMITIDA", chave_acesso: chave, updated_at: nowIso })
          .eq("id", savedId)
          .eq("operacao", "SAIDA")
          .eq("natureza", "SERVICO")
          .is("deleted_at", null),
        tenantId,
        empresaId
      );
      if (updErr) throw updErr;

      setStatus("EMITIDA");
      setOk("Emitida. Contas a Receber gerado automaticamente.");
      if (mode === "new") router.replace(`/faturamento/nfse/${savedId}`);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao emitir NFS-e.");
    } finally {
      setEmitting(false);
    }
  };

  const saveOsLink = async () => {
    if (!ready || mode !== "edit" || !docId) return;

    setSavingOsLink(true);
    setError(null);
    setOk(null);

    try {
      const supabase = supabaseBrowser();
      const nowIso = new Date().toISOString();
      const { error: updErr } = await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal")
          .update({
            os_id_import: osSelection?.id ?? null,
            updated_at: nowIso,
          })
          .eq("id", docId)
          .eq("operacao", "SAIDA")
          .eq("natureza", "SERVICO")
          .is("deleted_at", null),
        tenantId,
        empresaId
      );

      if (updErr) throw updErr;
      setOk(osSelection ? "OS vinculada atualizada." : "Vinculo com OS removido.");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao salvar a OS vinculada.");
    } finally {
      setSavingOsLink(false);
    }
  };

  const removeDoc = async () => {
    if (!ready || mode !== "edit" || !docId) return;
    if (
      typeof window !== "undefined" &&
      !window.confirm("Excluir esta NFS-e e o contas a receber vinculado? Depois sera possivel reimportar.")
    ) {
      return;
    }

    setDeleting(true);
    setError(null);
    setOk(null);

    const nowIso = new Date().toISOString();
    const supabase = supabaseBrowser();

    try {
      const { data: titulos, error: titErr } = await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("titulo")
          .select("id,status,valor_total,valor_aberto")
          .eq("documento_fiscal_id", docId)
          .eq("tipo", "AR")
          .is("deleted_at", null),
        tenantId,
        empresaId
      ).returns<LinkedTituloRow[]>();
      if (titErr) throw titErr;

      const linkedTitulos = titulos ?? [];
      const hasRecebimento = linkedTitulos.some((titulo) => {
        const statusTitulo = String(titulo.status ?? "").trim().toUpperCase();
        if (statusTitulo === "PAGO") return true;
        return Math.abs(round2(n(titulo.valor_total)) - round2(n(titulo.valor_aberto))) > 0.009;
      });

      if (hasRecebimento) {
        throw new Error("A NFS-e possui recebimento/baixa no financeiro. Estorne primeiro o contas a receber.");
      }

      const tituloIds = linkedTitulos.map((titulo) => String(titulo.id)).filter(Boolean);

      if (tituloIds.length) {
        const [agendamentoRes, parcelaRes, rateioRes, tituloRes] = await Promise.all([
          applyTenantEmpresa(
            supabase
              .schema("f")
              .from("titulo_agendamento")
              .update({ deleted_at: nowIso, updated_at: nowIso })
              .in("titulo_id", tituloIds)
              .is("deleted_at", null),
            tenantId,
            empresaId
          ),
          applyTenantEmpresa(
            supabase
              .schema("f")
              .from("titulo_parcela")
              .update({ valor_aberto: 0, deleted_at: nowIso, updated_at: nowIso })
              .in("titulo_id", tituloIds)
              .is("deleted_at", null),
            tenantId,
            empresaId
          ),
          applyTenantEmpresa(
            supabase
              .schema("f")
              .from("titulo_rateio")
              .update({ deleted_at: nowIso, updated_at: nowIso })
              .in("titulo_id", tituloIds)
              .is("deleted_at", null),
            tenantId,
            empresaId
          ),
          applyTenantEmpresa(
            supabase
              .schema("f")
              .from("titulo")
              .update({ status: "CANCELADO", valor_aberto: 0, deleted_at: nowIso, updated_at: nowIso })
              .in("id", tituloIds)
              .is("deleted_at", null),
            tenantId,
            empresaId
          ),
        ]);

        if (agendamentoRes.error) throw agendamentoRes.error;
        if (parcelaRes.error) throw parcelaRes.error;
        if (rateioRes.error) throw rateioRes.error;
        if (tituloRes.error) throw tituloRes.error;
      }

      const [xmlRes, docRes] = await Promise.all([
        applyTenantEmpresa(
          supabase
            .schema("f")
            .from("documento_fiscal_xml")
            .update({ deleted_at: nowIso })
            .eq("documento_fiscal_id", docId)
            .is("deleted_at", null),
          tenantId,
          empresaId
        ),
        applyTenantEmpresa(
          supabase
            .schema("f")
            .from("documento_fiscal")
            .update({ nfse_status: "CANCELADA", deleted_at: nowIso, updated_at: nowIso })
            .eq("id", docId)
            .eq("operacao", "SAIDA")
            .eq("natureza", "SERVICO")
            .is("deleted_at", null),
          tenantId,
          empresaId
        ),
      ]);

      if (xmlRes.error) throw xmlRes.error;
      const docErr = docRes.error;
      if (docErr) throw docErr;

      router.replace("/faturamento/nfse");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao excluir NFS-e.");
    } finally {
      setDeleting(false);
    }
  };

  const headerRight = (
    <div className="flex items-center gap-2">
      <Link href="/faturamento/nfse" className="text-sm text-zinc-300 hover:text-zinc-100">
        Voltar
      </Link>
      {mode === "edit" && docId ? (
        <button
          type="button"
          onClick={() => void removeDoc()}
          disabled={!ready || saving || emitting || deleting || loading}
          className="rounded-md bg-rose-900/70 px-3 py-2 text-sm text-rose-100 hover:bg-rose-800 disabled:opacity-50"
        >
          {deleting ? "Excluindo..." : "Excluir"}
        </button>
      ) : null}
      <button
        type="button"
        onClick={() => void saveAll(String(status || "RASCUNHO").toUpperCase() === "EMITIDA" ? "EMITIDA" : "RASCUNHO")}
        disabled={!ready || saving || emitting || deleting || loading || readOnly}
        className="rounded-md bg-zinc-800 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-700 disabled:opacity-50"
      >
        {saving ? "Salvando..." : "Salvar"}
      </button>
      <button
        type="button"
        onClick={() => void emit()}
        disabled={!ready || saving || emitting || deleting || loading || readOnly}
        className="rounded-md bg-emerald-700 px-3 py-2 text-sm text-white hover:bg-emerald-600 disabled:opacity-50"
      >
        {emitting ? "Emitindo..." : "Emitir"}
      </button>
    </div>
  );

  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100">
            {mode === "new" ? "Nova NFS-e" : `NFS-e ${serie ? `${serie}-${numero}` : ""}`}
          </h1>
          <div className="mt-1 text-sm text-zinc-400">
            Status: <span className="text-zinc-200">{String(status || "—").toUpperCase()}</span>
            {mode === "edit" && docId ? <span className="ml-3 text-xs text-zinc-500">ID: {docId}</span> : null}
          </div>
          {mode === "edit" ? <div className="text-xs text-zinc-500">Emissão: {formatDateBR(emissaoDate)}</div> : null}
        </div>
        {headerRight}
      </div>

      {loading ? <div className="mt-4 text-sm text-zinc-400">Carregando...</div> : null}
      {error ? (
        <div className="mt-4 rounded-md border border-rose-900/60 bg-rose-950/30 px-4 py-3 text-sm text-rose-200">
          {error}
        </div>
      ) : null}
      {ok ? (
        <div className="mt-4 rounded-md border border-emerald-900/60 bg-emerald-950/30 px-4 py-3 text-sm text-emerald-200">
          {ok}
        </div>
      ) : null}

      <div className="mt-6 grid gap-4">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950">
          <div className="px-4 py-3 border-b border-zinc-800">
            <div className="text-sm font-medium text-zinc-100">Cabeçalho</div>
          </div>
          <div className="p-4 grid gap-3 md:grid-cols-4">
            <div>
              <label htmlFor="nfse-emissao" className="block text-xs font-medium text-zinc-400">
                Emissão
              </label>
              <input
                id="nfse-emissao"
                type="date"
                value={emissaoDate}
                disabled={readOnly}
                onChange={(e) => setEmissaoDate(e.target.value)}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
              />
            </div>
            <div>
              <label htmlFor="nfse-serie" className="block text-xs font-medium text-zinc-400">
                Série
              </label>
              <input
                id="nfse-serie"
                value={serie}
                disabled={readOnly}
                onChange={(e) => setSerie(e.target.value)}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
              />
            </div>
            <div>
              <label htmlFor="nfse-numero" className="block text-xs font-medium text-zinc-400">
                Número
              </label>
              <input
                id="nfse-numero"
                value={numero}
                disabled={readOnly}
                onChange={(e) => setNumero(e.target.value)}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
              />
            </div>
            <div>
              <label htmlFor="nfse-total" className="block text-xs font-medium text-zinc-400">
                Total (serviços)
              </label>
              <input
                id="nfse-total"
                value={formatMoneyBR(valorTotal)}
                disabled
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 opacity-70"
              />
            </div>
          </div>

          <div className="px-4 pb-4">
            <label className="block text-xs font-medium text-zinc-400">Cliente</label>
            <div className="mt-1 grid gap-2 md:grid-cols-2">
              <div className="relative">
                <input
                  value={clienteQ}
                  disabled={readOnly}
                  onChange={(e) => {
                    const v = e.target.value;
                    setClienteQ(v);
                    if (!v.trim()) {
                      setClienteId(null);
                      setClienteNome("");
                      setClienteResults([]);
                    }
                  }}
                  placeholder="Buscar cliente por nome ou ID (rascunho pode ficar vazio)"
                  className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
                />

                {!readOnly && clienteResults.length > 0 ? (
                  <div className="absolute z-20 mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 shadow-lg overflow-hidden">
                    {clienteResults.map((c) => (
                      <button
                        type="button"
                        key={c.id}
                        className="w-full text-left px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
                        onClick={() => {
                          setClienteId(c.id);
                          setClienteNome(c.nome);
                          setClienteQ(c.nome);
                          setClienteResults([]);
                        }}
                      >
                        <span className="font-medium">{c.nome}</span>
                        <span className="ml-2 text-xs text-zinc-500">ID {c.id}</span>
                      </button>
                    ))}
                  </div>
                ) : null}
              </div>

              <div className="text-sm text-zinc-400 flex items-center">
                Selecionado:{" "}
                <span className="ml-2 text-zinc-200">{clienteId ? `${clienteNome || "—"} (ID ${clienteId})` : "—"}</span>
              </div>
            </div>
          </div>

          <div className="border-t border-zinc-800 px-4 py-4">
            <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
              <OsVinculoField
                tenantId={tenantId}
                empresaId={empresaId}
                value={osSelection}
                onChange={(next) => {
                  setOsSelection(next);
                  setOk(null);
                }}
                disabled={!ready || loading || deleting || saving || emitting || savingOsLink}
                helperText="Opcional. Para OS em andamento, este vinculo faz o analitico considerar apenas o saldo a faturar."
              />

              {mode === "edit" && readOnly ? (
                <button
                  type="button"
                  onClick={() => void saveOsLink()}
                  disabled={!ready || loading || deleting || saving || emitting || savingOsLink}
                  className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900 disabled:opacity-50"
                >
                  {savingOsLink ? "Salvando OS..." : "Salvar OS"}
                </button>
              ) : null}
            </div>
          </div>
        </div>

        <NfseItensEditor servico={servico} onChange={setServico} readOnly={readOnly} />

        <NfseIssCard
          valorServicos={valorServicos}
          materialPercent={materialPercent}
          materialValor={materialValorClamped}
          aliquota={aliquotaIss}
          onAliquotaChange={setAliquotaIss}
          onMaterialPercentChange={onMaterialPercent}
          onMaterialValorChange={onMaterialValor}
          readOnly={readOnly}
        />

        {readOnly ? (
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-zinc-400">
            Documento emitido: edição bloqueada (MVP).
          </div>
        ) : null}
      </div>
    </div>
  );
}
