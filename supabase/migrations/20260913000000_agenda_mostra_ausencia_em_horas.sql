-- =====================================================================================
-- A Agenda passa a mostrar ausência medida em HORAS.
--
-- Folga em horas não reserva o dia, de propósito: quem tira quatro horas trabalha
-- o resto do dia, então bloquear a agenda seria mentira. Só que a Agenda é montada
-- a partir de `tarefas_reservas`, e por isso essas quatro horas não apareciam em
-- célula nenhuma: quem olhava a semana não enxergava que a pessoa tinha parte do
-- dia fora. Era invisível justamente na tela onde a coordenação planeja.
--
-- A função passa a devolver também essas linhas, com `reserva_dia = false` para a
-- tela saber que o dia NÃO está tomado, e `horas` para dizer quanto saiu. As
-- linhas que vêm de reserva continuam com `reserva_dia = true` e `horas` nulo.
--
-- É DROP + CREATE porque as colunas de saída mudaram.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

drop function if exists public.app_tarefas_agenda(date, date);

create function public.app_tarefas_agenda(p_de date, p_ate date)
returns table (
  data date,
  colaborador_id uuid,
  colaborador_nome text,
  tarefa_id uuid,
  situacao text,
  detalhe_visivel boolean,
  numero_os text,
  cliente_nome text,
  descricao text,
  categoria text,
  -- false só na ausência medida em horas: a pessoa tem parte do dia fora, mas o
  -- dia continua disponível para trabalho.
  reserva_dia boolean,
  horas numeric
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  if p_de is null or p_ate is null or p_ate < p_de or p_ate - p_de > 92 then
    raise exception 'Informe um período de até 93 dias.';
  end if;

  return query
  -- 1. O que reserva o dia: trabalho e ausência medida em dias.
  select
    r.data,
    r.colaborador_id,
    colab.nome::text,
    r.tarefa_id,
    t.situacao,
    vis.visivel,
    case when vis.visivel and t.categoria = 'os'
         then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    case when vis.visivel and t.categoria = 'os'
         then coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente não informado')::text end,
    case when vis.visivel then t.descricao end,
    t.categoria,
    true,
    null::numeric
  from public.tarefas_reservas as r
  join public.tarefas as t on t.id = r.tarefa_id
  left join public.ordens_servico as os on os.id = t.os_id
  join public.colaboradores as colab on colab.id = r.colaborador_id
  cross join lateral (
    select (v_ctx.gestao
            or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = v_ctx.auth_uid, false))
            or (v_ctx.colaborador_id is not null and exists (
                  select 1 from public.tarefas_participantes as p
                  where p.tarefa_id = t.id and p.colaborador_id = v_ctx.colaborador_id))) as visivel
  ) as vis
  where r.liberada_em is null
    and r.tenant_id = v_ctx.tenant_id
    and r.empresa_id = v_ctx.empresa_id
    and r.data between p_de and p_ate
    and (v_ctx.pode_criar or (v_ctx.colaborador_id is not null and r.colaborador_id = v_ctx.colaborador_id))

  union all

  -- 2. A ausência em horas, que não tem reserva para pendurar a linha. Vem da
  --    tarefa direto; é sempre um dia só (chk_tarefas_duracao), então não precisa
  --    expandir intervalo.
  select
    t.data,
    part.colaborador_id,
    colab.nome::text,
    t.id,
    t.situacao,
    vis.visivel,
    null::text,
    null::text,
    case when vis.visivel then t.descricao end,
    t.categoria,
    false,
    t.horas
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab on colab.id = part.colaborador_id
  cross join lateral (
    select (v_ctx.gestao
            or (v_ctx.colaborador_id is not null and part.colaborador_id = v_ctx.colaborador_id)) as visivel
  ) as vis
  where t.tenant_id = v_ctx.tenant_id
    and t.empresa_id = v_ctx.empresa_id
    and t.categoria <> 'os'
    and t.medida = 'horas'
    and t.situacao <> 'cancelada'
    and t.data is not null
    and t.data between p_de and p_ate
    and (v_ctx.pode_criar or (v_ctx.colaborador_id is not null and part.colaborador_id = v_ctx.colaborador_id))

  order by 1, 3, 11 desc;
end;
$function$;

comment on function public.app_tarefas_agenda(date, date) is
  'Grade da semana por data e colaborador. reserva_dia = false é a ausência medida em horas: a pessoa tem parte do dia fora, mas o dia segue disponível para trabalho.';

revoke all on function public.app_tarefas_agenda(date, date) from public, anon;
grant execute on function public.app_tarefas_agenda(date, date) to authenticated;

do $assertions$
begin
  -- O que importa amarrar: as duas colunas novas existem e a antiga continua.
  if not exists (
    select 1 from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_tarefas_agenda'
      and 'reserva_dia' = any(p.proargnames)
      and 'horas' = any(p.proargnames)
      and 'categoria' = any(p.proargnames)
  ) then
    raise exception 'app_tarefas_agenda ficou sem reserva_dia, horas ou categoria';
  end if;

  if (select count(*) from pg_proc as p join pg_namespace as n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'app_tarefas_agenda') <> 1 then
    raise exception 'app_tarefas_agenda ficou com mais de uma assinatura';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
