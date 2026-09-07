-- Preco de material no app e valores de OS para a coordenacao.
-- Decisao de Gabriel em 07/09/2026, na revisao do perfil de coordenacao.
--
-- 1. COORDENACAO passa a ver valor da OS, percentual faturado e gasto. Ate
--    aqui app_mobile_pode_ver_valores_os so liberava ADMIN, DIRETOR,
--    FATURAMENTO, FINANCEIRO e COMERCIAL.
--
-- 2. Correcao: app_resumo_materiais_os usava uma regra propria
--    (papel not in ('APONTAMENTO_RH','APONTADOR')) e por isso mostrava o
--    "Total em material" da OS para o TECNICO, que nao pode ver valor nenhum.
--    Agora as tres portas de preco de material usam a mesma funcao.
--
-- 3. A lista de material lancado e a busca do item na tela de lancamento
--    passam a devolver preco, para o app mostrar unitario e total. Quem nao
--    pode ver recebe null, nao zero — zero passaria por preco de verdade.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Regra unica de preco de material -----------------------------------------

create or replace function public.app_mobile_pode_ver_preco_material(
  p_tenant_id uuid default public.current_tenant_id(),
  p_empresa_id uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $$
  select public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     and coalesce(a.fn_current_empresa_papel(p_tenant_id, p_empresa_id), '')
         not in ('TECNICO', 'APONTAMENTO_RH', 'APONTADOR', 'PAINEL_TV');
$$;

comment on function public.app_mobile_pode_ver_preco_material(uuid, uuid) is
  'Quem enxerga preco de material no app. Quem so aponta hora ou lanca material em campo nao ve valor nenhum.';

revoke all on function public.app_mobile_pode_ver_preco_material(uuid, uuid) from public, anon;
grant execute on function public.app_mobile_pode_ver_preco_material(uuid, uuid) to authenticated;

-- 2. Coordenacao enxerga os valores da OS -------------------------------------

create or replace function public.app_mobile_pode_ver_valores_os(
  p_tenant_id uuid default public.current_tenant_id(),
  p_empresa_id uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $$
  select public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     and coalesce(a.fn_current_empresa_papel(p_tenant_id, p_empresa_id), '')
         in ('ADMIN', 'DIRETOR', 'FATURAMENTO', 'FINANCEIRO', 'COMERCIAL', 'COORDENACAO');
$$;

-- 3. Resumo de materiais volta a respeitar a regra unica -----------------------

do $patch_resumo$
declare
  v_definition text;
  v_needle text := $needle$  v_pode_ver_valores := v_papel not in ('APONTAMENTO_RH', 'APONTADOR');$needle$;
  v_replacement text := $replacement$  v_pode_ver_valores := public.app_mobile_pode_ver_preco_material(v_tenant_id, v_empresa_id);$replacement$;
begin
  select pg_get_functiondef('public.app_resumo_materiais_os_unfiltered_ov_20260829(integer)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'resumo_materiais_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_resumo$;

-- 4. Lista de material lancado com preco --------------------------------------
-- Trocar o tipo de retorno exige recriar. As colunas novas vao no fim, entao a
-- versao antiga do app continua lendo os mesmos campos e ignora o resto.

drop function if exists public.app_listar_materiais_os(integer);

create function public.app_listar_materiais_os(p_os_id integer)
returns table(
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
  motivo_bloqueio text,
  valor_unitario numeric,
  valor_total numeric,
  pode_ver_valores boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'auth'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_status_fluxo text;
  v_pode_ver_valores boolean;
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

  v_pode_ver_valores := public.app_mobile_pode_ver_preco_material(v_tenant_id, v_empresa_id);

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
    end as motivo_bloqueio,
    case when v_pode_ver_valores then os_item.valor_unitario end,
    case when v_pode_ver_valores then os_item.valor_total end,
    v_pode_ver_valores
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
$function$;

revoke all on function public.app_listar_materiais_os(integer) from public, anon;
grant execute on function public.app_listar_materiais_os(integer) to authenticated;

-- 5. Busca do item na tela de lancamento, com preco ---------------------------

drop function if exists public.app_buscar_material_por_item_id(integer);

create function public.app_buscar_material_por_item_id(p_item_id integer)
returns table(
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade_disponivel numeric,
  disponivel boolean,
  preco_unitario numeric,
  pode_ver_preco boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'auth'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_pode_ver_preco boolean;
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

  v_pode_ver_preco := public.app_mobile_pode_ver_preco_material(v_tenant_id, v_empresa_id);

  return query
  select
    item.id,
    item.codigo_interno::text,
    coalesce(item.nome, item.descricao)::text,
    item.unidade_medida::text,
    coalesce(estoque.quantidade_atual, 0)::numeric,
    coalesce(estoque.quantidade_atual, 0) > 0,
    case
      when v_pode_ver_preco
        then public.fn_preco_venda_item_unscoped(v_tenant_id, v_empresa_id, item.id)
    end,
    v_pode_ver_preco
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
$function$;

revoke all on function public.app_buscar_material_por_item_id(integer) from public, anon;
grant execute on function public.app_buscar_material_por_item_id(integer) to authenticated;

-- 6. Conferencia ---------------------------------------------------------------

do $assertions$
declare
  v_resumo text := pg_get_functiondef('public.app_resumo_materiais_os_unfiltered_ov_20260829(integer)'::regprocedure);
  v_valores text := pg_get_functiondef('public.app_mobile_pode_ver_valores_os(uuid,uuid)'::regprocedure);
begin
  if position('app_mobile_pode_ver_preco_material' in v_resumo) = 0 then
    raise exception 'resumo_materiais_sem_regra_unica';
  end if;

  if position('COORDENACAO' in v_valores) = 0 then
    raise exception 'coordenacao_sem_valores_de_os';
  end if;

  if (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'app_listar_materiais_os'
  ) is null then
    raise exception 'listar_materiais_sem_colunas';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
