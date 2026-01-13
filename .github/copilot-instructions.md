# Instruções do Copilot (Estoque + OS)

Projeto: Next.js (App Router) + TypeScript + React 19 + Tailwind 4 + Supabase. O app é **multi-tenant** e **multi-empresa**; permissões vivem no banco via RLS/RPC.

## Boot e contexto (flujo real)
- [app/layout.tsx](../app/layout.tsx) tenta carregar capabilities/tenant server-side via `supabaseFromAuthHeader` + `getCapabilities()` e injeta em [components/auth/ClientProviders.tsx](../components/auth/ClientProviders.tsx).
- [app/components/AppShell.tsx](../app/components/AppShell.tsx) roda no client: `getSession()` sem travar UI, listener `onAuthStateChange()` (sempre unsubscribe), guard `/login`, e redireciona para `/selecionar-empresa` quando há mais de uma empresa e nenhuma selecionada.
- [app/components/EmpresaProvider.tsx](../app/components/EmpresaProvider.tsx) resolve empresas: usa [lib/auth/empresa.ts](../lib/auth/empresa.ts), persiste `current_empresa_id` no `localStorage`, chama RPC `set_current_empresa` ao trocar e recarrega router.

## Tenant/empresa (não assuma defaults)
- Tenant: `ensureCurrentTenant(supabase)` em [lib/tenant.ts](../lib/tenant.ts) lê `user_tenant_context` ou pega o 1º `tenant_memberships` ativo e chama RPC `set_current_tenant`.
- Empresa: `getAllowedEmpresas()` lê `empresa_memberships`; admin faz seed best-effort. Se só existir uma, ela é escolhida; se múltiplas, exigir seleção.
- Client pages: use [lib/auth/useTenantEmpresa.ts](../lib/auth/useTenantEmpresa.ts) para obter `tenantId`, `empresaId` e `loading`. Aplique RLS com `applyTenant`/`applyTenantEmpresa` em [lib/db/scopes.ts](../lib/db/scopes.ts).
- API/server handlers: antes de queries sensíveis, garanta contexto chamando `set_current_tenant` (e `set_current_empresa` se precisar) com IDs resolvidos do JWT ou de hooks.

## Supabase no app
- Client: crie com `useMemo(() => supabaseBrowser(), [])` ([lib/supabase/client.ts](../lib/supabase/client.ts)).
- Server/API: use `supabaseFromAuthHeader(req)` ([lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts)); evite “global client” no server.
- Após auth changes, limpe caches: `clearPermissionCache()` é chamado no listener do `AppShell`.

## Permissões/capabilities
- Provider: [components/auth/PermissionsProvider.tsx](../components/auth/PermissionsProvider.tsx) + [lib/auth/permissions.ts](../lib/auth/permissions.ts) carregam `can_many` e cacheiam em `sessionStorage` por `userId:tenantId`.
- `has(cap)` pode ser `undefined` enquanto carrega; em UI use `Boolean(has("os.read"))` (padrão dos menus).
- Falta de RPC `can_many` (migration `20260206_can_many.sql`) mostra aviso; não suprimir.
- Server best-effort de capabilities/tenant é opcional; client sempre refaz em background.

## CRUD Page (App Router) — 6 passos
1) "use client" (quase tudo é client-side).
2) `const supabase = useMemo(() => supabaseBrowser(), []);`
3) Resolva contexto: `useTenantEmpresa()` e use `applyTenant(query, tenantId)` (ou `applyTenantEmpresa`).
4) `useEffect` para `load()` depois de `loading` falso; nunca query sem `tenantId`.
5) Mutations via `.insert/.update/.delete` ou RPC; exponha `error.message` no estado (`err`).
6) Depois da mutation, `await load()`; não confie em cache local.

Micro-template
```tsx
"use client";
import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant } from "@/lib/db/scopes";

export default function Page() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId, loading } = useTenantEmpresa();
  const [rows, setRows] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    if (!tenantId) return setErr("Tenant nao carregado.");
    setErr(null);
    const { data, error } = await applyTenant(supabase.from("sua_tabela").select("*"), tenantId);
    if (error) return setErr(error.message);
    setRows((data ?? []) as any[]);
  }

  useEffect(() => {
    if (loading) return;
    void load();
  }, [loading, tenantId]);

  async function onCreate() {
    setBusy(true);
    setErr(null);
    // valide empresaId se a tabela exige
    const { error } = await supabase.from("sua_tabela").insert({ /*...*/ });
    setBusy(false);
    if (error) return setErr(error.message);
    await load();
  }

  return null;
}
```

## API Route (app/api/*) — 6 passos
1) Crie `app/api/<feature>/route.ts`.
2) Use `supabaseFromAuthHeader(req)` para ler auth do usuário no server.
3) Garanta contexto com RPCs já existentes (`set_current_tenant`, `set_current_empresa`) antes de queries/RPCs que dependem de RLS.
4) Confie na lógica do banco (`can`/RLS), não em “if admin” no Node.
5) Responda com `NextResponse.json({ ... }, { status })` e mensagens claras.
6) Em erros de RPC/DB, serialize `error.message`; não devolva objetos crus.

Micro-template
```ts
import { NextResponse } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

export async function GET(req: Request) {
  const supabase = supabaseFromAuthHeader(req);
  // opcional: await supabase.rpc("set_current_tenant", { p_tenant_id: "..." });
  const { data, error } = await supabase.from("sua_tabela").select("*").limit(50);
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data }, { status: 200 });
}

export async function POST(req: Request) {
  const supabase = supabaseFromAuthHeader(req);
  const body = await req.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "JSON invalido" }, { status: 400 });

  const { error } = await supabase.from("sua_tabela").insert(body);
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true }, { status: 200 });
}
```

## DB/migrations e scripts
- RLS multi-tenant/empresa: veja [README.md](../README.md) e `supabase/migrations/` (policies usam `tenant_memberships` e `empresa_memberships`).
- Scripts: `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev` (detalhes em [docs/DB.md](../docs/DB.md); requer `DATABASE_URL` + `pg_dump/pg_restore/psql`).
- RPC `can_many` vive em `supabase/migrations/20260206_can_many.sql`; sem ele menus e guards caem em warnings.

## Referências rápidas
- Menus/guards e sessão: [app/components/AppShell.tsx](../app/components/AppShell.tsx).
- Capabilities server-side e contexto: [lib/auth/capabilities.server.ts](../lib/auth/capabilities.server.ts).
- Exemplo de CRUDs: páginas em `app/*/page.tsx` (fornecedores/estoque/os/mov).
