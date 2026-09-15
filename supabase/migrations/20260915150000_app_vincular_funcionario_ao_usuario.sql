-- =====================================================================================
-- Funcionário ligado ao usuário já na criação, pelo aplicativo.
--
-- A tela "Novo usuário" do aplicativo (estoque-os-mobile,
-- src/app/configuracoes/usuario-novo.tsx) cria técnico ou apontador pela rota
-- /api/admin/invite-user, mas a conta nascia solta: public.colaboradores.user_id ficava
-- vazio, e o vínculo só se fazia depois, no web, em Cadastros > Colaboradores (coluna
-- "Usuário do sistema", update direto em colaboradores.user_id e email). Pedido de
-- Gabriel em 15/09/2026: escolher o funcionário ali mesmo, na criação.
--
--   app_funcionarios_sem_usuario(p_busca)
--       funcionários ativos da empresa atual ainda sem usuário, para escolher; a busca
--       (opcional) olha nome, cargo e e-mail, sem acento (fn_texto_busca).
--   app_vincular_funcionario_ao_usuario(p_colaborador_id, p_auth_user_id)
--       grava user_id e, se o funcionário estiver sem e-mail, o e-mail do usuário.
--       O aplicativo chama logo depois de a rota devolver o auth_user_id.
--
-- Quem pode: exatamente quem pode criar usuário no aplicativo. As duas funções leem
-- pode_criar_usuario de public.app_contexto_atual() (20260908050000), a mesma chave que
-- mostra o atalho em Configurações e libera o formulário. Ali a regra é
-- public.can('admin', 'manage_users', tenant), que cai em public.admin_can_manage_users:
-- OWNER ou ADMIN do tenant, fora quem é APONTADOR ou DIRETOR na empresa atual. É também o
-- que a rota confere antes de criar a conta. Chamar a função, em vez de copiar a
-- expressão, mantém as duas iguais se a regra mudar.
--
-- O vínculo é recusado, com a frase pronta para a tela:
--   * funcionário de outra empresa ou de outro tenant (ou que não existe), ou inativo;
--   * funcionário que já tem usuário. O mesmo par de novo não é erro: nada muda e a
--     resposta diz ja_estava_vinculado (repetição da chamada depois de uma queda de rede);
--   * usuário sem vínculo ativo com a empresa: a.usuario ativo e a.usuario_empresa ativo
--     nesta empresa, os dois sem deleted_at. É o mesmo critério da lista de usuários
--     vinculáveis do web (app/api/colaboradores/usuarios-vinculaveis);
--   * usuário já ligado a outro funcionário. A constraint colaboradores_user_id_key é
--     UNIQUE (user_id) na tabela inteira, então vale também para funcionário de outra
--     empresa; nesse caso a frase não diz qual.
--
-- Conferido em 15/09/2026, no banco local e em produção: colaboradores sem gatilho, com
-- colaboradores_user_id_key e RLS por tenant_memberships e empresa ativa; can,
-- admin_can_manage_users, has_active_empresa_access, current_tenant_id e
-- current_empresa_id iguais nos dois; app_contexto_atual em produção igual à migration.
-- Teste: supabase/tests/usuario_vinculo_funcionario.sql.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

do $pre$
begin
  if to_regprocedure('public.app_contexto_atual()') is null then
    raise exception 'Falta public.app_contexto_atual() (migration 20260908050000).';
  end if;
  if to_regprocedure('public.fn_texto_busca(text)') is null then
    raise exception 'Falta public.fn_texto_busca(text) (migration 20260914100000).';
  end if;
end;
$pre$;

-- 1. Funcionários sem usuário ----------------------------------------------------------

create or replace function public.app_funcionarios_sem_usuario(p_busca text default null)
returns table(id uuid, nome text, cargo text, area text, email text)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  -- Sem sessão ou sem empresa, app_contexto_atual já levanta
  -- 'Autenticação e contexto de empresa são obrigatórios.'
  v_contexto jsonb := public.app_contexto_atual();
  v_tenant_id uuid := (v_contexto->>'tenant_id')::uuid;
  v_empresa_id uuid := (v_contexto->>'empresa_id')::uuid;
  v_termo text := public.fn_texto_busca(nullif(btrim(p_busca), ''));
begin
  if not coalesce((v_contexto->>'pode_criar_usuario')::boolean, false) then
    raise exception 'Seu perfil não pode criar usuários.';
  end if;

  return query
  select
    colaborador.id,
    colaborador.nome::text,
    nullif(btrim(colaborador.cargo), '')::text,
    colaborador.area,
    nullif(btrim(colaborador.email), '')
  from public.colaboradores as colaborador
  where colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true
    and colaborador.user_id is null
    and (
      v_termo = ''
      or strpos(public.fn_texto_busca(colaborador.nome), v_termo) > 0
      or strpos(public.fn_texto_busca(colaborador.cargo), v_termo) > 0
      or strpos(public.fn_texto_busca(colaborador.email), v_termo) > 0
    )
  order by colaborador.nome, colaborador.id;
end;
$function$;

comment on function public.app_funcionarios_sem_usuario(text) is
  'Aplicativo, Novo usuário: funcionários ativos da empresa atual sem usuário. Mesma permissão de pode_criar_usuario (app_contexto_atual).';

revoke all on function public.app_funcionarios_sem_usuario(text) from public, anon;
grant execute on function public.app_funcionarios_sem_usuario(text) to authenticated;

-- 2. Vincular ------------------------------------------------------------------------

create or replace function public.app_vincular_funcionario_ao_usuario(p_colaborador_id uuid, p_auth_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_contexto jsonb := public.app_contexto_atual();
  v_tenant_id uuid := (v_contexto->>'tenant_id')::uuid;
  v_empresa_id uuid := (v_contexto->>'empresa_id')::uuid;
  v_colaborador public.colaboradores%rowtype;
  v_usuario_email text;
  v_outro_nome text;
  v_outro_na_empresa boolean;
  v_email_gravado text;
begin
  if not coalesce((v_contexto->>'pode_criar_usuario')::boolean, false) then
    raise exception 'Seu perfil não pode criar usuários.';
  end if;
  if p_colaborador_id is null then
    raise exception 'Escolha o funcionário.';
  end if;
  if p_auth_user_id is null then
    raise exception 'Informe o usuário que vai ficar ligado ao funcionário.';
  end if;

  -- A linha fica travada até o fim: duas chamadas para o mesmo funcionário não passam
  -- as duas pela conferência de "já tem usuário".
  select colaborador.*
    into v_colaborador
  from public.colaboradores as colaborador
  where colaborador.id = p_colaborador_id
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
  for update;

  if not found then
    raise exception 'Funcionário não encontrado nesta empresa.';
  end if;
  if v_colaborador.ativo is not true then
    raise exception 'O funcionário % está inativo.', v_colaborador.nome;
  end if;
  if v_colaborador.user_id = p_auth_user_id then
    return jsonb_build_object(
      'sucesso', true,
      'ja_estava_vinculado', true,
      'colaborador_id', v_colaborador.id,
      'nome', v_colaborador.nome,
      'email', nullif(btrim(v_colaborador.email), '')
    );
  end if;
  if v_colaborador.user_id is not null then
    raise exception 'O funcionário % já está ligado a outro usuário.', v_colaborador.nome;
  end if;

  select usuario.email
    into v_usuario_email
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
  where usuario.auth_user_id = p_auth_user_id
    and usuario.ativo is true
    and usuario.deleted_at is null
    and usuario_empresa.empresa_id = v_empresa_id
    and usuario_empresa.ativo is true
    and usuario_empresa.deleted_at is null
  limit 1;

  if not found then
    raise exception 'Este usuário não tem vínculo ativo com esta empresa.';
  end if;

  select outro.nome, (outro.tenant_id = v_tenant_id and outro.empresa_id = v_empresa_id)
    into v_outro_nome, v_outro_na_empresa
  from public.colaboradores as outro
  where outro.user_id = p_auth_user_id
  limit 1;

  if found then
    if v_outro_na_empresa then
      raise exception 'Este usuário já está ligado ao funcionário %.', v_outro_nome;
    end if;
    raise exception 'Este usuário já está ligado a um funcionário de outra empresa.';
  end if;

  begin
    update public.colaboradores as colaborador
       set user_id = p_auth_user_id,
           email = coalesce(nullif(btrim(colaborador.email), ''), v_usuario_email)
     where colaborador.id = v_colaborador.id
    returning colaborador.email into v_email_gravado;
  exception when unique_violation then
    -- Outra chamada ligou este usuário a outro funcionário entre a conferência acima e
    -- a gravação (a unique de user_id é que segura).
    raise exception 'Este usuário acabou de ser ligado a outro funcionário.';
  end;

  return jsonb_build_object(
    'sucesso', true,
    'ja_estava_vinculado', false,
    'colaborador_id', v_colaborador.id,
    'nome', v_colaborador.nome,
    'email', v_email_gravado
  );
end;
$function$;

comment on function public.app_vincular_funcionario_ao_usuario(uuid, uuid) is
  'Aplicativo, Novo usuário: liga o funcionário ao auth user recém-criado (user_id e, se faltar, e-mail). Mesma permissão de pode_criar_usuario (app_contexto_atual).';

revoke all on function public.app_vincular_funcionario_ao_usuario(uuid, uuid) from public, anon;
grant execute on function public.app_vincular_funcionario_ao_usuario(uuid, uuid) to authenticated;

-- 3. Conferências ----------------------------------------------------------------------

do $assertions$
declare
  v_nome text;
begin
  foreach v_nome in array array['app_funcionarios_sem_usuario', 'app_vincular_funcionario_ao_usuario'] loop
    if (select count(*) from pg_proc as p join pg_namespace as n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = v_nome) <> 1 then
      raise exception 'public.% ficou com mais de uma assinatura', v_nome;
    end if;
  end loop;

  if has_function_privilege('anon', 'public.app_funcionarios_sem_usuario(text)', 'execute')
     or has_function_privilege('anon', 'public.app_vincular_funcionario_ao_usuario(uuid, uuid)', 'execute') then
    raise exception 'funcao de vinculo de funcionario aberta para anon';
  end if;
  if not has_function_privilege('authenticated', 'public.app_funcionarios_sem_usuario(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.app_vincular_funcionario_ao_usuario(uuid, uuid)', 'execute') then
    raise exception 'authenticated sem execute nas funcoes de vinculo de funcionario';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
