"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type Cargo = {
  id: number;
  nome: string;
  tipo_gestao: string | null;
  item_servico_id: number | null;
  ativo: boolean;
  criado_em: string;
};

type ItemServico = {
  id: number;
  nome: string;
  codigo_interno: string;
};

const TIPO_GESTAO_OPTS: { value: string; label: string }[] = [
  { value: "", label: "— Sem gestão —" },
  { value: "projeto_eletrico", label: "Projeto Elétrico" },
  { value: "projeto_mecanico", label: "Projeto Mecânico" },
  { value: "projeto_seguranca", label: "Projeto Segurança" },
  { value: "projeto_software", label: "Projeto Software" },
  { value: "execucao_eletrica", label: "Execução Elétrica" },
  { value: "execucao_mecanica", label: "Execução Mecânica" },
];

function tipoGestaoLabel(v: string | null) {
  if (!v) return "—";
  return TIPO_GESTAO_OPTS.find((o) => o.value === v)?.label ?? v;
}

export default function CargosPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId } = usePermissions();
  const { empresaId } = useTenantEmpresa();

  const [rows, setRows] = useState<Cargo[]>([]);
  const [servicoItens, setServicoItens] = useState<ItemServico[]>([]);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);

  const [filtroAtivo, setFiltroAtivo] = useState<"ativos" | "inativos" | "todos">("ativos");
  const [busca, setBusca] = useState("");

  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<number | null>(null);

  const [nome, setNome] = useState("");
  const [tipoGestao, setTipoGestao] = useState("");
  const [itemServicoId, setItemServicoId] = useState<number | null>(null);
  const [ativo, setAtivo] = useState(true);

  const carregar = useCallback(async () => {
    if (!tenantId || !supabase) return;
    setLoading(true);
    setErrorMsg(null);
    try {
      const { error: te } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (te) throw te;

      const { data, error } = await supabase
        .from("cargos")
        .select("id,nome,tipo_gestao,item_servico_id,ativo,criado_em")
        .order("nome", { ascending: true });

      if (error) throw error;
      setRows((data ?? []) as Cargo[]);
    } catch (e: unknown) {
      setErrorMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [supabase, tenantId]);

  const carregarServicoItens = useCallback(async () => {
    if (!tenantId || !empresaId || !supabase) return;
    try {
      const { data, error } = await applyTenantEmpresa(
        supabase.from("itens").select("id,nome,codigo_interno").eq("tipo", "servico").eq("ativo", true).order("nome", { ascending: true }),
        tenantId,
        empresaId
      );
      if (error) throw error;
      setServicoItens((data ?? []) as ItemServico[]);
    } catch (e: unknown) {
      console.warn("[Cargos] carregarServicoItens:error", e);
      setServicoItens([]);
    }
  }, [empresaId, supabase, tenantId]);

  useEffect(() => {
    carregar();
  }, [carregar]);

  useEffect(() => {
    void carregarServicoItens();
  }, [carregarServicoItens]);

  const rowsFiltrados = useMemo(() => {
    let list = rows;
    if (filtroAtivo === "ativos") list = list.filter((r) => r.ativo);
    else if (filtroAtivo === "inativos") list = list.filter((r) => !r.ativo);
    const term = busca.trim().toLowerCase();
    if (term) list = list.filter((r) => r.nome.toLowerCase().includes(term));
    return list;
  }, [rows, filtroAtivo, busca]);

  function abrirNovo() {
    setEditId(null);
    setNome("");
    setTipoGestao("");
    setItemServicoId(null);
    setAtivo(true);
    setErrorMsg(null);
    setOkMsg(null);
    setModalOpen(true);
  }

  function abrirEditar(r: Cargo) {
    setEditId(r.id);
    setNome(r.nome);
    setTipoGestao(r.tipo_gestao ?? "");
    setItemServicoId(r.item_servico_id ?? null);
    setAtivo(r.ativo);
    setErrorMsg(null);
    setOkMsg(null);
    setModalOpen(true);
  }

  async function salvar() {
    if (!nome.trim()) {
      setErrorMsg("Informe o nome do cargo.");
      return;
    }
    if (!tenantId || !supabase) return;

    setLoading(true);
    setErrorMsg(null);
    setOkMsg(null);
    try {
      const { error: te } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (te) throw te;

      const payload = {
        tenant_id: tenantId,
        nome: nome.trim().toUpperCase(),
        tipo_gestao: tipoGestao || null,
        item_servico_id: itemServicoId,
        ativo,
      };

      if (editId === null) {
        const { error } = await supabase.from("cargos").insert([payload]);
        if (error) throw error;
        setOkMsg("Cargo criado com sucesso.");
      } else {
        const { error } = await supabase
          .from("cargos")
          .update({ ...payload })
          .eq("id", editId);
        if (error) throw error;
        setOkMsg("Cargo atualizado com sucesso.");
      }

      setModalOpen(false);
      await carregar();
    } catch (e: unknown) {
      setErrorMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }

  async function toggleAtivo(r: Cargo) {
    if (!tenantId || !supabase) return;
    try {
      const { error: te } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (te) throw te;
      const { error } = await supabase
        .from("cargos")
        .update({ ativo: !r.ativo })
        .eq("id", r.id);
      if (error) throw error;
      await carregar();
    } catch (e: unknown) {
      setErrorMsg(e instanceof Error ? e.message : String(e));
    }
  }

  async function excluir(r: Cargo) {
    if (!confirm(`Excluir o cargo "${r.nome}"? Esta ação não pode ser desfeita.`)) return;
    if (!tenantId || !supabase) return;
    try {
      const { error: te } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (te) throw te;
      const { error } = await supabase.from("cargos").delete().eq("id", r.id);
      if (error) throw error;
      await carregar();
    } catch (e: unknown) {
      setErrorMsg(e instanceof Error ? e.message : String(e));
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Cargos</h1>
        <button
          type="button"
          onClick={abrirNovo}
          className="bg-sky-600 hover:bg-sky-700 text-white px-4 py-2 rounded-md text-sm font-medium"
        >
          + Novo Cargo
        </button>
      </div>

      {errorMsg && !modalOpen && (
        <div className="mb-4 p-3 rounded-md bg-red-900/30 border border-red-700 text-red-300 text-sm">
          {errorMsg}
        </div>
      )}
      {okMsg && (
        <div className="mb-4 p-3 rounded-md bg-green-900/30 border border-green-700 text-green-300 text-sm">
          {okMsg}
        </div>
      )}

      <div className="flex gap-3 mb-4">
        <input
          type="text"
          placeholder="Buscar cargo..."
          value={busca}
          onChange={(e) => setBusca(e.target.value)}
          className="flex-1 bg-zinc-900 border border-zinc-700 rounded-md px-3 py-2 text-sm text-white placeholder-zinc-500 focus:outline-none focus:border-sky-500"
        />
        <select
          value={filtroAtivo}
          onChange={(e) => setFiltroAtivo(e.target.value as typeof filtroAtivo)}
          className="bg-zinc-900 border border-zinc-700 rounded-md px-3 py-2 text-sm text-white focus:outline-none focus:border-sky-500"
        >
          <option value="ativos">Ativos</option>
          <option value="inativos">Inativos</option>
          <option value="todos">Todos</option>
        </select>
      </div>

      {loading && !modalOpen && (
        <p className="text-zinc-400 text-sm">Carregando...</p>
      )}

      {!loading && rowsFiltrados.length === 0 && (
        <p className="text-zinc-500 text-sm">Nenhum cargo encontrado.</p>
      )}

      {rowsFiltrados.length > 0 && (
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-zinc-800 text-zinc-400">
              <th className="text-left py-2 pr-4 font-medium">Nome</th>
              <th className="text-left py-2 pr-4 font-medium">Tipo Gestão</th>
              <th className="text-center py-2 pr-4 font-medium w-24">Status</th>
              <th className="text-right py-2 font-medium w-32">Ações</th>
            </tr>
          </thead>
          <tbody>
            {rowsFiltrados.map((r) => (
              <tr key={r.id} className="border-b border-zinc-800/50 hover:bg-zinc-900/30">
                <td className="py-2 pr-4 font-medium text-white">{r.nome}</td>
                <td className="py-2 pr-4 text-zinc-300">{tipoGestaoLabel(r.tipo_gestao)}</td>
                <td className="py-2 pr-4 text-center">
                  <span
                    className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                      r.ativo
                        ? "bg-green-900/40 text-green-400 border border-green-800"
                        : "bg-zinc-800 text-zinc-400 border border-zinc-700"
                    }`}
                  >
                    {r.ativo ? "Ativo" : "Inativo"}
                  </span>
                </td>
                <td className="py-2 text-right">
                  <button
                    type="button"
                    onClick={() => abrirEditar(r)}
                    className="text-sky-400 hover:text-sky-300 text-xs mr-3"
                  >
                    Editar
                  </button>
                  <button
                    type="button"
                    onClick={() => toggleAtivo(r)}
                    className="text-zinc-400 hover:text-zinc-200 text-xs mr-3"
                  >
                    {r.ativo ? "Desativar" : "Ativar"}
                  </button>
                  <button
                    type="button"
                    onClick={() => excluir(r)}
                    className="text-red-500 hover:text-red-400 text-xs"
                  >
                    Excluir
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
          <div className="bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl w-full max-w-md p-6">
            <h2 className="text-lg font-semibold mb-5">{editId ? "Editar Cargo" : "Novo Cargo"}</h2>

            {errorMsg && (
              <div className="mb-4 p-3 rounded-md bg-red-900/30 border border-red-700 text-red-300 text-sm">
                {errorMsg}
              </div>
            )}

            <div className="space-y-4">
              <div>
                <label className="block text-xs text-zinc-400 mb-1">Nome do Cargo *</label>
                <input
                  type="text"
                  value={nome}
                  onChange={(e) => setNome(e.target.value)}
                  placeholder="Ex: ELETRICISTA"
                  className="w-full bg-zinc-900 border border-zinc-700 rounded-md px-3 py-2 text-sm text-white placeholder-zinc-500 focus:outline-none focus:border-sky-500"
                />
              </div>

              <div>
                <label className="block text-xs text-zinc-400 mb-1">Tipo de Gestão</label>
                <select
                  value={tipoGestao}
                  onChange={(e) => setTipoGestao(e.target.value)}
                  className="w-full bg-zinc-900 border border-zinc-700 rounded-md px-3 py-2 text-sm text-white focus:outline-none focus:border-sky-500"
                >
                  {TIPO_GESTAO_OPTS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>
                <p className="text-xs text-zinc-500 mt-1">
                  Define qual área de gestão é habilitada automaticamente ao lançar horas neste cargo.
                </p>
              </div>

              <div>
                <label className="block text-xs text-zinc-400 mb-1">Serviço para faturar mão de obra</label>
                <select
                  value={itemServicoId ?? ""}
                  onChange={(e) => setItemServicoId(e.target.value ? Number(e.target.value) : null)}
                  className="w-full bg-zinc-900 border border-zinc-700 rounded-md px-3 py-2 text-sm text-white focus:outline-none focus:border-sky-500"
                >
                  <option value="">— Sem vínculo —</option>
                  {servicoItens.map((it) => (
                    <option key={it.id} value={it.id}>
                      {it.codigo_interno} — {it.nome}
                    </option>
                  ))}
                </select>
                <p className="text-xs text-zinc-500 mt-1">
                  Item de catálogo (tipo serviço) usado para faturar horas apontadas por colaboradores deste cargo
                  ao gerar orçamento a partir de uma OS Fiado. Sem esse vínculo, as horas ficam pendentes.
                </p>
              </div>

              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  id="cargo-ativo"
                  checked={ativo}
                  onChange={(e) => setAtivo(e.target.checked)}
                  className="w-4 h-4 accent-sky-500"
                />
                <label htmlFor="cargo-ativo" className="text-sm text-zinc-300">
                  Cargo ativo
                </label>
              </div>
            </div>

            <div className="flex justify-end gap-3 mt-6">
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                className="px-4 py-2 rounded-md text-sm text-zinc-300 hover:text-white border border-zinc-700 hover:border-zinc-500"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={salvar}
                disabled={loading}
                className="px-4 py-2 rounded-md text-sm font-medium bg-sky-600 hover:bg-sky-700 text-white disabled:opacity-50"
              >
                {loading ? "Salvando..." : editId ? "Salvar alterações" : "Criar cargo"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
