begin;

-- Migration resiliente: aplica RLS/policies somente quando tabelas/colunas existem.
do $$
declare
  v_has_memberships boolean;
begin
  v_has_memberships := to_regclass('public.tenant_memberships') is not null;

  if to_regclass('public.itens') is not null then
    execute 'alter table public.itens enable row level security';
    if v_has_memberships
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='itens' and column_name='tenant_id') then
      execute 'drop policy if exists tenant_select_itens on public.itens';
      execute 'drop policy if exists tenant_insert_itens on public.itens';
      execute 'drop policy if exists tenant_update_itens on public.itens';
      execute 'drop policy if exists tenant_delete_itens on public.itens';

      execute $p$
        create policy tenant_select_itens on public.itens
          for select
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_insert_itens on public.itens
          for insert
          with check (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_update_itens on public.itens
          for update
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = itens.tenant_id
                and tm.status = 'active'
            )
          )
          with check (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_delete_itens on public.itens
          for delete
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;
    end if;
  end if;

  if to_regclass('public.fornecedores') is not null then
    execute 'alter table public.fornecedores enable row level security';
    if v_has_memberships
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='fornecedores' and column_name='tenant_id') then
      execute 'drop policy if exists tenant_select_fornecedores on public.fornecedores';
      execute 'drop policy if exists tenant_insert_fornecedores on public.fornecedores';
      execute 'drop policy if exists tenant_update_fornecedores on public.fornecedores';
      execute 'drop policy if exists tenant_delete_fornecedores on public.fornecedores';

      execute $p$
        create policy tenant_select_fornecedores on public.fornecedores
          for select
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fornecedores.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_insert_fornecedores on public.fornecedores
          for insert
          with check (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fornecedores.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_update_fornecedores on public.fornecedores
          for update
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fornecedores.tenant_id
                and tm.status = 'active'
            )
          )
          with check (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fornecedores.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_delete_fornecedores on public.fornecedores
          for delete
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fornecedores.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;
    end if;
  end if;

  if to_regclass('public.estoque') is not null then
    execute 'alter table public.estoque enable row level security';
    if v_has_memberships
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='estoque' and column_name='tenant_id')
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='estoque' and column_name='empresa_id') then
      execute 'drop policy if exists tenant_empresa_select_estoque on public.estoque';
      execute 'drop policy if exists tenant_empresa_insert_estoque on public.estoque';
      execute 'drop policy if exists tenant_empresa_update_estoque on public.estoque';
      execute 'drop policy if exists tenant_empresa_delete_estoque on public.estoque';

      execute $p$
        create policy tenant_empresa_select_estoque on public.estoque
          for select
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = estoque.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_insert_estoque on public.estoque
          for insert
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = estoque.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_update_estoque on public.estoque
          for update
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = estoque.tenant_id
                and tm.status = 'active'
            )
          )
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = estoque.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_delete_estoque on public.estoque
          for delete
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = estoque.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;
    end if;
  end if;

  if to_regclass('public.movimentacoes') is not null then
    execute 'alter table public.movimentacoes enable row level security';
    if v_has_memberships
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='tenant_id')
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='empresa_id') then
      execute 'drop policy if exists tenant_empresa_select_movimentacoes on public.movimentacoes';
      execute 'drop policy if exists tenant_empresa_insert_movimentacoes on public.movimentacoes';
      execute 'drop policy if exists tenant_empresa_update_movimentacoes on public.movimentacoes';
      execute 'drop policy if exists tenant_empresa_delete_movimentacoes on public.movimentacoes';

      execute $p$
        create policy tenant_empresa_select_movimentacoes on public.movimentacoes
          for select
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = movimentacoes.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_insert_movimentacoes on public.movimentacoes
          for insert
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = movimentacoes.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_update_movimentacoes on public.movimentacoes
          for update
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = movimentacoes.tenant_id
                and tm.status = 'active'
            )
          )
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = movimentacoes.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_delete_movimentacoes on public.movimentacoes
          for delete
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = movimentacoes.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;
    end if;
  end if;

  if to_regclass('public.nf_entrada') is not null then
    execute 'alter table public.nf_entrada enable row level security';
    if v_has_memberships
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='nf_entrada' and column_name='tenant_id')
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='nf_entrada' and column_name='empresa_id') then
      execute 'drop policy if exists tenant_empresa_select_nf_entrada on public.nf_entrada';
      execute 'drop policy if exists tenant_empresa_insert_nf_entrada on public.nf_entrada';
      execute 'drop policy if exists tenant_empresa_update_nf_entrada on public.nf_entrada';
      execute 'drop policy if exists tenant_empresa_delete_nf_entrada on public.nf_entrada';

      execute $p$
        create policy tenant_empresa_select_nf_entrada on public.nf_entrada
          for select
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_insert_nf_entrada on public.nf_entrada
          for insert
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_update_nf_entrada on public.nf_entrada
          for update
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada.tenant_id
                and tm.status = 'active'
            )
          )
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_delete_nf_entrada on public.nf_entrada
          for delete
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;
    end if;
  end if;

  if to_regclass('public.nf_entrada_itens') is not null then
    execute 'alter table public.nf_entrada_itens enable row level security';
    if v_has_memberships
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='nf_entrada_itens' and column_name='tenant_id') then
      execute 'drop policy if exists tenant_select_nf_entrada_itens on public.nf_entrada_itens';
      execute 'drop policy if exists tenant_insert_nf_entrada_itens on public.nf_entrada_itens';
      execute 'drop policy if exists tenant_update_nf_entrada_itens on public.nf_entrada_itens';
      execute 'drop policy if exists tenant_delete_nf_entrada_itens on public.nf_entrada_itens';

      execute $p$
        create policy tenant_select_nf_entrada_itens on public.nf_entrada_itens
          for select
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_insert_nf_entrada_itens on public.nf_entrada_itens
          for insert
          with check (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_update_nf_entrada_itens on public.nf_entrada_itens
          for update
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada_itens.tenant_id
                and tm.status = 'active'
            )
          )
          with check (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_delete_nf_entrada_itens on public.nf_entrada_itens
          for delete
          using (
            exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = nf_entrada_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;
    end if;
  end if;

  if to_regclass('public.fiscal_itens') is not null then
    execute 'alter table public.fiscal_itens enable row level security';
    if v_has_memberships
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='fiscal_itens' and column_name='tenant_id')
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name='fiscal_itens' and column_name='empresa_id') then
      execute 'drop policy if exists tenant_empresa_select_fiscal_itens on public.fiscal_itens';
      execute 'drop policy if exists tenant_empresa_insert_fiscal_itens on public.fiscal_itens';
      execute 'drop policy if exists tenant_empresa_update_fiscal_itens on public.fiscal_itens';
      execute 'drop policy if exists tenant_empresa_delete_fiscal_itens on public.fiscal_itens';

      execute $p$
        create policy tenant_empresa_select_fiscal_itens on public.fiscal_itens
          for select
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fiscal_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_insert_fiscal_itens on public.fiscal_itens
          for insert
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fiscal_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_update_fiscal_itens on public.fiscal_itens
          for update
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fiscal_itens.tenant_id
                and tm.status = 'active'
            )
          )
          with check (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fiscal_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;

      execute $p$
        create policy tenant_empresa_delete_fiscal_itens on public.fiscal_itens
          for delete
          using (
            empresa_id is not null
            and exists (
              select 1
              from public.tenant_memberships tm
              where tm.user_id = auth.uid()
                and tm.tenant_id = fiscal_itens.tenant_id
                and tm.status = 'active'
            )
          )
      $p$;
    end if;
  end if;
end $$;

commit;
