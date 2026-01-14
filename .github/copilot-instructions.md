# Instruções do Copilot (Estoque + OS)

Projeto: Next.js (App Router 16.1) + TypeScript + React 19 + Tailwind 4 + Supabase. O app é **multi-tenant** e **multi-empresa**; permissões vivem no banco via RLS/RPC.

## Boot e contexto (fluxo real)
- [app/layout.tsx](../app/layout.tsx) tenta carregar capabilities/tenant server-side via `supabaseFromAuthHeader` + `getCapabilities()` e injeta em [components/auth/ClientProviders.tsx](../components/auth/ClientProviders.tsx).
- [app/components/AppShell.tsx](../app/components/AppShell.tsx) roda no client: `getSession()` sem travar UI, listener `onAuthStateChange()` (sempre unsubscribe), guard `/login`, redireciona para `/selecionar-empresa` quando múltiplas empresas sem seleção.
- [app/components/EmpresaProvider.tsx](../app/components/EmpresaProvider.tsx) resolve empresas: usa [lib/auth/empresa.ts](../lib/auth/empresa.ts), persiste `current_empresa_id` no `localStorage`, chama RPC `set_current_empresa` ao trocar.

## Tenant/empresa (não assuma defaults)
- **Tenant:** `ensureCurrentTenant(supabase)` em [lib/tenant.ts](../lib/tenant.ts) lê `user_tenant_context` ou pega o 1º `tenant_memberships` ativo e chama RPC `set_current_tenant`.
- **Empresa:** `getAllowedEmpresas()` lê `empresa_memberships`. Se uma existe, escolhe; se múltiplas, exige seleção via `/selecionar-empresa`.
- **Client pages:** use `useTenantEmpresa()` para obter `tenantId`, `empresaId`, `loading`. Aplique RLS com `applyTenant(query, tenantId)` ou `applyTenantEmpresa(query, tenantId, empresaId)` em [lib/db/scopes.ts](../lib/db/scopes.ts).
- **Queries:** nunca execute sem `tenantId` setado; sempre aguarde `!loading` antes de carregar dados.

## Supabase — 3 contextos
- **Client (`"use client"` pages):** `supabase = useMemo(() => supabaseBrowser(), [])` ([lib/supabase/client.ts](../lib/supabase/client.ts)). RLS valida `tenant_id`/`empresa_id`.
- **API Routes:** `supabaseServer()` (anon key sem auth header; RLS valida via session) ou `supabaseFromAuthHeader(req)` (com token do usuário). Ver [lib/supabase/server.ts](../lib/supabase/server.ts) e [lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts).
- **Admin ops:** `supabaseAdmin()` ([lib/supabase/admin.ts](../lib/supabase/admin.ts)) apenas com validação via `can` RPC. Nunca bypass RLS no client.

## Permissões/capabilities
- **Provider:** [components/auth/PermissionsProvider.tsx](../components/auth/PermissionsProvider.tsx) + [lib/auth/permissions.ts](../lib/auth/permissions.ts) carregam `can_many` RPC uma vez por sessão e cacheiam em `sessionStorage`.
- **Uso:** `const { has } = usePermissions()` retorna `has(key) -> boolean | undefined`. Em JSX use `Boolean(has("os.read"))` ou wrapper `<Can perm="os.read">...</Can>` ([components/auth/Can.tsx](../components/auth/Can.tsx)).
- **Menu rendering:** `{permissionsReady && canAccessOs && <Menu>}` para evitar piscadas. `permissionsReady = capabilities !== null && tenantId !== null`.
- **Keys:** [lib/auth/capabilities.ts](../lib/auth/capabilities.ts) lista todas (e.g. `os.read`, `estoque.write`, `admin.manage_users`, `financeiro.read`).
- **RPC `can_many`:** migration [20260206_can_many.sql](../supabase/migrations/20260206_can_many.sql) obrigatória; sem ela, aviso no console "could not find the function public.can_many".

## CRUD Page (App Router) — padrão validado
1) `"use client"`
2) `const supabase = useMemo(() => supabaseBrowser(), []);`
3) `const { tenantId, empresaId, loading } = useTenantEmpresa();` Resolve contexto.
4) `useEffect` dispara `load()` apenas quando `!loading && tenantId`.
5) Mutations (insert/update/delete) + error handling: `if (error) return setErr(error.message); await load();`

**Exemplo real:** [app/estoque/page.tsx](../app/estoque/page.tsx) (581 linhas, CRUD completo com filtros), [app/itens/page.tsx](../app/itens/page.tsx) (1197 linhas, forms e fiscal items).

```tsx
"use client";
import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";

export default function Page() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId, loading } = useTenantEmpresa();
  const [rows, setRows] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    if (!tenantId || !empresaId) return;
    const { data, error } = await applyTenantEmpresa(
      supabase.from("sua_tabela").select("*"), tenantId, empresaId
    );
    if (error) return setErr(error.message);
    setRows(data ?? []);
  }

  useEffect(() => {
    if (loading) return;
    void load();
  }, [loading, tenantId, empresaId]);

  return <div>{rows.length} registros</div>;
}
```

## API Route (app/api/*) — padrão validado
1) `app/api/<feature>/route.ts`
2) Use `supabaseServer()` (simples) para RLS valida via session. Ou `supabaseFromAuthHeader(req)` se precisar token explícito.
3) Validação: confie em RLS + RPC `can`; não use "if (isAdmin)" em Node.
4) Erros: `NextResponse.json({ error: error.message }, { status: 400 })`

**Exemplos reais:**
- [app/api/os/route.ts](../app/api/os/route.ts) — POST cria OS, calcula custos.
- [app/api/admin/users/route.ts](../app/api/admin/users/route.ts) — GET lista (admin only), POST cria usuários com roles.

```ts
import { NextResponse } from "next/server";
import { supabaseServer } from "@/lib/supabase/server";

export async function GET(req: Request) {
  const supabase = supabaseServer();
  const { data, error } = await supabase.from("sua_tabela").select("*");
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
```

## DB/migrations e scripts
- **RLS:** Multi-tenant via `tenant_memberships`, multi-empresa via `empresa_memberships`. Veja [README.md](../README.md#rls-multi-tenant-e-multi-empresa) e `supabase/migrations/`.
- **Scripts:** `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev`. Detalhes em [docs/DB.md](../docs/DB.md); requer `DATABASE_URL` + `pg_dump/pg_restore/psql`.
- **Migrations ativas:** 30+ arquivos desde `20240102_fiscal.sql` até `20260213_financeiro_dashboard.sql`. Sempre aplicar em ordem alfabética.
- **RPC crítico:** `can_many` (20260206), `set_current_tenant`, `set_current_empresa`, `current_tenant_id()`, `current_empresa_id()`.

## Menu Flicker Fix (resolvido)
- **Problema:** Menu pisca/desaparece ao navegar (solução via `initializedRef` flag).
- **Solução:** [components/auth/PermissionsProvider.tsx](../components/auth/PermissionsProvider.tsx) carrega permissões UMA VEZ por sessão; [app/components/AppShell.tsx](../app/components/AppShell.tsx) renderiza com `{permissionsReady && menu}` (nunca com `loadingInitial`).
- **Resultado:** Menu nunca pisca ao navegar, trocar aba ou recarregar página.
- **Docs:** [MENU_FLICKER_FIX_SUMMARY.md](../docs/MENU_FLICKER_FIX_SUMMARY.md) (leitura rápida), [MENU_FLICKER_FIX.md](../docs/MENU_FLICKER_FIX.md) (análise detalhada).

## Convenções
- **Errors:** sempre capture `error.message` (string), não o objeto inteiro.
- **States:** `[rows, setRows]`, `[err, setErr]`, `[busy, setBusy]` (padrão do projeto).
- **Async:** `await load()` após mutations para refrescar dados; não confie em otimistic updates.
- **Permissions check:** `if (!has(perm)) return setErr("Sem permissão.")` no início de mutations.
- **Type safety:** use tipos extraídos de Supabase (`Row` types em comentários ou `as Row[]` cast).

## Referências rápidas
- Boot/session: [app/components/AppShell.tsx](../app/components/AppShell.tsx) (150+ linhas, listeners, guards).
- Capabilities server-side: [lib/auth/capabilities.server.ts](../lib/auth/capabilities.server.ts).
- Example CRUDs: [app/estoque/page.tsx](../app/estoque/page.tsx), [app/itens/page.tsx](../app/itens/page.tsx), [app/os/page.tsx](../app/os/page.tsx).
- Empresa switch: [app/selecionar-empresa/page.tsx](../app/selecionar-empresa/page.tsx).
