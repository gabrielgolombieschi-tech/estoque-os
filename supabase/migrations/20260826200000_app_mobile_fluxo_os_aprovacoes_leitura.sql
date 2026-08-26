-- Leituras aditivas para as telas mobile das frentes 01 (fluxo da OS) e 03
-- (aprovação de horas). Nenhuma tabela, dado ou RPC de escrita é alterado.

create or replace function public.app_listar_os_fluxo(
  p_status_fluxo text default 'em_andamento',
  p_busca text default null
)
returns table (
  id integer,
  numero_os character varying,
  os_num bigint,
  cliente_nome character varying,
  descricao_servico text,
  status_legado character varying,
  status_fluxo text,
  usa_relatorio_hh boolean,
  total_horas numeric,
  responsavel_nome text,
  situacao_margem text,
  sou_responsavel boolean,
  pendencias_aprovacao integer,
  garantia_motivo text,
  faturado_em timestamptz,
  faturada_presumida_legado boolean,
  pode_concluir boolean,
  pode_faturar boolean,
  pode_reabrir_garantia boolean,
  pode_concluir_garantia boolean
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
  v_status text := lower(coalesce(nullif(btrim(p_status_fluxo), ''), 'em_andamento'));
  v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if v_status not in ('em_andamento', 'concluida', 'faturada') then
    raise exception 'Filtro de status inválido.';
  end if;

  select ue.papel into v_papel
  from a.usuario u
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = v_auth_uid and u.ativo and u.deleted_at is null
    and ue.empresa_id = v_empresa_id and ue.ativo and ue.deleted_at is null
  limit 1;

  return query
  select
    base.id,
    base.numero_os,
    base.os_num,
    base.cliente_nome,
    base.descricao_servico,
    base.status,
    os.status_fluxo,
    base.usa_relatorio_hh,
    base.total_horas,
    base.responsavel_nome,
    base.situacao_margem,
    base.sou_responsavel,
    coalesce(pendencias.quantidade, 0)::integer,
    os.garantia_motivo,
    os.faturado_em,
    os.faturada_presumida_legado,
    upper(coalesce(v_papel, '')) in ('ADMIN', 'DIRETOR', 'COORDENACAO'),
    upper(coalesce(v_papel, '')) = 'FINANCEIRO',
    upper(coalesce(v_papel, '')) in ('COORDENACAO', 'FINANCEIRO'),
    upper(coalesce(v_papel, '')) = 'COORDENACAO'
  from public.app_listar_os(true, p_busca) as base
  join public.ordens_servico as os
    on os.id = base.id
   and os.tenant_id = v_tenant_id
   and os.empresa_id = v_empresa_id
  left join lateral (
    select count(*)::integer as quantidade
    from public.apontamentos_horas as ah
    where ah.os_id = os.id
      and ah.tenant_id = v_tenant_id
      and ah.empresa_id = v_empresa_id
      and ah.status_aprovacao = 'pendente'
  ) as pendencias on true
  where case v_status
    when 'em_andamento' then os.status_fluxo in ('em_andamento', 'em_andamento_garantia')
    when 'concluida' then os.status_fluxo in ('concluida', 'concluida_garantia')
    when 'faturada' then os.status_fluxo = 'faturada'
  end
  order by os.data_abertura desc nulls last, os.id desc;
end;
$$;

create or replace function public.app_listar_apontamentos_os_fluxo(p_os_id integer)
returns table (
  id uuid,
  os_id integer,
  numero_os character varying,
  cliente_nome character varying,
  colaborador_id uuid,
  nome_colaborador character varying,
  data date,
  horas numeric,
  tipo_hora_id uuid,
  nome_tipo_hora character varying,
  descricao text,
  status character varying,
  status_aprovacao text,
  pendente_em timestamptz,
  aprovado_em timestamptz,
  rejeitado_em timestamptz,
  gerado_por_hh boolean,
  motivo_devolucao text,
  criado_em timestamptz
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
  v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select c.id into v_colaborador_id
  from public.colaboradores c
  where c.user_id = v_auth_uid and c.tenant_id = v_tenant_id and c.empresa_id = v_empresa_id and c.ativo;
  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  select ue.papel into v_papel
  from a.usuario u
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = v_auth_uid and u.ativo and u.deleted_at is null
    and ue.empresa_id = v_empresa_id and ue.ativo and ue.deleted_at is null
  limit 1;
  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa.';
  end if;

  return query
  select ah.id, ah.os_id, os.numero_os, os.cliente_nome, ah.colaborador_id, c.nome,
         ah.data, ah.horas, ah.tipo_hora_id, th.descricao, ah.descricao, ah.status,
         ah.status_aprovacao, ah.pendente_em, ah.aprovado_em, ah.rejeitado_em,
         ah.gerado_por_hh, ah.motivo_devolucao, ah.criado_em
  from public.apontamentos_horas ah
  join public.ordens_servico os on os.id = ah.os_id and os.tenant_id = ah.tenant_id and os.empresa_id = ah.empresa_id
  join public.colaboradores c on c.id = ah.colaborador_id and c.tenant_id = v_tenant_id and c.empresa_id = v_empresa_id
  left join public.tipos_horas th on th.id = ah.tipo_hora_id and th.tenant_id = v_tenant_id
  where ah.os_id = p_os_id
    and ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id
    and (upper(v_papel) <> 'APONTADOR' or ah.colaborador_id = v_colaborador_id)
  order by ah.data desc, ah.criado_em desc, ah.id desc;
end;
$$;

create or replace function public.app_listar_aprovacoes_pendentes()
returns table (
  id uuid,
  os_id integer,
  numero_os character varying,
  cliente_nome character varying,
  colaborador_id uuid,
  nome_colaborador character varying,
  data date,
  horas numeric,
  nome_tipo_hora character varying,
  descricao text,
  pendente_em timestamptz
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
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  return query
  select ah.id, ah.os_id, os.numero_os, os.cliente_nome, ah.colaborador_id, c.nome,
         ah.data, ah.horas, th.descricao, ah.descricao, ah.pendente_em
  from public.apontamentos_horas ah
  join public.ordens_servico os on os.id = ah.os_id and os.tenant_id = ah.tenant_id and os.empresa_id = ah.empresa_id
  join public.colaboradores c on c.id = ah.colaborador_id and c.tenant_id = v_tenant_id and c.empresa_id = v_empresa_id
  left join public.tipos_horas th on th.id = ah.tipo_hora_id and th.tenant_id = v_tenant_id
  where ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id
    and ah.status_aprovacao = 'pendente'
    and os.responsavel_aprovacao_id = v_auth_uid
  order by ah.pendente_em asc nulls last, ah.data asc, ah.criado_em asc;
end;
$$;

create or replace function public.app_contar_aprovacoes_pendentes()
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
  select count(*)::integer from public.app_listar_aprovacoes_pendentes();
$$;

revoke all on function public.app_listar_os_fluxo(text, text) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_apontamentos_os_fluxo(integer) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_aprovacoes_pendentes() from public, anon, authenticated, service_role;
revoke all on function public.app_contar_aprovacoes_pendentes() from public, anon, authenticated, service_role;

grant execute on function public.app_listar_os_fluxo(text, text) to authenticated;
grant execute on function public.app_listar_apontamentos_os_fluxo(integer) to authenticated;
grant execute on function public.app_listar_aprovacoes_pendentes() to authenticated;
grant execute on function public.app_contar_aprovacoes_pendentes() to authenticated;
