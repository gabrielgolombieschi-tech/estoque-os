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
  if (!url || !service) throw new Error("Missing env vars");

  const supabase = createClient(url, service, { auth: { persistSession: false }, db: { schema: "m" } });

  const { data: pedido, error: pedidoErr } = await supabase
    .from("pedido_compra")
    .select("id, codigo, status")
    .eq("codigo", "PC-SEG-00300-026")
    .maybeSingle();
  console.log("PEDIDO:", pedidoErr ? pedidoErr : pedido);

  if (pedido?.id) {
    const { data: itens, error: itensErr } = await supabase
      .from("pedido_compra_item")
      .select("id, seq, item_id, item_codigo, item_nome, deleted_at")
      .eq("pedido_compra_id", pedido.id)
      .order("seq");
    console.log("ITENS:", itensErr ? itensErr : JSON.stringify(itens, null, 2));
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
