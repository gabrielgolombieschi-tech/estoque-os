-- RLS: a checagem de permissao passa a rodar uma vez por consulta, nao por linha.
--
-- Problema (17/09/2026): a Ellen (ALMOXARIFADO) nao conseguia cadastrar item pelo
-- agente de cadastro, no web e no app: "canceling statement due to statement timeout".
-- A busca por codigo em public.itens levava 70 s para ela e milissegundos para o ADMIN.
--
-- Causa: policies como itens_select tem
--   can__legacy_40734('estoque','read') OR can__legacy_40734('os','read') OR ...
-- escrito "solto". O Postgres avalia a funcao para CADA linha que a consulta toca
-- (3.703 itens x ~19 ms = 70 s). O ADMIN escapa porque a policy irma, pela
-- tenant_memberships, e um subplano hashed que responde true antes; quem nao tem
-- linha em tenant_memberships (a Ellen) cai na funcao linha por linha.
--
-- Correcao: envolver cada chamada em (select fn(...)). Com isso o planejador vira a
-- chamada em InitPlan, avaliado uma vez por comando. A semantica nao muda: os
-- argumentos sao constantes e as funcoes sao STABLE. O mesmo padrao ja estava na
-- policy enforce_active_empresa_scope, que por isso nunca pesou.
--
-- Vale para toda policy do schema public que chama can(), can__legacy_40734() ou
-- has_permission() sem o (select ...). O laco reescreve USING e WITH CHECK a partir
-- da expressao atual, entao nada de novo e concedido nem retirado.

do $$
declare
  r record;
  v_re constant text := '(?<!SELECT )\m(can__legacy_40734|can|has_permission)\(([^()]*)\)';
  v_qual text;
  v_check text;
  v_sql text;
  v_n int := 0;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (coalesce(qual, '') ~ v_re or coalesce(with_check, '') ~ v_re)
    order by tablename, policyname
  loop
    v_qual := case when r.qual is null then null
                   else regexp_replace(r.qual, v_re, '(select \1(\2))', 'g') end;
    v_check := case when r.with_check is null then null
                    else regexp_replace(r.with_check, v_re, '(select \1(\2))', 'g') end;

    v_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if v_qual is not null and v_qual is distinct from r.qual then
      v_sql := v_sql || ' using (' || v_qual || ')';
    end if;
    if v_check is not null and v_check is distinct from r.with_check then
      v_sql := v_sql || ' with check (' || v_check || ')';
    end if;
    if v_sql like '%using%' or v_sql like '%with check%' then
      execute v_sql;
      v_n := v_n + 1;
    end if;
  end loop;
  raise notice 'policies reescritas com (select fn()): %', v_n;
end $$;

-- Prova: nenhuma policy do public ficou com a chamada solta.
do $$
declare
  v_restantes int;
begin
  select count(*) into v_restantes
  from pg_policies
  where schemaname = 'public'
    and (coalesce(qual, '') ~ '(?<!SELECT )\m(can__legacy_40734|can|has_permission)\('
      or coalesce(with_check, '') ~ '(?<!SELECT )\m(can__legacy_40734|can|has_permission)\(');
  if v_restantes > 0 then
    raise exception 'ainda ha % policies chamando a permissao por linha', v_restantes;
  end if;
end $$;
