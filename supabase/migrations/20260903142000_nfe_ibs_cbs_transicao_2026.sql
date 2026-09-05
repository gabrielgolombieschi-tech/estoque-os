begin;

-- A versao da NT e metadado do leiaute implementado pelo provedor. Ela nao
-- qualifica o tratamento tributario e deixa de ser obrigatoria nos snapshots.
alter table f.solicitacao_item
  drop constraint if exists solicitacao_item_cclass_versao_ck;
alter table f.documento_fiscal_item
  drop constraint if exists documento_fiscal_item_cclass_versao_ck;
alter table f.perfil_operacao
  drop constraint if exists perfil_operacao_cclass_versao_ck;
alter table f.operacao_fiscal_item
  drop constraint if exists operacao_fiscal_item_cclass_versao_ck;

comment on column f.solicitacao_item.cclass_trib_versao is
  'Legado de auditoria do provedor; nao e valor tributario, nao e obrigatorio e nao integra o payload.';
comment on column f.documento_fiscal_item.cclass_trib_versao is
  'Legado de auditoria do provedor; nao e valor tributario, nao e obrigatorio e nao integra o payload.';
comment on column f.perfil_operacao.cclass_trib_versao is
  'Legado de auditoria do provedor; nao usar para resolver CST/cClassTrib nem para montar payload.';

-- A RPC especifica de 2026 impede que o navegador escolha ou adultere os
-- valores legais. Ela delega os demais campos ao validador consolidado e,
-- depois, substitui apenas IBS/CBS pela regra legal vinculada a natureza.
create or replace function f.fn_solicitacao_nfe_salvar_conferencia_2026(
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
  v_item jsonb;
  v_item_id uuid;
  v_codigo text;
  v_cfop text;
  v_perfil_id uuid;
  v_versao_legada text;
  v_itens_validados jsonb := '[]'::jsonb;
  v_resultado jsonb;
  v_data_local date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
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
  if extract(year from v_data_local)::integer <> 2026 then
    raise exception using errcode = '22023', message = format(
      'Emissao bloqueada: a tabela IBS/CBS precisa ser revisada para o exercicio %s; vigencia atual 2026-01-01 a 2026-12-31.',
      extract(year from v_data_local)::integer
    );
  end if;
  if v_sf.natureza_operacao is distinct from 'VENDA_MERCADORIA_TERCEIROS' then
    raise exception using errcode = '22023', message = format(
      'Emissao bloqueada: natureza da operacao %s sem cClassTrib mapeado para 2026.',
      coalesce(v_sf.natureza_operacao, '<vazia>')
    );
  end if;
  if jsonb_typeof(p_itens) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Os itens da conferencia sao obrigatorios.';
  end if;

  for v_item in select value from jsonb_array_elements(p_itens)
  loop
    v_item_id := nullif(v_item->>'id', '')::uuid;
    select coalesce(si.codigo_produto, si.descricao, si.id::text)
      into v_codigo
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item_id;
    if not found then
      raise exception using errcode = '22023', message = format('Item %s nao pertence a esta solicitacao.', v_item_id);
    end if;

    v_cfop := nullif(regexp_replace(coalesce(v_item->>'cfop', ''), '[^0-9]', '', 'g'), '');
    if v_cfop is distinct from '5102' then
      raise exception using errcode = '22023', message = format(
        'Emissao bloqueada: natureza da operacao %s nao possui cClassTrib aprovado para o CFOP %s (item %s).',
        v_sf.natureza_operacao, coalesce(v_cfop, '<vazio>'), v_codigo
      );
    end if;
    if nullif(regexp_replace(coalesce(v_item->>'cst_ibs_cbs', ''), '[^0-9]', '', 'g'), '') is distinct from '000'
       or nullif(regexp_replace(coalesce(v_item->>'cclass_trib', ''), '[^0-9]', '', 'g'), '') is distinct from '000001'
       or (v_item#>>'{ibs_cbs_json,ibs_uf_aliquota}')::numeric is distinct from 0.1000
       or (v_item#>>'{ibs_cbs_json,ibs_mun_aliquota}')::numeric is distinct from 0.0000
       or (v_item#>>'{ibs_cbs_json,cbs_aliquota}')::numeric is distinct from 0.9000 then
      raise exception using errcode = '22023', message = format(
        'Item %s: IBS/CBS deve usar a regra legal de 2026 da natureza %s (CST 000, cClassTrib 000001, IBS UF 0,1%%, IBS municipal 0%% e CBS 0,9%%).',
        v_codigo, v_sf.natureza_operacao
      );
    end if;

    v_perfil_id := nullif(v_item->>'perfil_operacao_id', '')::uuid;
    select po.cclass_trib_versao into v_versao_legada
    from f.perfil_operacao po
    where po.tenant_id = v_sf.tenant_id
      and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
      and po.id = v_perfil_id;

    -- Compatibilidade transitiva com o validador anterior. O valor e removido
    -- imediatamente abaixo e jamais segue para o payload da Focus.
    v_itens_validados := v_itens_validados || jsonb_build_array(
      v_item || jsonb_build_object(
        'cclass_trib_versao', coalesce(nullif(btrim(v_versao_legada), ''), 'NAO_APLICAVEL_A_TRIBUTACAO')
      )
    );
  end loop;

  v_resultado := f.fn_solicitacao_nfe_salvar_conferencia(
    p_solicitacao_id,
    p_operacao,
    v_itens_validados
  );

  update f.solicitacao_item si
  set cst_ibs_cbs = '000',
      cclass_trib = '000001',
      cclass_trib_versao = null,
      ibs_cbs_json = jsonb_build_object(
        'ibs_uf_aliquota', 0.1000,
        'ibs_mun_aliquota', 0.0000,
        'cbs_aliquota', 0.9000
      )
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  return v_resultado;
end;
$function$;

comment on function f.fn_solicitacao_nfe_salvar_conferencia_2026(uuid, jsonb, jsonb) is
  'Confere a NF-e e aplica IBS/CBS legal do exercicio 2026 por natureza; falha fora da vigencia ou sem cClassTrib mapeado.';
revoke all on function f.fn_solicitacao_nfe_salvar_conferencia_2026(uuid, jsonb, jsonb) from public, anon;
grant execute on function f.fn_solicitacao_nfe_salvar_conferencia_2026(uuid, jsonb, jsonb) to authenticated, service_role;

commit;
