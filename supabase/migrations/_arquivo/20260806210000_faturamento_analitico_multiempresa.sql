begin;

create or replace function f.faturamento_analitico_documentos(
  p_tenant_id uuid,
  p_empresa_ids uuid[],
  p_data_inicio date,
  p_data_fim_exclusiva date
)
returns table (
  id uuid,
  emissao_date date,
  competencia_date date,
  empresa_id uuid,
  cliente_id integer,
  cliente_nome text,
  valor_total numeric,
  modelo text,
  nfe_status text,
  nfse_status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $function$
declare
  v_empresa_ids uuid[];
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null
     or p_empresa_ids is null
     or cardinality(p_empresa_ids) = 0
     or p_data_inicio is null
     or p_data_fim_exclusiva is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id, empresas e periodo sao obrigatorios';
  end if;

  if public.current_tenant_id() is distinct from p_tenant_id then
    raise exception using
      errcode = '42501',
      message = 'Tenant informado nao corresponde ao contexto ativo';
  end if;

  if p_data_fim_exclusiva <= p_data_inicio
     or p_data_fim_exclusiva > (p_data_inicio + interval '20 years')::date then
    raise exception using
      errcode = '22023',
      message = 'Periodo invalido para o analitico de faturamento';
  end if;

  select array_agg(distinct requested.empresa_id order by requested.empresa_id)
    into v_empresa_ids
  from unnest(p_empresa_ids) as requested(empresa_id)
  where requested.empresa_id is not null;

  if v_empresa_ids is null or cardinality(v_empresa_ids) = 0 then
    raise exception using
      errcode = '22023',
      message = 'Informe ao menos uma empresa valida';
  end if;

  if exists (
    select 1
    from unnest(v_empresa_ids) as requested(empresa_id)
    left join c.empresa empresa
      on empresa.id = requested.empresa_id
     and empresa.tenant_id = p_tenant_id
     and empresa.deleted_at is null
    where empresa.id is null
       or not f.has_finance_access(p_tenant_id, requested.empresa_id)
  ) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para uma ou mais empresas solicitadas';
  end if;

  return query
  select
    documento.id,
    documento.emissao_date,
    documento.competencia_date,
    documento.empresa_id,
    documento.cliente_id,
    cliente.nome::text as cliente_nome,
    documento.valor_total::numeric,
    documento.modelo,
    documento.nfe_status,
    documento.nfse_status,
    documento.created_at
  from f.documento_fiscal documento
  left join public.clientes cliente
    on cliente.id = documento.cliente_id
   and cliente.tenant_id = documento.tenant_id
  where documento.tenant_id = p_tenant_id
    and documento.empresa_id = any(v_empresa_ids)
    and documento.operacao = 'SAIDA'
    and documento.deleted_at is null
    and documento.emissao_date >= p_data_inicio
    and documento.emissao_date < p_data_fim_exclusiva
  order by documento.emissao_date, documento.created_at, documento.id;
end;
$function$;

comment on function f.faturamento_analitico_documentos(uuid, uuid[], date, date) is
  'Retorna documentos de saida do analitico para empresas autorizadas sem alterar o contexto ativo compartilhado.';

revoke all on function f.faturamento_analitico_documentos(uuid, uuid[], date, date) from public;
revoke all on function f.faturamento_analitico_documentos(uuid, uuid[], date, date) from anon;
grant execute on function f.faturamento_analitico_documentos(uuid, uuid[], date, date) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
