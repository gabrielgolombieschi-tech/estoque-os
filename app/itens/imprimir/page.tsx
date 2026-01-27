"use client";

import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { applyTenant } from "@/lib/db/scopes";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny } from "@/lib/auth/capabilities";

type ItemTipo = "produto" | "servico" | "despesa";
type ItemFinalidade = "consumo" | "materia_prima" | "revenda" | "imobilizado" | "outros";

type PrintItem = {
  id: number;
  codigo_interno: string;
  nome: string;
  tipo: ItemTipo;
  finalidade: string | null;
  ativo: boolean;
  fornecedor_id: number | null;
};

type FornecedorRow = { id: number; nome: string | null };

const PRINT_PAGE_SIZE = 1000;
const FORNECEDORES_PAGE_SIZE = 1000;
const ROWS_FIRST_PAGE = 14;
const ROWS_OTHER_PAGES = 17;

function parseAtivoParam(v: string | null): "todos" | "ativos" | "inativos" {
  const s = String(v ?? "").trim().toLowerCase();
  if (s === "ativos" || s === "inativos") return s;
  return "todos";
}

function normalizeQ(v: string | null) {
  return String(v ?? "")
    .trim()
    .replace(/,/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function chunk<T>(items: T[], size: number): T[][] {
  if (items.length === 0) return [];
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

function formatDateTimePtBr(d: Date) {
  return d.toLocaleString("pt-BR");
}

function formatFinalidade(v: string | null | undefined) {
  if (!v) return "-";
  return String(v).replace(/_/g, " ");
}

function formatTipo(v: string) {
  return v === "servico" ? "Serviço" : v === "despesa" ? "Despesa" : "Produto";
}

export default function ItensImprimirPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const tenantEmpresaLoading = te.loading;
  const empresaPapel = String(te.empresa?.papel ?? "")
    .trim()
    .toUpperCase();

  const sp = useSearchParams();
  const id = sp.get("id");
  const q = sp.get("q");
  const codigo = sp.get("codigo");
  const produto = sp.get("produto");
  const fornecedorId = sp.get("fornecedor_id");
  const tipo = sp.get("tipo");
  const finalidade = sp.get("finalidade");
  const ativo = sp.get("ativo"); // "todos" | "ativos" | "inativos"

  const emittedAt = useMemo(() => formatDateTimePtBr(new Date()), []);
  const emittedBy = te.sessionEmail ?? te.email ?? null;

  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canViewByEmpresaPapel = Boolean(
    empresaPapel && ["ADMIN", "COORDENACAO", "ALMOXARIFADO", "FINANCEIRO", "COMPRAS"].includes(empresaPapel)
  );
  const canView = requireAny(capabilities, ["estoque.read", "os.read", "cad_itens.write"]) || canViewByEmpresaPapel;

  const [rows, setRows] = useState<PrintItem[]>([]);
  const [count, setCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [fornecedorFiltroNome, setFornecedorFiltroNome] = useState<string | null>(null);
  const [fornecedoresById, setFornecedoresById] = useState<Record<number, string>>({});

  useEffect(() => {
    const run = async () => {
      setErr(null);
      if (tenantEmpresaLoading) return;
      if (!tenantId) {
        setErr("Tenant não carregado.");
        setLoading(false);
        return;
      }

      setLoading(true);

      try {
        const tipoNorm = (String(tipo ?? "").trim() as ItemTipo | "") || "";
        const finalidadeNorm = (String(finalidade ?? "").trim() as ItemFinalidade | "") || "";
        const ativoNorm = parseAtivoParam(ativo);
        const codigoNorm = normalizeQ(codigo);
        const produtoNorm = String(produto ?? "").trim();
        const qNorm = normalizeQ(q);

        let qb = supabase
          .from("itens")
          .select("id,codigo_interno,nome,tipo,finalidade,ativo,fornecedor_id", { count: "exact" });
        qb = applyTenant(qb, tenantId);

        if (id) {
          const parsed = Number(id);
          if (!Number.isFinite(parsed)) throw new Error("Id inválido.");
          qb = qb.eq("id", parsed);
        }

        if (fornecedorId) {
          const parsed = Number(fornecedorId);
          if (!Number.isFinite(parsed)) throw new Error("Fornecedor inválido.");
          qb = qb.eq("fornecedor_id", parsed);
        }

        if (tipoNorm) qb = qb.eq("tipo", tipoNorm);
        if (finalidadeNorm) qb = qb.eq("finalidade", finalidadeNorm);
        if (ativoNorm === "ativos") qb = qb.eq("ativo", true);
        else if (ativoNorm === "inativos") qb = qb.eq("ativo", false);

        if (codigoNorm && codigoNorm.trim()) {
          const cc = codigoNorm.trim();
          qb = qb.or(`codigo_interno.ilike.%${cc}%,codigo_barras.ilike.%${cc}%`);
        }

        if (produtoNorm && produtoNorm.trim()) {
          const pp = produtoNorm.trim();
          qb = qb.ilike("nome", `%${pp}%`);
        }

        if (!codigoNorm && !produtoNorm && qNorm && qNorm.trim()) {
          const qq = qNorm.trim();
          qb = qb.or(`codigo_interno.ilike.%${qq}%,nome.ilike.%${qq}%`);
        }

        qb = qb.order("nome", { ascending: true });

        const pageSize = PRINT_PAGE_SIZE;
        let from = 0;
        let rowsAll: PrintItem[] = [];
        let totalCount: number | null = null;

        while (true) {
          const { data, error, count: c } = await qb.range(from, from + pageSize - 1);
          if (error) throw error;
          if (totalCount == null && typeof c === "number") totalCount = c;
          const chunkRows = (data ?? []) as unknown as PrintItem[];
          rowsAll = rowsAll.concat(chunkRows);
          if (!data || chunkRows.length < pageSize) break;
          from += pageSize;
        }

        setCount(totalCount ?? rowsAll.length);
        setRows(rowsAll);

        const fornecedorIds = Array.from(
          new Set(rowsAll.map((r) => r.fornecedor_id).filter((v): v is number => Number.isFinite(v as number)))
        );

        const map: Record<number, string> = {};
        for (const group of chunk(fornecedorIds, FORNECEDORES_PAGE_SIZE)) {
          const { data: fs, error: fErr } = await applyTenant(
            supabase.from("fornecedores").select("id,nome").in("id", group),
            tenantId
          );
          if (fErr) continue;
          for (const row of (fs ?? []) as unknown as FornecedorRow[]) {
            if (!Number.isFinite(row?.id)) continue;
            map[Number(row.id)] = String(row?.nome ?? "").trim() || `#${row.id}`;
          }
        }
        setFornecedoresById(map);

        if (fornecedorId) {
          const parsed = Number(fornecedorId);
          if (!Number.isFinite(parsed)) {
            setFornecedorFiltroNome("(não encontrado)");
          } else {
            const { data: f, error: fErr } = await applyTenant(
              supabase.from("fornecedores").select("nome").eq("id", parsed),
              tenantId
            ).maybeSingle();
            if (fErr) setFornecedorFiltroNome("(não encontrado)");
            else setFornecedorFiltroNome(f?.nome ? String(f.nome) : "(não encontrado)");
          }
        } else {
          setFornecedorFiltroNome(null);
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Erro ao carregar itens.";
        setErr(msg);
        setRows([]);
        setCount(0);
        setFornecedoresById({});
        setFornecedorFiltroNome(null);
      } finally {
        setLoading(false);
      }
    };

    void run();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantEmpresaLoading, tenantId, id, q, codigo, produto, fornecedorId, tipo, finalidade, ativo]);

  const pages = useMemo(() => {
    if (rows.length === 0) return [[] as PrintItem[]];
    const first = rows.slice(0, ROWS_FIRST_PAGE);
    const rest = rows.slice(ROWS_FIRST_PAGE);
    return [first, ...chunk(rest, ROWS_OTHER_PAGES)];
  }, [rows]);
  const totalPages = pages.length;

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-900">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-900">Acesso negado.</div>;
  }

  const filtros: Array<{ label: string; value: string }> = [];
  const qNorm = normalizeQ(q);
  const codigoNorm = normalizeQ(codigo);
  const produtoNorm = String(produto ?? "").trim();
  const tipoNorm = (String(tipo ?? "").trim() as ItemTipo | "") || "";
  const finalidadeNorm = (String(finalidade ?? "").trim() as ItemFinalidade | "") || "";
  const ativoNorm = parseAtivoParam(ativo);
  if (id) filtros.push({ label: "Id", value: id });
  if (codigoNorm) filtros.push({ label: "Código", value: codigoNorm });
  if (produtoNorm) filtros.push({ label: "Produto", value: produtoNorm });
  if (!codigoNorm && !produtoNorm && qNorm) filtros.push({ label: "Código/nome", value: qNorm });
  if (fornecedorId) filtros.push({ label: "Fornecedor", value: fornecedorFiltroNome ?? `#${fornecedorId}` });
  if (tipoNorm) filtros.push({ label: "Tipo", value: formatTipo(tipoNorm) });
  if (finalidadeNorm) filtros.push({ label: "Finalidade", value: String(finalidadeNorm).replace(/_/g, " ") });
  if (ativoNorm !== "todos") filtros.push({ label: "Ativo", value: ativoNorm === "ativos" ? "Ativos" : "Inativos" });

  return (
    <div className="print-root">
      <style jsx global>{`
        @page {
          size: A4 landscape;
          margin: 10mm;
        }
        * {
          -webkit-print-color-adjust: exact;
          print-color-adjust: exact;
        }

        html,
        body {
          background: #fff !important;
          color: #111 !important;
          height: auto !important;
        }
        body {
          margin: 0 !important;
          font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji",
            "Segoe UI Emoji";
          font-size: 12px;
        }

        .print-hidden {
          display: block;
        }
        @media print {
          .print-hidden {
            display: none !important;
          }
        }

        .print-sheet {
          width: 297mm;
          max-width: 297mm;
          margin: 0 auto;
          background: #fff;
          color: #111;
        }

        .print-muted {
          color: #333 !important;
        }

        table {
          width: 100%;
          border-collapse: collapse;
          color: #111;
          table-layout: fixed;
          font-size: 11px;
        }
        th,
        td {
          white-space: nowrap;
        }
        thead {
          display: table-header-group;
        }
        tfoot {
          display: table-footer-group;
        }
        th {
          text-align: left;
          font-weight: 700;
          color: #111;
          border-bottom: 1px solid #999;
          padding: 6px 8px;
          background: #f0f0f0;
        }
        td {
          color: #111;
          border-bottom: 1px solid #ddd;
          padding: 6px 8px;
          vertical-align: top;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        tr {
          break-inside: avoid;
          page-break-inside: avoid;
        }
        tbody tr:nth-child(even) {
          background: #f3f3f3;
        }

        .badge {
          display: inline-flex;
          border-radius: 9999px;
          padding: 2px 8px;
          font-size: 10px;
          font-weight: 700;
          border: 1px solid #bdbdbd;
          line-height: 1.1;
          white-space: nowrap;
        }
        .badge--active {
          border-color: #1b7f3a;
          background: #d9f5e3;
          color: #0d3b1c;
        }
        .badge--inactive {
          border-color: #bdbdbd;
          background: #f3f3f3;
          color: #111;
        }

        /* Screen-only scroll if needed; disable in print */
        .screen-scroll-wrapper {
          overflow-x: auto;
        }
        @media print {
          html,
          body {
            height: auto !important;
          }
          body {
            margin: 0 !important;
          }
          .print-sheet {
            width: auto !important;
            max-width: none !important;
            margin: 0 !important;
          }
          .screen-scroll-wrapper {
            overflow: visible !important;
          }
        }

        /* Force page breaks */
        .page {
          break-after: page;
          page-break-after: always;
        }
        .page:last-child {
          break-after: auto;
          page-break-after: auto;
        }
      `}</style>

      <div className="print-hidden border-b border-zinc-400 px-6 py-3 flex items-center justify-between gap-3 bg-white">
        <div className="text-[12px] text-zinc-900">Visualização de impressão</div>
        <button type="button" onClick={() => window.print()} className="px-3 py-2 rounded-md border border-zinc-400">
          Imprimir
        </button>
      </div>

      <div className="print-sheet">
        {loading && (
          <section className="page">
            <div style={{ padding: "10mm" }}>
              <div style={{ fontWeight: 800, fontSize: 16, color: "#111" }}>Carregando para impressão...</div>
              <div className="print-muted" style={{ marginTop: 6 }}>
                Buscando todos os registros em lotes.
              </div>
            </div>
          </section>
        )}

        {!loading && err && (
          <section className="page">
            <div style={{ padding: "10mm", color: "#b00020", fontSize: 12 }}>{err}</div>
          </section>
        )}

        {!loading && !err && (
          <>
            {pages.map((pageRows, pageIdx) => (
              <section className="page" key={`p-${pageIdx}`}>
                {pageIdx === 0 ? (
                  <div style={{ padding: "10mm 10mm 6mm 10mm" }}>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                        <img src="/Segau.png" alt="Segau" style={{ height: 42, width: "auto" }} />
                        <div>
                          <div className="print-muted" style={{ fontSize: 11, letterSpacing: "0.06em", textTransform: "uppercase" }}>
                            Sistema ERP
                          </div>
                          <div style={{ fontSize: 20, fontWeight: 800, color: "#111" }}>Relatório de Itens</div>
                          <div className="print-muted" style={{ fontSize: 12, marginTop: 2 }}>
                            Emitido em <span style={{ fontWeight: 700 }}>{emittedAt}</span>
                            {emittedBy ? <span> • Emitido por: {emittedBy}</span> : null}
                          </div>
                          {te.empresa?.nome_fantasia || te.empresa?.razao_social ? (
                            <div className="print-muted" style={{ fontSize: 12 }}>
                              Empresa: {te.empresa?.nome_fantasia ?? te.empresa?.razao_social}
                            </div>
                          ) : null}
                        </div>
                      </div>

                      <div style={{ textAlign: "right" }}>
                        <div className="print-muted" style={{ fontSize: 12 }}>
                          Total
                        </div>
                        <div style={{ fontSize: 20, fontWeight: 800, color: "#111" }}>{count || rows.length}</div>
                      </div>
                    </div>

                    <div style={{ marginTop: 10, display: "flex", flexWrap: "wrap", gap: 6 }}>
                      {filtros.length === 0 ? (
                        <span className="print-muted" style={{ fontSize: 12 }}>
                          Sem filtros aplicados.
                        </span>
                      ) : (
                        filtros.map((f) => (
                          <span
                            key={`${f.label}:${f.value}`}
                            style={{
                              display: "inline-flex",
                              gap: 6,
                              alignItems: "center",
                              border: "1px solid #bdbdbd",
                              background: "#f3f3f3",
                              borderRadius: 999,
                              padding: "3px 10px",
                              fontSize: 11,
                              color: "#111",
                            }}
                          >
                            <span className="print-muted">{f.label}:</span>
                            <span style={{ fontWeight: 700 }}>{f.value}</span>
                          </span>
                        ))
                      )}
                    </div>
                  </div>
                ) : (
                  <div style={{ padding: "8mm 10mm 4mm 10mm" }}>
                    <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 16 }}>
                      <div>
                        <div style={{ fontSize: 16, fontWeight: 800, color: "#111" }}>Relatório de Itens</div>
                        <div className="print-muted" style={{ fontSize: 12, marginTop: 2 }}>
                          Emitido em {emittedAt}
                        </div>
                      </div>
                      <div className="print-muted" style={{ fontSize: 12 }}>
                        Página {pageIdx + 1} de {totalPages}
                      </div>
                    </div>
                  </div>
                )}

                <div className="screen-scroll-wrapper" style={{ padding: "0 10mm" }}>
                  <table>
                    <thead>
                      <tr>
                        <th style={{ width: "18mm" }}>ID</th>
                        <th style={{ width: "36mm" }}>Código</th>
                        <th>Nome</th>
                        <th style={{ width: "24mm" }}>Tipo</th>
                        <th style={{ width: "32mm" }}>Finalidade</th>
                        <th style={{ width: "60mm" }}>Fornecedor</th>
                        <th style={{ width: "22mm" }}>Ativo</th>
                      </tr>
                    </thead>
                    <tbody>
                      {pageRows.map((r) => (
                        <tr key={r.id}>
                          <td style={{ fontVariantNumeric: "tabular-nums" }}>{r.id}</td>
                          <td>{r.codigo_interno}</td>
                          <td>{r.nome}</td>
                          <td>{formatTipo(r.tipo)}</td>
                          <td>{formatFinalidade(r.finalidade)}</td>
                          <td>{r.fornecedor_id ? fornecedoresById[r.fornecedor_id] ?? `#${r.fornecedor_id}` : "-"}</td>
                          <td>
                            <span className={`badge ${r.ativo ? "badge--active" : "badge--inactive"}`}>
                              {r.ativo ? "ATIVO" : "INATIVO"}
                            </span>
                          </td>
                        </tr>
                      ))}

                      {rows.length === 0 && (
                        <tr>
                          <td colSpan={7} className="print-muted" style={{ padding: "10px 9px" }}>
                            Nenhum item encontrado.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>

                <div
                  style={{
                    padding: "6mm 10mm 10mm 10mm",
                    display: "flex",
                    justifyContent: "space-between",
                    gap: 12,
                    flexWrap: "wrap",
                  }}
                >
                  <div className="print-muted" style={{ fontSize: 11 }}>
                    Sistema ERP
                  </div>
                  <div className="print-muted" style={{ fontSize: 11 }}>
                    Página {pageIdx + 1} de {totalPages} • Total: {count || rows.length}
                  </div>
                </div>
              </section>
            ))}
          </>
        )}
      </div>
    </div>
  );
}
