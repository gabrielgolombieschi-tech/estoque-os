\set ON_ERROR_STOP on

begin;

do $contrato$
begin
  if to_regprocedure(
    'f.fn_perfil_operacao_nfe_revisar(uuid,text,text,text,numeric,numeric,numeric,text,boolean,boolean)'
  ) is not null then
    raise exception 'A assinatura antiga ainda permite revisar e liberar no mesmo ato.';
  end if;
  if to_regprocedure(
    'f.fn_perfil_operacao_nfe_revisar(uuid,text,text,text,numeric,numeric,numeric,text)'
  ) is null then
    raise exception 'RPC separada de revisao nao encontrada.';
  end if;
  if to_regprocedure(
    'f.fn_perfil_operacao_nfe_liberar_producao(uuid,uuid,text,boolean)'
  ) is null then
    raise exception 'RPC controlada de liberacao nao encontrada.';
  end if;
  if has_table_privilege('authenticated', 'f.perfil_operacao', 'INSERT')
     or has_table_privilege('authenticated', 'f.perfil_operacao', 'UPDATE')
     or has_table_privilege('authenticated', 'f.perfil_operacao', 'DELETE') then
    raise exception 'Authenticated ainda possui DML direto em f.perfil_operacao.';
  end if;
  if not has_table_privilege('authenticated', 'f.perfil_operacao', 'SELECT') then
    raise exception 'Authenticated perdeu a leitura de f.perfil_operacao.';
  end if;
  if has_table_privilege('authenticated', 'f.perfil_operacao_revisao_evento', 'INSERT')
     or has_table_privilege('authenticated', 'f.perfil_operacao_revisao_evento', 'UPDATE')
     or has_table_privilege('authenticated', 'f.perfil_operacao_revisao_evento', 'DELETE') then
    raise exception 'Authenticated possui DML na trilha append-only.';
  end if;
  if not has_table_privilege('service_role', 'f.perfil_operacao_revisao_evento', 'SELECT')
     or not has_table_privilege('service_role', 'f.perfil_operacao_revisao_evento', 'INSERT')
     or has_table_privilege('service_role', 'f.perfil_operacao_revisao_evento', 'UPDATE')
     or has_table_privilege('service_role', 'f.perfil_operacao_revisao_evento', 'DELETE') then
    raise exception 'ACL da trilha append-only para o backend nao esta restrita a SELECT/INSERT.';
  end if;
end;
$contrato$;

insert into auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '17000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'perfil-fiscal@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"nome":"Revisor fiscal"}'::jsonb, now(), now()
);

insert into public.tenants (id, nome, ativo)
values ('17000000-0000-4000-8000-000000000010', 'Tenant perfil fiscal', true);
insert into c.tenant (id, codigo, nome, ativo)
values ('17000000-0000-4000-8000-000000000010', 'PERFIL-FISCAL', 'Tenant perfil fiscal', true);

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values (
  '17000000-0000-4000-8000-000000000020',
  '17000000-0000-4000-8000-000000000010',
  'PERFIL-A', 'Empresa perfil fiscal LTDA', 'Empresa perfil fiscal', '17000000000170', true
);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values (
  '17000000-0000-4000-8000-000000000020',
  '17000000-0000-4000-8000-000000000010',
  '17000000000170', 'Empresa perfil fiscal LTDA', 'Empresa perfil fiscal', true
);
insert into c.empresa_fiscal (empresa_id, crt, serie_nfe, certificado_validade_em)
values ('17000000-0000-4000-8000-000000000020', 3, 2, current_date + 365);

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values (
  '17000000-0000-4000-8000-000000000030',
  '17000000-0000-4000-8000-000000000001',
  'Revisor fiscal', 'perfil-fiscal@example.test', true
);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values (
  '17000000-0000-4000-8000-000000000030',
  '17000000-0000-4000-8000-000000000010', 'ADMIN', true
);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values (
  '17000000-0000-4000-8000-000000000030',
  '17000000-0000-4000-8000-000000000020', 'DIRETOR', true
);
insert into public.user_tenant_context (user_id, tenant_id)
values (
  '17000000-0000-4000-8000-000000000001',
  '17000000-0000-4000-8000-000000000010'
);
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values (
  '17000000-0000-4000-8000-000000000001',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020'
);

insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop,
  origem, cst_completo, cst_icms, aliquota_icms_observada,
  aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa,
  justificativa_faixa
) values (
  '17000000-0000-4000-8000-000000000040',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'teste-perfil.sql', 1, 'Venda de mercadoria adquirida', '5102',
  2, '200', '00', 12, 0, false, 1, 1, array['85371020'], array[1],
  'Cenario controlado de teste', 'REVISAO', 'Revisao fiscal obrigatoria'
);

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao,
  natureza_texto, crt, cfop_interno, cst_icms, cst_pis, cst_cofins,
  evidencia_id, faixa_automacao, origem_mercadoria, cbenef_aplicacao,
  ambito_destino, ufs_destino, indicador_ie_destinatario,
  icms_modalidade_base_calculo, finalidade_emissao, consumidor_final,
  habilitado_producao
) values (
  '17000000-0000-4000-8000-000000000050',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'PERFIL-TESTE-5102', 'Perfil teste 5102', 'NFE',
  'VENDA_MERCADORIA_TERCEIROS', 'Venda de mercadoria adquirida',
  '3', '5102', '00', '01', '01',
  '17000000-0000-4000-8000-000000000040', 'REVISAO', 2, 'SEM_BENEFICIO',
  'INTERNA', array['SC'], '1', '3', 1, 0, false
);

insert into f.solicitacao_faturamento (
  id, tenant_id, empresa_id, status, natureza_operacao,
  revisao_fiscal_confirmada_em, revisao_fiscal_confirmada_por,
  emitente_snapshot, destinatario_snapshot, operacao_snapshot,
  snapshot_cadastro_em, destino_uf_confirmada, destino_confirmado_em,
  destino_confirmado_por, perfil_aplicado_em, perfil_aplicado_por
) values (
  '17000000-0000-4000-8000-000000000060',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'APROVADA', 'VENDA_MERCADORIA_TERCEIROS', now(),
  '17000000-0000-4000-8000-000000000030',
  '{"uf":"SC"}', '{"uf":"SC","indicador_ie":"1"}',
  '{"finalidade_emissao":1,"consumidor_final":0}', now(),
  'SC', now(), '17000000-0000-4000-8000-000000000030', now(),
  '17000000-0000-4000-8000-000000000030'
);

insert into f.solicitacao_item (
  id, solicitacao_id, tenant_id, empresa_id, origem_tipo, descricao,
  quantidade, valor_unitario, ordem, perfil_operacao_id, cfop,
  origem_mercadoria, cst_ibs_cbs, cclass_trib, cclass_trib_versao,
  ibs_cbs_json
) values (
  '17000000-0000-4000-8000-000000000070',
  '17000000-0000-4000-8000-000000000060',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'AVULSO', 'Item do perfil', 1, 100, 1,
  '17000000-0000-4000-8000-000000000050', '5102', 2,
  '000', '000001', 'Informe Técnico 2025.002 v1.60',
  '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'
);

alter table f.documento_fiscal disable trigger trg_documento_fiscal__ar_nfe;
insert into f.documento_fiscal (
  id, tenant_id, empresa_id, chave_acesso, modelo, valor_total,
  operacao, natureza, origem, nfe_status
) values (
  '17000000-0000-4000-8000-000000000080',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  repeat('7', 44), '55', 100, 'SAIDA', 'PRODUTO', 'EMITIDO', 'EMITIDA'
);
alter table f.documento_fiscal enable trigger trg_documento_fiscal__ar_nfe;

insert into f.documento_fiscal_emissao (
  documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
  referencia_externa, ambiente, status, payload_enviado, autorizado_em
) values (
  '17000000-0000-4000-8000-000000000080',
  '17000000-0000-4000-8000-000000000060',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'NFEH-PERFIL-TESTE', 'HOMOLOGACAO', 'AUTORIZADA',
  '{"items":[{"numero_item":1,"ibs_cbs_situacao_tributaria":"000","ibs_cbs_classificacao_tributaria":"000001","ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}]}',
  now() + interval '1 hour'
);

insert into f.documento_fiscal_item (
  id, tenant_id, empresa_id, documento_fiscal_id, item_n, descricao,
  quantidade, valor_unitario, valor_total, cst_ibs_cbs, cclass_trib,
  cclass_trib_versao, ibs_cbs_json, snapshot_fiscal_em
) values (
  '17000000-0000-4000-8000-000000000090',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  '17000000-0000-4000-8000-000000000080',
  1, 'Item do perfil', 1, 100, 100, '000', '000001',
  'Informe Técnico 2025.002 v1.60',
  '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}',
  now() + interval '1 hour'
);

select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"17000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $acl_direto$
begin
  begin
    update f.perfil_operacao
    set cst_ibs_cbs = '999'
    where id = '17000000-0000-4000-8000-000000000050';
    raise exception 'UPDATE direto do perfil foi aceito.';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into f.perfil_operacao_revisao_evento (
      tenant_id, empresa_id, perfil_operacao_id, tipo,
      antes, depois, justificativa
    ) values (
      '17000000-0000-4000-8000-000000000010',
      '17000000-0000-4000-8000-000000000020',
      '17000000-0000-4000-8000-000000000050',
      'REVISAO', '{}', '{}', 'Tentativa direta indevida'
    );
    raise exception 'INSERT direto na auditoria foi aceito.';
  exception
    when insufficient_privilege then null;
  end;
end;
$acl_direto$;

select f.fn_perfil_operacao_nfe_revisar(
  '17000000-0000-4000-8000-000000000050',
  '000', '000001', 'Informe Técnico 2025.002 v1.60',
  0.1, 0, 0.9,
  'Conferencia da tabela oficial vigente para o perfil de teste.'
);

do $revisao$
declare
  v_lista jsonb;
begin
  if not exists (
    select 1 from f.perfil_operacao
    where id = '17000000-0000-4000-8000-000000000050'
      and cst_ibs_cbs = '000'
      and cclass_trib = '000001'
      and cclass_trib_versao = 'Informe Técnico 2025.002 v1.60'
      and not habilitado_producao
      and revisao_fiscal_em is not null
  ) then
    raise exception 'A revisao nao persistiu os seis campos com producao desabilitada.';
  end if;
  if not exists (
    select 1 from f.perfil_operacao_revisao_evento
    where perfil_operacao_id = '17000000-0000-4000-8000-000000000050'
      and tipo = 'REVISAO'
      and antes->>'habilitado_producao' = 'false'
      and depois->>'habilitado_producao' = 'false'
  ) then
    raise exception 'Evento append-only de REVISAO nao foi gravado com BEFORE/AFTER.';
  end if;

  v_lista := f.fn_perfil_operacao_nfe_homologacoes_listar(
    '17000000-0000-4000-8000-000000000050'
  );
  if jsonb_array_length(v_lista->'homologacoes') <> 1
     or (v_lista->'homologacoes'->0->>'apos_ultima_revisao')::boolean is not true
     or (v_lista->'homologacoes'->0->>'cancelamento_em_andamento')::boolean is not false then
    raise exception 'A homologacao autorizada posterior a revisao nao foi listada corretamente.';
  end if;
end;
$revisao$;

reset role;
do $auditoria_append_only$
begin
  begin
    update f.perfil_operacao_revisao_evento
    set justificativa = 'Tentativa indevida de alterar o evento ja registrado.'
    where perfil_operacao_id = '17000000-0000-4000-8000-000000000050';
    raise exception 'UPDATE da trilha append-only foi aceito pelo owner.';
  exception
    when object_not_in_prerequisite_state then null;
  end;

  begin
    delete from f.perfil_operacao_revisao_evento
    where perfil_operacao_id = '17000000-0000-4000-8000-000000000050';
    raise exception 'DELETE da trilha append-only foi aceito pelo owner.';
  exception
    when object_not_in_prerequisite_state then null;
  end;
end;
$auditoria_append_only$;

insert into f.documento_fiscal_evento (
  id, documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
  status, resposta, criado_por, created_at
) values (
  '17000000-0000-4000-8000-0000000000a0',
  '17000000-0000-4000-8000-000000000080',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'CANCELAMENTO', 'Claim de cancelamento concorrente do teste.',
  'ENVIANDO', '{"claim_duravel":true}', null, now()
);
set local role authenticated;

do $cancelamento_bloqueia_liberacao$
begin
  begin
    perform f.fn_perfil_operacao_nfe_liberar_producao(
      '17000000-0000-4000-8000-000000000050',
      '17000000-0000-4000-8000-000000000060',
      'Tentativa que deve aguardar o cancelamento da homologacao.',
      true
    );
    raise exception 'A liberacao ignorou cancelamento ENVIANDO da homologacao.';
  exception
    when object_not_in_prerequisite_state then null;
  end;
end;
$cancelamento_bloqueia_liberacao$;

reset role;
insert into f.documento_fiscal_evento (
  id, documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
  status, resposta, criado_por, created_at
) values (
  '17000000-0000-4000-8000-0000000000a1',
  '17000000-0000-4000-8000-000000000080',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'CANCELAMENTO', 'Falha conclusiva do cancelamento concorrente do teste.',
  'ERRO', '{}', null, now() + interval '1 second'
);
set local role authenticated;

select f.fn_perfil_operacao_nfe_liberar_producao(
  '17000000-0000-4000-8000-000000000050',
  '17000000-0000-4000-8000-000000000060',
  'Equivalencia exata conferida na NF-e autorizada em homologacao.',
  true
);

do $liberacao$
declare
  v_prontidao jsonb;
begin
  if not exists (
    select 1 from f.perfil_operacao
    where id = '17000000-0000-4000-8000-000000000050'
      and habilitado_producao
      and producao_homologacao_solicitacao_id = '17000000-0000-4000-8000-000000000060'
      and producao_homologacao_documento_id = '17000000-0000-4000-8000-000000000080'
  ) then
    raise exception 'A liberacao nao ficou vinculada a solicitacao/documento homologados.';
  end if;
  if not exists (
    select 1 from f.perfil_operacao_revisao_evento
    where perfil_operacao_id = '17000000-0000-4000-8000-000000000050'
      and tipo = 'LIBERACAO'
      and homologacao_solicitacao_id = '17000000-0000-4000-8000-000000000060'
      and homologacao_documento_id = '17000000-0000-4000-8000-000000000080'
      and antes->>'habilitado_producao' = 'false'
      and depois->>'habilitado_producao' = 'true'
  ) then
    raise exception 'Evento append-only de LIBERACAO nao foi gravado com BEFORE/AFTER.';
  end if;

  v_prontidao := f.fn_nfe_producao_pronta('17000000-0000-4000-8000-000000000060');
  if coalesce((v_prontidao->>'pronta')::boolean, false) is not true then
    raise exception 'Portao final recusou o perfil corretamente liberado: %', v_prontidao;
  end if;
end;
$liberacao$;

reset role;
insert into f.documento_fiscal_evento (
  id, documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
  status, resposta, criado_por, created_at
) values (
  '17000000-0000-4000-8000-0000000000a2',
  '17000000-0000-4000-8000-000000000080',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'CANCELAMENTO', 'Novo claim concorrente depois da liberacao do perfil.',
  'ENVIANDO', '{"claim_duravel":true}', null, now() + interval '2 seconds'
);
set local role authenticated;

do $cancelamento_bloqueia_portao$
declare
  v_prontidao jsonb;
begin
  v_prontidao := f.fn_nfe_producao_pronta('17000000-0000-4000-8000-000000000060');
  if coalesce((v_prontidao->>'pronta')::boolean, false)
     or v_prontidao->>'motivo' not like '%cancelamento em andamento%' then
    raise exception 'Portao final ignorou cancelamento ENVIANDO: %', v_prontidao;
  end if;
end;
$cancelamento_bloqueia_portao$;

reset role;
insert into f.documento_fiscal_evento (
  id, documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
  status, resposta, criado_por, created_at
) values (
  '17000000-0000-4000-8000-0000000000a3',
  '17000000-0000-4000-8000-000000000080',
  '17000000-0000-4000-8000-000000000010',
  '17000000-0000-4000-8000-000000000020',
  'CANCELAMENTO', 'Conclusao com erro do novo claim concorrente do teste.',
  'ERRO', '{}', null, now() + interval '3 seconds'
);
set local role authenticated;

select f.fn_perfil_operacao_nfe_revisar(
  '17000000-0000-4000-8000-000000000050',
  '000', '000001', 'Informe Técnico 2025.002 v1.60',
  0.1, 0, 0.9,
  'Nova conferencia que deve revogar a liberacao anterior do teste.'
);

do $revogacao$
declare
  v_prontidao jsonb;
begin
  if exists (
    select 1 from f.perfil_operacao
    where id = '17000000-0000-4000-8000-000000000050'
      and habilitado_producao
  ) then
    raise exception 'Nova revisao nao revogou a liberacao anterior.';
  end if;
  if not exists (
    select 1 from f.perfil_operacao_revisao_evento
    where perfil_operacao_id = '17000000-0000-4000-8000-000000000050'
      and tipo = 'DESABILITACAO'
      and homologacao_solicitacao_id = '17000000-0000-4000-8000-000000000060'
      and homologacao_documento_id = '17000000-0000-4000-8000-000000000080'
      and antes->>'habilitado_producao' = 'true'
      and depois->>'habilitado_producao' = 'false'
  ) then
    raise exception 'Evento append-only de DESABILITACAO nao foi gravado.';
  end if;

  v_prontidao := f.fn_nfe_producao_pronta('17000000-0000-4000-8000-000000000060');
  if coalesce((v_prontidao->>'pronta')::boolean, false) then
    raise exception 'Portao final aceitou perfil depois de uma nova revisao.';
  end if;
end;
$revogacao$;

reset role;
rollback;
