/* eslint-disable @typescript-eslint/no-require-imports */
const { createClient } = require("@supabase/supabase-js");
const fs = require("fs");
const path = require("path");

function loadEnvFile(fileName, baseDir) {
  const file = path.join(baseDir, fileName);
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*=/.test(line)) continue;
    const idx = line.indexOf("=");
    const key = line.slice(0, idx).trim();
    if (process.env[key]) continue;
    const value = line.slice(idx + 1).trim().replace(/^"|"$/g, "");
    process.env[key] = value;
  }
}

async function main() {
  const baseDir = "c:\\Users\\gabri\\Dropbox\\Projeto_Estoque\\estoque-os";
  loadEnvFile(".env", baseDir);
  loadEnvFile(".env.local", baseDir);

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !service) throw new Error("Missing env vars");

  const supabase = createClient(url, service, { auth: { persistSession: false } });

  const { data, error } = await supabase
    .from("ordens_servico")
    .select("id, numero_os, os_num, tipo_documento, tenant_id, empresa_id, status, cliente_nome")
    .or("id.in.(340,341,342,343,344,345,346),numero_os.in.(342,343,344)")
    .order("id");

  if (error) {
    console.error("ERROR", error);
    process.exit(1);
  }
  console.log(JSON.stringify(data, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
