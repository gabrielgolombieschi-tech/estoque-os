begin;

create index if not exists idx_pagamento_tenant_empresa_data_ativo
  on f.pagamento (tenant_id, empresa_id, data_pagamento)
  where deleted_at is null;

create index if not exists idx_pagamento_item_pagamento_ativo
  on f.pagamento_item (pagamento_id)
  where deleted_at is null;

create index if not exists idx_titulo_parcela_titulo_ativo
  on f.titulo_parcela (titulo_id)
  where deleted_at is null;

create index if not exists idx_titulo_rateio_titulo_ativo
  on f.titulo_rateio (titulo_id)
  where deleted_at is null;

create index if not exists idx_titulo_aprovacao_titulo_ativo
  on f.titulo_aprovacao (titulo_id)
  where deleted_at is null;

create index if not exists idx_titulo_documento_ativo
  on f.titulo (tenant_id, empresa_id, documento_fiscal_id, tipo)
  where deleted_at is null and documento_fiscal_id is not null;

drop function if exists f.relatorio_saude_financeira(uuid, uuid, date, date);

create function f.relatorio_saude_financeira(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_inicio date,
  p_data_fim date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'f', 'r', 'public', 'a', 'c'
set row_security to 'off'
as $function$
declare
  v_data_anterior_inicio date;
  v_data_anterior_fim date;
  v_serie_inicio date;
  v_competencia jsonb;
  v_caixa jsonb;
  v_compromissos jsonb;
  v_qualidade jsonb;
begin
  if p_tenant_id is null
     or p_empresa_id is null
     or p_data_inicio is null
     or p_data_fim is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id, empresa_id e período são obrigatórios';
  end if;

  if p_data_fim < p_data_inicio then
    raise exception using
      errcode = '22023',
      message = 'Data final não pode ser anterior à data inicial';
  end if;

  if (p_data_fim - p_data_inicio) > 366 then
    raise exception using
      errcode = '22023',
      message = 'O período máximo permitido é de 367 dias';
  end if;

  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'Usuário não autenticado';
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
      message = 'Empresa não encontrada no tenant informado';
  end if;

  if public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id() is distinct from p_empresa_id then
    raise exception using
      errcode = '42501',
      message = 'Tenant ou empresa não corresponde ao contexto ativo';
  end if;

  if not f.has_finance_access(p_tenant_id, p_empresa_id) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissão para acessar relatórios financeiros';
  end if;

  v_data_anterior_fim := p_data_inicio - 1;
  if p_data_inicio = date_trunc('month', p_data_inicio)::date
     and p_data_fim =
       (date_trunc('month', p_data_inicio) + interval '1 month - 1 day')::date then
    v_data_anterior_inicio := (p_data_inicio - interval '1 month')::date;
  elsif extract(month from p_data_inicio) = 1
     and extract(day from p_data_inicio) = 1
     and p_data_fim = make_date(extract(year from p_data_inicio)::integer, 12, 31) then
    v_data_anterior_inicio := make_date(
      extract(year from p_data_inicio)::integer - 1,
      1,
      1
    );
  else
    v_data_anterior_inicio :=
      p_data_inicio - ((p_data_fim - p_data_inicio) + 1);
  end if;
  v_serie_inicio :=
    (date_trunc('month', p_data_fim)::date - interval '11 months')::date;

  /*
   * Competência
   *
   * O resultado segue a regra da DRE gerencial atual: somente rateios entram
   * no resultado e planos em r.dre_plano_excluido são investimentos.
   */
  with
  titulos as (
    select
      t.id,
      t.tipo,
      t.status,
      t.fornecedor_id,
      t.cliente_id,
      t.descricao,
      t.competencia_date,
      t.valor_total,
      t.valor_aberto,
      t.arrendamento_contrato_id,
      coalesce(ta.motivo_compra_id, t.motivo_compra_id) as motivo_id,
      coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo,
      coalesce(mc.nome, 'Não classificado') as motivo_nome
    from f.titulo t
    left join f.titulo_aprovacao ta
      on ta.tenant_id = p_tenant_id
     and ta.titulo_id = t.id
     and ta.deleted_at is null
    left join f.motivo_compra mc
      on mc.tenant_id = p_tenant_id
     and mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
     and mc.deleted_at is null
     and mc.ativo
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
      and t.competencia_date between
        least(v_data_anterior_inicio, v_serie_inicio)
        and p_data_fim
  ),
  rateios as (
    select
      t.*,
      tr.id as rateio_id,
      tr.plano_contas_id,
      tr.centro_custo_id,
      coalesce(
        tr.valor,
        round(t.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
        0
      ) as valor_alocado,
      coalesce(pc.codigo, 'SEM_PLANO') as plano_codigo,
      coalesce(pc.nome, 'Sem plano de contas') as plano_nome,
      coalesce(cc.codigo, 'SEM_CENTRO') as centro_codigo,
      coalesce(cc.nome, 'Sem centro de custo') as centro_nome,
      (pc.id is not null and pc.ativo) as plano_valido,
      exists (
        select 1
        from r.dre_plano_excluido dpe
        where dpe.tenant_id = p_tenant_id
          and dpe.plano_contas_id = tr.plano_contas_id
      ) as investimento_plano
    from titulos t
    join f.titulo_rateio tr
      on tr.tenant_id = p_tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    left join f.plano_contas pc
      on pc.tenant_id = p_tenant_id
     and pc.id = tr.plano_contas_id
     and pc.deleted_at is null
    left join f.centro_custo cc
      on cc.tenant_id = p_tenant_id
     and cc.empresa_id = p_empresa_id
     and cc.id = tr.centro_custo_id
     and cc.deleted_at is null
  ),
  alocacoes as (
    select
      r.*,
      true as possui_rateio,
      r.investimento_plano as investimento,
      (
        r.plano_codigo = 'DESP_FINANCIAMENTO'
        or r.motivo_codigo = 'FINANCIAMENTO_RURAL'
        or exists (
          select 1
          from f.arrendamento_contrato ac_scope
          where ac_scope.id = r.arrendamento_contrato_id
            and ac_scope.tenant_id = p_tenant_id
            and ac_scope.empresa_id = p_empresa_id
            and ac_scope.ativo
            and ac_scope.deleted_at is null
        )
      ) as divida
    from rateios r

    union all

    select
      t.*,
      null::uuid as rateio_id,
      null::uuid as plano_contas_id,
      null::uuid as centro_custo_id,
      t.valor_total as valor_alocado,
      'SEM_PLANO'::text as plano_codigo,
      'Sem plano de contas'::text as plano_nome,
      'SEM_CENTRO'::text as centro_codigo,
      'Sem centro de custo'::text as centro_nome,
      false as plano_valido,
      false as investimento_plano,
      false as possui_rateio,
      (t.motivo_codigo = 'INVESTIMENTO') as investimento,
      (
        t.motivo_codigo = 'FINANCIAMENTO_RURAL'
        or exists (
          select 1
          from f.arrendamento_contrato ac_scope
          where ac_scope.id = t.arrendamento_contrato_id
            and ac_scope.tenant_id = p_tenant_id
            and ac_scope.empresa_id = p_empresa_id
            and ac_scope.ativo
            and ac_scope.deleted_at is null
        )
      ) as divida
    from titulos t
    where not exists (
      select 1
      from f.titulo_rateio tr
      where tr.tenant_id = p_tenant_id
        and tr.titulo_id = t.id
        and tr.deleted_at is null
    )
  ),
  resultado_mes as (
    select
      a.competencia_date,
      sum(
        case
          when a.tipo = 'AR'
           and a.possui_rateio
           and a.plano_valido
           and not a.investimento_plano
          then a.valor_alocado
          else 0
        end
      ) as receita,
      sum(
        case
          when a.tipo = 'AP'
           and a.possui_rateio
           and a.plano_valido
           and not a.investimento_plano
          then a.valor_alocado
          else 0
        end
      ) as despesa
    from alocacoes a
    group by a.competencia_date
  ),
  atual as (
    select
      coalesce(sum(rm.receita), 0) as receita,
      coalesce(sum(rm.despesa), 0) as despesa
    from resultado_mes rm
    where rm.competencia_date between p_data_inicio and p_data_fim
  ),
  anterior as (
    select
      coalesce(sum(rm.receita), 0) as receita,
      coalesce(sum(rm.despesa), 0) as despesa
    from resultado_mes rm
    where rm.competencia_date
      between v_data_anterior_inicio and v_data_anterior_fim
  ),
  meses as (
    select generate_series(
      v_serie_inicio::timestamp,
      date_trunc('month', p_data_fim)::timestamp,
      interval '1 month'
    )::date as mes
  ),
  serie as (
    select
      m.mes,
      coalesce(rm.receita, 0) as receita,
      coalesce(rm.despesa, 0) as despesa
    from meses m
    left join resultado_mes rm on rm.competencia_date = m.mes
  ),
  plano_resumo as (
    select
      a.plano_contas_id,
      a.plano_codigo,
      a.plano_nome,
      sum(a.valor_alocado) as valor
    from alocacoes a
    where a.tipo = 'AP'
      and a.competencia_date between p_data_inicio and p_data_fim
    group by a.plano_contas_id, a.plano_codigo, a.plano_nome
  ),
  motivo_resumo as (
    select
      t.motivo_id,
      t.motivo_codigo,
      t.motivo_nome,
      sum(t.valor_total) as valor
    from titulos t
    where t.tipo = 'AP'
      and t.competencia_date between p_data_inicio and p_data_fim
    group by t.motivo_id, t.motivo_codigo, t.motivo_nome
  ),
  centro_resumo as (
    select
      a.centro_custo_id,
      a.centro_codigo,
      a.centro_nome,
      sum(a.valor_alocado) as valor
    from alocacoes a
    where a.tipo = 'AP'
      and a.competencia_date between p_data_inicio and p_data_fim
    group by a.centro_custo_id, a.centro_codigo, a.centro_nome
  ),
  fornecedor_resumo as (
    select
      t.fornecedor_id,
      coalesce(forn.nome, 'Sem fornecedor') as nome,
      count(*) as quantidade,
      sum(t.valor_total) as valor
    from titulos t
    left join public.fornecedores forn
      on forn.tenant_id = p_tenant_id
     and forn.empresa_id = p_empresa_id
     and forn.id = t.fornecedor_id
    where t.tipo = 'AP'
      and t.competencia_date between p_data_inicio and p_data_fim
    group by t.fornecedor_id, coalesce(forn.nome, 'Sem fornecedor')
  ),
  plano_cobertura as (
    select
      t.id,
      t.valor_total,
      coalesce(
        sum(case when r.plano_valido then r.valor_alocado else 0 end),
        0
      ) as valor_classificado
    from titulos t
    left join rateios r on r.id = t.id
    where t.tipo = 'AP'
      and t.competencia_date between p_data_inicio and p_data_fim
    group by t.id, t.valor_total
  ),
  extras_titulo as (
    select
      t.id,
      t.competencia_date,
      case
        when count(r.rateio_id) > 0 then least(
          greatest(t.valor_total, 0),
          coalesce(sum(case when r.investimento_plano then r.valor_alocado else 0 end), 0)
        )
        when t.motivo_codigo = 'INVESTIMENTO' then greatest(t.valor_total, 0)
        else 0
      end as investimento,
      case
        when t.motivo_codigo = 'FINANCIAMENTO_RURAL'
          or exists (
            select 1
            from f.arrendamento_contrato ac_scope
            where ac_scope.id = t.arrendamento_contrato_id
              and ac_scope.tenant_id = p_tenant_id
              and ac_scope.empresa_id = p_empresa_id
              and ac_scope.ativo
              and ac_scope.deleted_at is null
          ) then greatest(t.valor_total, 0)
        else least(
          greatest(t.valor_total, 0),
          coalesce(sum(case when r.plano_codigo = 'DESP_FINANCIAMENTO' then r.valor_alocado else 0 end), 0)
        )
      end as divida
    from titulos t
    left join rateios r on r.id = t.id
    where t.tipo = 'AP'
    group by
      t.id,
      t.competencia_date,
      t.valor_total,
      t.motivo_codigo,
      t.arrendamento_contrato_id
  ),
  extras_atual as (
    select
      coalesce(sum(et.investimento), 0) as investimentos,
      coalesce(sum(et.divida), 0) as divida_identificada
    from extras_titulo et
    where et.competencia_date between p_data_inicio and p_data_fim
  ),
  extras_anterior as (
    select
      coalesce(sum(et.investimento), 0) as investimentos,
      coalesce(sum(et.divida), 0) as divida_identificada
    from extras_titulo et
    where et.competencia_date
      between v_data_anterior_inicio and v_data_anterior_fim
  ),
  ap_atual as (
    select
      coalesce(sum(t.valor_total), 0) as total_ap,
      count(*) as quantidade
    from titulos t
    where t.tipo = 'AP'
      and t.competencia_date between p_data_inicio and p_data_fim
  ),
  ap_anterior as (
    select coalesce(sum(t.valor_total), 0) as total_ap
    from titulos t
    where t.tipo = 'AP'
      and t.competencia_date
        between v_data_anterior_inicio and v_data_anterior_fim
  ),
  nao_classificado as (
    select coalesce(sum(
      greatest(
        coalesce(pc.valor_total, 0)
          - least(
              greatest(coalesce(pc.valor_classificado, 0), 0),
              greatest(coalesce(pc.valor_total, 0), 0)
            ),
        0
      )
    ), 0) as valor
    from plano_cobertura pc
  )
  select jsonb_build_object(
    'receita', round(at.receita, 2),
    'despesa', round(at.despesa, 2),
    'resultado', round(at.receita - at.despesa, 2),
    'margem', case
      when at.receita = 0 then null
      else round(((at.receita - at.despesa) / at.receita) * 100, 2)
    end,
    'investimentos', round(ea.investimentos, 2),
    'dividaIdentificada', round(ea.divida_identificada, 2),
    'totalAp', round(apa.total_ap, 2),
    'quantidadeAp', apa.quantidade,
    'naoClassificado', round(nc.valor, 2),
    'anterior', jsonb_build_object(
      'receita', round(an.receita, 2),
      'despesa', round(an.despesa, 2),
      'resultado', round(an.receita - an.despesa, 2),
      'margem', case
        when an.receita = 0 then null
        else round(((an.receita - an.despesa) / an.receita) * 100, 2)
      end,
      'investimentos', round(ean.investimentos, 2),
      'dividaIdentificada', round(ean.divida_identificada, 2),
      'totalAp', round(apan.total_ap, 2)
    ),
    'serie', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'label', to_char(s.mes, 'MM/YYYY'),
          'mes', s.mes,
          'receita', round(s.receita, 2),
          'despesa', round(s.despesa, 2),
          'resultado', round(s.receita - s.despesa, 2)
        )
        order by s.mes
      )
      from serie s
    ), '[]'::jsonb),
    'porPlano', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', x.plano_contas_id,
          'codigo', x.plano_codigo,
          'nome', x.plano_nome,
          'valor', round(x.valor, 2),
          'percentual', case
            when apa.total_ap = 0 then 0
            else round((x.valor / apa.total_ap) * 100, 2)
          end
        )
        order by x.valor desc, x.plano_nome
      )
      from (
        select pr.*
        from plano_resumo pr
        order by pr.valor desc
        limit 12
      ) x
    ), '[]'::jsonb),
    'porMotivo', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', x.motivo_id,
          'codigo', x.motivo_codigo,
          'nome', x.motivo_nome,
          'valor', round(x.valor, 2),
          'percentual', case
            when apa.total_ap = 0 then 0
            else round((x.valor / apa.total_ap) * 100, 2)
          end
        )
        order by x.valor desc, x.motivo_nome
      )
      from (
        select mr.*
        from motivo_resumo mr
        order by mr.valor desc
        limit 12
      ) x
    ), '[]'::jsonb),
    'porCentro', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', x.centro_custo_id,
          'codigo', x.centro_codigo,
          'nome', x.centro_nome,
          'valor', round(x.valor, 2),
          'percentual', case
            when apa.total_ap = 0 then 0
            else round((x.valor / apa.total_ap) * 100, 2)
          end
        )
        order by x.valor desc, x.centro_nome
      )
      from (
        select cr.*
        from centro_resumo cr
        order by cr.valor desc
        limit 12
      ) x
    ), '[]'::jsonb),
    'topFornecedores', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'fornecedorId', x.fornecedor_id,
          'nome', x.nome,
          'quantidade', x.quantidade,
          'valor', round(x.valor, 2),
          'percentual', case
            when apa.total_ap = 0 then 0
            else round((x.valor / apa.total_ap) * 100, 2)
          end
        )
        order by x.valor desc, x.nome
      )
      from (
        select fr.*
        from fornecedor_resumo fr
        order by fr.valor desc
        limit 10
      ) x
    ), '[]'::jsonb)
  )
  into v_competencia
  from atual at
  cross join anterior an
  cross join extras_atual ea
  cross join extras_anterior ean
  cross join ap_atual apa
  cross join ap_anterior apan
  cross join nao_classificado nc;

  /*
   * Caixa
   *
   * Cada cabeçalho é rateado entre seus itens pela participação no valor
   * aplicado, evitando multiplicação em pagamentos com várias parcelas.
   */
  with
  pagamentos as (
    select
      p.id,
      p.data_pagamento,
      p.valor,
      p.valor_principal,
      p.valor_juros,
      p.valor_multa,
      p.valor_desconto,
      p.conciliado_at
    from f.pagamento p
    where p.tenant_id = p_tenant_id
      and p.empresa_id = p_empresa_id
      and p.deleted_at is null
      and p.data_pagamento between
        least(v_data_anterior_inicio, v_serie_inicio)
        and p_data_fim
  ),
  itens as (
    select
      p.id as pagamento_id,
      p.data_pagamento,
      p.valor,
      p.valor_principal,
      p.valor_juros,
      p.valor_multa,
      p.valor_desconto,
      p.conciliado_at,
      t.id as titulo_id,
      t.tipo,
      t.fornecedor_id,
      t.arrendamento_contrato_id,
      coalesce(ta.motivo_compra_id, t.motivo_compra_id) as motivo_id,
      coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo,
      coalesce(mc.nome, 'Não classificado') as motivo_nome,
      sum(pi.valor) as valor_aplicado
    from pagamentos p
    join f.pagamento_item pi
      on pi.tenant_id = p_tenant_id
     and pi.empresa_id = p_empresa_id
     and pi.pagamento_id = p.id
     and pi.deleted_at is null
    join f.titulo_parcela tp
      on tp.tenant_id = p_tenant_id
     and tp.id = pi.titulo_parcela_id
     and tp.deleted_at is null
    join f.titulo t
      on t.tenant_id = p_tenant_id
     and t.empresa_id = p_empresa_id
     and t.id = tp.titulo_id
     and t.deleted_at is null
     and t.status <> 'CANCELADO'
    left join f.titulo_aprovacao ta
      on ta.tenant_id = p_tenant_id
     and ta.titulo_id = t.id
     and ta.deleted_at is null
    left join f.motivo_compra mc
      on mc.tenant_id = p_tenant_id
     and mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
     and mc.deleted_at is null
     and mc.ativo
    group by
      p.id,
      p.data_pagamento,
      p.valor,
      p.valor_principal,
      p.valor_juros,
      p.valor_multa,
      p.valor_desconto,
      p.conciliado_at,
      t.id,
      t.tipo,
      t.fornecedor_id,
      t.arrendamento_contrato_id,
      coalesce(ta.motivo_compra_id, t.motivo_compra_id),
      coalesce(mc.codigo, 'NAO_CLASSIFICADO'),
      coalesce(mc.nome, 'Não classificado')
  ),
  totais_pagamento as (
    select
      p.id as pagamento_id,
      coalesce(sum(pi.valor), 0) as valor_aplicado_total
    from pagamentos p
    left join f.pagamento_item pi
      on pi.pagamento_id = p.id
     and pi.deleted_at is null
    group by p.id
  ),
  titulos_caixa as (
    select distinct
      i.titulo_id,
      i.motivo_codigo,
      i.arrendamento_contrato_id
    from itens i
  ),
  classificacao_titulo as (
    select
      tc.titulo_id,
      t.valor_total as valor_titulo,
      coalesce(sum(
        case
          when exists (
            select 1
            from r.dre_plano_excluido dpe
            where dpe.tenant_id = p_tenant_id
              and dpe.plano_contas_id = tr.plano_contas_id
          )
          then coalesce(
            tr.valor,
            round(t.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
            0
          )
          else 0
        end
      ), 0) as valor_investimento,
      coalesce(sum(
        case
          when pc.codigo = 'DESP_FINANCIAMENTO'
            or tc.motivo_codigo = 'FINANCIAMENTO_RURAL'
            or exists (
          select 1
          from f.arrendamento_contrato ac_scope
          where ac_scope.id = tc.arrendamento_contrato_id
            and ac_scope.tenant_id = p_tenant_id
            and ac_scope.empresa_id = p_empresa_id
            and ac_scope.ativo
            and ac_scope.deleted_at is null
        )
          then coalesce(
            tr.valor,
            round(t.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
            0
          )
          else 0
        end
      ), 0) as valor_divida,
      coalesce(sum(coalesce(
        tr.valor,
        round(t.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
        0
      )), 0) as valor_rateado,
      count(tr.id) as quantidade_rateios
    from titulos_caixa tc
    join f.titulo t
      on t.tenant_id = p_tenant_id
     and t.empresa_id = p_empresa_id
     and t.id = tc.titulo_id
     and t.deleted_at is null
    left join f.titulo_rateio tr
      on tr.tenant_id = p_tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    left join f.plano_contas pc
      on pc.tenant_id = p_tenant_id
     and pc.id = tr.plano_contas_id
     and pc.deleted_at is null
    group by
      tc.titulo_id,
      t.valor_total,
      tc.motivo_codigo,
      tc.arrendamento_contrato_id
  ),
  linhas as (
    select
      i.*,
      case
        when tp.valor_aplicado_total = 0 then 0
        else i.valor * i.valor_aplicado / tp.valor_aplicado_total
      end as valor_movimento,
      case
        when tp.valor_aplicado_total = 0 then 0
        else i.valor_juros * i.valor_aplicado / tp.valor_aplicado_total
      end as juros_movimento,
      case
        when tp.valor_aplicado_total = 0 then 0
        else i.valor_multa * i.valor_aplicado / tp.valor_aplicado_total
      end as multa_movimento,
      case
        when tp.valor_aplicado_total = 0 then 0
        else i.valor_desconto * i.valor_aplicado / tp.valor_aplicado_total
      end as desconto_movimento,
      case
        when ct.quantidade_rateios > 0 and ct.valor_titulo > 0
        then least(greatest(ct.valor_investimento / ct.valor_titulo, 0), 1)
        when i.motivo_codigo = 'INVESTIMENTO' then 1
        else 0
      end as proporcao_investimento,
      case
        when i.motivo_codigo = 'FINANCIAMENTO_RURAL'
          or exists (
          select 1
          from f.arrendamento_contrato ac_scope
          where ac_scope.id = i.arrendamento_contrato_id
            and ac_scope.tenant_id = p_tenant_id
            and ac_scope.empresa_id = p_empresa_id
            and ac_scope.ativo
            and ac_scope.deleted_at is null
        )
        then 1
        when ct.quantidade_rateios > 0 and ct.valor_titulo > 0
        then least(greatest(ct.valor_divida / ct.valor_titulo, 0), 1)
        else 0
      end as proporcao_divida
    from itens i
    join totais_pagamento tp on tp.pagamento_id = i.pagamento_id
    left join classificacao_titulo ct on ct.titulo_id = i.titulo_id
  ),
  caixa_mes as (
    select
      date_trunc('month', l.data_pagamento)::date as mes,
      sum(case when l.tipo = 'AR' then l.valor_movimento else 0 end)
        as recebimentos,
      sum(case when l.tipo = 'AP' then l.valor_movimento else 0 end)
        as pagamentos
    from linhas l
    group by date_trunc('month', l.data_pagamento)::date
  ),
  caixa_atual as (
    select
      coalesce(sum(case when l.tipo = 'AR' then l.valor_movimento else 0 end), 0)
        as recebimentos,
      coalesce(sum(case when l.tipo = 'AP' then l.valor_movimento else 0 end), 0)
        as pagamentos,
      coalesce(sum(
        case when l.tipo = 'AP'
          then l.valor_movimento * l.proporcao_investimento else 0 end
      ), 0) as investimentos_pagos,
      coalesce(sum(
        case when l.tipo = 'AP'
          then l.valor_movimento * l.proporcao_divida else 0 end
      ), 0) as divida_paga,
      coalesce(sum(case when l.tipo = 'AP' then l.juros_movimento else 0 end), 0) as juros,
      coalesce(sum(case when l.tipo = 'AP' then l.multa_movimento else 0 end), 0) as multas,
      coalesce(sum(case when l.tipo = 'AP' then l.desconto_movimento else 0 end), 0) as descontos
    from linhas l
    where l.data_pagamento between p_data_inicio and p_data_fim
  ),
  caixa_anterior as (
    select
      coalesce(sum(case when l.tipo = 'AR' then l.valor_movimento else 0 end), 0)
        as recebimentos,
      coalesce(sum(case when l.tipo = 'AP' then l.valor_movimento else 0 end), 0)
        as pagamentos,
      coalesce(sum(
        case when l.tipo = 'AP'
          then l.valor_movimento * l.proporcao_investimento else 0 end
      ), 0) as investimentos_pagos,
      coalesce(sum(
        case when l.tipo = 'AP'
          then l.valor_movimento * l.proporcao_divida else 0 end
      ), 0) as divida_paga
    from linhas l
    where l.data_pagamento
      between v_data_anterior_inicio and v_data_anterior_fim
  ),
  meses as (
    select generate_series(
      v_serie_inicio::timestamp,
      date_trunc('month', p_data_fim)::timestamp,
      interval '1 month'
    )::date as mes
  ),
  serie as (
    select
      m.mes,
      coalesce(cm.recebimentos, 0) as recebimentos,
      coalesce(cm.pagamentos, 0) as pagamentos
    from meses m
    left join caixa_mes cm on cm.mes = m.mes
  ),
  motivo_resumo as (
    select
      l.motivo_id,
      l.motivo_codigo,
      l.motivo_nome,
      sum(l.valor_movimento) as valor
    from linhas l
    where l.tipo = 'AP'
      and l.data_pagamento between p_data_inicio and p_data_fim
    group by l.motivo_id, l.motivo_codigo, l.motivo_nome
  ),
  fornecedor_resumo as (
    select
      l.fornecedor_id,
      coalesce(forn.nome, 'Sem fornecedor') as nome,
      count(distinct l.pagamento_id) as quantidade,
      sum(l.valor_movimento) as valor
    from linhas l
    left join public.fornecedores forn
      on forn.tenant_id = p_tenant_id
     and forn.empresa_id = p_empresa_id
     and forn.id = l.fornecedor_id
    where l.tipo = 'AP'
      and l.data_pagamento between p_data_inicio and p_data_fim
    group by l.fornecedor_id, coalesce(forn.nome, 'Sem fornecedor')
  ),
  movimentos_sem_direcao as (
    select coalesce(sum(
      greatest(p.valor - coalesce(a.valor_atribuido, 0), 0)
    ), 0) as valor
    from pagamentos p
    left join (
      select l.pagamento_id, sum(l.valor_movimento) as valor_atribuido
      from linhas l
      group by l.pagamento_id
    ) a on a.pagamento_id = p.id
    where p.data_pagamento between p_data_inicio and p_data_fim
  ),
  conciliacao as (
    select
      coalesce(sum(
        case when p.conciliado_at is null then p.valor else 0 end
      ), 0) as nao_conciliado,
      coalesce(sum(
        case
          when p.conciliado_at is null
           and p.data_pagamento < current_date - 7
          then p.valor
          else 0
        end
      ), 0) as nao_conciliado_7_dias
    from pagamentos p
    where p.data_pagamento between p_data_inicio and p_data_fim
  )
  select jsonb_build_object(
    'recebimentos', round(ca.recebimentos, 2),
    'pagamentos', round(ca.pagamentos, 2),
    'saldo', round(ca.recebimentos - ca.pagamentos, 2),
    'investimentosPagos', round(ca.investimentos_pagos, 2),
    'dividaPaga', round(ca.divida_paga, 2),
    'juros', round(ca.juros, 2),
    'multas', round(ca.multas, 2),
    'descontos', round(ca.descontos, 2),
    'naoConciliado', round(co.nao_conciliado, 2),
    'naoConciliado7Dias', round(co.nao_conciliado_7_dias, 2),
    'movimentosSemDirecao', round(msd.valor, 2),
    'anterior', jsonb_build_object(
      'recebimentos', round(can.recebimentos, 2),
      'pagamentos', round(can.pagamentos, 2),
      'saldo', round(can.recebimentos - can.pagamentos, 2),
      'investimentosPagos', round(can.investimentos_pagos, 2),
      'dividaPaga', round(can.divida_paga, 2)
    ),
    'serie', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'label', to_char(s.mes, 'MM/YYYY'),
          'mes', s.mes,
          'recebimentos', round(s.recebimentos, 2),
          'pagamentos', round(s.pagamentos, 2),
          'saldo', round(s.recebimentos - s.pagamentos, 2)
        )
        order by s.mes
      )
      from serie s
    ), '[]'::jsonb),
    'porMotivo', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', x.motivo_id,
          'codigo', x.motivo_codigo,
          'nome', x.motivo_nome,
          'valor', round(x.valor, 2),
          'percentual', case
            when ca.pagamentos = 0 then 0
            else round((x.valor / ca.pagamentos) * 100, 2)
          end
        )
        order by x.valor desc, x.motivo_nome
      )
      from (
        select mr.*
        from motivo_resumo mr
        order by mr.valor desc
        limit 12
      ) x
    ), '[]'::jsonb),
    'topFornecedores', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'fornecedorId', x.fornecedor_id,
          'nome', x.nome,
          'quantidade', x.quantidade,
          'valor', round(x.valor, 2),
          'percentual', case
            when ca.pagamentos = 0 then 0
            else round((x.valor / ca.pagamentos) * 100, 2)
          end
        )
        order by x.valor desc, x.nome
      )
      from (
        select fr.*
        from fornecedor_resumo fr
        order by fr.valor desc
        limit 10
      ) x
    ), '[]'::jsonb)
  )
  into v_caixa
  from caixa_atual ca
  cross join caixa_anterior can
  cross join conciliacao co
  cross join movimentos_sem_direcao msd;

  /*
   * Compromissos atuais. A cobertura de 30 dias é uma razão em vezes:
   * contas a receber nos próximos 30 dias / contas a pagar no mesmo intervalo.
   */
  with
  titulos_abertos as (
    select
      t.id,
      t.tipo,
      t.fornecedor_id,
      t.valor_total,
      t.valor_aberto,
      t.arrendamento_contrato_id,
      coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo
    from f.titulo t
    left join f.titulo_aprovacao ta
      on ta.tenant_id = p_tenant_id
     and ta.titulo_id = t.id
     and ta.deleted_at is null
    left join f.motivo_compra mc
      on mc.tenant_id = p_tenant_id
     and mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
     and mc.deleted_at is null
     and mc.ativo
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
      and t.valor_aberto > 0
  ),
  parcelas as (
    select
      ta.*,
      tp.id as parcela_id,
      tp.vencimento_date,
      tp.valor_aberto as parcela_aberto
    from titulos_abertos ta
    join f.titulo_parcela tp
      on tp.tenant_id = p_tenant_id
     and tp.titulo_id = ta.id
     and tp.deleted_at is null
     and tp.valor_aberto > 0
  ),
  classificacao as (
    select
      ta.id as titulo_id,
      ta.valor_total as valor_titulo,
      coalesce(sum(coalesce(
        tr.valor,
        round(ta.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
        0
      )), 0) as valor_rateado,
      coalesce(sum(
        case
          when exists (
            select 1
            from r.dre_plano_excluido dpe
            where dpe.tenant_id = p_tenant_id
              and dpe.plano_contas_id = tr.plano_contas_id
          )
          then coalesce(
            tr.valor,
            round(ta.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
            0
          )
          else 0
        end
      ), 0) as investimento,
      coalesce(sum(
        case
          when pc.codigo = 'DESP_FINANCIAMENTO'
            or ta.motivo_codigo = 'FINANCIAMENTO_RURAL'
            or exists (
          select 1
          from f.arrendamento_contrato ac_scope
          where ac_scope.id = ta.arrendamento_contrato_id
            and ac_scope.tenant_id = p_tenant_id
            and ac_scope.empresa_id = p_empresa_id
            and ac_scope.ativo
            and ac_scope.deleted_at is null
        )
          then coalesce(
            tr.valor,
            round(ta.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
            0
          )
          else 0
        end
      ), 0) as divida,
      count(tr.id) as quantidade_rateios
    from titulos_abertos ta
    left join f.titulo_rateio tr
      on tr.tenant_id = p_tenant_id
     and tr.titulo_id = ta.id
     and tr.deleted_at is null
    left join f.plano_contas pc
      on pc.tenant_id = p_tenant_id
     and pc.id = tr.plano_contas_id
     and pc.deleted_at is null
    group by
      ta.id,
      ta.valor_total,
      ta.motivo_codigo,
      ta.arrendamento_contrato_id
  ),
  parcelas_classificadas as (
    select
      p.*,
      case
        when c.quantidade_rateios > 0 and c.valor_titulo > 0
        then least(greatest(c.investimento / c.valor_titulo, 0), 1)
        when p.motivo_codigo = 'INVESTIMENTO' then 1
        else 0
      end as proporcao_investimento,
      case
        when p.motivo_codigo = 'FINANCIAMENTO_RURAL'
          or exists (
          select 1
          from f.arrendamento_contrato ac_scope
          where ac_scope.id = p.arrendamento_contrato_id
            and ac_scope.tenant_id = p_tenant_id
            and ac_scope.empresa_id = p_empresa_id
            and ac_scope.ativo
            and ac_scope.deleted_at is null
        )
        then 1
        when c.quantidade_rateios > 0 and c.valor_titulo > 0
        then least(greatest(c.divida / c.valor_titulo, 0), 1)
        else 0
      end as proporcao_divida
    from parcelas p
    left join classificacao c on c.titulo_id = p.id
  ),
  abertos as (
    select
      coalesce(sum(case when ta.tipo = 'AP' then ta.valor_aberto else 0 end), 0)
        as ap_aberto,
      coalesce(sum(case when ta.tipo = 'AR' then ta.valor_aberto else 0 end), 0)
        as ar_aberto,
      coalesce(sum(case when ta.tipo = 'AP' then ta.valor_aberto *
        case
          when ta.motivo_codigo = 'FINANCIAMENTO_RURAL'
            or exists (
          select 1
          from f.arrendamento_contrato ac_scope
          where ac_scope.id = ta.arrendamento_contrato_id
            and ac_scope.tenant_id = p_tenant_id
            and ac_scope.empresa_id = p_empresa_id
            and ac_scope.ativo
            and ac_scope.deleted_at is null
        ) then 1
          when c.quantidade_rateios > 0 and c.valor_titulo > 0
            then least(greatest(c.divida / c.valor_titulo, 0), 1)
          else 0
        end
      else 0 end), 0) as divida_aberta,
      coalesce(sum(case when ta.tipo = 'AP' then ta.valor_aberto *
        case
          when c.quantidade_rateios > 0 and c.valor_titulo > 0
            then least(greatest(c.investimento / c.valor_titulo, 0), 1)
          when ta.motivo_codigo = 'INVESTIMENTO' then 1
          else 0
        end
      else 0 end), 0) as investimentos_abertos
    from titulos_abertos ta
    left join classificacao c on c.titulo_id = ta.id
  ),
  resumo as (
    select
      coalesce(sum(case when pc.tipo = 'AP'
        and pc.vencimento_date < current_date
        then pc.parcela_aberto else 0 end), 0) as ap_vencido,
      coalesce(sum(case when pc.tipo = 'AP'
        and pc.vencimento_date between current_date and current_date + 30
        then pc.parcela_aberto else 0 end), 0) as ap_vencer_30,
      coalesce(sum(case when pc.tipo = 'AR'
        and pc.vencimento_date < current_date
        then pc.parcela_aberto else 0 end), 0) as ar_vencido,
      coalesce(sum(case when pc.tipo = 'AR'
        and pc.vencimento_date between current_date and current_date + 30
        then pc.parcela_aberto else 0 end), 0) as ar_vencer_30
    from parcelas_classificadas pc
  ),
  aging as (
    select
      coalesce(sum(case when p.vencimento_date >= current_date
        then p.parcela_aberto else 0 end), 0) as a_vencer,
      coalesce(sum(case when current_date - p.vencimento_date between 1 and 30
        then p.parcela_aberto else 0 end), 0) as vencido_0_30,
      coalesce(sum(case when current_date - p.vencimento_date between 31 and 60
        then p.parcela_aberto else 0 end), 0) as vencido_31_60,
      coalesce(sum(case when current_date - p.vencimento_date between 61 and 90
        then p.parcela_aberto else 0 end), 0) as vencido_61_90,
      coalesce(sum(case when current_date - p.vencimento_date > 90
        then p.parcela_aberto else 0 end), 0) as vencido_mais_90
    from parcelas p
    where p.tipo = 'AP'
  ),
  ap_periodo as (
    select
      coalesce(sum(t.valor_total), 0) as total,
      coalesce(sum(t.valor_aberto), 0) as aberto,
      count(*) as quantidade
    from f.titulo t
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
      and t.tipo = 'AP'
      and t.competencia_date between p_data_inicio and p_data_fim
  )
  select jsonb_build_object(
    'apAberto', round(ab.ap_aberto, 2),
    'apVencido', round(r.ap_vencido, 2),
    'apVencer30', round(r.ap_vencer_30, 2),
    'arAberto', round(ab.ar_aberto, 2),
    'arVencido', round(r.ar_vencido, 2),
    'arVencer30', round(r.ar_vencer_30, 2),
    'cobertura30', case
      when r.ap_vencer_30 = 0 then null
      else round(r.ar_vencer_30 / r.ap_vencer_30, 4)
    end,
    'dividaAberta', round(ab.divida_aberta, 2),
    'investimentosAbertos', round(ab.investimentos_abertos, 2),
    'apPeriodoTotal', round(ap.total, 2),
    'apPeriodoAberto', round(ap.aberto, 2),
    'apPeriodoQtd', ap.quantidade,
    'agingAp', jsonb_build_object(
      'aVencer', round(ag.a_vencer, 2),
      'vencido0a30', round(ag.vencido_0_30, 2),
      'vencido31a60', round(ag.vencido_31_60, 2),
      'vencido61a90', round(ag.vencido_61_90, 2),
      'vencidoMais90', round(ag.vencido_mais_90, 2)
    )
  )
  into v_compromissos
  from resumo r
  cross join abertos ab
  cross join aging ag
  cross join ap_periodo ap;

  /*
   * Qualidade. Títulos sem competência entram pelo fallback emissão/criação,
   * para que a própria ausência da competência não os esconda do período.
   */
  with
  titulos as (
    select
      t.id,
      t.tipo,
      t.status,
      t.fornecedor_id,
      t.cliente_id,
      t.documento_fiscal_id,
      t.descricao,
      t.emissao_date,
      t.competencia_date,
      t.created_at::date as criado_date,
      t.valor_total,
      t.valor_aberto,
      t.arrendamento_contrato_id,
      coalesce(ta.motivo_compra_id, t.motivo_compra_id) as motivo_informado_id,
      mc.id as motivo_id,
      mc.codigo as motivo_codigo
    from f.titulo t
    left join f.titulo_aprovacao ta
      on ta.tenant_id = p_tenant_id
     and ta.titulo_id = t.id
     and ta.deleted_at is null
    left join f.motivo_compra mc
      on mc.tenant_id = p_tenant_id
     and mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
     and mc.deleted_at is null
     and mc.ativo
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
      and (
        coalesce(t.competencia_date, t.emissao_date, t.created_at::date)
          between p_data_inicio and p_data_fim
        or t.valor_aberto > 0
      )
  ),
  parcela_stats as (
    select
      t.id as titulo_id,
      count(tp.id) as quantidade,
      coalesce(sum(tp.valor), 0) as valor,
      coalesce(sum(tp.valor_aberto), 0) as valor_aberto
    from titulos t
    left join f.titulo_parcela tp
      on tp.tenant_id = p_tenant_id
     and tp.titulo_id = t.id
     and tp.deleted_at is null
    group by t.id
  ),
  rateio_stats as (
    select
      t.id as titulo_id,
      count(tr.id) as quantidade,
      count(tr.percentual) as quantidade_percentual,
      coalesce(sum(coalesce(
        tr.valor,
        round(t.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
        0
      )), 0) as valor,
      coalesce(sum(tr.percentual), 0) as percentual,
      count(*) filter (where tr.id is not null and tr.plano_contas_id is null)
        as sem_plano,
      count(*) filter (
        where tr.plano_contas_id is not null
          and (pc.id is null or not pc.ativo)
      ) as plano_invalido,
      count(*) filter (where tr.id is not null and tr.centro_custo_id is null)
        as sem_centro,
      count(*) filter (
        where tr.centro_custo_id is not null
          and (cc.id is null or not cc.ativo)
      ) as centro_invalido,
      coalesce(sum(case
        when pc.id is not null and pc.ativo
        then coalesce(
          tr.valor,
          round(t.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
          0
        )
        else 0
      end), 0) as valor_plano_valido,
      coalesce(sum(case
        when cc.id is not null and cc.ativo
        then coalesce(
          tr.valor,
          round(t.valor_total * coalesce(tr.percentual, 0) / 100.0, 2),
          0
        )
        else 0
      end), 0) as valor_centro_valido,
      bool_or(pc.codigo = 'DESP_FINANCIAMENTO') as plano_divida
    from titulos t
    left join f.titulo_rateio tr
      on tr.tenant_id = p_tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    left join f.plano_contas pc
      on pc.tenant_id = p_tenant_id
     and pc.id = tr.plano_contas_id
     and pc.deleted_at is null
    left join f.centro_custo cc
      on cc.tenant_id = p_tenant_id
     and cc.empresa_id = p_empresa_id
     and cc.id = tr.centro_custo_id
     and cc.deleted_at is null
    group by t.id, t.valor_total
  ),
  centros_ativos as (
    select count(*) as quantidade
    from f.centro_custo cc
    where cc.tenant_id = p_tenant_id
      and cc.empresa_id = p_empresa_id
      and cc.ativo
      and cc.deleted_at is null
  ),
  documentos_duplicados as (
    select
      t.documento_fiscal_id,
      t.tipo
    from f.titulo t
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
      and t.documento_fiscal_id is not null
    group by t.documento_fiscal_id, t.tipo
    having count(*) > 1
  ),
  pagamentos as (
    select
      p.id,
      p.data_pagamento,
      p.valor,
      p.valor_principal,
      p.conciliado_at
    from f.pagamento p
    where p.tenant_id = p_tenant_id
      and p.empresa_id = p_empresa_id
      and p.deleted_at is null
      and p.data_pagamento between p_data_inicio and p_data_fim
  ),
  pagamento_stats as (
    select
      p.id as pagamento_id,
      count(pi.id) as quantidade_itens,
      count(pi.id) filter (
        where t.id is not null and t.status <> 'CANCELADO'
      ) as quantidade_itens_validos,
      coalesce(sum(pi.valor), 0) as valor_itens,
      count(distinct t.tipo) filter (where t.status <> 'CANCELADO')
        as quantidade_tipos
    from pagamentos p
    left join f.pagamento_item pi
      on pi.tenant_id = p_tenant_id
     and pi.empresa_id = p_empresa_id
     and pi.pagamento_id = p.id
     and pi.deleted_at is null
    left join f.titulo_parcela tp
      on tp.tenant_id = p_tenant_id
     and tp.id = pi.titulo_parcela_id
     and tp.deleted_at is null
    left join f.titulo t
      on t.tenant_id = p_tenant_id
     and t.empresa_id = p_empresa_id
     and t.id = tp.titulo_id
     and t.deleted_at is null
    group by p.id
  ),
  cobertura as (
    select
      coalesce(sum(case
        when t.tipo = 'AP' then greatest(t.valor_total, 0)
        else 0
      end), 0) as total_ap,
      coalesce(sum(case
        when t.tipo = 'AP'
        then least(greatest(rs.valor, 0), greatest(t.valor_total, 0))
        else 0
      end), 0) as coberto_rateio,
      coalesce(sum(case
        when t.tipo = 'AP'
        then least(
          greatest(rs.valor_centro_valido, 0),
          greatest(t.valor_total, 0)
        )
        else 0
      end), 0) as coberto_centro,
      coalesce(sum(case
        when t.tipo = 'AP' and t.motivo_id is not null
          then greatest(t.valor_total, 0)
        when t.tipo = 'AP'
          then least(
            greatest(rs.valor_plano_valido, 0),
            greatest(t.valor_total, 0)
          )
        else 0
      end), 0) as coberto_classificacao
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
  ),
  alertas as (
    select
      'PARCELAS_DIVERGEM_TOTAL:' || t.id::text as id,
      'CRITICO'::text as severidade,
      'PARCELAS_DIVERGEM_TOTAL'::text as codigo,
      'Soma das parcelas diverge do título'::text as titulo_alerta,
      'titulo'::text as entidade,
      t.id as entidade_id,
      coalesce(nullif(t.descricao, ''), t.id::text) as referencia,
      coalesce(t.competencia_date, t.emissao_date, t.criado_date) as data_ref,
      t.valor_total as valor,
      format(
        'Título: %s; parcelas: %s.',
        round(t.valor_total, 2),
        round(ps.valor, 2)
      ) as detalhe,
      'Revisar valores e quantidade das parcelas.'::text as acao
    from titulos t
    join parcela_stats ps on ps.titulo_id = t.id
    where abs(ps.valor - t.valor_total) > 0.01

    union all

    select
      'SALDO_PARCELAS_DIVERGE:' || t.id::text,
      'CRITICO',
      'SALDO_PARCELAS_DIVERGE',
      'Saldo das parcelas diverge do título',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_aberto,
      format(
        'Saldo do título: %s; saldo das parcelas: %s.',
        round(t.valor_aberto, 2),
        round(ps.valor_aberto, 2)
      ),
      'Reprocessar ou corrigir a baixa das parcelas.'
    from titulos t
    join parcela_stats ps on ps.titulo_id = t.id
    where abs(ps.valor_aberto - t.valor_aberto) > 0.01

    union all

    select
      'STATUS_SALDO_INCONSISTENTE:' || t.id::text,
      'CRITICO',
      'STATUS_SALDO_INCONSISTENTE',
      'Status incompatível com o saldo',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_aberto,
      format('Status: %s; saldo: %s.', t.status, round(t.valor_aberto, 2)),
      'Revisar o status ou as baixas do título.'
    from titulos t
    where (t.status = 'PAGO' and abs(t.valor_aberto) > 0.01)
       or (t.status <> 'PAGO' and t.valor_total > 0 and t.valor_aberto <= 0.01)

    union all

    select
      'DOCUMENTO_DUPLICADO:' || t.id::text,
      'CRITICO',
      'DOCUMENTO_DUPLICADO',
      'Documento financeiro duplicado',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.documento_fiscal_id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'Há mais de um título ativo do mesmo tipo para o documento fiscal.',
      'Comparar os títulos e cancelar somente o lançamento indevido.'
    from titulos t
    join documentos_duplicados dd
      on dd.documento_fiscal_id = t.documento_fiscal_id
     and dd.tipo = t.tipo

    union all

    select
      'ESCOPO_RELACIONAMENTO_DIVERGENTE:' || t.id::text,
      'CRITICO',
      'ESCOPO_RELACIONAMENTO_DIVERGENTE',
      'Relacionamento fora do tenant',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'Existe parcela, rateio ou aprovação vinculada com tenant divergente.',
      'Corrigir o vínculo antes de qualquer baixa ou alteração.'
    from titulos t
    where exists (
      select 1
      from f.titulo_parcela tp_x
      where tp_x.titulo_id = t.id
        and tp_x.deleted_at is null
        and tp_x.tenant_id is distinct from p_tenant_id
    )
    or exists (
      select 1
      from f.titulo_rateio tr_x
      where tr_x.titulo_id = t.id
        and tr_x.deleted_at is null
        and tr_x.tenant_id is distinct from p_tenant_id
    )
    or exists (
      select 1
      from f.titulo_aprovacao ta_x
      where ta_x.titulo_id = t.id
        and ta_x.deleted_at is null
        and ta_x.tenant_id is distinct from p_tenant_id
    )

    union all

    select
      'PAGAMENTO_SEM_VINCULO_VALIDO:' || p.id::text,
      'CRITICO',
      'PAGAMENTO_SEM_VINCULO_VALIDO',
      'Pagamento sem vínculo financeiro válido',
      'pagamento',
      p.id,
      p.id::text,
      p.data_pagamento,
      p.valor,
      'O cabeçalho não possui item ligado a parcela e título ativos, não cancelados, no mesmo escopo.',
      'Vincular as parcelas corretas ou estornar o pagamento.'
    from pagamentos p
    join pagamento_stats ps on ps.pagamento_id = p.id
    where ps.quantidade_itens_validos = 0

    union all

    select
      'PAGAMENTO_VINCULO_PARCIAL_INVALIDO:' || p.id::text,
      'CRITICO',
      'PAGAMENTO_VINCULO_PARCIAL_INVALIDO',
      'Pagamento possui vínculo inválido',
      'pagamento',
      p.id,
      p.id::text,
      p.data_pagamento,
      p.valor,
      'Parte dos itens não aponta para parcela e título ativos, não cancelados, no mesmo escopo.',
      'Corrigir os vínculos; a parcela sem direção não foi forçada para AP ou AR.'
    from pagamentos p
    join pagamento_stats ps on ps.pagamento_id = p.id
    where ps.quantidade_itens_validos > 0
      and ps.quantidade_itens_validos < ps.quantidade_itens

    union all

    select
      'PAGAMENTO_TIPOS_MISTOS:' || p.id::text,
      'CRITICO',
      'PAGAMENTO_TIPOS_MISTOS',
      'Pagamento mistura contas a pagar e receber',
      'pagamento',
      p.id,
      p.id::text,
      p.data_pagamento,
      p.valor,
      'O mesmo pagamento está aplicado a títulos AP e AR.',
      'Separar o pagamento em movimentos financeiros distintos.'
    from pagamentos p
    join pagamento_stats ps on ps.pagamento_id = p.id
    where ps.quantidade_tipos > 1

    union all

    select
      'PAGAMENTO_PRINCIPAL_DIVERGENTE:' || p.id::text,
      'CRITICO',
      'PAGAMENTO_PRINCIPAL_DIVERGENTE',
      'Itens divergem do principal do pagamento',
      'pagamento',
      p.id,
      p.id::text,
      p.data_pagamento,
      p.valor,
      format(
        'Principal: %s; itens: %s.',
        round(p.valor_principal, 2),
        round(ps.valor_itens, 2)
      ),
      'Revisar a composição do pagamento e suas aplicações.'
    from pagamentos p
    join pagamento_stats ps on ps.pagamento_id = p.id
    where abs(ps.valor_itens - p.valor_principal) > 0.01

    union all

    select
      'PAGAMENTO_ESCOPO_DIVERGENTE:' || p.id::text,
      'CRITICO',
      'PAGAMENTO_ESCOPO_DIVERGENTE',
      'Item de pagamento fora do escopo',
      'pagamento',
      p.id,
      p.id::text,
      p.data_pagamento,
      p.valor,
      'Existe item, parcela ou título ligado com tenant/empresa divergente.',
      'Corrigir o vínculo antes de conciliar o pagamento.'
    from pagamentos p
    where exists (
      select 1
      from f.pagamento_item pi_x
      left join f.titulo_parcela tp_x on tp_x.id = pi_x.titulo_parcela_id
      left join f.titulo t_x on t_x.id = tp_x.titulo_id
      where pi_x.pagamento_id = p.id
        and pi_x.deleted_at is null
        and (
          pi_x.tenant_id is distinct from p_tenant_id
          or pi_x.empresa_id is distinct from p_empresa_id
          or tp_x.tenant_id is distinct from p_tenant_id
          or t_x.tenant_id is distinct from p_tenant_id
          or t_x.empresa_id is distinct from p_empresa_id
        )
    )

    union all

    select
      'CANCELADO_COM_SALDO:' || t.id::text,
      'CRITICO',
      'CANCELADO_COM_SALDO',
      'Título cancelado mantém saldo em aberto',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.created_at::date),
      t.valor_aberto,
      format('Título cancelado com saldo de %s.', round(t.valor_aberto, 2)),
      'Zerar o saldo mediante estorno correto ou revisar o cancelamento.'
    from f.titulo t
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.deleted_at is null
      and t.status = 'CANCELADO'
      and t.valor_aberto > 0.01

    union all

    select
      'COMPETENCIA_AUSENTE:' || t.id::text,
      'ALTO',
      'COMPETENCIA_AUSENTE',
      'Competência não informada',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.emissao_date, t.criado_date),
      t.valor_total,
      'O lançamento não participa corretamente da análise por competência.',
      'Informar a competência contábil do título.'
    from titulos t
    where t.competencia_date is null

    union all

    select
      'CONTRAPARTE_INVALIDA:' || t.id::text,
      'ALTO',
      'CONTRAPARTE_INVALIDA',
      case when t.tipo = 'AP' then 'Fornecedor inválido ou fora da empresa'
           else 'Cliente inválido ou fora da empresa' end,
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'A contraparte informada não está ativa no mesmo tenant e empresa.',
      case when t.tipo = 'AP' then 'Vincular um fornecedor ativo desta empresa.'
           else 'Vincular um cliente ativo desta empresa.' end
    from titulos t
    where (
      t.tipo = 'AP'
      and t.fornecedor_id is not null
      and not exists (
        select 1
        from public.fornecedores f_x
        where f_x.id = t.fornecedor_id
          and f_x.tenant_id = p_tenant_id
          and f_x.empresa_id = p_empresa_id
          and coalesce(f_x.ativo, true)
      )
    ) or (
      t.tipo = 'AR'
      and t.cliente_id is not null
      and not exists (
        select 1
        from public.clientes c_x
        where c_x.id = t.cliente_id
          and c_x.tenant_id = p_tenant_id
          and c_x.empresa_id = p_empresa_id
          and coalesce(c_x.ativo, true)
      )
    )

    union all

    select
      'PARTE_AUSENTE:' || t.id::text,
      'ALTO',
      'PARTE_AUSENTE',
      case when t.tipo = 'AP' then 'Fornecedor não informado'
           else 'Cliente não informado' end,
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'O título não possui a contraparte esperada para o seu tipo.',
      case when t.tipo = 'AP' then 'Vincular o fornecedor correto.'
           else 'Vincular o cliente correto.' end
    from titulos t
    where (t.tipo = 'AP' and t.fornecedor_id is null)
       or (t.tipo = 'AR' and t.cliente_id is null)

    union all

    select
      'SEM_RATEIO:' || t.id::text,
      'ALTO',
      'SEM_RATEIO',
      'Título sem rateio',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'Sem rateio, o valor não entra no resultado gerencial por competência.',
      'Criar o rateio com plano de contas e centro de custo.'
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
    where rs.quantidade = 0

    union all

    select
      'RATEIO_SEM_PLANO:' || t.id::text,
      'ALTO',
      'RATEIO_SEM_PLANO',
      'Rateio sem plano de contas',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      format('%s rateio(s) sem plano de contas.', rs.sem_plano),
      'Classificar todos os rateios no plano de contas.'
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
    where rs.sem_plano > 0

    union all

    select
      'RATEIO_DIVERGENTE:' || t.id::text,
      'ALTO',
      'RATEIO_DIVERGENTE',
      'Soma do rateio diverge do título',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      format(
        'Título: %s; rateio: %s; percentual: %s%%.',
        round(t.valor_total, 2),
        round(rs.valor, 2),
        round(rs.percentual, 4)
      ),
      'Ajustar os rateios para totalizar o título e 100%.'
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
    where rs.quantidade > 0
      and (
        abs(rs.valor - t.valor_total) > 0.01
        or (
          rs.quantidade_percentual = rs.quantidade
          and abs(rs.percentual - 100) > 0.0001
        )
      )

    union all

    select
      'PLANO_INVALIDO:' || t.id::text,
      'ALTO',
      'PLANO_INVALIDO',
      'Plano de contas inválido ou inativo',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      format(
        '%s rateio(s) usam plano inválido, excluído ou de outro tenant.',
        rs.plano_invalido
      ),
      'Substituir pelo plano de contas ativo correto.'
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
    where rs.plano_invalido > 0

    union all

    select
      'CENTRO_INVALIDO:' || t.id::text,
      'ALTO',
      'CENTRO_INVALIDO',
      'Centro de custo inválido ou inativo',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      format(
        '%s rateio(s) usam centro inválido, excluído ou de outra empresa.',
        rs.centro_invalido
      ),
      'Substituir pelo centro de custo ativo correto.'
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
    where rs.centro_invalido > 0

    union all

    select
      'MOTIVO_INVALIDO:' || t.id::text,
      'ALTO',
      'MOTIVO_INVALIDO',
      'Motivo da compra inválido ou inativo',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'O motivo informado não está ativo no tenant da empresa.',
      'Selecionar um motivo de compra ativo e válido.'
    from titulos t
    where t.tipo = 'AP'
      and t.motivo_informado_id is not null
      and t.motivo_id is null

    union all

    select
      'MOTIVO_AUSENTE:' || t.id::text,
      'MEDIO',
      'MOTIVO_AUSENTE',
      'Motivo da compra não informado',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'O AP não possui motivo efetivo no título nem na aprovação.',
      'Informar o motivo da compra.'
    from titulos t
    where t.tipo = 'AP'
      and t.motivo_informado_id is null

    union all

    select
      'CENTRO_CUSTO_AUSENTE:' || t.id::text,
      'MEDIO',
      'CENTRO_CUSTO_AUSENTE',
      'Centro de custo não informado',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      format('%s rateio(s) sem centro de custo.', rs.sem_centro),
      'Distribuir o gasto nos centros de custo responsáveis.'
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
    cross join centros_ativos ca
    where ca.quantidade > 0
      and rs.quantidade > 0
      and rs.sem_centro > 0

    union all

    select
      'SEM_CENTROS_CADASTRADOS:GLOBAL',
      'MEDIO',
      'SEM_CENTROS_CADASTRADOS',
      'Empresa sem centros de custo ativos',
      'configuracao',
      null::uuid,
      'Configuração financeira',
      p_data_fim,
      0::numeric,
      'Há AP no período, mas não existe centro de custo ativo.',
      'Cadastrar a estrutura mínima de centros de custo.'
    from centros_ativos ca
    where ca.quantidade = 0
      and exists (select 1 from titulos t where t.tipo = 'AP')

    union all

    select
      'PAGAMENTO_NAO_CONCILIADO:' || p.id::text,
      'MEDIO',
      'PAGAMENTO_NAO_CONCILIADO',
      'Pagamento sem conciliação há mais de 7 dias',
      'pagamento',
      p.id,
      p.id::text,
      p.data_pagamento,
      p.valor,
      format('%s dia(s) sem conciliação.', current_date - p.data_pagamento),
      'Conciliar com o extrato bancário ou revisar o lançamento.'
    from pagamentos p
    where p.conciliado_at is null
      and p.data_pagamento < current_date - 7

    union all

    select
      'ARRENDAMENTO_INVALIDO:' || t.id::text,
      'ALTO',
      'ARRENDAMENTO_INVALIDO',
      'Contrato de arrendamento inválido ou fora do escopo',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'O contrato informado não está ativo no mesmo tenant e empresa.',
      'Vincular o contrato correto ou remover a referência inválida.'
    from titulos t
    where t.arrendamento_contrato_id is not null
      and not exists (
        select 1
        from f.arrendamento_contrato ac_x
        where ac_x.id = t.arrendamento_contrato_id
          and ac_x.tenant_id = p_tenant_id
          and ac_x.empresa_id = p_empresa_id
          and ac_x.ativo
          and ac_x.deleted_at is null
      )

    union all

    select
      'POSSIVEL_DIVIDA_NAO_CLASSIFICADA:' || t.id::text,
      'MEDIO',
      'POSSIVEL_DIVIDA_NAO_CLASSIFICADA',
      'Possível dívida sem classificação explícita',
      'titulo',
      t.id,
      coalesce(nullif(t.descricao, ''), t.id::text),
      coalesce(t.competencia_date, t.emissao_date, t.criado_date),
      t.valor_total,
      'A descrição sugere financiamento, consórcio, leasing ou parcelamento.',
      'Confirmar a natureza e classificar como dívida quando aplicável.'
    from titulos t
    join rateio_stats rs on rs.titulo_id = t.id
    where t.tipo = 'AP'
      and coalesce(t.descricao, '')
        ~* '(FINANCIAMENTO|CONS[ÓO]RCIO|LEASING|PARCELAMENTO)'
      and not exists (
        select 1
        from f.arrendamento_contrato ac_x
        where ac_x.id = t.arrendamento_contrato_id
          and ac_x.tenant_id = p_tenant_id
          and ac_x.empresa_id = p_empresa_id
          and ac_x.ativo
          and ac_x.deleted_at is null
      )
      and coalesce(t.motivo_codigo, '') <> 'FINANCIAMENTO_RURAL'
      and not coalesce(rs.plano_divida, false)
  ),
  valor_afetado as (
    select coalesce(sum(x.valor), 0) as valor
    from (
      select
        a.entidade,
        a.entidade_id,
        max(abs(coalesce(a.valor, 0))) as valor
      from alertas a
      where a.entidade_id is not null
      group by a.entidade, a.entidade_id
    ) x
  )
  select jsonb_build_object(
    'coberturaRateioPct', case
      when c.total_ap = 0 then 100
      else round((c.coberto_rateio / c.total_ap) * 100, 2)
    end,
    'coberturaCentroPct', case
      when c.total_ap = 0 then 100
      else round((c.coberto_centro / c.total_ap) * 100, 2)
    end,
    'coberturaClassificacaoPct', case
      when c.total_ap = 0 then 100
      else round((c.coberto_classificacao / c.total_ap) * 100, 2)
    end,
    'totalAlertas', (select count(*) from alertas),
    'titulosAfetados', (
      select count(distinct a.entidade_id)
      from alertas a
      where a.entidade = 'titulo'
    ),
    'valorAfetado', round(va.valor, 2),
    'porSeveridade', jsonb_build_object(
      'critico', (
        select count(*) from alertas a where a.severidade = 'CRITICO'
      ),
      'alto', (
        select count(*) from alertas a where a.severidade = 'ALTO'
      ),
      'medio', (
        select count(*) from alertas a where a.severidade = 'MEDIO'
      )
    ),
    'porTipo', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'codigo', x.codigo,
          'titulo', x.titulo_alerta,
          'severidade', x.severidade,
          'quantidade', x.quantidade,
          'valor', round(x.valor, 2)
        )
        order by
          case x.severidade
            when 'CRITICO' then 1
            when 'ALTO' then 2
            else 3
          end,
          x.quantidade desc,
          x.titulo_alerta
      )
      from (
        select
          a.codigo,
          a.titulo_alerta,
          a.severidade,
          count(*) as quantidade,
          sum(abs(coalesce(a.valor, 0))) as valor
        from alertas a
        group by a.codigo, a.titulo_alerta, a.severidade
      ) x
    ), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', x.id,
          'severidade', x.severidade,
          'codigo', x.codigo,
          'tipo', x.codigo,
          'titulo', x.titulo_alerta,
          'entidade', x.entidade,
          'entidadeId', x.entidade_id,
          'referencia', x.referencia,
          'data', x.data_ref,
          'valor', round(coalesce(x.valor, 0), 2),
          'detalhe', x.detalhe,
          'acao', x.acao
        )
        order by
          case x.severidade
            when 'CRITICO' then 1
            when 'ALTO' then 2
            else 3
          end,
          x.data_ref desc nulls last,
          x.referencia
      )
      from (
        select a.*
        from alertas a
        order by
          case a.severidade
            when 'CRITICO' then 1
            when 'ALTO' then 2
            else 3
          end,
          a.data_ref desc nulls last
        limit 250
      ) x
    ), '[]'::jsonb)
  )
  into v_qualidade
  from cobertura c
  cross join valor_afetado va;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'tenantId', p_tenant_id,
      'empresaId', p_empresa_id,
      'dataInicio', p_data_inicio,
      'dataFim', p_data_fim,
      'periodoAnteriorInicio', v_data_anterior_inicio,
      'periodoAnteriorFim', v_data_anterior_fim,
      'compromissosReferencia', current_date,
      'geradoEm', statement_timestamp(),
      'moeda', 'BRL',
      'metodologia',
        'Resultado e caixa seguem o período filtrado. AP/AR aberto, aging e cobertura representam a posição atual. Qualidade inclui o período e títulos ainda abertos. Investimentos são excluídos do resultado e podem também estar classificados como dívida.'
    ),
    'competencia', coalesce(v_competencia, '{}'::jsonb),
    'caixa', coalesce(v_caixa, '{}'::jsonb),
    'compromissos', coalesce(v_compromissos, '{}'::jsonb),
    'qualidade', coalesce(v_qualidade, '{}'::jsonb)
  );
end;
$function$;

comment on function f.relatorio_saude_financeira(uuid, uuid, date, date) is
  'Visão gerencial de saúde financeira, caixa, compromissos e qualidade dos lançamentos, isolada por tenant e empresa.';

revoke all on function f.relatorio_saude_financeira(uuid, uuid, date, date)
  from public;
revoke all on function f.relatorio_saude_financeira(uuid, uuid, date, date)
  from anon;
grant execute on function f.relatorio_saude_financeira(uuid, uuid, date, date)
  to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
