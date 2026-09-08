import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { tenantId, empresaId } from "./lib/controle-revisoes.mjs";
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => {
  const p = l.indexOf("="); return [l.slice(0, p).trim(), l.slice(p + 1).trim().replace(/^(["'])(.*)\1$/, "$2")];
}));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
async function consultar(tabela) {
  const linhas = [];
  for (let inicio = 0; ; inicio += 1000) {
    const { data, error } = await db.from(tabela).select("*").eq("tenant_id", tenantId).eq("empresa_id", empresaId).order("id").range(inicio, inicio + 999);
    if (error) throw new Error(error.message);
    linhas.push(...data);
    if (data.length < 1000) return linhas;
  }
}
const [itens, grupos] = await Promise.all([consultar("itens"), consultar("item_grupos")]);
const data = new Date().toISOString();
fs.mkdirSync("backups/base-revisao", { recursive: true });
const arquivo = `backups/base-revisao/${data.replace(/[:.]/g, "-")}.json`;
fs.writeFileSync(arquivo, JSON.stringify({ tenant_id: tenantId, empresa_id: empresaId, capturado_em: data, itens, grupos }, null, 2), { flag: "wx" });
console.log(JSON.stringify({ arquivo, itens: itens.length, com_grupo: itens.filter((i) => i.grupo_id != null).length, grupos: grupos.length }));
