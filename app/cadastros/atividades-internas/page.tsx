"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabaseBrowser } from "@/lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";

// Atividades internas: para onde a hora vai quando nao e OS (comercial,
// treinamento, manutencao da fabrica...). Ver docs/horas-internas.md. Quem decide
// de verdade e o banco (web_atividade_interna_salvar: Admin, Diretor ou
// Coordenacao); a tela so mostra e pede. Nao tem "apagar" de proposito: uma
// atividade com hora lancada sai de cena desativando, e a hora continua com nome.

type Atividade = {
  id: string;
  codigo: string;
  nome: string;
  pede_cliente: boolean;
  ativo: boolean;
  ordem: number;
  em_uso: number;
};

type RetornoRpc = { sucesso: boolean; id?: string };

function mensagemErro(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim()) return msg;
  }
  return fallback;
}

export default function AtividadesInternasPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, has } = usePermissions();
  const { empresaId } = useTenantEmpresa();
  // O relatório pede leitura de apontamentos (web_horas_internas_resumo); a
  // Coordenação cadastra atividade mas não tem essa leitura no web, e o link a
  // levaria a uma tela de erro.
  const podeVerRelatorio = Boolean(has("apontamentos.read"));

  const [atividades, setAtividades] = useState<Atividade[]>([]);
  const [loading, setLoading] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [semAcesso, setSemAcesso] = useState(false);
  const [ok, setOk] = useState<string | null>(null);

  const [modalAberto, setModalAberto] = useState(false);
  const [editando, setEditando] = useState<Atividade | null>(null);
  const [codigo, setCodigo] = useState("");
  const [nome, setNome] = useState("");
  const [pedeCliente, setPedeCliente] = useState(false);
  const [ativo, setAtivo] = useState(true);
  const [ordem, setOrdem] = useState("0");

  const carregar = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) return;
    setLoading(true);
    setErro(null);
    try {
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;
      const { error: empresaErr } = await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
      if (empresaErr) throw empresaErr;

      const { data, error } = await supabase.rpc("web_atividades_internas_listar");
      if (error) {
        if (/da gestão/i.test(error.message)) {
          setSemAcesso(true);
          return;
        }
        throw error;
      }
      setSemAcesso(false);
      setAtividades(((data ?? []) as Atividade[]).map((item) => ({ ...item, em_uso: Number(item.em_uso ?? 0), ordem: Number(item.ordem ?? 0) })));
    } catch (e: unknown) {
      setErro(mensagemErro(e, "Falha ao carregar as atividades internas."));
    } finally {
      setLoading(false);
    }
  }, [empresaId, supabase, tenantId]);

  useEffect(() => {
    const timer = window.setTimeout(() => void carregar(), 0);
    return () => window.clearTimeout(timer);
  }, [carregar]);

  function abrirNova() {
    setEditando(null);
    setCodigo("");
    setNome("");
    setPedeCliente(false);
    setAtivo(true);
    // Entra depois das que existem, sem a pessoa precisar pensar em numero.
    setOrdem(String((atividades.reduce((maior, item) => Math.max(maior, item.ordem), 0) || 0) + 10));
    setErro(null);
    setOk(null);
    setModalAberto(true);
  }

  function abrirEditar(atividade: Atividade) {
    setEditando(atividade);
    setCodigo(atividade.codigo);
    setNome(atividade.nome);
    setPedeCliente(atividade.pede_cliente);
    setAtivo(atividade.ativo);
    setOrdem(String(atividade.ordem));
    setErro(null);
    setOk(null);
    setModalAberto(true);
  }

  async function gravar(dados: { id: string | null; codigo: string; nome: string; pede_cliente: boolean; ativo: boolean; ordem: number }) {
    if (!supabase) return;
    const { data, error } = await supabase.rpc("web_atividade_interna_salvar", {
      p_id: dados.id,
      p_codigo: dados.codigo,
      p_nome: dados.nome,
      p_pede_cliente: dados.pede_cliente,
      p_ativo: dados.ativo,
      p_ordem: dados.ordem,
    });
    if (error) throw error;
    const retorno = (data ?? {}) as RetornoRpc;
    if (!retorno.sucesso) throw new Error("Não foi possível salvar a atividade.");
  }

  async function salvar() {
    const ordemNumero = Number(ordem);
    if (nome.trim().length < 2) {
      setErro("Dê um nome à atividade (ex.: Treinamento).");
      return;
    }
    if (!Number.isInteger(ordemNumero) || ordemNumero < 0 || ordemNumero > 32000) {
      setErro("A ordem é um número inteiro de 0 a 32000.");
      return;
    }
    setLoading(true);
    setErro(null);
    try {
      await gravar({ id: editando?.id ?? null, codigo: codigo.trim(), nome: nome.trim(), pede_cliente: pedeCliente, ativo, ordem: ordemNumero });
      setModalAberto(false);
      setOk(editando ? "Atividade atualizada." : "Atividade criada. Ela já aparece para quem lança hora.");
      await carregar();
    } catch (e: unknown) {
      setErro(mensagemErro(e, "Erro ao salvar."));
    } finally {
      setLoading(false);
    }
  }

  async function alternarAtivo(atividade: Atividade) {
    const acao = atividade.ativo ? "Desativar" : "Reativar";
    const aviso = atividade.ativo
      ? " Ela some da lista de quem lança hora; as horas já lançadas continuam onde estão."
      : "";
    if (!confirm(`${acao} a atividade "${atividade.nome}"?${aviso}`)) return;
    setLoading(true);
    setErro(null);
    setOk(null);
    try {
      await gravar({ ...atividade, ativo: !atividade.ativo });
      await carregar();
    } catch (e: unknown) {
      setErro(mensagemErro(e, "Erro ao alterar."));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center gap-3 flex-wrap">
        <h1 className="text-2xl font-bold">Atividades internas</h1>
        {!semAcesso && (
          <button
            onClick={abrirNova}
            disabled={loading}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            + Nova atividade
          </button>
        )}
        {podeVerRelatorio && (
          <Link href="/apontamentos/horas-internas" className="text-sm text-sky-400 hover:text-sky-300 underline">
            Para onde foram as horas
          </Link>
        )}
        {loading && <span className="text-zinc-400">Carregando...</span>}
      </div>

      <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-300 space-y-1">
        <p>
          Atividade interna é para onde a hora vai quando não é de OS: reunião comercial, treinamento, manutenção da
          fábrica, exame, integração. Ela conta na meta da semana como hora trabalhada, nasce aprovada e fica fora de todo
          custo de OS.
        </p>
        <p className="text-zinc-400">
          <strong>Pede cliente e orçamento</strong> é para o Comercial: ao lançar, a pessoa informa para qual cliente
          (do cadastro ou só o nome) e qual orçamento. Atividades assim não aparecem no tablet da fábrica.
        </p>
        <p className="text-zinc-400">
          Não existe apagar: uma atividade com horas lançadas é desativada, e as horas continuam com o nome dela.
        </p>
      </div>

      {semAcesso && (
        <div className="p-3 border border-amber-700/50 rounded-lg bg-amber-950/20 text-amber-200 text-sm">
          O cadastro de atividades internas é da gestão: Admin, Diretor ou Coordenação.
        </div>
      )}
      {erro && !modalAberto && (
        <div className="p-3 border border-red-700 rounded-lg bg-red-900/20 text-red-300 text-sm">{erro}</div>
      )}
      {ok && <div className="p-3 border border-green-700 rounded-lg bg-green-900/20 text-green-300 text-sm">{ok}</div>}

      {!semAcesso && (
        <div className="border border-zinc-800 rounded-lg overflow-hidden bg-zinc-950">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/50">
              <tr className="text-left">
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300 text-right">Ordem</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Atividade</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Código</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Pede cliente e orçamento</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300 text-right">Lançamentos</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Situação</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Ações</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {atividades.map((atividade) => (
                <tr key={atividade.id} className={`hover:bg-zinc-900/40 ${atividade.ativo ? "" : "opacity-70"}`}>
                  <td className="px-3 py-2 text-zinc-400 text-right">{atividade.ordem}</td>
                  <td className="px-3 py-2 text-zinc-200">{atividade.nome}</td>
                  <td className="px-3 py-2 text-zinc-400 font-mono text-xs">{atividade.codigo}</td>
                  <td className="px-3 py-2 text-zinc-300">{atividade.pede_cliente ? "Sim" : "Não"}</td>
                  <td className="px-3 py-2 text-zinc-300 text-right" title="Horas já lançadas nesta atividade">
                    {atividade.em_uso}
                  </td>
                  <td className="px-3 py-2">
                    <span className={`px-2 py-0.5 rounded-full text-xs ${atividade.ativo ? "bg-green-900/40 text-green-400 border border-green-800" : "bg-zinc-800 text-zinc-400 border border-zinc-700"}`}>
                      {atividade.ativo ? "Ativa" : "Desativada"}
                    </span>
                  </td>
                  <td className="px-3 py-2 space-x-2 whitespace-nowrap">
                    <button onClick={() => abrirEditar(atividade)} disabled={loading} className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm">
                      Editar
                    </button>
                    <button onClick={() => alternarAtivo(atividade)} disabled={loading} className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm">
                      {atividade.ativo ? "Desativar" : "Reativar"}
                    </button>
                  </td>
                </tr>
              ))}
              {atividades.length === 0 && !loading && (
                <tr>
                  <td className="px-3 py-4 text-zinc-400 text-center" colSpan={7}>
                    Nenhuma atividade interna nesta empresa.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {modalAberto && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4">
          <div className="w-full max-w-lg bg-zinc-900 border border-zinc-700 rounded-xl p-6 space-y-4 shadow-xl">
            <h2 className="text-lg font-semibold text-zinc-100">{editando ? "Editar atividade" : "Nova atividade"}</h2>

            {erro && <div className="p-3 border border-red-700 rounded-lg bg-red-900/20 text-red-300 text-sm">{erro}</div>}

            <div className="space-y-3">
              <div className="space-y-1">
                <label className="text-sm text-zinc-300" htmlFor="ai-nome">Nome *</label>
                <input
                  id="ai-nome"
                  value={nome}
                  onChange={(e) => setNome(e.target.value)}
                  placeholder="Ex.: Treinamento"
                  maxLength={60}
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                />
              </div>

              <div className="space-y-1">
                <label className="text-sm text-zinc-300" htmlFor="ai-codigo">Código</label>
                <input
                  id="ai-codigo"
                  value={codigo}
                  onChange={(e) => setCodigo(e.target.value)}
                  placeholder="Deixe vazio para gerar a partir do nome"
                  maxLength={40}
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100 font-mono"
                />
                <small className="text-zinc-500 block">
                  Letras minúsculas, números e sublinhado; não pode repetir. É o que os relatórios usam para reconhecer a atividade.
                </small>
              </div>

              <div className="space-y-1">
                <label className="text-sm text-zinc-300" htmlFor="ai-ordem">Ordem</label>
                <input
                  id="ai-ordem"
                  type="number"
                  min={0}
                  max={32000}
                  value={ordem}
                  onChange={(e) => setOrdem(e.target.value)}
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                />
                <small className="text-zinc-500 block">Posição na lista de quem lança hora. Menor aparece primeiro.</small>
              </div>

              <label className="flex items-start gap-2 text-sm text-zinc-300">
                <input type="checkbox" checked={pedeCliente} onChange={(e) => setPedeCliente(e.target.checked)} className="w-4 h-4 mt-0.5" />
                <span>
                  Pede cliente e orçamento
                  <small className="text-zinc-500 block">Quem lança informa o cliente e qual orçamento. Fica fora do tablet da fábrica.</small>
                </span>
              </label>

              <label className="flex items-center gap-2 text-sm text-zinc-300">
                <input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="w-4 h-4" />
                Ativa
              </label>
            </div>

            <div className="border-t border-zinc-700 pt-4 flex justify-end gap-2">
              <button onClick={() => setModalAberto(false)} disabled={loading} className="px-4 py-2 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm">
                Cancelar
              </button>
              <button onClick={salvar} disabled={loading} className="px-4 py-2 rounded bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm">
                {loading ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
