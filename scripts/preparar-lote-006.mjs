import fs from "node:fs";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { tenantId, empresaId, diretorio, criterios, familiasNovas006, validarEscopo, impressaoTecnica } from "./lib/controle-revisoes.mjs";
import { ids006, grupos006, validarCinquenta, assinatura } from "./lib/lotes-cinquenta.mjs";
// Somente geração local de proposta. Nenhuma conexão ou gravação no ERP.
const arquivoBase = "backups/base-revisao/2026-09-09T13-00-31-806Z.json";
const base = JSON.parse(fs.readFileSync(arquivoBase, "utf8"));
validarEscopo(base);
const eventos = fs.readdirSync(diretorio).filter(f => /^eventos-.*\.json$/.test(f)).flatMap(f => JSON.parse(fs.readFileSync(`${diretorio}/${f}`, "utf8")));
eventos.forEach(validarEscopo);
const data = "2026-09-09", pasta = "backups/fontes-lote-006";
const moldados = {
  231:[3,80,25,12,800,"TM210 FTFM"],720:[3,63,25,12,630,"TM210 FTFM"],
  815:[3,100,16,8,1000,"TM210 FTFM"],935:[3,63,16,8,630,"TM210 FTFM"],
  3227:[3,200,18,"13,5",2000,"FTFM"],3228:[3,400,25,"18,75",4000,"FTFM"],
  3229:[2,160,25,"18,75",1600,"FTFM"],3289:[3,160,18,"13,5",1600,"FTFM"],
};
const contatores = {
  241:[185,"2NA+2NF","220-240VCA/CC","S6","BARRAMENTO"],
  257:[115,"2NA+2NF","110-127VCA/CC","S6","BORNE TIPO CAIXA"],
  807:[185,"2NA+2NF","110-127VCA/CC","S6","BARRAMENTO"],
  772:[41,"1NA+1NF","110VCA 50Hz / 120VCA 60Hz","S2","MISTA"],
  775:[95,"1NA+1NF","220VCA 50/60Hz","S3","MISTA"],
  813:[80,"1NA+1NF","24VCA 50/60Hz","S2","MISTA"],
  3231:[110,"1NA+1NF","230VCA 50/60Hz","S3","MISTA"],
};
const motores = {953:["1,4-2",26],954:["2,8-4",52],2453:["0,18-0,25","3,3"]};
const bases = {195:["3",630],196:["2",400],197:["1",250],198:["00",160]};
const especificos = {
  733:["DISJUNTOR CAIXA MOLDADA MAGNÉTICO 3P 160A ICU 55kA EM 415VCA SEM PROTEÇÃO TÉRMICA", "Disparador TM120 M, proteção exclusivamente magnética, sem proteção de sobrecarga. Corrente nominal 160A; ajuste magnético 1120-2560A (7-16In). Em 415VCA: Icu 55kA e Ics 41kA, conforme valores publicados, sem arredondar por proporção.",[1,2]],
  960:["DISJUNTOR CAIXA MOLDADA 3P 250A ICU 36kA EM 415VCA SEM UNIDADE DE DISPARO 3VT2", "Unidade de contatos 3VT2, 3 polos, 250A, fornecida sem disparador eletrônico ETU, sem disparadores auxiliares e sem contatos auxiliares. Não é conjunto completo de proteção. Em 415VCA: Icu 36kA e Ics 18kA; conexões frontais por parafuso. Selecionar ETU compatível separadamente.",[1,2]],
  3441:["DISJUNTOR ABERTO FIXO 3P 1600A ICU 50kA EM 440VCA PROTEÇÃO LSI CONEXÃO TRASEIRA HORIZONTAL", "Disjuntor aberto 3WJ1, montagem fixa, 3 polos, 1600A, 440VCA, 50/60Hz, Icu 50kA em 440VCA. Disparador ETU350WJ com funções LSI; não inferir proteção G. Conexão traseira horizontal. Fechamento mecânico manual; sem motor, bobina de fechamento, disparadores de abertura/subtensão ou contatos auxiliares no fornecimento indicado.",[1]],
  791:["CONTATOR 4P AC-3 41A EM 400VCA PRINCIPAIS 2NA+2NF AUX 1NA+1NF BOBINA 110VCA 50Hz / 120VCA 60Hz CONEXÃO POR PARAFUSO", "Contator SIRIUS S2, 4 polos principais (2NA+2NF), auxiliares 1NA+1NF. Categoria AC-3/AC-3e, 41A em 400VCA conforme ficha exata; bobina 110VCA em 50Hz ou 120VCA em 60Hz. Terminais por parafuso. Não confundir os quatro contatos principais com os auxiliares.",[1]],
  228:["DISJUNTOR MINI 3P CURVA C 63A ICN 15kA EM 400VCA", "Minidisjuntor 3 polos, curva C, corrente nominal 63A, 400VCA, 50/60Hz. Capacidade conforme EN 60898: 15kA. A capacidade de 20kA segundo IEC 60947-2 é classificação distinta, não substitui Icn no nome. IP20 com condutores conectados; corrente admissível varia com temperatura.",[1]],
  2460:["DISJUNTOR MAGNÉTICO PARA PARTIDA 3P 52A ICU 65kA EM 400VCA SEM PROTEÇÃO TÉRMICA CONEXÃO POR PARAFUSO", "Disjuntor 3RV2 tamanho S2 para combinação de partida; 3 polos, corrente nominal 52A, disparo magnético 741A. Proteção de sobrecarga térmica: não, conforme tabela. Em 400VCA: Icu 65kA e Ics 30kA. Terminais por parafuso. A ficha exibe classe 10 mas declara ausência de proteção térmica; não publicar classe térmica ou faixa de ajuste de sobrecarga para este componente.",[1,2]],
  232:["ACIONAMENTO ROTATIVO DE PORTA EMERGÊNCIA IP65 COM INTERTRAVAMENTO PARA 3VM10/11", "Acionamento de porta EMERGENCY OFF, IP65 segundo IEC, com intertravamento de porta. Compatível com disjuntores 3VM10/11. Não é bobina nem unidade de disparo.",[1]],
  734:["ACIONAMENTO ROTATIVO DE PORTA EMERGÊNCIA IP65 COM INTERTRAVAMENTO PARA 3VA15/25/26", "Acionamento rotativo de porta EMERGENCY OFF, IP65 segundo IEC, com intertravamento. Compatibilidade exata 3VA15/25/26; corrente isolada não define compatibilidade mecânica.",[1]],
  817:["MECANISMO ROTATIVO LATERAL ESQUERDO SEM MANOPLA E SEM TRAVA PARA VT160", "Mecanismo lateral esquerdo para VT160, sem trava, com ponta de eixo e sem manopla. Requer eixo adicional, espelho e manopla conforme montagem. Não descrever como kit completo de acionamento.",[1]],
  937:["ACIONAMENTO ROTATIVO LATERAL EMERGÊNCIA IP65 PARA 3VA10/11", "Acionamento rotativo de montagem na parede lateral, EMERGENCY OFF, IP65 segundo IEC. Compatibilidade 3VA10/11. Não confundir com acionamento montado na porta frontal.",[1]],
  942:["ADAPTADOR DE MONTAGEM EM TRILHO DIN PARA DISJUNTOR VT160", "Adaptador de montagem em trilho DIN para disjuntor VT160. A ficha consultada não informa largura do trilho; os 35mm do cadastro anterior ficam como dado histórico não confirmado, sem ampliar compatibilidade por suposição.",[1],["largura_trilho_35mm_do_cadastro_anterior"]],
  961:["UNIDADE DE DISPARO ELETRÔNICA ETU LI 3P IR 250A IRM 4IR PARA VT250", "ETU LP com funções LI para VT250, 3 polos, corrente de sobrecarga Ir 250A e disparo de curto-circuito Irm 4×Ir. É unidade de disparo, não disjuntor completo. A ficha atribui os terminais por parafuso ao fornecimento da unidade de manobra; não presumir incluídos nesta ETU.",[1]],
  962:["MECANISMO ROTATIVO FRONTAL SEM MANOPLA E SEM TRAVA PARA VT250", "Mecanismo frontal para VT250, sem trava, com ponta de eixo, sem manopla. Requer eixo adicional, espelho e manopla. Não é conjunto completo de acionamento.",[1]],
  963:["MANOPLA VERMELHA/AMARELA COM TRAVA PARA VT250/VT630", "Manopla vermelha/amarela com trava, compatível com VT250 e VT630. Não presumir mecanismo, eixo ou espelho incluídos.",[1]],
  964:["ESPELHO FRONTAL PRETO IP66 PARA MANOPLA VT250/VT630", "Espelho frontal preto para manopla dos disjuntores VT250/VT630, grau IP66 informado para esse acessório. A função é espelho frontal (front panel for handle), não acoplador genérico. Não transferir automaticamente IP66 ao painel completo.",[1]],
  1205:["ACIONAMENTO ROTATIVO DE PORTA PADRÃO IP65 COM INTERTRAVAMENTO PARA 3VM10/11", "Acionamento de porta padrão, IP65 segundo IEC, com intertravamento de porta, para 3VM10/11. Distinguir da versão de emergência 3VM9117-0FK25.",[1]],
  1206:["TERMINAL PLANO DE CONEXÃO TRASEIRA PARA 3VM10/11 CONJUNTO 3 PEÇAS", "Terminais planos de conexão traseira para 3VM10/11. A ficha indica conjunto de 3 peças; isso não implica mudança automática da unidade comercial, multiplicador ou quantidade em estoque.",[1]],
  3230:["ACIONAMENTO ROTATIVO DE PORTA PADRÃO IP65 COM INTERTRAVAMENTO PARA 3VJ12 250A", "Acionamento rotativo de porta padrão com 8UC, IP65, intertravamento de porta, compatível com disjuntores 3VJ12 de tamanho construtivo 250A. Corrente do tamanho construtivo não significa capacidade de uma bobina.",[1]],
  943:["CHAVE SECCIONADORA PORTA-FUSÍVEL 3P NH00 160A AC-23B EM 400VCA MONTAGEM EM PLACA", "Seccionadora porta-fusível 3NP1, 3 polos, para NH000/NH00, montagem em placa, terminal plano, nível de cobertura 45mm. Em AC-23B: 160A em 400VCA, 63A em 500VCA e 35A em 690VCA. Em AC-22B: 160A em 400/500VCA e 125A em 690VCA. Corrente publicada a 35°C: 160A; a 40°C: 155A. Não apresentar 160A em 690VCA para qualquer categoria/carga.",[1,2]],
  2921:["SUPORTE DE MONTAGEM INDIVIDUAL PARA RELÉ 3RU21/3RB30/3RB31/3RR2 S0 CONEXÃO POR PARAFUSO", "Suporte de montagem individual para 3RU21, 3RB30, 3RB31 e 3RR2 tamanho S0. Circuito principal com conexão por parafuso; não inclui relé. Fixação por parafuso ou encaixe em trilho DIN 35mm. Não atribuir tensão de bobina ao suporte.",[1]],
  2991:["BLOCO DE CONTATO AUXILIAR 1NA+1NF AC-15 3A EM 230VCA MONTAGEM FRONTAL PARA 3LD3", "Auxiliar frontal para seccionadoras 3LD3, 1NA+1NF, instalável à esquerda e/ou direita. Em AC-15: 6A em 110VCA, 3A em 230VCA e 1,4A em 500VCA; em DC-13: 4A em 24VCC. Terminais por parafuso. O NA fecha depois e abre antes dos contatos principais; NF tem sequência inversa, conforme ficha.",[1]],
  2992:["TAMPA DE PROTEÇÃO DE TERMINAIS 3P PARA CHAVE SECCIONADORA 3LD3", "Tampa de proteção de terminais para 3 polos de contatos de potência de seccionadoras 3LD3. Não é contato auxiliar nem tampa frontal de manopla. Material e grau IP não informados na ficha consultada; não inferidos.",[1],["material","grau_IP"]],
};
const itens = ids006.map(id => {
  const antes = base.itens.find(i => i.id === id);
  validarEscopo(antes);
  assert.ok(!eventos.some(e => e.item_id === id), `Já avaliado: ${id}`);
  assert.ok(antes.ativo && antes.grupo_id);
  const texto = fs.readFileSync(`${pasta}/${id}.txt`,"utf8");
  const referencia = texto.split(/\r?\n/)[0].replace(/^Data sheet\s+/,"").trim();
  assert.equal(referencia.replace(/[\s-]/g,""),antes.codigo_interno);
  let nome, conteudo, paginas = [1], atributos = {}, naoConfirmados = [];
  if (moldados[id]) {
    const [polos,corrente,icu,ics,magnetico,disparador] = moldados[id];
    atributos = {polos,corrente,icu,ics,magnetico,disparador,tensao_capacidade:"415VCA"};
    nome = `DISJUNTOR CAIXA MOLDADA TERMOMAGNÉTICO FIXO ${polos}P ${corrente}A ICU ${icu}kA EM 415VCA`;
    conteudo = `${polos} polos, ${corrente}A; disparador ${disparador}, térmico fixo ${corrente}A e magnético fixo ${magnetico}A. Em 415VCA: Icu ${icu}kA e Ics ${ics}kA. Não extrapolar a capacidade para outra tensão nem substituir Icu por Icn. Valores de Ics transcritos da ficha, sem recalcular por porcentagem.`;
    paginas = id < 3000 ? [1,2] : [1];
  } else if (contatores[id]) {
    const [corrente,auxiliares,bobina,tamanho,conexao] = contatores[id];
    atributos = {corrente,auxiliares,bobina,tamanho,conexao,polos:3};
    const caCc = bobina.includes("CA/CC");
    const ligacao = conexao === "MISTA" ? "POTÊNCIA PARAFUSO COMANDO MOLA" : `POTÊNCIA ${conexao} COMANDO PARAFUSO`;
    nome = `CONTATOR 3P AC-3 ${corrente}A EM 400VCA ${auxiliares} BOBINA ${bobina}${caCc ? " 50/60Hz EM CA" : ""} ${ligacao}`;
    conteudo = `Contator 3 polos, AC-3/AC-3e ${corrente}A em 400VCA, auxiliares ${auxiliares}, tamanho ${tamanho}. Bobina ${bobina}${caCc ? "; 50/60Hz somente na alimentação CA, corrente contínua sem frequência" : ""}. Circuito principal: ${conexao === "MISTA" ? "parafuso" : conexao.toLowerCase()}; circuitos de comando e auxiliares: ${conexao === "MISTA" ? "mola" : "parafuso"}. Não generalizar uma conexão única para todos os circuitos.`;
  } else if (motores[id]) {
    const [ajuste,magnetico] = motores[id];
    atributos = {ajuste,magnetico,polos:3,classe:10,tamanho:"S00",icu:100,ics:100};
    nome = `DISJUNTOR MOTOR 3P AJUSTE ${ajuste}A CLASSE 10 ICU 100kA EM 400VCA CONEXÃO POR PARAFUSO`;
    conteudo = `Proteção termomagnética de motor, 3 polos, S00, ajuste térmico ${ajuste}A, classe 10, disparo magnético ${magnetico}A. Em 400VCA: Icu 100kA e Ics 100kA. Terminais por parafuso. Não extrapolar capacidades para outra tensão.${id === 953 ? " A ficha apresenta valores inconsistentes de Icu/Ics em 500V; essa condição não foi validada nem utilizada na proposta." : ""}`;
    paginas = [1,2];
  } else if (bases[id]) {
    const [tamanho,corrente] = bases[id];
    nome = `BASE PARA FUSÍVEL NH TAMANHO ${tamanho} ${corrente}A VERSÃO TP`;
    conteudo = `Base NH tamanho ${tamanho}, ${corrente}A, versão TP, conforme ficha oficial atual. O cadastro anterior indicava 690VCA; esse valor não consta nas fichas atuais consultadas em inglês e português e NÃO foi confirmado. A proposta retira a tensão do nome, preservando sua origem neste complemento. Confirmar placa ou documentação histórica do fabricante antes de especificar tensão, quantidade de polos e conexão. Revisão parcial, não cadastro tecnicamente completo.`;
    atributos = {tamanho,corrente,versao:"TP"};
    naoConfirmados = ["tensao_690VCA_do_cadastro_anterior","polos","conexao"];
  } else if ([237,238].includes(id)) {
    const [tamanho,corrente,vdc] = id === 237 ? ["2",400,440] : ["00",160,250];
    nome = `FUSÍVEL NH TAMANHO ${tamanho} gG ${corrente}A 500VCA/${vdc}VCC INTERRUPÇÃO 120kA EM CA`;
    conteudo = `Fusível NH${tamanho}, categoria gG, ${corrente}A, 500VCA/${vdc}VCC, contatos tipo lâmina, indicador frontal e garras não isoladas. Capacidade de interrupção conforme IEC 60269: 120kA em CA; 25kA em CC com constante de tempo de até 10ms. Não transferir capacidade CA para CC nem substituir gG por aR/gR.`;
  } else if ([920,921].includes(id)) {
    const lado = id === 920 ? "ESQUERDA" : "DIREITA";
    nome = `BORNE PARA BARRAMENTO ENTRADA À ${lado} 80A 690VCA/1000VCC IP20`;
    conteudo = `Borne de conexão, entrada de cabo à ${lado.toLowerCase()}, 80A, 690VCA/1000VCC, IP20. Cobre maciço/encordoado 6-25mm²; flexível com terminal 4-16mm². Torque 1-2N·m. Não confundir com a variante de entrada central.`;
  } else if ([687,2136].includes(id)) {
    const [corrente,potencia] = id === 687 ? [63,"22"] : [40,"18,5"];
    nome = `CHAVE SECCIONADORA 3P IU ${corrente}A AC-23A ${potencia}kW EM 400VCA MANOPLA VERMELHA/AMARELA FURO 22,5mm`;
    conteudo = `Seccionadora 3LD3, 3 polos, corrente ininterrupta Iu ${corrente}A. Capacidade AC-23A: ${potencia}kW em 400VCA. Tensão operacional nominal 690VCA, 50/60Hz, IP65 frontal. Montagem frontal em furo central 22,5mm, manopla vermelha/amarela 66×66mm. Iu não deve ser confundida com corrente admissível de qualquer categoria e tensão.`;
  } else {
    assert.ok(especificos[id], `Sem proposta ${id}`);
    [nome,conteudo,paginas,naoConfirmados = []] = especificos[id];
  }
  const familia = id === 2460 ? "DISJUNTORES_PARTIDA_MAGNETICOS" : Object.keys(grupos006).find(f => grupos006[f] === antes.grupo_id);
  const descricao_tecnica = `Referência Siemens ${referencia}. ${conteudo}`;
  const fontes = [`https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${antes.codigo_interno}`];
  const descricao = [antes.descricao,descricao_tecnica,`Fontes técnicas consultadas em ${data}:\n${fontes.join("\n")}`].filter(Boolean).join("\n\n");
  return {id,antes,impressao_antes:impressaoTecnica(antes),familia,criterio:familiasNovas006.includes(familia) ? `${familia}:proposta006` : criterios[familia],referencia,nome,descricao_tecnica,depois:{nome,descricao},atributos,fontes,evidencia:{documento:referencia,paginas,sha256:createHash("sha256").update(fs.readFileSync(`${pasta}/${id}.pdf`)).digest("hex")},pendencias:[],atributos_nao_confirmados:naoConfirmados};
});
const m = {tenant_id:tenantId,empresa_id:empresaId,numero:"006",lote:"006-cinquenta-itens",data,responsavel:"Revisão assistida Codex; proposta sujeita à aprovação humana",autorizacao:"aguardando_aprovacao_humana",base:arquivoBase,itens};
validarCinquenta(m);
const destino = `${diretorio}/lote-${m.lote}.json`;
if (fs.existsSync(destino)) assert.deepEqual(JSON.parse(fs.readFileSync(destino,"utf8")),m,"Não sobrescrever proposta congelada");
else fs.writeFileSync(destino,JSON.stringify(m,null,2),{flag:"wx"});
console.log(JSON.stringify({lote:m.lote,itens:itens.length,assinatura:assinatura(m),aplicados:0}));
