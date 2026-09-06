/**
 * Formaliza na OS que o atendimento foi conserto isolado de equipamento com
 * defeito, sem contrato continuo (IN RFB 2.141/2023, art. 2, §2, II): grava a
 * marca conserto_isolado e acrescenta a justificativa nas observacoes da OS.
 * E o "escudo juridico" pedido pelo contador em 06/09/2026 para as NFS-e 14.01
 * emitidas sem CRF (notas 31 = OS 291, 32 = OS 248). Decisao humana: o script
 * so grava o que for informado.
 *
 *   node scripts/os-marcar-conserto-isolado.mjs <os_id> "<justificativa>"
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
for (const arquivo of [".env.local", ".env.e2e.local"]) {
  const caminho = path.join(raiz, arquivo);
  if (!fs.existsSync(caminho)) continue;
  for (const linha of fs.readFileSync(caminho, "utf8").split(/\r?\n/)) {
    const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "");
  }
}
const [osIdArg, justificativa] = process.argv.slice(2);
const osId = Number(osIdArg);
if (!osId || !justificativa || justificativa.trim().length < 15) {
  console.error("Uso: node scripts/os-marcar-conserto-isolado.mjs <os_id> \"<justificativa com 15+ caracteres>\"");
  process.exit(1);
}

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: os, error: osError } = await supabase.from("ordens_servico").select("id,numero_os,cliente_nome,conserto_isolado,observacoes").eq("id", osId).maybeSingle();
if (osError || !os) { console.error("OS nao encontrada:", osError?.message ?? osId); process.exit(1); }
const carimbo = new Date().toLocaleDateString("pt-BR");
const linha = `[${carimbo}] CONSERTO ISOLADO (IN RFB 2.141/2023, art. 2, §2, II): ${justificativa.trim()}`;
const observacoes = [String(os.observacoes ?? "").trim(), linha].filter(Boolean).join("\n");
const { error } = await supabase.from("ordens_servico").update({ conserto_isolado: true, observacoes, atualizado_em: new Date().toISOString() }).eq("id", osId);
if (error) { console.error("atualizar:", error.message); process.exit(2); }
console.log(`OS ${os.numero_os ?? os.id} (${os.cliente_nome}): conserto_isolado = true; observacao registrada.`);
