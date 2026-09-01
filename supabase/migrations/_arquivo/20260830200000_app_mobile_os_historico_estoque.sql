-- Lista de OS agrupada, historico operacional e consulta de estoque do app.
-- Todas as leituras sao limitadas ao tenant/empresa da sessao. Valores
-- comerciais sao decididos no banco e nunca retornam para papeis de campo.

create or replace function public.app_mobile_pode_ver_valores_os(
  p_tenant_id uuid default public.current_tenant_id(),
  p_empresa_id uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, a
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     and coalesce(a.fn_current_empresa_papel(p_tenant_id, p_empresa_id), '')
         in ('ADMIN', 'DIRETOR', 'FATURAMENTO', 'FINANCEIRO', 'COMERCIAL');
$$;

create or replace function public.app_mobile_status_os_compativel(
  p_status_fluxo text,
  p_status_legado text,
  p_status text[]
)
returns boolean
language sql
stable
set search_path = pg_catalog, public
as $$
  select case
    when coalesce(cardinality(p_status), 0) = 0 then true
    else exists (
      select 1
      from unnest(p_status) as filtro(status)
      where case lower(filtro.status)
        when 'em_andamento' then coalesce(
          nullif(lower(p_status_fluxo), ''),
          public.mapear_status_legado_para_fluxo(p_status_legado)
        ) in ('em_andamento', 'em_andamento_garantia')
        when 'concluida' then coalesce(
          nullif(lower(p_status_fluxo), ''),
          public.mapear_status_legado_para_fluxo(p_status_legado)
        ) in ('concluida', 'concluida_garantia')
        when 'faturada' then coalesce(
          nullif(lower(p_status_fluxo), ''),
          public.mapear_status_legado_para_fluxo(p_status_legado)
        ) = 'faturada'
        else false
      end
    )
  end;
$$;

create or replace function public.app_os_agrupado_cliente(
  p_status text[] default array['em_andamento']::text[],
  p_busca text default null
)
returns table (
  cliente_id integer,
  cliente_nome text,
  quantidade_os integer,
  quantidade_sem_oc integer,
  responsaveis text[],
  quantidade_faturadas integer,
  total_horas numeric,
  valor_total numeric,
  valor_faturado numeric,
  pode_ver_valores boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, f, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_valores boolean;
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar ordens de servico no app.';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_status, '{}'::text[])) as filtro(status)
    where lower(filtro.status) not in ('em_andamento', 'concluida', 'faturada')
  ) then
    raise exception 'Filtro de status invalido.';
  end if;

  v_pode_ver_valores := public.app_mobile_pode_ver_valores_os(v_tenant_id, v_empresa_id);

  return query
  with os_filtradas as (
    select
      os.id,
      os.cliente_id,
      coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cliente.nome), ''), 'Cliente nao informado')::text as cliente_nome,
      os.pedido_compra,
      coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) as status_fluxo,
      coalesce(horas.total_horas, 0)::numeric as total_horas,
      coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text as responsavel_nome,
      case
        when coalesce(os.usa_relatorio_hh, false) then coalesce(valor_hh.total_hh, 0)
        else coalesce(os.orcado, 0)
      end::numeric as valor_pedido,
      coalesce(documentos.valor_faturado, 0)::numeric as valor_faturado
    from public.ordens_servico as os
    left join public.clientes as cliente
      on cliente.id = os.cliente_id
     and cliente.tenant_id = v_tenant_id
     and cliente.empresa_id = v_empresa_id
    left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
    left join a.usuario as usuario
      on usuario.auth_user_id = os.responsavel_aprovacao_id
     and usuario.ativo is true
     and usuario.deleted_at is null
    left join public.colaboradores as colaborador
      on colaborador.user_id = os.responsavel_aprovacao_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
     and colaborador.ativo is true
    left join lateral (
      select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
      from public.apontamentos_horas as apontamento
      where apontamento.os_id = os.id
        and apontamento.tenant_id = v_tenant_id
        and apontamento.empresa_id = v_empresa_id
    ) as horas on true
    left join lateral (
      select coalesce(sum(resumo.total_hh), 0)::numeric as total_hh
      from public.vw_hh_total_os as resumo
      where resumo.os_id = os.id
        and resumo.tenant_id = v_tenant_id
        and resumo.empresa_id = v_empresa_id
    ) as valor_hh on true
    left join lateral (
      select coalesce(sum(documento.valor_total), 0)::numeric as valor_faturado
      from f.documento_fiscal as documento
      where documento.tenant_id = v_tenant_id
        and documento.empresa_id = v_empresa_id
        and documento.os_id_import = os.id
        and documento.operacao = 'SAIDA'
        and documento.deleted_at is null
        and (
          (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
          or (
            upper(coalesce(documento.modelo, '')) <> 'NFSE'
            and (nullif(btrim(documento.nfe_status), '') is null or upper(documento.nfe_status) = 'EMITIDA')
          )
        )
    ) as documentos on true
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and coalesce(os.tipo_documento, 'OS') = 'OS'
      and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, p_status)
      and (
        v_busca is null
        or os.numero_os ilike '%' || v_busca || '%'
        or os.os_num::text ilike '%' || v_busca || '%'
        or os.cliente_nome ilike '%' || v_busca || '%'
        or cliente.nome ilike '%' || v_busca || '%'
        or os.descricao_servico ilike '%' || v_busca || '%'
      )
  )
  select
    filtrada.cliente_id,
    filtrada.cliente_nome,
    count(*)::integer as quantidade_os,
    count(*) filter (where nullif(btrim(filtrada.pedido_compra), '') is null)::integer as quantidade_sem_oc,
    coalesce(
      array_agg(distinct filtrada.responsavel_nome order by filtrada.responsavel_nome)
        filter (where filtrada.responsavel_nome is not null),
      '{}'::text[]
    ) as responsaveis,
    count(*) filter (where filtrada.status_fluxo = 'faturada')::integer as quantidade_faturadas,
    sum(filtrada.total_horas)::numeric as total_horas,
    case when v_pode_ver_valores then sum(filtrada.valor_pedido)::numeric else null::numeric end as valor_total,
    case when v_pode_ver_valores then sum(filtrada.valor_faturado)::numeric else null::numeric end as valor_faturado,
    v_pode_ver_valores as pode_ver_valores
  from os_filtradas as filtrada
  group by filtrada.cliente_id, filtrada.cliente_nome
  order by lower(filtrada.cliente_nome), filtrada.cliente_id nulls last;
end;
$$;

create or replace function public.app_os_do_cliente(
  p_cliente_id integer,
  p_status text[] default array['em_andamento']::text[]
)
returns table (
  id integer,
  numero_os character varying,
  os_num bigint,
  cliente_id integer,
  cliente_nome text,
  descricao_servico text,
  status_legado character varying,
  status_fluxo text,
  usa_relatorio_hh boolean,
  total_horas numeric,
  responsavel_nome text,
  situacao_margem text,
  pedido_compra text,
  pendencias_aprovacao integer,
  garantia_motivo text,
  faturado_em timestamptz,
  faturada_presumida_legado boolean,
  pode_concluir boolean,
  pode_faturar boolean,
  pode_reabrir_garantia boolean,
  pode_concluir_garantia boolean,
  valor_total numeric,
  valor_faturado numeric,
  pode_ver_valores boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, f, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_valores boolean;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar ordens de servico no app.';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_status, '{}'::text[])) as filtro(status)
    where lower(filtro.status) not in ('em_andamento', 'concluida', 'faturada')
  ) then
    raise exception 'Filtro de status invalido.';
  end if;

  v_pode_ver_valores := public.app_mobile_pode_ver_valores_os(v_tenant_id, v_empresa_id);

  return query
  select
    os.id,
    os.numero_os,
    os.os_num,
    os.cliente_id,
    coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cliente.nome), ''), 'Cliente nao informado')::text,
    os.descricao_servico,
    os.status,
    coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status))::text,
    coalesce(os.usa_relatorio_hh, false),
    coalesce(horas.total_horas, 0)::numeric,
    coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text,
    null::text,
    os.pedido_compra::text,
    coalesce(pendencias.quantidade, 0)::integer,
    os.garantia_motivo,
    os.faturado_em,
    os.faturada_presumida_legado,
    v_papel in ('ADMIN', 'DIRETOR', 'COORDENACAO'),
    v_papel = 'FINANCEIRO' and documentos.valor_faturado > 0,
    v_papel in ('COORDENACAO', 'FINANCEIRO')
      and os.status_fluxo = 'faturada'
      and not coalesce(os.faturada_presumida_legado, false)
      and os.faturado_em is not null
      and os.faturado_em >= now() - interval '6 months',
    v_papel = 'COORDENACAO',
    case
      when v_pode_ver_valores then
        case when coalesce(os.usa_relatorio_hh, false) then coalesce(valor_hh.total_hh, 0) else coalesce(os.orcado, 0) end
      else null::numeric
    end::numeric,
    case when v_pode_ver_valores then documentos.valor_faturado else null::numeric end::numeric,
    v_pode_ver_valores
  from public.ordens_servico as os
  left join public.clientes as cliente
    on cliente.id = os.cliente_id
   and cliente.tenant_id = v_tenant_id
   and cliente.empresa_id = v_empresa_id
  left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
  left join a.usuario as usuario
    on usuario.auth_user_id = os.responsavel_aprovacao_id
   and usuario.ativo is true
   and usuario.deleted_at is null
  left join public.colaboradores as colaborador
    on colaborador.user_id = os.responsavel_aprovacao_id
   and colaborador.tenant_id = v_tenant_id
   and colaborador.empresa_id = v_empresa_id
   and colaborador.ativo is true
  left join lateral (
    select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
    from public.apontamentos_horas as apontamento
    where apontamento.os_id = os.id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
  ) as horas on true
  left join lateral (
    select count(*)::integer as quantidade
    from public.apontamentos_horas as apontamento
    where apontamento.os_id = os.id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.status_aprovacao = 'pendente'
  ) as pendencias on true
  left join lateral (
    select coalesce(sum(resumo.total_hh), 0)::numeric as total_hh
    from public.vw_hh_total_os as resumo
    where resumo.os_id = os.id
      and resumo.tenant_id = v_tenant_id
      and resumo.empresa_id = v_empresa_id
  ) as valor_hh on true
  left join lateral (
    select coalesce(sum(documento.valor_total), 0)::numeric as valor_faturado
    from f.documento_fiscal as documento
    where documento.tenant_id = v_tenant_id
      and documento.empresa_id = v_empresa_id
      and documento.os_id_import = os.id
      and documento.operacao = 'SAIDA'
      and documento.deleted_at is null
      and (
        (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
        or (
          upper(coalesce(documento.modelo, '')) <> 'NFSE'
          and (nullif(btrim(documento.nfe_status), '') is null or upper(documento.nfe_status) = 'EMITIDA')
        )
      )
  ) as documentos on true
  where os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and coalesce(os.tipo_documento, 'OS') = 'OS'
    and (os.cliente_id = p_cliente_id or (os.cliente_id is null and p_cliente_id is null))
    and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, p_status)
  order by os.data_abertura desc nulls last, os.id desc;
end;
$$;

create or replace function public.app_historico_lancamentos(
  p_tipo text default 'tudo',
  p_de date default (current_date - 29),
  p_ate date default current_date,
  p_colaborador_id uuid default null,
  p_os_id integer default null,
  p_limite integer default 40,
  p_cursor text default null
)
returns table (
  tipo text,
  origem_id text,
  criado_em timestamptz,
  data_lancamento date,
  os_id integer,
  numero_os text,
  cliente_nome text,
  descricao text,
  quantidade numeric,
  unidade text,
  status text,
  nao_cobrado boolean,
  autor_id uuid,
  autor_nome text,
  pode_ver_autoria boolean,
  cursor text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_colaborador_id uuid;
  v_apontador boolean;
  v_tipo text := lower(coalesce(nullif(btrim(p_tipo), ''), 'tudo'));
  v_de date := coalesce(p_de, current_date - 29);
  v_ate date := coalesce(p_ate, current_date);
  v_limite integer := greatest(1, least(coalesce(p_limite, 40), 100));
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar o historico do app.';
  end if;

  if v_tipo not in ('tudo', 'horas', 'materiais') then
    raise exception 'Tipo de historico invalido.';
  end if;
  if v_de > v_ate then
    raise exception 'Periodo de historico invalido.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true
  limit 1;

  v_apontador := v_papel in ('TECNICO', 'APONTAMENTO_RH', 'APONTADOR');
  if v_apontador and v_colaborador_id is null then
    raise exception 'Seu usuario nao esta vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  with lancamentos as (
    select
      'hora'::text as tipo,
      apontamento.id::text as origem_id,
      apontamento.criado_em::timestamptz as criado_em,
      apontamento.data as data_lancamento,
      os.id as os_id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text as numero_os,
      coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text as cliente_nome,
      coalesce(nullif(btrim(os.descricao_servico), ''), nullif(btrim(apontamento.descricao), ''), 'Apontamento de horas')::text as descricao,
      apontamento.horas::numeric as quantidade,
      'h'::text as unidade,
      coalesce(nullif(btrim(apontamento.status_aprovacao), ''), nullif(btrim(apontamento.status), ''), 'pendente')::text as status,
      false as nao_cobrado,
      apontamento.colaborador_id as autor_id,
      colaborador.nome::text as autor_nome
    from public.apontamentos_horas as apontamento
    join public.ordens_servico as os
      on os.id = apontamento.os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
    where apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.data between v_de and v_ate
      and v_tipo in ('tudo', 'horas')
      and (p_os_id is null or apontamento.os_id = p_os_id)
      and (
        case when v_apontador then apontamento.colaborador_id = v_colaborador_id
             else p_colaborador_id is null or apontamento.colaborador_id = p_colaborador_id end
      )

    union all

    select
      'material'::text,
      movimentacao.id::text,
      coalesce(movimentacao.created_at, movimentacao.data_movimentacao)::timestamptz,
      movimentacao.data_movimentacao::date,
      os.id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text,
      coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text,
      (coalesce(nullif(btrim(item.nome), ''), nullif(btrim(item.descricao), ''), 'Material')
        || case when nullif(btrim(item.codigo_interno), '') is not null then ' - cod. ' || item.codigo_interno else '' end)::text,
      movimentacao.quantidade::numeric,
      coalesce(nullif(btrim(item.unidade_medida), ''), 'un')::text,
      'baixado'::text,
      coalesce(item_os.nao_cobrado, false),
      autor.id,
      autor.nome::text
    from public.movimentacoes as movimentacao
    join public.ordens_servico as os
      on os.id = movimentacao.origem_os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.itens as item
      on item.id = movimentacao.item_id
     and item.tenant_id = v_tenant_id
     and item.empresa_id = v_empresa_id
    left join lateral (
      select
        colaborador.id,
        colaborador.nome
      from public.colaboradores as colaborador
      where colaborador.tenant_id = v_tenant_id
        and colaborador.empresa_id = v_empresa_id
        and colaborador.ativo is true
        and (
          colaborador.user_id::text = movimentacao.realizado_por
          or lower(coalesce(colaborador.email, '')) = lower(coalesce(movimentacao.realizado_por, ''))
        )
      order by case when colaborador.user_id::text = movimentacao.realizado_por then 0 else 1 end
      limit 1
    ) as autor on true
    left join lateral (
      select public.os_lancamento_nao_cobrado(
        v_tenant_id,
        v_empresa_id,
        item_lancado.os_id,
        item_lancado.criado_em
      ) as nao_cobrado
      from public.os_itens as item_lancado
      where item_lancado.tenant_id = v_tenant_id
        and item_lancado.empresa_id = v_empresa_id
        and item_lancado.os_id = movimentacao.origem_os_id
        and item_lancado.item_id = movimentacao.item_id
        and abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))) <= 600
      order by abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))), item_lancado.id desc
      limit 1
    ) as item_os on true
    where movimentacao.tenant_id = v_tenant_id
      and movimentacao.empresa_id = v_empresa_id
      and movimentacao.tipo = 'saida'
      and movimentacao.motivo like 'Material lançado pelo app na OS %'
      and movimentacao.data_movimentacao::date between v_de and v_ate
      and v_tipo in ('tudo', 'materiais')
      and (p_os_id is null or movimentacao.origem_os_id = p_os_id)
      and (
        case when v_apontador then autor.id = v_colaborador_id
             else p_colaborador_id is null or autor.id = p_colaborador_id end
      )
  ), com_cursor as (
    select
      lancamento.*,
      to_char(lancamento.criado_em at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
        || '|' || lancamento.tipo || '|' || lancamento.origem_id as chave_cursor
    from lancamentos as lancamento
  )
  select
    lancamento.tipo,
    lancamento.origem_id,
    lancamento.criado_em,
    lancamento.data_lancamento,
    lancamento.os_id,
    lancamento.numero_os,
    lancamento.cliente_nome,
    lancamento.descricao,
    lancamento.quantidade,
    lancamento.unidade,
    lancamento.status,
    lancamento.nao_cobrado,
    case when v_apontador then null::uuid else lancamento.autor_id end,
    case when v_apontador then null::text else lancamento.autor_nome end,
    not v_apontador,
    lancamento.chave_cursor
  from com_cursor as lancamento
  where p_cursor is null or lancamento.chave_cursor < p_cursor
  order by lancamento.chave_cursor desc
  limit v_limite;
end;
$$;

create or replace function public.app_consultar_estoque(
  p_busca text default null,
  p_apenas_disponiveis boolean default true,
  p_limite integer default 60,
  p_offset integer default 0
)
returns table (
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade_disponivel numeric,
  localizacao text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_limite integer := greatest(1, least(coalesce(p_limite, 60), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar o estoque no app.';
  end if;

  return query
  select
    item.id,
    item.codigo_interno::text,
    coalesce(nullif(btrim(item.nome), ''), nullif(btrim(item.descricao), ''), 'Item sem nome')::text,
    coalesce(nullif(btrim(item.unidade_medida), ''), 'un')::text,
    coalesce(estoque.quantidade_atual, 0)::numeric,
    estoque.localizacao::text
  from public.itens as item
  left join public.estoque as estoque
    on estoque.item_id = item.id
   and estoque.tenant_id = v_tenant_id
   and estoque.empresa_id = v_empresa_id
  where item.tenant_id = v_tenant_id
    and item.empresa_id = v_empresa_id
    and item.ativo is true
    and item.tipo = 'produto'
    and item.controla_estoque is true
    and (not coalesce(p_apenas_disponiveis, true) or coalesce(estoque.quantidade_atual, 0) > 0)
    and (
      v_busca is null
      or item.id::text = v_busca
      or item.codigo_interno ilike '%' || v_busca || '%'
      or item.codigo_barras ilike '%' || v_busca || '%'
      or item.nome ilike '%' || v_busca || '%'
      or item.descricao ilike '%' || v_busca || '%'
      or item.fabricante ilike '%' || v_busca || '%'
    )
  order by lower(coalesce(item.nome, item.descricao)), item.id
  limit v_limite
  offset v_offset;
end;
$$;

create index if not exists idx_apontamentos_historico_mobile
  on public.apontamentos_horas (tenant_id, empresa_id, colaborador_id, criado_em desc, id desc);

create index if not exists idx_movimentacoes_historico_mobile_empresa
  on public.movimentacoes (tenant_id, empresa_id, created_at desc, id desc)
  where origem_os_id is not null and motivo like 'Material lançado pelo app na OS %';

create index if not exists idx_movimentacoes_historico_mobile_autor
  on public.movimentacoes (tenant_id, empresa_id, realizado_por, created_at desc, id desc)
  where origem_os_id is not null and motivo like 'Material lançado pelo app na OS %';

revoke all on function public.app_mobile_pode_ver_valores_os(uuid, uuid) from public, anon, authenticated;
revoke all on function public.app_mobile_status_os_compativel(text, text, text[]) from public, anon, authenticated;
revoke all on function public.app_os_agrupado_cliente(text[], text) from public, anon, authenticated;
revoke all on function public.app_os_do_cliente(integer, text[]) from public, anon, authenticated;
revoke all on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) from public, anon, authenticated;
revoke all on function public.app_consultar_estoque(text, boolean, integer, integer) from public, anon, authenticated;

grant execute on function public.app_mobile_pode_ver_valores_os(uuid, uuid) to authenticated, service_role;
grant execute on function public.app_mobile_status_os_compativel(text, text, text[]) to authenticated, service_role;
grant execute on function public.app_os_agrupado_cliente(text[], text) to authenticated, service_role;
grant execute on function public.app_os_do_cliente(integer, text[]) to authenticated, service_role;
grant execute on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) to authenticated, service_role;
grant execute on function public.app_consultar_estoque(text, boolean, integer, integer) to authenticated, service_role;
