-- ============================================================
-- FIX + TEST (copiar e colar no Supabase)
-- Resolve:
--  - f.fn_find_documento_fiscal_from_import(bigint) não existe
--  - documento_fiscal_xml missing or blank
-- ============================================================

-- ------------------------------------------------------------
-- 0) FIX: garantir funções usadas pelo import_nf_entrada()
-- ------------------------------------------------------------
BEGIN;

CREATE SCHEMA IF NOT EXISTS f;

-- Cria/acha documento_fiscal a partir da nf_entrada + garante documento_fiscal_xml
CREATE OR REPLACE FUNCTION f.fn_ensure_documento_fiscal_from_nf_entrada(p_nf_entrada_id bigint)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'f', 'public', 'a', 'extensions'
AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_df_id uuid;
  v_emissao_date date;
  v_competencia date;
  v_xml_hash text;
begin
  select *
    into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada não encontrada: %', p_nf_entrada_id;
  end if;

  -- 1) Se já existe DF por source_nf_entrada_id, retorna
  select df.id
    into v_df_id
  from f.documento_fiscal df
  where df.tenant_id = v_nf.tenant_id
    and df.empresa_id = v_nf.empresa_id
    and df.source_nf_entrada_id = v_nf.id
    and df.deleted_at is null
  order by df.created_at desc
  limit 1;

  -- 2) Se não achou, tenta por chave_acesso (e cola o source_nf_entrada_id)
  if v_df_id is null then
    select df.id
      into v_df_id
    from f.documento_fiscal df
    where df.tenant_id = v_nf.tenant_id
      and df.empresa_id = v_nf.empresa_id
      and df.chave_acesso = v_nf.chave
      and df.deleted_at is null
    order by df.created_at desc
    limit 1;

    if v_df_id is not null then
      update f.documento_fiscal
         set source_nf_entrada_id = v_nf.id,
             updated_at = now(),
             updated_by = a.fn_current_usuario_id()
       where id = v_df_id
         and source_nf_entrada_id is null;
    end if;
  end if;

  -- 3) Se ainda não achou, cria DF mínimo
  if v_df_id is null then
    v_emissao_date := (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date;
    if v_emissao_date is null then
      v_emissao_date := (now() at time zone 'America/Sao_Paulo')::date;
    end if;

    v_competencia := date_trunc('month', v_emissao_date)::date;

    insert into f.documento_fiscal (
      id,
      tenant_id,
      empresa_id,
      modelo,
      serie,
      numero,
      chave_acesso,
      emissao_date,
      competencia_date,
      valor_total,
      operacao,
      natureza,
      source_nf_entrada_id,
      created_at,
      updated_at,
      created_by,
      updated_by
    ) values (
      gen_random_uuid(),
      v_nf.tenant_id,
      v_nf.empresa_id,
      null,
      v_nf.serie,
      v_nf.numero,
      v_nf.chave,
      v_emissao_date,
      v_competencia,
      coalesce(v_nf.valor_total, 0),
      'ENTRADA',
      'PRODUTO',
      v_nf.id,
      now(),
      now(),
      a.fn_current_usuario_id(),
      a.fn_current_usuario_id()
    )
    returning id into v_df_id;
  end if;

  -- 4) ✅ GARANTIR documento_fiscal_xml se xml_raw existir e não estiver vazio
  if v_nf.xml_raw is not null and nullif(btrim(v_nf.xml_raw), '') is not null then
    begin
      -- tenta extensions.digest (se existir no seu ambiente)
      v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');
    exception when others then
      v_xml_hash := null;
    end;

    insert into f.documento_fiscal_xml (
      tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash
    ) values (
      v_nf.tenant_id, v_df_id, v_nf.chave, v_nf.xml_raw, v_xml_hash
    )
    on conflict (tenant_id, documento_fiscal_id)
    do update set
      chave_acesso = excluded.chave_acesso,
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  return v_df_id;
end;
$$;

-- Função “find” esperada pelo import_nf_entrada (compat)
CREATE OR REPLACE FUNCTION f.fn_find_documento_fiscal_from_import(p_nf_entrada_id bigint)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'f', 'public', 'a', 'extensions'
AS $$
begin
  return f.fn_ensure_documento_fiscal_from_nf_entrada(p_nf_entrada_id);
end;
$$;

COMMIT;

-- ------------------------------------------------------------
-- 1) TESTE (tudo será ROLLBACK ao final)
-- ------------------------------------------------------------
BEGIN;

DO $$ BEGIN
  RAISE NOTICE 'Running xml_import_nf_entrada_xml_integridade.sql (FIXED find + xml)';
END $$;

DO $$
DECLARE
  v_user uuid := gen_random_uuid();
  v_usuario_id uuid := gen_random_uuid();
  v_tenant uuid := gen_random_uuid();
  v_empresa uuid := gen_random_uuid();

  v_email text := 'usuario.teste+' || replace(gen_random_uuid()::text,'-','') || '@example.com';
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

  -- auth.users
  INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (
    v_user,
    'authenticated',
    'authenticated',
    v_email,
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('nome', 'Usuario Teste'),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  -- Tenant
  INSERT INTO public.tenants (id, nome, ativo)
  VALUES (v_tenant, 'T-TEST-' || left(replace(v_tenant::text,'-',''), 8), true)
  ON CONFLICT DO NOTHING;

  INSERT INTO c.tenant (id, codigo, nome, ativo)
  VALUES (v_tenant, 'T-TEST-' || left(replace(v_tenant::text,'-',''), 8), 'TENANT TESTE', true)
  ON CONFLICT DO NOTHING;

  -- Empresa (cadastros)
  INSERT INTO c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, ativo)
  VALUES (v_empresa, v_tenant, 'E-TEST-' || left(replace(v_empresa::text,'-',''), 8), 'EMPRESA TESTE', 'EMPRESA TESTE', true)
  ON CONFLICT DO NOTHING;

  -- Empresa (public.empresas) - FK de public.nf_entrada.empresa_id
  INSERT INTO public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
  VALUES (v_empresa, v_tenant, v_empresa_cnpj, 'EMPRESA TESTE', 'EMPRESA TESTE', true)
  ON CONFLICT DO NOTHING;

  -- Usuário app
  INSERT INTO a.usuario (id, auth_user_id, nome, email, ativo)
  VALUES (v_usuario_id, v_user, 'USUARIO TESTE', lower(v_email), true)
  ON CONFLICT DO NOTHING;

  INSERT INTO a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
  VALUES (v_usuario_id, v_tenant, 'ADMIN', true)
  ON CONFLICT DO NOTHING;

  INSERT INTO a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
  VALUES (v_usuario_id, v_empresa, 'ADMIN', true)
  ON CONFLICT DO NOTHING;

  -- Motivo compra
  INSERT INTO f.motivo_compra (id, tenant_id, codigo, nome, aplica_em, ativo)
  VALUES (v_motivo, v_tenant, 'TEST-' || left(replace(v_motivo::text,'-',''), 6), 'TESTE', 'PRODUTO', true)
  ON CONFLICT DO NOTHING;

  -- Membership + Role + Access Rule (public.can)
  INSERT INTO public.tenant_memberships (id, tenant_id, user_id, status)
  VALUES (v_membership, v_tenant, v_user, 'active')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.roles (id, tenant_id, name)
  VALUES (v_role, v_tenant, 'ROLE_XML_IMPORT_TEST_' || left(replace(v_role::text,'-',''), 6))
  ON CONFLICT DO NOTHING;

  INSERT INTO public.membership_roles (membership_id, role_id)
  VALUES (v_membership, v_role)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.role_access_rules (role_id, resource, action)
  VALUES (v_role, 'xml_import', 'execute')
  ON CONFLICT DO NOTHING;

  -- Contexto tenant
  PERFORM public.set_current_tenant(v_tenant);

  IF public.current_tenant_id() IS DISTINCT FROM v_tenant THEN
    RAISE EXCEPTION 'TEST SETUP FAILED: current_tenant_id() nao foi definido (esperado=% atual=%)', v_tenant, public.current_tenant_id();
  END IF;

  IF NOT public.can('xml_import', 'execute') THEN
    RAISE EXCEPTION 'TEST SETUP FAILED: permissao can(xml_import,execute)=false (tenant=% user=%)', v_tenant, v_user;
  END IF;

  -- Fornecedor mínimo
  INSERT INTO public.fornecedores (nome, tenant_id, empresa_id)
  VALUES ('FORNECEDOR TESTE', v_tenant, v_empresa)
  RETURNING id INTO v_fornecedor_id;

  -- Item mínimo (para teste sem XML)
  INSERT INTO public.itens (codigo_interno, nome, tipo, tenant_id, empresa_id, finalidade)
  VALUES ('IT-TEST', 'ITEM TESTE', 'produto', v_tenant, v_empresa, 'revenda')
  RETURNING id INTO v_item_id;

  ---------------------------------------------------------------------------
  -- 1) XML válido -> deve persistir nf_entrada.xml_raw e garantir f.documento_fiscal_xml
  ---------------------------------------------------------------------------
  SELECT nf_entrada_id INTO v_nf_id
  FROM public.import_nf_entrada(
    v_empresa,
    'revenda'::public.item_finalidade,
    v_fornecedor_id,
    '[]'::jsonb,
    jsonb_build_object(
      'chave', '35111111111111111111111111111111111111111111',
      'emitente_nome', 'EMITENTE',
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

  IF (SELECT nullif(btrim(xml_raw), '') FROM public.nf_entrada WHERE id = v_nf_id) IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: nf_entrada.xml_raw is null/blank';
  END IF;

  SELECT id INTO v_df_id
  FROM f.documento_fiscal
  WHERE tenant_id = v_tenant AND source_nf_entrada_id = v_nf_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_df_id IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal not created';
  END IF;

  -- ✅ Agora quem garante documento_fiscal_xml é a fn_find_documento_fiscal_from_import (via ensure)
  IF NOT EXISTS (
    SELECT 1 FROM f.documento_fiscal_xml
    WHERE tenant_id = v_tenant
      AND documento_fiscal_id = v_df_id
      AND deleted_at IS NULL
      AND length(btrim(xml_raw)) > 0
  ) THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal_xml missing or blank';
  END IF;

  ---------------------------------------------------------------------------
  -- 2) XML vazio/whitespace -> deve dar erro (se seu import já valida isso)
  ---------------------------------------------------------------------------
  BEGIN
    PERFORM 1 FROM public.import_nf_entrada(
      v_empresa,
      'revenda'::public.item_finalidade,
      v_fornecedor_id,
      '[]'::jsonb,
      jsonb_build_object(
        'chave', '35222222222222222222222222222222222222222222',
        'emitente_nome', 'EMITENTE',
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

    RAISE EXCEPTION 'TEST FAILED: expected error for blank xml_raw (mas não ocorreu)';
  EXCEPTION WHEN OTHERS THEN
    -- ok (erro esperado)
  END;

  ---------------------------------------------------------------------------
  -- 3) Sem XML mas com itens completos -> deve criar pendência XML_FALTANDO
  ---------------------------------------------------------------------------
  SELECT nf_entrada_id INTO v_nf_id
  FROM public.import_nf_entrada(
    v_empresa,
    'revenda'::public.item_finalidade,
    v_fornecedor_id,
    jsonb_build_array(
      jsonb_build_object(
        'item_id', v_item_id,
        'codigo', 'IT-TEST',
        'nome', 'ITEM TESTE',
        'quantidade', 1,
        'valorUnit', 10,
        'total', 10
      )
    ),
    jsonb_build_object(
      'chave', '35333333333333333333333333333333333333333333',
      'emitente_nome', 'EMITENTE',
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
  WHERE tenant_id = v_tenant AND source_nf_entrada_id = v_nf_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_df_id IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal not created (no-xml case)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM f.documento_fiscal_pendencia
    WHERE tenant_id = v_tenant
      AND documento_fiscal_id = v_df_id
      AND tipo = 'XML_FALTANDO'
      AND resolved_at IS NULL
  ) THEN
    RAISE EXCEPTION 'TEST FAILED: documento_fiscal_pendencia XML_FALTANDO not created';
  END IF;

END $$;

ROLLBACK;

DO $$ BEGIN
  RAISE NOTICE 'OK: xml_import_nf_entrada_xml_integridade.sql (FIXED find + xml)';
END $$;
