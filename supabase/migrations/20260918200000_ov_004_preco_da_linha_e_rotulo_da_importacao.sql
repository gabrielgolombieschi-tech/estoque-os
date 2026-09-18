-- Dois acertos de dados pedidos pelo Gabriel em 18/09/2026, com o motivo registrado aqui e
-- no audit_log. Nenhuma nota fiscal muda.
--
-- 1. OV-SEG-00004-026 (ordens_servico 344, PBG S/A "Portobello", CLP OMRON CQM1H-CPU61):
--    a linha os_itens 6394 nasceu em 02/09/2026 com R$ 1.650,00, que e o preco de venda do
--    cadastro do item (itens.preco_unitario). O preco fechado com o cliente e o do orcamento
--    SEG-387-026 (FECHADO em 01/09/2026): R$ 4.488,00 + 1,68% da condicao 45 DIAS = R$ 4.563,40,
--    que ja e o `orcado` da OV. Por que herdou o preco do cadastro: o orcamento foi fechado
--    sem "importar itens para a OV" (m.orcamento.os_itens_importados_at e nulo), e a linha foi
--    incluida a mao na tela da venda, cujo campo de valor vem preenchido com
--    itens.preco_unitario (VendaDetalheClient.selecionarNovoItem) — ninguem trocou. Os rascunhos
--    de NF-e nao foram afetados porque o painel de faturar sugere o preco rateando o `orcado`.
--    Aqui so a linha e o total da OV mudam; o orcado ja estava certo.
--
-- 2. Importacao 6f420998 (DIR 260191366846, NF-e 2/24): dados_json.motivo_compra guardava
--    id = ef6a9131 (CONSUMO - PRODUCAO E ENGENHARIA) com nome/codigo "Compra para estoque" /
--    "ESTOQUE" — rotulo velho que sobrou quando a migration 20260918060000 trocou o motivo do
--    titulo da UPS para o plano de consumo (CFOP 3556). So o texto e corrigido; o id, o titulo
--    (cancelado) e o reembolso nao mudam.
--
-- Os blocos pulam quando as linhas nao existem (banco local recriado do zero).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

-- 1. Preco da linha da OV ------------------------------------------------------------------
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
  if (v_antes->>'valor_unitario')::numeric = 4563.40 then
    raise notice 'os_itens 6394 ja esta com 4.563,40.';
    return;
  end if;

  select o.orcado into v_orcado from public.ordens_servico o where o.id = 344 and o.tipo_documento = 'OV';
  if v_orcado is distinct from 4563.40 then
    raise exception 'OV 344: orcado esperado 4563.40, encontrado %', v_orcado;
  end if;

  update public.os_itens oi
     set valor_unitario = 4563.40,
         valor_total = round(oi.quantidade * 4563.40, 2),
         observacoes = concat_ws(' | ', nullif(btrim(coalesce(oi.observacoes, '')), ''),
           'Preco corrigido em 18/09/2026: de 1.650,00 (preco do cadastro do item) para 4.563,40, '
           || 'o do orcamento SEG-387-026 fechado (4.488,00 + 1,68% da condicao 45 DIAS). '
           || 'Pedido do Gabriel; migration 20260918200000.')
   where oi.id = 6394
  returning to_jsonb(oi) into v_depois;

  -- os_itens nao tem gatilho de auditoria: o registro vai a mao, no mesmo formato.
  insert into public.audit_log (tenant_id, table_name, action, row_pk, old_data, new_data, actor_email)
  values ((v_antes->>'tenant_id')::uuid, 'os_itens', 'UPDATE', '6394', v_antes, v_depois,
          'migration 20260918200000 (pedido do Gabriel, 18/09/2026)');

  update public.ordens_servico o
     set valor_total = (select coalesce(sum(x.valor_total), 0) from public.os_itens x where x.os_id = o.id),
         atualizado_em = now()
   where o.id = 344 and o.tipo_documento = 'OV';
end;
$preco$;

-- 2. Rotulo do motivo de compra no JSON da importacao ------------------------------------------
do $rotulo$
declare
  v_id constant uuid := '6f420998-c0b6-4a27-a2ca-c52bc5f030e1';
  v_motivo constant uuid := 'ef6a9131-d2c8-40d2-a2c0-f141d160a848';
  v_codigo text;
  v_nome text;
begin
  select m.codigo, m.nome into v_codigo, v_nome from f.motivo_compra m where m.id = v_motivo;
  if v_codigo is null then
    raise notice 'motivo de compra % nao existe neste banco: nada a corrigir.', v_motivo;
    return;
  end if;
  if v_codigo <> 'CONSUMO_PRODUCAO' then
    raise exception 'motivo % deveria ser CONSUMO_PRODUCAO, encontrado %', v_motivo, v_codigo;
  end if;

  update f.importacao_remessa r
     set dados_json = jsonb_set(
           jsonb_set(
             jsonb_set(r.dados_json, '{motivo_compra,nome}', to_jsonb(v_nome)),
             '{motivo_compra,codigo}', to_jsonb(v_codigo)),
           '{motivo_compra,rotulo_corrigido}',
           to_jsonb('18/09/2026: nome/codigo diziam "Compra para estoque"/ESTOQUE, mas o id e o de '
                    || v_codigo || ' (rateio do titulo da UPS no plano de consumo, CFOP 3556). So o texto mudou; migration 20260918200000.'::text)),
         updated_at = now()
   where r.id = v_id
     and r.dados_json->'motivo_compra'->>'id' = v_motivo::text
     and r.dados_json->'motivo_compra'->>'codigo' = 'ESTOQUE';
  if not found then
    raise notice 'importacao % nao existe ou o rotulo ja esta certo.', v_id;
  end if;
end;
$rotulo$;

-- Conferencias: so checam. --------------------------------------------------------------------
do $assertions$
declare
  v_linha public.os_itens%rowtype;
  v_ov numeric;
begin
  select * into v_linha from public.os_itens where id = 6394 and os_id = 344;
  if v_linha.id is not null then
    if v_linha.valor_unitario <> 4563.40 or v_linha.valor_total <> round(v_linha.quantidade * 4563.40, 2) then
      raise exception 'os_itens 6394 nao ficou com 4.563,40: % / %', v_linha.valor_unitario, v_linha.valor_total;
    end if;
    select valor_total into v_ov from public.ordens_servico where id = 344;
    if v_ov <> (select sum(valor_total) from public.os_itens where os_id = 344) then
      raise exception 'valor_total da OV 344 (%) nao fecha com as linhas', v_ov;
    end if;
    if not exists (select 1 from public.audit_log where table_name = 'os_itens' and row_pk = '6394' and actor_email like 'migration 20260918200000%') then
      raise exception 'audit_log da correcao da linha 6394 nao gravado';
    end if;
  end if;
  if exists (
    select 1 from f.importacao_remessa r
    where r.id = '6f420998-c0b6-4a27-a2ca-c52bc5f030e1'
      and r.dados_json->'motivo_compra'->>'codigo' = 'ESTOQUE'
      and r.dados_json->'motivo_compra'->>'id' = 'ef6a9131-d2c8-40d2-a2c0-f141d160a848'
  ) then
    raise exception 'rotulo do motivo de compra da importacao 6f420998 continua trocado';
  end if;
end;
$assertions$;

commit;
