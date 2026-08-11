begin;

-- A listagem por view fazia as policies das tabelas relacionadas reavaliarem
-- contexto e permissoes para cada linha. Esta RPC valida a fronteira uma vez e
-- continua obrigatoriamente presa ao tenant/empresa correntes do usuario.
create or replace function m.fn_orcamento_listar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_statuses text[] default null,
  p_emissao_de date default null,
  p_emissao_ate date default null,
  p_busca text default null,
  p_offset integer default 0,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado' using errcode = '42501';
  end if;

  if p_tenant_id is null or p_empresa_id is null then
    raise exception 'Tenant e empresa sao obrigatorios' using errcode = '22023';
  end if;

  if public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'Sem acesso aos orcamentos desta empresa' using errcode = '42501';
  end if;

  with filtered as materialized (
    select
      o.id,
      o.codigo,
      o.numero,
      o.versao,
      o.status,
      o.emissao_date,
      o.titulo,
      o.cliente_id,
      cli.nome as cliente_nome,
      o.vendedor_usuario_id,
      vendedor.nome as vendedor_nome,
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
      o.os_itens_importados_at,
      o.created_at,
      o.updated_at
    from m.orcamento o
    join public.clientes cli
      on cli.id = o.cliente_id
     and cli.tenant_id = o.tenant_id
     and cli.empresa_id = o.empresa_id
    left join a.usuario vendedor
      on vendedor.id = o.vendedor_usuario_id
     and vendedor.ativo is true
     and vendedor.deleted_at is null
     and exists (
       select 1
       from a.usuario_tenant ut
       join a.usuario_empresa ue on ue.usuario_id = ut.usuario_id
       where ut.usuario_id = vendedor.id
         and ut.tenant_id = o.tenant_id
         and ut.ativo is true
         and ut.deleted_at is null
         and ue.empresa_id = o.empresa_id
         and ue.ativo is true
         and ue.deleted_at is null
     )
    left join c.condicao_pagamento cp
      on cp.id = o.condicao_pagamento_id
     and cp.tenant_id = o.tenant_id
     and cp.empresa_id = o.empresa_id
     and cp.deleted_at is null
    where o.tenant_id = p_tenant_id
      and o.empresa_id = p_empresa_id
      and o.deleted_at is null
      and (
        p_statuses is null
        or cardinality(p_statuses) = 0
        or o.status = any (p_statuses)
      )
      and (p_emissao_de is null or o.emissao_date >= p_emissao_de)
      and (p_emissao_ate is null or o.emissao_date <= p_emissao_ate)
      and (
        v_busca is null
        or o.codigo ilike ('%' || v_busca || '%')
        or o.titulo ilike ('%' || v_busca || '%')
        or cli.nome ilike ('%' || v_busca || '%')
      )
  ),
  page_rows as (
    select *
    from filtered
    order by emissao_date desc, numero desc
    offset v_offset
    limit v_limit
  )
  select jsonb_build_object(
    'rows', coalesce(
      jsonb_agg(to_jsonb(page_rows) order by emissao_date desc, numero desc),
      '[]'::jsonb
    ),
    'count', (select count(*) from filtered)
  )
  into v_result
  from page_rows;

  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'count', 0));
end;
$$;

revoke all on function m.fn_orcamento_listar(
  uuid, uuid, text[], date, date, text, integer, integer
) from public, anon;
grant execute on function m.fn_orcamento_listar(
  uuid, uuid, text[], date, date, text, integer, integer
) to authenticated;

create index if not exists idx_orcamento__lista_scope
  on m.orcamento (
    tenant_id,
    empresa_id,
    status,
    emissao_date desc,
    numero desc
  )
  where deleted_at is null;

do $$
begin
  if has_function_privilege(
       'anon',
       'm.fn_orcamento_listar(uuid,uuid,text[],date,date,text,integer,integer)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'm.fn_orcamento_listar(uuid,uuid,text[],date,date,text,integer,integer)',
       'execute'
     ) then
    raise exception 'fn_orcamento_listar_acl_invalida';
  end if;
end;
$$;

commit;
