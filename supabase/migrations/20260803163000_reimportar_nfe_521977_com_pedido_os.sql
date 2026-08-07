-- Reimportacao controlada da NF-e 521977 da MKraft.
-- A nota anterior foi estornada porque apenas a chapa havia sido vinculada ao
-- cadastro. Esta rotina e idempotente e usa o fluxo oficial de importacao para
-- recriar as tres linhas, o AP e as entradas; em seguida concilia o pedido e a OS.

create or replace function public.corrigir_reimportacao_nfe_521977(p_xml_raw text)
returns jsonb
language plpgsql
security definer
set search_path = public, m, f, a, pg_temp
as $$
declare
  v_tenant_id constant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa_id constant uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_auth_user_id constant uuid := '8d76fa9d-9dba-4e87-a630-afd5cea2255a';
  v_solicitante_id constant uuid := '3bdbad2f-8715-4b78-8f93-1225060e4482';
  v_motivo_id constant uuid := 'fec2760a-cc42-4e51-af9f-75d7e07e64fe';
  v_pedido_id constant uuid := 'df29f6af-8cc3-435f-b20a-6a6a214171df';
  v_chave constant text := '42260702612064000179550010005219771564239546';
  v_nf_id bigint;
  v_titulo_id uuid;
  v_recebimento_id uuid;
  v_os_id integer := 205;
  v_os_label text;
  v_os_item_id bigint;
  v_item record;
  v_receber jsonb;
begin
  if coalesce(btrim(p_xml_raw), '') = '' then
    raise exception 'XML completo da NF-e 521977 e obrigatorio';
  end if;

  if p_xml_raw not like '%' || v_chave || '%' then
    raise exception 'O XML informado nao corresponde a chave da NF-e 521977';
  end if;

  if not exists (
    select 1
    from public.fornecedores f
    where f.id = 246
      and f.tenant_id = v_tenant_id
      and f.empresa_id = v_empresa_id
      and regexp_replace(coalesce(f.cnpj, f.documento, ''), '\\D', '', 'g') = '02612064000179'
  ) then
    raise exception 'Fornecedor MKraft esperado nao foi localizado no escopo correto';
  end if;

  if not exists (
    select 1 from m.pedido_compra p
    where p.id = v_pedido_id
      and p.tenant_id = v_tenant_id
      and p.empresa_id = v_empresa_id
      and p.fornecedor_id = 246
      and p.deleted_at is null
  ) then
    raise exception 'Pedido de compra esperado nao foi localizado no escopo correto';
  end if;

  -- O importador exige contexto autenticado e valida as memberships. O usuario
  -- abaixo e o proprio usuario que solicitou/executa a correcao no sistema.
  perform set_config('request.jwt.claim.sub', v_auth_user_id::text, true);
  perform set_config('request.jwt.claim.email', 'gabriel@segau.com.br', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_auth_user_id,
      'email', 'gabriel@segau.com.br',
      'role', 'authenticated'
    )::text,
    true
  );

  select ne.id
    into v_nf_id
  from public.nf_entrada ne
  where ne.tenant_id = v_tenant_id
    and ne.empresa_id = v_empresa_id
    and ne.chave = v_chave
    and ne.deleted_at is null
  order by ne.id desc
  limit 1;

  if v_nf_id is null then
    select imported.nf_entrada_id
      into v_nf_id
    from public.import_nf_entrada(
      p_empresa_id => v_empresa_id,
      p_finalidade_contexto => 'materia_prima'::public.item_finalidade,
      p_fornecedor_id => 246,
      p_itens_json => jsonb_build_array(
        jsonb_build_object(
          'item_id', 2928, 'numero_item_xml', 1,
          'codigo', '00000577', 'codigo_fornecedor', '00000577',
          'nome', 'CHAPA FINA QUENTE 2,00 x 1200 X 3000',
          'descricao', 'CHAPA FINA QUENTE 2,00 x 1200 X 3000',
          'unidade', 'KG', 'unidade_tributavel', 'KG',
          'ean', 'SEM GTIN', 'ean_tributavel', 'SEM GTIN',
          'ncm', '72085400', 'cfop', '5102',
          'informacoes_adicionais', '2 X 3000mm',
          'qtd', 115.302, 'quantidade', 115.302,
          'v_unit', 6.70153163, 'v_prod', 772.70,
          'v_desc', 0, 'v_frete', 0, 'v_seguro', 0, 'v_outro', 0, 'v_st', 0,
          'aliq_icms', 12, 'v_icms', 92.72,
          'aliq_ipi', 3.25, 'v_ipi', 25.11,
          'aliq_pis', 1.65, 'v_pis', 11.22,
          'aliq_cofins', 7.6, 'v_cofins', 51.68,
          'tipo', 'entrada',
          'motivo', 'NF 521977/1 chave ' || v_chave || ' emitente Mkraft Comercio de Metais LTDA',
          'realizado_por', 'gabriel@segau.com.br',
          'data_movimentacao', '2026-07-28T23:49:00-03:00'
        ),
        jsonb_build_object(
          'item_id', 45, 'numero_item_xml', 2,
          'codigo', '00000045', 'codigo_fornecedor', '00000045',
          'nome', 'TUBO RETANGULAR 40 X 60 X 2,00',
          'descricao', 'TUBO RETANGULAR 40 X 60 X 2,00',
          'unidade', 'KG', 'unidade_tributavel', 'KG',
          'ean', 'SEM GTIN', 'ean_tributavel', 'SEM GTIN',
          'ncm', '73066100', 'cfop', '5102',
          'informacoes_adicionais', '1 X 6000mm',
          'qtd', 18.558, 'quantidade', 18.558,
          'v_unit', 7.727125768, 'v_prod', 143.40,
          'v_desc', 0, 'v_frete', 0, 'v_seguro', 0, 'v_outro', 0, 'v_st', 0,
          'aliq_icms', 12, 'v_icms', 17.21,
          'aliq_ipi', 5, 'v_ipi', 7.17,
          'aliq_pis', 1.65, 'v_pis', 2.08,
          'aliq_cofins', 7.6, 'v_cofins', 9.59,
          'tipo', 'entrada',
          'motivo', 'NF 521977/1 chave ' || v_chave || ' emitente Mkraft Comercio de Metais LTDA',
          'realizado_por', 'gabriel@segau.com.br',
          'data_movimentacao', '2026-07-28T23:49:00-03:00'
        ),
        jsonb_build_object(
          'item_id', 45, 'numero_item_xml', 3,
          'codigo', '00000045', 'codigo_fornecedor', '00000045',
          'nome', 'TUBO RETANGULAR 40 X 60 X 2,00',
          'descricao', 'TUBO RETANGULAR 40 X 60 X 2,00',
          'unidade', 'KG', 'unidade_tributavel', 'KG',
          'ean', 'SEM GTIN', 'ean_tributavel', 'SEM GTIN',
          'ncm', '73066100', 'cfop', '5102',
          'informacoes_adicionais', '2 X 6000mm',
          'qtd', 37.116, 'quantidade', 37.116,
          'v_unit', 7.727125768, 'v_prod', 286.80,
          'v_desc', 0, 'v_frete', 0, 'v_seguro', 0, 'v_outro', 0, 'v_st', 0,
          'aliq_icms', 12, 'v_icms', 34.42,
          'aliq_ipi', 5, 'v_ipi', 14.34,
          'aliq_pis', 1.65, 'v_pis', 4.16,
          'aliq_cofins', 7.6, 'v_cofins', 19.18,
          'tipo', 'entrada',
          'motivo', 'NF 521977/1 chave ' || v_chave || ' emitente Mkraft Comercio de Metais LTDA',
          'realizado_por', 'gabriel@segau.com.br',
          'data_movimentacao', '2026-07-28T23:49:00-03:00'
        )
      ),
      p_nf_json => jsonb_build_object(
        'chave', v_chave,
        'numero', '521977',
        'serie', '1',
        'emitente_nome', 'Mkraft Comercio de Metais LTDA',
        'emitente_cnpj', '02612064000179',
        'valor_produtos', 1202.90,
        'valor_frete', 0,
        'valor_seguro', 0,
        'valor_desconto', 0,
        'valor_outros', 0,
        'valor_total', 1249.52,
        'data_emissao', '2026-07-28T23:49:00-03:00'
      ),
      p_tenant_id => v_tenant_id,
      p_xml_raw => p_xml_raw,
      p_gerar_contas_pagar => true,
      p_parcelas_json => jsonb_build_array(
        jsonb_build_object('numero', '001', 'vencimento', '2026-08-25', 'valor', 624.76),
        jsonb_build_object('numero', '002', 'vencimento', '2026-09-01', 'valor', 624.76)
      ),
      p_os_id => null,
      p_baixar_os => false,
      p_motivo_compra_id => v_motivo_id,
      p_solicitante_usuario_id => v_solicitante_id
    ) imported
    limit 1;
  end if;

  if v_nf_id is null then
    raise exception 'A importacao nao retornou nf_entrada_id';
  end if;

  -- Pos-condicoes usadas pelo endpoint oficial.
  perform public.fn_backfill_movimentacoes_nf_entrada(v_nf_id);

  select public.fn_ensure_titulo_ap_from_nf_entrada(
    p_nf_entrada_id => v_nf_id,
    p_force_regen_parcelas => true,
    p_parcelas_json => jsonb_build_array(
      jsonb_build_object('numero', '001', 'vencimento', '2026-08-25', 'valor', 624.76),
      jsonb_build_object('numero', '002', 'vencimento', '2026-09-01', 'valor', 624.76)
    )
  ) into v_titulo_id;

  if v_titulo_id is null then
    raise exception 'Titulo AP nao foi localizado/gerado';
  end if;

  perform public.fn_sync_titulo_aprovacao_from_nf_entrada(
    p_nf_entrada_id => v_nf_id,
    p_titulo_id => v_titulo_id,
    p_motivo_compra_id => v_motivo_id,
    p_os_id => null,
    p_aprovado_por => v_solicitante_id
  );

  -- O recebimento contabiliza as quantidades contratadas do pedido. As entradas
  -- de estoque continuam refletindo os pesos exatos do XML.
  if not exists (
    select 1
    from m.pedido_compra_recebimento r
    where r.tenant_id = v_tenant_id
      and r.empresa_id = v_empresa_id
      and r.pedido_compra_id = v_pedido_id
      and r.documento_ref = v_chave
      and r.deleted_at is null
  ) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'pedidoItemId', i.id,
          'quantidade', greatest(0, i.quantidade - coalesce(i.quantidade_recebida, 0))
        ) order by i.id
      ) filter (where i.quantidade - coalesce(i.quantidade_recebida, 0) > 0),
      '[]'::jsonb
    )
      into v_receber
    from m.pedido_compra_item i
    where i.tenant_id = v_tenant_id
      and i.empresa_id = v_empresa_id
      and i.pedido_compra_id = v_pedido_id
      and i.deleted_at is null;

    if jsonb_array_length(v_receber) > 0 then
      v_recebimento_id := m.fn_pedido_compra_receber(
        v_pedido_id,
        date '2026-07-28',
        v_chave,
        'Recebimento automatico via XML (NF entrada ' || v_nf_id || ')',
        v_receber,
        true
      );
    end if;
  end if;

  select coalesce(nullif(os.numero_os, ''), nullif(os.os_num::text, ''), os.id::text)
    into v_os_label
  from public.ordens_servico os
  where os.id = v_os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id;

  if v_os_label is null then
    raise exception 'OS de destino nao foi localizada';
  end if;

  for v_item in
    select ni.item_id,
           sum(ni.qtd)::numeric as quantidade,
           max(pi.valor_unitario)::numeric as valor_unitario
    from public.nf_entrada_itens ni
    left join m.pedido_compra_item pi
      on pi.pedido_compra_id = v_pedido_id
     and pi.item_id = ni.item_id
     and pi.deleted_at is null
    where ni.tenant_id = v_tenant_id
      and ni.empresa_id = v_empresa_id
      and ni.nf_entrada_id = v_nf_id
      and ni.item_id is not null
    group by ni.item_id
  loop
    select oi.id
      into v_os_item_id
    from public.os_itens oi
    where oi.tenant_id = v_tenant_id
      and oi.empresa_id = v_empresa_id
      and oi.os_id = v_os_id
      and oi.item_id = v_item.item_id
      and oi.observacoes = 'Importacao XML NF ' || v_nf_id || ' [OS ' || v_os_label || ']'
    order by oi.id
    limit 1;

    if v_os_item_id is null then
      insert into public.os_itens(
        tenant_id, empresa_id, os_id, item_id, quantidade,
        valor_unitario, valor_total, observacoes, baixa_estoque,
        quantidade_baixada, criado_em
      ) values (
        v_tenant_id, v_empresa_id, v_os_id, v_item.item_id, v_item.quantidade,
        coalesce(v_item.valor_unitario, 0),
        v_item.quantidade * coalesce(v_item.valor_unitario, 0),
        'Importacao XML NF ' || v_nf_id || ' [OS ' || v_os_label || ']',
        false, 0, now()
      ) returning id into v_os_item_id;
    else
      update public.os_itens
         set quantidade = v_item.quantidade,
             valor_unitario = coalesce(v_item.valor_unitario, 0),
             valor_total = v_item.quantidade * coalesce(v_item.valor_unitario, 0)
       where id = v_os_item_id
         and tenant_id = v_tenant_id
         and empresa_id = v_empresa_id;
    end if;

    if not exists (
      select 1 from public.movimentacoes mov
      where mov.tenant_id = v_tenant_id
        and mov.empresa_id = v_empresa_id
        and mov.tipo = 'saida'
        and mov.origem_nf_entrada_id = v_nf_id
        and mov.origem_os_id = v_os_id
        and mov.item_id = v_item.item_id
    ) then
      insert into public.movimentacoes(
        tenant_id, empresa_id, item_id, tipo, quantidade, motivo,
        realizado_por, data_movimentacao, origem_nf_entrada_id, origem_os_id
      ) values (
        v_tenant_id, v_empresa_id, v_item.item_id, 'saida', v_item.quantidade,
        'Baixa automatica via XML NF ' || v_nf_id || ' [OS ' || v_os_label || ']',
        'gabriel@segau.com.br', now(), v_nf_id, v_os_id
      );
    end if;

    update public.os_itens
       set baixa_estoque = true,
           quantidade_baixada = v_item.quantidade
     where id = v_os_item_id
       and tenant_id = v_tenant_id
       and empresa_id = v_empresa_id;

    v_os_item_id := null;
  end loop;

  update public.nf_entrada
     set baixa_os_automatica = true,
         updated_at = now()
   where id = v_nf_id
     and tenant_id = v_tenant_id
     and empresa_id = v_empresa_id;

  if (select count(*) from public.nf_entrada_itens ni where ni.nf_entrada_id = v_nf_id) <> 3 then
    raise exception 'A NF corrigida nao ficou com as tres linhas esperadas';
  end if;

  return jsonb_build_object(
    'status', 'ok',
    'nf_entrada_id', v_nf_id,
    'titulo_id', v_titulo_id,
    'recebimento_id', v_recebimento_id,
    'pedido_id', v_pedido_id,
    'os_id', v_os_id
  );
end;
$$;

revoke all on function public.corrigir_reimportacao_nfe_521977(text) from public, anon, authenticated;
grant execute on function public.corrigir_reimportacao_nfe_521977(text) to service_role;

