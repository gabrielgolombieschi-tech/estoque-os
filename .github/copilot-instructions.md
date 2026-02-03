# Copilot Instructions — Estoque-OS

## Stack
- Next.js App Router (`app/`), React 19, Tailwind v4, Supabase JS v2 (`@supabase/supabase-js`).
- Client-side libs usadas no produto: PDFs com `jspdf`/`jspdf-autotable` (ex.: `lib/pdf/`, `app/os/[id]/...`), leitura de código/placa com `@zxing/browser` + OCR `tesseract.js` (ex.: `app/baixa_os_cel/page.tsx`).

## Multi-tenant + Multi-empresa (DB decide via RLS)
- Não duplique regras no frontend: tenant/empresa vêm de `current_tenant_id()` / `current_empresa_id()` + policies.
- Tenant: resolva com `ensureCurrentTenant()` em [lib/tenant.ts](../lib/tenant.ts) (auth user → `a.usuario` → `a.usuario_tenant`; prefere vínculo ativo mais antigo) e faz `set_current_tenant` best-effort.
- Empresa: use `getAllowedEmpresas()`/`ensureEmpresaId()` em [lib/auth/empresa.ts](../lib/auth/empresa.ts) e, quando necessário, RPC `set_current_empresa`.
- Queries com sessão do usuário (Supabase anon + JWT): não dependa de `.eq('empresa_id', ...)` para “segurança”; o scoping de empresa é RLS + contexto. Use só tenant scope: `applyTenant()` em [lib/db/scopes.ts](../lib/db/scopes.ts) (e `applyTenantEmpresa()` não injeta `empresa_id`).
- Policies: tabelas com `empresa_id` geralmente exigem `empresa_id` **não nulo** (ver seção “RLS multi-tenant e multi-empresa” no [README.md](../README.md)); em INSERT/UPSERT inclua `empresa_id` no payload quando aplicável.
- IMPORTANTE: com `supabaseAdmin()` (service role) RLS não vale; então rotas/admin/mutações devem filtrar explicitamente `tenant_id` e `empresa_id` quando aplicável (ex.: `app/api/estoque/importar-xml/route.ts`).
- Cadastros “ERP” vivem em schemas `a` (usuários/vínculos) e `c` (cadastros, ex: `c.empresa`). Memberships principais: `tenant_memberships` e `empresa_memberships` (status `active`) + legado `a.usuario_*`.

## Auth/Contexto no cliente (anti-flicker)
- Provider global: [lib/auth/provider.tsx](../lib/auth/provider.tsx) (re-export em [lib/auth/TenantEmpresaProvider.tsx](../lib/auth/TenantEmpresaProvider.tsx)). Ele cacheia tenant/empresa, tenta setar contexto no DB e só carrega permissões depois de ter tenant+empresa (evita ambiguidade de `get_my_permissions`).
- UI shell: [app/components/AppShellClient.tsx](../app/components/AppShellClient.tsx) não renderiza menus até ter sessão+tenant+empresa; modo `PAINEL_TV` restringe rotas/menus/permissões.
- Hooks padrão: `useTenantEmpresa()` e `useIsAdminTenant()` em [lib/auth/hooks.ts](../lib/auth/hooks.ts).

## Permissões (Capabilities)
- Chaves e payload: [lib/auth/capabilities.ts](../lib/auth/capabilities.ts) (`CAPABILITY_KEYS`, `buildCanManyPayload`).
- Client: permissões vêm de `get_my_permissions` (tenant+empresa) e fazem merge best-effort com `can_many()`; aliases legacy também são aplicados no provider.
- Server components: prefetch em [lib/auth/capabilities.server.ts](../lib/auth/capabilities.server.ts) e gate em [lib/auth/requireCap.server.ts](../lib/auth/requireCap.server.ts).

## Supabase clients (use o certo)
- Browser: `getSupabaseBrowser()` em [lib/auth/supabase.ts](../lib/auth/supabase.ts) (singleton) → [lib/supabase/client.ts](../lib/supabase/client.ts).
- Route handler/SSR com token do usuário: `supabaseFromAuthHeader(req)` em [lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts).
- Admin/service role: `supabaseAdmin()` em [lib/supabase/admin.ts](../lib/supabase/admin.ts).

## Admin APIs (padrão do projeto)
- Autorize com `supabaseFromAuthHeader(req).rpc('can', { p_resource: 'admin', p_action: 'manage_users' })`.
- Execute mutações com `supabaseAdmin()`; exemplos: [app/api/admin/users/route.ts](../app/api/admin/users/route.ts), [app/api/admin/invite-user/route.ts](../app/api/admin/invite-user/route.ts).
- Rotas que usam `supabaseAdmin().auth.admin.*` devem exportar `runtime = "nodejs"`.

## Workflows
- Dev/build/lint/start: `npm run dev` | `npm run build` | `npm run lint` | `npm run start`.
- Banco: migrations em `supabase/migrations/`; scripts `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev` (requer `DATABASE_URL` + `psql/pg_dump/pg_restore`). Detalhes: [docs/DB.md](../docs/DB.md).
- Env vars comuns: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
- Formatação pt-BR: helpers em [lib/decimal.ts](../lib/decimal.ts) (`parseMoneyBR`, `formatMoneyBR`, etc.).