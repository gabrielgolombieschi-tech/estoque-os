-- Repara solicitacoes anteriores a conferencia de destino.
--
-- PROBLEMA
-- 20260903110000_nfe_conferencia_destino_perfil.sql criou
--   solicitacao_snapshot_destino_confirmado_ck
--     CHECK (snapshot_cadastro_em is null or destino_uf_confirmada is not null)
-- como NOT VALID, o que nao rejeita as linhas existentes mas passa a cobrar a regra
-- em todo INSERT/UPDATE. Uma solicitacao emitida ANTES dessa migration ficou com
-- snapshot_cadastro_em preenchido e destino_uf_confirmada nulo — e por isso ficou
-- congelada no banco: qualquer UPDATE nela falha, por qualquer caminho do sistema
-- (cancelamento, reconciliacao, abandono), nao apenas por um fluxo especifico.
--
-- SOLUCAO
-- Reconstruir a confirmacao a partir do dado autoritativo: a UF que efetivamente
-- foi enviada a SEFAZ no payload da emissao autorizada. Nao ha invencao de dado —
-- e o que consta no documento que a SEFAZ processou.
-- A data de confirmacao usa o proprio snapshot (ou a autorizacao), preservando a
-- ordem cronologica real. destino_confirmado_por fica nulo de proposito: nao houve
-- usuario confirmando, foi reconstrucao de sistema, e o par_ck admite esse caso.

begin;

with origem as (
  select distinct on (sf.id)
    sf.id as solicitacao_id,
    upper(btrim(dfe.payload_enviado->>'uf_destinatario')) as uf,
    coalesce(sf.snapshot_cadastro_em, dfe.autorizado_em, dfe.enviado_em) as confirmado_em
  from f.solicitacao_faturamento sf
  join f.documento_fiscal_emissao dfe
    on dfe.tenant_id = sf.tenant_id
   and dfe.empresa_id = sf.empresa_id
   and dfe.solicitacao_id = sf.id
  where sf.snapshot_cadastro_em is not null
    and sf.destino_uf_confirmada is null
    and dfe.payload_enviado is not null
    and upper(btrim(coalesce(dfe.payload_enviado->>'uf_destinatario', ''))) ~ '^[A-Z]{2}$'
  order by sf.id, dfe.autorizado_em desc nulls last, dfe.enviado_em desc nulls last
)
update f.solicitacao_faturamento sf
set destino_uf_confirmada = o.uf,
    destino_confirmado_em = o.confirmado_em,
    updated_at = now()
from origem o
where sf.id = o.solicitacao_id;

-- Agora que nao ha mais divergencia, a regra passa a valer tambem para o passado.
alter table f.solicitacao_faturamento
  validate constraint solicitacao_snapshot_destino_confirmado_ck;

commit;
