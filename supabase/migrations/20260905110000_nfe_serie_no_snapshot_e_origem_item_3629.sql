-- Decisoes de 05/09/2026:
--
-- 1. Serie da NF-e. A SEGAU emite pelo ERP na serie 2, tambem em producao; a
--    serie 1 fica com o emissor antigo (backup ate o fim das implantacoes). O
--    payload deixa de omitir a serie: ela entra no snapshot do emitente
--    (c.empresa_fiscal.serie_nfe), vira pendencia quando ausente e a Edge a
--    envia a Focus. O numero continua sob controle da Focus.
--
-- 2. Item 3629 (CONTROLADOR PROGRAMAVEL PLC CPU, NCM 8537.10.20): origem
--    confirmada pelo responsavel como 2 - Estrangeira, adquirida no mercado
--    interno. O cadastro estava com 0 desde a inferencia revertida em 04/09.

CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_cliente public.clientes%rowtype;
  v_item record;
  v_documento text;
  v_pendencias jsonb := '[]'::jsonb;
  v_rota_cliente text;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para validar esta solicitacao.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Somente solicitacao ainda nao emitida pode congelar cadastro.';
  end if;

  select * into v_empresa
  from c.empresa e
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null
    and e.ativo;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object(
      'entidade', 'empresa', 'id', v_sf.empresa_id, 'campo', 'empresa',
      'mensagem', 'Empresa ativa nao encontrada no cadastro corporativo.', 'rota', '/configuracoes'
    ));
  else
    select * into v_fiscal
    from c.empresa_fiscal ef
    where ef.empresa_id = v_empresa.id and ef.deleted_at is null
    order by ef.updated_at desc
    limit 1;
    select * into v_endereco
    from c.empresa_endereco ee
    where ee.empresa_id = v_empresa.id and ee.deleted_at is null
    order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc
    limit 1;

    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14
       or not public.cnpj_valido(v_empresa.cnpj) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cnpj','mensagem','CNPJ do emitente e invalido.','rota','/configuracoes'));
    end if;
    if nullif(btrim(v_empresa.razao_social), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','razao_social','mensagem','Razao social do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or nullif(btrim(v_fiscal.inscricao_estadual), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','inscricao_estadual','mensagem','IE do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.crt is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','crt','mensagem','CRT do emitente nao informado.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.serie_nfe is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','serie_nfe','mensagem','Serie da NF-e do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_endereco.id is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','endereco_fiscal','mensagem','Endereco fiscal do emitente nao informado.','rota','/configuracoes'));
    else
      if nullif(btrim(v_endereco.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','logradouro','mensagem','Logradouro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.numero), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','numero','mensagem','Numero do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','bairro','mensagem','Bairro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cidade','mensagem','Municipio do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.uf::text), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','uf','mensagem','UF do emitente nao informada.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cep','mensagem','CEP do emitente deve ter 8 digitos.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','codigo_municipio_ibge','mensagem','Codigo IBGE do emitente deve ter 7 digitos.','rota','/configuracoes')); end if;
    end if;
  end if;

  v_rota_cliente := '/clientes/cadastro-fiscal?cliente_id=' || coalesce(v_sf.cliente_id::text, '');
  select * into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id
    and c.empresa_id = v_sf.empresa_id
    and c.id = v_sf.cliente_id
    and c.ativo is true;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_sf.cliente_id,'campo','cliente','mensagem','Destinatario ativo nao encontrado nesta empresa.','rota',v_rota_cliente));
  else
    v_documento := regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g');
    if not ((length(v_documento) = 14 and public.cnpj_valido(v_documento)) or (length(v_documento) = 11 and public.cpf_valido(v_documento))) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','CPF/CNPJ do destinatario e invalido.','rota',v_rota_cliente));
    end if;
    if nullif(btrim(v_cliente.razao_social), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','razao_social','mensagem','Razao social ou nome completo nao informado.','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie is null or v_cliente.indicador_ie not in ('1','2','9') then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','indicador_ie','mensagem','Confirme manualmente o indicador de IE (1, 2 ou 9).','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie = '1' and nullif(btrim(v_cliente.inscricao_estadual), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','inscricao_estadual','mensagem','Contribuinte do ICMS deve ter IE informada.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','logradouro','mensagem','Logradouro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.numero_endereco), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','numero_endereco','mensagem','Numero do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','bairro','mensagem','Bairro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cidade','mensagem','Municipio do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if coalesce(v_cliente.uf, '') !~ '^[A-Za-z]{2}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','uf','mensagem','UF do destinatario deve ter 2 letras.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cep','mensagem','CEP do destinatario deve ter 8 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','codigo_ibge_municipio','mensagem','Codigo IBGE do destinatario deve ter 7 digitos.','rota',v_rota_cliente)); end if;
  end if;

  -- Copia apenas atributos permanentes do produto. CFOP, CST/CSOSN e aliquotas
  -- continuam exclusivamente sob responsabilidade da solicitacao.
  update f.solicitacao_item si
  set codigo_produto = coalesce(si.codigo_produto, nullif(btrim(i.codigo_interno), '')),
      ncm = coalesce(si.ncm, nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '')),
      cest = coalesce(si.cest, nullif(regexp_replace(coalesce(fi.cest, ''), '[^0-9]', '', 'g'), '')),
      origem_mercadoria = coalesce(si.origem_mercadoria, fi.origem),
      unidade_tributavel = coalesce(si.unidade_tributavel, nullif(btrim(fi.unidade_tributavel), ''), nullif(btrim(si.unidade), '')),
      valor_desconto = coalesce(si.valor_desconto, 0)
  from public.itens i
  left join public.fiscal_itens fi
    on fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id and fi.item_id = i.id
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
    and i.tenant_id = si.tenant_id
    and i.empresa_id = si.empresa_id
    and i.id = si.item_id;

  if not exists (select 1 from f.solicitacao_item si where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id) then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','itens','mensagem','A solicitacao nao possui itens.','rota','/faturamento/solicitacoes/' || v_sf.id));
  end if;

  for v_item in
    select si.*
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
    order by si.ordem, si.id
  loop
    if nullif(btrim(v_item.codigo_produto), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','codigo_produto','mensagem',format('Linha %s: codigo do produto nao informado.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.descricao), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','descricao','mensagem',format('Linha %s: descricao nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.ncm, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','ncm','mensagem',format('Linha %s: NCM deve ter 8 digitos.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g') !~ '^[0-9]{4}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cfop','mensagem',format('Linha %s: CFOP nao confirmado na solicitacao.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.origem_mercadoria is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','origem_mercadoria','mensagem',format('Linha %s: origem da mercadoria nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.unidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','unidade','mensagem',format('Linha %s: unidade comercial nao informada.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.unidade_tributavel), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','unidade_tributavel','mensagem',format('Linha %s: unidade tributavel nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if v_item.quantidade <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','quantidade','mensagem',format('Linha %s: quantidade deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.valor_unitario <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_unitario','mensagem',format('Linha %s: valor unitario deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if (case when nullif(btrim(v_item.cst_icms), '') is null then 0 else 1 end + case when nullif(btrim(v_item.csosn), '') is null then 0 else 1 end) <> 1 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms_csosn','mensagem',format('Linha %s: informe CST de ICMS ou CSOSN, nunca ambos.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt = 1 and nullif(btrim(v_item.csosn), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','csosn','mensagem',format('Linha %s: emitente do Simples exige CSOSN.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt is not null and v_fiscal.crt <> 1 and nullif(btrim(v_item.cst_icms), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms','mensagem',format('Linha %s: regime normal exige CST de ICMS.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_ipi), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_ipi','mensagem',format('Linha %s: CST de IPI nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_pis), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_pis','mensagem',format('Linha %s: CST de PIS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_cofins), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_cofins','mensagem',format('Linha %s: CST de COFINS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  end loop;

  if v_sf.finalidade_emissao is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','finalidade_emissao','mensagem','Finalidade de emissao nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.consumidor_final is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','consumidor_final','mensagem','Indicador de consumidor final nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.presenca_comprador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','presenca_comprador','mensagem','Indicador de presenca do comprador nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.modalidade_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','modalidade_frete','mensagem','Modalidade do frete nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_frete','mensagem','Valor do frete nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_seguro is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_seguro','mensagem','Valor do seguro nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_outras_despesas is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_outras_despesas','mensagem','Outras despesas nao confirmadas; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if nullif(btrim(v_sf.destinacao_mercadoria), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','destinacao_mercadoria','mensagem','Destinacao da mercadoria nao confirmada; ela decide a aliquota interna de ICMS.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if nullif(btrim(v_sf.pagamento_forma), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_forma','mensagem','Forma de pagamento nao confirmada; sem ela o provedor assume dinheiro.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.pagamento_indicador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_indicador','mensagem','Indicador de pagamento (a vista ou a prazo) nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;

  if jsonb_array_length(v_pendencias) = 0 then
    update f.solicitacao_faturamento
    set emitente_snapshot = jsonb_build_object(
          'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
          'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
          'telefone', v_empresa.telefone, 'inscricao_estadual', v_fiscal.inscricao_estadual,
          'crt', v_fiscal.crt, 'serie_nfe', v_fiscal.serie_nfe,
          'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero,
          'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro,
          'cidade', v_endereco.cidade, 'uf', upper(v_endereco.uf::text),
          'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')
        ),
        destinatario_snapshot = jsonb_build_object(
          'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social,
          'inscricao_estadual', nullif(btrim(v_cliente.inscricao_estadual), ''),
          'indicador_ie', v_cliente.indicador_ie, 'email', v_cliente.email,
          'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro,
          'numero_endereco', v_cliente.numero_endereco, 'complemento', v_cliente.complemento,
          'bairro', v_cliente.bairro, 'cidade', v_cliente.cidade, 'uf', upper(v_cliente.uf),
          'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')
        ),
        operacao_snapshot = jsonb_build_object(
          'natureza_operacao', natureza_operacao, 'finalidade_emissao', finalidade_emissao,
          'consumidor_final', consumidor_final, 'presenca_comprador', presenca_comprador,
          'modalidade_frete', modalidade_frete, 'valor_frete', valor_frete,
          'valor_seguro', valor_seguro, 'valor_outras_despesas', valor_outras_despesas,
          'destinacao_mercadoria', destinacao_mercadoria,
          'pagamento', jsonb_build_object(
            'forma', pagamento_forma,
            'indicador', pagamento_indicador,
            'descricao', pagamento_descricao
          )
        ),
        snapshot_cadastro_em = now(), updated_at = now()
    where id = v_sf.id;
  else
    update f.solicitacao_faturamento
    set emitente_snapshot = null, destinatario_snapshot = null,
        operacao_snapshot = null, snapshot_cadastro_em = null, updated_at = now()
    where id = v_sf.id;
  end if;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_pendencias) = 0,
    'solicitacao_id', v_sf.id,
    'cliente_id', v_sf.cliente_id,
    'rota_cliente', v_rota_cliente,
    'pendencias', v_pendencias
  );
end;
$function$;

-- Item 3629: origem 2 (estrangeira, adquirida no mercado interno), decisao
-- do responsavel em 05/09/2026. Escopo: tenant e empresa SEG.
update public.fiscal_itens
set origem = 2, atualizado_em = now()
where item_id = 3629
  and tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
  and coalesce(origem, 0) <> 2;

