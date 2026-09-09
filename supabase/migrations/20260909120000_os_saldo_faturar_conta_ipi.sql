-- Saldo a faturar da OS/OV passa a contar o IPI.
--
-- Decisao de Gabriel em 09/09/2026, na OS 287 (WEG Tintas, pedido 4518946561).
-- O orcado da OS e o valor do pedido do cliente, e o pedido vem com IPI: o da WEG
-- fecha em 21.303,96 porque soma 9,75% sobre 19.411,35 de mercadoria. A funcao,
-- porem, media o faturado da NF-e por valor_produtos (sem IPI), entao sobrava um
-- saldo residual do tamanho exato do imposto e a OS nunca zerava — os_faturar
-- exige saldo <= 0,005, logo nenhuma OS com IPI conseguia virar Faturada.
--
-- Evidencia levantada antes da mudanca, nas 11 NF-e de saida com IPI ligadas a OS
-- (notas 3715, 3733, 3766, 3771, 3781, 3786, 3793, 3795, 3798, 3799, 3801):
--   * orcado da OS = valor_total da nota nas 11; nenhuma tem orcado = valor_produtos;
--   * valor_total - valor_produtos = o IPI gravado em documento_fiscal_imposto,
--     centavo a centavo — sem frete, seguro ou outros no meio.
-- Das 486 notas de saida da base, so 6 tem frete ou desconto e nenhuma delas tem
-- os_id_import, ou seja, nunca entram nesta conta. A tela de faturar tambem so
-- oferece modalidade "9 - sem frete".
--
-- Duas mudancas, para faturado e reserva ficarem na mesma moeda:
--   1. valor_faturado = valor_total do documento (vNF, ja liquido de desconto —
--      por isso o valor_desconto NAO e subtraido de novo). NFS-e ja era assim.
--   2. valor_reservado = produtos + IPI previsto do rascunho, com a mesma regra do
--      builder da NF-e (CST 00/49/50/99 com aliquota). Sem isso um rascunho com IPI
--      reservaria menos do que vai consumir e a tela mostraria folga inexistente.
--
-- Efeito medido nas OS existentes: 11 OS saem do residual para saldo 0,00 (as 8 ja
-- faturadas, onde o resto era ruido, e as OS 342, 343 e 344, que ficam prontas para
-- faturar). Nenhuma OS nova fica negativa: 4 antes, as mesmas 4 depois. Como vNF
-- nunca e menor que valor_produtos, o saldo so pode cair — nenhuma OS reabre.

create or replace function f.fn_os_saldo_a_faturar(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns table(valor_pedido numeric, valor_faturado numeric, valor_reservado numeric, saldo numeric, usa_relatorio_hh boolean)
language plpgsql
stable security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_os public.ordens_servico%rowtype;
  v_valor_pedido numeric(14,2);
  v_valor_faturado numeric(14,2);
  v_valor_reservado numeric(14,2);
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS/OV sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar o faturamento desta empresa.';
  end if;

  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id and os.id = p_os_id and os.tipo_documento in ('OS', 'OV');
  if not found then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  if v_os.usa_relatorio_hh then
    select coalesce(hh.total_hh, 0) into v_valor_pedido
    from public.vw_hh_total_os hh
    where hh.tenant_id = p_tenant_id and hh.empresa_id = p_empresa_id and hh.os_id = p_os_id;
    v_valor_pedido := coalesce(v_valor_pedido, 0);
  else
    v_valor_pedido := coalesce(v_os.orcado, 0);
  end if;

  -- O que o cliente ja deve pela nota: vNF, que traz o IPI e ja esta liquido de
  -- desconto. Nao subtrair valor_desconto aqui — seria descontar duas vezes.
  select coalesce(sum(greatest(coalesce(df.valor_total, df.valor_produtos, 0), 0)), 0)
  into v_valor_faturado
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id and df.os_id_import = p_os_id
    and df.operacao = 'SAIDA' and df.deleted_at is null
    and (
      (upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
      or (upper(coalesce(df.modelo, '')) <> 'NFSE' and (nullif(btrim(df.nfe_status), '') is null or upper(df.nfe_status) = 'EMITIDA'))
    );

  -- Reserva do rascunho na mesma moeda do faturado: mercadoria + IPI previsto.
  -- Mesma regra do builder (supabase/functions/_shared/nfe-payload.ts): so ha IPI
  -- quando o CST e tributado e a aliquota esta preenchida.
  select coalesce(sum(
    (case when si.cst_ipi in ('00', '49', '50', '99') and si.aliquota_ipi is not null
       then round(round(greatest(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0), 0), 2) * si.aliquota_ipi / 100, 2)
       else 0 end)
    + round(greatest(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0), 0), 2)
  ), 0)
  into v_valor_reservado
  from f.solicitacao_faturamento sf
  join f.solicitacao_item si
    on si.tenant_id = sf.tenant_id and si.empresa_id = sf.empresa_id and si.solicitacao_id = sf.id
  where sf.tenant_id = p_tenant_id and sf.empresa_id = p_empresa_id
    and sf.status <> 'CANCELADA'
    and si.origem_tipo = v_os.tipo_documento
    and si.origem_id = p_os_id::text
    and not exists (
      select 1
      from f.documento_fiscal_emissao e
      join f.documento_fiscal d on d.tenant_id = e.tenant_id and d.empresa_id = e.empresa_id and d.id = e.documento_fiscal_id
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
        and d.deleted_at is null and upper(coalesce(d.nfe_status, d.nfse_status, '')) = 'EMITIDA'
    )
    and coalesce((
      select e.status
      from f.documento_fiscal_emissao e
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
      order by e.created_at desc, e.documento_fiscal_id desc
      limit 1
    ), 'RASCUNHO') not in ('REJEITADA', 'ERRO', 'CANCELADA');

  valor_pedido := round(v_valor_pedido, 2);
  valor_faturado := round(v_valor_faturado, 2);
  valor_reservado := round(v_valor_reservado, 2);
  saldo := round(v_valor_pedido - v_valor_faturado - v_valor_reservado, 2);
  usa_relatorio_hh := coalesce(v_os.usa_relatorio_hh, false);
  return next;
end;
$function$;
