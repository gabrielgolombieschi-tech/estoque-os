BEGIN;

-- Pendências de documento fiscal (ex.: XML faltando)
CREATE TABLE IF NOT EXISTS f.documento_fiscal_pendencia (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  empresa_id uuid NOT NULL,
  documento_fiscal_id uuid NOT NULL,
  tipo text NOT NULL,
  detalhe text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'documento_fiscal_pendencia_pkey'
  ) THEN
    ALTER TABLE ONLY f.documento_fiscal_pendencia
      ADD CONSTRAINT documento_fiscal_pendencia_pkey PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_doc_pend'
  ) THEN
    ALTER TABLE ONLY f.documento_fiscal_pendencia
      ADD CONSTRAINT uq_doc_pend UNIQUE (tenant_id, documento_fiscal_id, tipo);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_doc_pend__doc'
  ) THEN
    ALTER TABLE ONLY f.documento_fiscal_pendencia
      ADD CONSTRAINT fk_doc_pend__doc
      FOREIGN KEY (documento_fiscal_id) REFERENCES f.documento_fiscal(id) ON DELETE CASCADE;
  END IF;
END$$;

-- Import de NF-e (entrada): integridade do XML + cópia em f.documento_fiscal_xml + pendência quando XML faltar.
CREATE OR REPLACE FUNCTION public.import_nf_entrada(
  p_empresa_id uuid,
  p_finalidade_contexto public.item_finalidade,
  p_fornecedor_id bigint,
  p_itens_json jsonb,
  p_nf_json jsonb,
  p_tenant_id uuid,
  p_xml_raw text,
  p_gerar_contas_pagar boolean default false,
  p_parcelas_json jsonb default null,
  p_os_id integer default null,
  p_baixar_os boolean default false,
  p_motivo_compra_id uuid default null,
  p_solicitante_usuario_id uuid default null
) returns table(status text, message text, nf_entrada_id bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nf_id bigint;
  v_chave text;
  v_emitente text;
  v_numero text;
  v_serie text;
  v_data_emissao timestamptz;
  v_total_nf numeric(14,2);
  v_soma_parcelas numeric(14,2);

  v_categoria_id uuid;
  v_parcelamento_id uuid;

  v_it jsonb;

  v_item_id int;
  v_qtd numeric(14,3);
  v_vunit numeric(14,6);
  v_vtotal numeric(14,2);

  v_has_os boolean;

  v_solicitante_ok boolean;
  v_motivo_ok boolean;

  v_xml_trim text;
  v_doc_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id obrigatorio';
  end if;

  perform set_config('app.tenant_id', p_tenant_id::text, true);

  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant_id
      and tm.status in ('active','ativo')
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if not public.can('xml_import','execute') then
    raise exception 'Sem permissao para importar XML';
  end if;

  if p_nf_json is null then
    raise exception 'p_nf_json e obrigatorio';
  end if;

  -- XML: se veio string, deve ser o XML completo (nunca whitespace/empty).
  v_xml_trim := case when p_xml_raw is null then null else nullif(btrim(p_xml_raw), '') end;
  if p_xml_raw is not null and v_xml_trim is null then
    raise exception 'XML vazio/whitespace: envie o XML completo (xmlRaw).';
  end if;

  -- Se XML nao veio, permitir somente se itens estiverem completos (item_id + qtd > 0).
  if p_xml_raw is null then
    if p_itens_json is null or jsonb_typeof(p_itens_json) <> 'array' or jsonb_array_length(p_itens_json) = 0 then
      raise exception 'XML ausente: informe itens completos para importar sem XML.';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_itens_json) elem
      where coalesce(nullif((elem->>'item_id')::int, 0), 0) <= 0
         or coalesce((elem->>'quantidade')::numeric, (elem->>'qtd')::numeric, 0) <= 0
    ) then
      raise exception 'XML ausente: itens incompletos (exige item_id e quantidade > 0).';
    end if;
  end if;

  -- SOLICITANTE (OBRIGATORIO)
  if p_solicitante_usuario_id is null then
    raise exception 'Solicitante (usuario) e obrigatorio para importar';
  end if;

  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join public.tenant_memberships tm on tm.user_id = u.auth_user_id and tm.tenant_id = p_tenant_id
    where u.id = p_solicitante_usuario_id
      and u.deleted_at is null
      and u.ativo = true
      and ue.deleted_at is null
      and ue.ativo = true
      and ue.empresa_id = p_empresa_id
      and tm.status in ('active','ativo')
  ) into v_solicitante_ok;

  if not coalesce(v_solicitante_ok,false) then
    raise exception 'Solicitante invalido/sem acesso (usuario_id=%)', p_solicitante_usuario_id;
  end if;

  -- MOTIVO (OBRIGATORIO)
  if p_motivo_compra_id is null then
    raise exception 'Classificacao/Motivo e obrigatorio para importar';
  end if;

  select exists (
    select 1
    from f.motivo_compra mc
    where mc.id = p_motivo_compra_id
      and mc.tenant_id = p_tenant_id
      and mc.ativo = true
      and mc.deleted_at is null
      and mc.aplica_em in ('PRODUTO','AMBOS')
      and mc.codigo is not null
      and upper(trim(mc.codigo)) <> 'NAO_CLASSIFICADO'
  ) into v_motivo_ok;

  if not coalesce(v_motivo_ok,false) then
    raise exception 'Motivo invalido/inativo ou nao aplicavel a PRODUTO (id=%)', p_motivo_compra_id;
  end if;

  v_chave := nullif(trim(p_nf_json->>'chave'), '');
  if v_chave is null then
    raise exception 'NF sem chave (p_nf_json.chave)';
  end if;

  -- Ja existe?
  select id into v_nf_id
  from public.nf_entrada
  where chave = v_chave
  limit 1;

  if v_nf_id is not null then
    status := 'ja_importada';
    message := 'NF ja importada';
    nf_entrada_id := v_nf_id;
    return next;
    return;
  end if;

  v_emitente := coalesce(nullif(p_nf_json->>'emitente_nome',''), 'Emitente');
  v_numero   := coalesce(nullif(p_nf_json->>'numero',''), '');
  v_serie    := coalesce(nullif(p_nf_json->>'serie',''), '');
  v_data_emissao := nullif(p_nf_json->>'data_emissao','')::timestamptz;
  v_total_nf := coalesce((p_nf_json->>'valor_total')::numeric, 0);

  -- Se veio OS, validar se existe e pertence ao tenant
  v_has_os := (p_os_id is not null);

  if v_has_os then
    if not exists (
      select 1
      from public.ordens_servico os
      where os.id = p_os_id
        and os.tenant_id = p_tenant_id
    ) then
      raise exception 'OS invalida (id=%) para este tenant', p_os_id;
    end if;
  end if;

  -- 1) NF
  insert into public.nf_entrada (
    chave,
    numero,
    serie,
    emitente_nome,
    emitente_cnpj,
    data_emissao,
    valor_produtos,
    valor_frete,
    valor_seguro,
    valor_desconto,
    valor_outros,
    valor_total,
    xml_raw,
    fornecedor_id,
    tenant_id,
    empresa_id,
    finalidade_contexto,
    os_id,
    baixa_os_automatica,
    motivo_compra_id,
    solicitante_usuario_id
  )
  values (
    v_chave,
    v_numero,
    v_serie,
    v_emitente,
    p_nf_json->>'emitente_cnpj',
    v_data_emissao,
    coalesce((p_nf_json->>'valor_produtos')::numeric, 0),
    coalesce((p_nf_json->>'valor_frete')::numeric, 0),
    coalesce((p_nf_json->>'valor_seguro')::numeric, 0),
    coalesce((p_nf_json->>'valor_desconto')::numeric, 0),
    coalesce((p_nf_json->>'valor_outros')::numeric, 0),
    v_total_nf,
    p_xml_raw,
    p_fornecedor_id,
    p_tenant_id,
    p_empresa_id,
    p_finalidade_contexto,
    p_os_id,
    p_baixar_os,
    p_motivo_compra_id,
    p_solicitante_usuario_id
  )
  returning id into v_nf_id;

  -- 2) NF itens
  insert into public.nf_entrada_itens (
    nf_entrada_id,
    item_id,
    codigo_fornecedor,
    descricao,
    ncm,
    cfop,
    qtd,
    v_unit,
    v_prod,
    v_icms,
    v_ipi,
    v_pis,
    v_cofins,
    aliq_icms,
    aliq_ipi,
    aliq_pis,
    aliq_cofins,
    aliquota_icms,
    aliquota_ipi,
    aliquota_pis,
    aliquota_cofins,
    tenant_id
  )
  select
    v_nf_id,
    nullif((elem->>'item_id')::bigint, 0),
    elem->>'codigo',
    elem->>'nome',
    elem->>'ncm',
    elem->>'cfop',
    coalesce((elem->>'quantidade')::numeric, (elem->>'qtd')::numeric, 0),
    coalesce((elem->>'valorUnit')::numeric, (elem->>'v_unit')::numeric, 0),
    coalesce((elem->>'total')::numeric, (elem->>'v_prod')::numeric, 0),
    coalesce((elem->>'v_icms')::numeric, 0),
    coalesce((elem->>'v_ipi')::numeric, 0),
    coalesce((elem->>'v_pis')::numeric, 0),
    coalesce((elem->>'v_cofins')::numeric, 0),
    nullif((elem->>'aliq_icms')::numeric, 0),
    nullif((elem->>'aliq_ipi')::numeric, 0),
    nullif((elem->>'aliq_pis')::numeric, 0),
    nullif((elem->>'aliq_cofins')::numeric, 0),
    nullif((elem->>'aliq_icms')::numeric, 0),
    nullif((elem->>'aliq_ipi')::numeric, 0),
    nullif((elem->>'aliq_pis')::numeric, 0),
    nullif((elem->>'aliq_cofins')::numeric, 0),
    p_tenant_id
  from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb)) elem;

  -- 3) Movimentacoes (ENTRADA)
  insert into public.movimentacoes (
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    custo_unitario_bruto,
    custo_unitario_real,
    credito_icms,
    credito_pis,
    credito_cofins,
    origem_nf_entrada_id,
    origem_os_id,
    v_ipi,
    v_icms,
    v_pis,
    v_cofins,
    v_frete_rateado,
    tenant_id,
    empresa_id
  )
  select
    (elem->>'item_id')::int,
    coalesce(nullif(elem->>'tipo',''), 'entrada'),
    coalesce((elem->>'quantidade')::numeric, (elem->>'qtd')::numeric, 0),
    elem->>'motivo',
    elem->>'realizado_por',
    coalesce(nullif(elem->>'data_movimentacao','')::timestamp, now()),
    nullif((elem->>'custo_unitario_bruto')::numeric, 0),
    nullif((elem->>'custo_unitario_real')::numeric, 0),
    coalesce((elem->>'credito_icms')::numeric, 0),
    coalesce((elem->>'credito_pis')::numeric, 0),
    coalesce((elem->>'credito_cofins')::numeric, 0),
    v_nf_id,
    null,
    coalesce((elem->>'v_ipi')::numeric, 0),
    coalesce((elem->>'v_icms')::numeric, 0),
    coalesce((elem->>'v_pis')::numeric, 0),
    coalesce((elem->>'v_cofins')::numeric, 0),
    coalesce((elem->>'v_frete_rateado')::numeric, 0),
    p_tenant_id,
    p_empresa_id
  from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb)) elem;

  -- 3.5) Documento fiscal (obrigatorio) + pendência quando XML faltar
  v_doc_id := f.fn_find_documento_fiscal_from_import(v_nf_id);

  if v_doc_id is null then
    raise exception 'Falha ao criar/atualizar documento fiscal para NF importada (nf_entrada_id=%).', v_nf_id;
  end if;

  if v_doc_id is not null and v_xml_trim is null then
    insert into f.documento_fiscal_pendencia (tenant_id, empresa_id, documento_fiscal_id, tipo, detalhe)
    values (p_tenant_id, p_empresa_id, v_doc_id, 'XML_FALTANDO', 'Importado sem XML (xml_raw ausente).')
    on conflict (tenant_id, documento_fiscal_id, tipo) do update set
      detalhe = excluded.detalhe,
      updated_at = now(),
      resolved_at = null;
  end if;

  -- 4) Financeiro (opcional)
  if coalesce(p_gerar_contas_pagar, false) then
    if not (public.can('financeiro','write') or public.can('financeiro','config')) then
      raise exception 'Sem permissao para gerar contas a pagar';
    end if;

    select c.id into v_categoria_id
    from public.financeiro_categorias c
    where c.tenant_id = p_tenant_id
      and c.tipo = 'DESPESA'
      and c.nome = 'Compras (NF Entrada)'
    limit 1;

    if v_categoria_id is null then
      insert into public.financeiro_categorias (tenant_id, nome, tipo, exige_os)
      values (p_tenant_id, 'Compras (NF Entrada)', 'DESPESA', false)
      returning id into v_categoria_id;
    end if;

    v_parcelamento_id := gen_random_uuid();

    if p_parcelas_json is null or jsonb_typeof(p_parcelas_json) <> 'array' or jsonb_array_length(p_parcelas_json) = 0 then
      p_parcelas_json := jsonb_build_array(
        jsonb_build_object(
          'numero', '001',
          'vencimento', coalesce((v_data_emissao)::date, current_date),
          'valor', v_total_nf
        )
      );
    end if;

    select coalesce(sum((p->>'valor')::numeric), 0)
      into v_soma_parcelas
    from jsonb_array_elements(p_parcelas_json) p;

    if abs(coalesce(v_soma_parcelas,0) - coalesce(v_total_nf,0)) > 0.05 then
      raise exception 'Soma das parcelas (%.2f) difere do total da NF (%.2f)', v_soma_parcelas, v_total_nf;
    end if;

    insert into public.financeiro_titulos (
      tenant_id,
      natureza,
      status,
      categoria_id,
      descricao,
      documento_ref,
      competencia,
      vencimento,
      valor_original,
      parcelamento_id,
      observacoes,
      nf_entrada_id,
      parcela_numero,
      fornecedor_id,
      motivo_compra_id,
      solicitante_usuario_id
    )
    select
      p_tenant_id,
      'PAGAR'::public.financeiro_natureza_titulo,
      'ABERTO'::public.financeiro_status_titulo,
      v_categoria_id,
      ('NF-e ' || coalesce(v_numero,'') || '/' || coalesce(v_serie,'') || ' - ' || v_emitente),
      v_chave,
      coalesce(date_trunc('month', coalesce(v_data_emissao, now()))::date, current_date),
      (p->>'vencimento')::date,
      (p->>'valor')::numeric,
      v_parcelamento_id,
      'Gerado automaticamente na importacao XML',
      v_nf_id,
      nullif(p->>'numero',''),
      p_fornecedor_id,
      p_motivo_compra_id,
      p_solicitante_usuario_id
    from jsonb_array_elements(p_parcelas_json) p
    on conflict do nothing;
  end if;

  -- 5) Vincular OS + criar/atualizar os_itens + baixa automatica (opcional)
  if v_has_os then
    for v_it in select * from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb))
    loop
      v_item_id := (v_it->>'item_id')::int;
      v_qtd := coalesce((v_it->>'quantidade')::numeric, (v_it->>'qtd')::numeric, 0);

      v_vunit := coalesce(
        nullif((v_it->>'valorUnit')::numeric, 0),
        nullif((v_it->>'v_unit')::numeric, 0),
        nullif((v_it->>'valor_unitario')::numeric, 0),
        0
      );

      v_vtotal := coalesce(
        nullif((v_it->>'total')::numeric, 0),
        nullif((v_it->>'v_prod')::numeric, 0),
        case when v_vunit > 0 and v_qtd > 0 then (v_vunit * v_qtd)::numeric(14,2) else 0 end
      );

      if v_item_id is null or v_item_id <= 0 then
        raise exception 'Item invalido em p_itens_json (item_id=%)', v_it->>'item_id';
      end if;

      if v_qtd <= 0 then
        raise exception 'Quantidade invalida para item_id=% (qtd=%)', v_item_id, v_qtd;
      end if;

      with upd as (
        update public.os_itens oi
           set quantidade = oi.quantidade + v_qtd,
               valor_total = oi.valor_total + v_vtotal,
               valor_unitario = case when v_vunit > 0 then v_vunit else oi.valor_unitario end,
               baixa_estoque = (oi.baixa_estoque or p_baixar_os),
               observacoes = coalesce(oi.observacoes,'')
         where oi.tenant_id = p_tenant_id
           and oi.os_id = p_os_id
           and oi.item_id = v_item_id
         returning 1
      )
      insert into public.os_itens (
        os_id, item_id, quantidade, valor_unitario, valor_total,
        desconto_percentual, desconto_valor, baixa_estoque, observacoes, tenant_id
      )
      select
        p_os_id, v_item_id, v_qtd,
        case
          when v_vunit > 0 then v_vunit
          when v_qtd > 0 and v_vtotal > 0 then (v_vtotal / v_qtd)
          else 0
        end,
        v_vtotal,
        0, 0, p_baixar_os,
        ('Gerado via importacao NF-e ' || v_chave),
        p_tenant_id
      where not exists (select 1 from upd);

      if p_baixar_os then
        insert into public.movimentacoes (
          item_id,
          tipo,
          quantidade,
          motivo,
          realizado_por,
          data_movimentacao,
          origem_nf_entrada_id,
          origem_os_id,
          tenant_id,
          empresa_id
        )
        values (
          v_item_id,
          'saida',
          v_qtd,
          ('Baixa automatica OS ' || p_os_id || ' via NF-e ' || v_chave),
          'sistema',
          now(),
          v_nf_id,
          p_os_id,
          p_tenant_id,
          p_empresa_id
        );
      end if;
    end loop;
  end if;

  status := 'ok';
  message := 'Importado com sucesso';
  nf_entrada_id := v_nf_id;
  return next;
end;
$$;

COMMIT;
