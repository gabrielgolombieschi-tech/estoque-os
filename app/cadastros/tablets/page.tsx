"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabaseBrowser } from "@/lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";

// Tablets de apontamento: contas autorizadas a operar o modo compartilhado do
// app (PIN por colaborador). Quem decide de verdade e o banco
// (web_tablet_salvar: Admin ou Diretor); a tela so mostra e pede.

type Tablet = {
  id: string;
  nome: string;
  auth_user_id: string;
  usuario_nome: string | null;
  usuario_email: string | null;
  inatividade_segundos: number;
  ativo: boolean;
  criado_em: string;
  ultima_identificacao_em: string | null;
  identificacoes_hoje: number;
};

type ContaElegivel = {
  auth_user_id: string;
  nome: string;
  email: string;
  ja_autorizado: boolean;
};

type RetornoRpc = { sucesso: boolean; id?: string; erros?: { tipo: string; mensagem: string }[] };

function mensagemErro(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim()) return msg;
  }
  return fallback;
}

function dataHoraBr(iso: string | null) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(d);
}

export default function TabletsPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId } = usePermissions();
  const { empresaId } = useTenantEmpresa();

  const [tablets, setTablets] = useState<Tablet[]>([]);
  const [contas, setContas] = useState<ContaElegivel[]>([]);
  const [loading, setLoading] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [semAcesso, setSemAcesso] = useState(false);
  const [ok, setOk] = useState<string | null>(null);

  const [modalAberto, setModalAberto] = useState(false);
  const [editando, setEditando] = useState<Tablet | null>(null);
  const [contaId, setContaId] = useState("");
  const [nome, setNome] = useState("");
  const [inatividade, setInatividade] = useState("60");
  const [ativo, setAtivo] = useState(true);

  const carregar = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) return;
    setLoading(true);
    setErro(null);
    try {
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;
      const { error: empresaErr } = await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
      if (empresaErr) throw empresaErr;

      const [tabletsRes, contasRes] = await Promise.all([
        supabase.rpc("web_tablet_listar"),
        supabase.rpc("web_tablet_contas_elegiveis"),
      ]);
      if (tabletsRes.error) {
        if (/não pode administrar/i.test(tabletsRes.error.message)) {
          setSemAcesso(true);
          return;
        }
        throw tabletsRes.error;
      }
      if (contasRes.error) throw contasRes.error;
      setSemAcesso(false);
      setTablets((tabletsRes.data ?? []) as Tablet[]);
      setContas((contasRes.data ?? []) as ContaElegivel[]);
    } catch (e: unknown) {
      setErro(mensagemErro(e, "Falha ao carregar os tablets."));
    } finally {
      setLoading(false);
    }
  }, [empresaId, supabase, tenantId]);

  useEffect(() => {
    const timer = window.setTimeout(() => void carregar(), 0);
    return () => window.clearTimeout(timer);
  }, [carregar]);

  function abrirNovo() {
    setEditando(null);
    setContaId("");
    setNome("");
    setInatividade("60");
    setAtivo(true);
    setErro(null);
    setOk(null);
    setModalAberto(true);
  }

  function abrirEditar(tablet: Tablet) {
    setEditando(tablet);
    setContaId(tablet.auth_user_id);
    setNome(tablet.nome);
    setInatividade(String(tablet.inatividade_segundos));
    setAtivo(tablet.ativo);
    setErro(null);
    setOk(null);
    setModalAberto(true);
  }

  async function salvar() {
    if (!supabase) return;
    const segundos = Number(inatividade);
    if (!contaId) {
      setErro("Escolha a conta do tablet.");
      return;
    }
    if (nome.trim().length < 2) {
      setErro("Dê um nome ao tablet (ex.: Tablet da produção).");
      return;
    }
    if (!Number.isInteger(segundos) || segundos < 15 || segundos > 900) {
      setErro("Inatividade entre 15 e 900 segundos.");
      return;
    }
    setLoading(true);
    setErro(null);
    try {
      const { data, error } = await supabase.rpc("web_tablet_salvar", {
        p_auth_user_id: contaId,
        p_nome: nome.trim(),
        p_inatividade_segundos: segundos,
        p_ativo: ativo,
      });
      if (error) throw error;
      const retorno = (data ?? {}) as RetornoRpc;
      if (!retorno.sucesso) throw new Error(retorno.erros?.[0]?.mensagem ?? "Não foi possível salvar o tablet.");
      setModalAberto(false);
      setOk(editando ? "Tablet atualizado." : "Tablet autorizado. Entre no aplicativo com essa conta: ele abre direto na tela do PIN.");
      await carregar();
    } catch (e: unknown) {
      setErro(mensagemErro(e, "Erro ao salvar."));
    } finally {
      setLoading(false);
    }
  }

  async function alternarAtivo(tablet: Tablet) {
    if (!supabase) return;
    const acao = tablet.ativo ? "Desativar" : "Reativar";
    if (!confirm(`${acao} o tablet "${tablet.nome}"?${tablet.ativo ? " Ninguém mais conseguirá apontar horas por ele até reativar." : ""}`)) return;
    setLoading(true);
    setErro(null);
    try {
      const { data, error } = await supabase.rpc("web_tablet_salvar", {
        p_auth_user_id: tablet.auth_user_id,
        p_nome: tablet.nome,
        p_inatividade_segundos: tablet.inatividade_segundos,
        p_ativo: !tablet.ativo,
      });
      if (error) throw error;
      const retorno = (data ?? {}) as RetornoRpc;
      if (!retorno.sucesso) throw new Error(retorno.erros?.[0]?.mensagem ?? "Não foi possível alterar o tablet.");
      await carregar();
    } catch (e: unknown) {
      setErro(mensagemErro(e, "Erro ao alterar."));
    } finally {
      setLoading(false);
    }
  }

  const contasDisponiveis = contas.filter((conta) => !conta.ja_autorizado || conta.auth_user_id === contaId);

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center gap-3 flex-wrap">
        <h1 className="text-2xl font-bold">Tablets de apontamento</h1>
        {!semAcesso && (
          <button
            onClick={abrirNovo}
            disabled={loading}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            + Autorizar tablet
          </button>
        )}
        <Link href="/colaboradores" className="text-sm text-sky-400 hover:text-sky-300 underline">
          PINs dos colaboradores
        </Link>
        {loading && <span className="text-zinc-400">Carregando...</span>}
      </div>

      <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-300 space-y-1">
        <p>
          O tablet compartilhado usa uma conta do sistema só para o aparelho, com o perfil <strong>Apontador</strong> ou
          <strong> Painel de TV</strong>, e sem vínculo com colaborador. Quem lança as horas é o colaborador que digita o PIN.
        </p>
        <p className="text-zinc-400">
          Passos: criar a conta (Admin › Usuários, perfil Apontador nesta empresa), autorizar aqui, entrar no aplicativo com ela e
          definir os PINs: no aplicativo, em Perfil › Configurações › PINs do tablet, o próprio colaborador digita o PIN dele; ou
          aqui no web, em <Link href="/colaboradores" className="underline">Colaboradores</Link>. Só Admin e Diretor definem PINs.
        </p>
        <p className="text-zinc-400">
          Use <strong>Apontador</strong> quando a conta for só do tablet: ela não abre nada do sistema, e é a escolha mais segura
          para um aparelho que fica solto na fábrica. Use <strong>Painel de TV</strong> quando a mesma conta também for tocar as
          televisões — aí é um login só para as duas coisas, e quem tiver a senha do tablet consegue abrir as telas de TV no
          navegador.
        </p>
      </div>

      {semAcesso && (
        <div className="p-3 border border-amber-700/50 rounded-lg bg-amber-950/20 text-amber-200 text-sm">
          Somente Admin ou Diretor autoriza tablets e define os PINs dos colaboradores.
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
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Tablet</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Conta</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300 text-right">Inatividade</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Última identificação</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300 text-right">Hoje</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Situação</th>
                <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Ações</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {tablets.map((tablet) => (
                <tr key={tablet.id} className="hover:bg-zinc-900/40">
                  <td className="px-3 py-2 text-zinc-200">{tablet.nome}</td>
                  <td className="px-3 py-2 text-zinc-300">
                    <div>{tablet.usuario_nome ?? "—"}</div>
                    <div className="text-xs text-zinc-500">{tablet.usuario_email ?? tablet.auth_user_id}</div>
                  </td>
                  <td className="px-3 py-2 text-zinc-300 text-right">{tablet.inatividade_segundos} s</td>
                  <td className="px-3 py-2 text-zinc-300">{dataHoraBr(tablet.ultima_identificacao_em)}</td>
                  <td className="px-3 py-2 text-zinc-300 text-right">{tablet.identificacoes_hoje}</td>
                  <td className="px-3 py-2">
                    <span className={`px-2 py-0.5 rounded-full text-xs ${tablet.ativo ? "bg-green-900/40 text-green-400 border border-green-800" : "bg-zinc-800 text-zinc-400 border border-zinc-700"}`}>
                      {tablet.ativo ? "Ativo" : "Desativado"}
                    </span>
                  </td>
                  <td className="px-3 py-2 space-x-2 whitespace-nowrap">
                    <button onClick={() => abrirEditar(tablet)} disabled={loading} className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm">
                      Editar
                    </button>
                    <button onClick={() => alternarAtivo(tablet)} disabled={loading} className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm">
                      {tablet.ativo ? "Desativar" : "Reativar"}
                    </button>
                  </td>
                </tr>
              ))}
              {tablets.length === 0 && (
                <tr>
                  <td className="px-3 py-4 text-zinc-400 text-center" colSpan={7}>
                    Nenhum tablet autorizado nesta empresa.
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
            <h2 className="text-lg font-semibold text-zinc-100">{editando ? "Editar tablet" : "Autorizar tablet"}</h2>

            {erro && <div className="p-3 border border-red-700 rounded-lg bg-red-900/20 text-red-300 text-sm">{erro}</div>}

            <div className="space-y-3">
              <div className="space-y-1">
                <label className="text-sm text-zinc-300">Conta do tablet *</label>
                <select
                  value={contaId}
                  onChange={(e) => setContaId(e.target.value)}
                  disabled={Boolean(editando)}
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100 disabled:opacity-60"
                  aria-label="Conta do tablet"
                >
                  <option value="">Selecione</option>
                  {contasDisponiveis.map((conta) => (
                    <option key={conta.auth_user_id} value={conta.auth_user_id}>
                      {conta.nome} ({conta.email})
                    </option>
                  ))}
                </select>
                <small className="text-zinc-500 block">
                  Aparecem só contas com perfil Apontador ou Painel de TV nesta empresa, e sem colaborador vinculado.
                  {contasDisponiveis.length === 0 && !editando ? " Nenhuma disponível: crie a conta em Admin › Usuários." : ""}
                </small>
              </div>

              <div className="space-y-1">
                <label className="text-sm text-zinc-300">Nome do tablet *</label>
                <input
                  value={nome}
                  onChange={(e) => setNome(e.target.value)}
                  placeholder="Ex.: Tablet da produção"
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                  aria-label="Nome do tablet"
                />
              </div>

              <div className="space-y-1">
                <label className="text-sm text-zinc-300">Inatividade (segundos)</label>
                <input
                  type="number"
                  min={15}
                  max={900}
                  value={inatividade}
                  onChange={(e) => setInatividade(e.target.value)}
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                  aria-label="Inatividade em segundos"
                />
                <small className="text-zinc-500 block">Sem toque por esse tempo, o tablet esquece o colaborador e volta ao PIN. Padrão: 60.</small>
              </div>

              <label className="flex items-center gap-2 text-sm text-zinc-300">
                <input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="w-4 h-4" />
                Ativo
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
