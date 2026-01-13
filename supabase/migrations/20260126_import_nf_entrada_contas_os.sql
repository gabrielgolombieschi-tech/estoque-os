begin;

alter table public.nf_entrada
  add column if not exists os_id bigint,
  add column if not exists baixa_os_automatica boolean not null default false;

alter table public.movimentacoes
  add column if not exists origem_os_id bigint;

create index if not exists idx_mov_origem_os on public.movimentacoes(origem_os_id);

do $$
begin
  if exists (
    select 1 from pg_tables where schemaname = 'public' and tablename = 'financeiro_titulos'
  ) then
    alter table public.financeiro_titulos
      add column if not exists nf_entrada_id bigint,
      add column if not exists parcela_numero text,
      add column if not exists fornecedor_id bigint;

    if not exists (
      select 1 from pg_constraint where conname = 'financeiro_titulos_nf_entrada_id_fkey'
    ) then
      alter table public.financeiro_titulos
        add constraint financeiro_titulos_nf_entrada_id_fkey
        foreign key (nf_entrada_id) references public.nf_entrada(id) on delete set null;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'financeiro_titulos_fornecedor_id_fkey'
    ) then
      alter table public.financeiro_titulos
        add constraint financeiro_titulos_fornecedor_id_fkey
        foreign key (fornecedor_id) references public.fornecedores(id) on delete set null;
    end if;

    execute 'create unique index if not exists financeiro_titulos_nf_parcela_uq ' ||
            'on public.financeiro_titulos (tenant_id, nf_entrada_id, parcela_numero) ' ||
            'where natureza = ''PAGAR''';
  end if;
end$$;

drop function if exists public.import_nf_entrada(uuid, item_finalidade, bigint, jsonb, jsonb, uuid, text, boolean, jsonb, integer, boolean);
drop function if exists public.import_nf_entrada(uuid, uuid, bigint, jsonb, jsonb, text, public.item_finalidade);
drop function if exists public.import_nf_entrada(uuid, uuid, bigint, jsonb, jsonb, text);

create or replace function public.import_nf_entrada(
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
  p_baixar_os boolean default false
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
begin
  if p_nf_json is null then
    raise exception 'p_nf_json Ã© obrigatÃ³rio';
  end if;

  v_chave := nullif(trim(p_nf_json->>'chave'), '');
  if v_chave is null then
    raise exception 'NF sem chave (p_nf_json.chave)';
  end if;

  -- JÃ¡ existe?
  select id into v_nf_id
  from public.nf_entrada
  where chave = v_chave
  limit 1;

  if v_nf_id is not null then
    status := 'ja_importada';
    message := 'NF jÃ¡ importada';
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
      raise exception 'OS invÃ¡lida (id=%) para este tenant', p_os_id;
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
    baixa_os_automatica
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
    p_baixar_os
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

  -- 3) MovimentaÃ§Ãµes (ENTRADA)
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

  -- 4) Financeiro (opcional): contas a pagar por parcelas
  if coalesce(p_gerar_contas_pagar, false) then
    if not public.has_permission('financeiro.gerenciar') then
      raise exception 'Sem permissÃ£o financeiro.gerenciar para gerar contas a pagar';
    end if;

    -- categoria "Compras (NF Entrada)" por tenant (cria se nÃ£o existir)
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

    -- Se nÃ£o veio parcelas_json, cria 1 parcela padrÃ£o (Ã  vista)
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

    -- Insere 1 tÃ­tulo por parcela
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
      fornecedor_id
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
      'Gerado automaticamente na importaÃ§Ã£o XML',
      v_nf_id,
      nullif(p->>'numero',''),
      p_fornecedor_id
    from jsonb_array_elements(p_parcelas_json) p
    on conflict do nothing;
  end if;

  -- 5) Vincular OS + criar/atualizar os_itens + baixa automÃ¡tica (opcional)
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
        raise exception 'Item invÃ¡lido em p_itens_json (item_id=%)', v_it->>'item_id';
      end if;

      if v_qtd <= 0 then
        raise exception 'Quantidade invÃ¡lida para item_id=% (qtd=%)', v_item_id, v_qtd;
      end if;

      -- update se jÃ¡ existe
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
        ('Gerado via importaÃ§Ã£o NF-e ' || v_chave),
        p_tenant_id
      where not exists (select 1 from upd);

      -- baixa automÃ¡tica: cria uma SAÃDA referenciando OS
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
          ('Baixa automÃ¡tica OS ' || p_os_id || ' via NF-e ' || v_chave),
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

commit;
