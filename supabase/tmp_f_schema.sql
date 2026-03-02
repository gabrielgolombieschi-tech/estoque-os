


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "f";


ALTER SCHEMA "f" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_month_first"("p_date" "date") RETURNS "date"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select date_trunc('month', p_date)::date;
$$;


ALTER FUNCTION "f"."_month_first"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_month_last"("p_date" "date") RETURNS "date"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select (date_trunc('month', p_date) + interval '1 month - 1 day')::date;
$$;


ALTER FUNCTION "f"."_month_last"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_nfe_xpath_num"("p_xml" "xml", "p_path" "text") RETURNS numeric
    LANGUAGE "plpgsql"
    AS $$
declare
  v_text text;
begin
  -- pega o primeiro nó do xpath com namespace NF-e
  select (xpath(
    p_path,
    p_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  ))[1]::text
  into v_text;

  if v_text is null or btrim(v_text) = '' then
    return null;
  end if;

  -- normaliza decimal com vírgula (se vier)
  v_text := replace(btrim(v_text), ',', '.');

  return v_text::numeric;
exception when others then
  return null;
end;
$$;


ALTER FUNCTION "f"."_nfe_xpath_num"("p_xml" "xml", "p_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_nfe_xpath_text"("p_xml" "xml", "p_path" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select nullif((xpath(
    p_path,
    p_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  ))[1]::text, '');
$$;


ALTER FUNCTION "f"."_nfe_xpath_text"("p_xml" "xml", "p_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_safe_day_in_month"("p_month_first" "date", "p_day" integer) RETURNS "date"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select make_date(extract(year from p_month_first)::int, extract(month from p_month_first)::int,
    least(greatest(p_day, 1), extract(day from f._month_last(p_month_first))::int)
  );
$$;


ALTER FUNCTION "f"."_safe_day_in_month"("p_month_first" "date", "p_day" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_xpath_first_num_anyns"("p_xml" "xml", "p_xpath" "text") RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select coalesce(nullif(replace((xpath(p_xpath, p_xml))[1]::text, ',', '.'), '')::numeric, 0);
$$;


ALTER FUNCTION "f"."_xpath_first_num_anyns"("p_xml" "xml", "p_xpath" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_xpath_first_text_anyns"("p_xml" "xml", "p_xpath" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select nullif(btrim((xpath(p_xpath, p_xml))[1]::text), '');
$$;


ALTER FUNCTION "f"."_xpath_first_text_anyns"("p_xml" "xml", "p_xpath" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_xpath_num_anyns"("p_xml" "xml", "p_xpath" "text") RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
declare
  v_text text;
begin
  -- pega o primeiro resultado do xpath
  select (xpath(p_xpath, p_xml))[1]::text
    into v_text;

  v_text := nullif(btrim(v_text), '');

  if v_text is null then
    return 0;
  end if;

  -- normaliza decimal (caso venha com vírgula)
  v_text := replace(v_text, ',', '.');

  begin
    return v_text::numeric;
  exception when others then
    return 0;
  end;
end;
$$;


ALTER FUNCTION "f"."_xpath_num_anyns"("p_xml" "xml", "p_xpath" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."_xpath_sum_num_anyns"("p_xml" "xml", "p_xpath" "text") RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select coalesce(sum(nullif(replace(x::text, ',', '.'), '')::numeric), 0)
  from unnest(xpath(p_xpath, p_xml)) as t(x);
$$;


ALTER FUNCTION "f"."_xpath_sum_num_anyns"("p_xml" "xml", "p_xpath" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."agendar_pagamento_ap"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_prevista" "date", "p_forma_pagamento" "text", "p_valor_previsto" numeric, "p_observacoes" "text" DEFAULT NULL::"text", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_cb f.conta_bancaria%rowtype;

  v_user uuid;
begin
  if p_data_prevista is null then
    raise exception 'Data prevista obrigatoria';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'Forma de pagamento obrigatoria';
  end if;

  if p_forma_pagamento not in ('PIX','BOLETO','TRANSFERENCIA','DINHEIRO','CARTAO','OUTROS') then
    raise exception 'Forma de pagamento invalida: %', p_forma_pagamento;
  end if;

  if p_valor_previsto is null or p_valor_previsto <= 0 then
    raise exception 'Valor previsto deve ser > 0';
  end if;

  -- auth: app ou SQL Editor (postgres/service_role)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  -- carrega título
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Agendamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('PENDENTE','APROVADO','AGENDADO') then
    raise exception 'Titulo precisa estar PENDENTE/APROVADO/AGENDADO. Status atual=%', v_titulo.status;
  end if;

  if v_titulo.valor_aberto <= 0 then
    raise exception 'Titulo sem saldo em aberto';
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- fallback SQL Editor
  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- conta bancária
  select * into v_cb
  from f.conta_bancaria
  where id = p_conta_bancaria_id
    and deleted_at is null;

  if not found then
    raise exception 'Conta bancaria nao encontrada (id=%)', p_conta_bancaria_id;
  end if;

  if v_cb.tenant_id <> v_titulo.tenant_id or v_cb.empresa_id <> v_titulo.empresa_id then
    raise exception 'Conta bancaria nao pertence ao mesmo tenant/empresa do titulo';
  end if;

  if round(p_valor_previsto,2) > round(v_titulo.valor_aberto,2) then
    raise exception 'Valor previsto (%) maior que saldo em aberto (%)', round(p_valor_previsto,2), round(v_titulo.valor_aberto,2);
  end if;

  -- upsert 1:1 por título
  insert into f.titulo_agendamento (
    tenant_id,
    titulo_id,
    conta_bancaria_id,
    data_prevista,
    forma_pagamento,
    valor_previsto,
    observacoes,
    change_reason,
    agendado_em,
    agendado_por,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.id,
    v_cb.id,
    p_data_prevista,
    p_forma_pagamento,
    round(p_valor_previsto,2),
    p_observacoes,
    p_change_reason,
    now(),
    v_user,
    now(), now(), v_user, v_user
  )
  on conflict (tenant_id, titulo_id) do update set
    conta_bancaria_id = excluded.conta_bancaria_id,
    data_prevista = excluded.data_prevista,
    forma_pagamento = excluded.forma_pagamento,
    valor_previsto = excluded.valor_previsto,
    observacoes = excluded.observacoes,
    change_reason = excluded.change_reason,
    agendado_em = now(),
    agendado_por = v_user,
    updated_at = now(),
    updated_by = v_user;

  -- status do título
  update f.titulo
     set status = 'AGENDADO',
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  -- evento
  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'PAGAMENTO_AGENDADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'conta_bancaria_id', v_cb.id,
      'data_prevista', p_data_prevista,
      'forma_pagamento', p_forma_pagamento,
      'valor_previsto', round(p_valor_previsto,2),
      'change_reason', p_change_reason
    ),
    now(), v_user
  );
end;
$$;


ALTER FUNCTION "f"."agendar_pagamento_ap"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_prevista" "date", "p_forma_pagamento" "text", "p_valor_previsto" numeric, "p_observacoes" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."ajustar_valor_parcela_ap"("p_titulo_parcela_id" "uuid", "p_novo_valor" numeric, "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_tp f.titulo_parcela%rowtype;
  v_t f.titulo%rowtype;
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;
  v_delta numeric(15,2);
begin
  if p_titulo_parcela_id is null then
    raise exception 'p_titulo_parcela_id obrigat3rio';
  end if;
  if p_novo_valor is null or p_novo_valor <= 0 then
    raise exception 'p_novo_valor deve ser > 0';
  end if;

  -- Auth: app ou SQL Editor
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_tp
  from f.titulo_parcela tp
  where tp.id = p_titulo_parcela_id
    and tp.deleted_at is null;

  if not found then
    raise exception 'Parcela n3o encontrada';
  end if;

  select * into v_t
  from f.titulo t
  where t.id = v_tp.titulo_id
    and t.deleted_at is null;

  if not found then
    raise exception 'Titulo n3o encontrado';
  end if;

  if v_t.tipo <> 'AP' then
    raise exception 'Somente AP pode ajustar valor';
  end if;

  if v_t.status <> 'PENDENTE' then
    raise exception 'S3 ajusta valor em t1tulo PENDENTE (status=%)', v_t.status;
  end if;

  -- N3o permite ajustar se j1 h1 pagamentos aplicados
  if exists (
    select 1
    from f.pagamento_item pi
    where pi.titulo_parcela_id = v_tp.id
      and pi.deleted_at is null
  ) then
    raise exception 'N3o  poss1vel ajustar: parcela j1 possui pagamentos aplicados';
  end if;

  v_tenant_id := v_t.tenant_id;
  v_empresa_id := v_t.empresa_id;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();
  v_delta := p_novo_valor - v_tp.valor;

  -- Ajusta parcela
  update f.titulo_parcela
     set valor = p_novo_valor,
         valor_aberto = p_novo_valor,
         updated_at = now(),
         updated_by = v_usuario_id
   where id = v_tp.id;

  -- Ajusta t1tulo
  update f.titulo
     set valor_total = valor_total + v_delta,
         valor_aberto = valor_aberto + v_delta,
         updated_at = now(),
         updated_by = v_usuario_id
   where id = v_t.id;
end;
$$;


ALTER FUNCTION "f"."ajustar_valor_parcela_ap"("p_titulo_parcela_id" "uuid", "p_novo_valor" numeric, "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."aprovar_titulo_ap"("p_titulo_id" "uuid", "p_motivo_compra_id" "uuid", "p_os_id" integer DEFAULT NULL::integer, "p_motivo_outros_text" "text" DEFAULT NULL::"text", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_motivo f.motivo_compra%rowtype;

  v_aprovador uuid;
begin
  -- permite SQL Editor (postgres/service_role); no app continua autenticado
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  -- carrega titulo
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Aprovacao so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if v_titulo.status <> 'PENDENTE' then
    raise exception 'Titulo precisa estar PENDENTE para aprovar. Status atual=%', v_titulo.status;
  end if;

  -- permissão (somente ADMIN/FINANCEIRO no app)
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- aprovador normal (app)
  v_aprovador := a.fn_current_usuario_id();

  -- ✅ fallback para SQL Editor: pega um OWNER/ADMIN do tenant
  if v_aprovador is null then
    select ut.usuario_id
      into v_aprovador
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_aprovador is null then
      raise exception
        'Nao foi possivel determinar aprovador (a.fn_current_usuario_id() retornou null e nao existe OWNER/ADMIN no tenant). Execute pelo app.';
    end if;
  end if;

  -- =====================================================
  -- MOTIVO: busca por ID e realinha tenant se necessário
  -- =====================================================
  select * into v_motivo
  from f.motivo_compra
  where id = p_motivo_compra_id
    and deleted_at is null
    and ativo = true;

  if not found then
    raise exception 'Motivo de compra invalido/inativo (id=%)', p_motivo_compra_id;
  end if;

  if v_motivo.tenant_id <> v_titulo.tenant_id then
    if exists (
      select 1 from f.motivo_compra mc
      where mc.tenant_id = v_titulo.tenant_id
        and mc.codigo = v_motivo.codigo
        and mc.id <> v_motivo.id
        and mc.deleted_at is null
    ) then
      raise exception 'Conflito: ja existe motivo com codigo % no tenant do titulo', v_motivo.codigo;
    end if;

    if exists (
      select 1 from f.motivo_compra mc
      where mc.tenant_id = v_titulo.tenant_id
        and mc.nome = v_motivo.nome
        and mc.id <> v_motivo.id
        and mc.deleted_at is null
    ) then
      raise exception 'Conflito: ja existe motivo com nome % no tenant do titulo', v_motivo.nome;
    end if;

    update f.motivo_compra
       set tenant_id = v_titulo.tenant_id,
           updated_at = now(),
           updated_by = v_aprovador
     where id = v_motivo.id;

    select * into v_motivo
    from f.motivo_compra
    where id = p_motivo_compra_id
      and deleted_at is null
      and ativo = true;
  end if;

  -- validações do motivo
  if v_motivo.requires_os and p_os_id is null then
    raise exception 'Motivo "%" exige OS', v_motivo.nome;
  end if;

  if v_motivo.requires_text then
    if p_motivo_outros_text is null or length(trim(p_motivo_outros_text)) = 0 then
      raise exception 'Motivo "%" exige detalhamento em texto', v_motivo.nome;
    end if;
  end if;

  -- valida OS se informada
  if p_os_id is not null then
    if not exists (
      select 1
      from public.ordens_servico os
      where os.id = p_os_id
        and os.tenant_id = v_titulo.tenant_id
    ) then
      raise exception 'OS invalida (id=%) para este tenant', p_os_id;
    end if;
  end if;

  -- grava aprovação (upsert 1:1)
  insert into f.titulo_aprovacao (
    tenant_id,
    titulo_id,
    motivo_compra_id,
    motivo_outros_text,
    os_id,
    aprovado_em,
    aprovado_por,
    change_reason,
    created_at,
    updated_at,
    created_by,
    updated_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.id,
    v_motivo.id,
    p_motivo_outros_text,
    p_os_id,
    now(),
    v_aprovador,
    p_change_reason,
    now(),
    now(),
    v_aprovador,
    v_aprovador
  )
  on conflict (tenant_id, titulo_id) do update set
    motivo_compra_id = excluded.motivo_compra_id,
    motivo_outros_text = excluded.motivo_outros_text,
    os_id = excluded.os_id,
    aprovado_em = excluded.aprovado_em,
    aprovado_por = excluded.aprovado_por,
    change_reason = excluded.change_reason,
    updated_at = now(),
    updated_by = v_aprovador;

  -- status -> APROVADO
  update f.titulo
     set status = 'APROVADO',
         updated_at = now(),
         updated_by = v_aprovador
   where id = v_titulo.id;

  -- eventos
  insert into f.aprovacao_evento (
    tenant_id, empresa_id,
    acao, ref_table, ref_id,
    motivo, payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'APROVOU', 'f.titulo', v_titulo.id,
    v_motivo.nome,
    jsonb_build_object(
      'motivo_compra_id', v_motivo.id,
      'motivo_codigo', v_motivo.codigo,
      'motivo_nome', v_motivo.nome,
      'os_id', p_os_id,
      'motivo_outros_text', p_motivo_outros_text,
      'change_reason', p_change_reason
    ),
    now(), v_aprovador
  );

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'TITULO_APROVADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'status_anterior', 'PENDENTE',
      'status_novo', 'APROVADO',
      'motivo_compra_id', v_motivo.id,
      'os_id', p_os_id
    ),
    now(), v_aprovador
  );
end;
$$;


ALTER FUNCTION "f"."aprovar_titulo_ap"("p_titulo_id" "uuid", "p_motivo_compra_id" "uuid", "p_os_id" integer, "p_motivo_outros_text" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."atualizar_proximos_ap_recorrencia"("p_recorrencia_id" "uuid", "p_referencia_competencia" "date" DEFAULT NULL::"date", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_rec f.ap_recorrencia%rowtype;
  v_ref_comp date;
  v_ref_valor numeric(15,2);
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;

  v_count integer := 0;
begin
  if p_recorrencia_id is null then
    raise exception 'p_recorrencia_id obrigat3rio';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_rec
  from f.ap_recorrencia r
  where r.id = p_recorrencia_id
    and r.deleted_at is null;

  if not found then
    raise exception 'Recorr8ncia n3o encontrada';
  end if;

  v_tenant_id := v_rec.tenant_id;
  v_empresa_id := v_rec.empresa_id;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  if p_referencia_competencia is not null then
    v_ref_comp := f._month_first(p_referencia_competencia);
  else
    select t.competencia_date
      into v_ref_comp
    from f.titulo t
    where t.deleted_at is null
      and t.tenant_id = v_tenant_id
      and t.recorrencia_id = v_rec.id
    order by t.competencia_date desc nulls last
    limit 1;
  end if;

  if v_ref_comp is null then
    raise exception 'N3o h1 t1tulo de refer8ncia para esta recorr8ncia';
  end if;

  select t.valor_total
    into v_ref_valor
  from f.titulo t
  where t.deleted_at is null
    and t.tenant_id = v_tenant_id
    and t.recorrencia_id = v_rec.id
    and t.competencia_date = v_ref_comp
  order by t.created_at desc
  limit 1;

  if v_ref_valor is null or v_ref_valor <= 0 then
    raise exception 'Valor de refer8ncia inv1lido';
  end if;

  -- Atualiza apenas futuros ainda provisionados (PENDENTE) e sem pagamentos aplicados
  with futuros as (
    select t.id as titulo_id
    from f.titulo t
    where t.deleted_at is null
      and t.tenant_id = v_tenant_id
      and t.recorrencia_id = v_rec.id
      and t.competencia_date > v_ref_comp
      and t.status = 'PENDENTE'
  ), sem_pagamentos as (
    select f.titulo_id
    from futuros f
    where not exists (
      select 1
      from f.titulo_parcela tp
      join f.pagamento_item pi on pi.titulo_parcela_id = tp.id and pi.deleted_at is null
      where tp.titulo_id = f.titulo_id
        and tp.deleted_at is null
    )
  )
  update f.titulo t
     set valor_total = v_ref_valor,
         valor_aberto = v_ref_valor,
         updated_at = now(),
         updated_by = v_usuario_id
   where t.id in (select titulo_id from sem_pagamentos)
  returning 1 into v_count;

  -- Ajusta parcelas (valor + valor_aberto)
  update f.titulo_parcela tp
     set valor = v_ref_valor,
         valor_aberto = v_ref_valor,
         updated_at = now(),
         updated_by = v_usuario_id
   where tp.deleted_at is null
     and tp.titulo_id in (
       select t.id
       from f.titulo t
       where t.deleted_at is null
         and t.tenant_id = v_tenant_id
         and t.recorrencia_id = v_rec.id
         and t.competencia_date > v_ref_comp
         and t.status = 'PENDENTE'
     );

  return coalesce(v_count, 0);
end;
$$;


ALTER FUNCTION "f"."atualizar_proximos_ap_recorrencia"("p_recorrencia_id" "uuid", "p_referencia_competencia" "date", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."atualizar_titulo_emissao_date"("p_titulo_id" "uuid", "p_emissao_date" "date", "p_atualizar_competencia" boolean DEFAULT true, "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_t f.titulo%rowtype;
  v_user uuid;
  v_comp date;
begin
  if p_titulo_id is null then
    raise exception 'p_titulo_id obrigatorio';
  end if;

  if p_emissao_date is null then
    raise exception 'p_emissao_date obrigatorio';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_t
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_t.tenant_id, v_t.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();
  v_comp := f._month_first(p_emissao_date);

  update f.titulo
     set emissao_date = p_emissao_date,
         competencia_date = case when coalesce(p_atualizar_competencia, true) then v_comp else competencia_date end,
         updated_at = now(),
         updated_by = v_user
   where id = p_titulo_id;
end;
$$;


ALTER FUNCTION "f"."atualizar_titulo_emissao_date"("p_titulo_id" "uuid", "p_emissao_date" "date", "p_atualizar_competencia" boolean, "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
begin
  perform f.atualizar_titulo_parcela_vencimento_date(
    p_parcela_id => p_parcela_id,
    p_vencimento_date => p_vencimento_date,
    p_change_reason => null
  );
end;
$$;


ALTER FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_parcela f.titulo_parcela%rowtype;
  v_titulo f.titulo%rowtype;
  v_user uuid;
begin
  if p_parcela_id is null then
    raise exception 'p_parcela_id obrigatorio';
  end if;

  if p_vencimento_date is null then
    raise exception 'p_vencimento_date obrigatorio';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres', 'service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select *
    into v_parcela
  from f.titulo_parcela
  where id = p_parcela_id
    and deleted_at is null;

  if not found then
    raise exception 'Parcela nao encontrada (id=%)', p_parcela_id;
  end if;

  select *
    into v_titulo
  from f.titulo
  where id = v_parcela.titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado para parcela (id=%)', p_parcela_id;
  end if;

  if v_titulo.tipo not in ('AP', 'AR') then
    raise exception 'Somente parcelas AP/AR podem ser alteradas nesta operacao';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  if coalesce(v_parcela.valor_aberto, 0) <= 0 then
    raise exception 'Parcela liquidada; vencimento nao pode ser alterado';
  end if;

  v_user := a.fn_current_usuario_id();

  update f.titulo_parcela
     set vencimento_date = p_vencimento_date,
         updated_at = now(),
         updated_by = v_user
   where id = p_parcela_id;
end;
$$;


ALTER FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."cancelar_agendamento_ap"("p_titulo_id" "uuid", "p_motivo" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_user uuid;

  v_tem_agendamento boolean;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Cancelamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- fallback SQL Editor
  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  select exists(
    select 1
    from f.titulo_agendamento ta
    where ta.tenant_id = v_titulo.tenant_id
      and ta.titulo_id = v_titulo.id
      and ta.deleted_at is null
  ) into v_tem_agendamento;

  if not v_tem_agendamento then
    raise exception 'Nao existe agendamento ativo para este titulo';
  end if;

  -- soft delete do agendamento
  update f.titulo_agendamento
     set deleted_at = now(),
         updated_at = now(),
         updated_by = v_user
   where tenant_id = v_titulo.tenant_id
     and titulo_id = v_titulo.id
     and deleted_at is null;

  -- volta status: se tem saldo aberto, APROVADO; se não, PAGO
  update f.titulo
     set status = case when v_titulo.valor_aberto > 0 then 'APROVADO' else 'PAGO' end,
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'PAGAMENTO_AGENDADO_CANCELADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'motivo', p_motivo
    ),
    now(), v_user
  );
end;
$$;


ALTER FUNCTION "f"."cancelar_agendamento_ap"("p_titulo_id" "uuid", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."conciliar_pagamento_extrato"("p_extrato_linha_id" "uuid", "p_pagamento_id" "uuid", "p_referencia" "text" DEFAULT NULL::"text", "p_observacoes" "text" DEFAULT NULL::"text", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_linha f.extrato_bancario_linha%rowtype;
  v_pag f.pagamento%rowtype;

  v_user uuid;
  v_conc_id uuid;

  v_valor_mov numeric(15,2);
  v_valor_pag numeric(15,2);
  v_dif numeric(15,2);
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_linha
  from f.extrato_bancario_linha
  where id = p_extrato_linha_id
    and deleted_at is null;

  if not found then
    raise exception 'Extrato linha nao encontrada (id=%)', p_extrato_linha_id;
  end if;

  select * into v_pag
  from f.pagamento
  where id = p_pagamento_id
    and deleted_at is null;

  if not found then
    raise exception 'Pagamento nao encontrado/estornado (id=%)', p_pagamento_id;
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_pag.tenant_id, v_pag.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_pag.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  if v_linha.tenant_id <> v_pag.tenant_id then
    raise exception 'Tenant diferente entre extrato e pagamento';
  end if;

  if v_linha.conta_bancaria_id <> v_pag.conta_bancaria_id then
    raise exception 'Conta bancaria diferente entre extrato e pagamento';
  end if;

  -- MVP AP: extrato deve ser débito (negativo)
  if v_linha.valor >= 0 then
    raise exception 'Linha de extrato deve ser debito (valor negativo) para conciliar AP. Valor=%', v_linha.valor;
  end if;

  if v_linha.status <> 'PENDENTE' then
    raise exception 'Linha de extrato nao esta PENDENTE. Status atual=%', v_linha.status;
  end if;

  if v_pag.conciliado_at is not null then
    raise exception 'Pagamento ja conciliado (pagamento_id=%)', v_pag.id;
  end if;

  v_valor_mov := round(abs(v_linha.valor), 2);
  v_valor_pag := round(v_pag.valor, 2);
  v_dif := round(v_valor_mov - v_valor_pag, 2);

  insert into f.conciliacao_bancaria (
    tenant_id, empresa_id,
    conta_bancaria_id,
    extrato_linha_id,
    pagamento_id,
    referencia,
    status,
    valor_conciliado,
    diferenca,
    conciliado_em,
    conciliado_por,
    observacoes,
    change_reason,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    v_pag.conta_bancaria_id,
    v_linha.id,
    v_pag.id,
    p_referencia,
    'CONCILIADO',
    v_valor_pag,
    v_dif,
    now(),
    v_user,
    p_observacoes,
    p_change_reason,
    now(), now(), v_user, v_user
  )
  returning id into v_conc_id;

  update f.extrato_bancario_linha
     set status = 'CONCILIADO',
         updated_at = now(),
         updated_by = v_user
   where id = v_linha.id;

  update f.pagamento
     set conciliado_at = now(),
         conciliado_por = v_user,
         updated_at = now(),
         updated_by = v_user
   where id = v_pag.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    'PAGAMENTO_CONCILIADO',
    'f.conciliacao_bancaria',
    v_conc_id,
    jsonb_build_object(
      'extrato_linha_id', v_linha.id,
      'pagamento_id', v_pag.id,
      'valor_extrato', v_linha.valor,
      'valor_pagamento', v_pag.valor,
      'diferenca', v_dif,
      'referencia', p_referencia,
      'change_reason', p_change_reason
    ),
    now(), v_user
  );

  return v_conc_id;
end;
$$;


ALTER FUNCTION "f"."conciliar_pagamento_extrato"("p_extrato_linha_id" "uuid", "p_pagamento_id" "uuid", "p_referencia" "text", "p_observacoes" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."conciliar_por_sugestao_ap"("p_extrato_linha_id" "uuid", "p_score_min" integer DEFAULT 2, "p_referencia" "text" DEFAULT 'AUTO MATCH'::"text", "p_observacoes" "text" DEFAULT 'CONCILIADO VIA SUGESTAO'::"text", "p_change_reason" "text" DEFAULT 'AUTO-SUGESTAO'::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_status text;
  v_conc_id uuid;

  v_pagamento_id uuid;
  v_score integer;
begin
  -- 1) Se já está conciliado, devolve a conciliação ativa
  select el.status into v_status
  from f.extrato_bancario_linha el
  where el.id = p_extrato_linha_id
    and el.deleted_at is null;

  if v_status is null then
    raise exception 'Extrato linha nao encontrada (id=%)', p_extrato_linha_id;
  end if;

  if v_status = 'CONCILIADO' then
    select cb.id into v_conc_id
    from f.conciliacao_bancaria cb
    where cb.extrato_linha_id = p_extrato_linha_id
      and cb.deleted_at is null
    order by cb.created_at desc
    limit 1;

    if v_conc_id is null then
      raise exception 'Linha CONCILIADO mas sem conciliacao ativa (extrato_linha_id=%)', p_extrato_linha_id;
    end if;

    return v_conc_id;
  end if;

  if v_status = 'IGNORADO' then
    raise exception 'Linha do extrato esta IGNORADA. Desfaça/edite para conciliar (extrato_linha_id=%)', p_extrato_linha_id;
  end if;

  -- 2) PENDENTE: pega melhor sugestão
  select s.pagamento_id, s.score_data
    into v_pagamento_id, v_score
  from f.r_sugestoes_conciliacao_ap s
  where s.extrato_linha_id = p_extrato_linha_id
  order by s.score_data desc, s.data_pagamento desc
  limit 1;

  if v_pagamento_id is null then
    raise exception 'Nenhuma sugestao encontrada para extrato_linha_id=%', p_extrato_linha_id;
  end if;

  if v_score < coalesce(p_score_min, 0) then
    raise exception 'Melhor sugestao com score=% abaixo do minimo=%', v_score, p_score_min;
  end if;

  -- 3) Concilia de fato
  return f.conciliar_pagamento_extrato(
    p_extrato_linha_id,
    v_pagamento_id,
    p_referencia,
    p_observacoes,
    p_change_reason
  );
end;
$$;


ALTER FUNCTION "f"."conciliar_por_sugestao_ap"("p_extrato_linha_id" "uuid", "p_score_min" integer, "p_referencia" "text", "p_observacoes" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."criar_titulo_ap_manual"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer DEFAULT NULL::integer, "p_motivo_compra_id" "uuid" DEFAULT NULL::"uuid", "p_criar_recorrencia" boolean DEFAULT false, "p_dia_vencimento" integer DEFAULT NULL::integer, "p_auto_copiar_valor" boolean DEFAULT true, "p_change_reason" "text" DEFAULT NULL::"text") RETURNS TABLE("titulo_id" "uuid", "recorrencia_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;

  v_titulo_id uuid;
  v_recorrencia_id uuid;
  v_competencia date;
  v_day integer;
begin
  if p_descricao is null or length(trim(p_descricao)) = 0 then
    raise exception 'p_descricao obrigat3rio';
  end if;
  if p_vencimento_date is null then
    raise exception 'p_vencimento_date obrigat3rio';
  end if;
  if p_valor is null or p_valor <= 0 then
    raise exception 'p_valor deve ser > 0';
  end if;

  -- Auth: app ou SQL Editor
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  if v_tenant_id is null then
    raise exception 'Tenant n3o resolvido (current_tenant_id())';
  end if;
  if v_empresa_id is null then
    raise exception 'Empresa n3o resolvida (current_empresa_id())';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  v_competencia := f._month_first(p_vencimento_date);

  insert into f.titulo (
    tenant_id,
    empresa_id,
    tipo,
    status,
    fornecedor_id,
    descricao,
    emissao_date,
    competencia_date,
    valor_total,
    valor_aberto,
    motivo_compra_id,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
  ) values (
    v_tenant_id,
    v_empresa_id,
    'AP',
    'PENDENTE',
    p_fornecedor_id,
    trim(p_descricao),
    current_date,
    v_competencia,
    p_valor,
    p_valor,
    p_motivo_compra_id,
    now(),
    now(),
    v_usuario_id,
    v_usuario_id,
    null
  ) returning id into v_titulo_id;

  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
  ) values (
    v_tenant_id,
    v_titulo_id,
    '1',
    p_vencimento_date,
    p_valor,
    p_valor,
    now(),
    now(),
    v_usuario_id,
    v_usuario_id,
    null
  );

  if p_criar_recorrencia then
    v_day := coalesce(p_dia_vencimento, extract(day from p_vencimento_date)::int);

    insert into f.ap_recorrencia (
      tenant_id,
      empresa_id,
      fornecedor_id,
      descricao,
      motivo_compra_id,
      dia_vencimento,
      auto_copiar_valor,
      valor_base,
      ativo,
      created_at,
      updated_at,
      created_by,
      updated_by,
      deleted_at
    ) values (
      v_tenant_id,
      v_empresa_id,
      p_fornecedor_id,
      trim(p_descricao),
      p_motivo_compra_id,
      v_day,
      coalesce(p_auto_copiar_valor, true),
      p_valor,
      true,
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    ) returning id into v_recorrencia_id;

    update f.titulo
      set recorrencia_id = v_recorrencia_id,
          updated_at = now(),
          updated_by = v_usuario_id
    where id = v_titulo_id;
  end if;

  return query select v_titulo_id, v_recorrencia_id;
end;
$$;


ALTER FUNCTION "f"."criar_titulo_ap_manual"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."criar_titulo_ap_manual_v2"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer DEFAULT NULL::integer, "p_motivo_compra_id" "uuid" DEFAULT NULL::"uuid", "p_emissao_date" "date" DEFAULT NULL::"date", "p_criar_recorrencia" boolean DEFAULT false, "p_dia_vencimento" integer DEFAULT NULL::integer, "p_auto_copiar_valor" boolean DEFAULT true, "p_change_reason" "text" DEFAULT NULL::"text") RETURNS TABLE("titulo_id" "uuid", "recorrencia_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;

  v_titulo_id uuid;
  v_recorrencia_id uuid;

  v_emissao date;
  v_competencia date;
  v_day integer;
begin
  if p_descricao is null or length(trim(p_descricao)) = 0 then
    raise exception 'p_descricao obrigatorio';
  end if;

  if p_vencimento_date is null then
    raise exception 'p_vencimento_date obrigatorio';
  end if;

  if p_valor is null or p_valor <= 0 then
    raise exception 'p_valor deve ser > 0';
  end if;

  -- Auth: app ou SQL Editor
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null then
    raise exception 'Tenant nao resolvido (current_tenant_id())';
  end if;

  if v_empresa_id is null then
    raise exception 'Empresa nao resolvida (current_empresa_id())';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permissao financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  -- data da NF (emissão). Se não vier, usa vencimento como “melhor chute” (melhor que current_date).
  v_emissao := coalesce(
    p_emissao_date,
    p_vencimento_date,
    (now() at time zone 'America/Sao_Paulo')::date
  );

  -- competência baseada na emissão (se informada), mantendo padrão day=1
  v_competencia := f._month_first(v_emissao);

  insert into f.titulo (
    tenant_id,
    empresa_id,
    tipo,
    status,
    origem,
    fornecedor_id,
    descricao,
    emissao_date,
    competencia_date,
    valor_total,
    valor_aberto,
    motivo_compra_id,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
  ) values (
    v_tenant_id,
    v_empresa_id,
    'AP',
    'PENDENTE',
    'MANUAL',
    p_fornecedor_id,
    trim(p_descricao),
    v_emissao,
    v_competencia,
    p_valor,
    p_valor,
    p_motivo_compra_id,
    now(),
    now(),
    v_usuario_id,
    v_usuario_id,
    null
  ) returning id into v_titulo_id;

  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
  ) values (
    v_tenant_id,
    v_titulo_id,
    '1',
    p_vencimento_date,
    p_valor,
    p_valor,
    now(),
    now(),
    v_usuario_id,
    v_usuario_id,
    null
  );

  if p_criar_recorrencia then
    v_day := coalesce(p_dia_vencimento, extract(day from p_vencimento_date)::int);

    insert into f.ap_recorrencia (
      tenant_id,
      empresa_id,
      fornecedor_id,
      descricao,
      motivo_compra_id,
      dia_vencimento,
      auto_copiar_valor,
      valor_base,
      ativo,
      created_at,
      updated_at,
      created_by,
      updated_by,
      deleted_at
    ) values (
      v_tenant_id,
      v_empresa_id,
      p_fornecedor_id,
      trim(p_descricao),
      p_motivo_compra_id,
      v_day,
      coalesce(p_auto_copiar_valor, true),
      p_valor,
      true,
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    ) returning id into v_recorrencia_id;

    update f.titulo
      set recorrencia_id = v_recorrencia_id,
          updated_at = now(),
          updated_by = v_usuario_id
    where id = v_titulo_id;
  end if;

  return query select v_titulo_id, v_recorrencia_id;
end;
$$;


ALTER FUNCTION "f"."criar_titulo_ap_manual_v2"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_emissao_date" "date", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."desconciliar_pagamento_extrato"("p_conciliacao_id" "uuid", "p_motivo" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_conc f.conciliacao_bancaria%rowtype;
  v_user uuid;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_conc
  from f.conciliacao_bancaria
  where id = p_conciliacao_id
    and deleted_at is null;

  if not found then
    raise exception 'Conciliacao nao encontrada/ja desfeita (id=%)', p_conciliacao_id;
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_conc.tenant_id, v_conc.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_conc.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- desfaz conciliação (mantém histórico)
  update f.conciliacao_bancaria
     set status = 'DESCONCILIADO',
         deleted_at = now(),
         updated_at = now(),
         updated_by = v_user
   where id = v_conc.id;

  -- volta linha para pendente (se existir)
  update f.extrato_bancario_linha
     set status = 'PENDENTE',
         updated_at = now(),
         updated_by = v_user
   where id = v_conc.extrato_linha_id
     and deleted_at is null;

  -- limpa conciliação no pagamento (se existir)
  update f.pagamento
     set conciliado_at = null,
         conciliado_por = null,
         updated_at = now(),
         updated_by = v_user
   where id = v_conc.pagamento_id
     and deleted_at is null;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_conc.tenant_id, v_conc.empresa_id,
    'PAGAMENTO_DESCONCILIADO',
    'f.conciliacao_bancaria',
    v_conc.id,
    jsonb_build_object(
      'motivo', p_motivo,
      'extrato_linha_id', v_conc.extrato_linha_id,
      'pagamento_id', v_conc.pagamento_id
    ),
    now(), v_user
  );
end;
$$;


ALTER FUNCTION "f"."desconciliar_pagamento_extrato"("p_conciliacao_id" "uuid", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."desdobrar_parcela_ar_para_recebimento"("p_parcela_id" "uuid", "p_valor_receber" numeric, "p_novo_vencimento_date" "date" DEFAULT NULL::"date", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_parcela f.titulo_parcela%rowtype;
  v_titulo f.titulo%rowtype;
  v_user uuid;
  v_receber numeric(15,2);
  v_remanescente numeric(15,2);
  v_new_numero text;
  v_new_parcela_id uuid;
begin
  if p_parcela_id is null then
    raise exception 'p_parcela_id obrigatorio';
  end if;

  if p_valor_receber is null or p_valor_receber <= 0 then
    raise exception 'p_valor_receber deve ser > 0';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres', 'service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select p.*
    into v_parcela
  from f.titulo_parcela p
  where p.id = p_parcela_id
    and p.deleted_at is null
  for update;

  if not found then
    raise exception 'Parcela nao encontrada (id=%)', p_parcela_id;
  end if;

  select *
    into v_titulo
  from f.titulo
  where id = v_parcela.titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado para parcela (id=%)', p_parcela_id;
  end if;

  if v_titulo.tipo <> 'AR' then
    raise exception 'Desdobramento permitido somente para AR';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  if coalesce(v_parcela.valor_aberto, 0) <= 0 then
    raise exception 'Parcela sem saldo em aberto';
  end if;

  if round(coalesce(v_parcela.valor_aberto, 0), 2) <> round(coalesce(v_parcela.valor, 0), 2) then
    raise exception 'Desdobramento permitido apenas para parcela sem recebimentos anteriores';
  end if;

  v_receber := round(p_valor_receber, 2);
  if v_receber >= round(v_parcela.valor_aberto, 2) then
    raise exception 'Valor a receber deve ser menor que saldo aberto da parcela';
  end if;

  v_remanescente := round(v_parcela.valor_aberto - v_receber, 2);
  if v_remanescente <= 0 then
    raise exception 'Saldo remanescente invalido';
  end if;

  select lpad(
           (
             coalesce(
               max(
                 case
                   when regexp_replace(coalesce(numero, ''), '\D', '', 'g') <> ''
                     then regexp_replace(numero, '\D', '', 'g')::int
                   else null
                 end
               ),
               0
             ) + 1
           )::text,
           3,
           '0'
         )
    into v_new_numero
  from f.titulo_parcela
  where tenant_id = v_parcela.tenant_id
    and titulo_id = v_parcela.titulo_id
    and deleted_at is null;

  v_user := a.fn_current_usuario_id();

  update f.titulo_parcela
     set valor = v_receber,
         valor_aberto = v_receber,
         updated_at = now(),
         updated_by = v_user
   where id = v_parcela.id;

  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by
  )
  values (
    v_parcela.tenant_id,
    v_parcela.titulo_id,
    v_new_numero,
    coalesce(p_novo_vencimento_date, v_parcela.vencimento_date),
    v_remanescente,
    v_remanescente,
    now(),
    now(),
    v_user,
    v_user
  )
  returning id into v_new_parcela_id;

  return v_new_parcela_id;
end;
$$;


ALTER FUNCTION "f"."desdobrar_parcela_ar_para_recebimento"("p_parcela_id" "uuid", "p_valor_receber" numeric, "p_novo_vencimento_date" "date", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."estornar_pagamento_ap"("p_pagamento_id" "uuid", "p_motivo" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_pag f.pagamento%rowtype;
  v_user uuid;

  r record;

  v_titulo_id uuid;
  v_titulo f.titulo%rowtype;
  v_soma_aberto numeric(15,2);
begin
  -- auth: app ou SQL Editor (postgres/service_role)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- carrega pagamento
  select * into v_pag
  from f.pagamento
  where id = p_pagamento_id
    and (deleted_at is null);

  if not found then
    raise exception 'Pagamento nao encontrado/ja estornado (id=%)', p_pagamento_id;
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_pag.tenant_id, v_pag.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- fallback usuário (SQL Editor)
  if v_user is null then
    select ut.usuario_id
      into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_pag.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- devolve valor para cada parcela vinculada
  for r in
    select pi.id as pagamento_item_id,
           pi.valor as valor_aplicado,
           tp.id as parcela_id,
           tp.titulo_id as titulo_id
    from f.pagamento_item pi
    join f.titulo_parcela tp on tp.id = pi.titulo_parcela_id
    where pi.pagamento_id = v_pag.id
      and pi.tenant_id = v_pag.tenant_id
      and (pi.deleted_at is null)
      and (tp.deleted_at is null)
  loop
    -- guarda um titulo_id para recalcular ao final (assumimos 1 título por pagamento, que é o padrão aqui)
    v_titulo_id := r.titulo_id;

    update f.titulo_parcela
       set valor_aberto = round(valor_aberto + r.valor_aplicado, 2),
           updated_at = now(),
           updated_by = v_user
     where id = r.parcela_id;

    -- soft delete no item
    update f.pagamento_item
       set deleted_at = now()
     where id = r.pagamento_item_id;
  end loop;

  if v_titulo_id is null then
    raise exception 'Pagamento sem itens vinculados (pagamento_id=%)', v_pag.id;
  end if;

  -- soft delete no pagamento
  update f.pagamento
     set deleted_at = now(),
         updated_at = now(),
         updated_by = v_user
   where id = v_pag.id;

  -- recalcula título
  select * into v_titulo
  from f.titulo
  where id = v_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo do pagamento nao encontrado (titulo_id=%)', v_titulo_id;
  end if;

  select coalesce(sum(valor_aberto),0)::numeric(15,2)
    into v_soma_aberto
  from f.titulo_parcela
  where tenant_id = v_titulo.tenant_id
    and titulo_id = v_titulo.id
    and deleted_at is null;

  update f.titulo
     set valor_aberto = v_soma_aberto,
         status = case
                   when v_soma_aberto = 0 then 'PAGO'
                   else 'APROVADO'
                 end,
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  -- eventos
  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    'PAGAMENTO_ESTORNADO',
    'f.pagamento',
    v_pag.id,
    jsonb_build_object(
      'motivo', p_motivo,
      'titulo_id', v_titulo.id,
      'saldo_titulo_pos', v_soma_aberto
    ),
    now(), v_user
  );

  insert into f.aprovacao_evento (
    tenant_id, empresa_id,
    acao, ref_table, ref_id,
    motivo, payload,
    created_at, created_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    'REPROVOU',              -- usamos esse "tipo" como evento administrativo/financeiro
    'f.pagamento',
    v_pag.id,
    'ESTORNO',
    jsonb_build_object(
      'motivo', p_motivo,
      'titulo_id', v_titulo.id,
      'pagamento_id', v_pag.id
    ),
    now(), v_user
  );

end;
$$;


ALTER FUNCTION "f"."estornar_pagamento_ap"("p_pagamento_id" "uuid", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_aplicar_credito_fiscal_manual_titulo"("p_titulo_id" "uuid", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS TABLE("status" "text", "message" "text", "lancamentos_gerados" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_generated integer := 0;
  v_base numeric(15,2);
  v_imp text;
  v_rule record;
  v_comp_base date;
  v_parcelas integer;
  v_i integer;
  v_valor_total numeric(15,2);
  v_valor_parcela numeric(15,2);
  v_valor_last numeric(15,2);
  v_comp date;
begin
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.deleted_at is not null then
    update f.credito_fiscal_manual_lancamento
       set status = 'CANCELADO',
           deleted_at = now(),
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
     where tenant_id = v_titulo.tenant_id
       and titulo_id = v_titulo.id
       and deleted_at is null;

    status := 'ok';
    message := 'Titulo removido: lancamentos fiscais manuais cancelados.';
    lancamentos_gerados := 0;
    return next;
    return;
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from v_titulo.tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if public.current_empresa_id() is distinct from v_titulo.empresa_id then
      raise exception 'Empresa mismatch';
    end if;
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- Apenas AP manual sem documento fiscal (cenario energia/leasing/boletos)
  if v_titulo.tipo <> 'AP' or upper(coalesce(v_titulo.origem,'')) <> 'MANUAL' or v_titulo.documento_fiscal_id is not null then
    update f.credito_fiscal_manual_lancamento
       set status = 'CANCELADO',
           deleted_at = now(),
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
     where tenant_id = v_titulo.tenant_id
       and titulo_id = v_titulo.id
       and deleted_at is null;

    status := 'ok';
    message := 'Titulo fora do escopo de credito fiscal manual.';
    lancamentos_gerados := 0;
    return next;
    return;
  end if;

  v_base := round(coalesce(v_titulo.valor_total,0),2);
  if v_base <= 0 then
    status := 'ok';
    message := 'Titulo sem base para credito.';
    lancamentos_gerados := 0;
    return next;
    return;
  end if;

  update f.credito_fiscal_manual_lancamento
     set status = 'CANCELADO',
         deleted_at = now(),
         updated_at = now(),
         updated_by = a.fn_current_usuario_id()
   where tenant_id = v_titulo.tenant_id
     and titulo_id = v_titulo.id
     and deleted_at is null;

  foreach v_imp in array array['ICMS','PIS','COFINS']
  loop
    select * into v_rule
    from f.fn_pick_credito_fiscal_manual_regra(
      v_titulo.tenant_id,
      v_titulo.empresa_id,
      v_imp,
      v_titulo.origem,
      v_titulo.descricao,
      v_titulo.motivo_compra_id,
      v_titulo.fornecedor_id
    )
    limit 1;

    if v_rule.modo is null then
      continue;
    end if;

    v_comp_base := coalesce(v_titulo.competencia_date, date_trunc('month', coalesce(v_titulo.emissao_date, current_date))::date);
    v_comp_base := (v_comp_base + make_interval(months => coalesce(v_rule.competencia_offset_meses,0)))::date;

    if v_rule.modo = 'NAO_CREDITA' then
      continue;
    end if;

    if v_rule.modo = 'PENDENTE_REVISAO' then
      insert into f.credito_fiscal_manual_lancamento(
        tenant_id, empresa_id, titulo_id, regra_id, imposto, natureza,
        competencia_date, base_calculo, aliquota, valor_credito, modo, status,
        created_by, updated_by
      ) values (
        v_titulo.tenant_id, v_titulo.empresa_id, v_titulo.id, v_rule.regra_id, v_imp, 'CREDITO',
        v_comp_base, v_base, coalesce(v_rule.aliquota,0), round(v_base * coalesce(v_rule.aliquota,0) / 100, 2), v_rule.modo, 'PENDENTE_REVISAO',
        a.fn_current_usuario_id(), a.fn_current_usuario_id()
      )
      on conflict do nothing;
      continue;
    end if;

    v_valor_total := round(v_base * coalesce(v_rule.aliquota,0) / 100, 2);
    if v_valor_total <= 0 then
      continue;
    end if;

    v_parcelas := case when v_rule.modo = 'CREDITA_PARCELADO' then greatest(1, coalesce(v_rule.parcelas_apropriacao,1)) else 1 end;

    if v_parcelas = 1 then
      insert into f.credito_fiscal_manual_lancamento(
        tenant_id, empresa_id, titulo_id, regra_id, imposto, natureza,
        competencia_date, base_calculo, aliquota, valor_credito, modo, status,
        created_by, updated_by
      ) values (
        v_titulo.tenant_id, v_titulo.empresa_id, v_titulo.id, v_rule.regra_id, v_imp, 'CREDITO',
        v_comp_base, v_base, coalesce(v_rule.aliquota,0), v_valor_total, v_rule.modo, 'PROVISIONADO',
        a.fn_current_usuario_id(), a.fn_current_usuario_id()
      )
      on conflict do nothing;
      v_generated := v_generated + 1;
    else
      v_valor_parcela := round(v_valor_total / v_parcelas, 2);
      v_valor_last := v_valor_total - (v_valor_parcela * (v_parcelas - 1));

      for v_i in 0..(v_parcelas - 1)
      loop
        v_comp := (v_comp_base + make_interval(months => v_i))::date;

        insert into f.credito_fiscal_manual_lancamento(
          tenant_id, empresa_id, titulo_id, regra_id, imposto, natureza,
          competencia_date, base_calculo, aliquota, valor_credito, modo, status,
          created_by, updated_by
        ) values (
          v_titulo.tenant_id, v_titulo.empresa_id, v_titulo.id, v_rule.regra_id, v_imp, 'CREDITO',
          v_comp,
          case when v_i = v_parcelas - 1 then v_base - (round(v_base / v_parcelas, 2) * (v_parcelas - 1)) else round(v_base / v_parcelas, 2) end,
          coalesce(v_rule.aliquota,0),
          case when v_i = v_parcelas - 1 then v_valor_last else v_valor_parcela end,
          v_rule.modo,
          'PROVISIONADO',
          a.fn_current_usuario_id(), a.fn_current_usuario_id()
        )
        on conflict do nothing;

        v_generated := v_generated + 1;
      end loop;
    end if;
  end loop;

  status := 'ok';
  message := coalesce(p_change_reason, 'Credito fiscal manual reaplicado ao titulo.');
  lancamentos_gerados := v_generated;
  return next;
end;
$$;


ALTER FUNCTION "f"."fn_aplicar_credito_fiscal_manual_titulo"("p_titulo_id" "uuid", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_arrendamento_gerar_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f', 'a'
    AS $$
declare
  v_c f.arrendamento_contrato%rowtype;
  v_motivo_id uuid;
  v_plano_id uuid;
  v_titulo_id uuid;
  v_aprovado_por uuid;
  r record;
begin
  select *
    into v_c
    from f.arrendamento_contrato c
   where c.tenant_id = p_tenant_id
     and c.empresa_id = p_empresa_id
     and c.id = p_contrato_id
     and c.deleted_at is null;

  if not found then
    raise exception 'Contrato de arrendamento não encontrado (%).', p_contrato_id;
  end if;

  -- tenta pegar usuário logado (app)
  v_aprovado_por := a.fn_current_usuario_id();

  -- fallback (SQL editor): pega QUALQUER usuário do tenant via a.usuario_tenant
  if v_aprovado_por is null then
    select ut.usuario_id
      into v_aprovado_por
      from a.usuario_tenant ut
     where ut.tenant_id = p_tenant_id
       and ut.ativo = true
       and ut.deleted_at is null
     order by ut.created_at nulls last
     limit 1;

    if v_aprovado_por is null then
      raise exception
        'Nao foi possivel determinar aprovado_por (sem usuário autenticado e sem usuario_tenant ativo). Execute pelo app.';
    end if;
  end if;

  -- garante parcelas
  perform f.fn_arrendamento_gerar_parcelas(p_tenant_id, p_empresa_id, p_contrato_id);

  -- motivo padrão: OPEX_ARRENDAMENTO (se contrato não tiver)
  select coalesce(v_c.motivo_compra_id, mc.id)
    into v_motivo_id
    from f.motivo_compra mc
   where mc.tenant_id = p_tenant_id
     and mc.codigo = 'OPEX_ARRENDAMENTO'
     and mc.deleted_at is null
   limit 1;

  if v_motivo_id is null then
    raise exception 'Motivo OPEX_ARRENDAMENTO não encontrado no tenant %.', p_tenant_id;
  end if;

  select plano_contas_id
    into v_plano_id
    from f.motivo_compra
   where id = v_motivo_id
     and deleted_at is null;

  for r in
    select ap.*
      from f.arrendamento_parcela ap
     where ap.tenant_id = p_tenant_id
       and ap.empresa_id = p_empresa_id
       and ap.contrato_id = p_contrato_id
       and ap.deleted_at is null
       and ap.titulo_id is null
     order by ap.competencia_date
  loop
    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem,
      fornecedor_id,
      descricao,
      emissao_date,
      competencia_date,
      valor_total,
      valor_aberto,
      motivo_compra_id,
      arrendamento_contrato_id
    )
    values (
      p_tenant_id, p_empresa_id,
      'AP', 'PENDENTE', 'ARRENDAMENTO',
      v_c.fornecedor_id,
      ('ARRENDAMENTO/LEASING - ' || v_c.descricao || ' - ' || to_char(r.competencia_date, 'YYYY-MM')),
      r.competencia_date,
      r.competencia_date,
      r.valor,
      r.valor,
      v_motivo_id,
      p_contrato_id
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (
      tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto
    )
    values (
      p_tenant_id, v_titulo_id, '1/1', r.vencimento_date, r.valor, r.valor
    );

    insert into f.titulo_aprovacao (
      tenant_id, titulo_id, motivo_compra_id, motivo_outros_text, os_id,
      aprovado_em, aprovado_por
    )
    values (
      p_tenant_id, v_titulo_id, v_motivo_id, null, v_c.os_id,
      now(), v_aprovado_por
    );

    -- ✅ FIX anti-duplicação:
    -- Só cria rateio se ainda não existir nenhum rateio ativo para o título.
    if v_plano_id is not null then
      if not exists (
        select 1
          from f.titulo_rateio tr
         where tr.tenant_id = p_tenant_id
           and tr.titulo_id = v_titulo_id
           and tr.deleted_at is null
      ) then
        insert into f.titulo_rateio (
          tenant_id, titulo_id, plano_contas_id, centro_custo_id, os_id, percentual, valor
        )
        values (
          p_tenant_id, v_titulo_id, v_plano_id, v_c.centro_custo_id, v_c.os_id, 100::numeric(7,4), r.valor
        );
      end if;
    end if;

    update f.arrendamento_parcela
       set titulo_id = v_titulo_id,
           updated_at = now()
     where id = r.id;
  end loop;

end;
$$;


ALTER FUNCTION "f"."fn_arrendamento_gerar_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_arrendamento_gerar_parcelas"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f'
    AS $$
declare
  v_c f.arrendamento_contrato%rowtype;
  i integer;
  v_comp date;
  v_venc date;
  v_last_day date;
begin
  select *
    into v_c
    from f.arrendamento_contrato c
   where c.tenant_id = p_tenant_id
     and c.empresa_id = p_empresa_id
     and c.id = p_contrato_id
     and c.deleted_at is null;

  if not found then
    raise exception 'Contrato de arrendamento não encontrado (%).', p_contrato_id;
  end if;

  if extract(day from v_c.competencia_inicio) <> 1 then
    raise exception 'competencia_inicio deve ser dia 01 (recebido: %).', v_c.competencia_inicio;
  end if;

  for i in 1..v_c.prazo_meses loop
    v_comp := (v_c.competencia_inicio + ((i-1) || ' months')::interval)::date;

    -- vencimento: dia fixo limitado ao último dia do mês
    v_last_day := (date_trunc('month', v_comp)::date + interval '1 month - 1 day')::date;
    v_venc := make_date(extract(year from v_comp)::int, extract(month from v_comp)::int, 1);
    v_venc := (v_venc + (least(v_c.dia_vencimento, extract(day from v_last_day)::int) - 1))::date;

    insert into f.arrendamento_parcela (
      tenant_id, empresa_id, contrato_id,
      competencia_date, numero, vencimento_date, valor
    )
    values (
      p_tenant_id, p_empresa_id, p_contrato_id,
      v_comp, i, v_venc, v_c.valor_parcela
    )
    on conflict (tenant_id, contrato_id, competencia_date)
    where deleted_at is null
    do update set
      numero = excluded.numero,
      vencimento_date = excluded.vencimento_date,
      valor = excluded.valor,
      updated_at = now(),
      deleted_at = null;
  end loop;

  update f.arrendamento_contrato
     set updated_at = now()
   where tenant_id = p_tenant_id
     and empresa_id = p_empresa_id
     and id = p_contrato_id;

end;
$$;


ALTER FUNCTION "f"."fn_arrendamento_gerar_parcelas"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_backfill_irpj_csll_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_from" "date", "p_to" "date") RETURNS TABLE("competencia_date" "date", "status" "text", "detalhe" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f', 'r'
    AS $$
declare
  d record;
begin
  for d in
    select distinct a.competencia_date
    from r.r_apuracao_irpj_csll_mensal_comp2 a
    where a.tenant_id = p_tenant_id
      and a.empresa_id = p_empresa_id
      and a.competencia_date between p_from and p_to
    order by a.competencia_date
  loop
    begin
      perform f.fn_irpj_csll_ao_fechar_competencia(p_tenant_id, p_empresa_id, d.competencia_date);
      competencia_date := d.competencia_date;
      status := 'OK';
      detalhe := null;
      return next;
    exception when others then
      competencia_date := d.competencia_date;
      status := 'ERRO';
      detalhe := sqlerrm;
      return next;
    end;
  end loop;
end;
$$;


ALTER FUNCTION "f"."fn_backfill_irpj_csll_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_calc_vencimento"("p_tenant_id" "uuid", "p_regra_id" "uuid", "p_competencia_date" "date") RETURNS "date"
    LANGUAGE "plpgsql"
    AS $$
declare
  r record;
  v_last_next date;
  v_due date;
begin
  -- último dia do mês seguinte (fallback)
  v_last_next := (date_trunc('month', p_competencia_date)::date + interval '2 months - 1 day')::date;

  if p_regra_id is null then
    return v_last_next;
  end if;

  select vr.tipo, vr.dia
    into r
  from f.vencimento_regra vr
  where vr.tenant_id = p_tenant_id
    and vr.id = p_regra_id
    and vr.ativo = true
    and vr.deleted_at is null
  limit 1;

  if not found then
    return v_last_next;
  end if;

  if r.tipo = 'M1_ULTIMO_DIA' then
    return v_last_next;
  end if;

  if r.tipo = 'M1_DIA_FIXO' then
    -- dia fixo no mês seguinte, com "clamp" para o último dia do mês
    v_due := make_date(
      extract(year from v_last_next)::int,
      extract(month from v_last_next)::int,
      least(r.dia::int, extract(day from v_last_next)::int)
    );
    return v_due;
  end if;

  return v_last_next;
end;
$$;


ALTER FUNCTION "f"."fn_calc_vencimento"("p_tenant_id" "uuid", "p_regra_id" "uuid", "p_competencia_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_documento_fiscal__sync_xml_pendencia"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_xml_ok boolean;
begin
  -- ignora soft delete
  if new.deleted_at is not null then
    return new;
  end if;

  -- só NF-e: chave 44 e natureza PRODUTO (ajuste se quiser cobrir outros casos)
  if new.natureza <> 'PRODUTO' then
    return new;
  end if;

  if length(new.chave_acesso) <> 44 then
    return new;
  end if;

  select (
    exists (
      select 1
      from f.documento_fiscal_xml dfx
      where dfx.tenant_id = new.tenant_id
        and dfx.documento_fiscal_id = new.id
        and dfx.deleted_at is null
        and nullif(btrim(dfx.xml_raw), '') is not null
    )
    or
    exists (
      select 1
      from public.nf_entrada ne
      where ne.tenant_id = new.tenant_id
        and ne.id = new.source_nf_entrada_id
        and nullif(btrim(ne.xml_raw), '') is not null
    )
  ) into v_xml_ok;

  if not v_xml_ok then
    insert into f.documento_fiscal_pendencia (
      tenant_id, empresa_id, documento_fiscal_id, tipo, detalhe
    ) values (
      new.tenant_id, new.empresa_id, new.id, 'XML_FALTANDO',
      'Documento fiscal NF-e (chave 44) sem XML em nf_entrada.xml_raw e sem backup em f.documento_fiscal_xml.'
    )
    on conflict on constraint uq_doc_pend
    do update set
      detalhe = excluded.detalhe,
      updated_at = now(),
      resolved_at = null;
  else
    update f.documento_fiscal_pendencia
    set resolved_at = now(),
        updated_at = now()
    where tenant_id = new.tenant_id
      and documento_fiscal_id = new.id
      and tipo = 'XML_FALTANDO'
      and resolved_at is null;
  end if;

  return new;
end $$;


ALTER FUNCTION "f"."fn_documento_fiscal__sync_xml_pendencia"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_ensure_documento_fiscal_from_nf_entrada"("p_nf_entrada_id" bigint) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'extensions'
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_df_id uuid;
  v_emissao_date date;
  v_competencia date;
  v_xml_hash text;
begin
  select *
    into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada não encontrada: %', p_nf_entrada_id;
  end if;

  -- 1) Se já existe DF por source_nf_entrada_id, retorna
  select df.id
    into v_df_id
  from f.documento_fiscal df
  where df.tenant_id = v_nf.tenant_id
    and df.empresa_id = v_nf.empresa_id
    and df.source_nf_entrada_id = v_nf.id
    and df.deleted_at is null
  order by df.created_at desc
  limit 1;

  -- 2) Se não achou, tenta por chave_acesso (e cola o source_nf_entrada_id)
  if v_df_id is null then
    select df.id
      into v_df_id
    from f.documento_fiscal df
    where df.tenant_id = v_nf.tenant_id
      and df.empresa_id = v_nf.empresa_id
      and df.chave_acesso = v_nf.chave
      and df.deleted_at is null
    order by df.created_at desc
    limit 1;

    if v_df_id is not null then
      update f.documento_fiscal
         set source_nf_entrada_id = v_nf.id,
             updated_at = now(),
             updated_by = a.fn_current_usuario_id()
       where id = v_df_id
         and source_nf_entrada_id is null;
    end if;
  end if;

  -- 3) Se ainda não achou, cria DF mínimo
  if v_df_id is null then
    v_emissao_date := (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date;
    if v_emissao_date is null then
      v_emissao_date := (now() at time zone 'America/Sao_Paulo')::date;
    end if;

    v_competencia := date_trunc('month', v_emissao_date)::date;

    insert into f.documento_fiscal (
      id,
      tenant_id,
      empresa_id,
      modelo,
      serie,
      numero,
      chave_acesso,
      emissao_date,
      competencia_date,
      valor_total,
      operacao,
      natureza,
      source_nf_entrada_id,
      created_at,
      updated_at,
      created_by,
      updated_by
    ) values (
      gen_random_uuid(),
      v_nf.tenant_id,
      v_nf.empresa_id,
      null,
      v_nf.serie,
      v_nf.numero,
      v_nf.chave,
      v_emissao_date,
      v_competencia,
      coalesce(v_nf.valor_total, 0),
      'ENTRADA',
      'PRODUTO',
      v_nf.id,
      now(),
      now(),
      a.fn_current_usuario_id(),
      a.fn_current_usuario_id()
    )
    returning id into v_df_id;
  end if;

  -- 4) ✅ GARANTIR documento_fiscal_xml se xml_raw existir e não estiver vazio
  if v_nf.xml_raw is not null and nullif(btrim(v_nf.xml_raw), '') is not null then
    begin
      -- tenta extensions.digest (se existir no seu ambiente)
      v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');
    exception when others then
      v_xml_hash := null;
    end;

    insert into f.documento_fiscal_xml (
      tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash
    ) values (
      v_nf.tenant_id, v_df_id, v_nf.chave, v_nf.xml_raw, v_xml_hash
    )
    on conflict (tenant_id, documento_fiscal_id)
    do update set
      chave_acesso = excluded.chave_acesso,
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  return v_df_id;
end;
$$;


ALTER FUNCTION "f"."fn_ensure_documento_fiscal_from_nf_entrada"("p_nf_entrada_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_find_documento_fiscal_from_import"("p_nf_entrada_id" bigint) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'extensions'
    AS $$
begin
  return f.fn_ensure_documento_fiscal_from_nf_entrada(p_nf_entrada_id);
end;
$$;


ALTER FUNCTION "f"."fn_find_documento_fiscal_from_import"("p_nf_entrada_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_find_documento_fiscal_from_import"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nf_entrada_id" bigint, "p_chave_acesso" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c', 'extensions'
    SET "row_security" TO 'off'
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_doc_id uuid;
  v_competencia date;
  v_xml_hash text;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_nf_entrada_id is null and (p_chave_acesso is null or length(trim(p_chave_acesso)) = 0) then
    raise exception 'Informe p_nf_entrada_id ou p_chave_acesso';
  end if;

  if p_nf_entrada_id is not null then
    select * into v_nf
    from public.nf_entrada
    where id = p_nf_entrada_id;
  else
    select * into v_nf
    from public.nf_entrada
    where chave = p_chave_acesso
    limit 1;
  end if;

  if not found then
    raise exception 'NF entrada nao encontrada';
  end if;

  if p_tenant_id is not null and v_nf.tenant_id <> p_tenant_id then
    raise exception 'Tenant mismatch';
  end if;

  if p_empresa_id is not null and v_nf.empresa_id <> p_empresa_id then
    raise exception 'Empresa mismatch';
  end if;

  -- Allow finance users OR xml import executors.
  if auth.uid() is not null then
    if not f.has_finance_access(v_nf.tenant_id, v_nf.empresa_id)
       and not public.can('xml_import', 'execute', v_nf.tenant_id)
    then
      raise exception 'Sem permissao para importacao XML';
    end if;
  end if;

  v_competencia := date_trunc(
    'month',
    coalesce((v_nf.data_emissao at time zone 'America/Sao_Paulo')::date, current_date)
  )::date;

  insert into f.documento_fiscal (
    tenant_id, empresa_id, source_nf_entrada_id,
    fornecedor_id, chave_acesso,
    modelo, serie, numero,
    emissao_date, competencia_date,
    valor_total, valor_produtos, valor_frete, valor_seguro, valor_desconto, valor_outros,
    finalidade_import, os_id_import,
    pagamento_import_json
  )
  values (
    v_nf.tenant_id, v_nf.empresa_id, v_nf.id,
    v_nf.fornecedor_id::int, v_nf.chave,
    null, v_nf.serie, v_nf.numero,
    (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
    v_competencia,
    coalesce(v_nf.valor_total, 0),
    coalesce(v_nf.valor_produtos, 0),
    coalesce(v_nf.valor_frete, 0),
    coalesce(v_nf.valor_seguro, 0),
    coalesce(v_nf.valor_desconto, 0),
    coalesce(v_nf.valor_outros, 0),
    v_nf.finalidade_contexto,
    v_nf.os_id,
    null
  )
  on conflict (tenant_id, source_nf_entrada_id)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    chave_acesso = excluded.chave_acesso,
    serie = excluded.serie,
    numero = excluded.numero,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    valor_produtos = excluded.valor_produtos,
    valor_frete = excluded.valor_frete,
    valor_seguro = excluded.valor_seguro,
    valor_desconto = excluded.valor_desconto,
    valor_outros = excluded.valor_outros,
    finalidade_import = excluded.finalidade_import,
    os_id_import = excluded.os_id_import,
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  returning id into v_doc_id;

  if v_nf.xml_raw is not null and length(v_nf.xml_raw) > 0 then
    v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');

    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_nf.tenant_id, v_doc_id, v_nf.chave, v_nf.xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id) do update set
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  return v_doc_id;
end;
$$;


ALTER FUNCTION "f"."fn_find_documento_fiscal_from_import"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nf_entrada_id" bigint, "p_chave_acesso" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_gerar_ap_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date" DEFAULT NULL::"date") RETURNS TABLE("imposto" "text", "competencia_date" "date", "titulo_id" "uuid", "valor" numeric)
    LANGUAGE "plpgsql"
    AS $$
declare
  r record;
  v_motivo_id uuid;
  v_fornecedor_id integer;
  v_desc text;
  v_val numeric(15,2);
  v_titulo_id uuid;
  v_venc date;

  v_cfg record;
begin
  if to_regclass('r.r_apuracao_irpj_csll_mensal_comp2') is null then
    raise exception 'View r.r_apuracao_irpj_csll_mensal_comp2 não existe. Crie-a antes de gerar os títulos.';
  end if;

  select *
    into v_cfg
  from f.irpj_csll_financeiro_config cfg
  where cfg.tenant_id = p_tenant_id
    and cfg.empresa_id = p_empresa_id
    and cfg.deleted_at is null
  limit 1;

  select id into v_motivo_id
  from f.motivo_compra
  where tenant_id = p_tenant_id
    and codigo = 'IMPOSTO_LUCRO'
    and deleted_at is null
  limit 1;

  -- fornecedor "RECEITA FEDERAL - DARF" (sem documento)
  select f.id
    into v_fornecedor_id
  from public.fornecedores f
  where f.tenant_id = p_tenant_id
    and f.empresa_id = p_empresa_id
    and upper(f.nome) = 'RECEITA FEDERAL - DARF'
  limit 1;

  if v_fornecedor_id is null then
    insert into public.fornecedores (tenant_id, empresa_id, nome, ativo)
    values (p_tenant_id, p_empresa_id, 'RECEITA FEDERAL - DARF', true)
    returning id into v_fornecedor_id;
  end if;

  for r in
    select
      a.competencia_date,
      coalesce(a.irpj_total, 0)::numeric(15,2) as irpj_total,
      coalesce(a.csll_total, 0)::numeric(15,2) as csll_total
    from r.r_apuracao_irpj_csll_mensal_comp2 a
    where a.tenant_id = p_tenant_id
      and a.empresa_id = p_empresa_id
      and (p_competencia_date is null or a.competencia_date = p_competencia_date)
    order by a.competencia_date
  loop

    -- ========== IRPJ ==========
    if r.irpj_total > 0 then
      v_val := r.irpj_total;
      v_desc := 'IRPJ (LUCRO REAL) - ' || to_char(r.competencia_date, 'YYYY-MM');
      v_venc := f.fn_calc_vencimento(p_tenant_id, v_cfg.irpj_vencimento_regra_id, r.competencia_date);

      select t.id into v_titulo_id
      from f.titulo t
      where t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.tipo = 'AP'
        and t.origem = 'APURACAO_IRPJ_CSLL'
        and t.competencia_date = r.competencia_date
        and t.descricao = v_desc
        and t.deleted_at is null
      limit 1;

      if v_titulo_id is null then
        insert into f.titulo (
          tenant_id, empresa_id, tipo, status, origem,
          fornecedor_id, descricao, emissao_date, competencia_date,
          valor_total, valor_aberto, motivo_compra_id
        ) values (
          p_tenant_id, p_empresa_id, 'AP', 'PENDENTE', 'APURACAO_IRPJ_CSLL',
          v_fornecedor_id, v_desc, current_date, r.competencia_date,
          v_val, v_val, v_motivo_id
        )
        returning id into v_titulo_id;

        insert into f.titulo_parcela (
          tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto
        ) values (
          p_tenant_id, v_titulo_id, '1/1', v_venc, v_val, v_val
        );
      else
        update f.titulo
           set valor_total = v_val,
               valor_aberto = case when valor_aberto = valor_total then v_val else valor_aberto end,
               fornecedor_id = v_fornecedor_id,
               motivo_compra_id = v_motivo_id,
               updated_at = now()
         where id = v_titulo_id
           and tenant_id = p_tenant_id;

        -- ✅ FIX: alias tp para evitar ambiguidade com variável de saída titulo_id
        update f.titulo_parcela tp
           set vencimento_date = v_venc,
               valor = v_val,
               valor_aberto = case when tp.valor_aberto = tp.valor then v_val else tp.valor_aberto end,
               updated_at = now()
         where tp.tenant_id = p_tenant_id
           and tp.titulo_id = v_titulo_id
           and tp.numero = '1/1'
           and tp.deleted_at is null;

        if not found then
          insert into f.titulo_parcela (
            tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto
          ) values (
            p_tenant_id, v_titulo_id, '1/1', v_venc, v_val, v_val
          );
        end if;
      end if;

      imposto := 'IRPJ';
      competencia_date := r.competencia_date;
      titulo_id := v_titulo_id;
      valor := v_val;
      return next;
    end if;

    -- ========== CSLL ==========
    if r.csll_total > 0 then
      v_val := r.csll_total;
      v_desc := 'CSLL (LUCRO REAL) - ' || to_char(r.competencia_date, 'YYYY-MM');
      v_venc := f.fn_calc_vencimento(p_tenant_id, v_cfg.csll_vencimento_regra_id, r.competencia_date);

      select t.id into v_titulo_id
      from f.titulo t
      where t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.tipo = 'AP'
        and t.origem = 'APURACAO_IRPJ_CSLL'
        and t.competencia_date = r.competencia_date
        and t.descricao = v_desc
        and t.deleted_at is null
      limit 1;

      if v_titulo_id is null then
        insert into f.titulo (
          tenant_id, empresa_id, tipo, status, origem,
          fornecedor_id, descricao, emissao_date, competencia_date,
          valor_total, valor_aberto, motivo_compra_id
        ) values (
          p_tenant_id, p_empresa_id, 'AP', 'PENDENTE', 'APURACAO_IRPJ_CSLL',
          v_fornecedor_id, v_desc, current_date, r.competencia_date,
          v_val, v_val, v_motivo_id
        )
        returning id into v_titulo_id;

        insert into f.titulo_parcela (
          tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto
        ) values (
          p_tenant_id, v_titulo_id, '1/1', v_venc, v_val, v_val
        );
      else
        update f.titulo
           set valor_total = v_val,
               valor_aberto = case when valor_aberto = valor_total then v_val else valor_aberto end,
               fornecedor_id = v_fornecedor_id,
               motivo_compra_id = v_motivo_id,
               updated_at = now()
         where id = v_titulo_id
           and tenant_id = p_tenant_id;

        -- ✅ FIX: alias tp
        update f.titulo_parcela tp
           set vencimento_date = v_venc,
               valor = v_val,
               valor_aberto = case when tp.valor_aberto = tp.valor then v_val else tp.valor_aberto end,
               updated_at = now()
         where tp.tenant_id = p_tenant_id
           and tp.titulo_id = v_titulo_id
           and tp.numero = '1/1'
           and tp.deleted_at is null;

        if not found then
          insert into f.titulo_parcela (
            tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto
          ) values (
            p_tenant_id, v_titulo_id, '1/1', v_venc, v_val, v_val
          );
        end if;
      end if;

      imposto := 'CSLL';
      competencia_date := r.competencia_date;
      titulo_id := v_titulo_id;
      valor := v_val;
      return next;
    end if;

  end loop;
end;
$$;


ALTER FUNCTION "f"."fn_gerar_ap_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text" DEFAULT NULL::"text", "p_natureza" "text" DEFAULT NULL::"text") RETURNS TABLE("tenant_id" "uuid", "empresa_id" "uuid", "competencia_date" "date", "operacao" "text", "imposto" "text", "natureza" "text", "base_total" numeric, "valor_total_calculado" numeric, "valor_total_ajustado" numeric, "qtd_documentos" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
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
$$;


ALTER FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_imposto_credito_conferencia_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date") RETURNS TABLE("competencia_date" "date", "imposto" "text", "valor_provisionado" numeric, "valor_efetivo" numeric, "valor_pendente_revisao" numeric, "valor_nao_creditavel" numeric, "qtd_itens_pendentes" bigint, "qtd_nfs" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id e obrigatorio.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id e obrigatorio.'; end if;
  if p_comp_ini is null or p_comp_fim is null then raise exception 'Informe p_comp_ini e p_comp_fim'; end if;
  if p_comp_fim <= p_comp_ini then raise exception 'Intervalo invalido: p_comp_fim deve ser > p_comp_ini'; end if;

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
  with efet as (
    select
      df.competencia_date,
      dfi.imposto,
      sum(coalesce(dfi.valor_ajustado, dfi.valor_calculado, 0))::numeric as valor_efetivo,
      count(distinct df.id)::bigint as qtd_nfs
    from f.documento_fiscal_imposto dfi
    join f.documento_fiscal df
      on df.id = dfi.documento_fiscal_id
     and df.tenant_id = dfi.tenant_id
    where dfi.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and dfi.deleted_at is null
      and df.deleted_at is null
      and df.operacao = 'ENTRADA'
      and dfi.natureza = 'CREDITO'
      and dfi.imposto in ('ICMS','PIS','COFINS')
      and df.competencia_date >= p_comp_ini
      and df.competencia_date < p_comp_fim
    group by df.competencia_date, dfi.imposto
  )
  select
    e.competencia_date,
    e.imposto,
    e.valor_efetivo as valor_provisionado,
    e.valor_efetivo,
    0::numeric as valor_pendente_revisao,
    0::numeric as valor_nao_creditavel,
    0::bigint as qtd_itens_pendentes,
    e.qtd_nfs
  from efet e
  order by 1 asc, 2 asc;
end;
$$;


ALTER FUNCTION "f"."fn_imposto_credito_conferencia_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_imposto_credito_manual_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text" DEFAULT NULL::"text", "p_natureza" "text" DEFAULT NULL::"text") RETURNS TABLE("tenant_id" "uuid", "empresa_id" "uuid", "competencia_date" "date", "operacao" "text", "imposto" "text", "natureza" "text", "base_total" numeric, "valor_total_calculado" numeric, "valor_total_ajustado" numeric, "qtd_documentos" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id e obrigatorio.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id e obrigatorio.'; end if;
  if p_comp_ini is null or p_comp_fim is null then raise exception 'Informe p_comp_ini e p_comp_fim'; end if;
  if p_comp_fim <= p_comp_ini then raise exception 'Intervalo invalido: p_comp_fim deve ser > p_comp_ini'; end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from p_tenant_id then raise exception 'Tenant mismatch'; end if;
    if public.current_empresa_id() is distinct from p_empresa_id then raise exception 'Empresa mismatch'; end if;
    if not f.has_finance_access(p_tenant_id, p_empresa_id) then raise exception 'Sem permissao: somente ADMIN/FINANCEIRO'; end if;
  end if;

  return query
  select
    l.tenant_id,
    l.empresa_id,
    l.competencia_date,
    'ENTRADA'::text as operacao,
    upper(l.imposto) as imposto,
    'CREDITO'::text as natureza,
    round(sum(coalesce(l.base_calculo,0))::numeric,2) as base_total,
    round(sum(coalesce(l.valor_credito,0))::numeric,2) as valor_total_calculado,
    0::numeric as valor_total_ajustado,
    count(distinct l.titulo_id)::bigint as qtd_documentos
  from f.credito_fiscal_manual_lancamento l
  where l.tenant_id = p_tenant_id
    and l.empresa_id = p_empresa_id
    and l.deleted_at is null
    and l.status in ('PROVISIONADO','APROPRIADO')
    and l.competencia_date >= p_comp_ini
    and l.competencia_date < p_comp_fim
    and (p_operacao is null or upper(p_operacao) = 'ENTRADA')
    and (p_natureza is null or upper(p_natureza) = 'CREDITO')
  group by l.tenant_id, l.empresa_id, l.competencia_date, upper(l.imposto)
  order by l.competencia_date asc, upper(l.imposto) asc;
end;
$$;


ALTER FUNCTION "f"."fn_imposto_credito_manual_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text" DEFAULT NULL::"text") RETURNS TABLE("documento_fiscal_id" "uuid", "chave_acesso" "text", "emissao_date" "date", "competencia_date" "date", "operacao" "text", "modelo" "text", "serie" "text", "numero" "text", "valor_documento" numeric, "valor_imposto" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
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
$$;


ALTER FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_imposto_guardiao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text" DEFAULT NULL::"text", "p_tipo" "text" DEFAULT NULL::"text", "p_imposto" "text" DEFAULT NULL::"text") RETURNS TABLE("tenant_id" "uuid", "empresa_id" "uuid", "competencia_date" "date", "documento_fiscal_id" "uuid", "nf_entrada_id" bigint, "chave_acesso" "text", "operacao" "text", "tipo" "text", "imposto" "text", "natureza_esperada" "text", "esperado" numeric, "encontrado" numeric, "diff" numeric, "detalhe" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'r', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
begin
  if auth.uid() is null then
    if current_user not in ('postgres', 'service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id e obrigatorio.';
  end if;
  if p_empresa_id is null then
    raise exception 'empresa_id e obrigatorio.';
  end if;
  if p_comp_ini is null or p_comp_fim is null then
    raise exception 'Informe p_comp_ini e p_comp_fim';
  end if;
  if p_comp_fim <= p_comp_ini then
    raise exception 'Intervalo invalido: p_comp_fim deve ser > p_comp_ini';
  end if;

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
    g.tenant_id,
    g.empresa_id,
    g.competencia_date,
    g.documento_fiscal_id,
    g.nf_entrada_id,
    g.chave_acesso,
    g.operacao,
    g.tipo,
    g.imposto,
    g.natureza_esperada,
    g.esperado,
    g.encontrado,
    g.diff,
    g.detalhe
  from r.r_guardiao_impostos_docs g
  where g.tenant_id = p_tenant_id
    and g.empresa_id = p_empresa_id
    and g.competencia_date >= p_comp_ini
    and g.competencia_date < p_comp_fim
    and (p_operacao is null or g.operacao = p_operacao)
    and (p_tipo is null or g.tipo = p_tipo)
    and (p_imposto is null or g.imposto = p_imposto)
  order by g.competencia_date asc, g.tipo asc, g.imposto asc nulls last, g.documento_fiscal_id asc;
end;
$$;


ALTER FUNCTION "f"."fn_imposto_guardiao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_tipo" "text", "p_imposto" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_irpj_csll_ao_fechar_competencia"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f'
    AS $$
declare
  v_dummy int;
begin
  ------------------------------------------------------------------
  -- 0) AJUSTES AUTOMÁTICOS (V2) - NÃO BLOQUEIA FECHAMENTO SE FALHAR
  ------------------------------------------------------------------
  begin
    perform f.fn_irpj_csll_gerar_ajustes_auto(p_tenant_id, p_empresa_id, p_competencia_date);
  exception
    when undefined_function then
      raise notice 'IRPJ/CSLL: fn_irpj_csll_gerar_ajustes_auto não existe. Pulando (competência %).', p_competencia_date;
    when others then
      raise notice 'IRPJ/CSLL: erro ao gerar ajustes automáticos na competência %: %', p_competencia_date, sqlerrm;
  end;

  ------------------------------------------------------------------
  -- 1.1) gera/atualiza títulos AP (não bloqueia fechamento se falhar)
  ------------------------------------------------------------------
  begin
    select count(*) into v_dummy
    from f.parametro_irpj_csll_empresa p
    where p.tenant_id = p_tenant_id
      and p.empresa_id = p_empresa_id
      and p.deleted_at is null;

    if v_dummy = 0 then
      raise notice 'IRPJ/CSLL: parametro_irpj_csll_empresa não configurado. Pulando geração (tenant %, empresa %).',
        p_tenant_id, p_empresa_id;
    else
      select count(*) into v_dummy
      from f.fn_gerar_ap_irpj_csll(p_tenant_id, p_empresa_id, p_competencia_date);
    end if;
  exception when others then
    raise notice 'IRPJ/CSLL: erro ao gerar AP na competência %: %', p_competencia_date, sqlerrm;
  end;

  ------------------------------------------------------------------
  -- 1.2) aplica/ajusta rateio (não bloqueia fechamento se falhar)
  ------------------------------------------------------------------
  begin
    select count(*) into v_dummy
    from f.irpj_csll_financeiro_config cfg
    where cfg.tenant_id = p_tenant_id
      and cfg.empresa_id = p_empresa_id
      and cfg.deleted_at is null;

    if v_dummy = 0 then
      raise notice 'IRPJ/CSLL: irpj_csll_financeiro_config não encontrado. Pulando rateio (tenant %, empresa %).',
        p_tenant_id, p_empresa_id;
      return;
    end if;

    -- (A) se não houver rateio, cria 100%
    insert into f.titulo_rateio (
      tenant_id, titulo_id, plano_contas_id, percentual, valor, created_by
    )
    select
      t.tenant_id,
      t.id,
      case
        when t.descricao ilike 'IRPJ%' then cfg.irpj_plano_contas_id
        when t.descricao ilike 'CSLL%' then cfg.csll_plano_contas_id
        else null
      end,
      100::numeric(7,4),
      t.valor_total,
      null
    from f.titulo t
    join f.irpj_csll_financeiro_config cfg
      on cfg.tenant_id = t.tenant_id
     and cfg.empresa_id = t.empresa_id
     and cfg.deleted_at is null
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.origem = 'APURACAO_IRPJ_CSLL'
      and t.competencia_date = p_competencia_date
      and t.deleted_at is null
      and (t.descricao ilike 'IRPJ%' or t.descricao ilike 'CSLL%')
      and not exists (
        select 1
        from f.titulo_rateio tr
        where tr.tenant_id = t.tenant_id
          and tr.titulo_id = t.id
          and tr.deleted_at is null
      );

    -- (B) se já houver 1 rateio 100% (simples), ajusta conta + valor
    update f.titulo_rateio tr
    set
      plano_contas_id = case
        when t.descricao ilike 'IRPJ%' then cfg.irpj_plano_contas_id
        when t.descricao ilike 'CSLL%' then cfg.csll_plano_contas_id
        else tr.plano_contas_id
      end,
      percentual = 100::numeric(7,4),
      valor = t.valor_total,
      updated_at = now()
    from f.titulo t
    join f.irpj_csll_financeiro_config cfg
      on cfg.tenant_id = t.tenant_id
     and cfg.empresa_id = t.empresa_id
     and cfg.deleted_at is null
    where tr.tenant_id = t.tenant_id
      and tr.titulo_id = t.id
      and tr.deleted_at is null
      and t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.origem = 'APURACAO_IRPJ_CSLL'
      and t.competencia_date = p_competencia_date
      and t.deleted_at is null
      and t.status = 'PENDENTE'
      and (t.descricao ilike 'IRPJ%' or t.descricao ilike 'CSLL%')
      and (
        select count(*)
        from f.titulo_rateio tr2
        where tr2.tenant_id = t.tenant_id
          and tr2.titulo_id = t.id
          and tr2.deleted_at is null
      ) = 1;

  exception when others then
    raise notice 'IRPJ/CSLL: erro ao aplicar rateio na competência %: %', p_competencia_date, sqlerrm;
  end;

end;
$$;


ALTER FUNCTION "f"."fn_irpj_csll_ao_fechar_competencia"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_irpj_csll_gerar_ajustes_auto"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f', 'r'
    AS $$
  begin
    if extract(day from p_competencia_date) <> 1 then
      raise exception 'competencia_date deve ser dia 01 (recebido: %)', p_competencia_date;
    end if;

    -- apaga (soft delete) ajustes automáticos antigos dessa competência
    update f.irpj_csll_ajuste a
       set deleted_at = now(),
           updated_at = now()
     where a.tenant_id = p_tenant_id
       and a.empresa_id = p_empresa_id
       and a.competencia_date = p_competencia_date
       and a.deleted_at is null
       and a.observacao like 'AUTO_REGRA_PLANO:%';

    -- gera novos ajustes automáticos
    insert into f.irpj_csll_ajuste (
      tenant_id, empresa_id, competencia_date,
      escopo, tipo, descricao, valor, observacao
    )
    select
      rp.tenant_id,
      rp.empresa_id,
      p_competencia_date,
      rp.escopo,
      rp.tipo,
      rp.descricao,
      round((coalesce(d.despesa,0) * (rp.percentual/100.0))::numeric, 2)::numeric(15,2) as valor,
      ('AUTO_REGRA_PLANO:' || pc.codigo || ':PCT=' || rp.percentual::text) as observacao
    from f.irpj_csll_regra_plano rp
    join f.plano_contas pc
      on pc.tenant_id = rp.tenant_id
     and pc.id = rp.plano_contas_id
     and pc.deleted_at is null
    left join r.r_dre_mensal_plano d
      on d.tenant_id = rp.tenant_id
     and d.empresa_id = rp.empresa_id
     and d.competencia_date = p_competencia_date
     and d.plano_contas_id = rp.plano_contas_id
    where rp.tenant_id = p_tenant_id
      and rp.empresa_id = p_empresa_id
      and rp.deleted_at is null
      and rp.ativo = true
      and round((coalesce(d.despesa,0) * (rp.percentual/100.0))::numeric, 2) > 0;
  end;
  $$;


ALTER FUNCTION "f"."fn_irpj_csll_gerar_ajustes_auto"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_nf_entrada__auto_fix_ap_from_xml"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f', 'a'
    SET "row_security" TO 'off'
    AS $$
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

  if new.xml_raw is null or nullif(btrim(new.xml_raw), '') is null then
    return new;
  end if;

  -- so quando o XML "chega" (INSERT ou antes estava vazio)
  if tg_op = 'UPDATE' and old.xml_raw is not null and nullif(btrim(old.xml_raw), '') is not null then
    return new;
  end if;

  -- Importacao XML por usuarios nao-financeiros nao deve quebrar.
  -- O fluxo da API ja garante AP em etapa posterior via rotina privilegiada.
  if auth.uid() is not null and not f.has_finance_access(new.tenant_id, new.empresa_id) then
    return new;
  end if;

  v_emissao_date := (new.data_emissao at time zone 'America/Sao_Paulo')::date;
  v_xml := xmlparse(document new.xml_raw);
  v_dup_cnt := coalesce(array_length(xpath('//*[local-name()="cobr"]/*[local-name()="dup"]', v_xml), 1), 0);

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

  -- se ainda nao tem titulo/AP, cria/ajusta tudo
  if v_titulo_id is null then
    begin
      perform 1 from public.fn_fix_nf_entrada_pos_import(new.id);
    exception when others then
      return new;
    end;
    return new;
  end if;

  -- se ja teve baixa/pagamento, nao mexe
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

  select count(*) into v_parc_cnt
  from f.titulo_parcela p
  where p.tenant_id = new.tenant_id
    and p.titulo_id = v_titulo_id
    and p.deleted_at is null;

  -- so corrige quando detecta "placeholder" 1x e o XML diz que e parcelado
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
    begin
      perform 1 from public.fn_fix_nf_entrada_pos_import(new.id);
    exception when others then
      return new;
    end;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "f"."fn_nf_entrada__auto_fix_ap_from_xml"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_nf_entrada__resolve_xml_pendencia"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  -- só resolve se agora tiver XML
  if new.xml_raw is null or btrim(new.xml_raw) = '' then
    return new;
  end if;

  update f.documento_fiscal_pendencia p
  set resolved_at = now(),
      updated_at = now()
  from f.documento_fiscal df
  where df.tenant_id = new.tenant_id
    and df.source_nf_entrada_id = new.id
    and p.tenant_id = df.tenant_id
    and p.documento_fiscal_id = df.id
    and p.tipo = 'XML_FALTANDO'
    and p.resolved_at is null;

  return new;
end $$;


ALTER FUNCTION "f"."fn_nf_entrada__resolve_xml_pendencia"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_nfse_sync_piscofins_debito_doc"("p_documento_fiscal_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_df f.documento_fiscal%rowtype;
  v_base_original numeric(15,2);
  v_deducoes numeric(15,2);
  v_base_calculo numeric(15,2);
  v_imposto text;
  v_default_aliq numeric(12,4);
  v_ref_valor numeric(15,2);
  v_ref_aliq numeric(12,4);
  v_valor numeric(15,2);
  v_aliq numeric(12,4);
begin
  if p_documento_fiscal_id is null then
    return;
  end if;

  select *
    into v_df
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.deleted_at is null
  limit 1;

  if not found then
    return;
  end if;

  if coalesce(v_df.modelo, '') <> 'NFSE'
     or coalesce(v_df.operacao, '') <> 'SAIDA'
     or coalesce(v_df.natureza, '') <> 'SERVICO' then
    return;
  end if;

  v_base_original := round(coalesce(v_df.valor_servicos, v_df.valor_total, 0)::numeric, 2);
  v_deducoes := round(greatest(coalesce(v_df.material_valor, 0)::numeric, 0), 2);
  v_base_calculo := round(greatest(v_base_original - v_deducoes, 0), 2);

  foreach v_imposto in array array['PIS','COFINS'] loop
    v_default_aliq := case when v_imposto = 'PIS' then 0.6500 else 3.0000 end;
    v_ref_valor := null;
    v_ref_aliq := null;
    v_valor := 0;
    v_aliq := 0;

    select
      round(coalesce(i.valor_ajustado, i.valor_calculado, 0)::numeric, 2) as valor,
      round(coalesce(i.aliquota, 0)::numeric, 4) as aliq
      into v_ref_valor, v_ref_aliq
    from f.documento_fiscal_imposto i
    where i.tenant_id = v_df.tenant_id
      and i.documento_fiscal_id = v_df.id
      and i.imposto = v_imposto
      and i.deleted_at is null
    order by case when i.natureza = 'DEBITO' then 0 when i.natureza = 'RETENCAO' then 1 else 2 end,
             i.updated_at desc nulls last,
             i.created_at desc nulls last
    limit 1;

    if coalesce(v_ref_valor, 0) > 0 then
      v_valor := v_ref_valor;
      if coalesce(v_ref_aliq, 0) > 0 then
        v_aliq := v_ref_aliq;
      elsif v_base_calculo > 0 then
        v_aliq := round((v_valor * 100.0) / v_base_calculo, 4);
      else
        v_aliq := 0;
      end if;
    elsif v_base_calculo > 0 then
      -- fallback cumulativo para NFSE quando nao houver valor explicito.
      v_aliq := v_default_aliq;
      v_valor := round((v_base_calculo * v_aliq) / 100.0, 2);
    end if;

    if coalesce(v_valor, 0) <= 0 then
      continue;
    end if;

    insert into f.documento_fiscal_imposto (
      id,
      tenant_id,
      documento_fiscal_id,
      imposto,
      natureza,
      base_original,
      deducoes,
      base_calculo,
      aliquota,
      valor_calculado,
      valor_ajustado,
      created_at,
      updated_at,
      deleted_at
    )
    values (
      gen_random_uuid(),
      v_df.tenant_id,
      v_df.id,
      v_imposto,
      'DEBITO',
      v_base_original,
      v_deducoes,
      v_base_calculo,
      coalesce(v_aliq, 0),
      v_valor,
      null,
      now(),
      now(),
      null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      updated_at = now(),
      deleted_at = null;
  end loop;
end;
$$;


ALTER FUNCTION "f"."fn_nfse_sync_piscofins_debito_doc"("p_documento_fiscal_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_pagamentos_aplicados"() RETURNS TABLE("tenant_id" "uuid", "empresa_id" "uuid", "conta_bancaria_id" "uuid", "pagamento_id" "uuid", "data_pagamento" "date", "forma_pagamento" "text", "valor_pagamento" numeric, "titulo_id" "uuid", "titulo_parcela_id" "uuid", "valor_aplicado" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public'
    AS $_$
declare
  v_tbl text;
  v_col_parcela text;
  v_col_valor text;
  v_has_deleted_at boolean;
  v_sql text;
begin
  /*
    Detecta automaticamente a tabela de aplicação:
    - deve ter pagamento_id
    - deve ter (titulo_parcela_id OU parcela_id)
    - deve ter (valor_aplicado OU valor)
  */
  select x.table_name
    into v_tbl
  from (
    select t.table_name
    from information_schema.tables t
    where t.table_schema = 'f'
      and t.table_type = 'BASE TABLE'
      and exists (
        select 1 from information_schema.columns c
        where c.table_schema='f' and c.table_name=t.table_name and c.column_name='pagamento_id'
      )
      and exists (
        select 1 from information_schema.columns c
        where c.table_schema='f' and c.table_name=t.table_name and c.column_name in ('titulo_parcela_id','parcela_id')
      )
      and exists (
        select 1 from information_schema.columns c
        where c.table_schema='f' and c.table_name=t.table_name and c.column_name in ('valor_aplicado','valor')
      )
    order by
      case when t.table_name = 'pagamento_aplicacao' then 0 else 1 end,
      t.table_name
    limit 1
  ) x;

  if v_tbl is null then
    raise exception
      'Nao encontrei tabela de aplicacao pagamento->parcela no schema f. Preciso de uma tabela com: pagamento_id + (titulo_parcela_id/parcela_id) + (valor_aplicado/valor).';
  end if;

  -- qual coluna é a parcela?
  if exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name=v_tbl and column_name='titulo_parcela_id'
  ) then
    v_col_parcela := 'titulo_parcela_id';
  else
    v_col_parcela := 'parcela_id';
  end if;

  -- qual coluna é o valor aplicado?
  if exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name=v_tbl and column_name='valor_aplicado'
  ) then
    v_col_valor := 'valor_aplicado';
  else
    v_col_valor := 'valor';
  end if;

  -- tem deleted_at na tabela de aplicação?
  select exists(
    select 1 from information_schema.columns
    where table_schema='f' and table_name=v_tbl and column_name='deleted_at'
  ) into v_has_deleted_at;

  v_sql := format($fmt$
    select
      p.tenant_id,
      p.empresa_id,
      p.conta_bancaria_id,
      p.id as pagamento_id,
      p.data_pagamento,
      p.forma_pagamento::text as forma_pagamento,
      p.valor::numeric(15,2) as valor_pagamento,
      tp.titulo_id,
      pa.%1$I as titulo_parcela_id,
      pa.%2$I::numeric(15,2) as valor_aplicado
    from f.%3$I pa
    join f.pagamento p on p.id = pa.pagamento_id
    join f.titulo_parcela tp on tp.id = pa.%1$I
    where %4$s
      and p.deleted_at is null
      and tp.deleted_at is null
  $fmt$,
    v_col_parcela,
    v_col_valor,
    v_tbl,
    case when v_has_deleted_at then 'pa.deleted_at is null' else 'true' end
  );

  return query execute v_sql;
end;
$_$;


ALTER FUNCTION "f"."fn_pagamentos_aplicados"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_pick_credito_fiscal_manual_regra"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_imposto" "text", "p_origem" "text", "p_descricao" "text", "p_motivo_compra_id" "uuid", "p_fornecedor_id" integer) RETURNS TABLE("regra_id" "uuid", "modo" "text", "aliquota" numeric, "parcelas_apropriacao" integer, "competencia_offset_meses" integer, "fonte" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_rule record;
begin
  select
    r.id,
    r.modo,
    r.aliquota,
    r.parcelas_apropriacao,
    r.competencia_offset_meses
  into v_rule
  from f.credito_fiscal_manual_regra r
  where r.tenant_id = p_tenant_id
    and (r.empresa_id is null or r.empresa_id = p_empresa_id)
    and r.deleted_at is null
    and r.ativo = true
    and upper(r.imposto) = upper(p_imposto)
    and (r.aplica_origem is null or upper(r.aplica_origem) = upper(coalesce(p_origem,'')))
    and (r.descricao_like is null or upper(coalesce(p_descricao,'')) like upper(r.descricao_like))
    and (r.motivo_compra_id is null or r.motivo_compra_id = p_motivo_compra_id)
    and (r.fornecedor_id is null or r.fornecedor_id = p_fornecedor_id)
  order by
    r.prioridade asc,
    (case when r.empresa_id is null then 1 else 0 end) asc,
    (case when r.fornecedor_id is null then 1 else 0 end) asc,
    (case when r.motivo_compra_id is null then 1 else 0 end) asc,
    (case when r.descricao_like is null then 1 else 0 end) asc,
    r.created_at asc
  limit 1;

  if found then
    regra_id := v_rule.id;
    modo := v_rule.modo;
    aliquota := coalesce(v_rule.aliquota,0);
    parcelas_apropriacao := coalesce(v_rule.parcelas_apropriacao,1);
    competencia_offset_meses := coalesce(v_rule.competencia_offset_meses,0);
    fonte := 'REGRA';
    return next;
    return;
  end if;

  regra_id := null;
  modo := 'PENDENTE_REVISAO';
  aliquota := 0;
  parcelas_apropriacao := 1;
  competencia_offset_meses := 0;
  fonte := 'FALLBACK_PENDENTE';
  return next;
end;
$$;


ALTER FUNCTION "f"."fn_pick_credito_fiscal_manual_regra"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_imposto" "text", "p_origem" "text", "p_descricao" "text", "p_motivo_compra_id" "uuid", "p_fornecedor_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_set_updated_by"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_by := a.fn_current_usuario_id();
  return new;
end;
$$;


ALTER FUNCTION "f"."fn_set_updated_by"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_sync_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") RETURNS TABLE("imposto" "text", "competencia_date" "date", "titulo_id" "uuid", "valor" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'r'
    SET "row_security" TO 'off'
    AS $$
declare
  v_ap record;

  v_desc text;
  v_titulo_id uuid;
  v_status text;
  v_total numeric(15,2);
  v_aberto numeric(15,2);
  v_pago numeric(15,2);
begin
  -- Segurança padrão (igual outras rotinas do schema)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  else
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

  if to_regclass('r.r_apuracao_irpj_csll_mensal_comp2') is null then
    raise exception 'View r.r_apuracao_irpj_csll_mensal_comp2 não existe.';
  end if;

  -- (A) Atualiza/cria títulos conforme a apuração (idempotente)
  return query
  select * from f.fn_gerar_ap_irpj_csll(p_tenant_id, p_empresa_id, p_competencia_date);

  -- (B) Se a apuração virar 0 (ou não houver linha), cancela o título PENDENTE/sem pagamento
  select
    coalesce(a.irpj_total, 0)::numeric(15,2) as irpj_total,
    coalesce(a.csll_total, 0)::numeric(15,2) as csll_total
  into v_ap
  from r.r_apuracao_irpj_csll_mensal_comp2 a
  where a.tenant_id = p_tenant_id
    and a.empresa_id = p_empresa_id
    and a.competencia_date = p_competencia_date;

  -- IRPJ
  if coalesce(v_ap.irpj_total, 0) <= 0 then
    v_desc := 'IRPJ (LUCRO REAL) - ' || to_char(p_competencia_date, 'YYYY-MM');

    select t.id, t.status, t.valor_total, t.valor_aberto
      into v_titulo_id, v_status, v_total, v_aberto
    from f.titulo t
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.origem = 'APURACAO_IRPJ_CSLL'
      and t.competencia_date = p_competencia_date
      and t.descricao = v_desc
      and t.deleted_at is null
    order by t.created_at desc
    limit 1;

    if v_titulo_id is not null then
      v_pago := coalesce(v_total,0) - coalesce(v_aberto,0);

      if coalesce(v_status,'') <> 'PENDENTE' or v_pago <> 0 then
        raise exception 'IRPJ/CSLL: não posso cancelar automaticamente o título %, pois status=% e pago=%.',
          v_desc, v_status, v_pago;
      end if;

      update f.titulo
         set status = 'CANCELADO',
             deleted_at = now(),
             updated_at = now()
       where id = v_titulo_id;

      update f.titulo_parcela
         set deleted_at = now(),
             updated_at = now()
       where tenant_id = p_tenant_id
         and titulo_id = v_titulo_id
         and deleted_at is null;

      update f.titulo_rateio
         set deleted_at = now(),
             updated_at = now()
       where tenant_id = p_tenant_id
         and titulo_id = v_titulo_id
         and deleted_at is null;
    end if;

    imposto := 'IRPJ';
    competencia_date := p_competencia_date;
    titulo_id := v_titulo_id;
    valor := 0;
    return next;
  end if;

  -- CSLL
  if coalesce(v_ap.csll_total, 0) <= 0 then
    v_desc := 'CSLL (LUCRO REAL) - ' || to_char(p_competencia_date, 'YYYY-MM');

    select t.id, t.status, t.valor_total, t.valor_aberto
      into v_titulo_id, v_status, v_total, v_aberto
    from f.titulo t
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.origem = 'APURACAO_IRPJ_CSLL'
      and t.competencia_date = p_competencia_date
      and t.descricao = v_desc
      and t.deleted_at is null
    order by t.created_at desc
    limit 1;

    if v_titulo_id is not null then
      v_pago := coalesce(v_total,0) - coalesce(v_aberto,0);

      if coalesce(v_status,'') <> 'PENDENTE' or v_pago <> 0 then
        raise exception 'IRPJ/CSLL: não posso cancelar automaticamente o título %, pois status=% e pago=%.',
          v_desc, v_status, v_pago;
      end if;

      update f.titulo
         set status = 'CANCELADO',
             deleted_at = now(),
             updated_at = now()
       where id = v_titulo_id;

      update f.titulo_parcela
         set deleted_at = now(),
             updated_at = now()
       where tenant_id = p_tenant_id
         and titulo_id = v_titulo_id
         and deleted_at is null;

      update f.titulo_rateio
         set deleted_at = now(),
             updated_at = now()
       where tenant_id = p_tenant_id
         and titulo_id = v_titulo_id
         and deleted_at is null;
    end if;

    imposto := 'CSLL';
    competencia_date := p_competencia_date;
    titulo_id := v_titulo_id;
    valor := 0;
    return next;
  end if;
end;
$$;


ALTER FUNCTION "f"."fn_sync_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_sync_rateio_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
begin
  -- Atualiza rateios existentes (baseado em percentual)
  update f.titulo_rateio tr
  set valor = round(t.valor_total * tr.percentual / 100.0, 2)
  from f.titulo t
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.competencia_date = p_competencia_date
    and t.origem = 'APURACAO_IRPJ_CSLL'
    and t.deleted_at is null
    and tr.deleted_at is null
    and tr.percentual is not null
    and tr.tenant_id = t.tenant_id
    and tr.titulo_id = t.id;

  -- Se existir título sem rateio, tenta criar 100% no plano correto (DESP_IRPJ / DESP_CSLL)
  insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor)
  select
    t.tenant_id,
    t.id,
    pc.id,
    100.0000,
    coalesce(t.valor_total, 0)
  from f.titulo t
  join f.plano_contas pc
    on pc.tenant_id = t.tenant_id
   and pc.deleted_at is null
   and pc.codigo = case
     when position('CSLL' in upper(coalesce(t.descricao,''))) > 0 then 'DESP_CSLL'
     when position('IRPJ' in upper(coalesce(t.descricao,''))) > 0 then 'DESP_IRPJ'
     else null
   end
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.competencia_date = p_competencia_date
    and t.origem = 'APURACAO_IRPJ_CSLL'
    and t.deleted_at is null
    and not exists (
      select 1
      from f.titulo_rateio tr
      where tr.tenant_id = t.tenant_id
        and tr.titulo_id = t.id
        and tr.deleted_at is null
    );

end;
$$;


ALTER FUNCTION "f"."fn_sync_rateio_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_upsert_ar_from_documento_fiscal"("p_documento_fiscal_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
declare
  v_df record;
  v_titulo_id uuid;
  v_valor numeric(15,2);
  v_desc text;
  v_venc date;
  v_plano_contas_id uuid;
  v_valor_aberto_old numeric(15,2);
begin
  select * into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then return null; end if;

  if coalesce(v_df.operacao,'') <> 'SAIDA' then return null; end if;
  if coalesce(v_df.natureza,'') <> 'SERVICO' then return null; end if;
  if coalesce(v_df.nfse_status,'') <> 'EMITIDA' then return null; end if;
  if v_df.cliente_id is null then return null; end if;

  v_valor := coalesce(v_df.valor_total, 0);

  v_desc := concat(coalesce(v_df.modelo,'DOC'), ' ', coalesce(v_df.numero,''), '/', coalesce(v_df.serie,''));
  if btrim(v_desc) = '' then v_desc := 'FATURAMENTO'; end if;

  v_venc := coalesce(v_df.emissao_date, current_date) + 15;

  select pc.id into v_plano_contas_id
  from f.plano_contas pc
  where pc.tenant_id = v_df.tenant_id
    and pc.codigo = '3.01'
    and pc.deleted_at is null
  limit 1;

  if v_plano_contas_id is null then
    raise exception 'Plano de contas padrão (codigo=3.01) não encontrado para tenant %', v_df.tenant_id;
  end if;

  select t.id, t.valor_aberto
    into v_titulo_id, v_valor_aberto_old
  from f.titulo t
  where t.tenant_id = v_df.tenant_id
    and t.empresa_id = v_df.empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem,
      cliente_id, documento_fiscal_id, descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto
    ) values (
      v_df.tenant_id, v_df.empresa_id, 'AR', 'PENDENTE', 'FATURAMENTO',
      v_df.cliente_id, v_df.id, v_desc,
      v_df.emissao_date, v_df.competencia_date,
      v_valor, v_valor
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor)
    values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, 100.0000, v_valor);

  else
    -- atualiza valor_aberto só se ainda estava totalmente em aberto (sem baixa)
    update f.titulo
    set
      cliente_id = v_df.cliente_id,
      descricao = v_desc,
      emissao_date = v_df.emissao_date,
      competencia_date = v_df.competencia_date,
      valor_total = v_valor,
      valor_aberto = case
        when coalesce(v_valor_aberto_old, 0) = coalesce(valor_total, 0) then v_valor
        else valor_aberto
      end
    where id = v_titulo_id;

    update f.titulo_parcela
    set
      vencimento_date = v_venc,
      valor = v_valor,
      valor_aberto = case
        when coalesce(valor_aberto, 0) = coalesce(valor, 0) then v_valor
        else valor_aberto
      end
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and numero = '1'
      and deleted_at is null;

    update f.titulo_rateio
    set
      plano_contas_id = v_plano_contas_id,
      percentual = 100.0000,
      valor = v_valor
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;
  end if;

  return v_titulo_id;
end;
$$;


ALTER FUNCTION "f"."fn_upsert_ar_from_documento_fiscal"("p_documento_fiscal_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_upsert_ar_from_documento_fiscal_v2"("p_documento_fiscal_id" "uuid", "p_old_valor_total" numeric DEFAULT NULL::numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
declare
  v_df record;
  v_titulo_id uuid;
  v_valor numeric(15,2);
  v_desc text;
  v_venc date;
  v_plano_contas_id uuid;
  v_valor_aberto_old numeric(15,2);
begin
  select * into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then return null; end if;

  if coalesce(v_df.operacao,'') <> 'SAIDA' then return null; end if;
  if coalesce(v_df.natureza,'') <> 'SERVICO' then return null; end if;
  if coalesce(v_df.nfse_status,'') <> 'EMITIDA' then return null; end if;
  if v_df.cliente_id is null then return null; end if;

  v_valor := coalesce(v_df.valor_total, 0);

  v_desc := concat(coalesce(v_df.modelo,'DOC'), ' ', coalesce(v_df.numero,''), '/', coalesce(v_df.serie,''));
  if btrim(v_desc) = '' then v_desc := 'FATURAMENTO'; end if;

  v_venc := coalesce(v_df.emissao_date, current_date) + 15;

  select pc.id into v_plano_contas_id
  from f.plano_contas pc
  where pc.tenant_id = v_df.tenant_id
    and pc.codigo = '3.01'
    and pc.deleted_at is null
  limit 1;

  if v_plano_contas_id is null then
    raise exception 'Plano de contas padrão (codigo=3.01) não encontrado para tenant %', v_df.tenant_id;
  end if;

  select t.id, t.valor_aberto
    into v_titulo_id, v_valor_aberto_old
  from f.titulo t
  where t.tenant_id = v_df.tenant_id
    and t.empresa_id = v_df.empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem,
      cliente_id, documento_fiscal_id, descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto
    ) values (
      v_df.tenant_id, v_df.empresa_id, 'AR', 'PENDENTE', 'FATURAMENTO',
      v_df.cliente_id, v_df.id, v_desc,
      v_df.emissao_date, v_df.competencia_date,
      v_valor, v_valor
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor)
    values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, 100.0000, v_valor);

  else
    -- titulo: sincroniza aberto se ainda estava “no total antigo”
    update f.titulo
    set
      cliente_id = v_df.cliente_id,
      descricao = v_desc,
      emissao_date = v_df.emissao_date,
      competencia_date = v_df.competencia_date,
      valor_total = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor_total,0) then v_valor
        else valor_aberto
      end
    where id = v_titulo_id;

    -- parcela 1: idem (sincroniza aberto se ainda estava no valor antigo)
    update f.titulo_parcela
    set
      vencimento_date = v_venc,
      valor = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor,0) then v_valor
        else valor_aberto
      end
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and numero = '1'
      and deleted_at is null;

    update f.titulo_rateio
    set plano_contas_id = v_plano_contas_id,
        percentual = 100.0000,
        valor = v_valor
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;
  end if;

  return v_titulo_id;
end;
$$;


ALTER FUNCTION "f"."fn_upsert_ar_from_documento_fiscal_v2"("p_documento_fiscal_id" "uuid", "p_old_valor_total" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_upsert_ar_from_nfe_venda"("p_documento_fiscal_id" "uuid", "p_old_valor_total" numeric DEFAULT NULL::numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
declare
  v_df record;
  v_titulo_id uuid;
  v_valor numeric(15,2);
  v_desc text;
  v_venc date;
  v_plano_contas_id uuid;
begin
  select * into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then return null; end if;

  -- SEPARAÇÃO: só faturamento (SAÍDA / PRODUTO / EMITIDA)
  if coalesce(v_df.operacao,'') <> 'SAIDA' then return null; end if;
  if coalesce(v_df.natureza,'') <> 'PRODUTO' then return null; end if;
  if coalesce(v_df.nfe_status,'') <> 'EMITIDA' then return null; end if;

  if v_df.cliente_id is null then
    raise exception 'NF-e de faturamento precisa de cliente_id para gerar Contas a Receber.';
  end if;

  v_valor := coalesce(v_df.valor_total, 0);
  v_desc := concat('NFE ', coalesce(v_df.numero,''), '/', coalesce(v_df.serie,''));
  if btrim(v_desc) = '' then v_desc := 'FATURAMENTO NFE'; end if;

  v_venc := coalesce(v_df.emissao_date, current_date) + 15;

  select pc.id into v_plano_contas_id
  from f.plano_contas pc
  where pc.tenant_id = v_df.tenant_id
    and pc.codigo = '3.01' -- RECEITA DE SERVICOS (você pode trocar depois por receita de venda de produto)
    and pc.deleted_at is null
  limit 1;

  if v_plano_contas_id is null then
    raise exception 'Plano de contas padrão (codigo=3.01) não encontrado para tenant %', v_df.tenant_id;
  end if;

  select t.id into v_titulo_id
  from f.titulo t
  where t.tenant_id = v_df.tenant_id
    and t.empresa_id = v_df.empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id,
      tipo, status, origem,
      cliente_id,
      documento_fiscal_id,
      descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto
    ) values (
      v_df.tenant_id, v_df.empresa_id,
      'AR', 'PENDENTE', 'FATURAMENTO',
      v_df.cliente_id,
      v_df.id,
      v_desc,
      v_df.emissao_date, v_df.competencia_date,
      v_valor, v_valor
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor)
    values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, 100.0000, v_valor);

  else
    update f.titulo
    set
      cliente_id = v_df.cliente_id,
      descricao = v_desc,
      emissao_date = v_df.emissao_date,
      competencia_date = v_df.competencia_date,
      valor_total = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor_total,0) then v_valor
        else valor_aberto
      end
    where id = v_titulo_id;

    update f.titulo_parcela
    set
      vencimento_date = v_venc,
      valor = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor,0) then v_valor
        else valor_aberto
      end
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and numero = '1'
      and deleted_at is null;

    update f.titulo_rateio
    set percentual = 100.0000,
        valor = v_valor,
        plano_contas_id = v_plano_contas_id
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;
  end if;

  return v_titulo_id;
end;
$$;


ALTER FUNCTION "f"."fn_upsert_ar_from_nfe_venda"("p_documento_fiscal_id" "uuid", "p_old_valor_total" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."fn_validar_pos_importacao"("p_documento_fiscal_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_xml int;
  v_itens int;
  v_impostos int;
  v_cp int;
begin
  select count(*) into v_xml
  from f.documento_fiscal_xml
  where documento_fiscal_id = p_documento_fiscal_id;

  select count(*) into v_itens
  from f.documento_fiscal_item
  where documento_fiscal_id = p_documento_fiscal_id;

  select count(*) into v_impostos
  from f.documento_fiscal_imposto
  where documento_fiscal_id = p_documento_fiscal_id;

  select count(*) into v_cp
  from public.contas_pagar_titulos
  where documento_fiscal_id = p_documento_fiscal_id;

  if v_xml = 0 then
    raise exception 'IMPORT INCOMPLETA: sem XML (documento_fiscal_xml) para documento_fiscal_id=%', p_documento_fiscal_id;
  end if;

  -- se você considera obrigatório sempre ter item fiscal quando tem XML:
  if v_itens = 0 then
    raise exception 'IMPORT INCOMPLETA: sem itens fiscais (documento_fiscal_item) para documento_fiscal_id=%', p_documento_fiscal_id;
  end if;

  -- se impostos forem obrigatórios no seu fluxo:
  -- if v_impostos = 0 then
  --   raise exception 'IMPORT INCOMPLETA: sem impostos (documento_fiscal_imposto) para documento_fiscal_id=%', p_documento_fiscal_id;
  -- end if;

  if v_cp = 0 then
    raise exception 'IMPORT INCOMPLETA: sem contas a pagar (contas_pagar_titulos) para documento_fiscal_id=%', p_documento_fiscal_id;
  end if;
end;
$$;


ALTER FUNCTION "f"."fn_validar_pos_importacao"("p_documento_fiscal_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."gerar_ap_pendente_por_nf_entrada"("p_nf_entrada_id" bigint, "p_force" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c', 'extensions'
    SET "row_security" TO 'off'
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_doc_id uuid;
  v_titulo_id uuid;
  v_competencia date;
  v_xml_hash text;
begin
  -- ✅ permite SQL Editor (postgres/service_role), mas mantém segurança no app
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'NF entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  -- permissão: no app continua exigindo ADMIN/FINANCEIRO
  if auth.uid() is not null then
    if not f.has_finance_access(v_nf.tenant_id, v_nf.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_competencia := date_trunc(
    'month',
    coalesce((v_nf.data_emissao at time zone 'America/Sao_Paulo')::date, current_date)
  )::date;

  select df.id into v_doc_id
  from f.documento_fiscal df
  where df.tenant_id = v_nf.tenant_id
    and df.source_nf_entrada_id = v_nf.id
    and df.deleted_at is null
  limit 1;

  if v_doc_id is not null and not p_force then
    return v_doc_id;
  end if;

  insert into f.documento_fiscal (
    tenant_id, empresa_id, source_nf_entrada_id,
    fornecedor_id, chave_acesso,
    modelo, serie, numero,
    emissao_date, competencia_date,
    valor_total, valor_produtos, valor_frete, valor_seguro, valor_desconto, valor_outros,
    finalidade_import, os_id_import,
    pagamento_import_json
  )
  values (
    v_nf.tenant_id, v_nf.empresa_id, v_nf.id,
    v_nf.fornecedor_id::int, v_nf.chave,
    null, v_nf.serie, v_nf.numero,
    (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
    v_competencia,
    coalesce(v_nf.valor_total, 0),
    coalesce(v_nf.valor_produtos, 0),
    coalesce(v_nf.valor_frete, 0),
    coalesce(v_nf.valor_seguro, 0),
    coalesce(v_nf.valor_desconto, 0),
    coalesce(v_nf.valor_outros, 0),
    v_nf.finalidade_contexto,
    v_nf.os_id,
    null
  )
  on conflict (tenant_id, source_nf_entrada_id)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    chave_acesso = excluded.chave_acesso,
    serie = excluded.serie,
    numero = excluded.numero,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    valor_produtos = excluded.valor_produtos,
    valor_frete = excluded.valor_frete,
    valor_seguro = excluded.valor_seguro,
    valor_desconto = excluded.valor_desconto,
    valor_outros = excluded.valor_outros,
    finalidade_import = excluded.finalidade_import,
    os_id_import = excluded.os_id_import,
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  returning id into v_doc_id;

  if v_nf.xml_raw is not null and length(v_nf.xml_raw) > 0 then
    v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');

    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_nf.tenant_id, v_doc_id, v_nf.chave, v_nf.xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id) do update set
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  select t.id into v_titulo_id
  from f.titulo t
  where t.tenant_id = v_nf.tenant_id
    and t.empresa_id = v_nf.empresa_id
    and t.documento_fiscal_id = v_doc_id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id,
      tipo, status, origem,
      fornecedor_id, documento_fiscal_id,
      descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto
    )
    values (
      v_nf.tenant_id, v_nf.empresa_id,
      'AP', 'PENDENTE', 'XML',
      v_nf.fornecedor_id::int, v_doc_id,
      ('NF-e ' || coalesce(v_nf.numero,'') || '/' || coalesce(v_nf.serie,'') || ' - ' || coalesce(v_nf.emitente_nome,'EMITENTE')),
      (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
      v_competencia,
      coalesce(v_nf.valor_total, 0),
      coalesce(v_nf.valor_total, 0)
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (
      tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto
    )
    values (
      v_nf.tenant_id,
      v_titulo_id,
      '001',
      (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
      coalesce(v_nf.valor_total, 0),
      coalesce(v_nf.valor_total, 0)
    );
  end if;

  return v_doc_id;
end;
$$;


ALTER FUNCTION "f"."gerar_ap_pendente_por_nf_entrada"("p_nf_entrada_id" bigint, "p_force" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."gerar_ap_pendente_por_nf_entrada_v2"("p_nf_entrada_id" bigint, "p_force" boolean DEFAULT false, "p_parcelas_json" "jsonb" DEFAULT NULL::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c', 'extensions'
    SET "row_security" TO 'off'
    AS $_$
declare
  v_nf public.nf_entrada%rowtype;
  v_doc_id uuid;
  v_titulo_id uuid;

  v_emissao_date date;
  v_competencia_date date;
  v_total numeric(15,2);

  v_xml_hash text;

  v_parcelas jsonb;
  v_soma numeric(15,2) := 0;

  v_i int := 0;
  v_el jsonb;
  v_num text;
  v_venc date;
  v_val numeric(15,2);

  v_has_titulo_deleted_at boolean := false;
  v_has_parcela_deleted_at boolean := false;

  v_sql text;
  v_has_parcelas boolean := false;
  v_valor_aberto numeric(15,2) := 0;
begin
  select *
    into v_nf
  from public.nf_entrada n
  where n.id = p_nf_entrada_id
  limit 1;

  if v_nf.id is null then
    raise exception 'NF entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  -- Permissao:
  -- permite FINANCEIRO/ADMIN, OU quem tem capability xml_import.execute (para importacao gerar AP).
  if auth.uid() is not null then
    if not f.has_finance_access(v_nf.tenant_id, v_nf.empresa_id)
       and not public.can('xml_import','execute', v_nf.tenant_id)
    then
      raise exception 'Sem permissao para gerar contas a pagar (precisa FINANCEIRO/ADMIN ou xml_import.execute)';
    end if;
  end if;

  if v_nf.motivo_compra_id is null then
    raise exception 'NF sem motivo_compra_id. Importacao deve informar Classificacao/Motivo.';
  end if;

  if v_nf.solicitante_usuario_id is null then
    raise exception 'NF sem solicitante_usuario_id. Importacao deve informar solicitante.';
  end if;

  v_emissao_date := (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date;
  if v_emissao_date is null then
    v_emissao_date := (now() at time zone 'America/Sao_Paulo')::date;
  end if;

  v_competencia_date := date_trunc('month', v_emissao_date)::date;
  v_total := round(coalesce(v_nf.valor_total, 0), 2);

  -- Compat: algumas bases antigas nao tem deleted_at em f.titulo / f.titulo_parcela.
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'f'
      and table_name = 'titulo'
      and column_name = 'deleted_at'
  ) into v_has_titulo_deleted_at;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'f'
      and table_name = 'titulo_parcela'
      and column_name = 'deleted_at'
  ) into v_has_parcela_deleted_at;

  -- Documento fiscal (upsert por tenant + source_nf_entrada_id)
  insert into f.documento_fiscal (
    tenant_id,
    empresa_id,
    source_nf_entrada_id,
    fornecedor_id,
    chave_acesso,
    modelo,
    serie,
    numero,
    emissao_date,
    competencia_date,
    valor_total,
    valor_produtos,
    valor_frete,
    valor_seguro,
    valor_desconto,
    valor_outros,
    finalidade_import,
    os_id_import,
    pagamento_import_json
  )
  values (
    v_nf.tenant_id,
    v_nf.empresa_id,
    v_nf.id,
    v_nf.fornecedor_id::int,
    v_nf.chave,
    v_nf.modelo,
    v_nf.serie,
    v_nf.numero,
    v_emissao_date,
    v_competencia_date,
    v_total,
    round(coalesce(v_nf.valor_produtos, 0), 2),
    round(coalesce(v_nf.valor_frete, 0), 2),
    round(coalesce(v_nf.valor_seguro, 0), 2),
    round(coalesce(v_nf.valor_desconto, 0), 2),
    round(coalesce(v_nf.valor_outros, 0), 2),
    v_nf.finalidade_contexto,
    v_nf.os_id,
    p_parcelas_json
  )
  on conflict (tenant_id, source_nf_entrada_id)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    chave_acesso = excluded.chave_acesso,
    modelo = excluded.modelo,
    serie = excluded.serie,
    numero = excluded.numero,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    valor_produtos = excluded.valor_produtos,
    valor_frete = excluded.valor_frete,
    valor_seguro = excluded.valor_seguro,
    valor_desconto = excluded.valor_desconto,
    valor_outros = excluded.valor_outros,
    finalidade_import = excluded.finalidade_import,
    os_id_import = excluded.os_id_import,
    pagamento_import_json = excluded.pagamento_import_json,
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  returning id into v_doc_id;

  -- XML do documento (upsert)
  if v_nf.xml_raw is not null and length(v_nf.xml_raw) > 0 then
    v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');

    insert into f.documento_fiscal_xml (
      tenant_id,
      documento_fiscal_id,
      chave_acesso,
      xml_raw,
      xml_hash
    )
    values (
      v_nf.tenant_id,
      v_doc_id,
      v_nf.chave,
      v_nf.xml_raw,
      v_xml_hash
    )
    on conflict (tenant_id, documento_fiscal_id)
    do update set
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  -- Titulo AP (se existir e nao force, mantem; se force, recria parcelas)
  v_sql := '
    select t.id
    from f.titulo t
    where t.tenant_id = $1
      and t.empresa_id = $2
      and t.documento_fiscal_id = $3
      and t.tipo = ''AP''
      and t.origem = ''XML''';
  if v_has_titulo_deleted_at then
    v_sql := v_sql || ' and t.deleted_at is null';
  end if;
  v_sql := v_sql || ' limit 1';
  execute v_sql into v_titulo_id using v_nf.tenant_id, v_nf.empresa_id, v_doc_id;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id,
      empresa_id,
      tipo,
      status,
      origem,
      fornecedor_id,
      documento_fiscal_id,
      descricao,
      emissao_date,
      competencia_date,
      valor_total,
      valor_aberto,
      motivo_compra_id
    )
    values (
      v_nf.tenant_id,
      v_nf.empresa_id,
      'AP',
      'PENDENTE',
      'XML',
      v_nf.fornecedor_id::int,
      v_doc_id,
      ('NF-e ' || coalesce(v_nf.numero,'') || '/' || coalesce(v_nf.serie,'') || ' - ' || coalesce(v_nf.emitente_nome,'EMITENTE')),
      v_emissao_date,
      v_competencia_date,
      v_total,
      v_total,
      v_nf.motivo_compra_id
    )
    returning id into v_titulo_id;
  else
    -- Atualiza metadados do titulo (best-effort) e garante motivo
    update f.titulo
    set
      fornecedor_id = v_nf.fornecedor_id::int,
      emissao_date = v_emissao_date,
      competencia_date = v_competencia_date,
      valor_total = v_total,
      motivo_compra_id = v_nf.motivo_compra_id,
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
    where id = v_titulo_id
      and tenant_id = v_nf.tenant_id;

    if not p_force then
      -- Se ja existem parcelas, nao duplica.
      v_sql := '
        select exists(
          select 1
          from f.titulo_parcela tp
          where tp.tenant_id = $1
            and tp.titulo_id = $2';
      if v_has_parcela_deleted_at then
        v_sql := v_sql || ' and tp.deleted_at is null';
      end if;
      v_sql := v_sql || ' limit 1
        )';
      execute v_sql into v_has_parcelas using v_nf.tenant_id, v_titulo_id;
      if coalesce(v_has_parcelas,false) then
        return v_titulo_id;
      end if;
    else
      -- Soft delete parcelas antigas (quando existir coluna). Caso contrario, remove.
      if v_has_parcela_deleted_at then
        update f.titulo_parcela
        set deleted_at = now(),
            updated_at = now(),
            updated_by = a.fn_current_usuario_id()
        where tenant_id = v_nf.tenant_id
          and titulo_id = v_titulo_id
          and deleted_at is null;
      else
        delete from f.titulo_parcela
        where tenant_id = v_nf.tenant_id
          and titulo_id = v_titulo_id;
      end if;
    end if;
  end if;

  -- Parcelas: se vier array cria N parcelas; senao cria 001 a vista
  v_parcelas := coalesce(p_parcelas_json, '[]'::jsonb);

  if jsonb_typeof(v_parcelas) = 'array' and jsonb_array_length(v_parcelas) > 0 then
    v_i := 0;
    v_soma := 0;

    for v_el in select * from jsonb_array_elements(v_parcelas)
    loop
      v_num := coalesce(nullif(trim(v_el->>'numero'),''), lpad((v_i+1)::text, 3, '0'));
      v_num := regexp_replace(v_num, '\D', '', 'g');
      if v_num is null or v_num = '' then
        v_num := lpad((v_i+1)::text, 3, '0');
      else
        v_num := lpad(v_num, 3, '0');
      end if;

      v_venc := nullif(trim(v_el->>'vencimento'), '')::date;
      v_val := round(coalesce(nullif(trim(v_el->>'valor'), '')::numeric, 0), 2);

      if v_venc is null then
        raise exception 'Parcela sem vencimento_date (numero=%)', v_num;
      end if;
      if v_val <= 0 then
        raise exception 'Parcela com valor invalido (numero=% valor=%)', v_num, v_val;
      end if;

      insert into f.titulo_parcela (
        tenant_id,
        titulo_id,
        numero,
        vencimento_date,
        valor,
        valor_aberto
      )
      values (
        v_nf.tenant_id,
        v_titulo_id,
        v_num,
        v_venc,
        v_val,
        v_val
      );

      v_soma := round(v_soma + v_val, 2);
      v_i := v_i + 1;
    end loop;

    if abs(v_soma - v_total) > 0.05 then
      raise exception 'Soma das parcelas (%) difere do total da NF (%)', v_soma, v_total;
    end if;
  else
    insert into f.titulo_parcela (
      tenant_id,
      titulo_id,
      numero,
      vencimento_date,
      valor,
      valor_aberto
    )
    values (
      v_nf.tenant_id,
      v_titulo_id,
      '001',
      v_emissao_date,
      v_total,
      v_total
    );
  end if;

  -- Ajusta valor em aberto do titulo
  v_sql := '
    select coalesce(sum(tp.valor_aberto), 0)
    from f.titulo_parcela tp
    where tp.tenant_id = $1
      and tp.titulo_id = $2';
  if v_has_parcela_deleted_at then
    v_sql := v_sql || ' and tp.deleted_at is null';
  end if;
  execute v_sql into v_valor_aberto using v_nf.tenant_id, v_titulo_id;

  update f.titulo
  set valor_aberto = coalesce(v_valor_aberto, 0),
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
  where id = v_titulo_id
    and tenant_id = v_nf.tenant_id;

  -- log (opcional, mas ajuda suporte)
  insert into f.importacao_doc_log (
    tenant_id,
    empresa_id,
    documento_fiscal_id,
    origem,
    status,
    mensagem,
    payload
  )
  values (
    v_nf.tenant_id,
    v_nf.empresa_id,
    v_doc_id,
    'XML',
    'SUCESSO',
    'AP gerado a partir de NF importada',
    jsonb_build_object('nf_entrada_id', v_nf.id, 'titulo_id', v_titulo_id)
  );

  return v_titulo_id;
end;
$_$;


ALTER FUNCTION "f"."gerar_ap_pendente_por_nf_entrada_v2"("p_nf_entrada_id" bigint, "p_force" boolean, "p_parcelas_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."gerar_ap_por_nf_entrada"("p_nf_entrada_id" bigint, "p_motivo_compra_id" "uuid" DEFAULT NULL::"uuid", "p_parcelas_json" "jsonb" DEFAULT NULL::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public'
    AS $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();

  v_nf public.nf_entrada%rowtype;

  v_motivo uuid;
  v_doc_id uuid;
  v_titulo_id uuid;

  v_total numeric(15,2);
  v_emissao_date date;

  r jsonb;
  v_num text;
  v_venc date;
  v_val numeric(15,2);
  v_sum numeric(15,2) := 0;
begin
  select *
    into v_nf
    from public.nf_entrada
   where id = p_nf_entrada_id
     and tenant_id = v_tenant_id
     and empresa_id = v_empresa_id
     and deleted_at is null;

  if not found then
    raise exception 'NF entrada % não encontrada para este tenant/empresa.', p_nf_entrada_id;
  end if;

  v_motivo := coalesce(p_motivo_compra_id, v_nf.motivo_compra_id);
  if v_motivo is null then
    raise exception 'motivo_compra_id é obrigatório para gerar Contas a Pagar (XML).';
  end if;

  v_total := coalesce(v_nf.valor_total, 0)::numeric(15,2);
  v_emissao_date := (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date;

  -- Documento fiscal (não duplica)
  select id
    into v_doc_id
    from f.documento_fiscal
   where tenant_id = v_tenant_id
     and empresa_id = v_empresa_id
     and source_nf_entrada_id = v_nf.id
     and deleted_at is null
   limit 1;

  if v_doc_id is null then
    insert into f.documento_fiscal (
      tenant_id, empresa_id,
      chave_acesso, modelo, serie, numero,
      emissao_date, valor_total, xml_raw,
      source_nf_entrada_id,
      finalidade_import, os_id_import, pagamento_import_json,
      created_at, updated_at, created_by, updated_by, deleted_at
    ) values (
      v_tenant_id, v_empresa_id,
      v_nf.chave, v_nf.modelo, v_nf.serie, v_nf.numero,
      v_emissao_date, v_total, v_nf.xml_raw,
      v_nf.id,
      v_nf.finalidade, v_nf.os_id, v_nf.pagamento_import_json,
      now(), now(), auth.uid(), auth.uid(), null
    )
    returning id into v_doc_id;
  end if;

  -- Título AP (não duplica)
  select id
    into v_titulo_id
    from f.titulo
   where tenant_id = v_tenant_id
     and empresa_id = v_empresa_id
     and documento_fiscal_id = v_doc_id
     and tipo = 'AP'
     and deleted_at is null
   limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id,
      tipo, status, origem,
      fornecedor_id, cliente_id, documento_fiscal_id,
      descricao, emissao_date, competencia_date,
      valor_total, valor_aberto,
      created_at, updated_at, created_by, updated_by, deleted_at,
      motivo_compra_id, classificacao_id
    ) values (
      v_tenant_id, v_empresa_id,
      'AP', 'PENDENTE', 'XML',
      v_nf.fornecedor_id, null, v_doc_id,
      format('NF-e %s/%s - %s',
        coalesce(v_nf.numero::text,''),
        coalesce(v_nf.serie::text,''),
        coalesce(v_nf.fornecedor_nome,'FORNECEDOR')
      ),
      v_emissao_date,
      date_trunc('month', v_emissao_date)::date,
      v_total, v_total,
      now(), now(), auth.uid(), auth.uid(), null,
      v_motivo, null
    )
    returning id into v_titulo_id;
  else
    -- garante motivo se o título já existe
    update f.titulo
       set motivo_compra_id = v_motivo,
           updated_at = now(),
           updated_by = auth.uid()
     where id = v_titulo_id
       and motivo_compra_id is distinct from v_motivo;
  end if;

  -- Se já existem parcelas, não duplica
  if exists (
    select 1
      from f.titulo_parcela
     where tenant_id = v_tenant_id
       and titulo_id = v_titulo_id
       and deleted_at is null
  ) then
    return v_titulo_id;
  end if;

  -- Parcelas
  if p_parcelas_json is null
     or jsonb_typeof(p_parcelas_json) <> 'array'
     or jsonb_array_length(p_parcelas_json) = 0 then

    insert into f.titulo_parcela (
      tenant_id, titulo_id,
      numero, vencimento_date,
      valor, valor_aberto,
      created_at, updated_at, created_by, updated_by, deleted_at
    ) values (
      v_tenant_id, v_titulo_id,
      '001', v_emissao_date,
      v_total, v_total,
      now(), now(), auth.uid(), auth.uid(), null
    );

  else
    v_sum := 0;

    for r in select jsonb_array_elements(p_parcelas_json)
    loop
      v_num := lpad(coalesce(nullif(trim(r->>'numero'), ''), '1'), 3, '0');
      v_venc := (r->>'vencimento')::date;
      v_val := (r->>'valor')::numeric(15,2);

      if v_val is null or v_val <= 0 then
        continue;
      end if;

      v_sum := v_sum + v_val;

      insert into f.titulo_parcela (
        tenant_id, titulo_id,
        numero, vencimento_date,
        valor, valor_aberto,
        created_at, updated_at, created_by, updated_by, deleted_at
      ) values (
        v_tenant_id, v_titulo_id,
        v_num, v_venc,
        v_val, v_val,
        now(), now(), auth.uid(), auth.uid(), null
      );
    end loop;

    if abs(v_sum - v_total) > 0.05 then
      raise exception 'Soma das parcelas (%) diferente do total da NF (%).', v_sum, v_total;
    end if;
  end if;

  -- ajusta valor em aberto do título
  update f.titulo
     set valor_aberto = (
           select coalesce(sum(tp.valor_aberto), 0)
             from f.titulo_parcela tp
            where tp.tenant_id = v_tenant_id
              and tp.titulo_id = v_titulo_id
              and tp.deleted_at is null
         ),
         updated_at = now(),
         updated_by = auth.uid()
   where id = v_titulo_id;

  return v_titulo_id;
end;
$$;


ALTER FUNCTION "f"."gerar_ap_por_nf_entrada"("p_nf_entrada_id" bigint, "p_motivo_compra_id" "uuid", "p_parcelas_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."gerar_titulo_ar_do_documento"("p_documento_fiscal_id" "uuid", "p_vencimento_date" "date", "p_plano_contas_id" "uuid", "p_centro_custo_id" "uuid" DEFAULT NULL::"uuid", "p_os_id" integer DEFAULT NULL::integer, "p_descricao" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
declare
  v_df record;
  v_titulo_id uuid;
  v_desc text;
begin
  if p_documento_fiscal_id is null then
    raise exception 'documento_fiscal_id é obrigatório.';
  end if;

  if p_vencimento_date is null then
    raise exception 'vencimento_date é obrigatório para gerar Contas a Receber.';
  end if;

  if p_plano_contas_id is null then
    raise exception 'plano_contas_id (classificação) é obrigatório para gerar Contas a Receber.';
  end if;

  select *
    into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then
    raise exception 'Documento fiscal não encontrado: %', p_documento_fiscal_id;
  end if;

  -- Permissão
  if not f.has_finance_access(v_df.tenant_id, v_df.empresa_id) then
    raise exception 'Sem permissão financeira para gerar Contas a Receber.';
  end if;

  -- Só faz sentido para faturamento (SAÍDA)
  if coalesce(v_df.operacao,'') <> 'SAIDA' then
    raise exception 'Somente documentos com operacao=SAIDA geram Contas a Receber. Documento está em: %', v_df.operacao;
  end if;

  -- AR precisa de cliente
  if v_df.cliente_id is null then
    raise exception 'cliente_id é obrigatório no documento fiscal para gerar Contas a Receber.';
  end if;

  -- Evitar duplicar (soft delete respeitado)
  select t.id
    into v_titulo_id
  from f.titulo t
  where t.tenant_id = v_df.tenant_id
    and t.empresa_id = v_df.empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is not null then
    return v_titulo_id;
  end if;

  v_desc := coalesce(
    nullif(btrim(p_descricao), ''),
    concat(coalesce(v_df.modelo,'DOC'), ' ', coalesce(v_df.numero,''), '/', coalesce(v_df.serie,''))
  );

  -- Título (AR)
  insert into f.titulo (
    tenant_id,
    empresa_id,
    tipo,
    status,
    origem,
    cliente_id,
    documento_fiscal_id,
    descricao,
    emissao_date,
    competencia_date,
    valor_total,
    valor_aberto
  ) values (
    v_df.tenant_id,
    v_df.empresa_id,
    'AR',
    'PENDENTE',
    'FATURAMENTO',
    v_df.cliente_id,
    v_df.id,
    v_desc,
    v_df.emissao_date,
    v_df.competencia_date,
    coalesce(v_df.valor_total, 0),
    coalesce(v_df.valor_total, 0)
  )
  returning id into v_titulo_id;

  -- Parcela única (numero é TEXT na sua tabela)
  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    valor_aberto
  ) values (
    v_df.tenant_id,
    v_titulo_id,
    '1',
    p_vencimento_date,
    coalesce(v_df.valor_total, 0),
    coalesce(v_df.valor_total, 0)
  );

  -- Rateio (100% no plano de contas)
  insert into f.titulo_rateio (
    tenant_id,
    titulo_id,
    plano_contas_id,
    centro_custo_id,
    os_id,
    percentual,
    valor
  ) values (
    v_df.tenant_id,
    v_titulo_id,
    p_plano_contas_id,
    p_centro_custo_id,
    p_os_id,
    100.0000,
    coalesce(v_df.valor_total, 0)
  );

  return v_titulo_id;
end;
$$;


ALTER FUNCTION "f"."gerar_titulo_ar_do_documento"("p_documento_fiscal_id" "uuid", "p_vencimento_date" "date", "p_plano_contas_id" "uuid", "p_centro_custo_id" "uuid", "p_os_id" integer, "p_descricao" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."has_cobranca_access"("p_tenant" "uuid" DEFAULT "public"."current_tenant_id"(), "p_empresa" "uuid" DEFAULT "public"."current_empresa_id"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
  select f.has_finance_access(p_tenant, p_empresa);
$$;


ALTER FUNCTION "f"."has_cobranca_access"("p_tenant" "uuid", "p_empresa" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."has_finance_access"("p_tenant" "uuid" DEFAULT "public"."current_tenant_id"(), "p_empresa" "uuid" DEFAULT "public"."current_empresa_id"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
  select
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = public.current_auth_user_id()
        and ut.tenant_id = p_tenant
        and ut.ativo = true
        and ut.deleted_at is null
        and ut.papel in ('OWNER','ADMIN')
    )
    or
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.auth_user_id = public.current_auth_user_id()
        and ue.empresa_id = p_empresa
        and ue.ativo = true
        and ue.deleted_at is null
        and ue.papel in ('ADMIN','FINANCEIRO')
        and e.deleted_at is null
        and e.tenant_id = p_tenant
    );
$$;


ALTER FUNCTION "f"."has_finance_access"("p_tenant" "uuid", "p_empresa" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."has_motivo_compra_access"("p_tenant_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a', 'c', 'f'
    SET "row_security" TO 'off'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa e on e.id = ue.empresa_id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ue.ativo is true
      and ue.deleted_at is null
      and e.deleted_at is null
      and e.tenant_id = p_tenant_id
      and upper(trim(coalesce(ue.papel, ''))) in (
        'ADMIN',
        'FINANCEIRO',
        'COORDENACAO',
        'COMPRAS',
        'ALMOXARIFADO',
        'APONTAMENTO_RH'
      )
  );
$$;


ALTER FUNCTION "f"."has_motivo_compra_access"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."ignorar_extrato_linha"("p_extrato_linha_id" "uuid", "p_motivo" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_linha f.extrato_bancario_linha%rowtype;
  v_user uuid;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_linha
  from f.extrato_bancario_linha
  where id = p_extrato_linha_id
    and deleted_at is null;

  if not found then
    raise exception 'Extrato linha nao encontrada (id=%)', p_extrato_linha_id;
  end if;

  -- permissão
  if auth.uid() is not null then
    if not f.has_finance_access() then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_linha.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  if v_linha.status <> 'PENDENTE' then
    raise exception 'Somente linha PENDENTE pode ser ignorada. Status atual=%', v_linha.status;
  end if;

  update f.extrato_bancario_linha
     set status = 'IGNORADO',
         observacoes = coalesce(observacoes,'') ||
           case when p_motivo is null or length(trim(p_motivo))=0 then '' else (' | IGNORADO: ' || p_motivo) end,
         updated_at = now(),
         updated_by = v_user
   where id = v_linha.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_linha.tenant_id,
    (select eb.empresa_id from f.extrato_bancario eb where eb.id = v_linha.extrato_bancario_id),
    'EXTRATO_LINHA_IGNORADA',
    'f.extrato_bancario_linha',
    v_linha.id,
    jsonb_build_object(
      'motivo', p_motivo,
      'valor', v_linha.valor,
      'data_movimento', v_linha.data_movimento
    ),
    now(), v_user
  );
end;
$$;


ALTER FUNCTION "f"."ignorar_extrato_linha"("p_extrato_linha_id" "uuid", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."nfe_gravar_impostos_da_nf_entrada"("p_nf_entrada_id" bigint, "p_documento_fiscal_id" "uuid", "p_tenant_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
declare
  v_xml_text text;
  v_xml xml;

  v_operacao text;
  v_doc_natureza text;
  v_natureza_padrao text;

  v_now timestamptz := now();

  -- totais
  v_vprod   numeric := 0;

  v_vbc_icms numeric := 0;
  v_vicms    numeric := 0;

  v_vipi     numeric := 0;
  v_vpis     numeric := 0;
  v_vcofins  numeric := 0;

  -- bases (quando precisar)
  v_base_ipi    numeric := 0;
  v_base_pis    numeric := 0;
  v_base_cofins numeric := 0;

  -- aliquotas
  v_aliq_icms numeric := 0;
  v_aliq_ipi numeric := 0;
  v_aliq_pis numeric := 0;
  v_aliq_cofins numeric := 0;

  v_cnt int;
  v_single numeric;
begin
  if p_nf_entrada_id is null then raise exception 'nf_entrada_id é obrigatório.'; end if;
  if p_documento_fiscal_id is null then raise exception 'documento_fiscal_id é obrigatório.'; end if;
  if p_tenant_id is null then raise exception 'tenant_id é obrigatório.'; end if;

  select df.operacao, df.natureza
    into v_operacao, v_doc_natureza
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.tenant_id = p_tenant_id
    and df.deleted_at is null;

  if not found then
    raise exception 'Documento fiscal não encontrado (id=% tenant_id=%).', p_documento_fiscal_id, p_tenant_id;
  end if;

  if v_operacao = 'ENTRADA' then
    v_natureza_padrao := 'CREDITO';
  else
    v_natureza_padrao := 'DEBITO';
  end if;

  -- lê o XML da NF de entrada
  select ne.xml_raw
    into v_xml_text
  from public.nf_entrada ne
  where ne.id = p_nf_entrada_id;

  if v_xml_text is null or btrim(v_xml_text) = '' then
    raise exception 'XML vazio em public.nf_entrada.id=% (coluna xml_raw).', p_nf_entrada_id;
  end if;

  v_xml := v_xml_text::xml;

  --------------------------------------------------------------------
  -- TOTAIS: tenta em ICMSTot; se vier zerado, soma por item.
  -- (sempre usando local-name() para ignorar namespace)
  --------------------------------------------------------------------

  v_vprod := f._xpath_first_num_anyns(v_xml, '//*[local-name()="ICMSTot"]/*[local-name()="vProd"]/text()');

  v_vbc_icms := f._xpath_first_num_anyns(v_xml, '//*[local-name()="ICMSTot"]/*[local-name()="vBC"]/text()');
  v_vicms    := f._xpath_first_num_anyns(v_xml, '//*[local-name()="ICMSTot"]/*[local-name()="vICMS"]/text()');

  v_vipi     := f._xpath_first_num_anyns(v_xml, '//*[local-name()="ICMSTot"]/*[local-name()="vIPI"]/text()');
  v_vpis     := f._xpath_first_num_anyns(v_xml, '//*[local-name()="ICMSTot"]/*[local-name()="vPIS"]/text()');
  v_vcofins  := f._xpath_first_num_anyns(v_xml, '//*[local-name()="ICMSTot"]/*[local-name()="vCOFINS"]/text()');

  -- Fallback: soma por item (quando totais vierem 0)
  if v_vbc_icms = 0 then
    v_vbc_icms := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="ICMS"]//*[local-name()="vBC"]/text()');
  end if;
  if v_vicms = 0 then
    v_vicms := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="ICMS"]//*[local-name()="vICMS"]/text()');
  end if;

  if v_vipi = 0 then
    v_vipi := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="IPI"]//*[local-name()="vIPI"]/text()');
  end if;

  if v_vpis = 0 then
    v_vpis := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="PIS"]//*[local-name()="vPIS"]/text()');
  end if;

  if v_vcofins = 0 then
    v_vcofins := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="COFINS"]//*[local-name()="vCOFINS"]/text()');
  end if;

  --------------------------------------------------------------------
  -- BASES (quando existirem por item); senão, usa vProd.
  --------------------------------------------------------------------
  v_base_ipi := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="IPI"]//*[local-name()="vBC"]/text()');
  if v_base_ipi = 0 then v_base_ipi := v_vprod; end if;

  v_base_pis := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="PIS"]//*[local-name()="vBC"]/text()');
  if v_base_pis = 0 then v_base_pis := v_vprod; end if;

  v_base_cofins := f._xpath_sum_num_anyns(v_xml, '//*[local-name()="det"]//*[local-name()="COFINS"]//*[local-name()="vBC"]/text()');
  if v_base_cofins = 0 then v_base_cofins := v_vprod; end if;

  --------------------------------------------------------------------
  -- ALÍQUOTAS: se existir 1 única alíquota, usa ela; senão calcula.
  --------------------------------------------------------------------

  -- ICMS pICMS
  select count(distinct (x::text)::numeric), max((x::text)::numeric)
    into v_cnt, v_single
  from unnest(xpath('//*[local-name()="det"]//*[local-name()="ICMS"]//*[local-name()="pICMS"]/text()', v_xml)) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_icms := round(v_single, 4);
  else
    v_aliq_icms := case when v_vbc_icms > 0 then round((v_vicms / v_vbc_icms) * 100, 4) else 0 end;
  end if;

  -- IPI pIPI
  select count(distinct (x::text)::numeric), max((x::text)::numeric)
    into v_cnt, v_single
  from unnest(xpath('//*[local-name()="det"]//*[local-name()="IPI"]//*[local-name()="pIPI"]/text()', v_xml)) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_ipi := round(v_single, 4);
  else
    v_aliq_ipi := case when v_base_ipi > 0 then round((v_vipi / v_base_ipi) * 100, 4) else 0 end;
  end if;

  -- PIS pPIS
  select count(distinct (x::text)::numeric), max((x::text)::numeric)
    into v_cnt, v_single
  from unnest(xpath('//*[local-name()="det"]//*[local-name()="PIS"]//*[local-name()="pPIS"]/text()', v_xml)) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_pis := round(v_single, 4);
  else
    v_aliq_pis := case when v_base_pis > 0 then round((v_vpis / v_base_pis) * 100, 4) else 0 end;
  end if;

  -- COFINS pCOFINS
  select count(distinct (x::text)::numeric), max((x::text)::numeric)
    into v_cnt, v_single
  from unnest(xpath('//*[local-name()="det"]//*[local-name()="COFINS"]//*[local-name()="pCOFINS"]/text()', v_xml)) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_cofins := round(v_single, 4);
  else
    v_aliq_cofins := case when v_base_cofins > 0 then round((v_vcofins / v_base_cofins) * 100, 4) else 0 end;
  end if;

  --------------------------------------------------------------------
  -- UPSERT (tenant_id, documento_fiscal_id, imposto, natureza)
  --------------------------------------------------------------------

  -- ICMS
  if v_vicms > 0 or v_vbc_icms > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'ICMS', v_natureza_padrao,
      v_vbc_icms, 0, v_vbc_icms,
      v_aliq_icms, v_vicms, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;

  -- IPI
  if v_vipi > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'IPI', v_natureza_padrao,
      v_base_ipi, 0, v_base_ipi,
      v_aliq_ipi, v_vipi, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;

  -- PIS
  if v_vpis > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'PIS', v_natureza_padrao,
      v_base_pis, 0, v_base_pis,
      v_aliq_pis, v_vpis, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;

  -- COFINS
  if v_vcofins > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'COFINS', v_natureza_padrao,
      v_base_cofins, 0, v_base_cofins,
      v_aliq_cofins, v_vcofins, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;

end;
$$;


ALTER FUNCTION "f"."nfe_gravar_impostos_da_nf_entrada"("p_nf_entrada_id" bigint, "p_documento_fiscal_id" "uuid", "p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."nfe_gravar_impostos_da_nf_entrada_sem_xml"("p_nf_entrada_id" bigint, "p_documento_fiscal_id" "uuid", "p_tenant_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public'
    AS $$
declare
  v_operacao text;
  v_doc_natureza text;
  v_natureza_imposto text;

  v_base_prod numeric(15,2);
  v_vicms numeric(15,2);
  v_vipi numeric(15,2);
  v_vpis numeric(15,2);
  v_vcofins numeric(15,2);

  v_aliq_icms numeric(7,4);
  v_aliq_ipi numeric(7,4);
  v_aliq_pis numeric(7,4);
  v_aliq_cofins numeric(7,4);

  v_now timestamptz := now();
begin
  select df.operacao, df.natureza
    into v_operacao, v_doc_natureza
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.tenant_id = p_tenant_id
    and df.deleted_at is null;

  if not found then
    raise exception 'Documento fiscal % não encontrado (tenant %).', p_documento_fiscal_id, p_tenant_id;
  end if;

  if coalesce(v_doc_natureza,'') <> 'PRODUTO' then
    return;
  end if;

  v_natureza_imposto := case when v_operacao = 'ENTRADA' then 'CREDITO' else 'DEBITO' end;

  select
    coalesce(sum(i.v_prod),0)::numeric(15,2) as base_prod,
    coalesce(sum(i.v_icms),0)::numeric(15,2) as v_icms,
    coalesce(sum(i.v_ipi),0)::numeric(15,2) as v_ipi,
    coalesce(sum(i.v_pis),0)::numeric(15,2) as v_pis,
    coalesce(sum(i.v_cofins),0)::numeric(15,2) as v_cofins,
    case when coalesce(sum(i.v_prod),0) > 0 then round((sum(i.v_icms)/sum(i.v_prod))*100,4) else null end as aliq_icms,
    case when coalesce(sum(i.v_prod),0) > 0 then round((sum(i.v_ipi)/sum(i.v_prod))*100,4) else null end as aliq_ipi,
    case when coalesce(sum(i.v_prod),0) > 0 then round((sum(i.v_pis)/sum(i.v_prod))*100,4) else null end as aliq_pis,
    case when coalesce(sum(i.v_prod),0) > 0 then round((sum(i.v_cofins)/sum(i.v_prod))*100,4) else null end as aliq_cofins
  into
    v_base_prod, v_vicms, v_vipi, v_vpis, v_vcofins,
    v_aliq_icms, v_aliq_ipi, v_aliq_pis, v_aliq_cofins
  from public.nf_entrada_itens i
  where i.nf_entrada_id = p_nf_entrada_id
    and i.tenant_id = p_tenant_id;

  -- ICMS
  if coalesce(v_vicms,0) <> 0 then
    insert into f.documento_fiscal_imposto (
      id, tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at
    ) values (
      gen_random_uuid(), p_tenant_id, p_documento_fiscal_id, 'ICMS', v_natureza_imposto,
      v_base_prod, 0, v_base_prod,
      coalesce(v_aliq_icms,0), v_vicms, 0,
      v_now, v_now
    )
    on conflict on constraint uq_documento_fiscal_imposto__doc_imp_nat
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      updated_at = excluded.updated_at;
  end if;

  -- IPI
  if coalesce(v_vipi,0) <> 0 then
    insert into f.documento_fiscal_imposto (
      id, tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at
    ) values (
      gen_random_uuid(), p_tenant_id, p_documento_fiscal_id, 'IPI', v_natureza_imposto,
      v_base_prod, 0, v_base_prod,
      coalesce(v_aliq_ipi,0), v_vipi, 0,
      v_now, v_now
    )
    on conflict on constraint uq_documento_fiscal_imposto__doc_imp_nat
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      updated_at = excluded.updated_at;
  end if;

  -- PIS
  if coalesce(v_vpis,0) <> 0 then
    insert into f.documento_fiscal_imposto (
      id, tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at
    ) values (
      gen_random_uuid(), p_tenant_id, p_documento_fiscal_id, 'PIS', v_natureza_imposto,
      v_base_prod, 0, v_base_prod,
      coalesce(v_aliq_pis,0), v_vpis, 0,
      v_now, v_now
    )
    on conflict on constraint uq_documento_fiscal_imposto__doc_imp_nat
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      updated_at = excluded.updated_at;
  end if;

  -- COFINS
  if coalesce(v_vcofins,0) <> 0 then
    insert into f.documento_fiscal_imposto (
      id, tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at
    ) values (
      gen_random_uuid(), p_tenant_id, p_documento_fiscal_id, 'COFINS', v_natureza_imposto,
      v_base_prod, 0, v_base_prod,
      coalesce(v_aliq_cofins,0), v_vcofins, 0,
      v_now, v_now
    )
    on conflict on constraint uq_documento_fiscal_imposto__doc_imp_nat
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      updated_at = excluded.updated_at;
  end if;

end;
$$;


ALTER FUNCTION "f"."nfe_gravar_impostos_da_nf_entrada_sem_xml"("p_nf_entrada_id" bigint, "p_documento_fiscal_id" "uuid", "p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."nfe_gravar_impostos_do_documento"("p_documento_fiscal_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
declare
  v_df record;
begin
  select
    id,
    tenant_id,
    empresa_id,
    source_nf_entrada_id
  into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then
    raise exception 'Documento fiscal não encontrado: %', p_documento_fiscal_id;
  end if;

  if v_df.source_nf_entrada_id is null then
    raise exception 'Documento fiscal % não tem source_nf_entrada_id preenchido.', p_documento_fiscal_id;
  end if;

  perform f.nfe_gravar_impostos_da_nf_entrada(v_df.source_nf_entrada_id, v_df.id, v_df.tenant_id);
end;
$$;


ALTER FUNCTION "f"."nfe_gravar_impostos_do_documento"("p_documento_fiscal_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."nfe_gravar_impostos_entrada_do_documento"("p_documento_fiscal_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $_$
declare
  v_df record;
  v_xml_col text;
  v_xml_text text;
  v_xml xml;

  v_vbc_icms numeric;
  v_vicms numeric;

  v_vipi numeric;
  v_base_ipi numeric;

  v_vpis numeric;
  v_base_pis numeric;

  v_vcofins numeric;
  v_base_cofins numeric;

  v_now timestamptz := now();

  v_aliq_icms numeric;
  v_aliq_ipi numeric;
  v_aliq_pis numeric;
  v_aliq_cofins numeric;

  v_cnt int;
  v_single numeric;

  v_natureza text := 'CREDITO';
begin
  select *
    into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then
    raise exception 'documento_fiscal não encontrado: %', p_documento_fiscal_id;
  end if;

  if v_df.operacao <> 'ENTRADA' then
    raise exception 'Esta função é somente para ENTRADA. operacao atual=%', v_df.operacao;
  end if;

  if v_df.source_nf_entrada_id is null then
    raise exception 'documento_fiscal sem source_nf_entrada_id (não consigo achar o XML).';
  end if;

  -- Descobre a coluna do XML em public.nf_entrada
  select c.column_name
    into v_xml_col
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'nf_entrada'
    and c.column_name ilike '%xml%'
    and c.data_type in ('text','xml','character varying')
  order by
    case when c.column_name in ('xml','xml_raw','xml_text','conteudo_xml','arquivo_xml','xml_content') then 0 else 1 end,
    c.ordinal_position
  limit 1;

  if v_xml_col is null then
    raise exception 'Não encontrei coluna com XML em public.nf_entrada.';
  end if;

  execute format('select %I::text from public.nf_entrada where id = $1', v_xml_col)
    into v_xml_text
    using v_df.source_nf_entrada_id;

  if v_xml_text is null or btrim(v_xml_text) = '' then
    raise exception 'XML vazio em public.nf_entrada.id=% (coluna %).', v_df.source_nf_entrada_id, v_xml_col;
  end if;

  v_xml := v_xml_text::xml;

  -- Totais
  v_vbc_icms := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vBC/text()'), 0);
  v_vicms    := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vICMS/text()'), 0);

  v_vipi     := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vIPI/text()'), 0);
  v_vpis     := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vPIS/text()'), 0);
  v_vcofins  := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vCOFINS/text()'), 0);

  -- Bases por item (somando vBC)
  select coalesce(sum((x)::text::numeric), 0)
    into v_base_ipi
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:IPI//*[local-name()="vBC"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if v_base_ipi = 0 then
    v_base_ipi := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vProd/text()'), 0);
  end if;

  select coalesce(sum((x)::text::numeric), 0)
    into v_base_pis
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:PIS//*[local-name()="vBC"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  select coalesce(sum((x)::text::numeric), 0)
    into v_base_cofins
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:COFINS//*[local-name()="vBC"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if v_base_pis = 0 then
    v_base_pis := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vProd/text()'), 0);
  end if;
  if v_base_cofins = 0 then
    v_base_cofins := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vProd/text()'), 0);
  end if;

  -- Alíquotas (fonte do XML quando única; senão calcula)
  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:ICMS//*[local-name()="pICMS"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_icms := round(v_single, 4);
  else
    v_aliq_icms := case when v_vbc_icms > 0 then round((v_vicms / v_vbc_icms) * 100, 4) else 0 end;
  end if;

  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:IPI//*[local-name()="pIPI"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_ipi := round(v_single, 4);
  else
    v_aliq_ipi := case when v_base_ipi > 0 then round((v_vipi / v_base_ipi) * 100, 4) else 0 end;
  end if;

  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:PIS//*[local-name()="pPIS"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_pis := round(v_single, 4);
  else
    v_aliq_pis := case when v_base_pis > 0 then round((v_vpis / v_base_pis) * 100, 4) else 0 end;
  end if;

  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:COFINS//*[local-name()="pCOFINS"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_cofins := round(v_single, 4);
  else
    v_aliq_cofins := case when v_base_cofins > 0 then round((v_vcofins / v_base_cofins) * 100, 4) else 0 end;
  end if;

  -- UPSERT: CREDITO
  if v_vicms > 0 or v_vbc_icms > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'ICMS', v_natureza,
      v_vbc_icms, 0, v_vbc_icms, v_aliq_icms,
      v_vicms, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original=excluded.base_original,
      deducoes=excluded.deducoes,
      base_calculo=excluded.base_calculo,
      aliquota=excluded.aliquota,
      valor_calculado=excluded.valor_calculado,
      valor_ajustado=excluded.valor_ajustado,
      updated_at=excluded.updated_at,
      deleted_at=null;
  end if;

  if v_vipi > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'IPI', v_natureza,
      v_base_ipi, 0, v_base_ipi, v_aliq_ipi,
      v_vipi, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original=excluded.base_original,
      deducoes=excluded.deducoes,
      base_calculo=excluded.base_calculo,
      aliquota=excluded.aliquota,
      valor_calculado=excluded.valor_calculado,
      valor_ajustado=excluded.valor_ajustado,
      updated_at=excluded.updated_at,
      deleted_at=null;
  end if;

  if v_vpis > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'PIS', v_natureza,
      v_base_pis, 0, v_base_pis, v_aliq_pis,
      v_vpis, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original=excluded.base_original,
      deducoes=excluded.deducoes,
      base_calculo=excluded.base_calculo,
      aliquota=excluded.aliquota,
      valor_calculado=excluded.valor_calculado,
      valor_ajustado=excluded.valor_ajustado,
      updated_at=excluded.updated_at,
      deleted_at=null;
  end if;

  if v_vcofins > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'COFINS', v_natureza,
      v_base_cofins, 0, v_base_cofins, v_aliq_cofins,
      v_vcofins, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original=excluded.base_original,
      deducoes=excluded.deducoes,
      base_calculo=excluded.base_calculo,
      aliquota=excluded.aliquota,
      valor_calculado=excluded.valor_calculado,
      valor_ajustado=excluded.valor_ajustado,
      updated_at=excluded.updated_at,
      deleted_at=null;
  end if;

end;
$_$;


ALTER FUNCTION "f"."nfe_gravar_impostos_entrada_do_documento"("p_documento_fiscal_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."provisionar_ap_recorrencia"("p_recorrencia_id" "uuid", "p_meses_a_frente" integer DEFAULT 12, "p_change_reason" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_rec f.ap_recorrencia%rowtype;
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;

  v_i integer;
  v_month_first date;
  v_venc date;
  v_valor numeric(15,2);

  v_count integer := 0;
  v_exists uuid;
  v_last_valor numeric(15,2);
begin
  if p_recorrencia_id is null then
    raise exception 'p_recorrencia_id obrigat3rio';
  end if;

  -- Auth: app ou SQL Editor
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_rec
  from f.ap_recorrencia r
  where r.id = p_recorrencia_id
    and r.deleted_at is null
    and r.ativo = true;

  if not found then
    raise exception 'Recorr8ncia n3o encontrada/inativa';
  end if;

  v_tenant_id := v_rec.tenant_id;
  v_empresa_id := v_rec.empresa_id;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  if p_meses_a_frente is null or p_meses_a_frente < 0 then
    p_meses_a_frente := 0;
  end if;

  for v_i in 0..p_meses_a_frente loop
    v_month_first := f._month_first((current_date + (v_i || ' month')::interval)::date);

    -- evita duplicar por competencia
    select t.id into v_exists
    from f.titulo t
    where t.deleted_at is null
      and t.tenant_id = v_tenant_id
      and t.recorrencia_id = v_rec.id
      and t.competencia_date = v_month_first
    limit 1;

    if v_exists is not null then
      continue;
    end if;

    v_venc := f._safe_day_in_month(v_month_first, v_rec.dia_vencimento);

    v_valor := v_rec.valor_base;

    if v_rec.auto_copiar_valor then
      select t.valor_total
        into v_last_valor
      from f.titulo t
      where t.deleted_at is null
        and t.tenant_id = v_tenant_id
        and t.recorrencia_id = v_rec.id
        and t.competencia_date < v_month_first
      order by t.competencia_date desc nulls last
      limit 1;

      if v_last_valor is not null and v_last_valor > 0 then
        v_valor := v_last_valor;
      end if;
    end if;

    insert into f.titulo (
      tenant_id,
      empresa_id,
      tipo,
      status,
      fornecedor_id,
      descricao,
      emissao_date,
      competencia_date,
      valor_total,
      valor_aberto,
      recorrencia_id,
      motivo_compra_id,
      created_at,
      updated_at,
      created_by,
      updated_by,
      deleted_at
    ) values (
      v_tenant_id,
      v_empresa_id,
      'AP',
      'PENDENTE',
      v_rec.fornecedor_id,
      v_rec.descricao,
      current_date,
      v_month_first,
      v_valor,
      v_valor,
      v_rec.id,
      v_rec.motivo_compra_id,
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    ) returning id into v_exists;

    insert into f.titulo_parcela (
      tenant_id,
      titulo_id,
      numero,
      vencimento_date,
      valor,
      valor_aberto,
      created_at,
      updated_at,
      created_by,
      updated_by,
      deleted_at
    ) values (
      v_tenant_id,
      v_exists,
      '1',
      v_venc,
      v_valor,
      v_valor,
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;


ALTER FUNCTION "f"."provisionar_ap_recorrencia"("p_recorrencia_id" "uuid", "p_meses_a_frente" integer, "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."registrar_pagamento_ap"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor" numeric, "p_observacoes" "text" DEFAULT NULL::"text", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_cb f.conta_bancaria%rowtype;

  v_user uuid;
  v_pagamento_id uuid;

  v_restante numeric(15,2);
  v_alocar numeric(15,2);
  v_soma_aberto numeric(15,2);

  r record;
begin
  if p_valor is null or p_valor <= 0 then
    raise exception 'Valor de pagamento deve ser > 0';
  end if;

  if p_data_pagamento is null then
    raise exception 'Data de pagamento obrigatoria';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'Forma de pagamento obrigatoria';
  end if;

  if p_forma_pagamento not in ('PIX','BOLETO','TRANSFERENCIA','DINHEIRO','CARTAO','OUTROS') then
    raise exception 'Forma de pagamento invalida: %', p_forma_pagamento;
  end if;

  -- auth: app ou SQL Editor (postgres/service_role)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- fallback SQL Editor: pega um OWNER/ADMIN do tenant do título (depois que carregar título)
  -- (vamos carregar título antes de usar fallback)

  -- título
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Pagamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('APROVADO','AGENDADO','PAGO') then
    raise exception 'Titulo precisa estar APROVADO/AGENDADO/PAGO para pagar. Status atual=%', v_titulo.status;
  end if;

  if v_titulo.valor_aberto <= 0 then
    raise exception 'Titulo sem saldo em aberto';
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- fallback para SQL Editor caso fn_current_usuario_id() retorne null
  if v_user is null then
    select ut.usuario_id
      into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- conta bancária
  select * into v_cb
  from f.conta_bancaria
  where id = p_conta_bancaria_id
    and deleted_at is null;

  if not found then
    raise exception 'Conta bancaria nao encontrada (id=%)', p_conta_bancaria_id;
  end if;

  if v_cb.tenant_id <> v_titulo.tenant_id or v_cb.empresa_id <> v_titulo.empresa_id then
    raise exception 'Conta bancaria nao pertence ao mesmo tenant/empresa do titulo';
  end if;

  -- limita pagamento ao saldo aberto (proteção extra)
  if round(p_valor,2) > round(v_titulo.valor_aberto,2) then
    raise exception 'Pagamento (% ) maior que saldo em aberto do titulo (%)', round(p_valor,2), round(v_titulo.valor_aberto,2);
  end if;

  -- cria pagamento (cabeçalho)
  insert into f.pagamento (
    tenant_id, empresa_id,
    conta_bancaria_id,
    data_pagamento,
    forma_pagamento,
    valor,
    observacoes,
    pago_por,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    v_cb.id,
    p_data_pagamento,
    p_forma_pagamento,
    round(p_valor, 2),
    p_observacoes,
    v_user,
    now(), now(), v_user, v_user
  )
  returning id into v_pagamento_id;

  -- alocação: paga parcelas em aberto (ordem por vencimento)
  v_restante := round(p_valor, 2);

  for r in
    select id, valor_aberto
    from f.titulo_parcela
    where tenant_id = v_titulo.tenant_id
      and titulo_id = v_titulo.id
      and deleted_at is null
      and valor_aberto > 0
    order by vencimento_date asc, created_at asc
  loop
    exit when v_restante <= 0;

    v_alocar := least(r.valor_aberto, v_restante);

    insert into f.pagamento_item (
      tenant_id, pagamento_id, titulo_parcela_id, valor,
      created_at, created_by
    )
    values (
      v_titulo.tenant_id, v_pagamento_id, r.id, v_alocar,
      now(), v_user
    );

    update f.titulo_parcela
       set valor_aberto = round(valor_aberto - v_alocar, 2),
           updated_at = now(),
           updated_by = v_user
     where id = r.id;

    v_restante := round(v_restante - v_alocar, 2);
  end loop;

  if v_restante <> 0 then
    -- não deveria acontecer por causa do check contra saldo do título,
    -- mas mantém consistência
    raise exception 'Inconsistencia: restante=%', v_restante;
  end if;

  -- recalcula saldo do título
  select coalesce(sum(valor_aberto),0)::numeric(15,2)
    into v_soma_aberto
  from f.titulo_parcela
  where tenant_id = v_titulo.tenant_id
    and titulo_id = v_titulo.id
    and deleted_at is null;

  update f.titulo
     set valor_aberto = v_soma_aberto,
         status = case when v_soma_aberto = 0 then 'PAGO' else v_titulo.status end,
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  -- evento financeiro
  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'PAGAMENTO_REGISTRADO',
    'f.pagamento',
    v_pagamento_id,
    jsonb_build_object(
      'titulo_id', v_titulo.id,
      'conta_bancaria_id', v_cb.id,
      'data_pagamento', p_data_pagamento,
      'forma_pagamento', p_forma_pagamento,
      'valor', round(p_valor,2),
      'saldo_titulo_pos', v_soma_aberto,
      'change_reason', p_change_reason
    ),
    now(), v_user
  );

  return v_pagamento_id;
end;
$$;


ALTER FUNCTION "f"."registrar_pagamento_ap"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor" numeric, "p_observacoes" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."registrar_pagamento_ap_v2"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor_principal" numeric, "p_valor_juros" numeric DEFAULT 0, "p_valor_multa" numeric DEFAULT 0, "p_valor_desconto" numeric DEFAULT 0, "p_observacoes" "text" DEFAULT NULL::"text", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_cb f.conta_bancaria%rowtype;

  v_user uuid;
  v_pagamento_id uuid;

  v_total numeric(15,2);
  v_restante numeric(15,2);
  v_alocar numeric(15,2);
  v_soma_aberto numeric(15,2);

  r record;
begin
  if p_valor_principal is null or p_valor_principal <= 0 then
    raise exception 'Valor principal deve ser > 0';
  end if;

  if coalesce(p_valor_juros,0) < 0 or coalesce(p_valor_multa,0) < 0 or coalesce(p_valor_desconto,0) < 0 then
    raise exception 'Juros/Multa/Desconto não podem ser negativos';
  end if;

  if p_data_pagamento is null then
    raise exception 'Data de pagamento obrigatoria';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'Forma de pagamento obrigatoria';
  end if;

  if p_forma_pagamento not in ('PIX','BOLETO','TRANSFERENCIA','DINHEIRO','CARTAO','OUTROS') then
    raise exception 'Forma de pagamento invalida: %', p_forma_pagamento;
  end if;

  -- auth: app ou SQL Editor (postgres/service_role)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  select * into v_titulo
    from f.titulo
   where id = p_titulo_id
     and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Pagamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('APROVADO','AGENDADO','PAGO') then
    raise exception 'Titulo precisa estar APROVADO/AGENDADO/PAGO para pagar. Status atual=%', v_titulo.status;
  end if;

  if v_titulo.valor_aberto <= 0 then
    raise exception 'Titulo sem saldo em aberto';
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- fallback para SQL Editor caso fn_current_usuario_id() retorne null
  if v_user is null then
    select ut.usuario_id
      into v_user
      from a.usuario_tenant ut
     where ut.tenant_id = v_titulo.tenant_id
       and ut.ativo = true
       and ut.deleted_at is null
       and ut.papel in ('OWNER','ADMIN')
     order by ut.created_at nulls last
     limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  select * into v_cb
    from f.conta_bancaria
   where id = p_conta_bancaria_id
     and deleted_at is null;

  if not found then
    raise exception 'Conta bancaria nao encontrada (id=%)', p_conta_bancaria_id;
  end if;

  if v_cb.tenant_id <> v_titulo.tenant_id or v_cb.empresa_id <> v_titulo.empresa_id then
    raise exception 'Conta bancaria nao pertence ao mesmo tenant/empresa do titulo';
  end if;

  -- principal não pode exceder saldo do título
  if round(p_valor_principal,2) > round(v_titulo.valor_aberto,2) then
    raise exception 'Principal (%) maior que saldo em aberto do titulo (%)', round(p_valor_principal,2), round(v_titulo.valor_aberto,2);
  end if;

  v_total := round((p_valor_principal + coalesce(p_valor_juros,0) + coalesce(p_valor_multa,0) - coalesce(p_valor_desconto,0)), 2);

  if v_total <= 0 then
    raise exception 'Total do pagamento deve ser > 0 (principal + juros + multa - desconto)';
  end if;

  insert into f.pagamento (
    tenant_id, empresa_id,
    conta_bancaria_id,
    data_pagamento,
    forma_pagamento,
    valor,
    valor_principal,
    valor_juros,
    valor_multa,
    valor_desconto,
    observacoes,
    change_reason,
    pago_por,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    v_cb.id,
    p_data_pagamento,
    p_forma_pagamento,
    v_total,
    round(p_valor_principal,2),
    round(coalesce(p_valor_juros,0),2),
    round(coalesce(p_valor_multa,0),2),
    round(coalesce(p_valor_desconto,0),2),
    p_observacoes,
    p_change_reason,
    v_user,
    now(), now(), v_user, v_user
  )
  returning id into v_pagamento_id;

  -- baixa parcelas usando SOMENTE o principal
  v_restante := round(p_valor_principal, 2);

  for r in
    select id, valor_aberto
      from f.titulo_parcela
     where tenant_id = v_titulo.tenant_id
       and titulo_id = v_titulo.id
       and deleted_at is null
       and valor_aberto > 0
     order by vencimento_date asc, created_at asc
  loop
    exit when v_restante <= 0;

    v_alocar := least(r.valor_aberto, v_restante);

    insert into f.pagamento_item (
      tenant_id, empresa_id,
      pagamento_id, titulo_parcela_id, valor,
      change_reason,
      created_at, created_by, updated_at, updated_by
    )
    values (
      v_titulo.tenant_id, v_titulo.empresa_id,
      v_pagamento_id, r.id, v_alocar,
      p_change_reason,
      now(), v_user, now(), v_user
    );

    update f.titulo_parcela
       set valor_aberto = round(valor_aberto - v_alocar, 2),
           updated_at = now(),
           updated_by = v_user
     where id = r.id;

    v_restante := round(v_restante - v_alocar, 2);
  end loop;

  if v_restante <> 0 then
    raise exception 'Inconsistencia: restante(principal)=%', v_restante;
  end if;

  select coalesce(sum(valor_aberto),0)::numeric(15,2)
    into v_soma_aberto
    from f.titulo_parcela
   where tenant_id = v_titulo.tenant_id
     and titulo_id = v_titulo.id
     and deleted_at is null;

  update f.titulo
     set valor_aberto = v_soma_aberto,
         status = case when v_soma_aberto = 0 then 'PAGO' else v_titulo.status end,
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'PAGAMENTO_REGISTRADO',
    'f.pagamento',
    v_pagamento_id,
    jsonb_build_object(
      'titulo_id', v_titulo.id,
      'conta_bancaria_id', v_cb.id,
      'data_pagamento', p_data_pagamento,
      'forma_pagamento', p_forma_pagamento,
      'valor_total', v_total,
      'valor_principal', round(p_valor_principal,2),
      'juros', round(coalesce(p_valor_juros,0),2),
      'multa', round(coalesce(p_valor_multa,0),2),
      'desconto', round(coalesce(p_valor_desconto,0),2),
      'saldo_titulo_pos', v_soma_aberto,
      'change_reason', p_change_reason
    ),
    now(), v_user
  );

  return v_pagamento_id;
end;
$$;


ALTER FUNCTION "f"."registrar_pagamento_ap_v2"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor_principal" numeric, "p_valor_juros" numeric, "p_valor_multa" numeric, "p_valor_desconto" numeric, "p_observacoes" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."registrar_recebimento_ar"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor" numeric, "p_observacoes" "text" DEFAULT NULL::"text", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_pagamento_id uuid;
  v_titulo record;
  v_valor_restante numeric;
  v_parcela record;
  v_aplicado numeric;
  v_new_aberto numeric;
begin
  if p_titulo_id is null then
    raise exception 'p_titulo_id obrigatório';
  end if;
  if p_conta_bancaria_id is null then
    raise exception 'p_conta_bancaria_id obrigatório';
  end if;
  if p_data_pagamento is null then
    raise exception 'p_data_pagamento obrigatório';
  end if;
  if p_valor is null or p_valor <= 0 then
    raise exception 'p_valor deve ser > 0';
  end if;
  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'p_forma_pagamento obrigatório';
  end if;

  select *
    into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.deleted_at is null;

  if not found then
    raise exception 'Título não encontrado';
  end if;

  if v_titulo.tipo <> 'AR' then
    raise exception 'Somente AR pode receber (tipo=%)', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('APROVADO','AGENDADO','PAGO') then
    -- mirror AP function behaviour: require at least approved-ish.
    raise exception 'Status inválido para recebimento (status=%)', v_titulo.status;
  end if;

  if p_valor > v_titulo.valor_aberto then
    raise exception 'Valor maior que saldo em aberto';
  end if;

  insert into f.pagamento(
    tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_pagamento,
    forma_pagamento,
    valor,
    observacoes,
    change_reason
  )
  values (
    v_titulo.tenant_id,
    v_titulo.empresa_id,
    p_conta_bancaria_id,
    p_data_pagamento,
    p_forma_pagamento,
    p_valor,
    p_observacoes,
    p_change_reason
  )
  returning id into v_pagamento_id;

  v_valor_restante := p_valor;

  for v_parcela in
    select p.id, p.valor_aberto
    from f.titulo_parcela p
    where p.titulo_id = p_titulo_id
      and p.deleted_at is null
      and p.valor_aberto > 0
    order by p.vencimento_date asc, p.numero asc
  loop
    exit when v_valor_restante <= 0;

    v_aplicado := least(v_parcela.valor_aberto, v_valor_restante);

    insert into f.pagamento_item(
      tenant_id,
      empresa_id,
      pagamento_id,
      titulo_parcela_id,
      valor,
      change_reason
    )
    values (
      v_titulo.tenant_id,
      v_titulo.empresa_id,
      v_pagamento_id,
      v_parcela.id,
      v_aplicado,
      p_change_reason
    );

    update f.titulo_parcela
      set valor_aberto = valor_aberto - v_aplicado
    where id = v_parcela.id;

    v_valor_restante := v_valor_restante - v_aplicado;
  end loop;

  select coalesce(sum(p.valor_aberto), 0)
    into v_new_aberto
  from f.titulo_parcela p
  where p.titulo_id = p_titulo_id
    and p.deleted_at is null;

  update f.titulo
    set valor_aberto = v_new_aberto,
        status = case when v_new_aberto <= 0 then 'PAGO' else v_titulo.status end
  where id = p_titulo_id;

  return v_pagamento_id;
end;
$$;


ALTER FUNCTION "f"."registrar_recebimento_ar"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor" numeric, "p_observacoes" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."registrar_recebimento_ar_v2"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor_principal" numeric, "p_valor_juros" numeric DEFAULT 0, "p_valor_multa" numeric DEFAULT 0, "p_valor_desconto" numeric DEFAULT 0, "p_observacoes" "text" DEFAULT NULL::"text", "p_change_reason" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_pagamento_id uuid;
  v_titulo record;
  v_total numeric(15,2);
  v_valor_restante numeric(15,2);
  v_parcela record;
  v_aplicado numeric(15,2);
  v_new_aberto numeric(15,2);
  v_user uuid;
begin
  if p_titulo_id is null then raise exception 'p_titulo_id obrigatorio'; end if;
  if p_conta_bancaria_id is null then raise exception 'p_conta_bancaria_id obrigatorio'; end if;
  if p_data_pagamento is null then raise exception 'p_data_pagamento obrigatorio'; end if;

  if p_valor_principal is null or p_valor_principal <= 0 then
    raise exception 'Valor principal deve ser > 0';
  end if;

  if coalesce(p_valor_juros,0) < 0 or coalesce(p_valor_multa,0) < 0 or coalesce(p_valor_desconto,0) < 0 then
    raise exception 'Juros/Multa/Desconto nao podem ser negativos';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'p_forma_pagamento obrigatorio';
  end if;

  select *
    into v_titulo
    from f.titulo t
   where t.id = p_titulo_id
     and t.deleted_at is null;

  if not found then raise exception 'Titulo nao encontrado'; end if;

  if v_titulo.tipo <> 'AR' then
    raise exception 'Somente AR pode receber (tipo=%)', v_titulo.tipo;
  end if;

  -- Permite recebimento tambem quando AR estiver PENDENTE.
  if v_titulo.status not in ('PENDENTE','APROVADO','AGENDADO','PAGO') then
    raise exception 'Status invalido para recebimento (status=%)', v_titulo.status;
  end if;

  if round(p_valor_principal,2) > round(v_titulo.valor_aberto,2) then
    raise exception 'Principal (%) maior que saldo em aberto (%)', round(p_valor_principal,2), round(v_titulo.valor_aberto,2);
  end if;

  v_total := round((p_valor_principal + coalesce(p_valor_juros,0) + coalesce(p_valor_multa,0) - coalesce(p_valor_desconto,0)), 2);
  if v_total <= 0 then
    raise exception 'Total do recebimento deve ser > 0';
  end if;

  v_user := a.fn_current_usuario_id();

  insert into f.pagamento(
    tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_pagamento,
    forma_pagamento,
    valor,
    valor_principal,
    valor_juros,
    valor_multa,
    valor_desconto,
    observacoes,
    change_reason,
    pago_por,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.empresa_id,
    p_conta_bancaria_id,
    p_data_pagamento,
    p_forma_pagamento,
    v_total,
    round(p_valor_principal,2),
    round(coalesce(p_valor_juros,0),2),
    round(coalesce(p_valor_multa,0),2),
    round(coalesce(p_valor_desconto,0),2),
    p_observacoes,
    p_change_reason,
    v_user,
    now(), now(), v_user, v_user
  )
  returning id into v_pagamento_id;

  v_valor_restante := round(p_valor_principal,2);

  for v_parcela in
    select p.id, p.valor_aberto
      from f.titulo_parcela p
     where p.titulo_id = p_titulo_id
       and p.deleted_at is null
       and p.valor_aberto > 0
     order by p.vencimento_date asc, p.numero asc
  loop
    exit when v_valor_restante <= 0;

    v_aplicado := least(v_parcela.valor_aberto, v_valor_restante);

    insert into f.pagamento_item(
      tenant_id,
      empresa_id,
      pagamento_id,
      titulo_parcela_id,
      valor,
      change_reason,
      created_at, created_by, updated_at, updated_by
    )
    values (
      v_titulo.tenant_id,
      v_titulo.empresa_id,
      v_pagamento_id,
      v_parcela.id,
      v_aplicado,
      p_change_reason,
      now(), v_user, now(), v_user
    );

    update f.titulo_parcela
       set valor_aberto = round(valor_aberto - v_aplicado,2),
           updated_at = now(),
           updated_by = v_user
     where id = v_parcela.id;

    v_valor_restante := round(v_valor_restante - v_aplicado,2);
  end loop;

  select coalesce(sum(p.valor_aberto), 0)::numeric(15,2)
    into v_new_aberto
    from f.titulo_parcela p
   where p.titulo_id = p_titulo_id
     and p.deleted_at is null;

  update f.titulo
     set valor_aberto = v_new_aberto,
         status = case when v_new_aberto <= 0 then 'PAGO' else v_titulo.status end,
         updated_at = now(),
         updated_by = v_user
   where id = p_titulo_id;

  return v_pagamento_id;
end;
$$;


ALTER FUNCTION "f"."registrar_recebimento_ar_v2"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor_principal" numeric, "p_valor_juros" numeric, "p_valor_multa" numeric, "p_valor_desconto" numeric, "p_observacoes" "text", "p_change_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."seed_financeiro_defaults"("p_tenant" "uuid", "p_empresa" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
begin
  -- motivos padrão
  insert into f.motivo_compra (tenant_id, codigo, nome, requires_text, requires_os, ativo)
  values
    (p_tenant, 'OS', 'ORDEM DE SERVICO', false, true, true),
    (p_tenant, 'ESTOQUE', 'ESTOQUE', false, false, true),
    (p_tenant, 'INVESTIMENTO', 'INVESTIMENTO', false, false, true),
    (p_tenant, 'MANUTENCAO', 'MANUTENCAO', false, false, true),
    (p_tenant, 'EPI', 'EPI', false, false, true),
    (p_tenant, 'OUTROS', 'OUTROS', true, false, true)
  on conflict (tenant_id, codigo) do nothing;

  -- (opcional) garantir um fin_config por empresa
  insert into f.fin_config (tenant_id, empresa_id)
  values (p_tenant, p_empresa)
  on conflict (tenant_id, empresa_id) do nothing;
end;
$$;


ALTER FUNCTION "f"."seed_financeiro_defaults"("p_tenant" "uuid", "p_empresa" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_documento_fiscal__ar_nfe"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
begin
  if tg_op = 'UPDATE' then
    perform f.fn_upsert_ar_from_nfe_venda(new.id, old.valor_total);
  else
    perform f.fn_upsert_ar_from_nfe_venda(new.id, null);
  end if;
  return new;
end;
$$;


ALTER FUNCTION "f"."trg_documento_fiscal__ar_nfe"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_documento_fiscal__ar_nfse"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
begin
  if tg_op = 'UPDATE' then
    perform f.fn_upsert_ar_from_documento_fiscal_v2(new.id, old.valor_total);
  else
    perform f.fn_upsert_ar_from_documento_fiscal_v2(new.id, null);
  end if;

  return new;
end;
$$;


ALTER FUNCTION "f"."trg_documento_fiscal__ar_nfse"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_documento_fiscal_xml__valida_emitente_saida"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'c', 'a', 'extensions'
    AS $$
declare
  v_df record;
  v_empresa_cnpj text;
  v_emit_cnpj text;
  v_xml xml;
begin
  -- Documento fiscal relacionado
  select df.*
    into v_df
  from f.documento_fiscal df
  where df.id = new.documento_fiscal_id;

  if not found then
    return new;
  end if;

  -- Só valida faturamento (SAÍDA) de PRODUTO
  if coalesce(v_df.operacao,'') <> 'SAIDA' then
    return new;
  end if;

  if coalesce(v_df.natureza,'') <> 'PRODUTO' then
    return new;
  end if;

  -- CNPJ da empresa
  select e.cnpj
    into v_empresa_cnpj
  from c.empresa e
  where e.id = v_df.empresa_id
    and e.tenant_id = v_df.tenant_id
    and e.deleted_at is null;

  if v_empresa_cnpj is null or btrim(v_empresa_cnpj) = '' then
    raise exception 'Empresa sem CNPJ cadastrado em c.empresa.';
  end if;

  -- CNPJ do emitente do XML
  v_xml := xmlparse(document new.xml_raw);
  v_emit_cnpj := regexp_replace(
    coalesce(f._nfe_xpath_text(v_xml, '//nfe:emit/nfe:CNPJ/text()'), ''),
    '\D', '', 'g'
  );

  if v_emit_cnpj is null or btrim(v_emit_cnpj) = '' then
    raise exception 'XML inválido: não encontrei emit/CNPJ.';
  end if;

  if v_emit_cnpj <> v_empresa_cnpj then
    raise exception 'NF-e de faturamento recusada: emitente CNPJ % diferente do CNPJ da empresa %.',
      v_emit_cnpj, v_empresa_cnpj;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "f"."trg_documento_fiscal_xml__valida_emitente_saida"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_nfse_sync_piscofins_from_doc"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public'
    SET "row_security" TO 'off'
    AS $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.deleted_at is null
     and coalesce(new.modelo, '') = 'NFSE'
     and coalesce(new.operacao, '') = 'SAIDA'
     and coalesce(new.natureza, '') = 'SERVICO' then
    perform f.fn_nfse_sync_piscofins_debito_doc(new.id);
  end if;

  return new;
end;
$$;


ALTER FUNCTION "f"."trg_nfse_sync_piscofins_from_doc"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_nfse_sync_piscofins_from_imposto_ret"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public'
    SET "row_security" TO 'off'
    AS $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.deleted_at is null
     and new.imposto in ('PIS','COFINS')
     and new.natureza = 'RETENCAO' then
    perform f.fn_nfse_sync_piscofins_debito_doc(new.documento_fiscal_id);
  end if;

  return new;
end;
$$;


ALTER FUNCTION "f"."trg_nfse_sync_piscofins_from_imposto_ret"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_sync_rateio_apuracao_irpj_csll"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
begin
  if coalesce(new.origem,'') <> 'APURACAO_IRPJ_CSLL' then
    return new;
  end if;

  if tg_op = 'UPDATE' and coalesce(new.valor_total,0) = coalesce(old.valor_total,0) then
    return new;
  end if;

  update f.titulo_rateio tr
     set valor = round(coalesce(new.valor_total,0) * coalesce(tr.percentual,0) / 100.0, 2)
   where tr.tenant_id = new.tenant_id
     and tr.titulo_id = new.id
     and tr.deleted_at is null
     and tr.percentual is not null;

  return new;
end;
$$;


ALTER FUNCTION "f"."trg_sync_rateio_apuracao_irpj_csll"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_titulo__aplicar_credito_fiscal_manual"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    AS $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  -- Escopo correto: apenas AP MANUAL sem documento fiscal.
  -- Evita bloquear importacao XML com erro "somente ADMIN/FINANCEIRO".
  if coalesce(new.tipo,'') = 'AP'
     and upper(coalesce(new.origem,'')) = 'MANUAL'
     and new.documento_fiscal_id is null
  then
    perform 1 from f.fn_aplicar_credito_fiscal_manual_titulo(new.id, 'TRIGGER_TITULO_MANUAL');
  end if;

  return new;
end;
$$;


ALTER FUNCTION "f"."trg_titulo__aplicar_credito_fiscal_manual"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_titulo_ap_auto_rateio_por_motivo"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'f', 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_plano uuid;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if coalesce(new.tipo,'') <> 'AP' then
    return new;
  end if;

  -- se já tem rateio, não mexe
  if exists (
    select 1
    from f.titulo_rateio tr
    where tr.tenant_id = new.tenant_id
      and tr.titulo_id = new.id
      and tr.deleted_at is null
    limit 1
  ) then
    return new;
  end if;

  -- pega plano pelo motivo (se houver)
  if new.motivo_compra_id is not null then
    select mc.plano_contas_id
      into v_plano
    from f.motivo_compra mc
    where mc.tenant_id = new.tenant_id
      and mc.id = new.motivo_compra_id
      and mc.deleted_at is null
    limit 1;
  end if;

  -- fallback: DESP_GERAL (se existir)
  if v_plano is null then
    select pc.id
      into v_plano
    from f.plano_contas pc
    where pc.tenant_id = new.tenant_id
      and pc.codigo = 'DESP_GERAL'
      and pc.deleted_at is null
    limit 1;
  end if;

  if v_plano is null then
    -- sem plano, não cria rateio (evita exception)
    return new;
  end if;

  insert into f.titulo_rateio (
    tenant_id,
    titulo_id,
    plano_contas_id,
    percentual,
    valor
  ) values (
    new.tenant_id,
    new.id,
    v_plano,
    100.0000,
    coalesce(new.valor_total, 0)
  );

  return new;
end $$;


ALTER FUNCTION "f"."trg_titulo_ap_auto_rateio_por_motivo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "f"."trg_titulo_require_motivo_compra"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.tipo = 'AP' and coalesce(new.origem,'') = 'XML' then
    if new.motivo_compra_id is null then
      raise exception 'Classificação (motivo_compra_id) é obrigatória para título AP importado do XML.';
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "f"."trg_titulo_require_motivo_compra"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "f"."anexo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "ref_table" "text" NOT NULL,
    "ref_id" "uuid" NOT NULL,
    "arquivo_nome" "text" NOT NULL,
    "mime_type" "text",
    "storage_path" "text" NOT NULL,
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "uploaded_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "deleted_at" timestamp with time zone
);


ALTER TABLE "f"."anexo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."ap_recorrencia" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "fornecedor_id" integer,
    "descricao" "text" NOT NULL,
    "motivo_compra_id" "uuid",
    "dia_vencimento" integer NOT NULL,
    "auto_copiar_valor" boolean DEFAULT true NOT NULL,
    "valor_base" numeric(15,2) DEFAULT 0 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_ap_recorrencia__dia_vencimento" CHECK ((("dia_vencimento" >= 1) AND ("dia_vencimento" <= 31)))
);


ALTER TABLE "f"."ap_recorrencia" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."aprovacao_evento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "acao" "text" NOT NULL,
    "ref_table" "text" NOT NULL,
    "ref_id" "uuid" NOT NULL,
    "motivo" "text",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    CONSTRAINT "ck_aprovacao_evento__acao" CHECK (("acao" = ANY (ARRAY['APROVOU'::"text", 'REPROVOU'::"text"])))
);


ALTER TABLE "f"."aprovacao_evento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."arrendamento_contrato" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "fornecedor_id" integer NOT NULL,
    "motivo_compra_id" "uuid",
    "centro_custo_id" "uuid",
    "os_id" integer,
    "descricao" "text" NOT NULL,
    "data_inicio" "date" NOT NULL,
    "competencia_inicio" "date" NOT NULL,
    "prazo_meses" integer NOT NULL,
    "dia_vencimento" integer DEFAULT 20 NOT NULL,
    "valor_parcela" numeric(15,2) NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_arr_contrato__competencia_day1" CHECK ((EXTRACT(day FROM "competencia_inicio") = (1)::numeric)),
    CONSTRAINT "ck_arr_contrato__dia_venc" CHECK ((("dia_vencimento" >= 1) AND ("dia_vencimento" <= 31))),
    CONSTRAINT "ck_arr_contrato__prazo" CHECK ((("prazo_meses" >= 1) AND ("prazo_meses" <= 120))),
    CONSTRAINT "ck_arr_contrato__valor" CHECK (("valor_parcela" >= (0)::numeric))
);


ALTER TABLE "f"."arrendamento_contrato" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."arrendamento_parcela" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "competencia_date" "date" NOT NULL,
    "numero" integer NOT NULL,
    "vencimento_date" "date" NOT NULL,
    "valor" numeric(15,2) NOT NULL,
    "titulo_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_arr_parcela__competencia_day1" CHECK ((EXTRACT(day FROM "competencia_date") = (1)::numeric)),
    CONSTRAINT "ck_arr_parcela__numero" CHECK (("numero" >= 1)),
    CONSTRAINT "ck_arr_parcela__valor" CHECK (("valor" >= (0)::numeric))
);


ALTER TABLE "f"."arrendamento_parcela" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."centro_custo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "parent_id" "uuid",
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "f"."centro_custo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."conciliacao_bancaria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "conta_bancaria_id" "uuid" NOT NULL,
    "referencia" "text",
    "status" "text" DEFAULT 'ABERTA'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "extrato_linha_id" "uuid",
    "pagamento_id" "uuid",
    "valor_conciliado" numeric(15,2),
    "diferenca" numeric(15,2) DEFAULT 0,
    "conciliado_em" timestamp with time zone DEFAULT "now"(),
    "conciliado_por" "uuid",
    "observacoes" "text",
    "change_reason" "text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_conciliacao_bancaria__status" CHECK (("status" = ANY (ARRAY['CONCILIADO'::"text", 'DESCONCILIADO'::"text"])))
);


ALTER TABLE "f"."conciliacao_bancaria" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."conciliacao_lancamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "conciliacao_id" "uuid" NOT NULL,
    "data_lancamento" "date" NOT NULL,
    "descricao" "text" NOT NULL,
    "valor" numeric(15,2) NOT NULL,
    "pagamento_id" "uuid",
    "conciliado_em" timestamp with time zone,
    "conciliado_por" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"()
);


ALTER TABLE "f"."conciliacao_lancamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."conta_bancaria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "tipo" "text" DEFAULT 'BANCO'::"text" NOT NULL,
    "banco" "text",
    "agencia" "text",
    "conta" "text",
    "pix_chave" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_conta_bancaria__tipo" CHECK (("tipo" = ANY (ARRAY['BANCO'::"text", 'CAIXA'::"text"])))
);


ALTER TABLE "f"."conta_bancaria" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."credito_fiscal_manual_lancamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "titulo_id" "uuid" NOT NULL,
    "regra_id" "uuid",
    "imposto" "text" NOT NULL,
    "natureza" "text" DEFAULT 'CREDITO'::"text" NOT NULL,
    "competencia_date" "date" NOT NULL,
    "base_calculo" numeric(15,2) DEFAULT 0 NOT NULL,
    "aliquota" numeric(7,4) DEFAULT 0 NOT NULL,
    "valor_credito" numeric(15,2) DEFAULT 0 NOT NULL,
    "modo" "text" NOT NULL,
    "status" "text" DEFAULT 'PROVISIONADO'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "credito_fiscal_manual_lancamento_imposto_ck" CHECK (("upper"("imposto") = ANY (ARRAY['ICMS'::"text", 'PIS'::"text", 'COFINS'::"text"]))),
    CONSTRAINT "credito_fiscal_manual_lancamento_modo_ck" CHECK (("modo" = ANY (ARRAY['NAO_CREDITA'::"text", 'CREDITA_IMEDIATO'::"text", 'CREDITA_PARCELADO'::"text", 'PENDENTE_REVISAO'::"text"]))),
    CONSTRAINT "credito_fiscal_manual_lancamento_natureza_ck" CHECK (("natureza" = 'CREDITO'::"text")),
    CONSTRAINT "credito_fiscal_manual_lancamento_status_ck" CHECK (("status" = ANY (ARRAY['PROVISIONADO'::"text", 'APROPRIADO'::"text", 'PENDENTE_REVISAO'::"text", 'CANCELADO'::"text"]))),
    CONSTRAINT "credito_fiscal_manual_lancamento_valor_ck" CHECK (("valor_credito" >= (0)::numeric))
);


ALTER TABLE "f"."credito_fiscal_manual_lancamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."credito_fiscal_manual_regra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid",
    "imposto" "text" NOT NULL,
    "modo" "text" NOT NULL,
    "aliquota" numeric(7,4) DEFAULT 0 NOT NULL,
    "parcelas_apropriacao" integer DEFAULT 1 NOT NULL,
    "competencia_offset_meses" integer DEFAULT 0 NOT NULL,
    "prioridade" integer DEFAULT 100 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "aplica_origem" "text",
    "descricao_like" "text",
    "motivo_compra_id" "uuid",
    "fornecedor_id" integer,
    "observacao" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "credito_fiscal_manual_regra_aliquota_ck" CHECK ((("aliquota" >= (0)::numeric) AND ("aliquota" <= (100)::numeric))),
    CONSTRAINT "credito_fiscal_manual_regra_imposto_ck" CHECK (("upper"("imposto") = ANY (ARRAY['ICMS'::"text", 'PIS'::"text", 'COFINS'::"text"]))),
    CONSTRAINT "credito_fiscal_manual_regra_modo_ck" CHECK (("modo" = ANY (ARRAY['NAO_CREDITA'::"text", 'CREDITA_IMEDIATO'::"text", 'CREDITA_PARCELADO'::"text", 'PENDENTE_REVISAO'::"text"]))),
    CONSTRAINT "credito_fiscal_manual_regra_parcelas_ck" CHECK ((("parcelas_apropriacao" >= 1) AND ("parcelas_apropriacao" <= 240))),
    CONSTRAINT "credito_fiscal_manual_regra_prioridade_ck" CHECK ((("prioridade" >= 1) AND ("prioridade" <= 9999)))
);


ALTER TABLE "f"."credito_fiscal_manual_regra" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."documento_fiscal" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "source_nf_entrada_id" bigint,
    "fornecedor_id" integer,
    "chave_acesso" "text" NOT NULL,
    "modelo" "text",
    "serie" "text",
    "numero" "text",
    "emissao_date" "date",
    "competencia_date" "date",
    "valor_total" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_produtos" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_frete" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_desconto" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_outros" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_seguro" numeric(15,2) DEFAULT 0 NOT NULL,
    "finalidade_import" "public"."item_finalidade",
    "os_id_import" integer,
    "pagamento_import_json" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    "operacao" "text" DEFAULT 'ENTRADA'::"text" NOT NULL,
    "natureza" "text" DEFAULT 'PRODUTO'::"text" NOT NULL,
    "cliente_id" integer,
    "valor_servicos" numeric(15,2) DEFAULT 0 NOT NULL,
    "nfse_municipio_codigo" "text",
    "nfse_codigo_verificacao" "text",
    "nfse_status" "text",
    "servico_discriminacao" "text",
    "material_percent" numeric(7,4),
    "material_valor" numeric(15,2),
    "nfe_status" "text",
    CONSTRAINT "ck_documento_fiscal__competencia_day1" CHECK ((("competencia_date" IS NULL) OR (EXTRACT(day FROM "competencia_date") = (1)::numeric))),
    CONSTRAINT "ck_documento_fiscal__material_percent" CHECK ((("material_percent" IS NULL) OR (("material_percent" >= (0)::numeric) AND ("material_percent" <= (100)::numeric)))),
    CONSTRAINT "ck_documento_fiscal__natureza" CHECK (("natureza" = ANY (ARRAY['PRODUTO'::"text", 'SERVICO'::"text"]))),
    CONSTRAINT "ck_documento_fiscal__nfe_status" CHECK ((("nfe_status" IS NULL) OR ("nfe_status" = ANY (ARRAY['RASCUNHO'::"text", 'EMITIDA'::"text", 'CANCELADA'::"text", 'SUBSTITUIDA'::"text"])))),
    CONSTRAINT "ck_documento_fiscal__nfse_status" CHECK ((("nfse_status" IS NULL) OR ("nfse_status" = ANY (ARRAY['RASCUNHO'::"text", 'EMITIDA'::"text", 'CANCELADA'::"text", 'SUBSTITUIDA'::"text"])))),
    CONSTRAINT "ck_documento_fiscal__operacao" CHECK (("operacao" = ANY (ARRAY['ENTRADA'::"text", 'SAIDA'::"text"])))
);


ALTER TABLE "f"."documento_fiscal" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."documento_fiscal_imposto" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "documento_fiscal_id" "uuid" NOT NULL,
    "imposto" "text" NOT NULL,
    "natureza" "text" DEFAULT 'DEBITO'::"text" NOT NULL,
    "base_original" numeric(15,2) DEFAULT 0 NOT NULL,
    "deducoes" numeric(15,2) DEFAULT 0 NOT NULL,
    "base_calculo" numeric(15,2) DEFAULT 0 NOT NULL,
    "aliquota" numeric(7,4) DEFAULT 0 NOT NULL,
    "valor_calculado" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_ajustado" numeric(15,2),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_documento_fiscal_imposto__natureza" CHECK (("natureza" = ANY (ARRAY['DEBITO'::"text", 'CREDITO'::"text", 'RETENCAO'::"text"])))
);


ALTER TABLE "f"."documento_fiscal_imposto" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."documento_fiscal_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "documento_fiscal_id" "uuid" NOT NULL,
    "item_n" integer NOT NULL,
    "item_tipo" "text" DEFAULT 'PRODUTO'::"text" NOT NULL,
    "codigo" "text",
    "descricao" "text" NOT NULL,
    "ncm" "text",
    "cfop" "text",
    "codigo_servico" "text",
    "quantidade" numeric(15,4) DEFAULT 0 NOT NULL,
    "unidade" "text",
    "valor_unitario" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_total" numeric(15,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_documento_fiscal_item__tipo" CHECK (("item_tipo" = ANY (ARRAY['PRODUTO'::"text", 'SERVICO'::"text"])))
);


ALTER TABLE "f"."documento_fiscal_item" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."documento_fiscal_pendencia" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "documento_fiscal_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "detalhe" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone
);


ALTER TABLE "f"."documento_fiscal_pendencia" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."documento_fiscal_xml" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "documento_fiscal_id" "uuid" NOT NULL,
    "chave_acesso" "text" NOT NULL,
    "xml_raw" "text" NOT NULL,
    "xml_hash" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "deleted_at" timestamp with time zone
);


ALTER TABLE "f"."documento_fiscal_xml" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."evento_financeiro" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "evento" "text" NOT NULL,
    "ref_table" "text",
    "ref_id" "uuid",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"()
);


ALTER TABLE "f"."evento_financeiro" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."extrato_bancario" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "conta_bancaria_id" "uuid" NOT NULL,
    "fonte" "text" DEFAULT 'MANUAL'::"text" NOT NULL,
    "referencia" "text",
    "periodo_inicio" "date",
    "periodo_fim" "date",
    "observacoes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_extrato_bancario__fonte" CHECK (("fonte" = ANY (ARRAY['MANUAL'::"text", 'OFX'::"text", 'CSV'::"text", 'API'::"text"])))
);


ALTER TABLE "f"."extrato_bancario" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."extrato_bancario_linha" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "extrato_bancario_id" "uuid" NOT NULL,
    "conta_bancaria_id" "uuid" NOT NULL,
    "data_movimento" "date" NOT NULL,
    "descricao" "text",
    "documento" "text",
    "fit_id" "text",
    "valor" numeric(15,2) NOT NULL,
    "status" "text" DEFAULT 'PENDENTE'::"text" NOT NULL,
    "observacoes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_extrato_linha__status" CHECK (("status" = ANY (ARRAY['PENDENTE'::"text", 'CONCILIADO'::"text", 'IGNORADO'::"text"])))
);


ALTER TABLE "f"."extrato_bancario_linha" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."fin_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "conta_bancaria_padrao_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "f"."fin_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."gestao_cobranca_os" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "os_id" integer NOT NULL,
    "status" "text" DEFAULT 'PENDENTE'::"text" NOT NULL,
    "pedido_compra_cliente" "text",
    "pedido_recebido_em" "date",
    "faturado_em" "date",
    "documento_fiscal_id" "uuid",
    "titulo_ar_id" "uuid",
    "responsavel_id" "uuid",
    "proximo_contato_date" "date",
    "observacao" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "gestao_cobranca_os_status_check" CHECK (("status" = ANY (ARRAY['PENDENTE'::"text", 'FATURADO'::"text", 'RECEBIDO'::"text", 'CANCELADO'::"text"])))
);


ALTER TABLE "f"."gestao_cobranca_os" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."importacao_doc_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "documento_fiscal_id" "uuid",
    "origem" "text" DEFAULT 'XML'::"text" NOT NULL,
    "status" "text" NOT NULL,
    "mensagem" "text",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    CONSTRAINT "ck_importacao_doc_log__status" CHECK (("status" = ANY (ARRAY['SUCESSO'::"text", 'ERRO'::"text"])))
);


ALTER TABLE "f"."importacao_doc_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."imposto_retencao" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "titulo_id" "uuid" NOT NULL,
    "documento_fiscal_id" "uuid",
    "imposto" "text" NOT NULL,
    "base_calculo" numeric(15,2) DEFAULT 0 NOT NULL,
    "aliquota" numeric(7,4) DEFAULT 0 NOT NULL,
    "valor_calculado" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_ajustado" numeric(15,2),
    "vencimento_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "f"."imposto_retencao" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."irpj_csll_ajuste" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "competencia_date" "date" NOT NULL,
    "escopo" "text" DEFAULT 'AMBOS'::"text" NOT NULL,
    "tipo" "text" NOT NULL,
    "descricao" "text" NOT NULL,
    "valor" numeric(15,2) DEFAULT 0 NOT NULL,
    "observacao" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_irpj_csll_ajuste__competencia_day1" CHECK ((EXTRACT(day FROM "competencia_date") = (1)::numeric)),
    CONSTRAINT "ck_irpj_csll_ajuste__escopo" CHECK (("escopo" = ANY (ARRAY['IRPJ'::"text", 'CSLL'::"text", 'AMBOS'::"text"]))),
    CONSTRAINT "ck_irpj_csll_ajuste__tipo" CHECK (("tipo" = ANY (ARRAY['ADICAO'::"text", 'EXCLUSAO'::"text"]))),
    CONSTRAINT "ck_irpj_csll_ajuste__valor" CHECK (("valor" >= (0)::numeric))
);


ALTER TABLE "f"."irpj_csll_ajuste" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."irpj_csll_financeiro_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "irpj_plano_contas_id" "uuid" NOT NULL,
    "csll_plano_contas_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    "irpj_vencimento_regra_id" "uuid",
    "csll_vencimento_regra_id" "uuid"
);


ALTER TABLE "f"."irpj_csll_financeiro_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."irpj_csll_regra_plano" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "plano_contas_id" "uuid" NOT NULL,
    "escopo" "text" DEFAULT 'AMBOS'::"text" NOT NULL,
    "tipo" "text" NOT NULL,
    "percentual" numeric(7,4) DEFAULT 100 NOT NULL,
    "descricao" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_irpj_csll_regra_plano__escopo" CHECK (("escopo" = ANY (ARRAY['IRPJ'::"text", 'CSLL'::"text", 'AMBOS'::"text"]))),
    CONSTRAINT "ck_irpj_csll_regra_plano__percentual" CHECK ((("percentual" >= (0)::numeric) AND ("percentual" <= (100)::numeric))),
    CONSTRAINT "ck_irpj_csll_regra_plano__tipo" CHECK (("tipo" = ANY (ARRAY['ADICAO'::"text", 'EXCLUSAO'::"text"])))
);


ALTER TABLE "f"."irpj_csll_regra_plano" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."irpj_csll_saldo_inicial" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "competencia_inicio" "date" NOT NULL,
    "saldo_prejuizo_irpj" numeric(15,2) DEFAULT 0 NOT NULL,
    "saldo_base_negativa_csll" numeric(15,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_irpj_csll_saldo_inicial__competencia_day1" CHECK ((EXTRACT(day FROM "competencia_inicio") = (1)::numeric)),
    CONSTRAINT "ck_irpj_csll_saldo_inicial__saldo_csll" CHECK (("saldo_base_negativa_csll" >= (0)::numeric)),
    CONSTRAINT "ck_irpj_csll_saldo_inicial__saldo_irpj" CHECK (("saldo_prejuizo_irpj" >= (0)::numeric))
);


ALTER TABLE "f"."irpj_csll_saldo_inicial" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."motivo_compra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "requires_text" boolean DEFAULT false NOT NULL,
    "requires_os" boolean DEFAULT false NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    "aplica_em" "text" DEFAULT 'PRODUTO'::"text" NOT NULL,
    "plano_contas_id" "uuid",
    "favorito" boolean DEFAULT false NOT NULL,
    "ordem" integer DEFAULT 0 NOT NULL,
    "visivel_import_nfe" boolean DEFAULT true NOT NULL,
    CONSTRAINT "ck_motivo_compra__aplica_em" CHECK (("aplica_em" = ANY (ARRAY['PRODUTO'::"text", 'SERVICO'::"text", 'AMBOS'::"text"])))
);


ALTER TABLE "f"."motivo_compra" OWNER TO "postgres";


COMMENT ON COLUMN "f"."motivo_compra"."favorito" IS 'Mostra no topo da lista de motivos';



COMMENT ON COLUMN "f"."motivo_compra"."ordem" IS 'Ordenação manual (maior = mais acima)';



COMMENT ON COLUMN "f"."motivo_compra"."visivel_import_nfe" IS 'Se true, aparece no seletor de motivo na importação de NF-e de entrada';



CREATE OR REPLACE VIEW "f"."nf_entrada" AS
 SELECT "id",
    "tenant_id",
    "empresa_id",
    ("chave")::"text" AS "chave_acesso",
    ("numero")::"text" AS "numero",
    ("serie")::"text" AS "serie",
    ("emitente_nome")::"text" AS "emitente_nome",
    ("emitente_cnpj")::"text" AS "emitente_cnpj",
    ("data_emissao")::"date" AS "emissao_date",
    ("date_trunc"('month'::"text", "data_emissao"))::"date" AS "competencia_date",
    COALESCE("valor_total", (0)::numeric) AS "valor_total",
    COALESCE("valor_produtos", (0)::numeric) AS "valor_produtos",
    COALESCE("valor_frete", (0)::numeric) AS "valor_frete",
    COALESCE("valor_seguro", (0)::numeric) AS "valor_seguro",
    COALESCE("valor_desconto", (0)::numeric) AS "valor_desconto",
    COALESCE("valor_outros", (0)::numeric) AS "valor_outros",
    "finalidade_contexto" AS "finalidade_import",
    "os_id" AS "os_id_import",
    "fornecedor_id",
    ("modelo")::"text" AS "modelo",
    NULL::"jsonb" AS "pagamento_import_json",
    "motivo_compra_id",
    "solicitante_usuario_id",
    "baixa_os_automatica"
   FROM "public"."nf_entrada" "n";


ALTER VIEW "f"."nf_entrada" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."pagamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "conta_bancaria_id" "uuid" NOT NULL,
    "data_pagamento" "date" NOT NULL,
    "forma_pagamento" "text" DEFAULT 'OUTROS'::"text" NOT NULL,
    "valor" numeric(15,2) NOT NULL,
    "observacoes" "text",
    "pago_por" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    "conciliado_at" timestamp with time zone,
    "conciliado_por" "uuid",
    "change_reason" "text",
    "valor_principal" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_juros" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_multa" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_desconto" numeric(15,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "ck_pagamento__forma" CHECK (("forma_pagamento" = ANY (ARRAY['PIX'::"text", 'BOLETO'::"text", 'TRANSFERENCIA'::"text", 'DINHEIRO'::"text", 'CARTAO'::"text", 'OUTROS'::"text"]))),
    CONSTRAINT "ck_pagamento__valor" CHECK (("valor" >= (0)::numeric)),
    CONSTRAINT "ck_pagamento__valor_desconto" CHECK (("valor_desconto" >= (0)::numeric)),
    CONSTRAINT "ck_pagamento__valor_juros" CHECK (("valor_juros" >= (0)::numeric)),
    CONSTRAINT "ck_pagamento__valor_multa" CHECK (("valor_multa" >= (0)::numeric)),
    CONSTRAINT "ck_pagamento__valor_principal" CHECK (("valor_principal" >= (0)::numeric)),
    CONSTRAINT "ck_pagamento__valor_total_comp" CHECK (("round"("valor", 2) = "round"(((("valor_principal" + "valor_juros") + "valor_multa") - "valor_desconto"), 2)))
);


ALTER TABLE "f"."pagamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."pagamento_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "pagamento_id" "uuid" NOT NULL,
    "titulo_parcela_id" "uuid" NOT NULL,
    "valor" numeric(15,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "deleted_at" timestamp with time zone,
    "empresa_id" "uuid" NOT NULL,
    "change_reason" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "ck_pagamento_item__valor" CHECK (("valor" >= (0)::numeric))
);


ALTER TABLE "f"."pagamento_item" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."parametro_financeiro_empresa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "conta_bancaria_padrao_id" "uuid",
    "saldo_inicial" numeric(15,2) DEFAULT 0 NOT NULL,
    "data_saldo_inicial" "date" DEFAULT CURRENT_DATE NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "f"."parametro_financeiro_empresa" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."parametro_irpj_csll_empresa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "regime_apuracao" "text" DEFAULT 'ANUAL_ESTIMATIVA'::"text" NOT NULL,
    "irpj_aliquota" numeric(7,4) DEFAULT 15.0000 NOT NULL,
    "irpj_adicional_aliquota" numeric(7,4) DEFAULT 10.0000 NOT NULL,
    "irpj_adicional_limite_mensal" numeric(15,2) DEFAULT 20000.00 NOT NULL,
    "csll_aliquota" numeric(7,4) DEFAULT 9.0000 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_param_csll__aliquota" CHECK ((("csll_aliquota" >= (0)::numeric) AND ("csll_aliquota" <= (100)::numeric))),
    CONSTRAINT "ck_param_irpj__adicional_aliquota" CHECK ((("irpj_adicional_aliquota" >= (0)::numeric) AND ("irpj_adicional_aliquota" <= (100)::numeric))),
    CONSTRAINT "ck_param_irpj__adicional_limite" CHECK (("irpj_adicional_limite_mensal" >= (0)::numeric)),
    CONSTRAINT "ck_param_irpj__aliquota" CHECK ((("irpj_aliquota" >= (0)::numeric) AND ("irpj_aliquota" <= (100)::numeric))),
    CONSTRAINT "ck_param_irpj_csll__regime" CHECK (("regime_apuracao" = ANY (ARRAY['ANUAL_ESTIMATIVA'::"text", 'TRIMESTRAL'::"text"])))
);


ALTER TABLE "f"."parametro_irpj_csll_empresa" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."plano_contas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "parent_id" "uuid",
    "natureza" "text" DEFAULT 'DEBITO'::"text" NOT NULL,
    "tipo" "text" DEFAULT 'ANALITICA'::"text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_plano_contas__natureza" CHECK (("natureza" = ANY (ARRAY['DEBITO'::"text", 'CREDITO'::"text"]))),
    CONSTRAINT "ck_plano_contas__tipo" CHECK (("tipo" = ANY (ARRAY['SINTETICA'::"text", 'ANALITICA'::"text"])))
);


ALTER TABLE "f"."plano_contas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."titulo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "status" "text" DEFAULT 'PENDENTE'::"text" NOT NULL,
    "origem" "text" DEFAULT 'XML'::"text" NOT NULL,
    "fornecedor_id" integer,
    "cliente_id" integer,
    "documento_fiscal_id" "uuid",
    "descricao" "text",
    "emissao_date" "date",
    "competencia_date" "date",
    "valor_total" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_aberto" numeric(15,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    "motivo_compra_id" "uuid",
    "classificacao_id" bigint,
    "arrendamento_contrato_id" "uuid",
    "recorrencia_id" "uuid",
    CONSTRAINT "ck_titulo__competencia_day1" CHECK ((("competencia_date" IS NULL) OR (EXTRACT(day FROM "competencia_date") = (1)::numeric))),
    CONSTRAINT "ck_titulo__status" CHECK (("status" = ANY (ARRAY['PENDENTE'::"text", 'APROVADO'::"text", 'AGENDADO'::"text", 'PAGO'::"text", 'CANCELADO'::"text"]))),
    CONSTRAINT "ck_titulo__tipo" CHECK (("tipo" = ANY (ARRAY['AP'::"text", 'AR'::"text"])))
);


ALTER TABLE "f"."titulo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."titulo_aprovacao" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "titulo_id" "uuid" NOT NULL,
    "motivo_compra_id" "uuid" NOT NULL,
    "motivo_outros_text" "text",
    "os_id" integer,
    "aprovado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "aprovado_por" "uuid" DEFAULT "a"."fn_current_usuario_id"() NOT NULL,
    "change_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "f"."titulo_aprovacao" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."titulo_parcela" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "titulo_id" "uuid" NOT NULL,
    "numero" "text",
    "vencimento_date" "date" NOT NULL,
    "valor" numeric(15,2) NOT NULL,
    "valor_aberto" numeric(15,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_titulo_parcela__valor" CHECK (("valor" >= (0)::numeric)),
    CONSTRAINT "ck_titulo_parcela__valor_aberto" CHECK (("valor_aberto" >= (0)::numeric))
);


ALTER TABLE "f"."titulo_parcela" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_ap_aging_detalhe" AS
 SELECT "t"."tenant_id",
    "t"."empresa_id",
    "t"."id" AS "titulo_id",
    "tp"."id" AS "parcela_id",
    "tp"."numero" AS "parcela_numero",
    "t"."fornecedor_id",
    COALESCE("forn"."nome", 'SEM FORNECEDOR'::character varying) AS "fornecedor_nome",
    COALESCE("mc"."codigo", 'NAO_CLASSIFICADO'::"text") AS "motivo_codigo",
    COALESCE("mc"."nome", 'NAO CLASSIFICADO'::"text") AS "motivo_nome",
    "tp"."vencimento_date",
    (CURRENT_DATE - "tp"."vencimento_date") AS "dias_atraso",
    "tp"."valor" AS "valor_parcela",
    "tp"."valor_aberto",
    "t"."status",
    "t"."emissao_date",
    "t"."competencia_date"
   FROM (((("f"."titulo_parcela" "tp"
     JOIN "f"."titulo" "t" ON (("t"."id" = "tp"."titulo_id")))
     LEFT JOIN "f"."titulo_aprovacao" "ta" ON ((("ta"."tenant_id" = "t"."tenant_id") AND ("ta"."titulo_id" = "t"."id") AND ("ta"."deleted_at" IS NULL))))
     LEFT JOIN "f"."motivo_compra" "mc" ON ((("mc"."id" = COALESCE("ta"."motivo_compra_id", "t"."motivo_compra_id")) AND ("mc"."deleted_at" IS NULL))))
     LEFT JOIN "public"."fornecedores" "forn" ON (("forn"."id" = "t"."fornecedor_id")))
  WHERE (("tp"."deleted_at" IS NULL) AND ("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text") AND ("tp"."valor_aberto" > (0)::numeric));


ALTER VIEW "f"."r_ap_aging_detalhe" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_ap_aging_resumo" AS
 WITH "base" AS (
         SELECT "t"."tenant_id",
            "t"."empresa_id",
            "t"."fornecedor_id",
            COALESCE("forn"."nome", 'SEM FORNECEDOR'::character varying) AS "fornecedor_nome",
            COALESCE("mc"."codigo", 'NAO_CLASSIFICADO'::"text") AS "motivo_codigo",
            COALESCE("mc"."nome", 'NAO CLASSIFICADO'::"text") AS "motivo_nome",
            "tp"."vencimento_date",
            "tp"."valor_aberto",
            (CURRENT_DATE - "tp"."vencimento_date") AS "dias_atraso"
           FROM (((("f"."titulo_parcela" "tp"
             JOIN "f"."titulo" "t" ON (("t"."id" = "tp"."titulo_id")))
             LEFT JOIN "f"."titulo_aprovacao" "ta" ON ((("ta"."tenant_id" = "t"."tenant_id") AND ("ta"."titulo_id" = "t"."id") AND ("ta"."deleted_at" IS NULL))))
             LEFT JOIN "f"."motivo_compra" "mc" ON ((("mc"."id" = COALESCE("ta"."motivo_compra_id", "t"."motivo_compra_id")) AND ("mc"."deleted_at" IS NULL))))
             LEFT JOIN "public"."fornecedores" "forn" ON (("forn"."id" = "t"."fornecedor_id")))
          WHERE (("tp"."deleted_at" IS NULL) AND ("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text") AND ("tp"."valor_aberto" > (0)::numeric))
        )
 SELECT "tenant_id",
    "empresa_id",
    "fornecedor_id",
    "fornecedor_nome",
    "motivo_codigo",
    "motivo_nome",
    ("sum"(
        CASE
            WHEN ("vencimento_date" > CURRENT_DATE) THEN "valor_aberto"
            ELSE (0)::numeric
        END))::numeric(15,2) AS "a_vencer",
    ("sum"(
        CASE
            WHEN (("dias_atraso" >= 0) AND ("dias_atraso" <= 30)) THEN "valor_aberto"
            ELSE (0)::numeric
        END))::numeric(15,2) AS "vencido_0_30",
    ("sum"(
        CASE
            WHEN (("dias_atraso" >= 31) AND ("dias_atraso" <= 60)) THEN "valor_aberto"
            ELSE (0)::numeric
        END))::numeric(15,2) AS "vencido_31_60",
    ("sum"(
        CASE
            WHEN (("dias_atraso" >= 61) AND ("dias_atraso" <= 90)) THEN "valor_aberto"
            ELSE (0)::numeric
        END))::numeric(15,2) AS "vencido_61_90",
    ("sum"(
        CASE
            WHEN ("dias_atraso" >= 91) THEN "valor_aberto"
            ELSE (0)::numeric
        END))::numeric(15,2) AS "vencido_90_mais",
    ("sum"("valor_aberto"))::numeric(15,2) AS "total_aberto"
   FROM "base"
  GROUP BY "tenant_id", "empresa_id", "fornecedor_id", "fornecedor_nome", "motivo_codigo", "motivo_nome";


ALTER VIEW "f"."r_ap_aging_resumo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."titulo_agendamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "titulo_id" "uuid" NOT NULL,
    "conta_bancaria_id" "uuid" NOT NULL,
    "data_prevista" "date" NOT NULL,
    "forma_pagamento" "text" DEFAULT 'OUTROS'::"text" NOT NULL,
    "valor_previsto" numeric(15,2) NOT NULL,
    "observacoes" "text",
    "change_reason" "text",
    "agendado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "agendado_por" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_titulo_agendamento__forma" CHECK (("forma_pagamento" = ANY (ARRAY['PIX'::"text", 'BOLETO'::"text", 'TRANSFERENCIA'::"text", 'DINHEIRO'::"text", 'CARTAO'::"text", 'OUTROS'::"text"]))),
    CONSTRAINT "ck_titulo_agendamento__valor" CHECK (("valor_previsto" > (0)::numeric))
);


ALTER TABLE "f"."titulo_agendamento" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_previsto_diario" AS
 WITH "ag" AS (
         SELECT "t"."tenant_id",
            "t"."empresa_id",
            "ta"."conta_bancaria_id",
            "ta"."data_prevista" AS "data_ref",
            'AGENDADO'::"text" AS "origem",
            "ta"."valor_previsto"
           FROM ("f"."titulo_agendamento" "ta"
             JOIN "f"."titulo" "t" ON (("t"."id" = "ta"."titulo_id")))
          WHERE (("ta"."deleted_at" IS NULL) AND ("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text"))
        ), "venc" AS (
         SELECT "t"."tenant_id",
            "t"."empresa_id",
            COALESCE("ta"."conta_bancaria_id", NULL::"uuid") AS "conta_bancaria_id",
            "tp"."vencimento_date" AS "data_ref",
            'VENCIMENTO'::"text" AS "origem",
            "tp"."valor_aberto" AS "valor_previsto"
           FROM (("f"."titulo_parcela" "tp"
             JOIN "f"."titulo" "t" ON (("t"."id" = "tp"."titulo_id")))
             LEFT JOIN "f"."titulo_agendamento" "ta" ON ((("ta"."tenant_id" = "t"."tenant_id") AND ("ta"."titulo_id" = "t"."id") AND ("ta"."deleted_at" IS NULL))))
          WHERE (("tp"."deleted_at" IS NULL) AND ("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text") AND ("t"."status" = ANY (ARRAY['APROVADO'::"text", 'AGENDADO'::"text", 'PENDENTE'::"text"])) AND ("tp"."valor_aberto" > (0)::numeric) AND ("ta"."id" IS NULL))
        )
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "origem",
    ("sum"("valor_previsto"))::numeric(15,2) AS "valor_previsto"
   FROM ( SELECT "ag"."tenant_id",
            "ag"."empresa_id",
            "ag"."conta_bancaria_id",
            "ag"."data_ref",
            "ag"."origem",
            "ag"."valor_previsto"
           FROM "ag"
        UNION ALL
         SELECT "venc"."tenant_id",
            "venc"."empresa_id",
            "venc"."conta_bancaria_id",
            "venc"."data_ref",
            "venc"."origem",
            "venc"."valor_previsto"
           FROM "venc") "x"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", "data_ref", "origem";


ALTER VIEW "f"."r_fluxo_caixa_previsto_diario" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_realizado_diario" AS
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_pagamento" AS "data_ref",
        CASE
            WHEN ("conciliado_at" IS NOT NULL) THEN 'CONCILIADO'::"text"
            ELSE 'NAO_CONCILIADO'::"text"
        END AS "status_conciliacao",
    ("sum"("valor"))::numeric(15,2) AS "valor_realizado"
   FROM "f"."pagamento" "p"
  WHERE ("deleted_at" IS NULL)
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", "data_pagamento",
        CASE
            WHEN ("conciliado_at" IS NOT NULL) THEN 'CONCILIADO'::"text"
            ELSE 'NAO_CONCILIADO'::"text"
        END;


ALTER VIEW "f"."r_fluxo_caixa_realizado_diario" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_diario" AS
 SELECT COALESCE("pr"."tenant_id", "rr"."tenant_id") AS "tenant_id",
    COALESCE("pr"."empresa_id", "rr"."empresa_id") AS "empresa_id",
    COALESCE("pr"."conta_bancaria_id", "rr"."conta_bancaria_id") AS "conta_bancaria_id",
    COALESCE("pr"."data_ref", "rr"."data_ref") AS "data_ref",
    (COALESCE("pr"."valor_previsto", (0)::numeric))::numeric(15,2) AS "valor_previsto",
    (COALESCE("rr"."valor_realizado", (0)::numeric))::numeric(15,2) AS "valor_realizado"
   FROM (( SELECT "r_fluxo_caixa_previsto_diario"."tenant_id",
            "r_fluxo_caixa_previsto_diario"."empresa_id",
            "r_fluxo_caixa_previsto_diario"."conta_bancaria_id",
            "r_fluxo_caixa_previsto_diario"."data_ref",
            ("sum"("r_fluxo_caixa_previsto_diario"."valor_previsto"))::numeric(15,2) AS "valor_previsto"
           FROM "f"."r_fluxo_caixa_previsto_diario"
          GROUP BY "r_fluxo_caixa_previsto_diario"."tenant_id", "r_fluxo_caixa_previsto_diario"."empresa_id", "r_fluxo_caixa_previsto_diario"."conta_bancaria_id", "r_fluxo_caixa_previsto_diario"."data_ref") "pr"
     FULL JOIN ( SELECT "r_fluxo_caixa_realizado_diario"."tenant_id",
            "r_fluxo_caixa_realizado_diario"."empresa_id",
            "r_fluxo_caixa_realizado_diario"."conta_bancaria_id",
            "r_fluxo_caixa_realizado_diario"."data_ref",
            ("sum"("r_fluxo_caixa_realizado_diario"."valor_realizado"))::numeric(15,2) AS "valor_realizado"
           FROM "f"."r_fluxo_caixa_realizado_diario"
          GROUP BY "r_fluxo_caixa_realizado_diario"."tenant_id", "r_fluxo_caixa_realizado_diario"."empresa_id", "r_fluxo_caixa_realizado_diario"."conta_bancaria_id", "r_fluxo_caixa_realizado_diario"."data_ref") "rr" ON ((("rr"."tenant_id" = "pr"."tenant_id") AND ("rr"."empresa_id" = "pr"."empresa_id") AND (NOT ("rr"."conta_bancaria_id" IS DISTINCT FROM "pr"."conta_bancaria_id")) AND ("rr"."data_ref" = "pr"."data_ref"))));


ALTER VIEW "f"."r_fluxo_caixa_diario" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_diario_conta_resolvida" AS
 SELECT "d"."tenant_id",
    "d"."empresa_id",
    COALESCE("d"."conta_bancaria_id", "p"."conta_bancaria_padrao_id") AS "conta_bancaria_id",
    "d"."data_ref",
    "d"."valor_previsto",
    "d"."valor_realizado"
   FROM ("f"."r_fluxo_caixa_diario" "d"
     LEFT JOIN "f"."parametro_financeiro_empresa" "p" ON ((("p"."tenant_id" = "d"."tenant_id") AND ("p"."empresa_id" = "d"."empresa_id") AND ("p"."deleted_at" IS NULL))));


ALTER VIEW "f"."r_fluxo_caixa_diario_conta_resolvida" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_previsto_diario_dim" AS
 WITH "aprov" AS (
         SELECT "a"."tenant_id",
            "a"."titulo_id",
            "a"."motivo_compra_id",
            "a"."os_id"
           FROM "f"."titulo_aprovacao" "a"
          WHERE ("a"."deleted_at" IS NULL)
        ), "ag" AS (
         SELECT "t"."tenant_id",
            "t"."empresa_id",
            "ta"."conta_bancaria_id",
            "ta"."data_prevista" AS "data_ref",
            'AGENDADO'::"text" AS "origem",
            "t"."fornecedor_id",
            "ap"."motivo_compra_id",
            "ap"."os_id",
            "ta"."valor_previsto"
           FROM (("f"."titulo_agendamento" "ta"
             JOIN "f"."titulo" "t" ON (("t"."id" = "ta"."titulo_id")))
             LEFT JOIN "aprov" "ap" ON ((("ap"."tenant_id" = "t"."tenant_id") AND ("ap"."titulo_id" = "t"."id"))))
          WHERE (("ta"."deleted_at" IS NULL) AND ("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text"))
        ), "venc" AS (
         SELECT "t"."tenant_id",
            "t"."empresa_id",
            NULL::"uuid" AS "conta_bancaria_id",
            "tp"."vencimento_date" AS "data_ref",
            'VENCIMENTO'::"text" AS "origem",
            "t"."fornecedor_id",
            "ap"."motivo_compra_id",
            "ap"."os_id",
            "tp"."valor_aberto" AS "valor_previsto"
           FROM ((("f"."titulo_parcela" "tp"
             JOIN "f"."titulo" "t" ON (("t"."id" = "tp"."titulo_id")))
             LEFT JOIN "f"."titulo_agendamento" "ta" ON ((("ta"."tenant_id" = "t"."tenant_id") AND ("ta"."titulo_id" = "t"."id") AND ("ta"."deleted_at" IS NULL))))
             LEFT JOIN "aprov" "ap" ON ((("ap"."tenant_id" = "t"."tenant_id") AND ("ap"."titulo_id" = "t"."id"))))
          WHERE (("tp"."deleted_at" IS NULL) AND ("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text") AND ("t"."status" = ANY (ARRAY['PENDENTE'::"text", 'APROVADO'::"text", 'AGENDADO'::"text"])) AND ("tp"."valor_aberto" > (0)::numeric) AND ("ta"."id" IS NULL))
        )
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "origem",
    "fornecedor_id",
    "motivo_compra_id",
    "os_id",
    ("sum"("valor_previsto"))::numeric(15,2) AS "valor_previsto"
   FROM ( SELECT "ag"."tenant_id",
            "ag"."empresa_id",
            "ag"."conta_bancaria_id",
            "ag"."data_ref",
            "ag"."origem",
            "ag"."fornecedor_id",
            "ag"."motivo_compra_id",
            "ag"."os_id",
            "ag"."valor_previsto"
           FROM "ag"
        UNION ALL
         SELECT "venc"."tenant_id",
            "venc"."empresa_id",
            "venc"."conta_bancaria_id",
            "venc"."data_ref",
            "venc"."origem",
            "venc"."fornecedor_id",
            "venc"."motivo_compra_id",
            "venc"."os_id",
            "venc"."valor_previsto"
           FROM "venc") "x"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", "data_ref", "origem", "fornecedor_id", "motivo_compra_id", "os_id";


ALTER VIEW "f"."r_fluxo_previsto_diario_dim" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_realizado_diario_dim" AS
 WITH "aprov" AS (
         SELECT "a"."tenant_id",
            "a"."titulo_id",
            "a"."motivo_compra_id",
            "a"."os_id"
           FROM "f"."titulo_aprovacao" "a"
          WHERE ("a"."deleted_at" IS NULL)
        ), "base" AS (
         SELECT "pa"."tenant_id",
            "pa"."empresa_id",
            "pa"."conta_bancaria_id",
            "pa"."data_pagamento" AS "data_ref",
            "pa"."pagamento_id",
            "pa"."forma_pagamento",
            "pa"."valor_pagamento",
            "t"."fornecedor_id",
            "ap"."motivo_compra_id",
            "ap"."os_id",
            "pa"."valor_aplicado"
           FROM (("f"."fn_pagamentos_aplicados"() "pa"("tenant_id", "empresa_id", "conta_bancaria_id", "pagamento_id", "data_pagamento", "forma_pagamento", "valor_pagamento", "titulo_id", "titulo_parcela_id", "valor_aplicado")
             JOIN "f"."titulo" "t" ON (("t"."id" = "pa"."titulo_id")))
             LEFT JOIN "aprov" "ap" ON ((("ap"."tenant_id" = "t"."tenant_id") AND ("ap"."titulo_id" = "t"."id"))))
          WHERE (("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text"))
        )
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "fornecedor_id",
    "motivo_compra_id",
    "os_id",
    ("sum"("valor_aplicado"))::numeric(15,2) AS "valor_realizado"
   FROM "base"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", "data_ref", "fornecedor_id", "motivo_compra_id", "os_id";


ALTER VIEW "f"."r_fluxo_realizado_diario_dim" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_diario_dim" AS
 SELECT COALESCE("p"."tenant_id", "r"."tenant_id") AS "tenant_id",
    COALESCE("p"."empresa_id", "r"."empresa_id") AS "empresa_id",
    COALESCE("p"."conta_bancaria_id", "r"."conta_bancaria_id") AS "conta_bancaria_id",
    COALESCE("p"."data_ref", "r"."data_ref") AS "data_ref",
    COALESCE("p"."fornecedor_id", "r"."fornecedor_id") AS "fornecedor_id",
    COALESCE("p"."motivo_compra_id", "r"."motivo_compra_id") AS "motivo_compra_id",
    COALESCE("p"."os_id", "r"."os_id") AS "os_id",
    (COALESCE("p"."valor_previsto", (0)::numeric))::numeric(15,2) AS "valor_previsto",
    (COALESCE("r"."valor_realizado", (0)::numeric))::numeric(15,2) AS "valor_realizado"
   FROM ("f"."r_fluxo_previsto_diario_dim" "p"
     FULL JOIN "f"."r_fluxo_realizado_diario_dim" "r" ON ((("r"."tenant_id" = "p"."tenant_id") AND ("r"."empresa_id" = "p"."empresa_id") AND (NOT ("r"."conta_bancaria_id" IS DISTINCT FROM "p"."conta_bancaria_id")) AND ("r"."data_ref" = "p"."data_ref") AND (NOT ("r"."fornecedor_id" IS DISTINCT FROM "p"."fornecedor_id")) AND (NOT ("r"."motivo_compra_id" IS DISTINCT FROM "p"."motivo_compra_id")) AND (NOT ("r"."os_id" IS DISTINCT FROM "p"."os_id")))));


ALTER VIEW "f"."r_fluxo_caixa_diario_dim" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_diario_por_fornecedor" AS
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "fornecedor_id",
    ("sum"("valor_previsto"))::numeric(15,2) AS "valor_previsto",
    ("sum"("valor_realizado"))::numeric(15,2) AS "valor_realizado"
   FROM "f"."r_fluxo_caixa_diario_dim"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", "data_ref", "fornecedor_id";


ALTER VIEW "f"."r_fluxo_caixa_diario_por_fornecedor" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_diario_por_motivo" AS
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "motivo_compra_id",
    ("sum"("valor_previsto"))::numeric(15,2) AS "valor_previsto",
    ("sum"("valor_realizado"))::numeric(15,2) AS "valor_realizado"
   FROM "f"."r_fluxo_caixa_diario_dim"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", "data_ref", "motivo_compra_id";


ALTER VIEW "f"."r_fluxo_caixa_diario_por_motivo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_diario_por_motivo_rotulado" AS
 SELECT "x"."tenant_id",
    "x"."empresa_id",
    "x"."conta_bancaria_id",
    "x"."data_ref",
    "x"."motivo_compra_id",
    COALESCE("mc"."codigo", 'NAO_CLASSIFICADO'::"text") AS "motivo_codigo",
    COALESCE("mc"."nome", 'NAO CLASSIFICADO'::"text") AS "motivo_nome",
    "x"."valor_previsto",
    "x"."valor_realizado"
   FROM ("f"."r_fluxo_caixa_diario_por_motivo" "x"
     LEFT JOIN "f"."motivo_compra" "mc" ON ((("mc"."id" = "x"."motivo_compra_id") AND ("mc"."deleted_at" IS NULL))));


ALTER VIEW "f"."r_fluxo_caixa_diario_por_motivo_rotulado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_diario_por_os" AS
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "os_id",
    ("sum"("valor_previsto"))::numeric(15,2) AS "valor_previsto",
    ("sum"("valor_realizado"))::numeric(15,2) AS "valor_realizado"
   FROM "f"."r_fluxo_caixa_diario_dim"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", "data_ref", "os_id";


ALTER VIEW "f"."r_fluxo_caixa_diario_por_os" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_caixa_mensal" AS
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    ("date_trunc"('month'::"text", ("data_ref")::timestamp with time zone))::"date" AS "mes_ref",
    ("sum"("valor_previsto"))::numeric(15,2) AS "valor_previsto",
    ("sum"("valor_realizado"))::numeric(15,2) AS "valor_realizado"
   FROM "f"."r_fluxo_caixa_diario"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id", (("date_trunc"('month'::"text", ("data_ref")::timestamp with time zone))::"date");


ALTER VIEW "f"."r_fluxo_caixa_mensal" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_fluxo_previsto_diario_ajustado_hoje" AS
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
        CASE
            WHEN ("data_ref" < CURRENT_DATE) THEN CURRENT_DATE
            ELSE "data_ref"
        END AS "data_ref",
    ("sum"("valor_previsto"))::numeric(15,2) AS "valor_previsto"
   FROM "f"."r_fluxo_previsto_diario_dim"
  GROUP BY "tenant_id", "empresa_id", "conta_bancaria_id",
        CASE
            WHEN ("data_ref" < CURRENT_DATE) THEN CURRENT_DATE
            ELSE "data_ref"
        END;


ALTER VIEW "f"."r_fluxo_previsto_diario_ajustado_hoje" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_saldo_projetado_diario" AS
 WITH "base" AS (
         SELECT "r_fluxo_caixa_diario"."tenant_id",
            "r_fluxo_caixa_diario"."empresa_id",
            "r_fluxo_caixa_diario"."conta_bancaria_id",
            "r_fluxo_caixa_diario"."data_ref",
            ("sum"("r_fluxo_caixa_diario"."valor_previsto"))::numeric(15,2) AS "valor_previsto",
            ("sum"("r_fluxo_caixa_diario"."valor_realizado"))::numeric(15,2) AS "valor_realizado"
           FROM "f"."r_fluxo_caixa_diario"
          GROUP BY "r_fluxo_caixa_diario"."tenant_id", "r_fluxo_caixa_diario"."empresa_id", "r_fluxo_caixa_diario"."conta_bancaria_id", "r_fluxo_caixa_diario"."data_ref"
        )
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "valor_previsto",
    "valor_realizado",
    ("sum"("valor_previsto") OVER (PARTITION BY "tenant_id", "empresa_id", "conta_bancaria_id" ORDER BY "data_ref" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS "acumulado_previsto",
    ("sum"("valor_realizado") OVER (PARTITION BY "tenant_id", "empresa_id", "conta_bancaria_id" ORDER BY "data_ref" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS "acumulado_realizado",
    ("sum"(("valor_realizado" - "valor_previsto")) OVER (PARTITION BY "tenant_id", "empresa_id", "conta_bancaria_id" ORDER BY "data_ref" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS "acumulado_delta"
   FROM "base";


ALTER VIEW "f"."r_saldo_projetado_diario" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_saldo_projetado_diario_com_saldo_inicial" AS
 WITH "base" AS (
         SELECT "d"."tenant_id",
            "d"."empresa_id",
            "d"."conta_bancaria_id",
            "d"."data_ref",
            "d"."valor_previsto",
            "d"."valor_realizado",
            (COALESCE("p"."saldo_inicial", (0)::numeric))::numeric(15,2) AS "saldo_inicial",
            COALESCE("p"."data_saldo_inicial", "d"."data_ref") AS "data_saldo_inicial"
           FROM ("f"."r_fluxo_caixa_diario_conta_resolvida" "d"
             LEFT JOIN "f"."parametro_financeiro_empresa" "p" ON ((("p"."tenant_id" = "d"."tenant_id") AND ("p"."empresa_id" = "d"."empresa_id") AND ("p"."deleted_at" IS NULL))))
        )
 SELECT "tenant_id",
    "empresa_id",
    "conta_bancaria_id",
    "data_ref",
    "valor_previsto",
    "valor_realizado",
    ("sum"(
        CASE
            WHEN ("data_ref" >= "data_saldo_inicial") THEN "valor_previsto"
            ELSE (0)::numeric
        END) OVER (PARTITION BY "tenant_id", "empresa_id", "conta_bancaria_id" ORDER BY "data_ref"))::numeric(15,2) AS "acumulado_previsto",
    ("sum"(
        CASE
            WHEN ("data_ref" >= "data_saldo_inicial") THEN "valor_realizado"
            ELSE (0)::numeric
        END) OVER (PARTITION BY "tenant_id", "empresa_id", "conta_bancaria_id" ORDER BY "data_ref"))::numeric(15,2) AS "acumulado_realizado",
    (("max"("saldo_inicial") OVER (PARTITION BY "tenant_id", "empresa_id", "conta_bancaria_id") + "sum"(
        CASE
            WHEN ("data_ref" >= "data_saldo_inicial") THEN ("valor_realizado" - "valor_previsto")
            ELSE (0)::numeric
        END) OVER (PARTITION BY "tenant_id", "empresa_id", "conta_bancaria_id" ORDER BY "data_ref")))::numeric(15,2) AS "saldo_projetado"
   FROM "base"
  WHERE ("data_ref" >= "data_saldo_inicial");


ALTER VIEW "f"."r_saldo_projetado_diario_com_saldo_inicial" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_sugestoes_conciliacao_ap" AS
 WITH "extrato" AS (
         SELECT "el"."id" AS "extrato_linha_id",
            "el"."tenant_id",
            "el"."conta_bancaria_id",
            "el"."data_movimento",
            "el"."descricao",
            "el"."documento",
            "el"."valor" AS "valor_extrato",
            ("abs"("el"."valor"))::numeric(15,2) AS "valor_extrato_abs"
           FROM "f"."extrato_bancario_linha" "el"
          WHERE (("el"."deleted_at" IS NULL) AND ("el"."status" = 'PENDENTE'::"text") AND ("el"."valor" < (0)::numeric))
        ), "pag" AS (
         SELECT "p_1"."id" AS "pagamento_id",
            "p_1"."tenant_id",
            "p_1"."empresa_id",
            "p_1"."conta_bancaria_id",
            "p_1"."data_pagamento",
            "p_1"."forma_pagamento",
            "p_1"."valor" AS "valor_pagamento"
           FROM "f"."pagamento" "p_1"
          WHERE (("p_1"."deleted_at" IS NULL) AND ("p_1"."conciliado_at" IS NULL))
        )
 SELECT "e"."tenant_id",
    "p"."empresa_id",
    "e"."conta_bancaria_id",
    "e"."extrato_linha_id",
    "e"."data_movimento",
    "e"."valor_extrato",
    "e"."descricao",
    "e"."documento",
    "p"."pagamento_id",
    "p"."data_pagamento",
    "p"."forma_pagamento",
    "p"."valor_pagamento",
    (("e"."valor_extrato_abs" - "p"."valor_pagamento"))::numeric(15,2) AS "diferenca_valor",
        CASE
            WHEN ("e"."data_movimento" = "p"."data_pagamento") THEN 3
            WHEN (("e"."data_movimento" = ("p"."data_pagamento" - 1)) OR ("e"."data_movimento" = ("p"."data_pagamento" + 1))) THEN 2
            WHEN (("e"."data_movimento" = ("p"."data_pagamento" - 2)) OR ("e"."data_movimento" = ("p"."data_pagamento" + 2))) THEN 1
            ELSE 0
        END AS "score_data"
   FROM ("extrato" "e"
     JOIN "pag" "p" ON ((("p"."tenant_id" = "e"."tenant_id") AND ("p"."conta_bancaria_id" = "e"."conta_bancaria_id") AND ("p"."valor_pagamento" = "e"."valor_extrato_abs") AND (("e"."data_movimento" >= ("p"."data_pagamento" - 2)) AND ("e"."data_movimento" <= ("p"."data_pagamento" + 2))))));


ALTER VIEW "f"."r_sugestoes_conciliacao_ap" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."r_titulos_sem_motivo_por_fornecedor" AS
 SELECT "t"."tenant_id",
    "t"."empresa_id",
    "t"."fornecedor_id",
    COALESCE("f"."nome", 'SEM FORNECEDOR'::character varying) AS "fornecedor_nome",
    "count"(*) AS "qtd_titulos_sem_motivo",
    ("sum"("tp"."valor_aberto"))::numeric(15,2) AS "total_aberto"
   FROM ((("f"."titulo_parcela" "tp"
     JOIN "f"."titulo" "t" ON (("t"."id" = "tp"."titulo_id")))
     LEFT JOIN "f"."titulo_aprovacao" "ta" ON ((("ta"."tenant_id" = "t"."tenant_id") AND ("ta"."titulo_id" = "t"."id") AND ("ta"."deleted_at" IS NULL))))
     LEFT JOIN "public"."fornecedores" "f" ON (("f"."id" = "t"."fornecedor_id")))
  WHERE (("tp"."deleted_at" IS NULL) AND ("t"."deleted_at" IS NULL) AND ("t"."tipo" = 'AP'::"text") AND ("tp"."valor_aberto" > (0)::numeric) AND ("ta"."id" IS NULL))
  GROUP BY "t"."tenant_id", "t"."empresa_id", "t"."fornecedor_id", COALESCE("f"."nome", 'SEM FORNECEDOR'::character varying)
  ORDER BY (("sum"("tp"."valor_aberto"))::numeric(15,2)) DESC;


ALTER VIEW "f"."r_titulos_sem_motivo_por_fornecedor" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."titulo_rateio" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "titulo_id" "uuid" NOT NULL,
    "plano_contas_id" "uuid",
    "centro_custo_id" "uuid",
    "os_id" integer,
    "percentual" numeric(7,4),
    "valor" numeric(15,2),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_titulo_rateio__percentual" CHECK ((("percentual" IS NULL) OR (("percentual" >= (0)::numeric) AND ("percentual" <= (100)::numeric)))),
    CONSTRAINT "ck_titulo_rateio__valor" CHECK ((("valor" IS NULL) OR ("valor" >= (0)::numeric)))
);


ALTER TABLE "f"."titulo_rateio" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "f"."tmp_backfill_impostos_entrada_erros" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid",
    "empresa_id" "uuid",
    "documento_fiscal_id" "uuid",
    "source_nf_entrada_id" bigint,
    "chave_acesso" "text",
    "erro" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "f"."tmp_backfill_impostos_entrada_erros" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "f"."tmp_backfill_impostos_entrada_erros_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "f"."tmp_backfill_impostos_entrada_erros_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "f"."tmp_backfill_impostos_entrada_erros_id_seq" OWNED BY "f"."tmp_backfill_impostos_entrada_erros"."id";



CREATE TABLE IF NOT EXISTS "f"."vencimento_regra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "tipo" "text" NOT NULL,
    "dia" integer,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_vencimento_regra_dia" CHECK (((("tipo" = 'M1_ULTIMO_DIA'::"text") AND ("dia" IS NULL)) OR (("tipo" = 'M1_DIA_FIXO'::"text") AND (("dia" >= 1) AND ("dia" <= 31))))),
    CONSTRAINT "ck_vencimento_regra_tipo" CHECK (("tipo" = ANY (ARRAY['M1_ULTIMO_DIA'::"text", 'M1_DIA_FIXO'::"text"])))
);


ALTER TABLE "f"."vencimento_regra" OWNER TO "postgres";


CREATE OR REPLACE VIEW "f"."vw_imposto_apuracao_mensal" AS
 SELECT "df"."tenant_id",
    "df"."empresa_id",
    "df"."competencia_date",
    "df"."operacao",
    "dfi"."imposto",
    "dfi"."natureza",
    "sum"(COALESCE("dfi"."base_calculo", (0)::numeric)) AS "base_total",
    "sum"(COALESCE("dfi"."valor_ajustado", "dfi"."valor_calculado", (0)::numeric)) AS "valor_total_calculado",
    "sum"(COALESCE("dfi"."valor_ajustado", (0)::numeric)) AS "valor_total_ajustado",
    "count"(DISTINCT "dfi"."documento_fiscal_id") AS "qtd_documentos"
   FROM ("f"."documento_fiscal_imposto" "dfi"
     JOIN "f"."documento_fiscal" "df" ON ((("df"."id" = "dfi"."documento_fiscal_id") AND ("df"."tenant_id" = "dfi"."tenant_id"))))
  WHERE (("df"."deleted_at" IS NULL) AND ("dfi"."deleted_at" IS NULL) AND ("df"."competencia_date" IS NOT NULL))
  GROUP BY "df"."tenant_id", "df"."empresa_id", "df"."competencia_date", "df"."operacao", "dfi"."imposto", "dfi"."natureza";


ALTER VIEW "f"."vw_imposto_apuracao_mensal" OWNER TO "postgres";


ALTER TABLE ONLY "f"."tmp_backfill_impostos_entrada_erros" ALTER COLUMN "id" SET DEFAULT "nextval"('"f"."tmp_backfill_impostos_entrada_erros_id_seq"'::"regclass");



ALTER TABLE ONLY "f"."ap_recorrencia"
    ADD CONSTRAINT "ap_recorrencia_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."arrendamento_contrato"
    ADD CONSTRAINT "arrendamento_contrato_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."arrendamento_parcela"
    ADD CONSTRAINT "arrendamento_parcela_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."credito_fiscal_manual_lancamento"
    ADD CONSTRAINT "credito_fiscal_manual_lancamento_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."credito_fiscal_manual_regra"
    ADD CONSTRAINT "credito_fiscal_manual_regra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."documento_fiscal_pendencia"
    ADD CONSTRAINT "documento_fiscal_pendencia_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."irpj_csll_regra_plano"
    ADD CONSTRAINT "irpj_csll_regra_plano_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."anexo"
    ADD CONSTRAINT "pk_f_anexo" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."aprovacao_evento"
    ADD CONSTRAINT "pk_f_aprovacao_evento" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."centro_custo"
    ADD CONSTRAINT "pk_f_centro_custo" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."conciliacao_bancaria"
    ADD CONSTRAINT "pk_f_conciliacao_bancaria" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."conciliacao_lancamento"
    ADD CONSTRAINT "pk_f_conciliacao_lancamento" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."conta_bancaria"
    ADD CONSTRAINT "pk_f_conta_bancaria" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "pk_f_documento_fiscal" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."documento_fiscal_imposto"
    ADD CONSTRAINT "pk_f_documento_fiscal_imposto" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."documento_fiscal_item"
    ADD CONSTRAINT "pk_f_documento_fiscal_item" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."documento_fiscal_xml"
    ADD CONSTRAINT "pk_f_documento_fiscal_xml" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."evento_financeiro"
    ADD CONSTRAINT "pk_f_evento_financeiro" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."extrato_bancario"
    ADD CONSTRAINT "pk_f_extrato_bancario" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."extrato_bancario_linha"
    ADD CONSTRAINT "pk_f_extrato_bancario_linha" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."fin_config"
    ADD CONSTRAINT "pk_f_fin_config" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."gestao_cobranca_os"
    ADD CONSTRAINT "pk_f_gestao_cobranca_os" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."importacao_doc_log"
    ADD CONSTRAINT "pk_f_importacao_doc_log" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."imposto_retencao"
    ADD CONSTRAINT "pk_f_imposto_retencao" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."irpj_csll_ajuste"
    ADD CONSTRAINT "pk_f_irpj_csll_ajuste" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."irpj_csll_financeiro_config"
    ADD CONSTRAINT "pk_f_irpj_csll_financeiro_config" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."irpj_csll_saldo_inicial"
    ADD CONSTRAINT "pk_f_irpj_csll_saldo_inicial" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."motivo_compra"
    ADD CONSTRAINT "pk_f_motivo_compra" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."pagamento"
    ADD CONSTRAINT "pk_f_pagamento" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."pagamento_item"
    ADD CONSTRAINT "pk_f_pagamento_item" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."parametro_financeiro_empresa"
    ADD CONSTRAINT "pk_f_parametro_financeiro_empresa" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."parametro_irpj_csll_empresa"
    ADD CONSTRAINT "pk_f_parametro_irpj_csll_empresa" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."plano_contas"
    ADD CONSTRAINT "pk_f_plano_contas" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "pk_f_titulo" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."titulo_agendamento"
    ADD CONSTRAINT "pk_f_titulo_agendamento" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."titulo_aprovacao"
    ADD CONSTRAINT "pk_f_titulo_aprovacao" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."titulo_parcela"
    ADD CONSTRAINT "pk_f_titulo_parcela" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."titulo_rateio"
    ADD CONSTRAINT "pk_f_titulo_rateio" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."vencimento_regra"
    ADD CONSTRAINT "pk_f_vencimento_regra" PRIMARY KEY ("id");



ALTER TABLE "f"."titulo"
    ADD CONSTRAINT "titulo_motivo_compra_obrigatorio_chk" CHECK ((("origem" <> 'XML'::"text") OR ("motivo_compra_id" IS NOT NULL))) NOT VALID;



ALTER TABLE "f"."titulo_rateio"
    ADD CONSTRAINT "titulo_rateio_plano_contas_obrigatorio" CHECK (("plano_contas_id" IS NOT NULL)) NOT VALID;



ALTER TABLE ONLY "f"."tmp_backfill_impostos_entrada_erros"
    ADD CONSTRAINT "tmp_backfill_impostos_entrada_erros_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."centro_custo"
    ADD CONSTRAINT "uq_centro_custo__tenant_empresa_codigo" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "f"."conta_bancaria"
    ADD CONSTRAINT "uq_conta_bancaria__tenant_empresa_codigo" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "f"."documento_fiscal_pendencia"
    ADD CONSTRAINT "uq_doc_pend" UNIQUE ("tenant_id", "documento_fiscal_id", "tipo");



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "uq_documento_fiscal__tenant_chave" UNIQUE ("tenant_id", "chave_acesso");



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "uq_documento_fiscal__tenant_source_nf" UNIQUE ("tenant_id", "source_nf_entrada_id");



ALTER TABLE ONLY "f"."documento_fiscal_imposto"
    ADD CONSTRAINT "uq_documento_fiscal_imposto__doc_imp_nat" UNIQUE ("tenant_id", "documento_fiscal_id", "imposto", "natureza");



ALTER TABLE ONLY "f"."documento_fiscal_item"
    ADD CONSTRAINT "uq_documento_fiscal_item__doc_itemn" UNIQUE ("tenant_id", "documento_fiscal_id", "item_n");



ALTER TABLE ONLY "f"."documento_fiscal_xml"
    ADD CONSTRAINT "uq_documento_fiscal_xml__tenant_doc" UNIQUE ("tenant_id", "documento_fiscal_id");



ALTER TABLE ONLY "f"."fin_config"
    ADD CONSTRAINT "uq_fin_config__tenant_empresa" UNIQUE ("tenant_id", "empresa_id");



ALTER TABLE ONLY "f"."gestao_cobranca_os"
    ADD CONSTRAINT "uq_gestao_cobranca_os__tenant_empresa_os" UNIQUE ("tenant_id", "empresa_id", "os_id");



ALTER TABLE ONLY "f"."irpj_csll_financeiro_config"
    ADD CONSTRAINT "uq_irpj_csll_fin_config__tenant_empresa" UNIQUE ("tenant_id", "empresa_id");



ALTER TABLE ONLY "f"."irpj_csll_saldo_inicial"
    ADD CONSTRAINT "uq_irpj_csll_saldo_inicial__tenant_id__empresa_id" UNIQUE ("tenant_id", "empresa_id");



ALTER TABLE ONLY "f"."motivo_compra"
    ADD CONSTRAINT "uq_motivo_compra__tenant_codigo" UNIQUE ("tenant_id", "codigo");



ALTER TABLE ONLY "f"."motivo_compra"
    ADD CONSTRAINT "uq_motivo_compra__tenant_nome" UNIQUE ("tenant_id", "nome");



ALTER TABLE ONLY "f"."pagamento_item"
    ADD CONSTRAINT "uq_pagamento_item__tenant_pagamento_parcela" UNIQUE ("tenant_id", "pagamento_id", "titulo_parcela_id");



ALTER TABLE ONLY "f"."parametro_financeiro_empresa"
    ADD CONSTRAINT "uq_param_fin_emp__tenant_empresa" UNIQUE ("tenant_id", "empresa_id");



ALTER TABLE ONLY "f"."parametro_irpj_csll_empresa"
    ADD CONSTRAINT "uq_parametro_irpj_csll_empresa__tenant_empresa" UNIQUE ("tenant_id", "empresa_id");



ALTER TABLE ONLY "f"."plano_contas"
    ADD CONSTRAINT "uq_plano_contas__tenant_codigo" UNIQUE ("tenant_id", "codigo");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "uq_titulo__recorrencia_competencia" UNIQUE ("tenant_id", "recorrencia_id", "competencia_date");



ALTER TABLE ONLY "f"."titulo_agendamento"
    ADD CONSTRAINT "uq_titulo_agendamento__tenant_titulo" UNIQUE ("tenant_id", "titulo_id");



ALTER TABLE ONLY "f"."titulo_aprovacao"
    ADD CONSTRAINT "uq_titulo_aprovacao__tenant_titulo" UNIQUE ("tenant_id", "titulo_id");



ALTER TABLE ONLY "f"."vencimento_regra"
    ADD CONSTRAINT "uq_vencimento_regra__tenant_codigo" UNIQUE ("tenant_id", "codigo");



CREATE INDEX "idx_centro_custo__tenant_empresa_parent" ON "f"."centro_custo" USING "btree" ("tenant_id", "empresa_id", "parent_id");



CREATE INDEX "idx_conciliacao__tenant_empresa_conta" ON "f"."conciliacao_bancaria" USING "btree" ("tenant_id", "empresa_id", "conta_bancaria_id");



CREATE INDEX "idx_conta_bancaria__tenant_empresa_ativo" ON "f"."conta_bancaria" USING "btree" ("tenant_id", "empresa_id", "ativo");



CREATE INDEX "idx_credito_fiscal_manual_lancamento_range" ON "f"."credito_fiscal_manual_lancamento" USING "btree" ("tenant_id", "empresa_id", "competencia_date", "imposto", "status") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_credito_fiscal_manual_regra_match" ON "f"."credito_fiscal_manual_regra" USING "btree" ("tenant_id", "empresa_id", "imposto", "ativo", "prioridade") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_documento_fiscal__tenant_empresa" ON "f"."documento_fiscal" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "idx_documento_fiscal__tenant_empresa_competencia" ON "f"."documento_fiscal" USING "btree" ("tenant_id", "empresa_id", "competencia_date");



CREATE INDEX "idx_documento_fiscal__tenant_empresa_operacao" ON "f"."documento_fiscal" USING "btree" ("tenant_id", "empresa_id", "operacao");



CREATE INDEX "idx_documento_fiscal__tenant_fornecedor" ON "f"."documento_fiscal" USING "btree" ("tenant_id", "fornecedor_id");



CREATE INDEX "idx_documento_fiscal_imposto__tenant_doc" ON "f"."documento_fiscal_imposto" USING "btree" ("tenant_id", "documento_fiscal_id");



CREATE INDEX "idx_documento_fiscal_item__tenant_doc" ON "f"."documento_fiscal_item" USING "btree" ("tenant_id", "documento_fiscal_id");



CREATE INDEX "idx_evento_financeiro__tenant_empresa_created" ON "f"."evento_financeiro" USING "btree" ("tenant_id", "empresa_id", "created_at" DESC);



CREATE INDEX "idx_extrato_bancario__tenant_empresa_conta" ON "f"."extrato_bancario" USING "btree" ("tenant_id", "empresa_id", "conta_bancaria_id");



CREATE INDEX "idx_extrato_linha__tenant_conta_data" ON "f"."extrato_bancario_linha" USING "btree" ("tenant_id", "conta_bancaria_id", "data_movimento");



CREATE INDEX "idx_extrato_linha__tenant_extrato" ON "f"."extrato_bancario_linha" USING "btree" ("tenant_id", "extrato_bancario_id");



CREATE INDEX "idx_gestao_cobranca_os__proximo_contato" ON "f"."gestao_cobranca_os" USING "btree" ("tenant_id", "empresa_id", "proximo_contato_date") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_gestao_cobranca_os__tenant_empresa_os" ON "f"."gestao_cobranca_os" USING "btree" ("tenant_id", "empresa_id", "os_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_gestao_cobranca_os__tenant_empresa_status" ON "f"."gestao_cobranca_os" USING "btree" ("tenant_id", "empresa_id", "status") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_irpj_csll_ajuste__tenant_empresa_comp" ON "f"."irpj_csll_ajuste" USING "btree" ("tenant_id", "empresa_id", "competencia_date") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_irpj_csll_ajuste__tenant_empresa_tipo" ON "f"."irpj_csll_ajuste" USING "btree" ("tenant_id", "empresa_id", "escopo", "tipo") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_irpj_csll_saldo_inicial__tenant_empresa" ON "f"."irpj_csll_saldo_inicial" USING "btree" ("tenant_id", "empresa_id", "competencia_inicio") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_motivo_compra__tenant_aplica_em" ON "f"."motivo_compra" USING "btree" ("tenant_id", "aplica_em") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_motivo_compra__tenant_ativo" ON "f"."motivo_compra" USING "btree" ("tenant_id", "ativo");



CREATE INDEX "idx_motivo_compra__tenant_fav_ord_nome" ON "f"."motivo_compra" USING "btree" ("tenant_id", "favorito" DESC, "ordem" DESC, "nome") WHERE (("deleted_at" IS NULL) AND ("ativo" = true));



CREATE INDEX "idx_motivo_compra__tenant_plano" ON "f"."motivo_compra" USING "btree" ("tenant_id", "plano_contas_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_param_irpj_csll_empresa__tenant_empresa" ON "f"."parametro_irpj_csll_empresa" USING "btree" ("tenant_id", "empresa_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_plano_contas__tenant_parent" ON "f"."plano_contas" USING "btree" ("tenant_id", "parent_id");



CREATE INDEX "idx_titulo__arrendamento_contrato" ON "f"."titulo" USING "btree" ("tenant_id", "empresa_id", "arrendamento_contrato_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_titulo__recorrencia_id" ON "f"."titulo" USING "btree" ("recorrencia_id");



CREATE INDEX "idx_titulo__tenant_empresa_competencia_tipo" ON "f"."titulo" USING "btree" ("tenant_id", "empresa_id", "competencia_date", "tipo") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_titulo__tenant_empresa_status" ON "f"."titulo" USING "btree" ("tenant_id", "empresa_id", "status");



CREATE INDEX "idx_titulo_agendamento__tenant_titulo" ON "f"."titulo_agendamento" USING "btree" ("tenant_id", "titulo_id");



CREATE INDEX "idx_titulo_parcela__tenant_titulo" ON "f"."titulo_parcela" USING "btree" ("tenant_id", "titulo_id");



CREATE INDEX "idx_titulo_rateio__tenant_plano" ON "f"."titulo_rateio" USING "btree" ("tenant_id", "plano_contas_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_titulo_rateio__tenant_titulo" ON "f"."titulo_rateio" USING "btree" ("tenant_id", "titulo_id") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_arr_contrato__key" ON "f"."arrendamento_contrato" USING "btree" ("tenant_id", "empresa_id", "fornecedor_id", "competencia_inicio", "prazo_meses", "valor_parcela") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_arr_parcela__contrato_comp" ON "f"."arrendamento_parcela" USING "btree" ("tenant_id", "contrato_id", "competencia_date") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_conciliacao__tenant_extrato_linha" ON "f"."conciliacao_bancaria" USING "btree" ("tenant_id", "extrato_linha_id") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_conciliacao__tenant_pagamento" ON "f"."conciliacao_bancaria" USING "btree" ("tenant_id", "pagamento_id") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_credito_fiscal_manual_lancamento_unique" ON "f"."credito_fiscal_manual_lancamento" USING "btree" ("tenant_id", "titulo_id", "imposto", "competencia_date", COALESCE("regra_id", '00000000-0000-0000-0000-000000000000'::"uuid")) WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_extrato_linha__tenant_conta_fitid" ON "f"."extrato_bancario_linha" USING "btree" ("tenant_id", "conta_bancaria_id", "fit_id") WHERE (("fit_id" IS NOT NULL) AND ("deleted_at" IS NULL));



CREATE UNIQUE INDEX "uq_irpj_csll_regra_plano__key" ON "f"."irpj_csll_regra_plano" USING "btree" ("tenant_id", "empresa_id", "plano_contas_id", "escopo", "tipo") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_titulo__apuracao_irpj_csll" ON "f"."titulo" USING "btree" ("tenant_id", "empresa_id", "competencia_date", "descricao") WHERE (("deleted_at" IS NULL) AND ("tipo" = 'AP'::"text") AND ("origem" = 'APURACAO_IRPJ_CSLL'::"text"));



CREATE UNIQUE INDEX "uq_titulo_parcela__tenant_id_titulo_id_numero__active" ON "f"."titulo_parcela" USING "btree" ("tenant_id", "titulo_id", "numero") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_titulo_parcela__tenant_titulo_numero" ON "f"."titulo_parcela" USING "btree" ("tenant_id", "titulo_id", "numero") WHERE ("deleted_at" IS NULL);



CREATE OR REPLACE TRIGGER "tg_titulo_ap_auto_rateio_por_motivo" AFTER INSERT ON "f"."titulo" FOR EACH ROW EXECUTE FUNCTION "f"."trg_titulo_ap_auto_rateio_por_motivo"();



CREATE OR REPLACE TRIGGER "trg_audit_anexo" AFTER INSERT OR DELETE OR UPDATE ON "f"."anexo" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_aprovacao_evento" AFTER INSERT OR DELETE OR UPDATE ON "f"."aprovacao_evento" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_centro_custo" AFTER INSERT OR DELETE OR UPDATE ON "f"."centro_custo" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_conciliacao_bancaria" AFTER INSERT OR DELETE OR UPDATE ON "f"."conciliacao_bancaria" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_conciliacao_lancamento" AFTER INSERT OR DELETE OR UPDATE ON "f"."conciliacao_lancamento" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_conta_bancaria" AFTER INSERT OR DELETE OR UPDATE ON "f"."conta_bancaria" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_documento_fiscal" AFTER INSERT OR DELETE OR UPDATE ON "f"."documento_fiscal" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_documento_fiscal_xml" AFTER INSERT OR DELETE OR UPDATE ON "f"."documento_fiscal_xml" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_evento_financeiro" AFTER INSERT OR DELETE OR UPDATE ON "f"."evento_financeiro" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_extrato_bancario" AFTER INSERT OR DELETE OR UPDATE ON "f"."extrato_bancario" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_extrato_linha" AFTER INSERT OR DELETE OR UPDATE ON "f"."extrato_bancario_linha" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_fin_config" AFTER INSERT OR DELETE OR UPDATE ON "f"."fin_config" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_gestao_cobranca_os" AFTER INSERT OR DELETE OR UPDATE ON "f"."gestao_cobranca_os" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_importacao_doc_log" AFTER INSERT OR DELETE OR UPDATE ON "f"."importacao_doc_log" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_imposto_retencao" AFTER INSERT OR DELETE OR UPDATE ON "f"."imposto_retencao" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_motivo_compra" AFTER INSERT OR DELETE OR UPDATE ON "f"."motivo_compra" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_pagamento" AFTER INSERT OR DELETE OR UPDATE ON "f"."pagamento" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_pagamento_item" AFTER INSERT OR DELETE OR UPDATE ON "f"."pagamento_item" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_plano_contas" AFTER INSERT OR DELETE OR UPDATE ON "f"."plano_contas" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_titulo" AFTER INSERT OR DELETE OR UPDATE ON "f"."titulo" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_titulo_agendamento" AFTER INSERT OR DELETE OR UPDATE ON "f"."titulo_agendamento" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_titulo_aprovacao" AFTER INSERT OR DELETE OR UPDATE ON "f"."titulo_aprovacao" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_titulo_parcela" AFTER INSERT OR DELETE OR UPDATE ON "f"."titulo_parcela" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_titulo_rateio" AFTER INSERT OR DELETE OR UPDATE ON "f"."titulo_rateio" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_centro_custo_set_updated_at" BEFORE UPDATE ON "f"."centro_custo" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_centro_custo_set_updated_by" BEFORE UPDATE ON "f"."centro_custo" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_conta_bancaria_set_updated_at" BEFORE UPDATE ON "f"."conta_bancaria" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_conta_bancaria_set_updated_by" BEFORE UPDATE ON "f"."conta_bancaria" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_documento_fiscal__ar_nfe" AFTER INSERT OR UPDATE OF "nfe_status", "cliente_id", "valor_total", "emissao_date", "competencia_date" ON "f"."documento_fiscal" FOR EACH ROW EXECUTE FUNCTION "f"."trg_documento_fiscal__ar_nfe"();



CREATE OR REPLACE TRIGGER "trg_documento_fiscal__ar_nfse" AFTER INSERT OR UPDATE OF "nfse_status", "cliente_id", "valor_total", "emissao_date", "competencia_date" ON "f"."documento_fiscal" FOR EACH ROW EXECUTE FUNCTION "f"."trg_documento_fiscal__ar_nfse"();



CREATE OR REPLACE TRIGGER "trg_documento_fiscal__sync_xml_pendencia" AFTER INSERT OR UPDATE OF "source_nf_entrada_id", "chave_acesso", "natureza", "operacao", "deleted_at" ON "f"."documento_fiscal" FOR EACH ROW EXECUTE FUNCTION "f"."fn_documento_fiscal__sync_xml_pendencia"();



CREATE OR REPLACE TRIGGER "trg_documento_fiscal_set_updated_at" BEFORE UPDATE ON "f"."documento_fiscal" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_documento_fiscal_set_updated_by" BEFORE UPDATE ON "f"."documento_fiscal" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_documento_fiscal_xml__valida_emitente_saida" BEFORE INSERT OR UPDATE OF "xml_raw" ON "f"."documento_fiscal_xml" FOR EACH ROW EXECUTE FUNCTION "f"."trg_documento_fiscal_xml__valida_emitente_saida"();



CREATE OR REPLACE TRIGGER "trg_extrato_bancario_set_updated_at" BEFORE UPDATE ON "f"."extrato_bancario" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_extrato_bancario_set_updated_by" BEFORE UPDATE ON "f"."extrato_bancario" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_extrato_linha_set_updated_at" BEFORE UPDATE ON "f"."extrato_bancario_linha" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_extrato_linha_set_updated_by" BEFORE UPDATE ON "f"."extrato_bancario_linha" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_fin_config_set_updated_at" BEFORE UPDATE ON "f"."fin_config" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_fin_config_set_updated_by" BEFORE UPDATE ON "f"."fin_config" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_gestao_cobranca_os_set_updated_at" BEFORE UPDATE ON "f"."gestao_cobranca_os" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_gestao_cobranca_os_set_updated_by" BEFORE UPDATE ON "f"."gestao_cobranca_os" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_imposto_retencao_set_updated_at" BEFORE UPDATE ON "f"."imposto_retencao" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_imposto_retencao_set_updated_by" BEFORE UPDATE ON "f"."imposto_retencao" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_motivo_compra_set_updated_at" BEFORE UPDATE ON "f"."motivo_compra" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_motivo_compra_set_updated_by" BEFORE UPDATE ON "f"."motivo_compra" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_nfse_sync_piscofins_from_doc" AFTER INSERT OR UPDATE OF "valor_servicos", "valor_total", "material_valor", "chave_acesso", "modelo", "operacao", "natureza", "deleted_at" ON "f"."documento_fiscal" FOR EACH ROW EXECUTE FUNCTION "f"."trg_nfse_sync_piscofins_from_doc"();



CREATE OR REPLACE TRIGGER "trg_nfse_sync_piscofins_from_imposto_ret" AFTER INSERT OR UPDATE OF "valor_calculado", "valor_ajustado", "aliquota", "natureza", "deleted_at" ON "f"."documento_fiscal_imposto" FOR EACH ROW WHEN ((("new"."imposto" = ANY (ARRAY['PIS'::"text", 'COFINS'::"text"])) AND ("new"."natureza" = 'RETENCAO'::"text"))) EXECUTE FUNCTION "f"."trg_nfse_sync_piscofins_from_imposto_ret"();



CREATE OR REPLACE TRIGGER "trg_pagamento_set_updated_at" BEFORE UPDATE ON "f"."pagamento" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_pagamento_set_updated_by" BEFORE UPDATE ON "f"."pagamento" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_plano_contas_set_updated_at" BEFORE UPDATE ON "f"."plano_contas" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_plano_contas_set_updated_by" BEFORE UPDATE ON "f"."plano_contas" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_titulo__aplicar_credito_fiscal_manual" AFTER INSERT OR UPDATE OF "tipo", "origem", "fornecedor_id", "motivo_compra_id", "descricao", "emissao_date", "competencia_date", "valor_total", "documento_fiscal_id", "deleted_at" ON "f"."titulo" FOR EACH ROW EXECUTE FUNCTION "f"."trg_titulo__aplicar_credito_fiscal_manual"();



CREATE OR REPLACE TRIGGER "trg_titulo_agendamento_set_updated_at" BEFORE UPDATE ON "f"."titulo_agendamento" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_titulo_agendamento_set_updated_by" BEFORE UPDATE ON "f"."titulo_agendamento" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_titulo_aprovacao_set_updated_at" BEFORE UPDATE ON "f"."titulo_aprovacao" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_titulo_aprovacao_set_updated_by" BEFORE UPDATE ON "f"."titulo_aprovacao" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_titulo_parcela_set_updated_at" BEFORE UPDATE ON "f"."titulo_parcela" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_titulo_parcela_set_updated_by" BEFORE UPDATE ON "f"."titulo_parcela" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_titulo_rateio_set_updated_at" BEFORE UPDATE ON "f"."titulo_rateio" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_titulo_rateio_set_updated_by" BEFORE UPDATE ON "f"."titulo_rateio" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_titulo_require_motivo_compra" BEFORE INSERT OR UPDATE ON "f"."titulo" FOR EACH ROW EXECUTE FUNCTION "f"."trg_titulo_require_motivo_compra"();



CREATE OR REPLACE TRIGGER "trg_titulo_set_updated_at" BEFORE UPDATE ON "f"."titulo" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_titulo_set_updated_by" BEFORE UPDATE ON "f"."titulo" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_titulo_sync_rateio_apuracao_irpj_csll" AFTER INSERT OR UPDATE OF "valor_total" ON "f"."titulo" FOR EACH ROW EXECUTE FUNCTION "f"."trg_sync_rateio_apuracao_irpj_csll"();



ALTER TABLE ONLY "f"."anexo"
    ADD CONSTRAINT "fk_anexo__uploaded_by__usuario" FOREIGN KEY ("uploaded_by") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "f"."aprovacao_evento"
    ADD CONSTRAINT "fk_aprovacao_evento__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."arrendamento_contrato"
    ADD CONSTRAINT "fk_arr_contrato__fornecedor" FOREIGN KEY ("fornecedor_id") REFERENCES "public"."fornecedores"("id");



ALTER TABLE ONLY "f"."arrendamento_contrato"
    ADD CONSTRAINT "fk_arr_contrato__motivo" FOREIGN KEY ("motivo_compra_id") REFERENCES "f"."motivo_compra"("id");



ALTER TABLE ONLY "f"."arrendamento_parcela"
    ADD CONSTRAINT "fk_arr_parcela__contrato" FOREIGN KEY ("contrato_id") REFERENCES "f"."arrendamento_contrato"("id");



ALTER TABLE ONLY "f"."arrendamento_parcela"
    ADD CONSTRAINT "fk_arr_parcela__titulo" FOREIGN KEY ("titulo_id") REFERENCES "f"."titulo"("id");



ALTER TABLE ONLY "f"."centro_custo"
    ADD CONSTRAINT "fk_centro_custo__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."centro_custo"
    ADD CONSTRAINT "fk_centro_custo__parent_id__centro_custo" FOREIGN KEY ("parent_id") REFERENCES "f"."centro_custo"("id");



ALTER TABLE ONLY "f"."conciliacao_bancaria"
    ADD CONSTRAINT "fk_conciliacao_bancaria__conta_bancaria_id__conta_bancaria" FOREIGN KEY ("conta_bancaria_id") REFERENCES "f"."conta_bancaria"("id");



ALTER TABLE ONLY "f"."conciliacao_bancaria"
    ADD CONSTRAINT "fk_conciliacao_bancaria__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."conciliacao_lancamento"
    ADD CONSTRAINT "fk_conciliacao_lancamento__conciliacao_id__conciliacao" FOREIGN KEY ("conciliacao_id") REFERENCES "f"."conciliacao_bancaria"("id");



ALTER TABLE ONLY "f"."conciliacao_lancamento"
    ADD CONSTRAINT "fk_conciliacao_lancamento__conciliado_por__usuario" FOREIGN KEY ("conciliado_por") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "f"."conciliacao_lancamento"
    ADD CONSTRAINT "fk_conciliacao_lancamento__pagamento_id__pagamento" FOREIGN KEY ("pagamento_id") REFERENCES "f"."pagamento"("id");



ALTER TABLE ONLY "f"."conta_bancaria"
    ADD CONSTRAINT "fk_conta_bancaria__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."credito_fiscal_manual_lancamento"
    ADD CONSTRAINT "fk_credito_fiscal_manual_lancamento_regra" FOREIGN KEY ("regra_id") REFERENCES "f"."credito_fiscal_manual_regra"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "f"."credito_fiscal_manual_lancamento"
    ADD CONSTRAINT "fk_credito_fiscal_manual_lancamento_titulo" FOREIGN KEY ("titulo_id") REFERENCES "f"."titulo"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "f"."documento_fiscal_pendencia"
    ADD CONSTRAINT "fk_doc_pend__doc" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "fk_documento_fiscal__cliente_id__clientes" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id");



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "fk_documento_fiscal__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "fk_documento_fiscal__fornecedor_id__fornecedores" FOREIGN KEY ("fornecedor_id") REFERENCES "public"."fornecedores"("id");



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "fk_documento_fiscal__os_id_import__ordens_servico" FOREIGN KEY ("os_id_import") REFERENCES "public"."ordens_servico"("id");



ALTER TABLE ONLY "f"."documento_fiscal"
    ADD CONSTRAINT "fk_documento_fiscal__source_nf_entrada_id__nf_entrada" FOREIGN KEY ("source_nf_entrada_id") REFERENCES "public"."nf_entrada"("id");



ALTER TABLE ONLY "f"."documento_fiscal_imposto"
    ADD CONSTRAINT "fk_documento_fiscal_imposto__documento_fiscal_id__documento_fis" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "f"."documento_fiscal_item"
    ADD CONSTRAINT "fk_documento_fiscal_item__documento_fiscal_id__documento_fiscal" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "f"."documento_fiscal_xml"
    ADD CONSTRAINT "fk_documento_fiscal_xml__documento_fiscal_id__documento_fiscal" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id");



ALTER TABLE ONLY "f"."evento_financeiro"
    ADD CONSTRAINT "fk_evento_financeiro__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."extrato_bancario"
    ADD CONSTRAINT "fk_extrato_bancario__conta_bancaria_id__conta_bancaria" FOREIGN KEY ("conta_bancaria_id") REFERENCES "f"."conta_bancaria"("id");



ALTER TABLE ONLY "f"."extrato_bancario"
    ADD CONSTRAINT "fk_extrato_bancario__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."extrato_bancario_linha"
    ADD CONSTRAINT "fk_extrato_linha__conta_bancaria_id__conta_bancaria" FOREIGN KEY ("conta_bancaria_id") REFERENCES "f"."conta_bancaria"("id");



ALTER TABLE ONLY "f"."extrato_bancario_linha"
    ADD CONSTRAINT "fk_extrato_linha__extrato_bancario_id__extrato_bancario" FOREIGN KEY ("extrato_bancario_id") REFERENCES "f"."extrato_bancario"("id");



ALTER TABLE ONLY "f"."fin_config"
    ADD CONSTRAINT "fk_fin_config__conta_bancaria_padrao_id__conta_bancaria" FOREIGN KEY ("conta_bancaria_padrao_id") REFERENCES "f"."conta_bancaria"("id");



ALTER TABLE ONLY "f"."importacao_doc_log"
    ADD CONSTRAINT "fk_importacao_doc_log__documento_fiscal_id__documento_fiscal" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id");



ALTER TABLE ONLY "f"."importacao_doc_log"
    ADD CONSTRAINT "fk_importacao_doc_log__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."imposto_retencao"
    ADD CONSTRAINT "fk_imposto_retencao__documento_fiscal_id__documento_fiscal" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id");



ALTER TABLE ONLY "f"."imposto_retencao"
    ADD CONSTRAINT "fk_imposto_retencao__titulo_id__titulo" FOREIGN KEY ("titulo_id") REFERENCES "f"."titulo"("id");



ALTER TABLE ONLY "f"."motivo_compra"
    ADD CONSTRAINT "fk_motivo_compra__plano_contas_id__f_plano_contas" FOREIGN KEY ("plano_contas_id") REFERENCES "f"."plano_contas"("id");



ALTER TABLE ONLY "f"."pagamento"
    ADD CONSTRAINT "fk_pagamento__conciliado_por__usuario" FOREIGN KEY ("conciliado_por") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "f"."pagamento"
    ADD CONSTRAINT "fk_pagamento__conta_bancaria_id__conta_bancaria" FOREIGN KEY ("conta_bancaria_id") REFERENCES "f"."conta_bancaria"("id");



ALTER TABLE ONLY "f"."pagamento"
    ADD CONSTRAINT "fk_pagamento__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."pagamento"
    ADD CONSTRAINT "fk_pagamento__pago_por__usuario" FOREIGN KEY ("pago_por") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "f"."pagamento_item"
    ADD CONSTRAINT "fk_pagamento_item__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."pagamento_item"
    ADD CONSTRAINT "fk_pagamento_item__pagamento_id__pagamento" FOREIGN KEY ("pagamento_id") REFERENCES "f"."pagamento"("id");



ALTER TABLE ONLY "f"."pagamento_item"
    ADD CONSTRAINT "fk_pagamento_item__titulo_parcela_id__titulo_parcela" FOREIGN KEY ("titulo_parcela_id") REFERENCES "f"."titulo_parcela"("id");



ALTER TABLE ONLY "f"."parametro_financeiro_empresa"
    ADD CONSTRAINT "fk_param_fin_emp__conta_bancaria_padrao_id__conta_bancaria" FOREIGN KEY ("conta_bancaria_padrao_id") REFERENCES "f"."conta_bancaria"("id");



ALTER TABLE ONLY "f"."parametro_financeiro_empresa"
    ADD CONSTRAINT "fk_param_fin_emp__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."plano_contas"
    ADD CONSTRAINT "fk_plano_contas__parent_id__plano_contas" FOREIGN KEY ("parent_id") REFERENCES "f"."plano_contas"("id");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "fk_titulo__arrendamento_contrato" FOREIGN KEY ("arrendamento_contrato_id") REFERENCES "f"."arrendamento_contrato"("id");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "fk_titulo__cliente_id__clientes" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "fk_titulo__documento_fiscal_id__documento_fiscal" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "fk_titulo__empresa_id__empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "fk_titulo__fornecedor_id__fornecedores" FOREIGN KEY ("fornecedor_id") REFERENCES "public"."fornecedores"("id");



ALTER TABLE ONLY "f"."titulo_agendamento"
    ADD CONSTRAINT "fk_titulo_agendamento__agendado_por__usuario" FOREIGN KEY ("agendado_por") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "f"."titulo_agendamento"
    ADD CONSTRAINT "fk_titulo_agendamento__conta_bancaria_id__conta_bancaria" FOREIGN KEY ("conta_bancaria_id") REFERENCES "f"."conta_bancaria"("id");



ALTER TABLE ONLY "f"."titulo_agendamento"
    ADD CONSTRAINT "fk_titulo_agendamento__titulo_id__titulo" FOREIGN KEY ("titulo_id") REFERENCES "f"."titulo"("id");



ALTER TABLE ONLY "f"."titulo_aprovacao"
    ADD CONSTRAINT "fk_titulo_aprovacao__aprovado_por__usuario" FOREIGN KEY ("aprovado_por") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "f"."titulo_aprovacao"
    ADD CONSTRAINT "fk_titulo_aprovacao__motivo_compra_id__motivo_compra" FOREIGN KEY ("motivo_compra_id") REFERENCES "f"."motivo_compra"("id");



ALTER TABLE ONLY "f"."titulo_aprovacao"
    ADD CONSTRAINT "fk_titulo_aprovacao__os_id__ordens_servico" FOREIGN KEY ("os_id") REFERENCES "public"."ordens_servico"("id");



ALTER TABLE ONLY "f"."titulo_aprovacao"
    ADD CONSTRAINT "fk_titulo_aprovacao__titulo_id__titulo" FOREIGN KEY ("titulo_id") REFERENCES "f"."titulo"("id");



ALTER TABLE ONLY "f"."titulo_parcela"
    ADD CONSTRAINT "fk_titulo_parcela__titulo_id__titulo" FOREIGN KEY ("titulo_id") REFERENCES "f"."titulo"("id");



ALTER TABLE ONLY "f"."titulo_rateio"
    ADD CONSTRAINT "fk_titulo_rateio__centro_custo_id__centro_custo" FOREIGN KEY ("centro_custo_id") REFERENCES "f"."centro_custo"("id");



ALTER TABLE ONLY "f"."titulo_rateio"
    ADD CONSTRAINT "fk_titulo_rateio__os_id__ordens_servico" FOREIGN KEY ("os_id") REFERENCES "public"."ordens_servico"("id");



ALTER TABLE ONLY "f"."titulo_rateio"
    ADD CONSTRAINT "fk_titulo_rateio__plano_contas_id__plano_contas" FOREIGN KEY ("plano_contas_id") REFERENCES "f"."plano_contas"("id");



ALTER TABLE ONLY "f"."titulo_rateio"
    ADD CONSTRAINT "fk_titulo_rateio__titulo_id__titulo" FOREIGN KEY ("titulo_id") REFERENCES "f"."titulo"("id");



ALTER TABLE ONLY "f"."gestao_cobranca_os"
    ADD CONSTRAINT "gestao_cobranca_os_documento_fiscal_id_fkey" FOREIGN KEY ("documento_fiscal_id") REFERENCES "f"."documento_fiscal"("id");



ALTER TABLE ONLY "f"."gestao_cobranca_os"
    ADD CONSTRAINT "gestao_cobranca_os_os_id_fkey" FOREIGN KEY ("os_id") REFERENCES "public"."ordens_servico"("id");



ALTER TABLE ONLY "f"."gestao_cobranca_os"
    ADD CONSTRAINT "gestao_cobranca_os_responsavel_id_fkey" FOREIGN KEY ("responsavel_id") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "f"."gestao_cobranca_os"
    ADD CONSTRAINT "gestao_cobranca_os_titulo_ar_id_fkey" FOREIGN KEY ("titulo_ar_id") REFERENCES "f"."titulo"("id");



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "titulo_motivo_compra_fk" FOREIGN KEY ("motivo_compra_id") REFERENCES "f"."motivo_compra"("id");



ALTER TABLE "f"."anexo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "anexo_all" ON "f"."anexo" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."aprovacao_evento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "aprovacao_evento_all" ON "f"."aprovacao_evento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."arrendamento_contrato" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "arrendamento_contrato_all" ON "f"."arrendamento_contrato" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."arrendamento_parcela" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "arrendamento_parcela_all" ON "f"."arrendamento_parcela" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."centro_custo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "centro_custo_all" ON "f"."centro_custo" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."conciliacao_bancaria" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conciliacao_bancaria_all" ON "f"."conciliacao_bancaria" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."conciliacao_lancamento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conciliacao_lancamento_all" ON "f"."conciliacao_lancamento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."conta_bancaria" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conta_bancaria_all" ON "f"."conta_bancaria" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."credito_fiscal_manual_lancamento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "credito_fiscal_manual_lancamento_all" ON "f"."credito_fiscal_manual_lancamento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."credito_fiscal_manual_regra" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "credito_fiscal_manual_regra_all" ON "f"."credito_fiscal_manual_regra" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."documento_fiscal" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "documento_fiscal_all" ON "f"."documento_fiscal" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."documento_fiscal_imposto" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "documento_fiscal_imposto_all" ON "f"."documento_fiscal_imposto" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"() AND (EXISTS ( SELECT 1
   FROM "f"."documento_fiscal" "df"
  WHERE (("df"."id" = "documento_fiscal_imposto"."documento_fiscal_id") AND ("df"."tenant_id" = "public"."current_tenant_id"()) AND ("df"."empresa_id" = "public"."current_empresa_id"()) AND ("df"."deleted_at" IS NULL)))))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"() AND (EXISTS ( SELECT 1
   FROM "f"."documento_fiscal" "df"
  WHERE (("df"."id" = "documento_fiscal_imposto"."documento_fiscal_id") AND ("df"."tenant_id" = "public"."current_tenant_id"()) AND ("df"."empresa_id" = "public"."current_empresa_id"()) AND ("df"."deleted_at" IS NULL))))));



ALTER TABLE "f"."documento_fiscal_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "documento_fiscal_item_all" ON "f"."documento_fiscal_item" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"() AND (EXISTS ( SELECT 1
   FROM "f"."documento_fiscal" "df"
  WHERE (("df"."id" = "documento_fiscal_item"."documento_fiscal_id") AND ("df"."tenant_id" = "public"."current_tenant_id"()) AND ("df"."empresa_id" = "public"."current_empresa_id"()) AND ("df"."deleted_at" IS NULL)))))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"() AND (EXISTS ( SELECT 1
   FROM "f"."documento_fiscal" "df"
  WHERE (("df"."id" = "documento_fiscal_item"."documento_fiscal_id") AND ("df"."tenant_id" = "public"."current_tenant_id"()) AND ("df"."empresa_id" = "public"."current_empresa_id"()) AND ("df"."deleted_at" IS NULL))))));



ALTER TABLE "f"."documento_fiscal_xml" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "documento_fiscal_xml_all" ON "f"."documento_fiscal_xml" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."evento_financeiro" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "evento_financeiro_all" ON "f"."evento_financeiro" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."extrato_bancario" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "extrato_bancario_all" ON "f"."extrato_bancario" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."extrato_bancario_linha" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "extrato_bancario_linha_all" ON "f"."extrato_bancario_linha" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."fin_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fin_config_all" ON "f"."fin_config" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."gestao_cobranca_os" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "gestao_cobranca_os_all" ON "f"."gestao_cobranca_os" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_cobranca_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_cobranca_access"()));



ALTER TABLE "f"."importacao_doc_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "importacao_doc_log_all" ON "f"."importacao_doc_log" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."imposto_retencao" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "imposto_retencao_all" ON "f"."imposto_retencao" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."motivo_compra" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "motivo_compra_all" ON "f"."motivo_compra" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



CREATE POLICY "motivo_compra_select_allowed_roles" ON "f"."motivo_compra" FOR SELECT TO "authenticated" USING ((("deleted_at" IS NULL) AND ("ativo" IS TRUE) AND "f"."has_motivo_compra_access"("tenant_id")));



ALTER TABLE "f"."pagamento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pagamento_all" ON "f"."pagamento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."pagamento_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pagamento_item_all" ON "f"."pagamento_item" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



CREATE POLICY "param_fin_emp_all" ON "f"."parametro_financeiro_empresa" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."parametro_financeiro_empresa" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "f"."plano_contas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "plano_contas_all" ON "f"."plano_contas" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."titulo" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "f"."titulo_agendamento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "titulo_agendamento_all" ON "f"."titulo_agendamento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



CREATE POLICY "titulo_all" ON "f"."titulo" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."titulo_aprovacao" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "titulo_aprovacao_all" ON "f"."titulo_aprovacao" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."titulo_parcela" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "titulo_parcela_all" ON "f"."titulo_parcela" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



ALTER TABLE "f"."titulo_rateio" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "titulo_rateio_all" ON "f"."titulo_rateio" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "f"."has_finance_access"()));



GRANT USAGE ON SCHEMA "f" TO "authenticated";
GRANT USAGE ON SCHEMA "f" TO "service_role";



GRANT ALL ON FUNCTION "f"."ajustar_valor_parcela_ap"("p_titulo_parcela_id" "uuid", "p_novo_valor" numeric, "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."atualizar_proximos_ap_recorrencia"("p_recorrencia_id" "uuid", "p_referencia_competencia" "date", "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."atualizar_titulo_emissao_date"("p_titulo_id" "uuid", "p_emissao_date" "date", "p_atualizar_competencia" boolean, "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."atualizar_titulo_emissao_date"("p_titulo_id" "uuid", "p_emissao_date" "date", "p_atualizar_competencia" boolean, "p_change_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date", "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."atualizar_titulo_parcela_vencimento_date"("p_parcela_id" "uuid", "p_vencimento_date" "date", "p_change_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "f"."criar_titulo_ap_manual"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."criar_titulo_ap_manual_v2"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_emissao_date" "date", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."criar_titulo_ap_manual_v2"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_emissao_date" "date", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "f"."desdobrar_parcela_ar_para_recebimento"("p_parcela_id" "uuid", "p_valor_receber" numeric, "p_novo_vencimento_date" "date", "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."desdobrar_parcela_ar_para_recebimento"("p_parcela_id" "uuid", "p_valor_receber" numeric, "p_novo_vencimento_date" "date", "p_change_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_aplicar_credito_fiscal_manual_titulo"("p_titulo_id" "uuid", "p_change_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_aplicar_credito_fiscal_manual_titulo"("p_titulo_id" "uuid", "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_aplicar_credito_fiscal_manual_titulo"("p_titulo_id" "uuid", "p_change_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_find_documento_fiscal_from_import"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nf_entrada_id" bigint, "p_chave_acesso" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_find_documento_fiscal_from_import"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nf_entrada_id" bigint, "p_chave_acesso" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_imposto_credito_conferencia_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_imposto_credito_conferencia_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_imposto_credito_conferencia_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_imposto_credito_manual_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_imposto_credito_manual_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_imposto_credito_manual_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_imposto_guardiao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_tipo" "text", "p_imposto" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_imposto_guardiao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_tipo" "text", "p_imposto" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_imposto_guardiao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_tipo" "text", "p_imposto" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_nfse_sync_piscofins_debito_doc"("p_documento_fiscal_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_nfse_sync_piscofins_debito_doc"("p_documento_fiscal_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "f"."fn_nfse_sync_piscofins_debito_doc"("p_documento_fiscal_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "f"."fn_pick_credito_fiscal_manual_regra"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_imposto" "text", "p_origem" "text", "p_descricao" "text", "p_motivo_compra_id" "uuid", "p_fornecedor_id" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_pick_credito_fiscal_manual_regra"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_imposto" "text", "p_origem" "text", "p_descricao" "text", "p_motivo_compra_id" "uuid", "p_fornecedor_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_pick_credito_fiscal_manual_regra"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_imposto" "text", "p_origem" "text", "p_descricao" "text", "p_motivo_compra_id" "uuid", "p_fornecedor_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "f"."fn_sync_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_sync_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "f"."gerar_ap_por_nf_entrada"("p_nf_entrada_id" bigint, "p_motivo_compra_id" "uuid", "p_parcelas_json" "jsonb") TO "authenticated";



GRANT ALL ON FUNCTION "f"."has_motivo_compra_access"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "f"."has_motivo_compra_access"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "f"."provisionar_ap_recorrencia"("p_recorrencia_id" "uuid", "p_meses_a_frente" integer, "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."registrar_recebimento_ar"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor" numeric, "p_observacoes" "text", "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."registrar_recebimento_ar_v2"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor_principal" numeric, "p_valor_juros" numeric, "p_valor_multa" numeric, "p_valor_desconto" numeric, "p_observacoes" "text", "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."registrar_recebimento_ar_v2"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor_principal" numeric, "p_valor_juros" numeric, "p_valor_multa" numeric, "p_valor_desconto" numeric, "p_observacoes" "text", "p_change_reason" "text") TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."anexo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."ap_recorrencia" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."aprovacao_evento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."arrendamento_contrato" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."arrendamento_parcela" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."centro_custo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."conciliacao_bancaria" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."conciliacao_lancamento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."conta_bancaria" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."credito_fiscal_manual_lancamento" TO "authenticated";
GRANT SELECT ON TABLE "f"."credito_fiscal_manual_lancamento" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."credito_fiscal_manual_regra" TO "authenticated";
GRANT SELECT ON TABLE "f"."credito_fiscal_manual_regra" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_imposto" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_item" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_pendencia" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_xml" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."evento_financeiro" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."extrato_bancario" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."extrato_bancario_linha" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."fin_config" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."gestao_cobranca_os" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."importacao_doc_log" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."imposto_retencao" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_ajuste" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_financeiro_config" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_regra_plano" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_saldo_inicial" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."motivo_compra" TO "authenticated";
GRANT SELECT ON TABLE "f"."motivo_compra" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."nf_entrada" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."pagamento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."pagamento_item" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."parametro_financeiro_empresa" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."parametro_irpj_csll_empresa" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."plano_contas" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo_aprovacao" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo_parcela" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_ap_aging_detalhe" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_ap_aging_resumo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo_agendamento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_previsto_diario" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_realizado_diario" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_diario" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_diario_conta_resolvida" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_previsto_diario_dim" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_realizado_diario_dim" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_diario_dim" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_diario_por_fornecedor" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_diario_por_motivo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_diario_por_motivo_rotulado" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_diario_por_os" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_caixa_mensal" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_fluxo_previsto_diario_ajustado_hoje" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_saldo_projetado_diario" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_saldo_projetado_diario_com_saldo_inicial" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_sugestoes_conciliacao_ap" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."r_titulos_sem_motivo_por_fornecedor" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo_rateio" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."tmp_backfill_impostos_entrada_erros" TO "authenticated";



GRANT SELECT,USAGE ON SEQUENCE "f"."tmp_backfill_impostos_entrada_erros_id_seq" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."vencimento_regra" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."vw_imposto_apuracao_mensal" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "f" GRANT SELECT,USAGE ON SEQUENCES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "f" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "authenticated";




