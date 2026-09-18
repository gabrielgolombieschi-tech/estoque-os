-- OV-SEG-00004-026 (ordens_servico 344, PBG S/A "Portobello", CLP OMRON CQM1H-CPU61, item 3629):
-- a OC 1309011 do cliente e valor fechado, R$ 4.563,40 JA COM O IPI. Como a Segau importou a
-- peca (equiparada a industrial), a nota destaca IPI de 9,75%: mercadoria 4.158,00 + IPI 405,40
-- = 4.563,40. A linha da OV passa a ser o valor da mercadoria (vProd), 4.158,00; o `orcado` da
-- OV continua 4.563,40 (o valor fechado com o cliente, total da nota). A diferenca entre as
-- linhas e o orcado e esperada e fica registrada aqui, no audit_log e, na hora do rascunho da
-- NF-e, no motivo exigido pela migration 20260918240000.
--
-- Pedido do Gabriel em 18/09/2026 ("Fechar a OV-SEG-00004-026"), substituindo o preco de
-- 4.563,40 gravado pela migration 20260918200000. Nenhuma nota fiscal muda. O bloco pula quando
-- a linha nao existe (banco local recriado do zero).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

do $preco$
declare
  v_antes jsonb;
  v_depois jsonb;
  v_orcado numeric;
begin
  select to_jsonb(oi) into v_antes
  from public.os_itens oi
  where oi.id = 6394 and oi.os_id = 344;
  if v_antes is null then
    raise notice 'os_itens 6394 (OV 344) nao existe neste banco: nada a corrigir.';
    return;
  end if;
  if (v_antes->>'valor_unitario')::numeric = 4158.00 then
    raise notice 'os_itens 6394 ja esta com 4.158,00.';
    return;
  end if;

  select o.orcado into v_orcado from public.ordens_servico o where o.id = 344 and o.tipo_documento = 'OV';
  if v_orcado is distinct from 4563.40 then
    raise exception 'OV 344: orcado esperado 4563.40 (valor fechado com o cliente), encontrado %', v_orcado;
  end if;

  update public.os_itens oi
     set valor_unitario = 4158.00,
         valor_total = round(oi.quantidade * 4158.00, 2),
         observacoes = concat_ws(' | ', nullif(btrim(coalesce(oi.observacoes, '')), ''),
           'Preco ajustado em 18/09/2026: de 4.563,40 para 4.158,00. Motivo: OC 1309011 total 4.563,40 '
           || 'ja com IPI; mercadoria 4.158,00 + IPI 9,75%. O orcado da OV segue 4.563,40 (total da nota). '
           || 'Pedido do Gabriel; migration 20260918250000.')
   where oi.id = 6394
  returning to_jsonb(oi) into v_depois;

  -- os_itens nao tem gatilho de auditoria: o registro vai a mao, no mesmo formato da 200000.
  insert into public.audit_log (tenant_id, table_name, action, row_pk, old_data, new_data, actor_email)
  values ((v_antes->>'tenant_id')::uuid, 'os_itens', 'UPDATE', '6394', v_antes, v_depois,
          'migration 20260918250000 (pedido do Gabriel, 18/09/2026: OC 1309011 valor fechado com IPI)');

  update public.ordens_servico o
     set valor_total = (select coalesce(sum(x.valor_total), 0) from public.os_itens x where x.os_id = o.id),
         atualizado_em = now()
   where o.id = 344 and o.tipo_documento = 'OV';
end;
$preco$;

-- Conferencias: so checam.
do $assertions$
declare
  v_linha public.os_itens%rowtype;
begin
  select * into v_linha from public.os_itens where id = 6394 and os_id = 344;
  if v_linha.id is null then
    return;
  end if;
  if v_linha.valor_unitario <> 4158.00 or v_linha.valor_total <> round(v_linha.quantidade * 4158.00, 2) then
    raise exception 'os_itens 6394 nao ficou com 4.158,00: % / %', v_linha.valor_unitario, v_linha.valor_total;
  end if;
  if (select orcado from public.ordens_servico where id = 344) <> 4563.40 then
    raise exception 'orcado da OV 344 nao devia mudar';
  end if;
  if (select valor_total from public.ordens_servico where id = 344)
     <> (select sum(valor_total) from public.os_itens where os_id = 344) then
    raise exception 'valor_total da OV 344 nao fecha com as linhas';
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'os_itens' and row_pk = '6394' and actor_email like 'migration 20260918250000%') then
    raise exception 'audit_log do ajuste da linha 6394 nao gravado';
  end if;
end;
$assertions$;

commit;
