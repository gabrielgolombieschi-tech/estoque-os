-- Retorno de mercadoria de terceiros (5902/5903): cEnq do IPI 108 -> 109. Decisao do Gabriel em
-- 18/09/2026: 108 = RIPI (Decreto 7.212/2010) art. 43, VI, que e a remessa (5901); o retorno e o
-- art. 43, VII = cEnq 109 (tabela do Anexo XIV da NT 2015.002), e o infAdFisco da nota ja cita o
-- inciso VII. cBenef SC840008 confirmado (RICMS/SC, Anexo 2, art. 27, II). A NF-e 2/20 (WEG, 16/09)
-- saiu com 108: correcao por CC-e fica a cargo da contadora (rascunho no manual), nada e reemitido.
--
-- Tres lugares mudam: (a) f.fn_retorno_terceiros_config() (grava os itens da solicitacao),
-- (b) a constante RETORNO_REMESSA_TERCEIROS da Edge (montador; commit desta migration) e (c) o
-- perfil SEG-RETORNO-TERCEIROS-5902-O0-CST50. Como o payload muda, o perfil volta para revisao
-- (habilitado_producao false, revisao e liberacao zeradas): a producao so reabre depois de nova
-- revisao, nova homologacao posterior a ela e nova liberacao (f.fn_nfe_producao_pronta, gatilho
-- trg_bloquear_nfe_producao_sem_perfil_liberado). A remessa de conserto (remessa-conserto.ts,
-- 5915/5916) continua com 108: pendente com a contadora. Reversao: '108' nos tres lugares.

create or replace function f.fn_retorno_terceiros_config()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select jsonb_build_object(
    'cbenef_retorno_sc', 'SC840008',
    'cenq_ipi_retorno', '109',
    'cst_icms', '50',
    'cst_ipi', '55',
    'cst_pis_cofins', '08',
    'cst_ibs_cbs', '410',
    'cclass_trib', '410999',
    'cclass_trib_versao', 'NT 2025.002 - retorno de remessa de terceiros',
    'naturezas', jsonb_build_object(
      'INDUSTRIALIZACAO', jsonb_build_object('codigo', 'RETORNO_REMESSA_TERCEIROS', 'nat_op', 'RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO'),
      'CONSERTO', jsonb_build_object('codigo', 'RETORNO_REMESSA_TERCEIROS_CONSERTO', 'nat_op', 'RETORNO DE MERCADORIA RECEBIDA PARA CONSERTO')
    ),
    'modalidade_frete_padrao', 0,
    'cfops_origem', jsonb_build_array('5901', '6901', '5915', '6915')
  );
$$;

do $perfil$
declare
  v_perfil f.perfil_operacao%rowtype;
begin
  select * into v_perfil from f.perfil_operacao where codigo = 'SEG-RETORNO-TERCEIROS-5902-O0-CST50' and modelo = 'NFE';
  if not found then
    raise notice 'assert pulado: perfil SEG-RETORNO-TERCEIROS-5902-O0-CST50 ausente neste banco';
    return;
  end if;

  update f.perfil_operacao
     set ipi_codigo_enquadramento_legal = '109',
         observacao = 'Retorno de mercadoria de terceiros recebida para industrializacao por encomenda. cBenef SC840008 confirmado (RICMS/SC, Anexo 2, art. 27, II); cEnq 109 confirmado (RIPI art. 43, VII; Anexo XIV da NT 2015.002). Valores em f.fn_retorno_terceiros_config().',
         habilitado_producao = false,
         revisao_fiscal_em = null,
         revisao_fiscal_por = null,
         revisao_fiscal_justificativa = null,
         producao_decidida_em = null,
         producao_decidida_por = null,
         producao_decisao_justificativa = null,
         producao_homologacao_solicitacao_id = null,
         producao_homologacao_documento_id = null,
         justificativa_faixa = 'cEnq do IPI alterado de 108 para 109 em 18/09/2026: revisar, homologar de novo e liberar antes da proxima nota real.'
   where id = v_perfil.id;

  -- Auditoria no historico do perfil (mesma trilha das revisoes e liberacoes da tela).
  insert into f.perfil_operacao_revisao_evento (tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois, justificativa, criado_por)
  values (
    v_perfil.tenant_id, v_perfil.empresa_id, v_perfil.id, 'DESABILITACAO',
    jsonb_build_object('ipi_codigo_enquadramento_legal', v_perfil.ipi_codigo_enquadramento_legal, 'habilitado_producao', v_perfil.habilitado_producao,
                       'revisao_fiscal_em', v_perfil.revisao_fiscal_em, 'producao_decidida_em', v_perfil.producao_decidida_em,
                       'producao_homologacao_solicitacao_id', v_perfil.producao_homologacao_solicitacao_id,
                       'producao_homologacao_documento_id', v_perfil.producao_homologacao_documento_id),
    jsonb_build_object('ipi_codigo_enquadramento_legal', '109', 'habilitado_producao', false,
                       'revisao_fiscal_em', null, 'producao_decidida_em', null,
                       'producao_homologacao_solicitacao_id', null, 'producao_homologacao_documento_id', null),
    'Migration 20260918150000 a pedido do Gabriel: cEnq do IPI do retorno de terceiros 108 -> 109 (RIPI art. 43, VII; Anexo XIV da NT 2015.002). Perfil volta para revisao; producao so depois de nova homologacao e liberacao.',
    null
  );
  raise notice 'perfil % com cEnq 109, de volta para revisao (producao desabilitada)', v_perfil.codigo;
end;
$perfil$;

do $assert$
begin
  if f.fn_retorno_terceiros_config()->>'cenq_ipi_retorno' <> '109' then
    raise exception 'fn_retorno_terceiros_config ainda devolve cEnq %', f.fn_retorno_terceiros_config()->>'cenq_ipi_retorno';
  end if;
  if exists (select 1 from f.perfil_operacao where codigo = 'SEG-RETORNO-TERCEIROS-5902-O0-CST50' and (ipi_codigo_enquadramento_legal <> '109' or habilitado_producao)) then
    raise exception 'perfil SEG-RETORNO-TERCEIROS-5902-O0-CST50 nao ficou com cEnq 109 e producao desabilitada';
  end if;
end;
$assert$;

notify pgrst, 'reload schema';
