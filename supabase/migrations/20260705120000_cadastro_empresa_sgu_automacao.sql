-- Cadastra a segunda empresa do tenant "Segau": SGU AUTOMAÇÃO LTDA
-- (CNPJ 35.739.220/0001-16), replicando nas duas tabelas de empresa que
-- coexistem hoje (public.empresas, usada pelas RPCs de faturamento/permissao,
-- e c.empresa, usada pelo admin/empresas e pelas FKs financeiras) com o
-- MESMO id, e copiando os vinculos usuario_empresa que hoje apontam para a
-- ELÉTRICA SEGAU (codigo 'SEG') para a nova empresa, para que os usuarios que
-- ja tem acesso a Segau passem a ter acesso a SGU tambem.
--
-- Idempotente: pode ser reaplicada sem duplicar dados.

do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'; -- tenant "Segau"
  v_segau_empresa_id uuid;
  v_sgu_empresa_id uuid;
  v_copied_usuario_empresa int := 0;
begin
  if not exists (select 1 from c.tenant where id = v_tenant_id) then
    raise exception 'c.tenant % nao encontrado - abortando', v_tenant_id;
  end if;

  -- Empresa existente (ELÉTRICA SEGAU) usada como referencia para copiar vinculos de usuario.
  select id into v_segau_empresa_id
  from c.empresa
  where tenant_id = v_tenant_id and codigo = 'SEG' and deleted_at is null
  limit 1;

  if v_segau_empresa_id is null then
    select id into v_segau_empresa_id
    from c.empresa
    where id = 'f0e74f49-a127-46b4-901b-f7b37e43c690' and deleted_at is null;
  end if;

  -- Ja cadastrada? (reaplicacao da migration)
  select id into v_sgu_empresa_id
  from c.empresa
  where tenant_id = v_tenant_id and codigo = 'SGU' and deleted_at is null
  limit 1;

  if v_sgu_empresa_id is null then
    v_sgu_empresa_id := gen_random_uuid();

    insert into c.empresa (
      id, tenant_id, codigo, razao_social, nome_fantasia, cnpj,
      email, telefone, site, observacao, ativo
    ) values (
      v_sgu_empresa_id, v_tenant_id, 'SGU', 'SGU AUTOMAÇÃO LTDA', 'SGU AUTOMAÇÃO',
      '35739220000116',
      'sguautomacao@outlook.com', '4734735171', null,
      'Telefone celular: (47) 99122-4552. Socio: Nilton Neves Mendes (CPF 344.436.659-00). '
      || 'Dados bancarios: Sicredi Norte SC (748), Agencia 1593, Conta corrente 20032-9.',
      true
    );

    insert into c.empresa_endereco (
      empresa_id, tipo, cep, logradouro, numero, complemento, bairro, cidade, uf
    ) values
    (
      v_sgu_empresa_id, 'FISCAL', '88828000', 'Rua Manoel Joao da Silva', 'S/N',
      'Lote 12 Quadra 142', 'Zona Sul', 'Balneário Rincão', 'SC'
    ),
    (
      v_sgu_empresa_id, 'CORRESPONDENCIA', '89220865', 'Rua Guilhermina Heidemann de Oliveira', '407',
      null, 'Costa e Silva', 'Joinville', 'SC'
    );

    insert into c.empresa_fiscal (
      empresa_id, ie_isento, inscricao_estadual, inscricao_municipal, regime_tributario, crt
    ) values (
      v_sgu_empresa_id, false, '260586307', '152836', 'Simples Nacional', 1
    );

    insert into public.empresas (
      id, tenant_id, cnpj, razao_social, nome_fantasia, ie, im, uf, cidade, endereco,
      regime_tributario, ativo, habilita_servico_hh
    ) values (
      v_sgu_empresa_id, v_tenant_id, '35739220000116', 'SGU AUTOMAÇÃO LTDA', 'SGU AUTOMAÇÃO',
      '260586307', '152836', 'SC', 'Balneário Rincão',
      'Rua Manoel Joao da Silva, S/N, Lote 12 Quadra 142, Zona Sul, CEP 88828-000, Balneário Rincão - SC',
      'Simples Nacional', true, false
    );
  end if;

  -- Replica os vinculos usuario_empresa da ELÉTRICA SEGAU para a SGU (mesmo papel/status).
  if v_segau_empresa_id is not null then
    insert into a.usuario_empresa (
      id, usuario_id, empresa_id, papel, ativo, permissoes_extra, permissoes_negadas,
      created_at, updated_at, created_by, updated_by, deleted_at
    )
    select
      gen_random_uuid(), ue.usuario_id, v_sgu_empresa_id, ue.papel, ue.ativo,
      ue.permissoes_extra, ue.permissoes_negadas, now(), now(), ue.created_by, ue.updated_by, null
    from a.usuario_empresa ue
    where ue.empresa_id = v_segau_empresa_id
      and ue.deleted_at is null
    on conflict (usuario_id, empresa_id) where deleted_at is null do nothing;

    get diagnostics v_copied_usuario_empresa = row_count;
  end if;

  raise notice 'SGU setup ok: empresa_id=%, segau_empresa_id=%, usuario_empresa copiados=%',
    v_sgu_empresa_id, v_segau_empresa_id, v_copied_usuario_empresa;
end $$;
