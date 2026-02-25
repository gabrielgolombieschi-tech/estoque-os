


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


CREATE SCHEMA IF NOT EXISTS "a";


ALTER SCHEMA "a" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "c";


ALTER SCHEMA "c" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "f";


ALTER SCHEMA "f" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "m";


ALTER SCHEMA "m" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "r";


ALTER SCHEMA "r" OWNER TO "postgres";


CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."capability_pair" AS (
	"key" "text",
	"resource" "text",
	"action" "text"
);


ALTER TYPE "public"."capability_pair" OWNER TO "postgres";


CREATE TYPE "public"."item_finalidade" AS ENUM (
    'consumo',
    'materia_prima',
    'revenda',
    'imobilizado',
    'outros'
);


ALTER TYPE "public"."item_finalidade" OWNER TO "postgres";


CREATE TYPE "public"."os_gestao_area" AS ENUM (
    'eletrico',
    'mecanico',
    'seguranca',
    'software'
);


ALTER TYPE "public"."os_gestao_area" OWNER TO "postgres";


CREATE TYPE "public"."os_gestao_tipo" AS ENUM (
    'projeto',
    'execucao'
);


ALTER TYPE "public"."os_gestao_tipo" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_empresa_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a', 'c'
    SET "row_security" TO 'off'
    AS $$
  with me as (
    select public.current_auth_user_id() as user_id
  )
  select coalesce(
    (
      select uec.empresa_id
      from me
      join public.user_empresa_context uec on uec.user_id = me.user_id
      where uec.tenant_id = public.current_tenant_id()
      limit 1
    ),
    (
      select em.empresa_id
      from me
      join public.empresa_memberships em on em.user_id = me.user_id
      where em.tenant_id = public.current_tenant_id()
        and em.status = 'active'
      order by em.criado_em asc
      limit 1
    ),
    (
      -- NOVO MODELO
      select ue.empresa_id
      from me
      join a.usuario u on u.auth_user_id = me.user_id
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.deleted_at is null
        and ue.deleted_at is null
        and ue.ativo = true
        and e.deleted_at is null
        and e.tenant_id = public.current_tenant_id()
      order by ue.created_at asc
      limit 1
    ),
    nullif(current_setting('app.current_empresa_id', true), '')::uuid
  );
$$;


ALTER FUNCTION "public"."current_empresa_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_tenant_id"() RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_user uuid := public.current_auth_user_id();
  v_tenant uuid;
begin
  if v_user is null then
    return null;
  end if;

  -- contexto (se existir)
  begin
    select utc.tenant_id
      into v_tenant
    from public.user_tenant_context utc
    where utc.user_id = v_user
    limit 1;

    if v_tenant is not null then
      return v_tenant;
    end if;
  exception when undefined_table then
    null;
  end;

  -- legacy memberships
  select tm.tenant_id
    into v_tenant
  from public.tenant_memberships tm
  where tm.user_id = v_user
    and tm.status = 'active'
  order by tm.created_at asc nulls last
  limit 1;

  if v_tenant is not null then
    return v_tenant;
  end if;

  -- NOVO MODELO: a.usuario_tenant
  select ut.tenant_id
    into v_tenant
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  where u.auth_user_id = v_user
    and u.deleted_at is null
    and ut.deleted_at is null
    and ut.ativo = true
  order by ut.created_at asc
  limit 1;

  return v_tenant;
end;
$$;


ALTER FUNCTION "public"."current_tenant_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."ensure_config_orcamento"("p_tenant" "uuid" DEFAULT "public"."current_tenant_id"(), "p_empresa" "uuid" DEFAULT "public"."current_empresa_id"()) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'a', 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_tenant uuid := coalesce(p_tenant, public.current_tenant_id());
  v_empresa uuid := coalesce(p_empresa, public.current_empresa_id());
  v_id uuid;
begin
  if v_tenant is null or v_empresa is null then
    raise exception 'ensure_config_orcamento: tenant_id/empresa_id ausentes no contexto. Passe os parâmetros explicitamente.';
  end if;

  select id into v_id
  from a.config_orcamento
  where tenant_id = v_tenant
    and empresa_id = v_empresa
    and deleted_at is null
  limit 1;

  if v_id is null then
    insert into a.config_orcamento (
      tenant_id, empresa_id,
      margem_lucro_padrao_percent,
      desconto_max_percent
    ) values (
      v_tenant, v_empresa,
      53, 0
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;


ALTER FUNCTION "a"."ensure_config_orcamento"("p_tenant" "uuid", "p_empresa" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_can_manage_empresa"("p_empresa_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'a', 'c', 'public'
    AS $$
  select a.fn_is_tenant_admin(a.fn_empresa_tenant_id(p_empresa_id));
$$;


ALTER FUNCTION "a"."fn_can_manage_empresa"("p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_current_usuario_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'a', 'public'
    SET "row_security" TO 'off'
    AS $$
  select u.id
  from a.usuario u
  where u.auth_user_id = public.current_auth_user_id()
    and u.deleted_at is null
  limit 1;
$$;


ALTER FUNCTION "a"."fn_current_usuario_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_empresa_tenant_id"("p_empresa_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'a', 'c', 'public'
    AS $$
  select e.tenant_id
  from c.empresa e
  where e.id = p_empresa_id
    and e.deleted_at is null
  limit 1;
$$;


ALTER FUNCTION "a"."fn_empresa_tenant_id"("p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_is_admin_of_same_tenant"("p_other_usuario_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'a', 'c', 'public'
    AS $$
  with me as (
    select u.id as usuario_id
    from a.usuario u
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
    limit 1
  )
  select exists (
    select 1
    from me
    join a.usuario_tenant ut_me
      on ut_me.usuario_id = me.usuario_id
    join a.usuario_tenant ut_other
      on ut_other.tenant_id = ut_me.tenant_id
     and ut_other.usuario_id = p_other_usuario_id
    where ut_me.deleted_at is null
      and ut_me.ativo = true
      and ut_me.papel in ('OWNER','ADMIN')
      and ut_other.deleted_at is null
      and ut_other.ativo = true
  );
$$;


ALTER FUNCTION "a"."fn_is_admin_of_same_tenant"("p_other_usuario_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_is_tenant_admin"("p_tenant_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'a', 'c', 'public'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut on ut.usuario_id = u.id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ut.deleted_at is null
      and ut.ativo = true
      and ut.tenant_id = p_tenant_id
      and ut.papel in ('OWNER','ADMIN')
  );
$$;


ALTER FUNCTION "a"."fn_is_tenant_admin"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_is_tenant_member"("p_tenant_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'a', 'c', 'public'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut on ut.usuario_id = u.id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ut.deleted_at is null
      and ut.ativo = true
      and ut.tenant_id = p_tenant_id
  );
$$;


ALTER FUNCTION "a"."fn_is_tenant_member"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_map_papel_empresa"("p" "text") RETURNS "text"
    LANGUAGE "sql"
    AS $$
  select case
    when p is null then 'ADMIN'
    when upper(p) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV') then upper(p)
    when upper(p) in ('OWNER','CONTADOR','GESTOR') then 'ADMIN'
    else 'ADMIN'
  end;
$$;


ALTER FUNCTION "a"."fn_map_papel_empresa"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_map_papel_empresa_to_role"("papel" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case upper(coalesce(papel,''))
    when 'ADMIN' then 'admin'
    when 'FINANCEIRO' then 'financeiro'
    when 'COORDENACAO' then 'projetos'
    when 'TECNICO' then 'projetos'
    when 'COMPRAS' then 'estoque'
    when 'ALMOXARIFADO' then 'estoque'
    when 'APONTAMENTO_RH' then 'projetos'
    when 'PAINEL_TV' then 'projetos'
    else 'estoque'
  end
$$;


ALTER FUNCTION "a"."fn_map_papel_empresa_to_role"("papel" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_map_papel_tenant"("p" "text") RETURNS "text"
    LANGUAGE "sql"
    AS $$
  select case
    when p is null then 'GESTOR'
    when upper(p) in ('OWNER','ADMIN','CONTADOR','GESTOR') then upper(p)
    when upper(p) in ('FINANCEIRO','COMPRAS','ALMOXARIFADO','TECNICO','COORDENACAO','APONTAMENTO_RH','PAINEL_TV') then 'GESTOR'
    else 'GESTOR'
  end;
$$;


ALTER FUNCTION "a"."fn_map_papel_tenant"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_map_papel_tenant_to_role"("p_papel" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case upper(coalesce(p_papel,''))
    when 'OWNER' then 'admin'
    when 'ADMIN' then 'admin'
    when 'CONTADOR' then 'fiscal'
    when 'GESTOR' then 'projetos'
    when 'FINANCEIRO' then 'financeiro'
    else 'estoque'
  end
$$;


ALTER FUNCTION "a"."fn_map_papel_tenant_to_role"("p_papel" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "a"."fn_set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "a"."fn_set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "c"."has_comercial_access"("p_tenant" "uuid" DEFAULT "public"."current_tenant_id"(), "p_empresa" "uuid" DEFAULT "public"."current_empresa_id"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'c', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
  with me as (
    select coalesce(
      nullif(auth.jwt() ->> 'sub','')::uuid,  -- preferir JWT
      auth.uid()                               -- fallback
    ) as auth_user_id
  )
  select
    me.auth_user_id is not null
    and (
      exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        where u.auth_user_id = me.auth_user_id
          and ut.tenant_id = p_tenant
          and ut.ativo = true
          and ut.deleted_at is null
          and ut.papel in ('OWNER','ADMIN','GESTOR')
          and u.deleted_at is null
      )
      or
      exists (
        select 1
        from a.usuario u
        join a.usuario_empresa ue on ue.usuario_id = u.id
        join c.empresa e on e.id = ue.empresa_id
        where u.auth_user_id = me.auth_user_id
          and ue.empresa_id = p_empresa
          and ue.ativo = true
          and ue.deleted_at is null
          and ue.papel in ('ADMIN','COORDENACAO','COMPRAS','TECNICO','FINANCEIRO')
          and e.deleted_at is null
          and e.tenant_id = p_tenant
          and u.deleted_at is null
      )
    )
  from me;
$$;


ALTER FUNCTION "c"."has_comercial_access"("p_tenant" "uuid", "p_empresa" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "c"."has_imobilizado_access"("p_tenant" "uuid" DEFAULT "public"."current_tenant_id"(), "p_empresa" "uuid" DEFAULT "public"."current_empresa_id"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'c', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
  select
    -- ADMIN no TENANT (OWNER/ADMIN)
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ut.tenant_id = p_tenant
        and ut.ativo = true
        and ut.deleted_at is null
        and ut.papel in ('OWNER','ADMIN')
    )
    or
    -- Papéis na EMPRESA (acessam imobilizado)
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.auth_user_id = auth.uid()
        and ue.empresa_id = p_empresa
        and ue.ativo = true
        and ue.deleted_at is null
        and ue.papel in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH')
        and e.deleted_at is null
        and e.tenant_id = p_tenant
    );
$$;


ALTER FUNCTION "c"."has_imobilizado_access"("p_tenant" "uuid", "p_empresa" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "c"."i_ferramenta_gerar_codigo"("p_tenant" "uuid", "p_empresa" "uuid", "p_categoria" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'c', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_prefixo text;
  v_num integer;
begin
  if p_categoria is null then
    raise exception 'categoria_id é obrigatório para gerar código automático';
  end if;

  select prefixo
    into v_prefixo
  from c.i_ferramenta_categoria
  where id = p_categoria
    and tenant_id = p_tenant
    and empresa_id = p_empresa
    and deleted_at is null
    and ativo = true;

  if v_prefixo is null then
    raise exception 'Categoria inválida/inativa para gerar código';
  end if;

  insert into c.i_ferramenta_codigo_seq (tenant_id, empresa_id, categoria_id, proximo_numero)
  values (p_tenant, p_empresa, p_categoria, 1)
  on conflict (tenant_id, empresa_id, categoria_id) do nothing;

  update c.i_ferramenta_codigo_seq
     set proximo_numero = proximo_numero + 1,
         updated_at = now()
   where tenant_id = p_tenant
     and empresa_id = p_empresa
     and categoria_id = p_categoria
   returning (proximo_numero - 1) into v_num;

  return upper(v_prefixo) || '-' || lpad(v_num::text, 6, '0');
end $$;


ALTER FUNCTION "c"."i_ferramenta_gerar_codigo"("p_tenant" "uuid", "p_empresa" "uuid", "p_categoria" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "c"."trg_condicao_pagamento_biu"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.codigo := upper(trim(new.codigo));
  new.nome   := upper(trim(new.nome));
  return new;
end;
$$;


ALTER FUNCTION "c"."trg_condicao_pagamento_biu"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "c"."trg_conjunto_biu"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'c', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
begin
  new.codigo := upper(trim(new.codigo));
  new.nome   := upper(trim(new.nome));
  new.categoria := case when new.categoria is null then null else upper(trim(new.categoria)) end;

  new.codigo_norm := upper(trim(new.codigo));
  new.nome_norm   := upper(trim(new.nome));

  return new;
end;
$$;


ALTER FUNCTION "c"."trg_conjunto_biu"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "c"."trg_conjunto_item_biu"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'c', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_conj c.conjunto%rowtype;
  v_item public.itens%rowtype;
begin
  select * into v_conj
    from c.conjunto cj
   where cj.id = new.conjunto_id
     and cj.deleted_at is null;

  if not found then
    raise exception 'Conjunto não encontrado (conjunto_id=%)', new.conjunto_id;
  end if;

  -- alinha tenant/empresa no detalhe
  new.tenant_id  := v_conj.tenant_id;
  new.empresa_id := v_conj.empresa_id;

  -- valida item no mesmo tenant/empresa
  select * into v_item
    from public.itens i
   where i.id = new.item_id
     and i.tenant_id = new.tenant_id
     and i.empresa_id = new.empresa_id
     and i.ativo = true;

  if not found then
    raise exception 'Item inválido para este tenant/empresa (item_id=%)', new.item_id;
  end if;

  new.unidade := upper(trim(coalesce(new.unidade, v_item.unidade_medida, 'UN')));

  return new;
end;
$$;


ALTER FUNCTION "c"."trg_conjunto_item_biu"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "c"."trg_i_ferramenta_set_codigo"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if tg_op = 'INSERT' then
    new.codigo := c.i_ferramenta_gerar_codigo(new.tenant_id, new.empresa_id, new.categoria_id);
  end if;

  new.codigo := upper(new.codigo);
  new.nome := upper(new.nome);

  return new;
end $$;


ALTER FUNCTION "c"."trg_i_ferramenta_set_codigo"() OWNER TO "postgres";


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
    SET "search_path" TO 'f', 'public', 'a'
    AS $$
declare
  v_id uuid;
  v_chave text;
begin
  -- normaliza chave: remove prefixo NFe se vier como "NFe<44>"
  v_chave := nullif(regexp_replace(coalesce(p_chave_acesso,''), '^NFe', ''), '');

  -- 1) source_nf_entrada_id
  select df.id
    into v_id
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.source_nf_entrada_id = p_nf_entrada_id
    and df.deleted_at is null
  order by df.created_at desc
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  -- 2) chave_acesso (44 dígitos)
  if v_chave is not null then
    select df.id
      into v_id
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and df.chave_acesso = v_chave
      and df.deleted_at is null
    order by df.created_at desc
    limit 1;

    if v_id is not null then
      return v_id;
    end if;
  end if;

  -- 3) fallback conservador: último documento PRODUTO criado nos últimos 10 min
  select df.id
    into v_id
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.natureza = 'PRODUTO'
    and df.deleted_at is null
    and df.created_at >= now() - interval '10 minutes'
  order by df.created_at desc
  limit 1;

  return v_id;
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

  if new.xml_raw is null or nullif(btrim(new.xml_raw),'') is null then
    return new;
  end if;

  -- só quando o XML "chega" (INSERT ou antes estava vazio)
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

  -- se ainda não tem título/AP, cria/ajusta tudo
  if v_titulo_id is null then
    perform 1 from public.fn_fix_nf_entrada_pos_import(new.id);
    return new;
  end if;

  -- se já teve baixa/pagamento, não mexe
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

  -- só corrige quando detecta "placeholder" 1x e o XML diz que é parcelado
  if v_dup_cnt > 1 and v_parc_cnt = 1 and exists (
    select 1
    from f.titulo_parcela p
    join f.titulo t on t.tenant_id=p.tenant_id and t.id=p.titulo_id
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
  if p_titulo_id is null then raise exception 'p_titulo_id obrigatório'; end if;
  if p_conta_bancaria_id is null then raise exception 'p_conta_bancaria_id obrigatório'; end if;
  if p_data_pagamento is null then raise exception 'p_data_pagamento obrigatório'; end if;

  if p_valor_principal is null or p_valor_principal <= 0 then
    raise exception 'Valor principal deve ser > 0';
  end if;

  if coalesce(p_valor_juros,0) < 0 or coalesce(p_valor_multa,0) < 0 or coalesce(p_valor_desconto,0) < 0 then
    raise exception 'Juros/Multa/Desconto não podem ser negativos';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'p_forma_pagamento obrigatório';
  end if;

  select *
    into v_titulo
    from f.titulo t
   where t.id = p_titulo_id
     and t.deleted_at is null;

  if not found then raise exception 'Título não encontrado'; end if;

  if v_titulo.tipo <> 'AR' then
    raise exception 'Somente AR pode receber (tipo=%)', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('APROVADO','AGENDADO','PAGO') then
    raise exception 'Status inválido para recebimento (status=%)', v_titulo.status;
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


CREATE OR REPLACE FUNCTION "m"."fn_orcamento_adicionar_conjunto"("p_orcamento_id" "uuid", "p_conjunto_id" "uuid", "p_quantidade" numeric DEFAULT 1) RETURNS TABLE("conjunto_instancia_id" "uuid", "itens_inseridos" integer, "total_estimado" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'c', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_orc m.orcamento%rowtype;
  v_conj c.conjunto%rowtype;
  v_inst uuid := gen_random_uuid();
  v_count int := 0;
  v_total numeric(15,6) := 0;
  r record;
begin
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade do conjunto deve ser > 0';
  end if;

  select * into v_orc
    from m.orcamento o
   where o.id = p_orcamento_id
     and o.deleted_at is null;

  if not found then
    raise exception 'Orçamento não encontrado (orcamento_id=%)', p_orcamento_id;
  end if;

  if not c.has_comercial_access(v_orc.tenant_id, v_orc.empresa_id) then
    raise exception 'Sem permissão comercial para este tenant/empresa';
  end if;

  select * into v_conj
    from c.conjunto cj
   where cj.id = p_conjunto_id
     and cj.tenant_id = v_orc.tenant_id
     and cj.empresa_id = v_orc.empresa_id
     and cj.ativo = true
     and cj.deleted_at is null;

  if not found then
    raise exception 'Conjunto inválido para este tenant/empresa (conjunto_id=%)', p_conjunto_id;
  end if;

  for r in
    select
      ci.item_id,
      ci.quantidade as qtd_base,
      ci.ordem,
      i.preco_unitario,
      i.tipo
    from c.conjunto_item ci
    join public.itens i on i.id = ci.item_id
   where ci.conjunto_id = v_conj.id
     and ci.deleted_at is null
     and i.tenant_id = v_orc.tenant_id
     and i.empresa_id = v_orc.empresa_id
     and i.ativo = true
     and i.tipo in ('produto','servico')
   order by ci.ordem, ci.created_at
  loop
    insert into m.orcamento_item (
      orcamento_id,
      item_id,
      quantidade,
      valor_unitario,
      desconto_item_percent,
      conjunto_id,
      conjunto_instancia_id,
      conjunto_codigo,
      conjunto_nome
    ) values (
      v_orc.id,
      r.item_id,
      (r.qtd_base * p_quantidade),
      coalesce(r.preco_unitario, 0)::numeric(15,4),
      0,
      v_conj.id,
      v_inst,
      v_conj.codigo,
      v_conj.nome
    );

    v_count := v_count + 1;
    v_total := v_total + (coalesce(r.preco_unitario,0)::numeric(15,6) * (r.qtd_base * p_quantidade));
  end loop;

  conjunto_instancia_id := v_inst;
  itens_inseridos := v_count;
  total_estimado := round(v_total, 2);

  return next;
end;
$$;


ALTER FUNCTION "m"."fn_orcamento_adicionar_conjunto"("p_orcamento_id" "uuid", "p_conjunto_id" "uuid", "p_quantidade" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."fn_orcamento_item_calcular"("p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_item_percent" numeric, "p_acrescimo_cond_percent" numeric, "p_desconto_global_percent" numeric) RETURNS TABLE("valor_total_bruto" numeric, "valor_total" numeric, "valor_unitario_liquido" numeric)
    LANGUAGE "plpgsql"
    AS $$
declare
  v_q numeric := coalesce(p_quantidade,0);
  v_vu numeric := coalesce(p_valor_unitario,0);
  v_di numeric := coalesce(p_desconto_item_percent,0);
  v_ac numeric := coalesce(p_acrescimo_cond_percent,0);
  v_dg numeric := coalesce(p_desconto_global_percent,0);

  v_bruto numeric;
  v_total numeric;
  v_unit_liq numeric;
begin
  -- base * (1-desc_item) * (1+acresc)
  v_bruto := (v_q * v_vu);
  v_bruto := v_bruto * (1 - (v_di/100));
  v_bruto := v_bruto * (1 + (v_ac/100));
  v_bruto := round(v_bruto, 2);

  -- aplica desconto global
  v_total := v_bruto * (1 - (v_dg/100));
  v_total := round(v_total, 2);

  v_unit_liq := case when v_q > 0 then round((v_total / v_q), 4) else 0 end;

  return query select v_bruto, v_total, v_unit_liq;
end;
$$;


ALTER FUNCTION "m"."fn_orcamento_item_calcular"("p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_item_percent" numeric, "p_acrescimo_cond_percent" numeric, "p_desconto_global_percent" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."fn_orcamento_recalcular_totais"("p_orcamento_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_total_bruto numeric(15,2);
  v_total_liq numeric(15,2);
  v_total_desc numeric(15,2);
  v_prod numeric(15,2);
  v_serv numeric(15,2);
  v_frete numeric(15,2);
begin
  select coalesce(o.valor_frete,0)
    into v_frete
  from m.orcamento o
  where o.id = p_orcamento_id;

  select
    coalesce(sum(oi.valor_total_bruto),0)::numeric(15,2),
    coalesce(sum(oi.valor_total),0)::numeric(15,2),
    coalesce(sum(case when oi.item_tipo='PRODUTO' then oi.valor_total else 0 end),0)::numeric(15,2),
    coalesce(sum(case when oi.item_tipo='SERVICO' then oi.valor_total else 0 end),0)::numeric(15,2)
  into v_total_bruto, v_total_liq, v_prod, v_serv
  from m.orcamento_item oi
  where oi.orcamento_id = p_orcamento_id
    and oi.deleted_at is null;

  v_total_desc := (v_total_bruto - v_total_liq);

  update m.orcamento o
     set total_produtos = v_prod,
         total_servicos = v_serv,
         total_bruto = v_total_bruto,
         total_desconto_global = v_total_desc,
         total_liquido = round((v_total_liq + v_frete),2)
   where o.id = p_orcamento_id;
end;
$$;


ALTER FUNCTION "m"."fn_orcamento_recalcular_totais"("p_orcamento_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."fn_orcamento_sync_itens"("p_orcamento_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'public', 'c'
    SET "row_security" TO 'off'
    AS $$
declare
  v_desc_global numeric(7,4);
  v_acresc numeric(7,4);
begin
  select o.desconto_global_percent, o.acrescimo_cond_pag_percent
    into v_desc_global, v_acresc
  from m.orcamento o
  where o.id = p_orcamento_id;

  update m.orcamento_item oi
     set acrescimo_cond_pag_percent = v_acresc,
         desconto_global_percent = v_desc_global,
         valor_total_bruto = calc.valor_total_bruto,
         valor_total = calc.valor_total,
         valor_unitario_liquido = calc.valor_unitario_liquido
    from m.orcamento_item oi2
    join lateral (
      select * from m.fn_orcamento_item_calcular(
        oi2.quantidade,
        oi2.valor_unitario,
        oi2.desconto_item_percent,
        v_acresc,
        v_desc_global
      )
    ) calc on true
   where oi.id = oi2.id
     and oi2.orcamento_id = p_orcamento_id
     and oi2.deleted_at is null;

  perform m.fn_orcamento_recalcular_totais(p_orcamento_id);
end;
$$;


ALTER FUNCTION "m"."fn_orcamento_sync_itens"("p_orcamento_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."orcamento_build_codigo"("p_empresa_id" "uuid", "p_numero" integer, "p_emissao_date" "date") RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'c', 'public'
    AS $$
  select format(
    '%s-%s-%s',
    (select upper(trim(e.codigo)) from c.empresa e where e.id = p_empresa_id),
    lpad(p_numero::text, 3, '0'),
    lpad(((extract(year from p_emissao_date)::int % 1000))::text, 3, '0')
  );
$$;


ALTER FUNCTION "m"."orcamento_build_codigo"("p_empresa_id" "uuid", "p_numero" integer, "p_emissao_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."orcamento_build_codigo"("p_empresa_id" "uuid", "p_numero" integer, "p_versao" integer DEFAULT 1) RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'c', 'public'
    AS $$
  select format(
    '%s-%s-%s',
    lpad((select e.codigo from c.empresa e where e.id = p_empresa_id), 3, '0'),
    lpad(p_numero::text, 5, '0'),
    lpad(coalesce(p_versao,1)::text, 2, '0')
  );
$$;


ALTER FUNCTION "m"."orcamento_build_codigo"("p_empresa_id" "uuid", "p_numero" integer, "p_versao" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."orcamento_next_numero"("p_tenant" "uuid", "p_empresa" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_num integer;
begin
  insert into m.orcamento_seq (tenant_id, empresa_id, proximo_numero)
  values (p_tenant, p_empresa, 1)
  on conflict (tenant_id, empresa_id) do nothing;

  select proximo_numero
    into v_num
  from m.orcamento_seq
  where tenant_id = p_tenant
    and empresa_id = p_empresa
  for update;

  update m.orcamento_seq
     set proximo_numero = v_num + 1,
         updated_at = now()
   where tenant_id = p_tenant
     and empresa_id = p_empresa;

  return v_num;
end;
$$;


ALTER FUNCTION "m"."orcamento_next_numero"("p_tenant" "uuid", "p_empresa" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."trg_orcamento_au"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'public'
    SET "row_security" TO 'off'
    AS $$
begin
  if (
    new.desconto_global_percent is distinct from old.desconto_global_percent
    or new.condicao_pagamento_id is distinct from old.condicao_pagamento_id
    or new.valor_frete is distinct from old.valor_frete
  ) then
    perform m.fn_orcamento_sync_itens(new.id);
  end if;

  return new;
end;
$$;


ALTER FUNCTION "m"."trg_orcamento_au"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."trg_orcamento_biu"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'public', 'c', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_cfg a.config_orcamento%rowtype;
  v_acresc numeric(7,4);
begin
  perform a.ensure_config_orcamento(new.tenant_id, new.empresa_id);

  select * into v_cfg
  from a.config_orcamento
  where tenant_id = new.tenant_id
    and empresa_id = new.empresa_id
    and deleted_at is null
  limit 1;

  if new.desconto_global_percent > v_cfg.desconto_max_percent then
    raise exception 'Desconto global (%) excede o máximo configurado (%)',
      round(new.desconto_global_percent,2), round(v_cfg.desconto_max_percent,2);
  end if;

  new.titulo := upper(trim(new.titulo));

  if not exists (
    select 1 from public.clientes c1
    where c1.id = new.cliente_id
      and c1.tenant_id = new.tenant_id
      and c1.empresa_id = new.empresa_id
  ) then
    raise exception 'Cliente inválido para este tenant/empresa (cliente_id=%)', new.cliente_id;
  end if;

  if not exists (
    select 1 from a.usuario u
    where u.id = new.vendedor_usuario_id
      and u.deleted_at is null
      and u.ativo = true
  ) then
    raise exception 'Vendedor inválido (vendedor_usuario_id=%)', new.vendedor_usuario_id;
  end if;

  v_acresc := 0;
  if new.condicao_pagamento_id is not null then
    select cp.acrescimo_percent
      into v_acresc
    from c.condicao_pagamento cp
    where cp.id = new.condicao_pagamento_id
      and cp.tenant_id = new.tenant_id
      and cp.empresa_id = new.empresa_id
      and cp.deleted_at is null;

    if v_acresc is null then
      raise exception 'Condição de pagamento inválida para este tenant/empresa (id=%)', new.condicao_pagamento_id;
    end if;
  end if;

  new.acrescimo_cond_pag_percent := coalesce(v_acresc,0);

  -- numeração/código apenas no INSERT
  if tg_op = 'INSERT' then
    if new.numero is null or new.numero < 1 then
      new.numero := m.orcamento_next_numero(new.tenant_id, new.empresa_id);
    end if;

    if new.versao is null or new.versao < 1 then
      new.versao := 1;
    end if;

    -- NOVO PADRÃO
    new.codigo := m.orcamento_build_codigo(new.empresa_id, new.numero, new.emissao_date);
  end if;

  return new;
end;
$$;


ALTER FUNCTION "m"."trg_orcamento_biu"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."trg_orcamento_item_aiud"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'public'
    SET "row_security" TO 'off'
    AS $$
begin
  if tg_op = 'DELETE' then
    perform m.fn_orcamento_recalcular_totais(old.orcamento_id);
    return old;
  else
    perform m.fn_orcamento_recalcular_totais(new.orcamento_id);
    return new;
  end if;
end;
$$;


ALTER FUNCTION "m"."trg_orcamento_item_aiud"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "m"."trg_orcamento_item_biu"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'm', 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
declare
  v_orc m.orcamento%rowtype;
  v_item public.itens%rowtype;
  v_tipo text;
  v_calc record;
begin
  -- PROTEÇÃO: não permitir mover item de orçamento via UPDATE
  if tg_op = 'UPDATE' and new.orcamento_id is distinct from old.orcamento_id then
    raise exception 'Não é permitido alterar orcamento_id do item.';
  end if;

  -- SOFT DELETE: não recalcula snapshots/valores, só mantém tenant/empresa e segue
  if tg_op = 'UPDATE' and new.deleted_at is not null and old.deleted_at is null then
    new.tenant_id := old.tenant_id;
    new.empresa_id := old.empresa_id;
    return new;
  end if;

  -- carrega orçamento pai
  select * into v_orc
  from m.orcamento o
  where o.id = new.orcamento_id
    and o.deleted_at is null;

  if not found then
    raise exception 'Orçamento não encontrado (orcamento_id=%)', new.orcamento_id;
  end if;

  -- garante tenant/empresa alinhados
  new.tenant_id := v_orc.tenant_id;
  new.empresa_id := v_orc.empresa_id;

  -- seq automática  (IMPORTANTE: SEM filtrar deleted_at)
  if new.seq is null or new.seq < 1 then
    select coalesce(max(seq),0) + 1
      into new.seq
    from m.orcamento_item
    where orcamento_id = new.orcamento_id;
  end if;

  -- carrega item (mesmo tenant/empresa)
  select * into v_item
  from public.itens i
  where i.id = new.item_id
    and i.tenant_id = new.tenant_id
    and i.empresa_id = new.empresa_id
    and i.ativo = true;

  if not found then
    raise exception 'Item inválido para este tenant/empresa (item_id=%)', new.item_id;
  end if;

  -- permite apenas produto/serviço
  v_tipo := lower(v_item.tipo);
  if v_tipo = 'produto' then
    new.item_tipo := 'PRODUTO';
  elsif v_tipo = 'servico' then
    new.item_tipo := 'SERVICO';
  else
    raise exception 'Item do tipo "%" não é permitido em Orçamento (somente produto/servico)', v_item.tipo;
  end if;

  -- snapshots
  new.item_nome := upper(trim(v_item.nome));
  new.unidade := upper(trim(coalesce(v_item.unidade_medida,'UN')));

  -- snapshots do cabeçalho
  new.acrescimo_cond_pag_percent := v_orc.acrescimo_cond_pag_percent;
  new.desconto_global_percent := v_orc.desconto_global_percent;

  -- calcula valores
  select * into v_calc
  from m.fn_orcamento_item_calcular(
    new.quantidade,
    new.valor_unitario,
    new.desconto_item_percent,
    new.acrescimo_cond_pag_percent,
    new.desconto_global_percent
  );

  new.valor_total_bruto := v_calc.valor_total_bruto;
  new.valor_total := v_calc.valor_total;
  new.valor_unitario_liquido := v_calc.valor_unitario_liquido;

  return new;
end;
$$;


ALTER FUNCTION "m"."trg_orcamento_item_biu"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."a_is_empresa_member"("p_empresa_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
  select exists (
    select 1
    from a.usuario_empresa ue
    join a.usuario u on u.id = ue.usuario_id
    where u.auth_user_id = auth.uid()
      and ue.empresa_id = p_empresa_id
      and ue.deleted_at is null
      and ue.ativo = true
  );
$$;


ALTER FUNCTION "public"."a_is_empresa_member"("p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."a_is_tenant_admin"("p_tenant_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
  select public.a_is_tenant_role(p_tenant_id, array['admin']);
$$;


ALTER FUNCTION "public"."a_is_tenant_admin"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."a_is_tenant_role"("p_tenant_id" "uuid", "p_roles" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
  select exists (
    select 1
    from a.usuario_tenant ut
    join a.usuario u on u.id = ut.usuario_id
    where u.auth_user_id = auth.uid()
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
      and ut.ativo = true
      and a.fn_map_papel_tenant_to_role(ut.papel) = any (p_roles)
  );
$$;


ALTER FUNCTION "public"."a_is_tenant_role"("p_tenant_id" "uuid", "p_roles" "text"[]) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."os_itens" (
    "id" integer NOT NULL,
    "os_id" integer NOT NULL,
    "item_id" integer NOT NULL,
    "quantidade" numeric(14,3) DEFAULT 0 NOT NULL,
    "valor_unitario" numeric(10,2) NOT NULL,
    "valor_total" numeric(12,2) NOT NULL,
    "desconto_percentual" numeric(5,2) DEFAULT 0,
    "desconto_valor" numeric(10,2) DEFAULT 0,
    "baixa_estoque" boolean DEFAULT false,
    "observacoes" "text",
    "criado_em" timestamp without time zone DEFAULT "now"(),
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    CONSTRAINT "chk_os_itens_quantidade_pos" CHECK (("quantidade" > (0)::numeric))
);


ALTER TABLE "public"."os_itens" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric DEFAULT 0, "p_desconto_valor" numeric DEFAULT 0, "p_baixa_estoque" boolean DEFAULT true, "p_realizado_por" "text" DEFAULT NULL::"text", "p_motivo" "text" DEFAULT NULL::"text") RETURNS "public"."os_itens"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.add_os_item_baixa_imediata(
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    p_desconto_percentual,
    p_desconto_valor,
    p_baixa_estoque,
    p_realizado_por,
    p_motivo,
    null::uuid
  );
$$;


ALTER FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric DEFAULT 0, "p_desconto_valor" numeric DEFAULT 0, "p_baixa_estoque" boolean DEFAULT true, "p_realizado_por" "text" DEFAULT NULL::"text", "p_motivo" "text" DEFAULT NULL::"text", "p_empresa_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."os_itens"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_item public.itens;
  v_total numeric;
  v_row public.os_itens;
  v_tenant uuid;
  v_realizado_por text;
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.can('os_rpcs','execute') then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = v_tenant
  ) then
    raise exception 'OS invalida ou fora do tenant atual';
  end if;

  select *
    into v_item
  from public.itens
  where id = p_item_id
    and tenant_id = v_tenant
    and ativo = true;

  if not found then
    raise exception 'Item invalido/inativo ou fora do tenant atual';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade invalida';
  end if;

  v_total := (p_quantidade * p_valor_unitario) - coalesce(p_desconto_valor, 0);

  insert into public.os_itens (
    tenant_id,
    os_id,
    item_id,
    quantidade,
    valor_unitario,
    valor_total,
    desconto_percentual,
    desconto_valor,
    baixa_estoque,
    criado_em
  )
  values (
    v_tenant,
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    v_total,
    coalesce(p_desconto_percentual, 0),
    coalesce(p_desconto_valor, 0),
    coalesce(p_baixa_estoque, true),
    now()
  )
  returning * into v_row;

  if coalesce(p_baixa_estoque, true)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque','write') or public.can('os_rpcs','execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      p_item_id,
      'saida',
      p_quantidade,
      coalesce(p_motivo, 'Baixa imediata via OS ' || p_os_id),
      v_realizado_por,
      now(),
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = p_os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = p_os_id
    and os.tenant_id = v_tenant;

  return v_row;
end;
$$;


ALTER FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_can_manage_users"("p_tenant_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut
      on ut.usuario_id = u.id
    where u.auth_user_id = auth.uid()
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
      and ut.ativo = true
      and (
        ut.papel = 'OWNER'
        or exists (
          select 1
          from public.role_permissions rp
          where rp.role = a.fn_map_papel_tenant_to_role(ut.papel)
            and rp.permission in ('admin.users.manage', 'admin.manage_users')
        )
      )
  );
$$;


ALTER FUNCTION "public"."admin_can_manage_users"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_finalize_invited_user"("p_tenant_id" "uuid", "p_auth_user_id" "uuid", "p_email" "text", "p_nome" "text", "p_telefone" "text", "p_tenant_papel" "text", "p_empresa_vinculos" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_item jsonb;
  v_empresa_id uuid;
  v_empresa_papel text;
  v_empresa_ativo boolean;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  -- valida papel do tenant
  v_tenant_papel := upper(trim(coalesce(p_tenant_papel,'GESTOR')));
  if v_tenant_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_tenant_papel;
  end if;

  -- upsert usuario (por auth_user_id)
  insert into a.usuario (
    id, auth_user_id, nome, email, telefone, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(),
    p_auth_user_id,
    nullif(trim(coalesce(p_nome,'')), ''),
    lower(trim(coalesce(p_email,''))),
    nullif(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), ''),
    true,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (auth_user_id)
  do update set
    nome = excluded.nome,
    email = excluded.email,
    telefone = excluded.telefone,
    ativo = true,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null
  returning id into v_usuario_id;

  -- tenant role
  insert into a.usuario_tenant (
    id, usuario_id, tenant_id, papel, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), v_usuario_id, p_tenant_id, v_tenant_papel, true,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, tenant_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = true,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;

  -- empresa vínculos (opcional)
  if p_empresa_vinculos is not null and jsonb_typeof(p_empresa_vinculos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_empresa_vinculos)
    loop
      v_empresa_id := (v_item->>'empresa_id')::uuid;
      v_empresa_papel := upper(trim(coalesce(v_item->>'papel','TECNICO')));
      v_empresa_ativo := coalesce((v_item->>'ativo')::boolean, true);

      if v_empresa_papel not in (
        'ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV'
      ) then
        raise exception 'invalid_empresa_role: %', v_empresa_papel;
      end if;

      perform 1 from public.empresas e where e.id = v_empresa_id and e.tenant_id = p_tenant_id;
      if not found then
        raise exception 'empresa_not_in_tenant';
      end if;

      insert into a.usuario_empresa (
        id, usuario_id, empresa_id, papel, ativo,
        permissoes_extra, permissoes_negadas,
        created_at, updated_at, created_by, updated_by, deleted_at
      )
      values (
        gen_random_uuid(), v_usuario_id, v_empresa_id, v_empresa_papel, v_empresa_ativo,
        null, null,
        now(), now(), auth.uid(), auth.uid(), null
      )
      on conflict (usuario_id, empresa_id) where deleted_at is null
      do update set
        papel = excluded.papel,
        ativo = excluded.ativo,
        updated_at = now(),
        updated_by = auth.uid(),
        deleted_at = null;
    end loop;
  end if;

  return v_usuario_id;
end;
$$;


ALTER FUNCTION "public"."admin_finalize_invited_user"("p_tenant_id" "uuid", "p_auth_user_id" "uuid", "p_email" "text", "p_nome" "text", "p_telefone" "text", "p_tenant_papel" "text", "p_empresa_vinculos" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_users"("p_tenant_id" "uuid") RETURNS TABLE("usuario_id" "uuid", "auth_user_id" "uuid", "nome" "text", "email" "text", "telefone" "text", "usuario_ativo" boolean, "tenant_papel" "text", "tenant_ativo" boolean, "tenant_deleted_at" timestamp with time zone, "empresas" "jsonb", "usuario_created_at" timestamp with time zone, "usuario_updated_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
  -- autorização
  select
    u.id as usuario_id,
    u.auth_user_id,
    u.nome,
    u.email,
    u.telefone,
    u.ativo as usuario_ativo,
    ut.papel as tenant_papel,
    ut.ativo as tenant_ativo,
    ut.deleted_at as tenant_deleted_at,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', ue.id,
            'empresa_id', ue.empresa_id,
            'empresa_nome', coalesce(e.nome_fantasia, e.razao_social, 'Empresa'),
            'papel', ue.papel,
            'ativo', ue.ativo,
            'deleted_at', ue.deleted_at
          )
          order by coalesce(e.nome_fantasia, e.razao_social, 'Empresa')
        )
        from a.usuario_empresa ue
        join public.empresas e on e.id = ue.empresa_id
        where ue.usuario_id = u.id
          and ue.deleted_at is null
          and e.tenant_id = p_tenant_id
      ),
      '[]'::jsonb
    ) as empresas,
    u.created_at as usuario_created_at,
    u.updated_at as usuario_updated_at
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  where ut.tenant_id = p_tenant_id
    and ut.deleted_at is null
    and public.admin_can_manage_users(p_tenant_id) = true
  order by coalesce(u.nome, u.email), u.created_at desc;
$$;


ALTER FUNCTION "public"."admin_list_users"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_merge_fornecedores"("p_tenant_id" "uuid", "p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint, "p_soft_delete" boolean DEFAULT true) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
declare
  r record;
  v_sql text;
begin
  if p_keep_fornecedor_id = p_merge_fornecedor_id then
    raise exception 'keep e merge não podem ser iguais';
  end if;

  -- garante que ambos são do mesmo tenant
  if not exists (
    select 1 from public.fornecedores
    where id = p_keep_fornecedor_id and tenant_id = p_tenant_id and deleted_at is null
  ) then
    raise exception 'Fornecedor KEEP não encontrado para este tenant';
  end if;

  if not exists (
    select 1 from public.fornecedores
    where id = p_merge_fornecedor_id and tenant_id = p_tenant_id and deleted_at is null
  ) then
    raise exception 'Fornecedor MERGE não encontrado para este tenant';
  end if;

  -- atualiza todas as tabelas que têm FK -> public.fornecedores(id)
  for r in
    select
      n.nspname as schema_name,
      c.relname as table_name,
      a.attname as column_name
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_class cref on cref.oid = con.confrelid
    join pg_namespace nref on nref.oid = cref.relnamespace
    join unnest(con.conkey) with ordinality as ck(attnum, ord) on true
    join pg_attribute a on a.attrelid = c.oid and a.attnum = ck.attnum
    where con.contype = 'f'
      and nref.nspname = 'public'
      and cref.relname = 'fornecedores'
      and a.attname in ('fornecedor_id') -- padrão do teu modelo
  loop
    v_sql := format(
      'update %I.%I set %I = $1 where %I = $2',
      r.schema_name, r.table_name, r.column_name, r.column_name
    );
    execute v_sql using p_keep_fornecedor_id, p_merge_fornecedor_id;
  end loop;

  -- por fim, inativa o duplicado
  if p_soft_delete then
    update public.fornecedores
      set deleted_at = now(),
          updated_at = now()
    where id = p_merge_fornecedor_id;
  else
    delete from public.fornecedores
    where id = p_merge_fornecedor_id;
  end if;
end;
$_$;


ALTER FUNCTION "public"."admin_merge_fornecedores"("p_tenant_id" "uuid", "p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint, "p_soft_delete" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_user_empresa"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
declare
  v_empresa_tenant uuid;
  v_papel text;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  select e.tenant_id into v_empresa_tenant
  from public.empresas e
  where e.id = p_empresa_id;

  if v_empresa_tenant is null then
    raise exception 'empresa_not_found';
  end if;

  if v_empresa_tenant <> p_tenant_id then
    raise exception 'empresa_not_in_tenant';
  end if;

  v_papel := upper(trim(coalesce(p_papel, 'TECNICO')));

  -- valida domínio da empresa
  if v_papel not in (
    'ADMIN',
    'FINANCEIRO',
    'COORDENACAO',
    'COMPRAS',
    'ALMOXARIFADO',
    'TECNICO',
    'APONTAMENTO_RH',
    'PAINEL_TV'
  ) then
    raise exception 'invalid_empresa_role: %', v_papel;
  end if;

  insert into a.usuario_empresa (
    id, usuario_id, empresa_id, papel, ativo,
    permissoes_extra, permissoes_negadas,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), p_usuario_id, p_empresa_id, v_papel, coalesce(p_ativo,true),
    null, null,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, empresa_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = excluded.ativo,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;
end;
$$;


ALTER FUNCTION "public"."admin_set_user_empresa"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_user_tenant_role"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
declare
  v_papel text;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  v_papel := upper(trim(coalesce(p_papel, 'GESTOR')));

  -- valida domínio do tenant
  if v_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_papel;
  end if;

  insert into a.usuario_tenant (
    id, usuario_id, tenant_id, papel, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), p_usuario_id, p_tenant_id, v_papel, coalesce(p_ativo, true),
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, tenant_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = excluded.ativo,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;
end;
$$;


ALTER FUNCTION "public"."admin_set_user_tenant_role"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_user"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_nome" "text", "p_telefone" "text", "p_ativo" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  update a.usuario
     set nome = nullif(trim(p_nome), ''),
         telefone = nullif(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), ''),
         ativo = coalesce(p_ativo, true),
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_usuario_id
     and deleted_at is null;

  if not found then
    raise exception 'user_not_found';
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_update_user"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_nome" "text", "p_telefone" "text", "p_ativo" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_fiscal_regras_em_lote"("p_somente_sem_registro" boolean DEFAULT true) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_count int := 0;
  r record;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  if not public.has_permission('fiscal.editar') then
    raise exception 'Sem permissão: fiscal.editar';
  end if;

  for r in
    select
      i.id as item_id,
      fi.ncm as ncm_atual,
      fi.cfop_padrao as cfop_atual,
      fi.cst_icms as cst_icms_atual,
      fi.cst_pis as cst_pis_atual,
      fi.cst_cofins as cst_cofins_atual,
      fi.origem as origem_atual,
      i.tipo as tipo_item
    from public.itens i
    left join public.fiscal_itens fi
      on fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = i.id
    where coalesce(i.ativo, true) = true
      and (
        p_somente_sem_registro = false
        or fi.item_id is null
      )
  loop
    perform public.apply_fiscal_to_item(
      r.item_id,
      r.ncm_atual,
      r.cfop_atual,
      r.cst_icms_atual,
      r.cst_pis_atual,
      r.cst_cofins_atual,
      r.origem_atual,
      r.tipo_item
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;


ALTER FUNCTION "public"."apply_fiscal_regras_em_lote"("p_somente_sem_registro" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_fiscal_regras_em_lote_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_somente_sem_registro" boolean DEFAULT true) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_count int := 0;
  r record;
begin
  if session_user not in ('postgres', 'service_role') then
    raise exception 'Função admin: execução não permitida para %', session_user;
  end if;

  for r in
    select
      i.id as item_id,
      fi.ncm as ncm_atual,
      fi.cfop_padrao as cfop_atual,
      fi.cst_icms as cst_icms_atual,
      fi.cst_pis as cst_pis_atual,
      fi.cst_cofins as cst_cofins_atual,
      fi.origem as origem_atual,
      i.tipo as tipo_item
    from public.itens i
    left join public.fiscal_itens fi
      on fi.tenant_id = p_tenant
     and fi.empresa_id = p_empresa
     and fi.item_id = i.id
    where coalesce(i.ativo, true) = true
      and (p_somente_sem_registro = false or fi.item_id is null)
  loop
    perform public.apply_fiscal_to_item_admin(
      p_tenant, p_empresa,
      r.item_id,
      r.ncm_atual,
      r.cfop_atual,
      r.cst_icms_atual,
      r.cst_pis_atual,
      r.cst_cofins_atual,
      r.origem_atual,
      r.tipo_item
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;


ALTER FUNCTION "public"."apply_fiscal_regras_em_lote_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_somente_sem_registro" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_fiscal_to_item"("p_item_id" integer, "p_ncm" "text" DEFAULT NULL::"text", "p_cfop" "text" DEFAULT NULL::"text", "p_cst_icms" "text" DEFAULT NULL::"text", "p_cst_pis" "text" DEFAULT NULL::"text", "p_cst_cofins" "text" DEFAULT NULL::"text", "p_origem" smallint DEFAULT NULL::smallint, "p_tipo_item" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_regra_id uuid;
  v_regra public.fiscal_regras;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  if not public.has_permission('fiscal.editar') then
    raise exception 'Sem permissão: fiscal.editar';
  end if;

  v_regra_id := public.pick_fiscal_regra(
    p_ncm, p_cfop, p_cst_icms, p_cst_pis, p_cst_cofins, p_origem, p_tipo_item
  );

  if v_regra_id is null then
    raise exception 'Nenhuma regra fiscal encontrada para o contexto informado';
  end if;

  select * into v_regra
  from public.fiscal_regras
  where id = v_regra_id;

  insert into public.fiscal_itens (
    tenant_id, empresa_id, item_id,
    ncm, origem, cfop_padrao,
    cst_icms, cst_pis, cst_cofins,
    aliq_icms, aliq_pis, aliq_cofins,
    credita_icms, credita_pis, credita_cofins,
    atualizado_em
  )
  values (
    v_tenant, v_empresa, p_item_id,
    p_ncm, v_regra.origem, v_regra.cfop,
    v_regra.cst_icms, v_regra.cst_pis, v_regra.cst_cofins,
    v_regra.aliq_icms, v_regra.aliq_pis, v_regra.aliq_cofins,
    v_regra.credita_icms, v_regra.credita_pis, v_regra.credita_cofins,
    now()
  )
  on conflict (tenant_id, empresa_id, item_id) do update set
    ncm = excluded.ncm,
    origem = excluded.origem,
    cfop_padrao = excluded.cfop_padrao,
    cst_icms = excluded.cst_icms,
    cst_pis = excluded.cst_pis,
    cst_cofins = excluded.cst_cofins,
    aliq_icms = excluded.aliq_icms,
    aliq_pis = excluded.aliq_pis,
    aliq_cofins = excluded.aliq_cofins,
    credita_icms = excluded.credita_icms,
    credita_pis = excluded.credita_pis,
    credita_cofins = excluded.credita_cofins,
    atualizado_em = now();

  -- garante consistência (não deixa crédito true com CST null)
  update public.fiscal_itens fi
     set credita_icms = false
   where fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = p_item_id
     and fi.credita_icms = true
     and fi.cst_icms is null;

  update public.fiscal_itens fi
     set credita_pis = false
   where fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = p_item_id
     and fi.credita_pis = true
     and fi.cst_pis is null;

  update public.fiscal_itens fi
     set credita_cofins = false
   where fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = p_item_id
     and fi.credita_cofins = true
     and fi.cst_cofins is null;

end;
$$;


ALTER FUNCTION "public"."apply_fiscal_to_item"("p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_fiscal_to_item_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_item_id" integer, "p_ncm" "text" DEFAULT NULL::"text", "p_cfop" "text" DEFAULT NULL::"text", "p_cst_icms" "text" DEFAULT NULL::"text", "p_cst_pis" "text" DEFAULT NULL::"text", "p_cst_cofins" "text" DEFAULT NULL::"text", "p_origem" smallint DEFAULT NULL::smallint, "p_tipo_item" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_regra_id uuid;
  v_regra public.fiscal_regras;
begin
  if session_user not in ('postgres', 'service_role') then
    raise exception 'Função admin: execução não permitida para %', session_user;
  end if;

  v_regra_id := public.pick_fiscal_regra_admin(
    p_tenant, p_empresa,
    p_ncm, p_cfop, p_cst_icms, p_cst_pis, p_cst_cofins, p_origem, p_tipo_item
  );

  if v_regra_id is null then
    raise exception 'Nenhuma regra fiscal encontrada para o item_id=%', p_item_id;
  end if;

  select * into v_regra
  from public.fiscal_regras
  where id = v_regra_id;

  insert into public.fiscal_itens (
    tenant_id, empresa_id, item_id,
    ncm, origem, cfop_padrao,
    cst_icms, cst_pis, cst_cofins,
    aliq_icms, aliq_pis, aliq_cofins,
    credita_icms, credita_pis, credita_cofins,
    ipi_entra_no_custo,
    atualizado_em
  )
  values (
    p_tenant, p_empresa, p_item_id,
    p_ncm, v_regra.origem, v_regra.cfop,
    v_regra.cst_icms, v_regra.cst_pis, v_regra.cst_cofins,
    v_regra.aliq_icms, v_regra.aliq_pis, v_regra.aliq_cofins,
    v_regra.credita_icms, v_regra.credita_pis, v_regra.credita_cofins,
    false,
    now()
  )
  on conflict (tenant_id, empresa_id, item_id) do update set
    ncm = excluded.ncm,
    origem = excluded.origem,
    cfop_padrao = excluded.cfop_padrao,
    cst_icms = excluded.cst_icms,
    cst_pis = excluded.cst_pis,
    cst_cofins = excluded.cst_cofins,
    aliq_icms = excluded.aliq_icms,
    aliq_pis = excluded.aliq_pis,
    aliq_cofins = excluded.aliq_cofins,
    credita_icms = excluded.credita_icms,
    credita_pis = excluded.credita_pis,
    credita_cofins = excluded.credita_cofins,
    ipi_entra_no_custo = excluded.ipi_entra_no_custo,
    atualizado_em = now();
end;
$$;


ALTER FUNCTION "public"."apply_fiscal_to_item_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_movimentacao_estoque"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."apply_movimentacao_estoque"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid;
  v_uid uuid;
  v_email text;
  v_pk text;
begin
  v_uid := auth.uid();
  v_email := coalesce(auth.jwt() ->> 'email', null);

  -- tenta capturar tenant_id se existir na linha
  v_tenant := null;
  begin
    if tg_op in ('INSERT','UPDATE') then
      v_tenant := (to_jsonb(new) ->> 'tenant_id')::uuid;
    else
      v_tenant := (to_jsonb(old) ->> 'tenant_id')::uuid;
    end if;
  exception when others then
    v_tenant := null;
  end;

  -- tenta capturar PK "id" se existir
  v_pk := null;
  begin
    if tg_op in ('INSERT','UPDATE') then
      v_pk := to_jsonb(new) ->> 'id';
    else
      v_pk := to_jsonb(old) ->> 'id';
    end if;
  exception when others then
    v_pk := null;
  end;

  insert into public.audit_log(
    tenant_id, table_name, action, row_pk,
    old_data, new_data,
    actor_user_id, actor_email,
    request_id
  )
  values (
    v_tenant,
    tg_table_name,
    tg_op,
    v_pk,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end,
    v_uid,
    v_email,
    current_setting('request.jwt.claim.jti', true)
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;


ALTER FUNCTION "public"."audit_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_assign_empresa_segau"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  -- Pegar tenant padrão
  select id into v_tenant_id
  from public.tenants
  where ativo = true
  order by created_at asc nulls last
  limit 1;

  if v_tenant_id is null then
    return NEW;
  end if;

  -- Pegar empresa Elétrica Segau
  select id into v_empresa_id
  from public.empresas
  where tenant_id = v_tenant_id
    and (
      razao_social ilike '%segau%'
      or nome_fantasia ilike '%segau%'
    )
    and ativo = true
  limit 1;

  if v_empresa_id is null then
    return NEW;
  end if;

  -- Criar tenant membership
  insert into public.tenant_memberships (
    tenant_id,
    user_id,
    status,
    role
  ) values (
    v_tenant_id,
    NEW.id,
    'active',
    'admin'
  )
  on conflict do nothing;

  -- Criar empresa membership
  insert into public.empresa_memberships (
    tenant_id,
    empresa_id,
    user_id,
    role,
    status
  ) values (
    v_tenant_id,
    v_empresa_id,
    NEW.id,
    'user',
    'active'
  )
  on conflict do nothing;

  -- Definir contexto padrão
  insert into public.user_empresa_context (
    user_id,
    tenant_id,
    empresa_id
  ) values (
    NEW.id,
    v_tenant_id,
    v_empresa_id
  )
  on conflict (user_id, tenant_id) do update
    set empresa_id = excluded.empresa_id,
        updated_at = now();

  return NEW;
end;
$$;


ALTER FUNCTION "public"."auto_assign_empresa_segau"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_set_context_on_login"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';  -- Tenant fixo
  v_empresa_id uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690'; -- Elétrica Segau
begin
  -- Setar tenant
  perform set_config('app.current_tenant_id', v_tenant_id::text, false);
  
  -- Setar empresa
  perform set_config('app.current_empresa_id', v_empresa_id::text, false);
  
  return NEW;
end;
$$;


ALTER FUNCTION "public"."auto_set_context_on_login"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."block_movimentacoes_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  raise exception 'Movimentações são imutáveis. Use estorno.';
end $$;


ALTER FUNCTION "public"."block_movimentacoes_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_hh_lancamento"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_preco NUMERIC(10,2);
BEGIN
  -- Calcular horas trabalhadas (hora_saida - hora_entrada)
  NEW.horas_trabalhadas := EXTRACT(EPOCH FROM (NEW.hora_saida - NEW.hora_entrada)) / 3600.0;
  
  -- Se horas negativas (passou meia-noite), adicionar 24h
  IF NEW.horas_trabalhadas < 0 THEN
    NEW.horas_trabalhadas := NEW.horas_trabalhadas + 24;
  END IF;
  
  -- Se valor_hora nÃ£o foi fornecido ou Ã© 0, buscar de hh_tabela_precos
  -- Caso contrÃ¡rio, respeitar o valor enviado (vem de cliente_hh_servicos)
  IF NEW.valor_hora IS NULL OR NEW.valor_hora = 0 THEN
    SELECT 
      CASE 
        WHEN NEW.percentual_aplicado = 50 THEN preco_50
        WHEN NEW.percentual_aplicado = 100 THEN preco_100
        ELSE preco_base
      END
    INTO v_preco
    FROM public.hh_tabela_precos
    WHERE id = NEW.hh_tipo_id;
    
    NEW.valor_hora := COALESCE(v_preco, 0);
  END IF;
  
  NEW.valor_total := NEW.horas_trabalhadas * NEW.valor_hora;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."calculate_hh_lancamento"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can"("p_resource" "text", "p_action" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a', 'c'
    AS $$
  select public.can(p_resource, p_action, public.current_tenant_id());
$$;


ALTER FUNCTION "public"."can"("p_resource" "text", "p_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a', 'c'
    AS $$
declare
  v_auth_user_id uuid;
  v_usuario_id uuid;
  v_papel_tenant text;
  v_papel_empresa text;
  v_empresa_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    return false;
  end if;

  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = v_auth_user_id
    and u.ativo = true
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return false;
  end if;

  select ut.papel
    into v_papel_tenant
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  order by ut.updated_at desc nulls last, ut.created_at desc nulls last
  limit 1;

  if v_papel_tenant is null then
    return false;
  end if;

  -- ADMIN/OWNER do tenant => sempre libera
  if v_papel_tenant in ('ADMIN','OWNER') then
    return true;
  end if;

  -- Para não-admin, verifica permissões específicas do papel empresa
  v_empresa_id := public.current_empresa_id();

  if v_empresa_id is not null then
    select ue.papel
      into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

  -- ✅ XML Import (AGORA INCLUI FINANCEIRO e COORDENACAO)
  if p_resource = 'xml_import' and p_action = 'execute' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  -- ✅ NF Entrada Import (AGORA INCLUI FINANCEIRO e COORDENACAO)
  if p_resource = 'nf_entrada' and p_action = 'import' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  -- Financeiro (Contas a Pagar)
  if p_resource = 'financeiro' and p_action in ('write', 'config') then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  -- Estoque
  if p_resource = 'estoque' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'estoque' and p_action = 'read' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  -- MVP: não-admin -> nega admin.manage_users
  if p_resource = 'admin' and p_action = 'manage_users' then
    return false;
  end if;

  return false;
end;
$$;


ALTER FUNCTION "public"."can"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can__legacy_40734"("p_resource" "text", "p_action" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    SET "row_security" TO 'off'
    AS $$
  select
    (
      p_resource = 'os'
      and p_action in ('read','write')
      and public.current_tenant_id() is not null
      and public.current_empresa_id() is not null

      -- garante que a empresa atual é do tenant atual
      and exists (
        select 1
        from public.empresas e
        where e.id = public.current_empresa_id()
          and e.tenant_id = public.current_tenant_id()
          and e.ativo = true
      )

      -- papel na empresa (a.usuario_empresa) liberando OS
      and exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        join a.usuario_empresa ue on ue.usuario_id = u.id
        where u.auth_user_id = auth.uid()
          and u.ativo = true
          and u.deleted_at is null
          and ut.tenant_id = public.current_tenant_id()
          and ut.ativo = true
          and ut.deleted_at is null
          and ue.empresa_id = public.current_empresa_id()
          and ue.ativo = true
          and ue.deleted_at is null
          and upper(ue.papel) in ('ADMIN','COORDENACAO','APONTAMENTO_RH')
      )
    )
    or
    exists (
      select 1
      from public.tenant_memberships tm
      join public.membership_roles mr on mr.membership_id = tm.id
      join public.roles r on r.id = mr.role_id
      join public.role_access_rules ar on ar.role_id = r.id
      where tm.user_id = auth.uid()
        and tm.tenant_id = public.current_tenant_id()
        and tm.status in ('active', 'ativo')
        and (r.tenant_id is null or r.tenant_id = tm.tenant_id)
        and ar.resource = p_resource
        and ar.action = p_action
    );
$$;


ALTER FUNCTION "public"."can__legacy_40734"("p_resource" "text", "p_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can__legacy_56548"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid" DEFAULT "public"."current_tenant_id"()) RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  allowed boolean;
begin
  if p_tenant_id is null then
    return false;
  end if;

  -- NOVO MODELO: a.usuario_tenant (OWNER/ADMIN) -> libera tudo
  if exists (
    select 1
    from a.usuario_tenant ut
    where ut.usuario_id = auth.uid()
      and ut.tenant_id = p_tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
  ) then
    return true;
  end if;

  -- MODELO ANTIGO (mantém compatibilidade)
  select exists (
    select 1
    from public.tenant_memberships tm
    join public.membership_roles mr on mr.membership_role = tm.role
    join public.roles r on r.id = mr.role_id
    join public.role_access_rules rul on rul.role_id = r.id
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant_id
      and tm.status = 'active'
      and r.is_active = true
      and rul.resource = p_resource
      and rul.action = p_action
  )
  into allowed;

  return coalesce(allowed, false);
end;
$$;


ALTER FUNCTION "public"."can__legacy_56548"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_many"("p_pairs" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  arr public.capability_pair[];
begin
  select coalesce(array_agg(
    row(
      (x->>'key')::text,
      (x->>'resource')::text,
      (x->>'action')::text
    )::public.capability_pair
  ), '{}'::public.capability_pair[])
  into arr
  from jsonb_array_elements(coalesce(p_pairs, '[]'::jsonb)) as x;

  return public.can_many(arr);
end;
$$;


ALTER FUNCTION "public"."can_many"("p_pairs" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_many"("p_pairs" "public"."capability_pair"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant_id uuid;
  r public.capability_pair;
  out jsonb := '{}'::jsonb;
  allowed boolean;
begin
  v_tenant_id := public.current_tenant_id();

  foreach r in array p_pairs loop
    if v_tenant_id is null then
      allowed := false;
    else
      allowed := public.can(r.resource, r.action, v_tenant_id);
    end if;

    out := out || jsonb_build_object(r.key, allowed);
  end loop;

  return out;
end;
$$;


ALTER FUNCTION "public"."can_many"("p_pairs" "public"."capability_pair"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."concluir_os"("os_id_param" integer) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  update public.ordens_servico
  set status = 'concluida',
      data_conclusao = now(),
      atualizado_em = now()
  where id = os_id_param;

  update public.os_gestao_itens
  set progresso_percent = 100,
      data_prevista = coalesce(data_prevista, current_date),
      updated_at = now()
  where os_id = os_id_param
    and habilitado = true
    and item_tipo in ('projeto'::public.os_gestao_tipo, 'execucao'::public.os_gestao_tipo)
    and area in (
      'eletrico'::public.os_gestao_area,
      'seguranca'::public.os_gestao_area,
      'mecanico'::public.os_gestao_area,
      'software'::public.os_gestao_area
    )
    and coalesce(progresso_percent,0) < 100;
end;
$$;


ALTER FUNCTION "public"."concluir_os"("os_id_param" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirmar_lancamento_contabil"("p_lancamento_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_diff numeric;
  v_comp uuid;
  v_ano int;
  v_mes int;
  v_status_comp text;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  -- garante que lançamento é da empresa/tenant atual
  perform 1
  from public.lancamentos_contabeis
  where id = p_lancamento_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;

  if not found then
    raise exception 'Lançamento não encontrado para este tenant/empresa';
  end if;

  -- valida débito = crédito
  select diferenca into v_diff
  from public.v_lancamentos_contabeis_balance
  where lancamento_id = p_lancamento_id;

  if v_diff is null then v_diff := 0; end if;

  if v_diff <> 0 then
    raise exception 'Lançamento não balanceado (diferença=%). Ajuste débitos/créditos.', v_diff;
  end if;

  -- trava por competência: pega competência do data_lancamento (se não existir, cria)
  select data_lancamento into strict v_ano
  from public.lancamentos_contabeis
  where id = p_lancamento_id;

  -- cria/pega competencia do mês do lançamento
  select public.ensure_competencia(
    (select data_lancamento from public.lancamentos_contabeis where id = p_lancamento_id)
  ) into v_comp;

  -- verifica se competência está aberta
  select c.status into v_status_comp
  from public.competencias c
  where c.id = v_comp;

  if v_status_comp <> 'aberta' then
    raise exception 'Competência fechada. Não é permitido confirmar lançamentos nesse mês.';
  end if;

  -- grava competencia no lançamento e confirma
  update public.lancamentos_contabeis
     set competencia_id = v_comp,
         status = 'confirmado',
         atualizado_em = now()
   where id = p_lancamento_id;
end;
$$;


ALTER FUNCTION "public"."confirmar_lancamento_contabil"("p_lancamento_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."criar_gestao_padrao_os"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Só cria itens de gestão quando a OS estiver com gestão habilitada
  IF COALESCE(NEW.tem_gestao, false) IS DISTINCT FROM true THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.os_gestao_itens (tenant_id, os_id, item_tipo, area)
  VALUES
    (NEW.tenant_id, NEW.id, 'projeto',  'eletrico'),
    (NEW.tenant_id, NEW.id, 'projeto',  'mecanico'),
    (NEW.tenant_id, NEW.id, 'projeto',  'seguranca'),
    (NEW.tenant_id, NEW.id, 'projeto',  'software'),
    (NEW.tenant_id, NEW.id, 'execucao', 'eletrico'),
    (NEW.tenant_id, NEW.id, 'execucao', 'mecanico')
  ON CONFLICT ON CONSTRAINT os_gestao_itens_os_key DO NOTHING;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."criar_gestao_padrao_os"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_auth_user_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'),
    (nullif(current_setting('request.jwt.claim',  true), '')::jsonb ->> 'sub')
  )::uuid;
$$;


ALTER FUNCTION "public"."current_auth_user_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_competencia_key"("p_data" "date" DEFAULT CURRENT_DATE) RETURNS TABLE("ano" integer, "mes" integer)
    LANGUAGE "sql" STABLE
    AS $$
  select extract(year from p_data)::int as ano,
         extract(month from p_data)::int as mes;
$$;


ALTER FUNCTION "public"."current_competencia_key"("p_data" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_empresa_id"("p_tenant_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a', 'c'
    AS $$
  select public.current_empresa_id();
$$;


ALTER FUNCTION "public"."current_empresa_id"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_empresa_id__by_tenant"("p_tenant_id" "uuid" DEFAULT "public"."current_tenant_id"()) RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  e uuid;
begin
  if p_tenant_id is null then
    return null;
  end if;

  select uec.empresa_id
    into e
  from public.user_empresa_context uec
  where uec.user_id = auth.uid()
    and uec.tenant_id = p_tenant_id
  limit 1;

  if e is not null then
    return e;
  end if;

  select em.empresa_id
    into e
  from public.empresa_memberships em
  where em.user_id = auth.uid()
    and em.tenant_id = p_tenant_id
    and em.status = 'active'
  order by em.criado_em asc
  limit 1;

  if e is not null then
    return e;
  end if;

  select ue.empresa_id
    into e
  from a.usuario_empresa ue
  where ue.usuario_id = auth.uid()
    and ue.tenant_id = p_tenant_id
    and ue.ativo = true
    and ue.deleted_at is null
  order by ue.created_at asc
  limit 1;

  return e;
end;
$$;


ALTER FUNCTION "public"."current_empresa_id__by_tenant"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_auth_context"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select jsonb_build_object(
    'current_user', current_user,
    'session_user', session_user,
    'claim_sub', current_setting('request.jwt.claim.sub', true),
    'claims', current_setting('request.jwt.claims', true),
    'claim',  current_setting('request.jwt.claim', true),
    'current_auth_user_id', public.current_auth_user_id()::text
  );
$$;


ALTER FUNCTION "public"."debug_auth_context"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_jwt"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select jsonb_build_object(
    'claim_sub', current_setting('request.jwt.claim.sub', true),
    'claims', current_setting('request.jwt.claims', true),
    'claim', current_setting('request.jwt.claim', true),
    'current_auth_user_id', public.current_auth_user_id()::text
  );
$$;


ALTER FUNCTION "public"."debug_jwt"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_me"() RETURNS json
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_email text := coalesce((auth.jwt() ->> 'email'), '');
  v_roles text[];
begin
  if v_uid is null then
    raise exception 'Não autenticado';
  end if;

  -- recomendado: só Admin pode usar debug
  if not public.has_permission('cadastros.itens') and not public.has_permission('os.gerenciar') then
    -- Se quiser travar estritamente por Admin, eu ajusto para checar role 'Admin'.
    raise exception 'Sem permissão para debug';
  end if;

  select array_agg(distinct r.name order by r.name) into v_roles
  from public.tenant_memberships tm
  join public.membership_roles mr on mr.membership_id = tm.id
  join public.roles r on r.id = mr.role_id
  where tm.user_id = v_uid
    and tm.status = 'active'
    and tm.tenant_id = public.current_tenant_id();

  return json_build_object(
    'uid', v_uid,
    'email', v_email,
    'tenant_id', public.current_tenant_id(),
    'roles', coalesce(v_roles, array[]::text[])
  );
end $$;


ALTER FUNCTION "public"."debug_me"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_membership"() RETURNS TABLE("uid" "uuid", "memberships_active" integer, "tenant_id" "uuid")
    LANGUAGE "sql" STABLE
    AS $$
  select
    auth.uid() as uid,
    (
      select count(*)
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.status = 'active'
    ) as memberships_active,
    (
      select tm.tenant_id
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.status = 'active'
      order by tm.created_at desc
      limit 1
    ) as tenant_id
$$;


ALTER FUNCTION "public"."debug_membership"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_tenant"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  select jsonb_build_object(
    'uid', auth.uid(),
    'tenant', public.current_tenant_id(),
    'tenant_setting', current_setting('app.tenant_id', true)
  );
$$;


ALTER FUNCTION "public"."debug_tenant"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."default_empresa_id"("p_tenant_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select e.id
  from public.empresas e
  where e.tenant_id = p_tenant_id
  order by e.criado_em asc
  limit 1
$$;


ALTER FUNCTION "public"."default_empresa_id"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_competencia"("p_data" "date" DEFAULT CURRENT_DATE) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_ano int;
  v_mes int;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;

  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  select ano, mes into v_ano, v_mes from public.current_competencia_key(p_data);

  insert into public.competencias (tenant_id, empresa_id, ano, mes)
  values (v_tenant, v_empresa, v_ano, v_mes)
  on conflict (tenant_id, empresa_id, ano, mes) do update
    set atualizado_em = now()
  returning id into v_id;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."ensure_competencia"("p_data" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_estoque_rows"("p_tenant_id" "uuid", "p_item_ids" integer[]) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid;
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;

  v_empresa := public.current_empresa_id();
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  if not public.has_permission('estoque.ajustar') then
    raise exception 'Sem permissão: estoque.ajustar';
  end if;

  insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual, atualizado_em)
  select v_tenant, v_empresa, x, 0, now()
  from unnest(p_item_ids) as x
  on conflict on constraint estoque_tenant_empresa_item_key do nothing;
end;
$$;


ALTER FUNCTION "public"."ensure_estoque_rows"("p_tenant_id" "uuid", "p_item_ids" integer[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."estornar_lancamento_contabil"("p_lancamento_id" "uuid", "p_historico" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_status text;
  v_comp uuid;
  v_comp_status text;
  v_new_id uuid;
  v_hist text;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  select l.status, l.competencia_id, l.historico
    into v_status, v_comp, v_hist
  from public.lancamentos_contabeis l
  where l.id = p_lancamento_id
    and l.tenant_id = v_tenant
    and l.empresa_id = v_empresa;

  if not found then
    raise exception 'Lançamento não encontrado para este tenant/empresa';
  end if;

  if v_status <> 'confirmado' then
    raise exception 'Apenas lançamentos CONFIRMADOS podem ser estornados (status atual=%)', v_status;
  end if;

  if v_comp is not null then
    select status into v_comp_status
    from public.competencias
    where id = v_comp;

    if v_comp_status <> 'aberta' then
      raise exception 'Competência fechada. Não é permitido estornar lançamentos nesse mês.';
    end if;
  end if;

  -- cria cabeçalho do estorno
  insert into public.lancamentos_contabeis (
    tenant_id, empresa_id, competencia_id, data_lancamento,
    historico, origem_tipo, origem_id, status
  )
  select
    tenant_id, empresa_id, competencia_id, data_lancamento,
    coalesce(p_historico, 'ESTORNO: ' || historico),
    'estorno',
    p_lancamento_id::text,
    'confirmado'
  from public.lancamentos_contabeis
  where id = p_lancamento_id
  returning id into v_new_id;

  -- cria itens invertendo débito/credito
  insert into public.lancamentos_contabeis_itens (
    tenant_id, empresa_id, lancamento_id, conta_id, centro_custo_id, tipo, valor, complemento
  )
  select
    tenant_id, empresa_id, v_new_id, conta_id, centro_custo_id,
    case when tipo='debito' then 'credito' else 'debito' end,
    valor,
    coalesce(complemento,'') || ' (estorno)'
  from public.lancamentos_contabeis_itens
  where lancamento_id = p_lancamento_id;

  -- marca original como estornado
  update public.lancamentos_contabeis
     set status = 'estornado',
         atualizado_em = now()
   where id = p_lancamento_id;

  return v_new_id;
end;
$$;


ALTER FUNCTION "public"."estornar_lancamento_contabil"("p_lancamento_id" "uuid", "p_historico" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."estornar_movimentacao"("p_mov_id" integer, "p_motivo" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v public.movimentacoes%rowtype;
  v_new_id int;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  if not public.has_permission('estoque.movimentar') then
    raise exception 'Sem permissão: estoque.movimentar';
  end if;

  select *
  into v
  from public.movimentacoes
  where id = p_mov_id
    and tenant_id = public.current_tenant_id();

  if not found then
    raise exception 'Movimentação não encontrada no tenant atual';
  end if;

  insert into public.movimentacoes (
    tenant_id,
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    custo_unitario_bruto,
    custo_unitario_real,
    credito_icms,
    credito_pis,
    credito_cofins,
    origem_nf_entrada_id,
    v_ipi, v_icms, v_pis, v_cofins, v_frete_rateado,
    created_at
  ) values (
    v.tenant_id,
    v.item_id,
    'estorno',
    (v.quantidade * -1),
    coalesce(p_motivo, 'Estorno da movimentação #' || v.id),
    coalesce(v.realizado_por, auth.uid()::text),
    now(),
    v.custo_unitario_bruto,
    v.custo_unitario_real,
    (v.credito_icms * -1),
    (v.credito_pis * -1),
    (v.credito_cofins * -1),
    v.origem_nf_entrada_id,
    (v.v_ipi * -1),
    (v.v_icms * -1),
    (v.v_pis * -1),
    (v.v_cofins * -1),
    (v.v_frete_rateado * -1),
    now()
  )
  returning id into v_new_id;

  return v_new_id;
end $$;


ALTER FUNCTION "public"."estornar_movimentacao"("p_mov_id" integer, "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fechar_competencia"("p_ano" integer, "p_mes" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_competencia_date date := make_date(p_ano, p_mes, 1);
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;

  if v_empresa is null then
    raise exception 'Empresa atual não definido';
  end if;

  -- upsert: cria/fecha em um passo
  insert into public.competencias (
    tenant_id, empresa_id, ano, mes,
    status, fechada_em, fechada_por, atualizado_em
  )
  values (
    v_tenant, v_empresa, p_ano, p_mes,
    'fechada', now(), auth.uid(), now()
  )
  on conflict (tenant_id, empresa_id, ano, mes) do update
  set
    status = 'fechada',
    fechada_em = coalesce(public.competencias.fechada_em, excluded.fechada_em),
    fechada_por = coalesce(public.competencias.fechada_por, excluded.fechada_por),
    atualizado_em = now();

  -- Hook IRPJ/CSLL (não bloqueia fechamento)
  begin
    perform f.fn_irpj_csll_ao_fechar_competencia(v_tenant, v_empresa, v_competencia_date);
  exception when others then
    raise notice 'Fechamento: hook IRPJ/CSLL falhou na competência %: %', v_competencia_date, sqlerrm;
  end;
end;
$$;


ALTER FUNCTION "public"."fechar_competencia"("p_ano" integer, "p_mes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fechar_competencia_admin"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_ano" integer, "p_mes" integer, "p_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_competencia_date date := make_date(p_ano, p_mes, 1);
begin
  insert into public.competencias (
    tenant_id, empresa_id, ano, mes,
    status, fechada_em, fechada_por, atualizado_em
  )
  values (
    p_tenant_id, p_empresa_id, p_ano, p_mes,
    'fechada', now(), p_user_id, now()
  )
  on conflict (tenant_id, empresa_id, ano, mes) do update
  set
    status = 'fechada',
    -- não sobrescreve quem/ quando fechou se já estava fechado
    fechada_em = coalesce(public.competencias.fechada_em, excluded.fechada_em),
    fechada_por = coalesce(public.competencias.fechada_por, excluded.fechada_por),
    atualizado_em = now();

  -- Hook IRPJ/CSLL (não bloqueia)
  begin
    perform f.fn_irpj_csll_ao_fechar_competencia(p_tenant_id, p_empresa_id, v_competencia_date);
  exception when others then
    raise notice 'Fechamento admin: hook IRPJ/CSLL falhou na competência %: %', v_competencia_date, sqlerrm;
  end;
end;
$$;


ALTER FUNCTION "public"."fechar_competencia_admin"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_ano" integer, "p_mes" integer, "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_arrendamento_gerar_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f', 'a'
    AS $_$
  select f.fn_arrendamento_gerar_ap($1,$2,$3);
$_$;


ALTER FUNCTION "public"."fn_arrendamento_gerar_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_atualiza_estoque_por_mov"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."fn_atualiza_estoque_por_mov"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_calc_horas_2_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
  v_min1 numeric;
  v_min2 numeric;
  v_total_h numeric;
BEGIN
  IF p_e1 IS NULL OR p_s1 IS NULL OR p_e2 IS NULL OR p_s2 IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_s1 <= p_e1 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser maior que Entrada 1 (%).', p_s1, p_e1;
  END IF;

  IF p_s2 <= p_e2 THEN
    RAISE EXCEPTION 'Saída 2 (%) deve ser maior que Entrada 2 (%).', p_s2, p_e2;
  END IF;

  IF p_s1 > p_e2 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser menor/igual à Entrada 2 (%).', p_s1, p_e2;
  END IF;

  v_min1 := EXTRACT(EPOCH FROM (p_s1 - p_e1)) / 60.0;
  v_min2 := EXTRACT(EPOCH FROM (p_s2 - p_e2)) / 60.0;

  v_total_h := (v_min1 + v_min2) / 60.0;

  RETURN ROUND(v_total_h::numeric, 2);
END $$;


ALTER FUNCTION "public"."fn_calc_horas_2_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_calc_horas_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
  v_min1 numeric;
  v_min2 numeric;
  v_total_h numeric;
BEGIN
  IF p_e1 IS NULL OR p_s1 IS NULL OR p_e2 IS NULL OR p_s2 IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_s1 <= p_e1 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser maior que Entrada 1 (%).', p_s1, p_e1;
  END IF;

  IF p_s2 <= p_e2 THEN
    RAISE EXCEPTION 'Saída 2 (%) deve ser maior que Entrada 2 (%).', p_s2, p_e2;
  END IF;

  IF p_s1 > p_e2 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser menor/igual à Entrada 2 (%).', p_s1, p_e2;
  END IF;

  v_min1 := EXTRACT(EPOCH FROM (p_s1 - p_e1)) / 60.0;
  v_min2 := EXTRACT(EPOCH FROM (p_s2 - p_e2)) / 60.0;

  v_total_h := (v_min1 + v_min2) / 60.0;

  -- arredonda para 2 casas como a coluna "horas" (numeric(6,2))
  RETURN ROUND(v_total_h::numeric, 2);
END $$;


ALTER FUNCTION "public"."fn_calc_horas_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_documento_key"("p_doc" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case
    when p_doc is null then ''
    else
      case
        when length(regexp_replace(p_doc, '\D', '', 'g')) >= 14
          then substring(regexp_replace(p_doc, '\D', '', 'g') from 1 for 14)
        else regexp_replace(p_doc, '\D', '', 'g')
      end
  end
$$;


ALTER FUNCTION "public"."fn_documento_key"("p_doc" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_ensure_titulo_ap_from_nf_entrada"("p_nf_entrada_id" bigint, "p_force_regen_parcelas" boolean DEFAULT false, "p_parcelas_json" "jsonb" DEFAULT NULL::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f', 'a', 'extensions'
    AS $$
declare
  v_nf public.nf_entrada%rowtype;

  v_doc_id uuid;
  v_titulo_id uuid;
  v_fornecedor_id integer;

  v_emissao_date date;
  v_competencia date;

  v_total  numeric(15,2);
  v_vprod  numeric(15,2);
  v_vfrete numeric(15,2);
  v_vdesc  numeric(15,2);
  v_voutros numeric(15,2);
  v_vseg   numeric(15,2);

  v_xml xml;

  v_modelo text;
  v_serie  text;
  v_numero text;

  v_dup_nodes xml[];
  v_count int;
  i int;

  v_nDup text;
  v_dVenc date;
  v_vDup numeric(15,2);

  v_sum numeric(15,2) := 0;

  v_plano_contas_id uuid;
  v_tem_parcelas_ativas boolean := false;

begin
  select * into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada não encontrada (id=%)', p_nf_entrada_id;
  end if;

  -- Documento fiscal (garante por source_nf_entrada_id/chave)
  v_doc_id := f.fn_find_documento_fiscal_from_import(v_nf.id);
  if v_doc_id is null then
    raise exception 'Falha ao garantir documento_fiscal (nf_entrada_id=%)', v_nf.id;
  end if;

  -- Datas
  v_emissao_date := coalesce((v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
                             (now() at time zone 'America/Sao_Paulo')::date);
  v_competencia := date_trunc('month', v_emissao_date)::date;

  -- Valores (da NF)
  v_total   := coalesce(v_nf.valor_total, 0);
  v_vprod   := coalesce(v_nf.valor_produtos, 0);
  v_vfrete  := coalesce(v_nf.valor_frete, 0);
  v_vdesc   := coalesce(v_nf.valor_desconto, 0);
  v_voutros := coalesce(v_nf.valor_outros, 0);
  v_vseg    := coalesce(v_nf.valor_seguro, 0);

  -- Fornecedor (garante)
  v_fornecedor_id := nullif(v_nf.fornecedor_id, 0)::int;

  if v_fornecedor_id is null then
    v_fornecedor_id := public.fn_fornecedor_upsert_por_documento(
      v_nf.tenant_id,
      coalesce(v_nf.emitente_nome, 'FORNECEDOR'),
      v_nf.emitente_cnpj
    );

    update public.nf_entrada
       set fornecedor_id = v_fornecedor_id::bigint,
           updated_at = now()
     where id = v_nf.id;
  end if;

  -- Se tem XML, enriquece modelo/serie/numero e (se quiser) recalcula totais do XML
  if v_nf.xml_raw is not null and nullif(btrim(v_nf.xml_raw), '') is not null then
    v_xml := xmlparse(document v_nf.xml_raw);

    v_modelo := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="mod"])', v_xml))[1]::text,'');
    v_serie  := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="serie"])', v_xml))[1]::text,'');
    v_numero := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="nNF"])', v_xml))[1]::text,'');

    v_vprod   := coalesce(nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vProd"])', v_xml))[1]::text,'')::numeric, v_vprod);
    v_vfrete  := coalesce(nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vFrete"])', v_xml))[1]::text,'')::numeric, v_vfrete);
    v_vdesc   := coalesce(nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vDesc"])', v_xml))[1]::text,'')::numeric, v_vdesc);
    v_voutros := coalesce(nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vOutro"])', v_xml))[1]::text,'')::numeric, v_voutros);
    v_vseg    := coalesce(nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vSeg"])', v_xml))[1]::text,'')::numeric, v_vseg);
    v_total   := coalesce(nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vNF"])', v_xml))[1]::text,'')::numeric, v_total);
  end if;

  v_modelo := coalesce(nullif(v_modelo,''), nullif(v_nf.modelo,''), '55');
  v_serie  := coalesce(nullif(v_serie,''), nullif(v_nf.serie,''), '');
  v_numero := coalesce(nullif(v_numero,''), nullif(v_nf.numero,''), '');

  -- Atualiza nf_entrada modelo (pra ficar consistente)
  update public.nf_entrada
     set modelo = v_modelo,
         updated_at = now()
   where id = v_nf.id;

  -- Enriquecer documento_fiscal (corrige exatamente o que você viu: modelo/fornecedor/valores zerados)
  update f.documento_fiscal
     set fornecedor_id    = v_fornecedor_id,
         modelo           = v_modelo,
         serie            = v_serie,
         numero           = v_numero,
         emissao_date     = v_emissao_date,
         competencia_date = v_competencia,
         valor_total      = v_total,
         valor_produtos   = v_vprod,
         valor_frete      = v_vfrete,
         valor_desconto   = v_vdesc,
         valor_outros     = v_voutros,
         valor_seguro     = v_vseg,
         updated_at       = now()
   where id = v_doc_id;

  -- Garante título AP por documento_fiscal
  select t.id into v_titulo_id
  from f.titulo t
  where t.tenant_id = v_nf.tenant_id
    and t.empresa_id = v_nf.empresa_id
    and t.tipo = 'AP'
    and t.documento_fiscal_id = v_doc_id
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
    ) values (
      v_nf.tenant_id, v_nf.empresa_id, 'AP', 'PENDENTE', 'XML',
      v_fornecedor_id, v_doc_id,
      upper(concat('NF-E ', coalesce(v_numero,''), '/', coalesce(v_serie,''), ' - ', coalesce(v_nf.emitente_nome,'FORNECEDOR'))),
      v_emissao_date, v_competencia,
      v_total, v_total,
      v_nf.motivo_compra_id
    )
    returning id into v_titulo_id;

    -- título novo => sempre gerar parcelas
    p_force_regen_parcelas := true;
  end if;

  -- Se não tem parcelas ativas, também força gerar
  select exists(
    select 1 from f.titulo_parcela p
    where p.tenant_id = v_nf.tenant_id
      and p.titulo_id = v_titulo_id
      and p.deleted_at is null
  ) into v_tem_parcelas_ativas;

  if not v_tem_parcelas_ativas then
    p_force_regen_parcelas := true;
  end if;

  -- Regenera parcelas (se forçado ou não existiam)
  if p_force_regen_parcelas then
    update f.titulo_parcela
       set deleted_at = now(),
           updated_at = now()
     where tenant_id = v_nf.tenant_id
       and titulo_id = v_titulo_id
       and deleted_at is null;

    v_sum := 0;

    -- 1) Se vier parcelas_json, PRIORIDADE
    if p_parcelas_json is not null
       and jsonb_typeof(p_parcelas_json) = 'array'
       and jsonb_array_length(p_parcelas_json) > 0
    then
      select coalesce(sum((p->>'valor')::numeric),0)
        into v_sum
      from jsonb_array_elements(p_parcelas_json) p;

      if abs(coalesce(v_sum,0) - coalesce(v_total,0)) > 0.05 then
        raise exception 'Soma das parcelas (%.2f) difere do total da NF (%.2f)', v_sum, v_total;
      end if;

      insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
      select
        v_nf.tenant_id,
        v_titulo_id,
        nullif(p->>'numero',''),
        (p->>'vencimento')::date,
        (p->>'valor')::numeric,
        (p->>'valor')::numeric
      from jsonb_array_elements(p_parcelas_json) p;

    else
      -- 2) Senão tenta XML (duplicatas)
      if v_nf.xml_raw is not null and nullif(btrim(v_nf.xml_raw), '') is not null then
        -- v_xml já foi montado acima
        v_dup_nodes := xpath('//*[local-name()="cobr"]/*[local-name()="dup"]', v_xml);
        v_count := coalesce(array_length(v_dup_nodes, 1), 0);
      else
        v_count := 0;
      end if;

      if v_count = 0 then
        -- fallback: parcela única
        insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
        values (v_nf.tenant_id, v_titulo_id, '001', v_emissao_date, v_total, v_total);
        v_sum := v_total;
      else
        for i in 1..v_count loop
          v_nDup  := nullif((xpath('string(//*[local-name()="nDup"])',  v_dup_nodes[i]))[1]::text,'');
          v_dVenc := nullif((xpath('string(//*[local-name()="dVenc"])', v_dup_nodes[i]))[1]::text,'')::date;
          v_vDup  := nullif((xpath('string(//*[local-name()="vDup"])',  v_dup_nodes[i]))[1]::text,'')::numeric;

          v_nDup  := coalesce(v_nDup, lpad(i::text, 3, '0'));
          v_dVenc := coalesce(v_dVenc, v_emissao_date);
          v_vDup  := coalesce(v_vDup, 0);

          insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
          values (v_nf.tenant_id, v_titulo_id, v_nDup, v_dVenc, v_vDup, v_vDup);

          v_sum := v_sum + v_vDup;
        end loop;

        -- se bater, beleza; se não bater, só não explode (porque XML pode ter cobranças diferentes)
        -- (quem manda é o total do documento)
      end if;
    end if;

    -- Atualiza título aberto (não mexe se já estiver PAGO/CANCELADO)
    update f.titulo
       set emissao_date = v_emissao_date,
           competencia_date = v_competencia,
           valor_total = v_total,
           valor_aberto = case
                            when status not in ('PAGO','CANCELADO') then
                              coalesce((
                                select coalesce(sum(p.valor_aberto),0)
                                from f.titulo_parcela p
                                where p.tenant_id = v_nf.tenant_id
                                  and p.titulo_id = v_titulo_id
                                  and p.deleted_at is null
                              ), v_total)
                            else valor_aberto
                          end,
           fornecedor_id = v_fornecedor_id,
           motivo_compra_id = v_nf.motivo_compra_id,
           updated_at = now()
     where id = v_titulo_id
       and tenant_id = v_nf.tenant_id
       and deleted_at is null;
  end if;

  -- Rateio (1 linha 100%) se ainda não existir
  select mc.plano_contas_id
    into v_plano_contas_id
  from f.motivo_compra mc
  where mc.id = v_nf.motivo_compra_id
    and mc.tenant_id = v_nf.tenant_id
    and mc.deleted_at is null
  limit 1;

  if not exists (
    select 1 from f.titulo_rateio tr
    where tr.tenant_id = v_nf.tenant_id
      and tr.titulo_id = v_titulo_id
      and tr.deleted_at is null
  ) then
    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_nf.tenant_id, v_titulo_id, v_plano_contas_id, v_nf.os_id, 100, v_total);
  end if;

  return v_titulo_id;
end;
$$;


ALTER FUNCTION "public"."fn_ensure_titulo_ap_from_nf_entrada"("p_nf_entrada_id" bigint, "p_force_regen_parcelas" boolean, "p_parcelas_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_fix_nf_entrada_pos_import"("p_nf_entrada_id" bigint) RETURNS TABLE("status" "text", "message" "text", "documento_fiscal_id" "uuid", "titulo_id" "uuid")
    LANGUAGE "plpgsql"
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_xml xml;

  v_emit_nome text;
  v_emit_doc  text;

  v_mod   text;
  v_serie text;
  v_num   text;

  v_dhemi text;
  v_emissao_ts timestamptz;
  v_emissao_date date;
  v_competencia date;

  v_vprod   numeric(15,2);
  v_vfrete  numeric(15,2);
  v_vdesc   numeric(15,2);
  v_voutros numeric(15,2);
  v_vseg    numeric(15,2);
  v_vnf     numeric(15,2);

  v_fornecedor_id int;
  v_df_id uuid;
  v_titulo_id uuid;

  v_prev_total numeric(15,2);
  v_sum_parcelas numeric(15,2);
  v_plano_contas_id uuid;
begin
  select * into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada não encontrada (id=%)', p_nf_entrada_id;
  end if;

  if v_nf.xml_raw is null or nullif(btrim(v_nf.xml_raw), '') is null then
    raise exception 'nf_entrada % sem xml_raw. Não dá pra enriquecer/gerar AP.', p_nf_entrada_id;
  end if;

  v_xml := xmlparse(document v_nf.xml_raw);

  -- Extrair dados (ignora namespace via local-name())
  v_emit_nome := nullif((xpath('string(//*[local-name()="emit"]/*[local-name()="xNome"])', v_xml))[1]::text, '');
  v_emit_doc  := nullif((xpath('string(//*[local-name()="emit"]/*[local-name()="CNPJ"])', v_xml))[1]::text, '');
  if v_emit_doc is null then
    v_emit_doc := nullif((xpath('string(//*[local-name()="emit"]/*[local-name()="CPF"])', v_xml))[1]::text, '');
  end if;

  v_mod   := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="mod"])', v_xml))[1]::text, '');
  v_serie := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="serie"])', v_xml))[1]::text, '');
  v_num   := nullif((xpath('string(//*[local-name()="ide"]/*[local-name()="nNF"])', v_xml))[1]::text, '');

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

  v_vprod   := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vProd"])', v_xml))[1]::text, '')::numeric;
  v_vfrete  := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vFrete"])', v_xml))[1]::text, '')::numeric;
  v_vdesc   := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vDesc"])', v_xml))[1]::text, '')::numeric;
  v_voutros := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vOutro"])', v_xml))[1]::text, '')::numeric;
  v_vseg    := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vSeg"])', v_xml))[1]::text, '')::numeric;
  v_vnf     := nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vNF"])', v_xml))[1]::text, '')::numeric;

  v_vprod   := coalesce(v_vprod, (select coalesce(sum(i.v_prod),0) from public.nf_entrada_itens i where i.nf_entrada_id = v_nf.id), 0);
  v_vfrete  := coalesce(v_vfrete, 0);
  v_vdesc   := coalesce(v_vdesc, 0);
  v_voutros := coalesce(v_voutros, 0);
  v_vseg    := coalesce(v_vseg, 0);
  v_vnf     := coalesce(v_vnf, v_nf.valor_total, 0);

  -- fornecedor
  v_fornecedor_id := nullif(v_nf.fornecedor_id::int, 0);
  if v_fornecedor_id is null then
    v_fornecedor_id := public.fn_fornecedor_upsert_por_documento(
      v_nf.tenant_id,
      coalesce(v_emit_nome, v_nf.emitente_nome, 'FORNECEDOR'),
      coalesce(v_emit_doc, v_nf.emitente_cnpj)
    );
  end if;

  -- atualiza nf_entrada
  update public.nf_entrada
     set modelo         = coalesce(v_mod, modelo, '55'),
         serie          = coalesce(v_serie, serie),
         numero         = coalesce(v_num, numero),
         emitente_nome  = coalesce(v_emit_nome, emitente_nome),
         emitente_cnpj  = coalesce(v_emit_doc, emitente_cnpj),
         data_emissao   = coalesce(v_emissao_ts, data_emissao),
         valor_produtos = v_vprod,
         valor_frete    = v_vfrete,
         valor_desconto = v_vdesc,
         valor_outros   = v_voutros,
         valor_seguro   = v_vseg,
         valor_total    = v_vnf,
         fornecedor_id  = v_fornecedor_id,
         updated_at     = now()
   where id = v_nf.id;

  -- garante documento fiscal e enriquece
  v_df_id := f.fn_ensure_documento_fiscal_from_nf_entrada(v_nf.id);

  update f.documento_fiscal
     set modelo           = coalesce(v_mod, modelo, '55'),
         serie            = coalesce(v_serie, serie),
         numero           = coalesce(v_num, numero),
         fornecedor_id    = v_fornecedor_id,
         emissao_date     = v_emissao_date,
         competencia_date = v_competencia,
         valor_produtos   = v_vprod,
         valor_frete      = v_vfrete,
         valor_desconto   = v_vdesc,
         valor_outros     = v_voutros,
         valor_seguro     = v_vseg,
         valor_total      = v_vnf,
         updated_at       = now()
   where id = v_df_id;

  -- cria/acha título AP
  select t.id into v_titulo_id
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
    ) values (
      v_nf.tenant_id, v_nf.empresa_id, 'AP', 'PENDENTE', 'XML',
      v_fornecedor_id, v_df_id,
      concat('NF-e ', coalesce(v_num,''), '/', coalesce(v_serie,''), ' - ', coalesce(v_emit_nome, 'FORNECEDOR')),
      v_emissao_date, v_competencia,
      v_vnf, v_vnf,
      v_nf.motivo_compra_id
    )
    returning id into v_titulo_id;
  end if;

  -- parcelas: SEMPRE do XML (corrigido)
  perform 1 from public.fn_regerar_parcelas_titulo_from_xml(v_nf.id, v_titulo_id);

  select valor_total into v_prev_total
  from f.titulo where id = v_titulo_id;

  select coalesce(sum(p.valor),0) into v_sum_parcelas
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

  -- rateio (se não existir)
  select mc.plano_contas_id
    into v_plano_contas_id
  from f.motivo_compra mc
  where mc.id = v_nf.motivo_compra_id
    and mc.tenant_id = v_nf.tenant_id
    and mc.deleted_at is null
  limit 1;

  if not exists (
    select 1 from f.titulo_rateio tr
    where tr.tenant_id = v_nf.tenant_id
      and tr.titulo_id = v_titulo_id
      and tr.deleted_at is null
  ) then
    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_nf.tenant_id, v_titulo_id, v_plano_contas_id, v_nf.os_id, 100, v_sum_parcelas);
  end if;

  status := 'ok';
  message := 'NF enriquecida + DF atualizado + Título AP gerado (f.*).';
  documento_fiscal_id := v_df_id;
  titulo_id := v_titulo_id;
  return next;
end;
$$;


ALTER FUNCTION "public"."fn_fix_nf_entrada_pos_import"("p_nf_entrada_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_fornecedor_upsert_por_documento"("p_tenant_id" "uuid", "p_nome" "text", "p_documento" "text") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
declare
  v_doc_norm text := public.fn_normalize_documento(p_documento);
  v_id integer;
begin
  -- Se tem documento (CNPJ/CPF), tenta achar pelo documento_norm
  if v_doc_norm <> '' then
    select f.id
      into v_id
      from public.fornecedores f
     where f.tenant_id = p_tenant_id
       and f.documento_norm = v_doc_norm
     order by f.id
     limit 1;

    if v_id is not null then
      -- melhora o nome se vier mais completo
      update public.fornecedores
         set nome = coalesce(nullif(nome,''), p_nome)
       where id = v_id;

      return v_id;
    end if;
  end if;

  -- Se não achou (ou não tem documento), cria novo
  insert into public.fornecedores (tenant_id, nome, documento, ativo)
  values (p_tenant_id, coalesce(nullif(p_nome,''),'(Sem nome)'), nullif(p_documento,''), true)
  returning id into v_id;

  return v_id;
end $$;


ALTER FUNCTION "public"."fn_fornecedor_upsert_por_documento"("p_tenant_id" "uuid", "p_nome" "text", "p_documento" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_hh_criar_apontamento"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_apontamento_id uuid;
BEGIN
  -- Ao inserir/atualizar HH, criar/atualizar apontamento
  
  -- Buscar apontamento existente
  SELECT id INTO v_apontamento_id
  FROM public.apontamentos_horas
  WHERE hh_lancamento_id = NEW.id
  LIMIT 1;
  
  IF v_apontamento_id IS NULL THEN
    -- Criar novo
    INSERT INTO public.apontamentos_horas (
      tenant_id,
      empresa_id,
      os_id,
      colaborador_id,
      data,
      horas,
      gerado_por_hh,
      hh_lancamento_id,
      status
    ) VALUES (
      NEW.tenant_id,
      NEW.empresa_id,
      NEW.os_id,
      NEW.colaborador_id,
      NEW.data,
      NEW.horas_trabalhadas,
      true,
      NEW.id,
      'lancado'
    );
  ELSE
    -- Atualizar existente
    UPDATE public.apontamentos_horas
    SET
      colaborador_id = NEW.colaborador_id,
      data = NEW.data,
      horas = NEW.horas_trabalhadas
    WHERE id = v_apontamento_id;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_hh_criar_apontamento"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_hh_delete_apontamento"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  return old;
end;
$$;


ALTER FUNCTION "public"."fn_hh_delete_apontamento"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_hh_lancamentos_calc"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_perc int;
  v_cliente_id bigint;
  v_servico_id bigint;
  v_preco numeric;
  v_ok_vinculo boolean;
BEGIN
  -- 1) percentual sempre pela data (0/50/100)
  v_perc := public.fn_percentual_por_data(NEW.data);
  NEW.percentual_aplicado := v_perc;

  -- 2) Se usou 2 períodos, calcula horas. Se foi preenchido manualmente, aceita horas_trabalhadas direto
  IF NEW.entrada_1 IS NOT NULL OR NEW.saida_1 IS NOT NULL OR NEW.entrada_2 IS NOT NULL OR NEW.saida_2 IS NOT NULL THEN
    -- Modo 2-períodos: todos os 4 campos devem ser preenchidos
    IF NEW.entrada_1 IS NULL OR NEW.saida_1 IS NULL OR NEW.entrada_2 IS NULL OR NEW.saida_2 IS NULL THEN
      RAISE EXCEPTION 'Preencha Entrada 1, Saída 1, Entrada 2 e Saída 2 ou deixe todos em branco.';
    END IF;

    NEW.horas_trabalhadas := public.fn_calc_horas_2_periodos(
      NEW.entrada_1, NEW.saida_1, NEW.entrada_2, NEW.saida_2
    );

    NEW.hora_entrada := NEW.entrada_1;
    NEW.hora_saida   := NEW.saida_2;
  ELSIF NEW.horas_trabalhadas IS NULL THEN
    -- Se nem período nem horas_trabalhadas foram preenchidas, erro
    RAISE EXCEPTION 'Preencha ou (Entrada 1, Saída 1, Entrada 2, Saída 2) ou horas_trabalhadas.';
  END IF;

  -- 3) Descobrir cliente da OS
  SELECT os.cliente_id::bigint
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = NEW.os_id
    AND os.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % sem cliente vinculado (cliente_id).', NEW.os_id;
  END IF;

  -- 4) Serviço escolhido no lançamento:
  --    CRÍTICO: Usar hh_servico_id (ID real do serviço, ex: 8)
  --    NÃO usar hh_tipo_id (é apenas percentual mapping: 10, 11, 13, etc.)
  v_servico_id := NEW.hh_servico_id;

  IF v_servico_id IS NULL OR v_servico_id <= 0 THEN
    RAISE EXCEPTION 'Serviço HH inválido no lançamento (hh_servico_id=%).', NEW.hh_servico_id;
  END IF;

  -- 5) Valida se o colaborador tem vínculo com esse serviço para esse cliente
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_cliente_funcao ccf
    WHERE ccf.tenant_id = NEW.tenant_id
      AND ccf.cliente_id = v_cliente_id
      AND ccf.colaborador_id = NEW.colaborador_id
      AND ccf.hh_servico_id = v_servico_id
      AND COALESCE(ccf.ativo, true) = true
  )
  INTO v_ok_vinculo;

  IF NOT v_ok_vinculo THEN
    RAISE EXCEPTION
      'Serviço HH % não está vinculado ao colaborador % para o cliente % (colaborador_cliente_funcao).',
      v_servico_id, NEW.colaborador_id, v_cliente_id;
  END IF;

  -- 6) Buscar preço no cliente_hh_servicos pelo serviço selecionado + cliente/empresa/tenant
  SELECT
    CASE
      WHEN v_perc = 0   THEN s.preco_base
      WHEN v_perc = 50  THEN s.preco_50
      WHEN v_perc = 100 THEN s.preco_100
      ELSE NULL
    END
  INTO v_preco
  FROM public.cliente_hh_servicos s
  WHERE s.tenant_id = NEW.tenant_id
    AND s.empresa_id = NEW.empresa_id
    AND s.cliente_id = v_cliente_id
    AND s.id = v_servico_id
    AND s.ativo = true
  LIMIT 1;

  IF v_preco IS NULL THEN
    RAISE EXCEPTION
      'Preço HH não encontrado para serviço % / cliente % / empresa % / percentual %.',
      v_servico_id, v_cliente_id, NEW.empresa_id, v_perc;
  END IF;

  NEW.valor_hora  := ROUND(v_preco::numeric, 2);
  NEW.valor_total := ROUND(COALESCE(NEW.horas_trabalhadas, 0) * COALESCE(NEW.valor_hora, 0), 2);

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_hh_lancamentos_calc"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_hh_sync_apontamento"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_apontamento_id uuid;
BEGIN
  -- Buscar apontamento existente vinculado a este HH
  SELECT id INTO v_apontamento_id
  FROM public.apontamentos_horas
  WHERE hh_lancamento_id = NEW.id
  LIMIT 1;
  
  IF v_apontamento_id IS NULL THEN
    -- Criar novo apontamento (somente total, sem horários)
    INSERT INTO public.apontamentos_horas (
      tenant_id,
      empresa_id,
      os_id,
      colaborador_id,
      data,
      horas,
      gerado_por_hh,
      hh_lancamento_id,
      status,
      hora_entrada_1,
      hora_saida_1,
      hora_entrada_2,
      hora_saida_2
    ) VALUES (
      NEW.tenant_id,
      NEW.empresa_id,
      NEW.os_id,
      NEW.colaborador_id,
      NEW.data,
      NEW.horas_trabalhadas,
      true,
      NEW.id,
      'lancado',
      NULL,  -- Sem horários, somente total
      NULL,
      NULL,
      NULL
    );
  ELSE
    -- Atualizar apontamento existente
    UPDATE public.apontamentos_horas
    SET
      colaborador_id = NEW.colaborador_id,
      data = NEW.data,
      horas = NEW.horas_trabalhadas,
      status = 'lancado'
    WHERE id = v_apontamento_id;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_hh_sync_apontamento"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_importacao_xml__itens_auto_cadastrar_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") RETURNS "public"."item_finalidade"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
  select coalesce(
    (select p.itens_auto_cadastrar_finalidades
       from public.parametro_importacao_xml p
      where p.tenant_id = p_tenant_id
        and p.empresa_id = p_empresa_id
        and p.deleted_at is null
      limit 1),
    array['materia_prima'::public.item_finalidade]
  );
$$;


ALTER FUNCTION "public"."fn_importacao_xml__itens_auto_cadastrar_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_importacao_xml__itens_vincular_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") RETURNS "public"."item_finalidade"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
  select coalesce(
    (select p.itens_vincular_finalidades
       from public.parametro_importacao_xml p
      where p.tenant_id = p_tenant_id
        and p.empresa_id = p_empresa_id
        and p.deleted_at is null
      limit 1),
    array['materia_prima'::public.item_finalidade]
  );
$$;


ALTER FUNCTION "public"."fn_importacao_xml__itens_vincular_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_nf_entrada_sync_estoque_df"("p_nf_entrada_id" bigint) RETURNS TABLE("status" "text", "message" "text", "documento_fiscal_id" "uuid", "movs_criadas" integer, "df_itens_criados" integer, "df_impostos_criados" integer)
    LANGUAGE "plpgsql"
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_df_id uuid;

  v_movs int := 0;
  v_df_itens int := 0;
  v_df_impostos int := 0;

  v_has_empresa_df_item boolean := false;
  v_has_created_at_df_item boolean := false;
  v_has_updated_at_df_item boolean := false;

  v_has_empresa_df_imp boolean := false;
  v_has_created_at_df_imp boolean := false;
  v_has_updated_at_df_imp boolean := false;

  sql_text text;
  v_rc int := 0;
begin
  select * into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada não encontrada (id=%)', p_nf_entrada_id;
  end if;

  v_df_id := f.fn_ensure_documento_fiscal_from_nf_entrada(v_nf.id);

  -- =========================================================
  -- 1) MOVIMENTAÇÃO: SOMENTE se NÃO for imobilizado (ENUM safe)
  -- =========================================================
  if v_nf.finalidade_contexto is distinct from 'imobilizado'::item_finalidade then
    insert into public.movimentacoes (
      item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao,
      custo_unitario_bruto, custo_unitario_real,
      credito_icms, credito_pis, credito_cofins,
      origem_nf_entrada_id, origem_os_id,
      v_ipi, v_icms, v_pis, v_cofins, v_frete_rateado,
      tenant_id, empresa_id, created_at
    )
    select
      i.item_id,
      'entrada',
      i.qtd,
      'NF_ENTRADA',
      'sistema',
      (v_nf.data_emissao at time zone 'America/Sao_Paulo')::timestamp,
      coalesce(i.v_unit,0),
      coalesce(i.v_unit,0),
      coalesce(i.v_icms,0),
      coalesce(i.v_pis,0),
      coalesce(i.v_cofins,0),
      v_nf.id,
      v_nf.os_id,
      coalesce(i.v_ipi,0),
      coalesce(i.v_icms,0),
      coalesce(i.v_pis,0),
      coalesce(i.v_cofins,0),
      0,
      v_nf.tenant_id,
      v_nf.empresa_id,
      now()
    from public.nf_entrada_itens i
    where i.nf_entrada_id = v_nf.id
      and i.item_id is not null
      and not exists (
        select 1
        from public.movimentacoes m
        where m.tenant_id = v_nf.tenant_id
          and m.empresa_id = v_nf.empresa_id
          and m.origem_nf_entrada_id = v_nf.id
          and m.item_id = i.item_id
          and m.tipo = 'entrada'
      );

    get diagnostics v_rc = row_count;
    v_movs := v_rc;
  end if;

  -- =========================================================
  -- 2) DF ITENS (BLINDADO: descricao nunca nula/vazia)
  -- =========================================================
  select exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name='documento_fiscal_item' and column_name='empresa_id'
  ) into v_has_empresa_df_item;

  select exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name='documento_fiscal_item' and column_name='created_at'
  ) into v_has_created_at_df_item;

  select exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name='documento_fiscal_item' and column_name='updated_at'
  ) into v_has_updated_at_df_item;

  sql_text :=
    'insert into f.documento_fiscal_item (' ||
    'id, tenant_id' ||
    case when v_has_empresa_df_item then ', empresa_id' else '' end ||
    ', documento_fiscal_id, item_n, codigo, descricao, ncm, cfop, quantidade, unidade, valor_unitario, valor_total' ||
    case when v_has_created_at_df_item then ', created_at' else '' end ||
    case when v_has_updated_at_df_item then ', updated_at' else '' end ||
    ') ' ||
    'select gen_random_uuid(), ne.tenant_id' ||
    case when v_has_empresa_df_item then ', ne.empresa_id' else '' end ||
    ', df.id, row_number() over (order by i.id),' ||

    -- codigo blindado (evita vazio)
    'coalesce(nullif(btrim(i.codigo_fornecedor),''''), i.item_id::text),' ||

    -- descricao blindada + maiúsculo (evita NULL/blank)
    'coalesce(nullif(upper(btrim(i.descricao)),''''), upper(''ITEM '' || coalesce(nullif(btrim(i.codigo_fornecedor),''''), i.item_id::text))),' ||

    ' i.ncm, i.cfop, i.qtd, ''UN'', i.v_unit, i.v_prod' ||
    case when v_has_created_at_df_item then ', now()' else '' end ||
    case when v_has_updated_at_df_item then ', now()' else '' end ||
    ' from public.nf_entrada ne' ||
    ' join f.documento_fiscal df on df.tenant_id = ne.tenant_id and df.chave_acesso = ne.chave' ||
    ' join public.nf_entrada_itens i on i.nf_entrada_id = ne.id' ||
    ' where ne.id = ' || v_nf.id ||
    ' and not exists (select 1 from f.documento_fiscal_item x where x.tenant_id = ne.tenant_id and x.documento_fiscal_id = df.id)';

  execute sql_text;
  get diagnostics v_rc = row_count;
  v_df_itens := v_rc;

  -- =========================================================
  -- 3) DF IMPOSTOS (igual ao que já está funcionando pra você)
  -- =========================================================
  select exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name='documento_fiscal_imposto' and column_name='empresa_id'
  ) into v_has_empresa_df_imp;

  select exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name='documento_fiscal_imposto' and column_name='created_at'
  ) into v_has_created_at_df_imp;

  select exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name='documento_fiscal_imposto' and column_name='updated_at'
  ) into v_has_updated_at_df_imp;

  for sql_text in
    select unnest(array[
      -- ICMS
      'insert into f.documento_fiscal_imposto (id, tenant_id' ||
        case when v_has_empresa_df_imp then ', empresa_id' else '' end ||
        ', documento_fiscal_id, imposto, natureza, base_original, deducoes, base_calculo, aliquota, valor_calculado, valor_ajustado' ||
        case when v_has_created_at_df_imp then ', created_at' else '' end ||
        case when v_has_updated_at_df_imp then ', updated_at' else '' end ||
      ') ' ||
      'select gen_random_uuid(), ne.tenant_id' ||
        case when v_has_empresa_df_imp then ', ne.empresa_id' else '' end ||
      ', df.id, ''ICMS'', ''CREDITO'', sum(i.v_prod), 0, sum(i.v_prod),' ||
      ' case when sum(i.v_prod) > 0 then round((sum(coalesce(i.v_icms,0)) / sum(i.v_prod)) * 100, 4) else 0 end,' ||
      ' sum(coalesce(i.v_icms,0)), 0' ||
        case when v_has_created_at_df_imp then ', now()' else '' end ||
        case when v_has_updated_at_df_imp then ', now()' else '' end ||
      ' from public.nf_entrada ne' ||
      ' join f.documento_fiscal df on df.tenant_id=ne.tenant_id and df.chave_acesso=ne.chave' ||
      ' join public.nf_entrada_itens i on i.nf_entrada_id=ne.id' ||
      ' where ne.id=' || v_nf.id ||
      ' and not exists (select 1 from f.documento_fiscal_imposto x where x.tenant_id=ne.tenant_id and x.documento_fiscal_id=df.id and x.imposto=''ICMS'')' ||
      ' group by ne.tenant_id' || (case when v_has_empresa_df_imp then ', ne.empresa_id' else '' end) || ', df.id' ||
      ' having sum(coalesce(i.v_icms,0)) > 0',

      -- PIS
      'insert into f.documento_fiscal_imposto (id, tenant_id' ||
        case when v_has_empresa_df_imp then ', empresa_id' else '' end ||
        ', documento_fiscal_id, imposto, natureza, base_original, deducoes, base_calculo, aliquota, valor_calculado, valor_ajustado' ||
        case when v_has_created_at_df_imp then ', created_at' else '' end ||
        case when v_has_updated_at_df_imp then ', updated_at' else '' end ||
      ') ' ||
      'select gen_random_uuid(), ne.tenant_id' ||
        case when v_has_empresa_df_imp then ', ne.empresa_id' else '' end ||
      ', df.id, ''PIS'', ''CREDITO'', sum(i.v_prod), 0, sum(i.v_prod),' ||
      ' case when sum(i.v_prod) > 0 then round((sum(coalesce(i.v_pis,0)) / sum(i.v_prod)) * 100, 4) else 0 end,' ||
      ' sum(coalesce(i.v_pis,0)), 0' ||
        case when v_has_created_at_df_imp then ', now()' else '' end ||
        case when v_has_updated_at_df_imp then ', now()' else '' end ||
      ' from public.nf_entrada ne' ||
      ' join f.documento_fiscal df on df.tenant_id=ne.tenant_id and df.chave_acesso=ne.chave' ||
      ' join public.nf_entrada_itens i on i.nf_entrada_id=ne.id' ||
      ' where ne.id=' || v_nf.id ||
      ' and not exists (select 1 from f.documento_fiscal_imposto x where x.tenant_id=ne.tenant_id and x.documento_fiscal_id=df.id and x.imposto=''PIS'')' ||
      ' group by ne.tenant_id' || (case when v_has_empresa_df_imp then ', ne.empresa_id' else '' end) || ', df.id' ||
      ' having sum(coalesce(i.v_pis,0)) > 0',

      -- COFINS
      'insert into f.documento_fiscal_imposto (id, tenant_id' ||
        case when v_has_empresa_df_imp then ', empresa_id' else '' end ||
        ', documento_fiscal_id, imposto, natureza, base_original, deducoes, base_calculo, aliquota, valor_calculado, valor_ajustado' ||
        case when v_has_created_at_df_imp then ', created_at' else '' end ||
        case when v_has_updated_at_df_imp then ', updated_at' else '' end ||
      ') ' ||
      'select gen_random_uuid(), ne.tenant_id' ||
        case when v_has_empresa_df_imp then ', ne.empresa_id' else '' end ||
      ', df.id, ''COFINS'', ''CREDITO'', sum(i.v_prod), 0, sum(i.v_prod),' ||
      ' case when sum(i.v_prod) > 0 then round((sum(coalesce(i.v_cofins,0)) / sum(i.v_prod)) * 100, 4) else 0 end,' ||
      ' sum(coalesce(i.v_cofins,0)), 0' ||
        case when v_has_created_at_df_imp then ', now()' else '' end ||
        case when v_has_updated_at_df_imp then ', now()' else '' end ||
      ' from public.nf_entrada ne' ||
      ' join f.documento_fiscal df on df.tenant_id=ne.tenant_id and df.chave_acesso=ne.chave' ||
      ' join public.nf_entrada_itens i on i.nf_entrada_id=ne.id' ||
      ' where ne.id=' || v_nf.id ||
      ' and not exists (select 1 from f.documento_fiscal_imposto x where x.tenant_id=ne.tenant_id and x.documento_fiscal_id=df.id and x.imposto=''COFINS'')' ||
      ' group by ne.tenant_id' || (case when v_has_empresa_df_imp then ', ne.empresa_id' else '' end) || ', df.id' ||
      ' having sum(coalesce(i.v_cofins,0)) > 0'
    ])
  loop
    execute sql_text;
    get diagnostics v_rc = row_count;
    v_df_impostos := v_df_impostos + v_rc;
  end loop;

  status := 'ok';
  message := 'Sync concluído: DF itens/impostos (estoque só quando aplicável).';
  documento_fiscal_id := v_df_id;
  movs_criadas := v_movs;
  df_itens_criados := v_df_itens;
  df_impostos_criados := v_df_impostos;
  return next;
end;
$$;


ALTER FUNCTION "public"."fn_nf_entrada_sync_estoque_df"("p_nf_entrada_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_normalize_documento"("p_doc" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select regexp_replace(coalesce(p_doc, ''), '[^0-9]', '', 'g');
$$;


ALTER FUNCTION "public"."fn_normalize_documento"("p_doc" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_ordens_servico_validate_hh"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_cliente_habilita_hh boolean;
begin
  -- Se não tem cliente, não pode marcar HH
  if new.cliente_id is null then
    new.usa_relatorio_hh := false;
    return new;
  end if;

  -- Se não está marcada como HH, ok
  if coalesce(new.usa_relatorio_hh, false) = false then
    return new;
  end if;

  -- Se marcou HH, valida se o cliente permite HH
  select c.habilita_hh
    into v_cliente_habilita_hh
  from public.clientes c
  where c.id = new.cliente_id
    and c.tenant_id = new.tenant_id
    and c.empresa_id = new.empresa_id;

  if coalesce(v_cliente_habilita_hh, false) = false then
    raise exception
      'Cliente % não está habilitado para HH (clientes.habilita_hh=false). Não é permitido salvar OS com usa_relatorio_hh=true.',
      new.cliente_id
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."fn_ordens_servico_validate_hh"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fn_ordens_servico_validate_hh"() IS 'Bloqueia OS HH (usa_relatorio_hh=true) quando o cliente não tem habilita_hh=true. SECURITY DEFINER com row_security=off para não depender de RLS em clientes.';



CREATE OR REPLACE FUNCTION "public"."fn_percentual_por_data"("p_data" "date") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT CASE EXTRACT(DOW FROM p_data)
    WHEN 0 THEN 100
    WHEN 6 THEN 50
    ELSE 0
  END;
$$;


ALTER FUNCTION "public"."fn_percentual_por_data"("p_data" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_regerar_parcelas_titulo_from_xml"("p_nf_entrada_id" bigint, "p_titulo_id" "uuid") RETURNS TABLE("status" "text", "message" "text", "parcelas_criadas" integer, "total_parcelas" numeric)
    LANGUAGE "plpgsql"
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_xml xml;

  v_vnf numeric(15,2);

  v_dup_nodes xml[];
  v_count int;
  i int;

  v_nDup text;
  v_dVenc date;
  v_vDup numeric(15,2);

  v_sum numeric(15,2) := 0;
begin
  select * into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'nf_entrada % não encontrada', p_nf_entrada_id;
  end if;

  if v_nf.xml_raw is null or nullif(btrim(v_nf.xml_raw), '') is null then
    raise exception 'nf_entrada % sem xml_raw', p_nf_entrada_id;
  end if;

  v_xml := xmlparse(document v_nf.xml_raw);

  v_vnf :=
    coalesce(
      nullif((xpath('string(//*[local-name()="ICMSTot"]/*[local-name()="vNF"])', v_xml))[1]::text,'')::numeric,
      v_nf.valor_total,
      0
    );

  -- dup nodes
  v_dup_nodes := xpath('//*[local-name()="cobr"]/*[local-name()="dup"]', v_xml);
  v_count := coalesce(array_length(v_dup_nodes, 1), 0);

  -- soft delete parcelas atuais
  update f.titulo_parcela
     set deleted_at = now()
   where tenant_id = v_nf.tenant_id
     and titulo_id = p_titulo_id
     and deleted_at is null;

  if v_count = 0 then
    -- sem duplicata: 1 parcela única
    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (
      v_nf.tenant_id,
      p_titulo_id,
      '001',
      (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
      v_vnf,
      v_vnf
    );

    v_sum := v_vnf;
    parcelas_criadas := 1;
  else
    -- com duplicata: usa XPaths "absolutos" dentro do fragmento <dup>
    for i in 1..v_count loop
      v_nDup := nullif((xpath('string(//*[local-name()="nDup"])', v_dup_nodes[i]))[1]::text, '');
      v_nDup := coalesce(v_nDup, lpad(i::text, 3, '0'));

      v_dVenc := nullif((xpath('string(//*[local-name()="dVenc"])', v_dup_nodes[i]))[1]::text, '')::date;
      v_dVenc := coalesce(v_dVenc, (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date);

      v_vDup := nullif((xpath('string(//*[local-name()="vDup"])', v_dup_nodes[i]))[1]::text, '')::numeric;
      v_vDup := coalesce(v_vDup, 0);

      insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
      values (v_nf.tenant_id, p_titulo_id, v_nDup, v_dVenc, v_vDup, v_vDup);

      v_sum := v_sum + v_vDup;
    end loop;

    parcelas_criadas := v_count;
  end if;

  -- Ajusta aberto do título se estiver zerado (caso típico do seu bug)
  update f.titulo
     set valor_aberto = case
                          when coalesce(valor_aberto,0) = 0 and v_sum > 0 then v_sum
                          else valor_aberto
                        end,
         updated_at = now()
   where id = p_titulo_id
     and tenant_id = v_nf.tenant_id
     and deleted_at is null;

  status := 'ok';
  message := format('Parcelas regeneradas do XML. count=%s sum=%s', parcelas_criadas, v_sum);
  total_parcelas := v_sum;
  return next;
end;
$$;


ALTER FUNCTION "public"."fn_regerar_parcelas_titulo_from_xml"("p_nf_entrada_id" bigint, "p_titulo_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_set_fator_aplicado"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_fator numeric(6,3);
begin
  -- Se não informou tipo, assume fator 1.000
  if new.tipo_hora_id is null then
    -- só seta se estiver null, ou se mudou o tipo (para manter coerência)
    if new.fator_aplicado is null or (tg_op = 'UPDATE' and new.tipo_hora_id is distinct from old.tipo_hora_id) then
      new.fator_aplicado := 1.000;
    end if;
    return new;
  end if;

  select fator into v_fator
  from public.tipos_horas
  where id = new.tipo_hora_id
    and ativo = true;

  -- Se não achar (tipo inativo/excluído), assume 1.000
  if v_fator is null then
    v_fator := 1.000;
  end if;

  -- Regra:
  -- - Se fator_aplicado está null, preenche.
  -- - Se UPDATE e mudou tipo_hora_id, recalcula o fator_aplicado.
  if new.fator_aplicado is null
     or (tg_op = 'UPDATE' and new.tipo_hora_id is distinct from old.tipo_hora_id) then
    new.fator_aplicado := v_fator;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."fn_set_fator_aplicado"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_set_horas_from_periodos"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_horas numeric;
  v_info text;
BEGIN
  -- Se não usou períodos (modo antigo), não mexe
  IF NEW.hora_entrada_1 IS NULL
     AND NEW.hora_saida_1 IS NULL
     AND NEW.hora_entrada_2 IS NULL
     AND NEW.hora_saida_2 IS NULL THEN
    RETURN NEW;
  END IF;

  -- Se começou a usar, exige os 4 preenchidos
  IF NEW.hora_entrada_1 IS NULL OR NEW.hora_saida_1 IS NULL
     OR NEW.hora_entrada_2 IS NULL OR NEW.hora_saida_2 IS NULL THEN
    RAISE EXCEPTION 'Preencha Entrada 1, Saída 1, Entrada 2 e Saída 2 para calcular horas.';
  END IF;

  v_horas := public.fn_calc_horas_periodos(
    NEW.hora_entrada_1, NEW.hora_saida_1,
    NEW.hora_entrada_2, NEW.hora_saida_2
  );

  NEW.horas := v_horas;

  -- Opcional: anexa string de horários na descricao, sem destruir o que já existe
  v_info := format(
    'Horários: %s-%s / %s-%s',
    to_char(NEW.hora_entrada_1, 'HH24:MI'),
    to_char(NEW.hora_saida_1,   'HH24:MI'),
    to_char(NEW.hora_entrada_2, 'HH24:MI'),
    to_char(NEW.hora_saida_2,   'HH24:MI')
  );

  IF NEW.descricao IS NULL OR btrim(NEW.descricao) = '' THEN
    NEW.descricao := v_info;
  ELSIF position('Horários:' in NEW.descricao) = 0 THEN
    NEW.descricao := NEW.descricao || ' | ' || v_info;
  END IF;

  RETURN NEW;
END $$;


ALTER FUNCTION "public"."fn_set_horas_from_periodos"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_validar_apontamento_horas"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_status text;
  v_taxa numeric(10,2);
begin
  -- 1) Validar status da OS (bloqueia concluída/cancelada)
  select status into v_status
  from public.ordens_servico
  where id = new.os_id;

  if v_status is null then
    raise exception 'OS % não encontrada.', new.os_id;
  end if;

  if v_status in ('concluida', 'cancelada') then
    raise exception 'Não é permitido lançar horas: OS % está com status "%".', new.os_id, v_status;
  end if;

  -- 2) Se foi gerado por HH, não exigir taxa do colaborador (HH não depende de colaborador_taxas)
  if coalesce(new.gerado_por_hh, false) = true then
    return new;
  end if;

  -- 3) Validar existência de taxa vigente na data do apontamento (fluxo de apontamento normal)
  select t.valor_hora into v_taxa
  from public.colaborador_taxas t
  where t.colaborador_id = new.colaborador_id
    and new.data >= t.vigencia_inicio
    and (t.vigencia_fim is null or new.data <= t.vigencia_fim)
  order by t.vigencia_inicio desc, t.criado_em desc
  limit 1;

  if v_taxa is null then
    raise exception
      'Não é permitido lançar horas: colaborador % não possui taxa vigente em %.',
      new.colaborador_id, new.data;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."fn_validar_apontamento_horas"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_xml_strip_default_namespace"("p_xml_raw" "text") RETURNS "xml"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select xmlparse(document
    regexp_replace(
      regexp_replace(coalesce(p_xml_raw,''), 'xmlns(:\w+)?="[^"]+"', '', 'g'),
      '</?\w+:(\w+)', '<\1', 'g'
    )
  );
$$;


ALTER FUNCTION "public"."fn_xml_strip_default_namespace"("p_xml_raw" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gerar_relatorio_hh_os"("p_os_id" integer, "p_periodo_inicio" "date", "p_periodo_fim" "date") RETURNS TABLE("relatorio_id" bigint, "total" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tenant_id uuid;
  v_cliente_id bigint;
  v_tabela_hh_id bigint;
  v_relatorio_id bigint;
  v_total numeric := 0;
  v_ano int;
  v_missing_apontamento_id text;
  v_missing_valor_apontamento_id text;
BEGIN
  -- 1) Tenant obrigatorio
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant nao definido (current_tenant_id retornou null).';
  END IF;

  IF p_periodo_inicio IS NULL OR p_periodo_fim IS NULL THEN
    RAISE EXCEPTION 'Periodo inicio e fim sao obrigatorios.';
  END IF;

  IF p_periodo_inicio > p_periodo_fim THEN
    RAISE EXCEPTION 'Periodo inicio maior que periodo fim.';
  END IF;

  -- 2) Descobrir cliente da OS
  SELECT os.cliente_id
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = p_os_id
    AND os.tenant_id = v_tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % nao encontrada ou sem cliente vinculado.', p_os_id;
  END IF;

  -- 3) Descobrir tabela HH ativa do cliente para o ano do periodo
  v_ano := EXTRACT(YEAR FROM p_periodo_inicio)::int;
  SELECT t.id
    INTO v_tabela_hh_id
  FROM public.cliente_hh_tabela t
  WHERE t.tenant_id = v_tenant_id
    AND t.cliente_id = v_cliente_id
    AND t.ano = v_ano
    AND t.ativo = true
  ORDER BY t.criado_em DESC
  LIMIT 1;

  IF v_tabela_hh_id IS NULL THEN
    RAISE EXCEPTION 'Tabela HH ativa nao encontrada para cliente % no ano %.', v_cliente_id, v_ano;
  END IF;

  -- 4) Nao recalcular se ja existir relatorio fechado para a mesma OS e periodo
  IF EXISTS (
    SELECT 1
    FROM public.os_relatorios_hh r
    WHERE r.tenant_id = v_tenant_id
      AND r.os_id = p_os_id
      AND r.periodo_inicio = p_periodo_inicio
      AND r.periodo_fim = p_periodo_fim
      AND r.status = 'fechado'
  ) THEN
    RAISE EXCEPTION 'Relatorio HH ja fechado para OS % no periodo % a %.', p_os_id, p_periodo_inicio, p_periodo_fim;
  END IF;

  -- 5) Cria cabecalho (status fechado) com total 0 (sera atualizado no fim)
  INSERT INTO public.os_relatorios_hh (
    tenant_id,
    os_id,
    cliente_id,
    tabela_hh_id,
    periodo_inicio,
    periodo_fim,
    data_emissao,
    status,
    total
  ) VALUES (
    v_tenant_id,
    p_os_id,
    v_cliente_id,
    v_tabela_hh_id,
    p_periodo_inicio,
    p_periodo_fim,
    current_date,
    'fechado',
    0
  )
  RETURNING id INTO v_relatorio_id;

  -- 6) Validar especialidade: se nao houver, aborta com erro claro
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  )
  SELECT b.apontamento_id
    INTO v_missing_apontamento_id
  FROM base b
  WHERE b.especialidade_id IS NULL
  LIMIT 1;

  IF v_missing_apontamento_id IS NOT NULL THEN
    RAISE EXCEPTION 'Apontamento % sem especialidade (hh_especialidade_id).', v_missing_apontamento_id;
  END IF;

  -- 7) Validar valor_base da tabela HH para cada especialidade
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  ), enriched AS (
    SELECT
      b.*,
      ti.valor_base
    FROM base b
    LEFT JOIN public.cliente_hh_tabela_itens ti
      ON ti.tabela_hh_id = v_tabela_hh_id
     AND ti.hh_especialidade_id = b.especialidade_id
  )
  SELECT e.apontamento_id
    INTO v_missing_valor_apontamento_id
  FROM enriched e
  WHERE e.valor_base IS NULL
  LIMIT 1;

  IF v_missing_valor_apontamento_id IS NOT NULL THEN
    RAISE EXCEPTION 'Valor base nao encontrado na tabela HH para o apontamento %.', v_missing_valor_apontamento_id;
  END IF;

  -- 8) Inserir linhas (snapshot) com calculos financeiros
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  ), enriched AS (
    SELECT
      b.*,
      he.descricao AS especialidade_descricao,
      ti.valor_base,
      COALESCE(b.fator_aplicado, b.tipo_hora_fator, 1) AS fator_final
    FROM base b
    JOIN public.hh_especialidades he ON he.id = b.especialidade_id
    JOIN public.cliente_hh_tabela_itens ti
      ON ti.tabela_hh_id = v_tabela_hh_id
     AND ti.hh_especialidade_id = b.especialidade_id
  )
  INSERT INTO public.os_relatorios_hh_linhas (
    tenant_id,
    relatorio_id,
    colaborador_id,
    data,
    entrada_1,
    saida_1,
    entrada_2,
    saida_2,
    horas_trabalhadas,
    fator,
    tipo_hora_codigo,
    especialidade_descricao,
    valor_hora_base,
    valor_hora_aplicado,
    total
  )
  SELECT
    v_tenant_id,
    v_relatorio_id,
    e.colaborador_id,
    e.data,
    e.entrada_1,
    e.saida_1,
    e.entrada_2,
    e.saida_2,
    e.horas_trabalhadas,
    e.fator_final,
    e.tipo_hora_codigo,
    e.especialidade_descricao,
    e.valor_base,
    (e.valor_base * e.fator_final) AS valor_hora_aplicado,
    ROUND(e.horas_trabalhadas * (e.valor_base * e.fator_final), 2) AS total
  FROM enriched e;

  -- 9) Atualizar total no cabecalho (arredondamento financeiro)
  SELECT COALESCE(ROUND(SUM(l.total), 2), 0)
    INTO v_total
  FROM public.os_relatorios_hh_linhas l
  WHERE l.relatorio_id = v_relatorio_id;

  UPDATE public.os_relatorios_hh
     SET total = v_total
   WHERE id = v_relatorio_id;

  -- 10) Retorna id e total
  RETURN QUERY SELECT v_relatorio_id, v_total;
END;
$$;


ALTER FUNCTION "public"."gerar_relatorio_hh_os"("p_os_id" integer, "p_periodo_inicio" "date", "p_periodo_fim" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_default_empresa_id"("p_tenant_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select e.id
  from public.empresas e
  where e.tenant_id = p_tenant_id
    and e.ativo = true
  order by e.criado_em asc nulls last
  limit 1;
$$;


ALTER FUNCTION "public"."get_default_empresa_id"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_default_tenant_id"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  tenant_id uuid;
  has_created_at boolean;
  has_criado_em boolean;
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'tenants'
  ) then
    raise exception 'Tabela tenants nao encontrada.';
  end if;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'tenants'
      and column_name = 'created_at'
  ) into has_created_at;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'tenants'
      and column_name = 'criado_em'
  ) into has_criado_em;

  if has_criado_em then
    execute 'select id from public.tenants order by criado_em asc nulls last limit 1'
      into tenant_id;
  elsif has_created_at then
    execute 'select id from public.tenants order by created_at asc nulls last limit 1'
      into tenant_id;
  else
    execute 'select id from public.tenants limit 1'
      into tenant_id;
  end if;

  if tenant_id is null then
    raise exception 'Nenhum tenant encontrado.';
  end if;

  return tenant_id;
end;
$$;


ALTER FUNCTION "public"."get_default_tenant_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_full_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_empresa_papel text;
  v_perm_extra jsonb;
  v_perm_negadas jsonb;
  base_perms jsonb := '{}'::jsonb;
  extra_perms jsonb := '{}'::jsonb;
  result_perms jsonb;
begin
  select u.id into v_usuario_id
  from a.usuario u
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return '{}'::jsonb;
  end if;

  select ut.papel into v_tenant_papel
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  limit 1;

  if v_tenant_papel is null then
    return '{}'::jsonb;
  end if;

  select jsonb_object_agg(rp.permission, true) into base_perms
  from public.role_permissions rp
  where rp.role = a.fn_map_papel_tenant_to_role(v_tenant_papel);

  base_perms := coalesce(base_perms, '{}'::jsonb);

  select ue.papel, ue.permissoes_extra, ue.permissoes_negadas
    into v_empresa_papel, v_perm_extra, v_perm_negadas
  from a.usuario_empresa ue
  where ue.usuario_id = v_usuario_id
    and ue.empresa_id = p_empresa_id
    and ue.ativo = true
    and ue.deleted_at is null
  limit 1;

  if v_empresa_papel is null then
    return base_perms;
  end if;

  -- módulo preferencial por papel empresa
  extra_perms := extra_perms || jsonb_build_object(
    'modulo_preferencial',
    (
      case upper(coalesce(v_empresa_papel,''))
        when 'ADMIN' then 'admin'
        when 'FINANCEIRO' then 'financeiro'
        when 'COORDENACAO' then 'projetos'
        when 'COMPRAS' then 'estoque'
        when 'ALMOXARIFADO' then 'estoque'
        when 'APONTAMENTO_RH' then 'projetos'
        else null
      end
    )
  );

  -- GARANTIA: permissões mínimas OS
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COORDENACAO') then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true,
      'os.delete', true
    );
  elsif upper(coalesce(v_empresa_papel,'')) = 'APONTAMENTO_RH' then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true
    );
  end if;

  -- FINANCEIRO / FATURAMENTO
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO') then
    extra_perms := extra_perms || jsonb_build_object(
      'financeiro.read', true,
      'financeiro.write', true,
      'faturamento.read', true,
      'faturamento.write', true,
      'faturamento.nfe.import_xml', true
    );
  end if;

  -- ESTOQUE READ
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('estoque.read', true);
  end if;

  -- ESTOQUE WRITE
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO') then
    extra_perms := extra_perms || jsonb_build_object('estoque.write', true);
  end if;

  -- IMOBILIZADO
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.read', true);
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.write', true);
  end if;

  -- XML IMPORT
  if upper(coalesce(v_empresa_papel,'')) in ('ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO','FINANCEIRO') then
    extra_perms := extra_perms || jsonb_build_object(
      'xml_import.execute', true,
      'nf_entrada.import', true,
      'cad_fornecedores.write', true,
      'cad_itens.write', true
    );
  end if;

  -- extras/negadas do usuário
  if v_perm_extra is not null then
    extra_perms := extra_perms || v_perm_extra;
  end if;

  result_perms := base_perms || extra_perms;

  if v_perm_negadas is not null then
    result_perms := result_perms - (select array_agg(key) from jsonb_object_keys(v_perm_negadas) as key);
  end if;

  return coalesce(result_perms, '{}'::jsonb);
end;
$$;


ALTER FUNCTION "public"."get_full_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_hh_tipo_id_for_tenant"("p_tenant_id" "uuid") RETURNS bigint
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_hh_tipo_id BIGINT;
BEGIN
  -- Busca primeiro mapeamento ativo para o tenant
  SELECT hh_tipo_id INTO v_hh_tipo_id
  FROM public.hh_tipos_mapping
  WHERE tenant_id = p_tenant_id AND ativo = true
  LIMIT 1;
  
  RETURN v_hh_tipo_id;
END;
$$;


ALTER FUNCTION "public"."get_hh_tipo_id_for_tenant"("p_tenant_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_hh_tipo_id_for_tenant"("p_tenant_id" "uuid") IS 'Resolve hh_tipo_id padrÃ£o para um tenant baseado em tipos_horas';



CREATE OR REPLACE FUNCTION "public"."get_my_active_tenant"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.current_tenant_id()
$$;


ALTER FUNCTION "public"."get_my_active_tenant"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_permissions"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  
  if v_tenant_id is null or v_empresa_id is null then
    return '{}'::jsonb;
  end if;
  
  return public.get_full_permissions(v_tenant_id, v_empresa_id);
end;
$$;


ALTER FUNCTION "public"."get_my_permissions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid") RETURNS TABLE("permission" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
  select e.key as permission
  from jsonb_each(public.get_full_permissions(p_tenant_id, public.current_empresa_id())) e
  where e.value = 'true'::jsonb;
$$;


ALTER FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") RETURNS TABLE("permission" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'a'
    AS $$
  select e.key
  from jsonb_each(public.get_full_permissions(p_tenant_id, p_empresa_id)) e
  where e.value = 'true'::jsonb;
$$;


ALTER FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_roles"() RETURNS TABLE("role" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select distinct r.name as role
  from public.tenant_memberships tm
  join public.membership_roles mr on mr.membership_id = tm.id
  join public.roles r on r.id = mr.role_id
  where tm.user_id = auth.uid()
    and tm.status = 'active'
    and tm.tenant_id = public.current_tenant_id()
  order by r.name
$$;


ALTER FUNCTION "public"."get_my_roles"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles (id, email, nome)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nome', new.raw_user_meta_data->>'name')
  )
  on conflict (id) do update
    set email = excluded.email,
        nome = excluded.nome;
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_permission"("p_code" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
  select exists (
    select 1
    from public.v_user_permissions v
    where v.tenant_id = public.current_tenant_id()
      and v.permission = p_code
  );
$$;


ALTER FUNCTION "public"."has_permission"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."import_nf_entrada"("p_empresa_id" "uuid", "p_finalidade_contexto" "public"."item_finalidade", "p_fornecedor_id" bigint, "p_itens_json" "jsonb", "p_nf_json" "jsonb", "p_tenant_id" "uuid", "p_xml_raw" "text", "p_gerar_contas_pagar" boolean DEFAULT false, "p_parcelas_json" "jsonb" DEFAULT NULL::"jsonb", "p_os_id" integer DEFAULT NULL::integer, "p_baixar_os" boolean DEFAULT false, "p_motivo_compra_id" "uuid" DEFAULT NULL::"uuid", "p_solicitante_usuario_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("status" "text", "message" "text", "nf_entrada_id" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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

  -- Itens
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

  -- Log se faltar XML
  v_xml_trim := nullif(btrim(coalesce(p_xml_raw,'')), '');
  if v_xml_trim is null then
    insert into public.xml_import_errors (tenant_id, documento_fiscal_id, tipo, detalhe, created_at, updated_at)
    values (p_tenant_id, null, 'NF_ENTRADA', 'Importado sem XML (xml_raw ausente).', now(), now())
    on conflict (tenant_id, documento_fiscal_id, tipo) do update
      set detalhe = excluded.detalhe,
          updated_at = now(),
          resolved_at = null;
  end if;

  -- Financeiro novo (f.*)
  if not (public.can('financeiro','write') or public.can('financeiro','config')) then
    raise exception 'Sem permissao para gerar contas a pagar';
  end if;

  perform 1 from public.fn_fix_nf_entrada_pos_import(v_nf_id);

  -- ===== OS (AGORA: ignora item_id null e respeita finalidades permitidas) =====
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
        and i.deleted_at is null;

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


ALTER FUNCTION "public"."import_nf_entrada"("p_empresa_id" "uuid", "p_finalidade_contexto" "public"."item_finalidade", "p_fornecedor_id" bigint, "p_itens_json" "jsonb", "p_nf_json" "jsonb", "p_tenant_id" "uuid", "p_xml_raw" "text", "p_gerar_contas_pagar" boolean, "p_parcelas_json" "jsonb", "p_os_id" integer, "p_baixar_os" boolean, "p_motivo_compra_id" "uuid", "p_solicitante_usuario_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."import_nf_entrada"("p_empresa_id" "uuid", "p_finalidade_contexto" "public"."item_finalidade", "p_fornecedor_id" bigint, "p_itens_json" "jsonb", "p_nf_json" "jsonb", "p_tenant_id" "uuid", "p_xml_raw" "text", "p_gerar_contas_pagar" boolean, "p_parcelas_json" "jsonb", "p_os_id" integer, "p_baixar_os" boolean, "p_motivo_compra_id" "uuid", "p_solicitante_usuario_id" "uuid") IS 'Padrao do ERP: importacao de NF-e ENTRADA SEMPRE gera Contas a Pagar. Parametro p_gerar_contas_pagar mantido apenas por compatibilidade e e ignorado.';



CREATE OR REPLACE FUNCTION "public"."import_nf_entrada_v2"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_chave_acesso" "text", "p_numero" "text", "p_serie" "text", "p_emissao_date" "date", "p_competencia_date" "date", "p_valor_total" numeric, "p_fornecedor_nome" "text", "p_fornecedor_documento" "text", "p_gerar_titulo" boolean, "p_vencimento_date" "date", "p_plano_contas_id" "uuid", "p_centro_custo_id" "uuid" DEFAULT NULL::"uuid", "p_os_id" integer DEFAULT NULL::integer, "p_observacoes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_fornecedor_id integer;
  v_doc_id uuid;
  v_titulo_id uuid;
begin
  if coalesce(nullif(trim(p_chave_acesso),''),'') = '' then
    raise exception 'Chave de acesso é obrigatória.';
  end if;

  -- Fornecedor por CNPJ/CPF (consolidado)
  v_fornecedor_id := public.fn_fornecedor_upsert_por_documento(
    p_tenant_id,
    p_fornecedor_nome,
    p_fornecedor_documento
  );

  -- Documento fiscal (upsert por chave)
  insert into f.documento_fiscal (
    tenant_id,
    empresa_id,
    tipo,
    chave_acesso,
    fornecedor_id,
    emissao_date,
    competencia_date,
    valor_total,
    status,
    observacoes
  ) values (
    p_tenant_id,
    p_empresa_id,
    'NF_ENTRADA',
    p_chave_acesso,
    v_fornecedor_id,
    p_emissao_date,
    p_competencia_date,
    coalesce(p_valor_total, 0),
    'IMPORTADO',
    p_observacoes
  )
  on conflict (tenant_id, chave_acesso)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    observacoes = excluded.observacoes,
    updated_at = now()
  returning id into v_doc_id;

  -- Se não for gerar título, terminou aqui
  if not p_gerar_titulo then
    return v_doc_id;
  end if;

  -- CLASSIFICAÇÃO OBRIGATÓRIA daqui pra frente
  if p_plano_contas_id is null then
    raise exception 'Classificação (Plano de Contas) é obrigatória para gerar o título.';
  end if;

  if p_vencimento_date is null then
    raise exception 'Vencimento é obrigatório para gerar o título.';
  end if;

  -- Título (Contas a Pagar = tipo AP)
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
    valor_aberto
  ) values (
    p_tenant_id,
    p_empresa_id,
    'AP',
    'PENDENTE',
    'XML',
    v_fornecedor_id,
    v_doc_id,
    concat('NF-e ', coalesce(p_numero,''), '/', coalesce(p_serie,'')),
    p_emissao_date,
    p_competencia_date,
    coalesce(p_valor_total,0),
    coalesce(p_valor_total,0)
  )
  returning id into v_titulo_id;

  -- Parcela única
  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    status
  ) values (
    p_tenant_id,
    v_titulo_id,
    1,
    p_vencimento_date,
    coalesce(p_valor_total,0),
    'ABERTA'
  );

  -- Rateio (classificação / plano de contas)
  insert into f.titulo_rateio (
    tenant_id,
    empresa_id,
    titulo_id,
    plano_contas_id,
    centro_custo_id,
    os_id,
    valor
  ) values (
    p_tenant_id,
    p_empresa_id,
    v_titulo_id,
    p_plano_contas_id,
    p_centro_custo_id,
    p_os_id,
    coalesce(p_valor_total,0)
  );

  return v_doc_id;
end $$;


ALTER FUNCTION "public"."import_nf_entrada_v2"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_chave_acesso" "text", "p_numero" "text", "p_serie" "text", "p_emissao_date" "date", "p_competencia_date" "date", "p_valor_total" numeric, "p_fornecedor_nome" "text", "p_fornecedor_documento" "text", "p_gerar_titulo" boolean, "p_vencimento_date" "date", "p_plano_contas_id" "uuid", "p_centro_custo_id" "uuid", "p_os_id" integer, "p_observacoes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."import_nfse_saida"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nfse_json" "jsonb", "p_xml_raw" "text") RETURNS TABLE("status" "text", "message" "text", "documento_fiscal_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'f', 'a'
    AS $_$
#variable_conflict use_column
declare
  v_numero text;
  v_serie text;
  v_prestador_cnpj text;
  v_tomador_documento text;

  v_prestador_digits text;
  v_tomador_digits text;
  v_chave_acesso text;

  v_emissao_date date;
  v_competencia_date date;

  v_valor_servicos numeric(15,2);
  v_valor_deducoes numeric(15,2);
  v_valor_inss numeric(15,2);
  v_valor_iss numeric(15,2);
  v_valor_iss_retido numeric(15,2);
  v_base_calculo numeric(15,2);
  v_aliquota numeric(7,4);
  v_valor_liquido numeric(15,2);
  v_valor_total numeric(15,2);

  v_iss_retido_raw text;
  v_iss_retido boolean;

  v_discriminacao text;
  v_municipio_codigo text;
  v_codigo_verificacao text;

  v_tomador_razao_social text;
  v_tomador_nome_fantasia text;
  v_tomador_email text;
  v_tomador_telefone text;

  v_end_logradouro text;
  v_end_numero text;
  v_end_complemento text;
  v_end_bairro text;
  v_end_cidade text;
  v_end_uf text;
  v_end_cep text;
  v_endereco_full text;

  v_cliente_id integer;
  v_df_id uuid;
  v_existing_df_id uuid;
  v_inserted boolean;

  v_has_doc_key boolean;
  v_has_razao_social boolean;
  v_has_nome_fantasia boolean;
  v_has_email_financeiro boolean;
  v_has_contato_email boolean;
  v_has_contato_nome boolean;
  v_has_contato_telefone boolean;
  v_has_cep boolean;
  v_has_logradouro boolean;
  v_has_numero_endereco boolean;
  v_has_complemento boolean;
  v_has_bairro boolean;
  v_has_cidade boolean;
  v_has_uf boolean;
  v_has_pais boolean;

  v_extra_valor_pis numeric(15,2);
  v_extra_valor_cofins numeric(15,2);
  v_extra_valor_ir numeric(15,2);
  v_extra_valor_csll numeric(15,2);

  v_sql text;
begin
  begin
    if auth.uid() is null then
      raise exception 'Nao autenticado';
    end if;

    if p_tenant_id is null then
      raise exception 'tenant_id obrigatorio';
    end if;
    if p_empresa_id is null then
      raise exception 'empresa_id obrigatorio';
    end if;
    if p_nfse_json is null then
      raise exception 'p_nfse_json obrigatorio';
    end if;

    -- Contexto tenant/empresa para RLS + public.can()/current_*()
    perform set_config('app.tenant_id', p_tenant_id::text, true);
    perform set_config('app.current_empresa_id', p_empresa_id::text, true);

    if not exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = p_tenant_id
        and tm.status in ('active','ativo')
    ) then
      raise exception 'Tenant nao autorizado';
    end if;

    if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'empresas') then
      if not exists (
        select 1
        from public.empresas e
        where e.id = p_empresa_id
          and e.tenant_id = p_tenant_id
          and e.ativo = true
      ) then
        raise exception 'Empresa nao encontrada para este tenant';
      end if;
    end if;

    if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'empresa_memberships') then
      if not exists (
        select 1
        from public.empresa_memberships em
        where em.user_id = auth.uid()
          and em.tenant_id = p_tenant_id
          and em.empresa_id = p_empresa_id
          and em.status = 'active'
      ) then
        raise exception 'Sem acesso a esta empresa';
      end if;
    end if;

    if not (
      public.can('xml_import','execute')
      or public.can('xml_import_faturamento','execute')
    ) then
      raise exception 'Sem permissao para importar XML';
    end if;

    -- Campos obrigatórios
    v_numero := nullif(trim(coalesce(p_nfse_json->>'numero','')), '');
    v_serie := nullif(trim(coalesce(p_nfse_json->>'serie','')), '');
    v_prestador_cnpj := nullif(trim(coalesce(p_nfse_json->>'prestador_cnpj', p_nfse_json#>>'{prestador,cnpj}')), '');
    v_tomador_documento := nullif(trim(coalesce(p_nfse_json->>'tomador_documento', p_nfse_json#>>'{tomador,documento}')), '');

    if v_numero is null then
      raise exception 'numero obrigatorio';
    end if;
    if v_serie is null then
      raise exception 'serie obrigatoria';
    end if;
    if v_prestador_cnpj is null then
      raise exception 'prestador_cnpj obrigatorio';
    end if;
    if v_tomador_documento is null then
      raise exception 'tomador_documento obrigatorio';
    end if;

    v_prestador_digits := regexp_replace(v_prestador_cnpj, '\\D', '', 'g');
    v_tomador_digits := regexp_replace(v_tomador_documento, '\\D', '', 'g');

    if v_prestador_digits is null or length(v_prestador_digits) = 0 then
      raise exception 'prestador_cnpj invalido';
    end if;
    if v_tomador_digits is null or length(v_tomador_digits) = 0 then
      raise exception 'tomador_documento invalido';
    end if;

    -- NFSe não tem chave 44; criar determinística por tenant
    v_chave_acesso := 'NFSE:' || v_prestador_digits || ':' || v_serie || ':' || v_numero;

    -- Hard guarantee against duplicates:
    -- serialize by (tenant_id + chave_acesso) and reject if already imported.
    perform pg_advisory_xact_lock(hashtext(p_tenant_id::text || ':' || v_chave_acesso)::bigint);

    select df.id into v_existing_df_id
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id
      and df.chave_acesso = v_chave_acesso
      and df.operacao = 'SAIDA'
      and df.natureza = 'SERVICO'
      and df.modelo = 'NFSE'
      and df.deleted_at is null
    limit 1;

    if v_existing_df_id is not null then
      raise exception 'NFSe ja importada (chave %)', v_chave_acesso;
    end if;

    -- Datas
    if nullif(p_nfse_json->>'data_emissao', '') is not null then
      v_emissao_date := (p_nfse_json->>'data_emissao')::timestamptz::date;
    end if;

    if nullif(p_nfse_json->>'competencia_date', '') is not null then
      v_competencia_date := date_trunc('month', (p_nfse_json->>'competencia_date')::date)::date;
    elsif nullif(p_nfse_json->>'competencia', '') is not null then
      v_competencia_date := date_trunc('month', ((p_nfse_json->>'competencia') || '-01')::date)::date;
    elsif v_emissao_date is not null then
      v_competencia_date := date_trunc('month', v_emissao_date)::date;
    end if;

    -- Valores (default 0)
    v_valor_servicos := coalesce(nullif(p_nfse_json#>>'{valores,valor_servicos}', '')::numeric, 0);
    v_valor_deducoes := coalesce(nullif(p_nfse_json#>>'{valores,valor_deducoes}', '')::numeric, 0);
    v_valor_inss := coalesce(nullif(p_nfse_json#>>'{valores,valor_inss}', '')::numeric, 0);

    v_valor_iss := coalesce(nullif(p_nfse_json#>>'{valores,valor_iss}', '')::numeric, 0);
    v_valor_iss_retido := coalesce(nullif(p_nfse_json#>>'{valores,valor_iss_retido}', '')::numeric, 0);
    v_base_calculo := coalesce(nullif(p_nfse_json#>>'{valores,base_calculo}', '')::numeric, 0);
    v_aliquota := coalesce(nullif(p_nfse_json#>>'{valores,aliquota}', '')::numeric, 0);
    v_valor_liquido := nullif(p_nfse_json#>>'{valores,valor_liquido}', '')::numeric;

    v_valor_total := coalesce(v_valor_liquido, v_valor_servicos, 0);

    -- Flags / outros campos
    v_iss_retido_raw := nullif(p_nfse_json#>>'{valores,iss_retido}', '');
    v_iss_retido := coalesce(v_iss_retido_raw in ('1','true','TRUE','t','T','sim','SIM','S','s'), false);

    v_discriminacao := nullif(coalesce(p_nfse_json->>'discriminacao', p_nfse_json#>>'{servico,discriminacao}'), '');
    v_municipio_codigo := nullif(coalesce(
      p_nfse_json->>'municipio_codigo',
      p_nfse_json->>'nfse_municipio_codigo',
      p_nfse_json#>>'{orgao_gerador,codigo_municipio}',
      p_nfse_json#>>'{servico,codigo_municipio}'
    ), '');
    v_codigo_verificacao := nullif(coalesce(p_nfse_json->>'codigo_verificacao', p_nfse_json->>'nfse_codigo_verificacao'), '');

    -- Tomador (cliente)
    v_tomador_razao_social := nullif(p_nfse_json#>>'{tomador,razao_social}', '');
    v_tomador_nome_fantasia := nullif(p_nfse_json#>>'{tomador,nome_fantasia}', '');
    v_tomador_email := nullif(coalesce(p_nfse_json#>>'{tomador,email}', p_nfse_json#>>'{tomador,contato,email}'), '');
    v_tomador_telefone := nullif(coalesce(p_nfse_json#>>'{tomador,telefone}', p_nfse_json#>>'{tomador,contato,telefone}'), '');

    v_end_logradouro := nullif(p_nfse_json#>>'{tomador,endereco,logradouro}', '');
    v_end_numero := nullif(p_nfse_json#>>'{tomador,endereco,numero}', '');
    v_end_complemento := nullif(p_nfse_json#>>'{tomador,endereco,complemento}', '');
    v_end_bairro := nullif(p_nfse_json#>>'{tomador,endereco,bairro}', '');
    v_end_cidade := nullif(coalesce(p_nfse_json#>>'{tomador,endereco,cidade}', p_nfse_json#>>'{tomador,endereco,municipio}'), '');
    v_end_uf := nullif(p_nfse_json#>>'{tomador,endereco,uf}', '');
    v_end_cep := nullif(p_nfse_json#>>'{tomador,endereco,cep}', '');

    v_endereco_full := nullif(trim(concat_ws(', ',
      nullif(v_end_logradouro,''),
      nullif(v_end_numero,''),
      nullif(v_end_complemento,''),
      nullif(v_end_bairro,''),
      nullif(v_end_cidade,''),
      nullif(v_end_uf,''),
      nullif(v_end_cep,'')
    )), '');

    -- Descobrir se temos colunas opcionais em clientes (bases mais antigas podem não ter)
    select exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='clientes' and column_name='documento_key'
    ) into v_has_doc_key;

    -- Lookup cliente por documento
    v_cliente_id := null;
    if v_has_doc_key then
      select c.id into v_cliente_id
      from public.clientes c
      where c.tenant_id = p_tenant_id
        and c.empresa_id = p_empresa_id
        and c.documento_key = public.fn_documento_key(v_tomador_digits)
      limit 1;
    else
      select c.id into v_cliente_id
      from public.clientes c
      where c.tenant_id = p_tenant_id
        and c.empresa_id = p_empresa_id
        and regexp_replace(coalesce(c.documento,''), '\\D', '', 'g') = v_tomador_digits
      limit 1;
    end if;

    if v_cliente_id is null then
      insert into public.clientes(
        tenant_id,
        empresa_id,
        nome,
        documento,
        email,
        telefone,
        endereco,
        ativo,
        criado_em,
        atualizado_em
      ) values (
        p_tenant_id,
        p_empresa_id,
        upper(coalesce(v_tomador_nome_fantasia, v_tomador_razao_social, 'CLIENTE')),
        v_tomador_digits,
        v_tomador_email,
        v_tomador_telefone,
        v_endereco_full,
        true,
        now(),
        now()
      ) returning id into v_cliente_id;
    else
      update public.clientes
      set nome = upper(coalesce(v_tomador_nome_fantasia, v_tomador_razao_social, nome)),
          documento = coalesce(v_tomador_digits, documento),
          email = coalesce(v_tomador_email, email),
          telefone = coalesce(v_tomador_telefone, telefone),
          endereco = coalesce(v_endereco_full, endereco),
          ativo = true,
          atualizado_em = now()
      where id = v_cliente_id;
    end if;

    -- Best-effort: popular colunas extras em clientes quando existirem
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='razao_social') into v_has_razao_social;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='nome_fantasia') into v_has_nome_fantasia;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='email_financeiro') into v_has_email_financeiro;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='contato_email') into v_has_contato_email;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='contato_nome') into v_has_contato_nome;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='contato_telefone') into v_has_contato_telefone;

    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='cep') into v_has_cep;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='logradouro') into v_has_logradouro;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='numero_endereco') into v_has_numero_endereco;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='complemento') into v_has_complemento;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='bairro') into v_has_bairro;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='cidade') into v_has_cidade;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='uf') into v_has_uf;
    select exists (select 1 from information_schema.columns where table_schema='public' and table_name='clientes' and column_name='pais') into v_has_pais;

    if v_has_razao_social then
      execute 'update public.clientes set razao_social = upper($1) where id = $2'
      using coalesce(v_tomador_razao_social, v_tomador_nome_fantasia), v_cliente_id;
    end if;
    if v_has_nome_fantasia then
      execute 'update public.clientes set nome_fantasia = upper($1) where id = $2'
      using coalesce(v_tomador_nome_fantasia, v_tomador_razao_social), v_cliente_id;
    end if;
    if v_has_email_financeiro then
      execute 'update public.clientes set email_financeiro = coalesce($1, email_financeiro) where id = $2'
      using v_tomador_email, v_cliente_id;
    end if;
    if v_has_contato_email then
      execute 'update public.clientes set contato_email = coalesce($1, contato_email) where id = $2'
      using v_tomador_email, v_cliente_id;
    end if;
    if v_has_contato_nome then
      execute 'update public.clientes set contato_nome = coalesce($1, contato_nome) where id = $2'
      using nullif(p_nfse_json#>>'{tomador,contato,nome}', ''), v_cliente_id;
    end if;
    if v_has_contato_telefone then
      execute 'update public.clientes set contato_telefone = coalesce($1, contato_telefone) where id = $2'
      using v_tomador_telefone, v_cliente_id;
    end if;

    if v_has_cep then
      execute 'update public.clientes set cep = coalesce($1, cep) where id = $2'
      using v_end_cep, v_cliente_id;
    end if;
    if v_has_logradouro then
      execute 'update public.clientes set logradouro = coalesce($1, logradouro) where id = $2'
      using v_end_logradouro, v_cliente_id;
    end if;
    if v_has_numero_endereco then
      execute 'update public.clientes set numero_endereco = coalesce($1, numero_endereco) where id = $2'
      using v_end_numero, v_cliente_id;
    end if;
    if v_has_complemento then
      execute 'update public.clientes set complemento = coalesce($1, complemento) where id = $2'
      using v_end_complemento, v_cliente_id;
    end if;
    if v_has_bairro then
      execute 'update public.clientes set bairro = coalesce($1, bairro) where id = $2'
      using v_end_bairro, v_cliente_id;
    end if;
    if v_has_cidade then
      execute 'update public.clientes set cidade = coalesce($1, cidade) where id = $2'
      using v_end_cidade, v_cliente_id;
    end if;
    if v_has_uf then
      execute 'update public.clientes set uf = coalesce($1, uf) where id = $2'
      using v_end_uf, v_cliente_id;
    end if;
    if v_has_pais then
      execute 'update public.clientes set pais = coalesce($1, pais) where id = $2'
      using nullif(p_nfse_json#>>'{tomador,endereco,pais}', ''), v_cliente_id;
    end if;

    -- Insert documento_fiscal (NFSe SAIDA/SERVICO)
    insert into f.documento_fiscal(
      tenant_id,
      empresa_id,
      chave_acesso,
      operacao,
      natureza,
      modelo,
      serie,
      numero,
      emissao_date,
      competencia_date,
      cliente_id,
      valor_servicos,
      valor_total,
      nfse_municipio_codigo,
      nfse_codigo_verificacao,
      nfse_status,
      servico_discriminacao,
      updated_at
    ) values (
      p_tenant_id,
      p_empresa_id,
      v_chave_acesso,
      'SAIDA',
      'SERVICO',
      'NFSE',
      v_serie,
      v_numero,
      v_emissao_date,
      v_competencia_date,
      v_cliente_id,
      coalesce(v_valor_servicos, 0),
      coalesce(v_valor_total, 0),
      v_municipio_codigo,
      v_codigo_verificacao,
      'EMITIDA',
      v_discriminacao,
      now()
    )
    returning id into v_df_id;

    v_inserted := true;

    -- Upsert XML raw
    insert into f.documento_fiscal_xml(
      tenant_id,
      documento_fiscal_id,
      chave_acesso,
      xml_raw
    ) values (
      p_tenant_id,
      v_df_id,
      v_chave_acesso,
      coalesce(p_xml_raw, '')
    )
    on conflict (tenant_id, documento_fiscal_id) do update
      set chave_acesso = excluded.chave_acesso,
          xml_raw = excluded.xml_raw,
          deleted_at = null;

    -- Impostos / retenções
    -- Valores adicionais (se existirem no JSON)
    v_extra_valor_pis := coalesce(nullif(p_nfse_json#>>'{valores,valor_pis}', '')::numeric, 0);
    v_extra_valor_cofins := coalesce(nullif(p_nfse_json#>>'{valores,valor_cofins}', '')::numeric, 0);
    v_extra_valor_ir := coalesce(nullif(p_nfse_json#>>'{valores,valor_ir}', '')::numeric, 0);
    v_extra_valor_csll := coalesce(nullif(p_nfse_json#>>'{valores,valor_csll}', '')::numeric, 0);

    -- ISS
    if v_iss_retido or v_valor_iss_retido > 0 then
      if coalesce(v_valor_iss_retido, 0) > 0 then
        insert into f.documento_fiscal_imposto(
          tenant_id,
          documento_fiscal_id,
          imposto,
          natureza,
          base_original,
          deducoes,
          base_calculo,
          aliquota,
          valor_calculado,
          updated_at
        ) values (
          p_tenant_id,
          v_df_id,
          'ISS',
          'RETENCAO',
          coalesce(v_valor_servicos, 0),
          coalesce(v_valor_deducoes, 0),
          coalesce(v_base_calculo, 0),
          coalesce(v_aliquota, 0),
          coalesce(v_valor_iss_retido, 0),
          now()
        )
        on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
          set base_original = excluded.base_original,
              deducoes = excluded.deducoes,
              base_calculo = excluded.base_calculo,
              aliquota = excluded.aliquota,
              valor_calculado = excluded.valor_calculado,
              updated_at = now(),
              deleted_at = null;
      end if;

      -- Se veio retido, remove eventual ISS débito (best-effort)
      update f.documento_fiscal_imposto
      set deleted_at = now()
      where tenant_id = p_tenant_id
        and f.documento_fiscal_imposto.documento_fiscal_id = v_df_id
        and imposto = 'ISS'
        and natureza = 'DEBITO'
        and deleted_at is null;
    else
      if coalesce(v_valor_iss, 0) > 0 then
        insert into f.documento_fiscal_imposto(
          tenant_id,
          documento_fiscal_id,
          imposto,
          natureza,
          base_original,
          deducoes,
          base_calculo,
          aliquota,
          valor_calculado,
          updated_at
        ) values (
          p_tenant_id,
          v_df_id,
          'ISS',
          'DEBITO',
          coalesce(v_valor_servicos, 0),
          coalesce(v_valor_deducoes, 0),
          coalesce(v_base_calculo, 0),
          coalesce(v_aliquota, 0),
          coalesce(v_valor_iss, 0),
          now()
        )
        on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
          set base_original = excluded.base_original,
              deducoes = excluded.deducoes,
              base_calculo = excluded.base_calculo,
              aliquota = excluded.aliquota,
              valor_calculado = excluded.valor_calculado,
              updated_at = now(),
              deleted_at = null;
      end if;

      -- Se veio débito, remove eventual ISS retenção (best-effort)
      update f.documento_fiscal_imposto
      set deleted_at = now()
      where tenant_id = p_tenant_id
        and f.documento_fiscal_imposto.documento_fiscal_id = v_df_id
        and imposto = 'ISS'
        and natureza = 'RETENCAO'
        and deleted_at is null;
    end if;

    -- INSS (retenção)
    if coalesce(v_valor_inss, 0) > 0 then
      insert into f.documento_fiscal_imposto(
        tenant_id,
        documento_fiscal_id,
        imposto,
        natureza,
        base_original,
        deducoes,
        base_calculo,
        aliquota,
        valor_calculado,
        updated_at
      ) values (
        p_tenant_id,
        v_df_id,
        'INSS',
        'RETENCAO',
        coalesce(v_valor_servicos, 0),
        coalesce(v_valor_deducoes, 0),
        coalesce(v_base_calculo, 0),
        coalesce(v_aliquota, 0),
        coalesce(v_valor_inss, 0),
        now()
      )
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    -- PIS/COFINS/IR/CSLL (retenção padrão)
    if coalesce(v_extra_valor_pis, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'PIS','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_pis,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    if coalesce(v_extra_valor_cofins, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'COFINS','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_cofins,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    if coalesce(v_extra_valor_ir, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'IR','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_ir,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    if coalesce(v_extra_valor_csll, 0) > 0 then
      insert into f.documento_fiscal_imposto(tenant_id,documento_fiscal_id,imposto,natureza,base_original,deducoes,base_calculo,aliquota,valor_calculado,updated_at)
      values (p_tenant_id,v_df_id,'CSLL','RETENCAO',coalesce(v_valor_servicos,0),coalesce(v_valor_deducoes,0),coalesce(v_base_calculo,0),coalesce(v_aliquota,0),v_extra_valor_csll,now())
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza) do update
        set base_original = excluded.base_original,
            deducoes = excluded.deducoes,
            base_calculo = excluded.base_calculo,
            aliquota = excluded.aliquota,
            valor_calculado = excluded.valor_calculado,
            updated_at = now(),
            deleted_at = null;
    end if;

    status := 'ok';
    message := case when v_inserted then 'NFSe importada' else 'NFSe atualizada' end;
    documento_fiscal_id := v_df_id;
    return next;
    return;
  exception when others then
    status := 'error';
    message := sqlerrm;
    documento_fiscal_id := null;
    return next;
    return;
  end;
end;
$_$;


ALTER FUNCTION "public"."import_nfse_saida"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nfse_json" "jsonb", "p_xml_raw" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."itens_resolver_por_codigo"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_codigo" "text") RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  select i.id
  from public.itens i
  where i.tenant_id = p_tenant_id
    and i.empresa_id = p_empresa_id
    and i.ativo = true
    and i.mesclado_em_item_id is null
    and i.codigo_interno_sem_zeros = public.strip_zeros_esquerda(p_codigo)
  limit 1;
$$;


ALTER FUNCTION "public"."itens_resolver_por_codigo"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_codigo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jwt_claim"("claim" "text") RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select (current_setting('request.jwt.claims', true)::json ->> claim);
$$;


ALTER FUNCTION "public"."jwt_claim"("claim" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jwt_empresa_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select nullif(public.jwt_claim('empresa_id'), '')::uuid;
$$;


ALTER FUNCTION "public"."jwt_empresa_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jwt_tenant_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select nullif(public.jwt_claim('tenant_id'), '')::uuid;
$$;


ALTER FUNCTION "public"."jwt_tenant_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_user_empresas"("p_tenant_id" "text") RETURNS TABLE("id" bigint, "nome" "text", "nome_fantasia" "text", "razao_social" "text", "ativo" boolean, "criado_em" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.id,
    e.nome,
    e.nome_fantasia,
    e.razao_social,
    e.ativo,
    e.criado_em
  FROM empresas e
  INNER JOIN empresa_memberships em ON e.id = em.empresa_id
  WHERE em.tenant_id = p_tenant_id::BIGINT
    AND em.user_id = auth.uid()
    AND em.status = 'active'
    AND e.tenant_id = p_tenant_id::BIGINT
  ORDER BY e.criado_em ASC;
END;
$$;


ALTER FUNCTION "public"."list_user_empresas"("p_tenant_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_user_empresas"("p_tenant_id" "uuid") RETURNS TABLE("id" "uuid", "nome" "text", "ativo" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    e.id,
    COALESCE(e.nome_fantasia, e.razao_social, 'Empresa '||e.id::text) AS nome,
    e.ativo
  FROM public.empresas e
  WHERE e.tenant_id = p_tenant_id
    AND e.ativo = true
    AND EXISTS (
      -- User must be an active member of the tenant
      SELECT 1
      FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id = p_tenant_id
        AND tm.status = 'active'
    )
  ORDER BY e.criado_em ASC;
$$;


ALTER FUNCTION "public"."list_user_empresas"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_fornecedores"("p_keep_id" integer, "p_kill_id" integer) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $_$
begin
  if p_keep_id = p_kill_id then
    return;
  end if;

  -- Atualiza referências em f.titulo (contas a pagar)
  if to_regclass('f.titulo') is not null then
    execute '
      update f.titulo
         set fornecedor_id = $1
       where fornecedor_id = $2
    ' using p_keep_id, p_kill_id;
  end if;

  -- Se existirem outras tabelas com fornecedor_id, adicione aqui seguindo o mesmo padrão:
  -- if to_regclass('public.alguma_tabela') is not null then
  --   execute 'update public.alguma_tabela set fornecedor_id=$1 where fornecedor_id=$2'
  --   using p_keep_id, p_kill_id;
  -- end if;

  -- Apaga o duplicado
  delete from public.fornecedores
   where id = p_kill_id;

end;
$_$;


ALTER FUNCTION "public"."merge_fornecedores"("p_keep_id" integer, "p_kill_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_fornecedores"("p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  if p_keep_fornecedor_id = p_merge_fornecedor_id then
    raise exception 'keep e merge não podem ser iguais';
  end if;

  -- exemplos: ajuste conforme seu schema
  update public.contas_pagar_titulos
     set fornecedor_id = p_keep_fornecedor_id
   where fornecedor_id = p_merge_fornecedor_id;

  update public.contas_pagar_parcelas
     set fornecedor_id = p_keep_fornecedor_id
   where fornecedor_id = p_merge_fornecedor_id;

  -- se tiver NF entrada / compras etc, adicione aqui:
  -- update public.nf_entrada set fornecedor_id = p_keep_fornecedor_id where fornecedor_id = p_merge_fornecedor_id;

  delete from public.fornecedores
   where id = p_merge_fornecedor_id;
end;
$$;


ALTER FUNCTION "public"."merge_fornecedores"("p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_cnpj"("p" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select regexp_replace(coalesce(p,''), '\D', '', 'g');
$$;


ALTER FUNCTION "public"."normalize_cnpj"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_doc"("doc" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select nullif(regexp_replace(coalesce(doc,''), '[^0-9]', '', 'g'), '');
$$;


ALTER FUNCTION "public"."normalize_doc"("doc" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."os_sync_itens_from_nf_entrada"("p_nf_entrada_id" bigint) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_inserted int := 0;
begin
  select *
    into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if v_nf.id is null then
    raise exception 'NF não encontrada (id=%)', p_nf_entrada_id;
  end if;

  if v_nf.os_id is null then
    return 0; -- NF sem OS: nada a fazer
  end if;

  insert into public.os_itens (
    tenant_id, empresa_id, os_id,
    item_id, quantidade, valor_unitario, valor_total,
    desconto_percentual, desconto_valor, baixa_estoque,
    observacoes, criado_em
  )
  select
    v_nf.tenant_id, v_nf.empresa_id, v_nf.os_id,
    (ni.item_id)::int,
    round(ni.qtd, 3),
    round(ni.v_unit, 2),
    round(ni.v_prod, 2),
    0, 0,
    false, -- IMPORTANTe: não baixar estoque aqui (movimentação já pode existir)
    'IMPORT XML NF ' || v_nf.chave || ' NF_ITEM ' || ni.id::text,
    now()
  from public.nf_entrada_itens ni
  where ni.tenant_id = v_nf.tenant_id
    and ni.empresa_id = v_nf.empresa_id
    and ni.nf_entrada_id = v_nf.id
    and ni.item_id is not null
    and ni.qtd > 0
    and not exists (
      select 1
      from public.os_itens oi
      where oi.tenant_id = v_nf.tenant_id
        and oi.empresa_id = v_nf.empresa_id
        and oi.os_id = v_nf.os_id
        and oi.observacoes = ('IMPORT XML NF ' || v_nf.chave || ' NF_ITEM ' || ni.id::text)
    );

  get diagnostics v_inserted = row_count;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.tenant_id = v_nf.tenant_id
          and oi.empresa_id = v_nf.empresa_id
          and oi.os_id = v_nf.os_id
      ), 0),
      atualizado_em = now()
  where os.id = v_nf.os_id
    and os.tenant_id = v_nf.tenant_id
    and os.empresa_id = v_nf.empresa_id;

  return v_inserted;
end;
$$;


ALTER FUNCTION "public"."os_sync_itens_from_nf_entrada"("p_nf_entrada_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pick_fiscal_regra"("p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select r.id
  from public.fiscal_regras r
  where r.tenant_id = public.current_tenant_id()
    and r.empresa_id = public.current_empresa_id()
    and r.ativo = true

    -- "match" com coringas (null = aceita qualquer)
    and (r.ncm is null or r.ncm = p_ncm)
    and (r.cfop is null or r.cfop = p_cfop)
    and (r.cst_icms is null or r.cst_icms = p_cst_icms)
    and (r.cst_pis is null or r.cst_pis = p_cst_pis)
    and (r.cst_cofins is null or r.cst_cofins = p_cst_cofins)
    and (r.origem is null or r.origem = p_origem)
    and (r.tipo_item is null or r.tipo_item = p_tipo_item)

  order by
    -- 1) prioridade explícita
    r.prioridade asc,

    -- 2) mais específico ganha (quanto mais campos preenchidos, menor "score")
    (
      (case when r.ncm is null then 1 else 0 end) +
      (case when r.cfop is null then 1 else 0 end) +
      (case when r.cst_icms is null then 1 else 0 end) +
      (case when r.cst_pis is null then 1 else 0 end) +
      (case when r.cst_cofins is null then 1 else 0 end) +
      (case when r.origem is null then 1 else 0 end) +
      (case when r.tipo_item is null then 1 else 0 end)
    ) asc,

    r.atualizado_em desc
  limit 1;
$$;


ALTER FUNCTION "public"."pick_fiscal_regra"("p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pick_fiscal_regra_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select r.id
  from public.fiscal_regras r
  where r.tenant_id  = p_tenant
    and r.empresa_id = p_empresa
    and r.ativo = true

    and (r.ncm is null or r.ncm = p_ncm)
    and (r.cfop is null or r.cfop = p_cfop)
    and (r.cst_icms is null or r.cst_icms = p_cst_icms)
    and (r.cst_pis is null or r.cst_pis = p_cst_pis)
    and (r.cst_cofins is null or r.cst_cofins = p_cst_cofins)
    and (r.origem is null or r.origem = p_origem)
    and (r.tipo_item is null or r.tipo_item = p_tipo_item)

  order by
    coalesce(r.prioridade, 0) desc,
    r.atualizado_em desc
  limit 1;
$$;


ALTER FUNCTION "public"."pick_fiscal_regra_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_os_item_reverte_estoque"("p_os_item_id" integer, "p_realizado_por" "text" DEFAULT NULL::"text", "p_motivo" "text" DEFAULT NULL::"text", "p_empresa_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_item public.itens;
  v_row public.os_itens;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.can('os_rpcs','execute') then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  select *
    into v_row
  from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item da OS nao encontrado';
  end if;

  select *
    into v_item
  from public.itens
  where id = v_row.item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item invalido ou fora do tenant atual';
  end if;

  delete from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if coalesce(v_row.baixa_estoque, false)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque','write') or public.can('os_rpcs','execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'entrada',
      v_row.quantidade,
      coalesce(p_motivo, 'Estorno baixa OS ' || v_row.os_id),
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = v_row.os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant;
end;
$$;


ALTER FUNCTION "public"."remove_os_item_reverte_estoque"("p_os_item_id" integer, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_current_empresa"("p_empresa_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;
  if p_empresa_id is null then
    raise exception 'Empresa nao informada';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not exists (
    select 1
    from public.empresas e
    where e.id = p_empresa_id
      and e.tenant_id = v_tenant
      and e.ativo = true
  ) then
    raise exception 'Empresa invalida/inativa para este tenant';
  end if;

  if not exists (
    select 1
    from public.empresa_memberships em
    where em.tenant_id = v_tenant
      and em.empresa_id = p_empresa_id
      and em.user_id = auth.uid()
      and em.status = 'active'
  ) then
    raise exception 'Sem acesso a esta empresa';
  end if;

  insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
  values (auth.uid(), v_tenant, p_empresa_id)
  on conflict (user_id, tenant_id) do update
    set empresa_id = excluded.empresa_id,
        updated_at = now();

  perform set_config('app.current_empresa_id', p_empresa_id::text, true);
end;
$$;


ALTER FUNCTION "public"."set_current_empresa"("p_empresa_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_current_tenant"("p_tenant_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id nao informado';
  end if;

  if not (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = p_tenant_id
        and tm.status = 'active'
    )
    or
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and u.deleted_at is null
        and ut.deleted_at is null
        and ut.ativo = true
        and ut.tenant_id = p_tenant_id
    )
  ) then
    raise exception 'Usuário não é membro ativo deste tenant';
  end if;

  insert into public.user_tenant_context (user_id, tenant_id)
  values (auth.uid(), p_tenant_id)
  on conflict (user_id) do update
    set tenant_id = excluded.tenant_id,
        updated_at = now();
end
$$;


ALTER FUNCTION "public"."set_current_tenant"("p_tenant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" integer, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'a', 'f'
    SET "row_security" TO 'off'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_ok boolean;
begin
  -- Permissão: ADMIN do tenant OU papéis da empresa (os que importam)
  select (
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ut.tenant_id = v_tenant
        and ut.deleted_at is null
        and ut.ativo = true
        and ut.papel in ('OWNER','ADMIN')
    )
    or
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ue.empresa_id = v_empresa
        and ue.deleted_at is null
        and ue.ativo = true
        and ue.papel in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH')
    )
  ) into v_ok;

  if not v_ok then
    raise exception 'Sem permissão para alterar defaults de importação do fornecedor.';
  end if;

  -- Valida fornecedor no tenant/empresa do contexto
  if not exists (
    select 1
    from public.fornecedores f
    where f.id = p_fornecedor_id
      and f.tenant_id = v_tenant
      and f.empresa_id = v_empresa
  ) then
    raise exception 'Fornecedor inválido para o contexto atual.';
  end if;

  -- Valida motivo (se informado): mesmo tenant + ativo + não deletado
  if p_motivo_compra_id is not null then
    if not exists (
      select 1
      from f.motivo_compra mc
      where mc.id = p_motivo_compra_id
        and mc.tenant_id = v_tenant
        and mc.deleted_at is null
        and mc.ativo = true
        -- IMPORTAÇÃO XML (produtos): bloquear motivo de SERVIÇO
        and (
          -- se você já criou aplica_em:
          (mc.aplica_em in ('PRODUTO','AMBOS'))
        )
    ) then
      raise exception 'Motivo inválido (ou não permitido para importação de produtos).';
    end if;
  end if;

  update public.fornecedores
  set
    finalidade_padrao = p_finalidade,
    motivo_compra_padrao_id = p_motivo_compra_id,
    atualizado_em = now()
  where id = p_fornecedor_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;
end;
$$;


ALTER FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" integer, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" bigint, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  select f.tenant_id, f.empresa_id
    into v_tenant_id, v_empresa_id
  from public.fornecedores f
  where f.id = p_fornecedor_id
  limit 1;

  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Fornecedor nao encontrado';
  end if;

  -- Ensure the caller belongs to the same tenant/empresa.
  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = v_tenant_id
      and tm.status = 'active'
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if not exists (
    select 1
    from public.empresa_memberships em
    where em.user_id = auth.uid()
      and em.empresa_id = v_empresa_id
      and em.status = 'active'
  ) then
    raise exception 'Empresa nao autorizada';
  end if;

  -- Best-effort: set context so public.can(...) evaluates consistently.
  begin
    perform public.set_current_tenant(v_tenant_id);
  exception
    when undefined_function then
      null;
  end;

  begin
    perform public.set_current_empresa(v_empresa_id);
  exception
    when undefined_function then
      null;
  end;

  if not (
    public.can('xml_import','execute')
    or public.can('cad_fornecedores','write')
    or public.can('estoque','write')
  ) then
    raise exception 'Sem permissao.';
  end if;

  -- Optional validation: if f.motivo_compra exists, ensure the chosen motivo belongs to the same tenant.
  if p_motivo_compra_id is not null and to_regclass('f.motivo_compra') is not null then
    if not exists (
      select 1
      from f.motivo_compra m
      where m.id = p_motivo_compra_id
        and m.tenant_id = v_tenant_id
        and m.ativo = true
        and m.deleted_at is null
    ) then
      raise exception 'Motivo invalido para este tenant.';
    end if;
  end if;

  update public.fornecedores f
  set finalidade_padrao = p_finalidade,
      motivo_compra_padrao_id = p_motivo_compra_id,
      atualizado_em = now()
  where f.id = p_fornecedor_id;
end;
$$;


ALTER FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" bigint, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_tenant_id_colaborador_cliente_funcao"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Se tenant_id nÃ£o foi fornecido ou Ã© NULL, pega do contexto
  IF NEW.tenant_id IS NULL THEN
    NEW.tenant_id := public.current_tenant_id();
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_tenant_id_colaborador_cliente_funcao"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_tenant_id_colaborador_cliente_funcao"() IS 'Trigger function: preenche automaticamente tenant_id no INSERT de colaborador_cliente_funcao';



CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."strip_zeros_esquerda"("p" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case
    when p is null then null
    else coalesce(nullif(regexp_replace(trim(p), '^0+', ''), ''), '0')
  end;
$$;


ALTER FUNCTION "public"."strip_zeros_esquerda"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_nf_entrada_itens__enforce_item_finalidade_import"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
declare
  v_finalidade public.item_finalidade;
  v_allowed public.item_finalidade[];
begin
  if new.item_id is null then
    return new;
  end if;

  select i.finalidade
    into v_finalidade
  from public.itens i
  where i.id = new.item_id
    and i.tenant_id = new.tenant_id
    and i.empresa_id = new.empresa_id
    and i.deleted_at is null;

  -- se não achou ou não pertence ao tenant/empresa, desvincula
  if v_finalidade is null then
    new.item_id := null;
    return new;
  end if;

  v_allowed := public.fn_importacao_xml__itens_vincular_finalidades(new.tenant_id, new.empresa_id);

  if not (v_finalidade = any(v_allowed)) then
    new.item_id := null;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."tg_nf_entrada_itens__enforce_item_finalidade_import"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_nf_entrada_itens__fill_descricao"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_codigo text;
begin
  v_codigo := coalesce(nullif(btrim(new.codigo_fornecedor), ''), new.item_id::text);

  -- se veio descrição vazia/nula, cria fallback
  if new.descricao is null or btrim(new.descricao) = '' then
    if new.item_id is not null then
      new.descricao := upper('ITEM ' || v_codigo);
    else
      -- se nem item_id tem, ainda assim não deixamos em branco
      new.descricao := upper('ITEM');
    end if;
  else
    -- se veio preenchida, normaliza (texto funcional em MAIÚSCULO)
    new.descricao := upper(btrim(new.descricao));
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."tg_nf_entrada_itens__fill_descricao"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_block_nf_movimentacoes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- Bloqueia alterações/deleções de movimentos originados de NF
  if (coalesce(old.origem_nf_entrada_id, new.origem_nf_entrada_id) is not null) then
    raise exception 'Movimentação originada de NF não pode ser alterada/excluída. Use estorno.';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."trg_block_nf_movimentacoes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_fornecedores_force_gerar_cp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.gerar_contas_pagar_auto := true;
  return new;
end;
$$;


ALTER FUNCTION "public"."trg_fornecedores_force_gerar_cp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_itens_normalizar_codigos"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.codigo_interno is not null then
    new.codigo_interno := public.strip_zeros_esquerda(new.codigo_interno);
  end if;

  if new.codigo_fornecedor is not null then
    new.codigo_fornecedor := public.strip_zeros_esquerda(new.codigo_fornecedor);
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."trg_itens_normalizar_codigos"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_itens_sync_timestamps"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := COALESCE(NEW.created_at, now());
    NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);

    -- legado
    NEW.criado_em := COALESCE(NEW.criado_em, NEW.created_at::timestamp);
    NEW.atualizado_em := COALESCE(NEW.atualizado_em, NEW.updated_at::timestamp);
  ELSE
    NEW.updated_at := COALESCE(NEW.updated_at, now());
    NEW.atualizado_em := NEW.updated_at::timestamp;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_itens_sync_timestamps"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_nf_entrada_itens_sync_os_stmt"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  r record;
begin
  for r in (select distinct nf_entrada_id from new_rows) loop
    perform public.os_sync_itens_from_nf_entrada(r.nf_entrada_id);
  end loop;

  return null;
end;
$$;


ALTER FUNCTION "public"."trg_nf_entrada_itens_sync_os_stmt"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_nf_entrada_sync_os_itens"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- só tenta quando tem OS vinculada
  if new.os_id is not null then
    perform public.os_sync_itens_from_nf_entrada(new.id);
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."trg_nf_entrada_sync_os_itens"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_cliente_hh_servicos_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_cliente_hh_servicos_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_colaborador_cliente_funcao_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.atualizado_em = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_colaborador_cliente_funcao_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_timestamp"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_timestamp"() IS 'Trigger function para atualizar campo atualizado_em automaticamente';



CREATE OR REPLACE FUNCTION "public"."validate_apontamento_colaborador_contrato"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant_id uuid;
  v_cliente_id bigint;
  v_vinculo_exists boolean;
  v_usa_relatorio_hh boolean;
  v_os_num bigint;
  v_numero_os varchar;
begin
  v_tenant_id := new.tenant_id;

  -- Busca dados da OS (inclui o flag de HH)
  select
    os.cliente_id,
    os.usa_relatorio_hh,
    os.os_num,
    os.numero_os
  into
    v_cliente_id,
    v_usa_relatorio_hh,
    v_os_num,
    v_numero_os
  from public.ordens_servico os
  where os.id = new.os_id
    and os.tenant_id = v_tenant_id;

  -- Se não encontrou a OS, ou não é HH, NÃO valida vínculo (apontamento "normal")
  if v_usa_relatorio_hh is distinct from true then
    return new;
  end if;

  -- Se a OS não tem cliente_id, permite (validação opcional)
  if v_cliente_id is null then
    return new;
  end if;

  -- Verifica vínculo ativo do colaborador com o cliente
  select exists (
    select 1
    from public.colaborador_cliente_funcao
    where tenant_id = v_tenant_id
      and cliente_id = v_cliente_id
      and colaborador_id = new.colaborador_id
      and ativo = true
  ) into v_vinculo_exists;

  if not v_vinculo_exists then
    raise exception
      'Colaborador % não está vinculado ao contrato do cliente da OS % (id %). Cadastre o vínculo em Cadastros > Colaboradores × Cliente.',
      new.colaborador_id,
      coalesce(v_os_num::text, v_numero_os::text, new.os_id::text),
      new.os_id
      using errcode = '23503';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."validate_apontamento_colaborador_contrato"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."validate_apontamento_colaborador_contrato"() IS 'Valida vínculo do colaborador com o contrato do cliente SOMENTE quando a OS está em HH (usa_relatorio_hh=true).';



CREATE OR REPLACE FUNCTION "public"."validate_hh_lancamento"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_cliente_id bigint;
  v_servico_id bigint;
  v_ok_vinculo boolean;
  v_perc integer;
  v_preco numeric;
BEGIN
  -- 1) Percentual aplicado
  v_perc := COALESCE(NEW.percentual_aplicado, 0);

  -- 2) Se não há hh_servico_id, não validar vínculo (deixar RLS validar)
  IF NEW.hh_servico_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 3) Obter cliente_id da OS
  SELECT os.cliente_id
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = NEW.os_id
    AND os.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % sem cliente vinculado (cliente_id).', NEW.os_id;
  END IF;

  -- 4) CRÍTICO: Usar hh_servico_id, NÃO hh_tipo_id!
  v_servico_id := NEW.hh_servico_id;

  IF v_servico_id IS NULL OR v_servico_id <= 0 THEN
    RAISE EXCEPTION 'Serviço HH inválido no lançamento (hh_servico_id=%).', NEW.hh_servico_id;
  END IF;

  -- 5) Validar vínculo
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_cliente_funcao ccf
    WHERE ccf.tenant_id = NEW.tenant_id
      AND ccf.cliente_id = v_cliente_id
      AND ccf.colaborador_id = NEW.colaborador_id
      AND ccf.hh_servico_id = v_servico_id
      AND COALESCE(ccf.ativo, true) = true
  )
  INTO v_ok_vinculo;

  IF NOT v_ok_vinculo THEN
    RAISE EXCEPTION
      'Serviço HH % não está vinculado ao colaborador % para o cliente % (colaborador_cliente_funcao).',
      v_servico_id, NEW.colaborador_id, v_cliente_id;
  END IF;

  -- 6) Buscar e atualizar preço
  SELECT
    CASE
      WHEN v_perc = 0   THEN s.preco_base
      WHEN v_perc = 50  THEN s.preco_50
      WHEN v_perc = 100 THEN s.preco_100
      ELSE NULL
    END
  INTO v_preco
  FROM public.cliente_hh_servicos s
  WHERE s.tenant_id = NEW.tenant_id
    AND s.empresa_id = NEW.empresa_id
    AND s.cliente_id = v_cliente_id
    AND s.id = v_servico_id
    AND s.ativo = true
  LIMIT 1;

  IF v_preco IS NOT NULL THEN
    NEW.valor_hora := v_preco;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_hh_lancamento"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "a"."config_orcamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "margem_lucro_padrao_percent" numeric(7,4) DEFAULT 53 NOT NULL,
    "desconto_max_percent" numeric(7,4) DEFAULT 0 NOT NULL,
    "condicao_pagamento_padrao_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_config_orcamento__descmax_range" CHECK ((("desconto_max_percent" >= (0)::numeric) AND ("desconto_max_percent" <= (100)::numeric))),
    CONSTRAINT "ck_config_orcamento__margem_range" CHECK ((("margem_lucro_padrao_percent" >= (0)::numeric) AND ("margem_lucro_padrao_percent" <= (100)::numeric)))
);


ALTER TABLE "a"."config_orcamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "a"."usuario" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_user_id" "uuid" NOT NULL,
    "nome" "text" NOT NULL,
    "email" "text" NOT NULL,
    "telefone" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_usuario__email_lower" CHECK (("email" = "lower"("email"))),
    CONSTRAINT "ck_usuario__telefone_digits" CHECK ((("telefone" IS NULL) OR ("telefone" ~ '^[0-9]+$'::"text")))
);


ALTER TABLE "a"."usuario" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "a"."usuario_empresa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "usuario_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "papel" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "permissoes_extra" "jsonb",
    "permissoes_negadas" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_usuario_empresa__papel" CHECK (("papel" = ANY (ARRAY['ADMIN'::"text", 'FINANCEIRO'::"text", 'COORDENACAO'::"text", 'COMPRAS'::"text", 'ALMOXARIFADO'::"text", 'TECNICO'::"text", 'APONTAMENTO_RH'::"text", 'PAINEL_TV'::"text"])))
);


ALTER TABLE "a"."usuario_empresa" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "a"."usuario_tenant" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "usuario_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "papel" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_usuario_tenant__papel" CHECK (("papel" = ANY (ARRAY['OWNER'::"text", 'ADMIN'::"text", 'CONTADOR'::"text", 'GESTOR'::"text"])))
);


ALTER TABLE "a"."usuario_tenant" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."condicao_pagamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "acrescimo_percent" numeric(7,4) DEFAULT 0 NOT NULL,
    "dias" integer,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_condicao_pagamento__acrescimo_range" CHECK ((("acrescimo_percent" >= (0)::numeric) AND ("acrescimo_percent" <= (100)::numeric))),
    CONSTRAINT "ck_condicao_pagamento__codigo_not_blank" CHECK (("length"(TRIM(BOTH FROM "codigo")) > 0)),
    CONSTRAINT "ck_condicao_pagamento__dias_range" CHECK ((("dias" IS NULL) OR ("dias" >= 0))),
    CONSTRAINT "ck_condicao_pagamento__nome_not_blank" CHECK (("length"(TRIM(BOTH FROM "nome")) > 0))
);


ALTER TABLE "c"."condicao_pagamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."conjunto" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "categoria" "text",
    "descricao" "text",
    "precificacao" "text" DEFAULT 'SOMA_COMPONENTES'::"text" NOT NULL,
    "preco_fixo" numeric(15,2),
    "ativo" boolean DEFAULT true NOT NULL,
    "observacoes" "text",
    "codigo_norm" "text" NOT NULL,
    "nome_norm" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_conjunto__codigo_not_blank" CHECK (("length"(TRIM(BOTH FROM "codigo")) > 0)),
    CONSTRAINT "ck_conjunto__nome_not_blank" CHECK (("length"(TRIM(BOTH FROM "nome")) > 0)),
    CONSTRAINT "ck_conjunto__precificacao" CHECK (("precificacao" = ANY (ARRAY['SOMA_COMPONENTES'::"text", 'PRECO_FIXO'::"text"]))),
    CONSTRAINT "ck_conjunto__preco_fixo_required" CHECK ((("precificacao" <> 'PRECO_FIXO'::"text") OR (("preco_fixo" IS NOT NULL) AND ("preco_fixo" >= (0)::numeric))))
);


ALTER TABLE "c"."conjunto" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."conjunto_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "conjunto_id" "uuid" NOT NULL,
    "ordem" integer DEFAULT 1 NOT NULL,
    "item_id" integer NOT NULL,
    "quantidade" numeric(15,3) NOT NULL,
    "unidade" "text",
    "observacoes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_conjunto_item__ordem" CHECK (("ordem" >= 1)),
    CONSTRAINT "ck_conjunto_item__qtd" CHECK (("quantidade" > (0)::numeric))
);


ALTER TABLE "c"."conjunto_item" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."empresa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "razao_social" "text" NOT NULL,
    "nome_fantasia" "text" NOT NULL,
    "cnpj" "text",
    "email" "text",
    "telefone" "text",
    "site" "text",
    "observacao" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_empresa__cnpj_digits" CHECK ((("cnpj" IS NULL) OR ("cnpj" ~ '^[0-9]+$'::"text"))),
    CONSTRAINT "ck_empresa__codigo_not_blank" CHECK (("length"(TRIM(BOTH FROM "codigo")) > 0)),
    CONSTRAINT "ck_empresa__email_lower" CHECK ((("email" IS NULL) OR ("email" = "lower"("email")))),
    CONSTRAINT "ck_empresa__site_lower" CHECK ((("site" IS NULL) OR ("site" = "lower"("site")))),
    CONSTRAINT "ck_empresa__telefone_digits" CHECK ((("telefone" IS NULL) OR ("telefone" ~ '^[0-9]+$'::"text")))
);


ALTER TABLE "c"."empresa" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."empresa_endereco" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "cep" "text" NOT NULL,
    "logradouro" "text" NOT NULL,
    "numero" "text" NOT NULL,
    "complemento" "text",
    "bairro" "text" NOT NULL,
    "cidade" "text" NOT NULL,
    "uf" character(2) NOT NULL,
    "codigo_municipio_ibge" "text",
    "pais" character(2) DEFAULT 'BR'::"bpchar" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_empresa_endereco__cep_digits" CHECK (("cep" ~ '^[0-9]+$'::"text")),
    CONSTRAINT "ck_empresa_endereco__ibge_digits" CHECK ((("codigo_municipio_ibge" IS NULL) OR ("codigo_municipio_ibge" ~ '^[0-9]+$'::"text"))),
    CONSTRAINT "ck_empresa_endereco__pais" CHECK (("pais" ~ '^[A-Z]{2}$'::"text")),
    CONSTRAINT "ck_empresa_endereco__tipo" CHECK (("tipo" = ANY (ARRAY['FISCAL'::"text", 'COBRANCA'::"text", 'ENTREGA'::"text", 'CORRESPONDENCIA'::"text"]))),
    CONSTRAINT "ck_empresa_endereco__uf" CHECK (("uf" ~ '^[A-Z]{2}$'::"text"))
);


ALTER TABLE "c"."empresa_endereco" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."empresa_fiscal" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "ie_isento" boolean DEFAULT false NOT NULL,
    "inscricao_estadual" "text",
    "inscricao_municipal" "text",
    "cnae_principal" "text",
    "regime_tributario" "text",
    "crt" smallint,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_empresa_fiscal__cnae_digits" CHECK ((("cnae_principal" IS NULL) OR ("cnae_principal" ~ '^[0-9]+$'::"text"))),
    CONSTRAINT "ck_empresa_fiscal__crt_range" CHECK ((("crt" IS NULL) OR (("crt" >= 1) AND ("crt" <= 4)))),
    CONSTRAINT "ck_empresa_fiscal__ie_digits" CHECK ((("inscricao_estadual" IS NULL) OR ("inscricao_estadual" ~ '^[0-9]+$'::"text"))),
    CONSTRAINT "ck_empresa_fiscal__ie_isento_regra" CHECK (((("ie_isento" = true) AND ("inscricao_estadual" IS NULL)) OR ("ie_isento" = false))),
    CONSTRAINT "ck_empresa_fiscal__im_digits" CHECK ((("inscricao_municipal" IS NULL) OR ("inscricao_municipal" ~ '^[0-9]+$'::"text")))
);


ALTER TABLE "c"."empresa_fiscal" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_caixa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "status" "text" DEFAULT 'DISPONIVEL'::"text" NOT NULL,
    "localizacao" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_i_caixa__status" CHECK (("status" = ANY (ARRAY['DISPONIVEL'::"text", 'COM_COLABORADOR'::"text", 'MANUTENCAO'::"text", 'BAIXADA'::"text"])))
);


ALTER TABLE "c"."i_caixa" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_caixa_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "caixa_id" "uuid" NOT NULL,
    "ferramenta_id" "uuid" NOT NULL,
    "quantidade" numeric(15,2) DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "c"."i_caixa_item" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_caixa_vinculo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "caixa_id" "uuid" NOT NULL,
    "colaborador_id" "uuid" NOT NULL,
    "data_inicio" timestamp with time zone DEFAULT "now"() NOT NULL,
    "data_fim" timestamp with time zone,
    "observacao" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "c"."i_caixa_vinculo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_ferramenta" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "ncm" "text",
    "unidade" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    "custo_unit" numeric(15,2) DEFAULT 0 NOT NULL,
    "custo_moeda" character(3) DEFAULT 'BRL'::"bpchar" NOT NULL,
    "custo_atualizado_em" timestamp with time zone,
    "categoria_id" "uuid"
);


ALTER TABLE "c"."i_ferramenta" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_ferramenta_categoria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "prefixo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "c"."i_ferramenta_categoria" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_ferramenta_codigo_seq" (
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "categoria_id" "uuid" NOT NULL,
    "proximo_numero" integer DEFAULT 1 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "c"."i_ferramenta_codigo_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_ferramenta_sugestao_xml" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "chave_nfe" "text",
    "nfe_numero" "text",
    "item_numero" integer,
    "fornecedor_nome" "text",
    "fornecedor_doc" "text",
    "descricao_xml" "text" NOT NULL,
    "ncm" "text",
    "unidade" "text",
    "qtd" numeric(15,2),
    "valor_unit" numeric(15,2),
    "valor_total" numeric(15,2),
    "status" "text" DEFAULT 'PENDENTE'::"text" NOT NULL,
    "ferramenta_id" "uuid",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_i_ferr_sug_xml__status" CHECK (("status" = ANY (ARRAY['PENDENTE'::"text", 'VINCULADA'::"text", 'CRIADA'::"text", 'IGNORADA'::"text"])))
);


ALTER TABLE "c"."i_ferramenta_sugestao_xml" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_ferramenta_unidade" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "ferramenta_id" "uuid" NOT NULL,
    "patrimonio_codigo" "text" NOT NULL,
    "status" "text" DEFAULT 'DISPONIVEL'::"text" NOT NULL,
    "localizacao" "text",
    "custo_aquisicao" numeric(15,2) DEFAULT 0 NOT NULL,
    "adquirido_em" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_i_ferr_unid__status" CHECK (("status" = ANY (ARRAY['DISPONIVEL'::"text", 'COM_COLABORADOR'::"text", 'MANUTENCAO'::"text", 'BAIXADA'::"text"])))
);


ALTER TABLE "c"."i_ferramenta_unidade" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."i_ferramenta_unidade_vinculo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "ferramenta_unidade_id" "uuid" NOT NULL,
    "colaborador_id" "uuid" NOT NULL,
    "data_inicio" timestamp with time zone DEFAULT "now"() NOT NULL,
    "data_fim" timestamp with time zone,
    "observacao" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "c"."i_ferramenta_unidade_vinculo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "c"."tenant" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_tenant__codigo_not_blank" CHECK (("length"(TRIM(BOTH FROM "codigo")) > 0)),
    CONSTRAINT "ck_tenant__nome_not_blank" CHECK (("length"(TRIM(BOTH FROM "nome")) > 0))
);


ALTER TABLE "c"."tenant" OWNER TO "postgres";


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



CREATE TABLE IF NOT EXISTS "public"."nf_entrada" (
    "id" bigint NOT NULL,
    "chave" character varying(60) NOT NULL,
    "numero" character varying(20),
    "serie" character varying(10),
    "emitente_nome" character varying(255),
    "emitente_cnpj" character varying(20),
    "data_emissao" timestamp with time zone,
    "valor_produtos" numeric(14,2) DEFAULT 0 NOT NULL,
    "valor_frete" numeric(14,2) DEFAULT 0 NOT NULL,
    "valor_total" numeric(14,2) DEFAULT 0 NOT NULL,
    "xml_raw" "text",
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fornecedor_id" bigint,
    "modelo" character varying(10),
    "valor_seguro" numeric(18,6) DEFAULT 0 NOT NULL,
    "valor_desconto" numeric(18,6) DEFAULT 0 NOT NULL,
    "valor_outros" numeric(18,6) DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "finalidade_contexto" "public"."item_finalidade",
    "os_id" integer,
    "baixa_os_automatica" boolean DEFAULT false NOT NULL,
    "motivo_compra_id" "uuid",
    "solicitante_usuario_id" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_nf_entrada__xml_raw_not_blank" CHECK ((("xml_raw" IS NULL) OR ("btrim"("xml_raw") <> ''::"text")))
);


ALTER TABLE "public"."nf_entrada" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."fornecedores" (
    "id" integer NOT NULL,
    "nome" character varying(255) NOT NULL,
    "documento" character varying(20),
    "email" character varying(120),
    "telefone" character varying(30),
    "endereco" "text",
    "observacoes" "text",
    "ativo" boolean DEFAULT true,
    "criado_em" timestamp without time zone DEFAULT "now"(),
    "atualizado_em" timestamp without time zone DEFAULT "now"(),
    "documento_norm" "text" GENERATED ALWAYS AS ("regexp_replace"((COALESCE("documento", ''::character varying))::"text", '\D'::"text", ''::"text", 'g'::"text")) STORED,
    "tenant_id" "uuid" NOT NULL,
    "finalidade_padrao" "public"."item_finalidade",
    "gerar_contas_pagar_auto" boolean DEFAULT true NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "cnpj" "text",
    "cnpj_norm" "text" GENERATED ALWAYS AS ("public"."normalize_doc"("cnpj")) STORED,
    "doc" "text",
    "doc_digits" "text" GENERATED ALWAYS AS (
CASE
    WHEN (("doc" IS NULL) OR ("btrim"("doc") = ''::"text")) THEN NULL::"text"
    ELSE "regexp_replace"("doc", '\D'::"text", ''::"text", 'g'::"text")
END) STORED,
    "documento_key" "text" GENERATED ALWAYS AS ("public"."fn_documento_key"(("documento")::"text")) STORED,
    "cnpj_digits" "text" GENERATED ALWAYS AS ("public"."normalize_cnpj"("cnpj")) STORED,
    "motivo_compra_padrao_id" "uuid",
    CONSTRAINT "fornecedores_doc_digits_len" CHECK ((("doc_digits" IS NULL) OR ("length"("doc_digits") = ANY (ARRAY[11, 14]))))
);


ALTER TABLE "public"."fornecedores" OWNER TO "postgres";


COMMENT ON COLUMN "public"."fornecedores"."gerar_contas_pagar_auto" IS 'Padrao do ERP: mantido sempre TRUE por trigger (campo legado/compatibilidade).';



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
    "sum"(COALESCE("dfi"."valor_calculado", (0)::numeric)) AS "valor_total_calculado",
    "sum"(COALESCE("dfi"."valor_ajustado", (0)::numeric)) AS "valor_total_ajustado",
    "count"(DISTINCT "dfi"."documento_fiscal_id") AS "qtd_documentos"
   FROM ("f"."documento_fiscal_imposto" "dfi"
     JOIN "f"."documento_fiscal" "df" ON ((("df"."id" = "dfi"."documento_fiscal_id") AND ("df"."tenant_id" = "dfi"."tenant_id"))))
  WHERE (("df"."deleted_at" IS NULL) AND ("dfi"."deleted_at" IS NULL) AND ("df"."competencia_date" IS NOT NULL))
  GROUP BY "df"."tenant_id", "df"."empresa_id", "df"."competencia_date", "df"."operacao", "dfi"."imposto", "dfi"."natureza";


ALTER VIEW "f"."vw_imposto_apuracao_mensal" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "m"."orcamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "numero" integer NOT NULL,
    "versao" integer DEFAULT 1 NOT NULL,
    "codigo" "text" NOT NULL,
    "status" "text" DEFAULT 'RASCUNHO'::"text" NOT NULL,
    "emissao_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "titulo" "text" NOT NULL,
    "cliente_id" integer NOT NULL,
    "vendedor_usuario_id" "uuid" NOT NULL,
    "condicao_pagamento_id" "uuid",
    "acrescimo_cond_pag_percent" numeric(7,4) DEFAULT 0 NOT NULL,
    "desconto_global_percent" numeric(7,4) DEFAULT 0 NOT NULL,
    "valor_frete" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_produtos" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_servicos" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_bruto" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_desconto_global" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_liquido" numeric(15,2) DEFAULT 0 NOT NULL,
    "observacoes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    CONSTRAINT "ck_orcamento__acrescimo_range" CHECK ((("acrescimo_cond_pag_percent" >= (0)::numeric) AND ("acrescimo_cond_pag_percent" <= (100)::numeric))),
    CONSTRAINT "ck_orcamento__descglobal_range" CHECK ((("desconto_global_percent" >= (0)::numeric) AND ("desconto_global_percent" <= (100)::numeric))),
    CONSTRAINT "ck_orcamento__frete_range" CHECK (("valor_frete" >= (0)::numeric)),
    CONSTRAINT "ck_orcamento__numero" CHECK (("numero" >= 1)),
    CONSTRAINT "ck_orcamento__status" CHECK (("status" = ANY (ARRAY['RASCUNHO'::"text", 'FINALIZADO'::"text", 'CANCELADO'::"text"]))),
    CONSTRAINT "ck_orcamento__versao" CHECK (("versao" >= 1))
);


ALTER TABLE "m"."orcamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "m"."orcamento_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "orcamento_id" "uuid" NOT NULL,
    "seq" integer NOT NULL,
    "item_id" integer NOT NULL,
    "item_tipo" "text" NOT NULL,
    "item_nome" "text" NOT NULL,
    "unidade" "text" NOT NULL,
    "quantidade" numeric(15,3) DEFAULT 0 NOT NULL,
    "valor_unitario" numeric(15,4) DEFAULT 0 NOT NULL,
    "desconto_item_percent" numeric(7,4) DEFAULT 0 NOT NULL,
    "acrescimo_cond_pag_percent" numeric(7,4) DEFAULT 0 NOT NULL,
    "desconto_global_percent" numeric(7,4) DEFAULT 0 NOT NULL,
    "valor_total_bruto" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_total" numeric(15,2) DEFAULT 0 NOT NULL,
    "valor_unitario_liquido" numeric(15,4) DEFAULT 0 NOT NULL,
    "observacoes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone,
    "conjunto_id" "uuid",
    "conjunto_instancia_id" "uuid",
    "conjunto_codigo" "text",
    "conjunto_nome" "text",
    CONSTRAINT "ck_orcamento_item__acresc_range" CHECK ((("acrescimo_cond_pag_percent" >= (0)::numeric) AND ("acrescimo_cond_pag_percent" <= (100)::numeric))),
    CONSTRAINT "ck_orcamento_item__descglobal_range" CHECK ((("desconto_global_percent" >= (0)::numeric) AND ("desconto_global_percent" <= (100)::numeric))),
    CONSTRAINT "ck_orcamento_item__descitem_range" CHECK ((("desconto_item_percent" >= (0)::numeric) AND ("desconto_item_percent" <= (100)::numeric))),
    CONSTRAINT "ck_orcamento_item__qtd" CHECK (("quantidade" >= (0)::numeric)),
    CONSTRAINT "ck_orcamento_item__seq" CHECK (("seq" >= 1)),
    CONSTRAINT "ck_orcamento_item__tipo" CHECK (("item_tipo" = ANY (ARRAY['PRODUTO'::"text", 'SERVICO'::"text"]))),
    CONSTRAINT "ck_orcamento_item__valor_unit" CHECK (("valor_unitario" >= (0)::numeric))
);


ALTER TABLE "m"."orcamento_item" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "m"."orcamento_seq" (
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "proximo_numero" integer DEFAULT 1 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_orcamento_seq__proximo_numero" CHECK (("proximo_numero" >= 1))
);


ALTER TABLE "m"."orcamento_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."apontamentos_horas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "os_id" integer NOT NULL,
    "colaborador_id" "uuid" NOT NULL,
    "data" "date" NOT NULL,
    "horas" numeric(6,2) NOT NULL,
    "tipo_hora_id" "uuid",
    "fator_aplicado" numeric(6,3),
    "descricao" "text",
    "status" character varying(20) DEFAULT 'lancado'::character varying NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "hh_especialidade_id" "uuid",
    "hora_entrada_1" time without time zone,
    "hora_saida_1" time without time zone,
    "hora_entrada_2" time without time zone,
    "hora_saida_2" time without time zone,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "gerado_por_hh" boolean DEFAULT false NOT NULL,
    "hh_lancamento_id" bigint,
    CONSTRAINT "apontamentos_horas_chk" CHECK ((("horas" > (0)::numeric) AND ("horas" <= (24)::numeric))),
    CONSTRAINT "apontamentos_horas_periodos_ck" CHECK (((("hora_entrada_1" IS NULL) AND ("hora_saida_1" IS NULL) AND ("hora_entrada_2" IS NULL) AND ("hora_saida_2" IS NULL)) OR (("hora_entrada_1" IS NOT NULL) AND ("hora_saida_1" IS NOT NULL) AND ("hora_entrada_2" IS NOT NULL) AND ("hora_saida_2" IS NOT NULL) AND ("hora_saida_1" > "hora_entrada_1") AND ("hora_saida_2" > "hora_entrada_2") AND ("hora_saida_1" <= "hora_entrada_2"))))
);


ALTER TABLE "public"."apontamentos_horas" OWNER TO "postgres";


COMMENT ON COLUMN "public"."apontamentos_horas"."hora_entrada_1" IS 'Entrada período 1 (manhã)';



COMMENT ON COLUMN "public"."apontamentos_horas"."hora_saida_1" IS 'Saída período 1 (manhã)';



COMMENT ON COLUMN "public"."apontamentos_horas"."hora_entrada_2" IS 'Entrada período 2 (tarde)';



COMMENT ON COLUMN "public"."apontamentos_horas"."hora_saida_2" IS 'Saída período 2 (tarde)';



COMMENT ON COLUMN "public"."apontamentos_horas"."gerado_por_hh" IS 'True quando o lançamento foi gerado automaticamente a partir de HH lançado dentro da OS (sem horários, só total)';



CREATE TABLE IF NOT EXISTS "public"."audit_log" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid",
    "table_name" "text" NOT NULL,
    "action" "text" NOT NULL,
    "row_pk" "text",
    "old_data" "jsonb",
    "new_data" "jsonb",
    "actor_user_id" "uuid",
    "actor_email" "text",
    "request_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "audit_log_action_check" CHECK (("action" = ANY (ARRAY['INSERT'::"text", 'UPDATE'::"text", 'DELETE'::"text"])))
);


ALTER TABLE "public"."audit_log" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."audit_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."audit_log_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."audit_log_id_seq" OWNED BY "public"."audit_log"."id";



CREATE TABLE IF NOT EXISTS "public"."centros_custo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "descricao" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."centros_custo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cliente_hh_servicos" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "cliente_id" bigint NOT NULL,
    "nome" "text" NOT NULL,
    "descricao" "text",
    "preco_base" numeric(15,2) DEFAULT 0 NOT NULL,
    "preco_50" numeric(15,2) DEFAULT 0 NOT NULL,
    "preco_100" numeric(15,2) DEFAULT 0 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "criado_por" "text"
);


ALTER TABLE "public"."cliente_hh_servicos" OWNER TO "postgres";


COMMENT ON TABLE "public"."cliente_hh_servicos" IS 'ServiÃ§os de HH (Hora-Homem) especÃ­ficos por cliente, com preÃ§os em 3 nÃ­veis: base, 50% e 100%';



COMMENT ON COLUMN "public"."cliente_hh_servicos"."preco_base" IS 'PreÃ§o base do serviÃ§o (ex: R$ 100,00)';



COMMENT ON COLUMN "public"."cliente_hh_servicos"."preco_50" IS 'PreÃ§o com acrÃ©scimo de 50% (ex: R$ 150,00)';



COMMENT ON COLUMN "public"."cliente_hh_servicos"."preco_100" IS 'PreÃ§o com acrÃ©scimo de 100% (ex: R$ 200,00)';



CREATE SEQUENCE IF NOT EXISTS "public"."cliente_hh_servicos_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."cliente_hh_servicos_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."cliente_hh_servicos_id_seq" OWNED BY "public"."cliente_hh_servicos"."id";



CREATE TABLE IF NOT EXISTS "public"."cliente_hh_tabelas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" integer NOT NULL,
    "ano" integer NOT NULL,
    "nome" "text",
    "vigencia_inicio" "date" NOT NULL,
    "vigencia_fim" "date" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"(),
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    CONSTRAINT "cliente_hh_tabelas_vigencia_chk" CHECK (("vigencia_fim" >= "vigencia_inicio"))
);


ALTER TABLE "public"."cliente_hh_tabelas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clientes" (
    "id" integer NOT NULL,
    "nome" character varying(255) NOT NULL,
    "documento" character varying(20),
    "email" character varying(120),
    "telefone" character varying(30),
    "endereco" "text",
    "observacoes" "text",
    "ativo" boolean DEFAULT true,
    "criado_em" timestamp without time zone DEFAULT "now"(),
    "atualizado_em" timestamp without time zone DEFAULT "now"(),
    "tenant_id" "uuid" NOT NULL,
    "habilita_hh" boolean DEFAULT false NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "razao_social" character varying(255),
    "nome_fantasia" character varying(255),
    "inscricao_estadual" character varying(30),
    "inscricao_municipal" character varying(30),
    "cep" character varying(10),
    "logradouro" character varying(255),
    "numero_endereco" character varying(30),
    "complemento" character varying(120),
    "bairro" character varying(120),
    "cidade" character varying(120),
    "uf" character varying(2),
    "pais" character varying(60),
    "telefone2" character varying(30),
    "email_financeiro" character varying(120),
    "contato_nome" character varying(120),
    "contato_email" character varying(120),
    "contato_telefone" character varying(30),
    "documento_norm" "text" GENERATED ALWAYS AS ("public"."normalize_doc"(("documento")::"text")) STORED,
    "documento_key" "text" GENERATED ALWAYS AS ("public"."fn_documento_key"(("documento")::"text")) STORED
);


ALTER TABLE "public"."clientes" OWNER TO "postgres";


COMMENT ON COLUMN "public"."clientes"."habilita_hh" IS 'Indica se o cliente utiliza relatÃ³rios de Hora-Homem (HH)';



CREATE SEQUENCE IF NOT EXISTS "public"."clientes_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."clientes_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."clientes_id_seq" OWNED BY "public"."clientes"."id";



CREATE TABLE IF NOT EXISTS "public"."colaborador_cliente_funcao" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "cliente_id" bigint NOT NULL,
    "colaborador_id" "uuid" NOT NULL,
    "hh_servico_id" bigint NOT NULL,
    "ativo" boolean DEFAULT true,
    "criado_em" timestamp without time zone DEFAULT "now"(),
    "atualizado_em" timestamp without time zone DEFAULT "now"(),
    "criado_por" "text",
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL
);


ALTER TABLE "public"."colaborador_cliente_funcao" OWNER TO "postgres";


COMMENT ON TABLE "public"."colaborador_cliente_funcao" IS 'VÃ­nculos entre colaboradores e funÃ§Ãµes/serviÃ§os HH por cliente';



COMMENT ON COLUMN "public"."colaborador_cliente_funcao"."tenant_id" IS 'Tenant proprietÃ¡rio do vÃ­nculo';



COMMENT ON COLUMN "public"."colaborador_cliente_funcao"."cliente_id" IS 'Cliente para o qual o colaborador presta serviÃ§o';



COMMENT ON COLUMN "public"."colaborador_cliente_funcao"."colaborador_id" IS 'Colaborador vinculado';



COMMENT ON COLUMN "public"."colaborador_cliente_funcao"."hh_servico_id" IS 'ServiÃ§o/especialidade HH atribuÃ­da ao colaborador neste cliente';



COMMENT ON COLUMN "public"."colaborador_cliente_funcao"."ativo" IS 'Se false, vÃ­nculo foi desativado (soft delete)';



CREATE SEQUENCE IF NOT EXISTS "public"."colaborador_cliente_funcao_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."colaborador_cliente_funcao_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."colaborador_cliente_funcao_id_seq" OWNED BY "public"."colaborador_cliente_funcao"."id";



CREATE TABLE IF NOT EXISTS "public"."colaborador_funcao_hh" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "cliente_id" bigint NOT NULL,
    "colaborador_id" "uuid" NOT NULL,
    "servico_hh_id" bigint NOT NULL,
    "ativo" boolean DEFAULT true,
    "criado_em" timestamp with time zone DEFAULT "now"(),
    "atualizado_em" timestamp with time zone DEFAULT "now"(),
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL
);


ALTER TABLE "public"."colaborador_funcao_hh" OWNER TO "postgres";


COMMENT ON TABLE "public"."colaborador_funcao_hh" IS 'VÃ­nculo entre colaboradores e serviÃ§os de HH (funÃ§Ãµes/especialidades) por cliente';



COMMENT ON COLUMN "public"."colaborador_funcao_hh"."tenant_id" IS 'Tenant (organizaÃ§Ã£o)';



COMMENT ON COLUMN "public"."colaborador_funcao_hh"."cliente_id" IS 'Cliente relacionado';



COMMENT ON COLUMN "public"."colaborador_funcao_hh"."colaborador_id" IS 'Colaborador (funcionÃ¡rio)';



COMMENT ON COLUMN "public"."colaborador_funcao_hh"."servico_hh_id" IS 'ServiÃ§o de HH (funÃ§Ã£o/especialidade) do cliente';



ALTER TABLE "public"."colaborador_funcao_hh" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."colaborador_funcao_hh_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."colaborador_taxas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "colaborador_id" "uuid" NOT NULL,
    "valor_hora" numeric(10,2) NOT NULL,
    "vigencia_inicio" "date" NOT NULL,
    "vigencia_fim" "date",
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    CONSTRAINT "colaborador_taxas_vigencia_chk" CHECK ((("vigencia_fim" IS NULL) OR ("vigencia_fim" >= "vigencia_inicio")))
);


ALTER TABLE "public"."colaborador_taxas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."colaboradores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nome" character varying(150) NOT NULL,
    "cargo" character varying(100),
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "hh_especialidade_id" "uuid",
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL
);


ALTER TABLE "public"."colaboradores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."competencias" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "ano" integer NOT NULL,
    "mes" integer NOT NULL,
    "status" "text" DEFAULT 'aberta'::"text" NOT NULL,
    "fechada_em" timestamp with time zone,
    "fechada_por" "uuid",
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "competencias_ano_check" CHECK ((("ano" >= 2000) AND ("ano" <= 2100))),
    CONSTRAINT "competencias_mes_check" CHECK ((("mes" >= 1) AND ("mes" <= 12))),
    CONSTRAINT "competencias_status_check" CHECK (("status" = ANY (ARRAY['aberta'::"text", 'fechada'::"text"])))
);


ALTER TABLE "public"."competencias" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."contas_pagar_titulos" AS
 SELECT "id",
    "tenant_id",
    "empresa_id",
    "tipo",
    "status",
    "origem",
    "fornecedor_id",
    "cliente_id",
    "documento_fiscal_id",
    "descricao",
    "emissao_date",
    "competencia_date",
    "valor_total",
    "valor_aberto",
    "created_at",
    "updated_at",
    "created_by",
    "updated_by",
    "deleted_at",
    "motivo_compra_id"
   FROM "f"."titulo" "t";


ALTER VIEW "public"."contas_pagar_titulos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."contas_pagar_titulos_agendamentos" AS
 SELECT "id",
    "tenant_id",
    "titulo_id",
    "conta_bancaria_id",
    "data_prevista",
    "forma_pagamento",
    "valor_previsto",
    "observacoes",
    "change_reason",
    "agendado_em",
    "agendado_por",
    "created_at",
    "updated_at",
    "created_by",
    "updated_by",
    "deleted_at"
   FROM "f"."titulo_agendamento";


ALTER VIEW "public"."contas_pagar_titulos_agendamentos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."contas_pagar_titulos_aprovacoes" AS
 SELECT "id",
    "tenant_id",
    "titulo_id",
    "motivo_compra_id",
    "motivo_outros_text",
    "os_id",
    "aprovado_em",
    "aprovado_por",
    "change_reason",
    "created_at",
    "updated_at",
    "created_by",
    "updated_by",
    "deleted_at"
   FROM "f"."titulo_aprovacao";


ALTER VIEW "public"."contas_pagar_titulos_aprovacoes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."contas_pagar_titulos_parcelas" AS
 SELECT "id",
    "tenant_id",
    "titulo_id",
    "numero",
    "vencimento_date",
    "valor",
    "valor_aberto",
    "created_at",
    "updated_at",
    "created_by",
    "updated_by",
    "deleted_at"
   FROM "f"."titulo_parcela";


ALTER VIEW "public"."contas_pagar_titulos_parcelas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."contas_pagar_titulos_rateios" AS
 SELECT "id",
    "tenant_id",
    "titulo_id",
    "plano_contas_id",
    "centro_custo_id",
    "os_id",
    "percentual",
    "valor",
    "created_at",
    "updated_at",
    "created_by",
    "updated_by",
    "deleted_at"
   FROM "f"."titulo_rateio";


ALTER VIEW "public"."contas_pagar_titulos_rateios" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."empresa_memberships" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'user'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."empresa_memberships" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."empresa_memberships_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."empresa_memberships_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."empresa_memberships_id_seq" OWNED BY "public"."empresa_memberships"."id";



CREATE TABLE IF NOT EXISTS "public"."empresas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "cnpj" "text" NOT NULL,
    "razao_social" "text" NOT NULL,
    "nome_fantasia" "text",
    "ie" "text",
    "im" "text",
    "uf" character(2),
    "cidade" "text",
    "endereco" "text",
    "regime_tributario" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "habilita_servico_hh" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."empresas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."estoque" (
    "id" integer NOT NULL,
    "item_id" integer NOT NULL,
    "quantidade_atual" numeric(14,3) DEFAULT 0 NOT NULL,
    "localizacao" "text",
    "atualizado_em" timestamp without time zone DEFAULT "now"(),
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL
);


ALTER TABLE "public"."estoque" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."estoque_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."estoque_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."estoque_id_seq" OWNED BY "public"."estoque"."id";



CREATE TABLE IF NOT EXISTS "public"."feriados" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "data" "date" NOT NULL,
    "descricao" character varying(120),
    "abrangencia" character varying(20) DEFAULT 'NACIONAL'::character varying NOT NULL
);


ALTER TABLE "public"."feriados" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fiscal_itens" (
    "id" bigint NOT NULL,
    "item_id" bigint NOT NULL,
    "ncm" character varying(12),
    "cest" character varying(12),
    "origem" smallint,
    "cfop_padrao" character varying(10),
    "cst_icms" character varying(5),
    "cst_pis" character varying(5),
    "cst_cofins" character varying(5),
    "aliq_icms" numeric(7,4) DEFAULT 0,
    "aliq_ipi" numeric(7,4) DEFAULT 0,
    "aliq_pis" numeric(7,4) DEFAULT 0,
    "aliq_cofins" numeric(7,4) DEFAULT 0,
    "credita_icms" boolean DEFAULT false NOT NULL,
    "credita_pis" boolean DEFAULT false NOT NULL,
    "credita_cofins" boolean DEFAULT false NOT NULL,
    "ipi_entra_no_custo" boolean DEFAULT true NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    CONSTRAINT "fiscal_itens_aliq_cofins_ck" CHECK ((("aliq_cofins" IS NULL) OR (("aliq_cofins" >= (0)::numeric) AND ("aliq_cofins" <= (100)::numeric)))),
    CONSTRAINT "fiscal_itens_aliq_icms_ck" CHECK ((("aliq_icms" IS NULL) OR (("aliq_icms" >= (0)::numeric) AND ("aliq_icms" <= (100)::numeric)))),
    CONSTRAINT "fiscal_itens_aliq_ipi_ck" CHECK ((("aliq_ipi" IS NULL) OR (("aliq_ipi" >= (0)::numeric) AND ("aliq_ipi" <= (100)::numeric)))),
    CONSTRAINT "fiscal_itens_aliq_pis_ck" CHECK ((("aliq_pis" IS NULL) OR (("aliq_pis" >= (0)::numeric) AND ("aliq_pis" <= (100)::numeric)))),
    CONSTRAINT "fiscal_itens_cofins_credit_ck" CHECK ((("credita_cofins" IS NOT TRUE) OR (("cst_cofins" IS NOT NULL) AND ("length"(TRIM(BOTH FROM "cst_cofins")) > 0)))),
    CONSTRAINT "fiscal_itens_icms_credit_ck" CHECK ((("credita_icms" IS NOT TRUE) OR (("cst_icms" IS NOT NULL) AND ("length"(TRIM(BOTH FROM "cst_icms")) > 0)))),
    CONSTRAINT "fiscal_itens_origem_ck" CHECK ((("origem" IS NULL) OR (("origem" >= 0) AND ("origem" <= 8)))),
    CONSTRAINT "fiscal_itens_pis_credit_ck" CHECK ((("credita_pis" IS NOT TRUE) OR (("cst_pis" IS NOT NULL) AND ("length"(TRIM(BOTH FROM "cst_pis")) > 0))))
);


ALTER TABLE "public"."fiscal_itens" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."fiscal_itens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."fiscal_itens_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."fiscal_itens_id_seq" OWNED BY "public"."fiscal_itens"."id";



CREATE TABLE IF NOT EXISTS "public"."fiscal_regras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "ncm" "text",
    "cfop" "text",
    "cst_icms" "text",
    "cst_pis" "text",
    "cst_cofins" "text",
    "origem" smallint,
    "tipo_item" "text",
    "credita_icms" boolean DEFAULT false NOT NULL,
    "credita_pis" boolean DEFAULT false NOT NULL,
    "credita_cofins" boolean DEFAULT false NOT NULL,
    "aliq_icms" numeric,
    "aliq_pis" numeric,
    "aliq_cofins" numeric,
    "prioridade" integer DEFAULT 100 NOT NULL,
    "descricao" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."fiscal_regras" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."fornecedores_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."fornecedores_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."fornecedores_id_seq" OWNED BY "public"."fornecedores"."id";



CREATE TABLE IF NOT EXISTS "public"."hh_especialidades" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "descricao" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."hh_especialidades" OWNER TO "postgres";


ALTER TABLE "public"."hh_especialidades" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."hh_especialidades_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."hh_lancamentos" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid" DEFAULT "public"."current_tenant_id"() NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "os_id" bigint NOT NULL,
    "colaborador_id" "uuid" NOT NULL,
    "hh_tipo_id" bigint NOT NULL,
    "data" "date" NOT NULL,
    "hora_entrada" time without time zone NOT NULL,
    "hora_saida" time without time zone NOT NULL,
    "horas_trabalhadas" numeric(10,2) DEFAULT 0 NOT NULL,
    "percentual_aplicado" integer DEFAULT 0 NOT NULL,
    "valor_hora" numeric(10,2) DEFAULT 0 NOT NULL,
    "valor_total" numeric(10,2) DEFAULT 0 NOT NULL,
    "observacao" "text",
    "criado_por" "text",
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "hh_especialidade_id" "uuid",
    "entrada_1" time without time zone,
    "saida_1" time without time zone,
    "entrada_2" time without time zone,
    "saida_2" time without time zone,
    "hh_servico_id" bigint,
    CONSTRAINT "hh_lancamentos_percentual_aplicado_check" CHECK (("percentual_aplicado" = ANY (ARRAY[0, 50, 100]))),
    CONSTRAINT "hh_lancamentos_periodos_ck" CHECK (((("entrada_1" IS NULL) AND ("saida_1" IS NULL) AND ("entrada_2" IS NULL) AND ("saida_2" IS NULL)) OR (("entrada_1" IS NOT NULL) AND ("saida_1" IS NOT NULL) AND ("entrada_2" IS NOT NULL) AND ("saida_2" IS NOT NULL) AND ("saida_1" > "entrada_1") AND ("saida_2" > "entrada_2") AND ("saida_1" <= "entrada_2"))))
);


ALTER TABLE "public"."hh_lancamentos" OWNER TO "postgres";


COMMENT ON TABLE "public"."hh_lancamentos" IS 'Lançamentos de HH por OS (entrada/saída) com tabela negociada';



COMMENT ON COLUMN "public"."hh_lancamentos"."entrada_1" IS 'Entrada período 1 (manhã)';



COMMENT ON COLUMN "public"."hh_lancamentos"."saida_1" IS 'Saída período 1 (manhã)';



COMMENT ON COLUMN "public"."hh_lancamentos"."entrada_2" IS 'Entrada período 2 (tarde)';



COMMENT ON COLUMN "public"."hh_lancamentos"."saida_2" IS 'Saída período 2 (tarde)';



CREATE SEQUENCE IF NOT EXISTS "public"."hh_lancamentos_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."hh_lancamentos_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."hh_lancamentos_id_seq" OWNED BY "public"."hh_lancamentos"."id";



CREATE TABLE IF NOT EXISTS "public"."hh_tipos_mapping" (
    "id" bigint NOT NULL,
    "tipo_hora_id" "uuid" NOT NULL,
    "hh_tipo_id" bigint NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."hh_tipos_mapping" OWNER TO "postgres";


COMMENT ON TABLE "public"."hh_tipos_mapping" IS 'Mapeamento entre tipos_horas (UUID) e hh_lancamentos.hh_tipo_id (BIGINT)';



CREATE SEQUENCE IF NOT EXISTS "public"."hh_tipos_mapping_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."hh_tipos_mapping_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."hh_tipos_mapping_id_seq" OWNED BY "public"."hh_tipos_mapping"."id";



CREATE TABLE IF NOT EXISTS "public"."horas_trabalhadas" (
    "id" integer NOT NULL,
    "os_id" integer NOT NULL,
    "profissional_id" integer NOT NULL,
    "data_trabalho" "date" NOT NULL,
    "horas_trabalhadas" numeric(5,2) NOT NULL,
    "valor_hora" numeric(10,2) NOT NULL,
    "valor_total" numeric(10,2) GENERATED ALWAYS AS (("horas_trabalhadas" * "valor_hora")) STORED,
    "descricao" "text",
    "criado_em" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."horas_trabalhadas" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."horas_trabalhadas_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."horas_trabalhadas_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."horas_trabalhadas_id_seq" OWNED BY "public"."horas_trabalhadas"."id";



CREATE TABLE IF NOT EXISTS "public"."itens" (
    "id" integer NOT NULL,
    "codigo_interno" character varying(50) NOT NULL,
    "codigo_barras" character varying(50),
    "nome" character varying(255) NOT NULL,
    "descricao" "text",
    "tipo" character varying(20) NOT NULL,
    "categoria" character varying(100),
    "subcategoria" character varying(100),
    "unidade_medida" character varying(10) DEFAULT 'UN'::character varying,
    "peso_bruto" numeric(10,3),
    "peso_liquido" numeric(10,3),
    "controla_estoque" boolean DEFAULT false,
    "estoque_minimo" integer DEFAULT 0,
    "estoque_maximo" integer DEFAULT 0,
    "estoque_ideal" integer DEFAULT 0,
    "custo_ultima_compra" numeric(10,2) DEFAULT 0,
    "custo_medio" numeric(10,2) DEFAULT 0,
    "data_ultima_compra" timestamp without time zone,
    "preco_unitario" numeric(10,2) DEFAULT 0,
    "preco_promocional" numeric(10,2),
    "data_atualizacao_preco" timestamp without time zone,
    "margem_lucro_percentual" numeric(5,2),
    "ncm" character varying(10),
    "cest" character varying(10),
    "cfop_padrao" character varying(10),
    "aliquota_icms" numeric(5,2),
    "aliquota_ipi" numeric(5,2),
    "aliquota_pis" numeric(5,2),
    "aliquota_cofins" numeric(5,2),
    "fornecedor_id" integer,
    "codigo_fornecedor" character varying(50),
    "controla_lote" boolean DEFAULT false,
    "controla_validade" boolean DEFAULT false,
    "dias_alerta_vencimento" integer DEFAULT 30,
    "ativo" boolean DEFAULT true,
    "observacoes" "text",
    "criado_em" timestamp without time zone DEFAULT "now"(),
    "criado_por" character varying(100),
    "atualizado_em" timestamp without time zone DEFAULT "now"(),
    "atualizado_por" character varying(100),
    "fabricante" character varying(150),
    "tenant_id" "uuid" NOT NULL,
    "finalidade" "public"."item_finalidade" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "motivo_compra_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "codigo_interno_sem_zeros" "text" GENERATED ALWAYS AS ("public"."strip_zeros_esquerda"(("codigo_interno")::"text")) STORED,
    "codigo_fornecedor_sem_zeros" "text" GENERATED ALWAYS AS ("public"."strip_zeros_esquerda"(("codigo_fornecedor")::"text")) STORED,
    "mesclado_em_item_id" integer,
    "mesclado_em" timestamp with time zone,
    "mesclado_motivo" "text",
    CONSTRAINT "ck_itens__codigo_interno_sem_zero_esquerda" CHECK (((("codigo_interno")::"text" = '0'::"text") OR (("codigo_interno")::"text" !~ '^0'::"text"))),
    CONSTRAINT "itens_tipo_check" CHECK ((("tipo")::"text" = ANY ((ARRAY['produto'::character varying, 'servico'::character varying, 'despesa'::character varying])::"text"[])))
);


ALTER TABLE "public"."itens" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."itens_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."itens_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."itens_id_seq" OWNED BY "public"."itens"."id";



CREATE TABLE IF NOT EXISTS "public"."itens_merge_log" (
    "id" bigint NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "codigo_limpo" "text" NOT NULL,
    "keep_item_id" integer NOT NULL,
    "drop_item_id" integer NOT NULL,
    "drop_codigo_orig" "text",
    "merged_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "merged_by" "uuid" DEFAULT "auth"."uid"(),
    "merged_reason" "text"
);


ALTER TABLE "public"."itens_merge_log" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."itens_merge_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."itens_merge_log_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."itens_merge_log_id_seq" OWNED BY "public"."itens_merge_log"."id";



CREATE TABLE IF NOT EXISTS "public"."lancamentos_contabeis" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "competencia_id" "uuid",
    "data_lancamento" "date" DEFAULT CURRENT_DATE NOT NULL,
    "historico" "text" NOT NULL,
    "origem_tipo" "text",
    "origem_id" "text",
    "status" "text" DEFAULT 'rascunho'::"text" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "lancamentos_contabeis_status_check" CHECK (("status" = ANY (ARRAY['rascunho'::"text", 'confirmado'::"text", 'estornado'::"text"])))
);


ALTER TABLE "public"."lancamentos_contabeis" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lancamentos_contabeis_itens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "lancamento_id" "uuid" NOT NULL,
    "conta_id" "uuid" NOT NULL,
    "centro_custo_id" "uuid",
    "tipo" "text" NOT NULL,
    "valor" numeric(18,2) NOT NULL,
    "complemento" "text",
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "lancamentos_contabeis_itens_tipo_check" CHECK (("tipo" = ANY (ARRAY['debito'::"text", 'credito'::"text"]))),
    CONSTRAINT "lancamentos_contabeis_itens_valor_check" CHECK (("valor" > (0)::numeric))
);


ALTER TABLE "public"."lancamentos_contabeis_itens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."membership_roles" (
    "membership_id" "uuid" NOT NULL,
    "role_id" "uuid" NOT NULL
);


ALTER TABLE "public"."membership_roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."movimentacoes" (
    "id" integer NOT NULL,
    "item_id" integer NOT NULL,
    "tipo" "text" NOT NULL,
    "quantidade" numeric(14,3) DEFAULT 0 NOT NULL,
    "motivo" "text",
    "realizado_por" character varying(100),
    "data_movimentacao" timestamp without time zone DEFAULT "now"(),
    "custo_unitario_bruto" numeric(14,6),
    "custo_unitario_real" numeric(14,6),
    "credito_icms" numeric(14,2) DEFAULT 0 NOT NULL,
    "credito_pis" numeric(14,2) DEFAULT 0 NOT NULL,
    "credito_cofins" numeric(14,2) DEFAULT 0 NOT NULL,
    "origem_nf_entrada_id" bigint,
    "v_ipi" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_icms" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_pis" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_cofins" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_frete_rateado" numeric(14,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    "origem_os_id" integer,
    CONSTRAINT "movimentacoes_empresa_nn_ck" CHECK (("empresa_id" IS NOT NULL)),
    CONSTRAINT "movimentacoes_nf_required_ck" CHECK ((("origem_nf_entrada_id" IS NULL) OR (("tenant_id" IS NOT NULL) AND ("data_movimentacao" IS NOT NULL) AND ("tipo" = ANY (ARRAY['entrada'::"text", 'saida'::"text"]))))),
    CONSTRAINT "movimentacoes_tipo_check" CHECK (("tipo" = ANY (ARRAY['entrada'::"text", 'saida'::"text", 'ajuste'::"text"])))
);


ALTER TABLE "public"."movimentacoes" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."movimentacoes_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."movimentacoes_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."movimentacoes_id_seq" OWNED BY "public"."movimentacoes"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."nf_entrada_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."nf_entrada_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."nf_entrada_id_seq" OWNED BY "public"."nf_entrada"."id";



CREATE TABLE IF NOT EXISTS "public"."nf_entrada_itens" (
    "id" bigint NOT NULL,
    "nf_entrada_id" bigint NOT NULL,
    "item_id" bigint,
    "codigo_fornecedor" character varying(80),
    "descricao" "text",
    "ncm" character varying(12),
    "cfop" character varying(10),
    "qtd" numeric(14,4) DEFAULT 0 NOT NULL,
    "v_unit" numeric(14,6) DEFAULT 0 NOT NULL,
    "v_prod" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_icms" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_ipi" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_pis" numeric(14,2) DEFAULT 0 NOT NULL,
    "v_cofins" numeric(14,2) DEFAULT 0 NOT NULL,
    "aliq_icms" numeric(7,4),
    "aliq_ipi" numeric(7,4),
    "aliq_pis" numeric(7,4),
    "aliq_cofins" numeric(7,4),
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "aliquota_icms" numeric(12,4),
    "aliquota_ipi" numeric(12,4),
    "aliquota_pis" numeric(12,4),
    "aliquota_cofins" numeric(12,4),
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    CONSTRAINT "ck_nf_entrada_itens__descricao_obrigatoria" CHECK ((("item_id" IS NULL) OR (("descricao" IS NOT NULL) AND ("btrim"("descricao") <> ''::"text"))))
);


ALTER TABLE "public"."nf_entrada_itens" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."nf_entrada_itens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."nf_entrada_itens_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."nf_entrada_itens_id_seq" OWNED BY "public"."nf_entrada_itens"."id";



CREATE TABLE IF NOT EXISTS "public"."ordens_servico" (
    "id" integer NOT NULL,
    "numero_os" character varying(50) NOT NULL,
    "cliente_nome" character varying(255) NOT NULL,
    "cliente_id" integer,
    "descricao_servico" "text",
    "status" character varying(20) DEFAULT 'aberta'::character varying,
    "data_abertura" timestamp without time zone DEFAULT "now"(),
    "data_conclusao" timestamp without time zone,
    "valor_total" numeric(12,2) DEFAULT 0,
    "observacoes" "text",
    "criado_por" character varying(100),
    "atualizado_em" timestamp without time zone DEFAULT "now"(),
    "os_num" bigint NOT NULL,
    "pedido_compra" "text",
    "tipo_pedido" "text",
    "vendedor" "text",
    "orcado" numeric(12,2) DEFAULT 0,
    "custo" numeric(12,2) DEFAULT 0,
    "tem_gestao" boolean DEFAULT false NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "usa_relatorio_hh" boolean DEFAULT false NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    CONSTRAINT "ordens_servico_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['aberta'::character varying, 'em_andamento'::character varying, 'concluida'::character varying, 'cancelada'::character varying])::"text"[]))),
    CONSTRAINT "ordens_servico_tipo_pedido_check" CHECK (("tipo_pedido" = ANY (ARRAY['servico'::"text", 'material'::"text"])))
);


ALTER TABLE "public"."ordens_servico" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."ordens_servico_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."ordens_servico_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ordens_servico_id_seq" OWNED BY "public"."ordens_servico"."id";



ALTER TABLE "public"."ordens_servico" ALTER COLUMN "os_num" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."ordens_servico_os_num_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."os_gestao_itens" (
    "id" bigint NOT NULL,
    "os_id" integer NOT NULL,
    "item_tipo" "public"."os_gestao_tipo" NOT NULL,
    "area" "public"."os_gestao_area" NOT NULL,
    "habilitado" boolean DEFAULT false NOT NULL,
    "responsavel_id" "text",
    "data_prevista" "date",
    "progresso_percent" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" DEFAULT "public"."current_empresa_id"() NOT NULL,
    CONSTRAINT "os_gestao_itens_progresso_percent_check" CHECK ((("progresso_percent" >= 0) AND ("progresso_percent" <= 100)))
);


ALTER TABLE "public"."os_gestao_itens" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."os_gestao_itens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."os_gestao_itens_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."os_gestao_itens_id_seq" OWNED BY "public"."os_gestao_itens"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."os_itens_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."os_itens_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."os_itens_id_seq" OWNED BY "public"."os_itens"."id";



CREATE TABLE IF NOT EXISTS "public"."parametro_importacao_xml" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "itens_auto_cadastrar_finalidades" "public"."item_finalidade"[] DEFAULT ARRAY['materia_prima'::"public"."item_finalidade"] NOT NULL,
    "itens_vincular_finalidades" "public"."item_finalidade"[] DEFAULT ARRAY['materia_prima'::"public"."item_finalidade"] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" DEFAULT "a"."fn_current_usuario_id"(),
    "updated_by" "uuid",
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."parametro_importacao_xml" OWNER TO "postgres";


COMMENT ON TABLE "public"."parametro_importacao_xml" IS 'Parâmetros por tenant/empresa para controlar auto-cadastro e vínculo de itens durante importação de XML (NF-e).';



CREATE TABLE IF NOT EXISTS "public"."permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."plano_contas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "descricao" "text" NOT NULL,
    "tipo" "text" NOT NULL,
    "natureza" "text" NOT NULL,
    "parent_id" "uuid",
    "nivel" integer,
    "ativo" boolean DEFAULT true NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "plano_contas_natureza_check" CHECK (("natureza" = ANY (ARRAY['devedora'::"text", 'credora'::"text"]))),
    CONSTRAINT "plano_contas_tipo_check" CHECK (("tipo" = ANY (ARRAY['ativo'::"text", 'passivo'::"text", 'patrimonio_liquido'::"text", 'receita'::"text", 'despesa'::"text", 'resultado'::"text"])))
);


ALTER TABLE "public"."plano_contas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "nome" "text",
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profissionais" (
    "id" integer NOT NULL,
    "nome" character varying(255) NOT NULL,
    "cpf" character varying(14),
    "email" character varying(100),
    "telefone" character varying(20),
    "valor_hora" numeric(10,2) NOT NULL,
    "ativo" boolean DEFAULT true,
    "criado_em" timestamp without time zone DEFAULT "now"(),
    "atualizado_em" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."profissionais" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."profissionais_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."profissionais_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."profissionais_id_seq" OWNED BY "public"."profissionais"."id";



CREATE OR REPLACE VIEW "public"."r_itens_ativos" AS
 SELECT "id",
    "codigo_interno",
    "codigo_barras",
    "nome",
    "descricao",
    "tipo",
    "categoria",
    "subcategoria",
    "unidade_medida",
    "peso_bruto",
    "peso_liquido",
    "controla_estoque",
    "estoque_minimo",
    "estoque_maximo",
    "estoque_ideal",
    "custo_ultima_compra",
    "custo_medio",
    "data_ultima_compra",
    "preco_unitario",
    "preco_promocional",
    "data_atualizacao_preco",
    "margem_lucro_percentual",
    "ncm",
    "cest",
    "cfop_padrao",
    "aliquota_icms",
    "aliquota_ipi",
    "aliquota_pis",
    "aliquota_cofins",
    "fornecedor_id",
    "codigo_fornecedor",
    "controla_lote",
    "controla_validade",
    "dias_alerta_vencimento",
    "ativo",
    "observacoes",
    "criado_em",
    "criado_por",
    "atualizado_em",
    "atualizado_por",
    "fabricante",
    "tenant_id",
    "finalidade",
    "empresa_id",
    "motivo_compra_id",
    "created_at",
    "updated_at",
    "codigo_interno_sem_zeros",
    "codigo_fornecedor_sem_zeros",
    "mesclado_em_item_id",
    "mesclado_em",
    "mesclado_motivo"
   FROM "public"."itens"
  WHERE (("ativo" = true) AND ("mesclado_em_item_id" IS NULL));


ALTER VIEW "public"."r_itens_ativos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."role_access_rules" (
    "role_id" "uuid" NOT NULL,
    "resource" "text" NOT NULL,
    "action" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."role_access_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."role_permissions" (
    "role" "text" NOT NULL,
    "permission" "text" NOT NULL
);


ALTER TABLE "public"."role_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tenant_memberships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "role" "text" DEFAULT 'admin'::"text",
    CONSTRAINT "tenant_memberships_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text", 'estoque'::"text", 'projetos'::"text", 'financeiro'::"text"])))
);


ALTER TABLE "public"."tenant_memberships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tenants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nome" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."tenants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tipos_horas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" character varying(30) NOT NULL,
    "descricao" character varying(120) NOT NULL,
    "fator" numeric(6,3) DEFAULT 1 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "tenant_id" "uuid" NOT NULL
);


ALTER TABLE "public"."tipos_horas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_empresa_context" (
    "user_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_empresa_context" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "user_id" "uuid" NOT NULL,
    "nome" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_tenant_context" (
    "user_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_tenant_context" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_creditos_por_periodo" AS
 SELECT "tenant_id",
    "empresa_id",
    ("date_trunc"('month'::"text", "data_movimentacao"))::"date" AS "competencia",
    "sum"(COALESCE("credito_icms", (0)::numeric)) AS "credito_icms",
    "sum"(COALESCE("credito_pis", (0)::numeric)) AS "credito_pis",
    "sum"(COALESCE("credito_cofins", (0)::numeric)) AS "credito_cofins"
   FROM "public"."movimentacoes" "m"
  WHERE ("tipo" = 'entrada'::"text")
  GROUP BY "tenant_id", "empresa_id", (("date_trunc"('month'::"text", "data_movimentacao"))::"date");


ALTER VIEW "public"."v_creditos_por_periodo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_item_ultimo_custo" AS
 SELECT DISTINCT ON ("tenant_id", "item_id") "tenant_id",
    "item_id",
    "data_movimentacao",
    "origem_nf_entrada_id",
    "custo_unitario_bruto",
    "custo_unitario_real",
    "v_frete_rateado",
    "v_ipi",
    "v_icms",
    "v_pis",
    "v_cofins"
   FROM "public"."movimentacoes" "m"
  WHERE ("tipo" = 'entrada'::"text")
  ORDER BY "tenant_id", "item_id", "data_movimentacao" DESC, "id" DESC;


ALTER VIEW "public"."v_item_ultimo_custo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_estoque_custo_atual" AS
 SELECT "e"."tenant_id",
    "e"."item_id",
    "e"."quantidade_atual",
    "u"."custo_unitario_real" AS "custo_atual_unitario",
    ("e"."quantidade_atual" * COALESCE("u"."custo_unitario_real", (0)::numeric)) AS "custo_total_em_estoque",
    "u"."data_movimentacao" AS "data_ultimo_custo",
    "u"."origem_nf_entrada_id"
   FROM ("public"."estoque" "e"
     LEFT JOIN "public"."v_item_ultimo_custo" "u" ON ((("u"."tenant_id" = "e"."tenant_id") AND ("u"."item_id" = "e"."item_id"))));


ALTER VIEW "public"."v_estoque_custo_atual" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lancamentos_contabeis_balance" AS
 SELECT "l"."id" AS "lancamento_id",
    "l"."tenant_id",
    "l"."empresa_id",
    "l"."status",
    "l"."data_lancamento",
    "l"."historico",
    COALESCE("sum"(
        CASE
            WHEN ("i"."tipo" = 'debito'::"text") THEN "i"."valor"
            ELSE (0)::numeric
        END), (0)::numeric) AS "total_debito",
    COALESCE("sum"(
        CASE
            WHEN ("i"."tipo" = 'credito'::"text") THEN "i"."valor"
            ELSE (0)::numeric
        END), (0)::numeric) AS "total_credito",
    (COALESCE("sum"(
        CASE
            WHEN ("i"."tipo" = 'debito'::"text") THEN "i"."valor"
            ELSE (0)::numeric
        END), (0)::numeric) - COALESCE("sum"(
        CASE
            WHEN ("i"."tipo" = 'credito'::"text") THEN "i"."valor"
            ELSE (0)::numeric
        END), (0)::numeric)) AS "diferenca"
   FROM ("public"."lancamentos_contabeis" "l"
     LEFT JOIN "public"."lancamentos_contabeis_itens" "i" ON (("i"."lancamento_id" = "l"."id")))
  GROUP BY "l"."id", "l"."tenant_id", "l"."empresa_id", "l"."status", "l"."data_lancamento", "l"."historico";


ALTER VIEW "public"."v_lancamentos_contabeis_balance" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_permissions" AS
 SELECT DISTINCT "ut"."tenant_id",
    "rp"."permission"
   FROM (("a"."usuario" "u"
     JOIN "a"."usuario_tenant" "ut" ON (("ut"."usuario_id" = "u"."id")))
     JOIN "public"."role_permissions" "rp" ON (("rp"."role" = "a"."fn_map_papel_tenant_to_role"("ut"."papel"))))
  WHERE (("u"."auth_user_id" = "auth"."uid"()) AND ("ut"."deleted_at" IS NULL) AND ("ut"."ativo" = true))
UNION
 SELECT DISTINCT "e"."tenant_id",
    "rp"."permission"
   FROM ((("a"."usuario" "u"
     JOIN "a"."usuario_empresa" "ue" ON (("ue"."usuario_id" = "u"."id")))
     JOIN "c"."empresa" "e" ON (("e"."id" = "ue"."empresa_id")))
     JOIN "public"."role_permissions" "rp" ON (("rp"."role" = "a"."fn_map_papel_empresa_to_role"("ue"."papel"))))
  WHERE (("u"."auth_user_id" = "auth"."uid"()) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("e"."deleted_at" IS NULL));


ALTER VIEW "public"."v_user_permissions" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_apontamentos_horas_custo" AS
 SELECT "a"."id" AS "apontamento_id",
    "a"."os_id",
    "a"."colaborador_id",
    "c"."nome" AS "colaborador_nome",
    "a"."data",
    "a"."horas",
    "th"."codigo" AS "tipo_hora_codigo",
    "th"."descricao" AS "tipo_hora_descricao",
    COALESCE("a"."fator_aplicado", "th"."fator", (1)::numeric) AS "fator",
    COALESCE("tx"."valor_hora", (0)::numeric(10,2)) AS "valor_hora",
    "round"((("a"."horas" * COALESCE("tx"."valor_hora", (0)::numeric(10,2))) * COALESCE("a"."fator_aplicado", "th"."fator", (1)::numeric)), 2) AS "custo_lancamento",
    "a"."descricao",
    "a"."status",
    "a"."criado_em"
   FROM ((("public"."apontamentos_horas" "a"
     JOIN "public"."colaboradores" "c" ON (("c"."id" = "a"."colaborador_id")))
     LEFT JOIN "public"."tipos_horas" "th" ON (("th"."id" = "a"."tipo_hora_id")))
     LEFT JOIN LATERAL ( SELECT "t"."valor_hora"
           FROM "public"."colaborador_taxas" "t"
          WHERE (("t"."colaborador_id" = "a"."colaborador_id") AND ("t"."tenant_id" = "a"."tenant_id") AND ("t"."empresa_id" = "a"."empresa_id"))
          ORDER BY
                CASE
                    WHEN (("a"."data" >= "t"."vigencia_inicio") AND (("t"."vigencia_fim" IS NULL) OR ("a"."data" <= "t"."vigencia_fim"))) THEN 0
                    WHEN ("t"."vigencia_inicio" <= "a"."data") THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN ("t"."vigencia_inicio" <= "a"."data") THEN "t"."vigencia_inicio"
                    ELSE NULL::"date"
                END DESC NULLS LAST,
                CASE
                    WHEN ("t"."vigencia_inicio" > "a"."data") THEN "t"."vigencia_inicio"
                    ELSE NULL::"date"
                END, "t"."criado_em" DESC
         LIMIT 1) "tx" ON (true));


ALTER VIEW "public"."vw_apontamentos_horas_custo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_colaboradores_taxa_atual" AS
 SELECT "c"."id",
    "c"."nome",
    "c"."cargo",
    "c"."ativo",
    "c"."criado_em",
    "tx"."id" AS "taxa_id",
    "tx"."valor_hora",
    "tx"."vigencia_inicio",
    "tx"."vigencia_fim"
   FROM ("public"."colaboradores" "c"
     LEFT JOIN LATERAL ( SELECT "t"."id",
            "t"."colaborador_id",
            "t"."valor_hora",
            "t"."vigencia_inicio",
            "t"."vigencia_fim",
            "t"."criado_em"
           FROM "public"."colaborador_taxas" "t"
          WHERE (("t"."colaborador_id" = "c"."id") AND (CURRENT_DATE >= "t"."vigencia_inicio") AND (("t"."vigencia_fim" IS NULL) OR (CURRENT_DATE <= "t"."vigencia_fim")))
          ORDER BY "t"."vigencia_inicio" DESC, "t"."criado_em" DESC
         LIMIT 1) "tx" ON (true));


ALTER VIEW "public"."vw_colaboradores_taxa_atual" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_creditos_mensais" AS
 SELECT "date_trunc"('month'::"text", "data_movimentacao") AS "mes",
    "sum"("credito_icms") AS "credito_icms",
    "sum"("credito_pis") AS "credito_pis",
    "sum"("credito_cofins") AS "credito_cofins"
   FROM "public"."movimentacoes"
  WHERE ("tipo" = 'entrada'::"text")
  GROUP BY ("date_trunc"('month'::"text", "data_movimentacao"))
  ORDER BY ("date_trunc"('month'::"text", "data_movimentacao"));


ALTER VIEW "public"."vw_creditos_mensais" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_custo_mao_obra_os" AS
 SELECT "os_id",
    "sum"("horas") AS "total_horas",
    "sum"("custo_lancamento") AS "custo_mao_obra"
   FROM "public"."vw_apontamentos_horas_custo"
  GROUP BY "os_id";


ALTER VIEW "public"."vw_custo_mao_obra_os" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_hh_total_os" AS
 SELECT "tenant_id",
    "empresa_id",
    "os_id",
    (COALESCE("sum"("valor_total"), (0)::numeric))::numeric(12,2) AS "total_hh"
   FROM "public"."hh_lancamentos"
  GROUP BY "tenant_id", "empresa_id", "os_id";


ALTER VIEW "public"."vw_hh_total_os" OWNER TO "postgres";


COMMENT ON VIEW "public"."vw_hh_total_os" IS 'Total de HH (cobrança) por OS.';



CREATE TABLE IF NOT EXISTS "r"."dre_plano_excluido" (
    "tenant_id" "uuid" NOT NULL,
    "plano_contas_id" "uuid" NOT NULL,
    "motivo" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "r"."dre_plano_excluido" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_apuracao_impostos_mes" AS
 WITH "impostos" AS (
         SELECT "df"."tenant_id",
            "df"."empresa_id",
            "df"."competencia_date",
            "i"."imposto",
            "i"."natureza",
            "sum"("i"."base_calculo") AS "base_total",
            "sum"("i"."valor_calculado") AS "valor_total_calculado",
            "sum"(COALESCE("i"."valor_ajustado", (0)::numeric)) AS "valor_total_ajustado",
            "count"(DISTINCT "df"."id") AS "qtd_documentos"
           FROM ("f"."documento_fiscal" "df"
             JOIN "f"."documento_fiscal_imposto" "i" ON (("i"."documento_fiscal_id" = "df"."id")))
          WHERE (("df"."deleted_at" IS NULL) AND ("i"."deleted_at" IS NULL) AND ("df"."competencia_date" IS NOT NULL))
          GROUP BY "df"."tenant_id", "df"."empresa_id", "df"."competencia_date", "i"."imposto", "i"."natureza"
        ), "pendencias" AS (
         SELECT "df"."tenant_id",
            "df"."empresa_id",
            "df"."competencia_date",
            'PENDENCIAS_XML'::"text" AS "imposto",
            'INFO'::"text" AS "natureza",
            (0)::numeric AS "base_total",
            (0)::numeric AS "valor_total_calculado",
            (0)::numeric AS "valor_total_ajustado",
            "count"(DISTINCT "df"."id") AS "qtd_documentos"
           FROM ("f"."documento_fiscal" "df"
             JOIN "f"."documento_fiscal_pendencia" "p" ON ((("p"."documento_fiscal_id" = "df"."id") AND ("p"."tenant_id" = "df"."tenant_id") AND ("p"."resolved_at" IS NULL))))
          WHERE (("df"."deleted_at" IS NULL) AND ("df"."competencia_date" IS NOT NULL))
          GROUP BY "df"."tenant_id", "df"."empresa_id", "df"."competencia_date"
        )
 SELECT "impostos"."tenant_id",
    "impostos"."empresa_id",
    "impostos"."competencia_date",
    "impostos"."imposto",
    "impostos"."natureza",
    "impostos"."base_total",
    "impostos"."valor_total_calculado",
    "impostos"."valor_total_ajustado",
    "impostos"."qtd_documentos"
   FROM "impostos"
UNION ALL
 SELECT "pendencias"."tenant_id",
    "pendencias"."empresa_id",
    "pendencias"."competencia_date",
    "pendencias"."imposto",
    "pendencias"."natureza",
    "pendencias"."base_total",
    "pendencias"."valor_total_calculado",
    "pendencias"."valor_total_ajustado",
    "pendencias"."qtd_documentos"
   FROM "pendencias";


ALTER VIEW "r"."r_apuracao_impostos_mes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_dre_mensal_plano" AS
 WITH "base" AS (
         SELECT "t"."tenant_id",
            "t"."empresa_id",
            "t"."competencia_date",
            "t"."tipo" AS "titulo_tipo",
            "t"."status" AS "titulo_status",
            "tr"."plano_contas_id",
            COALESCE("pc"."codigo", 'SEM_PLANO'::"text") AS "plano_codigo",
            COALESCE("pc"."nome", 'SEM PLANO'::"text") AS "plano_nome",
            (COALESCE("tr"."valor", "round"(((COALESCE("tr"."percentual", (0)::numeric) / 100.0) * "t"."valor_total"), 2), (0)::numeric))::numeric(15,2) AS "valor_rateado"
           FROM (("f"."titulo" "t"
             JOIN "f"."titulo_rateio" "tr" ON ((("tr"."tenant_id" = "t"."tenant_id") AND ("tr"."titulo_id" = "t"."id") AND ("tr"."deleted_at" IS NULL))))
             LEFT JOIN "f"."plano_contas" "pc" ON ((("pc"."tenant_id" = "tr"."tenant_id") AND ("pc"."id" = "tr"."plano_contas_id") AND ("pc"."deleted_at" IS NULL))))
          WHERE (("t"."deleted_at" IS NULL) AND ("t"."competencia_date" IS NOT NULL) AND ("t"."status" <> 'CANCELADO'::"text"))
        )
 SELECT "tenant_id",
    "empresa_id",
    "competencia_date",
    "plano_contas_id",
    "plano_codigo",
    "plano_nome",
    ("sum"(
        CASE
            WHEN ("titulo_tipo" = 'AR'::"text") THEN "valor_rateado"
            ELSE (0)::numeric
        END))::numeric(15,2) AS "receita",
    ("sum"(
        CASE
            WHEN ("titulo_tipo" = 'AP'::"text") THEN "valor_rateado"
            ELSE (0)::numeric
        END))::numeric(15,2) AS "despesa",
    (("sum"(
        CASE
            WHEN ("titulo_tipo" = 'AR'::"text") THEN "valor_rateado"
            ELSE (0)::numeric
        END) - "sum"(
        CASE
            WHEN ("titulo_tipo" = 'AP'::"text") THEN "valor_rateado"
            ELSE (0)::numeric
        END)))::numeric(15,2) AS "resultado"
   FROM "base"
  GROUP BY "tenant_id", "empresa_id", "competencia_date", "plano_contas_id", "plano_codigo", "plano_nome";


ALTER VIEW "r"."r_dre_mensal_plano" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_dre_mensal_plano_filtrado" AS
 SELECT "tenant_id",
    "empresa_id",
    "competencia_date",
    "plano_contas_id",
    "plano_codigo",
    "plano_nome",
    "receita",
    "despesa",
    "resultado"
   FROM "r"."r_dre_mensal_plano" "d"
  WHERE (NOT (EXISTS ( SELECT 1
           FROM "r"."dre_plano_excluido" "e"
          WHERE (("e"."tenant_id" = "d"."tenant_id") AND ("e"."plano_contas_id" = "d"."plano_contas_id")))));


ALTER VIEW "r"."r_dre_mensal_plano_filtrado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_dre_mensal_filtrado" AS
 SELECT "tenant_id",
    "empresa_id",
    "competencia_date",
    ("sum"(COALESCE("receita", (0)::numeric)))::numeric(15,2) AS "receita",
    ("sum"(COALESCE("despesa", (0)::numeric)))::numeric(15,2) AS "despesa",
    ("sum"((COALESCE("receita", (0)::numeric) - COALESCE("despesa", (0)::numeric))))::numeric(15,2) AS "resultado"
   FROM "r"."r_dre_mensal_plano_filtrado" "d"
  GROUP BY "tenant_id", "empresa_id", "competencia_date";


ALTER VIEW "r"."r_dre_mensal_filtrado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_apuracao_irpj_csll_mensal_comp2" AS
 WITH RECURSIVE "dre" AS (
         SELECT "r_dre_mensal_filtrado"."tenant_id",
            "r_dre_mensal_filtrado"."empresa_id",
            "r_dre_mensal_filtrado"."competencia_date",
            "r_dre_mensal_filtrado"."resultado" AS "resultado_contabil"
           FROM "r"."r_dre_mensal_filtrado"
        ), "minc" AS (
         SELECT "dre"."tenant_id",
            "dre"."empresa_id",
            "min"("dre"."competencia_date") AS "min_competencia"
           FROM "dre"
          GROUP BY "dre"."tenant_id", "dre"."empresa_id"
        ), "param" AS (
         SELECT "p"."tenant_id",
            "p"."empresa_id",
            "p"."irpj_aliquota",
            "p"."irpj_adicional_aliquota",
            "p"."irpj_adicional_limite_mensal",
            "p"."csll_aliquota"
           FROM "f"."parametro_irpj_csll_empresa" "p"
          WHERE ("p"."deleted_at" IS NULL)
        ), "cfg" AS (
         SELECT "p"."tenant_id",
            "p"."empresa_id",
            COALESCE("si"."competencia_inicio", "m"."min_competencia") AS "competencia_inicio",
            (COALESCE("si"."saldo_prejuizo_irpj", (0)::numeric))::numeric(15,2) AS "saldo_prejuizo_irpj_inicial_cfg",
            (COALESCE("si"."saldo_base_negativa_csll", (0)::numeric))::numeric(15,2) AS "saldo_base_negativa_csll_inicial_cfg",
            "p"."irpj_aliquota",
            "p"."irpj_adicional_aliquota",
            "p"."irpj_adicional_limite_mensal",
            "p"."csll_aliquota"
           FROM (("param" "p"
             JOIN "minc" "m" ON ((("m"."tenant_id" = "p"."tenant_id") AND ("m"."empresa_id" = "p"."empresa_id"))))
             LEFT JOIN "f"."irpj_csll_saldo_inicial" "si" ON ((("si"."tenant_id" = "p"."tenant_id") AND ("si"."empresa_id" = "p"."empresa_id") AND ("si"."deleted_at" IS NULL))))
        ), "aj" AS (
         SELECT "a"."tenant_id",
            "a"."empresa_id",
            "a"."competencia_date",
            ("sum"(
                CASE
                    WHEN (("a"."tipo" = 'ADICAO'::"text") AND ("a"."escopo" = ANY (ARRAY['IRPJ'::"text", 'AMBOS'::"text"]))) THEN "a"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "adicoes_irpj",
            ("sum"(
                CASE
                    WHEN (("a"."tipo" = 'EXCLUSAO'::"text") AND ("a"."escopo" = ANY (ARRAY['IRPJ'::"text", 'AMBOS'::"text"]))) THEN "a"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "exclusoes_irpj",
            ("sum"(
                CASE
                    WHEN (("a"."tipo" = 'ADICAO'::"text") AND ("a"."escopo" = ANY (ARRAY['CSLL'::"text", 'AMBOS'::"text"]))) THEN "a"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "adicoes_csll",
            ("sum"(
                CASE
                    WHEN (("a"."tipo" = 'EXCLUSAO'::"text") AND ("a"."escopo" = ANY (ARRAY['CSLL'::"text", 'AMBOS'::"text"]))) THEN "a"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "exclusoes_csll"
           FROM "f"."irpj_csll_ajuste" "a"
          WHERE ("a"."deleted_at" IS NULL)
          GROUP BY "a"."tenant_id", "a"."empresa_id", "a"."competencia_date"
        ), "base" AS (
         SELECT "d"."tenant_id",
            "d"."empresa_id",
            "d"."competencia_date",
            (EXTRACT(year FROM "d"."competencia_date"))::integer AS "competencia_ano",
            (EXTRACT(month FROM "d"."competencia_date"))::integer AS "competencia_mes",
            "d"."resultado_contabil",
            (COALESCE("a"."adicoes_irpj", (0)::numeric))::numeric(15,2) AS "adicoes_irpj",
            (COALESCE("a"."exclusoes_irpj", (0)::numeric))::numeric(15,2) AS "exclusoes_irpj",
            (COALESCE("a"."adicoes_csll", (0)::numeric))::numeric(15,2) AS "adicoes_csll",
            (COALESCE("a"."exclusoes_csll", (0)::numeric))::numeric(15,2) AS "exclusoes_csll",
            "c"."competencia_inicio",
            "c"."saldo_prejuizo_irpj_inicial_cfg",
            "c"."saldo_base_negativa_csll_inicial_cfg",
            "c"."irpj_aliquota",
            "c"."irpj_adicional_aliquota",
            "c"."irpj_adicional_limite_mensal",
            "c"."csll_aliquota"
           FROM (("dre" "d"
             JOIN "cfg" "c" ON ((("c"."tenant_id" = "d"."tenant_id") AND ("c"."empresa_id" = "d"."empresa_id"))))
             LEFT JOIN "aj" "a" ON ((("a"."tenant_id" = "d"."tenant_id") AND ("a"."empresa_id" = "d"."empresa_id") AND ("a"."competencia_date" = "d"."competencia_date"))))
          WHERE ("d"."competencia_date" >= "c"."competencia_inicio")
        ), "calc" AS (
         SELECT "b"."tenant_id",
            "b"."empresa_id",
            "b"."competencia_date",
            "b"."competencia_ano",
            "b"."competencia_mes",
            "b"."resultado_contabil",
            "b"."adicoes_irpj",
            "b"."exclusoes_irpj",
            "b"."adicoes_csll",
            "b"."exclusoes_csll",
            "b"."competencia_inicio",
            "b"."saldo_prejuizo_irpj_inicial_cfg",
            "b"."saldo_base_negativa_csll_inicial_cfg",
            "b"."irpj_aliquota",
            "b"."irpj_adicional_aliquota",
            "b"."irpj_adicional_limite_mensal",
            "b"."csll_aliquota",
            ((("b"."resultado_contabil" + "b"."adicoes_irpj") - "b"."exclusoes_irpj"))::numeric(15,2) AS "lucro_fiscal_irpj_bruto",
            ((("b"."resultado_contabil" + "b"."adicoes_csll") - "b"."exclusoes_csll"))::numeric(15,2) AS "lucro_fiscal_csll_bruto",
            (GREATEST((("b"."resultado_contabil" + "b"."adicoes_irpj") - "b"."exclusoes_irpj"), (0)::numeric))::numeric(15,2) AS "base_irpj_bruta",
            (GREATEST((- (("b"."resultado_contabil" + "b"."adicoes_irpj") - "b"."exclusoes_irpj")), (0)::numeric))::numeric(15,2) AS "prejuizo_irpj_mes",
            (GREATEST((("b"."resultado_contabil" + "b"."adicoes_csll") - "b"."exclusoes_csll"), (0)::numeric))::numeric(15,2) AS "base_csll_bruta",
            (GREATEST((- (("b"."resultado_contabil" + "b"."adicoes_csll") - "b"."exclusoes_csll")), (0)::numeric))::numeric(15,2) AS "base_negativa_csll_mes"
           FROM "base" "b"
        ), "ord" AS (
         SELECT "c"."tenant_id",
            "c"."empresa_id",
            "c"."competencia_date",
            "c"."competencia_ano",
            "c"."competencia_mes",
            "c"."resultado_contabil",
            "c"."adicoes_irpj",
            "c"."exclusoes_irpj",
            "c"."adicoes_csll",
            "c"."exclusoes_csll",
            "c"."competencia_inicio",
            "c"."saldo_prejuizo_irpj_inicial_cfg",
            "c"."saldo_base_negativa_csll_inicial_cfg",
            "c"."irpj_aliquota",
            "c"."irpj_adicional_aliquota",
            "c"."irpj_adicional_limite_mensal",
            "c"."csll_aliquota",
            "c"."lucro_fiscal_irpj_bruto",
            "c"."lucro_fiscal_csll_bruto",
            "c"."base_irpj_bruta",
            "c"."prejuizo_irpj_mes",
            "c"."base_csll_bruta",
            "c"."base_negativa_csll_mes",
            "row_number"() OVER (PARTITION BY "c"."tenant_id", "c"."empresa_id" ORDER BY "c"."competencia_date") AS "rn"
           FROM "calc" "c"
        ), "rec" AS (
         SELECT "o"."tenant_id",
            "o"."empresa_id",
            "o"."competencia_date",
            "o"."competencia_ano",
            "o"."competencia_mes",
            "o"."resultado_contabil",
            "o"."adicoes_irpj",
            "o"."exclusoes_irpj",
            "o"."adicoes_csll",
            "o"."exclusoes_csll",
            "o"."competencia_inicio",
            "o"."saldo_prejuizo_irpj_inicial_cfg",
            "o"."saldo_base_negativa_csll_inicial_cfg",
            "o"."irpj_aliquota",
            "o"."irpj_adicional_aliquota",
            "o"."irpj_adicional_limite_mensal",
            "o"."csll_aliquota",
            "o"."lucro_fiscal_irpj_bruto",
            "o"."lucro_fiscal_csll_bruto",
            "o"."base_irpj_bruta",
            "o"."prejuizo_irpj_mes",
            "o"."base_csll_bruta",
            "o"."base_negativa_csll_mes",
            "o"."rn",
            "o"."saldo_prejuizo_irpj_inicial_cfg" AS "saldo_prejuizo_irpj_inicial",
            (LEAST("o"."saldo_prejuizo_irpj_inicial_cfg", "round"(("o"."base_irpj_bruta" * 0.30), 2)))::numeric(15,2) AS "compensacao_prejuizo_irpj",
            ((("o"."saldo_prejuizo_irpj_inicial_cfg" - LEAST("o"."saldo_prejuizo_irpj_inicial_cfg", "round"(("o"."base_irpj_bruta" * 0.30), 2))) + "o"."prejuizo_irpj_mes"))::numeric(15,2) AS "saldo_prejuizo_irpj_final",
            "o"."saldo_base_negativa_csll_inicial_cfg" AS "saldo_base_negativa_csll_inicial",
            (LEAST("o"."saldo_base_negativa_csll_inicial_cfg", "round"(("o"."base_csll_bruta" * 0.30), 2)))::numeric(15,2) AS "compensacao_base_negativa_csll",
            ((("o"."saldo_base_negativa_csll_inicial_cfg" - LEAST("o"."saldo_base_negativa_csll_inicial_cfg", "round"(("o"."base_csll_bruta" * 0.30), 2))) + "o"."base_negativa_csll_mes"))::numeric(15,2) AS "saldo_base_negativa_csll_final"
           FROM "ord" "o"
          WHERE ("o"."rn" = 1)
        UNION ALL
         SELECT "o"."tenant_id",
            "o"."empresa_id",
            "o"."competencia_date",
            "o"."competencia_ano",
            "o"."competencia_mes",
            "o"."resultado_contabil",
            "o"."adicoes_irpj",
            "o"."exclusoes_irpj",
            "o"."adicoes_csll",
            "o"."exclusoes_csll",
            "o"."competencia_inicio",
            "o"."saldo_prejuizo_irpj_inicial_cfg",
            "o"."saldo_base_negativa_csll_inicial_cfg",
            "o"."irpj_aliquota",
            "o"."irpj_adicional_aliquota",
            "o"."irpj_adicional_limite_mensal",
            "o"."csll_aliquota",
            "o"."lucro_fiscal_irpj_bruto",
            "o"."lucro_fiscal_csll_bruto",
            "o"."base_irpj_bruta",
            "o"."prejuizo_irpj_mes",
            "o"."base_csll_bruta",
            "o"."base_negativa_csll_mes",
            "o"."rn",
            "r"."saldo_prejuizo_irpj_final" AS "saldo_prejuizo_irpj_inicial",
            (LEAST("r"."saldo_prejuizo_irpj_final", "round"(("o"."base_irpj_bruta" * 0.30), 2)))::numeric(15,2) AS "compensacao_prejuizo_irpj",
            ((("r"."saldo_prejuizo_irpj_final" - LEAST("r"."saldo_prejuizo_irpj_final", "round"(("o"."base_irpj_bruta" * 0.30), 2))) + "o"."prejuizo_irpj_mes"))::numeric(15,2) AS "saldo_prejuizo_irpj_final",
            "r"."saldo_base_negativa_csll_final" AS "saldo_base_negativa_csll_inicial",
            (LEAST("r"."saldo_base_negativa_csll_final", "round"(("o"."base_csll_bruta" * 0.30), 2)))::numeric(15,2) AS "compensacao_base_negativa_csll",
            ((("r"."saldo_base_negativa_csll_final" - LEAST("r"."saldo_base_negativa_csll_final", "round"(("o"."base_csll_bruta" * 0.30), 2))) + "o"."base_negativa_csll_mes"))::numeric(15,2) AS "saldo_base_negativa_csll_final"
           FROM ("rec" "r"
             JOIN "ord" "o" ON ((("o"."tenant_id" = "r"."tenant_id") AND ("o"."empresa_id" = "r"."empresa_id") AND ("o"."rn" = ("r"."rn" + 1)))))
        )
 SELECT "tenant_id",
    "empresa_id",
    "competencia_date",
    "competencia_ano",
    "competencia_mes",
    "resultado_contabil",
    "adicoes_irpj",
    "exclusoes_irpj",
    "base_irpj_bruta",
    "prejuizo_irpj_mes",
    "saldo_prejuizo_irpj_inicial",
    "compensacao_prejuizo_irpj",
    "saldo_prejuizo_irpj_final",
    (("base_irpj_bruta" - "compensacao_prejuizo_irpj"))::numeric(15,2) AS "base_irpj",
    ("round"((("base_irpj_bruta" - "compensacao_prejuizo_irpj") * ("irpj_aliquota" / 100.0)), 2))::numeric(15,2) AS "irpj_15",
    "irpj_adicional_limite_mensal" AS "irpj_limite_adicional_mes",
    (GREATEST((("base_irpj_bruta" - "compensacao_prejuizo_irpj") - "irpj_adicional_limite_mensal"), (0)::numeric))::numeric(15,2) AS "base_irpj_adicional",
    ("round"((GREATEST((("base_irpj_bruta" - "compensacao_prejuizo_irpj") - "irpj_adicional_limite_mensal"), (0)::numeric) * ("irpj_adicional_aliquota" / 100.0)), 2))::numeric(15,2) AS "irpj_adicional",
    (("round"((("base_irpj_bruta" - "compensacao_prejuizo_irpj") * ("irpj_aliquota" / 100.0)), 2) + "round"((GREATEST((("base_irpj_bruta" - "compensacao_prejuizo_irpj") - "irpj_adicional_limite_mensal"), (0)::numeric) * ("irpj_adicional_aliquota" / 100.0)), 2)))::numeric(15,2) AS "irpj_total",
    "adicoes_csll",
    "exclusoes_csll",
    "base_csll_bruta",
    "base_negativa_csll_mes",
    "saldo_base_negativa_csll_inicial",
    "compensacao_base_negativa_csll",
    "saldo_base_negativa_csll_final",
    (("base_csll_bruta" - "compensacao_base_negativa_csll"))::numeric(15,2) AS "base_csll",
    ("round"((("base_csll_bruta" - "compensacao_base_negativa_csll") * ("csll_aliquota" / 100.0)), 2))::numeric(15,2) AS "csll_total"
   FROM "rec"
  ORDER BY "tenant_id", "empresa_id", "competencia_date" DESC;


ALTER VIEW "r"."r_apuracao_irpj_csll_mensal_comp2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_apuracao_irpj_csll_mensal" AS
 SELECT "tenant_id",
    "empresa_id",
    "competencia_date",
    "competencia_ano",
    "competencia_mes",
    "resultado_contabil",
    "adicoes_irpj",
    "exclusoes_irpj",
    "base_irpj",
    "prejuizo_irpj_mes" AS "prejuizo_irpj",
    "irpj_15",
    "irpj_limite_adicional_mes",
    "base_irpj_adicional",
    "irpj_adicional",
    "irpj_total",
    "adicoes_csll",
    "exclusoes_csll",
    "base_csll",
    "base_negativa_csll_mes" AS "base_negativa_csll",
    "csll_total"
   FROM "r"."r_apuracao_irpj_csll_mensal_comp2";


ALTER VIEW "r"."r_apuracao_irpj_csll_mensal" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_apuracao_irpj_csll_anual" AS
 WITH "m" AS (
         SELECT "r_apuracao_irpj_csll_mensal"."tenant_id",
            "r_apuracao_irpj_csll_mensal"."empresa_id",
            "r_apuracao_irpj_csll_mensal"."competencia_date",
            "r_apuracao_irpj_csll_mensal"."competencia_ano",
            "r_apuracao_irpj_csll_mensal"."competencia_mes",
            "r_apuracao_irpj_csll_mensal"."resultado_contabil",
            "r_apuracao_irpj_csll_mensal"."adicoes_irpj",
            "r_apuracao_irpj_csll_mensal"."exclusoes_irpj",
            "r_apuracao_irpj_csll_mensal"."base_irpj",
            "r_apuracao_irpj_csll_mensal"."prejuizo_irpj",
            "r_apuracao_irpj_csll_mensal"."irpj_15",
            "r_apuracao_irpj_csll_mensal"."irpj_limite_adicional_mes",
            "r_apuracao_irpj_csll_mensal"."base_irpj_adicional",
            "r_apuracao_irpj_csll_mensal"."irpj_adicional",
            "r_apuracao_irpj_csll_mensal"."irpj_total",
            "r_apuracao_irpj_csll_mensal"."adicoes_csll",
            "r_apuracao_irpj_csll_mensal"."exclusoes_csll",
            "r_apuracao_irpj_csll_mensal"."base_csll",
            "r_apuracao_irpj_csll_mensal"."base_negativa_csll",
            "r_apuracao_irpj_csll_mensal"."csll_total"
           FROM "r"."r_apuracao_irpj_csll_mensal"
        ), "param" AS (
         SELECT "parametro_irpj_csll_empresa"."tenant_id",
            "parametro_irpj_csll_empresa"."empresa_id",
            "parametro_irpj_csll_empresa"."irpj_adicional_limite_mensal" AS "limite_mensal"
           FROM "f"."parametro_irpj_csll_empresa"
          WHERE ("parametro_irpj_csll_empresa"."deleted_at" IS NULL)
        )
 SELECT "m"."tenant_id",
    "m"."empresa_id",
    "m"."competencia_ano",
    "count"(*) AS "meses",
    ("sum"("m"."resultado_contabil"))::numeric(15,2) AS "resultado_contabil_ano",
    ("sum"("m"."base_irpj"))::numeric(15,2) AS "base_irpj_ano",
    ("sum"("m"."prejuizo_irpj"))::numeric(15,2) AS "prejuizo_irpj_ano",
    ("sum"("m"."irpj_15"))::numeric(15,2) AS "irpj_15_soma_meses",
    ("sum"("m"."irpj_adicional"))::numeric(15,2) AS "irpj_adicional_soma_meses",
    ("sum"("m"."irpj_total"))::numeric(15,2) AS "irpj_total_soma_meses",
    (("p"."limite_mensal" * ("count"(*))::numeric))::numeric(15,2) AS "irpj_limite_adicional_periodo",
    (GREATEST(("sum"("m"."base_irpj") - ("p"."limite_mensal" * ("count"(*))::numeric)), (0)::numeric))::numeric(15,2) AS "base_irpj_adicional_periodo",
    ("sum"("m"."base_csll"))::numeric(15,2) AS "base_csll_ano",
    ("sum"("m"."csll_total"))::numeric(15,2) AS "csll_total_soma_meses"
   FROM ("m"
     JOIN "param" "p" ON ((("p"."tenant_id" = "m"."tenant_id") AND ("p"."empresa_id" = "m"."empresa_id"))))
  GROUP BY "m"."tenant_id", "m"."empresa_id", "m"."competencia_ano", "p"."limite_mensal";


ALTER VIEW "r"."r_apuracao_irpj_csll_anual" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_apuracao_irpj_csll_anual_comp" AS
 WITH RECURSIVE "mensal" AS (
         SELECT "m"."tenant_id",
            "m"."empresa_id",
            "m"."competencia_date",
            (EXTRACT(year FROM "m"."competencia_date"))::integer AS "competencia_ano",
            "m"."resultado_contabil",
            "m"."adicoes_irpj",
            "m"."exclusoes_irpj",
            "m"."adicoes_csll",
            "m"."exclusoes_csll"
           FROM "r"."r_apuracao_irpj_csll_mensal" "m"
        ), "param" AS (
         SELECT "parametro_irpj_csll_empresa"."tenant_id",
            "parametro_irpj_csll_empresa"."empresa_id",
            "parametro_irpj_csll_empresa"."irpj_aliquota",
            "parametro_irpj_csll_empresa"."irpj_adicional_aliquota",
            "parametro_irpj_csll_empresa"."irpj_adicional_limite_mensal",
            "parametro_irpj_csll_empresa"."csll_aliquota"
           FROM "f"."parametro_irpj_csll_empresa"
          WHERE ("parametro_irpj_csll_empresa"."deleted_at" IS NULL)
        ), "ano" AS (
         SELECT "mn"."tenant_id",
            "mn"."empresa_id",
            "mn"."competencia_ano",
            "count"(*) AS "meses",
            ("sum"("mn"."resultado_contabil"))::numeric(15,2) AS "resultado_contabil_ano",
            ("sum"("mn"."adicoes_irpj"))::numeric(15,2) AS "adicoes_irpj_ano",
            ("sum"("mn"."exclusoes_irpj"))::numeric(15,2) AS "exclusoes_irpj_ano",
            ("sum"("mn"."adicoes_csll"))::numeric(15,2) AS "adicoes_csll_ano",
            ("sum"("mn"."exclusoes_csll"))::numeric(15,2) AS "exclusoes_csll_ano"
           FROM "mensal" "mn"
          GROUP BY "mn"."tenant_id", "mn"."empresa_id", "mn"."competencia_ano"
        ), "calc" AS (
         SELECT "a"."tenant_id",
            "a"."empresa_id",
            "a"."competencia_ano",
            "a"."meses",
            "a"."resultado_contabil_ano",
            "a"."adicoes_irpj_ano",
            "a"."exclusoes_irpj_ano",
            "a"."adicoes_csll_ano",
            "a"."exclusoes_csll_ano",
            "p"."irpj_aliquota",
            "p"."irpj_adicional_aliquota",
            "p"."irpj_adicional_limite_mensal",
            "p"."csll_aliquota",
            ((("a"."resultado_contabil_ano" + "a"."adicoes_irpj_ano") - "a"."exclusoes_irpj_ano"))::numeric(15,2) AS "lucro_fiscal_irpj_bruto_ano",
            ((("a"."resultado_contabil_ano" + "a"."adicoes_csll_ano") - "a"."exclusoes_csll_ano"))::numeric(15,2) AS "lucro_fiscal_csll_bruto_ano",
            (GREATEST((("a"."resultado_contabil_ano" + "a"."adicoes_irpj_ano") - "a"."exclusoes_irpj_ano"), (0)::numeric))::numeric(15,2) AS "base_irpj_bruta_ano",
            (GREATEST((- (("a"."resultado_contabil_ano" + "a"."adicoes_irpj_ano") - "a"."exclusoes_irpj_ano")), (0)::numeric))::numeric(15,2) AS "prejuizo_irpj_ano",
            (GREATEST((("a"."resultado_contabil_ano" + "a"."adicoes_csll_ano") - "a"."exclusoes_csll_ano"), (0)::numeric))::numeric(15,2) AS "base_csll_bruta_ano",
            (GREATEST((- (("a"."resultado_contabil_ano" + "a"."adicoes_csll_ano") - "a"."exclusoes_csll_ano")), (0)::numeric))::numeric(15,2) AS "base_negativa_csll_ano"
           FROM ("ano" "a"
             JOIN "param" "p" ON ((("p"."tenant_id" = "a"."tenant_id") AND ("p"."empresa_id" = "a"."empresa_id"))))
        ), "ord" AS (
         SELECT "c"."tenant_id",
            "c"."empresa_id",
            "c"."competencia_ano",
            "c"."meses",
            "c"."resultado_contabil_ano",
            "c"."adicoes_irpj_ano",
            "c"."exclusoes_irpj_ano",
            "c"."adicoes_csll_ano",
            "c"."exclusoes_csll_ano",
            "c"."irpj_aliquota",
            "c"."irpj_adicional_aliquota",
            "c"."irpj_adicional_limite_mensal",
            "c"."csll_aliquota",
            "c"."lucro_fiscal_irpj_bruto_ano",
            "c"."lucro_fiscal_csll_bruto_ano",
            "c"."base_irpj_bruta_ano",
            "c"."prejuizo_irpj_ano",
            "c"."base_csll_bruta_ano",
            "c"."base_negativa_csll_ano",
            "row_number"() OVER (PARTITION BY "c"."tenant_id", "c"."empresa_id" ORDER BY "c"."competencia_ano") AS "rn"
           FROM "calc" "c"
        ), "rec" AS (
         SELECT "o"."tenant_id",
            "o"."empresa_id",
            "o"."competencia_ano",
            "o"."meses",
            "o"."resultado_contabil_ano",
            "o"."adicoes_irpj_ano",
            "o"."exclusoes_irpj_ano",
            "o"."adicoes_csll_ano",
            "o"."exclusoes_csll_ano",
            "o"."irpj_aliquota",
            "o"."irpj_adicional_aliquota",
            "o"."irpj_adicional_limite_mensal",
            "o"."csll_aliquota",
            "o"."lucro_fiscal_irpj_bruto_ano",
            "o"."lucro_fiscal_csll_bruto_ano",
            "o"."base_irpj_bruta_ano",
            "o"."prejuizo_irpj_ano",
            "o"."base_csll_bruta_ano",
            "o"."base_negativa_csll_ano",
            "o"."rn",
            (0)::numeric(15,2) AS "saldo_prejuizo_irpj_inicial",
            (0)::numeric(15,2) AS "compensacao_prejuizo_irpj",
            (((0)::numeric + "o"."prejuizo_irpj_ano"))::numeric(15,2) AS "saldo_prejuizo_irpj_final",
            (0)::numeric(15,2) AS "saldo_base_negativa_csll_inicial",
            (0)::numeric(15,2) AS "compensacao_base_negativa_csll",
            (((0)::numeric + "o"."base_negativa_csll_ano"))::numeric(15,2) AS "saldo_base_negativa_csll_final"
           FROM "ord" "o"
          WHERE ("o"."rn" = 1)
        UNION ALL
         SELECT "o"."tenant_id",
            "o"."empresa_id",
            "o"."competencia_ano",
            "o"."meses",
            "o"."resultado_contabil_ano",
            "o"."adicoes_irpj_ano",
            "o"."exclusoes_irpj_ano",
            "o"."adicoes_csll_ano",
            "o"."exclusoes_csll_ano",
            "o"."irpj_aliquota",
            "o"."irpj_adicional_aliquota",
            "o"."irpj_adicional_limite_mensal",
            "o"."csll_aliquota",
            "o"."lucro_fiscal_irpj_bruto_ano",
            "o"."lucro_fiscal_csll_bruto_ano",
            "o"."base_irpj_bruta_ano",
            "o"."prejuizo_irpj_ano",
            "o"."base_csll_bruta_ano",
            "o"."base_negativa_csll_ano",
            "o"."rn",
            "r"."saldo_prejuizo_irpj_final" AS "saldo_prejuizo_irpj_inicial",
            (LEAST("r"."saldo_prejuizo_irpj_final", "round"(("o"."base_irpj_bruta_ano" * 0.30), 2)))::numeric(15,2) AS "compensacao_prejuizo_irpj",
            ((("r"."saldo_prejuizo_irpj_final" - LEAST("r"."saldo_prejuizo_irpj_final", "round"(("o"."base_irpj_bruta_ano" * 0.30), 2))) + "o"."prejuizo_irpj_ano"))::numeric(15,2) AS "saldo_prejuizo_irpj_final",
            "r"."saldo_base_negativa_csll_final" AS "saldo_base_negativa_csll_inicial",
            (LEAST("r"."saldo_base_negativa_csll_final", "round"(("o"."base_csll_bruta_ano" * 0.30), 2)))::numeric(15,2) AS "compensacao_base_negativa_csll",
            ((("r"."saldo_base_negativa_csll_final" - LEAST("r"."saldo_base_negativa_csll_final", "round"(("o"."base_csll_bruta_ano" * 0.30), 2))) + "o"."base_negativa_csll_ano"))::numeric(15,2) AS "saldo_base_negativa_csll_final"
           FROM ("rec" "r"
             JOIN "ord" "o" ON ((("o"."tenant_id" = "r"."tenant_id") AND ("o"."empresa_id" = "r"."empresa_id") AND ("o"."rn" = ("r"."rn" + 1)))))
        )
 SELECT "tenant_id",
    "empresa_id",
    "competencia_ano",
    "meses",
    "resultado_contabil_ano",
    "adicoes_irpj_ano",
    "exclusoes_irpj_ano",
    "base_irpj_bruta_ano",
    "prejuizo_irpj_ano",
    "saldo_prejuizo_irpj_inicial",
    "compensacao_prejuizo_irpj",
    "saldo_prejuizo_irpj_final",
    (("base_irpj_bruta_ano" - "compensacao_prejuizo_irpj"))::numeric(15,2) AS "base_irpj_ano",
    ("round"((("base_irpj_bruta_ano" - "compensacao_prejuizo_irpj") * ("irpj_aliquota" / 100.0)), 2))::numeric(15,2) AS "irpj_15_ano",
    (("irpj_adicional_limite_mensal" * ("meses")::numeric))::numeric(15,2) AS "irpj_limite_adicional_periodo",
    (GREATEST((("base_irpj_bruta_ano" - "compensacao_prejuizo_irpj") - ("irpj_adicional_limite_mensal" * ("meses")::numeric)), (0)::numeric))::numeric(15,2) AS "base_irpj_adicional_periodo",
    ("round"((GREATEST((("base_irpj_bruta_ano" - "compensacao_prejuizo_irpj") - ("irpj_adicional_limite_mensal" * ("meses")::numeric)), (0)::numeric) * ("irpj_adicional_aliquota" / 100.0)), 2))::numeric(15,2) AS "irpj_adicional_ano",
    (("round"((("base_irpj_bruta_ano" - "compensacao_prejuizo_irpj") * ("irpj_aliquota" / 100.0)), 2) + "round"((GREATEST((("base_irpj_bruta_ano" - "compensacao_prejuizo_irpj") - ("irpj_adicional_limite_mensal" * ("meses")::numeric)), (0)::numeric) * ("irpj_adicional_aliquota" / 100.0)), 2)))::numeric(15,2) AS "irpj_total_ano",
    "adicoes_csll_ano",
    "exclusoes_csll_ano",
    "base_csll_bruta_ano",
    "base_negativa_csll_ano",
    "saldo_base_negativa_csll_inicial",
    "compensacao_base_negativa_csll",
    "saldo_base_negativa_csll_final",
    (("base_csll_bruta_ano" - "compensacao_base_negativa_csll"))::numeric(15,2) AS "base_csll_ano",
    ("round"((("base_csll_bruta_ano" - "compensacao_base_negativa_csll") * ("csll_aliquota" / 100.0)), 2))::numeric(15,2) AS "csll_total_ano"
   FROM "rec"
  ORDER BY "tenant_id", "empresa_id", "competencia_ano" DESC;


ALTER VIEW "r"."r_apuracao_irpj_csll_anual_comp" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_apuracao_irpj_csll_anual_comp2" AS
 WITH "m" AS (
         SELECT "r_apuracao_irpj_csll_mensal_comp2"."tenant_id",
            "r_apuracao_irpj_csll_mensal_comp2"."empresa_id",
            "r_apuracao_irpj_csll_mensal_comp2"."competencia_date",
            (EXTRACT(year FROM "r_apuracao_irpj_csll_mensal_comp2"."competencia_date"))::integer AS "competencia_ano",
            "r_apuracao_irpj_csll_mensal_comp2"."resultado_contabil",
            "r_apuracao_irpj_csll_mensal_comp2"."irpj_total",
            "r_apuracao_irpj_csll_mensal_comp2"."csll_total",
            "r_apuracao_irpj_csll_mensal_comp2"."saldo_prejuizo_irpj_inicial",
            "r_apuracao_irpj_csll_mensal_comp2"."saldo_prejuizo_irpj_final",
            "r_apuracao_irpj_csll_mensal_comp2"."saldo_base_negativa_csll_inicial",
            "r_apuracao_irpj_csll_mensal_comp2"."saldo_base_negativa_csll_final"
           FROM "r"."r_apuracao_irpj_csll_mensal_comp2"
        ), "w" AS (
         SELECT "m"."tenant_id",
            "m"."empresa_id",
            "m"."competencia_date",
            "m"."competencia_ano",
            "m"."resultado_contabil",
            "m"."irpj_total",
            "m"."csll_total",
            "m"."saldo_prejuizo_irpj_inicial",
            "m"."saldo_prejuizo_irpj_final",
            "m"."saldo_base_negativa_csll_inicial",
            "m"."saldo_base_negativa_csll_final",
            "first_value"("m"."saldo_prejuizo_irpj_inicial") OVER (PARTITION BY "m"."tenant_id", "m"."empresa_id", "m"."competencia_ano" ORDER BY "m"."competencia_date") AS "saldo_prejuizo_ini_ano",
            "last_value"("m"."saldo_prejuizo_irpj_final") OVER (PARTITION BY "m"."tenant_id", "m"."empresa_id", "m"."competencia_ano" ORDER BY "m"."competencia_date" ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS "saldo_prejuizo_fim_ano",
            "first_value"("m"."saldo_base_negativa_csll_inicial") OVER (PARTITION BY "m"."tenant_id", "m"."empresa_id", "m"."competencia_ano" ORDER BY "m"."competencia_date") AS "saldo_csll_ini_ano",
            "last_value"("m"."saldo_base_negativa_csll_final") OVER (PARTITION BY "m"."tenant_id", "m"."empresa_id", "m"."competencia_ano" ORDER BY "m"."competencia_date" ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS "saldo_csll_fim_ano"
           FROM "m"
        )
 SELECT "tenant_id",
    "empresa_id",
    "competencia_ano",
    "count"(*) AS "meses",
    ("sum"("resultado_contabil"))::numeric(15,2) AS "resultado_contabil_ano",
    ("sum"("irpj_total"))::numeric(15,2) AS "irpj_total_ano",
    ("sum"("csll_total"))::numeric(15,2) AS "csll_total_ano",
    ("max"("saldo_prejuizo_ini_ano"))::numeric(15,2) AS "saldo_prejuizo_ini_ano",
    ("max"("saldo_prejuizo_fim_ano"))::numeric(15,2) AS "saldo_prejuizo_fim_ano",
    ("max"("saldo_csll_ini_ano"))::numeric(15,2) AS "saldo_base_negativa_csll_ini_ano",
    ("max"("saldo_csll_fim_ano"))::numeric(15,2) AS "saldo_base_negativa_csll_fim_ano"
   FROM "w"
  GROUP BY "tenant_id", "empresa_id", "competencia_ano"
  ORDER BY "tenant_id", "empresa_id", "competencia_ano" DESC;


ALTER VIEW "r"."r_apuracao_irpj_csll_anual_comp2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_dre_mensal" AS
 WITH "m" AS (
         SELECT "r_dre_mensal_plano"."tenant_id",
            "r_dre_mensal_plano"."empresa_id",
            "r_dre_mensal_plano"."competencia_date",
            (EXTRACT(year FROM "r_dre_mensal_plano"."competencia_date"))::integer AS "competencia_ano",
            (EXTRACT(month FROM "r_dre_mensal_plano"."competencia_date"))::integer AS "competencia_mes",
            ("sum"("r_dre_mensal_plano"."receita"))::numeric(15,2) AS "receita",
            ("sum"("r_dre_mensal_plano"."despesa"))::numeric(15,2) AS "despesa",
            (("sum"("r_dre_mensal_plano"."receita") - "sum"("r_dre_mensal_plano"."despesa")))::numeric(15,2) AS "resultado"
           FROM "r"."r_dre_mensal_plano"
          GROUP BY "r_dre_mensal_plano"."tenant_id", "r_dre_mensal_plano"."empresa_id", "r_dre_mensal_plano"."competencia_date", ((EXTRACT(year FROM "r_dre_mensal_plano"."competencia_date"))::integer), ((EXTRACT(month FROM "r_dre_mensal_plano"."competencia_date"))::integer)
        )
 SELECT "tenant_id",
    "empresa_id",
    "competencia_date",
    "competencia_ano",
    "competencia_mes",
    "receita",
    "despesa",
    "resultado",
    ("sum"("receita") OVER (PARTITION BY "tenant_id", "empresa_id", "competencia_ano" ORDER BY "competencia_date" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS "receita_ytd",
    ("sum"("despesa") OVER (PARTITION BY "tenant_id", "empresa_id", "competencia_ano" ORDER BY "competencia_date" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS "despesa_ytd",
    ("sum"("resultado") OVER (PARTITION BY "tenant_id", "empresa_id", "competencia_ano" ORDER BY "competencia_date" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS "resultado_ytd"
   FROM "m"
  ORDER BY "competencia_date" DESC;


ALTER VIEW "r"."r_dre_mensal" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_apuracao_irpj_csll_mensal_comp" AS
 WITH RECURSIVE "dre" AS (
         SELECT "r_dre_mensal"."tenant_id",
            "r_dre_mensal"."empresa_id",
            "r_dre_mensal"."competencia_date",
            "r_dre_mensal"."resultado" AS "resultado_contabil"
           FROM "r"."r_dre_mensal"
        ), "param" AS (
         SELECT "parametro_irpj_csll_empresa"."tenant_id",
            "parametro_irpj_csll_empresa"."empresa_id",
            "parametro_irpj_csll_empresa"."regime_apuracao",
            "parametro_irpj_csll_empresa"."irpj_aliquota",
            "parametro_irpj_csll_empresa"."irpj_adicional_aliquota",
            "parametro_irpj_csll_empresa"."irpj_adicional_limite_mensal",
            "parametro_irpj_csll_empresa"."csll_aliquota"
           FROM "f"."parametro_irpj_csll_empresa"
          WHERE ("parametro_irpj_csll_empresa"."deleted_at" IS NULL)
        ), "aj" AS (
         SELECT "irpj_csll_ajuste"."tenant_id",
            "irpj_csll_ajuste"."empresa_id",
            "irpj_csll_ajuste"."competencia_date",
            ("sum"(
                CASE
                    WHEN (("irpj_csll_ajuste"."tipo" = 'ADICAO'::"text") AND ("irpj_csll_ajuste"."escopo" = ANY (ARRAY['IRPJ'::"text", 'AMBOS'::"text"]))) THEN "irpj_csll_ajuste"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "adicoes_irpj",
            ("sum"(
                CASE
                    WHEN (("irpj_csll_ajuste"."tipo" = 'EXCLUSAO'::"text") AND ("irpj_csll_ajuste"."escopo" = ANY (ARRAY['IRPJ'::"text", 'AMBOS'::"text"]))) THEN "irpj_csll_ajuste"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "exclusoes_irpj",
            ("sum"(
                CASE
                    WHEN (("irpj_csll_ajuste"."tipo" = 'ADICAO'::"text") AND ("irpj_csll_ajuste"."escopo" = ANY (ARRAY['CSLL'::"text", 'AMBOS'::"text"]))) THEN "irpj_csll_ajuste"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "adicoes_csll",
            ("sum"(
                CASE
                    WHEN (("irpj_csll_ajuste"."tipo" = 'EXCLUSAO'::"text") AND ("irpj_csll_ajuste"."escopo" = ANY (ARRAY['CSLL'::"text", 'AMBOS'::"text"]))) THEN "irpj_csll_ajuste"."valor"
                    ELSE (0)::numeric
                END))::numeric(15,2) AS "exclusoes_csll"
           FROM "f"."irpj_csll_ajuste"
          WHERE ("irpj_csll_ajuste"."deleted_at" IS NULL)
          GROUP BY "irpj_csll_ajuste"."tenant_id", "irpj_csll_ajuste"."empresa_id", "irpj_csll_ajuste"."competencia_date"
        ), "base" AS (
         SELECT "d"."tenant_id",
            "d"."empresa_id",
            "d"."competencia_date",
            (EXTRACT(year FROM "d"."competencia_date"))::integer AS "competencia_ano",
            (EXTRACT(month FROM "d"."competencia_date"))::integer AS "competencia_mes",
            "d"."resultado_contabil",
            (COALESCE("a"."adicoes_irpj", (0)::numeric))::numeric(15,2) AS "adicoes_irpj",
            (COALESCE("a"."exclusoes_irpj", (0)::numeric))::numeric(15,2) AS "exclusoes_irpj",
            (COALESCE("a"."adicoes_csll", (0)::numeric))::numeric(15,2) AS "adicoes_csll",
            (COALESCE("a"."exclusoes_csll", (0)::numeric))::numeric(15,2) AS "exclusoes_csll",
            "p"."regime_apuracao",
            "p"."irpj_aliquota",
            "p"."irpj_adicional_aliquota",
            "p"."irpj_adicional_limite_mensal",
            "p"."csll_aliquota"
           FROM (("dre" "d"
             JOIN "param" "p" ON ((("p"."tenant_id" = "d"."tenant_id") AND ("p"."empresa_id" = "d"."empresa_id"))))
             LEFT JOIN "aj" "a" ON ((("a"."tenant_id" = "d"."tenant_id") AND ("a"."empresa_id" = "d"."empresa_id") AND ("a"."competencia_date" = "d"."competencia_date"))))
        ), "calc" AS (
         SELECT "b"."tenant_id",
            "b"."empresa_id",
            "b"."competencia_date",
            "b"."competencia_ano",
            "b"."competencia_mes",
            "b"."resultado_contabil",
            "b"."adicoes_irpj",
            "b"."exclusoes_irpj",
            "b"."adicoes_csll",
            "b"."exclusoes_csll",
            "b"."regime_apuracao",
            "b"."irpj_aliquota",
            "b"."irpj_adicional_aliquota",
            "b"."irpj_adicional_limite_mensal",
            "b"."csll_aliquota",
            ((("b"."resultado_contabil" + "b"."adicoes_irpj") - "b"."exclusoes_irpj"))::numeric(15,2) AS "lucro_fiscal_irpj_bruto",
            ((("b"."resultado_contabil" + "b"."adicoes_csll") - "b"."exclusoes_csll"))::numeric(15,2) AS "lucro_fiscal_csll_bruto",
            (GREATEST((("b"."resultado_contabil" + "b"."adicoes_irpj") - "b"."exclusoes_irpj"), (0)::numeric))::numeric(15,2) AS "base_irpj_bruta",
            (GREATEST((- (("b"."resultado_contabil" + "b"."adicoes_irpj") - "b"."exclusoes_irpj")), (0)::numeric))::numeric(15,2) AS "prejuizo_irpj_mes",
            (GREATEST((("b"."resultado_contabil" + "b"."adicoes_csll") - "b"."exclusoes_csll"), (0)::numeric))::numeric(15,2) AS "base_csll_bruta",
            (GREATEST((- (("b"."resultado_contabil" + "b"."adicoes_csll") - "b"."exclusoes_csll")), (0)::numeric))::numeric(15,2) AS "base_negativa_csll_mes"
           FROM "base" "b"
        ), "ord" AS (
         SELECT "c"."tenant_id",
            "c"."empresa_id",
            "c"."competencia_date",
            "c"."competencia_ano",
            "c"."competencia_mes",
            "c"."resultado_contabil",
            "c"."adicoes_irpj",
            "c"."exclusoes_irpj",
            "c"."adicoes_csll",
            "c"."exclusoes_csll",
            "c"."regime_apuracao",
            "c"."irpj_aliquota",
            "c"."irpj_adicional_aliquota",
            "c"."irpj_adicional_limite_mensal",
            "c"."csll_aliquota",
            "c"."lucro_fiscal_irpj_bruto",
            "c"."lucro_fiscal_csll_bruto",
            "c"."base_irpj_bruta",
            "c"."prejuizo_irpj_mes",
            "c"."base_csll_bruta",
            "c"."base_negativa_csll_mes",
            "row_number"() OVER (PARTITION BY "c"."tenant_id", "c"."empresa_id" ORDER BY "c"."competencia_date") AS "rn"
           FROM "calc" "c"
        ), "rec" AS (
         SELECT "o"."tenant_id",
            "o"."empresa_id",
            "o"."competencia_date",
            "o"."competencia_ano",
            "o"."competencia_mes",
            "o"."resultado_contabil",
            "o"."adicoes_irpj",
            "o"."exclusoes_irpj",
            "o"."adicoes_csll",
            "o"."exclusoes_csll",
            "o"."regime_apuracao",
            "o"."irpj_aliquota",
            "o"."irpj_adicional_aliquota",
            "o"."irpj_adicional_limite_mensal",
            "o"."csll_aliquota",
            "o"."lucro_fiscal_irpj_bruto",
            "o"."lucro_fiscal_csll_bruto",
            "o"."base_irpj_bruta",
            "o"."prejuizo_irpj_mes",
            "o"."base_csll_bruta",
            "o"."base_negativa_csll_mes",
            "o"."rn",
            (0)::numeric(15,2) AS "saldo_prejuizo_irpj_inicial",
            (0)::numeric(15,2) AS "compensacao_prejuizo_irpj",
            (((0)::numeric + "o"."prejuizo_irpj_mes"))::numeric(15,2) AS "saldo_prejuizo_irpj_final",
            (0)::numeric(15,2) AS "saldo_base_negativa_csll_inicial",
            (0)::numeric(15,2) AS "compensacao_base_negativa_csll",
            (((0)::numeric + "o"."base_negativa_csll_mes"))::numeric(15,2) AS "saldo_base_negativa_csll_final"
           FROM "ord" "o"
          WHERE ("o"."rn" = 1)
        UNION ALL
         SELECT "o"."tenant_id",
            "o"."empresa_id",
            "o"."competencia_date",
            "o"."competencia_ano",
            "o"."competencia_mes",
            "o"."resultado_contabil",
            "o"."adicoes_irpj",
            "o"."exclusoes_irpj",
            "o"."adicoes_csll",
            "o"."exclusoes_csll",
            "o"."regime_apuracao",
            "o"."irpj_aliquota",
            "o"."irpj_adicional_aliquota",
            "o"."irpj_adicional_limite_mensal",
            "o"."csll_aliquota",
            "o"."lucro_fiscal_irpj_bruto",
            "o"."lucro_fiscal_csll_bruto",
            "o"."base_irpj_bruta",
            "o"."prejuizo_irpj_mes",
            "o"."base_csll_bruta",
            "o"."base_negativa_csll_mes",
            "o"."rn",
            "r"."saldo_prejuizo_irpj_final" AS "saldo_prejuizo_irpj_inicial",
            (LEAST("r"."saldo_prejuizo_irpj_final", "round"(("o"."base_irpj_bruta" * 0.30), 2)))::numeric(15,2) AS "compensacao_prejuizo_irpj",
            ((("r"."saldo_prejuizo_irpj_final" - LEAST("r"."saldo_prejuizo_irpj_final", "round"(("o"."base_irpj_bruta" * 0.30), 2))) + "o"."prejuizo_irpj_mes"))::numeric(15,2) AS "saldo_prejuizo_irpj_final",
            "r"."saldo_base_negativa_csll_final" AS "saldo_base_negativa_csll_inicial",
            (LEAST("r"."saldo_base_negativa_csll_final", "round"(("o"."base_csll_bruta" * 0.30), 2)))::numeric(15,2) AS "compensacao_base_negativa_csll",
            ((("r"."saldo_base_negativa_csll_final" - LEAST("r"."saldo_base_negativa_csll_final", "round"(("o"."base_csll_bruta" * 0.30), 2))) + "o"."base_negativa_csll_mes"))::numeric(15,2) AS "saldo_base_negativa_csll_final"
           FROM ("rec" "r"
             JOIN "ord" "o" ON ((("o"."tenant_id" = "r"."tenant_id") AND ("o"."empresa_id" = "r"."empresa_id") AND ("o"."rn" = ("r"."rn" + 1)))))
        )
 SELECT "tenant_id",
    "empresa_id",
    "competencia_date",
    "competencia_ano",
    "competencia_mes",
    "resultado_contabil",
    "adicoes_irpj",
    "exclusoes_irpj",
    "base_irpj_bruta",
    "prejuizo_irpj_mes",
    "saldo_prejuizo_irpj_inicial",
    "compensacao_prejuizo_irpj",
    "saldo_prejuizo_irpj_final",
    (("base_irpj_bruta" - "compensacao_prejuizo_irpj"))::numeric(15,2) AS "base_irpj",
    ("round"((("base_irpj_bruta" - "compensacao_prejuizo_irpj") * ("irpj_aliquota" / 100.0)), 2))::numeric(15,2) AS "irpj_15",
    "irpj_adicional_limite_mensal" AS "irpj_limite_adicional_mes",
    (GREATEST((("base_irpj_bruta" - "compensacao_prejuizo_irpj") - "irpj_adicional_limite_mensal"), (0)::numeric))::numeric(15,2) AS "base_irpj_adicional",
    ("round"((GREATEST((("base_irpj_bruta" - "compensacao_prejuizo_irpj") - "irpj_adicional_limite_mensal"), (0)::numeric) * ("irpj_adicional_aliquota" / 100.0)), 2))::numeric(15,2) AS "irpj_adicional",
    (("round"((("base_irpj_bruta" - "compensacao_prejuizo_irpj") * ("irpj_aliquota" / 100.0)), 2) + "round"((GREATEST((("base_irpj_bruta" - "compensacao_prejuizo_irpj") - "irpj_adicional_limite_mensal"), (0)::numeric) * ("irpj_adicional_aliquota" / 100.0)), 2)))::numeric(15,2) AS "irpj_total",
    "adicoes_csll",
    "exclusoes_csll",
    "base_csll_bruta",
    "base_negativa_csll_mes",
    "saldo_base_negativa_csll_inicial",
    "compensacao_base_negativa_csll",
    "saldo_base_negativa_csll_final",
    (("base_csll_bruta" - "compensacao_base_negativa_csll"))::numeric(15,2) AS "base_csll",
    ("round"((("base_csll_bruta" - "compensacao_base_negativa_csll") * ("csll_aliquota" / 100.0)), 2))::numeric(15,2) AS "csll_total"
   FROM "rec"
  ORDER BY "tenant_id", "empresa_id", "competencia_date" DESC;


ALTER VIEW "r"."r_apuracao_irpj_csll_mensal_comp" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_documentos_pendentes_xml" AS
 SELECT "df"."tenant_id",
    "df"."empresa_id",
    "df"."competencia_date",
    "df"."id" AS "documento_fiscal_id",
    "df"."chave_acesso",
    "df"."operacao",
    "df"."natureza",
    "df"."emissao_date",
    "df"."valor_total",
    "p"."tipo",
    "p"."detalhe",
    "p"."created_at" AS "pendencia_created_at"
   FROM ("f"."documento_fiscal_pendencia" "p"
     JOIN "f"."documento_fiscal" "df" ON (("df"."id" = "p"."documento_fiscal_id")))
  WHERE (("p"."resolved_at" IS NULL) AND ("df"."deleted_at" IS NULL));


ALTER VIEW "r"."r_documentos_pendentes_xml" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_guardiao_impostos_docs" AS
 WITH "docs" AS (
         SELECT "df"."tenant_id",
            "df"."empresa_id",
            "df"."competencia_date",
            "df"."id" AS "documento_fiscal_id",
            "df"."operacao",
            "df"."natureza",
            "df"."chave_acesso",
            "df"."source_nf_entrada_id" AS "nf_entrada_id",
            COALESCE(NULLIF("btrim"("ne"."xml_raw"), ''::"text"), NULLIF("btrim"("dfx"."xml_raw"), ''::"text")) AS "xml_text"
           FROM (("f"."documento_fiscal" "df"
             LEFT JOIN "public"."nf_entrada" "ne" ON ((("ne"."tenant_id" = "df"."tenant_id") AND ("ne"."id" = "df"."source_nf_entrada_id"))))
             LEFT JOIN "f"."documento_fiscal_xml" "dfx" ON ((("dfx"."tenant_id" = "df"."tenant_id") AND ("dfx"."documento_fiscal_id" = "df"."id") AND ("dfx"."deleted_at" IS NULL))))
          WHERE (("df"."deleted_at" IS NULL) AND ("df"."natureza" = 'PRODUTO'::"text") AND ("length"("df"."chave_acesso") = 44))
        ), "xml_faltando" AS (
         SELECT "docs"."tenant_id",
            "docs"."empresa_id",
            "docs"."competencia_date",
            "docs"."documento_fiscal_id",
            "docs"."nf_entrada_id",
            "docs"."chave_acesso",
            "docs"."operacao",
            'XML_FALTANDO'::"text" AS "tipo",
            NULL::"text" AS "imposto",
            NULL::"text" AS "natureza_esperada",
            NULL::numeric AS "esperado",
            NULL::numeric AS "encontrado",
            NULL::numeric AS "diff",
            'Sem XML em nf_entrada.xml_raw e sem backup em f.documento_fiscal_xml.'::"text" AS "detalhe"
           FROM "docs"
          WHERE ("docs"."xml_text" IS NULL)
        ), "xml_docs" AS (
         SELECT "d"."tenant_id",
            "d"."empresa_id",
            "d"."competencia_date",
            "d"."documento_fiscal_id",
            "d"."operacao",
            "d"."natureza",
            "d"."chave_acesso",
            "d"."nf_entrada_id",
            "d"."xml_text",
            ("d"."xml_text")::"xml" AS "nfe_xml",
                CASE
                    WHEN ("d"."operacao" = 'ENTRADA'::"text") THEN 'CREDITO'::"text"
                    ELSE 'DEBITO'::"text"
                END AS "natureza_esperada"
           FROM "docs" "d"
          WHERE ("d"."xml_text" IS NOT NULL)
        ), "exp" AS (
         SELECT "x"."tenant_id",
            "x"."empresa_id",
            "x"."competencia_date",
            "x"."documento_fiscal_id",
            "x"."operacao",
            "x"."natureza",
            "x"."chave_acesso",
            "x"."nf_entrada_id",
            "x"."xml_text",
            "x"."nfe_xml",
            "x"."natureza_esperada",
            COALESCE("f"."_nfe_xpath_num"("x"."nfe_xml", '//nfe:ICMSTot/nfe:vBC/text()'::"text"), (0)::numeric) AS "exp_icms_base",
            COALESCE("f"."_nfe_xpath_num"("x"."nfe_xml", '//nfe:ICMSTot/nfe:vICMS/text()'::"text"), (0)::numeric) AS "exp_icms_valor",
            COALESCE("f"."_nfe_xpath_num"("x"."nfe_xml", '//nfe:ICMSTot/nfe:vIPI/text()'::"text"), (0)::numeric) AS "exp_ipi_valor",
            COALESCE("f"."_nfe_xpath_num"("x"."nfe_xml", '//nfe:ICMSTot/nfe:vPIS/text()'::"text"), (0)::numeric) AS "exp_pis_valor",
            COALESCE("f"."_nfe_xpath_num"("x"."nfe_xml", '//nfe:ICMSTot/nfe:vCOFINS/text()'::"text"), (0)::numeric) AS "exp_cofins_valor"
           FROM "xml_docs" "x"
        ), "got" AS (
         SELECT "e"."documento_fiscal_id",
            "max"("i"."base_calculo") FILTER (WHERE (("i"."imposto" = 'ICMS'::"text") AND ("i"."natureza" = "e"."natureza_esperada"))) AS "got_icms_base",
            "max"("i"."valor_calculado") FILTER (WHERE (("i"."imposto" = 'ICMS'::"text") AND ("i"."natureza" = "e"."natureza_esperada"))) AS "got_icms_valor",
            "max"("i"."valor_calculado") FILTER (WHERE (("i"."imposto" = 'IPI'::"text") AND ("i"."natureza" = "e"."natureza_esperada"))) AS "got_ipi_valor",
            "max"("i"."valor_calculado") FILTER (WHERE (("i"."imposto" = 'PIS'::"text") AND ("i"."natureza" = "e"."natureza_esperada"))) AS "got_pis_valor",
            "max"("i"."valor_calculado") FILTER (WHERE (("i"."imposto" = 'COFINS'::"text") AND ("i"."natureza" = "e"."natureza_esperada"))) AS "got_cofins_valor"
           FROM ("exp" "e"
             LEFT JOIN "f"."documento_fiscal_imposto" "i" ON ((("i"."tenant_id" = "e"."tenant_id") AND ("i"."documento_fiscal_id" = "e"."documento_fiscal_id") AND ("i"."deleted_at" IS NULL) AND ("i"."imposto" = ANY (ARRAY['ICMS'::"text", 'IPI'::"text", 'PIS'::"text", 'COFINS'::"text"])))))
          GROUP BY "e"."documento_fiscal_id"
        ), "div_xml" AS (
         SELECT "e"."tenant_id",
            "e"."empresa_id",
            "e"."competencia_date",
            "e"."documento_fiscal_id",
            "e"."nf_entrada_id",
            "e"."chave_acesso",
            "e"."operacao",
            'IMPOSTO_DIVERGENTE_XML'::"text" AS "tipo",
            "v"."imposto",
            "e"."natureza_esperada",
            "v"."esperado",
            "v"."encontrado",
            ("v"."esperado" - "v"."encontrado") AS "diff",
            'Diferença entre total do XML e documento_fiscal_imposto.'::"text" AS "detalhe"
           FROM (("exp" "e"
             JOIN "got" "g" ON (("g"."documento_fiscal_id" = "e"."documento_fiscal_id")))
             CROSS JOIN LATERAL ( VALUES ('ICMS'::"text","e"."exp_icms_valor",COALESCE("g"."got_icms_valor", (0)::numeric)), ('IPI'::"text","e"."exp_ipi_valor",COALESCE("g"."got_ipi_valor", (0)::numeric)), ('PIS'::"text","e"."exp_pis_valor",COALESCE("g"."got_pis_valor", (0)::numeric)), ('COFINS'::"text","e"."exp_cofins_valor",COALESCE("g"."got_cofins_valor", (0)::numeric))) "v"("imposto", "esperado", "encontrado"))
          WHERE ("abs"(("v"."esperado" - "v"."encontrado")) > 0.01)
        ), "faltando_xml" AS (
         SELECT "e"."tenant_id",
            "e"."empresa_id",
            "e"."competencia_date",
            "e"."documento_fiscal_id",
            "e"."nf_entrada_id",
            "e"."chave_acesso",
            "e"."operacao",
            'IMPOSTO_FALTANDO_XML'::"text" AS "tipo",
            "v"."imposto",
            "e"."natureza_esperada",
            "v"."esperado",
            "v"."encontrado",
            ("v"."esperado" - "v"."encontrado") AS "diff",
            'XML tem valor > 0, mas não existe linha correspondente em documento_fiscal_imposto.'::"text" AS "detalhe"
           FROM (("exp" "e"
             JOIN "got" "g" ON (("g"."documento_fiscal_id" = "e"."documento_fiscal_id")))
             CROSS JOIN LATERAL ( VALUES ('ICMS'::"text","e"."exp_icms_valor",COALESCE("g"."got_icms_valor", (0)::numeric)), ('IPI'::"text","e"."exp_ipi_valor",COALESCE("g"."got_ipi_valor", (0)::numeric)), ('PIS'::"text","e"."exp_pis_valor",COALESCE("g"."got_pis_valor", (0)::numeric)), ('COFINS'::"text","e"."exp_cofins_valor",COALESCE("g"."got_cofins_valor", (0)::numeric))) "v"("imposto", "esperado", "encontrado"))
          WHERE (("v"."esperado" > 0.01) AND ("v"."encontrado" = (0)::numeric))
        )
 SELECT "xml_faltando"."tenant_id",
    "xml_faltando"."empresa_id",
    "xml_faltando"."competencia_date",
    "xml_faltando"."documento_fiscal_id",
    "xml_faltando"."nf_entrada_id",
    "xml_faltando"."chave_acesso",
    "xml_faltando"."operacao",
    "xml_faltando"."tipo",
    "xml_faltando"."imposto",
    "xml_faltando"."natureza_esperada",
    "xml_faltando"."esperado",
    "xml_faltando"."encontrado",
    "xml_faltando"."diff",
    "xml_faltando"."detalhe"
   FROM "xml_faltando"
UNION ALL
 SELECT "faltando_xml"."tenant_id",
    "faltando_xml"."empresa_id",
    "faltando_xml"."competencia_date",
    "faltando_xml"."documento_fiscal_id",
    "faltando_xml"."nf_entrada_id",
    "faltando_xml"."chave_acesso",
    "faltando_xml"."operacao",
    "faltando_xml"."tipo",
    "faltando_xml"."imposto",
    "faltando_xml"."natureza_esperada",
    "faltando_xml"."esperado",
    "faltando_xml"."encontrado",
    "faltando_xml"."diff",
    "faltando_xml"."detalhe"
   FROM "faltando_xml"
UNION ALL
 SELECT "div_xml"."tenant_id",
    "div_xml"."empresa_id",
    "div_xml"."competencia_date",
    "div_xml"."documento_fiscal_id",
    "div_xml"."nf_entrada_id",
    "div_xml"."chave_acesso",
    "div_xml"."operacao",
    "div_xml"."tipo",
    "div_xml"."imposto",
    "div_xml"."natureza_esperada",
    "div_xml"."esperado",
    "div_xml"."encontrado",
    "div_xml"."diff",
    "div_xml"."detalhe"
   FROM "div_xml";


ALTER VIEW "r"."r_guardiao_impostos_docs" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_i_caixa_custo" AS
 SELECT "cx"."tenant_id",
    "cx"."empresa_id",
    "cx"."id" AS "caixa_id",
    "cx"."codigo" AS "caixa_codigo",
    "cx"."nome" AS "caixa_nome",
    (COALESCE("sum"(("ci"."quantidade" * "f"."custo_unit")), (0)::numeric))::numeric(15,2) AS "custo_total"
   FROM (("c"."i_caixa" "cx"
     LEFT JOIN "c"."i_caixa_item" "ci" ON ((("ci"."caixa_id" = "cx"."id") AND ("ci"."deleted_at" IS NULL))))
     LEFT JOIN "c"."i_ferramenta" "f" ON ((("f"."id" = "ci"."ferramenta_id") AND ("f"."deleted_at" IS NULL))))
  WHERE ("cx"."deleted_at" IS NULL)
  GROUP BY "cx"."tenant_id", "cx"."empresa_id", "cx"."id", "cx"."codigo", "cx"."nome";


ALTER VIEW "r"."r_i_caixa_custo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_itens_ativos" AS
 SELECT "id",
    "codigo_interno",
    "codigo_barras",
    "nome",
    "descricao",
    "tipo",
    "categoria",
    "subcategoria",
    "unidade_medida",
    "peso_bruto",
    "peso_liquido",
    "controla_estoque",
    "estoque_minimo",
    "estoque_maximo",
    "estoque_ideal",
    "custo_ultima_compra",
    "custo_medio",
    "data_ultima_compra",
    "preco_unitario",
    "preco_promocional",
    "data_atualizacao_preco",
    "margem_lucro_percentual",
    "ncm",
    "cest",
    "cfop_padrao",
    "aliquota_icms",
    "aliquota_ipi",
    "aliquota_pis",
    "aliquota_cofins",
    "fornecedor_id",
    "codigo_fornecedor",
    "controla_lote",
    "controla_validade",
    "dias_alerta_vencimento",
    "ativo",
    "observacoes",
    "criado_em",
    "criado_por",
    "atualizado_em",
    "atualizado_por",
    "fabricante",
    "tenant_id",
    "finalidade",
    "empresa_id",
    "motivo_compra_id",
    "created_at",
    "updated_at",
    "codigo_interno_sem_zeros",
    "codigo_fornecedor_sem_zeros",
    "mesclado_em_item_id",
    "mesclado_em",
    "mesclado_motivo"
   FROM "public"."itens"
  WHERE (("ativo" = true) AND ("mesclado_em_item_id" IS NULL));


ALTER VIEW "r"."r_itens_ativos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_motivo_compra_rank" AS
 WITH "uso_titulos" AS (
         SELECT "t"."tenant_id",
            "t"."motivo_compra_id",
            "count"(*) AS "qtd_usos_180d"
           FROM "f"."titulo" "t"
          WHERE (("t"."deleted_at" IS NULL) AND ("t"."created_at" >= ("now"() - '180 days'::interval)) AND ("t"."motivo_compra_id" IS NOT NULL))
          GROUP BY "t"."tenant_id", "t"."motivo_compra_id"
        )
 SELECT "mc"."id",
    "mc"."tenant_id",
    "mc"."codigo",
    "mc"."nome",
    "mc"."requires_text",
    "mc"."requires_os",
    "mc"."ativo",
    "mc"."created_at",
    "mc"."updated_at",
    "mc"."created_by",
    "mc"."updated_by",
    "mc"."deleted_at",
    "mc"."aplica_em",
    "mc"."plano_contas_id",
    "mc"."favorito",
    "mc"."ordem",
    "mc"."visivel_import_nfe",
    COALESCE("ut"."qtd_usos_180d", (0)::bigint) AS "qtd_usos_180d"
   FROM ("f"."motivo_compra" "mc"
     LEFT JOIN "uso_titulos" "ut" ON ((("ut"."tenant_id" = "mc"."tenant_id") AND ("ut"."motivo_compra_id" = "mc"."id"))))
  WHERE (("mc"."deleted_at" IS NULL) AND ("mc"."ativo" = true) AND ("mc"."visivel_import_nfe" = true));


ALTER VIEW "r"."r_motivo_compra_rank" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_nfse_iss_conferencia" AS
 SELECT "df"."tenant_id",
    "df"."empresa_id",
    "df"."id" AS "documento_fiscal_id",
    "df"."emissao_date",
    "df"."modelo",
    "df"."serie",
    "df"."numero",
    "df"."chave_acesso",
    "df"."valor_total",
    "df"."valor_servicos",
    "df"."material_percent",
    "df"."material_valor",
    "imp"."natureza" AS "iss_natureza",
    "imp"."base_original",
    "imp"."deducoes",
    "imp"."base_calculo",
    "imp"."aliquota",
    "imp"."valor_calculado",
    "imp"."valor_ajustado",
    "df"."created_at",
    "df"."updated_at"
   FROM ("f"."documento_fiscal" "df"
     LEFT JOIN "f"."documento_fiscal_imposto" "imp" ON ((("imp"."documento_fiscal_id" = "df"."id") AND ("imp"."tenant_id" = "df"."tenant_id") AND ("imp"."imposto" = 'ISS'::"text") AND ("imp"."deleted_at" IS NULL))))
  WHERE (("df"."deleted_at" IS NULL) AND ("df"."operacao" = 'SAIDA'::"text") AND ("df"."natureza" = 'SERVICO'::"text"));


ALTER VIEW "r"."r_nfse_iss_conferencia" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_orcamento_catalogo_busca" AS
SELECT
    NULL::"text" AS "origem",
    NULL::"uuid" AS "tenant_id",
    NULL::"uuid" AS "empresa_id",
    NULL::"text" AS "ref_id",
    NULL::integer AS "item_id",
    NULL::"uuid" AS "conjunto_id",
    NULL::"text" AS "codigo",
    NULL::"text" AS "nome",
    NULL::"text" AS "unidade",
    NULL::"text" AS "tipo",
    NULL::numeric(15,2) AS "preco_sugerido";


ALTER VIEW "r"."r_orcamento_catalogo_busca" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_orcamento_itens" AS
 SELECT "id",
    "orcamento_id",
    "seq",
    "item_id",
    "item_tipo",
    "item_nome",
    "unidade",
    "quantidade",
    "valor_unitario",
    "desconto_item_percent",
    "acrescimo_cond_pag_percent",
    "desconto_global_percent",
    "valor_total_bruto",
    "valor_total",
    "valor_unitario_liquido",
    "created_at",
    "updated_at",
    "tenant_id",
    "empresa_id"
   FROM "m"."orcamento_item" "oi"
  WHERE ("deleted_at" IS NULL);


ALTER VIEW "r"."r_orcamento_itens" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_orcamento_lista" AS
 SELECT "o"."id",
    "o"."tenant_id",
    "o"."empresa_id",
    "o"."codigo",
    "o"."numero",
    "o"."versao",
    "o"."status",
    "o"."emissao_date",
    "o"."titulo",
    "o"."cliente_id",
    "c1"."nome" AS "cliente_nome",
    "o"."vendedor_usuario_id",
    "u"."nome" AS "vendedor_nome",
    "o"."condicao_pagamento_id",
    "cp"."nome" AS "condicao_pagamento_nome",
    "o"."desconto_global_percent",
    "o"."acrescimo_cond_pag_percent",
    "o"."valor_frete",
    "o"."total_produtos",
    "o"."total_servicos",
    "o"."total_bruto",
    "o"."total_desconto_global",
    "o"."total_liquido",
    "o"."created_at",
    "o"."updated_at"
   FROM ((("m"."orcamento" "o"
     JOIN "public"."clientes" "c1" ON (("c1"."id" = "o"."cliente_id")))
     JOIN "a"."usuario" "u" ON (("u"."id" = "o"."vendedor_usuario_id")))
     LEFT JOIN "c"."condicao_pagamento" "cp" ON (("cp"."id" = "o"."condicao_pagamento_id")))
  WHERE ("o"."deleted_at" IS NULL);


ALTER VIEW "r"."r_orcamento_lista" OWNER TO "postgres";


CREATE OR REPLACE VIEW "r"."r_pendencias_xml_entrada" AS
 SELECT "p"."tenant_id",
    "p"."empresa_id",
    "df"."competencia_date",
    "df"."emissao_date",
    "df"."id" AS "documento_fiscal_id",
    "df"."chave_acesso",
    "df"."valor_total" AS "doc_valor_total",
    "p"."tipo" AS "pendencia_tipo",
    "p"."detalhe" AS "pendencia_detalhe",
    "p"."created_at" AS "pendencia_created_at",
    "df"."source_nf_entrada_id",
    "ne"."modelo" AS "nf_modelo",
    "ne"."serie" AS "nf_serie",
    "ne"."numero" AS "nf_numero",
    "ne"."valor_total" AS "nf_valor_total",
    "ne"."emitente_nome" AS "fornecedor_nome",
    "ne"."emitente_cnpj" AS "fornecedor_cnpj",
    "ne"."fornecedor_id",
        CASE
            WHEN (("ne"."xml_raw" IS NULL) OR ("btrim"("ne"."xml_raw") = ''::"text")) THEN 'AUSENTE'::"text"
            WHEN ("length"("ne"."xml_raw") < 200) THEN 'CURTO'::"text"
            ELSE 'OK'::"text"
        END AS "xml_status",
    "length"("ne"."xml_raw") AS "xml_len"
   FROM (("f"."documento_fiscal_pendencia" "p"
     JOIN "f"."documento_fiscal" "df" ON ((("df"."id" = "p"."documento_fiscal_id") AND ("df"."tenant_id" = "p"."tenant_id"))))
     LEFT JOIN "public"."nf_entrada" "ne" ON ((("ne"."id" = "df"."source_nf_entrada_id") AND ("ne"."tenant_id" = "df"."tenant_id") AND ("ne"."empresa_id" = "df"."empresa_id"))))
  WHERE (("p"."resolved_at" IS NULL) AND ("df"."deleted_at" IS NULL) AND ("df"."operacao" = 'ENTRADA'::"text") AND ("df"."natureza" = 'PRODUTO'::"text"));


ALTER VIEW "r"."r_pendencias_xml_entrada" OWNER TO "postgres";


ALTER TABLE ONLY "f"."tmp_backfill_impostos_entrada_erros" ALTER COLUMN "id" SET DEFAULT "nextval"('"f"."tmp_backfill_impostos_entrada_erros_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."audit_log" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."audit_log_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."cliente_hh_servicos" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cliente_hh_servicos_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."clientes" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."clientes_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."colaborador_cliente_funcao" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."colaborador_cliente_funcao_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."empresa_memberships" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."empresa_memberships_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."estoque" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."estoque_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."fiscal_itens" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fiscal_itens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."fornecedores" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fornecedores_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."hh_lancamentos" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."hh_lancamentos_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."hh_tipos_mapping" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."hh_tipos_mapping_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."horas_trabalhadas" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."horas_trabalhadas_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."itens" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."itens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."itens_merge_log" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."itens_merge_log_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."movimentacoes" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."movimentacoes_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."nf_entrada" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."nf_entrada_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."nf_entrada_itens" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."nf_entrada_itens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."ordens_servico" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ordens_servico_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."os_gestao_itens" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."os_gestao_itens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."os_itens" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."os_itens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."profissionais" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."profissionais_id_seq"'::"regclass");



ALTER TABLE ONLY "a"."config_orcamento"
    ADD CONSTRAINT "pk_a_config_orcamento" PRIMARY KEY ("id");



ALTER TABLE ONLY "a"."usuario"
    ADD CONSTRAINT "pk_a_usuario" PRIMARY KEY ("id");



ALTER TABLE ONLY "a"."usuario_empresa"
    ADD CONSTRAINT "pk_a_usuario_empresa" PRIMARY KEY ("id");



ALTER TABLE ONLY "a"."usuario_tenant"
    ADD CONSTRAINT "pk_a_usuario_tenant" PRIMARY KEY ("id");



ALTER TABLE ONLY "a"."config_orcamento"
    ADD CONSTRAINT "uq_config_orcamento__tenant_empresa" UNIQUE ("tenant_id", "empresa_id");



ALTER TABLE ONLY "a"."usuario"
    ADD CONSTRAINT "uq_usuario__auth_user_id" UNIQUE ("auth_user_id");



ALTER TABLE ONLY "a"."usuario"
    ADD CONSTRAINT "uq_usuario__email" UNIQUE ("email");



ALTER TABLE ONLY "c"."i_caixa_item"
    ADD CONSTRAINT "i_caixa_item_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_caixa"
    ADD CONSTRAINT "i_caixa_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_caixa_vinculo"
    ADD CONSTRAINT "i_caixa_vinculo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_ferramenta_categoria"
    ADD CONSTRAINT "i_ferramenta_categoria_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_ferramenta"
    ADD CONSTRAINT "i_ferramenta_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_ferramenta_sugestao_xml"
    ADD CONSTRAINT "i_ferramenta_sugestao_xml_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_ferramenta_unidade"
    ADD CONSTRAINT "i_ferramenta_unidade_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_ferramenta_unidade_vinculo"
    ADD CONSTRAINT "i_ferramenta_unidade_vinculo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."condicao_pagamento"
    ADD CONSTRAINT "pk_c_condicao_pagamento" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."conjunto"
    ADD CONSTRAINT "pk_c_conjunto" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."conjunto_item"
    ADD CONSTRAINT "pk_c_conjunto_item" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."empresa"
    ADD CONSTRAINT "pk_c_empresa" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."empresa_endereco"
    ADD CONSTRAINT "pk_c_empresa_endereco" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."empresa_fiscal"
    ADD CONSTRAINT "pk_c_empresa_fiscal" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."tenant"
    ADD CONSTRAINT "pk_c_tenant" PRIMARY KEY ("id");



ALTER TABLE ONLY "c"."i_ferramenta_codigo_seq"
    ADD CONSTRAINT "pk_i_ferr_codigo_seq" PRIMARY KEY ("tenant_id", "empresa_id", "categoria_id");



ALTER TABLE ONLY "c"."condicao_pagamento"
    ADD CONSTRAINT "uq_condicao_pagamento__tenant_empresa_codigo" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "c"."condicao_pagamento"
    ADD CONSTRAINT "uq_condicao_pagamento__tenant_empresa_nome" UNIQUE ("tenant_id", "empresa_id", "nome");



ALTER TABLE ONLY "c"."conjunto"
    ADD CONSTRAINT "uq_conjunto__tenant_empresa_codigo" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "c"."conjunto_item"
    ADD CONSTRAINT "uq_conjunto_item__conjunto_item" UNIQUE ("tenant_id", "empresa_id", "conjunto_id", "item_id");



ALTER TABLE ONLY "c"."conjunto_item"
    ADD CONSTRAINT "uq_conjunto_item__conjunto_ordem" UNIQUE ("tenant_id", "empresa_id", "conjunto_id", "ordem");



ALTER TABLE ONLY "c"."i_caixa"
    ADD CONSTRAINT "uq_i_caixa__tenant_empresa_codigo" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "c"."i_caixa_item"
    ADD CONSTRAINT "uq_i_caixa_item__tenant_empresa_caixa_ferr" UNIQUE ("tenant_id", "empresa_id", "caixa_id", "ferramenta_id");



ALTER TABLE ONLY "c"."i_ferramenta_categoria"
    ADD CONSTRAINT "uq_i_ferr_cat__tenant_empresa_nome" UNIQUE ("tenant_id", "empresa_id", "nome");



ALTER TABLE ONLY "c"."i_ferramenta_categoria"
    ADD CONSTRAINT "uq_i_ferr_cat__tenant_empresa_prefixo" UNIQUE ("tenant_id", "empresa_id", "prefixo");



ALTER TABLE ONLY "c"."i_ferramenta_unidade"
    ADD CONSTRAINT "uq_i_ferr_unid__tenant_empresa_patrimonio" UNIQUE ("tenant_id", "empresa_id", "patrimonio_codigo");



ALTER TABLE ONLY "c"."i_ferramenta"
    ADD CONSTRAINT "uq_i_ferramenta__tenant_empresa_codigo" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "f"."ap_recorrencia"
    ADD CONSTRAINT "ap_recorrencia_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."arrendamento_contrato"
    ADD CONSTRAINT "arrendamento_contrato_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "f"."arrendamento_parcela"
    ADD CONSTRAINT "arrendamento_parcela_pkey" PRIMARY KEY ("id");



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



ALTER TABLE ONLY "m"."orcamento"
    ADD CONSTRAINT "pk_m_orcamento" PRIMARY KEY ("id");



ALTER TABLE ONLY "m"."orcamento_item"
    ADD CONSTRAINT "pk_m_orcamento_item" PRIMARY KEY ("id");



ALTER TABLE ONLY "m"."orcamento_seq"
    ADD CONSTRAINT "pk_m_orcamento_seq" PRIMARY KEY ("tenant_id", "empresa_id");



ALTER TABLE ONLY "m"."orcamento"
    ADD CONSTRAINT "uq_orcamento__tenant_empresa_codigo_versao" UNIQUE ("tenant_id", "empresa_id", "codigo", "versao");



ALTER TABLE ONLY "m"."orcamento"
    ADD CONSTRAINT "uq_orcamento__tenant_empresa_num_versao" UNIQUE ("tenant_id", "empresa_id", "numero", "versao");



ALTER TABLE ONLY "m"."orcamento_item"
    ADD CONSTRAINT "uq_orcamento_item__tenant_empresa_orcamento_seq" UNIQUE ("tenant_id", "empresa_id", "orcamento_id", "seq");



ALTER TABLE ONLY "public"."apontamentos_horas"
    ADD CONSTRAINT "apontamentos_horas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."centros_custo"
    ADD CONSTRAINT "centros_custo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."centros_custo"
    ADD CONSTRAINT "centros_custo_tenant_empresa_codigo_uk" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "public"."cliente_hh_servicos"
    ADD CONSTRAINT "cliente_hh_servicos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cliente_hh_tabelas"
    ADD CONSTRAINT "cliente_hh_tabelas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cliente_hh_tabelas"
    ADD CONSTRAINT "cliente_hh_tabelas_tenant_cliente_ano_uk" UNIQUE ("tenant_id", "cliente_id", "ano");



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_tenant_empresa_documento_norm_uk" UNIQUE ("tenant_id", "empresa_id", "documento_norm");



ALTER TABLE ONLY "public"."colaborador_cliente_funcao"
    ADD CONSTRAINT "colaborador_cliente_funcao_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."colaborador_funcao_hh"
    ADD CONSTRAINT "colaborador_funcao_hh_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."colaborador_funcao_hh"
    ADD CONSTRAINT "colaborador_funcao_hh_unique" UNIQUE ("tenant_id", "cliente_id", "colaborador_id", "servico_hh_id");



ALTER TABLE ONLY "public"."colaborador_taxas"
    ADD CONSTRAINT "colaborador_taxas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."colaboradores"
    ADD CONSTRAINT "colaboradores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."competencias"
    ADD CONSTRAINT "competencias_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."competencias"
    ADD CONSTRAINT "competencias_tenant_empresa_ano_mes_uk" UNIQUE ("tenant_id", "empresa_id", "ano", "mes");



ALTER TABLE ONLY "public"."empresa_memberships"
    ADD CONSTRAINT "empresa_memberships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."empresa_memberships"
    ADD CONSTRAINT "empresa_memberships_unique" UNIQUE ("tenant_id", "empresa_id", "user_id");



ALTER TABLE ONLY "public"."empresas"
    ADD CONSTRAINT "empresas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."estoque"
    ADD CONSTRAINT "estoque_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."estoque"
    ADD CONSTRAINT "estoque_tenant_empresa_item_key" UNIQUE ("tenant_id", "empresa_id", "item_id");



ALTER TABLE ONLY "public"."feriados"
    ADD CONSTRAINT "feriados_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feriados"
    ADD CONSTRAINT "feriados_uk" UNIQUE ("data", "abrangencia");



ALTER TABLE ONLY "public"."fiscal_itens"
    ADD CONSTRAINT "fiscal_itens_item_id_key" UNIQUE ("item_id");



ALTER TABLE ONLY "public"."fiscal_itens"
    ADD CONSTRAINT "fiscal_itens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fiscal_itens"
    ADD CONSTRAINT "fiscal_itens_tenant_empresa_item_uk" UNIQUE ("tenant_id", "empresa_id", "item_id");



ALTER TABLE ONLY "public"."fiscal_regras"
    ADD CONSTRAINT "fiscal_regras_pkey" PRIMARY KEY ("id");



ALTER TABLE "public"."fornecedores"
    ADD CONSTRAINT "fornecedores_cnpj_digits_len_chk" CHECK ((("cnpj_digits" = ''::"text") OR ("length"("cnpj_digits") = 14))) NOT VALID;



ALTER TABLE ONLY "public"."fornecedores"
    ADD CONSTRAINT "fornecedores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hh_especialidades"
    ADD CONSTRAINT "hh_especialidades_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hh_lancamentos"
    ADD CONSTRAINT "hh_lancamentos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hh_tipos_mapping"
    ADD CONSTRAINT "hh_tipos_mapping_hh_tipo_id_key" UNIQUE ("hh_tipo_id");



ALTER TABLE ONLY "public"."hh_tipos_mapping"
    ADD CONSTRAINT "hh_tipos_mapping_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hh_tipos_mapping"
    ADD CONSTRAINT "hh_tipos_mapping_tipo_hora_id_key" UNIQUE ("tipo_hora_id");



ALTER TABLE ONLY "public"."horas_trabalhadas"
    ADD CONSTRAINT "horas_trabalhadas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."itens_merge_log"
    ADD CONSTRAINT "itens_merge_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."itens"
    ADD CONSTRAINT "itens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."itens"
    ADD CONSTRAINT "itens_tenant_id_id_uk" UNIQUE ("tenant_id", "id");



ALTER TABLE ONLY "public"."lancamentos_contabeis_itens"
    ADD CONSTRAINT "lancamentos_contabeis_itens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lancamentos_contabeis"
    ADD CONSTRAINT "lancamentos_contabeis_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."membership_roles"
    ADD CONSTRAINT "membership_roles_pkey" PRIMARY KEY ("membership_id", "role_id");



ALTER TABLE ONLY "public"."movimentacoes"
    ADD CONSTRAINT "movimentacoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nf_entrada"
    ADD CONSTRAINT "nf_entrada_chave_key" UNIQUE ("chave");



ALTER TABLE ONLY "public"."nf_entrada_itens"
    ADD CONSTRAINT "nf_entrada_itens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nf_entrada"
    ADD CONSTRAINT "nf_entrada_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nf_entrada"
    ADD CONSTRAINT "nf_entrada_tenant_id_id_uk" UNIQUE ("tenant_id", "id");



ALTER TABLE ONLY "public"."ordens_servico"
    ADD CONSTRAINT "ordens_servico_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ordens_servico"
    ADD CONSTRAINT "ordens_servico_tenant_id_id_uk" UNIQUE ("tenant_id", "id");



ALTER TABLE ONLY "public"."ordens_servico"
    ADD CONSTRAINT "ordens_servico_tenant_numero_os_uk" UNIQUE ("tenant_id", "numero_os");



ALTER TABLE ONLY "public"."os_gestao_itens"
    ADD CONSTRAINT "os_gestao_itens_os_id_item_tipo_area_key" UNIQUE ("os_id", "item_tipo", "area");



ALTER TABLE ONLY "public"."os_gestao_itens"
    ADD CONSTRAINT "os_gestao_itens_os_key" UNIQUE ("os_id", "item_tipo", "area");



ALTER TABLE ONLY "public"."os_gestao_itens"
    ADD CONSTRAINT "os_gestao_itens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."os_itens"
    ADD CONSTRAINT "os_itens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."parametro_importacao_xml"
    ADD CONSTRAINT "parametro_importacao_xml_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."permissions"
    ADD CONSTRAINT "permissions_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."permissions"
    ADD CONSTRAINT "permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plano_contas"
    ADD CONSTRAINT "plano_contas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plano_contas"
    ADD CONSTRAINT "plano_contas_tenant_empresa_codigo_uk" UNIQUE ("tenant_id", "empresa_id", "codigo");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profissionais"
    ADD CONSTRAINT "profissionais_cpf_key" UNIQUE ("cpf");



ALTER TABLE ONLY "public"."profissionais"
    ADD CONSTRAINT "profissionais_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."role_access_rules"
    ADD CONSTRAINT "role_access_rules_pkey" PRIMARY KEY ("role_id", "resource", "action");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("role", "permission");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_tenant_id_name_key" UNIQUE ("tenant_id", "name");



ALTER TABLE ONLY "public"."tenant_memberships"
    ADD CONSTRAINT "tenant_memberships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenant_memberships"
    ADD CONSTRAINT "tenant_memberships_tenant_id_user_id_key" UNIQUE ("tenant_id", "user_id");



ALTER TABLE ONLY "public"."tenant_memberships"
    ADD CONSTRAINT "tenant_memberships_unique" UNIQUE ("tenant_id", "user_id");



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hh_tipos_mapping"
    ADD CONSTRAINT "tipos_horas_mapping_uk" UNIQUE ("tenant_id", "tipo_hora_id");



ALTER TABLE ONLY "public"."tipos_horas"
    ADD CONSTRAINT "tipos_horas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tipos_horas"
    ADD CONSTRAINT "tipos_horas_tenant_codigo_uk" UNIQUE ("tenant_id", "codigo");



ALTER TABLE ONLY "public"."cliente_hh_servicos"
    ADD CONSTRAINT "uk_cliente_hh_servicos_nome" UNIQUE ("tenant_id", "empresa_id", "cliente_id", "nome");



ALTER TABLE ONLY "public"."colaborador_cliente_funcao"
    ADD CONSTRAINT "unique_colab_cliente_funcao" UNIQUE ("tenant_id", "cliente_id", "colaborador_id", "hh_servico_id");



ALTER TABLE ONLY "public"."parametro_importacao_xml"
    ADD CONSTRAINT "uq_parametro_importacao_xml__tenant_empresa" UNIQUE ("tenant_id", "empresa_id");



ALTER TABLE ONLY "public"."user_empresa_context"
    ADD CONSTRAINT "user_empresa_context_pkey" PRIMARY KEY ("user_id", "tenant_id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_tenant_context"
    ADD CONSTRAINT "user_tenant_context_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "r"."dre_plano_excluido"
    ADD CONSTRAINT "pk_r_dre_plano_excluido" PRIMARY KEY ("tenant_id", "plano_contas_id");



CREATE INDEX "idx_usuario_empresa__empresa_id" ON "a"."usuario_empresa" USING "btree" ("empresa_id");



CREATE INDEX "idx_usuario_tenant__tenant_id" ON "a"."usuario_tenant" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "uq_usuario_empresa__usuario_id__empresa_id" ON "a"."usuario_empresa" USING "btree" ("usuario_id", "empresa_id") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_usuario_empresa__usuario_id__empresa_id__active" ON "a"."usuario_empresa" USING "btree" ("usuario_id", "empresa_id") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_usuario_tenant__usuario_id__tenant_id" ON "a"."usuario_tenant" USING "btree" ("usuario_id", "tenant_id") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_usuario_tenant__usuario_id__tenant_id__active" ON "a"."usuario_tenant" USING "btree" ("usuario_id", "tenant_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_condicao_pagamento__tenant_empresa_ativo" ON "c"."condicao_pagamento" USING "btree" ("tenant_id", "empresa_id", "ativo");



CREATE INDEX "idx_conjunto__tenant_empresa_codigo_norm" ON "c"."conjunto" USING "btree" ("tenant_id", "empresa_id", "codigo_norm");



CREATE INDEX "idx_conjunto__tenant_empresa_nome_norm" ON "c"."conjunto" USING "btree" ("tenant_id", "empresa_id", "nome_norm");



CREATE INDEX "idx_conjunto_item__conjunto" ON "c"."conjunto_item" USING "btree" ("tenant_id", "empresa_id", "conjunto_id");



CREATE INDEX "idx_empresa__tenant_id" ON "c"."empresa" USING "btree" ("tenant_id");



CREATE INDEX "idx_empresa_endereco__empresa_id" ON "c"."empresa_endereco" USING "btree" ("empresa_id");



CREATE INDEX "idx_i_caixa_vinculo__tenant_empresa_caixa_ativo" ON "c"."i_caixa_vinculo" USING "btree" ("tenant_id", "empresa_id", "caixa_id") WHERE (("data_fim" IS NULL) AND ("deleted_at" IS NULL));



CREATE INDEX "idx_i_ferr_sug_xml__tenant_empresa_status" ON "c"."i_ferramenta_sugestao_xml" USING "btree" ("tenant_id", "empresa_id", "status") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_i_ferr_unid__tenant_empresa_ferr" ON "c"."i_ferramenta_unidade" USING "btree" ("tenant_id", "empresa_id", "ferramenta_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_i_ferr_unid__tenant_empresa_status" ON "c"."i_ferramenta_unidade" USING "btree" ("tenant_id", "empresa_id", "status") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_i_ferr_unid_vinc__tenant_empresa_unidade_ativo" ON "c"."i_ferramenta_unidade_vinculo" USING "btree" ("tenant_id", "empresa_id", "ferramenta_unidade_id") WHERE (("data_fim" IS NULL) AND ("deleted_at" IS NULL));



CREATE UNIQUE INDEX "uq_empresa__tenant_id__cnpj" ON "c"."empresa" USING "btree" ("tenant_id", "cnpj") WHERE (("deleted_at" IS NULL) AND ("cnpj" IS NOT NULL));



CREATE UNIQUE INDEX "uq_empresa__tenant_id__codigo" ON "c"."empresa" USING "btree" ("tenant_id", "codigo") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_empresa_endereco__empresa_id__tipo" ON "c"."empresa_endereco" USING "btree" ("empresa_id", "tipo") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_empresa_fiscal__empresa_id" ON "c"."empresa_fiscal" USING "btree" ("empresa_id") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_tenant__codigo" ON "c"."tenant" USING "btree" ("codigo") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_tenant__nome" ON "c"."tenant" USING "btree" ("nome") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_centro_custo__tenant_empresa_parent" ON "f"."centro_custo" USING "btree" ("tenant_id", "empresa_id", "parent_id");



CREATE INDEX "idx_conciliacao__tenant_empresa_conta" ON "f"."conciliacao_bancaria" USING "btree" ("tenant_id", "empresa_id", "conta_bancaria_id");



CREATE INDEX "idx_conta_bancaria__tenant_empresa_ativo" ON "f"."conta_bancaria" USING "btree" ("tenant_id", "empresa_id", "ativo");



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



CREATE UNIQUE INDEX "uq_extrato_linha__tenant_conta_fitid" ON "f"."extrato_bancario_linha" USING "btree" ("tenant_id", "conta_bancaria_id", "fit_id") WHERE (("fit_id" IS NOT NULL) AND ("deleted_at" IS NULL));



CREATE UNIQUE INDEX "uq_irpj_csll_regra_plano__key" ON "f"."irpj_csll_regra_plano" USING "btree" ("tenant_id", "empresa_id", "plano_contas_id", "escopo", "tipo") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_titulo__apuracao_irpj_csll" ON "f"."titulo" USING "btree" ("tenant_id", "empresa_id", "competencia_date", "descricao") WHERE (("deleted_at" IS NULL) AND ("tipo" = 'AP'::"text") AND ("origem" = 'APURACAO_IRPJ_CSLL'::"text"));



CREATE UNIQUE INDEX "uq_titulo_parcela__tenant_id_titulo_id_numero__active" ON "f"."titulo_parcela" USING "btree" ("tenant_id", "titulo_id", "numero") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "uq_titulo_parcela__tenant_titulo_numero" ON "f"."titulo_parcela" USING "btree" ("tenant_id", "titulo_id", "numero") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_orcamento__tenant_empresa_emissao" ON "m"."orcamento" USING "btree" ("tenant_id", "empresa_id", "emissao_date" DESC);



CREATE INDEX "idx_orcamento__tenant_empresa_status" ON "m"."orcamento" USING "btree" ("tenant_id", "empresa_id", "status");



CREATE INDEX "idx_orcamento_item__conjunto_inst" ON "m"."orcamento_item" USING "btree" ("orcamento_id", "conjunto_instancia_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_orcamento_item__orcamento" ON "m"."orcamento_item" USING "btree" ("orcamento_id");



CREATE INDEX "apontamentos_colab_data_idx" ON "public"."apontamentos_horas" USING "btree" ("colaborador_id", "data");



CREATE INDEX "apontamentos_data_idx" ON "public"."apontamentos_horas" USING "btree" ("data");



CREATE INDEX "apontamentos_horas_hh_especialidade_id_idx" ON "public"."apontamentos_horas" USING "btree" ("hh_especialidade_id");



CREATE UNIQUE INDEX "apontamentos_horas_tenant_empresa_id_ux" ON "public"."apontamentos_horas" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "apontamentos_horas_tenant_empresa_idx" ON "public"."apontamentos_horas" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "apontamentos_horas_tenant_id_idx" ON "public"."apontamentos_horas" USING "btree" ("tenant_id");



CREATE INDEX "apontamentos_os_data_idx" ON "public"."apontamentos_horas" USING "btree" ("os_id", "data");



CREATE INDEX "audit_log_table_created_idx" ON "public"."audit_log" USING "btree" ("table_name", "created_at" DESC);



CREATE INDEX "audit_log_tenant_created_idx" ON "public"."audit_log" USING "btree" ("tenant_id", "created_at" DESC);



CREATE INDEX "cliente_hh_tabelas_cliente_id_idx" ON "public"."cliente_hh_tabelas" USING "btree" ("cliente_id");



CREATE INDEX "cliente_hh_tabelas_tenant_empresa_idx" ON "public"."cliente_hh_tabelas" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "cliente_hh_tabelas_tenant_id_idx" ON "public"."cliente_hh_tabelas" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "clientes_tenant_empresa_id_ux" ON "public"."clientes" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "clientes_tenant_empresa_idx" ON "public"."clientes" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "clientes_tenant_id_idx" ON "public"."clientes" USING "btree" ("tenant_id");



CREATE INDEX "colaborador_cliente_funcao_tenant_empresa_idx" ON "public"."colaborador_cliente_funcao" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "colaborador_funcao_hh_tenant_empresa_idx" ON "public"."colaborador_funcao_hh" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "colaborador_taxas_lookup_idx" ON "public"."colaborador_taxas" USING "btree" ("colaborador_id", "vigencia_inicio", "vigencia_fim");



CREATE INDEX "colaborador_taxas_tenant_empresa_idx" ON "public"."colaborador_taxas" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "colaborador_taxas_tenant_id_idx" ON "public"."colaborador_taxas" USING "btree" ("tenant_id");



CREATE INDEX "colaboradores_hh_especialidade_id_idx" ON "public"."colaboradores" USING "btree" ("hh_especialidade_id");



CREATE INDEX "colaboradores_nome_idx" ON "public"."colaboradores" USING "btree" ("nome");



CREATE INDEX "colaboradores_tenant_empresa_idx" ON "public"."colaboradores" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "colaboradores_tenant_id_idx" ON "public"."colaboradores" USING "btree" ("tenant_id");



CREATE INDEX "empresas_tenant_ativo_idx" ON "public"."empresas" USING "btree" ("tenant_id", "ativo");



CREATE UNIQUE INDEX "empresas_tenant_cnpj_uk" ON "public"."empresas" USING "btree" ("tenant_id", "cnpj");



CREATE INDEX "feriados_data_idx" ON "public"."feriados" USING "btree" ("data");



CREATE INDEX "fiscal_itens_tenant_id_idx" ON "public"."fiscal_itens" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "fornecedores_documento_norm_uniq" ON "public"."fornecedores" USING "btree" ("documento_norm") WHERE ("documento_norm" <> ''::"text");



CREATE UNIQUE INDEX "fornecedores_tenant_documento_key_uidx" ON "public"."fornecedores" USING "btree" ("tenant_id", "documento_key") WHERE ("documento_key" <> ''::"text");



CREATE UNIQUE INDEX "fornecedores_tenant_documento_norm_uidx" ON "public"."fornecedores" USING "btree" ("tenant_id", "documento_norm") WHERE ("documento_norm" <> ''::"text");



CREATE UNIQUE INDEX "fornecedores_tenant_documento_norm_uk" ON "public"."fornecedores" USING "btree" ("tenant_id", "documento_norm") WHERE (("documento_norm" IS NOT NULL) AND ("length"(TRIM(BOTH FROM "documento_norm")) > 0));



CREATE UNIQUE INDEX "fornecedores_tenant_empresa_cnpj_uq" ON "public"."fornecedores" USING "btree" ("tenant_id", "empresa_id", "cnpj_digits") WHERE ("cnpj_digits" <> ''::"text");



CREATE UNIQUE INDEX "fornecedores_tenant_empresa_id_ux" ON "public"."fornecedores" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "fornecedores_tenant_empresa_idx" ON "public"."fornecedores" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "fornecedores_tenant_finalidade_padrao_idx" ON "public"."fornecedores" USING "btree" ("tenant_id", "finalidade_padrao");



CREATE INDEX "fornecedores_tenant_id_idx" ON "public"."fornecedores" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "fornecedores_unique_cnpj" ON "public"."fornecedores" USING "btree" ("tenant_id", "empresa_id", "cnpj_norm") WHERE ("cnpj_norm" IS NOT NULL);



CREATE UNIQUE INDEX "fornecedores_unique_docnorm" ON "public"."fornecedores" USING "btree" ("tenant_id", "empresa_id", "documento_norm") WHERE (("documento_norm" IS NOT NULL) AND ("documento_norm" <> ''::"text"));



CREATE INDEX "hh_especialidades_tenant_id_idx" ON "public"."hh_especialidades" USING "btree" ("tenant_id");



CREATE INDEX "hh_lancamentos_hh_especialidade_id_idx" ON "public"."hh_lancamentos" USING "btree" ("hh_especialidade_id");



CREATE UNIQUE INDEX "hh_tipos_mapping_tenant_tipo_hora_uidx" ON "public"."hh_tipos_mapping" USING "btree" ("tenant_id", "tipo_hora_id");



CREATE UNIQUE INDEX "hh_tipos_mapping_tenant_tipo_hora_uq" ON "public"."hh_tipos_mapping" USING "btree" ("tenant_id", "tipo_hora_id");



CREATE INDEX "idx_apontamentos_horas_hh_lancamento" ON "public"."apontamentos_horas" USING "btree" ("hh_lancamento_id") WHERE ("hh_lancamento_id" IS NOT NULL);



CREATE INDEX "idx_centros_custo_tenant_empresa" ON "public"."centros_custo" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "idx_cliente_hh_servicos_ativo" ON "public"."cliente_hh_servicos" USING "btree" ("ativo") WHERE ("ativo" = true);



CREATE INDEX "idx_cliente_hh_servicos_cliente" ON "public"."cliente_hh_servicos" USING "btree" ("cliente_id");



CREATE INDEX "idx_cliente_hh_servicos_tenant_empresa" ON "public"."cliente_hh_servicos" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "idx_clientes_ativo" ON "public"."clientes" USING "btree" ("ativo");



CREATE INDEX "idx_clientes_documento_norm" ON "public"."clientes" USING "btree" ("tenant_id", "empresa_id", "documento_norm") WHERE ("documento_norm" IS NOT NULL);



CREATE INDEX "idx_clientes_habilita_hh" ON "public"."clientes" USING "btree" ("habilita_hh");



CREATE INDEX "idx_clientes_nome" ON "public"."clientes" USING "btree" ("nome");



CREATE INDEX "idx_colaborador_cliente_funcao_ativo" ON "public"."colaborador_cliente_funcao" USING "btree" ("ativo") WHERE ("ativo" = true);



CREATE INDEX "idx_colaborador_cliente_funcao_cliente" ON "public"."colaborador_cliente_funcao" USING "btree" ("tenant_id", "cliente_id");



CREATE INDEX "idx_colaborador_cliente_funcao_colab" ON "public"."colaborador_cliente_funcao" USING "btree" ("tenant_id", "colaborador_id");



CREATE INDEX "idx_colaborador_cliente_funcao_colaborador" ON "public"."colaborador_cliente_funcao" USING "btree" ("tenant_id", "colaborador_id");



CREATE INDEX "idx_colaborador_cliente_funcao_servico" ON "public"."colaborador_cliente_funcao" USING "btree" ("tenant_id", "hh_servico_id");



CREATE INDEX "idx_colaborador_cliente_funcao_tenant" ON "public"."colaborador_cliente_funcao" USING "btree" ("tenant_id");



CREATE INDEX "idx_colaborador_funcao_hh_cliente_id" ON "public"."colaborador_funcao_hh" USING "btree" ("cliente_id");



CREATE INDEX "idx_colaborador_funcao_hh_colaborador_id" ON "public"."colaborador_funcao_hh" USING "btree" ("colaborador_id");



CREATE INDEX "idx_colaborador_funcao_hh_servico_hh_id" ON "public"."colaborador_funcao_hh" USING "btree" ("servico_hh_id");



CREATE INDEX "idx_colaborador_funcao_hh_tenant_id" ON "public"."colaborador_funcao_hh" USING "btree" ("tenant_id");



CREATE INDEX "idx_competencias_tenant_empresa" ON "public"."competencias" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "idx_empresa_memberships_empresa_user" ON "public"."empresa_memberships" USING "btree" ("empresa_id", "user_id");



CREATE INDEX "idx_empresa_memberships_tenant_user" ON "public"."empresa_memberships" USING "btree" ("tenant_id", "user_id");



CREATE INDEX "idx_estoque_item" ON "public"."estoque" USING "btree" ("item_id");



CREATE INDEX "idx_fiscal_itens_item" ON "public"."fiscal_itens" USING "btree" ("item_id");



CREATE INDEX "idx_fiscal_itens_tenant_empresa_item" ON "public"."fiscal_itens" USING "btree" ("tenant_id", "empresa_id", "item_id");



CREATE INDEX "idx_fiscal_regras_lookup" ON "public"."fiscal_regras" USING "btree" ("tenant_id", "empresa_id", "ativo", "prioridade");



CREATE INDEX "idx_fiscal_regras_tenant_empresa" ON "public"."fiscal_regras" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "idx_fornecedores__tenant_motivo_compra_padrao" ON "public"."fornecedores" USING "btree" ("tenant_id", "motivo_compra_padrao_id");



CREATE INDEX "idx_fornecedores_ativo" ON "public"."fornecedores" USING "btree" ("ativo");



CREATE INDEX "idx_fornecedores_nome" ON "public"."fornecedores" USING "btree" ("nome");



CREATE INDEX "idx_hh_lancamentos_colaborador" ON "public"."hh_lancamentos" USING "btree" ("colaborador_id");



CREATE INDEX "idx_hh_lancamentos_data" ON "public"."hh_lancamentos" USING "btree" ("data");



CREATE INDEX "idx_hh_lancamentos_empresa" ON "public"."hh_lancamentos" USING "btree" ("empresa_id");



CREATE INDEX "idx_hh_lancamentos_hh_servico_id" ON "public"."hh_lancamentos" USING "btree" ("hh_servico_id");



CREATE INDEX "idx_hh_lancamentos_os" ON "public"."hh_lancamentos" USING "btree" ("os_id");



CREATE INDEX "idx_hh_lancamentos_tenant" ON "public"."hh_lancamentos" USING "btree" ("tenant_id");



CREATE INDEX "idx_hh_tipos_mapping_tenant" ON "public"."hh_tipos_mapping" USING "btree" ("tenant_id");



CREATE INDEX "idx_hh_tipos_mapping_tipo_hora" ON "public"."hh_tipos_mapping" USING "btree" ("tipo_hora_id");



CREATE INDEX "idx_horas_os" ON "public"."horas_trabalhadas" USING "btree" ("os_id");



CREATE INDEX "idx_horas_profissional" ON "public"."horas_trabalhadas" USING "btree" ("profissional_id");



CREATE INDEX "idx_itens__tenant_empresa_codigo_fornecedor_sem_zeros" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id", "codigo_fornecedor_sem_zeros");



CREATE INDEX "idx_itens__tenant_empresa_codigo_interno_sem_zeros" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id", "codigo_interno_sem_zeros");



CREATE INDEX "idx_itens__tenant_empresa_mesclado_em_item_id" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id", "mesclado_em_item_id");



CREATE INDEX "idx_itens_ativo" ON "public"."itens" USING "btree" ("ativo");



CREATE INDEX "idx_itens_categoria" ON "public"."itens" USING "btree" ("categoria");



CREATE INDEX "idx_itens_codigo_barras" ON "public"."itens" USING "btree" ("codigo_barras");



CREATE INDEX "idx_itens_fabricante" ON "public"."itens" USING "btree" ("fabricante");



CREATE INDEX "idx_itens_fornecedor_id" ON "public"."itens" USING "btree" ("fornecedor_id");



CREATE INDEX "idx_itens_tipo" ON "public"."itens" USING "btree" ("tipo");



CREATE INDEX "idx_lanc_cont_itens_conta" ON "public"."lancamentos_contabeis_itens" USING "btree" ("conta_id");



CREATE INDEX "idx_lanc_cont_itens_lanc" ON "public"."lancamentos_contabeis_itens" USING "btree" ("lancamento_id");



CREATE INDEX "idx_lanc_cont_tenant_empresa_data" ON "public"."lancamentos_contabeis" USING "btree" ("tenant_id", "empresa_id", "data_lancamento");



CREATE INDEX "idx_memberships_tenant" ON "public"."tenant_memberships" USING "btree" ("tenant_id");



CREATE INDEX "idx_memberships_user" ON "public"."tenant_memberships" USING "btree" ("user_id");



CREATE INDEX "idx_mov_created_at" ON "public"."movimentacoes" USING "btree" ("created_at");



CREATE INDEX "idx_mov_data" ON "public"."movimentacoes" USING "btree" ("data_movimentacao");



CREATE INDEX "idx_mov_nf_data" ON "public"."movimentacoes" USING "btree" ("origem_nf_entrada_id", "data_movimentacao");



CREATE INDEX "idx_mov_origem_nf" ON "public"."movimentacoes" USING "btree" ("origem_nf_entrada_id");



CREATE INDEX "idx_mov_origem_os" ON "public"."movimentacoes" USING "btree" ("origem_os_id");



CREATE INDEX "idx_movimentacoes_item" ON "public"."movimentacoes" USING "btree" ("item_id");



CREATE INDEX "idx_movimentacoes_tipo" ON "public"."movimentacoes" USING "btree" ("tipo");



CREATE INDEX "idx_nf_entrada__tenant_empresa_motivo" ON "public"."nf_entrada" USING "btree" ("tenant_id", "empresa_id", "motivo_compra_id");



CREATE INDEX "idx_nf_entrada__tenant_empresa_solicitante_usuario" ON "public"."nf_entrada" USING "btree" ("tenant_id", "empresa_id", "solicitante_usuario_id");



CREATE INDEX "idx_nf_entrada__tenant_id__deleted_at" ON "public"."nf_entrada" USING "btree" ("tenant_id", "deleted_at");



CREATE INDEX "idx_nf_entrada_data_emissao" ON "public"."nf_entrada" USING "btree" ("data_emissao");



CREATE INDEX "idx_nf_entrada_fornecedor" ON "public"."nf_entrada" USING "btree" ("fornecedor_id");



CREATE INDEX "idx_nf_entrada_itens_item" ON "public"."nf_entrada_itens" USING "btree" ("item_id");



CREATE INDEX "idx_nf_itens_item" ON "public"."nf_entrada_itens" USING "btree" ("item_id");



CREATE INDEX "idx_nf_itens_nf" ON "public"."nf_entrada_itens" USING "btree" ("nf_entrada_id");



CREATE INDEX "idx_os_cliente" ON "public"."ordens_servico" USING "btree" ("cliente_id");



CREATE INDEX "idx_os_cliente_id" ON "public"."ordens_servico" USING "btree" ("cliente_id");



CREATE INDEX "idx_os_gestao_itens_osid" ON "public"."os_gestao_itens" USING "btree" ("os_id");



CREATE INDEX "idx_os_itens_item" ON "public"."os_itens" USING "btree" ("item_id");



CREATE INDEX "idx_os_itens_os" ON "public"."os_itens" USING "btree" ("os_id");



CREATE INDEX "idx_os_numero" ON "public"."ordens_servico" USING "btree" ("numero_os");



CREATE INDEX "idx_os_status" ON "public"."ordens_servico" USING "btree" ("status");



CREATE INDEX "idx_plano_contas_parent" ON "public"."plano_contas" USING "btree" ("parent_id");



CREATE INDEX "idx_plano_contas_tenant_empresa" ON "public"."plano_contas" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "idx_profissionais_ativo" ON "public"."profissionais" USING "btree" ("ativo");



CREATE INDEX "idx_roles_tenant" ON "public"."roles" USING "btree" ("tenant_id");



CREATE INDEX "idx_user_empresa_context_tenant" ON "public"."user_empresa_context" USING "btree" ("tenant_id");



CREATE INDEX "idx_user_empresa_context_user" ON "public"."user_empresa_context" USING "btree" ("user_id");



CREATE UNIQUE INDEX "itens_tenant_codigo_barras_uk" ON "public"."itens" USING "btree" ("tenant_id", "codigo_barras") WHERE (("codigo_barras" IS NOT NULL) AND ("length"(TRIM(BOTH FROM "codigo_barras")) > 0));



CREATE UNIQUE INDEX "itens_tenant_empresa_id_ux" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "itens_tenant_empresa_idx" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "itens_tenant_empresa_motivo_compra_idx" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id", "motivo_compra_id");



CREATE INDEX "itens_tenant_finalidade_idx" ON "public"."itens" USING "btree" ("tenant_id", "finalidade");



CREATE INDEX "movimentacoes_origem_os_id_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "empresa_id", "origem_os_id") WHERE ("origem_os_id" IS NOT NULL);



CREATE INDEX "movimentacoes_tenant_data_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "data_movimentacao");



CREATE INDEX "movimentacoes_tenant_data_movimentacao_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "data_movimentacao");



CREATE INDEX "movimentacoes_tenant_empresa_data_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "empresa_id", "data_movimentacao");



CREATE INDEX "movimentacoes_tenant_empresa_nf_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "empresa_id", "origem_nf_entrada_id");



CREATE INDEX "movimentacoes_tenant_item_data_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "item_id", "data_movimentacao");



CREATE INDEX "movimentacoes_tenant_item_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "item_id");



CREATE INDEX "movimentacoes_tenant_nf_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "origem_nf_entrada_id");



CREATE INDEX "movimentacoes_tenant_tipo_idx" ON "public"."movimentacoes" USING "btree" ("tenant_id", "tipo");



CREATE UNIQUE INDEX "nf_entrada_itens_tenant_empresa_id_ux" ON "public"."nf_entrada_itens" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "nf_entrada_itens_tenant_empresa_idx" ON "public"."nf_entrada_itens" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "nf_entrada_itens_tenant_id_idx" ON "public"."nf_entrada_itens" USING "btree" ("tenant_id");



CREATE INDEX "nf_entrada_os_id_idx" ON "public"."nf_entrada" USING "btree" ("tenant_id", "os_id") WHERE ("os_id" IS NOT NULL);



CREATE UNIQUE INDEX "nf_entrada_tenant_empresa_id_ux" ON "public"."nf_entrada" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "nf_entrada_tenant_empresa_idx" ON "public"."nf_entrada" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "nf_entrada_tenant_finalidade_contexto_idx" ON "public"."nf_entrada" USING "btree" ("tenant_id", "finalidade_contexto");



CREATE INDEX "nf_entrada_tenant_id_idx" ON "public"."nf_entrada" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "ordens_servico_numero_os_uniq" ON "public"."ordens_servico" USING "btree" ("numero_os");



CREATE UNIQUE INDEX "ordens_servico_os_num_uniq" ON "public"."ordens_servico" USING "btree" ("os_num");



CREATE INDEX "ordens_servico_status_idx" ON "public"."ordens_servico" USING "btree" ("status");



CREATE UNIQUE INDEX "ordens_servico_tenant_empresa_id_ux" ON "public"."ordens_servico" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "ordens_servico_tenant_empresa_idx" ON "public"."ordens_servico" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "ordens_servico_usa_relatorio_hh_idx" ON "public"."ordens_servico" USING "btree" ("usa_relatorio_hh");



CREATE INDEX "os_gestao_itens_tenant_empresa_idx" ON "public"."os_gestao_itens" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "os_gestao_itens_tenant_id_idx" ON "public"."os_gestao_itens" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "os_itens_tenant_empresa_id_ux" ON "public"."os_itens" USING "btree" ("tenant_id", "empresa_id", "id");



CREATE INDEX "os_itens_tenant_empresa_idx" ON "public"."os_itens" USING "btree" ("tenant_id", "empresa_id");



CREATE INDEX "os_itens_tenant_id_idx" ON "public"."os_itens" USING "btree" ("tenant_id");



CREATE INDEX "tipos_horas_tenant_id_idx" ON "public"."tipos_horas" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "uq_apont_horas__hh__tenant_empresa_os_colab_data" ON "public"."apontamentos_horas" USING "btree" ("tenant_id", "empresa_id", "os_id", "colaborador_id", "data") WHERE ("gerado_por_hh" = true);



CREATE UNIQUE INDEX "uq_itens__tenant_empresa_codigo_interno" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id", "codigo_interno");



CREATE UNIQUE INDEX "uq_itens__tenant_empresa_codigo_interno_sem_zeros__ativos" ON "public"."itens" USING "btree" ("tenant_id", "empresa_id", "codigo_interno_sem_zeros") WHERE (("ativo" = true) AND ("mesclado_em_item_id" IS NULL));



CREATE UNIQUE INDEX "ux_fornecedores_doc_digits" ON "public"."fornecedores" USING "btree" ("tenant_id", "empresa_id", "doc_digits") WHERE ("doc_digits" IS NOT NULL);



CREATE UNIQUE INDEX "ux_fornecedores_tenant_documento_norm" ON "public"."fornecedores" USING "btree" ("tenant_id", "documento_norm") WHERE (("documento_norm" IS NOT NULL) AND ("documento_norm" <> ''::"text"));



CREATE OR REPLACE VIEW "r"."r_orcamento_catalogo_busca" AS
 SELECT 'ITEM'::"text" AS "origem",
    "i"."tenant_id",
    "i"."empresa_id",
    ("i"."id")::"text" AS "ref_id",
    "i"."id" AS "item_id",
    NULL::"uuid" AS "conjunto_id",
    "upper"(TRIM(BOTH FROM "i"."codigo_interno")) AS "codigo",
    "upper"(TRIM(BOTH FROM "i"."nome")) AS "nome",
    "upper"(TRIM(BOTH FROM COALESCE("i"."unidade_medida", 'UN'::character varying))) AS "unidade",
        CASE
            WHEN ("lower"(("i"."tipo")::"text") = 'produto'::"text") THEN 'PRODUTO'::"text"
            WHEN ("lower"(("i"."tipo")::"text") = 'servico'::"text") THEN 'SERVICO'::"text"
            ELSE "upper"(("i"."tipo")::"text")
        END AS "tipo",
    ("i"."preco_unitario")::numeric(15,2) AS "preco_sugerido"
   FROM "public"."itens" "i"
  WHERE (("i"."ativo" = true) AND (("i"."tipo")::"text" = ANY ((ARRAY['produto'::character varying, 'servico'::character varying])::"text"[])))
UNION ALL
 SELECT 'CONJUNTO'::"text" AS "origem",
    "c"."tenant_id",
    "c"."empresa_id",
    ("c"."id")::"text" AS "ref_id",
    NULL::integer AS "item_id",
    "c"."id" AS "conjunto_id",
    "c"."codigo",
    "c"."nome",
    'CJ'::"text" AS "unidade",
    'CONJUNTO'::"text" AS "tipo",
        CASE
            WHEN ("c"."precificacao" = 'PRECO_FIXO'::"text") THEN "c"."preco_fixo"
            ELSE (COALESCE("sum"(("ci"."quantidade" * "i"."preco_unitario")), (0)::numeric))::numeric(15,2)
        END AS "preco_sugerido"
   FROM (("c"."conjunto" "c"
     LEFT JOIN "c"."conjunto_item" "ci" ON ((("ci"."conjunto_id" = "c"."id") AND ("ci"."deleted_at" IS NULL))))
     LEFT JOIN "public"."itens" "i" ON ((("i"."id" = "ci"."item_id") AND ("i"."tenant_id" = "c"."tenant_id") AND ("i"."empresa_id" = "c"."empresa_id") AND ("i"."ativo" = true))))
  WHERE (("c"."deleted_at" IS NULL) AND ("c"."ativo" = true))
  GROUP BY "c"."id";



CREATE OR REPLACE TRIGGER "trg_config_orcamento_audit" AFTER INSERT OR DELETE OR UPDATE ON "a"."config_orcamento" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_config_orcamento_set_updated_at" BEFORE UPDATE ON "a"."config_orcamento" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_usuario_empresa_set_updated_at" BEFORE UPDATE ON "a"."usuario_empresa" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_usuario_set_updated_at" BEFORE UPDATE ON "a"."usuario" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_usuario_tenant_set_updated_at" BEFORE UPDATE ON "a"."usuario_tenant" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_condicao_pagamento_audit" AFTER INSERT OR DELETE OR UPDATE ON "c"."condicao_pagamento" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_condicao_pagamento_biu" BEFORE INSERT OR UPDATE ON "c"."condicao_pagamento" FOR EACH ROW EXECUTE FUNCTION "c"."trg_condicao_pagamento_biu"();



CREATE OR REPLACE TRIGGER "trg_condicao_pagamento_set_updated_at" BEFORE UPDATE ON "c"."condicao_pagamento" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_conjunto_audit" AFTER INSERT OR DELETE OR UPDATE ON "c"."conjunto" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_conjunto_biu" BEFORE INSERT OR UPDATE ON "c"."conjunto" FOR EACH ROW EXECUTE FUNCTION "c"."trg_conjunto_biu"();



CREATE OR REPLACE TRIGGER "trg_conjunto_item_audit" AFTER INSERT OR DELETE OR UPDATE ON "c"."conjunto_item" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_conjunto_item_biu" BEFORE INSERT OR UPDATE ON "c"."conjunto_item" FOR EACH ROW EXECUTE FUNCTION "c"."trg_conjunto_item_biu"();



CREATE OR REPLACE TRIGGER "trg_conjunto_item_set_updated_at" BEFORE UPDATE ON "c"."conjunto_item" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_conjunto_set_updated_at" BEFORE UPDATE ON "c"."conjunto" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_empresa_endereco_set_updated_at" BEFORE UPDATE ON "c"."empresa_endereco" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_empresa_fiscal_set_updated_at" BEFORE UPDATE ON "c"."empresa_fiscal" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_empresa_set_updated_at" BEFORE UPDATE ON "c"."empresa" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_i_caixa_item_set_updated_at" BEFORE UPDATE ON "c"."i_caixa_item" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_i_caixa_set_updated_at" BEFORE UPDATE ON "c"."i_caixa" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_i_caixa_vinculo_set_updated_at" BEFORE UPDATE ON "c"."i_caixa_vinculo" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_i_ferr_sug_xml_set_updated_at" BEFORE UPDATE ON "c"."i_ferramenta_sugestao_xml" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_i_ferr_unid_set_updated_at" BEFORE UPDATE ON "c"."i_ferramenta_unidade" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_i_ferr_unid_vinc_set_updated_at" BEFORE UPDATE ON "c"."i_ferramenta_unidade_vinculo" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_i_ferramenta_set_codigo" BEFORE INSERT ON "c"."i_ferramenta" FOR EACH ROW EXECUTE FUNCTION "c"."trg_i_ferramenta_set_codigo"();



CREATE OR REPLACE TRIGGER "trg_i_ferramenta_set_updated_at" BEFORE UPDATE ON "c"."i_ferramenta" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_tenant_set_updated_at" BEFORE UPDATE ON "c"."tenant" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



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



CREATE OR REPLACE TRIGGER "trg_imposto_retencao_set_updated_at" BEFORE UPDATE ON "f"."imposto_retencao" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_imposto_retencao_set_updated_by" BEFORE UPDATE ON "f"."imposto_retencao" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_motivo_compra_set_updated_at" BEFORE UPDATE ON "f"."motivo_compra" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_motivo_compra_set_updated_by" BEFORE UPDATE ON "f"."motivo_compra" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_pagamento_set_updated_at" BEFORE UPDATE ON "f"."pagamento" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_pagamento_set_updated_by" BEFORE UPDATE ON "f"."pagamento" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



CREATE OR REPLACE TRIGGER "trg_plano_contas_set_updated_at" BEFORE UPDATE ON "f"."plano_contas" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_plano_contas_set_updated_by" BEFORE UPDATE ON "f"."plano_contas" FOR EACH ROW EXECUTE FUNCTION "f"."fn_set_updated_by"();



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



CREATE OR REPLACE TRIGGER "trg_orcamento_au" AFTER UPDATE ON "m"."orcamento" FOR EACH ROW EXECUTE FUNCTION "m"."trg_orcamento_au"();



CREATE OR REPLACE TRIGGER "trg_orcamento_audit" AFTER INSERT OR DELETE OR UPDATE ON "m"."orcamento" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_orcamento_biu" BEFORE INSERT OR UPDATE ON "m"."orcamento" FOR EACH ROW EXECUTE FUNCTION "m"."trg_orcamento_biu"();



CREATE OR REPLACE TRIGGER "trg_orcamento_item_aiud" AFTER INSERT OR DELETE OR UPDATE ON "m"."orcamento_item" FOR EACH ROW EXECUTE FUNCTION "m"."trg_orcamento_item_aiud"();



CREATE OR REPLACE TRIGGER "trg_orcamento_item_audit" AFTER INSERT OR DELETE OR UPDATE ON "m"."orcamento_item" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_orcamento_item_biu" BEFORE INSERT OR UPDATE ON "m"."orcamento_item" FOR EACH ROW EXECUTE FUNCTION "m"."trg_orcamento_item_biu"();



CREATE OR REPLACE TRIGGER "trg_orcamento_item_set_updated_at" BEFORE UPDATE ON "m"."orcamento_item" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_orcamento_set_updated_at" BEFORE UPDATE ON "m"."orcamento" FOR EACH ROW EXECUTE FUNCTION "a"."fn_set_updated_at"();



CREATE OR REPLACE TRIGGER "colaborador_funcao_hh_update_timestamp" BEFORE UPDATE ON "public"."colaborador_funcao_hh" FOR EACH ROW EXECUTE FUNCTION "public"."update_timestamp"();



CREATE OR REPLACE TRIGGER "hh_lancamentos_calculate" BEFORE INSERT OR UPDATE ON "public"."hh_lancamentos" FOR EACH ROW EXECUTE FUNCTION "public"."calculate_hh_lancamento"();



CREATE OR REPLACE TRIGGER "trg_audit_fiscal_itens" AFTER INSERT OR DELETE OR UPDATE ON "public"."fiscal_itens" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_movimentacoes" AFTER INSERT OR DELETE OR UPDATE ON "public"."movimentacoes" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_nf_entrada" AFTER INSERT OR DELETE OR UPDATE ON "public"."nf_entrada" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_nf_entrada_itens" AFTER INSERT OR DELETE OR UPDATE ON "public"."nf_entrada_itens" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_ordens_servico" AFTER INSERT OR DELETE OR UPDATE ON "public"."ordens_servico" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_audit_parametro_importacao_xml" AFTER INSERT OR DELETE OR UPDATE ON "public"."parametro_importacao_xml" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger"();



CREATE OR REPLACE TRIGGER "trg_block_mov_delete" BEFORE DELETE ON "public"."movimentacoes" FOR EACH ROW EXECUTE FUNCTION "public"."block_movimentacoes_mutation"();



CREATE OR REPLACE TRIGGER "trg_block_mov_update" BEFORE UPDATE ON "public"."movimentacoes" FOR EACH ROW EXECUTE FUNCTION "public"."block_movimentacoes_mutation"();



CREATE OR REPLACE TRIGGER "trg_block_nf_mov_delete" BEFORE DELETE ON "public"."movimentacoes" FOR EACH ROW WHEN (("old"."origem_nf_entrada_id" IS NOT NULL)) EXECUTE FUNCTION "public"."trg_block_nf_movimentacoes"();



CREATE OR REPLACE TRIGGER "trg_block_nf_mov_update" BEFORE UPDATE ON "public"."movimentacoes" FOR EACH ROW WHEN ((("old"."origem_nf_entrada_id" IS NOT NULL) OR ("new"."origem_nf_entrada_id" IS NOT NULL))) EXECUTE FUNCTION "public"."trg_block_nf_movimentacoes"();



CREATE OR REPLACE TRIGGER "trg_cliente_hh_servicos_updated_at" BEFORE UPDATE ON "public"."cliente_hh_servicos" FOR EACH ROW EXECUTE FUNCTION "public"."update_cliente_hh_servicos_updated_at"();



CREATE OR REPLACE TRIGGER "trg_criar_gestao_padrao_os" AFTER INSERT ON "public"."ordens_servico" FOR EACH ROW EXECUTE FUNCTION "public"."criar_gestao_padrao_os"();



CREATE OR REPLACE TRIGGER "trg_fiscal_itens_updated_at" BEFORE UPDATE ON "public"."fiscal_itens" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_fornecedores_force_gerar_cp" BEFORE INSERT OR UPDATE OF "gerar_contas_pagar_auto" ON "public"."fornecedores" FOR EACH ROW EXECUTE FUNCTION "public"."trg_fornecedores_force_gerar_cp"();



CREATE OR REPLACE TRIGGER "trg_hh_criar_apontamento" AFTER INSERT OR UPDATE ON "public"."hh_lancamentos" FOR EACH ROW EXECUTE FUNCTION "public"."fn_hh_criar_apontamento"();



CREATE OR REPLACE TRIGGER "trg_hh_delete_apontamento" BEFORE DELETE ON "public"."hh_lancamentos" FOR EACH ROW EXECUTE FUNCTION "public"."fn_hh_delete_apontamento"();



CREATE OR REPLACE TRIGGER "trg_hh_sync_apontamento" AFTER INSERT OR UPDATE ON "public"."hh_lancamentos" FOR EACH ROW EXECUTE FUNCTION "public"."fn_hh_sync_apontamento"();



CREATE OR REPLACE TRIGGER "trg_itens_normalizar_codigos" BEFORE INSERT OR UPDATE OF "codigo_interno", "codigo_fornecedor" ON "public"."itens" FOR EACH ROW EXECUTE FUNCTION "public"."trg_itens_normalizar_codigos"();



CREATE OR REPLACE TRIGGER "trg_itens_sync_timestamps" BEFORE INSERT OR UPDATE ON "public"."itens" FOR EACH ROW EXECUTE FUNCTION "public"."trg_itens_sync_timestamps"();



CREATE OR REPLACE TRIGGER "trg_movimentacoes_apply_estoque" AFTER INSERT ON "public"."movimentacoes" FOR EACH ROW EXECUTE FUNCTION "public"."apply_movimentacao_estoque"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada__auto_fix_ap_from_xml" AFTER INSERT OR UPDATE OF "xml_raw" ON "public"."nf_entrada" FOR EACH ROW EXECUTE FUNCTION "f"."fn_nf_entrada__auto_fix_ap_from_xml"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada__resolve_xml_pendencia" AFTER INSERT OR UPDATE OF "xml_raw" ON "public"."nf_entrada" FOR EACH ROW EXECUTE FUNCTION "f"."fn_nf_entrada__resolve_xml_pendencia"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada_itens__enforce_item_finalidade_import" BEFORE INSERT OR UPDATE OF "item_id" ON "public"."nf_entrada_itens" FOR EACH ROW EXECUTE FUNCTION "public"."tg_nf_entrada_itens__enforce_item_finalidade_import"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada_itens__fill_descricao" BEFORE INSERT OR UPDATE OF "descricao", "codigo_fornecedor", "item_id" ON "public"."nf_entrada_itens" FOR EACH ROW EXECUTE FUNCTION "public"."tg_nf_entrada_itens__fill_descricao"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada_itens_sync_os_stmt" AFTER INSERT ON "public"."nf_entrada_itens" REFERENCING NEW TABLE AS "new_rows" FOR EACH STATEMENT EXECUTE FUNCTION "public"."trg_nf_entrada_itens_sync_os_stmt"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada_itens_updated_at" BEFORE UPDATE ON "public"."nf_entrada_itens" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada_sync_os_itens" AFTER UPDATE OF "os_id" ON "public"."nf_entrada" FOR EACH ROW EXECUTE FUNCTION "public"."trg_nf_entrada_sync_os_itens"();



CREATE OR REPLACE TRIGGER "trg_nf_entrada_updated_at" BEFORE UPDATE ON "public"."nf_entrada" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_ordens_servico_validate_hh" BEFORE INSERT OR UPDATE OF "cliente_id", "usa_relatorio_hh" ON "public"."ordens_servico" FOR EACH ROW EXECUTE FUNCTION "public"."fn_ordens_servico_validate_hh"();



CREATE OR REPLACE TRIGGER "trg_os_gestao_itens_updated_at" BEFORE UPDATE ON "public"."os_gestao_itens" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_parametro_importacao_xml_updated_at" BEFORE UPDATE ON "public"."parametro_importacao_xml" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_set_fator_aplicado" BEFORE INSERT OR UPDATE OF "tipo_hora_id", "fator_aplicado" ON "public"."apontamentos_horas" FOR EACH ROW EXECUTE FUNCTION "public"."fn_set_fator_aplicado"();



CREATE OR REPLACE TRIGGER "trg_set_horas_from_periodos" BEFORE INSERT OR UPDATE OF "hora_entrada_1", "hora_saida_1", "hora_entrada_2", "hora_saida_2" ON "public"."apontamentos_horas" FOR EACH ROW EXECUTE FUNCTION "public"."fn_set_horas_from_periodos"();



CREATE OR REPLACE TRIGGER "trg_set_tenant_id_colaborador_cliente_funcao" BEFORE INSERT ON "public"."colaborador_cliente_funcao" FOR EACH ROW EXECUTE FUNCTION "public"."set_tenant_id_colaborador_cliente_funcao"();



CREATE OR REPLACE TRIGGER "trg_validar_apontamento_horas" BEFORE INSERT OR UPDATE OF "os_id", "colaborador_id", "data" ON "public"."apontamentos_horas" FOR EACH ROW EXECUTE FUNCTION "public"."fn_validar_apontamento_horas"();



CREATE OR REPLACE TRIGGER "trigger_update_colaborador_cliente_funcao_updated_at" BEFORE UPDATE ON "public"."colaborador_cliente_funcao" FOR EACH ROW EXECUTE FUNCTION "public"."update_colaborador_cliente_funcao_updated_at"();



CREATE OR REPLACE TRIGGER "trigger_validate_apontamento_colaborador" BEFORE INSERT OR UPDATE OF "colaborador_id", "os_id" ON "public"."apontamentos_horas" FOR EACH ROW EXECUTE FUNCTION "public"."validate_apontamento_colaborador_contrato"();



CREATE OR REPLACE TRIGGER "trigger_validate_hh_lancamento" BEFORE INSERT OR UPDATE OF "colaborador_id", "hh_servico_id" ON "public"."hh_lancamentos" FOR EACH ROW EXECUTE FUNCTION "public"."validate_hh_lancamento"();

ALTER TABLE "public"."hh_lancamentos" DISABLE TRIGGER "trigger_validate_hh_lancamento";



ALTER TABLE ONLY "a"."config_orcamento"
    ADD CONSTRAINT "fk_config_orcamento__condicao_pagamento__ref" FOREIGN KEY ("condicao_pagamento_padrao_id") REFERENCES "c"."condicao_pagamento"("id");



ALTER TABLE ONLY "a"."usuario"
    ADD CONSTRAINT "fk_usuario__auth_user_id__auth_users" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "a"."usuario_empresa"
    ADD CONSTRAINT "fk_usuario_empresa__empresa_id__c_empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "a"."usuario_empresa"
    ADD CONSTRAINT "fk_usuario_empresa__usuario_id__a_usuario" FOREIGN KEY ("usuario_id") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "a"."usuario_tenant"
    ADD CONSTRAINT "fk_usuario_tenant__tenant_id__c_tenant" FOREIGN KEY ("tenant_id") REFERENCES "c"."tenant"("id");



ALTER TABLE ONLY "a"."usuario_tenant"
    ADD CONSTRAINT "fk_usuario_tenant__usuario_id__a_usuario" FOREIGN KEY ("usuario_id") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "c"."conjunto_item"
    ADD CONSTRAINT "fk_conjunto_item__conjunto_id__c_conjunto" FOREIGN KEY ("conjunto_id") REFERENCES "c"."conjunto"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "c"."conjunto_item"
    ADD CONSTRAINT "fk_conjunto_item__item_id__public_itens" FOREIGN KEY ("item_id") REFERENCES "public"."itens"("id");



ALTER TABLE ONLY "c"."empresa"
    ADD CONSTRAINT "fk_empresa__tenant_id__c_tenant" FOREIGN KEY ("tenant_id") REFERENCES "c"."tenant"("id");



ALTER TABLE ONLY "c"."empresa_endereco"
    ADD CONSTRAINT "fk_empresa_endereco__empresa_id__c_empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "c"."empresa_fiscal"
    ADD CONSTRAINT "fk_empresa_fiscal__empresa_id__c_empresa" FOREIGN KEY ("empresa_id") REFERENCES "c"."empresa"("id");



ALTER TABLE ONLY "c"."i_caixa_item"
    ADD CONSTRAINT "fk_i_caixa_item__caixa_id__c_i_caixa" FOREIGN KEY ("caixa_id") REFERENCES "c"."i_caixa"("id");



ALTER TABLE ONLY "c"."i_caixa_item"
    ADD CONSTRAINT "fk_i_caixa_item__ferramenta_id__c_i_ferramenta" FOREIGN KEY ("ferramenta_id") REFERENCES "c"."i_ferramenta"("id");



ALTER TABLE ONLY "c"."i_caixa_vinculo"
    ADD CONSTRAINT "fk_i_caixa_vinculo__caixa_id__c_i_caixa" FOREIGN KEY ("caixa_id") REFERENCES "c"."i_caixa"("id");



ALTER TABLE ONLY "c"."i_caixa_vinculo"
    ADD CONSTRAINT "fk_i_caixa_vinculo__colaborador_id__public_colaboradores" FOREIGN KEY ("colaborador_id") REFERENCES "public"."colaboradores"("id");



ALTER TABLE ONLY "c"."i_ferramenta_codigo_seq"
    ADD CONSTRAINT "fk_i_ferr_codigo_seq__categoria_id__c_i_ferramenta_categoria" FOREIGN KEY ("categoria_id") REFERENCES "c"."i_ferramenta_categoria"("id");



ALTER TABLE ONLY "c"."i_ferramenta_sugestao_xml"
    ADD CONSTRAINT "fk_i_ferr_sug_xml__ferramenta_id__c_i_ferramenta" FOREIGN KEY ("ferramenta_id") REFERENCES "c"."i_ferramenta"("id");



ALTER TABLE ONLY "c"."i_ferramenta_unidade"
    ADD CONSTRAINT "fk_i_ferr_unid__ferramenta_id__c_i_ferramenta" FOREIGN KEY ("ferramenta_id") REFERENCES "c"."i_ferramenta"("id");



ALTER TABLE ONLY "c"."i_ferramenta_unidade_vinculo"
    ADD CONSTRAINT "fk_i_ferr_unid_vinc__colaborador_id__public_colaboradores" FOREIGN KEY ("colaborador_id") REFERENCES "public"."colaboradores"("id");



ALTER TABLE ONLY "c"."i_ferramenta_unidade_vinculo"
    ADD CONSTRAINT "fk_i_ferr_unid_vinc__unidade_id__c_i_ferr_unidade" FOREIGN KEY ("ferramenta_unidade_id") REFERENCES "c"."i_ferramenta_unidade"("id");



ALTER TABLE ONLY "c"."i_ferramenta"
    ADD CONSTRAINT "fk_i_ferramenta__categoria_id__c_i_ferr_cat" FOREIGN KEY ("categoria_id") REFERENCES "c"."i_ferramenta_categoria"("id");



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



ALTER TABLE ONLY "f"."titulo"
    ADD CONSTRAINT "titulo_motivo_compra_fk" FOREIGN KEY ("motivo_compra_id") REFERENCES "f"."motivo_compra"("id");



ALTER TABLE ONLY "m"."orcamento"
    ADD CONSTRAINT "fk_orcamento__cliente__ref" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id");



ALTER TABLE ONLY "m"."orcamento"
    ADD CONSTRAINT "fk_orcamento__condicao_pagamento__ref" FOREIGN KEY ("condicao_pagamento_id") REFERENCES "c"."condicao_pagamento"("id");



ALTER TABLE ONLY "m"."orcamento"
    ADD CONSTRAINT "fk_orcamento__vendedor_usuario__ref" FOREIGN KEY ("vendedor_usuario_id") REFERENCES "a"."usuario"("id");



ALTER TABLE ONLY "m"."orcamento_item"
    ADD CONSTRAINT "fk_orcamento_item__conjunto__ref" FOREIGN KEY ("conjunto_id") REFERENCES "c"."conjunto"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "m"."orcamento_item"
    ADD CONSTRAINT "fk_orcamento_item__item__ref" FOREIGN KEY ("item_id") REFERENCES "public"."itens"("id");



ALTER TABLE ONLY "m"."orcamento_item"
    ADD CONSTRAINT "fk_orcamento_item__orcamento__ref" FOREIGN KEY ("orcamento_id") REFERENCES "m"."orcamento"("id");



ALTER TABLE ONLY "public"."apontamentos_horas"
    ADD CONSTRAINT "apontamentos_horas_colaborador_id_fkey" FOREIGN KEY ("colaborador_id") REFERENCES "public"."colaboradores"("id");



ALTER TABLE ONLY "public"."apontamentos_horas"
    ADD CONSTRAINT "apontamentos_horas_hh_lancamento_id_fkey" FOREIGN KEY ("hh_lancamento_id") REFERENCES "public"."hh_lancamentos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apontamentos_horas"
    ADD CONSTRAINT "apontamentos_horas_tenant_empresa_os_fk" FOREIGN KEY ("tenant_id", "empresa_id", "os_id") REFERENCES "public"."ordens_servico"("tenant_id", "empresa_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apontamentos_horas"
    ADD CONSTRAINT "apontamentos_horas_tenant_os_fk" FOREIGN KEY ("tenant_id", "os_id") REFERENCES "public"."ordens_servico"("tenant_id", "id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."apontamentos_horas"
    ADD CONSTRAINT "apontamentos_horas_tipo_hora_id_fkey" FOREIGN KEY ("tipo_hora_id") REFERENCES "public"."tipos_horas"("id");



ALTER TABLE ONLY "public"."centros_custo"
    ADD CONSTRAINT "centros_custo_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cliente_hh_tabelas"
    ADD CONSTRAINT "cliente_hh_tabelas_cliente_fk" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."colaborador_funcao_hh"
    ADD CONSTRAINT "colaborador_funcao_hh_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."colaborador_funcao_hh"
    ADD CONSTRAINT "colaborador_funcao_hh_colaborador_id_fkey" FOREIGN KEY ("colaborador_id") REFERENCES "public"."colaboradores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."colaborador_funcao_hh"
    ADD CONSTRAINT "colaborador_funcao_hh_servico_hh_id_fkey" FOREIGN KEY ("servico_hh_id") REFERENCES "public"."cliente_hh_servicos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."colaborador_funcao_hh"
    ADD CONSTRAINT "colaborador_funcao_hh_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."colaborador_taxas"
    ADD CONSTRAINT "colaborador_taxas_colaborador_id_fkey" FOREIGN KEY ("colaborador_id") REFERENCES "public"."colaboradores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."competencias"
    ADD CONSTRAINT "competencias_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."empresa_memberships"
    ADD CONSTRAINT "empresa_memberships_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."empresa_memberships"
    ADD CONSTRAINT "empresa_memberships_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."empresa_memberships"
    ADD CONSTRAINT "empresa_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."estoque"
    ADD CONSTRAINT "estoque_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."itens"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."estoque"
    ADD CONSTRAINT "estoque_tenant_item_fk" FOREIGN KEY ("tenant_id", "item_id") REFERENCES "public"."itens"("tenant_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fiscal_itens"
    ADD CONSTRAINT "fiscal_itens_empresa_fk" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fiscal_itens"
    ADD CONSTRAINT "fiscal_itens_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."itens"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fiscal_itens"
    ADD CONSTRAINT "fiscal_itens_tenant_item_fk" FOREIGN KEY ("tenant_id", "item_id") REFERENCES "public"."itens"("tenant_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fiscal_regras"
    ADD CONSTRAINT "fiscal_regras_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cliente_hh_servicos"
    ADD CONSTRAINT "fk_cliente_hh_servicos_cliente" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."colaborador_cliente_funcao"
    ADD CONSTRAINT "fk_colaborador_cliente_funcao_cliente" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."colaborador_cliente_funcao"
    ADD CONSTRAINT "fk_colaborador_cliente_funcao_colaborador" FOREIGN KEY ("colaborador_id") REFERENCES "public"."colaboradores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."colaborador_cliente_funcao"
    ADD CONSTRAINT "fk_colaborador_cliente_funcao_servico" FOREIGN KEY ("hh_servico_id") REFERENCES "public"."cliente_hh_servicos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fornecedores"
    ADD CONSTRAINT "fk_fornecedores__motivo_compra_padrao_id__motivo_compra" FOREIGN KEY ("motivo_compra_padrao_id") REFERENCES "f"."motivo_compra"("id");



ALTER TABLE ONLY "public"."colaborador_cliente_funcao"
    ADD CONSTRAINT "fk_hh_servico" FOREIGN KEY ("hh_servico_id") REFERENCES "public"."cliente_hh_servicos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."itens"
    ADD CONSTRAINT "fk_itens__mesclado_em_item_id__itens" FOREIGN KEY ("mesclado_em_item_id") REFERENCES "public"."itens"("id");



ALTER TABLE ONLY "public"."nf_entrada"
    ADD CONSTRAINT "fk_nf_entrada__motivo_compra_id__f_motivo_compra" FOREIGN KEY ("motivo_compra_id") REFERENCES "f"."motivo_compra"("id") ON UPDATE RESTRICT ON DELETE SET NULL;



ALTER TABLE ONLY "public"."nf_entrada"
    ADD CONSTRAINT "fk_nf_entrada__solicitante_usuario_id__a_usuario" FOREIGN KEY ("solicitante_usuario_id") REFERENCES "a"."usuario"("id") ON UPDATE RESTRICT ON DELETE SET NULL;



ALTER TABLE ONLY "public"."fornecedores"
    ADD CONSTRAINT "fornecedores_motivo_compra_padrao_fk" FOREIGN KEY ("motivo_compra_padrao_id") REFERENCES "f"."motivo_compra"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hh_lancamentos"
    ADD CONSTRAINT "hh_lancamentos_colaborador_id_fkey" FOREIGN KEY ("colaborador_id") REFERENCES "public"."colaboradores"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hh_lancamentos"
    ADD CONSTRAINT "hh_lancamentos_hh_servico_id_fkey" FOREIGN KEY ("hh_servico_id") REFERENCES "public"."cliente_hh_servicos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hh_lancamentos"
    ADD CONSTRAINT "hh_lancamentos_hh_tipo_id_fkey" FOREIGN KEY ("hh_tipo_id") REFERENCES "public"."cliente_hh_servicos"("id");



ALTER TABLE ONLY "public"."hh_lancamentos"
    ADD CONSTRAINT "hh_lancamentos_os_id_fkey" FOREIGN KEY ("os_id") REFERENCES "public"."ordens_servico"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hh_tipos_mapping"
    ADD CONSTRAINT "hh_tipos_mapping_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hh_tipos_mapping"
    ADD CONSTRAINT "hh_tipos_mapping_tipo_hora_id_fkey" FOREIGN KEY ("tipo_hora_id") REFERENCES "public"."tipos_horas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."horas_trabalhadas"
    ADD CONSTRAINT "horas_trabalhadas_os_id_fkey" FOREIGN KEY ("os_id") REFERENCES "public"."ordens_servico"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."horas_trabalhadas"
    ADD CONSTRAINT "horas_trabalhadas_profissional_id_fkey" FOREIGN KEY ("profissional_id") REFERENCES "public"."profissionais"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."itens"
    ADD CONSTRAINT "itens_motivo_compra_fk" FOREIGN KEY ("motivo_compra_id") REFERENCES "f"."motivo_compra"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."itens"
    ADD CONSTRAINT "itens_tenant_empresa_fornecedor_fk" FOREIGN KEY ("tenant_id", "empresa_id", "fornecedor_id") REFERENCES "public"."fornecedores"("tenant_id", "empresa_id", "id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lancamentos_contabeis"
    ADD CONSTRAINT "lancamentos_contabeis_competencia_id_fkey" FOREIGN KEY ("competencia_id") REFERENCES "public"."competencias"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."lancamentos_contabeis"
    ADD CONSTRAINT "lancamentos_contabeis_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lancamentos_contabeis_itens"
    ADD CONSTRAINT "lancamentos_contabeis_itens_centro_custo_id_fkey" FOREIGN KEY ("centro_custo_id") REFERENCES "public"."centros_custo"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."lancamentos_contabeis_itens"
    ADD CONSTRAINT "lancamentos_contabeis_itens_conta_id_fkey" FOREIGN KEY ("conta_id") REFERENCES "public"."plano_contas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."lancamentos_contabeis_itens"
    ADD CONSTRAINT "lancamentos_contabeis_itens_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lancamentos_contabeis_itens"
    ADD CONSTRAINT "lancamentos_contabeis_itens_lancamento_id_fkey" FOREIGN KEY ("lancamento_id") REFERENCES "public"."lancamentos_contabeis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."membership_roles"
    ADD CONSTRAINT "membership_roles_membership_id_fkey" FOREIGN KEY ("membership_id") REFERENCES "public"."tenant_memberships"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."membership_roles"
    ADD CONSTRAINT "membership_roles_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."movimentacoes"
    ADD CONSTRAINT "movimentacoes_empresa_fk" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id");



ALTER TABLE ONLY "public"."movimentacoes"
    ADD CONSTRAINT "movimentacoes_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."itens"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."movimentacoes"
    ADD CONSTRAINT "movimentacoes_origem_nf_entrada_id_fkey" FOREIGN KEY ("origem_nf_entrada_id") REFERENCES "public"."nf_entrada"("id");



ALTER TABLE ONLY "public"."movimentacoes"
    ADD CONSTRAINT "movimentacoes_tenant_item_fk" FOREIGN KEY ("tenant_id", "item_id") REFERENCES "public"."itens"("tenant_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."nf_entrada"
    ADD CONSTRAINT "nf_entrada_empresa_fk" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id");



ALTER TABLE ONLY "public"."nf_entrada"
    ADD CONSTRAINT "nf_entrada_fornecedor_id_fkey" FOREIGN KEY ("fornecedor_id") REFERENCES "public"."fornecedores"("id");



ALTER TABLE ONLY "public"."nf_entrada_itens"
    ADD CONSTRAINT "nf_entrada_itens_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."itens"("id");



ALTER TABLE ONLY "public"."nf_entrada_itens"
    ADD CONSTRAINT "nf_entrada_itens_tenant_empresa_nf_fk" FOREIGN KEY ("tenant_id", "empresa_id", "nf_entrada_id") REFERENCES "public"."nf_entrada"("tenant_id", "empresa_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."nf_entrada_itens"
    ADD CONSTRAINT "nf_entrada_itens_tenant_nf_fk" FOREIGN KEY ("tenant_id", "nf_entrada_id") REFERENCES "public"."nf_entrada"("tenant_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ordens_servico"
    ADD CONSTRAINT "ordens_servico_tenant_empresa_cliente_fk" FOREIGN KEY ("tenant_id", "empresa_id", "cliente_id") REFERENCES "public"."clientes"("tenant_id", "empresa_id", "id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."os_gestao_itens"
    ADD CONSTRAINT "os_gestao_itens_os_id_fkey" FOREIGN KEY ("os_id") REFERENCES "public"."ordens_servico"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."os_gestao_itens"
    ADD CONSTRAINT "os_gestao_itens_tenant_os_fk" FOREIGN KEY ("tenant_id", "os_id") REFERENCES "public"."ordens_servico"("tenant_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."os_itens"
    ADD CONSTRAINT "os_itens_tenant_empresa_item_fk" FOREIGN KEY ("tenant_id", "empresa_id", "item_id") REFERENCES "public"."itens"("tenant_id", "empresa_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."os_itens"
    ADD CONSTRAINT "os_itens_tenant_empresa_os_fk" FOREIGN KEY ("tenant_id", "empresa_id", "os_id") REFERENCES "public"."ordens_servico"("tenant_id", "empresa_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."plano_contas"
    ADD CONSTRAINT "plano_contas_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."plano_contas"
    ADD CONSTRAINT "plano_contas_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."plano_contas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."role_access_rules"
    ADD CONSTRAINT "role_access_rules_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tenant_memberships"
    ADD CONSTRAINT "tenant_memberships_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tenant_memberships"
    ADD CONSTRAINT "tenant_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_empresa_context"
    ADD CONSTRAINT "user_empresa_context_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_empresa_context"
    ADD CONSTRAINT "user_empresa_context_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_empresa_context"
    ADD CONSTRAINT "user_empresa_context_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_tenant_context"
    ADD CONSTRAINT "user_tenant_context_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_tenant_context"
    ADD CONSTRAINT "user_tenant_context_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "a"."config_orcamento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "config_orcamento_all" ON "a"."config_orcamento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "a"."usuario" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "a"."usuario_empresa" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "usuario_empresa_insert_admin" ON "a"."usuario_empresa" FOR INSERT TO "authenticated" WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_can_manage_empresa"("empresa_id")));



CREATE POLICY "usuario_empresa_select_self_or_admin" ON "a"."usuario_empresa" FOR SELECT TO "authenticated" USING ((("deleted_at" IS NULL) AND (("usuario_id" = "a"."fn_current_usuario_id"()) OR "a"."fn_can_manage_empresa"("empresa_id"))));



CREATE POLICY "usuario_empresa_update_admin" ON "a"."usuario_empresa" FOR UPDATE TO "authenticated" USING ((("deleted_at" IS NULL) AND "a"."fn_can_manage_empresa"("empresa_id"))) WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_can_manage_empresa"("empresa_id")));



CREATE POLICY "usuario_select_self_or_tenant_admin" ON "a"."usuario" FOR SELECT TO "authenticated" USING ((("deleted_at" IS NULL) AND (("id" = "a"."fn_current_usuario_id"()) OR "a"."fn_is_admin_of_same_tenant"("id"))));



ALTER TABLE "a"."usuario_tenant" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "usuario_tenant_insert_admin" ON "a"."usuario_tenant" FOR INSERT TO "authenticated" WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("tenant_id")));



CREATE POLICY "usuario_tenant_select_self_or_admin" ON "a"."usuario_tenant" FOR SELECT TO "authenticated" USING ((("deleted_at" IS NULL) AND (("usuario_id" = "a"."fn_current_usuario_id"()) OR "a"."fn_is_tenant_admin"("tenant_id"))));



CREATE POLICY "usuario_tenant_update_admin" ON "a"."usuario_tenant" FOR UPDATE TO "authenticated" USING ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("tenant_id"))) WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("tenant_id")));



CREATE POLICY "usuario_update_admin_only" ON "a"."usuario" FOR UPDATE TO "authenticated" USING ((("deleted_at" IS NULL) AND "a"."fn_is_admin_of_same_tenant"("id"))) WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_is_admin_of_same_tenant"("id")));



ALTER TABLE "c"."condicao_pagamento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "condicao_pagamento_all" ON "c"."condicao_pagamento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "c"."conjunto" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conjunto_all" ON "c"."conjunto" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "c"."conjunto_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conjunto_item_all" ON "c"."conjunto_item" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL)));



CREATE POLICY "conjunto_item_soft_delete" ON "c"."conjunto_item" FOR UPDATE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"()));



CREATE POLICY "conjunto_soft_delete" ON "c"."conjunto" FOR UPDATE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"()));



ALTER TABLE "c"."empresa" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "empresa_insert_admin" ON "c"."empresa" FOR INSERT TO "authenticated" WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("tenant_id")));



CREATE POLICY "empresa_select_member" ON "c"."empresa" FOR SELECT TO "authenticated" USING ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_member"("tenant_id")));



CREATE POLICY "empresa_update_admin" ON "c"."empresa" FOR UPDATE TO "authenticated" USING ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("tenant_id"))) WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("tenant_id")));



ALTER TABLE "c"."i_caixa" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "i_caixa_all" ON "c"."i_caixa" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "c"."i_caixa_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "i_caixa_item_all" ON "c"."i_caixa_item" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "c"."i_caixa_vinculo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "i_caixa_vinculo_all" ON "c"."i_caixa_vinculo" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL)));



CREATE POLICY "i_ferr_sug_xml_all" ON "c"."i_ferramenta_sugestao_xml" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL)));



CREATE POLICY "i_ferr_unid_all" ON "c"."i_ferramenta_unidade" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL)));



CREATE POLICY "i_ferr_unid_vinc_all" ON "c"."i_ferramenta_unidade_vinculo" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "c"."i_ferramenta" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "i_ferramenta_all" ON "c"."i_ferramenta" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_imobilizado_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "c"."i_ferramenta_sugestao_xml" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "c"."i_ferramenta_unidade" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "c"."i_ferramenta_unidade_vinculo" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "c"."tenant" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenant_select_member" ON "c"."tenant" FOR SELECT TO "authenticated" USING ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_member"("id")));



CREATE POLICY "tenant_update_admin" ON "c"."tenant" FOR UPDATE TO "authenticated" USING ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("id"))) WITH CHECK ((("deleted_at" IS NULL) AND "a"."fn_is_tenant_admin"("id")));



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



ALTER TABLE "m"."orcamento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orcamento_all" ON "m"."orcamento" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"() AND ("deleted_at" IS NULL)));



ALTER TABLE "m"."orcamento_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orcamento_item_insert" ON "m"."orcamento_item" FOR INSERT TO "authenticated" WITH CHECK (("c"."has_comercial_access"("tenant_id", "empresa_id") AND ("deleted_at" IS NULL)));



CREATE POLICY "orcamento_item_select" ON "m"."orcamento_item" FOR SELECT TO "authenticated" USING ("c"."has_comercial_access"("tenant_id", "empresa_id"));



CREATE POLICY "orcamento_item_update" ON "m"."orcamento_item" FOR UPDATE TO "authenticated" USING (("c"."has_comercial_access"("tenant_id", "empresa_id") AND ("deleted_at" IS NULL))) WITH CHECK (true);



ALTER TABLE "m"."orcamento_seq" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orcamento_seq_all" ON "m"."orcamento_seq" TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"())) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "c"."has_comercial_access"()));



CREATE POLICY "Users can view their tenants" ON "public"."tenants" FOR SELECT USING (("id" IN ( SELECT "tenant_memberships"."tenant_id"
   FROM "public"."tenant_memberships"
  WHERE (("tenant_memberships"."user_id" = "auth"."uid"()) AND ("tenant_memberships"."status" = 'active'::"text")))));



ALTER TABLE "public"."apontamentos_horas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "apontamentos_horas_delete" ON "public"."apontamentos_horas" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."empresa_memberships" "em"
  WHERE (("em"."user_id" = "auth"."uid"()) AND ("em"."tenant_id" = "em"."tenant_id") AND ("em"."empresa_id" = "em"."empresa_id") AND ("em"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



CREATE POLICY "apontamentos_horas_insert" ON "public"."apontamentos_horas" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."empresa_memberships" "em"
  WHERE (("em"."user_id" = "auth"."uid"()) AND ("em"."tenant_id" = "em"."tenant_id") AND ("em"."empresa_id" = "em"."empresa_id") AND ("em"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



CREATE POLICY "apontamentos_horas_select" ON "public"."apontamentos_horas" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."empresa_memberships" "em"
  WHERE (("em"."user_id" = "auth"."uid"()) AND ("em"."tenant_id" = "em"."tenant_id") AND ("em"."empresa_id" = "em"."empresa_id") AND ("em"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



CREATE POLICY "apontamentos_horas_update" ON "public"."apontamentos_horas" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."empresa_memberships" "em"
  WHERE (("em"."user_id" = "auth"."uid"()) AND ("em"."tenant_id" = "em"."tenant_id") AND ("em"."empresa_id" = "em"."empresa_id") AND ("em"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."empresa_memberships" "em"
  WHERE (("em"."user_id" = "auth"."uid"()) AND ("em"."tenant_id" = "em"."tenant_id") AND ("em"."empresa_id" = "em"."empresa_id") AND ("em"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



ALTER TABLE "public"."cliente_hh_servicos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cliente_hh_servicos_delete" ON "public"."cliente_hh_servicos" FOR DELETE USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text"))));



CREATE POLICY "cliente_hh_servicos_insert" ON "public"."cliente_hh_servicos" FOR INSERT WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))));



CREATE POLICY "cliente_hh_servicos_select" ON "public"."cliente_hh_servicos" FOR SELECT USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))));



CREATE POLICY "cliente_hh_servicos_tenant_empresa_policy" ON "public"."cliente_hh_servicos" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))));



CREATE POLICY "cliente_hh_servicos_update" ON "public"."cliente_hh_servicos" FOR UPDATE USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text")))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))));



ALTER TABLE "public"."cliente_hh_tabelas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cliente_hh_tabelas_delete" ON "public"."cliente_hh_tabelas" FOR DELETE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'delete'::"text")));



CREATE POLICY "cliente_hh_tabelas_insert" ON "public"."cliente_hh_tabelas" FOR INSERT TO "authenticated" WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'write'::"text")));



CREATE POLICY "cliente_hh_tabelas_select" ON "public"."cliente_hh_tabelas" FOR SELECT TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'read'::"text")));



CREATE POLICY "cliente_hh_tabelas_update" ON "public"."cliente_hh_tabelas" FOR UPDATE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'write'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'write'::"text")));



ALTER TABLE "public"."clientes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clientes_delete" ON "public"."clientes" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("a"."usuario_empresa" "ue"
     JOIN "public"."empresas" "emp" ON (("emp"."id" = "ue"."empresa_id")))
  WHERE (("ue"."usuario_id" = "a"."fn_current_usuario_id"()) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("ue"."empresa_id" = "clientes"."empresa_id") AND ("emp"."tenant_id" = "clientes"."tenant_id") AND ("upper"("ue"."papel") = 'ADMIN'::"text")))));



CREATE POLICY "clientes_insert" ON "public"."clientes" FOR INSERT TO "authenticated" WITH CHECK ((("public"."can"('cad_clientes'::"text", 'write'::"text") OR (EXISTS ( SELECT 1
   FROM ("a"."usuario_empresa" "ue"
     JOIN "public"."empresas" "emp" ON (("emp"."id" = "ue"."empresa_id")))
  WHERE (("ue"."usuario_id" = "a"."fn_current_usuario_id"()) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("ue"."empresa_id" = "clientes"."empresa_id") AND ("emp"."tenant_id" = "clientes"."tenant_id") AND ("upper"("ue"."papel") = ANY (ARRAY['ADMIN'::"text", 'FINANCEIRO'::"text", 'COORDENACAO'::"text", 'COMPRAS'::"text"])))))) AND ("tenant_id" = ( SELECT "e"."tenant_id"
   FROM "public"."empresas" "e"
  WHERE ("e"."id" = "clientes"."empresa_id")
 LIMIT 1))));



CREATE POLICY "clientes_select" ON "public"."clientes" FOR SELECT TO "authenticated" USING (("public"."can"('os'::"text", 'read'::"text") OR "public"."can"('cad_clientes'::"text", 'write'::"text") OR (EXISTS ( SELECT 1
   FROM ("a"."usuario_empresa" "ue"
     JOIN "public"."empresas" "emp" ON (("emp"."id" = "ue"."empresa_id")))
  WHERE (("ue"."usuario_id" = "a"."fn_current_usuario_id"()) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("ue"."empresa_id" = "clientes"."empresa_id") AND ("emp"."tenant_id" = "clientes"."tenant_id") AND ("upper"("ue"."papel") = ANY (ARRAY['ADMIN'::"text", 'FINANCEIRO'::"text", 'COORDENACAO'::"text", 'COMPRAS'::"text"])))))));



CREATE POLICY "clientes_update" ON "public"."clientes" FOR UPDATE TO "authenticated" USING (("public"."can"('cad_clientes'::"text", 'write'::"text") OR (EXISTS ( SELECT 1
   FROM ("a"."usuario_empresa" "ue"
     JOIN "public"."empresas" "emp" ON (("emp"."id" = "ue"."empresa_id")))
  WHERE (("ue"."usuario_id" = "a"."fn_current_usuario_id"()) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("ue"."empresa_id" = "clientes"."empresa_id") AND ("emp"."tenant_id" = "clientes"."tenant_id") AND ("upper"("ue"."papel") = ANY (ARRAY['ADMIN'::"text", 'FINANCEIRO'::"text", 'COORDENACAO'::"text", 'COMPRAS'::"text"]))))))) WITH CHECK ((("public"."can"('cad_clientes'::"text", 'write'::"text") OR (EXISTS ( SELECT 1
   FROM ("a"."usuario_empresa" "ue"
     JOIN "public"."empresas" "emp" ON (("emp"."id" = "ue"."empresa_id")))
  WHERE (("ue"."usuario_id" = "a"."fn_current_usuario_id"()) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("ue"."empresa_id" = "clientes"."empresa_id") AND ("emp"."tenant_id" = "clientes"."tenant_id") AND ("upper"("ue"."papel") = ANY (ARRAY['ADMIN'::"text", 'FINANCEIRO'::"text", 'COORDENACAO'::"text", 'COMPRAS'::"text"])))))) AND ("tenant_id" = ( SELECT "e"."tenant_id"
   FROM "public"."empresas" "e"
  WHERE ("e"."id" = "clientes"."empresa_id")
 LIMIT 1))));



ALTER TABLE "public"."colaborador_cliente_funcao" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "colaborador_cliente_funcao_delete" ON "public"."colaborador_cliente_funcao" FOR DELETE USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text"))));



CREATE POLICY "colaborador_cliente_funcao_insert" ON "public"."colaborador_cliente_funcao" FOR INSERT WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))));



CREATE POLICY "colaborador_cliente_funcao_select" ON "public"."colaborador_cliente_funcao" FOR SELECT USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))));



CREATE POLICY "colaborador_cliente_funcao_update" ON "public"."colaborador_cliente_funcao" FOR UPDATE USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text")))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text") OR "public"."can__legacy_40734"('financeiro'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))));



ALTER TABLE "public"."colaborador_funcao_hh" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "colaborador_funcao_hh_delete" ON "public"."colaborador_funcao_hh" FOR DELETE USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text")));



CREATE POLICY "colaborador_funcao_hh_insert" ON "public"."colaborador_funcao_hh" FOR INSERT WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text")));



CREATE POLICY "colaborador_funcao_hh_select" ON "public"."colaborador_funcao_hh" FOR SELECT USING (("tenant_id" = "public"."current_tenant_id"()));



CREATE POLICY "colaborador_funcao_hh_update" ON "public"."colaborador_funcao_hh" FOR UPDATE USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'write'::"text")));



ALTER TABLE "public"."colaborador_taxas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "colaborador_taxas_delete" ON "public"."colaborador_taxas" FOR DELETE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'config'::"text")));



CREATE POLICY "colaborador_taxas_insert" ON "public"."colaborador_taxas" FOR INSERT TO "authenticated" WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'config'::"text")));



CREATE POLICY "colaborador_taxas_select" ON "public"."colaborador_taxas" FOR SELECT TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'read'::"text")));



CREATE POLICY "colaborador_taxas_update" ON "public"."colaborador_taxas" FOR UPDATE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'config'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('apontamentos'::"text", 'config'::"text")));



ALTER TABLE "public"."colaboradores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "colaboradores_delete" ON "public"."colaboradores" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "colaboradores"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



CREATE POLICY "colaboradores_insert" ON "public"."colaboradores" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "colaboradores"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



CREATE POLICY "colaboradores_select" ON "public"."colaboradores" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "colaboradores"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



CREATE POLICY "colaboradores_update" ON "public"."colaboradores" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "colaboradores"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "colaboradores"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"]))))));



ALTER TABLE "public"."empresa_memberships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "empresa_memberships_delete" ON "public"."empresa_memberships" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "empresa_memberships"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))));



CREATE POLICY "empresa_memberships_insert" ON "public"."empresa_memberships" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "empresa_memberships"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))));



CREATE POLICY "empresa_memberships_select" ON "public"."empresa_memberships" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "empresa_memberships"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))));



CREATE POLICY "empresa_memberships_update" ON "public"."empresa_memberships" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "empresa_memberships"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "empresa_memberships"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))));



CREATE POLICY "empresas_delete" ON "public"."empresas" FOR DELETE USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.manage_users'::"text")));



CREATE POLICY "empresas_insert" ON "public"."empresas" FOR INSERT WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.manage_users'::"text")));



CREATE POLICY "empresas_select_a" ON "public"."empresas" FOR SELECT TO "authenticated" USING (("public"."a_is_empresa_member"("id") OR "public"."a_is_tenant_role"("tenant_id", ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text", 'projetos'::"text", 'financeiro'::"text"])));



CREATE POLICY "empresas_update" ON "public"."empresas" FOR UPDATE USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.manage_users'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.manage_users'::"text")));



ALTER TABLE "public"."estoque" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "estoque_delete" ON "public"."estoque" FOR DELETE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "estoque_delete_a" ON "public"."estoque" FOR DELETE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."a_is_tenant_role"("tenant_id", ARRAY['admin'::"text"])));



CREATE POLICY "estoque_insert" ON "public"."estoque" FOR INSERT TO "authenticated" WITH CHECK ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "estoque_insert_a" ON "public"."estoque" FOR INSERT TO "authenticated" WITH CHECK ((("empresa_id" IS NOT NULL) AND "public"."a_is_tenant_role"("tenant_id", ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"])));



CREATE POLICY "estoque_select" ON "public"."estoque" FOR SELECT TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'read'::"text")));



CREATE POLICY "estoque_select_a" ON "public"."estoque" FOR SELECT TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."a_is_tenant_role"("tenant_id", ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"])));



CREATE POLICY "estoque_update" ON "public"."estoque" FOR UPDATE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text"))) WITH CHECK ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "estoque_update_a" ON "public"."estoque" FOR UPDATE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."a_is_tenant_role"("tenant_id", ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"]))) WITH CHECK ((("empresa_id" IS NOT NULL) AND "public"."a_is_tenant_role"("tenant_id", ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"])));



ALTER TABLE "public"."fiscal_itens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fiscal_itens_delete" ON "public"."fiscal_itens" FOR DELETE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_itens'::"text", 'write'::"text")));



CREATE POLICY "fiscal_itens_insert" ON "public"."fiscal_itens" FOR INSERT TO "authenticated" WITH CHECK ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_itens'::"text", 'write'::"text")));



CREATE POLICY "fiscal_itens_select" ON "public"."fiscal_itens" FOR SELECT TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('fiscal_nf'::"text", 'read'::"text") OR "public"."can__legacy_40734"('fiscal_itens'::"text", 'write'::"text"))));



CREATE POLICY "fiscal_itens_update" ON "public"."fiscal_itens" FOR UPDATE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_itens'::"text", 'write'::"text"))) WITH CHECK ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_itens'::"text", 'write'::"text")));



ALTER TABLE "public"."fornecedores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fornecedores_delete" ON "public"."fornecedores" FOR DELETE TO "authenticated" USING (("public"."can__legacy_40734"('cad_fornecedores'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "fornecedores_insert" ON "public"."fornecedores" FOR INSERT TO "authenticated" WITH CHECK (("public"."can__legacy_40734"('cad_fornecedores'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "fornecedores_select" ON "public"."fornecedores" FOR SELECT TO "authenticated" USING (("public"."can__legacy_40734"('estoque'::"text", 'read'::"text") OR "public"."can__legacy_40734"('cad_fornecedores'::"text", 'write'::"text")));



CREATE POLICY "fornecedores_update" ON "public"."fornecedores" FOR UPDATE TO "authenticated" USING (("public"."can__legacy_40734"('cad_fornecedores'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text"))) WITH CHECK (("public"."can__legacy_40734"('cad_fornecedores'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



ALTER TABLE "public"."hh_especialidades" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hh_especialidades_delete" ON "public"."hh_especialidades" FOR DELETE USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can"('hh'::"text", 'delete'::"text")));



CREATE POLICY "hh_especialidades_insert" ON "public"."hh_especialidades" FOR INSERT WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can"('hh'::"text", 'write'::"text")));



CREATE POLICY "hh_especialidades_select" ON "public"."hh_especialidades" FOR SELECT USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can"('hh'::"text", 'read'::"text")));



CREATE POLICY "hh_especialidades_update" ON "public"."hh_especialidades" FOR UPDATE USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can"('hh'::"text", 'write'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can"('hh'::"text", 'write'::"text")));



ALTER TABLE "public"."hh_lancamentos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hh_lancamentos_delete" ON "public"."hh_lancamentos" FOR DELETE USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'delete'::"text")));



CREATE POLICY "hh_lancamentos_insert" ON "public"."hh_lancamentos" FOR INSERT WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'write'::"text")));



CREATE POLICY "hh_lancamentos_select" ON "public"."hh_lancamentos" FOR SELECT USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'read'::"text")));



CREATE POLICY "hh_lancamentos_tenant_isolation" ON "public"."hh_lancamentos" USING (("tenant_id" = "public"."current_tenant_id"()));



CREATE POLICY "hh_lancamentos_update" ON "public"."hh_lancamentos" FOR UPDATE USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND "public"."can__legacy_40734"('os'::"text", 'write'::"text")));



ALTER TABLE "public"."itens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "itens_delete" ON "public"."itens" FOR DELETE TO "authenticated" USING (("public"."can__legacy_40734"('cad_itens'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "itens_insert" ON "public"."itens" FOR INSERT TO "authenticated" WITH CHECK (("public"."can__legacy_40734"('cad_itens'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "itens_select" ON "public"."itens" FOR SELECT TO "authenticated" USING (("public"."can__legacy_40734"('estoque'::"text", 'read'::"text") OR "public"."can__legacy_40734"('os'::"text", 'read'::"text") OR "public"."can__legacy_40734"('cad_itens'::"text", 'write'::"text")));



CREATE POLICY "itens_update" ON "public"."itens" FOR UPDATE TO "authenticated" USING (("public"."can__legacy_40734"('cad_itens'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text"))) WITH CHECK (("public"."can__legacy_40734"('cad_itens'::"text", 'write'::"text") OR "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



ALTER TABLE "public"."membership_roles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "membership_roles_delete_admin" ON "public"."membership_roles" FOR DELETE TO "authenticated" USING (("public"."has_permission"('admin.users.manage'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."id" = "membership_roles"."membership_id") AND ("tm"."tenant_id" = "public"."current_tenant_id"()))))));



CREATE POLICY "membership_roles_insert_admin" ON "public"."membership_roles" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_permission"('admin.users.manage'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."id" = "membership_roles"."membership_id") AND ("tm"."tenant_id" = "public"."current_tenant_id"()))))));



CREATE POLICY "membership_roles_select_admin" ON "public"."membership_roles" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."id" = "membership_roles"."membership_id") AND ("tm"."tenant_id" = "public"."current_tenant_id"())))) AND "public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text")));



CREATE POLICY "membership_roles_select_self" ON "public"."membership_roles" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."id" = "membership_roles"."membership_id") AND ("tm"."user_id" = "auth"."uid"())))));



CREATE POLICY "memberships_delete_admin" ON "public"."tenant_memberships" FOR DELETE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.users.manage'::"text")));



CREATE POLICY "memberships_insert_admin" ON "public"."tenant_memberships" FOR INSERT TO "authenticated" WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.users.manage'::"text")));



CREATE POLICY "memberships_select_admin" ON "public"."tenant_memberships" FOR SELECT TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.users.manage'::"text")));



CREATE POLICY "memberships_select_self" ON "public"."tenant_memberships" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "memberships_update_admin" ON "public"."tenant_memberships" FOR UPDATE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.users.manage'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."has_permission"('admin.users.manage'::"text")));



ALTER TABLE "public"."movimentacoes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "movimentacoes_delete" ON "public"."movimentacoes" FOR DELETE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "movimentacoes_insert" ON "public"."movimentacoes" FOR INSERT TO "authenticated" WITH CHECK ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



CREATE POLICY "movimentacoes_select" ON "public"."movimentacoes" FOR SELECT TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'read'::"text")));



CREATE POLICY "movimentacoes_update" ON "public"."movimentacoes" FOR UPDATE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text"))) WITH CHECK ((("empresa_id" IS NOT NULL) AND "public"."can__legacy_40734"('estoque'::"text", 'write'::"text")));



ALTER TABLE "public"."nf_entrada" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "nf_entrada_delete" ON "public"."nf_entrada" FOR DELETE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'delete'::"text")));



CREATE POLICY "nf_entrada_insert" ON "public"."nf_entrada" FOR INSERT TO "authenticated" WITH CHECK ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'write'::"text")));



ALTER TABLE "public"."nf_entrada_itens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "nf_entrada_itens_delete" ON "public"."nf_entrada_itens" FOR DELETE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'delete'::"text")));



CREATE POLICY "nf_entrada_itens_insert" ON "public"."nf_entrada_itens" FOR INSERT TO "authenticated" WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'write'::"text")));



CREATE POLICY "nf_entrada_itens_select" ON "public"."nf_entrada_itens" FOR SELECT TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'read'::"text")));



CREATE POLICY "nf_entrada_itens_update" ON "public"."nf_entrada_itens" FOR UPDATE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'write'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'write'::"text")));



CREATE POLICY "nf_entrada_select" ON "public"."nf_entrada" FOR SELECT TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'read'::"text")));



CREATE POLICY "nf_entrada_update" ON "public"."nf_entrada" FOR UPDATE TO "authenticated" USING ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'write'::"text"))) WITH CHECK ((("empresa_id" IS NOT NULL) AND ("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('fiscal_nf'::"text", 'write'::"text")));



ALTER TABLE "public"."ordens_servico" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ordens_servico_delete" ON "public"."ordens_servico" FOR DELETE TO "authenticated" USING ("public"."can__legacy_40734"('os'::"text", 'delete'::"text"));



CREATE POLICY "ordens_servico_insert" ON "public"."ordens_servico" FOR INSERT TO "authenticated" WITH CHECK ("public"."can__legacy_40734"('os'::"text", 'write'::"text"));



CREATE POLICY "ordens_servico_select" ON "public"."ordens_servico" FOR SELECT TO "authenticated" USING ("public"."can__legacy_40734"('os'::"text", 'read'::"text"));



CREATE POLICY "ordens_servico_select_painel_tv" ON "public"."ordens_servico" FOR SELECT TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND (EXISTS ( SELECT 1
   FROM ("a"."usuario" "u"
     JOIN "a"."usuario_empresa" "ue" ON (("ue"."usuario_id" = "u"."id")))
  WHERE (("u"."auth_user_id" = "auth"."uid"()) AND ("u"."deleted_at" IS NULL) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("ue"."empresa_id" = "public"."current_empresa_id"()) AND ("ue"."papel" = 'PAINEL_TV'::"text"))))));



CREATE POLICY "ordens_servico_update" ON "public"."ordens_servico" FOR UPDATE TO "authenticated" USING ("public"."can__legacy_40734"('os'::"text", 'write'::"text")) WITH CHECK ("public"."can__legacy_40734"('os'::"text", 'write'::"text"));



ALTER TABLE "public"."os_gestao_itens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "os_gestao_itens_delete" ON "public"."os_gestao_itens" FOR DELETE TO "authenticated" USING ("public"."can__legacy_40734"('os_gestao'::"text", 'write'::"text"));



CREATE POLICY "os_gestao_itens_insert" ON "public"."os_gestao_itens" FOR INSERT TO "authenticated" WITH CHECK ("public"."can__legacy_40734"('os_gestao'::"text", 'write'::"text"));



CREATE POLICY "os_gestao_itens_select" ON "public"."os_gestao_itens" FOR SELECT TO "authenticated" USING ("public"."can__legacy_40734"('os'::"text", 'read'::"text"));



CREATE POLICY "os_gestao_itens_select_painel_tv" ON "public"."os_gestao_itens" FOR SELECT TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("empresa_id" = "public"."current_empresa_id"()) AND (EXISTS ( SELECT 1
   FROM ("a"."usuario" "u"
     JOIN "a"."usuario_empresa" "ue" ON (("ue"."usuario_id" = "u"."id")))
  WHERE (("u"."auth_user_id" = "auth"."uid"()) AND ("u"."deleted_at" IS NULL) AND ("ue"."deleted_at" IS NULL) AND ("ue"."ativo" = true) AND ("ue"."empresa_id" = "public"."current_empresa_id"()) AND ("ue"."papel" = 'PAINEL_TV'::"text"))))));



CREATE POLICY "os_gestao_itens_update" ON "public"."os_gestao_itens" FOR UPDATE TO "authenticated" USING ("public"."can__legacy_40734"('os_gestao'::"text", 'write'::"text")) WITH CHECK ("public"."can__legacy_40734"('os_gestao'::"text", 'write'::"text"));



ALTER TABLE "public"."os_itens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "os_itens_delete" ON "public"."os_itens" FOR DELETE TO "authenticated" USING ("public"."can__legacy_40734"('os_itens'::"text", 'write'::"text"));



CREATE POLICY "os_itens_insert" ON "public"."os_itens" FOR INSERT TO "authenticated" WITH CHECK ("public"."can__legacy_40734"('os_itens'::"text", 'write'::"text"));



CREATE POLICY "os_itens_select" ON "public"."os_itens" FOR SELECT TO "authenticated" USING ("public"."can__legacy_40734"('os'::"text", 'read'::"text"));



CREATE POLICY "os_itens_update" ON "public"."os_itens" FOR UPDATE TO "authenticated" USING ("public"."can__legacy_40734"('os_itens'::"text", 'write'::"text")) WITH CHECK ("public"."can__legacy_40734"('os_itens'::"text", 'write'::"text"));



ALTER TABLE "public"."parametro_importacao_xml" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."permissions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "permissions_select_all" ON "public"."permissions" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select" ON "public"."profiles" FOR SELECT USING ((("id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM ("public"."tenant_memberships" "tm_me"
     JOIN "public"."tenant_memberships" "tm_target" ON ((("tm_target"."user_id" = "profiles"."id") AND ("tm_target"."tenant_id" = "tm_me"."tenant_id"))))
  WHERE (("tm_me"."user_id" = "auth"."uid"()) AND ("tm_me"."status" = 'active'::"text") AND ("tm_target"."status" = 'active'::"text"))))));



CREATE POLICY "profiles_update" ON "public"."profiles" FOR UPDATE USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."role_access_rules" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "role_access_rules_admin" ON "public"."role_access_rules" TO "authenticated" USING ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text")) WITH CHECK ("public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text"));



ALTER TABLE "public"."roles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "roles_select_by_membership" ON "public"."roles" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."status" = 'active'::"text") AND ("tm"."tenant_id" = "roles"."tenant_id")))));



CREATE POLICY "tenant_delete_fornecedores" ON "public"."fornecedores" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fornecedores"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))));



CREATE POLICY "tenant_delete_itens" ON "public"."itens" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))));



CREATE POLICY "tenant_delete_nf_entrada_itens" ON "public"."nf_entrada_itens" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))));



CREATE POLICY "tenant_empresa_delete_fiscal_itens" ON "public"."fiscal_itens" FOR DELETE USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fiscal_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))));



CREATE POLICY "tenant_empresa_delete_movimentacoes" ON "public"."movimentacoes" FOR DELETE USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "movimentacoes"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))));



CREATE POLICY "tenant_empresa_delete_nf_entrada" ON "public"."nf_entrada" FOR DELETE USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))));



CREATE POLICY "tenant_empresa_insert_fiscal_itens" ON "public"."fiscal_itens" FOR INSERT WITH CHECK ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fiscal_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"])))))));



CREATE POLICY "tenant_empresa_insert_movimentacoes" ON "public"."movimentacoes" FOR INSERT WITH CHECK ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "movimentacoes"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"])))))));



CREATE POLICY "tenant_empresa_insert_nf_entrada" ON "public"."nf_entrada" FOR INSERT WITH CHECK ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"])))))));



CREATE POLICY "tenant_empresa_select_fiscal_itens" ON "public"."fiscal_itens" FOR SELECT USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fiscal_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"])))))));



CREATE POLICY "tenant_empresa_select_movimentacoes" ON "public"."movimentacoes" FOR SELECT USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "movimentacoes"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"])))))));



CREATE POLICY "tenant_empresa_select_nf_entrada" ON "public"."nf_entrada" FOR SELECT USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"])))))));



CREATE POLICY "tenant_empresa_update_fiscal_itens" ON "public"."fiscal_itens" FOR UPDATE USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fiscal_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"]))))))) WITH CHECK ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fiscal_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"])))))));



CREATE POLICY "tenant_empresa_update_movimentacoes" ON "public"."movimentacoes" FOR UPDATE USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "movimentacoes"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))))) WITH CHECK ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "movimentacoes"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))));



CREATE POLICY "tenant_empresa_update_nf_entrada" ON "public"."nf_entrada" FOR UPDATE USING ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))))) WITH CHECK ((("empresa_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))));



CREATE POLICY "tenant_insert_fornecedores" ON "public"."fornecedores" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fornecedores"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_insert_itens" ON "public"."itens" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text"]))))));



CREATE POLICY "tenant_insert_nf_entrada_itens" ON "public"."nf_entrada_itens" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_insert_parametro_importacao_xml" ON "public"."parametro_importacao_xml" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "parametro_importacao_xml"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"])) AND ("tm"."role" = 'admin'::"text")))));



ALTER TABLE "public"."tenant_memberships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenant_memberships_delete" ON "public"."tenant_memberships" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "tenant_memberships"."tenant_id") AND ("tm"."role" = 'admin'::"text") AND ("tm"."status" = 'active'::"text")))));



CREATE POLICY "tenant_memberships_insert" ON "public"."tenant_memberships" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "tenant_memberships"."tenant_id") AND ("tm"."status" = 'active'::"text")))) OR ("auth"."uid"() = "user_id")));



CREATE POLICY "tenant_memberships_select" ON "public"."tenant_memberships" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "tenant_memberships_update" ON "public"."tenant_memberships" FOR UPDATE USING ((("user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "tenant_memberships"."tenant_id") AND ("tm"."role" = 'admin'::"text") AND ("tm"."status" = 'active'::"text"))))));



CREATE POLICY "tenant_select_fornecedores" ON "public"."fornecedores" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fornecedores"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_select_itens" ON "public"."itens" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_select_nf_entrada_itens" ON "public"."nf_entrada_itens" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_select_parametro_importacao_xml" ON "public"."parametro_importacao_xml" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "parametro_importacao_xml"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"])) AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_update_fornecedores" ON "public"."fornecedores" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fornecedores"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "fornecedores"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_update_itens" ON "public"."itens" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = ANY (ARRAY['admin'::"text", 'estoque'::"text", 'fiscal'::"text"]))))));



CREATE POLICY "tenant_update_nf_entrada_itens" ON "public"."nf_entrada_itens" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "nf_entrada_itens"."tenant_id") AND ("tm"."status" = 'active'::"text") AND ("tm"."role" = 'admin'::"text")))));



CREATE POLICY "tenant_update_parametro_importacao_xml" ON "public"."parametro_importacao_xml" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "parametro_importacao_xml"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"])) AND ("tm"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "auth"."uid"()) AND ("tm"."tenant_id" = "parametro_importacao_xml"."tenant_id") AND ("tm"."status" = ANY (ARRAY['active'::"text", 'ativo'::"text"])) AND ("tm"."role" = 'admin'::"text")))));



ALTER TABLE "public"."tenants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenants_select_own" ON "public"."tenants" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."tenant_id" = "tenants"."id") AND ("tm"."user_id" = "auth"."uid"()) AND ("tm"."status" = 'active'::"text")))));



ALTER TABLE "public"."tipos_horas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tipos_horas_delete" ON "public"."tipos_horas" FOR DELETE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('tipos_horas'::"text", 'delete'::"text")));



CREATE POLICY "tipos_horas_insert" ON "public"."tipos_horas" FOR INSERT TO "authenticated" WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('tipos_horas'::"text", 'create'::"text")));



CREATE POLICY "tipos_horas_select" ON "public"."tipos_horas" FOR SELECT TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND ("public"."can__legacy_40734"('tipos_horas'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'read'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'create'::"text") OR "public"."can__legacy_40734"('apontamentos'::"text", 'update'::"text"))));



CREATE POLICY "tipos_horas_update" ON "public"."tipos_horas" FOR UPDATE TO "authenticated" USING ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('tipos_horas'::"text", 'update'::"text"))) WITH CHECK ((("tenant_id" = "public"."current_tenant_id"()) AND "public"."can__legacy_40734"('tipos_horas'::"text", 'update'::"text")));



ALTER TABLE "public"."user_empresa_context" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_empresa_context_delete" ON "public"."user_empresa_context" FOR DELETE USING (false);



CREATE POLICY "user_empresa_context_insert" ON "public"."user_empresa_context" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "user_empresa_context_select" ON "public"."user_empresa_context" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_empresa_context_update" ON "public"."user_empresa_context" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "user_profiles_select_admin" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "user_profiles"."user_id") AND ("tm"."tenant_id" = "public"."current_tenant_id"())))) AND "public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text")));



CREATE POLICY "user_profiles_select_own" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_profiles_update_admin" ON "public"."user_profiles" FOR UPDATE TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "user_profiles"."user_id") AND ("tm"."tenant_id" = "public"."current_tenant_id"())))) AND "public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text"))) WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."tenant_memberships" "tm"
  WHERE (("tm"."user_id" = "user_profiles"."user_id") AND ("tm"."tenant_id" = "public"."current_tenant_id"())))) AND "public"."can__legacy_40734"('admin'::"text", 'manage_users'::"text")));



CREATE POLICY "user_profiles_update_own" ON "public"."user_profiles" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."user_tenant_context" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "utc_select_own" ON "public"."user_tenant_context" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "utc_update_own" ON "public"."user_tenant_context" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "utc_upsert_own" ON "public"."user_tenant_context" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "a" TO "authenticated";
GRANT USAGE ON SCHEMA "a" TO "service_role";



GRANT USAGE ON SCHEMA "c" TO "authenticated";
GRANT USAGE ON SCHEMA "c" TO "service_role";



GRANT USAGE ON SCHEMA "f" TO "authenticated";
GRANT USAGE ON SCHEMA "f" TO "service_role";



GRANT USAGE ON SCHEMA "m" TO "authenticated";
GRANT USAGE ON SCHEMA "m" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "r" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."current_empresa_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_empresa_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_empresa_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_empresa_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_tenant_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_tenant_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_tenant_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_tenant_id"() TO "service_role";






















































































































































GRANT ALL ON FUNCTION "f"."ajustar_valor_parcela_ap"("p_titulo_parcela_id" "uuid", "p_novo_valor" numeric, "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."atualizar_proximos_ap_recorrencia"("p_recorrencia_id" "uuid", "p_referencia_competencia" "date", "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."atualizar_titulo_emissao_date"("p_titulo_id" "uuid", "p_emissao_date" "date", "p_atualizar_competencia" boolean, "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."atualizar_titulo_emissao_date"("p_titulo_id" "uuid", "p_emissao_date" "date", "p_atualizar_competencia" boolean, "p_change_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "f"."criar_titulo_ap_manual"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."criar_titulo_ap_manual_v2"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_emissao_date" "date", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."criar_titulo_ap_manual_v2"("p_descricao" "text", "p_vencimento_date" "date", "p_valor" numeric, "p_fornecedor_id" integer, "p_motivo_compra_id" "uuid", "p_emissao_date" "date", "p_criar_recorrencia" boolean, "p_dia_vencimento" integer, "p_auto_copiar_valor" boolean, "p_change_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_imposto_apuracao_range"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_comp_ini" "date", "p_comp_fim" "date", "p_operacao" "text", "p_natureza" "text") TO "service_role";



REVOKE ALL ON FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_imposto_documentos_do_mes"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia" "date", "p_imposto" "text", "p_nat" "text", "p_operacao" "text") TO "service_role";



GRANT ALL ON FUNCTION "f"."fn_sync_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "f"."fn_sync_apuracao_irpj_csll"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_competencia_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "f"."gerar_ap_por_nf_entrada"("p_nf_entrada_id" bigint, "p_motivo_compra_id" "uuid", "p_parcelas_json" "jsonb") TO "authenticated";



GRANT ALL ON FUNCTION "f"."has_motivo_compra_access"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "f"."has_motivo_compra_access"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "f"."provisionar_ap_recorrencia"("p_recorrencia_id" "uuid", "p_meses_a_frente" integer, "p_change_reason" "text") TO "authenticated";



GRANT ALL ON FUNCTION "f"."registrar_recebimento_ar"("p_titulo_id" "uuid", "p_conta_bancaria_id" "uuid", "p_data_pagamento" "date", "p_forma_pagamento" "text", "p_valor" numeric, "p_observacoes" "text", "p_change_reason" "text") TO "authenticated";






GRANT ALL ON FUNCTION "m"."fn_orcamento_adicionar_conjunto"("p_orcamento_id" "uuid", "p_conjunto_id" "uuid", "p_quantidade" numeric) TO "authenticated";



GRANT ALL ON FUNCTION "m"."fn_orcamento_item_calcular"("p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_item_percent" numeric, "p_acrescimo_cond_percent" numeric, "p_desconto_global_percent" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "m"."fn_orcamento_item_calcular"("p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_item_percent" numeric, "p_acrescimo_cond_percent" numeric, "p_desconto_global_percent" numeric) TO "service_role";



GRANT ALL ON FUNCTION "m"."fn_orcamento_recalcular_totais"("p_orcamento_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "m"."fn_orcamento_recalcular_totais"("p_orcamento_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "m"."fn_orcamento_sync_itens"("p_orcamento_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "m"."fn_orcamento_sync_itens"("p_orcamento_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "m"."orcamento_build_codigo"("p_empresa_id" "uuid", "p_numero" integer, "p_emissao_date" "date") TO "authenticated";



GRANT ALL ON FUNCTION "m"."orcamento_build_codigo"("p_empresa_id" "uuid", "p_numero" integer, "p_versao" integer) TO "authenticated";
GRANT ALL ON FUNCTION "m"."orcamento_build_codigo"("p_empresa_id" "uuid", "p_numero" integer, "p_versao" integer) TO "service_role";



GRANT ALL ON FUNCTION "m"."orcamento_next_numero"("p_tenant" "uuid", "p_empresa" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "m"."orcamento_next_numero"("p_tenant" "uuid", "p_empresa" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "m"."trg_orcamento_au"() TO "authenticated";
GRANT ALL ON FUNCTION "m"."trg_orcamento_au"() TO "service_role";



GRANT ALL ON FUNCTION "m"."trg_orcamento_biu"() TO "authenticated";
GRANT ALL ON FUNCTION "m"."trg_orcamento_biu"() TO "service_role";



GRANT ALL ON FUNCTION "m"."trg_orcamento_item_aiud"() TO "authenticated";
GRANT ALL ON FUNCTION "m"."trg_orcamento_item_aiud"() TO "service_role";



GRANT ALL ON FUNCTION "m"."trg_orcamento_item_biu"() TO "authenticated";
GRANT ALL ON FUNCTION "m"."trg_orcamento_item_biu"() TO "service_role";



GRANT ALL ON FUNCTION "public"."a_is_empresa_member"("p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."a_is_empresa_member"("p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."a_is_empresa_member"("p_empresa_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."a_is_tenant_admin"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."a_is_tenant_admin"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."a_is_tenant_admin"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."a_is_tenant_role"("p_tenant_id" "uuid", "p_roles" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."a_is_tenant_role"("p_tenant_id" "uuid", "p_roles" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."a_is_tenant_role"("p_tenant_id" "uuid", "p_roles" "text"[]) TO "service_role";



GRANT ALL ON TABLE "public"."os_itens" TO "anon";
GRANT ALL ON TABLE "public"."os_itens" TO "authenticated";
GRANT ALL ON TABLE "public"."os_itens" TO "service_role";



GRANT ALL ON FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_os_item_baixa_imediata"("p_os_id" integer, "p_item_id" integer, "p_quantidade" numeric, "p_valor_unitario" numeric, "p_desconto_percentual" numeric, "p_desconto_valor" numeric, "p_baixa_estoque" boolean, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_can_manage_users"("p_tenant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_can_manage_users"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_can_manage_users"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_can_manage_users"("p_tenant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_finalize_invited_user"("p_tenant_id" "uuid", "p_auth_user_id" "uuid", "p_email" "text", "p_nome" "text", "p_telefone" "text", "p_tenant_papel" "text", "p_empresa_vinculos" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_finalize_invited_user"("p_tenant_id" "uuid", "p_auth_user_id" "uuid", "p_email" "text", "p_nome" "text", "p_telefone" "text", "p_tenant_papel" "text", "p_empresa_vinculos" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_finalize_invited_user"("p_tenant_id" "uuid", "p_auth_user_id" "uuid", "p_email" "text", "p_nome" "text", "p_telefone" "text", "p_tenant_papel" "text", "p_empresa_vinculos" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_finalize_invited_user"("p_tenant_id" "uuid", "p_auth_user_id" "uuid", "p_email" "text", "p_nome" "text", "p_telefone" "text", "p_tenant_papel" "text", "p_empresa_vinculos" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_users"("p_tenant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_users"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_users"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_users"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_merge_fornecedores"("p_tenant_id" "uuid", "p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint, "p_soft_delete" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_merge_fornecedores"("p_tenant_id" "uuid", "p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint, "p_soft_delete" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_merge_fornecedores"("p_tenant_id" "uuid", "p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint, "p_soft_delete" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_user_empresa"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_user_empresa"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_set_user_empresa"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_user_empresa"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_user_tenant_role"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_user_tenant_role"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_set_user_tenant_role"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_user_tenant_role"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_papel" "text", "p_ativo" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_user"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_nome" "text", "p_telefone" "text", "p_ativo" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_user"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_nome" "text", "p_telefone" "text", "p_ativo" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_update_user"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_nome" "text", "p_telefone" "text", "p_ativo" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_user"("p_tenant_id" "uuid", "p_usuario_id" "uuid", "p_nome" "text", "p_telefone" "text", "p_ativo" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_fiscal_regras_em_lote"("p_somente_sem_registro" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."apply_fiscal_regras_em_lote"("p_somente_sem_registro" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_fiscal_regras_em_lote"("p_somente_sem_registro" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_fiscal_regras_em_lote_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_somente_sem_registro" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_fiscal_regras_em_lote_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_somente_sem_registro" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."apply_fiscal_regras_em_lote_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_somente_sem_registro" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_fiscal_regras_em_lote_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_somente_sem_registro" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_fiscal_to_item"("p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."apply_fiscal_to_item"("p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_fiscal_to_item"("p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_fiscal_to_item_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_fiscal_to_item_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."apply_fiscal_to_item_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_fiscal_to_item_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_item_id" integer, "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_movimentacao_estoque"() TO "anon";
GRANT ALL ON FUNCTION "public"."apply_movimentacao_estoque"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_movimentacao_estoque"() TO "service_role";



GRANT ALL ON FUNCTION "public"."audit_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."audit_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."audit_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_assign_empresa_segau"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_assign_empresa_segau"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_assign_empresa_segau"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_set_context_on_login"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_set_context_on_login"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_set_context_on_login"() TO "service_role";



GRANT ALL ON FUNCTION "public"."block_movimentacoes_mutation"() TO "anon";
GRANT ALL ON FUNCTION "public"."block_movimentacoes_mutation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."block_movimentacoes_mutation"() TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_hh_lancamento"() TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_hh_lancamento"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_hh_lancamento"() TO "service_role";



GRANT ALL ON FUNCTION "public"."can"("p_resource" "text", "p_action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."can"("p_resource" "text", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can"("p_resource" "text", "p_action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."can"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can__legacy_40734"("p_resource" "text", "p_action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."can__legacy_40734"("p_resource" "text", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can__legacy_40734"("p_resource" "text", "p_action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."can__legacy_56548"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can__legacy_56548"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can__legacy_56548"("p_resource" "text", "p_action" "text", "p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_many"("p_pairs" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."can_many"("p_pairs" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_many"("p_pairs" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_many"("p_pairs" "public"."capability_pair"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."can_many"("p_pairs" "public"."capability_pair"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_many"("p_pairs" "public"."capability_pair"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."concluir_os"("os_id_param" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."concluir_os"("os_id_param" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."concluir_os"("os_id_param" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."confirmar_lancamento_contabil"("p_lancamento_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."confirmar_lancamento_contabil"("p_lancamento_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirmar_lancamento_contabil"("p_lancamento_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."criar_gestao_padrao_os"() TO "anon";
GRANT ALL ON FUNCTION "public"."criar_gestao_padrao_os"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."criar_gestao_padrao_os"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_auth_user_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_auth_user_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_auth_user_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_competencia_key"("p_data" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."current_competencia_key"("p_data" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_competencia_key"("p_data" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."current_empresa_id"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."current_empresa_id"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_empresa_id"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."current_empresa_id__by_tenant"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."current_empresa_id__by_tenant"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_empresa_id__by_tenant"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."debug_auth_context"() TO "anon";
GRANT ALL ON FUNCTION "public"."debug_auth_context"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."debug_auth_context"() TO "service_role";



GRANT ALL ON FUNCTION "public"."debug_jwt"() TO "anon";
GRANT ALL ON FUNCTION "public"."debug_jwt"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."debug_jwt"() TO "service_role";



GRANT ALL ON FUNCTION "public"."debug_me"() TO "anon";
GRANT ALL ON FUNCTION "public"."debug_me"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."debug_me"() TO "service_role";



GRANT ALL ON FUNCTION "public"."debug_membership"() TO "anon";
GRANT ALL ON FUNCTION "public"."debug_membership"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."debug_membership"() TO "service_role";



GRANT ALL ON FUNCTION "public"."debug_tenant"() TO "anon";
GRANT ALL ON FUNCTION "public"."debug_tenant"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."debug_tenant"() TO "service_role";



GRANT ALL ON FUNCTION "public"."default_empresa_id"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."default_empresa_id"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."default_empresa_id"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_competencia"("p_data" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_competencia"("p_data" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_competencia"("p_data" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_estoque_rows"("p_tenant_id" "uuid", "p_item_ids" integer[]) TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_estoque_rows"("p_tenant_id" "uuid", "p_item_ids" integer[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_estoque_rows"("p_tenant_id" "uuid", "p_item_ids" integer[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."estornar_lancamento_contabil"("p_lancamento_id" "uuid", "p_historico" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."estornar_lancamento_contabil"("p_lancamento_id" "uuid", "p_historico" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."estornar_lancamento_contabil"("p_lancamento_id" "uuid", "p_historico" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."estornar_movimentacao"("p_mov_id" integer, "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."estornar_movimentacao"("p_mov_id" integer, "p_motivo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."estornar_movimentacao"("p_mov_id" integer, "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."estornar_movimentacao"("p_mov_id" integer, "p_motivo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fechar_competencia"("p_ano" integer, "p_mes" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."fechar_competencia"("p_ano" integer, "p_mes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fechar_competencia"("p_ano" integer, "p_mes" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."fechar_competencia_admin"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_ano" integer, "p_mes" integer, "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fechar_competencia_admin"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_ano" integer, "p_mes" integer, "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fechar_competencia_admin"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_ano" integer, "p_mes" integer, "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fechar_competencia_admin"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_ano" integer, "p_mes" integer, "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_arrendamento_gerar_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_arrendamento_gerar_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_arrendamento_gerar_ap"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_contrato_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_atualiza_estoque_por_mov"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_atualiza_estoque_por_mov"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_atualiza_estoque_por_mov"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_calc_horas_2_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_calc_horas_2_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_calc_horas_2_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_calc_horas_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_calc_horas_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_calc_horas_periodos"("p_e1" time without time zone, "p_s1" time without time zone, "p_e2" time without time zone, "p_s2" time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_documento_key"("p_doc" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_documento_key"("p_doc" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_documento_key"("p_doc" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_ensure_titulo_ap_from_nf_entrada"("p_nf_entrada_id" bigint, "p_force_regen_parcelas" boolean, "p_parcelas_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_ensure_titulo_ap_from_nf_entrada"("p_nf_entrada_id" bigint, "p_force_regen_parcelas" boolean, "p_parcelas_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_ensure_titulo_ap_from_nf_entrada"("p_nf_entrada_id" bigint, "p_force_regen_parcelas" boolean, "p_parcelas_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_fix_nf_entrada_pos_import"("p_nf_entrada_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_fix_nf_entrada_pos_import"("p_nf_entrada_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_fix_nf_entrada_pos_import"("p_nf_entrada_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_fornecedor_upsert_por_documento"("p_tenant_id" "uuid", "p_nome" "text", "p_documento" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_fornecedor_upsert_por_documento"("p_tenant_id" "uuid", "p_nome" "text", "p_documento" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_fornecedor_upsert_por_documento"("p_tenant_id" "uuid", "p_nome" "text", "p_documento" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_hh_criar_apontamento"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_hh_criar_apontamento"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_hh_criar_apontamento"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_hh_delete_apontamento"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_hh_delete_apontamento"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_hh_delete_apontamento"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_hh_lancamentos_calc"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_hh_lancamentos_calc"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_hh_lancamentos_calc"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_hh_sync_apontamento"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_hh_sync_apontamento"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_hh_sync_apontamento"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_importacao_xml__itens_auto_cadastrar_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_importacao_xml__itens_auto_cadastrar_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_importacao_xml__itens_auto_cadastrar_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_importacao_xml__itens_vincular_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_importacao_xml__itens_vincular_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_importacao_xml__itens_vincular_finalidades"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_nf_entrada_sync_estoque_df"("p_nf_entrada_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_nf_entrada_sync_estoque_df"("p_nf_entrada_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_nf_entrada_sync_estoque_df"("p_nf_entrada_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_normalize_documento"("p_doc" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_normalize_documento"("p_doc" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_normalize_documento"("p_doc" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_ordens_servico_validate_hh"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_ordens_servico_validate_hh"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_ordens_servico_validate_hh"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_percentual_por_data"("p_data" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_percentual_por_data"("p_data" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_percentual_por_data"("p_data" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_regerar_parcelas_titulo_from_xml"("p_nf_entrada_id" bigint, "p_titulo_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_regerar_parcelas_titulo_from_xml"("p_nf_entrada_id" bigint, "p_titulo_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_regerar_parcelas_titulo_from_xml"("p_nf_entrada_id" bigint, "p_titulo_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_set_fator_aplicado"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_set_fator_aplicado"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_set_fator_aplicado"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_set_horas_from_periodos"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_set_horas_from_periodos"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_set_horas_from_periodos"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_validar_apontamento_horas"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_validar_apontamento_horas"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_validar_apontamento_horas"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_xml_strip_default_namespace"("p_xml_raw" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_xml_strip_default_namespace"("p_xml_raw" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_xml_strip_default_namespace"("p_xml_raw" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."gerar_relatorio_hh_os"("p_os_id" integer, "p_periodo_inicio" "date", "p_periodo_fim" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."gerar_relatorio_hh_os"("p_os_id" integer, "p_periodo_inicio" "date", "p_periodo_fim" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gerar_relatorio_hh_os"("p_os_id" integer, "p_periodo_inicio" "date", "p_periodo_fim" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_default_empresa_id"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_default_empresa_id"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_default_empresa_id"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_default_tenant_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_default_tenant_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_default_tenant_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_full_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_full_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_full_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_hh_tipo_id_for_tenant"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_hh_tipo_id_for_tenant"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_hh_tipo_id_for_tenant"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_active_tenant"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_active_tenant"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_active_tenant"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_permissions"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_permissions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_permissions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_permissions"("p_tenant_id" "uuid", "p_empresa_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_roles"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_roles"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_roles"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_permission"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_permission"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_permission"("p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."import_nf_entrada"("p_empresa_id" "uuid", "p_finalidade_contexto" "public"."item_finalidade", "p_fornecedor_id" bigint, "p_itens_json" "jsonb", "p_nf_json" "jsonb", "p_tenant_id" "uuid", "p_xml_raw" "text", "p_gerar_contas_pagar" boolean, "p_parcelas_json" "jsonb", "p_os_id" integer, "p_baixar_os" boolean, "p_motivo_compra_id" "uuid", "p_solicitante_usuario_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."import_nf_entrada"("p_empresa_id" "uuid", "p_finalidade_contexto" "public"."item_finalidade", "p_fornecedor_id" bigint, "p_itens_json" "jsonb", "p_nf_json" "jsonb", "p_tenant_id" "uuid", "p_xml_raw" "text", "p_gerar_contas_pagar" boolean, "p_parcelas_json" "jsonb", "p_os_id" integer, "p_baixar_os" boolean, "p_motivo_compra_id" "uuid", "p_solicitante_usuario_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."import_nf_entrada"("p_empresa_id" "uuid", "p_finalidade_contexto" "public"."item_finalidade", "p_fornecedor_id" bigint, "p_itens_json" "jsonb", "p_nf_json" "jsonb", "p_tenant_id" "uuid", "p_xml_raw" "text", "p_gerar_contas_pagar" boolean, "p_parcelas_json" "jsonb", "p_os_id" integer, "p_baixar_os" boolean, "p_motivo_compra_id" "uuid", "p_solicitante_usuario_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."import_nf_entrada_v2"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_chave_acesso" "text", "p_numero" "text", "p_serie" "text", "p_emissao_date" "date", "p_competencia_date" "date", "p_valor_total" numeric, "p_fornecedor_nome" "text", "p_fornecedor_documento" "text", "p_gerar_titulo" boolean, "p_vencimento_date" "date", "p_plano_contas_id" "uuid", "p_centro_custo_id" "uuid", "p_os_id" integer, "p_observacoes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."import_nf_entrada_v2"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_chave_acesso" "text", "p_numero" "text", "p_serie" "text", "p_emissao_date" "date", "p_competencia_date" "date", "p_valor_total" numeric, "p_fornecedor_nome" "text", "p_fornecedor_documento" "text", "p_gerar_titulo" boolean, "p_vencimento_date" "date", "p_plano_contas_id" "uuid", "p_centro_custo_id" "uuid", "p_os_id" integer, "p_observacoes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."import_nf_entrada_v2"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_chave_acesso" "text", "p_numero" "text", "p_serie" "text", "p_emissao_date" "date", "p_competencia_date" "date", "p_valor_total" numeric, "p_fornecedor_nome" "text", "p_fornecedor_documento" "text", "p_gerar_titulo" boolean, "p_vencimento_date" "date", "p_plano_contas_id" "uuid", "p_centro_custo_id" "uuid", "p_os_id" integer, "p_observacoes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."import_nfse_saida"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nfse_json" "jsonb", "p_xml_raw" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."import_nfse_saida"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nfse_json" "jsonb", "p_xml_raw" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."import_nfse_saida"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_nfse_json" "jsonb", "p_xml_raw" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."itens_resolver_por_codigo"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_codigo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."itens_resolver_por_codigo"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_codigo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."itens_resolver_por_codigo"("p_tenant_id" "uuid", "p_empresa_id" "uuid", "p_codigo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."jwt_claim"("claim" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."jwt_claim"("claim" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."jwt_claim"("claim" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."jwt_empresa_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."jwt_empresa_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."jwt_empresa_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."jwt_tenant_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."jwt_tenant_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."jwt_tenant_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."list_user_empresas"("p_tenant_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."list_user_empresas"("p_tenant_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_user_empresas"("p_tenant_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."list_user_empresas"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."list_user_empresas"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_user_empresas"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."merge_fornecedores"("p_keep_id" integer, "p_kill_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."merge_fornecedores"("p_keep_id" integer, "p_kill_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_fornecedores"("p_keep_id" integer, "p_kill_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."merge_fornecedores"("p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."merge_fornecedores"("p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_fornecedores"("p_keep_fornecedor_id" bigint, "p_merge_fornecedor_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_cnpj"("p" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_cnpj"("p" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_cnpj"("p" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_doc"("doc" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_doc"("doc" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_doc"("doc" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."os_sync_itens_from_nf_entrada"("p_nf_entrada_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."os_sync_itens_from_nf_entrada"("p_nf_entrada_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."os_sync_itens_from_nf_entrada"("p_nf_entrada_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."pick_fiscal_regra"("p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pick_fiscal_regra"("p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pick_fiscal_regra"("p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pick_fiscal_regra_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pick_fiscal_regra_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pick_fiscal_regra_admin"("p_tenant" "uuid", "p_empresa" "uuid", "p_ncm" "text", "p_cfop" "text", "p_cst_icms" "text", "p_cst_pis" "text", "p_cst_cofins" "text", "p_origem" smallint, "p_tipo_item" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_os_item_reverte_estoque"("p_os_item_id" integer, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_os_item_reverte_estoque"("p_os_item_id" integer, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_os_item_reverte_estoque"("p_os_item_id" integer, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_os_item_reverte_estoque"("p_os_item_id" integer, "p_realizado_por" "text", "p_motivo" "text", "p_empresa_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_current_empresa"("p_empresa_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_current_empresa"("p_empresa_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_current_empresa"("p_empresa_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_current_tenant"("p_tenant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_current_tenant"("p_tenant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_current_tenant"("p_tenant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_current_tenant"("p_tenant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" integer, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" integer, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" integer, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" bigint, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" bigint, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_fornecedor_import_defaults"("p_fornecedor_id" bigint, "p_finalidade" "public"."item_finalidade", "p_motivo_compra_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_tenant_id_colaborador_cliente_funcao"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_tenant_id_colaborador_cliente_funcao"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_tenant_id_colaborador_cliente_funcao"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."strip_zeros_esquerda"("p" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strip_zeros_esquerda"("p" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strip_zeros_esquerda"("p" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_nf_entrada_itens__enforce_item_finalidade_import"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_nf_entrada_itens__enforce_item_finalidade_import"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_nf_entrada_itens__enforce_item_finalidade_import"() TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_nf_entrada_itens__fill_descricao"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_nf_entrada_itens__fill_descricao"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_nf_entrada_itens__fill_descricao"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_block_nf_movimentacoes"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_block_nf_movimentacoes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_block_nf_movimentacoes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_fornecedores_force_gerar_cp"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_fornecedores_force_gerar_cp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_fornecedores_force_gerar_cp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_itens_normalizar_codigos"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_itens_normalizar_codigos"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_itens_normalizar_codigos"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_itens_sync_timestamps"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_itens_sync_timestamps"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_itens_sync_timestamps"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_nf_entrada_itens_sync_os_stmt"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_nf_entrada_itens_sync_os_stmt"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_nf_entrada_itens_sync_os_stmt"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_nf_entrada_sync_os_itens"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_nf_entrada_sync_os_itens"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_nf_entrada_sync_os_itens"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_cliente_hh_servicos_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_cliente_hh_servicos_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_cliente_hh_servicos_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_colaborador_cliente_funcao_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_colaborador_cliente_funcao_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_colaborador_cliente_funcao_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_apontamento_colaborador_contrato"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_apontamento_colaborador_contrato"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_apontamento_colaborador_contrato"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_hh_lancamento"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_hh_lancamento"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_hh_lancamento"() TO "service_role";












GRANT SELECT ON TABLE "a"."config_orcamento" TO "authenticated";
GRANT SELECT ON TABLE "a"."config_orcamento" TO "service_role";



GRANT SELECT,UPDATE ON TABLE "a"."usuario" TO "authenticated";
GRANT SELECT ON TABLE "a"."usuario" TO "service_role";



GRANT SELECT ON TABLE "a"."usuario_empresa" TO "authenticated";
GRANT SELECT ON TABLE "a"."usuario_empresa" TO "service_role";



GRANT SELECT ON TABLE "a"."usuario_tenant" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."condicao_pagamento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."conjunto" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."conjunto_item" TO "authenticated";



GRANT SELECT,INSERT,UPDATE ON TABLE "c"."empresa" TO "authenticated";



GRANT SELECT ON TABLE "c"."empresa_endereco" TO "authenticated";



GRANT SELECT ON TABLE "c"."empresa_fiscal" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_caixa" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_caixa_item" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_caixa_vinculo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_ferramenta" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_ferramenta_categoria" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_ferramenta_codigo_seq" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_ferramenta_sugestao_xml" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_ferramenta_unidade" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "c"."i_ferramenta_unidade_vinculo" TO "authenticated";



GRANT SELECT ON TABLE "c"."tenant" TO "authenticated";









GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."anexo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."ap_recorrencia" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."aprovacao_evento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."arrendamento_contrato" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."arrendamento_parcela" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."centro_custo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."conciliacao_bancaria" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."conciliacao_lancamento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."conta_bancaria" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_imposto" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_item" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_pendencia" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."documento_fiscal_xml" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."evento_financeiro" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."extrato_bancario" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."extrato_bancario_linha" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."fin_config" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."importacao_doc_log" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."imposto_retencao" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_ajuste" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_financeiro_config" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_regra_plano" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."irpj_csll_saldo_inicial" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."motivo_compra" TO "authenticated";
GRANT SELECT ON TABLE "f"."motivo_compra" TO "service_role";



GRANT ALL ON TABLE "public"."nf_entrada" TO "anon";
GRANT ALL ON TABLE "public"."nf_entrada" TO "authenticated";
GRANT ALL ON TABLE "public"."nf_entrada" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."nf_entrada" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."pagamento" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."pagamento_item" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."parametro_financeiro_empresa" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."parametro_irpj_csll_empresa" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."plano_contas" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo_aprovacao" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "f"."titulo_parcela" TO "authenticated";



GRANT ALL ON TABLE "public"."fornecedores" TO "anon";
GRANT ALL ON TABLE "public"."fornecedores" TO "authenticated";
GRANT ALL ON TABLE "public"."fornecedores" TO "service_role";



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



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "m"."orcamento" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "m"."orcamento" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "m"."orcamento_item" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "m"."orcamento_item" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "m"."orcamento_seq" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "m"."orcamento_seq" TO "service_role";



GRANT ALL ON TABLE "public"."apontamentos_horas" TO "anon";
GRANT ALL ON TABLE "public"."apontamentos_horas" TO "authenticated";
GRANT ALL ON TABLE "public"."apontamentos_horas" TO "service_role";



GRANT ALL ON TABLE "public"."audit_log" TO "anon";
GRANT ALL ON TABLE "public"."audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."audit_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."audit_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."audit_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."centros_custo" TO "anon";
GRANT ALL ON TABLE "public"."centros_custo" TO "authenticated";
GRANT ALL ON TABLE "public"."centros_custo" TO "service_role";



GRANT ALL ON TABLE "public"."cliente_hh_servicos" TO "anon";
GRANT ALL ON TABLE "public"."cliente_hh_servicos" TO "authenticated";
GRANT ALL ON TABLE "public"."cliente_hh_servicos" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cliente_hh_servicos_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cliente_hh_servicos_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cliente_hh_servicos_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cliente_hh_tabelas" TO "anon";
GRANT ALL ON TABLE "public"."cliente_hh_tabelas" TO "authenticated";
GRANT ALL ON TABLE "public"."cliente_hh_tabelas" TO "service_role";



GRANT ALL ON TABLE "public"."clientes" TO "anon";
GRANT ALL ON TABLE "public"."clientes" TO "authenticated";
GRANT ALL ON TABLE "public"."clientes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."clientes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."clientes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."clientes_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."colaborador_cliente_funcao" TO "anon";
GRANT ALL ON TABLE "public"."colaborador_cliente_funcao" TO "authenticated";
GRANT ALL ON TABLE "public"."colaborador_cliente_funcao" TO "service_role";



GRANT ALL ON SEQUENCE "public"."colaborador_cliente_funcao_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."colaborador_cliente_funcao_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."colaborador_cliente_funcao_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."colaborador_funcao_hh" TO "anon";
GRANT ALL ON TABLE "public"."colaborador_funcao_hh" TO "authenticated";
GRANT ALL ON TABLE "public"."colaborador_funcao_hh" TO "service_role";



GRANT ALL ON SEQUENCE "public"."colaborador_funcao_hh_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."colaborador_funcao_hh_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."colaborador_funcao_hh_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."colaborador_taxas" TO "anon";
GRANT ALL ON TABLE "public"."colaborador_taxas" TO "authenticated";
GRANT ALL ON TABLE "public"."colaborador_taxas" TO "service_role";



GRANT ALL ON TABLE "public"."colaboradores" TO "anon";
GRANT ALL ON TABLE "public"."colaboradores" TO "authenticated";
GRANT ALL ON TABLE "public"."colaboradores" TO "service_role";



GRANT ALL ON TABLE "public"."competencias" TO "anon";
GRANT ALL ON TABLE "public"."competencias" TO "authenticated";
GRANT ALL ON TABLE "public"."competencias" TO "service_role";



GRANT ALL ON TABLE "public"."contas_pagar_titulos" TO "anon";
GRANT ALL ON TABLE "public"."contas_pagar_titulos" TO "authenticated";
GRANT ALL ON TABLE "public"."contas_pagar_titulos" TO "service_role";



GRANT ALL ON TABLE "public"."contas_pagar_titulos_agendamentos" TO "anon";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_agendamentos" TO "authenticated";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_agendamentos" TO "service_role";



GRANT ALL ON TABLE "public"."contas_pagar_titulos_aprovacoes" TO "anon";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_aprovacoes" TO "authenticated";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_aprovacoes" TO "service_role";



GRANT ALL ON TABLE "public"."contas_pagar_titulos_parcelas" TO "anon";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_parcelas" TO "authenticated";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_parcelas" TO "service_role";



GRANT ALL ON TABLE "public"."contas_pagar_titulos_rateios" TO "anon";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_rateios" TO "authenticated";
GRANT ALL ON TABLE "public"."contas_pagar_titulos_rateios" TO "service_role";



GRANT ALL ON TABLE "public"."empresa_memberships" TO "anon";
GRANT ALL ON TABLE "public"."empresa_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."empresa_memberships" TO "service_role";



GRANT ALL ON SEQUENCE "public"."empresa_memberships_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."empresa_memberships_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."empresa_memberships_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."empresas" TO "anon";
GRANT ALL ON TABLE "public"."empresas" TO "authenticated";
GRANT ALL ON TABLE "public"."empresas" TO "service_role";



GRANT ALL ON TABLE "public"."estoque" TO "anon";
GRANT ALL ON TABLE "public"."estoque" TO "authenticated";
GRANT ALL ON TABLE "public"."estoque" TO "service_role";



GRANT ALL ON SEQUENCE "public"."estoque_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."estoque_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."estoque_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."feriados" TO "anon";
GRANT ALL ON TABLE "public"."feriados" TO "authenticated";
GRANT ALL ON TABLE "public"."feriados" TO "service_role";



GRANT ALL ON TABLE "public"."fiscal_itens" TO "anon";
GRANT ALL ON TABLE "public"."fiscal_itens" TO "authenticated";
GRANT ALL ON TABLE "public"."fiscal_itens" TO "service_role";



GRANT ALL ON SEQUENCE "public"."fiscal_itens_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."fiscal_itens_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."fiscal_itens_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."fiscal_regras" TO "anon";
GRANT ALL ON TABLE "public"."fiscal_regras" TO "authenticated";
GRANT ALL ON TABLE "public"."fiscal_regras" TO "service_role";



GRANT ALL ON SEQUENCE "public"."fornecedores_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."fornecedores_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."fornecedores_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."hh_especialidades" TO "anon";
GRANT ALL ON TABLE "public"."hh_especialidades" TO "authenticated";
GRANT ALL ON TABLE "public"."hh_especialidades" TO "service_role";



GRANT ALL ON SEQUENCE "public"."hh_especialidades_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."hh_especialidades_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."hh_especialidades_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."hh_lancamentos" TO "anon";
GRANT ALL ON TABLE "public"."hh_lancamentos" TO "authenticated";
GRANT ALL ON TABLE "public"."hh_lancamentos" TO "service_role";



GRANT ALL ON SEQUENCE "public"."hh_lancamentos_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."hh_lancamentos_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."hh_lancamentos_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."hh_tipos_mapping" TO "anon";
GRANT ALL ON TABLE "public"."hh_tipos_mapping" TO "authenticated";
GRANT ALL ON TABLE "public"."hh_tipos_mapping" TO "service_role";



GRANT ALL ON SEQUENCE "public"."hh_tipos_mapping_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."hh_tipos_mapping_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."hh_tipos_mapping_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."horas_trabalhadas" TO "anon";
GRANT ALL ON TABLE "public"."horas_trabalhadas" TO "authenticated";
GRANT ALL ON TABLE "public"."horas_trabalhadas" TO "service_role";



GRANT ALL ON SEQUENCE "public"."horas_trabalhadas_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."horas_trabalhadas_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."horas_trabalhadas_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."itens" TO "anon";
GRANT ALL ON TABLE "public"."itens" TO "authenticated";
GRANT ALL ON TABLE "public"."itens" TO "service_role";



GRANT ALL ON SEQUENCE "public"."itens_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."itens_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."itens_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."itens_merge_log" TO "anon";
GRANT ALL ON TABLE "public"."itens_merge_log" TO "authenticated";
GRANT ALL ON TABLE "public"."itens_merge_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."itens_merge_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."itens_merge_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."itens_merge_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."lancamentos_contabeis" TO "anon";
GRANT ALL ON TABLE "public"."lancamentos_contabeis" TO "authenticated";
GRANT ALL ON TABLE "public"."lancamentos_contabeis" TO "service_role";



GRANT ALL ON TABLE "public"."lancamentos_contabeis_itens" TO "anon";
GRANT ALL ON TABLE "public"."lancamentos_contabeis_itens" TO "authenticated";
GRANT ALL ON TABLE "public"."lancamentos_contabeis_itens" TO "service_role";



GRANT ALL ON TABLE "public"."membership_roles" TO "anon";
GRANT ALL ON TABLE "public"."membership_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."membership_roles" TO "service_role";



GRANT ALL ON TABLE "public"."movimentacoes" TO "anon";
GRANT ALL ON TABLE "public"."movimentacoes" TO "authenticated";
GRANT ALL ON TABLE "public"."movimentacoes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."movimentacoes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."movimentacoes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."movimentacoes_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."nf_entrada_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."nf_entrada_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."nf_entrada_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."nf_entrada_itens" TO "anon";
GRANT ALL ON TABLE "public"."nf_entrada_itens" TO "authenticated";
GRANT ALL ON TABLE "public"."nf_entrada_itens" TO "service_role";



GRANT ALL ON SEQUENCE "public"."nf_entrada_itens_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."nf_entrada_itens_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."nf_entrada_itens_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ordens_servico" TO "anon";
GRANT ALL ON TABLE "public"."ordens_servico" TO "authenticated";
GRANT ALL ON TABLE "public"."ordens_servico" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ordens_servico_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ordens_servico_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ordens_servico_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ordens_servico_os_num_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ordens_servico_os_num_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ordens_servico_os_num_seq" TO "service_role";



GRANT ALL ON TABLE "public"."os_gestao_itens" TO "anon";
GRANT ALL ON TABLE "public"."os_gestao_itens" TO "authenticated";
GRANT ALL ON TABLE "public"."os_gestao_itens" TO "service_role";



GRANT ALL ON SEQUENCE "public"."os_gestao_itens_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."os_gestao_itens_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."os_gestao_itens_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."os_itens_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."os_itens_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."os_itens_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."parametro_importacao_xml" TO "anon";
GRANT ALL ON TABLE "public"."parametro_importacao_xml" TO "authenticated";
GRANT ALL ON TABLE "public"."parametro_importacao_xml" TO "service_role";



GRANT ALL ON TABLE "public"."permissions" TO "anon";
GRANT ALL ON TABLE "public"."permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."permissions" TO "service_role";



GRANT ALL ON TABLE "public"."plano_contas" TO "anon";
GRANT ALL ON TABLE "public"."plano_contas" TO "authenticated";
GRANT ALL ON TABLE "public"."plano_contas" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."profissionais" TO "anon";
GRANT ALL ON TABLE "public"."profissionais" TO "authenticated";
GRANT ALL ON TABLE "public"."profissionais" TO "service_role";



GRANT ALL ON SEQUENCE "public"."profissionais_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."profissionais_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."profissionais_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."r_itens_ativos" TO "anon";
GRANT ALL ON TABLE "public"."r_itens_ativos" TO "authenticated";
GRANT ALL ON TABLE "public"."r_itens_ativos" TO "service_role";



GRANT ALL ON TABLE "public"."role_access_rules" TO "anon";
GRANT ALL ON TABLE "public"."role_access_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."role_access_rules" TO "service_role";



GRANT ALL ON TABLE "public"."role_permissions" TO "anon";
GRANT ALL ON TABLE "public"."role_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."role_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."roles" TO "anon";
GRANT ALL ON TABLE "public"."roles" TO "authenticated";
GRANT ALL ON TABLE "public"."roles" TO "service_role";



GRANT ALL ON TABLE "public"."tenant_memberships" TO "anon";
GRANT ALL ON TABLE "public"."tenant_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."tenant_memberships" TO "service_role";



GRANT ALL ON TABLE "public"."tenants" TO "anon";
GRANT ALL ON TABLE "public"."tenants" TO "authenticated";
GRANT ALL ON TABLE "public"."tenants" TO "service_role";



GRANT ALL ON TABLE "public"."tipos_horas" TO "anon";
GRANT ALL ON TABLE "public"."tipos_horas" TO "authenticated";
GRANT ALL ON TABLE "public"."tipos_horas" TO "service_role";



GRANT ALL ON TABLE "public"."user_empresa_context" TO "anon";
GRANT ALL ON TABLE "public"."user_empresa_context" TO "authenticated";
GRANT ALL ON TABLE "public"."user_empresa_context" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."user_tenant_context" TO "anon";
GRANT ALL ON TABLE "public"."user_tenant_context" TO "authenticated";
GRANT ALL ON TABLE "public"."user_tenant_context" TO "service_role";



GRANT ALL ON TABLE "public"."v_creditos_por_periodo" TO "anon";
GRANT ALL ON TABLE "public"."v_creditos_por_periodo" TO "authenticated";
GRANT ALL ON TABLE "public"."v_creditos_por_periodo" TO "service_role";



GRANT ALL ON TABLE "public"."v_item_ultimo_custo" TO "anon";
GRANT ALL ON TABLE "public"."v_item_ultimo_custo" TO "authenticated";
GRANT ALL ON TABLE "public"."v_item_ultimo_custo" TO "service_role";



GRANT ALL ON TABLE "public"."v_estoque_custo_atual" TO "anon";
GRANT ALL ON TABLE "public"."v_estoque_custo_atual" TO "authenticated";
GRANT ALL ON TABLE "public"."v_estoque_custo_atual" TO "service_role";



GRANT ALL ON TABLE "public"."v_lancamentos_contabeis_balance" TO "anon";
GRANT ALL ON TABLE "public"."v_lancamentos_contabeis_balance" TO "authenticated";
GRANT ALL ON TABLE "public"."v_lancamentos_contabeis_balance" TO "service_role";



GRANT ALL ON TABLE "public"."v_user_permissions" TO "anon";
GRANT ALL ON TABLE "public"."v_user_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."v_user_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."vw_apontamentos_horas_custo" TO "anon";
GRANT ALL ON TABLE "public"."vw_apontamentos_horas_custo" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_apontamentos_horas_custo" TO "service_role";



GRANT ALL ON TABLE "public"."vw_colaboradores_taxa_atual" TO "anon";
GRANT ALL ON TABLE "public"."vw_colaboradores_taxa_atual" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_colaboradores_taxa_atual" TO "service_role";



GRANT ALL ON TABLE "public"."vw_creditos_mensais" TO "anon";
GRANT ALL ON TABLE "public"."vw_creditos_mensais" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_creditos_mensais" TO "service_role";



GRANT ALL ON TABLE "public"."vw_custo_mao_obra_os" TO "anon";
GRANT ALL ON TABLE "public"."vw_custo_mao_obra_os" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_custo_mao_obra_os" TO "service_role";



GRANT ALL ON TABLE "public"."vw_hh_total_os" TO "anon";
GRANT ALL ON TABLE "public"."vw_hh_total_os" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_hh_total_os" TO "service_role";



GRANT SELECT ON TABLE "r"."dre_plano_excluido" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_apuracao_impostos_mes" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_dre_mensal_plano" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_dre_mensal_plano_filtrado" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_dre_mensal_filtrado" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_apuracao_irpj_csll_mensal_comp2" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_apuracao_irpj_csll_mensal" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_apuracao_irpj_csll_anual" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_apuracao_irpj_csll_anual_comp" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_apuracao_irpj_csll_anual_comp2" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_dre_mensal" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_apuracao_irpj_csll_mensal_comp" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_documentos_pendentes_xml" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_guardiao_impostos_docs" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_i_caixa_custo" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_itens_ativos" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_motivo_compra_rank" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_nfse_iss_conferencia" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_orcamento_catalogo_busca" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_orcamento_itens" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_orcamento_lista" TO "authenticated";



GRANT SELECT ON TABLE "r"."r_pendencias_xml_entrada" TO "authenticated";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "a" GRANT SELECT,USAGE ON SEQUENCES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "a" GRANT SELECT ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "a" GRANT SELECT ON TABLES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "c" GRANT SELECT,USAGE ON SEQUENCES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "c" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "f" GRANT SELECT,USAGE ON SEQUENCES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "f" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "m" GRANT ALL ON FUNCTIONS TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "m" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "r" GRANT SELECT ON TABLES TO "authenticated";




























drop extension if exists "pg_net";

alter table "public"."itens" drop constraint "itens_tipo_check";

alter table "public"."ordens_servico" drop constraint "ordens_servico_status_check";

alter table "public"."itens" add constraint "itens_tipo_check" CHECK (((tipo)::text = ANY ((ARRAY['produto'::character varying, 'servico'::character varying, 'despesa'::character varying])::text[]))) not valid;

alter table "public"."itens" validate constraint "itens_tipo_check";

alter table "public"."ordens_servico" add constraint "ordens_servico_status_check" CHECK (((status)::text = ANY ((ARRAY['aberta'::character varying, 'em_andamento'::character varying, 'concluida'::character varying, 'cancelada'::character varying])::text[]))) not valid;

alter table "public"."ordens_servico" validate constraint "ordens_servico_status_check";

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


CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_auth_user_created_assign_empresa AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.auto_assign_empresa_segau();

CREATE TRIGGER on_auth_user_login_set_context AFTER UPDATE ON auth.users FOR EACH ROW WHEN ((old.last_sign_in_at IS DISTINCT FROM new.last_sign_in_at)) EXECUTE FUNCTION public.auto_set_context_on_login();


