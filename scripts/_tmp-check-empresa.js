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
  const baseDir = process.cwd();
  loadEnvFile(".env", baseDir);
  loadEnvFile(".env.local", baseDir);
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const supabase = createClient(url, service, { auth: { persistSession: false } });
  const { data, error } = await supabase.schema("c").from("empresa")
    .select("id, codigo, razao_social, nome_fantasia")
    .in("id", ["de04c78a-4fed-4118-8661-52163f93bc8b", "f0e74f49-a127-46b4-901b-f7b37e43c690"]);
  console.log(error ? error : JSON.stringify(data, null, 2));
}
main().catch((e) => { console.error(e); process.exit(1); });
