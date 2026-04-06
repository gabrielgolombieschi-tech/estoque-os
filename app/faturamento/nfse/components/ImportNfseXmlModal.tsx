"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { digitsOnly, isNfseSerieCompatible, normalizeNfseNumeroIdentity } from "@/lib/nfse/identity";
import { parseNfseXml, type ParsedNfse } from "@/lib/nfse/parseNfseXml";
import OsVinculoField from "@/app/faturamento/components/OsVinculoField";
import type { OsSelection } from "@/lib/os-vinculo";

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

function n(value: unknown): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const v = Number(String(value ?? "").replace(",", "."));
  return Number.isFinite(v) ? v : 0;
}

function splitTotal(total: number, parts: number): number[] {
  const safeParts = Math.max(1, Math.trunc(parts));
  const safeTotal = Math.max(0, Math.round(total * 100) / 100);
  const base = Math.floor((safeTotal / safeParts) * 100) / 100;
  const values = Array.from({ length: safeParts }, () => base);
  const sumBase = Math.round(base * safeParts * 100) / 100;
  values[safeParts - 1] = Math.round((safeTotal - (sumBase - base)) * 100) / 100;
  return values;
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

type ImportResultRow = {
  status: string | null;
  message: string | null;
  documento_fiscal_id: string | null;
};

type ClienteDocRow = {
  id: number;
};

type DuplicateNfseRow = {
  id: string;
  emissao_date: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string | null;
};

type ParcelaForm = {
  numero: string;
  valor: string;
  vencimento: string;
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
  const [osSelection, setOsSelection] = useState<OsSelection | null>(null);

  const [busy, setBusy] = useState(false);
  const [checkingDuplicate, setCheckingDuplicate] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [qtdPagamentos, setQtdPagamentos] = useState<number>(1);
  const [parcelas, setParcelas] = useState<ParcelaForm[]>([{ numero: "001", valor: "", vencimento: todayIso() }]);

  const parsedTotal = useMemo(() => {
    if (!parsed) return 0;
    return Math.max(0, n(parsed.valores?.valor_total ?? parsed.valores?.valor_liquido ?? parsed.valores?.valor_servicos));
  }, [parsed]);

  const rebuildParcelas = (nextQtd: number, baseDate: string, total: number, previous?: ParcelaForm[]) => {
    const safeQtd = Math.max(1, Math.trunc(nextQtd));
    const split = splitTotal(total, safeQtd);
    const prev = previous ?? [];
    const next: ParcelaForm[] = [];
    for (let i = 0; i < safeQtd; i += 1) {
      const numero = String(i + 1).padStart(3, "0");
      const existing = prev[i];
      next.push({
        numero,
        valor: existing?.valor ?? split[i].toFixed(2),
        vencimento: existing?.vencimento ?? baseDate,
      });
    }
    return next;
  };

  useEffect(() => {
    if (!open) return;
    setFile(null);
    setParsed(null);
    setChaveAcesso("");
    setAlreadyImportedId("");
    setOsSelection(null);
    setError(null);
    setOk(null);
    setBusy(false);
    setCheckingDuplicate(false);
    setQtdPagamentos(1);
    setParcelas(rebuildParcelas(1, todayIso(), 0));
  }, [open]);

  const buildChave = (p: ParsedNfse) => {
    const prestador = digitsOnly(p.prestador_cnpj);
    return `NFSE:${prestador}:${p.serie}:${p.numero}`;
  };

  const findPotentialDuplicate = async (p: ParsedNfse, key: string) => {
    const year = String(p.data_emissao ?? "").slice(0, 4);
    if (!/^\d{4}$/.test(year)) return null;

    const numeroIdentidade = normalizeNfseNumeroIdentity(p.numero, p.data_emissao);
    const tomadorDocumento = digitsOnly(p.tomador_documento);
    if (!numeroIdentidade || !tomadorDocumento) return null;

    const supabase = supabaseBrowser();

    const { data: clientes, error: cliErr } = await applyTenantEmpresa(
      supabase.from("clientes").select("id").eq("documento", tomadorDocumento).limit(10),
      tenantId,
      empresaId
    ).returns<ClienteDocRow[]>();
    if (cliErr) throw cliErr;

    const clienteIds = Array.from(new Set((clientes ?? []).map((row) => row.id).filter((id) => Number.isFinite(id))));
    if (!clienteIds.length) return null;

    const { data: docs, error: docsErr } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id,emissao_date,serie,numero,chave_acesso")
        .eq("operacao", "SAIDA")
        .eq("natureza", "SERVICO")
        .eq("modelo", "NFSE")
        .in("cliente_id", clienteIds)
        .gte("emissao_date", `${year}-01-01`)
        .lte("emissao_date", `${year}-12-31`)
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(50),
      tenantId,
      empresaId
    ).returns<DuplicateNfseRow[]>();
    if (docsErr) throw docsErr;

    return (
      (docs ?? []).find((row) => {
        if (!row?.id) return false;

        const existingKey = String(row.chave_acesso ?? "").trim();
        if (existingKey && existingKey === key) return true;

        const existingNumeroIdentidade = normalizeNfseNumeroIdentity(row.numero, row.emissao_date);
        if (!existingNumeroIdentidade || existingNumeroIdentidade !== numeroIdentidade) return false;

        return isNfseSerieCompatible(row.serie, p.serie);
      }) ?? null
    );
  };

  const checkDuplicate = async (key: string, p: ParsedNfse) => {
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
        setOk("Este XML ja foi importado. Reimportacao bloqueada.");
        return;
      }

      const duplicate = await findPotentialDuplicate(p, key);
      if (duplicate?.id) {
        setAlreadyImportedId(String(duplicate.id));
        setOk("Ja existe uma NFS-e potencialmente equivalente cadastrada. Revise antes de importar novamente.");
      }
    } catch {
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
    setOsSelection(null);
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

      const total = Math.max(0, n(p.valores?.valor_total ?? p.valores?.valor_liquido ?? p.valores?.valor_servicos));
      const baseDate = p.data_emissao ?? todayIso();
      setQtdPagamentos(1);
      setParcelas(rebuildParcelas(1, baseDate, total));

      const chave = buildChave(p);
      setChaveAcesso(chave);
      await checkDuplicate(chave, p);
    } catch (e: unknown) {
      setError(getErrorMessage(e, "Falha ao ler XML."));
    }
  };

  const onChangeQtdPagamentos = (raw: string) => {
    const nextQtd = Math.max(1, Math.min(24, Math.trunc(n(raw) || 1)));
    const baseDate = parsed?.data_emissao ?? todayIso();
    setQtdPagamentos(nextQtd);
    setParcelas((prev) => rebuildParcelas(nextQtd, baseDate, parsedTotal, prev));
  };

  const onChangeParcela = (index: number, field: "valor" | "vencimento", value: string) => {
    setParcelas((prev) =>
      prev.map((p, i) =>
        i === index
          ? {
              ...p,
              [field]: value,
            }
          : p
      )
    );
  };

  const importXml = async () => {
    if (!ready) return;
    if (canImport === false) return setError("Sem permissao para importar NFS-e.");
    if (!file) return setError("Selecione um arquivo XML.");
    if (!parsed) return setError("Nao foi possivel interpretar o XML.");
    if (!tenantId || !empresaId) return setError("Contexto de tenant/empresa incompleto.");
    if (alreadyImportedId) return setError(ok ?? "Ja existe uma NFS-e equivalente cadastrada. Importacao bloqueada.");
    if (qtdPagamentos < 1) return setError("Informe ao menos 1 pagamento.");

    const pagamentos = parcelas.slice(0, qtdPagamentos).map((p, idx) => {
      const numero = String(p.numero ?? "").trim() || String(idx + 1).padStart(3, "0");
      const vencimento = String(p.vencimento ?? "").trim();
      const valorNum = Math.round(n(p.valor) * 100) / 100;
      return { numero, vencimento, valor: valorNum };
    });

    if (pagamentos.length !== qtdPagamentos) {
      return setError("Nao foi possivel montar as parcelas de pagamento.");
    }

    for (let i = 0; i < pagamentos.length; i += 1) {
      const p = pagamentos[i];
      if (!p.vencimento) return setError(`Parcela ${i + 1}: informe a data.`);
      if (p.valor <= 0) return setError(`Parcela ${i + 1}: valor deve ser maior que zero.`);
    }

    const somaParcelas = Math.round(pagamentos.reduce((acc, p) => acc + p.valor, 0) * 100) / 100;
    if (parsedTotal > 0 && Math.abs(somaParcelas - parsedTotal) > 0.05) {
      return setError(`Soma das parcelas (R$ ${somaParcelas.toFixed(2)}) difere do total da NFS-e (R$ ${parsedTotal.toFixed(2)}).`);
    }

    setBusy(true);
    setError(null);
    setOk(null);

    try {
      const raw = await file.text();
      const supabase = supabaseBrowser();
      const nfsePayload = { ...parsed, pagamentos };

      const { data, error: rpcErr } = await supabase.rpc("import_nfse_saida_com_os", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_nfse_json: nfsePayload,
        p_xml_raw: raw,
        p_os_id: osSelection?.id ?? null,
      });

      if (rpcErr) throw rpcErr;

      const rows = (Array.isArray(data) ? data : data ? [data] : []) as unknown as ImportResultRow[];
      const first = rows[0] ?? null;

      const status = String(first?.status ?? "");
      const message = String(first?.message ?? "");
      const docId = first?.documento_fiscal_id ? String(first.documento_fiscal_id) : "";

      if (!docId) {
        throw new Error(message || "Importado, mas nao foi possivel identificar o documento fiscal.");
      }

      const { error: parcelaErr } = await supabase.rpc("nfse_sync_titulo_ar_parcelas", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_documento_fiscal_id: docId,
        p_parcelas_json: pagamentos,
      });
      if (parcelaErr) throw parcelaErr;

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
            <div className="text-xs text-zinc-500">Faturamento / Servicos</div>
          </div>
          <button type="button" onClick={onClose} className="text-sm text-zinc-300 hover:text-zinc-100">
            Fechar
          </button>
        </div>

        <div className="space-y-4 p-4">
          {canImport === false ? (
            <div className="rounded-md border border-rose-900/60 bg-rose-950/20 px-3 py-2 text-sm text-rose-200">
              Sem permissao para importar NFS-e.
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
            <div className="text-xs font-medium text-zinc-400">Previa</div>
            <div className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100">
              {!parsed ? (
                <div className="text-sm text-zinc-400">Selecione um XML para visualizar.</div>
              ) : (
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <div className="text-xs text-zinc-400">Numero</div>
                    <div className="tabular-nums">{parsed.numero}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Serie</div>
                    <div className="tabular-nums">{parsed.serie}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Prestador (CNPJ)</div>
                    <div className="tabular-nums">{parsed.prestador_cnpj || "-"}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Tomador (doc)</div>
                    <div className="tabular-nums">{parsed.tomador_documento || "-"}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Emissao</div>
                    <div className="tabular-nums">{parsed.data_emissao || "-"}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-400">Valor total</div>
                    <div className="tabular-nums">R$ {parsedTotal.toFixed(2)}</div>
                  </div>
                  <div className="col-span-2">
                    <div className="text-xs text-zinc-400">Chave</div>
                    <div className="break-all">{chaveAcesso || "-"}</div>
                    {alreadyImportedId ? <div className="mt-1 text-xs text-rose-200">Ja importada: {alreadyImportedId}</div> : null}
                  </div>
                </div>
              )}
            </div>
          </div>

          {parsed ? (
            <OsVinculoField
              tenantId={tenantId}
              empresaId={empresaId}
              value={osSelection}
              onChange={setOsSelection}
              disabled={busy || checkingDuplicate || !ready}
              helperText="Opcional. O valor desta NFS-e sera abatido da carteira da OS vinculada."
            />
          ) : null}

          {parsed ? (
            <div className="rounded-md border border-zinc-800 bg-zinc-950 p-3 space-y-3">
              <div className="text-xs font-medium text-zinc-300">Pagamentos (Contas a Receber)</div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end">
                <label className="block text-xs text-zinc-400">
                  Quantidade de pagamentos
                  <input
                    type="number"
                    min={1}
                    max={24}
                    value={qtdPagamentos}
                    onChange={(e) => onChangeQtdPagamentos(e.target.value)}
                    disabled={busy}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  />
                </label>
                <div className="sm:col-span-2 text-xs text-zinc-500">
                  Defina valor e data de vencimento para cada parcela.
                </div>
              </div>

              <div className="space-y-2">
                {parcelas.slice(0, qtdPagamentos).map((p, idx) => (
                  <div key={p.numero} className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                    <div className="rounded-md border border-zinc-800 bg-zinc-900/30 px-2 py-2 text-sm text-zinc-200">
                      Parcela {idx + 1}
                    </div>
                    <label className="block text-xs text-zinc-400">
                      Valor
                      <input
                        type="number"
                        step="0.01"
                        min="0"
                        value={p.valor}
                        onChange={(e) => onChangeParcela(idx, "valor", e.target.value)}
                        disabled={busy}
                        className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                      />
                    </label>
                    <label className="block text-xs text-zinc-400">
                      Data
                      <input
                        type="date"
                        value={p.vencimento}
                        onChange={(e) => onChangeParcela(idx, "vencimento", e.target.value)}
                        disabled={busy}
                        className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                      />
                    </label>
                  </div>
                ))}
              </div>
            </div>
          ) : null}

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
