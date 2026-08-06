create or replace function f.contas_bancarias_saldos_ativos(
  p_tenant_id uuid,
  p_empresa_ids uuid[],
  p_data_inicio date,
  p_data_fim date,
  p_data_referencia date default current_date
)
returns table (
  empresa_id uuid,
  conta_bancaria_id uuid,
  conta_codigo text,
  conta_nome text,
  conta_tipo text,
  configurada boolean,
  saldo_referencia numeric,
  saldo_referencia_data date,
  saldo_referencia_motivo text,
  saldo_inicial_periodo numeric,
  entradas_periodo numeric,
  saidas_periodo numeric,
  transferencias_periodo numeric,
  saldo_atual numeric
)
language sql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  select
    saldos.empresa_id,
    saldos.conta_bancaria_id,
    saldos.conta_codigo,
    saldos.conta_nome,
    saldos.conta_tipo,
    saldos.configurada,
    saldos.saldo_referencia,
    saldos.saldo_referencia_data,
    saldos.saldo_referencia_motivo,
    saldos.saldo_inicial_periodo,
    saldos.entradas_periodo,
    saldos.saidas_periodo,
    saldos.transferencias_periodo,
    saldos.saldo_atual
  from f.contas_bancarias_saldos(
    p_tenant_id,
    p_empresa_ids,
    p_data_inicio,
    p_data_fim,
    p_data_referencia
  ) as saldos
  join f.conta_bancaria cb
    on cb.id = saldos.conta_bancaria_id
   and cb.tenant_id = p_tenant_id
   and cb.empresa_id = saldos.empresa_id
  where cb.empresa_id = any(p_empresa_ids)
    and cb.ativo = true
    and cb.deleted_at is null
  order by saldos.empresa_id, saldos.conta_nome, saldos.conta_codigo;
$$;

revoke all on function f.contas_bancarias_saldos_ativos(uuid, uuid[], date, date, date) from public;
revoke all on function f.contas_bancarias_saldos_ativos(uuid, uuid[], date, date, date) from anon;
grant execute on function f.contas_bancarias_saldos_ativos(uuid, uuid[], date, date, date)
  to authenticated, service_role;

comment on function f.contas_bancarias_saldos_ativos(uuid, uuid[], date, date, date) is
  'Saldos das contas bancarias ativas acessiveis no dashboard, com escopo de tenant e empresas.';
