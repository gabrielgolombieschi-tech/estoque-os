export const CAPABILITY_KEYS = [
  "os.read",
  "os.write",
  "os.delete",
  "os_itens.write",
  "os_gestao.write",
  "os_rpcs.execute",
  "estoque.read",
  "estoque.write",
  "estoque_custos.cost_read",
  "fiscal_nf.read",
  "fiscal_nf.write",
  "fiscal_nf.delete",
  "fiscal_itens.write",
  "xml_import.execute",
  "xml_import_faturamento.execute",
  "financeiro.read",
  "financeiro.write",
  "financeiro.delete",
  "financeiro.config",
  "impostos.view",
  "imobilizado.read",
  "imobilizado.write",
  "apontamentos.read",
  "apontamentos.write",
  "apontamentos.delete",
  "apontamentos.config",
  "cad_clientes.write",
  "cad_fornecedores.write",
  "cad_itens.write",
  "compras.read",
  "compras.write",
  "compras.approve",
  "compras.receive",
  "admin.manage_users",
  "admin.users.manage",
] as const;

export type CapabilityKey = (typeof CAPABILITY_KEYS)[number];
export type Capabilities = Record<string, boolean>;
export type CapabilityPair = { key: CapabilityKey; resource: string; action: string };

export function buildCanManyPayload(keys: readonly CapabilityKey[] = CAPABILITY_KEYS): CapabilityPair[] {
  return Array.from(keys).map((key) => {
    const [resource, ...rest] = key.split(".");
    return {
      key,
      resource,
      action: rest.join("."),
    };
  });
}

export function emptyCapabilities(): Capabilities {
  return CAPABILITY_KEYS.reduce((acc, key) => {
    acc[key] = false;
    return acc;
  }, {} as Capabilities);
}

export function mapCapabilities(raw?: Record<string, boolean> | null): Capabilities {
  const base = emptyCapabilities();
  if (!raw) return base;
  for (const key of CAPABILITY_KEYS) {
    if (key in raw) {
      base[key] = Boolean(raw[key]);
    }
  }
  return base;
}

export function hasCapability(caps: Capabilities | null, key: CapabilityKey): boolean {
  return Boolean(caps?.[key]);
}

export function requireCap(caps: Capabilities | null, key: CapabilityKey): boolean {
  return hasCapability(caps, key);
}

export function requireAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  if (!caps) return false;
  return keys.some((key) => caps[key]);
}

export function requireAll(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  if (!caps) return false;
  return keys.every((key) => caps[key]);
}
