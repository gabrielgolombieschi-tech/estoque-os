begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

-- Leitura da Home: os indices cobrem apenas os recortes operacionais usados
-- pelo painel e preservam o isolamento tenant + empresa.
create index if not exists idx_home_apontamentos_escopo_data
  on public.apontamentos_horas (tenant_id, empresa_id, colaborador_id, data desc)
  where status <> 'devolvido';

create index if not exists idx_home_movimentacoes_escopo_data
  on public.movimentacoes (tenant_id, empresa_id, data_movimentacao desc);

create index if not exists idx_home_os_escopo_fluxo_abertura
  on public.ordens_servico (tenant_id, empresa_id, tipo_documento, status_fluxo, data_abertura desc);

create or replace function public.home_sala_controle()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_auth_uid uuid := auth.uid();
  v_colaborador_id uuid;
  v_mes_inicio date := date_trunc('month', current_date)::date;
  v_mes_fim date := (date_trunc('month', current_date) + interval '1 month - 1 day')::date;
  v_dias_uteis_ate_ontem integer := 0;

  v_can_os boolean := false;
  v_can_os_write boolean := false;
  v_can_apontamentos boolean := false;
  v_can_estoque boolean := false;
  v_can_financeiro boolean := false;
  v_can_financeiro_write boolean := false;
  v_can_faturamento boolean := false;
  v_can_admin boolean := false;

  v_contexto jsonb := '{}'::jsonb;
  v_horas_proprias jsonb := '{}'::jsonb;
  v_os jsonb;
  v_os_proprias jsonb := '[]'::jsonb;
  v_horas_equipe jsonb;
  v_estoque jsonb;
  v_financeiro jsonb;
  v_faturamento jsonb;
  v_admin jsonb;
begin
  if v_auth_uid is null then
    raise exception 'home_usuario_nao_autenticado';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id__by_tenant(v_tenant_id);

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'home_contexto_empresa_invalido';
  end if;

  v_can_os := public.can('os', 'read', v_tenant_id);
  v_can_os_write := public.can('os', 'write', v_tenant_id);
  v_can_apontamentos := public.can('apontamentos', 'read', v_tenant_id);
  v_can_estoque := public.can('estoque', 'read', v_tenant_id);
  v_can_financeiro := public.can('financeiro', 'read', v_tenant_id);
  v_can_financeiro_write := public.can('financeiro', 'write', v_tenant_id);
  v_can_faturamento := public.can('faturamento', 'read', v_tenant_id);
  v_can_admin := public.can('admin', 'manage_users', v_tenant_id)
    or public.can('admin', 'users.manage', v_tenant_id);

  select c.id
    into v_colaborador_id
  from public.colaboradores c
  where c.tenant_id = v_tenant_id
    and c.empresa_id = v_empresa_id
    and c.user_id = v_auth_uid
    and c.ativo = true
  order by c.criado_em desc
  limit 1;

  select jsonb_build_object(
    'empresa_nome', coalesce(e.nome_fantasia, e.razao_social, 'Empresa'),
    'usuario_nome', coalesce(u.nome, split_part(coalesce(u.email, ''), '@', 1), 'Usuário'),
    'papel', coalesce(a.fn_current_empresa_papel(v_tenant_id, v_empresa_id), ''),
    'competencia_status', coalesce(comp.status, 'aberta'),
    'competencia_ano', extract(year from current_date)::integer,
    'competencia_mes', extract(month from current_date)::integer,
    'colaborador_vinculado', v_colaborador_id is not null
  )
  into v_contexto
  from c.empresa e
  left join a.usuario u
    on u.auth_user_id = v_auth_uid
   and u.ativo = true
   and u.deleted_at is null
  left join public.competencias comp
    on comp.tenant_id = v_tenant_id
   and comp.empresa_id = v_empresa_id
   and comp.ano = extract(year from current_date)::integer
   and comp.mes = extract(month from current_date)::integer
  where e.id = v_empresa_id
    and e.tenant_id = v_tenant_id
    and e.deleted_at is null
  limit 1;

  with dias_uteis as (
    select serie.d::date as data
    from generate_series(
      v_mes_inicio::timestamp,
      least(current_date - 1, v_mes_fim)::timestamp,
      interval '1 day'
    ) as serie(d)
    where extract(isodow from serie.d) between 1 and 5
      and not exists (
        select 1
        from public.feriados f
        where f.data = serie.d::date
      )
  )
  select count(*)::integer into v_dias_uteis_ate_ontem from dias_uteis;

  if v_colaborador_id is not null then
    with dias_mes as (
      select serie.d::date as data
      from generate_series(v_mes_inicio::timestamp, current_date::timestamp, interval '1 day') as serie(d)
      where extract(isodow from serie.d) between 1 and 5
        and not exists (select 1 from public.feriados f where f.data = serie.d::date)
    ),
    totais_dia as (
      select ah.data, sum(ah.horas)::numeric as horas
      from public.apontamentos_horas ah
      where ah.tenant_id = v_tenant_id
        and ah.empresa_id = v_empresa_id
        and ah.colaborador_id = v_colaborador_id
        and ah.data between v_mes_inicio and current_date
        and ah.status <> 'devolvido'
      group by ah.data
    ),
    serie as (
      select d.data, coalesce(t.horas, 0)::numeric as horas
      from dias_mes d
      left join totais_dia t on t.data = d.data
      order by d.data
    ),
    resumo as (
      select
        coalesce(sum(ah.horas), 0)::numeric as total_horas,
        count(distinct ah.data)::integer as dias_com_horas
      from public.apontamentos_horas ah
      where ah.tenant_id = v_tenant_id
        and ah.empresa_id = v_empresa_id
        and ah.colaborador_id = v_colaborador_id
        and ah.data between v_mes_inicio and current_date
        and ah.status <> 'devolvido'
    ),
    por_os as (
      select coalesce(jsonb_agg(jsonb_build_object(
        'os_id', q.os_id,
        'numero_os', q.numero_os,
        'cliente', q.cliente_nome,
        'horas', q.horas
      ) order by q.horas desc), '[]'::jsonb) as itens
      from (
        select os.id as os_id, os.numero_os, os.cliente_nome, sum(ah.horas)::numeric as horas
        from public.apontamentos_horas ah
        join public.ordens_servico os
          on os.id = ah.os_id
         and os.tenant_id = ah.tenant_id
         and os.empresa_id = ah.empresa_id
        where ah.tenant_id = v_tenant_id
          and ah.empresa_id = v_empresa_id
          and ah.colaborador_id = v_colaborador_id
          and ah.data between v_mes_inicio and current_date
          and ah.status <> 'devolvido'
        group by os.id, os.numero_os, os.cliente_nome
        order by sum(ah.horas) desc
        limit 5
      ) q
    )
    select jsonb_build_object(
      'total', r.total_horas,
      'dias_com_horas', r.dias_com_horas,
      'dias_uteis_decorridos', v_dias_uteis_ate_ontem,
      'dias_em_branco', (
        select count(*)::integer
        from serie s
        where s.data < current_date and s.horas = 0
      ),
      'serie_diaria', coalesce((
        select jsonb_agg(jsonb_build_object('data', s.data, 'horas', s.horas) order by s.data)
        from serie s
      ), '[]'::jsonb),
      'por_os', por_os.itens
    )
    into v_horas_proprias
    from resumo r
    cross join por_os;

    select coalesce(jsonb_agg(jsonb_build_object(
      'os_id', q.os_id,
      'numero_os', q.numero_os,
      'cliente', q.cliente_nome,
      'descricao', q.descricao_servico,
      'status_fluxo', q.status_fluxo,
      'ultima_atividade', q.ultima_atividade,
      'horas_mes', q.horas_mes
    ) order by q.ultima_atividade desc nulls last), '[]'::jsonb)
    into v_os_proprias
    from (
      select
        os.id as os_id,
        os.numero_os,
        os.cliente_nome,
        os.descricao_servico,
        coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status)) as status_fluxo,
        max(ah.data) as ultima_atividade,
        coalesce(sum(ah.horas) filter (where ah.data between v_mes_inicio and current_date), 0)::numeric as horas_mes
      from public.apontamentos_horas ah
      join public.ordens_servico os
        on os.id = ah.os_id
       and os.tenant_id = ah.tenant_id
       and os.empresa_id = ah.empresa_id
      where ah.tenant_id = v_tenant_id
        and ah.empresa_id = v_empresa_id
        and ah.colaborador_id = v_colaborador_id
        and ah.status <> 'devolvido'
        and os.tipo_documento = 'OS'
        and coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status))
          in ('em_andamento', 'em_andamento_garantia')
      group by os.id, os.numero_os, os.cliente_nome, os.descricao_servico, os.status_fluxo, os.status
      order by max(ah.data) desc nulls last
      limit 5
    ) q;
  else
    v_horas_proprias := jsonb_build_object(
      'total', 0,
      'dias_com_horas', 0,
      'dias_uteis_decorridos', v_dias_uteis_ate_ontem,
      'dias_em_branco', 0,
      'serie_diaria', '[]'::jsonb,
      'por_os', '[]'::jsonb
    );
  end if;

  if v_can_os then
    with base as (
      select
        os.*,
        coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status)) as fluxo
      from public.ordens_servico os
      where os.tenant_id = v_tenant_id
        and os.empresa_id = v_empresa_id
        and os.tipo_documento = 'OS'
    ),
    andamento as (
      select * from base where fluxo in ('em_andamento', 'em_andamento_garantia')
    ),
    por_status as (
      select coalesce(fluxo, 'indefinido') as fluxo, count(*)::integer as quantidade
      from base
      group by coalesce(fluxo, 'indefinido')
    ),
    paradas as (
      select
        a.id,
        greatest(
          coalesce(a.data_abertura, timestamp '2000-01-01'),
          coalesce((select max(ah.criado_em)::timestamp from public.apontamentos_horas ah
                    where ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id and ah.os_id = a.id), timestamp '2000-01-01'),
          coalesce((select max(oi.criado_em) from public.os_itens oi
                    where oi.tenant_id = v_tenant_id and oi.empresa_id = v_empresa_id and oi.os_id = a.id), timestamp '2000-01-01')
        )::date as ultima_atividade
      from andamento a
    )
    select jsonb_build_object(
      'em_andamento', (select count(*)::integer from andamento),
      'clientes', (select count(distinct cliente_id)::integer from andamento where cliente_id is not null),
      'garantia', (select count(*)::integer from andamento where fluxo = 'em_andamento_garantia'),
      'paradas_90_dias', (select count(*)::integer from paradas where current_date - ultima_atividade > 90),
      'maior_parada_dias', coalesce((select max(current_date - ultima_atividade)::integer from paradas), 0),
      'por_status', coalesce((select jsonb_object_agg(fluxo, quantidade) from por_status), '{}'::jsonb)
    )
    into v_os;
  end if;

  if v_can_os_write then
    v_os := coalesce(v_os, '{}'::jsonb) || jsonb_build_object(
      'sem_pedido', (
        select count(*)::integer
        from public.ordens_servico os
        where os.tenant_id = v_tenant_id
          and os.empresa_id = v_empresa_id
          and os.tipo_documento = 'OS'
          and coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status))
            in ('em_andamento', 'em_andamento_garantia')
          and nullif(btrim(coalesce(os.pedido_compra, '')), '') is null
          and (
            exists (select 1 from public.os_itens oi
                    where oi.tenant_id = v_tenant_id and oi.empresa_id = v_empresa_id and oi.os_id = os.id)
            or exists (select 1 from public.apontamentos_horas ah
                       where ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id and ah.os_id = os.id
                         and ah.status <> 'devolvido')
          )
      ),
      'sem_pedido_valor', coalesce((
        select sum(coalesce(nullif(os.orcado, 0), os.valor_total, 0))::numeric
        from public.ordens_servico os
        where os.tenant_id = v_tenant_id
          and os.empresa_id = v_empresa_id
          and os.tipo_documento = 'OS'
          and coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status))
            in ('em_andamento', 'em_andamento_garantia')
          and nullif(btrim(coalesce(os.pedido_compra, '')), '') is null
          and (
            exists (select 1 from public.os_itens oi
                    where oi.tenant_id = v_tenant_id and oi.empresa_id = v_empresa_id and oi.os_id = os.id)
            or exists (select 1 from public.apontamentos_horas ah
                       where ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id and ah.os_id = os.id
                         and ah.status <> 'devolvido')
          )
      ), 0)
    );
  end if;

  if v_can_apontamentos then
    with dias_mes as (
      select serie.d::date as data
      from generate_series(v_mes_inicio::timestamp, current_date::timestamp, interval '1 day') as serie(d)
      where extract(isodow from serie.d) between 1 and 5
        and not exists (select 1 from public.feriados f where f.data = serie.d::date)
    ),
    totais_dia as (
      select ah.data, sum(ah.horas)::numeric as horas
      from public.apontamentos_horas ah
      where ah.tenant_id = v_tenant_id
        and ah.empresa_id = v_empresa_id
        and ah.data between v_mes_inicio and current_date
        and ah.status <> 'devolvido'
      group by ah.data
    ),
    resumo as (
      select
        coalesce(sum(ah.horas), 0)::numeric as total,
        count(distinct ah.colaborador_id)::integer as colaboradores
      from public.apontamentos_horas ah
      where ah.tenant_id = v_tenant_id
        and ah.empresa_id = v_empresa_id
        and ah.data between v_mes_inicio and current_date
        and ah.status <> 'devolvido'
    ),
    faltantes as (
      select count(distinct c.id)::integer as pessoas
      from public.colaboradores c
      where c.tenant_id = v_tenant_id
        and c.empresa_id = v_empresa_id
        and c.ativo = true
        and exists (
          select 1
          from dias_mes d
          where d.data < current_date
            and not exists (
              select 1
              from public.apontamentos_horas ah
              where ah.tenant_id = v_tenant_id
                and ah.empresa_id = v_empresa_id
                and ah.colaborador_id = c.id
                and ah.data = d.data
                and ah.status <> 'devolvido'
            )
        )
    )
    select jsonb_build_object(
      'total', r.total,
      'colaboradores', r.colaboradores,
      'pessoas_com_dias_em_branco', f.pessoas,
      'serie_diaria', coalesce((
        select jsonb_agg(jsonb_build_object('data', d.data, 'horas', coalesce(t.horas, 0)) order by d.data)
        from dias_mes d
        left join totais_dia t on t.data = d.data
      ), '[]'::jsonb),
      'recentes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'tipo', 'horas',
          'data_hora', q.criado_em,
          'titulo', q.colaborador_nome || ' lançou ' || trim(to_char(q.horas, 'FM999990D00')) || ' h',
          'detalhe', 'OS ' || q.numero_os,
          'href', '/os/' || q.os_id::text
        ) order by q.criado_em desc)
        from (
          select ah.criado_em, ah.horas, ah.os_id, os.numero_os, c.nome as colaborador_nome
          from public.apontamentos_horas ah
          join public.colaboradores c
            on c.id = ah.colaborador_id and c.tenant_id = ah.tenant_id and c.empresa_id = ah.empresa_id
          join public.ordens_servico os
            on os.id = ah.os_id and os.tenant_id = ah.tenant_id and os.empresa_id = ah.empresa_id
          where ah.tenant_id = v_tenant_id
            and ah.empresa_id = v_empresa_id
            and ah.status <> 'devolvido'
          order by ah.criado_em desc
          limit 5
        ) q
      ), '[]'::jsonb)
    )
    into v_horas_equipe
    from resumo r
    cross join faltantes f;
  end if;

  if v_can_estoque then
    with saldos as (
      select e.item_id, sum(e.quantidade_atual)::numeric as quantidade
      from public.estoque e
      where e.tenant_id = v_tenant_id and e.empresa_id = v_empresa_id
      group by e.item_id
    )
    select jsonb_build_object(
      'itens_ativos', count(*)::integer,
      'abaixo_minimo', count(*) filter (
        where i.controla_estoque = true
          and coalesce(s.quantidade, 0) < coalesce(i.estoque_minimo, 0)
      )::integer,
      'movimentacoes_hoje', (
        select count(*)::integer
        from public.movimentacoes m
        where m.tenant_id = v_tenant_id
          and m.empresa_id = v_empresa_id
          and m.data_movimentacao::date = current_date
      ),
      'recentes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'tipo', 'estoque',
          'data_hora', q.data_movimentacao,
          'titulo', case q.tipo when 'entrada' then 'Entrada' when 'saida' then 'Saída' else 'Ajuste' end
            || ' de ' || trim(to_char(q.quantidade, 'FM999999990D000')),
          'detalhe', q.item_nome,
          'href', '/mov'
        ) order by q.data_movimentacao desc)
        from (
          select m.data_movimentacao, m.tipo, m.quantidade, i.nome as item_nome
          from public.movimentacoes m
          join public.itens i
            on i.id = m.item_id and i.tenant_id = m.tenant_id and i.empresa_id = m.empresa_id
          where m.tenant_id = v_tenant_id and m.empresa_id = v_empresa_id
          order by m.data_movimentacao desc
          limit 5
        ) q
      ), '[]'::jsonb)
    )
    into v_estoque
    from public.itens i
    left join saldos s on s.item_id = i.id
    where i.tenant_id = v_tenant_id
      and i.empresa_id = v_empresa_id
      and i.ativo = true
      and i.mesclado_em_item_id is null;
  end if;

  if v_can_financeiro then
    with posicao as (
      select *
      from f.contas_bancarias_saldos_ativos(
        v_tenant_id,
        array[v_empresa_id],
        v_mes_inicio,
        current_date,
        current_date
      )
    ),
    titulos as (
      select
        t.tipo,
        tp.vencimento_date,
        tp.valor_aberto
      from f.titulo t
      join f.titulo_parcela tp
        on tp.titulo_id = t.id
       and tp.tenant_id = t.tenant_id
       and tp.deleted_at is null
      where t.tenant_id = v_tenant_id
        and t.empresa_id = v_empresa_id
        and t.deleted_at is null
        and t.status <> 'CANCELADO'
        and tp.valor_aberto > 0
    ),
    fluxo as (
      select
        coalesce(sum(d.valor_previsto), 0)::numeric as previsto,
        coalesce(sum(d.valor_realizado), 0)::numeric as realizado
      from f.r_fluxo_caixa_diario d
      where d.tenant_id = v_tenant_id
        and d.empresa_id = v_empresa_id
        and d.data_ref between v_mes_inicio and v_mes_fim
    ),
    exposicao as (
      select
        coalesce(sum(coalesce(g.valor_confirmado, g.valor_estimado, 0)), 0)::numeric as valor,
        count(*)::integer as lancamentos,
        count(*) filter (where current_date - coalesce(g.data_competencia, g.created_at::date) > 30)::integer as parados_30_dias
      from f.gestao_cobranca_os g
      where g.tenant_id = v_tenant_id
        and g.empresa_id = v_empresa_id
        and g.deleted_at is null
        and g.status in ('ABERTO', 'OC_RECEBIDA', 'FATURADO')
    )
    select jsonb_build_object(
      'caixa', coalesce((select sum(p.saldo_atual) from posicao p where p.configurada), 0),
      'contas_bancarias', (select count(*)::integer from posicao),
      'contas_sem_conferencia', (select count(*) filter (
        where not p.configurada or p.saldo_referencia_data < current_date - 3
      )::integer from posicao p),
      'ultima_conferencia', (select max(p.saldo_referencia_data) from posicao p where p.configurada),
      'a_receber', coalesce((select sum(t.valor_aberto) from titulos t where t.tipo = 'AR'), 0),
      'a_pagar', coalesce((select sum(t.valor_aberto) from titulos t where t.tipo = 'AP'), 0),
      'posicao_liquida',
        coalesce((select sum(t.valor_aberto) from titulos t where t.tipo = 'AR'), 0)
        - coalesce((select sum(t.valor_aberto) from titulos t where t.tipo = 'AP'), 0),
      'receber_vencido_valor', coalesce((select sum(t.valor_aberto) from titulos t where t.tipo = 'AR' and t.vencimento_date < current_date), 0),
      'receber_vencido_quantidade', (select count(*)::integer from titulos t where t.tipo = 'AR' and t.vencimento_date < current_date),
      'fluxo_previsto', fl.previsto,
      'fluxo_realizado', fl.realizado,
      'exposicao_credito', ex.valor,
      'exposicao_lancamentos', ex.lancamentos,
      'exposicao_parados_30_dias', ex.parados_30_dias
    )
    into v_financeiro
    from fluxo fl
    cross join exposicao ex;

    if not v_can_financeiro_write then
      v_financeiro := v_financeiro - 'contas_sem_conferencia';
    end if;
  end if;

  if v_can_faturamento then
    select jsonb_build_object(
      'os_concluidas_sem_nf', count(*)::integer,
      'valor_concluido_sem_nf', coalesce(sum(coalesce(nullif(os.orcado, 0), os.valor_total, 0)), 0)::numeric
    )
    into v_faturamento
    from public.ordens_servico os
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.tipo_documento = 'OS'
      and coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status)) = 'concluida'
      and not exists (
        select 1
        from f.documento_fiscal df
        where df.tenant_id = v_tenant_id
          and df.empresa_id = v_empresa_id
          and df.os_id_import = os.id
          and df.operacao = 'SAIDA'
          and df.deleted_at is null
          and coalesce(df.nfe_status, df.nfse_status, 'EMITIDA') <> 'CANCELADA'
      );
  end if;

  if v_can_admin then
    select jsonb_build_object(
      'clientes_incompletos', count(*) filter (
        where nullif(btrim(coalesce(c.documento, '')), '') is null
           or nullif(btrim(coalesce(c.email_financeiro, c.email, '')), '') is null
           or nullif(btrim(coalesce(c.telefone, '')), '') is null
      )::integer
    )
    into v_admin
    from public.clientes c
    where c.tenant_id = v_tenant_id
      and c.empresa_id = v_empresa_id
      and c.ativo = true;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'gerado_em', clock_timestamp(),
    'contexto', v_contexto,
    'horas_proprias', v_horas_proprias,
    'os_proprias', v_os_proprias,
    'os', v_os,
    'horas_equipe', v_horas_equipe,
    'estoque', v_estoque,
    'financeiro', v_financeiro,
    'faturamento', v_faturamento,
    'admin', v_admin
  ));
end;
$$;

create or replace function public.home_busca_comando(p_termo text)
returns table (
  tipo text,
  titulo text,
  subtitulo text,
  href text
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_auth_uid uuid := auth.uid();
  v_colaborador_id uuid;
  v_termo text := nullif(btrim(coalesce(p_termo, '')), '');
  v_padrao text;
  v_can_os boolean;
  v_can_estoque boolean;
  v_can_apontamentos boolean;
  v_can_financeiro boolean;
  v_can_faturamento boolean;
  v_can_clientes boolean;
begin
  if v_auth_uid is null then
    raise exception 'home_usuario_nao_autenticado';
  end if;

  if v_termo is null or length(v_termo) < 2 then
    return;
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id__by_tenant(v_tenant_id);

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'home_contexto_empresa_invalido';
  end if;

  v_padrao := '%' || v_termo || '%';
  v_can_os := public.can('os', 'read', v_tenant_id);
  v_can_estoque := public.can('estoque', 'read', v_tenant_id);
  v_can_apontamentos := public.can('apontamentos', 'read', v_tenant_id);
  v_can_financeiro := public.can('financeiro', 'read', v_tenant_id);
  v_can_faturamento := public.can('faturamento', 'read', v_tenant_id);
  v_can_clientes := v_can_os
    or v_can_financeiro
    or public.can('cad_clientes', 'write', v_tenant_id);

  select c.id
    into v_colaborador_id
  from public.colaboradores c
  where c.tenant_id = v_tenant_id
    and c.empresa_id = v_empresa_id
    and c.user_id = v_auth_uid
    and c.ativo = true
  order by c.criado_em desc
  limit 1;

  return query
  with resultados as (
    select
      'OS'::text as tipo,
      ('OS ' || os.numero_os)::text as titulo,
      concat_ws(' · ', os.cliente_nome, nullif(os.descricao_servico, ''))::text as subtitulo,
      ('/os/' || os.id::text)::text as href,
      1 as prioridade,
      os.data_abertura::timestamp as atualizado_em
    from public.ordens_servico os
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.tipo_documento = 'OS'
      and (
        v_can_os
        or (
          v_colaborador_id is not null
          and exists (
            select 1 from public.apontamentos_horas ah
            where ah.tenant_id = v_tenant_id
              and ah.empresa_id = v_empresa_id
              and ah.colaborador_id = v_colaborador_id
              and ah.os_id = os.id
          )
        )
      )
      and concat_ws(' ', os.numero_os, os.os_num::text, os.cliente_nome, os.descricao_servico, os.pedido_compra) ilike v_padrao

    union all

    select
      'Cliente'::text,
      coalesce(c.nome_fantasia, c.razao_social, c.nome)::text,
      coalesce(nullif(c.documento_norm, ''), 'Cliente ' || c.id::text)::text,
      '/clientes'::text,
      2,
      c.atualizado_em::timestamp
    from public.clientes c
    where v_can_clientes
      and c.tenant_id = v_tenant_id
      and c.empresa_id = v_empresa_id
      and c.ativo = true
      and concat_ws(' ', c.id::text, c.nome, c.nome_fantasia, c.razao_social, c.documento, c.documento_norm) ilike v_padrao

    union all

    select
      'Item'::text,
      i.nome::text,
      ('Código ' || i.codigo_interno)::text,
      '/itens'::text,
      3,
      coalesce(i.updated_at, i.created_at)::timestamp
    from public.itens i
    where v_can_estoque
      and i.tenant_id = v_tenant_id
      and i.empresa_id = v_empresa_id
      and i.ativo = true
      and i.mesclado_em_item_id is null
      and concat_ws(' ', i.codigo_interno, i.codigo_barras, i.codigo_fornecedor, i.nome, i.descricao) ilike v_padrao

    union all

    select
      'Colaborador'::text,
      c.nome::text,
      coalesce(c.cargo, 'Colaborador')::text,
      '/colaboradores'::text,
      4,
      c.criado_em::timestamp
    from public.colaboradores c
    where v_can_apontamentos
      and c.tenant_id = v_tenant_id
      and c.empresa_id = v_empresa_id
      and c.ativo = true
      and concat_ws(' ', c.nome, c.cargo, c.email) ilike v_padrao

    union all

    select
      case when df.natureza = 'SERVICO' then 'NFS-e' else 'NF-e' end::text,
      (coalesce(df.modelo, 'NF') || ' ' || coalesce(df.numero, 'sem número'))::text,
      concat_ws(' · ', df.serie, df.chave_acesso)::text,
      (case when df.natureza = 'SERVICO' then '/faturamento/nfse/' else '/faturamento/nfe/' end || df.id::text)::text,
      5,
      df.updated_at::timestamp
    from f.documento_fiscal df
    where (v_can_faturamento or v_can_financeiro)
      and df.tenant_id = v_tenant_id
      and df.empresa_id = v_empresa_id
      and df.deleted_at is null
      and df.operacao = 'SAIDA'
      and concat_ws(' ', df.numero, df.serie, df.chave_acesso) ilike v_padrao
  )
  select r.tipo, r.titulo, r.subtitulo, r.href
  from resultados r
  order by r.prioridade, r.atualizado_em desc nulls last
  limit 20;
end;
$$;

revoke all on function public.home_sala_controle() from public, anon;
revoke all on function public.home_busca_comando(text) from public, anon;
grant execute on function public.home_sala_controle() to authenticated, service_role;
grant execute on function public.home_busca_comando(text) to authenticated, service_role;

comment on function public.home_sala_controle() is
  'Agregado permission-aware da Sala de Controle, sempre no tenant e empresa da sessão.';
comment on function public.home_busca_comando(text) is
  'Busca global da Home com cada categoria filtrada por permissão antes de sair do banco.';

notify pgrst, 'reload schema';

commit;
