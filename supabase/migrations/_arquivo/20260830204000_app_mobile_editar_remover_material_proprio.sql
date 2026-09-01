begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Entradas sem custo explicito sao estornos/ajustes de quantidade e nao podem
-- alterar custo medio, custo da ultima compra nem a data da ultima compra.
-- Entradas fiscais e manuais que informam custo continuam com a regra atual.
create or replace function public.apply_movimentacao_estoque()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric;
  v_saldo_anterior numeric;
  v_custo_medio numeric;
  v_custo_entrada numeric;
  v_novo_custo numeric;
  v_data_mov timestamp without time zone;
begin
  if new.item_id is null then
    return new;
  end if;

  v_saldo_anterior := 0;
  select coalesce(e.quantidade_atual, 0)
    into v_saldo_anterior
  from public.estoque e
  where e.tenant_id = new.tenant_id
    and e.empresa_id = new.empresa_id
    and e.item_id = new.item_id
  limit 1;

  v_delta := case when new.tipo = 'saida' then -1 else 1 end * coalesce(new.quantidade, 0);

  insert into public.estoque(tenant_id, empresa_id, item_id, quantidade_atual)
  values (new.tenant_id, new.empresa_id, new.item_id, v_delta)
  on conflict (tenant_id, empresa_id, item_id) do update
    set quantidade_atual = coalesce(public.estoque.quantidade_atual, 0) + v_delta;

  if new.tipo = 'entrada'
     and coalesce(new.quantidade, 0) > 0
     and (new.custo_unitario_real is not null or new.custo_unitario_bruto is not null) then
    select coalesce(i.custo_medio, 0)
      into v_custo_medio
    from public.itens i
    where i.id = new.item_id
      and i.tenant_id = new.tenant_id
      and i.empresa_id = new.empresa_id
    limit 1;

    v_custo_entrada := coalesce(new.custo_unitario_real, new.custo_unitario_bruto, 0);
    v_novo_custo := case
      when (v_saldo_anterior + new.quantidade) > 0
        then ((v_saldo_anterior * v_custo_medio) + (new.quantidade * v_custo_entrada)) / (v_saldo_anterior + new.quantidade)
      else v_custo_entrada
    end;

    v_data_mov := coalesce(new.data_movimentacao, now()::timestamp without time zone);

    update public.itens
    set custo_ultima_compra = v_custo_entrada,
        custo_medio = v_novo_custo,
        data_ultima_compra = v_data_mov,
        preco_unitario = case
          when new.origem_nf_entrada_id is not null and v_custo_entrada > 0
            then v_custo_entrada
          else preco_unitario
        end,
        data_atualizacao_preco = case
          when new.origem_nf_entrada_id is not null and v_custo_entrada > 0
            then v_data_mov
          else data_atualizacao_preco
        end
    where id = new.item_id
      and tenant_id = new.tenant_id
      and empresa_id = new.empresa_id;
  end if;

  return new;
end;
$$;

drop function public.app_listar_materiais_os(integer);

create function public.app_listar_materiais_os(p_os_id integer)
returns table (
  id integer,
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade numeric,
  observacoes text,
  registrado_por_nome text,
  criado_em timestamp without time zone,
  nao_cobrado boolean,
  pode_editar boolean,
  motivo_bloqueio text
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
  v_status_fluxo text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  select coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status))
    into v_status_fluxo
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and os.tipo_documento = 'OS';

  if not found then
    raise exception 'A OS informada nao existe ou nao pertence a empresa atual.';
  end if;

  return query
  select
    os_item.id,
    os_item.item_id,
    item.codigo_interno::text,
    coalesce(item.nome, item.descricao)::text,
    item.unidade_medida::text,
    os_item.quantidade,
    os_item.observacoes,
    os_item.registrado_por_nome,
    os_item.criado_em,
    public.os_lancamento_nao_cobrado(
      v_tenant_id,
      v_empresa_id,
      p_os_id,
      os_item.criado_em
    ),
    (
      os_item.registrado_por = v_auth_uid
      and v_status_fluxo in ('em_andamento', 'em_andamento_garantia')
      and abs(coalesce(os_item.quantidade_baixada, 0) - os_item.quantidade) < 0.0005
      and exists (
        select 1
        from public.movimentacoes mov
        where mov.tenant_id = os_item.tenant_id
          and mov.empresa_id = os_item.empresa_id
          and mov.origem_os_id = os_item.os_id
          and mov.item_id = os_item.item_id
          and mov.tipo = 'saida'
          and mov.realizado_por = v_auth_uid::text
          and mov.motivo like 'Material lançado pelo app na OS %'
          and abs(extract(epoch from (mov.data_movimentacao - os_item.criado_em))) <= 600
      )
    ) as pode_editar,
    case
      when os_item.registrado_por is distinct from v_auth_uid then null
      when v_status_fluxo not in ('em_andamento', 'em_andamento_garantia')
        then 'A OS precisa estar em andamento para corrigir materiais.'
      when abs(coalesce(os_item.quantidade_baixada, 0) - os_item.quantidade) >= 0.0005
        then 'Este item possui baixa parcial e precisa ser ajustado no ERP Web.'
      when not exists (
        select 1
        from public.movimentacoes mov
        where mov.tenant_id = os_item.tenant_id
          and mov.empresa_id = os_item.empresa_id
          and mov.origem_os_id = os_item.os_id
          and mov.item_id = os_item.item_id
          and mov.tipo = 'saida'
          and mov.realizado_por = v_auth_uid::text
          and mov.motivo like 'Material lançado pelo app na OS %'
          and abs(extract(epoch from (mov.data_movimentacao - os_item.criado_em))) <= 600
      ) then 'Somente lancamentos feitos pelo app podem ser corrigidos aqui.'
      else null
    end as motivo_bloqueio
  from public.os_itens os_item
  join public.itens item
    on item.id = os_item.item_id
   and item.tenant_id = os_item.tenant_id
   and item.empresa_id = os_item.empresa_id
  where os_item.os_id = p_os_id
    and os_item.tenant_id = v_tenant_id
    and os_item.empresa_id = v_empresa_id
    and item.tipo = 'produto'
  order by os_item.criado_em desc, os_item.id desc;
end;
$$;

create or replace function public.app_editar_material_os(
  p_os_item_id integer,
  p_quantidade numeric,
  p_observacao text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_os_item public.os_itens%rowtype;
  v_os public.ordens_servico%rowtype;
  v_item public.itens%rowtype;
  v_quantidade numeric(14,3);
  v_baixada_atual numeric(14,3);
  v_delta numeric(14,3);
  v_saldo numeric(14,3) := 0;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Informe uma quantidade maior que zero.';
  end if;
  v_quantidade := round(p_quantidade, 3);

  select os_item.*
    into v_os_item
  from public.os_itens os_item
  where os_item.id = p_os_item_id
    and os_item.tenant_id = v_tenant_id
    and os_item.empresa_id = v_empresa_id
  for update;

  if not found then
    raise exception 'O material informado nao existe na empresa atual.';
  end if;

  if v_os_item.registrado_por is distinct from v_auth_uid then
    raise exception 'Somente o usuario que lancou o material pode edita-lo.';
  end if;

  select os.*
    into v_os
  from public.ordens_servico os
  where os.id = v_os_item.os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and os.tipo_documento = 'OS'
  for update;

  if not found then
    raise exception 'A OS do material nao existe ou nao e uma OS operacional.';
  end if;
  if coalesce(v_os.status_fluxo, public.mapear_status_legado_para_fluxo(v_os.status))
       not in ('em_andamento', 'em_andamento_garantia') then
    raise exception 'A OS precisa estar em andamento para corrigir materiais.';
  end if;

  if not exists (
    select 1
    from public.movimentacoes mov
    where mov.tenant_id = v_tenant_id
      and mov.empresa_id = v_empresa_id
      and mov.origem_os_id = v_os_item.os_id
      and mov.item_id = v_os_item.item_id
      and mov.tipo = 'saida'
      and mov.realizado_por = v_auth_uid::text
      and mov.motivo like 'Material lançado pelo app na OS %'
      and abs(extract(epoch from (mov.data_movimentacao - v_os_item.criado_em))) <= 600
  ) then
    raise exception 'Somente lancamentos feitos pelo app podem ser corrigidos aqui.';
  end if;

  v_baixada_atual := least(coalesce(v_os_item.quantidade_baixada, 0), v_os_item.quantidade);
  if abs(v_baixada_atual - v_os_item.quantidade) >= 0.0005 then
    raise exception 'Este item possui baixa parcial e precisa ser ajustado no ERP Web.';
  end if;

  select item.*
    into v_item
  from public.itens item
  where item.id = v_os_item.item_id
    and item.tenant_id = v_tenant_id
    and item.empresa_id = v_empresa_id
    and item.tipo = 'produto'
    and item.controla_estoque is true;

  if not found then
    raise exception 'O material nao possui controle de estoque valido.';
  end if;

  v_delta := v_quantidade - v_baixada_atual;

  if v_delta > 0 then
    select coalesce(estoque.quantidade_atual, 0)
      into v_saldo
    from public.estoque estoque
    where estoque.tenant_id = v_tenant_id
      and estoque.empresa_id = v_empresa_id
      and estoque.item_id = v_os_item.item_id
    for update;

    v_saldo := coalesce(v_saldo, 0);
    if v_saldo < v_delta then
      raise exception 'Estoque insuficiente para aumentar o lancamento. Disponivel: %; adicional: %.', v_saldo, v_delta;
    end if;

    insert into public.movimentacoes (
      tenant_id, empresa_id, item_id, tipo, quantidade, motivo,
      realizado_por, data_movimentacao, origem_os_id, created_at
    ) values (
      v_tenant_id, v_empresa_id, v_os_item.item_id, 'saida', v_delta,
      'Ajuste de quantidade de material pelo autor na OS ' || coalesce(nullif(btrim(v_os.numero_os), ''), v_os.os_num::text, v_os.id::text),
      v_auth_uid::text, now(), v_os_item.os_id, now()
    );
  elsif v_delta < 0 then
    insert into public.movimentacoes (
      tenant_id, empresa_id, item_id, tipo, quantidade, motivo,
      realizado_por, data_movimentacao, origem_os_id, created_at
    ) values (
      v_tenant_id, v_empresa_id, v_os_item.item_id, 'entrada', abs(v_delta),
      'Devolucao por ajuste de material pelo autor na OS ' || coalesce(nullif(btrim(v_os.numero_os), ''), v_os.os_num::text, v_os.id::text),
      v_auth_uid::text, now(), v_os_item.os_id, now()
    );
  end if;

  update public.os_itens os_item
     set quantidade = v_quantidade,
         quantidade_baixada = v_quantidade,
         baixa_estoque = true,
         valor_total = (v_quantidade * coalesce(v_os_item.valor_unitario, 0)) - coalesce(v_os_item.desconto_valor, 0),
         observacoes = nullif(btrim(p_observacao), '')
   where os_item.id = v_os_item.id
     and os_item.tenant_id = v_tenant_id
     and os_item.empresa_id = v_empresa_id;

  update public.ordens_servico os
     set valor_total = coalesce((
           select sum(item_os.valor_total)
           from public.os_itens item_os
           where item_os.os_id = v_os_item.os_id
             and item_os.tenant_id = v_tenant_id
             and item_os.empresa_id = v_empresa_id
         ), 0),
         atualizado_em = now()
   where os.id = v_os_item.os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id;

  return jsonb_build_object(
    'id', v_os_item.id,
    'quantidade', v_quantidade,
    'saldo_restante', case when v_delta > 0 then v_saldo - v_delta else null end
  );
end;
$$;

create or replace function public.app_remover_material_os(p_os_item_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_os_item public.os_itens%rowtype;
  v_os public.ordens_servico%rowtype;
  v_quantidade_estorno numeric(14,3);
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  select os_item.*
    into v_os_item
  from public.os_itens os_item
  where os_item.id = p_os_item_id
    and os_item.tenant_id = v_tenant_id
    and os_item.empresa_id = v_empresa_id
  for update;

  if not found then
    raise exception 'O material informado nao existe na empresa atual.';
  end if;
  if v_os_item.registrado_por is distinct from v_auth_uid then
    raise exception 'Somente o usuario que lancou o material pode remove-lo.';
  end if;

  select os.*
    into v_os
  from public.ordens_servico os
  where os.id = v_os_item.os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and os.tipo_documento = 'OS'
  for update;

  if not found then
    raise exception 'A OS do material nao existe ou nao e uma OS operacional.';
  end if;
  if coalesce(v_os.status_fluxo, public.mapear_status_legado_para_fluxo(v_os.status))
       not in ('em_andamento', 'em_andamento_garantia') then
    raise exception 'A OS precisa estar em andamento para remover materiais.';
  end if;

  if not exists (
    select 1
    from public.movimentacoes mov
    where mov.tenant_id = v_tenant_id
      and mov.empresa_id = v_empresa_id
      and mov.origem_os_id = v_os_item.os_id
      and mov.item_id = v_os_item.item_id
      and mov.tipo = 'saida'
      and mov.realizado_por = v_auth_uid::text
      and mov.motivo like 'Material lançado pelo app na OS %'
      and abs(extract(epoch from (mov.data_movimentacao - v_os_item.criado_em))) <= 600
  ) then
    raise exception 'Somente lancamentos feitos pelo app podem ser removidos aqui.';
  end if;

  v_quantidade_estorno := least(coalesce(v_os_item.quantidade_baixada, 0), v_os_item.quantidade);
  if abs(v_quantidade_estorno - v_os_item.quantidade) >= 0.0005 then
    raise exception 'Este item possui baixa parcial e precisa ser ajustado no ERP Web.';
  end if;

  if v_quantidade_estorno > 0 then
    insert into public.movimentacoes (
      tenant_id, empresa_id, item_id, tipo, quantidade, motivo,
      realizado_por, data_movimentacao, origem_os_id, created_at
    ) values (
      v_tenant_id, v_empresa_id, v_os_item.item_id, 'entrada', v_quantidade_estorno,
      'Estorno de material removido pelo autor na OS ' || coalesce(nullif(btrim(v_os.numero_os), ''), v_os.os_num::text, v_os.id::text),
      v_auth_uid::text, now(), v_os_item.os_id, now()
    );
  end if;

  delete from public.os_itens os_item
  where os_item.id = v_os_item.id
    and os_item.tenant_id = v_tenant_id
    and os_item.empresa_id = v_empresa_id;

  update public.ordens_servico os
     set valor_total = coalesce((
           select sum(item_os.valor_total)
           from public.os_itens item_os
           where item_os.os_id = v_os_item.os_id
             and item_os.tenant_id = v_tenant_id
             and item_os.empresa_id = v_empresa_id
         ), 0),
         atualizado_em = now()
   where os.id = v_os_item.os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id;

  return jsonb_build_object(
    'id', v_os_item.id,
    'quantidade_estornada', v_quantidade_estorno
  );
end;
$$;

revoke all on function public.app_listar_materiais_os(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.app_editar_material_os(integer, numeric, text)
  from public, anon, authenticated, service_role;
revoke all on function public.app_remover_material_os(integer)
  from public, anon, authenticated, service_role;

grant execute on function public.app_listar_materiais_os(integer) to authenticated, service_role;
grant execute on function public.app_editar_material_os(integer, numeric, text) to authenticated;
grant execute on function public.app_remover_material_os(integer) to authenticated;

notify pgrst, 'reload schema';

commit;
