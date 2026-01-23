# Copilot Instructions — Estoque-OS (Next.js + Supabase)

## Big picture
- Stack: Next.js App Router (`app/`) + React 19 + Tailwind v4; Supabase (Postgres + Auth + RLS).
- Multi-tenant + multi-empresa é “fonte da verdade” no Postgres via contexto (`current_*`) + RLS (evite duplicar regras no frontend).
- UI é guiada por “capabilities” vindas de RPC (`public.can_many` / `public.can`) para esconder/mostrar menus e ações.

## Auth / tenant / empresa (DB context + RLS)
- Tenant atual: `public.current_tenant_id()`; escolha/garantia no client via `ensureCurrentTenant()` ([lib/tenant.ts](../lib/tenant.ts)).
	- Nota: `ensureCurrentTenant` prefere o vínculo mais antigo para alinhar com o DB.
- Empresa atual: `public.current_empresa_id()`; trocas via `public.set_current_empresa(p_empresa_id)`.
- Memberships principais (RLS): `public.tenant_memberships` e `public.empresa_memberships` (README também descreve as policies).
- Cadastros “ERP” são consultados em schemas `a` (usuários/vínculos) e `c` (cadastros como `c.empresa`).

## Frontend patterns (não duplicar estado)
- Contexto global: [lib/auth/TenantEmpresaProvider.tsx](../lib/auth/TenantEmpresaProvider.tsx) (re-export de [lib/auth/provider.tsx](../lib/auth/provider.tsx)).
- Hook padrão: `useTenantEmpresa()` em [lib/auth/hooks.ts](../lib/auth/hooks.ts).
- Provider faz cache best-effort em `sessionStorage` por usuário/tenant e persiste empresa no `localStorage`.
- App shell usa `te.has()` (capabilities) e um fallback “lastKnownCaps” para reduzir flicker de menu: [app/components/AppShellClient.tsx](../app/components/AppShellClient.tsx).
- SSR tenta pré-carregar capabilities/tenant quando existir `Authorization` header: [app/layout.tsx](../app/layout.tsx). Caso falhe, o client resolve.

## Supabase clients (use o certo)
- Client-side: `getSupabaseBrowser()` em [lib/auth/supabase.ts](../lib/auth/supabase.ts) (singleton) → [lib/supabase/client.ts](../lib/supabase/client.ts).
- Server/Route Handlers com token explícito: `supabaseFromAuthHeader(req)` em [lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts).
- Service role (server-only): `supabaseAdmin()` em [lib/supabase/admin.ts](../lib/supabase/admin.ts) (requer `SUPABASE_SERVICE_ROLE_KEY`).
- Existe também `supabaseServer()`/`supabaseServerWithAuth()` em [lib/supabase/server.ts](../lib/supabase/server.ts) (cliente “simples”, sem persistência).

## Permissions / capabilities
- Chaves canônicas ficam em [lib/auth/capabilities.ts](../lib/auth/capabilities.ts).
- Fetch centralizado: `getCapabilities()` em [lib/auth/capabilities.server.ts](../lib/auth/capabilities.server.ts) (tenta `current_*`, chama `set_current_*` best-effort, e faz `rpc('can_many')`).
- Server-side gating em componentes: [lib/auth/requireCap.server.ts](../lib/auth/requireCap.server.ts).

## Query scoping / empresa
- Empresa deve ser “RLS-only”: não injete `.eq('empresa_id', ...)` automaticamente.
- Helper de escopo: [lib/db/scopes.ts](../lib/db/scopes.ts) (`applyTenant()` / `applyTenantEmpresa()`).

## API routes (padrão do projeto)
- Admin APIs validam permissão via `rpc('can', { resource: 'admin', action: 'manage_users' })` usando `supabaseFromAuthHeader`, e executam ações com `supabaseAdmin()`:
	- [app/api/admin/users/route.ts](../app/api/admin/users/route.ts)
	- [app/api/admin/invite-user/route.ts](../app/api/admin/invite-user/route.ts)

## Decimal pt-BR
- Use [lib/decimal.ts](../lib/decimal.ts) (`parseDecimalBR`, `formatDecimalBR`). `parseDecimalBR` aceita "1234,56" (sem milhar).

## Workflows
- Dev: `npm run dev` | Build: `npm run build` | Lint: `npm run lint`.
- Banco (migrations): arquivos em `supabase/migrations/`.
- Scripts de DB (exigem `DATABASE_URL` + ferramentas `psql`/`pg_dump`/`pg_restore` no PATH):
	- `npm run db:migrate` (aplica migrations via `psql`)
	- `npm run db:backup` / `npm run db:restore:dev` (restore só em dev: `DB_ENV=dev` ou `ALLOW_DB_RESTORE=true`)