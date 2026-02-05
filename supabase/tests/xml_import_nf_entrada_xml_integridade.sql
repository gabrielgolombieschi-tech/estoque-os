BEGIN;

DO $$ BEGIN
  RAISE NOTICE 'Running xml_import_nf_entrada_xml_integridade.sql';
END $$;

-- Test fixtures
DO $$
DECLARE
  v_user uuid := gen_random_uuid();
  v_usuario_id uuid := gen_random_uuid();
  v_tenant uuid := gen_random_uuid();
  v_empresa uuid := gen_random_uuid();
  v_empresa_cnpj text := lpad((floor(random()*100000000000000))::bigint::text, 14, '0');
  v_membership uuid := gen_random_uuid();
  v_role uuid := gen_random_uuid();
  v_motivo uuid := gen_random_uuid();
  v_fornecedor_id int;
  v_item_id int;
  v_nf_id bigint;
  v_df_id uuid;
  v_xml text := '<NFe><infNFe Id="NFe123"/></NFe>';
BEGIN
  -- Simula usuário autenticado
  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- auth.users (FK de tenant_memberships.user_id)
  INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (
    v_user,
    'authenticated',
    'authenticated',
    'usuario.teste@example.com',
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('nome', 'Usuario Teste'),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tenants (id, nome, ativo)
  VALUES (v_tenant, 'T-TEST', true);

  -- c.tenant (FK de c.empresa.tenant_id)
  INSERT INTO c.tenant (id, codigo, nome, ativo)
  VALUES (v_tenant, 'T-TEST', 'Tenant Teste', true);

  INSERT INTO c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, ativo)
  VALUES (v_empresa, v_tenant, 'E-TEST', 'Empresa Teste', 'Empresa Teste', true);

  -- public.empresas (FK de public.nf_entrada.empresa_id)
  INSERT INTO public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
  VALUES (v_empresa, v_tenant, v_empresa_cnpj, 'Empresa Teste', 'Empresa Teste', true)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO a.usuario (id, auth_user_id, nome, email, ativo)
  VALUES (v_usuario_id, v_user, 'Usuario Teste', 'usuario.teste@example.com', true);

  -- No DB atual, public.can() exige vinculo em a.usuario_tenant (ADMIN/OWNER libera tudo)
  INSERT INTO a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
  VALUES (v_usuario_id, v_tenant, 'ADMIN', true);

  INSERT INTO a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
  VALUES (v_usuario_id, v_empresa, 'ADMIN', true);

  INSERT INTO f.motivo_compra (id, tenant_id, codigo, nome, aplica_em, ativo)
  VALUES (v_motivo, v_tenant, 'TEST', 'Teste', 'PRODUTO', true);

  INSERT INTO public.tenant_memberships (id, tenant_id, user_id, status)
  VALUES (v_membership, v_tenant, v_user, 'active');

  INSERT INTO public.roles (id, tenant_id, name)
  VALUES (v_role, v_tenant, 'ROLE_XML_IMPORT_TEST');

  INSERT INTO public.membership_roles (membership_id, role_id)
  VALUES (v_membership, v_role);

  INSERT INTO public.role_access_rules (role_id, resource, action)
  VALUES (v_role, 'xml_import', 'execute')
  ON CONFLICT DO NOTHING;

  -- Garante contexto do tenant para public.current_tenant_id() e public.can()
  PERFORM public.set_current_tenant(v_tenant);

  IF public.current_tenant_id() IS DISTINCT FROM v_tenant THEN
    RAISE EXCEPTION 'TEST SETUP FAILED: current_tenant_id() nao foi definido (esperado=% atual=%)', v_tenant, public.current_tenant_id();
  END IF;

  IF NOT public.can('xml_import', 'execute') THEN
    RAISE EXCEPTION 'TEST SETUP FAILED: permissao can(xml_import,execute)=false (tenant=% user=%)', v_tenant, v_user;
  END IF;

  -- Fornecedor mínimo
  INSERT INTO public.fornecedores (nome, tenant_id, empresa_id)
  VALUES ('Fornecedor Teste', v_tenant, v_empresa)
  RETURNING id INTO v_fornecedor_id;

  -- Item mínimo (para teste de import sem XML)
  INSERT INTO public.itens (codigo_interno, nome, tipo, tenant_id, empresa_id, finalidade)
  VALUES ('IT-TEST', 'Item Teste', 'produto', v_tenant, v_empresa, 'revenda')
  RETURNING id INTO v_item_id;

  -- 1) XML válido -> persiste nf_entrada.xml_raw e cria f.documento_fiscal_xml
  SELECT nf_entrada_id INTO v_nf_id
  FROM public.import_nf_entrada(
    v_empresa,
    'revenda'::public.item_finalidade,
    v_fornecedor_id,
    '[]'::jsonb,
    jsonb_build_object(
      'chave', '35111111111111111111111111111111111111111111',
      'emitente_nome', 'Emitente',
      'emitente_cnpj', '11111111000111',
      'numero', '1',
      'serie', '1',
      'data_emissao', now()::text,
      'valor_total', 10,
      'valor_produtos', 10,
      'valor_frete', 0,
      'valor_seguro', 0,
      'valor_desconto', 0,
      'valor_outros', 0
    ),
    v_tenant,
    v_xml,
    false,
    null,
    null,
    false,
    v_motivo,
    v_usuario_id
  );

  IF v_nf_id IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: import_nf_entrada did not return nf_entrada_id';
  END IF;

  IF (SELECT btrim(xml_raw) FROM public.nf_entrada WHERE id = v_nf_id) IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: nf_entrada.xml_raw is null/blank';
  END IF;

  SELECT id INTO v_df_id
  FROM f.documento_fiscal
  WHERE tenant_id = v_tenant AND source_nf_entrada_id = v_nf_id;

  IF v_df_id IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal not created';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM f.documento_fiscal_xml
    WHERE tenant_id = v_tenant AND documento_fiscal_id = v_df_id AND length(btrim(xml_raw)) > 0
  ) THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal_xml missing or blank';
  END IF;

  -- 2) XML vazio/whitespace -> erro
  BEGIN
    PERFORM * FROM public.import_nf_entrada(
      v_empresa,
      'revenda'::public.item_finalidade,
      v_fornecedor_id,
      '[]'::jsonb,
      jsonb_build_object(
        'chave', '35222222222222222222222222222222222222222222',
        'emitente_nome', 'Emitente',
        'emitente_cnpj', '11111111000111',
        'numero', '2',
        'serie', '1',
        'data_emissao', now()::text,
        'valor_total', 10,
        'valor_produtos', 10,
        'valor_frete', 0,
        'valor_seguro', 0,
        'valor_desconto', 0,
        'valor_outros', 0
      ),
      v_tenant,
      '   ',
      false,
      null,
      null,
      false,
      v_motivo,
      v_usuario_id
    );
    RAISE EXCEPTION 'TEST FAILED: expected error for blank xml_raw';
  EXCEPTION WHEN OTHERS THEN
    -- ok
  END;

  -- 3) Sem XML mas com itens completos -> cria pendência XML_FALTANDO
  SELECT nf_entrada_id INTO v_nf_id
  FROM public.import_nf_entrada(
    v_empresa,
    'revenda'::public.item_finalidade,
    v_fornecedor_id,
    jsonb_build_array(jsonb_build_object('item_id', v_item_id, 'codigo', 'IT-TEST', 'nome', 'Item Teste', 'quantidade', 1, 'valorUnit', 10, 'total', 10)),
    jsonb_build_object(
      'chave', '35333333333333333333333333333333333333333333',
      'emitente_nome', 'Emitente',
      'emitente_cnpj', '11111111000111',
      'numero', '3',
      'serie', '1',
      'data_emissao', now()::text,
      'valor_total', 10,
      'valor_produtos', 10,
      'valor_frete', 0,
      'valor_seguro', 0,
      'valor_desconto', 0,
      'valor_outros', 0
    ),
    v_tenant,
    null,
    false,
    null,
    null,
    false,
    v_motivo,
    v_usuario_id
  );

  SELECT id INTO v_df_id
  FROM f.documento_fiscal
  WHERE tenant_id = v_tenant AND source_nf_entrada_id = v_nf_id;

  IF v_df_id IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal not created (no-xml case)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM f.documento_fiscal_pendencia
    WHERE tenant_id = v_tenant AND documento_fiscal_id = v_df_id AND tipo = 'XML_FALTANDO' AND resolved_at IS NULL
  ) THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal_pendencia XML_FALTANDO not created';
  END IF;
END$$;

ROLLBACK;

DO $$ BEGIN
  RAISE NOTICE 'OK: xml_import_nf_entrada_xml_integridade.sql';
END $$;
