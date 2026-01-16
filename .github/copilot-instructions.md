# Copilot Instructions (Estoque + OS)

## Stack
- Next.js App Router (Next 16) + TypeScript + React 19 + Tailwind 4.
- Supabase (RLS + RPC) is the source of truth for auth/permissions/tenancy.

## Tenancy + RLS (non-negotiable)
- The app is **multi-tenant** and many tables are **multi-empresa**. DB policies enforce `tenant_id` and (when present) `empresa_id`.
- In client pages/components, always resolve context first via `useTenantEmpresa()` (lib/auth/useTenantEmpresa.ts). Never query when `loading` or missing IDs.
- Always scope queries using helpers from lib/db/scopes.ts:
  - `applyTenant(query, tenantId)`
  - `applyTenantEmpresa(query, tenantId, empresaId)`

## Boot flow (why menus don’t flicker)
- Server tries to preload capabilities in app/layout.tsx via lib/auth/capabilities.server.ts and passes them into components/auth/ClientProviders.tsx.
- Client permissions cache lives in components/auth/PermissionsProvider.tsx (sessionStorage + in-memory); it refreshes mainly on login/logout.
- The shell/guards/menu live in app/components/AppShell.tsx.
- Empresa selection/state lives in app/components/EmpresaProvider.tsx and is synced to DB via RPC `set_current_empresa`.

## Supabase clients (use the right one)
- Browser/client components: lib/supabase/client.ts (`supabaseBrowser()` singleton).
- API routes with user JWT: lib/supabase/serverFromAuthHeader.ts (`supabaseFromAuthHeader(req)`), then call RPCs to set context when needed.
- Admin/server-role operations: lib/supabase/admin.ts (`supabaseAdmin()`), typically gated by RPC `can('admin','manage_users')` (see app/api/admin/users/route.ts).

## Page pattern (how most screens work)
- Typical pages (e.g., app/itens/page.tsx, app/estoque/page.tsx): `useMemo(supabaseBrowser)`, `load()` on mount/filters, local state for rows/errors/busy, and reload after mutations.
- Prefer `<Can perm="...">` (components/auth/Can.tsx) for UI gating; `has()` returns `boolean | undefined` until loaded.

## Domain conventions
- Brazilian decimals: always use `parseDecimalBR()` / `formatDecimalBR()` (lib/decimal.ts) and prefer `type="text"` + `inputMode="decimal"`.
- HH module has lots of edge cases; reference docs/HH_BUG_FIX_COMPLETE.md before changing HH flows.

## Commands
- Dev: `npm run dev`  | Build: `npm run build` / `npm run start`  | Lint: `npm run lint`
- DB scripts: `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev`

## Common gotchas
- “RLS violation” usually means missing scope (`applyTenant*`) or missing DB context (RPC `set_current_tenant` / `set_current_empresa`).
- If RPC `can_many` is missing, apply migration supabase/migrations/20260206_can_many.sql.
