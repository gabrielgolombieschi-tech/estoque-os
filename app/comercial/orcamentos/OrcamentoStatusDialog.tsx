"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { OrcamentoStatusCanonical } from "@/lib/comercial/status";

export type OrcamentoStatusDialogProps = {
  open: boolean;
  status: OrcamentoStatusCanonical | null;
  loading?: boolean;
  onCancel: () => void;
  onSave: (payload: { status: OrcamentoStatusCanonical; followup: string }) => Promise<void>;
};

type DialogMeta = {
  label: string;
  title: string;
  placeholder: string;
};

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
  const { open, status, loading = false, onCancel, onSave } = props;
  const [followup, setFollowup] = useState("");
  const [error, setError] = useState<string | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);

  const meta = useMemo(() => (status ? META[status] : null), [status]);

  useEffect(() => {
    if (!open) return;
    const timer = setTimeout(() => textareaRef.current?.focus(), 0);
    return () => clearTimeout(timer);
  }, [open, status]);

  if (!open || !status || !meta) return null;

  async function handleSubmit() {
    if (!status) return;
    const trimmed = followup.trim();
    if (trimmed.length < 5) {
      setError("Followup obrigatorio (minimo de 5 caracteres).");
      textareaRef.current?.focus();
      return;
    }
    setError(null);
    await onSave({ status, followup: trimmed });
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
