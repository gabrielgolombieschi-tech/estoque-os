-- Schema f: as 29 RPCs (app_*/fn_*, sem gatilhos) que o anon conseguia executar em 18/09/2026 —
-- pelo EXECUTE padrao do PostgreSQL (PUBLIC) e pelo privilegio padrao do Supabase (anon) — ficam
-- fechadas para anon e PUBLIC. authenticated e service_role continuam como hoje (era por PUBLIC;
-- passa a ser explicito). Levantamento e revisao das SECURITY DEFINER em
-- docs/faturamento/seguranca-grants-2026-09-18.md. Pedido do Gabriel em 18/09/2026.
--
-- Quem chama no codigo (todas com sessao): DevolucaoCompraPanel (fn_devolucao_compra_preparar),
-- OperacoesFiscaisClient (fn_estorno_criar, fn_operacao_registrar_chave, fn_operacao_validar_homologacao,
-- fn_remessa_criar, fn_remessa_prazo_configurar, fn_retorno_criar, fn_venda_ordem_criar) e a Edge
-- nfse-ciclo (fn_operacao_assert_acesso, com o token do usuario). As demais so sao chamadas por
-- outras funcoes do banco.

revoke execute on function f.fn_calc_vencimento(p_tenant_id uuid, p_regra_id uuid, p_competencia_date date) from public, anon;
grant execute on function f.fn_calc_vencimento(p_tenant_id uuid, p_regra_id uuid, p_competencia_date date) to authenticated, service_role;
revoke execute on function f.fn_cfop_devolucao_proposto(p_cfop_entrada text) from public, anon;
grant execute on function f.fn_cfop_devolucao_proposto(p_cfop_entrada text) to authenticated, service_role;
revoke execute on function f.fn_cfop_estorno_proposto(p_cfop_original text) from public, anon;
grant execute on function f.fn_cfop_estorno_proposto(p_cfop_original text) to authenticated, service_role;
revoke execute on function f.fn_data_hoje_sao_paulo() from public, anon;
grant execute on function f.fn_data_hoje_sao_paulo() to authenticated, service_role;
revoke execute on function f.fn_devolucao_compra_criar(p_nf_entrada_id bigint, p_itens jsonb) from public, anon;
grant execute on function f.fn_devolucao_compra_criar(p_nf_entrada_id bigint, p_itens jsonb) to authenticated, service_role;
revoke execute on function f.fn_devolucao_compra_preparar(p_nf_entrada_id bigint) from public, anon;
grant execute on function f.fn_devolucao_compra_preparar(p_nf_entrada_id bigint) to authenticated, service_role;
revoke execute on function f.fn_estorno_criar(p_documento_original_id uuid, p_cfop_confirmado text, p_justificativa text) from public, anon;
grant execute on function f.fn_estorno_criar(p_documento_original_id uuid, p_cfop_confirmado text, p_justificativa text) to authenticated, service_role;
revoke execute on function f.fn_formatar_brl(p_valor numeric) from public, anon;
grant execute on function f.fn_formatar_brl(p_valor numeric) to authenticated, service_role;
revoke execute on function f.fn_gerar_ap_irpj_csll(p_tenant_id uuid, p_empresa_id uuid, p_competencia_date date) from public, anon;
grant execute on function f.fn_gerar_ap_irpj_csll(p_tenant_id uuid, p_empresa_id uuid, p_competencia_date date) to authenticated, service_role;
revoke execute on function f.fn_importacao_brl(p_valor numeric) from public, anon;
grant execute on function f.fn_importacao_brl(p_valor numeric) to authenticated, service_role;
revoke execute on function f.fn_importacao_ua_local(p_ua text) from public, anon;
grant execute on function f.fn_importacao_ua_local(p_ua text) to authenticated, service_role;
revoke execute on function f.fn_nfe_normalizar_parcelas(p_parcelas jsonb) from public, anon;
grant execute on function f.fn_nfe_normalizar_parcelas(p_parcelas jsonb) to authenticated, service_role;
revoke execute on function f.fn_nfse_cancelamento_limite(p_empresa_id uuid, p_autorizado_em timestamp with time zone) from public, anon;
grant execute on function f.fn_nfse_cancelamento_limite(p_empresa_id uuid, p_autorizado_em timestamp with time zone) to authenticated, service_role;
revoke execute on function f.fn_nfse_competencia_pendencia(p_competencia date, p_emissao date) from public, anon;
grant execute on function f.fn_nfse_competencia_pendencia(p_competencia date, p_emissao date) to authenticated, service_role;
revoke execute on function f.fn_nfse_discriminacao(p_linhas jsonb, p_pedido text, p_pedido_item text, p_parcelas jsonb, p_base_date date, p_iss_retido boolean, p_texto_retencao text, p_observacao text, p_template text, p_material numeric, p_valor_servico numeric) from public, anon;
grant execute on function f.fn_nfse_discriminacao(p_linhas jsonb, p_pedido text, p_pedido_item text, p_parcelas jsonb, p_base_date date, p_iss_retido boolean, p_texto_retencao text, p_observacao text, p_template text, p_material numeric, p_valor_servico numeric) to authenticated, service_role;
revoke execute on function f.fn_nfse_nbs_compativel(p_item_servico text, p_nbs text) from public, anon;
grant execute on function f.fn_nfse_nbs_compativel(p_item_servico text, p_nbs text) to authenticated, service_role;
revoke execute on function f.fn_nfse_texto_proibido(p_texto text) from public, anon;
grant execute on function f.fn_nfse_texto_proibido(p_texto text) to authenticated, service_role;
revoke execute on function f.fn_operacao_assert_acesso() from public, anon;
grant execute on function f.fn_operacao_assert_acesso() to authenticated, service_role;
revoke execute on function f.fn_operacao_registrar_chave(p_operacao_id uuid, p_etapa smallint, p_chave text) from public, anon;
grant execute on function f.fn_operacao_registrar_chave(p_operacao_id uuid, p_etapa smallint, p_chave text) to authenticated, service_role;
revoke execute on function f.fn_operacao_validar_homologacao(p_operacao_id uuid, p_etapa smallint) from public, anon;
grant execute on function f.fn_operacao_validar_homologacao(p_operacao_id uuid, p_etapa smallint) to authenticated, service_role;
revoke execute on function f.fn_os_reverter_faturada_sem_nota(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer) from public, anon;
grant execute on function f.fn_os_reverter_faturada_sem_nota(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer) to authenticated, service_role;
revoke execute on function f.fn_remessa_criar(p_finalidade text, p_cfop_confirmado text, p_destinatario jsonb, p_itens jsonb, p_justificativa text) from public, anon;
grant execute on function f.fn_remessa_criar(p_finalidade text, p_cfop_confirmado text, p_destinatario jsonb, p_itens jsonb, p_justificativa text) to authenticated, service_role;
revoke execute on function f.fn_remessa_prazo_configurar(p_finalidade text, p_prazo_dias integer) from public, anon;
grant execute on function f.fn_remessa_prazo_configurar(p_finalidade text, p_prazo_dias integer) to authenticated, service_role;
revoke execute on function f.fn_retorno_criar(p_remessa_controle_id uuid, p_cfop_confirmado text) from public, anon;
grant execute on function f.fn_retorno_criar(p_remessa_controle_id uuid, p_cfop_confirmado text) to authenticated, service_role;
revoke execute on function f.fn_retorno_terceiros_config() from public, anon;
grant execute on function f.fn_retorno_terceiros_config() to authenticated, service_role;
revoke execute on function f.fn_round_half_even(p_valor numeric, p_casas integer) from public, anon;
grant execute on function f.fn_round_half_even(p_valor numeric, p_casas integer) to authenticated, service_role;
revoke execute on function f.fn_solicitacao_nfe_resolver_perfis(p_solicitacao_id uuid, p_destino_uf text, p_destinacao text) from public, anon;
grant execute on function f.fn_solicitacao_nfe_resolver_perfis(p_solicitacao_id uuid, p_destino_uf text, p_destinacao text) to authenticated, service_role;
revoke execute on function f.fn_validar_pos_importacao(p_documento_fiscal_id uuid) from public, anon;
grant execute on function f.fn_validar_pos_importacao(p_documento_fiscal_id uuid) to authenticated, service_role;
revoke execute on function f.fn_venda_ordem_criar(p_ov_id integer, p_entrega jsonb) from public, anon;
grant execute on function f.fn_venda_ordem_criar(p_ov_id integer, p_entrega jsonb) to authenticated, service_role;

-- Conferencia: nenhuma delas pode ficar executavel pelo anon.
do $$
declare
  v_abertas text;
begin
  select string_agg(p.oid::regprocedure::text, ', ' order by p.proname)
    into v_abertas
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_type t on t.oid = p.prorettype
  where n.nspname = 'f'
    and (p.proname like 'app\_%' or p.proname like 'fn\_%')
    and p.prokind = 'f'
    and t.typname <> 'trigger'
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_abertas is not null then
    raise exception 'RPCs do schema f ainda abertas ao anon: %', v_abertas;
  end if;
end $$;

-- Reversao: grant execute ... to public nas 29 assinaturas acima (estado anterior: EXECUTE de PUBLIC).
