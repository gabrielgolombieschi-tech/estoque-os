#!/usr/bin/env node
"use strict";

// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const path = require("path");
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const { spawnSync } = require("child_process");

const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  console.error("DATABASE_URL is required.");
  process.exit(1);
}

const file = path.join(process.cwd(), "supabase", "tests", "xml_import_nf_entrada_xml_integridade.sql");

console.log(`Running DB test: ${path.basename(file)}`);
const res = spawnSync(
  "psql",
  ["--set", "ON_ERROR_STOP=on", "--file", file, "--dbname", dbUrl],
  { stdio: "inherit" }
);

if (res.error) {
  console.error("Failed to run psql:", res.error.message);
  process.exit(1);
}

process.exit(res.status ?? 1);
