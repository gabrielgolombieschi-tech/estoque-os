"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { supabaseBrowser } from "@/lib/supabase/client";
import { emailsDoCadastro, separarEmails, type ContatoNfe } from "@/lib/nfe/emailsCliente";

/**
 * Campo "Entregar ao cliente" com a lista de e-mails daquele cliente.
 *
 * Pedido do Gabriel (18/09/2026, entrega da NF-e 2/33): com o campo selecionado, Enter abre a
 * lista de e-mails do cliente para escolher; a lista cresce sozinha, porque todo e-mail novo
 * digitado aqui e enviado pelo botao e cadastrado (public.clientes_registrar_emails_nfe).
 *
 * A lista junta o cadastro do cliente (financeiro e principal) com os contatos ja usados
 * (public.cliente_contatos, os mesmos do orcamento). Endereco do dominio da propria empresa
 * aparece marcado e nao pode ser escolhido.
 */

export type ContatoSalvoNfe = {
  id: number;
  email: string;
  nome: string | null;
  setor: string | null;
  principal: boolean;
  vezes_usado: number | null;
  ultimo_uso_em: string | null;
};

type Opcao = { email: string; titulo: string; detalhe: string; proprio: boolean };

/**
 * Registra no cliente os e-mails de uma entrega: marca o uso dos que ja existiam e cadastra os
 * novos. Nunca derruba o envio — a nota ja foi entregue quando isto roda.
 */
export async function registrarEmailsEntregaNfe(
  supabase: SupabaseClient,
  clienteId: number | null | undefined,
  emails: string[],
) {
  if (!clienteId || emails.length === 0) return;
  const { error } = await supabase.rpc("clientes_registrar_emails_nfe", {
    p_cliente_id: clienteId,
    p_emails: emails,
  });
  if (error) console.error("Nao foi possivel guardar os e-mails na lista do cliente:", error);
}

function dataCurta(valor: string | null) {
  if (!valor) return "";
  const data = new Date(valor);
  return Number.isNaN(data.getTime()) ? "" : data.toLocaleDateString("pt-BR");
}

/** O que a pessoa está digitando depois da última vírgula: filtra a lista enquanto ela escreve. */
function fragmentoAtual(valor: string) {
  const partes = valor.split(/[,;\n]/);
  return (partes[partes.length - 1] ?? "").trim().toLowerCase();
}

/**
 * Acrescenta o e-mail escolhido ao campo e termina com vírgula: o que vier depois é um
 * endereço novo, e a lista volta a mostrar todos (senão o e-mail recém-escolhido continuaria
 * filtrando a lista e a segunda escolha não sairia do lugar).
 */
function comEmail(valor: string, email: string) {
  const atuais = separarEmails(valor);
  const jaTem = atuais.some((item) => item.toLowerCase() === email.toLowerCase());
  // O último pedaço é o que está sendo digitado: sai, a menos que já esteja fechado por vírgula.
  const base = /[,;\n]\s*$/.test(valor) || valor.trim() === "" ? atuais : atuais.slice(0, -1);
  const lista = jaTem ? atuais : [...base, email];
  return lista.length ? `${lista.join(", ")}, ` : "";
}

export default function EmailsEntregaNfe({
  clienteId,
  ctx,
  valor,
  onChange,
  desabilitado = false,
  recarregarEm = 0,
  idCampo,
}: {
  clienteId: number | null | undefined;
  ctx: ContatoNfe | null | undefined;
  valor: string;
  onChange: (valor: string) => void;
  desabilitado?: boolean;
  /** Muda este número depois de enviar para a lista recarregar com o que foi cadastrado. */
  recarregarEm?: number;
  idCampo?: string;
}) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  // Guarda de quem e a lista carregada: trocando de cliente, a lista antiga nao aparece.
  const [carga, setCarga] = useState<{ clienteId: number | null; itens: ContatoSalvoNfe[] }>({ clienteId: null, itens: [] });
  const [aberta, setAberta] = useState(false);
  const [marcada, setMarcada] = useState(0);
  const campoRef = useRef<HTMLInputElement | null>(null);
  const caixaRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!clienteId) return;
    let ativo = true;
    void supabase.rpc("clientes_emails_nfe", { p_cliente_id: clienteId }).then(({ data, error }) => {
      if (!ativo) return;
      if (error) { console.error("Nao foi possivel ler os e-mails do cliente:", error); return; }
      setCarga({ clienteId, itens: (data ?? []) as ContatoSalvoNfe[] });
    });
    return () => { ativo = false; };
  }, [clienteId, recarregarEm, supabase]);

  const salvos = useMemo(
    () => (clienteId && carga.clienteId === clienteId ? carga.itens : []),
    [carga, clienteId],
  );

  // Fecha ao clicar fora, como qualquer lista suspensa da tela.
  useEffect(() => {
    if (!aberta) return;
    const fora = (evento: MouseEvent) => {
      if (!caixaRef.current?.contains(evento.target as Node)) setAberta(false);
    };
    document.addEventListener("mousedown", fora);
    return () => document.removeEventListener("mousedown", fora);
  }, [aberta]);

  const opcoes = useMemo<Opcao[]>(() => {
    const lista: Opcao[] = [];
    const vistos = new Set<string>();
    for (const contato of emailsDoCadastro(ctx)) {
      vistos.add(contato.email.toLowerCase());
      lista.push({
        email: contato.email,
        titulo: contato.email,
        detalhe: contato.proprio ? `cadastro · ${contato.rotulo} · é da própria empresa` : `cadastro · ${contato.rotulo}`,
        proprio: contato.proprio,
      });
    }
    for (const contato of salvos) {
      const email = (contato.email ?? "").trim();
      if (!email || vistos.has(email.toLowerCase())) continue;
      vistos.add(email.toLowerCase());
      const partes = [
        contato.nome?.trim(),
        contato.setor?.trim(),
        contato.principal ? "principal" : "",
        (contato.vezes_usado ?? 0) > 0 ? `${contato.vezes_usado}× usado` : "",
        contato.ultimo_uso_em ? `último ${dataCurta(contato.ultimo_uso_em)}` : "",
      ].filter(Boolean);
      lista.push({ email, titulo: email, detalhe: partes.join(" · "), proprio: false });
    }
    return lista;
  }, [ctx, salvos]);

  const fragmento = fragmentoAtual(valor);
  const filtradas = useMemo(
    () => (fragmento ? opcoes.filter((opcao) => opcao.email.toLowerCase().includes(fragmento) || opcao.detalhe.toLowerCase().includes(fragmento)) : opcoes),
    [fragmento, opcoes],
  );
  const escolhiveis = filtradas.filter((opcao) => !opcao.proprio);

  const escolher = useCallback((opcao: Opcao) => {
    if (opcao.proprio) return;
    onChange(comEmail(valor, opcao.email));
    setMarcada(0);
    setAberta(false);
    campoRef.current?.focus();
  }, [onChange, valor]);

  function aoTeclar(evento: React.KeyboardEvent<HTMLInputElement>) {
    if (evento.key === "Escape" && aberta) { evento.preventDefault(); setAberta(false); return; }
    if (evento.key === "ArrowDown" || evento.key === "ArrowUp") {
      if (escolhiveis.length === 0) return;
      evento.preventDefault();
      if (!aberta) { setAberta(true); setMarcada(0); return; }
      const passo = evento.key === "ArrowDown" ? 1 : -1;
      setMarcada((atual) => (atual + passo + escolhiveis.length) % escolhiveis.length);
      return;
    }
    if (evento.key !== "Enter") return;
    evento.preventDefault();
    // Enter com a lista fechada abre a lista; com a lista aberta, escolhe o item marcado.
    if (!aberta) { setMarcada(0); setAberta(true); return; }
    const opcao = escolhiveis[marcada];
    if (opcao) escolher(opcao);
  }

  return (
    <div className="relative" ref={caixaRef}>
      <div className="flex gap-2">
        <input
          id={idCampo}
          ref={campoRef}
          className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500 disabled:opacity-50"
          value={valor}
          disabled={desabilitado}
          onChange={(evento) => { onChange(evento.target.value); setMarcada(0); }}
          onKeyDown={aoTeclar}
          role="combobox"
          aria-expanded={aberta}
          aria-controls="lista-emails-cliente"
          aria-autocomplete="list"
          aria-label="E-mails para entrega da NF-e"
          placeholder="E-mails separados por vírgula · Enter abre a lista do cliente"
          autoComplete="off"
        />
        <button
          type="button"
          onClick={() => { setMarcada(0); setAberta((atual) => !atual); campoRef.current?.focus(); }}
          disabled={desabilitado}
          aria-label="Abrir a lista de e-mails do cliente"
          title="Lista de e-mails deste cliente (Enter no campo abre também)"
          className="rounded-md border border-zinc-700 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900 disabled:opacity-40"
        >
          Lista ▾
        </button>
      </div>
      {aberta ? (
        <div
          id="lista-emails-cliente"
          role="listbox"
          data-testid="lista-emails-cliente"
          className="absolute z-30 mt-1 max-h-72 w-full overflow-auto rounded-md border border-zinc-700 bg-zinc-950 shadow-xl"
        >
          {filtradas.length === 0 ? (
            <div className="px-3 py-2 text-xs text-zinc-400">
              {opcoes.length === 0
                ? "Nenhum e-mail na lista deste cliente ainda. Digite o e-mail e envie: ele entra aqui para a próxima nota."
                : "Nenhum e-mail com esse texto."}
            </div>
          ) : filtradas.map((opcao) => {
            const indice = escolhiveis.indexOf(opcao);
            const emFoco = indice >= 0 && indice === marcada;
            return opcao.proprio ? (
              <div key={opcao.email} className="border-b border-zinc-900 px-3 py-2 text-xs text-rose-200 last:border-b-0" title="Endereço do domínio da própria empresa emitente gravado no cadastro do cliente; corrija no cadastro fiscal.">
                <div className="font-medium">{opcao.titulo}</div>
                <div className="text-rose-300/80">{opcao.detalhe}</div>
              </div>
            ) : (
              <button
                key={opcao.email}
                type="button"
                role="option"
                aria-selected={emFoco}
                onMouseEnter={() => setMarcada(indice)}
                onClick={() => escolher(opcao)}
                className={`block w-full border-b border-zinc-900 px-3 py-2 text-left last:border-b-0 ${emFoco ? "bg-sky-950/50" : "hover:bg-zinc-900"}`}
              >
                <div className="text-sm text-zinc-100">{opcao.titulo}</div>
                {opcao.detalhe ? <div className="text-xs text-zinc-400">{opcao.detalhe}</div> : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
