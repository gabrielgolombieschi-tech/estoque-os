begin;

create index idx_solicitacao_item_origem_tipo_item
  on f.solicitacao_item (origem_tipo, origem_item_id);

create or replace function f.fn_os_itens_saldo_a_faturar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns table (
  os_item_id integer,
  item_id integer,
  descricao text,
  quantidade_total numeric,
  quantidade_faturada numeric,
  saldo numeric,
  unidade text
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS/OV sao obrigatorios.';
  end if;

  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar o faturamento desta empresa.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico os
    where os.tenant_id = p_tenant_id
      and os.empresa_id = p_empresa_id
      and os.id = p_os_id
      and os.tipo_documento in ('OS', 'OV')
  ) then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  return query
  with reservado as (
    select
      si.origem_item_id,
      sum(si.quantidade) as quantidade
    from f.solicitacao_item si
    join f.solicitacao_faturamento sf
      on sf.tenant_id = si.tenant_id
     and sf.empresa_id = si.empresa_id
     and sf.id = si.solicitacao_id
    where si.tenant_id = p_tenant_id
      and si.empresa_id = p_empresa_id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id = p_os_id::text
      and sf.status <> 'CANCELADA'
    group by si.origem_item_id
  )
  select
    oi.id,
    oi.item_id,
    coalesce(nullif(btrim(i.nome), ''), nullif(btrim(i.descricao), ''), format('Item %s', oi.item_id)),
    oi.quantidade::numeric,
    coalesce(r.quantidade, 0)::numeric,
    greatest(oi.quantidade - coalesce(r.quantidade, 0), 0)::numeric,
    nullif(btrim(i.unidade_medida), '')
  from public.os_itens oi
  join public.itens i
    on i.tenant_id = oi.tenant_id
   and i.empresa_id = oi.empresa_id
   and i.id = oi.item_id
  left join reservado r
    on r.origem_item_id = oi.id::text
  where oi.tenant_id = p_tenant_id
    and oi.empresa_id = p_empresa_id
    and oi.os_id = p_os_id
    and (oi.finalidade = 'venda' or oi.finalidade is null)
  order by oi.id;
end;
$function$;

comment on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) is
  'Saldo fisico por linha de OS/OV. Solicitacoes RASCUNHO, PREVIA, APROVADA e EMITIDA reservam quantidade; apenas CANCELADA devolve saldo.';

revoke all on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) from public, anon;
grant execute on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) to authenticated, service_role;

create or replace function f.fn_solicitacao_faturamento_criar_parcial(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer,
  p_itens_quantidades jsonb default null,
  p_os_item_ids integer[] default null,
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_origem public.ordens_servico%rowtype;
  v_solicitacao_id uuid := gen_random_uuid();
  v_requisicoes jsonb := p_itens_quantidades;
  v_requisicao record;
  v_linha record;
  v_quantidade numeric;
  v_ordem integer := 0;
  v_total_requisicoes integer;
  v_total_ids integer;
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS/OV sao obrigatorios.';
  end if;

  p_natureza_operacao := upper(btrim(coalesce(p_natureza_operacao, '')));
  if p_natureza_operacao = '' then
    raise exception using errcode = '22023', message = 'A natureza da operacao e obrigatoria.';
  end if;

  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para faturar nesta empresa.';
  end if;

  -- Uma unica chave por documento de origem serializa composicoes diferentes,
  -- inclusive quando os usuarios selecionam subconjuntos distintos das linhas.
  perform pg_advisory_xact_lock(
    hashtextextended(format('faturamento-parcial:%s:%s:%s', p_tenant_id, p_empresa_id, p_os_id), 0)
  );

  select os.* into v_origem
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and os.id = p_os_id
    and os.tipo_documento in ('OS', 'OV')
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;
  if coalesce(v_origem.status_fluxo, v_origem.status::text) = 'cancelada' then
    raise exception using errcode = '22023', message = format('%s %s esta cancelada e nao pode ser faturada.', v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
  end if;
  if v_origem.cliente_id is null then
    raise exception using errcode = '23502', message = format('%s %s nao tem cliente vinculado.', v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
  end if;

  if v_requisicoes is not null and jsonb_typeof(v_requisicoes) = 'null' then
    v_requisicoes := null;
  end if;
  if v_requisicoes is not null and jsonb_typeof(v_requisicoes) <> 'array' then
    raise exception using errcode = '22023', message = 'As quantidades precisam ser uma lista de os_item_id e quantidade.';
  end if;

  if p_os_item_ids is not null and (
    cardinality(p_os_item_ids) = 0
    or exists (select 1 from unnest(p_os_item_ids) id where id is null or id <= 0)
    or cardinality(p_os_item_ids) <> (select count(distinct id) from unnest(p_os_item_ids) id)
  ) then
    raise exception using errcode = '22023', message = 'A selecao de linhas da OS/OV e invalida ou possui duplicidades.';
  end if;

  -- Compatibilidade: sem quantidade explicita, cada linha solicita o saldo atual.
  if v_requisicoes is null then
    select coalesce(jsonb_agg(jsonb_build_object('os_item_id', s.os_item_id)), '[]'::jsonb)
    into v_requisicoes
    from f.fn_os_itens_saldo_a_faturar(p_tenant_id, p_empresa_id, p_os_id) s
    join public.os_itens oi
      on oi.tenant_id = p_tenant_id
     and oi.empresa_id = p_empresa_id
     and oi.id = s.os_item_id
    where oi.finalidade = 'venda'
      and (p_os_item_ids is null or s.os_item_id = any(p_os_item_ids))
      and (p_os_item_ids is not null or s.saldo > 0);
  end if;

  select count(*), count(distinct x.os_item_id)
  into v_total_requisicoes, v_total_ids
  from jsonb_to_recordset(v_requisicoes) as x(os_item_id integer, quantidade numeric);

  if v_total_requisicoes = 0 then
    raise exception using errcode = '22023', message = format('%s %s nao possui item de venda com saldo para faturar.', v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
  end if;
  if v_total_requisicoes <> v_total_ids then
    raise exception using errcode = '22023', message = 'A mesma linha nao pode aparecer duas vezes na solicitacao.';
  end if;
  if p_os_item_ids is not null and (
    v_total_ids <> cardinality(p_os_item_ids)
    or exists (
      select 1
      from jsonb_to_recordset(v_requisicoes) as x(os_item_id integer, quantidade numeric)
      where not (x.os_item_id = any(p_os_item_ids))
    )
  ) then
    raise exception using errcode = '22023', message = 'As quantidades informadas nao correspondem as linhas selecionadas.';
  end if;

  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, pedido_cliente,
    observacao, natureza_operacao
  ) values (
    v_solicitacao_id, p_tenant_id, p_empresa_id, v_origem.cliente_id, 'RASCUNHO',
    v_origem.pedido_compra,
    format('Composicao parcial da %s %s.', v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os)),
    p_natureza_operacao
  );

  for v_requisicao in
    select x.os_item_id, x.quantidade
    from jsonb_to_recordset(v_requisicoes) as x(os_item_id integer, quantidade numeric)
    order by x.os_item_id
  loop
    select
      oi.id,
      oi.item_id,
      oi.finalidade,
      oi.valor_unitario,
      coalesce(nullif(btrim(i.nome), ''), nullif(btrim(i.descricao), ''), format('Item %s', oi.item_id)) as descricao,
      nullif(btrim(i.unidade_medida), '') as unidade,
      nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '') as ncm,
      s.saldo
    into v_linha
    from public.os_itens oi
    join public.itens i
      on i.tenant_id = oi.tenant_id
     and i.empresa_id = oi.empresa_id
     and i.id = oi.item_id
    left join public.fiscal_itens fi
      on fi.tenant_id = oi.tenant_id
     and fi.empresa_id = oi.empresa_id
     and fi.item_id = oi.item_id
    join f.fn_os_itens_saldo_a_faturar(p_tenant_id, p_empresa_id, p_os_id) s
      on s.os_item_id = oi.id
    where oi.tenant_id = p_tenant_id
      and oi.empresa_id = p_empresa_id
      and oi.os_id = p_os_id
      and oi.id = v_requisicao.os_item_id;

    if not found then
      raise exception using errcode = '22023', message = format('Linha %s nao pertence a %s %s.', v_requisicao.os_item_id, v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
    end if;
    if v_linha.finalidade is null then
      raise exception using errcode = '22023', message = format('Linha %s da %s %s precisa ser classificada antes do faturamento.', v_linha.id, v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
    end if;
    if v_linha.finalidade <> 'venda' then
      raise exception using errcode = '22023', message = format('Linha %s da %s %s nao tem finalidade de venda.', v_linha.id, v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
    end if;

    v_quantidade := coalesce(v_requisicao.quantidade, v_linha.saldo);
    if v_quantidade <= 0 then
      raise exception using errcode = '22023', message = format('Quantidade da linha %s deve ser maior que zero. Saldo disponivel: %s.', v_linha.id, v_linha.saldo);
    end if;
    if v_quantidade > v_linha.saldo then
      raise exception using
        errcode = '22023',
        message = format(
          'Linha %s da %s %s excede o saldo. Solicitado: %s; disponivel: %s.',
          v_linha.id, v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os),
          v_quantidade, v_linha.saldo
        );
    end if;

    v_ordem := v_ordem + 1;
    insert into f.solicitacao_item (
      solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id,
      origem_item_id, pedido_linha, item_id, descricao, ncm, quantidade,
      unidade, valor_unitario, ordem
    ) values (
      v_solicitacao_id, p_tenant_id, p_empresa_id, v_origem.tipo_documento, p_os_id::text,
      v_linha.id::text, v_linha.id::text, v_linha.item_id, v_linha.descricao, v_linha.ncm,
      v_quantidade, v_linha.unidade, v_linha.valor_unitario, v_ordem
    );
  end loop;

  return v_solicitacao_id;
end;
$function$;

comment on function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text) is
  'Cria somente a composicao em RASCUNHO e reserva saldo por item. Usa o mesmo advisory lock transacional da emissao.';

revoke all on function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text) from public, anon;
grant execute on function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text) to authenticated, service_role;

drop function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text);
drop function f.fn_faturar_documento_impl(uuid, uuid, integer, integer[], uuid, text, text);

create function f.fn_faturar_documento_impl(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS',
  p_itens_quantidades jsonb default null
)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  referencia_externa text,
  status text,
  criado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_ov public.ordens_servico%rowtype;
  v_solicitacao_id uuid;
  v_referencia text;
  v_codigo_empresa text;
  v_total_produtos numeric(15,2);
  v_total_desconto numeric(15,2);
  v_total_nota numeric(15,2);
begin
  if p_tenant_id is null or p_empresa_id is null or p_ov_id is null or p_documento_fiscal_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa, OV e idempotencia da emissao sao obrigatorios.';
  end if;

  p_ambiente := upper(btrim(coalesce(p_ambiente, '')));
  p_natureza_operacao := upper(btrim(coalesce(p_natureza_operacao, '')));
  if p_ambiente not in ('HOMOLOGACAO', 'PRODUCAO') then
    raise exception using errcode = '22023', message = 'Ambiente invalido. Use HOMOLOGACAO ou PRODUCAO.';
  end if;
  if p_natureza_operacao = '' then
    raise exception using errcode = '22023', message = 'A natureza da operacao e obrigatoria.';
  end if;

  select os.* into v_ov
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and os.id = p_ov_id
    and os.tipo_documento = 'OV'
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = format('OV %s nao encontrada nesta empresa.', p_ov_id);
  end if;
  if coalesce(v_ov.status_fluxo, v_ov.status::text) = 'cancelada' then
    raise exception using errcode = '22023', message = format('A OV %s esta cancelada e nao pode ser emitida.', v_ov.codigo);
  end if;
  if v_ov.cliente_id is null then
    raise exception using errcode = '23502', message = format('A OV %s nao tem cliente vinculado.', v_ov.codigo);
  end if;

  select upper(btrim(e.codigo)) into v_codigo_empresa
  from c.empresa e
  where e.tenant_id = p_tenant_id
    and e.id = p_empresa_id
    and e.deleted_at is null
    and e.ativo;
  if nullif(v_codigo_empresa, '') is null then
    raise exception using errcode = 'P0002', message = 'Empresa ativa nao encontrada no cadastro corporativo.';
  end if;

  v_referencia := format('SEG-%s-%s', v_codigo_empresa, p_documento_fiscal_id);
  perform pg_advisory_xact_lock(hashtextextended(v_referencia, 0));

  return query
  select dfe.documento_fiscal_id, dfe.solicitacao_id, dfe.referencia_externa, dfe.status, false
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = p_tenant_id
    and dfe.empresa_id = p_empresa_id
    and dfe.referencia_externa = v_referencia;
  if found then
    return;
  end if;

  if p_ambiente = 'PRODUCAO' and not exists (
    select 1
    from f.perfil_operacao po
    join c.empresa_fiscal ef
      on ef.empresa_id = p_empresa_id
     and ef.deleted_at is null
    where po.tenant_id = p_tenant_id
      and (po.empresa_id = p_empresa_id or po.empresa_id is null)
      and po.modelo = 'NFE'
      and po.natureza_operacao = p_natureza_operacao
      and (po.crt is null or po.crt = ef.crt::text)
      and po.vigencia_inicio <= current_date
      and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
  ) then
    raise exception using
      errcode = 'P0001',
      message = format(
        'Emissao em PRODUCAO bloqueada: nao existe perfil fiscal vigente para a natureza %s e o CRT desta empresa.',
        p_natureza_operacao
      );
  end if;

  v_solicitacao_id := f.fn_solicitacao_faturamento_criar_parcial(
    p_tenant_id,
    p_empresa_id,
    p_ov_id,
    p_itens_quantidades,
    p_os_item_ids,
    p_natureza_operacao
  );

  update f.solicitacao_faturamento
  set status = 'APROVADA',
      observacao = format('Emissao da %s em %s.', v_ov.codigo, p_ambiente),
      updated_at = now()
  where id = v_solicitacao_id;

  select
    round(coalesce(sum(round(si.quantidade * si.valor_unitario, 2)), 0), 2),
    round(coalesce(sum(round(
      coalesce(
        coalesce(oi.desconto_valor, 0) * si.quantidade / nullif(oi.quantidade, 0),
        0
      ),
      2
    )), 0), 2),
    round(coalesce(sum(
      round(si.quantidade * si.valor_unitario, 2)
      - round(coalesce(
          coalesce(oi.desconto_valor, 0) * si.quantidade / nullif(oi.quantidade, 0),
          0
        ), 2)
    ), 0), 2)
  into v_total_produtos, v_total_desconto, v_total_nota
  from f.solicitacao_item si
  join public.os_itens oi
    on oi.tenant_id = si.tenant_id
   and oi.empresa_id = si.empresa_id
   and oi.id::text = si.origem_item_id
  where si.tenant_id = p_tenant_id
    and si.empresa_id = p_empresa_id
    and si.solicitacao_id = v_solicitacao_id;

  insert into f.documento_fiscal (
    id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date,
    valor_total, valor_produtos, valor_desconto, operacao, natureza,
    cliente_id, os_id_import, nfe_status, origem
  ) values (
    p_documento_fiscal_id, p_tenant_id, p_empresa_id, 'PENDENTE:' || v_referencia,
    '55', current_date, v_total_nota, v_total_produtos, v_total_desconto,
    'SAIDA', 'PRODUTO', v_ov.cliente_id, p_ov_id, 'RASCUNHO', 'EMITIDO'
  );

  insert into f.documento_fiscal_item (
    tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo,
    codigo, descricao, ncm, quantidade, unidade, valor_unitario,
    valor_total, item_id
  )
  select
    p_tenant_id, p_empresa_id, p_documento_fiscal_id, si.ordem, 'PRODUTO',
    i.codigo_interno, si.descricao, si.ncm, si.quantidade, si.unidade,
    si.valor_unitario,
    round(si.quantidade * si.valor_unitario, 2)
      - round(coalesce(
          coalesce(oi.desconto_valor, 0) * si.quantidade / nullif(oi.quantidade, 0),
          0
        ), 2),
    si.item_id
  from f.solicitacao_item si
  join public.os_itens oi
    on oi.tenant_id = si.tenant_id
   and oi.empresa_id = si.empresa_id
   and oi.id::text = si.origem_item_id
  join public.itens i
    on i.tenant_id = si.tenant_id
   and i.empresa_id = si.empresa_id
   and i.id = si.item_id
  where si.tenant_id = p_tenant_id
    and si.empresa_id = p_empresa_id
    and si.solicitacao_id = v_solicitacao_id
  order by si.ordem;

  insert into f.documento_fiscal_emissao (
    documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
    referencia_externa, ambiente, status
  ) values (
    p_documento_fiscal_id, v_solicitacao_id, p_tenant_id, p_empresa_id,
    v_referencia, p_ambiente, 'RASCUNHO'
  );

  return query select p_documento_fiscal_id, v_solicitacao_id, v_referencia, 'RASCUNHO'::text, true;
end;
$function$;

revoke all on function f.fn_faturar_documento_impl(uuid, uuid, integer, integer[], uuid, text, text, jsonb)
  from public, anon, authenticated, service_role;

create function f.fn_faturar_documento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS',
  p_itens_quantidades jsonb default null
)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  referencia_externa text,
  status text,
  criado boolean
)
language plpgsql
security invoker
set search_path = pg_catalog
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
begin
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para faturar nesta empresa.';
  end if;

  return query
  select x.documento_fiscal_id, x.solicitacao_id, x.referencia_externa, x.status, x.criado
  from f.fn_faturar_documento_impl(
    p_tenant_id, p_empresa_id, p_ov_id, p_os_item_ids,
    p_documento_fiscal_id, p_ambiente, p_natureza_operacao,
    p_itens_quantidades
  ) x;
end;
$function$;

comment on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb) is
  'Cria documento, solicitacao, itens e emissao respeitando o saldo reservado por linha. Quantidade ausente usa o saldo atual.';

revoke all on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb) from public, anon;
grant execute on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb) to authenticated, service_role;

commit;
