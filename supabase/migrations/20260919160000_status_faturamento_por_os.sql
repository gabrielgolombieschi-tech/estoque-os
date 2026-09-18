-- Status de faturamento da OS/OV, calculado, separado do status da ordem.
--
-- A lista de vendas mostrava uma coluna "Faturado: Sim/Nao" derivada de duas coisas soltas: o
-- status da ordem ser 'faturada' ou existir QUALQUER documento de saida "emitido". Duas falhas:
--
--   1. o teste de emitido aceitava situacao VAZIA como emitida
--      (lib/os/faturadoPorOs.ts: `if (!nfeStatus) return true;`), o que e um "sim" por omissao;
--   2. nao olhava o saldo: OS com uma nota parcial aparecia igual a uma OS quitada.
--
-- Esta view entrega os tres estados de uma vez, para a lista inteira, sem N+1:
--
--   FATURADA     saldo zerado (tolerancia de meio centavo) e ao menos uma nota emitida;
--   PARCIAL      nota emitida e saldo restante;
--   NAO_FATURADA nenhuma nota emitida.
--
-- Nota CANCELADA nunca conta, em nenhuma hipotese, e situacao vazia tambem nao: so entra
-- documento de saida, nao apagado, com situacao explicitamente EMITIDA. E a mesma regra de
-- f.fn_os_saldo_a_faturar, menos o atalho da situacao vazia.
--
-- O saldo aqui NAO desconta reserva de rascunho: rascunho nao e nota, e uma OS com rascunho
-- aberto continua "nao faturada". Quem precisa da reserva usa f.fn_os_saldo_a_faturar.
--
-- Legado: 141 OS estao marcadas 'faturada' sem nenhum documento no ERP (faturadas fora dele,
-- antes do modulo fiscal). Para essas a view devolve FATURADA com origem STATUS_ORDEM, para a
-- lista nao passar a mentir que elas estao em aberto. O status da ordem nunca e escrito aqui.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- A regra estrita de "documento emitido", em um lugar so. A versao antiga dessa regra, espalhada
-- pelo baseline, aceita situacao vazia como emitida; ela continua valendo onde ja esta (saldo,
-- titulo a receber, gatilhos de importacao) e NAO e tocada aqui. Esta funcao e a regra nova, usada
-- pelo status de faturamento da lista.
create or replace function f.fn_documento_esta_emitido(p_modelo text, p_nfe_status text, p_nfse_status text)
returns boolean
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select case
    when upper(coalesce(p_modelo, '')) = 'NFSE' then upper(coalesce(p_nfse_status, '')) = 'EMITIDA'
    else upper(coalesce(p_nfe_status, '')) = 'EMITIDA'
  end;
$function$;

comment on function f.fn_documento_esta_emitido(text, text, text) is
  'Regra estrita: so e documento emitido quem tem situacao explicitamente EMITIDA. Cancelada nao conta, situacao vazia nao conta.';

revoke all on function f.fn_documento_esta_emitido(text, text, text) from public;
grant execute on function f.fn_documento_esta_emitido(text, text, text) to authenticated;
grant execute on function f.fn_documento_esta_emitido(text, text, text) to service_role;

create or replace view f.v_os_faturamento_status with (security_invoker = true) as
with documentos as (
  select
    d.tenant_id,
    d.empresa_id,
    d.os_id_import as os_id,
    count(*) filter (where f.fn_documento_esta_emitido(d.modelo, d.nfe_status, d.nfse_status)) as notas_emitidas,
    count(*) filter (where upper(coalesce(d.nfe_status, d.nfse_status, '')) = 'CANCELADA') as notas_canceladas,
    coalesce(sum(f.fn_documento_valor_faturado(d.modelo, d.valor_total, d.valor_servicos, d.valor_produtos))
             filter (where f.fn_documento_esta_emitido(d.modelo, d.nfe_status, d.nfse_status)), 0) as valor_faturado
  from f.documento_fiscal d
  where d.os_id_import is not null
    and d.operacao = 'SAIDA'
    and d.deleted_at is null
  group by d.tenant_id, d.empresa_id, d.os_id_import
),
calculado as (
  select
    os.tenant_id,
    os.empresa_id,
    os.id as os_id,
    os.tipo_documento,
    coalesce(os.status_fluxo, os.status, 'em_andamento') as status_ordem,
    round(case
      when coalesce(os.usa_relatorio_hh, false) then coalesce(hh.total_hh, 0)
      else coalesce(os.orcado, 0)
    end, 2) as valor_pedido,
    round(coalesce(doc.valor_faturado, 0), 2) as valor_faturado,
    coalesce(doc.notas_emitidas, 0) as notas_emitidas,
    coalesce(doc.notas_canceladas, 0) as notas_canceladas
  from public.ordens_servico os
  left join documentos doc
    on doc.tenant_id = os.tenant_id and doc.empresa_id = os.empresa_id and doc.os_id = os.id
  left join public.vw_hh_total_os hh
    on hh.tenant_id = os.tenant_id and hh.empresa_id = os.empresa_id and hh.os_id = os.id
  where os.tipo_documento in ('OS', 'OV')
)
select
  c.tenant_id,
  c.empresa_id,
  c.os_id,
  c.tipo_documento,
  c.status_ordem,
  c.valor_pedido,
  c.valor_faturado,
  round(c.valor_pedido - c.valor_faturado, 2) as saldo_a_faturar,
  c.notas_emitidas,
  c.notas_canceladas,
  case
    when c.notas_emitidas > 0 and round(c.valor_pedido - c.valor_faturado, 2) <= 0.005 then 'FATURADA'
    when c.notas_emitidas > 0 then 'PARCIAL'
    when c.status_ordem = 'faturada' then 'FATURADA'
    else 'NAO_FATURADA'
  end as status_faturamento,
  case
    when c.notas_emitidas > 0 then 'DOCUMENTO'
    when c.status_ordem = 'faturada' then 'STATUS_ORDEM'
    else 'SEM_NOTA'
  end as origem_status
from calculado c;

comment on view f.v_os_faturamento_status is
  'Status de faturamento calculado por OS/OV (FATURADA, PARCIAL, NAO_FATURADA), separado do status da ordem. So conta documento de saida com situacao EMITIDA; cancelada e situacao vazia nunca contam. O saldo nao desconta reserva de rascunho.';

alter view f.v_os_faturamento_status owner to postgres;
revoke all on table f.v_os_faturamento_status from public;
grant select on table f.v_os_faturamento_status to authenticated;
grant select on table f.v_os_faturamento_status to service_role;

do $assertions$
declare
  v_ov record;
begin
  if not exists (select 1 from public.ordens_servico where id = 365) then
    raise notice 'banco sem os dados de producao: asserts de dados pulados.';
    return;
  end if;

  -- OV-SEG-00012-026: uma NF-e autorizada (2/35) e uma cancelada (2/34). Tem de ficar FATURADA
  -- pelo documento, com a cancelada contada a parte e fora do valor faturado.
  select * into v_ov from f.v_os_faturamento_status where os_id = 365;
  if v_ov.status_faturamento <> 'FATURADA' or v_ov.origem_status <> 'DOCUMENTO' then
    raise exception 'OV 365 devia ficar FATURADA por documento, veio % / %', v_ov.status_faturamento, v_ov.origem_status;
  end if;
  if v_ov.notas_emitidas <> 1 or v_ov.notas_canceladas <> 1 then
    raise exception 'OV 365: esperado 1 nota emitida e 1 cancelada, veio % / %', v_ov.notas_emitidas, v_ov.notas_canceladas;
  end if;
  if v_ov.valor_faturado <> 4145.70 or v_ov.saldo_a_faturar > 0.005 then
    raise exception 'OV 365: faturado % e saldo % fora do esperado', v_ov.valor_faturado, v_ov.saldo_a_faturar;
  end if;

  -- Nenhuma OS/OV pode ficar FATURADA por documento com saldo sobrando.
  if exists (
    select 1 from f.v_os_faturamento_status
    where status_faturamento = 'FATURADA' and origem_status = 'DOCUMENTO' and saldo_a_faturar > 0.005
  ) then
    raise exception 'ha OS marcada FATURADA por documento com saldo em aberto';
  end if;
end;
$assertions$;

commit;
