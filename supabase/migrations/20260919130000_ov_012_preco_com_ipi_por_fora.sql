-- OV-SEG-00012-026 (ordens_servico 365, PBG S/A "Portobello", CHAVE PIZZATO NG2D1D411AF30,
-- item 1828, os_itens 6894): o IPI da OC 1312773 e POR FORA.
--
-- A migration 20260919110000 tinha lido a OC como valor fechado COM IPI e baixado a linha para
-- 3.441,82 (mercadoria) + 335,58 (IPI) = 3.777,40. O Gabriel confirmou em 18/09/2026 que a leitura
-- correta e a inversa: os 3.777,40 da OC sao o valor da MERCADORIA e o IPI e destacado por fora.
--
--   mercadoria 3.777,40 + IPI 9,75% (368,30) = 4.145,70
--
-- A linha volta a 3.777,40, igual ao `orcado` da OV, e o alerta de "linhas x orcado" fica limpo.
-- Nenhuma nota fiscal muda aqui: a NF-e 2/34 (producao, autorizada em 18/09/2026 14:48:34) foi
-- emitida com o valor antigo e so o Gabriel pode cancela-la, pela tela.
--
-- O bloco pula quando a linha nao existe (banco local recriado do zero).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

do $preco$
declare
  v_antes jsonb;
  v_depois jsonb;
  v_orcado numeric;
  v_aliquota numeric;
begin
  select to_jsonb(oi) into v_antes
  from public.os_itens oi
  where oi.id = 6894 and oi.os_id = 365;
  if v_antes is null then
    raise notice 'os_itens 6894 (OV 365) nao existe neste banco: nada a corrigir.';
    return;
  end if;
  if (v_antes->>'valor_unitario')::numeric = 3777.40 then
    raise notice 'os_itens 6894 ja esta com 3.777,40.';
    return;
  end if;

  select o.orcado into v_orcado from public.ordens_servico o where o.id = 365 and o.tipo_documento = 'OV';
  if v_orcado is distinct from 3777.40 then
    raise exception 'OV 365: orcado esperado 3777.40 (mercadoria da OC 1312773), encontrado %', v_orcado;
  end if;

  -- Com o IPI por fora a conta da nota so fecha em 4.145,70 se a TIPI do NCM seguir em 9,75%.
  select t.aliquota into v_aliquota
  from f.tipi_ncm t
  where t.ncm = '85365090'
    and t.vigencia_inicio <= current_date
    and (t.vigencia_fim is null or t.vigencia_fim >= current_date)
  order by t.vigencia_inicio desc
  limit 1;
  if round(3777.40 * v_aliquota / 100, 2) is distinct from 368.30 then
    raise exception 'aliquota da TIPI do NCM 85365090 = %: 3.777,40 + IPI nao fecha em 4.145,70', v_aliquota;
  end if;

  update public.os_itens oi
     set valor_unitario = 3777.40,
         valor_total = round(oi.quantidade * 3777.40, 2),
         observacoes = concat_ws(' | ', nullif(btrim(coalesce(oi.observacoes, '')), ''),
           'Preco revisto em 18/09/2026: volta de 3.441,82 para 3.777,40. Motivo: OC 1312773: 3.777,40 e o '
           || 'valor da mercadoria; IPI destacado por fora (9,75% = 368,30), total da nota 4.145,70. '
           || 'Pedido do Gabriel; migration 20260919130000.')
   where oi.id = 6894
  returning to_jsonb(oi) into v_depois;

  -- os_itens nao tem gatilho de auditoria: o registro vai a mao, como nas anteriores.
  insert into public.audit_log (tenant_id, table_name, action, row_pk, old_data, new_data, actor_email)
  values ((v_antes->>'tenant_id')::uuid, 'os_itens', 'UPDATE', '6894', v_antes, v_depois,
          'migration 20260919130000 (pedido do Gabriel, 18/09/2026: OC 1312773 com IPI por fora)');

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
  if v_linha.valor_unitario <> 3777.40 or v_linha.valor_total <> round(v_linha.quantidade * 3777.40, 2) then
    raise exception 'os_itens 6894 nao ficou com 3.777,40: % / %', v_linha.valor_unitario, v_linha.valor_total;
  end if;
  if (select orcado from public.ordens_servico where id = 365) <> 3777.40 then
    raise exception 'orcado da OV 365 nao devia mudar';
  end if;
  -- O alerta de divergencia da tela compara a soma das linhas com o orcado: tem de fechar.
  if (select coalesce(sum(x.valor_total), 0) from public.os_itens x where x.os_id = 365)
     <> (select orcado from public.ordens_servico where id = 365) then
    raise exception 'soma das linhas da OV 365 nao ficou igual ao orcado';
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'os_itens' and row_pk = '6894' and actor_email like 'migration 20260919130000%') then
    raise exception 'audit_log do ajuste da linha 6894 nao gravado';
  end if;
end;
$assertions$;

commit;
