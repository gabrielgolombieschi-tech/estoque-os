/**
 * Navega a aba de teste para um caminho, logando se cair no login.
 *
 *   npm run chrome:ir -- /comercial/vendas/344
 */
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const alvo = process.argv[2] ?? "/comercial/vendas/344";
const url = new URL(alvo, baseURL).toString();

const { pagina, encerrar } = await conectar();

await pagina.goto(url, { waitUntil: "domcontentloaded" });
if (await garantirSessao(pagina)) {
  console.log("Sessão criada no perfil do Chrome (fica salva para as próximas).");
  await pagina.goto(url, { waitUntil: "domcontentloaded" });
}

await pagina.waitForLoadState("networkidle").catch(() => {});
console.log("URL:", pagina.url());
await encerrar();
