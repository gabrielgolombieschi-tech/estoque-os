\set ON_ERROR_STOP on
begin;

insert into c.tenant (id, codigo, nome)
values ('00000000-0000-0000-0000-00000000a001', 'TST', 'Tenant teste OV');

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia)
values (
  '00000000-0000-0000-0000-00000000e001',
  '00000000-0000-0000-0000-00000000a001',
  'TST',
  'Empresa teste OV',
  'Empresa teste OV'
);

insert into public.ordens_servico (
  id, numero_os, os_num, cliente_nome, tenant_id, empresa_id,
  tipo_pedido, tipo_documento, tem_gestao, usa_relatorio_hh
)
values (
  9000001, 9000001, 9000001, 'Cliente teste',
  '00000000-0000-0000-0000-00000000a001',
  '00000000-0000-0000-0000-00000000e001',
  'material', 'OV', true, true
);

insert into public.ordens_servico (
  id, numero_os, os_num, cliente_nome, tenant_id, empresa_id,
  tipo_pedido, tipo_documento
)
values (
  9000002, 9000002, 9000002, 'Cliente teste',
  '00000000-0000-0000-0000-00000000a001',
  '00000000-0000-0000-0000-00000000e001',
  'servico', 'OS'
);

do $$
declare
  v_ov public.ordens_servico%rowtype;
  v_os public.ordens_servico%rowtype;
begin
  select * into strict v_ov from public.ordens_servico where id = 9000001;
  select * into strict v_os from public.ordens_servico where id = 9000002;

  if v_ov.codigo !~ '^OV-TST-00001-[0-9]{3}$'
     or v_ov.numero_doc <> 1
     or v_ov.tem_gestao
     or v_ov.usa_relatorio_hh then
    raise exception 'Defaults OV incorretos: %', row_to_json(v_ov);
  end if;

  if v_os.codigo <> 'OS 9000002'
     or v_os.numero_doc is not null then
    raise exception 'Defaults OS incorretos: %', row_to_json(v_os);
  end if;
end
$$;

select id, tipo_documento, codigo, numero_doc, tem_gestao, usa_relatorio_hh
from public.ordens_servico
where id in (9000001, 9000002)
order by id;

rollback;
