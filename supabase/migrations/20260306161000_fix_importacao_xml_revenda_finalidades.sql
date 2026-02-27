begin;

create or replace function public.fn_importacao_xml__itens_auto_cadastrar_finalidades(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns public.item_finalidade[]
language sql
stable
security definer
set search_path to 'public'
set row_security to 'off'
as $$
  select coalesce(
    (
      select p.itens_auto_cadastrar_finalidades
      from public.parametro_importacao_xml p
      where p.tenant_id = p_tenant_id
        and p.empresa_id = p_empresa_id
        and p.deleted_at is null
      limit 1
    ),
    array['materia_prima'::public.item_finalidade, 'revenda'::public.item_finalidade]
  );
$$;

create or replace function public.fn_importacao_xml__itens_vincular_finalidades(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns public.item_finalidade[]
language sql
stable
security definer
set search_path to 'public'
set row_security to 'off'
as $$
  select coalesce(
    (
      select p.itens_vincular_finalidades
      from public.parametro_importacao_xml p
      where p.tenant_id = p_tenant_id
        and p.empresa_id = p_empresa_id
        and p.deleted_at is null
      limit 1
    ),
    array['materia_prima'::public.item_finalidade, 'revenda'::public.item_finalidade]
  );
$$;

update public.parametro_importacao_xml p
set itens_auto_cadastrar_finalidades = case
      when p.itens_auto_cadastrar_finalidades is null then array['materia_prima'::public.item_finalidade, 'revenda'::public.item_finalidade]
      when not ('revenda'::public.item_finalidade = any(p.itens_auto_cadastrar_finalidades)) then p.itens_auto_cadastrar_finalidades || 'revenda'::public.item_finalidade
      else p.itens_auto_cadastrar_finalidades
    end,
    itens_vincular_finalidades = case
      when p.itens_vincular_finalidades is null then array['materia_prima'::public.item_finalidade, 'revenda'::public.item_finalidade]
      when not ('revenda'::public.item_finalidade = any(p.itens_vincular_finalidades)) then p.itens_vincular_finalidades || 'revenda'::public.item_finalidade
      else p.itens_vincular_finalidades
    end,
    updated_at = now()
where p.deleted_at is null;

commit;

