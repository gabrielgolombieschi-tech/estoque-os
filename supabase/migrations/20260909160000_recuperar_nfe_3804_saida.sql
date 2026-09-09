-- Correcao de dado: promove a NF-e 55/1/3804 para saida emitida.
--
-- Gabriel, 09/09/2026. A nota (ARCELORMITTAL, R$ 433.434,55, autorizada em 03/09 sob o
-- protocolo 242260415804053) foi importada as 14:50 e ficou parada na primeira fase do
-- importador: ENTRADA, sem cliente e sem nfe_status, porque a segunda fase esbarrou na
-- trava corrigida em 20260909150000. Aqui roda a segunda fase no documento que ja
-- existe, em vez de estornar e reimportar — o registro esta limpo (sem titulo, sem
-- imposto e sem movimentacao de estoque), entao nao ha o que desfazer.
--
-- Faz o mesmo que app/api/faturamento/nfe/importar-xml na segunda fase: promove para
-- SAIDA/PRODUTO/EMITIDA, resolve o cliente pelo CNPJ do destinatario do XML e grava os
-- impostos. O titulo a receber nasce do trigger trg_documento_fiscal__ar_nfe.
--
-- os_id_import fica nulo de proposito: nao ha OS definida para esta nota. O vinculo e
-- feito na tela de detalhe da NF-e, que voltou a funcionar em 20260909140000.
--
-- Condicional e idempotente: nao faz nada se o documento nao existir (banco novo) ou se
-- ja estiver como saida emitida.

do $recuperar$
declare
  v_doc_id uuid := '53c631c6-72ab-4e18-b395-6c8fe89bec9a';
  v_doc f.documento_fiscal%rowtype;
  v_cliente_id integer;
  v_cnpj_destinatario text := '17469701010644';
begin
  select * into v_doc from f.documento_fiscal where id = v_doc_id;
  if not found then
    raise notice 'NF-e 3804: documento % nao existe neste banco; nada a fazer.', v_doc_id;
    return;
  end if;

  if upper(coalesce(v_doc.operacao, '')) = 'SAIDA' and upper(coalesce(v_doc.nfe_status, '')) = 'EMITIDA' then
    raise notice 'NF-e 3804: ja esta como saida emitida; nada a fazer.';
    return;
  end if;

  select c.id into v_cliente_id
  from public.clientes c
  where c.tenant_id = v_doc.tenant_id
    and c.empresa_id = v_doc.empresa_id
    and regexp_replace(coalesce(c.documento, ''), '[^0-9]', '', 'g') = v_cnpj_destinatario
  order by c.id
  limit 1;

  if v_cliente_id is null then
    raise exception 'NF-e 3804: cliente com CNPJ % nao encontrado nesta empresa.', v_cnpj_destinatario;
  end if;

  update f.documento_fiscal
     set operacao = 'SAIDA',
         natureza = 'PRODUTO',
         nfe_status = 'EMITIDA',
         cliente_id = v_cliente_id,
         competencia_date = date_trunc('month', coalesce(emissao_date, current_date))::date,
         updated_at = now()
   where id = v_doc_id;

  -- A versao com escopo (f.nfe_gravar_impostos_do_documento) exige contexto de empresa
  -- e acesso financeiro do usuario da sessao; numa migration nao ha sessao, e ela para
  -- em 'not_allowed'. A checagem e de autorizacao de tela, entao aqui vai a mesma
  -- implementacao que ela chama por dentro.
  perform f.nfe_gravar_impostos_do_documento_unscoped_20260810(v_doc_id);

  raise notice 'NF-e 3804: promovida para saida emitida, cliente %.', v_cliente_id;
end
$recuperar$;
