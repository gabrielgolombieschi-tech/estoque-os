/**
 * Lista as OVs e marca as que servem para o ciclo de teste de NF-e:
 * em andamento, com saldo a faturar e sem NF-e emitida. Só lê.
 *
 *   npm run chrome:ov
 */
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const { pagina, encerrar } = await conectar({ aceitarDialogos: false });

await pagina.goto(new URL("/comercial/vendas", baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(4000);

const linhas = pagina.locator("tbody tr:has(td:nth-child(3))");
await linhas.first().waitFor({ state: "visible", timeout: 45_000 }).catch(() => {});
const total = await linhas.count();
console.log(`${total} linha(s) na lista de vendas\n`);

const dados = await linhas.evaluateAll((trs) =>
  trs.map((tr) => [...tr.querySelectorAll("td")].map((td) => td.textContent?.replace(/\s+/g, " ").trim() ?? "")),
);

const cabecalho = await pagina.locator("thead th").allTextContents();
console.log("colunas:", cabecalho.map((c) => c.replace(/\s+/g, " ").trim()).join(" | "));
console.log();
dados.slice(0, 40).forEach((celulas, i) => console.log(`${String(i).padStart(2)} ${celulas.join(" | ").slice(0, 190)}`));

await encerrar();
