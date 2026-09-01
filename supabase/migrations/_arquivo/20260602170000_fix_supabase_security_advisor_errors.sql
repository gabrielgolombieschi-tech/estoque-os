-- Fix Supabase security advisor errors reported on 2026-06-02:
-- - policy_exists_rls_disabled
-- - rls_disabled_in_public
-- - security_definer_view

-- 1) Views exposed through PostgREST should run with invoker permissions/RLS.
do $$
declare
  v record;
begin
  for v in
    select *
    from (values
      ('r', 'r_apuracao_irpj_csll_anual_comp2'),
      ('r', 'r_compra_fornecedores_pendentes'),
      ('r', 'r_i_caixa_custo'),
      ('public', 'v_item_ultimo_custo'),
      ('public', 'v_user_permissions'),
      ('public', 'v_estoque_custo_atual'),
      ('public', 'contas_pagar_titulos_agendamentos'),
      ('r', 'r_orcamento_lista'),
      ('r', 'r_motivo_compra_rank'),
      ('f', 'r_fluxo_caixa_diario_por_os'),
      ('f', 'r_ap_aging_resumo'),
      ('f', 'r_fluxo_caixa_diario_por_motivo'),
      ('r', 'r_apuracao_irpj_csll_mensal_comp2'),
      ('f', 'r_fluxo_caixa_previsto_diario'),
      ('f', 'r_fluxo_previsto_diario_dim'),
      ('r', 'r_pendencias_xml_entrada'),
      ('public', 'vw_custo_mao_obra_os'),
      ('r', 'r_apuracao_irpj_csll_mensal_comp'),
      ('public', 'contas_pagar_titulos_parcelas'),
      ('r', 'r_apuracao_irpj_csll_anual_comp'),
      ('public', 'contas_pagar_titulos_rateios'),
      ('r', 'r_apuracao_irpj_csll_mensal'),
      ('r', 'r_orcamento_itens'),
      ('f', 'r_fluxo_caixa_diario_dim'),
      ('r', 'r_apuracao_irpj_csll_anual'),
      ('f', 'r_fluxo_caixa_diario_por_fornecedor'),
      ('r', 'r_compra_pendencias_detalhadas'),
      ('public', 'v_creditos_por_periodo'),
      ('public', 'vw_creditos_mensais'),
      ('f', 'r_fluxo_realizado_diario_dim'),
      ('r', 'r_documentos_pendentes_xml'),
      ('r', 'r_compra_pendencias_agrupadas_item'),
      ('public', 'vw_apontamentos_horas_custo'),
      ('f', 'r_fluxo_previsto_diario_ajustado_hoje'),
      ('r', 'r_dre_mensal'),
      ('f', 'nf_entrada'),
      ('public', 'contas_pagar_titulos'),
      ('r', 'r_itens_ativos'),
      ('r', 'r_guardiao_impostos_docs'),
      ('public', 'v_lancamentos_contabeis_balance'),
      ('r', 'r_nfse_iss_conferencia'),
      ('public', 'vw_hh_total_os'),
      ('f', 'r_titulos_sem_motivo_por_fornecedor'),
      ('f', 'r_fluxo_caixa_diario_por_motivo_rotulado'),
      ('r', 'r_dre_mensal_plano'),
      ('f', 'r_saldo_projetado_diario'),
      ('r', 'r_dre_mensal_plano_filtrado'),
      ('public', 'contas_pagar_titulos_aprovacoes'),
      ('f', 'r_saldo_projetado_diario_com_saldo_inicial'),
      ('f', 'vw_imposto_apuracao_mensal'),
      ('f', 'r_fluxo_caixa_realizado_diario'),
      ('r', 'r_gestao_cobranca_os'),
      ('f', 'r_fluxo_caixa_diario_conta_resolvida'),
      ('r', 'r_orcamento_catalogo_busca'),
      ('f', 'r_sugestoes_conciliacao_ap'),
      ('public', 'r_itens_ativos'),
      ('f', 'r_fluxo_caixa_diario'),
      ('r', 'r_dre_mensal_filtrado'),
      ('public', 'vw_colaboradores_taxa_atual'),
      ('f', 'r_fluxo_caixa_mensal'),
      ('f', 'r_ap_aging_detalhe'),
      ('r', 'r_apuracao_impostos_mes')
    ) as t(schema_name, view_name)
  loop
    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = v.schema_name
        and c.relname = v.view_name
        and c.relkind = 'v'
    ) then
      execute format('alter view %I.%I set (security_invoker = true)', v.schema_name, v.view_name);
    end if;
  end loop;
end;
$$;

create or replace function public.has_capability(
  p_capability text,
  p_tenant_id uuid default public.current_tenant_id(),
  p_empresa_id uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'a', 'c', 'f'
as $$
  select coalesce((public.get_full_permissions(p_tenant_id, p_empresa_id)->>p_capability)::boolean, false);
$$;

grant execute on function public.has_capability(text, uuid, uuid) to authenticated, service_role;

-- 2) Tables that already had policies only needed RLS enabled.
alter table if exists public.empresas enable row level security;
alter table if exists public.user_profiles enable row level security;

-- Keep FATURAMENTO able to discover empresas through the legacy public.empresas path.
drop policy if exists empresas_select_a on public.empresas;
create policy empresas_select_a
on public.empresas
for select
to authenticated
using (
  public.a_is_empresa_member(id)
  or public.a_is_tenant_role(tenant_id, array['admin', 'estoque', 'fiscal', 'projetos', 'financeiro', 'faturamento'])
);

-- 3) Global/support tables.
alter table if exists public.feriados enable row level security;
drop policy if exists codex_feriados_select on public.feriados;
create policy codex_feriados_select
on public.feriados
for select
to authenticated
using (true);

drop policy if exists codex_feriados_admin_write on public.feriados;
create policy codex_feriados_admin_write
on public.feriados
for all
to authenticated
using (public.can('admin', 'manage_users'))
with check (public.can('admin', 'manage_users'));

alter table if exists public.role_permissions enable row level security;
drop policy if exists codex_role_permissions_select on public.role_permissions;
create policy codex_role_permissions_select
on public.role_permissions
for select
to authenticated
using (true);

drop policy if exists codex_role_permissions_admin_write on public.role_permissions;
create policy codex_role_permissions_admin_write
on public.role_permissions
for all
to authenticated
using (public.can('admin', 'manage_users'))
with check (public.can('admin', 'manage_users'));

alter table if exists public.profissionais enable row level security;
drop policy if exists codex_profissionais_select on public.profissionais;
create policy codex_profissionais_select
on public.profissionais
for select
to authenticated
using (public.has_capability('apontamentos.read') or public.has_capability('os.read'));

drop policy if exists codex_profissionais_write on public.profissionais;
create policy codex_profissionais_write
on public.profissionais
for all
to authenticated
using (public.has_capability('apontamentos.config') or public.can('admin', 'manage_users'))
with check (public.has_capability('apontamentos.config') or public.can('admin', 'manage_users'));

-- Legacy HH table without tenant columns: scope by the linked OS.
alter table if exists public.horas_trabalhadas enable row level security;
drop policy if exists codex_horas_trabalhadas_select on public.horas_trabalhadas;
create policy codex_horas_trabalhadas_select
on public.horas_trabalhadas
for select
to authenticated
using (
  exists (
    select 1
    from public.ordens_servico os
    where os.id = horas_trabalhadas.os_id
      and os.tenant_id = public.current_tenant_id()
      and os.empresa_id = public.current_empresa_id()
      and (public.has_capability('apontamentos.read') or public.has_capability('os.read'))
  )
);

drop policy if exists codex_horas_trabalhadas_write on public.horas_trabalhadas;
create policy codex_horas_trabalhadas_write
on public.horas_trabalhadas
for all
to authenticated
using (
  exists (
    select 1
    from public.ordens_servico os
    where os.id = horas_trabalhadas.os_id
      and os.tenant_id = public.current_tenant_id()
      and os.empresa_id = public.current_empresa_id()
      and (public.has_capability('apontamentos.write') or public.has_capability('os.write'))
  )
)
with check (
  exists (
    select 1
    from public.ordens_servico os
    where os.id = horas_trabalhadas.os_id
      and os.tenant_id = public.current_tenant_id()
      and os.empresa_id = public.current_empresa_id()
      and (public.has_capability('apontamentos.write') or public.has_capability('os.write'))
  )
);

-- 4) Tenant-only support tables.
alter table if exists public.audit_log enable row level security;
drop policy if exists codex_audit_log_admin_select on public.audit_log;
create policy codex_audit_log_admin_select
on public.audit_log
for select
to authenticated
using (tenant_id = public.current_tenant_id() and public.can('admin', 'manage_users'));

alter table if exists public.hh_tipos_mapping enable row level security;
drop policy if exists codex_hh_tipos_mapping_select on public.hh_tipos_mapping;
create policy codex_hh_tipos_mapping_select
on public.hh_tipos_mapping
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (public.has_capability('apontamentos.read') or public.has_capability('os.read'))
);

drop policy if exists codex_hh_tipos_mapping_write on public.hh_tipos_mapping;
create policy codex_hh_tipos_mapping_write
on public.hh_tipos_mapping
for all
to authenticated
using (tenant_id = public.current_tenant_id() and public.has_capability('apontamentos.config'))
with check (tenant_id = public.current_tenant_id() and public.has_capability('apontamentos.config'));

alter table if exists r.dre_plano_excluido enable row level security;
drop policy if exists codex_dre_plano_excluido_all on r.dre_plano_excluido;
create policy codex_dre_plano_excluido_all
on r.dre_plano_excluido
for all
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and f.has_finance_access(public.current_tenant_id(), public.current_empresa_id())
)
with check (
  tenant_id = public.current_tenant_id()
  and f.has_finance_access(public.current_tenant_id(), public.current_empresa_id())
);

alter table if exists f.vencimento_regra enable row level security;
drop policy if exists codex_vencimento_regra_all on f.vencimento_regra;
create policy codex_vencimento_regra_all
on f.vencimento_regra
for all
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and f.has_finance_access(public.current_tenant_id(), public.current_empresa_id())
)
with check (
  tenant_id = public.current_tenant_id()
  and f.has_finance_access(public.current_tenant_id(), public.current_empresa_id())
);

-- 5) Tenant + empresa tables in public used by finance/fiscal.
do $$
declare
  v record;
begin
  for v in
    select *
    from (values
      ('public', 'plano_contas'),
      ('public', 'centros_custo'),
      ('public', 'competencias'),
      ('public', 'fiscal_regras'),
      ('public', 'lancamentos_contabeis'),
      ('public', 'lancamentos_contabeis_itens')
    ) as t(schema_name, table_name)
  loop
    execute format('alter table if exists %I.%I enable row level security', v.schema_name, v.table_name);
    execute format('drop policy if exists codex_finance_tenant_empresa_all on %I.%I', v.schema_name, v.table_name);
    execute format(
      'create policy codex_finance_tenant_empresa_all on %I.%I for all to authenticated using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access(tenant_id, empresa_id)) with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access(tenant_id, empresa_id))',
      v.schema_name,
      v.table_name
    );
  end loop;
end;
$$;

-- 6) Tenant + empresa tables in f schema.
do $$
declare
  v record;
begin
  for v in
    select *
    from (values
      ('f', 'irpj_csll_regra_plano'),
      ('f', 'tmp_backfill_impostos_entrada_erros'),
      ('f', 'documento_fiscal_pendencia'),
      ('f', 'irpj_csll_financeiro_config'),
      ('f', 'ap_recorrencia'),
      ('f', 'irpj_csll_saldo_inicial'),
      ('f', 'parametro_irpj_csll_empresa'),
      ('f', 'irpj_csll_ajuste')
    ) as t(schema_name, table_name)
  loop
    execute format('alter table if exists %I.%I enable row level security', v.schema_name, v.table_name);
    execute format('drop policy if exists codex_f_tenant_empresa_all on %I.%I', v.schema_name, v.table_name);
    execute format(
      'create policy codex_f_tenant_empresa_all on %I.%I for all to authenticated using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access(tenant_id, empresa_id)) with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access(tenant_id, empresa_id))',
      v.schema_name,
      v.table_name
    );
  end loop;
end;
$$;

-- 7) Tenant + empresa tables in c schema for imobilizado/ferramentas.
do $$
declare
  v record;
begin
  for v in
    select *
    from (values
      ('c', 'i_ferramenta_categoria'),
      ('c', 'i_ferramenta_codigo_seq')
    ) as t(schema_name, table_name)
  loop
    execute format('alter table if exists %I.%I enable row level security', v.schema_name, v.table_name);
    execute format('drop policy if exists codex_c_imobilizado_tenant_empresa_all on %I.%I', v.schema_name, v.table_name);
    execute format(
      'create policy codex_c_imobilizado_tenant_empresa_all on %I.%I for all to authenticated using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and c.has_imobilizado_access(tenant_id, empresa_id)) with check (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and c.has_imobilizado_access(tenant_id, empresa_id))',
      v.schema_name,
      v.table_name
    );
  end loop;
end;
$$;

-- 8) Empresa config tables only carry empresa_id; tenant comes from c.empresa.
alter table if exists c.empresa_endereco enable row level security;
drop policy if exists codex_empresa_endereco_context_all on c.empresa_endereco;
create policy codex_empresa_endereco_context_all
on c.empresa_endereco
for all
to authenticated
using (
  exists (
    select 1
    from c.empresa e
    where e.id = empresa_id
      and e.tenant_id = public.current_tenant_id()
      and e.id = public.current_empresa_id()
      and (
        c.has_comercial_access(e.tenant_id, e.id)
        or c.has_compras_access(e.tenant_id, e.id)
        or c.has_imobilizado_access(e.tenant_id, e.id)
        or f.has_finance_access(e.tenant_id, e.id)
      )
  )
)
with check (
  exists (
    select 1
    from c.empresa e
    where e.id = empresa_id
      and e.tenant_id = public.current_tenant_id()
      and e.id = public.current_empresa_id()
      and (
        c.has_comercial_access(e.tenant_id, e.id)
        or c.has_compras_access(e.tenant_id, e.id)
        or c.has_imobilizado_access(e.tenant_id, e.id)
        or f.has_finance_access(e.tenant_id, e.id)
      )
  )
);

alter table if exists c.empresa_fiscal enable row level security;
drop policy if exists codex_empresa_fiscal_context_all on c.empresa_fiscal;
create policy codex_empresa_fiscal_context_all
on c.empresa_fiscal
for all
to authenticated
using (
  exists (
    select 1
    from c.empresa e
    where e.id = empresa_id
      and e.tenant_id = public.current_tenant_id()
      and e.id = public.current_empresa_id()
      and (
        c.has_comercial_access(e.tenant_id, e.id)
        or c.has_compras_access(e.tenant_id, e.id)
        or c.has_imobilizado_access(e.tenant_id, e.id)
        or f.has_finance_access(e.tenant_id, e.id)
      )
  )
)
with check (
  exists (
    select 1
    from c.empresa e
    where e.id = empresa_id
      and e.tenant_id = public.current_tenant_id()
      and e.id = public.current_empresa_id()
      and (
        c.has_comercial_access(e.tenant_id, e.id)
        or c.has_compras_access(e.tenant_id, e.id)
        or c.has_imobilizado_access(e.tenant_id, e.id)
        or f.has_finance_access(e.tenant_id, e.id)
      )
  )
);

-- 9) Estoque merge audit table.
alter table if exists public.itens_merge_log enable row level security;
drop policy if exists codex_itens_merge_log_select on public.itens_merge_log;
create policy codex_itens_merge_log_select
on public.itens_merge_log
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and public.can('estoque', 'read')
);

drop policy if exists codex_itens_merge_log_insert on public.itens_merge_log;
create policy codex_itens_merge_log_insert
on public.itens_merge_log
for insert
to authenticated
with check (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and public.can('estoque', 'write')
);

notify pgrst, 'reload schema';
