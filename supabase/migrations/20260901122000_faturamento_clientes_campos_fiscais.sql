begin;

alter table public.clientes
  add column indicador_ie text
    check (indicador_ie in ('1', '2', '9')),
  add column codigo_ibge_municipio text;

commit;
