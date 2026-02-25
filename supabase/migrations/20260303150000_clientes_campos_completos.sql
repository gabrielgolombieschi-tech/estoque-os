begin;
-- Clientes: tornar cadastro mais completo + facilitar lookup por CNPJ/CPF (documento_norm).
-- Obs: campos novos são opcionais (nullable) para não quebrar dados existentes.

alter table public.clientes
  add column if not exists razao_social varchar(255),
  add column if not exists nome_fantasia varchar(255),
  add column if not exists inscricao_estadual varchar(30),
  add column if not exists inscricao_municipal varchar(30),
  add column if not exists cep varchar(10),
  add column if not exists logradouro varchar(255),
  add column if not exists numero_endereco varchar(30),
  add column if not exists complemento varchar(120),
  add column if not exists bairro varchar(120),
  add column if not exists cidade varchar(120),
  add column if not exists uf varchar(2),
  add column if not exists pais varchar(60),
  add column if not exists telefone2 varchar(30),
  add column if not exists email_financeiro varchar(120),
  add column if not exists contato_nome varchar(120),
  add column if not exists contato_email varchar(120),
  add column if not exists contato_telefone varchar(30);
-- Colunas derivadas (normalização de CPF/CNPJ) para busca consistente.
alter table public.clientes
  add column if not exists documento_norm text generated always as (public.normalize_doc(documento)) stored,
  add column if not exists documento_key text generated always as (public.fn_documento_key((documento)::text)) stored;
-- Índice para lookup por documento (CPF/CNPJ) por tenant/empresa.
create index if not exists idx_clientes_documento_norm
  on public.clientes (tenant_id, empresa_id, documento_norm)
  where documento_norm is not null;
commit;
notify pgrst, 'reload schema';
