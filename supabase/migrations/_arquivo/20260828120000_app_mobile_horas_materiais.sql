begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Papéis que podem registrar horas pelo aplicativo. APONTADOR é mantido como
-- alias legado; o papel vigente no cadastro é APONTAMENTO_RH.
create or replace function public.app_papel_pode_lancar_horas(p_papel text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select upper(coalesce(p_papel, '')) in (
    'ADMIN', 'DIRETOR', 'COORDENACAO', 'TECNICO',
    'APONTAMENTO_RH', 'APONTADOR'
  );
$$;

revoke all on function public.app_papel_pode_lancar_horas(text)
  from public, anon, authenticated, service_role;

-- Busca enxuta para o lançamento de material em campo. Não retorna preço,
-- custo nem fornecedor e sempre respeita tenant e empresa ativos.
create or replace function public.app_buscar_materiais(
  p_termo text default null,
  p_fabricante text default null,
  p_limite integer default 100
)
returns table (
  item_id integer,
  codigo_interno text,
  nome text,
  quantidade_disponivel numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_termo text := nullif(btrim(coalesce(p_termo, '')), '');
  v_fabricante text := nullif(btrim(coalesce(p_fabricante, '')), '');
  v_limite integer := greatest(1, least(coalesce(p_limite, 100), 100));
  v_numerico boolean := coalesce(v_termo ~ '^[0-9]+$', false);
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if v_termo is null and v_fabricante is null then
    raise exception 'Informe nome, código ou fabricante para localizar o material.';
  end if;

  return query
  select
    item.id,
    item.codigo_interno::text,
    coalesce(item.nome, item.descricao)::text,
    coalesce(estoque.quantidade_atual, 0)::numeric
  from public.itens as item
  left join public.estoque as estoque
    on estoque.tenant_id = item.tenant_id
   and estoque.empresa_id = item.empresa_id
   and estoque.item_id = item.id
  where item.tenant_id = v_tenant_id
    and item.empresa_id = v_empresa_id
    and item.ativo is true
    and item.tipo = 'produto'
    and item.controla_estoque is true
    and (
      v_termo is null
      or (
        v_numerico
        and (item.id::text = v_termo or item.codigo_interno = v_termo or item.codigo_barras = v_termo)
      )
      or (
        not v_numerico
        and (
          item.nome ilike '%' || v_termo || '%'
          or item.descricao ilike '%' || v_termo || '%'
          or item.codigo_interno ilike '%' || v_termo || '%'
        )
      )
    )
    and (v_fabricante is null or item.fabricante ilike '%' || v_fabricante || '%')
  order by lower(coalesce(item.nome, item.descricao)), item.id
  limit v_limite;
end;
$$;

-- O total monetário só é devolvido a quem não é apontador. Assim a regra não
-- depende apenas da interface mobile e não pode ser contornada pelo cliente.
create or replace function public.app_resumo_materiais_os(p_os_id integer)
returns table (
  itens_lancados bigint,
  valor_total numeric,
  pode_ver_valores boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_valores boolean;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select upper(usuario_empresa.papel)
    into v_papel
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = v_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico as os
    where os.id = p_os_id
      and os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
  ) then
    raise exception 'A OS informada não existe ou não pertence à empresa atual.';
  end if;

  v_pode_ver_valores := v_papel not in ('APONTAMENTO_RH', 'APONTADOR');

  return query
  select
    count(os_item.id)::bigint,
    case
      when v_pode_ver_valores then coalesce(sum(os_item.valor_total), 0)::numeric
      else null::numeric
    end,
    v_pode_ver_valores
  from public.os_itens as os_item
  join public.itens as item
    on item.id = os_item.item_id
   and item.tenant_id = os_item.tenant_id
   and item.empresa_id = os_item.empresa_id
  where os_item.os_id = p_os_id
    and os_item.tenant_id = v_tenant_id
    and os_item.empresa_id = v_empresa_id
    and item.tipo = 'produto';
end;
$$;

revoke all on function public.app_buscar_materiais(text, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.app_resumo_materiais_os(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.app_buscar_materiais(text, text, integer) to authenticated;
grant execute on function public.app_resumo_materiais_os(integer) to authenticated;

-- Material fica disponível a todos os papéis válidos da empresa. As demais
-- travas (contexto, OS em andamento, estoque e saldo) permanecem nas RPCs.
do $patch_material_roles$
declare
  v_proc regprocedure;
  v_definition text;
  v_patched text;
begin
  foreach v_proc in array array[
    'public.app_lancar_material_os(integer,text,numeric,text)'::regprocedure,
    'public.app_lancar_material_os_por_item_id(integer,integer,numeric,text)'::regprocedure
  ] loop
    select pg_get_functiondef(v_proc) into v_definition;
    v_patched := replace(
      v_definition,
      'not in (''ADMIN'', ''DIRETOR'', ''COORDENACAO'', ''TECNICO'')',
      'not in (''ADMIN'', ''DIRETOR'', ''FINANCEIRO'', ''FATURAMENTO'', ''COORDENACAO'', ''COMPRAS'', ''ALMOXARIFADO'', ''TECNICO'', ''APONTAMENTO_RH'', ''PAINEL_TV'', ''APONTADOR'')'
    );
    if v_patched = v_definition then
      raise exception 'material_role_patch_token_not_found: %', v_proc;
    end if;
    execute v_patched;
  end loop;
end;
$patch_material_roles$;

-- Corrige o nome real do papel apontador e limita o lançamento de horas aos
-- papéis operacionais/gestores definidos para o app.
do $patch_hour_roles$
declare
  v_proc regprocedure;
  v_definition text;
  v_patched text;
  v_token text := $token$
  if v_papel_empresa is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;
$token$;
  v_replacement text := $replacement$
  if v_papel_empresa is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  if not public.app_papel_pode_lancar_horas(v_papel_empresa) then
    raise exception 'Seu perfil não tem permissão para lançar horas na OS.';
  end if;
$replacement$;
begin
  foreach v_proc in array array[
    'public.app_lancar_apontamentos_lote(integer,date,uuid,jsonb,text,boolean)'::regprocedure,
    'public.app_lancar_hh(integer,uuid,date,bigint,time,time,time,time,smallint,numeric,numeric,text)'::regprocedure,
    'public.app_lancar_hh_lote(integer,date,time,time,time,time,smallint,text,jsonb)'::regprocedure
  ] loop
    select pg_get_functiondef(v_proc) into v_definition;
    v_patched := replace(
      v_definition,
      'upper(v_papel_empresa) = ''APONTADOR''',
      'upper(v_papel_empresa) in (''APONTAMENTO_RH'', ''APONTADOR'')'
    );
    v_patched := replace(v_patched, v_token, v_replacement);
    if v_patched = v_definition or position('app_papel_pode_lancar_horas' in v_patched) = 0 then
      raise exception 'hour_role_patch_token_not_found: %', v_proc;
    end if;
    execute v_patched;
  end loop;
end;
$patch_hour_roles$;

-- Mantém as restrições do apontador nas leituras e escritas legadas. Sem
-- esse ajuste, APONTAMENTO_RH seria tratado como gestor por essas RPCs.
do $patch_apontador_aliases$
declare
  v_proc regprocedure;
  v_definition text;
  v_patched text;
begin
  foreach v_proc in array array[
    'public.app_listar_os(boolean,text)'::regprocedure,
    'public.app_listar_apontamentos(date,date,integer,uuid)'::regprocedure,
    'public.app_editar_apontamento(uuid,numeric,uuid,text,boolean)'::regprocedure,
    'public.app_excluir_apontamento(uuid)'::regprocedure,
    'public.app_listar_especialidades_hh(integer,uuid)'::regprocedure,
    'public.app_criar_os_hh(integer,text)'::regprocedure
  ] loop
    select pg_get_functiondef(v_proc) into v_definition;
    v_patched := replace(
      v_definition,
      'upper(v_papel_empresa) = ''APONTADOR''',
      'upper(v_papel_empresa) in (''APONTAMENTO_RH'', ''APONTADOR'')'
    );
    v_patched := replace(
      v_patched,
      'upper(v_papel_empresa) <> ''APONTADOR''',
      'upper(v_papel_empresa) not in (''APONTAMENTO_RH'', ''APONTADOR'')'
    );
    v_patched := replace(
      v_patched,
      'upper(coalesce(v_papel,''''))=''APONTADOR''',
      'upper(coalesce(v_papel,'''')) in (''APONTAMENTO_RH'', ''APONTADOR'')'
    );
    if v_patched = v_definition then
      raise exception 'apontador_alias_patch_token_not_found: %', v_proc;
    end if;
    execute v_patched;
  end loop;
end;
$patch_apontador_aliases$;

-- Na seleção de equipe o apontador enxerga apenas o próprio colaborador.
-- Gestores e técnicos continuam podendo fazer lançamentos em lote.
create or replace function public.app_listar_colaboradores()
returns table (
  id uuid,
  nome character varying,
  sou_eu boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_colaborador_id uuid;
  v_papel_empresa text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  select upper(usuario_empresa.papel)
    into v_papel_empresa
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = v_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if v_papel_empresa is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  return query
  select
    colaborador.id,
    colaborador.nome,
    (colaborador.user_id is not distinct from v_auth_uid) as sou_eu
  from public.colaboradores as colaborador
  where colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true
    and (
      v_papel_empresa not in ('APONTAMENTO_RH', 'APONTADOR')
      or colaborador.id = v_colaborador_id
    )
  order by colaborador.nome;
end;
$$;

revoke all on function public.app_listar_colaboradores()
  from public, anon, authenticated, service_role;
grant execute on function public.app_listar_colaboradores() to authenticated;

-- Financeiro com vínculo de colaborador deve usar a leitura administrativa,
-- que não depende da RPC operacional app_listar_os.
do $patch_finance_os_read$
declare
  v_definition text;
  v_patched text;
begin
  select pg_get_functiondef('public.app_listar_os_fluxo(text,text)'::regprocedure)
    into v_definition;
  v_patched := replace(
    v_definition,
    'if v_colaborador_id is not null then',
    'if v_colaborador_id is not null and upper(v_papel) <> ''FINANCEIRO'' then'
  );
  if v_patched = v_definition then
    raise exception 'finance_os_read_patch_token_not_found';
  end if;
  execute v_patched;
end;
$patch_finance_os_read$;

-- Aprovação passa a depender do papel de quem lançou: APONTAMENTO_RH fica
-- pendente; os demais papéis autorizados nas RPCs nascem aprovados.
create or replace function public.fn_apontamento_preparar_aprovacao()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
as $$
declare
  v_papel_criador text;
  v_editou boolean := false;
  v_exige_aprovacao boolean;
begin
  if tg_op = 'INSERT' then
    new.criado_por_user_id := coalesce(new.criado_por_user_id, auth.uid());
  else
    v_editou := row(
      new.data, new.horas, new.tipo_hora_id, new.fator_aplicado, new.descricao,
      new.hora_entrada_1, new.hora_saida_1, new.hora_entrada_2, new.hora_saida_2
    ) is distinct from row(
      old.data, old.horas, old.tipo_hora_id, old.fator_aplicado, old.descricao,
      old.hora_entrada_1, old.hora_saida_1, old.hora_entrada_2, old.hora_saida_2
    );

    -- Aprovar, rejeitar ou executar outra atualização técnica não recalcula o
    -- status. Somente um novo lançamento ou a edição das horas o faz.
    if not v_editou then
      return new;
    end if;
  end if;

  select upper(usuario_empresa.papel)
    into v_papel_criador
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = new.empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = new.criado_por_user_id
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  -- Papel desconhecido é mantido pendente por segurança.
  v_exige_aprovacao := coalesce(v_papel_criador, '') in ('APONTAMENTO_RH', 'APONTADOR')
    or v_papel_criador is null;

  if v_exige_aprovacao then
    new.status_aprovacao := 'pendente';
    new.pendente_em := case when tg_op = 'UPDATE' then now() else coalesce(new.pendente_em, now()) end;
    new.aprovado_por := null;
    new.aprovado_em := null;
    new.aprovado_automaticamente_em := null;
    new.rejeitado_em := null;
    new.motivo_devolucao := null;
  else
    new.status_aprovacao := 'aprovado';
    new.pendente_em := null;
    new.aprovado_por := new.criado_por_user_id;
    new.aprovado_em := now();
    new.aprovado_automaticamente_em := now();
    new.rejeitado_em := null;
    new.motivo_devolucao := null;
  end if;

  return new;
end;
$$;

create or replace function public.fn_apontamento_registrar_evento_aprovacao()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_evento text;
  v_motivo text;
begin
  if tg_op = 'INSERT' then
    v_evento := case
      when new.status_aprovacao = 'pendente' then 'pendente'
      when new.gerado_por_hh then 'aprovado_hh'
      when new.aprovado_automaticamente_em is not null then 'aprovado_automaticamente'
      else 'aprovado'
    end;
  elsif old.status_aprovacao is distinct from new.status_aprovacao then
    v_evento := case new.status_aprovacao
      when 'pendente' then 'pendente'
      when 'aprovado' then case when new.aprovado_automaticamente_em is not null then 'aprovado_automaticamente' else 'aprovado' end
      when 'rejeitado' then 'rejeitado'
    end;
  else
    return new;
  end if;

  v_motivo := case when v_evento = 'rejeitado' then new.motivo_devolucao else null end;
  insert into public.apontamentos_horas_aprovacao_eventos (
    tenant_id, empresa_id, apontamento_id, evento, realizado_por, motivo
  ) values (
    new.tenant_id, new.empresa_id, new.id, v_evento, auth.uid(), v_motivo
  );
  return new;
end;
$$;

do $$
begin
  if has_function_privilege('anon', 'public.app_buscar_materiais(text,text,integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.app_buscar_materiais(text,text,integer)', 'execute')
     or has_function_privilege('anon', 'public.app_resumo_materiais_os(integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.app_resumo_materiais_os(integer)', 'execute') then
    raise exception 'app_mobile_horas_materiais_installation_invalid';
  end if;
end;
$$;

comment on function public.app_buscar_materiais(text, text, integer) is
  'Busca materiais ativos por nome, código ou fabricante sem expor valores financeiros.';
comment on function public.app_resumo_materiais_os(integer) is
  'Resume materiais da OS e oculta o total monetário para APONTAMENTO_RH.';

notify pgrst, 'reload schema';

commit;
