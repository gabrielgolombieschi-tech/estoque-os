begin;

alter table if exists m.orcamento
  add column if not exists valor_fechado numeric(15,2),
  add column if not exists os_id integer,
  add column if not exists os_itens_importados_at timestamp with time zone;

alter table if exists m.orcamento
  drop constraint if exists ck_orcamento__valor_fechado_range;

alter table if exists m.orcamento
  add constraint ck_orcamento__valor_fechado_range
  check (valor_fechado is null or valor_fechado >= 0);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fk_orcamento__os'
      and conrelid = 'm.orcamento'::regclass
  ) then
    alter table m.orcamento
      add constraint fk_orcamento__os
      foreign key (tenant_id, empresa_id, os_id)
      references public.ordens_servico (tenant_id, empresa_id, id)
      on delete set null;
  end if;
end;
$$;

create or replace view r.r_orcamento_lista as
select
  o.id,
  o.tenant_id,
  o.empresa_id,
  o.codigo,
  o.numero,
  o.versao,
  o.status,
  o.emissao_date,
  o.titulo,
  o.cliente_id,
  c1.nome as cliente_nome,
  o.vendedor_usuario_id,
  u.nome as vendedor_nome,
  o.condicao_pagamento_id,
  cp.nome as condicao_pagamento_nome,
  o.desconto_global_percent,
  o.acrescimo_cond_pag_percent,
  o.valor_frete,
  o.total_produtos,
  o.total_servicos,
  o.total_bruto,
  o.total_desconto_global,
  o.total_liquido,
  o.created_at,
  o.updated_at,
  o.valor_fechado,
  case
    when o.valor_fechado is null then null::numeric(15,2)
    else round((o.total_liquido - o.valor_fechado)::numeric, 2)
  end as desconto_fechamento_valor,
  case
    when o.valor_fechado is null or o.total_liquido = 0 then null::numeric(7,2)
    else round((((o.total_liquido - o.valor_fechado) / o.total_liquido) * 100)::numeric, 2)
  end as desconto_fechamento_percent,
  o.observacoes,
  o.os_id,
  o.os_itens_importados_at
from m.orcamento o
join public.clientes c1
  on c1.tenant_id = o.tenant_id
 and c1.empresa_id = o.empresa_id
 and c1.id = o.cliente_id
left join a.usuario u
  on u.id = o.vendedor_usuario_id
left join c.condicao_pagamento cp
  on cp.id = o.condicao_pagamento_id
where o.deleted_at is null;

drop function if exists m.fn_orcamento_atualizar_status(uuid, text, text, numeric, boolean, boolean);

create or replace function m.fn_orcamento_atualizar_status(
  p_orcamento_id uuid,
  p_status text,
  p_followup text default null,
  p_valor_fechado numeric default null,
  p_abrir_os boolean default false,
  p_importar_itens_os boolean default false
)
returns table (
  orcamento_id uuid,
  os_id integer,
  numero_os text,
  valor_orcado numeric,
  valor_fechado numeric,
  desconto_valor numeric,
  itens_importados boolean
)
language plpgsql
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_orc m.orcamento%rowtype;
  v_cliente_nome text;
  v_vendedor_nome text;
  v_status text;
  v_followup text;
  v_tipo_pedido text := 'servico';
  v_os_num bigint;
  v_os_id integer;
  v_numero_os text;
  v_valor_orcado numeric(15,2);
  v_valor_fechado_final numeric(15,2);
  v_desconto_valor_final numeric(15,2);
  v_itens_importados boolean := false;
  v_criado_por text;
  v_item record;
begin
  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Contexto tenant/empresa nao encontrado para atualizar status do orcamento.';
  end if;

  v_status := upper(trim(coalesce(p_status, '')));
  if v_status not in ('ANDAMENTO', 'FECHADO', 'PERDIDO') then
    raise exception 'Status de orcamento invalido: %', coalesce(p_status, '<null>');
  end if;

  v_followup := nullif(trim(coalesce(p_followup, '')), '');

  if coalesce(p_importar_itens_os, false) and not coalesce(p_abrir_os, false) then
    raise exception 'Selecione abrir OS antes de importar os itens.';
  end if;

  select o.*
    into v_orc
  from m.orcamento o
  where o.id = p_orcamento_id
    and o.tenant_id = v_tenant_id
    and o.empresa_id = v_empresa_id
    and o.deleted_at is null;

  if not found then
    raise exception 'Orcamento nao encontrado para o tenant/empresa atual.';
  end if;

  select
    coalesce(nullif(trim(c.nome), ''), 'Cliente #' || v_orc.cliente_id::text),
    nullif(trim(u.nome), '')
  into
    v_cliente_nome,
    v_vendedor_nome
  from m.orcamento o
  left join public.clientes c
    on c.tenant_id = o.tenant_id
   and c.empresa_id = o.empresa_id
   and c.id = o.cliente_id
  left join a.usuario u
    on u.id = o.vendedor_usuario_id
  where o.id = p_orcamento_id
    and o.tenant_id = v_tenant_id
    and o.empresa_id = v_empresa_id
    and o.deleted_at is null;

  v_valor_orcado := round(coalesce(v_orc.total_liquido, 0)::numeric, 2);

  if v_status = 'FECHADO' then
    v_valor_fechado_final := round(coalesce(p_valor_fechado, v_orc.valor_fechado, v_valor_orcado)::numeric, 2);
    if v_valor_fechado_final < 0 then
      raise exception 'Valor fechado nao pode ser negativo.';
    end if;
  else
    v_valor_fechado_final := round(coalesce(v_orc.valor_fechado, 0)::numeric, 2);
  end if;

  v_desconto_valor_final := round((v_valor_orcado - v_valor_fechado_final)::numeric, 2);
  v_os_id := v_orc.os_id;

  if v_os_id is not null then
    select os.numero_os
      into v_numero_os
    from public.ordens_servico os
    where os.tenant_id = v_orc.tenant_id
      and os.empresa_id = v_orc.empresa_id
      and os.id = v_os_id;

    if not found then
      v_os_id := null;
      v_numero_os := null;
    end if;
  end if;

  if coalesce(p_abrir_os, false) then
    if v_status <> 'FECHADO' then
      raise exception 'Abrir OS so e permitido ao fechar o orcamento.';
    end if;

    if v_os_id is null then
      if exists (
        select 1
        from m.orcamento_item oi
        where oi.tenant_id = v_orc.tenant_id
          and oi.empresa_id = v_orc.empresa_id
          and oi.orcamento_id = v_orc.id
          and oi.deleted_at is null
          and oi.item_tipo = 'SERVICO'
      ) then
        v_tipo_pedido := 'servico';
      else
        v_tipo_pedido := 'material';
      end if;

      v_os_num := nextval('public.ordens_servico_os_num_seq');
      v_numero_os := v_os_num::text;
      v_criado_por := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);

      insert into public.ordens_servico (
        tenant_id,
        empresa_id,
        numero_os,
        os_num,
        cliente_id,
        cliente_nome,
        descricao_servico,
        status,
        tipo_pedido,
        vendedor,
        orcado,
        observacoes,
        criado_por
      )
      values (
        v_orc.tenant_id,
        v_orc.empresa_id,
        v_numero_os,
        v_os_num,
        v_orc.cliente_id,
        left(v_cliente_nome, 255),
        nullif(upper(trim(coalesce(v_orc.titulo, ''))), ''),
        'em_andamento',
        v_tipo_pedido,
        v_vendedor_nome,
        v_valor_fechado_final,
        case
          when v_followup is null then 'Origem orcamento ' || coalesce(v_orc.codigo, v_orc.id::text)
          else 'Origem orcamento ' || coalesce(v_orc.codigo, v_orc.id::text) || ' | ' || v_followup
        end,
        v_criado_por
      )
      returning id, numero_os
      into v_os_id, v_numero_os;
    end if;

    update public.ordens_servico
       set cliente_id = v_orc.cliente_id,
           cliente_nome = left(v_cliente_nome, 255),
           descricao_servico = coalesce(nullif(upper(trim(coalesce(v_orc.titulo, ''))), ''), descricao_servico),
           vendedor = coalesce(v_vendedor_nome, vendedor),
           orcado = v_valor_fechado_final,
           atualizado_em = now()
     where tenant_id = v_orc.tenant_id
       and empresa_id = v_orc.empresa_id
       and id = v_os_id;

    if coalesce(p_importar_itens_os, false) and v_orc.os_itens_importados_at is null then
      v_criado_por := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);

      for v_item in
        select
          oi.item_id,
          oi.quantidade,
          oi.valor_unitario_liquido,
          oi.valor_total
        from m.orcamento_item oi
        where oi.tenant_id = v_orc.tenant_id
          and oi.empresa_id = v_orc.empresa_id
          and oi.orcamento_id = v_orc.id
          and oi.deleted_at is null
        order by oi.seq
      loop
        perform public.add_os_item_baixa_imediata(
          p_os_id => v_os_id,
          p_item_id => v_item.item_id,
          p_quantidade => v_item.quantidade,
          p_valor_unitario => case
            when coalesce(v_item.valor_unitario_liquido, 0) > 0 then v_item.valor_unitario_liquido
            when coalesce(v_item.quantidade, 0) > 0 and coalesce(v_item.valor_total, 0) > 0
              then round((v_item.valor_total / nullif(v_item.quantidade, 0))::numeric, 4)
            else 0
          end,
          p_desconto_percentual => 0,
          p_desconto_valor => 0,
          p_baixa_estoque => false,
          p_realizado_por => v_criado_por,
          p_motivo => 'Importado do orcamento ' || coalesce(v_orc.codigo, v_orc.id::text),
          p_empresa_id => v_orc.empresa_id
        );
      end loop;

      v_itens_importados := true;
    end if;
  end if;

  update m.orcamento
     set status = v_status,
         observacoes = v_followup,
         valor_fechado = case
           when v_status = 'FECHADO' then v_valor_fechado_final
           else valor_fechado
         end,
         os_id = coalesce(v_os_id, os_id),
         os_itens_importados_at = case
           when v_itens_importados and os_itens_importados_at is null then now()
           else os_itens_importados_at
         end,
         updated_at = now()
   where id = v_orc.id
     and tenant_id = v_orc.tenant_id
     and empresa_id = v_orc.empresa_id;

  orcamento_id := v_orc.id;
  os_id := v_os_id;
  numero_os := v_numero_os;
  valor_orcado := v_valor_orcado;
  valor_fechado := v_valor_fechado_final;
  desconto_valor := v_desconto_valor_final;
  itens_importados := v_itens_importados;

  return next;
end;
$$;

grant all on function m.fn_orcamento_atualizar_status(uuid, text, text, numeric, boolean, boolean) to authenticated;
grant all on function m.fn_orcamento_atualizar_status(uuid, text, text, numeric, boolean, boolean) to service_role;

commit;
