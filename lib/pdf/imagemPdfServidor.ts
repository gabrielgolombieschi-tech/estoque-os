// Carregador de imagem do lado do servidor.
//
// Fica separado de imagemPdf.ts de proposito: o `fs` importado aqui nunca pode
// entrar no pacote do navegador. Quem roda no cliente importa so imagemPdf.ts.

import { readFile } from "node:fs/promises";
import path from "node:path";

import type { CarregadorDeImagem } from "./imagemPdf";

const TIPOS_POR_EXTENSAO: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
};

/**
 * Le a imagem de /public pelo disco. O caminho recebido e o mesmo que o
 * navegador usaria ("/Segau2.png"), para os dois lados chamarem igual.
 */
export const carregarImagemNoServidor: CarregadorDeImagem = async (caminho) => {
  try {
    const relativo = caminho.replace(/^\/+/, "");
    // Barra a saida de /public por "..", ainda que o caminho venha de codigo nosso.
    const base = path.join(process.cwd(), "public");
    const destino = path.resolve(base, relativo);
    if (destino !== base && !destino.startsWith(base + path.sep)) return null;

    const bytes = await readFile(destino);
    const extensao = path.extname(destino).toLowerCase();
    const tipo = TIPOS_POR_EXTENSAO[extensao] ?? "application/octet-stream";
    return `data:${tipo};base64,${bytes.toString("base64")}`;
  } catch {
    return null;
  }
};
