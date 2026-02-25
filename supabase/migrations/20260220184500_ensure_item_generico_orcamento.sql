create or replace function public.ensure_orcamento_item_generico(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_codigo text default '9999'
)
returns integer
language plpgsql
security definer
set search_path to 'public', 'a'
set row_security = off
as $$
declare
  v_codigo text := coalesce(nullif(trim(p_codigo), ''), '9999');
  v_item_id integer;
begin
  select i.id
    into v_item_id
    from public.itens i
   where i.tenant_id = p_tenant_id
     and i.empresa_id = p_empresa_id
     and i.ativo = true
     and i.codigo_interno = v_codigo
     and i.mesclado_em_item_id is null
   order by i.id
   limit 1;

  if v_item_id is not null then
    return v_item_id;
  end if;

  insert into public.itens (
    id,
    tenant_id,
    empresa_id,
    codigo_interno,
    nome,
    descricao,
    tipo,
    finalidade,
    unidade_medida,
    controla_estoque,
    ativo,
    preco_unitario,
    custo_ultima_compra,
    created_at,
    updated_at
  )
  values (
    nextval('public.itens_id_seq'),
    p_tenant_id,
    p_empresa_id,
    v_codigo,
    'ITEM GENERICO ORCAMENTO',
    'ITEM GENERICO ORCAMENTO',
    'produto',
    'outros',
    'UN',
    false,
    true,
    0,
    0,
    now(),
    now()
  )
  returning id into v_item_id;

  return v_item_id;
end;
$$;
grant execute on function public.ensure_orcamento_item_generico(uuid, uuid, text) to authenticated;
grant execute on function public.ensure_orcamento_item_generico(uuid, uuid, text) to service_role;
