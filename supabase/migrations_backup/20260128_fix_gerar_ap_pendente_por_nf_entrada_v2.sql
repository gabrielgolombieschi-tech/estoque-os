begin;

-- Fix: make f.gerar_ap_pendente_por_nf_entrada_v2 compatible with the current finance schema.
-- The previous version referenced non-existent columns (ex.: f.documento_fiscal.tipo/status/origem/observacoes,
-- f.titulo.vencimento_date/solicitante_usuario_id/os_id, f.titulo_parcela.valor_original/status, etc).
--
-- Expected behavior:
-- - Upsert f.documento_fiscal by (tenant_id, source_nf_entrada_id)
-- - Upsert f.documento_fiscal_xml (store XML + hash)
-- - Create/update f.titulo (AP) and its parcelas based on p_parcelas_json (fallback to 001 à vista)
-- - Keep permissions: FINANCEIRO/ADMIN OR xml_import.execute (when called by an authenticated user)

create or replace function f.gerar_ap_pendente_por_nf_entrada_v2(
  p_nf_entrada_id bigint,
  p_force boolean default false,
  p_parcelas_json jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = 'f', 'public', 'a', 'c', 'extensions'
set row_security = 'off'
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_doc_id uuid;
  v_titulo_id uuid;

  v_emissao_date date;
  v_competencia_date date;
  v_total numeric(15,2);

  v_xml_hash text;

  v_parcelas jsonb;
  v_soma numeric(15,2) := 0;

  v_i int := 0;
  v_el jsonb;
  v_num text;
  v_venc date;
  v_val numeric(15,2);

  v_has_titulo_deleted_at boolean := false;
  v_has_parcela_deleted_at boolean := false;

  v_sql text;
  v_has_parcelas boolean := false;
  v_valor_aberto numeric(15,2) := 0;
begin
  select *
    into v_nf
  from public.nf_entrada n
  where n.id = p_nf_entrada_id
  limit 1;

  if v_nf.id is null then
    raise exception 'NF entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  -- Permissao:
  -- permite FINANCEIRO/ADMIN, OU quem tem capability xml_import.execute (para importacao gerar AP).
  if auth.uid() is not null then
    if not f.has_finance_access(v_nf.tenant_id, v_nf.empresa_id)
       and not public.can('xml_import','execute', v_nf.tenant_id)
    then
      raise exception 'Sem permissao para gerar contas a pagar (precisa FINANCEIRO/ADMIN ou xml_import.execute)';
    end if;
  end if;

  if v_nf.motivo_compra_id is null then
    raise exception 'NF sem motivo_compra_id. Importacao deve informar Classificacao/Motivo.';
  end if;

  if v_nf.solicitante_usuario_id is null then
    raise exception 'NF sem solicitante_usuario_id. Importacao deve informar solicitante.';
  end if;

  v_emissao_date := (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date;
  if v_emissao_date is null then
    v_emissao_date := (now() at time zone 'America/Sao_Paulo')::date;
  end if;

  v_competencia_date := date_trunc('month', v_emissao_date)::date;
  v_total := round(coalesce(v_nf.valor_total, 0), 2);

  -- Compat: algumas bases antigas nao tem deleted_at em f.titulo / f.titulo_parcela.
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'f'
      and table_name = 'titulo'
      and column_name = 'deleted_at'
  ) into v_has_titulo_deleted_at;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'f'
      and table_name = 'titulo_parcela'
      and column_name = 'deleted_at'
  ) into v_has_parcela_deleted_at;

  -- Documento fiscal (upsert por tenant + source_nf_entrada_id)
  insert into f.documento_fiscal (
    tenant_id,
    empresa_id,
    source_nf_entrada_id,
    fornecedor_id,
    chave_acesso,
    modelo,
    serie,
    numero,
    emissao_date,
    competencia_date,
    valor_total,
    valor_produtos,
    valor_frete,
    valor_seguro,
    valor_desconto,
    valor_outros,
    finalidade_import,
    os_id_import,
    pagamento_import_json
  )
  values (
    v_nf.tenant_id,
    v_nf.empresa_id,
    v_nf.id,
    v_nf.fornecedor_id::int,
    v_nf.chave,
    v_nf.modelo,
    v_nf.serie,
    v_nf.numero,
    v_emissao_date,
    v_competencia_date,
    v_total,
    round(coalesce(v_nf.valor_produtos, 0), 2),
    round(coalesce(v_nf.valor_frete, 0), 2),
    round(coalesce(v_nf.valor_seguro, 0), 2),
    round(coalesce(v_nf.valor_desconto, 0), 2),
    round(coalesce(v_nf.valor_outros, 0), 2),
    v_nf.finalidade_contexto,
    v_nf.os_id,
    p_parcelas_json
  )
  on conflict (tenant_id, source_nf_entrada_id)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    chave_acesso = excluded.chave_acesso,
    modelo = excluded.modelo,
    serie = excluded.serie,
    numero = excluded.numero,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    valor_produtos = excluded.valor_produtos,
    valor_frete = excluded.valor_frete,
    valor_seguro = excluded.valor_seguro,
    valor_desconto = excluded.valor_desconto,
    valor_outros = excluded.valor_outros,
    finalidade_import = excluded.finalidade_import,
    os_id_import = excluded.os_id_import,
    pagamento_import_json = excluded.pagamento_import_json,
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  returning id into v_doc_id;

  -- XML do documento (upsert)
  if v_nf.xml_raw is not null and length(v_nf.xml_raw) > 0 then
    v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');

    insert into f.documento_fiscal_xml (
      tenant_id,
      documento_fiscal_id,
      chave_acesso,
      xml_raw,
      xml_hash
    )
    values (
      v_nf.tenant_id,
      v_doc_id,
      v_nf.chave,
      v_nf.xml_raw,
      v_xml_hash
    )
    on conflict (tenant_id, documento_fiscal_id)
    do update set
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  -- Titulo AP (se existir e nao force, mantem; se force, recria parcelas)
  v_sql := '
    select t.id
    from f.titulo t
    where t.tenant_id = $1
      and t.empresa_id = $2
      and t.documento_fiscal_id = $3
      and t.tipo = ''AP''
      and t.origem = ''XML''';
  if v_has_titulo_deleted_at then
    v_sql := v_sql || ' and t.deleted_at is null';
  end if;
  v_sql := v_sql || ' limit 1';
  execute v_sql into v_titulo_id using v_nf.tenant_id, v_nf.empresa_id, v_doc_id;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id,
      empresa_id,
      tipo,
      status,
      origem,
      fornecedor_id,
      documento_fiscal_id,
      descricao,
      emissao_date,
      competencia_date,
      valor_total,
      valor_aberto,
      motivo_compra_id
    )
    values (
      v_nf.tenant_id,
      v_nf.empresa_id,
      'AP',
      'PENDENTE',
      'XML',
      v_nf.fornecedor_id::int,
      v_doc_id,
      ('NF-e ' || coalesce(v_nf.numero,'') || '/' || coalesce(v_nf.serie,'') || ' - ' || coalesce(v_nf.emitente_nome,'EMITENTE')),
      v_emissao_date,
      v_competencia_date,
      v_total,
      v_total,
      v_nf.motivo_compra_id
    )
    returning id into v_titulo_id;
  else
    -- Atualiza metadados do titulo (best-effort) e garante motivo
    update f.titulo
    set
      fornecedor_id = v_nf.fornecedor_id::int,
      emissao_date = v_emissao_date,
      competencia_date = v_competencia_date,
      valor_total = v_total,
      motivo_compra_id = v_nf.motivo_compra_id,
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
    where id = v_titulo_id
      and tenant_id = v_nf.tenant_id;

    if not p_force then
      -- Se ja existem parcelas, nao duplica.
      v_sql := '
        select exists(
          select 1
          from f.titulo_parcela tp
          where tp.tenant_id = $1
            and tp.titulo_id = $2';
      if v_has_parcela_deleted_at then
        v_sql := v_sql || ' and tp.deleted_at is null';
      end if;
      v_sql := v_sql || ' limit 1
        )';
      execute v_sql into v_has_parcelas using v_nf.tenant_id, v_titulo_id;
      if coalesce(v_has_parcelas,false) then
        return v_titulo_id;
      end if;
    else
      -- Soft delete parcelas antigas (quando existir coluna). Caso contrario, remove.
      if v_has_parcela_deleted_at then
        update f.titulo_parcela
        set deleted_at = now(),
            updated_at = now(),
            updated_by = a.fn_current_usuario_id()
        where tenant_id = v_nf.tenant_id
          and titulo_id = v_titulo_id
          and deleted_at is null;
      else
        delete from f.titulo_parcela
        where tenant_id = v_nf.tenant_id
          and titulo_id = v_titulo_id;
      end if;
    end if;
  end if;

  -- Parcelas: se vier array cria N parcelas; senao cria 001 a vista
  v_parcelas := coalesce(p_parcelas_json, '[]'::jsonb);

  if jsonb_typeof(v_parcelas) = 'array' and jsonb_array_length(v_parcelas) > 0 then
    v_i := 0;
    v_soma := 0;

    for v_el in select * from jsonb_array_elements(v_parcelas)
    loop
      v_num := coalesce(nullif(trim(v_el->>'numero'),''), lpad((v_i+1)::text, 3, '0'));
      v_num := regexp_replace(v_num, '\D', '', 'g');
      if v_num is null or v_num = '' then
        v_num := lpad((v_i+1)::text, 3, '0');
      else
        v_num := lpad(v_num, 3, '0');
      end if;

      v_venc := nullif(trim(v_el->>'vencimento'), '')::date;
      v_val := round(coalesce(nullif(trim(v_el->>'valor'), '')::numeric, 0), 2);

      if v_venc is null then
        raise exception 'Parcela sem vencimento_date (numero=%)', v_num;
      end if;
      if v_val <= 0 then
        raise exception 'Parcela com valor invalido (numero=% valor=%)', v_num, v_val;
      end if;

      insert into f.titulo_parcela (
        tenant_id,
        titulo_id,
        numero,
        vencimento_date,
        valor,
        valor_aberto
      )
      values (
        v_nf.tenant_id,
        v_titulo_id,
        v_num,
        v_venc,
        v_val,
        v_val
      );

      v_soma := round(v_soma + v_val, 2);
      v_i := v_i + 1;
    end loop;

    if abs(v_soma - v_total) > 0.05 then
      raise exception 'Soma das parcelas (%) difere do total da NF (%)', v_soma, v_total;
    end if;
  else
    insert into f.titulo_parcela (
      tenant_id,
      titulo_id,
      numero,
      vencimento_date,
      valor,
      valor_aberto
    )
    values (
      v_nf.tenant_id,
      v_titulo_id,
      '001',
      v_emissao_date,
      v_total,
      v_total
    );
  end if;

  -- Ajusta valor em aberto do titulo
  v_sql := '
    select coalesce(sum(tp.valor_aberto), 0)
    from f.titulo_parcela tp
    where tp.tenant_id = $1
      and tp.titulo_id = $2';
  if v_has_parcela_deleted_at then
    v_sql := v_sql || ' and tp.deleted_at is null';
  end if;
  execute v_sql into v_valor_aberto using v_nf.tenant_id, v_titulo_id;

  update f.titulo
  set valor_aberto = coalesce(v_valor_aberto, 0),
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
  where id = v_titulo_id
    and tenant_id = v_nf.tenant_id;

  -- log (opcional, mas ajuda suporte)
  insert into f.importacao_doc_log (
    tenant_id,
    empresa_id,
    documento_fiscal_id,
    origem,
    status,
    mensagem,
    payload
  )
  values (
    v_nf.tenant_id,
    v_nf.empresa_id,
    v_doc_id,
    'XML',
    'SUCESSO',
    'AP gerado a partir de NF importada',
    jsonb_build_object('nf_entrada_id', v_nf.id, 'titulo_id', v_titulo_id)
  );

  return v_titulo_id;
end;
$$;

commit;
