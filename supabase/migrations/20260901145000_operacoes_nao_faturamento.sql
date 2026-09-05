begin;

create table f.operacao_fiscal (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.current_tenant_id(),
  empresa_id uuid not null default public.current_empresa_id(),
  tipo text not null check (tipo in ('DEVOLUCAO_COMPRA', 'VENDA_ORDEM', 'REMESSA', 'RETORNO', 'ESTORNO')),
  finalidade text,
  status text not null default 'RASCUNHO'
    check (status in ('RASCUNHO', 'PRONTO_HOMOLOGACAO', 'AGUARDANDO_PRIMEIRA', 'AGUARDANDO_SEGUNDA', 'AGUARDANDO_RETORNO', 'CONCLUIDA', 'CANCELADA')),
  ambiente text not null default 'HOMOLOGACAO' check (ambiente = 'HOMOLOGACAO'),
  nf_entrada_origem_id bigint,
  documento_origem_id uuid,
  ov_origem_id integer,
  operacao_pai_id uuid,
  perfil_operacao_id uuid,
  cfop_proposto text check (cfop_proposto is null or cfop_proposto ~ '^[0-9]{4}$'),
  cfop_confirmado text check (cfop_confirmado is null or cfop_confirmado ~ '^[0-9]{4}$'),
  cfop_segunda_nota text check (cfop_segunda_nota is null or cfop_segunda_nota ~ '^[0-9]{4}$'),
  cfop_confirmado_em timestamptz,
  cfop_confirmado_por uuid references a.usuario(id) on delete set null,
  finalidade_emissao smallint not null default 1 check (finalidade_emissao in (1, 3)),
  nfe_referenciada text check (nfe_referenciada is null or nfe_referenciada ~ '^[0-9]{44}$'),
  chave_primeira_nota text check (chave_primeira_nota is null or chave_primeira_nota ~ '^[0-9]{44}$'),
  chave_segunda_nota text check (chave_segunda_nota is null or chave_segunda_nota ~ '^[0-9]{44}$'),
  documento_primeira_nota_id uuid,
  documento_segunda_nota_id uuid,
  destinatario_id integer,
  entrega_json jsonb,
  justificativa_fisco text,
  informacoes_complementares text,
  valor_total numeric(14,2) not null default 0,
  dados_json jsonb not null default '{}'::jsonb,
  preparado_homologacao_em timestamptz,
  criado_por uuid default a.fn_current_usuario_id() references a.usuario(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint operacao_fiscal_tenant_fk foreign key (tenant_id) references c.tenant(id),
  constraint operacao_fiscal_empresa_fk foreign key (tenant_id, empresa_id) references c.empresa(tenant_id, id),
  constraint operacao_fiscal_nf_entrada_fk foreign key (tenant_id, empresa_id, nf_entrada_origem_id)
    references public.nf_entrada(tenant_id, empresa_id, id),
  constraint operacao_fiscal_documento_origem_fk foreign key (tenant_id, empresa_id, documento_origem_id)
    references f.documento_fiscal(tenant_id, empresa_id, id),
  constraint operacao_fiscal_ov_origem_fk foreign key (tenant_id, empresa_id, ov_origem_id)
    references public.ordens_servico(tenant_id, empresa_id, id),
  constraint operacao_fiscal_pai_fk foreign key (tenant_id, empresa_id, operacao_pai_id)
    references f.operacao_fiscal(tenant_id, empresa_id, id),
  constraint operacao_fiscal_perfil_fk foreign key (tenant_id, perfil_operacao_id)
    references f.perfil_operacao(tenant_id, id),
  constraint operacao_fiscal_documento_1_fk foreign key (tenant_id, empresa_id, documento_primeira_nota_id)
    references f.documento_fiscal(tenant_id, empresa_id, id),
  constraint operacao_fiscal_documento_2_fk foreign key (tenant_id, empresa_id, documento_segunda_nota_id)
    references f.documento_fiscal(tenant_id, empresa_id, id),
  constraint operacao_fiscal_destinatario_fk foreign key (tenant_id, empresa_id, destinatario_id)
    references public.clientes(tenant_id, empresa_id, id),
  constraint operacao_fiscal_confirmacao_par_ck check (
    (cfop_confirmado_em is null) = (cfop_confirmado_por is null)
  ),
  constraint operacao_fiscal_tenant_empresa_id_uk unique (tenant_id, empresa_id, id)
);

create index operacao_fiscal_lista_idx
  on f.operacao_fiscal (tenant_id, empresa_id, status, created_at desc)
  where deleted_at is null;

create table f.operacao_fiscal_item (
  id uuid primary key default gen_random_uuid(),
  operacao_id uuid not null,
  tenant_id uuid not null,
  empresa_id uuid not null,
  ordem integer not null check (ordem > 0),
  origem_nitem integer,
  nf_entrada_item_id bigint,
  item_id integer,
  codigo text,
  descricao text not null,
  ncm text,
  unidade text,
  quantidade_original numeric(14,4),
  quantidade numeric(14,4) not null check (quantidade > 0),
  valor_unitario numeric(14,6) not null default 0,
  valor_total numeric(14,2) not null default 0,
  cfop_original text,
  cfop_proposto text,
  cfop_confirmado text not null check (cfop_confirmado ~ '^[0-9]{4}$'),
  origem_mercadoria smallint check (origem_mercadoria is null or origem_mercadoria between 0 and 8),
  cst_icms text,
  csosn text,
  cst_ipi text,
  cst_pis text,
  cst_cofins text,
  cbenef text,
  reducao_base_icms_percentual numeric(7,4),
  unidade_tributavel text,
  cst_ibs_cbs text,
  cclass_trib text,
  cclass_trib_versao text,
  ibs_cbs_json jsonb,
  base_icms numeric(14,2) not null default 0,
  base_ipi numeric(14,2) not null default 0,
  base_pis numeric(14,2) not null default 0,
  base_cofins numeric(14,2) not null default 0,
  aliquota_icms numeric(7,4),
  aliquota_ipi numeric(7,4),
  aliquota_pis numeric(7,4),
  aliquota_cofins numeric(7,4),
  valor_icms numeric(14,2) not null default 0,
  valor_ipi numeric(14,2) not null default 0,
  valor_pis numeric(14,2) not null default 0,
  valor_cofins numeric(14,2) not null default 0,
  xml_validado boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operacao_fiscal_item_operacao_fk foreign key (tenant_id, empresa_id, operacao_id)
    references f.operacao_fiscal(tenant_id, empresa_id, id) on delete cascade,
  constraint operacao_fiscal_item_nf_item_fk foreign key (tenant_id, empresa_id, nf_entrada_item_id)
    references public.nf_entrada_itens(tenant_id, empresa_id, id),
  constraint operacao_fiscal_item_item_fk foreign key (tenant_id, empresa_id, item_id)
    references public.itens(tenant_id, empresa_id, id),
  constraint operacao_fiscal_item_icms_regime_ck check (not (cst_icms is not null and csosn is not null)),
  constraint operacao_fiscal_item_reducao_ck check (
    reducao_base_icms_percentual is null or reducao_base_icms_percentual between 0 and 100
  ),
  constraint operacao_fiscal_item_cclass_versao_ck check (
    cclass_trib is null or nullif(btrim(cclass_trib_versao), '') is not null
  ),
  unique (operacao_id, ordem)
);

create table f.remessa_prazo_config (
  tenant_id uuid not null,
  empresa_id uuid not null,
  finalidade text not null check (finalidade in ('INDUSTRIALIZACAO', 'CONSERTO', 'SIMPLES', 'CONTA_ORDEM')),
  prazo_dias integer check (prazo_dias is null or prazo_dias > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references a.usuario(id) on delete set null,
  primary key (tenant_id, empresa_id, finalidade),
  foreign key (tenant_id, empresa_id) references c.empresa(tenant_id, id)
);

create table f.remessa_controle (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  operacao_remessa_id uuid not null,
  operacao_retorno_id uuid,
  finalidade text not null check (finalidade in ('INDUSTRIALIZACAO', 'CONSERTO', 'SIMPLES', 'CONTA_ORDEM')),
  chave_remessa text not null check (chave_remessa ~ '^[0-9]{44}$'),
  chave_retorno text check (chave_retorno is null or chave_retorno ~ '^[0-9]{44}$'),
  destinatario_documento text,
  destinatario_nome text not null,
  remessa_em date not null,
  retorno_em date,
  status text not null default 'ABERTA' check (status in ('ABERTA', 'ENCERRADA', 'CANCELADA')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, empresa_id, operacao_remessa_id)
    references f.operacao_fiscal(tenant_id, empresa_id, id),
  foreign key (tenant_id, empresa_id, operacao_retorno_id)
    references f.operacao_fiscal(tenant_id, empresa_id, id),
  unique (tenant_id, empresa_id, chave_remessa)
);

create or replace function f.fn_cfop_devolucao_proposto(p_cfop_entrada text)
returns text language sql immutable parallel safe as $function$
  select case btrim(p_cfop_entrada)
    when '1101' then '5201'
    when '2101' then '6201'
    when '1551' then '5553'
    when '2556' then '6556'
    else null
  end
$function$;

create or replace function f.fn_cfop_estorno_proposto(p_cfop_original text)
returns text language sql immutable parallel safe as $function$
  select case btrim(p_cfop_original)
    when '5101' then '1201'
    when '5102' then '1202'
    when '5915' then '1915'
    when '6102' then '2202'
    else null
  end
$function$;

create or replace function f.fn_operacao_assert_acesso()
returns table (tenant_id uuid, empresa_id uuid, usuario_id uuid)
language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
begin
  if auth.uid() is null or not f.has_finance_access() then
    raise exception using errcode = '42501', message = 'Sem permissao para operacoes fiscais.';
  end if;
  tenant_id := public.current_tenant_id();
  empresa_id := public.current_empresa_id();
  usuario_id := a.fn_current_usuario_id();
  if tenant_id is null or empresa_id is null or usuario_id is null then
    raise exception using errcode = '42501', message = 'Tenant, empresa e usuario ativos sao obrigatorios.';
  end if;
  return next;
end;
$function$;

create or replace function f.fn_devolucao_compra_preparar(p_nf_entrada_id bigint)
returns jsonb language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare
  v_scope record;
  v_nf public.nf_entrada%rowtype;
  v_itens jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_nf from public.nf_entrada n
   where n.tenant_id = v_scope.tenant_id and n.empresa_id = v_scope.empresa_id
     and n.id = p_nf_entrada_id and n.deleted_at is null;
  if v_nf.id is null then raise exception 'Nota de entrada nao encontrada nesta empresa.'; end if;
  if v_nf.chave !~ '^[0-9]{44}$' then raise exception 'Devolucao bloqueada: a nota de entrada nao possui chave de 44 digitos.'; end if;
  if nullif(btrim(v_nf.xml_raw), '') is null then raise exception 'Devolucao bloqueada: o XML original da entrada nao esta armazenado.'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'nitem', x.nitem, 'codigo', x.codigo, 'descricao', x.descricao, 'ncm', x.ncm,
    'unidade', x.unidade, 'unidade_tributavel', x.unidade_tributavel,
    'quantidade_original', x.quantidade, 'valor_unitario', x.valor_unitario,
    'valor_total', x.valor_total, 'cfop_original', x.cfop,
    'cfop_proposto', f.fn_cfop_devolucao_proposto(x.cfop), 'origem', x.origem,
    'cst_icms', x.cst_icms, 'csosn', x.csosn, 'cbenef', x.cbenef,
    'reducao_base_icms_percentual', x.reducao_base_icms_percentual,
    'base_icms', x.base_icms, 'aliquota_icms', x.aliquota_icms, 'valor_icms', x.valor_icms,
    'cst_ipi', x.cst_ipi, 'base_ipi', x.base_ipi, 'aliquota_ipi', x.aliquota_ipi, 'valor_ipi', x.valor_ipi,
    'cst_pis', x.cst_pis, 'base_pis', x.base_pis, 'aliquota_pis', x.aliquota_pis, 'valor_pis', x.valor_pis,
    'cst_cofins', x.cst_cofins, 'base_cofins', x.base_cofins,
    'aliquota_cofins', x.aliquota_cofins, 'valor_cofins', x.valor_cofins
  ) order by x.nitem), '[]'::jsonb) into v_itens
  from xmltable(
    xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '//n:det' passing xmlparse(document v_nf.xml_raw) columns
      nitem integer path '@nItem', codigo text path 'n:prod/n:cProd', descricao text path 'n:prod/n:xProd',
      ncm text path 'n:prod/n:NCM', cfop text path 'n:prod/n:CFOP', unidade text path 'n:prod/n:uCom',
      unidade_tributavel text path 'n:prod/n:uTrib',
      quantidade numeric path 'n:prod/n:qCom', valor_unitario numeric path 'n:prod/n:vUnCom', valor_total numeric path 'n:prod/n:vProd',
      origem smallint path 'n:imposto/n:ICMS/*/n:orig', cst_icms text path 'n:imposto/n:ICMS/*/n:CST',
      csosn text path 'n:imposto/n:ICMS/*/n:CSOSN', cbenef text path 'n:imposto/n:ICMS/*/n:cBenef',
      reducao_base_icms_percentual numeric path 'n:imposto/n:ICMS/*/n:pRedBC',
      base_icms numeric path 'n:imposto/n:ICMS/*/n:vBC',
      aliquota_icms numeric path 'n:imposto/n:ICMS/*/n:pICMS', valor_icms numeric path 'n:imposto/n:ICMS/*/n:vICMS',
      cst_ipi text path 'n:imposto/n:IPI/*/n:CST', base_ipi numeric path 'n:imposto/n:IPI/*/n:vBC',
      aliquota_ipi numeric path 'n:imposto/n:IPI/*/n:pIPI', valor_ipi numeric path 'n:imposto/n:IPI/*/n:vIPI',
      cst_pis text path 'n:imposto/n:PIS/*/n:CST', base_pis numeric path 'n:imposto/n:PIS/*/n:vBC',
      aliquota_pis numeric path 'n:imposto/n:PIS/*/n:pPIS', valor_pis numeric path 'n:imposto/n:PIS/*/n:vPIS',
      cst_cofins text path 'n:imposto/n:COFINS/*/n:CST', base_cofins numeric path 'n:imposto/n:COFINS/*/n:vBC',
      aliquota_cofins numeric path 'n:imposto/n:COFINS/*/n:pCOFINS', valor_cofins numeric path 'n:imposto/n:COFINS/*/n:vCOFINS'
  ) x;
  if jsonb_array_length(v_itens) = 0 then raise exception 'XML original nao possui itens de NF-e legiveis.'; end if;
  return jsonb_build_object('nf_entrada_id', v_nf.id, 'chave', v_nf.chave, 'numero', v_nf.numero,
    'fornecedor', v_nf.emitente_nome, 'valor_total', v_nf.valor_total, 'itens', v_itens);
end;
$function$;

commit;
