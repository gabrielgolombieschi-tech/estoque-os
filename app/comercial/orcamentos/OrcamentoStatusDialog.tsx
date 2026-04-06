"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { formatMoneyBR, parseMoneyBR } from "@/lib/decimal";
import type { OrcamentoStatusCanonical } from "@/lib/comercial/status";

export type OrcamentoStatusDialogPayload = {
  status: OrcamentoStatusCanonical;
  followup: string;
  valorFechado: number | null;
  abrirOs: boolean;
  importarItensOs: boolean;
};

export type OrcamentoStatusDialogProps = {
  open: boolean;
  status: OrcamentoStatusCanonical | null;
  loading?: boolean;
  initialFollowup?: string | null;
  initialValorFechado?: number | string | null;
  valorOrcado?: number | string | null;
  canOpenOs?: boolean;
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
  const base = Number.isFinite(Number(params.initialValorFechado))
    ? Number(params.initialValorFechado)
    : Number(params.valorOrcado ?? 0);
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
  const [error, setError] = useState<string | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const selectRef = useRef<HTMLSelectElement | null>(null);

  const meta = useMemo(() => (status ? META[status] : null), [status]);
  const valorOrcadoNumero = useMemo(() => {
    const parsed = Number(valorOrcado);
    return Number.isFinite(parsed) ? parsed : null;
  }, [valorOrcado]);

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
    });
  }

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
        className="w-full max-w-xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
          <div className="font-semibold text-zinc-100">{meta.title}</div>
          <div className="text-xs text-zinc-400 mt-1">Descreva o ultimo andamento para {meta.label.toLowerCase()}.</div>
        </div>
        <div className="px-5 py-4 space-y-3">
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
                <div className="text-xs text-zinc-500">Valor orcado atual: R$ {formatMoneyBR(valorOrcadoNumero)}</div>
              ) : null}
              {canOpenOs ? (
                <div className="space-y-2 rounded-lg border border-zinc-800/80 bg-zinc-900/40 p-3">
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
                    <span>Abrir OS</span>
                  </label>
                  {abrirOs ? (
                    <label className="flex items-center gap-2 pl-6 text-sm text-zinc-300">
                      <input
                        type="checkbox"
                        checked={importarItensOs}
                        onChange={(e) => setImportarItensOs(e.target.checked)}
                        disabled={loading}
                        className="h-4 w-4 rounded border-zinc-700 bg-zinc-950"
                      />
                      <span>Importar os itens do orcamento para OS</span>
                    </label>
                  ) : null}
                </div>
              ) : null}
            </>
          ) : null}
          {error && <div className="text-sm text-red-400">{error}</div>}
        </div>
        <div className="px-5 py-4 border-t border-zinc-900/80 flex items-center justify-end gap-2">
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
