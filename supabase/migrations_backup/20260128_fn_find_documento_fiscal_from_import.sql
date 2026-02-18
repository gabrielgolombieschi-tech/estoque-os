begin;

create or replace function f.fn_find_documento_fiscal_from_import(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_nf_entrada_id bigint,
  p_chave_acesso text
)
returns uuid
language plpgsql
security definer
set search_path = f, public, a, c, extensions
set row_security to off
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_doc_id uuid;
  v_competencia date;
  v_xml_hash text;
begin
  -- ✅ permite SQL Editor (postgres/service_role), mas mantém segurança no app
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

  -- Upsert documento fiscal (não gera título/AP aqui)
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

revoke all on function f.fn_find_documento_fiscal_from_import(uuid, uuid, bigint, text) from public;
grant execute on function f.fn_find_documento_fiscal_from_import(uuid, uuid, bigint, text) to authenticated;

commit;

