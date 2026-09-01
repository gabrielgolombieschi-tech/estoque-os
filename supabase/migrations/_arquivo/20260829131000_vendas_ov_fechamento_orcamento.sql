-- Fechamento de orcamento com escolha explicita entre OS e OV.
-- As assinaturas anteriores sao removidas para evitar ambiguidade causada pelo
-- novo parametro opcional no fim da lista.

drop function if exists m.fn_orcamento_atualizar_status_com_responsavel(
  uuid, text, text, numeric, boolean, boolean, uuid
);
drop function if exists m.fn_orcamento_atualizar_status(
  uuid, text, text, numeric, boolean, boolean
);

create function m.fn_orcamento_atualizar_status(
  p_orcamento_id uuid,
  p_status text,
  p_followup text default null,
  p_valor_fechado numeric default null,
  p_abrir_os boolean default false,
  p_importar_itens_os boolean default false,
  p_tipo_documento text default null
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
  v_tipo_documento text;
  v_tipo_documento_existente text;
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
    raise exception 'Selecione gerar o documento antes de importar os itens.';
  end if;

  if p_tipo_documento is not null
     and (v_status <> 'FECHADO' or not coalesce(p_abrir_os, false)) then
    raise exception 'O tipo de documento so pode ser escolhido ao fechar e gerar o documento.';
  end if;

  if p_tipo_documento is not null
     and upper(btrim(p_tipo_documento)) not in ('OS', 'OV') then
    raise exception 'Tipo de documento invalido: %', p_tipo_documento;
  end if;

  select orcamento.*
    into v_orc
  from m.orcamento as orcamento
  where orcamento.id = p_orcamento_id
    and orcamento.tenant_id = v_tenant_id
    and orcamento.empresa_id = v_empresa_id
    and orcamento.deleted_at is null;

  if not found then
    raise exception 'Orcamento nao encontrado para o tenant/empresa atual.';
  end if;

  select
    coalesce(nullif(trim(cliente.nome), ''), 'Cliente #' || v_orc.cliente_id::text),
    nullif(trim(usuario.nome), '')
  into v_cliente_nome, v_vendedor_nome
  from m.orcamento as orcamento
  left join public.clientes as cliente
    on cliente.tenant_id = orcamento.tenant_id
   and cliente.empresa_id = orcamento.empresa_id
   and cliente.id = orcamento.cliente_id
  left join a.usuario as usuario
    on usuario.id = orcamento.vendedor_usuario_id
  where orcamento.id = p_orcamento_id
    and orcamento.tenant_id = v_tenant_id
    and orcamento.empresa_id = v_empresa_id
    and orcamento.deleted_at is null;

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

  if exists (
    select 1
    from m.orcamento_item as item_orcamento
    where item_orcamento.tenant_id = v_orc.tenant_id
      and item_orcamento.empresa_id = v_orc.empresa_id
      and item_orcamento.orcamento_id = v_orc.id
      and item_orcamento.deleted_at is null
      and item_orcamento.item_tipo = 'SERVICO'
  ) then
    v_tipo_pedido := 'servico';
  else
    v_tipo_pedido := 'material';
  end if;

  v_tipo_documento := coalesce(
    nullif(upper(btrim(coalesce(p_tipo_documento, ''))), ''),
    case when v_tipo_pedido = 'servico' then 'OS' else 'OV' end
  );

  if v_os_id is not null then
    select documento.numero_os, documento.tipo_documento
      into v_numero_os, v_tipo_documento_existente
    from public.ordens_servico as documento
    where documento.tenant_id = v_orc.tenant_id
      and documento.empresa_id = v_orc.empresa_id
      and documento.id = v_os_id;

    if not found then
      v_os_id := null;
      v_numero_os := null;
      v_tipo_documento_existente := null;
    elsif p_tipo_documento is not null
          and v_tipo_documento_existente <> v_tipo_documento then
      raise exception 'O orcamento ja esta vinculado a um documento do tipo %.', v_tipo_documento_existente;
    else
      v_tipo_documento := v_tipo_documento_existente;
    end if;
  end if;

  if coalesce(p_abrir_os, false) then
    if v_status <> 'FECHADO' then
      raise exception 'Gerar documento so e permitido ao fechar o orcamento.';
    end if;

    if v_os_id is null then
      v_os_num := nextval('public.ordens_servico_os_num_seq');
      v_numero_os := v_os_num::text;
      v_criado_por := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);

      insert into public.ordens_servico as documento (
        tenant_id,
        empresa_id,
        numero_os,
        os_num,
        cliente_id,
        cliente_nome,
        descricao_servico,
        status,
        status_fluxo,
        tipo_pedido,
        tipo_documento,
        vendedor,
        orcado,
        observacoes,
        criado_por,
        tem_gestao,
        usa_relatorio_hh
      ) values (
        v_orc.tenant_id,
        v_orc.empresa_id,
        v_numero_os,
        v_os_num,
        v_orc.cliente_id,
        left(v_cliente_nome, 255),
        nullif(upper(trim(coalesce(v_orc.titulo, ''))), ''),
        'em_andamento',
        'em_andamento',
        v_tipo_pedido,
        v_tipo_documento,
        v_vendedor_nome,
        v_valor_fechado_final,
        case
          when v_followup is null then 'Origem orcamento ' || coalesce(v_orc.codigo, v_orc.id::text)
          else 'Origem orcamento ' || coalesce(v_orc.codigo, v_orc.id::text) || ' | ' || v_followup
        end,
        v_criado_por,
        false,
        false
      )
      returning documento.id, documento.numero_os
      into v_os_id, v_numero_os;
    end if;

    update public.ordens_servico as documento
       set cliente_id = v_orc.cliente_id,
           cliente_nome = left(v_cliente_nome, 255),
           descricao_servico = coalesce(nullif(upper(trim(coalesce(v_orc.titulo, ''))), ''), documento.descricao_servico),
           vendedor = coalesce(v_vendedor_nome, documento.vendedor),
           orcado = v_valor_fechado_final,
           tem_gestao = case when documento.tipo_documento = 'OV' then false else documento.tem_gestao end,
           usa_relatorio_hh = case when documento.tipo_documento = 'OV' then false else documento.usa_relatorio_hh end,
           atualizado_em = now()
     where documento.tenant_id = v_orc.tenant_id
       and documento.empresa_id = v_orc.empresa_id
       and documento.id = v_os_id;

    if coalesce(p_importar_itens_os, false) and v_orc.os_itens_importados_at is null then
      v_criado_por := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);

      for v_item in
        select
          item_orcamento.item_id,
          item_orcamento.quantidade,
          item_orcamento.valor_unitario_liquido,
          item_orcamento.valor_total,
          round(
            (coalesce(item.preco_unitario, 0) * (1 + coalesce(item.aliquota_ipi, 0) / 100))::numeric,
            2
          ) as valor_compra_com_impostos
        from m.orcamento_item as item_orcamento
        left join public.itens as item
          on item.tenant_id = item_orcamento.tenant_id
         and item.empresa_id = item_orcamento.empresa_id
         and item.id = item_orcamento.item_id
        where item_orcamento.tenant_id = v_orc.tenant_id
          and item_orcamento.empresa_id = v_orc.empresa_id
          and item_orcamento.orcamento_id = v_orc.id
          and item_orcamento.deleted_at is null
        order by item_orcamento.seq
      loop
        perform public.add_os_item_baixa_imediata(
          p_os_id => v_os_id,
          p_item_id => v_item.item_id,
          p_quantidade => v_item.quantidade,
          p_valor_unitario => case
            when coalesce(v_item.valor_compra_com_impostos, 0) > 0 then v_item.valor_compra_com_impostos
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

  update m.orcamento as orcamento
     set status = v_status,
         observacoes = v_followup,
         valor_fechado = case
           when v_status = 'FECHADO' then v_valor_fechado_final
           else orcamento.valor_fechado
         end,
         os_id = coalesce(v_os_id, orcamento.os_id),
         os_itens_importados_at = case
           when v_itens_importados and orcamento.os_itens_importados_at is null then now()
           else orcamento.os_itens_importados_at
         end,
         updated_at = now()
   where orcamento.id = v_orc.id
     and orcamento.tenant_id = v_orc.tenant_id
     and orcamento.empresa_id = v_orc.empresa_id;

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

create function m.fn_orcamento_atualizar_status_com_responsavel(
  p_orcamento_id uuid,
  p_status text,
  p_followup text default null,
  p_valor_fechado numeric default null,
  p_abrir_os boolean default false,
  p_importar_itens_os boolean default false,
  p_responsavel_aprovacao_id uuid default null,
  p_tipo_documento text default null
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
  v_result record;
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Contexto tenant/empresa nao encontrado para atualizar status do orcamento.';
  end if;

  select *
    into v_result
  from m.fn_orcamento_atualizar_status(
    p_orcamento_id,
    p_status,
    p_followup,
    p_valor_fechado,
    p_abrir_os,
    p_importar_itens_os,
    p_tipo_documento
  );

  if coalesce(p_abrir_os, false)
     and p_responsavel_aprovacao_id is not null
     and v_result.os_id is not null then
    update public.ordens_servico as documento
       set responsavel_aprovacao_id = case
             when documento.tipo_documento = 'OS' then p_responsavel_aprovacao_id
             else null
           end,
           atualizado_em = now()
     where documento.id = v_result.os_id
       and documento.tenant_id = v_tenant_id
       and documento.empresa_id = v_empresa_id;
  end if;

  orcamento_id := v_result.orcamento_id;
  os_id := v_result.os_id;
  numero_os := v_result.numero_os;
  valor_orcado := v_result.valor_orcado;
  valor_fechado := v_result.valor_fechado;
  desconto_valor := v_result.desconto_valor;
  itens_importados := v_result.itens_importados;
  return next;
end;
$$;

revoke all on function m.fn_orcamento_atualizar_status(
  uuid, text, text, numeric, boolean, boolean, text
) from public, anon;
grant execute on function m.fn_orcamento_atualizar_status(
  uuid, text, text, numeric, boolean, boolean, text
) to authenticated, service_role;

revoke all on function m.fn_orcamento_atualizar_status_com_responsavel(
  uuid, text, text, numeric, boolean, boolean, uuid, text
) from public, anon;
grant execute on function m.fn_orcamento_atualizar_status_com_responsavel(
  uuid, text, text, numeric, boolean, boolean, uuid, text
) to authenticated, service_role;
