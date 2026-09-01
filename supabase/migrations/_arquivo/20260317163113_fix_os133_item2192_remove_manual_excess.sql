do $$
begin
  delete from public.os_itens oi
   where oi.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
     and oi.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
     and oi.os_id = 133
     and oi.item_id = 2192
     and oi.id in (1235, 1236);

  update public.ordens_servico os
     set valor_total = coalesce((
           select sum(oi.valor_total)
             from public.os_itens oi
            where oi.tenant_id = os.tenant_id
              and oi.empresa_id = os.empresa_id
              and oi.os_id = os.id
         ), 0),
         atualizado_em = now()
   where os.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
     and os.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
     and os.id = 133;
end;
$$;
