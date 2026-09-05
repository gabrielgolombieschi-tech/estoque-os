begin;

-- Provisionamento unico concluido: as credenciais permanecem criptografadas
-- no Vault e a API que aceitava o valor sensivel deixa de existir.
drop function if exists f.fn_nfe_configurar_agendador(text, text);

commit;
