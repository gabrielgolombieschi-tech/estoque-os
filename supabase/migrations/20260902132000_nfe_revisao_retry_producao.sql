begin;

-- Uma solicitacao pode ter, no maximo, uma emissao por ambiente. A chave
-- anterior permitia somente uma emissao no total e impedia promover para
-- producao o mesmo rascunho que foi autorizado em homologacao.
drop index if exists f.uq_documento_fiscal_emissao_solicitacao;
create unique index if not exists uq_documento_fiscal_emissao_solicitacao_ambiente
  on f.documento_fiscal_emissao (tenant_id, empresa_id, solicitacao_id, ambiente)
  where solicitacao_id is not null;

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
    select 1 from public.ordens_servico os
    where os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id
      and os.id = p_os_id and os.tipo_documento in ('OS', 'OV')
  ) then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  return query
  with reservado as (
    select si.origem_item_id, sum(si.quantidade) as quantidade
    from f.solicitacao_item si
    join f.solicitacao_faturamento sf
      on sf.tenant_id = si.tenant_id and sf.empresa_id = si.empresa_id and sf.id = si.solicitacao_id
    where si.tenant_id = p_tenant_id and si.empresa_id = p_empresa_id
      and si.origem_tipo in ('OS', 'OV') and si.origem_id = p_os_id::text
      and sf.status <> 'CANCELADA'
      and (
        exists (
          select 1
          from f.documento_fiscal_emissao prod
          where prod.tenant_id = sf.tenant_id and prod.empresa_id = sf.empresa_id
            and prod.solicitacao_id = sf.id
            and prod.ambiente = 'PRODUCAO' and prod.status <> 'CANCELADA'
        )
        or not exists (
          select 1
          from f.documento_fiscal_emissao hom
          where hom.tenant_id = sf.tenant_id and hom.empresa_id = sf.empresa_id
            and hom.solicitacao_id = sf.id
            and hom.ambiente = 'HOMOLOGACAO' and hom.status = 'AUTORIZADA'
        )
      )
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
    on i.tenant_id = oi.tenant_id and i.empresa_id = oi.empresa_id and i.id = oi.item_id
  left join reservado r on r.origem_item_id = oi.id::text
  where oi.tenant_id = p_tenant_id and oi.empresa_id = p_empresa_id and oi.os_id = p_os_id
    and (oi.finalidade = 'venda' or oi.finalidade is null)
  order by oi.id;
end;
$function$;

comment on function f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer) is
  'Homologacao autorizada nao consome saldo; a mesma solicitacao volta a reservar e faturar quando possui emissao de PRODUCAO nao cancelada.';

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
  v_perfis integer := 0;
  v_perfil_id uuid;
  v_certificado_validade date;
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

  select ef.certificado_validade_em
    into v_certificado_validade
  from c.empresa_fiscal ef
  where ef.empresa_id = v_sf.empresa_id
    and ef.deleted_at is null;
  if not found or v_certificado_validade is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.');
  end if;
  if v_certificado_validade < current_date then
    return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.');
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

-- Depois que uma solicitacao possui a autorizacao de homologacao e uma
-- tentativa de producao, existem duas emissoes para o mesmo rascunho. A
-- conferencia sempre escolhe a emissao de producao quando ela existe; assim
-- uma rejeicao real pode ser corrigida sem trocar a referencia idempotente.
create or replace function f.fn_solicitacao_nfe_salvar_conferencia(
  p_solicitacao_id uuid,
  p_operacao jsonb,
  p_itens jsonb
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
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_item record;
  v_total_itens integer;
  v_usuario_id uuid := a.fn_current_usuario_id();
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Rascunho de NF-e nao encontrado.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Esta solicitacao nao pode mais ser alterada.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
  order by case when dfe.ambiente = 'PRODUCAO' then 0 else 1 end,
           dfe.created_at desc,
           dfe.documento_fiscal_id
  limit 1
  for update;

  if found and v_emissao.status not in ('REJEITADA', 'ERRO', 'RASCUNHO') then
    raise exception using errcode = '22023', message = 'Somente uma emissao rejeitada, com erro ou ainda em rascunho pode ser corrigida.';
  end if;
  if jsonb_typeof(p_operacao) <> 'object' or jsonb_typeof(p_itens) <> 'array' then
    raise exception using errcode = '22023', message = 'Operacao e itens da conferencia sao obrigatorios.';
  end if;

  select count(*) into v_total_itens
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if v_total_itens = 0
     or jsonb_array_length(p_itens) <> v_total_itens
     or (select count(distinct x.id) from jsonb_to_recordset(p_itens) x(id uuid)) <> v_total_itens then
    raise exception using errcode = '22023', message = 'A conferencia deve conter todas as linhas da solicitacao, sem duplicidade.';
  end if;

  update f.solicitacao_faturamento
  set finalidade_emissao = nullif(p_operacao->>'finalidade_emissao', '')::smallint,
      consumidor_final = nullif(p_operacao->>'consumidor_final', '')::smallint,
      presenca_comprador = nullif(p_operacao->>'presenca_comprador', '')::smallint,
      modalidade_frete = nullif(p_operacao->>'modalidade_frete', '')::smallint,
      valor_frete = nullif(p_operacao->>'valor_frete', '')::numeric,
      valor_seguro = nullif(p_operacao->>'valor_seguro', '')::numeric,
      valor_outras_despesas = nullif(p_operacao->>'valor_outras_despesas', '')::numeric,
      revisao_fiscal_confirmada_em = case when v_usuario_id is null then null else now() end,
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null,
      destinatario_snapshot = null,
      operacao_snapshot = null,
      snapshot_cadastro_em = null,
      status = 'PREVIA',
      updated_at = now()
  where id = v_sf.id;

  for v_item in
    select *
    from jsonb_to_recordset(p_itens) as x(
      id uuid,
      cfop text,
      cst_icms text,
      csosn text,
      cst_ipi text,
      cst_pis text,
      cst_cofins text,
      cbenef text,
      reducao_base_icms_percentual numeric,
      icms_modalidade_base_calculo text,
      aliquota_icms numeric,
      aliquota_ipi numeric,
      aliquota_pis numeric,
      aliquota_cofins numeric,
      cst_ibs_cbs text,
      cclass_trib text,
      cclass_trib_versao text,
      ibs_cbs_json jsonb
    )
  loop
    if nullif(btrim(v_item.cst_ibs_cbs), '') is null
       or nullif(btrim(v_item.cclass_trib), '') is null
       or nullif(btrim(v_item.cclass_trib_versao), '') is null
       or jsonb_typeof(v_item.ibs_cbs_json) is distinct from 'object'
       or v_item.ibs_cbs_json->>'ibs_uf_aliquota' is null
       or v_item.ibs_cbs_json->>'ibs_mun_aliquota' is null
       or v_item.ibs_cbs_json->>'cbs_aliquota' is null then
      raise exception using errcode = '22023', message = 'CST, cClassTrib, versao e aliquotas de IBS/CBS sao obrigatorios em cada item.';
    end if;

    update f.solicitacao_item si
    set cfop = nullif(regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g'), ''),
        cst_icms = nullif(btrim(v_item.cst_icms), ''),
        csosn = nullif(btrim(v_item.csosn), ''),
        cst_ipi = nullif(btrim(v_item.cst_ipi), ''),
        cst_pis = nullif(btrim(v_item.cst_pis), ''),
        cst_cofins = nullif(btrim(v_item.cst_cofins), ''),
        cbenef = nullif(btrim(v_item.cbenef), ''),
        reducao_base_icms_percentual = v_item.reducao_base_icms_percentual,
        icms_modalidade_base_calculo = nullif(btrim(v_item.icms_modalidade_base_calculo), ''),
        aliquota_icms = v_item.aliquota_icms,
        aliquota_ipi = v_item.aliquota_ipi,
        aliquota_pis = v_item.aliquota_pis,
        aliquota_cofins = v_item.aliquota_cofins,
        cst_ibs_cbs = nullif(regexp_replace(coalesce(v_item.cst_ibs_cbs, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib = nullif(regexp_replace(coalesce(v_item.cclass_trib, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib_versao = nullif(btrim(v_item.cclass_trib_versao), ''),
        ibs_cbs_json = v_item.ibs_cbs_json
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item.id;

    if not found then
      raise exception using errcode = '22023', message = format('Item %s nao pertence a esta solicitacao.', v_item.id);
    end if;
  end loop;

  if v_emissao.documento_fiscal_id is not null then
    update f.documento_fiscal_emissao
    set status = 'RASCUNHO', codigo_status = null, mensagem = null, updated_at = now()
    where documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;

  return jsonb_build_object('ok', true, 'solicitacao_id', v_sf.id, 'itens', v_total_itens);
end;
$function$;

comment on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) is
  'Salva a conferencia completa e reabre, pela mesma referencia, a emissao rejeitada mais recente, priorizando PRODUCAO.';

revoke all on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) from public, anon;
grant execute on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) to authenticated, service_role;

commit;
