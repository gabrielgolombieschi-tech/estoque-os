# Copilot instructions for Estoque + OS

Purpose: give AI coding agents the minimal, precise knowledge to be immediately productive in this repo.

- **Big picture**: This is a Next.js (App Router) TypeScript app using client-side Supabase for auth and DB. UI pages live under `app/*` and most interactive pages are client components (`"use client"`). `AppShell` (app/components/AppShell.tsx) is the auth gate and top-level layout wrapper.

- **Where to start reading**:
  - `app/layout.tsx` — root layout that mounts `AppShell`.
  - `app/components/AppShell.tsx` — handles auth state, redirects between `/login` and private pages, mounts header/nav.
  - `lib/supabase/client.ts` — single exported helper `supabaseBrowser()` used everywhere to create the Supabase client.
  - example pages: `app/fornecedores/page.tsx`, `app/itens/page.tsx`, `app/estoque/page.tsx` — show typical DB queries and insert/update flows.
  - `package.json` — dev/build/start scripts and dependencies.

- **Auth & routing pattern (critical)**:
  - `AppShell` calls `supabase.auth.getSession()` and subscribes to `onAuthStateChange()` to redirect to `/login` when unauthenticated.
  - The login page is `/login` and is treated as the only public route in `AppShell` (`const isPublic = pathname === "/login"`).
  - When changing auth logic, update `AppShell` to preserve the redirect rules.

- **Supabase usage patterns**:
  - Client factory: `lib/supabase/client.ts` exports `supabaseBrowser()` which reads `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
  - Pages instantiate the client with `useMemo(() => supabaseBrowser(), [])` or directly in client components.
  - Typical DB calls: `supabase.from("table").select(...).order(...)`, `.insert(...)`, `.update(...).eq("id", id)` — see `app/fornecedores/page.tsx` for a concise example.
  - All Supabase calls in this app are performed client-side; avoid creating server-side Supabase calls unless adding a server client and env vars safely.

- **Developer workflows / commands**:
  - Dev server: `npm run dev` (starts Next dev server on http://localhost:3000).
  - Build: `npm run build`; Production start: `npm start`.
  - Lint: `npm run lint` (uses `eslint`).
  - Environment: create `.env.local` with `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` for local auth/data.

- **Project conventions**:
  - Use React client components (`"use client"`) for pages that call Supabase or use hooks. Many pages explicitly include `"use client"` at the top.
  - Reuse `supabaseBrowser()` rather than calling `createClient` inline; prefer `useMemo` to avoid re-creating the client on each render.
  - UI shell/navigation is centralized in `AppShell`. Add new top-level routes under `app/` and link them in `AppShell` to show in the header.
  - Keep DB table names hard-coded in pages (e.g., `from('fornecedores')`) — when refactoring, update usages across `app/*` pages.

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
