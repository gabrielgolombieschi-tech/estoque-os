-- Cria tabela de cargos com tipo_gestao para mapeamento automático de gestão de projetos

create table if not exists public.cargos (
  id        bigserial primary key,
  tenant_id uuid        not null,
  nome      varchar(100) not null,
  tipo_gestao varchar(30) null,   -- 'projeto_eletrico' | 'projeto_mecanico' | 'projeto_seguranca' | 'projeto_software' | 'execucao_eletrica' | 'execucao_mecanica'
  ativo     boolean     not null default true,
  criado_em timestamptz not null default now(),
  constraint cargos_tenant_nome_unique unique (tenant_id, nome)
);

alter table public.cargos enable row level security;

drop policy if exists cargos_select on public.cargos;
create policy cargos_select on public.cargos
  for select to authenticated
  using (tenant_id = public.current_tenant_id());

drop policy if exists cargos_insert on public.cargos;
create policy cargos_insert on public.cargos
  for insert to authenticated
  with check (tenant_id = public.current_tenant_id());

drop policy if exists cargos_update on public.cargos;
create policy cargos_update on public.cargos
  for update to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

drop policy if exists cargos_delete on public.cargos;
create policy cargos_delete on public.cargos
  for delete to authenticated
  using (tenant_id = public.current_tenant_id());

notify pgrst, 'reload schema';
