-- Importacao por remessa expressa (RTS), so para as proximas notas (a NF-e 2/24 nao muda). Pedido do
-- Gabriel em 18/09/2026:
--   1. IPI de entrada: CST 02 (entrada isenta) com cEnq 319 (remessas sujeitas ao regime de tributacao
--      simplificada: RIPI, Decreto 7.212/2010, art. 54, XIX) no lugar de 03/999. Base: DL 1.804/80,
--      Portaria MF 156/99, RA art. 99. O leiaute exige cEnq 3xx para CST 02 (NT 2015.002).
--   2. PIS/COFINS de entrada: CST 71 (aquisicao com isencao) no lugar de 98. Base: Lei 10.865/2004,
--      art. 9, II, c (RTS isenta PIS/Pasep-Importacao e Cofins-Importacao).
--   3. tpViaTransp padrao 11 (courier), trocavel na tela.
--   4. Importacao de TESTE: homologacao com a mesma DIR da importacao real, sem tocar nela (coluna
--      teste; fora do indice unico da DIR e do "em uso"; sem producao, sem estoque, sem contas a pagar).
--   5. Os quatro perfis SEG-IMPORTACAO-* recebem os CSTs novos e voltam para revisao (habilitado_producao
--      false, revisao e liberacao zeradas): homologar de novo e liberar antes da proxima nota real.
-- Os CSTs dos itens da solicitacao passam a vir do perfil do CFOP (fn_importacao_remessa_criar), nao de
-- literais. Reversao: cst_ipi 03/999, cst_pis/cofins 98 nos perfis; drop column teste (recriar o indice
-- sem "and not teste"); as tres funcoes voltam as definicoes de 000000/060000/020000.

-- 1. Coluna teste e indice unico da DIR que ignora testes.
alter table f.importacao_remessa add column if not exists teste boolean not null default false;
comment on column f.importacao_remessa.teste is 'Importacao de teste: so homologacao, convive com a DIR ja usada, nunca vira estoque ou contas a pagar.';
drop index if exists f.importacao_remessa_dir_ativa_uq;
create unique index importacao_remessa_dir_ativa_uq on f.importacao_remessa (tenant_id, empresa_id, dir_numero)
  where deleted_at is null and status <> 'CANCELADA' and not teste;

-- 2. Perfis: CSTs novos e volta para revisao (o gatilho de escrita direta so barra o papel authenticated;
--    a migration roda como postgres).
do $perfis$
declare
  v_n integer;
begin
  update f.perfil_operacao po
     set cst_ipi = '02',
         ipi_codigo_enquadramento_legal = '319',
         cst_pis = '71',
         cst_cofins = '71',
         habilitado_producao = false,
         revisao_fiscal_em = null,
         revisao_fiscal_por = null,
         revisao_fiscal_justificativa = null,
         producao_decidida_em = null,
         producao_decidida_por = null,
         producao_decisao_justificativa = null,
         producao_homologacao_solicitacao_id = null,
         producao_homologacao_documento_id = null,
         observacao = 'Importacao por remessa expressa (RTS): ICMS por dentro a 17% sobre (valor aduaneiro + II); IPI CST 02 cEnq 319 (RIPI art. 54, XIX; DL 1.804/80, Portaria MF 156/99, RA art. 99); PIS/COFINS CST 71 (Lei 10.865/2004 art. 9, II, c); IBS/CBS sobre valor aduaneiro + II (LC 214/2025 art. 69). Destinatario = exportador no exterior (UF EX, municipio 9999999). tpViaTransp padrao 11 (courier).',
         justificativa_faixa = 'CSTs de IPI (02/319) e PIS/COFINS (71) alterados em 18/09/2026: homologar e revisar de novo antes de liberar producao.'
   where po.modelo = 'NFE' and po.codigo like 'SEG-IMPORTACAO-%';
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise notice 'assert pulado: perfis SEG-IMPORTACAO-* ausentes neste banco';
  elsif v_n <> 4 then
    raise exception 'esperava 4 perfis SEG-IMPORTACAO-*, atualizou %', v_n;
  else
    raise notice 'perfis SEG-IMPORTACAO-* com IPI 02/319 e PIS/COFINS 71, de volta para revisao: %', v_n;
  end if;
end;
$perfis$;

-- 3. Funcoes (definicao completa, copiada da mais nova e alterada nos pontos indicados).

-- 3.1 fn_importacao_remessa_ler_dir (de 20260918000000): em_uso ignora testes.
create or replace function f.fn_importacao_remessa_ler_dir(p_xml text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_doc xml;
  v_r record;
  v_remessas integer;
  v_itens jsonb;
  v_cnpj_empresa text;
  v_cnpj_dir text;
  v_bloqueios text[] := '{}';
  v_em_uso record;
  v_ua record;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if nullif(btrim(coalesce(p_xml, '')), '') is null then
    raise exception using errcode = '22023', message = 'Envie o XML da DIR (Siscomex Remessa).';
  end if;
  begin
    v_doc := xmlparse(document p_xml);
  exception when others then
    raise exception using errcode = '22023', message = 'O arquivo nao e um XML valido: ' || sqlerrm;
  end;

  select count(*) into v_remessas
  from xmltable(
    xmlnamespaces('http://www.siscomex.gov.br/remessa/v1' as s),
    '/s:xml1702/s:manifestos/s:manifesto/s:remessas/s:remessa' passing v_doc columns numero text path 's:numero'
  );
  if v_remessas = 0 then
    raise exception using errcode = '22023',
      message = 'O XML nao e uma DIR do Siscomex Remessa (raiz xml1702, namespace http://www.siscomex.gov.br/remessa/v1) ou nao traz remessa.';
  end if;
  if v_remessas > 1 then
    raise exception using errcode = '22023', message = format('O XML traz %s remessas; envie a DIR de uma remessa so.', v_remessas);
  end if;

  select x.* into v_r
  from xmltable(
    xmlnamespaces('http://www.siscomex.gov.br/remessa/v1' as s),
    '/s:xml1702/s:manifestos/s:manifesto' passing v_doc columns
      manifesto_numero text path 's:numero',
      manifesto_data text path 's:dataHoraManifesto',
      ua_entrada text path 's:uaEntrada',
      pais_origem text path 's:paisOrigem',
      courier_nome text path 's:nomeEmpresa',
      courier_cnpj text path 's:cnpj',
      awb text path 's:remessas/s:remessa/s:numero',
      master text path 's:remessas/s:remessa/s:master',
      destinacao_comercial text path 's:remessas/s:remessa/s:destinacaoComercial',
      volumes text path 's:remessas/s:remessa/s:volumes',
      peso text path 's:remessas/s:remessa/s:peso',
      descricao text path 's:remessas/s:remessa/s:descricao',
      valor_usd text path 's:remessas/s:remessa/s:valorRemessaDolar',
      valor_brl text path 's:remessas/s:remessa/s:valorRemessaReal',
      frete_usd text path 's:remessas/s:remessa/s:freteDolar',
      frete_brl text path 's:remessas/s:remessa/s:freteReal',
      frete_modo text path 's:remessas/s:remessa/s:freteModoPagto',
      tributavel_usd text path 's:remessas/s:remessa/s:valorTributavelDolar',
      tributavel_brl text path 's:remessas/s:remessa/s:valorTributavelReal',
      ii_real text path 's:remessas/s:remessa/s:valorIIReal',
      multas text path 's:remessas/s:remessa/s:valorMultasReal',
      situacao text path 's:remessas/s:remessa/s:situacao',
      cambio text path 's:remessas/s:remessa/s:txCambioDtRegistro',
      dir_numero text path 's:remessas/s:remessa/s:dir/s:numero',
      dir_lote text path 's:remessas/s:remessa/s:dir/s:numeroLote',
      dir_data_registro text path 's:remessas/s:remessa/s:dir/s:dataRegistro',
      dir_versao text path 's:remessas/s:remessa/s:dir/s:versaoDIR',
      dest_documento text path 's:remessas/s:remessa/s:destinatario/s:documento',
      dest_tipo_documento text path 's:remessas/s:remessa/s:destinatario/s:tipoDocumento',
      dest_nome text path 's:remessas/s:remessa/s:destinatario/s:nome',
      dest_logradouro text path 's:remessas/s:remessa/s:destinatario/s:endereco/s:logradouro',
      dest_cep text path 's:remessas/s:remessa/s:destinatario/s:endereco/s:cep',
      dest_estado text path 's:remessas/s:remessa/s:destinatario/s:endereco/s:estado',
      rem_nome text path 's:remessas/s:remessa/s:remetente/s:nome',
      rem_logradouro text path 's:remessas/s:remessa/s:remetente/s:endereco/s:logradouro',
      rem_complemento text path 's:remessas/s:remessa/s:remetente/s:endereco/s:complemento',
      rem_estado text path 's:remessas/s:remessa/s:remetente/s:endereco/s:estado',
      rem_pais text path 's:remessas/s:remessa/s:remetente/s:endereco/s:pais',
      ii_devido text path 's:remessas/s:remessa/s:ii/s:valorDevido',
      ii_pendente text path 's:remessas/s:remessa/s:ii/s:valorPendente',
      ii_recolhido text path 's:remessas/s:remessa/s:ii/s:valorRecolhido'
  ) x;

  select jsonb_agg(jsonb_build_object(
           'sequencia', m.sequencia, 'regime_tributacao', m.regime, 'valor_usd', nullif(m.valor, '')::numeric,
           'moeda', m.moeda, 'unidade_siscomex', m.unidade, 'quantidade', nullif(m.quantidade, '')::numeric,
           'peso', nullif(m.peso, '')::numeric, 'descricao', btrim(regexp_replace(coalesce(m.descricao, ''), '\s+', ' ', 'g'))
         ) order by m.sequencia)
    into v_itens
  from xmltable(
    xmlnamespaces('http://www.siscomex.gov.br/remessa/v1' as s),
    '/s:xml1702/s:manifestos/s:manifesto/s:remessas/s:remessa/s:mercadorias/s:mercadoria' passing v_doc columns
      sequencia text path 's:sequencia', regime text path 's:regimeTributacao', valor text path 's:valor',
      moeda text path 's:moeda', unidade text path 's:unidade', quantidade text path 's:quantidade',
      peso text path 's:peso', descricao text path 's:descricao'
  ) m;

  select regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') into v_cnpj_empresa
  from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id and e.deleted_at is null;
  v_cnpj_dir := regexp_replace(coalesce(v_r.dest_documento, ''), '[^0-9]', '', 'g');

  -- Bloqueios: todos de uma vez, para a tela mostrar o que falta.
  if nullif(v_r.dir_numero, '') is null then
    v_bloqueios := v_bloqueios || 'A DIR nao traz o numero (dir/numero).';
  end if;
  if v_cnpj_dir <> coalesce(v_cnpj_empresa, '') then
    v_bloqueios := v_bloqueios || format('O destinatario da DIR (CNPJ %s) nao e a empresa emitente (CNPJ %s).', coalesce(nullif(v_cnpj_dir, ''), '?'), coalesce(v_cnpj_empresa, '?'));
  end if;
  if coalesce(v_r.situacao, '') <> '25' then
    v_bloqueios := v_bloqueios || format('A remessa esta na situacao %s; so a situacao 25 (desembaracada) pode gerar a nota de entrada.', coalesce(nullif(v_r.situacao, ''), '?'));
  end if;
  if coalesce(nullif(v_r.ii_pendente, '')::numeric, 0) <> 0 then
    v_bloqueios := v_bloqueios || format('Ha II pendente de R$ %s na DIR; a nota so sai com o imposto recolhido.', f.fn_importacao_brl(nullif(v_r.ii_pendente, '')::numeric));
  end if;
  if v_itens is null then
    v_bloqueios := v_bloqueios || 'A DIR nao traz mercadorias.';
  end if;
  if coalesce(nullif(v_r.tributavel_brl, '')::numeric, 0) <= 0 then
    v_bloqueios := v_bloqueios || 'A DIR nao traz o valor tributavel em reais (valor aduaneiro).';
  end if;

  select i.id, i.status, i.chave_nfe, i.nfe_numero, i.nfe_serie, i.created_at
    into v_em_uso
  from f.importacao_remessa i
  where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id
    and i.dir_numero = v_r.dir_numero and i.deleted_at is null and i.status <> 'CANCELADA' and not i.teste
  order by i.created_at desc limit 1;

  select * into v_ua from f.fn_importacao_ua_local(v_r.ua_entrada);

  return jsonb_build_object(
    'awb', v_r.awb,
    'master', v_r.master,
    'dir', jsonb_build_object(
      'numero', v_r.dir_numero, 'lote', v_r.dir_lote, 'data_registro', v_r.dir_data_registro, 'versao', v_r.dir_versao,
      'situacao', v_r.situacao, 'ua_entrada', v_ua.ua, 'local_desembaraco', v_ua.local_desembaraco, 'uf_desembaraco', v_ua.uf,
      'data_desembaraco', left(v_r.dir_data_registro, 10)
    ),
    'manifesto', jsonb_build_object('numero', v_r.manifesto_numero, 'data', v_r.manifesto_data, 'pais_origem', v_r.pais_origem),
    'courier', jsonb_build_object('nome', v_r.courier_nome, 'cnpj', v_r.courier_cnpj),
    'remessa', jsonb_build_object(
      'destinacao_comercial', v_r.destinacao_comercial, 'volumes', nullif(v_r.volumes, '')::integer, 'peso', nullif(v_r.peso, '')::numeric,
      'descricao', btrim(regexp_replace(coalesce(v_r.descricao, ''), '\s+', ' ', 'g')),
      'valor_usd', nullif(v_r.valor_usd, '')::numeric, 'valor_brl', nullif(v_r.valor_brl, '')::numeric,
      'frete_usd', nullif(v_r.frete_usd, '')::numeric, 'frete_brl', nullif(v_r.frete_brl, '')::numeric, 'frete_modo', v_r.frete_modo,
      'tributavel_usd', nullif(v_r.tributavel_usd, '')::numeric, 'tributavel_brl', nullif(v_r.tributavel_brl, '')::numeric,
      'multas_brl', nullif(v_r.multas, '')::numeric, 'cambio', nullif(v_r.cambio, '')::numeric
    ),
    'ii', jsonb_build_object('valor', nullif(v_r.ii_real, '')::numeric, 'devido', nullif(v_r.ii_devido, '')::numeric,
                             'pendente', nullif(v_r.ii_pendente, '')::numeric, 'recolhido', nullif(v_r.ii_recolhido, '')::numeric),
    'destinatario', jsonb_build_object('documento', v_cnpj_dir, 'nome', v_r.dest_nome, 'logradouro', v_r.dest_logradouro, 'cep', v_r.dest_cep, 'uf', v_r.dest_estado),
    'remetente', jsonb_build_object('nome', v_r.rem_nome, 'logradouro', v_r.rem_logradouro, 'complemento', v_r.rem_complemento, 'uf', v_r.rem_estado, 'pais_codigo', v_r.rem_pais),
    'itens', coalesce(v_itens, '[]'::jsonb),
    'bloqueios', to_jsonb(v_bloqueios),
    'em_uso', case when v_em_uso.id is not null then jsonb_build_object(
      'importacao_id', v_em_uso.id, 'status', v_em_uso.status, 'chave_nfe', v_em_uso.chave_nfe,
      'nfe_numero', v_em_uso.nfe_numero, 'nfe_serie', v_em_uso.nfe_serie, 'created_at', v_em_uso.created_at) end
  );
end;
$$;

-- 3.2 fn_importacao_remessa_criar (de 20260918060000): teste, via 11, CSTs do perfil.
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
  v_teste boolean := coalesce((p_dados->>'teste')::boolean, false);
  v_cst_ipi text;
  v_cenq_ipi text;
  v_cst_pis text;
  v_cst_cofins text;
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
  v_via smallint := coalesce(nullif(p_dados->>'via_transporte', '')::smallint, 11);
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
  --      Importacao de TESTE (so homologacao) convive com a DIR ja usada e nao substitui nada.
  if not v_teste and v_em_uso is not null and jsonb_typeof(v_em_uso) = 'object' then
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

  -- 6.9b CST de IPI e de PIS/COFINS vem do perfil do CFOP. RTS desde 18/09/2026: IPI 02 (entrada isenta,
  --      cEnq 319 = remessas sujeitas ao regime de tributacao simplificada, RIPI art. 54, XIX) e
  --      PIS/COFINS 71 (aquisicao com isencao, Lei 10.865/2004 art. 9, II, c).
  select coalesce(nullif(po.cst_ipi, ''), '02'), coalesce(nullif(po.ipi_codigo_enquadramento_legal, ''), '319'),
         coalesce(nullif(po.cst_pis, ''), '71'), coalesce(nullif(po.cst_cofins, ''), '71')
    into v_cst_ipi, v_cenq_ipi, v_cst_pis, v_cst_cofins
  from f.perfil_operacao po where po.id = v_perfil_id;
  if v_perfil_id is null or v_cst_ipi is null then
    v_cst_ipi := '02'; v_cenq_ipi := '319'; v_cst_pis := '71'; v_cst_cofins := '71';
  end if;

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
    natureza_operacao, cfop, consumidor_final, credito_icms, perfil_operacao_id, solicitacao_id, xml_dir, observacao, teste, dados_json, criado_por
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
    v_natureza, v_cfop, v_consumidor_final, v_credito_icms, v_perfil_id, v_sol_id, p_dados->>'xml', v_observacao, v_teste,
    jsonb_build_object('dir', v_dir - 'itens' - 'bloqueios' - 'em_uso', 'perfil_codigo', v_perfil_codigo, 'uso_proprio', v_uso_proprio, 'teste', v_teste,
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

  -- 6.14 Itens fiscais da solicitacao: CST 00 a 17% (modBC 3), IPI e PIS/COFINS do perfil (RTS: 02/319 e 71), IBS/CBS 000/000001,
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
      v_cst_ipi, v_cenq_ipi, null, v_cst_pis, v_cst_cofins, null, null,
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
    'teste', v_teste, 'cst_ipi', v_cst_ipi, 'cenq_ipi', v_cenq_ipi, 'cst_pis', v_cst_pis, 'cst_cofins', v_cst_cofins,
    'substituiu', case when not v_teste and v_em_uso is not null and jsonb_typeof(v_em_uso) = 'object' then v_em_uso->>'importacao_id' end
  );
end;
$$;

-- 3.3 fn_importacao_remessa_apos_emissao (de 20260918020000): teste nao gera estoque nem AP.
create or replace function f.fn_importacao_remessa_apos_emissao()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_imp f.importacao_remessa%rowtype;
  v_item f.importacao_remessa_item%rowtype;
  v_email text;
  v_mov_id bigint;
  v_movs jsonb := '[]'::jsonb;
  v_pendencias jsonb := '[]'::jsonb;
  v_estorno jsonb := '[]'::jsonb;
  v_orig jsonb;
  v_motivo text;
  v_fornecedor_id integer;
  v_titulo_id uuid;
  v_pagamento_id uuid;
  v_ap jsonb := '{}'::jsonb;
  v_plano uuid;
  v_emissao date;
  v_courier_cnpj text;
  v_icms_total numeric(15,2) := 0;
  v_icms_credito jsonb;
  v_fiscal_itens jsonb := '[]'::jsonb;
  v_fi record;
  v_existia boolean;
  v_status_antes text := case when tg_op = 'UPDATE' then old.status else null end;
begin
  if new.solicitacao_id is null or new.status is not distinct from v_status_antes then
    return new;
  end if;
  select * into v_imp from f.importacao_remessa i
   where i.tenant_id = new.tenant_id and i.empresa_id = new.empresa_id and i.solicitacao_id = new.solicitacao_id and i.deleted_at is null
   limit 1;
  if not found then return new; end if;

  -- Importacao de TESTE (homologacao com DIR ja usada): a tela nao oferece producao; se uma nota real
  -- chegasse aqui, nada entra no estoque nem no contas a pagar, e o fato fica registrado.
  if v_imp.teste and new.ambiente = 'PRODUCAO' then
    update f.importacao_remessa set dados_json = dados_json || jsonb_build_object('teste_producao_ignorada', now()), updated_at = now()
     where id = v_imp.id;
    return new;
  end if;

  if new.ambiente = 'HOMOLOGACAO' then
    if new.status = 'AUTORIZADA' then
      update f.importacao_remessa set status = 'HOMOLOGADA', updated_at = now()
       where id = v_imp.id and status in ('RASCUNHO', 'HOMOLOGACAO');
    elsif v_imp.status = 'RASCUNHO' then
      update f.importacao_remessa set status = 'HOMOLOGACAO', updated_at = now() where id = v_imp.id;
    end if;
    return new;
  end if;
  if new.ambiente <> 'PRODUCAO' then return new; end if;

  select u.email into v_email from a.usuario u where u.id = v_imp.criado_por;
  v_email := coalesce(v_email, 'sistema');

  if new.status = 'AUTORIZADA' then
    if v_imp.dados_json ? 'estoque_movimentacoes' then return new; end if;

    -- 9.1 Entrada no estoque: custo = valor aduaneiro + II + despesas do courier (+ ICMS so sem credito).
    --     O credito de ICMS NAO e apropriado aqui (credito_icms 0): a GNRE esta em nome do courier e a
    --     contadora decide (pendencia em dados_json.icms_credito).
    for v_item in select * from f.importacao_remessa_item i where i.importacao_id = v_imp.id order by i.ordem loop
      v_icms_total := v_icms_total + v_item.icms_valor;
      if v_item.item_id is null then
        v_pendencias := v_pendencias || jsonb_build_object('ordem', v_item.ordem, 'codigo', v_item.codigo, 'motivo', 'mercadoria sem item do catalogo');
        continue;
      end if;
      v_motivo := format('Entrada por importacao NF-e %s/%s (AWB %s, DIR %s) [IMPORTACAO %s]',
        coalesce(new.serie::text, '?'), coalesce(new.numero::text, '?'), v_imp.awb, v_imp.dir_numero, v_imp.id);
      insert into public.movimentacoes (
        tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, created_at,
        custo_unitario_bruto, custo_unitario_real, credito_icms, credito_pis, credito_cofins, v_ipi, v_icms, v_pis, v_cofins, v_frete_rateado
      ) values (
        v_imp.tenant_id, v_imp.empresa_id, v_item.item_id, 'entrada', v_item.quantidade, v_motivo, v_email, now(), now(),
        round(v_item.valor_aduaneiro_brl / v_item.quantidade, 6), v_item.custo_unitario,
        0, 0, 0, 0, v_item.icms_valor, 0, 0, v_item.frete_brl
      ) returning id into v_mov_id;
      v_movs := v_movs || jsonb_build_object('movimentacao_id', v_mov_id, 'item_id', v_item.item_id, 'quantidade', v_item.quantidade, 'custo_unitario', v_item.custo_unitario);

      -- 9.1b Origem 1 em 3101/3102: a Segau importou; a saida futura destaca IPI (equiparacao).
      if v_imp.credito_icms then
        begin
          select fi.origem, fi.origem_entrada, fi.equiparado_industrial into v_fi
            from public.fiscal_itens fi where fi.item_id = v_item.item_id;
          v_existia := found;
          insert into public.fiscal_itens (tenant_id, empresa_id, item_id, ncm, origem, origem_entrada, equiparado_industrial)
          values (v_imp.tenant_id, v_imp.empresa_id, v_item.item_id, v_item.ncm, 1, 1, true)
          on conflict (item_id) do update
             set origem = 1, origem_entrada = 1, equiparado_industrial = true,
                 ncm = coalesce(public.fiscal_itens.ncm, excluded.ncm), atualizado_em = now();
          v_fiscal_itens := v_fiscal_itens || jsonb_build_object('item_id', v_item.item_id, 'existia', v_existia,
            'antes', case when v_existia then jsonb_build_object('origem', v_fi.origem, 'origem_entrada', v_fi.origem_entrada, 'equiparado_industrial', v_fi.equiparado_industrial) end,
            'depois', jsonb_build_object('origem', 1, 'origem_entrada', 1, 'equiparado_industrial', true));
        exception when others then
          v_fiscal_itens := v_fiscal_itens || jsonb_build_object('item_id', v_item.item_id, 'erro', sqlerrm);
        end;
      end if;
    end loop;
    v_icms_credito := case when v_imp.credito_icms then jsonb_build_object(
        'valor', v_icms_total, 'status', 'PENDENTE_CONTADORA', 'cfop', v_imp.cfop,
        'motivo', 'GNRE recolhida em nome do courier e repassada na nota de debito; o credito so e apropriado com a aprovacao da contadora.')
      else jsonb_build_object('valor', 0, 'status', 'SEM_CREDITO', 'cfop', v_imp.cfop, 'motivo', 'Uso proprio: o ICMS entra no custo.') end;

    -- 9.2 Nota de debito do courier: titulo AP da importacao, sem duplicar.
    if v_imp.nota_debito_numero is not null and coalesce(v_imp.nota_debito_valor, 0) > 0 then
      begin
        v_courier_cnpj := regexp_replace(coalesce(v_imp.courier_cnpj, ''), '[^0-9]', '', 'g');
        select fo.id into v_fornecedor_id from public.fornecedores fo
         where fo.tenant_id = v_imp.tenant_id and v_courier_cnpj <> '' and fo.cnpj_digits = v_courier_cnpj
         order by (fo.empresa_id = v_imp.empresa_id) desc, fo.id limit 1;
        if v_fornecedor_id is null then
          insert into public.fornecedores (tenant_id, empresa_id, nome, documento, cnpj, ativo, gerar_contas_pagar_auto)
          values (v_imp.tenant_id, v_imp.empresa_id, coalesce(v_imp.courier_nome, 'COURIER'), nullif(v_courier_cnpj, ''), nullif(v_courier_cnpj, ''), true, false)
          returning id into v_fornecedor_id;
        end if;
        select t.id into v_titulo_id from f.titulo t
         where t.tenant_id = v_imp.tenant_id and t.empresa_id = v_imp.empresa_id and t.tipo = 'AP' and t.deleted_at is null and t.status <> 'CANCELADO'
           and t.fornecedor_id = v_fornecedor_id
           and (t.id = v_imp.nota_debito_titulo_id or t.descricao ilike '%' || v_imp.nota_debito_numero || '%')
         order by t.created_at limit 1;
        if v_titulo_id is null then
          v_emissao := coalesce(v_imp.nota_debito_emissao, v_imp.nota_debito_pago_em, (v_imp.dir_data_registro at time zone 'America/Sao_Paulo')::date);
          insert into f.titulo (tenant_id, empresa_id, tipo, status, origem, fornecedor_id, descricao, emissao_date, competencia_date, valor_total, valor_aberto, motivo_compra_id, created_by)
          values (v_imp.tenant_id, v_imp.empresa_id, 'AP', 'APROVADO', 'IMPORTACAO', v_fornecedor_id,
                  upper(format('NOTA DE DEBITO %s %s - IMPORTACAO AWB %s (DIR %s): II, ICMS/GNRE E SERVICOS', coalesce(v_imp.courier_nome, 'COURIER'), v_imp.nota_debito_numero, v_imp.awb, v_imp.dir_numero)),
                  v_emissao, date_trunc('month', v_emissao)::date, v_imp.nota_debito_valor, v_imp.nota_debito_valor, v_imp.nota_debito_motivo_compra_id, v_imp.criado_por)
          returning id into v_titulo_id;
          insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
          values (v_imp.tenant_id, v_titulo_id, '001', coalesce(v_imp.nota_debito_pago_em, v_emissao), v_imp.nota_debito_valor, v_imp.nota_debito_valor);
          -- Rateio de 100% no plano de contas do motivo; sem plano no motivo o titulo fica sem
          -- rateio (o financeiro exige plano no rateio) e a tela de contas a pagar completa.
          select mc.plano_contas_id into v_plano from f.motivo_compra mc where mc.id = v_imp.nota_debito_motivo_compra_id and mc.deleted_at is null;
          if v_plano is not null then
            insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor, origem_rateio)
            values (v_imp.tenant_id, v_titulo_id, v_plano, 100, v_imp.nota_debito_valor, 'SISTEMA_FALLBACK');
          end if;
          v_ap := v_ap || jsonb_build_object('titulo_id', v_titulo_id, 'criado', true);
          -- Ja paga: registra o pagamento pelo fluxo do financeiro quando a tela informou conta e forma.
          if v_imp.nota_debito_pago_em is not null and v_imp.nota_debito_conta_bancaria_id is not null and v_imp.nota_debito_forma_pagamento is not null then
            v_pagamento_id := f.registrar_pagamento_ap_v2(
              v_titulo_id, v_imp.nota_debito_conta_bancaria_id, v_imp.nota_debito_pago_em, v_imp.nota_debito_forma_pagamento,
              v_imp.nota_debito_valor, 0, 0, 0,
              format('Nota de debito %s paga em %s (importacao AWB %s)', v_imp.nota_debito_numero, to_char(v_imp.nota_debito_pago_em, 'DD/MM/YYYY'), v_imp.awb),
              'Baixa automatica da nota de debito da importacao'
            );
            v_ap := v_ap || jsonb_build_object('pagamento_id', v_pagamento_id);
          end if;
        else
          v_ap := v_ap || jsonb_build_object('titulo_id', v_titulo_id, 'criado', false, 'motivo', 'titulo ja existia para esta nota de debito');
        end if;
        v_ap := v_ap || jsonb_build_object('fornecedor_id', v_fornecedor_id);
      exception when others then
        -- A SEFAZ ja autorizou: o financeiro nao pode derrubar a nota. O bloco inteiro volta
        -- atras (subtransacao) e a pendencia fica registrada para lancar a mao.
        v_titulo_id := null;
        v_ap := jsonb_build_object('erro', sqlerrm, 'criado', false);
      end;
    end if;

    update f.importacao_remessa
       set status = 'CONCLUIDA', chave_nfe = new.chave_acesso, nfe_numero = new.numero, nfe_serie = new.serie,
           nfe_autorizada_em = coalesce(new.autorizado_em, now()), documento_fiscal_id = new.documento_fiscal_id,
           nota_debito_titulo_id = coalesce(nullif(v_ap->>'titulo_id', '')::uuid, nota_debito_titulo_id),
           dados_json = dados_json || jsonb_build_object('estoque_movimentacoes', v_movs, 'estoque_pendencias', v_pendencias, 'ap', v_ap,
                                                         'icms_credito', v_icms_credito, 'fiscal_itens', v_fiscal_itens, 'concluida_em', now()),
           updated_at = now()
     where id = v_imp.id;
  elsif new.status = 'CANCELADA' then
    for v_orig in select value from jsonb_array_elements(coalesce(v_imp.dados_json->'estoque_movimentacoes', '[]'::jsonb)) loop
      insert into public.movimentacoes (tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, created_at)
      values (v_imp.tenant_id, v_imp.empresa_id, (v_orig->>'item_id')::integer, 'saida', (v_orig->>'quantidade')::numeric,
              format('Estorno da importacao: NF-e %s/%s cancelada [IMPORTACAO %s]', coalesce(new.serie::text, '?'), coalesce(new.numero::text, '?'), v_imp.id),
              v_email, now(), now())
      returning id into v_mov_id;
      v_estorno := v_estorno || jsonb_build_object('movimentacao_id', v_mov_id, 'estorna', v_orig->'movimentacao_id');
    end loop;
    -- A marca de importacao no cadastro fiscal volta ao que era (a nota que a justificava caiu).
    for v_orig in select value from jsonb_array_elements(coalesce(v_imp.dados_json->'fiscal_itens', '[]'::jsonb)) where value ? 'depois' loop
      begin
        if (v_orig->>'existia')::boolean then
          update public.fiscal_itens
             set origem = nullif(v_orig->'antes'->>'origem', '')::smallint,
                 origem_entrada = nullif(v_orig->'antes'->>'origem_entrada', '')::smallint,
                 equiparado_industrial = coalesce((v_orig->'antes'->>'equiparado_industrial')::boolean, false),
                 atualizado_em = now()
           where item_id = (v_orig->>'item_id')::integer;
        else
          delete from public.fiscal_itens where item_id = (v_orig->>'item_id')::integer;
        end if;
      exception when others then
        v_estorno := v_estorno || jsonb_build_object('fiscal_item_id', v_orig->>'item_id', 'erro', sqlerrm);
      end;
    end loop;
    update f.importacao_remessa
       set status = 'CANCELADA',
           dados_json = dados_json || jsonb_build_object('estoque_estornos', v_estorno, 'estoque_estornado_em', now(),
             'fiscal_itens_desfeitos_em', now(),
             'cancelamento', jsonb_build_object('motivo', 'NF-e real cancelada pelo ciclo de vida', 'em', now())),
           updated_at = now()
     where id = v_imp.id;
  end if;
  return new;
end;
$$;

revoke all on function f.fn_importacao_remessa_ler_dir(text) from public, anon;
grant execute on function f.fn_importacao_remessa_ler_dir(text) to authenticated, service_role;
revoke all on function f.fn_importacao_remessa_criar(jsonb) from public, anon;
grant execute on function f.fn_importacao_remessa_criar(jsonb) to authenticated, service_role;
revoke all on function f.fn_importacao_remessa_apos_emissao() from public, anon, authenticated, service_role;

-- 4. Conferencia estrutural.
do $assert$
begin
  if not exists (select 1 from pg_attribute where attrelid = 'f.importacao_remessa'::regclass and attname = 'teste' and not attisdropped) then
    raise exception 'coluna f.importacao_remessa.teste ausente';
  end if;
  if (select pg_get_indexdef(oid) from pg_class where relname = 'importacao_remessa_dir_ativa_uq') not like '%NOT teste%' then
    raise exception 'indice importacao_remessa_dir_ativa_uq nao ignora testes';
  end if;
  if pg_get_functiondef('f.fn_importacao_remessa_criar(jsonb)'::regprocedure) not like '%v_cst_ipi, v_cenq_ipi, null, v_cst_pis, v_cst_cofins%' then
    raise exception 'fn_importacao_remessa_criar nao usa os CSTs do perfil';
  end if;
  if pg_get_functiondef('f.fn_importacao_remessa_apos_emissao()'::regprocedure) not like '%v_imp.teste and new.ambiente = ''PRODUCAO''%' then
    raise exception 'fn_importacao_remessa_apos_emissao sem a guarda de teste';
  end if;
end;
$assert$;

notify pgrst, 'reload schema';
