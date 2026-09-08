import fs from "node:fs";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { tenantId, empresaId, diretorio, criterios, validarEscopo, impressaoTecnica } from "./lib/controle-revisoes.mjs";
import { ids005, validarCinquenta, assinatura } from "./lib/lotes-cinquenta.mjs";
// Proposta local, SEM acesso ao ERP. Atributos conferidos nas fichas exatas.
const arquivoBase = "backups/base-revisao/2026-09-07T22-27-50-622Z.json";
const base = JSON.parse(fs.readFileSync(arquivoBase, "utf8"));
validarEscopo(base);
const historico = JSON.parse(fs.readFileSync(`${diretorio}/historico-informado-grupos.json`, "utf8"));
validarEscopo(historico);
const eventos = fs.readdirSync(diretorio).filter((f) => /^eventos-.*\.json$/.test(f)).flatMap((f) => JSON.parse(fs.readFileSync(`${diretorio}/${f}`, "utf8")));
eventos.forEach(validarEscopo);
const data = "2026-09-07", pasta = "backups/fontes-lote-005";
const motores = {
  185: ["18-25",325,55,25,"S0","PARAFUSO"], 749: ["30-36",432,20,10,"S0","PARAFUSO"],
  752: ["23-28",364,55,25,"S0","MOLA"], 771: ["32-40",585,65,30,"S2","PARAFUSO"],
  794: ["27-32",400,55,25,"S0","MOLA"], 936: ["0,7-1",13,100,100,"S00","PARAFUSO"],
  1089: ["27-32",400,55,25,"S0","PARAFUSO"], 2902: ["9-12,5",163,100,100,"S00","PARAFUSO"],
  2945: ["0,9-1,25",16,100,100,"S00","PARAFUSO"],
};
const reles = {
  247: ["5,5-8","S00","PARAFUSO"], 753: ["9-12,5","S0","PARAFUSO"], 766: ["11-16","S0","PARAFUSO"],
  767: ["0,7-1","S00","PARAFUSO"], 796: ["1,8-2,5","S00","MOLA"], 797: ["7-10","S0","MOLA"],
  1632: ["1,4-2","S00","PARAFUSO"], 2903: ["2,8-4","S0","PARAFUSO"],
};
const auxiliares = {213:["3NA+1NF","24VCC"],245:["3NA+1NF","220VCA 50/60Hz"],759:["2NA+2NF","220VCA 50/60Hz"],788:["2NA+2NF","110VCA 50/60Hz"]};
const blocos = {
  180:["2NA+2NF","PARAFUSO"],181:["1NA+1NF","PARAFUSO"],193:["4NA","PARAFUSO"],
  820:["4NA","MOLA"],1048:["1NF","PARAFUSO"],1399:["4NF","PARAFUSO"],2302:["2NA+2NF","MOLA"],
};
const especificos = {
  1621: ["RELÉ DE SOBRECARGA AJUSTE 1,6-2,5A CLASSE 10A 1NA+1NF PARA 3TS29-32/3TB39-41", "Faixa de ajuste 1,6-2,5A, classe de disparo 10A (a letra A pertence à classe, não indica corrente de 10A), tamanho 0, auxiliares 1NA+1NF. Compatibilidade indicada: 3TS29-32 e 3TB39-41. A ficha resumida não confirma tensão, conexão ou rearme; estes atributos não são inferidos.", ["tensao","conexao","rearme"]],
  748: ["BLOCO DE TERMINAIS TIPO CAIXA ATÉ 120mm² PARA 3RT1/3RB2 S6", "Bloco de terminais tipo caixa para 3RT1/3RB2 tamanho S6; seção máxima indicada 120mm², sujeita à combinação de condutores da ficha. A fonte também cita 3RW505, 3RW443. e 3UF71.3-1BA00-0. Não confundir com tampa isolante simples nem aplicar a qualquer tamanho de contator."],
  2898: ["SUPRESSOR DE SURTO COMBINAÇÃO DE DIODOS 12-250VCC PARA 3RT2.1/3RH2 S00", "Combinação de diodos para supressão da bobina em 12-250VCC; compatível com contatores 3RT2.1 e auxiliares 3RH2, tamanho S00. Montagem por encaixe. Não é varistor, circuito RC nem DPS de alimentação CA."],
  250: ["BLOCO DE CONTATO AUXILIAR TRANSVERSAL 1NA+1NF CONEXÃO POR PARAFUSO PARA 3RV2", "Montagem transversal, 1NA+1NF instantâneos, conexão por parafuso, para disjuntores 3RV2 tamanhos S00/S0/S2/S3. Em AC-15: 0,5A em 230VCA; em DC-13: 1A em 24VCC. Isolação 300V não é tensão de bobina."],
  799: ["BLOCO DE CONTATO AUXILIAR TRANSVERSAL 1NA+1NF CONEXÃO POR MOLA PARA 3RV2", "Montagem transversal, 1NA+1NF instantâneos, conexão por mola, para disjuntores 3RV2 tamanhos S00/S0/S2/S3. Em AC-15: 0,5A em 230VCA; em DC-13: 1A em 24VCC. Isolação 300V não é tensão de bobina."],
  260: ["TERMINAL DE ALIMENTAÇÃO TRIFÁSICO 63A ENTRADA SUPERIOR PARA BARRAMENTO S00/S0 CONEXÃO POR PARAFUSO", "Terminal de alimentação trifásico, entrada superior, tamanho S00/S0, capacidade máxima 63A e tensão de isolação 690V. Condutores: maciços 2,5-16mm², encordoados 2,5-25mm², flexíveis com terminal 2,5-16mm². Isolação não equivale a capacidade de interrupção."],
  956: ["TERMINAL DE ALIMENTAÇÃO TRIFÁSICO TIPO PINO 63A ENTRADA SUPERIOR PARA BARRAMENTO S00/S0", "Terminal de alimentação trifásico tipo pino, entrada superior, S00/S0, conexão por parafuso. Capacidade máxima 63A; isolação 690V. Condutores maciços/encordoados 2,5-25mm²; flexíveis com terminal 4-16mm². Não substituir por terminal tipo garfo por semelhança."],
  780: ["PLUGUE DE POTÊNCIA 3P 32A 500VCA CONEXÃO POR MOLA PARA INFEED 3RV2 S0", "Plugue de conexão de cabos para sistema de alimentação 3RV2, tamanho S0, 3 polos, corrente nominal 32A, tensão nominal 500VCA, conexão por mola, montagem por encaixe. A classificação UL de 600VCA é distinta; não extrapolar corrente/capacidade do conjunto."],
  1125: ["PLUGUE DE POTÊNCIA 3P 16A 500VCA CONEXÃO POR MOLA PARA INFEED S00", "Plugue de conexão de cabos para sistema de alimentação, tamanho S00, 3 polos, corrente nominal/máxima 16A, tensão nominal 500VCA, conexão por mola. A classificação UL de 600VCA é distinta. Não confundir com a variante S0 de 32A."],
  782: ["BARRAMENTO DE EXPANSÃO TRIFÁSICO 63A 500VCA PARA 2 DISJUNTORES 3RV2 S00/S0", "Barramento trifásico de expansão para 2 disjuntores 3RV2 S00/S0, incluindo conector de extensão. Corrente nominal 63A e tensão nominal 500VCA; fixação em trilho DIN 35mm. O número 2 indica dispositivos atendidos, não polos. Capacidade de curto-circuito depende da tabela de montagem do fabricante."],
  783: ["BARRAMENTO DE EXPANSÃO TRIFÁSICO 63A 500VCA PARA 3 DISJUNTORES 3RV2 S00/S0", "Barramento trifásico de expansão para 3 disjuntores 3RV2 S00/S0, incluindo conector de extensão. Corrente nominal 63A e tensão nominal 500VCA; fixação em trilho DIN 35mm. Quantidade de dispositivos não deve ser confundida com polos. Capacidade de curto-circuito depende da tabela de montagem do fabricante."],
  784: ["BARRAMENTO TRIFÁSICO 63A 500VCA ALIMENTAÇÃO À ESQUERDA PARA 2 DISJUNTORES 3RV2 S00/S0", "Barramento de alimentação trifásico para 2 disjuntores 3RV2 S00/S0, alimentação à esquerda, 63A, 500VCA, trilho DIN 35mm. Proteção frontal IP00; IP20 somente nas condições de conexão indicadas na ficha (6mm² flexível com terminal de colar plástico ou seção a partir de 10mm² na alimentação). Não atribuir IP20 incondicionalmente."],
  802: ["BARRAMENTO TRIFÁSICO TIPO GARFO 63A PASSO 45mm PARA 2 DISJUNTORES 3RV2 S00/S0", "Barramento trifásico tipo garfo, corrente nominal 63A, passo modular 45mm, para 2 disjuntores tamanhos S00/S0; aplicação 3RV2 indicada na ficha. Fixação nos terminais por parafuso. Número de disjuntores não significa polos. A ficha consultada não informa tensão operacional: não inferida."],
  806: ["BARRAMENTO TRIFÁSICO TIPO GARFO 63A PASSO 45mm PARA 4 DISJUNTORES 3RV2 S00/S0", "Barramento trifásico tipo garfo, corrente nominal 63A, passo modular 45mm, para 4 disjuntores tamanhos S00/S0; aplicação 3RV2 indicada na ficha. Fixação nos terminais por parafuso. Número de disjuntores não significa polos. A ficha consultada não informa tensão operacional: não inferida."],
  810: ["BARRAMENTO TRIFÁSICO TIPO GARFO 63A PASSO 45mm PARA 3 DISJUNTORES 3RV2 S00/S0", "Barramento trifásico tipo garfo, corrente nominal 63A, passo modular 45mm, para 3 disjuntores tamanhos S00/S0; aplicação 3RV2 indicada na ficha. Fixação nos terminais por parafuso. Número de disjuntores não significa polos. A ficha consultada não informa tensão operacional: não inferida."],
  1542: ["BASE PARA CONTATOR S00/S0 SISTEMA 3RA2 PARTIDA DIRETA/REVERSORA", "Base para montagem de contatores S00/S0 no sistema de alimentação 3RA2, para partidas diretas e reversoras, fixação por encaixe. Dimensões A×L×P: 160×45×63mm. É suporte de montagem, não contator nem módulo eletrônico; não atribuir tensão/corrente de bobina."],
  1547: ["BASE PARA CONTATOR S00 SISTEMA 3RA2 PARTIDA DIRETA/REVERSORA", "Base para contator tamanho S00 com terminais por parafuso ou mola, sistema 3RA2, para partidas diretas e reversoras. A conexão descrita refere-se ao contator compatível, não a uma bobina da base. Não alterar unidade comercial ou multiplicador a partir da embalagem citada na ficha."],
  1626: ["CONECTOR DE EXPANSÃO LARGO 3P 63A 500VCA PARA BARRAMENTOS 3RV2917", "Conector de expansão largo para barramentos trifásicos 3RV2917, com passagem para canaleta a partir de 10mm conforme ficha. 3 polos, corrente nominal 63A, tensão nominal 500VCA, conexão plugável sem bornes. Dimensões A×L×P: 41,7×33×35,8mm. Não traduzir como ultralongo sem dimensão confirmada."],
  694: ["BLOCO DE DISTRIBUIÇÃO 4P 125A 690V CONEXÃO POR PARAFUSO TRILHO DIN", "Bloco de distribuição 4 polos, 125A, tensão nominal 690V, montagem em trilho DIN, conexões por parafuso. Por fase: 1 conexão 6-35mm², 2 conexões 4-16mm² e 5 conexões 1,5-6mm². Neutro: 1 conexão 6-35mm², 6 conexões 4-16mm² e 4 conexões 1,5-10mm². Faixas dependem do tipo de condutor; flexível com terminal limitado a 25mm² na indicação geral."],
  916: ["BORNE DE ALIMENTAÇÃO CURTO ATÉ 25mm² 690VCA PARA BARRAMENTO TIPO PINO", "Borne de alimentação curto para barramento tipo pino, tensão nominal 690VCA. Seções de cobre: maciço/encordoado 6-25mm²; flexível com terminal 4-16mm². O máximo de 25mm² não se aplica indistintamente a todo condutor. Comprimento 38,2mm; torque 1-2N·m."],
  917: ["BLOCO DE DISTRIBUIÇÃO 1P 80A 1000VCA/1500VCC IEC CONEXÃO POR PARAFUSO TRILHO DIN", "Bloco de distribuição 1 polo, 80A, conexões por parafuso, montagem em trilho DIN. Conforme ficha atual: IEC 1000VCA/1500VCC; UL 600VCA/CC. Entradas: 3 conexões 2,5-25mm²; saídas: 4 conexões 2,5-6mm². Flexível com terminal limitado a 16mm² na indicação geral. O cadastro antigo informava 690V: confirmar placa/versão física antes de dimensionar pela ficha atual."],
  919: ["BORNE PARA BARRAMENTO ENTRADA CENTRAL 80A 690VCA/1000VCC IP20", "Borne de conexão com entrada central de cabo, 80A, 690VCA/1000VCC, IP20. Cobre maciço/encordoado 6-25mm²; flexível com terminal 4-16mm². Torque 1-2N·m. Não confundir entrada central com versões de entrada lateral."],
};
const familiasGrupo = {18:"CONTATORES_AUXILIARES",19:"ACESSORIOS_CONTATORES",21:"DISJUNTORES_MOTOR",22:"ACESSORIOS_DISJUNTORES_MOTOR",24:"RELES_SOBRECARGA",4:"ACESSORIOS_MINIDISJUNTORES"};
const itens = ids005.map((id) => {
  const antes = base.itens.find((i) => i.id === id);
  validarEscopo(antes);
  assert.ok(historico.itens.some((i) => i.id === id && i.codigo === antes.codigo_interno && i.grupo_id === antes.grupo_id));
  assert.ok(!eventos.some((e) => e.item_id === id), `Já avaliado: ${id}`);
  assert.ok(antes.fabricante == null || antes.fabricante === "SIEMENS");
  const texto = fs.readFileSync(`${pasta}/${id}.txt`, "utf8");
  const referencia = texto.split(/\r?\n/)[0].replace(/^Data sheet\s+/, "").trim();
  assert.equal(referencia.replace(/[\s-]/g, ""), antes.codigo_interno);
  let nome, conteudo, atributos = {}, paginas = [1], naoConfirmados = [];
  if (motores[id]) {
    const [ajuste, magnetico, icu, ics, tamanho, conexao] = motores[id];
    atributos = { ajuste, magnetico, icu, ics, tamanho, conexao, polos: 3, classe: 10, tensao_capacidade: "400VCA" };
    nome = `DISJUNTOR MOTOR 3P AJUSTE ${ajuste}A CLASSE 10 ICU ${icu}kA EM 400VCA CONEXÃO POR ${conexao}`;
    conteudo = `Proteção termomagnética de motor, 3 polos, tamanho ${tamanho}, faixa térmica ${ajuste}A, classe 10, disparo magnético ${magnetico}A. Operação 20-690VCA, 50-60Hz. Em 400VCA: Icu ${icu}kA e Ics ${ics}kA; conexão por ${conexao.toLowerCase()}. Não extrapolar capacidades para outra tensão. Conferir placa/versão e coordenação antes de dimensionar.`;
    paginas = [1,2];
  } else if (reles[id]) {
    const [ajuste,tamanho,conexao] = reles[id];
    atributos = {ajuste,tamanho,conexao,polos:3,classe:10};
    nome = `RELÉ TÉRMICO DE SOBRECARGA 3P AJUSTE ${ajuste}A CLASSE 10 ${tamanho} CONEXÃO POR ${conexao}`;
    conteudo = `Relé térmico de proteção de motor, 3 polos, ajuste ${ajuste}A, classe de disparo 10, tamanho ${tamanho}, montagem em contator. Circuitos principal e auxiliar com conexão por ${conexao.toLowerCase()}; rearme manual/automático. Tensão operacional nominal 690V, com operação AC-3 indicada na ficha; não é tensão de bobina. Não confundir relé de sobrecarga com disjuntor de proteção contra curto-circuito.`;
  } else if (auxiliares[id]) {
    const [contatos,bobina] = auxiliares[id];
    atributos = {contatos,bobina,tamanho:"S00",conexao:"PARAFUSO"};
    nome = `CONTATOR AUXILIAR ${contatos} BOBINA ${bobina} S00 CONEXÃO POR PARAFUSO`;
    conteudo = `Contator auxiliar de comando, contatos ${contatos}, bobina ${bobina}, tamanho S00, conexão por parafuso. Os contatos descritos são de comando, não polos de potência AC-3. Isolação nominal 690V não substitui a tensão da bobina.`;
  } else if (blocos[id]) {
    const [contatos,conexao] = blocos[id];
    const para = id === 1048 ? "3RT1" : id === 1399 ? "3RT2.1/3RH2" : "3RT2/3RH2";
    const compativel = id === 1048 ? "3RT10, 3RT12, 3RT145, 3RT146 e 3RT147" : id === 1399 ? "3RT2.1 e 3RH2" : "3RT2.1, 3RT2.2, 3RT2.3, 3RT2.4 e 3RH2";
    atributos = {contatos,conexao,compatibilidade:compativel};
    nome = `BLOCO DE CONTATO AUXILIAR FRONTAL ${contatos} AC-15 6A EM 230VCA CONEXÃO POR ${conexao} PARA ${para}`;
    conteudo = `Bloco auxiliar frontal de encaixe, contatos instantâneos ${contatos}, conexão por ${conexao.toLowerCase()}. Compatibilidade listada: ${compativel}. Corrente AC-15: 6A em 230VCA, 3A em 400VCA e 1A em 690VCA. Corrente AC-12 de 10A não equivale à capacidade AC-15; não tratar como contator completo.`;
  } else {
    assert.ok(especificos[id], `Sem proposta: ${id}`);
    [nome, conteudo, naoConfirmados = []] = especificos[id];
  }
  const descricao_tecnica = `Referência Siemens ${referencia}. ${conteudo}`;
  const fontes = [`https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${antes.codigo_interno}`];
  const descricao = [antes.descricao, descricao_tecnica, `Fontes técnicas consultadas em ${data}:\n${fontes.join("\n")}`].filter(Boolean).join("\n\n");
  const familia = familiasGrupo[antes.grupo_id];
  return {id,antes,impressao_antes:impressaoTecnica(antes),familia,criterio:criterios[familia],referencia,nome,descricao_tecnica,depois:{nome,descricao},atributos,fontes,evidencia:{documento:referencia,paginas,sha256:createHash("sha256").update(fs.readFileSync(`${pasta}/${id}.pdf`)).digest("hex")},pendencias:[],atributos_nao_confirmados:naoConfirmados};
});
const m = {tenant_id:tenantId,empresa_id:empresaId,numero:"005",lote:"005-cinquenta-itens",data,responsavel:"Revisão assistida Codex; proposta sujeita à aprovação humana",autorizacao:"aguardando_aprovacao_humana",base:arquivoBase,itens};
validarCinquenta(m);
const destino = `${diretorio}/lote-${m.lote}.json`;
if (fs.existsSync(destino)) assert.deepEqual(JSON.parse(fs.readFileSync(destino,"utf8")),m,"Não sobrescrever proposta congelada");
else fs.writeFileSync(destino,JSON.stringify(m,null,2),{flag:"wx"});
console.log(JSON.stringify({lote:m.lote,itens:itens.length,assinatura:assinatura(m),aplicados:0}));
