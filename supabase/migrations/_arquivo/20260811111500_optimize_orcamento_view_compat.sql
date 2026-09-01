begin;

-- Compatibilidade para clientes ainda publicados que consultam diretamente
-- r.r_orcamento_lista. A funcao deriva o contexto da sessao e faz a validacao
-- uma unica vez, sem depender das policies das tabelas relacionadas por linha.
create or replace function m.fn_orcamento_lista_current()
returns table (
  id uuid,
  tenant_id uuid,
  empresa_id uuid,
  codigo text,
  numero integer,
  versao integer,
  status text,
  emissao_date date,
  titulo text,
  cliente_id integer,
  cliente_nome varchar(255),
  vendedor_usuario_id uuid,
  vendedor_nome text,
  condicao_pagamento_id uuid,
  condicao_pagamento_nome text,
  desconto_global_percent numeric(7,4),
  acrescimo_cond_pag_percent numeric(7,4),
  valor_frete numeric(15,2),
  total_produtos numeric(15,2),
  total_servicos numeric(15,2),
  total_bruto numeric(15,2),
  total_desconto_global numeric(15,2),
  total_liquido numeric(15,2),
  created_at timestamptz,
  updated_at timestamptz,
  valor_fechado numeric(15,2),
  desconto_fechamento_valor numeric(15,2),
  desconto_fechamento_percent numeric(7,2),
  observacoes text,
  os_id integer,
  os_itens_importados_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid;
begin
  if auth.uid() is null or v_tenant_id is null then
    return;
  end if;

  v_empresa_id := public.current_empresa_id__by_tenant(v_tenant_id);

  if v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id)
     or not c.has_comercial_access(v_tenant_id, v_empresa_id) then
    return;
  end if;

  return query
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
    cli.nome,
    o.vendedor_usuario_id,
    vendedor.nome,
    o.condicao_pagamento_id,
    cp.nome,
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
      else round((o.total_liquido - o.valor_fechado)::numeric, 2)::numeric(15,2)
    end,
    case
      when o.valor_fechado is null or o.total_liquido = 0 then null::numeric(7,2)
      else round((((o.total_liquido - o.valor_fechado) / o.total_liquido) * 100)::numeric, 2)::numeric(7,2)
    end,
    o.observacoes,
    o.os_id,
    o.os_itens_importados_at
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
  where o.tenant_id = v_tenant_id
    and o.empresa_id = v_empresa_id
    and o.deleted_at is null;
end;
$$;

revoke all on function m.fn_orcamento_lista_current() from public, anon;
grant execute on function m.fn_orcamento_lista_current() to authenticated;

create or replace view r.r_orcamento_lista
with (security_invoker = true)
as
select
  src.id,
  src.tenant_id,
  src.empresa_id,
  src.codigo,
  src.numero,
  src.versao,
  src.status,
  src.emissao_date,
  src.titulo,
  src.cliente_id,
  src.cliente_nome::varchar(255) as cliente_nome,
  src.vendedor_usuario_id,
  src.vendedor_nome,
  src.condicao_pagamento_id,
  src.condicao_pagamento_nome,
  src.desconto_global_percent::numeric(7,4) as desconto_global_percent,
  src.acrescimo_cond_pag_percent::numeric(7,4) as acrescimo_cond_pag_percent,
  src.valor_frete::numeric(15,2) as valor_frete,
  src.total_produtos::numeric(15,2) as total_produtos,
  src.total_servicos::numeric(15,2) as total_servicos,
  src.total_bruto::numeric(15,2) as total_bruto,
  src.total_desconto_global::numeric(15,2) as total_desconto_global,
  src.total_liquido::numeric(15,2) as total_liquido,
  src.created_at,
  src.updated_at,
  src.valor_fechado::numeric(15,2) as valor_fechado,
  src.desconto_fechamento_valor::numeric as desconto_fechamento_valor,
  src.desconto_fechamento_percent::numeric as desconto_fechamento_percent,
  src.observacoes,
  src.os_id,
  src.os_itens_importados_at
from m.fn_orcamento_lista_current() src;

revoke all on table r.r_orcamento_lista from public, anon;
grant select on table r.r_orcamento_lista to authenticated;

do $$
begin
  if has_function_privilege('anon', 'm.fn_orcamento_lista_current()', 'execute')
     or not has_function_privilege('authenticated', 'm.fn_orcamento_lista_current()', 'execute')
     or not coalesce(
       (
         select 'security_invoker=true' = any (cls.reloptions)
         from pg_class cls
         where cls.oid = 'r.r_orcamento_lista'::regclass
       ),
       false
     ) then
    raise exception 'r_orcamento_lista_compat_insegura';
  end if;
end;
$$;

commit;
