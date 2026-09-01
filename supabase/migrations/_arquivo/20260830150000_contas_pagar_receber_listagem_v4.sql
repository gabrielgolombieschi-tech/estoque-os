begin;

create or replace function f.contas_pagar_receber_listar_v4(
  p_tenant_id uuid,
  p_empresa_ids uuid[],
  p_data_inicio date,
  p_data_fim date,
  p_data_base text default 'vencimento'
)
returns table (
  empresa_id uuid,
  tipo text,
  nf_numero text,
  titulo_id uuid,
  parcela_id uuid,
  parcela_numero text,
  total_parcelas bigint,
  emissao_date date,
  competencia_date date,
  vencimento_date date,
  data_base date,
  pessoa_nome text,
  descricao text,
  motivo_codigo text,
  motivo_nome text,
  aprovado_por_nome text,
  os_id integer,
  os_numero text,
  valor numeric,
  valor_aberto numeric,
  titulo_status text,
  formas_aplicadas text[],
  formas_agendadas text[],
  contas_aplicadas text[],
  contas_agendadas text[],
  pagamento_import_json jsonb
)
language plpgsql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null
     or p_tenant_id is distinct from public.current_tenant_id() then
    raise exception 'Tenant invalido para a sessao atual';
  end if;

  if coalesce(cardinality(p_empresa_ids), 0) = 0 then
    raise exception 'Informe ao menos uma empresa';
  end if;

  if p_data_inicio is null or p_data_fim is null or p_data_inicio > p_data_fim then
    raise exception 'Periodo invalido';
  end if;

  p_data_base := lower(trim(coalesce(p_data_base, 'vencimento')));
  if p_data_base not in ('vencimento', 'emissao', 'competencia') then
    raise exception 'Base de data invalida: %', p_data_base;
  end if;

  if exists (
    select 1
    from unnest(p_empresa_ids) as requested(empresa_id)
    where not exists (
      select 1
      from c.empresa e
      where e.id = requested.empresa_id
        and e.tenant_id = p_tenant_id
        and e.deleted_at is null
    )
       or not f.has_finance_access(p_tenant_id, requested.empresa_id)
  ) then
    raise exception 'Sem acesso financeiro a uma das empresas solicitadas';
  end if;

  return query
  with parcelas as (
    select
      t.empresa_id,
      t.tipo,
      df.numero as nf_numero,
      t.id as titulo_id,
      tp.id as parcela_id,
      tp.numero as parcela_numero,
      coalesce(
        nullif(t.total_parcelas_serie, 0)::bigint,
        (
          select count(*)
          from f.titulo_parcela parcela_total
          where parcela_total.tenant_id = p_tenant_id
            and parcela_total.titulo_id = t.id
            and parcela_total.deleted_at is null
        )
      ) as total_parcelas,
      t.emissao_date,
      t.competencia_date,
      tp.vencimento_date,
      case p_data_base
        when 'emissao' then coalesce(t.emissao_date, tp.vencimento_date)
        when 'competencia' then coalesce(t.competencia_date, t.emissao_date, tp.vencimento_date)
        else tp.vencimento_date
      end as data_base,
      case
        when t.tipo = 'AP' then coalesce(forn.nome::text, 'Fornecedor')
        else coalesce(cli.nome::text, cli.razao_social::text, 'Cliente')
      end as pessoa_nome,
      t.descricao,
      mc.codigo as motivo_codigo,
      mc.nome as motivo_nome,
      aprovador.nome as aprovado_por_nome,
      coalesce(t.os_id, df.os_id_import, rateio_os.os_id) as os_id,
      tp.valor,
      tp.valor_aberto,
      t.status as titulo_status,
      df.pagamento_import_json
    from f.titulo_parcela tp
    join f.titulo t
      on t.id = tp.titulo_id
     and t.tenant_id = p_tenant_id
     and t.empresa_id = any(p_empresa_ids)
     and t.deleted_at is null
    left join f.documento_fiscal df
      on df.id = t.documento_fiscal_id
     and df.tenant_id = t.tenant_id
     and df.empresa_id = t.empresa_id
     and df.deleted_at is null
    left join public.fornecedores forn
      on forn.id = t.fornecedor_id
     and forn.tenant_id = t.tenant_id
     and forn.empresa_id = t.empresa_id
    left join public.clientes cli
      on cli.id = t.cliente_id
     and cli.tenant_id = t.tenant_id
     and cli.empresa_id = t.empresa_id
    left join lateral (
      select ta.motivo_compra_id, ta.aprovado_por, ta.os_id
      from f.titulo_aprovacao ta
      where ta.tenant_id = t.tenant_id
        and ta.titulo_id = t.id
        and ta.deleted_at is null
      order by ta.aprovado_em desc, ta.created_at desc
      limit 1
    ) aprovacao on true
    left join f.motivo_compra mc
      on mc.id = coalesce(aprovacao.motivo_compra_id, t.motivo_compra_id)
     and mc.tenant_id = t.tenant_id
     and mc.deleted_at is null
    left join a.usuario aprovador
      on aprovador.id = aprovacao.aprovado_por
     and aprovador.deleted_at is null
    left join lateral (
      select tr.os_id
      from f.titulo_rateio tr
      where tr.tenant_id = t.tenant_id
        and tr.titulo_id = t.id
        and tr.os_id is not null
        and tr.deleted_at is null
      order by tr.created_at desc
      limit 1
    ) rateio_os on true
    where tp.tenant_id = p_tenant_id
      and tp.deleted_at is null
      and t.tipo in ('AP', 'AR')
      and case p_data_base
        when 'emissao' then coalesce(t.emissao_date, tp.vencimento_date)
        when 'competencia' then coalesce(t.competencia_date, t.emissao_date, tp.vencimento_date)
        else tp.vencimento_date
      end between p_data_inicio and p_data_fim
  )
  select
    base.empresa_id,
    base.tipo,
    base.nf_numero,
    base.titulo_id,
    base.parcela_id,
    base.parcela_numero,
    base.total_parcelas,
    base.emissao_date,
    base.competencia_date,
    base.vencimento_date,
    base.data_base,
    base.pessoa_nome,
    base.descricao,
    base.motivo_codigo,
    base.motivo_nome,
    base.aprovado_por_nome,
    base.os_id,
    os.numero_os::text as os_numero,
    base.valor,
    base.valor_aberto,
    base.titulo_status,
    coalesce(aplicadas.formas, '{}'::text[]) as formas_aplicadas,
    coalesce(agendadas.formas, '{}'::text[]) as formas_agendadas,
    coalesce(aplicadas.contas, '{}'::text[]) as contas_aplicadas,
    coalesce(agendadas.contas, '{}'::text[]) as contas_agendadas,
    base.pagamento_import_json
  from parcelas base
  left join public.ordens_servico os
    on os.id = base.os_id
   and os.tenant_id = p_tenant_id
   and os.empresa_id = base.empresa_id
  left join lateral (
    select
      array_agg(distinct p.forma_pagamento order by p.forma_pagamento) as formas,
      array_agg(
        distinct concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
        order by concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
      ) as contas
    from f.pagamento_item pi
    join f.pagamento p
      on p.id = pi.pagamento_id
     and p.tenant_id = p_tenant_id
     and p.empresa_id = base.empresa_id
     and p.deleted_at is null
    join f.conta_bancaria cb
      on cb.id = p.conta_bancaria_id
     and cb.tenant_id = p.tenant_id
     and cb.empresa_id = p.empresa_id
     and cb.deleted_at is null
    where pi.tenant_id = p_tenant_id
      and pi.empresa_id = base.empresa_id
      and pi.titulo_parcela_id = base.parcela_id
      and pi.deleted_at is null
  ) aplicadas on true
  left join lateral (
    select
      array_agg(distinct ta.forma_pagamento order by ta.forma_pagamento) as formas,
      array_agg(
        distinct concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
        order by concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
      ) as contas
    from f.titulo_agendamento ta
    join f.conta_bancaria cb
      on cb.id = ta.conta_bancaria_id
     and cb.tenant_id = p_tenant_id
     and cb.empresa_id = base.empresa_id
     and cb.deleted_at is null
    where ta.tenant_id = p_tenant_id
      and ta.titulo_id = base.titulo_id
      and ta.deleted_at is null
  ) agendadas on true
  order by base.data_base, base.tipo, base.pessoa_nome;
end;
$$;

revoke all on function f.contas_pagar_receber_listar_v4(uuid, uuid[], date, date, text) from public;
revoke all on function f.contas_pagar_receber_listar_v4(uuid, uuid[], date, date, text) from anon;
grant execute on function f.contas_pagar_receber_listar_v4(uuid, uuid[], date, date, text)
  to authenticated, service_role;

comment on function f.contas_pagar_receber_listar_v4(uuid, uuid[], date, date, text) is
  'Lista AP/AR multiempresa por vencimento, emissao ou competencia, incluindo vinculo com OS.';

commit;

notify pgrst, 'reload schema';
