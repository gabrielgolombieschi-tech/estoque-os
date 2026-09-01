begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

-- Evolui a fila que ja alimentava a gestao de cobranca. A ordem e
-- intencional: remove a constraint antiga, converte os dados e so entao
-- instala o novo vocabulario.
alter table f.gestao_cobranca_os
  drop constraint if exists gestao_cobranca_os_status_check;

alter table f.gestao_cobranca_os
  alter column os_id drop not null,
  alter column status set default 'ABERTO';

update f.gestao_cobranca_os
set status = 'ABERTO'
where status = 'PENDENTE';

alter table f.gestao_cobranca_os
  add column if not exists cliente_id integer,
  add column if not exists unidade_id bigint,
  add column if not exists origem text not null default 'OS_SEM_OC',
  add column if not exists descricao text,
  add column if not exists valor_estimado numeric(15,2),
  add column if not exists valor_confirmado numeric(15,2),
  add column if not exists valor_origem text,
  add column if not exists valor_calculado_em timestamptz,
  add column if not exists data_competencia date default current_date;

update f.gestao_cobranca_os g
set cliente_id = os.cliente_id,
    unidade_id = os.unidade_id,
    data_competencia = coalesce(g.data_competencia, os.data_conclusao::date, os.data_abertura::date, current_date),
    origem = case when g.origem is null or g.origem = 'OS_SEM_OC' then 'OS_CONCLUIDA_SEM_NF' else g.origem end
from public.ordens_servico os
where os.id = g.os_id
  and os.tenant_id = g.tenant_id
  and os.empresa_id = g.empresa_id;

alter table f.gestao_cobranca_os
  alter column data_competencia set default current_date;

alter table f.gestao_cobranca_os
  add constraint gestao_cobranca_os_status_check
  check (status in ('ABERTO','OC_RECEBIDA','FATURADO','RECEBIDO','PERDIDO','CANCELADO')),
  add constraint gestao_cobranca_os_origem_check
  check (origem in (
    'OS_CONCLUIDA_SEM_NF','SERVICO_URGENCIA','MATERIAL_ANTECIPADO',
    'OS_SEM_OC','AVULSO_LEGADO','IMPORTACAO_CSV','OUTRO'
  )),
  add constraint gestao_cobranca_os_valor_estimado_check
  check (valor_estimado is null or valor_estimado >= 0),
  add constraint gestao_cobranca_os_valor_confirmado_check
  check (valor_confirmado is null or valor_confirmado >= 0),
  add constraint gestao_cobranca_os_valor_origem_check
  check (valor_origem is null or valor_origem in ('ORCAMENTO','CALCULADO','CONFIRMADO','DOCUMENTO','MANUAL'));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'gestao_cobranca_os_cliente_fk'
      and conrelid = 'f.gestao_cobranca_os'::regclass
  ) then
    alter table f.gestao_cobranca_os
      add constraint gestao_cobranca_os_cliente_fk
      foreign key (tenant_id, empresa_id, cliente_id)
      references public.clientes (tenant_id, empresa_id, id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'gestao_cobranca_os_unidade_fk'
      and conrelid = 'f.gestao_cobranca_os'::regclass
  ) then
    alter table f.gestao_cobranca_os
      add constraint gestao_cobranca_os_unidade_fk
      foreign key (tenant_id, empresa_id, unidade_id)
      references public.cliente_unidades (tenant_id, empresa_id, id)
      on delete set null;
  end if;
end;
$$;

create index if not exists gestao_cobranca_os_cliente_status_idx
  on f.gestao_cobranca_os (tenant_id, empresa_id, cliente_id, status)
  where deleted_at is null;

create index if not exists gestao_cobranca_os_competencia_idx
  on f.gestao_cobranca_os (tenant_id, empresa_id, data_competencia desc)
  where deleted_at is null;

-- Precedencia de valor: orcamento vinculado, depois HH + materiais com a
-- mesma regra canonica de preco usada pelo Comercial.
create or replace function f.fn_calcular_exposicao_os_unscoped(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns table(valor numeric, origem text)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_orcamento numeric;
  v_hh numeric := 0;
  v_materiais numeric := 0;
  v_margem numeric := 53;
begin
  if not exists (
    select 1 from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = p_tenant_id
      and os.empresa_id = p_empresa_id
  ) then
    return query select 0::numeric, 'CALCULADO'::text;
    return;
  end if;

  select coalesce(nullif(o.valor_fechado, 0), nullif(o.total_liquido, 0))
    into v_orcamento
  from m.orcamento o
  where o.tenant_id = p_tenant_id
    and o.empresa_id = p_empresa_id
    and o.os_id = p_os_id
    and o.deleted_at is null
  order by o.updated_at desc nulls last, o.created_at desc
  limit 1;

  if coalesce(v_orcamento, 0) > 0 then
    return query select round(v_orcamento, 2), 'ORCAMENTO'::text;
    return;
  end if;

  select coalesce(c.margem_lucro_padrao_percent, 53)
    into v_margem
  from a.config_orcamento c
  where c.tenant_id = p_tenant_id
    and c.empresa_id = p_empresa_id
    and c.deleted_at is null
  order by c.updated_at desc nulls last, c.created_at desc
  limit 1;

  select coalesce(v.total_hh, 0)
    into v_hh
  from public.vw_hh_total_os v
  where v.tenant_id = p_tenant_id
    and v.empresa_id = p_empresa_id
    and v.os_id = p_os_id;

  select coalesce(sum(
           oi.quantidade * public.fn_preco_venda_item_valores(
             i.custo_ultima_compra,
             i.preco_unitario,
             i.aliquota_ipi,
             coalesce(v_margem, 53)
           )
         ), 0)
    into v_materiais
  from public.os_itens oi
  join public.itens i
    on i.id = oi.item_id
   and i.tenant_id = oi.tenant_id
   and i.empresa_id = oi.empresa_id
  where oi.tenant_id = p_tenant_id
    and oi.empresa_id = p_empresa_id
    and oi.os_id = p_os_id;

  return query select round(coalesce(v_hh, 0) + coalesce(v_materiais, 0), 2), 'CALCULADO'::text;
end;
$$;

revoke all on function f.fn_calcular_exposicao_os_unscoped(uuid,uuid,integer)
  from public, anon, authenticated;

create or replace function f.fn_garantir_venda_credito_os(
  p_os_id integer,
  p_origem text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_os public.ordens_servico%rowtype;
  v_valor numeric;
  v_valor_origem text;
  v_origem text;
  v_id uuid;
begin
  select * into v_os
  from public.ordens_servico os
  where os.id = p_os_id;

  if not found then return null; end if;
  if v_os.cliente_id is null then
    raise exception 'venda_credito_os_sem_cliente:%', p_os_id;
  end if;
  if v_os.status = 'cancelada' or coalesce(v_os.status_fluxo, '') = 'faturada' then
    return null;
  end if;

  v_origem := coalesce(nullif(p_origem, ''),
    case
      when v_os.tipo_pedido = 'material' then 'MATERIAL_ANTECIPADO'
      when v_os.tipo_pedido = 'servico' then 'SERVICO_URGENCIA'
      else 'OS_SEM_OC'
    end
  );

  if v_origem not in (
    'OS_CONCLUIDA_SEM_NF','SERVICO_URGENCIA','MATERIAL_ANTECIPADO','OS_SEM_OC'
  ) then
    raise exception 'venda_credito_origem_invalida:%', v_origem;
  end if;

  select x.valor, x.origem
    into v_valor, v_valor_origem
  from f.fn_calcular_exposicao_os_unscoped(v_os.tenant_id, v_os.empresa_id, v_os.id) x;

  insert into f.gestao_cobranca_os (
    tenant_id, empresa_id, os_id, cliente_id, unidade_id, status,
    pedido_compra_cliente, pedido_recebido_em, origem, descricao,
    valor_estimado, valor_origem, valor_calculado_em, data_competencia
  ) values (
    v_os.tenant_id, v_os.empresa_id, v_os.id, v_os.cliente_id, v_os.unidade_id,
    case when nullif(btrim(v_os.pedido_compra), '') is null then 'ABERTO' else 'OC_RECEBIDA' end,
    nullif(btrim(v_os.pedido_compra), ''),
    case when nullif(btrim(v_os.pedido_compra), '') is null then null else current_date end,
    v_origem, v_os.descricao_servico,
    coalesce(v_valor, 0), v_valor_origem, now(),
    coalesce(v_os.data_conclusao::date, v_os.data_abertura::date, current_date)
  )
  on conflict on constraint uq_gestao_cobranca_os__tenant_empresa_os
  do update set
    cliente_id = excluded.cliente_id,
    unidade_id = excluded.unidade_id,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function f.fn_garantir_venda_credito_os(integer,text)
  from public, anon, authenticated;
grant execute on function f.fn_garantir_venda_credito_os(integer,text)
  to service_role;

-- Conclusao da OS continua sendo uma origem valida, agora usando ABERTO e
-- congelando o valor estimado ate uma recalculacao explicita.
create or replace function public.fn_on_os_concluida_init_cobranca()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if new.status = 'concluida' and old.status is distinct from 'concluida' then
    perform f.fn_garantir_venda_credito_os(new.id, 'OS_CONCLUIDA_SEM_NF');
  end if;
  return new;
end;
$$;

create or replace function public.fn_venda_credito_ao_primeiro_lancamento()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_os_id integer := new.os_id::integer;
  v_sem_oc boolean;
begin
  select nullif(btrim(os.pedido_compra), '') is null
    into v_sem_oc
  from public.ordens_servico os
  where os.id = v_os_id
    and os.tenant_id = new.tenant_id
    and os.empresa_id = new.empresa_id;

  if coalesce(v_sem_oc, false) then
    perform f.fn_garantir_venda_credito_os(v_os_id, null);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_os_itens_venda_credito on public.os_itens;
create trigger trg_os_itens_venda_credito
after insert on public.os_itens
for each row execute function public.fn_venda_credito_ao_primeiro_lancamento();

drop trigger if exists trg_hh_lancamentos_venda_credito on public.hh_lancamentos;
create trigger trg_hh_lancamentos_venda_credito
after insert on public.hh_lancamentos
for each row execute function public.fn_venda_credito_ao_primeiro_lancamento();

create or replace function public.fn_venda_credito_ao_receber_oc()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if nullif(btrim(new.pedido_compra), '') is not null
     and nullif(btrim(old.pedido_compra), '') is null then
    update f.gestao_cobranca_os g
       set status = case when g.status = 'ABERTO' then 'OC_RECEBIDA' else g.status end,
           pedido_compra_cliente = btrim(new.pedido_compra),
           pedido_recebido_em = coalesce(g.pedido_recebido_em, current_date),
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
     where g.tenant_id = new.tenant_id
       and g.empresa_id = new.empresa_id
       and g.os_id = new.id
       and g.deleted_at is null
       and g.status not in ('RECEBIDO','CANCELADO');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ordens_servico_venda_credito_oc on public.ordens_servico;
create trigger trg_ordens_servico_venda_credito_oc
after update of pedido_compra on public.ordens_servico
for each row execute function public.fn_venda_credito_ao_receber_oc();

create or replace function f.fn_venda_credito_ao_documento_fiscal()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if new.operacao = 'SAIDA'
     and new.os_id_import is not null
     and new.deleted_at is null
     and coalesce(new.nfe_status, new.nfse_status, 'EMITIDA') = 'EMITIDA' then
    update f.gestao_cobranca_os g
       set status = case when g.status in ('RECEBIDO','CANCELADO') then g.status else 'FATURADO' end,
           documento_fiscal_id = new.id,
           faturado_em = coalesce(new.emissao_date, current_date),
           valor_confirmado = case when new.valor_total > 0 then new.valor_total else g.valor_confirmado end,
           valor_origem = case when new.valor_total > 0 then 'DOCUMENTO' else g.valor_origem end,
           updated_at = now()
     where g.tenant_id = new.tenant_id
       and g.empresa_id = new.empresa_id
       and g.os_id = new.os_id_import
       and g.deleted_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_documento_fiscal_venda_credito on f.documento_fiscal;
create trigger trg_documento_fiscal_venda_credito
after insert or update of nfe_status, nfse_status, deleted_at, os_id_import, valor_total
on f.documento_fiscal
for each row execute function f.fn_venda_credito_ao_documento_fiscal();

create or replace function f.fn_venda_credito_ao_titulo_ar()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if new.tipo = 'AR' and new.deleted_at is null then
    update f.gestao_cobranca_os g
       set status = case
             when new.status = 'PAGO' or new.valor_aberto <= 0 then 'RECEBIDO'
             when g.status not in ('RECEBIDO','CANCELADO') then 'FATURADO'
             else g.status
           end,
           titulo_ar_id = new.id,
           updated_at = now()
     where g.tenant_id = new.tenant_id
       and g.empresa_id = new.empresa_id
       and g.deleted_at is null
       and (
         g.os_id = new.os_id
         or g.documento_fiscal_id = new.documento_fiscal_id
       );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_titulo_ar_venda_credito on f.titulo;
create trigger trg_titulo_ar_venda_credito
after insert or update of status, valor_aberto, deleted_at, documento_fiscal_id, os_id
on f.titulo
for each row execute function f.fn_venda_credito_ao_titulo_ar();

create or replace function f.fn_venda_credito_recalcular(p_credito_id uuid)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_gc f.gestao_cobranca_os%rowtype;
  v_valor numeric;
  v_origem text;
begin
  select * into v_gc from f.gestao_cobranca_os g
  where g.id = p_credito_id
    and g.tenant_id = public.current_tenant_id()
    and g.empresa_id = public.current_empresa_id()
    and g.deleted_at is null;

  if not found or not f.has_cobranca_access(v_gc.tenant_id, v_gc.empresa_id) then
    raise exception 'venda_credito_nao_encontrada_ou_sem_acesso';
  end if;
  if v_gc.os_id is null then raise exception 'venda_credito_avulsa_nao_recalcula'; end if;

  select x.valor, x.origem into v_valor, v_origem
  from f.fn_calcular_exposicao_os_unscoped(v_gc.tenant_id, v_gc.empresa_id, v_gc.os_id) x;

  update f.gestao_cobranca_os
     set valor_estimado = coalesce(v_valor, 0),
         valor_origem = v_origem,
         valor_calculado_em = now(),
         updated_at = now(),
         updated_by = a.fn_current_usuario_id()
   where id = v_gc.id;
  return coalesce(v_valor, 0);
end;
$$;

create or replace function f.fn_venda_credito_registrar_oc(
  p_credito_id uuid,
  p_numero text,
  p_data date default current_date,
  p_valor_confirmado numeric default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare v_gc f.gestao_cobranca_os%rowtype;
begin
  select * into v_gc from f.gestao_cobranca_os g
  where g.id=p_credito_id and g.tenant_id=public.current_tenant_id()
    and g.empresa_id=public.current_empresa_id() and g.deleted_at is null;
  if not found or not f.has_cobranca_access(v_gc.tenant_id,v_gc.empresa_id) then
    raise exception 'venda_credito_nao_encontrada_ou_sem_acesso';
  end if;
  if nullif(btrim(p_numero),'') is null then raise exception 'numero_oc_obrigatorio'; end if;
  if p_valor_confirmado is not null and p_valor_confirmado < 0 then raise exception 'valor_invalido'; end if;

  update f.gestao_cobranca_os set
    status=case when status='ABERTO' then 'OC_RECEBIDA' else status end,
    pedido_compra_cliente=btrim(p_numero), pedido_recebido_em=coalesce(p_data,current_date),
    valor_confirmado=coalesce(p_valor_confirmado,valor_confirmado),
    valor_origem=case when p_valor_confirmado is not null then 'CONFIRMADO' else valor_origem end,
    updated_at=now(), updated_by=a.fn_current_usuario_id()
  where id=v_gc.id;

  if v_gc.os_id is not null then
    update public.ordens_servico set pedido_compra=btrim(p_numero), atualizado_em=now()
    where id=v_gc.os_id and tenant_id=v_gc.tenant_id and empresa_id=v_gc.empresa_id;
  end if;
end;
$$;

create or replace function f.fn_venda_credito_atualizar(
  p_credito_id uuid,
  p_proximo_contato date default null,
  p_observacao text default null,
  p_responsavel_cliente_nome text default null,
  p_valor_confirmado numeric default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare v_gc f.gestao_cobranca_os%rowtype;
begin
  select * into v_gc from f.gestao_cobranca_os g
  where g.id=p_credito_id and g.tenant_id=public.current_tenant_id()
    and g.empresa_id=public.current_empresa_id() and g.deleted_at is null;
  if not found or not f.has_cobranca_access(v_gc.tenant_id,v_gc.empresa_id) then
    raise exception 'venda_credito_nao_encontrada_ou_sem_acesso';
  end if;
  if p_valor_confirmado is not null and p_valor_confirmado < 0 then raise exception 'valor_invalido'; end if;

  update f.gestao_cobranca_os set
    proximo_contato_date=p_proximo_contato,
    observacao=nullif(btrim(p_observacao),''),
    responsavel_cliente_nome=nullif(btrim(p_responsavel_cliente_nome),''),
    valor_confirmado=p_valor_confirmado,
    valor_origem=case when p_valor_confirmado is not null then 'CONFIRMADO' else valor_origem end,
    updated_at=now(), updated_by=a.fn_current_usuario_id()
  where id=v_gc.id;
end;
$$;

create or replace function f.fn_venda_credito_vincular_documento(
  p_credito_id uuid,
  p_documento_fiscal_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_gc f.gestao_cobranca_os%rowtype;
  v_df f.documento_fiscal%rowtype;
  v_titulo_id uuid;
  v_recebido boolean := false;
begin
  select * into v_gc from f.gestao_cobranca_os g
  where g.id=p_credito_id and g.tenant_id=public.current_tenant_id()
    and g.empresa_id=public.current_empresa_id() and g.deleted_at is null;
  if not found or not f.has_cobranca_access(v_gc.tenant_id,v_gc.empresa_id) then
    raise exception 'venda_credito_nao_encontrada_ou_sem_acesso';
  end if;

  select * into v_df from f.documento_fiscal d
  where d.id=p_documento_fiscal_id and d.tenant_id=v_gc.tenant_id
    and d.empresa_id=v_gc.empresa_id and d.operacao='SAIDA' and d.deleted_at is null;
  if not found then raise exception 'documento_fiscal_invalido'; end if;
  if v_gc.cliente_id is not null and v_df.cliente_id is distinct from v_gc.cliente_id then
    raise exception 'documento_fiscal_cliente_divergente';
  end if;

  select t.id, (t.status='PAGO' or t.valor_aberto<=0)
    into v_titulo_id, v_recebido
  from f.titulo t
  where t.tenant_id=v_gc.tenant_id and t.empresa_id=v_gc.empresa_id
    and t.documento_fiscal_id=v_df.id and t.tipo='AR' and t.deleted_at is null
  order by t.created_at desc limit 1;

  update f.gestao_cobranca_os set
    status=case when coalesce(v_recebido,false) then 'RECEBIDO' else 'FATURADO' end,
    documento_fiscal_id=v_df.id, titulo_ar_id=v_titulo_id,
    faturado_em=coalesce(v_df.emissao_date,current_date),
    valor_confirmado=case when v_df.valor_total>0 then v_df.valor_total else valor_confirmado end,
    valor_origem=case when v_df.valor_total>0 then 'DOCUMENTO' else valor_origem end,
    updated_at=now(), updated_by=a.fn_current_usuario_id()
  where id=v_gc.id;
end;
$$;

create or replace function f.fn_venda_credito_cancelar(p_credito_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare v_gc f.gestao_cobranca_os%rowtype;
begin
  select * into v_gc from f.gestao_cobranca_os g
  where g.id=p_credito_id and g.tenant_id=public.current_tenant_id()
    and g.empresa_id=public.current_empresa_id() and g.deleted_at is null;
  if not found or not f.has_cobranca_access(v_gc.tenant_id,v_gc.empresa_id) then
    raise exception 'venda_credito_nao_encontrada_ou_sem_acesso';
  end if;
  update f.gestao_cobranca_os set status='CANCELADO',updated_at=now(),updated_by=a.fn_current_usuario_id()
  where id=v_gc.id;
end;
$$;

create or replace function f.fn_venda_credito_encerrar(p_credito_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare v_gc f.gestao_cobranca_os%rowtype; v_status text:=upper(coalesce(p_status,''));
begin
  if v_status not in ('PERDIDO','CANCELADO') then raise exception 'status_encerramento_invalido'; end if;
  select * into v_gc from f.gestao_cobranca_os g
  where g.id=p_credito_id and g.tenant_id=public.current_tenant_id()
    and g.empresa_id=public.current_empresa_id() and g.deleted_at is null;
  if not found or not f.has_cobranca_access(v_gc.tenant_id,v_gc.empresa_id) then
    raise exception 'venda_credito_nao_encontrada_ou_sem_acesso';
  end if;
  update f.gestao_cobranca_os set status=v_status,updated_at=now(),updated_by=a.fn_current_usuario_id()
  where id=v_gc.id;
end;
$$;

create or replace function f.fn_venda_credito_excluir(p_credito_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare v_gc f.gestao_cobranca_os%rowtype; v_papel text;
begin
  select * into v_gc from f.gestao_cobranca_os g
  where g.id=p_credito_id and g.tenant_id=public.current_tenant_id()
    and g.empresa_id=public.current_empresa_id() and g.deleted_at is null;
  if not found or not f.has_cobranca_access(v_gc.tenant_id,v_gc.empresa_id) then
    raise exception 'venda_credito_nao_encontrada_ou_sem_acesso';
  end if;
  v_papel := upper(coalesce(a.fn_current_empresa_papel(v_gc.tenant_id,v_gc.empresa_id),''));
  if v_papel not in ('OWNER','ADMIN','DIRETOR') then raise exception 'venda_credito_exclusao_sem_permissao'; end if;
  update f.gestao_cobranca_os set deleted_at=now(),updated_at=now(),updated_by=a.fn_current_usuario_id()
  where id=v_gc.id;
end;
$$;

create or replace function f.fn_venda_credito_criar_avulso(
  p_cliente_id integer,
  p_unidade_id bigint,
  p_descricao text,
  p_valor numeric,
  p_data_competencia date,
  p_origem text default 'AVULSO_LEGADO'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare v_tenant uuid:=public.current_tenant_id(); v_empresa uuid:=public.current_empresa_id(); v_id uuid;
begin
  if not f.has_cobranca_access(v_tenant,v_empresa) then raise exception 'venda_credito_sem_acesso'; end if;
  if p_origem not in ('AVULSO_LEGADO','IMPORTACAO_CSV','OUTRO') then raise exception 'origem_avulsa_invalida'; end if;
  if p_valor is null or p_valor < 0 then raise exception 'valor_invalido'; end if;
  if nullif(btrim(p_descricao),'') is null then raise exception 'descricao_obrigatoria'; end if;
  if not exists (select 1 from public.clientes c where c.id=p_cliente_id and c.tenant_id=v_tenant and c.empresa_id=v_empresa) then
    raise exception 'cliente_invalido';
  end if;
  if p_unidade_id is not null and not exists (
    select 1 from public.cliente_unidades u where u.id=p_unidade_id and u.cliente_id=p_cliente_id
      and u.tenant_id=v_tenant and u.empresa_id=v_empresa
  ) then raise exception 'unidade_invalida'; end if;

  insert into f.gestao_cobranca_os(
    tenant_id,empresa_id,os_id,cliente_id,unidade_id,status,origem,descricao,
    valor_estimado,valor_confirmado,valor_origem,valor_calculado_em,data_competencia
  ) values (
    v_tenant,v_empresa,null,p_cliente_id,p_unidade_id,'ABERTO',p_origem,btrim(p_descricao),
    round(p_valor,2),round(p_valor,2),'MANUAL',now(),coalesce(p_data_competencia,current_date)
  ) returning id into v_id;
  return v_id;
end;
$$;

-- Exposicao calculada e relatorio operacional consumido pela nova pagina.
create or replace view f.v_os_exposicao_valor
with (security_invoker = true)
as
select os.tenant_id, os.empresa_id, os.id as os_id,
       x.valor::numeric(15,2) as valor_estimado, x.origem as valor_origem
from public.ordens_servico os
cross join lateral f.fn_calcular_exposicao_os_unscoped(os.tenant_id,os.empresa_id,os.id) x;

create or replace view r.r_venda_credito
with (security_invoker = true)
as
select
  g.tenant_id,
  g.empresa_id,
  g.id as credito_id,
  g.os_id,
  os.numero_os,
  os.status as os_status,
  os.status_fluxo as os_status_fluxo,
  g.cliente_id,
  c.nome as cliente_nome,
  c.documento,
  c.documento_norm,
  c.documento_raiz,
  coalesce(c.documento_raiz, 'CLIENTE:' || g.cliente_id::text) as grupo_cliente,
  g.unidade_id,
  u.nome as unidade_nome,
  g.status,
  g.origem,
  coalesce(g.descricao, os.descricao_servico) as descricao,
  g.data_competencia,
  g.pedido_compra_cliente,
  g.pedido_recebido_em,
  g.faturado_em,
  g.documento_fiscal_id,
  df.modelo as documento_modelo,
  df.serie as documento_serie,
  df.numero as documento_numero,
  g.titulo_ar_id,
  g.responsavel_id,
  au.nome as responsavel_nome,
  g.responsavel_cliente_nome,
  g.proximo_contato_date,
  g.observacao,
  g.valor_estimado,
  g.valor_confirmado,
  coalesce(g.valor_confirmado,g.valor_estimado,0)::numeric(15,2) as valor_exposicao,
  g.valor_origem,
  g.valor_calculado_em,
  (current_date - coalesce(g.data_competencia,g.created_at::date))::integer as dias_em_aberto,
  g.created_at,
  g.updated_at
from f.gestao_cobranca_os g
left join public.ordens_servico os
  on os.id=g.os_id and os.tenant_id=g.tenant_id and os.empresa_id=g.empresa_id
left join public.clientes c
  on c.id=g.cliente_id and c.tenant_id=g.tenant_id and c.empresa_id=g.empresa_id
left join public.cliente_unidades u
  on u.id=g.unidade_id and u.tenant_id=g.tenant_id and u.empresa_id=g.empresa_id
left join f.documento_fiscal df
  on df.id=g.documento_fiscal_id and df.tenant_id=g.tenant_id and df.empresa_id=g.empresa_id
left join a.usuario au
  on au.id=g.responsavel_id
where g.deleted_at is null;

grant select on f.v_os_exposicao_valor, r.r_venda_credito to authenticated, service_role;

revoke all on function f.fn_venda_credito_recalcular(uuid) from public, anon;
revoke all on function f.fn_venda_credito_registrar_oc(uuid,text,date,numeric) from public, anon;
revoke all on function f.fn_venda_credito_atualizar(uuid,date,text,text,numeric) from public, anon;
revoke all on function f.fn_venda_credito_vincular_documento(uuid,uuid) from public, anon;
revoke all on function f.fn_venda_credito_cancelar(uuid) from public, anon;
revoke all on function f.fn_venda_credito_encerrar(uuid,text) from public, anon;
revoke all on function f.fn_venda_credito_excluir(uuid) from public, anon;
revoke all on function f.fn_venda_credito_criar_avulso(integer,bigint,text,numeric,date,text) from public, anon;

grant execute on function f.fn_venda_credito_recalcular(uuid) to authenticated, service_role;
grant execute on function f.fn_venda_credito_registrar_oc(uuid,text,date,numeric) to authenticated, service_role;
grant execute on function f.fn_venda_credito_atualizar(uuid,date,text,text,numeric) to authenticated, service_role;
grant execute on function f.fn_venda_credito_vincular_documento(uuid,uuid) to authenticated, service_role;
grant execute on function f.fn_venda_credito_cancelar(uuid) to authenticated, service_role;
grant execute on function f.fn_venda_credito_encerrar(uuid,text) to authenticated, service_role;
grant execute on function f.fn_venda_credito_excluir(uuid) to authenticated, service_role;
grant execute on function f.fn_venda_credito_criar_avulso(integer,bigint,text,numeric,date,text) to authenticated, service_role;

-- Calcula as linhas ja existentes e inclui OS concluidas antigas que ainda
-- nao tinham fila. Em seguida sincroniza notas e AR historicos.
do $$
declare r record; v_valor numeric; v_origem text;
begin
  for r in
    select g.id,g.tenant_id,g.empresa_id,g.os_id
    from f.gestao_cobranca_os g
    where g.os_id is not null and g.deleted_at is null
  loop
    select x.valor,x.origem into v_valor,v_origem
    from f.fn_calcular_exposicao_os_unscoped(r.tenant_id,r.empresa_id,r.os_id) x;
    update f.gestao_cobranca_os set
      valor_estimado=coalesce(valor_estimado,v_valor,0),
      valor_origem=coalesce(valor_origem,v_origem),
      valor_calculado_em=coalesce(valor_calculado_em,now())
    where id=r.id;
  end loop;

  for r in
    select os.id
    from public.ordens_servico os
    where os.status='concluida' and os.cliente_id is not null
      and coalesce(os.status_fluxo,'') <> 'faturada'
      and not exists (
        select 1 from f.gestao_cobranca_os g
        where g.tenant_id=os.tenant_id and g.empresa_id=os.empresa_id and g.os_id=os.id
      )
  loop
    perform f.fn_garantir_venda_credito_os(r.id,'OS_CONCLUIDA_SEM_NF');
  end loop;
end;
$$;

with documentos_recentes as (
  select distinct on (df.tenant_id,df.empresa_id,df.os_id_import)
    df.tenant_id,df.empresa_id,df.os_id_import,df.id,df.emissao_date,df.valor_total
  from f.documento_fiscal df
  where df.os_id_import is not null and df.operacao='SAIDA' and df.deleted_at is null
    and coalesce(df.nfe_status,df.nfse_status,'EMITIDA')='EMITIDA'
  order by df.tenant_id,df.empresa_id,df.os_id_import,df.emissao_date desc nulls last,df.created_at desc
)
update f.gestao_cobranca_os g
set documento_fiscal_id=d.id,
    faturado_em=coalesce(d.emissao_date,current_date),
    status=case when g.status in ('RECEBIDO','CANCELADO') then g.status else 'FATURADO' end,
    valor_confirmado=case when d.valor_total>0 then d.valor_total else g.valor_confirmado end,
    valor_origem=case when d.valor_total>0 then 'DOCUMENTO' else g.valor_origem end
from documentos_recentes d
where g.os_id=d.os_id_import and g.tenant_id=d.tenant_id and g.empresa_id=d.empresa_id
  and g.deleted_at is null;

with titulos_recentes as (
  select distinct on (g.id) g.id as credito_id,t.id,t.status,t.valor_aberto
  from f.gestao_cobranca_os g
  join f.titulo t
    on t.tenant_id=g.tenant_id and t.empresa_id=g.empresa_id and t.tipo='AR'
   and t.deleted_at is null
   and (t.documento_fiscal_id=g.documento_fiscal_id or t.os_id=g.os_id)
  where g.deleted_at is null
  order by g.id,t.created_at desc
)
update f.gestao_cobranca_os g
set titulo_ar_id=t.id,
    status=case when t.status='PAGO' or t.valor_aberto<=0 then 'RECEBIDO' else g.status end
from titulos_recentes t
where g.id=t.credito_id;

notify pgrst, 'reload schema';

commit;
