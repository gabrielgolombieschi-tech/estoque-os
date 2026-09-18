import { NextRequest, NextResponse } from "next/server";
import fs from "node:fs/promises";
import path from "node:path";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

// Manuais do ERP (pasta manuais/ na raiz, fora de public/): so quem tem sessao no ERP le.
// Os prints e o texto trazem cliente, OC, precos e chave de NF-e. A pagina
// /manuais/<manual> busca o index.html e as imagens por aqui, com o Bearer da sessao.
// Sem sessao: 401. Caminho fora da pasta ou arquivo inexistente: 404.

export const runtime = "nodejs";

const RAIZ = path.join(process.cwd(), "manuais");
const TIPOS: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".pdf": "application/pdf",
  ".xml": "application/xml; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};

export async function GET(req: NextRequest, contexto: { params: Promise<{ caminho: string[] }> }) {
  const supabase = supabaseFromAuthHeader(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    return NextResponse.json({ error: "Entre no ERP para abrir o manual." }, { status: 401 });
  }

  const { caminho } = await contexto.params;
  const partes = (caminho ?? []).filter((parte) => /^[A-Za-z0-9._-]+$/.test(parte) && parte !== ".." && parte !== ".");
  if (partes.length === 0 || partes.length !== (caminho ?? []).length) {
    return NextResponse.json({ error: "Manual não encontrado." }, { status: 404 });
  }
  const arquivo = path.resolve(RAIZ, ...partes);
  if (!arquivo.startsWith(RAIZ + path.sep)) {
    return NextResponse.json({ error: "Manual não encontrado." }, { status: 404 });
  }
  const tipo = TIPOS[path.extname(arquivo).toLowerCase()];
  if (!tipo) {
    return NextResponse.json({ error: "Manual não encontrado." }, { status: 404 });
  }
  try {
    const conteudo = await fs.readFile(arquivo);
    return new NextResponse(new Uint8Array(conteudo), {
      status: 200,
      headers: { "Content-Type": tipo, "Cache-Control": "private, no-store" },
    });
  } catch {
    return NextResponse.json({ error: "Manual não encontrado." }, { status: 404 });
  }
}
