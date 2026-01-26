"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatDecimalBR, formatMoneyBR, parseMoneyBR } from "@/lib/decimal";

type SugestaoStatus = "PENDENTE" | "VINCULADA" | "CRIADA" | "IGNORADA";
const STATUS_OPTIONS: Array<SugestaoStatus | "TODOS"> = ["PENDENTE", "VINCULADA", "CRIADA", "IGNORADA", "TODOS"];

type SugestaoRow = {
  id: string;
  fornecedor_nome: string | null;
  descricao_xml: string;
  ncm: string | null;
  unidade: string | null;
  qtd: number | null;
  valor_unit: number | null;
  status: SugestaoStatus;
  ferramenta_id: string | null;
  updated_at: string;
};

type FerramentaMini = { id: string; codigo: string; nome: string; ativo: boolean };

type CriarFerramentaForm = {
  categoria_id: string;
  nome: string;
  ncm: string;
  unidade: string;
  ativo: boolean;
  custo_unit: number;
};

function upperText(value: string) {
  return value.trim().toUpperCase();
}

function numOrNull(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

export default function FerramentasSugestoesXmlPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const { tenantId, empresaId, loading: tenantEmpresaLoading, error: tenantEmpresaError } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("estoque.read") === true || has("estoque.write") === true || has("admin.manage_users") === true;
  const canEdit = has("estoque.write") === true || has("admin.manage_users") === true;

  const [rows, setRows] = useState<SugestaoRow[]>([]);
  const [categorias, setCategorias] = useState<Array<{ id: string; prefixo: string | null; nome: string | null }>>([]);
  const [ferramentasById, setFerramentasById] = useState<Record<string, FerramentaMini>>({});
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [texto, setTexto] = useState("");
  const [status, setStatus] = useState<SugestaoStatus | "TODOS">("PENDENTE");
  const [fornecedor, setFornecedor] = useState("");

  const [activeSugestao, setActiveSugestao] = useState<SugestaoRow | null>(null);
  const [modalMode, setModalMode] = useState<null | "vincular" | "criar">(null);
  const [atualizarCustoAoVincular, setAtualizarCustoAoVincular] = useState(false);

  const [buscaFerramenta, setBuscaFerramenta] = useState("");
  const [ferramentasBusca, setFerramentasBusca] = useState<FerramentaMini[]>([]);
  const [ferramentaSelecionada, setFerramentaSelecionada] = useState<FerramentaMini | null>(null);

  const [criarForm, setCriarForm] = useState<CriarFerramentaForm>({
    categoria_id: "",
    nome: "",
    ncm: "",
    unidade: "UN",
    ativo: true,
    custo_unit: 0,
  });

  function closeModal() {
    setModalMode(null);
    setActiveSugestao(null);
    setBuscaFerramenta("");
    setFerramentasBusca([]);
    setFerramentaSelecionada(null);
    setCriarForm({ categoria_id: "", nome: "", ncm: "", unidade: "UN", ativo: true, custo_unit: 0 });
    setAtualizarCustoAoVincular(false);
  }

  async function loadCategorias() {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_categoria")
        .select("id,prefixo,nome")
        .eq("ativo", true)
        .is("deleted_at", null)
        .order("prefixo", { ascending: true }),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setCategorias((data ?? []) as unknown as Array<{ id: string; prefixo: string | null; nome: string | null }>);
  }

  async function loadFerramentas(ids: string[]) {
    if (!tenantId || !empresaId) return;
    if (!ids.length) return setFerramentasById({});

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta")
        .select("id,codigo,nome,ativo")
        .is("deleted_at", null)
        .in("id", ids),
      tenantId,
      empresaId
    );
    if (error) return;

    const map: Record<string, FerramentaMini> = {};
    ((data ?? []) as unknown as FerramentaMini[]).forEach((f) => (map[f.id] = f));
    setFerramentasById(map);
  }

  async function load() {
    setErr(null);
    setOk(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;

    let query = applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_sugestao_xml")
        .select("id,fornecedor_nome,descricao_xml,ncm,unidade,qtd,valor_unit,status,ferramenta_id,updated_at")
        .is("deleted_at", null),
      tenantId,
      empresaId
    ).order("updated_at", { ascending: false });

    if (status !== "TODOS") query = query.eq("status", status);

    const t = texto.trim();
    if (t) query = query.ilike("descricao_xml", `%${t}%`);

    const f = fornecedor.trim();
    if (f) query = query.ilike("fornecedor_nome", `%${f}%`);

    const { data, error } = await query;
    if (error) return setErr(error.message);

    const listRaw = (data ?? []) as unknown as SugestaoRow[];
    const list: SugestaoRow[] = listRaw.map((r) => ({
      ...r,
      qtd: numOrNull((r as unknown as { qtd: unknown }).qtd),
      valor_unit: numOrNull((r as unknown as { valor_unit: unknown }).valor_unit),
    }));
    setRows(list);

    const ferramentaIds = Array.from(new Set(list.map((r) => r.ferramenta_id).filter(Boolean))) as string[];
    await loadFerramentas(ferramentaIds);
  }

  async function buscarFerramentas(term: string) {
    if (!tenantId || !empresaId) return;
    const t = term.trim();
    if (!t) {
      setFerramentasBusca([]);
      return;
    }
    const like = `%${t}%`;
    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta")
        .select("id,codigo,nome,ativo")
        .is("deleted_at", null)
        .eq("ativo", true)
        .or(`codigo.ilike.${like},nome.ilike.${like}`)
        .order("codigo", { ascending: true })
        .limit(20),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setFerramentasBusca((data ?? []) as unknown as FerramentaMini[]);
  }

  function openVincular(s: SugestaoRow) {
    setActiveSugestao(s);
    setModalMode("vincular");
    setFerramentaSelecionada(null);
    setBuscaFerramenta("");
    setFerramentasBusca([]);
    setAtualizarCustoAoVincular(Boolean(numOrNull(s.valor_unit)));
  }

  function openCriar(s: SugestaoRow) {
    setActiveSugestao(s);
    setModalMode("criar");
    setCriarForm({
      categoria_id: "",
      nome: s.descricao_xml ?? "",
      ncm: s.ncm ?? "",
      unidade: s.unidade ?? "UN",
      ativo: true,
      custo_unit: numOrNull(s.valor_unit) ?? 0,
    });
  }

  async function ignorar(s: SugestaoRow) {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para alterar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!confirm("Ignorar sugestao?")) return;

    const { error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_sugestao_xml")
        .update({ status: "IGNORADA", updated_at: new Date().toISOString() })
        .eq("id", s.id),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setOk("Sugestao ignorada.");
    await load();
  }

  async function confirmarVinculo() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para alterar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeSugestao) return;
    if (!ferramentaSelecionada) return setErr("Selecione uma ferramenta.");

    setBusy(true);
    const custoFromXml = numOrNull(activeSugestao.valor_unit);

    if (atualizarCustoAoVincular) {
      if (!custoFromXml) {
        setBusy(false);
        return setErr("Nao ha valor_unit no XML para atualizar custo.");
      }
      const { error: custoErr } = await applyTenantEmpresa(
        supabase
          .schema("c")
          .from("i_ferramenta")
          .update({ custo_unit: custoFromXml, custo_atualizado_em: new Date().toISOString() })
          .eq("id", ferramentaSelecionada.id),
        tenantId,
        empresaId
      );
      if (custoErr) {
        setBusy(false);
        return setErr(custoErr.message);
      }
    }

    const { error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_sugestao_xml")
        .update({
          status: "VINCULADA",
          ferramenta_id: ferramentaSelecionada.id,
          updated_at: new Date().toISOString(),
        })
        .eq("id", activeSugestao.id),
      tenantId,
      empresaId
    );
    setBusy(false);
    if (error) return setErr(error.message);
    setOk("Sugestao vinculada.");
    closeModal();
    await load();
  }

  async function confirmarCriacao() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para alterar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeSugestao) return;

    const categoriaId = String(criarForm.categoria_id ?? "").trim();
    const nome = upperText(criarForm.nome);
    const ncm = criarForm.ncm ? upperText(criarForm.ncm) : "";
    const unidade = criarForm.unidade ? upperText(criarForm.unidade) : "";
    const custoUnit = Number.isFinite(Number(criarForm.custo_unit)) ? Number(criarForm.custo_unit) : 0;
    if (!categoriaId) return setErr("Categoria e obrigatoria.");
    if (!nome) return setErr("Nome e obrigatorio.");

    setBusy(true);

    const ferramentaQuery = applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaId,
          categoria_id: categoriaId,
          nome,
          ncm: ncm || null,
          unidade: unidade || null,
          ativo: !!criarForm.ativo,
          custo_unit: custoUnit,
          custo_moeda: "BRL",
          custo_atualizado_em: new Date().toISOString(),
        })
        .select("id,codigo"),
      tenantId,
      empresaId
    );
    const { data: ferramentaData, error: ferramentaErr } = await ferramentaQuery.maybeSingle();

    if (ferramentaErr || !ferramentaData?.id) {
      setBusy(false);
      return setErr(ferramentaErr?.message ?? "Erro ao criar ferramenta.");
    }

    const { error: sugErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_sugestao_xml")
        .update({
          status: "CRIADA",
          ferramenta_id: ferramentaData.id,
          updated_at: new Date().toISOString(),
        })
        .eq("id", activeSugestao.id),
      tenantId,
      empresaId
    );

    setBusy(false);
    if (sugErr) return setErr(sugErr.message);
    setOk(`Ferramenta criada e sugestao conciliada. Codigo: ${ferramentaData.codigo ?? "-"}.`);
    closeModal();
    await load();
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantEmpresaLoading, texto, fornecedor, status]);

  useEffect(() => {
    void loadCategorias();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantEmpresaLoading]);

  useEffect(() => {
    if (!modalMode || modalMode !== "vincular") return;
    const handle = setTimeout(() => {
      void buscarFerramentas(buscaFerramenta);
    }, 250);
    return () => clearTimeout(handle);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [buscaFerramenta, modalMode]);

  if (tenantEmpresaError) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 p-6">
        {tenantEmpresaError}
      </div>
    );
  }

  if (tenantEmpresaLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando contexto...</div>;
  }

  if (!tenantId || !empresaId) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando contexto...</div>;
  }

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Ferramentas - Sugestoes do XML</h1>
          <p className="text-sm text-zinc-400 mt-1">Fila de conciliacao (vincular/criar/ignorar).</p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Texto (descricao_xml)</div>
            <input
              className="w-full px-3 py-2"
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              placeholder="Buscar descricao do item no XML"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor</div>
            <input
              className="w-full px-3 py-2"
              value={fornecedor}
              onChange={(e) => setFornecedor(e.target.value)}
              placeholder="Nome do fornecedor"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Status</div>
            <select
              aria-label="Status"
              className="w-full px-3 py-2"
              value={status}
              onChange={(e) => setStatus(e.target.value as typeof status)}
            >
              {STATUS_OPTIONS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Registros</div>
            <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-zinc-200">
              {rows.length}
            </div>
          </div>
        </div>
      </div>

      {err && <div className="text-sm text-red-400 border border-red-900/50 bg-red-950/30 px-4 py-3 rounded-lg">{err}</div>}
      {ok && <div className="text-sm text-emerald-300 border border-emerald-900/50 bg-emerald-950/20 px-4 py-3 rounded-lg">{ok}</div>}

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-900/40 text-zinc-200">
              <tr>
                <th className="text-left px-4 py-3">Fornecedor</th>
                <th className="text-left px-4 py-3">Descricao XML</th>
                <th className="text-left px-4 py-3">NCM</th>
                <th className="text-left px-4 py-3">Unid</th>
                <th className="text-left px-4 py-3">Qtd</th>
                <th className="text-left px-4 py-3">Status</th>
                <th className="text-left px-4 py-3">Ferramenta</th>
                <th className="text-right px-4 py-3">Acoes</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-900/80">
              {rows.map((r) => {
                const ferr = r.ferramenta_id ? ferramentasById[r.ferramenta_id] : null;
                return (
                  <tr key={r.id} className="hover:bg-zinc-900/40 align-top">
                    <td className="px-4 py-3">{r.fornecedor_nome ?? "-"}</td>
                    <td className="px-4 py-3">
                      <div className="text-zinc-200">{r.descricao_xml}</div>
                    </td>
                    <td className="px-4 py-3">{r.ncm ?? "-"}</td>
                    <td className="px-4 py-3">{r.unidade ?? "-"}</td>
                    <td className="px-4 py-3">{typeof r.qtd === "number" ? r.qtd : "-"}</td>
                    <td className="px-4 py-3 font-mono text-xs">{r.status}</td>
                    <td className="px-4 py-3">
                      {ferr ? (
                        <div>
                          <div className="font-mono text-xs text-zinc-200">{ferr.codigo}</div>
                          <div className="text-zinc-400 text-xs">{ferr.nome}</div>
                        </div>
                      ) : (
                        <span className="text-zinc-400">-</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => openVincular(r)}
                          disabled={!canEdit || r.status !== "PENDENTE"}
                          className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60 disabled:cursor-not-allowed"
                        >
                          Vincular
                        </button>
                        <button
                          onClick={() => openCriar(r)}
                          disabled={!canEdit || r.status !== "PENDENTE"}
                          className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60 disabled:cursor-not-allowed"
                        >
                          Criar no Catalogo
                        </button>
                        <button
                          onClick={() => ignorar(r)}
                          disabled={!canEdit || r.status !== "PENDENTE"}
                          className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60 disabled:cursor-not-allowed"
                        >
                          Ignorar
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}

              {rows.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-4 py-10 text-zinc-400 text-center">
                    Nenhuma sugestao encontrada.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {modalMode && activeSugestao && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeModal()}
        >
          <div
            className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">
                  {modalMode === "vincular" ? "Vincular sugestao" : "Criar ferramenta no catalogo"}
                </div>
                <div className="text-xs text-zinc-400 mt-0.5">{activeSugestao.descricao_xml}</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeModal}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                {modalMode === "vincular" ? (
                  <button
                    onClick={confirmarVinculo}
                    disabled={busy || !canEdit}
                    className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                  >
                    {busy ? "Salvando..." : "Confirmar"}
                  </button>
                ) : (
                  <button
                    onClick={confirmarCriacao}
                    disabled={busy || !canEdit}
                    className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                  >
                    {busy ? "Salvando..." : "Criar"}
                  </button>
                )}
              </div>
            </div>

            <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
              {modalMode === "vincular" ? (
                <>
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Buscar no catalogo</div>
                    <input
                      className="w-full px-3 py-2"
                      value={buscaFerramenta}
                      onChange={(e) => setBuscaFerramenta(e.target.value)}
                      placeholder="Codigo ou nome (somente ativas)"
                    />
                  </div>

                  <label className="flex items-center gap-2 text-sm text-zinc-200">
                    <input
                      type="checkbox"
                      checked={atualizarCustoAoVincular}
                      onChange={(e) => setAtualizarCustoAoVincular(e.target.checked)}
                      disabled={!numOrNull(activeSugestao.valor_unit)}
                    />
                    Atualizar custo da ferramenta com valor do XML
                    <span className="text-zinc-400">
                      (R$ {formatDecimalBR(numOrNull(activeSugestao.valor_unit) ?? 0, 2)})
                    </span>
                  </label>

                  <div className="border border-zinc-800 rounded-lg overflow-hidden">
                    <table className="min-w-full text-sm">
                      <thead className="bg-zinc-900/40 text-zinc-200">
                        <tr>
                          <th className="text-left px-4 py-3">Codigo</th>
                          <th className="text-left px-4 py-3">Nome</th>
                          <th className="text-right px-4 py-3">Selecionar</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-zinc-900/80">
                        {ferramentasBusca.map((f) => (
                          <tr key={f.id} className="hover:bg-zinc-900/40">
                            <td className="px-4 py-3 font-mono text-xs">{f.codigo}</td>
                            <td className="px-4 py-3">{f.nome}</td>
                            <td className="px-4 py-3 text-right">
                              <button
                                onClick={() => setFerramentaSelecionada(f)}
                                className={
                                  ferramentaSelecionada?.id === f.id
                                    ? "px-3 py-1.5 rounded-md bg-zinc-100 text-zinc-900 font-medium"
                                    : "px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                                }
                              >
                                {ferramentaSelecionada?.id === f.id ? "Selecionada" : "Selecionar"}
                              </button>
                            </td>
                          </tr>
                        ))}
                        {ferramentasBusca.length === 0 && (
                          <tr>
                            <td colSpan={3} className="px-4 py-10 text-zinc-400 text-center">
                              Digite para buscar.
                            </td>
                          </tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                </>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Categoria *</div>
                    <select
                      aria-label="Categoria"
                      className="w-full px-3 py-2"
                      value={criarForm.categoria_id}
                      onChange={(e) => setCriarForm((s) => ({ ...s, categoria_id: e.target.value }))}
                    >
                      <option value="">Selecione...</option>
                      {categorias.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.prefixo ?? "-"} {c.nome ? `- ${c.nome}` : ""}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Unidade</div>
                    <input
                      className="w-full px-3 py-2"
                      value={criarForm.unidade}
                      onChange={(e) => setCriarForm((s) => ({ ...s, unidade: e.target.value }))}
                    />
                  </div>

                  <div className="md:col-span-2 space-y-1">
                    <div className="text-xs text-zinc-400">Nome *</div>
                    <input
                      className="w-full px-3 py-2"
                      value={criarForm.nome}
                      onChange={(e) => setCriarForm((s) => ({ ...s, nome: e.target.value }))}
                    />
                  </div>

                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">NCM</div>
                    <input
                      className="w-full px-3 py-2"
                      value={criarForm.ncm}
                      onChange={(e) => setCriarForm((s) => ({ ...s, ncm: e.target.value }))}
                    />
                  </div>

                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Custo unitario (R$)</div>
                    <input
                      className="w-full px-3 py-2 tabular-nums"
                      value={formatMoneyBR(criarForm.custo_unit)}
                      onChange={(e) => setCriarForm((s) => ({ ...s, custo_unit: parseMoneyBR(e.target.value) }))}
                      placeholder="0,00"
                    />
                  </div>

                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Ativo</div>
                    <select
                      aria-label="Ativo"
                      className="w-full px-3 py-2"
                      value={criarForm.ativo ? "sim" : "nao"}
                      onChange={(e) => setCriarForm((s) => ({ ...s, ativo: e.target.value === "sim" }))}
                    >
                      <option value="sim">SIM</option>
                      <option value="nao">NAO</option>
                    </select>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
