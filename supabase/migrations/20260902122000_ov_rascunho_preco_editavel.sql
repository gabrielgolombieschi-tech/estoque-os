begin;

-- A OV atual nao possui preco comercial por linha. Desfaz a tentativa anterior
-- de persistir esse dado no item operacional; a origem oficial, por enquanto,
-- passa a ser o valor explicitamente conferido no rascunho da NF-e.
drop trigger if exists trg_solicitacao_item_preco_ov on f.solicitacao_item;
drop function if exists f.trg_solicitacao_item_preco_ov();
drop trigger if exists trg_ov_item_preco_venda on public.os_itens;
drop function if exists public.trg_ov_item_preco_venda();

alter table public.os_itens
  drop constraint if exists os_itens_orcamento_item_escopo_fk,
  drop constraint if exists os_itens_valor_unitario_venda_ck;

drop index if exists public.os_itens_orcamento_item_idx;
drop index if exists m.orcamento_item_tenant_empresa_id_ux;

alter table public.os_itens
  drop column if exists orcamento_item_id,
  drop column if exists valor_unitario_venda;

-- O wrapper publico continua separando OV de OS, mas precisa executar a
-- implementacao privada sem expo-la diretamente ao papel authenticated.
alter function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text)
  security definer;
alter function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text)
  set search_path = pg_catalog;
alter function f.fn_solicitacao_faturamento_criar_parcial(uuid, uuid, integer, jsonb, integer[], text)
  set row_security = off;

create or replace function f.fn_solicitacao_faturamento_criar_ov_impl(
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
  v_valor_unitario numeric;
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

  perform pg_advisory_xact_lock(
    hashtextextended(format('faturamento-parcial:%s:%s:%s', p_tenant_id, p_empresa_id, p_os_id), 0)
  );

  select os.* into v_origem
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and os.id = p_os_id
    and os.tipo_documento = 'OV'
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = format('OV %s nao encontrada nesta empresa.', p_os_id);
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
    raise exception using errcode = '22023', message = 'As linhas precisam ser uma lista de os_item_id, quantidade e valor_unitario.';
  end if;

  if p_os_item_ids is not null and (
    cardinality(p_os_item_ids) = 0
    or exists (select 1 from unnest(p_os_item_ids) id where id is null or id <= 0)
    or cardinality(p_os_item_ids) <> (select count(distinct id) from unnest(p_os_item_ids) id)
  ) then
    raise exception using errcode = '22023', message = 'A selecao de linhas da OS/OV e invalida ou possui duplicidades.';
  end if;

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
  from jsonb_to_recordset(v_requisicoes) as x(os_item_id integer, quantidade numeric, valor_unitario numeric);

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
      from jsonb_to_recordset(v_requisicoes) as x(os_item_id integer, quantidade numeric, valor_unitario numeric)
      where not (x.os_item_id = any(p_os_item_ids))
    )
  ) then
    raise exception using errcode = '22023', message = 'As linhas informadas nao correspondem as linhas selecionadas.';
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
    select x.os_item_id, x.quantidade, x.valor_unitario
    from jsonb_to_recordset(v_requisicoes) as x(os_item_id integer, quantidade numeric, valor_unitario numeric)
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

    if v_origem.tipo_documento = 'OV' then
      if v_requisicao.valor_unitario is null or v_requisicao.valor_unitario < 0 then
        raise exception using
          errcode = '22023',
          message = format('Informe o preco unitario de venda da linha %s. O custo da OV nao sera usado na NF-e.', v_linha.id);
      end if;
      v_valor_unitario := v_requisicao.valor_unitario;
    else
      v_valor_unitario := coalesce(v_requisicao.valor_unitario, v_linha.valor_unitario);
    end if;

    v_ordem := v_ordem + 1;
    insert into f.solicitacao_item (
      solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id,
      origem_item_id, pedido_linha, item_id, descricao, ncm, quantidade,
      unidade, valor_unitario, ordem
    ) values (
      v_solicitacao_id, p_tenant_id, p_empresa_id, v_origem.tipo_documento, p_os_id::text,
      v_linha.id::text, v_linha.id::text, v_linha.item_id, v_linha.descricao, v_linha.ncm,
      v_quantidade, v_linha.unidade, v_valor_unitario, v_ordem
    );
  end loop;

  return v_solicitacao_id;
end;
$function$;

comment on function f.fn_solicitacao_faturamento_criar_ov_impl(uuid, uuid, integer, jsonb, integer[], text) is
  'Cria composicao em RASCUNHO e reserva saldo. Para OV, exige e grava o preco de venda explicitamente informado por linha; nunca usa o custo operacional.';

commit;
