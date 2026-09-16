-- =====================================================================================
-- Falta: a ausência que ninguém combinou, com e sem atestado.
--
-- Decidido com o Gabriel em 16/09/2026. Na segunda-feira um funcionário faltou e o
-- dia dele ficou zerado na TV, sem ninguém saber se ele faltou, se esqueceu de
-- apontar ou se o apontamento se perdeu. Zero não é informação: é a mesma tela para
-- três coisas diferentes. Agora a coordenação registra a falta, e o buraco passa a
-- ter nome.
--
-- Duas categorias novas em public.tarefas.categoria, ao lado de 'os', 'folga',
-- 'ferias' e 'outro':
--
--   falta_justificada  falta COM atestado   -> nas telas: "Falta com atestado"
--   falta              falta SEM atestado   -> nas telas: "Falta sem atestado"
--
-- REGRA DE DESCONTO DA META DA SEMANA (a conta mora na tela do painel de TV, não
-- aqui: o banco só diz a categoria, quem soma é app/painel-tv/colaboradores):
--
--   DESCONTA   folga, ferias, outro, falta_justificada
--   NÃO DESCONTA   falta
--
-- É a diferença toda entre as duas. A falta com atestado é ausência combinada como
-- qualquer outra: as horas saem da meta e a semana fecha certa. A falta sem atestado
-- NÃO sai: as horas continuam previstas e o buraco aparece na TV, que é justamente o
-- que se quer ver. Por isso as duas são categorias separadas, e não uma categoria só
-- com um "tem atestado" pendurado — a tela da TV lê categoria.
--
-- Medida: o que já existe. Dia inteiro (medida 'dias', 1 a 60) ou horas (medida
-- 'horas', 0 < h <= 24). Atraso ou saída antes do fim do expediente é falta medida em
-- horas, e falta em horas não reserva o dia — a pessoa trabalhou o resto dele.
--
-- Quem marca: coordenação para cima (ADMIN, DIRETOR, COORDENACAO), que é o
-- v_ctx.gestao de fn_tarefas_contexto — a mesma regra que já vale para folga, férias
-- e outro. Para qualquer pessoa e também para si. Técnico e apontador não marcam
-- falta, nem a própria: a falta é o registro do que a coordenação viu, e quem faltou
-- carimbando a si mesmo esvaziaria o registro.
--
-- Atestado apresentado dias depois: app_tarefas_marcar_atestado troca 'falta' por
-- 'falta_justificada' na MESMA linha. Nada é cancelado nem recadastrado — a reserva
-- do dia continua de pé, o histórico da tarefa fica inteiro e o audit_log guarda a
-- troca. Não se digitaliza documento nenhum: é só o registro.
--
-- Funções geradas a partir das definições de PRODUÇÃO de 16/09/2026, com as trocas
-- conferidas uma a uma.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. As duas faltas entram na lista de categorias ---------------------------------------

alter table public.tarefas drop constraint if exists chk_tarefas_categoria;
alter table public.tarefas add constraint chk_tarefas_categoria
  check (categoria in ('os', 'folga', 'ferias', 'falta_justificada', 'falta', 'outro'));

comment on column public.tarefas.categoria is
  'os = trabalho numa ordem de servico; folga, ferias, falta_justificada (falta com atestado), falta (falta sem atestado) e outro = ausencia, sem OS. So falta nao desconta a meta da semana.';

-- Os outros checks da tabela já servem para a falta sem uma linha de mudança, e é
-- assim que tem de continuar. Se alguém afrouxar um deles, a falta passa a aceitar
-- combinação sem sentido, então a migration confere e para:
--
--   chk_tarefas_os_por_categoria   (categoria = 'os') = (os_id is not null)
--                                  -> falta nunca tem OS, como toda ausência.
--   chk_tarefas_ausencia_agendada  categoria = 'os' or tipo = 'agendada'
--                                  -> não existe falta sem o dia em que a pessoa faltou.
--   chk_tarefas_dias_por_tipo      só tarefa agendada dura mais de um dia.
--   chk_tarefas_duracao            dias 1..60 sem horas, ou horas 0 < h <= 24 num dia só.
--
-- Nenhum deles cita categoria de ausência, e é por isso que valem para a falta.
do $checks_coerentes$
declare
  v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
  from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_os_por_categoria';
  if v_def is null or v_def not like '%(categoria = ''os''::text) = (os_id IS NOT NULL)%' then
    raise exception 'chk_tarefas_os_por_categoria mudou: a falta pode ter ganhado OS (%)', v_def;
  end if;

  select pg_get_constraintdef(oid) into v_def
  from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_ausencia_agendada';
  if v_def is null or v_def not like '%categoria = ''os''::text%' or v_def not like '%tipo = ''agendada''::text%' then
    raise exception 'chk_tarefas_ausencia_agendada mudou: pode ter aparecido falta sem data (%)', v_def;
  end if;

  select pg_get_constraintdef(oid) into v_def
  from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_dias_por_tipo';
  if v_def is null or v_def not like '%tipo = ''agendada''::text%' then
    raise exception 'chk_tarefas_dias_por_tipo mudou (%)', v_def;
  end if;

  select pg_get_constraintdef(oid) into v_def
  from pg_constraint where conrelid = 'public.tarefas'::regclass and conname = 'chk_tarefas_duracao';
  if v_def is null
     or v_def not like '%(dias >= 1) AND (dias <= 60)%'
     or v_def not like '%(horas IS NOT NULL)%' then
    raise exception 'chk_tarefas_duracao mudou: falta em horas pode ter ficado sem horas (%)', v_def;
  end if;
end;
$checks_coerentes$;

-- 2. Criar a falta ----------------------------------------------------------------------
--
-- A permissão não muda de forma: a falta cai no mesmo ramo "não é OS" que já exige
-- v_ctx.gestao, e por isso já vale também para a própria pessoa da coordenação. O que
-- muda é a lista de categorias aceitas e as frases, que falavam só de folga e férias.

CREATE OR REPLACE FUNCTION public.app_tarefas_criar(p_colaboradores uuid[], p_tipo text, p_data date, p_dias integer, p_descricao text, p_categoria text DEFAULT 'os'::text, p_os_id integer DEFAULT NULL::integer, p_medida text DEFAULT 'dias'::text, p_horas numeric DEFAULT NULL::numeric, p_chave uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
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
  -- 'falta_justificada' e a falta COM atestado, 'falta' a falta SEM atestado.
  if v_categoria not in ('os', 'folga', 'ferias', 'falta_justificada', 'falta', 'outro') then
    return public.fn_tarefas_erro('categoria_invalida', 'Escolha o que a tarefa é: trabalho na OS, folga, férias, falta com atestado, falta sem atestado ou outro.');
  end if;
  if v_medida not in ('dias', 'horas') then
    return public.fn_tarefas_erro('medida_invalida', 'A duração é medida em dias ou em horas.');
  end if;

  v_data := case when v_tipo = 'agendada' then p_data end;
  if v_tipo = 'agendada' and v_data is null then
    return public.fn_tarefas_erro('data_obrigatoria', 'Tarefa agendada precisa de uma data.');
  end if;
  -- Nao existe "férias sem data", nem falta sem o dia em que a pessoa faltou.
  if v_categoria <> 'os' and v_tipo <> 'agendada' then
    return public.fn_tarefas_erro('data_obrigatoria', 'Folga, férias, falta e outras ausências precisam de data.');
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
      return public.fn_tarefas_erro('os_invalida', 'Folga, férias, falta e outras ausências não têm OS.');
    end if;
    -- Nao existe "responsável pelas férias de alguém": ausencia e da coordenacao
    -- para cima (ADMIN, DIRETOR, COORDENACAO), que e o que v_ctx.gestao diz.
    -- Vale tambem para a falta, inclusive a propria: quem faltou nao carimba a
    -- propria falta, senao o registro deixaria de ser o que a coordenacao viu.
    if not v_ctx.gestao then
      return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação registra folga, férias, falta e outras ausências.');
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

-- 3. Ler: a falta aparece nas ausências e é achada pelo nome ----------------------------
--
-- A seção 'ausencias' é "categoria <> 'os'", então a falta já entra nela sem mudança.
-- O que faltava era a busca por palavra: quem digita "falta" tem de achar as duas, e
-- quem digita "atestado" tem de conseguir separar uma da outra.

CREATE OR REPLACE FUNCTION public.app_tarefas_listar(p_secao text DEFAULT 'agendadas'::text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_colaborador_id uuid DEFAULT NULL::uuid, p_os_id integer DEFAULT NULL::integer, p_busca text DEFAULT NULL::text)
 RETURNS SETOF tarefa_linha
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
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
         -- Procurar por "folga", "férias" ou "falta" acha a ausencia pelo que ela
         -- e. "falta" traz as duas; "atestado" separa quem tem de quem nao tem.
         or (case linha.categoria
               when 'folga' then 'folga'
               when 'ferias' then 'férias ferias'
               when 'falta_justificada' then 'falta com atestado justificada'
               when 'falta' then 'falta sem atestado injustificada'
               when 'outro' then 'ausência ausencia outro'
               else '' end) ilike '%' || v_busca || '%')
  order by
    case when v_secao = 'historico' then coalesce(linha.concluida_em, linha.cancelada_em) end desc nulls last,
    case when v_secao in ('agendadas', 'todas', 'ausencias') then linha.data end asc nulls last,
    linha.colaborador_nome asc,
    linha.criado_em desc;
end;
$function$;

-- 4. Escolher quem vai na tarefa: o dia preso pela falta diz que é falta -----------------

CREATE OR REPLACE FUNCTION public.app_tarefas_colaboradores(p_data date DEFAULT NULL::date)
 RETURNS TABLE(id uuid, nome text, cargo text, sou_eu boolean, ocupado boolean, ocupado_tarefa_id uuid, ocupado_resumo text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
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
             -- Quem esta montando a agenda precisa saber POR QUE o dia esta preso;
             -- "Falta" sozinho nao diz se o atestado ja chegou.
             when 'falta_justificada' then 'Falta com atestado'
             when 'falta' then 'Falta sem atestado'
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

-- 5. Reagendar a falta (o dia certo da falta, quando se marcou errado) -------------------

CREATE OR REPLACE FUNCTION public.app_tarefas_reagendar(p_tarefa_id uuid, p_data date DEFAULT NULL::date, p_dias integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
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
    return public.fn_tarefas_erro('data_obrigatoria', 'Folga, férias, falta e outras ausências precisam de data.');
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

-- 6. O atestado que chega dias depois ---------------------------------------------------
--
-- A pessoa faltou na segunda e trouxe o atestado na quarta. Sem isto, a coordenação
-- teria de cancelar a falta e cadastrar outra: perderia o histórico, mexeria na
-- reserva do dia e o audit_log mostraria uma tarefa apagada em vez do que de fato
-- aconteceu. Aqui é uma linha só, que troca de categoria — e a TV, que lê categoria,
-- passa a descontar aquele dia da meta da semana.
--
-- p_com_atestado default true porque o caminho normal é o atestado chegando; false
-- desfaz o carimbo quando alguém marcou por engano.
create or replace function public.app_tarefas_marcar_atestado(
  p_tarefa_id uuid,
  p_com_atestado boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_tarefa public.tarefas;
  v_alvo text := case when coalesce(p_com_atestado, true) then 'falta_justificada' else 'falta' end;
  v_anterior text;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_travar(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id);
  if v_tarefa.id is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;

  -- Mesma permissão de registrar a falta: coordenação para cima, inclusive na
  -- própria. fn_tarefas_pode_gerir não serve aqui porque ela também abre a porta
  -- para o responsável da OS, e ausência não tem OS nem responsável.
  if not v_ctx.gestao then
    return public.fn_tarefas_erro('sem_permissao', 'Só a coordenação marca o atestado de uma falta.');
  end if;

  if v_tarefa.categoria not in ('falta', 'falta_justificada') then
    return public.fn_tarefas_erro('categoria_invalida', 'O atestado só vale para falta: esta tarefa não é uma falta.');
  end if;
  if v_tarefa.situacao = 'cancelada' then
    return public.fn_tarefas_erro('tarefa_encerrada', 'Falta cancelada não recebe atestado.');
  end if;

  v_anterior := v_tarefa.categoria;

  -- Já estava como se pediu: responde 'repetido' em vez de gravar de novo, para o
  -- clique repetido (ou o pedido que voltou pela rede) não virar linha de auditoria.
  if v_anterior = v_alvo then
    return jsonb_build_object(
      'sucesso', true,
      'repetido', true,
      'anterior', v_anterior,
      'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
      'avisos', '[]'::jsonb
    );
  end if;

  -- Só a categoria muda. Data, dias, horas, participantes e reservas ficam como
  -- estavam: é a mesma ausência, o que mudou é o documento.
  update public.tarefas
     set categoria = v_alvo,
         atualizado_em = now(),
         atualizado_por_user_id = v_ctx.auth_uid
   where id = v_tarefa.id
  returning * into v_tarefa;

  return jsonb_build_object(
    'sucesso', true,
    'anterior', v_anterior,
    'tarefa', public.fn_tarefas_linha_json(v_tarefa.id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id),
    'avisos', '[]'::jsonb
  );
end;
$function$;
revoke all on function public.app_tarefas_marcar_atestado(uuid, boolean) from public, anon;
grant execute on function public.app_tarefas_marcar_atestado(uuid, boolean) to authenticated, service_role;

-- 7. Confere o que subiu ----------------------------------------------------------------
do $assertions$
declare
  v_ok boolean;
begin
  -- As duas categorias entram, e uma inventada continua fora.
  select true into v_ok
  from pg_constraint
  where conrelid = 'public.tarefas'::regclass
    and conname = 'chk_tarefas_categoria'
    and pg_get_constraintdef(oid) like '%falta_justificada%'
    and pg_get_constraintdef(oid) like '%''falta''::text%';
  if not coalesce(v_ok, false) then
    raise exception 'chk_tarefas_categoria ficou sem falta_justificada e falta';
  end if;

  if pg_get_functiondef('public.app_tarefas_criar(uuid[], text, date, integer, text, text, integer, text, numeric, uuid)'::regprocedure)
     not like '%''falta_justificada'', ''falta''%' then
    raise exception 'app_tarefas_criar continua recusando as duas faltas';
  end if;
  -- E continua exigindo coordenação para cima em toda ausência, inclusive a falta.
  if pg_get_functiondef('public.app_tarefas_criar(uuid[], text, date, integer, text, text, integer, text, numeric, uuid)'::regprocedure)
     not like '%if not v_ctx.gestao then%' then
    raise exception 'app_tarefas_criar perdeu a trava de quem registra ausência';
  end if;

  if pg_get_functiondef('public.app_tarefas_listar(text, date, date, uuid, integer, text)'::regprocedure)
     not like '%when ''falta'' then ''falta sem atestado%' then
    raise exception 'app_tarefas_listar não acha a falta pela palavra';
  end if;

  if pg_get_functiondef('public.app_tarefas_colaboradores(date)'::regprocedure)
     not like '%Falta com atestado%' then
    raise exception 'app_tarefas_colaboradores não diz que o dia está preso por falta';
  end if;

  -- A RPC do atestado existe com a assinatura que as telas chamam, e só para quem
  -- tem conta na empresa.
  if pg_get_function_result('public.app_tarefas_marcar_atestado(uuid, boolean)'::regprocedure) <> 'jsonb' then
    raise exception 'app_tarefas_marcar_atestado não devolve jsonb';
  end if;
  if not has_function_privilege('authenticated', 'public.app_tarefas_marcar_atestado(uuid, boolean)', 'execute')
     or not has_function_privilege('service_role', 'public.app_tarefas_marcar_atestado(uuid, boolean)', 'execute') then
    raise exception 'app_tarefas_marcar_atestado ficou sem grant';
  end if;
  if has_function_privilege('anon', 'public.app_tarefas_marcar_atestado(uuid, boolean)', 'execute') then
    raise exception 'app_tarefas_marcar_atestado ficou aberta para anon';
  end if;

  -- As quatro funções tocadas não podem ter perdido grant no create or replace.
  if not has_function_privilege('authenticated', 'public.app_tarefas_criar(uuid[], text, date, integer, text, text, integer, text, numeric, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.app_tarefas_listar(text, date, date, uuid, integer, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.app_tarefas_colaboradores(date)', 'execute')
     or not has_function_privilege('authenticated', 'public.app_tarefas_reagendar(uuid, date, integer)', 'execute') then
    raise exception 'alguma função de tarefas perdeu o grant de authenticated';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
