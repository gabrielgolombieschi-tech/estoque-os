-- Correcao da 20260907005000. No ramo da aprovacao automatica eu troquei
-- array_remove(array[...], null) por array_agg(distinct ...), que devolve NULL
-- quando nenhuma linha sobra — e FOREACH ... IN ARRAY NULL levanta erro, o que
-- abortaria o UPDATE do apontamento. Os dois ramos passam a usar coalesce para
-- um array vazio.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.fn_app_notificar_apontamento_horas()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_responsavel uuid;
  v_destinatario uuid;
  v_dono uuid;
  v_os_numero text;
  v_dados jsonb;
  v_destinatarios uuid[];
begin
  if coalesce(new.gerado_por_hh, false) then
    return new;
  end if;

  select os.responsavel_aprovacao_id,
         coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)
    into v_responsavel, v_os_numero
  from public.ordens_servico os
  where os.id = new.os_id
    and os.tenant_id = new.tenant_id
    and os.empresa_id = new.empresa_id;

  -- Dono da hora: o colaborador apontado, que nem sempre e quem lancou.
  select colaborador.user_id
    into v_dono
  from public.colaboradores as colaborador
  where colaborador.id = new.colaborador_id
    and colaborador.tenant_id = new.tenant_id
    and colaborador.empresa_id = new.empresa_id;

  v_dados := jsonb_build_object(
    'os_id', new.os_id,
    'apontamento_id', new.id,
    'url', '/os/' || new.os_id::text
  );

  if tg_op = 'INSERT' and new.status_aprovacao = 'pendente' then
    perform public.app_criar_notificacao(
      new.tenant_id, new.empresa_id, v_responsavel, 'hora_pendente',
      'Hora pendente de aprovação',
      format('Há uma hora lançada na OS %s aguardando sua aprovação.', v_os_numero),
      jsonb_set(v_dados, '{url}', '"/(tabs)/aprovacao"'::jsonb), 'hora_pendente'
    );
  elsif tg_op = 'UPDATE'
    and old.status_aprovacao is distinct from new.status_aprovacao
    and new.status_aprovacao = 'aprovado'
    and new.aprovado_automaticamente_em is not null then
    select coalesce(array_agg(distinct destinatario), array[]::uuid[])
      into v_destinatarios
    from unnest(array[v_responsavel, new.criado_por_user_id, v_dono]) as destinatario
    where destinatario is not null;

    foreach v_destinatario in array v_destinatarios
    loop
      perform public.app_criar_notificacao(
        new.tenant_id, new.empresa_id, v_destinatario, 'hora_aprovada_automaticamente',
        'Hora aprovada automaticamente',
        format('A hora lançada na OS %s foi aprovada após 7 dias.', v_os_numero),
        v_dados, null
      );
    end loop;
  elsif tg_op = 'UPDATE'
    and old.status_aprovacao is distinct from new.status_aprovacao
    and new.status_aprovacao = 'aprovado' then
    -- Aprovacao feita por alguem: quem aprovou nao precisa do proprio aviso.
    select coalesce(array_agg(distinct destinatario), array[]::uuid[])
      into v_destinatarios
    from unnest(array[new.criado_por_user_id, v_dono]) as destinatario
    where destinatario is not null
      and destinatario is distinct from auth.uid();

    foreach v_destinatario in array v_destinatarios
    loop
      perform public.app_criar_notificacao(
        new.tenant_id, new.empresa_id, v_destinatario, 'hora_aprovada',
        'Hora aprovada',
        format('A hora lançada na OS %s foi aprovada.', v_os_numero),
        v_dados, 'hora_aprovada'
      );
    end loop;
  elsif tg_op = 'UPDATE'
    and old.status_aprovacao is distinct from new.status_aprovacao
    and new.status_aprovacao = 'rejeitado' then
    perform public.app_criar_notificacao(
      new.tenant_id, new.empresa_id, new.criado_por_user_id, 'hora_rejeitada',
      'Hora rejeitada',
      format('A hora lançada na OS %s foi rejeitada. Motivo: %s', v_os_numero, coalesce(new.motivo_devolucao, 'não informado')),
      v_dados, null
    );
  end if;

  return new;
end;
$function$;

commit;
