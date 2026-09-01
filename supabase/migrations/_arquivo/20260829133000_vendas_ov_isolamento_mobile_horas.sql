-- Isolamento operacional: OV nao aparece nas RPCs do app e nao aceita horas.

create or replace function public.assert_documento_operacional_os(p_os_id integer)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  if not exists (
    select 1
    from public.ordens_servico as os
    where os.id = p_os_id
      and os.tenant_id = public.current_tenant_id()
      and os.empresa_id = public.current_empresa_id()
      and os.tipo_documento = 'OS'
  ) then
    raise exception 'ordem_servico_operacional_not_found';
  end if;
end;
$$;

create or replace function public.fn_bloquear_horas_em_ov()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  if exists (
    select 1
    from public.ordens_servico as documento
    where documento.id = new.os_id
      and documento.tenant_id = new.tenant_id
      and documento.empresa_id = new.empresa_id
      and documento.tipo_documento = 'OV'
  ) then
    raise exception 'Venda (OV) nao aceita lancamento de horas. Converta a venda em OS antes de apontar horas.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_apontamentos_horas_bloquear_ov on public.apontamentos_horas;
create trigger trg_apontamentos_horas_bloquear_ov
before insert or update of os_id, tenant_id, empresa_id
on public.apontamentos_horas
for each row execute function public.fn_bloquear_horas_em_ov();

drop trigger if exists trg_hh_lancamentos_bloquear_ov on public.hh_lancamentos;
create trigger trg_hh_lancamentos_bloquear_ov
before insert or update of os_id, tenant_id, empresa_id
on public.hh_lancamentos
for each row execute function public.fn_bloquear_horas_em_ov();

create or replace function public.gerar_relatorio_hh_os(
  p_os_id integer,
  p_periodo_inicio date,
  p_periodo_fim date
)
returns table (relatorio_id bigint, total numeric)
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_tipo_documento text;
begin
  select os.tenant_id, os.empresa_id, os.tipo_documento
    into v_tenant_id, v_empresa_id, v_tipo_documento
  from public.ordens_servico as os
  where os.id = p_os_id;

  if not found or v_tipo_documento <> 'OS' then
    raise exception 'ordem_servico_not_found';
  end if;
  if v_empresa_id is distinct from public.current_empresa_id__by_tenant(v_tenant_id)
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'not_allowed';
  end if;

  return query
  select relatorio.relatorio_id, relatorio.total
  from public.gerar_relatorio_hh_os_unscoped_20260810(
    p_os_id, p_periodo_inicio, p_periodo_fim
  ) as relatorio;
end;
$$;

-- Preserva as implementacoes atuais e aplica o filtro em wrappers pequenos.
alter function public.app_listar_os(boolean, text)
  rename to app_listar_os_unfiltered_ov_20260829;

create function public.app_listar_os(
  p_incluir_fechadas boolean default false,
  p_busca text default null
)
returns table (
  id integer,
  numero_os varchar,
  os_num bigint,
  cliente_nome varchar,
  descricao_servico text,
  status varchar,
  usa_relatorio_hh boolean,
  data_abertura timestamp without time zone,
  sou_responsavel boolean,
  total_horas numeric,
  responsavel_nome text,
  situacao_margem text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  return query
  select base.*
  from public.app_listar_os_unfiltered_ov_20260829(p_incluir_fechadas, p_busca) as base
  join public.ordens_servico as os
    on os.id = base.id
   and os.tenant_id = public.current_tenant_id()
   and os.empresa_id = public.current_empresa_id()
   and os.tipo_documento = 'OS';
end;
$$;

alter function public.app_listar_os_fluxo(text, text)
  rename to app_listar_os_fluxo_unfiltered_ov_20260829;

create function public.app_listar_os_fluxo(
  p_status_fluxo text default 'em_andamento',
  p_busca text default null
)
returns table (
  id integer,
  numero_os varchar,
  os_num bigint,
  cliente_nome varchar,
  descricao_servico text,
  status_legado varchar,
  status_fluxo text,
  usa_relatorio_hh boolean,
  total_horas numeric,
  responsavel_nome text,
  situacao_margem text,
  sou_responsavel boolean,
  pendencias_aprovacao integer,
  garantia_motivo text,
  faturado_em timestamptz,
  faturada_presumida_legado boolean,
  pode_concluir boolean,
  pode_faturar boolean,
  pode_reabrir_garantia boolean,
  pode_concluir_garantia boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  return query
  select base.*
  from public.app_listar_os_fluxo_unfiltered_ov_20260829(p_status_fluxo, p_busca) as base
  join public.ordens_servico as os
    on os.id = base.id
   and os.tenant_id = public.current_tenant_id()
   and os.empresa_id = public.current_empresa_id()
   and os.tipo_documento = 'OS';
end;
$$;

alter function public.app_listar_materiais_os(integer)
  rename to app_listar_materiais_os_unfiltered_ov_20260829;

create function public.app_listar_materiais_os(p_os_id integer)
returns table (
  id integer,
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade numeric,
  observacoes text,
  registrado_por_nome text,
  criado_em timestamp without time zone,
  nao_cobrado boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  perform public.assert_documento_operacional_os(p_os_id);
  return query
  select * from public.app_listar_materiais_os_unfiltered_ov_20260829(p_os_id);
end;
$$;

alter function public.app_resumo_materiais_os(integer)
  rename to app_resumo_materiais_os_unfiltered_ov_20260829;

create function public.app_resumo_materiais_os(p_os_id integer)
returns table (itens_lancados bigint, valor_total numeric, pode_ver_valores boolean)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  perform public.assert_documento_operacional_os(p_os_id);
  return query
  select * from public.app_resumo_materiais_os_unfiltered_ov_20260829(p_os_id);
end;
$$;

alter function public.app_lancar_material_os(integer, text, numeric, text)
  rename to app_lancar_material_os_unfiltered_ov_20260829;

create function public.app_lancar_material_os(
  p_os_id integer,
  p_codigo text,
  p_quantidade numeric,
  p_observacao text default null
)
returns table (
  os_item_id integer,
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade numeric,
  saldo_restante numeric,
  nao_cobrado boolean,
  custo_medio_ausente boolean
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  perform public.assert_documento_operacional_os(p_os_id);
  return query
  select *
  from public.app_lancar_material_os_unfiltered_ov_20260829(
    p_os_id, p_codigo, p_quantidade, p_observacao
  );
end;
$$;

alter function public.app_lancar_material_os_por_item_id(integer, integer, numeric, text)
  rename to app_lancar_material_os_por_item_id_unfiltered_ov_20260829;

create function public.app_lancar_material_os_por_item_id(
  p_os_id integer,
  p_item_id integer,
  p_quantidade numeric,
  p_observacao text default null
)
returns table (
  os_item_id integer,
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade numeric,
  saldo_restante numeric,
  nao_cobrado boolean,
  custo_medio_ausente boolean
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  perform public.assert_documento_operacional_os(p_os_id);
  return query
  select *
  from public.app_lancar_material_os_por_item_id_unfiltered_ov_20260829(
    p_os_id, p_item_id, p_quantidade, p_observacao
  );
end;
$$;

alter function public.app_lancar_apontamentos_lote(integer, date, uuid, jsonb, text, boolean)
  rename to app_lancar_apontamentos_lote_unfiltered_ov_20260829;

create function public.app_lancar_apontamentos_lote(
  p_os_id integer,
  p_data date,
  p_tipo_hora_id uuid,
  p_lancamentos jsonb,
  p_descricao text default null,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  perform public.assert_documento_operacional_os(p_os_id);
  return public.app_lancar_apontamentos_lote_unfiltered_ov_20260829(
    p_os_id, p_data, p_tipo_hora_id, p_lancamentos, p_descricao, p_confirmar_avisos
  );
end;
$$;

alter function public.app_listar_apontamentos_os_fluxo(integer)
  rename to app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829;

create function public.app_listar_apontamentos_os_fluxo(p_os_id integer)
returns table (
  id uuid,
  os_id integer,
  numero_os varchar,
  cliente_nome varchar,
  colaborador_id uuid,
  nome_colaborador varchar,
  data date,
  horas numeric,
  tipo_hora_id uuid,
  nome_tipo_hora varchar,
  descricao text,
  status varchar,
  status_aprovacao text,
  pendente_em timestamptz,
  aprovado_em timestamptz,
  rejeitado_em timestamptz,
  gerado_por_hh boolean,
  motivo_devolucao text,
  criado_em timestamptz
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  perform public.assert_documento_operacional_os(p_os_id);
  return query
  select * from public.app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829(p_os_id);
end;
$$;

alter function public.app_listar_apontamentos(date, date, integer, uuid)
  rename to app_listar_apontamentos_unfiltered_ov_20260829;

create function public.app_listar_apontamentos(
  p_data_inicio date default null,
  p_data_fim date default null,
  p_os_id integer default null,
  p_colaborador_id uuid default null
)
returns table (
  id uuid,
  os_id integer,
  numero_os varchar,
  cliente_nome varchar,
  colaborador_id uuid,
  nome_colaborador varchar,
  data date,
  horas numeric,
  tipo_hora_id uuid,
  nome_tipo_hora varchar,
  descricao text,
  status varchar,
  gerado_por_hh boolean,
  motivo_devolucao text,
  criado_em timestamptz
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
begin
  if p_os_id is not null then
    perform public.assert_documento_operacional_os(p_os_id);
  end if;

  return query
  select base.*
  from public.app_listar_apontamentos_unfiltered_ov_20260829(
    p_data_inicio, p_data_fim, p_os_id, p_colaborador_id
  ) as base
  join public.ordens_servico as os
    on os.id = base.os_id
   and os.tenant_id = public.current_tenant_id()
   and os.empresa_id = public.current_empresa_id()
   and os.tipo_documento = 'OS';
end;
$$;

alter function public.get_os_detail_operacional(uuid, uuid, integer)
  rename to get_os_detail_operacional_unfiltered_ov_20260829;

create function public.get_os_detail_operacional(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
begin
  if not exists (
    select 1
    from public.ordens_servico as os
    where os.id = p_os_id
      and os.tenant_id = p_tenant_id
      and os.empresa_id = p_empresa_id
      and os.tipo_documento = 'OS'
  ) then
    raise exception 'os_not_found';
  end if;

  return public.get_os_detail_operacional_unfiltered_ov_20260829(
    p_tenant_id, p_empresa_id, p_os_id
  );
end;
$$;

revoke all on function public.assert_documento_operacional_os(integer) from public, anon;
grant execute on function public.assert_documento_operacional_os(integer) to authenticated, service_role;

revoke all on function public.app_listar_os_unfiltered_ov_20260829(boolean, text) from public, anon, authenticated;
revoke all on function public.app_listar_os_fluxo_unfiltered_ov_20260829(text, text) from public, anon, authenticated;
revoke all on function public.app_listar_materiais_os_unfiltered_ov_20260829(integer) from public, anon, authenticated;
revoke all on function public.app_resumo_materiais_os_unfiltered_ov_20260829(integer) from public, anon, authenticated;
revoke all on function public.app_lancar_material_os_unfiltered_ov_20260829(integer, text, numeric, text) from public, anon, authenticated;
revoke all on function public.app_lancar_material_os_por_item_id_unfiltered_ov_20260829(integer, integer, numeric, text) from public, anon, authenticated;
revoke all on function public.app_lancar_apontamentos_lote_unfiltered_ov_20260829(integer, date, uuid, jsonb, text, boolean) from public, anon, authenticated;
revoke all on function public.app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829(integer) from public, anon, authenticated;
revoke all on function public.app_listar_apontamentos_unfiltered_ov_20260829(date, date, integer, uuid) from public, anon, authenticated;
revoke all on function public.get_os_detail_operacional_unfiltered_ov_20260829(uuid, uuid, integer) from public, anon, authenticated;

grant execute on function public.app_listar_os(boolean, text) to authenticated, service_role;
grant execute on function public.app_listar_os_fluxo(text, text) to authenticated, service_role;
grant execute on function public.app_listar_materiais_os(integer) to authenticated, service_role;
grant execute on function public.app_resumo_materiais_os(integer) to authenticated, service_role;
grant execute on function public.app_lancar_material_os(integer, text, numeric, text) to authenticated, service_role;
grant execute on function public.app_lancar_material_os_por_item_id(integer, integer, numeric, text) to authenticated, service_role;
grant execute on function public.app_lancar_apontamentos_lote(integer, date, uuid, jsonb, text, boolean) to authenticated, service_role;
grant execute on function public.app_listar_apontamentos_os_fluxo(integer) to authenticated, service_role;
grant execute on function public.app_listar_apontamentos(date, date, integer, uuid) to authenticated, service_role;
grant execute on function public.get_os_detail_operacional(uuid, uuid, integer) to authenticated, service_role;
