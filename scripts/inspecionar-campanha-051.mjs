import fs from 'node:fs';
import {diretorio,situacaoRevisao} from './lib/controle-revisoes.mjs';
const base=JSON.parse(fs.readFileSync('backups/campanha-051/base-2026-09-10T21-45-48-288Z.json','utf8'));
const ler=n=>JSON.parse(fs.readFileSync(`${diretorio}/${n}`,'utf8'));
const eventos=fs.readdirSync(diretorio).filter(n=>/^eventos-.*\.json$/.test(n)).flatMap(ler);
const historico=ler('historico-recuperado.json').itens,informado=ler('historico-informado-grupos.json').itens;
const itens=base.itens.filter(i=>!['aprovado','pendente'].includes(situacaoRevisao(i,eventos,historico,informado))&&![2641,2642,2643].includes(i.id));
const arg=(nome,padrao)=>process.argv.find(a=>a.startsWith(`--${nome}=`))?.split('=').slice(1).join('=')??padrao;
if(process.argv.includes('--stats')){
 for(const campo of ['tipo','fabricante','fornecedor_id']){const mapa=new Map();for(const i of itens){const v=i[campo]??'—';mapa.set(v,(mapa.get(v)??0)+1);}console.log(campo,JSON.stringify([...mapa].sort((a,b)=>b[1]-a[1]).slice(0,45).map(([k,n])=>({valor:campo==='fornecedor_id'?`${k} ${base.fornecedores.find(f=>f.id===k)?.nome??''}`:k,n}))));}
 const mapa=new Map();for(const i of itens){const v=i.nome.split(' ')[0];mapa.set(v,(mapa.get(v)??0)+1);}console.log('prefixos',JSON.stringify([...mapa].sort((a,b)=>b[1]-a[1]).slice(0,120)));
 console.log('grupos',JSON.stringify(base.grupos.map(g=>({id:g.id,codigo:g.codigo,nome:g.nome}))));
}
if(process.argv.includes('--lista')){
 let lista=itens;const fornecedor=arg('fornecedor',null),regex=arg('regex',null),ids=arg('ids',null);
 if(fornecedor)lista=lista.filter(i=>i.fornecedor_id===Number(fornecedor));if(regex)lista=lista.filter(i=>new RegExp(regex,'i').test(i.nome));if(ids)lista=base.itens.filter(i=>ids.split(',').map(Number).includes(i.id));
 console.log('total',lista.length);
 for(const i of lista.slice(Number(arg('inicio',0)),Number(arg('inicio',0))+Number(arg('limite',200))))console.log(`${i.id}|${i.fornecedor_id}|${i.codigo_interno}|${i.nome}${process.argv.includes('--origens')?'|NOTAS: '+[...new Set(base.notas.filter(n=>n.item_id===i.id).map(n=>n.descricao))].join(' / '):''}`);
}
