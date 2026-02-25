begin;
-- Clientes: garantir cadastro mais completo + permitir upsert confiável por documento (CPF/CNPJ).
-- Esta migration é idempotente (IF NOT EXISTS) para rodar em bases já em produção.

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
-- Se houver duplicidade por documento (no mesmo tenant/empresa), mantemos o menor id e
-- desativamos os demais (limpando documento) para permitir criação do índice único.
with dup_groups as (
  select tenant_id, empresa_id, documento_norm, min(id) as keep_id
  from public.clientes
  where documento_norm is not null
  group by tenant_id, empresa_id, documento_norm
  having count(*) > 1
), victims as (
  select c.id
  from public.clientes c
  join dup_groups d
    on d.tenant_id = c.tenant_id
   and d.empresa_id = c.empresa_id
   and d.documento_norm = c.documento_norm
  where c.id <> d.keep_id
)
update public.clientes c
set documento = null,
    ativo = false,
    atualizado_em = now()
where c.id in (select id from victims);
-- Índice para lookup rápido.
create index if not exists idx_clientes_documento_norm
  on public.clientes (tenant_id, empresa_id, documento_norm)
  where documento_norm is not null;
-- Índice ÚNICO para permitir upsert por documento (CPF/CNPJ) no mesmo tenant/empresa.
create unique index if not exists clientes_tenant_empresa_documento_norm_uidx
  on public.clientes (tenant_id, empresa_id, documento_norm)
  where documento_norm is not null;
commit;
notify pgrst, 'reload schema';
