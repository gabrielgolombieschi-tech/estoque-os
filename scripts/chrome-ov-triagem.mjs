/**
 * Abre cada OV por id e reporta o estado de faturamento, para escolher qual
 * serve ao ciclo de teste de NF-e. Só lê.
 *
 *   npm run chrome:ov:triagem -- 341 342 343 344
 */
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const ids = process.argv.slice(2).length ? process.argv.slice(2) : ["341", "342", "343", "344"];
const { pagina, encerrar } = await conectar({ aceitarDialogos: false });

for (const id of ids) {
  await pagina.goto(new URL(`/comercial/vendas/${id}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
  await garantirSessao(pagina);
  await pagina.waitForTimeout(3500);

  const titulo = (await pagina.locator("h1").first().textContent().catch(() => ""))?.replace(/\s+/g, " ").trim();
  if (!titulo) {
    console.log(`\nid ${id}: não abriu (${pagina.url()})`);
    continue;
  }

  const progresso = (await pagina.locator("table").first().locator("tbody tr").allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim());
  const faturar = pagina.getByRole("button", { name: "Faturar", exact: true });
  const podeFaturar = (await faturar.count()) > 0 ? await faturar.isEnabled() : null;

  await pagina.getByRole("button", { name: /^Faturamento \(/ }).click().catch(() => {});
  await pagina.waitForTimeout(2500);
  const rascunhos = await pagina.getByRole("button", { name: "Descartar rascunho" }).count();
  const autorizadas = await pagina.getByText("Autorizada em homologação").count();
  const emitir = await pagina.getByRole("button", { name: /Conferir e emitir/ }).count();

  console.log(`\nid ${id} · ${titulo.slice(0, 90)}`);
  for (const p of progresso) console.log("   ", p.slice(0, 130));
  console.log(`    Faturar: ${podeFaturar === null ? "ausente" : podeFaturar ? "HABILITADO" : "desabilitado"}`);
  console.log(`    rascunhos: ${rascunhos} · autorizadas homologação: ${autorizadas} · prontos p/ emitir: ${emitir}`);
}

await encerrar();
