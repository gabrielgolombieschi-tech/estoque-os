-- Previsto x Realizado do mes para a tela Inicio do app, para ADMIN, DIRETOR,
-- FINANCEIRO e FATURAMENTO. Pedido de Gabriel em 08/09/2026: esses quatro
-- perfis veem a mesma Home da coordenacao, com este bloco acima do faturamento.
--
-- O calculo repete exatamente o que a tela web faz em
-- app/financeiro/contas_pagar_receber/page.tsx, e reaproveita as mesmas duas
-- funcoes que ela chama — f.contas_pagar_receber_listar_v4 e
-- f.contas_bancarias_saldos_ativos. Se um dia a regra mudar la, muda aqui
-- junto, porque a fonte e a mesma:
--
--   previsto.receitas  = soma do valor dos titulos a receber do periodo
--   previsto.despesas  = soma do valor dos titulos a pagar
--   realizado.receitas = soma de (valor - valor_aberto), ou seja o que entrou
--   realizado.despesas = idem, o que saiu
--   saldo_inicial      = soma do saldo inicial das contas configuradas
--   saldo_final        = saldo_inicial + receitas - despesas
--
-- Titulo CANCELADO fica de fora, como na web. A base de data e o vencimento,
-- que e o padrao da tela.
--
-- Diferente do painel de faturamento, este bloco nao tem piso de ano: os
-- titulos a pagar e a receber sempre nasceram dentro do sistema.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.app_previsto_realizado(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'f'
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
  v_previsto_receitas numeric := 0;
  v_previsto_despesas numeric := 0;
  v_realizado_receitas numeric := 0;
  v_realizado_despesas numeric := 0;
  v_saldo_inicial numeric := 0;
  v_contas_configuradas integer := 0;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if not f.has_finance_access(v_tenant_id, v_empresa_id) then
    raise exception 'Seu perfil não tem acesso ao previsto e realizado.';
  end if;

  if v_mes < 1 or v_mes > 12 then
    raise exception 'Mês inválido.';
  end if;

  v_inicio := make_date(v_ano, v_mes, 1);
  v_fim := (v_inicio + interval '1 month - 1 day')::date;

  select
    coalesce(sum(titulo.valor) filter (where titulo.tipo = 'AR'), 0),
    coalesce(sum(titulo.valor) filter (where titulo.tipo = 'AP'), 0),
    coalesce(sum(greatest(0, titulo.valor - coalesce(titulo.valor_aberto, 0))) filter (where titulo.tipo = 'AR'), 0),
    coalesce(sum(greatest(0, titulo.valor - coalesce(titulo.valor_aberto, 0))) filter (where titulo.tipo = 'AP'), 0)
    into v_previsto_receitas, v_previsto_despesas, v_realizado_receitas, v_realizado_despesas
  from f.contas_pagar_receber_listar_v4(
    v_tenant_id,
    array[v_empresa_id],
    v_inicio,
    v_fim,
    'vencimento'
  ) as titulo
  where upper(coalesce(titulo.titulo_status, '')) <> 'CANCELADO';

  -- Saldo inicial: so as contas que tem saldo configurado no periodo entram,
  -- do mesmo jeito que a web faz. Conta sem configuracao nao vira zero na
  -- soma, ela simplesmente nao participa.
  select
    coalesce(sum(saldo.saldo_inicial_periodo), 0),
    count(*)::integer
    into v_saldo_inicial, v_contas_configuradas
  from f.contas_bancarias_saldos_ativos(
    v_tenant_id,
    array[v_empresa_id],
    v_inicio,
    v_fim,
    v_fim
  ) as saldo
  where saldo.configurada is true;

  return jsonb_build_object(
    'ano', v_ano,
    'mes', v_mes,
    'saldo_inicial', v_saldo_inicial,
    'contas_configuradas', v_contas_configuradas,
    'previsto', jsonb_build_object(
      'receitas', v_previsto_receitas,
      'despesas', v_previsto_despesas,
      'saldo_final', v_saldo_inicial + v_previsto_receitas - v_previsto_despesas
    ),
    'realizado', jsonb_build_object(
      'receitas', v_realizado_receitas,
      'despesas', v_realizado_despesas,
      'saldo_final', v_saldo_inicial + v_realizado_receitas - v_realizado_despesas
    )
  );
end;
$function$;

revoke all on function public.app_previsto_realizado(integer, integer) from public, anon;
grant execute on function public.app_previsto_realizado(integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
