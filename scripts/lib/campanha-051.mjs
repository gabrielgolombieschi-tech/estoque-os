import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {normalizarNomeCadastro} from '../../lib/itens/normalizacaoNome.ts';
import {validarEscopo} from './controle-revisoes.mjs';

export const caminhoBase051='backups/campanha-051/base-2026-09-10T21-45-48-288Z.json';
export const camposPermitidos051=['nome','descricao','grupo_id'];
export const fonteBrm='https://brm.com.br/wp-content/uploads/2025/06/Catalogo-BRM-Outubro-2023_compressed.pdf';
export const fonteCwb='https://www.weg.net/catalog/weg/US/en/Controls/Contactors/Power-contactors/CWB---Contactors/CONTACTOR-CWB18-11-30D02/p/12660806';
export const fonteSkf='https://www.emarketplace.in.skf.com/industrial/bearings?search=608-RSH';
export const fonteZb='https://loja.ciser.com.br/p/elementos-de-fixacao/barras/barra-roscada-unc-rosca-inteira-ac-1-4-x-1000-zincado-branco-24215101';
export const hash051=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
export const semAcento=v=>String(v??'').normalize('NFD').replace(/\p{Diacritic}/gu,'').toUpperCase();

// Expansões fechadas. Não deduzir material, passo de rosca, classe ou comprimento.
export function melhorarRedacao051(valor){
 let n=normalizarNomeCadastro(String(valor??'').replace(/&QUOT;/gi,'"').replace(/&NBSP;/gi,' '));
 n=n.replace(/\s*(?:CC:\s*)?OC\s*:?\s*\d+\s*$/i,'').trim();
 const mec=/^(PARAF(?:USO)?\b|PORCA\b|ARRUELA\b|BARRA ROSCADA\b|MACHO\b|BROCA\b|TB[. ]|TUBO\b|ABRACADEIRA\b|CHAVETA\b)/i.test(n);
 const pares=[
  [/^PARAF\b\.?\s*/i,'PARAFUSO '], [/^MACHO MAQ(?:UINA)?\b\.?\s*/i,'MACHO DE MÁQUINA '],
  [/^TB\.?\s*RED\.?\s+/i,'TUBO REDONDO '],[/^TB\.?\s*QD\.?\s+/i,'TUBO QUADRADO '],[/^TB\.?\s*RET\.?\s+/i,'TUBO RETANGULAR '],
  [/^ABRACADEIRA\b/i,'ABRAÇADEIRA'],[/^ARRUELA PRESSAO\b/i,'ARRUELA DE PRESSÃO'],
  [/^BROCA HELIC\.?\s*/i,'BROCA HELICOIDAL '],
  [/^TUBO RED\b\.?\s*/i,'TUBO REDONDO '],[/^TUBO (?:QD|QUAD)\b\.?\s*/i,'TUBO QUADRADO '],[/^TUBO (?:RET|RT)\b\.?\s*/i,'TUBO RETANGULAR '],
  [/^REDONDO (?=\d{4} (?:TREFILADO|LAMINADO))/i,'BARRA REDONDA '],
  [/^ABRAC\b\.?\s*/i,'ABRAÇADEIRA '],[/^ARMARIO\b/i,'ARMÁRIO'],
  [/^BROCA HSS\b/i,'BROCA DE AÇO RÁPIDO HSS'],
 ];
 for(const [re,texto] of pares)n=n.replace(re,texto);
 if(mec){
  n=n.replace(/\b(PARAFUSO|PORCA)\s+(SX|SEXTAV|SEXT)\b\.?\s*/gi,(_,t)=>`${t} ${t==='PORCA'?'SEXTAVADA':'SEXTAVADO'} `)
   .replace(/\bS\/\s*CAB\.(?:\s*)/gi,'SEM CABEÇA ').replace(/\bCAB\.\s*CILIND\.?\b\.?/gi,'CABEÇA CILÍNDRICA')
   .replace(/\bCAB\.\s*CHATA\b/gi,'CABEÇA CHATA').replace(/\bPONTA CONC\b\.?/gi,'PONTA CÔNCAVA')
   .replace(/\bZB\b/g,'ACABAMENTO ZINCADO BRANCO').replace(/\b(?:ZINC|ZNC)\.(?=\s|\(|$)/g,'ACABAMENTO ZINCADO ')
   .replace(/\bM\s+(\d)/g,'M$1');
  // RI/RP são expandidos apenas em roscas de fixadores, nunca em referências elétricas.
  if(/^(PARAFUSO|BARRA ROSCADA)\b/.test(n))n=n.replace(/\bRI\b/g,'ROSCA INTEIRA').replace(/\bRP\b/g,'ROSCA PARCIAL');
  if(/^PORCA\b/.test(n))n=n.replace(/\bCL\s?(\d+)\b/g,'CLASSE $1');
  if(/^PARAFUSO\b/.test(n)&&/DIN (?:912|916|931|933|7991)\b/.test(n)){
   n=n.replace(/\((5\.8|8\.8|10\.9|12\.9)\)/g,'CLASSE $1')
    .replace(/(DIN (?:912|916|931|933|7991)) (5\.8|8\.8|10\.9|12\.9)\b/g,'$1 CLASSE $2');
  }
 }
 // Referência comercial preservada; só trazer a função já escrita para o início.
 n=n.replace(/^(EL\s+\d+[A-Z0-9-]*)\s+(.+)$/i,'$2 $1');
 return n.replace(/\s+/g,' ').trim();
}

export function grupoMecanico051(nome){
 const n=semAcento(nome);
 if(/^(PARAFUSO|PORCA (?:SEXTAVADA|CALOTA|INOX|T\b)|BARRA ROSCADA|PINO ELASTICO|REBITE)\b/.test(n)&&/\d/.test(n)&&!/(CHAVE|KIT.*CORDA|TENSIONADOR)/.test(n))return 142;
 if(/^ARRUELA (?:DE PRESSAO|LISA)\b/.test(n))return 154;
 if(/^MACHO (?:DE MAQUINA|MANUAL)\b/.test(n))return 175;
 if(/^BROCA\b/.test(n))return 174;
 if(/^TUBO REDONDO INOX\b/.test(n))return 149;
 return null;
}

export const revisoesExatas051=new Map([
 [3817,{nome:'CONTATOR 3P AC-3 18A EM 400VCA 1NA+1NF BOBINA 24VCA 50/60Hz CONEXÃO POR PARAFUSO CWB18-11-30D02',familia:'CONTATORES',fontes:[fonteCwb,'https://static.weg.net/medias/downloadcenter/hb6/h0a/WEG-contatores-CWB-50042424-pt.pdf'],complemento:'Referência WEG CWB18-11-30D02 identificada na NF vinculada. Bobina CA D02: 24VCA, 50/60Hz; o nome anterior indicava incorretamente VCC. Corrente AC-3 de 18A em até 440VCA (inclui 400VCA), conforme catálogo CWB. Não representa alimentação da bobina em 400VCA.'}],
 [3816,{nome:'ROLAMENTO RÍGIDO DE ESFERAS 608-2RSH 8X22X7mm',familia:'ROLAMENTOS_CATALOGO',fontes:[fonteSkf],complemento:'Fabricante SKF identificado na NF vinculada: 608-2RSH. Dimensões do catálogo SKF: diâmetro interno 8mm, externo 22mm e largura 7mm. Folga, capacidade de carga e equivalência com outros sufixos não certificadas nesta revisão.'}],
 [3813,{nome:'ARMÁRIO INDUSTRIAL ZK2L 1200X2200X600mm (LXAXP) RAL7035 IP55',familia:'GABINETES_DOCUMENTADOS',fontes:[],complemento:'Dimensões, ordem largura x altura x profundidade, linha ZK2L, RAL7035 e IP55 transcritos do cadastro e da nota vinculada. Composição informada na origem: perfil ZN, olhais, placa de montagem ZN. Material da caixa e alcance do fornecimento ainda não confirmados.',parcial:true}],
]);

for(const [id,ref,dim] of [[1122,'1045000','400X500X210'],[1123,'1050000','500X500X210'],[2229,'1058000','600X800X250'],[2492,'1076000','600X760X210'],[2780,'1054000','600X600X250']]){
 revisoesExatas051.set(id,{nome:`ARMÁRIO COMPACTO AX ${ref} AÇO CARBONO ${dim}mm (LXAXP) 1 PORTA IP66 RAL7035 COM PLACA DE MONTAGEM`,familia:'GABINETES_CATALOGO',grupo_id:168,fontes:[`https://www.rittal.com/ca-en/products/PG20231215SCH101/PG20231512SCH301/PRO70743?variantId=${ref}`],complemento:`Referência Rittal AX ${ref} confirmada individualmente. Caixa e porta de aço carbono, vedação em PU, placa de montagem zincada. Dimensões externas na ordem largura x altura x profundidade. Grau IP66 do gabinete padrão conforme EN 60529; perfurações, ventilação ou adaptações posteriores podem alterar o grau de proteção. Não presumir acessórios adicionais.`});
}

// A identidade e a montagem destes IDs foram conferidas nas NFs e no catálogo BRM.
for(const [id,tipo,tamanho,ref,pagina] of [
 [1480,'TENSOR',205,'UCT205',86],[3109,'FLANGE QUADRADA 4 FUROS',205,'UCF205',45],
 [3674,'DE APOIO 2 FUROS',206,'UCP206',23],[3717,'FLANGE OVAL 2 FUROS',210,'UC210 + FL210',70],
 [3719,'FLANGE QUADRADA 4 FUROS',209,'UC209 + F209',45],[3720,'FLANGE QUADRADA 4 FUROS',205,'UC205 + F205',45],
 [3721,'DE APOIO 2 FUROS',206,'UC206 + P206',23],[3814,'DE APOIO 2 FUROS',210,'UCP210',23],
 [3815,'FLANGE OVAL 2 FUROS',210,'UC210 + FL210',70],
]){
 const d={205:25,206:30,209:45,210:50}[tamanho];
 revisoesExatas051.set(id,{nome:`MANCAL COMPLETO ${tipo} EIXO ${d}mm CAIXA FERRO FUNDIDO ${ref}`,grupo_id:176,familia:'MANCAIS_CATALOGO',fontes:[`${fonteBrm}#page=${pagina}`],complemento:`Referência BRM ${ref}, confirmada na nota vinculada. Catálogo BRM, página PDF ${pagina}: tipo de caixa e diâmetro nominal do eixo ${d}mm. Conjunto inclui rolamento UC${tamanho}; não confundir caixa avulsa com mancal completo. Quantidade de componentes não altera unidade nem fator de estoque. Versões com tampas, inox ou alta temperatura não foram presumidas.`});
}

export const impedimentosExatos051=new Map([
 [1612,{motivo:'Conflito de identidade: o cadastro diz DISJUNTOR 3P C100 MDW; a nota vinculada diz SALVA DEDO DE PROTECAO PARA POLIA DE 230.',necessario:'Foto do item/etiqueta ou documento que esclareça se o código 2338 identifica o disjuntor ou a proteção mecânica. Nenhum dos textos será escolhido automaticamente.'}],
 [2908,{motivo:'Nome CP420 e categoria RELÉ, mas o código WEG 14810513 corresponde no catálogo oficial ao módulo MOD5.00-4RTD. Sem NF vinculada para desempatar.',necessario:'Foto da etiqueta e confirmação de qual item físico pertence a este cadastro. Se for MOD5.00-4RTD, corrigir também a classificação; não transformar um relé em módulo por suposição.',fontes:['https://www.weg.net/catalog/weg/BI/pt/compare/14810513']}],
 [3807,{motivo:'CARRO OBR-A-15E não informa desenho, aplicação, dimensões nem fabricante; sem NF vinculada que identifique a construção.',necessario:'Desenho ou foto e identificação da máquina/conjunto. Informar as dimensões relevantes.'}],
 [2491,{motivo:'O nome informa AX 800X800X300mm, mas a referência Rittal 1280000 possui dimensões oficiais 800X1200X300mm (LXAXP).',necessario:'Conferir etiqueta e altura física: 800mm ou 1200mm. Definir se está errado o nome ou o código antes de substituir a dimensão.',fontes:['https://www.rittal.com/ca-en/products/PG20231215SCH101/PG20231512SCH301/PRO70743?variantId=1280000']}],
]);

export function conferirPreservacao051(antes,depois,patch){
 validarEscopo(antes);validarEscopo(depois);
 assert.ok(Object.keys(patch).every(c=>camposPermitidos051.includes(c)),'Campo não permitido');
 assert.deepEqual(Object.keys(depois).sort(),Object.keys(antes).sort(),'Schema alterado');
 for(const [c,v] of Object.entries(antes)){
  if(['updated_at','atualizado_em'].includes(c))continue;
  assert.deepEqual(depois[c],Object.hasOwn(patch,c)?patch[c]:v,`Campo divergente: ${c}, item ${antes.id}`);
 }
}
