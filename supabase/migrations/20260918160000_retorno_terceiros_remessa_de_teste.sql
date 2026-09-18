-- Remessa de terceiros de TESTE de homologacao (pedido do Gabriel em 18/09/2026): re-homologar e liberar o
-- perfil SEG-RETORNO-TERCEIROS-5902-O0-CST50 (cEnq 109) sem tocar na remessa real da WEG 900356.
--   1. f.remessas_terceiros.is_teste: a importacao com p_teste aceita XML de chave ja usada e grava em linha
--      propria; a remessa real de mesma chave nunca muda (indice unico da chave passa a valer so entre as
--      reais; entre testes, um por chave).
--   2. Travas: emissao de PRODUCAO de um retorno de teste e recusada no banco (gatilho
--      aab_remessa_terceiros_teste_bloqueia_producao em f.documento_fiscal_emissao), alem da tela; o
--      gatilho de baixa (fn_remessa_terceiros_apos_retorno) so carimba a homologacao do teste; a tela lista
--      testes em secao propria (fora de "em nosso poder" e do prazo); f.v_remessas_abertas e das remessas
--      proprias e nao le esta tabela.
--   3. f.fn_remessa_terceiros_teste_excluir: cancela a solicitacao/homologacao do teste e apaga a linha.
-- O fluxo de perfil (revisar, homologar, liberar) e o normal: fn_perfil_operacao_nfe_liberar_producao nao
-- distingue teste; a liberacao vale para a solicitacao do teste, e a producao dela e bloqueada aqui.
-- Reversao: drop trigger/funcao de teste, drop column is_teste (recriar a unique da chave), funcoes de
-- 20260917100000/110000.

alter table f.remessas_terceiros add column if not exists is_teste boolean not null default false;
comment on column f.remessas_terceiros.is_teste is 'Teste de homologacao: convive com a remessa real de mesma chave, so homologa, nunca e baixada.';
alter table f.remessas_terceiros drop constraint if exists remessas_terceiros_chave_uk;
create unique index if not exists remessas_terceiros_chave_real_uk on f.remessas_terceiros (tenant_id, empresa_id, chave) where not is_teste;
create unique index if not exists remessas_terceiros_chave_teste_uk on f.remessas_terceiros (tenant_id, empresa_id, chave) where is_teste;

-- A assinatura ganha p_teste com padrao: a versao de um parametro sai para o PostgREST nao ter duas candidatas.
drop function if exists f.fn_remessa_terceiros_importar(text);

-- fn_remessa_terceiros_importar (de 20260917100000) com p_teste.
create or replace function f.fn_remessa_terceiros_importar(p_xml text, p_teste boolean default false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_scope record;
  v_doc xml;
  v_cab record;
  v_cnpj_empresa text;
  v_itens jsonb;
  v_cfops text[];
  v_tipo text;
  v_id uuid := gen_random_uuid();
  v_volumes jsonb;
  v_total numeric(14,2);
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if nullif(btrim(coalesce(p_xml, '')), '') is null then
    raise exception using errcode = '22023', message = 'Arquivo vazio.';
  end if;
  begin
    v_doc := xmlparse(document p_xml);
  exception when others then
    raise exception using errcode = '22023', message = 'Arquivo nao e um XML valido.';
  end;

  select x.* into v_cab
  from xmltable(
    xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '/n:nfeProc' passing v_doc columns
      id_infnfe text path 'n:NFe/n:infNFe/@Id',
      cstat text path 'n:protNFe/n:infProt/n:cStat',
      nprot text path 'n:protNFe/n:infProt/n:nProt',
      nnf text path 'n:NFe/n:infNFe/n:ide/n:nNF',
      serie text path 'n:NFe/n:infNFe/n:ide/n:serie',
      modelo text path 'n:NFe/n:infNFe/n:ide/n:mod',
      natop text path 'n:NFe/n:infNFe/n:ide/n:natOp',
      dhemi text path 'n:NFe/n:infNFe/n:ide/n:dhEmi',
      emit_cnpj text path 'n:NFe/n:infNFe/n:emit/n:CNPJ',
      emit_nome text path 'n:NFe/n:infNFe/n:emit/n:xNome',
      emit_ie text path 'n:NFe/n:infNFe/n:emit/n:IE',
      emit_xlgr text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:xLgr',
      emit_nro text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:nro',
      emit_xcpl text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:xCpl',
      emit_xbairro text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:xBairro',
      emit_cmun text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:cMun',
      emit_xmun text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:xMun',
      emit_uf text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:UF',
      emit_cep text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:CEP',
      emit_fone text path 'n:NFe/n:infNFe/n:emit/n:enderEmit/n:fone',
      dest_cnpj text path 'n:NFe/n:infNFe/n:dest/n:CNPJ',
      modfrete text path 'n:NFe/n:infNFe/n:transp/n:modFrete',
      vprod numeric path 'n:NFe/n:infNFe/n:total/n:ICMSTot/n:vProd',
      vnf numeric path 'n:NFe/n:infNFe/n:total/n:ICMSTot/n:vNF'
  ) x;
  if v_cab.id_infnfe is null then
    raise exception using errcode = '22023', message = 'O XML nao e uma NF-e processada (nfeProc). Envie o XML autorizado, com protocolo.';
  end if;
  if v_cab.cstat is distinct from '100' then
    raise exception using errcode = '22023', message = format('NF-e sem autorizacao (cStat %s). So entra nota autorizada.', coalesce(v_cab.cstat, 'ausente'));
  end if;
  select regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') into v_cnpj_empresa
  from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id;
  if regexp_replace(coalesce(v_cab.dest_cnpj, ''), '[^0-9]', '', 'g') is distinct from v_cnpj_empresa then
    raise exception using errcode = '22023', message = format('O destinatario da nota (%s) nao e a empresa ativa (%s).', coalesce(v_cab.dest_cnpj, 'ausente'), v_cnpj_empresa);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'n_item', i.nitem, 'c_prod', i.cprod, 'x_prod', i.xprod, 'ncm', i.ncm, 'cest', i.cest,
      'cfop', i.cfop, 'u_com', i.ucom, 'q_com', i.qcom, 'v_un_com', i.vuncom, 'v_prod', i.vprod,
      'orig', i.orig, 'icms_cst', coalesce(i.icms_cst, i.csosn), 'ipi_cst', i.ipi_cst, 'ipi_c_enq', i.cenq,
      'pis_cst', i.pis_cst, 'cofins_cst', i.cofins_cst, 'ibscbs_cst', i.ibscbs_cst, 'ibscbs_c_class_trib', i.cclass,
      'imposto_xml', i.imposto::text
    ) order by i.nitem), '[]'::jsonb),
    array_agg(distinct i.cfop)
  into v_itens, v_cfops
  from xmltable(
    xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '//n:det' passing v_doc columns
      nitem integer path '@nItem',
      cprod text path 'n:prod/n:cProd',
      xprod text path 'n:prod/n:xProd',
      ncm text path 'n:prod/n:NCM',
      cest text path 'n:prod/n:CEST',
      cfop text path 'n:prod/n:CFOP',
      ucom text path 'n:prod/n:uCom',
      qcom numeric path 'n:prod/n:qCom',
      vuncom numeric path 'n:prod/n:vUnCom',
      vprod numeric path 'n:prod/n:vProd',
      orig smallint path 'n:imposto/n:ICMS/*/n:orig',
      icms_cst text path 'n:imposto/n:ICMS/*/n:CST',
      csosn text path 'n:imposto/n:ICMS/*/n:CSOSN',
      ipi_cst text path 'n:imposto/n:IPI/*/n:CST',
      cenq text path 'n:imposto/n:IPI/n:cEnq',
      pis_cst text path 'n:imposto/n:PIS/*/n:CST',
      cofins_cst text path 'n:imposto/n:COFINS/*/n:CST',
      ibscbs_cst text path 'n:imposto/n:IBSCBS/n:CST',
      cclass text path 'n:imposto/n:IBSCBS/n:cClassTrib',
      imposto xml path 'n:imposto'
  ) i;
  if jsonb_array_length(v_itens) = 0 then
    raise exception using errcode = '22023', message = 'A NF-e nao tem itens legiveis.';
  end if;
  if exists (select 1 from unnest(v_cfops) c where c not in ('5901', '6901', '5915', '6915')) then
    raise exception using errcode = '22023', message = format(
      'Nao e remessa de terceiros: CFOP %s. Entram so 5901/6901 (industrializacao) e 5915/6915 (conserto).',
      array_to_string(v_cfops, ', '));
  end if;
  v_tipo := case when v_cfops[1] in ('5901', '6901') then 'INDUSTRIALIZACAO' when v_cfops[1] in ('5915', '6915') then 'CONSERTO' else 'OUTRO' end;
  -- Chave inedita entre as remessas reais. Com p_teste a mesma chave entra em linha propria (is_teste),
  -- so para homologar; um teste por chave (exclua o anterior na secao Testes).
  if not p_teste and exists (
    select 1 from f.remessas_terceiros r
    where r.tenant_id = v_scope.tenant_id and r.empresa_id = v_scope.empresa_id and r.chave = substr(v_cab.id_infnfe, 4, 44) and not r.is_teste
  ) then
    raise exception using errcode = '23505', message = format('NF-e %s ja importada.', substr(v_cab.id_infnfe, 4, 44));
  end if;
  if p_teste and exists (
    select 1 from f.remessas_terceiros r
    where r.tenant_id = v_scope.tenant_id and r.empresa_id = v_scope.empresa_id and r.chave = substr(v_cab.id_infnfe, 4, 44) and r.is_teste
  ) then
    raise exception using errcode = '23505', message = format('Teste de homologacao da NF-e %s ja existe; exclua o teste anterior na secao Testes.', substr(v_cab.id_infnfe, 4, 44));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'qVol', v.qvol, 'esp', v.esp, 'marca', v.marca, 'nVol', v.nvol, 'pesoL', v.pesol, 'pesoB', v.pesob
    )), '[]'::jsonb)
  into v_volumes
  from xmltable(
    xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '//n:transp/n:vol' passing v_doc columns
      qvol integer path 'n:qVol', esp text path 'n:esp', marca text path 'n:marca', nvol text path 'n:nVol',
      pesol numeric path 'n:pesoL', pesob numeric path 'n:pesoB'
  ) v;
  v_total := coalesce(v_cab.vprod, (select sum((x->>'v_prod')::numeric) from jsonb_array_elements(v_itens) x), 0);

  insert into f.remessas_terceiros (
    id, tenant_id, empresa_id, chave, numero, serie, modelo, emitente_cnpj, emitente_nome, emitente_ie,
    emitente_endereco, cfop_origem, nat_op, dh_emi, data_entrada, prazo_retorno, tipo, valor_total,
    status, xml_original, transporte_origem, created_by, is_teste
  ) values (
    v_id, v_scope.tenant_id, v_scope.empresa_id, substr(v_cab.id_infnfe, 4, 44), v_cab.nnf, v_cab.serie,
    coalesce(v_cab.modelo, '55'), regexp_replace(v_cab.emit_cnpj, '[^0-9]', '', 'g'), v_cab.emit_nome,
    nullif(btrim(coalesce(v_cab.emit_ie, '')), ''),
    jsonb_strip_nulls(jsonb_build_object(
      'logradouro', v_cab.emit_xlgr, 'numero', v_cab.emit_nro, 'complemento', v_cab.emit_xcpl,
      'bairro', v_cab.emit_xbairro, 'codigo_ibge_municipio', v_cab.emit_cmun, 'cidade', v_cab.emit_xmun,
      'uf', v_cab.emit_uf, 'cep', v_cab.emit_cep, 'telefone', v_cab.emit_fone
    )),
    v_cfops[1], v_cab.natop, v_cab.dhemi::timestamptz, current_date,
    ((v_cab.dhemi::timestamptz) at time zone 'America/Sao_Paulo')::date + 180,
    v_tipo, v_total, 'ABERTA', p_xml,
    jsonb_build_object('modFrete', v_cab.modfrete, 'volumes', v_volumes),
    v_scope.usuario_id, p_teste
  );

  insert into f.remessas_terceiros_itens (
    remessa_id, tenant_id, empresa_id, n_item, c_prod, x_prod, ncm, cest, cfop_origem, u_com, q_com, v_un_com, v_prod,
    orig, icms_cst, ipi_cst, ipi_c_enq, pis_cst, cofins_cst, ibscbs_cst, ibscbs_c_class_trib, impostos_xml
  )
  select v_id, v_scope.tenant_id, v_scope.empresa_id, (x->>'n_item')::integer, x->>'c_prod', x->>'x_prod',
    nullif(regexp_replace(coalesce(x->>'ncm', ''), '[^0-9]', '', 'g'), ''), nullif(regexp_replace(coalesce(x->>'cest', ''), '[^0-9]', '', 'g'), ''),
    x->>'cfop', coalesce(nullif(btrim(x->>'u_com'), ''), 'UN'), (x->>'q_com')::numeric, (x->>'v_un_com')::numeric, (x->>'v_prod')::numeric,
    nullif(x->>'orig', '')::smallint, x->>'icms_cst', x->>'ipi_cst', x->>'ipi_c_enq', x->>'pis_cst', x->>'cofins_cst',
    x->>'ibscbs_cst', x->>'ibscbs_c_class_trib', jsonb_build_object('xml', x->>'imposto_xml')
  from jsonb_array_elements(v_itens) x;

  return jsonb_build_object(
    'remessa_id', v_id, 'chave', substr(v_cab.id_infnfe, 4, 44), 'numero', v_cab.nnf, 'serie', v_cab.serie,
    'emitente', v_cab.emit_nome, 'tipo', v_tipo, 'cfop_origem', v_cfops[1], 'itens', jsonb_array_length(v_itens),
    'valor_total', v_total, 'prazo_retorno', ((v_cab.dhemi::timestamptz) at time zone 'America/Sao_Paulo')::date + 180,
    'teste', p_teste
  );
end;
$function$;

-- fn_remessa_terceiros_retorno_criar (de 20260917100000/110000) marca a operacao e a solicitacao do teste.
CREATE OR REPLACE FUNCTION f.fn_remessa_terceiros_retorno_criar(p_remessa_id uuid, p_cfop text, p_modalidade_frete smallint DEFAULT 0, p_observacao text DEFAULT NULL::text, p_volumes jsonb DEFAULT NULL::jsonb)
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
      'perfil_codigo', (select po.codigo from f.perfil_operacao po where po.id = v_perfil_id), 'chave_origem', v_rem.chave, 'remessa_teste', v_rem.is_teste),
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
      'retorno_terceiros', jsonb_build_object('teste', v_rem.is_teste, 
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
    'perfil_id', v_perfil_id, 'cliente_id', v_cliente_id, 'teste', v_rem.is_teste
  );
end;
$function$;

-- fn_remessa_terceiros_apos_retorno (de 20260917100000) ignora testes fora da homologacao.
CREATE OR REPLACE FUNCTION f.fn_remessa_terceiros_apos_retorno()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_remessa_id uuid;
begin
  if new.status not in ('AUTORIZADA', 'CANCELADA') or old.status = new.status or new.solicitacao_id is null then
    return new;
  end if;
  select si.origem_id::uuid into v_remessa_id
  from f.solicitacao_item si
  where si.tenant_id = new.tenant_id and si.empresa_id = new.empresa_id
    and si.solicitacao_id = new.solicitacao_id and si.origem_tipo = 'RETORNO_TERCEIROS'
  limit 1;
  if v_remessa_id is null then return new; end if;
  -- Remessa de TESTE de homologacao: so o carimbo da homologacao; nunca RETORNADA nem reaberta.
  if new.ambiente <> 'HOMOLOGACAO' and exists (select 1 from f.remessas_terceiros r where r.id = v_remessa_id and r.is_teste) then
    return new;
  end if;

  if new.status = 'AUTORIZADA' and new.ambiente = 'HOMOLOGACAO' then
    update f.remessas_terceiros
       set homologada_em = coalesce(new.autorizado_em, now()), nfe_homologacao_id = new.documento_fiscal_id, updated_at = now()
     where id = v_remessa_id;
  elsif new.status = 'AUTORIZADA' and new.ambiente = 'PRODUCAO' then
    update f.remessas_terceiros r
       set status = 'RETORNADA', nfe_retorno_id = new.documento_fiscal_id, retornada_em = coalesce(new.autorizado_em, now()),
           cfop_retorno = coalesce((select si.cfop from f.solicitacao_item si where si.solicitacao_id = new.solicitacao_id order by si.ordem limit 1), r.cfop_retorno),
           updated_at = now()
     where r.id = v_remessa_id and r.status = 'ABERTA';
  elsif new.status = 'CANCELADA' and new.ambiente = 'PRODUCAO' then
    -- NF-e de retorno cancelada: a mercadoria continua em nosso poder.
    update f.remessas_terceiros r
       set status = 'ABERTA', nfe_retorno_id = null, retornada_em = null, updated_at = now()
     where r.id = v_remessa_id and r.status = 'RETORNADA' and r.nfe_retorno_id = new.documento_fiscal_id;
  end if;
  return new;
end;
$function$;

revoke all on function f.fn_remessa_terceiros_importar(text, boolean) from public, anon;
grant execute on function f.fn_remessa_terceiros_importar(text, boolean) to authenticated, service_role;
revoke all on function f.fn_remessa_terceiros_retorno_criar(uuid, text, smallint, text, jsonb) from public, anon;
grant execute on function f.fn_remessa_terceiros_retorno_criar(uuid, text, smallint, text, jsonb) to authenticated, service_role;
revoke all on function f.fn_remessa_terceiros_apos_retorno() from public, anon, authenticated, service_role;

-- Producao de um retorno de teste e recusada no banco, antes de qualquer envio.
create or replace function f.fn_remessa_terceiros_teste_bloqueia_producao()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
begin
  if new.ambiente = 'PRODUCAO' and new.solicitacao_id is not null and exists (
    select 1
    from f.solicitacao_item si
    join f.remessas_terceiros r on r.id::text = si.origem_id
    where si.solicitacao_id = new.solicitacao_id and si.origem_tipo = 'RETORNO_TERCEIROS' and r.is_teste
  ) then
    raise exception using errcode = '55000',
      message = 'Producao bloqueada: retorno de remessa de terceiros de TESTE de homologacao (so homologacao).';
  end if;
  return new;
end;
$$;
revoke all on function f.fn_remessa_terceiros_teste_bloqueia_producao() from public, anon, authenticated, service_role;
drop trigger if exists aab_remessa_terceiros_teste_bloqueia_producao on f.documento_fiscal_emissao;
create trigger aab_remessa_terceiros_teste_bloqueia_producao
  before insert or update of ambiente, status on f.documento_fiscal_emissao
  for each row execute function f.fn_remessa_terceiros_teste_bloqueia_producao();

-- Excluir um teste: cancela a solicitacao/homologacao dele e apaga a linha (a real de mesma chave fica).
create or replace function f.fn_remessa_terceiros_teste_excluir(p_remessa_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_rem f.remessas_terceiros%rowtype;
  v_sol uuid;
  v_motivo text := 'Teste de homologacao do retorno de terceiros excluido pela tela';
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_rem from f.remessas_terceiros r
   where r.id = p_remessa_id and r.tenant_id = v_scope.tenant_id and r.empresa_id = v_scope.empresa_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Remessa nao encontrada.';
  end if;
  if not v_rem.is_teste then
    raise exception using errcode = '22023', message = 'So remessa de TESTE pode ser excluida; a remessa real fica no historico.';
  end if;
  if exists (
    select 1 from f.operacao_fiscal o
    join f.documento_fiscal_emissao e on e.solicitacao_id = o.solicitacao_id
    where o.dados_json->>'remessa_terceiros_id' = v_rem.id::text and e.ambiente = 'PRODUCAO' and e.status not in ('REJEITADA', 'ERRO', 'CANCELADA')
  ) then
    raise exception using errcode = '55000', message = 'Teste com emissao de producao registrada: nao deveria existir; avise o suporte antes de excluir.';
  end if;
  for v_sol in
    select o.solicitacao_id from f.operacao_fiscal o
    where o.dados_json->>'remessa_terceiros_id' = v_rem.id::text and o.solicitacao_id is not null
  loop
    if exists (select 1 from f.solicitacao_faturamento sf where sf.id = v_sol and sf.status not in ('EMITIDA', 'CANCELADA')) then
      if exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = v_sol and e.ambiente = 'HOMOLOGACAO' and e.status <> 'CANCELADA') then
        perform f.fn_solicitacao_nfe_abandonar_homologacao(v_sol, v_motivo);
      else
        perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol, v_motivo);
      end if;
    end if;
  end loop;
  update f.operacao_fiscal set status = 'CANCELADA', updated_at = now()
   where dados_json->>'remessa_terceiros_id' = v_rem.id::text and status not in ('CONCLUIDA', 'CANCELADA');
  delete from f.remessas_terceiros_itens where remessa_id = v_rem.id;
  delete from f.remessas_terceiros where id = v_rem.id;
  return jsonb_build_object('excluida', true, 'remessa_id', v_rem.id, 'chave', v_rem.chave, 'numero', v_rem.numero, 'serie', v_rem.serie);
end;
$$;
revoke all on function f.fn_remessa_terceiros_teste_excluir(uuid) from public, anon;
grant execute on function f.fn_remessa_terceiros_teste_excluir(uuid) to authenticated, service_role;

do $assert$
begin
  if not exists (select 1 from pg_attribute where attrelid = 'f.remessas_terceiros'::regclass and attname = 'is_teste' and not attisdropped) then
    raise exception 'coluna is_teste ausente';
  end if;
  if to_regprocedure('f.fn_remessa_terceiros_importar(text)') is not null then
    raise exception 'a versao antiga de fn_remessa_terceiros_importar(text) ainda existe';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'aab_remessa_terceiros_teste_bloqueia_producao' and tgrelid = 'f.documento_fiscal_emissao'::regclass) then
    raise exception 'gatilho de bloqueio de producao do teste ausente';
  end if;
  if pg_get_functiondef('f.fn_remessa_terceiros_apos_retorno()'::regprocedure) not like '%r.is_teste%' then
    raise exception 'fn_remessa_terceiros_apos_retorno nao ignora testes';
  end if;
end;
$assert$;

notify pgrst, 'reload schema';
