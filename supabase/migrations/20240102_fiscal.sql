-- Fiscal e custo real - criaÃ§Ã£o de tabelas e colunas complementares
-- Idempotente para reexecuÃ§Ã£o segura
begin;
-- FunÃ§Ã£o utilitÃ¡ria para atualizar updated_at
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;
-- Tabela de perfil fiscal por item (1:1)
create table if not exists public.fiscal_itens (
  id bigserial primary key,
  item_id bigint not null references public.itens(id) on delete cascade,
  ncm text,
  cst_icms text,
  cst_ipi text,
  cst_pis text,
  cst_cofins text,
  aliquota_icms numeric(12,4),
  aliquota_ipi numeric(12,4),
  aliquota_pis numeric(12,4),
  aliquota_cofins numeric(12,4),
  credita_icms boolean not null default false,
  credita_ipi boolean not null default false,
  ipi_entra_no_custo boolean not null default true,
  credita_pis boolean not null default false,
  credita_cofins boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fiscal_itens_item_id_key'
  ) then
    alter table public.fiscal_itens add constraint fiscal_itens_item_id_key unique (item_id);
  end if;
end$$;
-- Trigger updated_at para fiscal_itens
do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'trg_fiscal_itens_updated_at'
  ) then
    create trigger trg_fiscal_itens_updated_at
    before update on public.fiscal_itens
    for each row
    execute function public.set_updated_at();
  end if;
end$$;
-- CabeÃ§alho da NF de entrada
create table if not exists public.nf_entrada (
  id bigserial primary key,
  chave text not null,
  numero text,
  serie text,
  modelo text,
  emitente_nome text,
  emitente_cnpj text,
  fornecedor_id bigint references public.fornecedores(id),
  data_emissao timestamptz,
  valor_produtos numeric(18,6),
  valor_frete numeric(18,6),
  valor_seguro numeric(18,6),
  valor_desconto numeric(18,6),
  valor_outros numeric(18,6),
  valor_total numeric(18,6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Constrangimento de nÃ£o nulo/Ãºnico para chave
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='nf_entrada' and column_name='chave') then
    update public.nf_entrada set chave = '' where chave is null;
    alter table public.nf_entrada alter column chave set not null;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'nf_entrada_chave_key'
  ) then
    alter table public.nf_entrada add constraint nf_entrada_chave_key unique (chave);
  end if;
end$$;
-- Trigger updated_at para nf_entrada
do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'trg_nf_entrada_updated_at'
  ) then
    create trigger trg_nf_entrada_updated_at
    before update on public.nf_entrada
    for each row
    execute function public.set_updated_at();
  end if;
end$$;
-- Itens da NF com tributos
create table if not exists public.nf_entrada_itens (
  id bigserial primary key,
  nf_entrada_id bigint not null references public.nf_entrada(id) on delete cascade,
  item_id bigint references public.itens(id),
  codigo_produto text not null,
  descricao_produto text,
  ncm text,
  quantidade numeric(18,6) not null,
  valor_unitario numeric(18,6) not null,
  valor_total numeric(18,6) not null,
  aliquota_icms numeric(12,4),
  aliquota_ipi numeric(12,4),
  aliquota_pis numeric(12,4),
  aliquota_cofins numeric(12,4),
  v_icms numeric(18,6),
  v_ipi numeric(18,6),
  v_pis numeric(18,6),
  v_cofins numeric(18,6),
  v_st numeric(18,6),
  v_frete numeric(18,6),
  v_seguro numeric(18,6),
  v_desconto numeric(18,6),
  v_outros numeric(18,6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Trigger updated_at para nf_entrada_itens
do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'trg_nf_entrada_itens_updated_at'
  ) then
    create trigger trg_nf_entrada_itens_updated_at
    before update on public.nf_entrada_itens
    for each row
    execute function public.set_updated_at();
  end if;
end$$;
-- Novas colunas em movimentacoes para custo real/creditos e rastreio da NF
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='custo_unitario_bruto') then
    alter table public.movimentacoes add column custo_unitario_bruto numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='custo_unitario_real') then
    alter table public.movimentacoes add column custo_unitario_real numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='v_ipi') then
    alter table public.movimentacoes add column v_ipi numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='v_icms') then
    alter table public.movimentacoes add column v_icms numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='v_pis') then
    alter table public.movimentacoes add column v_pis numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='v_cofins') then
    alter table public.movimentacoes add column v_cofins numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='v_frete_rateado') then
    alter table public.movimentacoes add column v_frete_rateado numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='credito_icms') then
    alter table public.movimentacoes add column credito_icms numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='credito_pis') then
    alter table public.movimentacoes add column credito_pis numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='credito_cofins') then
    alter table public.movimentacoes add column credito_cofins numeric(18,6);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='origem_nf_entrada_id') then
    alter table public.movimentacoes add column origem_nf_entrada_id bigint references public.nf_entrada(id);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='movimentacoes' and column_name='created_at') then
    alter table public.movimentacoes add column created_at timestamptz not null default now();
  end if;
end$$;
-- Ãndices
create index if not exists idx_nf_entrada_data_emissao on public.nf_entrada(data_emissao);
create index if not exists idx_nf_entrada_itens_item on public.nf_entrada_itens(item_id);
create index if not exists idx_mov_origem_nf on public.movimentacoes(origem_nf_entrada_id);
create index if not exists idx_mov_created_at on public.movimentacoes(created_at);
commit;
