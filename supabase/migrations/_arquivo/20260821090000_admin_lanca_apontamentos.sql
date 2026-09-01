begin;

set local role postgres;

-- Papel 'admin' (mapeado a partir de OWNER/ADMIN/DIRETOR no tenant, ver
-- a.fn_map_papel_tenant_to_role) tinha em role_permissions somente
-- 'apontamentos.read'. A tela de apontamentos (app/apontamentos/page.tsx)
-- so libera o formulario de lancamento/edicao/exclusao quando a capability
-- "apontamentos.write" e true, e essa capability so vira true por dois
-- caminhos: a RPC can_many/can() (que ja bypassa tudo pra papel de tenant
-- OWNER/ADMIN/DIRETOR) ou o alias legado 'apontamentos.lancar' -> write=true
-- em lib/auth/provider.tsx. Sem essa permissao aqui, quem depende so do
-- caminho legado (ou quando can_many falha/e ignorado) fica preso na tela
-- "Consulta somente leitura" mesmo sendo dono/admin da conta.

insert into public.role_permissions (role, permission)
values ('admin', 'apontamentos.lancar')
on conflict (role, permission) do nothing;

notify pgrst, 'reload schema';

commit;
