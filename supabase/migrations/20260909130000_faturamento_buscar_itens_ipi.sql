-- A busca de produto fabricado devolve o IPI do cadastro fiscal.
--
-- Decisao de Gabriel em 09/09/2026, montando a NF-e da OS 287. O IPI ja esta no
-- cadastro do item (fiscal_itens.cst_ipi / aliq_ipi), mas a composicao das linhas
-- so somava mercadoria: a tela dizia "Total das linhas 19.411,35" enquanto a nota
-- ia sair 21.303,96, e o total real so aparecia depois de conferir. Com cst_ipi e
-- aliquota_ipi na busca, a linha ja mostra o total que vai para a nota e a
-- comparacao com o saldo (que passou a contar IPI na 20260909120000) fecha desde
-- a composicao.
--
-- Muda o retorno, entao vai de drop + create, como manda o padrao do projeto.

drop function if exists f.fn_faturamento_buscar_itens(uuid, uuid, text, integer);

create function f.fn_faturamento_buscar_itens(p_tenant_id uuid, p_empresa_id uuid, p_termo text, p_limite integer default 20)
returns table(id integer, codigo text, nome text, unidade text, valor_unitario numeric, cst_ipi text, aliquota_ipi numeric)
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
    (case when fi.cst_ipi in ('00', '49', '50', '99') then fi.aliq_ipi else null end)::numeric
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

grant execute on function f.fn_faturamento_buscar_itens(uuid, uuid, text, integer) to authenticated, service_role;
