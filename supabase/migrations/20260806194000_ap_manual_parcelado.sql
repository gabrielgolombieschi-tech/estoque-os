do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_plano_contas_id uuid;
begin
  select pc.id
    into v_plano_contas_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_FINANCIAMENTO'
    and pc.deleted_at is null
  limit 1;

  if v_plano_contas_id is not null
     and not exists (
       select 1
       from f.motivo_compra mc
       where mc.tenant_id = v_tenant_id
         and mc.codigo = 'EMPRESTIMO_CAPITAL_GIRO'
         and mc.deleted_at is null
     ) then
    insert into f.motivo_compra (
      tenant_id,
      codigo,
      nome,
      aplica_em,
      plano_contas_id,
      requires_text,
      requires_os,
      ativo,
      favorito,
      ordem,
      visivel_import_nfe,
      created_at,
      updated_at
    ) values (
      v_tenant_id,
      'EMPRESTIMO_CAPITAL_GIRO',
      'EMPRÉSTIMO / CAPITAL DE GIRO',
      'AMBOS',
      v_plano_contas_id,
      false,
      false,
      true,
      true,
      100,
      false,
      now(),
      now()
    );
  end if;
end;
$$;

create or replace function f.criar_titulo_ap_manual_parcelado_v1(
  p_descricao text,
  p_primeiro_vencimento date,
  p_valor_parcela numeric,
  p_quantidade_parcelas integer,
  p_fornecedor_id integer default null,
  p_motivo_compra_id uuid default null,
  p_emissao_date date default null,
  p_change_reason text default null
)
returns table (titulo_id uuid)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;
  v_titulo_id uuid;
  v_emissao date;
  v_valor_total numeric(15, 2);
  v_dia_vencimento integer;
  v_indice integer;
  v_vencimento date;
begin
  if p_descricao is null or length(trim(p_descricao)) = 0 then
    raise exception 'Descrição obrigatória';
  end if;

  if p_primeiro_vencimento is null then
    raise exception 'Primeiro vencimento obrigatório';
  end if;

  if p_valor_parcela is null or p_valor_parcela <= 0 then
    raise exception 'Valor da parcela deve ser maior que zero';
  end if;

  if p_quantidade_parcelas is null
     or p_quantidade_parcelas < 2
     or p_quantidade_parcelas > 120 then
    raise exception 'Quantidade de parcelas deve estar entre 2 e 120';
  end if;

  if auth.uid() is null
     and current_user not in ('postgres', 'service_role') then
    raise exception 'Usuário não autenticado';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Tenant e empresa devem estar selecionados';
  end if;

  if auth.uid() is not null
     and not f.has_finance_access(v_tenant_id, v_empresa_id) then
    raise exception 'Sem permissão financeira';
  end if;

  if p_fornecedor_id is not null
     and not exists (
       select 1
       from public.fornecedores fornecedor
       where fornecedor.id = p_fornecedor_id
         and fornecedor.tenant_id = v_tenant_id
         and fornecedor.empresa_id = v_empresa_id
         and fornecedor.ativo = true
     ) then
    raise exception 'Fornecedor inválido para a empresa selecionada';
  end if;

  if p_motivo_compra_id is not null
     and not exists (
       select 1
       from f.motivo_compra motivo
       where motivo.id = p_motivo_compra_id
         and motivo.tenant_id = v_tenant_id
         and motivo.ativo = true
         and motivo.deleted_at is null
     ) then
    raise exception 'Motivo inválido para o tenant selecionado';
  end if;

  v_usuario_id := a.fn_current_usuario_id();
  v_emissao := coalesce(p_emissao_date, p_primeiro_vencimento);
  v_valor_total := round(p_valor_parcela * p_quantidade_parcelas, 2);
  v_dia_vencimento := extract(day from p_primeiro_vencimento)::integer;

  if exists (
    select 1
    from f.titulo titulo
    where titulo.tenant_id = v_tenant_id
      and titulo.empresa_id = v_empresa_id
      and titulo.tipo = 'AP'
      and titulo.origem = 'MANUAL'
      and titulo.descricao = trim(p_descricao)
      and titulo.emissao_date = v_emissao
      and titulo.valor_total = v_valor_total
      and titulo.deleted_at is null
  ) then
    raise exception 'Já existe um AP parcelado com esta descrição, emissão e valor total';
  end if;

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
    total_parcelas_serie,
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
    f._month_first(v_emissao),
    v_valor_total,
    v_valor_total,
    p_motivo_compra_id,
    p_quantidade_parcelas,
    now(),
    now(),
    v_usuario_id,
    v_usuario_id,
    null
  ) returning id into v_titulo_id;

  for v_indice in 1..p_quantidade_parcelas loop
    v_vencimento := f._safe_day_in_month(
      f._month_first((p_primeiro_vencimento + ((v_indice - 1) || ' months')::interval)::date),
      v_dia_vencimento
    );

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
      lpad(v_indice::text, 3, '0'),
      v_vencimento,
      round(p_valor_parcela, 2),
      round(p_valor_parcela, 2),
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    );
  end loop;

  return query select v_titulo_id;
end;
$$;

revoke all on function f.criar_titulo_ap_manual_parcelado_v1(text, date, numeric, integer, integer, uuid, date, text)
  from public;
revoke all on function f.criar_titulo_ap_manual_parcelado_v1(text, date, numeric, integer, integer, uuid, date, text)
  from anon;
grant execute on function f.criar_titulo_ap_manual_parcelado_v1(text, date, numeric, integer, integer, uuid, date, text)
  to authenticated, service_role;

comment on function f.criar_titulo_ap_manual_parcelado_v1(text, date, numeric, integer, integer, uuid, date, text) is
  'Cria AP manual com parcelas mensais, respeitando tenant, empresa ativa e acesso financeiro.';
