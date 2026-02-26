drop policy "colaboradores_delete" on "public"."colaboradores";
drop policy "colaboradores_insert" on "public"."colaboradores";
drop policy "colaboradores_select" on "public"."colaboradores";
drop policy "colaboradores_update" on "public"."colaboradores";
drop policy "empresa_memberships_select" on "public"."empresa_memberships";
alter table "public"."itens" drop constraint "itens_tipo_check";
alter table "public"."ordens_servico" drop constraint "ordens_servico_status_check";
drop view if exists "f"."r_ap_aging_detalhe";
drop view if exists "f"."r_ap_aging_resumo";
drop view if exists "f"."r_titulos_sem_motivo_por_fornecedor";
drop view if exists "r"."r_compra_fornecedores_pendentes";
drop view if exists "r"."r_compra_pendencias_agrupadas_item";
drop view if exists "r"."r_compra_pendencias_detalhadas";
drop index if exists "public"."clientes_tenant_empresa_documento_norm_uidx";
drop index if exists "public"."fornecedores_tenant_empresa_cnpj_norm_uidx";
alter table "public"."fornecedores" alter column "cnpj_norm" set default public.normalize_doc(cnpj);
CREATE UNIQUE INDEX fornecedores_unique_cnpj ON public.fornecedores USING btree (tenant_id, empresa_id, cnpj_norm) WHERE (cnpj_norm IS NOT NULL);
alter table "public"."itens" add constraint "itens_tipo_check" CHECK (((tipo)::text = ANY ((ARRAY['produto'::character varying, 'servico'::character varying, 'despesa'::character varying])::text[]))) not valid;
alter table "public"."itens" validate constraint "itens_tipo_check";
alter table "public"."ordens_servico" add constraint "ordens_servico_status_check" CHECK (((status)::text = ANY ((ARRAY['aberta'::character varying, 'em_andamento'::character varying, 'concluida'::character varying, 'cancelada'::character varying])::text[]))) not valid;
alter table "public"."ordens_servico" validate constraint "ordens_servico_status_check";
set check_function_bodies = off;
CREATE OR REPLACE FUNCTION f.fn_imposto_apuracao_range(p_tenant_id uuid, p_empresa_id uuid, p_comp_ini date, p_comp_fim date, p_operacao text DEFAULT NULL::text, p_natureza text DEFAULT NULL::text)
 RETURNS TABLE(tenant_id uuid, empresa_id uuid, competencia_date date, operacao text, imposto text, natureza text, base_total numeric, valor_total_calculado numeric, valor_total_ajustado numeric, qtd_documentos bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'f', 'public', 'a', 'c'
 SET row_security TO 'off'
AS $function$
begin
  -- ✅ permite SQL Editor (postgres/service_role), mas mantém segurança no app
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id é obrigatório.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id é obrigatório.'; end if;
  if p_comp_ini is null or p_comp_fim is null then raise exception 'Informe p_comp_ini e p_comp_fim'; end if;
  if p_comp_fim <= p_comp_ini then raise exception 'Intervalo inválido: p_comp_fim deve ser > p_comp_ini'; end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from p_tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if public.current_empresa_id() is distinct from p_empresa_id then
      raise exception 'Empresa mismatch';
    end if;
    if not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  return query
  select
    v.tenant_id,
    v.empresa_id,
    v.competencia_date,
    v.operacao::text,
    v.imposto,
    v.natureza,
    v.base_total,
    v.valor_total_calculado,
    v.valor_total_ajustado,
    v.qtd_documentos
  from f.vw_imposto_apuracao_mensal v
  where v.tenant_id = p_tenant_id
    and v.empresa_id = p_empresa_id
    and v.competencia_date >= p_comp_ini
    and v.competencia_date < p_comp_fim
    and (p_operacao is null or v.operacao::text = p_operacao)
    and (p_natureza is null or v.natureza = p_natureza)
  order by v.competencia_date asc, v.imposto asc, v.natureza asc;
end;
$function$;
CREATE OR REPLACE FUNCTION f.fn_imposto_documentos_do_mes(p_tenant_id uuid, p_empresa_id uuid, p_competencia date, p_imposto text, p_nat text, p_operacao text DEFAULT NULL::text)
 RETURNS TABLE(documento_fiscal_id uuid, chave_acesso text, emissao_date date, competencia_date date, operacao text, modelo text, serie text, numero text, valor_documento numeric, valor_imposto numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'f', 'public', 'a', 'c'
 SET row_security TO 'off'
AS $function$
begin
  -- ✅ permite SQL Editor (postgres/service_role), mas mantém segurança no app
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id é obrigatório.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id é obrigatório.'; end if;
  if p_competencia is null then raise exception 'competencia_date é obrigatório.'; end if;
  if p_imposto is null or length(trim(p_imposto)) = 0 then raise exception 'imposto é obrigatório.'; end if;
  if p_nat is null or length(trim(p_nat)) = 0 then raise exception 'natureza é obrigatória.'; end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from p_tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if public.current_empresa_id() is distinct from p_empresa_id then
      raise exception 'Empresa mismatch';
    end if;
    if not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  return query
  select
    df.id as documento_fiscal_id,
    df.chave_acesso,
    df.emissao_date,
    df.competencia_date,
    df.operacao::text,
    df.modelo,
    df.serie,
    df.numero,
    coalesce(df.valor_total, 0)::numeric as valor_documento,
    sum(coalesce(dfi.valor_ajustado, dfi.valor_calculado, 0))::numeric as valor_imposto
  from f.documento_fiscal_imposto dfi
  join f.documento_fiscal df
    on df.id = dfi.documento_fiscal_id
    and df.tenant_id = dfi.tenant_id
  where df.deleted_at is null
    and dfi.deleted_at is null
    and df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.competencia_date = p_competencia
    and dfi.imposto = p_imposto
    and dfi.natureza = p_nat
    and (p_operacao is null or df.operacao::text = p_operacao)
  group by
    df.id,
    df.chave_acesso,
    df.emissao_date,
    df.competencia_date,
    df.operacao,
    df.modelo,
    df.serie,
    df.numero,
    df.valor_total
  order by df.emissao_date desc nulls last, df.created_at desc;
end;
$function$;
create or replace view "f"."r_ap_aging_detalhe" as  SELECT t.tenant_id,
    t.empresa_id,
    t.id AS titulo_id,
    tp.id AS parcela_id,
    tp.numero AS parcela_numero,
    t.fornecedor_id,
    COALESCE(forn.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
    COALESCE(mc.codigo, 'NAO_CLASSIFICADO'::text) AS motivo_codigo,
    COALESCE(mc.nome, 'NAO CLASSIFICADO'::text) AS motivo_nome,
    tp.vencimento_date,
    (CURRENT_DATE - tp.vencimento_date) AS dias_atraso,
    tp.valor AS valor_parcela,
    tp.valor_aberto,
    t.status,
    t.emissao_date,
    t.competencia_date
   FROM ((((f.titulo_parcela tp
     JOIN f.titulo t ON ((t.id = tp.titulo_id)))
     LEFT JOIN f.titulo_aprovacao ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
     LEFT JOIN f.motivo_compra mc ON (((mc.id = COALESCE(ta.motivo_compra_id, t.motivo_compra_id)) AND (mc.deleted_at IS NULL))))
     LEFT JOIN public.fornecedores forn ON ((forn.id = t.fornecedor_id)))
  WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (tp.valor_aberto > (0)::numeric));
create or replace view "f"."r_ap_aging_resumo" as  WITH base AS (
         SELECT t.tenant_id,
            t.empresa_id,
            t.fornecedor_id,
            COALESCE(forn.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
            COALESCE(mc.codigo, 'NAO_CLASSIFICADO'::text) AS motivo_codigo,
            COALESCE(mc.nome, 'NAO CLASSIFICADO'::text) AS motivo_nome,
            tp.vencimento_date,
            tp.valor_aberto,
            (CURRENT_DATE - tp.vencimento_date) AS dias_atraso
           FROM ((((f.titulo_parcela tp
             JOIN f.titulo t ON ((t.id = tp.titulo_id)))
             LEFT JOIN f.titulo_aprovacao ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
             LEFT JOIN f.motivo_compra mc ON (((mc.id = COALESCE(ta.motivo_compra_id, t.motivo_compra_id)) AND (mc.deleted_at IS NULL))))
             LEFT JOIN public.fornecedores forn ON ((forn.id = t.fornecedor_id)))
          WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (tp.valor_aberto > (0)::numeric))
        )
 SELECT tenant_id,
    empresa_id,
    fornecedor_id,
    fornecedor_nome,
    motivo_codigo,
    motivo_nome,
    (sum(
        CASE
            WHEN (vencimento_date > CURRENT_DATE) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS a_vencer,
    (sum(
        CASE
            WHEN ((dias_atraso >= 0) AND (dias_atraso <= 30)) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_0_30,
    (sum(
        CASE
            WHEN ((dias_atraso >= 31) AND (dias_atraso <= 60)) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_31_60,
    (sum(
        CASE
            WHEN ((dias_atraso >= 61) AND (dias_atraso <= 90)) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_61_90,
    (sum(
        CASE
            WHEN (dias_atraso >= 91) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_90_mais,
    (sum(valor_aberto))::numeric(15,2) AS total_aberto
   FROM base
  GROUP BY tenant_id, empresa_id, fornecedor_id, fornecedor_nome, motivo_codigo, motivo_nome;
create or replace view "f"."r_titulos_sem_motivo_por_fornecedor" as  SELECT t.tenant_id,
    t.empresa_id,
    t.fornecedor_id,
    COALESCE(f.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
    count(*) AS qtd_titulos_sem_motivo,
    (sum(tp.valor_aberto))::numeric(15,2) AS total_aberto
   FROM (((f.titulo_parcela tp
     JOIN f.titulo t ON ((t.id = tp.titulo_id)))
     LEFT JOIN f.titulo_aprovacao ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
     LEFT JOIN public.fornecedores f ON ((f.id = t.fornecedor_id)))
  WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (tp.valor_aberto > (0)::numeric) AND (ta.id IS NULL))
  GROUP BY t.tenant_id, t.empresa_id, t.fornecedor_id, COALESCE(f.nome, 'SEM FORNECEDOR'::character varying)
  ORDER BY ((sum(tp.valor_aberto))::numeric(15,2)) DESC;
CREATE OR REPLACE FUNCTION public.apply_movimentacao_estoque()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_delta numeric;
  v_saldo_anterior numeric;
  v_custo_medio numeric;
  v_custo_entrada numeric;
  v_novo_custo numeric;
begin
  if new.item_id is null then
    return new;
  end if;

  v_saldo_anterior := 0;
  select coalesce(e.quantidade_atual, 0)
    into v_saldo_anterior
  from public.estoque e
  where e.tenant_id = new.tenant_id
    and e.empresa_id = new.empresa_id
    and e.item_id = new.item_id
  limit 1;

  v_delta := case when new.tipo = 'saida' then -1 else 1 end * coalesce(new.quantidade, 0);

  insert into public.estoque(tenant_id, empresa_id, item_id, quantidade_atual)
  values (new.tenant_id, new.empresa_id, new.item_id, v_delta)
  on conflict (tenant_id, empresa_id, item_id) do update
    set quantidade_atual = coalesce(public.estoque.quantidade_atual, 0) + v_delta;

  if new.tipo = 'entrada' and coalesce(new.quantidade, 0) > 0 then
    select coalesce(i.custo_medio, 0)
      into v_custo_medio
    from public.itens i
    where i.id = new.item_id
      and i.tenant_id = new.tenant_id
    limit 1;

    v_custo_entrada := coalesce(new.custo_unitario_real, new.custo_unitario_bruto, 0);
    v_novo_custo := case
      when (v_saldo_anterior + new.quantidade) > 0
        then ((v_saldo_anterior * v_custo_medio) + (new.quantidade * v_custo_entrada)) / (v_saldo_anterior + new.quantidade)
      else v_custo_entrada
    end;

    update public.itens
    set custo_ultima_compra = v_custo_entrada,
        custo_medio = v_novo_custo
    where id = new.item_id
      and tenant_id = new.tenant_id;
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.fn_atualiza_estoque_por_mov()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_delta numeric;
  v_qtd   numeric;
begin
  if new.empresa_id is null then
    raise exception 'empresa_id obrigatório na movimentação (tenant_id=%, item_id=%)', new.tenant_id, new.item_id;
  end if;

  v_delta :=
    case new.tipo
      when 'entrada' then coalesce(new.quantidade, 0)
      when 'saida'   then -coalesce(new.quantidade, 0)
      when 'ajuste'  then coalesce(new.quantidade, 0)
      else null
    end;

  if v_delta is null then
    raise exception 'Tipo de movimentação inválido: %', new.tipo;
  end if;

  -- garante linha no estoque (tenant+empresa+item)
  insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual, atualizado_em)
  values (new.tenant_id, new.empresa_id, new.item_id, 0, now())
  on conflict on constraint estoque_tenant_empresa_item_key do nothing;

  -- atualiza e captura novo saldo
  update public.estoque
     set quantidade_atual = quantidade_atual + v_delta,
         atualizado_em = now()
   where tenant_id  = new.tenant_id
     and empresa_id = new.empresa_id
     and item_id    = new.item_id
   returning quantidade_atual into v_qtd;

  if v_qtd < 0 then
    raise exception
      'Estoque não pode ficar negativo (tenant_id=%, empresa_id=%, item_id=%, saldo=%)',
      new.tenant_id, new.empresa_id, new.item_id, v_qtd;
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.import_nf_entrada(p_empresa_id uuid, p_finalidade_contexto public.item_finalidade, p_fornecedor_id bigint, p_itens_json jsonb, p_nf_json jsonb, p_tenant_id uuid, p_xml_raw text, p_gerar_contas_pagar boolean DEFAULT false, p_parcelas_json jsonb DEFAULT NULL::jsonb, p_os_id integer DEFAULT NULL::integer, p_baixar_os boolean DEFAULT false, p_motivo_compra_id uuid DEFAULT NULL::uuid, p_solicitante_usuario_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(status text, message text, nf_entrada_id bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  if exists (
    select 1
    from public.nf_entrada ne
    where ne.tenant_id = p_tenant_id
      and ne.empresa_id = p_empresa_id
      and ne.chave = v_chave
  ) then
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
    solicitante_usuario_id
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
    p_solicitante_usuario_id
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

  if not (public.can('financeiro','write') or public.can('financeiro','config')) then
    raise exception 'Sem permissao para gerar contas a pagar';
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
$function$;
CREATE OR REPLACE FUNCTION public.normalize_cnpj(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select regexp_replace(coalesce(p,''), '\D', '', 'g');
$function$;
create or replace view "r"."r_compra_fornecedores_pendentes" as  SELECT cp.tenant_id,
    cp.empresa_id,
    cp.fornecedor_id,
    COALESCE(f.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
    count(*) FILTER (WHERE (cp.status = 'PENDENTE'::text)) AS qtd_pendencias_abertas,
    (COALESCE(sum(cp.quantidade) FILTER (WHERE (cp.status = 'PENDENTE'::text)), (0)::numeric))::numeric(15,3) AS qtd_total_pendente,
    count(DISTINCT COALESCE((cp.item_id)::text, cp.item_nome, (cp.id)::text)) FILTER (WHERE (cp.status = 'PENDENTE'::text)) AS qtd_itens_distintos,
    min(cp.necessario_em) FILTER (WHERE (cp.status = 'PENDENTE'::text)) AS data_mais_urgente
   FROM (m.compra_pendencia cp
     LEFT JOIN public.fornecedores f ON (((f.tenant_id = cp.tenant_id) AND (f.empresa_id = cp.empresa_id) AND (f.id = cp.fornecedor_id))))
  WHERE (cp.deleted_at IS NULL)
  GROUP BY cp.tenant_id, cp.empresa_id, cp.fornecedor_id, COALESCE(f.nome, 'SEM FORNECEDOR'::character varying);
create or replace view "r"."r_compra_pendencias_agrupadas_item" as  WITH pend AS (
         SELECT cp.id,
            cp.tenant_id,
            cp.empresa_id,
            cp.fornecedor_id,
            cp.origem_tipo,
            cp.origem_os_id,
            cp.item_id,
            upper(TRIM(BOTH FROM COALESCE(cp.item_nome, (i_1.nome)::text, i_1.descricao, 'ITEM SEM NOME'::text))) AS item_nome,
            COALESCE(NULLIF(TRIM(BOTH FROM cp.unidade), ''::text), NULLIF(TRIM(BOTH FROM i_1.unidade_medida), ''::text), 'UN'::text) AS unidade,
            cp.quantidade,
            cp.estoque_meta,
            cp.created_at,
            os.os_num,
            os.numero_os
           FROM ((m.compra_pendencia cp
             LEFT JOIN public.itens i_1 ON (((i_1.tenant_id = cp.tenant_id) AND (i_1.empresa_id = cp.empresa_id) AND (i_1.id = cp.item_id))))
             LEFT JOIN public.ordens_servico os ON (((os.tenant_id = cp.tenant_id) AND (os.empresa_id = cp.empresa_id) AND (os.id = cp.origem_os_id))))
          WHERE ((cp.deleted_at IS NULL) AND (cp.status = 'PENDENTE'::text))
        ), em_compra AS (
         SELECT p_1.tenant_id,
            p_1.empresa_id,
            i_1.item_id,
            (sum(GREATEST((i_1.quantidade - i_1.quantidade_recebida), (0)::numeric)))::numeric(15,3) AS qtd_em_compra_aberto
           FROM (m.pedido_compra_item i_1
             JOIN m.pedido_compra p_1 ON ((p_1.id = i_1.pedido_compra_id)))
          WHERE ((p_1.deleted_at IS NULL) AND (i_1.deleted_at IS NULL) AND (p_1.status = ANY (ARRAY['RASCUNHO'::text, 'AGUARDANDO_APROVACAO'::text, 'APROVADO'::text, 'ENVIADO'::text, 'PARCIAL_RECEBIDO'::text])))
          GROUP BY p_1.tenant_id, p_1.empresa_id, i_1.item_id
        )
 SELECT p.tenant_id,
    p.empresa_id,
    p.fornecedor_id,
    COALESCE(f.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
    p.item_id,
    i.codigo_interno AS item_codigo,
    p.item_nome,
    p.unidade,
    array_agg(p.id ORDER BY p.created_at) AS pendencia_ids,
    (COALESCE(sum(p.quantidade) FILTER (WHERE (p.origem_tipo = 'OS'::text)), (0)::numeric))::numeric(15,3) AS qtd_os_total,
    (COALESCE(sum(p.quantidade) FILTER (WHERE (p.origem_tipo = ANY (ARRAY['OUTROS'::text, 'ESTOQUE'::text]))), (0)::numeric))::numeric(15,3) AS qtd_outros_total,
    (COALESCE(e.quantidade_atual, (0)::numeric))::numeric(15,3) AS qtd_estoque_atual,
    (COALESCE(ec.qtd_em_compra_aberto, (0)::numeric))::numeric(15,3) AS qtd_em_compra_aberto,
    (GREATEST((0)::numeric, ((COALESCE(i.estoque_minimo, 0))::numeric - (COALESCE(e.quantidade_atual, (0)::numeric) + COALESCE(ec.qtd_em_compra_aberto, (0)::numeric)))))::numeric(15,3) AS sugestao_min,
    (GREATEST((0)::numeric, ((COALESCE(i.estoque_ideal, 0))::numeric - (COALESCE(e.quantidade_atual, (0)::numeric) + COALESCE(ec.qtd_em_compra_aberto, (0)::numeric)))))::numeric(15,3) AS sugestao_ideal,
    (GREATEST((0)::numeric, ((COALESCE(i.estoque_maximo, 0))::numeric - (COALESCE(e.quantidade_atual, (0)::numeric) + COALESCE(ec.qtd_em_compra_aberto, (0)::numeric)))))::numeric(15,3) AS sugestao_max,
    (array_agg(p.id ORDER BY p.created_at) FILTER (WHERE (p.origem_tipo = 'ESTOQUE'::text)))[1] AS estoque_pendencia_id,
    max(p.estoque_meta) FILTER (WHERE (p.origem_tipo = 'ESTOQUE'::text)) AS estoque_meta_atual,
    (COALESCE(sum(p.quantidade) FILTER (WHERE (p.origem_tipo = 'ESTOQUE'::text)), (0)::numeric))::numeric(15,3) AS qtd_estoque_pendencia,
    COALESCE(jsonb_agg(jsonb_build_object('pendencia_id', p.id, 'os_id', p.origem_os_id, 'os_num', p.os_num, 'numero_os', p.numero_os, 'quantidade', p.quantidade) ORDER BY p.created_at) FILTER (WHERE (p.origem_tipo = 'OS'::text)), '[]'::jsonb) AS os_breakdown
   FROM ((((pend p
     LEFT JOIN public.fornecedores f ON (((f.tenant_id = p.tenant_id) AND (f.empresa_id = p.empresa_id) AND (f.id = p.fornecedor_id))))
     LEFT JOIN public.itens i ON (((i.tenant_id = p.tenant_id) AND (i.empresa_id = p.empresa_id) AND (i.id = p.item_id))))
     LEFT JOIN public.estoque e ON (((e.tenant_id = p.tenant_id) AND (e.empresa_id = p.empresa_id) AND (e.item_id = p.item_id))))
     LEFT JOIN em_compra ec ON (((ec.tenant_id = p.tenant_id) AND (ec.empresa_id = p.empresa_id) AND (ec.item_id = p.item_id))))
  GROUP BY p.tenant_id, p.empresa_id, p.fornecedor_id, COALESCE(f.nome, 'SEM FORNECEDOR'::character varying), p.item_id, i.codigo_interno, p.item_nome, p.unidade, e.quantidade_atual, ec.qtd_em_compra_aberto, i.estoque_minimo, i.estoque_ideal, i.estoque_maximo;
create or replace view "r"."r_compra_pendencias_detalhadas" as  SELECT cp.id AS pendencia_id,
    cp.tenant_id,
    cp.empresa_id,
    cp.fornecedor_id,
    COALESCE(f.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
    cp.status,
    cp.origem_tipo,
    cp.origem_os_id,
    os.os_num,
    os.numero_os,
    cp.item_id,
    i.codigo_interno AS item_codigo,
    COALESCE(cp.item_nome, (i.nome)::text, i.descricao) AS item_nome,
    COALESCE(cp.unidade, (i.unidade_medida)::text, 'UN'::text) AS unidade,
    cp.quantidade,
    cp.prioridade,
    cp.necessario_em,
    cp.observacoes,
    cp.estoque_meta,
    cp.estoque_atual_qtd,
    cp.estoque_em_compra_qtd,
    cp.estoque_alvo_qtd,
    cp.estoque_sugestao_qtd
   FROM (((m.compra_pendencia cp
     LEFT JOIN public.fornecedores f ON (((f.tenant_id = cp.tenant_id) AND (f.empresa_id = cp.empresa_id) AND (f.id = cp.fornecedor_id))))
     LEFT JOIN public.ordens_servico os ON (((os.tenant_id = cp.tenant_id) AND (os.empresa_id = cp.empresa_id) AND (os.id = cp.origem_os_id))))
     LEFT JOIN public.itens i ON (((i.tenant_id = cp.tenant_id) AND (i.empresa_id = cp.empresa_id) AND (i.id = cp.item_id))))
  WHERE (cp.deleted_at IS NULL);
create or replace view "r"."r_orcamento_catalogo_busca" as  SELECT 'ITEM'::text AS origem,
    i.tenant_id,
    i.empresa_id,
    (i.id)::text AS ref_id,
    i.id AS item_id,
    NULL::uuid AS conjunto_id,
    upper(TRIM(BOTH FROM i.codigo_interno)) AS codigo,
    upper(TRIM(BOTH FROM i.nome)) AS nome,
    upper(TRIM(BOTH FROM COALESCE(i.unidade_medida, 'UN'::character varying))) AS unidade,
        CASE
            WHEN (lower((i.tipo)::text) = 'produto'::text) THEN 'PRODUTO'::text
            WHEN (lower((i.tipo)::text) = 'servico'::text) THEN 'SERVICO'::text
            ELSE upper((i.tipo)::text)
        END AS tipo,
    (i.preco_unitario)::numeric(15,2) AS preco_sugerido
   FROM public.itens i
  WHERE ((i.ativo = true) AND ((i.tipo)::text = ANY ((ARRAY['produto'::character varying, 'servico'::character varying])::text[])))
UNION ALL
 SELECT 'CONJUNTO'::text AS origem,
    c.tenant_id,
    c.empresa_id,
    (c.id)::text AS ref_id,
    NULL::integer AS item_id,
    c.id AS conjunto_id,
    c.codigo,
    c.nome,
    'CJ'::text AS unidade,
    'CONJUNTO'::text AS tipo,
        CASE
            WHEN (c.precificacao = 'PRECO_FIXO'::text) THEN c.preco_fixo
            ELSE (COALESCE(sum((ci.quantidade * i.preco_unitario)), (0)::numeric))::numeric(15,2)
        END AS preco_sugerido
   FROM ((c.conjunto c
     LEFT JOIN c.conjunto_item ci ON (((ci.conjunto_id = c.id) AND (ci.deleted_at IS NULL))))
     LEFT JOIN public.itens i ON (((i.id = ci.item_id) AND (i.tenant_id = c.tenant_id) AND (i.empresa_id = c.empresa_id) AND (i.ativo = true))))
  WHERE ((c.deleted_at IS NULL) AND (c.ativo = true))
  GROUP BY c.id;
create policy "colaboradores_delete"
  on "public"."colaboradores"
  as permissive
  for delete
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));
create policy "colaboradores_insert"
  on "public"."colaboradores"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));
create policy "colaboradores_select"
  on "public"."colaboradores"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));
create policy "colaboradores_update"
  on "public"."colaboradores"
  as permissive
  for update
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))))
with check ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));
create policy "empresa_memberships_select"
  on "public"."empresa_memberships"
  as permissive
  for select
  to public
using (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = empresa_memberships.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))));
