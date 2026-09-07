-- Orcamentos no app, para COORDENACAO e acima. Decisao de Gabriel em
-- 07/09/2026: no celular a aba Estoque da lugar a Orcamento para esses papeis.
--
-- Sao os MESMOS orcamentos da web (m.orcamento / m.orcamento_item). Nada de
-- tabela paralela: o app escreve nas mesmas tabelas e deixa os gatilhos ja
-- existentes fazerem o trabalho — m.trg_orcamento_biu numera, monta o codigo e
-- valida cliente e vendedor; m.trg_orcamento_item_biu resolve tipo, nome,
-- unidade e os totais do item; m.trg_orcamento_item_aiud recalcula o total do
-- orcamento. Assim um orcamento criado no celular e indistinguivel de um
-- criado na web.
--
-- A busca de produto reaproveita public.search_orcamento_itens, a mesma RPC da
-- tela web, que ja procura por nome, codigo interno e fabricante e devolve
-- preco sugerido e saldo. Aqui ela so ganha um involucro que preenche tenant e
-- empresa pelo contexto, para o app nao precisar carregar esses ids.
--
-- O portao de acesso e app_mobile_pode_ver_valores_os: orcamento e assunto
-- comercial e mostra preco o tempo todo, entao quem nao pode ver valor tambem
-- nao entra aqui.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 0. Portao ------------------------------------------------------------------

create or replace function public.app_orcamento_assert_acesso(
  out tenant_id uuid,
  out empresa_id uuid,
  out usuario_id uuid
)
returns record
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
begin
  tenant_id := public.current_tenant_id();
  empresa_id := public.current_empresa_id();

  if auth.uid() is null
     or tenant_id is null
     or empresa_id is null
     or not public.has_active_empresa_access(tenant_id, empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if not public.app_mobile_pode_ver_valores_os(tenant_id, empresa_id) then
    raise exception 'Seu perfil não tem acesso a orçamentos.';
  end if;

  usuario_id := a.fn_current_usuario_id();
  if usuario_id is null then
    raise exception 'Não foi possível identificar o seu usuário nesta empresa.';
  end if;
end;
$function$;

revoke all on function public.app_orcamento_assert_acesso() from public, anon, authenticated, service_role;

-- 1. Lista --------------------------------------------------------------------

create or replace function public.app_orcamento_listar(
  p_busca text default null,
  p_status text default 'ANDAMENTO',
  p_limite integer default 30,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm', 'a'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_busca text := nullif(btrim(p_busca), '');
  v_limite integer := least(greatest(coalesce(p_limite, 30), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_status text := nullif(btrim(upper(p_status)), '');
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  return coalesce((
    select jsonb_agg(linha order by linha->>'emissao_date' desc, linha->>'codigo' desc)
    from (
      select jsonb_build_object(
        'id', orcamento.id,
        'codigo', orcamento.codigo,
        'titulo', orcamento.titulo,
        'status', orcamento.status,
        'emissao_date', orcamento.emissao_date,
        'cliente_id', orcamento.cliente_id,
        'cliente_nome', coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado'),
        'total_liquido', orcamento.total_liquido,
        'itens', (
          select count(*)
          from m.orcamento_item as item
          where item.orcamento_id = orcamento.id
            and item.deleted_at is null
        )
      ) as linha
      from m.orcamento as orcamento
      left join public.clientes as cliente
        on cliente.id = orcamento.cliente_id
       and cliente.tenant_id = orcamento.tenant_id
      where orcamento.tenant_id = v_scope.tenant_id
        and orcamento.empresa_id = v_scope.empresa_id
        and orcamento.deleted_at is null
        and (v_status is null or orcamento.status = v_status)
        and (
          v_busca is null
          or orcamento.codigo ilike '%' || v_busca || '%'
          or orcamento.titulo ilike '%' || v_busca || '%'
          or cliente.nome ilike '%' || v_busca || '%'
        )
      order by orcamento.emissao_date desc, orcamento.numero desc
      offset v_offset
      limit v_limite
    ) as pagina
  ), '[]'::jsonb);
end;
$function$;

-- 2. Detalhe -------------------------------------------------------------------

create or replace function public.app_orcamento_detalhe(p_orcamento_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_orcamento jsonb;
  v_itens jsonb;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  select jsonb_build_object(
    'id', orcamento.id,
    'codigo', orcamento.codigo,
    'titulo', orcamento.titulo,
    'status', orcamento.status,
    'emissao_date', orcamento.emissao_date,
    'cliente_id', orcamento.cliente_id,
    'cliente_nome', coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado'),
    'observacoes', orcamento.observacoes,
    'total_produtos', orcamento.total_produtos,
    'total_servicos', orcamento.total_servicos,
    'total_liquido', orcamento.total_liquido,
    'desconto_global_percent', orcamento.desconto_global_percent,
    'editavel', orcamento.status = 'ANDAMENTO'
  )
    into v_orcamento
  from m.orcamento as orcamento
  left join public.clientes as cliente
    on cliente.id = orcamento.cliente_id
   and cliente.tenant_id = orcamento.tenant_id
  where orcamento.id = p_orcamento_id
    and orcamento.tenant_id = v_scope.tenant_id
    and orcamento.empresa_id = v_scope.empresa_id
    and orcamento.deleted_at is null;

  if v_orcamento is null then
    raise exception 'Orçamento não encontrado nesta empresa.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', item.id,
    'seq', item.seq,
    'item_id', item.item_id,
    'item_tipo', item.item_tipo,
    'nome', item.item_nome,
    'unidade', item.unidade,
    'quantidade', item.quantidade,
    'valor_unitario', item.valor_unitario,
    'desconto_item_percent', item.desconto_item_percent,
    'valor_total', item.valor_total,
    'observacoes', item.observacoes
  ) order by item.seq), '[]'::jsonb)
    into v_itens
  from m.orcamento_item as item
  where item.orcamento_id = p_orcamento_id
    and item.deleted_at is null;

  return jsonb_build_object('orcamento', v_orcamento, 'itens', v_itens);
end;
$function$;

-- 3. Clientes para o seletor ---------------------------------------------------

create or replace function public.app_orcamento_clientes(
  p_busca text default null,
  p_limite integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_busca text := nullif(btrim(p_busca), '');
  v_limite integer := least(greatest(coalesce(p_limite, 30), 1), 100);
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', cliente.id,
      'nome', cliente.nome,
      'documento', cliente.documento
    ) order by cliente.nome)
    from (
      select c.id, c.nome, c.documento
      from public.clientes as c
      where c.tenant_id = v_scope.tenant_id
        and c.empresa_id = v_scope.empresa_id
        and (v_busca is null or c.nome ilike '%' || v_busca || '%' or c.documento ilike '%' || v_busca || '%')
      order by c.nome
      limit v_limite
    ) as cliente
  ), '[]'::jsonb);
end;
$function$;

-- 4. Criar ---------------------------------------------------------------------

create or replace function public.app_orcamento_criar(
  p_cliente_id integer,
  p_titulo text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'a'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_titulo text := nullif(btrim(p_titulo), '');
  v_id uuid;
  v_codigo text;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  if v_titulo is null or char_length(v_titulo) < 3 then
    raise exception 'Informe um título com pelo menos 3 caracteres.';
  end if;
  if p_cliente_id is null then
    raise exception 'Selecione o cliente do orçamento.';
  end if;

  -- numero, versao e codigo saem do gatilho m.trg_orcamento_biu, que tambem
  -- recusa cliente ou vendedor invalidos.
  insert into m.orcamento (tenant_id, empresa_id, titulo, cliente_id, vendedor_usuario_id)
  values (v_scope.tenant_id, v_scope.empresa_id, v_titulo, p_cliente_id, v_scope.usuario_id)
  returning id, codigo into v_id, v_codigo;

  return jsonb_build_object('id', v_id, 'codigo', v_codigo);
end;
$function$;

-- 5. Busca de produto ----------------------------------------------------------

create or replace function public.app_orcamento_buscar_itens(
  p_termo text default null,
  p_fornecedor text default null,
  p_limite integer default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_limite integer := least(greatest(coalesce(p_limite, 40), 1), 100);
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'item_id', busca.id,
      'codigo_interno', busca.codigo_interno,
      'nome', busca.nome,
      'fabricante', busca.fabricante,
      'fornecedor', busca.fornecedor,
      'estoque_atual', busca.estoque_atual,
      'preco_sugerido', busca.preco_sugerido
    ) order by busca.nome)
    from public.search_orcamento_itens(
      v_scope.tenant_id,
      v_scope.empresa_id,
      nullif(btrim(p_termo), ''),
      nullif(btrim(p_fornecedor), ''),
      v_limite
    ) as busca
  ), '[]'::jsonb);
end;
$function$;

-- 6. Itens do orcamento --------------------------------------------------------

create or replace function public.app_orcamento_adicionar_item(
  p_orcamento_id uuid,
  p_item_id integer,
  p_quantidade numeric,
  p_valor_unitario numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_status text;
  v_valor numeric;
  v_id uuid;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  select orcamento.status into v_status
  from m.orcamento as orcamento
  where orcamento.id = p_orcamento_id
    and orcamento.tenant_id = v_scope.tenant_id
    and orcamento.empresa_id = v_scope.empresa_id
    and orcamento.deleted_at is null;

  if v_status is null then
    raise exception 'Orçamento não encontrado nesta empresa.';
  end if;
  if v_status <> 'ANDAMENTO' then
    raise exception 'Este orçamento está %. Só dá para alterar enquanto está em andamento.', lower(v_status);
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Informe uma quantidade maior que zero.';
  end if;

  -- Sem preco informado vale o sugerido, o mesmo numero que a tela web mostra.
  v_valor := coalesce(
    nullif(p_valor_unitario, 0),
    m.fn_orcamento_preco_sugerido_item_por_id(v_scope.tenant_id, v_scope.empresa_id, p_item_id),
    0
  );

  if v_valor <= 0 then
    raise exception 'Este item está sem preço sugerido. Informe o valor unitário.';
  end if;

  insert into m.orcamento_item (orcamento_id, item_id, quantidade, valor_unitario)
  values (p_orcamento_id, p_item_id, p_quantidade, v_valor)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'valor_unitario', v_valor);
end;
$function$;

create or replace function public.app_orcamento_atualizar_item(
  p_item_id uuid,
  p_quantidade numeric,
  p_valor_unitario numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_status text;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  select orcamento.status into v_status
  from m.orcamento_item as item
  join m.orcamento as orcamento on orcamento.id = item.orcamento_id
  where item.id = p_item_id
    and item.deleted_at is null
    and orcamento.tenant_id = v_scope.tenant_id
    and orcamento.empresa_id = v_scope.empresa_id
    and orcamento.deleted_at is null;

  if v_status is null then
    raise exception 'Item não encontrado neste orçamento.';
  end if;
  if v_status <> 'ANDAMENTO' then
    raise exception 'Este orçamento está %. Só dá para alterar enquanto está em andamento.', lower(v_status);
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Informe uma quantidade maior que zero.';
  end if;
  if p_valor_unitario is null or p_valor_unitario <= 0 then
    raise exception 'Informe um valor unitário maior que zero.';
  end if;

  update m.orcamento_item
     set quantidade = p_quantidade,
         valor_unitario = p_valor_unitario
   where id = p_item_id;

  return jsonb_build_object('sucesso', true);
end;
$function$;

create or replace function public.app_orcamento_remover_item(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_status text;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  select orcamento.status into v_status
  from m.orcamento_item as item
  join m.orcamento as orcamento on orcamento.id = item.orcamento_id
  where item.id = p_item_id
    and item.deleted_at is null
    and orcamento.tenant_id = v_scope.tenant_id
    and orcamento.empresa_id = v_scope.empresa_id
    and orcamento.deleted_at is null;

  if v_status is null then
    raise exception 'Item não encontrado neste orçamento.';
  end if;
  if v_status <> 'ANDAMENTO' then
    raise exception 'Este orçamento está %. Só dá para alterar enquanto está em andamento.', lower(v_status);
  end if;

  -- Exclusao logica, do mesmo jeito que a web faz: o gatilho de recalculo ja
  -- ignora item com deleted_at.
  update m.orcamento_item
     set deleted_at = now()
   where id = p_item_id;

  return jsonb_build_object('sucesso', true);
end;
$function$;

-- 7. Grants --------------------------------------------------------------------

do $grants$
declare
  v_assinatura text;
begin
  foreach v_assinatura in array array[
    'public.app_orcamento_listar(text, text, integer, integer)',
    'public.app_orcamento_detalhe(uuid)',
    'public.app_orcamento_clientes(text, integer)',
    'public.app_orcamento_criar(integer, text)',
    'public.app_orcamento_buscar_itens(text, text, integer)',
    'public.app_orcamento_adicionar_item(uuid, integer, numeric, numeric)',
    'public.app_orcamento_atualizar_item(uuid, numeric, numeric)',
    'public.app_orcamento_remover_item(uuid)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', v_assinatura);
    execute format('grant execute on function %s to authenticated', v_assinatura);
  end loop;
end;
$grants$;

notify pgrst, 'reload schema';

commit;
