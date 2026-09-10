import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { criterios, familiasNovas006, validarEscopo, impressaoTecnica } from "./controle-revisoes.mjs";
import { normalizarNomeCadastro } from "../../lib/itens/normalizacaoNome.ts";

export const ids003 = [207,208,209,210,211,212,229,230,689,690,691,719,721,722,723,724,726,736,743,746,747,750,755,757,770,774,819,833,946,1028,1030,1031,1032,1033,1034,1035,1036,1037,1038,1039,1040,1080,1086,1087,2742,773,777,1129,1589,1590];
export const ids004 = [1115,1550,1551,1565,1566,1567,1568,1573,1575,1576,1577,1596,1598,1599,1600,1601,1602,1603,1604,1605,1608,1609,1610,1611,1971,2847,2848,2347,2980,2981,3216,3217,3218,3219,3328,186,187,236,243,246,251,252,258,259,742,765,778,798,809,814];
export const assinatura = (obj) => createHash("sha256").update(JSON.stringify(obj)).digest("hex");
export const ids011 = [240,686,944,977,978,2406,1088,1623,2535,1615,1616,1618,735,776,781,789,927,928,957,973,1002,1003,226,227,737,738,744,745,816,2135,922,923,924,925,926,256,346,1628,2450,2455,821,824,1617,1619,2889,2890,2891,2641,2642,2643].sort((a,b)=>a-b);
export const grupos011 = {CONEXOES_PARTIDA:23,ATUADORES_CHAVES_SEGURANCA:28,RELES_INTERFACE:35,ACESSORIOS_RELES_INTERFACE:36,INTERRUPTORES_DR:42,RELES_MONITORAMENTO:45,ACESSORIOS_RELES_SEGURANCA:46,FONTES_ALIMENTACAO:50,ACESSORIOS_INVERSORES:54,UPS_CC:58,TAMPAS_BORNES:72,PENTES_BORNES:73,BORNES_PROTECAO:74,BORNES_PASSAGEM_PLUG_IN:75,CONECTORES_REDE:93};
export const ids010 = [214,215,216,217,218,219,220,221,222,223,224,225,253,254,345,827,828,829,830,834,967,968,969,971,1400,1401,1627,1629,1630,1631,1638,1686,1687,1688,1689,1690,1691,1692,1693,1694,1695,2137,2138,2139,2454,3184,3429,3430,3566,3567];
export const grupos010 = {PULSADORES:6,BOTOES_EMERGENCIA:7,SELETORES:9,BOTOEIRAS_CAIXAS:10,SINALEIROS:11,BLOCOS_CONTATO:12,MODULOS_LED:13,ACESSORIOS_BOTOES:14,CHAVES_SEGURANCA:27};
export const ids009 = [347,348,423,424,425,426,427,428,429,430,431,433,434,435,436,437,438,439,440,441,442,863,1124,1699,1700,1701,1702,1703,1704,1705,1706,1707,1708,1709,1710,1711,1712,1713,1714,1715,1716,3416,3417,3418,3419,3420,3421,3451,3610,3611];
export const grupos009 = {CHAVES_SEGURANCA:27,ATUADORES_CHAVES_SEGURANCA:28,ACESSORIOS_CHAVES_SEGURANCA:29,MODULOS_SEGURANCA_MODULARES:33,SENSORES_FOTOELETRICOS:103,SENSORES_INDUTIVOS:104,SENSORES_TIPO_GARFO:105,CABOS_PARA_SENSORES:106,ACESSORIOS_PARA_SENSORES:108,SENSORES_NIVEL:109,SENSORES_ULTRASSONICOS:110,SENSORES_FLUXO:111,SENSORES_TEMPERATURA:112,SENSORES_PRESSAO:113,ENCODERS:114,CORTINAS_LUZ_SEGURANCA:123,ACESSORIOS_CORTINAS_LUZ:124,CONTROLADORES_SEGURANCA:125,DISPOSITIVOS_HABILITACAO:126};
export const ids007 = [949,970,972,974,1597,3309,1102,1103,1104,1105,1106,2314,1805,1806,2224,2225,2228,1107,1108,1397,1398,1968,2861,1114,1730,1960,1961,2497,2924,1807,1808,1809,2329,2350,1878,1879,1969,2227,2174,2175,2215,2554,2352,2522,3324,2359,3213,3408,1884,636];
export const familiasNovas007 = ["CONTATORES_CAPACITORES", "CONTATORES_SEGURANCA"];
export const ids008 = [190,191,199,200,201,202,203,204,205,727,728,729,730,731,732,831,832,912,913,914,915,931,979,1091,1092,1093,1094,1095,1096,2140,2446,2448,2449,2463,2737,2930,2931,3129,3208,3209,3432,3433,3434,3435,3436,3437,3438,3439,3440,3733];
export const familiasNovas008 = ["CLPS", "MODULOS_DIGITAIS_CLP", "MODULOS_ANALOGICOS_CLP", "MODULOS_SEGURANCA_CLP", "INTERFACES_REMOTAS_CLP", "ACESSORIOS_CLP", "MODULOS_COMUNICACAO_CLP", "IHMS_CLP", "PESAGEM_CLP"];
export const ids005 = [185,749,752,771,794,936,1089,2902,2945,247,753,766,767,796,797,1621,1632,2903,213,245,759,788,180,181,193,748,820,916,1048,1399,2302,2898,250,260,780,782,783,784,799,802,806,810,917,919,956,1125,1542,1547,1626,694];
export const ids006 = [231,720,733,815,935,960,3227,3228,3229,3289,3441,232,734,817,937,942,961,962,963,964,1205,1206,3230,241,257,772,775,791,807,813,3231,228,920,921,953,954,2453,2460,195,196,197,198,237,238,943,2921,687,2136,2991,2992];
export const grupos006 = {DISJUNTORES_CAIXA_MOLDADA:1,ACESSORIOS_CAIXA_MOLDADA:2,DISJUNTORES_ABERTOS:81,CONTATORES:17,MINIDISJUNTORES:3,ACESSORIOS_MINIDISJUNTORES:4,DISJUNTORES_MOTOR:21,DISJUNTORES_PARTIDA_MAGNETICOS:21,BASES_FUSIVEIS_NH:41,FUSIVEIS_NH:40,SECCIONADORAS_FUSIVEIS:82,ACESSORIOS_RELES:25,SECCIONADORAS:38,ACESSORIOS_SECCIONADORAS:39};
export function validarCinquenta(m) {
  validarEscopo(m);
  assert.ok(["003", "004", "005", "006", "007", "008", "009", "010", "011"].includes(m.numero));
  assert.equal(m.itens.length, 50);
  assert.deepEqual(m.itens.map((i) => i.id).sort((a,b) => a-b), ({"003": ids003, "004": ids004, "005": ids005, "006":ids006, "007":ids007, "008":ids008, "009":ids009, "010":ids010, "011":ids011}[m.numero]).slice().sort((a,b) => a-b));
  for (const i of m.itens) {
    validarEscopo(i.antes);
    assert.equal(i.id, i.antes.id);
    assert.equal(i.impressao_antes, impressaoTecnica(i.antes));
    assert.equal(i.criterio, m.numero === "011" && Object.hasOwn(grupos011,i.familia) ? `${i.familia}:proposta011` : m.numero === "010" && Object.hasOwn(grupos010,i.familia) ? `${i.familia}:proposta010` : m.numero === "009" && Object.hasOwn(grupos009,i.familia) ? `${i.familia}:proposta009` : m.numero === "008" && familiasNovas008.includes(i.familia) ? `${i.familia}:proposta008` : m.numero === "007" && familiasNovas007.includes(i.familia) ? `${i.familia}:proposta007` : m.numero === "006" && familiasNovas006.includes(i.familia) ? `${i.familia}:proposta006` : criterios[i.familia]);
    assert.ok(i.criterio && i.antes.ativo && i.antes.grupo_id);
    assert.equal(i.pendencias.length, 0);
    assert.equal(i.nome, normalizarNomeCadastro(i.nome));
    assert.ok(i.nome.length <= 255 && i.nome !== i.antes.nome);
    assert.ok(i.fontes.length && i.fontes.every((f) => new URL(f).protocol === "https:"));
    assert.deepEqual(Object.keys(i.depois).sort(), ["descricao", "nome"]);
    assert.equal(i.depois.nome, i.nome);
    assert.ok(i.depois.descricao.includes(i.descricao_tecnica));
    if (m.numero === "011") {
      assert.equal(i.antes.grupo_id,grupos011[i.familia]);
      assert.equal(i.referencia.replace(/-/g,""),i.antes.codigo_interno.replace(/-/g,""));
      assert.ok(i.descricao_tecnica.includes(i.referencia));
      assert.match(i.evidencia.sha256,/^[a-f0-9]{64}$/);
      assert.equal(i.evidencia.arquivo,`backups/fontes-lote-011/${i.id}.pdf`);
      assert.ok(i.evidencia.paginas.includes(1));
    } else if (m.numero === "010") {
      assert.equal(i.antes.grupo_id,grupos010[i.familia]);
      assert.equal(i.referencia.replace(/-/g,""),i.antes.codigo_interno.replace(/-/g,""));
      assert.ok(i.descricao_tecnica.includes(i.referencia));
      assert.match(i.evidencia.sha256,/^[a-f0-9]{64}$/);
      assert.equal(i.evidencia.arquivo,`backups/fontes-lote-010/${i.id}.pdf`);
      assert.ok(i.evidencia.paginas.includes(1));
      if(i.id===1695) {assert.match(i.nome,/24VCA\/CC/); assert.ok(!i.nome.includes("220V"));}
      if(i.id===2137) assert.match(i.nome,/1NA\+1NF.*SEM LED/);
      if(i.id===3567) assert.match(i.nome,/2000N.*ISO14119/);
    } else if (m.numero === "009") {
      assert.equal(i.antes.grupo_id,grupos009[i.familia]);
      assert.equal(i.antes.fornecedor_id,14);
      assert.match(i.antes.codigo_interno,/^\d+$/);
      assert.ok(i.nome.includes(i.referencia.toUpperCase()));
      assert.ok(i.descricao_tecnica.includes(i.referencia));
      assert.match(i.evidencia.sha256,/^[a-f0-9]{64}$/);
      assert.ok(i.evidencia.arquivo.startsWith("backups/fontes-lote-009/"));
      assert.ok(i.evidencia.paginas.length);
      if(i.id===1708) assert.ok(i.atributos_nao_confirmados.includes("faixa_alimentacao"));
      if([423,424,440,441].includes(i.id)) assert.match(i.nome,/CABO.*M12.*(PUR|PVC)/);
    } else if (m.numero === "008") {
      const grupos = {CLPS:[55,87],MODULOS_DIGITAIS_CLP:[52,53,56,59,86],MODULOS_ANALOGICOS_CLP:[57,60],MODULOS_SEGURANCA_CLP:[61,62,63],INTERFACES_REMOTAS_CLP:[64,65],ACESSORIOS_CLP:[66,67,68,69],MODULOS_COMUNICACAO_CLP:[84,85],IHMS_CLP:[88],PESAGEM_CLP:[83]};
      assert.ok(grupos[i.familia]?.includes(i.antes.grupo_id));
      assert.equal(i.referencia.replace(/-/g,""),i.antes.codigo_interno.replace(/-/g,""));
      assert.ok(i.descricao_tecnica.includes(i.referencia));
      assert.match(i.evidencia.sha256,/^[a-f0-9]{64}$/);
      assert.equal(i.evidencia.arquivo,`backups/fontes-lote-008/${i.id}.pdf`);
      assert.ok(i.evidencia.paginas.includes(1));
      if ([190,3208,2737,2930,2931,3209].includes(i.id)) assert.match(i.nome,/S7-1200 G2/);
      if ([831,931,1094].includes(i.id)) assert.ok(!i.nome.includes("G2"));
      if (i.id === 3733) assert.match(i.nome,/ET200SP.*1510SP F-1PN/);
      if (i.id === 2931) assert.match(i.nome,/8DO RELÉ 2A/);
      if (i.id === 914) assert.match(i.nome,/SB1222.*0,1A.*200kHz/);
      if (i.id === 3440) assert.match(i.nome,/MÓDULO SERVIDOR/);
    } else if (m.numero === "007") {
      const grupos = {...grupos006,ACESSORIOS_DISJUNTORES_MOTOR:22,ACESSORIOS_CONTATORES:19,RELES_SOBRECARGA:24,CONTATORES_CAPACITORES:17,CONTATORES_SEGURANCA:17};
      assert.equal(i.antes.grupo_id, i.id === 2359 ? 38 : grupos[i.familia]);
      assert.ok(i.nome.includes(i.referencia));
      assert.ok(i.descricao_tecnica.includes(i.referencia));
      assert.ok(i.evidencias.length);
      for (const e of i.evidencias) {
        assert.match(e.sha256,/^[a-f0-9]{64}$/);
        assert.ok(e.arquivo.startsWith("backups/fontes-lote-007/"));
      }
      if (i.id === 1884) {
        assert.ok(!i.nome.includes("1000V"));
        assert.ok(i.atributos_nao_confirmados.includes("tensao_1000VCA_historica"));
      }
      if (i.id === 2554) assert.match(i.nome,/100kA EM 690VCA/);
      if (i.id === 3324) assert.match(i.nome,/GERADOR.*280-400A/);
    } else if (m.numero === "006") {
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
  assert.notEqual(m.numero,"011","Lote 011 exige nova aprovação humana; gravação bloqueada");
  if (m.numero === "003") {
    assert.equal(m.autorizacao, "primeiros_50_autorizados_pelo_usuario");
    assert.equal(assinatura(m), "e3c564701791e73c258a4007df905f97e8199505e239a45b1d05db8751facb58");
    return;
  }
  assert.ok(aprovacao, "Lote exige aprovação humana registrada; gravação bloqueada");
  validarEscopo(aprovacao);
  assert.ok(["004", "005", "006", "007", "008", "009", "010"].includes(m.numero));
  assert.equal(aprovacao.lote, m.lote);
  assert.equal(aprovacao.status, "aprovado");
  assert.equal(aprovacao.assinatura_lote, {"004":"8dfcc93fa2471aa24881f22ec41574c889f3b03bd5c7b6ab9996f3f3c7af0a26","005":"e34497cce0e1c0aa7aa59ba8eb97f4efe4cd5caf02fcdfbd0ab09f9d6476d66a","006":"2b7e14820510b475d1d8f1a6027a37527d1ad32b41416c9eeaf5e0fb66ad031d","007":"02b4cdf5f69af22c4c61517a9636b1ab6bf86def926dfad85ebb3f8bf9958aa5","008":"86c374ac97fe7099f31182b085b7d533cb89015861bf670368d7ec14524feb9b","009":"714df3a7c6a7ecd536a4e4be40768b1142f7854d5cd5f7e86f5d1db237d7d87b","010":"6b82344ea80f3e00a8c260b5e4866879cc3850a5aeba56c8b6b32d904d4d2276"}[m.numero]);
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
