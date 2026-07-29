-- Materializa, titulo a titulo, a composicao da fotografia historica de
-- R$ 2.129.657,42. A posicao atual continua sendo calculada pelo saldo vivo.

alter table f.titulo_classificacao_compromisso
  add column if not exists valor_referencia_historica numeric(15,2);

alter table f.titulo_classificacao_compromisso
  add column if not exists regra_referencia_historica text;

do $constraint$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname =
      'ck_titulo_classificacao_compromisso_referencia_historica'
      and conrelid = 'f.titulo_classificacao_compromisso'::regclass
  ) then
    alter table f.titulo_classificacao_compromisso
      add constraint
        ck_titulo_classificacao_compromisso_referencia_historica
      check (
        (
          valor_referencia_historica is null
          and regra_referencia_historica is null
        )
        or
        (
          valor_referencia_historica > 0
          and length(btrim(coalesce(regra_referencia_historica, ''))) >= 10
        )
      );
  end if;
end;
$constraint$;

comment on column
  f.titulo_classificacao_compromisso.valor_referencia_historica is
  'Valor do titulo que compunha a fotografia reconciliada de R$ 2.129.657,42.';

comment on column
  f.titulo_classificacao_compromisso.regra_referencia_historica is
  'Regra auditavel de inclusao do titulo na fotografia historica.';

create index if not exists
  idx_titulo_classificacao_compromisso_referencia_historica
  on f.titulo_classificacao_compromisso (
    tenant_id,
    empresa_id,
    categoria
  )
  where deleted_at is null
    and valor_referencia_historica is not null;

do $referencia$
declare
  v_tenant constant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa constant uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_lote_id constant uuid := '7a53fa77-0a85-4a9b-82f2-98f75e52fd5a';
  v_grenke_legado constant uuid :=
    'e3c7421e-51d2-45e0-90d5-f53628f88f10';
  v_virtus_pago constant uuid :=
    '56c1d3a7-7b6a-4f17-bc04-7ba2b512b014';
  v_polo_pago constant uuid :=
    '6bedd0b7-7f29-48b1-996a-12412085adb7';
  v_quantidade integer;
  v_valor numeric(15,2);
  v_hash text;
  v_rows_hash text;
  v_categoria record;
begin
  perform pg_advisory_xact_lock(
    hashtextextended(
      'CLASSIFICACAO_COMPROMISSOS_REFERENCIA:'
        || v_tenant::text || ':' || v_empresa::text,
      0
    )
  );

  update f.titulo_classificacao_compromisso tc
  set
    valor_referencia_historica = case
      when tc.titulo_id in (v_virtus_pago, v_polo_pago)
        then tc.valor_total_snapshot
      else tc.valor_aberto_parcelas_snapshot
    end,
    regra_referencia_historica = case
      when tc.categoria = 'DIVIDA_TRIBUTARIA'
        then 'SALDO_ABERTO_PARCELAMENTO_TRIBUTARIO_NA_REFERENCIA'
      when tc.categoria = 'MAQUINA'
        then 'SALDO_ABERTO_LEASING_MAQUINA_NA_REFERENCIA'
      when tc.categoria = 'VEICULO'
           and tc.titulo_id in (v_virtus_pago, v_polo_pago)
        then 'PARCELA_VEICULO_PAGA_APOS_A_REFERENCIA'
      when tc.categoria = 'VEICULO'
        then 'SALDO_ABERTO_VEICULO_NA_REFERENCIA'
      when tc.categoria = 'AJUSTE'
        then 'GRENKE_LEGADO_VISIVEL_ANTES_DO_CORTE_DE_IMPLANTACAO'
    end
  where tc.tenant_id = v_tenant
    and tc.empresa_id = v_empresa
    and tc.lote_id = v_lote_id
    and tc.deleted_at is null
    and tc.valor_referencia_historica is null
    and (
      (
        tc.categoria = 'DIVIDA_TRIBUTARIA'
        and tc.valor_aberto_parcelas_snapshot > 0
      )
      or
      (
        tc.categoria = 'MAQUINA'
        and tc.forma_contratacao = 'LEASING'
        and tc.valor_aberto_parcelas_snapshot > 0
      )
      or
      (
        tc.categoria = 'VEICULO'
        and (
          (
            tc.valor_aberto_parcelas_snapshot > 0
            and upper(btrim(coalesce(tc.descricao_snapshot, '')))
              not like 'FINANCIAMENTO CARRO DIOGO%'
          )
          or tc.titulo_id in (v_virtus_pago, v_polo_pago)
        )
      )
      or
      (
        tc.categoria = 'AJUSTE'
        and tc.titulo_id = v_grenke_legado
      )
    );

  select
    count(*)::integer,
    round(coalesce(sum(tc.valor_referencia_historica), 0), 2),
    md5(string_agg(tc.titulo_id::text, ',' order by tc.titulo_id::text)),
    md5(string_agg(
      tc.titulo_id::text
        || ':' || tc.categoria
        || ':' || to_char(
          tc.valor_referencia_historica,
          'FM999999999999990.00'
        ),
      ','
      order by tc.titulo_id::text
    ))
  into v_quantidade, v_valor, v_hash, v_rows_hash
  from f.titulo_classificacao_compromisso tc
  where tc.tenant_id = v_tenant
    and tc.empresa_id = v_empresa
    and tc.lote_id = v_lote_id
    and tc.deleted_at is null
    and tc.valor_referencia_historica is not null;

  if v_quantidade <> 450
     or v_valor <> 2129657.42
     or v_hash <> '817f21ce11b5491b2c5c5d51a61a8017'
     or v_rows_hash <> 'e145625bc88a7d15546eabf5e4adadeb'
  then
    raise exception
      'Referencia historica divergiu (qtd %, valor %, hash %, rows %).',
      v_quantidade, v_valor, v_hash, v_rows_hash;
  end if;

  for v_categoria in
    select *
    from (
      values
        (
          'DIVIDA_TRIBUTARIA'::text,
          217::integer,
          751922.85::numeric,
          '6766ade2205d2cc9b78d1206b0df9217'::text,
          '5bb89fbc5a3810ca0c80bf37ce1a9ed1'::text
        ),
        (
          'EMPRESTIMO',
          0,
          0,
          null::text,
          null::text
        ),
        (
          'MAQUINA',
          68,
          713926.49,
          'e5c75dd987c8264caac9ac98d8cfed7e',
          '6cc5e7dc4b7d1a4f098ef199bf676d7f'
        ),
        (
          'VEICULO',
          164,
          653101.92,
          '9edf536c955875e1dcaf8e27b5001d7a',
          '0d2705f6daea87920d0b7224907cefb1'
        ),
        (
          'AJUSTE',
          1,
          10706.16,
          '8cf80c3b9cf24c4d085a4cb404fc81ce',
          'a76129d15064b22c3f3b4b9cf9095229'
        )
    ) expected(
      categoria,
      quantidade,
      valor,
      manifest_md5,
      rows_md5
    )
  loop
    select
      count(*)::integer,
      round(coalesce(sum(tc.valor_referencia_historica), 0), 2),
      md5(string_agg(tc.titulo_id::text, ',' order by tc.titulo_id::text)),
      md5(string_agg(
        tc.titulo_id::text
          || ':' || tc.categoria
          || ':' || to_char(
            tc.valor_referencia_historica,
            'FM999999999999990.00'
          ),
        ','
        order by tc.titulo_id::text
      ))
    into v_quantidade, v_valor, v_hash, v_rows_hash
    from f.titulo_classificacao_compromisso tc
    where tc.tenant_id = v_tenant
      and tc.empresa_id = v_empresa
      and tc.lote_id = v_lote_id
      and tc.deleted_at is null
      and tc.valor_referencia_historica is not null
      and tc.categoria = v_categoria.categoria;

    if v_quantidade <> v_categoria.quantidade
       or v_valor <> v_categoria.valor
       or v_hash is distinct from v_categoria.manifest_md5
       or v_rows_hash is distinct from v_categoria.rows_md5
    then
      raise exception
        'Referencia historica da categoria % divergiu (qtd %, valor %, hash %, rows %).',
        v_categoria.categoria,
        v_quantidade,
        v_valor,
        v_hash,
        v_rows_hash;
    end if;
  end loop;

  update f.compromisso_classificacao_lote l
  set metadata = jsonb_set(
    l.metadata,
    '{composicaoReferenciaHistorica}',
    jsonb_build_object(
      'quantidadeTitulos', 450,
      'valorTotal', 2129657.42,
      'manifestMd5', '817f21ce11b5491b2c5c5d51a61a8017'
    ),
    true
  )
  where l.id = v_lote_id
    and l.tenant_id = v_tenant
    and l.empresa_id = v_empresa;

  if not found then
    raise exception 'Lote da referencia historica nao encontrado.';
  end if;
end;
$referencia$;

create or replace function
  f.resumo_classificacao_compromissos_referencia(
    p_tenant_id uuid,
    p_empresa_id uuid
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
  if p_tenant_id is null or p_empresa_id is null then
    raise exception 'Tenant e empresa sao obrigatorios.';
  end if;

  if auth.uid() is not null then
    if p_tenant_id is distinct from public.current_tenant_id()
       or p_empresa_id is distinct from public.current_empresa_id()
       or not f.has_finance_access(p_tenant_id, p_empresa_id)
    then
      raise exception 'Sem permissao para consultar este escopo.';
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
  lote as (
    select l.id, l.codigo, l.valor_referencia_informado
    from f.compromisso_classificacao_lote l
    where l.tenant_id = p_tenant_id
      and l.empresa_id = p_empresa_id
    order by l.created_at desc, l.id desc
    limit 1
  ),
  composicao as (
    select
      d.codigo,
      d.nome,
      d.ordem,
      count(tc.id)::integer as quantidade,
      round(coalesce(sum(tc.valor_referencia_historica), 0), 2)
        as valor
    from categorias_def d
    cross join lote l
    left join f.titulo_classificacao_compromisso tc
      on tc.tenant_id = p_tenant_id
     and tc.empresa_id = p_empresa_id
     and tc.lote_id = l.id
     and tc.categoria = d.codigo
     and tc.deleted_at is null
     and tc.valor_referencia_historica is not null
    group by d.codigo, d.nome, d.ordem
  )
  select jsonb_build_object(
    'loteCodigo', l.codigo,
    'valorReferencia', l.valor_referencia_informado,
    'quantidadeTitulos', sum(c.quantidade),
    'valorReconciliado', round(sum(c.valor), 2),
    'diferencaConciliacao',
      round(sum(c.valor) - l.valor_referencia_informado, 2),
    'categorias', jsonb_agg(
      jsonb_build_object(
        'codigo', c.codigo,
        'nome', c.nome,
        'quantidade', c.quantidade,
        'valor', c.valor,
        'percentual', case
          when l.valor_referencia_informado = 0 then 0
          else round(c.valor / l.valor_referencia_informado * 100, 2)
        end
      )
      order by c.ordem
    )
  )
  into v_resultado
  from lote l
  cross join composicao c
  group by l.codigo, l.valor_referencia_informado;

  return coalesce(
    v_resultado,
    jsonb_build_object(
      'valorReferencia', 0,
      'quantidadeTitulos', 0,
      'valorReconciliado', 0,
      'diferencaConciliacao', 0,
      'categorias', '[]'::jsonb
    )
  );
end;
$$;

comment on function
  f.resumo_classificacao_compromissos_referencia(uuid, uuid) is
  'Composicao auditada da fotografia historica de R$ 2.129.657,42.';

revoke all on function
  f.resumo_classificacao_compromissos_referencia(uuid, uuid)
  from public;

grant execute on function
  f.resumo_classificacao_compromissos_referencia(uuid, uuid)
  to authenticated, service_role;
