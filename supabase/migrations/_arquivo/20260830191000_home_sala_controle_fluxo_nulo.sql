begin;

-- A base legada ainda possui registros cujo status e status_fluxo nao
-- conseguem ser mapeados. O painel deve exibi-los como indefinidos, nunca
-- falhar ao montar o objeto JSON de contagens.
do $repair$
declare
  v_definition text;
  v_original text := E'select fluxo, count(*)::integer as quantidade\n      from base\n      group by fluxo';
  v_replacement text := E'select coalesce(fluxo, ''indefinido'') as fluxo, count(*)::integer as quantidade\n      from base\n      group by coalesce(fluxo, ''indefinido'')';
begin
  select pg_get_functiondef('public.home_sala_controle()'::regprocedure)
    into v_definition;

  if position(v_original in v_definition) = 0 then
    raise exception 'home_sala_controle_trecho_por_status_nao_encontrado';
  end if;

  execute replace(v_definition, v_original, v_replacement);
end;
$repair$;

notify pgrst, 'reload schema';

commit;
