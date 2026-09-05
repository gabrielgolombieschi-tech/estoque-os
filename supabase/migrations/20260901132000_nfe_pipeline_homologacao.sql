begin;

alter table f.solicitacao_faturamento
  add column natureza_operacao text not null default 'VENDA_MERCADORIA_TERCEIROS';

alter table f.documento_fiscal_emissao
  add column tentativa_count integer not null default 0 check (tentativa_count >= 0),
  add column ultima_tentativa_em timestamptz,
  add column callback_recebido_em timestamptz,
  add column reconciliado_em timestamptz;

comment on column f.solicitacao_faturamento.natureza_operacao is
  'Codigo funcional da natureza. Em producao precisa resolver para f.perfil_operacao vigente.';
comment on column f.documento_fiscal_emissao.callback_recebido_em is
  'Ultimo webhook da Focus recebido. Webhooks repetidos atualizam a mesma emissao.';

create index idx_documento_fiscal_emissao_reconciliar
  on f.documento_fiscal_emissao (updated_at)
  where status = 'PROCESSANDO';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'nfe-documentos',
  'nfe-documentos',
  false,
  52428800,
  array['application/xml', 'text/xml', 'application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop function if exists f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text);
create function f.fn_faturar_documento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS'
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
as $$
declare
  v_ov public.ordens_servico%rowtype;
  v_solicitacao_id uuid;
  v_referencia text;
  v_codigo_empresa text;
  v_total_produtos numeric(15,2);
  v_total_desconto numeric(15,2);
  v_total_nota numeric(15,2);
  v_quantidade_itens integer;
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

  if current_user not in ('postgres', 'service_role') and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para faturar nesta empresa.';
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

  select
    count(*)::integer,
    round(coalesce(sum(round(oi.quantidade * oi.valor_unitario, 2)), 0), 2),
    round(coalesce(sum(coalesce(oi.desconto_valor, 0)), 0), 2),
    round(coalesce(sum(oi.valor_total), 0), 2)
  into v_quantidade_itens, v_total_produtos, v_total_desconto, v_total_nota
  from public.os_itens oi
  where oi.tenant_id = p_tenant_id
    and oi.empresa_id = p_empresa_id
    and oi.os_id = p_ov_id
    and (p_os_item_ids is null or oi.id = any(p_os_item_ids))
    and coalesce(oi.finalidade, 'venda') = 'venda';

  if v_quantidade_itens = 0 then
    raise exception using errcode = '22023', message = format('A OV %s nao possui item de venda selecionado para faturar.', v_ov.codigo);
  end if;
  if p_os_item_ids is not null and v_quantidade_itens <> cardinality(p_os_item_ids) then
    raise exception using errcode = '22023', message = 'Um ou mais itens selecionados nao pertencem a esta OV ou nao tem finalidade de venda.';
  end if;

  v_solicitacao_id := gen_random_uuid();

  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, pedido_cliente,
    observacao, natureza_operacao
  ) values (
    v_solicitacao_id, p_tenant_id, p_empresa_id, v_ov.cliente_id, 'APROVADA',
    v_ov.pedido_compra, format('Emissao da %s em %s.', v_ov.codigo, p_ambiente),
    p_natureza_operacao
  );

  insert into f.documento_fiscal (
    id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date,
    valor_total, valor_produtos, valor_desconto, operacao, natureza,
    cliente_id, os_id_import, nfe_status, origem
  ) values (
    p_documento_fiscal_id, p_tenant_id, p_empresa_id, 'PENDENTE:' || v_referencia,
    '55', current_date, v_total_nota, v_total_produtos, v_total_desconto,
    'SAIDA', 'PRODUTO', v_ov.cliente_id, p_ov_id, 'RASCUNHO', 'EMITIDO'
  );

  insert into f.solicitacao_item (
    solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id,
    origem_item_id, pedido_linha, item_id, descricao, ncm, quantidade,
    unidade, valor_unitario, ordem
  )
  select
    v_solicitacao_id, p_tenant_id, p_empresa_id, 'OV', p_ov_id::text,
    oi.id::text, row_number() over (order by oi.id)::text, oi.item_id,
    i.nome, nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), ''),
    oi.quantidade, nullif(btrim(i.unidade_medida), ''), oi.valor_unitario,
    row_number() over (order by oi.id)
  from public.os_itens oi
  join public.itens i
    on i.tenant_id = oi.tenant_id and i.empresa_id = oi.empresa_id and i.id = oi.item_id
  left join public.fiscal_itens fi
    on fi.tenant_id = oi.tenant_id and fi.empresa_id = oi.empresa_id and fi.item_id = oi.item_id
  where oi.tenant_id = p_tenant_id
    and oi.empresa_id = p_empresa_id
    and oi.os_id = p_ov_id
    and (p_os_item_ids is null or oi.id = any(p_os_item_ids))
    and coalesce(oi.finalidade, 'venda') = 'venda'
  order by oi.id;

  insert into f.documento_fiscal_item (
    tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo,
    codigo, descricao, ncm, quantidade, unidade, valor_unitario,
    valor_total, item_id
  )
  select
    p_tenant_id, p_empresa_id, p_documento_fiscal_id,
    row_number() over (order by oi.id), 'PRODUTO', i.codigo_interno,
    i.nome, nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), ''),
    oi.quantidade, nullif(btrim(i.unidade_medida), ''), oi.valor_unitario,
    oi.valor_total, oi.item_id
  from public.os_itens oi
  join public.itens i
    on i.tenant_id = oi.tenant_id and i.empresa_id = oi.empresa_id and i.id = oi.item_id
  left join public.fiscal_itens fi
    on fi.tenant_id = oi.tenant_id and fi.empresa_id = oi.empresa_id and fi.item_id = oi.item_id
  where oi.tenant_id = p_tenant_id
    and oi.empresa_id = p_empresa_id
    and oi.os_id = p_ov_id
    and (p_os_item_ids is null or oi.id = any(p_os_item_ids))
    and coalesce(oi.finalidade, 'venda') = 'venda'
  order by oi.id;

  insert into f.documento_fiscal_emissao (
    documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
    referencia_externa, ambiente, status
  ) values (
    p_documento_fiscal_id, v_solicitacao_id, p_tenant_id, p_empresa_id,
    v_referencia, p_ambiente, 'RASCUNHO'
  );

  return query select p_documento_fiscal_id, v_solicitacao_id, v_referencia, 'RASCUNHO'::text, true;
end;
$$;

comment on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text) is
  'Cria documento, solicitacao, itens e emissao antes da chamada externa. O UUID informado e a chave idempotente.';

create or replace function f.fn_nfe_contexto_emissao(p_documento_fiscal_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $$
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
     and si.item_id = dfi.item_id
     and si.ordem = dfi.item_n
    join public.os_itens oi
      on oi.tenant_id = dfi.tenant_id
     and oi.empresa_id = dfi.empresa_id
     and oi.id::text = si.origem_item_id
    join public.itens i
      on i.tenant_id = dfi.tenant_id and i.empresa_id = dfi.empresa_id and i.id = dfi.item_id
    left join public.fiscal_itens fi
      on fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id and fi.item_id = i.id
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
$$;

create or replace function f.fn_nfe_registrar_envio(
  p_documento_fiscal_id uuid,
  p_payload jsonb,
  p_resposta jsonb,
  p_status text default 'PROCESSANDO',
  p_codigo_status integer default null,
  p_mensagem text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode registrar o envio.';
  end if;
  if upper(p_status) not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de envio invalido.';
  end if;
  update f.documento_fiscal_emissao
  set status = upper(p_status),
      payload_enviado = coalesce(p_payload, payload_enviado),
      resposta = coalesce(p_resposta, resposta),
      codigo_status = coalesce(p_codigo_status, codigo_status),
      mensagem = coalesce(p_mensagem, mensagem),
      tentativa_count = tentativa_count + 1,
      ultima_tentativa_em = now(),
      enviado_em = coalesce(enviado_em, now()),
      updated_at = now()
  where documento_fiscal_id = p_documento_fiscal_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao nao encontrada.';
  end if;
end;
$$;

create or replace function f.fn_nfe_aplicar_retorno(
  p_referencia_externa text,
  p_resposta jsonb,
  p_status text,
  p_chave_acesso text default null,
  p_protocolo text default null,
  p_numero integer default null,
  p_serie integer default null,
  p_codigo_status integer default null,
  p_mensagem text default null,
  p_xml_path text default null,
  p_danfe_path text default null,
  p_origem_retorno text default 'CALLBACK'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode aplicar retorno.';
  end if;
  if v_status not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'CANCELADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de retorno invalido.';
  end if;

  select * into v_emissao
  from f.documento_fiscal_emissao
  where referencia_externa = p_referencia_externa
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = format('Referencia %s nao encontrada.', p_referencia_externa);
  end if;

  if v_emissao.status = 'AUTORIZADA' and v_status <> 'AUTORIZADA' then
    return v_emissao.documento_fiscal_id;
  end if;

  update f.documento_fiscal_emissao
  set status = v_status,
      resposta = coalesce(p_resposta, resposta),
      chave_acesso = coalesce(nullif(p_chave_acesso, ''), chave_acesso),
      protocolo = coalesce(nullif(p_protocolo, ''), protocolo),
      numero = coalesce(p_numero, numero),
      serie = coalesce(p_serie, serie),
      codigo_status = coalesce(p_codigo_status, codigo_status),
      mensagem = coalesce(nullif(p_mensagem, ''), mensagem),
      xml_path = coalesce(nullif(p_xml_path, ''), xml_path),
      danfe_path = coalesce(nullif(p_danfe_path, ''), danfe_path),
      callback_recebido_em = case when upper(p_origem_retorno) = 'CALLBACK' then now() else callback_recebido_em end,
      reconciliado_em = case when upper(p_origem_retorno) = 'RECONCILIACAO' then now() else reconciliado_em end,
      autorizado_em = case when v_status = 'AUTORIZADA' then coalesce(autorizado_em, now()) else autorizado_em end,
      updated_at = now()
  where documento_fiscal_id = v_emissao.documento_fiscal_id;

  if v_status = 'AUTORIZADA' then
    if nullif(p_chave_acesso, '') is null or p_chave_acesso !~ '^[0-9]{44}$' then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem chave de acesso valida.';
    end if;
    update f.documento_fiscal
    set chave_acesso = p_chave_acesso,
        numero = coalesce(p_numero::text, numero),
        serie = coalesce(p_serie::text, serie),
        nfe_status = 'EMITIDA',
        emissao_date = coalesce(emissao_date, current_date),
        updated_at = now()
    where id = v_emissao.documento_fiscal_id;

    update f.solicitacao_faturamento
    set status = 'EMITIDA', updated_at = now()
    where id = v_emissao.solicitacao_id;

    update f.documento_fiscal_item dfi
    set ncm = coalesce(dfi.ncm, nullif(x.item->>'codigo_ncm', '')),
        cfop = coalesce(nullif(x.item->>'cfop', ''), dfi.cfop),
        cst_icms = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 2 then x.item->>'icms_situacao_tributaria' else null end,
        csosn = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 3 then x.item->>'icms_situacao_tributaria' else null end,
        cst_ipi = nullif(x.item->>'ipi_situacao_tributaria', ''),
        cst_pis = nullif(x.item->>'pis_situacao_tributaria', ''),
        cst_cofins = nullif(x.item->>'cofins_situacao_tributaria', ''),
        cbenef = nullif(x.item->>'codigo_beneficio_fiscal', ''),
        reducao_base_icms_percentual = nullif(x.item->>'icms_reducao_base_calculo', '')::numeric,
        unidade_tributavel = nullif(x.item->>'unidade_tributavel', ''),
        snapshot_fiscal_em = coalesce(dfi.snapshot_fiscal_em, now()),
        updated_at = now()
    from jsonb_array_elements(coalesce(v_emissao.payload_enviado->'items', '[]'::jsonb)) x(item)
    where dfi.documento_fiscal_id = v_emissao.documento_fiscal_id
      and dfi.item_n = (x.item->>'numero_item')::integer;
  end if;

  return v_emissao.documento_fiscal_id;
end;
$$;

create or replace function f.fn_nfe_emissoes_pendentes_reconciliacao(p_limite integer default 50)
returns table (documento_fiscal_id uuid, referencia_externa text, ambiente text)
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $$
  select dfe.documento_fiscal_id, dfe.referencia_externa, dfe.ambiente
  from f.documento_fiscal_emissao dfe
  where dfe.status = 'PROCESSANDO'
    and dfe.updated_at < now() - interval '10 minutes'
  order by dfe.updated_at
  limit least(greatest(coalesce(p_limite, 50), 1), 200);
$$;

revoke all on function f.fn_nfe_contexto_emissao(uuid) from public, anon;
revoke all on function f.fn_nfe_registrar_envio(uuid, jsonb, jsonb, text, integer, text) from public, anon, authenticated;
revoke all on function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text) from public, anon, authenticated;
revoke all on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer) from public, anon, authenticated;
grant execute on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text) to authenticated, service_role;
grant execute on function f.fn_nfe_contexto_emissao(uuid) to authenticated, service_role;
grant execute on function f.fn_nfe_registrar_envio(uuid, jsonb, jsonb, text, integer, text) to service_role;
grant execute on function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text) to service_role;
grant execute on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer) to service_role;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'f'
      and tablename = 'documento_fiscal_emissao'
  ) then
    alter publication supabase_realtime add table f.documento_fiscal_emissao;
  end if;
end;
$$;

-- O job fica instalado desde ja. Ele so dispara quando project_url e
-- service_role_key existirem no Vault; nenhuma credencial e versionada.
create extension if not exists pg_cron with schema pg_catalog;
do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'nfe-reconciliar-processando';

  perform cron.schedule(
    'nfe-reconciliar-processando',
    '*/15 * * * *',
    $job$
      select net.http_post(
        url := project_url.decrypted_secret || '/functions/v1/nfe-reconciliar',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_key.decrypted_secret
        ),
        body := '{}'::jsonb
      )
      from vault.decrypted_secrets project_url
      join vault.decrypted_secrets service_key on service_key.name = 'service_role_key'
      where project_url.name = 'project_url';
    $job$
  );
end;
$$;

commit;
