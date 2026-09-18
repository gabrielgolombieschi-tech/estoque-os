-- Retorno de terceiros em linguagem simples (pedido do Gabriel em 18/09/2026). Principio para o ERP:
-- codigo fiscal nunca aparece sozinho; a pessoa escolhe a situacao e o sistema deriva o codigo.
--   1. f.perfil_operacao.rotulo_usuario / legenda_usuario: texto da opcao e exemplo curto, lidos pela tela.
--   2. Perfil SEG-RETORNO-TERCEIROS-5903-O0-CST50 (retorno de material nao aplicado), copia do 5902 com
--      CFOP 5903: ICMS 50/SC840008, IPI 55/109, PIS/COFINS 08, IBS/CBS 410/410999; producao desabilitada
--      (o Gabriel revisa e libera). natOp cabe em 60 caracteres (leiaute): "RETORNO DE MERCADORIA P/
--      INDUSTRIALIZACAO NAO APLICADA"; o texto completo pedido vai no infCpl (montador).
--   3. fn_remessa_terceiros_retorno_criar ganha p_situacao (USADO -> 5902, NAO_USADO -> 5903, no conserto
--      CONSERTADO -> 5916; 6xxx fora da UF). PARCIAL e recusado no banco. p_cfop continua aceito (testes,
--      chamadas antigas) e passa a ter padrao nulo; a assinatura de cinco parametros sai.
-- Reversao: drop das colunas e do perfil 5903 (e da evidencia 4c0a5e1e-...-5903a0000001); funcao de 160000.

alter table f.perfil_operacao add column if not exists rotulo_usuario text;
alter table f.perfil_operacao add column if not exists legenda_usuario text;
comment on column f.perfil_operacao.rotulo_usuario is 'Opcao em linguagem simples mostrada na tela no lugar do codigo fiscal (ex.: "Foi usado no produto").';
comment on column f.perfil_operacao.legenda_usuario is 'Exemplo curto que acompanha o rotulo (ex.: "Ex.: tinta aplicada, peca montada.").';

do $perfis$
declare
  v_5902 f.perfil_operacao%rowtype;
  v_5903_id uuid := 'a6e1c3d2-5903-4c50-9a2b-000000000001';
  v_ev_5903 uuid := '4c0a5e1e-9f0b-4c7a-9b2e-5903a0000001';
begin
  select * into v_5902 from f.perfil_operacao where codigo = 'SEG-RETORNO-TERCEIROS-5902-O0-CST50' and modelo = 'NFE';
  if not found then
    raise notice 'assert pulado: perfil SEG-RETORNO-TERCEIROS-5902-O0-CST50 ausente neste banco';
    return;
  end if;

  update f.perfil_operacao
     set rotulo_usuario = 'Foi usado no produto',
         legenda_usuario = 'Ex.: tinta aplicada, peça montada. O material volta dentro do produto.'
   where id = v_5902.id;

  if exists (select 1 from f.perfil_operacao where codigo = 'SEG-RETORNO-TERCEIROS-5903-O0-CST50') then
    update f.perfil_operacao
       set rotulo_usuario = 'Voltou sem usar', legenda_usuario = 'Ex.: lata fechada, sobra devolvida como veio.'
     where codigo = 'SEG-RETORNO-TERCEIROS-5903-O0-CST50';
    raise notice 'perfil 5903 ja existia: so as legendas';
    return;
  end if;

  -- Evidencia do 5903 (copia da do 5902, mesma fonte, linha 5903), depois o perfil, depois o vinculo.
  insert into f.perfil_operacao_evidencia
  select (jsonb_populate_record(null::f.perfil_operacao_evidencia, to_jsonb(ev) || jsonb_build_object(
    'id', v_ev_5903, 'cfop', '5903', 'fonte_linha', 5903, 'perfil_operacao_id', null, 'created_at', now(),
    'leitura_operacional', 'Retorno de mercadoria de terceiros recebida para industrializacao por encomenda e NAO aplicada no processo (volta como veio): espelho da nota de origem, ICMS 50 com SC840008 (Anexo 2, Art. 27, II), IPI 55 cEnq 109, PIS/COFINS 08, IBS/CBS 410/410999, tPag 90. Perfil criado em 18/09/2026, a revisar e liberar.',
    'justificativa_faixa', 'Perfil 5903 criado em 18/09/2026: homologar, revisar e liberar antes da producao.'
  ))).*
  from f.perfil_operacao_evidencia ev where ev.id = v_5902.evidencia_id;

  insert into f.perfil_operacao
  select (jsonb_populate_record(null::f.perfil_operacao, to_jsonb(p) || jsonb_build_object(
    'id', v_5903_id,
    'codigo', 'SEG-RETORNO-TERCEIROS-5903-O0-CST50',
    'nome', 'SEG - retorno de mercadoria de terceiros nao aplicada (industrializacao) em SC - CFOP 5903 - origem 0 - CST 50',
    'cfop_interno', '5903',
    'natureza_texto', 'RETORNO DE MERCADORIA P/ INDUSTRIALIZACAO NAO APLICADA',
    'rotulo_usuario', 'Voltou sem usar',
    'legenda_usuario', 'Ex.: lata fechada, sobra devolvida como veio.',
    'evidencia_id', v_ev_5903,
    'habilitado_producao', false,
    'revisao_fiscal_em', null, 'revisao_fiscal_por', null, 'revisao_fiscal_justificativa', null,
    'producao_decidida_em', null, 'producao_decidida_por', null, 'producao_decisao_justificativa', null,
    'producao_homologacao_solicitacao_id', null, 'producao_homologacao_documento_id', null,
    'created_at', now(),
    'observacao', 'Retorno de mercadoria de terceiros recebida para industrializacao e nao aplicada (CFOP 5903). Mesma tributacao do 5902: ICMS 50/SC840008, IPI 55/109, PIS/COFINS 08, IBS/CBS 410/410999. natOp no limite de 60 caracteres do leiaute; o texto completo vai no infCpl.',
    'justificativa_faixa', 'Perfil 5903 criado em 18/09/2026: homologar, revisar e liberar antes da producao.'
  ))).*
  from f.perfil_operacao p where p.id = v_5902.id;

  update f.perfil_operacao_evidencia set perfil_operacao_id = v_5903_id where id = v_ev_5903;
  raise notice 'perfil SEG-RETORNO-TERCEIROS-5903-O0-CST50 criado (producao desabilitada); legendas do 5902 e do 5903 gravadas';
end;
$perfis$;

-- fn_remessa_terceiros_retorno_criar (de 20260918160000) com p_situacao; a assinatura antiga sai.
drop function if exists f.fn_remessa_terceiros_retorno_criar(uuid, text, smallint, text, jsonb);
create or replace function f.fn_remessa_terceiros_retorno_criar(p_remessa_id uuid, p_cfop text default null, p_modalidade_frete smallint default 0, p_observacao text default null, p_volumes jsonb default null, p_situacao text default null)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_scope record;
  v_rem f.remessas_terceiros%rowtype;
  v_cfg jsonb := f.fn_retorno_terceiros_config();
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_uf_emitente text;
  v_uf_destino text;
  v_ambito text;
  v_cfop text := regexp_replace(coalesce(p_cfop, ''), '[^0-9]', '', 'g');
  v_situacao text := nullif(upper(btrim(coalesce(p_situacao, ''))), '');
  v_permitidos text[];
  v_cliente_id integer;
  v_perfil_id uuid;
  v_op_id uuid := gen_random_uuid();
  v_sol_id uuid := gen_random_uuid();
  v_volumes jsonb;
  v_item record;
  v_total numeric(14,2) := 0;
  v_indicador_ie text;
  v_natureza text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_rem from f.remessas_terceiros r
  where r.tenant_id = v_scope.tenant_id and r.empresa_id = v_scope.empresa_id and r.id = p_remessa_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Remessa de terceiros nao encontrada.';
  end if;
  v_natureza := coalesce(v_cfg#>>array['naturezas', v_rem.tipo, 'codigo'], v_cfg#>>'{naturezas,INDUSTRIALIZACAO,codigo}');
  if v_rem.status <> 'ABERTA' then
    raise exception using errcode = '22023', message = format('Remessa %s: so remessa ABERTA gera retorno.', v_rem.status);
  end if;
  if p_modalidade_frete is null or p_modalidade_frete not in (0, 1, 3, 4, 9) then
    raise exception using errcode = '22023', message = 'Modalidade do frete deve ser 0, 1, 3, 4 ou 9.';
  end if;

  select * into v_empresa from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id and e.deleted_at is null;
  select * into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  select * into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
  if v_endereco.id is null or v_fiscal.id is null then
    raise exception using errcode = '22023', message = 'Cadastro fiscal do emitente incompleto (endereco ou dados fiscais).';
  end if;
  v_uf_emitente := upper(v_endereco.uf::text);
  v_uf_destino := upper(coalesce(v_rem.emitente_endereco->>'uf', ''));
  if v_uf_destino !~ '^[A-Z]{2}$' then
    raise exception using errcode = '22023', message = 'O XML da remessa nao traz a UF do remetente.';
  end if;
  v_ambito := case when v_uf_destino = v_uf_emitente then 'INTERNA' else 'INTERESTADUAL' end;

  -- CFOP de retorno: 5902/5903 para industrializacao (5901/6901), 5916/5903 para conserto
  -- (5915/6915); fora do estado do remetente, o 6xxx equivalente.
  v_permitidos := case v_rem.tipo
    when 'INDUSTRIALIZACAO' then array['5902', '5903']
    when 'CONSERTO' then array['5916', '5903']
    else array['5903'] end;
  if v_ambito = 'INTERESTADUAL' then
    v_permitidos := array(select '6' || substr(c, 2) from unnest(v_permitidos) c);
  end if;
  -- Situacao em linguagem simples (tela): o sistema deriva o CFOP. O retorno parcial e recusado aqui,
  -- nao so na tela.
  if v_situacao is not null then
    if v_situacao = 'PARCIAL' then
      raise exception using errcode = '22023', message = 'Retorno parcial (parte usada, parte devolvida) ainda nao esta disponivel. Fale com o responsavel fiscal.';
    end if;
    v_cfop := case
      when v_rem.tipo = 'INDUSTRIALIZACAO' and v_situacao = 'USADO' then '5902'
      when v_rem.tipo = 'INDUSTRIALIZACAO' and v_situacao = 'NAO_USADO' then '5903'
      when v_rem.tipo = 'CONSERTO' and v_situacao = 'CONSERTADO' then '5916'
      when v_rem.tipo = 'CONSERTO' and v_situacao = 'NAO_USADO' then '5903'
      else null end;
    if v_cfop is null then
      raise exception using errcode = '22023', message = format('Situacao %s nao vale para remessa de %s (use USADO, NAO_USADO ou, no conserto, CONSERTADO).', v_situacao, v_rem.tipo);
    end if;
    if v_ambito = 'INTERESTADUAL' then
      v_cfop := '6' || substr(v_cfop, 2);
    end if;
  end if;
  if not (v_cfop = any(v_permitidos)) then
    raise exception using errcode = '22023', message = format('CFOP %s nao vale para este retorno (%s, %s). Use %s.', coalesce(nullif(v_cfop, ''), 'vazio'), v_rem.tipo, v_ambito, array_to_string(v_permitidos, ' ou '));
  end if;

  -- Volumes: da tela quando informados; senao os da origem; senao nenhum (nao bloqueia).
  v_volumes := case
    when jsonb_typeof(p_volumes) = 'array' and jsonb_array_length(p_volumes) > 0 then p_volumes
    else coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'quantidade', coalesce((v->>'qVol')::integer, 1), 'especie', v->>'esp', 'marca', v->>'marca', 'numero', v->>'nVol',
        'peso_liquido', coalesce((v->>'pesoL')::numeric, 0), 'peso_bruto', coalesce((v->>'pesoB')::numeric, (v->>'pesoL')::numeric, 0)
      )))
      from jsonb_array_elements(coalesce(v_rem.transporte_origem->'volumes', '[]'::jsonb)) v
    ), '[]'::jsonb) end;
  if p_modalidade_frete = 9 then v_volumes := '[]'::jsonb; end if;

  -- Cliente so para a listagem, se o CNPJ existir no cadastro; o destinatario da nota vem do XML.
  select c.id into v_cliente_id
  from public.clientes c
  where c.tenant_id = v_scope.tenant_id and c.empresa_id = v_scope.empresa_id
    and regexp_replace(coalesce(c.documento, ''), '[^0-9]', '', 'g') = v_rem.emitente_cnpj and c.ativo
  order by c.id limit 1;
  v_indicador_ie := case when v_rem.emitente_ie is not null then '1' else '9' end;

  -- Perfil de operacao, se existir: so importa para a producao (portoes de perfil).
  select po.id into v_perfil_id
  from f.perfil_operacao po
  where po.tenant_id = v_scope.tenant_id and (po.empresa_id = v_scope.empresa_id or po.empresa_id is null)
    and po.modelo = 'NFE' and po.natureza_operacao = v_natureza and po.ambito_destino = v_ambito
    and coalesce(case when v_ambito = 'INTERNA' then po.cfop_interno else po.cfop_externo end, '') = v_cfop
    and po.faixa_automacao <> 'BLOQUEADO' and po.vigencia_inicio <= current_date and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
  order by po.habilitado_producao desc, po.revisao_fiscal_em desc nulls last
  limit 1;

  -- Retorno anterior ainda sem producao sai do caminho.
  update f.operacao_fiscal o
     set status = 'CANCELADA', updated_at = now()
   where o.tenant_id = v_scope.tenant_id and o.empresa_id = v_scope.empresa_id and o.deleted_at is null
     and o.tipo = 'RETORNO' and o.dados_json->>'remessa_terceiros_id' = v_rem.id::text
     and o.status not in ('CONCLUIDA', 'CANCELADA')
     and not exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = o.solicitacao_id and e.ambiente = 'PRODUCAO' and e.status not in ('REJEITADA', 'ERRO'));
  update f.solicitacao_faturamento sf
     set status = 'CANCELADA', updated_at = now()
   where sf.tenant_id = v_scope.tenant_id and sf.empresa_id = v_scope.empresa_id
     and sf.natureza_operacao like 'RETORNO_REMESSA_TERCEIROS%' and sf.status not in ('EMITIDA', 'CANCELADA')
     and sf.id in (select o.solicitacao_id from f.operacao_fiscal o where o.dados_json->>'remessa_terceiros_id' = v_rem.id::text and o.status = 'CANCELADA');

  insert into f.operacao_fiscal (
    id, tenant_id, empresa_id, tipo, finalidade, status, ambiente, nfe_referenciada,
    cfop_proposto, cfop_confirmado, cfop_confirmado_em, cfop_confirmado_por, destinatario_id, entrega_json,
    justificativa_fisco, criado_por, preparado_homologacao_em, dados_json, perfil_operacao_id
  ) values (
    v_op_id, v_scope.tenant_id, v_scope.empresa_id, 'RETORNO', v_rem.tipo, 'PRONTO_HOMOLOGACAO', 'HOMOLOGACAO', v_rem.chave,
    v_cfop, v_cfop, now(), v_scope.usuario_id, v_cliente_id,
    jsonb_build_object('documento', v_rem.emitente_cnpj, 'nome', v_rem.emitente_nome, 'uf', v_uf_destino),
    nullif(btrim(coalesce(p_observacao, '')), ''), v_scope.usuario_id, now(),
    jsonb_build_object('remessa_terceiros_id', v_rem.id, 'natureza_operacao', v_natureza, 'ambito', v_ambito,
      'perfil_codigo', (select po.codigo from f.perfil_operacao po where po.id = v_perfil_id), 'chave_origem', v_rem.chave, 'remessa_teste', v_rem.is_teste, 'situacao', v_situacao),
    v_perfil_id
  );

  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, natureza_operacao, observacao, criado_por,
    finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
    valor_frete, valor_seguro, valor_outras_despesas,
    destino_uf_confirmada, destino_confirmado_em, destino_confirmado_por,
    pagamento_forma, pagamento_indicador, pagamento_parcelas, transportador_dados, volumes_dados,
    revisao_fiscal_confirmada_em, revisao_fiscal_confirmada_por, perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por,
    emitente_snapshot, destinatario_snapshot, operacao_snapshot, snapshot_cadastro_em
  ) values (
    v_sol_id, v_scope.tenant_id, v_scope.empresa_id, v_cliente_id, 'PREVIA', v_natureza,
    nullif(btrim(coalesce(p_observacao, '')), ''), v_scope.usuario_id,
    1, 0, 9, p_modalidade_frete,
    0, 0, 0,
    v_uf_destino, now(), v_scope.usuario_id,
    '90', 0, null, null, case when jsonb_array_length(v_volumes) > 0 then v_volumes end,
    now(), v_scope.usuario_id, v_perfil_id, case when v_perfil_id is null then null else now() end, case when v_perfil_id is null then null else v_scope.usuario_id end,
    jsonb_build_object(
      'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
      'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
      'telefone', v_empresa.telefone, 'inscricao_estadual', v_fiscal.inscricao_estadual,
      'crt', v_fiscal.crt, 'serie_nfe', v_fiscal.serie_nfe,
      'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero,
      'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro,
      'cidade', coalesce((select mi.nome from public.municipios_ibge mi where mi.codigo_ibge = regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g')), v_endereco.cidade),
      'uf', v_uf_emitente,
      'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'),
      'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')
    ),
    -- Destinatario = emitente da nota de origem, do XML. Nunca do cadastro.
    jsonb_build_object(
      'id', v_cliente_id, 'documento', v_rem.emitente_cnpj, 'nome', v_rem.emitente_nome,
      'inscricao_estadual', v_rem.emitente_ie, 'indicador_ie', v_indicador_ie,
      'email', null, 'telefone', v_rem.emitente_endereco->>'telefone',
      'logradouro', v_rem.emitente_endereco->>'logradouro', 'numero_endereco', coalesce(v_rem.emitente_endereco->>'numero', 'S/N'),
      'complemento', v_rem.emitente_endereco->>'complemento', 'bairro', v_rem.emitente_endereco->>'bairro',
      'cidade', coalesce((select mi.nome from public.municipios_ibge mi where mi.codigo_ibge = v_rem.emitente_endereco->>'codigo_ibge_municipio'), v_rem.emitente_endereco->>'cidade'),
      'uf', v_uf_destino,
      'codigo_ibge_municipio', v_rem.emitente_endereco->>'codigo_ibge_municipio',
      'cep', regexp_replace(coalesce(v_rem.emitente_endereco->>'cep', ''), '[^0-9]', '', 'g')
    ),
    jsonb_build_object(
      'natureza_operacao', v_natureza, 'finalidade_emissao', 1, 'consumidor_final', 0, 'presenca_comprador', 9,
      'modalidade_frete', p_modalidade_frete, 'valor_frete', 0, 'valor_seguro', 0, 'valor_outras_despesas', 0,
      'destinacao_mercadoria', null, 'nfe_referenciada', v_rem.chave,
      'pagamento', jsonb_build_object('forma', '90', 'indicador', 0, 'descricao', null, 'parcelas', null, 'fatura_numero', null),
      'retorno_terceiros', jsonb_build_object('teste', v_rem.is_teste, 'situacao', v_situacao, 
        'remessa_id', v_rem.id, 'chave', v_rem.chave, 'numero', v_rem.numero, 'serie', v_rem.serie,
        'dh_emi', v_rem.dh_emi, 'data_emissao', to_char(v_rem.dh_emi at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
        'cfop_origem', v_rem.cfop_origem, 'tipo', v_rem.tipo, 'emitente_nome', v_rem.emitente_nome
      )
    ),
    now()
  );

  for v_item in
    select * from f.remessas_terceiros_itens i where i.remessa_id = v_rem.id order by i.n_item
  loop
    insert into f.solicitacao_item (
      id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, origem_item_id, item_id, descricao, ncm, cest, cfop,
      cst_icms, csosn, cbenef, reducao_base_icms_percentual, aliquota_icms, icms_modalidade_base_calculo,
      cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins, aliquota_pis, aliquota_cofins,
      cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json,
      quantidade, unidade, unidade_tributavel, valor_unitario, valor_desconto, ordem, codigo_produto, origem_mercadoria,
      perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por, tributacao_fonte, modelo
    ) values (
      gen_random_uuid(), v_sol_id, v_scope.tenant_id, v_scope.empresa_id, 'RETORNO_TERCEIROS', v_rem.id::text, v_item.id::text, null,
      v_item.x_prod, v_item.ncm, v_item.cest, v_cfop,
      v_cfg->>'cst_icms', null, v_cfg->>'cbenef_retorno_sc', 0, null, null,
      v_cfg->>'cst_ipi', v_cfg->>'cenq_ipi_retorno', null, v_cfg->>'cst_pis_cofins', v_cfg->>'cst_pis_cofins', null, null,
      v_cfg->>'cst_ibs_cbs', v_cfg->>'cclass_trib', v_cfg->>'cclass_trib_versao',
      jsonb_build_object('ibs_uf_aliquota', 0, 'ibs_mun_aliquota', 0, 'cbs_aliquota', 0),
      v_item.q_com, v_item.u_com, v_item.u_com, v_item.v_un_com, 0, v_item.n_item, v_item.c_prod, coalesce(v_item.orig, 0),
      v_perfil_id, case when v_perfil_id is null then null else now() end, case when v_perfil_id is null then null else v_scope.usuario_id end,
      case when v_perfil_id is null then null else 'PERFIL' end, 'NFE'
    );
    v_total := v_total + v_item.v_prod;
  end loop;

  update f.operacao_fiscal set valor_total = v_total, solicitacao_id = v_sol_id where id = v_op_id;
  update f.remessas_terceiros
     set solicitacao_retorno_id = v_sol_id, cfop_retorno = v_cfop,
         obs = nullif(btrim(coalesce(p_observacao, '')), ''), updated_at = now()
   where id = v_rem.id;

  return jsonb_build_object(
    'operacao_id', v_op_id, 'solicitacao_id', v_sol_id, 'cfop', v_cfop, 'ambito', v_ambito, 'natureza_operacao', v_natureza,
    'valor_total', v_total, 'itens', (select count(*) from f.remessas_terceiros_itens i where i.remessa_id = v_rem.id),
    'perfil_id', v_perfil_id, 'cliente_id', v_cliente_id, 'teste', v_rem.is_teste, 'situacao', v_situacao
  );
end;
$function$;

revoke all on function f.fn_remessa_terceiros_retorno_criar(uuid, text, smallint, text, jsonb, text) from public, anon;
grant execute on function f.fn_remessa_terceiros_retorno_criar(uuid, text, smallint, text, jsonb, text) to authenticated, service_role;

do $assert$
begin
  if to_regprocedure('f.fn_remessa_terceiros_retorno_criar(uuid, text, smallint, text, jsonb)') is not null then
    raise exception 'assinatura antiga de fn_remessa_terceiros_retorno_criar ainda existe';
  end if;
  if pg_get_functiondef('f.fn_remessa_terceiros_retorno_criar(uuid, text, smallint, text, jsonb, text)'::regprocedure) not like '%PARCIAL%' then
    raise exception 'fn_remessa_terceiros_retorno_criar nao recusa o retorno parcial';
  end if;
  if exists (select 1 from f.perfil_operacao where codigo = 'SEG-RETORNO-TERCEIROS-5902-O0-CST50')
     and not exists (select 1 from f.perfil_operacao where codigo = 'SEG-RETORNO-TERCEIROS-5903-O0-CST50' and cfop_interno = '5903' and not habilitado_producao and rotulo_usuario is not null) then
    raise exception 'perfil 5903 nao foi criado como esperado';
  end if;
end;
$assert$;

notify pgrst, 'reload schema';
