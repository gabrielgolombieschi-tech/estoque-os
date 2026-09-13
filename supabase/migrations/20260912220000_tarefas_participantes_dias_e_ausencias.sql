-- Tarefas: varias pessoas, duracao em dias e registro de ausencia.
--
-- Tres definicoes do Gabriel em 12/09/2026, olhando a tela "Nova tarefa":
--
-- 1. Uma tarefa pode ter VARIAS pessoas. Exemplo dele: Alciono e Gabriel, dia
--    14/09, 2 dias, OS 199.
-- 2. Uma tarefa pode durar VARIOS DIAS, informando a data inicial e quantos dias.
-- 3. A tarefa passa a registrar tambem AUSENCIA: folga, ferias e outros, medidos
--    em dias ou em horas.
--
-- O que isso muda no modelo:
--
-- * tarefas.colaborador_id sai e vira public.tarefas_participantes. A conclusao
--   passa a ser por pessoa: numa tarefa de tres, cada uma fecha a sua parte, e a
--   tarefa fica concluida quando a ultima fechar. Isso atende as duas leituras
--   possiveis sem precisar escolher agora.
-- * tarefas.data continua sendo o primeiro dia e entra tarefas.dias. A reserva
--   passa a ser uma linha por PESSOA e por DIA: duas pessoas por dois dias sao
--   quatro reservas, e basta um dia ocupado de uma delas para a operacao inteira
--   ser recusada. O indice unico parcial que ja existia continua sendo quem
--   garante isso.
-- * tarefas.categoria diz se e trabalho numa OS ou ausencia (folga, ferias,
--   outro). Ausencia nao tem OS, entao os_id deixa de ser obrigatorio.
-- * tarefas.medida diz se a duracao e em dias ou em horas. Ausencia em HORAS
--   (folga de 4h) nao reserva o dia: a pessoa trabalha o resto dele. Ausencia em
--   DIAS reserva, e por isso ninguem consegue agenda-la naquele dia.
--
-- E no painel de TV (decisao do Gabriel): ausencia DESCONTA DA SEMANA. Ela nao
-- conta como hora cumprida; o que ela faz e tirar o dia (ou as horas) da
-- cobranca, entao quem tirou ferias na quarta passa a dever 35h em vez de 44h e
-- o dia nao aparece em vermelho como se a pessoa tivesse esquecido de apontar.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

set local role postgres;

-- 1. Colunas novas em tarefas -----------------------------------------------------

alter table public.tarefas
  add column if not exists categoria text not null default 'os',
  add column if not exists dias smallint not null default 1,
  add column if not exists medida text not null default 'dias',
  add column if not exists horas numeric(6, 2);

comment on column public.tarefas.categoria is
  'os = trabalho numa ordem de servico; folga, ferias e outro = ausencia, sem OS.';
comment on column public.tarefas.dias is
  'Quantos dias corridos a tarefa ocupa a partir de data. Vale 1 quando e de um dia so, e 1 tambem quando a medida e horas.';
comment on column public.tarefas.medida is
  'dias = ocupa o dia inteiro (e reserva a agenda); horas = ocupa parte do dia e nao reserva.';
comment on column public.tarefas.horas is
  'Quantas horas, quando medida = horas. E o que sai da cobranca da semana no painel de TV.';

alter table public.tarefas alter column os_id drop not null;

do $regras$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_categoria') then
    alter table public.tarefas add constraint chk_tarefas_categoria
      check (categoria in ('os', 'folga', 'ferias', 'outro'));
  end if;

  -- Trabalho exige OS; ausencia nunca tem OS.
  if not exists (select 1 from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_os_por_categoria') then
    alter table public.tarefas add constraint chk_tarefas_os_por_categoria
      check ((categoria = 'os') = (os_id is not null));
  end if;

  if not exists (select 1 from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_medida') then
    alter table public.tarefas add constraint chk_tarefas_medida
      check (medida in ('dias', 'horas'));
  end if;

  -- Em horas: exatamente um dia e a quantidade de horas preenchida.
  -- Em dias: de 1 a 60 dias e nada em horas.
  if not exists (select 1 from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_duracao') then
    alter table public.tarefas add constraint chk_tarefas_duracao
      check (
        (medida = 'dias' and dias between 1 and 60 and horas is null)
        or (medida = 'horas' and dias = 1 and horas > 0 and horas <= 24)
      );
  end if;

  -- Duracao so faz sentido com data: tarefa sem data ocupa um dia so, no futuro.
  if not exists (select 1 from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_dias_por_tipo') then
    alter table public.tarefas add constraint chk_tarefas_dias_por_tipo
      check (tipo = 'agendada' or (dias = 1 and medida = 'dias'));
  end if;

  -- Ausencia sempre tem data: nao existe "ferias sem data".
  if not exists (select 1 from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_ausencia_agendada') then
    alter table public.tarefas add constraint chk_tarefas_ausencia_agendada
      check (categoria = 'os' or tipo = 'agendada');
  end if;
end;
$regras$;

-- 2. Participantes ------------------------------------------------------------------

create table if not exists public.tarefas_participantes (
  tarefa_id uuid not null references public.tarefas (id) on delete cascade,
  colaborador_id uuid not null references public.colaboradores (id),
  -- Copia de colaboradores.user_id no momento em que a pessoa entrou, igual ao
  -- que tarefas_reservas ja faz: e o que impede a mesma pessoa de ser reservada
  -- por caminhos diferentes.
  usuario_id uuid,
  criado_em timestamptz not null default now(),
  criado_por_user_id uuid,
  concluida_em timestamptz,
  concluida_por_user_id uuid,
  concluida_por_sessao_id uuid references public.tablet_sessoes (id),
  primary key (tarefa_id, colaborador_id)
);

comment on table public.tarefas_participantes is
  'Quem participa de cada tarefa. A conclusao e por pessoa: a tarefa fica concluida quando o ultimo participante fecha a parte dele.';

create index if not exists idx_tarefas_participantes_colaborador
  on public.tarefas_participantes (colaborador_id);

alter table public.tarefas_participantes enable row level security;
revoke all on table public.tarefas_participantes from public, anon, authenticated;
grant select, insert, update, delete, truncate, references, trigger
  on public.tarefas_participantes to service_role;

drop trigger if exists trg_tarefas_participantes_audit on public.tarefas_participantes;
create trigger trg_tarefas_participantes_audit
after insert or update or delete on public.tarefas_participantes
for each row execute function public.audit_trigger();

-- Traz quem ja estava na coluna antiga, com a conclusao que a tarefa tinha.
-- Em SQL dinamico porque a coluna sai logo abaixo: sem isto, reaplicar o arquivo
-- quebraria referenciando uma coluna que nao existe mais.
do $backfill$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tarefas' and column_name = 'colaborador_id'
  ) then
    execute $sql$
      insert into public.tarefas_participantes (
        tarefa_id, colaborador_id, usuario_id, criado_em, criado_por_user_id,
        concluida_em, concluida_por_user_id, concluida_por_sessao_id
      )
      select
        t.id,
        t.colaborador_id,
        colab.user_id,
        t.criado_em,
        t.criado_por_user_id,
        t.concluida_em,
        t.concluida_por_user_id,
        t.concluida_por_sessao_id
      from public.tarefas as t
      join public.colaboradores as colab on colab.id = t.colaborador_id
      on conflict (tarefa_id, colaborador_id) do nothing
    $sql$;
  end if;
end;
$backfill$;

-- 3. A coluna antiga sai --------------------------------------------------------------

-- As funcoes que liam tarefas.colaborador_id sao recriadas na proxima migration,
-- que vem junto desta no mesmo db push. Aqui a coluna sai para nao sobrar duas
-- fontes de verdade sobre quem e o dono da tarefa.
alter table public.tarefas drop column if exists colaborador_id cascade;

-- 4. Conferencia -----------------------------------------------------------------------

do $assertions$
declare
  v_sem_participante integer;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tarefas' and column_name = 'colaborador_id'
  ) then
    raise exception 'coluna_colaborador_id_ainda_existe';
  end if;

  select count(*) into v_sem_participante
  from public.tarefas as t
  where not exists (select 1 from public.tarefas_participantes as p where p.tarefa_id = t.id);
  if v_sem_participante > 0 then
    raise exception 'tarefas_sem_participante: %', v_sem_participante;
  end if;

  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'tarefas_participantes' and c.relrowsecurity) then
    raise exception 'participantes_sem_rls';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarefas_participantes') then
    raise exception 'participantes_com_policy';
  end if;
  if has_table_privilege('authenticated', 'public.tarefas_participantes', 'select') then
    raise exception 'participantes_aberto_para_authenticated';
  end if;
end;
$assertions$;

commit;

-- =====================================================================================
-- Parte 2: as funcoes. Tudo o que lia tarefas.colaborador_id passa a ler
-- tarefas_participantes, e o que reservava um dia passa a reservar um intervalo.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 5. O tipo da linha ganha o que a tarefa agora tem -------------------------------------

do $tipo$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join pg_attribute a on a.attrelid = t.typrelid
    where n.nspname = 'public' and t.typname = 'tarefa_linha'
      and a.attname = 'categoria' and not a.attisdropped
  ) then
    alter type public.tarefa_linha add attribute categoria text cascade;
    alter type public.tarefa_linha add attribute medida text cascade;
    alter type public.tarefa_linha add attribute dias smallint cascade;
    alter type public.tarefa_linha add attribute horas numeric cascade;
    alter type public.tarefa_linha add attribute data_fim date cascade;
    alter type public.tarefa_linha add attribute participantes integer cascade;
    alter type public.tarefa_linha add attribute participante_concluida_em timestamptz cascade;
  end if;
end;
$tipo$;

-- 6. Apoio ------------------------------------------------------------------------------

-- Os dias que a tarefa ocupa. Em horas e sempre um dia so.
create or replace function public.fn_tarefas_dias(p_data date, p_dias smallint, p_medida text)
returns setof date
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select (p_data + offset_dia)::date
  from generate_series(0, case when p_medida = 'horas' then 0 else greatest(coalesce(p_dias, 1), 1) - 1 end) as s(offset_dia)
  where p_data is not null;
$function$;

-- Quem administra a tarefa: a gestao sempre; o responsavel da OS quando a tarefa
-- e de trabalho. Ausencia (folga, ferias, outro) nao tem OS, entao so a gestao
-- mexe — nao existe "responsavel pelas ferias de alguem".
create or replace function public.fn_tarefas_pode_gerir(p_tarefa public.tarefas, p_auth_uid uuid, p_gestao boolean)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
  select p_gestao or (
    p_tarefa.categoria = 'os' and exists (
      select 1 from public.ordens_servico as os
      where os.id = p_tarefa.os_id
        and coalesce(os.responsavel_aprovacao_id = p_auth_uid, false)
    )
  );
$function$;

-- Reserva um intervalo inteiro para uma pessoa. Erro P0T01 com o json pronto no
-- detail quando qualquer um dos dias ja esta ocupado: a operacao inteira cai,
-- porque nao adianta reservar metade de uma tarefa de dois dias.
create or replace function public.fn_tarefas_reservar_intervalo(
  p_tarefa public.tarefas,
  p_colaborador_id uuid,
  p_usuario_id uuid,
  p_auth_uid uuid,
  p_gestao boolean,
  p_colaborador_proprio uuid
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_dia date;
  v_conflito jsonb;
  v_reservadas integer := 0;
begin
  -- Ausencia em horas nao reserva: a pessoa trabalha o resto do dia.
  if p_tarefa.tipo <> 'agendada' or p_tarefa.medida = 'horas' then
    return 0;
  end if;

  for v_dia in select * from public.fn_tarefas_dias(p_tarefa.data, p_tarefa.dias, p_tarefa.medida) loop
    perform pg_advisory_xact_lock(hashtextextended('tarefa-reserva:' || p_colaborador_id::text || ':' || v_dia::text, 0));
    if p_usuario_id is not null then
      perform pg_advisory_xact_lock(hashtextextended('tarefa-reserva-usuario:' || p_usuario_id::text || ':' || v_dia::text, 0));
    end if;

    v_conflito := public.fn_tarefas_conflito(
      p_tarefa.tenant_id, p_tarefa.empresa_id, p_colaborador_id, p_usuario_id, v_dia,
      p_tarefa.id, p_auth_uid, p_gestao, p_colaborador_proprio
    );
    if v_conflito is not null then
      raise exception using errcode = 'P0T01', message = 'colaborador_reservado', detail = v_conflito::text;
    end if;

    insert into public.tarefas_reservas (tenant_id, empresa_id, tarefa_id, colaborador_id, usuario_id, data, criado_por_user_id)
    values (p_tarefa.tenant_id, p_tarefa.empresa_id, p_tarefa.id, p_colaborador_id, p_usuario_id, v_dia, p_auth_uid);
    v_reservadas := v_reservadas + 1;
  end loop;

  return v_reservadas;
end;
$function$;

-- Libera as reservas da tarefa, de todos ou de uma pessoa so.
create or replace function public.fn_tarefas_liberar_de(
  p_tarefa_id uuid,
  p_colaborador_id uuid,
  p_auth_uid uuid,
  p_motivo text
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_liberadas integer;
begin
  update public.tarefas_reservas
     set liberada_em = now(),
         liberada_por_user_id = p_auth_uid,
         liberacao_motivo = p_motivo
   where tarefa_id = p_tarefa_id
     and liberada_em is null
     and (p_colaborador_id is null or colaborador_id = p_colaborador_id);
  get diagnostics v_liberadas = row_count;
  return v_liberadas;
end;
$function$;

-- A tarefa esta concluida quando o ultimo participante fechou a parte dele.
-- Chamar depois de mexer em tarefas_participantes.
create or replace function public.fn_tarefas_sincronizar_conclusao(p_tarefa_id uuid, p_auth_uid uuid)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_total integer;
  v_concluidos integer;
  v_ultimo timestamptz;
  v_situacao text;
begin
  select count(*), count(*) filter (where concluida_em is not null), max(concluida_em)
    into v_total, v_concluidos, v_ultimo
  from public.tarefas_participantes
  where tarefa_id = p_tarefa_id;

  select situacao into v_situacao from public.tarefas where id = p_tarefa_id;
  if v_situacao = 'cancelada' then
    return;
  end if;

  if v_total > 0 and v_concluidos = v_total then
    update public.tarefas
       set situacao = 'concluida',
           concluida_em = coalesce(v_ultimo, now()),
           concluida_por_user_id = coalesce(concluida_por_user_id, p_auth_uid),
           atualizado_em = now(),
           atualizado_por_user_id = p_auth_uid
     where id = p_tarefa_id
       and situacao <> 'concluida';
  else
    update public.tarefas
       set situacao = 'pendente',
           concluida_em = null,
           concluida_por_user_id = null,
           concluida_por_sessao_id = null,
           atualizado_em = now(),
           atualizado_por_user_id = p_auth_uid
     where id = p_tarefa_id
       and situacao = 'concluida';
  end if;
end;
$function$;

revoke all on function public.fn_tarefas_dias(date, smallint, text) from public, anon, authenticated;
revoke all on function public.fn_tarefas_pode_gerir(public.tarefas, uuid, boolean) from public, anon, authenticated;
revoke all on function public.fn_tarefas_reservar_intervalo(public.tarefas, uuid, uuid, uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.fn_tarefas_liberar_de(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.fn_tarefas_sincronizar_conclusao(uuid, uuid) from public, anon, authenticated;

commit;

-- =====================================================================================
-- Parte 3: as RPCs no modelo novo.
--
-- A leitura passa a ser UMA LINHA POR PARTICIPANTE: uma tarefa de tres pessoas
-- aparece tres vezes, uma para cada, e cada linha fala da parte daquela pessoa
-- (conclusao, reserva, atraso). E o que deixa as telas que ja existem
-- continuarem funcionando sem saber que a tarefa virou coletiva.
--
-- A escrita passa a mexer em todos os participantes de uma vez: criar reserva o
-- intervalo de cada um, reagendar libera tudo e reserva de novo, e um dia
-- ocupado de qualquer pessoa derruba a operacao inteira.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 8. O indice que dizia "uma reserva ativa por tarefa" ---------------------------------

-- Ele nasceu quando a tarefa era de uma pessoa e de um dia. Agora duas pessoas
-- por dois dias sao quatro reservas ativas da MESMA tarefa, e ele impediria
-- justamente o que o modelo novo existe para fazer. A exclusividade de verdade
-- continua nos outros dois indices (colaborador/dia e usuario/dia); no lugar
-- dele fica a garantia que ainda faz sentido: a mesma pessoa nao e reservada
-- duas vezes pela mesma tarefa no mesmo dia.
drop index if exists public.uq_tarefas_reservas__tarefa_ativa;

create unique index if not exists uq_tarefas_reservas__tarefa_pessoa_dia
  on public.tarefas_reservas (tarefa_id, colaborador_id, data)
  where liberada_em is null;

-- 9. Apoio que precisou mudar ----------------------------------------------------------

-- O conflito agora le participantes (quem pode ver a tarefa que ocupa o dia) e
-- aceita tarefa sem OS (ausencia).
create or replace function public.fn_tarefas_conflito(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_usuario_id uuid,
  p_data date,
  p_excluir_tarefa_id uuid,
  p_auth_uid uuid,
  p_gestao boolean,
  p_colaborador_proprio uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_conflito record;
  v_visivel boolean;
  v_detalhe jsonb;
begin
  select r.tarefa_id,
         r.colaborador_id,
         colab.nome::text as colaborador_nome,
         t.tenant_id,
         t.empresa_id,
         t.categoria,
         t.descricao,
         t.situacao,
         os.responsavel_aprovacao_id,
         case when t.categoria = 'os'
              then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end as numero_os,
         case when t.categoria = 'os'
              then coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente não informado') end as cliente_nome,
         exists (
           select 1 from public.tarefas_participantes as p
           where p.tarefa_id = t.id
             and p_colaborador_proprio is not null
             and p.colaborador_id = p_colaborador_proprio
         ) as sou_participante
    into v_conflito
  from public.tarefas_reservas as r
  join public.tarefas as t on t.id = r.tarefa_id
  left join public.ordens_servico as os on os.id = t.os_id
  join public.colaboradores as colab on colab.id = r.colaborador_id
  where r.liberada_em is null
    and r.data = p_data
    and (r.colaborador_id = p_colaborador_id
         or (p_usuario_id is not null and r.usuario_id = p_usuario_id))
    and (p_excluir_tarefa_id is null or r.tarefa_id <> p_excluir_tarefa_id)
  order by (r.colaborador_id = p_colaborador_id) desc
  limit 1;

  if not found then
    return null;
  end if;

  v_visivel := v_conflito.tenant_id = p_tenant_id
    and v_conflito.empresa_id = p_empresa_id
    and (p_gestao
         or (v_conflito.categoria = 'os' and coalesce(v_conflito.responsavel_aprovacao_id = p_auth_uid, false))
         or v_conflito.sou_participante);

  if v_visivel then
    v_detalhe := jsonb_build_object(
      'tarefa_id', v_conflito.tarefa_id,
      'categoria', v_conflito.categoria,
      'numero_os', v_conflito.numero_os,
      'cliente_nome', v_conflito.cliente_nome,
      'descricao', v_conflito.descricao,
      'situacao', v_conflito.situacao
    );
  end if;

  return public.fn_tarefas_erro(
    'colaborador_reservado',
    format('%s já está reservado(a) em %s.', v_conflito.colaborador_nome, to_char(p_data, 'DD/MM/YYYY'))
  ) || jsonb_build_object('conflito', v_detalhe, 'data', p_data, 'colaborador_id', p_colaborador_id);
end;
$function$;

-- A reserva de um dia so nao existe mais: quem reserva e fn_tarefas_reservar_intervalo.
drop function if exists public.fn_tarefas_reservar(public.tarefas, uuid, date, uuid, boolean, uuid);

-- 10. Leitura: uma linha por participante -----------------------------------------------

create or replace function public.fn_tarefas_linhas(p_tenant_id uuid, p_empresa_id uuid, p_auth_uid uuid, p_gestao boolean, p_colaborador_id uuid)
returns setof public.tarefa_linha
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
  with hoje as (select public.fn_tablet_data_hoje() as d)
  select
    t.id,
    t.tipo,
    t.data,
    t.situacao,
    part.colaborador_id,
    colab.nome::text,
    (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id),
    t.os_id,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    case when t.categoria = 'os' then os.cliente_id end,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado')::text end,
    case when t.categoria = 'os' then os.descricao_servico end,
    case when t.categoria = 'os'
         then coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) end,
    case when t.categoria = 'os' then coalesce(os.usa_relatorio_hh, false) end,
    case when t.categoria = 'os' then public.fn_tarefas_nome_usuario(os.responsavel_aprovacao_id) end,
    t.descricao,
    t.criado_em,
    public.fn_tarefas_nome_usuario(t.criado_por_user_id),
    t.atualizado_em,
    t.concluida_em,
    -- Quem fechou e quando: da PESSOA da linha, nao da tarefa inteira.
    case when part.concluida_em is null then null
         when part.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
         else public.fn_tarefas_nome_usuario(part.concluida_por_user_id) end,
    part.concluida_por_sessao_id is not null,
    t.cancelada_em,
    public.fn_tarefas_nome_usuario(t.cancelada_por_user_id),
    t.cancelamento_motivo,
    reserva.ativa,
    ultima.liberada_em,
    public.fn_tarefas_nome_usuario(ultima.liberada_por_user_id),
    ultima.liberacao_motivo,
    (t.situacao = 'pendente' and part.concluida_em is null and fim.data_fim is not null and fim.data_fim < hoje.d),
    (t.data is not null and hoje.d between t.data and fim.data_fim),
    gerir.pode,
    (t.situacao = 'pendente' and part.concluida_em is null
      and (gerir.pode or (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id))),
    t.categoria,
    t.medida,
    t.dias,
    t.horas,
    fim.data_fim,
    (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id),
    part.concluida_em
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab on colab.id = part.colaborador_id
  left join public.ordens_servico as os on os.id = t.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = t.tenant_id and cli.empresa_id = t.empresa_id
  cross join hoje
  cross join lateral (
    select case when t.data is null then null
                else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end as data_fim
  ) as fim
  cross join lateral (
    select (p_gestao or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = p_auth_uid, false))) as pode
  ) as gerir
  cross join lateral (
    select exists (
      select 1 from public.tarefas_reservas as r
      where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is null
    ) as ativa
  ) as reserva
  left join lateral (
    select r.liberada_em, r.liberada_por_user_id, r.liberacao_motivo
    from public.tarefas_reservas as r
    where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is not null
    order by r.liberada_em desc, r.ordem desc
    limit 1
  ) as ultima on true
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and (p_gestao
         or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = p_auth_uid, false))
         or (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id));
$function$;

-- Uma tarefa tem varias linhas; o json de uma acao devolve a de quem chamou
-- quando ela participa, e senao a primeira por nome.
create or replace function public.fn_tarefas_linha_json(p_tarefa_id uuid, p_tenant_id uuid, p_empresa_id uuid, p_auth_uid uuid, p_gestao boolean, p_colaborador_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
  select to_jsonb(linha)
  from public.fn_tarefas_linhas(p_tenant_id, p_empresa_id, p_auth_uid, p_gestao, p_colaborador_id) as linha
  where linha.id = p_tarefa_id
  order by (p_colaborador_id is not null and linha.colaborador_id = p_colaborador_id) desc,
           linha.colaborador_nome asc
  limit 1;
$function$;

-- 11. RPCs de leitura --------------------------------------------------------------------

-- Listas: 'agendadas' (pendentes com data), 'sem_data', 'ausencias' (folga,
-- ferias e outros que ainda nao terminaram), 'historico' ou 'todas'.
create or replace function public.app_tarefas_listar(
  p_secao text default 'agendadas',
  p_de date default null,
  p_ate date default null,
  p_colaborador_id uuid default null,
  p_os_id integer default null,
  p_busca text default null
)
returns setof public.tarefa_linha
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_secao text := lower(btrim(coalesce(p_secao, 'agendadas')));
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_hoje date := public.fn_tablet_data_hoje();
begin
  select * into v_ctx from public.fn_tarefas_contexto();

  if v_secao not in ('agendadas', 'sem_data', 'historico', 'todas', 'ausencias') then
    raise exception 'Seção inválida: %', v_secao;
  end if;

  return query
  select linha.*
  from public.fn_tarefas_linhas(v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id) as linha
  where (v_secao <> 'agendadas' or (linha.situacao = 'pendente' and linha.tipo = 'agendada'))
    and (v_secao <> 'sem_data' or (linha.situacao = 'pendente' and linha.tipo = 'sem_data'))
    and (v_secao <> 'historico' or linha.situacao in ('concluida', 'cancelada'))
    and (v_secao <> 'ausencias' or (linha.situacao = 'pendente' and linha.categoria <> 'os'
                                    and coalesce(linha.data_fim, v_hoje) >= v_hoje))
    and (p_colaborador_id is null or linha.colaborador_id = p_colaborador_id)
    and (p_os_id is null or linha.os_id = p_os_id)
    and (p_de is null or case
           when v_secao = 'historico' then (coalesce(linha.concluida_em, linha.cancelada_em) at time zone 'America/Sao_Paulo')::date >= p_de
           when v_secao = 'sem_data' then true
           -- Tarefa de varios dias entra no periodo se qualquer dia dela cair nele.
           else coalesce(linha.data_fim, linha.data) >= p_de end)
    and (p_ate is null or case
           when v_secao = 'historico' then (coalesce(linha.concluida_em, linha.cancelada_em) at time zone 'America/Sao_Paulo')::date <= p_ate
           when v_secao = 'sem_data' then true
           else linha.data <= p_ate end)
    and (v_busca is null
         or linha.descricao ilike '%' || v_busca || '%'
         or linha.numero_os ilike '%' || v_busca || '%'
         or linha.cliente_nome ilike '%' || v_busca || '%'
         or linha.colaborador_nome ilike '%' || v_busca || '%'
         -- Procurar por "folga" ou "férias" acha a ausencia pelo que ela e.
         or (case linha.categoria
               when 'folga' then 'folga'
               when 'ferias' then 'férias ferias'
               when 'outro' then 'ausência ausencia outro'
               else '' end) ilike '%' || v_busca || '%')
  order by
    case when v_secao = 'historico' then coalesce(linha.concluida_em, linha.cancelada_em) end desc nulls last,
    case when v_secao in ('agendadas', 'todas', 'ausencias') then linha.data end asc nulls last,
    linha.colaborador_nome asc,
    linha.criado_em desc;
end;
$function$;

create or replace function public.app_tarefas_detalhe(p_tarefa_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa jsonb;
  v_reservas jsonb;
  v_participantes jsonb;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_linha_json(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id);
  if v_tarefa is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'data', r.data,
           'colaborador_id', r.colaborador_id,
           'colaborador_nome', colab.nome,
           'criado_em', r.criado_em,
           'criado_por_nome', public.fn_tarefas_nome_usuario(r.criado_por_user_id),
           'ativa', r.liberada_em is null,
           'liberada_em', r.liberada_em,
           'liberada_por_nome', public.fn_tarefas_nome_usuario(r.liberada_por_user_id),
           'liberacao_motivo', r.liberacao_motivo
         ) order by r.ordem), '[]'::jsonb)
    into v_reservas
  from public.tarefas_reservas as r
  join public.colaboradores as colab on colab.id = r.colaborador_id
  where r.tarefa_id = p_tarefa_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'colaborador_id', p.colaborador_id,
           'nome', colab.nome,
           'concluida_em', p.concluida_em,
           'concluida_por_nome', case when p.concluida_em is null then null
                                      when p.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
                                      else public.fn_tarefas_nome_usuario(p.concluida_por_user_id) end,
           'concluida_pelo_tablet', p.concluida_por_sessao_id is not null
         ) order by colab.nome), '[]'::jsonb)
    into v_participantes
  from public.tarefas_participantes as p
  join public.colaboradores as colab on colab.id = p.colaborador_id
  where p.tarefa_id = p_tarefa_id;

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', v_tarefa,
    'participantes', v_participantes,
    'reservas', v_reservas
  );
end;
$function$;

-- Contadores da aba: tarefa conta uma vez (mesmo com varias pessoas); o que e da
-- pessoa conta por linha, porque a parte dela e que esta em aberto.
create or replace function public.app_tarefas_contar()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_resultado jsonb;
begin
  select * into v_ctx from public.fn_tarefas_contexto();

  select jsonb_build_object(
    'hoje', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.hoje),
    'atrasadas', count(distinct linha.id) filter (where linha.atrasada),
    'futuras', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.tipo = 'agendada' and not linha.hoje and not linha.atrasada),
    'agendadas', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.tipo = 'agendada'),
    'sem_data', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.tipo = 'sem_data'),
    'ausencias', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.categoria <> 'os'),
    'atencao', count(distinct linha.id) filter (where linha.situacao = 'pendente' and (linha.hoje or linha.atrasada)),
    'minhas_pendentes', count(*) filter (where linha.situacao = 'pendente' and linha.minha and linha.participante_concluida_em is null),
    'gestao', v_ctx.gestao,
    'pode_criar', v_ctx.pode_criar,
    'hoje_data', public.fn_tablet_data_hoje()
  )
    into v_resultado
  from public.fn_tarefas_linhas(v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id) as linha;

  return v_resultado;
end;
$function$;

-- A agenda ganhou a categoria: a grade precisa distinguir trabalho de ausencia.
drop function if exists public.app_tarefas_agenda(date, date);
create or replace function public.app_tarefas_agenda(p_de date, p_ate date)
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
  categoria text
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
    t.categoria
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
  order by r.data, colab.nome;
end;
$function$;

-- Colaboradores ativos para escolher na tarefa, com o dia ocupado ou nao.
create or replace function public.app_tarefas_colaboradores(p_data date default null)
returns table (
  id uuid,
  nome text,
  cargo text,
  sou_eu boolean,
  ocupado boolean,
  ocupado_tarefa_id uuid,
  ocupado_resumo text
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
  if not v_ctx.pode_criar then
    raise exception 'Seu perfil não cria tarefas.';
  end if;

  return query
  select
    colab.id,
    colab.nome::text,
    colab.cargo::text,
    colab.user_id is not distinct from v_ctx.auth_uid,
    ocupacao.tarefa_id is not null,
    case when ocupacao.visivel then ocupacao.tarefa_id end,
    case when ocupacao.tarefa_id is null then null
         when ocupacao.visivel then ocupacao.resumo
         else 'Reservado(a) neste dia' end
  from public.colaboradores as colab
  left join lateral (
    select r.tarefa_id,
           (t.tenant_id = v_ctx.tenant_id and t.empresa_id = v_ctx.empresa_id
             and (v_ctx.gestao
                  or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = v_ctx.auth_uid, false))
                  or (v_ctx.colaborador_id is not null and exists (
                        select 1 from public.tarefas_participantes as p
                        where p.tarefa_id = t.id and p.colaborador_id = v_ctx.colaborador_id)))) as visivel,
           case t.categoria
             when 'os' then 'OS ' || coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) || ' · '
                             || coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente não informado')
             when 'folga' then 'Folga'
             when 'ferias' then 'Férias'
             else 'Ausência'
           end as resumo
    from public.tarefas_reservas as r
    join public.tarefas as t on t.id = r.tarefa_id
    left join public.ordens_servico as os on os.id = t.os_id
    where p_data is not null
      and r.liberada_em is null
      and r.data = p_data
      and (r.colaborador_id = colab.id or (colab.user_id is not null and r.usuario_id = colab.user_id))
    order by (r.colaborador_id = colab.id) desc
    limit 1
  ) as ocupacao on true
  where colab.tenant_id = v_ctx.tenant_id
    and colab.empresa_id = v_ctx.empresa_id
    and colab.ativo is true
  order by colab.nome;
end;
$function$;

-- 12. Escrita ------------------------------------------------------------------------------

-- Criar: varias pessoas, varios dias, trabalho ou ausencia. Reserva o intervalo
-- de cada uma; um dia ocupado de qualquer uma derruba tudo.
drop function if exists public.app_tarefas_criar(text, uuid, integer, text, date, uuid);
create or replace function public.app_tarefas_criar(
  p_colaboradores uuid[],
  p_tipo text,
  p_data date,
  p_dias integer,
  p_descricao text,
  p_categoria text default 'os',
  p_os_id integer default null,
  p_medida text default 'dias',
  p_horas numeric default null,
  p_chave uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_os record;
  v_colab record;
  v_tarefa public.tarefas;
  v_resultado jsonb;
  v_tipo text := lower(btrim(coalesce(p_tipo, '')));
  v_categoria text := lower(btrim(coalesce(p_categoria, 'os')));
  v_medida text := lower(btrim(coalesce(p_medida, 'dias')));
  v_descricao text := btrim(coalesce(p_descricao, ''));
  v_colaboradores uuid[];
  v_informados integer;
  v_os_id integer;
  v_data date;
  v_dias smallint;
  v_horas numeric;
  v_detalhe text;
  v_ativos integer;
begin
  select * into v_ctx from public.fn_tarefas_contexto();

  if p_chave is not null then
    perform pg_advisory_xact_lock(hashtextextended('tarefa-op:' || p_chave::text, 0));
    select op.resultado into v_resultado
    from public.tarefas_operacoes as op
    where op.chave = p_chave and op.tenant_id = v_ctx.tenant_id;
    if found then
      return v_resultado || jsonb_build_object('repetido', true);
    end if;
  end if;

  if v_tipo not in ('agendada', 'sem_data') then
    return public.fn_tarefas_erro('tipo_invalido', 'Escolha o tipo da tarefa: agendada ou sem data.');
  end if;
  if v_categoria not in ('os', 'folga', 'ferias', 'outro') then
    return public.fn_tarefas_erro('categoria_invalida', 'Escolha o que a tarefa é: trabalho na OS, folga, férias ou outro.');
  end if;
  if v_medida not in ('dias', 'horas') then
    return public.fn_tarefas_erro('medida_invalida', 'A duração é medida em dias ou em horas.');
  end if;

  v_data := case when v_tipo = 'agendada' then p_data end;
  if v_tipo = 'agendada' and v_data is null then
    return public.fn_tarefas_erro('data_obrigatoria', 'Tarefa agendada precisa de uma data.');
  end if;
  -- Nao existe "férias sem data".
  if v_categoria <> 'os' and v_tipo <> 'agendada' then
    return public.fn_tarefas_erro('data_obrigatoria', 'Folga, férias e outras ausências precisam de data.');
  end if;

  if v_tipo = 'sem_data' then
    if v_medida = 'horas' then
      return public.fn_tarefas_erro('medida_invalida', 'Só tarefa agendada pode ser medida em horas.');
    end if;
    if coalesce(p_dias, 1) <> 1 then
      return public.fn_tarefas_erro('duracao_invalida', 'Tarefa sem data ocupa um dia só.');
    end if;
    v_dias := 1;
    v_horas := null;
  elsif v_medida = 'horas' then
    if p_horas is null or p_horas <= 0 or p_horas > 24 then
      return public.fn_tarefas_erro('duracao_invalida', 'Em horas, informe de 0,5 a 24 horas.');
    end if;
    v_dias := 1;
    v_horas := round(p_horas, 2);
  else
    if coalesce(p_dias, 1) < 1 or coalesce(p_dias, 1) > 60 then
      return public.fn_tarefas_erro('duracao_invalida', 'A duração vai de 1 a 60 dias.');
    end if;
    v_dias := coalesce(p_dias, 1)::smallint;
    v_horas := null;
  end if;

  if char_length(v_descricao) = 0 then
    return public.fn_tarefas_erro('descricao_obrigatoria', 'Descreva a tarefa.');
  end if;
  if char_length(v_descricao) > 2000 then
    return public.fn_tarefas_erro('descricao_longa', 'A descrição pode ter no máximo 2000 caracteres.');
  end if;

  if v_categoria = 'os' then
    if p_os_id is null then
      return public.fn_tarefas_erro('os_invalida', 'Escolha a OS da tarefa.');
    end if;
    select os.id,
           os.responsavel_aprovacao_id,
           coalesce(os.tipo_documento, 'OS') as tipo_documento,
           coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) as status_fluxo
      into v_os
    from public.ordens_servico as os
    where os.id = p_os_id
      and os.tenant_id = v_ctx.tenant_id
      and os.empresa_id = v_ctx.empresa_id;
    if not found then
      return public.fn_tarefas_erro('os_invalida', 'A OS informada não existe nesta empresa.');
    end if;
    if v_os.tipo_documento <> 'OS' then
      return public.fn_tarefas_erro('os_invalida', 'Este documento é uma venda (OV) e não recebe tarefas.');
    end if;
    if v_os.status_fluxo not in ('em_andamento', 'em_andamento_garantia') then
      return public.fn_tarefas_erro('os_encerrada', 'Esta OS não está em andamento. Tarefas só podem ser criadas em OS em andamento.');
    end if;
    if not (v_ctx.gestao or coalesce(v_os.responsavel_aprovacao_id = v_ctx.auth_uid, false)) then
      return public.fn_tarefas_erro('sem_permissao', 'Seu perfil não cria tarefas nesta OS. Fale com a coordenação ou com o responsável da OS.');
    end if;
    v_os_id := v_os.id;
  else
    if p_os_id is not null then
      return public.fn_tarefas_erro('os_invalida', 'Folga, férias e outras ausências não têm OS.');
    end if;
    -- Nao existe "responsável pelas férias de alguém": ausencia e da coordenacao.
    if not v_ctx.gestao then
      return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação registra folga, férias e outras ausências.');
    end if;
    v_os_id := null;
  end if;

  v_informados := coalesce(array_length(array(select x from unnest(coalesce(p_colaboradores, '{}'::uuid[])) as x where x is not null), 1), 0);
  v_colaboradores := array(select distinct x from unnest(coalesce(p_colaboradores, '{}'::uuid[])) as x where x is not null);
  if coalesce(array_length(v_colaboradores, 1), 0) = 0 then
    return public.fn_tarefas_erro('colaborador_invalido', 'Escolha pelo menos um colaborador.');
  end if;
  if array_length(v_colaboradores, 1) <> v_informados then
    return public.fn_tarefas_erro('colaborador_invalido', 'A mesma pessoa aparece duas vezes na tarefa.');
  end if;

  select count(*) into v_ativos
  from public.colaboradores as colab
  where colab.id = any(v_colaboradores)
    and colab.tenant_id = v_ctx.tenant_id
    and colab.empresa_id = v_ctx.empresa_id
    and colab.ativo is true;
  if v_ativos <> array_length(v_colaboradores, 1) then
    return public.fn_tarefas_erro('colaborador_invalido', 'Escolha colaboradores ativos desta empresa.');
  end if;

  begin
    insert into public.tarefas (
      tenant_id, empresa_id, os_id, tipo, data, descricao, situacao,
      categoria, dias, medida, horas, criado_por_user_id, atualizado_por_user_id
    )
    values (
      v_ctx.tenant_id, v_ctx.empresa_id, v_os_id, v_tipo, v_data, v_descricao, 'pendente',
      v_categoria, v_dias, v_medida, v_horas, v_ctx.auth_uid, v_ctx.auth_uid
    )
    returning * into v_tarefa;

    for v_colab in
      select colab.id, colab.nome, colab.user_id
      from public.colaboradores as colab
      where colab.id = any(v_colaboradores)
      order by colab.nome
    loop
      insert into public.tarefas_participantes (tarefa_id, colaborador_id, usuario_id, criado_por_user_id)
      values (v_tarefa.id, v_colab.id, v_colab.user_id, v_ctx.auth_uid);

      perform public.fn_tarefas_reservar_intervalo(
        v_tarefa, v_colab.id, v_colab.user_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id
      );
    end loop;
  exception
    when sqlstate 'P0T01' then
      get stacked diagnostics v_detalhe = pg_exception_detail;
      return v_detalhe::jsonb;
    when unique_violation then
      return coalesce(
        public.fn_tarefas_conflito(v_ctx.tenant_id, v_ctx.empresa_id, v_colab.id, v_colab.user_id, v_data, null, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
        public.fn_tarefas_erro('colaborador_reservado', 'O colaborador já está reservado naquela data.')
      );
  end;

  v_resultado := jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'avisos', '[]'::jsonb
  );

  if p_chave is not null then
    insert into public.tarefas_operacoes (chave, tenant_id, operacao, tarefa_id, resultado)
    values (p_chave, v_ctx.tenant_id, 'criar', v_tarefa.id, v_resultado)
    on conflict (chave) do nothing;
  end if;

  return v_resultado;
end;
$function$;

create or replace function public.app_tarefas_alterar(p_tarefa_id uuid, p_descricao text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_descricao text := btrim(coalesce(p_descricao, ''));
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;
  if not public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao) then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS altera a descrição da tarefa.');
  end if;
  if v_tarefa.situacao <> 'pendente' then
    return public.fn_tarefas_erro('tarefa_encerrada', 'Tarefa concluída ou cancelada não pode ser alterada.');
  end if;
  if char_length(v_descricao) = 0 then
    return public.fn_tarefas_erro('descricao_obrigatoria', 'Descreva a tarefa.');
  end if;
  if char_length(v_descricao) > 2000 then
    return public.fn_tarefas_erro('descricao_longa', 'A descrição pode ter no máximo 2000 caracteres.');
  end if;

  update public.tarefas
     set descricao = v_descricao,
         atualizado_em = now(),
         atualizado_por_user_id = v_ctx.auth_uid
   where id = v_tarefa.id;

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'avisos', '[]'::jsonb
  );
end;
$function$;

-- Reagendar: libera as reservas de TODO MUNDO e reserva o intervalo novo para
-- todos. Em conflito de qualquer pessoa em qualquer dia, nada muda.
drop function if exists public.app_tarefas_reagendar(uuid, date);
create or replace function public.app_tarefas_reagendar(p_tarefa_id uuid, p_data date default null, p_dias integer default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_part record;
  v_dias smallint;
  v_detalhe text;
  v_anterior jsonb;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;
  if not public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao) then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS reagenda tarefas.');
  end if;
  if v_tarefa.situacao <> 'pendente' then
    return public.fn_tarefas_erro('tarefa_encerrada', 'Tarefa concluída ou cancelada não pode ser reagendada.');
  end if;
  if p_data is null and v_tarefa.categoria <> 'os' then
    return public.fn_tarefas_erro('data_obrigatoria', 'Folga, férias e outras ausências precisam de data.');
  end if;

  if v_tarefa.medida = 'horas' then
    v_dias := 1;
  else
    v_dias := coalesce(p_dias, v_tarefa.dias, 1)::smallint;
    if v_dias < 1 or v_dias > 60 then
      return public.fn_tarefas_erro('duracao_invalida', 'A duração vai de 1 a 60 dias.');
    end if;
  end if;

  v_anterior := jsonb_build_object('tipo', v_tarefa.tipo, 'data', v_tarefa.data, 'dias', v_tarefa.dias);

  if (p_data is null and v_tarefa.tipo = 'sem_data')
     or (p_data is not null and v_tarefa.data = p_data and v_tarefa.dias = v_dias) then
    return jsonb_build_object(
      'sucesso', true,
      'repetido', true,
      'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
      'anterior', v_anterior,
      'avisos', '[]'::jsonb
    );
  end if;

  begin
    if p_data is null then
      update public.tarefas
         set tipo = 'sem_data', data = null, dias = 1, medida = 'dias', horas = null,
             atualizado_em = now(), atualizado_por_user_id = v_ctx.auth_uid
       where id = v_tarefa.id
      returning * into v_tarefa;
      perform public.fn_tarefas_liberar_de(v_tarefa.id, null, v_ctx.auth_uid, 'passou_para_sem_data');
    else
      update public.tarefas
         set tipo = 'agendada', data = p_data, dias = v_dias,
             atualizado_em = now(), atualizado_por_user_id = v_ctx.auth_uid
       where id = v_tarefa.id
      returning * into v_tarefa;
      perform public.fn_tarefas_liberar_de(v_tarefa.id, null, v_ctx.auth_uid, 'reagendada');

      for v_part in
        select p.colaborador_id, coalesce(p.usuario_id, colab.user_id) as usuario_id
        from public.tarefas_participantes as p
        join public.colaboradores as colab on colab.id = p.colaborador_id
        where p.tarefa_id = v_tarefa.id
        order by colab.nome
      loop
        perform public.fn_tarefas_reservar_intervalo(
          v_tarefa, v_part.colaborador_id, v_part.usuario_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id
        );
      end loop;
    end if;
  exception
    when sqlstate 'P0T01' then
      get stacked diagnostics v_detalhe = pg_exception_detail;
      return v_detalhe::jsonb;
    when unique_violation then
      return public.fn_tarefas_erro('colaborador_reservado', 'Alguém da tarefa já está reservado num dos dias.');
  end;

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'anterior', v_anterior,
    'avisos', '[]'::jsonb
  );
end;
$function$;

-- Entrar na tarefa: reserva o intervalo inteiro para quem chegou.
create or replace function public.app_tarefas_adicionar_participante(p_tarefa_id uuid, p_colaborador_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_colab record;
  v_detalhe text;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;
  if not public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao) then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS muda quem participa da tarefa.');
  end if;
  if v_tarefa.situacao = 'cancelada' then
    return public.fn_tarefas_erro('tarefa_encerrada', 'Tarefa cancelada não recebe participante.');
  end if;

  select colab.id, colab.nome, colab.user_id
    into v_colab
  from public.colaboradores as colab
  where colab.id = p_colaborador_id
    and colab.tenant_id = v_ctx.tenant_id
    and colab.empresa_id = v_ctx.empresa_id
    and colab.ativo is true;
  if not found then
    return public.fn_tarefas_erro('colaborador_invalido', 'Escolha um colaborador ativo desta empresa.');
  end if;

  if exists (select 1 from public.tarefas_participantes as p
             where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_colab.id) then
    return jsonb_build_object(
      'sucesso', true,
      'repetido', true,
      'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
      'avisos', '[]'::jsonb
    );
  end if;

  begin
    insert into public.tarefas_participantes (tarefa_id, colaborador_id, usuario_id, criado_por_user_id)
    values (v_tarefa.id, v_colab.id, v_colab.user_id, v_ctx.auth_uid);

    perform public.fn_tarefas_reservar_intervalo(
      v_tarefa, v_colab.id, v_colab.user_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id
    );
  exception
    when sqlstate 'P0T01' then
      get stacked diagnostics v_detalhe = pg_exception_detail;
      return v_detalhe::jsonb;
    when unique_violation then
      return coalesce(
        public.fn_tarefas_conflito(v_ctx.tenant_id, v_ctx.empresa_id, v_colab.id, v_colab.user_id, v_tarefa.data, v_tarefa.id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
        public.fn_tarefas_erro('colaborador_reservado', 'O colaborador já está reservado naquela data.')
      );
  end;

  -- Quem chegou depois reabre a tarefa que ja estava fechada.
  perform public.fn_tarefas_sincronizar_conclusao(v_tarefa.id, v_ctx.auth_uid);

  update public.tarefas
     set atualizado_em = now(), atualizado_por_user_id = v_ctx.auth_uid
   where id = v_tarefa.id;

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'avisos', '[]'::jsonb
  );
end;
$function$;

-- Sair da tarefa: libera os dias da pessoa. A tarefa nunca fica sem ninguem.
create or replace function public.app_tarefas_remover_participante(p_tarefa_id uuid, p_colaborador_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_total integer;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;
  if not public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao) then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS muda quem participa da tarefa.');
  end if;
  if v_tarefa.situacao = 'cancelada' then
    return public.fn_tarefas_erro('tarefa_encerrada', 'Tarefa cancelada não muda de participante.');
  end if;

  if not exists (select 1 from public.tarefas_participantes as p
                 where p.tarefa_id = v_tarefa.id and p.colaborador_id = p_colaborador_id) then
    return public.fn_tarefas_erro('participante_invalido', 'Essa pessoa não participa desta tarefa.');
  end if;

  select count(*) into v_total from public.tarefas_participantes as p where p.tarefa_id = v_tarefa.id;
  if v_total <= 1 then
    return public.fn_tarefas_erro('ultimo_participante', 'A tarefa precisa de pelo menos uma pessoa. Cancele a tarefa ou troque o participante.');
  end if;

  perform public.fn_tarefas_liberar_de(v_tarefa.id, p_colaborador_id, v_ctx.auth_uid, 'saiu_da_tarefa');

  delete from public.tarefas_participantes as p
   where p.tarefa_id = v_tarefa.id and p.colaborador_id = p_colaborador_id;

  -- Saindo o unico que faltava fechar, a tarefa fecha.
  perform public.fn_tarefas_sincronizar_conclusao(v_tarefa.id, v_ctx.auth_uid);

  update public.tarefas
     set atualizado_em = now(), atualizado_por_user_id = v_ctx.auth_uid
   where id = v_tarefa.id;

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'avisos', '[]'::jsonb
  );
end;
$function$;

-- Atalho das telas antigas, que so sabem de uma pessoa por tarefa: sai uma,
-- entra outra, na mesma transacao.
create or replace function public.app_tarefas_trocar_colaborador(p_tarefa_id uuid, p_colaborador_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_colab record;
  v_antigo uuid;
  v_total integer;
  v_detalhe text;
  v_anterior jsonb;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;
  if not public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao) then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS troca o colaborador da tarefa.');
  end if;
  if v_tarefa.situacao <> 'pendente' then
    return public.fn_tarefas_erro('tarefa_encerrada', 'Tarefa concluída ou cancelada não pode mudar de colaborador.');
  end if;

  select colab.id, colab.nome, colab.user_id
    into v_colab
  from public.colaboradores as colab
  where colab.id = p_colaborador_id
    and colab.tenant_id = v_ctx.tenant_id
    and colab.empresa_id = v_ctx.empresa_id
    and colab.ativo is true;
  if not found then
    return public.fn_tarefas_erro('colaborador_invalido', 'Escolha um colaborador ativo desta empresa.');
  end if;

  select count(*) into v_total from public.tarefas_participantes as p where p.tarefa_id = v_tarefa.id;
  select p.colaborador_id into v_antigo
  from public.tarefas_participantes as p where p.tarefa_id = v_tarefa.id limit 1;
  v_anterior := jsonb_build_object('colaborador_id', v_antigo);

  if exists (select 1 from public.tarefas_participantes as p
             where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_colab.id) then
    return jsonb_build_object(
      'sucesso', true,
      'repetido', true,
      'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
      'anterior', v_anterior,
      'avisos', '[]'::jsonb
    );
  end if;

  if v_total <> 1 then
    return public.fn_tarefas_erro('varios_participantes', 'Esta tarefa tem várias pessoas: use adicionar e remover participante.');
  end if;

  begin
    insert into public.tarefas_participantes (tarefa_id, colaborador_id, usuario_id, criado_por_user_id)
    values (v_tarefa.id, v_colab.id, v_colab.user_id, v_ctx.auth_uid);

    perform public.fn_tarefas_reservar_intervalo(
      v_tarefa, v_colab.id, v_colab.user_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id
    );

    perform public.fn_tarefas_liberar_de(v_tarefa.id, v_antigo, v_ctx.auth_uid, 'troca_de_colaborador');
    delete from public.tarefas_participantes as p
     where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_antigo;
  exception
    when sqlstate 'P0T01' then
      get stacked diagnostics v_detalhe = pg_exception_detail;
      return v_detalhe::jsonb;
    when unique_violation then
      return coalesce(
        public.fn_tarefas_conflito(v_ctx.tenant_id, v_ctx.empresa_id, v_colab.id, v_colab.user_id, v_tarefa.data, v_tarefa.id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
        public.fn_tarefas_erro('colaborador_reservado', 'O colaborador já está reservado naquela data.')
      );
  end;

  perform public.fn_tarefas_sincronizar_conclusao(v_tarefa.id, v_ctx.auth_uid);

  update public.tarefas
     set atualizado_em = now(), atualizado_por_user_id = v_ctx.auth_uid
   where id = v_tarefa.id;

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'anterior', v_anterior,
    'avisos', '[]'::jsonb
  );
end;
$function$;

create or replace function public.app_tarefas_cancelar(p_tarefa_id uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;
  if not public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao) then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS cancela tarefas.');
  end if;
  if v_tarefa.situacao = 'cancelada' then
    return jsonb_build_object(
      'sucesso', true,
      'repetido', true,
      'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
      'avisos', '[]'::jsonb
    );
  end if;
  if v_tarefa.situacao = 'concluida' then
    return public.fn_tarefas_erro('tarefa_concluida', 'Tarefa concluída não pode ser cancelada. Se o dia precisa ser liberado, use "Liberar reserva".');
  end if;

  update public.tarefas
     set situacao = 'cancelada',
         cancelada_em = now(),
         cancelada_por_user_id = v_ctx.auth_uid,
         cancelamento_motivo = nullif(btrim(coalesce(p_motivo, '')), ''),
         atualizado_em = now(),
         atualizado_por_user_id = v_ctx.auth_uid
   where id = v_tarefa.id;

  -- Cancelou, ninguem mais deve o dia: sai a reserva de todo mundo.
  perform public.fn_tarefas_liberar_de(v_tarefa.id, null, v_ctx.auth_uid, 'cancelada');

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'avisos', '[]'::jsonb
  );
end;
$function$;

-- Concluir e POR PESSOA: cada um fecha a sua parte e a tarefa fecha com o
-- ultimo. A reserva continua ativa: o dia foi usado.
drop function if exists public.app_tarefas_concluir(uuid, uuid);
create or replace function public.app_tarefas_concluir(p_tarefa_id uuid, p_chave uuid default null, p_colaborador_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_part public.tarefas_participantes;
  v_resultado jsonb;
  v_pode_gerir boolean;
  v_sou_participante boolean;
  v_alvo uuid;
begin
  select * into v_ctx from public.fn_tarefas_contexto();

  if p_chave is not null then
    perform pg_advisory_xact_lock(hashtextextended('tarefa-op:' || p_chave::text, 0));
    select op.resultado into v_resultado
    from public.tarefas_operacoes as op
    where op.chave = p_chave and op.tenant_id = v_ctx.tenant_id;
    if found then
      return v_resultado || jsonb_build_object('repetido', true);
    end if;
  end if;

  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;

  v_pode_gerir := public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao);
  v_sou_participante := v_ctx.colaborador_id is not null and exists (
    select 1 from public.tarefas_participantes as p
    where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_ctx.colaborador_id
  );
  if not (v_pode_gerir or v_sou_participante) then
    -- Quem nao pode nem ver a tarefa nao fica sabendo que ela existe.
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;

  v_alvo := coalesce(p_colaborador_id, v_ctx.colaborador_id);
  if v_alvo is null then
    return public.fn_tarefas_erro('participante_invalido', 'Você não participa desta tarefa. Informe de quem é a parte a concluir.');
  end if;
  if v_alvo is distinct from v_ctx.colaborador_id and not v_pode_gerir then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS conclui a parte de outra pessoa.');
  end if;

  select p.* into v_part
  from public.tarefas_participantes as p
  where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_alvo
  for update;
  if not found then
    return public.fn_tarefas_erro('participante_invalido', 'Essa pessoa não participa desta tarefa.');
  end if;

  if v_tarefa.situacao = 'cancelada' then
    return public.fn_tarefas_erro('tarefa_cancelada', 'Esta tarefa foi cancelada e não pode ser concluída.');
  end if;

  if v_part.concluida_em is not null then
    return jsonb_build_object(
      'sucesso', true,
      'repetido', true,
      'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
      'avisos', '[]'::jsonb
    );
  end if;

  update public.tarefas_participantes
     set concluida_em = now(),
         concluida_por_user_id = v_ctx.auth_uid,
         concluida_por_sessao_id = null
   where tarefa_id = v_tarefa.id and colaborador_id = v_alvo;

  perform public.fn_tarefas_sincronizar_conclusao(v_tarefa.id, v_ctx.auth_uid);

  v_resultado := jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'colaborador_id', v_alvo,
    'avisos', '[]'::jsonb
  );

  if p_chave is not null then
    insert into public.tarefas_operacoes (chave, tenant_id, operacao, tarefa_id, resultado)
    values (p_chave, v_ctx.tenant_id, 'concluir', v_tarefa.id, v_resultado)
    on conflict (chave) do nothing;
  end if;

  return v_resultado;
end;
$function$;

-- Libera o dia de uma tarefa encerrada. Acao explicita da gestao, com motivo.
create or replace function public.app_tarefas_liberar_reserva(p_tarefa_id uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_liberadas integer;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;
  if not public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao) then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS libera a reserva de uma tarefa.');
  end if;
  if v_tarefa.situacao = 'pendente' then
    return public.fn_tarefas_erro('tarefa_pendente', 'Para liberar o dia de uma tarefa pendente, reagende-a ou passe-a para sem data.');
  end if;

  v_liberadas := public.fn_tarefas_liberar_de(v_tarefa.id, null, v_ctx.auth_uid, coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'liberada_pela_gestao'));

  update public.tarefas
     set atualizado_em = now(), atualizado_por_user_id = v_ctx.auth_uid
   where id = v_tarefa.id;

  return jsonb_build_object(
    'sucesso', true,
    'repetido', v_liberadas = 0,
    'liberadas', v_liberadas,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'avisos', '[]'::jsonb
  );
end;
$function$;

-- 13. Tablet compartilhado -----------------------------------------------------------------

create or replace function public.app_tablet_tarefas(p_sessao_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_sessao public.tablet_sessoes;
  v_hoje date := public.fn_tablet_data_hoje();
  v_colaborador_nome text;
  v_agendadas jsonb;
  v_sem_data jsonb;
  v_concluidas_hoje jsonb;
begin
  v_sessao := public.fn_tablet_validar_sessao(p_sessao_token);
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;

  select colab.nome into v_colaborador_nome from public.colaboradores as colab where colab.id = v_sessao.colaborador_id;

  with tarefas_do_colaborador as (
    select t.id,
           t.tipo,
           t.data,
           -- A situacao que interessa ao tablet e a DELE, nao a da tarefa toda.
           case when part.concluida_em is not null then 'concluida' else t.situacao end as situacao,
           t.descricao,
           part.concluida_em,
           t.criado_em,
           t.categoria,
           t.medida,
           t.dias,
           t.horas,
           case when t.data is null then null
                else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end as data_fim,
           (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id) as participantes,
           case when t.categoria = 'os'
                then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end as numero_os,
           case when t.categoria = 'os'
                then coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente não informado') end as cliente_nome,
           case when t.categoria = 'os' then os.descricao_servico end as os_descricao,
           (t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
             and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje) as atrasada,
           (t.data is not null and v_hoje between t.data and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date) as hoje
    from public.tarefas as t
    join public.tarefas_participantes as part
      on part.tarefa_id = t.id and part.colaborador_id = v_sessao.colaborador_id
    left join public.ordens_servico as os on os.id = t.os_id
    where t.tenant_id = v_sessao.tenant_id
      and t.empresa_id = v_sessao.empresa_id
      and ((t.situacao = 'pendente' and part.concluida_em is null)
           or (part.concluida_em is not null and (part.concluida_em at time zone 'America/Sao_Paulo')::date = v_hoje))
  )
  select
    coalesce((select jsonb_agg(to_jsonb(x) order by x.data, x.criado_em) from tarefas_do_colaborador as x where x.situacao = 'pendente' and x.tipo = 'agendada'), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x) order by x.criado_em) from tarefas_do_colaborador as x where x.situacao = 'pendente' and x.tipo = 'sem_data'), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x) order by x.concluida_em desc) from tarefas_do_colaborador as x where x.situacao = 'concluida'), '[]'::jsonb)
    into v_agendadas, v_sem_data, v_concluidas_hoje;

  return jsonb_build_object(
    'sucesso', true,
    'colaborador_id', v_sessao.colaborador_id,
    'colaborador_nome', v_colaborador_nome,
    'hoje', v_hoje,
    'agendadas', v_agendadas,
    'sem_data', v_sem_data,
    'concluidas_hoje', v_concluidas_hoje
  );
end;
$function$;

create or replace function public.app_tablet_tarefa_concluir(p_sessao_token text, p_tarefa_id uuid, p_chave uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_sessao public.tablet_sessoes;
  v_tarefa public.tarefas;
  v_part public.tarefas_participantes;
  v_resultado jsonb;
  v_linha jsonb;
  v_ja_concluida boolean;
begin
  v_sessao := public.fn_tablet_validar_sessao(p_sessao_token);
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;

  if p_chave is not null then
    perform pg_advisory_xact_lock(hashtextextended('tarefa-op:' || p_chave::text, 0));
    select op.resultado into v_resultado
    from public.tarefas_operacoes as op
    where op.chave = p_chave and op.tenant_id = v_sessao.tenant_id;
    if found then
      return v_resultado || jsonb_build_object('repetido', true);
    end if;
  end if;

  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_sessao.tenant_id, v_sessao.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tablet_erro('tarefa_nao_encontrada', 'Esta tarefa não é sua ou não existe mais.');
  end if;

  select p.* into v_part
  from public.tarefas_participantes as p
  where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_sessao.colaborador_id
  for update;
  if not found then
    return public.fn_tablet_erro('tarefa_nao_encontrada', 'Esta tarefa não é sua ou não existe mais.');
  end if;

  if v_tarefa.situacao = 'cancelada' then
    return public.fn_tablet_erro('tarefa_cancelada', 'Esta tarefa foi cancelada e não pode ser concluída.');
  end if;

  -- A parte dele ja estava fechada: devolve sucesso sem gravar de novo.
  v_ja_concluida := v_part.concluida_em is not null;

  if not v_ja_concluida then
    update public.tarefas_participantes
       set concluida_em = now(),
           concluida_por_user_id = auth.uid(),
           concluida_por_sessao_id = v_sessao.id
     where tarefa_id = v_tarefa.id and colaborador_id = v_sessao.colaborador_id
    returning * into v_part;

    perform public.fn_tarefas_sincronizar_conclusao(v_tarefa.id, auth.uid());

    -- Se foi ele quem fechou a ultima parte, o rastro do tablet fica na tarefa.
    update public.tarefas
       set concluida_por_sessao_id = v_sessao.id
     where id = v_tarefa.id
       and situacao = 'concluida'
       and concluida_por_sessao_id is null;
  end if;

  select jsonb_build_object(
    'id', t.id, 'tipo', t.tipo, 'data', t.data,
    'situacao', case when v_part.concluida_em is not null then 'concluida' else t.situacao end,
    'descricao', t.descricao,
    'concluida_em', v_part.concluida_em,
    'categoria', t.categoria,
    'medida', t.medida,
    'dias', t.dias,
    'horas', t.horas,
    'numero_os', case when t.categoria = 'os'
                      then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    'cliente_nome', case when t.categoria = 'os'
                         then coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente não informado') end
  )
    into v_linha
  from public.tarefas as t
  left join public.ordens_servico as os on os.id = t.os_id
  where t.id = v_tarefa.id;

  v_resultado := jsonb_build_object('sucesso', true, 'repetido', v_ja_concluida, 'tarefa', v_linha, 'avisos', '[]'::jsonb);

  if p_chave is not null and not v_ja_concluida then
    insert into public.tarefas_operacoes (chave, tenant_id, operacao, tarefa_id, resultado)
    values (p_chave, v_sessao.tenant_id, 'tablet_concluir', v_tarefa.id, v_resultado)
    on conflict (chave) do nothing;
  end if;

  return v_resultado;
end;
$function$;

-- 14. Painel de TV ---------------------------------------------------------------------------

-- Uma linha por participante ativo da area: as pendentes dele e as que ele
-- fechou hoje. minha, pode_gerir e pode_concluir seguem falsos: a TV so mostra.
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
    part.colaborador_id,
    colab.nome::text,
    false,
    t.os_id,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    case when t.categoria = 'os' then os.cliente_id end,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado')::text end,
    case when t.categoria = 'os' then os.descricao_servico end,
    case when t.categoria = 'os'
         then coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) end,
    case when t.categoria = 'os' then coalesce(os.usa_relatorio_hh, false) end,
    case when t.categoria = 'os' then public.fn_tarefas_nome_usuario(os.responsavel_aprovacao_id) end,
    t.descricao,
    t.criado_em,
    public.fn_tarefas_nome_usuario(t.criado_por_user_id),
    t.atualizado_em,
    t.concluida_em,
    case when part.concluida_em is null then null
         when part.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
         else public.fn_tarefas_nome_usuario(part.concluida_por_user_id) end,
    part.concluida_por_sessao_id is not null,
    t.cancelada_em,
    public.fn_tarefas_nome_usuario(t.cancelada_por_user_id),
    t.cancelamento_motivo,
    exists (select 1 from public.tarefas_reservas as r
            where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is null),
    null::timestamptz,
    null::text,
    null::text,
    (t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
      and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje),
    (t.data is not null and v_hoje between t.data and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date),
    false,
    false,
    t.categoria,
    t.medida,
    t.dias,
    t.horas,
    case when t.data is null then null
         else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end,
    (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id),
    part.concluida_em
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab
    on colab.id = part.colaborador_id
   and colab.ativo is true
  left join public.ordens_servico as os on os.id = t.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = t.tenant_id and cli.empresa_id = t.empresa_id
  where t.tenant_id = v_ctx.tenant_id
    and t.empresa_id = v_ctx.empresa_id
    and (v_area is null or colab.area = v_area)
    and ((t.situacao = 'pendente' and part.concluida_em is null)
         or (part.concluida_em is not null and (part.concluida_em at time zone 'America/Sao_Paulo')::date = v_hoje))
  order by
    (t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
      and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje) desc,
    t.data asc nulls last,
    colab.nome asc,
    t.criado_em asc;
end;
$function$;

-- Ausencia por pessoa e por dia: e o que a TV DESCONTA da semana. Dia de
-- ausencia em 'dias' sai inteiro da cobranca; em 'horas', so aquelas horas saem
-- do previsto daquele dia. Sem valor, sem custo.
create or replace function public.tv_ausencias_periodo(
  p_inicio date,
  p_fim date,
  p_area text default null
)
returns table (
  colaborador_id uuid,
  colaborador_nome text,
  data date,
  categoria text,
  medida text,
  horas numeric,
  descricao text
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
    part.colaborador_id,
    colab.nome::text,
    d.dia,
    t.categoria,
    t.medida,
    t.horas,
    t.descricao
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab
    on colab.id = part.colaborador_id
   and colab.ativo is true
  cross join lateral public.fn_tarefas_dias(t.data, t.dias, t.medida) as d(dia)
  where t.tenant_id = v_ctx.tenant_id
    and t.empresa_id = v_ctx.empresa_id
    and t.categoria <> 'os'
    and t.situacao <> 'cancelada'
    and (v_area is null or colab.area = v_area)
    and d.dia between p_inicio and p_fim
  order by colab.nome, 3;
end;
$function$;

-- 15. Grants -----------------------------------------------------------------------------------

revoke all on function public.fn_tarefas_conflito(uuid, uuid, uuid, uuid, date, uuid, uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.fn_tarefas_linhas(uuid, uuid, uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.fn_tarefas_linha_json(uuid, uuid, uuid, uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.fn_tarefas_dias(date, smallint, text) from public, anon, authenticated;
revoke all on function public.fn_tarefas_pode_gerir(public.tarefas, uuid, boolean) from public, anon, authenticated;
revoke all on function public.fn_tarefas_reservar_intervalo(public.tarefas, uuid, uuid, uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.fn_tarefas_liberar_de(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.fn_tarefas_sincronizar_conclusao(uuid, uuid) from public, anon, authenticated;

revoke all on function public.app_tarefas_criar(uuid[], text, date, integer, text, text, integer, text, numeric, uuid) from public, anon;
revoke all on function public.app_tarefas_alterar(uuid, text) from public, anon;
revoke all on function public.app_tarefas_reagendar(uuid, date, integer) from public, anon;
revoke all on function public.app_tarefas_adicionar_participante(uuid, uuid) from public, anon;
revoke all on function public.app_tarefas_remover_participante(uuid, uuid) from public, anon;
revoke all on function public.app_tarefas_trocar_colaborador(uuid, uuid) from public, anon;
revoke all on function public.app_tarefas_cancelar(uuid, text) from public, anon;
revoke all on function public.app_tarefas_concluir(uuid, uuid, uuid) from public, anon;
revoke all on function public.app_tarefas_liberar_reserva(uuid, text) from public, anon;
revoke all on function public.app_tarefas_listar(text, date, date, uuid, integer, text) from public, anon;
revoke all on function public.app_tarefas_detalhe(uuid) from public, anon;
revoke all on function public.app_tarefas_contar() from public, anon;
revoke all on function public.app_tarefas_agenda(date, date) from public, anon;
revoke all on function public.app_tarefas_colaboradores(date) from public, anon;
revoke all on function public.app_tablet_tarefas(text) from public, anon;
revoke all on function public.app_tablet_tarefa_concluir(text, uuid, uuid) from public, anon;
revoke all on function public.tv_colaboradores_tarefas(text) from public, anon;
revoke all on function public.tv_ausencias_periodo(date, date, text) from public, anon;

grant execute on function public.app_tarefas_criar(uuid[], text, date, integer, text, text, integer, text, numeric, uuid) to authenticated;
grant execute on function public.app_tarefas_alterar(uuid, text) to authenticated;
grant execute on function public.app_tarefas_reagendar(uuid, date, integer) to authenticated;
grant execute on function public.app_tarefas_adicionar_participante(uuid, uuid) to authenticated;
grant execute on function public.app_tarefas_remover_participante(uuid, uuid) to authenticated;
grant execute on function public.app_tarefas_trocar_colaborador(uuid, uuid) to authenticated;
grant execute on function public.app_tarefas_cancelar(uuid, text) to authenticated;
grant execute on function public.app_tarefas_concluir(uuid, uuid, uuid) to authenticated;
grant execute on function public.app_tarefas_liberar_reserva(uuid, text) to authenticated;
grant execute on function public.app_tarefas_listar(text, date, date, uuid, integer, text) to authenticated;
grant execute on function public.app_tarefas_detalhe(uuid) to authenticated;
grant execute on function public.app_tarefas_contar() to authenticated;
grant execute on function public.app_tarefas_agenda(date, date) to authenticated;
grant execute on function public.app_tarefas_colaboradores(date) to authenticated;
grant execute on function public.app_tablet_tarefas(text) to authenticated;
grant execute on function public.app_tablet_tarefa_concluir(text, uuid, uuid) to authenticated;
grant execute on function public.tv_colaboradores_tarefas(text) to authenticated;
grant execute on function public.tv_ausencias_periodo(date, date, text) to authenticated;

-- 16. Conferencia --------------------------------------------------------------------------------

do $assertions$
declare
  v_nome text;
  v_acl text;
  v_def text;
begin
  -- As tabelas de tarefas continuam fechadas: RLS ligada, sem policy, sem select.
  foreach v_nome in array array['tarefas', 'tarefas_reservas', 'tarefas_operacoes', 'tarefas_participantes'] loop
    if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname = v_nome and c.relrowsecurity) then
      raise exception 'rls_desligada: %', v_nome;
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = v_nome) then
      raise exception 'policy_inesperada: %', v_nome;
    end if;
    if has_table_privilege('authenticated', format('public.%I', v_nome), 'select') then
      raise exception 'tabela_aberta_para_authenticated: %', v_nome;
    end if;
  end loop;

  -- A exclusividade continua sendo do banco.
  foreach v_nome in array array['uq_tarefas_reservas__colaborador_dia', 'uq_tarefas_reservas__usuario_dia', 'uq_tarefas_reservas__tarefa_pessoa_dia'] loop
    if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = v_nome and indexdef ilike 'create unique index%') then
      raise exception 'indice_unico_ausente: %', v_nome;
    end if;
  end loop;

  -- Nenhum helper exposto e nada aberto para anon.
  for v_nome in
    select p.proname::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'fn\_tarefas\_%' or p.proname like 'fn\_tv\_%')
      and has_function_privilege('authenticated', p.oid, 'execute')
  loop
    raise exception 'helper_exposto: %', v_nome;
  end loop;

  for v_acl in
    select coalesce(p.proacl::text, '')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'app\_tarefas\_%' or p.proname like 'fn\_tarefas\_%'
           or p.proname like 'app\_tablet\_tarefa%' or p.proname like 'tv\_%')
  loop
    if v_acl like '%anon=%' or v_acl like '{=X%' then
      raise exception 'grant_tarefas_aberto: %', v_acl;
    end if;
  end loop;

  -- A TV nunca encosta em dinheiro.
  foreach v_def in array array[
    pg_get_functiondef('public.tv_colaboradores_tarefas(text)'::regprocedure),
    pg_get_functiondef('public.tv_ausencias_periodo(date,date,text)'::regprocedure)
  ] loop
    if v_def ilike '%vw_apontamentos_horas_custo%'
       or v_def ilike '%valor_hora%'
       or v_def ilike '%custo_lancamento%'
       or v_def ilike '%fator_aplicado%' then
      raise exception 'funcao_de_tv_com_valor';
    end if;
  end loop;

  -- Ninguem mais le a coluna que saiu.
  for v_nome in
    select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and (p.proname like 'app\_tarefas\_%' or p.proname like 'fn\_tarefas\_%'
           or p.proname like 'app\_tablet\_tarefa%' or p.proname like 'tv\_colaboradores\_tarefas')
      and pg_get_functiondef(p.oid) ~ '\mt\.colaborador_id\M'
  loop
    raise exception 'funcao_ainda_le_tarefas_colaborador_id: %', v_nome;
  end loop;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;

-- =====================================================================================
-- Parte 4: compatibilidade com o aplicativo que ja esta publicado.
--
-- O build 22 (TestFlight, 12/09/2026) chama app_tarefas_criar com a assinatura
-- antiga, de um colaborador so. Se esta migration chegar em producao antes de o
-- aparelho atualizar, a tela de nova tarefa quebraria. O atalho abaixo mantem a
-- assinatura antiga viva: ela cria uma tarefa de trabalho, de uma pessoa e de um
-- dia, chamando a funcao nova.
--
-- As demais chamadas do aplicativo continuam valendo sem atalho, porque o
-- PostgREST resolve por NOME do argumento e os nomes antigos continuam existindo
-- com valor padrao: app_tarefas_reagendar(p_tarefa_id, p_data),
-- app_tarefas_concluir(p_tarefa_id, p_chave) e
-- app_tarefas_trocar_colaborador(p_tarefa_id, p_colaborador_id).
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.app_tarefas_criar(
  p_tipo text,
  p_colaborador_id uuid,
  p_os_id integer,
  p_descricao text,
  p_data date default null,
  p_chave uuid default null
)
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog', 'public'
as $function$
  select public.app_tarefas_criar(
    array[p_colaborador_id]::uuid[],
    p_tipo,
    p_data,
    1,
    p_descricao,
    'os',
    p_os_id,
    'dias',
    null::numeric,
    p_chave
  );
$function$;

comment on function public.app_tarefas_criar(text, uuid, integer, text, date, uuid) is
  'Atalho da assinatura antiga (um colaborador, um dia, sempre trabalho em OS), para o aplicativo publicado antes de 12/09/2026 continuar funcionando. Telas novas usam a assinatura com p_colaboradores.';

revoke all on function public.app_tarefas_criar(text, uuid, integer, text, date, uuid) from public, anon;
grant execute on function public.app_tarefas_criar(text, uuid, integer, text, date, uuid) to authenticated;

do $assertions$
begin
  -- As duas assinaturas precisam coexistir, senao o atalho nao serve para nada.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'app_tarefas_criar') <> 2 then
    raise exception 'app_tarefas_criar deveria ter duas assinaturas (a nova e o atalho antigo)';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;

-- =====================================================================================
-- Parte 5: concluir pela gestao numa tarefa de uma pessoa so.
--
-- Sem isto, a coordenacao que nao participa da tarefa recebia
-- 'participante_invalido' ao concluir — inclusive pelo aplicativo ja publicado,
-- onde concluir sempre foi uma acao da gestao. Com uma pessoa so na tarefa nao
-- ha ambiguidade; com duas ou mais, continua sendo preciso dizer de quem e a
-- parte.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

CREATE OR REPLACE FUNCTION public.app_tarefas_concluir(p_tarefa_id uuid, p_chave uuid DEFAULT NULL::uuid, p_colaborador_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_part public.tarefas_participantes;
  v_resultado jsonb;
  v_pode_gerir boolean;
  v_sou_participante boolean;
  v_alvo uuid;
begin
  select * into v_ctx from public.fn_tarefas_contexto();

  if p_chave is not null then
    perform pg_advisory_xact_lock(hashtextextended('tarefa-op:' || p_chave::text, 0));
    select op.resultado into v_resultado
    from public.tarefas_operacoes as op
    where op.chave = p_chave and op.tenant_id = v_ctx.tenant_id;
    if found then
      return v_resultado || jsonb_build_object('repetido', true);
    end if;
  end if;

  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;

  v_pode_gerir := public.fn_tarefas_pode_gerir(v_tarefa, v_ctx.auth_uid, v_ctx.gestao);
  v_sou_participante := v_ctx.colaborador_id is not null and exists (
    select 1 from public.tarefas_participantes as p
    where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_ctx.colaborador_id
  );
  if not (v_pode_gerir or v_sou_participante) then
    -- Quem nao pode nem ver a tarefa nao fica sabendo que ela existe.
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;

  v_alvo := coalesce(p_colaborador_id, case when v_sou_participante then v_ctx.colaborador_id end);

  -- Quem administra e nao participa: se a tarefa tem uma pessoa so, nao ha o que
  -- perguntar — conclui a dela. E o caso de toda tarefa criada antes dos
  -- participantes e o que o aplicativo publicado faz ao concluir pela gestao.
  if v_alvo is null and v_pode_gerir then
    select p.colaborador_id into v_alvo
    from public.tarefas_participantes as p
    where p.tarefa_id = v_tarefa.id
    limit 2;
    if (select count(*) from public.tarefas_participantes as p where p.tarefa_id = v_tarefa.id) <> 1 then
      v_alvo := null;
    end if;
  end if;

  if v_alvo is null then
    return public.fn_tarefas_erro('participante_invalido', 'Esta tarefa tem mais de uma pessoa. Informe de quem é a parte a concluir.');
  end if;
  if v_alvo is distinct from v_ctx.colaborador_id and not v_pode_gerir then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação ou o responsável da OS conclui a parte de outra pessoa.');
  end if;

  select p.* into v_part
  from public.tarefas_participantes as p
  where p.tarefa_id = v_tarefa.id and p.colaborador_id = v_alvo
  for update;
  if not found then
    return public.fn_tarefas_erro('participante_invalido', 'Essa pessoa não participa desta tarefa.');
  end if;

  if v_tarefa.situacao = 'cancelada' then
    return public.fn_tarefas_erro('tarefa_cancelada', 'Esta tarefa foi cancelada e não pode ser concluída.');
  end if;

  if v_part.concluida_em is not null then
    return jsonb_build_object(
      'sucesso', true,
      'repetido', true,
      'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
      'avisos', '[]'::jsonb
    );
  end if;

  update public.tarefas_participantes
     set concluida_em = now(),
         concluida_por_user_id = v_ctx.auth_uid,
         concluida_por_sessao_id = null
   where tarefa_id = v_tarefa.id and colaborador_id = v_alvo;

  perform public.fn_tarefas_sincronizar_conclusao(v_tarefa.id, v_ctx.auth_uid);

  v_resultado := jsonb_build_object(
    'sucesso', true,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'colaborador_id', v_alvo,
    'avisos', '[]'::jsonb
  );

  if p_chave is not null then
    insert into public.tarefas_operacoes (chave, tenant_id, operacao, tarefa_id, resultado)
    values (p_chave, v_ctx.tenant_id, 'concluir', v_tarefa.id, v_resultado)
    on conflict (chave) do nothing;
  end if;

  return v_resultado;
end;
$function$;

revoke all on function public.app_tarefas_concluir(uuid, uuid, uuid) from public, anon;
grant execute on function public.app_tarefas_concluir(uuid, uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

-- =====================================================================================
-- Parte 6: tres consertos que a bateria de testes encontrou.
--
-- 1. chk_tarefas_duracao deixava passar folga em HORAS sem horas. O ramo era
--    "medida = 'horas' and dias = 1 and horas > 0 and horas <= 24": com horas
--    nulo isso da NULO, o outro ramo da falso, e um CHECK que resulta em NULO
--    passa. So app_tarefas_criar recusava; qualquer escrita por fora (service
--    role, backfill, funcao futura) criava folga em horas sem horas, e ai
--    tv_ausencias_periodo devolvia horas nulo para um dia que devia descontar da
--    semana.
--
-- 2. Ausencia aparecia na lista de tarefas AGENDADAS e nos contadores de tarefa.
--    Folga e ferias tem secao propria ('ausencias'); contar ferias como tarefa
--    pendente faz a tela cobrar trabalho que nao existe.
--
-- 3. Ausencia ficava "atrasada" depois de passar a data, porque ninguem conclui
--    ferias. Na televisao isso aparecia como "ferias atrasada 5 dias", que e
--    leitura errada: ausencia nao e cobranca.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Duracao em horas exige horas. -----------------------------------------------------

alter table public.tarefas drop constraint if exists chk_tarefas_duracao;
alter table public.tarefas add constraint chk_tarefas_duracao
  check (
    (medida = 'dias' and dias between 1 and 60 and horas is null)
    or (medida = 'horas' and dias = 1 and horas is not null and horas > 0 and horas <= 24)
  );

-- 2 e 3. Ausencia nao e tarefa pendente nem fica atrasada. -----------------------------

-- atrasada passa a valer so para trabalho. O resto da funcao e igual.
create or replace function public.fn_tarefas_linhas(p_tenant_id uuid, p_empresa_id uuid, p_auth_uid uuid, p_gestao boolean, p_colaborador_id uuid)
returns setof public.tarefa_linha
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
  with hoje as (select public.fn_tablet_data_hoje() as d)
  select
    t.id,
    t.tipo,
    t.data,
    t.situacao,
    part.colaborador_id,
    colab.nome::text,
    (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id),
    t.os_id,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    case when t.categoria = 'os' then os.cliente_id end,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado')::text end,
    case when t.categoria = 'os' then os.descricao_servico end,
    case when t.categoria = 'os'
         then coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) end,
    case when t.categoria = 'os' then coalesce(os.usa_relatorio_hh, false) end,
    case when t.categoria = 'os' then public.fn_tarefas_nome_usuario(os.responsavel_aprovacao_id) end,
    t.descricao,
    t.criado_em,
    public.fn_tarefas_nome_usuario(t.criado_por_user_id),
    t.atualizado_em,
    t.concluida_em,
    -- Quem fechou e quando: da PESSOA da linha, nao da tarefa inteira.
    case when part.concluida_em is null then null
         when part.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
         else public.fn_tarefas_nome_usuario(part.concluida_por_user_id) end,
    part.concluida_por_sessao_id is not null,
    t.cancelada_em,
    public.fn_tarefas_nome_usuario(t.cancelada_por_user_id),
    t.cancelamento_motivo,
    reserva.ativa,
    ultima.liberada_em,
    public.fn_tarefas_nome_usuario(ultima.liberada_por_user_id),
    ultima.liberacao_motivo,
    -- Atrasada e cobranca de TRABALHO. Ninguem conclui ferias, entao ausencia
    -- com data no passado nao fica vermelha: ela so terminou.
    (t.categoria = 'os' and t.situacao = 'pendente' and part.concluida_em is null
      and fim.data_fim is not null and fim.data_fim < hoje.d),
    (t.data is not null and hoje.d between t.data and fim.data_fim),
    gerir.pode,
    (t.situacao = 'pendente' and part.concluida_em is null
      and (gerir.pode or (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id))),
    t.categoria,
    t.medida,
    t.dias,
    t.horas,
    fim.data_fim,
    (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id),
    part.concluida_em
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab on colab.id = part.colaborador_id
  left join public.ordens_servico as os on os.id = t.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = t.tenant_id and cli.empresa_id = t.empresa_id
  cross join hoje
  cross join lateral (
    select case when t.data is null then null
                else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end as data_fim
  ) as fim
  cross join lateral (
    select (p_gestao or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = p_auth_uid, false))) as pode
  ) as gerir
  cross join lateral (
    select exists (
      select 1 from public.tarefas_reservas as r
      where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is null
    ) as ativa
  ) as reserva
  left join lateral (
    select r.liberada_em, r.liberada_por_user_id, r.liberacao_motivo
    from public.tarefas_reservas as r
    where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is not null
    order by r.liberada_em desc, r.ordem desc
    limit 1
  ) as ultima on true
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and (p_gestao
         or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = p_auth_uid, false))
         or (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id));
$function$;

-- As secoes de trabalho passam a filtrar por categoria, e 'ausencias' com
-- periodo informado deixa de esconder a ausencia que ja terminou: com data, quem
-- manda e o periodo pedido; sem data, so o que ainda vale.
create or replace function public.app_tarefas_listar(
  p_secao text default 'agendadas',
  p_de date default null,
  p_ate date default null,
  p_colaborador_id uuid default null,
  p_os_id integer default null,
  p_busca text default null
)
returns setof public.tarefa_linha
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_secao text := lower(btrim(coalesce(p_secao, 'agendadas')));
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_hoje date := public.fn_tablet_data_hoje();
begin
  select * into v_ctx from public.fn_tarefas_contexto();

  if v_secao not in ('agendadas', 'sem_data', 'historico', 'todas', 'ausencias') then
    raise exception 'Seção inválida: %', v_secao;
  end if;

  return query
  select linha.*
  from public.fn_tarefas_linhas(v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id) as linha
  where (v_secao <> 'agendadas' or (linha.situacao = 'pendente' and linha.tipo = 'agendada' and linha.categoria = 'os'))
    and (v_secao <> 'sem_data' or (linha.situacao = 'pendente' and linha.tipo = 'sem_data' and linha.categoria = 'os'))
    and (v_secao <> 'historico' or linha.situacao in ('concluida', 'cancelada'))
    and (v_secao <> 'ausencias' or (linha.situacao = 'pendente' and linha.categoria <> 'os'
                                    and (p_de is not null or p_ate is not null
                                         or coalesce(linha.data_fim, v_hoje) >= v_hoje)))
    and (p_colaborador_id is null or linha.colaborador_id = p_colaborador_id)
    and (p_os_id is null or linha.os_id = p_os_id)
    and (p_de is null or case
           when v_secao = 'historico' then (coalesce(linha.concluida_em, linha.cancelada_em) at time zone 'America/Sao_Paulo')::date >= p_de
           when v_secao = 'sem_data' then true
           -- Tarefa de varios dias entra no periodo se qualquer dia dela cair nele.
           else coalesce(linha.data_fim, linha.data) >= p_de end)
    and (p_ate is null or case
           when v_secao = 'historico' then (coalesce(linha.concluida_em, linha.cancelada_em) at time zone 'America/Sao_Paulo')::date <= p_ate
           when v_secao = 'sem_data' then true
           else linha.data <= p_ate end)
    and (v_busca is null
         or linha.descricao ilike '%' || v_busca || '%'
         or linha.numero_os ilike '%' || v_busca || '%'
         or linha.cliente_nome ilike '%' || v_busca || '%'
         or linha.colaborador_nome ilike '%' || v_busca || '%'
         -- Procurar por "folga" ou "férias" acha a ausencia pelo que ela e.
         or (case linha.categoria
               when 'folga' then 'folga'
               when 'ferias' then 'férias ferias'
               when 'outro' then 'ausência ausencia outro'
               else '' end) ilike '%' || v_busca || '%')
  order by
    case when v_secao = 'historico' then coalesce(linha.concluida_em, linha.cancelada_em) end desc nulls last,
    case when v_secao in ('agendadas', 'todas', 'ausencias') then linha.data end asc nulls last,
    linha.colaborador_nome asc,
    linha.criado_em desc;
end;
$function$;

-- Os contadores de trabalho param de somar ausencia; 'ausencias' continua com o
-- proprio numero.
create or replace function public.app_tarefas_contar()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_resultado jsonb;
begin
  select * into v_ctx from public.fn_tarefas_contexto();

  select jsonb_build_object(
    'hoje', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.hoje and linha.categoria = 'os'),
    'atrasadas', count(distinct linha.id) filter (where linha.atrasada),
    'futuras', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.tipo = 'agendada' and linha.categoria = 'os' and not linha.hoje and not linha.atrasada),
    'agendadas', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.tipo = 'agendada' and linha.categoria = 'os'),
    'sem_data', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.tipo = 'sem_data' and linha.categoria = 'os'),
    'ausencias', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.categoria <> 'os'
                                                   and coalesce(linha.data_fim, public.fn_tablet_data_hoje()) >= public.fn_tablet_data_hoje()),
    'atencao', count(distinct linha.id) filter (where linha.situacao = 'pendente' and linha.categoria = 'os' and (linha.hoje or linha.atrasada)),
    'minhas_pendentes', count(*) filter (where linha.situacao = 'pendente' and linha.minha and linha.participante_concluida_em is null),
    'gestao', v_ctx.gestao,
    'pode_criar', v_ctx.pode_criar,
    'hoje_data', public.fn_tablet_data_hoje()
  )
    into v_resultado
  from public.fn_tarefas_linhas(v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id) as linha;

  return coalesce(v_resultado, '{}'::jsonb);
end;
$function$;

revoke all on function public.fn_tarefas_linhas(uuid, uuid, uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.app_tarefas_listar(text, date, date, uuid, integer, text) from public, anon;
grant execute on function public.app_tarefas_listar(text, date, date, uuid, integer, text) to authenticated;
revoke all on function public.app_tarefas_contar() from public, anon;
grant execute on function public.app_tarefas_contar() to authenticated;

-- 4. Ausencia nao fica atrasada na televisao tambem. ----------------------------------
-- tv_colaboradores_tarefas tem a propria conta de atrasada, inline. Sem isto a TV
-- continuava escrevendo "ferias atrasada 5 dias", porque ninguem conclui ferias.

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
    part.colaborador_id,
    colab.nome::text,
    false,
    t.os_id,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    case when t.categoria = 'os' then os.cliente_id end,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado')::text end,
    case when t.categoria = 'os' then os.descricao_servico end,
    case when t.categoria = 'os'
         then coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) end,
    case when t.categoria = 'os' then coalesce(os.usa_relatorio_hh, false) end,
    case when t.categoria = 'os' then public.fn_tarefas_nome_usuario(os.responsavel_aprovacao_id) end,
    t.descricao,
    t.criado_em,
    public.fn_tarefas_nome_usuario(t.criado_por_user_id),
    t.atualizado_em,
    t.concluida_em,
    case when part.concluida_em is null then null
         when part.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
         else public.fn_tarefas_nome_usuario(part.concluida_por_user_id) end,
    part.concluida_por_sessao_id is not null,
    t.cancelada_em,
    public.fn_tarefas_nome_usuario(t.cancelada_por_user_id),
    t.cancelamento_motivo,
    exists (select 1 from public.tarefas_reservas as r
            where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is null),
    null::timestamptz,
    null::text,
    null::text,
    -- Atrasada e cobranca de trabalho: ausencia so terminou.
    (t.categoria = 'os' and t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
      and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje),
    (t.data is not null and v_hoje between t.data and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date),
    false,
    false,
    t.categoria,
    t.medida,
    t.dias,
    t.horas,
    case when t.data is null then null
         else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end,
    (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id),
    part.concluida_em
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab
    on colab.id = part.colaborador_id
   and colab.ativo is true
  left join public.ordens_servico as os on os.id = t.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = t.tenant_id and cli.empresa_id = t.empresa_id
  where t.tenant_id = v_ctx.tenant_id
    and t.empresa_id = v_ctx.empresa_id
    and (v_area is null or colab.area = v_area)
    and ((t.situacao = 'pendente' and part.concluida_em is null)
         or (part.concluida_em is not null and (part.concluida_em at time zone 'America/Sao_Paulo')::date = v_hoje))
  order by
    (t.categoria = 'os' and t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
      and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje) desc,
    t.data asc nulls last,
    colab.nome asc,
    t.criado_em asc;
end;
$function$;

revoke all on function public.tv_colaboradores_tarefas(text) from public, anon;
grant execute on function public.tv_colaboradores_tarefas(text) to authenticated;

-- 5. Empresa nova nasce com jornada. -------------------------------------------------
-- A 20260912190000 semeou jornada_padrao so para as empresas que existiam. Como
-- tv_periodos usa coalesce(jornada.horas, 0), uma empresa criada depois mostrava
-- meta de 0h em todo dia e nunca ficava vermelha — em silencio. A jornada da
-- fabrica passa a ser o padrao de quem nasce: seg a qui 9h, sex 8h, fim de semana
-- zero, 44h na semana. Mudar continua sendo update na tabela.

create or replace function public.fn_jornada_padrao_semear()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
begin
  insert into public.jornada_padrao (tenant_id, empresa_id, dow, horas)
  select new.tenant_id, new.id, d.dow, d.horas
  from (values (1, 9), (2, 9), (3, 9), (4, 9), (5, 8), (6, 0), (7, 0)) as d(dow, horas)
  on conflict (tenant_id, empresa_id, dow) do nothing;
  return new;
end;
$function$;

comment on function public.fn_jornada_padrao_semear() is
  'Da a toda empresa nova a jornada da fabrica (44h). Sem isto, tv_periodos leria zero e a televisao nunca cobraria hora nenhuma daquela empresa.';

drop trigger if exists trg_empresas_jornada_padrao on public.empresas;
create trigger trg_empresas_jornada_padrao
after insert on public.empresas
for each row execute function public.fn_jornada_padrao_semear();

-- Alcanca tambem quem foi criado entre a 20260912190000 e agora.
insert into public.jornada_padrao (tenant_id, empresa_id, dow, horas)
select e.tenant_id, e.id, d.dow, d.horas
from public.empresas as e
cross join (values (1, 9), (2, 9), (3, 9), (4, 9), (5, 8), (6, 0), (7, 0)) as d(dow, horas)
where not exists (
  select 1 from public.jornada_padrao as j
  where j.tenant_id = e.tenant_id and j.empresa_id = e.id
)
on conflict (tenant_id, empresa_id, dow) do nothing;

do $assertions$
declare
  v_tenant uuid := gen_random_uuid();
  v_empresa uuid;
  v_soma numeric;
begin
  -- Toda empresa que existe hoje tem semana de 44h.
  if exists (
    select 1 from public.empresas as e
    left join public.jornada_padrao as j on j.tenant_id = e.tenant_id and j.empresa_id = e.id
    group by e.id
    having coalesce(sum(j.horas), 0) <> 44
  ) then
    raise exception 'existe empresa sem a jornada de 44h';
  end if;

  -- E a proxima tambem nasce com ela.
  insert into public.tenants (id, nome) values (v_tenant, 'jornada teste')
  on conflict (id) do nothing;
  insert into public.empresas (tenant_id, cnpj, razao_social)
  values (v_tenant, '99000000000199', 'JORNADA TESTE LTDA')
  returning id into v_empresa;
  select coalesce(sum(horas), 0) into v_soma
  from public.jornada_padrao where empresa_id = v_empresa;
  if v_soma <> 44 then
    raise exception 'empresa nova nasceu com % horas de jornada, esperado 44', v_soma;
  end if;
  delete from public.jornada_padrao where empresa_id = v_empresa;
  delete from public.empresas where id = v_empresa;
  delete from public.tenants where id = v_tenant;
end;
$assertions$;

do $assertions$
declare
  v_ok boolean;
begin
  -- A restricao tem que recusar horas nulo de verdade, nao devolver NULO.
  select (
    ('horas' = 'dias' and 1 between 1 and 60 and null::numeric is null)
    or ('horas' = 'horas' and 1 = 1 and null::numeric is not null and null::numeric > 0 and null::numeric <= 24)
  ) into v_ok;
  if v_ok is not false then
    raise exception 'chk_tarefas_duracao continua deixando passar horas nulo (deu %)', v_ok;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tarefas'::regclass
      and conname = 'chk_tarefas_duracao'
      and pg_get_constraintdef(oid) like '%horas IS NOT NULL%'
  ) then
    raise exception 'chk_tarefas_duracao nao exige horas preenchida';
  end if;

  -- Ausencia nao pode mais ficar atrasada.
  if pg_get_functiondef('public.fn_tarefas_linhas(uuid, uuid, uuid, boolean, uuid)'::regprocedure)
     not like '%t.categoria = ''os'' and t.situacao = ''pendente''%' then
    raise exception 'fn_tarefas_linhas ainda marca ausencia como atrasada';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
