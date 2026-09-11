-- OC do cliente no fechamento: persistir mesmo sem gerar documento e propagar
-- para OS/OV na mesma transação. A RPC anterior permanece compatível.
alter table m.orcamento add column if not exists pedido_compra_cliente text;
comment on column m.orcamento.pedido_compra_cliente is
  'Número do pedido de compra do cliente informado no fechamento; não é um pedido interno a fornecedor.';

create or replace function m.fn_orcamento_atualizar_status_com_pedido(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_orcamento_id uuid,
  p_status text,
  p_followup text default null,
  p_valor_fechado numeric default null,
  p_abrir_os boolean default false,
  p_importar_itens_os boolean default false,
  p_responsavel_aprovacao_id uuid default null,
  p_tipo_documento text default null,
  p_pedido_compra_cliente text default null
)
returns table (
  orcamento_id uuid, os_id integer, numero_os text, valor_orcado numeric,
  valor_fechado numeric, desconto_valor numeric, itens_importados boolean
)
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public', 'm'
as $$
declare
  v_orc m.orcamento%rowtype;
  v_result record;
  v_documento public.ordens_servico%rowtype;
  v_pedido text := nullif(btrim(p_pedido_compra_cliente), '');
begin
  if p_tenant_id is null or p_empresa_id is null
     or p_tenant_id is distinct from public.current_tenant_id()
     or p_empresa_id is distinct from public.current_empresa_id() then
    raise exception 'Contexto tenant/empresa divergente para atualizar o orçamento.';
  end if;
  if length(v_pedido) > 120 then
    raise exception 'Pedido de compra do cliente deve ter no máximo 120 caracteres.';
  end if;

  -- Serializa fechamentos do mesmo orçamento; mantém as permissões/RLS vigentes.
  select o.* into v_orc from m.orcamento o
   where o.id = p_orcamento_id and o.tenant_id = p_tenant_id
     and o.empresa_id = p_empresa_id and o.deleted_at is null
   for update;
  if not found then
    raise exception 'Orçamento não encontrado para o tenant/empresa atual.';
  end if;

  select * into v_result from m.fn_orcamento_atualizar_status_com_responsavel(
    p_orcamento_id, p_status, p_followup, p_valor_fechado,
    p_abrir_os, p_importar_itens_os, p_responsavel_aprovacao_id, p_tipo_documento
  );

  if upper(btrim(p_status)) = 'FECHADO' then
    if v_result.os_id is not null then
      select d.* into v_documento from public.ordens_servico d
       where d.id = v_result.os_id and d.tenant_id = p_tenant_id
         and d.empresa_id = p_empresa_id
       for update;
      if not found then
        raise exception 'Documento não encontrado para o tenant/empresa atual.';
      end if;
    end if;
    -- Campo opcional vazio nunca apaga uma OC já registrada na OS/OV.
    v_pedido := coalesce(v_pedido, nullif(btrim(v_documento.pedido_compra), ''), v_orc.pedido_compra_cliente);
    update m.orcamento o set pedido_compra_cliente = v_pedido
     where o.id = p_orcamento_id and o.tenant_id = p_tenant_id and o.empresa_id = p_empresa_id;
    if not found then
      raise exception 'Não foi possível salvar o pedido no orçamento.';
    end if;
    if v_documento.id is not null and v_pedido is not null
       and v_documento.pedido_compra is distinct from v_pedido then
      if coalesce(v_documento.status_fluxo, v_documento.status) = 'cancelada' then
        raise exception 'Não é possível alterar o pedido de um documento cancelado.';
      end if;
      update public.ordens_servico d set pedido_compra = v_pedido, atualizado_em = now()
       where d.id = v_documento.id and d.tenant_id = p_tenant_id and d.empresa_id = p_empresa_id;
      if not found then
        raise exception 'Não foi possível salvar o pedido na OS/OV.';
      end if;
    end if;
  end if;

  return query select v_result.orcamento_id, v_result.os_id, v_result.numero_os,
    v_result.valor_orcado, v_result.valor_fechado, v_result.desconto_valor, v_result.itens_importados;
end;
$$;

revoke all on function m.fn_orcamento_atualizar_status_com_pedido(uuid, uuid, uuid, text, text, numeric, boolean, boolean, uuid, text, text) from public, anon;
grant execute on function m.fn_orcamento_atualizar_status_com_pedido(uuid, uuid, uuid, text, text, numeric, boolean, boolean, uuid, text, text) to authenticated, service_role;
notify pgrst, 'reload schema';
