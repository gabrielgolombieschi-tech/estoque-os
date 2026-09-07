-- Busca de fornecedor para a tela de cadastro de item no app.
--
-- O agente de cadastro (/api/itens/agente-cadastro/sugerir) exige
-- fornecedor_id: e a partir do par fornecedor + codigo que ele reconhece a peca
-- e procura preco. No web o fornecedor vem de um seletor da propria tela; no
-- app faltava por onde buscar.
--
-- Mesmo portao do resto do cadastro: can('cad_itens','write'), que e o que a
-- rota do agente confere. Assim a lista nao aparece para quem nao poderia
-- cadastrar de qualquer forma.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

create or replace function public.app_itens_fornecedores(
  p_busca text default null,
  p_limite integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_busca text := nullif(btrim(p_busca), '');
  v_limite integer := least(greatest(coalesce(p_limite, 30), 1), 100);
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if not public.can('cad_itens', 'write', v_tenant_id) then
    raise exception 'Seu perfil não pode cadastrar itens.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', fornecedor.id,
      'nome', fornecedor.nome,
      'documento', fornecedor.documento
    ) order by fornecedor.nome)
    from (
      select f.id, f.nome, f.documento
      from public.fornecedores as f
      where f.tenant_id = v_tenant_id
        and f.empresa_id = v_empresa_id
        and coalesce(f.ativo, true) is true
        and (v_busca is null or f.nome ilike '%' || v_busca || '%' or f.documento ilike '%' || v_busca || '%')
      order by f.nome
      limit v_limite
    ) as fornecedor
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.app_itens_fornecedores(text, integer) from public, anon;
grant execute on function public.app_itens_fornecedores(text, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
