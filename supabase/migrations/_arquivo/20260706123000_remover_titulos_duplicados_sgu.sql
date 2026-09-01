-- A migration 20260706120000_importar_notas_saida_sgu.sql inseriu os titulos
-- AR explicitamente, mas um trigger em f.documento_fiscal ja cria o titulo AR
-- automaticamente quando o documento entra como EMITIDA (via
-- f.fn_upsert_ar_from_nfe_venda / _v2), com vencimento padrao emissao+15.
-- Resultado: cada nota da SGU ficou com dois titulos AR.
--
-- Esta migration desativa (soft delete) os titulos gerados pelo trigger,
-- mantendo os que tem as parcelas corretas das duplicatas:
--   fc35bffb-... NFE 134  (venc 05/02/2026, padrao +15)      -> remover
--   8e10c42a-... NFE 137  (venc 14/03/2026, padrao +15)      -> remover
--   c9a6f481-... NFSE ... (venc 22/01/2026, padrao +15)      -> remover
-- Mantidos: cd65fb76 (134 a vista), ff040237 (137 com 12 duplicatas),
--           c31a7630 (NFS-e a vista).
--
-- Guardas: so remove se o titulo nao tiver recebimento aplicado.
-- Idempotente.

do $$
declare
  v_ids uuid[] := array[
    'fc35bffb-557e-4d98-aee7-f93895d243ad',
    '8e10c42a-b69e-491d-8d0d-69ede6563917',
    'c9a6f481-9277-43cb-927e-9ca64223e226'
  ]::uuid[];
  v_id uuid;
begin
  foreach v_id in array v_ids loop
    if exists (
      select 1
      from f.titulo_parcela tp
      join f.pagamento_item pi on pi.titulo_parcela_id = tp.id and pi.deleted_at is null
      where tp.titulo_id = v_id and tp.deleted_at is null
    ) then
      raise exception 'titulo % possui recebimentos aplicados - abortando', v_id;
    end if;

    update f.titulo_rateio
    set deleted_at = now(), updated_at = now()
    where titulo_id = v_id and deleted_at is null;

    update f.titulo_parcela
    set deleted_at = now(), updated_at = now()
    where titulo_id = v_id and deleted_at is null;

    update f.titulo
    set deleted_at = now(), updated_at = now()
    where id = v_id and deleted_at is null;

    raise notice 'titulo duplicado % desativado', v_id;
  end loop;
end $$;
