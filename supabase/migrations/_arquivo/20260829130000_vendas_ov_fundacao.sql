-- Modulo Vendas (OV): discriminador, numeracao, acoes e isolamento basico.
-- As OVs continuam fisicamente em public.ordens_servico para preservar estoque,
-- compras, documentos fiscais e o vinculo historico com orcamentos.

alter table public.ordens_servico
  add column if not exists tipo_documento text,
  add column if not exists codigo text,
  add column if not exists numero_doc integer;

update public.ordens_servico
set tipo_documento = 'OS'
where tipo_documento is null;

update public.ordens_servico
set codigo = 'OS ' || coalesce(nullif(btrim(numero_os), ''), os_num::text, id::text)
where codigo is null;

alter table public.ordens_servico
  alter column tipo_documento set default 'OS',
  alter column tipo_documento set not null,
  alter column codigo set not null;

alter table public.ordens_servico
  drop constraint if exists ordens_servico_tipo_documento_check;

alter table public.ordens_servico
  add constraint ordens_servico_tipo_documento_check
  check (tipo_documento in ('OS', 'OV'));

alter table public.ordens_servico
  drop constraint if exists chk_ordens_servico_status_fluxo;

alter table public.ordens_servico
  add constraint chk_ordens_servico_status_fluxo
  check (
    status_fluxo is null
    or status_fluxo in (
      'em_andamento', 'concluida', 'faturada',
      'em_andamento_garantia', 'concluida_garantia', 'cancelada'
    )
  );

create table if not exists m.venda_seq (
  tenant_id uuid not null,
  empresa_id uuid not null,
  proximo_numero integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint venda_seq_pkey primary key (tenant_id, empresa_id),
  constraint venda_seq_proximo_numero_check check (proximo_numero > 0)
);

alter table m.venda_seq enable row level security;

create or replace function m.venda_next_numero(p_tenant uuid, p_empresa uuid)
returns integer
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_next integer;
begin
  if p_tenant is null or p_empresa is null then
    raise exception 'Tenant e empresa sao obrigatorios para numerar a venda.';
  end if;

  insert into m.venda_seq (tenant_id, empresa_id, proximo_numero)
  values (p_tenant, p_empresa, 1)
  on conflict (tenant_id, empresa_id) do nothing;

  update m.venda_seq as sequencia
     set proximo_numero = sequencia.proximo_numero + 1,
         updated_at = now()
   where sequencia.tenant_id = p_tenant
     and sequencia.empresa_id = p_empresa
  returning sequencia.proximo_numero - 1 into v_next;

  return coalesce(v_next, 1);
end;
$$;

create or replace function m.venda_build_codigo(
  p_empresa_id uuid,
  p_numero integer,
  p_emissao_date date
)
returns text
language sql
stable
security definer
set search_path to 'm', 'public', 'c'
as $$
  select 'OV-' || upper(trim(coalesce(empresa.codigo, 'SEMEMP')))
         || '-' || lpad(greatest(p_numero, 1)::text, 5, '0')
         || '-' || lpad(((extract(year from coalesce(p_emissao_date, current_date))::int) % 1000)::text, 3, '0')
  from c.empresa as empresa
  where empresa.id = p_empresa_id;
$$;

create or replace function public.fn_ordens_servico_documento_defaults()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm'
as $$
begin
  new.tipo_documento := upper(coalesce(nullif(btrim(new.tipo_documento), ''), 'OS'));

  if new.tipo_documento not in ('OS', 'OV') then
    raise exception 'Tipo de documento invalido: %', new.tipo_documento;
  end if;

  if new.tipo_documento = 'OV' then
    new.tem_gestao := false;
    new.usa_relatorio_hh := false;

    if new.numero_doc is null then
      new.numero_doc := m.venda_next_numero(new.tenant_id, new.empresa_id);
    end if;

    if nullif(btrim(new.codigo), '') is null
       or (tg_op = 'UPDATE' and old.tipo_documento is distinct from new.tipo_documento) then
      new.codigo := m.venda_build_codigo(
        new.empresa_id,
        new.numero_doc,
        coalesce(new.data_abertura::date, current_date)
      );
    end if;
  else
    if nullif(btrim(new.codigo), '') is null
       or (tg_op = 'UPDATE' and old.tipo_documento is distinct from new.tipo_documento) then
      new.codigo := 'OS ' || coalesce(nullif(btrim(new.numero_os), ''), new.os_num::text, new.id::text);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ordens_servico_documento_defaults on public.ordens_servico;
create trigger trg_ordens_servico_documento_defaults
before insert or update of tipo_documento, codigo, numero_doc, tem_gestao, usa_relatorio_hh
on public.ordens_servico
for each row execute function public.fn_ordens_servico_documento_defaults();

create unique index if not exists ordens_servico_codigo_tenant_empresa_uk
  on public.ordens_servico (tenant_id, empresa_id, codigo);

create unique index if not exists ordens_servico_ov_numero_doc_uk
  on public.ordens_servico (tenant_id, empresa_id, numero_doc)
  where tipo_documento = 'OV';

create index if not exists ordens_servico_tipo_status_idx
  on public.ordens_servico (tenant_id, empresa_id, tipo_documento, status_fluxo, data_abertura desc);

comment on column public.ordens_servico.tipo_documento is
  'Discriminador do documento comercial: OS para ordem de servico e OV para ordem de venda.';
comment on column public.ordens_servico.codigo is
  'Codigo visivel do documento. OVs usam OV-{EMPRESA}-{NUMERO}-{ANO}; OS preservam a numeracao tecnica.';
comment on column public.ordens_servico.numero_doc is
  'Numero sequencial da OV dentro do tenant e da empresa.';

-- PAINEL_TV e estritamente operacional e nao pode enxergar OVs.
drop policy if exists ordens_servico_select_painel_tv on public.ordens_servico;
create policy ordens_servico_select_painel_tv
on public.ordens_servico
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and tipo_documento = 'OS'
  and exists (
    select 1
    from a.usuario as usuario
    join a.usuario_empresa as usuario_empresa
      on usuario_empresa.usuario_id = usuario.id
    where usuario.auth_user_id = auth.uid()
      and usuario.deleted_at is null
      and usuario_empresa.deleted_at is null
      and usuario_empresa.ativo = true
      and usuario_empresa.empresa_id = public.current_empresa_id()
      and usuario_empresa.papel = 'PAINEL_TV'
  )
);

create or replace function m.venda_cancelar(p_venda_id integer, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'auth'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_status text;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if not (public.can('os_rpcs', 'execute') or public.has_permission('os.write')) then
    raise exception 'Sem permissao para cancelar a venda.';
  end if;

  if nullif(btrim(p_motivo), '') is null then
    raise exception 'Informe o motivo do cancelamento.';
  end if;

  select venda.status_fluxo
    into v_status
  from public.ordens_servico as venda
  where venda.id = p_venda_id
    and venda.tenant_id = v_tenant_id
    and venda.empresa_id = v_empresa_id
    and venda.tipo_documento = 'OV'
  for update;

  if not found then
    raise exception 'Venda nao encontrada na empresa atual.';
  end if;
  if v_status in ('faturada', 'cancelada') then
    raise exception 'Venda faturada ou ja cancelada nao pode ser cancelada.';
  end if;

  update public.ordens_servico
     set status = 'cancelada',
         status_fluxo = 'cancelada',
         observacoes = concat_ws(' | ', nullif(observacoes, ''), 'Cancelamento: ' || btrim(p_motivo)),
         atualizado_em = now()
   where id = p_venda_id
     and tenant_id = v_tenant_id
     and empresa_id = v_empresa_id;

  insert into public.ordens_servico_fluxo_eventos (
    tenant_id, empresa_id, os_id, evento, status_origem, status_destino, motivo, realizado_por
  ) values (
    v_tenant_id, v_empresa_id, p_venda_id, 'cancelar_venda', v_status, 'cancelada', btrim(p_motivo), auth.uid()
  );

  return jsonb_build_object('sucesso', true);
end;
$$;

create or replace function m.venda_converter_em_os(p_venda_id integer, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'auth'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_codigo_origem text;
  v_status text;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if not (public.can('os_rpcs', 'execute') or public.has_permission('os.write')) then
    raise exception 'Sem permissao para converter a venda.';
  end if;

  select venda.codigo, venda.status_fluxo
    into v_codigo_origem, v_status
  from public.ordens_servico as venda
  where venda.id = p_venda_id
    and venda.tenant_id = v_tenant_id
    and venda.empresa_id = v_empresa_id
    and venda.tipo_documento = 'OV'
  for update;

  if not found then
    raise exception 'Venda nao encontrada na empresa atual.';
  end if;
  if coalesce(v_status, 'em_andamento') <> 'em_andamento' then
    raise exception 'Somente uma venda em andamento pode ser convertida em OS.';
  end if;
  if exists (
    select 1 from public.apontamentos_horas as horas
    where horas.os_id = p_venda_id
      and horas.tenant_id = v_tenant_id
      and horas.empresa_id = v_empresa_id
  ) or exists (
    select 1 from public.hh_lancamentos as hh
    where hh.os_id = p_venda_id
      and hh.tenant_id = v_tenant_id
      and hh.empresa_id = v_empresa_id
  ) then
    raise exception 'A venda possui lancamentos de horas e nao pode ser convertida automaticamente.';
  end if;

  update public.ordens_servico
     set tipo_documento = 'OS',
         codigo = null,
         numero_doc = null,
         atualizado_em = now()
   where id = p_venda_id
     and tenant_id = v_tenant_id
     and empresa_id = v_empresa_id;

  insert into public.ordens_servico_fluxo_eventos (
    tenant_id, empresa_id, os_id, evento, status_origem, status_destino, motivo, realizado_por
  ) values (
    v_tenant_id,
    v_empresa_id,
    p_venda_id,
    'converter_ov_em_os',
    'OV',
    'OS',
    concat_ws(' | ', 'Origem ' || v_codigo_origem, nullif(btrim(p_motivo), '')),
    auth.uid()
  );

  return jsonb_build_object('sucesso', true, 'os_id', p_venda_id);
end;
$$;

create or replace function m.venda_vincular_documento_fiscal(
  p_venda_id integer,
  p_documento_fiscal_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'f', 'auth'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if auth.uid() is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if not (
    public.can('os_rpcs', 'execute')
    or public.has_permission('os.write')
    or public.can('financeiro', 'write')
    or public.has_permission('financeiro.write')
  ) then
    raise exception 'Sem permissao para vincular documento fiscal a venda.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico as venda
    where venda.id = p_venda_id
      and venda.tenant_id = v_tenant_id
      and venda.empresa_id = v_empresa_id
      and venda.tipo_documento = 'OV'
  ) then
    raise exception 'Venda nao encontrada na empresa atual.';
  end if;

  update f.documento_fiscal as documento
     set os_id_import = p_venda_id,
         updated_at = now()
   where documento.id = p_documento_fiscal_id
     and documento.tenant_id = v_tenant_id
     and documento.empresa_id = v_empresa_id
     and documento.operacao = 'SAIDA'
     and documento.deleted_at is null
     and (documento.os_id_import is null or documento.os_id_import = p_venda_id);

  if not found then
    raise exception 'Documento fiscal de saida indisponivel ou ja vinculado a outro documento.';
  end if;

  insert into public.ordens_servico_fluxo_eventos (
    tenant_id, empresa_id, os_id, evento, status_origem, status_destino, motivo, realizado_por
  ) values (
    v_tenant_id, v_empresa_id, p_venda_id, 'vincular_documento_fiscal', null, null,
    'Documento fiscal ' || p_documento_fiscal_id::text, auth.uid()
  );

  return jsonb_build_object('sucesso', true);
end;
$$;

create or replace view r.r_vendas_ov_divergencias
with (security_invoker = true)
as
select
  venda.tenant_id,
  venda.empresa_id,
  venda.id as venda_id,
  venda.codigo,
  venda.cliente_id,
  venda.status_fluxo,
  (venda.cliente_id is null) as sem_cliente,
  coalesce(venda.tem_gestao, false) as tem_gestao,
  coalesce(venda.usa_relatorio_hh, false) as usa_relatorio_hh,
  exists (
    select 1 from public.os_gestao_itens as gestao
    where gestao.tenant_id = venda.tenant_id
      and gestao.empresa_id = venda.empresa_id
      and gestao.os_id = venda.id
  ) as possui_gestao,
  exists (
    select 1 from public.apontamentos_horas as horas
    where horas.tenant_id = venda.tenant_id
      and horas.empresa_id = venda.empresa_id
      and horas.os_id = venda.id
  ) or exists (
    select 1 from public.hh_lancamentos as hh
    where hh.tenant_id = venda.tenant_id
      and hh.empresa_id = venda.empresa_id
      and hh.os_id = venda.id
  ) as possui_horas
from public.ordens_servico as venda
where venda.tipo_documento = 'OV'
  and (
    venda.cliente_id is null
    or coalesce(venda.tem_gestao, false)
    or coalesce(venda.usa_relatorio_hh, false)
    or exists (
      select 1 from public.os_gestao_itens as gestao
      where gestao.tenant_id = venda.tenant_id
        and gestao.empresa_id = venda.empresa_id
        and gestao.os_id = venda.id
    )
    or exists (
      select 1 from public.apontamentos_horas as horas
      where horas.tenant_id = venda.tenant_id
        and horas.empresa_id = venda.empresa_id
        and horas.os_id = venda.id
    )
    or exists (
      select 1 from public.hh_lancamentos as hh
      where hh.tenant_id = venda.tenant_id
        and hh.empresa_id = venda.empresa_id
        and hh.os_id = venda.id
    )
  );

revoke all on table m.venda_seq from anon, authenticated;
grant select, insert, update, delete on table m.venda_seq to service_role;

revoke all on function m.venda_next_numero(uuid, uuid) from public, anon;
grant execute on function m.venda_next_numero(uuid, uuid) to authenticated, service_role;
revoke all on function m.venda_build_codigo(uuid, integer, date) from public, anon;
grant execute on function m.venda_build_codigo(uuid, integer, date) to authenticated, service_role;

revoke all on function m.venda_cancelar(integer, text) from public, anon;
grant execute on function m.venda_cancelar(integer, text) to authenticated, service_role;
revoke all on function m.venda_converter_em_os(integer, text) from public, anon;
grant execute on function m.venda_converter_em_os(integer, text) to authenticated, service_role;
revoke all on function m.venda_vincular_documento_fiscal(integer, uuid) from public, anon;
grant execute on function m.venda_vincular_documento_fiscal(integer, uuid) to authenticated, service_role;

grant select on r.r_vendas_ov_divergencias to authenticated, service_role;
