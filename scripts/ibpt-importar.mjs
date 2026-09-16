#!/usr/bin/env node
/**
 * Carrega a tabela IBPT ("De Olho no Imposto") em f.ibpt_ncm — fonte do valor aproximado
 * dos tributos da NF-e com indFinal = 1 (Lei 12.741/2012).
 *
 * O arquivo e o CSV oficial por UF (ex.: TabelaIBPTaxSC26.2.A.csv), baixado em
 * https://deolhonoimposto.ibpt.org.br com o CNPJ e o token da empresa. Guardar em
 * dados/ibpt/ (fora do git se preferir) e rodar:
 *
 *   node scripts/ibpt-importar.mjs dados/ibpt/TabelaIBPTaxSC26.2.A.csv            # so confere
 *   node scripts/ibpt-importar.mjs dados/ibpt/TabelaIBPTaxSC26.2.A.csv --apply    # grava
 *
 * So importa o tipo 0 (NCM, 8 digitos); NBS e LC 116 sao de servico. Grava com a
 * service_role de .env.local e mostra o host antes — confira se e o banco certo.
 * Reimportar a mesma versao sobrescreve as linhas dela (chave uf+codigo+ex+versao).
 */
import fs from "node:fs";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const args = process.argv.slice(2);
const arquivo = args.find((a) => !a.startsWith("--"));
const aplicar = args.includes("--apply");
const ufArg = args.find((a) => a.startsWith("--uf="))?.slice(5);
if (!arquivo) {
  console.error("Uso: node scripts/ibpt-importar.mjs <TabelaIBPTaxUF<versao>.csv> [--uf=SC] [--apply]");
  process.exit(1);
}

const nome = path.basename(arquivo);
const uf = (ufArg ?? nome.match(/TabelaIBPTax([A-Z]{2})/i)?.[1] ?? "").toUpperCase();
if (!/^[A-Z]{2}$/.test(uf)) {
  console.error("Nao deu para saber a UF pelo nome do arquivo; informe --uf=SC.");
  process.exit(1);
}

// O IBPT publica em Latin-1; se vier em UTF-8 valido, usa como esta.
const bruto = fs.readFileSync(arquivo);
let texto = bruto.toString("utf8");
if (texto.includes("�")) texto = bruto.toString("latin1");
const linhas = texto.split(/\r?\n/).filter((l) => l.trim());
const cabecalho = linhas.shift().split(";").map((c) => c.trim().toLowerCase());
const col = (n) => {
  const i = cabecalho.indexOf(n);
  if (i < 0) throw new Error(`Coluna ${n} ausente no CSV (cabecalho: ${cabecalho.join(";")}).`);
  return i;
};
const C = Object.fromEntries(
  ["codigo", "ex", "tipo", "descricao", "nacionalfederal", "importadosfederal", "estadual", "municipal",
    "vigenciainicio", "vigenciafim", "chave", "versao", "fonte"].map((n) => [n, col(n)]),
);

const data = (v) => {
  const m = String(v ?? "").trim().match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (!m) throw new Error(`Data invalida: ${v}`);
  return `${m[3]}-${m[2]}-${m[1]}`;
};
const pct = (v) => {
  const n = Number(String(v ?? "").trim().replace(",", "."));
  if (!Number.isFinite(n) || n < 0 || n > 100) throw new Error(`Percentual invalido: ${v}`);
  return n;
};

const registros = [];
for (const linha of linhas) {
  const c = linha.split(";");
  if (String(c[C.tipo]).trim() !== "0") continue;
  const codigo = String(c[C.codigo]).trim();
  if (!/^\d{8}$/.test(codigo)) continue;
  registros.push({
    uf,
    codigo,
    ex: String(c[C.ex] ?? "").trim(),
    descricao: String(c[C.descricao] ?? "").trim() || null,
    nacional_federal_pct: pct(c[C.nacionalfederal]),
    importados_federal_pct: pct(c[C.importadosfederal]),
    estadual_pct: pct(c[C.estadual]),
    municipal_pct: pct(c[C.municipal]),
    vigencia_inicio: data(c[C.vigenciainicio]),
    vigencia_fim: data(c[C.vigenciafim]),
    versao: String(c[C.versao]).trim(),
    chave: String(c[C.chave] ?? "").trim() || null,
    fonte: String(c[C.fonte] ?? "").trim() || "IBPT",
    arquivo: nome,
  });
}
if (registros.length === 0) {
  console.error("Nenhuma linha de NCM (tipo 0) no arquivo.");
  process.exit(1);
}
const versoes = [...new Set(registros.map((r) => r.versao))];
const vigencias = [...new Set(registros.map((r) => `${r.vigencia_inicio} a ${r.vigencia_fim}`))];
console.log(`${nome}: UF ${uf}, ${registros.length} NCMs, versao ${versoes.join("/")}, vigencia ${vigencias.join(" | ")}`);
for (const ncm of ["85364100", "85364900", "85365090", "85371020"]) {
  const r = registros.find((x) => x.codigo === ncm && x.ex === "");
  console.log(`  ${ncm}: ${r ? `federal ${r.nacional_federal_pct}% (imp. ${r.importados_federal_pct}%), estadual ${r.estadual_pct}%` : "ausente"}`);
}
if (!aplicar) {
  console.log("Somente conferencia. Rode com --apply para gravar.");
  process.exit(0);
}

const env = Object.fromEntries(
  fs.readFileSync(".env.local", "utf8").split(/\r?\n/)
    .filter((l) => l.includes("=") && !l.trim().startsWith("#"))
    .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")]; }),
);
const url = env.NEXT_PUBLIC_SUPABASE_URL;
console.log(`Gravando em ${new URL(url).host}`);
const db = createClient(url, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
for (let i = 0; i < registros.length; i += 1000) {
  const lote = registros.slice(i, i + 1000);
  const { error } = await db.schema("f").from("ibpt_ncm").upsert(lote, { onConflict: "uf,codigo,ex,versao" });
  if (error) throw new Error(`Lote ${i / 1000 + 1}: ${error.message}`);
}
const { count, error } = await db.schema("f").from("ibpt_ncm").select("*", { count: "exact", head: true }).eq("uf", uf).in("versao", versoes);
if (error) throw new Error(error.message);
console.log(`Gravado: ${count} linhas da versao ${versoes.join("/")} em f.ibpt_ncm.`);
