/**
 * Converte um HTML local em PDF (A4 paisagem) com o Chromium do Playwright.
 * Usado para as apresentacoes de docs/faturamento.
 *
 *   node scripts/render-pdf-html.mjs <entrada.html> <saida.pdf>
 */
import { chromium } from "playwright";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [, , entrada, saida] = process.argv;
const retrato = process.argv.includes("--retrato");
if (!entrada || !saida) { console.error("Uso: node scripts/render-pdf-html.mjs <entrada.html> <saida.pdf> [--retrato]"); process.exit(1); }
const navegador = await chromium.launch();
const pagina = await navegador.newPage();
await pagina.goto(pathToFileURL(path.resolve(entrada)).toString(), { waitUntil: "load" });
await pagina.pdf({ path: path.resolve(saida), format: "A4", landscape: !retrato, printBackground: true, margin: { top: "12mm", bottom: "12mm", left: "12mm", right: "12mm" } });
await navegador.close();
console.log("PDF:", path.resolve(saida));
