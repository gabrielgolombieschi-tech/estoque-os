-- Faturamento e venda, nao qualquer nota de saida.
--
-- O painel do app e o analitico do web somavam toda NF-e de saida emitida. Em
-- setembro de 2026 isso colocou R$ 428.902,30 na WEG, quando a venda foi
-- R$ 280.057,46: nove NF-e de retorno do material da propria WEG (CFOP 5902,
-- R$ 148.844,84, uma delas o painel CNC de R$ 100.000,00) entraram como receita.
-- Pelo mesmo caminho entravam a remessa para conserto da SICK (6915, R$ 4.760,09)
-- e a devolucao de compra 2/23 (5201, R$ 313,18, que aparecia como "Cliente nao
-- informado").
--
-- O criterio fica no CFOP, que existe tanto na nota emitida pelo sistema quanto
-- no XML da importada, e mora num lugar so: f.fn_cfop_e_venda. Conta como venda:
--   x101 a x125  vendas (inclui industrializacao para terceiros, 5124/5125)
--   x401 a x405  vendas com substituicao tributaria
--   x933         servico com ISSQN dentro da NF-e
-- com x = 5, 6 ou 7. Fica de fora o resto: remessas e retornos (59xx),
-- devolucoes (52xx, 541x), transferencias (515x, 5408/5409), venda de ativo
-- (5551) e simples faturamento de entrega futura (5922).
--
-- Nota com itens de venda e de retorno juntos conta so a parte de venda,
-- proporcional ao valor dos itens (frete e IPI acompanham). Nota importada sem
-- itens usa os CFOPs do XML; sem XML conta inteira (em 18/09/2026 as duas nesse
-- caso eram venda). NFS-e e servico e conta inteira.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function f.fn_cfop_e_venda(p_cfop text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $function$
  select coalesce(btrim(p_cfop) ~ '^[567](10[1-9]|11[0-9]|12[0-5]|40[1-5]|933)$', false);
$function$;

create or replace function f.fn_documento_fiscal_valor_receita(p_documento_fiscal_id uuid)
returns numeric
language sql
stable
set search_path = pg_catalog
as $function$
  with documento as (
    select d.id, d.modelo, coalesce(d.valor_total, 0)::numeric as valor_total
    from f.documento_fiscal as d
    where d.id = p_documento_fiscal_id
  ),
  itens as (
    select
      count(*) as quantidade,
      coalesce(sum(i.valor_total), 0)::numeric as total,
      coalesce(sum(i.valor_total) filter (where f.fn_cfop_e_venda(i.cfop)), 0)::numeric as venda,
      coalesce(bool_or(f.fn_cfop_e_venda(i.cfop)), false) as tem_venda
    from f.documento_fiscal_item as i
    where i.documento_fiscal_id = p_documento_fiscal_id
      and i.deleted_at is null
  )
  select case
    when upper(coalesce(documento.modelo, '')) = 'NFSE' then documento.valor_total
    when itens.quantidade > 0 then
      case
        when not itens.tem_venda then 0
        when itens.venda = itens.total or itens.total = 0 then documento.valor_total
        else round(documento.valor_total * itens.venda / itens.total, 2)
      end
    -- Importada sem itens: o CFOP so existe no XML. Nulo = sem XML ou sem CFOP.
    when (
      select bool_or(f.fn_cfop_e_venda(cfop.m[1]))
      from f.documento_fiscal_xml as x
      cross join lateral regexp_matches(coalesce(x.xml_raw, ''), '<CFOP>([0-9]{4})</CFOP>', 'g') as cfop(m)
      where x.documento_fiscal_id = documento.id
        and x.deleted_at is null
    ) is false then 0
    else documento.valor_total
  end
  from documento, itens;
$function$;

-- Chamadas so de dentro das RPCs de faturamento (security definer).
revoke all on function f.fn_cfop_e_venda(text) from public, anon, authenticated;
revoke all on function f.fn_documento_fiscal_valor_receita(uuid) from public, anon, authenticated;

-- Painel do app.
do $patch_painel$
declare
  v_definition text;
  v_valor_needle text := $needle$      d.valor_total
    from f.documento_fiscal as d
    left join public.clientes as cliente$needle$;
  v_valor_replacement text := $replacement$      -- So a parte da nota que e venda: retorno de material do cliente,
      -- remessa e devolucao de compra saem com valor mas nao sao receita.
      receita.valor as valor_total
    from f.documento_fiscal as d
    cross join lateral (select f.fn_documento_fiscal_valor_receita(d.id) as valor) as receita
    left join public.clientes as cliente$replacement$;
  v_filtro_needle text := $needle$      and d.deleted_at is null
      and coalesce(d.competencia_date, d.emissao_date) >= make_date(v_ano, 1, 1)$needle$;
  v_filtro_replacement text := $replacement$      and d.deleted_at is null
      and receita.valor <> 0
      and coalesce(d.competencia_date, d.emissao_date) >= make_date(v_ano, 1, 1)$replacement$;
begin
  select pg_get_functiondef('public.app_faturamento_painel(integer,integer)'::regprocedure)
    into v_definition;

  if (length(v_definition) - length(replace(v_definition, v_valor_needle, ''))) / length(v_valor_needle) <> 1 then
    raise exception 'painel_faturamento_valor_nao_encontrado';
  end if;
  if (length(v_definition) - length(replace(v_definition, v_filtro_needle, ''))) / length(v_filtro_needle) <> 1 then
    raise exception 'painel_faturamento_filtro_nao_encontrado';
  end if;

  v_definition := replace(v_definition, v_valor_needle, v_valor_replacement);
  v_definition := replace(v_definition, v_filtro_needle, v_filtro_replacement);
  execute v_definition;
end;
$patch_painel$;

-- Analitico do web.
do $patch_analitico$
declare
  v_definition text;
  v_valor_needle text := $needle$    documento.valor_total::numeric,$needle$;
  v_valor_replacement text := $replacement$    -- So a parte da nota que e venda (f.fn_cfop_e_venda).
    receita.valor,$replacement$;
  v_from_needle text := $needle$  from f.documento_fiscal documento
  left join public.clientes cliente$needle$;
  v_from_replacement text := $replacement$  from f.documento_fiscal documento
  cross join lateral (select f.fn_documento_fiscal_valor_receita(documento.id) as valor) receita
  left join public.clientes cliente$replacement$;
  v_filtro_needle text := $needle$    and documento.deleted_at is null
    and documento.emissao_date >= p_data_inicio$needle$;
  v_filtro_replacement text := $replacement$    and documento.deleted_at is null
    -- Retorno, remessa e devolucao de compra nao sao faturamento.
    and receita.valor <> 0
    and documento.emissao_date >= p_data_inicio$replacement$;
begin
  select pg_get_functiondef('f.faturamento_analitico_documentos(uuid,uuid[],date,date)'::regprocedure)
    into v_definition;

  if (length(v_definition) - length(replace(v_definition, v_valor_needle, ''))) / length(v_valor_needle) <> 1 then
    raise exception 'analitico_valor_nao_encontrado';
  end if;
  if (length(v_definition) - length(replace(v_definition, v_from_needle, ''))) / length(v_from_needle) <> 1 then
    raise exception 'analitico_from_nao_encontrado';
  end if;
  if (length(v_definition) - length(replace(v_definition, v_filtro_needle, ''))) / length(v_filtro_needle) <> 1 then
    raise exception 'analitico_filtro_nao_encontrado';
  end if;

  v_definition := replace(v_definition, v_valor_needle, v_valor_replacement);
  v_definition := replace(v_definition, v_from_needle, v_from_replacement);
  v_definition := replace(v_definition, v_filtro_needle, v_filtro_replacement);
  execute v_definition;
end;
$patch_analitico$;

do $assert$
begin
  if not f.fn_cfop_e_venda('5101') or not f.fn_cfop_e_venda('6102') or not f.fn_cfop_e_venda('5124')
     or not f.fn_cfop_e_venda('6119') or not f.fn_cfop_e_venda('5405') or not f.fn_cfop_e_venda('5933')
     or f.fn_cfop_e_venda('5902') or f.fn_cfop_e_venda('6915') or f.fn_cfop_e_venda('5201')
     or f.fn_cfop_e_venda('5151') or f.fn_cfop_e_venda('5551') or f.fn_cfop_e_venda('5922')
     or f.fn_cfop_e_venda(null) then
    raise exception 'cfop_e_venda_errado';
  end if;

  if position('fn_documento_fiscal_valor_receita' in pg_get_functiondef('public.app_faturamento_painel(integer,integer)'::regprocedure)) = 0
     or position('fn_documento_fiscal_valor_receita' in pg_get_functiondef('f.faturamento_analitico_documentos(uuid,uuid[],date,date)'::regprocedure)) = 0 then
    raise exception 'faturamento_sem_criterio_de_venda';
  end if;

  -- Dados de producao: so confere onde as notas existem.
  -- NF-e 2/27 (retorno 5902 da WEG) e NF-e 2/11 (venda 5101 da WEG).
  if exists (select 1 from f.documento_fiscal where id = '84cbc79a-598d-4d7f-a07a-7a46307e49a0')
     and f.fn_documento_fiscal_valor_receita('84cbc79a-598d-4d7f-a07a-7a46307e49a0') <> 0 then
    raise exception 'retorno_5902_contado_como_venda';
  end if;
  if exists (select 1 from f.documento_fiscal where id = '3c2d7a1e-0ed1-41e5-adbd-799fa39c7133')
     and f.fn_documento_fiscal_valor_receita('3c2d7a1e-0ed1-41e5-adbd-799fa39c7133') <> 21303.95 then
    raise exception 'venda_5101_fora_do_faturamento';
  end if;
end;
$assert$;

notify pgrst, 'reload schema';

commit;
