#!/usr/bin/env node
"use strict";

// Consulta pontual (somente leitura) no banco linkado via Supabase CLI.
// As credenciais sao obtidas na hora, direto do CLI ja autenticado — nunca
// lidas de .env/.env.local nem impressas no terminal.
//
// Uso: node scripts/db-query.js "select ... from public.itens where ...;" [--raw]
//
// Contrato de saida (18/09/2026): o stdout so recebe o resultado da consulta. Qualquer
// falha (credencial, docker, psql, erro de SQL) vai para o stderr com mensagem clara e o
// processo termina com exit code diferente de zero — quem captura o stdout nunca recebe
// texto de erro no lugar do resultado. A obtencao de credenciais pela CLI tenta duas vezes.
//   exit 1: uso errado / consulta nao permitida
//   exit 2: credenciais (CLI) ou docker indisponiveis
//   exit 3: a consulta falhou no psql (ON_ERROR_STOP)

// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const { execSync, spawnSync } = require("child_process");

const sql = process.argv[2];
if (!sql) {
  console.error('Uso: node scripts/db-query.js "select ...;" [--raw]');
  process.exit(1);
}

const FORBIDDEN = /\b(insert|update|delete|drop|alter|truncate|grant|revoke|create|comment)\b/i;
if (FORBIDDEN.test(sql)) {
  console.error("Este script só executa consultas de leitura (select). Use a migration/CLI normal para alterações.");
  process.exit(1);
}

function obterCredenciais() {
  const TENTATIVAS = 2;
  let ultimoErro = null;
  for (let tentativa = 1; tentativa <= TENTATIVAS; tentativa += 1) {
    try {
      const dryRun = execSync("supabase db dump --data-only -s public --dry-run", {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      });
      const extract = (name) => {
        const m = dryRun.match(new RegExp(`export ${name}="([^"]*)"`));
        if (!m || !m[1]) throw new Error(`nao encontrei ${name} na saida do supabase CLI`);
        return m[1];
      };
      return {
        PGPASSWORD: extract("PGPASSWORD"),
        PGHOST: extract("PGHOST"),
        PGPORT: extract("PGPORT"),
        PGUSER: extract("PGUSER"),
        PGDATABASE: extract("PGDATABASE"),
      };
    } catch (err) {
      ultimoErro = err;
      if (tentativa < TENTATIVAS) {
        console.error(`Credenciais via Supabase CLI: tentativa ${tentativa} falhou (${resumo(err)}); tentando de novo...`);
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1500);
      }
    }
  }
  console.error(`Falha ao obter credenciais via Supabase CLI (${TENTATIVAS} tentativas): ${resumo(ultimoErro)}`);
  process.exit(2);
}

function resumo(err) {
  const texto = String((err && (err.stderr || err.message)) || err || "erro desconhecido").trim();
  return texto.split(/\r?\n/).filter(Boolean).slice(-1)[0] || "erro desconhecido";
}

const cred = obterCredenciais();

// Nao ha psql instalado localmente nesta maquina; usa o cliente do Docker
// (Docker Desktop) so pra essa chamada, sem instalar nada no projeto.
const res = spawnSync(
  "docker",
  [
    "run",
    "--rm",
    "-e",
    `PGPASSWORD=${cred.PGPASSWORD}`,
    "postgres:16-alpine",
    "psql",
    "-h",
    cred.PGHOST,
    "-p",
    cred.PGPORT,
    "-U",
    cred.PGUSER,
    "-d",
    cred.PGDATABASE,
    "-X",
    "-q",
    "-v",
    "ON_ERROR_STOP=1",
    // --raw: saida sem alinhamento nem cabecalho, para copiar definicoes de
    // funcao sem os marcadores de continuacao do psql.
    ...(process.argv.includes("--raw") ? ["-t", "-A"] : []),
    "-c",
    sql,
  ],
  { stdio: ["ignore", "inherit", "inherit"] }
);
if (res.error) {
  console.error("Falha ao executar docker/psql:", res.error.message);
  process.exit(2);
}
if (res.status !== 0) {
  console.error(`A consulta falhou no psql (exit ${res.status ?? "?"}); veja a mensagem acima.`);
  process.exit(3);
}
process.exit(0);
