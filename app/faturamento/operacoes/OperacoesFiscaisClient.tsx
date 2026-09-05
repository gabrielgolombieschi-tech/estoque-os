"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

type Aba = "DEVOLUCAO" | "VENDA_ORDEM" | "REMESSA" | "ESTORNO";
type ItemXml = { nitem: number; codigo: string; descricao: string; quantidade_original: number; valor_unitario: number; cfop_original: string; cfop_proposto: string | null };
type Operacao = { id: string; tipo: string; finalidade: string | null; status: string; cfop_confirmado: string | null; cfop_segunda_nota: string | null; chave_primeira_nota: string | null; chave_segunda_nota: string | null; valor_total: number; created_at: string };
type Remessa = { id: string; operacao_remessa_id: string; finalidade: string; chave_remessa: string; destinatario_nome: string; remessa_em: string; dias_decorridos: number; prazo_dias: number | null; prazo_excedido: boolean };

const field = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const button = "rounded border border-zinc-600 bg-zinc-900 px-4 py-2 text-sm hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40";

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) return String(error.message);
  return String(error ?? "Erro inesperado.");
}

export default function OperacoesFiscaisClient() {
  const scope = useTenantEmpresa();
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [aba, setAba] = useState<Aba>("DEVOLUCAO");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [operacoes, setOperacoes] = useState<Operacao[]>([]);
  const [remessas, setRemessas] = useState<Remessa[]>([]);

  const [nfEntradaId, setNfEntradaId] = useState("");
  const [itensXml, setItensXml] = useState<ItemXml[]>([]);
  const [selecionados, setSelecionados] = useState<Record<number, { quantidade: string; cfop: string }>>({});
  const [ovId, setOvId] = useState("");
  const [entrega, setEntrega] = useState({ cnpj: "", nome: "", logradouro: "", numero: "", bairro: "", municipio: "", uf: "SC", cep: "", codigo_municipio: "" });
  const [finalidade, setFinalidade] = useState("INDUSTRIALIZACAO");
  const [cfopRemessa, setCfopRemessa] = useState("5901");
  const [destinatario, setDestinatario] = useState({ documento: "", nome: "" });
  const [itensRemessa, setItensRemessa] = useState('[{"descricao":"ITEM DA REMESSA","quantidade":1,"unidade":"UN","valor_unitario":0}]');
  const [documentoOriginal, setDocumentoOriginal] = useState("");
  const [cfopEstorno, setCfopEstorno] = useState("");
  const [justificativa, setJustificativa] = useState("");
  const [chaves, setChaves] = useState<Record<string, string>>({});
  const [prazo, setPrazo] = useState("");

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("aba") === "ESTORNO") setAba("ESTORNO");
    const documento = params.get("documento");
    if (documento) setDocumentoOriginal(documento);
  }, []);

  const reload = useCallback(async () => {
    if (!scope.tenantId || !scope.empresaId) return;
    const [ops, rem] = await Promise.all([
      supabase.schema("f").from("operacao_fiscal").select("id,tipo,finalidade,status,cfop_confirmado,cfop_segunda_nota,chave_primeira_nota,chave_segunda_nota,valor_total,created_at").is("deleted_at", null).order("created_at", { ascending: false }).limit(50),
      supabase.schema("f").from("v_remessas_abertas").select("id,operacao_remessa_id,finalidade,chave_remessa,destinatario_nome,remessa_em,dias_decorridos,prazo_dias,prazo_excedido").order("remessa_em"),
    ]);
    if (ops.error) throw ops.error;
    if (rem.error) throw rem.error;
    setOperacoes((ops.data ?? []) as Operacao[]);
    setRemessas((rem.data ?? []) as Remessa[]);
  }, [scope.empresaId, scope.tenantId, supabase]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void reload().catch((e) => setMessage(errorMessage(e)));
    }, 0);
    return () => window.clearTimeout(timer);
  }, [reload]);

  async function run(action: () => Promise<void>) {
    setBusy(true); setMessage("");
    try { await action(); await reload(); } catch (e) { setMessage(errorMessage(e)); } finally { setBusy(false); }
  }

  async function carregarEntrada() {
    await run(async () => {
      const { data, error } = await supabase.schema("f").rpc("fn_devolucao_compra_preparar", { p_nf_entrada_id: Number(nfEntradaId) });
      if (error) throw error;
      const rows = ((data as { itens?: ItemXml[] })?.itens ?? []);
      setItensXml(rows);
      setSelecionados(Object.fromEntries(rows.map((item) => [item.nitem, { quantidade: "0", cfop: item.cfop_proposto ?? "" }])));
      setMessage(`XML validado: ${rows.length} item(ns). Selecione quantidades e confirme o CFOP de cada linha.`);
    });
  }

  async function criarDevolucao() {
    await run(async () => {
      const itens = itensXml.flatMap((item) => {
        const value = selecionados[item.nitem];
        return Number(value?.quantidade) > 0 ? [{ nitem: item.nitem, quantidade: Number(value.quantidade), cfop_confirmado: value.cfop }] : [];
      });
      const { data, error } = await supabase.schema("f").rpc("fn_devolucao_compra_criar", { p_nf_entrada_id: Number(nfEntradaId), p_itens: itens });
      if (error) throw error;
      setMessage(`Devolução ${data} criada e validada contra o XML original.`);
    });
  }

  async function criarVendaOrdem() {
    await run(async () => {
      const { data, error } = await supabase.schema("f").rpc("fn_venda_ordem_criar", { p_ov_id: Number(ovId), p_entrega: entrega });
      if (error) throw error;
      setMessage(`Venda à ordem ${data} criada. A NF-e 6923 continuará bloqueada até a chave da 6119.`);
    });
  }

  async function criarRemessa() {
    await run(async () => {
      let itens: unknown;
      try { itens = JSON.parse(itensRemessa); } catch { throw new Error("Itens da remessa: JSON inválido."); }
      const { data, error } = await supabase.schema("f").rpc("fn_remessa_criar", { p_finalidade: finalidade, p_cfop_confirmado: cfopRemessa, p_destinatario: destinatario, p_itens: itens, p_justificativa: justificativa || null });
      if (error) throw error;
      setMessage(`Remessa ${data} pronta para homologação.`);
    });
  }

  async function criarEstorno() {
    await run(async () => {
      const { data, error } = await supabase.schema("f").rpc("fn_estorno_criar", { p_documento_original_id: documentoOriginal, p_cfop_confirmado: cfopEstorno, p_justificativa: justificativa });
      if (error) throw error;
      setMessage(`Estorno ${data} criado com valores espelhados e finalidade 3.`);
    });
  }

  async function validar(op: Operacao) {
    await run(async () => {
      const etapa = op.tipo === "VENDA_ORDEM" && op.status === "AGUARDANDO_SEGUNDA" ? 2 : 1;
      const { error } = await supabase.schema("f").rpc("fn_operacao_validar_homologacao", { p_operacao_id: op.id, p_etapa: etapa });
      if (error) throw error;
      setMessage(`Operação ${op.id} passou no portão de homologação (etapa ${etapa}).`);
    });
  }

  async function registrarChave(op: Operacao) {
    await run(async () => {
      const etapa = op.tipo === "VENDA_ORDEM" && op.status === "AGUARDANDO_SEGUNDA" ? 2 : 1;
      const { error } = await supabase.schema("f").rpc("fn_operacao_registrar_chave", { p_operacao_id: op.id, p_etapa: etapa, p_chave: chaves[op.id] ?? "" });
      if (error) throw error;
      setMessage(`Chave autorizada registrada na etapa ${etapa}.`);
    });
  }

  async function criarRetorno(remessa: Remessa) {
    const cfop = remessa.finalidade === "INDUSTRIALIZACAO" ? "5902" : "5916";
    await run(async () => {
      const { data, error } = await supabase.schema("f").rpc("fn_retorno_criar", { p_remessa_controle_id: remessa.id, p_cfop_confirmado: cfop });
      if (error) throw error;
      setMessage(`Retorno ${data} criado e ligado à chave ${remessa.chave_remessa}.`);
    });
  }

  async function salvarPrazo() {
    await run(async () => {
      const { error } = await supabase.schema("f").rpc("fn_remessa_prazo_configurar", { p_finalidade: finalidade, p_prazo_dias: prazo ? Number(prazo) : null });
      if (error) throw error;
      setMessage(prazo ? `Alerta de ${finalidade} configurado para ${prazo} dias.` : `Prazo de ${finalidade} mantido vazio; alerta desligado.`);
    });
  }

  return <main className="mx-auto max-w-[1500px] space-y-6 p-6 text-zinc-100">
    <header className="flex flex-wrap items-start justify-between gap-4">
      <div><div className="text-xs text-zinc-500">Faturamento › Operações fiscais</div><h1 className="text-2xl font-semibold">Operações que não nascem do botão Faturar</h1><p className="text-sm text-zinc-400">Somente homologação. Nenhum perfil é habilitado para produção nesta tela.</p></div>
      <Link href="/faturamento/nfe" className={button}>Voltar para NF-e</Link>
    </header>
    {message && <div className="rounded border border-sky-700/50 bg-sky-950/30 p-3 text-sm text-sky-200">{message}</div>}
    <div className="flex flex-wrap gap-2">{(["DEVOLUCAO","VENDA_ORDEM","REMESSA","ESTORNO"] as Aba[]).map((value)=><button key={value} onClick={()=>setAba(value)} className={`${button} ${aba===value?"border-sky-500 bg-sky-950/50":""}`}>{value.replaceAll("_"," ")}</button>)}</div>

    <section className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-5">
      {aba === "DEVOLUCAO" && <div className="space-y-4"><h2 className="font-semibold">Devolução de compra a partir da entrada</h2><div className="flex gap-2"><input className={field} value={nfEntradaId} onChange={e=>setNfEntradaId(e.target.value)} placeholder="ID da nota de entrada"/><button disabled={busy||!nfEntradaId} className={button} onClick={carregarEntrada}>Ler e validar XML</button></div>{itensXml.length>0&&<><div className="overflow-auto"><table className="w-full text-sm"><thead className="text-left text-zinc-500"><tr><th>Item</th><th>Descrição</th><th>Qtd. original</th><th>Qtd. devolver</th><th>CFOP entrada</th><th>CFOP confirmado</th></tr></thead><tbody>{itensXml.map(item=><tr key={item.nitem} className="border-t border-zinc-800"><td className="py-2">{item.nitem}</td><td>{item.descricao}</td><td>{item.quantidade_original}</td><td><input className={`${field} w-28`} type="number" min="0" max={item.quantidade_original} step="0.0001" value={selecionados[item.nitem]?.quantidade??"0"} onChange={e=>setSelecionados(s=>({...s,[item.nitem]:{...s[item.nitem],quantidade:e.target.value}}))}/></td><td>{item.cfop_original}</td><td><input className={`${field} w-28`} value={selecionados[item.nitem]?.cfop??""} onChange={e=>setSelecionados(s=>({...s,[item.nitem]:{...s[item.nitem],cfop:e.target.value}}))}/></td></tr>)}</tbody></table></div><button disabled={busy} className={button} onClick={criarDevolucao}>Criar devolução parcial</button></>}</div>}
      {aba === "VENDA_ORDEM" && <div className="space-y-3"><h2 className="font-semibold">Venda à ordem — 6119 seguida de 6923</h2><input className={field} value={ovId} onChange={e=>setOvId(e.target.value)} placeholder="ID da OV"/><div className="grid gap-2 md:grid-cols-3">{Object.entries(entrega).map(([key,value])=><input key={key} className={field} value={value} onChange={e=>setEntrega(s=>({...s,[key]:e.target.value}))} placeholder={`Entrega: ${key}`}/>)}</div><button disabled={busy||!ovId} className={button} onClick={criarVendaOrdem}>Criar as duas etapas</button></div>}
      {aba === "REMESSA" && <div className="space-y-3"><h2 className="font-semibold">Remessa com controle de retorno</h2><div className="flex flex-wrap gap-2"><select className={field} value={finalidade} onChange={e=>setFinalidade(e.target.value)}><option>INDUSTRIALIZACAO</option><option>CONSERTO</option><option>SIMPLES</option><option>CONTA_ORDEM</option></select><input className={field} value={cfopRemessa} onChange={e=>setCfopRemessa(e.target.value)} placeholder="CFOP confirmado"/><input className={field} value={destinatario.documento} onChange={e=>setDestinatario(s=>({...s,documento:e.target.value}))} placeholder="CPF/CNPJ destinatário"/><input className={field} value={destinatario.nome} onChange={e=>setDestinatario(s=>({...s,nome:e.target.value}))} placeholder="Nome destinatário"/></div><textarea className={`${field} min-h-24 w-full font-mono`} value={itensRemessa} onChange={e=>setItensRemessa(e.target.value)}/><button disabled={busy} className={button} onClick={criarRemessa}>Criar remessa</button><div className="flex gap-2 border-t border-zinc-800 pt-3"><input className={field} type="number" min="1" value={prazo} onChange={e=>setPrazo(e.target.value)} placeholder="Prazo em dias (vazio = desligado)"/><button className={button} onClick={salvarPrazo}>Salvar prazo da finalidade</button></div></div>}
      {aba === "ESTORNO" && <div className="space-y-3"><h2 className="font-semibold">Estorno espelhado da NF-e original</h2><input className={`${field} w-full`} value={documentoOriginal} onChange={e=>setDocumentoOriginal(e.target.value)} placeholder="UUID do documento fiscal original"/><input className={field} value={cfopEstorno} onChange={e=>setCfopEstorno(e.target.value)} placeholder="CFOP confirmado: 1102, 1201, 1202, 1915 ou 2202"/><textarea className={`${field} min-h-20 w-full`} value={justificativa} onChange={e=>setJustificativa(e.target.value)} placeholder="Justificativa ao fisco"/><button disabled={busy} className={button} onClick={criarEstorno}>Criar estorno com finalidade 3</button></div>}
    </section>

    <section className="rounded-xl border border-zinc-800 p-5"><h2 className="mb-3 font-semibold">Remessas em aberto</h2><div className="overflow-auto"><table className="w-full text-sm"><thead className="text-left text-zinc-500"><tr><th>Chave</th><th>Finalidade</th><th>Destinatário</th><th>Data</th><th>Dias</th><th>Prazo</th><th></th></tr></thead><tbody>{remessas.map(r=><tr key={r.id} className={r.prazo_excedido?"border-t border-rose-800 bg-rose-950/20":"border-t border-zinc-800"}><td className="py-2 font-mono">{r.chave_remessa.slice(0,8)}…{r.chave_remessa.slice(-6)}</td><td>{r.finalidade}</td><td>{r.destinatario_nome}</td><td>{new Date(r.remessa_em+"T00:00:00").toLocaleDateString("pt-BR")}</td><td>{r.dias_decorridos}</td><td>{r.prazo_dias??"não configurado"}</td><td><button className={button} disabled={!["INDUSTRIALIZACAO","CONSERTO"].includes(r.finalidade)} onClick={()=>criarRetorno(r)}>Criar retorno</button></td></tr>)}{remessas.length===0&&<tr><td colSpan={7} className="py-4 text-zinc-500">Nenhuma remessa aberta.</td></tr>}</tbody></table></div></section>

    <section className="rounded-xl border border-zinc-800 p-5"><h2 className="mb-3 font-semibold">Operações recentes</h2><div className="space-y-2">{operacoes.map(op=><div key={op.id} className="grid gap-2 rounded border border-zinc-800 p-3 md:grid-cols-[1fr_auto_auto_auto]"><div><div className="font-medium">{op.tipo.replaceAll("_"," ")} · {op.status}</div><div className="text-xs text-zinc-500">{op.id} · CFOP {op.cfop_confirmado??"por item"} · R$ {Number(op.valor_total).toLocaleString("pt-BR",{minimumFractionDigits:2})}</div></div><button className={button} onClick={()=>validar(op)}>Validar homologação</button><input className={field} value={chaves[op.id]??""} onChange={e=>setChaves(s=>({...s,[op.id]:e.target.value}))} placeholder="Chave autorizada (44)"/><button className={button} disabled={(chaves[op.id]??"").replace(/\D/g,"").length!==44} onClick={()=>registrarChave(op)}>Registrar chave</button></div>)}</div></section>
  </main>;
}
