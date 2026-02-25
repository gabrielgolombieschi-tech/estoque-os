-- Fase 3: Credito fiscal para AP manual (sem XML)

create table if not exists f.credito_fiscal_manual_regra (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid,
  imposto text not null,
  modo text not null,
  aliquota numeric(7,4) not null default 0,
  parcelas_apropriacao integer not null default 1,
  competencia_offset_meses integer not null default 0,
  prioridade integer not null default 100,
  ativo boolean not null default true,
  aplica_origem text,
  descricao_like text,
  motivo_compra_id uuid,
  fornecedor_id integer,
  observacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  constraint credito_fiscal_manual_regra_imposto_ck check (upper(imposto) in ('ICMS','PIS','COFINS')),
  constraint credito_fiscal_manual_regra_modo_ck check (modo in ('NAO_CREDITA','CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO')),
  constraint credito_fiscal_manual_regra_aliquota_ck check (aliquota >= 0 and aliquota <= 100),
  constraint credito_fiscal_manual_regra_parcelas_ck check (parcelas_apropriacao between 1 and 240),
  constraint credito_fiscal_manual_regra_prioridade_ck check (prioridade between 1 and 9999)
);
create index if not exists idx_credito_fiscal_manual_regra_match
  on f.credito_fiscal_manual_regra (tenant_id, empresa_id, imposto, ativo, prioridade)
  where deleted_at is null;
create table if not exists f.credito_fiscal_manual_lancamento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  titulo_id uuid not null,
  regra_id uuid,
  imposto text not null,
  natureza text not null default 'CREDITO',
  competencia_date date not null,
  base_calculo numeric(15,2) not null default 0,
  aliquota numeric(7,4) not null default 0,
  valor_credito numeric(15,2) not null default 0,
  modo text not null,
  status text not null default 'PROVISIONADO',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  constraint credito_fiscal_manual_lancamento_imposto_ck check (upper(imposto) in ('ICMS','PIS','COFINS')),
  constraint credito_fiscal_manual_lancamento_natureza_ck check (natureza in ('CREDITO')),
  constraint credito_fiscal_manual_lancamento_modo_ck check (modo in ('NAO_CREDITA','CREDITA_IMEDIATO','CREDITA_PARCELADO','PENDENTE_REVISAO')),
  constraint credito_fiscal_manual_lancamento_status_ck check (status in ('PROVISIONADO','APROPRIADO','PENDENTE_REVISAO','CANCELADO')),
  constraint credito_fiscal_manual_lancamento_valor_ck check (valor_credito >= 0)
);
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'fk_credito_fiscal_manual_lancamento_titulo'
      and conrelid = 'f.credito_fiscal_manual_lancamento'::regclass
  ) then
    alter table f.credito_fiscal_manual_lancamento
      add constraint fk_credito_fiscal_manual_lancamento_titulo
      foreign key (titulo_id) references f.titulo(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'fk_credito_fiscal_manual_lancamento_regra'
      and conrelid = 'f.credito_fiscal_manual_lancamento'::regclass
  ) then
    alter table f.credito_fiscal_manual_lancamento
      add constraint fk_credito_fiscal_manual_lancamento_regra
      foreign key (regra_id) references f.credito_fiscal_manual_regra(id) on delete set null;
  end if;
end $$;
create unique index if not exists uq_credito_fiscal_manual_lancamento_unique
  on f.credito_fiscal_manual_lancamento (tenant_id, titulo_id, imposto, competencia_date, coalesce(regra_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where deleted_at is null;
create index if not exists idx_credito_fiscal_manual_lancamento_range
  on f.credito_fiscal_manual_lancamento (tenant_id, empresa_id, competencia_date, imposto, status)
  where deleted_at is null;
create or replace function f.fn_pick_credito_fiscal_manual_regra(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_imposto text,
  p_origem text,
  p_descricao text,
  p_motivo_compra_id uuid,
  p_fornecedor_id integer
) returns table(
  regra_id uuid,
  modo text,
  aliquota numeric,
  parcelas_apropriacao integer,
  competencia_offset_meses integer,
  fonte text
)
language plpgsql
security definer
set search_path to 'f', 'public'
set row_security to off
as $$
declare
  v_rule record;
begin
  select
    r.id,
    r.modo,
    r.aliquota,
    r.parcelas_apropriacao,
    r.competencia_offset_meses
  into v_rule
  from f.credito_fiscal_manual_regra r
  where r.tenant_id = p_tenant_id
    and (r.empresa_id is null or r.empresa_id = p_empresa_id)
    and r.deleted_at is null
    and r.ativo = true
    and upper(r.imposto) = upper(p_imposto)
    and (r.aplica_origem is null or upper(r.aplica_origem) = upper(coalesce(p_origem,'')))
    and (r.descricao_like is null or upper(coalesce(p_descricao,'')) like upper(r.descricao_like))
    and (r.motivo_compra_id is null or r.motivo_compra_id = p_motivo_compra_id)
    and (r.fornecedor_id is null or r.fornecedor_id = p_fornecedor_id)
  order by
    r.prioridade asc,
    (case when r.empresa_id is null then 1 else 0 end) asc,
    (case when r.fornecedor_id is null then 1 else 0 end) asc,
    (case when r.motivo_compra_id is null then 1 else 0 end) asc,
    (case when r.descricao_like is null then 1 else 0 end) asc,
    r.created_at asc
  limit 1;

  if found then
    regra_id := v_rule.id;
    modo := v_rule.modo;
    aliquota := coalesce(v_rule.aliquota,0);
    parcelas_apropriacao := coalesce(v_rule.parcelas_apropriacao,1);
    competencia_offset_meses := coalesce(v_rule.competencia_offset_meses,0);
    fonte := 'REGRA';
    return next;
    return;
  end if;

  regra_id := null;
  modo := 'PENDENTE_REVISAO';
  aliquota := 0;
  parcelas_apropriacao := 1;
  competencia_offset_meses := 0;
  fonte := 'FALLBACK_PENDENTE';
  return next;
end;
$$;
create or replace function f.fn_aplicar_credito_fiscal_manual_titulo(
  p_titulo_id uuid,
  p_change_reason text default null
) returns table(
  status text,
  message text,
  lancamentos_gerados integer
)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to off
as $$
declare
  v_titulo f.titulo%rowtype;
  v_generated integer := 0;
  v_base numeric(15,2);
  v_imp text;
  v_rule record;
  v_comp_base date;
  v_parcelas integer;
  v_i integer;
  v_valor_total numeric(15,2);
  v_valor_parcela numeric(15,2);
  v_valor_last numeric(15,2);
  v_comp date;
begin
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.deleted_at is not null then
    update f.credito_fiscal_manual_lancamento
       set status = 'CANCELADO',
           deleted_at = now(),
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
     where tenant_id = v_titulo.tenant_id
       and titulo_id = v_titulo.id
       and deleted_at is null;

    status := 'ok';
    message := 'Titulo removido: lancamentos fiscais manuais cancelados.';
    lancamentos_gerados := 0;
    return next;
    return;
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from v_titulo.tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if public.current_empresa_id() is distinct from v_titulo.empresa_id then
      raise exception 'Empresa mismatch';
    end if;
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- Apenas AP manual sem documento fiscal (cenario energia/leasing/boletos)
  if v_titulo.tipo <> 'AP' or upper(coalesce(v_titulo.origem,'')) <> 'MANUAL' or v_titulo.documento_fiscal_id is not null then
    update f.credito_fiscal_manual_lancamento
       set status = 'CANCELADO',
           deleted_at = now(),
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
     where tenant_id = v_titulo.tenant_id
       and titulo_id = v_titulo.id
       and deleted_at is null;

    status := 'ok';
    message := 'Titulo fora do escopo de credito fiscal manual.';
    lancamentos_gerados := 0;
    return next;
    return;
  end if;

  v_base := round(coalesce(v_titulo.valor_total,0),2);
  if v_base <= 0 then
    status := 'ok';
    message := 'Titulo sem base para credito.';
    lancamentos_gerados := 0;
    return next;
    return;
  end if;

  update f.credito_fiscal_manual_lancamento
     set status = 'CANCELADO',
         deleted_at = now(),
         updated_at = now(),
         updated_by = a.fn_current_usuario_id()
   where tenant_id = v_titulo.tenant_id
     and titulo_id = v_titulo.id
     and deleted_at is null;

  foreach v_imp in array array['ICMS','PIS','COFINS']
  loop
    select * into v_rule
    from f.fn_pick_credito_fiscal_manual_regra(
      v_titulo.tenant_id,
      v_titulo.empresa_id,
      v_imp,
      v_titulo.origem,
      v_titulo.descricao,
      v_titulo.motivo_compra_id,
      v_titulo.fornecedor_id
    )
    limit 1;

    if v_rule.modo is null then
      continue;
    end if;

    v_comp_base := coalesce(v_titulo.competencia_date, date_trunc('month', coalesce(v_titulo.emissao_date, current_date))::date);
    v_comp_base := (v_comp_base + make_interval(months => coalesce(v_rule.competencia_offset_meses,0)))::date;

    if v_rule.modo = 'NAO_CREDITA' then
      continue;
    end if;

    if v_rule.modo = 'PENDENTE_REVISAO' then
      insert into f.credito_fiscal_manual_lancamento(
        tenant_id, empresa_id, titulo_id, regra_id, imposto, natureza,
        competencia_date, base_calculo, aliquota, valor_credito, modo, status,
        created_by, updated_by
      ) values (
        v_titulo.tenant_id, v_titulo.empresa_id, v_titulo.id, v_rule.regra_id, v_imp, 'CREDITO',
        v_comp_base, v_base, coalesce(v_rule.aliquota,0), round(v_base * coalesce(v_rule.aliquota,0) / 100, 2), v_rule.modo, 'PENDENTE_REVISAO',
        a.fn_current_usuario_id(), a.fn_current_usuario_id()
      )
      on conflict do nothing;
      continue;
    end if;

    v_valor_total := round(v_base * coalesce(v_rule.aliquota,0) / 100, 2);
    if v_valor_total <= 0 then
      continue;
    end if;

    v_parcelas := case when v_rule.modo = 'CREDITA_PARCELADO' then greatest(1, coalesce(v_rule.parcelas_apropriacao,1)) else 1 end;

    if v_parcelas = 1 then
      insert into f.credito_fiscal_manual_lancamento(
        tenant_id, empresa_id, titulo_id, regra_id, imposto, natureza,
        competencia_date, base_calculo, aliquota, valor_credito, modo, status,
        created_by, updated_by
      ) values (
        v_titulo.tenant_id, v_titulo.empresa_id, v_titulo.id, v_rule.regra_id, v_imp, 'CREDITO',
        v_comp_base, v_base, coalesce(v_rule.aliquota,0), v_valor_total, v_rule.modo, 'PROVISIONADO',
        a.fn_current_usuario_id(), a.fn_current_usuario_id()
      )
      on conflict do nothing;
      v_generated := v_generated + 1;
    else
      v_valor_parcela := round(v_valor_total / v_parcelas, 2);
      v_valor_last := v_valor_total - (v_valor_parcela * (v_parcelas - 1));

      for v_i in 0..(v_parcelas - 1)
      loop
        v_comp := (v_comp_base + make_interval(months => v_i))::date;

        insert into f.credito_fiscal_manual_lancamento(
          tenant_id, empresa_id, titulo_id, regra_id, imposto, natureza,
          competencia_date, base_calculo, aliquota, valor_credito, modo, status,
          created_by, updated_by
        ) values (
          v_titulo.tenant_id, v_titulo.empresa_id, v_titulo.id, v_rule.regra_id, v_imp, 'CREDITO',
          v_comp,
          case when v_i = v_parcelas - 1 then v_base - (round(v_base / v_parcelas, 2) * (v_parcelas - 1)) else round(v_base / v_parcelas, 2) end,
          coalesce(v_rule.aliquota,0),
          case when v_i = v_parcelas - 1 then v_valor_last else v_valor_parcela end,
          v_rule.modo,
          'PROVISIONADO',
          a.fn_current_usuario_id(), a.fn_current_usuario_id()
        )
        on conflict do nothing;

        v_generated := v_generated + 1;
      end loop;
    end if;
  end loop;

  status := 'ok';
  message := coalesce(p_change_reason, 'Credito fiscal manual reaplicado ao titulo.');
  lancamentos_gerados := v_generated;
  return next;
end;
$$;
create or replace function f.trg_titulo__aplicar_credito_fiscal_manual()
returns trigger
language plpgsql
security definer
set search_path to 'f','public','a','c'
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if coalesce(new.tipo,'') = 'AP' then
    perform 1 from f.fn_aplicar_credito_fiscal_manual_titulo(new.id, 'TRIGGER_TITULO_MANUAL');
  end if;
  return new;
end;
$$;
drop trigger if exists trg_titulo__aplicar_credito_fiscal_manual on f.titulo;
create trigger trg_titulo__aplicar_credito_fiscal_manual
after insert or update of tipo, origem, fornecedor_id, motivo_compra_id, descricao, emissao_date, competencia_date, valor_total, documento_fiscal_id, deleted_at
on f.titulo
for each row
execute function f.trg_titulo__aplicar_credito_fiscal_manual();
create or replace function f.fn_imposto_credito_manual_range(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_comp_ini date,
  p_comp_fim date,
  p_operacao text default null,
  p_natureza text default null
) returns table(
  tenant_id uuid,
  empresa_id uuid,
  competencia_date date,
  operacao text,
  imposto text,
  natureza text,
  base_total numeric,
  valor_total_calculado numeric,
  valor_total_ajustado numeric,
  qtd_documentos bigint
)
language plpgsql
security definer
set search_path to 'f','public','a','c'
set row_security to off
as $$
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id e obrigatorio.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id e obrigatorio.'; end if;
  if p_comp_ini is null or p_comp_fim is null then raise exception 'Informe p_comp_ini e p_comp_fim'; end if;
  if p_comp_fim <= p_comp_ini then raise exception 'Intervalo invalido: p_comp_fim deve ser > p_comp_ini'; end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from p_tenant_id then raise exception 'Tenant mismatch'; end if;
    if public.current_empresa_id() is distinct from p_empresa_id then raise exception 'Empresa mismatch'; end if;
    if not f.has_finance_access(p_tenant_id, p_empresa_id) then raise exception 'Sem permissao: somente ADMIN/FINANCEIRO'; end if;
  end if;

  return query
  select
    l.tenant_id,
    l.empresa_id,
    l.competencia_date,
    'ENTRADA'::text as operacao,
    upper(l.imposto) as imposto,
    'CREDITO'::text as natureza,
    round(sum(coalesce(l.base_calculo,0))::numeric,2) as base_total,
    round(sum(coalesce(l.valor_credito,0))::numeric,2) as valor_total_calculado,
    0::numeric as valor_total_ajustado,
    count(distinct l.titulo_id)::bigint as qtd_documentos
  from f.credito_fiscal_manual_lancamento l
  where l.tenant_id = p_tenant_id
    and l.empresa_id = p_empresa_id
    and l.deleted_at is null
    and l.status in ('PROVISIONADO','APROPRIADO')
    and l.competencia_date >= p_comp_ini
    and l.competencia_date < p_comp_fim
    and (p_operacao is null or upper(p_operacao) = 'ENTRADA')
    and (p_natureza is null or upper(p_natureza) = 'CREDITO')
  group by l.tenant_id, l.empresa_id, l.competencia_date, upper(l.imposto)
  order by l.competencia_date asc, upper(l.imposto) asc;
end;
$$;
alter table f.credito_fiscal_manual_regra enable row level security;
alter table f.credito_fiscal_manual_lancamento enable row level security;
drop policy if exists credito_fiscal_manual_regra_all on f.credito_fiscal_manual_regra;
create policy credito_fiscal_manual_regra_all
  on f.credito_fiscal_manual_regra
  to authenticated
  using (tenant_id = public.current_tenant_id() and f.has_finance_access())
  with check (tenant_id = public.current_tenant_id() and f.has_finance_access());
drop policy if exists credito_fiscal_manual_lancamento_all on f.credito_fiscal_manual_lancamento;
create policy credito_fiscal_manual_lancamento_all
  on f.credito_fiscal_manual_lancamento
  to authenticated
  using (tenant_id = public.current_tenant_id() and f.has_finance_access())
  with check (tenant_id = public.current_tenant_id() and f.has_finance_access());
revoke all on table f.credito_fiscal_manual_regra from public;
grant select, insert, update, delete on table f.credito_fiscal_manual_regra to authenticated;
grant select on table f.credito_fiscal_manual_regra to service_role;
revoke all on table f.credito_fiscal_manual_lancamento from public;
grant select, insert, update, delete on table f.credito_fiscal_manual_lancamento to authenticated;
grant select on table f.credito_fiscal_manual_lancamento to service_role;
revoke all on function f.fn_pick_credito_fiscal_manual_regra(uuid, uuid, text, text, text, uuid, integer) from public;
grant execute on function f.fn_pick_credito_fiscal_manual_regra(uuid, uuid, text, text, text, uuid, integer) to authenticated;
grant execute on function f.fn_pick_credito_fiscal_manual_regra(uuid, uuid, text, text, text, uuid, integer) to service_role;
revoke all on function f.fn_aplicar_credito_fiscal_manual_titulo(uuid, text) from public;
grant execute on function f.fn_aplicar_credito_fiscal_manual_titulo(uuid, text) to authenticated;
grant execute on function f.fn_aplicar_credito_fiscal_manual_titulo(uuid, text) to service_role;
revoke all on function f.fn_imposto_credito_manual_range(uuid, uuid, date, date, text, text) from public;
grant execute on function f.fn_imposto_credito_manual_range(uuid, uuid, date, date, text, text) to authenticated;
grant execute on function f.fn_imposto_credito_manual_range(uuid, uuid, date, date, text, text) to service_role;
-- Regras padrao: energia automatica (PIS/COFINS) e leasing em revisao
insert into f.credito_fiscal_manual_regra(
  tenant_id, empresa_id, imposto, modo, aliquota, parcelas_apropriacao, prioridade, ativo,
  aplica_origem, descricao_like, observacao
)
select
  e.tenant_id,
  e.id,
  r.imposto,
  r.modo,
  r.aliquota,
  r.parcelas_apropriacao,
  r.prioridade,
  true,
  'MANUAL',
  r.descricao_like,
  r.observacao
from public.empresas e
cross join (
  values
    ('PIS','CREDITA_IMEDIATO',1.6500::numeric,1,20,'%ENERG%','Energia eletrica manual: PIS imediato'),
    ('COFINS','CREDITA_IMEDIATO',7.6000::numeric,1,20,'%ENERG%','Energia eletrica manual: COFINS imediato'),
    ('PIS','CREDITA_IMEDIATO',1.6500::numeric,1,20,'%CPFL%','Energia CPFL: PIS imediato'),
    ('COFINS','CREDITA_IMEDIATO',7.6000::numeric,1,20,'%CPFL%','Energia CPFL: COFINS imediato'),
    ('PIS','CREDITA_IMEDIATO',1.6500::numeric,1,20,'%CELESC%','Energia CELESC: PIS imediato'),
    ('COFINS','CREDITA_IMEDIATO',7.6000::numeric,1,20,'%CELESC%','Energia CELESC: COFINS imediato'),
    ('PIS','CREDITA_IMEDIATO',1.6500::numeric,1,20,'%ENEL%','Energia ENEL: PIS imediato'),
    ('COFINS','CREDITA_IMEDIATO',7.6000::numeric,1,20,'%ENEL%','Energia ENEL: COFINS imediato'),
    ('ICMS','PENDENTE_REVISAO',0::numeric,1,30,'%LEAS%','Leasing manual: revisar ICMS'),
    ('PIS','PENDENTE_REVISAO',0::numeric,1,30,'%LEAS%','Leasing manual: revisar PIS'),
    ('COFINS','PENDENTE_REVISAO',0::numeric,1,30,'%LEAS%','Leasing manual: revisar COFINS')
) r(imposto,modo,aliquota,parcelas_apropriacao,prioridade,descricao_like,observacao)
where coalesce(e.ativo,true)=true
  and not exists (
    select 1
    from f.credito_fiscal_manual_regra x
    where x.tenant_id=e.tenant_id
      and x.empresa_id=e.id
      and x.imposto=r.imposto
      and x.modo=r.modo
      and x.descricao_like=r.descricao_like
      and x.deleted_at is null
  );
-- Reprocessa todos AP manuais ativos
select rr.status, rr.message, rr.lancamentos_gerados
from f.titulo t
cross join lateral f.fn_aplicar_credito_fiscal_manual_titulo(t.id, 'BACKFILL_FASE3') rr
where t.deleted_at is null
  and t.tipo='AP'
  and upper(coalesce(t.origem,''))='MANUAL';
