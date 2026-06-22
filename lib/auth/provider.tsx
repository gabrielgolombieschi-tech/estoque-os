"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { ensureCurrentTenant } from "@/lib/tenant";
import { ensureEmpresaId, getAllowedEmpresas, setStoredEmpresaId } from "@/lib/auth/empresa";
import { buildCanManyPayload, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import type { EmpresaInfo, TenantEmpresaState } from "@/lib/auth/types";

export type TenantEmpresaContextValue = TenantEmpresaState & {
  providerBuildId: string;
  // Back-compat aliases (older UI used sessionEmail/sessionUserId naming)
  sessionEmail: string | null;
  has: (capability: CapabilityKey) => boolean | undefined;
  reload: (opts?: { reason?: string }) => Promise<void>;
  refreshCapabilities: () => Promise<void>;
  clear: () => void;
  setEmpresaId: (nextEmpresaId: string) => Promise<void>;
};

const TenantEmpresaContext = createContext<TenantEmpresaContextValue | null>(null);
const isDev = process.env.NODE_ENV !== "production";
const PROVIDER_BUILD_ID = "caps-rpc-20260119-213547";
const WINDOW_REVALIDATE_DEBOUNCE_MS = 1000;
const WINDOW_REVALIDATE_STALE_MS = 2 * 60 * 1000;

type CachedTenantEmpresa = {
  tenantId: string;
  empresaId: string;
  empresa: EmpresaInfo | null;
  empresas: EmpresaInfo[];
  updatedAt: number;
};

const CACHE_LAST_TENANT_KEY = "tenant_empresa:last_tenant";
const cacheKeyFor = (userId: string, tenantId: string) => `tenant_empresa:${userId}:${tenantId}`;
const lastTenantKeyFor = (userId: string) => `${CACHE_LAST_TENANT_KEY}:${userId}`;

function safeJsonParse<T>(raw: string | null): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function normalizeEmpresaPapel(papel: string | null | undefined): string {
  return typeof papel === "string" ? papel.trim().toUpperCase() : "";
}

function isPainelTvEmpresaRole(state: TenantEmpresaState): boolean {
  const papel =
    state.empresa?.papel ?? state.empresas.find((e) => e.id === state.empresaId)?.papel ?? null;
  return normalizeEmpresaPapel(papel) === "PAINEL_TV";
}

function readCached(userId: string, tenantId: string): CachedTenantEmpresa | null {
  if (typeof window === "undefined") return null;
  return safeJsonParse<CachedTenantEmpresa>(window.sessionStorage.getItem(cacheKeyFor(userId, tenantId)));
}

function writeCached(userId: string, tenantId: string, value: CachedTenantEmpresa) {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(cacheKeyFor(userId, tenantId), JSON.stringify(value));
    window.sessionStorage.setItem(lastTenantKeyFor(userId), tenantId);
  } catch {
    // ignore
  }
}

function readLastTenantId(userId: string): string | null {
  if (typeof window === "undefined") return null;
  return window.sessionStorage.getItem(lastTenantKeyFor(userId));
}

function isMissingRpc(error: unknown, rpcName: string) {
  const message =
    typeof error === "object" && error !== null && "message" in error
      ? String((error as { message?: unknown }).message ?? "")
      : String(error ?? "");
  return message.toLowerCase().includes(`could not find the function public.${rpcName}`);
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
  try {
    return await Promise.race<T>([
      promise,
      new Promise<T>((_, reject) => {
        timeoutHandle = setTimeout(() => reject(new Error("timeout")), timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutHandle) clearTimeout(timeoutHandle);
  }
}

async function rpcCurrentTenantId(supabase: ReturnType<typeof getSupabaseBrowser>): Promise<string | null> {
  try {
    const { data, error } = await supabase.rpc("current_tenant_id");
    if (error) return null;
    return data ? String(data) : null;
  } catch {
    return null;
  }
}

async function rpcSetCurrentTenant(supabase: ReturnType<typeof getSupabaseBrowser>, tenantId: string) {
  try {
    const { error } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
    if (error && !isMissingRpc(error, "set_current_tenant")) {
      if (isDev) console.debug("[TENANT] set_current_tenant error", { message: error.message });
    }
  } catch {
    // ignore
  }
}

async function rpcCurrentEmpresaId(supabase: ReturnType<typeof getSupabaseBrowser>): Promise<string | null> {
  try {
    const { data, error } = await supabase.rpc("current_empresa_id");
    if (error) return null;
    return data ? String(data) : null;
  } catch {
    return null;
  }
}

async function rpcSetCurrentEmpresa(supabase: ReturnType<typeof getSupabaseBrowser>, empresaId: string) {
  try {
    const { error } = await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
    if (error && !isMissingRpc(error, "set_current_empresa")) {
      if (isDev) console.debug("[TENANT] set_current_empresa error", { message: error.message });
    }
  } catch {
    // ignore
  }
}

type EmpresaMembershipJoinedRow = {
  empresa_id: string | null;
  tenant_id: string | null;
  role?: string | null;
  empresas?:
    | {
        id: string | null;
        tenant_id: string | null;
        nome_fantasia: string | null;
        razao_social: string | null;
        ativo: boolean | null;
      }
    | null;
};

type UsuarioIdRow = { id: string };
type UsuarioEmpresaRoleRow = { empresa_id: string; papel: string | null };

async function loadEmpresasForUser(userId: string): Promise<EmpresaInfo[]> {
  const supabase = getSupabaseBrowser();

  const { data, error } = await supabase
    .from("empresa_memberships")
    .select("empresa_id, tenant_id, role, empresas:empresa_id(id, tenant_id, nome_fantasia, razao_social, ativo)")
    .eq("user_id", userId)
    .eq("status", "active");

  if (error) throw error;

  const rows = (data ?? []) as unknown as EmpresaMembershipJoinedRow[];
  const mapped = rows
    .map((row) => {
      const e = row.empresas ?? null;
      const id = e?.id ?? row.empresa_id;
      const tenantId = e?.tenant_id ?? row.tenant_id;
      if (!id || !tenantId) return null;
      if (e?.ativo === false) return null;
      const papelFromMembership = typeof row.role === "string" ? row.role : null;
      const empresa: EmpresaInfo = {
        id: String(id),
        tenant_id: String(tenantId),
        nome_fantasia: e?.nome_fantasia ?? null,
        razao_social: e?.razao_social ?? null,
        cnpj: null,
        ativo: e?.ativo ?? null,
        papel: papelFromMembership,
      };
      return empresa;
    })
    .filter((v): v is EmpresaInfo => v !== null);

  const unique = new Map<string, EmpresaInfo>();
  for (const e of mapped) unique.set(e.id, e);

  // Best-effort: enrich empresa list with membership role (a.usuario_empresa.papel)
  try {
    const empresas = Array.from(unique.values());
    const empresaIds = empresas.map((e) => e.id);
    if (!empresaIds.length) return empresas;

    const { data: usuario } = await supabase
      .schema("a")
      .from("usuario")
      .select("id")
      .eq("auth_user_id", userId)
      .is("deleted_at", null)
      .maybeSingle<UsuarioIdRow>();

    const usuarioId = usuario?.id ? String(usuario.id) : null;
    if (!usuarioId) return empresas;

    const { data: roles } = await supabase
      .schema("a")
      .from("usuario_empresa")
      .select("empresa_id,papel")
      .eq("usuario_id", usuarioId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .in("empresa_id", empresaIds)
      .returns<UsuarioEmpresaRoleRow[]>();

    const papelById = new Map<string, string | null>();
    for (const r of roles ?? []) {
      if (!r?.empresa_id) continue;
      papelById.set(String(r.empresa_id), r.papel ? String(r.papel) : null);
    }

    return empresas.map((e) => ({ ...e, papel: papelById.get(e.id) ?? null }));
  } catch {
    return Array.from(unique.values());
  }
}

function getEmpresaStorageKeyForUser(userId: string) {
  return `erp_empresa_id:${userId}`;
}

function readStoredEmpresaIdForUser(userId: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(getEmpresaStorageKeyForUser(userId));
  } catch {
    return null;
  }
}

function writeStoredEmpresaIdForUser(userId: string, empresaId: string) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(getEmpresaStorageKeyForUser(userId), empresaId);
  } catch {
    // ignore
  }
}

async function deriveTenantIdFromEmpresaId(
  supabase: ReturnType<typeof getSupabaseBrowser>,
  empresaId: string
): Promise<string | null> {
  try {
    const { data, error } = await supabase
      .schema("c")
      .from("empresa")
      .select("tenant_id")
      .eq("id", empresaId)
      .is("deleted_at", null)
      .maybeSingle();
    if (error) return null;
    const row = data as { tenant_id?: unknown } | null;
    return row?.tenant_id ? String(row.tenant_id) : null;
  } catch {
    return null;
  }
}

type LegacyEmpresaMembershipRow = { tenant_id: string | null; empresa_id: string | null };

async function readLegacyEmpresaMemberships(
  supabase: ReturnType<typeof getSupabaseBrowser>,
  userId: string
): Promise<{ tenantIds: string[]; empresaIds: string[] }> {
  try {
    const { data, error } = await supabase
      .from("empresa_memberships")
      .select("tenant_id,empresa_id")
      .eq("user_id", userId)
      .eq("status", "active");
    if (error) return { tenantIds: [], empresaIds: [] };

    const rows = (data ?? []) as LegacyEmpresaMembershipRow[];
    const tenantIds = Array.from(new Set(rows.map((r) => (r.tenant_id ? String(r.tenant_id) : null)).filter(Boolean))) as string[];
    const empresaIds = Array.from(new Set(rows.map((r) => (r.empresa_id ? String(r.empresa_id) : null)).filter(Boolean))) as string[];
    return { tenantIds, empresaIds };
  } catch {
    return { tenantIds: [], empresaIds: [] };
  }
}

async function fetchEmpresasByIdsInTenant(
  supabase: ReturnType<typeof getSupabaseBrowser>,
  tenantId: string,
  empresaIds: string[]
): Promise<EmpresaInfo[]> {
  if (!empresaIds.length) return [];

  try {
    const { data, error } = await supabase
      .schema("c")
      .from("empresa")
      .select("id,tenant_id,nome_fantasia,razao_social,cnpj,ativo,deleted_at")
      .eq("tenant_id", tenantId)
      .is("deleted_at", null)
      .in("id", empresaIds)
      .order("nome_fantasia", { ascending: true });
    if (error) return [];

    type EmpresaRow = {
      id?: unknown;
      tenant_id?: unknown;
      nome_fantasia?: string | null;
      razao_social?: string | null;
      cnpj?: string | null;
      ativo?: boolean | null;
    };

    return (data ?? [])
      .map((r) => r as EmpresaRow)
      .filter((r) => r?.ativo !== false)
      .map((r) => ({
        id: String(r.id),
        tenant_id: String(r.tenant_id ?? tenantId),
        nome_fantasia: r.nome_fantasia ?? null,
        razao_social: r.razao_social ?? null,
        cnpj: r.cnpj ?? null,
        ativo: r.ativo ?? null,
        papel: null,
      }));
  } catch {
    return [];
  }
}

type UserPermissionRow = { permission: string | null };

async function loadCapabilitiesFromRpc(
  supabase: ReturnType<typeof getSupabaseBrowser>,
  tenantId: string,
  empresaId: string | null = null
): Promise<{
  caps: Capabilities;
  count: number;
  raw: (string | null)[];
  uniq: string[];
  errorMessage?: string;
}> {
  try {
    // Ensure DB context best-effort so can_many()/can() can evaluate permissions.
    // `public.can` uses current_tenant_id(), so without setting tenant this can return false.
    const resolvedEmpresaIdForContext = empresaId ?? (await rpcCurrentEmpresaId(supabase));
    try {
      await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
    } catch {
      // ignore
    }
    if (resolvedEmpresaIdForContext) {
      try {
        await supabase.rpc("set_current_empresa", { p_empresa_id: resolvedEmpresaIdForContext });
      } catch {
        // ignore
      }
    }

    // Some environments may have an overloaded `get_my_permissions` RPC:
    // - get_my_permissions(p_tenant_id uuid)
    // - get_my_permissions(p_tenant_id uuid, p_empresa_id uuid)
    // When both exist, calling with only `p_tenant_id` can become ambiguous.
    // Prefer the 2-arg signature (when available) and fall back to the 1-arg one.
    const resolvedEmpresaId = resolvedEmpresaIdForContext;

    let { data, error } = await supabase.rpc("get_my_permissions", {
      p_tenant_id: tenantId,
      p_empresa_id: resolvedEmpresaId,
    });

    if (error && isMissingRpc(error, "get_my_permissions")) {
      const retry = await supabase.rpc("get_my_permissions", { p_tenant_id: tenantId });
      data = retry.data;
      error = retry.error;
    }
    const count = Array.isArray(data) ? data.length : 0;
    const rows = (data ?? []) as unknown as UserPermissionRow[];
    const raw = rows.map((r) => (typeof r?.permission === "string" ? r.permission : null));
    const perms = raw
      .filter((p): p is string => typeof p === "string" && p.length > 0)
      .map((p) => p.trim())
      .filter((p) => p.length > 0);
    const uniq = Array.from(new Set(perms)).sort();

    if (error) {
      return { caps: {}, count, raw, uniq, errorMessage: error.message ?? "Erro ao carregar permissões." };
    }

    // IMPORTANT: keep all permissions returned by the RPC (no allowlist/filters here).
    // Build capabilities strictly from the unique list, then add aliases (never remove keys).
    const caps: Record<string, boolean> = Object.create(null);
    for (const perm of uniq) caps[perm] = true;

    // Some environments now use role_access_rules + public.can/can_many as the source of truth.
    // `get_my_permissions` may still be legacy and miss newer capability keys.
    // Merge can_many() results (best-effort) so UI can gate on new keys like xml_import_faturamento.execute.
    try {
      const { data: canManyData, error: canManyErr } = await supabase.rpc("can_many", {
        p_pairs: buildCanManyPayload(),
      });
      if (!canManyErr && canManyData && typeof canManyData === "object") {
        for (const [key, value] of Object.entries(canManyData as Record<string, unknown>)) {
          caps[key] = Boolean(value);
        }
      }
    } catch {
      // ignore missing can_many / permission errors
    }

    // Legacy permission codes (role_permissions) -> current UI capability keys (CapabilityKey list).
    // Keep the original permission codes in the map (for debugging), and add derived capability keys.
    const hasPerm = (code: string) => Boolean(caps[code]);

    // OS / Projetos
    if (hasPerm("projetos.view")) caps["os.read"] = true;

    // Estoque / Itens / Movimentações
    if (
      hasPerm("estoque.view") ||
      hasPerm("movimentacoes.view") ||
      hasPerm("itens.view") ||
      hasPerm("fornecedores.create") ||
      hasPerm("itens.create") ||
      hasPerm("estoque.ajuste.create")
    ) {
      caps["estoque.read"] = true;
    }
    if (hasPerm("estoque.ajuste.create")) caps["estoque.write"] = true;

    // Cadastros
    if (hasPerm("itens.create")) caps["cad_itens.write"] = true;
    if (hasPerm("fornecedores.create")) caps["cad_fornecedores.write"] = true;

    // Fiscal / XML
    if (hasPerm("nf_entrada.import")) caps["xml_import.execute"] = true;
    if (hasPerm("fiscal.edit")) {
      caps["fiscal_nf.read"] = true;
      caps["fiscal_nf.write"] = true;
      caps["fiscal_itens.write"] = true;
    }

    // Financeiro
    if (hasPerm("financeiro.gerenciar")) {
      caps["financeiro.read"] = true;
      caps["financeiro.write"] = true;
      caps["financeiro.delete"] = true;
      caps["financeiro.config"] = true;
    }

    // Apontamentos (legacy)
    if (hasPerm("apontamentos.lancar")) {
      caps["apontamentos.read"] = true;
      caps["apontamentos.write"] = true;
    }
    if (hasPerm("apontamentos.config")) caps["apontamentos.config"] = true;

    if (isDev) Object.freeze(caps);
    return { caps, count, raw, uniq };
  } catch (e) {
    const message = e instanceof Error ? e.message : "Erro inesperado ao carregar permissões.";
    return { caps: {}, count: 0, raw: [], uniq: [], errorMessage: message };
  }
}

export function TenantEmpresaProvider(props: {
  children: ReactNode;
  initialCapabilities?: Capabilities | null;
  initialTenantId?: string | null;
}) {
  const { children, initialTenantId = null } = props;
  const router = useRouter();
  const supabaseRef = useRef<ReturnType<typeof getSupabaseBrowser> | null>(null);
  const capsRequestIdRef = useRef(0);
  const lastCapsKeyRef = useRef<string | null>(null);

  const [state, setState] = useState<TenantEmpresaState>({
    sessionUserId: undefined,
    email: null,
    tenantId: initialTenantId,
    empresaId: null,
    empresas: [],
    empresa: null,
    capabilities: null,
    lastLoadPermissions: [],
    lastLoadPermissionsRaw: [],
    lastLoadSource: null,
    lastLoadCount: 0,
    lastLoadError: null,
    loading: true,
    refreshing: false,
    error: null,
  });

  const stateRef = useRef(state);
  useEffect(() => {
    stateRef.current = state;
  }, [state]);

  const lastCapsKeysLenRef = useRef<number | null>(null);
  useEffect(() => {
    if (!isDev) return;
    const caps = state.capabilities;
    if (caps === null) return;
    const keysLen = Object.keys(caps).length;
    if (lastCapsKeysLenRef.current !== null && keysLen < lastCapsKeysLenRef.current) {
      console.warn("[Caps] WARNING capabilities keys decreased", {
        buildId: PROVIDER_BUILD_ID,
        from: lastCapsKeysLenRef.current,
        to: keysLen,
      });
    }
    lastCapsKeysLenRef.current = keysLen;
  }, [state.capabilities]);

  useEffect(() => {
    if (!isDev) return;
    const caps = state.capabilities;
    if (caps === null) return;
    if (!state.lastLoadPermissions.length) return;
    const keysLen = Object.keys(caps).length;
    const uniqLen = state.lastLoadPermissions.length;
    if (keysLen >= uniqLen) return;
    const missing = state.lastLoadPermissions.filter((p) => !(p in caps));
    console.warn("[Caps] WARNING capabilities missing perms from lastLoadPermissions", {
      buildId: PROVIDER_BUILD_ID,
      uniqLen,
      keysLen,
      missingCount: missing.length,
      missingPreview: missing.slice(0, 30),
    });
  }, [state.capabilities, state.lastLoadPermissions]);

  const inflightRef = useRef<Promise<void> | null>(null);
  const requestIdRef = useRef(0);
  const lastRevalidateRef = useRef<number>(0);
  const lastContextSyncAtRef = useRef<number>(0);
  const permissionScopeRef = useRef<{ tenantId: string | null; empresaId: string | null }>({
    tenantId: null,
    empresaId: null,
  });

  const has = useCallback(
    (capability: CapabilityKey) => {
      if (state.capabilities === null) return undefined;

      if (isPainelTvEmpresaRole(state)) {
        if (capability === "os.read" || capability === "os_rpcs.execute") return true;
        if (capability.endsWith(".write") || capability.endsWith(".delete") || capability.endsWith(".config")) {
          return false;
        }
        if (capability === "xml_import.execute") return false;
        if (capability === "admin.manage_users" || capability === "admin.users.manage") return false;
      }

      if (normalizeEmpresaPapel(state.empresa?.papel) === "TECNICO") {
        if (capability === "apontamentos.read" || capability === "apontamentos.write") return true;
      }

      return state.capabilities[capability] ?? false;
    },
    [state]
  );

  const clear = useCallback(() => {
    if (isDev) console.debug("[TENANT] clear()");
    lastCapsKeyRef.current = null;
    capsRequestIdRef.current++;
    permissionScopeRef.current = { tenantId: null, empresaId: null };
    setState((prev) => ({
      ...prev,
      sessionUserId: null,
      email: null,
      tenantId: null,
      empresaId: null,
      empresas: [],
      empresa: null,
      capabilities: null,
      lastLoadPermissions: [],
      lastLoadPermissionsRaw: [],
      lastLoadSource: null,
      lastLoadCount: 0,
      lastLoadError: null,
      loading: false,
      refreshing: false,
      error: null,
    }));
  }, []);

  const hydrateFromCache = useCallback(
    (userId: string) => {
      const lastTenantId = readLastTenantId(userId);
      const cacheTenantId = lastTenantId ?? initialTenantId ?? null;
      if (!cacheTenantId) return false;

      const cached = readCached(userId, cacheTenantId);
      if (!cached) return false;

      setState((prev) => ({
        ...prev,
        tenantId: cached.tenantId,
        empresaId: cached.empresaId,
        empresas: cached.empresas ?? [],
        empresa: cached.empresa,
        loading: false,
        error: null,
      }));

      permissionScopeRef.current = { tenantId: cached.tenantId, empresaId: cached.empresaId };
      return true;
    },
    [initialTenantId]
  );

  const revalidate = useCallback(
    async (opts: { background: boolean; reason: string; userId?: string | null }) => {
      if (inflightRef.current) return inflightRef.current;

      const run = (async () => {
        const supabase = supabaseRef.current ?? (supabaseRef.current = getSupabaseBrowser());
        const requestId = ++requestIdRef.current;
        const isStale = () => requestIdRef.current !== requestId;

        const { background, reason } = opts;
        const userId = opts.userId ?? state.sessionUserId;
        if (userId === undefined) return;
        if (!userId) {
          clear();
          return;
        }

        setState((prev) => ({
          ...prev,
          loading: background ? prev.loading : true,
          refreshing: background ? true : prev.refreshing,
          error: null,
        }));

        try {
          const cachedTenantId = readLastTenantId(userId) ?? initialTenantId ?? state.tenantId ?? null;
          let ensuredTenantId =
            (await rpcCurrentTenantId(supabase)) ??
            (await ensureCurrentTenant(supabase, cachedTenantId, { authUserId: userId }));

          // Fallback 1: derive tenant via current empresa context.
          if (!ensuredTenantId) {
            const curEmpresaId = await rpcCurrentEmpresaId(supabase);
            if (curEmpresaId) {
              const derived = await deriveTenantIdFromEmpresaId(supabase, curEmpresaId);
              if (derived) ensuredTenantId = derived;
            }
          }

          // Fallback 2: legacy empresa_memberships has tenant_id.
          if (!ensuredTenantId) {
            const legacy = await readLegacyEmpresaMemberships(supabase, userId);
            if (legacy.tenantIds.length === 1) ensuredTenantId = legacy.tenantIds[0];
          }

          if (isStale()) return;
          if (!ensuredTenantId) {
            setState((prev) => ({ ...prev, error: "Nao foi possivel resolver tenant atual." }));
            return;
          }

          // Best-effort: don't block UI on RPC context setters.
          try {
            await withTimeout(rpcSetCurrentTenant(supabase, ensuredTenantId), 1500);
          } catch {
            // ignore timeout/errors; RLS may still work depending on policies/JWT.
          }
          if (isStale()) return;

          let allowed: EmpresaInfo[] = [];
          try {
            allowed = await getAllowedEmpresas(supabase, ensuredTenantId);
          } catch (e) {
            if (isDev) console.debug("[TENANT] getAllowedEmpresas failed (will try legacy fallback)", e);
            allowed = [];
          }
          if (isStale()) return;

          // If the new schema membership table is empty, try legacy empresa_memberships for this tenant.
          if (!allowed.length) {
            const legacy = await readLegacyEmpresaMemberships(supabase, userId);
            const empresasFromLegacy = await fetchEmpresasByIdsInTenant(supabase, ensuredTenantId, legacy.empresaIds);
            if (empresasFromLegacy.length) allowed = empresasFromLegacy;
          }

          const empresas = allowed;
          if (!empresas.length) {
            setState((prev) => ({ ...prev, error: "Sem acesso a empresas. Fale com o admin." }));
            return;
          }

          const rpcEmpresaId = await rpcCurrentEmpresaId(supabase);
          const fromRpc = rpcEmpresaId && empresas.some((e) => e.id === rpcEmpresaId) ? rpcEmpresaId : null;
          const storedPerUser = readStoredEmpresaIdForUser(userId);
          const fromStoredPerUser = storedPerUser && empresas.some((e) => e.id === storedPerUser) ? storedPerUser : null;
          const autoSingle = empresas.length === 1 ? empresas[0].id : null;
          const empresaId =
            fromRpc ?? fromStoredPerUser ?? autoSingle ?? (await ensureEmpresaId(supabase, ensuredTenantId, empresas));

          if (isStale()) return;
          setStoredEmpresaId(empresaId);
          writeStoredEmpresaIdForUser(userId, empresaId);

          const empresa = empresas.find((e) => e.id === empresaId) ?? null;

          // Commit tenant/empresa immediately (avoid "Empresa: Carregando..." while permissions load).
          setState((prev) => ({
            ...prev,
            tenantId: ensuredTenantId,
            empresaId,
            empresas,
            empresa,
            loading: false,
            refreshing: true,
            error: null,
          }));

          // Ensure DB context (best-effort), then permissions.
          try {
            await withTimeout(rpcSetCurrentEmpresa(supabase, empresaId), 1500);
          } catch {
            // ignore
          }
          if (isStale()) return;

          setState((prev) => ({
            ...prev,
            tenantId: ensuredTenantId,
            empresaId,
            empresas,
            empresa,
            loading: false,
            refreshing: false,
            error: null,
          }));

          writeCached(userId, ensuredTenantId, {
            tenantId: ensuredTenantId,
            empresaId,
            empresa,
            empresas,
            updatedAt: Date.now(),
          });
          lastContextSyncAtRef.current = Date.now();

          if (isDev) console.debug("[TENANT] revalidated", { reason, tenantId: ensuredTenantId, empresaId });
        } catch (e: unknown) {
          const message = e instanceof Error ? e.message : "Erro ao carregar contexto.";
          setState((prev) => ({ ...prev, loading: false, refreshing: false, error: message }));
        } finally {
          if (!isStale()) {
            setState((prev) => ({ ...prev, loading: false, refreshing: false }));
          }
        }
      })();

      inflightRef.current = run.finally(() => {
        if (inflightRef.current === run) inflightRef.current = null;
      });

      return inflightRef.current;
    },
    [clear, initialTenantId, state.sessionUserId, state.tenantId]
  );

  const reload = useCallback(
    async (opts?: { reason?: string }) => {
      await revalidate({ background: true, reason: opts?.reason ?? "reload" });
    },
    [revalidate]
  );

  const refreshCapabilities = useCallback(async () => {
    const tenantId = state.tenantId;

    if (isDev) console.log("[Caps] FORCE rpc", { tenantId, buildId: PROVIDER_BUILD_ID });

    lastCapsKeyRef.current = null;
    capsRequestIdRef.current++;
    const requestId = capsRequestIdRef.current;

    setState((prev) => ({
      ...prev,
      capabilities: null,
      refreshing: true,
      error: null,
      lastLoadPermissions: [],
      lastLoadPermissionsRaw: [],
      lastLoadSource: "rpc",
      lastLoadCount: 0,
      lastLoadError: null,
    }));

    const supabase = supabaseRef.current ?? (supabaseRef.current = getSupabaseBrowser());
    const res = tenantId
      ? await withTimeout(loadCapabilitiesFromRpc(supabase, tenantId, stateRef.current.empresaId), 5000).catch((e) => ({
          caps: {},
          count: 0,
          raw: [],
          uniq: [],
          errorMessage: e instanceof Error ? e.message : "Erro inesperado ao carregar permissões.",
        }))
      : { caps: {}, count: 0, raw: [], uniq: [], errorMessage: "tenantId missing" };

    if (capsRequestIdRef.current !== requestId) return;

    if (isDev) {
      console.log("[Caps] rpc raw sample", res.raw.slice(0, 30));
      console.log("[Caps] rpc uniq count", res.uniq.length, res.uniq);
    }

    if (res.errorMessage) {
      if (isDev) console.warn("[Caps] error", res.errorMessage);
    } else {
      if (isDev) console.log("[Caps] rpc loaded count", { count: res.count });
    }

    if (isDev) {
      const expectedKeys = Object.keys(res.caps).length;
      setTimeout(() => {
        const current = stateRef.current.capabilities;
        const currentKeys = current === null ? null : Object.keys(current).length;
        console.log("[Caps] state keys should be", expectedKeys, {
          buildId: PROVIDER_BUILD_ID,
          currentKeys,
          lastLoadPermissionsLen: stateRef.current.lastLoadPermissions.length,
        });
      }, 0);
    }

    setState((prev) => ({
      ...prev,
      capabilities: res.caps,
      refreshing: false,
      lastLoadPermissions: res.uniq,
      lastLoadPermissionsRaw: res.raw,
      lastLoadSource: "rpc",
      lastLoadCount: res.count,
      lastLoadError: res.errorMessage ? String(res.errorMessage) : null,
      error: res.errorMessage ? String(res.errorMessage) : prev.error,
    }));
  }, [state.tenantId]);

  // Capabilities: load via RPC get_my_permissions for the current tenant/empresa.
  // Null means "loading"; after that it's always an object (possibly empty).
  const sessionUserId = state.sessionUserId;
  const tenantId = state.tenantId;
  const empresaId = state.empresaId;
  useEffect(() => {
    if (sessionUserId === null) {
      lastCapsKeyRef.current = null;
      capsRequestIdRef.current++;
      return;
    }

    // Avoid calling permissions RPC before the empresa context is known.
    // In DBs where `get_my_permissions` is overloaded (tenant-only + tenant+empresa),
    // calling before we have an empresa can be ambiguous and poison the cached key.
    if (!sessionUserId || !tenantId || !empresaId) return;

    const key = `${sessionUserId}:${tenantId}:${empresaId}`;
    if (lastCapsKeyRef.current === key) return;
    lastCapsKeyRef.current = key;

    capsRequestIdRef.current++;
    const requestId = capsRequestIdRef.current;

    setState((prev) => ({
      ...prev,
      capabilities: null,
      lastLoadPermissions: [],
      lastLoadPermissionsRaw: [],
      lastLoadSource: "rpc",
      lastLoadCount: 0,
      lastLoadError: null,
    }));

    if (isDev) console.log("[Caps] rpc trigger", { sessionUserId, tenantId });

    let cancelled = false;
    const run = async () => {
      const supabase = supabaseRef.current ?? (supabaseRef.current = getSupabaseBrowser());

      setState((prev) => ({
        ...prev,
        refreshing: true,
        error: null,
        lastLoadPermissions: [],
        lastLoadPermissionsRaw: [],
        lastLoadSource: "rpc",
        lastLoadCount: 0,
        lastLoadError: null,
      }));

      const res = await withTimeout(loadCapabilitiesFromRpc(supabase, tenantId, stateRef.current.empresaId), 5000).catch((e) => ({
        caps: {},
        count: 0,
        raw: [],
        uniq: [],
        errorMessage: e instanceof Error ? e.message : "Erro inesperado ao carregar permissões.",
      }));

      if (cancelled || capsRequestIdRef.current !== requestId) return;

      if (isDev) {
        console.log("[Caps] rpc raw sample", res.raw.slice(0, 30));
        console.log("[Caps] rpc uniq count", res.uniq.length, res.uniq);
      }

      if (res.errorMessage) {
        if (isDev) console.warn("[Caps] error", res.errorMessage);
      } else {
        if (isDev) console.log("[Caps] rpc loaded count", { count: res.count });
      }

      setState((prev) => ({
        ...prev,
        capabilities: res.caps,
        refreshing: false,
        lastLoadPermissions: res.uniq,
        lastLoadPermissionsRaw: res.raw,
        lastLoadSource: "rpc",
        lastLoadCount: res.count,
        lastLoadError: res.errorMessage ? String(res.errorMessage) : null,
        error: res.errorMessage ? String(res.errorMessage) : prev.error,
      }));

      if (isDev) {
        const expectedKeys = Object.keys(res.caps).length;
        setTimeout(() => {
          const current = stateRef.current.capabilities;
          const currentKeys = current === null ? null : Object.keys(current).length;
          console.log("[Caps] state keys should be", expectedKeys, {
            buildId: PROVIDER_BUILD_ID,
            currentKeys,
            lastLoadPermissionsLen: stateRef.current.lastLoadPermissions.length,
          });
        }, 0);
      }
    };

    void run();

    return () => {
      cancelled = true;
    };
  }, [sessionUserId, tenantId, empresaId]);

  const setEmpresaId = useCallback(
    async (nextEmpresaId: string) => {
      const supabase = supabaseRef.current ?? (supabaseRef.current = getSupabaseBrowser());
      if (!nextEmpresaId) return;
      if (nextEmpresaId === state.empresaId) return;
      if (!state.tenantId) return;
      if (!state.empresas.some((e) => e.id === nextEmpresaId)) {
        setState((prev) => ({ ...prev, error: "Sem acesso a esta empresa." }));
        return;
      }

      setStoredEmpresaId(nextEmpresaId);
      if (typeof state.sessionUserId === "string") {
        writeStoredEmpresaIdForUser(state.sessionUserId, nextEmpresaId);
      }
      setState((prev) => ({
        ...prev,
        empresaId: nextEmpresaId,
        empresa: prev.empresas.find((e) => e.id === nextEmpresaId) ?? null,
        error: null,
      }));

      await rpcSetCurrentEmpresa(supabase, nextEmpresaId);
      permissionScopeRef.current = { tenantId: state.tenantId, empresaId: nextEmpresaId };
      void revalidate({ background: true, reason: "setEmpresaId" });
      router.refresh();
    },
    [revalidate, router, state.empresaId, state.empresas, state.sessionUserId, state.tenantId]
  );

  // Boot: getSession once + subscribe
  useEffect(() => {
    let active = true;

    const boot = async () => {
      const supabase = supabaseRef.current ?? (supabaseRef.current = getSupabaseBrowser());
      const { data, error } = await supabase.auth.getSession();
      if (!active) return;
      if (error) {
        setState((prev) => ({ ...prev, sessionUserId: null, email: null, loading: false, error: error.message }));
        return;
      }

      const session = data.session;
      const userId = session?.user?.id ?? null;
      const email = session?.user?.email ?? null;
      setState((prev) => ({ ...prev, sessionUserId: userId, email }));

      if (!userId) {
        setState((prev) => ({ ...prev, loading: false, refreshing: false }));
        return;
      }

      if (isDev) console.log("[TenantEmpresa] sessionUserId", userId);

      const hydrated = hydrateFromCache(userId);

      try {
        const empresas = await loadEmpresasForUser(userId);
        if (!active) return;
        if (isDev) console.log("[TenantEmpresa] memberships loaded", empresas.length);
        if (isDev) console.log("[TenantEmpresa] empresas mapped", empresas.map((e) => ({ id: e.id, tenant_id: e.tenant_id })));

        const stored = readStoredEmpresaIdForUser(userId);
        const storedMatch = stored && empresas.some((e) => e.id === stored) ? stored : null;
        const autoSingle = empresas.length === 1 ? empresas[0].id : null;

        setState((prev) => {
          const currentMatch = prev.empresaId && empresas.some((e) => e.id === prev.empresaId) ? prev.empresaId : null;
          const nextEmpresaId = currentMatch ?? storedMatch ?? (prev.empresaId ? null : autoSingle);
          const empresa = nextEmpresaId ? empresas.find((e) => e.id === nextEmpresaId) ?? null : null;
          const nextTenantId = empresa?.tenant_id ?? (empresas.length === 1 ? empresas[0].tenant_id : prev.tenantId);

          return {
            ...prev,
            tenantId: nextTenantId ?? prev.tenantId,
            empresas,
            empresaId: nextEmpresaId ?? prev.empresaId,
            empresa: empresa ?? prev.empresa,
            loading: false,
            error: null,
          };
        });

        const chosen = storedMatch ?? autoSingle;
        if (chosen) {
          setStoredEmpresaId(chosen);
          writeStoredEmpresaIdForUser(userId, chosen);
        }
      } catch (e: unknown) {
        if (!active) return;
        setState((prev) => ({
          ...prev,
          loading: false,
          error: e instanceof Error ? e.message : "Erro ao carregar empresas.",
        }));
      } finally {
        if (!active) return;
        // Always kick a background revalidate to set DB context + capabilities.
        void revalidate({ background: true, reason: hydrated ? "init:hydrated" : "init", userId });
      }
    };

    void boot();

    const supabase = supabaseRef.current ?? (supabaseRef.current = getSupabaseBrowser());
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (!active) return;
      if (isDev) console.debug("[AUTH] event", { event, hasSession: Boolean(session) });

      if (event === "SIGNED_OUT") {
        clear();
        return;
      }

      if (event === "SIGNED_IN" || event === "USER_UPDATED") {
        const userId = session?.user?.id ?? null;
        const email = session?.user?.email ?? null;
        setState((prev) => ({ ...prev, sessionUserId: userId, email }));
        if (userId) void revalidate({ background: true, reason: `auth:${event}` });
      }
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, [clear, hydrateFromCache, revalidate]);

  // SWR on window events
  useEffect(() => {
    const trigger = (reason: "focus" | "visible" | "pageshow" | "online") => {
      if (!state.sessionUserId) return;
      const now = Date.now();
      if (now - lastRevalidateRef.current < WINDOW_REVALIDATE_DEBOUNCE_MS) return;
      if (reason !== "online" && lastContextSyncAtRef.current && now - lastContextSyncAtRef.current < WINDOW_REVALIDATE_STALE_MS) {
        return;
      }
      lastRevalidateRef.current = now;
      void revalidate({ background: true, reason });
    };

    const onFocus = () => trigger("focus");
    const onVisibility = () => {
      if (document.visibilityState === "visible") trigger("visible");
    };
    const onPageShow = () => trigger("pageshow");
    const onOnline = () => trigger("online");

    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("pageshow", onPageShow);
    window.addEventListener("online", onOnline);

    return () => {
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pageshow", onPageShow);
      window.removeEventListener("online", onOnline);
    };
  }, [revalidate, state.sessionUserId]);

  const value = useMemo<TenantEmpresaContextValue>(
    () => ({
      ...state,
      providerBuildId: PROVIDER_BUILD_ID,
      sessionEmail: state.email,
      has,
      reload,
      refreshCapabilities,
      clear,
      setEmpresaId,
    }),
    [clear, has, reload, refreshCapabilities, setEmpresaId, state]
  );

  return <TenantEmpresaContext.Provider value={value}>{children}</TenantEmpresaContext.Provider>;
}

export function useTenantEmpresaContext() {
  const ctx = useContext(TenantEmpresaContext);
  if (!ctx) throw new Error("useTenantEmpresaContext must be used within TenantEmpresaProvider");
  return ctx;
}

/*
Repo search report (2026-01-19 20:39:25)
- Term: view name (v_user_permis
  sions): `supabase/migrations/20260112_roles_permissions.sql`, `supabase/migrations/20260219_fix_has_permission_user_id.sql`
- Term: JS/TS query using `.from("...")` for that view: (none)
- Term: JS/TS query using `.from('...')` for that view: (none)
- Term: RPC `get_my_permissions`: `lib/auth/provider.tsx`
*/
