"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { MotivoCompra } from "./ImportMotivosProvider";

function normalizeText(v: string) {
  return v
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

export default function MotivoCompraCombobox({
  motivos,
  value,
  disabled,
  placeholder = "Selecione...",
  loading,
  error,
  onChange,
  onToggleFavorito,
}: {
  motivos: MotivoCompra[];
  value: string;
  disabled?: boolean;
  placeholder?: string;
  loading?: boolean;
  error?: string | null;
  onChange: (nextId: string) => void;
  onToggleFavorito?: (id: string, next: boolean) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const rootRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);

  const selected = useMemo(() => motivos.find((m) => m.id === value) ?? null, [motivos, value]);

  const filtered = useMemo(() => {
    const q = normalizeText(query.trim());
    if (!q) return motivos;
    return motivos.filter((m) => {
      const hay = normalizeText(`${m.codigo} ${m.nome}`);
      return hay.includes(q);
    });
  }, [motivos, query]);

  useEffect(() => {
    if (!open) return;
    const onDocMouseDown = (e: MouseEvent) => {
      const el = rootRef.current;
      if (!el) return;
      if (e.target instanceof Node && el.contains(e.target)) return;
      setOpen(false);
    };
    document.addEventListener("mousedown", onDocMouseDown);
    return () => document.removeEventListener("mousedown", onDocMouseDown);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const t = setTimeout(() => inputRef.current?.focus(), 0);
    return () => clearTimeout(t);
  }, [open]);

  const buttonLabel = selected ? `${selected.codigo} — ${selected.nome}` : placeholder;

  return (
    <div className="relative" ref={rootRef}>
      <button
        type="button"
        disabled={disabled || loading}
        onClick={() => setOpen((v) => !v)}
        className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100 text-left disabled:opacity-60"
      >
        <div className="flex items-center justify-between gap-2">
          <span className={selected ? "" : "text-zinc-400"}>{buttonLabel}</span>
          <span className="text-zinc-400">▾</span>
        </div>
      </button>

      {open && (
        <div className="absolute z-30 mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 shadow-lg">
          <div className="p-2 border-b border-zinc-800">
            <input
              ref={inputRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Buscar por código ou nome..."
              autoComplete="off"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
            {loading && <div className="text-xs text-zinc-400 mt-1">Carregando motivos...</div>}
            {!loading && error && <div className="text-xs text-red-400 mt-1">{error}</div>}
          </div>

          <div className="max-h-72 overflow-auto">
            {filtered.length === 0 ? (
              <div className="px-3 py-2 text-sm text-zinc-400">Nenhum motivo encontrado.</div>
            ) : (
              filtered.slice(0, 120).map((m) => {
                const codigo = String(m.codigo ?? "").trim().toUpperCase();
                const isDisabled = codigo === "NAO_CLASSIFICADO";
                return (
                  <div
                    key={m.id}
                    className={
                      "px-3 py-2 flex items-start gap-2 border-b border-zinc-900 last:border-b-0 " +
                      (isDisabled ? "opacity-50" : "")
                    }
                  >
                    <button
                      type="button"
                      disabled={isDisabled}
                      onClick={() => {
                        onChange(m.id);
                        setOpen(false);
                        setQuery("");
                      }}
                      className="flex-1 text-left"
                    >
                      <div className="text-sm text-zinc-100">{m.codigo} — {m.nome}</div>
                      <div className="text-xs text-zinc-400">
                        Usos (180d): {Number(m.qtd_usos_180d ?? 0).toLocaleString("pt-BR")}
                      </div>
                    </button>

                    {typeof onToggleFavorito === "function" && (
                      <button
                        type="button"
                        disabled={isDisabled}
                        onClick={(e) => {
                          e.preventDefault();
                          e.stopPropagation();
                          onToggleFavorito(m.id, !Boolean(m.favorito));
                        }}
                        className={
                          "px-2 py-1 rounded-md border text-sm " +
                          (m.favorito
                            ? "border-amber-500/40 text-amber-300 bg-amber-500/10"
                            : "border-zinc-800 text-zinc-400 hover:bg-zinc-900")
                        }
                        title={m.favorito ? "Desfavoritar" : "Favoritar"}
                      >
                        {m.favorito ? "★" : "☆"}
                      </button>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}
