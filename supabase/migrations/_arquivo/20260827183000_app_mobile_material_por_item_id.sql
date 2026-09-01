begin;

-- Mantém as RPCs por codigo_interno para versoes anteriores do app.
-- As novas RPCs usam o mesmo identificador numerico exibido no estoque e no orcamento.
create or replace function public.app_buscar_material_por_item_id(p_item_id integer)
returns table (
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade_disponivel numeric,
  disponivel boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if p_item_id is null or p_item_id <= 0 then
    raise exception 'Informe o ID numérico do item.';
  end if;

  return query
  select
    item.id,
    item.codigo_interno::text,
    coalesce(item.nome, item.descricao)::text,
    item.unidade_medida::text,
    coalesce(estoque.quantidade_atual, 0)::numeric,
    coalesce(estoque.quantidade_atual, 0) > 0
  from public.itens item
  left join public.estoque estoque
    on estoque.tenant_id = item.tenant_id
   and estoque.empresa_id = item.empresa_id
   and estoque.item_id = item.id
  where item.id = p_item_id
    and item.tenant_id = v_tenant_id
    and item.empresa_id = v_empresa_id
    and item.ativo is true
    and item.tipo = 'produto'
    and item.controla_estoque is true;
end;
$$;

create or replace function public.app_lancar_material_os_por_item_id(
  p_os_id integer,
  p_item_id integer,
  p_quantidade numeric,
  p_observacao text default null
)
returns table (
  os_item_id integer,
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade numeric,
  saldo_restante numeric,
  nao_cobrado boolean,
  custo_medio_ausente boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_os public.ordens_servico%rowtype;
  v_item public.itens%rowtype;
  v_os_item public.os_itens%rowtype;
  v_saldo_atual numeric := 0;
  v_valor_unitario numeric := 0;
  v_observacao text := nullif(btrim(p_observacao), '');
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select usuario_empresa.papel
    into v_papel
  from a.usuario usuario
  join a.usuario_empresa usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = v_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if upper(coalesce(v_papel, '')) not in ('ADMIN', 'DIRETOR', 'COORDENACAO', 'TECNICO') then
    raise exception 'Somente técnico, coordenação, diretor ou admin podem lançar material na OS.';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Informe uma quantidade maior que zero.';
  end if;

  if p_item_id is null or p_item_id <= 0 then
    raise exception 'Informe o ID numérico do item.';
  end if;

  select os.*
    into v_os
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
  for update;

  if not found then
    raise exception 'A OS informada não existe ou não pertence à empresa atual.';
  end if;

  if coalesce(v_os.status_fluxo, public.mapear_status_legado_para_fluxo(v_os.status))
       not in ('em_andamento', 'em_andamento_garantia') then
    raise exception 'Só é permitido lançar material em uma OS em andamento.';
  end if;

  select item.*
    into v_item
  from public.itens item
  where item.id = p_item_id
    and item.tenant_id = v_tenant_id
    and item.empresa_id = v_empresa_id
    and item.ativo is true
    and item.tipo = 'produto'
    and item.controla_estoque is true;

  if not found then
    raise exception 'O ID informado não corresponde a um produto ativo com controle de estoque.';
  end if;

  select estoque.quantidade_atual
    into v_saldo_atual
  from public.estoque estoque
  where estoque.tenant_id = v_tenant_id
    and estoque.empresa_id = v_empresa_id
    and estoque.item_id = v_item.id
  for update;

  v_saldo_atual := coalesce(v_saldo_atual, 0);
  if v_saldo_atual < p_quantidade then
    raise exception 'Estoque insuficiente para este lançamento. Disponível: %; solicitado: %.', v_saldo_atual, p_quantidade;
  end if;

  v_valor_unitario := coalesce(v_item.custo_medio, 0);

  insert into public.os_itens (
    tenant_id,
    empresa_id,
    os_id,
    item_id,
    quantidade,
    valor_unitario,
    valor_total,
    desconto_percentual,
    desconto_valor,
    observacoes,
    baixa_estoque,
    quantidade_baixada,
    criado_em
  ) values (
    v_tenant_id,
    v_empresa_id,
    p_os_id,
    v_item.id,
    p_quantidade,
    v_valor_unitario,
    p_quantidade * v_valor_unitario,
    0,
    0,
    v_observacao,
    true,
    p_quantidade,
    (now() at time zone 'UTC')
  )
  returning * into v_os_item;

  insert into public.movimentacoes (
    tenant_id,
    empresa_id,
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    origem_os_id,
    created_at
  ) values (
    v_tenant_id,
    v_empresa_id,
    v_item.id,
    'saida',
    p_quantidade,
    'Material lançado pelo app na OS ' || coalesce(nullif(btrim(v_os.numero_os), ''), v_os.os_num::text, v_os.id::text),
    v_auth_uid::text,
    now(),
    p_os_id,
    now()
  );

  update public.ordens_servico os
     set valor_total = coalesce((
           select sum(os_item.valor_total)
           from public.os_itens os_item
           where os_item.os_id = p_os_id
             and os_item.tenant_id = v_tenant_id
             and os_item.empresa_id = v_empresa_id
         ), 0),
         atualizado_em = now()
   where os.id = p_os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id;

  return query
  select
    v_os_item.id,
    v_item.id,
    v_item.codigo_interno::text,
    coalesce(v_item.nome, v_item.descricao)::text,
    v_item.unidade_medida::text,
    v_os_item.quantidade,
    (v_saldo_atual - p_quantidade)::numeric,
    public.os_lancamento_nao_cobrado(
      v_tenant_id,
      v_empresa_id,
      p_os_id,
      v_os_item.criado_em
    ),
    v_item.custo_medio is null;
end;
$$;

revoke all on function public.app_buscar_material_por_item_id(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.app_lancar_material_os_por_item_id(integer, integer, numeric, text)
  from public, anon, authenticated, service_role;

grant execute on function public.app_buscar_material_por_item_id(integer) to authenticated;
grant execute on function public.app_lancar_material_os_por_item_id(integer, integer, numeric, text) to authenticated;

notify pgrst, 'reload schema';

commit;
