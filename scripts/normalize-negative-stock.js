const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const env = Object.fromEntries(fs.readFileSync('.env.local','utf8').split(/\r?\n/).filter(Boolean).map(l=>{const i=l.indexOf('='); return [l.slice(0,i), l.slice(i+1)]}));
const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const APPLY = process.argv.includes('--apply');
const motivoBase = 'INVENTARIO EXTRAORDINARIO: normalizacao de saldo negativo para zero';
async function all(table, cols){let from=0,res=[];for(;;){const {data,error}=await supabase.from(table).select(cols).range(from,from+999);if(error) throw error;if(!data?.length) break;res=res.concat(data);if(data.length<1000) break;from+=1000;}return res;}
(async()=>{
 const estoque = await all('estoque','tenant_id,empresa_id,item_id,quantidade_atual');
 const neg = estoque.filter(e=>Number(e.quantidade_atual??0)<0).map(e=>({
   tenant_id:e.tenant_id,
   empresa_id:e.empresa_id,
   item_id:e.item_id,
   quantidade: Math.abs(Number(e.quantidade_atual||0))
 }));
 let ok=0,err=0,errors=[];
 if(APPLY){
   for(const r of neg){
     const payload={
       tenant_id:r.tenant_id,
       empresa_id:r.empresa_id,
       item_id:r.item_id,
       tipo:'ajuste',
       quantidade:r.quantidade,
       motivo:motivoBase,
       realizado_por:'auditoria_sistema',
       data_movimentacao:new Date().toISOString(),
       created_at:new Date().toISOString(),
     };
     const {error}=await supabase.from('movimentacoes').insert(payload);
     if(error){err++; errors.push({item_id:r.item_id,error:error.message});}
     else ok++;
   }
 }
 const out={apply:APPLY,total_negativos:neg.length,ajustes_ok:ok,ajustes_erro:err,errors:errors.slice(0,100)};
 const f=`tmp/normalize_negative_stock_${APPLY?'apply':'dryrun'}_${new Date().toISOString().replace(/[:.]/g,'-')}.json`;
 fs.mkdirSync('tmp',{recursive:true});
 fs.writeFileSync(f,JSON.stringify(out,null,2));
 console.log(JSON.stringify(out,null,2));
 console.log('report',f);
})();
