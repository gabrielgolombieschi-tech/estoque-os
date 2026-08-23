begin;

alter table public.ordens_servico
  add column if not exists is_fiado boolean not null default false;

alter table public.ordens_servico
  add column if not exists orcamento_gerado_id uuid references m.orcamento (id) on delete set null;

comment on column public.ordens_servico.is_fiado is
  'OS aberta diretamente sem orcamento previo (OS Fiado): materiais/despesas e mao de obra (HH ou apontamento) ficam disponiveis simultaneamente, em vez de mutuamente exclusivos.';
comment on column public.ordens_servico.orcamento_gerado_id is
  'Orcamento gerado/atualizado a partir desta OS Fiado via fn_gerar_ou_atualizar_orcamento_de_os. Link reverso de m.orcamento.os_id. Nao usa FK composta (tenant_id, empresa_id) porque m.orcamento nao tem unique nessas 3 colunas; o RPC revalida tenant/empresa manualmente.';

notify pgrst, 'reload schema';

commit;
