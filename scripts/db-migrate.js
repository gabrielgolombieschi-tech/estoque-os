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
    if (val === "--from") {
      args.from = argv[i + 1];
      i += 1;
    }
  }
  return args;
}

const { from } = parseArgs(process.argv.slice(2));
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  console.error("DATABASE_URL is required.");
  process.exit(1);
}

const migrationsDir = path.join(process.cwd(), "supabase", "migrations");
if (!fs.existsSync(migrationsDir)) {
  console.error(`Migrations dir not found: ${migrationsDir}`);
  process.exit(1);
}

const files = fs
  .readdirSync(migrationsDir)
  .filter((f) => f.endsWith(".sql"))
  .sort();

const startIndex = from ? files.findIndex((f) => f >= from) : 0;
const list = startIndex >= 0 ? files.slice(startIndex) : files;

if (list.length === 0) {
  console.log("No migrations to apply.");
  process.exit(0);
}

for (const file of list) {
  const fullPath = path.join(migrationsDir, file);
  console.log(`Applying migration: ${file}`);
  const res = spawnSync(
    "psql",
    ["--set", "ON_ERROR_STOP=on", "--file", fullPath, "--dbname", dbUrl],
    { stdio: "inherit" }
  );
  if (res.error) {
    console.error("Failed to run psql:", res.error.message);
    process.exit(1);
  }
  if (res.status !== 0) {
    process.exit(res.status ?? 1);
  }
}

console.log("Migrations applied.");
