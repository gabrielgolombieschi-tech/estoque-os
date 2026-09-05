begin;

-- O cliente le o pipeline para montar as telas e receber realtime, mas toda
-- mutacao precisa atravessar as RPCs que validam tenant, empresa e estado.
revoke insert, update, delete on table f.solicitacao_faturamento from authenticated;
revoke insert, update, delete on table f.solicitacao_item from authenticated;
revoke insert, update, delete on table f.documento_fiscal_emissao from authenticated;
grant select on table f.solicitacao_faturamento to authenticated;
grant select on table f.solicitacao_item to authenticated;
grant select on table f.documento_fiscal_emissao to authenticated;
grant select, insert, update, delete on table f.solicitacao_faturamento to service_role;
grant select, insert, update, delete on table f.solicitacao_item to service_role;
grant select, insert, update, delete on table f.documento_fiscal_emissao to service_role;

-- A composicao legada continua sendo a entrada autenticada para criar o
-- rascunho de HOM. PRODUCAO nasce exclusivamente no preparar+claim atomico,
-- depois da HOM autorizada e da liberacao auditada.
create or replace function f.fn_faturar_documento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS',
  p_itens_quantidades jsonb default null,
  p_linhas_livres jsonb default null
)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  referencia_externa text,
  status text,
  criado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
begin
  if upper(btrim(coalesce(p_ambiente, ''))) <> 'HOMOLOGACAO' then
    raise exception using
      errcode = '42501',
      message = 'A composicao inicial cria somente rascunho em HOMOLOGACAO; PRODUCAO exige promocao fiscal auditada.';
  end if;
  if public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  then
    raise exception using errcode = '42501', message = 'Sem permissao para faturar nesta empresa.';
  end if;

  return query
  select x.documento_fiscal_id, x.solicitacao_id, x.referencia_externa, x.status, x.criado
  from f.fn_faturar_documento_impl(
    p_tenant_id, p_empresa_id, p_ov_id, p_os_item_ids,
    p_documento_fiscal_id, 'HOMOLOGACAO', p_natureza_operacao,
    p_itens_quantidades, p_linhas_livres
  ) x;
end;
$function$;

comment on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb) is
  'Wrapper SECURITY DEFINER cria composicao somente em HOMOLOGACAO; PRODUCAO e exclusiva do claim fiscal service-only.';
revoke all on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb)
  from public, anon;
grant execute on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb)
  to authenticated, service_role;

-- Mesmo RPCs SECURITY DEFINER conservam o JWT original. Esta barreira impede
-- que conferencia/congelamento (ou um mutador futuro) reescrevam snapshots,
-- itens ou totais depois que houve claim/tentativa, e tambem depois que PROD
-- passou a existir. Uma HOM RASCUNHO nunca tentada permanece editavel.
create or replace function f.fn_nfe_bloquear_material_pos_claim()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
  v_old_solicitacao_id uuid;
  v_new_solicitacao_id uuid;
  v_old_tenant_id uuid;
  v_new_tenant_id uuid;
  v_old_empresa_id uuid;
  v_new_empresa_id uuid;
begin
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_table_name = 'solicitacao_faturamento' then
    if tg_op <> 'INSERT' then
      v_old_solicitacao_id := old.id;
      v_old_tenant_id := old.tenant_id;
      v_old_empresa_id := old.empresa_id;
    end if;
    if tg_op <> 'DELETE' then
      v_new_solicitacao_id := new.id;
      v_new_tenant_id := new.tenant_id;
      v_new_empresa_id := new.empresa_id;
    end if;
  else
    if tg_op <> 'INSERT' then
      v_old_solicitacao_id := old.solicitacao_id;
      v_old_tenant_id := old.tenant_id;
      v_old_empresa_id := old.empresa_id;
    end if;
    if tg_op <> 'DELETE' then
      v_new_solicitacao_id := new.solicitacao_id;
      v_new_tenant_id := new.tenant_id;
      v_new_empresa_id := new.empresa_id;
    end if;
  end if;

  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where (
      (dfe.tenant_id = v_old_tenant_id and dfe.empresa_id = v_old_empresa_id and dfe.solicitacao_id = v_old_solicitacao_id)
      or
      (dfe.tenant_id = v_new_tenant_id and dfe.empresa_id = v_new_empresa_id and dfe.solicitacao_id = v_new_solicitacao_id)
    )
      and (
        dfe.ambiente <> 'HOMOLOGACAO'
        or dfe.status <> 'RASCUNHO'
        or coalesce(dfe.tentativa_count, 0) > 0
        or dfe.payload_enviado is not null
        or dfe.enviado_em is not null
        or dfe.ultima_tentativa_em is not null
        or dfe.callback_recebido_em is not null
        or dfe.reconciliado_em is not null
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'Material fiscal congelado: abandone/cancele pelo fluxo auditado e crie nova solicitacao.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

comment on function f.fn_nfe_bloquear_material_pos_claim() is
  'Bloqueia mutacao authenticated de solicitacao/itens apos qualquer claim/tentativa ou existencia de PRODUCAO, inclusive via SECURITY DEFINER.';
revoke all on function f.fn_nfe_bloquear_material_pos_claim()
  from public, anon, authenticated, service_role;

drop trigger if exists aaa_nfe_bloquear_material_pos_claim_sf on f.solicitacao_faturamento;
create trigger aaa_nfe_bloquear_material_pos_claim_sf
before update or delete on f.solicitacao_faturamento
for each row execute function f.fn_nfe_bloquear_material_pos_claim();

drop trigger if exists aaa_nfe_bloquear_material_pos_claim_si on f.solicitacao_item;
create trigger aaa_nfe_bloquear_material_pos_claim_si
before insert or update or delete on f.solicitacao_item
for each row execute function f.fn_nfe_bloquear_material_pos_claim();

-- f.documento_fiscal e f.documento_fiscal_item tambem atendem NFS-e e outros
-- fluxos legados que ainda fazem CRUD autenticado, portanto nao e seguro
-- revogar DML das tabelas inteiras. Estas guardas isolam somente NF-e modelo
-- 55 e documentos que ja entraram no pipeline controlado por emissao/RPC.
create or replace function f.fn_nfe_bloquear_documento_dml_direto()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_vinculado boolean := false;
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
begin
  -- RPC legado SECURITY DEFINER conserva o JWT authenticated; por isso a
  -- guarda nao confia apenas em current_user.
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op <> 'INSERT' then
    select exists (
      select 1
      from f.documento_fiscal_emissao dfe
      where dfe.tenant_id = old.tenant_id
        and dfe.empresa_id = old.empresa_id
        and dfe.documento_fiscal_id = old.id
    ) into v_vinculado;
    if v_vinculado then
      -- Unica transicao authenticated permitida: a RPC de descarte ja marcou
      -- uma HOM nunca tentada como CANCELADA, nao existe PROD e nenhum outro
      -- dado do documento foi alterado. Este trigger roda primeiro para que
      -- updated_at/updated_by automaticos sejam aplicados somente depois.
      if tg_op = 'UPDATE'
         and old.nfe_status = 'RASCUNHO'
         and new.nfe_status = 'CANCELADA'
         and (to_jsonb(new) - array['nfe_status','updated_at']::text[])
             is not distinct from
             (to_jsonb(old) - array['nfe_status','updated_at']::text[])
         and exists (
           select 1
           from f.documento_fiscal_emissao hom
           where hom.tenant_id = old.tenant_id
             and hom.empresa_id = old.empresa_id
             and hom.documento_fiscal_id = old.id
             and hom.ambiente = 'HOMOLOGACAO'
             and hom.status = 'CANCELADA'
             and hom.tentativa_count = 0
             and hom.payload_enviado is null
             and hom.enviado_em is null
             and hom.ultima_tentativa_em is null
         )
         and not exists (
           select 1
           from f.documento_fiscal_emissao prod
           where prod.tenant_id = old.tenant_id
             and prod.empresa_id = old.empresa_id
             and prod.solicitacao_id = (
               select hom.solicitacao_id
               from f.documento_fiscal_emissao hom
               where hom.tenant_id = old.tenant_id
                 and hom.empresa_id = old.empresa_id
                 and hom.documento_fiscal_id = old.id
                 and hom.ambiente = 'HOMOLOGACAO'
               limit 1
             )
             and prod.ambiente = 'PRODUCAO'
         ) then
        return new;
      end if;
      raise exception using
        errcode = '42501',
        message = 'Documento fiscal gerenciado pelo pipeline de NF-e so pode ser alterado ou excluido por RPC fiscal.';
    end if;
  end if;

  if tg_op <> 'DELETE'
     and upper(btrim(coalesce(new.operacao, ''))) = 'SAIDA'
     and btrim(coalesce(new.modelo, '')) = '55'
     and upper(btrim(coalesce(new.nfe_status, ''))) = 'EMITIDA' then
    raise exception using
      errcode = '42501',
      message = 'NF-e de saida modelo 55 nao pode ser marcada EMITIDA diretamente; use o pipeline fiscal autorizado.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

comment on function f.fn_nfe_bloquear_documento_dml_direto() is
  'Impede authenticated de forjar NF-e SAIDA/55 EMITIDA e de alterar/excluir documento ja vinculado ao pipeline; RPCs fiscais SECURITY DEFINER permanecem permitidas.';
revoke all on function f.fn_nfe_bloquear_documento_dml_direto()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_nfe_bloquear_documento_dml_direto on f.documento_fiscal;
drop trigger if exists aaa_nfe_bloquear_documento_dml_direto on f.documento_fiscal;
create trigger aaa_nfe_bloquear_documento_dml_direto
before insert or update or delete on f.documento_fiscal
for each row execute function f.fn_nfe_bloquear_documento_dml_direto();

create or replace function f.fn_nfe_bloquear_item_dml_direto()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_vinculado boolean := false;
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
begin
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op <> 'INSERT' then
    select exists (
      select 1
      from f.documento_fiscal_emissao dfe
      where dfe.tenant_id = old.tenant_id
        and dfe.empresa_id = old.empresa_id
        and dfe.documento_fiscal_id = old.documento_fiscal_id
    ) into v_vinculado;
  end if;
  if not v_vinculado and tg_op <> 'DELETE' then
    select exists (
      select 1
      from f.documento_fiscal_emissao dfe
      where dfe.tenant_id = new.tenant_id
        and dfe.empresa_id = new.empresa_id
        and dfe.documento_fiscal_id = new.documento_fiscal_id
    ) into v_vinculado;
  end if;
  if v_vinculado then
    raise exception using
      errcode = '42501',
      message = 'Item de documento gerenciado pelo pipeline de NF-e so pode ser alterado por RPC fiscal.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

comment on function f.fn_nfe_bloquear_item_dml_direto() is
  'Impede INSERT/UPDATE/DELETE autenticado de itens quando o documento esta vinculado a documento_fiscal_emissao no mesmo tenant/empresa.';
revoke all on function f.fn_nfe_bloquear_item_dml_direto()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_nfe_bloquear_item_dml_direto on f.documento_fiscal_item;
create trigger trg_nfe_bloquear_item_dml_direto
before insert or update or delete on f.documento_fiscal_item
for each row execute function f.fn_nfe_bloquear_item_dml_direto();

create or replace function f.fn_nfe_bloquear_evidencia_dml_direto()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_tenant_id uuid;
  v_documento_fiscal_id uuid;
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
begin
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    v_tenant_id := new.tenant_id;
    v_documento_fiscal_id := new.documento_fiscal_id;
  else
    v_tenant_id := old.tenant_id;
    v_documento_fiscal_id := old.documento_fiscal_id;
  end if;

  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    join f.documento_fiscal df
      on df.tenant_id = dfe.tenant_id
     and df.empresa_id = dfe.empresa_id
     and df.id = dfe.documento_fiscal_id
    where dfe.tenant_id = v_tenant_id
      and dfe.documento_fiscal_id = v_documento_fiscal_id
  ) then
    raise exception using
      errcode = '42501',
      message = format('%s de NF-e gerenciada so pode ser alterado por RPC fiscal.', tg_table_name);
  end if;

  -- UPDATE que tenta mover uma linha de outro documento para um gerenciado.
  if tg_op = 'UPDATE' and exists (
    select 1
    from f.documento_fiscal_emissao dfe
    join f.documento_fiscal df
      on df.tenant_id = dfe.tenant_id
     and df.empresa_id = dfe.empresa_id
     and df.id = dfe.documento_fiscal_id
    where dfe.tenant_id = new.tenant_id
      and dfe.documento_fiscal_id = new.documento_fiscal_id
  ) then
    raise exception using
      errcode = '42501',
      message = format('%s nao pode ser movido para uma NF-e gerenciada fora do pipeline.', tg_table_name);
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

comment on function f.fn_nfe_bloquear_evidencia_dml_direto() is
  'Protege XML e impostos vinculados a documento_fiscal_emissao contra DML authenticated, inclusive por RPC legado SECURITY DEFINER.';
revoke all on function f.fn_nfe_bloquear_evidencia_dml_direto()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_nfe_bloquear_xml_dml_direto on f.documento_fiscal_xml;
create trigger trg_nfe_bloquear_xml_dml_direto
before insert or update or delete on f.documento_fiscal_xml
for each row execute function f.fn_nfe_bloquear_evidencia_dml_direto();

drop trigger if exists trg_nfe_bloquear_imposto_dml_direto on f.documento_fiscal_imposto;
create trigger trg_nfe_bloquear_imposto_dml_direto
before insert or update or delete on f.documento_fiscal_imposto
for each row execute function f.fn_nfe_bloquear_evidencia_dml_direto();

create or replace function f.fn_nfe_validar_evento_entrega()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
begin
  if new.tipo not in ('EMAIL', 'DOWNLOAD') then return new; end if;
  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = new.tenant_id
    and dfe.empresa_id = new.empresa_id
    and dfe.documento_fiscal_id = new.documento_fiscal_id;
  if not found then return new; end if;

  if new.tipo = 'EMAIL' and v_emissao.ambiente <> 'PRODUCAO' then
    raise exception using errcode = '55000',
      message = 'EMAIL fiscal so pode ser registrado para NF-e em PRODUCAO.';
  end if;
  if v_emissao.ambiente = 'PRODUCAO' and (
    v_emissao.status <> 'AUTORIZADA'
    or nullif(btrim(v_emissao.xml_path), '') is null
    or nullif(btrim(v_emissao.danfe_path), '') is null
    or not exists (
      select 1 from f.documento_fiscal_xml dfx
      where dfx.tenant_id = v_emissao.tenant_id
        and dfx.documento_fiscal_id = v_emissao.documento_fiscal_id
        and dfx.deleted_at is null
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Entrega de NF-e em producao exige AUTORIZADA com XML e DANFE arquivados.';
  end if;
  return new;
end;
$function$;

comment on function f.fn_nfe_validar_evento_entrega() is
  'Bloqueia EMAIL de HOM e exige PROD AUTORIZADA com XML/DANFE antes de registrar entrega/download.';
revoke all on function f.fn_nfe_validar_evento_entrega()
  from public, anon, authenticated, service_role;
drop trigger if exists aaa_nfe_validar_evento_entrega on f.documento_fiscal_evento;
create trigger aaa_nfe_validar_evento_entrega
before insert on f.documento_fiscal_evento
for each row execute function f.fn_nfe_validar_evento_entrega();

create or replace function f.fn_nfe_bloquear_titulo_dml_direto()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
  v_old_gerenciado boolean := false;
  v_new_gerenciado boolean := false;
  v_new_autorizado boolean := false;
  v_documento_cliente_id integer;
  v_documento_valor_total numeric;
begin
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op <> 'INSERT' and old.documento_fiscal_id is not null then
    select exists (
      select 1 from f.documento_fiscal_emissao dfe
      where dfe.tenant_id = old.tenant_id
        and dfe.empresa_id = old.empresa_id
        and dfe.documento_fiscal_id = old.documento_fiscal_id
    ) into v_old_gerenciado;
  end if;
  if tg_op <> 'DELETE' and new.documento_fiscal_id is not null then
    select exists (
      select 1 from f.documento_fiscal_emissao dfe
      where dfe.tenant_id = new.tenant_id
        and dfe.empresa_id = new.empresa_id
        and dfe.documento_fiscal_id = new.documento_fiscal_id
    ), exists (
      select 1
      from f.documento_fiscal_emissao dfe
      join f.documento_fiscal df
        on df.tenant_id = dfe.tenant_id
       and df.empresa_id = dfe.empresa_id
       and df.id = dfe.documento_fiscal_id
      where dfe.tenant_id = new.tenant_id
        and dfe.empresa_id = new.empresa_id
        and dfe.documento_fiscal_id = new.documento_fiscal_id
        and dfe.ambiente = 'PRODUCAO'
        and dfe.status = 'AUTORIZADA'
        and df.operacao = 'SAIDA'
        and df.modelo = '55'
        and df.nfe_status = 'EMITIDA'
        and df.deleted_at is null
    ) into v_new_gerenciado, v_new_autorizado;
  end if;

  if tg_op = 'DELETE' and v_old_gerenciado then
    raise exception using errcode = '42501', message = 'Titulo de NF-e gerenciada nao pode ser excluido diretamente.';
  end if;
  if tg_op = 'UPDATE' and v_old_gerenciado
     and (
       new.documento_fiscal_id is distinct from old.documento_fiscal_id
       or new.tenant_id is distinct from old.tenant_id
       or new.empresa_id is distinct from old.empresa_id
       or new.tipo is distinct from old.tipo
       or new.origem is distinct from old.origem
       or new.cliente_id is distinct from old.cliente_id
       or new.valor_total is distinct from old.valor_total
       or new.deleted_at is distinct from old.deleted_at
     ) then
    raise exception using errcode = '42501', message = 'Identidade e valor do titulo de NF-e gerenciada sao imutaveis.';
  end if;
  if v_new_gerenciado and not v_new_autorizado then
    raise exception using
      errcode = '42501',
      message = 'Contas a Receber so pode ser vinculado a NF-e PROD AUTORIZADA com documento EMITIDA.';
  end if;
  if v_new_gerenciado then
    select df.cliente_id, df.valor_total
      into v_documento_cliente_id, v_documento_valor_total
    from f.documento_fiscal df
    where df.tenant_id = new.tenant_id
      and df.empresa_id = new.empresa_id
      and df.id = new.documento_fiscal_id
      and df.deleted_at is null;

    if new.tipo is distinct from 'AR'
       or new.origem is distinct from 'FATURAMENTO'
       or new.cliente_id is distinct from v_documento_cliente_id
       or new.valor_total is distinct from v_documento_valor_total
       or new.deleted_at is not null then
      raise exception using
        errcode = '42501',
        message = 'Titulo da NF-e deve ser AR/FATURAMENTO ativo, com cliente e valor identicos ao documento autorizado.';
    end if;

    -- Serializa inclusoes concorrentes; o indice existente nao e UNIQUE e um
    -- indice global afetaria NFS-e/documentos legados fora deste pipeline.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'nfe-ar:' || new.tenant_id::text || ':' || new.empresa_id::text || ':' || new.documento_fiscal_id::text,
        0
      )
    );
    if exists (
      select 1
      from f.titulo t
      where t.tenant_id = new.tenant_id
        and t.empresa_id = new.empresa_id
        and t.documento_fiscal_id = new.documento_fiscal_id
        and t.tipo = 'AR'
        and t.deleted_at is null
        and (tg_op <> 'UPDATE' or t.id <> new.id)
    ) then
      raise exception using
        errcode = '23505',
        message = 'Ja existe um titulo AR ativo para esta NF-e gerenciada.';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

comment on function f.fn_nfe_bloquear_titulo_dml_direto() is
  'Exige AR/FATURAMENTO unico e ativo, com cliente/valor do documento PROD autorizado, e congela sua identidade; NFS-e e documentos sem dfe permanecem compativeis.';
revoke all on function f.fn_nfe_bloquear_titulo_dml_direto()
  from public, anon, authenticated, service_role;

drop trigger if exists aaa_nfe_bloquear_titulo_dml_direto on f.titulo;
create trigger aaa_nfe_bloquear_titulo_dml_direto
before insert or update or delete on f.titulo
for each row execute function f.fn_nfe_bloquear_titulo_dml_direto();

-- Conserva a assinatura publica usada pelas telas, mas encapsula a rotina
-- legada para impedir que SECURITY DEFINER contorne a guarda fiscal.
alter function f.gerar_titulo_ar_do_documento(uuid, date, uuid, uuid, integer, text)
  rename to gerar_titulo_ar_do_documento_legado_antes_pipeline_nfe;
revoke all on function f.gerar_titulo_ar_do_documento_legado_antes_pipeline_nfe(uuid, date, uuid, uuid, integer, text)
  from public, anon, authenticated, service_role;

create function f.gerar_titulo_ar_do_documento(
  p_documento_fiscal_id uuid,
  p_vencimento_date date,
  p_plano_contas_id uuid,
  p_centro_custo_id uuid default null,
  p_os_id integer default null,
  p_descricao text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_df f.documento_fiscal%rowtype;
begin
  select df.* into v_df
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Documento fiscal nao encontrado.';
  end if;
  if not f.has_finance_access(v_df.tenant_id, v_df.empresa_id) then
    raise exception using errcode = '42501', message = 'Sem permissao financeira para gerar Contas a Receber.';
  end if;
  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_df.tenant_id
      and dfe.empresa_id = v_df.empresa_id
      and dfe.documento_fiscal_id = v_df.id
  ) and not exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_df.tenant_id
      and dfe.empresa_id = v_df.empresa_id
      and dfe.documento_fiscal_id = v_df.id
      and dfe.ambiente = 'PRODUCAO'
      and dfe.status = 'AUTORIZADA'
      and v_df.operacao = 'SAIDA'
      and v_df.modelo = '55'
      and v_df.nfe_status = 'EMITIDA'
  ) then
    raise exception using
      errcode = '55000',
      message = 'AR bloqueado: documento do pipeline precisa ser NF-e PROD AUTORIZADA e EMITIDA.';
  end if;

  return f.gerar_titulo_ar_do_documento_legado_antes_pipeline_nfe(
    p_documento_fiscal_id, p_vencimento_date, p_plano_contas_id,
    p_centro_custo_id, p_os_id, p_descricao
  );
end;
$function$;

comment on function f.gerar_titulo_ar_do_documento(uuid, date, uuid, uuid, integer, text) is
  'Wrapper compativel: documentos gerenciados so geram AR depois de PROD AUTORIZADA/EMITIDA; demais fluxos mantem a rotina legada.';
revoke all on function f.gerar_titulo_ar_do_documento(uuid, date, uuid, uuid, integer, text)
  from public, anon;
grant execute on function f.gerar_titulo_ar_do_documento(uuid, date, uuid, uuid, integer, text)
  to authenticated, service_role;

create or replace function f.fn_nfe_producao_estado(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_claim_homologacao_id uuid;
  v_claim_contexto_hash text;
begin
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a emissao de producao.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'PRODUCAO'
    and dfe.status <> 'CANCELADA';

  if not found then
    return jsonb_build_object(
      'existe', false,
      'tenant_id', v_sf.tenant_id,
      'empresa_id', v_sf.empresa_id,
      'solicitacao_id', v_sf.id
    );
  end if;

  select nullif(ev.resposta->>'homologacao_documento_fiscal_id', '')::uuid,
         ev.resposta->>'contexto_hash'
    into v_claim_homologacao_id, v_claim_contexto_hash
  from f.documento_fiscal_evento ev
  where ev.tenant_id = v_emissao.tenant_id
    and ev.empresa_id = v_emissao.empresa_id
    and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
    and ev.tipo = 'ENVIO'
    and coalesce((ev.resposta->>'claim_duravel')::boolean, false)
    and ev.resposta ? 'homologacao_documento_fiscal_id'
    and ev.resposta ? 'contexto_hash'
  order by ev.created_at, ev.id
  limit 1;

  return jsonb_build_object(
    'existe', true,
    'tenant_id', v_emissao.tenant_id,
    'empresa_id', v_emissao.empresa_id,
    'solicitacao_id', v_emissao.solicitacao_id,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status,
    'tentativa_count', v_emissao.tentativa_count,
    'homologacao_documento_fiscal_id', v_claim_homologacao_id,
    'contexto_hash', v_claim_contexto_hash,
    'payload_congelado', v_emissao.payload_enviado is not null,
    'confirmacao_nome_destinatario', v_emissao.payload_enviado->>'nome_destinatario',
    'confirmacao_tipo_documento_destinatario', case
      when nullif(v_emissao.payload_enviado->>'cnpj_destinatario', '') is not null then 'CNPJ'
      when nullif(v_emissao.payload_enviado->>'cpf_destinatario', '') is not null then 'CPF'
      else null
    end,
    'confirmacao_documento_destinatario', coalesce(
      nullif(v_emissao.payload_enviado->>'cnpj_destinatario', ''),
      nullif(v_emissao.payload_enviado->>'cpf_destinatario', '')
    ),
    'confirmacao_valor_total', v_emissao.payload_enviado->'valor_total',
    'claim_recente', (
      v_emissao.status = 'ENVIANDO'
      and v_emissao.ultima_tentativa_em >= now() - interval '2 minutes'
    ),
    'houve_claim', (
      v_emissao.status = 'ENVIANDO'
      or v_emissao.tentativa_count > 0
      or v_emissao.payload_enviado is not null
      or v_emissao.enviado_em is not null
    )
  );
end;
$function$;

comment on function f.fn_nfe_producao_estado(uuid) is
  'Informa, no escopo autenticado, se a solicitacao ja possui emissao de producao que precisa ser retomada/reconciliada.';
revoke all on function f.fn_nfe_producao_estado(uuid) from public, anon;
grant execute on function f.fn_nfe_producao_estado(uuid) to authenticated, service_role;

create or replace function f.fn_nfe_homologacao_estado(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
begin
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a emissao de homologacao.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.status <> 'CANCELADA';
  if not found then
    return jsonb_build_object('existe', false, 'tenant_id', v_sf.tenant_id,
      'empresa_id', v_sf.empresa_id, 'solicitacao_id', v_sf.id);
  end if;
  return jsonb_build_object(
    'existe', true, 'tenant_id', v_emissao.tenant_id,
    'empresa_id', v_emissao.empresa_id, 'solicitacao_id', v_emissao.solicitacao_id,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status
  );
end;
$function$;

comment on function f.fn_nfe_homologacao_estado(uuid) is
  'Localiza HOM ativa no escopo autenticado sem criar documento, inclusive para abandono auditado de rejeicao.';
revoke all on function f.fn_nfe_homologacao_estado(uuid) from public, anon;
grant execute on function f.fn_nfe_homologacao_estado(uuid) to authenticated, service_role;

-- Material canonico usado no compare-and-set entre o preflight da Edge e a
-- transacao que cria/retoma PROD. Campos de estado alterados pela propria
-- preparacao (status/updated_at) ficam de fora; todos os dados que alimentam
-- payload, documento, itens, totais e a HOM autorizada ficam dentro.
create or replace function f.fn_nfe_producao_contexto_material(
  p_solicitacao_id uuid,
  p_homologacao_documento_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select jsonb_build_object(
    'tenant_id', sf.tenant_id,
    'empresa_id', sf.empresa_id,
    'solicitacao_id', sf.id,
    'solicitacao', jsonb_build_object(
      'cliente_id', sf.cliente_id,
      'pedido_cliente', sf.pedido_cliente,
      'natureza_operacao', sf.natureza_operacao,
      'finalidade_emissao', sf.finalidade_emissao,
      'consumidor_final', sf.consumidor_final,
      'presenca_comprador', sf.presenca_comprador,
      'modalidade_frete', sf.modalidade_frete,
      'valor_frete', sf.valor_frete,
      'valor_seguro', sf.valor_seguro,
      'valor_outras_despesas', sf.valor_outras_despesas,
      'destino_uf_confirmada', sf.destino_uf_confirmada,
      'revisao_fiscal_confirmada_em', sf.revisao_fiscal_confirmada_em,
      'snapshot_cadastro_em', sf.snapshot_cadastro_em,
      'emitente_snapshot', sf.emitente_snapshot,
      'destinatario_snapshot', sf.destinatario_snapshot,
      'operacao_snapshot', sf.operacao_snapshot
    ),
    'homologacao', jsonb_build_object(
      'documento_fiscal_id', hom.documento_fiscal_id,
      'status', hom.status,
      'payload_enviado', hom.payload_enviado,
      'chave_acesso', hom.chave_acesso,
      'protocolo', hom.protocolo,
      'autorizado_em', hom.autorizado_em
    ),
    'documento_homologacao', to_jsonb(df) - 'created_at' - 'updated_at',
    'itens_solicitacao', coalesce((
      select jsonb_agg(to_jsonb(si) - 'created_at' - 'updated_at' order by si.ordem, si.id)
      from f.solicitacao_item si
      where si.tenant_id = sf.tenant_id
        and si.empresa_id = sf.empresa_id
        and si.solicitacao_id = sf.id
    ), '[]'::jsonb),
    'itens_homologacao', coalesce((
      select jsonb_agg(to_jsonb(dfi) - 'created_at' - 'updated_at' order by dfi.item_n, dfi.id)
      from f.documento_fiscal_item dfi
      where dfi.tenant_id = sf.tenant_id
        and dfi.empresa_id = sf.empresa_id
        and dfi.documento_fiscal_id = hom.documento_fiscal_id
        and dfi.deleted_at is null
    ), '[]'::jsonb)
  )
  from f.solicitacao_faturamento sf
  join f.documento_fiscal_emissao hom
    on hom.tenant_id = sf.tenant_id
   and hom.empresa_id = sf.empresa_id
   and hom.solicitacao_id = sf.id
   and hom.documento_fiscal_id = p_homologacao_documento_id
   and hom.ambiente = 'HOMOLOGACAO'
  join f.documento_fiscal df
    on df.tenant_id = hom.tenant_id
   and df.empresa_id = hom.empresa_id
   and df.id = hom.documento_fiscal_id
  where sf.id = p_solicitacao_id;
$function$;

revoke all on function f.fn_nfe_producao_contexto_material(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function f.fn_nfe_producao_preflight(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_prontidao jsonb;
  v_homologacao_documento_id uuid;
  v_contexto jsonb;
  v_material jsonb;
begin
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para executar o preflight de producao.';
  end if;

  v_prontidao := f.fn_nfe_producao_pronta(p_solicitacao_id);
  if not coalesce((v_prontidao->>'pronta')::boolean, false) then
    raise exception using errcode = 'P0001', message = coalesce(v_prontidao->>'motivo', 'Producao bloqueada no preflight.');
  end if;
  v_homologacao_documento_id := nullif(v_prontidao->>'homologacao_documento_fiscal_id', '')::uuid;
  v_contexto := f.fn_nfe_contexto_emissao(v_homologacao_documento_id);
  v_material := f.fn_nfe_producao_contexto_material(p_solicitacao_id, v_homologacao_documento_id);
  if v_contexto is null or v_material is null then
    raise exception using errcode = 'P0002', message = 'Contexto homologado nao encontrado para o preflight.';
  end if;

  return jsonb_build_object(
    'tenant_id', v_sf.tenant_id,
    'empresa_id', v_sf.empresa_id,
    'solicitacao_id', v_sf.id,
    'homologacao_documento_fiscal_id', v_homologacao_documento_id,
    'contexto_hash', encode(extensions.digest(convert_to(v_material::text, 'utf8'), 'sha256'), 'hex'),
    'contexto', v_contexto
  );
end;
$function$;

comment on function f.fn_nfe_producao_preflight(uuid) is
  'Entrega contexto HOM e hash canonico autenticado; o claim recomputa o hash sob locks para impedir TOCTOU.';
revoke all on function f.fn_nfe_producao_preflight(uuid) from public, anon;
grant execute on function f.fn_nfe_producao_preflight(uuid) to authenticated, service_role;

-- Uma emissao existente e devolvida antes de certificado/perfil/snapshot. Isso
-- permite consultar a Focus e reconciliar um POST incerto mesmo que um gate
-- mutavel tenha sido desabilitado depois do envio.
create or replace function f.fn_nfe_preparar_documento_solicitacao_producao(p_solicitacao_id uuid)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  referencia_externa text,
  status text,
  criado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_existente f.documento_fiscal_emissao%rowtype;
  v_documento_id uuid := gen_random_uuid();
  v_referencia text;
  v_total_produtos numeric(15,2);
  v_total_desconto numeric(15,2);
  v_total_nota numeric(15,2);
  v_os_id integer;
  v_prontidao jsonb;
  v_perfil_id uuid;
  v_origem record;
begin
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para emitir esta solicitacao em producao.';
  end if;

  select dfe.* into v_existente
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'PRODUCAO'
  for update;

  if found then
    if v_existente.status = 'CANCELADA' then
      raise exception using errcode = '55000', message = 'A emissao de producao desta solicitacao esta cancelada e exige tratamento fiscal proprio.';
    end if;
    return query select
      v_existente.documento_fiscal_id,
      v_existente.solicitacao_id,
      v_existente.referencia_externa,
      v_existente.status,
      false;
    return;
  end if;

  if not exists (
    select 1
    from f.documento_fiscal_emissao hom
    where hom.tenant_id = v_sf.tenant_id
      and hom.empresa_id = v_sf.empresa_id
      and hom.solicitacao_id = v_sf.id
      and hom.ambiente = 'HOMOLOGACAO'
      and hom.status = 'AUTORIZADA'
  ) then
    raise exception using errcode = '22023', message = 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.';
  end if;

  for v_origem in
    select distinct si.origem_id::integer as origem_id
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id ~ '^[0-9]+$'
    order by si.origem_id::integer
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      format('faturamento-parcial:%s:%s:%s', v_sf.tenant_id, v_sf.empresa_id, v_origem.origem_id),
      0
    ));
  end loop;

  v_referencia := 'NFEP-' || v_sf.id;
  perform pg_advisory_xact_lock(hashtextextended(v_referencia, 0));

  v_prontidao := f.fn_nfe_producao_pronta(v_sf.id);
  if not coalesce((v_prontidao->>'pronta')::boolean, false) then
    raise exception using errcode = 'P0001', message = coalesce(v_prontidao->>'motivo', 'Producao bloqueada.');
  end if;
  v_perfil_id := nullif(v_prontidao->>'perfil_operacao_id', '')::uuid;

  if exists (
    with atual as (
      select
        si.origem_id::integer as os_id,
        si.origem_item_id::integer as os_item_id,
        sum(si.quantidade) as quantidade
      from f.solicitacao_item si
      where si.tenant_id = v_sf.tenant_id
        and si.empresa_id = v_sf.empresa_id
        and si.solicitacao_id = v_sf.id
        and si.origem_tipo in ('OS', 'OV')
        and si.origem_id ~ '^[0-9]+$'
        and si.origem_item_id ~ '^[0-9]+$'
      group by si.origem_id::integer, si.origem_item_id::integer
    ), outros as (
      select
        si.origem_id::integer as os_id,
        si.origem_item_id::integer as os_item_id,
        sum(si.quantidade) as quantidade
      from f.solicitacao_item si
      join f.solicitacao_faturamento sf
        on sf.tenant_id = si.tenant_id
       and sf.empresa_id = si.empresa_id
       and sf.id = si.solicitacao_id
      where si.tenant_id = v_sf.tenant_id
        and si.empresa_id = v_sf.empresa_id
        and si.solicitacao_id <> v_sf.id
        and si.origem_tipo in ('OS', 'OV')
        and si.origem_id ~ '^[0-9]+$'
        and si.origem_item_id ~ '^[0-9]+$'
        and sf.status <> 'CANCELADA'
      group by si.origem_id::integer, si.origem_item_id::integer
    )
    select 1
    from atual a
    left join public.os_itens oi
      on oi.tenant_id = v_sf.tenant_id
     and oi.empresa_id = v_sf.empresa_id
     and oi.os_id = a.os_id
     and oi.id = a.os_item_id
    left join outros o
      on o.os_id = a.os_id
     and o.os_item_id = a.os_item_id
    where oi.id is null
       or a.quantidade > greatest(oi.quantidade - coalesce(o.quantidade, 0), 0)
  ) then
    raise exception using
      errcode = '22023',
      message = 'O saldo da OS/OV mudou depois da homologacao. Cancele ou ajuste as solicitacoes concorrentes antes de produzir.';
  end if;

  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA', 'EMITIDA') then
    raise exception using errcode = '22023', message = 'Solicitacao nao esta disponivel para emissao em producao.';
  end if;

  update f.solicitacao_faturamento sf
  set perfil_operacao_id = v_perfil_id,
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  select
    round(coalesce(sum(si.quantidade * si.valor_unitario), 0), 2),
    round(coalesce(sum(si.valor_desconto), 0), 2),
    round(coalesce(sum(si.quantidade * si.valor_unitario - si.valor_desconto), 0), 2)
      + coalesce(v_sf.valor_frete, 0)
      + coalesce(v_sf.valor_seguro, 0)
      + coalesce(v_sf.valor_outras_despesas, 0),
    min(case when si.origem_tipo in ('OS', 'OV') and si.origem_id ~ '^[0-9]+$' then si.origem_id::integer end)
  into v_total_produtos, v_total_desconto, v_total_nota, v_os_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if not exists (
    select 1
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
  ) then
    raise exception using errcode = '22023', message = 'Solicitacao sem itens.';
  end if;

  insert into f.documento_fiscal (
    id, tenant_id, empresa_id, chave_acesso, modelo, emissao_date,
    valor_total, valor_produtos, valor_frete, valor_seguro, valor_desconto, valor_outros,
    operacao, natureza, cliente_id, os_id_import, nfe_status, origem
  ) values (
    v_documento_id, v_sf.tenant_id, v_sf.empresa_id, 'PENDENTE:' || v_referencia, '55', current_date,
    v_total_nota, v_total_produtos, v_sf.valor_frete, v_sf.valor_seguro, v_total_desconto, v_sf.valor_outras_despesas,
    'SAIDA', 'PRODUTO', v_sf.cliente_id, v_os_id, 'RASCUNHO', 'EMITIDO'
  );

  insert into f.documento_fiscal_item (
    tenant_id, empresa_id, documento_fiscal_id, item_n, item_tipo,
    codigo, descricao, ncm, cfop, quantidade, unidade, valor_unitario,
    valor_total, item_id
  )
  select
    si.tenant_id, si.empresa_id, v_documento_id, si.ordem, 'PRODUTO',
    si.codigo_produto, si.descricao, si.ncm, si.cfop, si.quantidade, si.unidade, si.valor_unitario,
    round(si.quantidade * si.valor_unitario - si.valor_desconto, 2), si.item_id
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
  order by si.ordem, si.id;

  insert into f.documento_fiscal_emissao (
    documento_fiscal_id, solicitacao_id, tenant_id, empresa_id,
    referencia_externa, ambiente, status
  ) values (
    v_documento_id, v_sf.id, v_sf.tenant_id, v_sf.empresa_id,
    v_referencia, 'PRODUCAO', 'RASCUNHO'
  );

  update f.solicitacao_faturamento sf
  set status = 'APROVADA', updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  return query select v_documento_id, v_sf.id, v_referencia, 'RASCUNHO'::text, true;
end;
$function$;

comment on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid) is
  'Retoma uma emissao PROD existente antes de gates mutaveis; para a primeira emissao valida homologacao, perfil, snapshot, certificado e saldo sob lock.';
revoke all on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_preparar_documento_solicitacao_producao(uuid)
  to service_role;

create or replace function f.fn_nfe_producao_preparar_e_claimar(
  p_solicitacao_id uuid,
  p_payload jsonb,
  p_homologacao_documento_id uuid,
  p_contexto_hash text,
  p_reconciliacao_confirmada boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_preparada record;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_prontidao jsonb;
  v_tinha_claim boolean;
  v_material jsonb;
  v_contexto_hash_atual text;
  v_contexto_hash_primeiro_claim text;
  v_homologacao_primeiro_claim uuid;
  v_homologacao_payload jsonb;
  v_sf f.solicitacao_faturamento%rowtype;
  v_produtos numeric;
  v_desconto numeric;
  v_desconto_fonte numeric;
  v_frete numeric;
  v_seguro numeric;
  v_outros numeric;
  v_total numeric;
  v_ipi numeric;
  v_total_esperado numeric;
  v_itens_payload integer;
  v_itens_solicitacao integer;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o envio de producao.';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'O payload fiscal de producao deve ser um objeto JSON.';
  end if;
  if p_homologacao_documento_id is null
     or coalesce(p_contexto_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Documento HOM e hash do preflight sao obrigatorios.';
  end if;

  -- A chamada aninhada participa desta mesma transacao: se qualquer gate ou
  -- claim falhar, uma emissao criada agora e integralmente revertida.
  select * into v_preparada
  from f.fn_nfe_preparar_documento_solicitacao_producao(p_solicitacao_id);

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = (select sf.tenant_id from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id)
    and dfe.empresa_id = (select sf.empresa_id from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id)
    and dfe.solicitacao_id = p_solicitacao_id
    and dfe.documento_fiscal_id = v_preparada.documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO'
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de producao preparada nao encontrada no mesmo escopo.';
  end if;
  if v_emissao.status in ('AUTORIZADA', 'PROCESSANDO') then
    return jsonb_build_object(
      'deve_enviar', false,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status,
      'tentativa_count', v_emissao.tentativa_count,
      'payload', v_emissao.payload_enviado
    );
  end if;

  v_tinha_claim := v_emissao.status = 'ENVIANDO'
    or v_emissao.tentativa_count > 0
    or v_emissao.payload_enviado is not null
    or v_emissao.enviado_em is not null;

  -- Compare-and-set: um concorrente que perdeu a corrida nao consulta nem
  -- reenvia enquanto o vencedor ainda pode estar entre o COMMIT e o POST.
  if v_emissao.status = 'ENVIANDO'
     and v_emissao.ultima_tentativa_em >= now() - interval '2 minutes' then
    return jsonb_build_object(
      'deve_enviar', false,
      'aguardar', true,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status,
      'tentativa_count', v_emissao.tentativa_count,
      'payload', v_emissao.payload_enviado
    );
  end if;
  if v_tinha_claim and not coalesce(p_reconciliacao_confirmada, false) then
    raise exception using
      errcode = '55000',
      message = 'A referencia ja possui claim; consulte a Focus antes de qualquer novo POST.';
  end if;

  -- Congela todas as fontes que alimentam o contexto/payload. Se uma escrita
  -- venceu antes destes locks, o hash abaixo detecta; se vier depois, aguarda.
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  perform 1
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
  order by si.id
  for update;
  perform 1
  from f.documento_fiscal_emissao hom
  where hom.tenant_id = v_sf.tenant_id
    and hom.empresa_id = v_sf.empresa_id
    and hom.solicitacao_id = v_sf.id
    and hom.documento_fiscal_id = p_homologacao_documento_id
    and hom.ambiente = 'HOMOLOGACAO'
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'A homologacao do preflight nao pertence a solicitacao e escopo atuais.';
  end if;
  perform 1
  from f.documento_fiscal df
  where df.tenant_id = v_sf.tenant_id
    and df.empresa_id = v_sf.empresa_id
    and df.id = p_homologacao_documento_id
  for update;
  perform 1
  from f.documento_fiscal_item dfi
  where dfi.tenant_id = v_sf.tenant_id
    and dfi.empresa_id = v_sf.empresa_id
    and dfi.documento_fiscal_id = p_homologacao_documento_id
    and dfi.deleted_at is null
  order by dfi.id
  for update;
  perform po.id
  from f.perfil_operacao po
  where po.tenant_id = v_sf.tenant_id
    and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
    and exists (
      select 1 from f.solicitacao_item si
      where si.tenant_id = v_sf.tenant_id
        and si.empresa_id = v_sf.empresa_id
        and si.solicitacao_id = v_sf.id
        and si.perfil_operacao_id = po.id
    )
  order by po.id
  for update;
  perform ef.id
  from c.empresa_fiscal ef
  where ef.empresa_id = v_sf.empresa_id
    and ef.deleted_at is null
  order by ef.id
  for update;

  select nullif(ev.resposta->>'homologacao_documento_fiscal_id', '')::uuid,
         ev.resposta->>'contexto_hash'
    into v_homologacao_primeiro_claim, v_contexto_hash_primeiro_claim
  from f.documento_fiscal_evento ev
  where ev.tenant_id = v_emissao.tenant_id
    and ev.empresa_id = v_emissao.empresa_id
    and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
    and ev.tipo = 'ENVIO'
    and coalesce((ev.resposta->>'claim_duravel')::boolean, false)
    and ev.resposta ? 'contexto_hash'
  order by ev.created_at, ev.id
  limit 1;

  if v_tinha_claim and v_contexto_hash_primeiro_claim is not null then
    -- O primeiro claim capturou a liberacao exata. Uma liberacao posterior do
    -- mesmo perfil para outra solicitacao nao pode encalhar a reconciliacao
    -- desta referencia; continuam obrigatorios HOM autorizada, certificado,
    -- ausencia de cancelamento e o material fiscal originalmente congelado.
    if v_homologacao_primeiro_claim is distinct from p_homologacao_documento_id
       or v_contexto_hash_primeiro_claim is distinct from lower(p_contexto_hash) then
      raise exception using errcode = '40001', message = 'Retry diverge da homologacao/hash capturados no primeiro claim de producao.';
    end if;
    if v_sf.status = 'CANCELADA'
       or not exists (
         select 1
         from f.documento_fiscal_emissao hom
         where hom.tenant_id = v_sf.tenant_id
           and hom.empresa_id = v_sf.empresa_id
           and hom.solicitacao_id = v_sf.id
           and hom.documento_fiscal_id = p_homologacao_documento_id
           and hom.ambiente = 'HOMOLOGACAO'
           and hom.status = 'AUTORIZADA'
       )
       or coalesce((
         select ev.status = 'ENVIANDO'
         from f.documento_fiscal_evento ev
         where ev.tenant_id = v_sf.tenant_id
           and ev.empresa_id = v_sf.empresa_id
           and ev.documento_fiscal_id = p_homologacao_documento_id
           and ev.tipo = 'CANCELAMENTO'
         order by ev.created_at desc, ev.id desc
         limit 1
       ), false)
       or not exists (
         select 1
         from c.empresa e
         join c.empresa_fiscal ef
           on ef.empresa_id = e.id
          and ef.deleted_at is null
         where e.tenant_id = v_sf.tenant_id
           and e.id = v_sf.empresa_id
           and e.deleted_at is null
           and ef.certificado_validade_em >= current_date
       ) then
      raise exception using errcode = 'P0001', message = 'Retry bloqueado: homologacao, cancelamento ou certificado deixou de ser valido.';
    end if;
  else
    -- Primeiro claim (ou legado sem evidencia) exige os gates mutaveis atuais.
    v_prontidao := f.fn_nfe_producao_pronta(p_solicitacao_id);
    if not coalesce((v_prontidao->>'pronta')::boolean, false) then
      raise exception using errcode = 'P0001', message = coalesce(v_prontidao->>'motivo', 'Producao bloqueada antes do envio.');
    end if;
    if nullif(v_prontidao->>'homologacao_documento_fiscal_id', '')::uuid
       is distinct from p_homologacao_documento_id then
      raise exception using errcode = '40001', message = 'A homologacao autorizada mudou depois do preflight; recarregue antes de emitir.';
    end if;
  end if;

  v_material := f.fn_nfe_producao_contexto_material(p_solicitacao_id, p_homologacao_documento_id);
  if v_material is null then
    raise exception using errcode = '40001', message = 'O contexto fiscal deixou de existir depois do preflight; nenhuma emissao foi criada ou enviada.';
  end if;
  v_contexto_hash_atual := encode(extensions.digest(convert_to(v_material::text, 'utf8'), 'sha256'), 'hex');
  if v_contexto_hash_atual is distinct from lower(p_contexto_hash) then
    raise exception using errcode = '40001', message = 'O contexto fiscal mudou depois do preflight; nenhuma emissao foi criada ou enviada.';
  end if;
  if v_contexto_hash_primeiro_claim is not null
     and v_contexto_hash_primeiro_claim is distinct from v_contexto_hash_atual then
    raise exception using errcode = '40001', message = 'O contexto fiscal diverge daquele congelado no primeiro claim de producao.';
  end if;

  select hom.payload_enviado into v_homologacao_payload
  from f.documento_fiscal_emissao hom
  where hom.tenant_id = v_sf.tenant_id
    and hom.empresa_id = v_sf.empresa_id
    and hom.solicitacao_id = v_sf.id
    and hom.documento_fiscal_id = p_homologacao_documento_id
    and hom.ambiente = 'HOMOLOGACAO'
    and hom.status = 'AUTORIZADA';
  if jsonb_typeof(v_homologacao_payload) is distinct from 'object'
     or btrim(coalesce(v_homologacao_payload->>'nome_destinatario', ''))
        <> 'NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL'
     or nullif(btrim(coalesce(p_payload->>'nome_destinatario', '')), '') is null
     or btrim(p_payload->>'nome_destinatario')
        = 'NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL'
     or (v_homologacao_payload - array['data_emissao','data_entrada_saida','nome_destinatario','ambiente','ambiente_emissao']::text[])
        is distinct from
        (p_payload - array['data_emissao','data_entrada_saida','nome_destinatario','ambiente','ambiente_emissao']::text[]) then
    raise exception using errcode = '22023', message = 'O payload de producao diverge do payload HOM autorizado fora das diferencas legitimas de ambiente.';
  end if;
  if v_emissao.payload_enviado is not null and v_emissao.payload_enviado is distinct from p_payload then
    raise exception using
      errcode = '22023',
      message = 'O payload de retry diverge do payload de producao congelado no primeiro claim.';
  end if;
  if v_emissao.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'ENVIANDO') then
    raise exception using errcode = '55000', message = format('Status %s nao aceita novo claim de envio.', v_emissao.status);
  end if;

  v_produtos := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_produtos');
  v_desconto := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_desconto');
  v_frete := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_frete');
  v_seguro := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_seguro');
  v_outros := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_outras_despesas');
  v_total := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_total');
  if v_produtos is null or v_desconto is null or v_frete is null
     or v_seguro is null or v_outros is null or v_total is null
     or jsonb_typeof(p_payload->'items') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Payload sem totais monetarios completos para congelar o documento de producao.';
  end if;

  select round(coalesce(sum(si.quantidade * si.valor_unitario), 0), 2),
         round(coalesce(sum(si.valor_desconto), 0), 2), count(*)
    into v_total_esperado, v_desconto_fonte, v_itens_solicitacao
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;
  if v_produtos is distinct from v_total_esperado or v_desconto is distinct from v_desconto_fonte
     or v_frete is distinct from coalesce(v_sf.valor_frete, 0)
     or v_seguro is distinct from coalesce(v_sf.valor_seguro, 0)
     or v_outros is distinct from coalesce(v_sf.valor_outras_despesas, 0) then
    raise exception using errcode = '22023', message = 'Totais do payload divergem dos itens/frete/seguro/despesas congelados na solicitacao.';
  end if;
  select count(*), round(coalesce(sum(coalesce(
           f.fn_perfil_operacao_jsonb_numeric_seguro(x.item, 'ipi_valor'), 0
         )), 0), 2)
    into v_itens_payload, v_ipi
  from jsonb_array_elements(p_payload->'items') x(item);
  if v_itens_payload <> v_itens_solicitacao then
    raise exception using errcode = '22023', message = 'Quantidade de itens do payload diverge da solicitacao congelada.';
  end if;
  v_total_esperado := round(v_produtos - v_desconto + v_frete + v_seguro + v_outros + v_ipi, 2);
  if v_total is distinct from v_total_esperado then
    raise exception using errcode = '22023', message = 'Valor total do payload nao fecha produtos/desconto/frete/seguro/despesas/IPI.';
  end if;
  if exists (
    select 1
    from f.solicitacao_item si
    left join lateral (
      select p.item
      from jsonb_array_elements(p_payload->'items') p(item)
      where f.fn_perfil_operacao_jsonb_numeric_seguro(p.item, 'numero_item') = si.ordem
      limit 1
    ) px on true
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and (
        px.item is null
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'quantidade_comercial') is distinct from si.quantidade
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_unitario_comercial') is distinct from si.valor_unitario
        or coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_desconto'), 0) is distinct from si.valor_desconto
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_bruto') is distinct from round(si.quantidade * si.valor_unitario, 2)
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_total_item') is distinct from round(si.quantidade * si.valor_unitario - si.valor_desconto, 2)
      )
  ) then
    raise exception using errcode = '22023', message = 'Quantidade/valor/desconto dos itens do payload divergem da solicitacao congelada.';
  end if;

  update f.documento_fiscal df
  set valor_total = v_total,
      valor_produtos = v_produtos,
      valor_frete = v_frete,
      valor_seguro = v_seguro,
      valor_desconto = v_desconto,
      valor_outros = v_outros,
      updated_at = now()
  where df.tenant_id = v_emissao.tenant_id
    and df.empresa_id = v_emissao.empresa_id
    and df.id = v_emissao.documento_fiscal_id;
  update f.documento_fiscal_item dfi
  set valor_total = f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_total_item'),
      updated_at = now()
  from jsonb_array_elements(p_payload->'items') px(item)
  where dfi.tenant_id = v_emissao.tenant_id
    and dfi.empresa_id = v_emissao.empresa_id
    and dfi.documento_fiscal_id = v_emissao.documento_fiscal_id
    and dfi.item_n = f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'numero_item')::integer;

  update f.documento_fiscal_emissao dfe
  set status = 'ENVIANDO',
      payload_enviado = coalesce(dfe.payload_enviado, p_payload),
      tentativa_count = dfe.tentativa_count + 1,
      ultima_tentativa_em = now(),
      enviado_em = coalesce(dfe.enviado_em, now()),
      codigo_status = null,
      mensagem = null,
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id,
    v_emissao.tenant_id,
    v_emissao.empresa_id,
    'ENVIO',
    'ENVIANDO',
    jsonb_build_object(
      'claim_duravel', true,
      'tentativa', v_emissao.tentativa_count,
      'reconciliacao_previa', coalesce(p_reconciliacao_confirmada, false),
      'homologacao_documento_fiscal_id', p_homologacao_documento_id,
      'contexto_hash', v_contexto_hash_atual
    ),
    v_emissao.referencia_externa
  );

  return jsonb_build_object(
    'deve_enviar', true,
    'aguardar', false,
    'criado', v_preparada.criado,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status,
    'tentativa_count', v_emissao.tentativa_count,
    'payload', v_emissao.payload_enviado
  );
end;
$function$;

comment on function f.fn_nfe_producao_preparar_e_claimar(uuid, jsonb, uuid, text, boolean) is
  'Cria/retoma PROD e grava atomicamente o claim ENVIANDO, payload congelado e contador antes da rede; usa CAS e exige reconciliacao antes de retry.';
revoke all on function f.fn_nfe_producao_preparar_e_claimar(uuid, jsonb, uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_producao_preparar_e_claimar(uuid, jsonb, uuid, text, boolean)
  to service_role;

-- HOM tambem precisa deixar um claim duravel antes do primeiro POST. Sem ele,
-- um timeout apos aceite da Focus poderia parecer ERRO local e permitir que a
-- solicitacao devolvesse saldo antes de um callback tardio.
create or replace function f.fn_nfe_homologacao_claimar(
  p_documento_fiscal_id uuid,
  p_payload jsonb,
  p_reconciliacao_confirmada boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_tinha_claim boolean;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o envio de homologacao.';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'O payload fiscal de homologacao deve ser um objeto JSON.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id
   and df.empresa_id = dfe.empresa_id
   and df.id = dfe.documento_fiscal_id
  join f.solicitacao_faturamento sf
    on sf.tenant_id = dfe.tenant_id
   and sf.empresa_id = dfe.empresa_id
   and sf.id = dfe.solicitacao_id
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO'
  for update of dfe;
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de homologacao nao encontrada no mesmo escopo.';
  end if;

  if v_emissao.status in ('AUTORIZADA', 'PROCESSANDO', 'CANCELADA') then
    return jsonb_build_object(
      'deve_enviar', false,
      'aguardar', v_emissao.status = 'PROCESSANDO',
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status,
      'tentativa_count', v_emissao.tentativa_count,
      'payload', v_emissao.payload_enviado
    );
  end if;

  v_tinha_claim := v_emissao.status = 'ENVIANDO'
    or v_emissao.tentativa_count > 0
    or v_emissao.payload_enviado is not null
    or v_emissao.enviado_em is not null;
  if v_emissao.status = 'ENVIANDO'
     and v_emissao.ultima_tentativa_em >= now() - interval '2 minutes' then
    return jsonb_build_object(
      'deve_enviar', false,
      'aguardar', true,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status,
      'tentativa_count', v_emissao.tentativa_count,
      'payload', v_emissao.payload_enviado
    );
  end if;
  if v_tinha_claim and not coalesce(p_reconciliacao_confirmada, false) then
    raise exception using
      errcode = '55000',
      message = 'A referencia de homologacao ja possui tentativa; consulte a Focus antes de qualquer novo POST.';
  end if;
  if v_emissao.payload_enviado is not null
     and v_emissao.payload_enviado is distinct from p_payload then
    raise exception using errcode = '22023', message = 'O retry de homologacao diverge do payload congelado no primeiro claim.';
  end if;
  if v_emissao.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'ENVIANDO') then
    raise exception using errcode = '55000', message = format('Status %s nao aceita claim de homologacao.', v_emissao.status);
  end if;

  update f.documento_fiscal_emissao dfe
  set status = 'ENVIANDO',
      payload_enviado = coalesce(dfe.payload_enviado, p_payload),
      tentativa_count = dfe.tentativa_count + 1,
      ultima_tentativa_em = now(),
      enviado_em = coalesce(dfe.enviado_em, now()),
      codigo_status = null,
      mensagem = null,
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id,
    v_emissao.tenant_id,
    v_emissao.empresa_id,
    'ENVIO',
    'ENVIANDO',
    jsonb_build_object(
      'claim_duravel', true,
      'ambiente', 'HOMOLOGACAO',
      'tentativa', v_emissao.tentativa_count,
      'reconciliacao_previa', coalesce(p_reconciliacao_confirmada, false)
    ),
    v_emissao.referencia_externa
  );

  return jsonb_build_object(
    'deve_enviar', true,
    'aguardar', false,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status,
    'tentativa_count', v_emissao.tentativa_count,
    'payload', v_emissao.payload_enviado
  );
end;
$function$;

comment on function f.fn_nfe_homologacao_claimar(uuid, jsonb, boolean) is
  'Claim CAS duravel de HOM antes da rede; concorrente recente aguarda e qualquer retry exige GET Focus conclusivo antes de novo POST.';
revoke all on function f.fn_nfe_homologacao_claimar(uuid, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_homologacao_claimar(uuid, jsonb, boolean)
  to service_role;

-- O claim ja contabilizou a tentativa. Registrar a resposta do provedor nao
-- pode incrementar o contador pela segunda vez nem trocar o payload congelado.
create or replace function f.fn_nfe_registrar_envio(
  p_documento_fiscal_id uuid,
  p_payload jsonb,
  p_resposta jsonb,
  p_status text default 'PROCESSANDO',
  p_codigo_status integer default null,
  p_mensagem text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status_provedor text := upper(btrim(coalesce(p_status, '')));
  v_status_persistido text;
  v_claim_contabilizado boolean;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode registrar o envio.';
  end if;
  if v_status_provedor not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de envio invalido.';
  end if;
  -- AUTORIZADA so pode ser materializada pelas funcoes de aplicar retorno,
  -- depois de validar chave/XML e persistir os artefatos obrigatorios.
  v_status_persistido := case
    when v_status_provedor = 'AUTORIZADA' then 'PROCESSANDO'
    else v_status_provedor
  end;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id
   and df.empresa_id = dfe.empresa_id
   and df.id = dfe.documento_fiscal_id
  where dfe.documento_fiscal_id = p_documento_fiscal_id
  for update of dfe;
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao nao encontrada.';
  end if;
  if v_emissao.status = 'CANCELADA' then
    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
    ) values (
      v_emissao.documento_fiscal_id,
      v_emissao.tenant_id,
      v_emissao.empresa_id,
      'CONSULTA',
      'INCIDENTE_RETORNO_TARDIO',
      jsonb_strip_nulls(jsonb_build_object(
        'etapa', 'REGISTRAR_ENVIO',
        'status_recebido', v_status_provedor,
        'codigo_status', p_codigo_status,
        'mensagem', p_mensagem,
        'resposta', p_resposta,
        'cancelada_terminal', true
      )),
      v_emissao.referencia_externa
    );
    return;
  end if;
  if v_emissao.status = 'AUTORIZADA' then
    if v_status_provedor <> 'AUTORIZADA' then
      insert into f.documento_fiscal_evento (
        documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
      ) values (
        v_emissao.documento_fiscal_id,
        v_emissao.tenant_id,
        v_emissao.empresa_id,
        'CONSULTA',
        'INCIDENTE_RESPOSTA_TARDIA',
        jsonb_strip_nulls(jsonb_build_object(
          'etapa', 'REGISTRAR_ENVIO',
          'estado_terminal', 'AUTORIZADA',
          'status_recebido', v_status_provedor,
          'codigo_status', p_codigo_status,
          'mensagem', p_mensagem,
          'resposta', p_resposta
        )),
        v_emissao.referencia_externa
      );
    end if;
    return;
  end if;
  if v_emissao.ambiente = 'PRODUCAO'
     and v_emissao.payload_enviado is not null
     and p_payload is not null
     and v_emissao.payload_enviado is distinct from p_payload then
    raise exception using errcode = '22023', message = 'A resposta nao corresponde ao payload congelado da producao.';
  end if;

  -- Toda tentativa de PRODUCAO passa pelo claim atomico. Manter o marcador
  -- depois da primeira resposta torna o registro idempotente tambem quando a
  -- resposta do RPC se perde e a Edge repete apenas a persistencia local.
  v_claim_contabilizado := v_emissao.tentativa_count > 0
    and v_emissao.payload_enviado is not null
    and exists (
      select 1
      from f.documento_fiscal_evento ev
      where ev.tenant_id = v_emissao.tenant_id
        and ev.empresa_id = v_emissao.empresa_id
        and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
        and ev.tipo = 'ENVIO'
        and coalesce((ev.resposta->>'claim_duravel')::boolean, false)
    );

  update f.documento_fiscal_emissao dfe
  set status = v_status_persistido,
      payload_enviado = coalesce(dfe.payload_enviado, p_payload),
      resposta = coalesce(p_resposta, dfe.resposta),
      codigo_status = coalesce(p_codigo_status, dfe.codigo_status),
      mensagem = coalesce(p_mensagem, dfe.mensagem),
      tentativa_count = dfe.tentativa_count + case when v_claim_contabilizado then 0 else 1 end,
      ultima_tentativa_em = case when v_claim_contabilizado then dfe.ultima_tentativa_em else now() end,
      enviado_em = coalesce(dfe.enviado_em, now()),
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id,
    v_emissao.tenant_id,
    v_emissao.empresa_id,
    case
      when v_status_persistido in ('REJEITADA', 'ERRO') then 'REJEICAO'
      else 'ENVIO'
    end,
    v_status_persistido,
    jsonb_strip_nulls(jsonb_build_object(
      'codigo_status', p_codigo_status,
      'mensagem', p_mensagem,
      'resposta', p_resposta,
      'status_provedor', v_status_provedor,
      'claim_ja_contabilizado', v_claim_contabilizado
    )),
    v_emissao.referencia_externa
  );
end;
$function$;

revoke all on function f.fn_nfe_registrar_envio(uuid, jsonb, jsonb, text, integer, text)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_registrar_envio(uuid, jsonb, jsonb, text, integer, text)
  to service_role;

-- CANCELADA e terminal. Um callback/consulta tardio pode ser preservado como
-- incidente append-only, mas nunca reabre emissao, documento, solicitacao ou
-- financeiro que ja foram cancelados.
create or replace function f.fn_nfe_aplicar_retorno(
  p_referencia_externa text,
  p_resposta jsonb,
  p_status text,
  p_chave_acesso text default null,
  p_protocolo text default null,
  p_numero integer default null,
  p_serie integer default null,
  p_codigo_status integer default null,
  p_mensagem text default null,
  p_xml_path text default null,
  p_danfe_path text default null,
  p_xml_raw text default null,
  p_origem_retorno text default 'CALLBACK'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_xml_hash text;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode aplicar retorno.';
  end if;
  if v_status not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'CANCELADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de retorno invalido.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.referencia_externa = p_referencia_externa
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = format('Referencia %s nao encontrada.', p_referencia_externa);
  end if;
  if v_emissao.ambiente <> 'HOMOLOGACAO' then
    raise exception using errcode = '42501', message = 'Este pipeline aplica retorno somente de HOMOLOGACAO.';
  end if;

  if v_emissao.status = 'CANCELADA' then
    if v_status <> 'CANCELADA' then
      insert into f.documento_fiscal_evento (
        documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
      ) values (
        v_emissao.documento_fiscal_id,
        v_emissao.tenant_id,
        v_emissao.empresa_id,
        'CONSULTA',
        'INCIDENTE_RETORNO_TARDIO',
        jsonb_strip_nulls(jsonb_build_object(
          'etapa', 'APLICAR_RETORNO',
          'origem_retorno', upper(coalesce(p_origem_retorno, '')),
          'status_recebido', v_status,
          'chave_acesso_recebida', p_chave_acesso,
          'protocolo_recebido', p_protocolo,
          'codigo_status', p_codigo_status,
          'mensagem', p_mensagem,
          'resposta', p_resposta,
          'cancelada_terminal', true
        )),
        v_emissao.referencia_externa
      );
    end if;
    return v_emissao.documento_fiscal_id;
  end if;
  if v_status = 'CANCELADA' then
    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
    ) values (
      v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
      'CONSULTA', 'INCIDENTE_CANCELAMENTO_FORA_DO_FLUXO',
      jsonb_strip_nulls(jsonb_build_object(
        'ambiente', 'HOMOLOGACAO', 'origem_retorno', upper(coalesce(p_origem_retorno, '')),
        'codigo_status', p_codigo_status, 'mensagem', p_mensagem,
        'resposta', p_resposta, 'estado_preservado', v_emissao.status
      )),
      v_emissao.referencia_externa
    );
    return v_emissao.documento_fiscal_id;
  end if;
  if v_emissao.status = 'AUTORIZADA' and v_status <> 'AUTORIZADA' then
    return v_emissao.documento_fiscal_id;
  end if;

  if v_status = 'AUTORIZADA' then
    if nullif(p_chave_acesso, '') is null or p_chave_acesso !~ '^[0-9]{44}$' then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem chave de acesso valida.';
    end if;
    if nullif(btrim(coalesce(p_xml_raw, '')), '') is null then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem XML para f.documento_fiscal_xml.';
    end if;
    v_xml_hash := encode(extensions.digest(convert_to(p_xml_raw, 'utf8'), 'sha256'), 'hex');
  end if;

  update f.documento_fiscal_emissao dfe
  set status = v_status,
      resposta = coalesce(p_resposta, dfe.resposta),
      chave_acesso = coalesce(nullif(p_chave_acesso, ''), dfe.chave_acesso),
      protocolo = coalesce(nullif(p_protocolo, ''), dfe.protocolo),
      numero = coalesce(p_numero, dfe.numero),
      serie = coalesce(p_serie, dfe.serie),
      codigo_status = coalesce(p_codigo_status, dfe.codigo_status),
      mensagem = coalesce(nullif(p_mensagem, ''), dfe.mensagem),
      xml_path = coalesce(nullif(p_xml_path, ''), dfe.xml_path),
      danfe_path = coalesce(nullif(p_danfe_path, ''), dfe.danfe_path),
      callback_recebido_em = case when upper(p_origem_retorno) = 'CALLBACK' then now() else dfe.callback_recebido_em end,
      reconciliado_em = case when upper(p_origem_retorno) = 'RECONCILIACAO' then now() else dfe.reconciliado_em end,
      autorizado_em = case when v_status = 'AUTORIZADA' then coalesce(dfe.autorizado_em, now()) else dfe.autorizado_em end,
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;

  if v_status = 'AUTORIZADA' then
    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_emissao.tenant_id, v_emissao.documento_fiscal_id, p_chave_acesso, p_xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id)
    do update set chave_acesso = excluded.chave_acesso,
                  xml_raw = excluded.xml_raw,
                  xml_hash = excluded.xml_hash,
                  deleted_at = null;

    update f.documento_fiscal df
    set chave_acesso = p_chave_acesso,
        numero = coalesce(p_numero::text, df.numero),
        serie = coalesce(p_serie::text, df.serie),
        nfe_status = 'RASCUNHO',
        emissao_date = coalesce(df.emissao_date, current_date),
        updated_at = now()
    where df.tenant_id = v_emissao.tenant_id
      and df.empresa_id = v_emissao.empresa_id
      and df.id = v_emissao.documento_fiscal_id;

    update f.solicitacao_faturamento sf
    set status = 'EMITIDA', updated_at = now()
    where sf.tenant_id = v_emissao.tenant_id
      and sf.empresa_id = v_emissao.empresa_id
      and sf.id = v_emissao.solicitacao_id;

    update f.documento_fiscal_item dfi
    set ncm = coalesce(dfi.ncm, nullif(x.item->>'codigo_ncm', '')),
        cfop = coalesce(nullif(x.item->>'cfop', ''), dfi.cfop),
        cst_icms = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 2 then x.item->>'icms_situacao_tributaria' else null end,
        csosn = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 3 then x.item->>'icms_situacao_tributaria' else null end,
        cst_ipi = nullif(x.item->>'ipi_situacao_tributaria', ''),
        cst_pis = nullif(x.item->>'pis_situacao_tributaria', ''),
        cst_cofins = nullif(x.item->>'cofins_situacao_tributaria', ''),
        cbenef = nullif(x.item->>'codigo_beneficio_fiscal', ''),
        reducao_base_icms_percentual = nullif(x.item->>'icms_reducao_base_calculo', '')::numeric,
        unidade_tributavel = nullif(x.item->>'unidade_tributavel', ''),
        snapshot_fiscal_em = coalesce(dfi.snapshot_fiscal_em, now()),
        updated_at = now()
    from jsonb_array_elements(coalesce((
      select d.payload_enviado
      from f.documento_fiscal_emissao d
      where d.tenant_id = v_emissao.tenant_id
        and d.empresa_id = v_emissao.empresa_id
        and d.documento_fiscal_id = v_emissao.documento_fiscal_id
    )->'items', '[]'::jsonb)) x(item)
    where dfi.tenant_id = v_emissao.tenant_id
      and dfi.empresa_id = v_emissao.empresa_id
      and dfi.documento_fiscal_id = v_emissao.documento_fiscal_id
      and dfi.item_n = (x.item->>'numero_item')::integer;
  end if;

  return v_emissao.documento_fiscal_id;
end;
$function$;

comment on function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text) is
  'Aplica retorno HOM e trata CANCELADA como terminal; retorno tardio vira incidente append-only sem reabrir o fluxo.';
revoke all on function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_aplicar_retorno(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text)
  to service_role;

create or replace function f.fn_nfe_aplicar_retorno_producao(
  p_referencia_externa text,
  p_resposta jsonb,
  p_status text,
  p_chave_acesso text default null,
  p_protocolo text default null,
  p_numero integer default null,
  p_serie integer default null,
  p_codigo_status integer default null,
  p_mensagem text default null,
  p_xml_path text default null,
  p_danfe_path text default null,
  p_xml_raw text default null,
  p_origem_retorno text default 'CALLBACK'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_xml_hash text;
  v_claim_duravel boolean;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode aplicar retorno de producao.';
  end if;
  if v_status not in ('PROCESSANDO', 'AUTORIZADA', 'REJEITADA', 'CANCELADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status de retorno invalido.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.referencia_externa = p_referencia_externa
    and dfe.ambiente = 'PRODUCAO'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = format('Referencia de producao %s nao encontrada.', p_referencia_externa);
  end if;

  if v_emissao.status = 'CANCELADA' then
    if v_status <> 'CANCELADA' then
      insert into f.documento_fiscal_evento (
        documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
      ) values (
        v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
        'CONSULTA', 'INCIDENTE_RETORNO_TARDIO',
        jsonb_strip_nulls(jsonb_build_object(
          'ambiente', 'PRODUCAO', 'origem_retorno', upper(coalesce(p_origem_retorno, '')),
          'status_recebido', v_status, 'codigo_status', p_codigo_status,
          'mensagem', p_mensagem, 'resposta', p_resposta, 'cancelada_terminal', true
        )),
        v_emissao.referencia_externa
      );
    end if;
    return v_emissao.documento_fiscal_id;
  end if;

  -- O ERP nao implementa cancelamento externo de PROD nesta fase. Uma Focus
  -- que reporte CANCELADA e incidente; nunca converte o estado/financeiro.
  if v_status = 'CANCELADA' then
    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
    ) values (
      v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
      'CONSULTA', 'INCIDENTE_CANCELAMENTO_PRODUCAO_NAO_SUPORTADO',
      jsonb_strip_nulls(jsonb_build_object(
        'origem_retorno', upper(coalesce(p_origem_retorno, '')),
        'codigo_status', p_codigo_status, 'mensagem', p_mensagem,
        'resposta', p_resposta, 'estado_preservado', v_emissao.status
      )),
      v_emissao.referencia_externa
    );
    return v_emissao.documento_fiscal_id;
  end if;

  if v_emissao.status = 'AUTORIZADA' then
    if v_status = 'AUTORIZADA'
       and p_chave_acesso is not null
       and p_chave_acesso is distinct from v_emissao.chave_acesso then
      insert into f.documento_fiscal_evento (
        documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
      ) values (
        v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
        'CONSULTA', 'INCIDENTE_CHAVE_DIVERGENTE',
        jsonb_build_object('chave_atual', v_emissao.chave_acesso, 'chave_recebida', p_chave_acesso, 'resposta', p_resposta),
        v_emissao.referencia_externa
      );
    end if;
    return v_emissao.documento_fiscal_id;
  end if;

  select exists (
    select 1
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'ENVIO'
      and ev.status = 'ENVIANDO'
      and coalesce((ev.resposta->>'claim_duravel')::boolean, false)
  ) into v_claim_duravel;

  if v_status = 'AUTORIZADA' then
    if not v_claim_duravel
       or v_emissao.status not in ('ENVIANDO', 'PROCESSANDO')
       or v_emissao.tentativa_count <= 0
       or jsonb_typeof(v_emissao.payload_enviado) is distinct from 'object'
       or jsonb_typeof(v_emissao.payload_enviado->'items') is distinct from 'array' then
      raise exception using
        errcode = '55000',
        message = 'Autorizacao de producao sem claim duravel, payload congelado ou estado reconciliavel foi bloqueada.';
    end if;
    if nullif(p_chave_acesso, '') is null or p_chave_acesso !~ '^[0-9]{44}$' then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem chave de acesso valida.';
    end if;
    if nullif(btrim(coalesce(p_xml_raw, '')), '') is null then
      raise exception using errcode = '22023', message = 'Retorno autorizado sem XML para f.documento_fiscal_xml.';
    end if;
    v_xml_hash := encode(extensions.digest(convert_to(p_xml_raw, 'utf8'), 'sha256'), 'hex');
  elsif not v_claim_duravel then
    raise exception using errcode = '55000', message = 'Retorno de producao sem claim duravel foi bloqueado.';
  end if;

  -- Para AUTORIZADA, artefato e estado nascem na mesma transacao; nunca ha
  -- janela AUTORIZADA sem XML. PROCESSANDO/REJEITADA/ERRO apenas reconciliam.
  if v_status = 'AUTORIZADA' then
    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_emissao.tenant_id, v_emissao.documento_fiscal_id, p_chave_acesso, p_xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id)
    do update set chave_acesso = excluded.chave_acesso,
                  xml_raw = excluded.xml_raw,
                  xml_hash = excluded.xml_hash,
                  deleted_at = null;
  end if;

  update f.documento_fiscal_emissao dfe
  set status = v_status,
      resposta = coalesce(p_resposta, dfe.resposta),
      chave_acesso = coalesce(nullif(p_chave_acesso, ''), dfe.chave_acesso),
      protocolo = coalesce(nullif(p_protocolo, ''), dfe.protocolo),
      numero = coalesce(p_numero, dfe.numero),
      serie = coalesce(p_serie, dfe.serie),
      codigo_status = coalesce(p_codigo_status, dfe.codigo_status),
      mensagem = coalesce(nullif(p_mensagem, ''), dfe.mensagem),
      xml_path = coalesce(nullif(p_xml_path, ''), dfe.xml_path),
      danfe_path = coalesce(nullif(p_danfe_path, ''), dfe.danfe_path),
      callback_recebido_em = case when upper(p_origem_retorno) = 'CALLBACK' then now() else dfe.callback_recebido_em end,
      reconciliado_em = case when upper(p_origem_retorno) = 'RECONCILIACAO' then now() else dfe.reconciliado_em end,
      autorizado_em = case when v_status = 'AUTORIZADA' then coalesce(dfe.autorizado_em, now()) else dfe.autorizado_em end,
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;

  if v_status = 'AUTORIZADA' then
    update f.documento_fiscal df
    set chave_acesso = p_chave_acesso,
        numero = coalesce(p_numero::text, df.numero),
        serie = coalesce(p_serie::text, df.serie),
        nfe_status = 'EMITIDA',
        emissao_date = coalesce(df.emissao_date, current_date),
        competencia_date = date_trunc('month', coalesce(df.emissao_date, current_date))::date,
        updated_at = now()
    where df.tenant_id = v_emissao.tenant_id
      and df.empresa_id = v_emissao.empresa_id
      and df.id = v_emissao.documento_fiscal_id;

    update f.solicitacao_faturamento sf
    set status = 'EMITIDA', updated_at = now()
    where sf.tenant_id = v_emissao.tenant_id
      and sf.empresa_id = v_emissao.empresa_id
      and sf.id = v_emissao.solicitacao_id;

    update f.documento_fiscal_item dfi
    set ncm = coalesce(dfi.ncm, nullif(x.item->>'codigo_ncm', '')),
        cfop = coalesce(nullif(x.item->>'cfop', ''), dfi.cfop),
        cst_icms = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 2 then x.item->>'icms_situacao_tributaria' else null end,
        csosn = case when length(coalesce(x.item->>'icms_situacao_tributaria', '')) = 3 then x.item->>'icms_situacao_tributaria' else null end,
        cst_ipi = nullif(x.item->>'ipi_situacao_tributaria', ''),
        cst_pis = nullif(x.item->>'pis_situacao_tributaria', ''),
        cst_cofins = nullif(x.item->>'cofins_situacao_tributaria', ''),
        cbenef = nullif(x.item->>'codigo_beneficio_fiscal', ''),
        reducao_base_icms_percentual = nullif(x.item->>'icms_reducao_base_calculo', '')::numeric,
        unidade_tributavel = nullif(x.item->>'unidade_tributavel', ''),
        snapshot_fiscal_em = coalesce(dfi.snapshot_fiscal_em, now()),
        updated_at = now()
    from jsonb_array_elements(v_emissao.payload_enviado->'items') x(item)
    where dfi.tenant_id = v_emissao.tenant_id
      and dfi.empresa_id = v_emissao.empresa_id
      and dfi.documento_fiscal_id = v_emissao.documento_fiscal_id
      and dfi.item_n = (x.item->>'numero_item')::integer;

    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, protocolo, status, resposta, referencia_externa
    ) values (
      v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
      'AUTORIZACAO', p_protocolo, 'AUTORIZADA',
      jsonb_strip_nulls(jsonb_build_object(
        'codigo_status', p_codigo_status, 'mensagem', p_mensagem,
        'xml_sha256', v_xml_hash, 'origem_retorno', upper(coalesce(p_origem_retorno, '')),
        'resposta', p_resposta
      )),
      v_emissao.referencia_externa
    );
  end if;

  return v_emissao.documento_fiscal_id;
end;
$function$;

comment on function f.fn_nfe_aplicar_retorno_producao(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text) is
  'Aplica retorno PROD somente apos claim/payload duraveis; AUTORIZADA nasce com XML/AR atomicamente e estados terminais nunca sao reabertos.';
revoke all on function f.fn_nfe_aplicar_retorno_producao(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_aplicar_retorno_producao(text, jsonb, text, text, text, integer, integer, integer, text, text, text, text, text)
  to service_role;

create or replace function f.fn_nfe_emissoes_pendentes_reconciliacao_producao(p_limite integer default 50)
returns table (documento_fiscal_id uuid, referencia_externa text, ambiente text)
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select dfe.documento_fiscal_id, dfe.referencia_externa, dfe.ambiente
  from f.documento_fiscal_emissao dfe
  where dfe.ambiente = 'PRODUCAO'
    and dfe.status in ('ENVIANDO', 'PROCESSANDO')
    and coalesce(dfe.ultima_tentativa_em, dfe.updated_at) < now() - interval '10 minutes'
  order by coalesce(dfe.ultima_tentativa_em, dfe.updated_at)
  limit least(greatest(coalesce(p_limite, 50), 1), 200);
$function$;

comment on function f.fn_nfe_emissoes_pendentes_reconciliacao_producao(integer) is
  'Lista PROCESSANDO e claims ENVIANDO stale para reconciliacao automatica por referencia na Focus de producao.';
revoke all on function f.fn_nfe_emissoes_pendentes_reconciliacao_producao(integer)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_emissoes_pendentes_reconciliacao_producao(integer)
  to service_role;

create or replace function f.fn_nfe_emissoes_pendentes_reconciliacao(p_limite integer default 50)
returns table (documento_fiscal_id uuid, referencia_externa text, ambiente text)
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select dfe.documento_fiscal_id, dfe.referencia_externa, dfe.ambiente
  from f.documento_fiscal_emissao dfe
  where dfe.ambiente = 'HOMOLOGACAO'
    and dfe.status in ('ENVIANDO', 'PROCESSANDO')
    and coalesce(dfe.ultima_tentativa_em, dfe.updated_at) < now() - interval '10 minutes'
  order by coalesce(dfe.ultima_tentativa_em, dfe.updated_at)
  limit least(greatest(coalesce(p_limite, 50), 1), 200);
$function$;

comment on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer) is
  'Lista respostas PROCESSANDO e claims HOM ENVIANDO stale para reconciliacao automatica por referencia, sem novo POST.';
revoke all on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_emissoes_pendentes_reconciliacao(integer)
  to service_role;

create or replace function f.fn_nfe_producao_abandonar_rejeitada(
  p_documento_fiscal_id uuid,
  p_referencia_externa text,
  p_status_focus text,
  p_justificativa text,
  p_prova_focus jsonb,
  p_codigo_status integer default null,
  p_mensagem text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_meta record;
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_documento f.documento_fiscal%rowtype;
  v_origem record;
  v_prova_hash text;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode abandonar uma producao rejeitada.';
  end if;
  if upper(btrim(coalesce(p_status_focus, ''))) <> 'REJEITADA'
     or jsonb_typeof(p_prova_focus) is distinct from 'object'
     or nullif(btrim(coalesce(p_referencia_externa, '')), '') is null then
    raise exception using errcode = '22023', message = 'Abandono exige GET Focus conclusivo em REJEITADA, referencia e prova JSON.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa do abandono deve ter entre 15 e 255 caracteres.';
  end if;

  select dfe.tenant_id, dfe.empresa_id, dfe.solicitacao_id
    into v_meta
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de producao nao encontrada.';
  end if;

  -- Mesma ordem de locks dos demais fluxos: solicitacao -> emissao -> doc.
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_meta.tenant_id
    and sf.empresa_id = v_meta.empresa_id
    and sf.id = v_meta.solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao da producao nao encontrada no mesmo escopo.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO'
  for update;
  select df.* into v_documento
  from f.documento_fiscal df
  where df.tenant_id = v_sf.tenant_id
    and df.empresa_id = v_sf.empresa_id
    and df.id = v_emissao.documento_fiscal_id
  for update;
  if v_emissao.documento_fiscal_id is null or v_documento.id is null then
    raise exception using errcode = 'P0002', message = 'Producao/documento nao encontrado no mesmo escopo.';
  end if;

  if v_emissao.status = 'CANCELADA' and exists (
    select 1
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
      and ev.status = 'ABANDONADA_REJEITADA'
  ) then
    return jsonb_build_object(
      'ok', true,
      'idempotente', true,
      'solicitacao_id', v_sf.id,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'status', 'CANCELADA'
    );
  end if;

  if v_emissao.referencia_externa is distinct from btrim(p_referencia_externa)
     or v_emissao.status <> 'REJEITADA'
     or v_emissao.resposta is distinct from p_prova_focus
     or v_emissao.chave_acesso is not null
     or v_emissao.protocolo is not null
     or v_emissao.autorizado_em is not null
     or v_documento.nfe_status is distinct from 'RASCUNHO'
     or exists (
       select 1
       from f.documento_fiscal_xml dfx
       where dfx.tenant_id = v_emissao.tenant_id
         and dfx.documento_fiscal_id = v_emissao.documento_fiscal_id
         and dfx.deleted_at is null
     ) then
    raise exception using
      errcode = '55000',
      message = 'A producao nao esta em REJEITADA conclusiva sem qualquer evidencia de autorizacao; abandono bloqueado.';
  end if;

  for v_origem in
    select distinct si.origem_id::integer as origem_id
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id ~ '^[0-9]+$'
    order by si.origem_id::integer
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      format('faturamento-parcial:%s:%s:%s', v_sf.tenant_id, v_sf.empresa_id, v_origem.origem_id),
      0
    ));
  end loop;

  v_prova_hash := encode(extensions.digest(convert_to(p_prova_focus::text, 'utf8'), 'sha256'), 'hex');
  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
    status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id,
    v_emissao.tenant_id,
    v_emissao.empresa_id,
    'CANCELAMENTO',
    v_justificativa,
    'ABANDONADA_REJEITADA',
    jsonb_strip_nulls(jsonb_build_object(
      'sem_chamada_cancelamento_focus', true,
      'status_focus', 'REJEITADA',
      'codigo_status', p_codigo_status,
      'mensagem', p_mensagem,
      'prova_focus', p_prova_focus,
      'prova_sha256', v_prova_hash,
      'confirmado_em', clock_timestamp()
    )),
    v_emissao.referencia_externa
  );

  update f.documento_fiscal_emissao dfe
  set status = 'CANCELADA',
      mensagem = 'Producao abandonada apos rejeicao conclusiva reconciliada na Focus.',
      reconciliado_em = now(),
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;

  update f.documento_fiscal df
  set nfe_status = 'CANCELADA', updated_at = now()
  where df.tenant_id = v_emissao.tenant_id
    and df.empresa_id = v_emissao.empresa_id
    and df.id = v_emissao.documento_fiscal_id
    and df.nfe_status = 'RASCUNHO';

  update f.solicitacao_faturamento sf
  set status = 'CANCELADA',
      observacao = concat_ws(
        E'\n',
        nullif(btrim(sf.observacao), ''),
        'Producao abandonada apos rejeicao conclusiva da Focus. Motivo: ' || v_justificativa ||
        '. Provedor: ' || coalesce(nullif(btrim(p_mensagem), ''), 'sem mensagem')
      ),
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  return jsonb_build_object(
    'ok', true,
    'idempotente', false,
    'solicitacao_id', v_sf.id,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', 'CANCELADA',
    'prova_sha256', v_prova_hash
  );
end;
$function$;

comment on function f.fn_nfe_producao_abandonar_rejeitada(uuid, text, text, text, jsonb, integer, text) is
  'Abandona PROD somente com prova GET Focus persistida e estado REJEITADA sob lock, sem chave/XML/autorizacao; cancela a solicitacao e devolve saldo por advisory lock.';
revoke all on function f.fn_nfe_producao_abandonar_rejeitada(uuid, text, text, text, jsonb, integer, text)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_producao_abandonar_rejeitada(uuid, text, text, text, jsonb, integer, text)
  to service_role;

create or replace function f.fn_nfe_homologacao_abandonar_rejeitada(
  p_documento_fiscal_id uuid,
  p_referencia_externa text,
  p_status_focus text,
  p_justificativa text,
  p_prova_focus jsonb,
  p_codigo_status integer default null,
  p_mensagem text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_meta record;
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_documento f.documento_fiscal%rowtype;
  v_origem record;
  v_prova_hash text;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode abandonar uma homologacao rejeitada.';
  end if;
  if upper(btrim(coalesce(p_status_focus, ''))) <> 'REJEITADA'
     or jsonb_typeof(p_prova_focus) is distinct from 'object'
     or nullif(btrim(coalesce(p_referencia_externa, '')), '') is null then
    raise exception using errcode = '22023', message = 'Abandono exige GET Focus conclusivo em REJEITADA, referencia e prova JSON.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa do abandono deve ter entre 15 e 255 caracteres.';
  end if;

  select dfe.tenant_id, dfe.empresa_id, dfe.solicitacao_id
    into v_meta
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de homologacao nao encontrada.';
  end if;

  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_meta.tenant_id
    and sf.empresa_id = v_meta.empresa_id
    and sf.id = v_meta.solicitacao_id
  for update;
  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO'
  for update;
  select df.* into v_documento
  from f.documento_fiscal df
  where df.tenant_id = v_sf.tenant_id
    and df.empresa_id = v_sf.empresa_id
    and df.id = v_emissao.documento_fiscal_id
  for update;
  if v_emissao.documento_fiscal_id is null or v_documento.id is null then
    raise exception using errcode = 'P0002', message = 'Homologacao/documento nao encontrado no mesmo escopo.';
  end if;

  if v_emissao.status = 'CANCELADA' and exists (
    select 1 from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
      and ev.status = 'ABANDONADA_REJEITADA'
  ) then
    return jsonb_build_object('ok', true, 'idempotente', true,
      'solicitacao_id', v_sf.id, 'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'status', 'CANCELADA');
  end if;

  if v_emissao.referencia_externa is distinct from btrim(p_referencia_externa)
     or v_emissao.status <> 'REJEITADA'
     or v_emissao.resposta is distinct from p_prova_focus
     or v_emissao.chave_acesso is not null
     or v_emissao.protocolo is not null
     or v_emissao.autorizado_em is not null
     or v_documento.nfe_status is distinct from 'RASCUNHO'
     or exists (
       select 1 from f.documento_fiscal_xml dfx
       where dfx.tenant_id = v_emissao.tenant_id
         and dfx.documento_fiscal_id = v_emissao.documento_fiscal_id
         and dfx.deleted_at is null
     )
     or exists (
       select 1 from f.documento_fiscal_emissao prod
       where prod.tenant_id = v_emissao.tenant_id
         and prod.empresa_id = v_emissao.empresa_id
         and prod.solicitacao_id = v_emissao.solicitacao_id
         and prod.ambiente = 'PRODUCAO'
         and prod.status <> 'CANCELADA'
     ) then
    raise exception using errcode = '55000',
      message = 'A HOM nao esta em REJEITADA conclusiva sem autorizacao/promocao; abandono bloqueado.';
  end if;

  for v_origem in
    select distinct si.origem_id::integer as origem_id
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id ~ '^[0-9]+$'
    order by si.origem_id::integer
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      format('faturamento-parcial:%s:%s:%s', v_sf.tenant_id, v_sf.empresa_id, v_origem.origem_id), 0
    ));
  end loop;

  v_prova_hash := encode(extensions.digest(convert_to(p_prova_focus::text, 'utf8'), 'sha256'), 'hex');
  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
    status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
    'CANCELAMENTO', v_justificativa,
    'ABANDONADA_REJEITADA',
    jsonb_strip_nulls(jsonb_build_object(
      'ambiente', 'HOMOLOGACAO', 'sem_chamada_cancelamento_focus', true,
      'status_focus', 'REJEITADA', 'codigo_status', p_codigo_status,
      'mensagem', p_mensagem, 'prova_focus', p_prova_focus,
      'prova_sha256', v_prova_hash, 'confirmado_em', clock_timestamp()
    )),
    v_emissao.referencia_externa
  );
  update f.documento_fiscal_emissao dfe
  set status = 'CANCELADA',
      mensagem = 'Homologacao abandonada apos rejeicao conclusiva reconciliada na Focus.',
      reconciliado_em = now(), updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
  update f.documento_fiscal df
  set nfe_status = 'CANCELADA', updated_at = now()
  where df.tenant_id = v_emissao.tenant_id
    and df.empresa_id = v_emissao.empresa_id
    and df.id = v_emissao.documento_fiscal_id
    and df.nfe_status = 'RASCUNHO';
  update f.solicitacao_faturamento sf
  set status = 'CANCELADA',
      observacao = concat_ws(E'\n', nullif(btrim(sf.observacao), ''),
        'Homologacao abandonada apos rejeicao conclusiva da Focus. Motivo: ' || v_justificativa ||
        '. Provedor: ' || coalesce(nullif(btrim(p_mensagem), ''), 'sem mensagem')),
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  return jsonb_build_object(
    'ok', true, 'idempotente', false, 'solicitacao_id', v_sf.id,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', 'CANCELADA', 'prova_sha256', v_prova_hash
  );
end;
$function$;

comment on function f.fn_nfe_homologacao_abandonar_rejeitada(uuid, text, text, text, jsonb, integer, text) is
  'Abandona HOM somente apos GET Focus REJEITADA persistido, sem autorizacao/PROD; cancela a solicitacao e libera o saldo para nova tentativa.';
revoke all on function f.fn_nfe_homologacao_abandonar_rejeitada(uuid, text, text, text, jsonb, integer, text)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_homologacao_abandonar_rejeitada(uuid, text, text, text, jsonb, integer, text)
  to service_role;

create or replace function f.fn_nfe_cancelamento_homologacao_claim(
  p_documento_fiscal_id uuid,
  p_justificativa text,
  p_reconciliacao_claim_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_meta record;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_ultimo_cancelamento_id uuid;
  v_ultimo_cancelamento_status text;
  v_ultimo_cancelamento_em timestamptz;
  v_ultimo_cancelamento_justificativa text;
  v_evento_claim_id uuid;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o cancelamento.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa deve ter entre 15 e 255 caracteres.';
  end if;

  select dfe.tenant_id, dfe.empresa_id, dfe.solicitacao_id
    into v_meta
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id
   and df.empresa_id = dfe.empresa_id
   and df.id = dfe.documento_fiscal_id
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de homologacao nao encontrada.';
  end if;

  -- Mesma ordem de lock da promocao: solicitacao primeiro, emissao depois.
  perform 1
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_meta.tenant_id
    and sf.empresa_id = v_meta.empresa_id
    and sf.id = v_meta.solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao da homologacao nao encontrada no mesmo escopo.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_meta.tenant_id
    and dfe.empresa_id = v_meta.empresa_id
    and dfe.solicitacao_id = v_meta.solicitacao_id
    and dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO'
  for update;

  if exists (
    select 1
    from f.documento_fiscal_emissao prod
    where prod.tenant_id = v_emissao.tenant_id
      and prod.empresa_id = v_emissao.empresa_id
      and prod.solicitacao_id = v_emissao.solicitacao_id
      and prod.ambiente = 'PRODUCAO'
      and prod.status <> 'CANCELADA'
  ) then
    raise exception using errcode = '55000', message = 'A homologacao nao pode ser cancelada depois que a promocao para producao foi iniciada.';
  end if;

  select ev.id, ev.status, ev.created_at, ev.justificativa
    into v_ultimo_cancelamento_id, v_ultimo_cancelamento_status,
         v_ultimo_cancelamento_em, v_ultimo_cancelamento_justificativa
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
    order by ev.created_at desc, ev.id desc
    limit 1;

  if v_ultimo_cancelamento_status = 'ENVIANDO'
     and v_ultimo_cancelamento_em >= now() - interval '2 minutes' then
    return jsonb_build_object(
      'deve_cancelar', false,
      'aguardar', true,
      'deve_reconciliar', false,
      'evento_claim_id', v_ultimo_cancelamento_id,
      'justificativa_claim', v_ultimo_cancelamento_justificativa,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', 'ENVIANDO'
    );
  end if;
  if v_ultimo_cancelamento_status = 'ENVIANDO' then
    if p_reconciliacao_claim_id is distinct from v_ultimo_cancelamento_id then
      return jsonb_build_object(
        'deve_cancelar', false,
        'aguardar', false,
        'deve_reconciliar', true,
        'evento_claim_id', v_ultimo_cancelamento_id,
        'justificativa_claim', v_ultimo_cancelamento_justificativa,
        'documento_fiscal_id', v_emissao.documento_fiscal_id,
        'referencia_externa', v_emissao.referencia_externa,
        'status', 'ENVIANDO'
      );
    end if;
    if v_ultimo_cancelamento_justificativa is distinct from v_justificativa then
      raise exception using
        errcode = '22023',
        message = 'A justificativa do retry deve ser a mesma do claim de cancelamento reconciliado.';
    end if;
  elsif p_reconciliacao_claim_id is not null then
    raise exception using
      errcode = '55000',
      message = 'O claim informado ja nao e o cancelamento pendente mais recente.';
  end if;
  if v_emissao.status <> 'AUTORIZADA' then
    raise exception using errcode = '55000', message = format('Status %s nao permite cancelamento da homologacao.', v_emissao.status);
  end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
    status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
    'CANCELAMENTO', v_justificativa, 'ENVIANDO',
    jsonb_build_object('claim_duravel', true, 'sem_promocao_concorrente', true),
    v_emissao.referencia_externa
  ) returning id into v_evento_claim_id;

  return jsonb_build_object(
    'deve_cancelar', true,
    'aguardar', false,
    'deve_reconciliar', false,
    'evento_claim_id', v_evento_claim_id,
    'justificativa_claim', v_justificativa,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', 'ENVIANDO'
  );
end;
$function$;

create or replace function f.fn_nfe_cancelamento_homologacao_finalizar(
  p_documento_fiscal_id uuid,
  p_evento_claim_id uuid,
  p_status text,
  p_justificativa text,
  p_protocolo text default null,
  p_resposta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_meta record;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_claim record;
  v_ultimo_cancelamento_id uuid;
  v_ultimo_cancelamento_status text;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode concluir o cancelamento.';
  end if;
  if v_status not in ('AUTORIZADA', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status final de cancelamento invalido.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa deve ter entre 15 e 255 caracteres.';
  end if;

  select dfe.tenant_id, dfe.empresa_id, dfe.solicitacao_id
    into v_meta
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de homologacao nao encontrada.';
  end if;

  perform 1
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_meta.tenant_id
    and sf.empresa_id = v_meta.empresa_id
    and sf.id = v_meta.solicitacao_id
  for update;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_meta.tenant_id
    and dfe.empresa_id = v_meta.empresa_id
    and dfe.solicitacao_id = v_meta.solicitacao_id
    and dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO'
  for update;

  if p_evento_claim_id is null then
    raise exception using errcode = '22023', message = 'O identificador do claim de cancelamento e obrigatorio.';
  end if;
  if v_emissao.status = 'CANCELADA' and v_status = 'AUTORIZADA' then
    if exists (
      select 1
      from f.documento_fiscal_evento ev
      where ev.tenant_id = v_emissao.tenant_id
        and ev.empresa_id = v_emissao.empresa_id
        and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
        and ev.tipo = 'CANCELAMENTO'
        and ev.status = 'AUTORIZADA'
        and ev.resposta->>'claim_evento_id' = p_evento_claim_id::text
    ) then
      return jsonb_build_object('ok', true, 'idempotente', true, 'status', 'CANCELADA');
    end if;
    raise exception using errcode = '55000', message = 'Resposta tardia pertence a outro claim de cancelamento.';
  end if;

  select ev.id, ev.status
    into v_ultimo_cancelamento_id, v_ultimo_cancelamento_status
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
    order by ev.created_at desc, ev.id desc
    limit 1;
  if v_emissao.status <> 'AUTORIZADA'
     or v_ultimo_cancelamento_status is distinct from 'ENVIANDO'
     or v_ultimo_cancelamento_id is distinct from p_evento_claim_id then
    raise exception using errcode = '55000', message = 'Cancelamento sem claim duravel correspondente.';
  end if;

  select ev.id, ev.justificativa
    into v_claim
  from f.documento_fiscal_evento ev
  where ev.tenant_id = v_emissao.tenant_id
    and ev.empresa_id = v_emissao.empresa_id
    and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
    and ev.id = p_evento_claim_id
    and ev.tipo = 'CANCELAMENTO'
    and ev.status = 'ENVIANDO';
  if not found or v_claim.justificativa is distinct from v_justificativa then
    raise exception using errcode = '22023', message = 'Justificativa ou claim de cancelamento nao corresponde a reserva original.';
  end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, protocolo,
    status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
    'CANCELAMENTO', v_justificativa, nullif(btrim(p_protocolo), ''),
    v_status,
    coalesce(p_resposta, '{}'::jsonb) || jsonb_build_object('claim_evento_id', p_evento_claim_id),
    v_emissao.referencia_externa
  );

  if v_status = 'AUTORIZADA' then
    update f.documento_fiscal_emissao dfe
    set status = 'CANCELADA',
        protocolo = coalesce(nullif(btrim(p_protocolo), ''), dfe.protocolo),
        resposta = coalesce(p_resposta, dfe.resposta),
        mensagem = 'Cancelamento autorizado.',
        updated_at = now()
    where dfe.tenant_id = v_emissao.tenant_id
      and dfe.empresa_id = v_emissao.empresa_id
      and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;

    update f.documento_fiscal df
    set nfe_status = 'CANCELADA', updated_at = now()
    where df.tenant_id = v_emissao.tenant_id
      and df.empresa_id = v_emissao.empresa_id
      and df.id = v_emissao.documento_fiscal_id;

    update f.solicitacao_faturamento sf
    set status = 'CANCELADA', updated_at = now()
    where sf.tenant_id = v_emissao.tenant_id
      and sf.empresa_id = v_emissao.empresa_id
      and sf.id = v_emissao.solicitacao_id;
  else
    update f.documento_fiscal_emissao dfe
    set resposta = coalesce(p_resposta, dfe.resposta),
        mensagem = 'Cancelamento nao autorizado; NF-e de homologacao permanece autorizada.',
        updated_at = now()
    where dfe.tenant_id = v_emissao.tenant_id
      and dfe.empresa_id = v_emissao.empresa_id
      and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;

  return jsonb_build_object(
    'ok', v_status = 'AUTORIZADA',
    'idempotente', false,
    'status', case when v_status = 'AUTORIZADA' then 'CANCELADA' else 'AUTORIZADA' end
  );
end;
$function$;

comment on function f.fn_nfe_cancelamento_homologacao_claim(uuid, text, uuid) is
  'Serializa cancelamento HOM com promocao PROD; claim stale exige GET Focus e correlacao antes de permitir novo DELETE.';
comment on function f.fn_nfe_cancelamento_homologacao_finalizar(uuid, uuid, text, text, text, jsonb) is
  'Finaliza somente o claim HOM mais recente e correlacionado; cancela localmente apenas no sucesso confirmado.';
revoke all on function f.fn_nfe_cancelamento_homologacao_claim(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function f.fn_nfe_cancelamento_homologacao_finalizar(uuid, uuid, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function f.fn_nfe_cancelamento_homologacao_claim(uuid, text, uuid)
  to service_role;
grant execute on function f.fn_nfe_cancelamento_homologacao_finalizar(uuid, uuid, text, text, text, jsonb)
  to service_role;

create or replace function f.trg_nfe_bloquear_producao_cancelamento_hom_pendente()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_status text;
begin
  if new.ambiente <> 'PRODUCAO' or new.status = 'CANCELADA' or new.solicitacao_id is null then
    return new;
  end if;

  select ev.status into v_status
  from f.documento_fiscal_emissao hom
  join f.documento_fiscal_evento ev
    on ev.tenant_id = hom.tenant_id
   and ev.empresa_id = hom.empresa_id
   and ev.documento_fiscal_id = hom.documento_fiscal_id
   and ev.tipo = 'CANCELAMENTO'
  where hom.tenant_id = new.tenant_id
    and hom.empresa_id = new.empresa_id
    and hom.solicitacao_id = new.solicitacao_id
    and hom.ambiente = 'HOMOLOGACAO'
  order by ev.created_at desc, ev.id desc
  limit 1;

  if v_status = 'ENVIANDO' then
    raise exception using
      errcode = '55000',
      message = 'Promocao bloqueada: o cancelamento da homologacao esta em andamento.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_nfe_bloquear_producao_cancelamento_hom_pendente
  on f.documento_fiscal_emissao;
create trigger trg_nfe_bloquear_producao_cancelamento_hom_pendente
before insert or update of ambiente, status, solicitacao_id
on f.documento_fiscal_emissao
for each row execute function f.trg_nfe_bloquear_producao_cancelamento_hom_pendente();

revoke all on function f.trg_nfe_bloquear_producao_cancelamento_hom_pendente()
  from public, anon, authenticated;

create or replace function f.fn_solicitacao_nfe_cancelar_rascunho(
  p_solicitacao_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_emissoes_canceladas integer := 0;
  v_documentos_cancelados integer := 0;
  v_origem record;
begin
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de NF-e nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para cancelar esta solicitacao.';
  end if;
  if char_length(v_motivo) < 15 or char_length(v_motivo) > 255 then
    raise exception using errcode = '22023', message = 'O motivo deve ter entre 15 e 255 caracteres.';
  end if;

  -- Nunca trate uma tentativa real como mero rascunho, independentemente de
  -- estar ENVIANDO, PROCESSANDO, REJEITADA ou ERRO.
  if exists (
    select 1
    from f.documento_fiscal_emissao prod
    where prod.tenant_id = v_sf.tenant_id
      and prod.empresa_id = v_sf.empresa_id
      and prod.solicitacao_id = v_sf.id
      and prod.ambiente = 'PRODUCAO'
      and prod.status <> 'CANCELADA'
  ) then
    raise exception using
      errcode = '55000',
      message = 'A solicitacao possui emissao de PRODUCAO e nao pode ser cancelada pelo fluxo de rascunho.';
  end if;
  if v_sf.status = 'CANCELADA' then
    return jsonb_build_object(
      'ok', true,
      'idempotente', true,
      'solicitacao_id', v_sf.id,
      'status', 'CANCELADA'
    );
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Somente uma solicitacao editavel pode ser cancelada por este fluxo.';
  end if;
  -- A unica emissao descartavel localmente e HOM RASCUNHO nunca claimada.
  -- REJEITADA/ERRO podem representar uma referencia que chegou ao provedor;
  -- sem GET conclusivo jamais devolvem reserva/saldo por este atalho.
  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.ambiente = 'HOMOLOGACAO'
      and (
        dfe.status not in ('RASCUNHO', 'CANCELADA')
        or (
          dfe.status = 'RASCUNHO'
          and (
            dfe.tentativa_count <> 0
            or dfe.payload_enviado is not null
            or dfe.enviado_em is not null
            or dfe.ultima_tentativa_em is not null
          )
        )
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'A solicitacao possui tentativa fiscal; reconcilie/cancele pelo fluxo proprio antes de devolver o saldo.';
  end if;

  for v_origem in
    select distinct si.origem_id::integer as origem_id
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id ~ '^[0-9]+$'
    order by si.origem_id::integer
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      format('faturamento-parcial:%s:%s:%s', v_sf.tenant_id, v_sf.empresa_id, v_origem.origem_id),
      0
    ));
  end loop;

  with canceladas as (
    update f.documento_fiscal_emissao dfe
    set status = 'CANCELADA',
        mensagem = 'Solicitacao cancelada localmente antes de qualquer autorizacao.',
        updated_at = now()
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.ambiente = 'HOMOLOGACAO'
      and dfe.status = 'RASCUNHO'
      and dfe.tentativa_count = 0
      and dfe.payload_enviado is null
      and dfe.enviado_em is null
      and dfe.ultima_tentativa_em is null
    returning dfe.documento_fiscal_id, dfe.tenant_id, dfe.empresa_id, dfe.referencia_externa
  ), eventos as (
    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
      status, resposta, referencia_externa
    )
    select
      c.documento_fiscal_id, c.tenant_id, c.empresa_id, 'CANCELAMENTO', v_motivo,
      'LOCAL', jsonb_build_object('origem', 'RASCUNHO', 'sem_chamada_sefaz', true), c.referencia_externa
    from canceladas c
    returning documento_fiscal_id
  )
  select count(*) into v_emissoes_canceladas from eventos;

  with documentos as (
    update f.documento_fiscal df
    set nfe_status = 'CANCELADA', updated_at = now()
    where df.tenant_id = v_sf.tenant_id
      and df.empresa_id = v_sf.empresa_id
      and df.id in (
        select dfe.documento_fiscal_id
        from f.documento_fiscal_emissao dfe
        where dfe.tenant_id = v_sf.tenant_id
          and dfe.empresa_id = v_sf.empresa_id
          and dfe.solicitacao_id = v_sf.id
          and dfe.ambiente = 'HOMOLOGACAO'
          and dfe.status = 'CANCELADA'
      )
      and df.nfe_status = 'RASCUNHO'
    returning df.id
  )
  select count(*) into v_documentos_cancelados from documentos;

  update f.solicitacao_faturamento sf
  set status = 'CANCELADA',
      observacao = concat_ws(E'\n', nullif(btrim(sf.observacao), ''), 'Cancelada antes da autorizacao: ' || v_motivo),
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  return jsonb_build_object(
    'ok', true,
    'idempotente', false,
    'solicitacao_id', v_sf.id,
    'status', 'CANCELADA',
    'emissoes_canceladas', v_emissoes_canceladas,
    'documentos_cancelados', v_documentos_cancelados
  );
end;
$function$;

comment on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text) is
  'Cancela apenas solicitacao sem emissao ou HOM RASCUNHO nunca tentada; qualquer claim/tentativa ou PROD exige reconciliacao/tratamento fiscal proprio.';
revoke all on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text)
  from public, anon;
grant execute on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text)
  to authenticated, service_role;

do $block$
declare v_tabela text;
begin
  foreach v_tabela in array array[
    'f.solicitacao_faturamento',
    'f.solicitacao_item',
    'f.documento_fiscal_emissao'
  ] loop
    if has_table_privilege('authenticated', v_tabela, 'INSERT')
       or has_table_privilege('authenticated', v_tabela, 'UPDATE')
       or has_table_privilege('authenticated', v_tabela, 'DELETE') then
      raise exception 'ACL insegura: authenticated ainda possui DML em %.', v_tabela;
    end if;
    if not has_table_privilege('authenticated', v_tabela, 'SELECT') then
      raise exception 'ACL invalida: authenticated precisa manter SELECT em %.', v_tabela;
    end if;
  end loop;
end;
$block$;

notify pgrst, 'reload schema';

commit;
