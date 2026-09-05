begin;

alter table f.tributacao_provisoria_homologacao
  drop constraint tributacao_provisoria_homologacao_tenant_id_fkey,
  add constraint tributacao_provisoria_homologacao_tenant_id_fkey
    foreign key (tenant_id) references c.tenant(id) on delete cascade;

comment on constraint tributacao_provisoria_homologacao_tenant_id_fkey
  on f.tributacao_provisoria_homologacao is
  'Usa o tenant canonico do dominio c, igual aos demais objetos fiscais.';

commit;
