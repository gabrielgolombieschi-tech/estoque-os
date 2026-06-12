begin;

create table if not exists public.cliente_contatos (
  id bigserial primary key,
  tenant_id uuid not null,
  empresa_id uuid not null,
  cliente_id integer not null references public.clientes(id) on delete cascade,
  nome text,
  setor text,
  email text,
  telefone text,
  ativo boolean not null default true,
  principal boolean not null default false,
  vezes_usado integer not null default 0,
  ultimo_uso_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_cliente_contatos__tenant_empresa_cliente
  on public.cliente_contatos (tenant_id, empresa_id, cliente_id);

create index if not exists idx_cliente_contatos__tenant_empresa_cliente_email
  on public.cliente_contatos (tenant_id, empresa_id, cliente_id, lower(btrim(email)));

create unique index if not exists uq_cliente_contatos__tenant_empresa_cliente_email
  on public.cliente_contatos (tenant_id, empresa_id, cliente_id, lower(btrim(email)))
  where email is not null and btrim(email) <> '';

alter table m.orcamento
  add column if not exists solicitante_nome text,
  add column if not exists solicitante_setor text,
  add column if not exists solicitante_email text,
  add column if not exists solicitante_telefone text;

commit;
