begin;

-- Frente 05: notificacoes do app. A tabela de notificacoes e o dispositivo
-- sempre carregam tenant/empresa para que uma conta compartilhada nao misture
-- alertas de empresas diferentes.
create table if not exists public.app_notificacoes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null,
  titulo text not null,
  corpo text not null,
  dados jsonb not null default '{}'::jsonb,
  agrupamento_chave text,
  quantidade integer not null default 1 check (quantidade > 0),
  lida_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint chk_app_notificacoes_tipo check (tipo in (
    'hora_pendente',
    'hora_aprovada_automaticamente',
    'hora_rejeitada',
    'os_concluida',
    'os_faturada',
    'os_concluida_garantia',
    'material_lancado',
    'os_reaberta'
  ))
);

create table if not exists public.app_notificacoes_preferencias (
  tenant_id uuid not null,
  empresa_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null,
  habilitada boolean not null default true,
  atualizado_em timestamptz not null default now(),
  primary key (tenant_id, empresa_id, usuario_id, tipo),
  constraint chk_app_notificacoes_preferencias_tipo check (tipo in (
    'hora_pendente',
    'hora_aprovada_automaticamente',
    'hora_rejeitada',
    'os_concluida',
    'os_faturada',
    'os_concluida_garantia',
    'material_lancado',
    'os_reaberta'
  ))
);

create table if not exists public.app_dispositivos_push (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  expo_push_token text not null unique,
  plataforma text not null check (plataforma in ('ios', 'android')),
  ativo boolean not null default true,
  ultimo_acesso_em timestamptz not null default now(),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.app_notificacoes_push_entregas (
  id uuid primary key default gen_random_uuid(),
  notificacao_id uuid not null references public.app_notificacoes(id) on delete cascade,
  dispositivo_id uuid not null references public.app_dispositivos_push(id) on delete cascade,
  status text not null default 'pendente' check (status in ('pendente', 'enviando', 'enviada', 'falhou')),
  tentativas integer not null default 0 check (tentativas >= 0),
  erro text,
  enviado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (notificacao_id, dispositivo_id)
);

create index if not exists idx_app_notificacoes_usuario_nao_lidas
  on public.app_notificacoes (tenant_id, empresa_id, usuario_id, criado_em desc)
  where lida_em is null;
create unique index if not exists uq_app_notificacoes_agrupadas_nao_lidas
  on public.app_notificacoes (tenant_id, empresa_id, usuario_id, tipo, agrupamento_chave)
  where lida_em is null and agrupamento_chave is not null;
create index if not exists idx_app_dispositivos_push_usuario
  on public.app_dispositivos_push (tenant_id, empresa_id, usuario_id)
  where ativo;
create index if not exists idx_app_notificacoes_push_pendentes
  on public.app_notificacoes_push_entregas (status, criado_em)
  where status in ('pendente', 'falhou');

alter table public.app_notificacoes enable row level security;
alter table public.app_notificacoes_preferencias enable row level security;
alter table public.app_dispositivos_push enable row level security;
alter table public.app_notificacoes_push_entregas enable row level security;

-- A leitura/escrita do app ocorre apenas pelas RPCs abaixo. Assim o cliente
-- jamais escolhe tenant, empresa, usuario de destino ou estado da fila push.
create or replace function public.app_notificacao_contexto_valido()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  select auth.uid() is not null
    and public.current_tenant_id() is not null
    and public.current_empresa_id() is not null
    and public.has_active_empresa_access(public.current_tenant_id(), public.current_empresa_id());
$$;

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
       'os_concluida', 'os_faturada', 'os_concluida_garantia',
       'material_lancado', 'os_reaberta'
     ) then
    return null;
  end if;

  -- O destinatario precisa continuar ativo exatamente no contexto do evento.
  if not exists (
    select 1
    from public.empresa_memberships em
    where em.tenant_id = p_tenant_id
      and em.empresa_id = p_empresa_id
      and em.user_id = p_usuario_id
      and em.status = 'active'
  ) then
    return null;
  end if;

  if exists (
    select 1
    from public.app_notificacoes_preferencias pref
    where pref.tenant_id = p_tenant_id
      and pref.empresa_id = p_empresa_id
      and pref.usuario_id = p_usuario_id
      and pref.tipo = p_tipo
      and not pref.habilitada
  ) then
    return null;
  end if;

  if p_agrupamento_chave is not null then
    update public.app_notificacoes notificacao
       set quantidade = notificacao.quantidade + 1,
           atualizado_em = now(),
           dados = coalesce(p_dados, '{}'::jsonb) || jsonb_build_object('agrupada', true)
     where notificacao.tenant_id = p_tenant_id
       and notificacao.empresa_id = p_empresa_id
       and notificacao.usuario_id = p_usuario_id
       and notificacao.tipo = p_tipo
       and notificacao.agrupamento_chave = p_agrupamento_chave
       and notificacao.lida_em is null
     returning notificacao.id, notificacao.quantidade into v_id, v_quantidade;

    if found then
      v_titulo := case p_tipo
        when 'hora_pendente' then format('%s horas pendentes de aprovaçao', v_quantidade)
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
             dados = dados || jsonb_build_object('url', '/notificacoes', 'quantidade', v_quantidade)
       where id = v_id;

      -- Um novo evento precisa voltar para a fila mesmo se a versao anterior
      -- ja havia sido enviada ao mesmo aparelho.
      update public.app_notificacoes_push_entregas
         set status = 'pendente', tentativas = 0, erro = null, enviado_em = null, atualizado_em = now()
       where notificacao_id = v_id;
      return v_id;
    end if;
  end if;

  insert into public.app_notificacoes (
    tenant_id, empresa_id, usuario_id, tipo, titulo, corpo, dados, agrupamento_chave
  ) values (
    p_tenant_id, p_empresa_id, p_usuario_id, p_tipo, p_titulo, p_corpo,
    coalesce(p_dados, '{}'::jsonb), p_agrupamento_chave
  ) returning id into v_id;

  insert into public.app_notificacoes_push_entregas (notificacao_id, dispositivo_id)
  select v_id, dispositivo.id
  from public.app_dispositivos_push dispositivo
  where dispositivo.tenant_id = p_tenant_id
    and dispositivo.empresa_id = p_empresa_id
    and dispositivo.usuario_id = p_usuario_id
    and dispositivo.ativo;

  return v_id;
end;
$$;

create or replace function public.app_notificar_usuarios_por_papel(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_papeis text[],
  p_tipo text,
  p_titulo text,
  p_corpo text,
  p_dados jsonb,
  p_agrupamento_chave text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, a
set row_security = off
as $$
declare
  v_usuario_id uuid;
begin
  for v_usuario_id in
    select distinct usuario.auth_user_id
    from a.usuario usuario
    join a.usuario_empresa usuario_empresa on usuario_empresa.usuario_id = usuario.id
    join public.empresa_memberships membership
      on membership.user_id = usuario.auth_user_id
     and membership.tenant_id = p_tenant_id
     and membership.empresa_id = p_empresa_id
     and membership.status = 'active'
    where usuario_empresa.empresa_id = p_empresa_id
      and usuario.ativo
      and usuario.deleted_at is null
      and usuario_empresa.ativo
      and usuario_empresa.deleted_at is null
      and upper(usuario_empresa.papel::text) = any (p_papeis)
  loop
    perform public.app_criar_notificacao(
      p_tenant_id, p_empresa_id, v_usuario_id, p_tipo, p_titulo, p_corpo,
      p_dados, p_agrupamento_chave
    );
  end loop;
end;
$$;

create or replace function public.fn_app_notificar_apontamento_horas()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_responsavel uuid;
  v_destinatario uuid;
  v_os_numero text;
  v_dados jsonb;
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
    foreach v_destinatario in array array_remove(array[v_responsavel, new.criado_por_user_id], null)
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
$$;

drop trigger if exists trg_app_notificar_apontamento_horas on public.apontamentos_horas;
create trigger trg_app_notificar_apontamento_horas
after insert or update of status_aprovacao on public.apontamentos_horas
for each row execute function public.fn_app_notificar_apontamento_horas();

create or replace function public.fn_app_notificar_fluxo_os()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_numero_os text := coalesce(nullif(btrim(new.numero_os), ''), new.os_num::text, new.id::text);
  v_dados jsonb := jsonb_build_object('os_id', new.id, 'url', '/os/' || new.id::text);
begin
  if old.status_fluxo is not distinct from new.status_fluxo then
    return new;
  end if;

  if new.status_fluxo = 'concluida' then
    perform public.app_notificar_usuarios_por_papel(
      new.tenant_id, new.empresa_id, array['ADMIN', 'DIRETOR', 'FINANCEIRO'], 'os_concluida',
      'OS concluída', format('A OS %s está pronta para faturamento.', v_numero_os), v_dados, 'os_concluida'
    );
  elsif new.status_fluxo = 'faturada' then
    perform public.app_notificar_usuarios_por_papel(
      new.tenant_id, new.empresa_id, array['ADMIN', 'DIRETOR'], 'os_faturada',
      'OS faturada', format('A OS %s foi faturada.', v_numero_os), v_dados, 'os_faturada'
    );
    perform public.app_criar_notificacao(
      new.tenant_id, new.empresa_id, new.responsavel_aprovacao_id, 'os_faturada',
      'OS faturada', format('A OS %s foi faturada.', v_numero_os), v_dados, 'os_faturada'
    );
  elsif new.status_fluxo = 'concluida_garantia' then
    perform public.app_notificar_usuarios_por_papel(
      new.tenant_id, new.empresa_id, array['ADMIN', 'DIRETOR'], 'os_concluida_garantia',
      'Garantia concluída', format('O atendimento de garantia da OS %s foi concluído sem cobrança.', v_numero_os), v_dados, 'os_concluida_garantia'
    );
    perform public.app_criar_notificacao(
      new.tenant_id, new.empresa_id, new.responsavel_aprovacao_id, 'os_concluida_garantia',
      'Garantia concluída', format('O atendimento de garantia da OS %s foi concluído sem cobrança.', v_numero_os), v_dados, 'os_concluida_garantia'
    );
  elsif new.status_fluxo in ('em_andamento', 'em_andamento_garantia')
    and old.status_fluxo in ('concluida', 'faturada') then
    perform public.app_notificar_usuarios_por_papel(
      new.tenant_id, new.empresa_id, array['ADMIN', 'DIRETOR'], 'os_reaberta',
      'OS reaberta', format('A OS %s voltou para Em andamento.', v_numero_os), v_dados, 'os_reaberta'
    );
    perform public.app_criar_notificacao(
      new.tenant_id, new.empresa_id, new.responsavel_aprovacao_id, 'os_reaberta',
      'OS reaberta', format('A OS %s voltou para Em andamento.', v_numero_os), v_dados, 'os_reaberta'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_app_notificar_fluxo_os on public.ordens_servico;
create trigger trg_app_notificar_fluxo_os
after update of status_fluxo on public.ordens_servico
for each row execute function public.fn_app_notificar_fluxo_os();

create or replace function public.fn_app_notificar_material_lancado()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_responsavel uuid;
  v_numero_os text;
  v_url text;
begin
  -- A RPC do app grava esta origem; movimentacoes criadas pela web/importacao
  -- nao disparam a notificacao definida para o tecnico no mobile.
  if new.origem_os_id is null or new.tipo <> 'saida'
     or new.motivo not like 'Material lançado pelo app na OS %' then
    return new;
  end if;

  select os.responsavel_aprovacao_id,
         coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)
    into v_responsavel, v_numero_os
  from public.ordens_servico os
  where os.id = new.origem_os_id
    and os.tenant_id = new.tenant_id
    and os.empresa_id = new.empresa_id;

  v_url := '/os/' || new.origem_os_id::text || '/material';
  perform public.app_criar_notificacao(
    new.tenant_id, new.empresa_id, v_responsavel, 'material_lancado',
    'Material lançado na OS', format('Foi lançado material na OS %s.', v_numero_os),
    jsonb_build_object('os_id', new.origem_os_id, 'url', v_url), 'material_lancado'
  );
  return new;
end;
$$;

drop trigger if exists trg_app_notificar_material_lancado on public.movimentacoes;
create trigger trg_app_notificar_material_lancado
after insert on public.movimentacoes
for each row execute function public.fn_app_notificar_material_lancado();

create or replace function public.app_listar_preferencias_notificacoes()
returns table (tipo text, habilitada boolean)
language sql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
  with tipos(tipo) as (
    values
      ('hora_pendente'::text), ('hora_aprovada_automaticamente'::text), ('hora_rejeitada'::text),
      ('os_concluida'::text), ('os_faturada'::text), ('os_concluida_garantia'::text),
      ('material_lancado'::text), ('os_reaberta'::text)
  )
  select tipos.tipo, coalesce(pref.habilitada, true)
  from tipos
  left join public.app_notificacoes_preferencias pref
    on pref.tenant_id = public.current_tenant_id()
   and pref.empresa_id = public.current_empresa_id()
   and pref.usuario_id = auth.uid()
   and pref.tipo = tipos.tipo
  where public.app_notificacao_contexto_valido()
  order by tipos.tipo;
$$;

create or replace function public.app_definir_preferencia_notificacao(p_tipo text, p_habilitada boolean)
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
    'os_concluida', 'os_faturada', 'os_concluida_garantia', 'material_lancado', 'os_reaberta'
  ) then
    raise exception 'Tipo de notificação inválido.';
  end if;
  insert into public.app_notificacoes_preferencias (tenant_id, empresa_id, usuario_id, tipo, habilitada)
  values (public.current_tenant_id(), public.current_empresa_id(), auth.uid(), p_tipo, p_habilitada)
  on conflict (tenant_id, empresa_id, usuario_id, tipo) do update
    set habilitada = excluded.habilitada, atualizado_em = now();
end;
$$;

create or replace function public.app_registrar_dispositivo_push(p_expo_push_token text, p_plataforma text)
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
  if nullif(btrim(p_expo_push_token), '') is null
     or p_plataforma not in ('ios', 'android') then
    raise exception 'Dispositivo push inválido.';
  end if;

  insert into public.app_dispositivos_push (
    tenant_id, empresa_id, usuario_id, expo_push_token, plataforma, ativo, ultimo_acesso_em
  ) values (
    public.current_tenant_id(), public.current_empresa_id(), auth.uid(), btrim(p_expo_push_token), p_plataforma, true, now()
  )
  on conflict (expo_push_token) do update
    set tenant_id = excluded.tenant_id,
        empresa_id = excluded.empresa_id,
        usuario_id = excluded.usuario_id,
        plataforma = excluded.plataforma,
        ativo = true,
        ultimo_acesso_em = now(),
        atualizado_em = now();
end;
$$;

create or replace function public.app_desativar_dispositivo_push(p_expo_push_token text)
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
  update public.app_dispositivos_push
     set ativo = false, atualizado_em = now()
   where expo_push_token = nullif(btrim(p_expo_push_token), '')
     and tenant_id = public.current_tenant_id()
     and empresa_id = public.current_empresa_id()
     and usuario_id = auth.uid();
end;
$$;

create or replace function public.app_listar_notificacoes(p_limite integer default 50, p_antes_de timestamptz default null)
returns table (
  id uuid, tipo text, titulo text, corpo text, dados jsonb, quantidade integer,
  lida_em timestamptz, criado_em timestamptz
)
language sql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
  select n.id, n.tipo, n.titulo, n.corpo, n.dados, n.quantidade, n.lida_em, n.criado_em
  from public.app_notificacoes n
  where n.tenant_id = public.current_tenant_id()
    and n.empresa_id = public.current_empresa_id()
    and n.usuario_id = auth.uid()
    and public.app_notificacao_contexto_valido()
    and (p_antes_de is null or n.criado_em < p_antes_de)
  order by n.criado_em desc
  limit greatest(1, least(coalesce(p_limite, 50), 100));
$$;

create or replace function public.app_contar_notificacoes_nao_lidas()
returns integer
language sql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
  select count(*)::integer
  from public.app_notificacoes n
  where n.tenant_id = public.current_tenant_id()
    and n.empresa_id = public.current_empresa_id()
    and n.usuario_id = auth.uid()
    and n.lida_em is null
    and public.app_notificacao_contexto_valido();
$$;

create or replace function public.app_marcar_notificacao_lida(p_notificacao_id uuid)
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
  update public.app_notificacoes
     set lida_em = coalesce(lida_em, now()), atualizado_em = now()
   where id = p_notificacao_id
     and tenant_id = public.current_tenant_id()
     and empresa_id = public.current_empresa_id()
     and usuario_id = auth.uid();
end;
$$;

-- RPCs internas consumidas apenas pela Edge Function com service_role. Elas
-- reservam a entrega com SKIP LOCKED para execucoes concorrentes nao enviarem
-- o mesmo push duas vezes.
create or replace function public.internal_reservar_push_notificacoes(p_limite integer default 100)
returns table (entrega_id uuid, dispositivo_id uuid, expo_push_token text, titulo text, corpo text, dados jsonb)
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
begin
  return query
  with candidatas as (
    select entrega.id
    from public.app_notificacoes_push_entregas entrega
    join public.app_dispositivos_push dispositivo on dispositivo.id = entrega.dispositivo_id and dispositivo.ativo
    where entrega.status in ('pendente', 'falhou')
      and entrega.tentativas < 3
    order by entrega.criado_em
    limit greatest(1, least(coalesce(p_limite, 100), 100))
    for update of entrega skip locked
  ), reservadas as (
    update public.app_notificacoes_push_entregas entrega
       set status = 'enviando', tentativas = entrega.tentativas + 1, atualizado_em = now()
      from candidatas
     where entrega.id = candidatas.id
     returning entrega.id, entrega.dispositivo_id
  )
  select reservadas.id, reservadas.dispositivo_id, dispositivo.expo_push_token,
         notificacao.titulo, notificacao.corpo,
         notificacao.dados || jsonb_build_object('notificacao_id', notificacao.id)
  from reservadas
  join public.app_dispositivos_push dispositivo on dispositivo.id = reservadas.dispositivo_id
  join public.app_notificacoes notificacao on notificacao.id = (
    select entrega.notificacao_id from public.app_notificacoes_push_entregas entrega where entrega.id = reservadas.id
  );
end;
$$;

create or replace function public.internal_finalizar_push_notificacao(
  p_entrega_id uuid,
  p_sucesso boolean,
  p_erro text default null,
  p_desativar_dispositivo boolean default false
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_dispositivo_id uuid;
begin
  update public.app_notificacoes_push_entregas
     set status = case when p_sucesso then 'enviada' else 'falhou' end,
         erro = nullif(btrim(p_erro), ''),
         enviado_em = case when p_sucesso then now() else null end,
         atualizado_em = now()
   where id = p_entrega_id
   returning dispositivo_id into v_dispositivo_id;
  if p_desativar_dispositivo and v_dispositivo_id is not null then
    update public.app_dispositivos_push
       set ativo = false, atualizado_em = now()
     where id = v_dispositivo_id;
  end if;
end;
$$;

revoke all on function public.app_notificacao_contexto_valido() from public, anon, authenticated;
revoke all on function public.app_criar_notificacao(uuid, uuid, uuid, text, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.app_notificar_usuarios_por_papel(uuid, uuid, text[], text, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.internal_reservar_push_notificacoes(integer) from public, anon, authenticated;
revoke all on function public.internal_finalizar_push_notificacao(uuid, boolean, text, boolean) from public, anon, authenticated;
revoke all on function public.app_listar_preferencias_notificacoes() from public, anon;
revoke all on function public.app_definir_preferencia_notificacao(text, boolean) from public, anon;
revoke all on function public.app_registrar_dispositivo_push(text, text) from public, anon;
revoke all on function public.app_desativar_dispositivo_push(text) from public, anon;
revoke all on function public.app_listar_notificacoes(integer, timestamptz) from public, anon;
revoke all on function public.app_contar_notificacoes_nao_lidas() from public, anon;
revoke all on function public.app_marcar_notificacao_lida(uuid) from public, anon;

grant execute on function public.app_listar_preferencias_notificacoes() to authenticated;
grant execute on function public.app_definir_preferencia_notificacao(text, boolean) to authenticated;
grant execute on function public.app_registrar_dispositivo_push(text, text) to authenticated;
grant execute on function public.app_desativar_dispositivo_push(text) to authenticated;
grant execute on function public.app_listar_notificacoes(integer, timestamptz) to authenticated;
grant execute on function public.app_contar_notificacoes_nao_lidas() to authenticated;
grant execute on function public.app_marcar_notificacao_lida(uuid) to authenticated;
grant execute on function public.internal_reservar_push_notificacoes(integer) to service_role;
grant execute on function public.internal_finalizar_push_notificacao(uuid, boolean, text, boolean) to service_role;

notify pgrst, 'reload schema';

commit;
