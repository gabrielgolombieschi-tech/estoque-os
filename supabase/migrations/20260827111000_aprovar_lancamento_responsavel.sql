begin;

set local role postgres;

-- No lancamento inicial de horas normais, o proprio responsavel pela OS ja
-- efetuou a revisao no ato do cadastro. HH continua no fluxo proprio, e uma
-- edicao posterior continua devolvendo o apontamento para pendente.
do $patch_autoaprovacao_responsavel$
declare
  v_definition text;
  v_patched text;
begin
  select pg_get_functiondef('public.fn_apontamento_preparar_aprovacao()'::regprocedure)
    into v_definition;

  v_patched := regexp_replace(
    v_definition,
    E'\n[[:space:]]+and new\\.criado_por_user_id = v_user_id_colaborador then',
    E' then',
    ''
  );

  if v_patched = v_definition then
    raise exception 'autoaprovacao_responsavel_patch_token_not_found';
  end if;

  execute v_patched;
end;
$patch_autoaprovacao_responsavel$;

commit;
