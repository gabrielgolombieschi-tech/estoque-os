"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import {
  fetchOsSelectionByExactInput,
  searchOsSelections,
  type OsSelection,
} from "@/lib/os-vinculo";

function statusLabel(status: string | null): string {
  const normalized = String(status ?? "").trim().toLowerCase();
  if (normalized === "aberta") return "Aberta";
  if (normalized === "em_andamento") return "Em andamento";
  if (normalized === "concluida") return "Concluida";
  if (normalized === "cancelada") return "Cancelada";
  return normalized ? normalized : "-";
}

function statusBadgeClass(status: string | null): string {
  const normalized = String(status ?? "").trim().toLowerCase();
  if (normalized === "em_andamento") return "border-emerald-500/30 bg-emerald-500/10 text-emerald-200";
  if (normalized === "concluida") return "border-blue-500/30 bg-blue-500/10 text-blue-200";
  if (normalized === "cancelada") return "border-rose-500/30 bg-rose-500/10 text-rose-200";
  return "border-zinc-700 bg-zinc-900 text-zinc-200";
}

export default function OsVinculoField({
  tenantId,
  empresaId,
  value,
  onChange,
  disabled = false,
  label = "OS/OV vinculada",
  helperText,
}: {
  tenantId: string;
  empresaId: string;
  value: OsSelection | null;
  onChange: (next: OsSelection | null) => void;
  disabled?: boolean;
  label?: string;
  helperText?: string;
}) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [inputValue, setInputValue] = useState<string>(value?.codigo ?? "");
  const [resolving, setResolving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lookupOpen, setLookupOpen] = useState(false);
  const [lookupTerm, setLookupTerm] = useState("");
  const [lookupLoading, setLookupLoading] = useState(false);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [lookupRows, setLookupRows] = useState<OsSelection[]>([]);

  useEffect(() => {
    setInputValue(value?.codigo ?? "");
  }, [value?.codigo, value?.id]);

  useEffect(() => {
    if (!lookupOpen) return;

    let cancelled = false;
    const timer = setTimeout(() => {
      void (async () => {
        setLookupLoading(true);
        setLookupError(null);
        try {
          const rows = await searchOsSelections({
            supabase,
            tenantId,
            empresaId,
            term: lookupTerm,
          });
          if (cancelled) return;
          setLookupRows(rows);
        } catch (e: unknown) {
          if (cancelled) return;
          setLookupRows([]);
          setLookupError(e instanceof Error ? e.message : "Erro ao buscar OS.");
        } finally {
          if (!cancelled) setLookupLoading(false);
        }
      })();
    }, 250);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [empresaId, lookupOpen, lookupTerm, supabase, tenantId]);

  const resolveTypedValue = async () => {
    if (disabled) return;

    const raw = inputValue.trim();
    if (!raw) {
      onChange(null);
      setError(null);
      return;
    }

    setResolving(true);
    setError(null);
    try {
      const resolved = await fetchOsSelectionByExactInput({
        supabase,
        tenantId,
        empresaId,
        input: raw,
      });

      if (!resolved) {
        setError(`OS/OV não encontrada: ${raw}`);
        return;
      }

      onChange(resolved);
      setInputValue(resolved.codigo);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao validar OS.");
    } finally {
      setResolving(false);
    }
  };

  return (
    <>
      <div className="space-y-2">
        <div className="flex items-center justify-between gap-3">
          <label className="block text-xs font-medium text-zinc-400">{label}</label>
          {value ? (
            <button
              type="button"
              onClick={() => {
                if (disabled) return;
                onChange(null);
                setInputValue("");
                setError(null);
              }}
              className="text-xs text-zinc-400 hover:text-zinc-100 disabled:opacity-50"
              disabled={disabled}
            >
              Limpar
            </button>
          ) : null}
        </div>

        <div className="grid gap-2 md:grid-cols-[minmax(0,1fr)_auto_auto]">
          <input
            value={inputValue}
            onChange={(event) => {
              const nextValue = event.target.value;
              setInputValue(nextValue);
              setError(null);
              if (value && nextValue.trim() !== value.codigo) onChange(null);
            }}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                void resolveTypedValue();
              }
            }}
            placeholder="Digite o código da OS/OV ou ID interno"
            disabled={disabled || resolving}
            className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
          />
          <button
            type="button"
            onClick={() => void resolveTypedValue()}
            disabled={disabled || resolving}
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900 disabled:opacity-50"
          >
            {resolving ? "Validando..." : "Vincular"}
          </button>
          <button
            type="button"
            onClick={() => {
              if (disabled) return;
              setLookupOpen(true);
              setLookupTerm(value?.codigo ?? inputValue.trim());
              setLookupError(null);
            }}
            disabled={disabled}
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900 disabled:opacity-50"
          >
            Pesquisar
          </button>
        </div>

        {helperText ? <div className="text-xs text-zinc-500">{helperText}</div> : null}

        {value ? (
          <div className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2">
            <div className="flex flex-wrap items-center gap-2">
              <div className={`text-sm font-medium ${value.tipoDocumento === "OV" ? "text-violet-300" : "text-zinc-100"}`}>{value.codigo}</div>
              <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] ${statusBadgeClass(value.status)}`}>
                {statusLabel(value.status)}
              </span>
            </div>
            <div className="mt-1 text-sm text-zinc-300">{value.clienteNome || "(Sem cliente)"}</div>
            {value.descricao ? <div className="mt-1 text-xs text-zinc-500">{value.descricao}</div> : null}
          </div>
        ) : (
          <div className="rounded-md border border-dashed border-zinc-800 px-3 py-2 text-sm text-zinc-500">
            Nenhuma OS/OV vinculada.
          </div>
        )}

        {error ? <div className="text-sm text-rose-300">{error}</div> : null}
      </div>

      {lookupOpen ? (
        <div
          className="fixed inset-0 z-50 overflow-y-auto bg-black/70 backdrop-blur-sm"
          onClick={(event) => {
            if (event.target === event.currentTarget) setLookupOpen(false);
          }}
        >
          <div className="flex min-h-full w-full items-start justify-center p-4 py-6 sm:items-center">
            <div className="flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl">
              <div className="flex items-start justify-between gap-4 border-b border-zinc-800 px-5 py-4">
                <div>
                  <div className="text-lg font-semibold text-zinc-100">Pesquisar OS/OV</div>
                  <div className="text-sm text-zinc-400">
                    Busque por código, número, cliente ou descrição. Sem filtro, mostra os documentos em andamento.
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setLookupOpen(false)}
                  className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>

              <div className="flex-1 overflow-auto px-5 py-4">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Buscar</div>
                  <input
                    value={lookupTerm}
                    onChange={(event) => setLookupTerm(event.target.value)}
                    placeholder="Ex.: 43, WEG ou descricao da OS"
                    autoFocus
                    className="w-full rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100"
                  />
                </div>

                <div className="mt-4 rounded-lg border border-zinc-800 overflow-hidden">
                  <table className="w-full text-sm">
                    <thead className="bg-zinc-900/70 text-zinc-200">
                      <tr>
                        <th className="px-3 py-2 text-left font-medium">Documento</th>
                        <th className="px-3 py-2 text-left font-medium">Cliente</th>
                        <th className="px-3 py-2 text-left font-medium">Descricao</th>
                        <th className="px-3 py-2 text-left font-medium">Status</th>
                        <th className="px-3 py-2 text-center font-medium">Acao</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {lookupRows.map((row) => (
                        <tr key={row.id} className="hover:bg-zinc-900/40">
                          <td className={`px-3 py-2 ${row.tipoDocumento === "OV" ? "text-violet-300" : "text-zinc-100"}`}>{row.codigo}</td>
                          <td className="px-3 py-2 text-zinc-200">{row.clienteNome || "-"}</td>
                          <td className="px-3 py-2 text-zinc-400">{row.descricao || "-"}</td>
                          <td className="px-3 py-2">
                            <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] ${statusBadgeClass(row.status)}`}>
                              {statusLabel(row.status)}
                            </span>
                          </td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => {
                                onChange(row);
                                setInputValue(row.codigo);
                                setError(null);
                                setLookupOpen(false);
                              }}
                              className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-sm text-zinc-100 hover:bg-zinc-800"
                            >
                              Selecionar
                            </button>
                          </td>
                        </tr>
                      ))}

                      {!lookupLoading && !lookupError && lookupRows.length === 0 ? (
                        <tr>
                          <td colSpan={5} className="px-3 py-4 text-zinc-400">
                            {lookupTerm.trim() ? "Nenhuma OS/OV encontrada." : "Nenhum documento em andamento encontrado."}
                          </td>
                        </tr>
                      ) : null}
                    </tbody>
                  </table>
                </div>

                {lookupLoading ? <div className="mt-3 text-sm text-zinc-400">Buscando...</div> : null}
                {lookupError ? <div className="mt-3 text-sm text-rose-300">{lookupError}</div> : null}
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
