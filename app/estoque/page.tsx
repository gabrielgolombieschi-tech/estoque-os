"use client";

import { useEffect, useMemo, useState } from "react";
import { formatDecimalBR, parseDecimalBR } from "../../lib/decimal";
import { supabaseBrowser } from "../../lib/supabase/client";
import { gerarRelatorioEstoque } from "../../lib/pdf/relatorioEstoque";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
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
type EstoqueItemRow = NonNullable<EstoqueRow["itens"]> & { id: number };

export default function EstoquePage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId, loading: tenantEmpresaLoading } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("estoque.read");
  const canAdjust = has("estoque.write");

  const [rows, setRows] = useState<EstoqueRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [q, setQ] = useState("");
  const [soAbaixoMin, setSoAbaixoMin] = useState(false);
  const [ativos, setAtivos] = useState<"ativos" | "todos">("ativos");
  const [codigoId, setCodigoId] = useState("");
  const [fornecedorNome, setFornecedorNome] = useState("");

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

  async function load() {
    setErr(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setErr("Tenant ou empresa nao carregados.");
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
      const { data: itensData, error: itensErr } = await applyTenant(
        supabase
          .from("itens")
          .select(
            "id,codigo_interno,codigo_barras,nome,tipo,unidade_medida,controla_estoque,estoque_minimo,estoque_ideal,estoque_maximo,ativo,fornecedor_id,fornecedores:fornecedor_id(nome)"
          ),
        tenantId
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
  }

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
      empresa_id: empresaId,
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
    if (!tenantId) {
      setLimiteBusy(false);
      setLimiteMsg("Tenant nao carregado.");
      return;
    }
    const { error } = await applyTenant(supabase.from("itens").update({
      estoque_minimo: estoqueMinimo,
      estoque_ideal: estoqueIdeal,
      estoque_maximo: estoqueMaximo,
    }), tenantId).eq("id", ajusteItemId);
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
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [soAbaixoMin, ativos, page, tenantId, empresaId, tenantEmpresaLoading]);

  useEffect(() => {
    setPage(0);
  }, [q, codigoId, fornecedorNome, soAbaixoMin, ativos]);

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

            <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input className="w-full px-3 py-2" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Código ou nome" />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Código (id)</div>
            <input className="w-full px-3 py-2" value={codigoId} onChange={(e) => setCodigoId(e.target.value)} placeholder="item_id" />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor</div>
            <input
              className="w-full px-3 py-2"
              value={fornecedorNome}
              onChange={(e) => setFornecedorNome(e.target.value)}
              placeholder="Nome do fornecedor"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Ativos</div>
            <select
            aria-label="Ativos"
              className="w-full px-3 py-2"
              value={ativos}
              onChange={(e) => setAtivos(e.target.value as "ativos" | "todos")}
            >
              <option value="ativos">Somente ativos</option>
              <option value="todos">Ativos + inativos</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Abaixo do mínimo</div>
              <select
                aria-label="Abaixo do mínimo"
                className="w-full px-3 py-2"
                value={soAbaixoMin ? "sim" : "nao"}
                onChange={(e) => setSoAbaixoMin(e.target.value === "sim")}
              >
              <option value="nao">Não</option>
              <option value="sim">Sim</option>
            </select>
          </div>
        </div>

        <div className="flex items-center gap-2 mt-3">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Aplicar filtros
          </button>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </div>

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
              busca: q,
              codigoId,
              codigoFornecedor: "",
              fornecedorNome,
              ativos,
              abaixoMinimo: soAbaixoMin,
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

