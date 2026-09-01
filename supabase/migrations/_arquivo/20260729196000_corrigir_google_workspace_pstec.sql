-- A PSTEC fornece Google Workspace, contas de e-mail e servicos de nuvem
-- para a Segau. Os tres pagamentos foram lancados sem centro de custo; dois
-- deles tambem foram classificados como consultoria.
--
-- Unifica o historico em SERV_TI / DESP_TI, no centro TI, e configura o
-- fornecedor para repetir essa classificacao nas proximas cobrancas.
-- Valores, vencimentos e pagamentos permanecem inalterados.

do $corrigir_google_workspace_pstec$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_fornecedor_id constant integer := 584;
  v_plano_consultoria_id uuid;
  v_plano_id uuid;
  v_centro_id uuid;
  v_motivo_consultoria_id uuid;
  v_motivo_id uuid;
  v_regra_id uuid;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[];
  v_quantidade integer;
  v_pagos integer;
  v_valor_total numeric;
begin
  select pc.id
    into strict v_plano_consultoria_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_CONSULTORIA'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select pc.id
    into strict v_plano_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_TI'
    and pc.nome = 'DESPESA - TI'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select cc.id
    into strict v_centro_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'TI'
    and cc.ativo
    and cc.deleted_at is null;

  select mc.id
    into strict v_motivo_consultoria_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SERV_CONSULTORIA'
    and mc.plano_contas_id = v_plano_consultoria_id
    and mc.ativo
    and mc.deleted_at is null;

  select mc.id
    into strict v_motivo_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SERV_TI'
    and mc.plano_contas_id = v_plano_id
    and mc.ativo
    and mc.deleted_at is null;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) =
        'PSTEC TECNOLOGIA EM INFORMATICA LTDA'
      and regexp_replace(
        coalesce(fornecedor.documento, ''),
        '\D',
        '',
        'g'
      ) = '19151823000146'
      and fornecedor.finalidade_padrao = 'outros'
      and fornecedor.motivo_compra_padrao_id is null
      and fornecedor.ativo
  ) then
    raise exception
      'O fornecedor PSTEC divergiu do contexto validado.';
  end if;

  select
    count(*)::integer,
    count(*) filter (where t.status = 'PAGO')::integer,
    sum(t.valor_total)
    into
      v_quantidade,
      v_pagos,
      v_valor_total
  from f.titulo t
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and t.deleted_at is null
    and t.fornecedor_id = v_fornecedor_id
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    );

  if v_quantidade <> 3
     or v_pagos <> 3
     or v_valor_total <> 5079.33
  then
    raise exception
      'O historico da PSTEC divergiu: qtd %, pagos %, valor %.',
      v_quantidade,
      v_pagos,
      v_valor_total;
  end if;

  select
    array_agg(t.id order by t.competencia_date, t.valor_total, t.id),
    count(*)::integer,
    count(*) filter (where t.status = 'PAGO')::integer,
    sum(t.valor_total)
    into
      v_titulo_ids,
      v_quantidade,
      v_pagos,
      v_valor_total
  from f.titulo t
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and t.deleted_at is null
    and t.fornecedor_id = v_fornecedor_id
    and t.motivo_compra_id = v_motivo_consultoria_id
    and upper(btrim(t.descricao)) = 'CONECTA NUVEM'
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    );

  if v_quantidade <> 2
     or v_pagos <> 2
     or v_valor_total <> 3674.13
  then
    raise exception
      'Os titulos Conecta Nuvem divergiram: qtd %, pagos %, valor %.',
      v_quantidade,
      v_pagos,
      v_valor_total;
  end if;

  if (
    select count(*)::integer
    from f.titulo t
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and upper(btrim(t.descricao)) = 'CONECTA NUVEM'
      and t.competencia_date between '2026-06-01'::date and '2026-07-01'::date
      and t.valor_total in (1375.00, 2299.13)
  ) <> 2 then
    raise exception
      'Descricao, competencia ou valores dos servicos Google divergiram.';
  end if;

  if (
    select count(*)::integer
    from f.titulo t
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.motivo_compra_id = v_motivo_consultoria_id
  ) <> 2 then
    raise exception
      'Os motivos anteriores da PSTEC divergiram do contexto validado.';
  end if;

  if (
    select count(*)::integer
    from f.titulo t
    join f.titulo_rateio tr
      on tr.tenant_id = t.tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and tr.plano_contas_id = v_plano_consultoria_id
      and tr.centro_custo_id is null
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = t.valor_total
      and not exists (
        select 1
        from f.titulo_rateio outro
        where outro.tenant_id = tr.tenant_id
          and outro.titulo_id = tr.titulo_id
          and outro.id <> tr.id
          and outro.deleted_at is null
      )
  ) <> 2 then
    raise exception
      'Os rateios anteriores da PSTEC divergiram do contexto validado.';
  end if;

  -- O pagamento GOOGLE ja estava corretamente classificado e deve ser
  -- preservado sem qualquer alteracao.
  if (
    select count(*)::integer
    from f.titulo t
    join f.titulo_rateio tr
      on tr.tenant_id = t.tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    where t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.tipo = 'AP'
      and t.status = 'PAGO'
      and t.deleted_at is null
      and t.fornecedor_id = v_fornecedor_id
      and upper(btrim(t.descricao)) = 'GOOGLE'
      and t.valor_total = 1405.20
      and t.motivo_compra_id = v_motivo_id
      and tr.plano_contas_id = v_plano_id
      and tr.centro_custo_id = v_centro_id
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = t.valor_total
      and not exists (
        select 1
        from f.titulo_rateio outro
        where outro.tenant_id = tr.tenant_id
          and outro.titulo_id = tr.titulo_id
          and outro.id <> tr.id
          and outro.deleted_at is null
      )
  ) <> 1 then
    raise exception
      'O pagamento GOOGLE ja classificado divergiu do contexto validado.';
  end if;

  select rr.id
    into strict v_regra_id
  from f.regra_rateio rr
  join f.regra_rateio_item rri
    on rri.tenant_id = rr.tenant_id
   and rri.regra_rateio_id = rr.id
   and rri.deleted_at is null
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_id
    and rr.ativo
    and rr.deleted_at is null
    and rri.plano_contas_id = v_plano_id
    and rri.centro_custo_id = v_centro_id
    and abs(rri.percentual - 100.0000) <= 0.0001
    and not exists (
      select 1
      from f.regra_rateio_item outro
      where outro.tenant_id = rri.tenant_id
        and outro.regra_rateio_id = rri.regra_rateio_id
        and outro.id <> rri.id
        and outro.deleted_at is null
    );

  perform 1
  from f.titulo t
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
  order by t.id
  for update;

  -- O motivo precisa refletir o plano escolhido antes da chamada da Central.
  -- Como os rateios atuais sao explicitos, a alteracao preserva o estado
  -- anterior para o snapshot produzido durante a correcao.
  update f.titulo t
  set
    motivo_compra_id = v_motivo_id,
    updated_at = now()
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id;

  update f.titulo_aprovacao ta
  set
    motivo_compra_id = v_motivo_id,
    change_reason =
      'Google Workspace, contas de e-mail e servicos em nuvem: DESP_TI / TI.',
    updated_at = now()
  where ta.tenant_id = v_tenant_id
    and ta.titulo_id = any(v_titulo_ids)
    and ta.deleted_at is null;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_id,
    v_centro_id,
    'Google Workspace, contas de e-mail e servicos em nuvem: plano TI e centro Tecnologia da Informacao.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 2 then
    raise exception
      'Correcao dos servicos Google retornou quantidade inesperada: %.',
      v_correcao_resultado;
  end if;

  update public.fornecedores fornecedor
  set
    motivo_compra_padrao_id = v_motivo_id,
    atualizado_em = now()
  where fornecedor.id = v_fornecedor_id
    and fornecedor.tenant_id = v_tenant_id
    and fornecedor.empresa_id = v_empresa_id;

  if (
    select count(*)::integer
    from f.titulo t
    join f.titulo_rateio tr
      on tr.tenant_id = t.tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.motivo_compra_id = v_motivo_id
      and tr.plano_contas_id = v_plano_id
      and tr.centro_custo_id = v_centro_id
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = t.valor_total
      and not exists (
        select 1
        from f.titulo_rateio outro
        where outro.tenant_id = tr.tenant_id
          and outro.titulo_id = tr.titulo_id
          and outro.id <> tr.id
          and outro.deleted_at is null
      )
  ) <> 2 then
    raise exception
      'A classificacao final dos servicos Google nao passou na validacao.';
  end if;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and fornecedor.finalidade_padrao = 'outros'
      and fornecedor.motivo_compra_padrao_id = v_motivo_id
  ) then
    raise exception
      'O motivo padrao futuro da PSTEC nao foi aplicado.';
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
    'GOOGLE_WORKSPACE_PSTEC_CLASSIFICADO',
    'f.motivo_compra',
    v_motivo_id,
    jsonb_build_object(
      'fornecedorId', v_fornecedor_id,
      'fornecedor', 'PSTEC TECNOLOGIA EM INFORMATICA LTDA',
      'motivoCompraId', v_motivo_id,
      'planoContasId', v_plano_id,
      'centroCustoId', v_centro_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'quantidadeCorrigida', 2,
      'pagosCorrigidos', 2,
      'valorCorrigido', 3674.13,
      'quantidadeHistorico', 3,
      'valorHistorico', 5079.33,
      'planoAnteriorParcial', 'DESP_CONSULTORIA',
      'motivoFornecedorPadrao', 'SERV_TI',
      'fornecedorPadraoAlterado', true,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_google_workspace_pstec$;
