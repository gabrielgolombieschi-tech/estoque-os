import fs from "node:fs";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { tenantId, empresaId, diretorio, criterios, validarEscopo, impressaoTecnica } from "./lib/controle-revisoes.mjs";
import { ids003, ids004, validarCinquenta, assinatura } from "./lib/lotes-cinquenta.mjs";
// Geração local, sem acesso/gravação no ERP. Valores conferidos nas páginas indicadas.
const arquivoBase = "backups/base-revisao/2026-09-07T20-07-20-126Z.json";
const base = JSON.parse(fs.readFileSync(arquivoBase, "utf8"));
validarEscopo(base);
const data = "2026-09-07";
const siemens = "https://www.fegime.pt/images/uploaded/Catalogos/siemens-catalogo-minidisjutores.pdf";
const weg = "https://static.weg.net/medias/downloadcenter/h24/h69/WEG-MDW-MDWH-QDW-SPW-RDW-DWP-50023623-en.pdf";
const ficha = (ref) => `https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${ref}`;
const codigo = (ref) => ref.replace(/[\s-]/g, "");
const pastaFontes = "backups/fontes-lotes-003-004";
const textoSiemens = fs.readFileSync(`${pastaFontes}/siemens-mini.txt`, "utf8").replace(/[\s-]/g, "");
const textoWeg = fs.readFileSync(`${pastaFontes}/weg-mdw.txt`, "utf8");
const fonteHash = (file) => createHash("sha256").update(fs.readFileSync(`${pastaFontes}/${file}.pdf`)).digest("hex");
const historico = JSON.parse(fs.readFileSync(`${diretorio}/historico-informado-grupos.json`, "utf8"));
validarEscopo(historico);
const contatores = {
  773: ["3RT2026-1AK60",25,"110VCA 50Hz / 120VCA 60Hz"],
  777: ["3RT2026-1AN10",25,"220VCA 60Hz"],
  1129: ["3RT2028-1AK60",38,"110VCA 50Hz / 120VCA 60Hz"],
  1589: ["3RT2027-1AK60",32,"110VCA 50Hz / 120VCA 60Hz"],
  1590: ["3RT2036-1AK60",51,"110VCA 50Hz / 120VCA 60Hz"],
};
const motores = {
  186:["3RV2011-1EA10","2,8-4",52,100,100,"PARAFUSO"],
  187:["3RV2011-1CA10","1,8-2,5",33,100,100,"PARAFUSO"],
  236:["3RV2011-1AA20","1,1-1,6",21,100,100,"MOLA"],
  243:["3RV2011-1CA20","1,8-2,5",33,100,100,"MOLA"],
  246:["3RV2011-4AA10","10-16",208,55,30,"PARAFUSO"],
  251:["3RV2011-1FA10","3,5-5",65,100,100,"PARAFUSO"],
  252:["3RV2011-1AA10","1,1-1,6",21,100,100,"PARAFUSO"],
  258:["3RV2011-1BA10","1,4-2",26,100,100,"PARAFUSO"],
  259:["3RV2011-1JA10","7-10",130,100,100,"PARAFUSO"],
  742:["3RV2011-1HA10","5,5-8",104,100,100,"PARAFUSO"],
  765:["3RV2011-1EA20","2,8-4",52,100,100,"MOLA"],
  778:["3RV2011-1GA20","4,5-6,3",82,100,100,"MOLA"],
  798:["3RV2011-1BA20","1,4-2",26,100,100,"MOLA"],
  809:["3RV2011-1GA10","4,5-6,3",82,100,100,"PARAFUSO"],
  814:["3RV2011-1DA10","2,2-3,2",42,100,100,"PARAFUSO"],
};
function preparar(id) {
  const antes = base.itens.find((i) => i.id === id);
  assert.ok(antes && historico.itens.some((h) => h.id === id && h.codigo === antes.codigo_interno && h.grupo_id === antes.grupo_id));
  let nome, descricao_tecnica, familia, referencia, fontes, evidencia, atributos;
  if (contatores[id]) {
    const [ref, corrente, bobina] = contatores[id];
    referencia = ref; familia = "CONTATORES";
    assert.equal(codigo(ref), antes.codigo_interno);
    nome = `CONTATOR 3P AC-3 ${corrente}A EM 400VCA 1NA+1NF BOBINA ${bobina} CONEXÃO POR PARAFUSO`;
    descricao_tecnica = `Referência Siemens ${ref}. Circuito principal: 3 polos, categoria AC-3, ${corrente}A em 400VCA. Auxiliares integrados: 1NA+1NF. Bobina: ${bobina}. Conexão por parafuso. A tensão de 400VCA é a referência da corrente AC-3, não a tensão da bobina. Conferir versão/placa física para dimensionamento.`;
    fontes = [ficha(ref)]; evidencia = { documento: ref, paginas: [1], sha256: fonteHash(ref) };
    atributos = { corrente, bobina, polos: 3, auxiliares: "1NA+1NF", conexao: "PARAFUSO" };
  } else if (motores[id]) {
    const [ref, ajuste, magnetico, icu, ics, conexao] = motores[id];
    referencia = ref; familia = "DISJUNTORES_MOTOR";
    assert.equal(codigo(ref), antes.codigo_interno);
    nome = `DISJUNTOR MOTOR 3P AJUSTE ${ajuste}A CLASSE 10 ICU ${icu}kA EM 400VCA CONEXÃO POR ${conexao}`;
    descricao_tecnica = `Referência Siemens ${ref}, tamanho S00. Proteção termomagnética de motor, 3 polos; ajuste térmico ${ajuste}A; classe de disparo 10; disparo magnético instantâneo ${magnetico}A. Operação 20-690VCA, 50-60Hz. Em 400VCA: Icu ${icu}kA e Ics ${ics}kA, conforme ficha da referência exata. Conexão por ${conexao.toLowerCase()}. Não extrapolar a capacidade de 400VCA para 500VCA ou 690VCA. Dimensionamento/coordenação e eventual proteção de retaguarda dependem da rede e das tabelas do fabricante.`;
    fontes = [ficha(ref)]; evidencia = { documento: ref, paginas: [1,2], sha256: fonteHash(ref) };
    atributos = { ajuste, magnetico, icu, ics, tensao_capacidade: "400VCA", conexao, polos: 3, classe: 10 };
  } else if (antes.codigo_interno.startsWith("5SL")) {
    familia = "MINIDISJUNTORES";
    assert.ok(antes.fabricante == null || antes.fabricante === "SIEMENS", `Fabricante conflitante: ${id}`);
    const m = antes.codigo_interno.match(/^5SL([136])([123])(\d{2})([67])MB$/);
    assert.ok(m && textoSiemens.includes(antes.codigo_interno), `Referência não encontrada na tabela: ${id}`);
    const [, serie, polos, correnteCod, curvaCod] = m;
    const corrente = Number(correnteCod), curva = curvaCod === "6" ? "B" : "C";
    const icn = { 1: "3", 3: "4,5", 6: "6" }[serie];
    const icn127 = serie === "1" ? "5" : serie === "3" ? (corrente <= 25 ? "6" : "5") : "10";
    referencia = antes.codigo_interno.replace(/([67])MB$/, "-$1MB");
    nome = `DISJUNTOR MINI ${polos}P CURVA ${curva} ${corrente}A ICN ${icn}kA EM 220/380VCA`;
    descricao_tecnica = `Referência Siemens ${referencia}, família 5SL${serie}. Minidisjuntor termomagnético, ${polos} polos, curva ${curva}, corrente nominal ${corrente}A. Capacidade Icn conforme NBR NM 60898-1: ${icn}kA em rede 220/380VCA e ${icn127}kA em rede 127/220VCA. Os pares de tensão identificam as condições de rede do catálogo; não são tensão de bobina nem capacidade válida em qualquer tensão. Confirmar aplicação conforme polos, rede e versão física.`;
    fontes = [siemens]; evidencia = { documento: "Catálogo Siemens Minidisjuntores 5SL, 5SY e 5SP (cópia publicada pela Fegime)", paginas_impressas: serie === "1" ? [8,9] : [10,11], sha256: fonteHash("siemens-mini") };
    atributos = { serie: `5SL${serie}`, polos: Number(polos), corrente, curva, icn, tensao_capacidade: "220/380VCA", norma: "NBR NM 60898-1" };
  } else {
    familia = "MINIDISJUNTORES";
    assert.ok(antes.fabricante == null || antes.fabricante === "WEG");
    const padrao = new RegExp(`(MDWP?-C(\\d+)(?:-([234]))?)\\s+(\\d+)\\s*A\\s+C\\s+${antes.codigo_interno}\\b`);
    const m = textoWeg.match(padrao);
    assert.ok(m, `Código sem correspondência documental WEG: ${id}`);
    referencia = m[1]; const corrente = Number(m[2]), polos = Number(m[3] ?? 1), serie = referencia.split("-")[0];
    assert.equal(corrente, Number(m[4]));
    const icn = serie === "MDW" && corrente <= 4 ? "1,5" : "3";
    nome = `DISJUNTOR MINI ${polos}P CURVA C ${corrente}A ICN ${icn}kA EM 230/400VCA ${referencia}`;
    descricao_tecnica = `Código WEG ${antes.codigo_interno}: referência oficial ${referencia}, família ${serie}. Minidisjuntor termomagnético ${polos} polos, curva C, corrente ${corrente}A, 50/60Hz. Icn conforme IEC 60898-1: ${icn}kA em rede 230/400VCA e ${serie === "MDW" && corrente <= 4 ? "1,5" : "5"}kA em rede 127/220VCA. Conexão por parafuso, montagem em trilho DIN 35mm. Não confundir Icn da IEC 60898-1 com Icu da IEC 60947-2 nem aplicar a capacidade sem sua tensão de referência.`;
    fontes = [weg]; evidencia = { documento: "WEG Integrated Solutions for Electrical Installations 50023623", paginas_impressas: serie === "MDW" ? [23,25] : [7,8], sha256: fonteHash("weg-mdw") };
    atributos = { serie, polos, corrente, curva: "C", icn, tensao_capacidade: "230/400VCA", norma: "IEC 60898-1" };
  }
  const descricao = [antes.descricao, descricao_tecnica, `Fontes técnicas consultadas em ${data}:\n${fontes.join("\n")}`].filter(Boolean).join("\n\n");
  return { id, antes, impressao_antes: impressaoTecnica(antes), familia, criterio: criterios[familia], referencia, nome, descricao_tecnica, depois: { nome, descricao }, atributos, fontes, evidencia, pendencias: [] };
}
for (const [numero, ids] of [["003", ids003], ["004", ids004]]) {
  const m = { tenant_id: tenantId, empresa_id: empresaId, numero, lote: `${numero}-cinquenta-itens`, data, responsavel: "Revisão assistida Codex; autorização e aprovação de lotes pelo usuário", autorizacao: numero === "003" ? "primeiros_50_autorizados_pelo_usuario" : "aguardando_aprovacao_humana", base: arquivoBase, itens: ids.map(preparar) };
  validarCinquenta(m);
  const arquivo = `${diretorio}/lote-${m.lote}.json`;
  if (fs.existsSync(arquivo)) assert.deepEqual(JSON.parse(fs.readFileSync(arquivo, "utf8")), m, "Não sobrescrever lote congelado");
  else fs.writeFileSync(arquivo, JSON.stringify(m, null, 2), { flag: "wx" });
  console.log(JSON.stringify({ lote: m.lote, itens: m.itens.length, assinatura: assinatura(m) }));
}
