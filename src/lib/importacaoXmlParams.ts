import type { SupabaseClient } from "@supabase/supabase-js";

export type ItemFinalidade = "materia_prima" | "consumo" | "outros" | "imobilizado" | string;

export type ImportacaoXmlParams = {
  allowedAutoCadastrar: Set<ItemFinalidade>;
  allowedVincular: Set<ItemFinalidade>;
};

const FALLBACK_AUTO: ItemFinalidade[] = ["materia_prima"];
const FALLBACK_VINCULAR: ItemFinalidade[] = ["materia_prima"];

const buildFallback = (): ImportacaoXmlParams => ({
  allowedAutoCadastrar: new Set(FALLBACK_AUTO),
  allowedVincular: new Set(FALLBACK_VINCULAR),
});

const cache = new Map<string, Promise<ImportacaoXmlParams> | ImportacaoXmlParams>();

function toStringSet(value: unknown, fallback: ItemFinalidade[]): Set<ItemFinalidade> {
  if (!Array.isArray(value)) return new Set(fallback);
  const out = new Set<ItemFinalidade>();
  for (const v of value) {
    const s = String(v ?? "").trim();
    if (s) out.add(s);
  }
  return out.size ? out : new Set(fallback);
}

export async function getImportacaoXmlParams(
  supabase: SupabaseClient,
  tenantId: string,
  empresaId: string
): Promise<ImportacaoXmlParams> {
  const t = String(tenantId ?? "").trim();
  const e = String(empresaId ?? "").trim();
  if (!t || !e) return buildFallback();

  const key = `${t}:${e}`;
  const cached = cache.get(key);
  if (cached) {
    return cached instanceof Promise ? await cached : cached;
  }

  const pending = (async (): Promise<ImportacaoXmlParams> => {
    try {
      const { data, error } = await supabase
        .schema("public")
        .from("parametro_importacao_xml")
        .select("itens_auto_cadastrar_finalidades,itens_vincular_finalidades")
        .eq("tenant_id", t)
        .eq("empresa_id", e)
        // best-effort: coluna pode não existir em alguns ambientes
        .is("deleted_at", null)
        .limit(1)
        .maybeSingle<{
          itens_auto_cadastrar_finalidades?: unknown;
          itens_vincular_finalidades?: unknown;
        }>();

      if (error || !data) return buildFallback();

      return {
        allowedAutoCadastrar: toStringSet(data.itens_auto_cadastrar_finalidades, FALLBACK_AUTO),
        allowedVincular: toStringSet(data.itens_vincular_finalidades, FALLBACK_VINCULAR),
      };
    } catch {
      return buildFallback();
    }
  })();

  cache.set(key, pending);
  const resolved = await pending;
  cache.set(key, resolved);
  return resolved;
}
