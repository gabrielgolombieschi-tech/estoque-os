-- Importacao por remessa expressa: o que a primeira homologacao em tela (NF-e 2/66, 17/09/2026) pediu.
--
-- 1. Anexos: o bucket nfe-documentos so aceitava XML e PDF; a GNRE e a nota de debito chegam em
--    PDF, mas a invoice vem como foto (JPEG/PNG) e, quando o PDF nao vem, o extrato em texto.
-- 2. Nota de debito do courier: a conta bancaria que pagou (e a data) podem nao estar a mao na
--    hora de gerar a importacao; ate a nota real ser autorizada da para completar sem gerar de
--    novo (e sem tocar na NF-e, que nao leva esses dados).

update storage.buckets
   set allowed_mime_types = array['application/xml', 'text/xml', 'application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'text/plain', 'text/markdown']
 where id = 'nfe-documentos';

create or replace function f.fn_importacao_remessa_nota_debito_atualizar(p_importacao_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_imp f.importacao_remessa%rowtype;
  v_numero text := nullif(btrim(coalesce(p_dados->>'numero', '')), '');
  v_valor numeric(15,2) := nullif(p_dados->>'valor', '')::numeric;
  v_emissao date := nullif(p_dados->>'emissao', '')::date;
  v_pago_em date := nullif(p_dados->>'pago_em', '')::date;
  v_conta uuid := nullif(p_dados->>'conta_bancaria_id', '')::uuid;
  v_forma text := nullif(upper(btrim(coalesce(p_dados->>'forma_pagamento', ''))), '');
  v_motivo uuid := nullif(p_dados->>'motivo_compra_id', '')::uuid;
  v_servicos numeric(15,2) := nullif(p_dados->>'courier_servicos', '')::numeric;
  v_armazenagem numeric(15,2) := nullif(p_dados->>'courier_armazenagem', '')::numeric;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_imp from f.importacao_remessa i
   where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id and i.id = p_importacao_id and i.deleted_at is null
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Importacao nao encontrada.';
  end if;
  if v_imp.status in ('CONCLUIDA', 'CANCELADA') then
    raise exception using errcode = '55000', message = 'A importacao ja foi concluida ou cancelada; a nota de debito ja esta no contas a pagar (ou nao ha o que lancar).';
  end if;
  if v_numero is not null and (v_valor is null or v_valor <= 0) then
    raise exception using errcode = '22023', message = 'Informe o valor da nota de debito do courier.';
  end if;
  if v_forma is not null and v_forma not in ('PIX', 'BOLETO', 'TRANSFERENCIA', 'DINHEIRO', 'CARTAO', 'OUTROS') then
    raise exception using errcode = '22023', message = 'Forma de pagamento da nota de debito invalida (PIX, BOLETO, TRANSFERENCIA, DINHEIRO, CARTAO ou OUTROS).';
  end if;
  if v_conta is not null and not exists (
    select 1 from f.conta_bancaria cb where cb.id = v_conta and cb.tenant_id = v_scope.tenant_id and cb.empresa_id = v_scope.empresa_id and cb.deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Conta bancaria da nota de debito nao encontrada.';
  end if;
  if v_pago_em is not null and (v_conta is null or v_forma is null) then
    raise exception using errcode = '22023', message = 'Nota de debito paga: informe a conta bancaria e a forma de pagamento.';
  end if;
  if coalesce(v_servicos, 0) < 0 or coalesce(v_armazenagem, 0) < 0 then
    raise exception using errcode = '22023', message = 'Despesas do courier nao podem ser negativas.';
  end if;

  update f.importacao_remessa
     set nota_debito_numero = v_numero,
         nota_debito_valor = case when v_numero is null then null else v_valor end,
         nota_debito_emissao = v_emissao,
         nota_debito_pago_em = v_pago_em,
         nota_debito_conta_bancaria_id = case when v_pago_em is null then null else v_conta end,
         nota_debito_forma_pagamento = case when v_pago_em is null then null else v_forma end,
         nota_debito_motivo_compra_id = coalesce(v_motivo, nota_debito_motivo_compra_id),
         courier_servicos = coalesce(v_servicos, courier_servicos),
         courier_armazenagem = coalesce(v_armazenagem, courier_armazenagem),
         updated_at = now()
   where id = v_imp.id;
  -- O custo de estoque leva as despesas do courier: refaz o rateio quando elas mudaram.
  if v_servicos is not null or v_armazenagem is not null then
    update f.importacao_remessa_item it
       set courier_rateado = sub.rateado,
           custo_total = round(it.valor_aduaneiro_brl + it.ii_valor + sub.rateado + case when v_imp.credito_icms then 0 else it.icms_valor end, 2),
           custo_unitario = round((it.valor_aduaneiro_brl + it.ii_valor + sub.rateado + case when v_imp.credito_icms then 0 else it.icms_valor end) / it.quantidade, 6)
      from (
        select i.id, round((coalesce(v_servicos, v_imp.courier_servicos) + coalesce(v_armazenagem, v_imp.courier_armazenagem)) * i.valor_usd / nullif(sum(i.valor_usd) over (), 0), 2) as rateado
          from f.importacao_remessa_item i where i.importacao_id = v_imp.id
      ) sub
     where it.id = sub.id;
  end if;
  return jsonb_build_object('ok', true, 'importacao_id', v_imp.id, 'nota_debito_numero', v_numero, 'nota_debito_pago_em', v_pago_em);
end;
$$;
revoke all on function f.fn_importacao_remessa_nota_debito_atualizar(uuid, jsonb) from public, anon;
grant execute on function f.fn_importacao_remessa_nota_debito_atualizar(uuid, jsonb) to authenticated, service_role;

-- Reversao: drop function f.fn_importacao_remessa_nota_debito_atualizar(uuid, jsonb);
--   update storage.buckets set allowed_mime_types = array['application/xml','text/xml','application/pdf'] where id = 'nfe-documentos';
