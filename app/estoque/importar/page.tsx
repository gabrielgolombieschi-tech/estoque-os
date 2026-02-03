"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatDecimalBR, formatMoneyBR, parseDecimalBR } from "@/lib/decimal";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";
import { useImportMotivos } from "./ImportMotivosProvider";
import MotivoCompraCombobox from "./MotivoCompraCombobox";
import { parseNfeXml, type ParsedItem, type ParsedNfe } from "@/lib/nfe/parseNfeXml";

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
  cnpj_norm?: string | null;
  finalidade_padrao?: ItemFinalidade | null;
  motivo_compra_padrao_id?: string | null;
  gerar_contas_pagar_auto?: boolean | null;
};

type ItemCodigoRow = {
  id: number;
  codigo_interno: string;
};

type OsLookupRow = {
  id: number;
  numero_os?: string | null;
  cliente_nome?: string | null;
  descricao_servico?: string | null;
  status?: string | null;
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

type UsuarioSolicitante = {
  id: string;
  nome: string;
  email: string;
};

type UsuariosSolicitantesApiResponse = { usuarios?: UsuarioSolicitante[]; error?: string };

type ImportItemPayload = {
  tenant_id: string;
  item_id: number | null;
  codigo_fornecedor: string;
  // Compat: o importador do banco (public.import_nf_entrada) espera "codigo" e "nome".
  // Mantemos também "codigo_fornecedor"/"descricao" porque o app usa esses nomes no client.
  codigo?: string;
  nome?: string;
  descricao: string;
  ncm: string | null;
  cfop?: string | null;
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

type NfEntradaResumoRow = {
  id: number;
  chave: string;
  numero: string | null;
  serie: string | null;
  emitente_nome: string | null;
  data_emissao: string | null;
  valor_total: number | string | null;
  criado_em: string | null;
  finalidade_contexto?: string | null;
  fornecedor_id?: number | null;
  motivo_compra_id?: string | null;
  solicitante_usuario_id?: string | null;
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

function normalizeCnpj(doc: string | null): string | null {
  if (!doc) return null;
  const onlyDigits = doc.replace(/\D/g, "");
  if (!onlyDigits) return null;
  return onlyDigits.length === 14 ? onlyDigits : null;
}

function toDateOnly(value: string | null | undefined): string | null {
  const v = (value ?? "").trim();
  if (!v) return null;
  // aceita YYYY-MM-DD ou ISO com horário
  if (/^\d{4}-\d{2}-\d{2}/.test(v)) return v.slice(0, 10);
  return null;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const v = String(iso);
  const d = new Date(v.includes("T") ? v : `${v}T00:00:00`);
  if (Number.isNaN(d.getTime())) return v;
  return d.toLocaleDateString("pt-BR");
}

export default function ImportarXmlPage() {
  const router = useRouter();
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

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

  // Fonte de verdade durante parsing (evita race/stale setState ao ler múltiplos XMLs)
  const fornecedorCnpjBaseRef = useRef<string | null>(null);
  // Evita duplicidade por closure stale durante addJobFromRaw
  const chavesAddedRef = useRef<Set<string>>(new Set());

  const [fornecedorGerarContasAuto, setFornecedorGerarContasAuto] = useState(false);

  const [finalidadeLote, setFinalidadeLote] = useState<ItemFinalidade | "">("");

  const {
    motivos,
    loading: motivosLoading,
    error: motivosError,
    setFavorito: setMotivoFavorito,
  } = useImportMotivos();
  const [motivoCompraId, setMotivoCompraId] = useState<string>("");

  const [solicitanteUsuarioId, setSolicitanteUsuarioId] = useState<string>("");
  const [usuariosSolicitantes, setUsuariosSolicitantes] = useState<UsuarioSolicitante[]>([]);
  const [usuariosSolicitantesLoading, setUsuariosSolicitantesLoading] = useState(false);
  const [usuariosSolicitantesError, setUsuariosSolicitantesError] = useState<string | null>(null);

  const [defaultsToast, setDefaultsToast] = useState<{ kind: "saved" | "error" | "warn"; message: string } | null>(
    null
  );
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const fornecedorIdRef = useRef<number | null>(null);
  const finalidadeRef = useRef<ItemFinalidade | "">("");
  const motivoCompraIdRef = useRef<string>("");
  useEffect(() => {
    fornecedorIdRef.current = fornecedorId;
    finalidadeRef.current = finalidadeLote;
    motivoCompraIdRef.current = motivoCompraId;
  }, [finalidadeLote, fornecedorId, motivoCompraId]);

  const defaultsDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingDefaultsRef = useRef<{
    fornecedorId: number;
    finalidade: ItemFinalidade | null;
    motivoCompraId: string | null;
  } | null>(null);

  const clearToastLater = useCallback((ms = 2200) => {
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    toastTimerRef.current = setTimeout(() => setDefaultsToast(null), ms);
  }, []);

  const normalizeFinalidade = (v: ItemFinalidade | "" | null | undefined): ItemFinalidade | null => {
    if (!v) return null;
    return v as ItemFinalidade;
  };

  const normalizeMotivoId = (v: string | null | undefined): string | null => {
    const s = String(v ?? "").trim();
    return s ? s : null;
  };

  const saveFornecedorImportDefaultsNow = useCallback(
    async (payload: { fornecedorId: number; finalidade: ItemFinalidade | null; motivoCompraId: string | null }) => {
      try {
        const { error } = await supabase.rpc("set_fornecedor_import_defaults", {
          p_fornecedor_id: payload.fornecedorId,
          p_finalidade: payload.finalidade,
          p_motivo_compra_id: payload.motivoCompraId,
        });

        if (error) {
          setDefaultsToast({ kind: "error", message: "Erro ao salvar padrão do fornecedor." });
          clearToastLater();
          return;
        }

        setDefaultsToast({ kind: "saved", message: "Padrão do fornecedor salvo." });
        clearToastLater();
      } catch {
        setDefaultsToast({ kind: "error", message: "Erro ao salvar padrão do fornecedor." });
        clearToastLater();
      }
    },
    [clearToastLater, supabase]
  );

  const scheduleSaveFornecedorDefaults = useCallback(
    (next: { fornecedorId: number; finalidade: ItemFinalidade | null; motivoCompraId: string | null }) => {
      pendingDefaultsRef.current = next;
      if (defaultsDebounceRef.current) clearTimeout(defaultsDebounceRef.current);
      defaultsDebounceRef.current = setTimeout(() => {
        const p = pendingDefaultsRef.current;
        pendingDefaultsRef.current = null;
        if (!p) return;
        void saveFornecedorImportDefaultsNow(p);
      }, 650);
    },
    [saveFornecedorImportDefaultsNow]
  );

  const flushFornecedorDefaults = useCallback(
    (fornecedorIdToFlush?: number | null) => {
      const fid = fornecedorIdToFlush ?? fornecedorIdRef.current;
      if (!fid) return;

      if (defaultsDebounceRef.current) {
        clearTimeout(defaultsDebounceRef.current);
        defaultsDebounceRef.current = null;
      }

      const pending = pendingDefaultsRef.current;
      pendingDefaultsRef.current = null;

      const payload = pending?.fornecedorId === fid
        ? pending
        : {
            fornecedorId: fid,
            finalidade: normalizeFinalidade(finalidadeRef.current),
            motivoCompraId: normalizeMotivoId(motivoCompraIdRef.current),
          };

      void saveFornecedorImportDefaultsNow(payload);
    },
    [saveFornecedorImportDefaultsNow]
  );

  // Vinculo opcional de OS (somente quando finalidade do lote = materia_prima)
  const [osNumero, setOsNumero] = useState("");
  const [osId, setOsId] = useState<number | null>(null);
  const [osLabel, setOsLabel] = useState<string | null>(null);
  const [osLoading, setOsLoading] = useState(false);
  const [osError, setOsError] = useState<string | null>(null);

  const [showOsLookup, setShowOsLookup] = useState(false);
  const [osLookupTerm, setOsLookupTerm] = useState("");
  const [osLookupRows, setOsLookupRows] = useState<OsLookupRow[]>([]);
  const [osLookupLoading, setOsLookupLoading] = useState(false);
  const [osLookupError, setOsLookupError] = useState<string | null>(null);
  const osLookupDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const osResolveReqIdRef = useRef(0);

  const [loteMissing, setLoteMissing] = useState<string[]>([]);

  const te = useTenantEmpresa();
  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO";
  const { has, loading: permissionsLoading, ready } = usePermissions();

  const [recentNfs, setRecentNfs] = useState<NfEntradaResumoRow[]>([]);
  const [recentNfsLoading, setRecentNfsLoading] = useState(false);
  const [recentNfsError, setRecentNfsError] = useState<string | null>(null);
  const [openingNfEntradaId, setOpeningNfEntradaId] = useState<number | null>(null);
  const [recentReloadTick, setRecentReloadTick] = useState(0);

  const [recentFilterMonth, setRecentFilterMonth] = useState<string>(() => String(new Date().getMonth() + 1));
  const [recentFilterYear, setRecentFilterYear] = useState<string>(() => String(new Date().getFullYear()));

  const canImport = has("xml_import.execute");
  const canCreateFornecedor = has("cad_fornecedores.write");
  const canCreateItem = has("cad_itens.write");
  const canAccessPage = Boolean(canImport || canCreateFornecedor || canCreateItem || isFinanceiroEmpresaRole);

  const osEnabled = finalidadeLote === "materia_prima";

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!tenantId || !empresaId) {
        if (!active) return;
        setRecentNfs([]);
        setRecentNfsError(null);
        setRecentNfsLoading(false);
        return;
      }

      setRecentNfsLoading(true);
      setRecentNfsError(null);

      try {
        const y = Number(recentFilterYear);
        const m = Number(recentFilterMonth);
        const hasMonth = Number.isFinite(y) && Number.isFinite(m) && y > 2000 && m >= 1 && m <= 12;
        const start = hasMonth ? new Date(Date.UTC(y, m - 1, 1)).toISOString().slice(0, 10) : null;
        const end = hasMonth ? new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10) : null;

        let qb = supabase
          .schema("public")
          .from("nf_entrada")
          .select("id,chave,numero,serie,emitente_nome,data_emissao,valor_total,criado_em,finalidade_contexto", {
            count: "exact",
          })
          .eq("empresa_id", empresaId)
          .eq("finalidade_contexto", "materia_prima")
          .not("chave", "is", null)
          .order("criado_em", { ascending: false })
          .order("id", { ascending: false });

        if (start && end) {
          qb = qb.gte("data_emissao", start).lt("data_emissao", end);
        }

        qb = applyTenantEmpresa(qb, tenantId, empresaId);

        const pageSize = 1000;
        let from = 0;
        let rowsAll: NfEntradaResumoRow[] = [];

        while (true) {
          const { data, error } = await qb.range(from, from + pageSize - 1).returns<NfEntradaResumoRow[]>();
          if (error) throw error;
          if (!active) return;

          const chunkRows = (data ?? [])
            .map((r) => ({
              id: Number(r.id),
              chave: String(r.chave ?? ""),
              numero: r.numero ?? null,
              serie: r.serie ?? null,
              emitente_nome: r.emitente_nome ?? null,
              data_emissao: r.data_emissao ?? null,
              valor_total: r.valor_total ?? null,
              criado_em: r.criado_em ?? null,
            }))
            .filter((r) => Number.isFinite(r.id) && r.id > 0 && r.chave);

          rowsAll = rowsAll.concat(chunkRows);
          if (!data || chunkRows.length < pageSize) break;
          from += pageSize;
        }

        setRecentNfs(rowsAll);
      } catch (e: unknown) {
        if (!active) return;
        setRecentNfs([]);
        setRecentNfsError(getErrorMessage(e, "Erro ao carregar notas importadas."));
      } finally {
        if (active) setRecentNfsLoading(false);
      }
    };

    void run();
    return () => {
      active = false;
    };
  }, [empresaId, importOk, recentFilterMonth, recentFilterYear, recentReloadTick, tenantId]);

  const abrirNotaImportada = useCallback(
    async (row: NfEntradaResumoRow) => {
      if (!tenantId || !empresaId) return;
      if (!row?.id) return;

      setOpeningNfEntradaId(row.id);
      setRecentNfsError(null);

      try {
        const { data: foundId, error: findErr } = await supabase.schema("f").rpc("fn_find_documento_fiscal_from_import", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_nf_entrada_id: row.id,
          p_chave_acesso: row.chave ?? null,
        });

        let documentoFiscalId = foundId ? String(foundId) : null;

        // Fallback: garante DF a partir da NF de entrada (caso o importador não tenha criado).
        if (!documentoFiscalId) {
          const { data: ensuredId, error: ensureErr } = await supabase
            .schema("f")
            .rpc("fn_ensure_documento_fiscal_from_nf_entrada", { p_nf_entrada_id: row.id });

          if (ensureErr || !ensuredId) throw ensureErr ?? findErr ?? new Error("Não foi possível localizar o documento fiscal.");
          documentoFiscalId = String(ensuredId);
        }

        // Best-effort: garantir impostos gravados para exibição/apuração.
        try {
          await supabase
            .schema("f")
            .rpc("nfe_gravar_impostos_do_documento", { p_documento_fiscal_id: documentoFiscalId });
        } catch {
          // ignore
        }

        router.push(`/estoque/importar/${documentoFiscalId}`);
      } catch (e: unknown) {
        setRecentNfsError(getErrorMessage(e, "Erro ao abrir a nota importada."));
      } finally {
        setOpeningNfEntradaId(null);
      }
    },
    [empresaId, router, tenantId]
  );

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!tenantId || !empresaId) {
        setUsuariosSolicitantes([]);
        setUsuariosSolicitantesError(null);
        setUsuariosSolicitantesLoading(false);
        setSolicitanteUsuarioId("");
        return;
      }

      setUsuariosSolicitantesLoading(true);
      setUsuariosSolicitantesError(null);

      try {
        const { data: sess } = await supabase.auth.getSession();
        const token = sess.session?.access_token ?? null;
        if (!token) throw new Error("Sessao expirada. Faca login novamente.");

        const res = await fetch(`/api/estoque/usuarios-solicitantes?tenantId=${tenantId}&empresaId=${empresaId}`, {
          headers: { authorization: `Bearer ${token}` },
        });

        const json = (await res.json().catch(() => null)) as UsuariosSolicitantesApiResponse | null;
        if (!active) return;

        if (!res.ok) {
          const msg = typeof json?.error === "string" ? json.error : "Erro ao carregar usuarios.";
          setUsuariosSolicitantes([]);
          setUsuariosSolicitantesError(msg);
          setUsuariosSolicitantesLoading(false);
          return;
        }

        const data = Array.isArray(json?.usuarios) ? json!.usuarios! : [];
        const next = (data ?? [])
          .map((r) => ({ id: String(r.id ?? ""), nome: String(r.nome ?? ""), email: String(r.email ?? "") }))
          .filter((r) => r.id && r.nome && r.email);

        setUsuariosSolicitantes(next);
        setUsuariosSolicitantesLoading(false);
        setSolicitanteUsuarioId((prev) => (prev && !next.some((u) => u.id === prev) ? "" : prev));
      } catch (e: unknown) {
        if (!active) return;
        setUsuariosSolicitantes([]);
        setUsuariosSolicitantesError(getErrorMessage(e, "Erro ao carregar usuarios."));
        setUsuariosSolicitantesLoading(false);
      }
    };

    void run();
    return () => {
      active = false;
    };
  }, [empresaId, supabase, tenantId]);

  const resolveOsByNumero = useCallback(
    async (numero: string) => {
      const reqId = ++osResolveReqIdRef.current;
      const normalized = numero.trim();
      if (!normalized) {
        setOsId(null);
        setOsLabel(null);
        setOsError(null);
        setOsLoading(false);
        return;
      }

      setOsLoading(true);
      setOsError(null);

      if (!tenantId || !empresaId) {
        if (reqId !== osResolveReqIdRef.current) return;
        setOsId(null);
        setOsLabel(null);
        setOsError("Tenant ou empresa nao carregados.");
        setOsLoading(false);
        return;
      }

      const { data, error } = await applyTenantEmpresa(
        supabase.schema("public").from("ordens_servico").select("id,numero_os,cliente_nome,descricao_servico,status"),
        tenantId,
        empresaId
      )
        .eq("numero_os", normalized)
        .maybeSingle();

      if (reqId !== osResolveReqIdRef.current) return;

      if (error) {
        setOsId(null);
        setOsLabel(null);
        setOsError("Erro ao buscar OS.");
        setOsLoading(false);
        return;
      }

      if (!data) {
        setOsId(null);
        setOsLabel(null);
        setOsError("OS nao encontrada.");
        setOsLoading(false);
        return;
      }

      const row = data as OsLookupRow;
      setOsId(Number(row.id));
      const numeroDb = row.numero_os ?? String(row.id);
      const cliente = row.cliente_nome ?? "-";
      setOsLabel(`OS ${numeroDb} - ${cliente}`);
      setOsError(null);
      setOsLoading(false);
    },
    [supabase, tenantId, empresaId]
  );

  const loadOsLookup = useCallback(
    async (term: string) => {
      setOsLookupLoading(true);
      setOsLookupError(null);

      const trimmed = term.trim();
      if (!trimmed) {
        setOsLookupRows([]);
        setOsLookupLoading(false);
        return;
      }

      if (!tenantId || !empresaId) {
        setOsLookupRows([]);
        setOsLookupError("Tenant ou empresa nao carregados.");
        setOsLookupLoading(false);
        return;
      }

      let query = applyTenantEmpresa(
        supabase.schema("public").from("ordens_servico").select("id,numero_os,cliente_nome,descricao_servico,status"),
        tenantId,
        empresaId
      )
        .order("id", { ascending: false })
        .limit(50);

      const likeTerm = `%${trimmed}%`;
      query = query.or(`numero_os.ilike.${likeTerm},cliente_nome.ilike.${likeTerm}`);

      const { data, error } = await query;
      if (error) {
        setOsLookupRows([]);
        setOsLookupError("Erro ao buscar OS.");
        setOsLookupLoading(false);
        return;
      }

      setOsLookupRows((data ?? []) as OsLookupRow[]);
      setOsLookupLoading(false);
    },
    [supabase, tenantId, empresaId]
  );

  const openOsLookup = useCallback(() => {
    setShowOsLookup(true);
    setOsLookupTerm("");
    setOsLookupRows([]);
    setOsLookupError(null);
  }, []);

  const closeOsLookup = useCallback(() => {
    setShowOsLookup(false);
    setOsLookupRows([]);
    setOsLookupError(null);
  }, []);

  useEffect(() => {
    if (osEnabled) return;
    setOsNumero("");
    setOsId(null);
    setOsLabel(null);
    setOsLoading(false);
    setOsError(null);
    setShowOsLookup(false);
    setOsLookupTerm("");
    setOsLookupRows([]);
    setOsLookupError(null);
    setOsLookupLoading(false);
  }, [osEnabled]);

  useEffect(() => {
    if (!osEnabled) return;
    const trimmed = osNumero.trim();
    if (!trimmed) {
      setOsId(null);
      setOsLabel(null);
      setOsLoading(false);
      setOsError(null);
      return;
    }

    const t = setTimeout(() => {
      void resolveOsByNumero(trimmed);
    }, 400);

    return () => clearTimeout(t);
  }, [osNumero, osEnabled, resolveOsByNumero]);

  function parseXml(raw: string): { nfe: ParsedNfe; itens: ParsedItem[] } {
    return parseNfeXml(raw);
  }

  function applyFornecedorFinanceDefaults(flag: boolean) {
    setFornecedorGerarContasAuto(Boolean(flag));
  }

  async function checkFornecedor(
    params: { documento: string | null; nome: string | null },
    opts?: { allowCreate?: boolean }
  ) {
    const allowCreate = opts?.allowCreate ?? true;
    // Persist last supplier choices before switching.
    if (fornecedorIdRef.current) flushFornecedorDefaults(fornecedorIdRef.current);

    setFornecedorId(null);
    setFornecedorNome(null);
    applyFornecedorFinanceDefaults(false);

    const cnpjNormalizado = normalizeCnpj(params.documento);
    if (!cnpjNormalizado) return;

    if (!tenantId || !empresaId) {
      setImportErr("Tenant ou empresa nao carregados.");
      return;
    }

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("public")
        .from("fornecedores")
        .select("id,nome,cnpj_norm,finalidade_padrao,motivo_compra_padrao_id,gerar_contas_pagar_auto"),
      tenantId,
      empresaId
    )
      .or(`cnpj_norm.eq.${cnpjNormalizado},documento_norm.eq.${cnpjNormalizado}`)
      .order("id", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (error) {
      setImportErr(error.message);
      return;
    }

    const fornecedor = (data ?? null) as FornecedorRow | null;
    if (fornecedor?.id) {
      setFornecedorId(fornecedor.id);
      setFornecedorNome(fornecedor.nome ?? null);

      applyFornecedorFinanceDefaults(Boolean(fornecedor.gerar_contas_pagar_auto));

      // Auto-preenche defaults do fornecedor
      if (fornecedor.finalidade_padrao) {
        setFinalidadeLote(fornecedor.finalidade_padrao);
      }
      setMotivoCompraId(String(fornecedor.motivo_compra_padrao_id ?? ""));

      return;
    }

    if (!allowCreate) return;

    // Não encontrado: cria automaticamente (requisito)
    if (!canCreateFornecedor) {
      setImportErr("Fornecedor nao encontrado e voce nao tem permissao para cadastrar automaticamente.");
      return;
    }

    const createdId = await criarFornecedor(
      cnpjNormalizado,
      params.nome ?? "Fornecedor NF",
      finalidadeLote ? (finalidadeLote as ItemFinalidade) : null
    );

    if (createdId && finalidadeLote) {
      await atualizarFinalidadePadraoFornecedor(createdId, finalidadeLote as ItemFinalidade);
    }
  }

  async function criarFornecedor(cnpj: string, nome: string, finalidadePadrao?: ItemFinalidade | null) {
    setImportErr(null);

    if (!canCreateFornecedor) {
      setImportErr("Sem permissao para cadastrar fornecedor.");
      return null;
    }

    const documento = normalizeCnpj(cnpj);
    if (!documento) {
      setImportErr("CNPJ do fornecedor invalido.");
      return null;
    }

    if (!tenantId || !empresaId) {
      setImportErr("Tenant ou empresa nao carregados.");
      return null;
    }

    // Regra: fornecedor nasce com finalidade_padrao = finalidade do lote quando houver (senão, null)
    const finalidadeParaSalvar = (finalidadePadrao ?? null) ?? null;

    const nomeUpper = String(nome ?? "")
      .replace(/\s+/g, " ")
      .trim()
      .toUpperCase();

    const payload: Record<string, unknown> = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      nome: nomeUpper || "FORNECEDOR NF",
      cnpj: documento,
      documento,
      ativo: true,
      finalidade_padrao: finalidadeParaSalvar,
      motivo_compra_padrao_id: normalizeMotivoId(motivoCompraIdRef.current),
    };

    const { data, error } = await supabase
      .schema("public")
      .from("fornecedores")
      .insert(payload)
      .select("id,nome,cnpj_norm,finalidade_padrao,motivo_compra_padrao_id,gerar_contas_pagar_auto")
      .single();

    if (error) {
      const err = (error && typeof error === "object" ? (error as DbError) : null);

      // se já existe, tenta update (mantém robusto)
      if (err?.code === "23505") {
        const { data: existing, error: existingErr } = await applyTenantEmpresa(
          supabase.schema("public").from("fornecedores").select("id"),
          tenantId,
          empresaId
        )
          .or(`cnpj_norm.eq.${documento},documento_norm.eq.${documento}`)
          .order("id", { ascending: true })
          .limit(1)
          .maybeSingle();

        if (existingErr) {
          setImportErr(existingErr.message);
          return null;
        }

        const existingId = existing?.id ?? null;
        if (!existingId) {
          setImportErr("Fornecedor ja cadastrado para este documento.");
          return null;
        }

        const { data: updated, error: updateErr } = await applyTenantEmpresa(
          supabase
            .schema("public")
            .from("fornecedores")
            .update(payload)
            .select("id,nome,cnpj_norm,finalidade_padrao,motivo_compra_padrao_id,gerar_contas_pagar_auto"),
          tenantId,
          empresaId
        )
          .eq("id", existingId)
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
        applyFornecedorFinanceDefaults(Boolean(updatedRow.gerar_contas_pagar_auto));

        if (updatedRow.finalidade_padrao) setFinalidadeLote(updatedRow.finalidade_padrao);
        setMotivoCompraId(String(updatedRow.motivo_compra_padrao_id ?? ""));
        return updatedRow.id;
      }

      setImportErr(error.message);
      return null;
    }

    const created = (data ?? null) as FornecedorRow | null;
    if (!created?.id) return null;

    setFornecedorId(created.id);
    setFornecedorNome(created.nome ?? null);

    applyFornecedorFinanceDefaults(Boolean(created.gerar_contas_pagar_auto));

    // garante que o padrão fica setado
    if (created.finalidade_padrao) setFinalidadeLote(created.finalidade_padrao);
    setMotivoCompraId(String(created.motivo_compra_padrao_id ?? ""));

    // Persist defaults for the newly created supplier.
    scheduleSaveFornecedorDefaults({
      fornecedorId: created.id,
      finalidade: normalizeFinalidade(created.finalidade_padrao ?? finalidadeRef.current),
      motivoCompraId: normalizeMotivoId(created.motivo_compra_padrao_id ?? motivoCompraIdRef.current),
    });

    return created.id;
  }

  async function atualizarFinalidadePadraoFornecedor(fornecedorIdToUpdate: number, finalidade: ItemFinalidade) {
    if (!tenantId || !empresaId) return;
    const { error } = await applyTenantEmpresa(
      supabase.schema("public").from("fornecedores").update({ finalidade_padrao: finalidade }),
      tenantId,
      empresaId
    ).eq("id", fornecedorIdToUpdate);

    if (error) setImportErr(error.message);
  }

  // If the currently selected motivo becomes invalid for XML_PRODUTO (e.g. it was SERVICO), clear and warn.
  useEffect(() => {
    if (motivosLoading) return;
    if (!motivoCompraId) return;
    const ok = motivos.some((m) => m.id === motivoCompraId);
    if (ok) return;
    setMotivoCompraId("");
    setDefaultsToast({
      kind: "warn",
      message: "Motivo padrao do fornecedor nao se aplica a XML de produtos (SERVICO). Selecione outro.",
    });
    clearToastLater(3500);
  }, [clearToastLater, motivoCompraId, motivos, motivosLoading]);

  const carregarItensPorCodigo = useCallback(
    async (codigos: string[], tenantIdLocal: string, empresaIdLocal: string) => {
      if (codigos.length === 0) return new Map<string, number>();

      const { data, error } = await applyTenantEmpresa(
        supabase.schema("public").from("itens").select("id,codigo_interno"),
        tenantIdLocal,
        empresaIdLocal
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
        .schema("public")
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

  async function upsertFiscalItem(
    itemId: number,
    fiscal: Partial<FiscalPerfil>,
    tenantIdLocal: string,
    empresaIdLocal: string
  ) {
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

    const { error } = await supabase
      .schema("public")
      .from("fiscal_itens")
      .upsert(payload, { onConflict: "tenant_id,empresa_id,item_id" });

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
    const nomeUpper = String(nomeFinal).trim().toUpperCase();
    const dataCompra = dataEmissao || new Date().toISOString();
    const margem = 52;

    const valorUnitRaw = Number(it.valorUnit ?? 0);
    const valorUnit = Number.isFinite(valorUnitRaw) ? valorUnitRaw : 0;

    const aliq = (v?: number | null) => (Number.isFinite(v as number) ? Number(v) : null);

    if (!tenantId || !empresaId) {
      setImportErr("Tenant ou empresa nao carregados.");
      return null;
    }

    const { data, error } = await supabase
      .schema("public")
      .from("itens")
      .insert({
        tenant_id: tenantId,
        empresa_id: empresaId,
        codigo_interno: it.codigo,
        nome: nomeUpper,
        tipo: "produto",
        controla_estoque: true,
        unidade_medida: "UN",
        custo_ultima_compra: valorUnit,
        custo_medio: valorUnit,
        preco_unitario: valorUnit,
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
    const cnpj = normalizeCnpj(cnpjRaw);

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
        supabase.schema("public").from("nf_entrada").select("id", { count: "exact" }),
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
    const baseRef = fornecedorCnpjBaseRef.current;
    let setAsBase = false;
    if (!baseRef && cnpj && status !== "erro") {
      fornecedorCnpjBaseRef.current = cnpj;
      setFornecedorCnpjBase(cnpj); // state apenas para UI
      setAsBase = true;
    } else if (baseRef && cnpj && baseRef !== cnpj) {
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

    const chaveKey = chave ? String(chave) : null;
    const alreadyExists = Boolean(chaveKey && chavesAddedRef.current.has(chaveKey));
    if (chaveKey && !alreadyExists) chavesAddedRef.current.add(chaveKey);

    const didAdd = !alreadyExists;

    setJobs((prev) => {
      if (alreadyExists) return prev;
      if (chaveKey && prev.some((j) => j.nfeInfo?.chave === chaveKey)) return prev;
      return [...prev, job];
    });

    if (selected && didAdd) setSelectedJobId(job.id);

    if (didAdd && setAsBase && status !== "erro") {
      await checkFornecedor(
        { documento: parsed.nfe.cnpjEmitente, nome: parsed.nfe.emitente },
        { allowCreate: status === "ok" && selected }
      );
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

      fornecedorCnpjBaseRef.current = null;
      chavesAddedRef.current = new Set();

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

    fornecedorCnpjBaseRef.current = null;
    chavesAddedRef.current = new Set();
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
        fornecedorCnpjBaseRef.current ??
        fornecedorCnpjBase ??
        normalizeCnpj(jobsToUse.find((j) => j.nfeInfo?.cnpjEmitente)?.nfeInfo?.cnpjEmitente ?? null);

      let fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;

        if (!fornecedorFinal && baseCnpj) {
          const { data: found, error: findErr } = await applyTenantEmpresa(
            supabase.schema("public").from("fornecedores").select("id"),
            tenantId,
            empresaId
          )
            .or(`cnpj_norm.eq.${baseCnpj},documento_norm.eq.${baseCnpj}`)
            .order("id", { ascending: true })
            .limit(1)
            .maybeSingle();

        if (findErr) throw findErr;
        fornecedorFinal = found?.id ?? null;
      }

      if (!fornecedorFinal) {
        throw new Error("Fornecedor nao cadastrado. Cadastre o fornecedor antes de cadastrar itens.");
      }

      // Recarrega config do fornecedor (fonte da verdade)
      let gerarContasAuto = false;
      {
        const { data: fornecedorCfg, error: fornecedorCfgErr } = await applyTenantEmpresa(
          supabase.schema("public").from("fornecedores").select("nome,gerar_contas_pagar_auto"),
          tenantId,
          empresaId
        )
          .eq("id", fornecedorFinal)
          .maybeSingle();

        if (fornecedorCfgErr) throw fornecedorCfgErr;

        gerarContasAuto = Boolean(fornecedorCfg?.gerar_contas_pagar_auto);
        setFornecedorGerarContasAuto(gerarContasAuto);
        if (fornecedorCfg?.nome) setFornecedorNome(String(fornecedorCfg.nome));
      }

      // Sempre persiste finalidade padrão do fornecedor (comportamento obrigatório)
      // Persist supplier defaults (finalidade + motivo) before proceeding.
      flushFornecedorDefaults(fornecedorFinal);

      // agora itens
      const todosItens = jobsToUse.flatMap((j) => j.itens);
      const codigos = Array.from(new Set(todosItens.map((i) => i.codigo)));

      const map = await carregarItensPorCodigo(codigos, tenantId, empresaId);

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

      // Atualiza imediatamente os faltantes do lote para liberar a importacao sem precisar recarregar a tela.
      // (o efeito que recalcula loteMissing depende de selectedOkJobs, que pode não mudar após o cadastro)
      const nextMissing = codigos.filter((c) => !map.has(c));
      setLoteMissing(nextMissing);

      setFornecedorIdBase(fornecedorFinal ?? null);
      setImportOk("Itens cadastrados para os XMLs selecionados.");
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

      // Remove o item da lista de faltantes para liberar importacao imediatamente.
      setLoteMissing((prev) => (prev.length === 0 ? prev : prev.filter((c) => c !== it.codigo)));
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
      if (!solicitanteUsuarioId) throw new Error("Selecione o solicitante (usuario) antes de importar.");
      if (!finalidadeLote) throw new Error("Selecione a finalidade antes de importar.");

      if (!motivosLoading && motivos.length === 0) {
        throw new Error("Nao existe nenhum motivo/classificacao ativo. Contate o admin.");
      }

      const motivo = motivos.find((m) => m.id === motivoCompraId) ?? null;
      const motivoCodigo = String(motivo?.codigo ?? "")
        .trim()
        .toUpperCase();
      if (!motivoCompraId || !motivo || !motivoCodigo || motivoCodigo === "NAO_CLASSIFICADO") {
        throw new Error("Selecione uma classificacao/motivo valido (nao pode ser NAO_CLASSIFICADO).");
      }

      // OS opcional, mas se o usuario preencheu, precisa ser valida.
      if (finalidadeLote === "materia_prima") {
        if (osLoading) throw new Error("Aguarde a validacao da OS.");
        if (osNumero.trim() !== "" && osId === null) throw new Error("OS invalida. Limpe o campo ou selecione uma OS valida.");
      }

      const jobsToImport = jobs.filter((j) => j.selected && j.status === "ok");
      if (jobsToImport.length === 0) throw new Error("Nenhum XML selecionado para importar.");

      if (!tenantId || !empresaId) throw new Error("Tenant ou empresa nao carregados.");

      // regra: não importa se tiver itens faltando
      if (loteMissing.length > 0) throw new Error(`Itens nao cadastrados: ${loteMissing.join(", ")}`);

      // Best-effort: if fornecedor already resolved in UI, persist defaults (doesn't block import)
      const fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;
      let gerarContasAuto = fornecedorGerarContasAuto;
      if (fornecedorFinal) {
        try {
          await atualizarFinalidadePadraoFornecedor(fornecedorFinal, finalidadeLote as ItemFinalidade);
        } catch {
          // ignore
        }

        const { data: fornecedorCfg, error: fornecedorCfgErr } = await applyTenantEmpresa(
          supabase.schema("public").from("fornecedores").select("nome,gerar_contas_pagar_auto"),
          tenantId,
          empresaId
        )
          .eq("id", fornecedorFinal)
          .maybeSingle();

        if (fornecedorCfgErr) throw fornecedorCfgErr;

        gerarContasAuto = Boolean(fornecedorCfg?.gerar_contas_pagar_auto);
        setFornecedorGerarContasAuto(gerarContasAuto);
        if (fornecedorCfg?.nome) setFornecedorNome(String(fornecedorCfg.nome));
      }

      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      const userEmail = sess.session?.user?.email ?? null;
      if (!token) throw new Error("Sessao expirada. Faca login novamente.");

      const callImportApi = async (job: ImportJob, payload: { nfJson: unknown; itensJson: unknown; gerar: boolean; parcelas: unknown }) => {
        const info = job.nfeInfo;
        const res = await fetch("/api/estoque/importar-xml", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            tenantId,
            empresaId,
            finalidade: finalidadeLote,
            osId: finalidadeLote === "materia_prima" ? osId : null,
            motivoCompraId,
            solicitanteUsuarioId: solicitanteUsuarioId,
            fornecedorCnpj: info?.cnpjEmitente ?? null,
            fornecedorNome: info?.emitente ?? null,
            nfJson: payload.nfJson,
            itensJson: payload.itensJson,
            xmlRaw: job.xmlText,
            gerarContasPagar: payload.gerar,
            parcelasJson: payload.gerar ? payload.parcelas : null,
          }),
        });

        const jsonUnknown: unknown = await res.json().catch(() => null);
        const jsonObj =
          jsonUnknown && typeof jsonUnknown === "object" ? (jsonUnknown as Record<string, unknown>) : null;
        if (!res.ok) {
          const msg = typeof jsonObj?.error === "string" ? String(jsonObj.error) : "Erro ao importar.";
          const err = new Error(msg) as Error & { status?: number };
          err.status = res.status;
          throw err;
        }

        return {
          status: typeof jsonObj?.status === "string" ? jsonObj.status : undefined,
          message: typeof jsonObj?.message === "string" ? jsonObj.message : undefined,
          nf_entrada_id:
            typeof jsonObj?.nf_entrada_id === "number"
              ? jsonObj.nf_entrada_id
              : jsonObj?.nf_entrada_id
                ? Number(jsonObj.nf_entrada_id) || null
                : null,
        };
      };

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
            supabase.schema("public").from("nf_entrada").select("id", { count: "exact" }),
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
          const map = await carregarItensPorCodigo(codes, tenantId, empresaId);

          const missingCodes = job.itens.filter((it) => !map.get(it.codigo)).map((it) => it.codigo);
          if (missingCodes.length > 0) {
            throw new Error(`Itens nao cadastrados: ${missingCodes.join(", ")}`);
          }

          const itemIds = Array.from(map.values());
          const fiscalMap = await carregarFiscalPorItens(itemIds, tenantId, empresaId);

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
              codigo: it.codigo,
              nome: it.overrideNome ?? it.nome,
              codigo_fornecedor: it.codigo,
              descricao: it.overrideNome ?? it.nome,
              ncm: it.ncm ?? null,
              cfop: it.cfop ?? null,
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

          const shouldGenerateFinance = Boolean(gerarContasAuto);
          const parcelasFromXml = info.parcelas ?? [];
          const parcelasJson = shouldGenerateFinance && parcelasFromXml.length > 0 ? parcelasFromXml : null;

          let importRes: { status?: string; message?: string; nf_entrada_id?: number | null };
          try {
            importRes = await callImportApi(job, {
              nfJson,
              itensJson: itensPayload,
              gerar: shouldGenerateFinance,
              parcelas: parcelasJson,
            });
          } catch (e: unknown) {
            if (!shouldGenerateFinance) throw e;

            const msg = getErrorMessage(e, "Erro ao gerar contas a pagar.");
            const msgLower = msg.toLowerCase();
            const status =
              typeof e === "object" && e !== null && "status" in e
                ? (() => {
                    const raw = (e as { status?: unknown }).status;
                    return typeof raw === "number" ? raw : raw ? Number(raw) : null;
                  })()
                : null;

            // Don't retry on 422 (validation) — user must fix input.
            if (status === 422) throw e;

            const looksFinance =
              msgLower.includes("finance") ||
              msgLower.includes("parcel") ||
              msgLower.includes("soma das parcelas") ||
              msgLower.includes("titulo") ||
              msgLower.includes("aprovacao") ||
              msgLower.includes("contas a pagar") ||
              msgLower.includes("motivo_compra");

            if (!looksFinance) throw e;

            // Retry: import NF without finance generation.
            importRes = await callImportApi(job, {
              nfJson,
              itensJson: itensPayload,
              gerar: false,
              parcelas: null,
            });

            results.push(`${job.fileName}: NF importada, mas falhou ao gerar contas a pagar: ${msg}`);
          }

          const status = String(importRes?.status ?? "ok");
          const message = importRes?.message ? String(importRes.message) : null;

          if (status === "ja_importada") {
            setJobs((prev) =>
              prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: message ?? "NF ja importada" } : j))
            );
            results.push(`${job.fileName}: NF ja importada (nada foi duplicado).`);
          } else {
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: undefined } : j)));
            if (shouldGenerateFinance && parcelasFromXml.length === 0) {
              results.push(`${job.fileName}: importado com sucesso. XML sem duplicatas; gerado lançamento à vista.`);
            } else {
              results.push(`${job.fileName}: importado com sucesso.`);
            }
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
      if (!tenantId || !empresaId) {
        setImportErr("Tenant ou empresa nao carregados.");
        return;
      }
      try {
        const codes = Array.from(new Set(selectedJob.itens.map((i) => i.codigo)));
        const map = await carregarItensPorCodigo(codes, tenantId, empresaId);
        setItemMap(map);
      } catch (e: unknown) {
        setImportErr(getErrorMessage(e, "Erro ao carregar itens."));
      }
    };
    void loadMap();
  }, [selectedJob, tenantId, empresaId, carregarItensPorCodigo]);

  useEffect(() => {
    let active = true;

    const loadLoteMap = async () => {
      const clearMissing = () => setLoteMissing((prev) => (prev.length === 0 ? prev : []));

      if (!tenantId || !empresaId) {
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
        const map = await carregarItensPorCodigo(codes, tenantId, empresaId);
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
  }, [selectedOkJobs, tenantId, empresaId, carregarItensPorCodigo]);

  const fornecedorResolvido = Boolean(fornecedorIdBase ?? fornecedorId);
  const finalidadeSelecionada = Boolean(finalidadeLote);
  const solicitanteSelecionado = Boolean(solicitanteUsuarioId);
  const itensFaltantes = loteMissing.length > 0;

  const motivoSelecionadoRow = motivos.find((m) => m.id === motivoCompraId) ?? null;
  const motivoSelecionadoCodigo = String(motivoSelecionadoRow?.codigo ?? "")
    .trim()
    .toUpperCase();
  const motivoSelecionadoOk = Boolean(
    motivoCompraId && motivoSelecionadoRow && motivoSelecionadoCodigo && motivoSelecionadoCodigo !== "NAO_CLASSIFICADO"
  );

  const requisitosChecklist = {
    xml: hasSelectedOkJobs,
    finalidade: finalidadeSelecionada,
    motivo: motivoSelecionadoOk,
    solicitante: solicitanteSelecionado,
    fornecedor: fornecedorResolvido,
    itens: !itensFaltantes || canCreateItem,
  };

  // regra: importar só se tudo estiver ok e itens sem faltantes
  const bloqueiaImportacao =
    !hasSelectedOkJobs ||
    !finalidadeSelecionada ||
    !motivoSelecionadoOk ||
    !solicitanteSelecionado ||
    !fornecedorResolvido ||
    itensFaltantes ||
    !tenantId ||
    !empresaId;

  const podeCriarItens = !itensFaltantes || canCreateItem;

  // regra: o botão "Cadastrar itens" só fica habilitado quando o fornecedor já estiver cadastrado
  const bloqueiaCadastroItens =
    !hasSelectedOkJobs || !finalidadeSelecionada || !fornecedorResolvido || !tenantId || !empresaId || !podeCriarItens;

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
                  onChange={(e) => {
                    const next = e.target.value as ItemFinalidade | "";
                    setFinalidadeLote(next);

                    const fornecedorFinal = fornecedorIdBase ?? fornecedorIdRef.current;
                    if (fornecedorFinal) {
                      scheduleSaveFornecedorDefaults({
                        fornecedorId: fornecedorFinal,
                        finalidade: next ? (next as ItemFinalidade) : null,
                        motivoCompraId: normalizeMotivoId(motivoCompraIdRef.current),
                      });
                    }
                  }}
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

              <label className="flex flex-col gap-1">
                <span className="text-sm text-zinc-200">Classificacao / Motivo</span>
                <MotivoCompraCombobox
                  motivos={motivos}
                  value={motivoCompraId}
                  disabled={motivosLoading}
                  loading={motivosLoading}
                  error={motivosError}
                  onChange={(next) => {
                    setMotivoCompraId(next);
                    const fornecedorFinal = fornecedorIdBase ?? fornecedorIdRef.current;
                    if (fornecedorFinal) {
                      scheduleSaveFornecedorDefaults({
                        fornecedorId: fornecedorFinal,
                        finalidade: normalizeFinalidade(finalidadeRef.current),
                        motivoCompraId: normalizeMotivoId(next),
                      });
                    }
                  }}
                  onToggleFavorito={async (id, next) => {
                    await setMotivoFavorito(id, next);
                  }}
                />
                {!motivosLoading && !motivosError && !motivoSelecionadoOk && (
                  <div className="text-xs text-amber-300">Obrigatorio para importar (nao pode ser NAO_CLASSIFICADO).</div>
                )}

                {defaultsToast && (
                  <div
                    className={
                      defaultsToast.kind === "saved"
                        ? "text-xs text-emerald-300"
                        : defaultsToast.kind === "warn"
                          ? "text-xs text-amber-300"
                          : "text-xs text-red-300"
                    }
                  >
                    {defaultsToast.message}
                  </div>
                )}
              </label>

              <label className="flex flex-col gap-1">
                <span className="text-sm text-zinc-200">Solicitante (Usuario) (obrigatorio)</span>
                <select
                  value={solicitanteUsuarioId}
                  onChange={(e) => setSolicitanteUsuarioId(e.target.value)}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                  disabled={usuariosSolicitantesLoading || importBusy || isReading}
                >
                  <option value="">Selecione...</option>
                  {usuariosSolicitantes.map((u) => (
                    <option key={u.id} value={u.id}>
                      {u.nome} — {u.email}
                    </option>
                  ))}
                </select>
                {usuariosSolicitantesLoading && <div className="text-xs text-zinc-400">Carregando usuarios...</div>}
                {!usuariosSolicitantesLoading && usuariosSolicitantesError && (
                  <div className="text-xs text-red-400">{usuariosSolicitantesError}</div>
                )}
                {!usuariosSolicitantesLoading && !usuariosSolicitantesError && !solicitanteSelecionado && (
                  <div className="text-xs text-amber-300">Obrigatorio para importar.</div>
                )}
              </label>

              {osEnabled && (
                <label className="flex flex-col gap-1">
                  <span className="text-sm text-zinc-200">
                    OS (opcional)
                    <span className="text-xs text-zinc-500"> — apenas para Matéria-prima</span>
                  </span>

                  <div className="flex items-center gap-2">
                    <div className="relative flex-1">
                      <input
                        value={osNumero}
                        onChange={(e) => {
                          setOsNumero(e.target.value);
                          setOsId(null);
                          setOsLabel(null);
                          setOsError(null);
                        }}
                        onKeyDown={(e) => {
                          if (e.key === "Enter" && osNumero.trim() === "") {
                            e.preventDefault();
                            openOsLookup();
                          }
                        }}
                        placeholder="Numero da OS (Enter abre busca)"
                        className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                        disabled={importBusy || isReading}
                        autoComplete="off"
                        enterKeyHint="search"
                      />

                      {osLoading && (
                        <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
                          buscando...
                        </span>
                      )}
                    </div>

                    <button
                      type="button"
                      onClick={openOsLookup}
                      className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                      disabled={importBusy || isReading}
                    >
                      Buscar
                    </button>

                    <button
                      type="button"
                      onClick={() => {
                        setOsNumero("");
                        setOsId(null);
                        setOsLabel(null);
                        setOsError(null);
                      }}
                      className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                      disabled={importBusy || isReading || (!osNumero && osId === null)}
                      title="Limpar OS"
                    >
                      Limpar
                    </button>
                  </div>

                  {osLabel && <div className="text-xs text-zinc-400">{osLabel}</div>}
                  {osError && <div className="text-xs text-red-400">{osError}</div>}
                </label>
              )}

              {fornecedorResolvido && (
                <div className="text-sm text-zinc-200">
                  <span className="text-zinc-400">Fornecedor identificado:</span>{" "}
                  <span className="font-medium">{fornecedorNome ?? "—"}</span>
                  <span className="text-zinc-500"> — contas a pagar automático: </span>
                  <span className="font-medium">{fornecedorGerarContasAuto ? "Sim" : "Não"}</span>
                </div>
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
              <div className={requisitosChecklist.motivo ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.motivo ? "OK" : "Pendente"} - Classificacao/Motivo selecionado
              </div>
              <div className={requisitosChecklist.solicitante ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.solicitante ? "OK" : "Pendente"} - Solicitante selecionado
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
                  <Can perm="cad_fornecedores.write">
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
                              <Can perm="cad_itens.write">
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
            disabled={cadBusy || importBusy || isReading || bloqueiaCadastroItens}
            className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-100"
            title={!fornecedorResolvido ? "Cadastre/identifique o fornecedor para cadastrar itens." : undefined}
          >
            {cadBusy ? "Cadastrando..." : "Cadastrar itens"}
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

      <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-4 space-y-3">
        <div className="flex items-end justify-between gap-3 flex-wrap">
          <div>
            <div className="text-lg font-semibold">Notas importadas</div>
            <div className="text-sm text-zinc-400">
              Notas de entrada (material) importadas. Use o filtro por mês para imprimir/consultar um período.
            </div>
          </div>
          <div className="flex items-end gap-2 flex-wrap">
            <div className="flex items-center gap-2">
              <label className="text-xs text-zinc-400" htmlFor="recent-notas-mes">
                Mês
              </label>
              <select
                id="recent-notas-mes"
                className="px-2 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm"
                value={recentFilterMonth}
                onChange={(e) => setRecentFilterMonth(e.target.value)}
                disabled={!tenantId || !empresaId || recentNfsLoading}
                title="Filtrar por mês de emissão"
              >
                {Array.from({ length: 12 }).map((_, idx) => {
                  const m = idx + 1;
                  return (
                    <option key={m} value={String(m)}>
                      {String(m).padStart(2, "0")}
                    </option>
                  );
                })}
              </select>
            </div>

            <div className="flex items-center gap-2">
              <label className="text-xs text-zinc-400" htmlFor="recent-notas-ano">
                Ano
              </label>
              <input
                id="recent-notas-ano"
                className="w-[92px] px-2 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm"
                value={recentFilterYear}
                onChange={(e) => setRecentFilterYear(e.target.value.replace(/[^0-9]/g, "").slice(0, 4))}
                disabled={!tenantId || !empresaId || recentNfsLoading}
                inputMode="numeric"
                placeholder="YYYY"
                title="Filtrar por ano de emissão"
              />
            </div>

            <button
              type="button"
              onClick={() => {
                const params = new URLSearchParams({ mes: recentFilterMonth, ano: recentFilterYear });
                window.open(`/estoque/importar/imprimir?${params.toString()}`, "_blank");
              }}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
              disabled={!tenantId || !empresaId || recentNfsLoading}
            >
              Imprimir
            </button>

            <button
              type="button"
              onClick={() => setRecentReloadTick((n) => n + 1)}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
              disabled={!tenantId || !empresaId || recentNfsLoading}
            >
              {recentNfsLoading ? "Atualizando..." : "Atualizar"}
            </button>
          </div>
        </div>

        {recentNfsError ? (
          <div className="rounded-md border border-rose-900/60 bg-rose-950/30 px-3 py-2 text-sm text-rose-200">{recentNfsError}</div>
        ) : null}

        <div className="border border-zinc-800 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-3 py-2 text-left">Emissão</th>
                <th className="px-3 py-2 text-left">Série/Número</th>
                <th className="px-3 py-2 text-left">Emitente</th>
                <th className="px-3 py-2 text-left">Chave</th>
                <th className="px-3 py-2 text-right">Valor</th>
                <th className="px-3 py-2 text-center">Ação</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {recentNfsLoading ? (
                <tr>
                  <td colSpan={6} className="px-3 py-4 text-zinc-400 text-center">
                    Carregando...
                  </td>
                </tr>
              ) : recentNfs.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-3 py-4 text-zinc-400 text-center">
                    Nenhuma nota encontrada.
                  </td>
                </tr>
              ) : (
                recentNfs.map((nf) => {
                  const emissao = toDateOnly(nf.data_emissao ?? "") ?? "";
                  const serieNum = `${nf.serie ?? "—"} / ${nf.numero ?? "—"}`;
                  const chaveShort =
                    nf.chave && nf.chave.length > 18 ? `${nf.chave.slice(0, 8)}...${nf.chave.slice(-8)}` : nf.chave;
                  const isOpening = openingNfEntradaId === nf.id;
                  const canOpen = Boolean(tenantId && empresaId) && !isOpening;

                  return (
                    <tr
                      key={nf.id}
                      className={`hover:bg-zinc-900/40 ${canOpen ? "cursor-pointer" : "opacity-60"}`}
                      role="button"
                      tabIndex={canOpen ? 0 : -1}
                      onClick={() => {
                        if (!canOpen) return;
                        void abrirNotaImportada(nf);
                      }}
                      onKeyDown={(e) => {
                        if (!canOpen) return;
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          void abrirNotaImportada(nf);
                        }
                      }}
                    >
                      <td className="px-3 py-2">{formatDateBR(emissao) || "—"}</td>
                      <td className="px-3 py-2">{serieNum}</td>
                      <td className="px-3 py-2">{nf.emitente_nome ?? "—"}</td>
                      <td className="px-3 py-2 font-mono text-xs">{chaveShort || "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums">R$ {formatMoneyBR(Number(nf.valor_total ?? 0))}</td>
                      <td className="px-3 py-2 text-center">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            void abrirNotaImportada(nf);
                          }}
                          disabled={!canOpen}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs disabled:opacity-60"
                        >
                          {isOpening ? "Abrindo..." : "Abrir"}
                        </button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showOsLookup && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto"
          onClick={(e) => e.target === e.currentTarget && closeOsLookup()}
        >
          <div className="min-h-full w-full flex items-start sm:items-center justify-center p-4 py-6">
            <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl max-h-[90vh] flex flex-col overflow-hidden">
              <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
                <div>
                  <div className="text-lg font-semibold">Buscar OS</div>
                  <div className="text-sm text-zinc-400">Digite numero da OS ou cliente para buscar.</div>
                </div>
                <button
                  onClick={closeOsLookup}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>

              <div className="px-5 py-4 space-y-3 flex-1 min-h-0 overflow-auto">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Buscar</div>
                  <input
                    value={osLookupTerm}
                    onChange={(e) => {
                      const value = e.target.value;
                      setOsLookupTerm(value);
                      if (osLookupDebounceRef.current) clearTimeout(osLookupDebounceRef.current);
                      osLookupDebounceRef.current = setTimeout(() => {
                        void loadOsLookup(value);
                      }, 300);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void loadOsLookup(osLookupTerm);
                      }
                    }}
                    placeholder="Ex: 43 ou nome do cliente"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    autoFocus
                  />
                </div>

                {osLookupLoading && <div className="text-sm text-zinc-400">Buscando...</div>}
                {osLookupError && <div className="text-sm text-red-400">{osLookupError}</div>}

                <div className="border border-zinc-800 rounded-lg overflow-hidden">
                  <table className="w-full text-sm">
                    <thead className="bg-zinc-900/70">
                      <tr className="text-zinc-200">
                        <th className="px-3 py-2 text-left">OS</th>
                        <th className="px-3 py-2 text-left">Cliente</th>
                        <th className="px-3 py-2 text-left">Descricao</th>
                        <th className="px-3 py-2 text-center">Acao</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {osLookupRows.map((row) => (
                        <tr key={row.id} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2">{row.numero_os ?? row.id}</td>
                          <td className="px-3 py-2">{row.cliente_nome ?? "-"}</td>
                          <td className="px-3 py-2">{row.descricao_servico ?? "-"}</td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => {
                                const numero = row.numero_os ?? String(row.id);
                                setOsNumero(numero);
                                setOsId(Number(row.id));
                                setOsLabel(`OS ${numero} - ${(row.cliente_nome ?? "-")}`);
                                setOsError(null);
                                closeOsLookup();
                              }}
                              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                            >
                              Selecionar
                            </button>
                          </td>
                        </tr>
                      ))}
                      {!osLookupLoading && osLookupRows.length === 0 && osLookupTerm.trim() !== "" && (
                        <tr>
                          <td colSpan={4} className="px-3 py-4 text-zinc-400">
                            Nenhuma OS encontrada.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

