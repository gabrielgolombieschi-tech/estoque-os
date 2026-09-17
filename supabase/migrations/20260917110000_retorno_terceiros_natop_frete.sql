-- Retorno de terceiros: natOp e frete no modelo das notas que a Segau ja emitia no Vertex
-- (NF 3427/1 de 23/09/2025 para a WEG: CFOP 5902, modFrete 0, "RETORNO DE MERCAD. UTILIZADA
-- NA INDUST."). Pedido do Gabriel em 16/09/2026:
--   natOp do 5902 = "RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO POR ENCOMENDA"
--     (65 caracteres; natOp aceita 60, fica "RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO");
--   modalidade do frete padrao 0 (por conta do remetente) em vez de 9.
-- O texto vive no montador (tributacao-provisoria.ts); aqui so a copia informativa da config e
-- o nome do perfil, mais o padrao da RPC para chamadas sem o parametro.

create or replace function f.fn_retorno_terceiros_config()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select jsonb_build_object(
    'cbenef_retorno_sc', 'SC840008',
    'cenq_ipi_retorno', '108',
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

update f.perfil_operacao
   set natureza_texto = 'RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO'
 where natureza_operacao = 'RETORNO_REMESSA_TERCEIROS'
   and natureza_texto = 'RETORNO MERCADORIA RECEBIDA P/ INDUSTRIALIZACAO P/ ENCOMENDA';

-- Padrao da RPC: mesma definicao, so o DEFAULT do frete muda (Postgres nao tem ALTER para isso).
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('f.fn_remessa_terceiros_retorno_criar(uuid,text,smallint,text,jsonb)'::regprocedure) into v_def;
  if v_def not like '%p_modalidade_frete smallint DEFAULT 9%' then
    raise exception 'fn_remessa_terceiros_retorno_criar sem o DEFAULT 9 esperado; conferir a definicao antes de trocar o padrao';
  end if;
  execute replace(v_def, 'p_modalidade_frete smallint DEFAULT 9', 'p_modalidade_frete smallint DEFAULT 0');
end $$;
