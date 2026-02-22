
-- Modulo Compras > Pedidos

create or replace function c.has_compras_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path to 'c', 'public', 'a'
set row_security to 'off'
as $$
  with me as (
    select coalesce(nullif(auth.jwt() ->> 'sub','')::uuid, auth.uid()) as auth_user_id
  )
  select
    me.auth_user_id is not null
    and (
      exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        where u.auth_user_id = me.auth_user_id
          and ut.tenant_id = p_tenant
          and ut.ativo = true
          and ut.deleted_at is null
          and ut.papel in ('OWNER','ADMIN','GESTOR')
          and u.deleted_at is null
      )
      or exists (
        select 1
        from a.usuario u
        join a.usuario_empresa ue on ue.usuario_id = u.id
        join c.empresa e on e.id = ue.empresa_id
        where u.auth_user_id = me.auth_user_id
          and ue.empresa_id = p_empresa
          and ue.ativo = true
          and ue.deleted_at is null
          and ue.papel in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS')
          and e.deleted_at is null
          and e.tenant_id = p_tenant
          and u.deleted_at is null
      )
    )
  from me;
$$;

grant execute on function c.has_compras_access(uuid, uuid) to authenticated, service_role;

create or replace function public.can(p_resource text, p_action text, p_tenant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'a', 'c'
as $$
declare
  v_auth_user_id uuid;
  v_usuario_id uuid;
  v_papel_tenant text;
  v_papel_empresa text;
  v_empresa_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then return false; end if;

  select u.id into v_usuario_id
  from a.usuario u
  where u.auth_user_id = v_auth_user_id
    and u.ativo = true
    and u.deleted_at is null
  limit 1;
  if v_usuario_id is null then return false; end if;

  select ut.papel into v_papel_tenant
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  order by ut.updated_at desc nulls last, ut.created_at desc nulls last
  limit 1;
  if v_papel_tenant is null then return false; end if;

  if v_papel_tenant in ('ADMIN','OWNER') then return true; end if;

  v_empresa_id := public.current_empresa_id();
  if v_empresa_id is not null then
    select ue.papel into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

  if p_resource = 'xml_import' and p_action = 'execute' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'nf_entrada' and p_action = 'import' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'financeiro' and p_action in ('write', 'config') then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'estoque' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'estoque' and p_action = 'read' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;

  if p_resource = 'compras' and p_action = 'read' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS') then return true; end if;
  end if;
  if p_resource = 'compras' and p_action = 'write' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then return true; end if;
  end if;
  if p_resource = 'compras' and p_action = 'approve' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO') then return true; end if;
  end if;
  if p_resource = 'compras' and p_action = 'receive' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then return true; end if;
  end if;

  if p_resource = 'admin' and p_action = 'manage_users' then return false; end if;
  return false;
end;
$$;

create table if not exists m.compra_pendencia (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  status text not null default 'PENDENTE' check (status in ('PENDENTE','EM_PEDIDO','CONCLUIDO','CANCELADO')),
  fornecedor_id int null,
  origem_tipo text not null check (origem_tipo in ('OS','ESTOQUE','OUTROS')),
  origem_os_id int null,
  item_id int null,
  item_nome text null,
  unidade text null,
  quantidade numeric(15,3) not null check (quantidade > 0),
  prioridade text not null default 'MEDIA' check (prioridade in ('BAIXA','MEDIA','ALTA','URGENTE')),
  necessario_em date null,
  observacoes text null,
  estoque_meta text null check (estoque_meta in ('MIN','IDEAL','MAX')),
  estoque_atual_qtd numeric(15,3) null,
  estoque_em_compra_qtd numeric(15,3) null,
  estoque_alvo_qtd numeric(15,3) null,
  estoque_sugestao_qtd numeric(15,3) null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid null default a.fn_current_usuario_id(),
  updated_by uuid null,
  deleted_at timestamptz null,
  cancel_reason text null,
  concluido_em timestamptz null,
  constraint fk_compra_pendencia__fornecedor_id__fornecedores foreign key (tenant_id, empresa_id, fornecedor_id) references public.fornecedores(tenant_id, empresa_id, id),
  constraint fk_compra_pendencia__origem_os_id__ordens_servico foreign key (tenant_id, empresa_id, origem_os_id) references public.ordens_servico(tenant_id, empresa_id, id),
  constraint fk_compra_pendencia__item_id__itens foreign key (tenant_id, empresa_id, item_id) references public.itens(tenant_id, empresa_id, id)
);

create index if not exists idx_compra_pendencia__tenant_empresa_status on m.compra_pendencia(tenant_id, empresa_id, status);
create index if not exists idx_compra_pendencia__tenant_empresa_fornecedor_status on m.compra_pendencia(tenant_id, empresa_id, fornecedor_id, status);
create index if not exists idx_compra_pendencia__tenant_empresa_item_status on m.compra_pendencia(tenant_id, empresa_id, item_id, status);
create unique index if not exists uq_compra_pendencia__reposicao_aberta
  on m.compra_pendencia(tenant_id, empresa_id, fornecedor_id, item_id)
  where deleted_at is null and origem_tipo='ESTOQUE' and status in ('PENDENTE','EM_PEDIDO');

create table if not exists m.pedido_compra_seq (
  tenant_id uuid not null,
  empresa_id uuid not null,
  proximo_numero int not null default 1 check (proximo_numero >= 1),
  updated_at timestamptz not null default now(),
  constraint pk_m_pedido_compra_seq primary key (tenant_id, empresa_id)
);

create table if not exists m.pedido_compra (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  numero int not null check (numero >= 1),
  codigo text not null,
  status text not null default 'RASCUNHO' check (status in ('RASCUNHO','AGUARDANDO_APROVACAO','APROVADO','REPROVADO','ENVIADO','PARCIAL_RECEBIDO','RECEBIDO','CANCELADO')),
  fornecedor_id int not null,
  emissao_date date not null default current_date,
  previsao_entrega_date date null,
  observacoes text null,
  total_itens numeric(15,2) not null default 0,
  total_frete numeric(15,2) not null default 0,
  total_desconto numeric(15,2) not null default 0,
  total_geral numeric(15,2) not null default 0,
  cancel_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid null default a.fn_current_usuario_id(),
  updated_by uuid null,
  deleted_at timestamptz null,
  constraint fk_pedido_compra__fornecedor_id__fornecedores foreign key (tenant_id, empresa_id, fornecedor_id) references public.fornecedores(tenant_id, empresa_id, id)
);

create unique index if not exists uq_pedido_compra__tenant_empresa_numero on m.pedido_compra(tenant_id, empresa_id, numero) where deleted_at is null;
create unique index if not exists uq_pedido_compra__tenant_empresa_codigo on m.pedido_compra(tenant_id, empresa_id, codigo) where deleted_at is null;
create index if not exists idx_pedido_compra__tenant_empresa_status on m.pedido_compra(tenant_id, empresa_id, status);

create table if not exists m.pedido_compra_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  pedido_compra_id uuid not null references m.pedido_compra(id) on delete cascade,
  seq int not null check (seq >= 1),
  item_id int null,
  item_codigo text null,
  item_nome text not null,
  unidade text not null,
  quantidade numeric(15,3) not null check (quantidade > 0),
  quantidade_recebida numeric(15,3) not null default 0 check (quantidade_recebida >= 0 and quantidade_recebida <= quantidade),
  valor_unitario numeric(15,4) not null default 0 check (valor_unitario >= 0),
  valor_total numeric(15,2) not null default 0 check (valor_total >= 0),
  observacoes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid null default a.fn_current_usuario_id(),
  updated_by uuid null,
  deleted_at timestamptz null,
  constraint fk_pedido_compra_item__item_id__itens foreign key (tenant_id, empresa_id, item_id) references public.itens(tenant_id, empresa_id, id)
);

create unique index if not exists uq_pedido_compra_item__tenant_empresa_pedido_seq on m.pedido_compra_item(tenant_id, empresa_id, pedido_compra_id, seq) where deleted_at is null;

create table if not exists m.pedido_compra_item_origem (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  pedido_compra_item_id uuid not null references m.pedido_compra_item(id) on delete cascade,
  pendencia_id uuid not null references m.compra_pendencia(id),
  quantidade numeric(15,3) not null check (quantidade > 0),
  created_at timestamptz not null default now(),
  created_by uuid null default a.fn_current_usuario_id(),
  deleted_at timestamptz null
);

create unique index if not exists uq_pedido_compra_item_origem__item_pendencia on m.pedido_compra_item_origem(pedido_compra_item_id, pendencia_id) where deleted_at is null;

create table if not exists m.pedido_compra_evento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  pedido_compra_id uuid not null references m.pedido_compra(id) on delete cascade,
  tipo text not null check (tipo in ('STATUS','APROVACAO','RECEBIMENTO','OBS')),
  status_de text null,
  status_para text null,
  mensagem text null,
  created_at timestamptz not null default now(),
  created_by uuid null default a.fn_current_usuario_id()
);

create table if not exists m.pedido_compra_recebimento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  pedido_compra_id uuid not null references m.pedido_compra(id),
  recebimento_date date not null default current_date,
  documento_ref text null,
  observacoes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid null default a.fn_current_usuario_id(),
  updated_by uuid null,
  deleted_at timestamptz null
);

create table if not exists m.pedido_compra_recebimento_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  recebimento_id uuid not null references m.pedido_compra_recebimento(id) on delete cascade,
  pedido_compra_item_id uuid not null references m.pedido_compra_item(id),
  item_id int null,
  quantidade numeric(15,3) not null check (quantidade > 0),
  created_at timestamptz not null default now(),
  created_by uuid null default a.fn_current_usuario_id(),
  deleted_at timestamptz null,
  constraint fk_pedido_compra_recebimento_item__item_id__itens foreign key (tenant_id, empresa_id, item_id) references public.itens(tenant_id, empresa_id, id)
);

create or replace function m.pedido_compra_next_numero(p_tenant uuid, p_empresa uuid)
returns int
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare v_next int;
begin
  insert into m.pedido_compra_seq(tenant_id, empresa_id, proximo_numero)
  values (p_tenant, p_empresa, 1)
  on conflict (tenant_id, empresa_id) do nothing;

  update m.pedido_compra_seq s
     set proximo_numero = s.proximo_numero + 1,
         updated_at = now()
   where s.tenant_id = p_tenant
     and s.empresa_id = p_empresa
  returning s.proximo_numero - 1 into v_next;
  return coalesce(v_next, 1);
end;
$$;

create or replace function m.pedido_compra_build_codigo(p_empresa_id uuid, p_numero int, p_emissao_date date)
returns text
language sql
stable
security definer
set search_path to 'm', 'public', 'c'
as $$
  select 'PC-' || upper(trim(coalesce(e.codigo, 'SEMEMP')))
         || '-' || lpad(greatest(p_numero,1)::text, 5, '0')
         || '-' || lpad(((extract(year from coalesce(p_emissao_date, current_date))::int) % 1000)::text, 3, '0')
  from c.empresa e where e.id = p_empresa_id;
$$;

create or replace function m.fn_pedido_compra_recalcular_totais(p_pedido_id uuid)
returns void
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare v_total numeric(15,2);
begin
  select coalesce(sum(i.valor_total),0) into v_total
  from m.pedido_compra_item i
  where i.pedido_compra_id = p_pedido_id and i.deleted_at is null;

  update m.pedido_compra p
     set total_itens = v_total,
         total_geral = round(v_total + coalesce(p.total_frete,0) - coalesce(p.total_desconto,0), 2)
   where p.id = p_pedido_id;
end;
$$;

create or replace function m.trg_compra_pendencia_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
begin
  if new.item_id is null and new.item_nome is not null then
    new.item_nome := upper(trim(new.item_nome));
  end if;

  if new.origem_tipo = 'OS' and new.origem_os_id is null then
    raise exception 'origem_os_id obrigatorio quando origem_tipo=OS';
  end if;
  if new.origem_tipo = 'ESTOQUE' and new.estoque_meta is null then
    raise exception 'estoque_meta obrigatorio quando origem_tipo=ESTOQUE';
  end if;
  return new;
end;
$$;

create or replace function m.trg_pedido_compra_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
begin
  if tg_op = 'INSERT' then
    if new.numero is null or new.numero <= 0 then
      new.numero := m.pedido_compra_next_numero(new.tenant_id, new.empresa_id);
    end if;
    if new.codigo is null or btrim(new.codigo) = '' then
      new.codigo := m.pedido_compra_build_codigo(new.empresa_id, new.numero, new.emissao_date);
    end if;
  end if;
  new.status := upper(trim(coalesce(new.status, 'RASCUNHO')));
  return new;
end;
$$;

create or replace function m.trg_pedido_compra_item_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
begin
  if tg_op = 'INSERT' and (new.seq is null or new.seq <= 0) then
    select coalesce(max(i.seq), 0) + 1 into new.seq
    from m.pedido_compra_item i
    where i.pedido_compra_id = new.pedido_compra_id and i.deleted_at is null;
  end if;

  if new.item_id is not null then
    select i.codigo_interno, upper(trim(coalesce(i.nome, i.descricao, new.item_nome))), coalesce(nullif(trim(i.unidade_medida),''), new.unidade, 'UN')
      into new.item_codigo, new.item_nome, new.unidade
    from public.itens i
    where i.tenant_id = new.tenant_id
      and i.empresa_id = new.empresa_id
      and i.id = new.item_id
    limit 1;
  else
    new.item_nome := upper(trim(coalesce(new.item_nome, '')));
    new.unidade := coalesce(nullif(trim(new.unidade),''), 'UN');
  end if;

  new.valor_total := round(coalesce(new.quantidade,0) * coalesce(new.valor_unitario,0), 2);
  return new;
end;
$$;

create or replace function m.trg_pedido_compra_item_aiud()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
begin
  perform m.fn_pedido_compra_recalcular_totais(coalesce(new.pedido_compra_id, old.pedido_compra_id));
  return coalesce(new, old);
end;
$$;

create or replace function m.fn_pedido_compra_log_evento(p_pedido_id uuid, p_tipo text, p_status_de text, p_status_para text, p_mensagem text)
returns void
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare v_tenant uuid; v_empresa uuid;
begin
  select p.tenant_id, p.empresa_id into v_tenant, v_empresa from m.pedido_compra p where p.id = p_pedido_id;
  if v_tenant is null then return; end if;
  insert into m.pedido_compra_evento(tenant_id, empresa_id, pedido_compra_id, tipo, status_de, status_para, mensagem)
  values (v_tenant, v_empresa, p_pedido_id, p_tipo, p_status_de, p_status_para, p_mensagem);
end;
$$;

create or replace function m.fn_pedido_compra_gerar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_fornecedor_id int,
  p_pendencia_ids uuid[],
  p_observacoes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare v_pedido_id uuid;
begin
  if not public.can('compras','write', p_tenant_id) then
    raise exception 'Sem permissao para gerar pedido';
  end if;
  insert into m.pedido_compra(tenant_id, empresa_id, fornecedor_id, observacoes, status, emissao_date)
  values (p_tenant_id, p_empresa_id, p_fornecedor_id, p_observacoes, 'RASCUNHO', current_date)
  returning id into v_pedido_id;

  with src as (
    select cp.*
    from m.compra_pendencia cp
    where cp.tenant_id = p_tenant_id
      and cp.empresa_id = p_empresa_id
      and cp.deleted_at is null
      and cp.status = 'PENDENTE'
      and cp.id = any(p_pendencia_ids)
  ), grp as (
    select item_id, upper(trim(coalesce(item_nome,'ITEM'))) as item_nome, coalesce(nullif(trim(unidade),''), 'UN') as unidade, sum(quantidade)::numeric(15,3) as quantidade
    from src
    group by item_id, upper(trim(coalesce(item_nome,'ITEM'))), coalesce(nullif(trim(unidade),''), 'UN')
  ), ins as (
    insert into m.pedido_compra_item(tenant_id, empresa_id, pedido_compra_id, item_id, item_nome, unidade, quantidade, valor_unitario)
    select p_tenant_id, p_empresa_id, v_pedido_id, g.item_id, g.item_nome, g.unidade, g.quantidade, 0
    from grp g
    returning id, item_id, item_nome, unidade
  )
  insert into m.pedido_compra_item_origem(tenant_id, empresa_id, pedido_compra_item_id, pendencia_id, quantidade)
  select p_tenant_id, p_empresa_id, i.id, cp.id, cp.quantidade
  from m.compra_pendencia cp
  join ins i on coalesce(i.item_id, -1) = coalesce(cp.item_id, -1)
            and upper(trim(i.item_nome)) = upper(trim(coalesce(cp.item_nome, i.item_nome)))
            and upper(trim(i.unidade)) = upper(trim(coalesce(cp.unidade, i.unidade)))
  where cp.id = any(p_pendencia_ids);

  update m.compra_pendencia cp
     set status = 'EM_PEDIDO', updated_by = a.fn_current_usuario_id()
   where cp.id = any(p_pendencia_ids)
     and cp.status = 'PENDENTE'
     and cp.deleted_at is null;

  perform m.fn_pedido_compra_log_evento(v_pedido_id, 'STATUS', null, 'RASCUNHO', 'Pedido gerado por pendencias');
  return v_pedido_id;
end;
$$;

create or replace function m.fn_pedido_compra_transicionar(p_pedido_id uuid, p_status_para text, p_mensagem text default null)
returns void
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare v_pedido m.pedido_compra%rowtype; v_new text;
begin
  select * into v_pedido from m.pedido_compra p where p.id = p_pedido_id and p.deleted_at is null for update;
  if not found then raise exception 'Pedido nao encontrado'; end if;
  v_new := upper(trim(coalesce(p_status_para,'')));
  if v_new in ('APROVADO','REPROVADO') and not public.can('compras','approve', v_pedido.tenant_id) then raise exception 'Sem permissao para aprovar/reprovar'; end if;
  if v_new in ('PARCIAL_RECEBIDO','RECEBIDO') and not public.can('compras','receive', v_pedido.tenant_id) then raise exception 'Sem permissao para receber'; end if;
  if v_new not in ('APROVADO','REPROVADO','PARCIAL_RECEBIDO','RECEBIDO') and not public.can('compras','write', v_pedido.tenant_id) then raise exception 'Sem permissao para alterar pedido'; end if;

  update m.pedido_compra p set status = v_new, cancel_reason = case when v_new='CANCELADO' then p_mensagem else p.cancel_reason end, updated_by = a.fn_current_usuario_id() where p.id = p_pedido_id;
  perform m.fn_pedido_compra_log_evento(p_pedido_id, case when v_new in ('APROVADO','REPROVADO') then 'APROVACAO' else 'STATUS' end, v_pedido.status, v_new, p_mensagem);
end;
$$;

create or replace function m.fn_pedido_compra_receber(p_pedido_id uuid, p_recebimento_date date, p_documento_ref text, p_observacoes text, p_itens jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_pedido m.pedido_compra%rowtype;
  v_recebimento_id uuid;
  v_item jsonb;
  v_item_id uuid;
  v_qtd numeric(15,3);
  v_row m.pedido_compra_item%rowtype;
  v_all_received boolean;
  v_email text;
begin
  select * into v_pedido from m.pedido_compra p where p.id = p_pedido_id and p.deleted_at is null for update;
  if not found then raise exception 'Pedido nao encontrado'; end if;
  if not public.can('compras','receive', v_pedido.tenant_id) then raise exception 'Sem permissao para recebimento'; end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then raise exception 'Itens obrigatorios'; end if;

  insert into m.pedido_compra_recebimento(tenant_id, empresa_id, pedido_compra_id, recebimento_date, documento_ref, observacoes)
  values (v_pedido.tenant_id, v_pedido.empresa_id, v_pedido.id, coalesce(p_recebimento_date,current_date), p_documento_ref, p_observacoes)
  returning id into v_recebimento_id;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    v_item_id := nullif(v_item->>'pedidoItemId','')::uuid;
    v_qtd := coalesce((v_item->>'quantidade')::numeric,0);
    if v_item_id is null or v_qtd <= 0 then raise exception 'Item invalido no recebimento'; end if;

    select * into v_row from m.pedido_compra_item i where i.id = v_item_id and i.pedido_compra_id = v_pedido.id and i.deleted_at is null for update;
    if not found then raise exception 'Pedido item nao encontrado'; end if;
    if v_row.quantidade_recebida + v_qtd > v_row.quantidade then raise exception 'Quantidade excede saldo'; end if;

    insert into m.pedido_compra_recebimento_item(tenant_id, empresa_id, recebimento_id, pedido_compra_item_id, item_id, quantidade)
    values (v_pedido.tenant_id, v_pedido.empresa_id, v_recebimento_id, v_row.id, v_row.item_id, v_qtd);

    update m.pedido_compra_item set quantidade_recebida = quantidade_recebida + v_qtd, updated_by = a.fn_current_usuario_id() where id = v_row.id;

    if v_row.item_id is not null and exists (
      select 1 from public.itens it where it.tenant_id=v_pedido.tenant_id and it.empresa_id=v_pedido.empresa_id and it.id=v_row.item_id and coalesce(it.controla_estoque,false)=true
    ) then
      v_email := coalesce(current_setting('request.jwt.claim.email', true), 'sistema');
      insert into public.movimentacoes(tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao)
      values (v_pedido.tenant_id, v_pedido.empresa_id, v_row.item_id, 'entrada', v_qtd, 'RECEBIMENTO '||v_pedido.codigo, v_email, coalesce(p_recebimento_date,current_date)::timestamp);
    end if;
  end loop;

  select bool_and(i.quantidade_recebida >= i.quantidade) into v_all_received from m.pedido_compra_item i where i.pedido_compra_id = v_pedido.id and i.deleted_at is null;
  update m.pedido_compra set status = case when coalesce(v_all_received,false) then 'RECEBIDO' else 'PARCIAL_RECEBIDO' end, updated_by = a.fn_current_usuario_id() where id = v_pedido.id;
  perform m.fn_pedido_compra_log_evento(v_pedido.id, 'RECEBIMENTO', v_pedido.status, case when coalesce(v_all_received,false) then 'RECEBIDO' else 'PARCIAL_RECEBIDO' end, coalesce(p_observacoes, 'Recebimento'));

  update m.compra_pendencia cp
     set status='CONCLUIDO', concluido_em=now(), updated_by=a.fn_current_usuario_id()
   where cp.deleted_at is null and cp.status='EM_PEDIDO'
     and exists (
       select 1 from m.pedido_compra_item_origem io join m.pedido_compra_item pi on pi.id = io.pedido_compra_item_id
       where io.deleted_at is null and io.pendencia_id = cp.id and pi.pedido_compra_id = v_pedido.id and pi.deleted_at is null and pi.quantidade_recebida >= pi.quantidade
     );

  return v_recebimento_id;
end;
$$;

grant execute on function m.pedido_compra_next_numero(uuid, uuid) to authenticated, service_role;
grant execute on function m.pedido_compra_build_codigo(uuid, int, date) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_recalcular_totais(uuid) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_log_evento(uuid, text, text, text, text) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_gerar(uuid, uuid, int, uuid[], text) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_transicionar(uuid, text, text) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_receber(uuid, date, text, text, jsonb) to authenticated, service_role;

create trigger trg_compra_pendencia_biu before insert or update on m.compra_pendencia for each row execute function m.trg_compra_pendencia_biu();
create trigger trg_compra_pendencia_set_updated_at before update on m.compra_pendencia for each row execute function a.fn_set_updated_at();
create trigger trg_compra_pendencia_audit after insert or update or delete on m.compra_pendencia for each row execute function public.audit_trigger();

create trigger trg_pedido_compra_biu before insert or update on m.pedido_compra for each row execute function m.trg_pedido_compra_biu();
create trigger trg_pedido_compra_set_updated_at before update on m.pedido_compra for each row execute function a.fn_set_updated_at();
create trigger trg_pedido_compra_audit after insert or update or delete on m.pedido_compra for each row execute function public.audit_trigger();

create trigger trg_pedido_compra_item_biu before insert or update on m.pedido_compra_item for each row execute function m.trg_pedido_compra_item_biu();
create trigger trg_pedido_compra_item_aiud after insert or update or delete on m.pedido_compra_item for each row execute function m.trg_pedido_compra_item_aiud();
create trigger trg_pedido_compra_item_set_updated_at before update on m.pedido_compra_item for each row execute function a.fn_set_updated_at();
create trigger trg_pedido_compra_item_audit after insert or update or delete on m.pedido_compra_item for each row execute function public.audit_trigger();

create trigger trg_pedido_compra_item_origem_audit after insert or update or delete on m.pedido_compra_item_origem for each row execute function public.audit_trigger();
create trigger trg_pedido_compra_evento_audit after insert or update or delete on m.pedido_compra_evento for each row execute function public.audit_trigger();
create trigger trg_pedido_compra_recebimento_set_updated_at before update on m.pedido_compra_recebimento for each row execute function a.fn_set_updated_at();
create trigger trg_pedido_compra_recebimento_audit after insert or update or delete on m.pedido_compra_recebimento for each row execute function public.audit_trigger();
create trigger trg_pedido_compra_receb_item_audit after insert or update or delete on m.pedido_compra_recebimento_item for each row execute function public.audit_trigger();

alter table m.compra_pendencia enable row level security;
alter table m.pedido_compra_seq enable row level security;
alter table m.pedido_compra enable row level security;
alter table m.pedido_compra_item enable row level security;
alter table m.pedido_compra_item_origem enable row level security;
alter table m.pedido_compra_evento enable row level security;
alter table m.pedido_compra_recebimento enable row level security;
alter table m.pedido_compra_recebimento_item enable row level security;

create policy compra_pendencia_select on m.compra_pendencia for select to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy compra_pendencia_insert on m.compra_pendencia for insert to authenticated with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy compra_pendencia_update on m.compra_pendencia for update to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

create policy pedido_compra_seq_all on m.pedido_compra_seq for all to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id)) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

create policy pedido_compra_select on m.pedido_compra for select to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_insert on m.pedido_compra for insert to authenticated with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_update on m.pedido_compra for update to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

create policy pedido_compra_item_select on m.pedido_compra_item for select to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_item_insert on m.pedido_compra_item for insert to authenticated with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_item_update on m.pedido_compra_item for update to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

create policy pedido_compra_item_origem_select on m.pedido_compra_item_origem for select to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_item_origem_insert on m.pedido_compra_item_origem for insert to authenticated with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_item_origem_update on m.pedido_compra_item_origem for update to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

create policy pedido_compra_evento_all on m.pedido_compra_evento for all to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id)) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

create policy pedido_compra_recebimento_select on m.pedido_compra_recebimento for select to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_recebimento_insert on m.pedido_compra_recebimento for insert to authenticated with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_recebimento_update on m.pedido_compra_recebimento for update to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

create policy pedido_compra_receb_item_select on m.pedido_compra_recebimento_item for select to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_receb_item_insert on m.pedido_compra_recebimento_item for insert to authenticated with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null);
create policy pedido_compra_receb_item_update on m.pedido_compra_recebimento_item for update to authenticated using (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id) and deleted_at is null) with check (tenant_id=current_tenant_id() and empresa_id=current_empresa_id() and c.has_compras_access(tenant_id, empresa_id));

grant select, insert, update, delete on m.compra_pendencia to authenticated, service_role;
grant select, insert, update, delete on m.pedido_compra_seq to authenticated, service_role;
grant select, insert, update, delete on m.pedido_compra to authenticated, service_role;
grant select, insert, update, delete on m.pedido_compra_item to authenticated, service_role;
grant select, insert, update, delete on m.pedido_compra_item_origem to authenticated, service_role;
grant select, insert, update, delete on m.pedido_compra_evento to authenticated, service_role;
grant select, insert, update, delete on m.pedido_compra_recebimento to authenticated, service_role;
grant select, insert, update, delete on m.pedido_compra_recebimento_item to authenticated, service_role;

create or replace view r.r_compra_fornecedores_pendentes as
select
  cp.tenant_id,
  cp.empresa_id,
  cp.fornecedor_id,
  coalesce(f.nome, 'SEM FORNECEDOR') as fornecedor_nome,
  count(*) filter (where cp.status = 'PENDENTE') as qtd_pendencias_abertas,
  coalesce(sum(cp.quantidade) filter (where cp.status = 'PENDENTE'), 0)::numeric(15,3) as qtd_total_pendente,
  count(distinct coalesce(cp.item_id::text, cp.item_nome, cp.id::text)) filter (where cp.status = 'PENDENTE') as qtd_itens_distintos,
  min(cp.necessario_em) filter (where cp.status = 'PENDENTE') as data_mais_urgente
from m.compra_pendencia cp
left join public.fornecedores f on f.tenant_id=cp.tenant_id and f.empresa_id=cp.empresa_id and f.id=cp.fornecedor_id
where cp.deleted_at is null
group by cp.tenant_id, cp.empresa_id, cp.fornecedor_id, coalesce(f.nome, 'SEM FORNECEDOR');

create or replace view r.r_compra_pendencias_detalhadas as
select
  cp.id as pendencia_id,
  cp.tenant_id,
  cp.empresa_id,
  cp.fornecedor_id,
  coalesce(f.nome, 'SEM FORNECEDOR') as fornecedor_nome,
  cp.status,
  cp.origem_tipo,
  cp.origem_os_id,
  os.os_num,
  os.numero_os,
  cp.item_id,
  i.codigo_interno as item_codigo,
  coalesce(cp.item_nome, i.nome, i.descricao) as item_nome,
  coalesce(cp.unidade, i.unidade_medida, 'UN') as unidade,
  cp.quantidade,
  cp.prioridade,
  cp.necessario_em,
  cp.observacoes,
  cp.estoque_meta,
  cp.estoque_atual_qtd,
  cp.estoque_em_compra_qtd,
  cp.estoque_alvo_qtd,
  cp.estoque_sugestao_qtd
from m.compra_pendencia cp
left join public.fornecedores f on f.tenant_id=cp.tenant_id and f.empresa_id=cp.empresa_id and f.id=cp.fornecedor_id
left join public.ordens_servico os on os.tenant_id=cp.tenant_id and os.empresa_id=cp.empresa_id and os.id=cp.origem_os_id
left join public.itens i on i.tenant_id=cp.tenant_id and i.empresa_id=cp.empresa_id and i.id=cp.item_id
where cp.deleted_at is null;

create or replace view r.r_compra_pendencias_agrupadas_item as
with pend as (
  select
    cp.id,
    cp.tenant_id,
    cp.empresa_id,
    cp.fornecedor_id,
    cp.origem_tipo,
    cp.origem_os_id,
    cp.item_id,
    upper(trim(coalesce(cp.item_nome, i.nome, i.descricao, 'ITEM SEM NOME'))) as item_nome,
    coalesce(nullif(trim(cp.unidade),''), nullif(trim(i.unidade_medida),''), 'UN') as unidade,
    cp.quantidade,
    cp.estoque_meta,
    cp.created_at,
    os.os_num,
    os.numero_os
  from m.compra_pendencia cp
  left join public.itens i on i.tenant_id=cp.tenant_id and i.empresa_id=cp.empresa_id and i.id=cp.item_id
  left join public.ordens_servico os on os.tenant_id=cp.tenant_id and os.empresa_id=cp.empresa_id and os.id=cp.origem_os_id
  where cp.deleted_at is null and cp.status='PENDENTE'
), em_compra as (
  select p.tenant_id, p.empresa_id, i.item_id, sum(greatest(i.quantidade - i.quantidade_recebida, 0))::numeric(15,3) as qtd_em_compra_aberto
  from m.pedido_compra_item i
  join m.pedido_compra p on p.id = i.pedido_compra_id
  where p.deleted_at is null and i.deleted_at is null and p.status in ('RASCUNHO','AGUARDANDO_APROVACAO','APROVADO','ENVIADO','PARCIAL_RECEBIDO')
  group by p.tenant_id, p.empresa_id, i.item_id
)
select
  p.tenant_id,
  p.empresa_id,
  p.fornecedor_id,
  coalesce(f.nome, 'SEM FORNECEDOR') as fornecedor_nome,
  p.item_id,
  i.codigo_interno as item_codigo,
  p.item_nome,
  p.unidade,
  coalesce(sum(p.quantidade) filter (where p.origem_tipo='OS'),0)::numeric(15,3) as qtd_os_total,
  coalesce(sum(p.quantidade) filter (where p.origem_tipo in ('OUTROS','ESTOQUE')),0)::numeric(15,3) as qtd_outros_total,
  coalesce(e.quantidade_atual,0)::numeric(15,3) as qtd_estoque_atual,
  coalesce(ec.qtd_em_compra_aberto,0)::numeric(15,3) as qtd_em_compra_aberto,
  greatest(0, coalesce(i.estoque_minimo,0)::numeric - (coalesce(e.quantidade_atual,0)+coalesce(ec.qtd_em_compra_aberto,0)))::numeric(15,3) as sugestao_min,
  greatest(0, coalesce(i.estoque_ideal,0)::numeric - (coalesce(e.quantidade_atual,0)+coalesce(ec.qtd_em_compra_aberto,0)))::numeric(15,3) as sugestao_ideal,
  greatest(0, coalesce(i.estoque_maximo,0)::numeric - (coalesce(e.quantidade_atual,0)+coalesce(ec.qtd_em_compra_aberto,0)))::numeric(15,3) as sugestao_max,
  (array_agg(p.id order by p.created_at asc) filter (where p.origem_tipo='ESTOQUE'))[1] as estoque_pendencia_id,
  max(p.estoque_meta) filter (where p.origem_tipo='ESTOQUE') as estoque_meta_atual,
  coalesce(sum(p.quantidade) filter (where p.origem_tipo='ESTOQUE'),0)::numeric(15,3) as qtd_estoque_pendencia,
  coalesce(jsonb_agg(jsonb_build_object('pendencia_id', p.id, 'os_id', p.origem_os_id, 'os_num', p.os_num, 'numero_os', p.numero_os, 'quantidade', p.quantidade) order by p.created_at asc) filter (where p.origem_tipo='OS'), '[]'::jsonb) as os_breakdown
from pend p
left join public.fornecedores f on f.tenant_id=p.tenant_id and f.empresa_id=p.empresa_id and f.id=p.fornecedor_id
left join public.itens i on i.tenant_id=p.tenant_id and i.empresa_id=p.empresa_id and i.id=p.item_id
left join public.estoque e on e.tenant_id=p.tenant_id and e.empresa_id=p.empresa_id and e.item_id=p.item_id
left join em_compra ec on ec.tenant_id=p.tenant_id and ec.empresa_id=p.empresa_id and ec.item_id=p.item_id
group by p.tenant_id,p.empresa_id,p.fornecedor_id,coalesce(f.nome,'SEM FORNECEDOR'),p.item_id,i.codigo_interno,p.item_nome,p.unidade,e.quantidade_atual,ec.qtd_em_compra_aberto,i.estoque_minimo,i.estoque_ideal,i.estoque_maximo;

grant select on r.r_compra_fornecedores_pendentes to authenticated, service_role;
grant select on r.r_compra_pendencias_detalhadas to authenticated, service_role;
grant select on r.r_compra_pendencias_agrupadas_item to authenticated, service_role;
