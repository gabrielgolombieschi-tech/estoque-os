"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { formatMoneyBR, parseMoneyBR } from "@/lib/decimal";
import type { OrcamentoStatusCanonical } from "@/lib/comercial/status";
import ResponsavelAprovacaoSelect from "@/components/os/ResponsavelAprovacaoSelect";

// ── Gestão types ─────────────────────────────────────────────────────────────
type GestaoTipo = "projeto" | "execucao";
type GestaoArea = "eletrico" | "mecanico" | "seguranca" | "software";

export type GestaoConfigItem = {
  item_tipo: GestaoTipo;
  area: GestaoArea;
  habilitado: boolean;
  data_prevista: string | null;
  progresso_percent: number;
};

export type GestaoConfig = {
  habilitarGestao: boolean;
  items: GestaoConfigItem[];
};

const gestaoDefs: Array<{
  item_tipo: GestaoTipo;
  area: GestaoArea;
  label: string;
  grupo: "projetos" | "execucoes";
}> = [
  { item_tipo: "projeto", area: "eletrico", label: "Projeto Elétrico", grupo: "projetos" },
  { item_tipo: "projeto", area: "mecanico", label: "Projeto Mecânico", grupo: "projetos" },
  { item_tipo: "projeto", area: "seguranca", label: "Projeto Segurança", grupo: "projetos" },
  { item_tipo: "projeto", area: "software", label: "Projeto Software", grupo: "projetos" },
  { item_tipo: "execucao", area: "eletrico", label: "Execução Elétrica", grupo: "execucoes" },
  { item_tipo: "execucao", area: "mecanico", label: "Execução Mecânica", grupo: "execucoes" },
];

function makeDefaultGestaoItems(): GestaoConfigItem[] {
  return gestaoDefs.map((d) => ({
    item_tipo: d.item_tipo,
    area: d.area,
    habilitado: false,
    data_prevista: null,
    progresso_percent: 0,
  }));
}

// ── Status dialog types ───────────────────────────────────────────────────────
export type OrcamentoStatusDialogPayload = {
  status: OrcamentoStatusCanonical;
  followup: string;
  valorFechado: number | null;
  abrirOs: boolean;
  importarItensOs: boolean;
  responsavelAprovacaoId: string | null;
  tipoDocumento: "OS" | "OV" | null;
  gestao: GestaoConfig | null;
};

export type OrcamentoStatusDialogProps = {
  open: boolean;
  status: OrcamentoStatusCanonical | null;
  loading?: boolean;
  initialFollowup?: string | null;
  initialValorFechado?: number | string | null;
  valorOrcado?: number | string | null;
  canOpenOs?: boolean;
  suggestedTipoDocumento?: "OS" | "OV";
  tenantId?: string | null;
  empresaId?: string | null;
  onCancel: () => void;
  onSave: (payload: OrcamentoStatusDialogPayload) => Promise<void>;
};

type DialogMeta = {
  label: string;
  title: string;
  placeholder: string;
};

const LOST_REASON_OPTIONS = [
  "Maior preco, nao negociaram",
  "Maior preco, nao chegamos no target",
  "Nao atendemos tecnicamente",
  "Prazo de entrega nao atendeu",
  "Cliente cancelou ou adiou o projeto",
  "Concorrente ja homologado",
  "Cliente optou por solucao interna",
  "Escopo mudou e o orcamento perdeu aderencia",
  "Sem retorno do cliente",
] as const;

const LOST_REASON_OTHER = "Outros";

function getInitialLostReasonState(initialFollowup?: string | null): { selected: string; freeText: string } {
  const raw = String(initialFollowup ?? "").trim();
  if (!raw) return { selected: LOST_REASON_OPTIONS[0], freeText: "" };

  const normalizedRaw = raw.toLowerCase();
  for (const option of LOST_REASON_OPTIONS) {
    if (normalizedRaw === option.toLowerCase()) {
      return { selected: option, freeText: "" };
    }
  }

  if (normalizedRaw.startsWith("outros:")) {
    return { selected: LOST_REASON_OTHER, freeText: raw.slice("outros:".length).trim() };
  }

  return { selected: LOST_REASON_OTHER, freeText: raw };
}

function getInitialValorFechadoText(params: {
  status: OrcamentoStatusCanonical | null;
  initialValorFechado?: number | string | null;
  valorOrcado?: number | string | null;
}) {
  if (params.status !== "FECHADO") return "";
  const hasValorFechado =
    params.initialValorFechado !== null &&
    params.initialValorFechado !== undefined &&
    String(params.initialValorFechado).trim() !== "";
  const parsedValorFechado = hasValorFechado ? Number(params.initialValorFechado) : NaN;
  const parsedValorOrcado = Number(params.valorOrcado ?? 0);
  const base = Number.isFinite(parsedValorFechado)
    ? parsedValorFechado
    : Number.isFinite(parsedValorOrcado)
      ? parsedValorOrcado
      : 0;
  return formatMoneyBR(base);
}

const META: Record<OrcamentoStatusCanonical, DialogMeta> = {
  FECHADO: {
    label: "Fechado",
    title: "Marcar como Fechado",
    placeholder: "Ex.: Aprovado, aguardando pedido",
  },
  PERDIDO: {
    label: "Perdido",
    title: "Marcar como Perdido",
    placeholder: "Ex.: Nosso preco ficou maior",
  },
  ANDAMENTO: {
    label: "Andamento",
    title: "Marcar como Andamento",
    placeholder: "Ex.: Cliente disse que ira analisar semana que vem",
  },
};

export default function OrcamentoStatusDialog(props: OrcamentoStatusDialogProps) {
  const {
    open,
    status,
    loading = false,
    initialFollowup = "",
    initialValorFechado = null,
    valorOrcado = null,
    canOpenOs = false,
    suggestedTipoDocumento = "OS",
    tenantId = null,
    empresaId = null,
    onCancel,
    onSave,
  } = props;

  const initialLostReason = useMemo(() => getInitialLostReasonState(initialFollowup), [initialFollowup]);
  const [followup, setFollowup] = useState(() => String(initialFollowup ?? ""));
  const [valorFechado, setValorFechado] = useState(() =>
    getInitialValorFechadoText({ status, initialValorFechado, valorOrcado })
  );
  const [lostReason, setLostReason] = useState(() => initialLostReason.selected);
  const [lostReasonOtherText, setLostReasonOtherText] = useState(() => initialLostReason.freeText);
  const [abrirOs, setAbrirOs] = useState(false);
  const [importarItensOs, setImportarItensOs] = useState(false);
  const [responsavelAprovacaoId, setResponsavelAprovacaoId] = useState<string | null>(null);
  const [tipoDocumento, setTipoDocumento] = useState<"OS" | "OV">(suggestedTipoDocumento);
  const [error, setError] = useState<string | null>(null);

  // Gestão state
  const [gestaoHabilitado, setGestaoHabilitado] = useState(false);
  const [gestaoItems, setGestaoItems] = useState<GestaoConfigItem[]>(() => makeDefaultGestaoItems());

  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const selectRef = useRef<HTMLSelectElement | null>(null);

  const meta = useMemo(() => (status ? META[status] : null), [status]);
  const valorOrcadoNumero = useMemo(() => {
    const parsed = Number(valorOrcado);
    return Number.isFinite(parsed) ? parsed : null;
  }, [valorOrcado]);

  // Reset ao abrir o dialog
  useEffect(() => {
    if (open) {
      // Estado do formulário é reiniciado somente quando uma nova abertura é solicitada.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setAbrirOs(canOpenOs);
      setImportarItensOs(false);
      setTipoDocumento(suggestedTipoDocumento);
      setGestaoHabilitado(true);
      setGestaoItems(makeDefaultGestaoItems());
      setResponsavelAprovacaoId(null);
    }
  }, [open, canOpenOs, suggestedTipoDocumento]);

  useEffect(() => {
    if (!open) return;
    const timer = setTimeout(() => {
      if (status === "PERDIDO") {
        if (lostReason === LOST_REASON_OTHER) textareaRef.current?.focus();
        else selectRef.current?.focus();
        return;
      }
      textareaRef.current?.focus();
    }, 0);
    return () => clearTimeout(timer);
  }, [lostReason, open, status]);

  if (!open || !status || !meta) return null;

  function updateGestaoItem(item_tipo: GestaoTipo, area: GestaoArea, patch: Partial<GestaoConfigItem>) {
    setGestaoItems((prev) =>
      prev.map((it) => (it.item_tipo === item_tipo && it.area === area ? { ...it, ...patch } : it))
    );
  }

  async function handleSubmit() {
    if (!status) return;
    let trimmed = followup.trim();

    if (status === "PERDIDO") {
      const selected = String(lostReason ?? "").trim();
      if (!selected) {
        setError("Selecione o motivo da perda.");
        selectRef.current?.focus();
        return;
      }
      if (selected === LOST_REASON_OTHER) {
        const customText = lostReasonOtherText.trim();
        if (customText.length < 5) {
          setError("Descreva o motivo em Outros (minimo de 5 caracteres).");
          textareaRef.current?.focus();
          return;
        }
        trimmed = `Outros: ${customText}`;
      } else {
        trimmed = selected;
      }
    } else {
      trimmed = followup.trim();
      if (trimmed.length < 5) {
        setError("Followup obrigatorio (minimo de 5 caracteres).");
        textareaRef.current?.focus();
        return;
      }
    }

    let valorFechadoNumero: number | null = null;
    if (status === "FECHADO") {
      valorFechadoNumero = parseMoneyBR(valorFechado);
      if (!Number.isFinite(valorFechadoNumero) || valorFechadoNumero < 0) {
        setError("Informe um valor fechado valido.");
        return;
      }
      valorFechadoNumero = Number(valorFechadoNumero.toFixed(2));
    }

    setError(null);
    await onSave({
      status,
      followup: trimmed,
      valorFechado: valorFechadoNumero,
      abrirOs: status === "FECHADO" ? abrirOs : false,
      importarItensOs: status === "FECHADO" ? abrirOs && importarItensOs : false,
      responsavelAprovacaoId:
        status === "FECHADO" && abrirOs && tipoDocumento === "OS" ? responsavelAprovacaoId : null,
      tipoDocumento: status === "FECHADO" && abrirOs ? tipoDocumento : null,
      gestao:
        status === "FECHADO" && abrirOs && tipoDocumento === "OS"
          ? { habilitarGestao: gestaoHabilitado, items: gestaoItems }
          : null,
    });
  }

  // Show gestão column only when FECHADO + Abrir OS checked
  const showGestao = status === "FECHADO" && abrirOs && canOpenOs && tipoDocumento === "OS";

  const projetos = gestaoDefs.filter((d) => d.grupo === "projetos");
  const execucoes = gestaoDefs.filter((d) => d.grupo === "execucoes");

  return (
    <div
      className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
      onClick={(e) => {
        if (loading) return;
        if (e.target === e.currentTarget) onCancel();
      }}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={meta.title}
        className={`w-full bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden flex flex-col max-h-[calc(100dvh-2rem)] transition-all ${
          showGestao ? "max-w-4xl" : "max-w-xl"
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40 shrink-0">
          <div className="font-semibold text-zinc-100">{meta.title}</div>
          <div className="text-xs text-zinc-400 mt-1">
            Descreva o ultimo andamento para {meta.label.toLowerCase()}.
          </div>
        </div>

        {/* Body — two columns when gestão is active */}
        <div className={`flex min-h-0 flex-1 overflow-hidden ${showGestao ? "divide-x divide-zinc-800" : ""}`}>

          {/* ── Coluna esquerda: campos existentes ── */}
          <div className={`overflow-y-auto ${showGestao ? "w-80 shrink-0" : "flex-1"} px-5 py-4 space-y-3`}>
            {status === "PERDIDO" ? (
              <>
                <label className="block text-xs text-zinc-400">
                  Motivo da perda
                  <select
                    ref={selectRef}
                    value={lostReason}
                    onChange={(e) => {
                      const next = e.target.value;
                      setLostReason(next);
                      if (next !== LOST_REASON_OTHER) setLostReasonOtherText("");
                      if (error) setError(null);
                    }}
                    disabled={loading}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  >
                    {LOST_REASON_OPTIONS.map((option) => (
                      <option key={option} value={option}>
                        {option}
                      </option>
                    ))}
                    <option value={LOST_REASON_OTHER}>{LOST_REASON_OTHER}</option>
                  </select>
                </label>
                {lostReason === LOST_REASON_OTHER ? (
                  <label className="block text-xs text-zinc-400">
                    Outros
                    <textarea
                      ref={textareaRef}
                      value={lostReasonOtherText}
                      onChange={(e) => {
                        setLostReasonOtherText(e.target.value);
                        if (error) setError(null);
                      }}
                      placeholder="Descreva o motivo da perda"
                      rows={4}
                      maxLength={500}
                      disabled={loading}
                      className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60 resize-y"
                    />
                  </label>
                ) : null}
              </>
            ) : (
              <label className="block text-xs text-zinc-400">
                Followup
                <textarea
                  ref={textareaRef}
                  value={followup}
                  onChange={(e) => {
                    setFollowup(e.target.value);
                    if (error) setError(null);
                  }}
                  placeholder={meta.placeholder}
                  rows={4}
                  maxLength={500}
                  disabled={loading}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60 resize-y"
                />
              </label>
            )}

            {status === "FECHADO" ? (
              <>
                <label className="block text-xs text-zinc-400">
                  Valor fechado
                  <input
                    value={valorFechado}
                    onChange={(e) => {
                      setValorFechado(e.target.value);
                      if (error) setError(null);
                    }}
                    onBlur={() => {
                      const parsed = parseMoneyBR(valorFechado);
                      if (Number.isFinite(parsed)) setValorFechado(formatMoneyBR(parsed));
                    }}
                    placeholder="Ex.: 12.500,00"
                    inputMode="decimal"
                    disabled={loading}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>
                {valorOrcadoNumero !== null ? (
                  <div className="text-xs text-zinc-500">
                    Valor orcado atual: R$ {formatMoneyBR(valorOrcadoNumero)}
                  </div>
                ) : null}
                {canOpenOs ? (
                  <div className="space-y-3 rounded-lg border border-zinc-800/80 bg-zinc-900/40 p-3">
                    <label className="flex items-center gap-2 text-sm text-zinc-200">
                      <input
                        type="checkbox"
                        checked={abrirOs}
                        onChange={(e) => {
                          const next = e.target.checked;
                          setAbrirOs(next);
                          if (!next) setImportarItensOs(false);
                        }}
                        disabled={loading}
                        className="h-4 w-4 rounded border-zinc-700 bg-zinc-950"
                      />
                      <span>Gerar documento ao fechar</span>
                    </label>

                    {abrirOs ? (
                      <>
                        <div>
                          <div className="text-sm font-medium text-zinc-100">Este fechamento gera</div>
                          <div className="mt-0.5 text-xs text-zinc-500">
                            A sugestão considera os tipos de item, mas você pode escolher o fluxo correto.
                          </div>
                        </div>

                        <div className="grid grid-cols-2 gap-2">
                          {([
                            {
                              value: "OS" as const,
                              title: "Projeto · OS",
                              description: "Horas, gestão e execução",
                            },
                            {
                              value: "OV" as const,
                              title: "Material · OV",
                              description: "Estoque, compras e faturamento",
                            },
                          ]).map((option) => {
                            const selected = tipoDocumento === option.value;
                            const suggested = suggestedTipoDocumento === option.value;
                            return (
                              <button
                                key={option.value}
                                type="button"
                                onClick={() => {
                                  setTipoDocumento(option.value);
                                  if (option.value === "OV") setResponsavelAprovacaoId(null);
                                }}
                                disabled={loading}
                                aria-pressed={selected}
                                className={`rounded-lg border p-3 text-left transition disabled:opacity-60 ${
                                  selected
                                    ? "border-sky-500 bg-sky-500/10 ring-1 ring-sky-500/40"
                                    : "border-zinc-800 bg-zinc-950 hover:border-zinc-700"
                                }`}
                              >
                                <div className="flex items-center justify-between gap-2">
                                  <span className="text-sm font-semibold text-zinc-100">{option.title}</span>
                                  {suggested ? (
                                    <span className="rounded-full bg-zinc-800 px-1.5 py-0.5 text-[10px] text-zinc-300">
                                      Sugerido
                                    </span>
                                  ) : null}
                                </div>
                                <div className="mt-1 text-xs text-zinc-500">{option.description}</div>
                              </button>
                            );
                          })}
                        </div>

                        <label className="flex items-center gap-2 text-sm text-zinc-300">
                          <input
                            type="checkbox"
                            checked={importarItensOs}
                            onChange={(e) => setImportarItensOs(e.target.checked)}
                            disabled={loading}
                            className="h-4 w-4 rounded border-zinc-700 bg-zinc-950"
                          />
                          <span>Importar os itens para o documento</span>
                        </label>

                        {tipoDocumento === "OS" ? (
                          <ResponsavelAprovacaoSelect
                            tenantId={tenantId}
                            empresaId={empresaId}
                            value={responsavelAprovacaoId}
                            onChange={(userId) => setResponsavelAprovacaoId(userId)}
                            defaultToCurrentUser
                            disabled={loading}
                            label="Responsável da OS"
                          />
                        ) : null}
                      </>
                    ) : null}
                  </div>
                ) : null}
              </>
            ) : null}

            {error && <div className="text-sm text-red-400">{error}</div>}
          </div>

          {/* ── Coluna direita: gestão (só quando FECHADO + Abrir OS) ── */}
          {showGestao && (
            <div className="flex-1 min-w-0 overflow-y-auto px-5 py-4 space-y-4">
              <div className="text-sm font-semibold text-zinc-100">Gestão de Projetos e Execução</div>

              {/* Toggle habilitar gestão */}
              <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 px-3 py-2.5 flex items-center justify-between gap-3">
                <label className="flex items-center gap-2 text-sm text-zinc-200 cursor-pointer">
                  <input
                    type="checkbox"
                    className="h-4 w-4"
                    checked={gestaoHabilitado}
                    onChange={(e) => setGestaoHabilitado(e.target.checked)}
                    disabled={loading}
                  />
                  Habilitar gestão nesta OS
                </label>
                <span className="text-xs text-zinc-500 shrink-0">Salvo ao criar a OS.</span>
              </div>

              {gestaoHabilitado && (
                <div className="space-y-4">
                  {/* Projetos */}
                  <div className="space-y-1.5">
                    <div className="text-xs font-semibold uppercase tracking-wider text-zinc-400">
                      Projetos (Engenharia)
                    </div>
                    {projetos.map((def) => {
                      const item = gestaoItems.find(
                        (it) => it.item_tipo === def.item_tipo && it.area === def.area
                      );
                      if (!item) return null;
                      return (
                        <GestaoItemRow
                          key={`${def.item_tipo}-${def.area}`}
                          def={def}
                          item={item}
                          disabled={loading}
                          onChange={(patch) => updateGestaoItem(def.item_tipo, def.area, patch)}
                        />
                      );
                    })}
                  </div>

                  {/* Execuções */}
                  <div className="space-y-1.5">
                    <div className="text-xs font-semibold uppercase tracking-wider text-zinc-400">
                      Execuções (Campo)
                    </div>
                    {execucoes.map((def) => {
                      const item = gestaoItems.find(
                        (it) => it.item_tipo === def.item_tipo && it.area === def.area
                      );
                      if (!item) return null;
                      return (
                        <GestaoItemRow
                          key={`${def.item_tipo}-${def.area}`}
                          def={def}
                          item={item}
                          disabled={loading}
                          onChange={(patch) => updateGestaoItem(def.item_tipo, def.area, patch)}
                        />
                      );
                    })}
                  </div>
                </div>
              )}

              {!gestaoHabilitado && (
                <div className="text-xs text-zinc-500">
                  Ative a gestão acima para configurar projetos e execuções. Pode ser editado depois na OS.
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-5 py-4 border-t border-zinc-900/80 flex items-center justify-end gap-2 shrink-0">
          <button
            type="button"
            onClick={onCancel}
            disabled={loading}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
          >
            Cancelar
          </button>
          <button
            type="button"
            onClick={() => void handleSubmit()}
            disabled={loading}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
          >
            {loading ? "Salvando..." : "Salvar"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Gestão item row (compact) ─────────────────────────────────────────────────
function GestaoItemRow({
  def,
  item,
  disabled,
  onChange,
}: {
  def: (typeof gestaoDefs)[number];
  item: GestaoConfigItem;
  disabled: boolean;
  onChange: (patch: Partial<GestaoConfigItem>) => void;
}) {
  return (
    <div className="grid grid-cols-[1fr_130px_64px] gap-2 items-center rounded-md border border-zinc-800 bg-zinc-900/30 px-3 py-2">
      <label className="flex items-center gap-2 text-sm text-zinc-200 cursor-pointer min-w-0">
        <input
          type="checkbox"
          className="h-4 w-4 shrink-0"
          checked={item.habilitado}
          onChange={(e) => {
            const checked = e.target.checked;
            const patch: Partial<GestaoConfigItem> = { habilitado: checked };
            if (checked && !item.data_prevista) {
              const d = new Date();
              d.setDate(d.getDate() + 30);
              patch.data_prevista = d.toISOString().slice(0, 10);
            }
            onChange(patch);
          }}
          disabled={disabled}
        />
        <span className="truncate">{def.label}</span>
      </label>

      <div className="space-y-0.5">
        <div className="text-[10px] text-zinc-500">Data prevista</div>
        <input
          type="date"
          title={`Data prevista — ${def.label}`}
          value={item.data_prevista ? item.data_prevista.slice(0, 10) : ""}
          onChange={(e) => onChange({ data_prevista: e.target.value || null })}
          disabled={disabled || !item.habilitado}
          className="w-full rounded border border-zinc-800 bg-zinc-950 px-2 py-1 text-xs text-zinc-100 disabled:opacity-40"
        />
      </div>

      <div className="space-y-0.5">
        <div className="text-[10px] text-zinc-500">%</div>
        <input
          type="number"
          min={0}
          max={100}
          title={`Progresso % — ${def.label}`}
          placeholder="0"
          value={item.progresso_percent}
          onChange={(e) =>
            onChange({ progresso_percent: Math.max(0, Math.min(100, Number(e.target.value) || 0)) })
          }
          disabled={disabled || !item.habilitado}
          className="w-full rounded border border-zinc-800 bg-zinc-950 px-2 py-1 text-xs text-zinc-100 disabled:opacity-40"
        />
      </div>
    </div>
  );
}
