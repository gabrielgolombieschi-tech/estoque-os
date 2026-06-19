-- Importa os cargos já cadastrados em colaboradores para a nova tabela cargos

insert into public.cargos (tenant_id, nome, tipo_gestao, ativo)
select distinct
  tenant_id,
  upper(trim(cargo)),
  null,
  true
from public.colaboradores
where cargo is not null
  and trim(cargo) <> ''
on conflict (tenant_id, nome) do nothing;

notify pgrst, 'reload schema';
