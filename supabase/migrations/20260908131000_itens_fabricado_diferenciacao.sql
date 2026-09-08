-- Diferenciacao dos produtos fabricados (producao propria) no cadastro de itens.
--
-- Motivo (08/09/2026): na primeira nota real da OS 319 a busca de produto da
-- tela de faturar listou machos, fitas e conduites — itens de compra — ao lado
-- do produto fabricado, e a tela Estoque > Cadastro nao tinha como separar os
-- fabricados dos 213 itens de revenda comprados: os quatro fabricados nasciam
-- com finalidade = revenda e a flag `fabricado` nao aparecia em lugar nenhum.
--
-- Regra: a finalidade `fabricado` (valor novo do enum, migration anterior) e a
-- fonte da verdade; a coluna booleana `fabricado` passa a ser derivada dela por
-- trigger, nos dois sentidos, para que RPC, tela e importacao nunca divirjam.
--   - criar_item_fabricado_da_os grava finalidade = fabricado;
--   - search_cadastro_itens devolve fabricado + OS de origem e aceita p_fabricado;
--   - fn_faturamento_buscar_itens (tela de faturar OS) so devolve fabricados.

-- 1. Coluna booleana derivada da finalidade, nos dois sentidos.
create or replace function public.tg_itens_fabricado_finalidade()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $$
begin
  if tg_op = 'INSERT' then
    if new.fabricado is true and new.finalidade is distinct from 'fabricado'::public.item_finalidade then
      new.finalidade := 'fabricado'::public.item_finalidade;
    else
      new.fabricado := (new.finalidade = 'fabricado'::public.item_finalidade) is true;
    end if;
  else
    if new.finalidade is distinct from old.finalidade then
      new.fabricado := (new.finalidade = 'fabricado'::public.item_finalidade) is true;
    elsif new.fabricado is distinct from old.fabricado then
      if new.fabricado is true then
        new.finalidade := 'fabricado'::public.item_finalidade;
      elsif old.finalidade = 'fabricado'::public.item_finalidade then
        -- finalidade e not null e nao cabe inventar revenda/consumo aqui: quem
        -- tira o item de fabricado e que sabe o que ele virou.
        raise exception using errcode = '22023', message = format(
          'Item %s: para deixar de ser fabricado, troque a finalidade (revenda, consumo, materia-prima...) em vez de desmarcar a flag.', new.id);
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_itens_fabricado_finalidade on public.itens;
create trigger trg_itens_fabricado_finalidade
  before insert or update of finalidade, fabricado on public.itens
  for each row execute function public.tg_itens_fabricado_finalidade();

comment on column public.itens.fabricado is
  'Derivado de finalidade = fabricado pelo trigger trg_itens_fabricado_finalidade; nao gravar direto.';

-- 2. Os fabricados que ja existem (FAB-OS303-01, FAB-OS304-01/02, FAB-OS319-01)
--    saem de "revenda" — passa pelo trigger, que confirma fabricado = true.
update public.itens
set finalidade = 'fabricado'::public.item_finalidade
where fabricado is true and finalidade is distinct from 'fabricado'::public.item_finalidade;

-- 3. O produto criado a partir da OS nasce com a finalidade certa.
create or replace function public.criar_item_fabricado_da_os(
  p_os_id integer, p_nome text, p_ncm text, p_origem integer, p_unidade text, p_cst_ipi text,
  p_aliquota_ipi numeric default null, p_cenq text default null
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_os public.ordens_servico%rowtype;
  v_codigo text;
  v_seq integer;
  v_item_id integer;
  v_ncm text := regexp_replace(coalesce(p_ncm, ''), '[^0-9]', '', 'g');
  v_unidade text := upper(btrim(coalesce(p_unidade, '')));
  v_cst_ipi text := btrim(coalesce(p_cst_ipi, ''));
begin
  if v_tenant is null or v_empresa is null or not f.has_finance_access(v_tenant, v_empresa) then
    raise exception using errcode = '42501', message = 'Sem permissao para cadastrar produto fabricado nesta empresa.';
  end if;
  select * into v_os from public.ordens_servico os
  where os.tenant_id = v_tenant and os.empresa_id = v_empresa and os.id = p_os_id and os.tipo_documento = 'OS';
  if not found then
    raise exception using errcode = 'P0002', message = format('OS %s nao encontrada nesta empresa.', p_os_id);
  end if;
  if nullif(btrim(coalesce(p_nome, '')), '') is null then
    raise exception using errcode = '22023', message = 'Informe a descricao do produto fabricado.';
  end if;
  if v_ncm !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'NCM deve ter 8 digitos.';
  end if;
  if p_origem is null or p_origem not between 0 and 8 then
    raise exception using errcode = '22023', message = 'Origem da mercadoria (0 a 8) e obrigatoria e nao e deduzida.';
  end if;
  if v_unidade = '' then
    raise exception using errcode = '22023', message = 'Unidade tributavel e obrigatoria.';
  end if;
  if v_cst_ipi !~ '^(0[0-5]|49|5[0-5]|99)$' then
    raise exception using errcode = '22023', message = 'CST de IPI invalido.';
  end if;
  if v_cst_ipi in ('00', '49', '50', '99') and (p_aliquota_ipi is null or p_aliquota_ipi < 0) then
    raise exception using errcode = '22023', message = 'IPI tributado exige aliquota.';
  end if;

  select coalesce(max((regexp_match(i.codigo_interno, '-([0-9]+)$'))[1]::integer), 0) + 1 into v_seq
  from public.itens i
  where i.tenant_id = v_tenant and i.empresa_id = v_empresa
    and i.codigo_interno like 'FAB-OS' || coalesce(v_os.numero_os, v_os.id::text) || '-%';
  v_codigo := 'FAB-OS' || coalesce(v_os.numero_os, v_os.id::text) || '-' || lpad(v_seq::text, 2, '0');

  -- finalidade = fabricado e a fonte da verdade; o trigger confirma fabricado = true.
  insert into public.itens (tenant_id, empresa_id, codigo_interno, nome, descricao, tipo, unidade_medida, finalidade, ativo, fabricado, origem_os_id)
  values (v_tenant, v_empresa, v_codigo, upper(btrim(p_nome)), upper(btrim(p_nome)), 'produto', v_unidade, 'fabricado', true, true, v_os.id)
  returning id into v_item_id;

  -- A linha fiscal nasce pelo trigger; aqui entram os campos obrigatorios.
  update public.fiscal_itens fi
  set ncm = v_ncm,
      origem = p_origem,
      unidade_tributavel = v_unidade,
      cst_ipi = v_cst_ipi,
      aliq_ipi = case when v_cst_ipi in ('00', '49', '50', '99') then p_aliquota_ipi else null end,
      ipi_codigo_enquadramento_legal = nullif(btrim(coalesce(p_cenq, '')), ''),
      atualizado_em = now()
  where fi.tenant_id = v_tenant and fi.empresa_id = v_empresa and fi.item_id = v_item_id;
  if not found then
    raise exception using errcode = '55000', message = 'A linha fiscal do produto nao foi criada pelo trigger de itens.';
  end if;
  return v_item_id;
end;
$$;

-- 4. Tela de faturar OS: a NF-e de industrializacao (5101/6101) so sai com
--    produto de producao propria, entao a busca nao lista item de compra.
create or replace function f.fn_faturamento_buscar_itens(
  p_tenant_id uuid, p_empresa_id uuid, p_termo text, p_limite integer default 20
)
returns table(id integer, codigo text, nome text, unidade text, valor_unitario numeric)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
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
    coalesce(i.preco_unitario, 0)::numeric
  from public.itens i
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
$$;

-- 5. Lista de Estoque > Cadastro: devolve a flag e a OS de origem para o badge
--    e aceita p_fabricado. O tipo de retorno muda, entao a funcao e recriada.
drop function if exists public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text);
-- Assinatura nova tambem, para a migration poder ser reaplicada num banco onde ja rodou.
drop function if exists public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text, boolean);

create function public.search_cadastro_itens(
  p_tenant_id uuid, p_empresa_id uuid, p_item_id integer default null, p_codigo text default null,
  p_produto text default null, p_fornecedor text default null, p_tipo text default null,
  p_finalidade text default null, p_ativo_only boolean default false, p_page integer default 1,
  p_page_size integer default 100, p_sort_key text default 'nome', p_sort_dir text default 'asc',
  p_fabricado boolean default null
)
returns table(
  total_count bigint, id integer, codigo_interno text, codigo_barras text, nome text, descricao text,
  tipo text, categoria text, subcategoria text, fabricante text, finalidade text, motivo_compra_id uuid,
  unidade_medida text, unidade_compra text, fator_conversao_estoque numeric, peso_liquido numeric,
  controla_estoque boolean, estoque_minimo numeric, estoque_maximo numeric, estoque_ideal numeric,
  custo_ultima_compra numeric, custo_medio numeric, preco_unitario numeric, fornecedor_id integer,
  fornecedor_nome text, ativo boolean, criado_em timestamp without time zone, criado_por text,
  atualizado_em timestamp without time zone, atualizado_por text,
  fabricado boolean, origem_os_id integer, origem_os_numero text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_codigo text := nullif(btrim(coalesce(p_codigo, '')), '');
  v_produto text := nullif(btrim(coalesce(p_produto, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_tipo text := nullif(btrim(coalesce(p_tipo, '')), '');
  v_finalidade text := nullif(btrim(coalesce(p_finalidade, '')), '');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 100), 200));
  v_sort_key text := lower(coalesce(p_sort_key, 'nome'));
  v_sort_dir text := lower(coalesce(p_sort_dir, 'asc'));
  v_codigo_exato boolean := v_codigo ~ '^[0-9]+$';
  v_papel text := a.fn_current_empresa_papel(p_tenant_id, p_empresa_id);
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or coalesce(v_papel, '') not in (
       'ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO',
       'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH'
     ) then
    raise exception 'cadastro_item_search_access_denied';
  end if;

  if v_sort_key not in ('id', 'codigo_interno', 'nome', 'tipo', 'finalidade', 'fornecedor', 'ativo') then
    v_sort_key := 'nome';
  end if;
  if v_sort_dir not in ('asc', 'desc') then
    v_sort_dir := 'asc';
  end if;

  return query
  with filtered as (
    select
      i.id,
      i.codigo_interno::text,
      i.codigo_barras::text,
      i.nome::text,
      i.descricao,
      i.tipo::text,
      i.categoria::text,
      i.subcategoria::text,
      i.fabricante::text,
      i.finalidade::text,
      i.motivo_compra_id,
      i.unidade_medida::text,
      i.unidade_compra::text,
      i.fator_conversao_estoque,
      i.peso_liquido,
      i.controla_estoque,
      i.estoque_minimo::numeric,
      i.estoque_maximo::numeric,
      i.estoque_ideal::numeric,
      i.custo_ultima_compra,
      i.custo_medio,
      i.preco_unitario,
      i.fornecedor_id,
      f.nome::text as fornecedor_nome,
      i.ativo,
      i.criado_em,
      i.criado_por::text,
      i.atualizado_em,
      i.atualizado_por::text,
      coalesce(i.fabricado, false) as fabricado,
      i.origem_os_id,
      os.numero_os::text as origem_os_numero
    from public.itens i
    left join public.fornecedores f
      on f.tenant_id = i.tenant_id
     and f.empresa_id = i.empresa_id
     and f.id = i.fornecedor_id
    left join public.ordens_servico os
      on os.tenant_id = i.tenant_id
     and os.empresa_id = i.empresa_id
     and os.id = i.origem_os_id
    where i.tenant_id = p_tenant_id
      and i.empresa_id = p_empresa_id
      and (p_item_id is null or i.id = p_item_id)
      and (
        v_codigo is null
        or (v_codigo_exato and (i.codigo_interno = v_codigo or i.codigo_barras = v_codigo))
        or (not v_codigo_exato and (i.codigo_interno ilike '%' || v_codigo || '%' or i.codigo_barras ilike '%' || v_codigo || '%'))
      )
      and (v_produto is null or i.nome ilike '%' || v_produto || '%')
      and (v_fornecedor is null or f.nome ilike '%' || v_fornecedor || '%')
      and (v_tipo is null or i.tipo::text = v_tipo)
      and (v_finalidade is null or i.finalidade::text = v_finalidade)
      and (p_fabricado is null or coalesce(i.fabricado, false) = p_fabricado)
      and (not coalesce(p_ativo_only, false) or i.ativo is true)
  ), counted as (
    select count(*) over () as total_count, filtered.*
    from filtered
  )
  select counted.*
  from counted
  order by
    case when v_sort_key = 'id' and v_sort_dir = 'asc' then counted.id end asc,
    case when v_sort_key = 'id' and v_sort_dir = 'desc' then counted.id end desc,
    case when v_sort_key = 'codigo_interno' and v_sort_dir = 'asc' then lower(counted.codigo_interno) end asc,
    case when v_sort_key = 'codigo_interno' and v_sort_dir = 'desc' then lower(counted.codigo_interno) end desc,
    case when v_sort_key = 'nome' and v_sort_dir = 'asc' then lower(counted.nome) end asc,
    case when v_sort_key = 'nome' and v_sort_dir = 'desc' then lower(counted.nome) end desc,
    case when v_sort_key = 'tipo' and v_sort_dir = 'asc' then lower(counted.tipo) end asc,
    case when v_sort_key = 'tipo' and v_sort_dir = 'desc' then lower(counted.tipo) end desc,
    case when v_sort_key = 'finalidade' and v_sort_dir = 'asc' then lower(counted.finalidade) end asc,
    case when v_sort_key = 'finalidade' and v_sort_dir = 'desc' then lower(counted.finalidade) end desc,
    case when v_sort_key = 'fornecedor' and v_sort_dir = 'asc' then lower(counted.fornecedor_nome) end asc,
    case when v_sort_key = 'fornecedor' and v_sort_dir = 'desc' then lower(counted.fornecedor_nome) end desc,
    case when v_sort_key = 'ativo' and v_sort_dir = 'asc' then counted.ativo end asc,
    case when v_sort_key = 'ativo' and v_sort_dir = 'desc' then counted.ativo end desc,
    counted.id desc
  offset ((v_page - 1) * v_page_size)
  limit v_page_size;
end;
$$;

revoke all on function public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text, boolean) from public, anon;
grant execute on function public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text, boolean) to authenticated, service_role;

-- A funcao foi recriada com outra assinatura: o PostgREST precisa reler o schema.
notify pgrst, 'reload schema';
