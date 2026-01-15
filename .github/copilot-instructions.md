# Copilot Instructions (Estoque + OS)

## Stack & Architecture
- Next.js 16 App Router + TypeScript + React 19 + Tailwind 4 + Supabase (RLS/RPC).
- Multi-tenant + multi-empresa enforced by DB policies; client-side data loading with route guards.

## Boot & Context Flow
- Server preloads capabilities in [app/layout.tsx](../app/layout.tsx) via [lib/auth/capabilities.server.ts](../lib/auth/capabilities.server.ts) and passes them to [components/auth/ClientProviders.tsx](../components/auth/ClientProviders.tsx).
- Client shell handles auth guards and empresa selection in [app/components/AppShell.tsx](../app/components/AppShell.tsx).
- Empresa context persists `current_empresa_id` and calls `set_current_empresa` in [app/components/EmpresaProvider.tsx](../app/components/EmpresaProvider.tsx) and [lib/auth/empresa.ts](../lib/auth/empresa.ts).

## Tenancy & RLS (non‑negotiable)
- Always use `useTenantEmpresa()` and wait for `!loading && tenantId && empresaId` before querying.
- Apply RLS scopes with `applyTenant()` / `applyTenantEmpresa()` from [lib/db/scopes.ts](../lib/db/scopes.ts).

## Supabase Clients
- Client pages: `supabaseBrowser()` singleton from [lib/supabase/client.ts](../lib/supabase/client.ts).
- API routes: use `supabaseServer()` or `supabaseFromAuthHeader()` from [lib/supabase/server.ts](../lib/supabase/server.ts) and [lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts).
- Admin ops: `supabaseAdmin()` only, gated by RPC `can` ([lib/supabase/admin.ts](../lib/supabase/admin.ts)).

## Permissions & Menu Rendering
- Permissions load once per session in [components/auth/PermissionsProvider.tsx](../components/auth/PermissionsProvider.tsx); `has()` returns `boolean | undefined`.
- UI checks: `Boolean(has("os.read"))` or wrapper in [components/auth/Can.tsx](../components/auth/Can.tsx).
- Menu render gate uses `permissionsReady = capabilities !== null && tenantId !== null` (no reloads after boot).
- RPC `can_many` requires migration [supabase/migrations/20260206_can_many.sql](../supabase/migrations/20260206_can_many.sql).

## Page & Mutation Pattern
- CRUD pages follow: `useMemo(supabaseBrowser)`, `useTenantEmpresa`, `load()` after mutations, states `[rows, setRows]`, `[err, setErr]`, `[busy, setBusy]`.
- Examples: [app/estoque/page.tsx](../app/estoque/page.tsx), [app/itens/page.tsx](../app/itens/page.tsx), [app/os/page.tsx](../app/os/page.tsx).

## Domain Conventions
- HH services are per client in `cliente_hh_servicos`; always filter by `cliente_id` (see [app/os/[id]/components/RelatorioHHSection.tsx](../app/os/[id]/components/RelatorioHHSection.tsx)).
- Decimal inputs use `parseDecimalBR`/`formatDecimalBR` from [lib/decimal.ts](../lib/decimal.ts) with `type="text"` + `inputMode="decimal"`.

## Workflows & Env
- Commands: `npm run dev`, `npm run build`, `npm run lint`, `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev`.
- Required env: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
- DB tooling details in [docs/DB.md](../docs/DB.md); migrations run alphabetically in supabase/migrations.

## API Route Pattern
- Use `supabaseServer()` and return `NextResponse.json({ error: error.message }, { status: 400 })` on failures.
- Example routes: [app/api/os/route.ts](../app/api/os/route.ts) and [app/api/admin/users/route.ts](../app/api/admin/users/route.ts).
