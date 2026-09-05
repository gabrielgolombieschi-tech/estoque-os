begin;

-- Cancelamentos ficam fora da tabela operacional para que nenhum custo,
-- totalizador ou fechamento legado volte a considerar as horas canceladas.
-- O snapshot abaixo preserva o lançamento e toda a trilha da decisão.
create table if not exists public.apontamentos_horas_cancelamentos (
  id uuid primary key default gen_random_uuid(),
  apontamento_id uuid not null unique,
  tenant_id uuid not null,
  empresa_id uuid not null,
  os_id integer not null,
  numero_os text,
  cliente_nome text,
  colaborador_id uuid not null,
  colaborador_nome text not null,
  data date not null,
  horas numeric(6,2) not null,
  tipo_hora_id uuid,
  tipo_hora_nome text,
  fator_aplicado numeric(6,3),
  descricao text,
  status_anterior character varying(20) not null,
  status_aprovacao_anterior text not null,
  pendente_em timestamptz,
  aprovado_em timestamptz,
  rejeitado_em timestamptz,
  motivo_devolucao text,
  gerado_por_hh boolean not null,
  lancado_por_user_id uuid,
  criado_em timestamptz not null,
  cancelado_por_user_id uuid not null,
  cancelado_por_nome text not null,
  cancelamento_motivo text not null,
  cancelado_em timestamptz not null default now(),
  dados_apontamento jsonb not null,
  constraint chk_apontamentos_horas_cancelamentos_motivo
    check (char_length(btrim(cancelamento_motivo)) between 5 and 500)
);

create index if not exists idx_apontamentos_horas_cancelamentos_os
  on public.apontamentos_horas_cancelamentos
    (tenant_id, empresa_id, os_id, data desc, cancelado_em desc);

alter table public.apontamentos_horas_cancelamentos enable row level security;

revoke all on table public.apontamentos_horas_cancelamentos
  from public, anon, authenticated;

drop trigger if exists trg_apontamentos_horas_cancelamentos_audit
  on public.apontamentos_horas_cancelamentos;
create trigger trg_apontamentos_horas_cancelamentos_audit
after insert on public.apontamentos_horas_cancelamentos
for each row execute function public.audit_trigger();

comment on table public.apontamentos_horas_cancelamentos is
  'Histórico imutável dos apontamentos cancelados, com snapshot do lançamento, motivo e usuário responsável pelo cancelamento.';

comment on column public.apontamentos_horas_cancelamentos.dados_apontamento is
  'Snapshot JSON do apontamento original e dos eventos de aprovação existentes antes do cancelamento.';

-- A nova notificação pode ser controlada separadamente pelo usuário.
alter table public.app_notificacoes
  drop constraint if exists chk_app_notificacoes_tipo;
alter table public.app_notificacoes
  add constraint chk_app_notificacoes_tipo check (tipo in (
    'hora_pendente',
    'hora_aprovada_automaticamente',
    'hora_rejeitada',
    'hora_cancelada',
    'os_concluida',
    'os_faturada',
    'os_concluida_garantia',
    'material_lancado',
    'os_reaberta'
  ));

alter table public.app_notificacoes_preferencias
  drop constraint if exists chk_app_notificacoes_preferencias_tipo;
alter table public.app_notificacoes_preferencias
  add constraint chk_app_notificacoes_preferencias_tipo check (tipo in (
    'hora_pendente',
    'hora_aprovada_automaticamente',
    'hora_rejeitada',
    'hora_cancelada',
    'os_concluida',
    'os_faturada',
    'os_concluida_garantia',
    'material_lancado',
    'os_reaberta'
  ));

create or replace function public.app_criar_notificacao(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_tipo text,
  p_titulo text,
  p_corpo text,
  p_dados jsonb default '{}'::jsonb,
  p_agrupamento_chave text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_id uuid;
  v_quantidade integer;
  v_titulo text;
  v_corpo text;
begin
  if p_usuario_id is null
     or p_tenant_id is null
     or p_empresa_id is null
     or p_tipo not in (
       'hora_pendente', 'hora_aprovada_automaticamente', 'hora_rejeitada',
       'hora_cancelada', 'os_concluida', 'os_faturada',
       'os_concluida_garantia', 'material_lancado', 'os_reaberta'
     ) then
    return null;
  end if;

  if not exists (
    select 1
    from public.empresa_memberships as membership
    where membership.tenant_id = p_tenant_id
      and membership.empresa_id = p_empresa_id
      and membership.user_id = p_usuario_id
      and membership.status = 'active'
  ) then
    return null;
  end if;

  if exists (
    select 1
    from public.app_notificacoes_preferencias as preferencia
    where preferencia.tenant_id = p_tenant_id
      and preferencia.empresa_id = p_empresa_id
      and preferencia.usuario_id = p_usuario_id
      and preferencia.tipo = p_tipo
      and not preferencia.habilitada
  ) then
    return null;
  end if;

  if p_agrupamento_chave is not null then
    update public.app_notificacoes as notificacao
       set quantidade = notificacao.quantidade + 1,
           atualizado_em = now(),
           dados = coalesce(p_dados, '{}'::jsonb) || jsonb_build_object('agrupada', true)
     where notificacao.tenant_id = p_tenant_id
       and notificacao.empresa_id = p_empresa_id
       and notificacao.usuario_id = p_usuario_id
       and notificacao.tipo = p_tipo
       and notificacao.agrupamento_chave = p_agrupamento_chave
       and notificacao.lida_em is null
     returning notificacao.id, notificacao.quantidade
      into v_id, v_quantidade;

    if found then
      v_titulo := case p_tipo
        when 'hora_pendente' then format('%s horas pendentes de aprovação', v_quantidade)
        when 'hora_cancelada' then format('%s apontamentos cancelados', v_quantidade)
        when 'material_lancado' then format('%s materiais lançados em OS', v_quantidade)
        when 'os_concluida' then format('%s OS concluídas aguardando faturamento', v_quantidade)
        when 'os_faturada' then format('%s OS faturadas', v_quantidade)
        when 'os_concluida_garantia' then format('%s atendimentos de garantia concluídos', v_quantidade)
        when 'os_reaberta' then format('%s OS reabertas', v_quantidade)
        else format('%s novas notificações', v_quantidade)
      end;
      v_corpo := 'Abra a central de notificações para ver os detalhes.';

      update public.app_notificacoes
         set titulo = v_titulo,
             corpo = v_corpo,
             dados = dados || jsonb_build_object(
               'url', '/notificacoes',
               'quantidade', v_quantidade
             )
       where id = v_id;

      update public.app_notificacoes_push_entregas
         set status = 'pendente',
             tentativas = 0,
             erro = null,
             enviado_em = null,
             atualizado_em = now()
       where notificacao_id = v_id;

      return v_id;
    end if;
  end if;

  insert into public.app_notificacoes (
    tenant_id,
    empresa_id,
    usuario_id,
    tipo,
    titulo,
    corpo,
    dados,
    agrupamento_chave
  ) values (
    p_tenant_id,
    p_empresa_id,
    p_usuario_id,
    p_tipo,
    p_titulo,
    p_corpo,
    coalesce(p_dados, '{}'::jsonb),
    p_agrupamento_chave
  )
  returning id into v_id;

  insert into public.app_notificacoes_push_entregas (
    notificacao_id,
    dispositivo_id
  )
  select v_id, dispositivo.id
  from public.app_dispositivos_push as dispositivo
  where dispositivo.tenant_id = p_tenant_id
    and dispositivo.empresa_id = p_empresa_id
    and dispositivo.usuario_id = p_usuario_id
    and dispositivo.ativo;

  return v_id;
end;
$$;

create or replace function public.app_definir_preferencia_notificacao(
  p_tipo text,
  p_habilitada boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
begin
  if not public.app_notificacao_contexto_valido() then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if p_tipo not in (
    'hora_pendente', 'hora_aprovada_automaticamente', 'hora_rejeitada',
    'hora_cancelada', 'os_concluida', 'os_faturada',
    'os_concluida_garantia', 'material_lancado', 'os_reaberta'
  ) then
    raise exception 'Tipo de notificação inválido.';
  end if;

  insert into public.app_notificacoes_preferencias (
    tenant_id,
    empresa_id,
    usuario_id,
    tipo,
    habilitada
  ) values (
    public.current_tenant_id(),
    public.current_empresa_id(),
    auth.uid(),
    p_tipo,
    p_habilitada
  )
  on conflict (tenant_id, empresa_id, usuario_id, tipo) do update
    set habilitada = excluded.habilitada,
        atualizado_em = now();
end;
$$;

create or replace function public.app_listar_preferencias_notificacoes()
returns table (tipo text, habilitada boolean)
language sql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
  with tipos(tipo) as (
    values
      ('hora_pendente'::text),
      ('hora_aprovada_automaticamente'::text),
      ('hora_rejeitada'::text),
      ('hora_cancelada'::text),
      ('os_concluida'::text),
      ('os_faturada'::text),
      ('os_concluida_garantia'::text),
      ('material_lancado'::text),
      ('os_reaberta'::text)
  )
  select tipos.tipo, coalesce(preferencia.habilitada, true)
  from tipos
  left join public.app_notificacoes_preferencias as preferencia
    on preferencia.tenant_id = public.current_tenant_id()
   and preferencia.empresa_id = public.current_empresa_id()
   and preferencia.usuario_id = auth.uid()
   and preferencia.tipo = tipos.tipo
  where public.app_notificacao_contexto_valido()
  order by tipos.tipo;
$$;

create or replace function public.app_cancelar_apontamento(
  p_apontamento_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_cancelado_por_nome text;
  v_apontamento public.apontamentos_horas%rowtype;
  v_numero_os text;
  v_cliente_nome text;
  v_colaborador_nome text;
  v_tipo_hora_nome text;
  v_lancado_por_user_id uuid;
  v_eventos_aprovacao jsonb := '[]'::jsonb;
  v_notificacao_id uuid;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_horas_texto text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select upper(usuario_empresa.papel::text),
         coalesce(
           nullif(btrim(usuario.nome), ''),
           nullif(btrim(usuario.email), ''),
           'Usuário não identificado'
         )
    into v_papel, v_cancelado_por_nome
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

  if v_papel not in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', 'Somente Coordenação, Diretor ou Admin pode cancelar apontamentos.'
      ))
    );
  end if;

  if v_motivo is null or char_length(v_motivo) < 5 then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'motivo',
        'mensagem', 'Informe o motivo do cancelamento com pelo menos 5 caracteres.'
      ))
    );
  end if;

  if char_length(v_motivo) > 500 then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'motivo',
        'mensagem', 'O motivo do cancelamento deve ter no máximo 500 caracteres.'
      ))
    );
  end if;

  select apontamento.*
    into v_apontamento
  from public.apontamentos_horas as apontamento
  where apontamento.id = p_apontamento_id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
  for update;

  if not found then
    if exists (
      select 1
      from public.apontamentos_horas_cancelamentos as cancelamento
      where cancelamento.apontamento_id = p_apontamento_id
        and cancelamento.tenant_id = v_tenant_id
        and cancelamento.empresa_id = v_empresa_id
    ) then
      return jsonb_build_object(
        'sucesso', true,
        'gravados', 0,
        'ja_cancelado', true,
        'avisos', '[]'::jsonb,
        'erros', '[]'::jsonb
      );
    end if;

    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'apontamento',
        'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.'
      ))
    );
  end if;

  perform public.assert_documento_operacional_os(v_apontamento.os_id);

  if coalesce(v_apontamento.gerado_por_hh, false) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'hh',
        'mensagem', 'Este apontamento é um espelho de HH e deve ser corrigido no módulo HH.'
      ))
    );
  end if;

  if lower(coalesce(v_apontamento.status, '')) = 'fechado' then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'status',
        'mensagem', 'Este apontamento está fechado e não pode ser cancelado.'
      ))
    );
  end if;

  if exists (
    select 1
    from public.competencias as competencia
    where competencia.tenant_id = v_tenant_id
      and competencia.empresa_id = v_empresa_id
      and competencia.ano = extract(year from v_apontamento.data)::integer
      and competencia.mes = extract(month from v_apontamento.data)::integer
      and competencia.status = 'fechada'
  ) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'competencia',
        'mensagem', format(
          'A competência %s está fechada e este apontamento não pode ser cancelado.',
          to_char(v_apontamento.data, 'MM/YYYY')
        )
      ))
    );
  end if;

  select
    coalesce(nullif(btrim(ordem.numero_os), ''), ordem.os_num::text, ordem.id::text),
    ordem.cliente_nome,
    colaborador.nome,
    tipo_hora.descricao,
    coalesce(v_apontamento.criado_por_user_id, colaborador.user_id)
    into
      v_numero_os,
      v_cliente_nome,
      v_colaborador_nome,
      v_tipo_hora_nome,
      v_lancado_por_user_id
  from public.ordens_servico as ordem
  join public.colaboradores as colaborador
    on colaborador.id = v_apontamento.colaborador_id
   and colaborador.tenant_id = v_tenant_id
   and colaborador.empresa_id = v_empresa_id
  left join public.tipos_horas as tipo_hora
    on tipo_hora.id = v_apontamento.tipo_hora_id
   and tipo_hora.tenant_id = v_tenant_id
  where ordem.id = v_apontamento.os_id
    and ordem.tenant_id = v_tenant_id
    and ordem.empresa_id = v_empresa_id;

  if not found then
    raise exception 'Não foi possível localizar a OS e o colaborador do apontamento no contexto atual.';
  end if;

  select coalesce(
           jsonb_agg(to_jsonb(evento) order by evento.criado_em),
           '[]'::jsonb
         )
    into v_eventos_aprovacao
  from public.apontamentos_horas_aprovacao_eventos as evento
  where evento.apontamento_id = v_apontamento.id
    and evento.tenant_id = v_tenant_id
    and evento.empresa_id = v_empresa_id;

  insert into public.apontamentos_horas_cancelamentos (
    apontamento_id,
    tenant_id,
    empresa_id,
    os_id,
    numero_os,
    cliente_nome,
    colaborador_id,
    colaborador_nome,
    data,
    horas,
    tipo_hora_id,
    tipo_hora_nome,
    fator_aplicado,
    descricao,
    status_anterior,
    status_aprovacao_anterior,
    pendente_em,
    aprovado_em,
    rejeitado_em,
    motivo_devolucao,
    gerado_por_hh,
    lancado_por_user_id,
    criado_em,
    cancelado_por_user_id,
    cancelado_por_nome,
    cancelamento_motivo,
    dados_apontamento
  ) values (
    v_apontamento.id,
    v_apontamento.tenant_id,
    v_apontamento.empresa_id,
    v_apontamento.os_id,
    v_numero_os,
    v_cliente_nome,
    v_apontamento.colaborador_id,
    v_colaborador_nome,
    v_apontamento.data,
    v_apontamento.horas,
    v_apontamento.tipo_hora_id,
    v_tipo_hora_nome,
    v_apontamento.fator_aplicado,
    v_apontamento.descricao,
    v_apontamento.status,
    v_apontamento.status_aprovacao,
    v_apontamento.pendente_em,
    v_apontamento.aprovado_em,
    v_apontamento.rejeitado_em,
    v_apontamento.motivo_devolucao,
    v_apontamento.gerado_por_hh,
    v_lancado_por_user_id,
    v_apontamento.criado_em,
    v_auth_uid,
    v_cancelado_por_nome,
    v_motivo,
    to_jsonb(v_apontamento) || jsonb_build_object(
      'eventos_aprovacao', v_eventos_aprovacao
    )
  );

  delete from public.apontamentos_horas as apontamento
  where apontamento.id = v_apontamento.id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id;

  if not found then
    raise exception 'O apontamento mudou durante o cancelamento. Atualize a tela e tente novamente.';
  end if;

  v_horas_texto := replace(v_apontamento.horas::text, '.', ',');

  v_notificacao_id := public.app_criar_notificacao(
    v_tenant_id,
    v_empresa_id,
    v_lancado_por_user_id,
    'hora_cancelada',
    'Apontamento cancelado',
    format(
      '%s h de %s na OS %s foram canceladas por %s. Motivo: %s',
      v_horas_texto,
      to_char(v_apontamento.data, 'DD/MM/YYYY'),
      v_numero_os,
      v_cancelado_por_nome,
      v_motivo
    ),
    jsonb_build_object(
      'url', '/os/' || v_apontamento.os_id::text,
      'os_id', v_apontamento.os_id,
      'numero_os', v_numero_os,
      'apontamento_id', v_apontamento.id,
      'cancelado_por_user_id', v_auth_uid,
      'cancelado_por_nome', v_cancelado_por_nome,
      'cancelamento_motivo', v_motivo
    ),
    'hora_cancelada:' || v_apontamento.id::text
  );

  return jsonb_build_object(
    'sucesso', true,
    'gravados', 1,
    'avisos', '[]'::jsonb,
    'erros', '[]'::jsonb,
    'notificacao_enviada', v_notificacao_id is not null,
    'cancelado_por_nome', v_cancelado_por_nome
  );
end;
$$;

-- Versão aditiva: clientes antigos continuam usando a assinatura anterior;
-- o app novo recebe também os metadados do cancelamento e a permissão calculada.
create or replace function public.app_listar_apontamentos_os_fluxo_v2(
  p_os_id integer
)
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
  criado_em timestamptz,
  cancelado_em timestamptz,
  cancelado_por_user_id uuid,
  cancelado_por_nome text,
  cancelamento_motivo text,
  pode_cancelar boolean
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
  v_colaborador_id uuid;
  v_papel text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  perform public.assert_documento_operacional_os(p_os_id);

  select upper(usuario_empresa.papel::text)
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
    raise exception 'Não foi possível identificar o papel deste usuário na empresa.';
  end if;

  if v_papel = 'APONTAMENTO_RH' then
    select colaborador.id
      into v_colaborador_id
    from public.colaboradores as colaborador
    where colaborador.user_id = v_auth_uid
      and colaborador.tenant_id = v_tenant_id
      and colaborador.empresa_id = v_empresa_id
      and colaborador.ativo is true;

    if v_colaborador_id is null then
      raise exception 'Seu usuário de apontamento não está vinculado a um colaborador ativo nesta empresa.';
    end if;
  end if;

  return query
  select resultado.*
  from (
    select
      apontamento.id,
      apontamento.os_id,
      ordem.numero_os,
      ordem.cliente_nome,
      apontamento.colaborador_id,
      colaborador.nome as nome_colaborador,
      apontamento.data,
      apontamento.horas,
      apontamento.tipo_hora_id,
      tipo_hora.descricao as nome_tipo_hora,
      apontamento.descricao,
      apontamento.status,
      apontamento.status_aprovacao,
      apontamento.pendente_em,
      apontamento.aprovado_em,
      apontamento.rejeitado_em,
      apontamento.gerado_por_hh,
      apontamento.motivo_devolucao,
      apontamento.criado_em,
      null::timestamptz as cancelado_em,
      null::uuid as cancelado_por_user_id,
      null::text as cancelado_por_nome,
      null::text as cancelamento_motivo,
      (
        v_papel in ('ADMIN', 'DIRETOR', 'COORDENACAO')
        and not coalesce(apontamento.gerado_por_hh, false)
        and lower(coalesce(apontamento.status, '')) <> 'fechado'
        and not exists (
          select 1
          from public.competencias as competencia
          where competencia.tenant_id = apontamento.tenant_id
            and competencia.empresa_id = apontamento.empresa_id
            and competencia.ano = extract(year from apontamento.data)::integer
            and competencia.mes = extract(month from apontamento.data)::integer
            and competencia.status = 'fechada'
        )
      ) as pode_cancelar
    from public.apontamentos_horas as apontamento
    join public.ordens_servico as ordem
      on ordem.id = apontamento.os_id
     and ordem.tenant_id = apontamento.tenant_id
     and ordem.empresa_id = apontamento.empresa_id
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
    left join public.tipos_horas as tipo_hora
      on tipo_hora.id = apontamento.tipo_hora_id
     and tipo_hora.tenant_id = v_tenant_id
    where apontamento.os_id = p_os_id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and (
        v_papel <> 'APONTAMENTO_RH'
        or apontamento.colaborador_id = v_colaborador_id
      )

    union all

    select
      cancelamento.apontamento_id as id,
      cancelamento.os_id,
      cancelamento.numero_os::character varying,
      cancelamento.cliente_nome::character varying,
      cancelamento.colaborador_id,
      cancelamento.colaborador_nome::character varying as nome_colaborador,
      cancelamento.data,
      cancelamento.horas::numeric,
      cancelamento.tipo_hora_id,
      cancelamento.tipo_hora_nome::character varying as nome_tipo_hora,
      cancelamento.descricao,
      'cancelado'::character varying as status,
      'cancelado'::text as status_aprovacao,
      cancelamento.pendente_em,
      cancelamento.aprovado_em,
      cancelamento.rejeitado_em,
      cancelamento.gerado_por_hh,
      cancelamento.motivo_devolucao,
      cancelamento.criado_em,
      cancelamento.cancelado_em,
      cancelamento.cancelado_por_user_id,
      cancelamento.cancelado_por_nome,
      cancelamento.cancelamento_motivo,
      false as pode_cancelar
    from public.apontamentos_horas_cancelamentos as cancelamento
    where cancelamento.os_id = p_os_id
      and cancelamento.tenant_id = v_tenant_id
      and cancelamento.empresa_id = v_empresa_id
      and (
        v_papel <> 'APONTAMENTO_RH'
        or cancelamento.colaborador_id = v_colaborador_id
      )
  ) as resultado
  order by resultado.data desc, resultado.criado_em desc, resultado.id desc;
end;
$$;

-- Desativa a exclusão física legada. O cancelamento novo exige papel de gestão
-- e motivo, além de registrar/notificar a operação.
create or replace function public.app_excluir_apontamento(
  p_apontamento_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
  select jsonb_build_object(
    'sucesso', false,
    'gravados', 0,
    'avisos', '[]'::jsonb,
    'erros', jsonb_build_array(jsonb_build_object(
      'tipo', 'cancelamento_obrigatorio',
      'mensagem', 'A exclusão direta foi desativada. Use Cancelar apontamento e informe o motivo.'
    ))
  );
$$;

revoke all on function public.app_criar_notificacao(
  uuid, uuid, uuid, text, text, text, jsonb, text
) from public, anon, authenticated;
grant execute on function public.app_criar_notificacao(
  uuid, uuid, uuid, text, text, text, jsonb, text
) to service_role;

revoke all on function public.app_definir_preferencia_notificacao(text, boolean)
  from public, anon;
grant execute on function public.app_definir_preferencia_notificacao(text, boolean)
  to authenticated;

revoke all on function public.app_listar_preferencias_notificacoes()
  from public, anon;
grant execute on function public.app_listar_preferencias_notificacoes()
  to authenticated;

revoke all on function public.app_cancelar_apontamento(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.app_cancelar_apontamento(uuid, text)
  to authenticated;

revoke all on function public.app_listar_apontamentos_os_fluxo_v2(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.app_listar_apontamentos_os_fluxo_v2(integer)
  to authenticated;

revoke all on function public.app_excluir_apontamento(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.app_excluir_apontamento(uuid)
  to authenticated;

comment on function public.app_cancelar_apontamento(uuid, text) is
  'Cancela um apontamento com snapshot auditável; permitido somente a Coordenação, Diretor e Admin no tenant/empresa ativos.';

comment on function public.app_listar_apontamentos_os_fluxo_v2(integer) is
  'Lista apontamentos ativos e cancelados da OS, com metadados de auditoria e permissão de cancelamento.';

notify pgrst, 'reload schema';

commit;
