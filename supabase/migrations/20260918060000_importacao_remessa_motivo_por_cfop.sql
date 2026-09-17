-- Importacao por remessa expressa: o titulo AP da nota de debito do courier vai para o plano do
-- destino da mercadoria. Em 3556 (uso e consumo) e 3551 (ativo) o motivo de compra passa a ser o de
-- consumo/investimento, nao "Compra para estoque" (regra do Gabriel em 18/09/2026, depois da NF-e
-- 2/24 sair com o rateio em 4.01 ESTOQUE / INSUMOS).
--
--   3101/3102 -> o motivo escolhido na tela (padrao ESTOQUE);
--   3556      -> motivo CONSUMO_PRODUCAO (ou o primeiro CONSUMO_* ativo) quando o escolhido nao e de consumo;
--   3551      -> motivo INVESTIMENTO* quando o escolhido nao e de investimento.
-- O rateio do titulo continua sendo o plano de contas do motivo. O titulo ja criado (UPS 2953830,
-- importacao 6f420998...) e corrigido aqui: motivo CONSUMO - PRODUCAO E ENGENHARIA e rateio em
-- CONSUMO - MATERIAIS GERAIS.

create or replace function f.fn_importacao_remessa_motivo_por_cfop(p_tenant_id uuid, p_cfop text, p_motivo_id uuid)
returns uuid
language plpgsql
stable
set search_path to 'pg_catalog'
as $$
declare
  v_codigo text;
  v_escolhido uuid;
begin
  select mc.codigo into v_codigo from f.motivo_compra mc where mc.id = p_motivo_id and mc.tenant_id = p_tenant_id and mc.deleted_at is null and mc.ativo;
  if p_cfop = '3556' then
    if v_codigo ~* '^CONSUMO' then return p_motivo_id; end if;
    select mc.id into v_escolhido from f.motivo_compra mc
     where mc.tenant_id = p_tenant_id and mc.deleted_at is null and mc.ativo and mc.codigo ~* '^CONSUMO'
     order by (mc.codigo = 'CONSUMO_PRODUCAO') desc, mc.favorito desc, mc.ordem, mc.nome limit 1;
    return coalesce(v_escolhido, p_motivo_id);
  elsif p_cfop = '3551' then
    if v_codigo ~* '^INVESTIMENTO' then return p_motivo_id; end if;
    select mc.id into v_escolhido from f.motivo_compra mc
     where mc.tenant_id = p_tenant_id and mc.deleted_at is null and mc.ativo and mc.codigo ~* '^INVESTIMENTO'
     order by mc.favorito desc, mc.ordem, mc.nome limit 1;
    return coalesce(v_escolhido, p_motivo_id);
  end if;
  return p_motivo_id;
end;
$$;
revoke all on function f.fn_importacao_remessa_motivo_por_cfop(uuid, text, uuid) from public, anon;
grant execute on function f.fn_importacao_remessa_motivo_por_cfop(uuid, text, uuid) to authenticated, service_role;

create or replace function f.fn_importacao_remessa_criar(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_dir jsonb;
  v_bloqueios text[];
  v_em_uso jsonb;
  v_substituir boolean := coalesce((p_dados->>'substituir')::boolean, false);
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_uf_emitente text;
  v_cfop text := regexp_replace(coalesce(p_dados->>'cfop', ''), '[^0-9]', '', 'g');
  v_natureza text;
  v_consumidor_final smallint;
  v_credito_icms boolean;
  v_aliquota numeric(5,2);
  v_cambio numeric(12,6);
  v_valor_usd numeric(15,2);
  v_frete_usd numeric(15,2);
  v_valor_brl numeric(15,2);
  v_frete_brl numeric(15,2);
  v_aduaneiro numeric(15,2);
  v_ii numeric(15,2);
  v_bc numeric(15,2);
  v_icms numeric(15,2);
  v_nota numeric(15,2);
  v_gnre_valor numeric(15,2);
  v_courier_servicos numeric(15,2) := coalesce(nullif(p_dados->'courier'->>'servicos', '')::numeric, 0);
  v_courier_armazenagem numeric(15,2) := coalesce(nullif(p_dados->'courier'->>'armazenagem', '')::numeric, 0);
  v_nd jsonb := coalesce(p_dados->'nota_debito', '{}'::jsonb);
  v_exp jsonb := coalesce(p_dados->'exportador', '{}'::jsonb);
  v_itens_req jsonb := p_dados->'itens';
  v_itens_dir jsonb;
  v_n integer;
  v_i integer;
  v_soma_usd numeric(15,2);
  v_acum_merc numeric(15,2) := 0;
  v_acum_frete numeric(15,2) := 0;
  v_acum_adu numeric(15,2) := 0;
  v_acum_ii numeric(15,2) := 0;
  v_acum_bc numeric(15,2) := 0;
  v_acum_icms numeric(15,2) := 0;
  v_acum_courier numeric(15,2) := 0;
  v_req jsonb;
  v_dir_item jsonb;
  v_item_merc numeric(15,2);
  v_item_frete numeric(15,2);
  v_item_adu numeric(15,2);
  v_item_ii numeric(15,2);
  v_item_bc numeric(15,2);
  v_item_icms numeric(15,2);
  v_item_courier numeric(15,2);
  v_item_qtd numeric(15,4);
  v_item_ncm text;
  v_item_id integer;
  v_item_codigo text;
  v_item_desc text;
  v_item_un text;
  v_item_fab text;
  v_imp_id uuid := gen_random_uuid();
  v_sol_id uuid := gen_random_uuid();
  v_perfil_id uuid;
  v_perfil_codigo text;
  v_local text;
  v_uf_desemb text;
  v_data_desemb date;
  v_via smallint := coalesce(nullif(p_dados->>'via_transporte', '')::smallint, 4);
  v_intermedio smallint := coalesce(nullif(p_dados->>'forma_intermedio', '')::smallint, 1);
  v_exp_codigo text;
  v_itens_snapshot jsonb := '[]'::jsonb;
  v_item_row f.importacao_remessa_item%rowtype;
  v_data_registro_txt text;
  v_dir_numero text;
  v_awb text;
  v_conta uuid;
  v_forma text;
  v_motivo_compra uuid;
  v_motivo_escolhido uuid;
  v_motivo_codigo text;
  v_motivo_nome text;
  v_uso_proprio text;
  v_observacao text := nullif(btrim(coalesce(p_dados->>'observacao', '')), '');
  v_nd_valor numeric(15,2);
  v_texto_fisco text;
  v_texto_cpl text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  -- 6.1 DIR lida e validada de novo aqui: a tela nunca e a unica barreira.
  v_dir := f.fn_importacao_remessa_ler_dir(p_dados->>'xml');
  select coalesce(array_agg(b), '{}') into v_bloqueios from jsonb_array_elements_text(v_dir->'bloqueios') b;
  if cardinality(v_bloqueios) > 0 then
    raise exception using errcode = '22023', message = 'DIR bloqueada: ' || array_to_string(v_bloqueios, ' ');
  end if;
  v_em_uso := v_dir->'em_uso';
  v_dir_numero := v_dir->'dir'->>'numero';
  v_awb := v_dir->>'awb';

  -- 6.2 Emitente (cadastro fiscal congelado no snapshot, como nas outras operacoes).
  select * into v_empresa from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id and e.deleted_at is null;
  select * into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  select * into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
  if v_endereco.id is null or v_fiscal.id is null then
    raise exception using errcode = '22023', message = 'Cadastro fiscal do emitente incompleto (endereco ou dados fiscais).';
  end if;
  v_uf_emitente := upper(v_endereco.uf::text);

  -- 6.3 CFOP -> natureza. Os perfis de importacao sao 3101/3102/3556/3551.
  v_natureza := case v_cfop
    when '3101' then 'IMPORTACAO_INDUSTRIALIZACAO'
    when '3102' then 'IMPORTACAO_COMERCIALIZACAO'
    when '3556' then 'IMPORTACAO_CONSUMO'
    when '3551' then 'IMPORTACAO_ATIVO'
  end;
  if v_natureza is null then
    raise exception using errcode = '22023', message = format('CFOP %s nao vale para a importacao. Use 3101 (industrializacao), 3102 (revenda), 3556 (uso e consumo) ou 3551 (ativo imobilizado).', coalesce(nullif(v_cfop, ''), '?'));
  end if;
  v_consumidor_final := case when v_cfop in ('3556', '3551') then 1 else 0 end;
  v_credito_icms := v_cfop in ('3101', '3102');

  -- 6.4 Valores da DIR e da tela.
  v_cambio := (v_dir->'remessa'->>'cambio')::numeric;
  v_valor_usd := coalesce((v_dir->'remessa'->>'valor_usd')::numeric, 0);
  v_frete_usd := coalesce((v_dir->'remessa'->>'frete_usd')::numeric, 0);
  v_valor_brl := coalesce((v_dir->'remessa'->>'valor_brl')::numeric, 0);
  v_frete_brl := coalesce((v_dir->'remessa'->>'frete_brl')::numeric, 0);
  v_aduaneiro := (v_dir->'remessa'->>'tributavel_brl')::numeric;
  v_ii := coalesce((v_dir->'ii'->>'valor')::numeric, 0);
  if v_cambio is null or v_cambio <= 0 then
    raise exception using errcode = '22023', message = 'A DIR nao traz a taxa de cambio da data de registro.';
  end if;
  if abs((v_valor_brl + v_frete_brl) - v_aduaneiro) > 0.05 then
    raise exception using errcode = '22023',
      message = format('Na DIR, mercadoria (R$ %s) + frete (R$ %s) nao fecham com o valor tributavel (R$ %s).', v_valor_brl, v_frete_brl, v_aduaneiro);
  end if;
  if (v_dir->'ii'->>'devido') is not null and abs((v_dir->'ii'->>'devido')::numeric - v_ii) > 0.005 then
    raise exception using errcode = '22023', message = format('II devido (R$ %s) difere do II informado na remessa (R$ %s).', v_dir->'ii'->>'devido', v_ii);
  end if;
  v_aliquota := nullif(p_dados->>'aliquota_icms', '')::numeric;
  if v_aliquota is null or v_aliquota < 0 or v_aliquota >= 100 then
    raise exception using errcode = '22023', message = 'Informe a aliquota do ICMS da importacao (ex.: 17).';
  end if;
  v_gnre_valor := nullif(p_dados->'gnre'->>'valor', '')::numeric;
  if v_gnre_valor is null then
    raise exception using errcode = '22023', message = 'Informe o valor da GNRE paga (ICMS da importacao).';
  end if;
  -- ICMS "por dentro": BC = (vProd + II) / (1 - aliquota); ICMS = BC x aliquota (LC 87/96, art. 13, V e par. 1o).
  v_bc := round((v_aduaneiro + v_ii) / (1 - v_aliquota / 100), 2);
  v_icms := round(v_bc * v_aliquota / 100, 2);
  if abs(v_icms - v_gnre_valor) > 0.05 then
    raise exception using errcode = '22023',
      message = format('ICMS calculado R$ %s (BC R$ %s a %s%%) difere da GNRE R$ %s em R$ %s. Confira a aliquota ou o valor da GNRE antes de gerar a nota.',
        f.fn_importacao_brl(v_icms), f.fn_importacao_brl(v_bc), f.fn_importacao_brl(v_aliquota),
        f.fn_importacao_brl(v_gnre_valor), f.fn_importacao_brl(abs(v_icms - v_gnre_valor)));
  end if;
  v_nota := round(v_aduaneiro + v_ii + v_icms, 2);
  if v_courier_servicos < 0 or v_courier_armazenagem < 0 then
    raise exception using errcode = '22023', message = 'Despesas do courier nao podem ser negativas.';
  end if;

  -- 6.5 Desembaraco: da UA quando conhecida; a tela pode informar.
  v_local := upper(nullif(btrim(coalesce(p_dados->>'local_desembaraco', v_dir->'dir'->>'local_desembaraco', '')), ''));
  v_uf_desemb := upper(nullif(btrim(coalesce(p_dados->>'uf_desembaraco', v_dir->'dir'->>'uf_desembaraco', '')), ''));
  v_data_desemb := coalesce(nullif(p_dados->>'data_desembaraco', '')::date, (v_dir->'dir'->>'data_desembaraco')::date);
  if v_local is null or v_uf_desemb !~ '^[A-Z]{2}$' or v_data_desemb is null then
    raise exception using errcode = '22023', message = format('Informe o local, a UF e a data do desembaraco (UA de entrada %s nao consta na tabela).', v_dir->'dir'->>'ua_entrada');
  end if;
  if v_via not between 1 and 13 then
    raise exception using errcode = '22023', message = 'Via de transporte fora da tabela tpViaTransp (1 a 13).';
  end if;
  if v_intermedio not in (1, 2, 3) then
    raise exception using errcode = '22023', message = 'Forma de intermediacao deve ser 1 (conta propria), 2 (conta e ordem) ou 3 (encomenda).';
  end if;

  -- 6.6 Exportador: destinatario da nota de entrada, no exterior.
  if nullif(btrim(coalesce(v_exp->>'nome', '')), '') is null or nullif(btrim(coalesce(v_exp->>'logradouro', '')), '') is null then
    raise exception using errcode = '22023', message = 'Informe o nome e o endereco do exportador (conforme a invoice).';
  end if;
  if coalesce(v_exp->>'pais_codigo', '') !~ '^[0-9]{2,4}$' or nullif(btrim(coalesce(v_exp->>'pais_nome', '')), '') is null then
    raise exception using errcode = '22023', message = 'Informe o pais do exportador (codigo BACEN e nome).';
  end if;
  if v_exp->>'pais_codigo' = '1058' then
    raise exception using errcode = '22023', message = 'O exportador nao pode estar no Brasil (pais 1058).';
  end if;
  v_exp_codigo := left(upper(nullif(btrim(coalesce(v_exp->>'codigo', '')), '')), 60);
  if v_exp_codigo is null then
    v_exp_codigo := left(regexp_replace(upper(v_exp->>'nome'), '[^A-Z0-9]+', '-', 'g'), 60);
  end if;
  if v_exp->>'id_estrangeiro' is not null and (char_length(btrim(v_exp->>'id_estrangeiro')) < 5 or char_length(btrim(v_exp->>'id_estrangeiro')) > 20) then
    raise exception using errcode = '22023', message = 'A identificacao do exportador (idEstrangeiro) deve ter de 5 a 20 caracteres.';
  end if;

  -- 6.7 Itens: um por mercadoria da DIR, com NCM, item do catalogo e fabricante da tela.
  v_itens_dir := v_dir->'itens';
  v_n := jsonb_array_length(v_itens_dir);
  if jsonb_typeof(v_itens_req) <> 'array' or jsonb_array_length(v_itens_req) <> v_n then
    raise exception using errcode = '22023', message = format('Informe os dados de cada uma das %s mercadorias da DIR.', v_n);
  end if;
  select sum((e->>'valor_usd')::numeric) into v_soma_usd from jsonb_array_elements(v_itens_dir) e;
  if coalesce(v_soma_usd, 0) <= 0 then
    raise exception using errcode = '22023', message = 'As mercadorias da DIR nao tem valor.';
  end if;

  -- 6.8 Nota de debito do courier (despesa da importacao).
  v_nd_valor := nullif(v_nd->>'valor', '')::numeric;
  if nullif(btrim(coalesce(v_nd->>'numero', '')), '') is not null and (v_nd_valor is null or v_nd_valor <= 0) then
    raise exception using errcode = '22023', message = 'Informe o valor da nota de debito do courier.';
  end if;
  v_conta := nullif(v_nd->>'conta_bancaria_id', '')::uuid;
  v_forma := nullif(upper(btrim(coalesce(v_nd->>'forma_pagamento', ''))), '');
  if v_forma is not null and v_forma not in ('PIX', 'BOLETO', 'TRANSFERENCIA', 'DINHEIRO', 'CARTAO', 'OUTROS') then
    raise exception using errcode = '22023', message = 'Forma de pagamento da nota de debito invalida (PIX, BOLETO, TRANSFERENCIA, DINHEIRO, CARTAO ou OUTROS).';
  end if;
  if v_conta is not null and not exists (
    select 1 from f.conta_bancaria cb where cb.id = v_conta and cb.tenant_id = v_scope.tenant_id and cb.empresa_id = v_scope.empresa_id and cb.deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Conta bancaria da nota de debito nao encontrada.';
  end if;
  v_motivo_escolhido := nullif(v_nd->>'motivo_compra_id', '')::uuid;
  if v_motivo_escolhido is null then
    select mc.id into v_motivo_escolhido from f.motivo_compra mc
     where mc.tenant_id = v_scope.tenant_id and mc.deleted_at is null and mc.ativo and mc.codigo = 'ESTOQUE'
     order by mc.favorito desc, mc.ordem limit 1;
  end if;
  -- O plano do titulo segue o destino: 3556 vai para consumo, 3551 para investimento (o motivo
  -- escolhido so fica quando ja e desse tipo). Em 3101/3102 vale o escolhido.
  v_motivo_compra := f.fn_importacao_remessa_motivo_por_cfop(v_scope.tenant_id, v_cfop, v_motivo_escolhido);
  select mc.codigo, mc.nome into v_motivo_codigo, v_motivo_nome from f.motivo_compra mc where mc.id = v_motivo_compra;

  -- 6.8b Trava de destino: uso proprio nao entra em 3101/3102 (industrializacao/revenda).
  v_uso_proprio := f.fn_importacao_remessa_uso_proprio(v_observacao, v_motivo_codigo, v_motivo_nome);
  if v_uso_proprio is not null and v_cfop in ('3101', '3102') then
    raise exception using errcode = '22023',
      message = format('Uso proprio indicado (%s) nao combina com o CFOP %s (%s). Use 3556 (uso e consumo) ou 3551 (ativo imobilizado), ou corrija a observacao e o motivo de compra.',
        v_uso_proprio, v_cfop, case when v_cfop = '3101' then 'industrializacao' else 'revenda' end);
  end if;

  -- 6.8c Uma DIR so gera uma nota: a anterior sai do caminho so depois de tudo validado.
  if v_em_uso is not null and jsonb_typeof(v_em_uso) = 'object' then
    if not v_substituir then
      raise exception using errcode = '23505',
        message = format('A DIR %s ja esta em uso na importacao %s (status %s%s). Uma DIR so gera uma nota; cancele a anterior ou peca para gerar de novo.',
          v_dir_numero, v_em_uso->>'importacao_id', v_em_uso->>'status',
          case when v_em_uso->>'nfe_numero' is not null then format(', NF-e %s/%s', v_em_uso->>'nfe_serie', v_em_uso->>'nfe_numero') else '' end);
    end if;
    -- Gerar de novo: so sem nota real; fn_importacao_remessa_cancelar decide.
    perform f.fn_importacao_remessa_cancelar((v_em_uso->>'importacao_id')::uuid, 'Importacao gerada de novo pela tela de operacoes');
  end if;

  -- 6.9 Perfil de operacao (so importa para os portoes de producao): natureza + CFOP + UF EX.
  select po.id, po.codigo into v_perfil_id, v_perfil_codigo
  from f.perfil_operacao po
  where po.tenant_id = v_scope.tenant_id and (po.empresa_id = v_scope.empresa_id or po.empresa_id is null)
    and po.modelo = 'NFE' and po.natureza_operacao = v_natureza and po.cfop_externo = v_cfop
    and po.faixa_automacao <> 'BLOQUEADO' and po.vigencia_inicio <= current_date and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
  order by po.habilitado_producao desc, po.revisao_fiscal_em desc nulls last
  limit 1;

  v_data_registro_txt := to_char(((v_dir->'dir'->>'data_registro')::timestamp), 'DD/MM/YYYY');

  -- 6.10 Importacao.
  insert into f.importacao_remessa (
    id, tenant_id, empresa_id, status, awb, master, dir_numero, dir_lote, dir_data_registro, dir_situacao,
    manifesto_numero, manifesto_data, ua_entrada, pais_origem_codigo, destinatario_documento,
    remetente_dir_nome, remetente_dir_endereco, remetente_dir_pais_codigo, regime_tributacao, moeda, volumes, peso,
    local_desembaraco, uf_desembaraco, data_desembaraco, via_transporte, forma_intermedio,
    cambio, valor_mercadoria_usd, frete_usd, frete_modo, valor_mercadoria_brl, frete_brl, valor_aduaneiro_brl,
    ii_valor, ii_pendente, aliquota_icms, bc_icms, icms_valor, valor_nota,
    gnre_numero, gnre_receita, gnre_uf, gnre_valor,
    courier_nome, courier_cnpj, courier_servicos, courier_armazenagem,
    nota_debito_numero, nota_debito_valor, nota_debito_emissao, nota_debito_pago_em, nota_debito_conta_bancaria_id, nota_debito_forma_pagamento, nota_debito_motivo_compra_id,
    exportador_nome, exportador_logradouro, exportador_numero, exportador_complemento, exportador_bairro,
    exportador_pais_codigo, exportador_pais_nome, exportador_codigo, exportador_id_estrangeiro,
    natureza_operacao, cfop, consumidor_final, credito_icms, perfil_operacao_id, solicitacao_id, xml_dir, observacao, dados_json, criado_por
  ) values (
    v_imp_id, v_scope.tenant_id, v_scope.empresa_id, 'RASCUNHO', v_awb, v_dir->>'master', v_dir_numero, v_dir->'dir'->>'lote',
    (v_dir->'dir'->>'data_registro')::timestamp at time zone 'America/Sao_Paulo', v_dir->'dir'->>'situacao',
    v_dir->'manifesto'->>'numero', nullif(v_dir->'manifesto'->>'data', '')::timestamp at time zone 'America/Sao_Paulo',
    v_dir->'dir'->>'ua_entrada', v_dir->'manifesto'->>'pais_origem', v_dir->'destinatario'->>'documento',
    v_dir->'remetente'->>'nome', btrim(concat_ws(', ', nullif(v_dir->'remetente'->>'logradouro', ''), nullif(v_dir->'remetente'->>'complemento', ''))), v_dir->'remetente'->>'pais_codigo',
    (v_itens_dir->0->>'regime_tributacao'), (v_itens_dir->0->>'moeda'), (v_dir->'remessa'->>'volumes')::integer, (v_dir->'remessa'->>'peso')::numeric,
    v_local, v_uf_desemb, v_data_desemb, v_via, v_intermedio,
    v_cambio, v_valor_usd, v_frete_usd, v_dir->'remessa'->>'frete_modo', v_valor_brl, v_frete_brl, v_aduaneiro,
    v_ii, coalesce((v_dir->'ii'->>'pendente')::numeric, 0), v_aliquota, v_bc, v_icms, v_nota,
    nullif(btrim(coalesce(p_dados->'gnre'->>'numero', '')), ''), nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), ''), nullif(upper(btrim(coalesce(p_dados->'gnre'->>'uf', ''))), ''), v_gnre_valor,
    v_dir->'courier'->>'nome', v_dir->'courier'->>'cnpj', v_courier_servicos, v_courier_armazenagem,
    nullif(btrim(coalesce(v_nd->>'numero', '')), ''), v_nd_valor, nullif(v_nd->>'emissao', '')::date, nullif(v_nd->>'pago_em', '')::date, v_conta, v_forma, v_motivo_compra,
    left(btrim(v_exp->>'nome'), 60), left(btrim(v_exp->>'logradouro'), 60), left(coalesce(nullif(btrim(coalesce(v_exp->>'numero', '')), ''), 'S/N'), 60),
    left(nullif(btrim(coalesce(v_exp->>'complemento', '')), ''), 60), left(coalesce(nullif(btrim(coalesce(v_exp->>'bairro', '')), ''), 'EXTERIOR'), 60),
    v_exp->>'pais_codigo', left(upper(btrim(v_exp->>'pais_nome')), 60), v_exp_codigo, nullif(btrim(coalesce(v_exp->>'id_estrangeiro', '')), ''),
    v_natureza, v_cfop, v_consumidor_final, v_credito_icms, v_perfil_id, v_sol_id, p_dados->>'xml', v_observacao,
    jsonb_build_object('dir', v_dir - 'itens' - 'bloqueios' - 'em_uso', 'perfil_codigo', v_perfil_codigo, 'uso_proprio', v_uso_proprio,
                       'motivo_compra', jsonb_build_object('id', v_motivo_compra, 'codigo', v_motivo_codigo, 'nome', v_motivo_nome,
                                                           'escolhido_id', v_motivo_escolhido, 'trocado_pelo_cfop', v_motivo_compra is distinct from v_motivo_escolhido)),
    v_scope.usuario_id
  );

  -- 6.11 Itens: rateio proporcional ao valor em dolar; o ultimo fecha as pontas dos centavos.
  for v_i in 0 .. v_n - 1 loop
    v_dir_item := v_itens_dir->v_i;
    v_req := v_itens_req->v_i;
    v_item_qtd := coalesce(nullif(v_req->>'quantidade', '')::numeric, (v_dir_item->>'quantidade')::numeric);
    v_item_ncm := regexp_replace(coalesce(v_req->>'ncm', ''), '[^0-9]', '', 'g');
    v_item_id := nullif(v_req->>'item_id', '')::integer;
    v_item_codigo := nullif(btrim(coalesce(v_req->>'codigo', '')), '');
    v_item_desc := nullif(btrim(coalesce(v_req->>'descricao', '')), '');
    v_item_un := upper(nullif(btrim(coalesce(v_req->>'unidade', '')), ''));
    v_item_fab := nullif(btrim(coalesce(v_req->>'fabricante', '')), '');
    if v_item_qtd is null or v_item_qtd <= 0 then
      raise exception using errcode = '22023', message = format('Mercadoria %s: quantidade invalida.', v_i + 1);
    end if;
    if v_item_ncm !~ '^[0-9]{8}$' then
      raise exception using errcode = '22023', message = format('Mercadoria %s: NCM deve ter 8 digitos (o HS da invoice nao serve).', v_i + 1);
    end if;
    if v_item_fab is null then
      raise exception using errcode = '22023', message = format('Mercadoria %s: informe o fabricante (cFabricante da adicao).', v_i + 1);
    end if;
    if v_item_id is not null then
      select i.id, coalesce(v_item_codigo, i.codigo_interno), coalesce(v_item_desc, i.nome), coalesce(v_item_un, upper(i.unidade_medida))
        into v_item_id, v_item_codigo, v_item_desc, v_item_un
      from public.itens i
      where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id and i.id = v_item_id and i.ativo;
      if not found then
        raise exception using errcode = '22023', message = format('Mercadoria %s: item do catalogo %s nao encontrado nesta empresa.', v_i + 1, v_req->>'item_id');
      end if;
    end if;
    if v_item_codigo is null or v_item_desc is null or v_item_un is null then
      raise exception using errcode = '22023', message = format('Mercadoria %s: informe codigo, descricao e unidade (ou escolha o item do catalogo).', v_i + 1);
    end if;
    -- O valor aduaneiro (vProd) e rateado direto do valor tributavel da DIR: mercadoria + frete
    -- podem nao fechar com ele no centavo (228,85 + 209,11 = 437,96 contra 437,97 na DIR da UPS).
    -- O ICMS de cada item e base x aliquota (a SEFAZ confere item a item); o total da nota passa
    -- a ser a soma dos itens, que pode diferir da GNRE em centavos (tolerancia de 5 centavos).
    if v_i = v_n - 1 then
      v_item_merc := v_valor_brl - v_acum_merc;
      v_item_frete := v_frete_brl - v_acum_frete;
      v_item_adu := v_aduaneiro - v_acum_adu;
      v_item_ii := v_ii - v_acum_ii;
      v_item_bc := v_bc - v_acum_bc;
      v_item_courier := (v_courier_servicos + v_courier_armazenagem) - v_acum_courier;
    else
      v_item_merc := round(v_valor_brl * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_frete := round(v_frete_brl * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_adu := round(v_aduaneiro * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_ii := round(v_ii * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_bc := round(v_bc * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_courier := round((v_courier_servicos + v_courier_armazenagem) * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
    end if;
    v_item_icms := round(v_item_bc * v_aliquota / 100, 2);
    v_acum_merc := v_acum_merc + v_item_merc; v_acum_frete := v_acum_frete + v_item_frete; v_acum_adu := v_acum_adu + v_item_adu;
    v_acum_ii := v_acum_ii + v_item_ii; v_acum_bc := v_acum_bc + v_item_bc; v_acum_icms := v_acum_icms + v_item_icms;
    v_acum_courier := v_acum_courier + v_item_courier;

    insert into f.importacao_remessa_item (
      importacao_id, tenant_id, empresa_id, ordem, sequencia_dir, item_id, codigo, descricao, ncm, unidade, quantidade, peso, fabricante,
      valor_usd, valor_mercadoria_brl, frete_brl, valor_aduaneiro_brl, valor_unitario_brl, ii_valor, bc_icms, icms_valor, courier_rateado,
      custo_total, custo_unitario
    ) values (
      v_imp_id, v_scope.tenant_id, v_scope.empresa_id, v_i + 1, v_dir_item->>'sequencia', v_item_id, left(v_item_codigo, 60), left(v_item_desc, 120), v_item_ncm,
      left(v_item_un, 6), v_item_qtd, (v_dir_item->>'peso')::numeric, left(v_item_fab, 60),
      (v_dir_item->>'valor_usd')::numeric, v_item_merc, v_item_frete, v_item_adu, round(v_item_adu / v_item_qtd, 10), v_item_ii, v_item_bc, v_item_icms, v_item_courier,
      round(v_item_adu + v_item_ii + v_item_courier + case when v_credito_icms then 0 else v_item_icms end, 2),
      round((v_item_adu + v_item_ii + v_item_courier + case when v_credito_icms then 0 else v_item_icms end) / v_item_qtd, 6)
    ) returning * into v_item_row;

    -- IBS/CBS: base do II acrescida dos tributos do caput, sem o ICMS (LC 214/2025, art. 69, §§ 1º e 2º).
    v_itens_snapshot := v_itens_snapshot || jsonb_build_object(
      'ordem', v_i + 1, 'sequencia_dir', v_dir_item->>'sequencia', 'adicao', 1, 'sequencial_adicao', v_i + 1, 'fabricante', left(v_item_fab, 60),
      'valor_aduaneiro', v_item_adu, 'ii', v_item_ii, 'bc_icms', v_item_bc, 'icms', v_item_icms, 'outras_despesas', v_item_icms,
      'base_ibs_cbs', round(v_item_adu + v_item_ii, 2)
    );
  end loop;
  -- Totais da nota = soma dos itens (o ICMS pode andar centavos em relacao ao calculo pela base total).
  if v_acum_icms <> v_icms then
    v_icms := v_acum_icms;
    v_nota := round(v_aduaneiro + v_ii + v_icms, 2);
    update f.importacao_remessa set icms_valor = v_icms, valor_nota = v_nota where id = v_imp_id;
  end if;

  -- 6.12 Textos da nota (o montador tambem os conhece; ficam no snapshot para a tela e a auditoria).
  v_texto_fisco := format('NF-E DE ENTRADA DE IMPORTACAO POR REMESSA EXPRESSA (RTS, REGIME DE TRIBUTACAO SIMPLIFICADA). DIR %s DE %s. II RECOLHIDO NA DIR. ICMS RECOLHIDO POR GNRE%s.',
    v_dir_numero, v_data_registro_txt,
    case when nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), '') is not null then format(' RECEITA %s', p_dados->'gnre'->>'receita') else '' end);
  v_texto_cpl := format('IMPORTACAO POR REMESSA EXPRESSA. AWB %s%s. DIR %s REGISTRADA EM %s, UA %s (%s/%s). CAMBIO %s. MERCADORIA USD %s; FRETE USD %s; VALOR ADUANEIRO R$ %s. II R$ %s. ICMS R$ %s (BC R$ %s A %s%%), GNRE%s R$ %s. NOTA DE DEBITO %s %s. REMETENTE CONFORME DIR: %s. EXPORTADOR CONFORME INVOICE: %s. DESPESAS DO COURIER (SERVICOS R$ %s, ARMAZENAGEM R$ %s) FORA DA NOTA. SEM COBRANCA.',
    v_awb, case when v_dir->'courier'->>'nome' is not null then ' ' || (v_dir->'courier'->>'nome') else '' end,
    v_dir_numero, v_data_registro_txt, v_dir->'dir'->>'ua_entrada', v_local, v_uf_desemb,
    replace(to_char(v_cambio, 'FM990D0000'), '.', ','), f.fn_importacao_brl(v_valor_usd), f.fn_importacao_brl(v_frete_usd), f.fn_importacao_brl(v_aduaneiro),
    f.fn_importacao_brl(v_ii), f.fn_importacao_brl(v_icms), f.fn_importacao_brl(v_bc), f.fn_importacao_brl(v_aliquota),
    case when nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), '') is not null then ' RECEITA ' || (p_dados->'gnre'->>'receita') else '' end,
    f.fn_importacao_brl(v_gnre_valor),
    coalesce(v_dir->'courier'->>'nome', 'DO COURIER'), coalesce(nullif(btrim(coalesce(v_nd->>'numero', '')), ''), 'NAO INFORMADA'),
    coalesce(v_dir->'remetente'->>'nome', '?'), upper(btrim(v_exp->>'nome')),
    f.fn_importacao_brl(v_courier_servicos), f.fn_importacao_brl(v_courier_armazenagem));
  v_texto_cpl := upper(v_texto_cpl);

  -- 6.13 Solicitacao de NF-e: entrada (tpNF 0), destino exterior (idDest 3), sem cobranca.
  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, natureza_operacao, observacao, criado_por,
    finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
    valor_frete, valor_seguro, valor_outras_despesas,
    destino_uf_confirmada, destino_confirmado_em, destino_confirmado_por,
    pagamento_forma, pagamento_indicador, pagamento_parcelas, transportador_dados, volumes_dados,
    revisao_fiscal_confirmada_em, revisao_fiscal_confirmada_por, perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por,
    emitente_snapshot, destinatario_snapshot, operacao_snapshot, snapshot_cadastro_em
  ) values (
    v_sol_id, v_scope.tenant_id, v_scope.empresa_id, null, 'PREVIA', v_natureza,
    v_observacao, v_scope.usuario_id,
    1, v_consumidor_final, 9, 9,
    0, 0, v_icms,
    'EX', now(), v_scope.usuario_id,
    '90', 0, null, null, null,
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
    jsonb_build_object(
      'id', null, 'documento', null, 'id_estrangeiro', nullif(btrim(coalesce(v_exp->>'id_estrangeiro', '')), ''),
      'nome', left(upper(btrim(v_exp->>'nome')), 60), 'inscricao_estadual', null, 'indicador_ie', '9',
      'email', null, 'telefone', null,
      'logradouro', left(upper(btrim(v_exp->>'logradouro')), 60), 'numero_endereco', left(coalesce(nullif(btrim(coalesce(v_exp->>'numero', '')), ''), 'S/N'), 60),
      'complemento', left(nullif(upper(btrim(coalesce(v_exp->>'complemento', ''))), ''), 60), 'bairro', left(coalesce(nullif(upper(btrim(coalesce(v_exp->>'bairro', ''))), ''), 'EXTERIOR'), 60),
      'cidade', 'EXTERIOR', 'uf', 'EX', 'codigo_ibge_municipio', '9999999', 'cep', null,
      'pais_codigo', v_exp->>'pais_codigo', 'pais_nome', left(upper(btrim(v_exp->>'pais_nome')), 60)
    ),
    jsonb_build_object(
      'natureza_operacao', v_natureza, 'finalidade_emissao', 1, 'consumidor_final', v_consumidor_final, 'presenca_comprador', 9,
      'tipo_documento', 0, 'local_destino', 3,
      'modalidade_frete', 9, 'valor_frete', 0, 'valor_seguro', 0, 'valor_outras_despesas', v_icms, 'valor_total_ii', v_ii,
      'destinacao_mercadoria', null, 'nfe_referenciada', null, 'transportador', null, 'volumes', null,
      'pagamento', jsonb_build_object('forma', '90', 'indicador', 0, 'descricao', null, 'parcelas', null, 'fatura_numero', null),
      'importacao', jsonb_build_object(
        'importacao_id', v_imp_id, 'awb', v_awb, 'courier_nome', v_dir->'courier'->>'nome', 'courier_cnpj', v_dir->'courier'->>'cnpj',
        'dir_numero', v_dir_numero, 'dir_data_registro', left(v_dir->'dir'->>'data_registro', 10), 'dir_data_registro_texto', v_data_registro_txt,
        'ua_entrada', v_dir->'dir'->>'ua_entrada', 'local_desembaraco', v_local, 'uf_desembaraco', v_uf_desemb, 'data_desembaraco', to_char(v_data_desemb, 'YYYY-MM-DD'),
        'via_transporte', v_via, 'forma_intermedio', v_intermedio, 'exportador_codigo', v_exp_codigo,
        'remetente_dir', v_dir->'remetente'->>'nome', 'regime_tributacao', (v_itens_dir->0->>'regime_tributacao'),
        'cambio', v_cambio, 'valor_mercadoria_usd', v_valor_usd, 'frete_usd', v_frete_usd,
        'valor_aduaneiro', v_aduaneiro, 'ii', v_ii, 'aliquota_icms', v_aliquota, 'bc_icms', v_bc, 'icms', v_icms, 'valor_nota', v_nota,
        'base_ibs_cbs', round(v_aduaneiro + v_ii, 2),
        'gnre', jsonb_build_object('numero', nullif(btrim(coalesce(p_dados->'gnre'->>'numero', '')), ''), 'receita', nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), ''),
                                   'uf', nullif(upper(btrim(coalesce(p_dados->'gnre'->>'uf', ''))), ''), 'valor', v_gnre_valor),
        'nota_debito', jsonb_build_object('numero', nullif(btrim(coalesce(v_nd->>'numero', '')), ''), 'valor', v_nd_valor),
        'courier_servicos', v_courier_servicos, 'courier_armazenagem', v_courier_armazenagem, 'credito_icms', v_credito_icms,
        'itens', v_itens_snapshot,
        'texto_fisco', v_texto_fisco, 'texto_complementar', v_texto_cpl
      )
    ),
    now()
  );

  -- 6.14 Itens fiscais da solicitacao: CST 00 a 17% (modBC 3), IPI 03/999, PIS/COFINS 98, IBS/CBS 000/000001,
  --      origem 1, vUnCom = valor aduaneiro / quantidade.
  for v_item_row in select * from f.importacao_remessa_item i where i.importacao_id = v_imp_id order by i.ordem loop
    insert into f.solicitacao_item (
      id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, origem_item_id, item_id, descricao, ncm, cest, cfop,
      cst_icms, csosn, cbenef, reducao_base_icms_percentual, aliquota_icms, icms_modalidade_base_calculo,
      cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins, aliquota_pis, aliquota_cofins,
      cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json,
      quantidade, unidade, unidade_tributavel, valor_unitario, valor_desconto, ordem, codigo_produto, origem_mercadoria,
      perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por, tributacao_fonte, modelo
    ) values (
      gen_random_uuid(), v_sol_id, v_scope.tenant_id, v_scope.empresa_id, 'IMPORTACAO', v_imp_id::text, v_item_row.id::text, v_item_row.item_id,
      v_item_row.descricao, v_item_row.ncm, null, v_cfop,
      '00', null, null, 0, v_aliquota, '3',
      '03', '999', null, '98', '98', null, null,
      '000', '000001', null, jsonb_build_object('ibs_uf_aliquota', 0.1, 'ibs_mun_aliquota', 0, 'cbs_aliquota', 0.9),
      v_item_row.quantidade, v_item_row.unidade, v_item_row.unidade, v_item_row.valor_unitario_brl, 0, v_item_row.ordem, v_item_row.codigo, 1,
      v_perfil_id, case when v_perfil_id is null then null else now() end, case when v_perfil_id is null then null else v_scope.usuario_id end,
      case when v_perfil_id is null then null else 'PERFIL' end, 'NFE'
    );
  end loop;

  return jsonb_build_object(
    'importacao_id', v_imp_id, 'solicitacao_id', v_sol_id, 'cfop', v_cfop, 'natureza_operacao', v_natureza,
    'valor_aduaneiro', v_aduaneiro, 'ii', v_ii, 'bc_icms', v_bc, 'icms', v_icms, 'valor_nota', v_nota,
    'base_ibs_cbs', round(v_aduaneiro + v_ii, 2),
    'itens', v_n, 'perfil_id', v_perfil_id, 'perfil_codigo', v_perfil_codigo, 'destinatario', upper(btrim(v_exp->>'nome')),
    'motivo_compra_id', v_motivo_compra, 'motivo_compra_codigo', v_motivo_codigo,
    'substituiu', case when v_em_uso is not null and jsonb_typeof(v_em_uso) = 'object' then v_em_uso->>'importacao_id' end
  );
end;
$$;
revoke all on function f.fn_importacao_remessa_criar(jsonb) from public, anon;
grant execute on function f.fn_importacao_remessa_criar(jsonb) to authenticated, service_role;

-- A nota de debito editavel (fn_importacao_remessa_nota_debito_atualizar) tambem respeita o destino.
create or replace function f.fn_importacao_remessa_nota_debito_atualizar(p_importacao_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_imp f.importacao_remessa%rowtype;
  v_numero text := nullif(btrim(coalesce(p_dados->>'numero', '')), '');
  v_valor numeric(15,2) := nullif(p_dados->>'valor', '')::numeric;
  v_emissao date := nullif(p_dados->>'emissao', '')::date;
  v_pago_em date := nullif(p_dados->>'pago_em', '')::date;
  v_conta uuid := nullif(p_dados->>'conta_bancaria_id', '')::uuid;
  v_forma text := nullif(upper(btrim(coalesce(p_dados->>'forma_pagamento', ''))), '');
  v_motivo uuid := nullif(p_dados->>'motivo_compra_id', '')::uuid;
  v_servicos numeric(15,2) := nullif(p_dados->>'courier_servicos', '')::numeric;
  v_armazenagem numeric(15,2) := nullif(p_dados->>'courier_armazenagem', '')::numeric;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_imp from f.importacao_remessa i
   where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id and i.id = p_importacao_id and i.deleted_at is null
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Importacao nao encontrada.';
  end if;
  if v_imp.status in ('CONCLUIDA', 'CANCELADA') then
    raise exception using errcode = '55000', message = 'A importacao ja foi concluida ou cancelada; a nota de debito ja esta no contas a pagar (ou nao ha o que lancar).';
  end if;
  if v_numero is not null and (v_valor is null or v_valor <= 0) then
    raise exception using errcode = '22023', message = 'Informe o valor da nota de debito do courier.';
  end if;
  if v_forma is not null and v_forma not in ('PIX', 'BOLETO', 'TRANSFERENCIA', 'DINHEIRO', 'CARTAO', 'OUTROS') then
    raise exception using errcode = '22023', message = 'Forma de pagamento da nota de debito invalida (PIX, BOLETO, TRANSFERENCIA, DINHEIRO, CARTAO ou OUTROS).';
  end if;
  if v_conta is not null and not exists (
    select 1 from f.conta_bancaria cb where cb.id = v_conta and cb.tenant_id = v_scope.tenant_id and cb.empresa_id = v_scope.empresa_id and cb.deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Conta bancaria da nota de debito nao encontrada.';
  end if;
  if v_pago_em is not null and (v_conta is null or v_forma is null) then
    raise exception using errcode = '22023', message = 'Nota de debito paga: informe a conta bancaria e a forma de pagamento.';
  end if;
  if coalesce(v_servicos, 0) < 0 or coalesce(v_armazenagem, 0) < 0 then
    raise exception using errcode = '22023', message = 'Despesas do courier nao podem ser negativas.';
  end if;
  v_motivo := f.fn_importacao_remessa_motivo_por_cfop(v_scope.tenant_id, v_imp.cfop, coalesce(v_motivo, v_imp.nota_debito_motivo_compra_id));

  update f.importacao_remessa
     set nota_debito_numero = v_numero,
         nota_debito_valor = case when v_numero is null then null else v_valor end,
         nota_debito_emissao = v_emissao,
         nota_debito_pago_em = v_pago_em,
         nota_debito_conta_bancaria_id = case when v_pago_em is null then null else v_conta end,
         nota_debito_forma_pagamento = case when v_pago_em is null then null else v_forma end,
         nota_debito_motivo_compra_id = coalesce(v_motivo, nota_debito_motivo_compra_id),
         courier_servicos = coalesce(v_servicos, courier_servicos),
         courier_armazenagem = coalesce(v_armazenagem, courier_armazenagem),
         updated_at = now()
   where id = v_imp.id;
  -- O custo de estoque leva as despesas do courier: refaz o rateio quando elas mudaram.
  if v_servicos is not null or v_armazenagem is not null then
    update f.importacao_remessa_item it
       set courier_rateado = sub.rateado,
           custo_total = round(it.valor_aduaneiro_brl + it.ii_valor + sub.rateado + case when v_imp.credito_icms then 0 else it.icms_valor end, 2),
           custo_unitario = round((it.valor_aduaneiro_brl + it.ii_valor + sub.rateado + case when v_imp.credito_icms then 0 else it.icms_valor end) / it.quantidade, 6)
      from (
        select i.id, round((coalesce(v_servicos, v_imp.courier_servicos) + coalesce(v_armazenagem, v_imp.courier_armazenagem)) * i.valor_usd / nullif(sum(i.valor_usd) over (), 0), 2) as rateado
          from f.importacao_remessa_item i where i.importacao_id = v_imp.id
      ) sub
     where it.id = sub.id;
  end if;
  return jsonb_build_object('ok', true, 'importacao_id', v_imp.id, 'nota_debito_numero', v_numero, 'nota_debito_pago_em', v_pago_em, 'motivo_compra_id', v_motivo);
end;
$$;

-- Titulo ja criado pela NF-e 2/24 (importacao 6f420998-c0b6-4a27-a2ca-c52bc5f030e1, CFOP 3556):
-- motivo e rateio saem de "Compra para estoque" (4.01) e vao para consumo. So mexe se o titulo
-- ainda esta com o motivo de estoque e nao foi pago.
do $$
declare
  v_titulo uuid := '258af6c2-acca-4e71-8221-6837b11afcd9';
  v_imp uuid := '6f420998-c0b6-4a27-a2ca-c52bc5f030e1';
  v_tenant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_motivo uuid;
  v_plano uuid;
begin
  if not exists (select 1 from f.titulo t where t.id = v_titulo and t.tenant_id = v_tenant and t.deleted_at is null and t.status in ('PENDENTE', 'APROVADO', 'AGENDADO')) then
    raise notice 'titulo da nota de debito UPS 2953830 nao encontrado em aberto; nada a corrigir';
    return;
  end if;
  v_motivo := f.fn_importacao_remessa_motivo_por_cfop(v_tenant, '3556', (select nota_debito_motivo_compra_id from f.importacao_remessa where id = v_imp));
  select mc.plano_contas_id into v_plano from f.motivo_compra mc where mc.id = v_motivo;
  if v_motivo is null or v_plano is null then
    raise exception 'motivo de consumo (ou o plano dele) nao encontrado para corrigir o titulo da UPS';
  end if;
  update f.titulo set motivo_compra_id = v_motivo, updated_at = now() where id = v_titulo;
  update f.titulo_rateio set plano_contas_id = v_plano, updated_at = now() where titulo_id = v_titulo and deleted_at is null;
  update f.importacao_remessa
     set nota_debito_motivo_compra_id = v_motivo,
         dados_json = dados_json || jsonb_build_object('motivo_compra', coalesce(dados_json->'motivo_compra', '{}'::jsonb) || jsonb_build_object('id', v_motivo, 'corrigido_em', now(), 'motivo_correcao', 'rateio de 3556 no plano de consumo (18/09/2026)')),
         updated_at = now()
   where id = v_imp;
  raise notice 'titulo % corrigido: motivo %, plano %', v_titulo, v_motivo, v_plano;
end $$;

-- Reversao: reaplicar fn_importacao_remessa_criar e fn_importacao_remessa_nota_debito_atualizar de
-- 20260918020000/010000, drop function f.fn_importacao_remessa_motivo_por_cfop(uuid, text, uuid);
-- o titulo 258af6c2... volta ao motivo 712ddc83 (ESTOQUE) e ao plano 1a310a57 (4.01).
