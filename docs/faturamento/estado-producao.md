# Estado da produção para o squash de migrations

## Fonte e escopo

Levantamento somente leitura executado em 01/09/2026 contra o projeto Supabase vinculado `ptybnreejbkqwwozvhzb`.

As consultas de dados usam explicitamente o tenant Segau `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7` e suas empresas ativas, não excluídas. Nenhuma alteração foi feita em produção.

## Histórico reconhecido pela produção

A tabela `supabase_migrations.schema_migrations` contém **360 versões**:

- Primeira: `20240102` — `fiscal`.
- Última: `20260831144500` — `remover_os_itens_duplicados_nf_sick_364992`.
- Não há versão duplicada no repositório.
- Não há divergência de nome entre a produção e o arquivo correspondente.

### Aplicadas em produção e presentes no repositório (360)

- `20240102_fiscal.sql`
- `20260109_rls_multiempresa.sql`
- `20260110_import_nf_entrada.sql`
- `20260111_admin_users_manage.sql`
- `20260112_roles_permissions.sql`
- `20260113_roles_rls.sql`
- `20260114_cliente_habilita_hh.sql`
- `20260115_apontamentos_validate_colaborador_contrato.sql`
- `20260116_empresa_context.sql`
- `20260120_apontamentos_select_policies.sql`
- `20260121_apontamentos_permissions.sql`
- `20260122_finalidade_importacao.sql`
- `20260123_fornecedores_fix.sql`
- `20260124_tenant_memberships_self.sql`
- `20260125_estoque_coordenacao_access.sql`
- `20260127_fix_import_nf_entrada_movimentacoes.sql`
- `20260128_fix_gerar_ap_pendente_por_nf_entrada_v2.sql`
- `20260129153000_fix_impostos_entrada_credito.sql`
- `20260129160000_clientes_unique_constraint_documento_norm.sql`
- `20260129173000_import_nfse_saida.sql`
- `20260131_ap_manual_e_recorrencias.sql`
- `20260201_fix_add_os_item_baixa_imediata.sql`
- `20260202_fix_ap_aging_motivo_fallback.sql`
- `20260203_execucao_select_policies.sql`
- `20260204_permissions_admin_coord_all.sql`
- `20260205_rls_by_can.sql`
- `20260206_can_many.sql`
- `20260207_drop_legacy_remove_os_item_overload.sql`
- `20260208_fix_remove_os_item_reverte_estoque_rpc.sql`
- `20260209_fix_rpc_overloads_and_seed_os_gestao_itens.sql`
- `20260210_itens_fabricante.sql`
- `20260211_fornecedores_gerar_contas_pagar_auto.sql`
- `20260212_admin_apontamentos_config.sql`
- `20260213_financeiro_dashboard.sql`
- `20260214_fix_empresa_memberships_rls.sql`
- `20260215_clientes_habilita_hh.sql`
- `20260216_fix_empresa_eletrica_segau_default.sql`
- `20260217_fix_has_permission_undefined.sql`
- `20260218121503_remote_schema.sql`
- `20260218123217_teste_migrations.sql`
- `20260218124925_remote_schema.sql`
- `20260219125503_remote_schema.sql`
- `20260219133500_fix_os_rpc_permission_gate.sql`
- `20260219142000_fix_os_rpc_gate_use_has_permission.sql`
- `20260219151500_add_impostos_guardiao_rpc.sql`
- `20260219164000_auditoria_reparo_ap_nf_entrada.sql`
- `20260219170000_update_ap_parcela_vencimento_rpc.sql`
- `20260219170834_nome_da_mudanca.sql`
- `20260219173222_nome_da_mudanca.sql`
- `20260219174500_ar_vencimento_e_desdobro.sql`
- `20260219180641_nome_da_mudanca.sql`
- `20260219182000_allow_recebimento_ar_pendente.sql`
- `20260219193000_fase1_credito_elegibilidade_lucro_real.sql`
- `20260219194000_fix_credito_conferencia_ambiguous.sql`
- `20260219201000_fase2_politica_credito_fiscal.sql`
- `20260219213000_fase3_credito_manual_ap.sql`
- `20260220143721_nome_da_mudanca.sql`
- `20260220183000_orcamento_item_descricao_livre_generico.sql`
- `20260220184500_ensure_item_generico_orcamento.sql`
- `20260220193000_fix_import_nfe_itens_deleted_at.sql`
- `20260220201000_compras_pedidos_modulo.sql`
- `20260220212000_compras_pedidos_fase2_ajustes.sql`
- `20260220225000_compras_varredura_os_estoque.sql`
- `20260220232000_compras_varredura_estoque_filtro.sql`
- `20260220235500_fix_compra_varredura_cp_alias.sql`
- `20260221000500_fix_compra_pendencia_trigger_itens_deleted_at.sql`
- `20260221111202_nome_da_mudanca.sql`
- `20260221114500_fix_compra_varredura_itens_sem_deleted_at_e_baixa_os.sql`
- `20260221161651_nome_da_mudanca.sql`
- `20260221162500_fix_compra_varredura_cp_alias_update.sql`
- `20260221164500_fix_compra_varredura_sem_pedido_item_deleted_at.sql`
- `20260221170000_fix_compra_pendencia_trigger_sem_pedido_item_deleted_at.sql`
- `20260221173000_fix_compra_varredura_cancelar_os_item_removido.sql`
- `20260222140502_nome_da_mudanca.sql`
- `20260222145001_nome_da_mudanca.sql`
- `20260222190000_relatorio_entradas_consolidado.sql`
- `20260222193000_relatorio_entradas_motivo_coluna.sql`
- `20260222195000_relatorio_entradas_destino_os.sql`
- `20260222202000_fix_mov_estoque_os_direto_e_saldo_ajustado.sql`
- `20260222213000_relatorio_entradas_saldo_ajustado_fix.sql`
- `20260222220000_fix_estoque_delta_os_e_relatorio_operacional.sql`
- `20260222224500_refine_relatorio_entradas_saldo_heuristica.sql`
- `20260222232000_fix_add_os_item_mov_origem_os_id.sql`
- `20260222234500_blindagem_fluxo_os_movimentacoes.sql`
- `20260223001000_func_reclassificar_mov_saida_para_os.sql`
- `20260223002500_fix_reclassificar_mov_saida_return_type.sql`
- `20260223004000_reclassificacao_idempotente.sql`
- `20260223010000_prevent_negative_apply_mov.sql`
- `20260223013000_relatorio_operacional_exclusoes.sql`
- `20260223020000_relatorio_entradas_detalhes_usuario.sql`
- `20260223022000_fix_compra_pendencia_trigger_sem_deleted_at.sql`
- `20260223093000_fix_compra_varredura_os_dedup_cancel.sql`
- `20260224_apontamentos_horas_select_shortcircuit.sql`
- `20260225_fix_empresa_memberships_select_shortcircuit.sql`
- `20260226182531_remote_schema.sql`
- `20260226205318_20260226193000_remote_baseline.sql`
- `20260227_reset_apontamentos_horas_policies_members_only.sql`
- `20260228_colaboradores_permissions_fix.sql`
- `20260301_fornecedores_cnpj_unique.sql`
- `20260302_fornecedor_import_defaults.sql`
- `20260303121000_financeiro_impostos_apuracao.sql`
- `20260303150000_clientes_campos_completos.sql`
- `20260303153000_clientes_unique_documento_norm.sql`
- `20260304100000_fix_import_nf_entrada_xml_integridade.sql`
- `20260305193847_fix_root_xml_import_permissions.sql`
- `20260305201000_fix_xml_import_trigger_permission.sql`
- `20260305204000_fix_trigger_credito_manual_only.sql`
- `20260305211000_fix_import_xml_titulo_aprovacao_rpc.sql`
- `20260305220000_reconcile_import_xml_permission_matrix.sql`
- `20260305223000_fix_import_xml_backfill_movimentacoes.sql`
- `20260305230000_restore_fn_imposto_credito_conferencia_range.sql`
- `20260305232000_fix_fn_imposto_credito_conferencia_schema.sql`
- `20260305235000_fix_impostos_apuracao_effective_value.sql`
- `20260305235900_fix_nfse_piscofins_debito_import_manual_backfill_jan_fev.sql`
- `20260306001000_fix_nfse_piscofins_fallback_all_keys_backfill_jan_fev.sql`
- `20260306002000_orcamento_itens_codigo_interno.sql`
- `20260306003000_orcamento_campos_proposta.sql`
- `20260306100000_compras_pedidos_permissoes_totais_papeis.sql`
- `20260306103000_fix_compra_varredura_cancelar_pendente_coberta_por_em_pedido.sql`
- `20260306112000_fix_compra_pendencia_os_duplicada_aberta.sql`
- `20260306113000_fix_fn_compra_varredura_sem_i_deleted_at.sql`
- `20260306130000_fix_varredura_estoque_recalculo_e_cancelamento.sql`
- `20260306140000_uppercase_descricoes_ordens_servico.sql`
- `20260306150000_gestao_cobranca_os.sql`
- `20260306153000_fix_sync_titulo_aprovacao_permission.sql`
- `20260306154000_fix_compra_varredura_cp_from_clause.sql`
- `20260306155000_consolidar_fornecedores_siemens.sql`
- `20260306160000_fix_sync_titulo_aprovacao_os_id_column.sql`
- `20260306161000_fix_importacao_xml_revenda_finalidades.sql`
- `20260306162000_pedido_compra_solicitante_e_os_item.sql`
- `20260306163000_fix_impostos_credito_from_nf_itens.sql`
- `20260307100000_fix_trg_itens_sync_timestamps_updated_at_compat.sql`
- `20260307113000_fix_apply_movimentacao_estoque_update_preco_nf.sql`
- `20260307120000_backfill_preco_itens_importacoes_nf_2026.sql`
- `20260307123000_orcamento_status_followup_fluxo.sql`
- `20260307124000_nfse_sync_titulo_ar_parcelas.sql`
- `20260307130000_cancelar_titulo_ap.sql`
- `20260309110000_gestao_cobranca_responsavel_cliente.sql`
- `20260310195000_fix_nfe_saida_sem_ap_indevido.sql`
- `20260311143000_fix_orcamento_preco_sugerido_margem.sql`
- `20260317133301_fix_trg_itens_sync_timestamps_reapply_compat.sql`
- `20260317152725_fix_import_nf_entrada_os_item_total_and_os133_item2192.sql`
- `20260317163113_fix_os133_item2192_remove_manual_excess.sql`
- `20260320170000_drop_duplicate_movimentacoes_trigger.sql`
- `20260320173000_fix_public_set_updated_at_compat.sql`
- `20260320193000_add_pedido_receber_skip_movimentacao.sql`
- `20260330120000_add_conjunto_categorias_to_config_orcamento.sql`
- `20260331153000_fix_config_orcamento_update_grant.sql`
- `20260402113000_faturamento_vinculo_os.sql`
- `20260406120000_orcamento_fechamento_os_analitico.sql`
- `20260407101000_fix_orcamento_status_ambiguous_valor_fechado.sql`
- `20260407103000_fix_orcamento_emissao_janeiro_seg_001_029.sql`
- `20260407113000_fix_orcamento_status_ambiguous_numero_os.sql`
- `20260407123000_orcamento_permitir_itens_despesa.sql`
- `20260408130000_faturamento_empresas_disponiveis.sql`
- `20260408143000_faturamento_sync_titulo_ar_parcelas.sql`
- `20260408152000_faturamento_excluir_documento_saida.sql`
- `20260414130000_condicao_pagamento_soft_delete_policy.sql`
- `20260414143000_pedido_compra_campos_obrigatorios_fluxo.sql`
- `20260414152000_condicao_pagamento_compras_select.sql`
- `20260415101500_condicao_pagamento_service_role_grant.sql`
- `20260421113000_compras_varredura_meta_estoque_max.sql`
- `20260421143000_fix_estoque_movimentacoes_rls_can.sql`
- `20260421170000_pedido_compra_transporte_transportadora.sql`
- `20260422101500_fix_compra_varredura_os_dedup_lock.sql`
- `20260519143000_fix_os_movimentacao_numero_os.sql`
- `20260524120000_os_itens_quantidade_baixada.sql`
- `20260524123000_set_os_item_quantidade_baixada.sql`
- `20260526173000_fix_xml_os_direta_dedup_trigger.sql`
- `20260526193000_fix_import_nf_entrada_item_code_and_direct_os_validation.sql`
- `20260526200000_fix_import_nf_entrada_ignore_deleted_duplicate.sql`
- `20260526201000_fix_nf_entrada_chave_unique_active_tenant.sql`
- `20260529120000_allow_item_codigo_por_fornecedor.sql`
- `20260531150000_create_imobilizado_consumo_import_tables.sql`
- `20260602100000_faturamento_empresa_role.sql`
- `20260602143000_faturamento_import_nf_entrada_ap_permission.sql`
- `20260602170000_fix_supabase_security_advisor_errors.sql`
- `20260602173000_fix_supabase_security_warnings.sql`
- `20260602180000_fix_hh_tipos_mapping_rls_context.sql`
- `20260612100000_cliente_contatos_snapshot_orcamento.sql`
- `20260612110000_orcamento_drive_integracao.sql`
- `20260619100000_create_cargos.sql`
- `20260619100001_seed_cargos_from_colaboradores.sql`
- `20260623100000_pronamp_financiamento_parcelas.sql`
- `20260623110000_titulo_parcela_serie.sql`
- `20260623120000_imobilizado_naport_regional_telhas.sql`
- `20260623130000_titulo_descricao_view_rpc.sql`
- `20260623140000_reclass_parcelamentos_segau.sql`
- `20260623150000_dedup_grenke_virtus_polo.sql`
- `20260624103000_hh_lancamentos_horas_extras_manuais.sql`
- `20260624112000_hh_apontamentos_upsert_existente.sql`
- `20260624113000_hh_apontamentos_sync_key_bigint.sql`
- `20260625120000_orcamento_importar_itens_os_valor_compra.sql`
- `20260625130000_sanear_parcelamentos_caixa_sefaz.sql`
- `20260705120000_cadastro_empresa_sgu_automacao.sql`
- `20260706100000_restringe_acesso_sgu_automacao.sql`
- `20260706110000_empresa_memberships_sgu_automacao.sql`
- `20260706120000_importar_notas_saida_sgu.sql`
- `20260706123000_remover_titulos_duplicados_sgu.sql`
- `20260706130000_importar_nfse_sgu_maio_junho.sql`
- `20260723120000_relatorio_saude_financeira.sql`
- `20260723130000_relatorio_saude_financeira_ajustes.sql`
- `20260724100000_legado_implantacao_ap_base.sql`
- `20260724103000_marcar_legado_implantacao_ap_segau.sql`
- `20260724104500_fix_legado_aging_permissions.sql`
- `20260724110000_rateio_auditoria_prevencao.sql`
- `20260724113000_sanear_rateios_segau.sql`
- `20260724114500_rateio_guardrails.sql`
- `20260724115000_rateio_titulo_guard_smoke.sql`
- `20260724120000_compromissos_classificacao_preview.sql`
- `20260724123000_classificar_compromissos_segau.sql`
- `20260724124500_resumo_classificacao_compromissos.sql`
- `20260724125000_corrigir_referencia_grenke_classificacao.sql`
- `20260724125500_composicao_historica_compromissos.sql`
- `20260724130000_guardrails_classificacao_compromissos.sql`
- `20260724131000_saude_financeira_respeitar_classificacao.sql`
- `20260724140000_separar_faturamento_dos_itens_os.sql`
- `20260725100000_centros_custo_regras_rateio.sql`
- `20260725101000_centros_regras_iniciais_segau.sql`
- `20260728100000_central_inconsistencias_financeiras.sql`
- `20260729100000_corrigir_nf_63964_material_direto_os.sql`
- `20260729120000_corrigir_nfs_os_sem_centro.sql`
- `20260729130000_corrigir_meis_operacionais_julho.sql`
- `20260729140000_corrigir_custo_os_mat_sem_centro_julho.sql`
- `20260729150000_corrigir_planos_saude_bradesco.sql`
- `20260729160000_corrigir_aluguel_casa_tijucas.sql`
- `20260729170000_corrigir_alimentacao_equipe_campo.sql`
- `20260729180000_corrigir_salarios_funcionarios_ativos.sql`
- `20260729181000_isolar_salarios_funcionarios_ativos.sql`
- `20260729190000_corrigir_financiamentos_veiculos_frota.sql`
- `20260729191000_corrigir_arts_crea_producao.sql`
- `20260729192000_corrigir_pronamp_adm_fin.sql`
- `20260729193000_corrigir_alimentacao_sede.sql`
- `20260729194000_corrigir_parcelamento_pis_cofins_sicredi.sql`
- `20260729195000_corrigir_financiamento_terreno_segau.sql`
- `20260729196000_corrigir_google_workspace_pstec.sql`
- `20260729197000_corrigir_salario_larissa.sql`
- `20260729200000_pedido_compra_ipi_observacoes_fob.sql`
- `20260729201000_corrigir_aluguel_endereco_fiscal_treecom.sql`
- `20260729202000_corrigir_nf_hidramave_os206.sql`
- `20260729203000_corrigir_inconsistencias_julho_aprovadas.sql`
- `20260731183000_os_itens_registro_usuario.sql`
- `20260731213000_os_itens_autor_movimentacao.sql`
- `20260731223000_itens_auditoria_ultima_alteracao.sql`
- `20260803120000_estornar_nf_entrada.sql`
- `20260803150000_preparar_reimportacao_nfe_521977.sql`
- `20260803163000_reimportar_nfe_521977_com_pedido_os.sql`
- `20260803164000_documento_fiscal_chave_unica_somente_ativo.sql`
- `20260803165000_reimportacao_nfe_521977_classificar_ap_na_os.sql`
- `20260803170000_corrigir_baixa_duplicada_nfe_521977_os.sql`
- `20260803171000_validacao_reimportacao_nfe_521977.sql`
- `20260803172000_remover_validacao_temporaria_nfe_521977.sql`
- `20260806120000_contas_pagar_receber_multiempresa_resumo_hoje.sql`
- `20260806183000_saldos_por_conta_bancaria.sql`
- `20260806193000_saldos_ativos_dashboard.sql`
- `20260806194000_ap_manual_parcelado.sql`
- `20260806195000_contas_pagar_receber_total_parcelas.sql`
- `20260806200000_resumo_estoque_saude_financeira.sql`
- `20260806210000_faturamento_analitico_multiempresa.sql`
- `20260807100000_excluir_faturamento_intercompanhia.sql`
- `20260807113000_revisao_valor_final_ap.sql`
- `20260807121500_fix_revisao_valor_final_rateio.sql`
- `20260807153000_transferencias_bancarias_atomicas.sql`
- `20260810120000_empresa_access_boundary.sql`
- `20260810123000_legacy_admin_rpc_compat.sql`
- `20260811100000_add_tenant_diretor_role.sql`
- `20260811103000_harden_shared_user_profile_scope.sql`
- `20260811110000_optimize_orcamento_list.sql`
- `20260811111500_optimize_orcamento_view_compat.sql`
- `20260811120000_add_empresa_diretor_role.sql`
- `20260811130000_optimize_import_motivos_compra.sql`
- `20260811140000_fix_compras_fornecedores_lookup.sql`
- `20260811150000_optimize_orcamento_client_search.sql`
- `20260811160000_optimize_estoque_code_search.sql`
- `20260811170000_optimize_imported_nfe_list.sql`
- `20260812120000_financeiro_read_apontamentos.sql`
- `20260812130000_criar_titulo_ar_manual.sql`
- `20260812140000_os_saldo_a_faturar.sql`
- `20260812150000_fix_os_saldo_a_faturar_ambiguous_column.sql`
- `20260813120000_optimize_orcamento_item_lookup.sql`
- `20260813130000_search_orcamento_itens_rpc.sql`
- `20260813140000_search_itens_perfis_operacionais.sql`
- `20260814100000_optimize_multiempresa_operational_queries.sql`
- `20260814110000_orcamento_cliente_search_documento.sql`
- `20260814120000_compras_fornecedor_documento.sql`
- `20260817100000_create_item_groups.sql`
- `20260818100000_create_item_cadastro_agente_sugestoes.sql`
- `20260819120000_item_cadastro_agente_estoque_inicial.sql`
- `20260819130000_item_peso_referencia_kg_orcamento.sql`
- `20260820100000_almoxarifado_cadastra_itens.sql`
- `20260821090000_admin_lanca_apontamentos.sql`
- `20260822100000_remove_legacy_profissionais_horas_trabalhadas.sql`
- `20260823090000_apontamentos_aprovacao_colunas.sql`
- `20260823100000_apontamentos_integridade_triggers.sql`
- `20260823120000_os_responsavel_e_vinculo_colaborador.sql`
- `20260823130000_apontador_guardas_autorizacao.sql`
- `20260823140000_apontador_fechamento_total.sql`
- `20260823150000_app_mobile_rpcs_leitura.sql`
- `20260823160000_app_listar_apontamentos_coordenacao.sql`
- `20260823170000_app_mobile_lancamentos_lote.sql`
- `20260823170500_os_fiado_flag_e_link_orcamento.sql`
- `20260823171000_cargos_item_servico_mapeamento.sql`
- `20260823172000_config_orcamento_margem_mao_obra.sql`
- `20260823173000_os_orcamento_export_linha.sql`
- `20260823174000_fn_gerar_ou_atualizar_orcamento_de_os.sql`
- `20260823175000_get_os_detail_operacional_fiado.sql`
- `20260823176000_app_lancar_lote_taxa_amigavel.sql`
- `20260823180000_app_mobile_editar_excluir_apontamento.sql`
- `20260823181000_corrige_exclusao_apontamento_coordenacao.sql`
- `20260823182000_app_mobile_hh_rpcs.sql`
- `20260823183000_app_verificar_feriado.sql`
- `20260823184000_app_lancar_hh_lote.sql`
- `20260823184100_corrige_hh_tipo_rpcs_mobile.sql`
- `20260824090000_app_mobile_resumo_os_e_mes.sql`
- `20260824100000_os_lista_custo_operacional.sql`
- `20260824100500_corrige_total_operacional_os_hh.sql`
- `20260824110000_app_criar_os_hh.sql`
- `20260826120000_fluxo_os_e_aprovacao_horas.sql`
- `20260826130000_agendar_sla_aprovacao_horas.sql`
- `20260826140000_app_minhas_horas.sql`
- `20260826200000_app_mobile_fluxo_os_aprovacoes_leitura.sql`
- `20260827090000_compras_leitura_os.sql`
- `20260827100000_compras_os_read_rls.sql`
- `20260827110000_apontador_filtros_mobile.sql`
- `20260827111000_aprovar_lancamento_responsavel.sql`
- `20260827130000_apontador_validacao_admin.sql`
- `20260827140000_app_mobile_material_os.sql`
- `20260827160000_fornecedores_leitura_cadastro_itens.sql`
- `20260827170000_list_fornecedores_cadastro_itens.sql`
- `20260827183000_app_mobile_material_por_item_id.sql`
- `20260827190000_app_mobile_notificacoes.sql`
- `20260828120000_app_mobile_horas_materiais.sql`
- `20260828170000_fix_admin_password_usuario_tenant.sql`
- `20260829100000_venda_credito_fundacao.sql`
- `20260829110000_preco_venda_canonico.sql`
- `20260829115000_gestao_cobranca_os_baseline.sql`
- `20260829120000_venda_credito_banco_automacoes.sql`
- `20260829123000_venda_credito_validacao_grants.sql`
- `20260829123100_venda_credito_views_service_role.sql`
- `20260829123200_venda_credito_schema_grants.sql`
- `20260829124000_venda_credito_view_performance.sql`
- `20260829124100_venda_credito_competencia_historica.sql`
- `20260829130000_vendas_ov_fundacao.sql`
- `20260829131000_vendas_ov_fechamento_orcamento.sql`
- `20260829132000_vendas_ov_compras.sql`
- `20260829133000_vendas_ov_isolamento_mobile_horas.sql`
- `20260829134000_vendas_ov_relatorios_operacionais.sql`
- `20260829135000_vendas_ov_integracao_compras.sql`
- `20260830124500_apontamentos_listagem_performance.sql`
- `20260830150000_contas_pagar_receber_listagem_v4.sql`
- `20260830163000_apontamentos_lancar_horas_v2.sql`
- `20260830190000_home_sala_controle.sql`
- `20260830191000_home_sala_controle_fluxo_nulo.sql`
- `20260830200000_app_mobile_os_historico_estoque.sql`
- `20260830201000_app_mobile_agrupar_cliente_canonico.sql`
- `20260830202000_app_mobile_estoque_preco_por_perfil.sql`
- `20260830203000_apontamentos_edicao_por_status_e_papel.sql`
- `20260830204000_app_mobile_editar_remover_material_proprio.sql`
- `20260831143000_corrigir_nf_sick_364992_pedido_333.sql`
- `20260831144500_remover_os_itens_duplicados_nf_sick_364992.sql`

### Aplicadas em produção e ausentes do repositório (0)

- Nenhuma.

### Presentes no repositório e não aplicadas em produção (0)

- Nenhuma.

## `public.ordens_servico`

As duas colunas existem em produção:

| Coluna | Tipo | Nulo | Default |
|---|---|---|---|
| `status_fluxo` | `text` | Sim | sem default |
| `tipo_documento` | `text` | Não | `'OS'` |

Valores no tenant Segau:

| `status_fluxo` | Quantidade |
|---|---:|
| `NULL` | 12 |
| `concluida` | 3 |
| `em_andamento` | 75 |
| `faturada` | 225 |
| **Total** | **315** |

Todos os 315 registros do escopo têm `tipo_documento = 'OS'`; não há OV gravada nessa fotografia de produção.

## `f.documento_fiscal.operacao` e `natureza`

Contagem dos documentos não excluídos no tenant Segau:

| `operacao` | `natureza` | Quantidade |
|---|---|---:|
| `ENTRADA` | `PRODUTO` | 1.897 |
| `SAIDA` | `PRODUTO` | 208 |
| `SAIDA` | `SERVICO` | 219 |
| **Total** |  | **2.324** |

Conclusão: `operacao` distingue entrada de saída e `natureza` distingue produto de serviço. Essas colunas **não informam se o documento foi importado ou emitido pelo ERP**. Portanto, elas não tornam semanticamente redundante um discriminador de proveniência, embora a decisão de criar `origem` tenha sido adiada conforme solicitado.

## `c.empresa_fiscal`

Há **1 linha fiscal ativa** para as empresas do tenant Segau:

| Empresa | Linha em `c.empresa_fiscal` | IE | Isento | CRT | Regime | CNAE |
|---|---|---|---|---|---|---|
| `SEG` — ELÉTRICA SEGAU LTDA | Não | — | — | — | — | — |
| `SGU` — SGU AUTOMAÇÃO LTDA | Sim | `260586307` | Não | `1` | Simples Nacional | não preenchido |

## Observação para o squash

Embora produção e repositório concordem sobre as 360 versões aplicadas, o histórico não é reexecutável do zero: o shadow/local falha em `20260306161000_fix_importacao_xml_revenda_finalidades.sql` porque `public.parametro_importacao_xml` ainda não existe nesse ponto. A produção é, portanto, a fonte canônica do schema para o baseline.

## Resultado da tentativa de baseline

O `supabase db pull --linked --schema public,a,c,f,m,r producao_squash_baseline` foi tentado de duas formas, sempre sem escrita em produção:

1. Com as 360 migrations na raiz, o shadow parou em `20260306161000_fix_importacao_xml_revenda_finalidades.sql` por ausência de `public.parametro_importacao_xml`.
2. Com as 360 migrations movidas temporariamente para `supabase/migrations/_arquivo/`, o pull parou com `LegacyDbPullMigrationConflictError`: a CLI exige marcar as 360 versões remotas como `reverted` antes de gerar o baseline.

`supabase migration repair --linked` altera `supabase_migrations.schema_migrations` na produção. Como a tarefa também determina que produção seja somente leitura, esse repair **não foi executado**. Os 360 arquivos foram restaurados à raiz original, nenhum baseline foi criado e a produção continuou com 360 versões, terminando em `20260831144500`.

Consequentemente, `supabase db reset --local` com o baseline e a Fase 3 não foram executados. Para continuar, é necessário escolher entre autorizar explicitamente a alteração do histórico remoto ou permitir a geração read-only do baseline por `supabase db dump --linked`, deixando o repair remoto para uma janela autorizada posterior.
