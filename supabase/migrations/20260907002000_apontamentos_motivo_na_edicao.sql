-- Editar hora de OUTRO colaborador passa a exigir motivo, do mesmo jeito que o
-- cancelamento. Decisao de Gabriel em 06/09/2026, junto da revisao do app com
-- o perfil de apontamento.
--
-- Quem edita a propria hora nao precisa justificar — o que ele escreve e a
-- descricao do servico, que ja e obrigatoria. O motivo existe para o caso em
-- que responsavel da OS, Coordenacao, Diretor ou Admin mexe no lancamento de
-- terceiro: fica registrado quem alterou, quando, por que e o antes/depois.
--
-- A assinatura antiga de app_editar_apontamento continua publicada, porque os
-- aparelhos com a versao anterior do app ainda a chamam. Ela delega para a
-- nova com motivo nulo — o que basta para editar a propria hora e recusa,
-- com mensagem clara, a edicao de hora de terceiro.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Historico de edicao ------------------------------------------------------

create table if not exists public.apontamentos_horas_edicoes (
  id uuid primary key default gen_random_uuid(),
  apontamento_id uuid not null,
  tenant_id uuid not null,
  empresa_id uuid not null,
  os_id integer not null,
  colaborador_id uuid not null,
  editado_por_user_id uuid not null,
  editado_por_nome text not null,
  motivo text,
  horas_antes numeric,
  horas_depois numeric,
  tipo_hora_id_antes uuid,
  tipo_hora_id_depois uuid,
  descricao_antes text,
  descricao_depois text,
  status_aprovacao_no_momento text,
  criado_em timestamp with time zone not null default now()
);

comment on table public.apontamentos_horas_edicoes is
  'Trilha de alteracao de apontamento de horas: quem alterou, quando, por que e o antes/depois. Escrita apenas por app_editar_apontamento.';

create index if not exists idx_apontamentos_horas_edicoes_apontamento
  on public.apontamentos_horas_edicoes (apontamento_id, criado_em desc);

create index if not exists idx_apontamentos_horas_edicoes_os
  on public.apontamentos_horas_edicoes (tenant_id, empresa_id, os_id, criado_em desc);

-- Mesma postura de apontamentos_horas_cancelamentos: RLS ligada e sem policy,
-- entao so as funcoes SECURITY DEFINER (row_security off) enxergam a tabela.
alter table public.apontamentos_horas_edicoes enable row level security;

grant select, insert, update, delete, truncate, references, trigger
  on public.apontamentos_horas_edicoes to service_role;

-- 2. Nova assinatura, com motivo ----------------------------------------------

create or replace function public.app_editar_apontamento(
  p_apontamento_id uuid,
  p_horas numeric,
  p_tipo_hora_id uuid,
  p_descricao text,
  p_confirmar_avisos boolean,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'c'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_os_id integer;
  v_colaborador_id uuid;
  v_colaborador_user_id uuid;
  v_data date;
  v_gerado_por_hh boolean;
  v_status text;
  v_status_aprovacao text;
  v_horas_antes numeric;
  v_tipo_hora_antes uuid;
  v_descricao_antes text;
  v_tipo_existe boolean;
  v_descricao text := nullif(btrim(p_descricao), '');
  v_motivo text := nullif(btrim(p_motivo), '');
  v_editor_nome text;
  v_hora_de_terceiro boolean;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar autenticação, tenant e empresa ativos.';
  end if;
  if not public.can('apontamentos', 'write', v_tenant_id) then
    raise exception 'Seu perfil não possui permissão para editar apontamentos.';
  end if;
  if p_horas is null or p_horas <= 0 or p_horas > 24 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'horas', 'mensagem', 'Informe uma quantidade de horas entre 0 e 24.')));
  end if;
  if v_descricao is null or char_length(v_descricao) < 10 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'descricao', 'mensagem', 'Descreva o serviço realizado com pelo menos 10 caracteres.')));
  end if;

  select apontamento.os_id, apontamento.colaborador_id, apontamento.data, apontamento.gerado_por_hh,
         apontamento.status::text, apontamento.status_aprovacao,
         apontamento.horas, apontamento.tipo_hora_id, apontamento.descricao,
         colaborador.user_id
    into v_os_id, v_colaborador_id, v_data, v_gerado_por_hh, v_status, v_status_aprovacao,
         v_horas_antes, v_tipo_hora_antes, v_descricao_antes,
         v_colaborador_user_id
  from public.apontamentos_horas as apontamento
  join public.colaboradores as colaborador
    on colaborador.id = apontamento.colaborador_id
   and colaborador.tenant_id = apontamento.tenant_id
   and colaborador.empresa_id = apontamento.empresa_id
  where apontamento.id = p_apontamento_id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id;

  if not found then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'apontamento', 'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.')));
  end if;
  if coalesce(v_gerado_por_hh, false) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'hh', 'mensagem', 'Este apontamento é um espelho de HH e deve ser alterado no módulo HH.')));
  end if;
  if lower(coalesce(v_status, '')) = 'fechado' then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'status', 'mensagem', 'Este apontamento está fechado e não pode ser alterado.')));
  end if;
  if not public.fn_usuario_pode_alterar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, p_apontamento_id) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', case
          when v_status_aprovacao = 'aprovado' then 'Após a aprovação, somente o responsável da OS, Coordenação, Diretor ou Admin pode alterar.'
          else 'Antes da aprovação, somente o próprio colaborador, o responsável da OS, Coordenação, Diretor ou Admin pode alterar.'
        end
      )));
  end if;

  v_hora_de_terceiro := v_colaborador_user_id is distinct from v_auth_uid;

  if v_hora_de_terceiro and (v_motivo is null or char_length(v_motivo) < 5) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'motivo', 'mensagem', 'Para alterar a hora de outro colaborador, informe o motivo com pelo menos 5 caracteres.')));
  end if;
  if v_motivo is not null and char_length(v_motivo) > 500 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'motivo', 'mensagem', 'O motivo da alteração deve ter no máximo 500 caracteres.')));
  end if;

  select exists (
    select 1
    from public.tipos_horas as tipo
    where tipo.id = p_tipo_hora_id
      and tipo.tenant_id = v_tenant_id
      and tipo.ativo
  ) into v_tipo_existe;
  if not v_tipo_existe then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'tipo_hora', 'mensagem', 'O tipo de hora informado não existe ou está inativo.')));
  end if;
  if exists (
    select 1
    from public.apontamentos_horas as apontamento
    where apontamento.id <> p_apontamento_id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.os_id = v_os_id
      and apontamento.colaborador_id = v_colaborador_id
      and apontamento.data = v_data
      and apontamento.tipo_hora_id = p_tipo_hora_id
      and not coalesce(apontamento.gerado_por_hh, false)
  ) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'duplicidade', 'mensagem', 'Já existe outro apontamento para esta OS, colaborador, data e tipo de hora.')));
  end if;

  update public.apontamentos_horas
  set horas = p_horas,
      tipo_hora_id = p_tipo_hora_id,
      descricao = v_descricao
  where id = p_apontamento_id
    and tenant_id = v_tenant_id
    and empresa_id = v_empresa_id;

  select coalesce(
           nullif(btrim(usuario.nome), ''),
           nullif(btrim(usuario.email), ''),
           'Usuário não identificado'
         )
    into v_editor_nome
  from a.usuario as usuario
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  insert into public.apontamentos_horas_edicoes (
    apontamento_id, tenant_id, empresa_id, os_id, colaborador_id,
    editado_por_user_id, editado_por_nome, motivo,
    horas_antes, horas_depois,
    tipo_hora_id_antes, tipo_hora_id_depois,
    descricao_antes, descricao_depois,
    status_aprovacao_no_momento
  ) values (
    p_apontamento_id, v_tenant_id, v_empresa_id, v_os_id, v_colaborador_id,
    v_auth_uid, coalesce(v_editor_nome, 'Usuário não identificado'), v_motivo,
    v_horas_antes, p_horas,
    v_tipo_hora_antes, p_tipo_hora_id,
    v_descricao_antes, v_descricao,
    v_status_aprovacao
  );

  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', '[]'::jsonb, 'erros', '[]'::jsonb);
end;
$function$;

grant execute on function public.app_editar_apontamento(uuid, numeric, uuid, text, boolean, text) to authenticated;

-- 3. Assinatura antiga vira atalho para a nova --------------------------------
-- Sem DEFAULT em p_motivo la em cima, uma chamada com as cinco chaves antigas
-- so casa com esta versao — nao ha ambiguidade de overload no PostgREST.

create or replace function public.app_editar_apontamento(
  p_apontamento_id uuid,
  p_horas numeric,
  p_tipo_hora_id uuid,
  p_descricao text default null::text,
  p_confirmar_avisos boolean default false
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
  select public.app_editar_apontamento(p_apontamento_id, p_horas, p_tipo_hora_id, p_descricao, p_confirmar_avisos, null::text);
$function$;

-- 4. Conferencia --------------------------------------------------------------

do $assertions$
begin
  if to_regclass('public.apontamentos_horas_edicoes') is null then
    raise exception 'tabela_edicoes_ausente';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'app_editar_apontamento'
  ) <> 2 then
    raise exception 'app_editar_apontamento_assinaturas_inesperadas';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
