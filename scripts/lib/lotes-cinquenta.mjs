import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { criterios, validarEscopo, impressaoTecnica } from "./controle-revisoes.mjs";
import { normalizarNomeCadastro } from "../../lib/itens/normalizacaoNome.ts";

export const ids003 = [207,208,209,210,211,212,229,230,689,690,691,719,721,722,723,724,726,736,743,746,747,750,755,757,770,774,819,833,946,1028,1030,1031,1032,1033,1034,1035,1036,1037,1038,1039,1040,1080,1086,1087,2742,773,777,1129,1589,1590];
export const ids004 = [1115,1550,1551,1565,1566,1567,1568,1573,1575,1576,1577,1596,1598,1599,1600,1601,1602,1603,1604,1605,1608,1609,1610,1611,1971,2847,2848,2347,2980,2981,3216,3217,3218,3219,3328,186,187,236,243,246,251,252,258,259,742,765,778,798,809,814];
export const assinatura = (obj) => createHash("sha256").update(JSON.stringify(obj)).digest("hex");
export const ids005 = [185,749,752,771,794,936,1089,2902,2945,247,753,766,767,796,797,1621,1632,2903,213,245,759,788,180,181,193,748,820,916,1048,1399,2302,2898,250,260,780,782,783,784,799,802,806,810,917,919,956,1125,1542,1547,1626,694];
export const ids006 = [231,720,733,815,935,960,3227,3228,3229,3289,3441,232,734,817,937,942,961,962,963,964,1205,1206,3230,241,257,772,775,791,807,813,3231,228,920,921,953,954,2453,2460,195,196,197,198,237,238,943,2921,687,2136,2991,2992];
export const grupos006 = {DISJUNTORES_CAIXA_MOLDADA:1,ACESSORIOS_CAIXA_MOLDADA:2,DISJUNTORES_ABERTOS:81,CONTATORES:17,MINIDISJUNTORES:3,ACESSORIOS_MINIDISJUNTORES:4,DISJUNTORES_MOTOR:21,DISJUNTORES_PARTIDA_MAGNETICOS:21,BASES_FUSIVEIS_NH:41,FUSIVEIS_NH:40,SECCIONADORAS_FUSIVEIS:82,ACESSORIOS_RELES:25,SECCIONADORAS:38,ACESSORIOS_SECCIONADORAS:39};
export function validarCinquenta(m) {
  validarEscopo(m);
  assert.ok(["003", "004", "005", "006"].includes(m.numero));
  assert.equal(m.itens.length, 50);
  assert.deepEqual(m.itens.map((i) => i.id).sort((a,b) => a-b), ({"003": ids003, "004": ids004, "005": ids005, "006":ids006}[m.numero]).slice().sort((a,b) => a-b));
  for (const i of m.itens) {
    validarEscopo(i.antes);
    assert.equal(i.id, i.antes.id);
    assert.equal(i.impressao_antes, impressaoTecnica(i.antes));
    assert.equal(i.criterio, criterios[i.familia] ?? (m.numero === "006" && grupos006[i.familia] ? `${i.familia}:proposta006` : undefined));
    assert.ok(i.criterio && i.antes.ativo && i.antes.grupo_id);
    assert.equal(i.pendencias.length, 0);
    assert.equal(i.nome, normalizarNomeCadastro(i.nome));
    assert.ok(i.nome.length <= 255 && i.nome !== i.antes.nome);
    assert.ok(i.fontes.length && i.fontes.every((f) => new URL(f).protocol === "https:"));
    assert.deepEqual(Object.keys(i.depois).sort(), ["descricao", "nome"]);
    assert.equal(i.depois.nome, i.nome);
    assert.ok(i.depois.descricao.includes(i.descricao_tecnica));
    if (m.numero === "006") {
      assert.equal(i.antes.grupo_id, grupos006[i.familia]);
      assert.ok(i.descricao_tecnica.includes(i.referencia));
      assert.match(i.evidencia.sha256, /^[a-f0-9]{64}$/);
      assert.ok(i.evidencia.paginas.length);
      if ([733,2460].includes(i.id)) assert.match(i.nome, /SEM PROTEÇÃO TÉRMICA/);
      if (i.id === 960) assert.match(i.nome, /SEM UNIDADE DE DISPARO/);
      if (i.id === 791) assert.match(i.nome, /4P.*PRINCIPAIS 2NA\+2NF AUX 1NA\+1NF/);
      if ([772,775,813,3231].includes(i.id)) assert.match(i.nome, /POTÊNCIA PARAFUSO COMANDO MOLA/);
      if ([195,196,197,198].includes(i.id)) {
        assert.ok(!i.nome.includes("690V"));
        assert.ok(i.atributos_nao_confirmados.includes("tensao_690VCA_do_cadastro_anterior"));
      }
    } else if (i.familia === "MINIDISJUNTORES") {
      assert.equal(i.antes.grupo_id, 3);
      assert.match(i.nome, /^DISJUNTOR MINI [123]P CURVA [BC] \d+A ICN [\d,]+kA EM \d+\/\d+VCA/);
      assert.match(i.descricao_tecnica, /60898-1/);
      if (/^\d+$/.test(i.antes.codigo_interno)) assert.ok(i.nome.includes(i.referencia));
    } else if (i.familia === "CONTATORES") {
      assert.equal(i.antes.grupo_id, 17);
      assert.match(i.nome, /^CONTATOR 3P AC-3 \d+A EM 400VCA 1NA\+1NF BOBINA (110VCA 50Hz \/ 120VCA 60Hz|220VCA 60Hz) CONEXÃO POR PARAFUSO$/);
    } else if (i.familia === "DISJUNTORES_MOTOR") {
      assert.equal(i.antes.grupo_id, 21);
      assert.match(i.nome, /^DISJUNTOR MOTOR 3P AJUSTE [\d,]+-[\d,]+A CLASSE 10 ICU (20|55|65|100)kA EM 400VCA CONEXÃO POR (MOLA|PARAFUSO)$/);
    } else {
      assert.equal(m.numero, "005");
      const grupos = { CONTATORES_AUXILIARES: 18, RELES_SOBRECARGA: 24, ACESSORIOS_CONTATORES: 19, ACESSORIOS_DISJUNTORES_MOTOR: 22, ACESSORIOS_MINIDISJUNTORES: 4 };
      assert.equal(i.antes.grupo_id, grupos[i.familia]);
      assert.ok(i.descricao_tecnica.includes(i.referencia));
      assert.match(i.evidencia.sha256, /^[a-f0-9]{64}$/);
      if (i.familia === "CONTATORES_AUXILIARES") assert.match(i.nome, /^CONTATOR AUXILIAR [23]NA\+[12]NF BOBINA .* S00 CONEXÃO POR PARAFUSO$/);
      if (i.familia === "RELES_SOBRECARGA") assert.match(i.nome, /^RELÉ (TÉRMICO )?DE SOBRECARGA .*CLASSE 10/);
    }
  }
}

// A aprovação vincula o conteúdo congelado; mudar flag/status não basta.
export function exigirAutorizacao(m, aprovacao = null) {
  validarCinquenta(m);
  assert.notEqual(m.numero, "006", "Lote 006 aguarda aprovação humana; gravação bloqueada");
  if (m.numero === "003") {
    assert.equal(m.autorizacao, "primeiros_50_autorizados_pelo_usuario");
    assert.equal(assinatura(m), "e3c564701791e73c258a4007df905f97e8199505e239a45b1d05db8751facb58");
    return;
  }
  assert.ok(aprovacao, "Lote exige aprovação humana registrada; gravação bloqueada");
  validarEscopo(aprovacao);
  assert.ok(["004", "005"].includes(m.numero));
  assert.equal(aprovacao.lote, m.lote);
  assert.equal(aprovacao.status, "aprovado");
  assert.equal(aprovacao.assinatura_lote, {"004":"8dfcc93fa2471aa24881f22ec41574c889f3b03bd5c7b6ab9996f3f3c7af0a26","005":"e34497cce0e1c0aa7aa59ba8eb97f4efe4cd5caf02fcdfbd0ab09f9d6476d66a"}[m.numero]);
  assert.equal(assinatura(m), aprovacao.assinatura_lote, "Proposta mudou após aprovação");
}

export function planejarCinquenta(m, atuais) {
  validarCinquenta(m);
  assert.equal(atuais.length, 50);
  return m.itens.map((i) => {
    const atual = atuais.find((a) => a.id === i.id);
    assert.ok(atual, `Item ausente: ${i.id}`);
    validarEscopo(atual);
    const aplicado = atual.nome === i.depois.nome && atual.descricao === i.depois.descricao;
    const esperado = aplicado ? { ...i.antes, ...i.depois } : i.antes;
    assert.equal(impressaoTecnica(atual), impressaoTecnica(esperado), `Mudança técnica concorrente: ${i.id}`);
    assert.equal(atual.ativo, i.antes.ativo, `Atividade mudou: ${i.id}`);
    return { item: i, antes: atual, depois: i.depois, aplicado };
  });
}
export function conferirCinquenta(p, retorno) {
  assert.ok(retorno, `Sem retorno: ${p.antes.id}`);
  assert.deepEqual(retorno, { ...p.antes, ...p.depois, atualizado_em: retorno.atualizado_em }, `Campo protegido ou gravação divergente: ${p.antes.id}`);
}
