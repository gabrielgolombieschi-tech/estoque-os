"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { parseNfeXml } from "@/lib/nfe/parseNfeXml";

function normalizeDigits(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

function normalizeDocumento(value: string | null | undefined): string | null {
  const digits = normalizeDigits(value);
  if (digits.length === 14) return digits;
  return null;
}

function normalizeChaveNfe(value: string | null | undefined): string | null {
  const digits = normalizeDigits(value);
  return digits.length === 44 ? digits : null;
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
    const empresaRole = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    const isFinanceiroEmpresaRole = typeof empresaRole === "string" && empresaRole.trim().toUpperCase() === "FINANCEIRO";
    if (isFinanceiroEmpresaRole) return true;

    const explicit = te.has("xml_import_faturamento.execute");
    if (explicit === true) return true;

    const fRead = te.has("financeiro.read");
    const fWrite = te.has("financeiro.write");
    if (explicit === undefined || fRead === undefined || fWrite === undefined) return undefined;
    return Boolean(explicit || fRead || fWrite);
  }, [te]);

  const [file, setFile] = useState<File | null>(null);
  const [clienteId, setClienteId] = useState<string>("");
  const [clienteLabel, setClienteLabel] = useState<string>("");
  const [clienteCnpj, setClienteCnpj] = useState<string>("");
  const [chaveAcesso, setChaveAcesso] = useState<string>("");
  const [alreadyImportedId, setAlreadyImportedId] = useState<string>("");

  const [busy, setBusy] = useState(false);
  const [detectingCliente, setDetectingCliente] = useState(false);
  const [checkingDuplicate, setCheckingDuplicate] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setError(null);
    setOk(null);
    setAlreadyImportedId("");
  }, [open]);

  const onPickFile = async (f: File | null) => {
    setFile(f);
    setError(null);
    setOk(null);
    setClienteId("");
    setClienteLabel("");
    setClienteCnpj("");
    setChaveAcesso("");
    setAlreadyImportedId("");
    if (!f) return;
    if (!f.name.toLowerCase().endsWith(".xml")) {
      setError("Selecione um arquivo .xml");
      setFile(null);
      return;
    }
    if (!ready) return;

    setDetectingCliente(true);
    try {
      const raw = await f.text();
      const parsed = parseNfeXml(raw);
      const chave = normalizeChaveNfe(parsed.nfe.chave);
      if (chave) setChaveAcesso(chave);
      const documento = normalizeDocumento(parsed.nfe.documentoDestinatario);
      const nome = (parsed.nfe.destinatario ?? "").trim();

      let importedExistingId = "";

      if (documento) setClienteCnpj(documento);
      if (nome) setClienteLabel(nome);

      if (!chave) {
        setError("Chave da NF-e não encontrada/ inválida (esperado 44 dígitos).");
        return;
      }

      // Duplicate check (block re-import on UI before submitting).
      setCheckingDuplicate(true);
      try {
        const supabase = supabaseBrowser();
        const { data: sess } = await supabase.auth.getSession();
        const token = sess.session?.access_token ?? null;
        if (!token) throw new Error("Sessão expirada. Faça login novamente.");

        const chk = await fetch("/api/faturamento/nfe/check-imported", {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({ tenantId, empresaId, chave }),
        });

        const chkJsonUnknown: unknown = await chk.json().catch(() => null);
        const chkJson = chkJsonUnknown && typeof chkJsonUnknown === "object" ? (chkJsonUnknown as Record<string, unknown>) : null;
        if (!chk.ok) {
          const msg = typeof chkJson?.error === "string" ? String(chkJson.error) : "Erro ao verificar duplicidade do XML.";
          throw new Error(msg);
        }

        const imported = Boolean(chkJson?.imported);
        const existingIdRaw = chkJson?.documento_fiscal_id ?? null;
        const existingId = existingIdRaw ? String(existingIdRaw) : "";
        if (imported && existingId) {
          importedExistingId = existingId;
          setAlreadyImportedId(existingId);
          setOk("Este XML já foi importado. Reimportação bloqueada.");
        }
      } finally {
        setCheckingDuplicate(false);
      }

      if (!documento) {
        setError("CNPJ do cliente não encontrado no XML (tag <dest><CNPJ>). Não é possível conferir/cadastrar o cliente.");
        return;
      }

      const supabase = supabaseBrowser();
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      if (!token) throw new Error("Sessão expirada. Faça login novamente.");

      const res = await fetch("/api/faturamento/nfe/upsert-cliente-from-xml", {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          tenantId,
          empresaId,
          documento,
          nome: nome || null,
          razao_social: nome || null,
          inscricao_estadual: parsed.nfe.inscricaoEstadualDestinatario,
          email: parsed.nfe.emailDestinatario,
          cep: parsed.nfe.endDestCep,
          logradouro: parsed.nfe.endDestLogradouro,
          numero_endereco: parsed.nfe.endDestNumero,
          complemento: parsed.nfe.endDestComplemento,
          bairro: parsed.nfe.endDestBairro,
          cidade: parsed.nfe.endDestCidade,
          uf: parsed.nfe.endDestUf,
          pais: parsed.nfe.endDestPais,
        }),
      });

      const jsonUnknown: unknown = await res.json().catch(() => null);
      const jsonObj = jsonUnknown && typeof jsonUnknown === "object" ? (jsonUnknown as Record<string, unknown>) : null;
      if (!res.ok) {
        const msg = typeof jsonObj?.error === "string" ? String(jsonObj.error) : "Erro ao cadastrar/atualizar cliente pelo XML.";
        throw new Error(msg);
      }

      const clienteIdRaw = jsonObj?.cliente_id ?? null;
      const clienteIdStr = clienteIdRaw ? String(clienteIdRaw) : "";
      if (!clienteIdStr) return;

      setClienteId(clienteIdStr);

      const clienteObj = jsonObj?.cliente && typeof jsonObj.cliente === "object" ? (jsonObj.cliente as Record<string, unknown>) : null;
      const clienteNomeFromApi = clienteObj && typeof clienteObj.nome === "string" ? String(clienteObj.nome) : "";
      const finalLabel = (clienteNomeFromApi || nome || `Cliente ${documento}`).trim();
      if (finalLabel) setClienteLabel(finalLabel);

      if (!importedExistingId) setOk(`Cliente conferido por CNPJ: ${documento}`);
    } catch (e: unknown) {
      // Não bloqueia o usuário de seguir manualmente.
      setError(getErrorMessage(e, "Falha ao ler XML e conferir cliente."));
    } finally {
      setDetectingCliente(false);
    }
  };

  const importXml = async () => {
    if (!ready) return;
    if (canImportXml === false) return setError("Sem permissão para importar XML.");
    if (!file) return setError("Selecione um arquivo XML.");
    if (alreadyImportedId) return setError("Este XML já foi importado. Reimportação bloqueada.");
    if (!clienteId) return setError("Cliente não resolvido a partir do XML.");

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
            <div className="text-xs font-medium text-zinc-400">Cliente detectado</div>
            <div className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100">
              {clienteLabel ? (
                <div className="flex flex-col gap-1">
                  <div className="font-medium">{clienteLabel}</div>
                  <div className="text-xs text-zinc-400">CNPJ: {clienteCnpj || "—"}</div>
                </div>
              ) : (
                <div className="text-sm text-zinc-400">Selecione um XML para detectar o cliente.</div>
              )}
            </div>
          </div>

          <div>
            <div className="text-xs font-medium text-zinc-400">NF-e</div>
            <div className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100">
              <div className="text-xs text-zinc-400">Chave</div>
              <div className="break-all">{chaveAcesso || "—"}</div>
              {alreadyImportedId ? (
                <div className="mt-2 text-xs text-rose-200">Já importada: {alreadyImportedId}</div>
              ) : null}
            </div>
          </div>

          <div>
            <label htmlFor="nfe-xml-file" className="block text-xs font-medium text-zinc-400">
              Arquivo XML
            </label>
            <input
              id="nfe-xml-file"
              type="file"
              accept=".xml"
              onChange={(e) => void onPickFile(e.target.files?.[0] ?? null)}
              className="mt-1 block w-full text-sm text-zinc-200 file:mr-4 file:rounded-md file:border-0 file:bg-zinc-800 file:px-3 file:py-2 file:text-sm file:font-medium file:text-zinc-100 hover:file:bg-zinc-700"
              disabled={busy || detectingCliente || checkingDuplicate || !ready}
            />
            {file ? <div className="mt-1 text-xs text-zinc-500">Selecionado: {file.name}</div> : null}
            {detectingCliente ? <div className="mt-1 text-xs text-zinc-400">Lendo XML e conferindo cliente...</div> : null}
            {checkingDuplicate ? <div className="mt-1 text-xs text-zinc-400">Verificando se já foi importado...</div> : null}
          </div>

          {error ? <div className="rounded-md border border-rose-900/60 bg-rose-950/20 px-3 py-2 text-sm text-rose-200">{error}</div> : null}
          {ok ? <div className="rounded-md border border-emerald-900/60 bg-emerald-950/20 px-3 py-2 text-sm text-emerald-200">{ok}</div> : null}

          <div className="flex items-center justify-end gap-2 pt-2">
            {alreadyImportedId ? (
              <button
                type="button"
                onClick={() => router.push(`/faturamento/nfe/${alreadyImportedId}`)}
                className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900"
                disabled={busy}
              >
                Abrir NF-e
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
              disabled={busy || !ready || canImportXml === false || detectingCliente || checkingDuplicate || !file || !clienteId || Boolean(alreadyImportedId)}
            >
              {busy ? "Importando..." : "Importar"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
