"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

type Excecao = { tipo: string; documento_id: string; detalhe: string };
type Lacuna = { serie: number; numero_inicial: number; numero_final: number; detectada_em: string; prazo_inutilizar: string; alerta: boolean };
type Certificado = { certificado_validade_em: string | null; dias_para_vencer: number | null };
const labels: Record<string,string> = { DUPLICIDADE:"Duplicidades", CANCELADA_SUBSTITUIDA:"Canceladas e substituídas", CFOP_CST_RARO:"CFOP ou CST raro", IPI_DIVERGENTE:"IPI divergente", REDUCAO_APLICADA:"Redução aplicada", REMESSA_ABERTA:"Remessas em aberto" };
const input = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const button = "rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-800 disabled:opacity-40";

function errorMessage(error: unknown) { return error instanceof Error ? error.message : error && typeof error === "object" && "message" in error ? String(error.message) : "Erro inesperado."; }

export default function NfeExceptionsClient() {
  const scope = useTenantEmpresa();
  const supabase = useMemo(()=>supabaseBrowser(),[]);
  const [competencia,setCompetencia]=useState(new Date().toISOString().slice(0,7));
  const [itens,setItens]=useState<Excecao[]>([]);
  const [lacunas,setLacunas]=useState<Lacuna[]>([]);
  const [certificado,setCertificado]=useState<Certificado|null>(null);
  const [justificativas,setJustificativas]=useState<Record<string,string>>({});
  const [feedback,setFeedback]=useState(""); const [busy,setBusy]=useState(false);

  const reload=useCallback(async()=>{
    if(!scope.tenantId||!scope.empresaId)return;
    const [exc,lac,cert]=await Promise.all([
      supabase.schema("f").rpc("fn_nfe_excecoes_mensais",{p_competencia:`${competencia}-01`}),
      supabase.schema("f").rpc("fn_nfe_lacunas"),
      supabase.rpc("empresa_certificado_alerta"),
    ]);
    if(exc.error)throw exc.error;if(lac.error)throw lac.error;if(cert.error)throw cert.error;
    setItens(((exc.data as {itens?:Excecao[]})?.itens??[])); setLacunas((lac.data??[]) as Lacuna[]); setCertificado(cert.data as Certificado);
  },[competencia,scope.empresaId,scope.tenantId,supabase]);
  useEffect(()=>{void reload().catch(e=>setFeedback(errorMessage(e)));},[reload]);

  async function inutilizar(lacuna:Lacuna){
    const key=`${lacuna.serie}:${lacuna.numero_inicial}:${lacuna.numero_final}`; setBusy(true);setFeedback("");
    try{const {data,error}=await supabase.functions.invoke("nfe-ciclo",{body:{acao:"INUTILIZAR",serie:lacuna.serie,numero_inicial:lacuna.numero_inicial,numero_final:lacuna.numero_final,justificativa:justificativas[key]??""}});if(error)throw error;if(data?.error)throw new Error(String(data.error));setFeedback(`Faixa ${lacuna.numero_inicial}–${lacuna.numero_final} inutilizada e protocolada.`);await reload();}catch(e){setFeedback(errorMessage(e));}finally{setBusy(false);}
  }
  const groups=Object.keys(labels).map(tipo=>({tipo,itens:itens.filter(item=>item.tipo===tipo)}));
  return <main className="mx-auto max-w-[1500px] space-y-6 p-6 text-zinc-100">
    <header className="flex flex-wrap items-start justify-between gap-4"><div><div className="text-xs text-zinc-500">Faturamento › NF-e</div><h1 className="text-2xl font-semibold">Exceções e rotinas mensais</h1><p className="text-sm text-zinc-400">Checklist operacional por empresa. As ações fiscais continuam restritas à homologação.</p></div><Link href="/faturamento/nfe" className={button}>Voltar para NF-e</Link></header>
    {feedback?<div className="rounded border border-sky-800/60 bg-sky-950/20 p-3 text-sm text-sky-200">{feedback}</div>:null}
    {certificado?.dias_para_vencer===null||certificado?.dias_para_vencer===undefined?<div className="rounded border border-amber-700/60 bg-amber-950/20 p-3 text-sm text-amber-200">Validade do certificado não informada. Abra uma NF-e emitida para ler o .pfx.</div>:certificado.dias_para_vencer<=30?<div className="rounded border border-rose-700/60 bg-rose-950/20 p-3 text-sm text-rose-200">Certificado {certificado.dias_para_vencer<0?"vencido":`vence em ${certificado.dias_para_vencer} dia(s)`}.</div>:null}
    <section className="space-y-3 rounded-xl border border-zinc-800 p-4"><div className="flex items-center justify-between"><h2 className="font-semibold">Checklist da competência</h2><input type="month" className={input} value={competencia} onChange={e=>setCompetencia(e.target.value)}/></div><div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{groups.map(group=><div key={group.tipo} className={`rounded border p-3 ${group.itens.length?"border-amber-800/60 bg-amber-950/10":"border-emerald-900/50 bg-emerald-950/10"}`}><div className="flex justify-between gap-2"><strong className="text-sm">{labels[group.tipo]}</strong><span className="font-mono text-xs">{group.itens.length}</span></div><div className="mt-2 max-h-48 space-y-2 overflow-auto">{group.itens.length?group.itens.map((item,index)=><div key={`${item.documento_id}-${index}`} className="text-xs text-zinc-300"><Link className="text-sky-300 hover:underline" href={item.tipo==="REMESSA_ABERTA"?"/faturamento/operacoes":`/faturamento/nfe/${item.documento_id}`}>{item.detalhe}</Link></div>):<p className="text-xs text-emerald-300">Sem ocorrência.</p>}</div></div>)}</div></section>
    <section className="space-y-3 rounded-xl border border-zinc-800 p-4"><div><h2 className="font-semibold">Lacunas de numeração</h2><p className="text-xs text-zinc-400">Alerta a partir de cinco dias antes do prazo legal. Número já registrado em qualquer estado não entra aqui.</p></div>{lacunas.map(l=>{const key=`${l.serie}:${l.numero_inicial}:${l.numero_final}`;return <div key={key} className={`grid gap-3 rounded border p-3 lg:grid-cols-[220px_180px_1fr_auto] lg:items-center ${l.alerta?"border-rose-700/60 bg-rose-950/20":"border-zinc-800"}`}><div className="text-sm">Série {l.serie} · {l.numero_inicial}–{l.numero_final}</div><div className="text-xs text-zinc-400">Prazo {new Date(`${l.prazo_inutilizar}T00:00:00`).toLocaleDateString("pt-BR")}</div><input className={input} value={justificativas[key]??""} onChange={e=>setJustificativas(s=>({...s,[key]:e.target.value}))} placeholder="Justificativa (mínimo 15 caracteres)"/><button className={button} disabled={busy||(justificativas[key]??"").trim().length<15} onClick={()=>void inutilizar(l)}>Inutilizar faixa</button></div>})}{!lacunas.length?<p className="text-sm text-emerald-300">Nenhuma lacuna pendente detectada.</p>:null}</section>
  </main>;
}
