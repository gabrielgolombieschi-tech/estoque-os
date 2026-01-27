"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { formatDecimalBR, parseDecimalBR } from "../../lib/decimal";
import { supabaseBrowser } from "../../lib/supabase/client";
import { gerarRelatorioEstoque } from "../../lib/pdf/relatorioEstoque";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
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
type EstoqueItemRow = NonNullable<EstoqueRow["itens"]> & { id: number; estoque: EstoqueJoinRow[] };

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
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("estoque.read");
  const canAdjust = has("estoque.write");

  const [rows, setRows] = useState<EstoqueRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [draftFiltros, setDraftFiltros] = useState<Filtros>(getFiltrosIniciais);
  const [filtros, setFiltros] = useState<Filtros>(getFiltrosIniciais);
  const [abaixoMinCacheKey, setAbaixoMinCacheKey] = useState<string>("");
  const [abaixoMinCache, setAbaixoMinCache] = useState<EstoqueRow[] | null>(null);

  const [ajusteItemId, setAjusteItemId] = useState<number | null>(null);
  const [ajusteQuantidade, setAjusteQuantidade] = useState<number>(0);
  const [ajusteMotivo, setAjusteMotivo] = useState<string>("Ajuste manual");
  const [showAjuste, setShowAjuste] = useState(false);
  const [estoqueMinimo, setEstoqueMinimo] = useState<number>(0);
  const [estoqueIdeal, setEstoqueIdeal] = useState<number>(0);
  const [estoqueMaximo, setEstoqueMaximo] = useState<number>(0);
  const [limiteBusy, setLimiteBusy] = useState(false);
  const [limiteMsg, setLimiteMsg] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const pageSize = 250;
  const [totalCount, setTotalCount] = useState<number | null>(null);

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

    const filtrosKey = JSON.stringify(filtros);
    if (filtros.abaixoMinimo && abaixoMinCache && abaixoMinCacheKey === filtrosKey) {
      setTotalCount(abaixoMinCache.length);
      setRows(abaixoMinCache.slice(page * pageSize, page * pageSize + pageSize));
      return;
    }

    if (!filtros.abaixoMinimo && abaixoMinCache) {
      setAbaixoMinCache(null);
      setAbaixoMinCacheKey("");
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

    const select =
      "id,codigo_interno,codigo_barras,nome,tipo,unidade_medida,controla_estoque,estoque_minimo,estoque_ideal,estoque_maximo,ativo,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome),estoque!estoque_item_id_fkey!inner(id,item_id,quantidade_atual,atualizado_em,localizacao)";

    const buildItensQuery = (withCount: boolean) => {
      const base = withCount
        ? supabase.from("itens").select(select, { count: "exact" })
        : supabase.from("itens").select(select);

      let query = applyTenantEmpresa(base, tenantId, empresaId)
        .eq("tipo", "produto")
        .eq("controla_estoque", true)
        .order("id", { foreignTable: "estoque", ascending: false })
        .order("id", { ascending: false });

      if (filtros.ativos === "ativos") query = query.eq("ativo", true);
      if (idNumber !== null) query = query.eq("id", idNumber);

      const codigoTerm = filtros.codigo.trim();
      if (codigoTerm) {
        const safe = codigoTerm.replaceAll(",", " ").trim();
        query = query.or(`codigo_interno.ilike.%${safe}%,codigo_barras.ilike.%${safe}%`);
      }

      const produtoTerm = filtros.produto.trim();
      if (produtoTerm) query = query.ilike("nome", `%${produtoTerm}%`);

      const fornTerm = filtros.fornecedor.trim();
      if (fornTerm) query = query.ilike("fornecedores.nome", `%${fornTerm}%`);

      return query;
    };

    const mapToEstoqueRow = (item: EstoqueItemRow): EstoqueRow | null => {
      const estoqueRow = item.estoque?.[0];
      if (!estoqueRow) return null;
      const { estoque, ...itens } = item;
      void estoque;
      return {
        id: estoqueRow.id,
        item_id: item.id,
        quantidade_atual: Number(estoqueRow.quantidade_atual ?? 0),
        atualizado_em: estoqueRow.atualizado_em,
        localizacao: estoqueRow.localizacao ?? null,
        itens,
      };
    };

    if (filtros.abaixoMinimo) {
      const all: EstoqueItemRow[] = [];
      const chunkSize = 1000;
      let offset = 0;

      while (true) {
        const { data, error } = await buildItensQuery(false).range(offset, offset + chunkSize - 1);
        if (error) return setErr(error.message);
        const typed = (data ?? []) as unknown as EstoqueItemRow[];
        all.push(...typed);
        if (typed.length < chunkSize) break;
        offset += chunkSize;
      }

      const below = all
        .map(mapToEstoqueRow)
        .filter(Boolean)
        .filter((r) => Number(r!.quantidade_atual ?? 0) < Number(r!.itens?.estoque_minimo ?? 0)) as EstoqueRow[];

      setAbaixoMinCacheKey(filtrosKey);
      setAbaixoMinCache(below);
      setTotalCount(below.length);
      setRows(below.slice(page * pageSize, page * pageSize + pageSize));
      return;
    }

    const { data, error, count } = await buildItensQuery(true).range(page * pageSize, page * pageSize + pageSize - 1);
    if (error) return setErr(error.message);
    setTotalCount(typeof count === "number" ? count : null);

    const typed = (data ?? []) as unknown as EstoqueItemRow[];
    const list = typed.map(mapToEstoqueRow).filter(Boolean) as EstoqueRow[];
    setRows(list);
  }, [
    abaixoMinCache,
    abaixoMinCacheKey,
    empresaId,
    filtros,
    page,
    pageSize,
    supabase,
    tenantEmpresaLoading,
    tenantId,
  ]);

  function startAjuste(item_id: number, atual: number) {
    setOk(null);
    setErr(null);
    setAjusteItemId(item_id);
    setAjusteQuantidade(atual);
    setAjusteMotivo("Ajuste manual");
    const row = rows.find((r) => r.item_id === item_id);
    setEstoqueMinimo(Number(row?.itens?.estoque_minimo ?? 0));
    setEstoqueIdeal(Number(row?.itens?.estoque_ideal ?? 0));
    setEstoqueMaximo(Number(row?.itens?.estoque_maximo ?? 0));
    setLimiteMsg(null);
    setShowAjuste(true);
  }

  async function aplicarAjuste() {
    setOk(null);
    setErr(null);
    if (!canAdjust) return setErr("Sem permissao para ajustar estoque.");

    if (!ajusteItemId) return setErr("Selecione um item para ajustar.");
    if (!Number.isFinite(ajusteQuantidade)) return setErr("Quantidade inválida.");
    const novoSaldo = Number(ajusteQuantidade);

    setBusy(true);

    const atualRow = rows.find((r) => r.item_id === ajusteItemId);
    const saldoAtual = Number(atualRow?.quantidade_atual ?? 0);
    const diff = novoSaldo - saldoAtual;

    if (diff === 0) {
      setBusy(false);
      return setErr("Nada a ajustar (novo saldo igual ao atual).");
    }

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const tipoMov = diff > 0 ? "entrada" : "saida";
    const qtdMov = Math.abs(diff);

    if (!tenantId || !empresaId) {
      setBusy(false);
      return setErr("Tenant ou empresa nao carregados.");
    }

    const { error } = await supabase.from("movimentacoes").insert({
      tenant_id: tenantId,
      item_id: ajusteItemId,
      tipo: tipoMov,
      quantidade: qtdMov,
      motivo: `${ajusteMotivo} (ajuste para ${novoSaldo})`,
      realizado_por: userEmail,
      data_movimentacao: new Date().toISOString(),
    });

    setBusy(false);
    if (error) return setErr(error.message);

    setOk(`Ajuste aplicado. Saldo: ${saldoAtual} -> ${novoSaldo}`);
    setAjusteItemId(null);
    setAjusteQuantidade(0);
    setShowAjuste(false);
    await load();
  }

  async function salvarLimites() {
    if (!ajusteItemId) return;
    if (!canAdjust) {
      setLimiteMsg("Sem permissao para ajustar estoque.");
      return;
    }
    setLimiteBusy(true);
    setLimiteMsg(null);
    if (!tenantId || !empresaId) {
      setLimiteBusy(false);
      setLimiteMsg("Tenant ou empresa nao carregados.");
      return;
    }
    const { error } = await applyTenantEmpresa(supabase.from("itens").update({
      estoque_minimo: estoqueMinimo,
      estoque_ideal: estoqueIdeal,
      estoque_maximo: estoqueMaximo,
    }), tenantId, empresaId).eq("id", ajusteItemId);
    setLimiteBusy(false);
    setLimiteMsg(error ? `Erro ao salvar limites: ${error.message}` : "Limites salvos.");
    if (!error) await load();
  }

  function fecharAjuste() {
    setShowAjuste(false);
    setAjusteItemId(null);
    setAjusteQuantidade(0);
    setAjusteMotivo("Ajuste manual");
    setEstoqueMinimo(0);
    setEstoqueIdeal(0);
    setEstoqueMaximo(0);
    setLimiteMsg(null);
  }

  useEffect(() => {
    const t = setTimeout(() => {
      void load();
    }, 0);
    return () => clearTimeout(t);
  }, [load]);

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
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          setErr(null);
          setOk(null);
          setPage(0);
          setAbaixoMinCache(null);
          setAbaixoMinCacheKey("");
          setFiltros(draftFiltros);
        }}
        className="border border-zinc-800 rounded-xl p-4 bg-zinc-950"
      >
        <div className="grid grid-cols-1 md:grid-cols-12 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">ID</div>
            <input
              className="w-full px-3 py-2"
              value={draftFiltros.id}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, id: e.target.value }))}
              placeholder="item_id"
            />
          </div>

          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Código</div>
            <input
              className="w-full px-3 py-2"
              value={draftFiltros.codigo}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, codigo: e.target.value }))}
              placeholder="código interno ou barras"
            />
          </div>

          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Produto</div>
            <input
              className="w-full px-3 py-2"
              value={draftFiltros.produto}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, produto: e.target.value }))}
              placeholder="Nome do produto"
            />
          </div>

          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor</div>
            <input
              className="w-full px-3 py-2"
              value={draftFiltros.fornecedor}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, fornecedor: e.target.value }))}
              placeholder="Nome do fornecedor"
            />
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">Ativo</div>
            <select
              aria-label="Ativo"
              className="w-full px-3 py-2"
              value={draftFiltros.ativos}
              onChange={(e) => setDraftFiltros((prev) => ({ ...prev, ativos: e.target.value as "ativos" | "todos" }))}
            >
              <option value="ativos">Sim</option>
              <option value="todos">Ativos + inativos</option>
            </select>
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">Abaixo do mínimo</div>
            <select
              aria-label="Abaixo do mínimo"
              className="w-full px-3 py-2"
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
              setAbaixoMinCache(null);
              setAbaixoMinCacheKey("");
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
                <div className="text-lg font-semibold">Ajustar estoque</div>
                <div className="text-sm text-zinc-400">Defina o novo saldo para o item selecionado.</div>
              </div>
              <button
                onClick={fecharAjuste}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Item selecionado</div>
                <input
                aria-label="Item selecionado"
                  className="w-full px-3 py-2"
                  value={ajusteItemId ? `item_id=${ajusteItemId}` : ""}
                  disabled
                  placeholder="Nenhum item selecionado"
                />
                <div className="text-xs text-zinc-400">
                  {rows.find((r) => r.item_id === ajusteItemId)?.itens?.nome ?? "Sem descrição"}
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Novo saldo desejado</div>
                  <input
                    type="text"
                    inputMode="decimal"
                      aria-label="Novo saldo desejado"
                    step="0.001"
                    className="w-full px-3 py-2"
                    value={ajusteQuantidade}
                    onChange={(e) => setAjusteQuantidade(parseDecimalBR(e.target.value) || 0)}
                    disabled={!ajusteItemId}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Motivo</div>
                    <input aria-label="Motivo" className="w-full px-3 py-2" value={ajusteMotivo} disabled />
                </div>
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
              {ok && <div className="text-sm text-emerald-300">{ok}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
              <button
                onClick={fecharAjuste}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={aplicarAjuste}
                disabled={busy || !ajusteItemId || !canAdjust}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
              >
                {busy ? "Aplicando..." : "Aplicar ajuste"}
              </button>
            </div>

            <div className="px-5 py-4 border-t border-zinc-800 bg-zinc-950 space-y-3">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Estoque mínimo</div>
                  <input
                      aria-label="Estoque mínimo"
                    className="w-full px-3 py-2"
                    value={estoqueMinimo}
                    onChange={(e) => setEstoqueMinimo(parseDecimalBR(e.target.value) || 0)}
                    disabled={!ajusteItemId || limiteBusy}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Estoque ideal</div>
                  <input
                      aria-label="Estoque ideal"
                    className="w-full px-3 py-2"
                    value={estoqueIdeal}
                    onChange={(e) => setEstoqueIdeal(parseDecimalBR(e.target.value) || 0)}
                    disabled={!ajusteItemId || limiteBusy}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Estoque máximo</div>
                  <input
                      aria-label="Estoque máximo"
                    className="w-full px-3 py-2"
                    value={estoqueMaximo}
                    onChange={(e) => setEstoqueMaximo(parseDecimalBR(e.target.value) || 0)}
                    disabled={!ajusteItemId || limiteBusy}
                  />
                </div>
              </div>

              {limiteMsg && <div className="text-sm text-emerald-300">{limiteMsg}</div>}
              <div className="flex justify-end">
                <button
                  onClick={salvarLimites}
                  disabled={!ajusteItemId || limiteBusy || !canAdjust}
                  className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-100"
                >
                  {limiteBusy ? "Salvando..." : "Salvar limites"}
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
              const ideal = Number(r.itens?.estoque_ideal ?? 0);
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
                      {r.itens?.fornecedores?.nome ?? "—"}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatDecimalBR(saldo, 3)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatDecimalBR(min, 3)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatDecimalBR(ideal, 3)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatDecimalBR(max, 3)}</td>
                  <td className="px-4 py-3 text-center">
                    <Can perm="estoque.write">
                      <button
                        onClick={() => startAjuste(r.item_id, saldo)}
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

