create or replace function f.contas_pagar_receber_listar_v3(
  p_tenant_id uuid,
  p_empresa_ids uuid[],
  p_data_inicio date,
  p_data_fim date
)
returns table (
  empresa_id uuid,
  tipo text,
  nf_numero text,
  titulo_id uuid,
  parcela_id uuid,
  parcela_numero text,
  total_parcelas bigint,
  emissao_date date,
  vencimento_date date,
  pessoa_nome text,
  descricao text,
  motivo_codigo text,
  motivo_nome text,
  aprovado_por_nome text,
  valor numeric,
  valor_aberto numeric,
  titulo_status text,
  formas_aplicadas text[],
  formas_agendadas text[],
  contas_aplicadas text[],
  contas_agendadas text[],
  pagamento_import_json jsonb
)
language sql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  select
    lista.empresa_id,
    lista.tipo,
    lista.nf_numero,
    lista.titulo_id,
    lista.parcela_id,
    lista.parcela_numero,
    coalesce(
      nullif(titulo.total_parcelas_serie, 0)::bigint,
      (
        select count(*)
        from f.titulo_parcela parcela_total
        where parcela_total.tenant_id = p_tenant_id
          and parcela_total.titulo_id = lista.titulo_id
          and parcela_total.deleted_at is null
      )
    ) as total_parcelas,
    lista.emissao_date,
    lista.vencimento_date,
    lista.pessoa_nome,
    lista.descricao,
    lista.motivo_codigo,
    lista.motivo_nome,
    lista.aprovado_por_nome,
    lista.valor,
    lista.valor_aberto,
    lista.titulo_status,
    lista.formas_aplicadas,
    lista.formas_agendadas,
    lista.contas_aplicadas,
    lista.contas_agendadas,
    lista.pagamento_import_json
  from f.contas_pagar_receber_listar_v2(
    p_tenant_id,
    p_empresa_ids,
    p_data_inicio,
    p_data_fim
  ) as lista
  join f.titulo titulo
    on titulo.id = lista.titulo_id
   and titulo.tenant_id = p_tenant_id
   and titulo.empresa_id = lista.empresa_id
   and titulo.deleted_at is null
  where lista.empresa_id = any(p_empresa_ids)
  order by lista.vencimento_date, lista.tipo, lista.pessoa_nome;
$$;

revoke all on function f.contas_pagar_receber_listar_v3(uuid, uuid[], date, date) from public;
revoke all on function f.contas_pagar_receber_listar_v3(uuid, uuid[], date, date) from anon;
grant execute on function f.contas_pagar_receber_listar_v3(uuid, uuid[], date, date)
  to authenticated, service_role;

comment on function f.contas_pagar_receber_listar_v3(uuid, uuid[], date, date) is
  'Lista AP/AR multiempresa com total de parcelas da série completa, mesmo fora do período filtrado.';
