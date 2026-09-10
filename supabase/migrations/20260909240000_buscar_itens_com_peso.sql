-- A busca de produto fabricado devolve os pesos do cadastro.
--
-- Fase 1 do grupo vol (Gabriel, 09/09/2026): a tela de faturar passa a montar volumes
-- com transportador e peso, e o peso vem sugerido do cadastro quando existir. Sem
-- obrigar nada nesta fase — hoje 3.593 itens ativos estao sem peso, e travar agora
-- pararia a emissao inteira. A obrigatoriedade fica para a fase 2.
--
-- Muda o retorno, entao vai de drop + create. Os grants voltam explicitos, sem PUBLIC,
-- como as irmas do schema (licao da 20260909131000).

drop function if exists f.fn_faturamento_buscar_itens(uuid, uuid, text, integer);

create function f.fn_faturamento_buscar_itens(p_tenant_id uuid, p_empresa_id uuid, p_termo text, p_limite integer default 20)
returns table(
  id integer, codigo text, nome text, unidade text, valor_unitario numeric,
  cst_ipi text, aliquota_ipi numeric, peso_liquido numeric, peso_bruto numeric
)
language plpgsql
stable security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_termo text := nullif(btrim(coalesce(p_termo, '')), '');
  v_limite integer := greatest(1, least(coalesce(p_limite, 20), 50));
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using errcode = '22023', message = 'Tenant e empresa sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar itens desta empresa.';
  end if;
  if v_termo is null then return; end if;

  return query
  select
    i.id,
    i.codigo_interno::text,
    i.nome::text,
    coalesce(nullif(btrim(i.unidade_medida), ''), 'UN')::text,
    coalesce(i.preco_unitario, 0)::numeric,
    fi.cst_ipi::text,
    -- Mesma regra da conferencia e do builder: aliquota so vale com CST tributado.
    (case when fi.cst_ipi in ('00', '49', '50', '99') then fi.aliq_ipi else null end)::numeric,
    nullif(i.peso_liquido, 0)::numeric,
    nullif(i.peso_bruto, 0)::numeric
  from public.itens i
  left join public.fiscal_itens fi
    on fi.item_id = i.id and fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id
  where i.tenant_id = p_tenant_id
    and i.empresa_id = p_empresa_id
    and i.ativo is true
    and i.fabricado is true
    and (
      i.id::text = v_termo
      or i.codigo_interno ilike '%' || v_termo || '%'
      or i.codigo_barras ilike '%' || v_termo || '%'
      or i.nome ilike '%' || v_termo || '%'
    )
  order by
    (i.codigo_interno = v_termo or i.id::text = v_termo) desc,
    i.nome,
    i.id
  limit v_limite;
end;
$function$;

revoke execute on function f.fn_faturamento_buscar_itens(uuid, uuid, text, integer) from public;
grant execute on function f.fn_faturamento_buscar_itens(uuid, uuid, text, integer) to authenticated, service_role;
