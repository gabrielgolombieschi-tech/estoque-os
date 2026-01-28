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
  fornecedor_nome: string | null;
  competencia_date: string | null;
  emissao_date: string | null;
  status: string | null;
  motivo_codigo: string | null;
  vencimento_date: string | null;
  dias_atraso: number | string | null;
  valor_aberto: number | string | null;
};

type QueueItem = {
  tituloId: string;
  fornecedorNome: string;
  competencia: string | null;
  emissao: string | null;
  status: string | null;
  nextVencimento: string | null;
  maiorAtrasoDias: number;
  totalAberto: number;
  parcelasCount: number;
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
  const [onlyOverdue, setOnlyOverdue] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [queue, setQueue] = useState<QueueItem[]>([]);
  const [motivos, setMotivos] = useState<MotivoCompra[]>([]);
  const warnedMissingContextRef = useRef(false);

  const [selectedTituloId, setSelectedTituloId] = useState<string | null>(null);
  const selected = useMemo(
    () => (selectedTituloId ? queue.find((x) => x.tituloId === selectedTituloId) ?? null : null),
    [queue, selectedTituloId]
  );

  const [motivoId, setMotivoId] = useState<string>("");
  const [motivoOutrosText, setMotivoOutrosText] = useState<string>("");
  const [osId, setOsId] = useState<string>("");
  const [changeReason, setChangeReason] = useState<string>("");

  const selectedMotivo = useMemo(() => motivos.find((m) => m.id === motivoId) ?? null, [motivos, motivoId]);

  const resumo = useMemo(() => {
    const totalAberto = queue.reduce((acc, r) => acc + r.totalAberto, 0);
    const vencidos = queue.reduce((acc, r) => (r.maiorAtrasoDias >= 0 ? acc + r.totalAberto : acc), 0);
    return { totalAberto, vencidos, count: queue.length };
  }, [queue]);

  useEffect(() => {
    if (!selectedTituloId) {
      setMotivoId("");
      setMotivoOutrosText("");
      setOsId("");
      setChangeReason("");
      return;
    }
    // keep motivo selection when switching items only if still valid
    setMotivoId((prev) => (prev && motivos.some((m) => m.id === prev) ? prev : ""));
  }, [motivos, selectedTituloId]);

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
            .select("titulo_id,fornecedor_nome,competencia_date,emissao_date,status,motivo_codigo,vencimento_date,dias_atraso,valor_aberto"),
          tenantId,
          empresaId
        )
          .eq("empresa_id", empresaId)
          .eq("motivo_codigo", "NAO_CLASSIFICADO")
          .in("status", ["PENDENTE", "APROVADO", "AGENDADO"])
          .order("vencimento_date", { ascending: true })
          .limit(1000);

        const term = q.trim();
        if (term) {
          query = query.or([`fornecedor_nome.ilike.%${term}%`, `titulo_id.eq.${term}`].join(","));
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
          const aberto = n(r.valor_aberto);
          const atraso = n(r.dias_atraso);

          if (!prev) {
            map.set(tituloId, {
              tituloId,
              fornecedorNome,
              competencia: r.competencia_date ? String(r.competencia_date) : null,
              emissao: r.emissao_date ? String(r.emissao_date) : null,
              status: r.status ? String(r.status) : null,
              nextVencimento: r.vencimento_date ? String(r.vencimento_date) : null,
              maiorAtrasoDias: atraso,
              totalAberto: aberto,
              parcelasCount: 1,
            });
          } else {
            prev.totalAberto += aberto;
            prev.parcelasCount += 1;
            prev.maiorAtrasoDias = Math.max(prev.maiorAtrasoDias, atraso);
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
  }, [canFinanceiro, onlyOverdue, q, selectedTituloId, te.empresas, te.empresaId, te.sessionUserId, te.tenantId]);

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
        change_reason: changeReason.trim() ? changeReason.trim() : null,
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
      setChangeReason("");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao aprovar." );
    } finally {
      setLoading(false);
    }
  }

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
            placeholder="Buscar por fornecedor ou título_id…"
            aria-label="Buscar"
            className="w-full sm:w-[420px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
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

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2 rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-xs text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="py-2 px-3 text-left font-medium">Fornecedor</th>
                  <th className="py-2 px-3 text-left font-medium">Status</th>
                  <th className="py-2 px-3 text-left font-medium">Competência</th>
                  <th className="py-2 px-3 text-left font-medium">Próx. venc.</th>
                  <th className="py-2 px-3 text-right font-medium">Parcelas</th>
                  <th className="py-2 px-3 text-right font-medium">Aberto</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={6} className="py-6 text-center text-zinc-500">Carregando…</td>
                  </tr>
                ) : null}

                {!loading && queue.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="py-6 text-center text-zinc-500">Nenhum título pendente de aprovação.</td>
                  </tr>
                ) : null}

                {queue.map((r) => (
                  <tr
                    key={r.tituloId}
                    className={
                      selectedTituloId === r.tituloId
                        ? "border-b border-zinc-900/70 bg-zinc-900/40"
                        : "border-b border-zinc-900/70 hover:bg-zinc-900/30"
                    }
                  >
                    <td className="py-2 px-3">
                      <button
                        type="button"
                        onClick={() => setSelectedTituloId(r.tituloId)}
                        className="text-left w-full"
                        title={r.tituloId}
                      >
                        <div className="truncate text-zinc-100">{r.fornecedorNome}</div>
                        <div className="text-xs text-zinc-500 truncate">{r.tituloId}</div>
                      </button>
                    </td>
                    <td className="py-2 px-3"><Pill label={String(r.status ?? "—")} status={r.status} /></td>
                    <td className="py-2 px-3 whitespace-nowrap">{formatDateBR(r.competencia)}</td>
                    <td className="py-2 px-3 whitespace-nowrap">{formatDateBR(r.nextVencimento)}</td>
                    <td className="py-2 px-3 text-right tabular-nums">{r.parcelasCount}</td>
                    <td className="py-2 px-3 text-right tabular-nums font-medium">R$ {formatDecimalBR(r.totalAberto, 2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold">Aprovar / Classificar</div>
          <div className="text-xs text-zinc-500 mt-1">Insere em `f.titulo_aprovacao` para o título selecionado.</div>

          {!selected ? (
            <div className="mt-4 text-sm text-zinc-500">Selecione um título na lista para aprovar.</div>
          ) : (
            <div className="mt-4 space-y-3">
              <div className="rounded-lg border border-zinc-800 p-3">
                <div className="text-xs text-zinc-500">Título</div>
                <div className="mt-1 text-sm text-zinc-100 break-all">{selected.tituloId}</div>
                <div className="mt-2 text-xs text-zinc-400">Fornecedor: <span className="text-zinc-200">{selected.fornecedorNome}</span></div>
                <div className="text-xs text-zinc-400">Competência: <span className="text-zinc-200">{formatDateBR(selected.competencia)}</span></div>
                <div className="text-xs text-zinc-400">Próx. venc.: <span className="text-zinc-200">{formatDateBR(selected.nextVencimento)}</span></div>
                <div className="text-xs text-zinc-400">Total aberto: <span className="text-zinc-200">R$ {formatDecimalBR(selected.totalAberto, 2)}</span></div>
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

              <div className="grid grid-cols-1 gap-2">
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

                <label className="block text-xs text-zinc-400">
                  Motivo da alteração (auditoria)
                  <input
                    value={changeReason}
                    onChange={(e) => setChangeReason(e.target.value)}
                    placeholder="Ex.: Classificado conforme nota/contrato"
                    aria-label="Motivo da alteração"
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>
              </div>

              <button
                type="button"
                onClick={aprovar}
                disabled={loading}
                className="w-full px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
              >
                Aprovar
              </button>

              <div className="text-xs text-zinc-600">
                Dica Lucro Real: a aprovação aqui evita lançamentos sem classificação (impacta relatórios e centros/OS).
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
