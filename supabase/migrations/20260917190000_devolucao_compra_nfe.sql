-- Devolucao de compra emitida pelo ERP (NF-e finNFe 4) pelo pipeline de sempre.
--
-- Pedido do Gabriel em 17/09/2026: devolver 41,55 kg do item 2 (401014, tubo 76,10x3,75) da
-- NF-e 121481/3 da Acos America (chave 42260808819200000182550030001214811001242895).
-- Orientacao da contadora, no papel: CFOP 5201, saida tributada, CST ICMS o da origem (00),
-- IPI fora da base do ICMS como na nota de origem, transporte com 1 volume e 41,55 kg.
--
-- Ate aqui a aba DEVOLUCAO de /faturamento/operacoes so preparava a operacao (f.operacao_fiscal
-- + itens validados contra o XML, fn_devolucao_compra_criar) e esperava uma chave digitada.
-- Agora f.fn_devolucao_compra_nfe_criar reaproveita essa validacao e monta a solicitacao de
-- NF-e (f.solicitacao_faturamento + itens) exatamente como o retorno de terceiros: nfe-emitir
-- manda para a Focus em homologacao, o perfil e liberado pela tela de perfis e
-- nfe-emitir-producao emite a nota real. Tributacao e textos no montador
-- (supabase/functions/_shared/fiscal/devolucao-compra.ts).
--
-- Regras:
--   - destinatario = emitente da NF-e de entrada, do XML (nunca do cadastro);
--   - item = espelho proporcional da linha de origem (cProd, xProd, NCM, unidade, valor
--     unitario; CST e aliquotas de ICMS, IPI, PIS e COFINS do XML); IBS/CBS 000/000001;
--   - finNFe 4, NFref com a chave de entrada, tPag 90 (sem cobranca), sem destinacao;
--   - a soma das devolucoes de cada linha nunca passa da quantidade do XML (regra ja
--     existente em fn_devolucao_compra_criar);
--   - a autorizacao em PRODUCAO da baixa no estoque (movimentacao de saida) quando ha saldo;
--     sem saldo a nota sai do mesmo jeito e a pendencia fica registrada na operacao;
--     cancelamento da nota real estorna a saida.

-- ---------------------------------------------------------------------------
-- 1. A NF-e de devolucao aponta para a operacao pela origem do item.
-- ---------------------------------------------------------------------------
alter table f.solicitacao_item drop constraint if exists solicitacao_item_origem_tipo_check;
alter table f.solicitacao_item add constraint solicitacao_item_origem_tipo_check
  check (origem_tipo = any (array['OS'::text, 'OV'::text, 'AVULSO'::text, 'CONTRATO'::text, 'RETORNO_TERCEIROS'::text, 'DEVOLUCAO_COMPRA'::text]));

-- A operacao passa a guardar a finalidade 4 (devolucao); ate aqui so 1 e 3 (estorno).
alter table f.operacao_fiscal drop constraint if exists operacao_fiscal_finalidade_emissao_check;
alter table f.operacao_fiscal add constraint operacao_fiscal_finalidade_emissao_check
  check (finalidade_emissao = any (array[1, 2, 3, 4]));

-- ---------------------------------------------------------------------------
-- 2. Gerar a NF-e de devolucao (operacao DEVOLUCAO_COMPRA + solicitacao pelo pipeline)
-- ---------------------------------------------------------------------------
create or replace function f.fn_devolucao_compra_nfe_criar(
  p_nf_entrada_id bigint,
  p_itens jsonb,
  p_modalidade_frete smallint default 0,
  p_volumes jsonb default null,
  p_observacao text default null,
  p_transportador jsonb default null,
  p_cfop text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_nf public.nf_entrada%rowtype;
  v_preparo jsonb;
  v_emit record;
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
  v_op_id uuid;
  v_sol_id uuid := gen_random_uuid();
  v_volumes jsonb;
  v_transportador jsonb;
  v_itens_req jsonb;
  v_item record;
  v_cenq text;
  v_total numeric(14,2) := 0;
  v_indicador_ie text;
  v_natureza constant text := 'DEVOLUCAO_COMPRA';
  v_data_emissao text;
  v_itens_texto text;
  v_fmt text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos um item com a quantidade a devolver.';
  end if;
  if p_modalidade_frete is null or p_modalidade_frete not in (0, 1, 2, 3, 4, 9) then
    raise exception using errcode = '22023', message = 'Modalidade do frete deve ser 0, 1, 2, 3, 4 ou 9.';
  end if;

  -- Le e valida o XML (chave de 44 digitos, XML armazenado, itens legiveis).
  v_preparo := f.fn_devolucao_compra_preparar(p_nf_entrada_id);
  select * into v_nf from public.nf_entrada n
   where n.tenant_id = v_scope.tenant_id and n.empresa_id = v_scope.empresa_id and n.id = p_nf_entrada_id and n.deleted_at is null;

  -- Emitente da entrada = destinatario da devolucao, do XML.
  select x.* into v_emit
  from xmltable(
    xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '/n:nfeProc/n:NFe/n:infNFe' passing xmlparse(document v_nf.xml_raw) columns
      cnpj text path 'n:emit/n:CNPJ', cpf text path 'n:emit/n:CPF', nome text path 'n:emit/n:xNome',
      ie text path 'n:emit/n:IE', telefone text path 'n:emit/n:enderEmit/n:fone',
      logradouro text path 'n:emit/n:enderEmit/n:xLgr', numero text path 'n:emit/n:enderEmit/n:nro',
      complemento text path 'n:emit/n:enderEmit/n:xCpl', bairro text path 'n:emit/n:enderEmit/n:xBairro',
      codigo_ibge text path 'n:emit/n:enderEmit/n:cMun', cidade text path 'n:emit/n:enderEmit/n:xMun',
      uf text path 'n:emit/n:enderEmit/n:UF', cep text path 'n:emit/n:enderEmit/n:CEP',
      nnf text path 'n:ide/n:nNF', serie text path 'n:ide/n:serie', dh_emi text path 'n:ide/n:dhEmi'
  ) x;
  if v_emit.nome is null or coalesce(v_emit.cnpj, v_emit.cpf) is null then
    raise exception using errcode = '22023', message = 'O XML da entrada nao traz o emitente.';
  end if;
  v_uf_destino := upper(coalesce(v_emit.uf, ''));
  if v_uf_destino !~ '^[A-Z]{2}$' then
    raise exception using errcode = '22023', message = 'O XML da entrada nao traz a UF do emitente.';
  end if;
  v_data_emissao := to_char((v_emit.dh_emi)::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');

  select * into v_empresa from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id and e.deleted_at is null;
  select * into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  select * into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
  if v_endereco.id is null or v_fiscal.id is null then
    raise exception using errcode = '22023', message = 'Cadastro fiscal do emitente incompleto (endereco ou dados fiscais).';
  end if;
  v_uf_emitente := upper(v_endereco.uf::text);
  v_ambito := case when v_uf_destino = v_uf_emitente then 'INTERNA' else 'INTERESTADUAL' end;

  -- CFOP: 5201 (industrializacao) e o padrao da contadora; 5553 para ativo imobilizado.
  -- Fora do estado, 6201/6556. Sao os CFOPs que fn_devolucao_compra_criar aceita.
  v_permitidos := case v_ambito when 'INTERNA' then array['5201', '5553'] else array['6201', '6556'] end;
  if v_cfop = '' then v_cfop := v_permitidos[1]; end if;
  if not (v_cfop = any(v_permitidos)) then
    raise exception using errcode = '22023', message = format('CFOP %s nao vale para esta devolucao (%s). Use %s.', v_cfop, v_ambito, array_to_string(v_permitidos, ' ou '));
  end if;

  -- Volumes e transportadora vem da tela (a contadora pede quantidade e peso do que volta).
  v_volumes := case when jsonb_typeof(p_volumes) = 'array' and jsonb_array_length(p_volumes) > 0 then p_volumes else '[]'::jsonb end;
  if p_modalidade_frete = 9 then v_volumes := '[]'::jsonb; end if;
  if p_modalidade_frete <> 9 and jsonb_array_length(v_volumes) = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos um volume (quantidade e peso) quando houver transporte.';
  end if;
  v_transportador := case when jsonb_typeof(p_transportador) = 'object' and nullif(btrim(coalesce(p_transportador->>'nome', '')), '') is not null then p_transportador end;
  if v_transportador is not null and p_modalidade_frete = 9 then
    raise exception using errcode = '22023', message = 'Transportadora informada nao combina com modalidade 9 (sem frete).';
  end if;

  -- Fornecedor como cliente, se o CNPJ existir no cadastro: so para a listagem.
  select c.id into v_cliente_id
  from public.clientes c
  where c.tenant_id = v_scope.tenant_id and c.empresa_id = v_scope.empresa_id
    and regexp_replace(coalesce(c.documento, ''), '[^0-9]', '', 'g') = coalesce(v_emit.cnpj, v_emit.cpf) and c.ativo
  order by c.id limit 1;
  v_indicador_ie := case when nullif(btrim(coalesce(v_emit.ie, '')), '') is not null and upper(v_emit.ie) <> 'ISENTO' then '1' else '9' end;

  -- Perfil de operacao, se existir: so importa para a producao (portoes de perfil).
  select po.id into v_perfil_id
  from f.perfil_operacao po
  where po.tenant_id = v_scope.tenant_id and (po.empresa_id = v_scope.empresa_id or po.empresa_id is null)
    and po.modelo = 'NFE' and po.natureza_operacao = v_natureza and po.ambito_destino = v_ambito
    and coalesce(case when v_ambito = 'INTERNA' then po.cfop_interno else po.cfop_externo end, '') = v_cfop
    and po.faixa_automacao <> 'BLOQUEADO' and po.vigencia_inicio <= current_date and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
  order by po.habilitado_producao desc, po.revisao_fiscal_em desc nulls last
  limit 1;

  -- Devolucao anterior desta entrada ainda sem nota real sai do caminho (a regra de quantidade
  -- acumulada de fn_devolucao_compra_criar so conta operacoes nao canceladas).
  update f.solicitacao_faturamento sf
     set status = 'CANCELADA', updated_at = now()
   where sf.tenant_id = v_scope.tenant_id and sf.empresa_id = v_scope.empresa_id
     and sf.status not in ('EMITIDA', 'CANCELADA')
     and sf.id in (
       select o.solicitacao_id from f.operacao_fiscal o
        where o.tenant_id = v_scope.tenant_id and o.empresa_id = v_scope.empresa_id and o.deleted_at is null
          and o.tipo = 'DEVOLUCAO_COMPRA' and o.nf_entrada_origem_id = p_nf_entrada_id
          and o.status not in ('CONCLUIDA', 'CANCELADA') and o.solicitacao_id is not null
          and not exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = o.solicitacao_id and e.ambiente = 'PRODUCAO' and e.status not in ('REJEITADA', 'ERRO')));
  update f.operacao_fiscal o
     set status = 'CANCELADA', updated_at = now()
   where o.tenant_id = v_scope.tenant_id and o.empresa_id = v_scope.empresa_id and o.deleted_at is null
     and o.tipo = 'DEVOLUCAO_COMPRA' and o.nf_entrada_origem_id = p_nf_entrada_id
     and o.status not in ('CONCLUIDA', 'CANCELADA')
     and not exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = o.solicitacao_id and e.ambiente = 'PRODUCAO' and e.status not in ('REJEITADA', 'ERRO'));

  -- Operacao + itens validados contra o XML (quantidade, acumulado, CST/aliquotas proporcionais).
  select jsonb_agg(jsonb_build_object('nitem', e->>'nitem', 'quantidade', e->>'quantidade', 'cfop_confirmado', v_cfop))
    into v_itens_req
  from jsonb_array_elements(p_itens) e;
  v_op_id := f.fn_devolucao_compra_criar(p_nf_entrada_id, v_itens_req);

  -- Frases dos itens para o infCpl ("ITEM 2 (401014): 41,55 KG DE 2.742,30 KG").
  select string_agg(
           format('ITEM %s (%s): %s %s DE %s %s', i.origem_nitem, i.codigo,
                  replace(replace(replace(to_char(i.quantidade, 'FM999G999G999G990D00'), '.', '#'), ',', '.'), '#', ','), upper(i.unidade),
                  replace(replace(replace(to_char(i.quantidade_original, 'FM999G999G999G990D00'), '.', '#'), ',', '.'), '#', ','), upper(i.unidade)),
           '; ' order by i.ordem)
    into v_itens_texto
  from f.operacao_fiscal_item i where i.operacao_id = v_op_id;

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
    4, 0, 9, p_modalidade_frete,
    0, 0, 0,
    v_uf_destino, now(), v_scope.usuario_id,
    '90', 0, null, v_transportador, case when jsonb_array_length(v_volumes) > 0 then v_volumes end,
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
      'id', v_cliente_id, 'documento', coalesce(v_emit.cnpj, v_emit.cpf), 'nome', v_emit.nome,
      'inscricao_estadual', case when v_indicador_ie = '1' then v_emit.ie end, 'indicador_ie', v_indicador_ie,
      'email', null, 'telefone', v_emit.telefone,
      'logradouro', v_emit.logradouro, 'numero_endereco', coalesce(nullif(btrim(v_emit.numero), ''), 'S/N'),
      'complemento', v_emit.complemento, 'bairro', v_emit.bairro,
      'cidade', coalesce((select mi.nome from public.municipios_ibge mi where mi.codigo_ibge = v_emit.codigo_ibge), v_emit.cidade),
      'uf', v_uf_destino, 'codigo_ibge_municipio', v_emit.codigo_ibge,
      'cep', regexp_replace(coalesce(v_emit.cep, ''), '[^0-9]', '', 'g')
    ),
    jsonb_build_object(
      'natureza_operacao', v_natureza, 'finalidade_emissao', 4, 'consumidor_final', 0, 'presenca_comprador', 9,
      'modalidade_frete', p_modalidade_frete, 'valor_frete', 0, 'valor_seguro', 0, 'valor_outras_despesas', 0,
      'destinacao_mercadoria', null, 'nfe_referenciada', v_nf.chave,
      'transportador', v_transportador, 'volumes', case when jsonb_array_length(v_volumes) > 0 then v_volumes end,
      'pagamento', jsonb_build_object('forma', '90', 'indicador', 0, 'descricao', null, 'parcelas', null, 'fatura_numero', null),
      'devolucao_compra', jsonb_build_object(
        'nf_entrada_id', v_nf.id, 'operacao_id', v_op_id, 'chave', v_nf.chave,
        'numero', coalesce(v_emit.nnf, v_nf.numero), 'serie', coalesce(v_emit.serie, v_nf.serie),
        'data_emissao', v_data_emissao, 'emitente_nome', v_emit.nome, 'cfop', v_cfop, 'ambito', v_ambito,
        'itens_texto', v_itens_texto
      )
    ),
    now()
  );

  -- Itens: espelho proporcional da origem, CST e aliquotas do XML; cEnq do IPI direto do XML.
  for v_item in
    select i.* from f.operacao_fiscal_item i where i.operacao_id = v_op_id order by i.ordem
  loop
    select x.cenq into v_cenq
    from xmltable(
      xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
      '//n:det' passing xmlparse(document v_nf.xml_raw) columns
        nitem integer path '@nItem', cenq text path 'n:imposto/n:IPI/n:cEnq'
    ) x
    where x.nitem = v_item.origem_nitem;
    insert into f.solicitacao_item (
      id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, origem_item_id, item_id, descricao, ncm, cest, cfop,
      cst_icms, csosn, cbenef, reducao_base_icms_percentual, aliquota_icms, icms_modalidade_base_calculo,
      cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins, aliquota_pis, aliquota_cofins,
      cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json,
      quantidade, unidade, unidade_tributavel, valor_unitario, valor_desconto, ordem, codigo_produto, origem_mercadoria,
      perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por, tributacao_fonte, modelo
    ) values (
      gen_random_uuid(), v_sol_id, v_scope.tenant_id, v_scope.empresa_id, 'DEVOLUCAO_COMPRA', v_op_id::text, v_item.id::text, v_item.item_id,
      v_item.descricao, v_item.ncm, null, v_cfop,
      v_item.cst_icms, v_item.csosn, v_item.cbenef, coalesce(v_item.reducao_base_icms_percentual, 0), v_item.aliquota_icms,
      case when v_item.aliquota_icms is not null then '3' end,
      coalesce(v_item.cst_ipi, '53'), coalesce(nullif(regexp_replace(coalesce(v_cenq, ''), '[^0-9]', '', 'g'), ''), '999'),
      case when v_item.cst_ipi in ('50', '99') then v_item.aliquota_ipi end,
      coalesce(v_item.cst_pis, '08'), coalesce(v_item.cst_cofins, '08'),
      case when v_item.cst_pis in ('01', '02') then v_item.aliquota_pis end,
      case when v_item.cst_cofins in ('01', '02') then v_item.aliquota_cofins end,
      '000', '000001', null,
      jsonb_build_object('ibs_uf_aliquota', 0.1, 'ibs_mun_aliquota', 0, 'cbs_aliquota', 0.9),
      v_item.quantidade, v_item.unidade, coalesce(v_item.unidade_tributavel, v_item.unidade), v_item.valor_unitario, 0,
      v_item.ordem, v_item.codigo, coalesce(v_item.origem_mercadoria, 0),
      v_perfil_id, case when v_perfil_id is null then null else now() end, case when v_perfil_id is null then null else v_scope.usuario_id end,
      case when v_perfil_id is null then null else 'PERFIL' end, 'NFE'
    );
    v_total := v_total + v_item.valor_total;
  end loop;

  update f.operacao_fiscal
     set solicitacao_id = v_sol_id, perfil_operacao_id = v_perfil_id, ambiente = 'HOMOLOGACAO',
         finalidade = 'DEVOLUCAO_COMPRA', finalidade_emissao = 4, destinatario_id = v_cliente_id,
         justificativa_fisco = nullif(btrim(coalesce(p_observacao, '')), ''),
         entrega_json = jsonb_build_object('documento', coalesce(v_emit.cnpj, v_emit.cpf), 'nome', v_emit.nome, 'uf', v_uf_destino),
         dados_json = coalesce(dados_json, '{}'::jsonb) || jsonb_build_object(
           'nf_entrada_id', v_nf.id, 'natureza_operacao', v_natureza, 'ambito', v_ambito, 'chave_origem', v_nf.chave,
           'origem_numero', coalesce(v_emit.nnf, v_nf.numero), 'origem_serie', coalesce(v_emit.serie, v_nf.serie),
           'origem_emitente', v_emit.nome, 'origem_data_emissao', v_data_emissao,
           'perfil_codigo', (select po.codigo from f.perfil_operacao po where po.id = v_perfil_id)),
         updated_at = now()
   where id = v_op_id;

  return jsonb_build_object(
    'operacao_id', v_op_id, 'solicitacao_id', v_sol_id, 'cfop', v_cfop, 'ambito', v_ambito, 'natureza_operacao', v_natureza,
    'valor_produtos', v_total, 'valor_total', (select valor_total from f.operacao_fiscal where id = v_op_id),
    'itens', (select count(*) from f.operacao_fiscal_item i where i.operacao_id = v_op_id),
    'perfil_id', v_perfil_id, 'cliente_id', v_cliente_id, 'destinatario', v_emit.nome
  );
end;
$$;
revoke all on function f.fn_devolucao_compra_nfe_criar(bigint, jsonb, smallint, jsonb, text, jsonb, text) from public, anon;
grant execute on function f.fn_devolucao_compra_nfe_criar(bigint, jsonb, smallint, jsonb, text, jsonb, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Autorizacao em producao baixa o estoque; cancelamento estorna
-- ---------------------------------------------------------------------------
-- O gatilho generico das operacoes (fn_operacao_fiscal_apos_emissao, 20260916160000) ja
-- conclui a operacao e guarda a chave. Aqui so o estoque: a mercadoria devolvida sai do
-- saldo do item ligado a linha da entrada. Sem saldo suficiente a nota nao e barrada (a
-- SEFAZ ja autorizou); fica a pendencia em dados_json para o almoxarifado acertar.
create or replace function f.fn_devolucao_compra_apos_emissao()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_op f.operacao_fiscal%rowtype;
  v_item record;
  v_saldo numeric;
  v_mov_id bigint;
  v_movs jsonb := '[]'::jsonb;
  v_pendencias jsonb := '[]'::jsonb;
  v_email text;
  v_motivo text;
  v_estorno jsonb := '[]'::jsonb;
  v_orig jsonb;
begin
  if new.status not in ('AUTORIZADA', 'CANCELADA') or old.status = new.status
     or new.ambiente <> 'PRODUCAO' or new.solicitacao_id is null then
    return new;
  end if;
  select * into v_op from f.operacao_fiscal o
   where o.tenant_id = new.tenant_id and o.empresa_id = new.empresa_id
     and o.solicitacao_id = new.solicitacao_id and o.tipo = 'DEVOLUCAO_COMPRA' and o.deleted_at is null
   limit 1;
  if not found then return new; end if;
  select u.email into v_email from a.usuario u where u.id = v_op.criado_por;
  v_email := coalesce(v_email, 'sistema');

  if new.status = 'AUTORIZADA' then
    if coalesce(v_op.dados_json->'estoque_movimentacoes', '[]'::jsonb) <> '[]'::jsonb then return new; end if;
    for v_item in
      select i.* from f.operacao_fiscal_item i where i.operacao_id = v_op.id order by i.ordem
    loop
      if v_item.item_id is null then
        v_pendencias := v_pendencias || jsonb_build_object('ordem', v_item.ordem, 'codigo', v_item.codigo, 'motivo', 'linha da entrada sem item do catalogo');
        continue;
      end if;
      select coalesce(e.quantidade_atual, 0) into v_saldo
      from public.estoque e where e.tenant_id = v_op.tenant_id and e.empresa_id = v_op.empresa_id and e.item_id = v_item.item_id;
      v_saldo := coalesce(v_saldo, 0);
      if v_saldo < v_item.quantidade then
        v_pendencias := v_pendencias || jsonb_build_object('ordem', v_item.ordem, 'codigo', v_item.codigo, 'item_id', v_item.item_id,
          'quantidade', v_item.quantidade, 'saldo', v_saldo, 'motivo', 'saldo insuficiente para a baixa da devolucao');
        continue;
      end if;
      v_motivo := format('Devolucao de compra NF-e %s/%s ao fornecedor %s (NF entrada %s) [DEVOLUCAO %s]',
        coalesce(new.serie::text, '?'), coalesce(new.numero::text, '?'), coalesce(v_op.dados_json->>'origem_emitente', '?'),
        coalesce(v_op.dados_json->>'origem_numero', v_op.nf_entrada_origem_id::text), v_op.id);
      insert into public.movimentacoes (tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, created_at)
      values (v_op.tenant_id, v_op.empresa_id, v_item.item_id, 'saida', v_item.quantidade, v_motivo, v_email, now(), now())
      returning id into v_mov_id;
      v_movs := v_movs || jsonb_build_object('movimentacao_id', v_mov_id, 'item_id', v_item.item_id, 'quantidade', v_item.quantidade);
    end loop;
    update f.operacao_fiscal
       set dados_json = coalesce(dados_json, '{}'::jsonb) || jsonb_build_object('estoque_movimentacoes', v_movs, 'estoque_pendencias', v_pendencias, 'estoque_baixado_em', now()),
           updated_at = now()
     where id = v_op.id;
  elsif new.status = 'CANCELADA' then
    for v_orig in select value from jsonb_array_elements(coalesce(v_op.dados_json->'estoque_movimentacoes', '[]'::jsonb)) loop
      insert into public.movimentacoes (tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, created_at)
      values (v_op.tenant_id, v_op.empresa_id, (v_orig->>'item_id')::integer, 'entrada', (v_orig->>'quantidade')::numeric,
              format('Estorno da devolucao de compra: NF-e %s/%s cancelada [DEVOLUCAO %s]', coalesce(new.serie::text, '?'), coalesce(new.numero::text, '?'), v_op.id),
              v_email, now(), now())
      returning id into v_mov_id;
      v_estorno := v_estorno || jsonb_build_object('movimentacao_id', v_mov_id, 'estorna', v_orig->'movimentacao_id');
    end loop;
    update f.operacao_fiscal
       set dados_json = coalesce(dados_json, '{}'::jsonb) || jsonb_build_object('estoque_estornos', v_estorno, 'estoque_estornado_em', now()),
           updated_at = now()
     where id = v_op.id;
  end if;
  return new;
end;
$$;
revoke all on function f.fn_devolucao_compra_apos_emissao() from public, anon, authenticated;
drop trigger if exists trg_devolucao_compra_apos_emissao on f.documento_fiscal_emissao;
create trigger trg_devolucao_compra_apos_emissao
  after update of status on f.documento_fiscal_emissao
  for each row execute function f.fn_devolucao_compra_apos_emissao();

-- ---------------------------------------------------------------------------
-- 4. Perfil da devolucao em SC (5201, origem 0, CST 00) para a liberacao de producao.
--    Nasce sem revisao e desabilitado; revisao e liberacao pela tela de perfis.
-- ---------------------------------------------------------------------------
insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
  aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa, justificativa_faixa,
  divergencia_ipi, divergencia_fabricado_revenda, divergencia_cabo_beneficio,
  xml_notas, xml_itens, xml_pis_csts, xml_cofins_csts, xml_pis_aliquotas, xml_cofins_aliquotas,
  xml_ipi_csts, xml_cbenef_valores, xml_cbenef_ausente_itens, xml_fci_itens, xml_divergente
)
select
  '4c0a5e1e-9f0b-4c7a-9b2e-5201a0000001'::uuid, '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7', 'f0e74f49-a127-46b4-901b-f7b37e43c690',
  'NF-e 121481/3 Acos America (chave 42260808819200000182550030001214811001242895, CFOP 5102, 24/08/2026) + orientacao da contadora em 17/09/2026',
  5201, 'DEVOLUCAO_COMPRA', '5201', 0, '000', '00', 12, 3.25, false, 1, 1,
  array['73063090']::text[], array[121481]::integer[],
  'Devolucao de compra para industrializacao: espelho proporcional da nota de entrada, ICMS CST 00 a 12% (IPI fora da base), IPI CST 50 cEnq 999, PIS/COFINS 01, IBS/CBS 000/000001, finNFe 4 com NFref, sem cobranca.',
  'REVISAO', 'Primeira devolucao pelo ERP: homologar e revisar antes de liberar producao.',
  false, false, false, 1, 4, array['01']::text[], array['01']::text[], array[1.65]::numeric[], array[7.6]::numeric[], array['50']::text[], '{}'::text[], 0, 0, false
where exists (select 1 from c.empresa e where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7' and e.id = 'f0e74f49-a127-46b4-901b-f7b37e43c690')
on conflict (tenant_id, empresa_id, fonte, fonte_linha) do nothing;

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_interno, cfop_externo, cst_icms, aliquota_icms, cbenef, cbenef_aplicacao, beneficio_texto_legal,
  cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins, aliquota_pis, aliquota_cofins, finalidade_emissao, consumidor_final,
  ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  exige_referencia, exige_motivo, observacao, informacoes_complementares_modelo, vigencia_inicio,
  evidencia_id, faixa_automacao, justificativa_faixa, habilitado_producao
)
select
  'a6e1c3d2-5201-4c00-9a2b-000000000001'::uuid, '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7', 'f0e74f49-a127-46b4-901b-f7b37e43c690',
  'SEG-DEVOLUCAO-COMPRA-5201-O0-CST00', 'SEG - devolucao de compra para industrializacao em SC - CFOP 5201 - origem 0 - CST 00',
  'NFE', 'DEVOLUCAO_COMPRA', 'DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO', '3',
  '5201', null, '00', 12, null, 'SEM_BENEFICIO', null,
  '50', '999', 3.25, '01', '01', 1.65, 7.6, 4, 0,
  'INTERNA', array['SC']::text[], '1', 0,
  true, false,
  'Devolucao de compra: os CST e aliquotas de cada item vem do XML da NF-e de entrada (f.fn_devolucao_compra_nfe_criar); os valores do perfil sao os da NF-e 121481/3 da Acos America. Orientacao da contadora em 17/09/2026: CFOP 5201, saida tributada com o CST da origem, IPI fora da base do ICMS.',
  'DEVOLUCAO DE COMPRA REFERENTE A NF-E DE ENTRADA. IMPOSTOS DESTACADOS PROPORCIONALMENTE CONFORME A NOTA DE ORIGEM.',
  '2026-09-16', '4c0a5e1e-9f0b-4c7a-9b2e-5201a0000001'::uuid, 'REVISAO',
  'Primeira devolucao pelo ERP: homologar e revisar antes de liberar producao.', false
where exists (select 1 from f.perfil_operacao_evidencia ev where ev.id = '4c0a5e1e-9f0b-4c7a-9b2e-5201a0000001'::uuid)
on conflict (tenant_id, empresa_id, codigo, vigencia_inicio) do nothing;

update f.perfil_operacao_evidencia ev
   set perfil_operacao_id = po.id
  from f.perfil_operacao po
 where po.evidencia_id = ev.id and po.codigo = 'SEG-DEVOLUCAO-COMPRA-5201-O0-CST00' and ev.perfil_operacao_id is null;
