# Instruções do Copilot (Estoque + OS)

Projeto: Next.js (App Router) + TypeScript + React 19 + Tailwind, com autenticação/DB via Supabase. O app é **multi-tenant (tenant)** e **multi-empresa (empresa)**; a maior parte da lógica de permissão vive no banco (RLS + RPCs).

## Comece por aqui (fluxo real)
- [app/layout.tsx](../app/layout.tsx) faz *best-effort* de capabilities/tenant no server usando [lib/supabase/serverFromAuthHeader.ts](../lib/supabase/serverFromAuthHeader.ts) + `getCapabilities()` e injeta em [components/auth/ClientProviders.tsx](../components/auth/ClientProviders.tsx).
- [app/components/AppShell.tsx](../app/components/AppShell.tsx) faz boot no client: `getSession()` (não bloqueia UI), `onAuthStateChange()` (sempre dar unsubscribe), guard `/login`, e guard de empresa (`/selecionar-empresa` quando `empresas.length > 1` e nenhuma selecionada).

## Tenant e Empresa (não assuma defaults)
- Tenant é garantido por `ensureCurrentTenant(supabase)` em [lib/tenant.ts](../lib/tenant.ts): lê `user_tenant_context` ou pega o 1º membership ativo e chama RPC `set_current_tenant`.
- Empresa é gerenciada por [app/components/EmpresaProvider.tsx](../app/components/EmpresaProvider.tsx): carrega empresas permitidas via [lib/auth/empresa.ts](../lib/auth/empresa.ts), persiste `current_empresa_id` no `localStorage`, e chama RPC `set_current_empresa` ao selecionar.

## Supabase: como usar no app
- Código de UI é majoritariamente client-side; em componentes, instancie com `useMemo(() => supabaseBrowser(), [])` via [lib/supabase/client.ts](../lib/supabase/client.ts).
- Para leituras server-side/API com auth do usuário, use `supabaseFromAuthHeader(req)` (não crie “client global” novo sem necessidade).

## Permissões/capabilities (menus e guards)
- Fonte: [components/auth/PermissionsProvider.tsx](../components/auth/PermissionsProvider.tsx) + [lib/auth/permissions.ts](../lib/auth/permissions.ts). O provider faz cache em `sessionStorage` por `userId:tenantId` e atualiza em background.
- `has(cap)` pode retornar `undefined` enquanto carrega; em UI use `Boolean(has("os.read"))` (padrão do `AppShell`).
- Em mudanças de auth, limpe cache: `clearPermissionCache()` (o `AppShell` já faz isso no listener).

## Banco / migrations / scripts
- RLS multi-tenant/empresa: ver [README.md](../README.md) e `supabase/migrations/` (policies usam `tenant_memberships` e `empresa_memberships`).
- Workflows DB: `npm run db:migrate`, `npm run db:backup`, `npm run db:restore:dev` (detalhes em [docs/DB.md](../docs/DB.md); requer `DATABASE_URL` + ferramentas `pg_dump/pg_restore/psql`).

## Exemplos úteis
- CRUDs de referência ficam em `app/*/page.tsx` (ex.: fornecedores/estoque/os/mov).

## CRUD Page (App Router) — 6 passos
1) `"use client"` (páginas interativas quase sempre são client-side aqui).
2) `const supabase = useMemo(() => supabaseBrowser(), []);`
3) Resolva contexto: `useTenantEmpresa()` (tenant/empresa) e use `applyTenant(query, tenantId)` em selects.
4) `useEffect` para `load()` após `tenantEmpresaLoading` (não faça query sem `tenantId`).
5) Mutations via `.insert/.update/.delete` ou RPC; trate `error.message` no estado (`err`).
6) Após mutation, `await load()`; não assuma que caches/estado local estão corretos.

Micro-template (copiável):
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
		const { data, error } = await applyTenant(
			supabase.from("sua_tabela").select("*")
			, tenantId
		);
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
		// se precisar de empresa obrigatória em RLS, valide `empresaId` antes
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
3) Para contexto tenant/empresa, prefira chamar RPCs já existentes (ex.: `set_current_tenant`, `set_current_empresa`) antes de queries/RPCs que dependem de RLS.
4) Para permissões, use a lógica do banco (RPCs/`can`/RLS), não “if admin” no Node.
5) Retorne `NextResponse.json({ ... }, { status })` com mensagens claras.
6) Em erros de RPC/DB, serialize `error.message` (não jogue objeto cru pro client).

Micro-template (copiável):
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
