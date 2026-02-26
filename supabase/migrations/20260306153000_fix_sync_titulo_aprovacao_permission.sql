begin;
create or replace function public.fn_sync_titulo_aprovacao_from_nf_entrada(
  p_nf_entrada_id bigint,
  p_titulo_id uuid,
  p_motivo_compra_id uuid,
  p_os_id integer default null,
  p_aprovado_por uuid default null
) returns void
language plpgsql
security definer
set search_path to 'public', 'f', 'a', 'c'
set row_security to off
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_aprovador uuid;
begin
  if p_nf_entrada_id is null then
    raise exception 'p_nf_entrada_id obrigatorio';
  end if;
  if p_titulo_id is null then
    raise exception 'p_titulo_id obrigatorio';
  end if;
  if p_motivo_compra_id is null then
    raise exception 'p_motivo_compra_id obrigatorio';
  end if;

  select *
    into v_nf
  from public.nf_entrada n
  where n.id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  update f.titulo t
     set motivo_compra_id = p_motivo_compra_id,
         os_id = coalesce(p_os_id, t.os_id),
         updated_at = now()
   where t.tenant_id = v_nf.tenant_id
     and t.empresa_id = v_nf.empresa_id
     and t.id = p_titulo_id
     and t.deleted_at is null;

  if not found then
    raise exception 'Titulo AP nao encontrado para sincronizar (id=%)', p_titulo_id;
  end if;

  v_aprovador := coalesce(p_aprovado_por, a.fn_current_usuario_id());

  update f.titulo_aprovacao ta
     set motivo_compra_id = p_motivo_compra_id,
         os_id = p_os_id,
         deleted_at = null,
         updated_at = now(),
         updated_by = v_aprovador
   where ta.tenant_id = v_nf.tenant_id
     and ta.titulo_id = p_titulo_id;

  if not found then
    insert into f.titulo_aprovacao (
      tenant_id,
      titulo_id,
      motivo_compra_id,
      os_id,
      aprovado_por
    )
    values (
      v_nf.tenant_id,
      p_titulo_id,
      p_motivo_compra_id,
      p_os_id,
      v_aprovador
    );
  end if;
end;
$$;
alter function public.fn_sync_titulo_aprovacao_from_nf_entrada(bigint, uuid, uuid, integer, uuid) owner to postgres;
revoke all on function public.fn_sync_titulo_aprovacao_from_nf_entrada(bigint, uuid, uuid, integer, uuid) from public;
grant execute on function public.fn_sync_titulo_aprovacao_from_nf_entrada(bigint, uuid, uuid, integer, uuid) to authenticated;
grant execute on function public.fn_sync_titulo_aprovacao_from_nf_entrada(bigint, uuid, uuid, integer, uuid) to service_role;
commit;
