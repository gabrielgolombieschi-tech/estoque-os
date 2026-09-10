-- NF-e 55/1/3805 (ArcelorMittal, R$ 433.434,55) termina a importacao que parou na metade.
--
-- Gabriel em 10/09/2026: a nota nao aparecia em /faturamento/nfe nem estava ligada a
-- OS 282. Ela foi importada em 08/09 17:33 — um dia ANTES da 20260909150000, que
-- destravou a segunda fase do importador de saida. Ficou exatamente no estado que
-- aquela migration descreve: ENTRADA, com o fornecedor sintetico "FATURAMENTO
-- (EMITENTE)" (id 262), sem cliente, sem nfe_status e sem OS.
--
-- E a nota que substituiu a 3804 (mesmo valor, mesma OS, emitida no dia seguinte);
-- a 3804 esta CANCELADA. A chave confirma que a emitente e a propria Segau:
-- 4226 09 13671448000189 55 001 000003805 1 00005424 5.
--
-- Reimportar o XML nao resolvia: o importador recusa com 409 "Este XML ja foi
-- importado" justamente porque este documento pela metade ja carrega a chave. Por
-- isso a correcao vem por migration, com os mesmos campos que a fase 2 do
-- app/api/faturamento/nfe/importar-xml grava.
--
-- Fica de fora, de proposito, a serie 11 numero 167992 (emitente 34776007000898, de
-- terceiro): tambem esta travada, mas nao e nota de saida da Segau e nao se sabe o
-- destino pretendido. Anotada para o Gabriel decidir.

update f.documento_fiscal df
   set cliente_id = 42,
       fornecedor_id = null,
       operacao = 'SAIDA',
       natureza = 'PRODUTO',
       nfe_status = 'EMITIDA',
       os_id_import = 281,
       competencia_date = date_trunc('month', df.emissao_date)::date,
       updated_at = now()
 where df.chave_acesso = '42260913671448000189550010000038051000054245'
   and df.operacao = 'ENTRADA'
   and df.nfe_status is null
   and df.deleted_at is null;

do $conferir$
declare
  v record;
begin
  select df.id, df.operacao, df.nfe_status, df.os_id_import, df.cliente_id, df.valor_total
    into v
  from f.documento_fiscal df
  where df.chave_acesso = '42260913671448000189550010000038051000054245'
    and df.deleted_at is null;

  if not found then
    raise notice 'NF-e 3805 nao existe neste banco; nada a fazer.';
    return;
  end if;
  if v.operacao <> 'SAIDA' or v.nfe_status <> 'EMITIDA' or v.os_id_import <> 281 or v.cliente_id <> 42 then
    raise exception 'NF-e 3805 ficou com operacao=%, nfe_status=%, os=%, cliente=%; esperado SAIDA / EMITIDA / 281 / 42.',
      v.operacao, v.nfe_status, v.os_id_import, v.cliente_id;
  end if;

  -- Impostos do documento: o mesmo trabalho que a fase 2 do importador dispara. Aqui
  -- vai pela variante unscoped porque a migration roda como postgres, e o wrapper
  -- publico exige contexto de empresa e papel de faturamento de uma sessao logada.
  perform f.nfe_gravar_impostos_do_documento_unscoped_20260810(v.id);
  raise notice 'NF-e 1/3805 promovida a SAIDA/EMITIDA, cliente 42, OS 282 (id 281), R$ %.', v.valor_total;
end
$conferir$;
