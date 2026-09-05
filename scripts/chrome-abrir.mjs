/**
 * Abre o Chrome nativo com porta de depuração, num perfil próprio para testes.
 * A janela é sua: use normalmente. Quando eu precisar agir, eu me conecto nessa
 * porta, faço o que for e desconecto — enquanto não estou conectado, o Chrome se
 * comporta 100% nativo (confirm/alert aparecem de verdade).
 *
 *   npm run chrome            -> abre em /comercial/vendas/344
 *   npm run chrome -- /os     -> abre noutro caminho
 */
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
export const PORTA = 9222;
const PERFIL = path.join(raiz, ".chrome-e2e");
const CHROME = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";

const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";
const alvo = process.argv[2] ?? "/comercial/vendas/344";
const url = new URL(alvo, baseURL).toString();

function portaAberta(porta) {
  return new Promise((resolve) => {
    const socket = net.connect({ port: porta, host: "127.0.0.1" }, () => {
      socket.destroy();
      resolve(true);
    });
    socket.on("error", () => resolve(false));
    socket.setTimeout(1000, () => {
      socket.destroy();
      resolve(false);
    });
  });
}

if (await portaAberta(PORTA)) {
  console.log(`Chrome de teste já está aberto na porta ${PORTA}. Reaproveitando.`);
  spawn(CHROME, [`--user-data-dir=${PERFIL}`, url], { detached: true, stdio: "ignore" }).unref();
  process.exit(0);
}

if (!fs.existsSync(CHROME)) {
  console.error(`Chrome não encontrado em ${CHROME}`);
  process.exit(1);
}
fs.mkdirSync(PERFIL, { recursive: true });

spawn(
  CHROME,
  [
    `--remote-debugging-port=${PORTA}`,
    `--user-data-dir=${PERFIL}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--start-maximized",
    url,
  ],
  { detached: true, stdio: "ignore" },
).unref();

for (let tentativa = 0; tentativa < 30; tentativa += 1) {
  await new Promise((r) => setTimeout(r, 500));
  if (await portaAberta(PORTA)) {
    console.log(`Chrome aberto em ${url}`);
    console.log(`Depuração na porta ${PORTA} · perfil em .chrome-e2e`);
    process.exit(0);
  }
}

console.error("Chrome subiu mas a porta de depuração não respondeu.");
process.exit(1);
