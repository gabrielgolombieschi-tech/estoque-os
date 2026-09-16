-- Busca de itens para a remessa para conserto.
--
-- A tela de operacoes usava f.fn_faturamento_buscar_itens, que e do faturamento de OS e so
-- devolve item fabricado (i.fabricado is true). A cortina SICK 1211482 (revenda) nao aparecia
-- (16/09/2026). A remessa manda qualquer item do catalogo: aqui a busca cobre tudo que esta
-- ativo, traz o custo da ultima compra como sugestao de valor e diz se o cadastro fiscal
-- (NCM e origem) esta pronto, para a pessoa corrigir antes de tentar criar a remessa.
create or replace function f.fn_remessa_buscar_itens(p_termo text, p_limite integer default 12)
returns table (
  id integer,
  codigo text,
  nome text,
  unidade text,
  custo_ultima_compra numeric,
  ncm text,
  origem smallint,
  fiscal_pronto boolean,
  peso_liquido numeric,
  peso_bruto numeric
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_termo text := nullif(btrim(coalesce(p_termo, '')), '');
  v_limite integer := least(greatest(coalesce(p_limite, 12), 1), 50);
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if v_termo is null then return; end if;

  return query
  select
    i.id,
    i.codigo_interno::text,
    i.nome::text,
    coalesce(nullif(btrim(i.unidade_medida), ''), 'UN')::text,
    nullif(i.custo_ultima_compra, 0)::numeric,
    nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '')::text,
    fi.origem,
    (regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g') ~ '^[0-9]{8}$' and fi.origem is not null),
    nullif(i.peso_liquido, 0)::numeric,
    nullif(i.peso_bruto, 0)::numeric
  from public.itens i
  left join public.fiscal_itens fi
    on fi.item_id = i.id and fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id
  where i.tenant_id = v_scope.tenant_id
    and i.empresa_id = v_scope.empresa_id
    and i.ativo is true
    and i.mesclado_em_item_id is null
    and (
      i.id::text = v_termo
      or public.fn_texto_busca(i.codigo_interno::text) like '%' || public.fn_texto_busca(v_termo) || '%'
      or public.fn_texto_busca(i.codigo_barras::text) like '%' || public.fn_texto_busca(v_termo) || '%'
      or public.fn_texto_busca(i.nome::text) like '%' || public.fn_texto_busca(v_termo) || '%'
    )
  order by
    (i.codigo_interno = v_termo or i.id::text = v_termo) desc,
    i.nome,
    i.id
  limit v_limite;
end;
$$;
revoke all on function f.fn_remessa_buscar_itens(text, integer) from public, anon;
grant execute on function f.fn_remessa_buscar_itens(text, integer) to authenticated, service_role;
