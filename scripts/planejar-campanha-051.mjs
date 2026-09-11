import fs from 'node:fs';
import assert from 'node:assert/strict';
import {tenantId,empresaId,diretorio,situacaoRevisao,impressaoTecnica,validarEscopo} from './lib/controle-revisoes.mjs';
import {caminhoBase051,melhorarRedacao051,grupoMecanico051,revisoesExatas051,impedimentosExatos051,hash051,semAcento,fonteZb} from './lib/campanha-051.mjs';
const base=JSON.parse(fs.readFileSync(caminhoBase051,'utf8'));validarEscopo(base);base.itens.forEach(validarEscopo);
const ler=n=>JSON.parse(fs.readFileSync(`${diretorio}/${n}`,'utf8'));
const eventos=fs.readdirSync(diretorio).filter(n=>/^eventos-.*\.json$/.test(n)).flatMap(ler);
const historico=ler('historico-recuperado.json').itens,informado=ler('historico-informado-grupos.json').itens;
const retidos=new Map(ler('excecoes-referencias-claras.json').itens.map(i=>[i.id,i]));
const notas=new Map();for(const n of base.notas){if(!notas.has(n.item_id))notas.set(n.item_id,[]);notas.get(n.item_id).push(n);}
const suplementosNf=new Set([3605,3606,3662,3663,3664,3665,3722]);
const registros=[];
for(const i of base.itens){
 const origens=notas.get(i.id)??[],textos=[...new Set(origens.map(n=>n.descricao?.trim()).filter(Boolean))];
 const statusAnterior=situacaoRevisao(i,eventos,historico,informado);
 const r={id:i.id,codigo:i.codigo_interno,nome_antes:i.nome,fornecedor:base.fornecedores.find(f=>f.id===i.fornecedor_id)?.nome??'Sem fornecedor',tipo:i.tipo,ativo:i.ativo,finalidade:i.finalidade,status_anterior:statusAnterior,impressao_antes:impressaoTecnica(i),notas:origens.map(n=>({id:n.id,codigo:n.codigo_fornecedor,descricao:n.descricao})),fontes:[],alteracoes:{},limites:[]};
 const especial=revisoesExatas051.get(i.id),impedimento=impedimentosExatos051.get(i.id)??retidos.get(i.id);
 if(impedimento){Object.assign(r,{situacao:'revisao_humana',motivo:impedimento.motivo,necessario:impedimento.necessario,fontes:impedimento.fontes??[]});}
 else if(statusAnterior==='aprovado'){r.situacao='aprovado_anterior_preservado';}
 else if(statusAnterior==='pendente'){Object.assign(r,{situacao:'revisao_humana',motivo:'Pendência técnica individual já registrada no controle; mantida sem nova evidência.',necessario:'Conferir as fontes e a pendência no evento anterior.',eventos_anteriores:eventos.filter(e=>e.item_id===i.id)});}
 else if(/^(RESERVA|USAR)(?:\b|-)/i.test(i.nome)){r.situacao='reserva_administrativa_preservada';}
 else if(i.tipo!=='produto'){r.situacao='fora_escopo_material';r.motivo='Serviço ou despesa: não aplicar descrição de componente físico.';}
 else if(especial){
  r.alteracoes={nome:especial.nome,descricao:[i.descricao,especial.complemento].filter(Boolean).join('\n\n')};
  if(especial.grupo_id&&especial.grupo_id!==i.grupo_id)r.alteracoes.grupo_id=especial.grupo_id;
  r.fontes=especial.fontes;r.familia=especial.familia;r.situacao=especial.parcial?'melhoria_parcial':'revisao_tecnica_confirmada';
  r.motivo='Identidade e atributos conferidos individualmente na origem e nas fontes indicadas.';
  if(especial.parcial)r.limites.push('Material da caixa e composição completa ainda precisam ser confirmados.');
 }
 else {
  let entrada=i.nome;
  if(suplementosNf.has(i.id)){
   const candidatas=textos.filter(t=>/^(PARAF|PORCA|ARRUELA)/i.test(t)&&!/^ITEM \d+$/.test(t));
   assert.equal(candidatas.length,1,`Origem divergente para ${i.id}`);entrada=candidatas[0];r.origem_enriquecimento='NF vinculada conferida individualmente';
  }
  const nome=melhorarRedacao051(entrada);
  // Não gerar gravações só para remover espaçamento duplicado.
  if(nome!==i.nome&&nome!==i.nome.replace(/\s+/g,' ').trim())r.alteracoes.nome=nome;
  const grupo=grupoMecanico051(nome);
  if(grupo&&(i.grupo_id==null||i.id===3810))r.alteracoes.grupo_id=grupo;
  const mecanico=/^(PARAFUSO|PORCA|ARRUELA|BARRA ROSCADA|MACHO|BROCA|TUBO|BARRA REDONDA|ABRAÇADEIRA|ARMÁRIO)\b/.test(nome);
  if(Object.keys(r.alteracoes).length){
   r.situacao='melhoria_parcial';r.motivo=r.origem_enriquecimento??(mecanico?'Expandir somente abreviações e atributos explícitos da origem; grupo funcional quando inequívoco.':'Normalização determinística do texto existente; não adiciona atributo de catálogo.');
   r.limites.push('Esta melhoria de redação/classificação não certifica todos os atributos técnicos.');
   if(/\bZB\b|\bRI\b/.test(entrada)&&mecanico)r.fontes.push(fonteZb);
   if(r.origem_enriquecimento)r.alteracoes.descricao=[i.descricao,`Especificação recuperada da nota vinculada: ${entrada}. Dados comerciais/fiscais da nota e multiplicador de estoque preservados.`].filter(Boolean).join('\n\n');
  }else r.situacao='fila_pesquisa';
  const n=semAcento(nome),todos=semAcento([nome,...textos.filter(t=>!/^ITEM \d+$/.test(t))].join(' '));
  if(i.fabricado){r.destino_pendencia='revisao_humana';r.necessario='Desenho/revisão de fabricação e medidas ou aplicação do componente fabricado.';}
  else if(/^(MATERIAL(?: DIVERSO)?|PRODUTO|ITEM GENERICO ORCAMENTO|DIVERSOS|CONSUMO|PECAS PARA ZINCAGEM)$/.test(n)&&!/[A-Z]{2,}[-/]?\d{2,}/.test(todos)){
   r.destino_pendencia='revisao_humana';r.necessario='Identificar o produto físico, fabricante e referência. O cadastro e as notas disponíveis não fornecem identidade técnica suficiente.';
  }else if(/^(ROLAMENTO(?: DE ESFERAS)?|MANCAL(?: COMPLETO)?|SENSOR|RELE|RETENTOR|FILTRO|TAMPA MOTOR|ARRUELA EIXO|SUPORTE|FONTE DE ALIMENTACAO)$/.test(n)&&textos.every(t=>/^ITEM \d+$/.test(t)||semAcento(t)===n)){
   r.destino_pendencia='revisao_humana';r.necessario='Foto/etiqueta, referência completa e dimensões ou características de operação; não há identificação complementar nas notas vinculadas.';
  }else r.destino_pendencia='fila_pesquisa';
  if(/-DUP\d+|COPIA/i.test(i.codigo_interno)){r.alerta_duplicidade='Possível duplicado já sinalizado no código: comparar com o principal antes de qualquer marcação USAR/RESERVA. Nenhuma fusão ou marcação automática nesta campanha.';}
  if(r.situacao==='fila_pesquisa'&&r.destino_pendencia==='revisao_humana'){r.situacao='revisao_humana';r.motivo='Identidade/aplicação não resolvida pelos campos e notas disponíveis.';}
 }
 for(const c of Object.keys(r.alteracoes))if(r.alteracoes[c]===i[c])delete r.alteracoes[c];
 if(r.alteracoes.grupo_id){const g=base.grupos.find(g=>g.id===r.alteracoes.grupo_id);assert.ok(g);validarEscopo(g);}
 registros.push(r);
}
const manifesto={tenant_id:tenantId,empresa_id:empresaId,decisao:'D-051',base:caminhoBase051,base_sha256:hash051(base),escopo:'3651 cadastros da fotografia; produtos físicos alteráveis, serviços/despesas e reservas preservados. Revisão técnica não equivale a triagem.',itens:registros};
const destino=`${diretorio}/campanha-051-plano.json`;
const texto=JSON.stringify(manifesto,null,2);
if(fs.existsSync(`${diretorio}/campanha-051-resultado.json`))throw Error('Campanha já aplicada: não reescrever plano; criar rodada incremental.');
fs.writeFileSync(destino,texto);
console.log(JSON.stringify({arquivo:destino,assinatura:hash051(manifesto),total:registros.length,alterar:registros.filter(r=>Object.keys(r.alteracoes).length).length,situacoes:Object.fromEntries([...new Set(registros.map(r=>r.situacao))].map(s=>[s,registros.filter(r=>r.situacao===s).length]))},null,2));
if(process.argv.includes('--preview'))for(const r of registros.filter(r=>Object.keys(r.alteracoes).length))console.log(`${r.id}|${r.nome_antes}|${r.alteracoes.nome??'(nome preservado)'}|grupo:${r.alteracoes.grupo_id??'-'}`);
