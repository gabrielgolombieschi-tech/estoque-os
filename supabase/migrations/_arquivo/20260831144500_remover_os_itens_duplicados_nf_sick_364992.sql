-- Remove somente as linhas auxiliares sem baixa criadas ao vincular diretamente
-- a NF 364992 a OS 282. Os oito itens manuais baixados permanecem intactos.

do $$
declare
  v_tenant_id constant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa_id constant uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_nf_entrada_id constant bigint := 2221;
  v_os_id constant integer := 281;
  v_count integer;
begin
  select count(*)
    into v_count
  from public.os_itens oi
  where oi.tenant_id = v_tenant_id
    and oi.empresa_id = v_empresa_id
    and oi.os_id = v_os_id
    and oi.id between 6324 and 6331
    and coalesce(oi.baixa_estoque, false) = false
    and coalesce(oi.quantidade_baixada, 0) = 0
    and oi.observacoes like 'IMPORT XML NF 35260800769222000335550020003649921439857551 NF_ITEM %';

  if v_count <> 8 then
    raise exception 'As oito linhas auxiliares da NF SICK nao estao no estado esperado.';
  end if;

  -- No fluxo por pedido, a OS pertence aos itens do pedido e nao ao campo direto
  -- da NF. A aprovacao financeira ja permanece vinculada a OS 282.
  update public.nf_entrada
     set os_id = null,
         baixa_os_automatica = true,
         updated_at = now()
   where id = v_nf_entrada_id
     and tenant_id = v_tenant_id
     and empresa_id = v_empresa_id
     and os_id = v_os_id
     and deleted_at is null;
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'NF SICK 364992 nao estava vinculada diretamente a OS esperada.';
  end if;

  delete from public.os_itens oi
   where oi.tenant_id = v_tenant_id
     and oi.empresa_id = v_empresa_id
     and oi.os_id = v_os_id
     and oi.id between 6324 and 6331
     and coalesce(oi.baixa_estoque, false) = false
     and coalesce(oi.quantidade_baixada, 0) = 0
     and oi.observacoes like 'IMPORT XML NF 35260800769222000335550020003649921439857551 NF_ITEM %';
  get diagnostics v_count = row_count;
  if v_count <> 8 then
    raise exception 'Nao foi possivel remover exatamente as oito linhas auxiliares.';
  end if;
end;
$$;
