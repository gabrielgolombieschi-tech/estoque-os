begin;

alter table public.nf_entrada
  add column if not exists gerar_contas_pagar boolean not null default false;

comment on column public.nf_entrada.gerar_contas_pagar is
  'Indica se a importacao desta NF deve gerar/ajustar titulo AP automaticamente.';

update public.nf_entrada nf
   set gerar_contas_pagar = true
 where coalesce(nf.gerar_contas_pagar, false) = false
   and exists (
     select 1
       from f.documento_fiscal df
       join f.titulo t
         on t.tenant_id = df.tenant_id
        and t.documento_fiscal_id = df.id
        and t.tipo = 'AP'
        and t.deleted_at is null
      where df.tenant_id = nf.tenant_id
        and df.source_nf_entrada_id = nf.id
        and df.deleted_at is null
        and coalesce(df.operacao, 'ENTRADA') <> 'SAIDA'
   );

update public.nf_entrada nf
   set gerar_contas_pagar = false
  from f.documento_fiscal df
 where df.tenant_id = nf.tenant_id
   and df.source_nf_entrada_id = nf.id
   and df.deleted_at is null
   and df.operacao = 'SAIDA'
   and coalesce(nf.gerar_contas_pagar, false) <> false;

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
               valor_unitario = case when coalesce(oi.valor_unitario,0) = 0 then v_vunit else oi.valor_unitario end
         where oi.tenant_id = p_tenant_id
           and oi.empresa_id = p_empresa_id
           and oi.os_id = p_os_id
           and oi.item_id = v_item_id
         returning oi.id
      )
      insert into public.os_itens (os_id, item_id, quantidade, valor_unitario, tenant_id, empresa_id, criado_em)
      select p_os_id, v_item_id, v_qtd, v_vunit, p_tenant_id, p_empresa_id, now()
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

create or replace function public.fn_fix_nf_entrada_pos_import(p_nf_entrada_id bigint)
returns table(status text, message text, documento_fiscal_id uuid, titulo_id uuid)
language plpgsql
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_xml xml;

  v_emit_nome text;
  v_emit_doc text;

  v_mod text;
  v_serie text;
  v_num text;

  v_dhemi text;
  v_emissao_ts timestamptz;
  v_emissao_date date;
  v_competencia date;

  v_vprod numeric(15,2);
  v_vfrete numeric(15,2);
  v_vdesc numeric(15,2);
  v_voutros numeric(15,2);
  v_vseg numeric(15,2);
  v_vnf numeric(15,2);

  v_fornecedor_id int;
  v_df_id uuid;
  v_titulo_id uuid;

  v_prev_total numeric(15,2);
  v_sum_parcelas numeric(15,2);
  v_plano_contas_id uuid;
begin
  select *
    into v_nf
    from public.nf_entrada
   where id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  if v_nf.xml_raw is null or nullif(btrim(v_nf.xml_raw), '') is null then
    raise exception 'nf_entrada % sem xml_raw. Nao da pra enriquecer/gerar AP.', p_nf_entrada_id;
  end if;

  v_xml := xmlparse(document v_nf.xml_raw);

  v_emit_nome := nullif((xpath('string(//*[local-name()="emit"]/*[local-name()="xNome"])', v_xml))[1]::text, '');
  v_emit_doc := nullif((xpath('string(//*[local-name()="emit"]/*[local-name()="CNPJ"])', v_xml))[1]::text, '');
  if v_emit_doc is null then
    v_emit_doc := nullif((xpath('string(//*[local-name()="emit"]/*[local-name()="CPF"])', v_xml))[1]::text, '');
  end if;

  v_mod := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="mod"])', v_xml))[1]::text, '');
  v_serie := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="serie"])', v_xml))[1]::text, '');
  v_num := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="nNF"])', v_xml))[1]::text, '');

  v_dhemi := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="dhEmi"])', v_xml))[1]::text, '');
  if v_dhemi is null then
    v_dhemi := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="dEmi"])', v_xml))[1]::text, '');
  end if;

  begin
    v_emissao_ts := nullif(v_dhemi,'')::timestamptz;
  exception when others then
    v_emissao_ts := v_nf.data_emissao;
  end;

  v_emissao_date := coalesce((v_emissao_ts at time zone 'America/Sao_Paulo')::date, (now() at time zone 'America/Sao_Paulo')::date);
  v_competencia := date_trunc('month', v_emissao_date)::date;

  v_vprod := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vProd"])', v_xml))[1]::text, '')::numeric;
  v_vfrete := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vFrete"])', v_xml))[1]::text, '')::numeric;
  v_vdesc := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vDesc"])', v_xml))[1]::text, '')::numeric;
  v_voutros := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vOutro"])', v_xml))[1]::text, '')::numeric;
  v_vseg := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vSeg"])', v_xml))[1]::text, '')::numeric;
  v_vnf := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vNF"])', v_xml))[1]::text, '')::numeric;

  v_vprod := coalesce(v_vprod, (select coalesce(sum(i.v_prod),0) from public.nf_entrada_itens i where i.nf_entrada_id = v_nf.id), 0);
  v_vfrete := coalesce(v_vfrete, 0);
  v_vdesc := coalesce(v_vdesc, 0);
  v_voutros := coalesce(v_voutros, 0);
  v_vseg := coalesce(v_vseg, 0);
  v_vnf := coalesce(v_vnf, v_nf.valor_total, 0);

  v_fornecedor_id := nullif(v_nf.fornecedor_id::int, 0);
  if v_fornecedor_id is null then
    v_fornecedor_id := public.fn_fornecedor_upsert_por_documento(
      v_nf.tenant_id,
      coalesce(v_emit_nome, v_nf.emitente_nome, 'FORNECEDOR'),
      coalesce(v_emit_doc, v_nf.emitente_cnpj)
    );
  end if;

  update public.nf_entrada
     set modelo = coalesce(v_mod, modelo, '55'),
         serie = coalesce(v_serie, serie),
         numero = coalesce(v_num, numero),
         emitente_nome = coalesce(v_emit_nome, emitente_nome),
         emitente_cnpj = coalesce(v_emit_doc, emitente_cnpj),
         data_emissao = coalesce(v_emissao_ts, data_emissao),
         valor_produtos = v_vprod,
         valor_frete = v_vfrete,
         valor_desconto = v_vdesc,
         valor_outros = v_voutros,
         valor_seguro = v_vseg,
         valor_total = v_vnf,
         fornecedor_id = v_fornecedor_id,
         updated_at = now()
   where id = v_nf.id;

  v_df_id := f.fn_ensure_documento_fiscal_from_nf_entrada(v_nf.id);

  update f.documento_fiscal
     set modelo = coalesce(v_mod, modelo, '55'),
         serie = coalesce(v_serie, serie),
         numero = coalesce(v_num, numero),
         fornecedor_id = v_fornecedor_id,
         emissao_date = v_emissao_date,
         competencia_date = v_competencia,
         valor_produtos = v_vprod,
         valor_frete = v_vfrete,
         valor_desconto = v_vdesc,
         valor_outros = v_voutros,
         valor_seguro = v_vseg,
         valor_total = v_vnf,
         updated_at = now()
   where id = v_df_id;

  if not coalesce(v_nf.gerar_contas_pagar, false) then
    status := 'ok';
    message := 'NF enriquecida + DF atualizado (sem AP automatico).';
    documento_fiscal_id := v_df_id;
    titulo_id := null;
    return next;
    return;
  end if;

  select t.id
    into v_titulo_id
    from f.titulo t
   where t.tenant_id = v_nf.tenant_id
     and t.empresa_id = v_nf.empresa_id
     and t.tipo = 'AP'
     and t.documento_fiscal_id = v_df_id
     and t.deleted_at is null
   order by t.created_at desc
   limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem,
      fornecedor_id, documento_fiscal_id,
      descricao, emissao_date, competencia_date,
      valor_total, valor_aberto,
      motivo_compra_id
    )
    values (
      v_nf.tenant_id, v_nf.empresa_id, 'AP', 'PENDENTE', 'XML',
      v_fornecedor_id, v_df_id,
      concat('NF-e ', coalesce(v_num,''), '/', coalesce(v_serie,''), ' - ', coalesce(v_emit_nome, 'FORNECEDOR')),
      v_emissao_date, v_competencia,
      v_vnf, v_vnf,
      v_nf.motivo_compra_id
    )
    returning id into v_titulo_id;
  end if;

  perform 1 from public.fn_regerar_parcelas_titulo_from_xml(v_nf.id, v_titulo_id);

  select valor_total
    into v_prev_total
    from f.titulo
   where id = v_titulo_id;

  select coalesce(sum(p.valor),0)
    into v_sum_parcelas
    from f.titulo_parcela p
   where p.tenant_id = v_nf.tenant_id
     and p.titulo_id = v_titulo_id
     and p.deleted_at is null;

  update f.titulo
     set valor_total = v_sum_parcelas,
         valor_aberto = case
           when coalesce(valor_aberto,0) = 0 or valor_aberto = v_prev_total then v_sum_parcelas
           else valor_aberto
         end,
         updated_at = now()
   where id = v_titulo_id
     and tenant_id = v_nf.tenant_id
     and deleted_at is null;

  select mc.plano_contas_id
    into v_plano_contas_id
    from f.motivo_compra mc
   where mc.id = v_nf.motivo_compra_id
     and mc.tenant_id = v_nf.tenant_id
     and mc.deleted_at is null
   limit 1;

  if not exists (
    select 1
      from f.titulo_rateio tr
     where tr.tenant_id = v_nf.tenant_id
       and tr.titulo_id = v_titulo_id
       and tr.deleted_at is null
  ) then
    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_nf.tenant_id, v_titulo_id, v_plano_contas_id, v_nf.os_id, 100, v_sum_parcelas);
  end if;

  status := 'ok';
  message := 'NF enriquecida + DF atualizado + titulo AP gerado (f.*).';
  documento_fiscal_id := v_df_id;
  titulo_id := v_titulo_id;
  return next;
end;
$$;

create or replace function f.fn_nf_entrada__auto_fix_ap_from_xml()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'f', 'a'
set row_security to 'off'
as $$
declare
  v_titulo_id uuid;
  v_parc_cnt int;
  v_dup_cnt int;
  v_emissao_date date;
  v_xml xml;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if new.xml_raw is null or nullif(btrim(new.xml_raw),'') is null then
    return new;
  end if;

  if not coalesce(new.gerar_contas_pagar, false) then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.xml_raw is not null and nullif(btrim(old.xml_raw),'') is not null then
    return new;
  end if;

  v_emissao_date := (new.data_emissao at time zone 'America/Sao_Paulo')::date;

  v_xml := xmlparse(document new.xml_raw);
  v_dup_cnt := coalesce(array_length(xpath('//*[local-name()="cobr"]/*[local-name()="dup"]', v_xml),1),0);

  select t.id
    into v_titulo_id
    from f.documento_fiscal df
    join f.titulo t
      on t.tenant_id = df.tenant_id
     and t.documento_fiscal_id = df.id
     and t.tipo = 'AP'
     and t.deleted_at is null
   where df.tenant_id = new.tenant_id
     and df.source_nf_entrada_id = new.id
     and df.deleted_at is null
   limit 1;

  if v_titulo_id is null then
    perform 1 from public.fn_fix_nf_entrada_pos_import(new.id);
    return new;
  end if;

  if exists (
    select 1
      from f.titulo_parcela p
     where p.tenant_id = new.tenant_id
       and p.titulo_id = v_titulo_id
       and p.deleted_at is null
       and coalesce(p.valor_aberto, p.valor) <> p.valor
  ) then
    return new;
  end if;

  select count(*)
    into v_parc_cnt
    from f.titulo_parcela p
   where p.tenant_id = new.tenant_id
     and p.titulo_id = v_titulo_id
     and p.deleted_at is null;

  if v_dup_cnt > 1 and v_parc_cnt = 1 and exists (
    select 1
      from f.titulo_parcela p
      join f.titulo t on t.tenant_id = p.tenant_id and t.id = p.titulo_id
     where p.tenant_id = new.tenant_id
       and p.titulo_id = v_titulo_id
       and p.deleted_at is null
       and p.vencimento_date = v_emissao_date
       and abs(p.valor - t.valor_total) <= 0.01
  ) then
    perform 1 from public.fn_fix_nf_entrada_pos_import(new.id);
  end if;

  return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select t.id as titulo_id
      from f.titulo t
      join f.documento_fiscal df
        on df.id = t.documento_fiscal_id
       and df.tenant_id = t.tenant_id
       and df.deleted_at is null
     where t.tipo = 'AP'
       and t.deleted_at is null
       and upper(coalesce(t.status, '')) <> 'CANCELADO'
       and df.source_nf_entrada_id is not null
       and df.operacao = 'SAIDA'
  loop
    begin
      perform f.cancelar_titulo_ap(r.titulo_id, 'AP_INDEVIDO_IMPORTACAO_NFE_SAIDA');
    exception
      when others then
        raise notice 'Nao foi possivel cancelar titulo AP indevido %: %', r.titulo_id, sqlerrm;
    end;
  end loop;
end;
$$;

commit;
