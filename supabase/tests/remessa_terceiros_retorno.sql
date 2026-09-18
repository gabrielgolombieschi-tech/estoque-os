\set ON_ERROR_STOP on

-- Retorno de mercadoria de terceiros (supabase/migrations/20260917100000_retorno_remessa_terceiros.sql).
--
-- Blocos:
--   1  importar: recusa XML invalido, sem nfeProc, sem cStat 100, destinatario diferente da
--      empresa, CFOP fora de 5901/6901/5915/6915 e chave repetida; nada gravado nas recusas
--   2  importacao da NF-e 900356/1 da WEG Tintas: cabecalho, endereco do remetente, prazo de
--      180 dias, transporte da origem e o item como veio no XML
--   3  gerar retorno: recusa CFOP fora do tipo/ambito e modalidade invalida; cria operacao
--      RETORNO + solicitacao com destinatario do XML, item espelho com CST 50/SC840008,
--      IPI 55/109, PIS/COFINS 08, IBS 410/410999, tPag 90, sem estoque; volumes da origem
--      quando a modalidade tem transporte; o retorno anterior sai do caminho; o pipeline
--      prepara o documento de homologacao a partir dela
--   4  autorizacoes: homologacao so marca homologada_em; producao baixa a remessa
--      (RETORNADA, nfe_retorno_id) e a NF-e EMITIDA nao gera contas a receber;
--      cancelamento da nota de producao reabre a remessa
--   5  producao desligada por padrao; so ADMIN liga; RLS entrega a remessa ao usuario
--
-- Tenant 1e160000-...-0001, empresa ...0002 (SC, CNPJ 22222222000191 — o XML da WEG e
-- reescrito com esse destinatario). Usuario ...0011 ADMIN, ...0021 COORDENACAO.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('1e160000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'retorno@example.test',
   '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Retorno"}'::jsonb, now(), now()),
  ('1e160000-0000-4000-8000-000000000020', 'authenticated', 'authenticated', 'coordenacao@example.test',
   '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Coordenacao"}'::jsonb, now(), now());
insert into public.tenants (id, nome, ativo) values ('1e160000-0000-4000-8000-000000000001', 'Teste retorno', true);
insert into c.tenant (id, codigo, nome) values ('1e160000-0000-4000-8000-000000000001', 'TESTE-RETORNO', 'Teste retorno');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e160000-0000-4000-8000-000000000002', '1e160000-0000-4000-8000-000000000001', 'RETORNO', 'EMPRESA RETORNO LTDA', 'RETORNO', '22222222000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e160000-0000-4000-8000-000000000002', '1e160000-0000-4000-8000-000000000001', '22222222000191', 'EMPRESA RETORNO LTDA', 'RETORNO', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('1e160000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2);
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('1e160000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');
insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1e160000-0000-4000-8000-000000000011', '1e160000-0000-4000-8000-000000000010', 'Fiscal Retorno', 'retorno@example.test', true),
  ('1e160000-0000-4000-8000-000000000021', '1e160000-0000-4000-8000-000000000020', 'Coordenacao', 'coordenacao@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1e160000-0000-4000-8000-000000000011', '1e160000-0000-4000-8000-000000000001', 'ADMIN', true),
  ('1e160000-0000-4000-8000-000000000021', '1e160000-0000-4000-8000-000000000001', 'GESTOR', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1e160000-0000-4000-8000-000000000011', '1e160000-0000-4000-8000-000000000002', 'ADMIN', true),
  ('1e160000-0000-4000-8000-000000000021', '1e160000-0000-4000-8000-000000000002', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id) values
  ('1e160000-0000-4000-8000-000000000010', '1e160000-0000-4000-8000-000000000001'),
  ('1e160000-0000-4000-8000-000000000020', '1e160000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id) values
  ('1e160000-0000-4000-8000-000000000010', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002'),
  ('1e160000-0000-4000-8000-000000000020', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002');
insert into public.municipios_ibge (codigo_ibge, nome, nome_normalizado, uf, fonte, fonte_versao, atualizado_em)
values ('4206504', 'Guaramirim', 'guaramirim', 'SC', 'teste', 'teste', now()),
       ('4209102', 'Joinville', 'joinville', 'SC', 'teste', 'teste', now())
on conflict (codigo_ibge) do nothing;

-- A WEG existe como cliente: a operacao aponta para ela na listagem, mas o destinatario da
-- nota vem do XML.
insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, uf, cidade, indicador_ie)
values (916001, '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'WEG TINTAS', '60621141000404', 'WEG TINTAS LTDA', 'SC', 'GUARAMIRIM', '1');

-- Perfil do retorno (mesmo desenho do SEG-RETORNO-TERCEIROS-5902-O0-CST50), sem revisao.
insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_interno, cst_icms, aliquota_icms, cbenef, cbenef_aplicacao, beneficio_texto_legal,
  cst_ipi, ipi_codigo_enquadramento_legal, cst_pis, cst_cofins, finalidade_emissao, consumidor_final,
  ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria, faixa_automacao, justificativa_faixa,
  habilitado_producao, vigencia_inicio
) values (
  '1e160000-0000-4000-8000-000000000301', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002',
  'TESTE-RETORNO-5902-O0', 'Retorno terceiros teste', 'NFE', 'RETORNO_REMESSA_TERCEIROS', 'RETORNO MERCADORIA RECEBIDA P/ INDUSTRIALIZACAO P/ ENCOMENDA', '3',
  '5902', '50', 0, 'SC840008', 'COM_BENEFICIO', 'ICMS suspenso (teste)',
  '55', '109', '08', '08', 1, 0,
  'INTERNA', array['SC']::text[], '1', 0, 'REVISAO', 'teste', false, '2026-09-16'
);
-- Perfil 5903 (material nao aplicado), como o SEG-RETORNO-TERCEIROS-5903-O0-CST50 da migration 20260918170000.
insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_interno, cst_icms, aliquota_icms, cbenef, cbenef_aplicacao, beneficio_texto_legal,
  cst_ipi, ipi_codigo_enquadramento_legal, cst_pis, cst_cofins, finalidade_emissao, consumidor_final,
  ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria, faixa_automacao, justificativa_faixa,
  habilitado_producao, vigencia_inicio, rotulo_usuario, legenda_usuario
) values (
  '1e160000-0000-4000-8000-000000000303', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002',
  'TESTE-RETORNO-5903-O0', 'Retorno terceiros nao aplicado teste', 'NFE', 'RETORNO_REMESSA_TERCEIROS', 'RETORNO DE MERCADORIA P/ INDUSTRIALIZACAO NAO APLICADA', '3',
  '5903', '50', 0, 'SC840008', 'COM_BENEFICIO', 'ICMS suspenso (teste)',
  '55', '109', '08', '08', 1, 0,
  'INTERNA', array['SC']::text[], '1', 0, 'REVISAO', 'teste', false, '2026-09-18', 'Voltou sem usar', 'Ex.: lata fechada, sobra devolvida como veio.'
);

create temporary table retorno_ids (nome text primary key, id uuid not null) on commit drop;
grant all on retorno_ids to authenticated;

-- NF-e 900356/1 da WEG Tintas (docs/fiscal/exemplos/42260660621141000404550010009003561304254706.xml),
-- com o destinatario trocado pela empresa de teste.
create temporary table xml_origem on commit drop as
select replace($xml$<nfeProc versao="4.00" xmlns="http://www.portalfiscal.inf.br/nfe"><NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe Id="NFe42260660621141000404550010009003561304254706" versao="4.00"><ide><cUF>42</cUF><cNF>30425470</cNF><natOp>REM. P/INDUST. POR ENCOM REMESSA TERCEIROS C/RETOR</natOp><mod>55</mod><serie>1</serie><nNF>900356</nNF><dhEmi>2026-06-10T11:44:06-03:00</dhEmi><dhSaiEnt>2026-06-10T11:44:06-03:00</dhSaiEnt><tpNF>1</tpNF><idDest>1</idDest><cMunFG>4206504</cMunFG><tpImp>2</tpImp><tpEmis>1</tpEmis><cDV>6</cDV><tpAmb>1</tpAmb><finNFe>1</finNFe><indFinal>0</indFinal><indPres>9</indPres><indIntermed>0</indIntermed><procEmi>0</procEmi><verProc>SAP CLOUD NFE</verProc></ide><emit><CNPJ>60621141000404</CNPJ><xNome>WEG TINTAS LTDA</xNome><xFant>60.621.141/0004-04 GUARAMIRIM</xFant><enderEmit><xLgr>RODOVIA BR 280 - KM50</xLgr><nro>6918</nro><xCpl>BLOCO A</xCpl><xBairro>CAIXA D AGUA</xBairro><cMun>4206504</cMun><xMun>GUARAMIRIM</xMun><UF>SC</UF><CEP>89270000</CEP><cPais>1058</cPais><xPais>BRASIL</xPais><fone>4732764000</fone></enderEmit><IE>257843876</IE><IM>62718</IM><CNAE>2071100</CNAE><CRT>3</CRT></emit><dest><CNPJ>13671448000189</CNPJ><xNome>ELETRICA SEGAU LTDA</xNome><enderDest><xLgr>RUA DONA FRANCISCA</xLgr><nro>8300</nro><xBairro>ZONA INDUSTRIAL NORTE</xBairro><cMun>4209102</cMun><xMun>JOINVILLE</xMun><UF>SC</UF><CEP>89219600</CEP><cPais>1058</cPais><xPais>BRASIL</xPais><fone>4734735171</fone></enderDest><indIEDest>1</indIEDest><IE>257686835</IE></dest><det nItem="1"><prod><cProd>000000000050017810</cProd><cEAN>SEM GTIN</cEAN><xProd>MATERIAIS PARA PINTURA</xProd><NCM>32099019</NCM><cBenef>SC840007</cBenef><CFOP>5901</CFOP><uCom>GL</uCom><qCom>4.0000</qCom><vUnCom>400.0000000000</vUnCom><vProd>1600.00</vProd><cEANTrib>SEM GTIN</cEANTrib><uTrib>GL</uTrib><qTrib>4.0000</qTrib><vUnTrib>400.0000000000</vUnTrib><indTot>1</indTot></prod><imposto><ICMS><ICMS40><orig>0</orig><CST>50</CST></ICMS40></ICMS><IPI><cEnq>108</cEnq><IPINT><CST>55</CST></IPINT></IPI><PIS><PISNT><CST>08</CST></PISNT></PIS><COFINS><COFINSNT><CST>08</CST></COFINSNT></COFINS><IBSCBS><CST>410</CST><cClassTrib>410999</cClassTrib></IBSCBS></imposto><infAdProd>.</infAdProd><vItem>1600.00</vItem></det><total><ICMSTot><vBC>0.00</vBC><vICMS>0.00</vICMS><vICMSDeson>0.00</vICMSDeson><vFCP>0.00</vFCP><vBCST>0.00</vBCST><vST>0.00</vST><vFCPST>0.00</vFCPST><vFCPSTRet>0.00</vFCPSTRet><vProd>1600.00</vProd><vFrete>0.00</vFrete><vSeg>0.00</vSeg><vDesc>0.00</vDesc><vII>0.00</vII><vIPI>0.00</vIPI><vIPIDevol>0.00</vIPIDevol><vPIS>0.00</vPIS><vCOFINS>0.00</vCOFINS><vOutro>0.00</vOutro><vNF>1600.00</vNF></ICMSTot><IBSCBSTot><vBCIBSCBS>0.00</vBCIBSCBS></IBSCBSTot><vNFTot>1600.00</vNFTot></total><transp><modFrete>4</modFrete><vol><qVol>4</qVol><esp>VOLUMES</esp><pesoL>5.560</pesoL><pesoB>5.560</pesoB></vol></transp><cobr><fat><nFat>0944595183</nFat><vOrig>1600.00</vOrig><vDesc>0.00</vDesc><vLiq>1600.00</vLiq></fat></cobr><pag><detPag><tPag>90</tPag><vPag>0.00</vPag></detPag></pag><infAdic><infAdFisco>SUSPENSO DO ICMS DE ACORDO COM O INCISO I DO ARTIGO 27, ANEXO II DO RICM S/SC, APROVADO PELO DECRETO N  2.870/01. IPI SUSPENSO DE ACORDO COM O INCISO VI DO ARTIGO 43, DECRETO NR. 7.212 D E 15.06.2010- RIPI.</infAdFisco><infCpl>OBS. STEPHANY GUIMARAES. RAMAL 7772 REMESSA PARA INDUSTRIALIZAÇAO POR ENCOMENDA.</infCpl></infAdic></infNFe></NFe><protNFe versao="4.00" xmlns="http://www.portalfiscal.inf.br/nfe"><infProt><tpAmb>1</tpAmb><verAplic>SVRS2606081136DR</verAplic><chNFe>42260660621141000404550010009003561304254706</chNFe><dhRecbto>2026-06-10T11:44:16-03:00</dhRecbto><nProt>242260265092628</nProt><digVal>tdA42J4qzpGiW/ueWO34UVmLRdM=</digVal><cStat>100</cStat><xMotivo>Autorizado o uso da NF-e</xMotivo></infProt></protNFe></nfeProc>$xml$::text,
  '<dest><CNPJ>13671448000189</CNPJ>', '<dest><CNPJ>22222222000191</CNPJ>') as xml;
grant all on xml_origem to authenticated;

select set_config('request.jwt.claim.sub', '1e160000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e160000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

-- 1 ---------------------------------------------------------------- importar: recusas
do $test$
declare
  v_xml text := (select xml from xml_origem);
begin
  begin
    perform f.fn_remessa_terceiros_importar('isto nao e xml');
    raise exception 'importou texto que nao e XML';
  exception when sqlstate '22023' then
    if sqlerrm not like '%nao e um XML valido%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_importar('<a/>');
    raise exception 'importou XML sem nfeProc';
  exception when sqlstate '22023' then
    if sqlerrm not like '%nao e uma NF-e processada%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_importar(replace(v_xml, '<cStat>100</cStat>', '<cStat>110</cStat>'));
    raise exception 'importou NF-e sem cStat 100';
  exception when sqlstate '22023' then
    if sqlerrm not like '%sem autorizacao (cStat 110)%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_importar(replace(v_xml, '<dest><CNPJ>22222222000191</CNPJ>', '<dest><CNPJ>13671448000189</CNPJ>'));
    raise exception 'importou NF-e de outro destinatario';
  exception when sqlstate '22023' then
    if sqlerrm not like '%nao e a empresa ativa%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_importar(replace(v_xml, '<CFOP>5901</CFOP>', '<CFOP>5102</CFOP>'));
    raise exception 'importou NF-e de venda';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Nao e remessa de terceiros: CFOP 5102%' then raise; end if;
  end;
  if exists (select 1 from f.remessas_terceiros) then
    raise exception 'recusa deixou remessa gravada';
  end if;
end;
$test$;

-- 2 ---------------------------------------------------------------- importacao
do $test$
declare
  v_res jsonb;
  v_rem f.remessas_terceiros%rowtype;
  v_item f.remessas_terceiros_itens%rowtype;
begin
  v_res := f.fn_remessa_terceiros_importar((select xml from xml_origem));
  insert into retorno_ids values ('remessa', (v_res->>'remessa_id')::uuid);
  if v_res->>'chave' <> '42260660621141000404550010009003561304254706' or v_res->>'tipo' <> 'INDUSTRIALIZACAO'
     or (v_res->>'itens')::integer <> 1 or (v_res->>'valor_total')::numeric <> 1600 or v_res->>'prazo_retorno' <> '2026-12-07' then
    raise exception 'retorno da importacao errado: %', v_res;
  end if;
  select * into v_rem from f.remessas_terceiros where id = (v_res->>'remessa_id')::uuid;
  if v_rem.numero <> '900356' or v_rem.serie <> '1' or v_rem.modelo <> '55' or v_rem.emitente_cnpj <> '60621141000404'
     or v_rem.emitente_nome <> 'WEG TINTAS LTDA' or v_rem.emitente_ie <> '257843876'
     or v_rem.emitente_endereco->>'uf' <> 'SC' or v_rem.emitente_endereco->>'codigo_ibge_municipio' <> '4206504'
     or v_rem.emitente_endereco->>'logradouro' <> 'RODOVIA BR 280 - KM50' or v_rem.emitente_endereco->>'numero' <> '6918'
     or v_rem.emitente_endereco->>'complemento' <> 'BLOCO A' or v_rem.emitente_endereco->>'cep' <> '89270000'
     or v_rem.cfop_origem <> '5901' or v_rem.nat_op not like 'REM. P/INDUST.%' or v_rem.tipo <> 'INDUSTRIALIZACAO'
     or (v_rem.dh_emi at time zone 'America/Sao_Paulo')::date <> date '2026-06-10' or v_rem.data_entrada <> current_date
     or v_rem.prazo_retorno <> date '2026-12-07' or v_rem.valor_total <> 1600 or v_rem.status <> 'ABERTA'
     or v_rem.xml_original not like '<nfeProc%' or v_rem.transporte_origem->>'modFrete' <> '4'
     or (v_rem.transporte_origem#>>'{volumes,0,qVol}')::integer <> 4 or v_rem.transporte_origem#>>'{volumes,0,esp}' <> 'VOLUMES'
     or (v_rem.transporte_origem#>>'{volumes,0,pesoB}')::numeric <> 5.56
     or v_rem.created_by <> '1e160000-0000-4000-8000-000000000011' or v_rem.nfe_retorno_id is not null then
    raise exception 'remessa gravada errada: %', row_to_json(v_rem);
  end if;
  select * into v_item from f.remessas_terceiros_itens where remessa_id = v_rem.id;
  if v_item.n_item <> 1 or v_item.c_prod <> '000000000050017810' or v_item.x_prod <> 'MATERIAIS PARA PINTURA'
     or v_item.ncm <> '32099019' or v_item.cest is not null or v_item.cfop_origem <> '5901' or v_item.u_com <> 'GL'
     or v_item.q_com <> 4 or v_item.v_un_com <> 400 or v_item.v_prod <> 1600 or v_item.orig <> 0
     or v_item.icms_cst <> '50' or v_item.ipi_cst <> '55' or v_item.ipi_c_enq <> '108' or v_item.pis_cst <> '08'
     or v_item.cofins_cst <> '08' or v_item.ibscbs_cst <> '410' or v_item.ibscbs_c_class_trib <> '410999'
     or v_item.impostos_xml->>'xml' not like '<imposto%' then
    raise exception 'item gravado errado: %', row_to_json(v_item);
  end if;
  begin
    perform f.fn_remessa_terceiros_importar((select xml from xml_origem));
    raise exception 'importou a mesma chave duas vezes';
  exception when sqlstate '23505' then
    if sqlerrm not like 'NF-e 4226066062114100040455001000900356130425470% ja importada.' then raise; end if;
  end;
  -- Nada de estoque nem compra: a nota de terceiros nao vira nf_entrada.
  if exists (select 1 from public.nf_entrada n where n.tenant_id = '1e160000-0000-4000-8000-000000000001') then
    raise exception 'importacao criou nf_entrada';
  end if;
end;
$test$;

-- 3 ---------------------------------------------------------------- gerar retorno
do $test$
declare
  v_rem uuid := (select id from retorno_ids where nome = 'remessa');
  v_res jsonb;
  v_op f.operacao_fiscal%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_si f.solicitacao_item%rowtype;
  v_primeira_op uuid;
  v_primeira_sol uuid;
begin
  begin
    perform f.fn_remessa_terceiros_retorno_criar(v_rem, '5916', 9::smallint, null, null);
    raise exception 'aceitou CFOP de conserto numa industrializacao';
  exception when sqlstate '22023' then
    if sqlerrm not like 'CFOP 5916 nao vale para este retorno (INDUSTRIALIZACAO, INTERNA). Use 5902 ou 5903.' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_retorno_criar(v_rem, '6902', 9::smallint, null, null);
    raise exception 'aceitou CFOP interestadual dentro de SC';
  exception when sqlstate '22023' then
    if sqlerrm not like 'CFOP 6902 nao vale%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_retorno_criar(v_rem, '5902', 2::smallint, null, null);
    raise exception 'aceitou modalidade 2';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Modalidade do frete deve ser%' then raise; end if;
  end;
  if exists (select 1 from f.operacao_fiscal where tenant_id = '1e160000-0000-4000-8000-000000000001') then
    raise exception 'recusa deixou operacao gravada';
  end if;

  -- Retorno integral, CFOP 5902, sem frete.
  v_res := f.fn_remessa_terceiros_retorno_criar(v_rem, '5902', 9::smallint, 'Retorno das latas da OP 1234', null);
  v_primeira_op := (v_res->>'operacao_id')::uuid;
  v_primeira_sol := (v_res->>'solicitacao_id')::uuid;
  if v_res->>'cfop' <> '5902' or v_res->>'ambito' <> 'INTERNA' or v_res->>'natureza_operacao' <> 'RETORNO_REMESSA_TERCEIROS'
     or (v_res->>'valor_total')::numeric <> 1600 or (v_res->>'itens')::integer <> 1
     or v_res->>'perfil_id' <> '1e160000-0000-4000-8000-000000000301' or (v_res->>'cliente_id')::integer <> 916001 then
    raise exception 'retorno da criacao errado: %', v_res;
  end if;
  select * into v_op from f.operacao_fiscal where id = v_primeira_op;
  if v_op.tipo <> 'RETORNO' or v_op.finalidade <> 'INDUSTRIALIZACAO' or v_op.status <> 'PRONTO_HOMOLOGACAO' or v_op.ambiente <> 'HOMOLOGACAO'
     or v_op.nfe_referenciada <> '42260660621141000404550010009003561304254706' or v_op.cfop_confirmado <> '5902'
     or v_op.destinatario_id <> 916001 or v_op.solicitacao_id <> v_primeira_sol or v_op.valor_total <> 1600
     or v_op.dados_json->>'remessa_terceiros_id' <> v_rem::text or v_op.dados_json->>'perfil_codigo' <> 'TESTE-RETORNO-5902-O0'
     or v_op.entrega_json->>'documento' <> '60621141000404' or v_op.entrega_json->>'nome' <> 'WEG TINTAS LTDA'
     or v_op.justificativa_fisco <> 'Retorno das latas da OP 1234' or v_op.perfil_operacao_id <> '1e160000-0000-4000-8000-000000000301' then
    raise exception 'operacao errada: %', row_to_json(v_op);
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_primeira_sol;
  if v_sf.natureza_operacao <> 'RETORNO_REMESSA_TERCEIROS' or v_sf.cliente_id <> 916001 or v_sf.status <> 'PREVIA'
     or v_sf.finalidade_emissao <> 1 or v_sf.consumidor_final <> 0 or v_sf.presenca_comprador <> 9 or v_sf.modalidade_frete <> 9
     or v_sf.valor_frete <> 0 or v_sf.pagamento_forma <> '90' or v_sf.pagamento_indicador <> 0 or v_sf.destinacao_mercadoria is not null
     or v_sf.destino_uf_confirmada <> 'SC' or v_sf.snapshot_cadastro_em is null or v_sf.revisao_fiscal_confirmada_em is null
     or v_sf.transportador_dados is not null or v_sf.volumes_dados is not null or v_sf.observacao <> 'Retorno das latas da OP 1234'
     or v_sf.perfil_operacao_id <> '1e160000-0000-4000-8000-000000000301' then
    raise exception 'solicitacao errada: %', row_to_json(v_sf);
  end if;
  -- Destinatario = emitente da origem, do XML (nao do cadastro: la a WEG esta sem endereco).
  if v_sf.destinatario_snapshot->>'documento' <> '60621141000404' or v_sf.destinatario_snapshot->>'nome' <> 'WEG TINTAS LTDA'
     or v_sf.destinatario_snapshot->>'inscricao_estadual' <> '257843876' or v_sf.destinatario_snapshot->>'indicador_ie' <> '1'
     or v_sf.destinatario_snapshot->>'logradouro' <> 'RODOVIA BR 280 - KM50' or v_sf.destinatario_snapshot->>'numero_endereco' <> '6918'
     or v_sf.destinatario_snapshot->>'complemento' <> 'BLOCO A' or v_sf.destinatario_snapshot->>'bairro' <> 'CAIXA D AGUA'
     or v_sf.destinatario_snapshot->>'cidade' <> 'Guaramirim' or v_sf.destinatario_snapshot->>'uf' <> 'SC'
     or v_sf.destinatario_snapshot->>'codigo_ibge_municipio' <> '4206504' or v_sf.destinatario_snapshot->>'cep' <> '89270000'
     or (v_sf.destinatario_snapshot->>'id')::integer <> 916001 then
    raise exception 'destinatario_snapshot errado: %', v_sf.destinatario_snapshot;
  end if;
  if v_sf.emitente_snapshot->>'cnpj' <> '22222222000191' or v_sf.emitente_snapshot->>'cidade' <> 'Joinville'
     or (v_sf.emitente_snapshot->>'serie_nfe')::integer <> 2 then
    raise exception 'emitente_snapshot errado: %', v_sf.emitente_snapshot;
  end if;
  if v_sf.operacao_snapshot->>'natureza_operacao' <> 'RETORNO_REMESSA_TERCEIROS'
     or v_sf.operacao_snapshot->>'nfe_referenciada' <> '42260660621141000404550010009003561304254706'
     or v_sf.operacao_snapshot#>>'{pagamento,forma}' <> '90' or (v_sf.operacao_snapshot#>>'{pagamento,indicador}')::integer <> 0
     or v_sf.operacao_snapshot#>>'{pagamento,parcelas}' is not null
     or (v_sf.operacao_snapshot->>'modalidade_frete')::integer <> 9 or v_sf.operacao_snapshot->>'destinacao_mercadoria' is not null
     or v_sf.operacao_snapshot#>>'{retorno_terceiros,numero}' <> '900356' or v_sf.operacao_snapshot#>>'{retorno_terceiros,serie}' <> '1'
     or v_sf.operacao_snapshot#>>'{retorno_terceiros,data_emissao}' <> '10/06/2026'
     or v_sf.operacao_snapshot#>>'{retorno_terceiros,chave}' <> '42260660621141000404550010009003561304254706'
     or v_sf.operacao_snapshot#>>'{retorno_terceiros,remessa_id}' <> v_rem::text then
    raise exception 'operacao_snapshot errado: %', v_sf.operacao_snapshot;
  end if;
  select * into v_si from f.solicitacao_item where solicitacao_id = v_sf.id;
  if v_si.origem_tipo <> 'RETORNO_TERCEIROS' or v_si.origem_id <> v_rem::text or v_si.item_id is not null
     or v_si.codigo_produto <> '000000000050017810' or v_si.descricao <> 'MATERIAIS PARA PINTURA' or v_si.ncm <> '32099019'
     or v_si.cfop <> '5902' or v_si.cst_icms <> '50' or v_si.csosn is not null or v_si.aliquota_icms is not null
     or v_si.cbenef <> 'SC840008' or v_si.reducao_base_icms_percentual <> 0
     or v_si.cst_ipi <> '55' or v_si.ipi_codigo_enquadramento_legal <> '109' or v_si.aliquota_ipi is not null
     or v_si.cst_pis <> '08' or v_si.cst_cofins <> '08' or v_si.aliquota_pis is not null
     or v_si.cst_ibs_cbs <> '410' or v_si.cclass_trib <> '410999' or (v_si.ibs_cbs_json->>'cbs_aliquota')::numeric <> 0
     or v_si.quantidade <> 4 or v_si.unidade <> 'GL' or v_si.unidade_tributavel <> 'GL' or v_si.valor_unitario <> 400
     or v_si.valor_desconto <> 0 or v_si.ordem <> 1 or v_si.origem_mercadoria <> 0
     or v_si.perfil_operacao_id <> '1e160000-0000-4000-8000-000000000301' or v_si.tributacao_fonte <> 'PERFIL' or v_si.modelo <> 'NFE' then
    raise exception 'item errado: %', row_to_json(v_si);
  end if;
  if (select solicitacao_retorno_id from f.remessas_terceiros where id = v_rem) <> v_primeira_sol
     or (select cfop_retorno from f.remessas_terceiros where id = v_rem) <> '5902'
     or (select status from f.remessas_terceiros where id = v_rem) <> 'ABERTA' then
    raise exception 'remessa nao apontou para a solicitacao';
  end if;

  -- Retorno de novo com transporte por conta do destinatario: volumes copiados da origem,
  -- e o retorno anterior (sem producao) sai do caminho.
  v_res := f.fn_remessa_terceiros_retorno_criar(v_rem, '5902', 1::smallint, null, null);
  insert into retorno_ids values ('op', (v_res->>'operacao_id')::uuid), ('sol', (v_res->>'solicitacao_id')::uuid);
  select * into v_sf from f.solicitacao_faturamento where id = (v_res->>'solicitacao_id')::uuid;
  if v_sf.modalidade_frete <> 1 or v_sf.transportador_dados is not null or jsonb_array_length(v_sf.volumes_dados) <> 1
     or (v_sf.volumes_dados#>>'{0,quantidade}')::integer <> 4 or v_sf.volumes_dados#>>'{0,especie}' <> 'VOLUMES'
     or (v_sf.volumes_dados#>>'{0,peso_liquido}')::numeric <> 5.56 or (v_sf.volumes_dados#>>'{0,peso_bruto}')::numeric <> 5.56
     or jsonb_array_length(v_sf.operacao_snapshot->'volumes') <> 1 or v_sf.operacao_snapshot->'transportador' <> 'null'::jsonb then
    raise exception 'volumes da origem nao foram copiados: %', row_to_json(v_sf);
  end if;
  if (select status from f.operacao_fiscal where id = v_primeira_op) <> 'CANCELADA'
     or (select status from f.solicitacao_faturamento where id = v_primeira_sol) <> 'CANCELADA' then
    raise exception 'retorno anterior continuou ativo';
  end if;
  -- Volumes informados na tela valem sobre os da origem.
  v_res := f.fn_remessa_terceiros_retorno_criar(v_rem, '5903', 4::smallint, null, '[{"quantidade":2,"especie":"CAIXA","peso_liquido":3,"peso_bruto":3.2}]'::jsonb);
  select * into v_sf from f.solicitacao_faturamento where id = (v_res->>'solicitacao_id')::uuid;
  if (v_sf.volumes_dados#>>'{0,quantidade}')::integer <> 2 or v_sf.volumes_dados#>>'{0,especie}' <> 'CAIXA'
     or (select cfop from f.solicitacao_item where solicitacao_id = v_sf.id) <> '5903'
     or (select cfop_retorno from f.remessas_terceiros where id = v_rem) <> '5903' then
    raise exception 'volumes da tela nao prevaleceram: %', row_to_json(v_sf);
  end if;
  -- CFOP 5903 tem perfil proprio (TESTE-RETORNO-5903-O0, como o SEG-RETORNO-TERCEIROS-5903-O0-CST50): o item
  -- recebe esse perfil, nao o do 5902.
  if (select perfil_operacao_id from f.solicitacao_item where solicitacao_id = v_sf.id) is distinct from '1e160000-0000-4000-8000-000000000303'::uuid then
    raise exception 'item do 5903 nao ganhou o perfil 5903: %', (select perfil_operacao_id from f.solicitacao_item where solicitacao_id = v_sf.id);
  end if;
  delete from retorno_ids where nome in ('op', 'sol');
  insert into retorno_ids values ('op', (v_res->>'operacao_id')::uuid), ('sol', (v_res->>'solicitacao_id')::uuid);
end;
$test$;

reset role;
-- O pipeline prepara o documento de homologacao a partir dessa solicitacao (a Edge chama
-- com service_role).
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $test$
declare
  v_sol uuid := (select id from retorno_ids where nome = 'sol');
  v_prep record;
  v_ctx jsonb;
begin
  select * into v_prep from f.fn_nfe_preparar_documento_solicitacao(v_sol);
  if not v_prep.criado or v_prep.status <> 'RASCUNHO' then
    raise exception 'preparacao nao criou o documento: %', row_to_json(v_prep);
  end if;
  insert into retorno_ids values ('doc_hom', v_prep.documento_fiscal_id);
  if (select valor_total from f.documento_fiscal where id = v_prep.documento_fiscal_id) <> 1600
     or (select cliente_id from f.documento_fiscal where id = v_prep.documento_fiscal_id) <> 916001
     or (select count(*) from f.documento_fiscal_item where documento_fiscal_id = v_prep.documento_fiscal_id) <> 1 then
    raise exception 'documento preparado errado';
  end if;
  v_ctx := f.fn_nfe_contexto_emissao_impl(v_prep.documento_fiscal_id);
  if jsonb_array_length(v_ctx->'itens') <> 1 or v_ctx#>>'{solicitacao,operacao_snapshot,nfe_referenciada}' <> '42260660621141000404550010009003561304254706'
     or v_ctx#>>'{itens,0,solicitacao_item,cbenef}' <> 'SC840008' then
    raise exception 'contexto de emissao errado';
  end if;
end;
$test$;

-- 4 ---------------------------------------------------------------- autorizacoes
-- Notas de mentira: as travas de producao (perfil liberado, claim) nao sao o assunto; ficam
-- desligadas na transacao, que termina em rollback. Os gatilhos da operacao e da remessa
-- continuam ligados.
alter table f.documento_fiscal disable trigger aaa_nfe_bloquear_documento_dml_direto;
alter table f.documento_fiscal_emissao disable trigger trg_bloquear_nfe_producao_sem_perfil_liberado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_bloquear_producao_cancelamento_hom_pendente;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_autorizado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_zz_aliquotas;

do $test$
declare
  v_rem uuid := (select id from retorno_ids where nome = 'remessa');
  v_op uuid := (select id from retorno_ids where nome = 'op');
  v_sol uuid := (select id from retorno_ids where nome = 'sol');
  v_doc_hom uuid := (select id from retorno_ids where nome = 'doc_hom');
  v_chave_hom text := '42260913671448000189550020000000701000000001';
  v_chave_prod text := '42260913671448000189550020000000711000000002';
  v_r f.remessas_terceiros%rowtype;
  v_movimentos bigint := (select count(*) from public.movimentacoes);
  v_prontidao jsonb;
begin
  -- Homologacao autorizada: so o carimbo; a remessa continua ABERTA e pode gerar de novo.
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_hom, numero = 70, serie = 2, autorizado_em = now()
  where documento_fiscal_id = v_doc_hom;
  select * into v_r from f.remessas_terceiros where id = v_rem;
  if v_r.status <> 'ABERTA' or v_r.homologada_em is null or v_r.nfe_homologacao_id <> v_doc_hom or v_r.nfe_retorno_id is not null then
    raise exception 'homologacao nao marcou a remessa (ou baixou indevidamente): %', row_to_json(v_r);
  end if;
  if (select dados_json#>>'{homologacao,chave}' from f.operacao_fiscal where id = v_op) is distinct from v_chave_hom
     or (select status from f.operacao_fiscal where id = v_op) <> 'PRONTO_HOMOLOGACAO' then
    raise exception 'homologacao nao ficou na operacao';
  end if;

  -- Portao de producao: com a homologacao autorizada mas o perfil sem revisao/liberacao (como
  -- fica depois de uma mudanca de tributacao, ex. cEnq 108 -> 109 em 18/09/2026), a producao e
  -- recusada antes de qualquer envio, tanto na consulta (fn_nfe_producao_pronta) quanto no
  -- gatilho da emissao (trg_bloquear_nfe_producao_sem_perfil_liberado), aqui religado so para isso.
  update f.documento_fiscal_emissao set payload_enviado = '{"items":[{"cfop":"5903"}]}'::jsonb where documento_fiscal_id = v_doc_hom;
  v_prontidao := f.fn_nfe_producao_pronta(v_sol);
  if coalesce((v_prontidao->>'pronta')::boolean, true) then
    raise exception 'portao liberou producao com perfil nao liberado: %', v_prontidao;
  end if;
  if coalesce(v_prontidao->>'motivo', '') not ilike 'Perfis precisam estar liberados para esta homologacao%' then
    raise exception 'portao recusou por outro motivo antes de chegar ao perfil: %', v_prontidao;
  end if;
  execute 'alter table f.documento_fiscal_emissao enable trigger trg_bloquear_nfe_producao_sem_perfil_liberado';
  begin
    insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, cliente_id, nfe_status, origem, valor_total)
    values ('1e160000-0000-4000-8000-000000000503', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'PENDENTE:X', '55', '2', '72', 'SAIDA', 'PRODUTO', 916001, 'RASCUNHO', 'EMITIDO', 1600);
    insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
    values ('1e160000-0000-4000-8000-000000000503', v_sol, '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'NFEP-RET-0', 'PRODUCAO', 'RASCUNHO');
    raise exception 'gatilho aceitou emissao de producao com perfil nao liberado';
  exception when others then
    if sqlerrm not like 'Producao bloqueada:%' then raise; end if;
  end;
  execute 'alter table f.documento_fiscal_emissao disable trigger trg_bloquear_nfe_producao_sem_perfil_liberado';

  -- Producao autorizada: baixa a remessa.
  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, cliente_id, nfe_status, origem, valor_total)
  values ('1e160000-0000-4000-8000-000000000502', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'PENDENTE:P', '55', '2', '71', 'SAIDA', 'PRODUTO', 916001, 'RASCUNHO', 'EMITIDO', 1600);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
  values ('1e160000-0000-4000-8000-000000000502', v_sol, '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'NFEP-RET-1', 'PRODUCAO', 'RASCUNHO');
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_prod, numero = 71, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e160000-0000-4000-8000-000000000502';
  select * into v_r from f.remessas_terceiros where id = v_rem;
  if v_r.status <> 'RETORNADA' or v_r.nfe_retorno_id <> '1e160000-0000-4000-8000-000000000502' or v_r.retornada_em is null or v_r.cfop_retorno <> '5903' then
    raise exception 'producao nao baixou a remessa: %', row_to_json(v_r);
  end if;
  if (select status from f.operacao_fiscal where id = v_op) <> 'CONCLUIDA'
     or (select chave_primeira_nota from f.operacao_fiscal where id = v_op) <> v_chave_prod
     or (select ambiente from f.operacao_fiscal where id = v_op) <> 'PRODUCAO' then
    raise exception 'operacao RETORNO nao concluiu: %', (select row_to_json(o) from f.operacao_fiscal o where o.id = v_op);
  end if;
  if exists (select 1 from f.remessa_controle rc where rc.tenant_id = '1e160000-0000-4000-8000-000000000001') then
    raise exception 'retorno abriu controle de remessa (isso e da REMESSA, nao do RETORNO)';
  end if;
  -- Remessa baixada nao gera outro retorno.
  begin
    perform f.fn_remessa_terceiros_retorno_criar(v_rem, '5902', 9::smallint, null, null);
    raise exception 'gerou retorno de remessa RETORNADA';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Remessa RETORNADA: so remessa ABERTA gera retorno.' then raise; end if;
  end;

  -- NF-e EMITIDA: sem contas a receber (tPag 90) e sem estoque.
  update f.documento_fiscal set nfe_status = 'EMITIDA', chave_acesso = v_chave_prod where id = '1e160000-0000-4000-8000-000000000502';
  if exists (select 1 from f.titulo t where t.documento_fiscal_id = '1e160000-0000-4000-8000-000000000502') then
    raise exception 'retorno gerou contas a receber';
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos then
    raise exception 'retorno mexeu no estoque';
  end if;

  -- Cancelamento da nota de producao: a mercadoria continua em nosso poder.
  update f.documento_fiscal_emissao set status = 'CANCELADA' where documento_fiscal_id = '1e160000-0000-4000-8000-000000000502';
  select * into v_r from f.remessas_terceiros where id = v_rem;
  if v_r.status <> 'ABERTA' or v_r.nfe_retorno_id is not null or v_r.retornada_em is not null or v_r.homologada_em is null then
    raise exception 'cancelamento nao reabriu a remessa: %', row_to_json(v_r);
  end if;
end;
$test$;

-- 5 ---------------------------------------------------------------- producao e RLS
select set_config('request.jwt.claim.sub', '1e160000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e160000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

do $test$
declare
  v_res jsonb;
  v_cfg jsonb;
begin
  if exists (select 1 from f.retorno_terceiros_config where producao_ligada) then
    raise exception 'producao nasceu ligada';
  end if;
  v_res := f.fn_retorno_terceiros_producao_ligar(true);
  select to_jsonb(c) into v_cfg from f.retorno_terceiros_config c where c.tenant_id = '1e160000-0000-4000-8000-000000000001';
  if (v_res->>'producao_ligada')::boolean is not true or coalesce((v_cfg->>'producao_ligada')::boolean, false) is not true
     or v_cfg->>'ligada_por' <> '1e160000-0000-4000-8000-000000000011' then
    raise exception 'ADMIN nao conseguiu ligar a producao: % / %', v_res, coalesce(v_cfg::text, 'linha invisivel');
  end if;
  perform f.fn_retorno_terceiros_producao_ligar(false);
  if exists (select 1 from f.retorno_terceiros_config where tenant_id = '1e160000-0000-4000-8000-000000000001' and producao_ligada) then
    raise exception 'ADMIN nao conseguiu desligar a producao';
  end if;
  if (select count(*) from f.remessas_terceiros) <> 1 or (select count(*) from f.remessas_terceiros_itens) <> 1 then
    raise exception 'RLS nao entregou a remessa ao usuario da empresa';
  end if;
end;
$test$;

reset role;
select set_config('request.jwt.claim.sub', '1e160000-0000-4000-8000-000000000020', true);
select set_config('request.jwt.claims', '{"sub":"1e160000-0000-4000-8000-000000000020","role":"authenticated"}', true);
set local role authenticated;
do $test$
begin
  begin
    perform f.fn_retorno_terceiros_producao_ligar(true);
    raise exception 'DIRETOR ligou a producao';
  exception when sqlstate '42501' then
    null;
  end;
end;
$test$;

-- 6 ---------------------------------------------------------------- remessa de TESTE de homologacao
-- (migration 20260918160000): a mesma chave da remessa real (reaberta no fim do bloco 4) entra em
-- linha propria com a caixa marcada; sem a caixa continua recusada; o retorno do teste so homologa;
-- a producao e recusada no banco; a exclusao apaga o teste e a real fica intacta.
reset role;
select set_config('request.jwt.claim.sub', '1e160000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claims', '{"sub":"1e160000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $test$
declare
  v_xml text := (select xml from xml_origem);
  v_real uuid := (select id from retorno_ids where nome = 'remessa');
  v_real_antes jsonb := (select to_jsonb(r) - 'updated_at' from f.remessas_terceiros r where r.id = (select id from retorno_ids where nome = 'remessa'));
  v_res jsonb;
  v_teste uuid;
begin
  -- Sem a caixa: chave repetida continua recusada.
  begin
    perform f.fn_remessa_terceiros_importar(v_xml);
    raise exception 'importou a chave da remessa real sem a caixa de teste';
  exception when sqlstate '23505' then
    if sqlerrm not like 'NF-e % ja importada.' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_importar(v_xml, false);
    raise exception 'importou a chave da remessa real com p_teste false';
  exception when sqlstate '23505' then null;
  end;

  -- Com a caixa: linha propria, is_teste, ABERTA; a real nao muda.
  v_res := f.fn_remessa_terceiros_importar(v_xml, true);
  v_teste := (v_res->>'remessa_id')::uuid;
  if (v_res->>'teste')::boolean is not true or v_teste = v_real
     or (select (r.is_teste, r.status, r.chave) from f.remessas_terceiros r where r.id = v_teste) is distinct from (true, 'ABERTA'::text, '42260660621141000404550010009003561304254706'::text)
     or (select count(*) from f.remessas_terceiros_itens where remessa_id = v_teste) <> 1 then
    raise exception 'importacao de teste errada: %', v_res;
  end if;
  if (select to_jsonb(r) - 'updated_at' from f.remessas_terceiros r where r.id = v_real) <> v_real_antes then
    raise exception 'a remessa real mudou com a importacao de teste';
  end if;
  insert into retorno_ids values ('teste', v_teste);

  -- Um teste por chave.
  begin
    perform f.fn_remessa_terceiros_importar(v_xml, true);
    raise exception 'aceitou segundo teste da mesma chave';
  exception when sqlstate '23505' then
    if sqlerrm not like 'Teste de homologacao da NF-e % ja existe%' then raise; end if;
  end;

  -- Situacao em linguagem simples (migration 20260918170000): a) usado -> 5902, b) nao usado -> 5903,
  -- c) parcial recusado no banco; o CFOP continua aceito para chamadas antigas.
  v_res := f.fn_remessa_terceiros_retorno_criar(p_remessa_id => v_teste, p_situacao => 'USADO');
  if v_res->>'cfop' <> '5902' or v_res->>'situacao' <> 'USADO'
     or (select cfop from f.solicitacao_item where solicitacao_id = (v_res->>'solicitacao_id')::uuid) <> '5902'
     or (select sf.operacao_snapshot#>>'{retorno_terceiros,situacao}' from f.solicitacao_faturamento sf where sf.id = (v_res->>'solicitacao_id')::uuid) <> 'USADO' then
    raise exception 'situacao USADO nao virou 5902: %', v_res;
  end if;
  v_res := f.fn_remessa_terceiros_retorno_criar(p_remessa_id => v_teste, p_situacao => 'nao_usado');
  if v_res->>'cfop' <> '5903' or v_res->>'situacao' <> 'NAO_USADO'
     or (select cfop from f.solicitacao_item where solicitacao_id = (v_res->>'solicitacao_id')::uuid) <> '5903'
     or (select perfil_operacao_id from f.solicitacao_item where solicitacao_id = (v_res->>'solicitacao_id')::uuid) <> '1e160000-0000-4000-8000-000000000303' then
    raise exception 'situacao NAO_USADO nao virou 5903 com o perfil 5903: %', v_res;
  end if;
  begin
    perform f.fn_remessa_terceiros_retorno_criar(p_remessa_id => v_teste, p_situacao => 'PARCIAL');
    raise exception 'banco aceitou retorno parcial';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Retorno parcial (parte usada, parte devolvida) ainda nao esta disponivel%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_terceiros_retorno_criar(p_remessa_id => v_teste, p_situacao => 'CONSERTADO');
    raise exception 'aceitou CONSERTADO numa industrializacao';
  exception when sqlstate '22023' then null;
  end;

  -- Retorno do teste: solicitacao e operacao marcadas como teste.
  v_res := f.fn_remessa_terceiros_retorno_criar(v_teste, '5902', 0::smallint, 'TESTE DE HOMOLOGACAO', null);
  if (v_res->>'teste')::boolean is not true
     or (select o.dados_json->>'remessa_teste' from f.operacao_fiscal o where o.id = (v_res->>'operacao_id')::uuid) <> 'true'
     or (select sf.operacao_snapshot#>>'{retorno_terceiros,teste}' from f.solicitacao_faturamento sf where sf.id = (v_res->>'solicitacao_id')::uuid) <> 'true'
     or (select cst_ipi || '/' || ipi_codigo_enquadramento_legal || '/' || cbenef from f.solicitacao_item where solicitacao_id = (v_res->>'solicitacao_id')::uuid) <> '55/109/SC840008' then
    raise exception 'retorno de teste nao ficou marcado: %', v_res;
  end if;
  insert into retorno_ids values ('op_teste', (v_res->>'operacao_id')::uuid), ('sol_teste', (v_res->>'solicitacao_id')::uuid);

  -- A real nao pode ser excluida por esta funcao.
  begin
    perform f.fn_remessa_terceiros_teste_excluir(v_real);
    raise exception 'excluiu a remessa real';
  exception when sqlstate '22023' then null;
  end;
end;
$test$;

-- Emissoes do teste (como a Edge, com service_role): homologacao autorizada so carimba; producao e recusada
-- pelo gatilho do teste mesmo com o portao do perfil desligado (segue desligado desde o bloco 4).
reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $test$
declare
  v_real uuid := (select id from retorno_ids where nome = 'remessa');
  v_teste uuid := (select id from retorno_ids where nome = 'teste');
  v_sol uuid := (select id from retorno_ids where nome = 'sol_teste');
  v_real_antes jsonb := (select to_jsonb(r) - 'updated_at' from f.remessas_terceiros r where r.id = (select id from retorno_ids where nome = 'remessa'));
  v_r f.remessas_terceiros%rowtype;
begin
  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, cliente_id, nfe_status, origem, valor_total)
  values ('1e160000-0000-4000-8000-000000000504', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'PENDENTE:T', '55', '2', '73', 'SAIDA', 'PRODUTO', 916001, 'RASCUNHO', 'EMITIDO', 1600);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
  values ('1e160000-0000-4000-8000-000000000504', v_sol, '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'NFEH-RET-T', 'HOMOLOGACAO', 'RASCUNHO');
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = '42260913671448000189550020000000731000000003', numero = 73, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e160000-0000-4000-8000-000000000504';
  select * into v_r from f.remessas_terceiros where id = v_teste;
  if v_r.status <> 'ABERTA' or v_r.homologada_em is null or v_r.nfe_homologacao_id <> '1e160000-0000-4000-8000-000000000504' or v_r.nfe_retorno_id is not null then
    raise exception 'homologacao do teste nao carimbou (ou baixou): %', row_to_json(v_r);
  end if;
  if (select to_jsonb(r) - 'updated_at' from f.remessas_terceiros r where r.id = v_real) <> v_real_antes then
    raise exception 'a remessa real mudou com a homologacao do teste';
  end if;

  -- Producao do teste: recusada no banco.
  begin
    insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, cliente_id, nfe_status, origem, valor_total)
    values ('1e160000-0000-4000-8000-000000000505', '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'PENDENTE:U', '55', '2', '74', 'SAIDA', 'PRODUTO', 916001, 'RASCUNHO', 'EMITIDO', 1600);
    insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
    values ('1e160000-0000-4000-8000-000000000505', v_sol, '1e160000-0000-4000-8000-000000000001', '1e160000-0000-4000-8000-000000000002', 'NFEP-RET-T', 'PRODUCAO', 'RASCUNHO');
    raise exception 'banco aceitou emissao de producao de um retorno de teste';
  exception when sqlstate '55000' then
    if sqlerrm not like 'Producao bloqueada: retorno de remessa de terceiros de TESTE%' then raise; end if;
  end;
  if exists (select 1 from f.documento_fiscal_emissao where solicitacao_id = v_sol and ambiente = 'PRODUCAO') then
    raise exception 'emissao de producao do teste ficou gravada';
  end if;
  select * into v_r from f.remessas_terceiros where id = v_teste;
  if v_r.status <> 'ABERTA' or v_r.nfe_retorno_id is not null or v_r.retornada_em is not null then
    raise exception 'teste foi baixado: %', row_to_json(v_r);
  end if;
end;
$test$;

-- Excluir o teste (usuario ADMIN): solicitacao cancelada, linha apagada, real intacta.
reset role;
select set_config('request.jwt.claim.sub', '1e160000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claims', '{"sub":"1e160000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $test$
declare
  v_real uuid := (select id from retorno_ids where nome = 'remessa');
  v_teste uuid := (select id from retorno_ids where nome = 'teste');
  v_sol uuid := (select id from retorno_ids where nome = 'sol_teste');
  v_op uuid := (select id from retorno_ids where nome = 'op_teste');
  v_real_antes jsonb := (select to_jsonb(r) - 'updated_at' from f.remessas_terceiros r where r.id = (select id from retorno_ids where nome = 'remessa'));
  v_res jsonb;
begin
  v_res := f.fn_remessa_terceiros_teste_excluir(v_teste);
  if (v_res->>'excluida')::boolean is not true
     or exists (select 1 from f.remessas_terceiros where id = v_teste)
     or exists (select 1 from f.remessas_terceiros_itens where remessa_id = v_teste)
     or (select status from f.solicitacao_faturamento where id = v_sol) <> 'CANCELADA'
     or (select status from f.operacao_fiscal where id = v_op) <> 'CANCELADA' then
    raise exception 'exclusao do teste incompleta: %', v_res;
  end if;
  if (select to_jsonb(r) - 'updated_at' from f.remessas_terceiros r where r.id = v_real) is distinct from v_real_antes then
    raise exception 'a remessa real mudou com a exclusao do teste: antes=% depois=%', v_real_antes,
      (select to_jsonb(r) - 'updated_at' from f.remessas_terceiros r where r.id = v_real);
  end if;
  -- Depois de excluido, um novo teste da mesma chave volta a ser aceito.
  v_res := f.fn_remessa_terceiros_importar((select xml from xml_origem), true);
  if (v_res->>'teste')::boolean is not true then
    raise exception 'novo teste apos exclusao nao entrou: %', v_res;
  end if;
end;
$test$;

reset role;
rollback;
