"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type MotivoCompra = {
  id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
};

type MotivoCompraSelectRow = {
  id: string | null;
  codigo: string | null;
  nome: string | null;
  requires_text: boolean | null;
  requires_os: boolean | null;
};

type ApprovalQueueRow = {
  titulo_id: string;
  fornecedor_id?: number | string | null;
  fornecedor_nome: string | null;
  competencia_date: string | null;
  emissao_date: string | null;
  status: string | null;
  motivo_codigo: string | null;
  motivo_nome?: string | null;
  vencimento_date: string | null;
  dias_atraso: number | string | null;
  valor_aberto: number | string | null;
};

type QueueItem = {
  tituloId: string;
  fornecedorId: number | null;
  fornecedorNome: string;
  competencia: string | null;
  emissao: string | null;
  status: string | null;
  motivoCodigo: string | null;
  motivoNome: string | null;
  nextVencimento: string | null;
  maiorAtrasoDias: number;
  totalAberto: number;
  parcelasCount: number;
};

type TituloDetails = {
  tituloId: string;
  documentoFiscalId: string | null;
  nfEntradaId: number | null;
  nfNumero: string | null;
  nfSerie: string | null;
  chaveAcesso: string | null;
  solicitanteUsuarioId: string | null;
  solicitanteNome: string | null;
  motivoCompraIdImport: string | null;
  motivoCompraCodigoImport: string | null;
  motivoCompraNomeImport: string | null;
  osIdImport: number | null;
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

function classForStatus(status: string | null | undefined) {
  const s = String(status ?? "").toUpperCase();
  if (s === "PENDENTE") return "bg-amber-500/15 text-amber-200 border-amber-500/30";
  if (s === "APROVADO") return "bg-sky-500/15 text-sky-200 border-sky-500/30";
  if (s === "AGENDADO") return "bg-emerald-500/15 text-emerald-200 border-emerald-500/30";
  if (s === "PAGO") return "bg-zinc-500/15 text-zinc-200 border-zinc-500/30";
  if (s === "CANCELADO") return "bg-rose-500/15 text-rose-200 border-rose-500/30";
  return "bg-zinc-500/10 text-zinc-200 border-zinc-500/20";
}

function Pill({ label, status }: { label: string; status?: string | null }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${classForStatus(status)}`}>{label}</span>
  );
}

export default function ContasPagarAprovacoesClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [q, setQ] = useState("");
  const [fornecedorFiltro, setFornecedorFiltro] = useState("");
  const [nfFiltro, setNfFiltro] = useState("");
  const [onlyOverdue, setOnlyOverdue] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [queue, setQueue] = useState<QueueItem[]>([]);
  const [detailsByTituloId, setDetailsByTituloId] = useState<Record<string, TituloDetails>>({});
  const [motivos, setMotivos] = useState<MotivoCompra[]>([]);
  const warnedMissingContextRef = useRef(false);

  const [selectedTituloId, setSelectedTituloId] = useState<string | null>(null);
  const [approveOpen, setApproveOpen] = useState(false);
  const selected = useMemo(
    () => (selectedTituloId ? queue.find((x) => x.tituloId === selectedTituloId) ?? null : null),
    [queue, selectedTituloId]
  );

  const selectedDetails = useMemo(() => {
    if (!selectedTituloId) return null;
    return detailsByTituloId[selectedTituloId] ?? null;
  }, [detailsByTituloId, selectedTituloId]);

  const [motivoId, setMotivoId] = useState<string>("");
  const [motivoOutrosText, setMotivoOutrosText] = useState<string>("");
  const [osId, setOsId] = useState<string>("");
  const [observacao, setObservacao] = useState<string>("");

  const selectedMotivo = useMemo(() => motivos.find((m) => m.id === motivoId) ?? null, [motivos, motivoId]);

  const filteredQueue = useMemo(() => {
    const nfTerm = nfFiltro.trim();
    if (!nfTerm) return queue;
    return queue.filter((row) => {
      const d = detailsByTituloId[row.tituloId] ?? null;
      const nfNumero = d?.nfNumero ?? "";
      const nfSerie = d?.nfSerie ?? "";
      const chave = d?.chaveAcesso ?? "";
      const hay = `${nfNumero} ${nfSerie} ${chave}`.toLowerCase();
      return hay.includes(nfTerm.toLowerCase());
    });
  }, [detailsByTituloId, nfFiltro, queue]);

  const resumo = useMemo(() => {
    const list = filteredQueue;
    const totalAberto = list.reduce((acc, r) => acc + r.totalAberto, 0);
    const vencidos = list.reduce((acc, r) => (r.maiorAtrasoDias >= 0 ? acc + r.totalAberto : acc), 0);
    return { totalAberto, vencidos, count: list.length };
  }, [filteredQueue]);

  useEffect(() => {
    if (!selectedTituloId) {
      setMotivoId("");
      setMotivoOutrosText("");
      setOsId("");
      setObservacao("");
      setApproveOpen(false);
      return;
    }
    // Only validate selected motivo if we already loaded the motivos list.
    // (Otherwise we'd clear a prefilled motivoId before the list arrives.)
    if (motivos.length > 0) {
      setMotivoId((prev) => (prev && motivos.some((m) => m.id === prev) ? prev : ""));
    }
  }, [motivos, selectedTituloId]);

  // Prefill modal fields with import defaults (NF/XML) when opening.
  useEffect(() => {
    if (!approveOpen) return;
    if (!selectedTituloId) return;
    const d = selectedDetails;
    if (!d) return;

    // Motivo: prefer the imported one (nf_entrada.motivo_compra_id)
    if (!motivoId && d.motivoCompraIdImport) {
      setMotivoId(d.motivoCompraIdImport);
    }

    // OS: prefer the imported one (nf_entrada.os_id or documento_fiscal.os_id_import)
    if (!osId.trim() && typeof d.osIdImport === "number" && Number.isFinite(d.osIdImport)) {
      setOsId(String(d.osIdImport));
    }
  }, [approveOpen, motivoId, osId, selectedDetails, selectedTituloId]);

  useEffect(() => {
    if (typeof te.sessionUserId !== "string") return;
    const tenantId = te.tenantId ?? null;
    const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id : null);
    if (!tenantId || !empresaId) {
      if (process.env.NODE_ENV !== "production" && !warnedMissingContextRef.current) {
        console.debug("[financeiro] Contexto ausente ao carregar aprovações AP", {
          tenantId,
          empresaId: te.empresaId ?? null,
          empresasCount: te.empresas.length,
        });
        warnedMissingContextRef.current = true;
      }
      return;
    }
    warnedMissingContextRef.current = false;
    if (canFinanceiro !== true) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      const supabase = getSupabaseBrowser();

      const loadExtraDetails = async (tituloIds: string[]) => {
        if (!tituloIds.length) return;

        try {
          const { data: titRows, error: titErr } = await supabase
            .schema("f")
            .from("titulo")
            .select(
              "id,documento_fiscal:documento_fiscal_id(id,numero,serie,chave_acesso,source_nf_entrada_id,os_id_import),fornecedor_id"
            )
            .eq("tenant_id", tenantId)
            .in("id", tituloIds)
            .is("deleted_at", null);

          if (cancelled) return;
          if (titErr) return;

          type TituloRow = {
            id: string;
            fornecedor_id: number | null;
            documento_fiscal?: {
              id: string | null;
              numero: string | null;
              serie: string | null;
              chave_acesso: string | null;
              source_nf_entrada_id: number | null;
              os_id_import: number | null;
            } | null;
          };

          const tituloRows = (titRows ?? []) as unknown as TituloRow[];
          const nfEntradaIds = Array.from(
            new Set(
              tituloRows
                .map((r) => r.documento_fiscal?.source_nf_entrada_id ?? null)
                .filter((v): v is number => typeof v === "number" && Number.isFinite(v))
            )
          );

          const solicitanteByNfEntradaId = new Map<number, string | null>();
          const motivoByNfEntradaId = new Map<number, string | null>();
          const osByNfEntradaId = new Map<number, number | null>();
          if (nfEntradaIds.length) {
            const { data: nfRows, error: nfErr } = await supabase
              .from("nf_entrada")
              .select("id,solicitante_usuario_id,motivo_compra_id,os_id")
              .eq("tenant_id", tenantId)
              .in("id", nfEntradaIds);
            if (!nfErr) {
              for (const nf of (nfRows ?? []) as unknown[]) {
                const row = (nf ?? {}) as Record<string, unknown>;
                const id = typeof row.id === "number" ? row.id : Number(row.id);
                if (!Number.isFinite(id)) continue;
                const solicitante = row.solicitante_usuario_id ? String(row.solicitante_usuario_id) : null;
                solicitanteByNfEntradaId.set(id, solicitante);
                const motivoCompraId = row.motivo_compra_id ? String(row.motivo_compra_id) : null;
                motivoByNfEntradaId.set(id, motivoCompraId);
                const osId = row.os_id === null || row.os_id === undefined ? null : Number(row.os_id);
                osByNfEntradaId.set(id, Number.isFinite(osId) ? osId : null);
              }
            }
          }

          const solicitanteIds = Array.from(new Set(Array.from(solicitanteByNfEntradaId.values()).filter(Boolean))) as string[];
          const solicitanteNomeById = new Map<string, string>();
          if (solicitanteIds.length) {
            try {
              const { data: usuarios, error: uErr } = await supabase
                .schema("a")
                .from("usuario")
                .select("id,nome")
                .in("id", solicitanteIds)
                .is("deleted_at", null);
              if (!uErr) {
                for (const u of (usuarios ?? []) as unknown[]) {
                  const row = (u ?? {}) as Record<string, unknown>;
                  const id = row.id ? String(row.id) : "";
                  const nome = row.nome ? String(row.nome) : "";
                  if (id && nome) solicitanteNomeById.set(id, nome);
                }
              }
            } catch {
              // ignore: RLS/permissions may block schema a
            }
          }

          const motivoCompraIds = Array.from(new Set(Array.from(motivoByNfEntradaId.values()).filter(Boolean))) as string[];
          const motivoCompraById = new Map<string, { codigo: string; nome: string }>();
          if (motivoCompraIds.length) {
            try {
              const { data: motivosData } = await supabase
                .schema("f")
                .from("motivo_compra")
                .select("id,codigo,nome")
                .in("id", motivoCompraIds)
                .is("deleted_at", null);
              for (const m of (motivosData ?? []) as unknown[]) {
                const row = (m ?? {}) as Record<string, unknown>;
                const id = row.id ? String(row.id) : "";
                const codigo = row.codigo ? String(row.codigo) : "";
                const nome = row.nome ? String(row.nome) : "";
                if (id && codigo && nome) motivoCompraById.set(id, { codigo, nome });
              }
            } catch {
              // ignore
            }
          }

          const next: Record<string, TituloDetails> = {};
          for (const r of tituloRows) {
            const tituloId = String(r.id);
            const df = r.documento_fiscal ?? null;
            const nfEntradaId = df?.source_nf_entrada_id ?? null;
            const solicitanteUsuarioId = nfEntradaId ? solicitanteByNfEntradaId.get(nfEntradaId) ?? null : null;
            const solicitanteNome = solicitanteUsuarioId ? solicitanteNomeById.get(solicitanteUsuarioId) ?? null : null;
            const motivoCompraIdImport = nfEntradaId ? motivoByNfEntradaId.get(nfEntradaId) ?? null : null;
            const motivo = motivoCompraIdImport ? motivoCompraById.get(motivoCompraIdImport) ?? null : null;

            const osFromNf = nfEntradaId ? osByNfEntradaId.get(nfEntradaId) ?? null : null;
            const osFromDf = df?.os_id_import === null || df?.os_id_import === undefined ? null : Number(df.os_id_import);
            const osIdImport = osFromNf ?? (Number.isFinite(osFromDf) ? osFromDf : null);

            next[tituloId] = {
              tituloId,
              documentoFiscalId: df?.id ? String(df.id) : null,
              nfEntradaId: typeof nfEntradaId === "number" ? nfEntradaId : null,
              nfNumero: df?.numero ?? null,
              nfSerie: df?.serie ?? null,
              chaveAcesso: df?.chave_acesso ?? null,
              solicitanteUsuarioId,
              solicitanteNome,
              motivoCompraIdImport,
              motivoCompraCodigoImport: motivo?.codigo ?? null,
              motivoCompraNomeImport: motivo?.nome ?? null,
              osIdImport: typeof osIdImport === "number" && Number.isFinite(osIdImport) ? osIdImport : null,
            };
          }

          setDetailsByTituloId((prev) => ({ ...prev, ...next }));
        } catch {
          // ignore enrichment failures
        }
      };

      try {
        // Load motivos
        const { data: motivosData, error: motivosErr } = await applyTenantEmpresa(
          supabase.schema("f").from("motivo_compra").select("id,codigo,nome,requires_text,requires_os"),
          tenantId,
          empresaId
        )
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("codigo", { ascending: true });

        if (cancelled) return;
        if (motivosErr) {
          setMotivos([]);
        } else {
          const rows = (motivosData ?? []) as unknown as MotivoCompraSelectRow[];
          const mapped = rows
            .map((r) => ({
              id: String(r.id ?? ""),
              codigo: String(r.codigo ?? ""),
              nome: String(r.nome ?? ""),
              requires_text: Boolean(r.requires_text),
              requires_os: Boolean(r.requires_os),
            }))
            .filter((m) => m.id && m.codigo && m.nome);
          setMotivos(mapped);
        }

        // Queue: AP em aberto sem motivo (via view)
        let query = applyTenantEmpresa(
          supabase
            .schema("f")
            .from("r_ap_aging_detalhe")
            .select(
              "titulo_id,fornecedor_id,fornecedor_nome,competencia_date,emissao_date,status,motivo_codigo,motivo_nome,vencimento_date,dias_atraso,valor_aberto"
            ),
          tenantId,
          empresaId
        )
          .eq("motivo_codigo", "NAO_CLASSIFICADO")
          .in("status", ["PENDENTE", "APROVADO", "AGENDADO"])
          .order("vencimento_date", { ascending: true })
          .limit(1000);

        const term = q.trim();
        if (term) {
          query = query.or([`fornecedor_nome.ilike.%${term}%`, `titulo_id.eq.${term}`].join(","));
        }

        const fornecedorTerm = fornecedorFiltro.trim();
        if (fornecedorTerm) {
          query = query.ilike("fornecedor_nome", `%${fornecedorTerm}%`);
        }

        if (onlyOverdue) {
          query = query.gte("dias_atraso", 0);
        }

        const { data, error: qErr } = await query;
        if (cancelled) return;
        if (qErr) {
          setQueue([]);
          setError(qErr.message ?? "Erro ao carregar fila de aprovação.");
          return;
        }

        const rows = (data ?? []) as unknown as ApprovalQueueRow[];
        const map = new Map<string, QueueItem>();
        for (const r of rows) {
          const tituloId = String(r.titulo_id);
          const prev = map.get(tituloId);
          const fornecedorNome = String(r.fornecedor_nome ?? "SEM FORNECEDOR");
          const fornecedorId = r.fornecedor_id === null || r.fornecedor_id === undefined ? null : Number(r.fornecedor_id);
          const motivoCodigo = r.motivo_codigo ? String(r.motivo_codigo) : null;
          const motivoNome = r.motivo_nome ? String(r.motivo_nome) : null;
          const aberto = n(r.valor_aberto);
          const atraso = n(r.dias_atraso);

          if (!prev) {
            map.set(tituloId, {
              tituloId,
              fornecedorId: Number.isFinite(fornecedorId as number) ? (fornecedorId as number) : null,
              fornecedorNome,
              competencia: r.competencia_date ? String(r.competencia_date) : null,
              emissao: r.emissao_date ? String(r.emissao_date) : null,
              status: r.status ? String(r.status) : null,
              motivoCodigo,
              motivoNome,
              nextVencimento: r.vencimento_date ? String(r.vencimento_date) : null,
              maiorAtrasoDias: atraso,
              totalAberto: aberto,
              parcelasCount: 1,
            });
          } else {
            prev.totalAberto += aberto;
            prev.parcelasCount += 1;
            prev.maiorAtrasoDias = Math.max(prev.maiorAtrasoDias, atraso);
            if (!prev.motivoCodigo && motivoCodigo) prev.motivoCodigo = motivoCodigo;
            if (!prev.motivoNome && motivoNome) prev.motivoNome = motivoNome;
            const venc = r.vencimento_date ? String(r.vencimento_date) : null;
            if (venc && (!prev.nextVencimento || venc < prev.nextVencimento)) prev.nextVencimento = venc;
          }
        }

        const list = Array.from(map.values()).sort((a, b) => {
          const av = a.nextVencimento ?? "9999-12-31";
          const bv = b.nextVencimento ?? "9999-12-31";
          if (av !== bv) return av.localeCompare(bv);
          return b.totalAberto - a.totalAberto;
        });

        setQueue(list);

        // Best-effort enrichment: NF (número/série/chave) + solicitante via nf_entrada.
        void loadExtraDetails(list.map((x) => x.tituloId));

        if (selectedTituloId && !list.some((x) => x.tituloId === selectedTituloId)) {
          setSelectedTituloId(null);
        }
      } catch (e: unknown) {
        if (cancelled) return;
        setQueue([]);
        setError(e instanceof Error ? e.message : "Erro inesperado ao carregar aprovações.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [canFinanceiro, fornecedorFiltro, onlyOverdue, q, selectedTituloId, te.empresas, te.empresaId, te.sessionUserId, te.tenantId]);

  async function aprovar() {
    if (!selected) return;
    if (!te.tenantId) return;
    if (!motivoId) {
      setError("Selecione um motivo de compra.");
      return;
    }

    const motivo = selectedMotivo;
    if (motivo?.requires_text && !motivoOutrosText.trim()) {
      setError("Este motivo exige descrição (texto)." );
      return;
    }

    if (motivo?.requires_os && !osId.trim()) {
      setError("Este motivo exige OS." );
      return;
    }

    const osIdNum = osId.trim() ? Number(osId.trim()) : null;
    if (osId.trim() && !Number.isFinite(osIdNum)) {
      setError("OS inválida." );
      return;
    }

    setError(null);
    setLoading(true);

    try {
      const supabase = getSupabaseBrowser();
      const payload: {
        tenant_id: string;
        titulo_id: string;
        motivo_compra_id: string;
        motivo_outros_text?: string | null;
        os_id?: number | null;
        change_reason?: string | null;
      } = {
        tenant_id: te.tenantId,
        titulo_id: selected.tituloId,
        motivo_compra_id: motivoId,
        motivo_outros_text: motivo?.requires_text ? motivoOutrosText.trim() : (motivoOutrosText.trim() ? motivoOutrosText.trim() : null),
        os_id: motivo?.requires_os ? (osIdNum as number) : (osId.trim() ? (osIdNum as number) : null),
        change_reason: observacao.trim() ? observacao.trim() : null,
      };

      const { error: insErr } = await supabase
        .schema("f")
        .from("titulo_aprovacao")
        .insert(payload);

      if (insErr) {
        setError(insErr.message ?? "Falha ao aprovar." );
        return;
      }

      // refresh list
      setSelectedTituloId(null);
      setMotivoId("");
      setMotivoOutrosText("");
      setOsId("");
      setObservacao("");
      setApproveOpen(false);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao aprovar." );
    } finally {
      setLoading(false);
    }
  }

  const openApprove = (tituloId: string) => {
    // Reset form fields for the new selection; defaults will be prefilled from import.
    setMotivoId("");
    setMotivoOutrosText("");
    setOsId("");
    setObservacao("");
    setSelectedTituloId(tituloId);
    setApproveOpen(true);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Contas a Pagar — Aprovações</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Fila de classificação/aprovação para manter competência e centro/motivo consistentes (Lucro Real).
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/contas-pagar/lancamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Lançamentos
          </Link>
          <Link
            href="/financeiro/contas-pagar/pagamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Pagamentos
          </Link>
          <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
            Voltar
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Filtro (título_id ou fornecedor)…"
            aria-label="Filtro"
            className="w-full sm:w-[280px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />
          <input
            value={fornecedorFiltro}
            onChange={(e) => setFornecedorFiltro(e.target.value)}
            placeholder="Fornecedor"
            aria-label="Fornecedor"
            className="w-full sm:w-[280px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />
          <input
            value={nfFiltro}
            onChange={(e) => setNfFiltro(e.target.value)}
            placeholder="Nº NF / série / chave"
            aria-label="Número da NF"
            className="w-full sm:w-[220px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={onlyOverdue}
              onChange={(e) => setOnlyOverdue(e.target.checked)}
              className="accent-zinc-200"
            />
            <span>Somente vencidos</span>
          </label>
          <div className="flex-1" />
          <div className="text-xs text-zinc-500">Fila: {resumo.count} título(s) · R$ {formatDecimalBR(resumo.totalAberto, 2)}</div>
        </div>
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-900/50 bg-rose-950/20 p-4 text-rose-200 text-sm">{error}</div>
      ) : null}

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-xs text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="py-2 px-3 text-left font-medium">Fornecedor</th>
                  <th className="py-2 px-3 text-left font-medium">N. NF</th>
                  <th className="py-2 px-3 text-left font-medium">Status</th>
                  <th className="py-2 px-3 text-left font-medium">Vencidos</th>
                  <th className="py-2 px-3 text-left font-medium">Competência</th>
                  <th className="py-2 px-3 text-left font-medium">Próx. venc.</th>
                  <th className="py-2 px-3 text-left font-medium">Classificação</th>
                  <th className="py-2 px-3 text-left font-medium">Solicitante</th>
                  <th className="py-2 px-3 text-right font-medium">Parcelas</th>
                  <th className="py-2 px-3 text-right font-medium">Aberto</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={10} className="py-6 text-center text-zinc-500">Carregando…</td>
                  </tr>
                ) : null}

                {!loading && filteredQueue.length === 0 ? (
                  <tr>
                    <td colSpan={10} className="py-6 text-center text-zinc-500">Nenhum título pendente de aprovação.</td>
                  </tr>
                ) : null}

                {filteredQueue.map((r) => (
                  <tr
                    key={r.tituloId}
                    role="button"
                    tabIndex={0}
                    onClick={() => openApprove(r.tituloId)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        openApprove(r.tituloId);
                      }
                    }}
                    className={
                      selectedTituloId === r.tituloId
                        ? "border-b border-zinc-900/70 bg-zinc-900/40 cursor-pointer"
                        : "border-b border-zinc-900/70 hover:bg-zinc-900/30 cursor-pointer"
                    }
                  >
                    <td className="py-2 px-3">
                      <div className="truncate text-zinc-100" title={r.fornecedorNome}>{r.fornecedorNome}</div>
                      <div className="text-xs text-zinc-500 truncate" title={r.tituloId}>{r.tituloId}</div>
                    </td>
                    <td className="py-2 px-3 whitespace-nowrap">
                      {(() => {
                        const d = detailsByTituloId[r.tituloId] ?? null;
                        const numero = d?.nfNumero ? String(d.nfNumero) : "";
                        const serie = d?.nfSerie ? String(d.nfSerie) : "";
                        const chave = d?.chaveAcesso ? String(d.chaveAcesso) : "";
                        const chaveShort = chave.length >= 10 ? `${chave.slice(0, 6)}…${chave.slice(-4)}` : chave;
                        if (!numero && !serie) return <span className="text-zinc-500">—</span>;
                        return (
                          <div className="leading-tight">
                            <div className="text-zinc-100">{numero || "—"}</div>
                            <div className="text-xs text-zinc-500">
                              Série {serie || "—"}
                              {chaveShort ? <span className="text-zinc-600"> · Chave {chaveShort}</span> : null}
                            </div>
                          </div>
                        );
                      })()}
                    </td>
                    <td className="py-2 px-3"><Pill label={String(r.status ?? "—")} status={r.status} /></td>
                    <td className="py-2 px-3 tabular-nums whitespace-nowrap">
                      {r.maiorAtrasoDias >= 0 ? (
                        <span className="text-rose-200">{r.maiorAtrasoDias}d</span>
                      ) : (
                        <span className="text-zinc-500">—</span>
                      )}
                    </td>
                    <td className="py-2 px-3 whitespace-nowrap">{formatDateBR(r.competencia)}</td>
                    <td className="py-2 px-3 whitespace-nowrap">{formatDateBR(r.nextVencimento)}</td>
                    <td className="py-2 px-3">
                      {(() => {
                        const d = detailsByTituloId[r.tituloId] ?? null;
                        const importLabel =
                          d?.motivoCompraCodigoImport && d?.motivoCompraNomeImport
                            ? `${d.motivoCompraCodigoImport} — ${d.motivoCompraNomeImport}`
                            : null;
                        const isNaoClass = String(r.motivoCodigo ?? "").toUpperCase() === "NAO_CLASSIFICADO";

                        return (
                          <div className="leading-tight">
                            <div className="text-zinc-100 truncate">{r.motivoNome ?? "—"}</div>
                            <div className="text-xs text-zinc-500 truncate">{r.motivoCodigo ?? ""}</div>
                            {isNaoClass && importLabel ? (
                              <div className="text-xs text-amber-200/90 truncate">Importação: {importLabel}</div>
                            ) : null}
                          </div>
                        );
                      })()}
                    </td>
                    <td className="py-2 px-3">
                      {(() => {
                        const d = detailsByTituloId[r.tituloId] ?? null;
                        if (d?.solicitanteNome) return <span className="text-zinc-100">{d.solicitanteNome}</span>;
                        if (d?.solicitanteUsuarioId) return <span className="text-zinc-400">{d.solicitanteUsuarioId}</span>;
                        return <span className="text-zinc-500">—</span>;
                      })()}
                    </td>
                    <td className="py-2 px-3 text-right tabular-nums">{r.parcelasCount}</td>
                    <td className="py-2 px-3 text-right tabular-nums font-medium">R$ {formatDecimalBR(r.totalAberto, 2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

      </div>

      {approveOpen && selected ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <button
            type="button"
            aria-label="Fechar"
            className="absolute inset-0 bg-black/60"
            onClick={() => setApproveOpen(false)}
          />

          <div
            role="dialog"
            aria-modal="true"
            className="relative w-full max-w-2xl rounded-xl border border-zinc-800 bg-zinc-950 shadow-2xl"
          >
            <div className="flex items-center justify-between gap-3 border-b border-zinc-800 px-4 py-3">
              <div>
                <div className="text-sm font-semibold">Aprovar / Classificar</div>
                <div className="text-xs text-zinc-500">Insere em f.titulo_aprovacao</div>
              </div>
              <button
                type="button"
                onClick={() => setApproveOpen(false)}
                className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Fechar
              </button>
            </div>

            <div className="p-4 space-y-3">
              <div className="rounded-lg border border-zinc-800 p-3">
                <div className="text-xs text-zinc-500">Título</div>
                <div className="mt-1 text-sm text-zinc-100 break-all">{selected.tituloId}</div>
                <div className="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
                  <div className="text-zinc-400">
                    Fornecedor: <span className="text-zinc-200">{selected.fornecedorNome}</span>
                  </div>
                  <div className="text-zinc-400">
                    NF: <span className="text-zinc-200">{selectedDetails?.nfNumero ?? "—"}</span>
                    <span className="text-zinc-500"> (Série {selectedDetails?.nfSerie ?? "—"})</span>
                  </div>
                  <div className="text-zinc-400">
                    Competência: <span className="text-zinc-200">{formatDateBR(selected.competencia)}</span>
                  </div>
                  <div className="text-zinc-400">
                    Próx. venc.: <span className="text-zinc-200">{formatDateBR(selected.nextVencimento)}</span>
                  </div>
                  <div className="text-zinc-400">
                    Total aberto: <span className="text-zinc-200">R$ {formatDecimalBR(selected.totalAberto, 2)}</span>
                  </div>
                  <div className="text-zinc-400">
                    Solicitante: <span className="text-zinc-200">{selectedDetails?.solicitanteNome ?? "—"}</span>
                  </div>
                </div>
              </div>

              <label className="block text-xs text-zinc-400">
                Motivo de compra
                <select
                  value={motivoId}
                  onChange={(e) => setMotivoId(e.target.value)}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  aria-label="Motivo de compra"
                >
                  <option value="">Selecione…</option>
                  {motivos.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.codigo} — {m.nome}
                    </option>
                  ))}
                </select>
              </label>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <label className="block text-xs text-zinc-400">
                  OS (se aplicável)
                  <input
                    value={osId}
                    onChange={(e) => setOsId(e.target.value)}
                    placeholder={selectedMotivo?.requires_os ? "Obrigatório para este motivo" : "Opcional"}
                    aria-label="OS"
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Texto (se aplicável)
                  <input
                    value={motivoOutrosText}
                    onChange={(e) => setMotivoOutrosText(e.target.value)}
                    placeholder={selectedMotivo?.requires_text ? "Obrigatório para este motivo" : "Opcional"}
                    aria-label="Texto do motivo"
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400 sm:col-span-2">
                  Observação
                  <input
                    value={observacao}
                    onChange={(e) => setObservacao(e.target.value)}
                    placeholder="Ex.: Classificado conforme nota/contrato"
                    aria-label="Observação"
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>
              </div>

              <div className="flex items-center justify-between gap-3">
                <div className="text-xs text-zinc-600">
                  Dica Lucro Real: a aprovação evita títulos sem classificação.
                </div>
                <button
                  type="button"
                  onClick={aprovar}
                  disabled={loading}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                >
                  Aprovar
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
