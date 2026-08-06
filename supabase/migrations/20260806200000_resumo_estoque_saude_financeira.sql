begin;

create or replace function f.resumo_estoque_saude_financeira(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_inicio date,
  p_data_fim date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $function$
declare
  v_fluxo record;
  v_posicao record;
  v_qualidade record;
  v_pendencias jsonb := '[]'::jsonb;
begin
  if p_tenant_id is null
     or p_empresa_id is null
     or p_data_inicio is null
     or p_data_fim is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id, empresa_id e periodo sao obrigatorios';
  end if;

  if p_data_fim < p_data_inicio then
    raise exception using
      errcode = '22023',
      message = 'Data final nao pode ser anterior a data inicial';
  end if;

  if (p_data_fim - p_data_inicio) > 366 then
    raise exception using
      errcode = '22023',
      message = 'O periodo maximo permitido e de 367 dias';
  end if;

  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado';
  end if;

  if not exists (
    select 1
    from c.empresa e
    where e.id = p_empresa_id
      and e.tenant_id = p_tenant_id
      and e.deleted_at is null
  ) then
    raise exception using
      errcode = '22023',
      message = 'Empresa nao encontrada no tenant informado';
  end if;

  if public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id() is distinct from p_empresa_id then
    raise exception using
      errcode = '42501',
      message = 'Tenant ou empresa nao corresponde ao contexto ativo';
  end if;

  if not f.has_finance_access(p_tenant_id, p_empresa_id) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para acessar relatorios financeiros';
  end if;

  with movimentos_periodo as (
    select
      m.id,
      m.tipo,
      coalesce(m.quantidade, 0)::numeric as quantidade,
      m.origem_nf_entrada_id,
      m.origem_os_id,
      nf.os_id as nf_os_id,
      coalesce(
        nullif(m.custo_unitario_real, 0),
        nullif(m.custo_unitario_bruto, 0),
        nullif(i.custo_medio, 0),
        nullif(i.custo_ultima_compra, 0),
        0
      )::numeric as custo_unitario,
      (coalesce(m.custo_unitario_real, 0) <= 0
       and coalesce(m.custo_unitario_bruto, 0) <= 0) as custo_historico_ausente
    from public.movimentacoes m
    join public.itens i
      on i.id = m.item_id
     and i.tenant_id = m.tenant_id
     and i.empresa_id = m.empresa_id
    left join public.nf_entrada nf
      on nf.id = m.origem_nf_entrada_id
     and nf.tenant_id = m.tenant_id
     and nf.empresa_id = m.empresa_id
     and nf.deleted_at is null
    where m.tenant_id = p_tenant_id
      and m.empresa_id = p_empresa_id
      and m.data_movimentacao::date between p_data_inicio and p_data_fim
  )
  select
    coalesce(sum(quantidade * custo_unitario)
      filter (where tipo = 'entrada' and origem_nf_entrada_id is not null and nf_os_id is null), 0)::numeric(18,2)
      as compras_para_estoque,
    coalesce(sum(quantidade * custo_unitario)
      filter (where tipo = 'entrada' and origem_nf_entrada_id is not null and nf_os_id is not null), 0)::numeric(18,2)
      as compras_diretas_os,
    coalesce(sum(quantidade * custo_unitario)
      filter (where tipo = 'entrada' and origem_nf_entrada_id is null), 0)::numeric(18,2)
      as outras_entradas,
    coalesce(sum(quantidade * custo_unitario)
      filter (where tipo = 'saida' and origem_os_id is not null and origem_nf_entrada_id is null), 0)::numeric(18,2)
      as consumo_estoque_os,
    coalesce(sum(quantidade * custo_unitario)
      filter (where tipo = 'saida' and origem_os_id is not null and origem_nf_entrada_id is not null), 0)::numeric(18,2)
      as saidas_diretas_os,
    coalesce(sum(quantidade * custo_unitario)
      filter (where tipo = 'saida' and origem_os_id is null), 0)::numeric(18,2)
      as outras_saidas,
    coalesce(sum(quantidade * custo_unitario)
      filter (where tipo = 'ajuste'), 0)::numeric(18,2)
      as ajustes,
    count(*) filter (
      where tipo = 'saida'
        and custo_historico_ausente
        and custo_unitario > 0
    )::integer as saidas_valorizadas_por_custo_atual,
    count(*) filter (where custo_unitario <= 0)::integer as movimentos_sem_valor
  into v_fluxo
  from movimentos_periodo;

  with movimento_item as (
    select
      m.item_id,
      max(m.data_movimentacao::date) as ultima_movimentacao,
      coalesce(sum(
        case
          when m.data_movimentacao::date between p_data_inicio and p_data_fim then
            case when m.tipo = 'saida' then -coalesce(m.quantidade, 0) else coalesce(m.quantidade, 0) end
          else 0
        end
      ), 0)::numeric as delta_periodo,
      coalesce(sum(
        case
          when m.data_movimentacao::date > p_data_fim then
            case when m.tipo = 'saida' then -coalesce(m.quantidade, 0) else coalesce(m.quantidade, 0) end
          else 0
        end
      ), 0)::numeric as delta_apos_periodo
    from public.movimentacoes m
    where m.tenant_id = p_tenant_id
      and m.empresa_id = p_empresa_id
    group by m.item_id
  ),
  posicao_item as (
    select
      e.item_id,
      coalesce(e.quantidade_atual, 0)::numeric as quantidade_atual,
      (coalesce(e.quantidade_atual, 0) - coalesce(mi.delta_apos_periodo, 0))::numeric as quantidade_fim,
      (
        coalesce(e.quantidade_atual, 0)
        - coalesce(mi.delta_apos_periodo, 0)
        - coalesce(mi.delta_periodo, 0)
      )::numeric as quantidade_inicio,
      coalesce(nullif(i.custo_medio, 0), nullif(i.custo_ultima_compra, 0), 0)::numeric as custo_unitario,
      coalesce(i.estoque_ideal, 0)::numeric as estoque_ideal,
      mi.ultima_movimentacao
    from public.estoque e
    join public.itens i
      on i.id = e.item_id
     and i.tenant_id = e.tenant_id
     and i.empresa_id = e.empresa_id
    left join movimento_item mi
      on mi.item_id = e.item_id
    where e.tenant_id = p_tenant_id
      and e.empresa_id = p_empresa_id
      and coalesce(i.ativo, true)
  )
  select
    coalesce(sum(greatest(quantidade_atual, 0) * custo_unitario), 0)::numeric(18,2) as valor_atual,
    coalesce(sum(greatest(quantidade_inicio, 0) * custo_unitario), 0)::numeric(18,2) as valor_inicio_periodo,
    coalesce(sum(greatest(quantidade_fim, 0) * custo_unitario), 0)::numeric(18,2) as valor_fim_periodo,
    (
      coalesce(sum(greatest(quantidade_fim, 0) * custo_unitario), 0)
      - coalesce(sum(greatest(quantidade_inicio, 0) * custo_unitario), 0)
    )::numeric(18,2) as variacao_periodo,
    count(*) filter (where quantidade_atual > 0)::integer as itens_com_saldo,
    count(*) filter (where quantidade_atual > 0 and custo_unitario <= 0)::integer as itens_sem_custo,
    coalesce(sum(quantidade_atual) filter (where quantidade_atual > 0 and custo_unitario <= 0), 0)::numeric(18,3)
      as quantidade_sem_custo,
    count(*) filter (where quantidade_atual < 0)::integer as itens_negativos,
    coalesce(sum(abs(quantidade_atual)) filter (where quantidade_atual < 0), 0)::numeric(18,3)
      as quantidade_negativa,
    count(*) filter (
      where quantidade_atual > 0
        and (ultima_movimentacao is null or ultima_movimentacao < current_date - 180)
    )::integer as itens_sem_movimento_180d,
    coalesce(sum(quantidade_atual * custo_unitario) filter (
      where quantidade_atual > 0
        and (ultima_movimentacao is null or ultima_movimentacao < current_date - 180)
    ), 0)::numeric(18,2) as valor_sem_movimento_180d,
    count(*) filter (
      where quantidade_atual > estoque_ideal
        and estoque_ideal > 0
    )::integer as itens_acima_ideal,
    coalesce(sum((quantidade_atual - estoque_ideal) * custo_unitario) filter (
      where quantidade_atual > estoque_ideal
        and estoque_ideal > 0
    ), 0)::numeric(18,2) as valor_acima_ideal
  into v_posicao
  from posicao_item;

  with nf_periodo as (
    select nf.id, nf.numero, nf.data_emissao::date as data_emissao
    from public.nf_entrada nf
    where nf.tenant_id = p_tenant_id
      and nf.empresa_id = p_empresa_id
      and nf.deleted_at is null
      and nf.finalidade_contexto in ('materia_prima'::public.item_finalidade, 'revenda'::public.item_finalidade)
      and coalesce(nf.data_emissao::date, nf.criado_em::date) between p_data_inicio and p_data_fim
  ),
  linhas as (
    select
      nfi.id,
      nfi.nf_entrada_id,
      nfi.item_id,
      nfi.descricao,
      coalesce(nfi.v_prod, 0)::numeric as valor
    from public.nf_entrada_itens nfi
    join nf_periodo nf on nf.id = nfi.nf_entrada_id
    where nfi.tenant_id = p_tenant_id
      and nfi.empresa_id = p_empresa_id
  ),
  pendencias as (
    select l.*, 'SEM_CADASTRO'::text as tipo
    from linhas l
    where l.item_id is null
    union all
    select l.*, 'SEM_ENTRADA'::text as tipo
    from linhas l
    where l.item_id is not null
      and not exists (
        select 1
        from public.movimentacoes m
        where m.tenant_id = p_tenant_id
          and m.empresa_id = p_empresa_id
          and m.origem_nf_entrada_id = l.nf_entrada_id
          and m.item_id = l.item_id
          and m.tipo = 'entrada'
      )
  )
  select
    (select count(*) from linhas)::integer as itens_esperados,
    count(*) filter (where tipo = 'SEM_CADASTRO')::integer as itens_sem_cadastro,
    coalesce(sum(valor) filter (where tipo = 'SEM_CADASTRO'), 0)::numeric(18,2) as valor_sem_cadastro,
    count(*) filter (where tipo = 'SEM_ENTRADA')::integer as itens_sem_entrada,
    coalesce(sum(valor) filter (where tipo = 'SEM_ENTRADA'), 0)::numeric(18,2) as valor_sem_entrada
  into v_qualidade
  from pendencias;

  with nf_periodo as (
    select nf.id, nf.numero, nf.data_emissao::date as data_emissao
    from public.nf_entrada nf
    where nf.tenant_id = p_tenant_id
      and nf.empresa_id = p_empresa_id
      and nf.deleted_at is null
      and nf.finalidade_contexto in ('materia_prima'::public.item_finalidade, 'revenda'::public.item_finalidade)
      and coalesce(nf.data_emissao::date, nf.criado_em::date) between p_data_inicio and p_data_fim
  ),
  pendencias as (
    select
      nf.id as nf_id,
      nf.numero,
      nf.data_emissao,
      nfi.descricao,
      coalesce(nfi.v_prod, 0)::numeric as valor,
      case
        when nfi.item_id is null then 'SEM_CADASTRO'
        else 'SEM_ENTRADA'
      end as tipo
    from nf_periodo nf
    join public.nf_entrada_itens nfi
      on nfi.nf_entrada_id = nf.id
     and nfi.tenant_id = p_tenant_id
     and nfi.empresa_id = p_empresa_id
    where nfi.item_id is null
       or not exists (
         select 1
         from public.movimentacoes m
         where m.tenant_id = p_tenant_id
           and m.empresa_id = p_empresa_id
           and m.origem_nf_entrada_id = nfi.nf_entrada_id
           and m.item_id = nfi.item_id
           and m.tipo = 'entrada'
       )
  ),
  destaque as (
    select *
    from pendencias
    order by data_emissao desc nulls last, valor desc, nf_id desc
    limit 8
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'tipo', tipo,
        'nfId', nf_id,
        'nfNumero', coalesce(numero, '-'),
        'data', data_emissao,
        'descricao', coalesce(nullif(btrim(descricao), ''), 'Item sem descricao'),
        'valor', valor
      )
      order by data_emissao desc nulls last, valor desc
    ),
    '[]'::jsonb
  )
  into v_pendencias
  from destaque;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'tenantId', p_tenant_id,
      'empresaId', p_empresa_id,
      'dataInicio', p_data_inicio,
      'dataFim', p_data_fim,
      'posicaoAtualEm', current_date,
      'criterioValoracao', 'CUSTO_MEDIO_ATUAL_COM_FALLBACK_ULTIMA_COMPRA'
    ),
    'periodo', jsonb_build_object(
      'comprasParaEstoque', coalesce(v_fluxo.compras_para_estoque, 0),
      'comprasDiretasOs', coalesce(v_fluxo.compras_diretas_os, 0),
      'outrasEntradas', coalesce(v_fluxo.outras_entradas, 0),
      'consumoEstoqueOs', coalesce(v_fluxo.consumo_estoque_os, 0),
      'saidasDiretasOs', coalesce(v_fluxo.saidas_diretas_os, 0),
      'outrasSaidas', coalesce(v_fluxo.outras_saidas, 0),
      'ajustes', coalesce(v_fluxo.ajustes, 0),
      'saidasValorizadasPorCustoAtual', coalesce(v_fluxo.saidas_valorizadas_por_custo_atual, 0),
      'movimentosSemValor', coalesce(v_fluxo.movimentos_sem_valor, 0)
    ),
    'posicao', jsonb_build_object(
      'valorAtual', coalesce(v_posicao.valor_atual, 0),
      'valorInicioPeriodo', coalesce(v_posicao.valor_inicio_periodo, 0),
      'valorFimPeriodo', coalesce(v_posicao.valor_fim_periodo, 0),
      'variacaoPeriodo', coalesce(v_posicao.variacao_periodo, 0),
      'itensComSaldo', coalesce(v_posicao.itens_com_saldo, 0),
      'itensSemCusto', coalesce(v_posicao.itens_sem_custo, 0),
      'quantidadeSemCusto', coalesce(v_posicao.quantidade_sem_custo, 0),
      'itensNegativos', coalesce(v_posicao.itens_negativos, 0),
      'quantidadeNegativa', coalesce(v_posicao.quantidade_negativa, 0),
      'itensSemMovimento180d', coalesce(v_posicao.itens_sem_movimento_180d, 0),
      'valorSemMovimento180d', coalesce(v_posicao.valor_sem_movimento_180d, 0),
      'itensAcimaIdeal', coalesce(v_posicao.itens_acima_ideal, 0),
      'valorAcimaIdeal', coalesce(v_posicao.valor_acima_ideal, 0)
    ),
    'qualidade', jsonb_build_object(
      'itensEsperados', coalesce(v_qualidade.itens_esperados, 0),
      'itensSemCadastro', coalesce(v_qualidade.itens_sem_cadastro, 0),
      'valorSemCadastro', coalesce(v_qualidade.valor_sem_cadastro, 0),
      'itensSemEntrada', coalesce(v_qualidade.itens_sem_entrada, 0),
      'valorSemEntrada', coalesce(v_qualidade.valor_sem_entrada, 0)
    ),
    'pendencias', coalesce(v_pendencias, '[]'::jsonb)
  );
end;
$function$;

comment on function f.resumo_estoque_saude_financeira(uuid, uuid, date, date) is
  'Cruza compras, movimentacoes fisicas, consumo por OS, posicao valorizada e pendencias cadastrais do estoque no tenant e empresa ativos.';

revoke all on function f.resumo_estoque_saude_financeira(uuid, uuid, date, date) from public;
revoke all on function f.resumo_estoque_saude_financeira(uuid, uuid, date, date) from anon;
grant execute on function f.resumo_estoque_saude_financeira(uuid, uuid, date, date) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
