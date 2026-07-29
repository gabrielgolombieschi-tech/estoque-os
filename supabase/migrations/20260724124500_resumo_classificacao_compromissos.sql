-- Expõe a composicao mutuamente exclusiva dos compromissos para o relatorio
-- Saude Financeira. A funcao usa o saldo vivo das parcelas; os snapshots do
-- lote permanecem imutaveis para auditoria.

create or replace function f.resumo_classificacao_compromissos(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_referencia date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_resultado jsonb;
begin
  if p_tenant_id is null
     or p_empresa_id is null
     or p_data_referencia is null
  then
    raise exception 'Tenant, empresa e data de referencia sao obrigatorios.';
  end if;

  if auth.uid() is not null then
    if p_tenant_id is distinct from public.current_tenant_id()
       or p_empresa_id is distinct from public.current_empresa_id()
       or not f.has_finance_access(p_tenant_id, p_empresa_id)
    then
      raise exception 'Sem permissao para consultar compromissos deste escopo.';
    end if;
  elsif coalesce(auth.role(), '') <> 'service_role'
        and session_user not in ('postgres', 'service_role')
  then
    raise exception 'Usuario nao autenticado.';
  end if;

  with
  categorias_def as (
    select *
    from (
      values
        ('DIVIDA_TRIBUTARIA'::text, 'Dívida tributária'::text, 1),
        ('EMPRESTIMO', 'Empréstimos', 2),
        ('MAQUINA', 'Máquinas e ativos produtivos', 3),
        ('VEICULO', 'Veículos', 4),
        ('AJUSTE', 'Ajustes de implantação', 5)
    ) c(codigo, nome, ordem)
  ),
  classificacoes as (
    select
      tc.id,
      tc.titulo_id,
      tc.categoria,
      tc.forma_contratacao,
      tc.confianca,
      tc.lote_id
    from f.titulo_classificacao_compromisso tc
    join f.titulo t
      on t.id = tc.titulo_id
     and t.tenant_id = p_tenant_id
     and t.empresa_id = p_empresa_id
     and t.tipo = 'AP'
     and t.deleted_at is null
     and t.status <> 'CANCELADO'
    where tc.tenant_id = p_tenant_id
      and tc.empresa_id = p_empresa_id
      and tc.deleted_at is null
  ),
  parcelas_classificadas as (
    select
      c.titulo_id,
      c.categoria,
      c.forma_contratacao,
      c.confianca,
      tp.id as parcela_id,
      tp.vencimento_date,
      tp.valor_aberto
    from classificacoes c
    join f.titulo_parcela tp
      on tp.tenant_id = p_tenant_id
     and tp.titulo_id = c.titulo_id
     and tp.deleted_at is null
     and tp.valor_aberto > 0
  ),
  posicao_categoria as (
    select
      d.codigo,
      d.nome,
      d.ordem,
      count(distinct pc.titulo_id)::integer as quantidade,
      round(coalesce(sum(pc.valor_aberto), 0), 2) as valor_aberto,
      round(coalesce(sum(pc.valor_aberto) filter (
        where pc.vencimento_date < p_data_referencia
      ), 0), 2) as vencido,
      round(coalesce(sum(pc.valor_aberto) filter (
        where pc.vencimento_date between
          p_data_referencia and p_data_referencia + 30
      ), 0), 2) as proximos_30
    from categorias_def d
    left join parcelas_classificadas pc
      on pc.categoria = d.codigo
    group by d.codigo, d.nome, d.ordem
  ),
  totais as (
    select
      round(coalesce(sum(pc.valor_aberto), 0), 2)
        as total_classificado,
      round(coalesce(sum(pc.valor_aberto) filter (
        where pc.categoria <> 'AJUSTE'
      ), 0), 2) as total_financeiro,
      round(coalesce(sum(pc.valor_aberto) filter (
        where pc.categoria in ('DIVIDA_TRIBUTARIA', 'EMPRESTIMO')
      ), 0), 2) as divida,
      round(coalesce(sum(pc.valor_aberto) filter (
        where pc.categoria in ('MAQUINA', 'VEICULO')
      ), 0), 2) as investimento,
      round(coalesce(sum(pc.valor_aberto) filter (
        where pc.categoria = 'AJUSTE'
      ), 0), 2) as ajustes,
      count(distinct pc.titulo_id) filter (
        where pc.confianca <> 'ALTA'
      )::integer as quantidade_revisao,
      round(coalesce(sum(pc.valor_aberto) filter (
        where pc.confianca <> 'ALTA'
      ), 0), 2) as valor_revisao
    from parcelas_classificadas pc
  ),
  formas as (
    select
      pc.forma_contratacao as codigo,
      count(distinct pc.titulo_id)::integer as quantidade,
      round(sum(pc.valor_aberto), 2) as valor_aberto
    from parcelas_classificadas pc
    group by pc.forma_contratacao
  ),
  lote as (
    select
      l.codigo,
      l.valor_referencia_informado,
      l.valor_financeiro_aberto_snapshot,
      l.valor_ajustes_aberto_snapshot,
      l.valor_total_aberto_snapshot,
      l.diferenca_referencia_snapshot,
      l.quantidade_titulos,
      l.manifest_md5,
      l.created_at
    from f.compromisso_classificacao_lote l
    where l.tenant_id = p_tenant_id
      and l.empresa_id = p_empresa_id
    order by l.created_at desc, l.id desc
    limit 1
  ),
  ap_operacional as (
    select
      round(coalesce(sum(tp.valor_aberto), 0), 2) as valor_aberto
    from f.titulo t
    join f.titulo_parcela tp
      on tp.tenant_id = p_tenant_id
     and tp.titulo_id = t.id
     and tp.deleted_at is null
     and tp.valor_aberto > 0
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
      and not exists (
        select 1
        from f.titulo_legado_implantacao li
        where li.tenant_id = p_tenant_id
          and li.empresa_id = p_empresa_id
          and li.titulo_id = t.id
          and li.desmarcado_em is null
      )
  ),
  possiveis_sem_classificacao as (
    select
      count(distinct t.id)::integer as quantidade,
      round(coalesce(sum(tp_saldo.valor_aberto), 0), 2) as valor_aberto
    from f.titulo t
    join lateral (
      select coalesce(sum(tp.valor_aberto), 0)::numeric as valor_aberto
      from f.titulo_parcela tp
      where tp.tenant_id = p_tenant_id
        and tp.titulo_id = t.id
        and tp.deleted_at is null
        and tp.valor_aberto > 0
    ) tp_saldo on tp_saldo.valor_aberto > 0
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
      and coalesce(t.descricao, '')
        ~* '(FINANCIAMENTO|CONS[ÓO]RCIO|LEASING|PARCELAMENTO|PRONAMP)'
      and not exists (
        select 1
        from f.titulo_classificacao_compromisso tc
        where tc.tenant_id = p_tenant_id
          and tc.empresa_id = p_empresa_id
          and tc.titulo_id = t.id
          and tc.deleted_at is null
      )
      and not exists (
        select 1
        from f.titulo_legado_implantacao li
        where li.tenant_id = p_tenant_id
          and li.empresa_id = p_empresa_id
          and li.titulo_id = t.id
          and li.desmarcado_em is null
      )
  )
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'referencia', p_data_referencia,
      'atualizadoEm', now(),
      'loteCodigo', l.codigo,
      'loteCriadoEm', l.created_at,
      'manifestMd5', l.manifest_md5
    ),
    'valorReferenciaInformado', l.valor_referencia_informado,
    'totalClassificadoAberto', t.total_classificado,
    'totalFinanceiroAberto', t.total_financeiro,
    'ajustesAberto', t.ajustes,
    'dividaAberta', t.divida,
    'investimentosAbertos', t.investimento,
    'diferencaReferencia',
      round(t.total_financeiro - l.valor_referencia_informado, 2),
    'diferencaConciliacao',
      round(
        t.total_classificado
          - t.divida
          - t.investimento
          - t.ajustes,
        2
      ),
    'apOperacionalAberto', ap.valor_aberto,
    'apOperacionalForaComposicao',
      round(greatest(ap.valor_aberto - t.total_financeiro, 0), 2),
    'snapshot', jsonb_build_object(
      'valorFinanceiroAberto', l.valor_financeiro_aberto_snapshot,
      'valorAjustesAberto', l.valor_ajustes_aberto_snapshot,
      'valorTotalAberto', l.valor_total_aberto_snapshot,
      'diferencaReferencia', l.diferenca_referencia_snapshot,
      'quantidadeTitulos', l.quantidade_titulos
    ),
    'revisao', jsonb_build_object(
      'quantidade', t.quantidade_revisao,
      'valorAberto', t.valor_revisao,
      'possiveisSemClassificacaoQtd', psc.quantidade,
      'possiveisSemClassificacaoValor', psc.valor_aberto
    ),
    'categorias', (
      select jsonb_agg(
        jsonb_build_object(
          'codigo', pc.codigo,
          'nome', pc.nome,
          'quantidade', pc.quantidade,
          'valorAberto', pc.valor_aberto,
          'vencido', pc.vencido,
          'proximos30', pc.proximos_30,
          'percentual', case
            when t.total_classificado = 0 then 0
            else round(pc.valor_aberto / t.total_classificado * 100, 2)
          end
        )
        order by pc.ordem
      )
      from posicao_categoria pc
    ),
    'formas', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'codigo', f.codigo,
          'quantidade', f.quantidade,
          'valorAberto', f.valor_aberto
        )
        order by f.valor_aberto desc, f.codigo
      ), '[]'::jsonb)
      from formas f
    )
  )
  into v_resultado
  from totais t
  cross join lote l
  cross join ap_operacional ap
  cross join possiveis_sem_classificacao psc;

  return coalesce(v_resultado, jsonb_build_object(
    'meta', jsonb_build_object(
      'referencia', p_data_referencia,
      'atualizadoEm', now()
    ),
    'valorReferenciaInformado', 0,
    'totalClassificadoAberto', 0,
    'totalFinanceiroAberto', 0,
    'ajustesAberto', 0,
    'dividaAberta', 0,
    'investimentosAbertos', 0,
    'diferencaReferencia', 0,
    'diferencaConciliacao', 0,
    'apOperacionalAberto', 0,
    'apOperacionalForaComposicao', 0,
    'revisao', jsonb_build_object(
      'quantidade', 0,
      'valorAberto', 0,
      'possiveisSemClassificacaoQtd', 0,
      'possiveisSemClassificacaoValor', 0
    ),
    'categorias', '[]'::jsonb,
    'formas', '[]'::jsonb
  ));
end;
$$;

comment on function f.resumo_classificacao_compromissos(uuid, uuid, date) is
  'Composicao gerencial mutuamente exclusiva dos compromissos AP, com saldos vivos e referencia auditada.';

revoke all on function f.resumo_classificacao_compromissos(uuid, uuid, date)
  from public;
grant execute on function f.resumo_classificacao_compromissos(uuid, uuid, date)
  to authenticated, service_role;
