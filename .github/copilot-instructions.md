# Copilot Instructions — Estoque-OS

## Stack & layout
- Next.js App Router (Next 16) em `app/`, React 19, TypeScript, Tailwind v4.
- Supabase JS v2 (`@supabase/supabase-js`); cadastros “ERP” ficam nos schemas `a` (usuários/vínculos) e `c` (cadastros como `c.empresa`).
- Libs relevantes no client: PDFs com `jspdf`/`jspdf-autotable` (ex.: `lib/pdf/`, `app/os/[id]/...`), leitura de código/placa com `@zxing/browser` + OCR `tesseract.js` (ex.: `app/baixa_os_cel/page.tsx`).

## Multi-tenant + multi-empresa (RLS-first)
- Tenant/empresa são definidos pelo banco via `current_tenant_id()` / `current_empresa_id()` + RLS; não replique “segurança” no frontend.
- Tenant: use `ensureCurrentTenant()` em [lib/tenant.ts](../lib/tenant.ts) e `set_current_tenant` best-effort.
- Empresa: use `getAllowedEmpresas()` + `ensureEmpresaId()` em [lib/auth/empresa.ts](../lib/auth/empresa.ts); quando necessário, aplique contexto com `set_current_empresa`.
- Queries com sessão do usuário: não dependa de `.eq('empresa_id', ...)`; o scoping de empresa é contexto + RLS.
- Helpers de query: `applyTenant()` em [lib/db/scopes.ts](../lib/db/scopes.ts); `applyTenantEmpresa()` **não** injeta `empresa_id` (por design).
- Inserts/Upserts em tabelas com `empresa_id`: inclua `empresa_id` no payload (RLS costuma exigir não-nulo; ver [README.md](../README.md)).

## Auth/contexto no cliente (anti-flicker)
- Provider global: [lib/auth/provider.tsx](../lib/auth/provider.tsx) (re-export em [lib/auth/TenantEmpresaProvider.tsx](../lib/auth/TenantEmpresaProvider.tsx)). Cacheia tenant/empresa e evita carregar permissões antes de ter contexto completo.
- Shell: [app/components/AppShellClient.tsx](../app/components/AppShellClient.tsx) só renderiza menus com sessão+tenant+empresa; papel `PAINEL_TV` restringe rotas/menus/permissões.
- Hooks: `useTenantEmpresa()` e `useIsAdminTenant()` em [lib/auth/hooks.ts](../lib/auth/hooks.ts).

## Permissões (Capabilities)
- Chaves/payload: [lib/auth/capabilities.ts](../lib/auth/capabilities.ts) (`CAPABILITY_KEYS`, `buildCanManyPayload`).
- Client: permissões vêm de `get_my_permissions` e fazem merge best-effort com `can_many()` (ver provider).
- Server: prefetch/gate em [lib/auth/capabilities.server.ts](../lib/auth/capabilities.server.ts) e [lib/auth/requireCap.server.ts](../lib/auth/requireCap.server.ts).

## Supabase clients (use o certo)
- Browser: `getSupabaseBrowser()` em [lib/auth/supabase.ts](../lib/auth/supabase.ts) → [lib/supabase/client.ts](../lib/supabase/client.ts).
- Route handler/SSR com token do usuário: `supabaseFromAuthHeader(req)` em [lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts).
- Service role: `supabaseAdmin()` em [lib/supabase/admin.ts](../lib/supabase/admin.ts) — **RLS é bypassado**; filtre explicitamente `tenant_id`/`empresa_id` em rotas admin/mutações.

## Admin APIs (padrão do projeto)
- Autorize com `supabaseFromAuthHeader(req).rpc('can', { p_resource: 'admin', p_action: 'manage_users' })`.
- Execute mutações com `supabaseAdmin()`; exemplos: [app/api/admin/users/route.ts](../app/api/admin/users/route.ts), [app/api/admin/invite-user/route.ts](../app/api/admin/invite-user/route.ts).
- Rotas que chamam `supabaseAdmin().auth.admin.*` devem exportar `runtime = "nodejs"`.

## Workflows
- `npm run dev | build | lint | start`
- Banco: migrations em `supabase/migrations/`; scripts `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev` (requer `DATABASE_URL` + `psql/pg_dump/pg_restore`; ver [docs/DB.md](../docs/DB.md)).
- Env vars comuns: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
- Formatação pt-BR: helpers em [lib/decimal.ts](../lib/decimal.ts) (`parseMoneyBR`, `formatMoneyBR`).