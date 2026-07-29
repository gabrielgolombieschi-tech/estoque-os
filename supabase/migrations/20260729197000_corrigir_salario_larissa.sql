-- Larissa Mello Rechia foi confirmada como funcionaria pelo responsavel da
-- empresa. Ela nao possui cadastro em public.colaboradores e, por isso, ficou
-- fora da correcao anterior baseada somente em colaboradores ativos.
--
-- Corrige exclusivamente as 12 parcelas descritas como Salario mensal para
-- SALARIO_FUNCIONARIO_ATIVO / DESP_SALARIOS / PESSOAS. O motivo padrao do
-- fornecedor permanece vazio para nao classificar eventuais reembolsos como
-- salario. Valores, vencimentos e pagamentos permanecem inalterados.

do $corrigir_salario_larissa$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_fornecedor_id constant integer := 429;
  v_plano_anterior_id uuid;
  v_plano_id uuid;
  v_centro_id uuid;
  v_motivo_legado_id uuid;
  v_motivo_id uuid;
  v_regra_id uuid;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[];
  v_quantidade integer;
  v_pagos integer;
  v_pendentes integer;
  v_valor_total numeric;
begin
  select pc.id
    into strict v_plano_anterior_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_GERAL'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select pc.id
    into strict v_plano_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_SALARIOS'
    and pc.nome = 'DESPESA - SALARIOS E REMUNERACOES'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select cc.id
    into strict v_centro_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'PESSOAS'
    and cc.ativo
    and cc.deleted_at is null;

  select mc.id
    into strict v_motivo_legado_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SALARIOS'
    and mc.plano_contas_id is null
    and mc.ativo
    and mc.deleted_at is null;

  select mc.id
    into strict v_motivo_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SALARIO_FUNCIONARIO_ATIVO'
    and mc.plano_contas_id = v_plano_id
    and mc.ativo
    and mc.deleted_at is null;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) = 'LARISSA MELLO RECHIA'
      and regexp_replace(
        coalesce(fornecedor.documento, ''),
        '\D',
        '',
        'g'
      ) = '06427431935'
      and fornecedor.motivo_compra_padrao_id is null
      and fornecedor.ativo
  ) then
    raise exception
      'O cadastro financeiro de Larissa divergiu do contexto validado.';
  end if;

  select
    array_agg(t.id order by t.competencia_date, t.id),
    count(*)::integer,
    count(*) filter (where t.status = 'PAGO')::integer,
    count(*) filter (where t.status = 'PENDENTE')::integer,
    sum(t.valor_total)
    into
      v_titulo_ids,
      v_quantidade,
      v_pagos,
      v_pendentes,
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

  if v_quantidade <> 12
     or v_pagos <> 4
     or v_pendentes <> 8
     or v_valor_total <> 25452.00
  then
    raise exception
      'A serie salarial de Larissa divergiu: qtd %, pagos %, pendentes %, valor %.',
      v_quantidade,
      v_pagos,
      v_pendentes,
      v_valor_total;
  end if;

  if (
    select count(*)::integer
    from f.titulo t
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and upper(btrim(t.descricao)) = 'SALARIO MENSAL'
      and t.valor_total = 2121.00
      and t.competencia_date between '2026-03-01'::date and '2027-03-01'::date
      and t.motivo_compra_id = v_motivo_legado_id
      and t.documento_fiscal_id is null
  ) <> 12 then
    raise exception
      'Descricao, motivo, competencia ou valor dos salarios divergiram.';
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
      and tr.plano_contas_id = v_plano_anterior_id
      and tr.centro_custo_id is null
      and tr.os_id is null
      and tr.origem_rateio = 'EXPLICITO'
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
  ) <> 12 then
    raise exception
      'Os rateios anteriores dos salarios divergiram do contexto validado.';
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

  -- O motivo especifico precisa refletir o plano antes da chamada da Central.
  -- Os rateios atuais sao explicitos e permanecem disponiveis para o snapshot
  -- de auditoria ate a correcao financeira.
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
      'Salario mensal de funcionaria: plano de salarios e centro Pessoas.',
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
    'Salarios mensais de Larissa Mello Rechia: plano de salarios e centro Pessoas.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 12 then
    raise exception
      'Correcao dos salarios de Larissa retornou quantidade inesperada: %.',
      v_correcao_resultado;
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
  ) <> 12 then
    raise exception
      'A classificacao final dos salarios de Larissa nao passou na validacao.';
  end if;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and fornecedor.motivo_compra_padrao_id is null
  ) then
    raise exception
      'O motivo padrao do fornecedor Larissa foi alterado indevidamente.';
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
    'SALARIO_LARISSA_CLASSIFICADO',
    'f.motivo_compra',
    v_motivo_id,
    jsonb_build_object(
      'fornecedorId', v_fornecedor_id,
      'nome', 'LARISSA MELLO RECHIA',
      'motivoCompraId', v_motivo_id,
      'planoContasId', v_plano_id,
      'centroCustoId', v_centro_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'quantidade', 12,
      'pagos', 4,
      'pendentes', 8,
      'valorMensal', 2121.00,
      'valorTotal', 25452.00,
      'confirmacaoNegocio',
        'Responsavel confirmou Larissa como funcionaria em 2026-07-29.',
      'cadastroColaboradorAusente', true,
      'fornecedorPadraoAlterado', false,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_salario_larissa$;
