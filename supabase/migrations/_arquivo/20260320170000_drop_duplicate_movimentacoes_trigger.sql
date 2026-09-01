begin;

-- Evita dupla aplicação de delta no estoque ao inserir em public.movimentacoes.
-- A trigger trg_movimentacoes_apply_estoque é a implementação que deve permanecer.
drop trigger if exists trg_mov_atualiza_estoque on public.movimentacoes;

commit;
