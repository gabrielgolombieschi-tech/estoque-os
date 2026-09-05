-- O livro de notas de saida e o analitico so mostram documento fiscal que existe.
--
-- As emissoes de homologacao ficam em nfe_status = 'RASCUNHO' de proposito, mas
-- nada filtrava por isso: elas apareciam na tela /faturamento/nfe misturadas com
-- as notas reais e, pior, o analitico somava R$ 41.070,60 de notas de teste como
-- faturamento de agosto/setembro de 2026.
--
-- Criterio: nfe_status EMITIDA (gravado so pelo retorno de producao) ou
-- CANCELADA com numero (cancelamento autorizado na SEFAZ, documento que
-- existiu). Rascunho descartado tambem vira CANCELADA, mas nunca teve numero.

CREATE OR REPLACE FUNCTION f.faturamento_analitico_documentos(p_tenant_id uuid, p_empresa_ids uuid[], p_data_inicio date, p_data_fim_exclusiva date)
 RETURNS TABLE(id uuid, emissao_date date, competencia_date date, empresa_id uuid, cliente_id integer, cliente_nome text, valor_total numeric, modelo text, nfe_status text, nfse_status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'f', 'public', 'a', 'c'
 SET row_security TO 'off'
AS $function$
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
    -- Nota de homologacao nao e faturamento. O retorno de homologacao grava
    -- nfe_status = 'RASCUNHO' de proposito (f.fn_nfe_aplicar_retorno); so o
    -- retorno de producao grava 'EMITIDA'. Sem este filtro o analitico somava
    -- as notas de teste como receita. CANCELADA com numero continua entrando:
    -- foi cancelamento autorizado na SEFAZ e o documento existiu. Rascunho
    -- descartado tambem vira CANCELADA, porem sem numero.
    -- NFS-e nao usa nfe_status (fica nulo) e segue pelo nfse_status.
    and (
      documento.modelo = 'NFSE'
      or (
        documento.nfe_status in ('EMITIDA', 'CANCELADA')
        and documento.numero is not null
      )
    )
    and not exists (
      select 1
      from public.empresas empresa_destino
      where empresa_destino.tenant_id = documento.tenant_id
        and empresa_destino.id <> documento.empresa_id
        and regexp_replace(coalesce(empresa_destino.cnpj, ''), '[^0-9]', '', 'g') <> ''
        and regexp_replace(coalesce(empresa_destino.cnpj, ''), '[^0-9]', '', 'g') =
            regexp_replace(coalesce(cliente.documento_norm, cliente.documento, ''), '[^0-9]', '', 'g')
    )
  order by documento.emissao_date, documento.created_at, documento.id;
end;
$function$;
