begin;

alter table f.documento_fiscal
  add column origem text not null default 'IMPORTADO'
    check (origem in ('IMPORTADO', 'EMITIDO'));

create table f.perfil_operacao (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid,
  codigo text not null,
  nome text not null,
  modelo text not null check (modelo in ('NFE', 'NFSE')),
  natureza_texto text not null,
  crt text check (crt in ('1', '2', '3')),
  cfop_interno text,
  cfop_externo text,
  item_servico text,
  nbs text,
  cst_icms text,
  csosn text,
  cst_ipi text,
  cst_pis text,
  cst_cofins text,
  exige_referencia boolean not null default false,
  exige_motivo boolean not null default false,
  observacao text,
  vigencia_inicio date not null default current_date,
  vigencia_fim date,
  created_at timestamptz not null default now(),
  unique (tenant_id, empresa_id, codigo, vigencia_inicio)
);

create table f.solicitacao_faturamento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  cliente_id uuid,
  perfil_operacao_id uuid references f.perfil_operacao(id),
  status text not null default 'RASCUNHO'
    check (status in ('RASCUNHO', 'PREVIA', 'APROVADA', 'EMITIDA', 'CANCELADA')),
  pedido_cliente text,
  condicao_pagamento text,
  observacao text,
  criado_por uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table f.solicitacao_item (
  id uuid primary key default gen_random_uuid(),
  solicitacao_id uuid not null references f.solicitacao_faturamento(id) on delete cascade,
  tenant_id uuid not null default public.current_tenant_id(),
  origem_tipo text not null check (origem_tipo in ('OS', 'OV', 'AVULSO', 'CONTRATO')),
  origem_id uuid,
  origem_item_id uuid,
  pedido_linha text,
  item_id uuid,
  descricao text not null,
  ncm text,
  cfop text,
  cst_icms text,
  quantidade numeric not null,
  unidade text,
  valor_unitario numeric not null,
  ordem int not null default 1
);

create table f.documento_fiscal_emissao (
  documento_fiscal_id uuid primary key references f.documento_fiscal(id),
  solicitacao_id uuid references f.solicitacao_faturamento(id),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  referencia_externa text not null,
  provedor text not null default 'focus_nfe',
  ambiente text not null check (ambiente in ('HOMOLOGACAO', 'PRODUCAO')),
  status text not null default 'RASCUNHO'
    check (status in (
      'RASCUNHO', 'ENVIANDO', 'PROCESSANDO', 'AUTORIZADA',
      'REJEITADA', 'CANCELADA', 'ERRO'
    )),
  chave_acesso text,
  protocolo text,
  numero int,
  serie int,
  codigo_status int,
  mensagem text,
  payload_enviado jsonb,
  resposta jsonb,
  xml_path text,
  danfe_path text,
  enviado_em timestamptz,
  autorizado_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, empresa_id, referencia_externa)
);

create table f.documento_fiscal_evento (
  id uuid primary key default gen_random_uuid(),
  documento_fiscal_id uuid not null references f.documento_fiscal(id),
  tipo text not null check (tipo in (
    'CANCELAMENTO', 'CARTA_CORRECAO', 'ESTORNO',
    'SUBSTITUICAO', 'REENVIO', 'CONSULTA'
  )),
  justificativa text,
  documento_referenciado_chave text,
  protocolo text,
  status text not null,
  resposta jsonb,
  criado_por uuid,
  created_at timestamptz not null default now()
);

create index idx_solicitacao_faturamento_status
  on f.solicitacao_faturamento (status);
create index idx_solicitacao_item_solicitacao_id
  on f.solicitacao_item (solicitacao_id);
create index idx_solicitacao_item_origem_id
  on f.solicitacao_item (origem_id);
create index idx_documento_fiscal_emissao_status
  on f.documento_fiscal_emissao (status);
create index idx_documento_fiscal_emissao_solicitacao_id
  on f.documento_fiscal_emissao (solicitacao_id);
create index idx_documento_fiscal_emissao_chave_acesso
  on f.documento_fiscal_emissao (chave_acesso);
create index idx_documento_fiscal_evento_status
  on f.documento_fiscal_evento (status);

alter table f.perfil_operacao enable row level security;
alter table f.solicitacao_faturamento enable row level security;
alter table f.solicitacao_item enable row level security;
alter table f.documento_fiscal_emissao enable row level security;
alter table f.documento_fiscal_evento enable row level security;

create policy perfil_operacao_all
  on f.perfil_operacao
  for all
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and (empresa_id is null or empresa_id = public.current_empresa_id())
    and f.has_finance_access()
  )
  with check (
    tenant_id = public.current_tenant_id()
    and (empresa_id is null or empresa_id = public.current_empresa_id())
    and f.has_finance_access()
  );

create policy enforce_active_empresa_scope
  on f.perfil_operacao
  as restrictive
  for all
  to authenticated
  using (
    tenant_id = (select public.current_tenant_id())
    and (empresa_id is null or empresa_id = (select public.current_empresa_id()))
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
  )
  with check (
    tenant_id = (select public.current_tenant_id())
    and (empresa_id is null or empresa_id = (select public.current_empresa_id()))
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
  );

create policy solicitacao_faturamento_all
  on f.solicitacao_faturamento
  for all
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access()
  )
  with check (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access()
  );

create policy enforce_active_empresa_scope
  on f.solicitacao_faturamento
  as restrictive
  for all
  to authenticated
  using (
    tenant_id = (select public.current_tenant_id())
    and empresa_id = (select public.current_empresa_id())
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
  )
  with check (
    tenant_id = (select public.current_tenant_id())
    and empresa_id = (select public.current_empresa_id())
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
  );

create policy solicitacao_item_all
  on f.solicitacao_item
  for all
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and f.has_finance_access()
    and exists (
      select 1
      from f.solicitacao_faturamento sf
      where sf.id = solicitacao_id
        and sf.tenant_id = public.current_tenant_id()
        and sf.empresa_id = public.current_empresa_id()
    )
  )
  with check (
    tenant_id = public.current_tenant_id()
    and f.has_finance_access()
    and exists (
      select 1
      from f.solicitacao_faturamento sf
      where sf.id = solicitacao_id
        and sf.tenant_id = public.current_tenant_id()
        and sf.empresa_id = public.current_empresa_id()
    )
  );

create policy enforce_active_empresa_scope
  on f.solicitacao_item
  as restrictive
  for all
  to authenticated
  using (
    tenant_id = (select public.current_tenant_id())
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
    and exists (
      select 1
      from f.solicitacao_faturamento sf
      where sf.id = solicitacao_id
        and sf.tenant_id = public.current_tenant_id()
        and sf.empresa_id = public.current_empresa_id()
    )
  )
  with check (
    tenant_id = (select public.current_tenant_id())
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
    and exists (
      select 1
      from f.solicitacao_faturamento sf
      where sf.id = solicitacao_id
        and sf.tenant_id = public.current_tenant_id()
        and sf.empresa_id = public.current_empresa_id()
    )
  );

create policy documento_fiscal_emissao_all
  on f.documento_fiscal_emissao
  for all
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access()
  )
  with check (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access()
  );

create policy enforce_active_empresa_scope
  on f.documento_fiscal_emissao
  as restrictive
  for all
  to authenticated
  using (
    tenant_id = (select public.current_tenant_id())
    and empresa_id = (select public.current_empresa_id())
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
  )
  with check (
    tenant_id = (select public.current_tenant_id())
    and empresa_id = (select public.current_empresa_id())
    and (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
  );

create policy documento_fiscal_evento_all
  on f.documento_fiscal_evento
  for all
  to authenticated
  using (
    f.has_finance_access()
    and exists (
      select 1
      from f.documento_fiscal df
      where df.id = documento_fiscal_id
        and df.tenant_id = public.current_tenant_id()
        and df.empresa_id = public.current_empresa_id()
    )
  )
  with check (
    f.has_finance_access()
    and exists (
      select 1
      from f.documento_fiscal df
      where df.id = documento_fiscal_id
        and df.tenant_id = public.current_tenant_id()
        and df.empresa_id = public.current_empresa_id()
    )
  );

create policy enforce_active_empresa_scope
  on f.documento_fiscal_evento
  as restrictive
  for all
  to authenticated
  using (
    (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
    and exists (
      select 1
      from f.documento_fiscal df
      where df.id = documento_fiscal_id
        and df.tenant_id = public.current_tenant_id()
        and df.empresa_id = public.current_empresa_id()
    )
  )
  with check (
    (select public.has_active_empresa_access(
      public.current_tenant_id(), public.current_empresa_id()
    ))
    and exists (
      select 1
      from f.documento_fiscal df
      where df.id = documento_fiscal_id
        and df.tenant_id = public.current_tenant_id()
        and df.empresa_id = public.current_empresa_id()
    )
  );

create trigger trg_solicitacao_faturamento_set_updated_at
  before update on f.solicitacao_faturamento
  for each row execute function a.fn_set_updated_at();

create trigger trg_documento_fiscal_emissao_set_updated_at
  before update on f.documento_fiscal_emissao
  for each row execute function a.fn_set_updated_at();

commit;
