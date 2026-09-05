begin;

-- A coluna historica cclass_trib_versao nao participa mais da equivalencia
-- fiscal. Recria as duas funcoes preservando todas as demais guardas e
-- removendo somente predicados que dependiam desse metadado do fornecedor.
do $migration$
declare
  v_funcao regprocedure;
  v_definicao text;
  v_antes text;
begin
  foreach v_funcao in array array[
    'f.fn_perfil_operacao_nfe_liberar_producao(uuid,uuid,text,boolean)'::regprocedure,
    'f.fn_nfe_producao_pronta(uuid)'::regprocedure
  ]
  loop
    select pg_get_functiondef(v_funcao) into v_definicao;
    v_antes := v_definicao;
    v_definicao := regexp_replace(
      v_definicao,
      E'\\n[^\\n]*cclass_trib_versao[^\\n]*',
      '',
      'g'
    );
    v_definicao := replace(v_definicao, 'Os seis campos IBS/CBS', 'Os cinco campos IBS/CBS');
    if v_definicao = v_antes then
      raise exception 'A migration nao encontrou dependencia de cclass_trib_versao em %.', v_funcao::text;
    end if;
    execute v_definicao;
  end loop;
end;
$migration$;

comment on function f.fn_perfil_operacao_nfe_liberar_producao(uuid, uuid, text, boolean) is
  'Libera producao apos equivalencia da homologacao; a versao da NT e responsabilidade do provedor e nao integra a comparacao fiscal.';
comment on function f.fn_nfe_producao_pronta(uuid) is
  'Valida portoes e equivalencia fiscal com a homologacao, sem tratar versao da NT do fornecedor como valor tributario.';

commit;
