create table if not exists public.imobilizado_itens (
  id bigserial primary key,
  tenant_id uuid not null,
  empresa_id uuid not null,
  status text not null default 'IMPORTADO',
  origem text not null default 'XML_NFE',

  nf_entrada_id bigint not null references public.nf_entrada(id) on delete cascade,
  nf_entrada_item_id bigint not null references public.nf_entrada_itens(id) on delete cascade,
  fornecedor_id bigint references public.fornecedores(id),
  motivo_compra_id uuid,
  solicitante_usuario_id uuid,

  documento_chave text,
  documento_numero text,
  documento_serie text,
  data_emissao date,
  data_entrada timestamptz not null default now(),

  codigo_xml text,
  codigo_fornecedor text,
  codigo_normalizado text,
  descricao text not null,
  unidade text,
  unidade_tributavel text,
  ean text,
  ean_tributavel text,
  ncm text,
  cest text,
  cfop text,
  pedido_xml text,
  pedido_item_xml text,
  informacoes_adicionais text,

  quantidade numeric(18,6) not null default 0,
  valor_unitario numeric(18,6) not null default 0,
  valor_total numeric(18,6) not null default 0,
  v_prod numeric(18,6) not null default 0,
  v_desc numeric(18,6) not null default 0,
  v_frete numeric(18,6) not null default 0,
  v_seguro numeric(18,6) not null default 0,
  v_outro numeric(18,6) not null default 0,
  v_st numeric(18,6) not null default 0,
  v_icms numeric(18,6) not null default 0,
  v_ipi numeric(18,6) not null default 0,
  v_pis numeric(18,6) not null default 0,
  v_cofins numeric(18,6) not null default 0,
  aliq_icms numeric(12,4),
  aliq_ipi numeric(12,4),
  aliq_pis numeric(12,4),
  aliq_cofins numeric(12,4),
  credito_icms numeric(18,6) not null default 0,
  credito_pis numeric(18,6) not null default 0,
  credito_cofins numeric(18,6) not null default 0,
  custo_unitario_bruto numeric(18,6),
  custo_unitario_real numeric(18,6),

  patrimonio_codigo text,
  categoria text,
  subcategoria text,
  marca text,
  modelo text,
  numero_serie text,
  localizacao text,
  responsavel_usuario_id uuid,
  data_inicio_uso date,
  depreciavel boolean not null default true,
  metodo_depreciacao text not null default 'LINEAR',
  vida_util_meses integer,
  valor_residual numeric(18,6) not null default 0,
  centro_custo text,
  conta_contabil text,

  observacoes text,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamptz,

  constraint chk_imobilizado_itens_status check (status in ('IMPORTADO', 'EM_USO', 'MANUTENCAO', 'BAIXADO', 'CANCELADO')),
  constraint chk_imobilizado_itens_origem check (origem in ('XML_NFE', 'MANUAL', 'AJUSTE')),
  constraint chk_imobilizado_itens_quantidade check (quantidade >= 0),
  constraint chk_imobilizado_itens_valores check (
    valor_unitario >= 0
    and valor_total >= 0
    and v_prod >= 0
    and v_desc >= 0
    and v_frete >= 0
    and v_seguro >= 0
    and v_outro >= 0
    and v_st >= 0
    and v_icms >= 0
    and v_ipi >= 0
    and v_pis >= 0
    and v_cofins >= 0
  ),
  constraint chk_imobilizado_itens_vida_util check (vida_util_meses is null or vida_util_meses >= 0)
);

create table if not exists public.consumo_itens (
  id bigserial primary key,
  tenant_id uuid not null,
  empresa_id uuid not null,
  status text not null default 'IMPORTADO',
  origem text not null default 'XML_NFE',

  nf_entrada_id bigint not null references public.nf_entrada(id) on delete cascade,
  nf_entrada_item_id bigint not null references public.nf_entrada_itens(id) on delete cascade,
  fornecedor_id bigint references public.fornecedores(id),
  motivo_compra_id uuid,
  solicitante_usuario_id uuid,

  documento_chave text,
  documento_numero text,
  documento_serie text,
  data_emissao date,
  data_entrada timestamptz not null default now(),

  codigo_xml text,
  codigo_fornecedor text,
  codigo_normalizado text,
  descricao text not null,
  unidade text,
  unidade_tributavel text,
  ean text,
  ean_tributavel text,
  ncm text,
  cest text,
  cfop text,
  pedido_xml text,
  pedido_item_xml text,
  informacoes_adicionais text,

  quantidade numeric(18,6) not null default 0,
  quantidade_consumida numeric(18,6) not null default 0,
  quantidade_disponivel numeric(18,6) not null default 0,
  valor_unitario numeric(18,6) not null default 0,
  valor_total numeric(18,6) not null default 0,
  v_prod numeric(18,6) not null default 0,
  v_desc numeric(18,6) not null default 0,
  v_frete numeric(18,6) not null default 0,
  v_seguro numeric(18,6) not null default 0,
  v_outro numeric(18,6) not null default 0,
  v_st numeric(18,6) not null default 0,
  v_icms numeric(18,6) not null default 0,
  v_ipi numeric(18,6) not null default 0,
  v_pis numeric(18,6) not null default 0,
  v_cofins numeric(18,6) not null default 0,
  aliq_icms numeric(12,4),
  aliq_ipi numeric(12,4),
  aliq_pis numeric(12,4),
  aliq_cofins numeric(12,4),
  credito_icms numeric(18,6) not null default 0,
  credito_pis numeric(18,6) not null default 0,
  credito_cofins numeric(18,6) not null default 0,
  custo_unitario_bruto numeric(18,6),
  custo_unitario_real numeric(18,6),

  categoria text,
  subcategoria text,
  local_uso text,
  centro_custo text,
  responsavel_usuario_id uuid,
  data_consumo date,
  observacoes text,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamptz,

  constraint chk_consumo_itens_status check (status in ('IMPORTADO', 'DISPONIVEL', 'CONSUMIDO', 'CANCELADO')),
  constraint chk_consumo_itens_origem check (origem in ('XML_NFE', 'MANUAL', 'AJUSTE')),
  constraint chk_consumo_itens_quantidades check (
    quantidade >= 0
    and quantidade_consumida >= 0
    and quantidade_disponivel >= 0
    and quantidade_consumida <= quantidade
    and quantidade_disponivel <= quantidade
  ),
  constraint chk_consumo_itens_valores check (
    valor_unitario >= 0
    and valor_total >= 0
    and v_prod >= 0
    and v_desc >= 0
    and v_frete >= 0
    and v_seguro >= 0
    and v_outro >= 0
    and v_st >= 0
    and v_icms >= 0
    and v_ipi >= 0
    and v_pis >= 0
    and v_cofins >= 0
  )
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'uq_imobilizado_itens_nf_item'
      and conrelid = 'public.imobilizado_itens'::regclass
  ) then
    alter table public.imobilizado_itens
      add constraint uq_imobilizado_itens_nf_item unique (tenant_id, empresa_id, nf_entrada_item_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'uq_consumo_itens_nf_item'
      and conrelid = 'public.consumo_itens'::regclass
  ) then
    alter table public.consumo_itens
      add constraint uq_consumo_itens_nf_item unique (tenant_id, empresa_id, nf_entrada_item_id);
  end if;
end;
$$;

create index if not exists idx_imobilizado_itens_tenant_empresa_nf
  on public.imobilizado_itens (tenant_id, empresa_id, nf_entrada_id);

create index if not exists idx_imobilizado_itens_tenant_empresa_status
  on public.imobilizado_itens (tenant_id, empresa_id, status)
  where deleted_at is null;

create index if not exists idx_consumo_itens_tenant_empresa_nf
  on public.consumo_itens (tenant_id, empresa_id, nf_entrada_id);

create index if not exists idx_consumo_itens_tenant_empresa_status
  on public.consumo_itens (tenant_id, empresa_id, status)
  where deleted_at is null;

do $$
begin
  if to_regprocedure('public.set_updated_at()') is not null then
    drop trigger if exists trg_imobilizado_itens_updated_at on public.imobilizado_itens;
    create trigger trg_imobilizado_itens_updated_at
    before update on public.imobilizado_itens
    for each row execute function public.set_updated_at();

    drop trigger if exists trg_consumo_itens_updated_at on public.consumo_itens;
    create trigger trg_consumo_itens_updated_at
    before update on public.consumo_itens
    for each row execute function public.set_updated_at();
  end if;
end;
$$;

alter table public.imobilizado_itens enable row level security;
alter table public.consumo_itens enable row level security;

drop policy if exists tenant_empresa_select_imobilizado_itens on public.imobilizado_itens;
drop policy if exists tenant_empresa_insert_imobilizado_itens on public.imobilizado_itens;
drop policy if exists tenant_empresa_update_imobilizado_itens on public.imobilizado_itens;
drop policy if exists tenant_empresa_delete_imobilizado_itens on public.imobilizado_itens;

create policy tenant_empresa_select_imobilizado_itens on public.imobilizado_itens
  for select to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

create policy tenant_empresa_insert_imobilizado_itens on public.imobilizado_itens
  for insert to authenticated
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

create policy tenant_empresa_update_imobilizado_itens on public.imobilizado_itens
  for update to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id())
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

create policy tenant_empresa_delete_imobilizado_itens on public.imobilizado_itens
  for delete to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

drop policy if exists tenant_empresa_select_consumo_itens on public.consumo_itens;
drop policy if exists tenant_empresa_insert_consumo_itens on public.consumo_itens;
drop policy if exists tenant_empresa_update_consumo_itens on public.consumo_itens;
drop policy if exists tenant_empresa_delete_consumo_itens on public.consumo_itens;

create policy tenant_empresa_select_consumo_itens on public.consumo_itens
  for select to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

create policy tenant_empresa_insert_consumo_itens on public.consumo_itens
  for insert to authenticated
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

create policy tenant_empresa_update_consumo_itens on public.consumo_itens
  for update to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id())
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

create policy tenant_empresa_delete_consumo_itens on public.consumo_itens
  for delete to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id());

grant select, insert, update, delete on public.imobilizado_itens to authenticated;
grant select, insert, update, delete on public.consumo_itens to authenticated;
grant usage, select on sequence public.imobilizado_itens_id_seq to authenticated;
grant usage, select on sequence public.consumo_itens_id_seq to authenticated;

comment on table public.imobilizado_itens is
  'Cadastro documental de itens importados como imobilizado. Nao substitui public.itens e mantem rastreabilidade da NF.';

comment on table public.consumo_itens is
  'Cadastro documental de itens importados como consumo. Nao substitui public.itens e mantem rastreabilidade da NF.';

insert into public.imobilizado_itens (
  tenant_id, empresa_id, nf_entrada_id, nf_entrada_item_id, fornecedor_id, motivo_compra_id, solicitante_usuario_id,
  documento_chave, documento_numero, documento_serie, data_emissao,
  codigo_xml, codigo_fornecedor, codigo_normalizado, descricao, ncm, cfop,
  quantidade, valor_unitario, valor_total, v_prod, v_icms, v_ipi, v_pis, v_cofins,
  aliq_icms, aliq_ipi, aliq_pis, aliq_cofins, payload_json
)
select
  nf.tenant_id, nf.empresa_id, nf.id, nfi.id, nf.fornecedor_id, nf.motivo_compra_id, nf.solicitante_usuario_id,
  nf.chave, nf.numero, nf.serie, nf.data_emissao::date,
  nfi.codigo_fornecedor, nfi.codigo_fornecedor,
  case
    when nfi.codigo_fornecedor ~ '^[0-9]+$' then coalesce(nullif(ltrim(nfi.codigo_fornecedor, '0'), ''), '0')
    else upper(btrim(coalesce(nfi.codigo_fornecedor, '')))
  end,
  coalesce(nullif(nfi.descricao, ''), nfi.codigo_fornecedor, 'Item imobilizado'),
  nfi.ncm, nfi.cfop,
  coalesce(nfi.qtd, 0), coalesce(nfi.v_unit, 0), coalesce(nfi.v_prod, 0), coalesce(nfi.v_prod, 0),
  coalesce(nfi.v_icms, 0), coalesce(nfi.v_ipi, 0), coalesce(nfi.v_pis, 0), coalesce(nfi.v_cofins, 0),
  nfi.aliq_icms, nfi.aliq_ipi, nfi.aliq_pis, nfi.aliq_cofins,
  jsonb_build_object('backfill', true)
from public.nf_entrada nf
join public.nf_entrada_itens nfi
  on nfi.nf_entrada_id = nf.id
 and nfi.tenant_id = nf.tenant_id
 and nfi.empresa_id = nf.empresa_id
where nf.finalidade_contexto = 'imobilizado'::public.item_finalidade
  and nf.deleted_at is null
  and not exists (
    select 1
    from public.imobilizado_itens ii
    where ii.tenant_id = nf.tenant_id
      and ii.empresa_id = nf.empresa_id
      and ii.nf_entrada_item_id = nfi.id
      and ii.deleted_at is null
  );

insert into public.consumo_itens (
  tenant_id, empresa_id, nf_entrada_id, nf_entrada_item_id, fornecedor_id, motivo_compra_id, solicitante_usuario_id,
  documento_chave, documento_numero, documento_serie, data_emissao,
  codigo_xml, codigo_fornecedor, codigo_normalizado, descricao, ncm, cfop,
  quantidade, quantidade_disponivel, valor_unitario, valor_total, v_prod, v_icms, v_ipi, v_pis, v_cofins,
  aliq_icms, aliq_ipi, aliq_pis, aliq_cofins, payload_json
)
select
  nf.tenant_id, nf.empresa_id, nf.id, nfi.id, nf.fornecedor_id, nf.motivo_compra_id, nf.solicitante_usuario_id,
  nf.chave, nf.numero, nf.serie, nf.data_emissao::date,
  nfi.codigo_fornecedor, nfi.codigo_fornecedor,
  case
    when nfi.codigo_fornecedor ~ '^[0-9]+$' then coalesce(nullif(ltrim(nfi.codigo_fornecedor, '0'), ''), '0')
    else upper(btrim(coalesce(nfi.codigo_fornecedor, '')))
  end,
  coalesce(nullif(nfi.descricao, ''), nfi.codigo_fornecedor, 'Item de consumo'),
  nfi.ncm, nfi.cfop,
  coalesce(nfi.qtd, 0), coalesce(nfi.qtd, 0), coalesce(nfi.v_unit, 0), coalesce(nfi.v_prod, 0), coalesce(nfi.v_prod, 0),
  coalesce(nfi.v_icms, 0), coalesce(nfi.v_ipi, 0), coalesce(nfi.v_pis, 0), coalesce(nfi.v_cofins, 0),
  nfi.aliq_icms, nfi.aliq_ipi, nfi.aliq_pis, nfi.aliq_cofins,
  jsonb_build_object('backfill', true)
from public.nf_entrada nf
join public.nf_entrada_itens nfi
  on nfi.nf_entrada_id = nf.id
 and nfi.tenant_id = nf.tenant_id
 and nfi.empresa_id = nf.empresa_id
where nf.finalidade_contexto = 'consumo'::public.item_finalidade
  and nf.deleted_at is null
  and not exists (
    select 1
    from public.consumo_itens ci
    where ci.tenant_id = nf.tenant_id
      and ci.empresa_id = nf.empresa_id
      and ci.nf_entrada_item_id = nfi.id
      and ci.deleted_at is null
  );

notify pgrst, 'reload schema';
