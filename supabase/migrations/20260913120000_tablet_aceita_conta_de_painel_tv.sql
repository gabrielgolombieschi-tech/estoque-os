-- =====================================================================================
-- Uma conta só para a televisão e para o tablet.
--
-- Decisão do Gabriel em 13/09/2026: o painel de TV roda no navegador e o tablet
-- roda no aplicativo, e ele quer os dois no mesmo login, em vez de manter duas
-- contas do sistema.
--
-- O perfil não é por plataforma: é um por empresa, no banco, e vale nos dois
-- lugares. Por isso a conta não podia ser APONTADOR e PAINEL_TV ao mesmo tempo.
-- Juntar tinha dois caminhos opostos:
--
--  - por baixo, deixando a conta como APONTADOR e abrindo o painel para ela.
--    Recusado: APONTADOR não lê nada, então as telas de Projetos e Execução, que
--    também rodam em televisão, ficariam vazias.
--  - por cima, aceitando PAINEL_TV também no tablet. É o que esta migration faz.
--
-- O QUE ISSO CUSTA, escrito aqui porque é uma proteção que está sendo afrouxada:
-- até hoje a conta do tablet era obrigatoriamente APONTADOR, que não abre módulo
-- nenhum do ERP. O tablet fica solto na fábrica, e essa era a garantia de que a
-- senha dele não valia para mais nada. Com PAINEL_TV, quem tiver essa senha abre
-- as telas de televisão num navegador. O que se vê ali já está pendurado numa TV
-- na parede da fábrica, então o que vaza é o que já era público lá dentro — e foi
-- com esse argumento que a troca foi aceita.
--
-- O que NÃO mudou: a conta continua precisando estar autorizada como aparelho em
-- tablet_dispositivos, e continua precisando ser de aparelho, sem colaborador
-- vinculado. E as app_tarefas_* continuam recusando a conta do tablet.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. O tablet passa a aceitar os dois perfis. -----------------------------------------

create or replace function public.fn_tablet_dispositivo_atual()
returns public.tablet_dispositivos
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_dispositivo public.tablet_dispositivos;
begin
  if v_auth_uid is null then
    return null;
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  if v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    return null;
  end if;

  -- APONTADOR nao abre nada do ERP, e era o unico perfil aceito aqui. PAINEL_TV
  -- entrou em 13/09/2026 para a mesma conta servir a televisao e ao tablet: ele
  -- abre as telas de televisao, que mostram o que ja esta na parede da fabrica.
  -- Qualquer outro perfil continua fora: a conta do aparelho nao pode ser a de
  -- uma pessoa com acesso ao sistema.
  if coalesce(a.fn_current_empresa_papel(v_tenant_id, v_empresa_id), '') not in ('APONTADOR', 'PAINEL_TV') then
    return null;
  end if;

  select dispositivo.*
    into v_dispositivo
  from public.tablet_dispositivos as dispositivo
  where dispositivo.auth_user_id = v_auth_uid
    and dispositivo.tenant_id = v_tenant_id
    and dispositivo.empresa_id = v_empresa_id
    and dispositivo.ativo;

  if not found then
    return null;
  end if;

  return v_dispositivo;
end;
$function$;

revoke all on function public.fn_tablet_dispositivo_atual() from public, anon, authenticated;

-- 2. A tela de autorizacao passa a listar os dois perfis. ------------------------------

create or replace function public.web_tablet_contas_elegiveis()
returns table (auth_user_id uuid, nome text, email text, ja_autorizado boolean)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);
  return query
  select usuario.auth_user_id,
         coalesce(nullif(btrim(usuario.nome), ''), usuario.email)::text,
         usuario.email::text,
         exists (select 1 from public.tablet_dispositivos as dispositivo where dispositivo.auth_user_id = usuario.auth_user_id)
  from a.usuario as usuario
  join a.usuario_empresa as vinculo
    on vinculo.usuario_id = usuario.id
   and vinculo.empresa_id = v_ctx.empresa_id
   and vinculo.ativo
   and vinculo.deleted_at is null
  where usuario.ativo
    and usuario.deleted_at is null
    and usuario.auth_user_id is not null
    -- Mesma lista de fn_tablet_dispositivo_atual: as duas precisam concordar,
    -- senao a tela oferece conta que o banco recusa, ou esconde conta que serve.
    and upper(coalesce(vinculo.papel, '')) in ('APONTADOR', 'PAINEL_TV')
    and not exists (
      select 1 from public.colaboradores as colaborador
      where colaborador.user_id = usuario.auth_user_id
    )
  order by 2;
end;
$function$;

revoke all on function public.web_tablet_contas_elegiveis() from public, anon;
grant execute on function public.web_tablet_contas_elegiveis() to authenticated;

-- 3. A conta da SEGAU volta a ser PAINEL_TV. -------------------------------------------
-- Ela foi trocada para APONTADOR no dia 13/09/2026, enquanto se procurava onde
-- ficava a autorizacao do tablet, e isso derrubou as televisoes daquela empresa:
-- era a unica conta com PAINEL_TV ativo ali. O bloco e guardado pelo estado
-- exato, entao ele nao faz nada em copia nenhuma onde isso nao aconteceu.

do $volta_painel$
declare
  v_linhas integer;
begin
  update a.usuario_empresa as vinculo
     set papel = 'PAINEL_TV'
  from a.usuario as usuario, c.empresa as empresa
  where vinculo.usuario_id = usuario.id
    and empresa.id = vinculo.empresa_id
    and lower(usuario.email) = 'contato@segau.com.br'
    and upper(empresa.razao_social) like 'ELETRICA SEGAU%'
    and upper(coalesce(vinculo.papel, '')) = 'APONTADOR';
  get diagnostics v_linhas = row_count;
  raise notice 'contato@segau.com.br: % vinculo(s) devolvido(s) para PAINEL_TV', v_linhas;
end;
$volta_painel$;

-- 4. E fica autorizada como aparelho. ---------------------------------------------------
-- O nome e o tempo de inatividade se mudam depois em Cadastros › Tablets.

do $autoriza$
declare
  v_auth uuid;
  v_tenant uuid;
  v_empresa uuid;
begin
  select usuario.auth_user_id, empresa.tenant_id, empresa.id
    into v_auth, v_tenant, v_empresa
  from a.usuario as usuario
  join a.usuario_empresa as vinculo on vinculo.usuario_id = usuario.id and vinculo.ativo
  join c.empresa as empresa on empresa.id = vinculo.empresa_id
  where lower(usuario.email) = 'contato@segau.com.br'
    and upper(empresa.razao_social) like 'ELETRICA SEGAU%'
  limit 1;

  if v_auth is null then
    raise notice 'contato@segau.com.br nao existe nesta copia: nada a autorizar';
    return;
  end if;

  insert into public.tablet_dispositivos (tenant_id, empresa_id, auth_user_id, nome, inatividade_segundos, ativo)
  values (v_tenant, v_empresa, v_auth, 'Tablet da produção', 60, true)
  on conflict (auth_user_id) do update
     set ativo = true,
         atualizado_em = now();
  raise notice 'contato@segau.com.br autorizada como aparelho';
end;
$autoriza$;

do $assertions$
begin
  -- As duas listas de perfil precisam concordar, senao a tela e o banco brigam.
  if pg_get_functiondef('public.fn_tablet_dispositivo_atual()'::regprocedure)
     not like '%''APONTADOR'', ''PAINEL_TV''%' then
    raise exception 'fn_tablet_dispositivo_atual nao aceita PAINEL_TV';
  end if;
  if pg_get_functiondef('public.web_tablet_contas_elegiveis()'::regprocedure)
     not like '%''APONTADOR'', ''PAINEL_TV''%' then
    raise exception 'web_tablet_contas_elegiveis nao lista PAINEL_TV';
  end if;

  -- A conta do aparelho continua sem poder ser a de uma pessoa.
  if pg_get_functiondef('public.web_tablet_contas_elegiveis()'::regprocedure)
     not like '%not exists%colaborador.user_id = usuario.auth_user_id%' then
    raise exception 'a tela de tablets deixou de exigir conta sem colaborador';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
