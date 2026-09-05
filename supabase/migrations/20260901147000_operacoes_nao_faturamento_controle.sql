begin;

create or replace function f.fn_operacao_validar_homologacao(p_operacao_id uuid, p_etapa smallint default 1)
returns jsonb language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record; v_op f.operacao_fiscal%rowtype; v_itens int; v_pendentes int;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_op from f.operacao_fiscal o where o.tenant_id=v_scope.tenant_id and o.empresa_id=v_scope.empresa_id and o.id=p_operacao_id and o.deleted_at is null;
  if v_op.id is null then raise exception 'Operacao fiscal nao encontrada.'; end if;
  if v_op.ambiente <> 'HOMOLOGACAO' then raise exception 'Somente HOMOLOGACAO esta liberada.'; end if;
  select count(*),count(*) filter(where cfop_confirmado is null or cfop_confirmado !~ '^[0-9]{4}$') into v_itens,v_pendentes
    from f.operacao_fiscal_item where tenant_id=v_scope.tenant_id and empresa_id=v_scope.empresa_id and operacao_id=v_op.id;
  if v_itens=0 or v_pendentes>0 then raise exception 'Operacao sem itens ou com CFOP nao confirmado.'; end if;
  if v_op.tipo='DEVOLUCAO_COMPRA' then
    if v_op.nfe_referenciada is null or exists(select 1 from f.operacao_fiscal_item where operacao_id=v_op.id and not xml_validado) then
      raise exception 'Devolucao exige chave da entrada e todos os itens validados contra o XML.';
    end if;
  elsif v_op.tipo='VENDA_ORDEM' and p_etapa=2 then
    if v_op.chave_primeira_nota is null then raise exception 'Segunda NF-e bloqueada: a primeira ainda nao possui chave autorizada.'; end if;
    if v_op.entrega_json is null then raise exception 'Segunda NF-e bloqueada: endereco de entrega alternativo ausente.'; end if;
  elsif v_op.tipo='RETORNO' and v_op.nfe_referenciada is null then
    raise exception 'Retorno bloqueado: chave da remessa original ausente.';
  elsif v_op.tipo='ESTORNO' then
    if v_op.nfe_referenciada is null or v_op.finalidade_emissao<>3 or nullif(btrim(v_op.justificativa_fisco),'') is null then
      raise exception 'Estorno exige chave original, finalidade 3 e justificativa ao fisco.';
    end if;
  end if;
  return jsonb_build_object('operacao_id',v_op.id,'tipo',v_op.tipo,'etapa',p_etapa,'ambiente','HOMOLOGACAO','valida',true,
    'nfe_referenciada',case when v_op.tipo='VENDA_ORDEM' and p_etapa=2 then v_op.chave_primeira_nota else v_op.nfe_referenciada end);
end;
$function$;

create or replace function f.fn_operacao_registrar_chave(p_operacao_id uuid, p_etapa smallint, p_chave text)
returns jsonb language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record; v_op f.operacao_fiscal%rowtype; v_pai f.remessa_controle%rowtype;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if p_chave !~ '^[0-9]{44}$' then raise exception 'Chave autorizada deve conter 44 digitos.'; end if;
  perform f.fn_operacao_validar_homologacao(p_operacao_id,p_etapa);
  select * into v_op from f.operacao_fiscal where tenant_id=v_scope.tenant_id and empresa_id=v_scope.empresa_id and id=p_operacao_id for update;
  if v_op.tipo='VENDA_ORDEM' then
    if p_etapa=1 then
      update f.operacao_fiscal set chave_primeira_nota=p_chave,status='AGUARDANDO_SEGUNDA',updated_at=now(),
        informacoes_complementares='REMESSA POR CONTA E ORDEM REFERENTE A NF-E '||p_chave
      where id=v_op.id;
    elsif p_etapa=2 then
      if v_op.chave_primeira_nota is null then raise exception 'Segunda NF-e bloqueada sem chave da primeira.'; end if;
      update f.operacao_fiscal set chave_segunda_nota=p_chave,nfe_referenciada=v_op.chave_primeira_nota,status='CONCLUIDA',updated_at=now() where id=v_op.id;
    else raise exception 'Venda a ordem aceita somente etapa 1 ou 2.';
    end if;
  elsif v_op.tipo='REMESSA' then
    insert into f.remessa_controle(tenant_id,empresa_id,operacao_remessa_id,finalidade,chave_remessa,
      destinatario_documento,destinatario_nome,remessa_em)
    values(v_scope.tenant_id,v_scope.empresa_id,v_op.id,v_op.finalidade,p_chave,
      regexp_replace(coalesce(v_op.entrega_json->>'documento',v_op.entrega_json->>'cnpj',''),'\D','','g'),
      coalesce(v_op.entrega_json->>'nome','DESTINATARIO'),current_date);
    update f.operacao_fiscal set chave_primeira_nota=p_chave,status='AGUARDANDO_RETORNO',updated_at=now() where id=v_op.id;
  elsif v_op.tipo='RETORNO' then
    select * into v_pai from f.remessa_controle where tenant_id=v_scope.tenant_id and empresa_id=v_scope.empresa_id
      and operacao_retorno_id=v_op.id and status='ABERTA' for update;
    if v_pai.id is null then raise exception 'Controle de remessa aberto nao encontrado para este retorno.'; end if;
    update f.remessa_controle set chave_retorno=p_chave,retorno_em=current_date,status='ENCERRADA',updated_at=now() where id=v_pai.id;
    update f.operacao_fiscal set chave_primeira_nota=p_chave,status='CONCLUIDA',updated_at=now() where id=v_op.id;
  else
    update f.operacao_fiscal set chave_primeira_nota=p_chave,status='CONCLUIDA',updated_at=now() where id=v_op.id;
  end if;
  return jsonb_build_object('operacao_id',v_op.id,'tipo',v_op.tipo,'etapa',p_etapa,'chave',p_chave,'registrada',true);
end;
$function$;

create or replace function f.fn_retorno_criar(p_remessa_controle_id uuid, p_cfop_confirmado text)
returns uuid language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record; v_rem f.remessa_controle%rowtype; v_op_rem f.operacao_fiscal%rowtype; v_id uuid:=gen_random_uuid(); v_esperado text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  select * into v_rem from f.remessa_controle where tenant_id=v_scope.tenant_id and empresa_id=v_scope.empresa_id and id=p_remessa_controle_id and status='ABERTA' for update;
  if v_rem.id is null then raise exception 'Remessa aberta nao encontrada.'; end if;
  select * into v_op_rem from f.operacao_fiscal where id=v_rem.operacao_remessa_id;
  v_esperado:=case v_op_rem.cfop_confirmado when '5901' then '5902' when '5915' then '5916' when '6915' then '6916' else null end;
  if v_esperado is null then raise exception 'Esta finalidade nao possui retorno fiscal configurado.'; end if;
  if p_cfop_confirmado<>v_esperado then raise exception 'CFOP de retorno divergente: confirmado %, esperado % para a remessa %.',p_cfop_confirmado,v_esperado,v_op_rem.cfop_confirmado; end if;
  insert into f.operacao_fiscal(id,tenant_id,empresa_id,tipo,finalidade,status,operacao_pai_id,nfe_referenciada,
    cfop_proposto,cfop_confirmado,cfop_confirmado_em,cfop_confirmado_por,entrega_json,criado_por,preparado_homologacao_em)
  values(v_id,v_scope.tenant_id,v_scope.empresa_id,'RETORNO',v_rem.finalidade,'PRONTO_HOMOLOGACAO',v_op_rem.id,v_rem.chave_remessa,
    v_esperado,p_cfop_confirmado,now(),v_scope.usuario_id,v_op_rem.entrega_json,v_scope.usuario_id,now());
  insert into f.operacao_fiscal_item(operacao_id,tenant_id,empresa_id,ordem,item_id,codigo,descricao,ncm,unidade,
    quantidade_original,quantidade,valor_unitario,valor_total,cfop_original,cfop_proposto,cfop_confirmado,
    origem_mercadoria,cst_icms,csosn,cst_ipi,cst_pis,cst_cofins,cbenef,reducao_base_icms_percentual,
    unidade_tributavel,cst_ibs_cbs,cclass_trib,cclass_trib_versao,ibs_cbs_json,
    base_icms,base_ipi,base_pis,base_cofins,aliquota_icms,aliquota_ipi,aliquota_pis,aliquota_cofins,
    valor_icms,valor_ipi,valor_pis,valor_cofins,xml_validado)
  select v_id,v_scope.tenant_id,v_scope.empresa_id,i.ordem,i.item_id,i.codigo,i.descricao,i.ncm,i.unidade,
    i.quantidade,i.quantidade,i.valor_unitario,i.valor_total,i.cfop_confirmado,v_esperado,p_cfop_confirmado,
    i.origem_mercadoria,i.cst_icms,i.csosn,i.cst_ipi,i.cst_pis,i.cst_cofins,i.cbenef,i.reducao_base_icms_percentual,
    i.unidade_tributavel,i.cst_ibs_cbs,i.cclass_trib,i.cclass_trib_versao,i.ibs_cbs_json,
    i.base_icms,i.base_ipi,i.base_pis,i.base_cofins,i.aliquota_icms,i.aliquota_ipi,i.aliquota_pis,i.aliquota_cofins,
    i.valor_icms,i.valor_ipi,i.valor_pis,i.valor_cofins,false
  from f.operacao_fiscal_item i where i.operacao_id=v_op_rem.id;
  update f.remessa_controle set operacao_retorno_id=v_id,updated_at=now() where id=v_rem.id;
  update f.operacao_fiscal set valor_total=(select sum(valor_total) from f.operacao_fiscal_item where operacao_id=v_id) where id=v_id;
  return v_id;
end;
$function$;

create or replace function f.fn_remessa_prazo_configurar(p_finalidade text, p_prazo_dias integer)
returns void language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if p_finalidade not in ('INDUSTRIALIZACAO','CONSERTO','SIMPLES','CONTA_ORDEM') then raise exception 'Finalidade invalida.'; end if;
  if p_prazo_dias is not null and p_prazo_dias<=0 then raise exception 'Prazo deve ser positivo ou vazio.'; end if;
  insert into f.remessa_prazo_config(tenant_id,empresa_id,finalidade,prazo_dias,updated_at,updated_by)
  values(v_scope.tenant_id,v_scope.empresa_id,p_finalidade,p_prazo_dias,now(),v_scope.usuario_id)
  on conflict(tenant_id,empresa_id,finalidade) do update set prazo_dias=excluded.prazo_dias,updated_at=now(),updated_by=excluded.updated_by;
end;
$function$;

create or replace view f.v_remessas_abertas with (security_invoker=true) as
select rc.id,rc.tenant_id,rc.empresa_id,rc.operacao_remessa_id,rc.finalidade,rc.chave_remessa,
  rc.destinatario_documento,rc.destinatario_nome,rc.remessa_em,
  (current_date-rc.remessa_em)::integer as dias_decorridos,cfg.prazo_dias,
  case when cfg.prazo_dias is null then false else current_date-rc.remessa_em>cfg.prazo_dias end as prazo_excedido
from f.remessa_controle rc left join f.remessa_prazo_config cfg
  on cfg.tenant_id=rc.tenant_id and cfg.empresa_id=rc.empresa_id and cfg.finalidade=rc.finalidade
where rc.status='ABERTA';

grant select on f.v_remessas_abertas to authenticated,service_role;
grant execute on function f.fn_devolucao_compra_preparar(bigint),f.fn_devolucao_compra_criar(bigint,jsonb),
  f.fn_venda_ordem_criar(integer,jsonb),f.fn_remessa_criar(text,text,jsonb,jsonb,text),
  f.fn_estorno_criar(uuid,text,text),f.fn_operacao_validar_homologacao(uuid,smallint),
  f.fn_operacao_registrar_chave(uuid,smallint,text),f.fn_retorno_criar(uuid,text),
  f.fn_remessa_prazo_configurar(text,integer) to authenticated,service_role;

commit;
