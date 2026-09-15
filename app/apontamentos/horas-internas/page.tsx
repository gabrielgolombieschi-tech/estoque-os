"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { supabaseBrowser } from "@/lib/supabase/client";
import "../horas-internas.css";

// Para onde foram as horas que não são de OS: por atividade, por pessoa e, no
// Comercial, por cliente e orçamento. É TEMPO, não dinheiro, de propósito: a hora
// interna fica fora de todo custo (docs/horas-internas.md), e esta tela responde
// "quanto esforço foi para cada coisa", não "quanto custou".

type LinhaResumo = {
  atividade_id: string;
  atividade_codigo: string;
  atividade_nome: string;
  colaborador_id: string;
  colaborador_nome: string;
  cliente_id: number | null;
  cliente_nome: string | null;
  orcamento_descricao: string | null;
  horas: number | string;
  lancamentos: number | string;
  primeiro_dia: string;
  ultimo_dia: string;
};

type Orcamento = { descricao: string; horas: number; pessoas: Map<string, number> };
type Cliente = { chave: string; nome: string; horas: number; orcamentos: Map<string, Orcamento> };
type Pessoa = { id: string; nome: string; horas: number; lancamentos: number };
type Atividade = {
  id: string;
  codigo: string;
  nome: string;
  horas: number;
  lancamentos: number;
  primeiro_dia: string;
  ultimo_dia: string;
  pessoas: Map<string, Pessoa>;
  clientes: Map<string, Cliente>;
};

const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];

function numero(value: unknown) {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function arredonda(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function isoLocal(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function inicioDoMes(ano: number, mes: number) {
  return isoLocal(new Date(ano, mes - 1, 1, 12));
}

function fimDoMes(ano: number, mes: number) {
  return isoLocal(new Date(ano, mes, 0, 12));
}

function dataBR(iso: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return iso || "—";
  const [ano, mes, dia] = iso.split("-");
  return `${dia}/${mes}/${ano}`;
}

function formatHoras(value: number) {
  return new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value);
}

function formatHoraMinuto(value: number) {
  const totalMinutos = Math.round(value * 60);
  const horas = Math.floor(totalMinutos / 60);
  return `${horas}h${String(totalMinutos % 60).padStart(2, "0")}`;
}

function titleCase(value: string) {
  return value
    .trim()
    .toLocaleLowerCase("pt-BR")
    .split(/(\s+|-)/)
    .map((parte) => (/^(\s+|-)$/.test(parte) || ["da", "das", "de", "do", "dos", "e"].includes(parte) ? parte : parte ? `${parte.charAt(0).toLocaleUpperCase("pt-BR")}${parte.slice(1)}` : parte))
    .join("");
}

function mensagemErro(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (error && typeof error === "object" && "message" in error) return String((error as { message?: unknown }).message ?? "");
  return "sem detalhes";
}

// Agrupa as linhas do banco (uma por atividade × pessoa × cliente × orçamento) na
// árvore que a tela mostra. A ordem das atividades já vem do banco (campo ordem).
function agrupar(linhas: LinhaResumo[]) {
  const atividades = new Map<string, Atividade>();
  for (const linha of linhas) {
    const horas = numero(linha.horas);
    const lancamentos = numero(linha.lancamentos);
    let atividade = atividades.get(linha.atividade_id);
    if (!atividade) {
      atividade = {
        id: linha.atividade_id,
        codigo: linha.atividade_codigo,
        nome: linha.atividade_nome,
        horas: 0,
        lancamentos: 0,
        primeiro_dia: linha.primeiro_dia,
        ultimo_dia: linha.ultimo_dia,
        pessoas: new Map(),
        clientes: new Map(),
      };
      atividades.set(linha.atividade_id, atividade);
    }
    atividade.horas = arredonda(atividade.horas + horas);
    atividade.lancamentos += lancamentos;
    if (linha.primeiro_dia < atividade.primeiro_dia) atividade.primeiro_dia = linha.primeiro_dia;
    if (linha.ultimo_dia > atividade.ultimo_dia) atividade.ultimo_dia = linha.ultimo_dia;

    const pessoa = atividade.pessoas.get(linha.colaborador_id) ?? { id: linha.colaborador_id, nome: linha.colaborador_nome, horas: 0, lancamentos: 0 };
    pessoa.horas = arredonda(pessoa.horas + horas);
    pessoa.lancamentos += lancamentos;
    atividade.pessoas.set(linha.colaborador_id, pessoa);

    // Só o Comercial traz cliente e orçamento; nas outras a linha vem sem os dois.
    if (linha.cliente_nome || linha.orcamento_descricao) {
      const chaveCliente = linha.cliente_id != null ? `id:${linha.cliente_id}` : `nome:${(linha.cliente_nome ?? "").trim().toLocaleLowerCase("pt-BR")}`;
      const cliente = atividade.clientes.get(chaveCliente) ?? { chave: chaveCliente, nome: linha.cliente_nome?.trim() || "Cliente não informado", horas: 0, orcamentos: new Map() };
      cliente.horas = arredonda(cliente.horas + horas);
      const descricao = linha.orcamento_descricao?.trim() || "Sem orçamento informado";
      const orcamento = cliente.orcamentos.get(descricao) ?? { descricao, horas: 0, pessoas: new Map() };
      orcamento.horas = arredonda(orcamento.horas + horas);
      orcamento.pessoas.set(linha.colaborador_nome, arredonda((orcamento.pessoas.get(linha.colaborador_nome) ?? 0) + horas));
      cliente.orcamentos.set(descricao, orcamento);
      atividade.clientes.set(chaveCliente, cliente);
    }
  }
  return Array.from(atividades.values());
}

function ordenarPorHoras<T extends { horas: number }>(itens: Iterable<T>) {
  return Array.from(itens).sort((a, b) => b.horas - a.horas);
}

export default function HorasInternasPage() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { tenantId, empresaId } = useTenantEmpresa();
  const supabase = useMemo(() => supabaseBrowser(), []);
  const hoje = useMemo(() => new Date(), []);

  const [de, setDe] = useState(searchParams.get("de") || inicioDoMes(hoje.getFullYear(), hoje.getMonth() + 1));
  const [ate, setAte] = useState(searchParams.get("ate") || fimDoMes(hoje.getFullYear(), hoje.getMonth() + 1));
  const [linhas, setLinhas] = useState<LinhaResumo[]>([]);
  const [loading, setLoading] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("de", de);
    params.set("ate", ate);
    const proximo = params.toString();
    if (proximo !== searchParams.toString()) router.replace(`${pathname}?${proximo}`, { scroll: false });
  }, [ate, de, pathname, router, searchParams]);

  const carregar = useCallback(async () => {
    if (!tenantId || !empresaId) return;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(de) || !/^\d{4}-\d{2}-\d{2}$/.test(ate) || ate < de) return;
    setLoading(true);
    setErro(null);
    try {
      const tenantContext = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantContext.error) throw tenantContext.error;
      const empresaContext = await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
      if (empresaContext.error) throw empresaContext.error;
      const { data, error } = await supabase.rpc("web_horas_internas_resumo", { p_de: de, p_ate: ate });
      if (error) throw error;
      setLinhas((data ?? []) as LinhaResumo[]);
    } catch (loadError) {
      setLinhas([]);
      setErro(`Erro ao carregar as horas internas: ${mensagemErro(loadError)}`);
    } finally {
      setLoading(false);
    }
  }, [ate, de, empresaId, supabase, tenantId]);

  useEffect(() => {
    const timer = window.setTimeout(() => void carregar(), 0);
    return () => window.clearTimeout(timer);
  }, [carregar]);

  const atividades = useMemo(() => agrupar(linhas), [linhas]);
  const totalHoras = useMemo(() => arredonda(atividades.reduce((soma, item) => soma + item.horas, 0)), [atividades]);
  const totalLancamentos = useMemo(() => atividades.reduce((soma, item) => soma + item.lancamentos, 0), [atividades]);
  const pessoasDistintas = useMemo(() => new Set(linhas.map((linha) => linha.colaborador_id)).size, [linhas]);
  const maiorAtividade = Math.max(0, ...atividades.map((item) => item.horas));

  function mesAtual() {
    setDe(inicioDoMes(hoje.getFullYear(), hoje.getMonth() + 1));
    setAte(fimDoMes(hoje.getFullYear(), hoje.getMonth() + 1));
  }

  function mesPassado() {
    const referencia = new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1, 12);
    setDe(inicioDoMes(referencia.getFullYear(), referencia.getMonth() + 1));
    setAte(fimDoMes(referencia.getFullYear(), referencia.getMonth() + 1));
  }

  const mesInteiro = de.slice(0, 7) === ate.slice(0, 7) && de.endsWith("-01") && ate === fimDoMes(Number(ate.slice(0, 4)), Number(ate.slice(5, 7)));
  const rotuloPeriodo = mesInteiro
    ? `${MESES[Number(de.slice(5, 7)) - 1]} de ${de.slice(0, 4)}`
    : `${dataBR(de)} a ${dataBR(ate)}`;

  return (
    <div className="carteira-theme resumo-horas-page horas-internas-page w-full space-y-3">
      <header className="rh-page-header">
        <div>
          <div className="rh-breadcrumb"><span>Apontamentos</span><b>›</b><strong>Horas internas</strong></div>
          <h1>Para onde foram as horas</h1>
          <p>{rotuloPeriodo} · tempo em atividades internas, por atividade, pessoa, cliente e orçamento</p>
        </div>
        <div className="rh-page-actions">
          <Link href="/apontamentos" className="carteira-button">Lançar horas</Link>
          <button type="button" className="carteira-button" onClick={() => void carregar()} disabled={loading}>
            {loading ? "Atualizando..." : "Atualizar"}
          </button>
        </div>
      </header>

      <div className="rh-filter-bar">
        <div className="hi-atalhos">
          <button type="button" onClick={mesAtual}>Este mês</button>
          <button type="button" onClick={mesPassado}>Mês passado</button>
        </div>
        <label className="hi-periodo">
          <span>De</span>
          <input type="date" className="carteira-control rh-filter-pill" value={de} max={ate} onChange={(event) => setDe(event.target.value)} aria-label="Data inicial" />
        </label>
        <label className="hi-periodo">
          <span>Até</span>
          <input type="date" className="carteira-control rh-filter-pill" value={ate} min={de} onChange={(event) => setAte(event.target.value)} aria-label="Data final" />
        </label>
      </div>

      {erro && <div className="rh-error" role="alert">{erro}</div>}

      <section className="rh-stats" aria-label="Indicadores do período">
        <article>
          <span>Horas internas</span>
          <strong>{formatHoras(totalHoras)} h</strong>
          <small>{formatHoraMinuto(totalHoras)} · {totalLancamentos} lançamento{totalLancamentos === 1 ? "" : "s"}</small>
        </article>
        <article>
          <span>Atividades com hora</span>
          <strong>{atividades.length}</strong>
          <small>{atividades.length ? atividades.map((item) => item.nome).join(", ") : "Nenhuma no período"}</small>
        </article>
        <article>
          <span>Pessoas</span>
          <strong>{pessoasDistintas}</strong>
          <small>Com hora interna no período</small>
        </article>
        <article>
          <span>Maior atividade</span>
          <strong>{atividades.length ? formatHoras(maiorAtividade) : "0,00"} h</strong>
          <small>{atividades.length ? ordenarPorHoras(atividades)[0].nome : "—"}</small>
        </article>
      </section>

      <div className="rh-scope-note">
        Hora interna é tempo, não custo: nada aqui vira dinheiro nem entra no custo de OS. Serve para decidir onde a equipe
        está gastando esforço. Hora em OS está no <Link href="/apontamentos/resumo-mensal" className="underline">Resumo de horas</Link>.
      </div>

      {loading && atividades.length === 0 ? (
        <div className="rh-empty rh-bordered">Carregando horas internas...</div>
      ) : atividades.length === 0 ? (
        <section className="rh-select-empty">
          <strong>Nenhuma hora interna no período</strong>
          <span>Quando alguém lançar Comercial, Treinamento ou outra atividade interna, ela aparece aqui.</span>
        </section>
      ) : (
        <div>
          {atividades.map((atividade) => {
            const pessoas = ordenarPorHoras(atividade.pessoas.values());
            const clientes = ordenarPorHoras(atividade.clientes.values());
            const largura = maiorAtividade > 0 ? Math.max(2, (atividade.horas / maiorAtividade) * 100) : 0;
            return (
              <section key={atividade.id} className="hi-atividade" aria-label={atividade.nome}>
                <div className="hi-linha hi-atividade-head">
                  <div>
                    <h2>{atividade.nome}</h2>
                    <small>{atividade.codigo} · {pessoas.length} pessoa{pessoas.length === 1 ? "" : "s"} · {atividade.lancamentos} lançamento{atividade.lancamentos === 1 ? "" : "s"} · {dataBR(atividade.primeiro_dia)}{atividade.primeiro_dia !== atividade.ultimo_dia ? ` a ${dataBR(atividade.ultimo_dia)}` : ""}</small>
                  </div>
                  <span className="rh-hours-track"><i style={{ width: `${largura}%` }} /></span>
                  <span className="rh-hour-pair"><strong>{formatHoras(atividade.horas)} h</strong><small>{formatHoraMinuto(atividade.horas)}</small></span>
                </div>

                <div className="hi-grupo">Por pessoa</div>
                {pessoas.map((pessoa) => (
                  <div key={pessoa.id} className="hi-linha">
                    <span className="hi-nome">{titleCase(pessoa.nome)}</span>
                    <span className="rh-hours-track"><i style={{ width: `${Math.max(2, (pessoa.horas / atividade.horas) * 100)}%` }} /></span>
                    <span className="rh-hour-pair"><strong>{formatHoras(pessoa.horas)} h</strong><small>{pessoa.lancamentos} lançamento{pessoa.lancamentos === 1 ? "" : "s"}</small></span>
                  </div>
                ))}

                {clientes.length > 0 && (
                  <>
                    <div className="hi-grupo">Por cliente e orçamento</div>
                    {clientes.map((cliente) => (
                      <div key={cliente.chave}>
                        <div className="hi-linha is-cliente">
                          <span className="hi-nome">{cliente.nome}{cliente.chave.startsWith("nome:") ? <small>Nome digitado, ainda sem cadastro</small> : null}</span>
                          <span className="rh-hours-track"><i style={{ width: `${Math.max(2, (cliente.horas / atividade.horas) * 100)}%` }} /></span>
                          <span className="rh-hour-pair"><strong>{formatHoras(cliente.horas)} h</strong><small>{cliente.orcamentos.size} orçamento{cliente.orcamentos.size === 1 ? "" : "s"}</small></span>
                        </div>
                        {ordenarPorHoras(cliente.orcamentos.values()).map((orcamento) => (
                          <div key={orcamento.descricao} className="hi-linha is-orcamento">
                            <span className="hi-nome">
                              {orcamento.descricao}
                              <small>{Array.from(orcamento.pessoas.entries()).sort((a, b) => b[1] - a[1]).map(([nome, horas]) => `${titleCase(nome)} ${formatHoras(horas)} h`).join(" · ")}</small>
                            </span>
                            <span className="rh-hours-track"><i style={{ width: `${Math.max(2, (orcamento.horas / atividade.horas) * 100)}%` }} /></span>
                            <span className="rh-hour-pair"><strong>{formatHoras(orcamento.horas)} h</strong><small>{formatHoraMinuto(orcamento.horas)}</small></span>
                          </div>
                        ))}
                      </div>
                    ))}
                  </>
                )}
              </section>
            );
          })}

          <footer className="hi-total">
            <span>Total de horas internas · {atividades.length} atividade{atividades.length === 1 ? "" : "s"} · {pessoasDistintas} pessoa{pessoasDistintas === 1 ? "" : "s"}</span>
            <strong>{formatHoras(totalHoras)} h</strong>
          </footer>
        </div>
      )}
    </div>
  );
}
