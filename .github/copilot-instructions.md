# Copilot instructions for Estoque + OS

Purpose: give AI coding agents the minimal, precise knowledge to be immediately productive in this repo.

- **Big picture**: This is a Next.js (App Router) TypeScript app that relies on client-side Supabase for auth and most DB operations. Pages live under `app/*` and interactive pages are React client components (`"use client"`). The UI shell and auth gating are centralized in `app/components/AppShell.tsx`.

- **Where to start reading**:
  - [app/layout.tsx](app/layout.tsx#L1) — root layout mounting `AppShell`.
  - [app/components/AppShell.tsx](app/components/AppShell.tsx#L1) — auth routing, `onAuthStateChange()` handling, header/navigation.
  - [lib/supabase/client.ts](lib/supabase/client.ts#L1) — `supabaseBrowser()` factory used in browser code.
  - [lib/supabase/server.ts](lib/supabase/server.ts#L1), [lib/supabase/admin.ts](lib/supabase/admin.ts#L1) — server helpers; use them only when adding server env vars.
  - [app/components/EmpresaProvider.tsx](app/components/EmpresaProvider.tsx#L1) and `lib/auth/*` — tenant / empresa context and hooks.
  - Example CRUD pages: [app/fornecedores/page.tsx](app/fornecedores/page.tsx#L1), [app/itens/page.tsx](app/itens/page.tsx#L1), [app/estoque/page.tsx](app/estoque/page.tsx#L1).

- **Auth & routing (critical)**:
  - `AppShell` obtains session via `supabase.auth.getSession()` and subscribes to `onAuthStateChange()`; it redirects to `/login` when unauthenticated.
  - `/login` is treated as the single public route (`const isPublic = pathname === "/login"`).
  - If auth flow changes, update `AppShell` first and keep `onAuthStateChange()` cleanup (unsubscribe) intact.

- **Supabase patterns**:
  - Use `supabaseBrowser()` from [lib/supabase/client.ts](lib/supabase/client.ts#L1) in UI code, typically wrapped in `useMemo(() => supabaseBrowser(), [])`.
  - Server-side helpers exist for use in API routes, but adding them requires server env vars (do not hardcode keys).
  - Common operations: `supabase.from('table').select(...)`, `.insert(...)`, `.update(...).eq('id', id)` — see example pages.
  - Most DB calls are client-side; RBAC/RLS is enforced by Supabase (see `supabase/migrations/*`).

- **Multi-empresa / tenant conventions**:
  - Tenant context is explicit — see `lib/tenant.ts`, `lib/auth/empresa.ts`, `app/components/EmpresaProvider.tsx`, `lib/useEmpresa.ts`.
  - Preserve tenant scoping in queries and when adding new pages or server endpoints.

- **Developer workflows / useful scripts** (`package.json`):
  - `npm run dev` — start Next dev server (http://localhost:3000)
  - `npm run build` — build production output
  - `npm start` — run built app
  # Copilot instructions for Estoque + OS

  Purpose: Give AI coding agents concise, actionable guidance to be immediately productive in this repository.

  What this project is
  - Next.js (App Router) + TypeScript web app. UI pages live under `app/*`.
  - Auth and most DB actions are performed client-side using Supabase.
  - Multi-tenant (multi-empresa) app: tenant context is explicit and enforced via RLS in Supabase migrations.

  Key files to read first
  - [app/layout.tsx](app/layout.tsx#L1) — root layout that mounts the app shell.
  - [app/components/AppShell.tsx](app/components/AppShell.tsx#L1) — central auth gate and header/navigation; handles `supabase.auth.getSession()` and `onAuthStateChange()` redirects (update this when changing auth logic).
  - [lib/supabase/client.ts](lib/supabase/client.ts#L1) — `supabaseBrowser()` factory used everywhere in browser code.
  - [app/components/EmpresaProvider.tsx](app/components/EmpresaProvider.tsx#L1) + [lib/auth](lib/auth) + [lib/useEmpresa.ts](lib/useEmpresa.ts#L1) — tenant/empresa context and hooks.
  - Example CRUD pages: [app/fornecedores/page.tsx](app/fornecedores/page.tsx#L1), [app/itens/page.tsx](app/itens/page.tsx#L1), [app/estoque/page.tsx](app/estoque/page.tsx#L1).
  - [supabase/migrations/](supabase/migrations/) — RLS, roles and tenant membership SQL (critical for permission behavior).

  Essential patterns & conventions
  - Client components: add "use client" at the top whenever using hooks, `next/navigation`, or the Supabase client — runtime errors occur otherwise.
  - Supabase client: always use `supabaseBrowser()` from [lib/supabase/client.ts](lib/supabase/client.ts#L1). Prefer `useMemo(() => supabaseBrowser(), [])` to avoid re-creating the client.
  - DB calls are client-side: `supabase.from('table').select(...)`, `.insert(...)`, `.update(...).eq('id', id)`. See [app/fornecedores/page.tsx](app/fornecedores/page.tsx#L1) for a compact example.
  - Tenant scoping: include tenant/empresa filters or use helpers in [lib/db/scopes.ts](lib/db/scopes.ts#L1) and [lib/tenant.ts](lib/tenant.ts#L1) when writing queries.
  - App shell auth flow: `/login` is treated as the public route. `AppShell` redirects unauthenticated users — change it first if you change auth UX.

  API & server-side notes
  - App Router API routes live under `app/api/*` (example: [app/api/os/route.ts](app/api/os/route.ts#L1)).
  - Server helpers exist in [lib/supabase/](lib/supabase) (`admin.ts`, `server.ts`); using them requires proper server env vars — do not hardcode service keys.

  Developer workflows & commands
  - Start dev server: `npm run dev` (localhost:3000).
  - Build: `npm run build`; Start production: `npm start`.
  - Lint: `npm run lint`.
  - DB helper scripts in `scripts/` and `package.json`: `db:backup`, `db:migrate`, `db:restore:dev`.
  - Local env: create `.env.local` with `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.

  Patterns to watch for when editing
  - Always preserve `onAuthStateChange()` subscription cleanup (unsubscribe in effect cleanup) in `AppShell`.
  - Many pages assume client-side session access; if adding server-side endpoints, ensure RBAC/RLS expectations still hold.
  - UI uses Tailwind; keep class patterns consistent with `app/globals.css`.
  - Table names are often hard-coded (e.g., `from('fornecedores')`). When renaming, update all usages.

  Quick examples
  - Instantiating client:
    ```ts
    const supabase = useMemo(() => supabaseBrowser(), []);
    ```
  - Fetch list example:
    ```ts
    const { data, error } = await supabase.from('fornecedores').select('id,nome').order('id', { ascending: false });
    ```

  If anything here is unclear or you want repository-specific examples added (e.g., common `Empresa` query patterns, AppShell auth flow, or an API route example), tell me which file to expand and I'll iterate.

- **Patterns to watch for when editing**:
  - Many components rely on `onAuthStateChange()` cleanup: return `sub.subscription.unsubscribe()` in effect cleanup.
  - `use client` is required when using hooks, `next/navigation` (useRouter, usePathname), or supabase client — forgetting it causes runtime errors.
  - UI uses Tailwind classes; keep class patterns consistent with `globals.css`.

- **Files to reference when working**:
  - `app/components/AppShell.tsx` — auth + navigation
  - `lib/supabase/client.ts` — Supabase factory
  - `app/*/page.tsx` — canonical CRUD examples (`fornecedores`, `itens`, `clientes`, `estoque`, `os`, `mov`)
  - `package.json` — scripts and dependency versions

- **When changing auth or DB logic**:
  - Update `AppShell` redirect rules first, then update each page that assumes a session (they often call `supabase.auth.getSession()` before operations).
  - Ensure env vars are present locally and in CI; do not commit secret keys.

- **Small code example (pattern to follow)**:
  - Fetch list:
    ```ts
    const supabase = useMemo(() => supabaseBrowser(), []);
    const { data, error } = await supabase.from('fornecedores').select('id,nome').order('id', { ascending: false });
    ```

- **Notes / limitations discovered from the codebase**:
  - All Supabase usage is client-side; there's no server-side Supabase client in this project.
  - There are two nested projects in the workspace — be sure to edit files under the intended folder (this file targets the main `estoque-os` project root).

If any of these areas are unclear or you'd like me to add examples for a different page (e.g., `itens` or `os`), tell me which file to expand and I'll iterate.
