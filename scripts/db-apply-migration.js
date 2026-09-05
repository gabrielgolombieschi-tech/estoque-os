#!/usr/bin/env node
"use strict";

// Aplica UMA migration no banco linkado via Supabase CLI.
// Irmao de db-query.js: mesma origem de credencial (CLI ja autenticado, nunca
// .env/.env.local) e mesmo psql do Docker, ja que nao ha psql local nesta maquina.
// A diferenca e que aqui a escrita e permitida — por isso exige caminho de arquivo
// dentro de supabase/migrations e roda com ON_ERROR_STOP.
//
// Uso: node scripts/db-apply-migration.js supabase/migrations/2026...sql

// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const { execSync, spawnSync } = require("child_process");
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const fs = require("fs");
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const path = require("path");

const alvo = process.argv[2];
if (!alvo) {
  console.error("Uso: node scripts/db-apply-migration.js supabase/migrations/<arquivo>.sql");
  process.exit(1);
}

const absoluto = path.resolve(alvo);
const raizMigrations = path.resolve("supabase", "migrations");
if (!absoluto.startsWith(raizMigrations + path.sep) || !absoluto.endsWith(".sql")) {
  console.error("So aplica arquivos .sql de supabase/migrations.");
  process.exit(1);
}
if (!fs.existsSync(absoluto)) {
  console.error(`Migration nao encontrada: ${absoluto}`);
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

console.log(`Aplicando ${path.relative(process.cwd(), absoluto)}...`);

const res = spawnSync(
  "docker",
  [
    "run",
    "--rm",
    "-i",
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
    "-v",
    "ON_ERROR_STOP=on",
    "-f",
    "-",
  ],
  {
    // O usuario do Supabase CLI nao e dono dos schemas (f, public), entao assume
    // postgres antes do arquivo — mesma convencao das consultas em db-query.js.
    // Fica aqui, e nao na migration, para os arquivos seguirem aplicaveis pelo
    // db:migrate normal (que ja conecta como postgres via DATABASE_URL).
    input: Buffer.concat([Buffer.from("set role postgres;\n"), fs.readFileSync(absoluto)]),
    stdio: ["pipe", "inherit", "inherit"],
  }
);

if (res.error) {
  console.error("Falha ao executar docker/psql:", res.error.message);
  process.exit(1);
}
if (res.status === 0) console.log("Migration aplicada.");
process.exit(res.status ?? 1);
