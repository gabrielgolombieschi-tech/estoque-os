-- Etapa 3 da Saude Financeira:
-- classifica os compromissos em uma categoria gerencial unica, sem alterar
-- titulo, parcela, pagamento, caixa, rateio ou plano de contas.
--
-- O valor de R$ 2.129.657,42 e preservado como referencia historica informada.
-- A fotografia atual e reconciliada separadamente, pois recebeu novos titulos
-- e pagamentos depois daquela referencia.

create table if not exists f.compromisso_classificacao_lote (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  codigo text not null,
  descricao text not null,
  valor_referencia_informado numeric(15,2),
  valor_financeiro_aberto_snapshot numeric(15,2) not null,
  valor_ajustes_aberto_snapshot numeric(15,2) not null,
  valor_total_aberto_snapshot numeric(15,2) not null,
  diferenca_referencia_snapshot numeric(15,2),
  quantidade_titulos integer not null,
  manifest_md5 text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid default a.fn_current_usuario_id(),
  constraint fk_compromisso_classificacao_lote_empresa
    foreign key (empresa_id) references c.empresa(id),
  constraint uq_compromisso_classificacao_lote_codigo
    unique (tenant_id, empresa_id, codigo),
  constraint ck_compromisso_classificacao_lote_valores
    check (
      valor_financeiro_aberto_snapshot >= 0
      and valor_ajustes_aberto_snapshot >= 0
      and valor_total_aberto_snapshot >= 0
      and quantidade_titulos >= 0
    )
);

comment on table f.compromisso_classificacao_lote is
  'Cabecalho auditavel de uma reconciliacao gerencial de compromissos AP.';

create table if not exists f.titulo_classificacao_compromisso (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  titulo_id uuid not null,
  lote_id uuid not null,
  categoria text not null,
  forma_contratacao text not null,
  confianca text not null default 'ALTA',
  justificativa text not null,
  regra_origem text not null,
  status_titulo_snapshot text not null,
  descricao_snapshot text,
  fornecedor_id_snapshot integer,
  motivo_codigo_snapshot text,
  valor_total_snapshot numeric(15,2) not null,
  valor_aberto_titulo_snapshot numeric(15,2) not null,
  valor_aberto_parcelas_snapshot numeric(15,2) not null,
  planos_snapshot jsonb not null default '[]'::jsonb,
  classificado_em timestamptz not null default now(),
  classificado_por uuid default a.fn_current_usuario_id(),
  deleted_at timestamptz,
  deleted_by uuid,
  motivo_reversao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fk_titulo_classificacao_compromisso_titulo
    foreign key (titulo_id) references f.titulo(id),
  constraint fk_titulo_classificacao_compromisso_lote
    foreign key (lote_id) references f.compromisso_classificacao_lote(id),
  constraint fk_titulo_classificacao_compromisso_empresa
    foreign key (empresa_id) references c.empresa(id),
  constraint ck_titulo_classificacao_compromisso_categoria
    check (
      categoria in (
        'DIVIDA_TRIBUTARIA',
        'EMPRESTIMO',
        'MAQUINA',
        'VEICULO',
        'AJUSTE'
      )
    ),
  constraint ck_titulo_classificacao_compromisso_forma
    check (
      forma_contratacao in (
        'PARCELAMENTO_TRIBUTARIO',
        'EMPRESTIMO',
        'FINANCIAMENTO',
        'CONSORCIO',
        'LEASING',
        'AQUISICAO_IMOBILIZADO',
        'AJUSTE_SISTEMA'
      )
    ),
  constraint ck_titulo_classificacao_compromisso_confianca
    check (confianca in ('ALTA', 'MEDIA', 'REVISAR')),
  constraint ck_titulo_classificacao_compromisso_valores
    check (
      valor_total_snapshot >= 0
      and valor_aberto_titulo_snapshot >= 0
      and valor_aberto_parcelas_snapshot >= 0
    ),
  constraint ck_titulo_classificacao_compromisso_reversao
    check (
      (deleted_at is null and motivo_reversao is null)
      or
      (
        deleted_at is not null
        and length(btrim(coalesce(motivo_reversao, ''))) >= 10
      )
    )
);

comment on table f.titulo_classificacao_compromisso is
  'Categoria gerencial unica do compromisso. Nao substitui o rateio contabil nem altera caixa.';

create unique index if not exists uq_titulo_classificacao_compromisso_ativo
  on f.titulo_classificacao_compromisso (
    tenant_id,
    empresa_id,
    titulo_id
  )
  where deleted_at is null;

create index if not exists idx_titulo_classificacao_compromisso_categoria
  on f.titulo_classificacao_compromisso (
    tenant_id,
    empresa_id,
    categoria
  )
  where deleted_at is null;

create or replace function f.trg_titulo_classificacao_compromisso_validar()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_legado boolean;
begin
  if not exists (
    select 1
    from f.titulo t
    where t.id = new.titulo_id
      and t.tenant_id = new.tenant_id
      and t.empresa_id = new.empresa_id
      and t.tipo = 'AP'
      and t.deleted_at is null
      and t.status <> 'CANCELADO'
  ) then
    raise exception
      'Classificacao: titulo AP invalido ou fora do tenant/empresa.';
  end if;

  if not exists (
    select 1
    from f.compromisso_classificacao_lote l
    where l.id = new.lote_id
      and l.tenant_id = new.tenant_id
      and l.empresa_id = new.empresa_id
  ) then
    raise exception
      'Classificacao: lote invalido ou fora do tenant/empresa.';
  end if;

  select exists (
    select 1
    from f.titulo_legado_implantacao li
    where li.tenant_id = new.tenant_id
      and li.empresa_id = new.empresa_id
      and li.titulo_id = new.titulo_id
      and li.desmarcado_em is null
  )
  into v_legado;

  if new.deleted_at is null
     and new.categoria = 'AJUSTE'
     and not v_legado
  then
    raise exception
      'Classificacao: AJUSTE exige marcacao ativa de legado de implantacao.';
  end if;

  if new.deleted_at is null
     and new.categoria <> 'AJUSTE'
     and v_legado
  then
    raise exception
      'Classificacao: titulo legado deve permanecer exclusivamente em AJUSTE.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_titulo_classificacao_compromisso_validar
  on f.titulo_classificacao_compromisso;

create trigger trg_titulo_classificacao_compromisso_validar
before insert or update
on f.titulo_classificacao_compromisso
for each row
execute function f.trg_titulo_classificacao_compromisso_validar();

drop trigger if exists trg_audit_compromisso_classificacao_lote
  on f.compromisso_classificacao_lote;

create trigger trg_audit_compromisso_classificacao_lote
after insert or update or delete
on f.compromisso_classificacao_lote
for each row
execute function public.audit_trigger();

drop trigger if exists trg_audit_titulo_classificacao_compromisso
  on f.titulo_classificacao_compromisso;

create trigger trg_audit_titulo_classificacao_compromisso
after insert or update or delete
on f.titulo_classificacao_compromisso
for each row
execute function public.audit_trigger();

alter table f.compromisso_classificacao_lote enable row level security;
alter table f.titulo_classificacao_compromisso enable row level security;

drop policy if exists compromisso_classificacao_lote_select
  on f.compromisso_classificacao_lote;

create policy compromisso_classificacao_lote_select
  on f.compromisso_classificacao_lote
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access(tenant_id, empresa_id)
  );

drop policy if exists titulo_classificacao_compromisso_select
  on f.titulo_classificacao_compromisso;

create policy titulo_classificacao_compromisso_select
  on f.titulo_classificacao_compromisso
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access(tenant_id, empresa_id)
    and exists (
      select 1
      from f.titulo t_scope
      where t_scope.id = titulo_id
        and t_scope.tenant_id =
          f.titulo_classificacao_compromisso.tenant_id
        and t_scope.empresa_id =
          f.titulo_classificacao_compromisso.empresa_id
    )
  );

revoke all on table f.compromisso_classificacao_lote from public, anon;
revoke all on table f.titulo_classificacao_compromisso from public, anon;
grant select on table f.compromisso_classificacao_lote
  to authenticated, service_role;
grant select on table f.titulo_classificacao_compromisso
  to authenticated, service_role;

do $classificacao$
declare
  v_tenant constant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa constant uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_lote_id constant uuid := '7a53fa77-0a85-4a9b-82f2-98f75e52fd5a';
  v_lote_codigo constant text := 'COMPROMISSOS_SEG_20260724';
  v_referencia constant numeric(15,2) := 2129657.42;
  v_quantidade integer;
  v_valor_total numeric(15,2);
  v_valor_aberto numeric(15,2);
  v_valor_financeiro numeric(15,2);
  v_valor_ajustes numeric(15,2);
  v_hash text;
  v_categoria record;
begin
  perform pg_advisory_xact_lock(
    hashtextextended(
      'CLASSIFICACAO_COMPROMISSOS:'
        || v_tenant::text || ':' || v_empresa::text,
      0
    )
  );

  create temp table _compromissos_base
  on commit drop
  as
  with parcelas as (
    select
      tp.titulo_id,
      coalesce(sum(tp.valor_aberto), 0)::numeric(15,2)
        as valor_aberto_parcelas
    from f.titulo_parcela tp
    join f.titulo t_scope
      on t_scope.id = tp.titulo_id
     and t_scope.tenant_id = v_tenant
     and t_scope.empresa_id = v_empresa
     and t_scope.deleted_at is null
    where tp.tenant_id = v_tenant
      and tp.deleted_at is null
    group by tp.titulo_id
  )
  select
    t.id as titulo_id,
    t.status,
    t.descricao,
    t.fornecedor_id,
    t.valor_total,
    t.valor_aberto as valor_aberto_titulo,
    coalesce(p.valor_aberto_parcelas, 0) as valor_aberto_parcelas,
    coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pc.id,
          'codigo', pc.codigo,
          'nome', pc.nome
        )
        order by pc.codigo, pc.id
      )
      from f.titulo_rateio tr
      left join f.plano_contas pc
        on pc.id = tr.plano_contas_id
       and pc.tenant_id = v_tenant
       and pc.deleted_at is null
      where tr.tenant_id = v_tenant
        and tr.titulo_id = t.id
        and tr.deleted_at is null
        and pc.id is not null
    ), '[]'::jsonb) as planos,
    (li.titulo_id is not null) as legado_implantacao
  from f.titulo t
  left join lateral (
    select ta.motivo_compra_id
    from f.titulo_aprovacao ta
    where ta.tenant_id = v_tenant
      and ta.titulo_id = t.id
      and ta.deleted_at is null
    order by ta.aprovado_em desc, ta.id desc
    limit 1
  ) ta_efetiva on true
  left join f.motivo_compra mc
    on mc.id = coalesce(ta_efetiva.motivo_compra_id, t.motivo_compra_id)
   and mc.tenant_id = v_tenant
   and mc.deleted_at is null
  left join parcelas p on p.titulo_id = t.id
  left join f.titulo_legado_implantacao li
    on li.tenant_id = v_tenant
   and li.empresa_id = v_empresa
   and li.titulo_id = t.id
   and li.desmarcado_em is null
  where t.tenant_id = v_tenant
    and t.empresa_id = v_empresa
    and t.tipo = 'AP'
    and t.deleted_at is null
    and t.status <> 'CANCELADO';

  create temp table _compromissos_manifesto
  on commit drop
  as
  select
    b.*,
    case
      when b.legado_implantacao then 'AJUSTE'
      when
        upper(btrim(coalesce(b.descricao, ''))) like 'PARCELAMENTO ICMS%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'PARCELAMENTO DO ICMS%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'PARCELAMENTO PIS/COFINS%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'PARCELAMENTO PIS COFINS%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'PARCELAMENTO INSS%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'PARCELAMENTO SIMPLES NACIONAL%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'PARCELAMENTO DARF%'
        then 'DIVIDA_TRIBUTARIA'
      when
        b.motivo_codigo = 'FINANCIAMENTO_RURAL'
        or upper(btrim(coalesce(b.descricao, ''))) like 'PRONAMP%'
        then 'EMPRESTIMO'
      when
        (
          b.fornecedor_id in (329, 613)
          and upper(coalesce(b.descricao, '')) like '%LEASING%'
        )
        or b.motivo_codigo = 'IMOB_AQUISICAO'
        then 'MAQUINA'
      when
        upper(btrim(coalesce(b.descricao, ''))) like 'FINANCIAMENTO VEÍCULO%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'FINANCIAMENTO VEICULO%'
        or upper(btrim(coalesce(b.descricao, ''))) = 'FINANCIAMENTO CAMINHAO'
        or (
          b.fornecedor_id = 414
          and upper(btrim(coalesce(b.descricao, ''))) = 'PARCELA CAMINHÃO'
        )
        or upper(btrim(coalesce(b.descricao, ''))) like 'FINANCIAMENTO CARRO%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'CONSÓRCIO - CHEVROLET ONIX%'
        or upper(btrim(coalesce(b.descricao, ''))) like 'CONSORCIO - CHEVROLET ONIX%'
        or (
          b.fornecedor_id = 440
          and upper(btrim(coalesce(b.descricao, ''))) = 'FINANCIAMENTO'
        )
        then 'VEICULO'
      else null
    end::text as categoria
  from _compromissos_base b;

  delete from _compromissos_manifesto where categoria is null;

  select
    count(*)::integer,
    round(coalesce(sum(valor_total), 0), 2),
    round(coalesce(sum(valor_aberto_parcelas), 0), 2),
    md5(string_agg(titulo_id::text, ',' order by titulo_id::text))
  into
    v_quantidade,
    v_valor_total,
    v_valor_aberto,
    v_hash
  from _compromissos_manifesto;

  if v_quantidade <> 637
     or v_valor_total <> 2816479.54
     or v_valor_aberto <> 2448596.82
     or v_hash <> 'c2c6a24ed05458480f03e7508a5c5bb6'
  then
    raise exception
      'Classificacao abortada: manifesto geral divergiu (qtd %, total %, aberto %, hash %).',
      v_quantidade, v_valor_total, v_valor_aberto, v_hash;
  end if;

  for v_categoria in
    select *
    from (
      values
        (
          'DIVIDA_TRIBUTARIA'::text,
          238::integer,
          909783.22::numeric,
          751922.85::numeric,
          '0cf6ed897c887a4442c4ff0cfb6706db'::text
        ),
        (
          'EMPRESTIMO',
          2,
          14924.18,
          7462.09,
          '4710b7e9bde03dfab3b62f1fc61397d7'
        ),
        (
          'MAQUINA',
          100,
          858266.74,
          741992.74,
          '1a353aad8c021f433b0f0a59a365e71f'
        ),
        (
          'VEICULO',
          231,
          852271.03,
          765984.77,
          '8f889affdfd96f1e0dc22b875ac0633d'
        ),
        (
          'AJUSTE',
          66,
          181234.37,
          181234.37,
          '0d9dab87f9979321ab4a5ab8d6274f5b'
        )
    ) expected(categoria, quantidade, valor_total, valor_aberto, manifest_md5)
  loop
    select
      count(*)::integer,
      round(coalesce(sum(m.valor_total), 0), 2),
      round(coalesce(sum(m.valor_aberto_parcelas), 0), 2),
      md5(string_agg(m.titulo_id::text, ',' order by m.titulo_id::text))
    into
      v_quantidade,
      v_valor_total,
      v_valor_aberto,
      v_hash
    from _compromissos_manifesto m
    where m.categoria = v_categoria.categoria;

    if v_quantidade <> v_categoria.quantidade
       or v_valor_total <> v_categoria.valor_total
       or v_valor_aberto <> v_categoria.valor_aberto
       or v_hash <> v_categoria.manifest_md5
    then
      raise exception
        'Classificacao abortada: categoria % divergiu (qtd %, total %, aberto %, hash %).',
        v_categoria.categoria,
        v_quantidade,
        v_valor_total,
        v_valor_aberto,
        v_hash;
    end if;
  end loop;

  perform 1
  from f.titulo t_lock
  join _compromissos_manifesto m on m.titulo_id = t_lock.id
  order by t_lock.id
  for update;

  select
    round(coalesce(
      sum(valor_aberto_parcelas) filter (where categoria <> 'AJUSTE'),
      0
    ), 2),
    round(coalesce(
      sum(valor_aberto_parcelas) filter (where categoria = 'AJUSTE'),
      0
    ), 2)
  into v_valor_financeiro, v_valor_ajustes
  from _compromissos_manifesto;

  insert into f.compromisso_classificacao_lote (
    id,
    tenant_id,
    empresa_id,
    codigo,
    descricao,
    valor_referencia_informado,
    valor_financeiro_aberto_snapshot,
    valor_ajustes_aberto_snapshot,
    valor_total_aberto_snapshot,
    diferenca_referencia_snapshot,
    quantidade_titulos,
    manifest_md5,
    metadata
  )
  values (
    v_lote_id,
    v_tenant,
    v_empresa,
    v_lote_codigo,
    'Reclassificacao dos compromissos financeiros e ajustes de implantacao.',
    v_referencia,
    v_valor_financeiro,
    v_valor_ajustes,
    v_valor_financeiro + v_valor_ajustes,
    v_valor_financeiro - v_referencia,
    637,
    'c2c6a24ed05458480f03e7508a5c5bb6',
    jsonb_build_object(
      'migration', '20260724123000',
      'alteraTitulo', false,
      'alteraParcela', false,
      'alteraPagamento', false,
      'alteraCaixa', false,
      'alteraRateio', false,
      'valorReferenciaNatureza', 'fotografia_historica_informada',
      'reconciliacaoReferencia', jsonb_build_object(
        'baseAbertaRegraOriginalAtual', 2231834.11,
        'menosSerieDiogoCriadaEm20260724', 117626.90,
        'maisGrenkeLegadoVisivelAntesEtapa1', 10706.16,
        'grenkeLegadoTituloId',
          '95bde27d-38c4-4d8b-abf7-0f287f7f58a3',
        'maisVeiculosPagosEm20260724', 4744.05,
        'virtusTituloPagoId',
          '56c1d3a7-7b6a-4f17-bc04-7ba2b512b014',
        'poloTituloPagoId',
          '6bedd0b7-7f29-48b1-996a-12412085adb7',
        'valorReconciliado', 2129657.42
      ),
      'categorias', jsonb_build_object(
        'DIVIDA_TRIBUTARIA', jsonb_build_object(
          'quantidade', 238,
          'valorAberto', 751922.85
        ),
        'EMPRESTIMO', jsonb_build_object(
          'quantidade', 2,
          'valorAberto', 7462.09
        ),
        'MAQUINA', jsonb_build_object(
          'quantidade', 100,
          'valorAberto', 741992.74
        ),
        'VEICULO', jsonb_build_object(
          'quantidade', 231,
          'valorAberto', 765984.77
        ),
        'AJUSTE', jsonb_build_object(
          'quantidade', 66,
          'valorAberto', 181234.37
        )
      )
    )
  )
  on conflict (tenant_id, empresa_id, codigo) do nothing;

  if not exists (
    select 1
    from f.compromisso_classificacao_lote l
    where l.id = v_lote_id
      and l.tenant_id = v_tenant
      and l.empresa_id = v_empresa
      and l.codigo = v_lote_codigo
      and l.quantidade_titulos = 637
      and l.manifest_md5 = 'c2c6a24ed05458480f03e7508a5c5bb6'
  ) then
    raise exception 'Classificacao abortada: lote existente nao confere.';
  end if;

  with inseridos as (
    insert into f.titulo_classificacao_compromisso (
      tenant_id,
      empresa_id,
      titulo_id,
      lote_id,
      categoria,
      forma_contratacao,
      confianca,
      justificativa,
      regra_origem,
      status_titulo_snapshot,
      descricao_snapshot,
      fornecedor_id_snapshot,
      motivo_codigo_snapshot,
      valor_total_snapshot,
      valor_aberto_titulo_snapshot,
      valor_aberto_parcelas_snapshot,
      planos_snapshot
    )
    select
      v_tenant,
      v_empresa,
      m.titulo_id,
      v_lote_id,
      m.categoria,
      case
        when m.categoria = 'AJUSTE' then 'AJUSTE_SISTEMA'
        when m.categoria = 'DIVIDA_TRIBUTARIA'
          then 'PARCELAMENTO_TRIBUTARIO'
        when m.categoria = 'EMPRESTIMO' then 'EMPRESTIMO'
        when m.categoria = 'MAQUINA'
             and m.motivo_codigo = 'IMOB_AQUISICAO'
          then 'AQUISICAO_IMOBILIZADO'
        when m.categoria = 'MAQUINA' then 'LEASING'
        when m.categoria = 'VEICULO'
             and (
               upper(coalesce(m.descricao, '')) like 'CONSÓRCIO%'
               or upper(coalesce(m.descricao, '')) like 'CONSORCIO%'
             )
          then 'CONSORCIO'
        else 'FINANCIAMENTO'
      end,
      case
        when m.categoria = 'MAQUINA'
             and m.fornecedor_id = 329
             and upper(btrim(coalesce(m.descricao, ''))) = 'LEASING'
          then 'MEDIA'
        else 'ALTA'
      end,
      case
        when m.categoria = 'AJUSTE'
          then 'Saldo anterior ao corte de confiabilidade, validado como ajuste de implantacao.'
        when m.categoria = 'DIVIDA_TRIBUTARIA'
          then 'Serie identificada como parcelamento de tributo.'
        when m.categoria = 'EMPRESTIMO'
          then 'Operacao PRONAMP identificada como emprestimo.'
        when m.categoria = 'MAQUINA'
             and m.fornecedor_id = 329
             and upper(btrim(coalesce(m.descricao, ''))) = 'LEASING'
          then 'Leasing Santander classificado como maquina pela decisao gerencial; confirmar o ativo especifico.'
        when m.categoria = 'MAQUINA'
             and m.motivo_codigo = 'IMOB_AQUISICAO'
          then 'Aquisicao registrada como imobilizado; agrupada em maquinas e ativos produtivos.'
        when m.categoria = 'MAQUINA'
          then 'Leasing com ativo produtivo identificado no titulo.'
        when m.categoria = 'VEICULO'
          then 'Financiamento ou consorcio com veiculo identificado no titulo ou no fornecedor.'
        else 'Classificacao gerencial revisada.'
      end,
      case
        when m.categoria = 'AJUSTE' then 'LEGADO_IMPLANTACAO_ATIVO'
        when m.categoria = 'DIVIDA_TRIBUTARIA'
          then 'SERIE_PARCELAMENTO_TRIBUTARIO'
        when m.categoria = 'EMPRESTIMO'
          then 'MOTIVO_OU_SERIE_PRONAMP'
        when m.categoria = 'MAQUINA'
             and m.motivo_codigo = 'IMOB_AQUISICAO'
          then 'MOTIVO_IMOB_AQUISICAO'
        when m.categoria = 'MAQUINA'
          then 'FORNECEDOR_LEASING_ATIVO_PRODUTIVO'
        when m.categoria = 'VEICULO'
          then 'SERIE_OU_FORNECEDOR_VEICULO'
        else 'REVISAO_GERENCIAL'
      end,
      m.status,
      m.descricao,
      m.fornecedor_id,
      m.motivo_codigo,
      m.valor_total,
      m.valor_aberto_titulo,
      m.valor_aberto_parcelas,
      m.planos
    from _compromissos_manifesto m
    where not exists (
      select 1
      from f.titulo_classificacao_compromisso tc_existente
      where tc_existente.tenant_id = v_tenant
        and tc_existente.empresa_id = v_empresa
        and tc_existente.titulo_id = m.titulo_id
        and tc_existente.deleted_at is null
    )
    returning *
  )
  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload
  )
  select
    i.tenant_id,
    i.empresa_id,
    'TITULO_AP_COMPROMISSO_CLASSIFICADO',
    'f.titulo',
    i.titulo_id,
    jsonb_build_object(
      'classificacaoId', i.id,
      'loteId', i.lote_id,
      'lote', v_lote_codigo,
      'categoria', i.categoria,
      'formaContratacao', i.forma_contratacao,
      'confianca', i.confianca,
      'justificativa', i.justificativa,
      'valorTotalSnapshot', i.valor_total_snapshot,
      'valorAbertoSnapshot', i.valor_aberto_parcelas_snapshot,
      'alterouTitulo', false,
      'alterouParcela', false,
      'alterouPagamento', false,
      'alterouCaixa', false,
      'alterouRateio', false
    )
  from inseridos i;

  select
    count(*)::integer,
    round(coalesce(sum(tc.valor_aberto_parcelas_snapshot), 0), 2),
    md5(string_agg(tc.titulo_id::text, ',' order by tc.titulo_id::text))
  into v_quantidade, v_valor_aberto, v_hash
  from f.titulo_classificacao_compromisso tc
  where tc.tenant_id = v_tenant
    and tc.empresa_id = v_empresa
    and tc.lote_id = v_lote_id
    and tc.deleted_at is null;

  if v_quantidade <> 637
     or v_valor_aberto <> 2448596.82
     or v_hash <> 'c2c6a24ed05458480f03e7508a5c5bb6'
  then
    raise exception
      'Classificacao abortada: pos-condicao divergiu (qtd %, aberto %, hash %).',
      v_quantidade, v_valor_aberto, v_hash;
  end if;
end;
$classificacao$;
