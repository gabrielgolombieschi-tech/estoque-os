begin;

grant select on table r.r_clientes_documento_pendencia to authenticated, service_role;
grant select on table r.r_venda_credito to authenticated, service_role;
grant select on table f.gestao_cobranca_os to service_role;
grant select on table public.cliente_unidades to service_role;

notify pgrst, 'reload schema';

commit;
