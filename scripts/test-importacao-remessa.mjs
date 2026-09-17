import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  bloqueiosDaDir,
  calcularImportacao,
  custoImportacao,
  DirInvalida,
  lerDirRemessa,
} from "../lib/importacao/dir-remessa.ts";

// DIR da remessa UPS 1ZJ451C10441551106 (anonimizada em supabase/tests/fixtures).
const xml = readFileSync(new URL("../supabase/tests/fixtures/dir_remessa_ups.xml", import.meta.url), "utf8");
const dir = lerDirRemessa(xml);

// Leitura.
assert.equal(dir.awb, "1ZJ451C10441551106");
assert.equal(dir.dir.numero, "260191366846");
assert.equal(dir.dir.dataRegistro, "2026-09-09T14:34:00");
assert.equal(dir.dir.versao, "1");
assert.equal(dir.situacao, "25");
assert.equal(dir.manifesto.uaEntrada, "0817700", "UA com o zero a esquerda");
assert.equal(dir.manifesto.paisOrigem, "249");
assert.equal(dir.courier.nome, "UPS DO BRASIL REMESSAS EXPRESSAS LTDA");
assert.equal(dir.courier.cnpj, "74155052000173");
assert.equal(dir.valorUsd, 45);
assert.equal(dir.freteUsd, 41.12);
assert.equal(dir.valorBrl, 228.85);
assert.equal(dir.freteBrl, 209.11);
assert.equal(dir.freteModo, "Collect");
assert.equal(dir.tributavelUsd, 86.12);
assert.equal(dir.tributavelBrl, 437.97);
assert.equal(dir.multasBrl, 0);
assert.equal(dir.cambio, 5.0856);
assert.equal(dir.volumes, 1);
assert.equal(dir.peso, 1);
assert.equal(dir.descricao, "(PLC) CPU UNIT FOR INDUSTRIAL AUTOMATION. J451C1G7HNY", "espacos repetidos viram um");
assert.equal(dir.destinatario.documento, "13671448000189");
assert.equal(dir.destinatario.nome, "ELETRICA SEGAU LTDA");
assert.equal(dir.destinatario.uf, "SC");
assert.equal(dir.remetente.nome, "SHENZHEN COOL DREAM SUPPLY CO LTD");
assert.equal(dir.remetente.logradouro, "SPBALBA402 BLDG CNO27 DAPU 2");
assert.equal(dir.remetente.complemento, "SHENZHEN");
assert.equal(dir.remetente.uf, "EX");
assert.equal(dir.remetente.paisCodigo, "160");
assert.equal(dir.ii.devido, 262.78);
assert.equal(dir.ii.pendente, 0);
assert.equal(dir.ii.recolhido, 262.78);
assert.equal(dir.mercadorias.length, 1);
assert.deepEqual(dir.mercadorias[0], {
  sequencia: "00001", regimeTributacao: "7", valorUsd: 45, moeda: "220", unidadeSiscomex: "11", quantidade: 1, peso: 1,
  descricao: "PLC CPU UNIT FOR INDUSTRIAL AUTOMATION J451C1G7HNY",
});

// Bloqueios.
assert.deepEqual(bloqueiosDaDir(dir, "13.671.448/0001-89"), []);
assert.deepEqual(bloqueiosDaDir(dir, "22222222000191"), ["O destinatário da DIR (CNPJ 13671448000189) não é a empresa emitente (CNPJ 22222222000191)."]);
const dirSituacao = lerDirRemessa(xml.replace("<situacao>25</situacao>", "<situacao>24</situacao>").replace("<valorPendente>0.00</valorPendente>", "<valorPendente>10.50</valorPendente>"));
assert.deepEqual(bloqueiosDaDir(dirSituacao, "13671448000189"), [
  "A remessa está na situação 24; só a situação 25 (desembaraçada) pode gerar a nota de entrada.",
  "Há II pendente de R$ 10,50 na DIR; a nota só sai com o imposto recolhido.",
]);
assert.throws(() => lerDirRemessa("<nfeProc><NFe/></nfeProc>"), DirInvalida);
assert.throws(() => lerDirRemessa("<nfeProc><NFe/></nfeProc>"), /não é uma DIR do Siscomex Remessa/);
assert.throws(() => lerDirRemessa(xml.replace('xmlns="http://www.siscomex.gov.br/remessa/v1"', "")), /namespace/);
assert.throws(() => lerDirRemessa(xml.replace("</remessa>", "</remessa><remessa><numero>X</numero></remessa>")), /2 remessas/);
assert.throws(() => lerDirRemessa(xml.replace("<numero>1ZJ451C10441551106</numero>", "<numero />")), /AWB/);
// BOM e CRLF nao atrapalham.
assert.equal(lerDirRemessa(`﻿${xml.replace(/\n/g, "\r\n")}`).dir.numero, "260191366846");

// Conta da nota: BC ICMS = (437,97 + 262,78) / 0,83 = 844,28; ICMS 143,53; vNF 844,28.
const conta = calcularImportacao({ valorAduaneiro: dir.tributavelBrl, ii: dir.ii.devido, aliquotaIcms: 17, gnre: 143.53 });
assert.deepEqual(conta, {
  valorAduaneiro: 437.97, ii: 262.78, aliquotaIcms: 17, bcIcms: 844.28, icms: 143.53, outrasDespesas: 143.53, valorNota: 844.28,
  gnre: 143.53, diferencaGnre: 0, gnreConfere: true,
});
assert.equal(calcularImportacao({ valorAduaneiro: 437.97, ii: 262.78, aliquotaIcms: 17, gnre: 143.58 }).gnreConfere, true, "5 centavos ainda passa");
assert.equal(calcularImportacao({ valorAduaneiro: 437.97, ii: 262.78, aliquotaIcms: 17, gnre: 143.59 }).gnreConfere, false, "6 centavos bloqueia");
assert.equal(calcularImportacao({ valorAduaneiro: 437.97, ii: 262.78, aliquotaIcms: 17, gnre: 100 }).diferencaGnre, 43.53);
assert.equal(calcularImportacao({ valorAduaneiro: 437.97, ii: 262.78, aliquotaIcms: 17 }).gnre, null);
assert.equal(calcularImportacao({ valorAduaneiro: 437.97, ii: 262.78, aliquotaIcms: 17 }).gnreConfere, false);
assert.equal(calcularImportacao({ valorAduaneiro: 437.97, ii: 262.78, aliquotaIcms: 12 }).bcIcms, 796.31);
assert.equal(calcularImportacao({ valorAduaneiro: 100, ii: 0, aliquotaIcms: 0 }).valorNota, 100);
assert.throws(() => calcularImportacao({ valorAduaneiro: 100, ii: 0, aliquotaIcms: 100 }), /Alíquota/);

// Custo: vProd + II + courier (150,94); o ICMS so entra sem credito (3556/3551).
assert.deepEqual(custoImportacao({ valorAduaneiro: 437.97, ii: 262.78, icms: 143.53, courier: 150.94, creditoIcms: true, quantidade: 1 }), { total: 851.69, unitario: 851.69 });
assert.deepEqual(custoImportacao({ valorAduaneiro: 437.97, ii: 262.78, icms: 143.53, courier: 150.94, creditoIcms: false, quantidade: 1 }), { total: 995.22, unitario: 995.22 });
assert.deepEqual(custoImportacao({ valorAduaneiro: 437.97, ii: 262.78, icms: 143.53, courier: 150.94, creditoIcms: true, quantidade: 4 }), { total: 851.69, unitario: 212.9225 });

console.log("58 cenarios do parser da DIR e da conta da importacao passaram.");
