/**
 * Roda o builder do payload NF-e localmente sobre um contexto exportado do
 * banco (f.fn_nfe_contexto_emissao_impl), para diagnosticar erros de emissao.
 *
 *   node --experimental-strip-types scripts/nfe-builder-local.mjs contexto.json
 */
import fs from "node:fs";
import { montarPayloadNfe } from "../supabase/functions/_shared/nfe-payload.ts";
const ctx = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
try {
  const p = montarPayloadNfe(ctx);
  console.log("payload ok:", JSON.stringify({ serie: p.serie, numero_fatura: p.numero_fatura, duplicatas: p.duplicatas, origem: p.items[0].icms_origem, aliquota: p.items[0].icms_aliquota, infCpl: p.informacoes_adicionais_contribuinte }));
} catch (e) {
  console.log("ERRO builder:", e.message);
}
