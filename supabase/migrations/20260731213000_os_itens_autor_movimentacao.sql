create or replace function public.atualizar_registro_os_item_por_movimentacao()
returns trigger
language plpgsql
security definer
set search_path = public, auth, a
as $$
declare
  v_os_item_id integer;
  v_usuario_id uuid;
  v_usuario_nome text;
  v_realizado_por text := nullif(trim(new.realizado_por), '');
begin
  if new.origem_os_id is null or v_realizado_por is null then
    return new;
  end if;

  select u.auth_user_id, nullif(trim(u.nome), '')
    into v_usuario_id, v_usuario_nome
    from a.usuario u
   where u.deleted_at is null
     and (
       lower(u.email) = lower(v_realizado_por)
       or u.auth_user_id::text = v_realizado_por
     )
   order by case when lower(u.email) = lower(v_realizado_por) then 0 else 1 end
   limit 1;

  if v_usuario_id is null then
    select p.id, nullif(trim(p.nome), '')
      into v_usuario_id, v_usuario_nome
      from public.profiles p
     where lower(p.email) = lower(v_realizado_por)
        or p.id::text = v_realizado_por
     limit 1;
  end if;

  v_usuario_nome := coalesce(v_usuario_nome, v_realizado_por);

  select oi.id
    into v_os_item_id
    from public.os_itens oi
   where oi.tenant_id = new.tenant_id
     and oi.empresa_id = new.empresa_id
     and oi.os_id = new.origem_os_id
     and oi.item_id = new.item_id
     and abs(extract(epoch from (oi.criado_em - new.data_movimentacao))) <= 600
   order by
     abs(extract(epoch from (oi.criado_em - new.data_movimentacao))),
     case when abs(oi.quantidade - new.quantidade) < 0.0005 then 0 else 1 end,
     oi.id desc
   limit 1;

  if v_os_item_id is not null then
    update public.os_itens
       set registrado_por = v_usuario_id,
           registrado_por_nome = v_usuario_nome
     where id = v_os_item_id
       and tenant_id = new.tenant_id
       and empresa_id = new.empresa_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_atualizar_registro_os_item_por_movimentacao on public.movimentacoes;

create trigger trg_atualizar_registro_os_item_por_movimentacao
after insert on public.movimentacoes
for each row
execute function public.atualizar_registro_os_item_por_movimentacao();

alter table public.os_itens disable trigger trg_preencher_registro_os_item;

with movimentos_compativeis as (
  select
    oi.id as os_item_id,
    m.realizado_por,
    row_number() over (
      partition by oi.id
      order by
        abs(extract(epoch from (oi.criado_em - m.data_movimentacao))),
        case when abs(oi.quantidade - m.quantidade) < 0.0005 then 0 else 1 end,
        m.id desc
    ) as posicao
  from public.os_itens oi
  join public.movimentacoes m
    on m.tenant_id = oi.tenant_id
   and m.empresa_id = oi.empresa_id
   and m.origem_os_id = oi.os_id
   and m.item_id = oi.item_id
   and abs(extract(epoch from (oi.criado_em - m.data_movimentacao))) <= 600
  where coalesce(nullif(trim(oi.registrado_por_nome), ''), 'Não identificado') = 'Não identificado'
    and nullif(trim(m.realizado_por), '') is not null
), autores_resolvidos as (
  select
    mc.os_item_id,
    coalesce(u.auth_user_id, p.id) as auth_user_id,
    coalesce(nullif(trim(u.nome), ''), nullif(trim(p.nome), ''), mc.realizado_por) as nome
  from movimentos_compativeis mc
  left join lateral (
    select au.auth_user_id, au.nome
      from a.usuario au
     where au.deleted_at is null
       and (
         lower(au.email) = lower(mc.realizado_por)
         or au.auth_user_id::text = mc.realizado_por
       )
     order by case when lower(au.email) = lower(mc.realizado_por) then 0 else 1 end
     limit 1
  ) u on true
  left join lateral (
    select pr.id, pr.nome
      from public.profiles pr
     where lower(pr.email) = lower(mc.realizado_por)
        or pr.id::text = mc.realizado_por
     limit 1
  ) p on u.auth_user_id is null
  where mc.posicao = 1
)
update public.os_itens oi
   set registrado_por = ar.auth_user_id,
       registrado_por_nome = ar.nome
  from autores_resolvidos ar
 where oi.id = ar.os_item_id;

alter table public.os_itens enable trigger trg_preencher_registro_os_item;
