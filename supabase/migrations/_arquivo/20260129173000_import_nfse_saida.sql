begin;
-- TODO: FASE 2 - UI import NFSe (botão + parse XML no front)

create or replace function public.import_nfse_saida(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_nfse_json jsonb,
  p_xml_raw text
) returns table(status text, message text, documento_fiscal_id uuid)
language plpgsql
security definer
set search_path = 'public','f','a'
as $$
#variable_conflict use_column
declare
  v_numero text;
  v_serie text;
  v_prestador_cnpj text;
  v_tomador_documento text;

  v_prestador_digits text;
  v_tomador_digits text;
  v_chave_acesso text;

  v_emissao_date date;
  v_competencia_date date;

  v_valor_servicos numeric(15,2);
  v_valor_deducoes numeric(15,2);
  v_valor_inss numeric(15,2);
  v_valor_iss numeric(15,2);
  v_valor_iss_retido numeric(15,2);
  v_base_calculo numeric(15,2);
  v_aliquota numeric(7,4);
  v_valor_liquido numeric(15,2);
  v_valor_total numeric(15,2);

  v_iss_retido_raw text;
  v_iss_retido boolean;

  v_discriminacao text;
  v_municipio_codigo text;
  v_codigo_verificacao text;

  v_tomador_razao_social text;
  v_tomador_nome_fantasia text;
  v_tomador_email text;
  v_tomador_telefone text;

  v_end_logradouro text;
  v_end_numero text;
  v_end_complemento text;
  v_end_bairro text;
  v_end_cidade text;
  v_end_uf text;
  v_end_cep text;
  v_endereco_full text;

  v_cliente_id integer;
  v_df_id uuid;
  v_existing_df_id uuid;
  v_inserted boolean;

  v_has_doc_key boolean;
  v_has_razao_social boolean;
  v_has_nome_fantasia boolean;
  v_has_email_financeiro boolean;
  v_has_contato_email boolean;
  v_has_contato_nome boolean;
  v_has_contato_telefone boolean;
  v_has_cep boolean;
  v_has_logradouro boolean;
  v_has_numero_endereco boolean;
  v_has_complemento boolean;
  v_has_bairro boolean;
  v_has_cidade boolean;
  v_has_uf boolean;
  v_has_pais boolean;

  v_extra_valor_pis numeric(15,2);
  v_extra_valor_cofins numeric(15,2);
  v_extra_valor_ir numeric(15,2);
  v_extra_valor_csll numeric(15,2);

  v_sql text;
begin
  begin
    if auth.uid() is null then
      raise exception 'Nao autenticado';
    end if;

    if p_tenant_id is null then
      raise exception 'tenant_id obrigatorio';
    end if;
    if p_empresa_id is null then
      raise exception 'empresa_id obrigatorio';
    end if;
    if p_nfse_json is null then
      raise exception 'p_nfse_json obrigatorio';
    end if;

    -- Contexto tenant/empresa para RLS + public.can()/current_*()
    perform set_config('app.tenant_id', p_tenant_id::text, true);
    perform set_config('app.current_empresa_id', p_empresa_id::text, true);

    if not exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = p_tenant_id
        and tm.status in ('active','ativo')
    ) then
      raise exception 'Tenant nao autorizado';
    end if;

    if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'empresas') then
      if not exists (
        select 1
        from public.empresas e
        where e.id = p_empresa_id
          and e.tenant_id = p_tenant_id
          and e.ativo = true
      ) then
        raise exception 'Empresa nao encontrada para este tenant';
      end if;
    end if;

    if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'empresa_memberships') then
      if not exists (
        select 1
        from public.empresa_memberships em
        where em.user_id = auth.uid()
          and em.tenant_id = p_tenant_id
          and em.empresa_id = p_empresa_id
          and em.status = 'active'
      ) then
        raise exception 'Sem acesso a esta empresa';
      end if;
    end if;

    if not (
      public.can('xml_import','execute')
      or public.can('xml_import_faturamento','execute')
    ) then
      raise exception 'Sem permissao para importar XML';
    end if;

    -- Campos obrigatórios
    v_numero := nullif(trim(coalesce(p_nfse_json->>'numero','')), '');
    v_serie := nullif(trim(coalesce(p_nfse_json->>'serie','')), '');
    v_prestador_cnpj := nullif(trim(coalesce(p_nfse_json->>'prestador_cnpj', p_nfse_json#>>'{prestador,cnpj}')), '');
    v_tomador_documento := nullif(trim(coalesce(p_nfse_json->>'tomador_documento', p_nfse_json#>>'{tomador,documento}')), '');

    if v_numero is null then
      raise exception 'numero obrigatorio';
    end if;
    if v_serie is null then
      raise exception 'serie obrigatoria';
    end if;
    if v_prestador_cnpj is null then
      raise exception 'prestador_cnpj obrigatorio';
    end if;
    if v_tomador_documento is null then
      raise exception 'tomador_documento obrigatorio';
    end if;

    v_prestador_digits := regexp_replace(v_prestador_cnpj, '\\D', '', 'g');
    v_tomador_digits := regexp_replace(v_tomador_documento, '\\D', '', 'g');

    if v_prestador_digits is null or length(v_prestador_digits) = 0 then
      raise exception 'prestador_cnpj invalido';
    end if;
    if v_tomador_digits is null or length(v_tomador_digits) = 0 then
      raise exception 'tomador_documento invalido';
    end if;

    -- NFSe não tem chave 44; criar determinística por tenant
    v_chave_acesso := 'NFSE:' || v_prestador_digits || ':' || v_serie || ':' || v_numero;

    -- Hard guarantee against duplicates:
    -- serialize by (tenant_id + chave_acesso) and reject if already imported.
    perform pg_advisory_xact_lock(hashtext(p_tenant_id::text || ':' || v_chave_acesso)::bigint);

    select df.id into v_existing_df_id
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id
      and df.chave_acesso = v_chave_acesso
      and df.operacao = 'SAIDA'
      and df.natureza = 'SERVICO'
      and df.modelo = 'NFSE'
      and df.deleted_at is null
    limit 1;

    if v_existing_df_id is not null then
      raise exception 'NFSe ja importada (chave %)', v_chave_acesso;
    end if;

    -- Datas
    if nullif(p_nfse_json->>'data_emissao', '') is not null then
      v_emissao_date := (p_nfse_json->>'data_emissao')::timestamptz::date;
    end if;

    if nullif(p_nfse_json->>'competencia_date', '') is not null then
      v_competencia_date := date_trunc('month', (p_nfse_json->>'competencia_date')::date)::date;
    elsif nullif(p_nfse_json->>'competencia', '') is not null then
      v_competencia_date := date_trunc('month', ((p_nfse_json->>'competencia') || '-01')::date)::date;
    elsif v_emissao_date is not null then
      v_competencia_date := date_trunc('month', v_emissao_date)::date;
    end if;

    -- Valores (default 0)
    v_valor_servicos := coalesce(nullif(p_nfse_json#>>'{valores,valor_servicos}', '')::numeric, 0);
    v_valor_deducoes := coalesce(nullif(p_nfse_json#>>'{valores,valor_deducoes}', '')::numeric, 0);
    v_valor_inss := coalesce(nullif(p_nfse_json#>>'{valores,valor_inss}', '')::numeric, 0);

    v_valor_iss := coalesce(nullif(p_nfse_json#>>'{valores,valor_iss}', '')::numeric, 0);
    v_valor_iss_retido := coalesce(nullif(p_nfse_json#>>'{valores,valor_iss_retido}', '')::numeric, 0);
    v_base_calculo := coalesce(nullif(p_nfse_json#>>'{valores,base_calculo}', '')::numeric, 0);
    v_aliquota := coalesce(nullif(p_nfse_json#>>'{valores,aliquota}', '')::numeric, 0);
    v_valor_liquido := nullif(p_nfse_json#>>'{valores,valor_liquido}', '')::numeric;

    v_valor_total := coalesce(v_valor_liquido, v_valor_servicos, 0);

    -- Flags / outros campos
    v_iss_retido_raw := nullif(p_nfse_json#>>'{valores,iss_retido}', '');
    v_iss_retido := coalesce(v_iss_retido_raw in ('1','true','TRUE','t','T','sim','SIM','S','s'), false);

    v_discriminacao := nullif(coalesce(p_nfse_json->>'discriminacao', p_nfse_json#>>'{servico,discriminacao}'), '');
    v_municipio_codigo := nullif(coalesce(
      p_nfse_json->>'municipio_codigo',
      p_nfse_json->>'nfse_municipio_codigo',
      p_nfse_json#>>'{orgao_gerador,codigo_municipio}',
      p_nfse_json#>>'{servico,codigo_municipio}'
    ), '');
    v_codigo_verificacao := nullif(coalesce(p_nfse_json->>'codigo_verificacao', p_nfse_json->>'nfse_codigo_verificacao'), '');

    -- Tomador (cliente)
    v_tomador_razao_social := nullif(p_nfse_json#>>'{tomador,razao_social}', '');
    v_tomador_nome_fantasia := nullif(p_nfse_json#>>'{tomador,nome_fantasia}', '');
    v_tomador_email := nullif(coalesce(p_nfse_json#>>'{tomador,email}', p_nfse_json#>>'{tomador,contato,email}'), '');
    v_tomador_telefone := nullif(coalesce(p_nfse_json#>>'{tomador,telefone}', p_nfse_json#>>'{tomador,contato,telefone}'), '');

    v_end_logradouro := nullif(p_nfse_json#>>'{tomador,endereco,logradouro}', '');
    v_end_numero := nullif(p_nfse_json#>>'{tomador,endereco,numero}', '');
    v_end_complemento := nullif(p_nfse_json#>>'{tomador,endereco,complemento}', '');
    v_end_bairro := nullif(p_nfse_json#>>'{tomador,endereco,bairro}', '');
    v_end_cidade := nullif(coalesce(p_nfse_json#>>'{tomador,endereco,cidade}', p_nfse_json#>>'{tomador,endereco,municipio}'), '');
    v_end_uf := nullif(p_nfse_json#>>'{tomador,endereco,uf}', '');
    v_end_cep := nullif(p_nfse_json#>>'{tomador,endereco,cep}', '');

    v_endereco_full := nullif(trim(concat_ws(', ',
      nullif(v_end_logradouro,''),
      nullif(v_end_numero,''),
      nullif(v_end_complemento,''),
      nullif(v_end_bairro,''),
      nullif(v_end_cidade,''),
      nullif(v_end_uf,''),
      nullif(v_end_cep,'')
    )), '');

    -- Descobrir se temos colunas opcionais em clientes (bases mais antigas podem não ter)
    select exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='clientes' and column_name='documento_key'
    ) into v_has_doc_key;

    -- Lookup cliente por documento
    v_cliente_id := null;
    if v_has_doc_key then
      select c.id into v_cliente_id
      from public.clientes c
      where c.tenant_id = p_tenant_id
        and c.empresa_id = p_empresa_id
        and c.documento_key = public.fn_documento_key(v_tomador_digits)
      limit 1;
    else
      select c.id into v_cliente_id
      from public.clientes c
      where c.tenant_id = p_tenant_id
        and c.empresa_id = p_empresa_id
        and regexp_replace(coalesce(c.documento,''), '\\D', '', 'g') = v_tomador_digits
      limit 1;
    end if;

    if v_cliente_id is null then
      insert into public.clientes(
        tenant_id,
        empresa_id,
        nome,
        documento,
        email,
        telefone,
        endereco,
        ativo,
        criado_em,
        atualizado_em
      ) values (
        p_tenant_id,
        p_empresa_id,
        upper(coalesce(v_tomador_nome_fantasia, v_tomador_razao_social, 'CLIENTE')),
        v_tomador_digits,
        v_tomador_email,
        v_tomador_telefone,
        v_endereco_full,
        true,
        now(),
        now()
      ) returning id into v_cliente_id;
    else
      update public.clientes
      set nome = upper(coalesce(v_tomador_nome_fantasia, v_tomador_razao_social, nome)),
          documento = coalesce(v_tomador_digits, documento),
          email = coalesce(v_tomador_email, email),
          telefone = coalesce(v_tomador_telefone, telefone),
          endereco = coalesce(v_endereco_full, endereco),
          ativo = true,
          atualizado_em = now()
      where id = v_cliente_id;
    end if;

    -- Best-effort: popular colunas extras em clientes quando existirem
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='razao_social') into v_has_razao_social;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='nome_fantasia') into v_has_nome_fantasia;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='email_financeiro') into v_has_email_financeiro;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='contato_email') into v_has_contato_email;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='contato_nome') into v_has_contato_nome;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='contato_telefone') into v_has_contato_telefone;

    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='cep') into v_has_cep;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='logradouro') into v_has_logradouro;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='numero_endereco') into v_has_numero_endereco;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='complemento') into v_has_complemento;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='bairro') into v_has_bairro;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='cidade') into v_has_cidade;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='uf') into v_has_uf;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='pais') into v_has_pais;

    if v_has_razao_social then
      execute 'update public.clientes set razao_social = upper($1) where id = $2'
      using coalesce(v_tomador_razao_social, v_tomador_nome_fantasia), v_cliente_id;
    end if;
    if v_has_nome_fantasia then
      execute 'update public.clientes set nome_fantasia = upper($1) where id = $2'
      using coalesce(v_tomador_nome_fantasia, v_tomador_razao_social), v_cliente_id;
    end if;
    if v_has_email_financeiro then
      execute 'update public.clientes set email_financeiro = coalesce($1, email_financeiro) where id = $2'
      using v_tomador_email, v_cliente_id;
    end if;
    if v_has_contato_email then
      execute 'update public.clientes set contato_email = coalesce($1, contato_email) where id = $2'
      using v_tomador_email, v_cliente_id;
    end if;
    if v_has_contato_nome then
      execute 'update public.clientes set contato_nome = coalesce($1, contato_nome) where id = $2'
      using nullif(p_nfse_json#>>'{tomador,contato,nome}', ''), v_cliente_id;
    end if;
    if v_has_contato_telefone then
      execute 'update public.clientes set contato_telefone = coalesce($1, contato_telefone) where id = $2'
      using v_tomador_telefone, v_cliente_id;
    end if;

    if v_has_cep then
      execute 'update public.clientes set cep = coalesce($1, cep) where id = $2'
      using v_end_cep, v_cliente_id;
    end if;
    if v_has_logradouro then
      execute 'update public.clientes set logradouro = coalesce($1, logradouro) where id = $2'
      using v_end_logradouro, v_cliente_id;
    end if;
    if v_has_numero_endereco then
      execute 'update public.clientes set numero_endereco = coalesce($1, numero_endereco) where id = $2'
      using v_end_numero, v_cliente_id;
    end if;
    if v_has_complemento then
      execute 'update public.clientes set complemento = coalesce($1, complemento) where id = $2'
      using v_end_complemento, v_cliente_id;
    end if;
    if v_has_bairro then
      execute 'update public.clientes set bairro = coalesce($1, bairro) where id = $2'
      using v_end_bairro, v_cliente_id;
    end if;
    if v_has_cidade then
      execute 'update public.clientes set cidade = coalesce($1, cidade) where id = $2'
      using v_end_cidade, v_cliente_id;
    end if;
    if v_has_uf then
      execute 'update public.clientes set uf = coalesce($1, uf) where id = $2'
      using v_end_uf, v_cliente_id;
    end if;
    if v_has_pais then
      execute 'update public.clientes set pais = coalesce($1, pais) where id = $2'
      using nullif(p_nfse_json#>>'{tomador,endereco,pais}', ''), v_cliente_id;
    end if;

    -- Insert documento_fiscal (NFSe SAIDA/SERVICO)
    insert into f.documento_fiscal(
      tenant_id,
      empresa_id,
      chave_acesso,
      operacao,
      natureza,
      modelo,
      serie,
      numero,
      emissao_date,
      competencia_date,
      cliente_id,
      valor_servicos,
      valor_total,
      nfse_municipio_codigo,
      nfse_codigo_verificacao,
      nfse_status,
      servico_discriminacao,
      updated_at
    ) values (
      p_tenant_id,
      p_empresa_id,
      v_chave_acesso,
      'SAIDA',
      'SERVICO',
      'NFSE',
      v_serie,
      v_numero,
      v_emissao_date,
      v_competencia_date,
      v_cliente_id,
      coalesce(v_valor_servicos, 0),
      coalesce(v_valor_total, 0),
      v_municipio_codigo,
      v_codigo_verificacao,
      'EMITIDA',
      v_discriminacao,
      now()
    )
    returning id into v_df_id;

    v_inserted := true;

    -- Upsert XML raw
    insert into f.documento_fiscal_xml(
      tenant_id,
      documento_fiscal_id,
      chave_acesso,
      xml_raw
    ) values (
      p_tenant_id,
      v_df_id,
      v_chave_acesso,
      coalesce(p_xml_raw, '')
    )
    on conflict (tenant_id, documento_fiscal_id) do update
      set chave_acesso = excluded.chave_acesso,
          xml_raw = excluded.xml_raw,
          deleted_at = null;

    -- Impostos / retenções
    -- Valores adicionais (se existirem no JSON)
    v_extra_valor_pis := coalesce(nullif(p_nfse_json#>>'{valores,valor_pis}', '')::numeric, 0);
    v_extra_valor_cofins := coalesce(nullif(p_nfse_json#>>'{valores,valor_cofins}', '')::numeric, 0);
    v_extra_valor_ir := coalesce(nullif(p_nfse_json#>>'{valores,valor_ir}', '')::numeric, 0);
    v_extra_valor_csll := coalesce(nullif(p_nfse_json#>>'{valores,valor_csll}', '')::numeric, 0);

    -- ISS
    if v_iss_retido or v_valor_iss_retido > 0 then
      if coalesce(v_valor_iss_retido, 0) > 0 then
        insert into f.documento_fiscal_imposto(
          tenant_id,
          documento_fiscal_id,
          imposto,
          natureza,
          base_original,
          deducoes,
          base_calculo,
          aliquota,
          valor_calculado,
          updated_at
        ) values (
          p_tenant_id,
          v_df_id,
          'ISS',
          'RETENCAO',
          coalesce(v_valor_servicos, 0),
          coalesce(v_valor_deducoes, 0),
          coalesce(v_base_calculo, 0),
          coalesce(v_aliquota, 0),
          coalesce(v_valor_iss_retido, 0),
          now()
        )
        on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
          set base_original = excluded.base_original,
              deducoes = excluded.deducoes,
              base_calculo = excluded.base_calculo,
              aliquota = excluded.aliquota,
              valor_calculado = excluded.valor_calculado,
              updated_at = now(),
              deleted_at = null;
      end if;

      -- Se veio retido, remove eventual ISS débito (best-effort)
      update f.documento_fiscal_imposto
      set deleted_at = now()
      where tenant_id = p_tenant_id
        and f.documento_fiscal_imposto.documento_fiscal_id = v_df_id
        and imposto = 'ISS'
        and natureza = 'DEBITO'
        and deleted_at is null;
    else
      if coalesce(v_valor_iss, 0) > 0 then
        insert into f.documento_fiscal_imposto(
          tenant_id,
          documento_fiscal_id,
          imposto,
          natureza,
          base_original,
          deducoes,
          base_calculo,
          aliquota,
          valor_calculado,
          updated_at
        ) values (
          p_tenant_id,
          v_df_id,
          'ISS',
          'DEBITO',
          coalesce(v_valor_servicos, 0),
          coalesce(v_valor_deducoes, 0),
          coalesce(v_base_calculo, 0),
          coalesce(v_aliquota, 0),
          coalesce(v_valor_iss, 0),
          now()
        )
        on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
          set base_original = excluded.base_original,
              deducoes = excluded.deducoes,
              base_calculo = excluded.base_calculo,
              aliquota = excluded.aliquota,
              valor_calculado = excluded.valor_calculado,
              updated_at = now(),
              deleted_at = null;
      end if;

      -- Se veio débito, remove eventual ISS retenção (best-effort)
      update f.documento_fiscal_imposto
      set deleted_at = now()
      where tenant_id = p_tenant_id
        and f.documento_fiscal_imposto.documento_fiscal_id = v_df_id
        and imposto = 'ISS'
        and natureza = 'RETENCAO'
        and deleted_at is null;
    end if;

    -- INSS (retenção)
    if coalesce(v_valor_inss, 0) > 0 then
      insert into f.documento_fiscal_imposto(
        tenant_id,
        documento_fiscal_id,
        imposto,
        natureza,
        base_original,
        deducoes,
        base_calculo,
        aliquota,
        valor_calculado,
        updated_at
      ) values (
        p_tenant_id,
        v_df_id,
        'INSS',
        'RETENCAO',
        coalesce(v_valor_servicos, 0),
        coalesce(v_valor_deducoes, 0),
        coalesce(v_base_calculo, 0),
        coalesce(v_aliquota, 0),
        coalesce(v_valor_inss, 0),
        now()
      )
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    -- PIS/COFINS/IR/CSLL (retenção padrão)
    if coalesce(v_extra_valor_pis, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'PIS','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_pis,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    if coalesce(v_extra_valor_cofins, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'COFINS','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_cofins,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    if coalesce(v_extra_valor_ir, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'IR','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_ir,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    if coalesce(v_extra_valor_csll, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'CSLL','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_csll,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    status := 'ok';
    message := case when v_inserted then 'NFSe importada' else 'NFSe atualizada' end;
    documento_fiscal_id := v_df_id;
    return next;
    return;
  exception when others then
    status := 'error';
    message := sqlerrm;
    documento_fiscal_id := null;
    return next;
    return;
  end;
end;
$$;
grant execute on function public.import_nfse_saida(uuid, uuid, jsonb, text) to authenticated;
commit;
notify pgrst, 'reload schema';
