\set ON_ERROR_STOP on

begin;

-- O trigger de contas a receber exige plano de contas completo, que nao faz
-- parte deste smoke de integridade. Apenas ele e suspenso; os triggers de FK
-- permanecem ativos e sao justamente o objeto deste teste.
alter table f.documento_fiscal
  disable trigger trg_documento_fiscal__ar_nfe;

insert into c.tenant (id, codigo, nome)
values (
  '11111111-1111-4111-8111-111111111111',
  'SMOKE-FATURAMENTO',
  'Smoke faturamento'
);

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values
  (
    '22222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    'SMOKE-A',
    'Empresa Smoke A',
    'Empresa Smoke A',
    '11111111000111'
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111',
    'SMOKE-B',
    'Empresa Smoke B',
    'Empresa Smoke B',
    '22222222000122'
  );

-- O legado ainda mantem uma projecao separada em public.empresas. O smoke
-- cria ambas explicitamente para exercitar as FKs reais usadas por itens.
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia)
values
  (
    '22222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    '11111111000111',
    'Empresa Smoke A',
    'Empresa Smoke A'
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111',
    '22222222000122',
    'Empresa Smoke B',
    'Empresa Smoke B'
  )
on conflict (id) do nothing;

insert into public.clientes (tenant_id, empresa_id, nome, documento)
values (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'CLIENTE REAL DO SMOKE',
  '12345678000199'
)
returning id as cliente_id \gset smoke_

insert into public.clientes (tenant_id, empresa_id, nome, documento)
values (
  '11111111-1111-4111-8111-111111111111',
  '33333333-3333-4333-8333-333333333333',
  'CLIENTE DE OUTRA EMPRESA',
  '98765432000188'
)
returning id as cliente_outra_empresa_id \gset smoke_

insert into public.itens (
  tenant_id,
  empresa_id,
  codigo_interno,
  nome,
  tipo,
  finalidade,
  ativo
)
values (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'SMOKE-ITEM-REAL',
  'ITEM REAL DO SMOKE',
  'produto',
  'revenda',
  true
)
returning id as item_id \gset smoke_

insert into public.itens (
  tenant_id,
  empresa_id,
  codigo_interno,
  nome,
  tipo,
  finalidade,
  ativo
)
values (
  '11111111-1111-4111-8111-111111111111',
  '33333333-3333-4333-8333-333333333333',
  'SMOKE-ITEM-OUTRA-EMPRESA',
  'ITEM DE OUTRA EMPRESA',
  'produto',
  'revenda',
  true
)
returning id as item_outra_empresa_id \gset smoke_

insert into f.perfil_operacao (
  id,
  tenant_id,
  empresa_id,
  codigo,
  nome,
  modelo,
  natureza_operacao,
  natureza_texto
)
values (
  '44444444-4444-4444-8444-444444444444',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'SMOKE-SEM-REGRA-FISCAL',
  'Smoke sem regra fiscal',
  'NFE',
  'SMOKE',
  'Smoke sem regra fiscal'
);

insert into f.solicitacao_faturamento (
  id,
  tenant_id,
  empresa_id,
  cliente_id,
  perfil_operacao_id,
  status
)
values (
  '55555555-5555-4555-8555-555555555555',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  :smoke_cliente_id,
  '44444444-4444-4444-8444-444444444444',
  'APROVADA'
);

insert into f.solicitacao_item (
  id,
  solicitacao_id,
  tenant_id,
  empresa_id,
  origem_tipo,
  item_id,
  descricao,
  quantidade,
  unidade,
  valor_unitario
)
values (
  '66666666-6666-4666-8666-666666666666',
  '55555555-5555-4555-8555-555555555555',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'AVULSO',
  :smoke_item_id,
  'ITEM REAL DO SMOKE',
  1,
  'UN',
  100
);

insert into f.documento_fiscal (
  id,
  tenant_id,
  empresa_id,
  cliente_id,
  chave_acesso,
  modelo,
  serie,
  numero,
  valor_total,
  valor_produtos,
  operacao,
  natureza,
  origem,
  nfe_status
)
values (
  '77777777-7777-4777-8777-777777777777',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  :smoke_cliente_id,
  repeat('9', 44),
  '55',
  '2',
  '1',
  100,
  100,
  'SAIDA',
  'PRODUTO',
  'EMITIDO',
  'EMITIDA'
);

alter table f.documento_fiscal
  enable trigger trg_documento_fiscal__ar_nfe;

insert into f.documento_fiscal_emissao (
  documento_fiscal_id,
  solicitacao_id,
  tenant_id,
  empresa_id,
  referencia_externa,
  ambiente,
  status,
  autorizado_em
)
values (
  '77777777-7777-4777-8777-777777777777',
  '55555555-5555-4555-8555-555555555555',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'SMOKE-AUTORIZADO',
  'HOMOLOGACAO',
  'AUTORIZADA',
  clock_timestamp()
);

insert into f.documento_fiscal_item (
  id,
  tenant_id,
  empresa_id,
  documento_fiscal_id,
  item_id,
  item_n,
  item_tipo,
  codigo,
  descricao,
  quantidade,
  unidade,
  valor_unitario,
  valor_total,
  snapshot_fiscal_em
)
values (
  '88888888-8888-4888-8888-888888888888',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '77777777-7777-4777-8777-777777777777',
  :smoke_item_id,
  1,
  'PRODUTO',
  'SMOKE-ITEM-REAL',
  'ITEM REAL DO SMOKE',
  1,
  'UN',
  100,
  100,
  clock_timestamp()
);

-- O trigger contabil nao participa das duas tentativas negativas abaixo. A
-- FK NOT VALID do documento deve continuar rejeitando toda escrita nova.
alter table f.documento_fiscal
  disable trigger trg_documento_fiscal__ar_nfe;

do $smoke$
begin
  if not exists (
    select 1
    from f.solicitacao_faturamento sf
    join f.solicitacao_item si
      on si.tenant_id = sf.tenant_id
     and si.empresa_id = sf.empresa_id
     and si.solicitacao_id = sf.id
    join public.clientes c
      on c.tenant_id = sf.tenant_id
     and c.empresa_id = sf.empresa_id
     and c.id = sf.cliente_id
    join public.itens i
      on i.tenant_id = si.tenant_id
     and i.empresa_id = si.empresa_id
     and i.id = si.item_id
    join f.documento_fiscal df
      on df.tenant_id = sf.tenant_id
     and df.empresa_id = sf.empresa_id
     and df.cliente_id = c.id
     and df.origem = 'EMITIDO'
    join f.documento_fiscal_emissao dfe
      on dfe.tenant_id = df.tenant_id
     and dfe.empresa_id = df.empresa_id
     and dfe.documento_fiscal_id = df.id
     and dfe.solicitacao_id = sf.id
     and dfe.status = 'AUTORIZADA'
    join f.documento_fiscal_item dfi
      on dfi.tenant_id = df.tenant_id
     and dfi.empresa_id = df.empresa_id
     and dfi.documento_fiscal_id = df.id
     and dfi.item_id = i.id
     and dfi.snapshot_fiscal_em is not null
    where sf.id = '55555555-5555-4555-8555-555555555555'
  ) then
    raise exception 'SMOKE FALHOU: cliente/item/documento/emissao nao ficaram amarrados';
  end if;

  begin
    insert into f.solicitacao_item (
      solicitacao_id,
      tenant_id,
      empresa_id,
      origem_tipo,
      item_id,
      descricao,
      quantidade,
      unidade,
      valor_unitario
    )
    values (
      '55555555-5555-4555-8555-555555555555',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'AVULSO',
      (
        select id
        from public.itens
        where tenant_id = '11111111-1111-4111-8111-111111111111'
          and empresa_id = '33333333-3333-4333-8333-333333333333'
          and codigo_interno = 'SMOKE-ITEM-OUTRA-EMPRESA'
      ),
      'ITEM DE ESCOPO ERRADO',
      1,
      'UN',
      1
    );

    raise exception 'SMOKE FALHOU: FK aceitou item de outra empresa';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into f.solicitacao_faturamento (
      tenant_id,
      empresa_id,
      cliente_id,
      status
    )
    values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      (
        select id
        from public.clientes
        where tenant_id = '11111111-1111-4111-8111-111111111111'
          and empresa_id = '33333333-3333-4333-8333-333333333333'
          and nome = 'CLIENTE DE OUTRA EMPRESA'
      ),
      'RASCUNHO'
    );

    raise exception 'SMOKE FALHOU: FK aceitou cliente de outra empresa na solicitacao';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    update f.documento_fiscal
    set cliente_id = (
      select id
      from public.clientes
      where tenant_id = '11111111-1111-4111-8111-111111111111'
        and empresa_id = '33333333-3333-4333-8333-333333333333'
        and nome = 'CLIENTE DE OUTRA EMPRESA'
    )
    where id = '77777777-7777-4777-8777-777777777777';

    raise exception 'SMOKE FALHOU: FK NOT VALID aceitou cliente de outra empresa em nova escrita';
  exception
    when foreign_key_violation then
      null;
  end;
end;
$smoke$;

alter table f.documento_fiscal
  enable trigger trg_documento_fiscal__ar_nfe;

select
  :smoke_cliente_id::integer as cliente_real_id,
  :smoke_item_id::integer as item_real_id,
  'EMITIDO'::text as documento_origem,
  'AUTORIZADA'::text as emissao_status,
  true as item_cruzado_rejeitado,
  true as cliente_cruzado_rejeitado,
  true as fk_not_valid_rejeitou_nova_escrita;

rollback;
