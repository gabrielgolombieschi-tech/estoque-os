alter table public.os_itens
  add column if not exists registrado_em timestamp with time zone,
  add column if not exists registrado_por uuid,
  add column if not exists registrado_por_nome text;

comment on column public.os_itens.registrado_em is
  'Data e hora da inclusao ou ultima alteracao do item na OS.';

comment on column public.os_itens.registrado_por is
  'Usuario autenticado responsavel pela inclusao ou ultima alteracao do item na OS.';

comment on column public.os_itens.registrado_por_nome is
  'Nome do usuario responsavel, preservado para exibicao e auditoria.';

update public.os_itens
   set registrado_em = coalesce(criado_em at time zone 'America/Sao_Paulo', now()),
       registrado_por_nome = coalesce(nullif(trim(registrado_por_nome), ''), 'Não identificado')
 where registrado_em is null;

create or replace function public.preencher_registro_os_item()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_user_nome text;
begin
  if v_user_id is not null then
    select nullif(trim(u.nome), '')
      into v_user_nome
      from a.usuario u
     where u.auth_user_id = v_user_id
       and u.deleted_at is null;

    if v_user_nome is null then
      select nullif(trim(p.nome), '')
        into v_user_nome
        from public.profiles p
       where p.id = v_user_id;
    end if;

    v_user_nome := coalesce(
      v_user_nome,
      nullif(trim(auth.jwt() -> 'user_metadata' ->> 'full_name'), ''),
      nullif(trim(auth.jwt() -> 'user_metadata' ->> 'name'), ''),
      nullif(trim(auth.jwt() ->> 'email'), ''),
      v_user_id::text
    );

    new.registrado_por := v_user_id;
    new.registrado_por_nome := v_user_nome;
  elsif tg_op = 'INSERT' then
    new.registrado_por := null;
    new.registrado_por_nome := coalesce(nullif(trim(new.registrado_por_nome), ''), 'Sistema');
  end if;

  new.registrado_em := now();
  return new;
end;
$$;

drop trigger if exists trg_preencher_registro_os_item on public.os_itens;

create trigger trg_preencher_registro_os_item
before insert or update on public.os_itens
for each row
execute function public.preencher_registro_os_item();
