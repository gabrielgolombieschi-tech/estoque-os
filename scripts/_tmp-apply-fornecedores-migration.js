#!/usr/bin/env node
"use strict";

// Aplica UMA migration especifica usando credenciais frescas do Supabase CLI
// (mesma extracao do db-query.js), pois o DATABASE_URL do .env esta com senha
// desatualizada. Nao le nem imprime segredos além do necessário para a chamada.

const { execSync, spawnSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const migrationFile = path.join(
  process.cwd(),
  "supabase",
  "migrations",
  "20260901130000_fornecedores_unicidade_por_empresa.sql"
);

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
    "--set",
    "ON_ERROR_STOP=on",
    "-h",
    extract("PGHOST"),
    "-p",
    extract("PGPORT"),
    "-U",
    extract("PGUSER"),
    "-d",
    extract("PGDATABASE"),
  ],
  { stdio: ["pipe", "inherit", "inherit"], input: fs.readFileSync(migrationFile) }
);

process.exit(res.status ?? 1);
