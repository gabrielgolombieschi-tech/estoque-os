begin;

-- O payload autorizado e a fonte do snapshot historico. Esta funcao nao consulta
-- o cadastro fiscal do item, portanto uma alteracao posterior nao reescreve a NF-e.
create or replace function f.fn_nfe_sincronizar_snapshot_autorizado(
  p_documento_fiscal_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_documento f.documento_fiscal%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_imposto text;
  v_base numeric;
  v_valor numeric;
  v_aliquota numeric;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode congelar o snapshot autorizado.';
  end if;

  select * into v_documento
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Documento fiscal nao encontrado para congelar o snapshot.';
  end if;

  select * into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id;
  if not found or v_emissao.status <> 'AUTORIZADA' then
    raise exception using errcode = '22023', message = 'O snapshot fiscal so pode ser congelado depois da autorizacao.';
  end if;
  if jsonb_typeof(p_payload->'items') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Payload autorizado sem lista de itens.';
  end if;

  update f.documento_fiscal_item dfi
  set cst_ibs_cbs = nullif(x.item->>'ibs_cbs_situacao_tributaria', ''),
      cclass_trib = nullif(x.item->>'ibs_cbs_classificacao_tributaria', ''),
      cclass_trib_versao = si.cclass_trib_versao,
      ibs_cbs_json = jsonb_strip_nulls(jsonb_build_object(
        'base_calculo', nullif(x.item->>'ibs_cbs_base_calculo', '')::numeric,
        'ibs_uf_aliquota', nullif(x.item->>'ibs_uf_aliquota', '')::numeric,
        'ibs_uf_valor', nullif(x.item->>'ibs_uf_valor', '')::numeric,
        'ibs_mun_aliquota', nullif(x.item->>'ibs_mun_aliquota', '')::numeric,
        'ibs_mun_valor', nullif(x.item->>'ibs_mun_valor', '')::numeric,
        'ibs_valor_total', nullif(x.item->>'ibs_valor_total', '')::numeric,
        'cbs_aliquota', nullif(x.item->>'cbs_aliquota', '')::numeric,
        'cbs_valor', nullif(x.item->>'cbs_valor', '')::numeric,
        'valor_total_item', nullif(x.item->>'valor_total_item', '')::numeric
      )),
      snapshot_fiscal_em = coalesce(dfi.snapshot_fiscal_em, v_emissao.autorizado_em, now()),
      updated_at = now()
  from jsonb_array_elements(p_payload->'items') x(item)
  left join f.solicitacao_item si
    on si.tenant_id = v_emissao.tenant_id
   and si.empresa_id = v_emissao.empresa_id
   and si.solicitacao_id = v_emissao.solicitacao_id
   and si.ordem = (x.item->>'numero_item')::integer
  where dfi.tenant_id = v_emissao.tenant_id
    and dfi.empresa_id = v_emissao.empresa_id
    and dfi.documento_fiscal_id = p_documento_fiscal_id
    and dfi.item_n = (x.item->>'numero_item')::integer;

  -- documento_fiscal_imposto guarda o debito consolidado do documento. Quando
  -- ha mais de uma aliquota, registra a aliquota efetiva (valor/base).
  for v_imposto, v_base, v_valor, v_aliquota in
    with itens as (
      select item
      from jsonb_array_elements(p_payload->'items') x(item)
    ), tributos(imposto, base_chave, valor_chave, aliquota_chave) as (
      values
        ('ICMS'::text, 'icms_base_calculo'::text, 'icms_valor'::text, 'icms_aliquota'::text),
        ('IPI', 'ipi_base_calculo', 'ipi_valor', 'ipi_aliquota'),
        ('PIS', 'pis_base_calculo', 'pis_valor', 'pis_aliquota'),
        ('COFINS', 'cofins_base_calculo', 'cofins_valor', 'cofins_aliquota'),
        ('IBS', 'ibs_cbs_base_calculo', 'ibs_valor_total', null),
        ('CBS', 'ibs_cbs_base_calculo', 'cbs_valor', 'cbs_aliquota')
    )
    select t.imposto,
           round(coalesce(sum(coalesce(nullif(i.item->>t.base_chave, '')::numeric, 0)), 0), 2),
           round(coalesce(sum(coalesce(nullif(i.item->>t.valor_chave, '')::numeric, 0)), 0), 2),
           case
             when count(distinct nullif(i.item->>t.aliquota_chave, '')::numeric) = 1
               then max(nullif(i.item->>t.aliquota_chave, '')::numeric)
             when sum(coalesce(nullif(i.item->>t.base_chave, '')::numeric, 0)) > 0
               then round(
                 sum(coalesce(nullif(i.item->>t.valor_chave, '')::numeric, 0))
                 / sum(coalesce(nullif(i.item->>t.base_chave, '')::numeric, 0)) * 100,
                 4
               )
             else 0
           end
    from tributos t
    cross join itens i
    group by t.imposto, t.base_chave, t.valor_chave, t.aliquota_chave
  loop
    if coalesce(v_base, 0) > 0 or coalesce(v_valor, 0) > 0 then
      insert into f.documento_fiscal_imposto (
        tenant_id, documento_fiscal_id, imposto, natureza,
        base_original, deducoes, base_calculo, aliquota,
        valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
      ) values (
        v_emissao.tenant_id, p_documento_fiscal_id, v_imposto, 'DEBITO',
        v_base, 0, v_base, coalesce(v_aliquota, 0),
        v_valor, null, now(), now(), null
      )
      on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
      do update set
        base_original = excluded.base_original,
        deducoes = excluded.deducoes,
        base_calculo = excluded.base_calculo,
        aliquota = excluded.aliquota,
        valor_calculado = excluded.valor_calculado,
        valor_ajustado = null,
        updated_at = now(),
        deleted_at = null;
    end if;
  end loop;
end;
$function$;

revoke all on function f.fn_nfe_sincronizar_snapshot_autorizado(uuid, jsonb) from public, anon, authenticated;
grant execute on function f.fn_nfe_sincronizar_snapshot_autorizado(uuid, jsonb) to service_role;

create or replace function f.trg_nfe_snapshot_autorizado()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
begin
  if new.status = 'AUTORIZADA'
     and jsonb_typeof(new.payload_enviado->'items') = 'array' then
    perform f.fn_nfe_sincronizar_snapshot_autorizado(new.documento_fiscal_id, new.payload_enviado);
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_nfe_snapshot_autorizado on f.documento_fiscal_emissao;
create trigger trg_nfe_snapshot_autorizado
after insert or update of status, payload_enviado
on f.documento_fiscal_emissao
for each row execute function f.trg_nfe_snapshot_autorizado();

-- Backfill idempotente das autorizacoes obtidas antes desta migration.
do $block$
declare v_row record;
begin
  for v_row in
    select dfe.documento_fiscal_id, dfe.payload_enviado
    from f.documento_fiscal_emissao dfe
    where dfe.status = 'AUTORIZADA'
      and jsonb_typeof(dfe.payload_enviado->'items') = 'array'
  loop
    perform f.fn_nfe_sincronizar_snapshot_autorizado(v_row.documento_fiscal_id, v_row.payload_enviado);
  end loop;
end;
$block$;

-- RPC operacional somente-leitura para provar os efeitos de uma emissao sem
-- abrir SELECT direto nas tabelas privadas de XML e financeiro.
create or replace function f.fn_nfe_auditar_documento(p_documento_fiscal_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
  select jsonb_build_object(
    'documento', to_jsonb(df),
    'emissao', to_jsonb(dfe),
    'solicitacao', to_jsonb(sf),
    'itens', coalesce((
      select jsonb_agg(to_jsonb(dfi) order by dfi.item_n)
      from f.documento_fiscal_item dfi
      where dfi.tenant_id = df.tenant_id
        and dfi.documento_fiscal_id = df.id
        and dfi.deleted_at is null
    ), '[]'::jsonb),
    'xml', coalesce((
      select jsonb_build_object(
        'registros', count(*),
        'chave_acesso', min(x.chave_acesso),
        'tamanho_bytes', max(octet_length(x.xml_raw)),
        'xml_hash', min(x.xml_hash),
        'tem_protocolo_autorizacao', bool_or(x.xml_raw ~ '<([A-Za-z0-9_]+:)?protNFe[ >]'),
        'tem_ibs', bool_or(x.xml_raw ~ '<([A-Za-z0-9_]+:)?gIBS(UF|Mun)?[ >]'),
        'tem_cbs', bool_or(x.xml_raw ~ '<([A-Za-z0-9_]+:)?gCBS[ >]')
      )
      from f.documento_fiscal_xml x
      where x.tenant_id = df.tenant_id
        and x.documento_fiscal_id = df.id
        and x.deleted_at is null
    ), '{}'::jsonb),
    'titulos', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.created_at)
      from f.titulo t
      where t.tenant_id = df.tenant_id
        and t.empresa_id = df.empresa_id
        and t.documento_fiscal_id = df.id
        and t.deleted_at is null
    ), '[]'::jsonb),
    'impostos', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.imposto)
      from f.documento_fiscal_imposto i
      where i.tenant_id = df.tenant_id
        and i.documento_fiscal_id = df.id
        and i.deleted_at is null
    ), '[]'::jsonb),
    'movimentacoes_da_origem', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.created_at)
      from public.movimentacoes m
      where m.tenant_id = df.tenant_id
        and m.empresa_id = df.empresa_id
        and m.origem_os_id = df.os_id_import
        and exists (
          select 1 from f.documento_fiscal_item dfi
          where dfi.tenant_id = df.tenant_id
            and dfi.empresa_id = df.empresa_id
            and dfi.documento_fiscal_id = df.id
            and dfi.item_id = m.item_id
            and dfi.deleted_at is null
        )
    ), '[]'::jsonb),
    'eventos', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.created_at)
      from f.documento_fiscal_evento e
      where e.tenant_id = df.tenant_id
        and e.empresa_id = df.empresa_id
        and e.documento_fiscal_id = df.id
    ), '[]'::jsonb)
  )
  from f.documento_fiscal df
  join f.documento_fiscal_emissao dfe
    on dfe.tenant_id = df.tenant_id
   and dfe.empresa_id = df.empresa_id
   and dfe.documento_fiscal_id = df.id
  join f.solicitacao_faturamento sf
    on sf.tenant_id = dfe.tenant_id
   and sf.empresa_id = dfe.empresa_id
   and sf.id = dfe.solicitacao_id
  where df.id = p_documento_fiscal_id;
$function$;

revoke all on function f.fn_nfe_auditar_documento(uuid) from public, anon, authenticated;
grant execute on function f.fn_nfe_auditar_documento(uuid) to service_role;

commit;
