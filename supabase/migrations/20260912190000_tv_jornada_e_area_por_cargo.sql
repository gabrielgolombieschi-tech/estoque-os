-- Duas definicoes do Gabriel em 12/09/2026, depois de ver o painel de TV:
--
-- 1. A area do colaborador (mecanica ou eletrica) pode ser deduzida do cargo que
--    ja existe. Os cargos reais da empresa sao inequivocos: quem e de mecanica
--    tem MEC no cargo (MECANICO, AUXILIAR MEC, PROJETISTA MEC, ENGENHEIRO
--    MECANICO, COORDENADOR MECANICO) e quem e de eletrica tem ELE (ELETRICISTA,
--    AUXILIAR ELE, COORDENADOR ELETRICA, ENGENHEIRO ELETRICISTA). Segurança e
--    programação nao sao nenhuma das duas e ficam sem area.
--    O preenchimento aqui e so um ponto de partida: a partir de agora quem manda
--    e o campo Área do cadastro de colaboradores, e esta migration nunca
--    sobrescreve area ja preenchida.
--
-- 2. A jornada da fabrica: segunda a quinta das 7:30 as 12:00 e das 13:00 as
--    17:30 (9 horas), sexta ate as 16:30 (8 horas). Total de 44 horas na semana.
--    Isso da ao painel a conta que faltava: quanto ja foi apontado e quanto falta
--    para fechar a semana.
--
-- A jornada fica numa tabela, e nao numa constante dentro da funcao, porque
-- horario de fabrica muda (banco de horas, turno de verao, acordo coletivo) e
-- mudar isso nao pode exigir migration nova.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

set local role postgres;

-- 1. Area deduzida do cargo ----------------------------------------------------------

-- Cargo com as duas marcas (ou com nenhuma) fica sem area de proposito: e melhor
-- a pessoa nao aparecer em nenhuma TV do que aparecer na errada.
update public.colaboradores
   set area = case
     when upper(coalesce(cargo, '')) like '%MEC%'
      and upper(coalesce(cargo, '')) not like '%ELE%' then 'mecanica'
     when upper(coalesce(cargo, '')) like '%ELE%'
      and upper(coalesce(cargo, '')) not like '%MEC%' then 'eletrica'
     else null
   end
 where area is null
   and cargo is not null;

-- 2. Jornada padrao -------------------------------------------------------------------

create table if not exists public.jornada_padrao (
  tenant_id uuid not null,
  empresa_id uuid not null,
  dow smallint not null,
  horas numeric(5, 2) not null,
  atualizado_em timestamptz not null default now(),
  atualizado_por_user_id uuid,
  primary key (tenant_id, empresa_id, dow),
  constraint chk_jornada_padrao_dow check (dow between 1 and 7),
  constraint chk_jornada_padrao_horas check (horas >= 0 and horas <= 24)
);

comment on table public.jornada_padrao is
  'Horas previstas por dia da semana (1 = segunda ... 7 = domingo) em cada empresa. E a referencia do painel de TV para dizer quanto falta fechar na semana; nao controla ponto nem folha.';

alter table public.jornada_padrao enable row level security;
revoke all on table public.jornada_padrao from public, anon, authenticated;
grant select, insert, update, delete, truncate, references, trigger
  on public.jornada_padrao to service_role;

drop trigger if exists trg_jornada_padrao_audit on public.jornada_padrao;
create trigger trg_jornada_padrao_audit
after insert or update or delete on public.jornada_padrao
for each row execute function public.audit_trigger();

-- Segunda a quinta 9h, sexta 8h, fim de semana zero. Entra para as empresas que
-- ja existem e nao mexe em quem ja tiver jornada gravada.
insert into public.jornada_padrao (tenant_id, empresa_id, dow, horas)
select empresa.tenant_id, empresa.id, d.dow,
       case d.dow when 5 then 8 when 6 then 0 when 7 then 0 else 9 end
from public.empresas as empresa
cross join (select generate_series(1, 7) as dow) as d
on conflict (tenant_id, empresa_id, dow) do nothing;

-- 3. tv_periodos passa a devolver a previsao do dia -------------------------------------

-- Dia nao util (fim de semana ou feriado) tem previsao zero, mesmo que a jornada
-- diga outra coisa: o calendario manda.
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
  v_previsto_total numeric;
  v_previsto_ate_hoje numeric;
begin
  select * into v_ctx from public.fn_tv_contexto();

  v_inicio_semana := (date_trunc('week', v_hoje::timestamp))::date;
  v_inicio := coalesce(p_inicio, v_inicio_semana);
  v_fim := coalesce(p_fim, v_inicio_semana + 6);

  if v_fim < v_inicio or v_fim - v_inicio > 366 then
    raise exception 'Informe um período de até 367 dias.';
  end if;

  with dias as (
    select
      s.dia::date as data,
      extract(isodow from s.dia)::int as dow,
      (extract(isodow from s.dia) between 1 and 5 and feriado.descricao is null) as eh_util,
      feriado.descricao as feriado,
      (s.dia::date <= v_hoje) as passado,
      case
        when extract(isodow from s.dia) between 1 and 5 and feriado.descricao is null
          then coalesce(jornada.horas, 0)
        else 0
      end as horas_previstas
    from generate_series(v_inicio, v_fim, interval '1 day') as s(dia)
    left join lateral (
      select f.descricao from public.feriados as f where f.data = s.dia::date limit 1
    ) as feriado on true
    left join public.jornada_padrao as jornada
      on jornada.tenant_id = v_ctx.tenant_id
     and jornada.empresa_id = v_ctx.empresa_id
     and jornada.dow = extract(isodow from s.dia)::int
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      -- generate_series com interval devolve timestamp; a tela precisa de
      -- 'AAAA-MM-DD' puro para nao passar por new Date() na televisao.
      'data', data,
      'dow', dow,
      'eh_util', eh_util,
      'feriado', feriado,
      'passado', passado,
      'horas_previstas', horas_previstas
    ) order by data), '[]'::jsonb),
    coalesce(sum(horas_previstas), 0),
    coalesce(sum(horas_previstas) filter (where passado), 0)
    into v_dias, v_previsto_total, v_previsto_ate_hoje
  from dias;

  return jsonb_build_object(
    'hoje', v_hoje,
    'inicio_semana', v_inicio_semana,
    'inicio_mes', (date_trunc('month', v_hoje::timestamp))::date,
    'papel', v_ctx.papel,
    'dias', v_dias,
    -- Previsto do periodo inteiro e previsto so ate hoje: a televisao cobra o que
    -- ja deveria ter sido apontado, nao o que ainda vai acontecer.
    'horas_previstas', v_previsto_total,
    'horas_previstas_ate_hoje', v_previsto_ate_hoje
  );
end;
$function$;

-- 4. Conferencia --------------------------------------------------------------------------

do $assertions$
declare
  v_previsto numeric;
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'jornada_padrao' and c.relrowsecurity) then
    raise exception 'jornada_padrao_sem_rls';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'jornada_padrao') then
    raise exception 'jornada_padrao_com_policy';
  end if;
  if has_table_privilege('authenticated', 'public.jornada_padrao', 'select') then
    raise exception 'jornada_padrao_aberta';
  end if;

  -- A semana da fabrica fecha em 44 horas.
  select sum(horas) into v_previsto
  from public.jornada_padrao
  where (tenant_id, empresa_id) = (select tenant_id, id from public.empresas order by criado_em nulls last, id limit 1);
  if v_previsto is not null and v_previsto <> 44 then
    raise exception 'jornada da semana deveria somar 44 horas, somou %', v_previsto;
  end if;

  if exists (
    select 1 from public.colaboradores
    where area is not null and area not in ('mecanica', 'eletrica')
  ) then
    raise exception 'area_invalida_apos_backfill';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
