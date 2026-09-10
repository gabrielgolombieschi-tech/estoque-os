\set ON_ERROR_STOP on
begin;

insert into public.tenants (id, nome, ativo)
values ('10000000-0000-4000-8000-000000000001', 'Tenant teste NF-e', true);

insert into c.tenant (id, codigo, nome)
values ('10000000-0000-4000-8000-000000000001', 'TESTE-NFE', 'Tenant teste NF-e');

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'SEGTESTE', 'ELETRICA SEGAU TESTE LTDA', 'SEG TESTE', '13671448000189'
);

insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '13671448000189', 'ELETRICA SEGAU TESTE LTDA', 'SEG TESTE', 'SC', 'JOINVILLE'
)
on conflict (id) do nothing;

insert into auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '70000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'nfe-pipeline@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values (
  '70000000-0000-4000-8000-000000000002',
  '70000000-0000-4000-8000-000000000001',
  'Usuario pipeline NF-e', 'nfe-pipeline@example.test', true
);

insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values (
  '70000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001', 'ADMIN', true
);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values (
  '70000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001', 'DIRETOR', true
);
insert into public.user_tenant_context (user_id, tenant_id)
values (
  '70000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001'
);
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values (
  '70000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001'
);

select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $acl_pipeline$
declare v_tabela text;
begin
  foreach v_tabela in array array[
    'f.solicitacao_faturamento',
    'f.solicitacao_item',
    'f.documento_fiscal_emissao'
  ] loop
    if has_table_privilege('authenticated', v_tabela, 'INSERT')
       or has_table_privilege('authenticated', v_tabela, 'UPDATE')
       or has_table_privilege('authenticated', v_tabela, 'DELETE') then
      raise exception 'Authenticated ainda possui DML direto em %.', v_tabela;
    end if;
    if not has_table_privilege('authenticated', v_tabela, 'SELECT') then
      raise exception 'Authenticated perdeu SELECT em %.', v_tabela;
    end if;
    if not has_table_privilege('service_role', v_tabela, 'INSERT')
       or not has_table_privilege('service_role', v_tabela, 'UPDATE')
       or not has_table_privilege('service_role', v_tabela, 'DELETE') then
      raise exception 'Service role perdeu DML necessario em %.', v_tabela;
    end if;
  end loop;
end;
$acl_pipeline$;

insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('20000000-0000-4000-8000-000000000001', '123456789', 3, current_date + 365, 2);

insert into c.empresa_endereco (
  empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge
) values (
  '20000000-0000-4000-8000-000000000001', 'FISCAL', '89200000',
  'RUA TESTE', '1', 'CENTRO', 'JOINVILLE', 'SC', '4209102'
);

insert into public.clientes (
  id, nome, documento, tenant_id, empresa_id, razao_social,
  inscricao_estadual, cep, logradouro, numero_endereco, bairro,
  cidade, uf, pais, indicador_ie, codigo_ibge_municipio
) values (
  910001, 'CLIENTE HOMOLOGACAO', '11222333000181',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'CLIENTE HOMOLOGACAO LTDA', '123456789', '89200000',
  'RUA CLIENTE', '100', 'CENTRO', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102'
);

insert into public.itens (
  id, codigo_interno, nome, tipo, unidade_medida, tenant_id,
  empresa_id, finalidade, ativo
) values (
  910001, 'NFE-TESTE-1', 'ITEM TESTE NFE', 'produto', 'UN',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', 'revenda', true
);

update public.fiscal_itens
set ncm = '85365090', origem = 0, unidade_tributavel = 'UN',
    cst_ipi = '53'
where tenant_id = '10000000-0000-4000-8000-000000000001'
  and empresa_id = '20000000-0000-4000-8000-000000000001'
  and item_id = 910001;

do $cenq_no_produto$
declare
  v_mensagem text;
begin
  begin
    update public.fiscal_itens
    set ipi_codigo_enquadramento_legal = '999'
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and item_id = 910001;
    raise exception 'O cadastro do item aceitou cEnq indevidamente.';
  exception when sqlstate '22023' then
    get stacked diagnostics v_mensagem = message_text;
    if position('Item 910001' in v_mensagem) = 0
       or position('ipi_codigo_enquadramento_legal' in v_mensagem) = 0 then
      raise exception 'Bloqueio de cEnq nao nomeou item e campo: %', v_mensagem;
    end if;
  end;
  if exists (
    select 1 from public.fiscal_itens
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and item_id = 910001
      and ipi_codigo_enquadramento_legal is not null
  ) then
    raise exception 'cEnq foi persistido no cadastro do item.';
  end if;
end;
$cenq_no_produto$;

insert into public.ordens_servico (
  id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id,
  empresa_id, status_fluxo, tipo_documento, codigo, numero_doc, orcado
) values (
  910001, 'OV-TESTE-1', 'CLIENTE HOMOLOGACAO', 910001,
  'em_andamento', 910001,
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  -- Orcado = pedido do cliente, com IPI: 200 de mercadoria + 5% = 210, que e o vNF
  -- da nota de producao deste cenario. E assim que o saldo zera desde a migration
  -- 20260909120000.
  'em_andamento', 'OV', 'OV-SEGTESTE-00001-026', 1, 210
);

insert into public.os_itens (
  id, os_id, item_id, quantidade, valor_unitario, valor_total,
  tenant_id, empresa_id, finalidade
) values (
  910001, 910001, 910001, 2, 100, 200,
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', 'venda'
);

-- A composicao publica usada pela tela continua criando HOM, mas nao pode
-- mais ser usada para fabricar PRODUCAO. A OV isolada evita interferir nos
-- saldos dos cenarios de ciclo de vida abaixo.
insert into public.ordens_servico (
  id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id,
  empresa_id, status_fluxo, tipo_documento, codigo, numero_doc, orcado
) values (
  910005, 'OV-TESTE-COMPOSICAO', 'CLIENTE HOMOLOGACAO', 910001,
  'em_andamento', 910005,
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'em_andamento', 'OV', 'OV-SEGTESTE-00005-026', 5, 50
);
insert into public.os_itens (
  id, os_id, item_id, quantidade, valor_unitario, valor_total,
  tenant_id, empresa_id, finalidade
) values (
  910005, 910005, 910001, 1, 50, 50,
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', 'venda'
);

set local role authenticated;
do $composicao_publica_somente_homologacao$
declare
  v_hom record;
  v_sf integer;
  v_si integer;
  v_df integer;
  v_dfi integer;
  v_dfe integer;
begin
  select * into v_hom
  from f.fn_faturar_documento(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    910005, array[910005],
    '60000000-0000-4000-8000-000000000005',
    'HOMOLOGACAO', 'VENDA_MERCADORIA_TERCEIROS',
    '[{"os_item_id":910005,"quantidade":1,"valor_unitario":50}]'::jsonb,
    null
  );
  if v_hom.documento_fiscal_id is distinct from '60000000-0000-4000-8000-000000000005'::uuid
     or v_hom.solicitacao_id is null
     or v_hom.status is distinct from 'RASCUNHO'
     or v_hom.criado is distinct from true
     or not exists (
       select 1
       from f.documento_fiscal_emissao dfe
       where dfe.tenant_id = '10000000-0000-4000-8000-000000000001'
         and dfe.empresa_id = '20000000-0000-4000-8000-000000000001'
         and dfe.documento_fiscal_id = v_hom.documento_fiscal_id
         and dfe.solicitacao_id = v_hom.solicitacao_id
         and dfe.ambiente = 'HOMOLOGACAO'
         and dfe.status = 'RASCUNHO'
         and dfe.tentativa_count = 0
         and dfe.payload_enviado is null
     )
     or (select count(*) from f.solicitacao_item si
         where si.tenant_id = '10000000-0000-4000-8000-000000000001'
           and si.empresa_id = '20000000-0000-4000-8000-000000000001'
           and si.solicitacao_id = v_hom.solicitacao_id) <> 1
     or (select count(*) from f.documento_fiscal_item dfi
         where dfi.tenant_id = '10000000-0000-4000-8000-000000000001'
           and dfi.empresa_id = '20000000-0000-4000-8000-000000000001'
           and dfi.documento_fiscal_id = v_hom.documento_fiscal_id) <> 1 then
    raise exception 'Composicao autenticada nao criou somente o rascunho HOM esperado: %', row_to_json(v_hom);
  end if;

  select count(*) into v_sf from f.solicitacao_faturamento
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001';
  select count(*) into v_si from f.solicitacao_item
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001';
  select count(*) into v_df from f.documento_fiscal
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001';
  select count(*) into v_dfi from f.documento_fiscal_item
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001';
  select count(*) into v_dfe from f.documento_fiscal_emissao
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001';

  begin
    perform 1
    from f.fn_faturar_documento(
      '10000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000001',
      910005, array[910005],
      '60000000-0000-4000-8000-000000000006',
      'PRODUCAO', 'VENDA_MERCADORIA_TERCEIROS',
      '[{"os_item_id":910005,"quantidade":1,"valor_unitario":50}]'::jsonb,
      null
    );
    raise exception 'Composicao autenticada aceitou PRODUCAO.';
  exception when sqlstate '42501' then null;
  end;

  if (select count(*) from f.solicitacao_faturamento
      where tenant_id = '10000000-0000-4000-8000-000000000001'
        and empresa_id = '20000000-0000-4000-8000-000000000001') <> v_sf
     or (select count(*) from f.solicitacao_item
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001') <> v_si
     or (select count(*) from f.documento_fiscal
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001') <> v_df
     or (select count(*) from f.documento_fiscal_item
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001') <> v_dfi
     or (select count(*) from f.documento_fiscal_emissao
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001') <> v_dfe
     or exists (
       select 1 from f.documento_fiscal
       where tenant_id = '10000000-0000-4000-8000-000000000001'
         and empresa_id = '20000000-0000-4000-8000-000000000001'
         and id = '60000000-0000-4000-8000-000000000006'
     ) then
    raise exception 'PRODUCAO rejeitada pela composicao deixou efeito parcial.';
  end if;
end;
$composicao_publica_somente_homologacao$;
reset role;

insert into f.solicitacao_faturamento (
  id, tenant_id, empresa_id, cliente_id, status, natureza_operacao,
  finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
  valor_frete, valor_seguro, valor_outras_despesas, destino_uf_confirmada,
  destino_confirmado_em, destinacao_mercadoria, pagamento_forma, pagamento_indicador
) values (
  '30000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  910001, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS',
  1, 0, 9, 9, 0, 0, 0, 'SC', now(), 'REVENDA', '15', 1
);

insert into f.solicitacao_item (
  solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, origem_item_id, item_id, descricao,
  cfop, cst_icms, cst_ipi, ipi_codigo_enquadramento_legal, cst_pis, cst_cofins, quantidade, unidade,
  valor_unitario, valor_desconto, icms_modalidade_base_calculo,
  aliquota_icms, aliquota_pis, aliquota_cofins,
  cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json, ordem
) values (
  '30000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'OV', '910001', '910001', 910001, 'ITEM TESTE NFE',
  '5102', '00', '53', '999', '01', '01', 2, 'UN',
  100, 0, '3', 17, 1.65, 7.6,
  '000', '000001', 'NT 2025.002 v1.34',
  '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb, 1
);

do $$
declare
  v_result jsonb;
begin
  v_result := f.fn_solicitacao_nfe_congelar_cadastro('30000000-0000-4000-8000-000000000001');
  if not coalesce((v_result->>'ok')::boolean, false) then
    raise exception 'Validador recusou fixture completa: %', v_result;
  end if;
end;
$$;

-- Daqui em diante a preparacao/claim/retorno simula o cliente administrativo
-- da Edge (JWT service_role). As guardas de DML usam o JWT, inclusive dentro
-- de RPCs SECURITY DEFINER, para fechar atalhos legados autenticados.
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

create temp table nfe_preparada on commit drop as
select * from f.fn_nfe_preparar_documento_solicitacao('30000000-0000-4000-8000-000000000001');
grant select on nfe_preparada to service_role, authenticated;

create temp table nfe_payload_homologacao_1 on commit drop as
select jsonb_build_object(
  'nome_destinatario', 'NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL',
  'valor_produtos', 200,
  'valor_desconto', 0,
  'valor_frete', 0,
  'valor_seguro', 0,
  'valor_outras_despesas', 0,
  'valor_total', 200,
  'items', jsonb_build_array(jsonb_build_object(
    'numero_item', 1,
    'codigo_ncm', '85365090',
    'cfop', '5102',
    'quantidade_comercial', 2,
    'valor_unitario_comercial', 100,
    'valor_bruto', 200,
    'valor_desconto', 0,
    'valor_total_item', 200,
    'icms_situacao_tributaria', '00',
    'icms_base_calculo', 200,
    'icms_aliquota', 17,
    'icms_valor', 34,
    'ipi_situacao_tributaria', '53',
    'ipi_codigo_enquadramento_legal', '999',
    'pis_situacao_tributaria', '01',
    'pis_base_calculo', 200,
    'pis_aliquota', 1.65,
    'pis_valor', 3.30,
    'cofins_situacao_tributaria', '01',
    'cofins_base_calculo', 200,
    'cofins_aliquota', 7.6,
    'cofins_valor', 15.20,
    'unidade_tributavel', 'UN',
    'ibs_cbs_situacao_tributaria', '000',
    'ibs_cbs_classificacao_tributaria', '000001',
    'ibs_cbs_base_calculo', 200,
    'ibs_uf_aliquota', 0.1,
    'ibs_uf_valor', 0.20,
    'ibs_mun_aliquota', 0,
    'ibs_mun_valor', 0,
    'ibs_valor_total', 0.20,
    'cbs_aliquota', 0.9,
    'cbs_valor', 1.80
  ))
) as payload;

-- A Edge Function chama o wrapper como service_role. O wrapper precisa
-- alcançar a implementacao, que continua proibida para chamada direta.
set local role service_role;

do $$
declare
  v_contexto jsonb;
  v_documento_id uuid := (select documento_fiscal_id from nfe_preparada);
begin
  v_contexto := f.fn_nfe_contexto_emissao(v_documento_id);
  if v_contexto is null or v_contexto->'emissao' is null then
    raise exception 'Wrapper nao devolveu o contexto da emissao.';
  end if;

  begin
    perform f.fn_nfe_contexto_emissao_impl(v_documento_id);
    raise exception 'Implementacao interna ficou acessivel diretamente ao service_role.';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- O documento e os itens do pipeline nao podem ser adulterados pelo cliente.
-- O bloqueio cobre inclusive campos que poderiam forjar autorizacao, valor ou
-- destinatario e continua valendo para DELETE e para todo DML dos itens.
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $dml_direto_bloqueado$
declare
  v_documento_id uuid := (select documento_fiscal_id from nfe_preparada);
begin
  begin
    insert into f.documento_fiscal (
      id, tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo,
      nfe_status, cliente_id, valor_total
    ) values (
      '60000000-0000-4000-8000-000000000099',
      '10000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000001',
      '', 'SAIDA', 'PRODUTO', '55', 'EMITIDA', 910001, 200
    );
    raise exception 'Authenticated conseguiu forjar SAIDA/55 EMITIDA.';
  exception when sqlstate '42501' then null;
  end;

  begin
    update f.documento_fiscal set nfe_status = 'EMITIDA'
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and id = v_documento_id;
    raise exception 'Authenticated conseguiu alterar nfe_status do documento vinculado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    update f.documento_fiscal set valor_total = 999
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and id = v_documento_id;
    raise exception 'Authenticated conseguiu alterar valor do documento vinculado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    update f.documento_fiscal set cliente_id = null
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and id = v_documento_id;
    raise exception 'Authenticated conseguiu alterar cliente do documento vinculado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    delete from f.documento_fiscal
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and id = v_documento_id;
    raise exception 'Authenticated conseguiu excluir documento vinculado.';
  exception when sqlstate '42501' then null;
  end;

  -- O helper legado e SECURITY DEFINER. Quando o papel da fixture o habilita,
  -- o JWT authenticated ainda precisa chegar ao trigger e impedir o atalho.
  if public.has_active_empresa_access(
       '10000000-0000-4000-8000-000000000001',
       '20000000-0000-4000-8000-000000000001'
     ) and (
       public.can('os_rpcs', 'execute')
       or public.has_permission('os.write')
       or public.can('financeiro', 'write')
       or public.has_permission('financeiro.write')
     ) then
    begin
      perform m.venda_vincular_documento_fiscal(910001, v_documento_id);
      raise exception 'RPC legado SECURITY DEFINER alterou documento gerenciado.';
    exception when sqlstate '42501' then null;
    end;
  end if;

  begin
    update f.documento_fiscal_item
    set valor_total = 999
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and documento_fiscal_id = v_documento_id;
    raise exception 'Authenticated conseguiu alterar item vinculado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    delete from f.documento_fiscal_item
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and documento_fiscal_id = v_documento_id;
    raise exception 'Authenticated conseguiu excluir item vinculado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into f.documento_fiscal_item (
      id, tenant_id, empresa_id, documento_fiscal_id, item_n, descricao,
      quantidade, unidade, valor_unitario, valor_total
    ) values (
      '60000000-0000-4000-8000-000000000098',
      '10000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000001',
      v_documento_id, 99, 'ITEM FORJADO', 1, 'UN', 1, 1
    );
    raise exception 'Authenticated conseguiu inserir item em documento vinculado.';
  exception when sqlstate '42501' then null;
  end;

  begin
    insert into f.documento_fiscal_xml (
      tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash
    ) values (
      '10000000-0000-4000-8000-000000000001', v_documento_id,
      repeat('8', 44),
      '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>13671448000189</CNPJ></emit></infNFe></NFe>',
      repeat('a', 64)
    );
    raise exception 'Authenticated conseguiu inserir XML em documento vinculado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, base_calculo, aliquota, valor_calculado
    ) values (
      '10000000-0000-4000-8000-000000000001', v_documento_id,
      'ICMS', 'DEBITO', 200, 200, 17, 34
    );
    raise exception 'Authenticated conseguiu inserir imposto em documento vinculado.';
  exception when sqlstate '42501' then null;
  end;
end;
$dml_direto_bloqueado$;

reset role;

select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $dml_direto_preservou_documento$
declare
  v_documento_id uuid := (select documento_fiscal_id from nfe_preparada);
begin
  if exists (
    select 1 from f.documento_fiscal
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and id = '60000000-0000-4000-8000-000000000099'
  ) then
    raise exception 'Documento forjado permaneceu gravado.';
  end if;
  if not exists (
    select 1 from f.documento_fiscal df
    where df.tenant_id = '10000000-0000-4000-8000-000000000001'
      and df.empresa_id = '20000000-0000-4000-8000-000000000001'
      and df.id = v_documento_id
      and df.nfe_status = 'RASCUNHO'
      and df.valor_total = 200
      and df.cliente_id = 910001
  ) then
    raise exception 'Tentativa de DML direto alterou o documento do pipeline.';
  end if;
  if (select count(*) from f.documento_fiscal_item dfi
      where dfi.tenant_id = '10000000-0000-4000-8000-000000000001'
        and dfi.empresa_id = '20000000-0000-4000-8000-000000000001'
        and dfi.documento_fiscal_id = v_documento_id) <> 1 then
    raise exception 'Tentativa de DML direto alterou os itens do pipeline.';
  end if;
  if exists (
       select 1 from f.documento_fiscal_xml dfx
       where dfx.tenant_id = '10000000-0000-4000-8000-000000000001'
         and dfx.documento_fiscal_id = v_documento_id
     )
     or exists (
       select 1 from f.documento_fiscal_imposto dfi
       where dfi.tenant_id = '10000000-0000-4000-8000-000000000001'
         and dfi.documento_fiscal_id = v_documento_id
     ) then
    raise exception 'Tentativa de DML direto criou XML ou imposto no pipeline.';
  end if;
end;
$dml_direto_preservou_documento$;

do $$
declare
  v_primeiro record;
  v_segundo record;
begin
  select * into v_primeiro from nfe_preparada;
  select * into v_segundo from f.fn_nfe_preparar_documento_solicitacao('30000000-0000-4000-8000-000000000001');
  if v_primeiro.documento_fiscal_id is distinct from v_segundo.documento_fiscal_id
     or v_segundo.criado is distinct from false then
    raise exception 'Idempotencia da preparacao falhou: primeiro %, segundo %', row_to_json(v_primeiro), row_to_json(v_segundo);
  end if;
  if v_primeiro.referencia_externa <> 'NFEH-30000000-0000-4000-8000-000000000001' then
    raise exception 'Referencia externa inesperada: %', v_primeiro.referencia_externa;
  end if;
end;
$$;

create temp table nfe_homologacao_claim_1 on commit drop as
select f.fn_nfe_homologacao_claimar(
  (select documento_fiscal_id from nfe_preparada),
  (select payload from nfe_payload_homologacao_1),
  false
) as claim;

do $claim_homologacao_1$
declare
  v_claim jsonb := (select claim from nfe_homologacao_claim_1);
  v_perdedor jsonb;
  v_retry jsonb;
begin
  if coalesce((v_claim->>'deve_enviar')::boolean, false) is not true
     or v_claim->>'status' <> 'ENVIANDO'
     or (v_claim->>'tentativa_count')::integer <> 1 then
    raise exception 'Primeiro claim HOM invalido: %', v_claim;
  end if;
  v_perdedor := f.fn_nfe_homologacao_claimar(
    (select documento_fiscal_id from nfe_preparada),
    (select payload from nfe_payload_homologacao_1),
    false
  );
  if coalesce((v_perdedor->>'deve_enviar')::boolean, true)
     or coalesce((v_perdedor->>'aguardar')::boolean, false) is not true
     or (v_perdedor->>'tentativa_count')::integer <> 1 then
    raise exception 'Perdedor concorrente HOM nao aguardou o claim recente: %', v_perdedor;
  end if;

  update f.documento_fiscal_emissao
  set ultima_tentativa_em = clock_timestamp() - interval '3 minutes'
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and documento_fiscal_id = (select documento_fiscal_id from nfe_preparada);
  begin
    perform f.fn_nfe_homologacao_claimar(
      (select documento_fiscal_id from nfe_preparada),
      (select payload from nfe_payload_homologacao_1),
      false
    );
    raise exception 'Retry HOM sem GET/reconciliacao abriu novo POST.';
  exception when sqlstate '55000' then null;
  end;

  v_retry := f.fn_nfe_homologacao_claimar(
    (select documento_fiscal_id from nfe_preparada),
    (select payload from nfe_payload_homologacao_1),
    true
  );
  if coalesce((v_retry->>'deve_enviar')::boolean, false) is not true
     or (v_retry->>'tentativa_count')::integer <> 2 then
    raise exception 'Retry HOM reconciliado nao abriu novo claim: %', v_retry;
  end if;
end;
$claim_homologacao_1$;

-- Um RPC SECURITY DEFINER nao pode reabrir nem recalcular o material fiscal
-- depois do claim. O snapshot integral e as contagens demonstram que a falha
-- 55000 acontece antes de qualquer efeito parcial em SF/SI ou seus artefatos.
create temp table nfe_material_pos_claim_snapshot on commit drop as
select
  (select to_jsonb(sf)
   from f.solicitacao_faturamento sf
   where sf.tenant_id = '10000000-0000-4000-8000-000000000001'
     and sf.empresa_id = '20000000-0000-4000-8000-000000000001'
     and sf.id = '30000000-0000-4000-8000-000000000001') as solicitacao,
  (select coalesce(jsonb_agg(to_jsonb(si) order by si.id), '[]'::jsonb)
   from f.solicitacao_item si
   where si.tenant_id = '10000000-0000-4000-8000-000000000001'
     and si.empresa_id = '20000000-0000-4000-8000-000000000001'
     and si.solicitacao_id = '30000000-0000-4000-8000-000000000001') as itens,
  (select count(*) from f.solicitacao_faturamento sf
   where sf.tenant_id = '10000000-0000-4000-8000-000000000001'
     and sf.empresa_id = '20000000-0000-4000-8000-000000000001') as sf_count,
  (select count(*) from f.solicitacao_item si
   where si.tenant_id = '10000000-0000-4000-8000-000000000001'
     and si.empresa_id = '20000000-0000-4000-8000-000000000001') as si_count,
  (select count(*) from f.documento_fiscal df
   where df.tenant_id = '10000000-0000-4000-8000-000000000001'
     and df.empresa_id = '20000000-0000-4000-8000-000000000001') as df_count,
  (select count(*) from f.documento_fiscal_item dfi
   where dfi.tenant_id = '10000000-0000-4000-8000-000000000001'
     and dfi.empresa_id = '20000000-0000-4000-8000-000000000001') as dfi_count,
  (select count(*) from f.documento_fiscal_emissao dfe
   where dfe.tenant_id = '10000000-0000-4000-8000-000000000001'
     and dfe.empresa_id = '20000000-0000-4000-8000-000000000001') as dfe_count;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
do $material_pos_claim_bloqueado$
begin
  begin
    perform f.fn_solicitacao_nfe_congelar_cadastro(
      '30000000-0000-4000-8000-000000000001'
    );
    raise exception 'RPC SECURITY DEFINER recalculou material fiscal depois do claim.';
  exception when sqlstate '55000' then null;
  end;
end;
$material_pos_claim_bloqueado$;
reset role;

select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $material_pos_claim_preservado$
declare
  v_solicitacao jsonb;
  v_itens jsonb;
begin
  select to_jsonb(sf) into v_solicitacao
  from f.solicitacao_faturamento sf
  where sf.tenant_id = '10000000-0000-4000-8000-000000000001'
    and sf.empresa_id = '20000000-0000-4000-8000-000000000001'
    and sf.id = '30000000-0000-4000-8000-000000000001';
  select coalesce(jsonb_agg(to_jsonb(si) order by si.id), '[]'::jsonb) into v_itens
  from f.solicitacao_item si
  where si.tenant_id = '10000000-0000-4000-8000-000000000001'
    and si.empresa_id = '20000000-0000-4000-8000-000000000001'
    and si.solicitacao_id = '30000000-0000-4000-8000-000000000001';

  if v_solicitacao is distinct from (select solicitacao from nfe_material_pos_claim_snapshot)
     or v_itens is distinct from (select itens from nfe_material_pos_claim_snapshot)
     or (select count(*) from f.solicitacao_faturamento sf
         where sf.tenant_id = '10000000-0000-4000-8000-000000000001'
           and sf.empresa_id = '20000000-0000-4000-8000-000000000001')
        <> (select sf_count from nfe_material_pos_claim_snapshot)
     or (select count(*) from f.solicitacao_item si
         where si.tenant_id = '10000000-0000-4000-8000-000000000001'
           and si.empresa_id = '20000000-0000-4000-8000-000000000001')
        <> (select si_count from nfe_material_pos_claim_snapshot)
     or (select count(*) from f.documento_fiscal df
         where df.tenant_id = '10000000-0000-4000-8000-000000000001'
           and df.empresa_id = '20000000-0000-4000-8000-000000000001')
        <> (select df_count from nfe_material_pos_claim_snapshot)
     or (select count(*) from f.documento_fiscal_item dfi
         where dfi.tenant_id = '10000000-0000-4000-8000-000000000001'
           and dfi.empresa_id = '20000000-0000-4000-8000-000000000001')
        <> (select dfi_count from nfe_material_pos_claim_snapshot)
     or (select count(*) from f.documento_fiscal_emissao dfe
         where dfe.tenant_id = '10000000-0000-4000-8000-000000000001'
           and dfe.empresa_id = '20000000-0000-4000-8000-000000000001')
        <> (select dfe_count from nfe_material_pos_claim_snapshot) then
    raise exception 'Bloqueio pos-claim alterou snapshot ou contagens do material fiscal.';
  end if;
end;
$material_pos_claim_preservado$;

select f.fn_nfe_registrar_envio(
  (select documento_fiscal_id from nfe_preparada),
  (select payload from nfe_payload_homologacao_1),
  '{"status":"processando_autorizacao"}'::jsonb,
  'PROCESSANDO'
);

select f.fn_nfe_aplicar_retorno(
  'NFEH-30000000-0000-4000-8000-000000000001',
  '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', repeat('1', 44), '123456789012345', 1, 2, 100,
  'Autorizado o uso da NF-e', 'teste/nfe.xml', 'teste/danfe.pdf',
  '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>13671448000189</CNPJ></emit></infNFe></NFe>',
  'CALLBACK'
);

-- Callback repetido atualiza a mesma emissao e o mesmo XML.
select f.fn_nfe_aplicar_retorno(
  'NFEH-30000000-0000-4000-8000-000000000001',
  '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', repeat('1', 44), '123456789012345', 1, 2, 100,
  'Autorizado o uso da NF-e', 'teste/nfe.xml', 'teste/danfe.pdf',
  '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>13671448000189</CNPJ></emit></infNFe></NFe>',
  'CALLBACK'
);

do $$
declare
  v_documento_id uuid := (select documento_fiscal_id from nfe_preparada);
  v_doc record;
  v_emissao record;
  v_xml_count integer;
  v_titulo_count integer;
  v_snapshot timestamptz;
  v_cst_ibs_cbs text;
  v_cclass_trib text;
  v_cclass_trib_versao text;
  v_imposto_count integer;
  v_auditoria jsonb;
  v_saldo_item numeric;
begin
  select * into v_doc from f.documento_fiscal
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and id = v_documento_id;
  select * into v_emissao from f.documento_fiscal_emissao
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and documento_fiscal_id = v_documento_id;
  select count(*) into v_xml_count from f.documento_fiscal_xml where tenant_id = v_doc.tenant_id and documento_fiscal_id = v_documento_id and deleted_at is null;
  select count(*) into v_titulo_count from f.titulo where tenant_id = v_doc.tenant_id and empresa_id = v_doc.empresa_id and documento_fiscal_id = v_documento_id and deleted_at is null;
  select max(snapshot_fiscal_em), max(cst_ibs_cbs), max(cclass_trib), max(cclass_trib_versao)
    into v_snapshot, v_cst_ibs_cbs, v_cclass_trib, v_cclass_trib_versao
  from f.documento_fiscal_item
  where tenant_id = v_doc.tenant_id
    and empresa_id = v_doc.empresa_id
    and documento_fiscal_id = v_documento_id;
  select count(*) into v_imposto_count
  from f.documento_fiscal_imposto
  where tenant_id = v_doc.tenant_id
    and documento_fiscal_id = v_documento_id
    and deleted_at is null;
  select s.saldo into v_saldo_item
  from f.fn_os_itens_saldo_a_faturar(v_doc.tenant_id, v_doc.empresa_id, 910001) s
  where s.os_item_id = 910001;

  if v_doc.chave_acesso <> repeat('1', 44) or v_doc.numero <> '1' or v_doc.serie <> '2' then
    raise exception 'Conversao/swap da chave, numero e serie falhou: %', row_to_json(v_doc);
  end if;
  if v_doc.nfe_status <> 'RASCUNHO' or v_emissao.status <> 'AUTORIZADA' then
    raise exception 'Homologacao alterou status incorreto: documento %, emissao %', v_doc.nfe_status, v_emissao.status;
  end if;
  if v_xml_count <> 1 then raise exception 'Esperado um XML persistido, encontrado %', v_xml_count; end if;
  if v_titulo_count <> 0 then raise exception 'Homologacao criou % titulo(s) financeiro(s).', v_titulo_count; end if;
  if v_snapshot is null then raise exception 'Snapshot fiscal por item nao foi gravado.'; end if;
  if v_cst_ibs_cbs <> '000' or v_cclass_trib <> '000001' or v_cclass_trib_versao <> 'NT 2025.002 v1.34' then
    raise exception 'Snapshot IBS/CBS incompleto: CST %, cClassTrib %, versao %.', v_cst_ibs_cbs, v_cclass_trib, v_cclass_trib_versao;
  end if;
  if v_imposto_count <> 5 then raise exception 'Esperados ICMS, PIS, COFINS, IBS e CBS; encontrados %.', v_imposto_count; end if;
  v_auditoria := f.fn_nfe_auditar_documento(v_documento_id);
  if jsonb_array_length(v_auditoria->'titulos') <> 0
     or jsonb_array_length(v_auditoria->'impostos') <> 5 then
    raise exception 'RPC de auditoria devolveu efeitos incorretos: %', v_auditoria;
  end if;
  if v_saldo_item <> 0 then raise exception 'Homologacao autorizada deixou de reservar o saldo comercial da OV: saldo %.', v_saldo_item; end if;
end;
$$;

-- O cancelamento fiscal grava claim antes da rede, mantem HOM AUTORIZADA
-- durante a incerteza e exige reconciliacao/correlacao forte no retry.
create temp table nfe_cancelamento_claim on commit drop as
select f.fn_nfe_cancelamento_homologacao_claim(
  (select documento_fiscal_id from nfe_preparada),
  'Cancelamento controlado do primeiro cenario',
  null
) as claim;

do $cancelamento_claim_fresco$
declare v_claim jsonb := (select claim from nfe_cancelamento_claim); v_segundo jsonb;
begin
  if coalesce((v_claim->>'deve_cancelar')::boolean, false) is not true
     or nullif(v_claim->>'evento_claim_id', '') is null then
    raise exception 'Primeiro claim de cancelamento invalido: %', v_claim;
  end if;
  if (select status from f.documento_fiscal_emissao
      where documento_fiscal_id = (select documento_fiscal_id from nfe_preparada)) <> 'AUTORIZADA' then
    raise exception 'Claim alterou o estado fiscal antes da resposta da Focus.';
  end if;
  v_segundo := f.fn_nfe_cancelamento_homologacao_claim(
    (select documento_fiscal_id from nfe_preparada),
    'Cancelamento controlado do primeiro cenario',
    null
  );
  if coalesce((v_segundo->>'deve_cancelar')::boolean, true)
     or coalesce((v_segundo->>'aguardar')::boolean, false) is not true
     or v_segundo->>'evento_claim_id' is distinct from v_claim->>'evento_claim_id' then
    raise exception 'Concorrente do claim fresco nao aguardou: %', v_segundo;
  end if;
end;
$cancelamento_claim_fresco$;

-- Envelhecimento controlado, somente dentro da transacao de teste, simula
-- timeout/crash depois do DELETE sem violar a trilha persistida em producao.
alter table f.documento_fiscal_evento disable trigger documento_fiscal_evento_append_only;
update f.documento_fiscal_evento
set created_at = clock_timestamp() - interval '3 minutes'
where id = ((select claim from nfe_cancelamento_claim)->>'evento_claim_id')::uuid;
alter table f.documento_fiscal_evento enable trigger documento_fiscal_evento_append_only;

do $cancelamento_claim_stale$
declare
  v_antigo uuid := ((select claim from nfe_cancelamento_claim)->>'evento_claim_id')::uuid;
  v_reconciliar jsonb;
  v_novo jsonb;
  v_novo_id uuid;
begin
  v_reconciliar := f.fn_nfe_cancelamento_homologacao_claim(
    (select documento_fiscal_id from nfe_preparada),
    'Cancelamento controlado do primeiro cenario',
    null
  );
  if coalesce((v_reconciliar->>'deve_reconciliar')::boolean, false) is not true
     or v_reconciliar->>'evento_claim_id' is distinct from v_antigo::text then
    raise exception 'Claim stale nao exigiu GET/correlacao antes de novo DELETE: %', v_reconciliar;
  end if;

  v_novo := f.fn_nfe_cancelamento_homologacao_claim(
    (select documento_fiscal_id from nfe_preparada),
    'Cancelamento controlado do primeiro cenario',
    v_antigo
  );
  v_novo_id := nullif(v_novo->>'evento_claim_id', '')::uuid;
  if coalesce((v_novo->>'deve_cancelar')::boolean, false) is not true
     or v_novo_id is null or v_novo_id = v_antigo then
    raise exception 'Retry reconciliado nao obteve novo claim CAS: %', v_novo;
  end if;

  begin
    perform f.fn_nfe_cancelamento_homologacao_finalizar(
      (select documento_fiscal_id from nfe_preparada), v_antigo,
      'AUTORIZADA', 'Cancelamento controlado do primeiro cenario',
      'PROTOCOLO-ATRASADO', '{"status":"cancelado"}'::jsonb
    );
    raise exception 'Resposta tardia do claim anterior finalizou o claim mais recente.';
  exception when sqlstate '55000' then null;
  end;

  perform f.fn_nfe_cancelamento_homologacao_finalizar(
    (select documento_fiscal_id from nfe_preparada), v_novo_id,
    'AUTORIZADA', 'Cancelamento controlado do primeiro cenario',
    'PROTOCOLO-CANCELAMENTO-TESTE', '{"status":"cancelado"}'::jsonb
  );
end;
$cancelamento_claim_stale$;

-- CANCELADA e terminal: callback AUTORIZADA tardio vira incidente append-only,
-- sem reabrir emissao/documento/solicitacao nem criar efeito financeiro.
select f.fn_nfe_aplicar_retorno(
  'NFEH-30000000-0000-4000-8000-000000000001',
  '{"status":"autorizado","origem":"callback_tardio"}'::jsonb,
  'AUTORIZADA', repeat('9', 44), 'PROTOCOLO-TARDIO', 99, 1, 100,
  'Autorizacao tardia apos cancelamento', 'teste/tardio.xml', 'teste/tardio.pdf',
  '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe/></NFe>',
  'CALLBACK'
);

do $$
declare v_saldo numeric; v_documento_id uuid := (select documento_fiscal_id from nfe_preparada);
begin
  if (select status from f.solicitacao_faturamento
      where tenant_id = '10000000-0000-4000-8000-000000000001'
        and empresa_id = '20000000-0000-4000-8000-000000000001'
        and id = '30000000-0000-4000-8000-000000000001') <> 'CANCELADA' then
    raise exception 'Cancelamento da homologacao nao cancelou a solicitacao.';
  end if;
  if (select status from f.documento_fiscal_emissao
      where tenant_id = '10000000-0000-4000-8000-000000000001'
        and empresa_id = '20000000-0000-4000-8000-000000000001'
        and documento_fiscal_id = v_documento_id) <> 'CANCELADA'
     -- Homologacao cancelada na SEFAZ nao vira documento CANCELADA: continua
     -- RASCUNHO para nunca entrar no livro de saidas nem no analitico.
     or (select nfe_status from f.documento_fiscal
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001'
           and id = v_documento_id) <> 'RASCUNHO' then
    raise exception 'Callback tardio reabriu emissao ou documento cancelado.';
  end if;
  if (select chave_acesso from f.documento_fiscal_emissao
      where tenant_id = '10000000-0000-4000-8000-000000000001'
        and empresa_id = '20000000-0000-4000-8000-000000000001'
        and documento_fiscal_id = v_documento_id) <> repeat('1', 44)
     or (select chave_acesso from f.documento_fiscal
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001'
           and id = v_documento_id) <> repeat('1', 44)
     or (select count(*) from f.documento_fiscal_xml
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and documento_fiscal_id = v_documento_id and deleted_at is null) <> 1 then
    raise exception 'Callback tardio sobrescreveu chave ou XML da NF-e cancelada.';
  end if;
  if exists (
    select 1 from f.titulo
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and empresa_id = '20000000-0000-4000-8000-000000000001'
      and documento_fiscal_id = v_documento_id and deleted_at is null
  ) then
    raise exception 'Callback tardio criou titulo para homologacao cancelada.';
  end if;
  if not exists (
    select 1 from f.documento_fiscal_evento ev
    where ev.tenant_id = '10000000-0000-4000-8000-000000000001'
      and ev.empresa_id = '20000000-0000-4000-8000-000000000001'
      and ev.documento_fiscal_id = v_documento_id
      and ev.tipo = 'CONSULTA'
      and ev.status = 'INCIDENTE_RETORNO_TARDIO'
      and coalesce((ev.resposta->>'cancelada_terminal')::boolean, false)
  ) then
    raise exception 'Callback tardio nao foi preservado como incidente append-only.';
  end if;
  select s.saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001', 910001
  ) s where s.os_item_id = 910001;
  if v_saldo <> 2 then raise exception 'Cancelamento da homologacao nao devolveu o saldo: %.', v_saldo; end if;
end;
$$;

-- O cancelamento local autenticado tambem e idempotente e libera a reserva
-- sem apagar solicitacao, itens, documento ou trilha fiscal.
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

insert into f.solicitacao_faturamento (
  id, tenant_id, empresa_id, cliente_id, status, natureza_operacao,
  finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
  valor_frete, valor_seguro, valor_outras_despesas,
  destinacao_mercadoria, pagamento_forma, pagamento_indicador
) values (
  '30000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  910001, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS',
  1, 0, 9, 9, 0, 0, 0,
  'REVENDA', '15', 1
);
insert into f.solicitacao_item (
  id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, origem_item_id,
  item_id, descricao, quantidade, unidade, valor_unitario, valor_desconto, ordem
) values (
  '40000000-0000-4000-8000-000000000003',
  '30000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'OV', '910001', '910001', 910001, 'ITEM TESTE NFE', 1, 'UN', 100, 0, 1
);

-- A variante local permitida inclui HOM RASCUNHO nunca claimada. A RPC deve
-- cancelar essa emissao/documento sem apagar a trilha nem chamar a SEFAZ.
insert into f.documento_fiscal (
  id, tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo,
  nfe_status, cliente_id, valor_total, valor_produtos
) values (
  '60000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'PENDENTE:NFEH-30000000-0000-4000-8000-000000000003',
  'SAIDA', 'PRODUTO', '55', 'RASCUNHO', 910001, 100, 100
);
insert into f.documento_fiscal_emissao (
  documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
  referencia_externa, ambiente, status
) values (
  '60000000-0000-4000-8000-000000000003',
  '30000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'NFEH-30000000-0000-4000-8000-000000000003', 'HOMOLOGACAO', 'RASCUNHO'
);

do $$
declare v_resultado jsonb; v_saldo numeric;
begin
  select s.saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001', 910001
  ) s where s.os_item_id = 910001;
  if v_saldo <> 1 then raise exception 'Rascunho nao reservou uma unidade: %.', v_saldo; end if;

  begin
    perform f.fn_solicitacao_nfe_cancelar_rascunho(
      '30000000-0000-4000-8000-000000000003', 'curto'
    );
    raise exception 'Backend aceitou motivo local com menos de 15 caracteres.';
  exception when sqlstate '22023' then null;
  end;

  v_resultado := f.fn_solicitacao_nfe_cancelar_rascunho(
    '30000000-0000-4000-8000-000000000003', 'Teste de devolucao do saldo'
  );
  if v_resultado->>'status' <> 'CANCELADA' or coalesce((v_resultado->>'idempotente')::boolean, true) then
    raise exception 'RPC nao cancelou o rascunho: %', v_resultado;
  end if;
  if (v_resultado->>'emissoes_canceladas')::integer <> 1
     or (v_resultado->>'documentos_cancelados')::integer <> 1
     or (select status from f.documento_fiscal_emissao
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001'
           and documento_fiscal_id = '60000000-0000-4000-8000-000000000003') <> 'CANCELADA'
     or (select nfe_status from f.documento_fiscal
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001'
           and id = '60000000-0000-4000-8000-000000000003') <> 'CANCELADA' then
    raise exception 'RPC nao descartou exatamente a HOM RASCUNHO nunca tentada: %', v_resultado;
  end if;
  v_resultado := f.fn_solicitacao_nfe_cancelar_rascunho(
    '30000000-0000-4000-8000-000000000003', 'Teste de devolucao do saldo'
  );
  if not coalesce((v_resultado->>'idempotente')::boolean, false) then
    raise exception 'Segundo cancelamento do rascunho nao foi idempotente: %', v_resultado;
  end if;

  select s.saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001', 910001
  ) s where s.os_item_id = 910001;
  if v_saldo <> 2 then raise exception 'Cancelamento local nao devolveu o saldo: %.', v_saldo; end if;
end;
$$;

-- HOM ERRO representa tentativa possivelmente aceita pelo provedor e nunca
-- pode ser descartada pelo atalho local, mesmo que a solicitacao esteja editavel.
insert into f.solicitacao_faturamento (
  id, tenant_id, empresa_id, cliente_id, status, natureza_operacao,
  finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
  valor_frete, valor_seguro, valor_outras_despesas,
  destinacao_mercadoria, pagamento_forma, pagamento_indicador
) values (
  '30000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  910001, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS',
  1, 0, 9, 9, 0, 0, 0,
  'REVENDA', '15', 1
);
insert into f.documento_fiscal (
  id, tenant_id, empresa_id, chave_acesso, operacao, natureza, modelo,
  nfe_status, cliente_id, valor_total, valor_produtos
) values (
  '60000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'PENDENTE:NFEH-30000000-0000-4000-8000-000000000004',
  'SAIDA', 'PRODUTO', '55', 'RASCUNHO', 910001, 100, 100
);
insert into f.documento_fiscal_emissao (
  documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
  referencia_externa, ambiente, status, tentativa_count, payload_enviado,
  enviado_em, ultima_tentativa_em
) values (
  '60000000-0000-4000-8000-000000000004',
  '30000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'NFEH-30000000-0000-4000-8000-000000000004', 'HOMOLOGACAO', 'ERRO', 1,
  '{"tentativa":"persistida"}'::jsonb, now(), now()
);

do $hom_erro_nao_descartavel$
begin
  begin
    perform f.fn_solicitacao_nfe_cancelar_rascunho(
      '30000000-0000-4000-8000-000000000004',
      'Tentativa fiscal incerta deve ser reconciliada'
    );
    raise exception 'Fluxo local descartou uma HOM em ERRO.';
  exception when sqlstate '55000' then null;
  end;
  if (select status from f.solicitacao_faturamento
      where tenant_id = '10000000-0000-4000-8000-000000000001'
        and empresa_id = '20000000-0000-4000-8000-000000000001'
        and id = '30000000-0000-4000-8000-000000000004') <> 'RASCUNHO'
     or (select status from f.documento_fiscal_emissao
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001'
           and documento_fiscal_id = '60000000-0000-4000-8000-000000000004') <> 'ERRO' then
    raise exception 'Tentativa de descarte alterou HOM ERRO ou solicitacao.';
  end if;
end;
$hom_erro_nao_descartavel$;

-- Producao: exige a homologacao autorizada da mesma solicitacao e perfil
-- explicitamente liberado; cria AR (nunca AP) somente depois da autorizacao.
insert into f.plano_contas (tenant_id, codigo, nome, natureza, tipo)
values ('10000000-0000-4000-8000-000000000001', '3.01', 'RECEITA DE VENDAS', 'CREDITO', 'ANALITICA');

insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop,
  origem, cst_completo, cst_icms, aliquota_icms_observada,
  aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa,
  justificativa_faixa
) values (
  '50000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'faturamento_nfe_pipeline.sql', 1, 'Venda de mercadoria', '5102',
  0, '000', '00', 17, 5, false, 1, 1, array['85365090'], array[1],
  'Cenario controlado do pipeline', 'REVISAO', 'Revisao fiscal obrigatoria'
);

insert into f.solicitacao_faturamento (
  id, tenant_id, empresa_id, cliente_id, status, natureza_operacao,
  finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
  valor_frete, valor_seguro, valor_outras_despesas,
  destinacao_mercadoria, pagamento_forma, pagamento_indicador
) values (
  '30000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  910001, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS',
  1, 0, 9, 9, 0, 0, 0,
  'REVENDA', '15', 1
);

-- O cenario de producao abaixo exercita IPI tributado no perfil de operacao.
update public.fiscal_itens
set cst_ipi = '50', aliq_ipi = 5
where tenant_id = '10000000-0000-4000-8000-000000000001'
  and empresa_id = '20000000-0000-4000-8000-000000000001'
  and item_id = 910001;

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao,
  natureza_texto, crt, cfop_interno, cst_icms, cst_ipi, ipi_codigo_enquadramento_legal, cst_pis, cst_cofins,
  evidencia_id, faixa_automacao, habilitado_producao, ambito_destino, ufs_destino,
  indicador_ie_destinatario, origem_mercadoria, icms_modalidade_base_calculo,
  aliquota_icms, aliquota_ipi, reducao_base_icms_percentual, aliquota_pis, aliquota_cofins,
  finalidade_emissao, consumidor_final, cbenef_aplicacao
) values (
  '50000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'VENDA-INTERNA-TESTE', 'Venda interna teste', 'NFE',
  'VENDA_MERCADORIA_TERCEIROS', 'VENDA DE MERCADORIA', '3', '5102',
  '00', '50', '999', '01', '01', '50000000-0000-4000-8000-000000000002',
  'REVISAO', false, 'INTERNA', array['SC'], '1', 0,
  '3', 17, 5, 0, 1.65, 7.6, 1, 0, 'SEM_BENEFICIO'
);

set local role authenticated;
select f.fn_perfil_operacao_nfe_revisar(
  '50000000-0000-4000-8000-000000000001',
  '000', '000001', 'NT 2025.002 v1.34', 0.1, 0, 0.9,
  'Revisao fiscal controlada antes da homologacao do pipeline.'
);
reset role;

insert into f.solicitacao_item (
  id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, origem_item_id,
  item_id, descricao, ncm, cfop, cst_icms, cst_ipi, ipi_codigo_enquadramento_legal, cst_pis, cst_cofins,
  quantidade, unidade, valor_unitario, valor_desconto,
  icms_modalidade_base_calculo, aliquota_icms, aliquota_ipi, aliquota_pis, aliquota_cofins,
  cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json, ordem
) values (
  '40000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'OV', '910001', '910001', 910001, 'ITEM TESTE NFE', '85365090',
  '5102', '00', '50', '999', '01', '01', 2, 'UN', 100, 0,
  '3', 17, 5, 1.65, 7.6, '000', '000001', 'NT 2025.002 v1.34',
  '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb, 1
);

select f.fn_solicitacao_nfe_salvar_conferencia_2026(
  '30000000-0000-4000-8000-000000000002',
  '{"destino_uf_confirmada":"SC","finalidade_emissao":1,"consumidor_final":0,"presenca_comprador":9,"modalidade_frete":9,"valor_frete":0,"valor_seguro":0,"valor_outras_despesas":0,"destinacao_mercadoria":"REVENDA","pagamento_forma":"15","pagamento_indicador":1}'::jsonb,
  '[{"id":"40000000-0000-4000-8000-000000000002","perfil_operacao_id":"50000000-0000-4000-8000-000000000001","cfop":"5102","cst_icms":"00","cst_ipi":"50","ipi_codigo_enquadramento_legal":"999","cst_pis":"01","cst_cofins":"01","cbenef":null,"reducao_base_icms_percentual":0,"icms_modalidade_base_calculo":"3","aliquota_icms":17,"aliquota_ipi":5,"aliquota_pis":1.65,"aliquota_cofins":7.6,"cst_ibs_cbs":"000","cclass_trib":"000001","ibs_cbs_json":{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9},"numero_fci":null}]'::jsonb
);

do $$
declare v_versao text;
begin
  select cclass_trib_versao into v_versao
  from f.solicitacao_item
  where id = '40000000-0000-4000-8000-000000000002';
  if v_versao is not null then
    raise exception 'A versao da NT foi gravada indevidamente no novo fluxo: %', v_versao;
  end if;
end;
$$;
select f.fn_solicitacao_nfe_salvar_transporte(
  '30000000-0000-4000-8000-000000000002',
  '{"transportador":null,"volumes":[]}'::jsonb
);
select f.fn_solicitacao_nfe_congelar_cadastro('30000000-0000-4000-8000-000000000002');

do $$
declare v_operacao jsonb;
begin
  select operacao_snapshot into v_operacao
  from f.solicitacao_faturamento
  where id = '30000000-0000-4000-8000-000000000002';
  if v_operacao->'transportador' <> 'null'::jsonb
     or v_operacao->'volumes' <> 'null'::jsonb then
    raise exception 'modFrete 9 deveria congelar transporte e volumes nulos: %', v_operacao;
  end if;
end;
$$;

do $$
declare v_prontidao jsonb;
begin
  v_prontidao := f.fn_nfe_producao_pronta('30000000-0000-4000-8000-000000000002');
  if coalesce((v_prontidao->>'pronta')::boolean, false)
     or position('AUTORIZADA em homologacao' in coalesce(v_prontidao->>'motivo', '')) = 0 then
    raise exception 'Producao nao bloqueou a ausencia de homologacao autorizada: %', v_prontidao;
  end if;
end;
$$;

-- A mesma solicitacao passa primeiro por homologacao. A autorizacao mantem a
-- reserva comercial e nao cria Contas a Receber.
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

create temp table nfe_homologacao_producao on commit drop as
select * from f.fn_nfe_preparar_documento_solicitacao('30000000-0000-4000-8000-000000000002');

create temp table nfe_payload_homologacao_producao on commit drop as
select jsonb_build_object(
  'nome_destinatario', 'NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL',
  'valor_produtos', 200,
  'valor_desconto', 0,
  'valor_frete', 0,
  'valor_seguro', 0,
  'valor_outras_despesas', 0,
  'valor_total', 210,
  'items', jsonb_build_array(jsonb_build_object(
    'numero_item', 1,
    'codigo_ncm', '85365090',
    'cfop', '5102',
    'quantidade_comercial', 2,
    'valor_unitario_comercial', 100,
    'valor_bruto', 200,
    'valor_desconto', 0,
    -- vItem = mercadoria + IPI, como o builder passou a montar em 10/09/2026 para o
    -- vNFTot fechar com a soma dos itens (NT 2025.002-RTC, rejeicao 1094): 200 + 10.
    'valor_total_item', 210,
    'icms_situacao_tributaria', '00',
    'icms_base_calculo', 200,
    'icms_aliquota', 17,
    'icms_valor', 34,
    'ipi_situacao_tributaria', '50',
    'ipi_codigo_enquadramento_legal', '999',
    'ipi_base_calculo', 200,
    'ipi_aliquota', 5,
    'ipi_valor', 10,
    'pis_situacao_tributaria', '01',
    'pis_base_calculo', 200,
    'pis_aliquota', 1.65,
    'pis_valor', 3.30,
    'cofins_situacao_tributaria', '01',
    'cofins_base_calculo', 200,
    'cofins_aliquota', 7.6,
    'cofins_valor', 15.20,
    'unidade_tributavel', 'UN',
    'ibs_cbs_situacao_tributaria', '000',
    'ibs_cbs_classificacao_tributaria', '000001',
    'ibs_cbs_base_calculo', 200,
    'ibs_uf_aliquota', 0.1,
    'ibs_uf_valor', 0.20,
    'ibs_mun_aliquota', 0,
    'ibs_mun_valor', 0,
    'ibs_valor_total', 0.20,
    'cbs_aliquota', 0.9,
    'cbs_valor', 1.80
  ))
) as payload;

create temp table nfe_homologacao_producao_claim on commit drop as
select f.fn_nfe_homologacao_claimar(
  (select documento_fiscal_id from nfe_homologacao_producao),
  (select payload from nfe_payload_homologacao_producao),
  false
) as claim;

do $claim_homologacao_producao$
declare v_claim jsonb := (select claim from nfe_homologacao_producao_claim);
begin
  if coalesce((v_claim->>'deve_enviar')::boolean, false) is not true
     or v_claim->>'status' <> 'ENVIANDO'
     or (v_claim->>'tentativa_count')::integer <> 1 then
    raise exception 'Claim HOM anterior a promocao invalido: %', v_claim;
  end if;
end;
$claim_homologacao_producao$;

select f.fn_nfe_registrar_envio(
  (select documento_fiscal_id from nfe_homologacao_producao),
  (select payload from nfe_payload_homologacao_producao),
  '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', 100, 'Autorizado o uso da NF-e'
);

do $hom_autorizada_so_no_apply$
begin
  if (select status from f.documento_fiscal_emissao
      where documento_fiscal_id = (select documento_fiscal_id from nfe_homologacao_producao)) <> 'PROCESSANDO' then
    raise exception 'Registrar envio materializou AUTORIZADA antes de chave/XML da homologacao.';
  end if;
end;
$hom_autorizada_so_no_apply$;

select f.fn_nfe_aplicar_retorno(
  'NFEH-30000000-0000-4000-8000-000000000002',
  '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', repeat('3', 44), '323456789012345', 9, 2, 100,
  'Autorizado o uso da NF-e', 'teste/homologacao.xml', 'teste/homologacao.pdf',
  '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>13671448000189</CNPJ></emit></infNFe></NFe>',
  'ENVIO'
);

-- now() e constante na transacao de teste; representa que a autorizacao da
-- SEFAZ ocorreu depois da revisao do perfil.
update f.documento_fiscal_emissao
set autorizado_em = clock_timestamp() + interval '1 second'
where tenant_id = '10000000-0000-4000-8000-000000000001'
  and empresa_id = '20000000-0000-4000-8000-000000000001'
  and documento_fiscal_id = (select documento_fiscal_id from nfe_homologacao_producao);

do $$
declare v_prontidao jsonb; v_saldo numeric;
begin
  if not exists (
    select 1 from f.documento_fiscal_imposto dfi
    where dfi.tenant_id = '10000000-0000-4000-8000-000000000001'
      and dfi.documento_fiscal_id = (select documento_fiscal_id from nfe_homologacao_producao)
      and dfi.imposto = 'IPI'
      and dfi.base_calculo = 200
      and dfi.aliquota = 5
      and dfi.valor_calculado = 10
      and dfi.deleted_at is null
  ) then
    raise exception 'Homologacao nao materializou o IPI tributado de 5%% antes da promocao.';
  end if;
  select s.saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001', 910001
  ) s where s.os_item_id = 910001;
  if v_saldo <> 0 then raise exception 'Homologacao da promocao nao preservou a reserva: %.', v_saldo; end if;

  v_prontidao := f.fn_nfe_producao_pronta('30000000-0000-4000-8000-000000000002');
  if coalesce((v_prontidao->>'pronta')::boolean, false)
     or position('perfi' in lower(coalesce(v_prontidao->>'motivo', ''))) = 0
     or position('liberad' in lower(coalesce(v_prontidao->>'motivo', ''))) = 0 then
    raise exception 'Producao nao bloqueou o perfil ainda desabilitado: %', v_prontidao;
  end if;
end;
$$;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select f.fn_perfil_operacao_nfe_liberar_producao(
  '50000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  'Equivalencia fiscal conferida na homologacao autorizada do pipeline.',
  true
);
reset role;

do $$
declare v_prontidao jsonb;
begin
  v_prontidao := f.fn_nfe_producao_pronta('30000000-0000-4000-8000-000000000002');
  if not coalesce((v_prontidao->>'pronta')::boolean, false)
     or v_prontidao->>'perfil_operacao_id' <> '50000000-0000-4000-8000-000000000001'
     or not (v_prontidao->'perfil_operacao_ids' ? '50000000-0000-4000-8000-000000000001') then
    raise exception 'Prontidao nao devolveu perfis singular/plural coerentes: %', v_prontidao;
  end if;
end;
$$;

create temp table nfe_payload_producao on commit drop as
select jsonb_set(
  payload,
  '{nome_destinatario}',
  to_jsonb('CLIENTE HOMOLOGACAO LTDA'::text),
  false
) as payload
from nfe_payload_homologacao_producao;

-- O preflight autenticado entrega o contexto HOM exato e seu hash canonico.
-- A transacao de claim recomputa esse material sob lock antes de criar PROD.
create temp table nfe_preflight_producao (preflight jsonb) on commit drop;
grant select, insert, update on nfe_preflight_producao to authenticated, service_role;
set local role authenticated;
insert into nfe_preflight_producao (preflight)
select f.fn_nfe_producao_preflight(
  '30000000-0000-4000-8000-000000000002'
);
reset role;

do $preflight_producao_valido$
declare v_preflight jsonb := (select preflight from nfe_preflight_producao);
begin
  if v_preflight->>'tenant_id' <> '10000000-0000-4000-8000-000000000001'
     or v_preflight->>'empresa_id' <> '20000000-0000-4000-8000-000000000001'
     or v_preflight->>'solicitacao_id' <> '30000000-0000-4000-8000-000000000002'
     or nullif(v_preflight->>'homologacao_documento_fiscal_id', '')::uuid
        is distinct from (select documento_fiscal_id from nfe_homologacao_producao)
     or coalesce(v_preflight->>'contexto_hash', '') !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(v_preflight->'contexto') is distinct from 'object' then
    raise exception 'Preflight de producao incompleto ou fora do escopo: %', v_preflight;
  end if;
end;
$preflight_producao_valido$;

select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Simula alteracao entre a montagem do payload/preflight e o claim. A falha
-- 40001 precisa reverter inclusive a preparacao transiente de PROD.
do $preflight_producao_toctou$
declare
  v_preflight jsonb := (select preflight from nfe_preflight_producao);
  v_emissoes_prod integer;
  v_documentos_antes integer;
  v_documentos_depois integer;
begin
  select count(*) into v_documentos_antes
  from f.documento_fiscal df
  where df.tenant_id = '10000000-0000-4000-8000-000000000001'
    and df.empresa_id = '20000000-0000-4000-8000-000000000001';

  update f.solicitacao_item
  set valor_unitario = 101
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and id = '40000000-0000-4000-8000-000000000002';

  begin
    perform f.fn_nfe_producao_preparar_e_claimar(
      '30000000-0000-4000-8000-000000000002',
      (select payload from nfe_payload_producao),
      nullif(v_preflight->>'homologacao_documento_fiscal_id', '')::uuid,
      v_preflight->>'contexto_hash',
      false
    );
    raise exception 'Claim aceitou contexto alterado depois do preflight.';
  exception when sqlstate '40001' then null;
  end;

  select count(*) into v_emissoes_prod
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = '10000000-0000-4000-8000-000000000001'
    and dfe.empresa_id = '20000000-0000-4000-8000-000000000001'
    and dfe.solicitacao_id = '30000000-0000-4000-8000-000000000002'
    and dfe.ambiente = 'PRODUCAO';
  if v_emissoes_prod <> 0 then
    raise exception 'Falha TOCTOU deixou emissao PROD parcial: %.', v_emissoes_prod;
  end if;
  select count(*) into v_documentos_depois
  from f.documento_fiscal df
  where df.tenant_id = '10000000-0000-4000-8000-000000000001'
    and df.empresa_id = '20000000-0000-4000-8000-000000000001';
  if v_documentos_depois <> v_documentos_antes then
    raise exception 'Falha TOCTOU deixou documento fiscal orfao: antes %, depois %.',
      v_documentos_antes, v_documentos_depois;
  end if;

  update f.solicitacao_item
  set valor_unitario = 100
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and id = '40000000-0000-4000-8000-000000000002';

  update nfe_preflight_producao
  set preflight = f.fn_nfe_producao_preflight(
    '30000000-0000-4000-8000-000000000002'
  );
end;
$preflight_producao_toctou$;

create temp table nfe_producao on commit drop as
select
  (claim->>'documento_fiscal_id')::uuid as documento_fiscal_id,
  claim->>'referencia_externa' as referencia_externa,
  claim
from (
  select f.fn_nfe_producao_preparar_e_claimar(
    '30000000-0000-4000-8000-000000000002',
    (select payload from nfe_payload_producao),
    nullif((select preflight->>'homologacao_documento_fiscal_id' from nfe_preflight_producao), '')::uuid,
    (select preflight->>'contexto_hash' from nfe_preflight_producao),
    false
  ) as claim
) x;

do $claim_producao_cas$
declare
  v_claim jsonb := (select claim from nfe_producao);
  v_perdedor jsonb;
  v_pendente integer;
begin
  if coalesce((v_claim->>'deve_enviar')::boolean, false) is not true
     or v_claim->>'status' <> 'ENVIANDO'
     or (v_claim->>'tentativa_count')::integer <> 1 then
    raise exception 'Primeiro claim atomico de producao invalido: %', v_claim;
  end if;
  if not exists (
    select 1 from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = '10000000-0000-4000-8000-000000000001'
      and dfe.empresa_id = '20000000-0000-4000-8000-000000000001'
      and dfe.documento_fiscal_id = (select documento_fiscal_id from nfe_producao)
      and dfe.ambiente = 'PRODUCAO'
      and dfe.status = 'ENVIANDO'
      and dfe.tentativa_count = 1
      and dfe.payload_enviado = (select payload from nfe_payload_producao)
  ) then
    raise exception 'Claim nao congelou payload/status/contador antes da rede.';
  end if;
  if not exists (
    select 1 from f.documento_fiscal df
    where df.tenant_id = '10000000-0000-4000-8000-000000000001'
      and df.empresa_id = '20000000-0000-4000-8000-000000000001'
      and df.id = (select documento_fiscal_id from nfe_producao)
      and df.valor_produtos = 200
      and df.valor_desconto = 0
      and df.valor_frete = 0
      and df.valor_seguro = 0
      and df.valor_outros = 0
      and df.valor_total = 210
  ) then
    raise exception 'Claim nao congelou total PROD com IPI: esperado produtos 200 e total 210.';
  end if;
  if not exists (
    select 1 from f.documento_fiscal_item dfi
    where dfi.tenant_id = '10000000-0000-4000-8000-000000000001'
      and dfi.empresa_id = '20000000-0000-4000-8000-000000000001'
      and dfi.documento_fiscal_id = (select documento_fiscal_id from nfe_producao)
      and dfi.item_n = 1
      and dfi.quantidade = 2
      and dfi.valor_unitario = 100
      and dfi.valor_total = 200
  ) then
    raise exception 'Claim nao congelou quantidade/preco/total liquido do item PROD.';
  end if;
  if not exists (
    select 1 from f.documento_fiscal_evento ev
    where ev.tenant_id = '10000000-0000-4000-8000-000000000001'
      and ev.empresa_id = '20000000-0000-4000-8000-000000000001'
      and ev.documento_fiscal_id = (select documento_fiscal_id from nfe_producao)
      and ev.tipo = 'ENVIO'
      and ev.status = 'ENVIANDO'
      and coalesce((ev.resposta->>'claim_duravel')::boolean, false)
      and ev.resposta->>'homologacao_documento_fiscal_id'
          = (select preflight->>'homologacao_documento_fiscal_id' from nfe_preflight_producao)
      and ev.resposta->>'contexto_hash'
          = (select preflight->>'contexto_hash' from nfe_preflight_producao)
  ) then
    raise exception 'Claim PROD nao registrou HOM/hash canonico na trilha duravel.';
  end if;

  v_perdedor := f.fn_nfe_producao_preparar_e_claimar(
    '30000000-0000-4000-8000-000000000002',
    (select payload from nfe_payload_producao),
    nullif((select preflight->>'homologacao_documento_fiscal_id' from nfe_preflight_producao), '')::uuid,
    (select preflight->>'contexto_hash' from nfe_preflight_producao),
    false
  );
  if coalesce((v_perdedor->>'deve_enviar')::boolean, true)
     or coalesce((v_perdedor->>'aguardar')::boolean, false) is not true
     or (v_perdedor->>'tentativa_count')::integer <> 1 then
    raise exception 'Perdedor concorrente nao foi bloqueado pelo CAS: %', v_perdedor;
  end if;

  update f.documento_fiscal_emissao
  set ultima_tentativa_em = clock_timestamp() - interval '11 minutes'
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and documento_fiscal_id = (select documento_fiscal_id from nfe_producao);
  select count(*) into v_pendente
  from f.fn_nfe_emissoes_pendentes_reconciliacao_producao(50) p
  where p.documento_fiscal_id = (select documento_fiscal_id from nfe_producao);
  if v_pendente <> 1 then
    raise exception 'ENVIANDO stale ficou fora do reconciliador de producao.';
  end if;
end;
$claim_producao_cas$;

-- Depois de existir promocao para producao, a homologacao de origem nao pode
-- ser cancelada, nem mesmo enquanto a emissao real ainda esta em rascunho.
do $$
begin
  begin
    perform f.fn_nfe_evento_registrar(
      (select documento_fiscal_id from nfe_homologacao_producao),
      'CANCELAMENTO', 'AUTORIZADA', 'Tentativa indevida apos promocao'
    );
    raise exception 'Cancelamento da homologacao foi aceito depois da promocao.';
  exception when sqlstate '55000' then
    null;
  end;
  begin
    perform f.fn_solicitacao_nfe_cancelar_rascunho(
      '30000000-0000-4000-8000-000000000002', 'Tentativa indevida com homologacao autorizada'
    );
    raise exception 'RPC local cancelou solicitacao com emissao autorizada.';
  exception when sqlstate '55000' then
    null;
  end;
  if (select status from f.documento_fiscal_emissao
      where tenant_id = '10000000-0000-4000-8000-000000000001'
        and empresa_id = '20000000-0000-4000-8000-000000000001'
        and documento_fiscal_id = (select documento_fiscal_id from nfe_homologacao_producao)) <> 'AUTORIZADA' then
    raise exception 'Tentativa bloqueada alterou a homologacao autorizada.';
  end if;
end;
$$;

-- Primeira tentativa rejeitada. A revisao precisa priorizar PRODUCAO mesmo
-- existindo uma autorizacao de homologacao para a mesma solicitacao.
select f.fn_nfe_registrar_envio(
  (select documento_fiscal_id from nfe_producao),
  (select payload from nfe_payload_producao),
  '{"status":"erro_autorizacao","status_sefaz":"539","mensagem_sefaz":"Duplicidade simulada"}'::jsonb,
  'REJEITADA', 539, 'Duplicidade simulada'
);

do $retomada_e_revalidacao$
declare
  v_retry record;
  v_retry_claim jsonb;
  v_perdedor jsonb;
  v_preflight jsonb := (select preflight from nfe_preflight_producao);
begin
  if (select status from f.documento_fiscal_emissao
      where tenant_id = '10000000-0000-4000-8000-000000000001'
        and empresa_id = '20000000-0000-4000-8000-000000000001'
        and documento_fiscal_id = (select documento_fiscal_id from nfe_producao)) <> 'REJEITADA'
     or (select tentativa_count from f.documento_fiscal_emissao
         where tenant_id = '10000000-0000-4000-8000-000000000001'
           and empresa_id = '20000000-0000-4000-8000-000000000001'
           and documento_fiscal_id = (select documento_fiscal_id from nfe_producao)) <> 1 then
    raise exception 'Resposta da primeira tentativa alterou contador/status incorretamente.';
  end if;

  begin
    perform f.fn_nfe_producao_preparar_e_claimar(
      '30000000-0000-4000-8000-000000000002',
      (select payload from nfe_payload_producao),
      nullif(v_preflight->>'homologacao_documento_fiscal_id', '')::uuid,
      v_preflight->>'contexto_hash',
      false
    );
    raise exception 'Retry PROD sem GET/reconciliacao abriu novo POST.';
  exception when sqlstate '55000' then null;
  end;

  update c.empresa_fiscal
  set certificado_validade_em = current_date - 1
  where empresa_id = '20000000-0000-4000-8000-000000000001';
  select * into v_retry
  from f.fn_nfe_preparar_documento_solicitacao_producao('30000000-0000-4000-8000-000000000002');
  if v_retry.documento_fiscal_id is distinct from (select documento_fiscal_id from nfe_producao)
     or v_retry.criado is distinct from false then
    raise exception 'Retomada nao devolveu emissao existente antes dos gates mutaveis: %', row_to_json(v_retry);
  end if;

  begin
    perform f.fn_nfe_producao_preparar_e_claimar(
      '30000000-0000-4000-8000-000000000002',
      (select payload from nfe_payload_producao),
      nullif(v_preflight->>'homologacao_documento_fiscal_id', '')::uuid,
      v_preflight->>'contexto_hash',
      true
    );
    raise exception 'Claim ignorou certificado vencido na revalidacao sob lock.';
  exception when sqlstate 'P0001' then null;
  end;
  update c.empresa_fiscal
  set certificado_validade_em = current_date + 365
  where empresa_id = '20000000-0000-4000-8000-000000000001';

  begin
    perform f.fn_nfe_producao_preparar_e_claimar(
      '30000000-0000-4000-8000-000000000002',
      '{"items":[{"numero_item":99}]}'::jsonb,
      nullif(v_preflight->>'homologacao_documento_fiscal_id', '')::uuid,
      v_preflight->>'contexto_hash',
      true
    );
    raise exception 'Retry aceitou payload diferente do payload congelado.';
  exception when sqlstate '22023' then null;
  end;

  v_retry_claim := f.fn_nfe_producao_preparar_e_claimar(
    '30000000-0000-4000-8000-000000000002',
    (select payload from nfe_payload_producao),
    nullif(v_preflight->>'homologacao_documento_fiscal_id', '')::uuid,
    v_preflight->>'contexto_hash',
    true
  );
  if coalesce((v_retry_claim->>'deve_enviar')::boolean, false) is not true
     or (v_retry_claim->>'tentativa_count')::integer <> 2 then
    raise exception 'Retry reconciliado nao abriu o segundo claim: %', v_retry_claim;
  end if;

  v_perdedor := f.fn_nfe_producao_preparar_e_claimar(
    '30000000-0000-4000-8000-000000000002',
    (select payload from nfe_payload_producao),
    nullif(v_preflight->>'homologacao_documento_fiscal_id', '')::uuid,
    v_preflight->>'contexto_hash',
    false
  );
  if coalesce((v_perdedor->>'deve_enviar')::boolean, true)
     or coalesce((v_perdedor->>'aguardar')::boolean, false) is not true
     or (v_perdedor->>'tentativa_count')::integer <> 2 then
    raise exception 'Segundo claim concorrente nao aguardou o vencedor: %', v_perdedor;
  end if;
end;
$retomada_e_revalidacao$;

select f.fn_nfe_registrar_envio(
  (select documento_fiscal_id from nfe_producao),
  (select payload from nfe_payload_producao),
  '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', 100, 'Autorizado o uso da NF-e'
);

do $producao_autorizada_so_no_apply$
declare v_pendente integer; v_ar integer; v_xml integer;
begin
  if not exists (
    select 1 from f.documento_fiscal_emissao dfe
    where dfe.documento_fiscal_id = (select documento_fiscal_id from nfe_producao)
      and dfe.status = 'PROCESSANDO' and dfe.tentativa_count = 2
  ) then
    raise exception 'Registrar envio materializou AUTORIZADA ou contou claim duas vezes.';
  end if;
  select count(*) into v_ar from f.titulo
  where documento_fiscal_id = (select documento_fiscal_id from nfe_producao)
    and deleted_at is null;
  select count(*) into v_xml from f.documento_fiscal_xml
  where documento_fiscal_id = (select documento_fiscal_id from nfe_producao)
    and deleted_at is null;
  if v_ar <> 0 or v_xml <> 0 then
    raise exception 'Resposta AUTORIZADA antes do apply criou artefatos: AR %, XML %.', v_ar, v_xml;
  end if;

  update f.documento_fiscal_emissao
  set ultima_tentativa_em = clock_timestamp() - interval '11 minutes'
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and documento_fiscal_id = (select documento_fiscal_id from nfe_producao);
  select count(*) into v_pendente
  from f.fn_nfe_emissoes_pendentes_reconciliacao_producao(50) p
  where p.documento_fiscal_id = (select documento_fiscal_id from nfe_producao);
  if v_pendente <> 1 then
    raise exception 'PROCESSANDO sem apply ficou fora do reconciliador.';
  end if;
end;
$producao_autorizada_so_no_apply$;

select f.fn_nfe_aplicar_retorno_producao(
  'NFEP-30000000-0000-4000-8000-000000000002',
  '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', repeat('2', 44), '223456789012345', 10, 1, 100,
  'Autorizado o uso da NF-e', 'teste/producao.xml', 'teste/producao.pdf',
  '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>13671448000189</CNPJ></emit></infNFe></NFe>',
  'ENVIO'
);

-- Reaplicar o mesmo retorno nao pode duplicar o AR, XML ou impostos.
select f.fn_nfe_aplicar_retorno_producao(
  'NFEP-30000000-0000-4000-8000-000000000002',
  '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', repeat('2', 44), '223456789012345', 10, 1, 100,
  'Autorizado o uso da NF-e', 'teste/producao.xml', 'teste/producao.pdf',
  '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>13671448000189</CNPJ></emit></infNFe></NFe>',
  'RECONCILIACAO'
);

-- Eventos operacionais seguros funcionam em producao; cancelamento real
-- permanece bloqueado ate existir estorno financeiro/estoque homologado.
select f.fn_nfe_evento_registrar(
  (select documento_fiscal_id from nfe_producao),
  'DOWNLOAD', 'CONCLUIDO', null, null, '{"artefato":"DANFE"}'::jsonb
);
select f.fn_nfe_evento_registrar(
  (select documento_fiscal_id from nfe_producao),
  'EMAIL', 'ENFILEIRADO', null, null, '{"origem":"teste"}'::jsonb,
  array['financeiro@example.test']
);

do $$
declare v_eventos integer;
begin
  begin
    perform f.fn_nfe_evento_registrar(
      (select documento_fiscal_id from nfe_producao),
      'CANCELAMENTO', 'AUTORIZADA', 'Cancelamento real ainda nao suportado'
    );
    raise exception 'Cancelamento de producao foi aceito sem fluxo de estorno.';
  exception when sqlstate '55000' then
    null;
  end;
  select count(*) into v_eventos
  from f.documento_fiscal_evento ev
  where ev.tenant_id = '10000000-0000-4000-8000-000000000001'
    and ev.empresa_id = '20000000-0000-4000-8000-000000000001'
    and ev.documento_fiscal_id = (select documento_fiscal_id from nfe_producao)
    and ev.tipo in ('DOWNLOAD', 'EMAIL');
  if v_eventos <> 2 then raise exception 'Eventos seguros de producao incorretos: %.', v_eventos; end if;
end;
$$;

do $$
declare
  v_documento_id uuid := (select documento_fiscal_id from nfe_producao);
  v_doc f.documento_fiscal%rowtype;
  v_ar integer;
  v_ap integer;
  v_xml integer;
  v_impostos integer;
  v_saldo numeric;
  v_saldo_valor numeric;
  v_movimentos integer;
begin
  select * into v_doc from f.documento_fiscal
  where tenant_id = '10000000-0000-4000-8000-000000000001'
    and empresa_id = '20000000-0000-4000-8000-000000000001'
    and id = v_documento_id;
  select count(*) filter (where tipo = 'AR'), count(*) filter (where tipo = 'AP')
    into v_ar, v_ap
  from f.titulo
  where tenant_id = v_doc.tenant_id and empresa_id = v_doc.empresa_id
    and documento_fiscal_id = v_documento_id and deleted_at is null;
  select count(*) into v_xml from f.documento_fiscal_xml
  where tenant_id = v_doc.tenant_id and documento_fiscal_id = v_documento_id and deleted_at is null;
  select count(*) into v_impostos from f.documento_fiscal_imposto
  where tenant_id = v_doc.tenant_id and documento_fiscal_id = v_documento_id and deleted_at is null;
  select s.saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(v_doc.tenant_id, v_doc.empresa_id, 910001) s
  where s.os_item_id = 910001;
  select s.saldo into v_saldo_valor
  from f.fn_os_saldo_a_faturar(v_doc.tenant_id, v_doc.empresa_id, 910001) s;
  select count(*) into v_movimentos from public.movimentacoes
  where tenant_id = v_doc.tenant_id and empresa_id = v_doc.empresa_id and origem_os_id = 910001;

  if v_doc.nfe_status <> 'EMITIDA' or v_doc.competencia_date is null then
    raise exception 'Producao nao consolidou documento/competencia: %', row_to_json(v_doc);
  end if;
  if v_doc.valor_produtos <> 200 or v_doc.valor_desconto <> 0
     or v_doc.valor_frete <> 0 or v_doc.valor_seguro <> 0
     or v_doc.valor_outros <> 0 or v_doc.valor_total <> 210 then
    raise exception 'Totais finais de producao nao preservaram o IPI: %', row_to_json(v_doc);
  end if;
  if v_ar <> 1 or v_ap <> 0 then raise exception 'Financeiro incorreto: AR %, AP %.', v_ar, v_ap; end if;
  if not exists (
    select 1 from f.titulo t
    where t.tenant_id = v_doc.tenant_id
      and t.empresa_id = v_doc.empresa_id
      and t.documento_fiscal_id = v_documento_id
      and t.tipo = 'AR'
      and t.valor_total = 210
      and t.deleted_at is null
  ) then
    raise exception 'AR de producao nao refletiu o total 210 com IPI.';
  end if;
  if v_xml <> 1 then raise exception 'XML de producao duplicado/ausente: %.', v_xml; end if;
  if v_impostos <> 6 then raise exception 'Esperados ICMS, IPI, PIS, COFINS, IBS e CBS; encontrados %.', v_impostos; end if;
  if not exists (
    select 1 from f.documento_fiscal_imposto dfi
    where dfi.tenant_id = v_doc.tenant_id
      and dfi.documento_fiscal_id = v_documento_id
      and dfi.imposto = 'IPI'
      and dfi.base_calculo = 200
      and dfi.aliquota = 5
      and dfi.valor_calculado = 10
      and dfi.deleted_at is null
  ) then
    raise exception 'IPI tributado de 5%% nao foi congelado como base 200/valor 10.';
  end if;
  if v_saldo <> 0 then raise exception 'Producao nao consumiu saldo comercial: %.', v_saldo; end if;
  if v_saldo_valor <> 0 then raise exception 'Producao nao zerou saldo por valor: %.', v_saldo_valor; end if;
  if v_movimentos <> 0 then raise exception 'Emissao criou baixa de estoque duplicada: %.', v_movimentos; end if;
end;
$$;

-- Cancelamento real dentro das 24h (05/09/2026): claim duravel, finalizacao
-- com a resposta da Focus e efeitos financeiros. O documento continua
-- existindo (numero e chave), o titulo AR e cancelado e o saldo da OV volta.
do $cancelamento_producao$
declare
  v_documento_id uuid := (select documento_fiscal_id from nfe_producao);
  v_claim jsonb;
  v_claim_id uuid;
  v_fim jsonb;
  v_doc f.documento_fiscal%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_titulo f.titulo%rowtype;
  v_saldo numeric;
  v_movimentos integer;
begin
  -- Claim direto pela RPC de homologacao nao serve para PRODUCAO.
  begin
    perform f.fn_nfe_cancelamento_homologacao_claim(v_documento_id, 'Cancelamento pela RPC errada de ambiente');
    raise exception 'Claim de homologacao aceitou emissao de producao.';
  exception when sqlstate 'P0002' then null;
  end;

  v_claim := f.fn_nfe_cancelamento_producao_claim(v_documento_id, 'Cancelamento real controlado no teste do pipeline');
  if coalesce((v_claim->>'deve_cancelar')::boolean, false) is not true then
    raise exception 'Claim de producao nao autorizou o DELETE: %', v_claim;
  end if;
  v_claim_id := (v_claim->>'evento_claim_id')::uuid;

  -- Enquanto o claim esta ENVIANDO, um segundo claim aguarda em vez de duplicar.
  v_claim := f.fn_nfe_cancelamento_producao_claim(v_documento_id, 'Cancelamento real controlado no teste do pipeline');
  if coalesce((v_claim->>'aguardar')::boolean, false) is not true then
    raise exception 'Segundo claim de producao nao aguardou o primeiro: %', v_claim;
  end if;

  v_fim := f.fn_nfe_cancelamento_producao_finalizar(
    v_documento_id, v_claim_id, 'AUTORIZADA', 'Cancelamento real controlado no teste do pipeline',
    '135000000000001', '{"status":"cancelado","status_sefaz":"135","numero_protocolo":"135000000000001"}'::jsonb
  );
  if coalesce((v_fim->>'ok')::boolean, false) is not true or (v_fim->>'titulos_cancelados')::integer <> 1 then
    raise exception 'Finalizacao de producao nao cancelou como esperado: %', v_fim;
  end if;

  select * into v_doc from f.documento_fiscal where id = v_documento_id;
  select * into v_emissao from f.documento_fiscal_emissao where documento_fiscal_id = v_documento_id and ambiente = 'PRODUCAO';
  select * into v_titulo from f.titulo
  where documento_fiscal_id = v_documento_id and tipo = 'AR' and deleted_at is null;
  if v_emissao.status <> 'CANCELADA' or v_emissao.protocolo <> '223456789012345' then
    raise exception 'Emissao de producao nao ficou CANCELADA preservando o protocolo de autorizacao: %/%', v_emissao.status, v_emissao.protocolo;
  end if;
  if v_doc.nfe_status <> 'CANCELADA' or v_doc.numero is null or v_doc.chave_acesso <> repeat('2', 44) then
    raise exception 'Documento cancelado perdeu numero/chave ou nao mudou de status: %', row_to_json(v_doc);
  end if;
  if (select status from f.solicitacao_faturamento where id = v_emissao.solicitacao_id) <> 'CANCELADA' then
    raise exception 'Solicitacao nao foi cancelada junto com a NF-e real.';
  end if;
  if v_titulo.status <> 'CANCELADO' or v_titulo.valor_aberto <> 0 then
    raise exception 'Titulo AR nao foi cancelado: % / %', v_titulo.status, v_titulo.valor_aberto;
  end if;
  if exists (
    select 1 from f.titulo_parcela tp
    where tp.titulo_id = v_titulo.id and tp.deleted_at is null and tp.valor_aberto <> 0
  ) then
    raise exception 'Parcela do titulo cancelado manteve valor em aberto.';
  end if;
  if not exists (
    select 1 from f.documento_fiscal_evento ev
    where ev.documento_fiscal_id = v_documento_id and ev.tipo = 'CANCELAMENTO'
      and ev.status = 'AUTORIZADA' and ev.protocolo = '135000000000001'
      and ev.resposta->>'claim_evento_id' = v_claim_id::text
  ) then
    raise exception 'Evento de cancelamento autorizado nao registrou protocolo/claim.';
  end if;
  select s.saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(v_doc.tenant_id, v_doc.empresa_id, 910001) s
  where s.os_item_id = 910001;
  if coalesce(v_saldo, 0) <= 0 then
    raise exception 'Cancelamento real nao devolveu o saldo da OV: %.', v_saldo;
  end if;
  select count(*) into v_movimentos from public.movimentacoes
  where tenant_id = v_doc.tenant_id and empresa_id = v_doc.empresa_id and origem_os_id = 910001;
  if v_movimentos <> 0 then
    raise exception 'Cancelamento real mexeu no estoque: %.', v_movimentos;
  end if;

  -- Resposta tardia do mesmo claim e idempotente; de outro claim e rejeitada.
  v_fim := f.fn_nfe_cancelamento_producao_finalizar(
    v_documento_id, v_claim_id, 'AUTORIZADA', 'Cancelamento real controlado no teste do pipeline',
    '135000000000001', '{"status":"cancelado"}'::jsonb
  );
  if coalesce((v_fim->>'idempotente')::boolean, false) is not true then
    raise exception 'Finalizacao repetida nao foi idempotente: %', v_fim;
  end if;
  begin
    perform f.fn_nfe_cancelamento_producao_claim(v_documento_id, 'Cancelamento real controlado no teste do pipeline');
    raise exception 'Nota ja cancelada aceitou novo claim.';
  exception when sqlstate '55000' then null;
  end;
end;
$cancelamento_producao$;

-- Mesmo depois da autorizacao, XML e impostos sao evidencias imutaveis para
-- o cliente. UPDATE/DELETE precisam passar pelo backend fiscal controlado.
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $evidencias_fiscais_dml_bloqueado$
declare
  v_documento_id uuid := (
    select dfe.documento_fiscal_id
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = '10000000-0000-4000-8000-000000000001'
      and dfe.empresa_id = '20000000-0000-4000-8000-000000000001'
      and dfe.referencia_externa = 'NFEP-30000000-0000-4000-8000-000000000002'
  );
begin
  begin
    update f.documento_fiscal_xml
    set xml_raw = '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>13671448000189</CNPJ></emit></infNFe></NFe>'
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and documento_fiscal_id = v_documento_id;
    raise exception 'Authenticated conseguiu alterar XML autorizado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    delete from f.documento_fiscal_xml
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and documento_fiscal_id = v_documento_id;
    raise exception 'Authenticated conseguiu excluir XML autorizado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    update f.documento_fiscal_imposto
    set valor_calculado = 999
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and documento_fiscal_id = v_documento_id;
    raise exception 'Authenticated conseguiu alterar imposto autorizado.';
  exception when sqlstate '42501' then null;
  end;
  begin
    delete from f.documento_fiscal_imposto
    where tenant_id = '10000000-0000-4000-8000-000000000001'
      and documento_fiscal_id = v_documento_id;
    raise exception 'Authenticated conseguiu excluir imposto autorizado.';
  exception when sqlstate '42501' then null;
  end;
end;
$evidencias_fiscais_dml_bloqueado$;

reset role;

rollback;
