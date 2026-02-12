"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { mapOrcamentoError, n, toSupabaseErrorLike } from "@/lib/comercial/utils";
import { getConfig, ensureConfig, updateConfig } from "@/src/services/configOrcamento";
import { list as listCondicoesPagamento } from "@/src/services/condicaoPagamento";

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

type ConfigForm = {
  margem_lucro_padrao_percent: string;
  desconto_max_percent: string;
  condicao_pagamento_padrao_id: string | null;
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
    desconto_max_percent: "25",
    condicao_pagamento_padrao_id: null,
  });

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
        desconto_max_percent: String(cfg.desconto_max_percent ?? "25"),
        condicao_pagamento_padrao_id: cfg.condicao_pagamento_padrao_id ?? null,
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
      const descontoMax = n(form.desconto_max_percent);
      if (margem < 0 || margem > 100) {
        setErr("Margem padrão deve estar entre 0 e 100.");
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
            desconto_max_percent: descontoMax,
            condicao_pagamento_padrao_id: form.condicao_pagamento_padrao_id ?? null,
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
