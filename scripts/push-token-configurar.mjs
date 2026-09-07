#!/usr/bin/env node
"use strict";

// Gera e instala o segredo compartilhado do despacho de push.
//
// A Edge Function enviar-push-notificacoes so aceita chamadas com
// Authorization: Bearer <PUSH_DISPATCH_TOKEN>, e o job de cron
// enviar-push-notificacoes-1min monta esse header a partir do segredo
// push_dispatch_token do vault. Se o segredo do vault nao existir, o join do
// job devolve zero linhas, nenhum net.http_post e disparado e a fila fica
// parada em "pendente" para sempre — foi exatamente o que aconteceu.
//
// Este script gera um token novo, grava nos dois lugares de uma vez e nunca
// imprime o valor. Rodar de novo troca o token nos dois lados juntos.
//
// Uso: node scripts/push-token-configurar.mjs

import { execFileSync, execSync, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const NOME_SEGREDO_VAULT = "push_dispatch_token";
const NOME_SEGREDO_FUNCTION = "PUSH_DISPATCH_TOKEN";

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

const token = randomBytes(32).toString("base64url");

// O SQL vai por stdin para o token nao aparecer na linha de comando.
const sql = `
set role postgres;
do $$
declare
  v_id uuid;
begin
  select id into v_id from vault.secrets where name = '${NOME_SEGREDO_VAULT}';
  if v_id is null then
    perform vault.create_secret(
      $token$${token}$token$,
      '${NOME_SEGREDO_VAULT}',
      'Bearer da Edge Function enviar-push-notificacoes, usado pelo cron enviar-push-notificacoes-1min.'
    );
  else
    perform vault.update_secret(v_id, $token$${token}$token$);
  end if;
end;
$$;
select count(*) as segredo_instalado from vault.decrypted_secrets where name = '${NOME_SEGREDO_VAULT}';
`;

const psql = spawnSync(
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
    "-q",
    "-v",
    "ON_ERROR_STOP=1",
    "-f",
    "-",
  ],
  { input: sql, stdio: ["pipe", "inherit", "inherit"] }
);
if (psql.status !== 0) {
  console.error("Nao consegui gravar o segredo no vault.");
  process.exit(1);
}

// A CLI le o valor de um arquivo .env temporario, entao o token tambem nao
// aparece nos argumentos deste processo.
const pasta = mkdtempSync(join(tmpdir(), "push-token-"));
const arquivo = join(pasta, ".env");
try {
  writeFileSync(arquivo, `${NOME_SEGREDO_FUNCTION}=${token}\n`, { encoding: "utf8" });
  execFileSync("supabase", ["secrets", "set", "--env-file", arquivo], { stdio: "inherit" });
} catch (err) {
  console.error("Segredo gravado no vault, mas falhou em secrets set:", err.message);
  console.error("Rode de novo depois de resolver — o script troca os dois lados juntos.");
  process.exit(1);
} finally {
  rmSync(pasta, { recursive: true, force: true });
}

console.log(`Token de push instalado no vault (${NOME_SEGREDO_VAULT}) e nos secrets da Edge Function (${NOME_SEGREDO_FUNCTION}).`);
