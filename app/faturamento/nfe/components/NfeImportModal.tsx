"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type ClienteOption = { id: number; nome: string };

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

export default function NfeImportModal({
  open,
  onClose,
  onImported,
}: {
  open: boolean;
  onClose: () => void;
  onImported?: (documentoFiscalId: string) => void;
}) {
  const te = useTenantEmpresa();
  const router = useRouter();

  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1);

  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const canImportXml = useMemo(() => {
    const v = te.has("xml_import.execute");
    if (v === undefined) return undefined;
    return Boolean(v);
  }, [te]);

  const [file, setFile] = useState<File | null>(null);
  const [clienteId, setClienteId] = useState<string>("");
  const [clienteSearch, setClienteSearch] = useState<string>("");
  const [clientes, setClientes] = useState<ClienteOption[]>([]);
  const [loadingClientes, setLoadingClientes] = useState(false);

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setError(null);
    setOk(null);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    if (!ready) return;

    let cancelled = false;
    const t = setTimeout(() => {
      const run = async () => {
        setLoadingClientes(true);
        try {
          const term = clienteSearch.trim();
          const supabase = supabaseBrowser();

          const base = supabase.from("clientes").select("id,nome").order("nome", { ascending: true }).limit(30);
          const q = applyTenantEmpresa(term ? base.ilike("nome", `%${term}%`) : base, tenantId, empresaId);

          const { data, error: qErr } = await q.returns<ClienteOption[]>();
          if (qErr) throw qErr;

          if (cancelled) return;
          setClientes((data ?? []).filter((r) => typeof r?.id === "number"));
        } catch (e: unknown) {
          if (cancelled) return;
          setError(getErrorMessage(e, "Erro ao carregar clientes."));
          setClientes([]);
        } finally {
          if (!cancelled) setLoadingClientes(false);
        }
      };

      void run();
    }, 250);

    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [clienteSearch, empresaId, open, ready, tenantId]);

  const onPickFile = (f: File | null) => {
    setFile(f);
    setError(null);
    setOk(null);
    if (!f) return;
    if (!f.name.toLowerCase().endsWith(".xml")) {
      setError("Selecione um arquivo .xml");
      setFile(null);
    }
  };

  const importXml = async () => {
    if (!ready) return;
    if (canImportXml === false) return setError("Sem permissão para importar XML.");
    if (!file) return setError("Selecione um arquivo XML.");
    if (!clienteId) return setError("Selecione um cliente.");

    setBusy(true);
    setError(null);
    setOk(null);

    try {
      const supabase = supabaseBrowser();
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      if (!token) throw new Error("Sessão expirada. Faça login novamente.");

      const fd = new FormData();
      fd.append("file", file);
      fd.append("cliente_id", clienteId);
      // Optional hints (server can also resolve via RPC current_*).
      if (tenantId) fd.append("tenant_id", tenantId);
      if (empresaId) fd.append("empresa_id", empresaId);

      const res = await fetch("/api/faturamento/nfe/importar-xml", {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
        body: fd,
      });

      const jsonUnknown: unknown = await res.json().catch(() => null);
      const jsonObj = jsonUnknown && typeof jsonUnknown === "object" ? (jsonUnknown as Record<string, unknown>) : null;
      if (!res.ok) {
        const msg = typeof jsonObj?.error === "string" ? String(jsonObj.error) : "Erro ao importar XML.";
        throw new Error(msg);
      }

      const docIdRaw = jsonObj?.documento_fiscal_id ?? jsonObj?.documentoFiscalId ?? null;
      const docId = docIdRaw ? String(docIdRaw) : "";
      if (!docId) throw new Error("Importado, mas não foi possível identificar o documento fiscal.");

      setOk(typeof jsonObj?.message === "string" ? String(jsonObj.message) : "Importado.");
      onImported?.(docId);
      onClose();
      router.push(`/faturamento/nfe/${docId}`);
    } catch (e: unknown) {
      setError(getErrorMessage(e, "Erro ao importar XML."));
    } finally {
      setBusy(false);
    }
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-xl rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl">
        <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
          <div>
            <div className="text-sm font-medium text-zinc-100">Importar NF-e (Faturamento)</div>
            <div className="text-xs text-zinc-500">SAÍDA / Contas a Receber</div>
          </div>
          <button type="button" onClick={onClose} className="text-sm text-zinc-300 hover:text-zinc-100">
            Fechar
          </button>
        </div>

        <div className="space-y-4 p-4">
          {canImportXml === false ? (
            <div className="rounded-md border border-rose-900/60 bg-rose-950/20 px-3 py-2 text-sm text-rose-200">
              Sem permissão para importar XML.
            </div>
          ) : null}

          <div>
            <label className="block text-xs font-medium text-zinc-400">Cliente (obrigatório)</label>
            <input
              value={clienteSearch}
              onChange={(e) => setClienteSearch(e.target.value)}
              placeholder="Buscar por nome..."
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700"
              disabled={busy || !ready}
            />
            <select
              value={clienteId}
              onChange={(e) => setClienteId(e.target.value)}
              className="mt-2 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700"
              disabled={busy || !ready}
            >
              <option value="">{loadingClientes ? "Carregando..." : "Selecione..."}</option>
              {clientes.map((c) => (
                <option key={c.id} value={String(c.id)}>
                  {c.nome}
                </option>
              ))}
            </select>
            <div className="mt-1 text-xs text-zinc-500">{loadingClientes ? "Buscando clientes..." : `${clientes.length} opção(ões)`}</div>
          </div>

          <div>
            <label className="block text-xs font-medium text-zinc-400">Arquivo XML</label>
            <input
              type="file"
              accept=".xml"
              onChange={(e) => onPickFile(e.target.files?.[0] ?? null)}
              className="mt-1 block w-full text-sm text-zinc-200 file:mr-4 file:rounded-md file:border-0 file:bg-zinc-800 file:px-3 file:py-2 file:text-sm file:font-medium file:text-zinc-100 hover:file:bg-zinc-700"
              disabled={busy || !ready}
            />
            {file ? <div className="mt-1 text-xs text-zinc-500">Selecionado: {file.name}</div> : null}
          </div>

          {error ? <div className="rounded-md border border-rose-900/60 bg-rose-950/20 px-3 py-2 text-sm text-rose-200">{error}</div> : null}
          {ok ? <div className="rounded-md border border-emerald-900/60 bg-emerald-950/20 px-3 py-2 text-sm text-emerald-200">{ok}</div> : null}

          <div className="flex items-center justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900"
              disabled={busy}
            >
              Cancelar
            </button>
            <button
              type="button"
              onClick={() => void importXml()}
              className="rounded-md bg-zinc-800 px-3 py-2 text-sm font-medium text-zinc-100 hover:bg-zinc-700 disabled:opacity-50"
              disabled={busy || !ready || canImportXml === false}
            >
              {busy ? "Importando..." : "Importar"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
