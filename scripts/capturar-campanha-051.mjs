import fs from 'node:fs';
import {createClient} from '@supabase/supabase-js';
import {tenantId,empresaId} from './lib/controle-revisoes.mjs';
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split(/\r?\n/).filter(l=>l.includes('=')&&!l.trim().startsWith('#')).map(l=>{const p=l.indexOf('=');return[l.slice(0,p).trim(),l.slice(p+1).trim().replace(/^(["'])(.*)\1$/,'$2')];}));
const db=createClient(env.NEXT_PUBLIC_SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
async function ler(tabela,campos='*'){
 const rows=[];for(let offset=0;;offset+=1000){const {data,error}=await db.from(tabela).select(campos).eq('tenant_id',tenantId).eq('empresa_id',empresaId).order('id').range(offset,offset+999);if(error)throw new Error(`${tabela}: ${error.message}`);rows.push(...data);if(data.length<1000)return rows;}
}
const [itens,grupos,fornecedores,notas]=await Promise.all([ler('itens'),ler('item_grupos'),ler('fornecedores','id,nome'),ler('nf_entrada_itens','id,item_id,codigo_fornecedor,descricao')]);
const pasta='backups/campanha-051';fs.mkdirSync(pasta,{recursive:true});
const arquivo=`${pasta}/base-${new Date().toISOString().replace(/[:.]/g,'-')}.json`;
fs.writeFileSync(arquivo,JSON.stringify({tenant_id:tenantId,empresa_id:empresaId,capturado_em:new Date().toISOString(),itens,grupos,fornecedores,notas},null,2),{flag:'wx'});
console.log(JSON.stringify({arquivo,itens:itens.length,grupos:grupos.length,fornecedores:fornecedores.length,notas:notas.length}));
