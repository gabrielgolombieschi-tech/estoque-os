import type { SupabaseClient } from "@supabase/supabase-js";
import { buildCanManyPayload, mapCapabilities, type Capabilities } from "./capabilities";
import { ensureCurrentTenant } from "@/lib/tenant";
import { getAllowedEmpresas } from "@/lib/auth/empresa";

type CapResult = { capabilities: Capabilities | null; tenantId: string | null; empresaId: string | null; error?: unknown };

export async function getCapabilities(supabase: SupabaseClient): Promise<CapResult> {
  const payload = buildCanManyPayload();

  let tenantId: string | null = null;
  let empresaId: string | null = null;

  try {
    // Try to read current tenant from RPC first (may be set via JWT/session)
    try {
      const { data: cur, error: curErr } = await supabase.rpc("current_tenant_id");
      if (!curErr && cur) tenantId = String(cur);
    } catch {
      // ignore
    }

    // If tenantId still not present, ensure it (reads user_tenant_context or tenant_memberships)
    if (!tenantId) {
      try {
        tenantId = await ensureCurrentTenant(supabase, tenantId);
      } catch (e) {
        console.warn("ensureCurrentTenant failed:", e);
      }
    }

    // Try to read current empresa via RPC
    try {
      const { data: curEmp, error: curEmpErr } = await supabase.rpc("current_empresa_id");
      if (!curEmpErr && curEmp) empresaId = String(curEmp);
    } catch {
      // ignore
    }

    // If empresaId not present, attempt to pick first allowed empresa for tenant
    if (!empresaId && tenantId) {
      try {
        const empresas = await getAllowedEmpresas(supabase, tenantId);
        if (empresas && empresas.length) {
          empresaId = empresas[0].id;
          // attempt to set on DB context (best-effort)
          try {
            await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
          } catch {
            // ignore set failure
          }
        }
      } catch (e) {
        console.warn("getAllowedEmpresas failed:", e);
      }
    }

    // Ensure tenant set in DB context before calling can_many
    if (tenantId) {
      try {
        await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      } catch {
        // best-effort
      }
    }

    // Diagnostics: log context in dev
    try {
      console.info("[capabilities] resolving context", { tenantId, empresaId });
    } catch {}

    const { data, error } = await supabase.rpc("can_many", { p_pairs: payload });

    if (error) {
      // diagnostics log
      console.error("Erro can_many:", error, { tenantId, empresaId, payload });
      return { capabilities: null, tenantId, empresaId, error };
    }

    // diagnostics
    try {
      console.info("[capabilities] can_many result", { tenantId, empresaId, result: data });
    } catch {}

    const caps = mapCapabilities(data as Record<string, boolean> | null);
    return { capabilities: caps, tenantId, empresaId };
  } catch (e) {
    console.error("getCapabilities unexpected error:", e, { tenantId, empresaId });
    return { capabilities: null, tenantId, empresaId, error: e };
  }
}
