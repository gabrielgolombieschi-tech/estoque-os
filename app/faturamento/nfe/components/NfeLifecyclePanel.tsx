"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

type Evento = { id: string; tipo: string; status: string; justificativa: string | null; protocolo: string | null; destinatarios: string[] | null; sequencia: number | null; resposta?: Record<string, unknown> | null; created_at: string };
type Contexto = {
  documento: { serie: string | null; numero: string | null } | null;
  emissao: { status: string; ambiente: string; xml_path: string | null; danfe_path: string | null; autorizado_em: string | null };
  cliente: { nome: string; email: string | null; email_financeiro: string | null } | null;
  empresa_fiscal: { email_fisco: string | null; certificado_validade_em: string | null; dias_certificado: number | null } | null;
  cancelamento: { limite_em: string | null; segundos_restantes: number; pode_cancelar: boolean; deve_estornar: boolean };
  cfops_estorno_propostos: string[];
  eventos: Evento[];
};

const EMAIL = /^\S+@\S+\.\S+$/;

function dominio(email: string | null | undefined) {
  const v = (email ?? "").trim().toLowerCase();
  const at = v.lastIndexOf("@");
  return at > 0 ? v.slice(at + 1) : "";
}

// E-mails do cadastro do cliente, marcando os que estao no dominio da propria empresa
// emitente: na PBG S/A o "e-mail financeiro" veio gravado como CONTATO@SEGAU.COM.BR e a
// tela oferecia a Segau como destinataria da nota da Portobello.
function emailsDoCadastro(ctx: Contexto | null) {
  const proprioDominio = dominio(ctx?.empresa_fiscal?.email_fisco);
  const lista: Array<{ rotulo: string; email: string; proprio: boolean }> = [];
  for (const [rotulo, valor] of [["financeiro", ctx?.cliente?.email_financeiro], ["principal", ctx?.cliente?.email]] as const) {
    const email = (valor ?? "").trim().toLowerCase();
    if (!EMAIL.test(email) || lista.some((c) => c.email === email)) continue;
    lista.push({ rotulo, email, proprio: Boolean(proprioDominio) && dominio(email) === proprioDominio });
  }
  return lista;
}

function emailPadraoCliente(ctx: Contexto | null) {
  return emailsDoCadastro(ctx).find((c) => !c.proprio)?.email ?? "";
}

const input = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const button = "rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40";

function message(error: unknown) {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) return String(error.message);
  return "Erro inesperado.";
}

async function functionMessage(error: unknown) {
  if (error && typeof error === "object" && "context" in error) {
    const response = (error as { context?: unknown }).context;
    if (response instanceof Response) {
      try {
        const body = await response.clone().json() as {
          error?: string;
          erro?: string;
          resposta?: { mensagem?: string; mensagem_sefaz?: string };
        };
        const detalhe = body.error ?? body.erro ?? body.resposta?.mensagem ?? body.resposta?.mensagem_sefaz;
        if (detalhe) return detalhe;
      } catch {
        // Usa a mensagem padrao quando a Function nao devolve JSON legivel.
      }
    }
  }
  return message(error);
}

function eventSummary(evento: Evento) {
  const resposta = evento.resposta ?? {};
  const mensagemResposta = resposta.mensagem ?? resposta.mensagem_sefaz;
  return evento.destinatarios?.join(", ")
    || (typeof mensagemResposta === "string" ? mensagemResposta : null)
    || evento.justificativa
    || evento.protocolo
    || "—";
}

function countdown(seconds: number) {
  const safe = Math.max(0, Math.floor(seconds));
  const h = Math.floor(safe / 3600);
  const m = Math.floor((safe % 3600) / 60);
  const s = safe % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

function binaryFromArrayBuffer(buffer: ArrayBuffer) {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(offset + chunkSize, bytes.length)));
  }
  return binary;
}

function isoDate(date: Date) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`;
}

export default function NfeLifecyclePanel({ documentoId }: { documentoId: string }) {
  const scope = useTenantEmpresa();
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [ctx, setCtx] = useState<Contexto | null>(null);
  const [remaining, setRemaining] = useState(0);
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [justificativa, setJustificativa] = useState("");
  const [correcao, setCorrecao] = useState("");
  const [emails, setEmails] = useState("");
  const [senhaPfx, setSenhaPfx] = useState("");
  const [pfx, setPfx] = useState<File | null>(null);
  const [emailFisco, setEmailFisco] = useState("");

  const reload = useCallback(async () => {
    const { data, error } = await supabase.schema("f").rpc("fn_nfe_ciclo_contexto", { p_documento_fiscal_id: documentoId });
    if (error) throw error;
    const next = data as Contexto;
    setCtx(next);
    setRemaining(Number(next.cancelamento?.segundos_restantes ?? 0));
    if (!emails) setEmails(emailPadraoCliente(next));
  }, [documentoId, emails, supabase]);

  useEffect(() => {
    if (!scope.tenantId || !scope.empresaId) return;
    void reload().catch((error) => setFeedback(message(error)));
  }, [reload, scope.empresaId, scope.tenantId]);

  useEffect(() => {
    if (remaining <= 0) return;
    const timer = window.setInterval(() => setRemaining((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [remaining]);

  useEffect(() => {
    setEmailFisco(ctx?.empresa_fiscal?.email_fisco ?? "");
  }, [ctx?.empresa_fiscal?.email_fisco]);

  async function invoke(body: Record<string, unknown>) {
    setBusy(true); setFeedback("");
    try {
      const { data, error } = await supabase.functions.invoke("nfe-ciclo", { body: { ...body, documento_fiscal_id: documentoId } });
      if (error) throw error;
      if (data?.error) throw new Error(String(data.error));
      setFeedback("Operação concluída e registrada no histórico.");
      await reload();
      return data;
    } catch (error) {
      setFeedback(await functionMessage(error));
      return null;
    } finally { setBusy(false); }
  }

  async function abrirArquivo(arquivo: "XML" | "DANFE", imprimir = false) {
    const novaAba = imprimir ? window.open("about:blank", "_blank") : null;
    if (novaAba) novaAba.opener = null;
    const data = await invoke({ acao: "ARQUIVO", arquivo });
    if (data?.url) {
      if (imprimir) {
        if (!novaAba) {
          setFeedback("O navegador bloqueou o DANFE. Libere pop-ups para este sistema.");
          return;
        }
        novaAba.location.replace(String(data.url));
      } else {
        window.location.assign(String(data.url));
      }
      if (imprimir) setFeedback("DANFE aberto em uma nova aba para usar a impressão do navegador.");
    } else {
      novaAba?.close();
    }
  }

  async function cancelarNaSefaz() {
    if (!ctx || !["HOMOLOGACAO", "PRODUCAO"].includes(ctx.emissao.ambiente)) return;
    const motivo = justificativa.trim();
    const mensagem = ctx.emissao.ambiente === "PRODUCAO"
      ? `CANCELAR NF-e REAL na SEFAZ?\n\nNF-e ${ctx.documento?.serie ?? ""}/${ctx.documento?.numero ?? ""} · ${ctx.cliente?.nome ?? ""}\nJustificativa: ${motivo}\n\nEfeitos: a nota fica cancelada na SEFAZ (número preservado), o título a receber é cancelado e o saldo da OV volta a ficar disponível. Esta ação não pode ser desfeita.`
      : `Cancelar esta NF-e de HOMOLOGAÇÃO na SEFAZ?\n\nJustificativa: ${motivo}\n\nA solicitação será cancelada e o saldo voltará a ficar disponível.`;
    if (!window.confirm(mensagem)) return;
    await invoke({ acao: "CANCELAR", justificativa: motivo });
  }

  async function testarCancelamentoForaPrazo() {
    if (!ctx || ctx.emissao.ambiente !== "HOMOLOGACAO") return;
    if (!window.confirm(
      "Executar agora o teste real de cancelamento fora do prazo na Focus/SEFAZ?\n\nA NF-e deve permanecer autorizada e a rejeição será gravada no histórico. Se a SEFAZ aceitar inesperadamente, o estado será conciliado como cancelado.",
    )) return;
    await invoke({
      acao: "TESTAR_CANCELAMENTO_FORA_PRAZO",
      justificativa: "Teste de cancelamento fora do prazo legal.",
    });
  }

  async function enviarAoCliente() {
    if (!ctx || ctx.emissao.ambiente !== "PRODUCAO" || ctx.emissao.status !== "AUTORIZADA") return;
    const destinatarios = emails.split(/[,;\n]/).map((value) => value.trim()).filter(Boolean);
    if (!window.confirm(
      `Enviar XML e DANFE da NF-e ${ctx.emissao.ambiente} para:\n\n${destinatarios.join("\n")}\n\nConfirme somente após revisar os dois arquivos.`,
    )) return;
    await invoke({ acao: "EMAIL", emails: destinatarios });
  }

  async function lerCertificado() {
    if (!pfx || !scope.tenantId || !scope.empresaId) return;
    setBusy(true); setFeedback("");
    try {
      const forge = await import("node-forge");
      let validade: Date | null = null;
      try {
        const asn1 = forge.asn1.fromDer(binaryFromArrayBuffer(await pfx.arrayBuffer()));
        const p12 = forge.pkcs12.pkcs12FromAsn1(asn1, false, senhaPfx);
        const bags = p12.getBags({ bagType: forge.pki.oids.certBag });
        const certificados = bags[forge.pki.oids.certBag] ?? [];
        const certificadosDaChave = certificados.filter((bag) => (bag.attributes?.localKeyId?.length ?? 0) > 0);
        const datas = (certificadosDaChave.length ? certificadosDaChave : certificados)
          .map((bag) => bag.cert?.validity.notAfter ?? null)
          .filter((date): date is Date => date instanceof Date && !Number.isNaN(date.getTime()));
        validade = datas.sort((a, b) => a.getTime() - b.getTime())[0] ?? null;
      } catch {
        throw new Error("Não foi possível abrir o certificado. Confira o arquivo e a senha.");
      }
      if (!validade) throw new Error("O arquivo não contém certificado X.509 com validade legível.");

      const dataValidade = isoDate(validade);
      const { error } = await supabase.schema("f").rpc("fn_empresa_certificado_validade_atualizar", {
        p_empresa_id: scope.empresaId,
        p_validade: dataValidade,
      });
      if (error) throw error;

      setFeedback(`Validade do certificado atualizada para ${new Date(`${dataValidade}T00:00:00`).toLocaleDateString("pt-BR")}. O arquivo e a senha permaneceram somente neste navegador.`);
      setSenhaPfx(""); setPfx(null); await reload();
    } catch (error) { setFeedback(message(error)); } finally { setBusy(false); }
  }

  async function salvarEmailFisco() {
    if (!scope.empresaId) return;
    setBusy(true); setFeedback("");
    try {
      const { data, error } = await supabase.schema("f").rpc("fn_empresa_email_fisco_atualizar", {
        p_empresa_id: scope.empresaId,
        p_email: emailFisco.trim(),
      });
      if (error) throw error;
      setFeedback(`E-mail fiscal atualizado para ${String(data)}.`);
      await reload();
    } catch (error) { setFeedback(message(error)); } finally { setBusy(false); }
  }

  if (!ctx) {
    return <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-400">
      {feedback ? <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-3 text-red-200">Não foi possível carregar o ciclo da NF-e: {feedback}</div> : "Carregando ciclo da NF-e..."}
    </section>;
  }
  const podeCancelar = ctx.cancelamento.pode_cancelar && remaining > 0;
  const vencimento = ctx.empresa_fiscal?.dias_certificado;
  const homologacao = ctx.emissao.ambiente === "HOMOLOGACAO";
  const producao = ctx.emissao.ambiente === "PRODUCAO";
  const autorizada = ctx.emissao.status === "AUTORIZADA";
  const cancelamentoForaPrazoTestado = ctx.eventos.some((evento) =>
    evento.resposta?.cenario_homologacao === "CANCELAMENTO_FORA_PRAZO"
  );

  return <section className="rounded-xl border border-sky-900/60 bg-sky-950/10 p-4 text-zinc-100">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h2 className="font-semibold">Ciclo de vida da NF-e</h2><p className="text-xs text-zinc-400">Ambiente {ctx.emissao.ambiente} · eventos imutáveis</p></div>
      <span className="rounded border border-zinc-700 px-2 py-1 text-xs">{ctx.emissao.status}</span>
    </div>

    {feedback ? <div className="mt-3 rounded border border-sky-800/60 bg-sky-950/30 p-3 text-sm text-sky-200">{feedback}</div> : null}
    {!ctx.empresa_fiscal?.email_fisco ? <div className="mt-3 rounded border border-amber-700/60 bg-amber-950/20 p-3 text-sm text-amber-200">E-mail do fisco não cadastrado. A nota continua disponível, mas este contato precisa ser preenchido no cadastro fiscal da empresa.</div> : null}
    {vencimento === null || vencimento === undefined ? <div className="mt-3 rounded border border-amber-700/60 bg-amber-950/20 p-3 text-sm text-amber-200">Validade do certificado desconhecida.</div> : vencimento <= 30 ? <div className="mt-3 rounded border border-rose-700/60 bg-rose-950/20 p-3 text-sm text-rose-200">Certificado {vencimento < 0 ? `vencido há ${Math.abs(vencimento)} dia(s)` : `vence em ${vencimento} dia(s)`}.</div> : null}

    <div className="mt-4 grid gap-4 lg:grid-cols-2">
      <div className="space-y-3 rounded border border-zinc-800 p-3">
        <h3 className="text-sm font-medium">Cancelar ou estornar</h3>
        {podeCancelar ? <>{producao ? <div className="rounded border border-rose-800/70 bg-rose-950/20 p-3 text-xs text-rose-100"><strong>NF-e real.</strong> Cancelar na SEFAZ cancela também o título a receber e devolve o saldo da OV. Só é possível dentro de 24 horas da autorização e enquanto não houver recebimento.</div> : null}<div className="text-sm text-amber-200">Tempo restante: <strong className="font-mono">{countdown(remaining)}</strong></div><textarea className={`${input} min-h-20 w-full`} value={justificativa} onChange={(e)=>setJustificativa(e.target.value)} placeholder="Justificativa (15 a 255 caracteres)" maxLength={255}/><button className={button} disabled={busy || justificativa.trim().length < 15 || justificativa.trim().length > 255} onClick={()=>void cancelarNaSefaz()}>{producao ? "Cancelar NF-e real na SEFAZ" : "Cancelar homologação na SEFAZ"}</button></> : null}
        {homologacao && !podeCancelar && autorizada && ctx.cancelamento.deve_estornar ? <><p className="text-sm text-rose-200">A janela de 24 horas terminou. O fluxo normal exige NF-e de estorno.</p><p className="text-xs text-zinc-400">CFOP proposto a partir da original: {ctx.cfops_estorno_propostos.join(", ") || "exige conferência manual"}.</p>{cancelamentoForaPrazoTestado ? <p className="text-xs text-emerald-300">Cenário de cancelamento fora do prazo já executado e registrado no histórico.</p> : <button className={button} disabled={busy} onClick={()=>void testarCancelamentoForaPrazo()}>Testar rejeição fora do prazo (homologação)</button>}<Link className={button} href={`/faturamento/operacoes?aba=ESTORNO&documento=${documentoId}`}>Criar NF-e de estorno</Link></> : null}
        {producao && autorizada && !podeCancelar ? <><p className="text-sm text-rose-200">A janela de 24 horas terminou. O fluxo normal exige NF-e de estorno.</p><p className="text-xs text-zinc-400">CFOP proposto a partir da original: {ctx.cfops_estorno_propostos.join(", ") || "exige conferência manual"}.</p><Link className={button} href={`/faturamento/operacoes?aba=ESTORNO&documento=${documentoId}`}>Criar NF-e de estorno</Link></> : null}
        {ctx.emissao.status === "CANCELADA" ? <p className="text-sm text-emerald-300">NF-e cancelada; o protocolo está preservado no histórico abaixo.</p> : null}
      </div>

      <div className="space-y-3 rounded border border-zinc-800 p-3">
        <h3 className="text-sm font-medium">Entregar ao cliente</h3>
        <div className="flex flex-wrap gap-2"><button className={button} disabled={busy || !ctx.emissao.danfe_path} onClick={()=>void abrirArquivo("DANFE")}>Baixar DANFE</button><button className={button} disabled={busy || !ctx.emissao.danfe_path} onClick={()=>void abrirArquivo("DANFE", true)}>Imprimir DANFE</button><button className={button} disabled={busy || !ctx.emissao.xml_path} onClick={()=>void abrirArquivo("XML")}>Baixar XML</button></div>
        <input className={`${input} w-full`} value={emails} onChange={(e)=>setEmails(e.target.value)} placeholder="E-mails separados por vírgula"/>
        <div className="flex flex-wrap items-center gap-2 text-xs text-zinc-400">
          <span>Cadastro do cliente:</span>
          {emailsDoCadastro(ctx).map((c) => c.proprio ? (
            <span key={c.rotulo} className="rounded border border-rose-900/60 bg-rose-950/30 px-2 py-0.5 text-rose-200" title="Endereço do domínio da própria empresa emitente gravado no cadastro do cliente; corrija no cadastro.">{c.rotulo}: {c.email} · é da própria empresa</span>
          ) : (
            <button key={c.rotulo} type="button" className="rounded border border-zinc-700 px-2 py-0.5 hover:bg-zinc-800" onClick={() => setEmails(c.email)}>{c.rotulo}: {c.email}</button>
          ))}
          {emailsDoCadastro(ctx).length === 0 ? <span>nenhum e-mail cadastrado</span> : null}
        </div>
        <button className={button} disabled={busy || !producao || !autorizada || !emails.trim() || !ctx.emissao.xml_path || !ctx.emissao.danfe_path} onClick={()=>void enviarAoCliente()}>Revisado: enviar XML + DANFE</button>
        {homologacao ? <p className="text-xs text-amber-300">Documentos de homologação podem ser baixados para conferência, mas nunca são enviados ao cliente por esta tela.</p> : null}
      </div>

      <div className="space-y-3 rounded border border-zinc-800 p-3 lg:col-span-2">
        <h3 className="text-sm font-medium">Carta de correção eletrônica</h3>
        <div className="grid gap-2 text-xs md:grid-cols-2"><div className="rounded border border-emerald-900/60 bg-emerald-950/20 p-2 text-emerald-200"><strong>Pode corrigir:</strong> dados acessórios permitidos, como peso, volume e informação complementar, sem alterar a tributação.</div><div className="rounded border border-rose-900/60 bg-rose-950/20 p-2 text-rose-200"><strong>Não corrige:</strong> valor, quantidade, preço, base/alíquota/imposto, destinatário/remetente ou data de emissão/saída. Esses casos exigem estorno.</div></div>
        <textarea className={`${input} min-h-24 w-full`} value={correcao} onChange={(e)=>setCorrecao(e.target.value)} placeholder="Correção completa (15 a 1.000 caracteres). A última CC-e substitui as anteriores."/>
        <button className={button} disabled={busy || !homologacao || !autorizada || correcao.trim().length < 15} onClick={()=>void invoke({ acao:"CARTA_CORRECAO", correcao })}>Emitir carta de correção</button>
        {producao ? <p className="text-xs text-amber-300">CC-e de produção permanece bloqueada nesta tela até o fluxo real também tratar seus efeitos e auditoria de ponta a ponta.</p> : null}
      </div>

      <div className="space-y-3 rounded border border-zinc-800 p-3 lg:col-span-2">
        <h3 className="text-sm font-medium">Contato fiscal da empresa</h3>
        <p className="text-xs text-zinc-400">Endereço interno para avisos fiscais. Não é o e-mail do cliente nem configura o remetente da NF-e.</p>
        <div className="flex flex-wrap gap-2">
          <input className={`${input} min-w-72 flex-1`} type="email" value={emailFisco} onChange={(event) => setEmailFisco(event.target.value)} placeholder="financeiro@empresa.com.br" />
          <button className={button} disabled={busy || !/^\S+@\S+\.\S+$/.test(emailFisco.trim()) || emailFisco.trim().toLowerCase() === (ctx.empresa_fiscal?.email_fisco ?? "").toLowerCase()} onClick={()=>void salvarEmailFisco()}>Salvar e-mail fiscal</button>
        </div>
      </div>

      <div className="space-y-3 rounded border border-zinc-800 p-3 lg:col-span-2">
        <h3 className="text-sm font-medium">Validade do certificado da empresa</h3>
        <p className="text-xs text-zinc-400">O navegador lê somente a validade do .pfx/.p12. Arquivo e senha permanecem locais e não são armazenados.</p>
        <div className="flex flex-wrap gap-2"><input className={input} type="file" accept=".pfx,.p12,application/x-pkcs12" onChange={(e)=>setPfx(e.target.files?.[0] ?? null)}/><input className={input} type="password" value={senhaPfx} onChange={(e)=>setSenhaPfx(e.target.value)} placeholder="Senha do certificado"/><button className={button} disabled={busy || !pfx} onClick={()=>void lerCertificado()}>Ler validade</button></div>
      </div>
    </div>

    <div className="mt-4 rounded border border-zinc-800">
      <div className="border-b border-zinc-800 px-3 py-2 text-sm font-medium">Histórico</div>
      <div className="divide-y divide-zinc-800">{ctx.eventos.length ? ctx.eventos.map((evento)=><div key={evento.id} className="grid gap-1 px-3 py-2 text-xs md:grid-cols-[150px_120px_1fr_160px]"><span>{evento.tipo}{evento.sequencia ? ` #${evento.sequencia}`:""}</span><span>{evento.status}</span><span className="text-zinc-400">{eventSummary(evento)}</span><span className="text-right text-zinc-500">{new Date(evento.created_at).toLocaleString("pt-BR")}</span></div>) : <div className="px-3 py-4 text-sm text-zinc-500">Nenhum evento registrado.</div>}</div>
    </div>
  </section>;
}
