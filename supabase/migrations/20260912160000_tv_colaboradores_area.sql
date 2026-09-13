-- Tela de TV por colaborador: horas da semana e do mes, e tarefas pendentes,
-- separadas por area de trabalho (mecanica ou eletrica).
--
-- Por que funcoes novas em vez de reaproveitar as de tarefas e de horas: a conta
-- da televisao tem papel PAINEL_TV, nao e pessoa e nao tem colaborador
-- vinculado. As leituras existentes sao todas "de alguem" — fn_tarefas_contexto
-- so abre a porta para gestao, responsavel da OS ou o proprio colaborador, e a
-- policy de apontamentos_horas exige can('apontamentos','read'), que e falso
-- para PAINEL_TV. Resultado: hoje a TV le zero linha de tarefa e zero linha de
-- hora. As funcoes abaixo sao autorizadas pelo PAPEL, nao pela pessoa, e por
-- isso nao passam pelo contexto de tarefas.
--
-- O que a TV nunca ve: valor da hora, custo e fator aplicado. A vw_apontamentos_horas_custo
-- fica de fora de proposito — ela carrega remuneracao e a tela fica numa
-- televisao aberta no chao de fabrica.
--
-- Nada de policy nem de grant de select nas tabelas de tarefas: elas seguem com
-- RLS ligada e sem policy (a propria migration de tarefas derruba o deploy se
-- alguem abrir), e o acesso continua so por funcao SECURITY DEFINER.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Todas as funcoes do banco pertencem a postgres.
set local role postgres;

-- 1. Area do colaborador ---------------------------------------------------------

alter table public.colaboradores
  add column if not exists area text;

comment on column public.colaboradores.area is
  'Frente de trabalho do colaborador para os paineis de TV: mecanica, eletrica ou nulo quando nao se aplica.';

do $area$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.colaboradores'::regclass
      and conname = 'chk_colaboradores_area'
  ) then
    alter table public.colaboradores
      add constraint chk_colaboradores_area
      check (area is null or area in ('mecanica', 'eletrica'));
  end if;
end;
$area$;

-- A TV filtra por area dentro da empresa; o indice cobre exatamente essa varredura.
create index if not exists idx_colaboradores_area
  on public.colaboradores (tenant_id, empresa_id, area)
  where ativo is true;

-- 2. Autorizacao pelo papel --------------------------------------------------------

-- Quem pode abrir um painel de TV: a conta da televisao e a gestao (que precisa
-- conseguir conferir a tela sem trocar de conta). Levanta para todo o resto —
-- inclusive para o colaborador comum, que ja tem as proprias telas no aplicativo.
create or replace function public.fn_tv_contexto()
returns table (tenant_id uuid, empresa_id uuid, papel text)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  v_papel := coalesce(a.fn_current_empresa_papel(v_tenant_id, v_empresa_id), '');

  if v_papel not in ('PAINEL_TV', 'ADMIN', 'DIRETOR', 'COORDENACAO') then
    raise exception 'Este painel é restrito ao perfil de painel de TV e à gestão.';
  end if;

  return query select v_tenant_id, v_empresa_id, v_papel;
end;
$function$;

-- Area aceita na consulta: nula (todos) ou uma das duas frentes.
create or replace function public.fn_tv_area(p_area text)
returns text
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_area text := nullif(btrim(lower(coalesce(p_area, ''))), '');
begin
  if v_area is not null and v_area not in ('mecanica', 'eletrica') then
    raise exception 'Área inválida: %. Use mecanica, eletrica ou nenhuma.', p_area;
  end if;
  return v_area;
end;
$function$;

-- 3. Periodos e lista de colaboradores ------------------------------------------

-- A semana e o mes sao contados aqui, no fuso da operacao, e nao no navegador da
-- televisao: a maquina ligada na TV pode estar com a data errada e ninguem
-- olhando. Semana comeca na segunda; mes no dia 1.
--
-- Devolve tambem os dias do periodo com eh_util, decidido pelo MESMO calendario
-- que classifica a hora extra do colaborador (public.feriados), para a televisao
-- nao contradizer o que a pessoa viu no tablet num feriado municipal. Sem
-- periodo informado, devolve a semana corrente.
create or replace function public.tv_periodos(p_inicio date default null, p_fim date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_hoje date := public.fn_tablet_data_hoje();
  v_inicio_semana date;
  v_inicio date;
  v_fim date;
  v_dias jsonb;
begin
  select * into v_ctx from public.fn_tv_contexto();

  v_inicio_semana := (date_trunc('week', v_hoje::timestamp))::date;
  v_inicio := coalesce(p_inicio, v_inicio_semana);
  v_fim := coalesce(p_fim, v_inicio_semana + 6);

  if v_fim < v_inicio or v_fim - v_inicio > 366 then
    raise exception 'Informe um período de até 367 dias.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           -- generate_series com interval devolve timestamp; a tela precisa de
           -- 'AAAA-MM-DD' puro para nao passar por new Date() na televisao.
           'data', dia::date,
           'dow', extract(isodow from dia)::int,
           'eh_util', extract(isodow from dia) between 1 and 5 and feriado.descricao is null,
           'feriado', feriado.descricao,
           'passado', dia <= v_hoje
         ) order by dia), '[]'::jsonb)
    into v_dias
  from generate_series(v_inicio, v_fim, interval '1 day') as s(dia)
  left join lateral (
    select f.descricao from public.feriados as f where f.data = s.dia::date limit 1
  ) as feriado on true;

  return jsonb_build_object(
    'hoje', v_hoje,
    'inicio_semana', v_inicio_semana,
    'inicio_mes', (date_trunc('month', v_hoje::timestamp))::date,
    'papel', v_ctx.papel,
    'dias', v_dias
  );
end;
$function$;

-- A lista de quem aparece no painel. Colaborador ativo sem hora e sem tarefa
-- entra do mesmo jeito: o cartao vazio dele e justamente o que a coordenacao
-- precisa enxergar.
create or replace function public.tv_colaboradores(p_area text default null)
returns table (id uuid, nome text, cargo text, area text)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_area text := public.fn_tv_area(p_area);
begin
  select * into v_ctx from public.fn_tv_contexto();

  return query
  select colaborador.id, colaborador.nome::text, colaborador.cargo::text, colaborador.area
  from public.colaboradores as colaborador
  where colaborador.tenant_id = v_ctx.tenant_id
    and colaborador.empresa_id = v_ctx.empresa_id
    and colaborador.ativo is true
    and (v_area is null or colaborador.area = v_area)
  order by colaborador.nome;
end;
$function$;
-- 4. Tarefas do painel ---------------------------------------------------------------

-- Todas as tarefas pendentes dos colaboradores ativos da area, mais as que eles
-- concluiram hoje (para a TV conseguir mostrar o que ja saiu do caminho). Mesmo
-- formato de public.tarefa_linha, para a tela usar o vocabulario que ja existe.
--
-- minha, pode_gerir e pode_concluir vem sempre falsos: a televisao nao age, so
-- mostra.
create or replace function public.tv_colaboradores_tarefas(p_area text default null)
returns setof public.tarefa_linha
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_area text := public.fn_tv_area(p_area);
  v_hoje date := public.fn_tablet_data_hoje();
begin
  select * into v_ctx from public.fn_tv_contexto();

  return query
  select
    t.id,
    t.tipo,
    t.data,
    t.situacao,
    t.colaborador_id,
    colab.nome::text,
    false,
    t.os_id,
    coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text),
    os.cliente_id,
    coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado')::text,
    os.descricao_servico,
    coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)),
    coalesce(os.usa_relatorio_hh, false),
    public.fn_tarefas_nome_usuario(os.responsavel_aprovacao_id),
    t.descricao,
    t.criado_em,
    public.fn_tarefas_nome_usuario(t.criado_por_user_id),
    t.atualizado_em,
    t.concluida_em,
    case when t.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
         else public.fn_tarefas_nome_usuario(t.concluida_por_user_id) end,
    t.concluida_por_sessao_id is not null,
    t.cancelada_em,
    public.fn_tarefas_nome_usuario(t.cancelada_por_user_id),
    t.cancelamento_motivo,
    reserva.id is not null,
    null::timestamptz,
    null::text,
    null::text,
    (t.situacao = 'pendente' and t.data is not null and t.data < v_hoje),
    (t.data is not null and t.data = v_hoje),
    false,
    false
  from public.tarefas as t
  join public.colaboradores as colab
    on colab.id = t.colaborador_id
   and colab.ativo is true
  join public.ordens_servico as os on os.id = t.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = t.tenant_id and cli.empresa_id = t.empresa_id
  left join public.tarefas_reservas as reserva
    on reserva.tarefa_id = t.id and reserva.liberada_em is null
  where t.tenant_id = v_ctx.tenant_id
    and t.empresa_id = v_ctx.empresa_id
    and (v_area is null or colab.area = v_area)
    and (
      t.situacao = 'pendente'
      or (t.situacao = 'concluida' and (t.concluida_em at time zone 'America/Sao_Paulo')::date = v_hoje)
    )
  order by
    (t.situacao = 'pendente' and t.data is not null and t.data < v_hoje) desc,
    t.data asc nulls last,
    colab.nome asc,
    t.criado_em asc;
end;
$function$;

-- 5. Horas do painel -------------------------------------------------------------------

-- Uma linha por colaborador, OS e dia, com a soma das horas apontadas. Sem fator,
-- sem valor e sem custo. Hora recusada fica de fora; pendente entra e vem
-- marcada, para a televisao conseguir cobrar a aprovacao sem mudar o total que a
-- pessoa ja viu no aplicativo.
create or replace function public.tv_horas_periodo(
  p_inicio date,
  p_fim date,
  p_area text default null
)
returns table (
  colaborador_id uuid,
  colaborador_nome text,
  os_id integer,
  numero_os text,
  cliente_nome text,
  data date,
  horas numeric,
  status_aprovacao text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_area text := public.fn_tv_area(p_area);
begin
  select * into v_ctx from public.fn_tv_contexto();

  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 366 then
    raise exception 'Informe um período de até 367 dias.';
  end if;

  return query
  select
    apontamento.colaborador_id,
    colab.nome::text,
    apontamento.os_id,
    coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text,
    coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado')::text,
    apontamento.data,
    sum(apontamento.horas)::numeric,
    coalesce(apontamento.status_aprovacao, 'pendente')::text
  from public.apontamentos_horas as apontamento
  join public.colaboradores as colab
    on colab.id = apontamento.colaborador_id
   and colab.ativo is true
  join public.ordens_servico as os on os.id = apontamento.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = apontamento.tenant_id and cli.empresa_id = apontamento.empresa_id
  where apontamento.tenant_id = v_ctx.tenant_id
    and apontamento.empresa_id = v_ctx.empresa_id
    and apontamento.data between p_inicio and p_fim
    and coalesce(apontamento.status_aprovacao, 'pendente') <> 'rejeitado'
    and (v_area is null or colab.area = v_area)
  group by
    apontamento.colaborador_id,
    colab.nome,
    apontamento.os_id,
    os.numero_os,
    os.os_num,
    os.id,
    os.cliente_nome,
    cli.nome,
    apontamento.data,
    coalesce(apontamento.status_aprovacao, 'pendente')
  order by colab.nome, apontamento.data, 4;
end;
$function$;

-- 6. Grants ------------------------------------------------------------------------------

revoke all on function public.fn_tv_contexto() from public, anon, authenticated;
revoke all on function public.fn_tv_area(text) from public, anon, authenticated;

revoke all on function public.tv_periodos(date, date) from public, anon;
revoke all on function public.tv_colaboradores(text) from public, anon;
revoke all on function public.tv_colaboradores_tarefas(text) from public, anon;
revoke all on function public.tv_horas_periodo(date, date, text) from public, anon;

grant execute on function public.tv_periodos(date, date) to authenticated;
grant execute on function public.tv_colaboradores(text) to authenticated;
grant execute on function public.tv_colaboradores_tarefas(text) to authenticated;
grant execute on function public.tv_horas_periodo(date, date, text) to authenticated;

-- 7. Conferencia --------------------------------------------------------------------------

do $assertions$
declare
  v_acl text;
  v_def text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'colaboradores' and column_name = 'area'
  ) then
    raise exception 'coluna_area_ausente';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.colaboradores'::regclass and conname = 'chk_colaboradores_area'
  ) then
    raise exception 'check_area_ausente';
  end if;

  -- As tabelas de tarefas continuam fechadas: nem policy, nem select aberto.
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('tarefas', 'tarefas_reservas')) then
    raise exception 'policy_inesperada_em_tarefas';
  end if;
  if has_table_privilege('authenticated', 'public.tarefas', 'select') then
    raise exception 'tabela_tarefas_aberta';
  end if;

  -- Nenhuma funcao de TV pode encostar na view de custo.
  foreach v_def in array array[
    pg_get_functiondef('public.tv_colaboradores_tarefas(text)'::regprocedure),
    pg_get_functiondef('public.tv_horas_periodo(date,date,text)'::regprocedure),
    pg_get_functiondef('public.tv_periodos(date,date)'::regprocedure),
    pg_get_functiondef('public.tv_colaboradores(text)'::regprocedure)
  ] loop
    if v_def ilike '%vw_apontamentos_horas_custo%'
       or v_def ilike '%valor_hora%'
       or v_def ilike '%custo_lancamento%' then
      raise exception 'funcao_de_tv_com_valor';
    end if;
  end loop;

  -- Helpers nao ficam expostos e nada abre para anon.
  if has_function_privilege('authenticated', 'public.fn_tv_contexto()'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.fn_tv_area(text)'::regprocedure, 'execute') then
    raise exception 'helper_de_tv_exposto';
  end if;

  for v_acl in
    select coalesce(p.proacl::text, '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'tv\_%' or p.proname like 'fn\_tv\_%')
  loop
    if v_acl like '%anon=%' or v_acl like '{=X%' then
      raise exception 'grant_de_tv_aberto: %', v_acl;
    end if;
  end loop;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
