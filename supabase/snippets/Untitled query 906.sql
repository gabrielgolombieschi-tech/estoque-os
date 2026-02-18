create table if not exists public._teste_migrations (
  id bigserial primary key,
  created_at timestamptz not null default now()
);
