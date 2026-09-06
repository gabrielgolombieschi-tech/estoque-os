-- Tela de perfis fiscais passa a atender NFS-e (liberacao para producao) e a
-- emissao de nota ganha capacidade propria.
--
-- 1. Liberar um perfil de servico para producao era so por script
--    (fn_perfil_operacao_nfse_liberar_producao). A tela /faturamento/perfis
--    filtrava modelo = 'NFE' em duas RPCs; agora lista os dois modelos e traz
--    junto os campos de servico, para o resumo somente leitura. A REVISAO do
--    perfil de servico continua por script, de proposito: os ~30 campos e a
--    justificativa do contador ficam versionados em scripts/nfse-perfil-revisar.mjs,
--    do mesmo jeito que os campos de NF-e vem de migration.
--
-- 2. faturamento.emitir: quem emite nota e libera perfil. Decisao de Gabriel em
--    06/09/2026 — ADMIN, FINANCEIRO e FATURAMENTO na empresa (Gabriel, Larissa,
--    Deyvison e Vanessa). DIRETOR nao entra. Vale para o botao Faturar da OS, o
--    quadro de faturamento por valor e o menu Comercial > OV.
--    Observacao: papel de TENANT OWNER/ADMIN/DIRETOR continua com carta branca no
--    portao antigo (can_unscoped), entao a restricao real e de tela.
--
-- Baselines (06/09/2026): f.fn_perfil_operacao_nfe_listar e
-- f.fn_perfil_operacao_nfe_homologacoes_listar (20260902132000),
-- public.get_full_permissions_unscoped_20260810 e public.can_unscoped_20260810
-- (20260810120000).

CREATE OR REPLACE FUNCTION f.fn_perfil_operacao_nfe_listar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
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
        'producao_decidida_por', po.producao_decidida_por,
        'producao_decisao_justificativa', po.producao_decisao_justificativa,
        'producao_homologacao_solicitacao_id', po.producao_homologacao_solicitacao_id,
        'producao_homologacao_documento_id', po.producao_homologacao_documento_id,
        'item_servico', po.item_servico,
        'codigo_tributacao_nacional', po.codigo_tributacao_nacional,
        'codigo_nbs', po.codigo_nbs,
        'descricao_servico_padrao', po.descricao_servico_padrao,
        'local_prestacao_regra', po.local_prestacao_regra,
        'incidencia_iss_regra', po.incidencia_iss_regra,
        'tributacao_iss', po.tributacao_iss,
        'aliquota_iss', po.aliquota_iss,
        'iss_retido_regra', po.iss_retido_regra,
        'retencao_pcc_regra', po.retencao_pcc_regra,
        'aliquota_pcc', po.aliquota_pcc,
        'retencao_irrf_regra', po.retencao_irrf_regra,
        'aliquota_irrf', po.aliquota_irrf,
        'retencao_inss_regra', po.retencao_inss_regra,
        'aliquota_inss', po.aliquota_inss,
        'permite_deducao_material', po.permite_deducao_material,
        'excecao_conserto_isolado', po.excecao_conserto_isolado,
        'codigo_indicador_operacao', po.codigo_indicador_operacao,
        'tributos_aprox_federal_pct', po.tributos_aprox_federal_pct,
        'tributos_aprox_municipal_pct', po.tributos_aprox_municipal_pct,
        'campos_conferir', po.campos_conferir,
        'texto_complementar', po.texto_complementar,
        'texto_sem_retencao', po.texto_sem_retencao
      ) as perfil
    from f.perfil_operacao po
    where po.tenant_id = v_scope.tenant_id
      and po.empresa_id = v_scope.empresa_id
      and po.modelo in ('NFE', 'NFSE')
  ) x;

  return jsonb_build_object(
    'tenant_id', v_scope.tenant_id,
    'empresa_id', v_scope.empresa_id,
    'perfis', v_perfis
  );
end;
$function$;

CREATE OR REPLACE FUNCTION f.fn_perfil_operacao_nfe_homologacoes_listar(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_homologacoes jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select po.* into v_perfil
  from f.perfil_operacao po
  where po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
    and po.id = p_perfil_id
    and po.modelo in ('NFE', 'NFSE');

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Perfil fiscal nao encontrado no tenant e empresa ativos.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'solicitacao_id', h.solicitacao_id,
        'documento_fiscal_id', h.documento_fiscal_id,
        'referencia_externa', h.referencia_externa,
        'autorizado_em', h.autorizado_em,
        'cancelamento_em_andamento', h.cancelamento_em_andamento,
        'apos_ultima_revisao', (
          v_perfil.revisao_fiscal_em is not null
          and h.autorizado_em > v_perfil.revisao_fiscal_em
        )
      )
      order by h.autorizado_em desc
    ),
    '[]'::jsonb
  ) into v_homologacoes
  from (
    select distinct on (sf.id)
      sf.id as solicitacao_id,
      dfe.documento_fiscal_id,
      dfe.referencia_externa,
      dfe.autorizado_em,
      coalesce((
        select ev.status = 'ENVIANDO'
        from f.documento_fiscal_evento ev
        where ev.tenant_id = dfe.tenant_id
          and ev.empresa_id = dfe.empresa_id
          and ev.documento_fiscal_id = dfe.documento_fiscal_id
          and ev.tipo = 'CANCELAMENTO'
        order by ev.created_at desc, ev.id desc
        limit 1
      ), false) as cancelamento_em_andamento
    from f.solicitacao_faturamento sf
    join f.solicitacao_item si
      on si.tenant_id = sf.tenant_id
     and si.empresa_id = sf.empresa_id
     and si.solicitacao_id = sf.id
     and si.perfil_operacao_id = v_perfil.id
    join f.documento_fiscal_emissao dfe
      on dfe.tenant_id = sf.tenant_id
     and dfe.empresa_id = sf.empresa_id
     and dfe.solicitacao_id = sf.id
     and dfe.ambiente = 'HOMOLOGACAO'
     and dfe.status = 'AUTORIZADA'
     and dfe.autorizado_em is not null
    where sf.tenant_id = v_scope.tenant_id
      and sf.empresa_id = v_scope.empresa_id
      and sf.status <> 'CANCELADA'
    order by sf.id, dfe.autorizado_em desc, dfe.updated_at desc, dfe.documento_fiscal_id desc
  ) h;

  return jsonb_build_object(
    'tenant_id', v_scope.tenant_id,
    'empresa_id', v_scope.empresa_id,
    'perfil_id', v_perfil.id,
    'homologacoes', v_homologacoes
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_full_permissions_unscoped_20260810(p_tenant_id uuid, p_empresa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'a'
AS $function$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_empresa_papel text;
  v_perm_extra jsonb;
  v_perm_negadas jsonb;
  v_empresa_papel_norm text;
  v_negadas text[];
  base_perms jsonb := '{}'::jsonb;
  extra_perms jsonb := '{}'::jsonb;
  result_perms jsonb;
begin
  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return '{}'::jsonb;
  end if;

  select ut.papel
    into v_tenant_papel
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  limit 1;

  if v_tenant_papel is null then
    return '{}'::jsonb;
  end if;

  select ue.papel, ue.permissoes_extra, ue.permissoes_negadas
    into v_empresa_papel, v_perm_extra, v_perm_negadas
  from a.usuario_empresa ue
  where ue.usuario_id = v_usuario_id
    and ue.empresa_id = p_empresa_id
    and ue.ativo = true
    and ue.deleted_at is null
  limit 1;

  if upper(coalesce(v_empresa_papel, '')) = 'APONTADOR' then
    return '{}'::jsonb;
  end if;

  select jsonb_object_agg(rp.permission, true)
    into base_perms
  from public.role_permissions rp
  where rp.role = a.fn_map_papel_tenant_to_role(v_tenant_papel);

  base_perms := coalesce(base_perms, '{}'::jsonb);

  if v_empresa_papel is null then
    return base_perms;
  end if;

  v_empresa_papel_norm := upper(coalesce(v_empresa_papel, ''));

  extra_perms := extra_perms || jsonb_build_object(
    'modulo_preferencial',
    case v_empresa_papel_norm
      when 'ADMIN' then 'admin'
      when 'FINANCEIRO' then 'financeiro'
      when 'FATURAMENTO' then 'faturamento'
      when 'COORDENACAO' then 'projetos'
      when 'COMPRAS' then 'estoque'
      when 'ALMOXARIFADO' then 'estoque'
      when 'APONTAMENTO_RH' then 'projetos'
      else null
    end
  );

  if v_empresa_papel_norm in ('ADMIN','COORDENACAO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true,
      'os.delete', true,
      'os_itens.write', true,
      'os_gestao.write', true,
      'os_rpcs.execute', true
    );
  elsif v_empresa_papel_norm = 'COMPRAS' then
    extra_perms := extra_perms || jsonb_build_object('os.read', true);
  elsif v_empresa_papel_norm = 'APONTAMENTO_RH' then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true
    );
  end if;

  if v_empresa_papel_norm in ('ADMIN','FINANCEIRO') then
    extra_perms := extra_perms || jsonb_build_object(
      'financeiro.read', true,
      'financeiro.write', true,
      'faturamento.read', true,
      'faturamento.write', true,
      'faturamento.nfe.import_xml', true
    );
  end if;

  if v_empresa_papel_norm = 'FATURAMENTO' then
    extra_perms := extra_perms || jsonb_build_object(
      'faturamento.read', true,
      'faturamento.write', true,
      'faturamento.nfe.import_xml', true,
      'xml_import_faturamento.execute', true
    );
  end if;

  if v_empresa_papel_norm in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('estoque.read', true);
  end if;

  if v_empresa_papel_norm in ('ADMIN','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('estoque.write', true);
  end if;

  if v_empresa_papel_norm in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.read', true);
  end if;

  if v_empresa_papel_norm in ('ADMIN','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.write', true);
  end if;

  if v_empresa_papel_norm in ('ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO','FINANCEIRO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object(
      'xml_import.execute', true,
      'nf_entrada.import', true,
      'cad_fornecedores.write', true,
      'cad_itens.write', true
    );
  end if;

  -- Emissao de nota (NF-e da OV, NF-e da OS e NFS-e) e liberacao de perfil fiscal para producao:
  -- decisao de 06/09/2026 (Gabriel), restrita a quem fatura. DIRETOR nao entra.
  if v_empresa_papel_norm in ('ADMIN', 'FINANCEIRO', 'FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('faturamento.emitir', true);
  end if;

  if v_empresa_papel_norm = 'FATURAMENTO' then
    extra_perms := extra_perms || jsonb_build_object(
      'estoque_custos.cost_read', true,
      'fiscal_nf.read', true,
      'fiscal_nf.write', true,
      'fiscal_nf.delete', true,
      'fiscal_itens.write', true,
      'apontamentos.read', true,
      'apontamentos.write', true,
      'apontamentos.delete', true,
      'apontamentos.config', true,
      'cad_clientes.write', true,
      'compras.read', true,
      'compras.write', true,
      'compras.approve', true,
      'compras.receive', true
    );
  end if;

  if v_perm_extra is not null then
    extra_perms := extra_perms || v_perm_extra;
  end if;

  result_perms := base_perms || extra_perms;

  if v_perm_negadas is not null then
    select array_agg(key)
      into v_negadas
    from jsonb_object_keys(v_perm_negadas) as key;

    if v_negadas is not null then
      result_perms := result_perms - v_negadas;
    end if;
  end if;

  return coalesce(result_perms, '{}'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.can_unscoped_20260810(p_resource text, p_action text, p_tenant_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'a', 'c'
AS $function$
declare
  v_auth_user_id uuid;
  v_usuario_id uuid;
  v_papel_tenant text;
  v_papel_empresa text;
  v_empresa_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    return false;
  end if;

  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = v_auth_user_id
    and u.ativo = true
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return false;
  end if;

  select ut.papel
    into v_papel_tenant
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  order by ut.updated_at desc nulls last, ut.created_at desc nulls last
  limit 1;

  if v_papel_tenant is null then
    return false;
  end if;

  v_empresa_id := public.current_empresa_id();

  if v_empresa_id is not null then
    select upper(coalesce(ue.papel, ''))
      into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

  if v_papel_empresa = 'APONTADOR' then
    return false;
  end if;

  if v_papel_tenant in ('ADMIN','DIRETOR','OWNER') then
    return true;
  end if;

  v_empresa_id := public.current_empresa_id();

  if v_empresa_id is not null then
    select ue.papel
      into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

  v_papel_empresa := upper(coalesce(v_papel_empresa, ''));

  if v_papel_empresa = 'FATURAMENTO' then
    if p_resource = 'admin' and p_action = 'manage_users' then
      return false;
    end if;

    if (p_resource, p_action) in (
      values
        ('os', 'read'),
        ('os', 'write'),
        ('os', 'delete'),
        ('os_itens', 'write'),
        ('os_gestao', 'write'),
        ('os_rpcs', 'execute'),
        ('estoque', 'read'),
        ('estoque', 'write'),
        ('estoque_custos', 'cost_read'),
        ('fiscal_nf', 'read'),
        ('fiscal_nf', 'write'),
        ('fiscal_nf', 'delete'),
        ('fiscal_itens', 'write'),
        ('xml_import', 'execute'),
        ('xml_import_faturamento', 'execute'),
        ('nf_entrada', 'import'),
        ('faturamento', 'read'),
        ('faturamento', 'write'),
        ('faturamento', 'nfe.import_xml'),
        ('imobilizado', 'read'),
        ('imobilizado', 'write'),
        ('apontamentos', 'read'),
        ('apontamentos', 'write'),
        ('apontamentos', 'delete'),
        ('apontamentos', 'config'),
        ('cad_clientes', 'write'),
        ('cad_fornecedores', 'write'),
        ('cad_itens', 'write'),
        ('compras', 'read'),
        ('compras', 'write'),
        ('compras', 'approve'),
        ('compras', 'receive')
    ) then
      return true;
    end if;
  end if;

  if p_resource = 'faturamento' and p_action = 'emitir' then
    return v_papel_empresa in ('ADMIN', 'FINANCEIRO', 'FATURAMENTO');
  end if;

  if p_resource = 'os' and p_action = 'read' and v_papel_empresa = 'COMPRAS' then
    return true;
  end if;

  if p_resource = 'xml_import' and p_action = 'execute' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'xml_import_faturamento' and p_action = 'execute' then
    if v_papel_empresa in ('FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'nf_entrada' and p_action = 'import' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'faturamento' and p_action in ('read', 'write', 'nfe.import_xml') then
    if v_papel_empresa in ('FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'financeiro' and p_action in ('write', 'config') then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'estoque' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'estoque' and p_action = 'read' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'cad_itens' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'read' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'write' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'approve' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'receive' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then
      return true;
    end if;
  end if;

  if p_resource = 'admin' and p_action = 'manage_users' then
    return false;
  end if;

  return false;
end;
$function$;
