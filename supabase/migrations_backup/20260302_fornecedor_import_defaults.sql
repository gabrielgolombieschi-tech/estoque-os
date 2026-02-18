begin;

-- Supplier defaults for XML import
alter table public.fornecedores
  add column if not exists motivo_compra_padrao_id uuid;

-- Optional FK (best-effort) if schema/table exists.
do $$
begin
  if to_regclass('f.motivo_compra') is not null then
    begin
      alter table public.fornecedores
        add constraint fornecedores_motivo_compra_padrao_fk
        foreign key (motivo_compra_padrao_id)
        references f.motivo_compra(id)
        on delete set null;
    exception
      when duplicate_object then
        null;
    end;
  end if;
end $$;

-- Persists defaults chosen on /estoque/importar.
-- SECURITY DEFINER so we can allow xml_import users even if they don't have broad fornecedores UPDATE.
create or replace function public.set_fornecedor_import_defaults(
  p_fornecedor_id bigint,
  p_finalidade public.item_finalidade,
  p_motivo_compra_id uuid
) returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  select f.tenant_id, f.empresa_id
    into v_tenant_id, v_empresa_id
  from public.fornecedores f
  where f.id = p_fornecedor_id
  limit 1;

  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Fornecedor nao encontrado';
  end if;

  -- Ensure the caller belongs to the same tenant/empresa.
  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = v_tenant_id
      and tm.status = 'active'
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if not exists (
    select 1
    from public.empresa_memberships em
    where em.user_id = auth.uid()
      and em.empresa_id = v_empresa_id
      and em.status = 'active'
  ) then
    raise exception 'Empresa nao autorizada';
  end if;

  -- Best-effort: set context so public.can(...) evaluates consistently.
  begin
    perform public.set_current_tenant(v_tenant_id);
  exception
    when undefined_function then
      null;
  end;

  begin
    perform public.set_current_empresa(v_empresa_id);
  exception
    when undefined_function then
      null;
  end;

  if not (
    public.can('xml_import','execute')
    or public.can('cad_fornecedores','write')
    or public.can('estoque','write')
  ) then
    raise exception 'Sem permissao.';
  end if;

  -- Optional validation: if f.motivo_compra exists, ensure the chosen motivo belongs to the same tenant.
  if p_motivo_compra_id is not null and to_regclass('f.motivo_compra') is not null then
    if not exists (
      select 1
      from f.motivo_compra m
      where m.id = p_motivo_compra_id
        and m.tenant_id = v_tenant_id
        and m.ativo = true
        and m.deleted_at is null
    ) then
      raise exception 'Motivo invalido para este tenant.';
    end if;
  end if;

  update public.fornecedores f
  set finalidade_padrao = p_finalidade,
      motivo_compra_padrao_id = p_motivo_compra_id,
      atualizado_em = now()
  where f.id = p_fornecedor_id;
end;
$$;

grant execute on function public.set_fornecedor_import_defaults(bigint, public.item_finalidade, uuid) to authenticated;

commit;
