import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Evita disputa de arquivos no Windows/Dropbox quando `next dev` e
  // `next build` são executados no mesmo workspace.
  distDir: process.env.NODE_ENV === "development" ? ".next-dev" : ".next",
};

export default nextConfig;
