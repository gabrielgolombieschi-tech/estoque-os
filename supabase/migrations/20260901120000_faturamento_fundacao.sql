begin;

alter table f.documento_fiscal
  add column origem text not null default 'IMPORTADO'
    check (origem in ('IMPORTADO', 'EMITIDO')),
  add column nfe_referenciada text
    check (nfe_referenciada is null or nfe_referenciada ~ '^[0-9]{44}$');

comment on column f.documento_fiscal.nfe_referenciada is
  'Chave da NF-e referenciada pela operacao emitida. Nula quando a natureza nao exige documento anterior.';

-- Chaves compostas usadas pelas FKs abaixo. O id continua sendo globalmente
-- unico; a composicao impede que um filho carregue tenant/empresa divergente.
create unique index if not exists empresa_tenant_id_id_ux
  on c.empresa (tenant_id, id);
create unique index if not exists documento_fiscal_tenant_id_ux
  on f.documento_fiscal (tenant_id, id);
create unique index if not exists documento_fiscal_tenant_empresa_id_ux
  on f.documento_fiscal (tenant_id, empresa_id, id);

alter table f.documento_fiscal
  drop constraint if exists fk_documento_fiscal__empresa_id__empresa,
  drop constraint if exists fk_documento_fiscal__cliente_id__clientes,
  add constraint fk_documento_fiscal__tenant_empresa__empresa
    foreign key (tenant_id, empresa_id)
    references c.empresa (tenant_id, id),
  add constraint fk_documento_fiscal__tenant_empresa_cliente__clientes
    foreign key (tenant_id, empresa_id, cliente_id)
    references public.clientes (tenant_id, empresa_id, id)
    not valid;

comment on constraint fk_documento_fiscal__tenant_empresa_cliente__clientes on f.documento_fiscal is
  'NOT VALID por legado: o pre-voo de 2026-09-01 encontrou 7 documentos ligados a clientes de outra empresa no mesmo tenant. Novas gravacoes ja sao validadas; validar a constraint somente apos saneamento explicito.';

-- O snapshot historico e o que efetivamente foi enviado/autorizado. Os campos
-- da solicitacao continuam sendo apenas a previa recalculavel do payload.
alter table f.documento_fiscal_item
  add column empresa_id uuid,
  add column item_id integer,
  add column cst_icms text,
  add column csosn text,
  add column cst_ipi text,
  add column cst_pis text,
  add column cst_cofins text,
  add column cbenef text,
  add column reducao_base_icms_percentual numeric(7,4)
    check (
      reducao_base_icms_percentual is null
      or reducao_base_icms_percentual between 0 and 100
    ),
  add column unidade_tributavel text,
  add column cst_ibs_cbs text
    check (cst_ibs_cbs is null or cst_ibs_cbs ~ '^[0-9]{3}$'),
  add column cclass_trib text
    check (cclass_trib is null or cclass_trib ~ '^[0-9]{6}$'),
  add column cclass_trib_versao text,
  add column ibs_cbs_json jsonb
    check (ibs_cbs_json is null or jsonb_typeof(ibs_cbs_json) = 'object'),
  add column snapshot_fiscal_em timestamptz,
  add constraint documento_fiscal_item_icms_regime_ck
    check (not (cst_icms is not null and csosn is not null)),
  add constraint documento_fiscal_item_ibs_cbs_classificacao_ck
    check (
      cst_ibs_cbs is null
      or cclass_trib is null
      or left(cclass_trib, 3) = cst_ibs_cbs
    ),
  add constraint documento_fiscal_item_cclass_versao_ck
    check (
      cclass_trib is null
      or nullif(btrim(cclass_trib_versao), '') is not null
    );

comment on column f.documento_fiscal_item.snapshot_fiscal_em is
  'Instante em que o snapshot fiscal foi congelado para o documento autorizado; nao deve ser preenchido no rascunho.';
comment on column f.documento_fiscal_item.cclass_trib_versao is
  'Versao da tabela oficial cClassTrib usada para montar e autorizar o item.';

update f.documento_fiscal_item dfi
set empresa_id = df.empresa_id
from f.documento_fiscal df
where df.tenant_id = dfi.tenant_id
  and df.id = dfi.documento_fiscal_id
  and dfi.empresa_id is null;

alter table f.documento_fiscal_item
  alter column empresa_id set not null,
  drop constraint if exists fk_documento_fiscal_item__documento_fiscal_id__documento_fiscal,
  add constraint fk_documento_fiscal_item__documento_escopo_fk
    foreign key (tenant_id, empresa_id, documento_fiscal_id)
    references f.documento_fiscal (tenant_id, empresa_id, id)
    on delete cascade,
  add constraint fk_documento_fiscal_item__item_escopo_fk
    foreign key (tenant_id, empresa_id, item_id)
    references public.itens (tenant_id, empresa_id, id)
    on delete restrict;

alter table public.itens
  add column fabricado boolean not null default false;

comment on column public.itens.fabricado is
  'Indica produto fabricado pela empresa. Nao define sozinho CFOP ou tributacao da saida.';

alter table public.os_itens
  add column finalidade text
    check (finalidade is null or finalidade in ('componente', 'venda'));

comment on column public.os_itens.finalidade is
  'Componente sai do estoque sem compor a NF; venda compoe a solicitacao de faturamento. Legado permanece nulo ate classificacao.';

create table f.perfil_operacao (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid,
  codigo text not null,
  nome text not null,
  modelo text not null check (modelo in ('NFE', 'NFSE')),
  natureza_operacao text not null,
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
  cbenef text,
  reducao_base_icms_percentual numeric(7,4)
    check (
      reducao_base_icms_percentual is null
      or reducao_base_icms_percentual between 0 and 100
    ),
  beneficio_texto_legal text,
  cst_ibs_cbs text
    check (cst_ibs_cbs is null or cst_ibs_cbs ~ '^[0-9]{3}$'),
  cclass_trib text
    check (cclass_trib is null or cclass_trib ~ '^[0-9]{6}$'),
  cclass_trib_versao text,
  exige_referencia boolean not null default false,
  exige_motivo boolean not null default false,
  observacao text,
  vigencia_inicio date not null default current_date,
  vigencia_fim date,
  created_at timestamptz not null default now(),
  constraint perfil_operacao_icms_regime_ck
    check (not (cst_icms is not null and csosn is not null)),
  constraint perfil_operacao_ibs_cbs_classificacao_ck
    check (
      cst_ibs_cbs is null
      or cclass_trib is null
      or left(cclass_trib, 3) = cst_ibs_cbs
    ),
  constraint perfil_operacao_cclass_versao_ck
    check (
      cclass_trib is null
      or nullif(btrim(cclass_trib_versao), '') is not null
    ),
  constraint perfil_operacao_vigencia_ck
    check (vigencia_fim is null or vigencia_fim >= vigencia_inicio),
  constraint perfil_operacao_tenant_fk
    foreign key (tenant_id) references c.tenant(id),
  constraint perfil_operacao_empresa_escopo_fk
    foreign key (tenant_id, empresa_id) references c.empresa(tenant_id, id),
  unique nulls not distinct (tenant_id, empresa_id, codigo, vigencia_inicio)
);

create unique index perfil_operacao_tenant_id_ux
  on f.perfil_operacao (tenant_id, id);

comment on column f.perfil_operacao.cst_icms is
  'CST do ICMS para regime normal. Mutuamente exclusivo com CSOSN.';
comment on column f.perfil_operacao.csosn is
  'CSOSN do ICMS para Simples Nacional. Mutuamente exclusivo com CST do ICMS.';
comment on column f.perfil_operacao.cbenef is
  'Codigo de beneficio fiscal enviado em campo proprio da NF-e.';
comment on column f.perfil_operacao.cclass_trib is
  'Classificacao tributaria IBS/CBS. Os tres primeiros digitos correspondem ao CST IBS/CBS.';

create table f.solicitacao_faturamento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  cliente_id integer,
  perfil_operacao_id uuid,
  status text not null default 'RASCUNHO'
    check (status in ('RASCUNHO', 'PREVIA', 'APROVADA', 'EMITIDA', 'CANCELADA')),
  pedido_cliente text,
  condicao_pagamento text,
  observacao text,
  criado_por uuid default a.fn_current_usuario_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint solicitacao_faturamento_empresa_escopo_fk
    foreign key (tenant_id, empresa_id) references c.empresa(tenant_id, id),
  constraint solicitacao_faturamento_cliente_escopo_fk
    foreign key (tenant_id, empresa_id, cliente_id)
    references public.clientes(tenant_id, empresa_id, id),
  constraint solicitacao_faturamento_perfil_tenant_fk
    foreign key (tenant_id, perfil_operacao_id)
    references f.perfil_operacao(tenant_id, id),
  constraint solicitacao_faturamento_criado_por_fk
    foreign key (criado_por) references a.usuario(id) on delete set null,
  unique (tenant_id, empresa_id, id)
);

create table f.solicitacao_item (
  id uuid primary key default gen_random_uuid(),
  solicitacao_id uuid not null,
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  origem_tipo text not null check (origem_tipo in ('OS', 'OV', 'AVULSO', 'CONTRATO')),
  origem_id text,
  origem_item_id text,
  pedido_linha text,
  item_id integer,
  descricao text not null,
  ncm text,
  cfop text,
  cst_icms text,
  csosn text,
  cst_ipi text,
  cst_pis text,
  cst_cofins text,
  cbenef text,
  reducao_base_icms_percentual numeric(7,4)
    check (
      reducao_base_icms_percentual is null
      or reducao_base_icms_percentual between 0 and 100
    ),
  cst_ibs_cbs text
    check (cst_ibs_cbs is null or cst_ibs_cbs ~ '^[0-9]{3}$'),
  cclass_trib text
    check (cclass_trib is null or cclass_trib ~ '^[0-9]{6}$'),
  cclass_trib_versao text,
  ibs_cbs_json jsonb
    check (ibs_cbs_json is null or jsonb_typeof(ibs_cbs_json) = 'object'),
  quantidade numeric not null,
  unidade text,
  valor_unitario numeric not null,
  ordem int not null default 1,
  constraint solicitacao_item_icms_regime_ck
    check (not (cst_icms is not null and csosn is not null)),
  constraint solicitacao_item_ibs_cbs_classificacao_ck
    check (
      cst_ibs_cbs is null
      or cclass_trib is null
      or left(cclass_trib, 3) = cst_ibs_cbs
    ),
  constraint solicitacao_item_cclass_versao_ck
    check (
      cclass_trib is null
      or nullif(btrim(cclass_trib_versao), '') is not null
    ),
  constraint solicitacao_item_solicitacao_escopo_fk
    foreign key (tenant_id, empresa_id, solicitacao_id)
    references f.solicitacao_faturamento(tenant_id, empresa_id, id)
    on delete cascade,
  constraint solicitacao_item_item_escopo_fk
    foreign key (tenant_id, empresa_id, item_id)
    references public.itens(tenant_id, empresa_id, id)
    on delete restrict
);

comment on column f.solicitacao_item.cst_icms is
  'Previa recalculavel do payload. O snapshot historico e congelado em f.documento_fiscal_item na autorizacao.';

create table f.documento_fiscal_emissao (
  documento_fiscal_id uuid primary key,
  solicitacao_id uuid,
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
  constraint documento_fiscal_emissao_documento_escopo_fk
    foreign key (tenant_id, empresa_id, documento_fiscal_id)
    references f.documento_fiscal(tenant_id, empresa_id, id),
  constraint documento_fiscal_emissao_solicitacao_escopo_fk
    foreign key (tenant_id, empresa_id, solicitacao_id)
    references f.solicitacao_faturamento(tenant_id, empresa_id, id),
  unique (tenant_id, empresa_id, referencia_externa)
);

create table f.documento_fiscal_evento (
  id uuid primary key default gen_random_uuid(),
  documento_fiscal_id uuid not null,
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  tipo text not null check (tipo in (
    'CANCELAMENTO', 'CARTA_CORRECAO', 'ESTORNO',
    'SUBSTITUICAO', 'REENVIO', 'CONSULTA'
  )),
  justificativa text,
  documento_referenciado_chave text,
  protocolo text,
  status text not null,
  resposta jsonb,
  criado_por uuid default a.fn_current_usuario_id(),
  created_at timestamptz not null default now(),
  constraint documento_fiscal_evento_documento_escopo_fk
    foreign key (tenant_id, empresa_id, documento_fiscal_id)
    references f.documento_fiscal(tenant_id, empresa_id, id),
  constraint documento_fiscal_evento_criado_por_fk
    foreign key (criado_por) references a.usuario(id) on delete set null
);

create index idx_solicitacao_faturamento_status
  on f.solicitacao_faturamento (status);
create index idx_solicitacao_item_solicitacao_id
  on f.solicitacao_item (solicitacao_id);
create index idx_solicitacao_item_empresa_id
  on f.solicitacao_item (empresa_id);
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
