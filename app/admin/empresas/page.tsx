"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant } from "@/lib/db/scopes";
import { useIsAdminTenant } from "@/lib/auth/useIsAdminTenant";

type TenantRow = {
  id: string;
  nome: string | null;
};

type EmpresaRow = {
  id: string;
  tenant_id: string;
  codigo: string | null;
  razao_social: string | null;
  nome_fantasia: string | null;
  cnpj: string | null;
  email?: string | null;
  telefone?: string | null;
  site?: string | null;
  observacao?: string | null;
  ativo: boolean | null;
  created_at: string | null;
  tenant?: {
    id: string;
    nome: string | null;
    deleted_at?: string | null;
  } | null;
};

type EmpresaForm = {
  tenant_id: string;
  codigo: string;
  razao_social: string;
  nome_fantasia: string;
  cnpj: string;
  email: string;
  telefone: string;
  site: string;
  observacao: string;
  ativo: boolean;
};

const FOCUSABLE_SELECTOR =
  "button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])";

function getFocusable(container: HTMLElement | null): HTMLElement[] {
  if (!container) return [];
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
    (el) => !el.hasAttribute("disabled") && el.getAttribute("aria-hidden") !== "true"
  );
}

function normalizeDigits(value: string): string {
  return value.replace(/\D/g, "");
}

function normalizeCodeBase(value: string): string {
  const cleaned = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^0-9a-zA-Z]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .replace(/_+/g, "_")
    .toUpperCase();
  return cleaned || "EMPRESA";
}

function generateCodigo(nomeFantasia: string): string {
  const base = normalizeCodeBase(nomeFantasia);
  const suffix = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `${base}_${suffix}`;
}

function formatDate(value: string | null) {
  if (!value) return "-";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "-";
  return parsed.toLocaleDateString("pt-BR");
}

export default function AdminEmpresasPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId, loading: tenantEmpresaLoading, error: tenantEmpresaError } = useTenantEmpresa();
  const { isAdmin, loading: adminLoading } = useIsAdminTenant(tenantId ?? null);

  const [tenants, setTenants] = useState<TenantRow[]>([]);
  const [tenantFilter, setTenantFilter] = useState("");
  const [rows, setRows] = useState<EmpresaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [tenantsLoading, setTenantsLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");

  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState<"create" | "edit">("create");
  const [editing, setEditing] = useState<EmpresaRow | null>(null);
  const [form, setForm] = useState<EmpresaForm>({
    tenant_id: "",
    codigo: "",
    razao_social: "",
    nome_fantasia: "",
    cnpj: "",
    email: "",
    telefone: "",
    site: "",
    observacao: "",
    ativo: true,
  });
  const [modalErr, setModalErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const modalRef = useRef<HTMLDivElement | null>(null);
  const firstInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    const handle = setTimeout(() => {
      setDebouncedSearch(search.trim());
    }, 300);
    return () => clearTimeout(handle);
  }, [search]);

  const closeModal = useCallback(() => {
    setModalOpen(false);
    setEditing(null);
    setModalErr(null);
  }, []);

  const openCreate = useCallback(() => {
    if (!isAdmin) return;
    const fallbackTenant = tenantFilter || tenantId || "";
    setForm({
      tenant_id: fallbackTenant,
      codigo: "",
      razao_social: "",
      nome_fantasia: "",
      cnpj: "",
      email: "",
      telefone: "",
      site: "",
      observacao: "",
      ativo: true,
    });
    setModalMode("create");
    setEditing(null);
    setModalErr(null);
    setOk(null);
    setModalOpen(true);
  }, [isAdmin, tenantFilter, tenantId]);

  const openEdit = useCallback((row: EmpresaRow) => {
    if (!isAdmin) return;
    setForm({
      tenant_id: row.tenant_id ?? "",
      codigo: row.codigo ?? "",
      razao_social: row.razao_social ?? "",
      nome_fantasia: row.nome_fantasia ?? "",
      cnpj: row.cnpj ?? "",
      email: row.email ?? "",
      telefone: row.telefone ?? "",
      site: row.site ?? "",
      observacao: row.observacao ?? "",
      ativo: !!row.ativo,
    });
    setModalMode("edit");
    setEditing(row);
    setModalErr(null);
    setOk(null);
    setModalOpen(true);
  }, [isAdmin]);

  useEffect(() => {
    if (!modalOpen) return;

    const previousFocus = document.activeElement as HTMLElement | null;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        closeModal();
        return;
      }
      if (e.key !== "Tab") return;
      const focusable = getFocusable(modalRef.current);
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    requestAnimationFrame(() => {
      firstInputRef.current?.focus();
    });

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      previousFocus?.focus?.();
    };
  }, [closeModal, modalOpen]);

  useEffect(() => {
    if (tenantId && !tenantFilter) {
      setTenantFilter(tenantId);
    }
  }, [tenantId, tenantFilter]);

  const loadTenants = useCallback(async () => {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setTenants([]);
      return;
    }

    setTenantsLoading(true);
    const { data, error } = await supabase
      .schema("c")
      .from("tenant")
      .select("id,nome")
      .is("deleted_at", null)
      .order("nome", { ascending: true });

    if (error) {
      setErr(error.message);
      setTenants([]);
    } else {
      setTenants((data ?? []) as TenantRow[]);
    }
    setTenantsLoading(false);
  }, [empresaId, supabase, tenantEmpresaLoading, tenantId]);

  const load = useCallback(async () => {
    setErr(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setRows([]);
      setLoading(false);
      return;
    }

    const scopedTenantId = tenantFilter || tenantId;
    if (!scopedTenantId) {
      setRows([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    let query = supabase
      .schema("c")
      .from("empresa")
      .select(
        "id,tenant_id,codigo,razao_social,nome_fantasia,cnpj,email,telefone,site,observacao,ativo,created_at,tenant:tenant_id(id,nome)"
      )
      .is("deleted_at", null)
      .is("tenant.deleted_at", null);

    query = applyTenant(query, scopedTenantId);

    if (debouncedSearch) {
      query = query.or(
        `nome_fantasia.ilike.%${debouncedSearch}%,razao_social.ilike.%${debouncedSearch}%,cnpj.ilike.%${debouncedSearch}%,codigo.ilike.%${debouncedSearch}%`
      );
    }

    query = query.order("nome_fantasia", { ascending: true }).order("razao_social", { ascending: true });

    const { data, error } = await query;
    if (error) {
      setErr(error.message);
      setRows([]);
    } else {
      setRows((data ?? []) as unknown as EmpresaRow[]);
    }
    setLoading(false);
  }, [debouncedSearch, empresaId, supabase, tenantEmpresaLoading, tenantFilter, tenantId]);

  useEffect(() => {
    void loadTenants();
  }, [loadTenants]);

  useEffect(() => {
    void load();
  }, [load]);

  const handleSave = useCallback(async () => {
    setModalErr(null);
    if (!isAdmin) {
      setModalErr("Sem permissao para salvar empresas.");
      return;
    }

    const tenantValue = form.tenant_id.trim();
    if (!tenantValue) {
      setModalErr("Tenant obrigatorio.");
      return;
    }

    const nomeFantasia = form.nome_fantasia.trim();
    if (!nomeFantasia) {
      setModalErr("Nome fantasia obrigatorio.");
      return;
    }

    const razaoSocial = form.razao_social.trim();
    if (!razaoSocial) {
      setModalErr("Razao social obrigatoria.");
      return;
    }

    let codigo = form.codigo.trim();
    if (!codigo) {
      codigo = generateCodigo(nomeFantasia);
      setForm((prev) => ({ ...prev, codigo }));
    }

    const cnpjRaw = form.cnpj.trim();
    if (cnpjRaw && /[^0-9]/.test(cnpjRaw)) {
      setModalErr("CNPJ deve conter apenas digitos.");
      return;
    }
    const cnpj = cnpjRaw ? normalizeDigits(cnpjRaw) : null;
    if (cnpj && cnpj.length !== 14) {
      setModalErr("CNPJ deve ter 14 digitos.");
      return;
    }

    const telefoneRaw = form.telefone.trim();
    if (telefoneRaw && /[^0-9]/.test(telefoneRaw)) {
      setModalErr("Telefone deve conter apenas digitos.");
      return;
    }
    const telefone = telefoneRaw ? normalizeDigits(telefoneRaw) : null;

    const email = form.email.trim().toLowerCase();
    const site = form.site.trim().toLowerCase();
    const observacao = form.observacao.trim();

    const payload = {
      codigo,
      razao_social: razaoSocial,
      nome_fantasia: nomeFantasia,
      cnpj,
      email: email || null,
      telefone: telefone || null,
      site: site || null,
      observacao: observacao || null,
      ativo: !!form.ativo,
    };

    setSaving(true);
    const { error } =
      modalMode === "edit" && editing
        ? await supabase.schema("c").from("empresa").update(payload).eq("id", editing.id)
        : await supabase
            .schema("c")
            .from("empresa")
            .insert({ tenant_id: tenantValue, ...payload })
            .select("id")
            .single();
    setSaving(false);

    if (error) {
      setModalErr(error.message);
      return;
    }

    setOk(modalMode === "edit" ? "Empresa atualizada." : "Empresa criada.");
    closeModal();
    await load();
  }, [closeModal, editing, form, isAdmin, load, modalMode, supabase]);

  async function toggleAtivo(row: EmpresaRow) {
    if (busyId) return;
    const nextAtivo = !row.ativo;
    setBusyId(row.id);
    setErr(null);

    const { error } = await supabase
      .schema("c")
      .from("empresa")
      .update({ ativo: nextAtivo })
      .eq("id", row.id);

    setBusyId(null);
    if (error) {
      setErr(error.message);
      return;
    }

    setRows((prev) =>
      prev.map((item) => (item.id === row.id ? { ...item, ativo: nextAtivo } : item))
    );
  }

  if (tenantEmpresaError) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 p-6">
        {tenantEmpresaError}
      </div>
    );
  }

  if (tenantEmpresaLoading || !tenantId || !empresaId) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando contexto...
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Empresas</h1>
          <p className="text-sm text-zinc-400 mt-1">Empresas cadastradas no sistema.</p>
        </div>

        <div className="flex items-center gap-2">
          {isAdmin && !adminLoading && (
            <button
              onClick={openCreate}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              Nova Empresa
            </button>
          )}
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 space-y-3">
        <div className="grid gap-3 md:grid-cols-[1fr_220px_auto] items-end">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input
              className="w-full px-3 py-2"
              placeholder="Nome fantasia, razao social, CNPJ ou codigo"
              aria-label="Buscar empresas"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Tenant</div>
            <select
              aria-label="Filtrar por tenant"
              className="w-full px-3 py-2"
              value={tenantFilter}
              onChange={(e) => setTenantFilter(e.target.value)}
              disabled={tenantsLoading}
            >
              <option value="" disabled>
                Selecione
              </option>
              {tenants.map((tenant) => (
                <option key={tenant.id} value={tenant.id}>
                  {tenant.nome ?? tenant.id}
                </option>
              ))}
            </select>
          </div>
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Buscar
          </button>
        </div>

        {err && <div className="text-sm text-red-400">{err}</div>}
        {ok && <div className="text-sm text-emerald-300">{ok}</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Nome fantasia</th>
              <th className="px-4 py-3 text-left">Razao social</th>
              <th className="px-4 py-3 text-left">CNPJ</th>
              <th className="px-4 py-3 text-left">Tenant</th>
              <th className="px-4 py-3 text-center">Status</th>
              <th className="px-4 py-3 text-left">Criado em</th>
              <th className="px-4 py-3 text-center">Acoes</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {loading && (
              <tr>
                <td colSpan={7} className="px-4 py-6 text-zinc-400">
                  Carregando empresas...
                </td>
              </tr>
            )}

            {!loading &&
              rows.map((row) => (
                <tr key={row.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3">
                    <div className="font-medium">{row.nome_fantasia ?? "-"}</div>
                    {row.codigo && <div className="text-xs text-zinc-500">Codigo: {row.codigo}</div>}
                  </td>
                  <td className="px-4 py-3 text-zinc-300">{row.razao_social ?? "-"}</td>
                  <td className="px-4 py-3 text-zinc-300">{row.cnpj ?? "-"}</td>
                  <td className="px-4 py-3 text-zinc-300">{row.tenant?.nome ?? "-"}</td>
                  <td className="px-4 py-3 text-center">
                    <span
                      className={`inline-flex items-center px-2 py-1 rounded-md text-xs border ${
                        row.ativo
                          ? "border-emerald-500/40 text-emerald-300"
                          : "border-amber-500/40 text-amber-300"
                      }`}
                    >
                      {row.ativo ? "Ativo" : "Inativo"}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-zinc-300">{formatDate(row.created_at)}</td>
                  <td className="px-4 py-3 text-center">
                    <div className="flex items-center justify-center gap-2">
                      {isAdmin && !adminLoading && (
                        <button
                          onClick={() => openEdit(row)}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                        >
                          Editar
                        </button>
                      )}
                      <button
                        onClick={() => toggleAtivo(row)}
                        disabled={busyId === row.id}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs disabled:opacity-60"
                      >
                        {row.ativo ? "Desativar" : "Ativar"}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}

            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-6 text-zinc-400">
                  Nenhuma empresa encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {modalOpen && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeModal()}
          role="presentation"
        >
          <div
            ref={modalRef}
            role="dialog"
            aria-modal="true"
            aria-label={modalMode === "edit" ? "Editar empresa" : "Nova empresa"}
            className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">{modalMode === "edit" ? "Editar empresa" : "Nova empresa"}</div>
                <div className="text-xs text-zinc-400 mt-0.5">Dados cadastrais da empresa.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={closeModal}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  type="submit"
                  form="empresa-form"
                  disabled={saving}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  {saving ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <form
              id="empresa-form"
              onSubmit={(e) => {
                e.preventDefault();
                void handleSave();
              }}
              className="p-5 space-y-4"
            >
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Tenant *</div>
                  <select
                    aria-label="Tenant"
                    className="w-full px-3 py-2"
                    value={form.tenant_id}
                    onChange={(e) => setForm((s) => ({ ...s, tenant_id: e.target.value }))}
                    disabled={modalMode === "edit"}
                  >
                    <option value="" disabled>
                      Selecione
                    </option>
                    {tenants.map((tenant) => (
                      <option key={tenant.id} value={tenant.id}>
                        {tenant.nome ?? tenant.id}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Codigo *</div>
                  <input
                    aria-label="Codigo"
                    className="w-full px-3 py-2"
                    value={form.codigo}
                    onChange={(e) => setForm((s) => ({ ...s, codigo: e.target.value }))}
                    placeholder="Se vazio, gera automaticamente"
                  />
                </div>

                <div className="space-y-1 md:col-span-2">
                  <div className="text-xs text-zinc-400">Nome fantasia *</div>
                  <input
                    ref={firstInputRef}
                    aria-label="Nome fantasia"
                    className="w-full px-3 py-2"
                    value={form.nome_fantasia}
                    onChange={(e) => setForm((s) => ({ ...s, nome_fantasia: e.target.value }))}
                  />
                </div>

                <div className="space-y-1 md:col-span-2">
                  <div className="text-xs text-zinc-400">Razao social *</div>
                  <input
                    aria-label="Razao social"
                    className="w-full px-3 py-2"
                    value={form.razao_social}
                    onChange={(e) => setForm((s) => ({ ...s, razao_social: e.target.value }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">CNPJ</div>
                  <input
                    aria-label="CNPJ"
                    className="w-full px-3 py-2"
                    value={form.cnpj}
                    onChange={(e) => setForm((s) => ({ ...s, cnpj: e.target.value }))}
                    placeholder="Somente digitos"
                    inputMode="numeric"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Telefone</div>
                  <input
                    aria-label="Telefone"
                    className="w-full px-3 py-2"
                    value={form.telefone}
                    onChange={(e) => setForm((s) => ({ ...s, telefone: e.target.value }))}
                    placeholder="Somente digitos"
                    inputMode="numeric"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Email</div>
                  <input
                    aria-label="Email"
                    className="w-full px-3 py-2"
                    value={form.email}
                    onChange={(e) => setForm((s) => ({ ...s, email: e.target.value }))}
                    placeholder="contato@empresa.com"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Site</div>
                  <input
                    aria-label="Site"
                    className="w-full px-3 py-2"
                    value={form.site}
                    onChange={(e) => setForm((s) => ({ ...s, site: e.target.value }))}
                    placeholder="www.exemplo.com"
                  />
                </div>

                <div className="space-y-1 md:col-span-2">
                  <div className="text-xs text-zinc-400">Observacao</div>
                  <textarea
                    aria-label="Observacao"
                    className="w-full px-3 py-2 min-h-[80px]"
                    value={form.observacao}
                    onChange={(e) => setForm((s) => ({ ...s, observacao: e.target.value }))}
                  />
                </div>
              </div>

              <div className="flex items-center justify-between gap-3 border border-zinc-800 rounded-lg p-3">
                <div className="text-sm">
                  <div className="font-medium">Status</div>
                  <div className="text-xs text-zinc-400">Empresa visivel no sistema.</div>
                </div>
                <label className="text-sm text-zinc-300 flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={form.ativo}
                    onChange={(e) => setForm((s) => ({ ...s, ativo: e.target.checked }))}
                  />
                  Ativo
                </label>
              </div>

              {modalErr && <div className="text-sm text-red-400">{modalErr}</div>}
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
