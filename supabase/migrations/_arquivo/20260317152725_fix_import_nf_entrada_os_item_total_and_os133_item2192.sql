create or replace function public.import_nf_entrada(
  p_empresa_id uuid,
  p_finalidade_contexto item_finalidade,
  p_fornecedor_id bigint,
  p_itens_json jsonb,
  p_nf_json jsonb,
  p_tenant_id uuid,
  p_xml_raw text,
  p_gerar_contas_pagar boolean default false,
  p_parcelas_json jsonb default null::jsonb,
  p_os_id integer default null::integer,
  p_baixar_os boolean default false,
  p_motivo_compra_id uuid default null::uuid,
  p_solicitante_usuario_id uuid default null::uuid
)
returns table(status text, message text, nf_entrada_id bigint)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_nf_id bigint;
  v_chave text;
  v_emitente text;
  v_numero text;
  v_serie text;
  v_data_emissao timestamptz;
  v_total_nf numeric(14,2);

  v_it jsonb;

  v_item_id int;
  v_qtd numeric(14,3);
  v_vunit numeric(14,6);
  v_vtotal numeric(14,2);

  v_has_os boolean;

  v_solicitante_ok boolean;
  v_motivo_ok boolean;

  v_xml_trim text;

  v_allowed public.item_finalidade[];
  v_item_finalidade public.item_finalidade;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id obrigatorio';
  end if;

  perform set_config('app.tenant_id', p_tenant_id::text, true);

  if not exists (
    select 1
      from public.tenant_memberships tm
     where tm.user_id = auth.uid()
       and tm.tenant_id = p_tenant_id
       and tm.status in ('active','ativo')
  ) then
    raise exception 'Sem acesso ao tenant';
  end if;

  if p_empresa_id is null then
    raise exception 'empresa_id obrigatorio';
  end if;

  if not exists (
    select 1
      from public.empresa_memberships em
     where em.user_id = auth.uid()
       and em.tenant_id = p_tenant_id
       and em.empresa_id = p_empresa_id
       and em.status in ('active','ativo')
  ) then
    raise exception 'Sem acesso a empresa';
  end if;

  v_solicitante_ok := (p_solicitante_usuario_id is null)
    or exists (
      select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
       where u.id = p_solicitante_usuario_id
         and ut.tenant_id = p_tenant_id
         and ut.deleted_at is null
    );

  if not v_solicitante_ok then
    raise exception 'Solicitante invalido';
  end if;

  v_motivo_ok := (p_motivo_compra_id is null)
    or exists (
      select 1
        from f.motivo_compra mc
       where mc.id = p_motivo_compra_id
         and mc.tenant_id = p_tenant_id
         and mc.deleted_at is null
    );

  if not v_motivo_ok then
    raise exception 'Motivo_compra invalido';
  end if;

  v_chave := nullif(p_nf_json->>'chave','');
  v_emitente := coalesce(nullif(p_nf_json->>'emitente_nome',''), 'FORNECEDOR');
  v_numero := nullif(p_nf_json->>'numero','');
  v_serie := nullif(p_nf_json->>'serie','');
  v_data_emissao := nullif(p_nf_json->>'data_emissao','')::timestamptz;
  v_total_nf := coalesce((p_nf_json->>'valor_total')::numeric, 0);

  if v_chave is null then
    raise exception 'Chave obrigatoria';
  end if;

  select ne.id
    into v_nf_id
    from public.nf_entrada ne
   where ne.tenant_id = p_tenant_id
     and ne.empresa_id = p_empresa_id
     and ne.chave = v_chave
   limit 1;

  if v_nf_id is not null then
    update public.nf_entrada
       set motivo_compra_id = coalesce(motivo_compra_id, p_motivo_compra_id),
           solicitante_usuario_id = coalesce(solicitante_usuario_id, p_solicitante_usuario_id),
           gerar_contas_pagar = coalesce(gerar_contas_pagar, false) or coalesce(p_gerar_contas_pagar, false)
     where id = v_nf_id
       and tenant_id = p_tenant_id
       and empresa_id = p_empresa_id;

    status := 'error';
    message := 'NF ja importada';
    nf_entrada_id := null;
    return next;
    return;
  end if;

  v_has_os := (p_os_id is not null);

  insert into public.nf_entrada (
    chave,
    numero,
    serie,
    emitente_nome,
    emitente_cnpj,
    data_emissao,
    valor_produtos,
    valor_frete,
    valor_seguro,
    valor_desconto,
    valor_outros,
    valor_total,
    xml_raw,
    fornecedor_id,
    tenant_id,
    empresa_id,
    finalidade_contexto,
    os_id,
    baixa_os_automatica,
    motivo_compra_id,
    solicitante_usuario_id,
    gerar_contas_pagar
  )
  values (
    v_chave,
    v_numero,
    v_serie,
    v_emitente,
    p_nf_json->>'emitente_cnpj',
    v_data_emissao,
    coalesce((p_nf_json->>'valor_produtos')::numeric, 0),
    coalesce((p_nf_json->>'valor_frete')::numeric, 0),
    coalesce((p_nf_json->>'valor_seguro')::numeric, 0),
    coalesce((p_nf_json->>'valor_desconto')::numeric, 0),
    coalesce((p_nf_json->>'valor_outros')::numeric, 0),
    v_total_nf,
    p_xml_raw,
    p_fornecedor_id,
    p_tenant_id,
    p_empresa_id,
    p_finalidade_contexto,
    p_os_id,
    coalesce(p_baixar_os,false),
    p_motivo_compra_id,
    p_solicitante_usuario_id,
    coalesce(p_gerar_contas_pagar, false)
  )
  returning id into v_nf_id;

  for v_it in select * from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb))
  loop
    v_item_id := (v_it->>'item_id')::int;
    v_qtd := coalesce((v_it->>'quantidade')::numeric, (v_it->>'qtd')::numeric, 0);

    v_vunit := coalesce(
      nullif((v_it->>'valorUnit')::numeric, 0),
      nullif((v_it->>'v_unit')::numeric, 0),
      nullif((v_it->>'valor_unitario')::numeric, 0),
      0
    );

    v_vtotal := coalesce(
      nullif((v_it->>'total')::numeric, 0),
      nullif((v_it->>'v_prod')::numeric, 0),
      case when v_vunit > 0 and v_qtd > 0 then (v_vunit * v_qtd)::numeric(14,2) else 0 end
    );

    insert into public.nf_entrada_itens (
      tenant_id, empresa_id, nf_entrada_id, item_id,
      descricao, ncm, cfop,
      qtd, v_unit, v_prod,
      aliq_icms, v_icms, aliq_ipi, v_ipi, aliq_pis, v_pis, aliq_cofins, v_cofins
    )
    values (
      p_tenant_id, p_empresa_id, v_nf_id, v_item_id,
      v_it->>'descricao',
      v_it->>'ncm',
      v_it->>'cfop',
      v_qtd, v_vunit, v_vtotal,
      coalesce((v_it->>'aliq_icms')::numeric,0), coalesce((v_it->>'v_icms')::numeric,0),
      coalesce((v_it->>'aliq_ipi')::numeric,0),  coalesce((v_it->>'v_ipi')::numeric,0),
      coalesce((v_it->>'aliq_pis')::numeric,0),  coalesce((v_it->>'v_pis')::numeric,0),
      coalesce((v_it->>'aliq_cofins')::numeric,0), coalesce((v_it->>'v_cofins')::numeric,0)
    );
  end loop;

  v_xml_trim := nullif(btrim(coalesce(p_xml_raw,'')), '');
  if v_xml_trim is null then
    insert into public.xml_import_errors (tenant_id, documento_fiscal_id, tipo, detalhe, created_at, updated_at)
    values (p_tenant_id, null, 'NF_ENTRADA', 'Importado sem XML (xml_raw ausente).', now(), now())
    on conflict (tenant_id, documento_fiscal_id, tipo) do update
      set detalhe = excluded.detalhe,
          updated_at = now(),
          resolved_at = null;
  end if;

  if coalesce(p_gerar_contas_pagar, false) then
    if not (public.can('financeiro','write') or public.can('financeiro','config')) then
      raise exception 'Sem permissao para gerar contas a pagar';
    end if;
  end if;

  perform 1 from public.fn_fix_nf_entrada_pos_import(v_nf_id);

  if v_has_os then
    v_allowed := public.fn_importacao_xml__itens_vincular_finalidades(p_tenant_id, p_empresa_id);

    for v_it in select * from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb))
    loop
      v_item_id := (v_it->>'item_id')::int;
      v_qtd := coalesce((v_it->>'quantidade')::numeric, (v_it->>'qtd')::numeric, 0);

      if v_item_id is null or v_item_id <= 0 then
        continue;
      end if;

      if v_qtd <= 0 then
        continue;
      end if;

      select i.finalidade
        into v_item_finalidade
        from public.itens i
       where i.id = v_item_id
         and i.tenant_id = p_tenant_id
         and i.empresa_id = p_empresa_id
         and coalesce(i.ativo, true) = true;

      if v_item_finalidade is null then
        continue;
      end if;

      if not (v_item_finalidade = any(v_allowed)) then
        continue;
      end if;

      v_vunit := coalesce(
        nullif((v_it->>'valorUnit')::numeric, 0),
        nullif((v_it->>'v_unit')::numeric, 0),
        nullif((v_it->>'valor_unitario')::numeric, 0),
        0
      );

      v_vtotal := coalesce(
        nullif((v_it->>'total')::numeric, 0),
        nullif((v_it->>'v_prod')::numeric, 0),
        case when v_vunit > 0 and v_qtd > 0 then (v_vunit * v_qtd)::numeric(14,2) else 0 end
      );

      with upd as (
        update public.os_itens oi
           set quantidade = oi.quantidade + v_qtd,
               valor_unitario = case when coalesce(oi.valor_unitario, 0) = 0 then v_vunit else oi.valor_unitario end,
               valor_total = coalesce(oi.valor_total, 0) + v_vtotal
         where oi.tenant_id = p_tenant_id
           and oi.empresa_id = p_empresa_id
           and oi.os_id = p_os_id
           and oi.item_id = v_item_id
           and coalesce(upper(oi.observacoes), '') not like 'IMPORT XML NF %'
           and coalesce(upper(oi.observacoes), '') not like 'IMPORTACAO XML NF %'
         returning oi.id
      )
      insert into public.os_itens (
        os_id,
        item_id,
        quantidade,
        valor_unitario,
        valor_total,
        tenant_id,
        empresa_id,
        criado_em
      )
      select
        p_os_id,
        v_item_id,
        v_qtd,
        v_vunit,
        v_vtotal,
        p_tenant_id,
        p_empresa_id,
        now()
      where not exists (select 1 from upd);

      if coalesce(p_baixar_os,false) then
        perform public.baixar_item_os(
          v_item_id,
          v_qtd,
          ('NF-e ' || v_chave),
          'sistema',
          now(),
          v_nf_id,
          p_os_id,
          p_tenant_id,
          p_empresa_id
        );
      end if;
    end loop;
  end if;

  status := 'ok';
  message := 'Importado com sucesso';
  nf_entrada_id := v_nf_id;
  return next;
end;
$$;

do $$
declare
  v_qtd numeric(14,3);
  v_vunit numeric(14,6);
  v_vtotal numeric(14,2);
begin
  select
    coalesce(sum(ni.qtd), 0),
    max(ni.v_unit),
    coalesce(sum(ni.v_prod), 0)
  into v_qtd, v_vunit, v_vtotal
  from public.nf_entrada_itens ni
  where ni.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and ni.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
    and ni.nf_entrada_id = 978
    and ni.item_id = 2192;

  if coalesce(v_qtd, 0) <= 0 then
    return;
  end if;

  update public.os_itens oi
     set quantidade = v_qtd,
         valor_unitario = coalesce(nullif(v_vunit, 0), oi.valor_unitario),
         valor_total = v_vtotal
   where oi.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
     and oi.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
     and oi.os_id = 133
     and oi.item_id = 2192
     and oi.observacoes = 'IMPORT XML NF 42260327502984000165550010000043251953876650 NF_ITEM 3058';

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
