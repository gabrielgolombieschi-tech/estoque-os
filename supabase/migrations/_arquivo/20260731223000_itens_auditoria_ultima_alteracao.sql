update public.profiles p
   set nome = u.nome
  from a.usuario u
 where u.auth_user_id = p.id
   and u.deleted_at is null
   and nullif(trim(u.nome), '') is not null
   and nullif(trim(p.nome), '') is null;

drop function if exists public.list_itens_auditoria(uuid, uuid, integer[]);

create function public.list_itens_auditoria(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_item_ids integer[]
)
returns table (
  item_id integer,
  acao text,
  data_acao timestamp without time zone,
  autor_nome text,
  autor_identificador text
)
language sql
stable
security definer
set search_path = public, auth, a
as $$
  select
    i.id as item_id,
    case
      when nullif(trim(i.atualizado_por), '') is not null then 'alteracao'
      else 'criacao'
    end as acao,
    case
      when nullif(trim(i.atualizado_por), '') is not null then i.atualizado_em
      else i.criado_em
    end as data_acao,
    coalesce(
      nullif(trim(autor.nome), ''),
      nullif(trim(perfil.nome), ''),
      nullif(trim(coalesce(i.atualizado_por, i.criado_por)), ''),
      'Não identificado'
    ) as autor_nome,
    nullif(trim(coalesce(i.atualizado_por, i.criado_por)), '') as autor_identificador
  from public.itens i
  left join lateral (
    select u.nome, u.auth_user_id
      from a.usuario u
     where u.deleted_at is null
       and (
         lower(u.email) = lower(nullif(trim(coalesce(i.atualizado_por, i.criado_por)), ''))
         or u.auth_user_id::text = nullif(trim(coalesce(i.atualizado_por, i.criado_por)), '')
       )
     order by case
       when lower(u.email) = lower(nullif(trim(coalesce(i.atualizado_por, i.criado_por)), '')) then 0
       else 1
     end
     limit 1
  ) autor on true
  left join public.profiles perfil
    on perfil.id = autor.auth_user_id
  where i.tenant_id = p_tenant_id
    and i.empresa_id = p_empresa_id
    and i.id = any(coalesce(p_item_ids, array[]::integer[]))
    and (
      public.can__legacy_40734('estoque', 'read')
      or public.can__legacy_40734('os', 'read')
      or public.can__legacy_40734('cad_itens', 'write')
    );
$$;

revoke all on function public.list_itens_auditoria(uuid, uuid, integer[]) from public;
grant execute on function public.list_itens_auditoria(uuid, uuid, integer[]) to authenticated;
