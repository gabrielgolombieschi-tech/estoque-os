-- Aceita APONTADOR na validação central compartilhada pelos caminhos
-- administrativos de salvar e convite. Nenhuma tabela ou vínculo existente é alterado.

do $apontador_admin_validation$
declare
  v_signature regprocedure;
  v_definition text;
  v_patched text;
  v_occurrences integer;
begin
  foreach v_signature in array array[
    'a.validate_empresa_vinculos_payload(uuid,jsonb)'::regprocedure
  ]
  loop
    select pg_get_functiondef(v_signature) into v_definition;

    if position('APONTADOR' in v_definition) > 0 then
      continue;
    end if;

    v_occurrences := (length(v_definition) - length(replace(v_definition, '''PAINEL_TV''', '')))
      / length('''PAINEL_TV''');
    if v_occurrences <> 1 then
      raise exception 'apontador_role_validation_marker_invalid: %, ocorrências=%', v_signature, v_occurrences;
    end if;

    v_patched := replace(
      v_definition,
      '''PAINEL_TV''',
      '''PAINEL_TV'',''APONTADOR'''
    );

    execute v_patched;
  end loop;
end;
$apontador_admin_validation$;

do $apontador_admin_validation_assertions$
declare
  v_signature regprocedure;
begin
  foreach v_signature in array array[
    'a.validate_empresa_vinculos_payload(uuid,jsonb)'::regprocedure
  ]
  loop
    if position('APONTADOR' in pg_get_functiondef(v_signature)) = 0 then
      raise exception 'apontador_role_validation_not_installed: %', v_signature;
    end if;
  end loop;
end;
$apontador_admin_validation_assertions$;

notify pgrst, 'reload schema';
