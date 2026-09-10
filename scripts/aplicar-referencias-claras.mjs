import fs from "node:fs";
import assert from "node:assert/strict";
import {createClient} from "@supabase/supabase-js";
import {tenantId,empresaId,diretorio,criterios,impressaoTecnica} from "./lib/controle-revisoes.mjs";
import {conferirCinquenta,assinatura} from "./lib/lotes-cinquenta.mjs";
import {validarLiberacaoClara,planejarReferenciasClaras} from "./lib/referencias-claras.mjs";
const numero=process.argv.find(a=>a.startsWith("--lote="))?.slice(7); assert.match(numero??"",/^\d{3}$/);
const ler=arquivo=>JSON.parse(fs.readFileSync(`${diretorio}/${arquivo}`,"utf8"));
const arquivoManifesto=fs.existsSync(`${diretorio}/lote-${numero}-referencias-claras.json`)?`lote-${numero}-referencias-claras.json`:`lote-${numero}-cinquenta-itens.json`;
const m=ler(arquivoManifesto),liberacao=ler(`liberacao-${numero}-referencias-claras.json`),autorizacao=ler("autorizacao-referencias-claras.json");
validarLiberacaoClara(m,liberacao,autorizacao); // Autoridade e evidências antes da conexão.
const env=Object.fromEntries(fs.readFileSync(".env.local","utf8").split(/\r?\n/).filter(l=>l.includes("=")&&!l.trim().startsWith("#")).map(l=>{const p=l.indexOf("=");return [l.slice(0,p).trim(),l.slice(p+1).trim().replace(/^(["'])(.*)\1$/,"$2")];}));
const db=createClient(env.NEXT_PUBLIC_SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const scope=q=>q.eq("tenant_id",tenantId).eq("empresa_id",empresaId);
async function consultar(){const {data,error}=await scope(db.from("itens").select("*")).in("id",m.itens.map(i=>i.id));if(error)throw new Error(error.message);return data;}
const plano=planejarReferenciasClaras(m,await consultar()),selecionados=plano.filter(p=>liberacao.ids_claros.includes(p.item.id));
const alterar=selecionados.filter(p=>!p.aplicado);
const retidos=plano.filter(p=>liberacao.retidos.includes(p.item.id));
assert.ok(retidos.every(p=>!p.aplicado),"Retido não pode aparecer aplicado por esta rotina");
console.log(JSON.stringify({lote:m.lote,claros:selecionados.length,a_alterar:alterar.length,retidos:retidos.length}));
if(process.argv.includes("--verify"))assert.equal(alterar.length,0);
if(process.argv.includes("--apply")) {
  let backup=null;
  if(alterar.length){
    fs.mkdirSync("backups/revisao-lotes",{recursive:true});
    backup=`backups/revisao-lotes/${numero}-claros-${new Date().toISOString().replace(/[:.]/g,"-")}.json`;
    fs.writeFileSync(backup,JSON.stringify({tenant_id:tenantId,empresa_id:empresaId,manifesto:m,liberacao,autorizacao,plano},null,2),{flag:"wx"});
    for(const p of alterar){
      let q=scope(db.from("itens").update(p.depois));
      for(const c of new Set(["id","codigo_interno","nome","descricao","fabricante","fornecedor_id","grupo_id","tipo","finalidade","ativo","atualizado_em",...Object.keys(p.antes).filter(c=>/unidade|multiplicador|conversao|fator|modelo|referencia|especificacao/.test(c))]))q=p.antes[c]==null?q.is(c,null):q.eq(c,p.antes[c]);
      const {data,error}=await q.select("*");
      if(error||data?.length!==1)throw new Error(`Parou em ${p.item.id}: ${error?.message??"alteração concorrente"}. Backup ${backup}`);
      fs.appendFileSync(`${backup}.resultado.jsonl`,JSON.stringify(data[0])+"\n"); conferirCinquenta(p,data[0]);
    }
  }
  const atuais=await consultar();
  for(const p of selecionados)conferirCinquenta(p,atuais.find(i=>i.id===p.item.id));
  for(const p of retidos)assert.deepEqual(atuais.find(i=>i.id===p.item.id),p.antes,`Retido mudou: ${p.item.id}`);
  const eventos=selecionados.map(p=>{const i=atuais.find(i=>i.id===p.item.id);return {tenant_id:tenantId,empresa_id:empresaId,item_id:i.id,codigo:i.codigo_interno,nome:i.nome,familia:p.item.familia,criterio:criterios[p.item.familia],lote:m.lote,revisado_em:new Date().toISOString(),responsavel:liberacao.responsavel_conferencia,status:"aprovado",origem_aprovacao:"autorizacao_condicional_D-047",fontes:p.item.fontes,pendencias:[],atributos_nao_confirmados:[],impressao_tecnica:impressaoTecnica(i),backup,assinatura_lote:assinatura(m)};});
  const destino=`${diretorio}/eventos-${m.lote}.json`;
  if(fs.existsSync(destino)){const antigos=JSON.parse(fs.readFileSync(destino,"utf8"));assert.equal(antigos.length,eventos.length);for(const e of eventos){const a=antigos.find(a=>a.item_id===e.item_id);for(const c of ["tenant_id","empresa_id","criterio","status","impressao_tecnica","assinatura_lote"])assert.equal(a?.[c],e[c]);}}
  else fs.writeFileSync(destino,JSON.stringify(eventos,null,2),{flag:"wx"});
  console.log(JSON.stringify({atualizados:alterar.length,verificados:selecionados.length,retidos_sem_alteracao:retidos.length,backup}));
}
