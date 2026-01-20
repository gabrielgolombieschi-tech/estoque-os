"use client";

import { useMemo, useState, type ReactNode } from "react";
import type { Capabilities, CapabilityKey } from "@/lib/auth/capabilities";
import type { EmpresaInfo } from "@/lib/auth/types";

const isDev = process.env.NODE_ENV !== "production";

type AdminDebugPanelProps = {
  providerBuildId: string;
  sessionUserId: string | null | undefined;
  email: string | null | undefined;
  tenantId: string | null | undefined;
  empresaId: string | null | undefined;
  empresas: EmpresaInfo[] | undefined;
  isAdminTenant: boolean;
  adminLoading: boolean;
  capabilities: Capabilities | null | undefined;
  lastLoadPermissions: string[];
  lastLoadPermissionsRaw: (string | null)[];
  lastLoadSource: "rpc" | "view" | null;
  lastLoadCount: number;
  lastLoadError: string | null;
  can?: (k: CapabilityKey) => boolean;
  canAdminManageUsers: boolean;
  shouldShowAdmin: boolean;
  reason: string;
  onRefreshCapabilities?: () => Promise<void> | void;
};

function fmt(v: unknown) {
  if (v === undefined) return "undefined";
  if (v === null) return "null";
  if (typeof v === "string" && v.length === 0) return '""';
  if (typeof v === "string") return v;
  if (typeof v === "boolean") return v ? "true" : "false";
  return String(v);
}

function Row({ k, v }: { k: string; v: ReactNode }) {
  return (
    <>
      <div className="text-zinc-400">{k}</div>
      <div className="font-mono text-zinc-200 break-all">{v}</div>
    </>
  );
}

export default function AdminDebugPanel(props: AdminDebugPanelProps) {
  const [open, setOpen] = useState(false);
  const [refreshingCaps, setRefreshingCaps] = useState(false);

  const capsInfo = useMemo(() => {
    const caps = props.capabilities;
    const isNull = caps === null;
    const isObject = typeof caps === "object" && caps !== null;
    const keysLen = isObject ? Object.keys(caps).length : 0;
    return { isNull, isObject, keysLen };
  }, [props.capabilities]);

  const showDebug = isDev || props.isAdminTenant === true;

  const empresasPreview = useMemo(() => {
    const empresas = props.empresas ?? [];
    if (empresas.length > 3) return null;
    return empresas.map((e) => ({
      id: e.id,
      nome_fantasia: e.nome_fantasia,
    }));
  }, [props.empresas]);

  const permissionsList = useMemo(() => {
    const caps = props.capabilities ?? {};
    return Object.keys(caps).sort().join(", ");
  }, [props.capabilities]);

  const lastLoadPermissionsList = useMemo(() => props.lastLoadPermissions.join(", "), [props.lastLoadPermissions]);
  const lastLoadRawNullCount = useMemo(
    () => props.lastLoadPermissionsRaw.filter((p) => p === null).length,
    [props.lastLoadPermissionsRaw]
  );
  const lastLoadRawSample = useMemo(
    () => props.lastLoadPermissionsRaw.slice(0, 30).map((p) => (p === null ? "null" : p)).join(", "),
    [props.lastLoadPermissionsRaw]
  );

  const canVal = (k: CapabilityKey) => props.can?.(k);
  const canOsRead = canVal("os.read");
  const canEstoqueRead = canVal("estoque.read");
  const canEstoqueWrite = canVal("estoque.write");
  const canFinanceiroRead = canVal("financeiro.read");
  const canXmlImport = canVal("xml_import.execute");

  const canAccessOs = Boolean(canOsRead);
  const canAccessEstoque = Boolean(canEstoqueRead || canEstoqueWrite);
  const canAccessFinanceiro = Boolean(canFinanceiroRead);

  if (!showDebug) return null;

  return (
    <div className="relative flex flex-col items-end">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="text-[11px] text-zinc-500 hover:text-zinc-200 underline underline-offset-2"
      >
        Debug
      </button>

      {open && (
        <div className="absolute right-0 top-full mt-1 w-[420px] max-w-[92vw] max-h-[calc(100vh-6rem)] overflow-y-auto overflow-x-auto overscroll-contain rounded-md border border-zinc-800 bg-zinc-950/95 p-2 text-[11px] leading-snug shadow-lg z-50 select-text">
          {props.onRefreshCapabilities && (
            <div className="flex justify-end pb-2">
              <button
                type="button"
                disabled={refreshingCaps}
                onClick={async () => {
                  try {
                    setRefreshingCaps(true);
                    await props.onRefreshCapabilities?.();
                  } finally {
                    setRefreshingCaps(false);
                  }
                }}
                className="px-2 py-0.5 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {refreshingCaps ? "Recarregando..." : "Recarregar perms"}
              </button>
            </div>
          )}
          <div className="grid grid-cols-[150px,1fr] gap-x-2 gap-y-1">
            <Row k="providerBuildId" v={fmt(props.providerBuildId)} />
            <Row k="sessionUserId" v={fmt(props.sessionUserId)} />
            <Row k="email" v={fmt(props.email)} />
            <Row k="tenantId" v={fmt(props.tenantId)} />
            <Row k="empresaId" v={fmt(props.empresaId)} />
            <Row k="empresas.length" v={fmt(props.empresas?.length ?? 0)} />
            {empresasPreview && empresasPreview.length > 0 && (
              <>
                <div className="text-zinc-400">empresas</div>
                <div className="font-mono text-zinc-200">
                  {empresasPreview.map((e) => (
                    <div key={e.id} className="break-all">
                      {fmt(e.nome_fantasia)} · {e.id}
                    </div>
                  ))}
                </div>
              </>
            )}
            <Row k="isAdminTenant" v={fmt(props.isAdminTenant)} />
            <Row k="adminLoading" v={fmt(props.adminLoading)} />
            <Row k="lastLoadSource" v={fmt(props.lastLoadSource)} />
            <Row k="lastLoadCount" v={fmt(props.lastLoadCount)} />
            <Row k="lastLoadPermissions.length" v={fmt(props.lastLoadPermissions.length)} />
            <Row
              k="lastLoadError"
              v={<span className={props.lastLoadError ? "text-amber-300" : "text-zinc-200"}>{fmt(props.lastLoadError)}</span>}
            />
            <Row k="lastLoadRawNulls" v={fmt(lastLoadRawNullCount)} />
            <div className="text-zinc-400">lastLoadRawSample</div>
            <div className="font-mono text-zinc-200 break-words max-h-28 overflow-auto">{lastLoadRawSample || "(empty)"}</div>
            <div className="text-zinc-400">lastLoadPermissions</div>
            <div className="font-mono text-zinc-200 break-words max-h-28 overflow-auto">{lastLoadPermissionsList || "(empty)"}</div>
            <Row
              k="te.capabilities"
              v={`${capsInfo.isNull ? "null" : capsInfo.isObject ? "object" : typeof props.capabilities} (keys=${capsInfo.keysLen})`}
            />
            <Row k='can("os.read")' v={fmt(canOsRead)} />
            <Row k='can("estoque.read")' v={fmt(canEstoqueRead)} />
            <Row k='can("estoque.write")' v={fmt(canEstoqueWrite)} />
            <Row k='can("financeiro.read")' v={fmt(canFinanceiroRead)} />
            <Row k='can("xml_import.execute")' v={fmt(canXmlImport)} />
            <Row k="canAccessOs" v={fmt(canAccessOs)} />
            <Row k="canAccessEstoque" v={fmt(canAccessEstoque)} />
            <Row k="canAccessFinanceiro" v={fmt(canAccessFinanceiro)} />
            <Row k='can("admin.manage_users")' v={fmt(props.canAdminManageUsers)} />
            <Row k="shouldShowAdmin" v={fmt(props.shouldShowAdmin)} />
            <Row
              k="reason"
              v={
                <span className={props.shouldShowAdmin ? "text-emerald-300" : "text-amber-300"}>
                  {props.reason || "unknown"}
                </span>
              }
            />
            <div className="text-zinc-400">permissions</div>
            <div className="font-mono text-zinc-200 break-words max-h-28 overflow-auto">
              {permissionsList || "(empty)"}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
