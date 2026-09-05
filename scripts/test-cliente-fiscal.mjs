import assert from "node:assert/strict";
import {
  cnpjValido,
  cpfValido,
  documentoFiscalValido,
  validarClienteFiscal,
} from "../lib/nfe/clienteFiscal.ts";

assert.equal(cnpjValido("13.671.448/0001-89"), true);
assert.equal(cnpjValido("13.671.448/0001-88"), false);
assert.equal(cpfValido("529.982.247-25"), true);
assert.equal(cpfValido("111.111.111-11"), false);
assert.equal(documentoFiscalValido("13.671.448/0001-89"), true);

const completo = {
  razao_social: "CLIENTE PILOTO LTDA",
  documento: "13.671.448/0001-89",
  inscricao_estadual: "123456789",
  indicador_ie: "1",
  cep: "89200-000",
  logradouro: "RUA TESTE",
  numero_endereco: "10",
  bairro: "CENTRO",
  cidade: "JOINVILLE",
  uf: "SC",
  codigo_ibge_municipio: "4209102",
};

assert.deepEqual(validarClienteFiscal(completo), []);
assert.equal(
  validarClienteFiscal({ ...completo, indicador_ie: "9", inscricao_estadual: "987654321" }).length,
  0,
  "Não contribuinte pode possuir IE; a presença da IE não muda o indicador.",
);
assert.equal(
  validarClienteFiscal({ ...completo, indicador_ie: "1", inscricao_estadual: null })[0]?.campo,
  "inscricao_estadual",
);
assert.equal(
  validarClienteFiscal({ ...completo, indicador_ie: null, inscricao_estadual: "123456789" })[0]?.campo,
  "indicador_ie",
  "IE preenchida não pode inferir indIEDest.",
);

console.log("cadastro fiscal do cliente: ok");

