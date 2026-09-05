begin;

alter table f.operacao_fiscal enable row level security;
alter table f.operacao_fiscal_item enable row level security;
alter table f.remessa_prazo_config enable row level security;
alter table f.remessa_controle enable row level security;

create policy operacao_fiscal_all on f.operacao_fiscal for all to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access())
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access());
create policy operacao_fiscal_item_all on f.operacao_fiscal_item for all to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access())
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access());
create policy remessa_prazo_config_all on f.remessa_prazo_config for all to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access())
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access());
create policy remessa_controle_all on f.remessa_controle for all to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access())
  with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access());

grant select, insert, update, delete on f.operacao_fiscal, f.operacao_fiscal_item,
  f.remessa_prazo_config, f.remessa_controle to authenticated, service_role;

create or replace function f.fn_devolucao_compra_criar(p_nf_entrada_id bigint, p_itens jsonb)
returns uuid language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare
  v_scope record; v_preparo jsonb; v_operacao uuid := gen_random_uuid(); v_req jsonb; v_src jsonb;
  v_qtd numeric; v_original numeric; v_usada numeric; v_ratio numeric; v_cfop text;
  v_primeiro_cfop text; v_cfop_unico boolean := true; v_ordem integer := 0;
  v_nf_entrada_item_id bigint; v_item_id integer;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Selecione ao menos um item para devolver.';
  end if;
  v_preparo := f.fn_devolucao_compra_preparar(p_nf_entrada_id);
  insert into f.operacao_fiscal (
    id, tenant_id, empresa_id, tipo, status, nf_entrada_origem_id, nfe_referenciada,
    cfop_confirmado_em, cfop_confirmado_por, criado_por, dados_json
  ) values (
    v_operacao, v_scope.tenant_id, v_scope.empresa_id, 'DEVOLUCAO_COMPRA', 'PRONTO_HOMOLOGACAO',
    p_nf_entrada_id, v_preparo->>'chave', now(), v_scope.usuario_id, v_scope.usuario_id,
    jsonb_build_object('origem_xml_validada', true)
  );

  for v_req in select value from jsonb_array_elements(p_itens) loop
    v_ordem := v_ordem + 1;
    select value into v_src from jsonb_array_elements(v_preparo->'itens')
      where (value->>'nitem')::integer = (v_req->>'nitem')::integer;
    if v_src is null then raise exception 'Item nItem % nao existe no XML original.', v_req->>'nitem'; end if;
    v_qtd := nullif(v_req->>'quantidade', '')::numeric;
    v_original := (v_src->>'quantidade_original')::numeric;
    if v_qtd is null or v_qtd <= 0 or v_qtd > v_original then
      raise exception 'Quantidade divergente no item %: devolucao %; XML original %.', v_req->>'nitem', v_qtd, v_original;
    end if;
    select coalesce(sum(oi.quantidade), 0) into v_usada
      from f.operacao_fiscal_item oi join f.operacao_fiscal op on op.id = oi.operacao_id
     where op.tenant_id = v_scope.tenant_id and op.empresa_id = v_scope.empresa_id
       and op.tipo = 'DEVOLUCAO_COMPRA' and op.nf_entrada_origem_id = p_nf_entrada_id
       and op.status <> 'CANCELADA' and oi.origem_nitem = (v_req->>'nitem')::integer;
    if v_usada + v_qtd > v_original then
      raise exception 'Quantidade acumulada excede o XML no item %: original %, ja devolvida %, solicitada %.',
        v_req->>'nitem', v_original, v_usada, v_qtd;
    end if;
    v_cfop := btrim(v_req->>'cfop_confirmado');
    if v_cfop not in ('5201', '6201', '5553', '6556') then
      raise exception 'CFOP % nao e uma opcao observada para devolucao de compra; confirme 5201, 6201, 5553 ou 6556.', coalesce(v_cfop, '<vazio>');
    end if;
    if v_req ? 'cst_icms' and coalesce(v_req->>'cst_icms', '') <> coalesce(v_src->>'cst_icms', '') then
      raise exception 'CST ICMS divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'cst_icms', v_src->>'cst_icms';
    end if;
    if v_req ? 'csosn' and coalesce(v_req->>'csosn', '') <> coalesce(v_src->>'csosn', '') then
      raise exception 'CSOSN divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'csosn', v_src->>'csosn';
    end if;
    if v_req ? 'cst_ipi' and coalesce(v_req->>'cst_ipi', '') <> coalesce(v_src->>'cst_ipi', '') then
      raise exception 'CST IPI divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'cst_ipi', v_src->>'cst_ipi';
    end if;
    if v_req ? 'cst_pis' and coalesce(v_req->>'cst_pis', '') <> coalesce(v_src->>'cst_pis', '') then
      raise exception 'CST PIS divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'cst_pis', v_src->>'cst_pis';
    end if;
    if v_req ? 'cst_cofins' and coalesce(v_req->>'cst_cofins', '') <> coalesce(v_src->>'cst_cofins', '') then
      raise exception 'CST COFINS divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'cst_cofins', v_src->>'cst_cofins';
    end if;
    if v_req ? 'aliquota_icms' and abs((v_req->>'aliquota_icms')::numeric - coalesce((v_src->>'aliquota_icms')::numeric, 0)) > 0.0001 then
      raise exception 'Aliquota ICMS divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'aliquota_icms', v_src->>'aliquota_icms';
    end if;
    if v_req ? 'aliquota_ipi' and abs((v_req->>'aliquota_ipi')::numeric - coalesce((v_src->>'aliquota_ipi')::numeric, 0)) > 0.0001 then
      raise exception 'Aliquota IPI divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'aliquota_ipi', v_src->>'aliquota_ipi';
    end if;
    if v_req ? 'aliquota_pis' and abs((v_req->>'aliquota_pis')::numeric - coalesce((v_src->>'aliquota_pis')::numeric, 0)) > 0.0001 then
      raise exception 'Aliquota PIS divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'aliquota_pis', v_src->>'aliquota_pis';
    end if;
    if v_req ? 'aliquota_cofins' and abs((v_req->>'aliquota_cofins')::numeric - coalesce((v_src->>'aliquota_cofins')::numeric, 0)) > 0.0001 then
      raise exception 'Aliquota COFINS divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'aliquota_cofins', v_src->>'aliquota_cofins';
    end if;
    if v_req ? 'valor_unitario' and abs((v_req->>'valor_unitario')::numeric - (v_src->>'valor_unitario')::numeric) > 0.000001 then
      raise exception 'Valor unitario divergente no item %: informado %, XML %.', v_req->>'nitem', v_req->>'valor_unitario', v_src->>'valor_unitario';
    end if;
    if v_req ? 'valor_icms' and abs((v_req->>'valor_icms')::numeric - round(coalesce((v_src->>'valor_icms')::numeric,0)*(v_qtd/v_original),2)) > 0.01 then
      raise exception 'Valor ICMS divergente no item %: informado %, XML proporcional %.', v_req->>'nitem', v_req->>'valor_icms', round(coalesce((v_src->>'valor_icms')::numeric,0)*(v_qtd/v_original),2);
    end if;
    if v_req ? 'valor_ipi' and abs((v_req->>'valor_ipi')::numeric - round(coalesce((v_src->>'valor_ipi')::numeric,0)*(v_qtd/v_original),2)) > 0.01 then
      raise exception 'Valor IPI divergente no item %: informado %, XML proporcional %.', v_req->>'nitem', v_req->>'valor_ipi', round(coalesce((v_src->>'valor_ipi')::numeric,0)*(v_qtd/v_original),2);
    end if;
    if v_req ? 'valor_pis' and abs((v_req->>'valor_pis')::numeric - round(coalesce((v_src->>'valor_pis')::numeric,0)*(v_qtd/v_original),2)) > 0.01 then
      raise exception 'Valor PIS divergente no item %: informado %, XML proporcional %.', v_req->>'nitem', v_req->>'valor_pis', round(coalesce((v_src->>'valor_pis')::numeric,0)*(v_qtd/v_original),2);
    end if;
    if v_req ? 'valor_cofins' and abs((v_req->>'valor_cofins')::numeric - round(coalesce((v_src->>'valor_cofins')::numeric,0)*(v_qtd/v_original),2)) > 0.01 then
      raise exception 'Valor COFINS divergente no item %: informado %, XML proporcional %.', v_req->>'nitem', v_req->>'valor_cofins', round(coalesce((v_src->>'valor_cofins')::numeric,0)*(v_qtd/v_original),2);
    end if;
    v_nf_entrada_item_id := null;
    v_item_id := null;
    select ni.id, ni.item_id into v_nf_entrada_item_id, v_item_id from public.nf_entrada_itens ni
     where ni.tenant_id = v_scope.tenant_id and ni.empresa_id = v_scope.empresa_id
       and ni.nf_entrada_id = p_nf_entrada_id and ni.codigo_fornecedor = v_src->>'codigo'
     order by ni.id limit 1;
    v_ratio := v_qtd / v_original;
    insert into f.operacao_fiscal_item (
      operacao_id, tenant_id, empresa_id, ordem, origem_nitem, nf_entrada_item_id, item_id,
      codigo, descricao, ncm, unidade, quantidade_original, quantidade, valor_unitario, valor_total,
      cfop_original, cfop_proposto, cfop_confirmado, origem_mercadoria,
      cst_icms, csosn, cst_ipi, cst_pis, cst_cofins, cbenef, reducao_base_icms_percentual, unidade_tributavel,
      base_icms, base_ipi, base_pis, base_cofins, aliquota_icms, aliquota_ipi, aliquota_pis, aliquota_cofins,
      valor_icms, valor_ipi, valor_pis, valor_cofins, xml_validado
    ) values (
      v_operacao, v_scope.tenant_id, v_scope.empresa_id, v_ordem, (v_src->>'nitem')::integer,
      v_nf_entrada_item_id, v_item_id, v_src->>'codigo', v_src->>'descricao', v_src->>'ncm', v_src->>'unidade',
      v_original, v_qtd, (v_src->>'valor_unitario')::numeric, round((v_src->>'valor_total')::numeric * v_ratio, 2),
      v_src->>'cfop_original', v_src->>'cfop_proposto', v_cfop, nullif(v_src->>'origem', '')::smallint,
      v_src->>'cst_icms', v_src->>'csosn', v_src->>'cst_ipi', v_src->>'cst_pis', v_src->>'cst_cofins',
      v_src->>'cbenef', nullif(v_src->>'reducao_base_icms_percentual','')::numeric, v_src->>'unidade_tributavel',
      round(coalesce((v_src->>'base_icms')::numeric,0)*v_ratio,2), round(coalesce((v_src->>'base_ipi')::numeric,0)*v_ratio,2),
      round(coalesce((v_src->>'base_pis')::numeric,0)*v_ratio,2), round(coalesce((v_src->>'base_cofins')::numeric,0)*v_ratio,2),
      nullif(v_src->>'aliquota_icms','')::numeric, nullif(v_src->>'aliquota_ipi','')::numeric,
      nullif(v_src->>'aliquota_pis','')::numeric, nullif(v_src->>'aliquota_cofins','')::numeric,
      round(coalesce((v_src->>'valor_icms')::numeric,0)*v_ratio,2), round(coalesce((v_src->>'valor_ipi')::numeric,0)*v_ratio,2),
      round(coalesce((v_src->>'valor_pis')::numeric,0)*v_ratio,2), round(coalesce((v_src->>'valor_cofins')::numeric,0)*v_ratio,2), true
    );
    if v_primeiro_cfop is null then v_primeiro_cfop := v_cfop; elsif v_primeiro_cfop <> v_cfop then v_cfop_unico := false; end if;
  end loop;
  update f.operacao_fiscal op set
    cfop_proposto = case when v_cfop_unico then (select min(i.cfop_proposto) from f.operacao_fiscal_item i where i.operacao_id=v_operacao) end,
    cfop_confirmado = case when v_cfop_unico then v_primeiro_cfop end,
    valor_total = (select coalesce(sum(i.valor_total+i.valor_ipi),0) from f.operacao_fiscal_item i where i.operacao_id=v_operacao),
    preparado_homologacao_em = now(), updated_at = now()
  where op.id = v_operacao;
  return v_operacao;
end;
$function$;

create or replace function f.fn_venda_ordem_criar(p_ov_id integer, p_entrega jsonb)
returns uuid language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record; v_ov record; v_id uuid := gen_random_uuid(); v_campo text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select os.* into v_ov from public.ordens_servico os where os.tenant_id=v_scope.tenant_id and os.empresa_id=v_scope.empresa_id and os.id=p_ov_id and os.tipo_documento='OV';
  if v_ov.id is null then raise exception 'OV nao encontrada nesta empresa.'; end if;
  foreach v_campo in array array['cnpj','nome','logradouro','numero','bairro','municipio','uf','cep','codigo_municipio'] loop
    if nullif(btrim(p_entrega->>v_campo),'') is null then raise exception 'Entrega alternativa incompleta: campo %.', v_campo; end if;
  end loop;
  if regexp_replace(p_entrega->>'cnpj','\D','','g') !~ '^[0-9]{14}$' then raise exception 'Entrega alternativa: CNPJ deve ter 14 digitos.'; end if;
  insert into f.operacao_fiscal (id,tenant_id,empresa_id,tipo,status,ov_origem_id,destinatario_id,entrega_json,
    cfop_proposto,cfop_confirmado,cfop_segunda_nota,cfop_confirmado_em,cfop_confirmado_por,criado_por,dados_json)
  values (v_id,v_scope.tenant_id,v_scope.empresa_id,'VENDA_ORDEM','AGUARDANDO_PRIMEIRA',p_ov_id,v_ov.cliente_id,p_entrega,
    '6119','6119','6923',now(),v_scope.usuario_id,v_scope.usuario_id,jsonb_build_object('ordem_emissao',array['6119','6923']));
  insert into f.operacao_fiscal_item (operacao_id,tenant_id,empresa_id,ordem,item_id,codigo,descricao,ncm,unidade,
    quantidade_original,quantidade,valor_unitario,valor_total,cfop_original,cfop_proposto,cfop_confirmado,
    origem_mercadoria,unidade_tributavel,xml_validado)
  select v_id,v_scope.tenant_id,v_scope.empresa_id,row_number() over(order by oi.id),oi.item_id,i.codigo_interno,i.nome,fi.ncm,i.unidade_medida,
    oi.quantidade,oi.quantidade,oi.valor_unitario,oi.valor_total,null,'6119','6119',fi.origem,fi.unidade_tributavel,false
  from public.os_itens oi join public.itens i on i.id=oi.item_id
  left join public.fiscal_itens fi on fi.tenant_id=oi.tenant_id and fi.empresa_id=oi.empresa_id and fi.item_id=oi.item_id
  where oi.tenant_id=v_scope.tenant_id and oi.empresa_id=v_scope.empresa_id and oi.os_id=p_ov_id and coalesce(oi.finalidade,'venda')='venda';
  if not found then raise exception 'OV sem itens de venda.'; end if;
  update f.operacao_fiscal set valor_total=(select sum(valor_total) from f.operacao_fiscal_item where operacao_id=v_id), preparado_homologacao_em=now() where id=v_id;
  return v_id;
end;
$function$;

create or replace function f.fn_remessa_criar(p_finalidade text, p_cfop_confirmado text, p_destinatario jsonb, p_itens jsonb, p_justificativa text default null)
returns uuid language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record; v_id uuid:=gen_random_uuid(); v_item jsonb; v_ordem int:=0; v_allowed text[];
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  v_allowed := case p_finalidade when 'INDUSTRIALIZACAO' then array['5901'] when 'CONSERTO' then array['5915','6915']
    when 'SIMPLES' then array['5949','6949'] when 'CONTA_ORDEM' then array['6923'] else null end;
  if v_allowed is null or not (p_cfop_confirmado=any(v_allowed)) then raise exception 'CFOP % incompativel com a finalidade %.',p_cfop_confirmado,p_finalidade; end if;
  if nullif(btrim(p_destinatario->>'nome'),'') is null or nullif(regexp_replace(p_destinatario->>'documento','\D','','g'),'') is null then
    raise exception 'Destinatario da remessa exige nome e documento.';
  end if;
  if jsonb_typeof(p_itens)<>'array' or jsonb_array_length(p_itens)=0 then raise exception 'Remessa exige ao menos um item.'; end if;
  insert into f.operacao_fiscal(id,tenant_id,empresa_id,tipo,finalidade,status,cfop_proposto,cfop_confirmado,
    cfop_confirmado_em,cfop_confirmado_por,entrega_json,justificativa_fisco,criado_por,preparado_homologacao_em)
  values(v_id,v_scope.tenant_id,v_scope.empresa_id,'REMESSA',p_finalidade,'PRONTO_HOMOLOGACAO',p_cfop_confirmado,p_cfop_confirmado,
    now(),v_scope.usuario_id,p_destinatario,p_justificativa,v_scope.usuario_id,now());
  for v_item in select value from jsonb_array_elements(p_itens) loop
    v_ordem:=v_ordem+1;
    insert into f.operacao_fiscal_item(operacao_id,tenant_id,empresa_id,ordem,item_id,codigo,descricao,ncm,unidade,
      quantidade_original,quantidade,valor_unitario,valor_total,cfop_proposto,cfop_confirmado,xml_validado)
    values(v_id,v_scope.tenant_id,v_scope.empresa_id,v_ordem,nullif(v_item->>'item_id','')::integer,v_item->>'codigo',
      coalesce(nullif(v_item->>'descricao',''),'ITEM DA REMESSA'),v_item->>'ncm',coalesce(v_item->>'unidade','UN'),
      (v_item->>'quantidade')::numeric,(v_item->>'quantidade')::numeric,coalesce(nullif(v_item->>'valor_unitario','')::numeric,0),
      round((v_item->>'quantidade')::numeric*coalesce(nullif(v_item->>'valor_unitario','')::numeric,0),2),p_cfop_confirmado,p_cfop_confirmado,false);
  end loop;
  update f.operacao_fiscal set valor_total=(select sum(valor_total) from f.operacao_fiscal_item where operacao_id=v_id) where id=v_id;
  return v_id;
end;
$function$;

create or replace function f.fn_estorno_criar(p_documento_original_id uuid, p_cfop_confirmado text, p_justificativa text)
returns uuid language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record; v_doc f.documento_fiscal%rowtype; v_id uuid:=gen_random_uuid(); v_proposto text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_doc from f.documento_fiscal d where d.tenant_id=v_scope.tenant_id and d.empresa_id=v_scope.empresa_id and d.id=p_documento_original_id and d.deleted_at is null;
  if v_doc.id is null then raise exception 'NF-e original nao encontrada nesta empresa.'; end if;
  if v_doc.chave_acesso !~ '^[0-9]{44}$' then raise exception 'Estorno bloqueado: NF-e original sem chave de 44 digitos.'; end if;
  if length(btrim(coalesce(p_justificativa,'')))<15 then raise exception 'Justificativa ao fisco deve ter ao menos 15 caracteres.'; end if;
  if p_cfop_confirmado not in ('1102','1201','1202','1915','2202') then raise exception 'CFOP de estorno fora das combinacoes observadas.'; end if;
  select case when count(distinct f.fn_cfop_estorno_proposto(i.cfop))=1 then min(f.fn_cfop_estorno_proposto(i.cfop)) end
    into v_proposto from f.documento_fiscal_item i where i.tenant_id=v_scope.tenant_id and i.empresa_id=v_scope.empresa_id and i.documento_fiscal_id=v_doc.id and i.deleted_at is null;
  insert into f.operacao_fiscal(id,tenant_id,empresa_id,tipo,status,documento_origem_id,nfe_referenciada,finalidade_emissao,
    cfop_proposto,cfop_confirmado,cfop_confirmado_em,cfop_confirmado_por,justificativa_fisco,informacoes_complementares,
    valor_total,dados_json,criado_por,preparado_homologacao_em)
  values(v_id,v_scope.tenant_id,v_scope.empresa_id,'ESTORNO','PRONTO_HOMOLOGACAO',v_doc.id,v_doc.chave_acesso,3,
    v_proposto,p_cfop_confirmado,now(),v_scope.usuario_id,p_justificativa,
    '999 - ESTORNO DE NF-E NAO CANCELADA NO PRAZO LEGAL. CHAVE REFERENCIADA: '||v_doc.chave_acesso,v_doc.valor_total,
    jsonb_build_object(
      'snapshot_documento_original', jsonb_build_object(
        'valor_total',v_doc.valor_total,'valor_produtos',v_doc.valor_produtos,'valor_frete',v_doc.valor_frete,
        'valor_desconto',v_doc.valor_desconto,'valor_outros',v_doc.valor_outros,'valor_seguro',v_doc.valor_seguro
      ),
      'snapshot_impostos', coalesce((
        select jsonb_agg(jsonb_build_object(
          'imposto',di.imposto,'natureza',di.natureza,'base_original',di.base_original,'deducoes',di.deducoes,
          'base_calculo',di.base_calculo,'aliquota',di.aliquota,'valor_calculado',di.valor_calculado,'valor_ajustado',di.valor_ajustado
        ) order by di.imposto,di.natureza)
        from f.documento_fiscal_imposto di
        where di.tenant_id=v_scope.tenant_id and di.documento_fiscal_id=v_doc.id and di.deleted_at is null
      ),'[]'::jsonb)
    ),v_scope.usuario_id,now());
  insert into f.operacao_fiscal_item(operacao_id,tenant_id,empresa_id,ordem,item_id,codigo,descricao,ncm,unidade,
    quantidade_original,quantidade,valor_unitario,valor_total,cfop_original,cfop_proposto,cfop_confirmado,
    cst_icms,csosn,cst_ipi,cst_pis,cst_cofins,cbenef,reducao_base_icms_percentual,unidade_tributavel,
    cst_ibs_cbs,cclass_trib,cclass_trib_versao,ibs_cbs_json,xml_validado)
  select v_id,v_scope.tenant_id,v_scope.empresa_id,i.item_n,i.item_id,i.codigo,i.descricao,i.ncm,i.unidade,
    i.quantidade,i.quantidade,i.valor_unitario,i.valor_total,i.cfop,f.fn_cfop_estorno_proposto(i.cfop),p_cfop_confirmado,
    i.cst_icms,i.csosn,i.cst_ipi,i.cst_pis,i.cst_cofins,i.cbenef,i.reducao_base_icms_percentual,i.unidade_tributavel,
    i.cst_ibs_cbs,i.cclass_trib,i.cclass_trib_versao,i.ibs_cbs_json,true
  from f.documento_fiscal_item i where i.tenant_id=v_scope.tenant_id and i.empresa_id=v_scope.empresa_id and i.documento_fiscal_id=v_doc.id and i.deleted_at is null;
  if not found then raise exception 'Estorno bloqueado: NF-e original sem snapshot de itens.'; end if;
  return v_id;
end;
$function$;

commit;
