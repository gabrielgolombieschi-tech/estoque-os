import * as forge from "node-forge";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

export const runtime = "nodejs";

function isoDate(date: Date) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`;
}

export async function POST(request: Request) {
  try {
    const authorization = request.headers.get("authorization") ?? "";
    const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim() ?? "";
    if (!token) return Response.json({ error: "Sessão ausente. Recarregue a página e tente novamente." }, { status: 401 });

    const supabase = supabaseFromAuthHeader(request);
    // PostgREST validates the bearer and derives auth.uid() using the same path
    // already used by the application's scoped RPCs. This avoids depending on a
    // persisted GoTrue session in a stateless server route.
    const { data: authUserId, error: authError } = await supabase.rpc("current_auth_user_id");
    if (authError || !authUserId) {
      return Response.json({ error: "Sessão expirada ou recusada. Entre novamente e tente de novo." }, { status: 401 });
    }

    const form = await request.formData();
    const arquivo = form.get("arquivo");
    const senha = String(form.get("senha") ?? "");
    const tenantId = String(form.get("tenant_id") ?? "");
    const empresaId = String(form.get("empresa_id") ?? "");
    if (!(arquivo instanceof File) || !arquivo.size) return Response.json({ error: "Selecione o arquivo .pfx/.p12." }, { status: 400 });
    if (!tenantId || !empresaId) return Response.json({ error: "Tenant e empresa são obrigatórios." }, { status: 400 });
    if (arquivo.size > 5 * 1024 * 1024) return Response.json({ error: "Certificado maior que 5 MB." }, { status: 400 });

    const permitidas = await getAllowedEmpresas(supabase, tenantId, String(authUserId));
    if (!permitidas.some((empresa) => empresa.id === empresaId)) return Response.json({ error: "Sem acesso à empresa." }, { status: 403 });

    let validade: Date | null = null;
    try {
      const bytes = Buffer.from(await arquivo.arrayBuffer());
      const asn1 = forge.asn1.fromDer(bytes.toString("binary"));
      const p12 = forge.pkcs12.pkcs12FromAsn1(asn1, false, senha);
      const bags = p12.getBags({ bagType: forge.pki.oids.certBag });
      const certificados = bags[forge.pki.oids.certBag] ?? [];
      const certificadosDaChave = certificados.filter((bag) => (bag.attributes?.localKeyId?.length ?? 0) > 0);
      const datas = (certificadosDaChave.length ? certificadosDaChave : certificados)
        .map((bag) => bag.cert?.validity.notAfter ?? null)
        .filter((date): date is Date => date instanceof Date && !Number.isNaN(date.getTime()));
      validade = datas.sort((a, b) => a.getTime() - b.getTime())[0] ?? null;
    } catch {
      return Response.json({ error: "Não foi possível abrir o certificado. Confira o arquivo e a senha." }, { status: 422 });
    }
    if (!validade) return Response.json({ error: "O arquivo não contém certificado X.509 com validade legível." }, { status: 422 });

    const dataValidade = isoDate(validade);
    const { error } = await supabase.schema("f").rpc("fn_empresa_certificado_validade_atualizar", {
      p_empresa_id: empresaId,
      p_validade: dataValidade,
    });
    if (error) throw error;

    return Response.json({ ok: true, certificado_validade_em: dataValidade });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha ao ler o certificado.";
    return Response.json({ error: message }, { status: 400 });
  }
}
