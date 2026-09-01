begin;

create or replace function public.validate_apontamento_colaborador_contrato()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_cliente_id bigint;
  v_vinculo_exists boolean;
begin
  v_tenant_id := new.tenant_id;

  select cliente_id into v_cliente_id
  from public.ordens_servico
  where id = new.os_id
    and tenant_id = v_tenant_id;

  if v_cliente_id is null then
    return new;
  end if;

  select exists (
    select 1
    from public.colaborador_cliente_funcao
    where tenant_id = v_tenant_id
      and cliente_id = v_cliente_id
      and colaborador_id = new.colaborador_id
      and ativo = true
  ) into v_vinculo_exists;

  if not v_vinculo_exists then
    raise exception
      'Colaborador % nao esta vinculado ao contrato do cliente da OS %. Cadastre o vinculo em Cadastros > Colaboradores x Cliente.',
      new.colaborador_id, new.os_id
      using errcode = '23503';
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.apontamentos_horas') is not null then
    drop trigger if exists trigger_validate_apontamento_colaborador on public.apontamentos_horas;

    create trigger trigger_validate_apontamento_colaborador
      before insert or update of colaborador_id, os_id
      on public.apontamentos_horas
      for each row
      execute function public.validate_apontamento_colaborador_contrato();
  end if;
end$$;

comment on function public.validate_apontamento_colaborador_contrato() is
  'Valida que o colaborador do apontamento esta vinculado ao contrato do cliente da OS (via colaborador_cliente_funcao)';

commit;
notify pgrst, 'reload schema';
