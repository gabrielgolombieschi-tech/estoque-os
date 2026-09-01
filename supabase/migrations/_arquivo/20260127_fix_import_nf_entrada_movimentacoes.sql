begin;
-- Fix: ensure XML import always creates estoque movimentacoes (and thus updates estoque via trigger),
-- even when the NF was previously imported without movements.

drop function if exists public.import_nf_entrada(uuid, uuid, bigint, jsonb, jsonb, text);
drop function if exists public.import_nf_entrada(uuid, uuid, bigint, jsonb, jsonb, text, public.item_finalidade);
drop function if exists public.import_nf_entrada(uuid, public.item_finalidade, bigint, jsonb, jsonb, uuid, text, boolean, jsonb, integer, boolean);
drop function if exists public.import_nf_entrada(uuid, public.item_finalidade, bigint, jsonb, jsonb, uuid, text, boolean, jsonb, integer, boolean, uuid, uuid);
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
      and mc.deleted_at is null
      and mc.ativo = true
      and mc.aplica_em in ('PRODUTO','AMBOS')
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
  where tenant_id = p_tenant_id
    and empresa_id = p_empresa_id
    and chave = v_chave
  limit 1;

  if v_nf_id is not null then
    -- Best-effort: fill missing metadata if this NF was imported before these columns existed.
    update public.nf_entrada
    set motivo_compra_id = coalesce(motivo_compra_id, p_motivo_compra_id),
        solicitante_usuario_id = coalesce(solicitante_usuario_id, p_solicitante_usuario_id)
    where id = v_nf_id
      and tenant_id = p_tenant_id
      and empresa_id = p_empresa_id;

    -- Best-effort: if there are no movimentacoes for this NF, create them now.
    if not exists (
      select 1
      from public.movimentacoes m
      where m.tenant_id = p_tenant_id
        and m.empresa_id = p_empresa_id
        and m.origem_nf_entrada_id = v_nf_id
      limit 1
    ) then
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
        i.id,
        'entrada',
        coalesce(nullif(elem->>'quantidade','')::numeric, nullif(elem->>'qtd','')::numeric, 0),
        coalesce(nullif(elem->>'motivo',''), 'Importacao XML NF-e ' || v_chave),
        coalesce(nullif(elem->>'realizado_por',''), public.jwt_claim('email'), auth.uid()::text),
        now(),
        nullif(nullif(elem->>'custo_unitario_bruto','')::numeric, 0),
        nullif(nullif(elem->>'custo_unitario_real','')::numeric, 0),
        coalesce(nullif(elem->>'credito_icms','')::numeric, 0),
        coalesce(nullif(elem->>'credito_pis','')::numeric, 0),
        coalesce(nullif(elem->>'credito_cofins','')::numeric, 0),
        v_nf_id,
        null,
        coalesce(nullif(elem->>'v_ipi','')::numeric, 0),
        coalesce(nullif(elem->>'v_icms','')::numeric, 0),
        coalesce(nullif(elem->>'v_pis','')::numeric, 0),
        coalesce(nullif(elem->>'v_cofins','')::numeric, 0),
        coalesce(nullif(elem->>'v_frete_rateado','')::numeric, 0),
        p_tenant_id,
        p_empresa_id
      from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb)) elem
      join public.itens i
        on i.tenant_id = p_tenant_id
       and i.id = (nullif(elem->>'item_id',''))::int
       and i.tipo = 'produto'
       and coalesce(i.controla_estoque, false) = true;
    end if;

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
    i.id,
    'entrada',
    coalesce(nullif(elem->>'quantidade','')::numeric, nullif(elem->>'qtd','')::numeric, 0),
    coalesce(nullif(elem->>'motivo',''), 'Importacao XML NF-e ' || v_chave),
    coalesce(nullif(elem->>'realizado_por',''), public.jwt_claim('email'), auth.uid()::text),
    now(),
    nullif(nullif(elem->>'custo_unitario_bruto','')::numeric, 0),
    nullif(nullif(elem->>'custo_unitario_real','')::numeric, 0),
    coalesce(nullif(elem->>'credito_icms','')::numeric, 0),
    coalesce(nullif(elem->>'credito_pis','')::numeric, 0),
    coalesce(nullif(elem->>'credito_cofins','')::numeric, 0),
    v_nf_id,
    null,
    coalesce(nullif(elem->>'v_ipi','')::numeric, 0),
    coalesce(nullif(elem->>'v_icms','')::numeric, 0),
    coalesce(nullif(elem->>'v_pis','')::numeric, 0),
    coalesce(nullif(elem->>'v_cofins','')::numeric, 0),
    coalesce(nullif(elem->>'v_frete_rateado','')::numeric, 0),
    p_tenant_id,
    p_empresa_id
  from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb)) elem
  join public.itens i
    on i.tenant_id = p_tenant_id
   and i.id = (nullif(elem->>'item_id',''))::int
   and i.tipo = 'produto'
   and coalesce(i.controla_estoque, false) = true;

  status := 'ok';
  message := 'Importado com sucesso';
  nf_entrada_id := v_nf_id;
  return next;
end;
$$;
commit;
