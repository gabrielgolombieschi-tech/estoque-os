import { NextResponse } from "next/server";
import { supabaseServer } from "@/lib/supabase/server";

type Body = {
  pedido_compra?: string | null;
  tipo_pedido?: string | null;
  vendedor?: string | null;
  orcado?: number;
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const pedido_compra = body.pedido_compra ?? null;
    const vendedor = body.vendedor ?? null;
    const tipoRaw = body.tipo_pedido;
    const tipo =
      tipoRaw === "servico" || tipoRaw === "material" ? tipoRaw : "servico";

    const orcado = Number(body.orcado);
    if (!Number.isFinite(orcado)) {
      return NextResponse.json(
        { error: "Valor 'orcado' inválido." },
        { status: 400 }
      );
    }

    const fator = tipo === "servico" ? 0.22 : 0.27;
    const custo = Math.round(orcado * fator * 100) / 100;

    const supabase = supabaseServer();
    const { data, error } = await supabase
      .from("os")
      .insert({
        pedido_compra,
        tipo_pedido: tipo,
        vendedor,
        orcado,
        custo,
        status: "aberta",
      })
      .select(
        "id,os_num,pedido_compra,tipo_pedido,vendedor,orcado,custo,status,created_at"
      )
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ ok: true, data });
  } catch (err: any) {
    const message =
      typeof err?.message === "string" ? err.message : "Erro inesperado.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
