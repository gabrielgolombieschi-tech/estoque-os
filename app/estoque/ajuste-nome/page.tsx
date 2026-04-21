"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";

type ItemNomeRow = {
  id: number;
  codigo_interno: string | null;
  codigo_barras: string | null;
  nome: string | null;
  ativo: boolean | null;
  fornecedor_id: number | null;
  unidade_medida: string | null;
  fornecedores?: { nome: string | null } | null;
};

type Fornecedor = {
  id: number;
  nome: string;
  ativo: boolean;
};

type Filtros = {
  id: string;
  codigo: string;
  produto: string;
  fornecedor: string;
  ativos: "ativos" | "todos";
};

type AjusteContext = {
  id: number;
  codigo: string;
  nomeAtual: string;
  fornecedorNome: string;
};

function normalizeSearchTerm(input: unknown) {
  return String(input ?? "")
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function getFiltrosIniciais(): Filtros {
  return {
    id: "",
    codigo: "",
    produto: "",
    fornecedor: "",
    ativos: "ativos",
  };
}

const ALLOWED_ROLES = ["ADMIN", "FINANCEIRO", "COORDENACAO"] as const;

export default function AjusteNomePage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;
  const tenantEmpresaLoading = te.loading;
  const tenantEmpresaError = te.error;
  const empresaPapel = String(te.empresa?.papel ?? "").trim().toUpperCase();
  const canAccess = ALLOWED_ROLES.includes(empresaPapel as (typeof ALLOWED_ROLES)[number]);

  const [rows, setRows] = useState<ItemNomeRow[]>([]);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [listLoading, setListLoading] = useState(false);
  const [showAjuste, setShowAjuste] = useState(false);
  const [page, setPage] = useState(0);
  const [totalCount, setTotalCount] = useState<number | null>(null);
  const pageSize = 100;

  const filtrosFormRef = useRef<HTMLFormElement | null>(null);
  const codigoInputRef = useRef<HTMLInputElement | null>(null);
  const ajusteItemIdRef = useRef<HTMLInputElement | null>(null);
  const ajusteNovoNomeRef = useRef<HTMLInputElement | null>(null);

  const [draftFiltros, setDraftFiltros] = useState<Filtros>(getFiltrosIniciais);
  const [filtros, setFiltros] = useState<Filtros>(getFiltrosIniciais);

  const [ajusteItemIdText, setAjusteItemIdText] = useState("");
  const [ajusteNomeAtual, setAjusteNomeAtual] = useState("");
  const [ajusteNovoNome, setAjusteNovoNome] = useState("");
  const [ajusteDescricao, setAjusteDescricao] = useState("");

  const itemSelect = useMemo(
    () =>
      "id,codigo_interno,codigo_barras,nome,ativo,fornecedor_id,unidade_medida,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)",
    []
  );

  const fornecedorNomeById = useCallback(
    (id: number | null | undefined) => {
      const parsed = Number(id ?? Number.NaN);
      if (!Number.isFinite(parsed)) return null;
      const nome = fornecedores.find((f) => f.id === parsed)?.nome ?? null;
      const trimmed = String(nome ?? "").trim();
      return trimmed || `#${parsed}`;
    },
    [fornecedores]
  );

  const resetAjuste = useCallback(() => {
    setAjusteItemIdText("");
    setAjusteNomeAtual("");
    setAjusteNovoNome("");
    setAjusteDescricao("");
  }, []);

  const closeAjusteAndFocusCodigo = useCallback(() => {
    setShowAjuste(false);
    resetAjuste();
    setTimeout(() => {
      codigoInputRef.current?.focus();
      codigoInputRef.current?.select?.();
    }, 0);
  }, [resetAjuste]);

  const focusAjusteId = useCallback(() => {
    setTimeout(() => {
      ajusteItemIdRef.current?.focus();
      ajusteItemIdRef.current?.select?.();
    }, 0);
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

  const resolveFornecedorIdsByTerm = useCallback(
    async (termRaw: string): Promise<number[] | null> => {
      const term = normalizeSearchTerm(termRaw);
      if (!term) return null;

      let base = fornecedores;
      if (base.length === 0) {
        if (tenantEmpresaLoading) return [];
        if (!tenantId) return [];
        const { data } = await applyTenant(
          supabase.from("fornecedores").select("id,nome,ativo"),
          tenantId
        )
          .eq("ativo", true)
          .order("nome", { ascending: true })
          .limit(1000);
        base = (data ?? []) as unknown as Fornecedor[];
      }

      return base
        .filter((f) => normalizeSearchTerm(f.nome).includes(term))
        .map((f) => f.id)
        .filter((id) => Number.isFinite(id));
    },
    [fornecedores, supabase, tenantEmpresaLoading, tenantId]
  );

  const load = useCallback(async () => {
    setErr(null);

    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setRows([]);
      setTotalCount(null);
      return;
    }
    if (!canAccess) {
      setRows([]);
      setTotalCount(null);
      return;
    }

    setListLoading(true);
    try {
      let query = applyTenantEmpresa(
        supabase.from("itens").select(itemSelect, { count: "exact" }),
        tenantId,
        empresaId
      )
        .eq("tipo", "produto")
        .eq("controla_estoque", true)
        .order("id", { ascending: false });

      const idParsed = Number(String(filtros.id ?? "").trim());
      if (String(filtros.id ?? "").trim()) {
        if (!Number.isInteger(idParsed) || idParsed <= 0) {
          setErr("Filtro de ID invalido.");
          setRows([]);
          setTotalCount(0);
          return;
        }
        query = query.eq("id", idParsed);
      }

      const codigo = String(filtros.codigo ?? "").trim();
      if (codigo) query = query.ilike("codigo_interno", `%${codigo}%`);

      const produto = String(filtros.produto ?? "").trim();
      if (produto) query = query.ilike("nome", `%${produto}%`);

      if (filtros.ativos === "ativos") query = query.eq("ativo", true);

      const fornecedorIds = await resolveFornecedorIdsByTerm(filtros.fornecedor);
      if (Array.isArray(fornecedorIds)) {
        if (fornecedorIds.length === 0) {
          setRows([]);
          setTotalCount(0);
          return;
        }
        query = query.in("fornecedor_id", fornecedorIds);
      }

      const { data, error, count } = await query.range(page * pageSize, page * pageSize + pageSize - 1);
      if (error) {
        setErr(error.message);
        setRows([]);
        setTotalCount(null);
        return;
      }

      setRows((data ?? []) as unknown as ItemNomeRow[]);
      setTotalCount(typeof count === "number" ? count : null);
    } finally {
      setListLoading(false);
    }
  }, [canAccess, empresaId, filtros, itemSelect, page, pageSize, resolveFornecedorIdsByTerm, supabase, tenantEmpresaLoading, tenantId]);

  const fetchAjusteContext = useCallback(
    async (itemId: number): Promise<AjusteContext | null> => {
      if (tenantEmpresaLoading) return null;
      if (!tenantId || !empresaId) {
        setErr("Tenant ou empresa nao carregados.");
        return null;
      }

      const { data, error } = await applyTenantEmpresa(
        supabase.from("itens").select(itemSelect),
        tenantId,
        empresaId
      )
        .eq("tipo", "produto")
        .eq("controla_estoque", true)
        .eq("id", itemId)
        .maybeSingle();

      if (error) {
        setErr(error.message);
        return null;
      }
      if (!data) {
        setErr("Item nao encontrado para ajuste de nome.");
        return null;
      }

      const row = data as unknown as ItemNomeRow;
      const nomeAtual = String(row.nome ?? "").trim();
      const codigo = String(row.codigo_interno ?? row.codigo_barras ?? "").trim();
      const fornecedorNome =
        String(row.fornecedores?.nome ?? "").trim() ||
        fornecedorNomeById(row.fornecedor_id) ||
        "Sem fornecedor";

      return {
        id: row.id,
        codigo,
        nomeAtual,
        fornecedorNome,
      };
    },
    [empresaId, fornecedorNomeById, itemSelect, supabase, tenantEmpresaLoading, tenantId]
  );

  const preencherAjustePorId = useCallback(
    async (itemId: number) => {
      setErr(null);
      setOk(null);
      const ctx = await fetchAjusteContext(itemId);
      if (!ctx) return false;

      setAjusteItemIdText(String(ctx.id));
      setAjusteNomeAtual(ctx.nomeAtual);
      setAjusteNovoNome(ctx.nomeAtual);
      setAjusteDescricao(`${ctx.codigo || "(sem codigo)"} - ${ctx.fornecedorNome}`);
      return true;
    },
    [fetchAjusteContext]
  );

  const abrirAjustePorLinha = useCallback((row: ItemNomeRow) => {
    setErr(null);
    setOk(null);
    setShowAjuste(true);
    setAjusteItemIdText(String(row.id));
    setAjusteNomeAtual(String(row.nome ?? "").trim());
    setAjusteNovoNome(String(row.nome ?? "").trim());
    const codigo = String(row.codigo_interno ?? row.codigo_barras ?? "").trim() || "(sem codigo)";
    const fornecedorNome =
      String(row.fornecedores?.nome ?? "").trim() ||
      fornecedorNomeById(row.fornecedor_id) ||
      "Sem fornecedor";
    setAjusteDescricao(`${codigo} - ${fornecedorNome}`);
    setTimeout(() => {
      ajusteNovoNomeRef.current?.focus();
      ajusteNovoNomeRef.current?.select?.();
    }, 0);
  }, [fornecedorNomeById]);

  const saveItemName = useCallback(
    async (itemId: number, nextNameRaw: string, currentNameRaw?: string) => {
      setOk(null);
      setErr(null);

      if (!canAccess) {
        setErr("Sem permissao para acessar ajuste de nome.");
        return false;
      }

      const nextName = String(nextNameRaw ?? "").trim();
      const currentName = String(currentNameRaw ?? "").trim();
      if (!nextName) {
        setErr("Informe o novo nome do item.");
        return false;
      }

      if (nextName === currentName) return false;

      if (tenantEmpresaLoading) return false;
      if (!tenantId || !empresaId) {
        setErr("Tenant ou empresa nao carregados.");
        return false;
      }

      setBusy(true);
      try {
        const { error } = await applyTenantEmpresa(
          supabase.from("itens").update({ nome: nextName }),
          tenantId,
          empresaId
        ).eq("id", itemId);

        if (error) {
          setErr(error.message);
          return false;
        }

        setOk(`Nome atualizado no item ${itemId}.`);
        await load();
        return true;
      } finally {
        setBusy(false);
      }
    },
    [canAccess, empresaId, load, supabase, tenantEmpresaLoading, tenantId]
  );

  const salvarAjusteNome = useCallback(async () => {
    const idParsed = Number(String(ajusteItemIdText ?? "").trim());
    if (!Number.isInteger(idParsed) || idParsed <= 0) {
      setErr("Informe um ID de item valido.");
      return;
    }

    const saved = await saveItemName(idParsed, ajusteNovoNome, ajusteNomeAtual);
    if (!saved) {
      ajusteNovoNomeRef.current?.focus();
      ajusteNovoNomeRef.current?.select?.();
      return;
    }

    setAjusteNomeAtual("");
    setAjusteNovoNome("");
    setAjusteDescricao("");
    setAjusteItemIdText("");
    focusAjusteId();
  }, [ajusteItemIdText, ajusteNomeAtual, ajusteNovoNome, focusAjusteId, saveItemName]);

  function InlineTextInput(props: {
    ariaLabel: string;
    value: string;
    disabled?: boolean;
    placeholder?: string;
    onCommit: (value: string) => void | Promise<void>;
  }) {
    const { ariaLabel, value, disabled, placeholder, onCommit } = props;
    const [text, setText] = useState<string>(String(value ?? ""));

    useEffect(() => {
      setText(String(value ?? ""));
    }, [value]);

    const reset = () => setText(String(value ?? ""));

    const commit = async () => {
      const next = String(text ?? "").trim();
      const prev = String(value ?? "").trim();
      if (!next) {
        reset();
        return;
      }
      if (next === prev) return;
      await onCommit(next);
    };

    return (
      <input
        aria-label={ariaLabel}
        type="text"
        className="w-full px-2 py-1 rounded-md border border-zinc-700 bg-zinc-900/40 text-left"
        value={text}
        placeholder={placeholder}
        disabled={disabled}
        onChange={(e) => setText(e.target.value)}
        onFocus={(e) => e.currentTarget.select()}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            void commit();
          }
          if (e.key === "Escape") {
            e.preventDefault();
            reset();
          }
        }}
        onBlur={reset}
      />
    );
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
    const t = setTimeout(() => {
      void load();
    }, 0);
    return () => clearTimeout(t);
  }, [load]);

  useEffect(() => {
    void loadFornecedores();
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

  if (!tenantId || !empresaId) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando contexto...
      </div>
    );
  }

  if (!canAccess) {
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
          <h1 className="text-2xl font-semibold">Ajuste Nome</h1>
          <p className="text-sm text-zinc-400 mt-1">Renomeie itens de estoque na tabela e pressione Enter para confirmar.</p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              setErr(null);
              setOk(null);
              resetAjuste();
              setShowAjuste(true);
            }}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Ajuste nome
          </button>
          <button
            onClick={() => void load()}
            disabled={listLoading}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
          >
            {listLoading ? "Atualizando..." : "Atualizar"}
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

          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Codigo</div>
            <input
              aria-label="Filtrar por codigo"
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
              placeholder="codigo interno"
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
              list="ajuste-nome-fornecedor-options"
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
            <datalist id="ajuste-nome-fornecedor-options">
              {fornecedores.map((f) => (
                <option key={f.id} value={String(f.nome ?? "").trim()} />
              ))}
            </datalist>
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">Ativo</div>
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
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Ajuste Nome</div>
                <div className="text-sm text-zinc-400">ID, nome atual e novo nome (Enter salva)</div>
              </div>
              <button
                onClick={closeAjusteAndFocusCodigo}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
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
                          const found = await preencherAjustePorId(parsed);
                          if (!found) return;
                          ajusteNovoNomeRef.current?.focus();
                          ajusteNovoNomeRef.current?.select?.();
                        })();
                      }
                    }}
                    placeholder="id"
                  />
                </div>

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Nome atual</div>
                  <input
                    aria-label="Nome atual"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/20 text-zinc-300"
                    value={ajusteNomeAtual}
                    readOnly
                    placeholder="Carregue um item pelo ID"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Novo nome</div>
                <input
                  ref={ajusteNovoNomeRef}
                  aria-label="Novo nome"
                  className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
                  value={ajusteNovoNome}
                  onChange={(e) => setAjusteNovoNome(e.target.value)}
                  onFocus={(e) => e.currentTarget.select()}
                  onKeyDown={(e) => {
                    if (e.key === "Escape") {
                      e.preventDefault();
                      closeAjusteAndFocusCodigo();
                      return;
                    }
                    if (e.key === "Enter") {
                      e.preventDefault();
                      void salvarAjusteNome();
                    }
                  }}
                  placeholder="Informe o novo nome"
                />
              </div>

              <div className="text-xs text-zinc-400">{ajusteDescricao || "Codigo e fornecedor do item"}</div>
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
              <button
                onClick={closeAjusteAndFocusCodigo}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={() => void salvarAjusteNome()}
                disabled={busy}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {busy ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">ID</th>
              <th className="px-4 py-3 text-left">Codigo</th>
              <th className="px-4 py-3 text-left">Produto</th>
              <th className="px-4 py-3 text-left">Fornecedor</th>
              <th className="px-4 py-3 text-center">Status</th>
              <th className="px-4 py-3 text-center">Acao</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {rows.map((row) => {
              const fornecedorNome =
                String(row.fornecedores?.nome ?? "").trim() ||
                fornecedorNomeById(row.fornecedor_id) ||
                "Sem fornecedor";

              return (
                <tr key={row.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 text-zinc-300">{row.id}</td>
                  <td className="px-4 py-3 font-medium">{String(row.codigo_interno ?? row.codigo_barras ?? "-")}</td>
                  <td className="px-4 py-3">
                    <InlineTextInput
                      ariaLabel={`Nome item ${row.id}`}
                      value={String(row.nome ?? "")}
                      disabled={busy}
                      placeholder="Nome do item"
                      onCommit={(nextValue) => saveItemName(row.id, nextValue, String(row.nome ?? ""))}
                    />
                    <div className="text-xs text-zinc-400 mt-1">{String(row.unidade_medida ?? "UN")}</div>
                  </td>
                  <td className="px-4 py-3 text-zinc-200">{fornecedorNome}</td>
                  <td className="px-4 py-3 text-center">{row.ativo === false ? "Inativo" : "Ativo"}</td>
                  <td className="px-4 py-3 text-center">
                    <button
                      onClick={() => abrirAjustePorLinha(row)}
                      className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                    >
                      Renomear
                    </button>
                  </td>
                </tr>
              );
            })}

            {rows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-zinc-400">
                  Nenhum item de estoque encontrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between mt-3">
        <div className="text-xs text-zinc-400">
          Pagina {page + 1}
          {typeof totalCount === "number" && totalCount > 0 ? ` de ${Math.ceil(totalCount / pageSize)}` : ""}
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setPage((current) => Math.max(0, current - 1))}
            disabled={page === 0}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
          >
            Anterior
          </button>
          <button
            onClick={() => setPage((current) => current + 1)}
            disabled={typeof totalCount === "number" ? (page + 1) * pageSize >= totalCount : false}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
          >
            Proxima
          </button>
        </div>
      </div>
    </div>
  );
}
