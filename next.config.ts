import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Evita disputa de arquivos no Windows/Dropbox quando `next dev` e
  // `next build` são executados no mesmo workspace.
  distDir: process.env.NODE_ENV === "development" ? ".next-dev" : ".next",
  // O catálogo YAML é lido em runtime pelo agente da importação de NF-e.
  // Incluí-lo explicitamente garante disponibilidade no bundle de produção.
  outputFileTracingIncludes: {
    "/api/estoque/importar/normalizar-itens": ["./docs/padroes-cadastro/catalogo-paineis-eletricos.yaml"],
  },
};

export default nextConfig;
