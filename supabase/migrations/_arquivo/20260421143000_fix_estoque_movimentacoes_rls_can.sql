begin;

do $$
begin
  if to_regclass('public.estoque') is not null then
    drop policy if exists estoque_select on public.estoque;
    drop policy if exists estoque_insert on public.estoque;
    drop policy if exists estoque_update on public.estoque;
    drop policy if exists estoque_delete on public.estoque;
    drop policy if exists estoque_select_a on public.estoque;
    drop policy if exists estoque_insert_a on public.estoque;
    drop policy if exists estoque_update_a on public.estoque;
    drop policy if exists estoque_delete_a on public.estoque;
    drop policy if exists tenant_empresa_select_estoque on public.estoque;
    drop policy if exists tenant_empresa_insert_estoque on public.estoque;
    drop policy if exists tenant_empresa_update_estoque on public.estoque;
    drop policy if exists tenant_empresa_delete_estoque on public.estoque;

    create policy estoque_select on public.estoque
      for select
      to authenticated
      using (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and (
          public.can('estoque', 'read')
          or public.can('estoque', 'write')
        )
      );

    create policy estoque_insert on public.estoque
      for insert
      to authenticated
      with check (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('estoque', 'write')
      );

    create policy estoque_update on public.estoque
      for update
      to authenticated
      using (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('estoque', 'write')
      )
      with check (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('estoque', 'write')
      );

    create policy estoque_delete on public.estoque
      for delete
      to authenticated
      using (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('admin', 'manage_users')
      );
  end if;

  if to_regclass('public.movimentacoes') is not null then
    drop policy if exists movimentacoes_select on public.movimentacoes;
    drop policy if exists movimentacoes_insert on public.movimentacoes;
    drop policy if exists movimentacoes_update on public.movimentacoes;
    drop policy if exists movimentacoes_delete on public.movimentacoes;
    drop policy if exists tenant_empresa_select_movimentacoes on public.movimentacoes;
    drop policy if exists tenant_empresa_insert_movimentacoes on public.movimentacoes;
    drop policy if exists tenant_empresa_update_movimentacoes on public.movimentacoes;
    drop policy if exists tenant_empresa_delete_movimentacoes on public.movimentacoes;

    create policy movimentacoes_select on public.movimentacoes
      for select
      to authenticated
      using (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and (
          public.can('estoque', 'read')
          or public.can('estoque', 'write')
        )
      );

    create policy movimentacoes_insert on public.movimentacoes
      for insert
      to authenticated
      with check (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('estoque', 'write')
      );

    create policy movimentacoes_update on public.movimentacoes
      for update
      to authenticated
      using (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('admin', 'manage_users')
      )
      with check (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('admin', 'manage_users')
      );

    create policy movimentacoes_delete on public.movimentacoes
      for delete
      to authenticated
      using (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and public.can('admin', 'manage_users')
      );
  end if;
end
$$;

commit;
