"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { BrowserMultiFormatReader } from "@zxing/browser";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";

type ItemRow = {
  id: string;
  codigo: string;
  descricao: string;
  quantidade: number | null;
  quantidadeText: string;
  itemId: number | null;
  tipo: string | null;
  finalidade: string | null;
  controlaEstoque: boolean | null;
  valorUnitario: number | null;
  estoqueAtual: number | null;
  itemFound?: boolean | null;
  itemLoading?: boolean;
  itemError?: string | null;
};

type OsInfo = {
  id: number;
  descricao: string;
  status: string | null;
  clienteNome: string;
};

type CachedItem = {
  id: number;
  descricao: string;
  tipo: string | null;
  finalidade: string | null;
  controlaEstoque: boolean | null;
  valorUnitario: number | null;
  estoqueAtual: number | null;
};

type ClienteRow = {
  nome: string | null;
  razao_social: string | null;
};

type OsRow = {
  id: number;
  numero_os?: string | null;
  descricao_servico?: string | null;
  descricao?: string | null;
  status?: string | null;
  cliente_nome?: string | null;
  cliente_id?: number | null;
};

type ItemLookupRow = {
  id: number;
  codigo_interno?: string | null;
  nome?: string | null;
  descricao?: string | null;
  tipo?: string | null;
  finalidade?: string | null;
  controla_estoque?: boolean | null;
  preco_unitario?: number | null;
};

type EstoqueQuantidadeRow = {
  quantidade_atual: number | null;
};

type EstoqueItemRow = {
  item_id: number;
  quantidade_atual: number | null;
};

type DetectorLike = {
  detect: (source: HTMLVideoElement) => Promise<Array<{ rawValue?: string }>>;
};

type ZxingControls = {
  stop: () => void;
};

const createEmptyRow = (): ItemRow => ({
  id: typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : Math.random().toString(36).slice(2, 8),
  codigo: "",
  descricao: "",
  quantidade: null,
  quantidadeText: "",
  itemId: null,
  tipo: null,
  finalidade: null,
  controlaEstoque: null,
  valorUnitario: null,
  estoqueAtual: null,
  itemFound: null,
  itemLoading: false,
  itemError: null,
});

const isRowEmpty = (row: ItemRow) =>
  row.codigo.trim() === "" && row.descricao.trim() === "" && row.quantidadeText.trim() === "";

const isRowComplete = (row: ItemRow) => {
  const qtyValid = row.quantidade !== null && !Number.isNaN(row.quantidade);
  const hasFound = row.itemFound === true;
  const hasId = row.itemId !== null;
  return hasFound && qtyValid && hasId;
};

function ensureTrailingEmptyRow(rows: ItemRow[]) {
  const next = rows.length ? [...rows] : [createEmptyRow()];

  while (next.length > 1 && isRowEmpty(next[next.length - 1]) && isRowEmpty(next[next.length - 2])) {
    next.pop();
  }

  const last = next[next.length - 1];
  if (isRowComplete(last)) {
    next.push(createEmptyRow());
  }

  return next;
}

const statusLabels: Record<string, { label: string; className: string }> = {
  em_andamento: { label: "Em andamento", className: "bg-emerald-900/50 text-emerald-100" },
  aberta: { label: "Aberta", className: "bg-zinc-800 text-zinc-200" },
  concluida: { label: "Concluida", className: "bg-blue-900/50 text-blue-100" },
  cancelada: { label: "Cancelada", className: "bg-red-900/50 text-red-100" },
};

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

export default function BaixaOsCelPage() {
  const supabase = supabaseBrowser();
  const { tenantId, empresaId } = useTenantEmpresa();
  const fixedTenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
  const fixedEmpresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
  const effectiveTenantId = useMemo(() => tenantId ?? fixedTenantId, [tenantId]);
  const effectiveEmpresaId = useMemo(() => empresaId ?? fixedEmpresaId, [empresaId]);
  const [tenantValidated, setTenantValidated] = useState(false);

  const [os, setOs] = useState("");
  const [osDescricao, setOsDescricao] = useState("");
  const [osId, setOsId] = useState<number | null>(null);
  const [osStatus, setOsStatus] = useState<string | null>(null);
  const [osClienteNome, setOsClienteNome] = useState("");
  const [osLoading, setOsLoading] = useState(false);
  const [osError, setOsError] = useState<string | null>(null);

  const [showOsLookup, setShowOsLookup] = useState(false);
  const [osLookupTerm, setOsLookupTerm] = useState("");
  const [osLookupRows, setOsLookupRows] = useState<OsRow[]>([]);
  const [osLookupLoading, setOsLookupLoading] = useState(false);
  const [osLookupError, setOsLookupError] = useState<string | null>(null);

  const [rows, setRows] = useState<ItemRow[]>([createEmptyRow()]);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const [supportsDetector, setSupportsDetector] = useState(false);
  const [supportsCamera, setSupportsCamera] = useState(false);
  const [scanMode, setScanMode] = useState<"detector" | "zxing" | "none">("none");
  const [scanningRowId, setScanningRowId] = useState<string | null>(null);
  const [scanError, setScanError] = useState<string | null>(null);
  const [ocrBusyRowId, setOcrBusyRowId] = useState<string | null>(null);

  const validItems = useMemo(() => rows.filter(isRowComplete), [rows]);

  const osCacheRef = useRef<Record<string, OsInfo | null>>({});
  const itemCacheRef = useRef<Record<string, CachedItem | null>>({});
  const osDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const osLookupDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const itemDebounceRef = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const scanLoopRef = useRef<number | null>(null);
  const detectorRef = useRef<DetectorLike | null>(null);
  const zxingReaderRef = useRef<BrowserMultiFormatReader | null>(null);
  const zxingControlsRef = useRef<ZxingControls | null>(null);
  const ocrInputRef = useRef<HTMLInputElement | null>(null);
  const ocrRowRef = useRef<string | null>(null);

  useEffect(() => {
    setTenantValidated(true);
  }, [tenantId, effectiveTenantId]);

  useEffect(() => {
    const hasDetector = typeof window !== "undefined" && "BarcodeDetector" in window;
    const hasCamera = typeof navigator !== "undefined" && !!navigator.mediaDevices?.getUserMedia;
    setSupportsDetector(hasDetector);
    setSupportsCamera(hasCamera);
    setScanMode(hasDetector ? "detector" : hasCamera ? "zxing" : "none");
  }, []);

  useEffect(() => {
    const timeoutsRef = itemDebounceRef.current;
    return () => {
      if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
      if (osLookupDebounceRef.current) clearTimeout(osLookupDebounceRef.current);
      const timeouts = Object.values(timeoutsRef);
      timeouts.forEach((t) => clearTimeout(t));
      stopScan();
    };
  }, []);

  const normalizeOsNumber = (numero: string) => {
    const trimmed = numero.trim();
    if (/^\d+$/.test(trimmed)) {
      return String(Number(trimmed));
    }
    return trimmed;
  };

  const fetchClienteNome = useCallback(async (clienteId: number | null, clienteNomeInline: string | null) => {
    if (clienteNomeInline && clienteNomeInline.trim() !== "") {
      return clienteNomeInline.trim();
    }
    if (!clienteId) return "-";

    const { data, error: cliErr } = await supabase
      .from("clientes")
      .select("nome,razao_social")
      .eq("id", clienteId)
      .maybeSingle();

    if (cliErr || !data) return "-";
    const cliente = data as ClienteRow;
    const nome = cliente.nome ?? cliente.razao_social ?? "";
    return nome.trim() === "" ? "-" : nome;
  }, [supabase]);

  const fetchOs = useCallback(async (numero: string) => {
    const normalized = normalizeOsNumber(numero);
    if (!normalized) {
      setOsDescricao("");
      setOsId(null);
      setOsStatus(null);
      setOsClienteNome("");
      setOsError(null);
      return;
    }

    if (osCacheRef.current[normalized] !== undefined) {
      const cached = osCacheRef.current[normalized];
      if (cached) {
        setOsDescricao(cached.descricao);
        setOsId(cached.id);
        setOsStatus(cached.status);
        setOsClienteNome(cached.clienteNome);
        setOsError(null);
      } else {
        setOsDescricao("");
        setOsId(null);
        setOsStatus(null);
        setOsClienteNome("");
        setOsError("OS nao encontrada");
      }
      return;
    }

    setOsLoading(true);
    setOsError(null);

    const { data, error: queryError } = await supabase
      .from("ordens_servico")
      .select("id,descricao_servico,status,cliente_nome,cliente_id")
      .eq("numero_os", normalized)
      .maybeSingle();

    setOsLoading(false);

    if (queryError) {
      setOsDescricao("");
      setOsId(null);
      setOsStatus(null);
      setOsClienteNome("");
      setOsError("Erro ao buscar OS");
      osCacheRef.current[normalized] = null;
      return;
    }

    if (!data) {
      setOsDescricao("");
      setOsId(null);
      setOsStatus(null);
      setOsClienteNome("");
      setOsError("OS nao encontrada");
      osCacheRef.current[normalized] = null;
      return;
    }

    const osRow = data as OsRow;
    const osIdDb = Number(osRow.id ?? null);
    const descricaoDb = osRow.descricao_servico ?? osRow.descricao ?? "";
    const statusDb = osRow.status ?? null;
    const clienteNomeInline = osRow.cliente_nome ?? null;
    const clienteId = osRow.cliente_id ?? null;

    const clienteNome = await fetchClienteNome(clienteId, clienteNomeInline);

    osCacheRef.current[normalized] = { id: osIdDb, descricao: descricaoDb, status: statusDb, clienteNome };
    setOsDescricao(descricaoDb);
    setOsId(osIdDb);
    setOsStatus(statusDb);
    setOsClienteNome(clienteNome);
    setOsError(null);
  }, [fetchClienteNome, supabase]);

  const openOsLookup = () => {
    setOsLookupTerm("");
    setOsLookupRows([]);
    setOsLookupError(null);
    setShowOsLookup(true);
  };

  const closeOsLookup = () => {
    setShowOsLookup(false);
  };

  const loadOsLookup = useCallback(async (term: string) => {
    setOsLookupLoading(true);
    setOsLookupError(null);

    const trimmed = term.trim();
    if (!trimmed) {
      setOsLookupRows([]);
      setOsLookupLoading(false);
      return;
    }

    let query = supabase
      .from("ordens_servico")
      .select("id,numero_os,cliente_nome,descricao_servico,status")
      .order("id", { ascending: false })
      .limit(50)
      .eq("status", "em_andamento");

    if (trimmed) {
      query = query.or(`numero_os.ilike.%${trimmed}%,cliente_nome.ilike.%${trimmed}%`);
    }

    const { data, error: queryError } = await query;

    setOsLookupLoading(false);

    if (queryError) {
      setOsLookupError("Erro ao buscar OS");
      setOsLookupRows([]);
      return;
    }

    setOsLookupRows((data ?? []) as OsRow[]);
  }, [supabase]);

  const fetchItem = async (rowId: string, codigo: string) => {
    const trimmed = codigo.trim();
    if (!trimmed) {
      setRows((prev) =>
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: "",
                itemId: null,
                tipo: null,
                finalidade: null,
                controlaEstoque: null,
                valorUnitario: null,
                estoqueAtual: null,
                itemFound: null,
                itemError: null,
                itemLoading: false,
              }
            : r
        )
      );
      return;
    }

    const isNumeric = /^\d+$/.test(trimmed);
    const cacheKey = isNumeric ? String(Number(trimmed)) : trimmed;
    const queryValue = isNumeric ? Number(cacheKey) : trimmed;

    if (itemCacheRef.current[cacheKey] !== undefined) {
      const cached = itemCacheRef.current[cacheKey];
      if (cached) {
        setRows((prev) =>
          ensureTrailingEmptyRow(
            prev.map((r) =>
              r.id === rowId
                ? {
                    ...r,
                    descricao: cached?.descricao ?? "",
                    itemId: cached?.id ?? null,
                    tipo: cached?.tipo ?? null,
                    finalidade: cached?.finalidade ?? null,
                    controlaEstoque: cached?.controlaEstoque ?? null,
                    valorUnitario: cached?.valorUnitario ?? null,
                    estoqueAtual: cached?.estoqueAtual ?? null,
                    itemFound: cached !== null,
                    itemError:
                      cached && (cached.finalidade ?? "") !== "materia_prima"
                        ? "Apenas materia-prima"
                        : cached
                          ? null
                          : "Item nao encontrado",
                    itemLoading: false,
                  }
                : r
            )
          )
        );
        return;
      }
    }

    setRows((prev) =>
      prev.map((r) => (r.id === rowId ? { ...r, itemLoading: true, itemError: null } : r))
    );

    let data: ItemLookupRow | null = null;
    let queryError: { message?: string } | null = null;

    const selectFields = "id,codigo_interno,nome,descricao,tipo,finalidade,controla_estoque,preco_unitario";

    if (isNumeric) {
      const byNumber = await supabase.from("itens").select(selectFields).eq("id", queryValue).maybeSingle();
      data = (byNumber.data ?? null) as ItemLookupRow | null;
      queryError = byNumber.error ?? null;
      if (!data && !queryError) {
        const byString = await supabase.from("itens").select(selectFields).eq("id", cacheKey).maybeSingle();
        data = (byString.data ?? null) as ItemLookupRow | null;
        queryError = byString.error ?? null;
      }
    } else {
      const byString = await supabase.from("itens").select(selectFields).eq("id", queryValue).maybeSingle();
      data = (byString.data ?? null) as ItemLookupRow | null;
      queryError = byString.error ?? null;
    }

    if (queryError) {
      setRows((prev) =>
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: "",
                itemId: null,
                tipo: null,
                finalidade: null,
                controlaEstoque: null,
                valorUnitario: null,
                itemFound: false,
                itemError: "Erro ao buscar item",
                itemLoading: false,
              }
            : r
        )
      );
      itemCacheRef.current[cacheKey] = null;
      return;
    }

    if (!data) {
      setRows((prev) =>
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: "",
                itemId: null,
                tipo: null,
                finalidade: null,
                controlaEstoque: null,
                valorUnitario: null,
                itemFound: false,
                itemError: "Item nao encontrado",
                itemLoading: false,
              }
            : r
        )
      );
      itemCacheRef.current[cacheKey] = null;
      return;
    }

    const codigoInterno = data.codigo_interno ?? "";
    const nomeDesc = data.nome ?? data.descricao ?? "";
    const desc = codigoInterno ? `[${codigoInterno}] ${nomeDesc}` : nomeDesc;
    const tipo = data.tipo ?? null;
    const finalidade = data.finalidade ?? null;
    const controlaEstoque = data.controla_estoque ?? null;
    const valorUnitarioRaw = Number(data.preco_unitario ?? null);
    const valorUnitario = Number.isFinite(valorUnitarioRaw) ? valorUnitarioRaw : null;
    const itemId = Number(data.id);

    let estoqueAtual: number | null = null;
    const { data: estoqueData } = await supabase
      .from("estoque")
      .select("quantidade_atual")
      .eq("item_id", itemId)
      .maybeSingle();
    const estoqueRow = (estoqueData ?? null) as EstoqueQuantidadeRow | null;
    if (estoqueRow) estoqueAtual = Number(estoqueRow.quantidade_atual ?? 0);

    const isMateriaPrima = (finalidade ?? "") === "materia_prima";
    const itemError = isMateriaPrima ? null : "Apenas materia-prima";

    itemCacheRef.current[cacheKey] = {
      id: itemId,
      descricao: desc,
      tipo,
      finalidade,
      controlaEstoque,
      valorUnitario,
      estoqueAtual,
    };

    setRows((prev) =>
      ensureTrailingEmptyRow(
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: desc,
                itemId,
                tipo,
                finalidade,
                controlaEstoque,
                valorUnitario,
                estoqueAtual,
                itemFound: true,
                itemError,
                itemLoading: false,
              }
            : r
        )
      )
    );
  };

  const handleRowChange = (id: string, field: "codigo" | "descricao" | "quantidade", value: string) => {
    setRows((prev) => {
      const updated = prev.map((row) => {
        if (row.id !== id) return row;

        if (field === "quantidade") {
          const normalized = value.replace(",", ".").trim();
          const parsed = normalized === "" ? null : Number(normalized);
          return {
            ...row,
            quantidadeText: value,
            quantidade: Number.isNaN(parsed) ? null : parsed,
          };
        }

        if (field === "codigo") {
          return {
            ...row,
            codigo: value,
            itemFound: null,
            itemError: null,
            itemId: null,
            tipo: null,
            finalidade: null,
            controlaEstoque: null,
            valorUnitario: null,
            estoqueAtual: null,
          };
        }

        return row;
      });

      return ensureTrailingEmptyRow(updated);
    });

    if (field === "codigo") {
      if (itemDebounceRef.current[id]) clearTimeout(itemDebounceRef.current[id]);
      itemDebounceRef.current[id] = setTimeout(() => {
        fetchItem(id, value);
      }, 250);
    }
  };

  const removeRow = (id: string) => {
    setRows((prev) => {
      const idx = prev.findIndex((r) => r.id === id);
      if (idx === -1) return prev;
      if (idx === prev.length - 1 && isRowEmpty(prev[idx])) return prev;

      const next = prev.filter((r) => r.id !== id);
      return ensureTrailingEmptyRow(next.length ? next : [createEmptyRow()]);
    });
  };

  const handleScannedCode = (rowId: string, code: string) => {
    const clean = code?.trim();
    if (!clean) return;
    setRows((prev) =>
      ensureTrailingEmptyRow(
        prev.map((r) => (r.id === rowId ? { ...r, codigo: clean, itemFound: null, itemError: null } : r))
      )
    );
    fetchItem(rowId, clean);
  };

  const triggerOcrCapture = (rowId: string) => {
    ocrRowRef.current = rowId;
    if (ocrInputRef.current) {
      ocrInputRef.current.value = "";
      ocrInputRef.current.click();
    }
  };

  const handleOcrFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    const rowId = ocrRowRef.current;
    if (!file || !rowId) return;

    setScanError(null);
    setOcrBusyRowId(rowId);

    try {
      const { default: Tesseract } = await import("tesseract.js");
      const { data } = await Tesseract.recognize(file, "eng");
      const raw = (data?.text ?? "").replace(/\s+/g, " ").trim();
      const normalized = raw.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      const codMatch = normalized.match(/cod(?:igo)?\.?\s*[:\-]?\s*([0-9]{2,})/i);
      const codNumber = codMatch?.[1] ?? "";
      const numericMatches = raw.match(/\d{2,}/g) || [];
      const bestNumeric = numericMatches.sort((a, b) => b.length - a.length)[0];
      const fallbackMatch = raw.match(/[0-9A-Za-z_.-]+/);
      const code = codNumber || bestNumeric || fallbackMatch?.[0] || "";
      if (code) {
        handleScannedCode(rowId, code);
      } else {
        setScanError("Nada reconhecido na foto. Tente enquadrar apenas o numero.");
      }
    } catch (err: unknown) {
      setScanError(getErrorMessage(err, "Erro ao processar OCR."));
    } finally {
      setOcrBusyRowId(null);
      ocrRowRef.current = null;
      if (ocrInputRef.current) ocrInputRef.current.value = "";
    }
  };

  const stopScan = () => {
    if (scanLoopRef.current) {
      cancelAnimationFrame(scanLoopRef.current);
      scanLoopRef.current = null;
    }
    if (zxingControlsRef.current) {
      try {
        zxingControlsRef.current.stop();
      } catch {
        // noop
      }
      zxingControlsRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    setScanningRowId(null);
  };

  const startScan = async (rowId: string) => {
    setScanError(null);
    if (!supportsCamera) {
      setScanError("Camera indisponivel neste dispositivo.");
      return;
    }
    const willUseDetector = supportsDetector;
    try {
      if (willUseDetector) {
        const detectorCtor = (window as unknown as { BarcodeDetector?: new (options: { formats?: string[] }) => DetectorLike })
          .BarcodeDetector;
        if (!detectorRef.current) {
          if (detectorCtor) {
            detectorRef.current = new detectorCtor({
              formats: ["code_128", "code_39", "ean_13", "ean_8", "qr_code", "codabar"],
            });
          }
        }

        const stream = await navigator.mediaDevices.getUserMedia({
          video: {
            facingMode: { ideal: "environment" },
            width: { ideal: 1280 },
            height: { ideal: 720 },
          },
        });

        streamRef.current = stream;
        setScanningRowId(rowId);
        setScanMode("detector");

        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }

        const detect = async () => {
          if (!detectorRef.current || !videoRef.current) return;
          try {
            const codes = await detectorRef.current.detect(videoRef.current);
            if (codes?.length) {
              const codeText = codes[0]?.rawValue ?? "";
              if (codeText) {
                handleScannedCode(rowId, codeText);
                stopScan();
                return;
              }
            }
          } catch (err: unknown) {
            setScanError(getErrorMessage(err, "Erro ao ler codigo."));
          }
          scanLoopRef.current = requestAnimationFrame(detect);
        };

        detect();
      } else {
        // ZXing fallback (melhor suporte no iOS)
        if (!zxingReaderRef.current) {
          zxingReaderRef.current = new BrowserMultiFormatReader();
        }
        const reader = zxingReaderRef.current;
        const controls = await reader.decodeFromVideoDevice(
          undefined,
          videoRef.current!,
          (result, err) => {
            if (result && result.getText()) {
              handleScannedCode(rowId, result.getText());
              stopScan();
            }
            if (err && err.name !== "NotFoundException") {
              setScanError(err.message);
            }
          }
        );
        zxingControlsRef.current = controls;
        setScanningRowId(rowId);
        setScanMode("zxing");
      }
    } catch (err: unknown) {
      setScanError(getErrorMessage(err, "Nao foi possivel abrir a camera."));
      stopScan();
    }
  };

  const handleSubmit = async () => {
    const messages: string[] = [];
    setSuccess(null);

    if (os.trim() === "") messages.push("Informe a OS");
    if (osStatus !== "em_andamento") messages.push("So e possivel baixar itens em OS em andamento.");
    if (!osId) messages.push("OS nao encontrada");
    if (!empresaId) messages.push("Selecione uma empresa antes de baixar itens.");

    const hasInvalidQty = rows.some((r) => r.quantidade === null && r.quantidadeText.trim() !== "");
    if (hasInvalidQty) messages.push("Quantidade invalida");

    const hasMissingCode = rows.some((r, idx) => {
      const isLastEmpty = idx === rows.length - 1 && isRowEmpty(r);
      if (isLastEmpty) return false;
      const hasCode = r.codigo.trim() !== "";
      const hasQty = r.quantidadeText.trim() !== "" || r.quantidade !== null;
      return hasCode && hasQty && r.itemFound !== true;
    });
    if (hasMissingCode) messages.push("Item nao encontrado");

    const hasMissingId = rows.some((r) => r.itemFound === true && r.itemId === null);
    if (hasMissingId) messages.push("Item invalido");
    const hasNonMateriaPrima = rows.some(
      (r) => r.itemFound === true && (r.finalidade ?? "") !== "materia_prima"
    );
    if (hasNonMateriaPrima) messages.push("Apenas itens de materia-prima podem ser baixados");

    if (validItems.length === 0) messages.push("Informe pelo menos 1 item");

    if (messages.length) {
      setError(messages[0]);
      return;
    }

    setError(null);

    const itemIds = validItems.map((r) => r.itemId).filter((id): id is number => id !== null);
    const estoqueMap = new Map<number, number>();
    if (itemIds.length > 0) {
      const { data: estoqueData, error: estoqueErr } = await supabase
        .from("estoque")
        .select("item_id,quantidade_atual")
        .in("item_id", itemIds);

      if (estoqueErr) {
        setError("Erro ao consultar estoque");
        return;
      }

      const estoqueRows = (estoqueData ?? []) as EstoqueItemRow[];
      estoqueRows.forEach((e) => {
        estoqueMap.set(Number(e.item_id), Number(e.quantidade_atual ?? 0));
      });
    }

    const insuficiente = validItems.find((r) => {
      const precisaBaixa = (r.finalidade ?? "") === "materia_prima" && r.controlaEstoque !== false;
      if (!precisaBaixa || r.itemId === null) return false;
      const saldo = estoqueMap.has(r.itemId) ? estoqueMap.get(r.itemId)! : 0;
      return Number(r.quantidade ?? 0) > saldo;
    });

    if (insuficiente) {
      const saldo =
        insuficiente.itemId !== null && estoqueMap.has(insuficiente.itemId)
          ? estoqueMap.get(insuficiente.itemId)!
          : 0;
      setError(
        `Sem saldo suficiente para o item ${insuficiente.codigo || insuficiente.descricao}. Saldo atual: ${saldo.toLocaleString(
          "pt-BR"
        )}`
      );
      return;
    }

    setSubmitting(true);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    for (const item of validItems) {
      const precisaBaixa = (item.finalidade ?? "") === "materia_prima" && item.controlaEstoque !== false;
      const { error: rpcErr } = await supabase.rpc("add_os_item_baixa_imediata", {
        p_os_id: osId,
        p_item_id: item.itemId,
        p_quantidade: item.quantidade as number,
        p_valor_unitario: Number(item.valorUnitario ?? 0),
        p_baixa_estoque: precisaBaixa,
        p_realizado_por: userEmail,
        p_motivo: "Baixa manual pela tela Baixa OS Cel",
        p_empresa_id: empresaId,
      });

      if (rpcErr) {
        setSubmitting(false);
        setError(rpcErr.message);
        return;
      }
    }

    setSubmitting(false);
    setSuccess("Itens baixados e registrados na OS.");
    setRows([createEmptyRow()]);
  };

  useEffect(() => {
    if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
    osDebounceRef.current = setTimeout(() => {
      fetchOs(os);
    }, 300);

    return () => {
      if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
    };
  }, [os, fetchOs]);

  const canSubmit = osStatus === "em_andamento" && !!osDescricao && osId !== null;
  const submitEnabled = canSubmit && !submitting;

  const statusDisplay = osStatus ? statusLabels[osStatus]?.label ?? "-" : "-";
  const statusClass =
    osStatus && statusLabels[osStatus] ? statusLabels[osStatus].className : "bg-zinc-800 text-zinc-200";
  const scanStatusLabel =
    scanMode === "detector"
      ? "Camera pronta (nativo)"
      : scanMode === "zxing"
        ? "Camera pronta (ZXing)"
        : "Camera indisponivel";
  const scanStatusClass =
    scanMode === "none" ? "text-amber-300" : scanMode === "detector" ? "text-emerald-300" : "text-blue-200";

  return (
    <div className="min-h-screen px-3 py-4 bg-zinc-950">
      <div className="mx-auto max-w-xl space-y-4">
        <header className="space-y-1">
          <p className="text-xs uppercase tracking-[0.12em] text-blue-300/80">Apontamento celular</p>
          <h1 className="text-2xl font-semibold text-zinc-100">Baixa OS (Cel)</h1>
          <p className="text-sm text-zinc-400">
            Focado em celular: digite, leia por camera (codigo de barras/QR) ou foto OCR de numeros e informe a quantidade.
          </p>
        </header>

        <div className="space-y-3 rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4 shadow">
          <div className="grid grid-cols-1 gap-3">
            <div className="grid grid-cols-[1fr_1fr] gap-3">
              <label className="flex flex-col gap-1 text-sm font-medium text-zinc-200">
                <span>OS</span>
                <div className="flex gap-2 items-end">
                  <div className="relative flex-1">
                    <input
                      value={os}
                      onChange={(e) => setOs(e.target.value)}
                      disabled={!tenantValidated}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" && os.trim() === "") {
                          e.preventDefault();
                          openOsLookup();
                        }
                      }}
                      enterKeyHint="next"
                      className="w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-3 text-lg text-white placeholder:text-zinc-500 focus:border-blue-500 focus:outline-none"
                      placeholder="Numero da OS"
                      autoComplete="off"
                      inputMode="numeric"
                    />
                    {osLoading && (
                      <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[11px] text-blue-300">
                        carregando...
                      </span>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={openOsLookup}
                    className="shrink-0 px-4 py-3 rounded-xl border border-zinc-700 bg-zinc-900 text-sm text-zinc-100 hover:bg-zinc-800"
                  >
                    Pesquisar
                  </button>
                </div>
                {osError && <span className="text-xs text-red-300">{osError}</span>}
              </label>

              <label className="flex flex-col gap-1 text-sm font-medium text-zinc-200">
                <span>Cliente</span>
                <input
                  value={osClienteNome || "-"}
                  readOnly
                  title="Campo preenchido automaticamente"
                  className="w-full rounded-lg border border-zinc-800 bg-zinc-900 px-3 py-3 text-lg text-white placeholder:text-zinc-500 focus:border-blue-500 focus:outline-none opacity-90 cursor-not-allowed"
                />
              </label>
            </div>
          </div>

          <label className="flex flex-col gap-1 text-sm font-medium text-zinc-200">
            <span>Descricao</span>
            <textarea
              value={osDescricao}
              readOnly
              title="Campo preenchido automaticamente"
              className="w-full rounded-lg border border-zinc-800 bg-zinc-900 px-3 py-3 text-lg text-white placeholder:text-zinc-500 focus:border-blue-500 focus:outline-none min-h-[80px] opacity-90 cursor-not-allowed"
              placeholder="Descricao da OS"
            />
          </label>

          <div className="flex flex-col gap-1 text-sm font-medium text-zinc-200">
            <span>Condicao</span>
            <div className={`rounded-lg border border-zinc-800 px-3 py-3 text-lg ${statusClass}`}>
              {statusDisplay}
            </div>
          </div>
        </div>

        <div className="space-y-3 rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4 shadow">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-lg font-semibold text-zinc-100">Itens</h2>
              <p className="text-xs text-zinc-500">Use camera ou digitacao rapida.</p>
            </div>
            <span className={`text-[11px] ${scanStatusClass}`}>{scanStatusLabel}</span>
          </div>

          <div className="space-y-2">
            {rows.map((row, idx) => {
              const showRemove = !(idx === rows.length - 1 && isRowEmpty(row));

              return (
                <div key={row.id} className="space-y-2 rounded-xl border border-zinc-800 bg-zinc-950 p-3 shadow-sm">
                  <div className="flex gap-2">
                    <div className="flex-1">
                      <div className="text-[11px] uppercase text-zinc-400">Codigo</div>
                      <div className="flex gap-2 items-center">
                        <div className="relative flex-1">
                          <input
                            value={row.codigo}
                            onChange={(e) => handleRowChange(row.id, "codigo", e.target.value)}
                            className="w-full rounded-lg bg-zinc-900 px-3 py-3 text-base text-white placeholder:text-zinc-500 focus:border focus:border-blue-500 focus:outline-none border border-zinc-800/70"
                            placeholder="ID ou codigo do item"
                            autoComplete="off"
                            enterKeyHint="next"
                            inputMode="text"
                          />
                          {row.itemLoading && (
                            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[11px] text-blue-300">
                              ...
                            </span>
                          )}
                        </div>
                        <button
                          type="button"
                          onClick={() => (scanningRowId === row.id ? stopScan() : startScan(row.id))}
                          className={`shrink-0 rounded-lg px-3 py-2 text-sm font-semibold ${
                            scanningRowId === row.id
                              ? "border border-emerald-500/60 bg-emerald-900/40 text-emerald-100"
                              : "border border-blue-500/50 bg-blue-500/10 text-blue-100 hover:bg-blue-500/20"
                          }`}
                          disabled={!supportsCamera}
                        >
                          {scanningRowId === row.id ? "Parar" : "Camera"}
                        </button>
                        <button
                          type="button"
                          onClick={() => triggerOcrCapture(row.id)}
                          className="shrink-0 rounded-lg px-3 py-2 text-sm font-semibold border border-amber-500/60 bg-amber-500/10 text-amber-100 hover:bg-amber-500/20"
                          disabled={!!ocrBusyRowId}
                        >
                          {ocrBusyRowId === row.id ? "OCR..." : "Foto OCR"}
                        </button>
                      </div>
                      {row.itemError && <span className="text-[11px] text-red-300">{row.itemError}</span>}
                    </div>
                  </div>

                  <div>
                    <div className="text-[11px] uppercase text-zinc-400">Descricao</div>
                    <div className="w-full rounded-lg bg-zinc-900 px-2 py-2 text-base text-white leading-relaxed min-h-[52px] border border-zinc-800/70">
                      {row.descricao || <span className="text-zinc-500">Descricao</span>}
                    </div>
                  </div>

                  <div className="grid grid-cols-3 gap-2 items-end">
                    <div>
                      <div className="text-[11px] uppercase text-zinc-400">Estoque</div>
                      <div className="rounded-lg bg-zinc-900 px-3 py-2 text-sm text-zinc-200 border border-zinc-800/70">
                        {row.estoqueAtual !== null
                          ? row.estoqueAtual.toLocaleString("pt-BR", { minimumFractionDigits: 0 })
                          : "-"}
                      </div>
                    </div>

                    <div className="col-span-2">
                      <div className="text-[11px] uppercase text-zinc-400">Quantidade</div>
                      <div className="flex gap-2 items-center">
                        <input
                          value={row.quantidadeText}
                          onChange={(e) => handleRowChange(row.id, "quantidade", e.target.value)}
                          className="w-full rounded-lg bg-zinc-900 px-4 py-3 text-base text-white placeholder:text-zinc-500 focus:border focus:border-blue-500 focus:outline-none text-right border border-zinc-800/70"
                          placeholder="0,0"
                          inputMode="decimal"
                          enterKeyHint="done"
                        />
                        {showRemove && (
                          <button
                            type="button"
                            onClick={() => removeRow(row.id)}
                            className="shrink-0 rounded-full border border-red-900 bg-red-900/40 px-3 py-2 text-[11px] font-semibold text-red-100 hover:bg-red-900/60"
                          >
                            remover
                          </button>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          {scanError && <div className="text-sm text-red-300">{scanError}</div>}

          <div
            className={`rounded-xl border border-blue-500/40 bg-blue-950/40 p-3 space-y-2 ${
              scanningRowId ? "" : "hidden"
            }`}
          >
            <div className="text-sm font-semibold text-blue-100">Lendo codigo...</div>
            <video ref={videoRef} className="w-full rounded-lg border border-zinc-800 bg-black" autoPlay muted playsInline />
            <div className="flex items-center gap-2 text-xs text-blue-100">
              <span className="inline-flex h-2 w-2 rounded-full bg-emerald-400 animate-pulse" />
              Aponte a camera para o codigo de barras ou QR. Fecha automaticamente ao ler.
            </div>
          </div>

          <input
            ref={ocrInputRef}
            type="file"
            accept="image/*"
            capture="environment"
            className="hidden"
            onChange={handleOcrFile}
          />
        </div>

        {success && (
          <div className="rounded-xl border border-emerald-900 bg-emerald-950 px-4 py-3 text-sm text-emerald-200">
            {success}
          </div>
        )}

        {error && (
          <div className="rounded-xl border border-red-900 bg-red-950 px-4 py-3 text-sm text-red-200">{error}</div>
        )}

        <button
          type="button"
          onClick={handleSubmit}
          disabled={!submitEnabled}
          className={`w-full rounded-2xl px-4 py-4 text-lg font-semibold text-white shadow-lg shadow-blue-500/20 ${
            submitEnabled ? "bg-blue-600 hover:bg-blue-500 active:translate-y-[1px]" : "bg-zinc-700 text-zinc-300"
          }`}
        >
          {submitting ? "Baixando..." : "Baixar Itens"}
        </button>
      </div>

      {showOsLookup && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto"
          onClick={(e) => e.target === e.currentTarget && closeOsLookup()}
        >
          <div className="min-h-full w-full flex items-start sm:items-center justify-center p-4 py-6">
            <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl max-h-[90vh] flex flex-col overflow-hidden">
              <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
                <div>
                  <div className="text-lg font-semibold">Buscar OS</div>
                  <div className="text-sm text-zinc-400">Digite numero da OS ou cliente para buscar.</div>
                </div>
                <button
                  type="button"
                  onClick={closeOsLookup}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>

              <div className="px-5 py-4 space-y-3 flex-1 min-h-0 overflow-auto">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Buscar</div>
                  <input
                    value={osLookupTerm}
                    onChange={(e) => {
                      const value = e.target.value;
                      setOsLookupTerm(value);
                      if (osLookupDebounceRef.current) clearTimeout(osLookupDebounceRef.current);
                      osLookupDebounceRef.current = setTimeout(() => {
                        void loadOsLookup(value);
                      }, 300);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void loadOsLookup(osLookupTerm);
                      }
                    }}
                    placeholder="Ex: 43 ou nome do cliente"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    autoFocus
                  />
                </div>

                {osLookupLoading && <div className="text-sm text-zinc-400">Buscando...</div>}
                {osLookupError && <div className="text-sm text-red-400">{osLookupError}</div>}

                <div className="border border-zinc-800 rounded-lg overflow-hidden">
                  <table className="w-full text-sm">
                    <thead className="bg-zinc-900/70">
                      <tr className="text-zinc-200">
                        <th className="px-3 py-2 text-left">OS</th>
                        <th className="px-3 py-2 text-left">Cliente</th>
                        <th className="px-3 py-2 text-left">Descricao</th>
                        <th className="px-3 py-2 text-center">Acao</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {osLookupRows.map((row) => (
                        <tr key={row.id} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2">{row.numero_os ?? row.id}</td>
                          <td className="px-3 py-2">{row.cliente_nome ?? "-"}</td>
                          <td className="px-3 py-2">{row.descricao_servico ?? "-"}</td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => {
                                const numero = row.numero_os ?? String(row.id);
                                setOs(numero);
                                closeOsLookup();
                              }}
                              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                            >
                              Selecionar
                            </button>
                          </td>
                        </tr>
                      ))}
                      {!osLookupLoading && osLookupRows.length === 0 && osLookupTerm.trim() !== "" && (
                        <tr>
                          <td colSpan={4} className="px-3 py-4 text-zinc-400">
                            Nenhuma OS encontrada.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
