"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatDecimalBR, parseDecimalBR } from "../../lib/decimal";
import { supabaseBrowser } from "../../lib/supabase/client";
import { gerarRelatorioEstoque } from "../../lib/pdf/relatorioEstoque";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { useIsAdminTenant } from "@/lib/auth/useIsAdminTenant";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";

type EstoqueRow = {
  id: number;
  item_id: number;
  quantidade_atual: number;
  atualizado_em: string;
  localizacao: string | null;
  itens: {
    codigo_interno: string;
    codigo_barras: string | null;
    nome: string;
    tipo: string;
    unidade_medida: string | null;
    controla_estoque: boolean | null;
    estoque_minimo: number | null;
    estoque_ideal: number | null;
    estoque_maximo: number | null;
    ativo: boolean;
    fornecedor_id: number | null;
    fornecedores?: { nome: string | null } | null;
  } | null;
};

type EstoqueBaseRow = Omit<EstoqueRow, "itens">;
type EstoqueJoinRow = EstoqueBaseRow;
type EstoqueItemRow = NonNullable<EstoqueRow["itens"]> & { id: number; estoque?: EstoqueJoinRow[] | null };

type Fornecedor = { id: number; nome: string; ativo: boolean };

type Filtros = {
  id: string;
  codigo: string;
  produto: string;
  fornecedor: string;
  ativos: "ativos" | "todos";
  abaixoMinimo: boolean;
};

function getFiltrosIniciais(): Filtros {
  return {
    id: "",
    codigo: "",
    produto: "",
    fornecedor: "",
    ativos: "ativos",
    abaixoMinimo: false,
  };
}

export default function EstoquePage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId, loading: tenantEmpresaLoading, error: tenantEmpresaError } = useTenantEmpresa();
  const { isAdmin: isAdminTenant, loading: adminTenantLoading } = useIsAdminTenant();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("estoque.read");
  const canAdjust = has("estoque.write");

  const [rows, setRows] = useState<EstoqueRow[]>([]);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const filtrosFormRef = useRef<HTMLFormElement | null>(null);
  const codigoInputRef = useRef<HTMLInputElement | null>(null);

  const [draftFiltros, setDraftFiltros] = useState<Filtros>(getFiltrosIniciais);
  const [filtros, setFiltros] = useState<Filtros>(getFiltrosIniciais);

  const [showAjuste, setShowAjuste] = useState(false);
  const [ajusteItemIdText, setAjusteItemIdText] = useState<string>("");
  const [ajusteSaldoText, setAjusteSaldoText] = useState<string>("");
  const [ajusteMinText, setAjusteMinText] = useState<string>("");
  const [ajusteMaxText, setAjusteMaxText] = useState<string>("");
  const [ajusteDescricao, setAjusteDescricao] = useState<string>("");

  const ajusteItemIdRef = useRef<HTMLInputElement | null>(null);
  const ajusteSaldoRef = useRef<HTMLInputElement | null>(null);
  const ajusteMinRef = useRef<HTMLInputElement | null>(null);
  const ajusteMaxRef = useRef<HTMLInputElement | null>(null);

  const [showZeraEstoque, setShowZeraEstoque] = useState(false);
  const [zeraFornecedorId, setZeraFornecedorId] = useState<string>("");
  const zeraFornecedorRef = useRef<HTMLSelectElement | null>(null);
  const [page, setPage] = useState(0);
  const pageSize = 250;
  const [totalCount, setTotalCount] = useState<number | null>(null);

  const calcIdeal = useCallback((min: number, max: number) => {
    const a = Number.isFinite(min) ? Number(min) : 0;
    const b = Number.isFinite(max) ? Number(max) : 0;
    return Math.floor((a + b) / 2);
  }, []);

  const itensSelect = useMemo(
    () =>
      "id,codigo_interno,codigo_barras,nome,tipo,unidade_medida,controla_estoque,estoque_minimo,estoque_ideal,estoque_maximo,ativo,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome),estoque!estoque_item_id_fkey(id,item_id,quantidade_atual,atualizado_em,localizacao)",
    []
  );

  const mapItemToEstoqueRow = useCallback((item: EstoqueItemRow): EstoqueRow | null => {
    const estoqueRows = Array.isArray(item.estoque) ? item.estoque : [];
    const { estoque, ...itens } = item;
    void estoque;

    const quantidadeTotal = estoqueRows.reduce(
      (acc, r) => acc + Number((r as unknown as { quantidade_atual?: unknown })?.quantidade_atual ?? 0),
      0
    );

    const atualizadoEm = estoqueRows
      .map((r) => String((r as unknown as { atualizado_em?: unknown })?.atualizado_em ?? ""))
      .filter(Boolean)
      .sort()
      .at(-1);

    return {
      // Use item id as stable row id (estoque may have multiple rows per item).
      id: item.id,
      item_id: item.id,
      quantidade_atual: Number(quantidadeTotal ?? 0),
      atualizado_em: atualizadoEm || new Date(0).toISOString(),
      localizacao: null,
      itens,
    };
  }, []);

  const loadFornecedores = useCallback(async () => {
    if (tenantEmpresaLoading) return;
    if (!tenantId) return;

    const { data, error } = await applyTenant(
      supabase.from("fornecedores").select("id,nome,ativo"),
      tenantId
    )
      .eq("ativo", true)
      .order("nome", { ascending: true })
      .limit(1000);

    if (!error) setFornecedores((data ?? []) as unknown as Fornecedor[]);
  }, [supabase, tenantEmpresaLoading, tenantId]);

  function fornecedorNomeById(id: number | null | undefined) {
    const parsed = Number(id ?? NaN);
    if (!Number.isFinite(parsed)) return null;
    const nome = fornecedores.find((f) => f.id === parsed)?.nome ?? null;
    const trimmed = String(nome ?? "").trim();
    return trimmed ? trimmed : `#${parsed}`;
  }

  async function aplicarAjusteInline(itemId: number, novoSaldo: number) {
    setOk(null);
    setErr(null);
    if (!canAdjust) return setErr("Sem permissao para ajustar estoque.");
    if (!Number.isFinite(novoSaldo)) return setErr("Quantidade inválida.");
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return setErr("Tenant ou empresa nao carregados.");

    const atualRow = rows.find((r) => r.item_id === itemId);
    const saldoAtual = Number(atualRow?.quantidade_atual ?? 0);
    const diff = Number(novoSaldo) - saldoAtual;
    if (diff === 0) return;

    setBusy(true);
    try {
      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      const tipoMov = diff > 0 ? "entrada" : "saida";
      const qtdMov = Math.abs(diff);

      const { error } = await supabase.from("movimentacoes").insert({
        tenant_id: tenantId,
        empresa_id: empresaId,
        item_id: itemId,
        tipo: tipoMov,
        quantidade: qtdMov,
        motivo: `Ajuste rápido (inline) (ajuste para ${Number(novoSaldo)})`,
        realizado_por: userEmail,
        data_movimentacao: new Date().toISOString(),
      });
      if (error) return setErr(error.message);

      setOk(`Saldo atualizado: ${saldoAtual} -> ${Number(novoSaldo)}`);
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function salvarLimitesInline(itemId: number, min: number, max: number) {
    setOk(null);
    setErr(null);
    if (!canAdjust) return setErr("Sem permissao para ajustar estoque.");
    if (!tenantId || !empresaId) return setErr("Tenant ou empresa nao carregados.");
    if (!Number.isFinite(min) || !Number.isFinite(max)) return setErr("Valor inválido.");

    const ideal = calcIdeal(min, max);
    setBusy(true);
    try {
      const { error } = await applyTenantEmpresa(
        supabase.from("itens").update({
          estoque_minimo: min,
          estoque_maximo: max,
          estoque_ideal: ideal,
        }),
        tenantId,
        empresaId
      ).eq("id", itemId);
      if (error) return setErr(error.message);
      setOk("Limites atualizados.");
      await load();
    } finally {
      setBusy(false);
    }
  }

  function resetAjuste() {
    setAjusteItemIdText("");
    setAjusteSaldoText("");
    setAjusteMinText("");
    setAjusteMaxText("");
    setAjusteDescricao("");
  }

  function closeAjusteAndFocusCodigo() {
    setShowAjuste(false);
    resetAjuste();
    setTimeout(() => {
      codigoInputRef.current?.focus();
      codigoInputRef.current?.select?.();
    }, 0);
  }

  function focusAjusteId() {
    setTimeout(() => {
      ajusteItemIdRef.current?.focus();
      ajusteItemIdRef.current?.select?.();
    }, 0);
  }

  function closeZeraEstoqueAndFocusCodigo() {
    setShowZeraEstoque(false);
    setZeraFornecedorId("");
    setTimeout(() => {
      codigoInputRef.current?.focus();
      codigoInputRef.current?.select?.();
    }, 0);
  }

  async function zerarEstoqueFornecedorSelecionado() {
    setOk(null);
    setErr(null);

    if (!canAdjust) return setErr("Sem permissao para ajustar estoque.");
    if (adminTenantLoading) return;
    if (!isAdminTenant) return setErr("Apenas admin pode zerar estoque.");

    const fornecedorId = Number(String(zeraFornecedorId ?? "").trim());
    if (!Number.isInteger(fornecedorId) || fornecedorId <= 0) return setErr("Selecione um fornecedor valido.");
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return setErr("Tenant ou empresa nao carregados.");

    setBusy(true);
    try {
      const fornecedorNome = fornecedorNomeById(fornecedorId) ?? `#${fornecedorId}`;
      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      const all: EstoqueItemRow[] = [];
      const chunkSize = 1000;
      let offset = 0;
      while (true) {
        const qb = applyTenantEmpresa(supabase.from("itens").select(itensSelect), tenantId, empresaId)
          .eq("tipo", "produto")
          .eq("controla_estoque", true)
          .eq("fornecedor_id", fornecedorId)
          .order("id", { ascending: false })
          .range(offset, offset + chunkSize - 1);

        const { data, error } = await qb;
        if (error) return setErr(error.message);

        const typed = (data ?? []) as unknown as EstoqueItemRow[];
        all.push(...typed);
        if (typed.length < chunkSize) break;
        offset += chunkSize;
      }

      const estoqueRows = all.map(mapItemToEstoqueRow).filter(Boolean) as EstoqueRow[];

      const movimentos = estoqueRows
        .map((r) => {
          const saldoAtual = Number(r.quantidade_atual ?? 0);
          if (!Number.isFinite(saldoAtual)) return null;
          if (Math.abs(saldoAtual) < 1e-12) return null;
          const tipo = saldoAtual > 0 ? "saida" : "entrada";
          return {
            tenant_id: tenantId,
            empresa_id: empresaId,
            item_id: r.item_id,
            tipo,
            quantidade: Math.abs(saldoAtual),
            motivo: `Zera estoque (fornecedor ${fornecedorNome})`,
            realizado_por: userEmail,
            data_movimentacao: new Date().toISOString(),
          };
        })
        .filter(Boolean) as Array<Record<string, unknown>>;

      if (movimentos.length === 0) {
        setOk(`Nenhum item com saldo para zerar (${fornecedorNome}).`);
        closeZeraEstoqueAndFocusCodigo();
        return;
      }

      const insertChunkSize = 500;
      for (let i = 0; i < movimentos.length; i += insertChunkSize) {
        const chunk = movimentos.slice(i, i + insertChunkSize);
        const { error } = await supabase.from("movimentacoes").insert(chunk);
        if (error) return setErr(error.message);
      }

      setOk(`Estoque zerado para ${fornecedorNome}. Itens ajustados: ${movimentos.length}.`);
      closeZeraEstoqueAndFocusCodigo();
      await load();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao zerar estoque.";
      setErr(msg);
    } finally {
      setBusy(false);
    }
  }

  async function fetchAjusteContext(itemId: number) {
    if (tenantEmpresaLoading) return null;
    if (!tenantId || !empresaId) {
      setErr("Tenant ou empresa nao carregados.");
      return null;
    }

    const { data, error } = await applyTenantEmpresa(supabase.from("itens").select(itensSelect), tenantId, empresaId)
      .eq("tipo", "produto")
      .eq("controla_estoque", true)
      .eq("id", itemId)
      .maybeSingle();

    if (error) {
      setErr(error.message);
      return null;
    }
    if (!data) {
      setErr("Item nao encontrado no estoque.");
      return null;
    }

    const row = mapItemToEstoqueRow(data as unknown as EstoqueItemRow);
    if (!row) {
      setErr("Item sem estoque vinculado.");
      return null;
    }

    return {
      saldoAtual: Number(row.quantidade_atual ?? 0),
      min: Number(row.itens?.estoque_minimo ?? 0),
      max: Number(row.itens?.estoque_maximo ?? 0),
      descricao: String(row.itens?.nome ?? "").trim(),
    };
  }

  async function preencherAjustePorId(itemId: number) {
    setErr(null);
    setOk(null);
    const ctx = await fetchAjusteContext(itemId);
    if (!ctx) return false;
    setAjusteDescricao(ctx.descricao || "Sem descricao");
    setAjusteSaldoText(formatDecimalBR(ctx.saldoAtual, 3));
    setAjusteMinText(formatDecimalBR(ctx.min, 3));
    setAjusteMaxText(formatDecimalBR(ctx.max, 3));
    return true;
  }

  async function salvarAjusteRapido() {
    setOk(null);
    setErr(null);
    if (!canAdjust) return setErr("Sem permissao para ajustar estoque.");

    const idParsed = Number(String(ajusteItemIdText ?? "").trim());
    if (!Number.isInteger(idParsed) || idParsed <= 0) return setErr("Informe um ID de item valido.");

    const saldoParsed = parseDecimalBR(ajusteSaldoText);
    const minParsed = parseDecimalBR(ajusteMinText);
    const maxParsed = parseDecimalBR(ajusteMaxText);
    if (saldoParsed == null || !Number.isFinite(saldoParsed)) return setErr("Saldo invalido.");
    if (minParsed == null || !Number.isFinite(minParsed)) return setErr("Minimo invalido.");
    if (maxParsed == null || !Number.isFinite(maxParsed)) return setErr("Maximo invalido.");

    const novoSaldo = Number(saldoParsed);
    const novoMin = Number(minParsed);
    const novoMax = Number(maxParsed);

    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return setErr("Tenant ou empresa nao carregados.");

    setBusy(true);
    try {
      const ctx = await fetchAjusteContext(idParsed);
      if (!ctx) return;

      const diff = novoSaldo - ctx.saldoAtual;
      if (diff !== 0) {
        const { data: sess } = await supabase.auth.getSession();
        const userEmail = sess.session?.user?.email ?? null;

        const tipoMov = diff > 0 ? "entrada" : "saida";
        const qtdMov = Math.abs(diff);

        const { error } = await supabase.from("movimentacoes").insert({
          tenant_id: tenantId,
          empresa_id: empresaId,
          item_id: idParsed,
          tipo: tipoMov,
          quantidade: qtdMov,
          motivo: `Ajuste estoque (ajuste para ${novoSaldo})`,
          realizado_por: userEmail,
          data_movimentacao: new Date().toISOString(),
        });
        if (error) return setErr(error.message);
      }

      const ideal = calcIdeal(novoMin, novoMax);
      const { error: limErr } = await applyTenantEmpresa(
        supabase.from("itens").update({
          estoque_minimo: novoMin,
          estoque_maximo: novoMax,
          estoque_ideal: ideal,
        }),
        tenantId,
        empresaId
      ).eq("id", idParsed);
      if (limErr) return setErr(limErr.message);

      setOk(`Ajuste salvo. Saldo: ${ctx.saldoAtual} -> ${novoSaldo}`);
      // Não fecha o popup após salvar; volta o foco para o ID para facilitar o próximo ajuste.
      focusAjusteId();
      await load();
    } finally {
      setBusy(false);
    }
  }

  function InlineNumberInput(props: {
    ariaLabel: string;
    value: number;
    decimals?: number;
    disabled?: boolean;
    placeholder?: string;
    onCommit: (v: number) => void | Promise<void>;
  }) {
    const { ariaLabel, value, decimals = 3, disabled, placeholder, onCommit } = props;
    const [text, setText] = useState<string>(formatDecimalBR(Number(value ?? 0), decimals));

    useEffect(() => {
      setText(formatDecimalBR(Number(value ?? 0), decimals));
    }, [value, decimals]);

    const commit = async () => {
      const parsed = parseDecimalBR(text);
      if (parsed == null || !Number.isFinite(parsed)) {
        setText(formatDecimalBR(Number(value ?? 0), decimals));
        return;
      }
      const next = Number(parsed);
      const prev = Number(value ?? 0);
      if (Math.abs(next - prev) < 1e-12) return;
      await onCommit(next);
    };

    return (
      <input
        aria-label={ariaLabel}
        type="text"
        inputMode="decimal"
        className="w-full px-2 py-1 rounded-md border border-zinc-700 bg-zinc-900/40 text-right tabular-nums"
        value={text}
        placeholder={placeholder}
        disabled={disabled}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            void commit();
          }
          if (e.key === "Escape") {
            e.preventDefault();
            setText(formatDecimalBR(Number(value ?? 0), decimals));
          }
        }}
        onBlur={() => {
          setText((prev) => {
            const parsed = parseDecimalBR(prev);
            if (parsed == null || !Number.isFinite(parsed)) return formatDecimalBR(Number(value ?? 0), decimals);
            return formatDecimalBR(Number(parsed), decimals);
          });
        }}
      />
    );
  }

  /* async function loadOld() {
    setErr(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      // Contexto ainda não disponível (sem tenant/empresa selecionados).
      // Não faz query e não exibe erro genérico.
      setRows([]);
      setTotalCount(null);
      return;
    }

    const query = applyTenantEmpresa(
      supabase.from("estoque").select("id,item_id,quantidade_atual,atualizado_em,localizacao", { count: "exact" }),
      tenantId,
      empresaId
    )
      .order("id", { ascending: false })
      .range(page * pageSize, page * pageSize + pageSize - 1);

    const { data, error, count } = await query;
    if (error) return setErr(error.message);
    setTotalCount(typeof count === "number" ? count : null);

    const estoqueRows = (data ?? []) as unknown as EstoqueBaseRow[];
    const itemIds = Array.from(new Set(estoqueRows.map((row) => row.item_id).filter(Number.isFinite)));
    const itensMap = new Map<number, EstoqueRow["itens"]>();

    if (itemIds.length > 0) {
      const { data: itensData, error: itensErr } = await applyTenantEmpresa(
        supabase
          .from("itens")
          .select(
            "id,codigo_interno,codigo_barras,nome,tipo,unidade_medida,controla_estoque,estoque_minimo,estoque_ideal,estoque_maximo,ativo,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)"
          ),
        tenantId,
        empresaId
      ).in("id", itemIds);
      if (itensErr) return setErr(itensErr.message);
      const typedItens = (itensData ?? []) as unknown as EstoqueItemRow[];
      typedItens.forEach((item) => {
        itensMap.set(item.id, item);
      });
    }

    let list: EstoqueRow[] = estoqueRows.map((row) => ({
      ...row,
      itens: itensMap.get(row.item_id) ?? null,
    }));
    list = list.filter((r) => r.itens?.tipo === "produto" && r.itens?.controla_estoque);
    if (ativos === "ativos") list = list.filter((r) => r.itens?.ativo);

    const term = q.trim().toLowerCase();
    if (term) {
      list = list.filter((r) => {
        const cod = (r.itens?.codigo_interno ?? "").toLowerCase();
        const nome = (r.itens?.nome ?? "").toLowerCase();
        return cod.includes(term) || nome.includes(term);
      });
    }

    const idTerm = codigoId.trim();
    if (idTerm) {
      list = list.filter((r) => String(r.item_id).includes(idTerm));
    }

    const fornTerm = fornecedorNome.trim().toLowerCase();
    if (fornTerm) {
      list = list.filter((r) => {
        const nomeForn = (r.itens?.fornecedores?.nome ?? "").toLowerCase();
        return nomeForn.includes(fornTerm);
      });
    }

    if (soAbaixoMin) {
      list = list.filter((r) => (r.quantidade_atual ?? 0) < Number(r.itens?.estoque_minimo ?? 0));
    }

    setRows(list);
  } */

  const load = useCallback(async () => {
    setErr(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setRows([]);
      setTotalCount(null);
      return;
    }

    const idTerm = filtros.id.trim();
    let idNumber: number | null = null;
    if (idTerm) {
      const parsed = Number(idTerm);
      if (!Number.isInteger(parsed) || parsed <= 0) {
        setRows([]);
        setTotalCount(0);
        setErr("ID invÃ¡lido. Informe um nÃºmero inteiro.");
        return;
      }
      idNumber = parsed;
    }

    const fornTerm = filtros.fornecedor.trim();

    // A RPC pagina e calcula o total no banco, sem expandir o relacionamento de
    // estoque nem executar uma contagem exata sujeita a RLS linha a linha.
    const { data, error } = await supabase.rpc("search_estoque_itens", {
      p_tenant_id: tenantId,
      p_empresa_id: empresaId,
      p_busca_geral: null,
      p_codigo: filtros.codigo.trim() || null,
      p_nome: filtros.produto.trim() || null,
      p_fornecedor: fornTerm || null,
      p_item_id: idNumber,
      p_ativo_only: filtros.ativos === "ativos",
      p_finalidade: null,
      p_abaixo_minimo: filtros.abaixoMinimo,
      p_sem_fornecedor: false,
      p_saldo_positivo: false,
      p_page: page + 1,
      p_page_size: pageSize,
      p_sort_key: "id",
      p_sort_dir: "desc",
    });
    if (error) {
      setRows([]);
      setTotalCount(0);
      setErr(error.message);
      return;
    }

    const rpcRows = Array.isArray(data) ? (data as Array<Record<string, unknown>>) : [];
    const mapped: EstoqueRow[] = rpcRows.map((row) => ({
      id: Number(row.estoque_id ?? row.item_id ?? 0),
      item_id: Number(row.item_id ?? 0),
      quantidade_atual: Number(row.quantidade_atual ?? 0),
      atualizado_em: String(row.atualizado_em ?? new Date(0).toISOString()),
      localizacao: row.localizacao == null ? null : String(row.localizacao),
      itens: {
        codigo_interno: String(row.codigo_interno ?? ""),
        codigo_barras: row.codigo_barras == null ? null : String(row.codigo_barras),
        nome: String(row.item_nome ?? ""),
        tipo: String(row.tipo ?? "produto"),
        unidade_medida: row.unidade_medida == null ? null : String(row.unidade_medida),
        controla_estoque: row.controla_estoque === true,
        estoque_minimo: row.estoque_minimo == null ? null : Number(row.estoque_minimo),
        estoque_ideal: row.estoque_ideal == null ? null : Number(row.estoque_ideal),
        estoque_maximo: row.estoque_maximo == null ? null : Number(row.estoque_maximo),
        ativo: row.ativo === true,
        fornecedor_id: row.fornecedor_id == null ? null : Number(row.fornecedor_id),
        fornecedores: row.fornecedor_nome == null ? null : { nome: String(row.fornecedor_nome) },
      },
    }));

    setRows(mapped);
    setTotalCount(rpcRows.length > 0 ? Number(rpcRows[0].total_count ?? 0) : 0);
  }, [
    empresaId,
    filtros,
    page,
    pageSize,
    supabase,
    tenantEmpresaLoading,
    tenantId,
  ]);

  function startAjuste(item_id: number) {
    setOk(null);
    setErr(null);
    setAjusteItemIdText(String(item_id));
    setShowAjuste(true);
    void preencherAjustePorId(item_id);
    setTimeout(() => {
      ajusteSaldoRef.current?.focus();
      ajusteSaldoRef.current?.select?.();
    }, 0);
  }

  useEffect(() => {
    if (!showAjuste) return;
    const t = setTimeout(() => {
      ajusteItemIdRef.current?.focus();
      ajusteItemIdRef.current?.select?.();
    }, 0);
    return () => clearTimeout(t);
  }, [showAjuste]);

  useEffect(() => {
    if (!showZeraEstoque) return;
    const t = setTimeout(() => {
      zeraFornecedorRef.current?.focus();
    }, 0);
    return () => clearTimeout(t);
  }, [showZeraEstoque]);

  useEffect(() => {
    const t = setTimeout(() => {
      void load();
    }, 0);
    return () => clearTimeout(t);
  }, [load]);

  useEffect(() => {
    const t = setTimeout(() => {
      void loadFornecedores();
    }, 0);
    return () => clearTimeout(t);
  }, [loadFornecedores]);

  if (tenantEmpresaError) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 p-6">
        {tenantEmpresaError}
      </div>
    );
  }

  if (tenantEmpresaLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando contexto...
      </div>
    );
  }

  // After login, tenant/empresa should be auto-resolved by the provider.
  // Keep a simple loading state while IDs are being set.
  if (!tenantId || !empresaId) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando contexto...
      </div>
    );
  }

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissoes...
      </div>
    );
  }

  if (!canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Estoque</h1>
          <p className="text-sm text-zinc-400 mt-1">Saldo atual por produto (com controle de estoque).</p>
        </div>

        <div className="flex items-center gap-2">
          <Can perm="estoque.write">
            <button
              onClick={() => {
                setErr(null);
                setOk(null);
                resetAjuste();
                setShowAjuste(true);
              }}
              disabled={!canAdjust}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
            >
              Ajuste estoque
            </button>
          </Can>
          <Can perm="estoque.write">
            {isAdminTenant && !adminTenantLoading && (
              <button
                onClick={() => {
                  setErr(null);
                  setOk(null);
                  setZeraFornecedorId("");
                  setShowZeraEstoque(true);
                }}
                disabled={!canAdjust || busy}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
              >
                Zera estoque
              </button>
            )}
          </Can>
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <form
        ref={filtrosFormRef}
        onSubmit={(e) => {
          e.preventDefault();
          setErr(null);
          setOk(null);
          setPage(0);
          setFiltros(draftFiltros);
        }}
        className="border border-zinc-800 rounded-xl p-4 bg-zinc-950"
      >
        <div className="grid grid-cols-1 md:grid-cols-12 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">ID</div>
            <input
              aria-label="Filtrar por id"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFiltros.id}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, id: e.target.value }))}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder="item_id"
            />
          </div>

          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Código</div>
            <input
              aria-label="Filtrar por código"
              ref={codigoInputRef}
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFiltros.codigo}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, codigo: e.target.value }))}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder="código interno ou barras"
            />
          </div>

          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Produto</div>
            <input
              aria-label="Filtrar por produto"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFiltros.produto}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, produto: e.target.value }))}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder="Nome do produto"
            />
          </div>

          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor</div>
            <input
              aria-label="Filtrar por fornecedor"
              list="fornecedor-options"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFiltros.fornecedor}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, fornecedor: e.target.value }))}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder='Ex: "siemens"'
            />
            <datalist id="fornecedor-options">
              {fornecedores.map((f) => (
                <option key={f.id} value={String(f.nome ?? "").trim()} />
              ))}
            </datalist>
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400 whitespace-nowrap truncate">Ativo</div>
            <select
              aria-label="Ativo"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFiltros.ativos}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, ativos: e.target.value as "ativos" | "todos" }))}
            >
              <option value="ativos">Sim</option>
              <option value="todos">Ativos + inativos</option>
            </select>
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400 whitespace-nowrap truncate">Abaixo do mínimo</div>
            <select
              aria-label="Abaixo do mínimo"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFiltros.abaixoMinimo ? "sim" : "nao"}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, abaixoMinimo: e.target.value === "sim" }))}
            >
              <option value="nao">Não</option>
              <option value="sim">Sim</option>
            </select>
          </div>
        </div>

        <div className="flex items-center gap-2 mt-3">
          <button type="submit" className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
            Aplicar filtros
          </button>
          <button
            type="button"
            onClick={() => {
              setErr(null);
              setOk(null);
              setPage(0);
              setDraftFiltros(getFiltrosIniciais());
              setFiltros(getFiltrosIniciais());
            }}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Limpar
          </button>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </form>

      {showAjuste && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Ajuste estoque</div>
                <div className="text-sm text-zinc-400">ID → saldo → mín → máx (Enter salva)</div>
              </div>
              <button
                onClick={closeAjusteAndFocusCodigo}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">ID</div>
                  <input
                    ref={ajusteItemIdRef}
                    aria-label="ID do item"
                    inputMode="numeric"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
                    value={ajusteItemIdText}
                    onChange={(e) => setAjusteItemIdText(e.target.value)}
                    onFocus={(e) => e.currentTarget.select()}
                    onKeyDown={(e) => {
                      if (e.key === "Escape") {
                        e.preventDefault();
                        closeAjusteAndFocusCodigo();
                        return;
                      }
                      if (e.key === "Enter") {
                        e.preventDefault();
                        const parsed = Number(String(ajusteItemIdText ?? "").trim());
                        if (!Number.isInteger(parsed) || parsed <= 0) {
                          setErr("Informe um ID de item valido.");
                          return;
                        }
                        void (async () => {
                          const ok = await preencherAjustePorId(parsed);
                          if (!ok) return;
                          ajusteSaldoRef.current?.focus();
                          ajusteSaldoRef.current?.select?.();
                        })();
                      }
                    }}
                    placeholder="id"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Saldo</div>
                  <input
                    ref={ajusteSaldoRef}
                    aria-label="Saldo"
                    inputMode="decimal"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
                    value={ajusteSaldoText}
                    onChange={(e) => setAjusteSaldoText(e.target.value)}
                    onFocus={(e) => e.currentTarget.select()}
                    onKeyDown={(e) => {
                      if (e.key === "Escape") {
                        e.preventDefault();
                        closeAjusteAndFocusCodigo();
                        return;
                      }
                      if (e.key === "Enter") {
                        e.preventDefault();
                        ajusteMinRef.current?.focus();
                        ajusteMinRef.current?.select?.();
                      }
                    }}
                    placeholder="saldo"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Mín</div>
                  <input
                    ref={ajusteMinRef}
                    aria-label="Min"
                    inputMode="decimal"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
                    value={ajusteMinText}
                    onChange={(e) => setAjusteMinText(e.target.value)}
                    onFocus={(e) => e.currentTarget.select()}
                    onKeyDown={(e) => {
                      if (e.key === "Escape") {
                        e.preventDefault();
                        closeAjusteAndFocusCodigo();
                        return;
                      }
                      if (e.key === "Enter") {
                        e.preventDefault();
                        ajusteMaxRef.current?.focus();
                        ajusteMaxRef.current?.select?.();
                      }
                    }}
                    placeholder="min"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Máx</div>
                  <input
                    ref={ajusteMaxRef}
                    aria-label="Max"
                    inputMode="decimal"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
                    value={ajusteMaxText}
                    onChange={(e) => setAjusteMaxText(e.target.value)}
                    onFocus={(e) => e.currentTarget.select()}
                    onKeyDown={(e) => {
                      if (e.key === "Escape") {
                        e.preventDefault();
                        closeAjusteAndFocusCodigo();
                        return;
                      }
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void salvarAjusteRapido();
                      }
                    }}
                    placeholder="max"
                  />
                </div>
              </div>

              <div className="text-xs text-zinc-400">{ajusteDescricao || "Descricao do item"}</div>

              {err && <div className="text-sm text-red-400">{err}</div>}
              {ok && <div className="text-sm text-emerald-300">{ok}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
              <button
                onClick={closeAjusteAndFocusCodigo}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={salvarAjusteRapido}
                disabled={busy || !canAdjust}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
              >
                {busy ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}

      {showZeraEstoque && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Zera estoque</div>
                <div className="text-sm text-zinc-400">Selecione o fornecedor para zerar o saldo.</div>
              </div>
              <button
                onClick={closeZeraEstoqueAndFocusCodigo}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Fornecedor</div>
                <select
                  ref={zeraFornecedorRef}
                  aria-label="Fornecedor"
                  className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
                  value={zeraFornecedorId}
                  onChange={(e) => setZeraFornecedorId(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Escape") {
                      e.preventDefault();
                      closeZeraEstoqueAndFocusCodigo();
                      return;
                    }
                    if (e.key === "Enter") {
                      e.preventDefault();
                      void zerarEstoqueFornecedorSelecionado();
                    }
                  }}
                >
                  <option value="">Selecione...</option>
                  {fornecedores
                    .filter((f) => f.ativo)
                    .map((f) => (
                      <option key={f.id} value={String(f.id)}>
                        {String(f.nome ?? "").trim() || `#${f.id}`}
                      </option>
                    ))}
                </select>
              </div>

              <div className="flex items-center justify-end gap-2 pt-1">
                <button
                  onClick={closeZeraEstoqueAndFocusCodigo}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={() => void zerarEstoqueFornecedorSelecionado()}
                  disabled={busy || !canAdjust || !isAdminTenant || adminTenantLoading || !zeraFornecedorId}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  {busy ? "Zerando..." : "Zerar estoque"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">ID</th>
              <th className="px-4 py-3 text-left">Código</th>
              <th className="px-4 py-3 text-left">Produto</th>
              <th className="px-4 py-3 text-left">Fornecedor</th>
              <th className="px-4 py-3 text-right">Saldo</th>
              <th className="px-4 py-3 text-right">Mín</th>
              <th className="px-4 py-3 text-right">Ideal</th>
              <th className="px-4 py-3 text-right">Máx</th>
              <th className="px-4 py-3 text-center">Ações</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => {
              const min = Number(r.itens?.estoque_minimo ?? 0);
              const max = Number(r.itens?.estoque_maximo ?? 0);
              const saldo = Number(r.quantidade_atual ?? 0);
              const abaixo = saldo < min;

              return (
                <tr key={r.id} className={abaixo ? "bg-red-500/10" : "hover:bg-zinc-900/40"}>
                  <td className="px-4 py-3 text-zinc-300">{r.item_id}</td>
                  <td className="px-4 py-3 font-medium">{r.itens?.codigo_interno}</td>
                  <td className="px-4 py-3">
                    <div className="font-medium">{r.itens?.nome}</div>
                    <div className="text-xs text-zinc-400">
                      {r.itens?.unidade_medida ?? "UN"} · {abaixo ? "Abaixo do mínimo" : "OK"}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-left">
                    <div className="text-sm text-zinc-200">
                      {r.itens?.fornecedores?.nome ?? fornecedorNomeById(r.itens?.fornecedor_id) ?? "—"}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <InlineNumberInput
                      ariaLabel={`Saldo item ${r.item_id}`}
                      value={saldo}
                      decimals={3}
                      disabled={busy || !canAdjust}
                      onCommit={(v) => aplicarAjusteInline(r.item_id, v)}
                    />
                  </td>
                  <td className="px-4 py-3">
                    <InlineNumberInput
                      ariaLabel={`Min item ${r.item_id}`}
                      value={min}
                      decimals={3}
                      disabled={busy || !canAdjust}
                      onCommit={(v) => salvarLimitesInline(r.item_id, v, max)}
                    />
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatDecimalBR(calcIdeal(min, max), 0)}</td>
                  <td className="px-4 py-3">
                    <InlineNumberInput
                      ariaLabel={`Max item ${r.item_id}`}
                      value={max}
                      decimals={3}
                      disabled={busy || !canAdjust}
                      onCommit={(v) => salvarLimitesInline(r.item_id, min, v)}
                    />
                  </td>
                  <td className="px-4 py-3 text-center">
                    <Can perm="estoque.write">
                      <button
                        onClick={() => startAjuste(r.item_id)}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                      >
                        Ajustar
                      </button>
                    </Can>
                  </td>
                </tr>
              );
            })}

            {rows.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-6 text-zinc-400">
                  Nenhum produto com estoque encontrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <div className="flex items-center justify-between mt-3">
        <div className="text-xs text-zinc-400">
          Pagina {page + 1}
          {typeof totalCount === "number" && totalCount > 0
            ? ` de ${Math.ceil(totalCount / pageSize)}`
            : ""}
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setPage((p) => Math.max(0, p - 1))}
            disabled={page === 0}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
          >
            Anterior
          </button>
          <button
            onClick={() => setPage((p) => p + 1)}
            disabled={typeof totalCount === "number" ? (page + 1) * pageSize >= totalCount : false}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
          >
            Proxima
          </button>
        </div>
      </div>
      <div className="flex justify-end mt-4">
        <button
          onClick={() =>
            gerarRelatorioEstoque(rows, {
              busca: [filtros.codigo, filtros.produto].filter(Boolean).join(" | "),
              codigoId: filtros.id,
              codigoFornecedor: "",
              fornecedorNome: filtros.fornecedor,
              ativos: filtros.ativos,
              abaixoMinimo: filtros.abaixoMinimo,
            })
          }
          className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
        >
          Imprimir PDF
        </button>
      </div>
    </div>
  );
}

