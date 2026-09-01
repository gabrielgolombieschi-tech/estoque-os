-- Tabelas legadas sem registros e sem consumidores ativos no ERP.
-- A tabela filha deve ser removida antes da tabela de profissionais.
drop table if exists public.horas_trabalhadas;
drop table if exists public.profissionais;
