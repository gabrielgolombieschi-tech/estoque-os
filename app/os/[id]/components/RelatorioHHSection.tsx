"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { applyTenant } from "@/lib/db/scopes";

type HHTipoPreco = {
  id: number;
  descricao: string;
  nivel: string;
  categoria: string;
  preco_base: number;
  preco_50: number;
  preco_100: number;
};

type Colaborador = {
  id: string;
  nome: string;
  ativo: boolean;
};

type HHLancamento = {
  id: number;
  colaborador_id: string;
  colaborador_nome: string | null;
  hh_tipo_id: number;
  hh_tipo_descricao: string | null;
  hh_tipo_nivel: string | null;
  data: string;
  hora_entrada: string;
  hora_saida: string;
  horas_trabalhadas: number;
  percentual_aplicado: number;
  valor_hora: number;
  valor_total: number;
  observacao: string | null;
};

type RelatorioRow = {
  id: number;
  data_emissao: string | null;
  periodo_inicio: string;
  periodo_fim: string;
  status: string;
  total: number | null;
};

type RelatorioLinha = {
  id: number;
  colaborador_id: string;
  data: string;
  entrada_1: string | null;
  saida_1: string | null;
  entrada_2: string | null;
  saida_2: string | null;
  horas_trabalhadas: number;
  fator: number;
  tipo_hora_codigo: string | null;
  especialidade_descricao: string | null;
  valor_hora_base: number;
  valor_hora_aplicado: number;
  total: number;
};

function formatMoneyBR(value: number | null | undefined) {
  const n = Number(value ?? 0);
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDateBR(isoDate: string | null | undefined) {
  if (!isoDate) return "--";
  const d = new Date(isoDate + "T00:00:00");
  return d.toLocaleDateString("pt-BR");
}

function formatDecimalCSV(value: number | null | undefined) {
  const n = Number(value ?? 0);
  return n.toFixed(2).replace(".", ",");
}

function csvEscape(value: string | null | undefined) {
  const str = String(value ?? "");
  if (str.includes(";") || str.includes('"') || str.includes("\n")) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

export default function RelatorioHHSection({ osId, osDetail }: { osId: number; osDetail?: { cliente_id: number | null } | null }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId, loading: tenantLoading } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canRead = Boolean(has("apontamentos.read"));
  const canWrite = Boolean(has("apontamentos.write"));

  const [relatorios, setRelatorios] = useState<RelatorioRow[]>([]);
  const [linhas, setLinhas] = useState<RelatorioLinha[]>([]);
  const [relatorioAbertoId, setRelatorioAbertoId] = useState<number | null>(null);

  const [periodoInicio, setPeriodoInicio] = useState("");
  const [periodoFim, setPeriodoFim] = useState("");
  const [loadingRelatorios, setLoadingRelatorios] = useState(false);
  const [loadingLinhas, setLoadingLinhas] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const relatorioAberto = useMemo(
    () => relatorios.find((r) => r.id === relatorioAbertoId) ?? null,
    [relatorios, relatorioAbertoId]
  );

  const hhEnabled = false; // TODO: Verificar se HH está habilitado nesta OS
  const valorOS = 0; // TODO: Calcular valor total da OS
  const saldoOs = null as number | null; // TODO: Calcular saldo disponível

  async function ensureDbContext() {
    // Best-effort: garante tenant/empresa no contexto de RLS antes das queries.
    if (tenantId) {
      try {
        await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      } catch (e) {
        console.warn("set_current_tenant falhou", e);
      }
    }
    if (empresaId) {
      try {
        await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
      } catch (e) {
        console.warn("set_current_empresa falhou", e);
      }
    }
  }

  // Estados para lançamento de horas
  const [showLancamentoForm, setShowLancamentoForm] = useState(false);
  const [lancamentos, setLancamentos] = useState<HHLancamento[]>([]);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [hhTipos, setHhTipos] = useState<HHTipoPreco[]>([]);
  const [lancamentoForm, setLancamentoForm] = useState({
    data: new Date().toISOString().slice(0, 10),
    hora_entrada: "08:00",
    hora_saida: "17:00",
    colaborador_id: "",
    hh_tipo_id: "",
    percentual_aplicado: "100",
    observacao: "",
  });
  const [lancamentoBusy, setLancamentoBusy] = useState(false);

  async function loadRelatorios() {
    if (!tenantId || !Number.isFinite(osId)) return;
    await ensureDbContext();
    setLoadingRelatorios(true);
    setErr(null);
    try {
      const { data, error } = await applyTenant(
        supabase
          .from("os_relatorios_hh")
          .select("id,data_emissao,periodo_inicio,periodo_fim,status,total")
          .eq("os_id", osId)
          .order("data_emissao", { ascending: false }),
        tenantId
      );
      if (error) throw error;
      setRelatorios((data ?? []) as RelatorioRow[]);
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao carregar relatórios.";
      setErr(message);
    } finally {
      setLoadingRelatorios(false);
    }
  }

  async function loadColaboradores() {
    if (!tenantId) return;
    if (!osDetail?.cliente_id) {
      setColaboradores([]);
      return;
    }
    
    await ensureDbContext();
    
    try {
      // 1) Busca vínculos ativos do cliente
      const { data: vinculos, error: vinculosErr } = await applyTenant(
        supabase
          .from("colaborador_cliente_funcao")
          .select("colaborador_id")
          .eq("cliente_id", osDetail.cliente_id)
          .eq("ativo", true),
        tenantId
      );
      
      if (vinculosErr) throw vinculosErr;

      const colaboradorIds = Array.from(new Set((vinculos ?? []).map((v: { colaborador_id: string }) => v.colaborador_id).filter(Boolean)));

      if (colaboradorIds.length === 0) {
        setColaboradores([]);
        return;
      }

      // 2) Busca dados dos colaboradores
      const { data: colaboradoresData, error: colaboradoresErr } = await applyTenant(
        supabase
          .from("colaboradores")
          .select("id,nome,ativo")
          .in("id", colaboradorIds)
          .eq("ativo", true),
        tenantId
      );

      if (colaboradoresErr) throw colaboradoresErr;

      const mapped = (colaboradoresData ?? []).map((c: { id: string; nome: string; ativo: boolean }) => ({
        id: c.id,
        nome: c.nome,
        ativo: c.ativo,
      }));
      
      setColaboradores(mapped);
    } catch (e: unknown) {
      console.error("[loadColaboradores] Erro ao carregar colaboradores:", e);
      setColaboradores([]);
    }
  }

  async function loadHHTipos() {
    if (!tenantId || !empresaId || !osDetail?.cliente_id) return;
    await ensureDbContext();
    try {
      const { data, error } = await supabase
        .from("cliente_hh_servicos")
        .select("id, nome, preco_base, preco_50, preco_100")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("cliente_id", osDetail.cliente_id)
        .eq("ativo", true)
        .order("nome", { ascending: true });
      if (error) throw error;
      
      // Mapear para o formato esperado (compatibilidade)
      const mapped = (data ?? []).map((item: any) => ({
        id: item.id,
        descricao: item.nome,
        nivel: "",
        categoria: "",
        preco_base: item.preco_base,
        preco_50: item.preco_50,
        preco_100: item.preco_100,
      }));
      setHhTipos(mapped as HHTipoPreco[]);
    } catch (e: unknown) {
      console.warn("Erro ao carregar serviços HH do cliente:", e);
    }
  }

  async function salvarLancamento() {
    if (!tenantId || !canWrite) {
      setErr("Sem permissão para lançar horas.");
      return;
    }
    if (!lancamentoForm.colaborador_id || !lancamentoForm.hh_tipo_id) {
      setErr("Selecione colaborador e tipo de hora.");
      return;
    }

    const horaEntrada = new Date(`${lancamentoForm.data}T${lancamentoForm.hora_entrada}`);
    const horaSaida = new Date(`${lancamentoForm.data}T${lancamentoForm.hora_saida}`);
    const horas = (horaSaida.getTime() - horaEntrada.getTime()) / (1000 * 60 * 60);

    if (horas <= 0) {
      setErr("Hora de saída deve ser posterior à hora de entrada.");
      return;
    }

    setLancamentoBusy(true);
    setErr(null);
    try {
      const { error } = await applyTenant(
        supabase.from("apontamentos_hh").insert({
          os_id: osId,
          colaborador_id: lancamentoForm.colaborador_id,
          hh_tipo_id: Number(lancamentoForm.hh_tipo_id),
          data: lancamentoForm.data,
          hora_entrada: lancamentoForm.hora_entrada,
          hora_saida: lancamentoForm.hora_saida,
          horas_trabalhadas: horas,
          percentual_aplicado: Number(lancamentoForm.percentual_aplicado),
          observacao: lancamentoForm.observacao || null,
        }),
        tenantId
      );
      if (error) throw error;
      setOk("Lançamento salvo com sucesso!");
      setLancamentoForm({
        data: new Date().toISOString().slice(0, 10),
        hora_entrada: "08:00",
        hora_saida: "17:00",
        colaborador_id: "",
        hh_tipo_id: "",
        percentual_aplicado: "100",
        observacao: "",
      });
      setShowLancamentoForm(false);
      await loadRelatorios();
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao salvar lançamento.";
      setErr(message);
    } finally {
      setLancamentoBusy(false);
    }
  }

  async function loadLinhas(relatorioId: number) {
    if (!tenantId || !Number.isFinite(relatorioId)) return;
    setLoadingLinhas(true);
    setErr(null);
    try {
      const { data, error } = await applyTenant(
        supabase
          .from("os_relatorios_hh_linhas")
          .select(
            "id,colaborador_id,data,entrada_1,saida_1,entrada_2,saida_2,horas_trabalhadas,fator,tipo_hora_codigo,especialidade_descricao,valor_hora_base,valor_hora_aplicado,total"
          )
          .eq("relatorio_id", relatorioId)
          .order("data", { ascending: true })
          .order("colaborador_id", { ascending: true }),
        tenantId
      );
      if (error) throw error;
      setLinhas((data ?? []) as RelatorioLinha[]);
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao carregar linhas do relatório.";
      setErr(message);
    } finally {
      setLoadingLinhas(false);
    }
  }

  async function handleGerar() {
    if (!tenantId) return;
    if (!periodoInicio || !periodoFim) {
      setErr("Informe o período inicial e final.");
      return;
    }
    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      const { data, error } = await supabase.rpc("gerar_relatorio_hh_os", {
        p_os_id: osId,
        p_periodo_inicio: periodoInicio,
        p_periodo_fim: periodoFim,
      });
      if (error) throw error;

      const result = Array.isArray(data) ? data[0] : data;
      const newId = result?.relatorio_id ? Number(result.relatorio_id) : null;

      setOk("Relatório gerado e fechado.");
      await loadRelatorios();
      if (newId) {
        setRelatorioAbertoId(newId);
        await loadLinhas(newId);
      }
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao gerar relatório.";
      setErr(message);
    } finally {
      setBusy(false);
    }
  }

  function exportarCSV() {
    if (!relatorioAberto || linhas.length === 0) return;

    const headers = [
      "Colaborador",
      "Funcao",
      "Data",
      "Entrada 1",
      "Saida 1",
      "Entrada 2",
      "Saida 2",
      "Horas",
      "Tipo Hora",
      "Fator",
      "Valor Hora Base",
      "Valor Hora Aplicado",
      "Total",
    ];

    const rows = linhas.map((l) => [
      l.colaborador_id,
      l.especialidade_descricao ?? "",
      l.data ? new Date(l.data).toLocaleDateString("pt-BR") : "",
      l.entrada_1 ?? "",
      l.saida_1 ?? "",
      l.entrada_2 ?? "",
      l.saida_2 ?? "",
      formatDecimalCSV(l.horas_trabalhadas),
      l.tipo_hora_codigo ?? "",
      formatDecimalCSV(l.fator),
      formatDecimalCSV(l.valor_hora_base),
      formatDecimalCSV(l.valor_hora_aplicado),
      formatDecimalCSV(l.total),
    ]);

    const csv = [
      headers.map(csvEscape).join(";"),
      ...rows.map((r) => r.map(csvEscape).join(";")),
    ].join("\n");

    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `relatorio_hh_os_${osId}_${relatorioAberto.id}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  useEffect(() => {
    if (tenantLoading) return;
    if (!tenantId || !Number.isFinite(osId)) return;
    void loadRelatorios();
    void loadColaboradores();
    void loadHHTipos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantLoading, tenantId, empresaId, osId, osDetail?.cliente_id]);

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
            disabled={loadingRelatorios}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            {loadingRelatorios ? "Atualizando..." : "Atualizar"}
          </button>
          {canWrite && (
            <button
              onClick={() => setShowLancamentoForm(true)}
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
        <div className="border border-zinc-800 rounded-lg p-4 bg-zinc-900/40 space-y-3">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold">Novo Lançamento de Horas</h3>
            <button
              onClick={() => setShowLancamentoForm(false)}
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
              <label className="text-xs text-zinc-400">Tipo de Hora *</label>
              <select
                aria-label="Selecionar tipo de hora"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.hh_tipo_id}
                onChange={(e) =>
                  setLancamentoForm((prev) => ({ ...prev, hh_tipo_id: e.target.value }))
                }
              >
                <option value="">Selecione...</option>
                {hhTipos.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.descricao}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Data *</label>
              <input
                type="date"
                aria-label="Data do lançamento"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.data}
                onChange={(e) =>
                  setLancamentoForm((prev) => ({ ...prev, data: e.target.value }))
                }
              />
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Percentual Aplicado %</label>
              <input
                type="number"
                aria-label="Percentual aplicado"
                min="0"
                max="200"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.percentual_aplicado}
                onChange={(e) =>
                  setLancamentoForm((prev) => ({
                    ...prev,
                    percentual_aplicado: e.target.value,
                  }))
                }
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Hora Entrada *</label>
              <input
                type="time"
                aria-label="Hora de entrada"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.hora_entrada}
                onChange={(e) =>
                  setLancamentoForm((prev) => ({ ...prev, hora_entrada: e.target.value }))
                }
              />
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Hora Saída *</label>
              <input
                type="time"
                aria-label="Hora de saída"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.hora_saida}
                onChange={(e) =>
                  setLancamentoForm((prev) => ({ ...prev, hora_saida: e.target.value }))
                }
              />
            </div>

            <div className="flex items-end">
              <button
                onClick={salvarLancamento}
                disabled={lancamentoBusy}
                className="w-full px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium disabled:opacity-60"
              >
                {lancamentoBusy ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>

          <div className="space-y-1">
            <label className="text-xs text-zinc-400">Observação</label>
            <textarea
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm min-h-[60px]"
              value={lancamentoForm.observacao}
              onChange={(e) =>
                setLancamentoForm((prev) => ({ ...prev, observacao: e.target.value }))
              }
              placeholder="Observações opcionais..."
            />
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
        <div className="space-y-1">
          <label className="text-xs text-zinc-400">Período Início</label>
          <input
            type="date"
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
            value={periodoInicio}
            onChange={(e) => setPeriodoInicio(e.target.value)}
            aria-label="Data início relatório HH"
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-zinc-400">Período Fim</label>
          <input
            type="date"
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
            value={periodoFim}
            onChange={(e) => setPeriodoFim(e.target.value)}
            aria-label="Data fim relatório HH"
          />
        </div>
        <div className="flex items-end">
          <button
            onClick={handleGerar}
            disabled={!canWrite || busy}
            className="w-full px-4 py-2 rounded-md bg-blue-300 text-blue-950 hover:bg-blue-200 font-medium disabled:opacity-60"
          >
            {busy ? "Gerando..." : "Gerar Relatório"}
          </button>
        </div>
        {!canWrite && (
          <div className="text-xs text-amber-300 flex items-end">
            Sem permissão para gerar.
          </div>
        )}
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div className="border border-zinc-800 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-zinc-800 text-sm text-zinc-300">Relatórios gerados</div>
          <div className="max-h-[320px] overflow-auto">
            <table className="w-full text-sm">
              <thead className="bg-zinc-900/60">
                <tr className="text-left text-zinc-200">
                  <th className="px-3 py-2">Emissão</th>
                  <th className="px-3 py-2">Período</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2 text-right">Total</th>
                  <th className="px-3 py-2 text-right">Ações</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800">
                {relatorios.map((r) => (
                  <tr key={r.id} className={r.id === relatorioAbertoId ? "bg-zinc-900/40" : ""}>
                    <td className="px-3 py-2 text-zinc-300">
                      {r.data_emissao ? new Date(r.data_emissao).toLocaleDateString("pt-BR") : "—"}
                    </td>
                    <td className="px-3 py-2 text-zinc-300">
                      {new Date(r.periodo_inicio).toLocaleDateString("pt-BR")} → {new Date(r.periodo_fim).toLocaleDateString("pt-BR")}
                    </td>
                    <td className="px-3 py-2 text-zinc-300">{r.status}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-zinc-200">R$ {formatMoneyBR(r.total)}</td>
                    <td className="px-3 py-2 text-right">
                      <button
                        onClick={async () => {
                          setRelatorioAbertoId(r.id);
                          await loadLinhas(r.id);
                        }}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                      >
                        Abrir
                      </button>
                    </td>
                  </tr>
                ))}
                {relatorios.length === 0 && (
                  <tr>
                    <td colSpan={5} className="px-3 py-6 text-zinc-400 text-center">
                      Nenhum relatório gerado.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-950 space-y-3">
          <div className="text-sm text-zinc-300">Resumo do relatório</div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-900/40">
              <div className="text-xs text-zinc-400">Total do relatório</div>
              <div className="text-lg font-semibold text-emerald-300">
                R$ {formatMoneyBR(relatorioAberto?.total ?? 0)}
              </div>
            </div>
            <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-900/40">
              <div className="text-xs text-zinc-400">Status</div>
              <div className="text-lg font-semibold text-zinc-200">{relatorioAberto?.status ?? "—"}</div>
            </div>
            <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-900/40">
              <div className="text-xs text-zinc-400">Período</div>
              <div className="text-sm text-zinc-200">
                {relatorioAberto
                  ? `${new Date(relatorioAberto.periodo_inicio).toLocaleDateString("pt-BR")} → ${new Date(relatorioAberto.periodo_fim).toLocaleDateString("pt-BR")}`
                  : "—"}
              </div>
            </div>
            {!hhEnabled && valorOS > 0 && (
              <div className="border border-zinc-800 rounded-lg p-3 bg-zinc-900/40">
                <div className="text-xs text-zinc-400">Valor OS</div>
                <div className="text-sm text-zinc-200">R$ {formatMoneyBR(valorOS)}</div>
                <div className="text-xs text-zinc-400 mt-1">Saldo: R$ {formatMoneyBR(saldoOs ?? 0)}</div>
              </div>
            )}
          </div>

          <button
            onClick={exportarCSV}
            disabled={!relatorioAberto || linhas.length === 0}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
          >
            Exportar CSV
          </button>
        </div>
      </div>

      {relatorioAbertoId && (
        <div className="border border-zinc-800 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-zinc-800 text-sm text-zinc-300 flex items-center justify-between">
            <span>Linhas do relatório</span>
            {loadingLinhas && <span className="text-xs text-zinc-400">Carregando linhas...</span>}
          </div>
          <div className="overflow-auto max-h-[520px]">
            <table className="w-full text-sm min-w-[1200px]">
              <thead className="bg-zinc-900/60">
                <tr className="text-left text-zinc-200">
                  <th className="px-3 py-2">Colaborador</th>
                  <th className="px-3 py-2">Função</th>
                  <th className="px-3 py-2">Data</th>
                  <th className="px-3 py-2">Entrada 1</th>
                  <th className="px-3 py-2">Saída 1</th>
                  <th className="px-3 py-2">Entrada 2</th>
                  <th className="px-3 py-2">Saída 2</th>
                  <th className="px-3 py-2 text-right">Horas</th>
                  <th className="px-3 py-2">Tipo Hora</th>
                  <th className="px-3 py-2 text-right">Fator</th>
                  <th className="px-3 py-2 text-right">Valor Hora Base</th>
                  <th className="px-3 py-2 text-right">Valor Hora Aplicado</th>
                  <th className="px-3 py-2 text-right">Total</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800">
                {linhas.map((l) => (
                  <tr key={l.id} className="hover:bg-zinc-900/40">
                    <td className="px-3 py-2 text-zinc-300">{l.colaborador_id}</td>
                    <td className="px-3 py-2 text-zinc-300">{l.especialidade_descricao ?? "—"}</td>
                    <td className="px-3 py-2 text-zinc-300">{new Date(l.data).toLocaleDateString("pt-BR")}</td>
                    <td className="px-3 py-2 text-zinc-300">{l.entrada_1 ?? "—"}</td>
                    <td className="px-3 py-2 text-zinc-300">{l.saida_1 ?? "—"}</td>
                    <td className="px-3 py-2 text-zinc-300">{l.entrada_2 ?? "—"}</td>
                    <td className="px-3 py-2 text-zinc-300">{l.saida_2 ?? "—"}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-zinc-200">{formatDecimalCSV(l.horas_trabalhadas)}</td>
                    <td className="px-3 py-2 text-zinc-300">{l.tipo_hora_codigo ?? "—"}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-zinc-200">{formatDecimalCSV(l.fator)}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-zinc-200">R$ {formatMoneyBR(l.valor_hora_base)}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-zinc-200">R$ {formatMoneyBR(l.valor_hora_aplicado)}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-emerald-300">R$ {formatMoneyBR(l.total)}</td>
                  </tr>
                ))}

                {!loadingLinhas && relatorioAbertoId && linhas.length === 0 && (
                  <tr>
                    <td colSpan={13} className="px-3 py-6 text-zinc-400 text-center">
                      Nenhuma linha encontrada.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  );
}
