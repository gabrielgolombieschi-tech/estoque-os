#!/usr/bin/env node
// Compara o md5 de pg_get_functiondef() de funcoes do banco local (Docker do supabase start) com o
// online (via scripts/db-query.js, credenciais pela CLI). Uma consulta por lado, nunca uma por funcao.
//
// Uso:
//   node scripts/comparar-funcoes-local-online.mjs "f.fn_x(uuid)" "f.fn_y(text,uuid)"
//   node scripts/comparar-funcoes-local-online.mjs --schema f --prefixo fn_nfe_cancelamento_
//
// Contrato (18/09/2026): qualquer falha (credencial, conexao, consulta, saida fora do formato)
// aborta com exit code diferente de zero e mensagem no stderr. Cada md5 e validado (32 hex) antes de
// comparar: uma linha fora do formato e erro, nao "diferente". Exit 0 = todas iguais; exit 3 = ha
// diferencas; exit 1 = uso/entrada; exit 2 = falha ao consultar um dos lados.
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONTAINER = process.env.LOCAL_PG_CONTAINER || "supabase_db_estoque-os";
const MD5 = /^[0-9a-f]{32}$/;

const args = process.argv.slice(2);
let filtro;
if (args[0] === "--schema") {
  const schema = args[1];
  const iPrefixo = args.indexOf("--prefixo");
  const prefixo = iPrefixo >= 0 ? args[iPrefixo + 1] : "";
  if (!schema || !/^[a-z_]+$/.test(schema) || !/^[a-z0-9_]*$/.test(prefixo)) {
    console.error("Uso: --schema <schema> [--prefixo <inicio_do_nome>] (so letras, numeros e _)");
    process.exit(1);
  }
  filtro = `n.nspname = '${schema}' and p.proname like '${prefixo.replace(/_/g, "\\_")}%'`;
} else {
  const assinaturas = args.filter((a) => /^[a-z_]+\.[a-z0-9_]+\(.*\)$/.test(a));
  if (assinaturas.length === 0 || assinaturas.length !== args.length) {
    console.error('Uso: assinaturas como "f.fn_x(uuid,text)" ou --schema <schema> [--prefixo <inicio>]');
    process.exit(1);
  }
  filtro = `p.oid in (${assinaturas.map((a) => `'${a}'::regprocedure`).join(", ")})`;
}

const consulta =
  "select p.oid::regprocedure::text || '|' || md5(pg_get_functiondef(p.oid)) " +
  "from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
  `where p.prokind = 'f' and ${filtro} order by 1`;

function linhasOuAborta(lado, saida, status, erroTexto) {
  if (status !== 0) {
    console.error(`[${lado}] a consulta falhou (exit ${status}): ${(erroTexto || "").trim().split(/\r?\n/).filter(Boolean).slice(-1)[0] || "sem detalhe"}`);
    process.exit(2);
  }
  const mapa = new Map();
  for (const linha of saida.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)) {
    const sep = linha.lastIndexOf("|");
    const assinatura = sep > 0 ? linha.slice(0, sep) : "";
    const md5 = sep > 0 ? linha.slice(sep + 1) : "";
    if (!assinatura || !MD5.test(md5)) {
      console.error(`[${lado}] linha fora do formato "assinatura|md5(32 hex)": ${linha.slice(0, 160)}`);
      process.exit(2);
    }
    mapa.set(assinatura, md5);
  }
  if (mapa.size === 0) {
    console.error(`[${lado}] nenhuma funcao encontrada para o filtro.`);
    process.exit(2);
  }
  return mapa;
}

const local = spawnSync("docker", ["exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c", consulta], { encoding: "utf8" });
if (local.error) {
  console.error(`[local] falha ao executar docker: ${local.error.message}`);
  process.exit(2);
}
const mapaLocal = linhasOuAborta("local", local.stdout, local.status, local.stderr);

const online = spawnSync(process.execPath, [path.join(RAIZ, "scripts", "db-query.js"), `set role postgres; ${consulta}`, "--raw"], { encoding: "utf8", cwd: RAIZ });
if (online.error) {
  console.error(`[online] falha ao executar db-query.js: ${online.error.message}`);
  process.exit(2);
}
const mapaOnline = linhasOuAborta("online", online.stdout, online.status, online.stderr);

const todas = [...new Set([...mapaLocal.keys(), ...mapaOnline.keys()])].sort();
let diferentes = 0;
for (const assinatura of todas) {
  const l = mapaLocal.get(assinatura);
  const o = mapaOnline.get(assinatura);
  const veredito = !l ? "SO ONLINE" : !o ? "SO LOCAL" : l === o ? "IGUAL" : "DIFERENTE";
  if (veredito !== "IGUAL") diferentes += 1;
  console.log(`${veredito.padEnd(9)} ${assinatura}  local=${l ?? "-"} online=${o ?? "-"}`);
}
console.log(`${todas.length} funcoes comparadas, ${diferentes} com diferenca.`);
process.exit(diferentes === 0 ? 0 : 3);
