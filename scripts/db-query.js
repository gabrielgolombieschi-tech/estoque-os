#!/usr/bin/env node
"use strict";

// Consulta pontual (somente leitura) no banco linkado via Supabase CLI.
// As credenciais sao obtidas na hora, direto do CLI ja autenticado — nunca
// lidas de .env/.env.local nem impressas no terminal.
//
// Uso: node scripts/db-query.js "select ... from public.itens where ...;"

// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const { execSync, spawnSync } = require("child_process");

const sql = process.argv[2];
if (!sql) {
  console.error('Uso: node scripts/db-query.js "select ...;"');
  process.exit(1);
}

const FORBIDDEN = /\b(insert|update|delete|drop|alter|truncate|grant|revoke|create|comment)\b/i;
if (FORBIDDEN.test(sql)) {
  console.error("Este script só executa consultas de leitura (select). Use a migration/CLI normal para alterações.");
  process.exit(1);
}

let dryRun;
try {
  dryRun = execSync("supabase db dump --data-only -s public --dry-run", {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
} catch (err) {
  console.error("Falha ao obter credenciais via Supabase CLI:", err.message);
  process.exit(1);
}

function extract(name) {
  const m = dryRun.match(new RegExp(`export ${name}="([^"]*)"`));
  if (!m) throw new Error(`Nao encontrei ${name} na saida do supabase CLI.`);
  return m[1];
}

// Nao ha psql instalado localmente nesta maquina; usa o cliente do Docker
// (Docker Desktop) so pra essa chamada, sem instalar nada no projeto.
const res = spawnSync(
  "docker",
  [
    "run",
    "--rm",
    "-e",
    `PGPASSWORD=${extract("PGPASSWORD")}`,
    "postgres:16-alpine",
    "psql",
    "-h",
    extract("PGHOST"),
    "-p",
    extract("PGPORT"),
    "-U",
    extract("PGUSER"),
    "-d",
    extract("PGDATABASE"),
    "-X",
    "-q",
    "-c",
    sql,
  ],
  { stdio: ["ignore", "inherit", "inherit"] }
);
if (res.error) {
  console.error("Falha ao executar docker/psql:", res.error.message);
  process.exit(1);
}
process.exit(res.status ?? 1);
