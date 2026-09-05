begin;

-- A producao usa uma funcao propria. O endpoint de homologacao continua sem
-- qualquer caminho que possa selecionar o ambiente fiscal real.
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
  v_perfis integer := 0;
  v_perfil_id uuid;
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
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;

  select count(*), (array_agg(po.id order by po.vigencia_inicio desc, po.id))[1]
    into v_perfis, v_perfil_id
  from f.perfil_operacao po
  join c.empresa_fiscal ef
    on ef.empresa_id = v_sf.empresa_id
   and ef.deleted_at is null
  where po.tenant_id = v_sf.tenant_id
    and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
    and po.modelo = 'NFE'
    and po.natureza_operacao = v_sf.natureza_operacao
    and (po.crt is null or po.crt = ef.crt::text)
    and po.habilitado_producao
    and po.faixa_automacao <> 'BLOQUEADO'
    and po.vigencia_inicio <= current_date
    and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
    and (v_sf.perfil_operacao_id is null or po.id = v_sf.perfil_operacao_id);

  if v_perfis = 0 then
    return jsonb_build_object('pronta', false, 'motivo', 'Nenhum perfil fiscal vigente foi explicitamente liberado para producao.');
  end if;
  if v_perfis > 1 and v_sf.perfil_operacao_id is null then
    return jsonb_build_object('pronta', false, 'motivo', 'Mais de um perfil fiscal se aplica; selecione o perfil explicitamente.');
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

  return jsonb_build_object('pronta', true, 'perfil_operacao_id', coalesce(v_sf.perfil_operacao_id, v_perfil_id));
end;
$function$;

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
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para emitir esta solicitacao em producao.';
  end if;

  v_referencia := 'NFEP-' || v_sf.id;
  perform pg_advisory_xact_lock(hashtextextended(v_referencia, 0));

  return query
  select dfe.documento_fiscal_id, dfe.solicitacao_id, dfe.referencia_externa, dfe.status, false
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'PRODUCAO';
  if found then return; end if;

  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA')
     and not (
       v_sf.status = 'EMITIDA'
       and exists (
         select 1
         from f.documento_fiscal_emissao hom
         where hom.tenant_id = v_sf.tenant_id
           and hom.empresa_id = v_sf.empresa_id
           and hom.solicitacao_id = v_sf.id
           and hom.ambiente = 'HOMOLOGACAO'
           and hom.status = 'AUTORIZADA'
       )
     ) then
    raise exception using errcode = '22023', message = 'Solicitacao nao esta disponivel para emissao em producao.';
  end if;
  v_prontidao := f.fn_nfe_producao_pronta(v_sf.id);
  if not coalesce((v_prontidao->>'pronta')::boolean, false) then
    raise exception using errcode = 'P0001', message = coalesce(v_prontidao->>'motivo', 'Producao bloqueada.');
  end if;
  v_perfil_id := (v_prontidao->>'perfil_operacao_id')::uuid;

  update f.solicitacao_faturamento
  set perfil_operacao_id = v_perfil_id, updated_at = now()
  where id = v_sf.id;

  select
    round(coalesce(sum(si.quantidade * si.valor_unitario), 0), 2),
    round(coalesce(sum(si.valor_desconto), 0), 2),
    round(coalesce(sum(si.quantidade * si.valor_unitario - si.valor_desconto), 0), 2)
      + coalesce(v_sf.valor_frete, 0) + coalesce(v_sf.valor_seguro, 0) + coalesce(v_sf.valor_outras_despesas, 0),
    min(case when si.origem_tipo in ('OS','OV') and si.origem_id ~ '^[0-9]+$' then si.origem_id::integer end)
  into v_total_produtos, v_total_desconto, v_total_nota, v_os_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if not exists (
    select 1 from f.solicitacao_item si
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

  update f.solicitacao_faturamento
  set status = 'APROVADA', updated_at = now()
  where id = v_sf.id;

  return query select v_documento_id, v_sf.id, v_referencia, 'RASCUNHO'::text, true;
end;
$function$;

revoke all on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid) from public, anon;
grant execute on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid) to authenticated, service_role;

create or replace function f.fn_nfe_aplicar_retorno_producao(
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
  p_xml_raw text default null,
  p_origem_retorno text default 'CALLBACK'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_xml_hash text;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode aplicar retorno de producao.';
  end if;
  if v_status not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'CANCELADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de retorno invalido.';
  end if;

  select * into v_emissao
  from f.documento_fiscal_emissao
  where referencia_externa = p_referencia_externa
  for update;
  if not found then raise exception using errcode = 'P0002', message = format('Referencia %s nao encontrada.', p_referencia_externa); end if;
  if v_emissao.ambiente <> 'PRODUCAO' then
    raise exception using errcode = '42501', message = 'Este pipeline aplica retorno somente de PRODUCAO.';
  end if;
  if v_emissao.status = 'AUTORIZADA' and v_status <> 'AUTORIZADA' then return v_emissao.documento_fiscal_id; end if;

  if v_status = 'AUTORIZADA' then
    if nullif(p_chave_acesso, '') is null or p_chave_acesso !~ '^[0-9]{44}$' then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem chave de acesso valida.';
    end if;
    if nullif(btrim(coalesce(p_xml_raw, '')), '') is null then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem XML para f.documento_fiscal_xml.';
    end if;
    v_xml_hash := encode(extensions.digest(convert_to(p_xml_raw, 'utf8'), 'sha256'), 'hex');
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
    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_emissao.tenant_id, v_emissao.documento_fiscal_id, p_chave_acesso, p_xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id)
    do update set chave_acesso = excluded.chave_acesso,
                  xml_raw = excluded.xml_raw,
                  xml_hash = excluded.xml_hash,
                  deleted_at = null;

    -- Esta mudanca de status e o unico ponto que cria o Contas a Receber.
    -- O trigger legado de faturamento continua sendo a fonte dessa automacao.
    update f.documento_fiscal
    set chave_acesso = p_chave_acesso,
        numero = coalesce(p_numero::text, numero),
        serie = coalesce(p_serie::text, serie),
        nfe_status = 'EMITIDA',
        emissao_date = coalesce(emissao_date, current_date),
        competencia_date = date_trunc('month', coalesce(emissao_date, current_date))::date,
        updated_at = now()
    where tenant_id = v_emissao.tenant_id
      and empresa_id = v_emissao.empresa_id
      and id = v_emissao.documento_fiscal_id;

    update f.solicitacao_faturamento
    set status = 'EMITIDA', updated_at = now()
    where tenant_id = v_emissao.tenant_id
      and empresa_id = v_emissao.empresa_id
      and id = v_emissao.solicitacao_id;

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
    from jsonb_array_elements(coalesce(
      (select payload_enviado from f.documento_fiscal_emissao where documento_fiscal_id = v_emissao.documento_fiscal_id)->'items',
      '[]'::jsonb
    )) x(item)
    where dfi.tenant_id = v_emissao.tenant_id
      and dfi.empresa_id = v_emissao.empresa_id
      and dfi.documento_fiscal_id = v_emissao.documento_fiscal_id
      and dfi.item_n = (x.item->>'numero_item')::integer;
  end if;

  return v_emissao.documento_fiscal_id;
end;
$function$;

revoke all on function f.fn_nfe_aplicar_retorno_producao(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_aplicar_retorno_producao(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text)
  to service_role;

create or replace function f.fn_nfe_emissoes_pendentes_reconciliacao_producao(p_limite integer default 50)
returns table (documento_fiscal_id uuid, referencia_externa text, ambiente text)
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select dfe.documento_fiscal_id, dfe.referencia_externa, dfe.ambiente
  from f.documento_fiscal_emissao dfe
  where dfe.status = 'PROCESSANDO'
    and dfe.ambiente = 'PRODUCAO'
    and dfe.updated_at < now() - interval '10 minutes'
  order by dfe.updated_at
  limit least(greatest(coalesce(p_limite, 50), 1), 200);
$function$;

revoke all on function f.fn_nfe_emissoes_pendentes_reconciliacao_producao(integer) from public, anon, authenticated;
grant execute on function f.fn_nfe_emissoes_pendentes_reconciliacao_producao(integer) to service_role;

-- A consulta historica nao separava ambientes porque, ate aqui, so existia
-- homologacao. A partir deste ponto cada reconciliador recebe apenas o seu
-- ambiente e nunca pode consultar uma referencia real na API errada.
create or replace function f.fn_nfe_emissoes_pendentes_reconciliacao(p_limite integer default 50)
returns table (documento_fiscal_id uuid, referencia_externa text, ambiente text)
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select dfe.documento_fiscal_id, dfe.referencia_externa, dfe.ambiente
  from f.documento_fiscal_emissao dfe
  where dfe.status = 'PROCESSANDO'
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.updated_at < now() - interval '10 minutes'
  order by dfe.updated_at
  limit least(greatest(coalesce(p_limite, 50), 1), 200);
$function$;

revoke all on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer) to service_role;

-- O historico de envio passa a registrar cada tentativa; a linha de emissao
-- permanece o estado atual e o evento e append-only.
alter table f.documento_fiscal_evento
  drop constraint documento_fiscal_evento_tipo_check;
alter table f.documento_fiscal_evento
  add constraint documento_fiscal_evento_tipo_check check (tipo in (
    'CANCELAMENTO', 'CARTA_CORRECAO', 'ESTORNO', 'SUBSTITUICAO',
    'REENVIO', 'CONSULTA', 'EMAIL', 'DOWNLOAD',
    'ENVIO', 'REJEICAO', 'AUTORIZACAO'
  ));

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
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode registrar o envio.';
  end if;
  if v_status not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de envio invalido.';
  end if;

  update f.documento_fiscal_emissao
  set status = v_status,
      payload_enviado = coalesce(p_payload, payload_enviado),
      resposta = coalesce(p_resposta, resposta),
      codigo_status = coalesce(p_codigo_status, codigo_status),
      mensagem = coalesce(p_mensagem, mensagem),
      tentativa_count = tentativa_count + 1,
      ultima_tentativa_em = now(),
      enviado_em = coalesce(enviado_em, now()),
      updated_at = now()
  where documento_fiscal_id = p_documento_fiscal_id
  returning * into v_emissao;
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao nao encontrada.';
  end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta
  ) values (
    v_emissao.documento_fiscal_id,
    v_emissao.tenant_id,
    v_emissao.empresa_id,
    case
      when v_status = 'AUTORIZADA' then 'AUTORIZACAO'
      when v_status in ('REJEITADA', 'ERRO') then 'REJEICAO'
      else 'ENVIO'
    end,
    v_status,
    jsonb_strip_nulls(jsonb_build_object(
      'codigo_status', p_codigo_status,
      'mensagem', p_mensagem,
      'resposta', p_resposta
    ))
  );
end;
$function$;

revoke all on function f.fn_nfe_registrar_envio(uuid, jsonb, jsonb, text, integer, text)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_registrar_envio(uuid, jsonb, jsonb, text, integer, text)
  to service_role;

-- Registra a autorizacao piloto anterior ao historico por tentativa.
insert into f.documento_fiscal_evento (
  documento_fiscal_id, tenant_id, empresa_id, tipo, status, protocolo, resposta, created_at
)
select dfe.documento_fiscal_id, dfe.tenant_id, dfe.empresa_id,
       'AUTORIZACAO', 'AUTORIZADA', dfe.protocolo,
       jsonb_strip_nulls(jsonb_build_object(
         'codigo_status', dfe.codigo_status,
         'mensagem', dfe.mensagem,
         'resposta', dfe.resposta
       )),
       coalesce(dfe.autorizado_em, dfe.updated_at, now())
from f.documento_fiscal_emissao dfe
where dfe.status = 'AUTORIZADA'
  and not exists (
    select 1 from f.documento_fiscal_evento ev
    where ev.tenant_id = dfe.tenant_id
      and ev.empresa_id = dfe.empresa_id
      and ev.documento_fiscal_id = dfe.documento_fiscal_id
      and ev.tipo = 'AUTORIZACAO'
  );

-- Corrige a aliquota consolidada usando os nomes efetivamente aceitos pela
-- Focus para PIS/COFINS. O valor e a base continuam vindo do payload enviado.
update f.documento_fiscal_imposto imp
set aliquota = src.aliquota,
    updated_at = now()
from (
  select dfe.tenant_id, dfe.documento_fiscal_id, t.imposto,
         case
           when count(distinct nullif(x.item->>t.chave, '')::numeric) = 1
             then max(nullif(x.item->>t.chave, '')::numeric)
           else imp2.aliquota
         end as aliquota
  from f.documento_fiscal_emissao dfe
  cross join lateral jsonb_array_elements(coalesce(dfe.payload_enviado->'items', '[]'::jsonb)) x(item)
  cross join (values
    ('PIS'::text, 'pis_aliquota_porcentual'::text),
    ('COFINS'::text, 'cofins_aliquota_porcentual'::text)
  ) t(imposto, chave)
  join f.documento_fiscal_imposto imp2
    on imp2.tenant_id = dfe.tenant_id
   and imp2.documento_fiscal_id = dfe.documento_fiscal_id
   and imp2.imposto = t.imposto
   and imp2.natureza = 'DEBITO'
   and imp2.deleted_at is null
  where dfe.status = 'AUTORIZADA'
  group by dfe.tenant_id, dfe.documento_fiscal_id, t.imposto, imp2.aliquota
) src
where imp.tenant_id = src.tenant_id
  and imp.documento_fiscal_id = src.documento_fiscal_id
  and imp.imposto = src.imposto
  and imp.natureza = 'DEBITO'
  and src.aliquota is not null;

create or replace function f.trg_nfe_snapshot_zz_aliquotas()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
begin
  if new.status = 'AUTORIZADA'
     and jsonb_typeof(new.payload_enviado->'items') = 'array' then
    update f.documento_fiscal_imposto imp
    set aliquota = src.aliquota,
        updated_at = now()
    from (
      select t.imposto,
             case
               when count(distinct nullif(x.item->>t.chave, '')::numeric) = 1
                 then max(nullif(x.item->>t.chave, '')::numeric)
               when sum(coalesce(nullif(x.item->>t.base_chave, '')::numeric, 0)) > 0
                 then round(
                   sum(coalesce(nullif(x.item->>t.valor_chave, '')::numeric, 0))
                   / sum(coalesce(nullif(x.item->>t.base_chave, '')::numeric, 0)) * 100,
                   4
                 )
               else 0
             end as aliquota
      from jsonb_array_elements(new.payload_enviado->'items') x(item)
      cross join (values
        ('PIS'::text, 'pis_aliquota_porcentual'::text, 'pis_base_calculo'::text, 'pis_valor'::text),
        ('COFINS'::text, 'cofins_aliquota_porcentual'::text, 'cofins_base_calculo'::text, 'cofins_valor'::text)
      ) t(imposto, chave, base_chave, valor_chave)
      group by t.imposto, t.chave, t.base_chave, t.valor_chave
    ) src
    where imp.tenant_id = new.tenant_id
      and imp.documento_fiscal_id = new.documento_fiscal_id
      and imp.imposto = src.imposto
      and imp.natureza = 'DEBITO'
      and imp.deleted_at is null;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_nfe_snapshot_zz_aliquotas on f.documento_fiscal_emissao;
create trigger trg_nfe_snapshot_zz_aliquotas
after insert or update of status, payload_enviado
on f.documento_fiscal_emissao
for each row execute function f.trg_nfe_snapshot_zz_aliquotas();

commit;
