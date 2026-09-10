import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {tenantId,empresaId,diretorio,validarEscopo,impressaoTecnica,criterios} from './lib/controle-revisoes.mjs';
import {assinatura} from './lib/lotes-cinquenta.mjs';
import {validarLiberacaoClara} from './lib/referencias-claras.mjs';
const base=JSON.parse(fs.readFileSync('backups/base-revisao/2026-09-10T17-44-54-468Z.json','utf8'));validarEscopo(base);
const antes=base.itens.find(i=>i.id===800);validarEscopo(antes);
const referencia='LZS:PT5A5L24';assert.equal(antes.codigo_interno,referencia);assert.equal(antes.grupo_id,35);
const pasta='backups/fontes-complemento-paineis',arquivo=`${pasta}/800.pdf`,fonte=JSON.parse(fs.readFileSync(`${pasta}/800.fonte.json`,'utf8'));
const nome='RELÉ DE INTERFACE SIRIUS LZS COMPLETO ENCAIXÁVEL 4REV BOBINA 24VCC AC-15 4A EM 250VCA DC-13 4A EM 24VCC LED VERMELHO PARAFUSO';
const descricao_tecnica=`Referência Siemens ${referencia}. Conjunto com relé encaixável e base padrão, quatro contatos reversíveis, bobina nominal 24VCC e LED vermelho. Corrente de utilização 4A em 250VCA AC-15 e 4A em 24VCC DC-13; corrente térmica 6A não é capacidade universal de carga. Contatos AgNi90/10, terminais por parafuso, pinagem 3,5mm. Fusível gG6A indicado na ficha para proteção dos contatos. Não atribuir frequência CA à bobina CC. Conferir placa e condições de montagem antes de dimensionar; revisão cadastral não autoriza intervenção elétrica.`;
const descricao=[`Cadastro anterior preservado como histórico:\n${antes.nome}${antes.descricao?`\n${antes.descricao}`:''}`,descricao_tecnica,`Fonte técnica consultada em 2026-09-10:\n${fonte.url}`].join('\n\n');
const m={tenant_id:tenantId,empresa_id:empresaId,numero:'012',lote:'012-referencias-claras',formato:'referencias_claras_v1',decisao:'D-047',data:'2026-09-10',itens:[{id:800,antes,impressao_antes:impressaoTecnica(antes),familia:'RELES_INTERFACE',criterio:criterios.RELES_INTERFACE,referencia,nome,descricao_tecnica,depois:{nome,descricao},fontes:[fonte.url],evidencia:{arquivo,documento:`Ficha oficial Siemens ${referencia}`,paginas:[1,2],sha256:createHash('sha256').update(fs.readFileSync(arquivo)).digest('hex'),...fonte},pendencias:[],atributos_nao_confirmados:[]}]};
const l={tenant_id:tenantId,empresa_id:empresaId,decisao:'D-047',lote:m.lote,assinatura_lote:assinatura(m),ids_claros:[800],retidos:[],exclusoes_adicionais:{},responsavel_conferencia:'Codex: conferência técnica sob autorização condicional D-047, não aprovação humana individual'};
const a=JSON.parse(fs.readFileSync(`${diretorio}/autorizacao-referencias-claras.json`,'utf8'));validarLiberacaoClara(m,l,a);
for(const [f,v] of [[`lote-${m.lote}.json`,m],['liberacao-012-referencias-claras.json',l]]){
 const destino=`${diretorio}/${f}`;if(fs.existsSync(destino))assert.deepEqual(JSON.parse(fs.readFileSync(destino,'utf8')),v);else fs.writeFileSync(destino,JSON.stringify(v,null,2),{flag:'wx'});
}
console.log(JSON.stringify({lote:m.lote,claros:1,assinatura:assinatura(m)}));
