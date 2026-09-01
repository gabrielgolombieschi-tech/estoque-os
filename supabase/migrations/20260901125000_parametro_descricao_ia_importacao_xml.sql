-- Aprendizado humano do agente de cadastro durante a importacao de XML.
-- A memoria e deliberadamente restrita a descricao: grupo, fiscal e demais
-- atributos continuam dependendo das regras e confirmacoes proprias.

create table if not exists public.parametro_importacao_xml_descricao_ia (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  descricao_origem text not null,
  descricao_origem_normalizada text not null,
  descricao_sugerida_ia text,
  descricao_corrigida text not null,
  codigo_item text,
  corrigido_por_auth uuid,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint parametro_importacao_xml_descricao_ia_origem_ck
    check (btrim(descricao_origem) <> ''),
  constraint parametro_importacao_xml_descricao_ia_origem_norm_ck
    check (btrim(descricao_origem_normalizada) <> ''),
  constraint parametro_importacao_xml_descricao_ia_corrigida_ck
    check (btrim(descricao_corrigida) <> ''),
  constraint parametro_importacao_xml_descricao_ia_empresa_escopo_fk
    foreign key (tenant_id, empresa_id)
    references c.empresa (tenant_id, id),
  constraint parametro_importacao_xml_descricao_ia_corrigido_por_fk
    foreign key (corrigido_por_auth)
    references auth.users (id)
    on delete set null,
  constraint parametro_importacao_xml_descricao_ia_escopo_origem_uq
    unique (tenant_id, empresa_id, descricao_origem_normalizada)
);

comment on table public.parametro_importacao_xml_descricao_ia is
  'Exemplos de descricao de XML corrigidos por pessoa usuaria para orientar sugestoes futuras do agente de cadastro.';
comment on column public.parametro_importacao_xml_descricao_ia.descricao_origem_normalizada is
  'Chave deterministica sem acentos e pontuacao usada somente para reconhecer a mesma descricao de origem.';
comment on column public.parametro_importacao_xml_descricao_ia.descricao_corrigida is
  'Descricao final aprovada pela pessoa usuaria. Nao parametriza grupo, NCM ou qualquer dado fiscal.';

create index if not exists idx_parametro_importacao_xml_descricao_ia_recentes
  on public.parametro_importacao_xml_descricao_ia (tenant_id, empresa_id, updated_at desc)
  where ativo and deleted_at is null;

drop trigger if exists trg_parametro_importacao_xml_descricao_ia_updated_at
  on public.parametro_importacao_xml_descricao_ia;
create trigger trg_parametro_importacao_xml_descricao_ia_updated_at
before update on public.parametro_importacao_xml_descricao_ia
for each row execute function public.set_updated_at();

alter table public.parametro_importacao_xml_descricao_ia enable row level security;

drop policy if exists parametro_importacao_xml_descricao_ia_select
  on public.parametro_importacao_xml_descricao_ia;
create policy parametro_importacao_xml_descricao_ia_select
on public.parametro_importacao_xml_descricao_ia
for select to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and public.can('cad_itens', 'write')
);

revoke all on table public.parametro_importacao_xml_descricao_ia from anon, authenticated;
grant select on table public.parametro_importacao_xml_descricao_ia to authenticated;
grant all on table public.parametro_importacao_xml_descricao_ia to service_role;
