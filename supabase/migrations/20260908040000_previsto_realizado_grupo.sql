-- Previsto x Realizado passa a somar todas as empresas do tenant, e nao apenas
-- a empresa do contexto. Decisao de Gabriel em 08/09/2026.
--
-- Motivo: faturamento e por empresa porque cada uma emite as proprias notas,
-- mas caixa e da casa. Com o recorte de uma empresa so, setembro escondia
-- R$ 242 mil de despesa e R$ 171 mil de receita da SGU, e o numero nao batia
-- com a tela de contas a pagar e receber que a diretoria ja usa.
--
-- Conferido: somando as duas empresas o resultado bate exatamente com aquela
-- tela — saldo inicial 739.351,69, previsto 804.783,92 / 1.401.253,72 e
-- realizado 208.821,93 / 331.771,32 em setembro de 2026.
--
-- So entram empresas em que o usuario tem acesso financeiro. Quem enxerga uma
-- so ve o total de uma so, e a lista de nomes devolvida deixa a tela dizer de
-- quem e o numero — o bloco fica logo acima do faturamento, que e de uma
-- empresa, e sem o rotulo daria para confundir os dois.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.app_previsto_realizado(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'f', 'c'
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
  v_empresa_ids uuid[];
  v_empresa_nomes text[];
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
    array_agg(empresa.id order by empresa.razao_social),
    array_agg(coalesce(nullif(btrim(empresa.nome_fantasia), ''), empresa.razao_social) order by empresa.razao_social)
    into v_empresa_ids, v_empresa_nomes
  from c.empresa as empresa
  where empresa.tenant_id = v_tenant_id
    and empresa.deleted_at is null
    and f.has_finance_access(v_tenant_id, empresa.id);

  if v_empresa_ids is null or cardinality(v_empresa_ids) = 0 then
    raise exception 'Seu perfil não tem acesso ao previsto e realizado.';
  end if;

  select
    coalesce(sum(titulo.valor) filter (where titulo.tipo = 'AR'), 0),
    coalesce(sum(titulo.valor) filter (where titulo.tipo = 'AP'), 0),
    coalesce(sum(greatest(0, titulo.valor - coalesce(titulo.valor_aberto, 0))) filter (where titulo.tipo = 'AR'), 0),
    coalesce(sum(greatest(0, titulo.valor - coalesce(titulo.valor_aberto, 0))) filter (where titulo.tipo = 'AP'), 0)
    into v_previsto_receitas, v_previsto_despesas, v_realizado_receitas, v_realizado_despesas
  from f.contas_pagar_receber_listar_v4(
    v_tenant_id,
    v_empresa_ids,
    v_inicio,
    v_fim,
    'vencimento'
  ) as titulo
  where upper(coalesce(titulo.titulo_status, '')) <> 'CANCELADO';

  select
    coalesce(sum(saldo.saldo_inicial_periodo), 0),
    count(*)::integer
    into v_saldo_inicial, v_contas_configuradas
  from f.contas_bancarias_saldos_ativos(
    v_tenant_id,
    v_empresa_ids,
    v_inicio,
    v_fim,
    v_fim
  ) as saldo
  where saldo.configurada is true;

  return jsonb_build_object(
    'ano', v_ano,
    'mes', v_mes,
    'empresas', to_jsonb(v_empresa_nomes),
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
