-- A NF-e 359577/3 da HIDRAMAVE possui um unico item:
--   10 UN de TUBO PU 4 NATURAL 29710.
-- As 10 unidades foram baixadas integralmente para a OS 206.
--
-- Substitui a classificacao legada OS / 4.05 pelo padrao atual de material
-- direto de OS: OS_MATERIAL_DIRETO / CUSTO_OS_MAT / PRODUCAO. Valores,
-- vencimentos, pagamentos, documento fiscal e vinculos de estoque/OS sao
-- preservados.

do $corrigir_nf_hidramave_os206$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_nf_id constant bigint := 1951;
  v_fornecedor_id constant integer := 685;
  v_os_id constant integer := 205;
  v_os_numero constant integer := 206;
  v_titulo_id constant uuid :=
    'a09913c5-139a-432f-9cef-89cc6b741371'::uuid;
  v_motivo_anterior_id uuid;
  v_plano_anterior_id uuid;
  v_motivo_os_id uuid;
  v_plano_os_id uuid;
  v_centro_producao_id uuid;
  v_rateio_anterior_id uuid;
  v_resultado jsonb;
begin
  select mc.id, mc.plano_contas_id
    into strict v_motivo_anterior_id, v_plano_anterior_id
  from f.motivo_compra mc
  join f.plano_contas pc
    on pc.tenant_id = mc.tenant_id
   and pc.id = mc.plano_contas_id
   and pc.codigo = '4.05'
   and pc.nome = 'ORDEM DE SERVICO (OS)'
   and pc.tipo = 'ANALITICA'
   and pc.ativo
   and pc.deleted_at is null
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'OS'
    and mc.ativo
    and mc.deleted_at is null;

  select mc.id, mc.plano_contas_id
    into strict v_motivo_os_id, v_plano_os_id
  from f.motivo_compra mc
  join f.plano_contas pc
    on pc.tenant_id = mc.tenant_id
   and pc.id = mc.plano_contas_id
   and pc.codigo = 'CUSTO_OS_MAT'
   and pc.tipo = 'ANALITICA'
   and pc.ativo
   and pc.deleted_at is null
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'OS_MATERIAL_DIRETO'
    and mc.ativo
    and mc.deleted_at is null;

  select cc.id
    into strict v_centro_producao_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'PRODUCAO'
    and cc.ativo
    and cc.deleted_at is null;

  if not exists (
    select 1
    from f.regra_rateio rr
    join f.regra_rateio_item rri
      on rri.tenant_id = rr.tenant_id
     and rri.regra_rateio_id = rr.id
     and rri.deleted_at is null
    where rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_os_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_os_id
      and rri.centro_custo_id = v_centro_producao_id
      and abs(rri.percentual - 100.0000) <= 0.0001
      and not exists (
        select 1
        from f.regra_rateio_item outro
        where outro.tenant_id = rri.tenant_id
          and outro.regra_rateio_id = rri.regra_rateio_id
          and outro.id <> rri.id
          and outro.deleted_at is null
      )
  ) then
    raise exception
      'Regra OS_MATERIAL_DIRETO -> CUSTO_OS_MAT/PRODUCAO nao esta configurada.';
  end if;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) =
        'HIDRAMAVE COMERCIO DE PROD HIDRAULICOS E VEDACOES'
      and regexp_replace(
        coalesce(fornecedor.documento, ''),
        '\D',
        '',
        'g'
      ) = '79683496000103'
      and fornecedor.ativo
  ) then
    raise exception
      'O cadastro da HIDRAMAVE divergiu do contexto validado.';
  end if;

  perform 1
  from public.nf_entrada ne
  where ne.id = v_nf_id
    and ne.tenant_id = v_tenant_id
    and ne.empresa_id = v_empresa_id
    and ne.chave = '42260779683496000103550030003595771006654223'
    and ne.numero = '359577'
    and ne.serie = '3'
    and ne.fornecedor_id = v_fornecedor_id
    and ne.valor_produtos = 25.00
    and ne.valor_total = 25.81
    and ne.finalidade_contexto = 'materia_prima'
    and ne.os_id = v_os_id
    and ne.motivo_compra_id = v_motivo_anterior_id
    and ne.deleted_at is null
  for update;

  if not found then
    raise exception
      'A NF-e 359577/3 divergiu do documento validado.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = v_os_id
      and os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.os_num = v_os_numero
  ) then
    raise exception
      'A OS 206 vinculada a NF-e 359577/3 nao foi encontrada.';
  end if;

  if (
    select count(*)::integer
    from public.nf_entrada_itens nei
    where nei.tenant_id = v_tenant_id
      and nei.empresa_id = v_empresa_id
      and nei.nf_entrada_id = v_nf_id
  ) <> 1 then
    raise exception
      'A NF-e 359577/3 deixou de possuir exatamente um item.';
  end if;

  if not exists (
    select 1
    from public.nf_entrada_itens nei
    where nei.tenant_id = v_tenant_id
      and nei.empresa_id = v_empresa_id
      and nei.nf_entrada_id = v_nf_id
      and nei.id = 5435
      and nei.item_id = 3322
      and upper(btrim(nei.codigo_fornecedor)) = '29710 NATURAL'
      and upper(btrim(nei.descricao)) = 'TUBO PU 4 NATURAL 29710'
      and abs(nei.qtd - 10.000000) <= 0.000001
      and nei.v_unit = 2.50
      and nei.v_prod = 25.00
      and nei.v_ipi = 0.81
  ) then
    raise exception
      'O item da NF-e 359577/3 divergiu do item validado.';
  end if;

  if not exists (
    select 1
    from public.movimentacoes mov
    where mov.tenant_id = v_tenant_id
      and mov.empresa_id = v_empresa_id
      and mov.origem_nf_entrada_id = v_nf_id
      and mov.origem_os_id = v_os_id
      and mov.item_id = 3322
      and lower(mov.tipo) = 'saida'
      and abs(mov.quantidade - 10.000000) <= 0.000001
  ) then
    raise exception
      'O item da NF-e 359577/3 nao possui baixa integral para a OS 206.';
  end if;

  if exists (
    select 1
    from public.movimentacoes mov
    where mov.tenant_id = v_tenant_id
      and mov.empresa_id = v_empresa_id
      and mov.origem_nf_entrada_id = v_nf_id
      and mov.origem_os_id is not null
      and mov.origem_os_id <> v_os_id
  ) then
    raise exception
      'A NF-e 359577/3 possui movimentacao para outra OS.';
  end if;

  if not exists (
    select 1
    from public.os_itens oi
    where oi.tenant_id = v_tenant_id
      and oi.empresa_id = v_empresa_id
      and oi.os_id = v_os_id
      and oi.item_id = 3322
      and abs(oi.quantidade - 10.000000) <= 0.000001
      and abs(oi.quantidade_baixada - 10.000000) <= 0.000001
  ) then
    raise exception
      'O item da OS 206 nao confirma quantidade e baixa integrais.';
  end if;

  if not exists (
    select 1
    from f.documento_fiscal df
    join f.titulo t
      on t.tenant_id = df.tenant_id
     and t.empresa_id = df.empresa_id
     and t.documento_fiscal_id = df.id
     and t.id = v_titulo_id
     and t.tipo = 'AP'
     and t.status <> 'CANCELADO'
     and t.valor_total = 25.81
     and t.fornecedor_id = v_fornecedor_id
     and t.motivo_compra_id = v_motivo_anterior_id
     and t.deleted_at is null
    where df.tenant_id = v_tenant_id
      and df.empresa_id = v_empresa_id
      and df.source_nf_entrada_id = v_nf_id
      and df.numero = '359577'
      and df.serie = '3'
      and df.deleted_at is null
  ) then
    raise exception
      'O titulo financeiro da NF-e 359577/3 divergiu do caso validado.';
  end if;

  select tr.id
    into strict v_rateio_anterior_id
  from f.titulo_rateio tr
  where tr.tenant_id = v_tenant_id
    and tr.titulo_id = v_titulo_id
    and tr.plano_contas_id = v_plano_anterior_id
    and tr.centro_custo_id is null
    and tr.os_id is null
    and abs(tr.percentual - 100.0000) <= 0.0001
    and tr.valor = 25.81
    and tr.origem_rateio = 'EXPLICITO'
    and tr.deleted_at is null;

  update public.nf_entrada ne
  set
    motivo_compra_id = v_motivo_os_id,
    updated_at = now()
  where ne.id = v_nf_id
    and ne.tenant_id = v_tenant_id
    and ne.empresa_id = v_empresa_id;

  update f.titulo_aprovacao ta
  set
    motivo_compra_id = v_motivo_os_id,
    os_id = v_os_id,
    change_reason =
      'NF-e 359577/3 baixada integralmente para a OS 206: material direto de OS.',
    updated_at = now()
  where ta.tenant_id = v_tenant_id
    and ta.titulo_id = v_titulo_id
    and ta.deleted_at is null;

  if not found then
    raise exception
      'A aprovacao financeira da NF-e 359577/3 nao foi encontrada.';
  end if;

  update f.titulo t
  set
    motivo_compra_id = v_motivo_os_id,
    updated_at = now()
  where t.id = v_titulo_id
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id;

  update f.titulo_rateio tr
  set
    deleted_at = now(),
    updated_at = now()
  where tr.tenant_id = v_tenant_id
    and tr.titulo_id = v_titulo_id
    and tr.id = v_rateio_anterior_id
    and tr.deleted_at is null;

  v_resultado := f.aplicar_regra_rateio_titulo(
    v_tenant_id,
    v_titulo_id,
    true
  );

  if coalesce(v_resultado ->> 'status', '') <> 'APLICADO' then
    raise exception
      'Falha ao aplicar o rateio da NF-e 359577/3: %.',
      v_resultado;
  end if;

  if not exists (
    select 1
    from f.titulo t
    join f.titulo_rateio tr
      on tr.tenant_id = t.tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    where t.id = v_titulo_id
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.motivo_compra_id = v_motivo_os_id
      and t.valor_total = 25.81
      and tr.plano_contas_id = v_plano_os_id
      and tr.centro_custo_id = v_centro_producao_id
      and tr.os_id = v_os_id
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = 25.81
      and not exists (
        select 1
        from f.titulo_rateio outro
        where outro.tenant_id = tr.tenant_id
          and outro.titulo_id = tr.titulo_id
          and outro.id <> tr.id
          and outro.deleted_at is null
      )
  ) then
    raise exception
      'A classificacao final da NF-e 359577/3 nao passou na validacao.';
  end if;

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload
  )
  values (
    v_tenant_id,
    v_empresa_id,
    'NF_OS_MATERIAL_DIRETO_CLASSIFICADA',
    'f.titulo',
    v_titulo_id,
    jsonb_build_object(
      'nfEntradaId', v_nf_id,
      'numero', '359577',
      'serie', '3',
      'fornecedorId', v_fornecedor_id,
      'osId', v_os_id,
      'osNumero', v_os_numero,
      'itemId', 3322,
      'itemDescricao', 'TUBO PU 4 NATURAL 29710',
      'quantidadeNf', 10,
      'quantidadeBaixadaOs', 10,
      'motivoAnteriorId', v_motivo_anterior_id,
      'motivoAtualId', v_motivo_os_id,
      'planoAnteriorId', v_plano_anterior_id,
      'planoAtualId', v_plano_os_id,
      'centroCustoId', v_centro_producao_id,
      'valorTotal', 25.81,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouDocumentoFiscal', true,
      'preservouMovimentacoes', true,
      'preservouOs', true
    )
  );
end;
$corrigir_nf_hidramave_os206$;
