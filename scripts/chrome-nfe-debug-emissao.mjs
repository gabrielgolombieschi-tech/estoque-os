/**
 * Abre a conferencia pendente e clica em emitir com console/rede instrumentados,
 * para achar por que o envio nao sai quando ha transportadora.
 */
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const ovId = process.argv[2] ?? "344";
const { pagina, encerrar } = await conectar();

pagina.on("console", (m) => {
  const t = m.text();
  if (m.type() === "error" || /erro|error|pend|cadastro|transporte|congelar/i.test(t)) {
    console.log(`[console:${m.type()}] ${t.slice(0, 300)}`);
  }
});
pagina.on("pageerror", (e) => console.log(`[pageerror] ${e.message.slice(0, 300)}`));
pagina.on("response", async (r) => {
  if (r.status() >= 400 || /rpc|functions/.test(r.url())) {
    let corpo = "";
    try { corpo = (await r.text()).slice(0, 400); } catch { /* stream consumido */ }
    console.log(`[http ${r.status()}] ${r.url().split("/").slice(-2).join("/")} :: ${corpo}`);
  }
});

await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(3500);
await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
await pagina.waitForTimeout(2500);

const botao = pagina.getByRole("button", { name: /^(Conferir e emitir em homologação|Continuar conferência)$/ }).first();
console.log("abrindo:", (await botao.textContent())?.trim());
await botao.click();
await pagina.waitForTimeout(4000);

const conf = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();
const destinoSC = conf.getByRole("button", { name: /^Dentro de Santa Catarina/ });
if ((await destinoSC.count()) > 0) {
  await destinoSC.click();
  await conf.getByRole("button", { name: /^Continuar para conferência fiscal/ }).click();
  await pagina.waitForTimeout(5000);
}

console.log("\n--- clicando emitir ---");
const emitir = conf.getByRole("button", { name: /^(Emitir em homologação|Tentar emitir novamente)/ });
console.log("botão:", (await emitir.textContent())?.trim(), "| habilitado:", await emitir.isEnabled());
await emitir.click();
await pagina.waitForTimeout(15_000);

console.log("\n--- estado da tela ---");
const textos = await conf.locator('[role="alert"], li').allTextContents();
for (const t of textos) {
  const limpo = t.replace(/\s+/g, " ").trim();
  if (limpo) console.log("  •", limpo.slice(0, 300));
}

await encerrar();
