"use client";

import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatMoneyBR } from "@/lib/decimal";

type NfEntradaResumoRow = {
  id: number;
  chave: string;
  numero: string | number | null;
  serie: string | number | null;
  emitente_nome: string | null;
  data_emissao: string | null;
  valor_total: number | string | null;
  criado_em: string | null;
  finalidade_contexto?: string | null;
};

function getErrorMessage(error: unknown, fallback: string) {
  if (!error) return fallback;
  if (typeof error === "string") return error;
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message?: unknown }).message;
    if (typeof message === "string" && message.trim()) return message;
  }
  return fallback;
}

function formatDateBR(dateIso: string | null | undefined): string {
  if (!dateIso) return "—";
  const d = new Date(`${String(dateIso).slice(0, 10)}T00:00:00`);
  if (!Number.isFinite(d.getTime())) return "—";
  return d.toLocaleDateString("pt-BR");
}

function formatFinalidadeImportada(value: string | null | undefined): string {
  const key = String(value ?? "").trim().toLowerCase();
  if (key === "materia_prima") return "Materia-prima";
  if (key === "imobilizado") return "Imobilizado";
  if (key === "consumo") return "Consumo";
  if (key === "revenda") return "Revenda";
  return key || "-";
}

function safeInt(value: string | null): number | null {
  const n = Number(String(value ?? "").trim());
  return Number.isFinite(n) ? n : null;
}

const RECENT_NFS_LIMIT = 20;

function escapePostgrestLikeTerm(value: string): string {
  return value.replace(/[\\%_]/g, (match) => `\\${match}`);
}

export default function EstoqueImportarImprimirPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const te = useTenantEmpresa();
  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const sp = useSearchParams();
  const mes = safeInt(sp.get("mes"));
  const ano = safeInt(sp.get("ano"));
  const periodoParam = sp.get("periodo");
  const usePeriodo = periodoParam === null ? Boolean(sp.get("mes") || sp.get("ano")) : periodoParam === "1";
  const emitente = String(sp.get("emitente") ?? "").trim();
  const numero = String(sp.get("numero") ?? "").trim();

  const { has, ready } = usePermissions();
  const canView =
    has("xml_import.execute") ||
    has("estoque.read") ||
    has("financeiro.read") ||
    has("financeiro.write") ||
    has("cad_itens.write") ||
    has("cad_fornecedores.write");

  const [rows, setRows] = useState<NfEntradaResumoRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const run = async () => {
      setErr(null);

      if (!ready) return;
      if (!canView) {
        setLoading(false);
        setErr("Sem permissão para imprimir notas importadas.");
        return;
      }

      if (!tenantId || !empresaId) {
        setLoading(false);
        setErr("Tenant/empresa não carregados.");
        return;
      }

      const hasMonth =
        usePeriodo &&
        Number.isFinite(ano) &&
        Number.isFinite(mes) &&
        (ano ?? 0) > 2000 &&
        (mes ?? 0) >= 1 &&
        (mes ?? 0) <= 12;

      const start = hasMonth ? new Date(Date.UTC(ano!, mes! - 1, 1)).toISOString().slice(0, 10) : null;
      const end = hasMonth ? new Date(Date.UTC(ano!, mes!, 1)).toISOString().slice(0, 10) : null;

      setLoading(true);

      try {
        let qb = supabase
          .schema("public")
          .from("nf_entrada")
          .select("id,chave,numero,serie,emitente_nome,data_emissao,valor_total,criado_em,finalidade_contexto")
          .eq("empresa_id", empresaId)
          .not("chave", "is", null)
          .order("criado_em", { ascending: false })
          .order("id", { ascending: false });

        if (start && end) {
          qb = qb.gte("data_emissao", start).lt("data_emissao", end);
        }

        if (emitente) {
          qb = qb.ilike("emitente_nome", `%${escapePostgrestLikeTerm(emitente)}%`);
        }

        if (numero) {
          qb = qb.ilike("numero", `%${escapePostgrestLikeTerm(numero)}%`);
        }

        qb = applyTenantEmpresa(qb, tenantId, empresaId);

        const { data, error } = await qb.limit(RECENT_NFS_LIMIT).returns<NfEntradaResumoRow[]>();
        if (error) throw error;
        if (!active) return;

        const all = (data ?? [])
          .map((r) => ({
            id: Number(r.id),
            chave: String(r.chave ?? ""),
            numero: r.numero ?? null,
            serie: r.serie ?? null,
            emitente_nome: r.emitente_nome ?? null,
            data_emissao: r.data_emissao ?? null,
            valor_total: r.valor_total ?? null,
            criado_em: r.criado_em ?? null,
            finalidade_contexto: r.finalidade_contexto ?? null,
          }))
          .filter((r) => Number.isFinite(r.id) && r.id > 0 && r.chave);

        if (!active) return;
        setRows(all);
      } catch (e) {
        if (!active) return;
        setRows([]);
        setErr(getErrorMessage(e, "Erro ao carregar notas para impressão."));
      } finally {
        if (!active) return;
        setLoading(false);
      }
    };

    void run();
    return () => {
      active = false;
    };
  }, [ano, canView, emitente, empresaId, mes, numero, ready, supabase, tenantId, usePeriodo]);

  const title = "Relatório — Notas importadas";
  const periodo =
    usePeriodo && Number.isFinite(ano) && Number.isFinite(mes)
      ? `${String(mes).padStart(2, "0")}/${ano}`
      : `Últimas ${RECENT_NFS_LIMIT}`;
  const filtros = [
    emitente ? `Emitente: ${emitente}` : null,
    numero ? `Número: ${numero}` : null,
  ].filter((item): item is string => Boolean(item));
  const empresaNome = te.empresa?.nome_fantasia ?? te.empresa?.razao_social ?? null;

  return (
    <div className="bg-white text-zinc-900 min-h-screen">
      <style>{`
        @media print {
          .print-hidden { display: none !important; }
          body { margin: 0 !important; }
        }
        .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }
      `}</style>

      <div className="print-hidden border-b border-zinc-200 px-6 py-3 flex items-center justify-between gap-3">
        <div className="text-[12px]">Visualização de impressão</div>
        <button type="button" onClick={() => window.print()} className="px-3 py-2 rounded-md border border-zinc-300">
          Imprimir
        </button>
      </div>

      <div className="p-10">
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="text-xl font-extrabold">{title}</div>
            <div className="mt-1 text-xs text-zinc-600">
              {usePeriodo ? "Período" : "Consulta"}: <span className="font-bold">{periodo}</span>
              {filtros.length > 0 ? <span> • {filtros.join(" • ")}</span> : null}
              {empresaNome ? <span> • Empresa: {empresaNome}</span> : null}
            </div>
          </div>

          <div className="text-right">
            <div className="text-xs text-zinc-600">Total</div>
            <div className="text-xl font-extrabold">{rows.length}</div>
          </div>
        </div>

        {loading ? (
          <div className="mt-5 text-zinc-600">Carregando...</div>
        ) : err ? (
          <div className="mt-5 text-rose-700">{err}</div>
        ) : rows.length === 0 ? (
          <div className="mt-5 text-zinc-600">Nenhuma nota encontrada.</div>
        ) : (
          <div className="mt-4">
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr>
                  <th className="w-[92px] border border-zinc-300 bg-zinc-100 px-2 py-1 text-left">Emissão</th>
                  <th className="w-[120px] border border-zinc-300 bg-zinc-100 px-2 py-1 text-left">Série/Número</th>
                  <th className="border border-zinc-300 bg-zinc-100 px-2 py-1 text-left">Emitente</th>
                  <th className="w-[110px] border border-zinc-300 bg-zinc-100 px-2 py-1 text-left">Finalidade</th>
                  <th className="border border-zinc-300 bg-zinc-100 px-2 py-1 text-left">Chave</th>
                  <th className="w-[120px] border border-zinc-300 bg-zinc-100 px-2 py-1 text-right">Valor</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((nf) => {
                  const serieNum = `${nf.serie ?? "—"} / ${nf.numero ?? "—"}`;
                  return (
                    <tr key={nf.id}>
                      <td className="border border-zinc-300 px-2 py-1">{formatDateBR(nf.data_emissao)}</td>
                      <td className="border border-zinc-300 px-2 py-1">{serieNum}</td>
                      <td className="border border-zinc-300 px-2 py-1">{nf.emitente_nome ?? "—"}</td>
                      <td className="border border-zinc-300 px-2 py-1">{formatFinalidadeImportada(nf.finalidade_contexto)}</td>
                      <td className="mono border border-zinc-300 px-2 py-1 text-[11px]">{nf.chave || "—"}</td>
                      <td className="border border-zinc-300 px-2 py-1 text-right">R$ {formatMoneyBR(Number(nf.valor_total ?? 0))}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
