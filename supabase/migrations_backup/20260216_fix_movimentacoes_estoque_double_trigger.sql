begin;

-- FIX: Movimentações estavam atualizando estoque em dobro.
-- Causa: duas triggers AFTER INSERT em public.movimentacoes aplicando o delta:
--   - trg_mov_atualiza_estoque -> fn_atualiza_estoque_por_mov()
--   - trg_movimentacoes_apply_estoque -> apply_movimentacao_estoque()
-- Resultado observado no app: 30 -> setar 50 => vira 70 (delta aplicado 2x).
-- Mantemos a trigger baseada em apply_movimentacao_estoque() (já versionada em migration 20260111)
-- e removemos a trigger duplicada.

drop trigger if exists trg_mov_atualiza_estoque on public.movimentacoes;

commit;
