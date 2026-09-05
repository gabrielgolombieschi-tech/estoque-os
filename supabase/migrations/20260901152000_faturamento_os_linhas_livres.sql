begin;

-- A API antiga continua existindo para nao quebrar a OV, mas a implementacao
-- que trabalha com public.os_itens fica privada e o wrapper recusa OS.
alter function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text)
  rename to fn_solicitacao_faturamento_criar_ov_impl;

revoke all on function f.fn_solicitacao_faturamento_criar_ov_impl(uuid, uuid, integer, jsonb, integer[], text)
  from public, anon, authenticated, service_role;

create function f.fn_solicitacao_faturamento_criar_parcial(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer,
  p_itens_quantidades jsonb default null,
  p_os_item_ids integer[] default null,
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS'
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog
as $function$
begin
  if not exists (
    select 1
    from public.ordens_servico os
    where os.tenant_id = p_tenant_id
      and os.empresa_id = p_empresa_id
      and os.id = p_os_id
      and os.tipo_documento = 'OV'
  ) then
    raise exception using
      errcode = '22023',
      message = format('A origem %s nao e uma OV. Para OS, use linhas livres de faturamento.', p_os_id);
  end if;

  return f.fn_solicitacao_faturamento_criar_ov_impl(
    p_tenant_id,
    p_empresa_id,
    p_os_id,
    p_itens_quantidades,
    p_os_item_ids,
    p_natureza_operacao
  );
end;
$function$;

comment on function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text) is
  'Cria composicao parcial de OV por public.os_itens e reserva quantidade. OS deve usar linhas livres.';

revoke all on function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text)
  from public, anon;
grant execute on function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text)
  to authenticated, service_role;

-- A tela de OV passa por esta RPC: ela reaproveita a baixa existente e grava
-- finalidade='venda' na mesma transacao. O legado nao e alterado em massa.
create function public.add_ov_item_baixa_imediata(
  p_os_id integer,
  p_item_id integer,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_desconto_percentual numeric default 0,
  p_desconto_valor numeric default 0,
  p_baixa_estoque boolean default true,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
)
returns public.os_itens
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := coalesce(p_empresa_id, public.current_empresa_id());
  v_linha public.os_itens%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Nao autenticado.';
  end if;
  if v_tenant_id is null or v_empresa_id is null then
    raise exception using errcode = '22023', message = 'Tenant e empresa atuais sao obrigatorios.';
  end if;
  if not exists (
    select 1
    from public.ordens_servico os
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.id = p_os_id
      and os.tipo_documento = 'OV'
  ) then
    raise exception using errcode = '22023', message = format('OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  v_linha := public.add_os_item_baixa_imediata(
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    p_desconto_percentual,
    p_desconto_valor,
    p_baixa_estoque,
    p_realizado_por,
    p_motivo,
    v_empresa_id
  );

  update public.os_itens oi
  set finalidade = 'venda'
  where oi.tenant_id = v_tenant_id
    and oi.empresa_id = v_empresa_id
    and oi.os_id = p_os_id
    and oi.id = v_linha.id
  returning oi.* into v_linha;

  return v_linha;
end;
$function$;

comment on function public.add_ov_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text, uuid) is
  'Inclui item em uma OV usando a baixa existente e grava finalidade=venda atomicamente.';

revoke all on function public.add_ov_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text, uuid)
  from public, anon;
grant execute on function public.add_ov_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text, uuid)
  to authenticated, service_role;

-- Retorno ampliado: faturado e reservado ficam separados. Solicitacoes em
-- RASCUNHO/PREVIA/APROVADA reservam; EMITIDA ja aparece no documento fiscal.
drop function f.fn_os_saldo_a_faturar(uuid, uuid, integer);

create function f.fn_os_saldo_a_faturar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns table (
  valor_pedido numeric,
  valor_faturado numeric,
  valor_reservado numeric,
  saldo numeric,
  usa_relatorio_hh boolean
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_os public.ordens_servico%rowtype;
  v_valor_pedido numeric(14,2);
  v_valor_faturado numeric(14,2);
  v_valor_reservado numeric(14,2);
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

  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and os.id = p_os_id
    and os.tipo_documento in ('OS', 'OV');

  if not found then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  if v_os.usa_relatorio_hh then
    select coalesce(hh.total_hh, 0)
    into v_valor_pedido
    from public.vw_hh_total_os hh
    where hh.tenant_id = p_tenant_id
      and hh.empresa_id = p_empresa_id
      and hh.os_id = p_os_id;
    v_valor_pedido := coalesce(v_valor_pedido, 0);
  else
    v_valor_pedido := coalesce(v_os.orcado, 0);
  end if;

  select coalesce(sum(df.valor_total), 0)
  into v_valor_faturado
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.os_id_import = p_os_id
    and df.operacao = 'SAIDA'
    and df.deleted_at is null
    and (
      (upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
      or (
        upper(coalesce(df.modelo, '')) <> 'NFSE'
        and (nullif(btrim(df.nfe_status), '') is null or upper(df.nfe_status) = 'EMITIDA')
      )
    );

  select coalesce(sum(round(si.quantidade * si.valor_unitario, 2)), 0)
  into v_valor_reservado
  from f.solicitacao_faturamento sf
  join f.solicitacao_item si
    on si.tenant_id = sf.tenant_id
   and si.empresa_id = sf.empresa_id
   and si.solicitacao_id = sf.id
  where sf.tenant_id = p_tenant_id
    and sf.empresa_id = p_empresa_id
    and sf.status in ('RASCUNHO', 'PREVIA', 'APROVADA')
    and si.origem_tipo = v_os.tipo_documento
    and si.origem_id = p_os_id::text;

  valor_pedido := round(v_valor_pedido, 2);
  valor_faturado := round(v_valor_faturado, 2);
  valor_reservado := round(v_valor_reservado, 2);
  saldo := round(v_valor_pedido - v_valor_faturado - v_valor_reservado, 2);
  usa_relatorio_hh := coalesce(v_os.usa_relatorio_hh, false);
  return next;
end;
$function$;

comment on function f.fn_os_saldo_a_faturar(uuid, uuid, integer) is
  'Resumo por valor compativel com OS/OV: pedido/HH menos documentos emitidos e solicitacoes abertas. Para OV, o bloqueio continua sendo o saldo por item.';

revoke all on function f.fn_os_saldo_a_faturar(uuid, uuid, integer) from public, anon;
grant execute on function f.fn_os_saldo_a_faturar(uuid, uuid, integer) to authenticated, service_role;

create function f.fn_solicitacao_faturamento_criar_os_livre(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer,
  p_linhas jsonb,
  p_natureza_operacao text default 'FATURAMENTO_OS'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_os public.ordens_servico%rowtype;
  v_solicitacao_id uuid := gen_random_uuid();
  v_linha record;
  v_ncm text;
  v_ordem integer := 0;
  v_total integer;
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS sao obrigatorios.';
  end if;
  if jsonb_typeof(p_linhas) <> 'array' then
    raise exception using errcode = '22023', message = 'As linhas livres precisam ser uma lista.';
  end if;
  select count(*) into v_total from jsonb_array_elements(p_linhas);
  if v_total = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos uma linha para faturar.';
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

  perform pg_advisory_xact_lock(
    hashtextextended(format('faturamento-parcial:%s:%s:%s', p_tenant_id, p_empresa_id, p_os_id), 0)
  );

  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and os.id = p_os_id
    and os.tipo_documento = 'OS'
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = format('OS %s nao encontrada nesta empresa.', p_os_id);
  end if;
  if coalesce(v_os.status_fluxo, v_os.status::text) = 'cancelada' then
    raise exception using errcode = '22023', message = format('A OS %s esta cancelada e nao pode ser faturada.', coalesce(v_os.numero_os, v_os.id::text));
  end if;
  if v_os.cliente_id is null then
    raise exception using errcode = '23502', message = format('A OS %s nao tem cliente vinculado.', coalesce(v_os.numero_os, v_os.id::text));
  end if;

  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, pedido_cliente,
    observacao, natureza_operacao
  ) values (
    v_solicitacao_id, p_tenant_id, p_empresa_id, v_os.cliente_id, 'RASCUNHO',
    v_os.pedido_compra,
    format('Composicao livre da OS %s.', coalesce(v_os.numero_os, v_os.id::text)),
    p_natureza_operacao
  );

  for v_linha in
    select x.descricao, x.quantidade, x.unidade, x.valor_unitario, x.item_id
    from jsonb_to_recordset(p_linhas) as x(
      descricao text,
      quantidade numeric,
      unidade text,
      valor_unitario numeric,
      item_id integer
    )
  loop
    v_ordem := v_ordem + 1;
    v_linha.descricao := nullif(btrim(v_linha.descricao), '');
    v_linha.unidade := nullif(upper(btrim(v_linha.unidade)), '');
    if v_linha.descricao is null then
      raise exception using errcode = '22023', message = format('A descricao da linha %s e obrigatoria.', v_ordem);
    end if;
    if v_linha.quantidade is null or v_linha.quantidade <= 0 then
      raise exception using errcode = '22023', message = format('A quantidade da linha %s deve ser maior que zero.', v_ordem);
    end if;
    if v_linha.unidade is null then
      raise exception using errcode = '22023', message = format('A unidade da linha %s e obrigatoria.', v_ordem);
    end if;
    if v_linha.valor_unitario is null or v_linha.valor_unitario < 0 then
      raise exception using errcode = '22023', message = format('O valor unitario da linha %s deve ser maior ou igual a zero.', v_ordem);
    end if;

    v_ncm := null;
    if v_linha.item_id is not null then
      select nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '')
      into v_ncm
      from public.itens i
      left join public.fiscal_itens fi
        on fi.tenant_id = i.tenant_id
       and fi.empresa_id = i.empresa_id
       and fi.item_id = i.id
      where i.tenant_id = p_tenant_id
        and i.empresa_id = p_empresa_id
        and i.id = v_linha.item_id
        and i.ativo is true;
      if not found then
        raise exception using errcode = '22023', message = format('O produto da linha %s e invalido, inativo ou pertence a outra empresa.', v_ordem);
      end if;
    end if;

    insert into f.solicitacao_item (
      solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id,
      origem_item_id, pedido_linha, item_id, descricao, ncm, quantidade,
      unidade, valor_unitario, ordem
    ) values (
      v_solicitacao_id, p_tenant_id, p_empresa_id, 'OS', p_os_id::text,
      null, null, v_linha.item_id, v_linha.descricao, v_ncm,
      v_linha.quantidade, v_linha.unidade, v_linha.valor_unitario, v_ordem
    );
  end loop;

  return v_solicitacao_id;
end;
$function$;

comment on function f.fn_solicitacao_faturamento_criar_os_livre(uuid, uuid, integer, jsonb, text) is
  'Cria rascunho de faturamento da OS com linhas livres. Nao consulta os_itens nem finalidade e nao bloqueia valor acima do orcado.';

revoke all on function f.fn_solicitacao_faturamento_criar_os_livre(uuid, uuid, integer, jsonb, text)
  from public, anon;
grant execute on function f.fn_solicitacao_faturamento_criar_os_livre(uuid, uuid, integer, jsonb, text)
  to authenticated, service_role;

create function f.fn_faturamento_buscar_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_termo text,
  p_limite integer default 20
)
returns table (
  id integer,
  codigo text,
  nome text,
  unidade text,
  valor_unitario numeric
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_termo text := nullif(btrim(coalesce(p_termo, '')), '');
  v_limite integer := greatest(1, least(coalesce(p_limite, 20), 50));
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using errcode = '22023', message = 'Tenant e empresa sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar itens desta empresa.';
  end if;
  if v_termo is null then return; end if;

  return query
  select
    i.id,
    i.codigo_interno::text,
    i.nome::text,
    coalesce(nullif(btrim(i.unidade_medida), ''), 'UN')::text,
    coalesce(i.preco_unitario, 0)::numeric
  from public.itens i
  where i.tenant_id = p_tenant_id
    and i.empresa_id = p_empresa_id
    and i.ativo is true
    and (
      i.id::text = v_termo
      or i.codigo_interno ilike '%' || v_termo || '%'
      or i.codigo_barras ilike '%' || v_termo || '%'
      or i.nome ilike '%' || v_termo || '%'
    )
  order by
    (i.codigo_interno = v_termo or i.id::text = v_termo) desc,
    i.nome,
    i.id
  limit v_limite;
end;
$function$;

revoke all on function f.fn_faturamento_buscar_itens(uuid, uuid, text, integer) from public, anon;
grant execute on function f.fn_faturamento_buscar_itens(uuid, uuid, text, integer) to authenticated, service_role;

-- A composicao completa passa a decidir o caminho pelo tipo_documento.
drop function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb);
drop function f.fn_faturar_documento_impl(uuid, uuid, integer, integer[], uuid, text, text, jsonb);

create function f.fn_faturar_documento_impl(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS',
  p_itens_quantidades jsonb default null,
  p_linhas_livres jsonb default null
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
  v_origem public.ordens_servico%rowtype;
  v_solicitacao_id uuid;
  v_referencia text;
  v_codigo_empresa text;
  v_total_produtos numeric(15,2);
  v_total_desconto numeric(15,2);
  v_total_nota numeric(15,2);
begin
  if p_tenant_id is null or p_empresa_id is null or p_ov_id is null or p_documento_fiscal_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa, OS/OV e idempotencia da emissao sao obrigatorios.';
  end if;

  p_ambiente := upper(btrim(coalesce(p_ambiente, '')));
  p_natureza_operacao := upper(btrim(coalesce(p_natureza_operacao, '')));
  if p_ambiente not in ('HOMOLOGACAO', 'PRODUCAO') then
    raise exception using errcode = '22023', message = 'Ambiente invalido. Use HOMOLOGACAO ou PRODUCAO.';
  end if;
  if p_natureza_operacao = '' then
    raise exception using errcode = '22023', message = 'A natureza da operacao e obrigatoria.';
  end if;

  select os.* into v_origem
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and os.id = p_ov_id
    and os.tipo_documento in ('OS', 'OV')
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_ov_id);
  end if;
  if coalesce(v_origem.status_fluxo, v_origem.status::text) = 'cancelada' then
    raise exception using errcode = '22023', message = format('%s %s esta cancelada e nao pode ser emitida.', v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
  end if;
  if v_origem.cliente_id is null then
    raise exception using errcode = '23502', message = format('%s %s nao tem cliente vinculado.', v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os));
  end if;
  if v_origem.tipo_documento = 'OS' and p_linhas_livres is null then
    raise exception using errcode = '22023', message = 'OS exige linhas livres de faturamento.';
  end if;
  if v_origem.tipo_documento = 'OV' and p_linhas_livres is not null then
    raise exception using errcode = '22023', message = 'OV deve usar as linhas e quantidades do pedido, nao linhas livres.';
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
  if found then return; end if;

  if p_ambiente = 'PRODUCAO' and not exists (
    select 1
    from f.perfil_operacao po
    join c.empresa_fiscal ef on ef.empresa_id = p_empresa_id and ef.deleted_at is null
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
      message = format('Emissao em PRODUCAO bloqueada: nao existe perfil fiscal vigente para a natureza %s e o CRT desta empresa.', p_natureza_operacao);
  end if;

  if v_origem.tipo_documento = 'OV' then
    v_solicitacao_id := f.fn_solicitacao_faturamento_criar_ov_impl(
      p_tenant_id, p_empresa_id, p_ov_id, p_itens_quantidades,
      p_os_item_ids, p_natureza_operacao
    );
  else
    v_solicitacao_id := f.fn_solicitacao_faturamento_criar_os_livre(
      p_tenant_id, p_empresa_id, p_ov_id, p_linhas_livres,
      p_natureza_operacao
    );
  end if;

  update f.solicitacao_faturamento
  set status = 'APROVADA',
      observacao = format('Emissao da %s %s em %s.', v_origem.tipo_documento, coalesce(v_origem.codigo, v_origem.numero_os), p_ambiente),
      updated_at = now()
  where id = v_solicitacao_id;

  if v_origem.tipo_documento = 'OV' then
    select
      round(coalesce(sum(round(si.quantidade * si.valor_unitario, 2)), 0), 2),
      round(coalesce(sum(round(coalesce(oi.desconto_valor, 0) * si.quantidade / nullif(oi.quantidade, 0), 2)), 0), 2),
      round(coalesce(sum(
        round(si.quantidade * si.valor_unitario, 2)
        - round(coalesce(oi.desconto_valor, 0) * si.quantidade / nullif(oi.quantidade, 0), 2)
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
  else
    select round(coalesce(sum(round(si.quantidade * si.valor_unitario, 2)), 0), 2)
    into v_total_produtos
    from f.solicitacao_item si
    where si.tenant_id = p_tenant_id
      and si.empresa_id = p_empresa_id
      and si.solicitacao_id = v_solicitacao_id;
    v_total_desconto := 0;
    v_total_nota := v_total_produtos;
  end if;

  insert into f.documento_fiscal (
    id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date,
    valor_total, valor_produtos, valor_desconto, operacao, natureza,
    cliente_id, os_id_import, nfe_status, origem
  ) values (
    p_documento_fiscal_id, p_tenant_id, p_empresa_id, 'PENDENTE:' || v_referencia,
    '55', current_date, v_total_nota, v_total_produtos, v_total_desconto,
    'SAIDA', 'PRODUTO', v_origem.cliente_id, p_ov_id, 'RASCUNHO', 'EMITIDO'
  );

  if v_origem.tipo_documento = 'OV' then
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
        - round(coalesce(oi.desconto_valor, 0) * si.quantidade / nullif(oi.quantidade, 0), 2),
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
  else
    insert into f.documento_fiscal_item (
      tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo,
      codigo, descricao, ncm, quantidade, unidade, valor_unitario,
      valor_total, item_id
    )
    select
      p_tenant_id, p_empresa_id, p_documento_fiscal_id, si.ordem, 'PRODUTO',
      coalesce(i.codigo_interno, format('OS-%s-%s', p_ov_id, lpad(si.ordem::text, 3, '0'))),
      si.descricao, si.ncm, si.quantidade, si.unidade, si.valor_unitario,
      round(si.quantidade * si.valor_unitario, 2), si.item_id
    from f.solicitacao_item si
    left join public.itens i
      on i.tenant_id = si.tenant_id
     and i.empresa_id = si.empresa_id
     and i.id = si.item_id
    where si.tenant_id = p_tenant_id
      and si.empresa_id = p_empresa_id
      and si.solicitacao_id = v_solicitacao_id
    order by si.ordem;
  end if;

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

revoke all on function f.fn_faturar_documento_impl(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb)
  from public, anon, authenticated, service_role;

create function f.fn_faturar_documento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS',
  p_itens_quantidades jsonb default null,
  p_linhas_livres jsonb default null
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
    p_itens_quantidades, p_linhas_livres
  ) x;
end;
$function$;

comment on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb) is
  'OV usa itens do pedido e saldo por quantidade; OS usa linhas livres e saldo apenas informativo por valor.';

revoke all on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb)
  from public, anon;
grant execute on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb)
  to authenticated, service_role;

-- O contexto deixa de exigir os_itens e item_id. Em OS livre, os valores e a
-- descricao sao lidos de solicitacao_item/documento_fiscal_item.
create or replace function f.fn_nfe_contexto_emissao_impl(p_documento_fiscal_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select jsonb_build_object(
    'emissao', to_jsonb(dfe),
    'documento', to_jsonb(df),
    'solicitacao', to_jsonb(sf),
    'ov', to_jsonb(os),
    'empresa', to_jsonb(e),
    'empresa_fiscal', to_jsonb(ef),
    'empresa_endereco', to_jsonb(ee),
    'cliente', to_jsonb(cl),
    'perfil_operacao', to_jsonb(po),
    'itens', coalesce(it.itens, '[]'::jsonb)
  )
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id and df.empresa_id = dfe.empresa_id and df.id = dfe.documento_fiscal_id
  join f.solicitacao_faturamento sf
    on sf.tenant_id = dfe.tenant_id and sf.empresa_id = dfe.empresa_id and sf.id = dfe.solicitacao_id
  join public.ordens_servico os
    on os.tenant_id = df.tenant_id and os.empresa_id = df.empresa_id and os.id = df.os_id_import
  join c.empresa e
    on e.tenant_id = df.tenant_id and e.id = df.empresa_id and e.deleted_at is null
  left join lateral (
    select x.* from c.empresa_fiscal x
    where x.empresa_id = e.id and x.deleted_at is null
    order by x.updated_at desc limit 1
  ) ef on true
  left join lateral (
    select x.* from c.empresa_endereco x
    where x.empresa_id = e.id and x.deleted_at is null
    order by (x.tipo = 'FISCAL') desc, x.updated_at desc limit 1
  ) ee on true
  join public.clientes cl
    on cl.tenant_id = df.tenant_id and cl.empresa_id = df.empresa_id and cl.id = df.cliente_id
  left join lateral (
    select x.*
    from f.perfil_operacao x
    where x.tenant_id = df.tenant_id
      and (x.empresa_id = df.empresa_id or x.empresa_id is null)
      and x.modelo = 'NFE'
      and x.natureza_operacao = sf.natureza_operacao
      and (x.crt is null or x.crt = ef.crt::text)
      and x.vigencia_inicio <= current_date
      and (x.vigencia_fim is null or x.vigencia_fim >= current_date)
    order by (x.empresa_id is not null) desc, x.vigencia_inicio desc
    limit 1
  ) po on true
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'documento_item', to_jsonb(dfi),
        'solicitacao_item', to_jsonb(si),
        'os_item', to_jsonb(oi),
        'item', to_jsonb(i),
        'fiscal_item', to_jsonb(fi)
      ) order by dfi.item_n
    ) as itens
    from f.documento_fiscal_item dfi
    join f.solicitacao_item si
      on si.tenant_id = dfi.tenant_id
     and si.empresa_id = dfi.empresa_id
     and si.solicitacao_id = sf.id
     and si.ordem = dfi.item_n
     and si.item_id is not distinct from dfi.item_id
    left join public.os_itens oi
      on oi.tenant_id = dfi.tenant_id
     and oi.empresa_id = dfi.empresa_id
     and oi.id::text = si.origem_item_id
    left join public.itens i
      on i.tenant_id = dfi.tenant_id
     and i.empresa_id = dfi.empresa_id
     and i.id = dfi.item_id
    left join public.fiscal_itens fi
      on fi.tenant_id = i.tenant_id
     and fi.empresa_id = i.empresa_id
     and fi.item_id = i.id
    where dfi.tenant_id = df.tenant_id
      and dfi.empresa_id = df.empresa_id
      and dfi.documento_fiscal_id = df.id
      and dfi.deleted_at is null
  ) it on true
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and (
      current_user in ('postgres', 'service_role')
      or (
        dfe.tenant_id = public.current_tenant_id()
        and dfe.empresa_id = public.current_empresa_id()
        and f.has_finance_access()
      )
    );
$function$;

commit;
