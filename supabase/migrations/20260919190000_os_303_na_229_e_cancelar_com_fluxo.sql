-- OS cancelada passa a sair de "em andamento", e a OS 303 da Incepa vira parte da 229.
--
-- 1) Cancelar pela tela gravava so ordens_servico.status = 'cancelada'. O
--    status_fluxo ficava 'em_andamento', e e ele que a lista (filtro "Em
--    andamento"), o app, o status de faturamento (f.v_os_faturamento_status) e
--    as travas da NF-e/NFS-e leem primeiro. As OS 353 e 358, canceladas pela tela
--    em setembro, continuavam aparecendo como em andamento. Agora o banco acompanha:
--    status 'cancelada' leva o status_fluxo junto.
--
-- 2) A Incepa fechou as OS 229 (ADICIONAL ESTEIRA TRANSPORTADORA) e 303 (PROTECOES
--    LINHA ESTEIRA) numa ordem de compra so, a 50752518, com uma linha no valor da
--    229 (R$ 56.428,23). Decisao do Gabriel em 18/09/2026: o material da 303 vai
--    para a 229, a 303 e cancelada e o faturamento sai pela 229. Nao ha tela para
--    trocar material de OS: remover e lancar de novo devolveria ao estoque o que foi
--    comprado direto para a obra e perderia o vinculo com a NF de compra.
--
--    Vai para a 229 tudo o que aponta o material comprado para a 303:
--      os_itens 5414, 5415, 5422 (R$ 821,00, NF de entrada 3655 e 3670 da Telas BR
--        Fence), com a observacao "[OS 229]" que a reimportacao de XML reconhece;
--      as baixas 11025, 11026, 11051: movimentacao e imutavel, entao cada uma e
--        neutralizada por um ajuste e ganha uma baixa nova para a 229 (padrao de
--        reclassificar_mov_saida_para_os; o saldo do estoque nao muda);
--      nf_entrada 1992 e 2001 e o espelho fiscal delas (f.documento_fiscal);
--      f.titulo_aprovacao dos dois titulos a pagar dessas notas (rateio explicito,
--        preservado pela regra).
--    Fica na 303: as 8,5 h apontadas em 28 e 29/07 (apontamento fechado e aprovado,
--    o banco trava a alteracao), o orcamento SEG-341-026, os itens de gestao e o
--    teste de homologacao 2/19 de 05/09 (solicitacao ja cancelada).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.fn_ordens_servico_cancelada_no_fluxo()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  if new.status = 'cancelada' and old.status is distinct from 'cancelada' then
    new.status_fluxo := 'cancelada';
  end if;
  return new;
end;
$function$;

revoke all on function public.fn_ordens_servico_cancelada_no_fluxo() from public, anon, authenticated;

drop trigger if exists trg_ordens_servico_cancelada_no_fluxo on public.ordens_servico;
create trigger trg_ordens_servico_cancelada_no_fluxo
  before update of status on public.ordens_servico
  for each row execute function public.fn_ordens_servico_cancelada_no_fluxo();

-- OS canceladas pela tela antes desta correcao (353 e 358 em 18/09/2026).
update public.ordens_servico
   set status_fluxo = 'cancelada'
 where status = 'cancelada'
   and status_fluxo is not null
   and status_fluxo <> 'cancelada';

do $os_303_na_229$
declare
  v_303 public.ordens_servico%rowtype;
  v_229 public.ordens_servico%rowtype;
  v_n integer;
  v_saldo numeric;
  v_nota constant text := 'Cancelada em 18/09/2026: a Incepa fechou esta OS junto com a 229 na OC 50752518 (linha unica, valor da 229). Material transferido para a OS 229, que fatura.';
begin
  select * into v_303 from public.ordens_servico where id = 302 and numero_os = '303';
  select * into v_229 from public.ordens_servico where id = 228 and numero_os = '229';

  -- Banco sem os dados de producao (local recriado das migrations).
  if v_303.id is null or v_229.id is null then
    raise notice 'OS 303/229 ausentes; transferencia ignorada.';
    return;
  end if;

  if v_303.tenant_id <> v_229.tenant_id
     or v_303.empresa_id <> v_229.empresa_id
     or v_303.cliente_id <> v_229.cliente_id then
    raise exception 'OS 303 e 229 nao sao do mesmo cliente e empresa.';
  end if;

  if v_303.status = 'cancelada' then
    raise notice 'OS 303 ja cancelada; nada a fazer.';
    return;
  end if;

  -- Movimentacao e imutavel: a baixa para a 303 fica, neutralizada por um ajuste,
  -- e entra uma baixa nova para a 229. Mesmo padrao e mesmas datas de
  -- public.reclassificar_mov_saida_para_os; o saldo do estoque nao muda. Antes de
  -- mover os_itens, para o gatilho de registro nao reescrever quem lancou o material.
  if (select count(*) from public.movimentacoes
       where id in (11025, 11026, 11051) and tipo = 'saida' and origem_os_id = 302) <> 3 then
    raise exception 'Baixas da OS 303 fora do esperado.';
  end if;

  select coalesce(sum(e.quantidade_atual), 0) into v_saldo
    from public.estoque e
   where e.tenant_id = v_303.tenant_id and e.empresa_id = v_303.empresa_id
     and e.item_id in (2143, 3407, 2868);

  insert into public.movimentacoes (
    tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por,
    data_movimentacao, origem_nf_entrada_id, origem_os_id, created_at
  )
  select m.tenant_id, m.empresa_id, m.item_id, 'ajuste', m.quantidade,
         'CORRECAO RASTREIO OS: neutraliza mov #' || m.id::text, 'auditoria_sistema',
         -- Ajuste nao leva NF (movimentacoes_nf_required_ck), como os demais desta correcao.
         m.data_movimentacao, null, null, now()
    from public.movimentacoes m
   where m.id in (11025, 11026, 11051)
   order by m.id;

  insert into public.movimentacoes (
    tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por,
    data_movimentacao, origem_nf_entrada_id, origem_os_id, created_at
  )
  select m.tenant_id, m.empresa_id, m.item_id, 'saida', m.quantidade,
         replace(m.motivo, '[OS 303]', '[OS 229]'), 'auditoria_sistema',
         m.data_movimentacao, m.origem_nf_entrada_id, 228, now()
    from public.movimentacoes m
   where m.id in (11025, 11026, 11051)
   order by m.id;

  if (select coalesce(sum(e.quantidade_atual), 0) from public.estoque e
       where e.tenant_id = v_303.tenant_id and e.empresa_id = v_303.empresa_id
         and e.item_id in (2143, 3407, 2868)) <> v_saldo then
    raise exception 'Saldo de estoque mudou na troca de OS.';
  end if;

  update public.os_itens
     set os_id = 228,
         observacoes = replace(observacoes, '[OS 303]', '[OS 229]')
   where id in (5414, 5415, 5422)
     and os_id = 302;
  get diagnostics v_n = row_count;
  if v_n <> 3 then raise exception 'os_itens transferidos: % (esperado 3)', v_n; end if;

  if exists (select 1 from public.os_itens where os_id = 302) then
    raise exception 'OS 303 ainda tem material lancado fora dos tres itens conferidos.';
  end if;

  -- O gatilho antigo de NF de entrada recriaria os itens na OS nova com outra
  -- observacao (duplicando o material). Os itens ja foram movidos acima.
  alter table public.nf_entrada disable trigger trg_nf_entrada_sync_os_itens;
  update public.nf_entrada
     set os_id = 228
   where id in (1992, 2001)
     and os_id = 302;
  get diagnostics v_n = row_count;
  alter table public.nf_entrada enable trigger trg_nf_entrada_sync_os_itens;
  if v_n <> 2 then raise exception 'nf_entrada transferidas: % (esperado 2)', v_n; end if;

  update f.documento_fiscal
     set os_id_import = 228
   where id in ('1d14e355-d68e-4b05-9a22-6f70e9a72043', 'b3ebe81c-1297-495b-a495-b0e3303efb4c')
     and operacao = 'ENTRADA'
     and os_id_import = 302;
  get diagnostics v_n = row_count;
  if v_n <> 2 then raise exception 'documentos de entrada transferidos: % (esperado 2)', v_n; end if;

  update f.titulo_aprovacao
     set os_id = 228
   where id in ('267c47e2-c795-4915-804b-bacaa07ee4c7', 'd277579c-ce27-40e5-a643-2192a3c454fc')
     and os_id = 302;
  get diagnostics v_n = row_count;
  if v_n <> 2 then raise exception 'aprovacoes de titulo transferidas: % (esperado 2)', v_n; end if;

  update public.ordens_servico os
     set valor_total = coalesce((select sum(oi.valor_total) from public.os_itens oi where oi.os_id = os.id), 0),
         observacoes = case os.id
           when 228 then concat_ws(' | ', nullif(btrim(os.observacoes), ''),
             'Inclui o escopo da OS 303 (PROTECOES LINHA ESTEIRA): OC Incepa 50752518 unica. Material da 303 transferido em 18/09/2026.')
           else concat_ws(' | ', nullif(btrim(os.observacoes), ''), v_nota)
         end,
         status = case os.id when 302 then 'cancelada' else os.status end,
         atualizado_em = now()
   where os.id in (228, 302);

  if (select status_fluxo from public.ordens_servico where id = 302) is distinct from 'cancelada' then
    raise exception 'OS 303 cancelada sem status_fluxo cancelada.';
  end if;
  if (select valor_total from public.ordens_servico where id = 302) <> 0
     or (select valor_total from public.ordens_servico where id = 228) <> v_229.valor_total + 821.00 then
    raise exception 'valor_total das OS 229/303 fora do esperado.';
  end if;
end;
$os_303_na_229$;

notify pgrst, 'reload schema';

commit;
