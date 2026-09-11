import fs from 'node:fs';
import assert from 'node:assert/strict';
import {diretorio,tenantId,empresaId,validarEscopo,impressaoTecnica,criterios} from './lib/controle-revisoes.mjs';
import {hash051,conferirPreservacao051} from './lib/campanha-051.mjs';
const ler=n=>JSON.parse(fs.readFileSync(`${diretorio}/${n}`,'utf8'));
const plano=ler('campanha-051-plano.json'),resultado=ler('campanha-051-resultado.json');
validarEscopo(plano);validarEscopo(resultado);assert.equal(resultado.status,'aplicado_verificado');assert.equal(resultado.assinatura,hash051(plano));
const backup=JSON.parse(fs.readFileSync(resultado.backup,'utf8'));validarEscopo(backup);
const aplicados=new Set(resultado.aplicados.map(a=>a.id));
for(const r of plano.itens.filter(r=>aplicados.has(r.id)))conferirPreservacao051(backup.itens.find(i=>i.id===r.id),resultado.itens_atuais.find(i=>i.id===r.id),r.alteracoes);
const registros=plano.itens.map(r=>{const atual=resultado.itens_atuais.find(i=>i.id===r.id);return {...r,situacao:aplicados.has(r.id)?r.situacao:Object.keys(r.alteracoes).length?'mudanca_concorrente':r.situacao,aplicado:aplicados.has(r.id),nome_atual:atual?.nome??r.nome_antes,impressao_atual:atual?impressaoTecnica(atual):null,verificado_em:resultado.verificado_em};});
const eventos=registros.filter(r=>r.aplicado&&r.situacao==='revisao_tecnica_confirmada').map(r=>({tenant_id:tenantId,empresa_id:empresaId,item_id:r.id,codigo:r.codigo,nome:r.nome_atual,familia:r.familia,criterio:criterios[r.familia],lote:'014-campanha-integral-051',revisado_em:resultado.verificado_em,responsavel:'Codex: D-051, continuidade autorizada por referência clara',status:'aprovado',origem_aprovacao:'autorizacao_condicional_D-051',fontes:r.fontes,notas_origem_ids:r.notas.map(n=>n.id),pendencias:[],impressao_tecnica:r.impressao_atual,backup:resultado.backup,assinatura_lote:resultado.assinatura}));
for(const e of eventos)assert.ok(e.criterio);
function congelar(nome,conteudo){const path=`${diretorio}/${nome}`;if(fs.existsSync(path))assert.deepEqual(JSON.parse(fs.readFileSync(path,'utf8')),conteudo,'Arquivo fechado divergente');else fs.writeFileSync(path,JSON.stringify(conteudo,null,2),{flag:'wx'});}
function gravarRelatorio(nome,conteudo){const path=`${diretorio}/${nome}`;if(fs.existsSync(path))assert.equal(fs.readFileSync(path,'utf8'),conteudo,`Relatório ${nome} editado: preservar respostas e gerar uma nova versão.`);else fs.writeFileSync(path,conteudo,{flag:'wx'});}
congelar('eventos-014-campanha-integral-051.json',eventos);
const contagens=Object.fromEntries([...new Set(registros.map(r=>r.situacao))].map(s=>[s,registros.filter(r=>r.situacao===s).length]));
const controle={tenant_id:tenantId,empresa_id:empresaId,decisao:'D-051',criterio:'TRIAGEM_INTEGRAL:1',verificado_em:resultado.verificado_em,assinatura:resultado.assinatura,base:plano.base,total_fotografia:registros.length,aplicados:aplicados.size,contagens,novos_fora_fotografia:resultado.itens_atuais.filter(i=>!registros.some(r=>r.id===i.id)).map(i=>i.id),itens:registros};
congelar('campanha-051-controle.json',controle);
const cel=v=>String(v??'—').replace(/\|/g,' / ').replace(/[\r\n]+/g,' ').replace(/</g,'&lt;');
const referencias=r=>r.fontes.map((url,k)=>`[Fonte ${k+1}](${url})`).join(' · ')||'Cadastro/NF vinculada';
const humanos=registros.filter(r=>r.situacao==='revisao_humana'||r.destino_pendencia==='revisao_humana'||r.situacao==='mudanca_concorrente').sort((a,b)=>Number([1612,2908,2491,3807].includes(b.id))-Number([1612,2908,2491,3807].includes(a.id))||a.id-b.id);
const pesquisa=registros.filter(r=>['fila_pesquisa','melhoria_parcial'].includes(r.situacao)&&!humanos.some(h=>h.id===r.id));
const linhas=[
 '# Itens para revisar amanhã — 11/09/2026','',
 `Gerado após aplicação e releitura em ${resultado.verificado_em}. Empresa autorizada: ${empresaId}.`, '',
 `A fotografia contém ${registros.length} cadastros. Foram aplicadas ${aplicados.size} melhorias: ${eventos.length} revisões técnicas por referência exata e ${registros.filter(r=>r.aplicado&&r.situacao==='melhoria_parcial').length} melhorias parciais de redação/classificação. Os 490 anteriormente aprovados foram preservados.`, '',
 `Este arquivo reúne ${humanos.length} casos para decisão/documentação humana. Escreva sua resposta abaixo de cada item; os dados originais foram preservados. Não há proposta de exclusão, fusão, alteração fiscal ou conversão de unidade.`, '',
 `A revisão técnica de 100% NÃO foi concluída. Há ainda ${pesquisa.length} registros na [fila de pesquisa técnica](fila-pesquisa-campanha-051.md), incluindo melhorias parciais. Essa fila não significa ausência de informação sua: contém referências que ainda precisam ser pesquisadas ou validadas.`, '',
 '[Antes e depois dos itens alterados](alteracoes-campanha-051.md). [Controle completo por ID](campanha-051-controle.json).', '',
 '## Dúvidas para sua revisão','',
 ];
for(const r of humanos){
 const origens=[...new Set(r.notas.map(n=>n.descricao).filter(Boolean))];
 const eventoAnterior=r.eventos_anteriores?.at(-1);
 const motivo=eventoAnterior?.pendencias?.join(' ')||r.motivo||'Identificação e aplicação dependem de documentação interna.';
 const necessario=eventoAnterior?'Foto da etiqueta com bobina e contatos, ou conferência visual da linha e dos cabeçalhos no catálogo abaixo. Não é ausência de referência: a associação dos atributos ainda está pendente.':r.necessario??'Conferir alteração concorrente e refazer a comparação antes de gravar.';
 linhas.push(`### ID ${r.id} — ${cel(r.codigo)}`,'',`Descrição atual: **${cel(r.nome_atual)}**.`, '',`Fornecedor: ${cel(r.fornecedor)}. Ativo: ${r.ativo?'sim':'não'}.`, '',`Dúvida: ${motivo}`, '',`O que falta: ${necessario}`, '',`Origem vinculada: ${origens.length?origens.map(cel).join(' / '):'nenhuma descrição de nota localizada nesta fotografia.'}`, '',`Fontes: ${referencias(eventoAnterior??r)}.`, '', 'Sua resposta: ______________________________', '');
}
gravarRelatorio('itens-para-revisar-amanha.md',linhas.join('\n'));
const fila=['# Fila de pesquisa técnica — campanha D-051','',`${pesquisa.length} registros: pesquisa não concluída ou apenas melhoria parcial aplicada. Não classificar como falta de colaboração do usuário e não contar como aprovação técnica.`, '', 'A pesquisa pode confirmar que um nome já está adequado. Não é necessário alterar texto só para marcar revisão. Cabos continuam exigindo formação, seção, tensão, materiais, blindagem e terminação. Um código numérico de fabricante pode ser pesquisável; não é automaticamente inconclusivo.', '', '[Dúvidas para revisão humana](itens-para-revisar-amanha.md). [Alterações verificadas](alteracoes-campanha-051.md).',''];
for(const fornecedor of [...new Set(pesquisa.map(r=>r.fornecedor))].sort((a,b)=>a.localeCompare(b,'pt-BR'))){
 const itens=pesquisa.filter(r=>r.fornecedor===fornecedor);
 fila.push(`## ${cel(fornecedor)} — ${itens.length} itens`, '', '| ID | Código | Descrição atual | Situação | Evidência já disponível |', '| ---: | --- | --- | --- | --- |');
 for(const r of itens)fila.push(`| ${r.id} | ${cel(r.codigo)} | ${cel(r.nome_atual)} | ${r.aplicado?'Melhoria parcial aplicada; validar atributos':'Pesquisa técnica pendente'}${r.alerta_duplicidade?'; possível duplicado':''} | ${cel([...new Set(r.notas.map(n=>n.descricao).filter(t=>t&&!/^ITEM \d+$/.test(t)))].join(' / ')||'Sem descrição de NF complementar; consultar referência e fabricante')} |`);
 fila.push('');
}
gravarRelatorio('fila-pesquisa-campanha-051.md',fila.join('\n'));
const alteracoes=['# Antes e depois — campanha D-051','',`${aplicados.size} itens alterados e relidos. Backup: ${resultado.backup}.`, '', `${resultado.fiscais_preservados} registros de fiscal_itens preservados; todos os campos de itens fora de nome/descrição/grupo (exceto timestamps automáticos) comparados sem divergência nos itens alterados.`, '', 'Melhoria parcial não é revisão técnica concluída. Referências e atributos não confirmados permanecem na fila de pesquisa.', '', '| ID | Código | Antes | Depois | Grupo alterado | Nível |', '| ---: | --- | --- | --- | --- | --- |'];
for(const r of registros.filter(r=>r.aplicado))alteracoes.push(`| ${r.id} | ${cel(r.codigo)} | ${cel(r.nome_antes)} | ${cel(r.nome_atual)} | ${r.alteracoes.grupo_id??'Preservado'} | ${r.situacao==='revisao_tecnica_confirmada'?'Referência e atributos conferidos':'Melhoria parcial'} |`);
alteracoes.push('', '## Fontes das revisões técnicas', '');
for(const r of registros.filter(r=>r.aplicado&&r.fontes.length))alteracoes.push(`- ID ${r.id}: ${referencias(r)}.`);
gravarRelatorio('alteracoes-campanha-051.md',alteracoes.join('\n'));
console.log(JSON.stringify({aplicados:aplicados.size,revisoes_tecnicas:eventos.length,duvidas_humanas:humanos.length,fila_pesquisa:pesquisa.length,contagens},null,2));
