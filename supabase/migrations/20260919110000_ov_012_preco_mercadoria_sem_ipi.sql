-- OV-SEG-00012-026 (ordens_servico 365, PBG S/A "Portobello", CHAVE PIZZATO NG2D1D411AF30,
-- item 1828): a OC 1312773 e valor fechado, R$ 3.777,40 JA COM O IPI. A Segau e a adquirente na
-- DI da importacao por conta e ordem (nota 8509/1 da PRANA, DI 2422904512), logo e equiparada a
-- industrial e a venda destaca o IPI de 9,75% da TIPI (NCM 8536.50.90):
--
--   mercadoria 3.441,82 + IPI 335,58 = 3.777,40
--
-- A linha da OV passa a ser o valor da mercadoria (vProd); o `orcado` da OV continua 3.777,40 (o
-- total fechado com o cliente). A diferenca entre as linhas e o orcado e esperada e o rascunho da
-- NF-e so nasce com o motivo (migration 20260918240000).
--
-- Mesmo caminho da OV-SEG-00004-026 (NF-e 2/33). Pedido do Gabriel em 18/09/2026. Nenhuma nota
-- fiscal muda. O bloco pula quando a linha nao existe (banco local recriado do zero).

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
  where oi.id = 6894 and oi.os_id = 365;
  if v_antes is null then
    raise notice 'os_itens 6894 (OV 365) nao existe neste banco: nada a corrigir.';
    return;
  end if;
  if (v_antes->>'valor_unitario')::numeric = 3441.82 then
    raise notice 'os_itens 6894 ja esta com 3.441,82.';
    return;
  end if;

  select o.orcado into v_orcado from public.ordens_servico o where o.id = 365 and o.tipo_documento = 'OV';
  if v_orcado is distinct from 3777.40 then
    raise exception 'OV 365: orcado esperado 3777.40 (valor fechado da OC 1312773), encontrado %', v_orcado;
  end if;
  -- A conta so fecha com a aliquota da TIPI vigente do NCM: 3.441,82 x 9,75% = 335,58.
  if round(3441.82 * (select t.aliquota from f.tipi_ncm t where t.ncm = '85365090'
                       and t.vigencia_inicio <= current_date and (t.vigencia_fim is null or t.vigencia_fim >= current_date)
                       order by t.vigencia_inicio desc limit 1) / 100, 2) is distinct from 335.58 then
    raise exception 'a aliquota da TIPI do NCM 85365090 mudou: a conta 3.441,82 + IPI nao fecha mais em 3.777,40';
  end if;

  update public.os_itens oi
     set valor_unitario = 3441.82,
         valor_total = round(oi.quantidade * 3441.82, 2),
         observacoes = concat_ws(' | ', nullif(btrim(coalesce(oi.observacoes, '')), ''),
           'Preco ajustado em 18/09/2026: de 3.777,40 para 3.441,82. Motivo: OC 1312773 total 3.777,40 ja com IPI; '
           || 'mercadoria 3.441,82 + IPI 9,75% (335,58). O orcado da OV segue 3.777,40 (total da nota). '
           || 'Pedido do Gabriel; migration 20260919110000.')
   where oi.id = 6894
  returning to_jsonb(oi) into v_depois;

  -- os_itens nao tem gatilho de auditoria: o registro vai a mao, no mesmo formato das anteriores.
  insert into public.audit_log (tenant_id, table_name, action, row_pk, old_data, new_data, actor_email)
  values ((v_antes->>'tenant_id')::uuid, 'os_itens', 'UPDATE', '6894', v_antes, v_depois,
          'migration 20260919110000 (pedido do Gabriel, 18/09/2026: OC 1312773 valor fechado com IPI)');

  update public.ordens_servico o
     set valor_total = (select coalesce(sum(x.valor_total), 0) from public.os_itens x where x.os_id = o.id),
         atualizado_em = now()
   where o.id = 365 and o.tipo_documento = 'OV';
end;
$preco$;

do $assertions$
declare
  v_linha public.os_itens%rowtype;
begin
  select * into v_linha from public.os_itens where id = 6894 and os_id = 365;
  if v_linha.id is null then return; end if;
  if v_linha.valor_unitario <> 3441.82 or v_linha.valor_total <> round(v_linha.quantidade * 3441.82, 2) then
    raise exception 'os_itens 6894 nao ficou com 3.441,82: % / %', v_linha.valor_unitario, v_linha.valor_total;
  end if;
  if (select orcado from public.ordens_servico where id = 365) <> 3777.40 then
    raise exception 'orcado da OV 365 nao devia mudar';
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'os_itens' and row_pk = '6894' and actor_email like 'migration 20260919110000%') then
    raise exception 'audit_log do ajuste da linha 6894 nao gravado';
  end if;
end;
$assertions$;

commit;
