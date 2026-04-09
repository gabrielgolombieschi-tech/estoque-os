import type { SupabaseClient } from "@supabase/supabase-js";
import type { EmpresaInfo } from "@/lib/auth/types";

export type EmpresaDisplayInfo = {
  id: string;
  label: string;
  fullName: string;
  cnpj: string | null;
  searchText: string;
};

export type DocumentoEmpresaSource = {
  empresa_id: string | null;
  emitente_nome?: string | null;
  emitente_cnpj?: string | null;
};

const SGU_CNPJ = "35739220000116";
type EmpresaRow = {
  id: string;
  tenant_id: string;
  nome_fantasia: string | null;
  razao_social: string | null;
  cnpj: string | null;
  ativo: boolean | null;
  deleted_at?: string | null;
};

function normalizeText(value: string | null | undefined): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/\s+/g, " ")
    .trim();
}

function digitsOnly(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D+/g, "");
}

function resolveEmpresaLabel(empresa: Pick<EmpresaInfo, "nome_fantasia" | "razao_social" | "cnpj">): string {
  const fullName = normalizeText(`${empresa.nome_fantasia ?? ""} ${empresa.razao_social ?? ""}`);
  const cnpjDigits = digitsOnly(empresa.cnpj);

  if (cnpjDigits === SGU_CNPJ || fullName.includes("SGU")) return "SGU";
  if (fullName.includes("SEGAU")) return "Segau";

  const fallback = String(empresa.nome_fantasia ?? empresa.razao_social ?? empresa.cnpj ?? "").trim();
  return fallback || "Sem empresa";
}

function resolveEmpresaFullName(empresa: Pick<EmpresaInfo, "nome_fantasia" | "razao_social" | "cnpj">): string {
  return String(empresa.nome_fantasia ?? empresa.razao_social ?? empresa.cnpj ?? "").trim() || "Sem empresa";
}

function getEmpresaSortWeight(label: string): number {
  if (label === "Segau") return 0;
  if (label === "SGU") return 1;
  return 9;
}

function toEmpresaInfo(row: EmpresaRow): EmpresaInfo {
  return {
    id: String(row.id),
    tenant_id: String(row.tenant_id),
    nome_fantasia: row.nome_fantasia ?? null,
    razao_social: row.razao_social ?? null,
    cnpj: row.cnpj ?? null,
    ativo: row.ativo ?? null,
    papel: null,
  };
}

export function resolveDocumentoEmpresaKey(source: DocumentoEmpresaSource): string | null {
  if (source.empresa_id) return String(source.empresa_id);

  const cnpj = digitsOnly(source.emitente_cnpj);
  if (cnpj) return `cnpj:${cnpj}`;

  const nome = normalizeText(source.emitente_nome);
  if (nome) return `nome:${nome}`;

  return null;
}

export function buildEmpresaInfosFromDocumentos(rows: DocumentoEmpresaSource[]): EmpresaInfo[] {
  const out = new Map<string, EmpresaInfo>();

  for (const row of rows) {
    const key = resolveDocumentoEmpresaKey(row);
    if (!key) continue;

    const current = out.get(key);
    const nome = row.emitente_nome ? String(row.emitente_nome).trim() : null;
    const cnpj = digitsOnly(row.emitente_cnpj) || null;

    out.set(key, {
      id: key,
      tenant_id: current?.tenant_id ?? "",
      nome_fantasia: nome ?? current?.nome_fantasia ?? null,
      razao_social: nome ?? current?.razao_social ?? null,
      cnpj: cnpj ?? current?.cnpj ?? null,
      ativo: true,
      papel: current?.papel ?? null,
    });
  }

  return Array.from(out.values());
}

export function mergeEmpresaInfos(...groups: EmpresaInfo[][]): EmpresaInfo[] {
  const merged = new Map<string, EmpresaInfo>();

  for (const group of groups) {
    for (const empresa of group) {
      if (!empresa?.id) continue;
      const key = String(empresa.id);
      const current = merged.get(key);
      merged.set(key, {
        id: key,
        tenant_id: empresa.tenant_id ?? current?.tenant_id ?? "",
        nome_fantasia: empresa.nome_fantasia ?? current?.nome_fantasia ?? null,
        razao_social: empresa.razao_social ?? current?.razao_social ?? null,
        cnpj: empresa.cnpj ?? current?.cnpj ?? null,
        ativo: empresa.ativo ?? current?.ativo ?? null,
        papel: empresa.papel ?? current?.papel ?? null,
      });
    }
  }

  return Array.from(merged.values()).sort((left, right) =>
    String(left.nome_fantasia ?? left.razao_social ?? left.id).localeCompare(
      String(right.nome_fantasia ?? right.razao_social ?? right.id),
      "pt-BR"
    )
  );
}

export async function fetchTenantEmpresas(supabase: SupabaseClient, tenantId: string): Promise<EmpresaInfo[]> {
  void tenantId;
  const { data, error } = await supabase.rpc("faturamento_empresas_disponiveis");

  if (error) throw error;

  return ((data ?? []) as Array<
    Pick<EmpresaRow, "tenant_id" | "nome_fantasia" | "razao_social" | "cnpj"> & {
      empresa_id: string;
    }
  >).map((row) =>
    toEmpresaInfo({
      id: row.empresa_id,
      tenant_id: row.tenant_id,
      nome_fantasia: row.nome_fantasia ?? null,
      razao_social: row.razao_social ?? null,
      cnpj: row.cnpj ?? null,
      ativo: true,
      deleted_at: null,
    })
  );
}

export function buildEmpresaDisplayOptions(empresas: EmpresaInfo[]): EmpresaDisplayInfo[] {
  return empresas
    .filter((empresa) => Boolean(empresa?.id))
    .map((empresa) => {
      const label = resolveEmpresaLabel(empresa);
      const fullName = resolveEmpresaFullName(empresa);
      const cnpj = empresa.cnpj ?? null;
      return {
        id: String(empresa.id),
        label,
        fullName,
        cnpj,
        searchText: `${label} ${fullName} ${cnpj ?? ""}`.toLowerCase(),
      };
    })
    .sort((left, right) => {
      const weightDiff = getEmpresaSortWeight(left.label) - getEmpresaSortWeight(right.label);
      if (weightDiff !== 0) return weightDiff;
      return left.label.localeCompare(right.label, "pt-BR");
    });
}

export function buildEmpresaDisplayById(empresas: EmpresaInfo[]): Record<string, EmpresaDisplayInfo> {
  return buildEmpresaDisplayOptions(empresas).reduce<Record<string, EmpresaDisplayInfo>>((acc, empresa) => {
    acc[empresa.id] = empresa;
    return acc;
  }, {});
}
