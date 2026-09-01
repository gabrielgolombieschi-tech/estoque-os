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
  const supabase = createClient(url, service, { auth: { persistSession: false }, db: { schema: "m" } });

  const { data, error } = await supabase
    .from("pedido_compra_item")
    .select("id, pedido_compra_id, seq, item_id, item_codigo, item_nome, deleted_at")
    .in("item_id", [3691, 3692]);
  console.log("BY_ITEM_ID:", error ? error : JSON.stringify(data, null, 2));

  const { data: item3692, error: e2 } = await supabase
    .schema("public")
    .from("itens")
    .select("id, codigo_interno, nome, tenant_id, empresa_id, ativo, criado_em")
    .in("id", [3691, 3692]);
  console.log("ITENS:", e2 ? e2 : JSON.stringify(item3692, null, 2));
}
main().catch((e) => { console.error(e); process.exit(1); });
