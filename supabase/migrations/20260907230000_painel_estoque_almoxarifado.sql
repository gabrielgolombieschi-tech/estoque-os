-- Painel de estoque para a tela Inicio do almoxarifado e de compras.
-- Pedido de Gabriel em 07/09/2026: "quantidade de itens cadastrados por mes" e
-- algo de estoque que ajude no dia a dia.
--
-- O que entrou e por que:
--
--   cadastros    - o que ele pediu, e e a medida do proprio trabalho dele.
--                  Serie de 12 meses para comparar.
--   reposicao    - dos 3.498 produtos, 1.031 tem estoque_minimo preenchido;
--                  desses, 471 estao abaixo do minimo e 234 zerados. E o unico
--                  numero da base que aponta acao concreta: comprar. Itens sem
--                  minimo definido ficam de fora de proposito — dizer que 1.340
--                  itens estao zerados seria ruido, porque muita compra e de
--                  uma vez so e nunca mais.
--   movimento    - entradas e saidas do mes, para dar volume de operacao.
--   giro         - o que mais saiu no mes.
--
-- Portao: app_mobile_pode_ver_preco_material, o mesmo de quem ja enxerga preco
-- de material. Deixa entrar almoxarifado, compras, coordenacao e acima, e
-- mantem fora tecnico e apontador.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.app_estoque_painel(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_ano integer := coalesce(p_ano, extract(year from current_date)::integer);
  v_mes integer := coalesce(p_mes, extract(month from current_date)::integer);
  v_inicio date;
  v_fim date;
  v_cadastros jsonb;
  v_cadastros_mes integer;
  v_cadastros_ano integer;
  v_entradas integer;
  v_saidas integer;
  v_itens_ativos integer;
  v_com_minimo integer;
  v_abaixo integer;
  v_zerados integer;
  v_repor jsonb;
  v_giro jsonb;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if not public.app_mobile_pode_ver_preco_material(v_tenant_id, v_empresa_id) then
    raise exception 'Seu perfil não tem acesso ao painel de estoque.';
  end if;

  if v_mes < 1 or v_mes > 12 then
    raise exception 'Mês inválido.';
  end if;

  v_inicio := make_date(v_ano, v_mes, 1);
  v_fim := (v_inicio + interval '1 month')::date;

  -- Cadastros de produto, mes a mes no ano.
  select
    coalesce(jsonb_agg(jsonb_build_object('mes', serie.mes, 'total', contagem.total) order by serie.mes), '[]'::jsonb),
    coalesce(sum(contagem.total) filter (where serie.mes = v_mes), 0)::integer,
    coalesce(sum(contagem.total), 0)::integer
    into v_cadastros, v_cadastros_mes, v_cadastros_ano
  from generate_series(1, 12) as serie(mes)
  cross join lateral (
    select count(*)::integer as total
    from public.itens as item
    where item.tenant_id = v_tenant_id
      and item.empresa_id = v_empresa_id
      and item.tipo = 'produto'
      and item.criado_em >= make_date(v_ano, serie.mes, 1)
      and item.criado_em < (make_date(v_ano, serie.mes, 1) + interval '1 month')
  ) as contagem;

  -- Movimento do mes.
  select
    coalesce(count(*) filter (where movimento.tipo = 'entrada'), 0)::integer,
    coalesce(count(*) filter (where movimento.tipo = 'saida'), 0)::integer
    into v_entradas, v_saidas
  from public.movimentacoes as movimento
  where movimento.tenant_id = v_tenant_id
    and movimento.empresa_id = v_empresa_id
    and movimento.data_movimentacao >= v_inicio
    and movimento.data_movimentacao < v_fim;

  -- Situacao atual do estoque. So conta item que controla estoque e tem minimo
  -- definido: sem minimo nao da para dizer que faltou.
  select
    count(*)::integer,
    count(*) filter (where item.estoque_minimo > 0)::integer,
    count(*) filter (where item.estoque_minimo > 0 and coalesce(saldo.quantidade_atual, 0) < item.estoque_minimo)::integer,
    count(*) filter (where item.estoque_minimo > 0 and coalesce(saldo.quantidade_atual, 0) <= 0)::integer
    into v_itens_ativos, v_com_minimo, v_abaixo, v_zerados
  from public.itens as item
  left join public.estoque as saldo
    on saldo.item_id = item.id
   and saldo.tenant_id = item.tenant_id
   and saldo.empresa_id = item.empresa_id
  where item.tenant_id = v_tenant_id
    and item.empresa_id = v_empresa_id
    and item.tipo = 'produto'
    and item.ativo is true
    and item.controla_estoque is true;

  -- Fila de reposicao: zerado primeiro, depois quem esta mais longe do minimo.
  select coalesce(jsonb_agg(linha order by (linha->>'falta')::numeric desc), '[]'::jsonb)
    into v_repor
  from (
    select jsonb_build_object(
      'item_id', item.id,
      'codigo', item.codigo_interno,
      'nome', coalesce(item.nome, item.descricao),
      'unidade', item.unidade_medida,
      'saldo', coalesce(saldo.quantidade_atual, 0),
      'minimo', item.estoque_minimo,
      'falta', item.estoque_minimo - coalesce(saldo.quantidade_atual, 0)
    ) as linha
    from public.itens as item
    left join public.estoque as saldo
      on saldo.item_id = item.id
     and saldo.tenant_id = item.tenant_id
     and saldo.empresa_id = item.empresa_id
    where item.tenant_id = v_tenant_id
      and item.empresa_id = v_empresa_id
      and item.tipo = 'produto'
      and item.ativo is true
      and item.controla_estoque is true
      and item.estoque_minimo > 0
      and coalesce(saldo.quantidade_atual, 0) < item.estoque_minimo
    order by (item.estoque_minimo - coalesce(saldo.quantidade_atual, 0)) desc
    limit 10
  ) as fila;

  -- O que mais saiu no mes.
  select coalesce(jsonb_agg(linha order by (linha->>'quantidade')::numeric desc), '[]'::jsonb)
    into v_giro
  from (
    select jsonb_build_object(
      'item_id', item.id,
      'codigo', item.codigo_interno,
      'nome', coalesce(item.nome, item.descricao),
      'unidade', item.unidade_medida,
      'quantidade', sum(movimento.quantidade),
      'vezes', count(*)
    ) as linha
    from public.movimentacoes as movimento
    join public.itens as item
      on item.id = movimento.item_id
     and item.tenant_id = movimento.tenant_id
     and item.empresa_id = movimento.empresa_id
    where movimento.tenant_id = v_tenant_id
      and movimento.empresa_id = v_empresa_id
      and movimento.tipo = 'saida'
      and movimento.data_movimentacao >= v_inicio
      and movimento.data_movimentacao < v_fim
    group by item.id, item.codigo_interno, item.nome, item.descricao, item.unidade_medida
    order by sum(movimento.quantidade) desc
    limit 8
  ) as top;

  return jsonb_build_object(
    'ano', v_ano,
    'mes', v_mes,
    'cadastros_mes', v_cadastros_mes,
    'cadastros_ano', v_cadastros_ano,
    'cadastros', v_cadastros,
    'entradas_mes', v_entradas,
    'saidas_mes', v_saidas,
    'itens_ativos', v_itens_ativos,
    'itens_com_minimo', v_com_minimo,
    'abaixo_do_minimo', v_abaixo,
    'zerados', v_zerados,
    'repor', v_repor,
    'giro', v_giro
  );
end;
$function$;

revoke all on function public.app_estoque_painel(integer, integer) from public, anon;
grant execute on function public.app_estoque_painel(integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
