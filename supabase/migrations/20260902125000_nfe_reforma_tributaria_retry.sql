begin;

-- Permite corrigir e reenviar, com a mesma referencia idempotente, uma NF-e
-- efetivamente rejeitada. Uma autorizacao ou processamento continua imutavel.
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

  select * into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
  for update;

  if found and (v_emissao.ambiente <> 'HOMOLOGACAO' or v_emissao.status not in ('REJEITADA', 'ERRO', 'RASCUNHO')) then
    raise exception using errcode = '22023', message = 'Somente uma emissao rejeitada em homologacao pode ser corrigida.';
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
  'Salva conferencia completa, inclusive IBS/CBS, e permite corrigir rejeicao de homologacao sem trocar a referencia idempotente.';

revoke all on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) from public, anon;
grant execute on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) to authenticated, service_role;

commit;
