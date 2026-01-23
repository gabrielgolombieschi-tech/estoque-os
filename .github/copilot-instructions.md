# Copilot Instructions — Estoque-OS (Next.js + Supabase)

## Big picture
- Stack: Next.js App Router + React 19 + Tailwind v4; Supabase (Postgres + Auth + RLS).
- Multi-tenant + multi-empresa é controlado no Postgres via contexto e RLS.
- UI usa “capabilities” vindas de RPC (`public.can_many`) para esconder/mostrar features.

## Auth / tenant / empresa (fonte da verdade)
- Tenant atual vem de `public.current_tenant_id()` (definido via `public.set_current_tenant(...)` quando existir no DB).
- Empresa atual vem de `public.current_empresa_id()` e é definida via `public.set_current_empresa(p_empresa_id)`.
- Memberships principais (RLS): `public.tenant_memberships` e `public.empresa_memberships`.
- Há cadastros “ERP” em schemas `a` (usuários/vínculos) e `c` (cadastros) usados por várias telas.

## Frontend patterns (não duplicar estado)
- Contexto global fica em [lib/auth/TenantEmpresaProvider.tsx](../lib/auth/TenantEmpresaProvider.tsx) (re-export de `lib/auth/provider.tsx`).
- Hook padrão: [lib/auth/hooks.ts](../lib/auth/hooks.ts) (`useTenantEmpresa()`).
- Layout tenta prefetchar capabilities no server para reduzir flicker: [app/layout.tsx](../app/layout.tsx).

## Supabase client (obrigatório)
- Client-side: usar `getSupabaseBrowser()` ([lib/auth/supabase.ts](../lib/auth/supabase.ts)), que encapsula `supabaseBrowser()` ([lib/supabase/client.ts](../lib/supabase/client.ts)).
- Route handlers/server utils com token explícito: `supabaseFromAuthHeader(req)` ([lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts)).
- Service role (server-only): `supabaseAdmin()` ([lib/supabase/admin.ts](../lib/supabase/admin.ts)); requer `SUPABASE_SERVICE_ROLE_KEY`.

## Query scoping
- Preferir RLS para empresa: não injete `.eq('empresa_id', ...)` automaticamente.
- Helper de escopo: [lib/db/scopes.ts](../lib/db/scopes.ts) (`applyTenant()` / `applyTenantEmpresa()`), onde empresa é “RLS-only”.

## Permissions / capabilities
- Lista de chaves fica em [lib/auth/capabilities.ts](../lib/auth/capabilities.ts).
- Server-side check (server components): [lib/auth/requireCap.server.ts](../lib/auth/requireCap.server.ts).

## Decimal pt-BR
- Use [lib/decimal.ts](../lib/decimal.ts) (`parseDecimalBR`, `formatDecimalBR`).
- Observação: `parseDecimalBR` aceita bem "1234,56"; não assume separador de milhar.

## Workflows
- Dev: `npm run dev` | Build: `npm run build` | Lint: `npm run lint`.
- Banco: migrations em `supabase/migrations/` (ex.: `20260116_empresa_context.sql`, `20260206_can_many.sql`).
- Scripts: `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev`.