-- Consolida fornecedores Siemens no CNPJ alvo e prepara cadastros legados para reuso.
do $$
declare
  v_target_tenant uuid;
  v_target_empresa uuid;
  v_target_fornecedor_id integer;
  v_itens_movidos integer := 0;
  v_fornecedores_renomeados integer := 0;
begin
  select f.tenant_id, f.empresa_id, f.id
    into v_target_tenant, v_target_empresa, v_target_fornecedor_id
  from public.fornecedores f
  where (
          f.cnpj_digits = '34776007000898'
          or f.cnpj_norm = '34776007000898'
          or f.doc_digits = '34776007000898'
          or f.documento_norm = '34776007000898'
          or regexp_replace(coalesce(f.cnpj, ''), '\D', '', 'g') = '34776007000898'
          or regexp_replace(coalesce(f.doc, ''), '\D', '', 'g') = '34776007000898'
          or regexp_replace(coalesce(f.documento, ''), '\D', '', 'g') = '34776007000898'
        )
  order by f.id
  limit 1;

  if v_target_fornecedor_id is null then
    raise exception 'Fornecedor alvo com CNPJ 34.776.007/0008-98 nao encontrado.';
  end if;

  update public.itens i
     set fornecedor_id = v_target_fornecedor_id
   where i.tenant_id = v_target_tenant
     and i.empresa_id = v_target_empresa
     and i.fornecedor_id in (
       select f.id
       from public.fornecedores f
       where f.tenant_id = v_target_tenant
         and f.empresa_id = v_target_empresa
         and upper(f.nome) like '%SIEMENS%'
         and f.id <> v_target_fornecedor_id
     );
  get diagnostics v_itens_movidos = row_count;

  update public.fornecedores f
     set nome = 'USAR',
         atualizado_em = now()
   where f.tenant_id = v_target_tenant
     and f.empresa_id = v_target_empresa
     and upper(f.nome) like '%SIEMENS%'
     and f.id <> v_target_fornecedor_id;
  get diagnostics v_fornecedores_renomeados = row_count;

  raise notice 'Consolidacao Siemens concluida. Itens movidos: %, fornecedores renomeados: %.',
    v_itens_movidos, v_fornecedores_renomeados;
end
$$;
