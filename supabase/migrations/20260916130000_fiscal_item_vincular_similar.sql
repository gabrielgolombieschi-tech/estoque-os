-- "Vincular com similar": copiar o cadastro fiscal de um item parecido para um item que
-- esta sem ele.
--
-- Pedido do Gabriel em 16/09/2026, na conferencia da NF-e de uma OV: o item 1770 (CLP
-- CP1H Omron) e estoque antigo do outro sistema, sem nota de entrada, e a emissao para em
-- "Origem da mercadoria nao informada no produto." Ate o dia de recadastrar o catalogo,
-- ele precisa buscar um componente parecido e copiar os dados fiscais dele.
--
-- Duas funcoes:
--
--   public.fiscal_item_similares(item, busca, limite)
--     O item atual (cadastro fiscal + NCM e CEST antigos de public.itens) e os candidatos
--     com fiscal completo (NCM e origem). Ordem: mesmo NCM do item atual primeiro, depois
--     pontos por palavras fortes do nome em comum (a mesma regra de tokensFortesDescricao
--     do agente de cadastro: 3+ caracteres com 2+ letras; a primeira palavra e a familia,
--     "CLP"), fabricante e grupo. Com busca, filtra por id, codigo ou nome.
--
--   public.fiscal_item_copiar_de_similar(item, similar, campos)
--     Copia so os campos marcados, e grava de onde vieram: fiscal_copiado_de_item_id,
--     fiscal_copiado_campos, fiscal_copiado_em, fiscal_copiado_por. O audit_trigger de
--     fiscal_itens guarda o antes e o depois.
--
-- Por que colunas novas e nao origem_entrada: origem_entrada (20260911140000) e smallint e
-- guarda a origem que o FORNECEDOR declarou na nota de entrada. Item sem nota nao tem esse
-- fato, e o do similar nao e dele. Tambem nao se copia:
--   - cEnq: e do perfil de operacao; o trigger tg_fiscal_item_bloquear_cenq_produto recusa.
--   - numero_fci, equiparado_industrial, origem_entrada: sao fatos do proprio produto.
--   - credita_*, ipi_entra_no_custo: sao da compra, nao da venda.
--   - origem 1 ou 6 (importacao propria): so vale com a equiparacao declarada item a item,
--     e a trava do montador recusa origem 1 sem ela. Declare a mao no cadastro do item.
--
-- Permissao: public.can('fiscal_itens','write'), a mesma que libera a aba fiscal do
-- cadastro de item (has("fiscal_itens.write") via can_many) e o podeEditarFiscal do agente
-- de cadastro; mais o escopo de empresa ativa de enforce_active_empresa_scope.
--
-- Os dados fiscais de public.itens (ncm, cest, aliquota_*) sao do cadastro antigo: a NF-e
-- le fiscal_itens (fn_solicitacao_nfe_resolver_perfis e fn_solicitacao_nfe_salvar_conferencia),
-- e o cadastro de item so grava la. Por isso a copia so escreve em fiscal_itens.

alter table public.fiscal_itens
  add column if not exists fiscal_copiado_de_item_id integer,
  add column if not exists fiscal_copiado_campos text[],
  add column if not exists fiscal_copiado_em timestamptz,
  add column if not exists fiscal_copiado_por uuid;

comment on column public.fiscal_itens.fiscal_copiado_de_item_id is
  'Item similar de onde o cadastro fiscal foi copiado por "Vincular com similar" (fiscal_item_copiar_de_similar). Nulo quando o fiscal foi digitado ou veio de nota.';
comment on column public.fiscal_itens.fiscal_copiado_campos is
  'Campos copiados do similar na ultima copia. O antes e o depois ficam no audit_log.';
comment on column public.fiscal_itens.fiscal_copiado_em is
  'Quando a ultima copia de similar foi gravada.';
comment on column public.fiscal_itens.fiscal_copiado_por is
  'auth.uid() de quem gravou a ultima copia de similar.';

create or replace function public.fiscal_item_permissao_copiar_similar()
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
begin
  if auth.uid() is null
     or v_tenant is null
     or v_empresa is null
     or not public.has_active_empresa_access(v_tenant, v_empresa)
     or not coalesce(public.can('fiscal_itens', 'write'), false) then
    raise exception using errcode = '42501',
      message = 'Sem permissao para editar o cadastro fiscal de itens.';
  end if;
end;
$$;

revoke all on function public.fiscal_item_permissao_copiar_similar() from public, anon, authenticated;

create or replace function public.fiscal_item_similares(
  p_item_id integer,
  p_busca text default null,
  p_limite integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_item public.itens%rowtype;
  v_atual jsonb;
  v_ncm_atual text;
  v_tokens text[];
  v_familia text;
  v_fabricante text;
  v_busca text[];
  v_limite integer := least(greatest(coalesce(p_limite, 30), 1), 100);
  v_candidatos jsonb;
begin
  perform public.fiscal_item_permissao_copiar_similar();
  v_tenant := public.current_tenant_id();
  v_empresa := public.current_empresa_id();

  select * into v_item
  from public.itens i
  where i.id = p_item_id and i.tenant_id = v_tenant and i.empresa_id = v_empresa;
  if not found then
    raise exception using errcode = 'P0002',
      message = format('Item #%s nao encontrado nesta empresa.', p_item_id);
  end if;

  select jsonb_build_object(
      'id', v_item.id,
      'codigo', v_item.codigo_interno,
      'nome', v_item.nome,
      'fabricante', v_item.fabricante,
      'grupo_id', v_item.grupo_id,
      'grupo', g.nome,
      'fiscal_existe', fi.item_id is not null,
      'ncm_cadastro_antigo', nullif(regexp_replace(coalesce(v_item.ncm, ''), '[^0-9]', '', 'g'), ''),
      'cest_cadastro_antigo', nullif(regexp_replace(coalesce(v_item.cest, ''), '[^0-9]', '', 'g'), ''),
      'origem', fi.origem,
      'ncm', nullif(btrim(fi.ncm), ''),
      'cest', nullif(btrim(fi.cest), ''),
      'unidade_tributavel', nullif(btrim(fi.unidade_tributavel), ''),
      'cfop_padrao', nullif(btrim(fi.cfop_padrao), ''),
      'cst_icms', nullif(btrim(fi.cst_icms), ''),
      'cst_pis', nullif(btrim(fi.cst_pis), ''),
      'cst_cofins', nullif(btrim(fi.cst_cofins), ''),
      'cst_ipi', nullif(btrim(fi.cst_ipi), ''),
      'aliq_icms', fi.aliq_icms,
      'aliq_ipi', fi.aliq_ipi,
      'aliq_pis', fi.aliq_pis,
      'aliq_cofins', fi.aliq_cofins,
      'fiscal_copiado_de_item_id', fi.fiscal_copiado_de_item_id,
      'fiscal_copiado_em', fi.fiscal_copiado_em
    )
  into v_atual
  from (select 1) as um
  left join public.fiscal_itens fi
    on fi.tenant_id = v_item.tenant_id and fi.empresa_id = v_item.empresa_id and fi.item_id = v_item.id
  left join public.item_grupos g
    on g.tenant_id = v_item.tenant_id and g.empresa_id = v_item.empresa_id and g.id = v_item.grupo_id;

  v_ncm_atual := coalesce(v_atual->>'ncm', v_atual->>'ncm_cadastro_antigo');
  v_ncm_atual := nullif(regexp_replace(coalesce(v_ncm_atual, ''), '[^0-9]', '', 'g'), '');

  -- Palavras fortes do nome, na ordem em que aparecem.
  select coalesce(array_agg(t.palavra order by t.pos), '{}'::text[])
  into v_tokens
  from (
    select distinct on (w.palavra) w.palavra, w.pos
    from regexp_split_to_table(
           regexp_replace(upper(translate(coalesce(v_item.nome, ''),
             'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
             'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')), '[^A-Z0-9]+', ' ', 'g'),
           ' ') with ordinality as w(palavra, pos)
    where length(w.palavra) >= 3
      and length(regexp_replace(w.palavra, '[^A-Z]', '', 'g')) >= 2
    order by w.palavra, w.pos
  ) t;
  v_familia := v_tokens[1];
  v_fabricante := nullif(upper(btrim(coalesce(v_item.fabricante, ''))), '');

  select coalesce(array_agg(w), '{}'::text[])
  into v_busca
  from regexp_split_to_table(
         regexp_replace(upper(translate(coalesce(p_busca, ''),
           'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
           'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')), '[^A-Z0-9]+', ' ', 'g'),
         ' ') as w
  where w <> '';

  with base as (
    select i.id, i.codigo_interno, i.nome, i.fabricante, i.grupo_id, g.nome as grupo_nome,
           fi.origem, nullif(regexp_replace(fi.ncm, '[^0-9]', '', 'g'), '') as ncm,
           nullif(btrim(fi.cest), '') as cest,
           nullif(btrim(fi.unidade_tributavel), '') as unidade_tributavel,
           nullif(btrim(fi.cfop_padrao), '') as cfop_padrao,
           nullif(btrim(fi.cst_icms), '') as cst_icms,
           nullif(btrim(fi.cst_pis), '') as cst_pis,
           nullif(btrim(fi.cst_cofins), '') as cst_cofins,
           nullif(btrim(fi.cst_ipi), '') as cst_ipi,
           fi.aliq_icms, fi.aliq_ipi, fi.aliq_pis, fi.aliq_cofins,
           regexp_split_to_array(
             regexp_replace(upper(translate(coalesce(i.nome, ''),
               'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
               'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')), '[^A-Z0-9]+', ' ', 'g'),
             ' ') as palavras,
           upper(translate(coalesce(i.id::text, '') || ' ' || coalesce(i.codigo_interno, '') || ' ' || coalesce(i.nome, ''),
             'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
             'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')) as texto_busca
    from public.itens i
    join public.fiscal_itens fi
      on fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id and fi.item_id = i.id
    left join public.item_grupos g
      on g.tenant_id = i.tenant_id and g.empresa_id = i.empresa_id and g.id = i.grupo_id
    where i.tenant_id = v_tenant
      and i.empresa_id = v_empresa
      and i.id <> v_item.id
      and i.ativo is not false
      and i.mesclado_em_item_id is null
      and nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '') is not null
      and fi.origem is not null
  ), pontuados as (
    select b.*,
           (v_ncm_atual is not null and b.ncm = v_ncm_atual) as mesmo_ncm,
           (v_familia is not null and v_familia = any(b.palavras)) as mesma_familia,
           array(select t from unnest(v_tokens) t where t = any(b.palavras)) as em_comum,
           (v_fabricante is not null and (
              upper(btrim(coalesce(b.fabricante, ''))) = v_fabricante
              or v_fabricante = any(b.palavras))) as mesmo_fabricante,
           (v_item.grupo_id is not null and b.grupo_id = v_item.grupo_id) as mesmo_grupo
    from base b
    where cardinality(v_busca) = 0
       or not exists (select 1 from unnest(v_busca) w where strpos(b.texto_busca, w) = 0)
  ), ordenados as (
    select p.*,
           cardinality(p.em_comum) * 2
             + case when p.mesma_familia then 3 else 0 end
             + case when p.mesmo_fabricante then 2 else 0 end
             + case when p.mesmo_grupo then 2 else 0 end as pontos,
           (case when p.cest is not null then 1 else 0 end
             + case when p.cst_icms is not null then 1 else 0 end
             + case when p.cst_pis is not null then 1 else 0 end
             + case when p.cst_cofins is not null then 1 else 0 end
             + case when p.cst_ipi is not null then 1 else 0 end
             + case when p.aliq_icms is not null then 1 else 0 end) as completude
    from pontuados p
    -- Sem busca, so o que tem alguma semelhanca; com busca, o que a pessoa pediu.
    where cardinality(v_busca) > 0
       or p.mesmo_ncm or cardinality(p.em_comum) > 0 or p.mesmo_fabricante or p.mesmo_grupo
    order by p.mesmo_ncm desc, pontos desc, completude desc, p.id
    limit v_limite
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id,
      'codigo', o.codigo_interno,
      'nome', o.nome,
      'fabricante', o.fabricante,
      'grupo', o.grupo_nome,
      'origem', o.origem,
      'origem_copiavel', o.origem not in (1, 6),
      'ncm', o.ncm,
      'cest', o.cest,
      'unidade_tributavel', o.unidade_tributavel,
      'cfop_padrao', o.cfop_padrao,
      'cst_icms', o.cst_icms,
      'cst_pis', o.cst_pis,
      'cst_cofins', o.cst_cofins,
      'cst_ipi', o.cst_ipi,
      'aliq_icms', o.aliq_icms,
      'aliq_ipi', o.aliq_ipi,
      'aliq_pis', o.aliq_pis,
      'aliq_cofins', o.aliq_cofins,
      'mesmo_ncm', o.mesmo_ncm,
      'motivos', to_jsonb(array_remove(array[
        case when o.mesmo_ncm then 'mesmo NCM' end,
        case when cardinality(o.em_comum) > 0 then 'palavras em comum: ' || array_to_string(o.em_comum, ', ') end,
        case when o.mesmo_fabricante then 'mesmo fabricante' end,
        case when o.mesmo_grupo then 'mesmo grupo' end
      ], null))
    ) order by o.mesmo_ncm desc, o.pontos desc, o.completude desc, o.id), '[]'::jsonb)
  into v_candidatos
  from ordenados o;

  return jsonb_build_object(
    'atual', v_atual,
    'ncm_referencia', v_ncm_atual,
    'palavras', to_jsonb(v_tokens),
    'candidatos', v_candidatos
  );
end;
$$;

create or replace function public.fiscal_item_copiar_de_similar(
  p_item_id integer,
  p_similar_id integer,
  p_campos text[]
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  c_permitidos constant text[] := array[
    'origem', 'ncm', 'cest', 'unidade_tributavel', 'cfop_padrao',
    'cst_icms', 'cst_pis', 'cst_cofins', 'cst_ipi',
    'aliq_icms', 'aliq_ipi', 'aliq_pis', 'aliq_cofins'
  ];
  v_tenant uuid;
  v_empresa uuid;
  v_campos text[];
  v_campo text;
  v_similar_json jsonb;
  v_fs public.fiscal_itens%rowtype;
  v_antes public.fiscal_itens%rowtype;
  v_depois public.fiscal_itens%rowtype;
begin
  perform public.fiscal_item_permissao_copiar_similar();
  v_tenant := public.current_tenant_id();
  v_empresa := public.current_empresa_id();

  select coalesce(array_agg(distinct lower(btrim(c))), '{}'::text[])
  into v_campos
  from unnest(coalesce(p_campos, '{}'::text[])) c
  where btrim(coalesce(c, '')) <> '';

  if cardinality(v_campos) = 0 then
    raise exception using errcode = '22023', message = 'Marque ao menos um campo para copiar.';
  end if;
  foreach v_campo in array v_campos loop
    if not v_campo = any(c_permitidos) then
      raise exception using errcode = '22023',
        message = format('O campo %s nao e copiado de similar.', v_campo);
    end if;
  end loop;

  if p_item_id is not distinct from p_similar_id then
    raise exception using errcode = '22023', message = 'Escolha um similar diferente do proprio item.';
  end if;

  perform 1 from public.itens i
  where i.id = p_item_id and i.tenant_id = v_tenant and i.empresa_id = v_empresa
  for update;
  if not found then
    raise exception using errcode = 'P0002',
      message = format('Item #%s nao encontrado nesta empresa.', p_item_id);
  end if;

  perform 1 from public.itens i
  where i.id = p_similar_id and i.tenant_id = v_tenant and i.empresa_id = v_empresa;
  if not found then
    raise exception using errcode = 'P0002',
      message = format('Similar #%s nao encontrado nesta empresa.', p_similar_id);
  end if;

  select * into v_fs
  from public.fiscal_itens fi
  where fi.tenant_id = v_tenant and fi.empresa_id = v_empresa and fi.item_id = p_similar_id;
  if not found
     or nullif(regexp_replace(coalesce(v_fs.ncm, ''), '[^0-9]', '', 'g'), '') is null
     or v_fs.origem is null then
    raise exception using errcode = '22023',
      message = format('O similar #%s nao tem cadastro fiscal completo (NCM e origem).', p_similar_id);
  end if;

  v_similar_json := to_jsonb(v_fs);
  foreach v_campo in array v_campos loop
    if nullif(btrim(coalesce(v_similar_json->>v_campo, '')), '') is null then
      raise exception using errcode = '22023',
        message = format('O similar #%s nao tem %s para copiar.', p_similar_id, v_campo);
    end if;
  end loop;

  if 'origem' = any(v_campos) and v_fs.origem in (1, 6) then
    raise exception using errcode = '22023', message = format(
      'A origem %s do similar #%s e de importacao propria: ela so vale com a equiparacao a industrial declarada no proprio item. Informe a origem no cadastro do item.',
      v_fs.origem, p_similar_id
    );
  end if;

  select * into v_antes
  from public.fiscal_itens fi
  where fi.tenant_id = v_tenant and fi.empresa_id = v_empresa and fi.item_id = p_item_id
  for update;
  if not found then
    insert into public.fiscal_itens (tenant_id, empresa_id, item_id)
    values (v_tenant, v_empresa, p_item_id)
    returning * into v_antes;
  end if;

  update public.fiscal_itens fi set
    origem = case when 'origem' = any(v_campos) then v_fs.origem else fi.origem end,
    ncm = case when 'ncm' = any(v_campos) then v_fs.ncm else fi.ncm end,
    cest = case when 'cest' = any(v_campos) then v_fs.cest else fi.cest end,
    unidade_tributavel = case when 'unidade_tributavel' = any(v_campos) then v_fs.unidade_tributavel else fi.unidade_tributavel end,
    cfop_padrao = case when 'cfop_padrao' = any(v_campos) then v_fs.cfop_padrao else fi.cfop_padrao end,
    cst_icms = case when 'cst_icms' = any(v_campos) then v_fs.cst_icms else fi.cst_icms end,
    cst_pis = case when 'cst_pis' = any(v_campos) then v_fs.cst_pis else fi.cst_pis end,
    cst_cofins = case when 'cst_cofins' = any(v_campos) then v_fs.cst_cofins else fi.cst_cofins end,
    cst_ipi = case when 'cst_ipi' = any(v_campos) then v_fs.cst_ipi else fi.cst_ipi end,
    aliq_icms = case when 'aliq_icms' = any(v_campos) then v_fs.aliq_icms else fi.aliq_icms end,
    aliq_ipi = case when 'aliq_ipi' = any(v_campos) then v_fs.aliq_ipi else fi.aliq_ipi end,
    aliq_pis = case when 'aliq_pis' = any(v_campos) then v_fs.aliq_pis else fi.aliq_pis end,
    aliq_cofins = case when 'aliq_cofins' = any(v_campos) then v_fs.aliq_cofins else fi.aliq_cofins end,
    fiscal_copiado_de_item_id = p_similar_id,
    fiscal_copiado_campos = v_campos,
    fiscal_copiado_em = now(),
    fiscal_copiado_por = auth.uid(),
    atualizado_em = now()
  where fi.id = v_antes.id
  returning * into v_depois;

  return jsonb_build_object(
    'item_id', p_item_id,
    'similar_id', p_similar_id,
    'campos', to_jsonb(v_campos),
    'antes', to_jsonb(v_antes),
    'depois', to_jsonb(v_depois)
  );
end;
$$;

revoke all on function public.fiscal_item_similares(integer, text, integer) from public, anon;
revoke all on function public.fiscal_item_copiar_de_similar(integer, integer, text[]) from public, anon;
grant execute on function public.fiscal_item_similares(integer, text, integer) to authenticated;
grant execute on function public.fiscal_item_copiar_de_similar(integer, integer, text[]) to authenticated;

comment on function public.fiscal_item_similares(integer, text, integer) is
  'Vincular com similar: o cadastro fiscal do item e os itens parecidos com NCM e origem, mesmo NCM primeiro, depois palavras do nome, fabricante e grupo.';
comment on function public.fiscal_item_copiar_de_similar(integer, integer, text[]) is
  'Vincular com similar: copia do similar so os campos fiscais marcados e grava fiscal_copiado_de_item_id/campos/em/por. Permissao: can(fiscal_itens, write).';
