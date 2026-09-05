begin;

-- Registra a ultima revisao humana do perfil e a decisao explicita sobre o
-- uso em producao. O historico detalhado continua coberto pela auditoria
-- geral; estas colunas deixam o estado corrente visivel para a operacao.
alter table f.perfil_operacao
  add column revisao_fiscal_em timestamptz,
  add column revisao_fiscal_por uuid references a.usuario(id) on delete set null,
  add column revisao_fiscal_justificativa text,
  add column producao_decidida_em timestamptz,
  add column producao_decidida_por uuid references a.usuario(id) on delete set null,
  add constraint perfil_operacao_revisao_fiscal_justificativa_ck
    check (
      revisao_fiscal_justificativa is null
      or char_length(btrim(revisao_fiscal_justificativa)) between 15 and 1000
    );

comment on column f.perfil_operacao.revisao_fiscal_em is
  'Data da ultima revisao humana dos campos IBS/CBS do perfil.';
comment on column f.perfil_operacao.revisao_fiscal_por is
  'Usuario que realizou a ultima revisao humana dos campos IBS/CBS.';
comment on column f.perfil_operacao.revisao_fiscal_justificativa is
  'Justificativa obrigatoria da ultima revisao dos campos IBS/CBS.';
comment on column f.perfil_operacao.producao_decidida_em is
  'Data da ultima decisao explicita de habilitar ou desabilitar o perfil em producao.';
comment on column f.perfil_operacao.producao_decidida_por is
  'Usuario responsavel pela ultima decisao explicita sobre producao.';

create or replace function f.fn_perfil_operacao_nfe_listar()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_scope record;
  v_perfis jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select coalesce(
    jsonb_agg(x.perfil order by x.codigo, x.vigencia_inicio desc),
    '[]'::jsonb
  )
    into v_perfis
  from (
    select
      po.codigo,
      po.vigencia_inicio,
      jsonb_build_object(
        'id', po.id,
        'codigo', po.codigo,
        'nome', po.nome,
        'modelo', po.modelo,
        'natureza_operacao', po.natureza_operacao,
        'natureza_texto', po.natureza_texto,
        'crt', po.crt,
        'cfop_interno', po.cfop_interno,
        'cfop_externo', po.cfop_externo,
        'cst_icms', po.cst_icms,
        'csosn', po.csosn,
        'origem_mercadoria', po.origem_mercadoria,
        'icms_modalidade_base_calculo', po.icms_modalidade_base_calculo,
        'aliquota_icms', po.aliquota_icms,
        'reducao_base_icms_percentual', po.reducao_base_icms_percentual,
        'cbenef', po.cbenef,
        'cbenef_aplicacao', po.cbenef_aplicacao,
        'cst_pis', po.cst_pis,
        'aliquota_pis', po.aliquota_pis,
        'cst_cofins', po.cst_cofins,
        'aliquota_cofins', po.aliquota_cofins,
        'ambito_destino', po.ambito_destino,
        'ufs_destino', po.ufs_destino,
        'indicador_ie_destinatario', po.indicador_ie_destinatario,
        'finalidade_emissao', po.finalidade_emissao,
        'consumidor_final', po.consumidor_final,
        'faixa_automacao', po.faixa_automacao,
        'justificativa_faixa', po.justificativa_faixa,
        'evidencia_id', po.evidencia_id,
        'vigencia_inicio', po.vigencia_inicio,
        'vigencia_fim', po.vigencia_fim,
        'vigente', (
          po.vigencia_inicio <= current_date
          and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
        ),
        'cst_ibs_cbs', po.cst_ibs_cbs,
        'cclass_trib', po.cclass_trib,
        'cclass_trib_versao', po.cclass_trib_versao,
        'ibs_uf_aliquota', po.ibs_cbs_json->'ibs_uf_aliquota',
        'ibs_mun_aliquota', po.ibs_cbs_json->'ibs_mun_aliquota',
        'cbs_aliquota', po.ibs_cbs_json->'cbs_aliquota',
        'habilitado_producao', po.habilitado_producao,
        'revisao_fiscal_em', po.revisao_fiscal_em,
        'revisao_fiscal_por', po.revisao_fiscal_por,
        'revisao_fiscal_justificativa', po.revisao_fiscal_justificativa,
        'producao_decidida_em', po.producao_decidida_em,
        'producao_decidida_por', po.producao_decidida_por
      ) as perfil
    from f.perfil_operacao po
    where po.tenant_id = v_scope.tenant_id
      and po.empresa_id = v_scope.empresa_id
      and po.modelo = 'NFE'
  ) x;

  return jsonb_build_object(
    'tenant_id', v_scope.tenant_id,
    'empresa_id', v_scope.empresa_id,
    'perfis', v_perfis
  );
end;
$function$;

create or replace function f.fn_perfil_operacao_nfe_revisar(
  p_perfil_id uuid,
  p_cst_ibs_cbs text,
  p_cclass_trib text,
  p_cclass_trib_versao text,
  p_ibs_uf_aliquota numeric,
  p_ibs_mun_aliquota numeric,
  p_cbs_aliquota numeric,
  p_justificativa text,
  p_habilitado_producao boolean,
  p_confirmacao_producao boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_cst text := btrim(coalesce(p_cst_ibs_cbs, ''));
  v_cclass text := btrim(coalesce(p_cclass_trib, ''));
  v_versao text := btrim(coalesce(p_cclass_trib_versao, ''));
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '')
       in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao de escrita para revisar perfis fiscais.';
  end if;

  if p_perfil_id is null then
    raise exception using errcode = '22023', message = 'Perfil fiscal obrigatorio.';
  end if;

  select po.*
    into v_perfil
  from f.perfil_operacao po
  where po.id = p_perfil_id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
    and po.modelo = 'NFE'
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Perfil NF-e nao encontrado no tenant e empresa ativos.';
  end if;

  if v_cst !~ '^[0-9]{3}$' then
    raise exception using errcode = '22023', message = 'CST IBS/CBS deve conter exatamente 3 digitos.';
  end if;
  if v_cclass !~ '^[0-9]{6}$' then
    raise exception using errcode = '22023', message = 'cClassTrib deve conter exatamente 6 digitos.';
  end if;
  if left(v_cclass, 3) <> v_cst then
    raise exception using errcode = '22023', message = 'Os 3 primeiros digitos do cClassTrib devem coincidir com o CST IBS/CBS.';
  end if;
  if char_length(v_versao) < 3 or char_length(v_versao) > 100 then
    raise exception using errcode = '22023', message = 'Informe a versao da tabela cClassTrib (3 a 100 caracteres).';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then
    raise exception using errcode = '22023', message = 'A justificativa da revisao deve ter entre 15 e 1000 caracteres.';
  end if;
  if p_ibs_uf_aliquota is null or p_ibs_uf_aliquota < 0 or p_ibs_uf_aliquota > 100
     or p_ibs_uf_aliquota <> round(p_ibs_uf_aliquota, 4) then
    raise exception using errcode = '22023', message = 'Aliquota IBS UF deve estar entre 0 e 100, com ate 4 casas decimais.';
  end if;
  if p_ibs_mun_aliquota is null or p_ibs_mun_aliquota < 0 or p_ibs_mun_aliquota > 100
     or p_ibs_mun_aliquota <> round(p_ibs_mun_aliquota, 4) then
    raise exception using errcode = '22023', message = 'Aliquota IBS municipal deve estar entre 0 e 100, com ate 4 casas decimais.';
  end if;
  if p_cbs_aliquota is null or p_cbs_aliquota < 0 or p_cbs_aliquota > 100
     or p_cbs_aliquota <> round(p_cbs_aliquota, 4) then
    raise exception using errcode = '22023', message = 'Aliquota CBS deve estar entre 0 e 100, com ate 4 casas decimais.';
  end if;
  if p_habilitado_producao is null then
    raise exception using errcode = '22023', message = 'A decisao sobre producao deve ser explicita.';
  end if;
  if p_habilitado_producao and not coalesce(p_confirmacao_producao, false) then
    raise exception using errcode = '22023', message = 'Confirme explicitamente a liberacao do perfil para producao.';
  end if;

  if p_habilitado_producao then
    if v_perfil.faixa_automacao = 'BLOQUEADO' then
      raise exception using errcode = '22023', message = 'Perfil bloqueado nao pode ser liberado para producao.';
    end if;
    if v_perfil.vigencia_inicio > current_date
       or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date) then
      raise exception using errcode = '22023', message = 'Somente perfil vigente pode ser liberado para producao.';
    end if;
    if v_perfil.evidencia_id is null then
      raise exception using errcode = '22023', message = 'A evidencia fiscal do perfil precisa estar vinculada antes da producao.';
    end if;
    if v_perfil.ambito_destino is null
       or v_perfil.ufs_destino is null
       or cardinality(v_perfil.ufs_destino) = 0 then
      raise exception using errcode = '22023', message = 'Ambito e UFs de destino precisam estar confirmados antes da producao.';
    end if;
    if v_perfil.ambito_destino = 'INTERNA' and coalesce(v_perfil.cfop_interno, '') !~ '^[0-9]{4}$' then
      raise exception using errcode = '22023', message = 'CFOP interno valido e obrigatorio para este perfil.';
    end if;
    if v_perfil.ambito_destino = 'INTERESTADUAL' and coalesce(v_perfil.cfop_externo, '') !~ '^[0-9]{4}$' then
      raise exception using errcode = '22023', message = 'CFOP interestadual valido e obrigatorio para este perfil.';
    end if;
    if v_perfil.origem_mercadoria is null then
      raise exception using errcode = '22023', message = 'Origem da mercadoria precisa estar confirmada antes da producao.';
    end if;
    if coalesce(v_perfil.crt, '') !~ '^[123]$' then
      raise exception using errcode = '22023', message = 'CRT precisa estar confirmado antes da producao.';
    end if;
    if v_perfil.crt = '3' and coalesce(v_perfil.cst_icms, '') !~ '^[0-9]{2}$' then
      raise exception using errcode = '22023', message = 'CST ICMS valido e obrigatorio para regime normal.';
    end if;
    if v_perfil.crt in ('1', '2') and coalesce(v_perfil.csosn, '') !~ '^[0-9]{3}$' then
      raise exception using errcode = '22023', message = 'CSOSN valido e obrigatorio para Simples Nacional.';
    end if;
    if v_perfil.cbenef_aplicacao = 'NAO_CONFIRMADO' then
      raise exception using errcode = '22023', message = 'A aplicacao de cBenef precisa estar confirmada antes da producao.';
    end if;
    if coalesce(v_perfil.cst_pis, '') !~ '^[0-9]{2}$'
       or coalesce(v_perfil.cst_cofins, '') !~ '^[0-9]{2}$' then
      raise exception using errcode = '22023', message = 'CST de PIS e COFINS precisam estar confirmados antes da producao.';
    end if;
    if v_perfil.finalidade_emissao is null or v_perfil.consumidor_final is null then
      raise exception using errcode = '22023', message = 'Finalidade da emissao e consumidor final precisam estar confirmados antes da producao.';
    end if;
  end if;

  update f.perfil_operacao po
  set cst_ibs_cbs = v_cst,
      cclass_trib = v_cclass,
      cclass_trib_versao = v_versao,
      ibs_cbs_json = jsonb_build_object(
        'ibs_uf_aliquota', p_ibs_uf_aliquota,
        'ibs_mun_aliquota', p_ibs_mun_aliquota,
        'cbs_aliquota', p_cbs_aliquota
      ),
      habilitado_producao = p_habilitado_producao,
      revisao_fiscal_em = now(),
      revisao_fiscal_por = v_scope.usuario_id,
      revisao_fiscal_justificativa = v_justificativa,
      producao_decidida_em = now(),
      producao_decidida_por = v_scope.usuario_id
  where po.id = v_perfil.id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id;

  return jsonb_build_object(
    'perfil_id', v_perfil.id,
    'codigo', v_perfil.codigo,
    'habilitado_producao', p_habilitado_producao,
    'revisao_fiscal_em', now(),
    'mensagem', case
      when p_habilitado_producao then 'Perfil revisado e liberado explicitamente para producao.'
      else 'Perfil revisado e mantido fora de producao.'
    end
  );
end;
$function$;

revoke all on function f.fn_perfil_operacao_nfe_listar()
  from public, anon, authenticated;
grant execute on function f.fn_perfil_operacao_nfe_listar()
  to authenticated, service_role;

revoke all on function f.fn_perfil_operacao_nfe_revisar(
  uuid, text, text, text, numeric, numeric, numeric, text, boolean, boolean
) from public, anon, authenticated;
grant execute on function f.fn_perfil_operacao_nfe_revisar(
  uuid, text, text, text, numeric, numeric, numeric, text, boolean, boolean
) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
