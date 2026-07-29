-- Saneamento auditavel dos rateios duplicados da empresa Segau.
--
-- Escopo:
--   tenant  3ced7cfa-efbb-4f0f-addc-2028f60d1ca7
--   empresa f0e74f49-a127-46b4-901b-f7b37e43c690
--
-- A migration:
--   * preserva um dos rateios quando as duas linhas sao identicas;
--   * nos tres leasings operacionais, preserva DESP_LEASING e desativa
--     DESP_GERAL;
--   * mantem a NF-e 6654/1 como pendencia contabil, pois o documento e o
--     rateio sao R$ 280,00, mas a cobranca, o titulo e o pagamento sao R$ 80,00;
--   * nao reescreve rateios de titulos cancelados;
--   * nao altera titulo, parcela, pagamento, caixa ou status;
--   * usa soft delete e guarda snapshot completo para reversao auditada.

create table if not exists f.titulo_rateio_saneamento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  lote text not null,
  titulo_id uuid not null,
  rateio_id uuid not null,
  acao text not null,
  motivo text not null,
  dados_anteriores jsonb not null,
  dados_posteriores jsonb,
  executado_at timestamptz not null default now(),
  executado_by uuid default a.fn_current_usuario_id(),
  revertido_at timestamptz,
  revertido_by uuid,
  motivo_reversao text,
  constraint ck_titulo_rateio_saneamento_acao
    check (acao in (
      'SOFT_DELETE_DUPLICADO_EXATO',
      'SOFT_DELETE_PLANO_PADRAO'
    )),
  constraint uq_titulo_rateio_saneamento_lote_rateio
    unique (tenant_id, empresa_id, lote, rateio_id)
);

comment on table f.titulo_rateio_saneamento is
  'Snapshot auditavel e reversivel dos saneamentos efetuados em f.titulo_rateio.';

create index if not exists idx_titulo_rateio_saneamento_escopo_lote
  on f.titulo_rateio_saneamento (tenant_id, empresa_id, lote);

alter table f.titulo_rateio_saneamento enable row level security;

drop policy if exists titulo_rateio_saneamento_select
  on f.titulo_rateio_saneamento;

create policy titulo_rateio_saneamento_select
  on f.titulo_rateio_saneamento
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access()
  );

revoke all on table f.titulo_rateio_saneamento from public;
grant select on table f.titulo_rateio_saneamento to authenticated, service_role;

do $$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_lote constant text := 'SAUDE_FINANCEIRA_RATEIO_20260724';
  v_now timestamptz := clock_timestamp();
  v_count bigint;
  v_hash text;
  v_total_rateios_before bigint;
  v_total_rateios_after bigint;
begin
  -- O Supabase CLI executa migrations com uma conta tecnica sem JWT. O papel
  -- e definido apenas nesta transacao para permitir a RPC de auditoria, cuja
  -- execucao publica permanece revogada.
  perform set_config('request.jwt.claim.role', 'service_role', true);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'SAUDE_FINANCEIRA_RATEIO_20260724:'
      || v_tenant_id::text
      || ':'
      || v_empresa_id::text,
      0
    )
  );

  -- Bloqueia escritas concorrentes em rateios durante a fotografia e o lote.
  lock table f.titulo_rateio in share row exclusive mode;

  create temporary table _rateio_alvos_iniciais
  on commit drop
  as
  select *
  from f.preview_inconsistencias_rateio(v_tenant_id, v_empresa_id)
  where status <> 'CANCELADO'
    and percentual_total > 100.0001;

  -- Os titulos ficam imutaveis enquanto o lote calcula e corrige seus rateios.
  perform 1
  from f.titulo t
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.id in (
      select a.titulo_id
      from _rateio_alvos_iniciais a
    )
  for update;

  create temporary table _rateio_alvos
  on commit drop
  as
  select *
  from f.preview_inconsistencias_rateio(v_tenant_id, v_empresa_id)
  where status <> 'CANCELADO'
    and percentual_total > 100.0001;

  select count(*)
    into v_count
  from _rateio_alvos;

  if v_count <> 122 then
    raise exception
      'Rateios: esperado 122 titulos operacionais acima de 100%%; encontrado %.',
      v_count;
  end if;

  select md5(string_agg(a.titulo_id::text, E'\n' order by a.titulo_id::text))
    into v_hash
  from _rateio_alvos a;

  if v_hash is distinct from '14da6ce3df74187d2635b6198bc8a14d' then
    raise exception
      'Rateios: manifesto de titulos mudou (hash %).',
      v_hash;
  end if;

  if (
    select count(*) from _rateio_alvos where status = 'PENDENTE'
  ) <> 117
  or (
    select count(*) from _rateio_alvos where status = 'PAGO'
  ) <> 5
  then
    raise exception 'Rateios: distribuicao por status mudou; lote abortado.';
  end if;

  create temporary table _rateios_before
  on commit drop
  as
  select tr.*
  from f.titulo_rateio tr
  join _rateio_alvos a on a.titulo_id = tr.titulo_id
  where tr.tenant_id = v_tenant_id
    and tr.deleted_at is null;

  select count(*)
    into v_count
  from _rateios_before;

  if v_count <> 244 then
    raise exception
      'Rateios: esperado snapshot com 244 linhas ativas; encontrado %.',
      v_count;
  end if;

  select md5(string_agg(r.id::text, E'\n' order by r.id::text))
    into v_hash
  from _rateios_before r;

  if v_hash is distinct from 'b350cefc897a52bbe3b41297f51748d9' then
    raise exception
      'Rateios: manifesto das linhas mudou (hash %).',
      v_hash;
  end if;

  select count(*)
    into v_total_rateios_before
  from f.titulo_rateio tr
  join f.titulo t
    on t.tenant_id = v_tenant_id
   and t.empresa_id = v_empresa_id
   and t.id = tr.titulo_id
  where tr.tenant_id = v_tenant_id;

  -- Duplicatas rigorosamente iguais. Preserva deterministicamente o menor UUID.
  create temporary table _rateios_duplicados_exatos
  on commit drop
  as
  select x.id
  from (
    select
      tr.id,
      row_number() over (
        partition by
          tr.titulo_id,
          tr.plano_contas_id,
          tr.centro_custo_id,
          tr.os_id,
          tr.percentual,
          tr.valor
        order by tr.id::text
      ) as ordem
    from f.titulo_rateio tr
    join _rateio_alvos a
      on a.titulo_id = tr.titulo_id
     and a.duplicidades_exatas > 0
    where tr.tenant_id = v_tenant_id
      and tr.deleted_at is null
  ) x
  where x.ordem > 1;

  select count(*)
    into v_count
  from _rateios_duplicados_exatos;

  if v_count <> 119 then
    raise exception
      'Rateios: esperado desativar 119 duplicatas exatas; encontrado %.',
      v_count;
  end if;

  select md5(string_agg(d.id::text, E'\n' order by d.id::text))
    into v_hash
  from _rateios_duplicados_exatos d;

  if v_hash is distinct from '383c8771775d8b0f40dd8a60135d88af' then
    raise exception
      'Rateios: conjunto de duplicatas exatas mudou (hash %).',
      v_hash;
  end if;

  -- Leasings antigos: DESP_GERAL foi o fallback automatico; DESP_LEASING e a
  -- classificacao explicita que deve ser preservada.
  create temporary table _rateios_plano_padrao
  on commit drop
  as
  select tr.id
  from f.titulo_rateio tr
  join _rateio_alvos a on a.titulo_id = tr.titulo_id
  join f.plano_contas pc
    on pc.tenant_id = v_tenant_id
   and pc.id = tr.plano_contas_id
   and pc.codigo = 'DESP_GERAL'
   and pc.deleted_at is null
  where tr.tenant_id = v_tenant_id
    and tr.deleted_at is null
    and exists (
      select 1
      from f.titulo_rateio tr_leasing
      join f.plano_contas pc_leasing
        on pc_leasing.tenant_id = v_tenant_id
       and pc_leasing.id = tr_leasing.plano_contas_id
       and pc_leasing.codigo = 'DESP_LEASING'
       and pc_leasing.deleted_at is null
      where tr_leasing.tenant_id = v_tenant_id
        and tr_leasing.titulo_id = tr.titulo_id
        and tr_leasing.deleted_at is null
    );

  select count(*)
    into v_count
  from _rateios_plano_padrao;

  if v_count <> 3 then
    raise exception
      'Rateios: esperado desativar 3 fallbacks DESP_GERAL; encontrado %.',
      v_count;
  end if;

  select md5(string_agg(d.id::text, E'\n' order by d.id::text))
    into v_hash
  from _rateios_plano_padrao d;

  if v_hash is distinct from 'e21cfd3da38ee2087d0943aa4382919c' then
    raise exception
      'Rateios: conjunto DESP_GERAL dos leasings mudou (hash %).',
      v_hash;
  end if;

  if exists (
    select 1
    from _rateios_duplicados_exatos e
    join _rateios_plano_padrao p on p.id = e.id
  ) then
    raise exception 'Rateios: os conjuntos de descarte se sobrepoem.';
  end if;

  insert into f.titulo_rateio_saneamento (
    tenant_id,
    empresa_id,
    lote,
    titulo_id,
    rateio_id,
    acao,
    motivo,
    dados_anteriores
  )
  select
    v_tenant_id,
    v_empresa_id,
    v_lote,
    tr.titulo_id,
    tr.id,
    'SOFT_DELETE_DUPLICADO_EXATO',
    'Linha rigorosamente igual a outro rateio ativo do mesmo titulo.',
    to_jsonb(tr)
  from f.titulo_rateio tr
  join _rateios_duplicados_exatos d on d.id = tr.id;

  insert into f.titulo_rateio_saneamento (
    tenant_id,
    empresa_id,
    lote,
    titulo_id,
    rateio_id,
    acao,
    motivo,
    dados_anteriores
  )
  select
    v_tenant_id,
    v_empresa_id,
    v_lote,
    tr.titulo_id,
    tr.id,
    'SOFT_DELETE_PLANO_PADRAO',
    'Fallback DESP_GERAL criado antes da classificacao explicita DESP_LEASING.',
    to_jsonb(tr)
  from f.titulo_rateio tr
  join _rateios_plano_padrao d on d.id = tr.id;

  update f.titulo_rateio tr
  set
    deleted_at = v_now,
    updated_at = v_now,
    updated_by = a.fn_current_usuario_id()
  where tr.tenant_id = v_tenant_id
    and tr.deleted_at is null
    and (
      tr.id in (select d.id from _rateios_duplicados_exatos d)
      or tr.id in (select d.id from _rateios_plano_padrao d)
    );

  get diagnostics v_count = row_count;

  if v_count <> 122 then
    raise exception
      'Rateios: esperado soft delete de 122 linhas; alterado %.',
      v_count;
  end if;

  update f.titulo_rateio_saneamento s
  set dados_posteriores = to_jsonb(tr)
  from f.titulo_rateio tr
  where s.tenant_id = v_tenant_id
    and s.empresa_id = v_empresa_id
    and s.lote = v_lote
    and tr.id = s.rateio_id;

  if (
    select count(*)
    from f.titulo_rateio_saneamento s
    where s.tenant_id = v_tenant_id
      and s.empresa_id = v_empresa_id
      and s.lote = v_lote
      and s.dados_posteriores is not null
  ) <> 122 then
    raise exception 'Rateios: trilha de saneamento incompleta.';
  end if;

  if exists (
    select 1
    from f.preview_inconsistencias_rateio(v_tenant_id, v_empresa_id)
    where status <> 'CANCELADO'
      and percentual_total > 100.0001
  ) then
    raise exception
      'Rateios: ainda existem titulos operacionais acima de 100%%.';
  end if;

  -- A unica divergencia operacional remanescente e deliberadamente mantida
  -- para decisao contabil: NF-e/documento R$ 280, cobranca/AP/pagamento R$ 80.
  if (
    select count(*)
    from f.preview_inconsistencias_rateio(v_tenant_id, v_empresa_id)
    where status <> 'CANCELADO'
  ) <> 1
  or not exists (
    select 1
    from f.preview_inconsistencias_rateio(v_tenant_id, v_empresa_id)
    where status <> 'CANCELADO'
      and titulo_id = '3f2a356b-1081-4c43-8b9a-fa752ab735d5'::uuid
      and percentual_total = 100.0000
      and valor_titulo = 80.00
      and valor_rateado = 280.00
  ) then
    raise exception
      'Rateios: pendencias operacionais remanescentes diferem da NF-e 6654/1 esperada.';
  end if;

  if exists (
    select 1
    from _rateio_alvos a
    left join lateral (
      select
        count(*) as quantidade,
        coalesce(sum(tr.percentual), 0) as percentual,
        coalesce(sum(coalesce(
          tr.valor,
          round(a.valor_titulo * coalesce(tr.percentual, 0) / 100.0, 2),
          0
        )), 0) as valor
      from f.titulo_rateio tr
      where tr.tenant_id = v_tenant_id
        and tr.titulo_id = a.titulo_id
        and tr.deleted_at is null
    ) r on true
    where r.quantidade <> 1
       or abs(r.percentual - 100.0000) > 0.0001
       or abs(r.valor - a.valor_titulo) > 0.01
  ) then
    raise exception
      'Rateios: pos-condicao de um rateio, 100%% e valor integral falhou.';
  end if;

  select count(*)
    into v_total_rateios_after
  from f.titulo_rateio tr
  join f.titulo t
    on t.tenant_id = v_tenant_id
   and t.empresa_id = v_empresa_id
   and t.id = tr.titulo_id
  where tr.tenant_id = v_tenant_id;

  if v_total_rateios_after <> v_total_rateios_before then
    raise exception
      'Rateios: quantidade fisica mudou; hard delete ou insert inesperado.';
  end if;
end;
$$;
