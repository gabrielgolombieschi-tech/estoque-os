import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

export const runtime = "nodejs";

type EmpresaVinculo = { empresa_id: string; papel: string; ativo: boolean };

type Body = {
  tenantId?: string;
  email?: string;
  nome?: string;
  telefone?: string | null;
  tenantPapel?: string;
  empresaVinculos?: EmpresaVinculo[];
};

type AdminContext =
  | { error: string; status: number }
  | { supabase: ReturnType<typeof supabaseFromAuthHeader>; tenantId: string };

function isAdminError(ctx: AdminContext): ctx is { error: string; status: number } {
  return "error" in ctx;
}

async function getAdminContext(req: NextRequest): Promise<AdminContext> {
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return { error: "Nao autenticado.", status: 401 } as const;
  }

  const supabase = supabaseFromAuthHeader(req);
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) {
    return { error: "Nao autenticado.", status: 401 } as const;
  }

  const { data: hasPerm, error: permErr } = await supabase.rpc("can", {
    p_resource: "admin",
    p_action: "manage_users",
  });
  if (permErr || !hasPerm) {
    return { error: "Sem permissao.", status: 403 } as const;
  }

  const { data: tenantId, error: tenantErr } = await supabase.rpc("current_tenant_id");
  if (tenantErr || !tenantId) {
    return { error: "Tenant nao carregado.", status: 400 } as const;
  }

  return { supabase, tenantId: String(tenantId) } as const;
}

function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

function isValidEmail(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

const TENANT_ROLES = new Set(["OWNER", "ADMIN", "CONTADOR", "GESTOR"]);
const EMPRESA_ROLES = new Set([
  "ADMIN",
  "FINANCEIRO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "TECNICO",
  "APONTAMENTO_RH",
  "PAINEL_TV",
]);

export async function POST(req: NextRequest) {
  try {
    const ctx = await getAdminContext(req);
    if (isAdminError(ctx)) {
      return jerr(ctx.status, ctx.error);
    }

    const body = (await req.json()) as Body;
    const tenantId = String(body.tenantId ?? "").trim();
    const email = normalizeEmail(String(body.email ?? ""));
    const nome = String(body.nome ?? "").trim();
    const telefone = String(body.telefone ?? "").trim();
    const tenantPapel = String(body.tenantPapel ?? "GESTOR").trim().toUpperCase();
    const empresaVinculos = Array.isArray(body.empresaVinculos) ? body.empresaVinculos : [];

    if (!tenantId) return jerr(400, "tenantId obrigatorio.");
    if (tenantId !== ctx.tenantId) return jerr(403, "Tenant invalido.");

    if (!email) return jerr(400, "Email obrigatorio.");
    if (!isValidEmail(email)) return jerr(400, "Email invalido.");

    if (!nome) return jerr(400, "Nome obrigatorio.");
    if (!TENANT_ROLES.has(tenantPapel)) return jerr(400, "Papel do tenant invalido.");

    const vinculos: EmpresaVinculo[] = empresaVinculos
      .map((v) => ({
        empresa_id: String(v?.empresa_id ?? "").trim(),
        papel: String(v?.papel ?? "TECNICO").trim().toUpperCase(),
        ativo: Boolean(v?.ativo),
      }))
      .filter((v) => v.empresa_id.length > 0);

    for (const v of vinculos) {
      if (!EMPRESA_ROLES.has(v.papel)) return jerr(400, `Papel de empresa invalido: ${v.papel}`);
    }

    const admin = supabaseAdmin();

    // Best-effort: if the user already exists, reuse it.
    let authUserId: string | null = null;
    const { data: existingAuth, error: existingAuthErr } = await admin
      .schema("auth")
      .from("users")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (!existingAuthErr && existingAuth?.id) {
      authUserId = String(existingAuth.id);
    }

    if (!authUserId) {
      const { data: inviteData, error: inviteErr } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { nome },
      });

      if (inviteErr) {
        // Fallback: try createUser (some environments disable invites)
        const { data: created, error: createErr } = await admin.auth.admin.createUser({
          email,
          email_confirm: false,
          user_metadata: { nome },
        });
        if (createErr) return jerr(400, createErr.message);
        authUserId = created.user?.id ? String(created.user.id) : null;
      } else {
        authUserId = inviteData.user?.id ? String(inviteData.user.id) : null;
      }
    }

    if (!authUserId) return jerr(400, "Nao foi possivel criar/convidar o usuario no Auth.");

    const { error: finalizeErr } = await admin.rpc("admin_finalize_invited_user", {
      p_tenant_id: tenantId,
      p_auth_user_id: authUserId,
      p_email: email,
      p_nome: nome,
      p_telefone: telefone ? telefone : null,
      p_tenant_papel: tenantPapel,
      p_empresa_vinculos: vinculos,
    });

    if (finalizeErr) {
      return jerr(400, finalizeErr.message ?? "Erro ao finalizar usuario convidado.");
    }

    return NextResponse.json({ ok: true, auth_user_id: authUserId });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}

