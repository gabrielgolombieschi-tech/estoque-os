begin;

create or replace function public.fn_clientes_cadastro_candidatos(
  p_tenant_id uuid,
  p_data_referencia date default current_date
)
returns table (
  id integer,
  tenant_id uuid,
  empresa_id uuid,
  nome text,
  documento text,
  cidade text,
  uf text,
  codigo_ibge_municipio text,
  ibge_matches integer,
  ibge_sugerido text,
  indicador_ie text,
  indicador_sugerido text,
  indicador_regra text
)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $function$
  with movimento as (
    select os.tenant_id, os.empresa_id, os.cliente_id
    from public.ordens_servico os
    where os.tenant_id = p_tenant_id
      and os.cliente_id is not null
      and os.data_abertura >= p_data_referencia - interval '12 months'
      and os.data_abertura < p_data_referencia + interval '1 day'
      and lower(coalesce(os.status, '')) <> 'cancelada'
      and coalesce(os.tipo_documento, 'OS') in ('OS', 'OV')
    union
    select df.tenant_id, df.empresa_id, df.cliente_id
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id
      and df.cliente_id is not null
      and df.deleted_at is null
      and df.operacao = 'SAIDA'
      and df.emissao_date >= p_data_referencia - interval '12 months'
      and df.emissao_date < p_data_referencia + interval '1 day'
  ), base as (
    select c.id, c.tenant_id, c.empresa_id, c.nome, c.documento,
      c.cidade, c.uf, c.inscricao_estadual, c.indicador_ie,
      c.codigo_ibge_municipio,
      public.normalizar_nome_municipio(c.cidade) as cidade_normalizada,
      upper(btrim(coalesce(c.uf, ''))) as uf_normalizada,
      regexp_replace(coalesce(c.documento, ''), '[^0-9]', '', 'g') as documento_digitos,
      btrim(coalesce(c.inscricao_estadual, '')) as ie_normalizada
    from public.clientes c
    join movimento m
      on m.tenant_id = c.tenant_id
     and m.empresa_id = c.empresa_id
     and m.cliente_id = c.id
    where c.tenant_id = p_tenant_id
      and c.ativo is true
  )
  select b.id, b.tenant_id, b.empresa_id, b.nome, b.documento, b.cidade, b.uf,
    b.codigo_ibge_municipio,
    count(mi.codigo_ibge)::integer as ibge_matches,
    min(mi.codigo_ibge) as ibge_sugerido,
    b.indicador_ie,
    case
      when b.ie_normalizada ~ '^[0-9]+$' then '1'
      when upper(b.ie_normalizada) = 'ISENTO' then '2'
      when length(b.documento_digitos) = 11 and b.ie_normalizada = '' then '9'
      else null
    end as indicador_sugerido,
    case
      when b.ie_normalizada ~ '^[0-9]+$' then 'IE numerica preenchida'
      when upper(b.ie_normalizada) = 'ISENTO' then 'IE literal ISENTO'
      when length(b.documento_digitos) = 11 and b.ie_normalizada = '' then 'Pessoa fisica sem IE'
      else null
    end as indicador_regra
  from base b
  left join public.municipios_ibge mi
    on mi.uf = b.uf_normalizada
   and (
     mi.nome_normalizado = b.cidade_normalizada
     or (
       btrim(coalesce(b.cidade, '')) ~ '^[0-9]{7}$'
       and mi.codigo_ibge = btrim(b.cidade)
     )
   )
  group by b.id, b.tenant_id, b.empresa_id, b.nome, b.documento,
    b.cidade, b.uf, b.codigo_ibge_municipio, b.indicador_ie,
    b.documento_digitos, b.ie_normalizada;
$function$;

create or replace function public.fn_clientes_ibge_legado_codigo_cidade(
  p_tenant_id uuid,
  p_data_referencia date default current_date,
  p_aplicar boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $function$
declare
  v_elegiveis integer;
  v_aplicados integer := 0;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Apenas service_role pode corrigir o legado de municipio.';
  end if;

  select count(*)::integer into v_elegiveis
  from public.fn_clientes_cadastro_candidatos(p_tenant_id, p_data_referencia) t
  join public.municipios_ibge mi
    on mi.codigo_ibge = t.ibge_sugerido
   and mi.uf = upper(btrim(t.uf))
  where btrim(coalesce(t.cidade, '')) ~ '^[0-9]{7}$'
    and t.ibge_matches = 1;

  if p_aplicar then
    update public.clientes c
       set cidade = mi.nome,
           codigo_ibge_municipio = coalesce(c.codigo_ibge_municipio, mi.codigo_ibge),
           atualizado_em = now()
      from public.fn_clientes_cadastro_candidatos(p_tenant_id, p_data_referencia) t
      join public.municipios_ibge mi
        on mi.codigo_ibge = t.ibge_sugerido
       and mi.uf = upper(btrim(t.uf))
     where c.id = t.id
       and c.tenant_id = t.tenant_id
       and c.empresa_id = t.empresa_id
       and btrim(coalesce(t.cidade, '')) ~ '^[0-9]{7}$'
       and t.ibge_matches = 1;
    get diagnostics v_aplicados = row_count;
  end if;

  return jsonb_build_object(
    'elegiveis', v_elegiveis,
    'aplicados', v_aplicados,
    'aplicado', p_aplicar
  );
end;
$function$;

revoke all on function public.fn_clientes_ibge_legado_codigo_cidade(uuid, date, boolean)
  from public, anon, authenticated;
grant execute on function public.fn_clientes_ibge_legado_codigo_cidade(uuid, date, boolean)
  to service_role;

commit;
