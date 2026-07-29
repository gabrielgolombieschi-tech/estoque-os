-- Etapa 3 da Saude Financeira:
-- disponibiliza uma base somente leitura, auditavel e restrita por tenant/empresa
-- para reconciliar os compromissos antes da classificacao gerencial definitiva.

create or replace function f.preview_classificacao_compromissos(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns table (
  titulo_id uuid,
  status text,
  origem text,
  descricao text,
  fornecedor_id integer,
  fornecedor_nome text,
  emissao_date date,
  competencia_date date,
  primeiro_vencimento date,
  ultimo_vencimento date,
  valor_titulo numeric,
  valor_aberto_titulo numeric,
  valor_parcelas numeric,
  valor_aberto_parcelas numeric,
  quantidade_parcelas bigint,
  total_parcelas_serie integer,
  motivo_codigo text,
  motivo_nome text,
  arrendamento_contrato_id uuid,
  legado_implantacao boolean,
  planos jsonb
)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception 'Tenant e empresa sao obrigatorios.';
  end if;

  if auth.uid() is not null then
    if p_tenant_id is distinct from public.current_tenant_id()
       or p_empresa_id is distinct from public.current_empresa_id()
       or not f.has_finance_access(p_tenant_id, p_empresa_id)
    then
      raise exception 'Sem permissao para auditar compromissos deste escopo.';
    end if;
  elsif coalesce(auth.role(), '') <> 'service_role'
        and session_user not in ('postgres', 'service_role')
  then
    raise exception 'Usuario nao autenticado.';
  end if;

  return query
  with parcelas as (
    select
      tp.titulo_id,
      min(tp.vencimento_date) as primeiro_vencimento,
      max(tp.vencimento_date) as ultimo_vencimento,
      coalesce(sum(tp.valor), 0)::numeric as valor_parcelas,
      coalesce(sum(tp.valor_aberto), 0)::numeric as valor_aberto_parcelas,
      count(*)::bigint as quantidade_parcelas
    from f.titulo_parcela tp
    join f.titulo t_scope
      on t_scope.id = tp.titulo_id
     and t_scope.tenant_id = p_tenant_id
     and t_scope.empresa_id = p_empresa_id
     and t_scope.deleted_at is null
    where tp.tenant_id = p_tenant_id
      and tp.deleted_at is null
    group by tp.titulo_id
  ),
  rateios as (
    select
      tr.titulo_id,
      jsonb_agg(
        distinct jsonb_build_object(
          'id', pc.id,
          'codigo', pc.codigo,
          'nome', pc.nome,
          'investimento',
            exists (
              select 1
              from r.dre_plano_excluido dpe
              where dpe.tenant_id = p_tenant_id
                and dpe.plano_contas_id = pc.id
            )
        )
      ) filter (where pc.id is not null) as planos
    from f.titulo_rateio tr
    join f.titulo t_scope
      on t_scope.id = tr.titulo_id
     and t_scope.tenant_id = p_tenant_id
     and t_scope.empresa_id = p_empresa_id
     and t_scope.deleted_at is null
    left join f.plano_contas pc
      on pc.id = tr.plano_contas_id
     and pc.tenant_id = p_tenant_id
     and pc.deleted_at is null
    where tr.tenant_id = p_tenant_id
      and tr.deleted_at is null
    group by tr.titulo_id
  )
  select
    t.id,
    t.status,
    t.origem,
    t.descricao,
    t.fornecedor_id,
    forn.nome::text,
    t.emissao_date,
    t.competencia_date,
    p.primeiro_vencimento,
    p.ultimo_vencimento,
    t.valor_total,
    t.valor_aberto,
    coalesce(p.valor_parcelas, 0),
    coalesce(p.valor_aberto_parcelas, 0),
    coalesce(p.quantidade_parcelas, 0),
    t.total_parcelas_serie,
    coalesce(mc.codigo, 'NAO_CLASSIFICADO'),
    coalesce(mc.nome, 'Nao classificado'),
    t.arrendamento_contrato_id,
    exists (
      select 1
      from f.titulo_legado_implantacao li
      where li.tenant_id = p_tenant_id
        and li.empresa_id = p_empresa_id
        and li.titulo_id = t.id
        and li.desmarcado_em is null
    ),
    coalesce(r.planos, '[]'::jsonb)
  from f.titulo t
  left join f.titulo_aprovacao ta
    on ta.tenant_id = p_tenant_id
   and ta.titulo_id = t.id
   and ta.deleted_at is null
  left join f.motivo_compra mc
    on mc.tenant_id = p_tenant_id
   and mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
   and mc.deleted_at is null
  left join public.fornecedores forn
    on forn.id = t.fornecedor_id
   and forn.tenant_id = p_tenant_id
   and forn.empresa_id = p_empresa_id
  left join parcelas p on p.titulo_id = t.id
  left join rateios r on r.titulo_id = t.id
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.tipo = 'AP'
    and t.deleted_at is null
    and t.status <> 'CANCELADO'
  order by
    coalesce(p.primeiro_vencimento, t.competencia_date, t.emissao_date),
    t.id;
end;
$$;

comment on function f.preview_classificacao_compromissos(uuid, uuid) is
  'Base somente leitura para reconciliar e classificar compromissos AP, limitada obrigatoriamente a tenant e empresa.';

revoke all on function f.preview_classificacao_compromissos(uuid, uuid) from public;
grant execute on function f.preview_classificacao_compromissos(uuid, uuid)
  to authenticated, service_role;
