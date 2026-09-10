import fs from 'node:fs';
import assert from 'node:assert/strict';
import {tenantId,empresaId,diretorio,validarEscopo,impressaoTecnica} from './lib/controle-revisoes.mjs';
import {grupos011} from './lib/lotes-cinquenta.mjs';
const ler=f=>JSON.parse(fs.readFileSync(f,'utf8'));
const baseArquivo=fs.readdirSync('backups/base-revisao').filter(f=>f.endsWith('.json')).sort().at(-1);
const base=ler(`backups/base-revisao/${baseArquivo}`);validarEscopo(base);
const m=ler(`${diretorio}/lote-011-cinquenta-itens.json`),l=ler(`${diretorio}/liberacao-011-referencias-claras.json`);
const eventos=fs.readdirSync(diretorio).filter(f=>/^eventos-.*\.json$/.test(f)).flatMap(f=>ler(`${diretorio}/${f}`));eventos.forEach(validarEscopo);
const motivos={
 240:['Material isolante não identificado; largura não conciliada com o passo da tabela.','Catálogo/desenho dimensional e polímero da referência exata.'],
 256:['Material do atuador não confirmado.','Ficha ou confirmação do fabricante sobre material da versão de 67mm.'],
 346:['Material do atuador não confirmado.','Ficha ou confirmação do fabricante sobre material da versão de 77mm.'],
 735:['Tipo de conexão do histórico não explícito na ficha consultada.','Documento que confirme os terminais e a combinação disjuntor/contator.'],
 776:['Resumo inclui CA/CC e outros dispositivos; tabela limita a bobina a CC.','Compatibilidade exata por versão de contator e bobina.'],
 824:['Tensão e material do pente de interface ausentes.','Ficha completa da referência, com limites elétricos e material.'],
 944:['Faixa de condutor encordoado invertida na tabela; polímero não identificado.','Correção do fabricante ou manual exato com seção por tipo de condutor.'],
 957:['Resumo e tabela indicam gerações diferentes de contatores compatíveis.','Manual que identifique exatamente as referências compatíveis.'],
 977:['Polímero e largura dimensional não confirmados.','Ficha/desenho com material e largura, sem confundir seção com passo.'],
 978:['Polímero e referência exata do borne compatível não confirmados.','Lista oficial de compatibilidade da tampa e material.'],
 1088:['Compatibilidade G120 e composição do kit não confirmadas na ficha resumida.','Manual do BOP-2 e lista de fornecimento/montagem da referência.'],
 1615:['Polímero e referência exata do borne compatível não confirmados.','Lista oficial de compatibilidade da tampa e material.'],
 1616:['Limites de condutor encordoado invertidos na tabela.','Manual ou correção do fabricante. Não transformar PE em PEN.'],
 1618:['Cor conflitante; seção histórica, material e limites elétricos não confirmados.','Ficha/catálogo exato que esclareça a cor, compatibilidade e limites.'],
 1619:['Resumo/corrente térmica indicam 5A; faixa da saída informa apenas 5mA, sem máximo.','Tabela oficial completa de corrente da saída e condições de carga.'],
 1623:['Fornecimento de bateria e fonte externa não confirmado.','Composição da compra ou lista oficial de fornecimento; não presumir UPS completo.'],
 2450:['Material e comprimento do atuador não confirmados.','Desenho e material da referência exata.'],
 2455:['Comprimento do atuador não confirmado.','Desenho dimensional da referência exata.'],
 2535:['Ficha indica embalagem com 50 peças; relação com a unidade comercial do ERP é desconhecida.','Documento de compra e conferência da unidade. Nenhum fator será alterado nesta revisão.'],
 2641:['Limites elétricos ausentes; código coincide após normalização com ID 2698.','Ficha completa e conferência cadastral da dupla; não fundir registros.'],
 2642:['Limites elétricos ausentes; código coincide após normalização com ID 2699.','Ficha completa e conferência cadastral da dupla; não fundir registros.'],
 2643:['Limites elétricos ausentes; código coincide após normalização com ID 2700.','Ficha completa e conferência cadastral da dupla; não fundir registros.'],
};
const excecoes=l.retidos.map(id=>{const i=m.itens.find(i=>i.id===id);assert.ok(motivos[id]);return {id,codigo:i.antes.codigo_interno,nome_atual:i.antes.nome,motivo:motivos[id][0],necessario:motivos[id][1],fontes:i.fontes,evidencia:i.evidencia,origem:'011-retido',status:'aguardando_esclarecimento_tecnico'};});
function extra(id,motivo,necessario,fontes,evidencia,origem='complemento-siemens'){
 const i=base.itens.find(i=>i.id===id);assert.ok(i);validarEscopo(i);
 assert.ok(!eventos.some(e=>e.item_id===id));
 excecoes.push({id,codigo:i.codigo_interno,nome_atual:i.nome,motivo,necessario,fontes,evidencia,origem,status:'aguardando_esclarecimento_tecnico'});
}
for(const i of ler(`${diretorio}/pesquisa-adiada-011.json`).fora_do_lote){
 extra(i.id,'Ficha oficial indisponível (HTTP 404); identidade técnica não reconfirmada.','Catálogo histórico ou ficha do fabricante para o código exato.',[`https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${i.codigo}`],null,'pesquisa-adiada-011');
}
for(const id of [769,1580,1581,1584,1587]){
 const f=ler(`backups/fontes-complemento-paineis/${id}.falha.json`);
 extra(id,'Código A7B não retornou ficha oficial. Correspondência com código técnico não confirmada pelo fabricante.','Catálogo Siemens ou etiqueta que vincule o código A7B à referência técnica exata.',[f.url],f);
}
extra(447,'Resumo informa placa de 26mm; tabela informa largura de 26,5mm. Material não confirmado.','Desenho/medição identificada e confirmação do material, distinguindo dimensão nominal e física.',[ler('backups/fontes-complemento-paineis/447.fonte.json').url],{arquivo:'backups/fontes-complemento-paineis/447.pdf',paginas:[1]});
for(const [id,anterior] of [[2698,2641],[2699,2642],[2700,2643]]){
 const i=m.itens.find(i=>i.id===anterior);assert.equal(i.referencia.replace(/-/g,''),base.itens.find(a=>a.id===id).codigo_interno.replace(/-/g,''));
 extra(id,`Mesma referência normalizada do ID ${anterior}; ficha resumida não informa limites elétricos.`,`Conferência cadastral da dupla ${anterior}/${id} e ficha completa; não fundir registros.`,i.fontes,i.evidencia);
}
assert.equal(excecoes.length,36);assert.equal(new Set(excecoes.map(i=>i.id)).size,36);
const recentes=eventos.filter(e=>e.origem_aprovacao==='autorizacao_condicional_D-047');
assert.equal(recentes.length,29);
const idsEscopo=new Set([...base.itens.filter(i=>i.ativo&&Object.values(grupos011).includes(i.grupo_id)).map(i=>i.id),...excecoes.map(i=>i.id)]);
const fila=[...idsEscopo].sort((a,b)=>a-b).map(id=>{
 const i=base.itens.find(i=>i.id===id),e=eventos.filter(e=>e.item_id===id).at(-1);
 const pendente=excecoes.find(p=>p.id===id);
 return {id,codigo:i.codigo_interno,nome:i.nome,grupo_id:i.grupo_id,fornecedor_id:i.fornecedor_id,impressao_tecnica:impressaoTecnica(i),status:pendente?'aguardando_esclarecimento_tecnico':e?(e.impressao_tecnica===impressaoTecnica(i)?e.status:'reavaliar'):'aguardando_pesquisa',origem:pendente?.origem??e?.lote??null};
});
const escopo={tenant_id:tenantId,empresa_id:empresaId,gerado_em:new Date().toISOString(),base:`backups/base-revisao/${baseArquivo}`};
fs.writeFileSync(`${diretorio}/fila-paineis-referencias-claras.json`,JSON.stringify({...escopo,grupos:Object.values(grupos011),observacao:'Recorte operacional dos grupos do lote 011, todas as marcas, mais exceção histórica 242. Aguardar pesquisa não significa referência duvidosa. Não representa catálogo inteiro.',contagens:Object.fromEntries([...new Set(fila.map(i=>i.status))].map(s=>[s,fila.filter(i=>i.status===s).length])),itens:fila},null,2));
fs.writeFileSync(`${diretorio}/excecoes-referencias-claras.json`,JSON.stringify({...escopo,aplicados_nesta_rodada:29,total_excecoes:36,itens:excecoes},null,2));
const cel=s=>String(s).replace(/\|/g,'/').replace(/\n/g,' ');
fs.writeFileSync(`${diretorio}/excecoes-referencias-claras.md`,[
 '# Itens não claros — revisão de painéis Siemens','',
 '29 itens claros aplicados e verificados nesta rodada. Abaixo estão somente os 36 casos mantidos sem alteração: 22 do lote 011 e 14 encontrados na conferência complementar. Fonte indisponível não significa produto inexistente.','',
 'Este relatório não declara o catálogo inteiro concluído: outras marcas e famílias permanecem na fila de pesquisa, separadas das dúvidas técnicas. As ressalvas das revisões anteriores continuam registradas nos respectivos lotes.','',
 `Consulta de controle: ${escopo.gerado_em}. Escopo: tenant ${tenantId}; empresa ${empresaId}.`,'',
 '| ID | Código | Motivo para não alterar | O que falta confirmar |','| ---: | --- | --- | --- |',
 ...excecoes.sort((a,b)=>a.id-b.id).map(i=>`| ${i.id} | ${i.codigo} | ${cel(i.motivo)} | ${cel(i.necessario)} |`),'',
 '## Evidências para retomada','',...excecoes.map(i=>`- ID ${i.id}: ${i.fontes.map(f=>`[fonte consultada](${f})`).join('; ')}. ${i.evidencia?.arquivo?`Arquivo preservado: ${i.evidencia.arquivo}.`:''}`),'',
 'Não retornar estes IDs à fila automática sem nova evidência. Não alterar unidades, fatores, códigos ou fundir possíveis duplicidades. Manifestos, backups, impressão técnica e eventos conservam os antes/depois internos.',''
 ].join('\n'));
console.log(JSON.stringify({aplicados:29,excecoes:excecoes.length,fila:fila.length,nao_pesquisados:fila.filter(i=>i.status==='aguardando_pesquisa').length}));
