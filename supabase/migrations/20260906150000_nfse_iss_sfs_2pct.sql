-- Contador, 06/09/2026 (terceira rodada):
--  1. ISS do 07.02 em Sao Francisco do Sul e 2% (LC municipal, piso; NFS-e 1646). A nota 37
--     saiu com 3% por erro do emissor antigo. Tabela corrigida e o perfil 07.02 sai de BLOQUEADO
--     para REVISAO (producao continua exigindo homologacao + liberacao).
--  2. Obra em municipio sem aliquota cadastrada vira pendencia, nunca chute.
--  3. cBenef do Convenio 52/91 (NCM 8460.90.90): codigo exato ainda com o contador (Tabela 5.2 SEF/SC,
--     Anexo 2 art. 9). Nada parametrizado.
--  4. Remessa de material para obra: NF-e 5.949/6.949 sem ICMS/IPI serve de prova do material
--     deduzido; material vendido por NF-e nao entra na deducao. Regras em docs/faturamento.
--  5. PIS/COFINS das NFS-e importadas: ajuste e na escrituracao (EFD-Contribuicoes); o ERP nao
--     reescreve o historico sem decisao explicita (impacto medido no relatorio).
-- Baseline: f.fn_os_nfse_conferir_homologacao (20260906140000).

update f.nfse_aliquota_iss set aliquota = 2.00,
  fonte = 'Contador 06/09/2026: LC municipal de Sao Francisco do Sul, piso de 2% para 07.02 (NFS-e 1646). A NFS-e 37 saiu com 3% por erro do emissor antigo.'
where item_servico = '07.02' and municipio_ibge = '4216206';

update f.tributacao_provisoria_nfse_homologacao set aliquota_iss = 2,
  pendencia_contador = 'Contador 06/09/2026: ISS 2% em SFS (LC municipal), retido pelo tomador; INSS 11% (material discriminado abate a base); sem IRRF/CRF; NBS 1.0102.41.00; cIndOp 020201.'
where item_servico = '07.02';

-- Perfil 07.02 deixa de ser BLOQUEADO: as tres pendencias (aliquota, deducao de material, cIndOp/NBS) foram
-- respondidas. Producao continua fechada ate homologar e liberar (fn_perfil_operacao_nfse_liberar_producao).
update f.perfil_operacao set faixa_automacao = 'REVISAO', justificativa_faixa = null
where modelo = 'NFSE' and item_servico = '07.02' and faixa_automacao = 'BLOQUEADO'
  and exists (select 1 from c.empresa e where e.id = perfil_operacao.empresa_id and e.codigo = 'SEG');

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
  v_municipio_incidencia text;
  v_sede_ibge text;
  v_competencia date;
  v_iss_retido boolean; v_pcc boolean; v_irrf boolean; v_inss boolean;
  v_iss_override boolean; v_pcc_override boolean; v_irrf_override boolean; v_inss_override boolean;
  v_justificativa text;
  v_bruto numeric(15,2) := 0; v_valor_iss numeric(15,2) := 0; v_v_irrf numeric(15,2) := 0; v_v_pcc numeric(15,2) := 0; v_v_inss numeric(15,2) := 0;
  v_deducao numeric(15,2) := 0; v_base_iss numeric(15,2); v_base_inss numeric(15,2);
  v_permite_deducao boolean := false;
  v_liquido numeric(15,2);
  v_retencoes jsonb := '[]'::jsonb;
  v_parcelas jsonb;
  v_pag_forma text; v_pag_indicador smallint;
  v_saldo record; v_reserva_propria numeric(15,2); v_reserva_substituida numeric(15,2); v_os_total record;
  v_linhas_desc jsonb := '[]'::jsonb;
  v_os_numeros text[] := array[]::text[];
  v_discriminacao text; v_texto_retencao text; v_proibido text;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_emissao_status text;
  v_linhas integer := 0;
  v_consumidor_final smallint;
  v_pedido text; v_pedido_item text; v_observacao text; v_obs_composta text;
  v_conserto_isolado boolean;
  v_todas_conserto boolean := true;
  v_tem_federal boolean;
  v_motivo_pcc text;
  v_frase_motivo text;
  v_substituto boolean := false;
  v_ibs_base numeric(15,2); v_ibs_uf numeric(15,2); v_ibs_mun numeric(15,2); v_cbs numeric(15,2);
  v_vtottrib numeric(15,2);
  v_fonte text;
  f_ctrib text; f_ctrib_mun text; f_nbs text; f_desc text; f_local text; f_incid text; f_trib_iss smallint; f_aliq_iss numeric;
  f_iss_regra text; f_pcc_regra text; f_irrf_regra text; f_inss_regra text; f_aliq_pcc numeric; f_aliq_irrf numeric; f_aliq_inss numeric;
  f_cst_pis text; f_cst_cofins text; f_aliq_pis numeric; f_aliq_cofins numeric; f_cst_ibs text; f_cclass text;
  f_ibs_uf numeric; f_ibs_mun numeric; f_cbs numeric; f_cindop text; f_pct_fed numeric; f_pct_mun numeric; f_pct_est numeric;
  f_texto_sem text; f_texto_com text; f_item text; f_excecao_conserto boolean := false;
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

  select po.* into v_perfil from f.perfil_operacao po
  where po.id = coalesce(nullif(p_operacao->>'perfil_operacao_id', '')::uuid, v_sf.perfil_operacao_id)
    and po.tenant_id = v_sf.tenant_id and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null);
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','campo','perfil_operacao_id','mensagem','Escolha o perfil de servico da NFS-e.','rota',v_rota_perfil));
  else
    if v_perfil.modelo <> 'NFSE' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','modelo','mensagem',format('Perfil %s nao e de servico.', v_perfil.codigo),'rota',v_rota_perfil)); end if;
    if v_perfil.item_servico = '17.06' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','item_servico','mensagem','O subitem 17.06 (propaganda) nao existe no catalogo da Segau; laudos e documentacao tecnica sao 17.09.','rota',v_rota_perfil)); end if;
    if v_perfil.faixa_automacao = 'BLOQUEADO' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','faixa_automacao','mensagem',format('Perfil %s bloqueado: %s', v_perfil.codigo, coalesce(v_perfil.justificativa_faixa, 'aguarda o contador.')),'rota',v_rota_perfil)); end if;
    if v_perfil.vigencia_inicio > current_date or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date) then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','vigencia','mensagem',format('Perfil %s fora da vigencia.', v_perfil.codigo),'rota',v_rota_perfil)); end if;
    if v_perfil.revisao_fiscal_em is not null and v_perfil.codigo_tributacao_nacional is not null and v_perfil.aliquota_iss is not null and v_perfil.iss_retido_regra is not null then
      v_fonte := 'PERFIL';
      f_item := v_perfil.item_servico; f_ctrib := v_perfil.codigo_tributacao_nacional; f_ctrib_mun := v_perfil.codigo_tributacao_municipal; f_nbs := v_perfil.codigo_nbs;
      f_desc := v_perfil.descricao_servico_padrao; f_local := coalesce(v_perfil.local_prestacao_regra, 'SEDE'); f_incid := coalesce(v_perfil.incidencia_iss_regra, 'PRESTADOR');
      f_trib_iss := coalesce(v_perfil.tributacao_iss, 1); f_aliq_iss := v_perfil.aliquota_iss;
      f_iss_regra := v_perfil.iss_retido_regra; f_pcc_regra := coalesce(v_perfil.retencao_pcc_regra, 'NUNCA'); f_irrf_regra := coalesce(v_perfil.retencao_irrf_regra, 'NUNCA'); f_inss_regra := coalesce(v_perfil.retencao_inss_regra, 'NUNCA');
      f_aliq_pcc := v_perfil.aliquota_pcc; f_aliq_irrf := v_perfil.aliquota_irrf; f_aliq_inss := v_perfil.aliquota_inss;
      f_cst_pis := v_perfil.cst_pis; f_cst_cofins := v_perfil.cst_cofins; f_aliq_pis := v_perfil.aliquota_pis; f_aliq_cofins := v_perfil.aliquota_cofins;
      f_cst_ibs := v_perfil.cst_ibs_cbs; f_cclass := v_perfil.cclass_trib;
      f_ibs_uf := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'); f_ibs_mun := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'); f_cbs := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota');
      f_cindop := v_perfil.codigo_indicador_operacao; f_pct_fed := v_perfil.tributos_aprox_federal_pct; f_pct_mun := v_perfil.tributos_aprox_municipal_pct;
      f_texto_com := v_perfil.texto_complementar; f_texto_sem := v_perfil.texto_sem_retencao; f_excecao_conserto := coalesce(v_perfil.excecao_conserto_isolado, false);
      v_permite_deducao := coalesce(v_perfil.permite_deducao_material, false);
      v_consumidor_final := coalesce(v_perfil.consumidor_final, 0);
      if f_cindop is null then
        if current_date >= date '2026-10-01' then
          v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','codigo_indicador_operacao','mensagem','Perfil sem cIndOp: obrigatorio no grupo IBS/CBS desde 01/10/2026 (Ato Conjunto RFB/CGIBS 4/2026).','rota',v_rota_perfil));
        else
          v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','codigo_indicador_operacao','mensagem','Perfil sem cIndOp; obrigatorio a partir de 01/10/2026.','rota',v_rota_perfil));
        end if;
      end if;
      if v_perfil.campos_conferir is not null and jsonb_array_length(v_perfil.campos_conferir) > 0 then
        v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','campos_conferir','mensagem','Perfil com campos travados (' || (select string_agg(x->>'campo' || ': ' || (x->>'motivo'), '; ') from jsonb_array_elements(v_perfil.campos_conferir) x) || '). Homologacao segue; producao bloqueada ate a confirmacao.','rota',v_rota_perfil));
      end if;
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
        f_desc := v_fx.descricao_servico_padrao; f_local := v_fx.local_prestacao_regra; f_incid := case when v_fx.item_servico like '07.%' then 'LOCAL_PRESTACAO' else 'PRESTADOR' end;
        f_trib_iss := v_fx.tributacao_iss; f_aliq_iss := v_fx.aliquota_iss;
        f_iss_regra := v_fx.iss_retido_regra; f_pcc_regra := v_fx.retencao_pcc_regra; f_irrf_regra := v_fx.retencao_irrf_regra; f_inss_regra := v_fx.retencao_inss_regra;
        f_aliq_pcc := v_fx.aliquota_pcc; f_aliq_irrf := v_fx.aliquota_irrf; f_aliq_inss := v_fx.aliquota_inss;
        f_cst_pis := v_fx.cst_pis_cofins; f_cst_cofins := v_fx.cst_pis_cofins; f_aliq_pis := v_fx.aliquota_pis; f_aliq_cofins := v_fx.aliquota_cofins;
        f_cst_ibs := v_fx.cst_ibs_cbs; f_cclass := v_fx.cclass_trib; f_ibs_uf := v_fx.ibs_uf_aliquota; f_ibs_mun := v_fx.ibs_mun_aliquota; f_cbs := v_fx.cbs_aliquota;
        f_cindop := case when v_fx.item_servico = '07.02' then '020201' else '050103' end; f_pct_fed := null; f_pct_mun := null;
        f_texto_sem := v_fx.texto_sem_retencao; f_texto_com := v_fx.texto_com_retencao;
        v_permite_deducao := v_fx.item_servico like '07.%';
        v_consumidor_final := coalesce(v_perfil.consumidor_final, v_fx.consumidor_final, 0);
      end if;
    end if;
    if v_fonte is not null and not f.fn_nfse_nbs_compativel(f_item, f_nbs) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','codigo_nbs','mensagem',format('NBS %s incompativel com o subitem %s (capitulo errado; caso da nota 21 real).', f_nbs, f_item),'rota',v_rota_perfil));
    end if;
  end if;

  select e.* into v_empresa from c.empresa e where e.tenant_id = v_sf.tenant_id and e.id = v_sf.empresa_id and e.deleted_at is null and e.ativo;
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','empresa','mensagem','Empresa ativa nao encontrada.','rota','/configuracoes'));
  else
    select ef.* into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
    select ee.* into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
    v_sede_ibge := regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g');
    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14 then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','cnpj','mensagem','CNPJ do prestador invalido.','rota','/configuracoes')); end if;
    if v_fiscal.id is null or v_fiscal.serie_dps is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','serie_dps','mensagem','Serie da DPS nao configurada no cadastro fiscal da empresa.','rota','/configuracoes')); end if;
    if v_fiscal.id is null or v_fiscal.codigo_opcao_simples_nacional is null or v_fiscal.regime_especial_tributacao is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_opcao_simples_nacional','mensagem','Opcao pelo Simples e regime especial nao informados no cadastro fiscal da empresa.','rota','/configuracoes')); end if;
    if v_sede_ibge !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_municipio_ibge','mensagem','Codigo IBGE do endereco fiscal do prestador deve ter 7 digitos.','rota','/configuracoes')); end if;
  end if;

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
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') = '4209102' and nullif(btrim(v_cliente.inscricao_municipal), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','inscricao_municipal','mensagem','Tomador de Joinville sem inscricao municipal (nao enviada na DPS; as NFS-e reais tambem nao levam).','rota',v_rota_cliente));
    end if;
    if nullif(btrim(coalesce(v_cliente.email_nfse, '')), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','email_nfse','mensagem','Tomador sem e-mail de NFS-e; a nota nao sera enviada por e-mail.','rota',v_rota_cliente));
    end if;
  end if;

  v_municipio := regexp_replace(coalesce(p_operacao->>'municipio_prestacao_ibge', ''), '[^0-9]', '', 'g');
  if v_municipio = '' and f_local is not null then
    v_municipio := case when f_local = 'SEDE' then v_sede_ibge else regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') end;
  end if;
  if v_municipio !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','municipio_prestacao_ibge','mensagem','Municipio de prestacao vazio ou invalido (7 digitos IBGE).')); end if;
  v_municipio_incidencia := case when f_incid = 'LOCAL_PRESTACAO' then v_municipio else v_sede_ibge end;
  begin
    v_competencia := coalesce(nullif(btrim(coalesce(p_operacao->>'data_competencia', '')), '')::date, current_date);
  exception when others then v_competencia := null; end;
  if v_competencia is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Data de competencia invalida.'));
  elsif v_competencia > current_date then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Competencia no futuro nao e aceita.'));
  end if;

  if v_fonte is not null then
    select a.aliquota into f_aliq_iss from f.nfse_aliquota_iss a
    where a.tenant_id = v_sf.tenant_id and a.empresa_id = v_sf.empresa_id and a.item_servico = f_item and a.municipio_ibge = v_municipio_incidencia;
    if not found then
      -- Obra (incidencia no municipio da prestacao): a aliquota e da lei de cada municipio (SFS 2%, Joinville 5%);
      -- sem linha cadastrada nao se adivinha (contador, 06/09/2026: a nota 37 saiu com 3% em SFS e o certo e 2%).
      if f_incid = 'LOCAL_PRESTACAO' then
        v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','aliquota_iss','mensagem',format('Aliquota de ISS do subitem %s no municipio %s (local da obra) nao cadastrada; confirme na prefeitura e cadastre em f.nfse_aliquota_iss antes de emitir.', f_item, v_municipio_incidencia),'rota',v_rota_perfil));
      end if;
      f_aliq_iss := coalesce(v_perfil.aliquota_iss, v_fx.aliquota_iss);
    end if;
    select t.federal_pct, t.municipal_pct, t.estadual_pct into f_pct_fed, f_pct_mun, f_pct_est
    from f.nfse_tributos_aproximados t
    where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.item_servico = f_item and t.vigencia_inicio <= coalesce(v_competencia, current_date)
    order by t.vigencia_inicio desc limit 1;
    if not found then f_pct_fed := v_perfil.tributos_aprox_federal_pct; f_pct_mun := v_perfil.tributos_aprox_municipal_pct; f_pct_est := 0; end if;
  end if;

  v_justificativa := nullif(btrim(coalesce(p_operacao->>'retencao_justificativa', '')), '');
  v_iss_override := case when jsonb_typeof(p_operacao->'iss_retido') = 'boolean' then (p_operacao->>'iss_retido')::boolean end;
  v_pcc_override := case when jsonb_typeof(p_operacao->'retem_pcc') = 'boolean' then (p_operacao->>'retem_pcc')::boolean end;
  v_irrf_override := case when jsonb_typeof(p_operacao->'retem_irrf') = 'boolean' then (p_operacao->>'retem_irrf')::boolean end;
  v_inss_override := case when jsonb_typeof(p_operacao->'retem_inss') = 'boolean' then (p_operacao->>'retem_inss')::boolean end;
  v_conserto_isolado := case when jsonb_typeof(p_operacao->'conserto_isolado') = 'boolean' then (p_operacao->>'conserto_isolado')::boolean end;
  if v_fonte is not null and v_cliente.id is not null then
    v_iss_retido := coalesce(v_iss_override, case f_iss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.iss_retido end);
    v_pcc := coalesce(v_pcc_override, case f_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end);
    v_irrf := coalesce(v_irrf_override, case f_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end);
    v_inss := coalesce(v_inss_override, case f_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end);
    if f_iss_regra = 'NUNCA' and v_iss_override is null and coalesce(v_cliente.iss_substituto_tributario, false) then
      v_iss_retido := true; v_substituto := true;
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','iss_substituto_tributario','mensagem','Tomador substituto tributario do ISS: a nota sai com o ISS retido pelo tomador (cadastro fiscal do cliente).','rota',v_rota_cliente));
    end if;
    if v_iss_retido is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','iss_retido','mensagem','ISS retido indefinido para este tomador: decida no cadastro fiscal do cliente ou aqui, com justificativa.','rota',v_rota_cliente)); end if;
    if v_pcc is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_pcc','mensagem','Retencao de PIS/COFINS/CSLL indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if v_irrf is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_irrf','mensagem','Retencao de IRRF indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if v_inss is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_inss','mensagem','Retencao de INSS indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if ((v_iss_override is not null and v_iss_override is distinct from (case f_iss_regra when 'NUNCA' then coalesce(v_cliente.iss_substituto_tributario, false) when 'SEMPRE' then true else v_cliente.iss_retido end))
        or (v_pcc_override is not null and v_pcc_override is distinct from case f_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end)
        or (v_irrf_override is not null and v_irrf_override is distinct from case f_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end)
        or (v_inss_override is not null and v_inss_override is distinct from case f_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end))
       and (v_justificativa is null or char_length(v_justificativa) < 15) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','retencao_justificativa','mensagem','Retencao diferente da regra do perfil/cadastro exige justificativa (15 caracteres ou mais), gravada na observacao.'));
    end if;
    if coalesce(v_pcc, false) and v_cliente.optante_simples is true then
      v_pcc := false; v_motivo_pcc := 'SIMPLES';
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_pcc','mensagem','Tomador optante do Simples Nacional: CRF (PIS/COFINS/CSLL) nao se aplica (Lei 10.833/2003 art. 30 §2).'));
    elsif coalesce(v_pcc, false) and v_cliente.optante_simples is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','optante_simples','mensagem','Regime do tomador nao informado: se for optante do Simples, a CRF nao se aplica.','rota',v_rota_cliente));
    end if;
  end if;

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

  for v_item in select si.* from f.solicitacao_item si where si.solicitacao_id = v_sf.id order by si.ordem loop
    v_linhas := v_linhas + 1;
    if v_item.valor_servico is null or v_item.valor_servico <= 0 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_servico','mensagem',format('Linha %s: valor do servico deve ser maior que zero.', v_item.ordem))); continue;
    end if;
    if nullif(btrim(coalesce(v_item.descricao_servico, '')), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','descricao_servico','mensagem',format('Linha %s: descricao do servico obrigatoria.', v_item.ordem))); end if;
    v_proibido := f.fn_nfse_texto_proibido(v_item.descricao_servico);
    if v_proibido is not null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','descricao_servico','mensagem',format('Linha %s: a expressao "%s" e proibida na discriminacao (define cessao de mao de obra: INSS 11%%, IRRF 1%%, CRF 4,65%%). Descreva o resultado entregue.', v_item.ordem, v_proibido)));
    end if;
    select os.* into v_os from public.ordens_servico os where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id and os.tipo_documento = 'OS' and os.id::text = v_item.origem_id;
    if not found then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','origem_id','mensagem',format('Linha %s: OS %s nao encontrada.', v_item.ordem, v_item.origem_id))); continue; end if;
    if lower(coalesce(v_os.status_fluxo, v_os.status::text, '')) = 'cancelada' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','status','mensagem',format('Linha %s: a OS %s esta cancelada.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id)); end if;
    if v_os.cliente_id is distinct from v_sf.cliente_id then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','cliente_id','mensagem',format('Linha %s: a OS %s e de outro tomador.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id)); end if;
    if lower(coalesce(v_os.status_fluxo, '')) = 'em_andamento' then v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','status_fluxo','mensagem',format('OS %s ainda em andamento.', coalesce(v_os.numero_os, v_os.id::text)))); end if;
    if v_conserto_isolado is not null and v_conserto_isolado is distinct from v_os.conserto_isolado then
      update public.ordens_servico set conserto_isolado = v_conserto_isolado, atualizado_em = now() where id = v_os.id;
      v_os.conserto_isolado := v_conserto_isolado;
    end if;
    if not coalesce(v_os.conserto_isolado, false) then v_todas_conserto := false; end if;
    v_bruto := v_bruto + v_item.valor_servico;
    v_linhas_desc := v_linhas_desc || jsonb_build_object('descricao', coalesce(v_item.descricao_servico, f_desc), 'os_numero', coalesce(v_os.numero_os, v_os.id::text));
    if not (coalesce(v_os.numero_os, v_os.id::text) = any(v_os_numeros)) then v_os_numeros := v_os_numeros || coalesce(v_os.numero_os, v_os.id::text); end if;
  end loop;
  if v_linhas = 0 then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','itens','mensagem','A solicitacao nao tem linhas.')); v_todas_conserto := false; end if;
  if coalesce(v_pcc, false) and f_excecao_conserto and v_todas_conserto then
    v_pcc := false; v_motivo_pcc := 'CONSERTO_ISOLADO';
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','conserto_isolado','mensagem','OS marcada como conserto isolado (IN RFB 2.141/2023 art. 2 §2 II): CRF nao retida nesta nota.'));
  end if;

  -- Material fornecido e incorporado a obra (LC 116/2003 art. 7 §2 I): sai da base do ISS e do INSS.
  begin
    v_deducao := round(coalesce(nullif(btrim(coalesce(p_operacao->>'valor_deducao_material', '')), '')::numeric, 0), 2);
  exception when others then
    v_deducao := 0;
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','valor_deducao_material','mensagem','Valor de material invalido.'));
  end;
  if v_deducao < 0 then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','valor_deducao_material','mensagem','Valor de material nao pode ser negativo.')); end if;
  if v_deducao > 0 and not v_permite_deducao then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','permite_deducao_material','mensagem',format('O perfil %s nao permite abater material da base: a deducao vale so para obra (07.02).', coalesce(v_perfil.codigo, '?')),'rota',v_rota_perfil));
  end if;
  if v_deducao > 0 and v_linhas > 0 and v_deducao >= v_bruto then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','valor_deducao_material','mensagem','O material deduzido precisa ser menor que o valor total do servico.'));
  end if;
  if v_deducao > 0 and v_permite_deducao then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','valor_deducao_material','mensagem','Material deduzido da base do ISS e do INSS (LC 116/2003 art. 7 §2 I): o contrato precisa prever o fornecimento e o material sair do estoque conforme orientacao do contador (remessa).'));
  end if;

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
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os_total.os_id,'campo','valor_servico','mensagem',format('OS %s: total das linhas %s acima do saldo da OS %s.', v_os_total.os_id, f.fn_formatar_brl(v_os_total.total), f.fn_formatar_brl(v_saldo.saldo + v_reserva_propria + v_reserva_substituida)),'rota','/os/' || v_os_total.os_id));
    end if;
  end loop;

  v_pedido := case when p_operacao ? 'pedido_cliente' then nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') else v_sf.pedido_cliente end;
  v_pedido_item := nullif(btrim(coalesce(p_operacao->>'pedido_item', '')), '');
  v_observacao := nullif(btrim(coalesce(p_operacao->>'observacao', '')), '');
  if v_pedido is null then v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','pedido_cliente','mensagem','Sem pedido de compra do tomador.')); end if;
  if f.fn_nfse_texto_proibido(v_observacao) is not null then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','observacao','mensagem','A expressao MAO DE OBRA e proibida na observacao da nota.'));
  end if;

  if jsonb_array_length(v_pend) > 0 then
    update f.solicitacao_faturamento set emitente_snapshot = null, destinatario_snapshot = null, operacao_snapshot = null, snapshot_cadastro_em = null,
        revisao_fiscal_confirmada_em = null, revisao_fiscal_confirmada_por = null, updated_at = now() where id = v_sf.id;
    return jsonb_build_object('ok', false, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente, 'pendencias', v_pend, 'avisos', v_avisos);
  end if;

  -- Bases: ISS e INSS sobre servico - material; IRRF e CRF sobre o valor integral.
  v_base_iss := v_bruto - v_deducao;
  v_base_inss := v_bruto - v_deducao;
  v_valor_iss := round(v_base_iss * f_aliq_iss / 100, 2);
  v_v_irrf := case when v_irrf then round(v_bruto * coalesce(f_aliq_irrf, 0) / 100, 2) else 0 end;
  v_v_pcc := case when v_pcc then round(v_bruto * coalesce(f_aliq_pcc, 0) / 100, 2) else 0 end;
  v_v_inss := case when v_inss then round(v_base_inss * coalesce(f_aliq_inss, 0) / 100, 2) else 0 end;
  if v_irrf and v_v_irrf <= 10 then v_irrf := false; v_v_irrf := 0; v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_irrf','mensagem','IRRF dispensado: valor retido <= R$ 10,00 (Lei 9.430/1996 art. 67).')); end if;
  if v_pcc and v_v_pcc <= 10 then v_pcc := false; v_v_pcc := 0; v_motivo_pcc := coalesce(v_motivo_pcc, 'MINIMO'); v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_pcc','mensagem','CRF dispensada: valor retido <= R$ 10,00 (Lei 10.833/2003 art. 31 §3).')); end if;
  if v_inss and v_v_inss <= 10 then v_inss := false; v_v_inss := 0; v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_inss','mensagem','INSS dispensado: valor retido <= R$ 10,00.')); end if;
  v_liquido := v_bruto - (case when v_iss_retido then v_valor_iss else 0 end) - v_v_irrf - v_v_pcc - v_v_inss;
  if v_iss_retido then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'ISS', 'base', v_base_iss, 'aliquota', f_aliq_iss, 'valor', v_valor_iss); end if;
  if v_irrf then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'IRRF', 'base', v_bruto, 'aliquota', f_aliq_irrf, 'valor', v_v_irrf); end if;
  if v_pcc then
    v_retencoes := v_retencoes
      || jsonb_build_object('tributo', 'PIS', 'base', v_bruto, 'aliquota', 0.65, 'valor', round(v_bruto * 0.65 / 100, 2))
      || jsonb_build_object('tributo', 'COFINS', 'base', v_bruto, 'aliquota', 3.00, 'valor', round(v_bruto * 3.00 / 100, 2))
      || jsonb_build_object('tributo', 'CSLL', 'base', v_bruto, 'aliquota', 1.00, 'valor', v_v_pcc - round(v_bruto * 0.65 / 100, 2) - round(v_bruto * 3.00 / 100, 2));
  end if;
  if v_inss then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'INSS', 'base', v_base_inss, 'aliquota', f_aliq_inss, 'valor', v_v_inss); end if;
  v_tem_federal := v_irrf or v_pcc or v_inss;
  v_ibs_base := v_bruto - v_valor_iss;
  v_ibs_uf := f.fn_round_half_even(v_ibs_base * coalesce(f_ibs_uf, 0) / 100, 2);
  v_ibs_mun := f.fn_round_half_even(v_ibs_base * coalesce(f_ibs_mun, 0) / 100, 2);
  v_cbs := f.fn_round_half_even(v_ibs_base * coalesce(f_cbs, 0) / 100, 2);
  v_vtottrib := round(v_bruto * (coalesce(f_pct_fed, 0) + coalesce(f_pct_mun, 0) + coalesce(f_pct_est, 0)) / 100, 2);

  v_frase_motivo := case
    when f_pcc_regra = 'SEMPRE' and v_motivo_pcc = 'CONSERTO_ISOLADO' then 'Serviço de conserto isolado não sujeito à retenção de PIS/COFINS/CSLL, conforme art. 2º, § 2º, inciso II, da IN RFB nº 2.141/2023.'
    when f_pcc_regra = 'SEMPRE' and v_motivo_pcc = 'SIMPLES' then 'Tomador optante pelo Simples Nacional: dispensada a retenção de PIS/COFINS/CSLL, conforme IN RFB nº 2.141/2023.'
    when f_pcc_regra = 'SEMPRE' and v_motivo_pcc = 'MINIMO' then 'Retenção de PIS/COFINS/CSLL dispensada: valor igual ou inferior a R$ 10,00, conforme IN RFB nº 2.141/2023.'
    else null end;
  v_texto_retencao := case when v_tem_federal then coalesce(f_texto_com, f_texto_sem) else coalesce(v_frase_motivo, f_texto_sem, f_texto_com) end;
  v_texto_retencao := replace(coalesce(v_texto_retencao, ''), '{VTOTTRIB}', f.fn_formatar_brl(v_vtottrib));
  v_obs_composta := concat_ws(' ', v_observacao,
    case when v_justificativa is not null then 'RETENCAO AJUSTADA: ' || v_justificativa end);
  v_discriminacao := f.fn_nfse_discriminacao(v_linhas_desc, v_pedido, v_pedido_item, v_parcelas, current_date, v_iss_retido, nullif(v_texto_retencao, ''),
    nullif(v_obs_composta, ''), v_cliente.nfse_discriminacao_template, v_deducao);
  v_proibido := f.fn_nfse_texto_proibido(v_discriminacao);
  if v_proibido is not null then
    update f.solicitacao_faturamento set emitente_snapshot = null, destinatario_snapshot = null, operacao_snapshot = null, snapshot_cadastro_em = null, updated_at = now() where id = v_sf.id;
    return jsonb_build_object('ok', false, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente,
      'pendencias', jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','descricao_servico','mensagem','A discriminacao composta contem "' || v_proibido || '" (proibido).')), 'avisos', v_avisos);
  end if;

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
      valor_deducao_material = nullif(v_deducao, 0),
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
        'codigo_municipio_ibge', v_sede_ibge, 'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')),
      destinatario_snapshot = jsonb_build_object(
        'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social, 'inscricao_municipal', nullif(btrim(coalesce(v_cliente.inscricao_municipal, '')), ''),
        'email', coalesce(nullif(btrim(coalesce(v_cliente.email_nfse, '')), ''), nullif(btrim(coalesce(v_cliente.email_financeiro, '')), '')),
        'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro, 'numero_endereco', v_cliente.numero_endereco, 'complemento', v_cliente.complemento,
        'bairro', v_cliente.bairro, 'cidade', v_cliente.cidade, 'uf', upper(v_cliente.uf), 'optante_simples', v_cliente.optante_simples, 'iss_substituto_tributario', coalesce(v_cliente.iss_substituto_tributario, false),
        'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'), 'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')),
      operacao_snapshot = jsonb_build_object(
        'natureza_operacao', 'PRESTACAO_SERVICO', 'modelo', 'NFSE', 'tributacao_fonte', v_fonte, 'consumidor_final', v_consumidor_final,
        'servico', jsonb_build_object(
          'perfil_operacao_id', v_perfil.id, 'perfil_codigo', v_perfil.codigo, 'item_servico', f_item,
          'codigo_tributacao_nacional', f_ctrib, 'codigo_tributacao_municipal', f_ctrib_mun, 'codigo_nbs', f_nbs,
          'municipio_prestacao_ibge', v_municipio, 'municipio_incidencia_iss', v_municipio_incidencia, 'data_competencia', v_competencia,
          'tributacao_iss', f_trib_iss, 'aliquota_iss', f_aliq_iss, 'iss_retido', v_iss_retido, 'iss_substituto_tributario', v_substituto,
          'retem_pcc', v_pcc, 'retem_irrf', v_irrf, 'retem_inss', v_inss, 'motivo_dispensa_pcc', v_motivo_pcc,
          'conserto_isolado', (f_excecao_conserto and v_todas_conserto),
          'valor_bruto', v_bruto, 'valor_deducoes', v_deducao, 'base_iss', v_base_iss, 'base_inss', v_base_inss,
          'valor_iss', v_valor_iss, 'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss, 'valor_liquido', v_liquido, 'retencoes', v_retencoes,
          'cst_pis_cofins', f_cst_pis, 'aliquota_pis', f_aliq_pis, 'aliquota_cofins', f_aliq_cofins,
          'cst_ibs_cbs', f_cst_ibs, 'cclass_trib', f_cclass, 'ibs_uf_aliquota', f_ibs_uf, 'ibs_mun_aliquota', f_ibs_mun, 'cbs_aliquota', f_cbs,
          'ibs_cbs', jsonb_build_object('base', v_ibs_base, 'ibs_uf', v_ibs_uf, 'ibs_mun', v_ibs_mun, 'cbs', v_cbs, 'total', v_ibs_uf + v_ibs_mun + v_cbs, 'municipio_incidencia', v_municipio),
          'codigo_indicador_operacao', f_cindop, 'tributos_aprox_federal_pct', f_pct_fed, 'tributos_aprox_municipal_pct', f_pct_mun, 'tributos_aprox_estadual_pct', coalesce(f_pct_est, 0), 'tributos_aprox_valor', v_vtottrib,
          'descricao_servico', v_discriminacao, 'texto_retencao', nullif(v_texto_retencao, ''), 'os_numeros', to_jsonb(v_os_numeros)),
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
      'item_servico', f_item, 'codigo_tributacao_nacional', f_ctrib, 'codigo_nbs', f_nbs, 'municipio_prestacao_ibge', v_municipio, 'municipio_incidencia_iss', v_municipio_incidencia, 'data_competencia', v_competencia,
      'valor_bruto', v_bruto, 'valor_deducoes', v_deducao, 'base_iss', v_base_iss, 'base_inss', v_base_inss,
      'aliquota_iss', f_aliq_iss, 'valor_iss', v_valor_iss, 'iss_retido', v_iss_retido, 'iss_substituto_tributario', v_substituto,
      'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss, 'valor_liquido', v_liquido, 'motivo_dispensa_pcc', v_motivo_pcc,
      'ibs_cbs', jsonb_build_object('base', v_ibs_base, 'ibs_uf', v_ibs_uf, 'ibs_mun', v_ibs_mun, 'cbs', v_cbs, 'total', v_ibs_uf + v_ibs_mun + v_cbs),
      'tributos_aprox', jsonb_build_object('federal_pct', f_pct_fed, 'municipal_pct', f_pct_mun, 'federal', round(v_bruto * coalesce(f_pct_fed, 0) / 100, 2), 'municipal', round(v_bruto * coalesce(f_pct_mun, 0) / 100, 2), 'total', v_vtottrib),
      'retencoes', v_retencoes, 'parcelas', v_parcelas, 'descricao_servico', v_discriminacao, 'tributacao_fonte', v_fonte,
      'campos_conferir', v_perfil.campos_conferir));
end;
$$;

