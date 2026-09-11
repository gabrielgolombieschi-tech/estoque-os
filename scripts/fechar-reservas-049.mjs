import fs from 'node:fs';
import assert from 'node:assert/strict';
import {diretorio,validarEscopo,impressaoTecnica} from './lib/controle-revisoes.mjs';
import {pares049,pendentes049,conferir049} from './lib/reservas-049.mjs';
const ler=n=>JSON.parse(fs.readFileSync(`${diretorio}/${n}`,'utf8'));
const r=ler('marcacao-reservas-049.json');validarEscopo(r);assert.equal(r.status,'aplicado_verificado');
assert.deepEqual(r.pares.map(({usar,reserva,referencia})=>({usar,reserva,referencia})),pares049);
for(const p of r.pares)conferir049(p.antes,p.depois,true);
const e=ler('excecoes-referencias-claras.json');validarEscopo(e);assert.deepEqual(e.itens.map(i=>i.id).sort((a,b)=>a-b),pendentes049);
e.decisao='D-049';e.gerado_em=new Date().toISOString();e.pendencia_marcacao={total_ids:0,pares:[]};
e.marcacao_concluida={total_reservas:3,principais_preservados:3,registro:'marcacao-reservas-049.json',aplicado_em:r.aplicado_em};
e.orientacao_atual='Demais itens pendentes por solicitação do usuário; não retomar automaticamente nem alterar conversão do ID 2535.';
fs.writeFileSync(`${diretorio}/excecoes-referencias-claras.json`,JSON.stringify(e,null,2));
fs.writeFileSync(`${diretorio}/excecoes-referencias-claras.md`,[
  '# Pendências após marcação D-049','',
  'Três duplicados tiveram nome e código substituídos por RESERVA-[ID]. Três principais preservados; sete dificuldades técnicas/comerciais permanecem pendentes por solicitação do usuário. Tratamento administrativo não é aprovação técnica das descrições.','',
  '| ID pendente | Código | Dificuldade |','| ---: | --- | --- |',...e.itens.map(i=>`| ${i.id} | ${i.codigo} | ${i.motivo} |`),'',
  'ID2535 permanece com preço cadastrado R$92,99, unidade UN e fator 1; unidade comercial/embalagem não confirmada. Nenhuma conversão aplicada.','',
  '## Duplicados tratados','',
  '| ID reserva | Código anterior | Nome anterior | Novo nome e código | Principal preservado |','| ---: | --- | --- | --- | ---: |',
  ...r.pares.map(p=>`| ${p.reserva} | ${p.antes.codigo_interno} | ${p.antes.nome} | ${p.depois.nome} | ${p.usar} |`),'',
  'Referências originais e antes/depois completos em [marcacao-reservas-049.json](marcacao-reservas-049.json). NCM, impostos, preços, unidades e demais campos preservados; apenas código derivado e timestamps são recalculados pelo banco. Sem exclusão, inativação, mesclagem ou transferência. RESERVA no nome não bloqueia tecnicamente uso no ERP.','',
  'D-048: 23 descrições já corrigidas; manifestos históricos preservados. Não retomar os sete pendentes até nova orientação.',''
].join('\n'));
const fila=ler('fila-paineis-referencias-claras.json');validarEscopo(fila);
for(const p of r.pares)for(const id of [p.usar,p.reserva]){
  const i=fila.itens.find(i=>i.id===id);assert.ok(i);const atual=id===p.reserva?p.depois:p.principal_preservado;
  Object.assign(i,{codigo:atual.codigo_interno,nome:atual.nome,impressao_tecnica:impressaoTecnica(atual),status:id===p.reserva?'reserva':'principal_selecionado',origem:'D-049',vinculo_duplicidade:{usar:p.usar,reserva:p.reserva},observacao:'Tratamento administrativo concluído; não equivale a aprovação técnica da descrição.'});
}
fila.gerado_em=new Date().toISOString();fila.atualizacao_parcial='marcacao-reservas-049.json; demais registros mantêm a base anterior.';
fila.contagens=Object.fromEntries([...new Set(fila.itens.map(i=>i.status))].map(s=>[s,fila.itens.filter(i=>i.status===s).length]));
fs.writeFileSync(`${diretorio}/fila-paineis-referencias-claras.json`,JSON.stringify(fila,null,2));
console.log(JSON.stringify({reservas:3,principais_preservados:3,pendentes:e.itens.length,fila:fila.contagens}));
