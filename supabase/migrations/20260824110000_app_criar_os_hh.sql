-- Criação de OS HH pelo app móvel, sem expor dados financeiros.

create or replace function public.app_listar_clientes_hh()
returns table (
  id integer,
  nome character varying
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar clientes HH.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  return query
  select cliente.id, cliente.nome
  from public.clientes as cliente
  where cliente.tenant_id = v_tenant_id
    and cliente.empresa_id = v_empresa_id
    and cliente.ativo is true
    and cliente.habilita_hh is true
  order by cliente.nome;
end;
$$;

create or replace function public.app_criar_os_hh(
  p_cliente_id integer,
  p_descricao_servico text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_papel_empresa text;
  v_cliente_nome character varying;
  v_cliente_ativo boolean;
  v_cliente_habilita_hh boolean;
  v_os_id integer;
  v_os_num bigint;
  v_numero_os text;
  v_criado_por text;
begin
  if v_auth_uid is null then
    return jsonb_build_object(
      'sucesso', false,
      'os_id', null,
      'numero_os', null,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'autenticacao', 'mensagem', 'Autenticação obrigatória para criar OS HH.'))
    );
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    return jsonb_build_object(
      'sucesso', false,
      'os_id', null,
      'numero_os', null,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'contexto', 'mensagem', 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.'))
    );
  end if;

  select usuario_empresa.papel
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
    return jsonb_build_object(
      'sucesso', false,
      'os_id', null,
      'numero_os', null,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'permissao', 'mensagem', 'Não foi possível identificar seu papel na empresa atual.'))
    );
  end if;

  if upper(v_papel_empresa) = 'APONTADOR' then
    return jsonb_build_object(
      'sucesso', false,
      'os_id', null,
      'numero_os', null,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'permissao', 'mensagem', 'O papel APONTADOR não pode criar OS.'))
    );
  end if;

  select cliente.nome, cliente.ativo, cliente.habilita_hh
    into v_cliente_nome, v_cliente_ativo, v_cliente_habilita_hh
  from public.clientes as cliente
  where cliente.id = p_cliente_id
    and cliente.tenant_id = v_tenant_id
    and cliente.empresa_id = v_empresa_id;

  if v_cliente_nome is null then
    return jsonb_build_object(
      'sucesso', false,
      'os_id', null,
      'numero_os', null,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'cliente', 'mensagem', 'O cliente informado não existe ou não pertence à empresa atual.'))
    );
  end if;

  if coalesce(v_cliente_ativo, false) is false then
    return jsonb_build_object(
      'sucesso', false,
      'os_id', null,
      'numero_os', null,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'cliente_inativo', 'mensagem', 'O cliente informado está inativo.'))
    );
  end if;

  if coalesce(v_cliente_habilita_hh, false) is false then
    return jsonb_build_object(
      'sucesso', false,
      'os_id', null,
      'numero_os', null,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'cliente_hh', 'mensagem', 'O cliente informado não está habilitado para HH.'))
    );
  end if;

  v_os_num := nextval('public.ordens_servico_os_num_seq');
  v_numero_os := v_os_num::text;
  v_criado_por := coalesce(nullif(auth.jwt() ->> 'email', ''), v_auth_uid::text);

  begin
    insert into public.ordens_servico (
      tenant_id,
      empresa_id,
      os_num,
      numero_os,
      cliente_id,
      cliente_nome,
      descricao_servico,
      tipo_pedido,
      orcado,
      tem_gestao,
      usa_relatorio_hh,
      is_fiado,
      status,
      criado_por,
      responsavel_aprovacao_id
    ) values (
      v_tenant_id,
      v_empresa_id,
      v_os_num,
      v_numero_os,
      p_cliente_id,
      v_cliente_nome,
      nullif(upper(btrim(p_descricao_servico)), ''),
      'servico',
      0,
      false,
      true,
      false,
      'em_andamento',
      v_criado_por,
      v_auth_uid
    )
    returning id into v_os_id;
  exception
    when unique_violation then
      return jsonb_build_object(
        'sucesso', false,
        'os_id', null,
        'numero_os', null,
        'avisos', '[]'::jsonb,
        'erros', jsonb_build_array(jsonb_build_object('tipo', 'numeracao', 'mensagem', 'Não foi possível reservar uma numeração única para a OS. Tente novamente.'))
      );
  end;

  return jsonb_build_object(
    'sucesso', true,
    'os_id', v_os_id,
    'numero_os', v_numero_os,
    'avisos', '[]'::jsonb,
    'erros', '[]'::jsonb
  );
end;
$$;

revoke all on function public.app_listar_clientes_hh() from public, anon, authenticated, service_role;
revoke all on function public.app_criar_os_hh(integer, text) from public, anon, authenticated, service_role;

grant execute on function public.app_listar_clientes_hh() to authenticated;
grant execute on function public.app_criar_os_hh(integer, text) to authenticated;
