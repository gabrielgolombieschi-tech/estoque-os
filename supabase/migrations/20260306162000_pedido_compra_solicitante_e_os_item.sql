begin;

alter table if exists m.pedido_compra
  add column if not exists solicitante_usuario_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fk_pedido_compra__solicitante_usuario_id__a_usuario'
  ) then
    alter table m.pedido_compra
      add constraint fk_pedido_compra__solicitante_usuario_id__a_usuario
      foreign key (solicitante_usuario_id)
      references a.usuario(id)
      on update restrict
      on delete set null;
  end if;
end
$$;

create index if not exists idx_pedido_compra__tenant_empresa_solicitante
  on m.pedido_compra (tenant_id, empresa_id, solicitante_usuario_id)
  where deleted_at is null;

alter table if exists m.pedido_compra_item
  add column if not exists origem_os_id integer;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fk_pedido_compra_item__origem_os_id__ordens_servico'
  ) then
    alter table m.pedido_compra_item
      add constraint fk_pedido_compra_item__origem_os_id__ordens_servico
      foreign key (tenant_id, empresa_id, origem_os_id)
      references public.ordens_servico(tenant_id, empresa_id, id)
      on update restrict
      on delete set null;
  end if;
end
$$;

create index if not exists idx_pedido_compra_item__tenant_empresa_origem_os
  on m.pedido_compra_item (tenant_id, empresa_id, origem_os_id)
  where deleted_at is null;

commit;
