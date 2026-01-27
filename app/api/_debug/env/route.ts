import { NextResponse } from "next/server";

export const runtime = "nodejs";

export async function GET() {
  return NextResponse.json({
    has_next_public_supabase_url: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    has_service_role_key: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    node_env: process.env.NODE_ENV ?? null,
  });
}

