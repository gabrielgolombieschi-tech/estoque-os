"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";
import type { CapabilityKey } from "@/lib/auth/capabilities";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { HOME_SHORTCUTS, selectVitalBlocks, type HomeBlockId } from "@/lib/home/blocks";
import styles from "./home.module.css";

type DailyPoint = { data: string; horas: number };
type FeedItem = { tipo: string; data_hora: string; titulo: string; detalhe: string; href: string };
type OwnOs = {
  os_id: number;
  numero_os: string;
  cliente: string;
  descricao: string | null;
  status_fluxo: string;
  ultima_atividade: string | null;
  horas_mes: number;
};

type HomeData = {
  gerado_em: string;
  contexto: {
    empresa_nome: string;
    usuario_nome: string;
    papel: string;
    competencia_status: string;
    competencia_ano: number;
    competencia_mes: number;
    colaborador_vinculado: boolean;
  };
  horas_proprias: {
    total: number;
    dias_com_horas: number;
    dias_uteis_decorridos: number;
    dias_em_branco: number;
    serie_diaria: DailyPoint[];
    por_os: Array<{ os_id: number; numero_os: string; cliente: string; horas: number }>;
  };
  os_proprias: OwnOs[];
  os?: {
    em_andamento: number;
    clientes: number;
    garantia: number;
    paradas_90_dias: number;
    maior_parada_dias: number;
    sem_pedido?: number;
    sem_pedido_valor?: number;
    por_status: Record<string, number>;
  };
  horas_equipe?: {
    total: number;
    colaboradores: number;
    pessoas_com_dias_em_branco: number;
    serie_diaria: DailyPoint[];
    recentes: FeedItem[];
  };
  estoque?: {
    itens_ativos: number;
    abaixo_minimo: number;
    movimentacoes_hoje: number;
    recentes: FeedItem[];
  };
  financeiro?: {
    caixa: number;
    contas_bancarias: number;
    contas_sem_conferencia?: number;
    ultima_conferencia: string | null;
    a_receber: number;
    a_pagar: number;
    posicao_liquida: number;
    receber_vencido_valor: number;
    receber_vencido_quantidade: number;
    fluxo_previsto: number;
    fluxo_realizado: number;
    exposicao_credito: number;
    exposicao_lancamentos: number;
    exposicao_parados_30_dias: number;
  };
  faturamento?: { os_concluidas_sem_nf: number; valor_concluido_sem_nf: number };
  admin?: { clientes_incompletos: number };
};

type CommandResult = { tipo: string; titulo: string; subtitulo: string; href: string };
type Severity = "critical" | "warning" | "info";
type HomeAlert = {
  id: string;
  severity: Severity;
  title: string;
  reason: string;
  value: string;
  area: string;
  action: string;
  href: string;
};

const currency = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 2 });
const number = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 });
const monthName = new Intl.DateTimeFormat("pt-BR", { month: "long" });
const fullDate = new Intl.DateTimeFormat("pt-BR", { weekday: "long", day: "2-digit", month: "long" });
const compactDateTime = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });

function n(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatHours(value: unknown) {
  return `${number.format(n(value))} h`;
}

function relativeActivity(value: string | null) {
  if (!value) return "sem atividade recente";
  const date = new Date(`${value}T12:00:00`);
  const today = new Date();
  today.setHours(12, 0, 0, 0);
  const days = Math.max(0, Math.round((today.getTime() - date.getTime()) / 86_400_000));
  if (days === 0) return "hoje";
  if (days === 1) return "ontem";
  return `há ${days} dias`;
}

function Icon({ name, size = 16 }: { name: string; size?: number }) {
  const common = { width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.8, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  const paths: Record<string, ReactNode> = {
    search: <><circle cx="11" cy="11" r="7" /><path d="m20 20-3.4-3.4" /></>,
    arrow: <><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></>,
    os: <><path d="M7 3h10l3 3v15H4V3h3" /><path d="M8 3v4h8V3" /><path d="M8 12h8M8 16h5" /></>,
    clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    execution: <><path d="m14 6 4 4" /><path d="m4 20 7-7" /><path d="M16 3a4 4 0 0 0 5 5L8 21l-5-5Z" /></>,
    stock: <><path d="m4 7 8-4 8 4-8 4Z" /><path d="m4 7 8 4 8-4v10l-8 4-8-4Z" /><path d="M12 11v10" /></>,
    move: <><path d="M7 7h11l-3-3" /><path d="m18 7-3 3" /><path d="M17 17H6l3 3" /><path d="m6 17 3-3" /></>,
    finance: <><path d="M3 10h18" /><path d="M5 10v8m5-8v8m4-8v8m5-8v8M3 21h18" /><path d="m12 3 9 4H3Z" /></>,
    credit: <><rect x="3" y="5" width="18" height="14" rx="2" /><path d="M3 10h18M7 15h3" /></>,
    billing: <><path d="M6 3h12v18l-3-2-3 2-3-2-3 2Z" /><path d="M9 8h6M9 12h6M9 16h3" /></>,
    purchase: <><circle cx="9" cy="20" r="1" /><circle cx="18" cy="20" r="1" /><path d="M3 4h2l2 11h11l2-7H6" /></>,
  };
  return <svg aria-hidden="true" {...common}>{paths[name] ?? paths.os}</svg>;
}

function metricFor(blockId: HomeBlockId, data: HomeData) {
  switch (blockId) {
    case "os_em_andamento":
      return { value: number.format(n(data.os?.em_andamento)), detail: `${number.format(n(data.os?.clientes))} cliente(s) · ${number.format(n(data.os?.garantia))} em garantia` };
    case "horas_proprias":
      return { value: formatHours(data.horas_proprias.total), detail: `${number.format(data.horas_proprias.dias_com_horas)} dia(s) com lançamento${data.horas_proprias.dias_em_branco ? ` · ${data.horas_proprias.dias_em_branco} em branco` : ""}` };
    case "caixa":
      return { value: currency.format(n(data.financeiro?.caixa)), detail: `${number.format(n(data.financeiro?.contas_bancarias))} conta(s) bancária(s)` };
    case "estoque_baixo":
      return { value: number.format(n(data.estoque?.abaixo_minimo)), detail: `de ${number.format(n(data.estoque?.itens_ativos))} itens ativos` };
    case "horas_equipe":
      return { value: formatHours(data.horas_equipe?.total), detail: `${number.format(n(data.horas_equipe?.colaboradores))} colaborador(es) no mês` };
    case "posicao_liquida":
      return { value: currency.format(n(data.financeiro?.posicao_liquida)), detail: `${currency.format(n(data.financeiro?.a_receber))} a receber · ${currency.format(n(data.financeiro?.a_pagar))} a pagar`, compact: true };
    case "movimentacoes_hoje":
      return { value: number.format(n(data.estoque?.movimentacoes_hoje)), detail: "entradas, saídas e ajustes hoje" };
    case "dias_regulares":
      return { value: `${number.format(data.horas_proprias.dias_com_horas)}/${number.format(data.horas_proprias.dias_uteis_decorridos)}`, detail: "dias úteis decorridos com apontamento" };
    case "os_proprias":
      return { value: number.format(data.os_proprias.length), detail: "OS em andamento com sua atuação" };
  }
}

function buildAlerts(data: HomeData): HomeAlert[] {
  const alerts: HomeAlert[] = [];
  const add = (condition: boolean, alert: HomeAlert) => { if (condition) alerts.push(alert); };

  add(n(data.financeiro?.contas_sem_conferencia) > 0, { id: "saldo", severity: "critical", title: "Saldos bancários sem conferência", reason: "Há contas sem posição recente; os demais indicadores financeiros podem ficar distorcidos.", value: `${n(data.financeiro?.contas_sem_conferencia)} conta(s)`, area: "Financeiro", action: "Conferir", href: "/financeiro/cadastros/contas-bancarias" });
  add(n(data.financeiro?.receber_vencido_quantidade) > 0, { id: "receber", severity: "critical", title: "Contas a receber vencidas", reason: "Títulos em aberto já passaram do vencimento e precisam de ação de cobrança.", value: currency.format(n(data.financeiro?.receber_vencido_valor)), area: "Financeiro", action: "Abrir títulos", href: "/financeiro/contas_pagar_receber" });
  add(n(data.faturamento?.os_concluidas_sem_nf) > 0, { id: "faturar", severity: "warning", title: "OS concluídas sem nota fiscal", reason: "Serviços concluídos ainda não entraram no faturamento.", value: `${n(data.faturamento?.os_concluidas_sem_nf)} OS`, area: "Faturamento", action: "Faturar", href: "/financeiro/venda-a-credito" });
  add(n(data.financeiro?.exposicao_parados_30_dias) > 0, { id: "credito", severity: "warning", title: "Venda a crédito parada há mais de 30 dias", reason: "Exposição entregue antes da nota ou do contas a receber, sem evolução recente.", value: `${n(data.financeiro?.exposicao_parados_30_dias)} lançamento(s)`, area: "Financeiro", action: "Cobrar", href: "/financeiro/venda-a-credito?idade=30" });
  add(data.horas_proprias.dias_em_branco > 0, { id: "horas-proprias", severity: "warning", title: "Você tem dias úteis sem apontamento", reason: "Complete o mês para evitar pendências no fechamento de horas.", value: `${data.horas_proprias.dias_em_branco} dia(s)`, area: "Apontamentos", action: "Lançar horas", href: "/apontamentos" });
  add(n(data.os?.sem_pedido) > 0, { id: "pedido", severity: "warning", title: "OS com execução e sem pedido do cliente", reason: "Há horas ou materiais lançados sem a ordem de compra registrada.", value: `${n(data.os?.sem_pedido)} OS`, area: "OS", action: "Revisar", href: "/os" });
  add(n(data.os?.paradas_90_dias) > 0, { id: "os-paradas", severity: "warning", title: "OS em andamento sem atividade há mais de 90 dias", reason: "Revise continuidade, encerramento ou atualização dessas ordens.", value: `${n(data.os?.paradas_90_dias)} OS`, area: "OS", action: "Ver OS", href: "/os" });
  add(n(data.estoque?.abaixo_minimo) > 0, { id: "estoque", severity: "warning", title: "Itens abaixo do estoque mínimo", reason: "Reposição necessária para reduzir risco de parada operacional.", value: `${n(data.estoque?.abaixo_minimo)} item(ns)`, area: "Estoque", action: "Analisar", href: "/estoque/relatorios?tab=saldo&a_abaixo_minimo=1" });
  add(n(data.horas_equipe?.pessoas_com_dias_em_branco) > 0, { id: "equipe-horas", severity: "info", title: "Equipe com dias úteis sem apontamento", reason: "Indicador agregado; consulte o resumo mensal para tratar as pendências.", value: `${n(data.horas_equipe?.pessoas_com_dias_em_branco)} pessoa(s)`, area: "Apontamentos", action: "Ver resumo", href: "/apontamentos/resumo-mensal" });
  add(n(data.admin?.clientes_incompletos) > 0, { id: "clientes", severity: "info", title: "Cadastros de clientes incompletos", reason: "Documento ou dados básicos faltantes podem impedir faturamento e cobrança.", value: `${n(data.admin?.clientes_incompletos)} cliente(s)`, area: "Cadastros", action: "Corrigir", href: "/clientes/documentos-pendentes" });

  const rank: Record<Severity, number> = { critical: 0, warning: 1, info: 2 };
  return alerts.sort((a, b) => rank[a.severity] - rank[b.severity]).slice(0, 5);
}

function BarRow({ label, value, max, formatted, tone }: { label: string; value: number; max: number; formatted: string; tone?: "green" | "amber" | "red" }) {
  const width = max > 0 ? Math.max(2, Math.min(100, (Math.abs(value) / max) * 100)) : 2;
  const toneClass = tone === "green" ? styles.barFillGreen : tone === "amber" ? styles.barFillAmber : tone === "red" ? styles.barFillRed : "";
  return <div className={styles.barRow}><span className={styles.barLabel}>{label}</span><div className={styles.barTrack}><div className={`${styles.barFill} ${toneClass}`} style={{ width: `${width}%` }} /></div><span className={styles.barValue}>{formatted}</span></div>;
}

function LeftContext({ data }: { data: HomeData }) {
  if (data.financeiro) {
    const values = [n(data.financeiro.fluxo_previsto), n(data.financeiro.fluxo_realizado), n(data.financeiro.a_receber), n(data.financeiro.a_pagar)];
    const max = Math.max(1, ...values.map(Math.abs));
    return <section className={styles.panel}><div className={styles.panelHeader}><div><div className={styles.panelTitle}>Pulso financeiro</div><div className={styles.panelSubtitle}>Previsão, realizado e posição em aberto</div></div><Link href="/financeiro/relatorios/fluxo-caixa" className={styles.textLink}>Abrir fluxo →</Link></div><div className={styles.chartBody}><div className={styles.barList}><BarRow label="Previsto no mês" value={values[0]} max={max} formatted={currency.format(values[0])} tone="amber" /><BarRow label="Realizado no mês" value={values[1]} max={max} formatted={currency.format(values[1])} tone="green" /><BarRow label="A receber" value={values[2]} max={max} formatted={currency.format(values[2])} /><BarRow label="A pagar" value={values[3]} max={max} formatted={currency.format(values[3])} tone="red" /></div><div className={styles.chartLegend}><span>Base: títulos e pagamentos da empresa atual</span><span>Competência: {monthName.format(new Date())}</span></div></div></section>;
  }

  if (data.os) {
    const rows = [["Em andamento", n(data.os.em_andamento), "blue"], ["Em garantia", n(data.os.garantia), "amber"], ["Concluídas", n(data.os.por_status?.concluida), "green"], ["Faturadas", n(data.os.por_status?.faturada), "green"]] as const;
    const max = Math.max(1, ...rows.map((row) => row[1]));
    return <section className={styles.panel}><div className={styles.panelHeader}><div><div className={styles.panelTitle}>OS por situação</div><div className={styles.panelSubtitle}>Retrato operacional da empresa atual</div></div><Link href="/os/analitico" className={styles.textLink}>Abrir analítico →</Link></div><div className={styles.chartBody}><div className={styles.barList}>{rows.map(([label, value, tone]) => <BarRow key={label} label={label} value={value} max={max} formatted={number.format(value)} tone={tone === "blue" ? undefined : tone} />)}</div><div className={styles.chartLegend}><span>{number.format(data.os.clientes)} cliente(s) em execução</span><span>Maior parada: {number.format(data.os.maior_parada_dias)} dias</span></div></div></section>;
  }

  const points = data.horas_proprias.serie_diaria ?? [];
  const max = Math.max(1, ...points.map((point) => n(point.horas)));
  return <section className={styles.panel}><div className={styles.panelHeader}><div><div className={styles.panelTitle}>Seu ritmo de apontamentos</div><div className={styles.panelSubtitle}>Horas registradas por dia útil</div></div><Link href="/apontamentos" className={styles.textLink}>Lançar horas →</Link></div><div className={styles.chartBody}><div className={styles.sparkline}>{points.length ? points.map((point) => <div key={point.data} className={`${styles.sparkBar} ${n(point.horas) === 0 ? styles.sparkBarZero : ""}`} style={{ height: `${Math.max(2, (n(point.horas) / max) * 100)}%` }} title={`${point.data}: ${formatHours(point.horas)}`} />) : <div className={styles.empty}>Ainda não há horas no mês.</div>}</div><div className={styles.chartLegend}><span>{formatHours(data.horas_proprias.total)} no mês</span><span>{data.horas_proprias.dias_em_branco} dia(s) útil(eis) em branco</span></div></div></section>;
}

export default function HomePage() {
  const router = useRouter();
  const te = useTenantEmpresaContext();
  const [data, setData] = useState<HomeData | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<CommandResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);
  const requestIdRef = useRef(0);

  const has = useCallback((permission: CapabilityKey) => Boolean(te.capabilities?.[permission]), [te.capabilities]);
  const load = useCallback(async (background = false) => {
    if (!te.tenantId || !te.empresaId || te.capabilities === null) return;
    const requestId = ++requestIdRef.current;
    if (background) setRefreshing(true); else setLoading(true);
    setError(null);
    try {
      const { data: payload, error: rpcError } = await getSupabaseBrowser().rpc("home_sala_controle");
      if (rpcError) throw rpcError;
      if (requestId !== requestIdRef.current) return;
      setData(payload as HomeData);
    } catch (cause) {
      if (requestId !== requestIdRef.current) return;
      setError(cause instanceof Error ? cause.message : String((cause as { message?: unknown })?.message ?? cause));
    } finally {
      if (requestId === requestIdRef.current) { setLoading(false); setRefreshing(false); }
    }
  }, [te.capabilities, te.empresaId, te.tenantId]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(false), 0);
    return () => window.clearTimeout(timer);
  }, [load]);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") { event.preventDefault(); setSearchOpen(true); searchRef.current?.focus(); }
      if (event.key === "Escape") setSearchOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);
  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) return;
    let active = true;
    const timer = window.setTimeout(async () => {
      setSearching(true);
      const { data: rows, error: searchError } = await getSupabaseBrowser().rpc("home_busca_comando", { p_termo: term });
      if (!active) return;
      setSearching(false);
      setResults(searchError ? [] : (rows ?? []) as CommandResult[]);
    }, 220);
    return () => { active = false; window.clearTimeout(timer); };
  }, [query]);

  const vitalBlocks = useMemo(() => selectVitalBlocks(has), [has]);
  const alerts = useMemo(() => data ? buildAlerts(data) : [], [data]);
  const shortcuts = useMemo(() => HOME_SHORTCUTS.filter((item) => !item.permission || has(item.permission)), [has]);
  const feed = useMemo(() => data ? [...(data.horas_equipe?.recentes ?? []), ...(data.estoque?.recentes ?? [])].sort((a, b) => new Date(b.data_hora).getTime() - new Date(a.data_hora).getTime()).slice(0, 5) : [], [data]);
  const today = new Date();
  const openResult = (result: CommandResult) => { setSearchOpen(false); setQuery(""); setResults([]); router.push(result.href); };

  return <div className={styles.page}><div className={styles.shell}>
    <header className={styles.statusBar}>
      <div className={styles.statusLeft}><span className={styles.statusDot} /><span className={styles.brand}>segau.app</span><span className={styles.divider} /><span>{data?.contexto.papel ? data.contexto.papel.replaceAll("_", " ") : "ERP"}</span><span>·</span><span>{data?.contexto.usuario_nome ?? te.email ?? "Usuário"}</span></div>
      <div className={styles.statusRight}><span>{data?.contexto.empresa_nome ?? te.empresa?.nome_fantasia ?? "Empresa atual"}</span><span>·</span><span>{fullDate.format(today)}</span><span className={styles.divider} /><span>Fechamento de {monthName.format(today)}: <strong style={{ color: data?.contexto.competencia_status === "fechada" ? "var(--control-green)" : "var(--control-amber)" }}>{data?.contexto.competencia_status === "fechada" ? "concluído" : "em aberto"}</strong></span></div>
    </header>

    <div className={styles.commandWrap} onFocus={() => setSearchOpen(true)} onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setSearchOpen(false); }}>
      <div className={styles.commandBar}><span className={styles.commandIcon}><Icon name="search" size={17} /></span><input ref={searchRef} className={styles.commandInput} value={query} onChange={(event) => { const next = event.target.value; setQuery(next); setSearching(next.trim().length >= 2); if (next.trim().length < 2) setResults([]); }} placeholder="Buscar OS, cliente, item, colaborador ou nota fiscal…" aria-label="Busca global do ERP" autoComplete="off" /><span className={styles.kbd}>Ctrl K</span></div>
      {searchOpen && query.trim().length >= 2 && <div className={styles.searchResults} role="listbox" aria-label="Resultados da busca">{searching ? <div className={styles.searchHint}>Buscando no contexto da empresa…</div> : results.length ? results.map((result, index) => <button type="button" role="option" aria-selected="false" className={styles.searchResult} key={`${result.tipo}-${result.href}-${index}`} onMouseDown={(event) => event.preventDefault()} onClick={() => openResult(result)}><span className={styles.searchType}>{result.tipo}</span><span className={styles.searchTitle}>{result.titulo}</span><span className={styles.searchSubtitle}>{result.subtitulo}</span></button>) : <div className={styles.searchHint}>Nenhum resultado permitido para “{query.trim()}”.</div>}</div>}
    </div>

    {error && <div className={styles.errorBox}><span>Não foi possível carregar a Sala de Controle: {error}</span><button type="button" className={styles.actionButton} onClick={() => void load(false)}>Tentar novamente</button></div>}
    {loading && !data ? <div className={styles.loadingGrid}>{[1, 2, 3, 4].map((item) => <div className={styles.skeleton} key={item} />)}</div> : data && <>
      <section className={styles.vitalGrid} aria-label="Indicadores vitais">{vitalBlocks.map((block) => { const metric = metricFor(block.id, data); return <Link href={block.href} className={`${styles.vitalCard} ${block.tone === "blue" ? styles.toneBlue : block.tone === "green" ? styles.toneGreen : block.tone === "amber" ? styles.toneAmber : ""}`} key={`${block.slot}-${block.id}`}><div><div className={styles.cardMeta}><span className={styles.eyebrow}>{block.title}</span><span className={styles.cardArrow}><Icon name="arrow" size={13} /></span></div><div className={`${styles.metric} ${metric.compact ? styles.metricCompact : ""}`}>{metric.value}</div></div><div className={styles.cardDetail}>{metric.detail}</div></Link>; })}</section>

      <section className={styles.panel} aria-label="Alertas prioritários"><div className={styles.panelHeader}><div className={styles.sectionTitle}><span className={styles.panelTitle}>O que precisa de atenção</span><span className={styles.panelSubtitle}>até 5 prioridades, ordenadas por severidade</span></div><button type="button" className={styles.actionButton} onClick={() => void load(true)} disabled={refreshing}>{refreshing ? "Atualizando…" : "Atualizar"}</button></div>{alerts.length ? <div className={styles.alertList}>{alerts.map((alert) => <div className={styles.alertRow} key={alert.id}><span className={`${styles.severity} ${alert.severity === "critical" ? styles.severityCritical : alert.severity === "warning" ? styles.severityWarning : styles.severityInfo}`} /><div><div className={styles.alertTitle}>{alert.title}</div></div><div className={styles.alertReason}>{alert.reason}</div><div className={styles.alertMeta}><span className={styles.alertValue}>{alert.value}</span><span className={styles.alertArea}>{alert.area}</span></div><Link href={alert.href} className={styles.actionButton}>{alert.action}</Link></div>)}</div> : <div className={styles.empty}>Nenhuma pendência prioritária encontrada para as suas permissões.</div>}</section>

      <div className={styles.contextGrid}><LeftContext data={data} /><section className={styles.panel}><div className={styles.panelHeader}><div><div className={styles.panelTitle}>Suas OS</div><div className={styles.panelSubtitle}>Ordens em andamento com seus apontamentos</div></div><Link href="/os" className={styles.textLink}>Ver carteira →</Link></div><div className={styles.osList}>{data.os_proprias.length ? data.os_proprias.map((os) => <Link href={`/os/${os.os_id}`} className={styles.osRow} key={os.os_id}><div><div className={styles.osMeta}><span className={styles.osNumber}>OS {os.numero_os}</span><span className={styles.osClient}>{os.cliente}</span></div><div className={styles.osDescription}>{os.descricao || "Sem descrição"} · {relativeActivity(os.ultima_atividade)}</div></div><div><div className={styles.osHours}>{formatHours(os.horas_mes)}</div><div className={styles.rowSecondary}>no mês</div></div></Link>) : <div className={styles.empty}>{data.contexto.colaborador_vinculado ? "Nenhuma OS em andamento com sua atuação." : "Seu usuário ainda não está vinculado a um colaborador."}</div>}</div><div className={styles.subPanelHeader}>Movimentos recentes permitidos</div><div className={styles.feedList}>{feed.length ? feed.map((item, index) => <Link href={item.href} className={styles.feedRow} key={`${item.tipo}-${item.data_hora}-${index}`}><span className={styles.feedIcon}><Icon name={item.tipo === "estoque" ? "move" : "clock"} size={13} /></span><span><span className={styles.feedTitle}>{item.titulo}</span><span className={styles.rowSecondary}> · {item.detalhe}</span></span><span className={styles.feedTime}>{compactDateTime.format(new Date(item.data_hora))}</span></Link>) : <div className={styles.empty}>Sem movimentos recentes nos módulos permitidos.</div>}</div></section></div>

      <section><div className={styles.sectionTitle} style={{ margin: "3px 1px 8px" }}><span className={styles.panelTitle}>Acessos rápidos</span><span className={styles.panelSubtitle}>somente módulos liberados para você</span></div><div className={styles.shortcutGrid}>{shortcuts.map((item) => <Link href={item.href} className={styles.shortcut} key={item.id}><span className={styles.shortcutIcon}><Icon name={item.icon} size={16} /></span><span><span className={styles.shortcutTitle}>{item.title}</span><span className={styles.shortcutDescription}>{item.description}</span></span></Link>)}</div></section>
      <footer className={styles.footer}><span>Indicadores calculados para {data.contexto.empresa_nome}, com escopo de tenant e empresa.</span><span>Atualizado em {compactDateTime.format(new Date(data.gerado_em))}</span></footer>
    </>}
  </div></div>;
}
