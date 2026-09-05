begin;

create or replace function f.fn_empresa_email_fisco_atualizar(
  p_empresa_id uuid,
  p_email text
)
returns text
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_scope record;
  v_email text := lower(nullif(btrim(p_email), ''));
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  if p_empresa_id is distinct from v_scope.empresa_id then
    raise exception 'Empresa fora do contexto ativo.';
  end if;
  if v_email is null or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Informe um e-mail fiscal valido.';
  end if;

  update c.empresa_fiscal
     set email_fisco = v_email,
         updated_at = now(),
         updated_by = v_scope.usuario_id
   where empresa_id = p_empresa_id
     and deleted_at is null;

  if not found then
    raise exception 'Cadastro fiscal da empresa nao encontrado.';
  end if;

  return v_email;
end;
$function$;

comment on function f.fn_empresa_email_fisco_atualizar(uuid,text) is
  'Atualiza o e-mail fiscal da empresa ativa, validando tenant, empresa e usuario pelo contexto autenticado.';

revoke all on function f.fn_empresa_email_fisco_atualizar(uuid,text) from public, anon;
grant execute on function f.fn_empresa_email_fisco_atualizar(uuid,text) to authenticated, service_role;

commit;
