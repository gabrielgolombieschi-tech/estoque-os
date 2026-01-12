#!/usr/bin/env node
"use strict";

// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const fs = require("fs");
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const path = require("path");
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Node CLI script uses CJS.
const { spawnSync } = require("child_process");

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const val = argv[i];
    if (val === "--file") {
      args.file = argv[i + 1];
      i += 1;
    }
  }
  return args;
}

const { file } = parseArgs(process.argv.slice(2));
const restoreFile = file || process.env.DB_RESTORE_FILE;
const dbUrl = process.env.DATABASE_URL;

if (!dbUrl) {
  console.error("DATABASE_URL is required.");
  process.exit(1);
}

if (!restoreFile) {
  console.error("Restore file is required. Use --file or DB_RESTORE_FILE.");
  process.exit(1);
}

const isDev =
  process.env.DB_ENV === "dev" ||
  process.env.NODE_ENV === "development" ||
  process.env.ALLOW_DB_RESTORE === "true";
if (!isDev) {
  console.error("Restore is only allowed in dev. Set DB_ENV=dev or ALLOW_DB_RESTORE=true.");
  process.exit(1);
}

const target = path.resolve(restoreFile);
if (!fs.existsSync(target)) {
  console.error(`Restore file not found: ${target}`);
  process.exit(1);
}

const ext = path.extname(target).toLowerCase();
if (ext === ".sql") {
  const res = spawnSync(
    "psql",
    ["--set", "ON_ERROR_STOP=on", "--file", target, "--dbname", dbUrl],
    { stdio: "inherit" }
  );
  if (res.error) {
    console.error("Failed to run psql:", res.error.message);
    process.exit(1);
  }
  process.exit(res.status ?? 0);
}

const res = spawnSync(
  "pg_restore",
  ["--clean", "--if-exists", "--no-owner", "--no-privileges", "--dbname", dbUrl, target],
  { stdio: "inherit" }
);
if (res.error) {
  console.error("Failed to run pg_restore:", res.error.message);
  process.exit(1);
}
process.exit(res.status ?? 0);
