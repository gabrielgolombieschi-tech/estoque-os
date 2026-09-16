"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import {
  EXCECAO_ALIQUOTA_12_DESTINATARIO,
  ehDestinacaoValida,
  rotuloDestinacao,
} from "@/supabase/functions/_shared/fiscal/icms-sc-destinacao";

/**
 * Excecao "ICMS 12% por exigencia do destinatario" na conferencia da NF-e (OV e OS).
 *
 * Aparece so quando cabe: destinatario contribuinte (indIEDest 1), operacao interna e
 * destinacao manutencao, uso e consumo ou ativo imobilizado. Ativar pede OC e evidencia
 * (texto ou anexo do e-mail do cliente); o banco grava quem ativou e quando
 * (f.fn_nfe_excecao_aliquota_ativar). As regras fiscais ficam no banco e no montador —
 * aqui so se mostra, ativa e desativa.
 */

export type ExcecaoIcms12Ativa = {
  id: string;
  numero_oc: string;
  evidencia_texto: string | null;
  evidencia_arquivo_nome: string | null;
  evidencia_arquivo_tamanho: number | null;
  ativada_em: string;
  ativada_por_nome: string | null;
};

type Consulta = {
  indicador_ie: string | null;
  destinatario_contribuinte: boolean;
  pedido_cliente: string | null;
  ativa: boolean;
  excecao: ExcecaoIcms12Ativa | null;
};

const TAMANHO_MAXIMO_ANEXO = 5 * 1024 * 1024;

function dataHora(valor: string) {
  const data = new Date(valor);
  return Number.isNaN(data.getTime())
    ? valor
    : data.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" });
}

function textoErro(cause: unknown) {
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return String(cause);
}

function lerComoBase64(arquivo: File) {
  return new Promise<string>((resolve, reject) => {
    const leitor = new FileReader();
    leitor.onload = () => {
      const resultado = String(leitor.result ?? "");
      resolve(resultado.slice(resultado.indexOf(",") + 1));
    };
    leitor.onerror = () => reject(new Error("Não foi possível ler o anexo."));
    leitor.readAsDataURL(arquivo);
  });
}

/** Texto da confirmacao que substitui a trava "manutencao exige 17%" quando a excecao esta ativa. */
export function confirmacaoExcecaoIcms12(excecao: ExcecaoIcms12Ativa, destinacao: string) {
  const rotulo = ehDestinacaoValida(destinacao) ? rotuloDestinacao(destinacao) : destinacao.toLowerCase();
  return `ICMS 12% POR EXIGÊNCIA DO DESTINATÁRIO\n\n`
    + `A destinação ${rotulo} exige alíquota interna de 17%. Esta nota sai com 12% nos itens sem cBenef SC820006, `
    + `por determinação do destinatário (OC nº ${excecao.numero_oc}), `
    + `exceção ativada por ${excecao.ativada_por_nome ?? "usuário sem nome"} em ${dataHora(excecao.ativada_em)}.\n\n`
    + "O destinatário responde solidariamente pela diferença de alíquota (RICMS/SC-01, art. 26, § 6º).\n\n"
    + "Confirma a emissão com 12%?";
}

export default function ExcecaoIcms12Destinatario({
  solicitacaoId,
  destinacao,
  interna,
  bloqueado,
  depoisDeAlterar,
  onChange,
}: {
  solicitacaoId: string | null;
  /** Codigo da destinacao na tela (ainda pode nao estar gravado). */
  destinacao: string;
  interna: boolean;
  /** Emissao em andamento, autorizada ou conferencia de producao: so leitura. */
  bloqueado: boolean;
  /** O que a pessoa precisa fazer para a mudanca valer (ex.: reconferir a OS). */
  depoisDeAlterar?: string;
  onChange?: (excecao: ExcecaoIcms12Ativa | null) => void;
}) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [consulta, setConsulta] = useState<Consulta | null>(null);
  const [aberto, setAberto] = useState(false);
  const [numeroOc, setNumeroOc] = useState("");
  const [evidenciaTexto, setEvidenciaTexto] = useState("");
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  // A tela passa uma funcao nova a cada render; o ref evita recarregar por isso e evita
  // chamar a versao antiga depois de ativar ou desativar.
  const avisarMudanca = useRef(onChange);
  useEffect(() => { avisarMudanca.current = onChange; });

  const carregar = useCallback(async () => {
    if (!solicitacaoId) {
      setConsulta(null);
      avisarMudanca.current?.(null);
      return;
    }
    const { data, error } = await supabase.schema("f").rpc("fn_nfe_excecao_aliquota_consultar", { p_solicitacao_id: solicitacaoId });
    if (error) {
      setErro(textoErro(error));
      return;
    }
    const resultado = data as Consulta;
    setConsulta(resultado);
    avisarMudanca.current?.(resultado.ativa ? resultado.excecao : null);
  }, [solicitacaoId, supabase]);

  useEffect(() => { void carregar(); }, [carregar]);

  const destinacaoCabe = (EXCECAO_ALIQUOTA_12_DESTINATARIO.destinacoes as string[]).includes(destinacao);
  const contribuinte = consulta?.destinatario_contribuinte === true;
  const disponivel = contribuinte && interna && destinacaoCabe;
  const excecao = consulta?.ativa ? consulta.excecao : null;

  if (!solicitacaoId) {
    return destinacaoCabe && interna ? (
      <p className="rounded border border-zinc-800 bg-zinc-900/30 px-3 py-2 text-xs text-zinc-400">
        Cliente exige ICMS 12% na OC? Salve o rascunho primeiro; depois a exceção pode ser ativada aqui.
      </p>
    ) : null;
  }
  // Nao contribuinte, interestadual ou destinacao que ja tem 12%: a opcao nao aparece.
  if (!consulta || (!disponivel && !excecao)) return null;

  async function ativar() {
    if (!solicitacaoId) return;
    setErro(null);
    setAviso(null);
    if (!numeroOc.trim()) {
      setErro("Informe o número da OC do cliente.");
      return;
    }
    if (!evidenciaTexto.trim() && !arquivo) {
      setErro("Informe a evidência: cole o texto do e-mail do cliente ou anexe o arquivo.");
      return;
    }
    if (arquivo && arquivo.size > TAMANHO_MAXIMO_ANEXO) {
      setErro("O anexo passa de 5 MB.");
      return;
    }
    setOcupado(true);
    try {
      const { error } = await supabase.schema("f").rpc("fn_nfe_excecao_aliquota_ativar", {
        p_solicitacao_id: solicitacaoId,
        p_numero_oc: numeroOc.trim(),
        p_evidencia_texto: evidenciaTexto.trim() || null,
        p_arquivo_nome: arquivo?.name ?? null,
        p_arquivo_tipo: arquivo?.type || null,
        p_arquivo_base64: arquivo ? await lerComoBase64(arquivo) : null,
        p_destinacao: destinacao,
      });
      if (error) throw error;
      setAberto(false);
      setEvidenciaTexto("");
      setArquivo(null);
      setAviso(`Exceção ativada.${depoisDeAlterar ? ` ${depoisDeAlterar}` : ""}`);
      await carregar();
    } catch (cause) {
      setErro(textoErro(cause));
    } finally {
      setOcupado(false);
    }
  }

  async function desativar() {
    if (!solicitacaoId) return;
    if (!window.confirm("Desativar a exceção de ICMS 12%? A nota volta à alíquota do perfil fiscal e a trava de 17% volta a bloquear.")) return;
    setErro(null);
    setAviso(null);
    setOcupado(true);
    try {
      const { error } = await supabase.schema("f").rpc("fn_nfe_excecao_aliquota_desativar", { p_solicitacao_id: solicitacaoId });
      if (error) throw error;
      setAviso(`Exceção desativada.${depoisDeAlterar ? ` ${depoisDeAlterar}` : ""}`);
      await carregar();
    } catch (cause) {
      setErro(textoErro(cause));
    } finally {
      setOcupado(false);
    }
  }

  async function baixarEvidencia(id: string) {
    setErro(null);
    const { data, error } = await supabase.schema("f").rpc("fn_nfe_excecao_aliquota_evidencia", { p_excecao_id: id });
    if (error) {
      setErro(textoErro(error));
      return;
    }
    const evidencia = data as { nome: string | null; tipo: string; base64: string | null };
    if (!evidencia.base64) return;
    const bytes = Uint8Array.from(atob(evidencia.base64), (caractere) => caractere.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([bytes], { type: evidencia.tipo }));
    const link = document.createElement("a");
    link.href = url;
    link.download = evidencia.nome ?? "evidencia";
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
  }

  function abrirFormulario() {
    setNumeroOc(consulta?.pedido_cliente ?? "");
    setEvidenciaTexto("");
    setArquivo(null);
    setErro(null);
    setAberto(true);
  }

  return (
    <section className={`space-y-3 rounded-lg border p-4 ${excecao ? "border-amber-700 bg-amber-950/20" : "border-zinc-800"}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="font-medium">
            ICMS 12% por exigência do destinatário
            {excecao ? <span className="ml-2 rounded-full border border-amber-600 px-2 py-0.5 text-xs font-normal text-amber-200">ativa</span> : null}
          </h3>
          <p className="mt-1 max-w-3xl text-xs text-zinc-400">
            A destinação {ehDestinacaoValida(destinacao) ? rotuloDestinacao(destinacao) : "declarada"} vai a 17%. Se o cliente
            exige 12% na OC, a nota sai com 12% ({EXCECAO_ALIQUOTA_12_DESTINATARIO.baseLegal}) nos itens sem cBenef SC820006,
            CST 00, e cita a OC e a responsabilidade solidária dele pela diferença. Itens com SC820006, IPI e consumidor final = 1 não mudam.
          </p>
        </div>
        {!excecao && !aberto && !bloqueado ? (
          <button type="button" onClick={abrirFormulario} className="rounded-md border border-amber-700 px-3 py-1.5 text-xs text-amber-100 hover:bg-amber-950/40">
            Aplicar exceção
          </button>
        ) : null}
      </div>

      {excecao ? (
        <div className="grid gap-2 text-sm md:grid-cols-2">
          <div><span className="text-zinc-500">OC:</span> <strong>{excecao.numero_oc}</strong></div>
          <div><span className="text-zinc-500">Ativada por:</span> {excecao.ativada_por_nome ?? "—"} em {dataHora(excecao.ativada_em)}</div>
          <div className="md:col-span-2">
            <span className="text-zinc-500">Evidência:</span>{" "}
            {excecao.evidencia_texto ? <span className="whitespace-pre-line">{excecao.evidencia_texto}</span> : null}
            {excecao.evidencia_arquivo_nome ? (
              <button type="button" onClick={() => void baixarEvidencia(excecao.id)} className="ml-2 underline hover:text-amber-200">
                {excecao.evidencia_arquivo_nome}
              </button>
            ) : null}
          </div>
          {!disponivel ? (
            <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-2 text-red-200 md:col-span-2">
              A exceção não cabe mais nesta nota ({!contribuinte ? "destinatário não contribuinte" : !interna ? "operação interestadual" : "destinação sem 17%"}). Desative para emitir.
            </div>
          ) : null}
          {!bloqueado ? (
            <div className="md:col-span-2">
              <button type="button" onClick={() => void desativar()} disabled={ocupado} className="rounded-md border border-zinc-700 px-3 py-1.5 text-xs hover:bg-zinc-900 disabled:opacity-40">
                Desativar exceção
              </button>
            </div>
          ) : null}
        </div>
      ) : null}

      {aberto && !excecao ? (
        <div className="grid gap-3 md:grid-cols-2">
          <label className="space-y-1 text-xs text-zinc-400">
            Número da OC <span className="text-amber-300">obrigatório</span>
            <input
              className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500"
              value={numeroOc}
              onChange={(event) => setNumeroOc(event.target.value)}
              maxLength={60}
              placeholder="Ex.: 4500123456"
            />
          </label>
          <label className="space-y-1 text-xs text-zinc-400">
            Anexo do e-mail do cliente <span className="text-zinc-500">(até 5 MB)</span>
            <input
              type="file"
              className="block w-full text-sm text-zinc-300 file:mr-3 file:rounded-md file:border file:border-zinc-700 file:bg-zinc-900 file:px-3 file:py-1.5 file:text-xs file:text-zinc-100"
              onChange={(event) => setArquivo(event.target.files?.[0] ?? null)}
            />
          </label>
          <label className="space-y-1 text-xs text-zinc-400 md:col-span-2">
            Evidência em texto <span className="text-zinc-500">(ou o anexo acima)</span>
            <textarea
              className="min-h-20 w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500"
              value={evidenciaTexto}
              onChange={(event) => setEvidenciaTexto(event.target.value)}
              placeholder="Cole o trecho do e-mail em que o cliente exige 12% e informa a utilização."
            />
          </label>
          <div className="flex flex-wrap gap-2 md:col-span-2">
            <button type="button" onClick={() => void ativar()} disabled={ocupado} className="rounded-md bg-amber-600 px-3 py-2 text-sm font-medium text-white hover:bg-amber-500 disabled:opacity-40">
              {ocupado ? "Ativando..." : "Ativar exceção"}
            </button>
            <button type="button" onClick={() => setAberto(false)} disabled={ocupado} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900">
              Cancelar
            </button>
          </div>
        </div>
      ) : null}

      {erro ? <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-2 text-sm text-red-200">{erro}</div> : null}
      {aviso ? <div role="status" className="text-xs text-amber-200">{aviso}</div> : null}
    </section>
  );
}
