begin;

create or replace function public.can(p_resource text, p_action text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
begin
  if to_regprocedure('public.has_permission(text)') is null then
    return false;
  end if;

  execute 'select public.has_permission($1)'
    into v_ok
    using (p_resource || '.' || p_action);

  return coalesce(v_ok, false);
end;
$$;

create or replace function public.can_many(p_pairs jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_object_agg(key, val),
    '{}'::jsonb
  )
  from (
    select
      case
        when elem ? 'key' then elem->>'key'
        else (elem->>'resource') || '.' || (elem->>'action')
      end as key,
      public.can(elem->>'resource', elem->>'action') as val
    from jsonb_array_elements(coalesce(p_pairs, '[]'::jsonb)) elem
    where jsonb_typeof(elem) = 'object'
  ) s;
$$;

do $$
begin
  if to_regclass('public.roles') is not null
    and to_regclass('public.role_access_rules') is not null then
    with roles_norm as (
      select id,
             translate(lower(coalesce(name, '')),
               'Ã‚Â Ã¢Â€Â¦ÃƒÂ†Ã†Â’Ã¢Â€ÂžÃ¢Â€ÂšÃ…Â Ã‹Â†Ã¢Â€Â°Ã‚Â¡Ã‚ÂÃ…Â’Ã¢Â€Â¹Ã‚Â¢Ã¢Â€Â¢Ã¢Â€ÂœÃƒÂ¤Ã¢Â€ÂÃ‚Â£Ã¢Â€Â”Ã¢Â€Â“Ã‚ÂÃ¢Â€Â¡',
               'aaaaaeeeeiiiiooooouuuuc') as name_norm
      from public.roles
    ),
    admin_roles as (
      select id
      from roles_norm
      where name_norm like 'admin%'
    )
    insert into public.role_access_rules (role_id, resource, action)
    select id, 'admin', 'manage_users'
    from admin_roles
    on conflict do nothing;
  end if;
end$$;

notify pgrst, 'reload schema';
commit;
