begin;

-- A homologacao faz parte do mesmo fluxo que pode chegar a producao. Enquanto
-- a solicitacao nao for cancelada, ela continua reservando a quantidade da OV.
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
    or not f.has_finance_access(p_tenant_id, p_empresa_id)
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
    select si.origem_item_id, sum(si.quantidade) as quantidade
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
  left join reservado r on r.origem_item_id = oi.id::text
  where oi.tenant_id = p_tenant_id
    and oi.empresa_id = p_empresa_id
    and oi.os_id = p_os_id
    and (oi.finalidade = 'venda' or oi.finalidade is null)
  order by oi.id;
end;
$function$;

comment on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) is
  'Reserva toda solicitacao nao cancelada, inclusive homologacao autorizada, ate cancelamento logico ou conclusao do fluxo em producao.';
revoke all on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) from public, anon;
grant execute on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) to authenticated, service_role;

create or replace function f.fn_nfe_producao_pronta(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_certificado_validade date;
  v_crt text;
  v_ambito text;
  v_homologacao_documento_id uuid;
  v_homologacao_payload jsonb;
  v_total_itens integer;
  v_invalidos integer;
  v_perfis jsonb;
  v_perfil_unico uuid;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id;

  if not found then
    return jsonb_build_object('pronta', false, 'motivo', 'Solicitacao nao encontrada.');
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;
  if v_sf.status = 'CANCELADA' then
    return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao esta cancelada.');
  end if;

  select dfe.documento_fiscal_id, dfe.payload_enviado
    into v_homologacao_documento_id, v_homologacao_payload
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.status = 'AUTORIZADA'
  order by dfe.autorizado_em desc nulls last, dfe.updated_at desc
  limit 1;

  if v_homologacao_documento_id is null then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.'
    );
  end if;
  if jsonb_typeof(v_homologacao_payload) is distinct from 'object' then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A homologacao autorizada nao possui o payload fiscal enviado para comparacao.'
    );
  end if;

  select ef.certificado_validade_em, ef.crt::text
    into v_certificado_validade, v_crt
  from c.empresa e
  join c.empresa_fiscal ef
    on ef.empresa_id = e.id
   and ef.deleted_at is null
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null;

  if not found or v_certificado_validade is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.');
  end if;
  if v_certificado_validade < current_date then
    return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.');
  end if;
  if v_sf.destino_uf_confirmada is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A UF de destino ainda nao foi confirmada.');
  end if;
  if v_sf.revisao_fiscal_confirmada_em is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A conferencia fiscal desta solicitacao ainda nao foi confirmada.');
  end if;
  if v_sf.snapshot_cadastro_em is null
     or jsonb_typeof(v_sf.emitente_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.destinatario_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.operacao_snapshot) is distinct from 'object' then
    return jsonb_build_object('pronta', false, 'motivo', 'O cadastro fiscal ainda nao foi validado e congelado.');
  end if;
  if upper(nullif(btrim(v_sf.destinatario_snapshot->>'uf'), '')) is distinct from v_sf.destino_uf_confirmada
     or nullif(btrim(v_sf.emitente_snapshot->>'uf'), '') is null then
    return jsonb_build_object('pronta', false, 'motivo', 'As UFs do snapshot fiscal nao correspondem ao destino confirmado.');
  end if;
  v_ambito := case
    when upper(btrim(v_sf.emitente_snapshot->>'uf')) = v_sf.destino_uf_confirmada then 'INTERNA'
    else 'INTERESTADUAL'
  end;

  select
    count(*),
    count(*) filter (
      where si.perfil_operacao_id is null
         or po.id is null
         or po.modelo <> 'NFE'
         or po.natureza_operacao <> v_sf.natureza_operacao
         or (po.crt is not null and po.crt is distinct from v_crt)
         or po.ambito_destino is distinct from v_ambito
         or not po.habilitado_producao
         or po.faixa_automacao = 'BLOQUEADO'
         or po.vigencia_inicio > current_date
         or (po.vigencia_fim is not null and po.vigencia_fim < current_date)
         or po.ufs_destino is null
         or not (v_sf.destino_uf_confirmada = any(po.ufs_destino))
         or (po.indicador_ie_destinatario is not null
             and po.indicador_ie_destinatario is distinct from v_sf.destinatario_snapshot->>'indicador_ie')
         or (po.origem_mercadoria is not null
             and po.origem_mercadoria is distinct from si.origem_mercadoria)
         or (v_ambito = 'INTERNA' and po.cfop_interno is distinct from si.cfop)
         or (v_ambito = 'INTERESTADUAL' and po.cfop_externo is distinct from si.cfop)
         or (po.finalidade_emissao is not null
             and po.finalidade_emissao is distinct from (v_sf.operacao_snapshot->>'finalidade_emissao')::smallint)
         or (po.consumidor_final is not null
             and po.consumidor_final is distinct from (v_sf.operacao_snapshot->>'consumidor_final')::smallint)
    ),
    coalesce(jsonb_agg(distinct po.id) filter (where po.id is not null), '[]'::jsonb)
  into v_total_itens, v_invalidos, v_perfis
  from f.solicitacao_item si
  left join f.perfil_operacao po
    on po.tenant_id = si.tenant_id
   and (po.empresa_id = si.empresa_id or po.empresa_id is null)
   and po.id = si.perfil_operacao_id
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if v_total_itens = 0 then
    return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao nao possui itens fiscais.');
  end if;
  if v_invalidos > 0 then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'Todos os itens precisam de perfil fiscal vigente, compativel e explicitamente liberado para producao.'
    );
  end if;

  if jsonb_array_length(v_perfis) = 1 then
    v_perfil_unico := (v_perfis->>0)::uuid;
  end if;

  return jsonb_build_object(
    'pronta', true,
    'tenant_id', v_sf.tenant_id,
    'empresa_id', v_sf.empresa_id,
    'homologacao_documento_fiscal_id', v_homologacao_documento_id,
    'perfil_operacao_id', v_perfil_unico,
    'perfil_operacao_ids', v_perfis
  );
end;
$function$;

comment on function f.fn_nfe_producao_pronta(uuid) is
  'Libera producao somente para a mesma solicitacao autorizada em homologacao, congelada, revisada, com certificado valido e todos os perfis por item liberados.';
revoke all on function f.fn_nfe_producao_pronta(uuid) from public, anon;
grant execute on function f.fn_nfe_producao_pronta(uuid) to authenticated, service_role;

create or replace function f.fn_nfe_preparar_documento_solicitacao_producao(p_solicitacao_id uuid)
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
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_documento_id uuid := gen_random_uuid();
  v_referencia text;
  v_total_produtos numeric(15,2);
  v_total_desconto numeric(15,2);
  v_total_nota numeric(15,2);
  v_os_id integer;
  v_prontidao jsonb;
  v_perfil_id uuid;
  v_origem record;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para emitir esta solicitacao em producao.';
  end if;

  if not exists (
    select 1
    from f.documento_fiscal_emissao hom
    where hom.tenant_id = v_sf.tenant_id
      and hom.empresa_id = v_sf.empresa_id
      and hom.solicitacao_id = v_sf.id
      and hom.ambiente = 'HOMOLOGACAO'
      and hom.status = 'AUTORIZADA'
  ) then
    raise exception using errcode = '22023', message = 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.';
  end if;

  -- Serializa com a composicao de novas solicitacoes da mesma OS/OV.
  for v_origem in
    select distinct si.origem_id::integer as origem_id
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id ~ '^[0-9]+$'
    order by si.origem_id::integer
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      format('faturamento-parcial:%s:%s:%s', v_sf.tenant_id, v_sf.empresa_id, v_origem.origem_id),
      0
    ));
  end loop;

  v_referencia := 'NFEP-' || v_sf.id;
  perform pg_advisory_xact_lock(hashtextextended(v_referencia, 0));

  v_prontidao := f.fn_nfe_producao_pronta(v_sf.id);
  if not coalesce((v_prontidao->>'pronta')::boolean, false) then
    raise exception using errcode = 'P0001', message = coalesce(v_prontidao->>'motivo', 'Producao bloqueada.');
  end if;
  v_perfil_id := nullif(v_prontidao->>'perfil_operacao_id', '')::uuid;

  if exists (
    with atual as (
      select
        si.origem_id::integer as os_id,
        si.origem_item_id::integer as os_item_id,
        sum(si.quantidade) as quantidade
      from f.solicitacao_item si
      where si.tenant_id = v_sf.tenant_id
        and si.empresa_id = v_sf.empresa_id
        and si.solicitacao_id = v_sf.id
        and si.origem_tipo in ('OS', 'OV')
        and si.origem_id ~ '^[0-9]+$'
        and si.origem_item_id ~ '^[0-9]+$'
      group by si.origem_id::integer, si.origem_item_id::integer
    ), outros as (
      select
        si.origem_id::integer as os_id,
        si.origem_item_id::integer as os_item_id,
        sum(si.quantidade) as quantidade
      from f.solicitacao_item si
      join f.solicitacao_faturamento sf
        on sf.tenant_id = si.tenant_id
       and sf.empresa_id = si.empresa_id
       and sf.id = si.solicitacao_id
      where si.tenant_id = v_sf.tenant_id
        and si.empresa_id = v_sf.empresa_id
        and si.solicitacao_id <> v_sf.id
        and si.origem_tipo in ('OS', 'OV')
        and si.origem_id ~ '^[0-9]+$'
        and si.origem_item_id ~ '^[0-9]+$'
        and sf.status <> 'CANCELADA'
      group by si.origem_id::integer, si.origem_item_id::integer
    )
    select 1
    from atual a
    left join public.os_itens oi
      on oi.tenant_id = v_sf.tenant_id
     and oi.empresa_id = v_sf.empresa_id
     and oi.os_id = a.os_id
     and oi.id = a.os_item_id
    left join outros o
      on o.os_id = a.os_id
     and o.os_item_id = a.os_item_id
    where oi.id is null
       or a.quantidade > greatest(oi.quantidade - coalesce(o.quantidade, 0), 0)
  ) then
    raise exception using
      errcode = '22023',
      message = 'O saldo da OS/OV mudou depois da homologacao. Cancele ou ajuste as solicitacoes concorrentes antes de produzir.';
  end if;

  return query
  select dfe.documento_fiscal_id, dfe.solicitacao_id, dfe.referencia_externa, dfe.status, false
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'PRODUCAO';
  if found then
    return;
  end if;

  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA', 'EMITIDA') then
    raise exception using errcode = '22023', message = 'Solicitacao nao esta disponivel para emissao em producao.';
  end if;

  update f.solicitacao_faturamento sf
  set perfil_operacao_id = v_perfil_id,
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  select
    round(coalesce(sum(si.quantidade * si.valor_unitario), 0), 2),
    round(coalesce(sum(si.valor_desconto), 0), 2),
    round(coalesce(sum(si.quantidade * si.valor_unitario - si.valor_desconto), 0), 2)
      + coalesce(v_sf.valor_frete, 0)
      + coalesce(v_sf.valor_seguro, 0)
      + coalesce(v_sf.valor_outras_despesas, 0),
    min(case when si.origem_tipo in ('OS', 'OV') and si.origem_id ~ '^[0-9]+$' then si.origem_id::integer end)
  into v_total_produtos, v_total_desconto, v_total_nota, v_os_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if not exists (
    select 1
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
  ) then
    raise exception using errcode = '22023', message = 'Solicitacao sem itens.';
  end if;

  insert into f.documento_fiscal (
    id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date,
    valor_total, valor_produtos, valor_frete, valor_seguro, valor_desconto, valor_outros,
    operacao, natureza, cliente_id, os_id_import, nfe_status, origem
  ) values (
    v_documento_id, v_sf.tenant_id, v_sf.empresa_id, 'PENDENTE:' || v_referencia, '55', current_date,
    v_total_nota, v_total_produtos, v_sf.valor_frete, v_sf.valor_seguro, v_total_desconto, v_sf.valor_outras_despesas,
    'SAIDA', 'PRODUTO', v_sf.cliente_id, v_os_id, 'RASCUNHO', 'EMITIDO'
  );

  insert into f.documento_fiscal_item (
    tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo,
    codigo, descricao, ncm, cfop, quantidade, unidade, valor_unitario,
    valor_total, item_id
  )
  select
    si.tenant_id, si.empresa_id, v_documento_id, si.ordem, 'PRODUTO',
    si.codigo_produto, si.descricao, si.ncm, si.cfop, si.quantidade, si.unidade, si.valor_unitario,
    round(si.quantidade * si.valor_unitario - si.valor_desconto, 2), si.item_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
  order by si.ordem, si.id;

  insert into f.documento_fiscal_emissao (
    documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
    referencia_externa, ambiente, status
  ) values (
    v_documento_id, v_sf.id, v_sf.tenant_id, v_sf.empresa_id,
    v_referencia, 'PRODUCAO', 'RASCUNHO'
  );

  update f.solicitacao_faturamento sf
  set status = 'APROVADA', updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  return query select v_documento_id, v_sf.id, v_referencia, 'RASCUNHO'::text, true;
end;
$function$;

comment on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid) is
  'Promove idempotentemente a mesma solicitacao homologada, sob os locks da origem, revalidando perfis, certificado, snapshot e saldo antes de criar a emissao real.';
revoke all on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid) from public, anon;
grant execute on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid) to authenticated, service_role;

create or replace function f.fn_nfe_evento_registrar(
  p_documento_fiscal_id uuid,
  p_tipo text,
  p_status text,
  p_justificativa text default null,
  p_protocolo text default null,
  p_resposta jsonb default '{}'::jsonb,
  p_destinatarios text[] default null,
  p_sequencia integer default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_id uuid;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode registrar eventos.';
  end if;

  p_tipo := upper(btrim(coalesce(p_tipo, '')));
  p_status := upper(btrim(coalesce(p_status, '')));

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id
   and df.empresa_id = dfe.empresa_id
   and df.id = dfe.documento_fiscal_id
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and df.deleted_at is null
  for update of dfe;

  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao nao encontrada.';
  end if;

  if v_emissao.ambiente = 'PRODUCAO' and p_tipo = 'CANCELAMENTO' then
    raise exception using
      errcode = '55000',
      message = 'Cancelamento de NF-e em producao ainda nao possui estorno financeiro seguro neste fluxo.';
  end if;
  if v_emissao.ambiente = 'PRODUCAO' and p_tipo not in ('DOWNLOAD', 'EMAIL') then
    raise exception using
      errcode = '55000',
      message = format('Evento %s ainda nao esta liberado para NF-e em producao.', p_tipo);
  end if;

  if v_emissao.ambiente = 'HOMOLOGACAO'
     and p_tipo = 'CANCELAMENTO'
     and p_status = 'AUTORIZADA' then
    -- Serializa o cancelamento com a promocao, que tambem bloqueia esta linha.
    perform 1
    from f.solicitacao_faturamento sf
    where sf.tenant_id = v_emissao.tenant_id
      and sf.empresa_id = v_emissao.empresa_id
      and sf.id = v_emissao.solicitacao_id
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'Solicitacao da emissao nao encontrada no mesmo escopo.';
    end if;
    if exists (
       select 1
       from f.documento_fiscal_emissao prod
       where prod.tenant_id = v_emissao.tenant_id
         and prod.empresa_id = v_emissao.empresa_id
         and prod.solicitacao_id = v_emissao.solicitacao_id
         and prod.ambiente = 'PRODUCAO'
         and prod.status <> 'CANCELADA'
    ) then
      raise exception using
        errcode = '55000',
        message = 'A homologacao nao pode ser cancelada depois que a promocao para producao foi iniciada.';
    end if;
  end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, protocolo,
    status, resposta, destinatarios, sequencia, referencia_externa
  ) values (
    p_documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, p_tipo,
    nullif(btrim(p_justificativa), ''), nullif(btrim(p_protocolo), ''), p_status,
    coalesce(p_resposta, '{}'::jsonb), p_destinatarios, p_sequencia, v_emissao.referencia_externa
  ) returning id into v_id;

  if p_tipo = 'CANCELAMENTO' and p_status = 'AUTORIZADA' then
    update f.documento_fiscal_emissao dfe
    set status = 'CANCELADA',
        protocolo = coalesce(nullif(p_protocolo, ''), dfe.protocolo),
        resposta = coalesce(p_resposta, dfe.resposta),
        updated_at = now()
    where dfe.tenant_id = v_emissao.tenant_id
      and dfe.empresa_id = v_emissao.empresa_id
      and dfe.documento_fiscal_id = p_documento_fiscal_id;

    update f.documento_fiscal df
    set nfe_status = 'CANCELADA', updated_at = now()
    where df.tenant_id = v_emissao.tenant_id
      and df.empresa_id = v_emissao.empresa_id
      and df.id = p_documento_fiscal_id;

    update f.solicitacao_faturamento sf
    set status = 'CANCELADA', updated_at = now()
    where sf.tenant_id = v_emissao.tenant_id
      and sf.empresa_id = v_emissao.empresa_id
      and sf.id = v_emissao.solicitacao_id;
  end if;

  return v_id;
end;
$function$;

comment on function f.fn_nfe_evento_registrar(uuid, text, text, text, text, jsonb, text[], integer) is
  'Registra eventos fiscais no escopo da emissao. Em producao permite somente DOWNLOAD/EMAIL; cancelamento real permanece bloqueado ate possuir reversao financeira segura.';
revoke all on function f.fn_nfe_evento_registrar(uuid, text, text, text, text, jsonb, text[], integer) from public, anon, authenticated;
grant execute on function f.fn_nfe_evento_registrar(uuid, text, text, text, text, jsonb, text[], integer) to service_role;

create or replace function f.fn_solicitacao_nfe_cancelar_rascunho(
  p_solicitacao_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_emissoes_canceladas integer := 0;
  v_documentos_cancelados integer := 0;
  v_origem record;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de NF-e nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para cancelar esta solicitacao.';
  end if;
  if char_length(v_motivo) < 5 or char_length(v_motivo) > 255 then
    raise exception using errcode = '22023', message = 'O motivo deve ter entre 5 e 255 caracteres.';
  end if;
  if v_sf.status = 'CANCELADA' then
    return jsonb_build_object(
      'ok', true,
      'idempotente', true,
      'solicitacao_id', v_sf.id,
      'status', 'CANCELADA'
    );
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Somente uma solicitacao editavel pode ser cancelada por este fluxo.';
  end if;
  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.status in ('AUTORIZADA', 'ENVIANDO', 'PROCESSANDO')
  ) then
    raise exception using
      errcode = '55000',
      message = 'A solicitacao possui emissao autorizada ou em processamento e nao pode ser cancelada como rascunho.';
  end if;
  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'CANCELADA')
  ) then
    raise exception using errcode = '55000', message = 'A solicitacao possui uma emissao que exige tratamento fiscal proprio.';
  end if;

  for v_origem in
    select distinct si.origem_id::integer as origem_id
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id ~ '^[0-9]+$'
    order by si.origem_id::integer
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      format('faturamento-parcial:%s:%s:%s', v_sf.tenant_id, v_sf.empresa_id, v_origem.origem_id),
      0
    ));
  end loop;

  with canceladas as (
    update f.documento_fiscal_emissao dfe
    set status = 'CANCELADA',
        mensagem = coalesce(nullif(dfe.mensagem, ''), 'Solicitacao cancelada localmente antes da autorizacao.'),
        updated_at = now()
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.status in ('RASCUNHO', 'REJEITADA', 'ERRO')
    returning dfe.documento_fiscal_id, dfe.tenant_id, dfe.empresa_id, dfe.referencia_externa
  ), eventos as (
    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
      status, resposta, referencia_externa
    )
    select
      c.documento_fiscal_id, c.tenant_id, c.empresa_id, 'CANCELAMENTO', v_motivo,
      'LOCAL', jsonb_build_object('origem', 'RASCUNHO', 'sem_chamada_sefaz', true), c.referencia_externa
    from canceladas c
    returning documento_fiscal_id
  )
  select count(*) into v_emissoes_canceladas from eventos;

  with documentos as (
    update f.documento_fiscal df
    set nfe_status = 'CANCELADA', updated_at = now()
    where df.tenant_id = v_sf.tenant_id
      and df.empresa_id = v_sf.empresa_id
      and df.id in (
        select dfe.documento_fiscal_id
        from f.documento_fiscal_emissao dfe
        where dfe.tenant_id = v_sf.tenant_id
          and dfe.empresa_id = v_sf.empresa_id
          and dfe.solicitacao_id = v_sf.id
          and dfe.status = 'CANCELADA'
      )
      and df.nfe_status = 'RASCUNHO'
    returning df.id
  )
  select count(*) into v_documentos_cancelados from documentos;

  update f.solicitacao_faturamento sf
  set status = 'CANCELADA',
      observacao = concat_ws(E'\n', nullif(btrim(sf.observacao), ''), 'Cancelada antes da autorizacao: ' || v_motivo),
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  return jsonb_build_object(
    'ok', true,
    'idempotente', false,
    'solicitacao_id', v_sf.id,
    'status', 'CANCELADA',
    'emissoes_canceladas', v_emissoes_canceladas,
    'documentos_cancelados', v_documentos_cancelados
  );
end;
$function$;

comment on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text) is
  'Cancela logicamente uma solicitacao editavel sem emissao autorizada/processando, preserva documentos e eventos e devolve o saldo reservado.';
revoke all on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text) from public, anon;
grant execute on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text) to authenticated, service_role;

commit;
