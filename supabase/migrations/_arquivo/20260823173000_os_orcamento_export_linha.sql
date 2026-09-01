begin;

create table if not exists public.os_orcamento_export_linha (
  id bigint generated always as identity primary key,
  tenant_id uuid not null,
  empresa_id uuid not null,
  os_id integer not null,
  origem text not null check (origem in ('os_item', 'hh_lancamento', 'apontamento')),
  origem_id text not null,
  orcamento_id uuid not null,
  orcamento_item_id uuid not null,
  criado_em timestamptz not null default now(),
  criado_por text null,
  constraint uq_os_orcamento_export_linha unique (tenant_id, origem, origem_id)
);

comment on table public.os_orcamento_export_linha is
  'Rastreia quais linhas de origem (os_itens, hh_lancamentos, apontamentos_horas) ja foram exportadas para um orcamento via fn_gerar_ou_atualizar_orcamento_de_os, para permitir gerar/atualizar o mesmo orcamento sem duplicar. origem_id fica em text porque os ids das 3 origens tem tipos diferentes (os_itens=integer, hh_lancamentos=bigint, apontamentos_horas=uuid). Insert-only por desenho: apontamentos_horas com status=fechado bloqueiam UPDATE via trigger (fn_apontamento_bloquear_fechado), entao nao daria pra marcar "exportado" com uma coluna na propria linha.';

create index if not exists ix_os_orcamento_export_linha_os on public.os_orcamento_export_linha (os_id, origem);

alter table public.os_orcamento_export_linha enable row level security;

drop policy if exists enforce_active_empresa_scope on public.os_orcamento_export_linha;
create policy enforce_active_empresa_scope on public.os_orcamento_export_linha
  as restrictive for all to authenticated
  using (
    tenant_id = (select public.current_tenant_id())
    and empresa_id = (select public.current_empresa_id())
    and (select public.has_active_empresa_access(public.current_tenant_id(), public.current_empresa_id()))
  )
  with check (
    tenant_id = (select public.current_tenant_id())
    and empresa_id = (select public.current_empresa_id())
    and (select public.has_active_empresa_access(public.current_tenant_id(), public.current_empresa_id()))
  );

grant select on public.os_orcamento_export_linha to authenticated;
grant select, insert on public.os_orcamento_export_linha to service_role;

notify pgrst, 'reload schema';

commit;
