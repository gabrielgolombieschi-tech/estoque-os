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

function timestamp() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(
    now.getHours()
  )}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

const { file } = parseArgs(process.argv.slice(2));
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  console.error("DATABASE_URL is required.");
  process.exit(1);
}

const backupsDir = path.join(process.cwd(), "backups");
if (!fs.existsSync(backupsDir)) {
  fs.mkdirSync(backupsDir, { recursive: true });
}

const targetFile = file
  ? path.resolve(file)
  : path.join(backupsDir, `backup_${timestamp()}.dump`);

const args = [
  "--format=custom",
  "--no-owner",
  "--no-privileges",
  "--file",
  targetFile,
  "--dbname",
  dbUrl,
];

const res = spawnSync("pg_dump", args, { stdio: "inherit" });
if (res.error) {
  console.error("Failed to run pg_dump:", res.error.message);
  process.exit(1);
}
if (res.status !== 0) {
  process.exit(res.status ?? 1);
}

console.log(`Backup created: ${targetFile}`);
