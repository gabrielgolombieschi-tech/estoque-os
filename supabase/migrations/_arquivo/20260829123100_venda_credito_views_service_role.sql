begin;

-- As views usam security_invoker; o papel técnico precisa também poder ler
-- as relações de origem. RLS continua sendo aplicada aos usuários normais.
grant select on table public.clientes to service_role;
grant select on table public.ordens_servico to service_role;
grant select on table public.cliente_unidades to service_role;
grant select on table f.gestao_cobranca_os to service_role;
grant select on table f.documento_fiscal to service_role;
grant select on table a.usuario to service_role;

notify pgrst, 'reload schema';

commit;
