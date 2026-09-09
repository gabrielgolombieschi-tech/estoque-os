-- Correcao de dado: vencimento do contas a receber da NF-e 55/1/3804.
--
-- Gabriel, 09/09/2026. Ao promover a nota (20260909160000) o titulo AR nasceu pelo
-- trigger trg_documento_fiscal__ar_nfe, que usa o prazo padrao e marcou 18/09/2026.
-- A propria nota traz a duplicata: <dup><nDup>001</nDup><dVenc>2026-10-02</dVenc>
-- <vDup>433434.55</vDup></dup>. Manter 18/09 cobraria a ARCELORMITTAL duas semanas
-- antes do combinado no documento, entao o vencimento passa a ser o da duplicata.
--
-- Pela tela isso viria de faturamento_sync_titulo_ar_parcelas, que o importador so
-- chama quando recebe pagamentos_json. Aqui o ajuste e direto porque a parcela nao
-- tem nenhum recebimento aplicado (conferido antes).
--
-- Condicional e idempotente: so age na parcela unica desse titulo, se ela existir e
-- ainda estiver com a data padrao.

do $vencimento$
declare
  v_doc_id uuid := '53c631c6-72ab-4e18-b395-6c8fe89bec9a';
  v_venc_duplicata date := date '2026-10-02';
  v_parcelas integer;
  v_recebimentos integer;
begin
  select count(*) into v_parcelas
  from f.titulo_parcela p
  join f.titulo t on t.id = p.titulo_id
  where t.documento_fiscal_id = v_doc_id and t.tipo = 'AR' and t.deleted_at is null and p.deleted_at is null;

  if v_parcelas = 0 then
    raise notice 'NF-e 3804: sem parcela de AR neste banco; nada a fazer.';
    return;
  end if;
  if v_parcelas <> 1 then
    raise exception 'NF-e 3804: esperada 1 parcela e encontradas %; ajuste manual.', v_parcelas;
  end if;

  select count(*) into v_recebimentos
  from f.pagamento_item pi
  where pi.titulo_parcela_id in (
    select p.id from f.titulo_parcela p
    join f.titulo t on t.id = p.titulo_id
    where t.documento_fiscal_id = v_doc_id and t.tipo = 'AR' and t.deleted_at is null
  );
  if v_recebimentos > 0 then
    raise exception 'NF-e 3804: parcela ja tem recebimento aplicado; nao alterar o vencimento.';
  end if;

  update f.titulo_parcela p
     set vencimento_date = v_venc_duplicata,
         updated_at = now()
    from f.titulo t
   where t.id = p.titulo_id
     and t.documento_fiscal_id = v_doc_id
     and t.tipo = 'AR'
     and t.deleted_at is null
     and p.deleted_at is null
     and p.vencimento_date is distinct from v_venc_duplicata;

  raise notice 'NF-e 3804: vencimento do AR ajustado para % (duplicata da nota).', v_venc_duplicata;
end
$vencimento$;
