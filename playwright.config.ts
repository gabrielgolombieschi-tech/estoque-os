import { defineConfig, devices } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";

// Credenciais de teste ficam em .env.e2e.local, que o .gitignore já cobre (.env*).
const arquivoEnv = path.join(__dirname, ".env.e2e.local");
if (fs.existsSync(arquivoEnv)) {
  for (const linha of fs.readFileSync(arquivoEnv, "utf8").split(/\r?\n/)) {
    const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (par && !process.env[par[1]]) {
      process.env[par[1]] = par[2].replace(/^["']|["']$/g, "");
    }
  }
}

const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";

export default defineConfig({
  testDir: "./tests/e2e",
  // Specs prefixados com "_" são descartáveis (diagnóstico, limpeza pontual) e ficam
  // fora da suíte. Para rodar um, tire esta linha temporariamente.
  testIgnore: ["**/_*.spec.ts"],
  outputDir: "./tests/e2e/.saida",
  timeout: 120_000,
  expect: { timeout: 20_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [["list"], ["html", { outputFolder: "tests/e2e/.relatorio", open: "never" }]],
  use: {
    baseURL,
    screenshot: { mode: "only-on-failure", fullPage: true },
    trace: "retain-on-failure",
    viewport: { width: 1440, height: 900 },
  },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        storageState: "tests/e2e/.auth/user.json",
      },
      dependencies: ["setup"],
    },
  ],
  webServer: {
    command: "npm run dev",
    url: baseURL,
    reuseExistingServer: true,
    timeout: 240_000,
  },
});
