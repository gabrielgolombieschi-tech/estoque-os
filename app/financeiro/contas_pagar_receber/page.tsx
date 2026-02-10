"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { formatMoneyBR, parseMoneyBR } from "@/lib/decimal";

type Kind = "AP" | "AR";

type UnifiedRow = {
  kind: Kind;
  tituloId: string;
  parcelaId: string;
  parcelaNumero: string | null;
  emissao: string | null; // yyyy-mm-dd (AP manual / XML)
  vencimento: string; // yyyy-mm-dd
  pessoaNome: string;
  descricao: string | null;
  motivoCodigo: string | null; // AP only
  motivoNome: string | null; // AP only
  aprovadoPorNome: string | null; // AP only
  valor: number;
  valorAberto: number;
  tituloStatus: string;
};

type MotivoCompra = {
  id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
};

type Fornecedor = {
  id: number;
  nome: string;
};

type ContaBancaria = {
  id: string;
  codigo: string;
  nome: string;
};

type PagamentoAplicado = {
  valor: number;
  pagamento: {
    id: string;
    conta_bancaria_id: string;
    data_pagamento: string;
    forma_pagamento: string;
    valor: number;
  };
};

function getErrorMessage(error: unknown, fallback: string): string {
  if (!error) return fallback;
  if (typeof error === "string") return error;
  if (typeof error === "object" && error !== null && "message" in error) {
    const msg = (error as { message?: unknown }).message;
    if (typeof msg === "string" && msg.trim()) return msg;
  }
  try {
    return JSON.stringify(error);
  } catch {
    return fallback;
  }
}

function isMissingRpc(error: unknown, functionName: string) {
  const msg = getErrorMessage(error, "").toLowerCase();
  // Supabase/PostgREST typical message:
  // "Could not find the function f.criar_titulo_ap_manual(...) in the schema cache"
  return msg.includes("could not find the function") && msg.includes(functionName.toLowerCase());
}

function pad2(n: number) {
  return String(n).padStart(2, "0");
}

function monthIso(date = new Date()) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}`;
}

function monthRange(month: string): { ini: string; fim: string } {
  const [y, m] = month.split("-").map((v) => Number(v));
  const first = new Date(y, m - 1, 1);
  const last = new Date(y, m, 0);
  const toISO = (d: Date) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  return { ini: toISO(first), fim: toISO(last) };
}

function toDateOnly(iso: string): Date {
  const [y, m, d] = iso.split("-").map((v) => Number(v));
  return new Date(y, (m ?? 1) - 1, d ?? 1);
}

function isOverdue(vencimentoISO: string): boolean {
  const today = new Date();
  const today0 = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  return toDateOnly(vencimentoISO).getTime() < today0.getTime();
}

function statusBadge(row: UnifiedRow): { label: string; className: string } {
  const overdue = isOverdue(row.vencimento) && row.valorAberto > 0;
  if (overdue) {
    return { label: "Atrasado", className: "bg-red-500/15 text-red-300 border border-red-500/30" };
  }

  if (row.kind === "AP") {
    if ((row.motivoCodigo ?? "").toUpperCase() === "NAO_CLASSIFICADO") {
      return {
        label: "Pendente aprovação",
        className: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
      };
    }
    return { label: "Aprovado", className: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30" };
  }

  return { label: "A receber", className: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30" };
}

function fmtParcela(n: string | null) {
  return n ? `Parc. ${n}` : "Parcela";
}

function FormError({ message }: { message: string | null }) {
  if (!message) return null;
  return <div className="text-sm text-red-300">{message}</div>;
}

function buildYearOptions(centerYear: number, span = 3) {
  const years: number[] = [];
  for (let y = centerYear - span; y <= centerYear + span; y++) years.push(y);
  return years;
}

function todayISO(): string {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function formatDateBR(iso: string | null | undefined): string {
  if (!iso) return "";
  const [y, m, d] = String(iso).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

export default function ContasPagarReceberPage() {
  const te = useTenantEmpresa();
  const supabase = useMemo(() => getSupabaseBrowser(), []);

  const canFinanceiro = (te.has("financeiro.read") ?? false) || (te.has("financeiro.write") ?? false);

  const [month, setMonth] = useState<string>(() => monthIso());
  const range = useMemo(() => monthRange(month), [month]);
  const [year, setYear] = useState<number>(() => Number(month.split("-")[0] ?? new Date().getFullYear()));
  const [monthNum, setMonthNum] = useState<number>(() => Number(month.split("-")[1] ?? new Date().getMonth() + 1));

  useEffect(() => {
    const next = `${year}-${pad2(monthNum)}`;
    if (next !== month) setMonth(next);
  }, [month, monthNum, year]);

  const [q, setQ] = useState("");
  const [only, setOnly] = useState<"ALL" | Kind>("ALL");
  const [onlyToday, setOnlyToday] = useState(false);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<UnifiedRow[]>([]);

  const [selected, setSelected] = useState<UnifiedRow | null>(null);
  const [tab, setTab] = useState<"APROVAR" | "PAGAR" | "RECEBER">("APROVAR");

  const [createOpen, setCreateOpen] = useState(false);
  const [createBusy, setCreateBusy] = useState(false);
  const [createErr, setCreateErr] = useState<string | null>(null);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);

  const [newFornecedorId, setNewFornecedorId] = useState<string>("");
  const [newDescricao, setNewDescricao] = useState<string>("");
  const [newEmissaoDate, setNewEmissaoDate] = useState<string>(todayISO());
  const [newVencimento, setNewVencimento] = useState<string>(todayISO());
  const [newValor, setNewValor] = useState<string>("");
  const [newMotivoId, setNewMotivoId] = useState<string>("");
  const [newRecorrente, setNewRecorrente] = useState<boolean>(false);
  const [newProvisionarMeses, setNewProvisionarMeses] = useState<number>(12);

  const [motivos, setMotivos] = useState<MotivoCompra[]>([]);
  const [contas, setContas] = useState<ContaBancaria[]>([]);
  const [aplicacoes, setAplicacoes] = useState<PagamentoAplicado[]>([]);

  const [actionBusy, setActionBusy] = useState(false);
  const [actionErr, setActionErr] = useState<string | null>(null);

  const [tituloMeta, setTituloMeta] = useState<{ emissaoDate: string | null; documentoFiscalId: string | null } | null>(
    null
  );
  const [editEmissaoDate, setEditEmissaoDate] = useState<string>("");
  const [emissaoBusy, setEmissaoBusy] = useState(false);
  const [emissaoErr, setEmissaoErr] = useState<string | null>(null);

  // Aprovar
  const [motivoId, setMotivoId] = useState<string>("");
  const [motivoOutrosText, setMotivoOutrosText] = useState<string>("");
  const [osId, setOsId] = useState<string>("");

  // Pagar / Receber
  const [contaBancariaId, setContaBancariaId] = useState<string>("");
  const [dataPagamento, setDataPagamento] = useState<string>("");
  const [formaPagamento, setFormaPagamento] = useState<string>("PIX");
  const [valorMov, setValorMov] = useState<string>("");
  const [observacoes, setObservacoes] = useState<string>("");

  const resetModalState = useCallback(() => {
    setActionErr(null);
    setActionBusy(false);
    setEmissaoErr(null);
    setEmissaoBusy(false);
    setTituloMeta(null);
    setEditEmissaoDate("");
    setMotivoId("");
    setMotivoOutrosText("");
    setOsId("");
    setContaBancariaId("");
    setDataPagamento("");
    setFormaPagamento("PIX");
    setValorMov("");
    setObservacoes("");
    setAplicacoes([]);
  }, []);

  const requestIdRef = useRef(0);
  const load = useCallback(async () => {
    if (!canFinanceiro) return;
    if (!te.tenantId || !te.empresaId) return;

    const reqId = ++requestIdRef.current;
    setLoading(true);
    setError(null);

    try {
      const [{ data: apData, error: apErr }, { data: arData, error: arErr }] = await Promise.all([
        supabase
          .schema("f")
          .from("r_ap_aging_detalhe")
          .select(
            "titulo_id,parcela_id,parcela_numero,fornecedor_nome,motivo_codigo,motivo_nome,vencimento_date,valor_parcela,valor_aberto,status"
          )
          .gte("vencimento_date", range.ini)
          .lte("vencimento_date", range.fim),
        supabase
          .schema("f")
          .from("titulo_parcela")
          .select(
            "id,titulo_id,numero,vencimento_date,valor,valor_aberto,titulo:titulo_id!inner(id,tipo,status,cliente_id,descricao)"
          )
          .eq("titulo.tipo", "AR")
          .gt("valor_aberto", 0)
          .gte("vencimento_date", range.ini)
          .lte("vencimento_date", range.fim),
      ]);

      if (requestIdRef.current !== reqId) return;
      if (apErr) throw apErr;
      if (arErr) throw arErr;

      type ApAgingDetalheRow = {
        titulo_id: unknown;
        parcela_id: unknown;
        parcela_numero: unknown;
        vencimento_date: unknown;
        fornecedor_nome: unknown;
        motivo_codigo: unknown;
        motivo_nome: unknown;
        valor_parcela: unknown;
        valor_aberto: unknown;
        status: unknown;
      };

      const apRows: UnifiedRow[] = ((apData ?? []) as ApAgingDetalheRow[]).map((r) => ({
        kind: "AP",
        tituloId: String(r.titulo_id),
        parcelaId: String(r.parcela_id),
        parcelaNumero: r.parcela_numero ? String(r.parcela_numero) : null,
        emissao: null,
        vencimento: String(r.vencimento_date),
        pessoaNome: r.fornecedor_nome ? String(r.fornecedor_nome) : "Fornecedor",
        descricao: null,
        motivoCodigo: r.motivo_codigo ? String(r.motivo_codigo) : null,
        motivoNome: r.motivo_nome ? String(r.motivo_nome) : null,
        aprovadoPorNome: null,
        valor: Number(r.valor_parcela ?? 0),
        valorAberto: Number(r.valor_aberto ?? 0),
        tituloStatus: String(r.status ?? ""),
      }));

      // Enrich AP rows with approver name from f.titulo_aprovacao.aprovado_por (a.usuario.id)
      const apTituloIds = Array.from(new Set(apRows.map((r) => r.tituloId)));

      // Enrich AP rows with emissao_date from f.titulo (works for manual + XML titles).
      const emissaoByTituloId = new Map<string, string | null>();
      if (apTituloIds.length) {
        try {
          const { data: titulos, error: titErr } = await supabase
            .schema("f")
            .from("titulo")
            .select("id,emissao_date")
            .in("id", apTituloIds)
            .is("deleted_at", null);

          if (!titErr) {
            const tituloRows = (titulos ?? []) as Array<{ id: unknown; emissao_date: unknown }>;
            for (const t of tituloRows) {
              const id = t?.id ? String(t.id) : "";
              if (!id) continue;
              emissaoByTituloId.set(id, t?.emissao_date ? String(t.emissao_date) : null);
            }
          }
        } catch {
          // ignore enrichment failures
        }
      }

      const aprovadoPorNomeByTituloId = new Map<string, string>();
      if (apTituloIds.length) {
        const { data: aprovacoes, error: aprovErr } = await supabase
          .schema("f")
          .from("titulo_aprovacao")
          .select("titulo_id,aprovado_por")
          .in("titulo_id", apTituloIds)
          .is("deleted_at", null);

        if (!aprovErr) {
          const aprovacaoRows = (aprovacoes ?? []) as Array<{ titulo_id: unknown; aprovado_por: unknown }>;
          const aprovadorIds = Array.from(
            new Set(
              aprovacaoRows
                .map((a) => (a?.aprovado_por ? String(a.aprovado_por) : null))
                .filter((v): v is string => Boolean(v))
            )
          );

          const aprovadorNomeById = new Map<string, string>();
          if (aprovadorIds.length) {
            const { data: usuarios, error: usrErr } = await supabase
              .schema("a")
              .from("usuario")
              .select("id,nome")
              .in("id", aprovadorIds)
              .is("deleted_at", null);
            if (!usrErr) {
              type UsuarioRow = { id: unknown; nome: unknown };
              for (const u of (usuarios ?? []) as UsuarioRow[]) {
                const id = u?.id ? String(u.id) : "";
                const nome = u?.nome ? String(u.nome) : "";
                if (id && nome) aprovadorNomeById.set(id, nome);
              }
            }
          }

          for (const a of aprovacaoRows) {
            const tituloId = a?.titulo_id ? String(a.titulo_id) : "";
            const aprovadorId = a?.aprovado_por ? String(a.aprovado_por) : "";
            if (!tituloId || !aprovadorId) continue;
            const nome = aprovadorNomeById.get(aprovadorId) ?? "";
            if (nome) aprovadoPorNomeByTituloId.set(tituloId, nome);
          }
        }
      }

      const apRowsEnriched: UnifiedRow[] = apRows.map((r) => ({
        ...r,
        emissao: emissaoByTituloId.get(r.tituloId) ?? null,
        aprovadoPorNome: aprovadoPorNomeByTituloId.get(r.tituloId) ?? null,
      }));

      type ArParcelaJoinedRow = {
        id: unknown;
        titulo_id: unknown;
        numero: unknown;
        vencimento_date: unknown;
        valor: unknown;
        valor_aberto: unknown;
        titulo?: {
          cliente_id?: unknown;
          descricao?: unknown;
          status?: unknown;
        } | null;
      };

      const arRaw = (arData ?? []) as ArParcelaJoinedRow[];
      const clienteIds = Array.from(
        new Set(
          arRaw
            .map((r) => (r?.titulo?.cliente_id ? String(r.titulo.cliente_id) : null))
            .filter((v): v is string => Boolean(v))
        )
      );

      const clienteNomeById = new Map<string, string>();
      if (clienteIds.length) {
        const { data: clientes, error: clientesErr } = await supabase
          .from("clientes")
          .select("id,nome")
          .in("id", clienteIds);
        if (!clientesErr) {
          type ClienteRow = { id: unknown; nome: unknown };
          for (const c of (clientes ?? []) as ClienteRow[]) {
            const id = c?.id;
            const nome = c?.nome;
            if (id) clienteNomeById.set(String(id), nome ? String(nome) : "Cliente");
          }
        }
      }

      const arRows: UnifiedRow[] = arRaw.map((r) => {
        const clienteId = r?.titulo?.cliente_id ? String(r.titulo.cliente_id) : null;
        const pessoaNome = clienteId ? clienteNomeById.get(clienteId) ?? `Cliente ${clienteId}` : "Cliente";
        return {
          kind: "AR",
          tituloId: String(r.titulo_id),
          parcelaId: String(r.id),
          parcelaNumero: r.numero ? String(r.numero) : null,
          emissao: null,
          vencimento: String(r.vencimento_date),
          pessoaNome,
          descricao: r?.titulo?.descricao ? String(r.titulo.descricao) : null,
          motivoCodigo: null,
          motivoNome: null,
          aprovadoPorNome: null,
          valor: Number(r.valor ?? 0),
          valorAberto: Number(r.valor_aberto ?? 0),
          tituloStatus: String(r?.titulo?.status ?? ""),
        };
      });

      const merged = [...apRowsEnriched, ...arRows]
        .filter((r) => r.valorAberto > 0)
        .sort((a, b) => {
          const av = a.vencimento.localeCompare(b.vencimento);
          if (av !== 0) return av;
          if (a.kind !== b.kind) return a.kind === "AP" ? -1 : 1;
          return a.pessoaNome.localeCompare(b.pessoaNome);
        });

      setRows(merged);
    } catch (e: unknown) {
      if (requestIdRef.current !== reqId) return;
      setError(getErrorMessage(e, "Erro ao carregar contas."));
    } finally {
      if (requestIdRef.current === reqId) setLoading(false);
    }
  }, [canFinanceiro, range.fim, range.ini, supabase, te.empresaId, te.tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  const closeCreate = useCallback(() => {
    setCreateOpen(false);
    setCreateBusy(false);
    setCreateErr(null);
  }, []);

  const openCreate = useCallback(async () => {
    setCreateErr(null);
    setCreateBusy(false);
    setCreateOpen(true);

    // Defaults/suggestions
    setNewEmissaoDate(todayISO());
    setNewVencimento(todayISO());

    // Load motivos/fornecedores for manual AP.
    try {
      if (motivos.length === 0) {
        const { data, error } = await supabase
          .schema("f")
          .from("motivo_compra")
          .select("id,codigo,nome,requires_text,requires_os")
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("nome", { ascending: true });
        if (!error) {
          type MotivoCompraRow = {
            id: unknown;
            codigo: unknown;
            nome: unknown;
            requires_text: unknown;
            requires_os: unknown;
          };
          const mapped = ((data ?? []) as MotivoCompraRow[]).map((m) => ({
            id: String(m.id),
            codigo: String(m.codigo),
            nome: String(m.nome),
            requires_text: Boolean(m.requires_text),
            requires_os: Boolean(m.requires_os),
          }));
          setMotivos(mapped);
          const estoque = mapped.find((m) => m.codigo === "ESTOQUE") ?? null;
          if (!newMotivoId && estoque) setNewMotivoId(estoque.id);
        }
      }

      if (fornecedores.length === 0) {
        const { data, error } = await supabase
          .from("fornecedores")
          .select("id,nome")
          .eq("ativo", true)
          .order("nome", { ascending: true })
          .limit(500);
        if (!error) {
          type FornecedorRow = { id: unknown; nome: unknown };
          const mapped = (data ?? []) as FornecedorRow[];
          setFornecedores(
            mapped
              .map((f) => ({ id: Number(f.id), nome: f?.nome ? String(f.nome) : "Fornecedor" }))
              .filter((f) => Number.isFinite(f.id))
          );
        }
      }
    } catch (e: unknown) {
      setCreateErr(getErrorMessage(e, "Erro ao preparar criação."));
    }
  }, [fornecedores.length, motivos.length, newMotivoId, supabase]);

  const doCreateAp = useCallback(async () => {
    setCreateErr(null);
    const desc = newDescricao.trim();
    const emissao = newEmissaoDate;
    const venc = newVencimento;
    const valorParsed = parseMoneyBR(newValor);
    const fornecedorIdParsed = newFornecedorId.trim() ? Number(newFornecedorId) : null;

    if (!desc) {
      setCreateErr("Informe a descrição.");
      return;
    }
    if (!venc) {
      setCreateErr("Informe o vencimento.");
      return;
    }
    if (!emissao) {
      setCreateErr("Informe a data da NF (Emissão).");
      return;
    }
    if (!Number.isFinite(valorParsed) || valorParsed <= 0) {
      setCreateErr("Informe um valor válido.");
      return;
    }

    setCreateBusy(true);
    try {
      // IMPORTANT: RPC payload is strict. Do not send extra fields.
      const args = {
        p_descricao: desc,
        p_vencimento_date: venc,
        p_valor: valorParsed,
        p_fornecedor_id: fornecedorIdParsed && Number.isFinite(fornecedorIdParsed) ? fornecedorIdParsed : null,
        p_motivo_compra_id: newMotivoId || null,
        p_emissao_date: emissao,
        p_criar_recorrencia: Boolean(newRecorrente),
        p_dia_vencimento: null,
        p_auto_copiar_valor: true,
      };

      const { data, error } = await supabase.schema("f").rpc("criar_titulo_ap_manual_v2", args);

      if (error) {
        if (isMissingRpc(error, "f.criar_titulo_ap_manual_v2")) {
          throw new Error(
            "RPC f.criar_titulo_ap_manual_v2 não encontrada no banco. Aplique a migration/SQL do financeiro (AP manual v2)."
          );
        }
        throw error;
      }

      type CriarTituloApManualRes = { titulo_id?: unknown; recorrencia_id?: unknown };
      const row = (Array.isArray(data) ? data[0] : data) as CriarTituloApManualRes | null;
      const recorrenciaId = row?.recorrencia_id ? String(row.recorrencia_id) : null;

      if (newRecorrente && recorrenciaId && newProvisionarMeses > 0) {
        const { error: provErr } = await supabase.schema("f").rpc("provisionar_ap_recorrencia", {
          p_recorrencia_id: recorrenciaId,
          p_meses_a_frente: Number(newProvisionarMeses),
          p_change_reason: "UI:contas_pagar_receber:provisionar",
        });
        if (provErr) throw provErr;
      }

      await load();
      closeCreate();
    } catch (e: unknown) {
      setCreateErr(getErrorMessage(e, "Erro ao criar AP."));
    } finally {
      setCreateBusy(false);
    }
  }, [closeCreate, load, newDescricao, newEmissaoDate, newFornecedorId, newMotivoId, newRecorrente, newProvisionarMeses, newValor, newVencimento, supabase]);

  const doUpdateEmissaoDate = useCallback(async () => {
    if (!selected || selected.kind !== "AP") return;
    if (!editEmissaoDate) {
      setEmissaoErr("Informe a data da NF (Emissão).");
      return;
    }

    const canEdit = tituloMeta !== null && tituloMeta.documentoFiscalId === null;
    if (!canEdit) return;

    setEmissaoErr(null);
    setEmissaoBusy(true);
    try {
      const { error } = await supabase.schema("f").rpc("atualizar_titulo_emissao_date", {
        p_titulo_id: selected.tituloId,
        p_emissao_date: editEmissaoDate,
        p_atualizar_competencia: true,
        p_change_reason: "AJUSTE DATA NF (UI)",
      });
      if (error) throw error;

      setTituloMeta((prev) => (prev ? { ...prev, emissaoDate: editEmissaoDate } : prev));
      setSelected((prev) => (prev ? { ...prev, emissao: editEmissaoDate } : prev));
      await load();
    } catch (e: unknown) {
      setEmissaoErr(getErrorMessage(e, "Erro ao atualizar emissão."));
    } finally {
      setEmissaoBusy(false);
    }
  }, [editEmissaoDate, load, selected, supabase, tituloMeta?.documentoFiscalId]);

  const filtered = useMemo(() => {
    const today = todayISO();
    const query = q.trim().toLowerCase();
    return rows.filter((r) => {
      if (only !== "ALL" && r.kind !== only) return false;
      if (onlyToday && r.vencimento !== today) return false;
      if (!query) return true;
      return (
        r.pessoaNome.toLowerCase().includes(query) ||
        (r.descricao ?? "").toLowerCase().includes(query) ||
        (r.motivoNome ?? "").toLowerCase().includes(query) ||
        (r.aprovadoPorNome ?? "").toLowerCase().includes(query)
      );
    });
  }, [only, onlyToday, q, rows]);

  const totals = useMemo(() => {
    const sumAP = filtered.filter((r) => r.kind === "AP").reduce((acc, r) => acc + r.valorAberto, 0);
    const sumAR = filtered.filter((r) => r.kind === "AR").reduce((acc, r) => acc + r.valorAberto, 0);
    return { sumAP, sumAR };
  }, [filtered]);

  const selectedMotivo = useMemo(() => {
    if (!motivoId) return null;
    return motivos.find((m) => m.id === motivoId) ?? null;
  }, [motivoId, motivos]);

  const open = useCallback(
    async (row: UnifiedRow) => {
      resetModalState();
      setSelected(row);
      setTab(row.kind === "AP" ? "APROVAR" : "RECEBER");

      try {
        // Prefill AP approval fields from:
        // 1) existing approval row (f.titulo_aprovacao)
        // 2) imported title values (f.titulo.motivo_compra_id and f.documento_fiscal.os_id_import)
        // 3) default motivo (ESTOQUE)
        let prefMotivoId: string | null = null;
        let prefMotivoOutrosText: string | null = null;
        let prefOsInternalId: number | null = null;

        if (row.kind === "AP") {
          type AprovacaoRow = { motivo_compra_id: unknown; motivo_outros_text: unknown; os_id: unknown };
          const { data: aprovacao } = await supabase
            .schema("f")
            .from("titulo_aprovacao")
            .select("motivo_compra_id,motivo_outros_text,os_id")
            .eq("titulo_id", row.tituloId)
            .is("deleted_at", null)
            .maybeSingle<AprovacaoRow>();

          if (aprovacao?.motivo_compra_id) prefMotivoId = String(aprovacao.motivo_compra_id);
          if (typeof aprovacao?.motivo_outros_text === "string") prefMotivoOutrosText = aprovacao.motivo_outros_text;
          if (aprovacao?.os_id !== null && aprovacao?.os_id !== undefined && aprovacao.os_id !== "") {
            const n = Number(aprovacao.os_id);
            if (Number.isFinite(n)) prefOsInternalId = n;
          }

          // Load title meta (emissao + origin) and also use it to prefill missing approval fields.
          type TituloRow = {
            motivo_compra_id: unknown;
            emissao_date: unknown;
            documento_fiscal_id: unknown;
            documento_fiscal?: { os_id_import?: unknown } | null;
          };
          const { data: titulo } = await supabase
            .schema("f")
            .from("titulo")
            .select("motivo_compra_id,emissao_date,documento_fiscal_id,documento_fiscal:documento_fiscal_id(os_id_import)")
            .eq("id", row.tituloId)
            .is("deleted_at", null)
            .maybeSingle<TituloRow>();

          const documentoFiscalId = titulo?.documento_fiscal_id ? String(titulo.documento_fiscal_id) : null;
          const emissaoDate = titulo?.emissao_date ? String(titulo.emissao_date) : null;
          setTituloMeta({ documentoFiscalId, emissaoDate });
          setEditEmissaoDate(emissaoDate ?? row.emissao ?? todayISO());

          if (!prefMotivoId && titulo?.motivo_compra_id) prefMotivoId = String(titulo.motivo_compra_id);
          if (prefOsInternalId === null) {
            const osImport = titulo?.documento_fiscal?.os_id_import;
            const n = osImport === null || osImport === undefined || osImport === "" ? NaN : Number(osImport);
            if (Number.isFinite(n)) prefOsInternalId = n;
          }

          if (prefMotivoId) setMotivoId(prefMotivoId);
          if (prefMotivoOutrosText) setMotivoOutrosText(prefMotivoOutrosText);

          // Convert internal OS id -> displayed OS number
          if (prefOsInternalId !== null) {
            type OsRow = { numero_os: unknown };
            const { data: osRow } = await supabase
              .from("ordens_servico")
              .select("numero_os")
              .eq("id", prefOsInternalId)
              .maybeSingle<OsRow>();

            const numero = osRow?.numero_os ? String(osRow.numero_os) : "";
            if (numero) setOsId(numero);
          }
        }

        if (row.kind === "AP" && motivos.length === 0) {
          const { data, error } = await supabase
            .schema("f")
            .from("motivo_compra")
            .select("id,codigo,nome,requires_text,requires_os")
            .eq("ativo", true)
            .is("deleted_at", null)
            .order("nome", { ascending: true });
          if (!error) {
            type MotivoCompraRow = {
              id: unknown;
              codigo: unknown;
              nome: unknown;
              requires_text: unknown;
              requires_os: unknown;
            };
            const mapped = ((data ?? []) as MotivoCompraRow[]).map((m) => ({
              id: String(m.id),
              codigo: String(m.codigo),
              nome: String(m.nome),
              requires_text: Boolean(m.requires_text),
              requires_os: Boolean(m.requires_os),
            }));
            setMotivos(mapped);

            // Only default to ESTOQUE when we couldn't prefill from import/approval.
            const estoque = mapped.find((m) => m.codigo === "ESTOQUE") ?? null;
            if (!prefMotivoId && estoque) setMotivoId(estoque.id);
          }
        }

        if (contas.length === 0) {
          const { data, error } = await supabase
            .schema("f")
            .from("conta_bancaria")
            .select("id,codigo,nome")
            .eq("ativo", true)
            .is("deleted_at", null)
            .order("nome", { ascending: true });
          if (!error) {
            type ContaBancariaRow = { id: unknown; codigo: unknown; nome: unknown };
            const mapped = ((data ?? []) as ContaBancariaRow[]).map((c) => ({
              id: String(c.id),
              codigo: String(c.codigo),
              nome: String(c.nome),
            }));
            setContas(mapped);
            if (mapped.length === 1) setContaBancariaId(mapped[0].id);
          }
        }

        const { data: applied, error: appliedErr } = await supabase
          .schema("f")
          .from("pagamento_item")
          .select("valor,pagamento:pagamento_id(id,conta_bancaria_id,data_pagamento,forma_pagamento,valor)")
          .eq("titulo_parcela_id", row.parcelaId)
          .is("deleted_at", null)
          .order("created_at", { ascending: false });
        if (!appliedErr) setAplicacoes((applied ?? []) as unknown as PagamentoAplicado[]);
      } catch (e: unknown) {
        setActionErr(getErrorMessage(e, "Erro ao preparar modal."));
      }
    },
    [resetModalState, supabase, contas, motivos]
  );

  const close = useCallback(() => {
    setSelected(null);
    resetModalState();
  }, [resetModalState]);

  // UX: when opening/going to the "PAGAR" tab, prefill value with the current open amount.
  useEffect(() => {
    if (!selected) return;
    if (tab !== "PAGAR") return;
    if (selected.kind !== "AP") return;
    if (valorMov.trim()) return;
    setValorMov(formatMoneyBR(selected.valorAberto));
  }, [selected, tab, valorMov]);

  // UX: prefill payment/receipt date with today when entering PAGAR/RECEBER.
  useEffect(() => {
    if (!selected) return;
    if (tab !== "PAGAR" && tab !== "RECEBER") return;
    if (dataPagamento.trim()) return;

    const today = new Date();
    const iso = `${today.getFullYear()}-${pad2(today.getMonth() + 1)}-${pad2(today.getDate())}`;
    setDataPagamento(iso);
  }, [dataPagamento, selected, tab]);

  const doAprovar = useCallback(async () => {
    if (!selected || selected.kind !== "AP") return;
    if (!motivoId) {
      setActionErr("Selecione o motivo.");
      return;
    }
    if (selectedMotivo?.requires_text && !motivoOutrosText.trim()) {
      setActionErr("Preencha o motivo (texto).");
      return;
    }
    if (selectedMotivo?.requires_os && !osId.trim()) {
      setActionErr("Informe a OS.");
      return;
    }

    setActionBusy(true);
    setActionErr(null);
    try {
      let os: number | null = null;
      if (selectedMotivo?.requires_os) {
        const osNumero = osId.trim();
        type OsLookupRow = { id: unknown };

        // Prefer lookup by OS number (numero_os), since that's what the UI asks for.
        const { data: byNumero } = await supabase
          .from("ordens_servico")
          .select("id")
          .eq("numero_os", osNumero)
          .maybeSingle<OsLookupRow>();

        if (byNumero?.id) {
          const n = Number(byNumero.id);
          os = Number.isFinite(n) ? n : null;
        }

        // Fallback: accept direct internal id if user typed it.
        if (os === null) {
          const asId = Number(osNumero);
          if (Number.isFinite(asId)) {
            const { data: byId } = await supabase
              .from("ordens_servico")
              .select("id")
              .eq("id", asId)
              .maybeSingle<OsLookupRow>();
            if (byId?.id) os = asId;
          }
        }

        if (os === null) {
          setActionErr(`OS não encontrada: ${osNumero}`);
          setActionBusy(false);
          return;
        }
      }
      const { error } = await supabase.schema("f").rpc("aprovar_titulo_ap", {
        p_titulo_id: selected.tituloId,
        p_motivo_compra_id: motivoId,
        p_os_id: os,
        p_motivo_outros_text: selectedMotivo?.requires_text ? motivoOutrosText.trim() : null,
        p_change_reason: "UI:contas_pagar_receber",
      });
      if (error) throw error;

      await load();
      close();
    } catch (e: unknown) {
      setActionErr(getErrorMessage(e, "Erro ao aprovar."));
    } finally {
      setActionBusy(false);
    }
  }, [close, load, motivoId, motivoOutrosText, osId, selected, selectedMotivo, supabase]);

  const doMov = useCallback(
    async (mode: "PAGAR" | "RECEBER") => {
      if (!selected) return;
      if (mode === "PAGAR" && selected.kind !== "AP") return;
      if (mode === "RECEBER" && selected.kind !== "AR") return;

      const parsed = parseMoneyBR(valorMov);
      if (!Number.isFinite(parsed) || parsed <= 0) {
        setActionErr("Informe um valor válido.");
        return;
      }
      if (parsed > selected.valorAberto + 1e-9) {
        setActionErr("Valor maior que o saldo em aberto.");
        return;
      }
      if (!contaBancariaId) {
        setActionErr("Selecione a conta bancária.");
        return;
      }
      if (!dataPagamento) {
        setActionErr("Informe a data.");
        return;
      }

      setActionBusy(true);
      setActionErr(null);
      try {
        const rpcName = mode === "PAGAR" ? "registrar_pagamento_ap" : "registrar_recebimento_ar";
        const { error } = await supabase.schema("f").rpc(rpcName, {
          p_titulo_id: selected.tituloId,
          p_conta_bancaria_id: contaBancariaId,
          p_data_pagamento: dataPagamento,
          p_forma_pagamento: formaPagamento,
          p_valor: parsed,
          p_observacoes: observacoes.trim() ? observacoes.trim() : null,
          p_change_reason: "UI:contas_pagar_receber",
        });
        if (error) throw error;

        await load();
        close();
      } catch (e: unknown) {
        setActionErr(getErrorMessage(e, mode === "PAGAR" ? "Erro ao pagar." : "Erro ao receber."));
      } finally {
        setActionBusy(false);
      }
    },
    [close, contaBancariaId, dataPagamento, formaPagamento, load, observacoes, selected, valorMov, supabase]
  );

  if (!canFinanceiro) {
    return <div className="text-sm text-zinc-300">Sem permissão financeira.</div>;
  }

  const now = new Date();
  const years = buildYearOptions(now.getFullYear(), 5);

  return (
    <div className="space-y-4">
      <div className="flex flex-col md:flex-row md:items-end gap-3 md:gap-4">
        <div className="flex items-center gap-2">
          <div className="text-sm text-zinc-300">Vencimento</div>
          <select
            aria-label="Ano"
            value={String(year)}
            onChange={(e) => {
              setOnlyToday(false);
              setYear(Number(e.target.value));
            }}
            className="bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
          >
            {years.map((y) => (
              <option key={y} value={String(y)}>
                {y}
              </option>
            ))}
          </select>
          <select
            aria-label="Mês"
            value={String(monthNum)}
            onChange={(e) => {
              setOnlyToday(false);
              setMonthNum(Number(e.target.value));
            }}
            className="bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
          >
            {Array.from({ length: 12 }).map((_, i) => {
              const m = i + 1;
              return (
                <option key={m} value={String(m)}>
                  {pad2(m)}
                </option>
              );
            })}
          </select>
        </div>

        <div className="flex items-center gap-2">
          <div className="text-sm text-zinc-300">Tipo</div>
          <select
            aria-label="Tipo"
            value={only}
            onChange={(e) => setOnly(e.target.value as "ALL" | Kind)}
            className="bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
          >
            <option value="ALL">AP + AR</option>
            <option value="AP">AP (pagar)</option>
            <option value="AR">AR (receber)</option>
          </select>
        </div>

        <div className="flex-1">
          <div className="text-sm text-zinc-300">Buscar</div>
          <input
            aria-label="Buscar"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Fornecedor/Cliente, motivo, descrição..."
            className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
          />
        </div>

        <button
          type="button"
          onClick={() => load()}
          className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
        >
          Atualizar
        </button>

        <button
          type="button"
          onClick={() => {
            const d = new Date();
            setYear(d.getFullYear());
            setMonthNum(d.getMonth() + 1);
            setOnlyToday((s) => !s);
          }}
          className={
            onlyToday
              ? "px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
              : "px-3 py-2 rounded-md border border-zinc-800 text-zinc-100 hover:bg-zinc-900 text-sm font-medium"
          }
        >
          Hoje
        </button>

        {only !== "AR" && (
          <button
            type="button"
            onClick={() => void openCreate()}
            className="px-3 py-2 rounded-md border border-zinc-800 text-zinc-100 hover:bg-zinc-900 text-sm font-medium"
          >
            Novo AP (manual)
          </button>
        )}
      </div>

      <div className="flex flex-wrap gap-3 text-sm text-zinc-300">
        <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950/60">
          <div className="text-xs text-zinc-400">AP em aberto</div>
          <div className="font-medium text-zinc-100">{formatMoneyBR(totals.sumAP)}</div>
        </div>
        <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950/60">
          <div className="text-xs text-zinc-400">AR em aberto</div>
          <div className="font-medium text-zinc-100">{formatMoneyBR(totals.sumAR)}</div>
        </div>
      </div>

      {error && <div className="text-sm text-red-300">{error}</div>}
      {loading && <div className="text-sm text-zinc-400">Carregando...</div>}

      <div className="w-full overflow-x-auto rounded-md border border-zinc-800">
        <table className="w-full min-w-full text-sm">
          <thead className="bg-zinc-950/80">
            <tr className="text-left text-zinc-300">
              <th className="px-3 py-2">Tipo</th>
              <th className="px-3 py-2">Pessoa</th>
              <th className="px-3 py-2">Motivo</th>
              <th className="px-3 py-2">Aprovado por</th>
              <th className="px-3 py-2">Parcela</th>
              <th className="px-3 py-2">Emissão</th>
              <th className="px-3 py-2">Vencimento</th>
              <th className="px-3 py-2 text-right">Valor</th>
              <th className="px-3 py-2 text-right">Aberto</th>
              <th className="px-3 py-2">Status</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((r) => {
              const badge = statusBadge(r);
              const tint = r.kind === "AR" ? "bg-emerald-900/5" : "bg-red-900/5";
              return (
                <tr
                  key={`${r.kind}:${r.parcelaId}`}
                  className={`border-t border-zinc-800 hover:bg-zinc-900/40 cursor-pointer ${tint}`}
                  onClick={() => open(r)}
                >
                  <td className="px-3 py-2 font-medium text-zinc-100">{r.kind}</td>
                  <td className="px-3 py-2 text-zinc-200">{r.pessoaNome}</td>
                  <td className="px-3 py-2 text-zinc-200">{r.kind === "AP" ? r.motivoNome ?? "-" : "-"}</td>
                  <td className="px-3 py-2 text-zinc-200">{r.kind === "AP" ? r.aprovadoPorNome ?? "-" : "-"}</td>
                  <td className="px-3 py-2 text-zinc-200">{fmtParcela(r.parcelaNumero)}</td>
                  <td className="px-3 py-2 text-zinc-200">{r.emissao ? formatDateBR(r.emissao) : "-"}</td>
                  <td className="px-3 py-2 text-zinc-200">{r.vencimento}</td>
                  <td className="px-3 py-2 text-right text-zinc-200">{formatMoneyBR(r.valor)}</td>
                  <td className="px-3 py-2 text-right text-zinc-200">{formatMoneyBR(r.valorAberto)}</td>
                  <td className="px-3 py-2">
                    <span className={`inline-flex items-center px-2 py-1 rounded-md text-xs ${badge.className}`}>
                      {badge.label}
                    </span>
                  </td>
                </tr>
              );
            })}
            {!filtered.length && !loading && (
              <tr>
                <td colSpan={10} className="px-3 py-6 text-center text-zinc-400">
                  Nenhum item neste período.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {selected && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60" onClick={close} />
          <div className="relative w-full max-w-2xl rounded-lg border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-sm text-zinc-400">{selected.kind === "AP" ? "Conta a pagar" : "Conta a receber"}</div>
                <div className="text-lg font-semibold text-zinc-100">{selected.pessoaNome}</div>
                <div className="text-sm text-zinc-400">
                  {fmtParcela(selected.parcelaNumero)} • Venc: {selected.vencimento} • Aberto: {formatMoneyBR(selected.valorAberto)}
                </div>
                {selected.kind === "AP" && (
                  <div className="text-sm text-zinc-400">
                    Emissão: {selected.emissao ? formatDateBR(selected.emissao) : tituloMeta?.emissaoDate ? formatDateBR(tituloMeta.emissaoDate) : "-"}
                  </div>
                )}
                {selected.kind === "AP" && (
                  <div className="text-sm text-zinc-400">Motivo: {selected.motivoNome ?? "-"}</div>
                )}
                {selected.kind === "AR" && selected.descricao && (
                  <div className="text-sm text-zinc-400">{selected.descricao}</div>
                )}
              </div>
              <button
                type="button"
                onClick={close}
                className="px-2 py-1 rounded-md border border-zinc-800 text-zinc-200 hover:bg-zinc-900"
              >
                Fechar
              </button>
            </div>

            <div className="mt-4 flex items-center gap-2">
              {selected.kind === "AP" ? (
                <>
                  <button
                    type="button"
                    onClick={() => setTab("APROVAR")}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "APROVAR" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Aprovar
                  </button>
                  <button
                    type="button"
                    onClick={() => setTab("PAGAR")}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "PAGAR" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Pagar
                  </button>
                </>
              ) : (
                <button
                  type="button"
                  onClick={() => setTab("RECEBER")}
                  className={`px-3 py-1.5 rounded-md text-sm border ${
                    tab === "RECEBER" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                  }`}
                >
                  Receber
                </button>
              )}
            </div>

            <div className="mt-4 space-y-3">
              <FormError message={actionErr} />

              {selected.kind === "AP" && (
                <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex-1">
                      <div className="text-sm text-zinc-300">Data da NF (Emissão)</div>
                      <input
                        aria-label="Data da NF (Emissão)"
                        type="date"
                        value={editEmissaoDate}
                        onChange={(e) => setEditEmissaoDate(e.target.value)}
                        disabled={
                          emissaoBusy ||
                          !tituloMeta ||
                          (tituloMeta.documentoFiscalId !== null && tituloMeta.documentoFiscalId !== "")
                        }
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100 disabled:opacity-60"
                      />
                      <div className="text-xs text-zinc-500 mt-1">Data da nota/serviço, usada para competência.</div>
                      {(tituloMeta?.documentoFiscalId ?? null) !== null && (
                        <div className="text-xs text-zinc-500 mt-1">Importado por XML: emissão é somente leitura.</div>
                      )}
                      {!tituloMeta && (
                        <div className="text-xs text-zinc-500 mt-1">Carregando origem do título...</div>
                      )}
                      <FormError message={emissaoErr} />
                    </div>
                    {tituloMeta && tituloMeta.documentoFiscalId === null && (
                      <button
                        type="button"
                        disabled={emissaoBusy || !editEmissaoDate || editEmissaoDate === (tituloMeta?.emissaoDate ?? selected.emissao ?? "")}
                        onClick={() => void doUpdateEmissaoDate()}
                        className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                      >
                        {emissaoBusy ? "Salvando..." : "Salvar emissão"}
                      </button>
                    )}
                  </div>
                </div>
              )}

              {tab === "APROVAR" && selected.kind === "AP" && (
                <div className="space-y-3">
                  <div>
                    <div className="text-sm text-zinc-300">Motivo</div>
                    <select
                      aria-label="Motivo"
                      value={motivoId}
                      onChange={(e) => setMotivoId(e.target.value)}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    >
                      <option value="">Selecione...</option>
                      {motivos.map((m) => (
                        <option key={m.id} value={m.id}>
                          {m.codigo} - {m.nome}
                        </option>
                      ))}
                    </select>
                  </div>

                  {selectedMotivo?.requires_os && (
                    <div>
                      <div className="text-sm text-zinc-300">OS</div>
                      <input
                        aria-label="OS"
                        value={osId}
                        onChange={(e) => setOsId(e.target.value)}
                        placeholder="Ex: 1234"
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                  )}

                  {selectedMotivo?.requires_text && (
                    <div>
                      <div className="text-sm text-zinc-300">Motivo (texto)</div>
                      <input
                        aria-label="Motivo texto"
                        value={motivoOutrosText}
                        onChange={(e) => setMotivoOutrosText(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                  )}

                  <div className="flex justify-end">
                    <button
                      type="button"
                      disabled={actionBusy}
                      onClick={doAprovar}
                      className="px-3 py-2 rounded-md bg-emerald-500 text-zinc-950 hover:bg-emerald-400 text-sm font-medium disabled:opacity-60"
                    >
                      {actionBusy ? "Aprovando..." : "Confirmar aprovação"}
                    </button>
                  </div>
                </div>
              )}

              {(tab === "PAGAR" || tab === "RECEBER") && (
                <div className="space-y-3">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <div className="text-sm text-zinc-300">Conta bancária</div>
                      <select
                        aria-label="Conta bancária"
                        value={contaBancariaId}
                        onChange={(e) => setContaBancariaId(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      >
                        <option value="">Selecione...</option>
                        {contas.map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.codigo} - {c.nome}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div>
                      <div className="text-sm text-zinc-300">Data</div>
                      <input
                        aria-label="Data"
                        type="date"
                        value={dataPagamento}
                        onChange={(e) => setDataPagamento(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <div className="text-sm text-zinc-300">Forma</div>
                      <select
                        aria-label="Forma"
                        value={formaPagamento}
                        onChange={(e) => setFormaPagamento(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      >
                        <option value="PIX">PIX</option>
                        <option value="TRANSFERENCIA">TRANSFERÊNCIA</option>
                        <option value="BOLETO">BOLETO</option>
                        <option value="DINHEIRO">DINHEIRO</option>
                        <option value="CARTAO">CARTÃO</option>
                        <option value="OUTROS">OUTROS</option>
                      </select>
                    </div>

                    <div>
                      <div className="text-sm text-zinc-300">Valor</div>
                      <input
                        aria-label="Valor"
                        value={valorMov}
                        onChange={(e) => setValorMov(e.target.value)}
                        placeholder={formatMoneyBR(selected.valorAberto)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                      <div className="text-xs text-zinc-500 mt-1">Dica: aceita &quot;1234,56&quot; ou &quot;R$ 1.234,56&quot;</div>
                    </div>
                  </div>

                  <div>
                    <div className="text-sm text-zinc-300">Observações</div>
                    <input
                      aria-label="Observações"
                      value={observacoes}
                      onChange={(e) => setObservacoes(e.target.value)}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    />
                  </div>

                  <div className="flex justify-end">
                    {tab === "PAGAR" && (
                      <button
                        type="button"
                        disabled={actionBusy}
                        onClick={() => doMov("PAGAR")}
                        className="px-3 py-2 rounded-md bg-red-500 text-zinc-950 hover:bg-red-400 text-sm font-medium disabled:opacity-60"
                      >
                        {actionBusy ? "Pagando..." : "Confirmar pagamento"}
                      </button>
                    )}
                    {tab === "RECEBER" && (
                      <button
                        type="button"
                        disabled={actionBusy}
                        onClick={() => doMov("RECEBER")}
                        className="px-3 py-2 rounded-md bg-emerald-500 text-zinc-950 hover:bg-emerald-400 text-sm font-medium disabled:opacity-60"
                      >
                        {actionBusy ? "Recebendo..." : "Confirmar recebimento"}
                      </button>
                    )}
                  </div>
                </div>
              )}

              {!!aplicacoes.length && (
                <div className="border-t border-zinc-800 pt-3">
                  <div className="text-sm text-zinc-300 mb-2">Movimentos desta parcela</div>
                  <div className="space-y-2">
                    {aplicacoes.map((a) => {
                      const conta = contas.find((c) => c.id === a.pagamento.conta_bancaria_id) ?? null;
                      return (
                        <div
                          key={`${a.pagamento.id}:${a.pagamento.data_pagamento}:${a.valor}`}
                          className="text-sm text-zinc-300"
                        >
                          <span className="text-zinc-100 font-medium">{formatMoneyBR(Number(a.valor ?? 0))}</span>
                          <span className="text-zinc-500"> • </span>
                          <span>{a.pagamento.data_pagamento}</span>
                          <span className="text-zinc-500"> • </span>
                          <span>{a.pagamento.forma_pagamento}</span>
                          <span className="text-zinc-500"> • </span>
                          <span>{conta ? `${conta.codigo} - ${conta.nome}` : a.pagamento.conta_bancaria_id}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {createOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60" onClick={closeCreate} />
          <div className="relative w-full max-w-2xl rounded-lg border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-sm text-zinc-400">Conta a pagar</div>
                <div className="text-lg font-semibold text-zinc-100">Novo AP (manual)</div>
                <div className="text-sm text-zinc-400">Para energia, água, aluguel, etc (sem XML).</div>
              </div>
              <button
                type="button"
                onClick={closeCreate}
                className="px-2 py-1 rounded-md border border-zinc-800 text-zinc-200 hover:bg-zinc-900"
              >
                Fechar
              </button>
            </div>

            <div className="mt-4 space-y-3">
              <FormError message={createErr} />

              <div>
                <div className="text-sm text-zinc-300">Fornecedor (opcional)</div>
                <select
                  aria-label="Fornecedor"
                  value={newFornecedorId}
                  onChange={(e) => setNewFornecedorId(e.target.value)}
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                >
                  <option value="">Sem fornecedor</option>
                  {fornecedores.map((f) => (
                    <option key={f.id} value={String(f.id)}>
                      {f.nome}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <div className="text-sm text-zinc-300">Descrição</div>
                <input
                  aria-label="Descrição"
                  value={newDescricao}
                  onChange={(e) => setNewDescricao(e.target.value)}
                  placeholder="Ex: Energia - ENEL"
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <div className="text-sm text-zinc-300">Data da NF (Emissão)</div>
                  <input
                    aria-label="Data da NF (Emissão)"
                    type="date"
                    value={newEmissaoDate}
                    onChange={(e) => setNewEmissaoDate(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                  />
                  <div className="text-xs text-zinc-500 mt-1">Data da nota/serviço, usada para competência.</div>
                </div>
                <div>
                  <div className="text-sm text-zinc-300">Vencimento</div>
                  <input
                    aria-label="Vencimento"
                    type="date"
                    value={newVencimento}
                    onChange={(e) => setNewVencimento(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <div className="text-sm text-zinc-300">Valor</div>
                  <input
                    aria-label="Valor"
                    value={newValor}
                    onChange={(e) => setNewValor(e.target.value)}
                    placeholder='Ex: 450,00'
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                  />
                </div>
              </div>

              <div>
                <div className="text-sm text-zinc-300">Motivo (opcional)</div>
                <select
                  aria-label="Motivo"
                  value={newMotivoId}
                  onChange={(e) => setNewMotivoId(e.target.value)}
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                >
                  <option value="">Sem motivo</option>
                  {motivos.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.codigo} - {m.nome}
                    </option>
                  ))}
                </select>
              </div>

              <div className="flex items-center gap-2">
                <input
                  id="ap-recorrente"
                  type="checkbox"
                  checked={newRecorrente}
                  onChange={(e) => setNewRecorrente(e.target.checked)}
                />
                <label htmlFor="ap-recorrente" className="text-sm text-zinc-200">
                  É recorrente (provisionar próximos meses)
                </label>
              </div>

              {newRecorrente && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div>
                    <div className="text-sm text-zinc-300">Provisionar quantos meses</div>
                    <input
                      aria-label="Meses"
                      type="number"
                      min={0}
                      max={60}
                      value={String(newProvisionarMeses)}
                      onChange={(e) => setNewProvisionarMeses(Number(e.target.value))}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    />
                    <div className="text-xs text-zinc-500 mt-1">Dica: ele copia o valor do mês anterior por padrão.</div>
                  </div>
                </div>
              )}

              <div className="flex justify-end">
                <button
                  type="button"
                  disabled={createBusy}
                  onClick={() => void doCreateAp()}
                  className="px-3 py-2 rounded-md bg-emerald-500 text-zinc-950 hover:bg-emerald-400 text-sm font-medium disabled:opacity-60"
                >
                  {createBusy ? "Salvando..." : "Criar"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
