-- Somente no PostgreSQL LOCAL. As RPCs reais de fechamento são exercitadas.
-- Contexto de sessão e fixtures isolados; triggers/FKs externos ao fechamento
-- ficam fora deste teste. Tudo, inclusive as funções de contexto, é revertido.
begin;
set local session_replication_role = replica;
create or replace function public.current_tenant_id() returns uuid language sql stable as
$$ select '00000000-0000-0000-0000-000000000051'::uuid $$;
create or replace function public.current_empresa_id() returns uuid language sql stable as
$$ select '00000000-0000-0000-0000-000000000052'::uuid $$;

insert into m.orcamento (id,tenant_id,empresa_id,numero,codigo,titulo,cliente_id,vendedor_usuario_id,created_by)
select ('00000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  public.current_tenant_id(), public.current_empresa_id(), n, 'TESTE-PC-' || n,
  'Fixture pedido cliente', 999991, '00000000-0000-0000-0000-000000000053', null
from generate_series(91001,91003) n;
insert into public.ordens_servico (id,tenant_id,empresa_id,numero_os,os_num,codigo,cliente_nome,tipo_documento,status,status_fluxo)
select n,public.current_tenant_id(),public.current_empresa_id(),n::text,n,'TESTE-PC-'||n,'Fixture',
  case when n=91002 then 'OS' else 'OV' end, 'em_andamento','em_andamento'
from generate_series(91002,91003) n;
update m.orcamento set os_id=numero where tenant_id=public.current_tenant_id()
  and empresa_id=public.current_empresa_id() and numero in (91002,91003);

do $$
declare
  v_id uuid := '00000000-0000-0000-0000-000000091001';
  v record;
  v_n integer;
begin
  -- Salva sem gerar documento, mantém texto alfanumérico/zeros e remove bordas.
  perform * from m.fn_orcamento_atualizar_status_com_pedido(
    public.current_tenant_id(),public.current_empresa_id(),v_id,'FECHADO',
    'Pedido recebido',100,false,false,null,null,'  PC-000123/26  ');
  select * into v from m.orcamento where id=v_id and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id();
  assert v.pedido_compra_cliente='PC-000123/26' and v.status='FECHADO' and v.os_id is null, 'Fechamento sem documento';

  -- Outros status não modificam o pedido.
  perform * from m.fn_orcamento_atualizar_status_com_pedido(
    public.current_tenant_id(),public.current_empresa_id(),v_id,'ANDAMENTO',
    'Nova negociação',null,false,false,null,null,'IGNORAR');
  assert (select pedido_compra_cliente='PC-000123/26' from m.orcamento where id=v_id and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id()), 'Preservação em andamento';

  for v_n in 91002..91003 loop
    v_id := ('00000000-0000-0000-0000-' || lpad(v_n::text,12,'0'))::uuid;
    perform * from m.fn_orcamento_atualizar_status_com_pedido(
      public.current_tenant_id(),public.current_empresa_id(),v_id,'FECHADO',
      'Pedido recebido',200,true,false,null,case when v_n=91002 then 'OS' else 'OV' end,'PC-001/26');
    assert (select pedido_compra='PC-001/26' from public.ordens_servico where id=v_n and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id()), 'Propagação para OS/OV';
    assert (select pedido_compra_cliente='PC-001/26' from m.orcamento where id=v_id and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id()), 'Persistência no orçamento';
    perform * from m.fn_orcamento_atualizar_status_com_pedido(
      public.current_tenant_id(),public.current_empresa_id(),v_id,'FECHADO',
      'Pedido mantido',200,true,false,null,case when v_n=91002 then 'OS' else 'OV' end,'  ');
    assert (select pedido_compra='PC-001/26' from public.ordens_servico where id=v_n and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id()), 'Vazio não apaga OC';
  end loop;

  -- Pedido salvo antes da geração acompanha documento vinculado posteriormente.
  update m.orcamento set pedido_compra_cliente='PC-ANTERIOR' where id=v_id and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id();
  update public.ordens_servico set pedido_compra=null where id=91003 and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id();
  perform * from m.fn_orcamento_atualizar_status_com_pedido(
    public.current_tenant_id(),public.current_empresa_id(),v_id,'FECHADO','Gerar depois',200,true,false,null,'OV',null);
  assert (select pedido_compra='PC-ANTERIOR' from public.ordens_servico where id=91003 and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id()), 'Reutiliza OC guardada';

  begin
    perform * from m.fn_orcamento_atualizar_status_com_pedido(gen_random_uuid(),public.current_empresa_id(),v_id,'FECHADO');
    raise exception 'TESTE: tenant divergente aceito';
  exception when raise_exception then
    if sqlerrm like 'TESTE:%' then raise; end if;
    assert sqlerrm like 'Contexto tenant/empresa divergente%';
  end;
  begin
    perform * from m.fn_orcamento_atualizar_status_com_pedido(public.current_tenant_id(),gen_random_uuid(),v_id,'FECHADO');
    raise exception 'TESTE: empresa divergente aceita';
  exception when raise_exception then
    if sqlerrm like 'TESTE:%' then raise; end if;
    assert sqlerrm like 'Contexto tenant/empresa divergente%';
  end;

  -- Falha ao propagar deve reverter também valor e status do orçamento.
  update public.ordens_servico set status='cancelada',status_fluxo='cancelada' where id=91003 and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id();
  begin
    perform * from m.fn_orcamento_atualizar_status_com_pedido(
      public.current_tenant_id(),public.current_empresa_id(),v_id,'FECHADO','Não deve gravar',777,false,false,null,null,'OUTRA-OC');
    raise exception 'TESTE: documento cancelado aceito';
  exception when raise_exception then
    if sqlerrm like 'TESTE:%' then raise; end if;
    assert sqlerrm like 'Não é possível alterar o pedido%';
  end;
  assert (select valor_fechado=200 and pedido_compra_cliente='PC-ANTERIOR' from m.orcamento where id=v_id and tenant_id=public.current_tenant_id() and empresa_id=public.current_empresa_id()), 'Rollback atômico';
  raise notice 'OK: sem documento, OS, OV, reaproveitamento, vazio, outros status, tenant, empresa e rollback.';
end $$;
rollback;
