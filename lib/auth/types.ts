import type { Capabilities } from "@/lib/auth/capabilities";

export type EmpresaInfo = {
  id: string;
  tenant_id: string;
  nome_fantasia: string | null;
  razao_social: string | null;
  cnpj: string | null;
  ativo: boolean | null;
  papel: string | null;
};

// Back-compat alias (older code used EmpresaOption naming).
export type EmpresaOption = EmpresaInfo;

export type TenantEmpresaState = {
  sessionUserId: string | null | undefined;
  email: string | null;

  tenantId: string | null;
  empresaId: string | null;
  empresas: EmpresaInfo[];
  empresa: EmpresaInfo | null;
  capabilities: Capabilities | null;
  lastLoadPermissions: string[];
  lastLoadPermissionsRaw: (string | null)[];
  lastLoadSource: "rpc" | "view" | null;
  lastLoadCount: number;
  lastLoadError: string | null;

  loading: boolean;
  refreshing: boolean;
  error: string | null;
};
