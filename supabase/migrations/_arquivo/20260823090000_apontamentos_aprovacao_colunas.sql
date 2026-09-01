begin;

alter table colaboradores
  add column user_id uuid unique references auth.users(id),
  add column email text;

alter table ordens_servico
  add column responsavel_aprovacao_id uuid references auth.users(id);

alter table apontamentos_horas
  add column criado_por_user_id uuid references auth.users(id),
  add column aprovado_por uuid references auth.users(id),
  add column aprovado_em timestamptz,
  add column motivo_devolucao text;

-- Congela o histórico existente antes do novo fluxo de aprovação.
update apontamentos_horas set status = 'fechado';

alter table apontamentos_horas
  add constraint chk_status_apontamento
  check (status in ('lancado', 'aprovado', 'devolvido', 'fechado'));

create index idx_colaboradores_user_id
  on colaboradores (user_id) where user_id is not null;

create index idx_apontamentos_status
  on apontamentos_horas (status, empresa_id);

commit;
