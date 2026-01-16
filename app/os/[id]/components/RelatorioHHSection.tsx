"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { RowInput, UserOptions } from "jspdf-autotable";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";

type EspecialidadeOption = { id: string; descricao: string | null };
type TabelaAtiva = {
  id: number;
  cliente_id: number;
  nome?: string | null;
  vigencia_inicio?: string | null;
  vigencia_fim?: string | null;
  ativo?: boolean | null;
};

type HhLancamentoViewRow = {
  id: string | number;
  os_id: number;
  data: string;
  colaborador_nome: string | null;
  especialidade_descricao: string | null;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  hora_entrada: string | null;
  hora_saida: string | null;
  horas_trabalhadas: number | null;
  hh_tipo_descricao?: string | null;
  hh_tipo_id?: string | number | null;
  hh_servico_id?: string | number | null;
  percentual_aplicado?: number | null;
  valor_hora: number | null;
  valor_total: number | null;
  observacao: string | null;
  criado_em: string | null;
};

type DidDrawPageData = Parameters<NonNullable<UserOptions["didDrawPage"]>>[0];

type Colaborador = {
  id: string;
  nome: string;
  ativo: boolean;
};

function formatHoursBR(value: number | null | undefined) {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0,00";
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatTimeHHMM(value: string | null | undefined): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  // Pode vir "HH:MM" ou "HH:MM:SS".
  if (/^\d{2}:\d{2}/.test(raw)) return raw.slice(0, 5);
  return raw;
}

function formatDateBR(isoDate: string | null | undefined) {
  if (!isoDate) return "--";
  const d = new Date(isoDate + "T00:00:00");
  return d.toLocaleDateString("pt-BR");
}

function getPercentualFromDate(dateISO: string): 0 | 50 | 100 {
  const raw = String(dateISO ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return 0;
  const d = new Date(raw + "T00:00:00");
  const dow = d.getDay();
  if (dow === 0) return 100;
  if (dow === 6) return 50;
  return 0;
}

function getTipoHHLabel(percentual: number): string {
  if (percentual === 50) return "Extra 50%";
  if (percentual === 100) return "Extra 100%";
  return "Normal";
}

function formatSupabaseError(err: unknown): string {
  if (!err || typeof err !== "object") return "Erro ao salvar lançamento HH.";
  const e = err as { message?: string; details?: string; hint?: string };
  const parts = [e.message ?? "Erro ao salvar lançamento HH.", e.details, e.hint].filter(Boolean);
  return parts.join(" | ");
}

function parseHHMM(value: string): number | null {
  const raw = String(value ?? "").trim();
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(raw);
  if (!m) return null;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  return hh * 60 + mm;
}

function isMissingColumnError(err: unknown): boolean {
  const message =
    err && typeof err === "object" && "message" in err ? String((err as { message?: unknown }).message ?? "") : "";
  return (
    /column\s+"?\w+"?\s+does not exist/i.test(message) ||
    /could not find the '\w+' column/i.test(message)
  );
}

function addOneDayISO(dateStr: string): string {
  const raw = String(dateStr ?? "").trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!m) return raw;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  if (!Number.isFinite(y) || !Number.isFinite(mo) || !Number.isFinite(d)) return raw;
  const utc = Date.UTC(y, mo - 1, d);
  if (!Number.isFinite(utc)) return raw;
  const next = new Date(utc + 24 * 60 * 60 * 1000);
  return next.toISOString().slice(0, 10);
}

async function gerarRelatorioPDF(
  hhRows: HhLancamentoViewRow[],
  osId: number
) {
  try {
    // Importa jsPDF dinamicamente
    const { jsPDF } = await import("jspdf");
    const autoTable = await import("jspdf-autotable");

    const doc = new jsPDF({
      orientation: "landscape",
      unit: "mm",
      format: "a4",
    });

    const margin = 10;
    let yPos = margin;

    // Título
    doc.setFontSize(16);
    doc.setFont("helvetica", "bold");
    doc.text(`Relatório de Horas Lançadas - OS ${osId}`, margin, yPos);
    yPos += 10;

    // Data de emissão
    doc.setFontSize(9);
    doc.setFont("helvetica", "normal");
    doc.text(`Emissão: ${new Date().toLocaleDateString("pt-BR")}`, margin, yPos);
    yPos += 6;

    // Dados da tabela
    const headRow: RowInput = [
      "Funcionário",
      "Função",
      "V. Hora Normal",
      "V. Hora 50%",
      "V. Hora 100%",
      "Data",
      "Entrada 1",
      "Saída 1",
      "Entrada 2",
      "Saída 2",
      "Horas",
      "Tipo",
      "Horas Normais",
      "Horas Extras",
      "R$ Total",
    ];

    const bodyRows: RowInput[] = [];

    // Dados das linhas
    let totalGeral = 0;
    hhRows.forEach((r) => {
      const valorHoraNormal = Number(r.valor_hora ?? 0);
      const valorHora50 = valorHoraNormal * 1.5;
      const valorHora100 = valorHoraNormal * 2.0;
      const horas = Number(r.horas_trabalhadas ?? 0);
      const percentualAplicado = Number(r.percentual_aplicado ?? 0);

      let horasNormais = horas;
      let horasExtras = 0;
      if (percentualAplicado > 0) {
        horasExtras = horas;
        horasNormais = 0;
      }

      const tipo = percentualAplicado === 0 ? "Normal" : `Extra ${percentualAplicado}%`;
      const valorNormalStr = horasNormais > 0 ? `R$ ${(horasNormais * valorHoraNormal).toFixed(2)}` : "R$ -";
      const valorExtrasStr =
        horasExtras > 0
          ? `R$ ${(horasExtras * (percentualAplicado === 50 ? valorHora50 : valorHora100)).toFixed(2)}`
          : "R$ -";
      const total = Number(r.valor_total ?? 0);
      totalGeral += total;

      bodyRows.push([
        r.colaborador_nome ?? "—",
        r.especialidade_descricao ?? "—",
        `R$ ${valorHoraNormal.toFixed(2)}`,
        valorHora50.toFixed(2),
        valorHora100.toFixed(2),
        formatDateBR(r.data),
        formatTimeHHMM(r.entrada_1) || "—",
        formatTimeHHMM(r.saida_1) || "—",
        formatTimeHHMM(r.entrada_2) || "—",
        formatTimeHHMM(r.saida_2) || "—",
        horas.toFixed(2),
        tipo,
        valorNormalStr,
        valorExtrasStr,
        `R$ ${total.toFixed(2)}`,
      ]);
    });

    // Linha de TOTAL
    bodyRows.push(["", "", "", "", "", "", "", "", "", "", "", "", "", "TOTAL", `R$ ${totalGeral.toFixed(2)}`]);

    // Usa autoTable para desenhar a tabela
    autoTable.default(doc, {
      startY: yPos,
      head: [headRow],
      body: bodyRows,
      margin: { left: margin, right: margin },
      columnStyles: {
        0: { cellWidth: 18 }, // Funcionário
        1: { cellWidth: 18 }, // Função
        2: { cellWidth: 14 }, // V. Hora Normal
        3: { cellWidth: 12 }, // V. Hora 50%
        4: { cellWidth: 12 }, // V. Hora 100%
        5: { cellWidth: 12 }, // Data
        6: { cellWidth: 11 }, // Entrada 1
        7: { cellWidth: 11 }, // Saída 1
        8: { cellWidth: 11 }, // Entrada 2
        9: { cellWidth: 11 }, // Saída 2
        10: { cellWidth: 10 }, // Horas
        11: { cellWidth: 12 }, // Tipo
        12: { cellWidth: 16 }, // Horas Normais
        13: { cellWidth: 14 }, // Horas Extras
        14: { cellWidth: 14, halign: "right" }, // R$ Total
      },
      headStyles: {
        fillColor: [40, 40, 40],
        textColor: [200, 200, 200],
        fontSize: 8,
        fontStyle: "bold",
      },
      bodyStyles: {
        fontSize: 7,
        textColor: [200, 200, 200],
      },
      footStyles: {
        fillColor: [50, 50, 50],
        textColor: [200, 200, 200],
        fontSize: 8,
        fontStyle: "bold",
      },
      didDrawPage: (data: DidDrawPageData) => {
        // Footer
        const pageCount = (doc as unknown as { internal: { pages: unknown[] } }).internal.pages.length;
        const pageSize = doc.internal.pageSize;
        const pageWidth = pageSize.getWidth();
        const pageHeight = pageSize.getHeight();

        doc.setFontSize(8);
        doc.text(`Página ${data.pageNumber} de ${pageCount}`, pageWidth / 2, pageHeight - 5, { align: "center" });
      },
    });

    // Download
    const dataStr = new Date().toISOString().slice(0, 10);
    doc.save(`relatorio-hh-os-${osId}-${dataStr}.pdf`);
  } catch (e) {
    console.error("Erro ao gerar PDF:", e);
    alert("Erro ao gerar PDF");
  }
}

export default function RelatorioHHSection({ osId, osDetail }: { osId: number; osDetail?: { cliente_id: number | null } | null }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId, loading: tenantLoading } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canRead = Boolean(has("os.read"));
  const canWrite = Boolean(has("os.write"));
  const canDelete = Boolean(has("os.delete"));
  
  // Garantir que cliente_id sempre vem do osDetail (requerido para todo fluxo HH)
  const clienteIdContext = osDetail?.cliente_id ?? null;

  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function ensureDbContext() {
    // Tenant/empresa context is owned by TenantEmpresaProvider.
    // Keep API for existing call sites without extra RPCs/fetch.
    return { tenant: tenantId, empresa: empresaId } as const;
  }

  // Estados para tabela de lançamentos HH (cobrança) desta OS
  const [hhRows, setHhRows] = useState<HhLancamentoViewRow[]>([]);
  const [loadingHh, setLoadingHh] = useState(false);
  const [hhErr, setHhErr] = useState<string | null>(null);

  // Estados para lançamento/edição de horas
  const [showLancamentoForm, setShowLancamentoForm] = useState(false);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [especialidadesOptions, setEspecialidadesOptions] = useState<EspecialidadeOption[]>([]);
  const [especialidadeLocked, setEspecialidadeLocked] = useState(false);
  const [tabelaAtiva, setTabelaAtiva] = useState<TabelaAtiva | null>(null);
  const [precoServicoSelecionado, setPrecoServicoSelecionado] = useState<{ preco_base: number; preco_50: number; preco_100: number } | null>(null);
  const vinculoEspecialidadesRef = useRef<Map<string, string[]>>(new Map());
  const [horaEntrada1, setHoraEntrada1] = useState("07:30");
  const [horaSaida1, setHoraSaida1] = useState("12:00");
  const [horaEntrada2, setHoraEntrada2] = useState("13:00");
  const [horaSaida2, setHoraSaida2] = useState("17:00");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [lancamentoForm, setLancamentoForm] = useState({
    data: new Date().toISOString().slice(0, 10),
    colaborador_id: "",
    hh_servico_id: "",
    observacao: "",
  });
  const [lancamentoBusy, setLancamentoBusy] = useState(false);
  const lancamentoDateRef = useRef<HTMLInputElement | null>(null);
  const lancamentoSubmitLockRef = useRef(false);

  useEffect(() => {
    if (!showLancamentoForm) return;
    const t = setTimeout(() => {
      lancamentoDateRef.current?.focus();
    }, 0);
    return () => clearTimeout(t);
  }, [showLancamentoForm]);

  useEffect(() => {
    if (!clienteIdContext) {
      setHhErr("Cliente não identificado. Não é possível carregar apontamentos HH.");
      return;
    }
    void loadHhLancamentos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [osId, clienteIdContext]);

  async function loadRelatorios() {
    // DEPRECATED: Tabela os_relatorios_hh foi removida.
    // Relatórios agora são gerados direto de hh_lancamentos em tempo real.
    // Esta função é um no-op para compatibilidade.
    return;
  }

  async function loadTabelaAtiva(clienteId: number, dataISO: string): Promise<TabelaAtiva | null> {
    if (!clienteId) {
      console.warn("[loadTabelaAtiva] cliente_id não fornecido");
      return null;
    }
    
    const ctx = await ensureDbContext();
    if (!ctx.tenant) {
      console.warn("[loadTabelaAtiva] tenant não resolvido");
      return null;
    }

    try {
      // 1. Tentar tabela vigente (dentro do período)
      const { data: vigente, error: vigenteErr } = await applyTenant(
        supabase
          .from("cliente_hh_tabelas")
          .select("id,cliente_id,nome,vigencia_inicio,vigencia_fim,ativo")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .lte("vigencia_inicio", dataISO)
          .gte("vigencia_fim", dataISO)
          .order("vigencia_inicio", { ascending: false })
          .limit(1)
          .maybeSingle(),
        ctx.tenant
      );
      
      if (!vigenteErr && vigente) {
        console.log("[loadTabelaAtiva] Tabela vigente encontrada:", vigente.id);
        return vigente as TabelaAtiva;
      }

      // 2. Fallback: tabela mais recente (mesmo se fora do período)
      const { data: recent, error: recentErr } = await applyTenant(
        supabase
          .from("cliente_hh_tabelas")
          .select("id,cliente_id,nome,vigencia_inicio,vigencia_fim,ativo")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .order("vigencia_inicio", { ascending: false })
          .limit(1)
          .maybeSingle(),
        ctx.tenant
      );
      
      if (!recentErr && recent) {
        console.warn("[loadTabelaAtiva] Usando tabela fora do período (fallback):", recent.id);
        return recent as TabelaAtiva;
      }
      
      if (recentErr) throw recentErr;
      console.warn("[loadTabelaAtiva] Nenhuma tabela HH encontrada para cliente:", clienteId);
      return null;
    } catch (e) {
      console.error("[loadTabelaAtiva] Erro:", e);
      return null;
    }
  }

  async function loadColaboradores(clienteId: number) {
    if (!clienteId) {
      console.warn("[loadColaboradores] cliente_id não fornecido");
      setColaboradores([]);
      return;
    }
    
    const ctx = await ensureDbContext();
    if (!ctx.tenant) {
      console.warn("[loadColaboradores] tenant não resolvido");
      setColaboradores([]);
      return;
    }

    vinculoEspecialidadesRef.current = new Map();

    try {
      console.log("[loadColaboradores] Carregando colaboradores para cliente:", clienteId);
      
      // Carregar vínculos colaborador-cliente-função (via cliente_id)
      const { data: vinculosData, error: vinculosErr } = await applyTenant(
        supabase
          .from("colaborador_funcao_hh")
          .select("colaborador_id,servico_hh_id,ativo,cliente_id")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .order("colaborador_id", { ascending: true }),
        ctx.tenant
      );
      
      if (vinculosErr) throw vinculosErr;

      const vinculos = (vinculosData ?? []).filter((v) => v.colaborador_id) as Array<{
        colaborador_id: string;
        hh_servico_id?: string | number | null;
      }>;

      if (vinculos.length === 0) {
        console.warn("[loadColaboradores] Nenhum colaborador vinculado ao cliente:", clienteId);
        setColaboradores([]);
        return;
      }

      // Mapear vínculos: colaborador_id → [hh_servico_ids]
      vinculos.forEach((v) => {
        const colabId = String(v.colaborador_id);
        const servicoId = v.hh_servico_id ?? null;
        if (!servicoId) return;
        const list = vinculoEspecialidadesRef.current.get(colabId) ?? [];
        const servicoStr = String(servicoId);
        if (!list.includes(servicoStr)) list.push(servicoStr);
        vinculoEspecialidadesRef.current.set(colabId, list);
      });

      const colaboradorIds = Array.from(new Set(vinculos.map((v) => String(v.colaborador_id))));

      // Carregar dados dos colaboradores
      const { data: colaboradoresData, error: colaboradoresErr } = await applyTenant(
        supabase
          .from("colaboradores")
          .select("id,nome,ativo")
          .in("id", colaboradorIds)
          .eq("ativo", true)
          .order("nome", { ascending: true }),
        ctx.tenant
      );

      if (colaboradoresErr) throw colaboradoresErr;

      const mapped = (colaboradoresData ?? []).map((c: { id: string; nome: string; ativo: boolean }) => ({
        id: String(c.id),
        nome: String(c.nome ?? ""),
        ativo: Boolean(c.ativo),
      }));

      console.log("[loadColaboradores] Carregados", mapped.length, "colaboradores");
      setColaboradores(mapped);
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : JSON.stringify(e);
      console.error("[loadColaboradores] Erro:", message);
      setErr(`Erro ao carregar colaboradores: ${message}`);
      setColaboradores([]);
    }
  }

  async function loadEspecialidadesParaColaborador(clienteId: number, colaboradorId: string) {
    if (!clienteId || !colaboradorId) {
      console.warn("[loadEspecialidadesParaColaborador] cliente_id ou colaborador_id não fornecido");
      setEspecialidadesOptions([]);
      setEspecialidadeLocked(false);
      return;
    }
    
    const ctx = await ensureDbContext();
    if (!ctx.tenant || !ctx.empresa) {
      console.warn("[loadEspecialidadesParaColaborador] tenant/empresa não resolvido");
      setEspecialidadesOptions([]);
      return;
    }

    setEspecialidadesOptions([]);
    setEspecialidadeLocked(false);
    setLancamentoForm((prev) => ({ ...prev, hh_servico_id: "" }));
    setPrecoServicoSelecionado(null);

    try {
      console.log("[loadEspecialidadesParaColaborador] Carregando para", { clienteId, colaboradorId });
      
      // 1. Vínculos via ref map (já carregado em loadColaboradores)
      let servicoIds = vinculoEspecialidadesRef.current.get(colaboradorId) ?? [];

      // 2. Fallback: reconsulta direto se ref não tem (ainda não carregado)
      if (servicoIds.length === 0) {
        const { data, error } = await applyTenant(
          supabase
            .from("colaborador_funcao_hh")
            .select("servico_hh_id,ativo")
            .eq("colaborador_id", colaboradorId)
            .eq("cliente_id", clienteId)
            .eq("ativo", true),
          ctx.tenant
        );
        if (error) throw error;
        const rows = (data ?? []) as Array<{ hh_servico_id?: string | number | null }>;
        servicoIds = Array.from(new Set(rows.map((r) => String(r.hh_servico_id ?? "")).filter(Boolean)));
        
        if (servicoIds.length > 0) {
          console.log("[loadEspecialidadesParaColaborador] Serviços encontrados via fallback:", servicoIds);
        }
      }

      if (servicoIds.length === 0) {
        console.warn("[loadEspecialidadesParaColaborador] Nenhum serviço vinculado");
        setEspecialidadesOptions([]);
        setEspecialidadeLocked(false);
        return;
      }

      // 3. Carregar dados dos serviços (cliente_hh_servicos)
      // IMPORTANTE: empresa é escopada por RLS (current_empresa_id). Não filtrar empresa_id manualmente.
      console.log("[loadEspecialidadesParaColaborador] Buscando serviços com:", {
        tenant_id: ctx.tenant,
        empresa_id: ctx.empresa,
        cliente_id: clienteId,
        servico_ids: servicoIds,
      });

      const { data, error } = await applyTenant(
        supabase
          .from("cliente_hh_servicos")
          .select("id,nome,ativo,preco_base,preco_50,preco_100,cliente_id,empresa_id")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .in("id", servicoIds)
          .order("nome", { ascending: true }),
        ctx.tenant
      );
      if (error) throw error;

      // Mapear mantendo EXATAMENTE o id (bigint) como number
      const mappedOptions: EspecialidadeOption[] = ((data ?? []) as Array<{ id: string | number; nome?: string | null; preco_base?: number; preco_50?: number; preco_100?: number }>).map(
        (o) => ({
          id: String(Number(o.id)), // Garantir conversão correta: string do number
          descricao: o.nome ?? null,
        })
      );
      console.log("[loadEspecialidadesParaColaborador] Serviços mapeados:", mappedOptions);

      console.log("[loadEspecialidadesParaColaborador] Opções carregadas:", mappedOptions.length);
      setEspecialidadesOptions(mappedOptions);

      // Se apenas 1 especialidade, auto-selecionar
      if (mappedOptions.length === 1) {
        const servicoId = String(mappedOptions[0].id);
        setEspecialidadeLocked(true);
        setLancamentoForm((prev) => ({ ...prev, hh_servico_id: servicoId }));
        
        // Pré-carregar preços da especialidade selecionada
        const servicoRows = (data ?? []) as Array<{
          id: string | number;
          preco_base?: number | null;
          preco_50?: number | null;
          preco_100?: number | null;
        }>;
        const servicoData = servicoRows.find((r) => String(r.id) === servicoId) ?? null;
        if (servicoData) {
          setPrecoServicoSelecionado({
            preco_base: Number(servicoData.preco_base ?? 0),
            preco_50: Number(servicoData.preco_50 ?? 0),
            preco_100: Number(servicoData.preco_100 ?? 0),
          });
        }
      } else if (mappedOptions.length > 1) {
        setEspecialidadeLocked(false);
        setLancamentoForm((prev) => {
          const current = String(prev.hh_servico_id ?? "").trim();
          const valid = mappedOptions.some((opt) => String(opt.id) === current);
          return valid ? prev : { ...prev, hh_servico_id: "" };
        });
      }
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : JSON.stringify(e);
      console.error("[loadEspecialidadesParaColaborador] Erro:", message);
      setErr(`Erro ao carregar especialidades: ${message}`);
      setEspecialidadesOptions([]);
      setEspecialidadeLocked(false);
    }
  }

  async function loadHhLancamentos() {
    if (!Number.isFinite(osId)) return;
    setLoadingHh(true);
    setHhErr(null);
    try {
      const ctx = await ensureDbContext();
      if (!ctx.tenant || !ctx.empresa) {
        setHhErr("Tenant/empresa não carregados.");
        setHhRows([]);
        return;
      }

      console.log("[loadHhLancamentos] Carregando dados de hh_lancamentos...", { osId });

      // Carrega direto da tabela hh_lancamentos (sem view)
      const result = await applyTenantEmpresa(
        supabase
          .from("hh_lancamentos")
          .select(
            "id,os_id,data,colaborador_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,horas_trabalhadas,percentual_aplicado,observacao,criado_em,hh_tipo_id,valor_hora,valor_total,hh_especialidade_id"
          )
          .eq("os_id", osId)
          .order("data", { ascending: false })
          .order("criado_em", { ascending: false }),
        ctx.tenant,
        ctx.empresa
      );

      if (result.error) {
        console.error("[loadHhLancamentos] Erro ao carregar tabela:", result.error);
        throw result.error;
      }

      const rows = (result.data ?? []) as Array<{
        id: number | string;
        os_id: number;
        data: string;
        colaborador_id?: string;
        entrada_1?: string | null;
        saida_1?: string | null;
        entrada_2?: string | null;
        saida_2?: string | null;
        hora_entrada?: string | null;
        hora_saida?: string | null;
        horas_trabalhadas?: number | null;
        percentual_aplicado?: number | null;
        observacao?: string | null;
        criado_em?: string | null;
        hh_tipo_id?: number | string | null;
        valor_hora?: number | null;
        valor_total?: number | null;
        hh_especialidade_id?: string | null;
      }>;

      console.log("[loadHhLancamentos] Carregados", rows.length, "registros da tabela");

      if (rows.length === 0) {
        setHhRows([]);
        return;
      }

      // Carrega colaboradores que faltam
      const colaboradorIds = Array.from(
        new Set(rows.map((r) => String(r.colaborador_id)).filter(Boolean))
      );

      const colaboradorMap = new Map<string, string>();
      if (colaboradorIds.length > 0) {
        console.log("[loadHhLancamentos] Carregando", colaboradorIds.length, "colaboradores...");
        const { data: colabData, error: colabErr } = await supabase
          .from("colaboradores")
          .select("id,nome")
          .in("id", colaboradorIds);

        if (colabErr) {
          console.warn("[loadHhLancamentos] Erro ao carregar colaboradores:", colabErr);
        } else if (colabData) {
          (colabData as Array<{ id: string; nome: string }>).forEach((c) => {
            colaboradorMap.set(String(c.id), c.nome);
          });
          console.log("[loadHhLancamentos] Colaboradores carregados:", colaboradorMap.size);
        }
      }

      // Carrega especialidades que faltam
      const especialidadeIds = Array.from(
        new Set(rows.map((r) => String(r.hh_especialidade_id)).filter((id) => id !== "null" && id !== ""))
      );

      const especialidadeMap = new Map<string, string>();
      if (especialidadeIds.length > 0) {
        console.log("[loadHhLancamentos] Carregando", especialidadeIds.length, "especialidades...");
        const { data: espData, error: espErr } = await supabase
          .from("hh_especialidades")
          .select("id,descricao")
          .in("id", especialidadeIds);

        if (espErr) {
          console.warn("[loadHhLancamentos] Erro ao carregar especialidades:", espErr);
        } else if (espData) {
          (espData as Array<{ id: string; descricao: string }>).forEach((e) => {
            especialidadeMap.set(String(e.id), e.descricao);
          });
          console.log("[loadHhLancamentos] Especialidades carregadas:", especialidadeMap.size);
        }
      }

      // Mapeia dados para formato HhLancamentoViewRow
      const mapped: HhLancamentoViewRow[] = rows.map((r) => {
        const percentual = Number(r.percentual_aplicado ?? getPercentualFromDate(r.data));
        return {
          ...r,
          entrada_1: r.entrada_1 ?? null,
          saida_1: r.saida_1 ?? null,
          entrada_2: r.entrada_2 ?? null,
          saida_2: r.saida_2 ?? null,
          hora_entrada: r.hora_entrada ?? null,
          hora_saida: r.hora_saida ?? null,
          horas_trabalhadas: r.horas_trabalhadas ?? null,
          valor_hora: r.valor_hora ?? null,
          valor_total: r.valor_total ?? null,
          observacao: r.observacao ?? null,
          criado_em: r.criado_em ?? null,
          colaborador_nome: colaboradorMap.get(String(r.colaborador_id)) ?? "—",
          hh_tipo_descricao: getTipoHHLabel(percentual),
          especialidade_descricao: r.hh_especialidade_id
            ? especialidadeMap.get(String(r.hh_especialidade_id)) ?? "—"
            : null,
          hh_servico_id: null, // Não disponível na tabela
        };
      });

      console.log("[loadHhLancamentos] Dados prontos para exibição:", mapped.length, "registros");
      setHhRows(mapped);
    } catch (e: unknown) {
      let message = "Erro ao carregar lançamentos HH.";

      if (e instanceof Error) {
        message = e.message;
      } else if (typeof e === "object" && e !== null) {
        const err = e as Record<string, unknown>;
        if (typeof err.message === "string") {
          message = err.message;
        }
      }

      console.error("loadHhLancamentos error:", { osId, message, fullError: e });
      setHhErr(message);
      setHhRows([]);
    } finally {
      setLoadingHh(false);
    }
  }

  function closeLancamentoForm() {
    setShowLancamentoForm(false);
    setEditingId(null);
    setErr(null);
    setOk(null);
  }

  async function openEditHhLancamento(rowId: string) {
    if (!canWrite) return;
    setErr(null);
    setOk(null);
    setEditingId(rowId);
    setShowLancamentoForm(true);

    try {
      const ctx = await ensureDbContext();
      if (!ctx.tenant || !ctx.empresa) {
        setErr("Tenant/empresa não carregados.");
        return;
      }

      // Busca na tabela base para garantir IDs (colaborador_id, etc.)
      const selectOldBase = "id,data,colaborador_id,hora_entrada,hora_saida,percentual_aplicado,observacao,hh_servico_id";
      const selectNewBase = "id,data,colaborador_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,percentual_aplicado,observacao,hh_servico_id";
      const selectOldWithEsp = selectOldBase;
      const selectNewWithEsp = selectNewBase;

      const first = await supabase.from("hh_lancamentos").select(selectNewWithEsp).eq("id", rowId).maybeSingle();

      const second =
        first.error && isMissingColumnError(first.error)
          ? await supabase.from("hh_lancamentos").select(selectOldWithEsp).eq("id", rowId).maybeSingle()
          : null;

      const third =
        second?.error && isMissingColumnError(second.error)
          ? await supabase.from("hh_lancamentos").select(selectOldBase).eq("id", rowId).maybeSingle()
          : null;

      type HhLancamentoRow = {
        id: string | number;
        data: string | null;
        colaborador_id: string | null;
        entrada_1?: string | null;
        saida_1?: string | null;
        entrada_2?: string | null;
        saida_2?: string | null;
        hora_entrada: string | null;
        hora_saida: string | null;
        percentual_aplicado: number | null;
        observacao: string | null;
        hh_servico_id?: string | number | null;
      };

      const data = (third?.data ?? second?.data ?? first.data) as unknown as HhLancamentoRow | null;
      const error = third?.error ?? second?.error ?? first.error;

      if (error) throw error;
      if (!data) {
        setErr("Lançamento não encontrado.");
        return;
      }

      setLancamentoForm({
        data: String(data.data ?? new Date().toISOString().slice(0, 10)),
        colaborador_id: String(data.colaborador_id ?? ""),
        hh_servico_id: String(data.hh_servico_id ?? ""),
        observacao: String(data.observacao ?? ""),
      });

      const e1 = formatTimeHHMM(data.entrada_1) || "";
      const s1 = formatTimeHHMM(data.saida_1) || "";
      const e2 = formatTimeHHMM(data.entrada_2) || "";
      const s2 = formatTimeHHMM(data.saida_2) || "";

      // Fallback de schema antigo (hora_entrada/hora_saida) para preencher UI
      const oldE = formatTimeHHMM(data.hora_entrada) || "";
      const oldS = formatTimeHHMM(data.hora_saida) || "";

      // Se for schema antigo (apenas hora_entrada/hora_saida), preenche o 1º período e deixa o 2º vazio.
      setHoraEntrada1(e1 || oldE || "07:30");
      setHoraSaida1(s1 || oldS || "12:00");
      setHoraEntrada2(e2 || "13:00");
      setHoraSaida2(s2 || oldS || "17:00");
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao carregar lançamento para edição.";
      setErr(message);
    }
  }

  async function excluirHhLancamento(id: string) {
    if (!canDelete) return;
    const okConfirm = confirm("Excluir este lançamento de HH?");
    if (!okConfirm) return;

    try {
      setErr(null);
      const ctx = await ensureDbContext();
      if (!ctx.tenant || !ctx.empresa) {
        setErr("Tenant/empresa não carregados.");
        return;
      }
      const { error } = await supabase.from("hh_lancamentos").delete().eq("id", id);
      if (error) throw error;
      setOk("Lançamento excluído.");
      await loadHhLancamentos();
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao excluir lançamento.";
      setErr(message);
    }
  }

  async function salvarLancamento(): Promise<boolean> {
    const ctx = await ensureDbContext();
    if (!ctx.tenant || !ctx.empresa || !canWrite) {
      setErr("Sem permissão ou contexto (tenant/empresa) não carregado.");
      return false;
    }

    if (!lancamentoForm.data || !lancamentoForm.colaborador_id) {
      setErr("Informe data e colaborador.");
      return false;
    }

    const entrada1 = parseHHMM(horaEntrada1);
    const saida1 = parseHHMM(horaSaida1);
    const e2Raw = String(horaEntrada2 ?? "").trim();
    const s2Raw = String(horaSaida2 ?? "").trim();
    const entrada2 = parseHHMM(e2Raw);
    const saida2 = parseHHMM(s2Raw);

    if (entrada1 === null) {
      setErr("Entrada 1 inválida (use HH:MM). Ex: 07:30");
      return false;
    }
    if (saida1 === null) {
      setErr("Saída 1 inválida (use HH:MM). Ex: 12:00");
      return false;
    }
    if (!e2Raw) {
      setErr("Entrada 2 é obrigatória.");
      return false;
    }
    if (!s2Raw) {
      setErr("Saída 2 é obrigatória.");
      return false;
    }
    if (entrada2 === null) {
      setErr("Entrada 2 inválida (use HH:MM). Ex: 13:00");
      return false;
    }
    if (saida2 === null) {
      setErr("Saída 2 inválida (use HH:MM). Ex: 17:00");
      return false;
    }

    // Validar períodos
    if (entrada1 >= saida1) {
      setErr("Entrada 1 deve ser menor que Saída 1.");
      return false;
    }
    if (entrada2 >= saida2) {
      setErr("Entrada 2 deve ser menor que Saída 2.");
      return false;
    }
    if (saida1 > entrada2) {
      setErr("Saída 1 deve ser menor ou igual a Entrada 2 (sem sobreposição).");
      return false;
    }

    // Converter minutos para HH:MM para payload
    const minutosParaHHMM = (minutos: number): string => {
      const hh = Math.floor(minutos / 60);
      const mm = minutos % 60;
      return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    };

    if (especialidadesOptions.length > 0 && !String(lancamentoForm.hh_servico_id ?? "").trim()) {
      setErr("Selecione a especialidade.");
      return false;
    }
    if (especialidadesOptions.length === 0) {
      setErr("Nenhuma especialidade vinculada a este colaborador.");
      return false;
    }

    setLancamentoBusy(true);
    setErr(null);
    try {
      const descRaw = String(lancamentoForm.observacao ?? "").trim();
      const hhServicoIdRaw = String(lancamentoForm.hh_servico_id ?? "").trim();
      const hhServicoId = hhServicoIdRaw ? Number(hhServicoIdRaw) : NaN;
      
      // DEBUG LOG: Mostrar exatamente o que foi recebido
      console.warn("[salvarLancamento] VALIDAÇÃO DE ENTRADA:", {
        timestamp: new Date().toISOString(),
        colaborador_id: lancamentoForm.colaborador_id,
        data: lancamentoForm.data,
        hh_servico_id_form: lancamentoForm.hh_servico_id,
        hh_servico_id_string: hhServicoIdRaw,
        hh_servico_id_number: hhServicoId,
        isFinite: Number.isFinite(hhServicoId),
        especialidadesOptionosCount: especialidadesOptions.length,
        opcoesDisponiveis: especialidadesOptions.map((opt) => ({
          id: opt.id,
          descricao: opt.descricao,
        })),
      });
      
      if (!Number.isFinite(hhServicoId)) {
        setErr("Especialidade inválida.");
        return false;
      }

      // Validação prática: serviço HH precisa existir/estar ativo.
      try {
        const svcBase = supabase.from("cliente_hh_servicos").select("id,ativo").eq("id", hhServicoId);
        const svcQ = ctx.empresa ? applyTenantEmpresa(svcBase, ctx.tenant, ctx.empresa) : applyTenant(svcBase, ctx.tenant);
        const { data: svcData, error: svcErr } = await svcQ.maybeSingle();
        if (svcErr) throw svcErr;
        if (!svcData) {
          setErr("Especialidade (serviço HH) não encontrada.");
          return false;
        }
      } catch (svcE) {
        console.warn("Falha ao validar serviço HH:", svcE);
      }

      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      // VALIDAÇÃO CRÍTICA: Verificar se o colaborador tem vínculo com este serviço neste cliente
      if (!clienteIdContext) {
        setErr("Cliente não identificado na OS. Não é possível lançar horas.");
        setLancamentoBusy(false);
        return false;
      }

      if (!hhServicoId || !Number.isFinite(hhServicoId)) {
        setErr("Serviço HH inválido ou não selecionado.");
        setLancamentoBusy(false);
        return false;
      }

      if (!lancamentoForm.colaborador_id) {
        setErr("Colaborador não selecionado.");
        setLancamentoBusy(false);
        return false;
      }

      console.warn("[salvarLancamento] VALIDANDO vínculo:", {
        tenant_id: ctx.tenant,
        cliente_id: clienteIdContext,
        colaborador_id: lancamentoForm.colaborador_id,
        hh_servico_id: hhServicoId,
      });

      // 1. Verificar se o vínculo existe na tabela colaborador_funcao_hh
      const { data: vinculoExistente, error: checkVinculoErr } = await applyTenant(
        supabase
          .from("colaborador_funcao_hh")
          .select("id,ativo")
          .eq("tenant_id", ctx.tenant)
          .eq("cliente_id", clienteIdContext)
          .eq("colaborador_id", lancamentoForm.colaborador_id)
          .eq("servico_hh_id", hhServicoId)
          .maybeSingle(),
        ctx.tenant
      );

      if (checkVinculoErr) {
        console.error("[salvarLancamento] Erro ao validar vínculo:", checkVinculoErr);
        setErr(`Erro ao validar vínculo: ${checkVinculoErr.message}`);
        setLancamentoBusy(false);
        return false;
      }

      // 2. Se não existe, criar o vínculo
      if (!vinculoExistente) {
        console.warn("[salvarLancamento] Vínculo não encontrado, criando automaticamente...");
        const { error: criarVinculoErr } = await applyTenant(
          supabase.from("colaborador_funcao_hh").insert({
            tenant_id: ctx.tenant,
            cliente_id: clienteIdContext,
            colaborador_id: lancamentoForm.colaborador_id,
            servico_hh_id: hhServicoId,
            ativo: true,
          }),
          ctx.tenant
        );

        if (criarVinculoErr) {
          console.error("[salvarLancamento] Erro ao criar vínculo:", criarVinculoErr);
          // Pode ser erro de constraint já existindo, tenta continuar
          if (!criarVinculoErr.message.includes("duplicate") && !criarVinculoErr.message.includes("Conflito")) {
            setErr(`Erro ao vincular colaborador: ${criarVinculoErr.message}`);
            setLancamentoBusy(false);
            return false;
          }
        } else {
          console.log("[salvarLancamento] Vínculo criado com sucesso");
        }
      } else if (vinculoExistente && !vinculoExistente.ativo) {
        // 3. Se existe mas está inativo, ativar
        console.warn("[salvarLancamento] Vínculo inativo, ativando...");
        const { error: ativarErr } = await applyTenant(
          supabase
            .from("colaborador_funcao_hh")
            .update({ ativo: true })
            .eq("tenant_id", ctx.tenant)
            .eq("cliente_id", clienteIdContext)
            .eq("colaborador_id", lancamentoForm.colaborador_id)
            .eq("servico_hh_id", hhServicoId),
          ctx.tenant
        );

        if (ativarErr) {
          console.warn("[salvarLancamento] Erro ao ativar vínculo (ignorando):", ativarErr);
        } else {
          console.log("[salvarLancamento] Vínculo ativado com sucesso");
        }
      } else {
        console.log("[salvarLancamento] Vínculo já existe e está ativo ✓");
      }

      const percentual = getPercentualFromDate(lancamentoForm.data) as 0 | 50 | 100;

      // Carregar os preços diretos de cliente_hh_servicos para usar na gravação
      const { data: svcData, error: svcErr } = await supabase
        .from("cliente_hh_servicos")
        .select("preco_base,preco_50,preco_100")
        .eq("id", hhServicoId)
        .maybeSingle();

      if (svcErr || !svcData) {
        setErr("Serviço HH não encontrado ou sem preços configurados.");
        setLancamentoBusy(false);
        return false;
      }

      // Usar o preço correto baseado no percentual
      const preco_base = Number(svcData.preco_base ?? 0);
      const preco_50 = Number(svcData.preco_50 ?? 0);
      const preco_100 = Number(svcData.preco_100 ?? 0);
      const valorHoraAplicado = percentual === 0 ? preco_base : (percentual === 50 ? preco_50 : preco_100);

      // hh_tipo_id DEVE SER o ID do serviço HH selecionado, não um tipo de hora genérico
      // hhServicoId já foi validado acima, é o ID real do cliente_hh_servicos
      const hhTipoId = hhServicoId;
      
      console.warn("[salvarLancamento] hh_tipo_id resolvido:", {
        servicoId: hhServicoId,
        tipoId: hhTipoId,
        isFinite: Number.isFinite(hhTipoId),
      });

      // DEBUG: Log completo antes de salvar
      console.warn("[salvarLancamento] VALORES ANTES DE ENVIAR:", {
        _contexto: {
          tenant_id: ctx.tenant,
          empresa_id: ctx.empresa,
          cliente_id: clienteIdContext,
        },
        _formulario: {
          colaborador_id: lancamentoForm.colaborador_id,
          hh_servico_id_form: lancamentoForm.hh_servico_id,
          data: lancamentoForm.data,
        },
        _hh_tipo: {
          hhTipoId: hhTipoId,
          percentual_aplicado: percentual,
        },
        _horarios: {
          hora_entrada: horaEntrada1,
          hora_saida: horaSaida2,
        },
        _valores: {
          valor_hora: valorHoraAplicado,
          percentual_aplicado: percentual,
        },
      });

      // ✅ NOVO: Enviar para campos NOVOS (entrada_1, saida_1, entrada_2, saida_2)
      // Manter compatibilidade com legado via trigger
      const basePayload = {
        tenant_id: ctx.tenant,
        os_id: osId,
        colaborador_id: lancamentoForm.colaborador_id,
        hh_tipo_id: hhTipoId,
        data: lancamentoForm.data,
        // ✅ NOVOS (principais):
        entrada_1: minutosParaHHMM(entrada1),
        saida_1: minutosParaHHMM(saida1),
        entrada_2: minutosParaHHMM(entrada2),
        saida_2: minutosParaHHMM(saida2),
        // Legacy (compatibilidade - trigger mantém em sync):
        hora_entrada: minutosParaHHMM(entrada1),
        hora_saida: minutosParaHHMM(saida2),
        percentual_aplicado: percentual,
        observacao: descRaw || null,
        valor_hora: valorHoraAplicado,
      };

      console.warn("[HH_SAVE_PAYLOAD] Payload final a ser enviado:", {
        ...basePayload,
        _debug_horarios: {
          entrada_1_minutos: entrada1,
          saida_1_minutos: saida1,
          entrada_2_minutos: entrada2,
          saida_2_minutos: saida2,
          horas_periodo1: ((saida1 - entrada1) / 60).toFixed(2),
          horas_periodo2: ((saida2 - entrada2) / 60).toFixed(2),
          horas_total: (((saida1 - entrada1) + (saida2 - entrada2)) / 60).toFixed(2),
        },
      });

      if (editingId) {
        const { error } = await supabase
          .from("hh_lancamentos")
          .update(basePayload)
          .eq("id", editingId)
          .eq("tenant_id", ctx.tenant);

        if (error) throw error;
        setOk("Lançamento HH atualizado!");
      } else {
        const { error } = await supabase.from("hh_lancamentos").insert({
          ...basePayload,
          criado_por: userEmail,
        });

        if (error) throw error;
        setOk("Lançamento HH salvo com sucesso!");
      }

      await loadHhLancamentos();
      await loadRelatorios();
      return true;
    } catch (e: unknown) {
      const errorMsg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error("Erro ao salvar lançamento HH:", errorMsg, {
        osId,
        editingId,
        payload: {
          colaborador_id: lancamentoForm.colaborador_id,
          data: lancamentoForm.data,
          hora_entrada: horaEntrada1,
          hora_saida: horaSaida2,
          entrada_1: horaEntrada1,
          saida_1: horaSaida1,
          entrada_2: e2Raw,
          saida_2: s2Raw,
          hh_servico_id: lancamentoForm.hh_servico_id,
        },
      });
      setErr(formatSupabaseError(e));
      return false;
    } finally {
      setLancamentoBusy(false);
    }
  }

  async function submitAndAdvance(): Promise<void> {
    if (lancamentoBusy) return;
    if (lancamentoSubmitLockRef.current) return;
    lancamentoSubmitLockRef.current = true;
    try {
      const okSave = await salvarLancamento();
      if (!okSave) return;

      setErr(null);

      if (editingId) {
        closeLancamentoForm();
        return;
      }

      setLancamentoForm((prev) => {
        const nextDate = addOneDayISO(prev.data);
        return {
          ...prev,
          data: nextDate,
        };
      });
      setTimeout(() => {
        lancamentoDateRef.current?.focus();
      }, 0);
    } finally {
      lancamentoSubmitLockRef.current = false;
    }
  }

  function handleLancamentoKeyDownCapture(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== "Enter") return;
    if (e.shiftKey || e.altKey || e.metaKey || e.ctrlKey) return;
    if (lancamentoBusy) return;

    const target = e.target as HTMLElement | null;
    if (target?.tagName === "TEXTAREA") return;

    e.preventDefault();
    e.stopPropagation();
    void submitAndAdvance();
  }

  // DEPRECATED: geração de relatório via RPC removida.
  // Mantido apenas o fluxo de lançamento HH + exportação em PDF.

  useEffect(() => {
    void loadRelatorios();
    void loadHhLancamentos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, osId, osDetail?.cliente_id]);

  // Quando abre formulário ou muda a data: carregar tabela e colaboradores
  useEffect(() => {
    if (!showLancamentoForm) return;
    if (!clienteIdContext) {
      console.warn("[useEffect] cliente_id não disponível");
      setTabelaAtiva(null);
      setColaboradores([]);
      return;
    }

    const run = async () => {
      console.log("[useEffect] Carregando contexto HH para data:", lancamentoForm.data);
      
      // 1. Carregar tabela ativa para a data
      const tabela = await loadTabelaAtiva(clienteIdContext, lancamentoForm.data);
      setTabelaAtiva(tabela);
      
      if (!tabela) {
        console.warn("[useEffect] Tabela HH não encontrada para cliente:", clienteIdContext);
        setColaboradores([]);
        setEspecialidadesOptions([]);
        setEspecialidadeLocked(false);
        return;
      }
      
      // 2. Carregar colaboradores vinculados ao cliente
      await loadColaboradores(clienteIdContext);
    };

    void run();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showLancamentoForm, lancamentoForm.data, clienteIdContext]);

  // Quando colaborador muda: carregar especialidades vinculadas
  useEffect(() => {
    if (!showLancamentoForm) return;
    if (!tabelaAtiva?.id) {
      console.warn("[useEffect] Tabela HH não está ativa");
      return;
    }
    if (!clienteIdContext) {
      console.warn("[useEffect] cliente_id não disponível");
      return;
    }
    
    const colabId = String(lancamentoForm.colaborador_id ?? "").trim();
    if (!colabId) {
      setEspecialidadesOptions([]);
      setEspecialidadeLocked(false);
      setLancamentoForm((prev) => ({ ...prev, hh_servico_id: "" }));
      return;
    }

    void loadEspecialidadesParaColaborador(clienteIdContext, colabId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showLancamentoForm, tabelaAtiva?.id, lancamentoForm.colaborador_id, clienteIdContext]);

  if (!ready && permissionsLoading) {
    return (
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 text-sm text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  if (!canRead) return null;

  return (
    <section className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold">Relatório HH</h2>
          <p className="text-sm text-zinc-400">
            Geração e consulta do relatório de horas da OS.{" "}
            <a
              href="/cadastros/hh/servicos-cliente"
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-400 hover:underline text-xs"
            >
              Cadastrar serviços →
            </a>
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={loadRelatorios}
            disabled={loadingHh}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            {loadingHh ? "Atualizando..." : "Atualizar"}
          </button>
          {canWrite && (
            <button
              onClick={() => {
                // Novo lançamento (não edição)
                setEditingId(null);
                setErr(null);
                setOk(null);
                const today = new Date().toISOString().slice(0, 10);
                setLancamentoForm({
                  data: today,
                  colaborador_id: "",
                  hh_servico_id: "",
                  observacao: "",
                });
                setHoraEntrada1("07:30");
                setHoraSaida1("12:00");
                setHoraEntrada2("13:00");
                setHoraSaida2("17:00");

                setShowLancamentoForm(true);
              }}
              className="px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
            >
              Lançar Horas
            </button>
          )}
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      {/* Formulário de Lançamento */}
      {showLancamentoForm && (
        <div
          className="border border-zinc-800 rounded-lg p-4 bg-zinc-900/40 space-y-3"
          onKeyDownCapture={handleLancamentoKeyDownCapture}
        >
          <div className="flex items-center justify-between">
            <h3 className="font-semibold">{editingId ? "Editar Lançamento HH" : "Novo Lançamento HH"}</h3>
            <button
              onClick={closeLancamentoForm}
              className="text-zinc-400 hover:text-zinc-200"
            >
              ✕
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Colaborador *</label>
              <select
                aria-label="Selecionar colaborador"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.colaborador_id}
                onChange={(e) =>
                  setLancamentoForm((prev) => ({ ...prev, colaborador_id: e.target.value }))
                }
              >
                <option value="">Selecione...</option>
                {colaboradores.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nome}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Tipo HH</label>
              <input
                aria-label="Tipo HH (automático)"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-300"
                value={getTipoHHLabel(getPercentualFromDate(lancamentoForm.data))}
                readOnly
                disabled
              />
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Data *</label>
              <input
                type="date"
                aria-label="Data do lançamento"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                ref={lancamentoDateRef}
                value={lancamentoForm.data}
                onChange={(e) => {
                  const nextDate = e.target.value;
                  setLancamentoForm((prev) => ({
                    ...prev,
                    data: nextDate,
                  }));
                }}
              />
              <div className="text-[11px] text-zinc-500">
                {(() => {
                  const p = getPercentualFromDate(lancamentoForm.data);
                  if (p === 50) return "Sábado (50%)";
                  if (p === 100) return "Domingo (100%)";
                  return "Dias de semana (0%)";
                })()}
              </div>
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Especialidade</label>
              <select
                aria-label="Selecionar especialidade"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.hh_servico_id}
                onChange={(e) => {
                  const servicoId = e.target.value;
                  console.warn("[dropdown onChange] Seleção de serviço HH:", {
                    servicoId_string: servicoId,
                    servicoId_number: servicoId ? Number(servicoId) : null,
                    isValid: servicoId && /^\d+$/.test(servicoId),
                    optionsCount: especialidadesOptions.length,
                    opcoesValidas: especialidadesOptions.map((o) => ({ id: String(o.id), descricao: o.descricao })),
                  });

                  setLancamentoForm((prev) => ({ ...prev, hh_servico_id: servicoId }));
                  
                  // Carregar preços do serviço selecionado
                  if (servicoId && /^\d+$/.test(servicoId)) {
                    const servicoIdNum = Number(servicoId);
                    const servicoData = especialidadesOptions.find((opt) => String(opt.id) === servicoId);
                    
                    console.warn("[dropdown onChange] Validação do serviço:", {
                      servicoIdNum,
                      encontradoEmOptions: Boolean(servicoData),
                      descricao: servicoData?.descricao,
                    });

                    // Se não temos os preços já carregados no option, fazer uma query direta
                    if (servicoData) {
                      // Tentar buscar os preços diretamente se disponível
                      (async () => {
                        try {
                          const ctx = await ensureDbContext();
                          if (!ctx.tenant) {
                            console.warn("[dropdown onChange] Tenant não carregado");
                            return;
                          }
                          
                          console.warn("[dropdown onChange] Consultando preços de serviço HH:", {
                            servicoId: servicoIdNum,
                            tenant_id: ctx.tenant,
                          });

                          const { data, error } = await applyTenant(
                            supabase
                              .from("cliente_hh_servicos")
                              .select("id,preco_base,preco_50,preco_100")
                              .eq("id", servicoIdNum),  // ← CORRIGIDO: usar number
                            ctx.tenant
                          );
                          
                          if (error) {
                            console.warn("[dropdown onChange] Erro ao carregar preços:", error);
                            return;
                          }

                          if (data && data.length > 0) {
                            const row = (data[0] ?? null) as {
                              id: string | number;
                              preco_base?: number | null;
                              preco_50?: number | null;
                              preco_100?: number | null;
                            } | null;
                            if (!row) return;
                            console.warn("[dropdown onChange] Preços carregados:", {
                              id: row.id,
                              preco_base: row.preco_base,
                              preco_50: row.preco_50,
                              preco_100: row.preco_100,
                            });
                            
                            setPrecoServicoSelecionado({
                              preco_base: Number(row.preco_base ?? 0),
                              preco_50: Number(row.preco_50 ?? 0),
                              preco_100: Number(row.preco_100 ?? 0),
                            });
                          } else {
                            console.warn("[dropdown onChange] Nenhum serviço encontrado com id:", servicoIdNum);
                          }
                        } catch (e) {
                          console.error("[dropdown onChange] Erro inesperado:", e);
                        }
                      })();
                    }
                  } else {
                    setPrecoServicoSelecionado(null);
                  }
                }}
                disabled={especialidadeLocked}
              >
                {especialidadesOptions.length === 0 && <option value="">(Sem)</option>}
                {especialidadesOptions.map((esp) => (
                  <option key={esp.id} value={esp.id}>
                    {esp.descricao ?? esp.id}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {precoServicoSelecionado && (
            <div className="bg-zinc-900/60 border border-zinc-700 rounded-lg p-4 space-y-2">
              <div className="text-xs font-semibold text-zinc-300 uppercase">Valores de hora para esta especialidade:</div>
              <div className="grid grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-[11px] text-zinc-400">Normal (0%)</div>
                  <div className="text-sm font-medium text-emerald-300">
                    R$ {Number(precoServicoSelecionado.preco_base).toFixed(2).replace(".", ",")}
                  </div>
                </div>
                <div className="space-y-1">
                  <div className="text-[11px] text-zinc-400">Extra 50%</div>
                  <div className="text-sm font-medium text-amber-300">
                    R$ {Number(precoServicoSelecionado.preco_50).toFixed(2).replace(".", ",")}
                  </div>
                </div>
                <div className="space-y-1">
                  <div className="text-[11px] text-zinc-400">Extra 100%</div>
                  <div className="text-sm font-medium text-red-300">
                    R$ {Number(precoServicoSelecionado.preco_100).toFixed(2).replace(".", ",")}
                  </div>
                </div>
              </div>
            </div>
          )}

          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Entrada 1 *</label>
              <input
                type="time"
                aria-label="Entrada 1"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaEntrada1}
                onChange={(e) => setHoraEntrada1(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Saída 1 *</label>
              <input
                type="time"
                aria-label="Saída 1"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaSaida1}
                onChange={(e) => setHoraSaida1(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Entrada 2 *</label>
              <input
                type="time"
                aria-label="Entrada 2"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaEntrada2}
                onChange={(e) => setHoraEntrada2(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Saída 2 *</label>
              <input
                type="time"
                aria-label="Saída 2"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaSaida2}
                onChange={(e) => setHoraSaida2(e.target.value)}
              />
            </div>
          </div>

          <div className="flex items-end justify-end">
            <button
              onClick={submitAndAdvance}
              disabled={lancamentoBusy}
              className="px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium disabled:opacity-60"
            >
              {lancamentoBusy ? "Salvando..." : editingId ? "Salvar alterações" : "Salvar"}
            </button>
          </div>

          <div className="space-y-1">
            <label className="text-xs text-zinc-400">Observação</label>
            <textarea
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm min-h-[60px]"
              value={lancamentoForm.observacao}
              onChange={(e) =>
                setLancamentoForm((prev) => ({ ...prev, observacao: e.target.value }))
              }
              onKeyDown={(e) => {
                // Enter deve quebrar linha no textarea.
                // Opcional: Ctrl+Enter salva.
                if (e.key !== "Enter") return;
                if (lancamentoBusy) return;
                if (e.ctrlKey || e.metaKey) {
                  e.preventDefault();
                  e.stopPropagation();
                  void submitAndAdvance();
                }
              }}
              placeholder="Observações opcionais..."
            />
          </div>
        </div>
      )}

      {/* Tabela: lançamentos HH (cobrança) desta OS */}
      <div className="flex items-center justify-between gap-3 mb-3">
        <div>
          <h3 className="text-lg font-semibold">Lançamentos HH</h3>
          <p className="text-xs text-zinc-400 mt-0.5">{hhRows.length} registro(s)</p>
        </div>
        {!loadingHh && !hhErr && hhRows.length > 0 && (
          <button
            type="button"
            onClick={() => void gerarRelatorioPDF(hhRows, osId)}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            Exportar PDF
          </button>
        )}
      </div>
      
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[1020px]">
            <thead className="bg-zinc-900/60">
              <tr className="text-left text-zinc-200">
                <th className="px-3 py-2">Data</th>
                <th className="px-3 py-2">Colaborador</th>
                <th className="px-3 py-2">Entrada 1</th>
                <th className="px-3 py-2">Saída 1</th>
                <th className="px-3 py-2">Entrada 2</th>
                <th className="px-3 py-2">Saída 2</th>
                <th className="px-3 py-2 text-right">Horas</th>
                <th className="px-3 py-2 text-right">Ações</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {loadingHh && (
                <tr>
                  <td colSpan={8} className="px-3 py-6 text-zinc-400">
                    Carregando lançamentos HH...
                  </td>
                </tr>
              )}

              {!loadingHh && hhErr && (
                <tr>
                  <td colSpan={8} className="px-3 py-6 text-red-400">
                    {hhErr}
                  </td>
                </tr>
              )}

              {!loadingHh && !hhErr && hhRows.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-3 py-6 text-zinc-400">
                    Nenhum lançamento HH ainda.
                  </td>
                </tr>
              )}

              {!loadingHh && !hhErr &&
                hhRows.map((r) => {
                  const rowLocked = !canWrite;
                  const idStr = String(r.id);
                  return (
                    <tr key={idStr} className="hover:bg-zinc-900/40">
                      <td className="px-3 py-2 text-zinc-300 whitespace-nowrap">{formatDateBR(r.data)}</td>
                      <td className="px-3 py-2 text-zinc-200">
                        <div className="font-medium">{r.colaborador_nome ?? "—"}</div>
                        {r.observacao ? <div className="text-xs text-zinc-500 truncate max-w-[260px]">{r.observacao}</div> : null}
                      </td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.entrada_1) || formatTimeHHMM(r.hora_entrada) || "—"}</td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.saida_1) || formatTimeHHMM(r.hora_saida) || "—"}</td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.entrada_2) || "—"}</td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.saida_2) || "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-zinc-200">{formatHoursBR(r.horas_trabalhadas)}</td>
                      <td className="px-3 py-2 text-right whitespace-nowrap">
                        <div className="inline-flex items-center gap-2">
                          <button
                            type="button"
                            onClick={() => void openEditHhLancamento(idStr)}
                            disabled={rowLocked}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
                          >
                            Editar
                          </button>
                          <button
                            type="button"
                            onClick={() => void excluirHhLancamento(idStr)}
                            disabled={rowLocked || !canDelete}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
                          >
                            Excluir
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
