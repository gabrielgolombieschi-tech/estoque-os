"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { mapOrcamentoError, n, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import { DEFAULT_CONJUNTO_CATEGORIAS, ensureConfig, getConfig, getConjuntoCategorias, normalizeConjuntoCategorias, updateConfig } from "@/src/services/configOrcamento";
import { list as listCondicoesPagamento } from "@/src/services/condicaoPagamento";

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

type ConfigForm = {
  margem_lucro_padrao_percent: string;
  margem_mao_obra_padrao_percent: string;
  desconto_max_percent: string;
  condicao_pagamento_padrao_id: string | null;
  conjunto_categorias_text: string;
};

export default function ConfigOrcamentosPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = hasAny(capabilities, ["financeiro.config", "financeiro.write", "os.write"]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [cfgId, setCfgId] = useState<string | null>(null);
  const [condicoes, setCondicoes] = useState<Array<{ id: string; nome: string | null }>>([]);
  const [form, setForm] = useState<ConfigForm>({
    margem_lucro_padrao_percent: "53",
    margem_mao_obra_padrao_percent: "30",
    desconto_max_percent: "25",
    condicao_pagamento_padrao_id: null,
    conjunto_categorias_text: DEFAULT_CONJUNTO_CATEGORIAS.join("\n"),
  });
  const [showNovaCategoria, setShowNovaCategoria] = useState(false);
  const [novaCategoria, setNovaCategoria] = useState("");
  const [categoriaErr, setCategoriaErr] = useState<string | null>(null);
  const conjuntoCategoriasPreview = useMemo(
    () => normalizeConjuntoCategorias(form.conjunto_categorias_text.split(/\r?\n/g)),
    [form.conjunto_categorias_text]
  );

  const applyConjuntoCategorias = useCallback((categorias: string[]) => {
    setForm((prev) => ({ ...prev, conjunto_categorias_text: categorias.join("\n") }));
  }, []);

  const openNovaCategoria = useCallback(() => {
    setCategoriaErr(null);
    setNovaCategoria("");
    setShowNovaCategoria(true);
  }, []);

  const cancelNovaCategoria = useCallback(() => {
    setCategoriaErr(null);
    setNovaCategoria("");
    setShowNovaCategoria(false);
  }, []);

  const addCategoria = useCallback(() => {
    const categoria = upperTrim(novaCategoria);
    if (!categoria) {
      setCategoriaErr("Informe o nome da categoria.");
      return;
    }
    if (conjuntoCategoriasPreview.includes(categoria)) {
      setCategoriaErr("Essa categoria ja esta cadastrada.");
      return;
    }

    applyConjuntoCategorias([...conjuntoCategoriasPreview, categoria]);
    setCategoriaErr(null);
    setNovaCategoria("");
    setShowNovaCategoria(false);
  }, [applyConjuntoCategorias, conjuntoCategoriasPreview, novaCategoria]);

  const removeCategoria = useCallback(
    (categoria: string) => {
      if (conjuntoCategoriasPreview.length <= 1) {
        setCategoriaErr("Mantenha ao menos uma categoria cadastrada.");
        return;
      }

      applyConjuntoCategorias(conjuntoCategoriasPreview.filter((value) => value !== categoria));
      setCategoriaErr(null);
    },
    [applyConjuntoCategorias, conjuntoCategoriasPreview]
  );

  const load = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (te.loading) return;

    if (!tenantId || !empresaId) {
      setLoading(false);
      setErr("Contexto (tenant/empresa) não carregado.");
      return;
    }

    setLoading(true);
    try {
      let cfg = await getConfig(supabase, { tenantId, empresaId });
      if (!cfg) {
        cfg = await ensureConfig(supabase, { tenantId, empresaId });
      }

      const cps = await listCondicoesPagamento(supabase, { tenantId, empresaId, onlyActive: true });

      setCfgId(cfg.id);
      setForm({
        margem_lucro_padrao_percent: String(cfg.margem_lucro_padrao_percent ?? "53"),
        margem_mao_obra_padrao_percent: String(cfg.margem_mao_obra_padrao_percent ?? "30"),
        desconto_max_percent: String(cfg.desconto_max_percent ?? "25"),
        condicao_pagamento_padrao_id: cfg.condicao_pagamento_padrao_id ?? null,
        conjunto_categorias_text: getConjuntoCategorias(cfg).join("\n"),
      });
      setCondicoes(cps.map((c) => ({ id: c.id, nome: c.nome ?? null })));
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar configurações."));
    } finally {
      setLoading(false);
    }
  }, [empresaId, supabase, te.loading, tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  const save = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      if (!supabase || !tenantId || !empresaId || !cfgId) return;

      const margem = n(form.margem_lucro_padrao_percent);
      const margemMaoObra = n(form.margem_mao_obra_padrao_percent);
      const descontoMax = n(form.desconto_max_percent);
      const conjuntoCategorias = normalizeConjuntoCategorias(form.conjunto_categorias_text.split(/\r?\n/g));
      if (margem < 0 || margem > 100) {
        setErr("Margem padrão deve estar entre 0 e 100.");
        return;
      }
      if (margemMaoObra < 0 || margemMaoObra > 100) {
        setErr("Margem de mão de obra deve estar entre 0 e 100.");
        return;
      }
      if (descontoMax < 0 || descontoMax > 100) {
        setErr("Desconto máximo deve estar entre 0 e 100.");
        return;
      }

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await updateConfig(supabase, {
          tenantId,
          empresaId,
          id: cfgId,
          patch: {
            margem_lucro_padrao_percent: margem,
            margem_mao_obra_padrao_percent: margemMaoObra,
            desconto_max_percent: descontoMax,
            condicao_pagamento_padrao_id: form.condicao_pagamento_padrao_id ?? null,
            conjunto_categorias: conjuntoCategorias,
          },
        });

        setOk("Configuração atualizada.");
        await load();
      } catch (e2: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e2), "Erro ao salvar."));
      } finally {
        setBusy(false);
      }
    },
    [cfgId, empresaId, form, load, supabase, tenantId]
  );

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Configurações — Orçamentos</h1>
          <p className="text-sm text-zinc-400 mt-1">Limites e padrões por empresa.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/comercial/orcamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Ir para Orçamentos
          </Link>
          <button
            type="button"
            onClick={() => void load()}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Atualizar
          </button>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}
      {loading && <div className="text-sm text-zinc-400">Carregando...</div>}

      {!loading && (
        <form onSubmit={save} className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <label className="block text-xs text-zinc-400">
              Margem lucro padrão (%)
              <input
                value={form.margem_lucro_padrao_percent}
                onChange={(e) => setForm((p) => ({ ...p, margem_lucro_padrao_percent: e.target.value }))}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
              />
            </label>

            <label className="block text-xs text-zinc-400">
              Margem mão de obra padrão (%)
              <input
                value={form.margem_mao_obra_padrao_percent}
                onChange={(e) => setForm((p) => ({ ...p, margem_mao_obra_padrao_percent: e.target.value }))}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
              />
            </label>

            <label className="block text-xs text-zinc-400">
              Desconto máximo (%)
              <input
                value={form.desconto_max_percent}
                onChange={(e) => setForm((p) => ({ ...p, desconto_max_percent: e.target.value }))}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
              />
            </label>

            <label className="block text-xs text-zinc-400">
              Condição padrão
              <select
                value={form.condicao_pagamento_padrao_id ?? ""}
                onChange={(e) =>
                  setForm((p) => ({ ...p, condicao_pagamento_padrao_id: e.target.value ? e.target.value : null }))
                }
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
              >
                <option value="">(Sem condição)</option>
                {condicoes.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nome ?? c.id}
                  </option>
                ))}
              </select>
            </label>
            <section className="md:col-span-3 rounded-xl border border-zinc-800 bg-zinc-900/30">
              <div className="flex flex-col gap-3 border-b border-zinc-800 px-4 py-4 md:flex-row md:items-start md:justify-between">
                <div>
                  <h2 className="text-sm font-semibold text-zinc-100">Categorias fixas dos conjuntos</h2>
                  <p className="mt-1 max-w-2xl text-xs leading-5 text-zinc-400">
                    Defina a lista padrao exibida no campo de categoria do cadastro de conjuntos. A normalizacao
                    mantem os nomes em caixa alta e ignora linhas vazias ou duplicadas ao salvar.
                  </p>
                </div>

                <div className="flex flex-col items-stretch gap-2 sm:flex-row sm:items-center">
                  <div className="rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-3 sm:min-w-[150px]">
                    <div className="text-[11px] uppercase tracking-wide text-zinc-500">Categorias cadastradas</div>
                    <div className="mt-1 text-lg font-semibold text-zinc-100 tabular-nums">{conjuntoCategoriasPreview.length}</div>
                  </div>
                  <button
                    type="button"
                    onClick={showNovaCategoria ? cancelNovaCategoria : openNovaCategoria}
                    className="rounded-md border border-zinc-700 bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 hover:bg-white"
                  >
                    {showNovaCategoria ? "Cancelar cadastro" : "Nova categoria"}
                  </button>
                </div>
              </div>

              {showNovaCategoria && (
                <div className="border-b border-zinc-800 px-4 py-4">
                  <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto_auto]">
                    <label className="block text-[11px] uppercase tracking-wide text-zinc-500">
                      Nome da categoria
                      <input
                        value={novaCategoria}
                        onChange={(e) => {
                          setNovaCategoria(e.target.value);
                          if (categoriaErr) setCategoriaErr(null);
                        }}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") {
                            e.preventDefault();
                            addCategoria();
                          }
                        }}
                        className="mt-2 w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none transition focus:border-zinc-500"
                        placeholder="Ex.: ENTRADA ENERGIA"
                        autoFocus
                        spellCheck={false}
                      />
                    </label>
                    <button
                      type="button"
                      onClick={addCategoria}
                      className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 hover:bg-white md:self-end"
                    >
                      Adicionar
                    </button>
                    <button
                      type="button"
                      onClick={cancelNovaCategoria}
                      className="rounded-md border border-zinc-800 bg-zinc-950 px-4 py-2 text-sm text-zinc-100 hover:bg-zinc-900 md:self-end"
                    >
                      Cancelar
                    </button>
                  </div>

                  {categoriaErr && <div className="mt-2 text-xs text-rose-400">{categoriaErr}</div>}
                </div>
              )}

              <div className="p-4">
                <div className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
                  <table className="w-full text-sm">
                    <thead className="bg-zinc-900/70 text-zinc-300">
                      <tr>
                        <th className="px-4 py-3 text-left font-medium">Categoria</th>
                        <th className="px-4 py-3 text-right font-medium whitespace-nowrap w-36">Ação</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {conjuntoCategoriasPreview.map((categoria) => (
                        <tr key={categoria}>
                          <td className="px-4 py-3 text-zinc-100">{categoria}</td>
                          <td className="px-4 py-3 text-right">
                            <button
                              type="button"
                              onClick={() => removeCategoria(categoria)}
                              className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-1.5 text-sm text-zinc-100 hover:bg-zinc-900"
                            >
                              Excluir
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                {!showNovaCategoria && categoriaErr && <div className="mt-3 text-xs text-rose-400">{categoriaErr}</div>}

                <div className="mt-3 text-[11px] leading-5 text-zinc-500">
                  Essa lista sera usada como base fixa no cadastro de conjuntos.
                  {conjuntoCategoriasPreview.length === 1 && " Mantenha ao menos uma categoria ativa."}
                </div>
                <div className="mt-2 text-[11px] leading-5 text-zinc-500">
                  Novas categorias sao salvas em caixa alta e sem duplicidades.
                </div>
              </div>
            </section>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="submit"
              disabled={busy}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm disabled:opacity-60"
            >
              Salvar
            </button>
            <Link
              href="/configuracoes/comercial/condicoes-pagamento"
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
            >
              Condições de Pagamento
            </Link>
          </div>
        </form>
      )}
    </div>
  );
}
