"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR, parseDecimalBR } from "@/lib/decimal";

type CreditoRow = {
  tenant_id: string;
  empresa_id: string;
  credito_id: string;
  os_id: number | null;
  numero_os: string | null;
  cliente_id: number;
  cliente_nome: string | null;
  documento: string | null;
  documento_norm: string | null;
  documento_raiz: string | null;
  grupo_cliente: string;
  unidade_id: number | null;
  unidade_nome: string | null;
  status: string;
  origem: string;
  descricao: string | null;
  data_competencia: string | null;
  pedido_compra_cliente: string | null;
  pedido_recebido_em: string | null;
  documento_fiscal_id: string | null;
  documento_modelo: string | null;
  documento_serie: string | null;
  documento_numero: string | null;
  responsavel_nome: string | null;
  responsavel_cliente_nome: string | null;
  proximo_contato_date: string | null;
  observacao: string | null;
  valor_estimado: number | string | null;
  valor_confirmado: number | string | null;
  valor_exposicao: number | string | null;
  valor_origem: string | null;
  dias_em_aberto: number | null;
  created_at: string;
};

type ClienteRow = { id: number; nome: string; documento: string | null; documento_norm: string | null; ativo: boolean | null };
type UnidadeRow = { id: number; cliente_id: number; nome: string; codigo: string | null; ativo: boolean };
type Aba = "carteira" | "avulso";

const BASE_PATH = "/financeiro/venda-a-credito";
const STATUS_ABERTOS = new Set(["ABERTO", "OC_RECEBIDA"]);
const STATUS_LABEL: Record<string, string> = {
  ABERTO: "Aberto",
  OC_RECEBIDA: "OC recebida",
  FATURADO: "Faturado",
  RECEBIDO: "Recebido",
  PERDIDO: "Perdido",
  CANCELADO: "Cancelado",
};
const ORIGEM_LABEL: Record<string, string> = {
  SERVICO_URGENCIA: "Serviço de urgência",
  MATERIAL_ANTECIPADO: "Material antecipado",
  OS_SEM_OC: "OS sem OC",
  OS_CONCLUIDA_SEM_NF: "OS concluída sem NF",
  AVULSO_LEGADO: "Avulso legado",
  IMPORTACAO_CSV: "Importação CSV",
  OUTRO: "Outro",
};

function n(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const [year, month, day] = value.slice(0, 10).split("-");
  return year && month && day ? `${day}/${month}/${year}` : value;
}

function normalize(value: unknown): string {
  return String(value ?? "").trim().toUpperCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function errorText(value: unknown, fallback: string): string {
  if (value instanceof Error && value.message) return value.message;
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const message = typeof record.message === "string" ? record.message.trim() : "";
    const code = typeof record.code === "string" ? record.code.trim() : "";
    if (message && code) return `${message} (${code})`;
    if (message) return message;
    if (code) return code;
  }
  return fallback;
}

function csvCell(value: unknown): string {
  return `"${String(value ?? "").replace(/"/g, '""')}"`;
}

function parseCsvLine(line: string, separator: string): string[] {
  const result: string[] = [];
  let current = "";
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    if (char === '"') {
      if (quoted && line[i + 1] === '"') { current += '"'; i += 1; }
      else quoted = !quoted;
    } else if (char === separator && !quoted) {
      result.push(current.trim()); current = "";
    } else current += char;
  }
  result.push(current.trim());
  return result;
}

function parseCsv(text: string): Array<Record<string, string>> {
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/).filter((line) => line.trim());
  if (lines.length < 2) return [];
  const separator = (lines[0].match(/;/g)?.length ?? 0) >= (lines[0].match(/,/g)?.length ?? 0) ? ";" : ",";
  const headers = parseCsvLine(lines[0], separator).map((header) => normalize(header).toLowerCase().replace(/\s+/g, "_"));
  return lines.slice(1).map((line) => {
    const values = parseCsvLine(line, separator);
    return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ""]));
  });
}

function statusClass(status: string): string {
  if (status === "ABERTO") return "border-amber-500/30 bg-amber-500/10 text-amber-200";
  if (status === "OC_RECEBIDA") return "border-sky-500/30 bg-sky-500/10 text-sky-200";
  if (status === "FATURADO") return "border-violet-500/30 bg-violet-500/10 text-violet-200";
  if (status === "RECEBIDO") return "border-emerald-500/30 bg-emerald-500/10 text-emerald-200";
  return "border-zinc-700 bg-zinc-900 text-zinc-300";
}

function carteiraBadge(row: CreditoRow): { label: string; className: string } {
  if (row.status === "OC_RECEBIDA") return { label: "OC recebida", className: "vc-badge-emerald border-emerald-500/20 bg-emerald-500/10 text-emerald-300" };
  if (row.status === "FATURADO") return { label: "Faturado", className: "vc-badge-violet border-violet-500/20 bg-violet-500/10 text-violet-300" };
  if (row.status === "RECEBIDO") return { label: "Recebido", className: "vc-badge-sky border-sky-500/20 bg-sky-500/10 text-sky-300" };
  if (n(row.dias_em_aberto) >= 30) return { label: "Dívida antiga", className: "vc-badge-neutral border-zinc-600/60 bg-zinc-700/30 text-zinc-300" };
  if (row.origem === "SERVICO_URGENCIA") return { label: "Urgência", className: "vc-badge-amber border-amber-500/20 bg-amber-500/10 text-amber-300" };
  if (row.origem === "MATERIAL_ANTECIPADO") return { label: "Material antecip.", className: "vc-badge-cyan border-cyan-500/20 bg-cyan-500/10 text-cyan-300" };
  return {
    label: STATUS_LABEL[row.status] ?? "Sem OC",
    className: `${row.status === "ABERTO" ? "vc-badge-amber" : "vc-badge-neutral"} ${statusClass(row.status)}`,
  };
}

export default function VendaCreditoClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const searchParams = useSearchParams();
  const filterQueryRef = useRef(searchParams.toString());
  const supabase = useMemo(() => getSupabaseBrowser(), []);
  const [rows, setRows] = useState<CreditoRow[]>([]);
  const [clientes, setClientes] = useState<ClienteRow[]>([]);
  const [unidades, setUnidades] = useState<UnidadeRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [manual, setManual] = useState({ clienteId: "", unidadeId: "", descricao: "", valor: "", data: new Date().toISOString().slice(0, 10), origem: "AVULSO_LEGADO" });
  const [importing, setImporting] = useState(false);

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id ?? null : null);
  const empresaRole = normalize(te.empresa?.papel ?? te.empresas.find((e) => e.id === empresaId)?.papel);
  const canWrite = Boolean(te.has("financeiro.write")) || ["ADMIN", "DIRETOR", "FINANCEIRO"].includes(empresaRole);
  const canView = canWrite || Boolean(te.has("financeiro.read"));
  const canDelete = ["ADMIN", "DIRETOR"].includes(empresaRole);
  const ready = Boolean(te.sessionUserId && tenantId && empresaId && canView);
  const aba: Aba = searchParams.get("aba") === "avulso" ? "avulso" : "carteira";

  useEffect(() => { if (!te.loading && te.sessionUserId && !canView) router.replace("/forbidden"); }, [canView, router, te.loading, te.sessionUserId]);
  useEffect(() => { filterQueryRef.current = searchParams.toString(); }, [searchParams]);

  const setParam = useCallback((key: string, value: string) => {
    const params = new URLSearchParams(filterQueryRef.current);
    if (!value || value === "TODOS") params.delete(key); else params.set(key, value);
    filterQueryRef.current = params.toString();
    router.replace(params.toString() ? `${BASE_PATH}?${params}` : BASE_PATH, { scroll: false });
  }, [router]);

  const load = useCallback(async () => {
    if (!ready || !tenantId || !empresaId) return;
    setLoading(true); setError(null);
    try {
      const [creditosRes, clientesRes, unidadesRes] = await Promise.all([
        applyTenantEmpresa(supabase.schema("r").from("r_venda_credito").select("*"), tenantId, empresaId).order("data_competencia", { ascending: false }),
        applyTenantEmpresa(supabase.from("clientes").select("id,nome,documento,documento_norm,ativo"), tenantId, empresaId).order("nome"),
        applyTenantEmpresa(supabase.from("cliente_unidades").select("id,cliente_id,nome,codigo,ativo").eq("ativo", true), tenantId, empresaId).order("nome"),
      ]);
      if (creditosRes.error) throw new Error(`Carteira: ${errorText(creditosRes.error, "falha na consulta")}`);
      if (clientesRes.error) throw new Error(`Clientes: ${errorText(clientesRes.error, "falha na consulta")}`);
      if (unidadesRes.error) throw new Error(`Unidades: ${errorText(unidadesRes.error, "falha na consulta")}`);
      setRows((creditosRes.data ?? []) as CreditoRow[]);
      setClientes((clientesRes.data ?? []) as ClienteRow[]);
      setUnidades((unidadesRes.data ?? []) as UnidadeRow[]);
    } catch (e: unknown) {
      setError(errorText(e, "Erro ao carregar Venda a Crédito."));
    } finally { setLoading(false); }
  }, [empresaId, ready, supabase, tenantId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const filters = {
    q: normalize(searchParams.get("q")),
    grupo: searchParams.get("grupo") ?? "",
    cliente: searchParams.get("cliente") ?? "",
    unidade: searchParams.get("unidade") ?? "",
    origem: searchParams.get("origem") ?? "",
    status: searchParams.get("status") ?? "",
    responsavel: searchParams.get("responsavel") ?? "",
    dias: Number(searchParams.get("dias") ?? 0),
    semOc: searchParams.get("sem_oc") === "1",
  };

  const filteredRows = useMemo(() => rows.filter((row) => {
    if (filters.grupo && row.grupo_cliente !== filters.grupo) return false;
    if (filters.cliente && String(row.cliente_id) !== filters.cliente) return false;
    if (filters.unidade && String(row.unidade_id ?? "") !== filters.unidade) return false;
    if (filters.origem && row.origem !== filters.origem) return false;
    if (filters.status && row.status !== filters.status) return false;
    if (filters.responsavel && normalize(row.responsavel_nome) !== filters.responsavel) return false;
    if (filters.dias > 0 && n(row.dias_em_aberto) < filters.dias) return false;
    if (filters.semOc && row.pedido_compra_cliente?.trim()) return false;
    if (filters.q) {
      const haystack = normalize([row.numero_os,row.cliente_nome,row.documento,row.unidade_nome,row.descricao,row.pedido_compra_cliente,row.documento_numero].join(" "));
      if (!haystack.includes(filters.q)) return false;
    }
    return true;
  }), [filters.cliente, filters.dias, filters.grupo, filters.origem, filters.q, filters.responsavel, filters.semOc, filters.status, filters.unidade, rows]);

  const groups = useMemo(() => {
    const map = new Map<string, CreditoRow[]>();
    for (const row of filteredRows) map.set(row.grupo_cliente, [...(map.get(row.grupo_cliente) ?? []), row]);
    return Array.from(map.entries()).sort((a, b) => {
      const av = a[1].reduce((sum, row) => sum + n(row.valor_exposicao), 0);
      const bv = b[1].reduce((sum, row) => sum + n(row.valor_exposicao), 0);
      return bv - av;
    });
  }, [filteredRows]);

  const kpis = useMemo(() => {
    const active = filteredRows.filter((row) => STATUS_ABERTOS.has(row.status));
    const semOc = active.filter((row) => row.status === "ABERTO");
    const comOc = active.filter((row) => row.status === "OC_RECEBIDA");
    const parados = active.filter((row) => n(row.dias_em_aberto) >= 30);
    return {
      total: active.reduce((sum, row) => sum + n(row.valor_exposicao), 0),
      totalCount: active.length,
      aberto: semOc.reduce((sum, row) => sum + n(row.valor_exposicao), 0),
      abertoCount: semOc.length,
      oc: comOc.reduce((sum, row) => sum + n(row.valor_exposicao), 0),
      ocCount: comOc.length,
      clientes: new Set(active.map((row) => row.grupo_cliente)).size,
      parados: parados.length,
      paradosValor: parados.reduce((sum, row) => sum + n(row.valor_exposicao), 0),
    };
  }, [filteredRows]);

  const runAction = useCallback(async (id: string, fn: () => Promise<void>, success: string) => {
    setBusyId(id); setError(null); setOk(null);
    try { await fn(); setOk(success); await load(); }
    catch (e: unknown) { setError(errorText(e, "Não foi possível concluir a ação.")); }
    finally { setBusyId(null); }
  }, [load]);

  async function registrarOc(row: CreditoRow) {
    const numero = window.prompt("Número da ordem de compra do cliente:", row.pedido_compra_cliente ?? "");
    if (!numero?.trim()) return;
    const data = window.prompt("Data de recebimento da OC (AAAA-MM-DD):", new Date().toISOString().slice(0, 10));
    if (data === null) return;
    const valorTexto = window.prompt("Valor acordado (opcional):", row.valor_confirmado ? String(row.valor_confirmado) : "");
    if (valorTexto === null) return;
    const valor = valorTexto.trim() ? parseDecimalBR(valorTexto) : null;
    await runAction(row.credito_id, async () => {
      const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_registrar_oc", { p_credito_id: row.credito_id, p_numero: numero, p_data: data || null, p_valor_confirmado: valor });
      if (rpcError) throw rpcError;
    }, "OC registrada.");
  }

  async function editarCobranca(row: CreditoRow) {
    const data = window.prompt("Próximo contato (AAAA-MM-DD, vazio para remover):", row.proximo_contato_date ?? "");
    if (data === null) return;
    const contato = window.prompt("Contato responsável no cliente:", row.responsavel_cliente_nome ?? "");
    if (contato === null) return;
    const observacao = window.prompt("Observação da cobrança:", row.observacao ?? "");
    if (observacao === null) return;
    const valorTexto = window.prompt("Valor acordado (vazio mantém como estimativa):", row.valor_confirmado ? String(row.valor_confirmado) : "");
    if (valorTexto === null) return;
    const valor = valorTexto.trim() ? parseDecimalBR(valorTexto) : null;
    await runAction(row.credito_id, async () => {
      const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_atualizar", { p_credito_id: row.credito_id, p_proximo_contato: data || null, p_observacao: observacao, p_responsavel_cliente_nome: contato, p_valor_confirmado: valor });
      if (rpcError) throw rpcError;
    }, "Cobrança atualizada.");
  }

  async function vincularNf(row: CreditoRow) {
    if (!tenantId || !empresaId) return;
    const query = applyTenantEmpresa(
      supabase.schema("f").from("documento_fiscal").select("id,numero,serie,modelo,emissao_date,valor_total").eq("operacao", "SAIDA").eq("cliente_id", row.cliente_id).is("deleted_at", null),
      tenantId, empresaId
    ).order("emissao_date", { ascending: false }).limit(10);
    const { data, error: docsError } = await query;
    if (docsError) { setError(docsError.message); return; }
    const options = (data ?? []).map((doc) => `${doc.numero ?? "s/n"} · ${formatDate(doc.emissao_date)} · R$ ${formatMoneyBR(n(doc.valor_total))} · ${doc.id}`).join("\n");
    const id = window.prompt(`Cole o UUID da NF. Últimas notas deste cliente:\n\n${options}`, row.documento_fiscal_id ?? "");
    if (!id?.trim()) return;
    await runAction(row.credito_id, async () => {
      const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_vincular_documento", { p_credito_id: row.credito_id, p_documento_fiscal_id: id.trim() });
      if (rpcError) throw rpcError;
    }, "Nota fiscal vinculada.");
  }

  async function encerrar(row: CreditoRow, status: "PERDIDO" | "CANCELADO") {
    if (!window.confirm(`${status === "PERDIDO" ? "Marcar como perdido" : "Cancelar"} este registro? Ele continuará no histórico.`)) return;
    await runAction(row.credito_id, async () => {
      const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_encerrar", { p_credito_id: row.credito_id, p_status: status });
      if (rpcError) throw rpcError;
    }, status === "PERDIDO" ? "Registro marcado como perdido." : "Registro cancelado.");
  }

  async function handleManualSubmit(event: FormEvent) {
    event.preventDefault();
    const valor = parseDecimalBR(manual.valor);
    if (!manual.clienteId || !manual.descricao.trim() || !Number.isFinite(valor) || valor < 0) { setError("Preencha cliente, descrição e um valor válido."); return; }
    await runAction("manual", async () => {
      const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_criar_avulso", {
        p_cliente_id: Number(manual.clienteId), p_unidade_id: manual.unidadeId ? Number(manual.unidadeId) : null,
        p_descricao: manual.descricao, p_valor: valor, p_data_competencia: manual.data || null, p_origem: manual.origem,
      });
      if (rpcError) throw rpcError;
      setManual({ clienteId: "", unidadeId: "", descricao: "", valor: "", data: new Date().toISOString().slice(0, 10), origem: "AVULSO_LEGADO" });
    }, "Lançamento avulso criado.");
  }

  async function handleCsv(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]; event.target.value = "";
    if (!file) return;
    setImporting(true); setError(null); setOk(null);
    try {
      const parsed = parseCsv(await file.text());
      if (!parsed.length) throw new Error("CSV vazio ou sem linhas de dados.");
      const clientById = new Map(clientes.map((c) => [String(c.id), c]));
      const clientByDoc = new Map(clientes.filter((c) => c.documento_norm).map((c) => [String(c.documento_norm), c]));
      const clientByName = new Map(clientes.map((c) => [normalize(c.nome), c]));
      let imported = 0;
      const failures: string[] = [];
      for (let index = 0; index < parsed.length; index += 1) {
        const item = parsed[index];
        const doc = String(item.documento ?? item.cnpj ?? "").replace(/\D/g, "");
        const client = clientById.get(String(item.cliente_id ?? "")) ?? clientByDoc.get(doc) ?? clientByName.get(normalize(item.cliente ?? item.cliente_nome));
        if (!client) { failures.push(`linha ${index + 2}: cliente não encontrado`); continue; }
        const unidade = unidades.find((u) => u.cliente_id === client.id && (String(u.id) === String(item.unidade_id ?? "") || normalize(u.nome) === normalize(item.unidade)));
        const valor = parseDecimalBR(item.valor ?? item.valor_confirmado ?? "");
        const descricao = item.descricao ?? item.historico ?? item.observacao ?? "";
        if (!descricao.trim() || !Number.isFinite(valor) || valor < 0) { failures.push(`linha ${index + 2}: descrição/valor inválido`); continue; }
        const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_criar_avulso", {
          p_cliente_id: client.id, p_unidade_id: unidade?.id ?? null, p_descricao: descricao, p_valor: valor,
          p_data_competencia: item.data_competencia || item.data || null, p_origem: "IMPORTACAO_CSV",
        });
        if (rpcError) failures.push(`linha ${index + 2}: ${rpcError.message}`); else imported += 1;
      }
      setOk(`${imported} lançamento(s) importado(s).${failures.length ? ` ${failures.length} rejeitado(s): ${failures.slice(0, 5).join("; ")}` : ""}`);
      await load();
    } catch (e: unknown) { setError(e instanceof Error ? e.message : "Falha na importação."); }
    finally { setImporting(false); }
  }

  function exportCsv() {
    const header = ["grupo","cliente","cnpj","unidade","os","status","origem","competencia","dias","valor_estimado","valor_confirmado","valor_exposicao","oc","nf","observacao"];
    const body = filteredRows.map((row) => [row.grupo_cliente,row.cliente_nome,row.documento,row.unidade_nome,row.numero_os,row.status,row.origem,row.data_competencia,row.dias_em_aberto,row.valor_estimado,row.valor_confirmado,row.valor_exposicao,row.pedido_compra_cliente,row.documento_numero,row.observacao].map(csvCell).join(";"));
    const blob = new Blob(["\uFEFF" + [header.join(";"), ...body].join("\r\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob); const a = document.createElement("a"); a.href = url; a.download = `venda-a-credito-${new Date().toISOString().slice(0,10)}.csv`; a.click(); URL.revokeObjectURL(url);
  }

  const unique = <T,>(values: T[]) => Array.from(new Set(values));
  const inputClass = "vc-control w-full rounded-lg border border-zinc-700/80 bg-[#0d1316] px-3 py-2.5 text-sm text-zinc-100 outline-none transition focus:border-sky-500/60 focus:ring-2 focus:ring-sky-500/10";
  const buttonClass = "vc-button rounded-lg border border-zinc-700/80 bg-[#0d1316] px-3 py-2 text-sm text-zinc-100 transition hover:border-zinc-600 hover:bg-zinc-800/70 disabled:opacity-50";
  const rowButtonClass = "vc-row-button rounded-md border border-zinc-700 bg-zinc-950/80 px-2.5 py-1.5 text-xs text-zinc-200 transition hover:border-zinc-500 hover:bg-zinc-800 disabled:opacity-50";
  const manualUnits = unidades.filter((u) => String(u.cliente_id) === manual.clienteId);
  const activeFilterCount = [filters.q, filters.grupo, filters.cliente, filters.unidade, filters.origem, filters.status, filters.responsavel, filters.dias, filters.semOc].filter(Boolean).length;

  return (
    <div className="carteira-theme venda-credito-page mx-auto w-full max-w-[1480px] px-3 py-5 text-zinc-100 sm:px-5 sm:py-7">
      <section className="vc-shell rounded-2xl border border-zinc-700/70 bg-[#151d21] p-4 shadow-2xl shadow-black/20 sm:p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold tracking-wide text-sky-300/80">Financeiro <span className="px-1.5 text-zinc-600">›</span> Venda a Crédito</div>
            <h1 className="mt-2 text-xl font-semibold tracking-tight text-zinc-50">Carteira de venda a crédito</h1>
            <p className="mt-1 text-sm text-zinc-400">Exposição entregue antes da nota fiscal e do contas a receber.</p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Link href="/financeiro/gestao-cobranca" className={buttonClass}>Gestão de Cobrança</Link>
            <button className={buttonClass} onClick={exportCsv}>Exportar CSV</button>
            <button className={buttonClass} onClick={() => void load()} disabled={loading}>{loading ? "Atualizando..." : "Atualizar"}</button>
          </div>
        </div>

        <div className="vc-tabbar mt-5 inline-flex rounded-lg border border-zinc-700/70 bg-[#0d1316] p-1">
          <button className={`vc-tab rounded-md px-3 py-1.5 text-sm transition ${aba === "carteira" ? "vc-tab-active bg-zinc-700/70 text-white shadow" : "text-zinc-400 hover:text-zinc-200"}`} onClick={() => setParam("aba", "")}>Carteira</button>
          <button className={`vc-tab rounded-md px-3 py-1.5 text-sm transition ${aba === "avulso" ? "vc-tab-active bg-zinc-700/70 text-white shadow" : "text-zinc-400 hover:text-zinc-200"}`} onClick={() => setParam("aba", "avulso")}>Lançar / importar</button>
        </div>

        {error && <div className="mt-4 rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error}</div>}
        {ok && <div className="mt-4 rounded-lg border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-200">{ok}</div>}

        {aba === "avulso" ? (
          <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,2fr)_minmax(320px,1fr)]">
            <form onSubmit={handleManualSubmit} className="vc-surface rounded-xl border border-zinc-700/70 bg-[#11181c] p-5">
              <h2 className="font-semibold">Lançamento avulso</h2>
              <p className="mt-1 text-sm text-zinc-500">Para saldos legados e exceções que não possuem OS.</p>
              <div className="mt-4 grid gap-4 md:grid-cols-2">
                <label className="text-xs text-zinc-400">Cliente<select className={`${inputClass} mt-1`} value={manual.clienteId} onChange={(e) => setManual((p) => ({ ...p, clienteId: e.target.value, unidadeId: "" }))}><option value="">Selecione</option>{clientes.filter((c) => c.ativo !== false).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}</select></label>
                <label className="text-xs text-zinc-400">Unidade<select className={`${inputClass} mt-1`} value={manual.unidadeId} onChange={(e) => setManual((p) => ({ ...p, unidadeId: e.target.value }))}><option value="">Sem unidade</option>{manualUnits.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}</select></label>
                <label className="text-xs text-zinc-400 md:col-span-2">Descrição<input className={`${inputClass} mt-1`} value={manual.descricao} onChange={(e) => setManual((p) => ({ ...p, descricao: e.target.value }))} /></label>
                <label className="text-xs text-zinc-400">Valor<input className={`${inputClass} mt-1 text-right`} inputMode="decimal" value={manual.valor} onChange={(e) => setManual((p) => ({ ...p, valor: e.target.value }))} /></label>
                <label className="text-xs text-zinc-400">Competência<input className={`${inputClass} mt-1`} type="date" value={manual.data} onChange={(e) => setManual((p) => ({ ...p, data: e.target.value }))} /></label>
                <label className="text-xs text-zinc-400 md:col-span-2">Origem<select className={`${inputClass} mt-1`} value={manual.origem} onChange={(e) => setManual((p) => ({ ...p, origem: e.target.value }))}><option value="AVULSO_LEGADO">Avulso legado</option><option value="OUTRO">Outro</option></select></label>
              </div>
              <button type="submit" className={`${buttonClass} mt-4 border-emerald-500/40 bg-emerald-500/10 text-emerald-200`} disabled={!canWrite || busyId === "manual"}>Salvar lançamento</button>
            </form>
            <div className="vc-surface rounded-xl border border-zinc-700/70 bg-[#11181c] p-5">
              <h2 className="font-semibold">Importar CSV</h2>
              <p className="mt-2 text-sm leading-6 text-zinc-400">Aceita ponto e vírgula ou vírgula. Identifique o cliente por <code>cliente_id</code>, <code>cnpj</code> ou <code>cliente</code>. Colunas: descrição, valor, data_competencia e unidade são opcionais conforme o caso.</p>
              <label className={`${buttonClass} mt-5 inline-block cursor-pointer border-sky-500/40 bg-sky-500/10 text-sky-200`}>{importing ? "Importando..." : "Selecionar CSV"}<input type="file" accept=".csv,text/csv" className="hidden" onChange={handleCsv} disabled={importing || !canWrite} /></label>
            </div>
          </div>
        ) : (
          <>
            <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <div className="vc-surface vc-risk-card rounded-xl border border-amber-500/70 bg-[#11181c] p-4 shadow-sm shadow-amber-950/20">
                <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-amber-200/80">Sem OC · risco alto</div>
                <div className="mt-3 font-mono text-2xl font-bold tabular-nums text-amber-300">R$ {formatMoneyBR(kpis.aberto)}</div>
                <div className="mt-1 text-xs text-sky-300/80">{kpis.abertoCount} lançamento(s)</div>
              </div>
              <div className="vc-surface rounded-xl border border-zinc-700/70 bg-[#11181c] p-4">
                <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-sky-300/80">Com OC, aguardando NF</div>
                <div className="mt-3 font-mono text-2xl font-bold tabular-nums text-zinc-50">R$ {formatMoneyBR(kpis.oc)}</div>
                <div className="mt-1 text-xs text-sky-300/80">{kpis.ocCount} lançamento(s)</div>
              </div>
              <div className="vc-surface rounded-xl border border-zinc-700/70 bg-[#11181c] p-4">
                <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-sky-300/80">Total em aberto</div>
                <div className="mt-3 font-mono text-2xl font-bold tabular-nums text-zinc-50">R$ {formatMoneyBR(kpis.total)}</div>
                <div className="mt-1 text-xs text-sky-300/80">{kpis.totalCount} lançamento(s) · {kpis.clientes} grupo(s)</div>
              </div>
              <div className="vc-surface rounded-xl border border-zinc-700/70 bg-[#11181c] p-4">
                <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-sky-300/80">Parado há +30 dias</div>
                <div className="mt-3 font-mono text-2xl font-bold tabular-nums text-zinc-50">R$ {formatMoneyBR(kpis.paradosValor)}</div>
                <div className="mt-1 text-xs text-sky-300/80">{kpis.parados} lançamento(s)</div>
              </div>
            </div>

            <details className="vc-surface group/filters mt-4 rounded-xl border border-zinc-700/70 bg-[#11181c]">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3 text-sm font-medium text-zinc-300 [&::-webkit-details-marker]:hidden">
                <span className="flex items-center gap-2"><span className="text-xs text-sky-300 transition group-open/filters:rotate-90">▶</span> Filtros da carteira</span>
                <span className="text-xs font-normal text-zinc-500">{activeFilterCount ? `${activeFilterCount} ativo(s)` : "Nenhum filtro ativo"}</span>
              </summary>
              <div className="grid gap-3 border-t border-zinc-700/60 p-4 md:grid-cols-4 xl:grid-cols-8">
                <input className={`${inputClass} md:col-span-2`} placeholder="Buscar cliente, OS, OC, NF..." defaultValue={searchParams.get("q") ?? ""} onKeyDown={(e) => { if (e.key === "Enter") setParam("q", e.currentTarget.value); }} onBlur={(e) => setParam("q", e.currentTarget.value)} />
                <select className={inputClass} value={filters.grupo} onChange={(e) => setParam("grupo", e.target.value)}><option value="">Todos os grupos</option>{unique(rows.map((r) => r.grupo_cliente)).map((g) => <option key={g} value={g}>{g}</option>)}</select>
                <select className={inputClass} value={filters.cliente} onChange={(e) => setParam("cliente", e.target.value)}><option value="">Todos os clientes</option>{unique(rows.map((r) => r.cliente_id)).map((id) => <option key={id} value={id}>{rows.find((r) => r.cliente_id === id)?.cliente_nome}</option>)}</select>
                <select className={inputClass} value={filters.unidade} onChange={(e) => setParam("unidade", e.target.value)}><option value="">Todas as unidades</option>{unidades.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}</select>
                <select className={inputClass} value={filters.origem} onChange={(e) => setParam("origem", e.target.value)}><option value="">Todas as origens</option>{unique(rows.map((r) => r.origem)).map((o) => <option key={o} value={o}>{ORIGEM_LABEL[o] ?? o}</option>)}</select>
                <select className={inputClass} value={filters.status} onChange={(e) => setParam("status", e.target.value)}><option value="">Todos os status</option>{Object.entries(STATUS_LABEL).map(([s,l]) => <option key={s} value={s}>{l}</option>)}</select>
                <select className={inputClass} value={filters.dias || ""} onChange={(e) => setParam("dias", e.target.value)}><option value="">Qualquer idade</option><option value="7">7+ dias</option><option value="15">15+ dias</option><option value="30">30+ dias</option><option value="60">60+ dias</option></select>
                {filters.semOc ? <button type="button" className={`${buttonClass} text-amber-300`} onClick={() => setParam("sem_oc", "")}>Sem OC ×</button> : null}
              </div>
            </details>

            <div className="mt-4 space-y-3">
              {loading && <div className="vc-surface rounded-xl border border-zinc-700/70 bg-[#11181c] p-6 text-sm text-zinc-400">Carregando carteira...</div>}
              {!loading && groups.map(([group, groupRows], index) => {
                const activeRows = groupRows.filter((row) => STATUS_ABERTOS.has(row.status));
                const groupValue = activeRows.reduce((sum, row) => sum + n(row.valor_exposicao), 0);
                const clientNames = unique(groupRows.map((row) => row.cliente_nome).filter(Boolean) as string[]);
                const groupName = clientNames[0] ?? `Grupo ${group}`;
                const units = new Set(groupRows.map((row) => row.unidade_id ? `u-${row.unidade_id}` : `c-${row.cliente_id}`)).size;
                return (
                  <details key={group} open={index === 0 || (index === 1 && groupRows.length <= 15)} className="vc-surface group/client overflow-visible rounded-xl border border-zinc-700/70 bg-[#11181c]">
                    <summary className="grid cursor-pointer list-none grid-cols-[minmax(0,1fr)_auto] items-center gap-4 px-4 py-3.5 [&::-webkit-details-marker]:hidden">
                      <div className="min-w-0">
                        <div className="flex items-center gap-2"><span className="text-[10px] text-sky-300 transition group-open/client:rotate-90">▶</span><span className="truncate font-semibold text-zinc-50">{groupName}</span></div>
                        <div className="mt-1 pl-4 text-xs text-sky-300/70">{units} unidade(s) · {groupRows.length} lançamento(s){clientNames.length > 1 ? ` · ${clientNames.length} clientes vinculados` : ""}</div>
                      </div>
                      <div className="text-right font-mono text-base font-bold tabular-nums text-zinc-50">R$ {formatMoneyBR(groupValue)}</div>
                    </summary>

                    <div className={`border-t border-zinc-700/70 ${groupRows.length > 10 ? "max-h-[520px] overflow-y-auto" : ""}`}>
                      {groupRows.map((row) => {
                        const badge = carteiraBadge(row);
                        const age = n(row.dias_em_aberto);
                        return (
                          <div key={row.credito_id} className="vc-row grid gap-3 border-b border-zinc-800/90 px-4 py-3 text-sm last:border-b-0 hover:bg-zinc-800/20 lg:grid-cols-[minmax(220px,1.4fr)_100px_minmax(180px,1fr)_minmax(160px,.8fr)_130px_92px] lg:items-center">
                            <div className="min-w-0">
                              <div className="font-medium text-zinc-100">{row.unidade_nome ?? row.cliente_nome ?? `Cliente ${row.cliente_id}`}</div>
                              {row.unidade_nome && <div className="truncate text-xs text-sky-300/70">{row.cliente_nome}</div>}
                              <div className="mt-1 truncate text-xs text-zinc-500" title={row.descricao ?? ""}>{row.descricao || row.documento || "Sem descrição"}</div>
                            </div>

                            <div>
                              <div className="text-[10px] uppercase tracking-wide text-zinc-600 lg:hidden">OS / origem</div>
                              {row.os_id ? <Link className="font-mono text-sm text-sky-300 hover:underline" href={`/os/${row.os_id}`}>{row.numero_os ?? `OS ${row.os_id}`}</Link> : <span className="text-zinc-500">Avulso</span>}
                              <div className="mt-1 text-xs text-zinc-500">{formatDate(row.data_competencia)}</div>
                            </div>

                            <div className="flex flex-wrap items-center gap-2">
                              <span className={`inline-flex rounded-md border px-2 py-1 text-[10px] font-semibold uppercase tracking-wide ${badge.className}`}>{badge.label}</span>
                              <span className={`font-mono text-xs ${age >= 30 ? "font-semibold text-amber-300" : "text-sky-300/80"}`}>{age} d</span>
                              <span className="text-xs text-zinc-600">{STATUS_LABEL[row.status] ?? row.status}</span>
                            </div>

                            <div className="min-w-0 text-xs">
                              <div className="truncate text-zinc-300">OC: {row.pedido_compra_cliente ?? "—"} · NF: {row.documento_numero ?? "—"}</div>
                              <div className="mt-1 truncate text-zinc-500" title={row.observacao ?? ""}>{row.responsavel_cliente_nome ? `${row.responsavel_cliente_nome} · ` : ""}Próximo: {formatDate(row.proximo_contato_date)}</div>
                            </div>

                            <div className="text-left lg:text-right">
                              <div className="font-mono font-bold tabular-nums text-zinc-50">R$ {formatMoneyBR(n(row.valor_exposicao))}</div>
                              <div className="mt-1 text-[10px] text-zinc-600">{row.valor_confirmado === null ? "Estimado" : "Acordado"}</div>
                            </div>

                            <details className="relative">
                              <summary className="cursor-pointer list-none rounded-md border border-zinc-700 bg-zinc-950/70 px-2.5 py-1.5 text-center text-xs text-zinc-300 hover:border-zinc-500 [&::-webkit-details-marker]:hidden">Ações</summary>
                              <div className="vc-menu mt-2 flex flex-wrap gap-1 rounded-lg border border-zinc-700 bg-[#0d1316] p-2 shadow-xl lg:absolute lg:right-0 lg:z-30 lg:w-80">
                                {canWrite && <>
                                  <button className={rowButtonClass} disabled={busyId===row.credito_id} onClick={() => void registrarOc(row)}>Registrar OC</button>
                                  <button className={rowButtonClass} disabled={busyId===row.credito_id} onClick={() => void vincularNf(row)}>Vincular NF</button>
                                  {row.os_id && <button className={rowButtonClass} disabled={busyId===row.credito_id} onClick={() => void runAction(row.credito_id, async () => { const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_recalcular", { p_credito_id: row.credito_id }); if (rpcError) throw rpcError; }, "Valor recalculado.")}>Recalcular</button>}
                                  <button className={rowButtonClass} disabled={busyId===row.credito_id} onClick={() => void editarCobranca(row)}>Contato / nota</button>
                                  {!['RECEBIDO','CANCELADO','PERDIDO'].includes(row.status) && <>
                                    <button className={rowButtonClass} disabled={busyId===row.credito_id} onClick={() => void encerrar(row,'PERDIDO')}>Marcar perdido</button>
                                    <button className={rowButtonClass} disabled={busyId===row.credito_id} onClick={() => void encerrar(row,'CANCELADO')}>Cancelar</button>
                                  </>}
                                </>}
                                {canDelete && <button className={`${rowButtonClass} text-red-300`} disabled={busyId===row.credito_id} onClick={() => { if (window.confirm("Excluir logicamente este registro?")) void runAction(row.credito_id, async () => { const { error: rpcError } = await supabase.schema("f").rpc("fn_venda_credito_excluir", { p_credito_id: row.credito_id }); if (rpcError) throw rpcError; }, "Registro excluído."); }}>Excluir</button>}
                              </div>
                            </details>
                          </div>
                        );
                      })}
                    </div>
                  </details>
                );
              })}
              {!loading && filteredRows.length === 0 && <div className="vc-surface rounded-xl border border-zinc-700/70 bg-[#11181c] px-4 py-12 text-center text-sm text-zinc-500">Nenhuma exposição encontrada.</div>}
            </div>
          </>
        )}
      </section>
    </div>
  );
}
