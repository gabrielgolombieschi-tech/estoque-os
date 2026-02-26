-- Gestão Cobrança de OS concluídas

create or replace function f.has_cobranca_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
) returns boolean
language sql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  select f.has_finance_access(p_tenant, p_empresa);
$$;

create table if not exists f.gestao_cobranca_os (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  empresa_id uuid not null default public.current_empresa_id(),
  os_id integer not null references public.ordens_servico(id),
  status text not null default 'PENDENTE'
    check (status in ('PENDENTE','FATURADO','RECEBIDO','CANCELADO')),
  pedido_compra_cliente text,
  pedido_recebido_em date,
  faturado_em date,
  documento_fiscal_id uuid references f.documento_fiscal(id),
  titulo_ar_id uuid references f.titulo(id),
  responsavel_id uuid references a.usuario(id),
  proximo_contato_date date,
  observacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default a.fn_current_usuario_id(),
  updated_by uuid,
  deleted_at timestamptz,
  constraint pk_f_gestao_cobranca_os primary key (id),
  constraint uq_gestao_cobranca_os__tenant_empresa_os unique (tenant_id, empresa_id, os_id)
);

create index if not exists idx_gestao_cobranca_os__tenant_empresa_status
  on f.gestao_cobranca_os (tenant_id, empresa_id, status)
  where deleted_at is null;

create index if not exists idx_gestao_cobranca_os__tenant_empresa_os
  on f.gestao_cobranca_os (tenant_id, empresa_id, os_id)
  where deleted_at is null;

create index if not exists idx_gestao_cobranca_os__proximo_contato
  on f.gestao_cobranca_os (tenant_id, empresa_id, proximo_contato_date)
  where deleted_at is null;

drop trigger if exists trg_gestao_cobranca_os_set_updated_at on f.gestao_cobranca_os;
create trigger trg_gestao_cobranca_os_set_updated_at
before update on f.gestao_cobranca_os
for each row execute function a.fn_set_updated_at();

drop trigger if exists trg_gestao_cobranca_os_set_updated_by on f.gestao_cobranca_os;
create trigger trg_gestao_cobranca_os_set_updated_by
before update on f.gestao_cobranca_os
for each row execute function f.fn_set_updated_by();

drop trigger if exists trg_audit_gestao_cobranca_os on f.gestao_cobranca_os;
create trigger trg_audit_gestao_cobranca_os
after insert or update or delete on f.gestao_cobranca_os
for each row execute function public.audit_trigger();

alter table f.gestao_cobranca_os enable row level security;

drop policy if exists gestao_cobranca_os_all on f.gestao_cobranca_os;
create policy gestao_cobranca_os_all
on f.gestao_cobranca_os
for all
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and f.has_cobranca_access()
)
with check (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and f.has_cobranca_access()
);

insert into f.gestao_cobranca_os (tenant_id, empresa_id, os_id, status)
select os.tenant_id, os.empresa_id, os.id, 'PENDENTE'
from public.ordens_servico os
where os.status = 'concluida'
on conflict on constraint uq_gestao_cobranca_os__tenant_empresa_os do nothing;

create or replace function public.fn_on_os_concluida_init_cobranca()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'f', 'a', 'c'
set row_security to 'off'
as $$
begin
  if new.status = 'concluida' and old.status is distinct from 'concluida' then
    insert into f.gestao_cobranca_os (tenant_id, empresa_id, os_id, status)
    values (new.tenant_id, new.empresa_id, new.id, 'PENDENTE')
    on conflict on constraint uq_gestao_cobranca_os__tenant_empresa_os do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_on_os_concluida_init_cobranca on public.ordens_servico;
create trigger trg_on_os_concluida_init_cobranca
after update of status on public.ordens_servico
for each row
execute function public.fn_on_os_concluida_init_cobranca();

create or replace view r.r_gestao_cobranca_os as
select
  os.tenant_id,
  os.empresa_id,
  os.id as os_id,
  os.numero_os,
  os.os_num,
  os.cliente_nome,
  os.descricao_servico,
  os.data_conclusao,
  os.valor_total,
  os.pedido_compra as pedido_compra_os,
  gc.id as cobranca_id,
  gc.status as cobranca_status,
  gc.pedido_compra_cliente,
  gc.pedido_recebido_em,
  gc.faturado_em,
  gc.proximo_contato_date,
  gc.responsavel_id,
  gc.observacao,
  df.documento_fiscal_id,
  df.doc_modelo,
  df.doc_serie,
  df.doc_numero,
  df.doc_emissao_date,
  df.doc_status,
  ar.titulo_ar_id,
  ar.ar_status,
  ar.ar_valor_total,
  ar.ar_valor_aberto,
  case
    when os.data_conclusao is null then null
    else (current_date - os.data_conclusao::date)
  end::integer as dias_desde_conclusao
from public.ordens_servico os
left join f.gestao_cobranca_os gc
  on gc.tenant_id = os.tenant_id
 and gc.empresa_id = os.empresa_id
 and gc.os_id = os.id
 and gc.deleted_at is null
left join lateral (
  select
    d.id as documento_fiscal_id,
    d.modelo as doc_modelo,
    d.serie as doc_serie,
    d.numero as doc_numero,
    d.emissao_date as doc_emissao_date,
    coalesce(d.nfe_status, d.nfse_status) as doc_status
  from f.documento_fiscal d
  where d.tenant_id = os.tenant_id
    and d.empresa_id = os.empresa_id
    and d.os_id_import = os.id
    and d.operacao = 'SAIDA'
    and d.deleted_at is null
  order by d.emissao_date desc nulls last, d.created_at desc
  limit 1
) df on true
left join lateral (
  select
    t.id as titulo_ar_id,
    t.status as ar_status,
    t.valor_total as ar_valor_total,
    t.valor_aberto as ar_valor_aberto
  from f.titulo t
  where t.tenant_id = os.tenant_id
    and t.empresa_id = os.empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = df.documento_fiscal_id
    and t.deleted_at is null
  order by t.created_at desc
  limit 1
) ar on true
where os.status = 'concluida';
