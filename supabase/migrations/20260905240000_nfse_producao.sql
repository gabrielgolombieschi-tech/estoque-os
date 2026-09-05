-- NFS-e Padrao Nacional: caminho de PRODUCAO (05/09/2026, liberado pelo
-- responsavel no painel da Focus para uma NFS-e real na OS 319, cancelada em
-- seguida). Matriz fiscal de 9 NFS-e reais de agosto/2026 fornecida pelo
-- responsavel: a retencao e atributo do servico (perfil), nao do tomador;
-- DPS e NFS-e sao sequencias independentes; IBS/CBS = (servico - ISS) x
-- 0,10% UF / 0,90% CBS; cIndOp por perfil; totais aproximados por tabela.
--
-- O que este arquivo faz:
--   1. c.empresa_fiscal.proximo_numero_dps_producao (contador proprio de
--      producao) e f.fn_proximo_numero_dps(empresa, ambiente).
--   2. f.perfil_operacao: cIndOp e percentuais aproximados (Lei 12.741).
--   3. f.fn_perfil_operacao_nfse_revisar e f.fn_perfil_operacao_nfse_liberar_producao
--      (mesma disciplina da NF-e: revisao auditada -> homologacao com o
--      perfil -> liberacao amarrada a essa homologacao).
--   4. f.fn_os_nfse_conferir_homologacao: usa o PERFIL revisado quando
--      existe (tributacao_fonte = PERFIL); sem revisao continua na fixture.
--      Pedido de compra pode ser limpo explicitamente ('' = sem pedido).
--   5. f.fn_nfse_preparar_documento_solicitacao(solicitacao, ambiente):
--      PRODUCAO exige homologacao AUTORIZADA da mesma solicitacao e passa
--      pelo trigger de producao (fn_nfe_producao_pronta -> fn_nfse_producao_pronta).
--   6. f.fn_nfse_emissao_claimar: claim duravel para os dois ambientes.
--   7. f.fn_nfse_renumerar_dps usa o contador do ambiente da emissao.
--   8. Prazo de cancelamento provisorio (24 h) para a NFS-e real de teste.
--
-- Baselines (05/09/2026): fn_proximo_numero_dps(uuid), fn_nfse_preparar_documento_solicitacao(uuid),
-- fn_os_nfse_conferir_homologacao(uuid,jsonb), fn_nfse_renumerar_dps(uuid) das
-- migrations 20260905190000/200000. Nenhuma funcao de NF-e alterada.

-- ---------------------------------------------------------------------------
-- 1. Contador de DPS por ambiente
-- ---------------------------------------------------------------------------
alter table c.empresa_fiscal add column if not exists proximo_numero_dps_producao bigint not null default 1;
alter table c.empresa_fiscal drop constraint if exists empresa_fiscal_proximo_numero_dps_prod_ck;
alter table c.empresa_fiscal add constraint empresa_fiscal_proximo_numero_dps_prod_ck check (proximo_numero_dps_producao >= 1);
comment on column c.empresa_fiscal.proximo_numero_dps_producao is 'Proximo numero de DPS em PRODUCAO (serie_dps). Homologacao usa proximo_numero_dps. Sequencias independentes do numero da NFS-e.';

drop function if exists f.fn_proximo_numero_dps(uuid);
create function f.fn_proximo_numero_dps(p_empresa_id uuid, p_ambiente text default 'HOMOLOGACAO')
returns table (serie smallint, numero bigint)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_fiscal c.empresa_fiscal%rowtype;
begin
  if current_user not in ('postgres', 'service_role') and session_user <> 'postgres' then
    raise exception using errcode = '42501', message = 'A numeracao da DPS e reservada ao pipeline fiscal.';
  end if;
  if p_ambiente not in ('HOMOLOGACAO', 'PRODUCAO') then
    raise exception using errcode = '22023', message = 'Ambiente invalido para numerar a DPS.';
  end if;
  select ef.* into v_fiscal from c.empresa_fiscal ef
  where ef.empresa_id = p_empresa_id and ef.deleted_at is null
  order by ef.updated_at desc limit 1
  for update;
  if not found then raise exception using errcode = '22023', message = 'Empresa sem cadastro fiscal; nao ha serie de DPS.'; end if;
  if v_fiscal.serie_dps is null then raise exception using errcode = '22023', message = 'Serie da DPS nao configurada em c.empresa_fiscal.serie_dps.'; end if;
  serie := v_fiscal.serie_dps;
  if p_ambiente = 'PRODUCAO' then
    numero := v_fiscal.proximo_numero_dps_producao;
    update c.empresa_fiscal set proximo_numero_dps_producao = v_fiscal.proximo_numero_dps_producao + 1, updated_at = now() where id = v_fiscal.id;
  else
    numero := v_fiscal.proximo_numero_dps;
    update c.empresa_fiscal set proximo_numero_dps = v_fiscal.proximo_numero_dps + 1, updated_at = now() where id = v_fiscal.id;
  end if;
  return next;
end;
$$;
revoke all on function f.fn_proximo_numero_dps(uuid, text) from public;
grant execute on function f.fn_proximo_numero_dps(uuid, text) to service_role;

-- Prazo provisorio de cancelamento (24 h) para a NFS-e real de teste; o
-- contador ainda nao confirmou a norma (pergunta 18).
update c.empresa_fiscal ef set prazo_cancelamento_nfse_horas = coalesce(ef.prazo_cancelamento_nfse_horas, 24), updated_at = now()
from c.empresa e
where e.id = ef.empresa_id and ef.deleted_at is null
  and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') = '13671448000189';

-- ---------------------------------------------------------------------------
-- 2. Perfil: cIndOp e totais aproximados
-- ---------------------------------------------------------------------------
alter table f.perfil_operacao
  add column if not exists codigo_indicador_operacao text,
  add column if not exists tributos_aprox_federal_pct numeric(5,2),
  add column if not exists tributos_aprox_municipal_pct numeric(5,2);
alter table f.perfil_operacao drop constraint if exists perfil_operacao_nfse_extras_ck;
alter table f.perfil_operacao add constraint perfil_operacao_nfse_extras_ck check (
  (codigo_indicador_operacao is null or codigo_indicador_operacao ~ '^[0-9]{6}$')
  and (tributos_aprox_federal_pct is null or (tributos_aprox_federal_pct >= 0 and tributos_aprox_federal_pct <= 100))
  and (tributos_aprox_municipal_pct is null or (tributos_aprox_municipal_pct >= 0 and tributos_aprox_municipal_pct <= 100))
);
comment on column f.perfil_operacao.codigo_indicador_operacao is 'cIndOp do grupo IBS/CBS da NFS-e (6 digitos). Observado: 050103 (14.01) e 040101 (07.02).';
comment on column f.perfil_operacao.tributos_aprox_federal_pct is 'Percentual aproximado de tributos federais (Lei 12.741) para a NFS-e; 13,45% em todas as notas de agosto/2026.';
comment on column f.perfil_operacao.tributos_aprox_municipal_pct is 'Percentual aproximado de tributos municipais (Lei 12.741) por servico: 4,69 (14.xx), 3,64 (17.09), 2,11 (07.02).';

-- ---------------------------------------------------------------------------
-- 3. Revisao e liberacao do perfil de servico
-- ---------------------------------------------------------------------------
create or replace function f.fn_perfil_operacao_nfse_revisar(p_perfil_id uuid, p_campos jsonb, p_justificativa text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  c jsonb := coalesce(p_campos, '{}'::jsonb);
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '') in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao de escrita para revisar perfis fiscais.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then
    raise exception using errcode = '22023', message = 'A justificativa da revisao deve ter entre 15 e 1000 caracteres.';
  end if;
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = p_perfil_id and po.tenant_id = v_scope.tenant_id and po.empresa_id = v_scope.empresa_id and po.modelo = 'NFSE'
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Perfil de servico nao encontrado no tenant e empresa ativos.'; end if;
  if coalesce(c->>'codigo_tributacao_nacional', '') !~ '^[0-9]{6}$' then raise exception using errcode = '22023', message = 'codigo_tributacao_nacional deve ter 6 digitos.'; end if;
  if nullif(c->>'codigo_nbs', '') is not null and (c->>'codigo_nbs') !~ '^[0-9]{9}$' then raise exception using errcode = '22023', message = 'codigo_nbs deve ter 9 digitos.'; end if;
  if coalesce(c->>'local_prestacao_regra', '') not in ('SEDE', 'CLIENTE') then raise exception using errcode = '22023', message = 'local_prestacao_regra deve ser SEDE ou CLIENTE.'; end if;
  if coalesce((c->>'tributacao_iss')::int, 0) not in (1, 2, 3, 4) then raise exception using errcode = '22023', message = 'tributacao_iss deve ser 1 a 4.'; end if;
  if (c->>'aliquota_iss')::numeric is null or (c->>'aliquota_iss')::numeric < 0 or (c->>'aliquota_iss')::numeric > 100 then raise exception using errcode = '22023', message = 'aliquota_iss obrigatoria (0 a 100).'; end if;
  if coalesce(c->>'iss_retido_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')
     or coalesce(c->>'retencao_pcc_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')
     or coalesce(c->>'retencao_irrf_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')
     or coalesce(c->>'retencao_inss_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR') then
    raise exception using errcode = '22023', message = 'Regras de retencao (ISS, PCC, IRRF, INSS) devem ser NUNCA, SEMPRE ou POR_TOMADOR.';
  end if;
  if coalesce(c->>'cst_pis', '') !~ '^[0-9]{2}$' or coalesce(c->>'cst_cofins', '') !~ '^[0-9]{2}$' then raise exception using errcode = '22023', message = 'CST de PIS e COFINS devem ter 2 digitos.'; end if;
  if coalesce(c->>'cst_ibs_cbs', '') !~ '^[0-9]{3}$' or coalesce(c->>'cclass_trib', '') !~ '^[0-9]{6}$' or left(c->>'cclass_trib', 3) <> (c->>'cst_ibs_cbs') then
    raise exception using errcode = '22023', message = 'CST IBS/CBS (3 digitos) e cClassTrib (6 digitos, mesmo prefixo) obrigatorios.';
  end if;
  if coalesce(c->>'codigo_indicador_operacao', '') !~ '^[0-9]{6}$' then raise exception using errcode = '22023', message = 'codigo_indicador_operacao (cIndOp) deve ter 6 digitos.'; end if;
  if (c->>'ibs_uf_aliquota')::numeric is null or (c->>'ibs_mun_aliquota')::numeric is null or (c->>'cbs_aliquota')::numeric is null then
    raise exception using errcode = '22023', message = 'Aliquotas IBS UF, IBS municipal e CBS obrigatorias.';
  end if;

  update f.perfil_operacao po
  set codigo_tributacao_nacional = c->>'codigo_tributacao_nacional',
      codigo_tributacao_municipal = nullif(c->>'codigo_tributacao_municipal', ''),
      codigo_nbs = nullif(c->>'codigo_nbs', ''),
      descricao_servico_padrao = nullif(c->>'descricao_servico_padrao', ''),
      local_prestacao_regra = c->>'local_prestacao_regra',
      tributacao_iss = (c->>'tributacao_iss')::smallint,
      aliquota_iss = (c->>'aliquota_iss')::numeric,
      iss_retido_regra = c->>'iss_retido_regra',
      retencao_pcc_regra = c->>'retencao_pcc_regra', aliquota_pcc = nullif(c->>'aliquota_pcc', '')::numeric,
      retencao_irrf_regra = c->>'retencao_irrf_regra', aliquota_irrf = nullif(c->>'aliquota_irrf', '')::numeric,
      retencao_inss_regra = c->>'retencao_inss_regra', aliquota_inss = nullif(c->>'aliquota_inss', '')::numeric,
      permite_deducao_material = coalesce((c->>'permite_deducao_material')::boolean, false),
      texto_complementar = nullif(c->>'texto_complementar', ''),
      cst_pis = c->>'cst_pis', cst_cofins = c->>'cst_cofins',
      aliquota_pis = nullif(c->>'aliquota_pis', '')::numeric, aliquota_cofins = nullif(c->>'aliquota_cofins', '')::numeric,
      consumidor_final = coalesce((c->>'consumidor_final')::smallint, 0),
      cst_ibs_cbs = c->>'cst_ibs_cbs', cclass_trib = c->>'cclass_trib',
      cclass_trib_versao = coalesce(nullif(c->>'cclass_trib_versao', ''), po.cclass_trib_versao, 'NFS-e ago/2026'),
      ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', (c->>'ibs_uf_aliquota')::numeric, 'ibs_mun_aliquota', (c->>'ibs_mun_aliquota')::numeric, 'cbs_aliquota', (c->>'cbs_aliquota')::numeric),
      codigo_indicador_operacao = c->>'codigo_indicador_operacao',
      tributos_aprox_federal_pct = nullif(c->>'tributos_aprox_federal_pct', '')::numeric,
      tributos_aprox_municipal_pct = nullif(c->>'tributos_aprox_municipal_pct', '')::numeric,
      cbenef_aplicacao = 'SEM_BENEFICIO', cbenef = null,
      revisao_fiscal_em = now(), revisao_fiscal_por = v_scope.usuario_id, revisao_fiscal_justificativa = v_justificativa,
      habilitado_producao = false, producao_decidida_em = null, producao_decidida_por = null,
      producao_decisao_justificativa = null, producao_homologacao_solicitacao_id = null, producao_homologacao_documento_id = null
  where po.id = v_perfil.id
  returning po.* into v_depois;

  insert into f.perfil_operacao_revisao_evento (tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois, justificativa, criado_por, created_at)
  values (v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'REVISAO', to_jsonb(v_perfil), to_jsonb(v_depois), v_justificativa, v_scope.usuario_id, v_depois.revisao_fiscal_em);
  return jsonb_build_object('perfil_id', v_perfil.id, 'revisao_fiscal_em', v_depois.revisao_fiscal_em, 'habilitado_producao', false);
end;
$$;
revoke all on function f.fn_perfil_operacao_nfse_revisar(uuid, jsonb, text) from public;
grant execute on function f.fn_perfil_operacao_nfse_revisar(uuid, jsonb, text) to authenticated, service_role;

create or replace function f.fn_perfil_operacao_nfse_liberar_producao(p_perfil_id uuid, p_solicitacao_id uuid, p_justificativa text, p_confirmacao boolean)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_hom f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '') in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao de escrita para liberar perfis fiscais.';
  end if;
  if not coalesce(p_confirmacao, false) then raise exception using errcode = '22023', message = 'Confirme explicitamente a liberacao para producao.'; end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then raise exception using errcode = '22023', message = 'A justificativa da liberacao deve ter entre 15 e 1000 caracteres.'; end if;
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = p_perfil_id and po.tenant_id = v_scope.tenant_id and po.empresa_id = v_scope.empresa_id and po.modelo = 'NFSE'
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Perfil de servico nao encontrado.'; end if;
  if v_perfil.revisao_fiscal_em is null or v_perfil.codigo_tributacao_nacional is null or v_perfil.aliquota_iss is null or v_perfil.iss_retido_regra is null
     or v_perfil.cst_ibs_cbs is null or v_perfil.cclass_trib is null or v_perfil.codigo_indicador_operacao is null then
    raise exception using errcode = '22023', message = 'O perfil de servico precisa ser revisado (codigo, ISS, retencoes, IBS/CBS, cIndOp) antes da liberacao.';
  end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' then raise exception using errcode = '22023', message = 'Perfil bloqueado nao pode ser liberado.'; end if;
  if not exists (
    select 1 from f.perfil_operacao_revisao_evento re
    where re.perfil_operacao_id = v_perfil.id and re.tipo = 'REVISAO' and re.created_at = v_perfil.revisao_fiscal_em and re.justificativa = v_perfil.revisao_fiscal_justificativa
  ) then
    raise exception using errcode = '55000', message = 'A ultima revisao do perfil nao possui evento de auditoria equivalente.';
  end if;
  select sf.* into v_sf from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id and sf.tenant_id = v_scope.tenant_id and sf.empresa_id = v_scope.empresa_id and sf.status <> 'CANCELADA';
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao ativa nao encontrada.'; end if;
  if v_sf.perfil_operacao_id is distinct from v_perfil.id then raise exception using errcode = '22023', message = 'A solicitacao nao usa este perfil de servico.'; end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and (si.modelo <> 'NFSE' or si.tributacao_fonte is distinct from 'PERFIL' or si.perfil_operacao_id is distinct from v_perfil.id
              or si.codigo_tributacao_nacional is distinct from v_perfil.codigo_tributacao_nacional or si.cst_ibs_cbs is distinct from v_perfil.cst_ibs_cbs or si.cclass_trib is distinct from v_perfil.cclass_trib)) then
    raise exception using errcode = '22023', message = 'As linhas da solicitacao homologada precisam ter sido conferidas com este perfil (tributacao_fonte = PERFIL) e coincidir com ele.';
  end if;
  select dfe.* into v_hom from f.documento_fiscal_emissao dfe
  where dfe.solicitacao_id = v_sf.id and dfe.ambiente = 'HOMOLOGACAO' and dfe.modelo = 'NFSE' and dfe.status = 'AUTORIZADA'
    and dfe.autorizado_em is not null and dfe.autorizado_em > v_perfil.revisao_fiscal_em
  order by dfe.autorizado_em desc limit 1;
  if not found then raise exception using errcode = '22023', message = 'A solicitacao precisa de NFS-e AUTORIZADA em homologacao depois da ultima revisao do perfil.'; end if;
  if v_hom.payload_enviado->>'codigo_tributacao_nacional_iss' is distinct from v_perfil.codigo_tributacao_nacional
     or v_hom.payload_enviado->>'ibs_cbs_situacao_tributaria' is distinct from v_perfil.cst_ibs_cbs
     or v_hom.payload_enviado->>'ibs_cbs_classificacao_tributaria' is distinct from v_perfil.cclass_trib
     or v_hom.payload_enviado->>'codigo_indicador_operacao' is distinct from v_perfil.codigo_indicador_operacao then
    raise exception using errcode = '22023', message = 'O payload autorizado em homologacao nao coincide com o perfil (codigo, IBS/CBS, cIndOp).';
  end if;

  update f.perfil_operacao po
  set habilitado_producao = true, producao_decidida_em = now(), producao_decidida_por = v_scope.usuario_id,
      producao_decisao_justificativa = v_justificativa, producao_homologacao_solicitacao_id = v_sf.id, producao_homologacao_documento_id = v_hom.documento_fiscal_id
  where po.id = v_perfil.id
  returning po.* into v_depois;
  insert into f.perfil_operacao_revisao_evento (tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois, homologacao_solicitacao_id, homologacao_documento_id, justificativa, criado_por, created_at)
  values (v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'LIBERACAO', to_jsonb(v_perfil), to_jsonb(v_depois), v_sf.id, v_hom.documento_fiscal_id, v_justificativa, v_scope.usuario_id, v_depois.producao_decidida_em);
  return jsonb_build_object('perfil_id', v_perfil.id, 'solicitacao_id', v_sf.id, 'homologacao_documento_fiscal_id', v_hom.documento_fiscal_id, 'habilitado_producao', true);
end;
$$;
revoke all on function f.fn_perfil_operacao_nfse_liberar_producao(uuid, uuid, text, boolean) from public;
grant execute on function f.fn_perfil_operacao_nfse_liberar_producao(uuid, uuid, text, boolean) to authenticated, service_role;

-- fn_nfse_producao_pronta: o evento LIBERACAO e gravado com created_at = producao_decidida_em (mesma disciplina da NF-e).
create or replace function f.fn_nfse_producao_pronta(p_solicitacao_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_perfil f.perfil_operacao%rowtype;
  v_hom_doc uuid;
  v_hom_autorizado_em timestamptz;
  v_certificado date;
begin
  select * into v_sf from f.solicitacao_faturamento where id = p_solicitacao_id;
  if not found then return jsonb_build_object('pronta', false, 'motivo', 'Solicitacao nao encontrada.'); end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;
  if v_sf.status = 'CANCELADA' then return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao esta cancelada.'); end if;
  select dfe.documento_fiscal_id, dfe.autorizado_em into v_hom_doc, v_hom_autorizado_em
  from f.documento_fiscal_emissao dfe
  where dfe.solicitacao_id = v_sf.id and dfe.ambiente = 'HOMOLOGACAO' and dfe.status = 'AUTORIZADA' and dfe.modelo = 'NFSE'
  order by dfe.autorizado_em desc nulls last limit 1;
  if v_hom_doc is null then return jsonb_build_object('pronta', false, 'motivo', 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.'); end if;
  select ef.certificado_validade_em into v_certificado from c.empresa_fiscal ef where ef.empresa_id = v_sf.empresa_id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  if v_certificado is null then return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.'); end if;
  if v_certificado < current_date then return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.'); end if;
  if v_sf.snapshot_cadastro_em is null or jsonb_typeof(v_sf.operacao_snapshot->'servico') is distinct from 'object' then
    return jsonb_build_object('pronta', false, 'motivo', 'A conferencia da NFS-e ainda nao foi salva.');
  end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and (si.tributacao_fonte is distinct from 'PERFIL' or si.perfil_operacao_id is null)) then
    return jsonb_build_object('pronta', false, 'motivo', 'Linhas de servico com valores da fixture de homologacao; producao exige perfil de servico revisado e liberado.');
  end if;
  select po.* into v_perfil from f.perfil_operacao po where po.id = v_sf.perfil_operacao_id;
  if not found or v_perfil.modelo <> 'NFSE' then return jsonb_build_object('pronta', false, 'motivo', 'Perfil de servico nao encontrado.'); end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' or not v_perfil.habilitado_producao
     or v_perfil.vigencia_inicio > current_date or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date)
     or v_perfil.revisao_fiscal_em is null or v_perfil.producao_decidida_em is null
     or v_perfil.producao_homologacao_solicitacao_id is distinct from v_sf.id
     or v_perfil.producao_homologacao_documento_id is distinct from v_hom_doc
     or v_hom_autorizado_em <= v_perfil.revisao_fiscal_em
     or v_perfil.codigo_tributacao_nacional is null or v_perfil.aliquota_iss is null or v_perfil.iss_retido_regra is null
     or v_perfil.cst_ibs_cbs is null or v_perfil.cclass_trib is null or v_perfil.codigo_indicador_operacao is null
     or not exists (
       select 1 from f.perfil_operacao_revisao_evento le
       where le.perfil_operacao_id = v_perfil.id and le.tipo = 'LIBERACAO'
         and le.homologacao_solicitacao_id = v_sf.id and le.homologacao_documento_id = v_hom_doc
         and le.depois->>'habilitado_producao' = 'true'
     ) then
    return jsonb_build_object('pronta', false, 'motivo', 'Perfil de servico precisa estar liberado para esta homologacao (revisao + liberacao auditadas).');
  end if;
  return jsonb_build_object('pronta', true, 'tenant_id', v_sf.tenant_id, 'empresa_id', v_sf.empresa_id,
    'homologacao_documento_fiscal_id', v_hom_doc, 'perfil_operacao_id', v_perfil.id, 'perfil_operacao_ids', jsonb_build_array(v_perfil.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Conferencia: perfil revisado ou fixture
-- ---------------------------------------------------------------------------
create or replace function f.fn_os_nfse_conferir_homologacao(p_solicitacao_id uuid, p_operacao jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_perfil f.perfil_operacao%rowtype;
  v_fx f.tributacao_provisoria_nfse_homologacao%rowtype;
  v_cliente public.clientes%rowtype;
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_item record;
  v_os public.ordens_servico%rowtype;
  v_pend jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
  v_rota_cliente text;
  v_rota_perfil text := '/faturamento/perfis';
  v_documento text;
  v_municipio text;
  v_competencia date;
  v_iss_retido boolean; v_pcc boolean; v_irrf boolean; v_inss boolean;
  v_iss_override boolean; v_pcc_override boolean; v_irrf_override boolean; v_inss_override boolean;
  v_justificativa text;
  v_bruto numeric(15,2) := 0; v_valor_iss numeric(15,2) := 0; v_v_irrf numeric(15,2) := 0; v_v_pcc numeric(15,2) := 0; v_v_inss numeric(15,2) := 0;
  v_liquido numeric(15,2);
  v_retencoes jsonb := '[]'::jsonb;
  v_parcelas jsonb;
  v_pag_forma text; v_pag_indicador smallint;
  v_saldo record; v_reserva_propria numeric(15,2); v_reserva_substituida numeric(15,2); v_os_total record;
  v_linhas_desc jsonb := '[]'::jsonb;
  v_os_numeros text[] := array[]::text[];
  v_discriminacao text; v_texto_retencao text;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_emissao_status text;
  v_linhas integer := 0;
  v_consumidor_final smallint;
  v_pedido text; v_pedido_item text; v_observacao text;
  v_tem_federal boolean;
  -- Fonte fiscal resolvida (PERFIL revisado ou FIXTURE_HOMOLOGACAO).
  v_fonte text;
  f_ctrib text; f_ctrib_mun text; f_nbs text; f_desc text; f_local text; f_trib_iss smallint; f_aliq_iss numeric;
  f_iss_regra text; f_pcc_regra text; f_irrf_regra text; f_inss_regra text; f_aliq_pcc numeric; f_aliq_irrf numeric; f_aliq_inss numeric;
  f_cst_pis text; f_cst_cofins text; f_aliq_pis numeric; f_aliq_cofins numeric; f_cst_ibs text; f_cclass text;
  f_ibs_uf numeric; f_ibs_mun numeric; f_cbs numeric; f_cindop text; f_pct_fed numeric; f_pct_mun numeric; f_texto_sem text; f_item text;
begin
  select * into v_sf from f.solicitacao_faturamento where id = p_solicitacao_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NFS-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s nao pode ser conferida.', v_sf.status);
  end if;
  select e.status into v_emissao_status from f.documento_fiscal_emissao e
  where e.tenant_id = v_sf.tenant_id and e.empresa_id = v_sf.empresa_id and e.solicitacao_id = v_sf.id order by e.created_at desc limit 1;
  if v_emissao_status is not null and v_emissao_status not in ('RASCUNHO') then
    raise exception using errcode = '55000', message = format('A NFS-e desta solicitacao ja esta em %s; a conferencia nao pode mais ser alterada. Para refazer, descarte e crie outra.', v_emissao_status);
  end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and si.modelo <> 'NFSE') then
    raise exception using errcode = '22023', message = 'Esta conferencia e exclusiva de linhas de servico (NFS-e).';
  end if;
  v_rota_cliente := '/clientes/cadastro-fiscal?cliente_id=' || coalesce(v_sf.cliente_id::text, '');

  -- Perfil escolhido; valores do perfil quando revisado, senao da fixture provisoria.
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = coalesce(nullif(p_operacao->>'perfil_operacao_id', '')::uuid, v_sf.perfil_operacao_id)
    and po.tenant_id = v_sf.tenant_id and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null);
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','campo','perfil_operacao_id','mensagem','Escolha o perfil de servico da NFS-e.','rota',v_rota_perfil));
  else
    if v_perfil.modelo <> 'NFSE' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','modelo','mensagem',format('Perfil %s nao e de servico.', v_perfil.codigo),'rota',v_rota_perfil)); end if;
    if v_perfil.faixa_automacao = 'BLOQUEADO' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','faixa_automacao','mensagem',format('Perfil %s bloqueado: %s', v_perfil.codigo, coalesce(v_perfil.justificativa_faixa, 'aguarda o contador.')),'rota',v_rota_perfil)); end if;
    if v_perfil.vigencia_inicio > current_date or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date) then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','vigencia','mensagem',format('Perfil %s fora da vigencia.', v_perfil.codigo),'rota',v_rota_perfil)); end if;
    if v_perfil.revisao_fiscal_em is not null and v_perfil.codigo_tributacao_nacional is not null and v_perfil.aliquota_iss is not null and v_perfil.iss_retido_regra is not null then
      v_fonte := 'PERFIL';
      f_item := v_perfil.item_servico; f_ctrib := v_perfil.codigo_tributacao_nacional; f_ctrib_mun := v_perfil.codigo_tributacao_municipal; f_nbs := v_perfil.codigo_nbs;
      f_desc := v_perfil.descricao_servico_padrao; f_local := coalesce(v_perfil.local_prestacao_regra, 'SEDE'); f_trib_iss := coalesce(v_perfil.tributacao_iss, 1); f_aliq_iss := v_perfil.aliquota_iss;
      f_iss_regra := v_perfil.iss_retido_regra; f_pcc_regra := coalesce(v_perfil.retencao_pcc_regra, 'NUNCA'); f_irrf_regra := coalesce(v_perfil.retencao_irrf_regra, 'NUNCA'); f_inss_regra := coalesce(v_perfil.retencao_inss_regra, 'NUNCA');
      f_aliq_pcc := v_perfil.aliquota_pcc; f_aliq_irrf := v_perfil.aliquota_irrf; f_aliq_inss := v_perfil.aliquota_inss;
      f_cst_pis := v_perfil.cst_pis; f_cst_cofins := v_perfil.cst_cofins; f_aliq_pis := v_perfil.aliquota_pis; f_aliq_cofins := v_perfil.aliquota_cofins;
      f_cst_ibs := v_perfil.cst_ibs_cbs; f_cclass := v_perfil.cclass_trib;
      f_ibs_uf := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'); f_ibs_mun := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'); f_cbs := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota');
      f_cindop := v_perfil.codigo_indicador_operacao; f_pct_fed := v_perfil.tributos_aprox_federal_pct; f_pct_mun := v_perfil.tributos_aprox_municipal_pct; f_texto_sem := v_perfil.texto_complementar;
      v_consumidor_final := coalesce(v_perfil.consumidor_final, 0);
    else
      select t.* into v_fx from f.tributacao_provisoria_nfse_homologacao t
      where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.item_servico = v_perfil.item_servico and t.ativo;
      if not found then
        v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','item_servico','mensagem',format('Perfil %s sem revisao fiscal e sem fixture provisoria de homologacao.', coalesce(v_perfil.item_servico, '?')),'rota',v_rota_perfil));
      elsif v_fx.aliquota_iss is null then
        v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','aliquota_iss','mensagem',format('Fixture do item %s sem aliquota de ISS: %s', v_fx.item_servico, v_fx.pendencia_contador),'rota',v_rota_perfil));
      else
        v_fonte := 'FIXTURE_HOMOLOGACAO';
        f_item := v_fx.item_servico; f_ctrib := v_fx.codigo_tributacao_nacional; f_ctrib_mun := v_fx.codigo_tributacao_municipal; f_nbs := v_fx.codigo_nbs;
        f_desc := v_fx.descricao_servico_padrao; f_local := v_fx.local_prestacao_regra; f_trib_iss := v_fx.tributacao_iss; f_aliq_iss := v_fx.aliquota_iss;
        f_iss_regra := v_fx.iss_retido_regra; f_pcc_regra := v_fx.retencao_pcc_regra; f_irrf_regra := v_fx.retencao_irrf_regra; f_inss_regra := v_fx.retencao_inss_regra;
        f_aliq_pcc := v_fx.aliquota_pcc; f_aliq_irrf := v_fx.aliquota_irrf; f_aliq_inss := v_fx.aliquota_inss;
        f_cst_pis := v_fx.cst_pis_cofins; f_cst_cofins := v_fx.cst_pis_cofins; f_aliq_pis := v_fx.aliquota_pis; f_aliq_cofins := v_fx.aliquota_cofins;
        f_cst_ibs := v_fx.cst_ibs_cbs; f_cclass := v_fx.cclass_trib; f_ibs_uf := v_fx.ibs_uf_aliquota; f_ibs_mun := v_fx.ibs_mun_aliquota; f_cbs := v_fx.cbs_aliquota;
        f_cindop := case when v_fx.item_servico = '07.02' then '040101' else '050103' end; f_pct_fed := null; f_pct_mun := null; f_texto_sem := v_fx.texto_sem_retencao;
        v_consumidor_final := coalesce(v_perfil.consumidor_final, v_fx.consumidor_final, 0);
      end if;
    end if;
  end if;

  -- Emitente (prestador).
  select e.* into v_empresa from c.empresa e where e.tenant_id = v_sf.tenant_id and e.id = v_sf.empresa_id and e.deleted_at is null and e.ativo;
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','empresa','mensagem','Empresa ativa nao encontrada.','rota','/configuracoes'));
  else
    select ef.* into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
    select ee.* into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14 then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','cnpj','mensagem','CNPJ do prestador invalido.','rota','/configuracoes')); end if;
    if v_fiscal.id is null or v_fiscal.serie_dps is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','serie_dps','mensagem','Serie da DPS nao configurada no cadastro fiscal da empresa.','rota','/configuracoes')); end if;
    if v_fiscal.id is null or v_fiscal.codigo_opcao_simples_nacional is null or v_fiscal.regime_especial_tributacao is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_opcao_simples_nacional','mensagem','Opcao pelo Simples e regime especial nao informados no cadastro fiscal da empresa.','rota','/configuracoes')); end if;
    if v_endereco.id is null or regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_municipio_ibge','mensagem','Codigo IBGE do endereco fiscal do prestador deve ter 7 digitos.','rota','/configuracoes')); end if;
  end if;

  -- Tomador.
  select c.* into v_cliente from public.clientes c where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id and c.ativo is true;
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_sf.cliente_id,'campo','cliente','mensagem','Tomador ativo nao encontrado nesta empresa.','rota',v_rota_cliente));
  else
    v_documento := regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g');
    if not ((length(v_documento) = 14 and public.cnpj_valido(v_documento)) or (length(v_documento) = 11 and public.cpf_valido(v_documento))) then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','CNPJ/CPF do tomador invalido.','rota',v_rota_cliente)); end if;
    if exists (select 1 from public.empresas e where e.tenant_id = v_sf.tenant_id and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') <> '' and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') = v_documento) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','OS interna (tomador e uma empresa do grupo) nao emite NFS-e por este fluxo.'));
    end if;
    if nullif(btrim(v_cliente.razao_social), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','razao_social','mensagem','Razao social do tomador nao informada.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.logradouro), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','logradouro','mensagem','Logradouro do tomador nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.numero_endereco), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','numero_endereco','mensagem','Numero do endereco do tomador nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.bairro), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','bairro','mensagem','Bairro do tomador nao informado.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cep','mensagem','CEP do tomador deve ter 8 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','codigo_ibge_municipio','mensagem','Codigo IBGE do tomador deve ter 7 digitos.','rota',v_rota_cliente)); end if;
    -- IM do tomador de Joinville: as NFS-e reais nunca a enviam; passa a aviso (matriz de 05/09/2026).
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') = '4209102' and nullif(btrim(v_cliente.inscricao_municipal), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','inscricao_municipal','mensagem','Tomador de Joinville sem inscricao municipal (nao enviada na DPS; as NFS-e reais tambem nao levam).','rota',v_rota_cliente));
    end if;
    if nullif(btrim(coalesce(v_cliente.email_nfse, '')), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','email_nfse','mensagem','Tomador sem e-mail de NFS-e; a nota nao sera enviada por e-mail.','rota',v_rota_cliente));
    end if;
  end if;

  -- Municipio de prestacao e competencia (pode ser de mes anterior).
  v_municipio := regexp_replace(coalesce(p_operacao->>'municipio_prestacao_ibge', ''), '[^0-9]', '', 'g');
  if v_municipio = '' and f_local is not null then
    v_municipio := case when f_local = 'SEDE' then regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g') else regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') end;
  end if;
  if v_municipio !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','municipio_prestacao_ibge','mensagem','Municipio de prestacao vazio ou invalido (7 digitos IBGE).')); end if;
  begin
    v_competencia := coalesce(nullif(btrim(coalesce(p_operacao->>'data_competencia', '')), '')::date, current_date);
  exception when others then v_competencia := null; end;
  if v_competencia is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Data de competencia invalida.'));
  elsif v_competencia > current_date then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Competencia no futuro nao e aceita.'));
  end if;

  -- Retencoes: override da tela (com justificativa) > cadastro do tomador > regra do perfil/fixture.
  v_justificativa := nullif(btrim(coalesce(p_operacao->>'retencao_justificativa', '')), '');
  v_iss_override := case when jsonb_typeof(p_operacao->'iss_retido') = 'boolean' then (p_operacao->>'iss_retido')::boolean end;
  v_pcc_override := case when jsonb_typeof(p_operacao->'retem_pcc') = 'boolean' then (p_operacao->>'retem_pcc')::boolean end;
  v_irrf_override := case when jsonb_typeof(p_operacao->'retem_irrf') = 'boolean' then (p_operacao->>'retem_irrf')::boolean end;
  v_inss_override := case when jsonb_typeof(p_operacao->'retem_inss') = 'boolean' then (p_operacao->>'retem_inss')::boolean end;
  if v_fonte is not null and v_cliente.id is not null then
    v_iss_retido := coalesce(v_iss_override, case f_iss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.iss_retido end);
    v_pcc := coalesce(v_pcc_override, case f_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end);
    v_irrf := coalesce(v_irrf_override, case f_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end);
    v_inss := coalesce(v_inss_override, case f_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end);
    if v_iss_retido is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','iss_retido','mensagem','ISS retido indefinido para este tomador: decida no cadastro fiscal do cliente ou aqui, com justificativa.','rota',v_rota_cliente)); end if;
    if v_pcc is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_pcc','mensagem','Retencao de PIS/COFINS/CSLL indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if v_irrf is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_irrf','mensagem','Retencao de IRRF indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if v_inss is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_inss','mensagem','Retencao de INSS indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if ((v_iss_override is not null and v_iss_override is distinct from case f_iss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.iss_retido end)
        or (v_pcc_override is not null and v_pcc_override is distinct from case f_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end)
        or (v_irrf_override is not null and v_irrf_override is distinct from case f_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end)
        or (v_inss_override is not null and v_inss_override is distinct from case f_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end))
       and (v_justificativa is null or char_length(v_justificativa) < 15) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','retencao_justificativa','mensagem','Retencao diferente da regra do perfil/cadastro exige justificativa (15 caracteres ou mais), gravada na observacao.'));
    end if;
  end if;

  -- Pagamento e parcelas.
  v_pag_forma := nullif(btrim(coalesce(p_operacao->>'pagamento_forma', '')), '');
  if v_pag_forma is null or v_pag_forma !~ '^(0[1-5]|1[0-9]|2[0-4]|9[019])$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_forma','mensagem','Forma de pagamento invalida ou nao confirmada.')); end if;
  begin v_pag_indicador := nullif(btrim(coalesce(p_operacao->>'pagamento_indicador', '')), '')::smallint; exception when others then v_pag_indicador := null; end;
  if v_pag_indicador is null or v_pag_indicador not in (0, 1) then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_indicador','mensagem','Indique a vista (0) ou a prazo (1).')); end if;
  begin
    v_parcelas := case when v_pag_indicador = 1 then f.fn_nfe_normalizar_parcelas(p_operacao->'pagamento_parcelas') else null end;
  exception when others then
    v_parcelas := null;
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_parcelas','mensagem',sqlerrm));
  end;

  -- Linhas e saldo por OS.
  for v_item in select si.* from f.solicitacao_item si where si.solicitacao_id = v_sf.id order by si.ordem loop
    v_linhas := v_linhas + 1;
    if v_item.valor_servico is null or v_item.valor_servico <= 0 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_servico','mensagem',format('Linha %s: valor do servico deve ser maior que zero.', v_item.ordem))); continue;
    end if;
    if nullif(btrim(coalesce(v_item.descricao_servico, '')), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','descricao_servico','mensagem',format('Linha %s: descricao do servico obrigatoria.', v_item.ordem))); end if;
    select os.* into v_os from public.ordens_servico os where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id and os.tipo_documento = 'OS' and os.id::text = v_item.origem_id;
    if not found then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','origem_id','mensagem',format('Linha %s: OS %s nao encontrada.', v_item.ordem, v_item.origem_id))); continue; end if;
    if lower(coalesce(v_os.status_fluxo, v_os.status::text, '')) = 'cancelada' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','status','mensagem',format('Linha %s: a OS %s esta cancelada.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id)); end if;
    if v_os.cliente_id is distinct from v_sf.cliente_id then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','cliente_id','mensagem',format('Linha %s: a OS %s e de outro tomador.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id)); end if;
    if lower(coalesce(v_os.status_fluxo, '')) = 'em_andamento' then v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','status_fluxo','mensagem',format('OS %s ainda em andamento.', coalesce(v_os.numero_os, v_os.id::text)))); end if;
    v_bruto := v_bruto + v_item.valor_servico;
    v_linhas_desc := v_linhas_desc || jsonb_build_object('descricao', coalesce(v_item.descricao_servico, f_desc), 'os_numero', coalesce(v_os.numero_os, v_os.id::text));
    if not (coalesce(v_os.numero_os, v_os.id::text) = any(v_os_numeros)) then v_os_numeros := v_os_numeros || coalesce(v_os.numero_os, v_os.id::text); end if;
  end loop;
  if v_linhas = 0 then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','itens','mensagem','A solicitacao nao tem linhas.')); end if;

  for v_os_total in
    select si.origem_id::integer as os_id, round(sum(si.valor_servico), 2) as total from f.solicitacao_item si
    where si.solicitacao_id = v_sf.id and si.origem_id ~ '^[0-9]+$' group by si.origem_id
  loop
    begin select * into v_saldo from f.fn_os_saldo_a_faturar(v_sf.tenant_id, v_sf.empresa_id, v_os_total.os_id); exception when others then v_saldo := null; end;
    if v_saldo is null then continue; end if;
    v_reserva_propria := case when v_sf.status <> 'CANCELADA' then v_os_total.total else 0 end;
    v_reserva_substituida := 0;
    if v_sf.substitui_solicitacao_id is not null then
      select coalesce(round(sum(si.valor_servico), 2), 0) into v_reserva_substituida
      from f.solicitacao_item si join f.solicitacao_faturamento s on s.id = si.solicitacao_id
      where si.solicitacao_id = v_sf.substitui_solicitacao_id and si.origem_id = v_os_total.os_id::text and s.status <> 'CANCELADA'
        and not exists (select 1 from f.documento_fiscal_emissao e join f.documento_fiscal d on d.id = e.documento_fiscal_id where e.solicitacao_id = s.id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA');
      select v_reserva_substituida + coalesce(sum(d.valor_total), 0) into v_reserva_substituida from f.documento_fiscal d
      where d.id = v_sf.substitui_documento_fiscal_id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA' and d.os_id_import = v_os_total.os_id;
    end if;
    if v_saldo.valor_pedido > 0 and v_os_total.total > v_saldo.saldo + v_reserva_propria + v_reserva_substituida + 0.005 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os_total.os_id,'campo','valor_servico','mensagem',format('OS %s: total das linhas R$ %s acima do saldo da OS R$ %s.', v_os_total.os_id, to_char(v_os_total.total, 'FM999G999G990D00'), to_char(v_saldo.saldo + v_reserva_propria + v_reserva_substituida, 'FM999G999G990D00')),'rota','/os/' || v_os_total.os_id));
    end if;
  end loop;

  -- Pedido: chave presente com valor vazio = sem pedido (nao herda o texto da OS).
  v_pedido := case when p_operacao ? 'pedido_cliente' then nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') else v_sf.pedido_cliente end;
  v_pedido_item := nullif(btrim(coalesce(p_operacao->>'pedido_item', '')), '');
  v_observacao := nullif(btrim(coalesce(p_operacao->>'observacao', '')), '');
  if v_pedido is null then v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','pedido_cliente','mensagem','Sem pedido de compra do tomador.')); end if;

  if jsonb_array_length(v_pend) > 0 then
    update f.solicitacao_faturamento set emitente_snapshot = null, destinatario_snapshot = null, operacao_snapshot = null, snapshot_cadastro_em = null,
        revisao_fiscal_confirmada_em = null, revisao_fiscal_confirmada_por = null, updated_at = now() where id = v_sf.id;
    return jsonb_build_object('ok', false, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente, 'pendencias', v_pend, 'avisos', v_avisos);
  end if;

  -- Valores.
  v_valor_iss := round(v_bruto * f_aliq_iss / 100, 2);
  v_v_irrf := case when v_irrf then round(v_bruto * coalesce(f_aliq_irrf, 0) / 100, 2) else 0 end;
  v_v_pcc := case when v_pcc then round(v_bruto * coalesce(f_aliq_pcc, 0) / 100, 2) else 0 end;
  v_v_inss := case when v_inss then round(v_bruto * coalesce(f_aliq_inss, 0) / 100, 2) else 0 end;
  v_liquido := v_bruto - (case when v_iss_retido then v_valor_iss else 0 end) - v_v_irrf - v_v_pcc - v_v_inss;
  if v_iss_retido then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'ISS', 'base', v_bruto, 'aliquota', f_aliq_iss, 'valor', v_valor_iss); end if;
  if v_irrf then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'IRRF', 'base', v_bruto, 'aliquota', f_aliq_irrf, 'valor', v_v_irrf); end if;
  if v_pcc then
    v_retencoes := v_retencoes
      || jsonb_build_object('tributo', 'PIS', 'base', v_bruto, 'aliquota', 0.65, 'valor', round(v_bruto * 0.65 / 100, 2))
      || jsonb_build_object('tributo', 'COFINS', 'base', v_bruto, 'aliquota', 3.00, 'valor', round(v_bruto * 3.00 / 100, 2))
      || jsonb_build_object('tributo', 'CSLL', 'base', v_bruto, 'aliquota', 1.00, 'valor', v_v_pcc - round(v_bruto * 0.65 / 100, 2) - round(v_bruto * 3.00 / 100, 2));
  end if;
  if v_inss then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'INSS', 'base', v_bruto, 'aliquota', f_aliq_inss, 'valor', v_v_inss); end if;
  v_tem_federal := v_irrf or v_pcc or v_inss;
  v_texto_retencao := case
    when v_tem_federal then
      'RETENCOES FEDERAIS: ' || concat_ws('; ',
        case when v_irrf then 'IRRF ' || replace(to_char(f_aliq_irrf, 'FM990D00'), '.', ',') || '%' end,
        case when v_pcc then 'PIS/COFINS/CSLL ' || replace(to_char(f_aliq_pcc, 'FM990D00'), '.', ',') || '% (PIS 0,65%; COFINS 3,00%; CSLL 1,00%)' end,
        case when v_inss then 'INSS ' || replace(to_char(f_aliq_inss, 'FM990D00'), '.', ',') || '%' end) || '.'
    else f_texto_sem end;
  v_discriminacao := f.fn_nfse_discriminacao(v_linhas_desc, v_pedido, v_pedido_item, v_parcelas, current_date, v_iss_retido, v_texto_retencao,
    concat_ws(' ', v_observacao, case when v_justificativa is not null then 'RETENCAO AJUSTADA: ' || v_justificativa end));

  update f.solicitacao_item si
  set codigo_tributacao_nacional = f_ctrib, codigo_tributacao_municipal = f_ctrib_mun, codigo_nbs = f_nbs,
      tributacao_iss = f_trib_iss, aliquota_iss = f_aliq_iss, iss_retido = v_iss_retido,
      aliquota_irrf = case when v_irrf then f_aliq_irrf end, aliquota_pcc = case when v_pcc then f_aliq_pcc end, aliquota_inss = case when v_inss then f_aliq_inss end,
      local_prestacao_ibge = v_municipio,
      cst_pis = f_cst_pis, aliquota_pis = f_aliq_pis, cst_cofins = f_cst_cofins, aliquota_cofins = f_aliq_cofins,
      cst_ibs_cbs = f_cst_ibs, cclass_trib = f_cclass,
      ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', f_ibs_uf, 'ibs_mun_aliquota', f_ibs_mun, 'cbs_aliquota', f_cbs),
      perfil_operacao_id = v_perfil.id, perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id,
      tributacao_fonte = v_fonte, descricao = coalesce(si.descricao_servico, si.descricao)
  where si.solicitacao_id = v_sf.id;

  update f.solicitacao_faturamento sf
  set perfil_operacao_id = v_perfil.id, natureza_operacao = 'PRESTACAO_SERVICO', consumidor_final = v_consumidor_final,
      municipio_prestacao_ibge = v_municipio, data_competencia = v_competencia,
      iss_retido = v_iss_retido, retem_pcc = v_pcc, retem_irrf = v_irrf, retem_inss = v_inss, retencao_justificativa = v_justificativa,
      pagamento_forma = v_pag_forma, pagamento_indicador = v_pag_indicador, pagamento_descricao = nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''), pagamento_parcelas = v_parcelas,
      pedido_cliente = v_pedido, pedido_item = v_pedido_item, observacao = coalesce(v_observacao, sf.observacao),
      modalidade_frete = null, transportador_dados = null, volumes_dados = null,
      destino_uf_confirmada = upper(v_cliente.uf), destino_confirmado_em = now(), destino_confirmado_por = v_usuario_id,
      perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id, revisao_fiscal_confirmada_em = now(), revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = jsonb_build_object(
        'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'), 'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
        'telefone', v_empresa.telefone, 'email', v_empresa.email, 'inscricao_municipal', nullif(btrim(coalesce(v_fiscal.inscricao_municipal, '')), ''),
        'codigo_opcao_simples_nacional', v_fiscal.codigo_opcao_simples_nacional, 'regime_especial_tributacao', v_fiscal.regime_especial_tributacao, 'serie_dps', v_fiscal.serie_dps,
        'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero, 'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro, 'cidade', v_endereco.cidade, 'uf', upper(v_endereco.uf::text),
        'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'), 'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')),
      destinatario_snapshot = jsonb_build_object(
        'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social, 'inscricao_municipal', nullif(btrim(coalesce(v_cliente.inscricao_municipal, '')), ''),
        'email', coalesce(nullif(btrim(coalesce(v_cliente.email_nfse, '')), ''), nullif(btrim(coalesce(v_cliente.email_financeiro, '')), '')),
        'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro, 'numero_endereco', v_cliente.numero_endereco, 'complemento', v_cliente.complemento,
        'bairro', v_cliente.bairro, 'cidade', v_cliente.cidade, 'uf', upper(v_cliente.uf),
        'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'), 'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')),
      operacao_snapshot = jsonb_build_object(
        'natureza_operacao', 'PRESTACAO_SERVICO', 'modelo', 'NFSE', 'tributacao_fonte', v_fonte, 'consumidor_final', v_consumidor_final,
        'servico', jsonb_build_object(
          'perfil_operacao_id', v_perfil.id, 'perfil_codigo', v_perfil.codigo, 'item_servico', f_item,
          'codigo_tributacao_nacional', f_ctrib, 'codigo_tributacao_municipal', f_ctrib_mun, 'codigo_nbs', f_nbs,
          'municipio_prestacao_ibge', v_municipio, 'data_competencia', v_competencia,
          'tributacao_iss', f_trib_iss, 'aliquota_iss', f_aliq_iss, 'iss_retido', v_iss_retido, 'retem_pcc', v_pcc, 'retem_irrf', v_irrf, 'retem_inss', v_inss,
          'valor_bruto', v_bruto, 'valor_iss', v_valor_iss, 'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss, 'valor_liquido', v_liquido, 'retencoes', v_retencoes,
          'cst_pis_cofins', f_cst_pis, 'aliquota_pis', f_aliq_pis, 'aliquota_cofins', f_aliq_cofins,
          'cst_ibs_cbs', f_cst_ibs, 'cclass_trib', f_cclass, 'ibs_uf_aliquota', f_ibs_uf, 'ibs_mun_aliquota', f_ibs_mun, 'cbs_aliquota', f_cbs,
          'codigo_indicador_operacao', f_cindop, 'tributos_aprox_federal_pct', f_pct_fed, 'tributos_aprox_municipal_pct', f_pct_mun,
          'descricao_servico', v_discriminacao, 'texto_retencao', v_texto_retencao, 'os_numeros', to_jsonb(v_os_numeros)),
        'pedido', jsonb_build_object('pedido_cliente', v_pedido, 'pedido_item', v_pedido_item),
        'substituicao', case when v_sf.substitui_documento_fiscal_id is null then null else jsonb_build_object(
          'documento_fiscal_id', v_sf.substitui_documento_fiscal_id, 'solicitacao_id', v_sf.substitui_solicitacao_id, 'codigo', v_sf.substituicao_codigo, 'motivo', v_sf.substituicao_motivo,
          'chave', (select e.chave_nfse from f.documento_fiscal_emissao e where e.documento_fiscal_id = v_sf.substitui_documento_fiscal_id limit 1)) end,
        'pagamento', jsonb_build_object('forma', v_pag_forma, 'indicador', v_pag_indicador, 'descricao', nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''), 'parcelas', v_parcelas, 'fatura_numero', null)),
      snapshot_cadastro_em = now(), updated_at = now()
  where sf.id = v_sf.id;

  if nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is not null then
    update public.ordens_servico os set pedido_compra = btrim(p_operacao->>'pedido_cliente'), atualizado_em = now()
    where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id
      and os.id::text in (select si.origem_id from f.solicitacao_item si where si.solicitacao_id = v_sf.id)
      and os.pedido_compra is distinct from btrim(p_operacao->>'pedido_cliente');
  end if;

  return jsonb_build_object(
    'ok', true, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente, 'pendencias', '[]'::jsonb, 'avisos', v_avisos,
    'previa', jsonb_build_object(
      'item_servico', f_item, 'codigo_tributacao_nacional', f_ctrib, 'codigo_nbs', f_nbs, 'municipio_prestacao_ibge', v_municipio, 'data_competencia', v_competencia,
      'valor_bruto', v_bruto, 'aliquota_iss', f_aliq_iss, 'valor_iss', v_valor_iss, 'iss_retido', v_iss_retido,
      'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss, 'valor_liquido', v_liquido,
      'retencoes', v_retencoes, 'parcelas', v_parcelas, 'descricao_servico', v_discriminacao, 'tributacao_fonte', v_fonte));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Preparo por ambiente
-- ---------------------------------------------------------------------------
drop function if exists f.fn_nfse_preparar_documento_solicitacao(uuid);
create function f.fn_nfse_preparar_documento_solicitacao(p_solicitacao_id uuid, p_ambiente text default 'HOMOLOGACAO')
returns table (documento_fiscal_id uuid, solicitacao_id uuid, referencia_externa text, status text, criado boolean, dps_serie smallint, dps_numero bigint)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_documento_id uuid := gen_random_uuid();
  v_referencia text;
  v_serv jsonb;
  v_bruto numeric(15,2); v_liquido numeric(15,2);
  v_os_id integer;
  v_dps record;
  v_prontidao jsonb;
begin
  if p_ambiente not in ('HOMOLOGACAO', 'PRODUCAO') then raise exception using errcode = '22023', message = 'Ambiente invalido.'; end if;
  select * into v_sf from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id or public.current_empresa_id() is distinct from v_sf.empresa_id or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para emitir esta solicitacao.';
  end if;
  v_referencia := case when p_ambiente = 'PRODUCAO' then 'NFSP-' else 'NFSH-' end || v_sf.id;
  perform pg_advisory_xact_lock(hashtextextended(v_referencia, 0));

  return query
  select dfe.documento_fiscal_id, dfe.solicitacao_id, dfe.referencia_externa, dfe.status, false, dfe.dps_serie, dfe.dps_numero
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id and dfe.empresa_id = v_sf.empresa_id and dfe.solicitacao_id = v_sf.id and dfe.ambiente = p_ambiente;
  if found then return; end if;

  if p_ambiente = 'HOMOLOGACAO' and v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Solicitacao nao esta disponivel para emissao.';
  end if;
  if p_ambiente = 'PRODUCAO' then
    if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA', 'EMITIDA') then raise exception using errcode = '22023', message = 'Solicitacao nao esta disponivel para emissao em producao.'; end if;
    if not exists (select 1 from f.documento_fiscal_emissao hom where hom.solicitacao_id = v_sf.id and hom.ambiente = 'HOMOLOGACAO' and hom.status = 'AUTORIZADA' and hom.modelo = 'NFSE') then
      raise exception using errcode = '22023', message = 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.';
    end if;
    v_prontidao := f.fn_nfse_producao_pronta(v_sf.id);
    if not coalesce((v_prontidao->>'pronta')::boolean, false) then
      raise exception using errcode = 'P0001', message = coalesce(v_prontidao->>'motivo', 'Producao bloqueada.');
    end if;
  end if;
  if v_sf.snapshot_cadastro_em is null or jsonb_typeof(v_sf.emitente_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.destinatario_snapshot) is distinct from 'object' or jsonb_typeof(v_sf.operacao_snapshot->'servico') is distinct from 'object' then
    raise exception using errcode = '22023', message = 'Conferencia da NFS-e ainda nao foi salva nesta solicitacao.';
  end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and si.modelo <> 'NFSE') then
    raise exception using errcode = '22023', message = 'Solicitacao com linha de mercadoria; use o pipeline de NF-e.';
  end if;
  v_serv := v_sf.operacao_snapshot->'servico';
  v_bruto := round((v_serv->>'valor_bruto')::numeric, 2);
  v_liquido := round((v_serv->>'valor_liquido')::numeric, 2);
  if v_bruto is null or v_bruto <= 0 or v_liquido is null or v_liquido <= 0 then raise exception using errcode = '22023', message = 'Valores da NFS-e invalidos na conferencia.'; end if;
  select min(si.origem_id::integer) into v_os_id from f.solicitacao_item si where si.solicitacao_id = v_sf.id and si.origem_tipo = 'OS' and si.origem_id ~ '^[0-9]+$';

  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date, competencia_date, valor_total, valor_servicos, operacao, natureza, cliente_id, os_id_import, nfse_status, origem, nfse_municipio_codigo, servico_discriminacao)
  values (v_documento_id, v_sf.tenant_id, v_sf.empresa_id, 'PENDENTE:' || v_referencia, 'NFSE', current_date,
    date_trunc('month', coalesce((v_serv->>'data_competencia')::date, current_date))::date,
    v_liquido, v_bruto, 'SAIDA', 'SERVICO', v_sf.cliente_id, v_os_id, 'RASCUNHO', 'EMITIDO', v_serv->>'municipio_prestacao_ibge', v_serv->>'descricao_servico');
  insert into f.documento_fiscal_item (tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo, codigo, codigo_servico, descricao, quantidade, unidade, valor_unitario, valor_total, item_id, cst_pis, cst_cofins, cst_ibs_cbs, cclass_trib, ibs_cbs_json)
  select si.tenant_id, si.empresa_id, v_documento_id, si.ordem, 'SERVICO', si.codigo_tributacao_nacional, si.codigo_tributacao_nacional, coalesce(si.descricao_servico, si.descricao), 1, 'UN', si.valor_servico, si.valor_servico, null,
         si.cst_pis, si.cst_cofins, si.cst_ibs_cbs, si.cclass_trib, si.ibs_cbs_json
  from f.solicitacao_item si where si.solicitacao_id = v_sf.id order by si.ordem, si.id;

  select * into v_dps from f.fn_proximo_numero_dps(v_sf.empresa_id, p_ambiente);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status, modelo,
    dps_serie, dps_numero, municipio_prestacao_ibge, iss_retido, valor_iss, valor_deducoes, retencoes, valor_liquido, chave_nfse_substituida, substituicao_codigo, substituicao_motivo)
  values (v_documento_id, v_sf.id, v_sf.tenant_id, v_sf.empresa_id, v_referencia, p_ambiente, 'RASCUNHO', 'NFSE',
    v_dps.serie, v_dps.numero, v_serv->>'municipio_prestacao_ibge', (v_serv->>'iss_retido')::boolean, round((v_serv->>'valor_iss')::numeric, 2), 0,
    coalesce(v_serv->'retencoes', '[]'::jsonb), v_liquido, v_sf.operacao_snapshot->'substituicao'->>'chave', v_sf.substituicao_codigo, v_sf.substituicao_motivo);
  insert into f.dps_numero_log (tenant_id, empresa_id, serie, numero, documento_fiscal_id, referencia_externa, resultado, mensagem)
  values (v_sf.tenant_id, v_sf.empresa_id, v_dps.serie, v_dps.numero, v_documento_id, v_referencia, 'RESERVADO', format('Reservado na preparacao (%s).', p_ambiente));

  if v_sf.status <> 'EMITIDA' then update f.solicitacao_faturamento set status = 'APROVADA', updated_at = now() where id = v_sf.id; end if;
  return query select v_documento_id, v_sf.id, v_referencia, 'RASCUNHO'::text, true, v_dps.serie, v_dps.numero;
end;
$$;
revoke all on function f.fn_nfse_preparar_documento_solicitacao(uuid, text) from public;
grant execute on function f.fn_nfse_preparar_documento_solicitacao(uuid, text) to authenticated, service_role;

-- O log da DPS de producao e de homologacao compartilham (serie, numero): a
-- unicidade passa a incluir o ambiente (a referencia distingue os documentos).
alter table f.dps_numero_log add column if not exists ambiente text not null default 'HOMOLOGACAO';
alter table f.dps_numero_log drop constraint if exists dps_numero_log_tenant_id_empresa_id_serie_numero_key;
alter table f.dps_numero_log drop constraint if exists dps_numero_log_ambiente_check;
alter table f.dps_numero_log add constraint dps_numero_log_ambiente_check check (ambiente in ('HOMOLOGACAO', 'PRODUCAO'));
create unique index if not exists dps_numero_log_serie_numero_ambiente_ux on f.dps_numero_log (tenant_id, empresa_id, ambiente, serie, numero);
-- Preenche o ambiente do log a partir da emissao e faz o preparo gravar o ambiente.
update f.dps_numero_log l set ambiente = e.ambiente from f.documento_fiscal_emissao e where e.documento_fiscal_id = l.documento_fiscal_id and l.ambiente <> e.ambiente;
create or replace function f.trg_dps_numero_log_ambiente() returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if new.documento_fiscal_id is not null then
    select e.ambiente into new.ambiente from f.documento_fiscal_emissao e where e.documento_fiscal_id = new.documento_fiscal_id;
    new.ambiente := coalesce(new.ambiente, 'HOMOLOGACAO');
  end if;
  return new;
end;
$$;
drop trigger if exists trg_dps_numero_log_ambiente on f.dps_numero_log;
create trigger trg_dps_numero_log_ambiente before insert on f.dps_numero_log for each row execute function f.trg_dps_numero_log_ambiente();

-- ---------------------------------------------------------------------------
-- 6. Claim duravel para os dois ambientes; 7. renumeracao por ambiente
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfse_emissao_claimar(p_documento_fiscal_id uuid, p_payload jsonb, p_reconciliacao_confirmada boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_tinha_claim boolean;
  v_payload_congelado jsonb;
  v_payload_alterado boolean := false;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o envio.'; end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then raise exception using errcode = '22023', message = 'O payload da NFS-e deve ser um objeto JSON.'; end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE' for update;
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  if v_emissao.status in ('AUTORIZADA', 'PROCESSANDO', 'CANCELADA') then
    return jsonb_build_object('deve_enviar', false, 'aguardar', v_emissao.status = 'PROCESSANDO', 'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa, 'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
  end if;
  v_tinha_claim := v_emissao.status = 'ENVIANDO' or v_emissao.tentativa_count > 0 or v_emissao.payload_enviado is not null or v_emissao.enviado_em is not null;
  if v_emissao.status = 'ENVIANDO' and v_emissao.ultima_tentativa_em >= now() - interval '2 minutes' then
    return jsonb_build_object('deve_enviar', false, 'aguardar', true, 'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa, 'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
  end if;
  if v_tinha_claim and not coalesce(p_reconciliacao_confirmada, false) then
    raise exception using errcode = '55000', message = 'A referencia ja possui tentativa; consulte a Focus antes de qualquer novo POST.';
  end if;
  if (p_payload->>'numero_dps')::bigint is distinct from v_emissao.dps_numero or (p_payload->>'serie_dps')::smallint is distinct from v_emissao.dps_serie then
    raise exception using errcode = '22023', message = 'O payload nao traz a serie/numero de DPS reservados para esta emissao.';
  end if;
  if v_emissao.status in ('REJEITADA', 'ERRO') then
    v_payload_alterado := v_emissao.payload_enviado is not null and (v_emissao.payload_enviado - 'numero_dps' - 'data_emissao') is distinct from (p_payload - 'numero_dps' - 'data_emissao');
    v_payload_congelado := p_payload;
  else
    if v_emissao.payload_enviado is not null and v_emissao.payload_enviado is distinct from p_payload then
      raise exception using errcode = '22023', message = 'O retry diverge do payload congelado no primeiro claim.';
    end if;
    v_payload_congelado := coalesce(v_emissao.payload_enviado, p_payload);
  end if;
  if v_emissao.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'ENVIANDO') then
    raise exception using errcode = '55000', message = format('Status %s nao aceita claim.', v_emissao.status);
  end if;
  update f.documento_fiscal_emissao dfe
  set status = 'ENVIANDO', payload_enviado = v_payload_congelado, tentativa_count = dfe.tentativa_count + 1, ultima_tentativa_em = now(),
      enviado_em = coalesce(dfe.enviado_em, now()), codigo_status = null, mensagem = null, updated_at = now()
  where dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;
  insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa)
  values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'ENVIO', 'ENVIANDO',
    jsonb_build_object('claim_duravel', true, 'ambiente', v_emissao.ambiente, 'modelo', 'NFSE', 'tentativa', v_emissao.tentativa_count,
      'dps_serie', v_emissao.dps_serie, 'dps_numero', v_emissao.dps_numero, 'payload_alterado_apos_rejeicao', v_payload_alterado, 'reconciliacao_previa', coalesce(p_reconciliacao_confirmada, false)),
    v_emissao.referencia_externa);
  return jsonb_build_object('deve_enviar', true, 'aguardar', false, 'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa, 'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
end;
$$;
revoke all on function f.fn_nfse_emissao_claimar(uuid, jsonb, boolean) from public;
grant execute on function f.fn_nfse_emissao_claimar(uuid, jsonb, boolean) to service_role;

create or replace function f.fn_nfse_renumerar_dps(p_documento_fiscal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_dps record;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then raise exception using errcode = '42501', message = 'Somente o backend fiscal renumera a DPS.'; end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE' for update;
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  if v_emissao.status not in ('REJEITADA', 'ERRO') then
    return jsonb_build_object('dps_serie', v_emissao.dps_serie, 'dps_numero', v_emissao.dps_numero, 'renumerada', false);
  end if;
  update f.dps_numero_log set resultado = case when resultado = 'RESERVADO' then 'REJEITADO' else resultado end, mensagem = coalesce(mensagem, 'DPS queimada por rejeicao.'), updated_at = now()
  where documento_fiscal_id = v_emissao.documento_fiscal_id and serie = v_emissao.dps_serie and numero = v_emissao.dps_numero;
  select * into v_dps from f.fn_proximo_numero_dps(v_emissao.empresa_id, v_emissao.ambiente);
  update f.documento_fiscal_emissao set dps_serie = v_dps.serie, dps_numero = v_dps.numero, updated_at = now() where documento_fiscal_id = v_emissao.documento_fiscal_id;
  insert into f.dps_numero_log (tenant_id, empresa_id, serie, numero, documento_fiscal_id, referencia_externa, resultado, mensagem)
  values (v_emissao.tenant_id, v_emissao.empresa_id, v_dps.serie, v_dps.numero, v_emissao.documento_fiscal_id, v_emissao.referencia_externa, 'RESERVADO',
          format('Retry apos %s da DPS %s/%s (%s).', v_emissao.status, v_emissao.dps_serie, v_emissao.dps_numero, v_emissao.ambiente));
  return jsonb_build_object('dps_serie', v_dps.serie, 'dps_numero', v_dps.numero, 'renumerada', true);
end;
$$;
