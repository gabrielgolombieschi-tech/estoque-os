-- Remove o falso positivo "possivel divida sem classificacao" quando o titulo
-- ja possui uma categoria gerencial ativa. Todos os demais alertas permanecem.

do $patch_function$
declare
  v_assinatura constant regprocedure :=
    'f.relatorio_saude_financeira(uuid,uuid,date,date)'::regprocedure;
  v_definicao text;
  v_trecho_original constant text :=
    '      and not coalesce(rs.plano_divida, false)';
  v_trecho_novo constant text :=
    '      and not coalesce(rs.plano_divida, false)
      and not exists (
        select 1
        from f.titulo_classificacao_compromisso tc_compromisso
        where tc_compromisso.tenant_id = p_tenant_id
          and tc_compromisso.empresa_id = p_empresa_id
          and tc_compromisso.titulo_id = t.id
          and tc_compromisso.deleted_at is null
      )';
  v_ocorrencias integer;
begin
  select pg_get_functiondef(v_assinatura)
  into v_definicao;

  v_ocorrencias :=
    (
      length(v_definicao)
        - length(replace(v_definicao, v_trecho_original, ''))
    ) / length(v_trecho_original);

  if v_ocorrencias <> 1 then
    raise exception
      'Patch da Saude Financeira abortado: trecho esperado apareceu % vezes.',
      v_ocorrencias;
  end if;

  v_definicao := replace(
    v_definicao,
    v_trecho_original,
    v_trecho_novo
  );

  execute v_definicao;
end;
$patch_function$;

comment on function
  f.relatorio_saude_financeira(uuid, uuid, date, date) is
  'Relatorio executivo de saude financeira; classificacoes ativas eliminam falsos alertas de divida nao classificada.';
