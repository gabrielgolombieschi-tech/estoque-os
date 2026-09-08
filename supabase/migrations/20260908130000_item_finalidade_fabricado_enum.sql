-- Finalidade propria para produto fabricado (producao propria).
--
-- Fica sozinha nesta migration porque um valor novo de enum so pode ser usado
-- depois que a transacao que o criou termina; o trigger, as funcoes e o
-- backfill que dependem dele vem na migration seguinte.
alter type public.item_finalidade add value if not exists 'fabricado';
