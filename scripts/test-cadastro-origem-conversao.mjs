import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import ts from 'typescript';
import * as normalizacao from '../lib/itens/cadastroNormalizacao.ts';
import * as nomes from '../lib/itens/normalizacaoNome.ts';
import * as qualidade from '../lib/itens/qualidadeDescricao.ts';

const require=createRequire(import.meta.url);
function carregar(arquivo,dependencias={}) {
  const exports={};
  const codigo=ts.transpileModule(fs.readFileSync(arquivo,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,esModuleInterop:true}}).outputText;
  vm.runInNewContext(codigo,{exports,require:n=>dependencias[n]??require(n),process,Buffer,URL,Date,console,setTimeout,clearTimeout},{filename:arquivo});
  return exports;
}
const lib=carregar('app/api/itens/agente-cadastro/_lib.ts',{
  '@/lib/itens/cadastroNormalizacao':normalizacao,
  '@/lib/itens/normalizacaoNome':nomes,
  '@/lib/itens/qualidadeDescricao':qualidade,
});
for(let origem=0;origem<=8;origem++){
  assert.equal(lib.sanitizarFiscal({origem,ncm:'85444200'}).origem,origem);
  assert.equal(lib.sanitizarFiscal({origem:String(origem)}).origem,origem);
}
assert.equal(lib.fiscalComReferencia({origem:2,ncm:'85444200'},440).origem,0);
for(const origem of [-1,9,1.5,'abc',false,{}])assert.equal(normalizacao.origemFiscalConfirmada(origem),null);
assert.equal(normalizacao.origemFiscalConfirmada(undefined),0);
for(const [estoque,compra] of [['UN','UN'],[' un ','Un '],['M','m']]){
  const r=normalizacao.normalizarConversaoCadastro(estoque,compra,1);
  assert.equal(r.erro,null);assert.equal(r.unidade_compra,null);assert.equal(r.fator_conversao_estoque,1);
}
for(const fator of [50,0,-1,NaN,Infinity,null])assert.ok(normalizacao.normalizarConversaoCadastro('UN','UN',fator).erro);
assert.equal(normalizacao.normalizarConversaoCadastro('M','RL',100).fator_conversao_estoque,100);
assert.equal(normalizacao.normalizarConversaoCadastro('UN',' ',null).fator_conversao_estoque,1);

// Executa a rota real com banco em memória: nenhuma consulta/mutação remota.
async function confirmar({origem=2,compra='UN',fator=1,permitido=true}={}){
  const gravacoes=[];
  const db={rpc:async(_,{p_resource})=>({data:p_resource==='fiscal_itens'?permitido:true,error:null}),from(tabela){
    let payload=null;const filtros=[];
    const resposta=()=>{
      if(payload){assert.equal(payload.tenant_id,'tenant-teste');assert.equal(payload.empresa_id,'empresa-teste');gravacoes.push({tabela,payload});return {data:{id:999,...payload},error:null};}
      assert.ok(filtros.some(([c,v])=>c==='tenant_id'&&v==='tenant-teste'));
      assert.ok(filtros.some(([c,v])=>c==='empresa_id'&&v==='empresa-teste'));
      return {data:tabela==='fornecedores'?{id:1,nome:'Fornecedor teste',ativo:true}:tabela==='item_grupos'?{id:46,ativo:true}:[],error:null};
    };
    const chain={select(){return chain;},eq(c,v){filtros.push([c,v]);return chain;},order(){return chain;},limit(){return chain;},insert(p){payload=p;return chain;},upsert(p){payload=p;return chain;},single(){return Promise.resolve(resposta());},maybeSingle(){return Promise.resolve(resposta());},then(resolve,reject){return Promise.resolve().then(resposta).then(resolve,reject);}};
    return chain;
  }};
  const rota=carregar('app/api/itens/agente-cadastro/confirmar/route.ts',{
    'next/server':{NextResponse:{json:(body,{status=200}={})=>({status,body})}},
    '@/app/api/compras/_lib':{getAuthSupabase:async()=>({supabase:db,user:{id:'usuario-teste'}}),resolveTenantEmpresa:async()=>({tenantId:'tenant-teste',empresaId:'empresa-teste'}),jsonError:(status,error)=>({status,body:{error}})},
    '@/lib/supabase/admin':{supabaseAdmin:()=>db},
    '@/lib/itens/cadastroNormalizacao':normalizacao,
    '../_lib':{...lib,verificarTokenCotacaoAssinada:()=>({tenant_id:'tenant-teste',empresa_id:'empresa-teste',usuario_id:'usuario-teste',fornecedor_id:1,codigo:'TESTE123',quantidade_referencia:0,fontes:[],pesquisa_preco:{}})},
  });
  const result=await rota.POST({json:async()=>({fornecedor_id:1,codigo:'TESTE123',quantidade_referencia:0,preco_unitario_confirmado:595.30,cotacao_token:'teste',sugestao:{descricao_padronizada:'CABO PARA SENSOR M12 4 PINOS',grupo_id:46,unidade_medida:'UN',unidade_compra:compra,fator_conversao_estoque:fator},fiscal_sugerido:{ncm:'85444200',origem}})});
  return {...result,gravacoes};
}
for(const origem of [0,1,2,8]){
  const r=await confirmar({origem});assert.equal(r.status,201,JSON.stringify(r.body));
  const item=r.gravacoes.find(g=>g.tabela==='itens').payload;
  assert.equal(item.unidade_compra,null);assert.equal(item.fator_conversao_estoque,1);assert.equal(item.preco_unitario,595.30);
  assert.equal(r.gravacoes.find(g=>g.tabela==='fiscal_itens').payload.origem,origem);
}
const pacote=await confirmar({compra:'CX',fator:50});assert.equal(pacote.status,201);assert.equal(pacote.gravacoes.find(g=>g.tabela==='itens').payload.preco_unitario,595.30/50);
for(const options of [{fator:50},{fator:0},{origem:9},{origem:1.5},{permitido:false}]){
  const r=await confirmar(options);assert.equal(r.status,options.permitido===false?403:422);assert.equal(r.gravacoes.length,0);
}
console.log('OK: origem 0–8 preservada até gravação, padrão inicial nacional, permissão fiscal, UN/UN fator 1, conflito de fator e conversão CX/UN. Banco simulado, sem escrita remota.');
