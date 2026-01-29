"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { parseNfseXml, type ParsedNfse } from "@/lib/nfse/parseNfseXml";

function digitsOnly(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

type ImportResultRow = {
  status: string | null;
  message: string | null;
  documento_fiscal_id: string | null;
};

export default function ImportNfseXmlModal({
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

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO";

  const canImport = useMemo(() => {
    // UI gate: keep aligned with the NFSe page access (Financeiro).
    // The DB RPC will still enforce server-side permissions.
    if (isFinanceiroEmpresaRole) return true;
    const fRead = te.has("financeiro.read");
    const fWrite = te.has("financeiro.write");
    if (fRead === undefined || fWrite === undefined) return undefined;
    return Boolean(fRead || fWrite);
  }, [isFinanceiroEmpresaRole, te]);

  const [file, setFile] = useState<File | null>(null);
  const [parsed, setParsed] = useState<ParsedNfse | null>(null);
  const [chaveAcesso, setChaveAcesso] = useState<string>("");
  const [alreadyImportedId, setAlreadyImportedId] = useState<string>("");

  const [busy, setBusy] = useState(false);
  const [checkingDuplicate, setCheckingDuplicate] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setError(null);
    setOk(null);
    setBusy(false);
    setCheckingDuplicate(false);
    setAlreadyImportedId("");
  }, [open]);

  const buildChave = (p: ParsedNfse) => {
    const prestador = digitsOnly(p.prestador_cnpj);
    return `NFSE:${prestador}:${p.serie}:${p.numero}`;
  };

  const checkDuplicate = async (key: string) => {
    if (!ready) return;
    if (!tenantId) return;

    setCheckingDuplicate(true);
    try {
      const supabase = supabaseBrowser();
      const q = applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal")
          .select("id")
          .eq("chave_acesso", key)
          .eq("operacao", "SAIDA")
          .eq("natureza", "SERVICO")
          .is("deleted_at", null)
          .limit(1),
        tenantId,
        empresaId
      );

      const { data, error: qErr } = await q.maybeSingle<{ id: string }>();
      if (qErr) throw qErr;

      if (data?.id) {
        setAlreadyImportedId(String(data.id));
        setOk("Este XML já foi importado. Reimportação bloqueada.");
      }
    } catch {
      // Ignore duplicate check failures; RPC will still reject on unique key.
      setAlreadyImportedId("");
    } finally {
      setCheckingDuplicate(false);
    }
  };

  const onPickFile = async (f: File | null) => {
    setFile(f);
    setParsed(null);
    setChaveAcesso("");
    setAlreadyImportedId("");
    setError(null);
    setOk(null);

    if (!f) return;
    if (!f.name.toLowerCase().endsWith(".xml")) {
      setError("Selecione um arquivo .xml");
      setFile(null);
      return;
    }

    try {
      const raw = await f.text();
      const p = parseNfseXml(raw);
      setParsed(p);

      const chave = buildChave(p);
      setChaveAcesso(chave);
      await checkDuplicate(chave);
    } catch (e: unknown) {
      setError(getErrorMessage(e, "Falha ao ler XML."));
    }
  };

  const importXml = async () => {
    if (!ready) return;
    if (canImport === false) return setError("Sem permissão para importar NFS-e.");
    if (!file) return setError("Selecione um arquivo XML.");
    if (!parsed) return setError("Não foi possível interpretar o XML.");
    if (!tenantId || !empresaId) return setError("Contexto de tenant/empresa incompleto.");
    if (alreadyImportedId) return setError("Este XML já foi importado. Reimportação bloqueada.");

    setBusy(true);
    setError(null);
    setOk(null);

    try {
      const raw = await file.text();
      const supabase = supabaseBrowser();

      const { data, error: rpcErr } = await supabase.rpc("import_nfse_saida", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_nfse_json: parsed,
        p_xml_raw: raw,
      });

      if (rpcErr) throw rpcErr;

      const rows = (Array.isArray(data) ? data : data ? [data] : []) as unknown as ImportResultRow[];
      const first = rows[0] ?? null;

      const status = String(first?.status ?? "");
      const message = String(first?.message ?? "");
      const docId = first?.documento_fiscal_id ? String(first.documento_fiscal_id) : "";

      if (!docId) {
        throw new Error(message || "Importado, mas não foi possível identificar o documento fiscal.");
      }

      setOk(message || (status ? `Importado (${status}).` : "Importado."));
      onImported?.(docId);
      onClose();
      router.push(`/faturamento/nfse/${docId}`);
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
            <div className="text-sm font-medium text-zinc-100">Importar NFS-e (XML)</div>
            <div className="text-xs text-zinc-500">Faturamento / Serviços</div>
          </div>
          <button type="button" onClick={onClose} className="text-sm text-zinc-300 hover:text-zinc-100">
            Fechar
          </button>
        </div>

        <div className="space-y-4 p-4">
          {canImport === false ? (
            <div className="rounded-md border border-rose-900/60 bg-rose-950/20 px-3 py-2 text-sm text-rose-200">
              Sem permissão para importar NFS-e.
            </div>
          ) : null}

          <div>
            <label htmlFor="nfse-xml-file" className="block text-xs font-medium text-zinc-400">
              Arquivo XML
            </label>
            <input
              id="nfse-xml-file"
              type="file"
              accept=".xml"
              onChange={(e) => void onPickFile(e.target.files?.[0] ?? null)}
              className="mt-1 block w-full text-sm text-zinc-200 file:mr-4 file:rounded-md file:border-0 file:bg-zinc-800 file:px-3 file:py-2 file:text-sm file:font-medium file:text-zinc-100 hover:file:bg-zinc-700"
              disabled={busy || checkingDuplicate || !ready}
            />
            {file ? <div className="mt-1 text-xs text-zinc-500">Selecionado: {file.name}</div> : null}
            {checkingDuplicate ? <div className="mt-1 text-xs text-zinc-400">Verificando duplicidade...</div> : null}
          </div>

          <div>
            <div className="text-xs font-medium text-zinc-400">Prévia</div>
            <div className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100">
              {!parsed ? (
                <div className="text-sm text-zinc-400">Selecione um XML para visualizar.</div>
              ) : (
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <div className="text-xs text-zinc-400">Número</div>
                    <div className="tabular-nums">{parsed.numero}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Série</div>
                    <div className="tabular-nums">{parsed.serie}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Prestador (CNPJ)</div>
                    <div className="tabular-nums">{parsed.prestador_cnpj || "—"}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Tomador (doc)</div>
                    <div className="tabular-nums">{parsed.tomador_documento || "—"}</div>
                  </div>
                  <div className="col-span-2">
                    <div className="text-xs text-zinc-400">Chave</div>
                    <div className="break-all">{chaveAcesso || "—"}</div>
                    {alreadyImportedId ? <div className="mt-1 text-xs text-rose-200">Já importada: {alreadyImportedId}</div> : null}
                  </div>
                </div>
              )}
            </div>
          </div>

          {error ? (
            <div className="rounded-md border border-rose-900/60 bg-rose-950/20 px-3 py-2 text-sm text-rose-200">
              {error}
            </div>
          ) : null}
          {ok ? (
            <div className="rounded-md border border-emerald-900/60 bg-emerald-950/20 px-3 py-2 text-sm text-emerald-200">
              {ok}
            </div>
          ) : null}

          <div className="flex items-center justify-end gap-2 pt-2">
            {alreadyImportedId ? (
              <button
                type="button"
                onClick={() => router.push(`/faturamento/nfse/${alreadyImportedId}`)}
                className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900"
                disabled={busy}
              >
                Abrir
              </button>
            ) : null}
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
              disabled={busy || !ready || canImport === false || checkingDuplicate || !file || !parsed || Boolean(alreadyImportedId)}
            >
              {busy ? "Importando..." : "Importar"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
