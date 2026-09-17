-- Garantia como atividade interna.
--
-- Pedido do Gabriel em 16/09/2026: a equipe atendeu uma ocorrencia em garantia e nao
-- tinha onde apontar a hora — a OS ja estava faturada, e a hora interna nao tinha essa
-- opcao. Decisao dele: nao precisa escolher OS nem cliente, a pessoa escreve isso na
-- descricao; o que importa e, no fim do ano, saber quantas horas foram para garantia.
--
-- Entao Garantia entra no catalogo como as outras (sem aprovacao, sem custo de OS,
-- conta na meta da semana), com uma regra a mais: pede a descricao, que e onde fica a
-- OS ou o cliente. O tablet do PIN nao tem campo de descricao e continua aceitando —
-- la a hora conta do mesmo jeito, so sem o texto. O "Reabrir como garantia" da OS
-- continua existindo para quem quer a hora com aprovacao e custo na OS.

-- 1. O catalogo de partida ganha a setima atividade; empresa nova nasce com ela.
create or replace function public.fn_atividades_internas_semear(p_tenant_id uuid, p_empresa_id uuid)
returns void
language sql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
  insert into public.atividades_internas (tenant_id, empresa_id, codigo, nome, pede_cliente, ordem)
  values
    (p_tenant_id, p_empresa_id, 'comercial',          'Comercial',             true,  10),
    (p_tenant_id, p_empresa_id, 'treinamento',        'Treinamento',           false, 20),
    (p_tenant_id, p_empresa_id, 'manutencao_fabrica', 'Manutenção da fábrica', false, 30),
    (p_tenant_id, p_empresa_id, 'garantia',           'Garantia',              false, 35),
    (p_tenant_id, p_empresa_id, 'administrativo',     'Administrativo',        false, 40),
    (p_tenant_id, p_empresa_id, 'exames',             'Exames',                false, 50),
    (p_tenant_id, p_empresa_id, 'integracao',         'Integração',            false, 60)
  on conflict (tenant_id, empresa_id, codigo) do nothing;
$fn$;

revoke all on function public.fn_atividades_internas_semear(uuid, uuid) from public, anon, authenticated;

-- Quem ja existe recebe a Garantia agora (as outras seis ja estao la: on conflict).
select public.fn_atividades_internas_semear(e.tenant_id, e.id) from c.empresa as e;

-- 2. Garantia pede a descricao (fora do tablet). Mesma definicao de
--    fn_horas_internas_gravar (20260914140000), com a regra inserida antes da
--    conferencia do cliente — o texto e trocado na definicao atual, sem repetir a funcao.
do $$
declare
  v_oid oid;
  v_def text;
  v_antes text := '  if p_cliente_id is not null and not exists (';
  v_depois text :=
    '  -- Garantia (20260917140000): a OS ou o cliente vem na descricao, entao ela e' || E'\n' ||
    '  -- obrigatoria. O tablet nao tem campo de descricao e fica de fora da regra.' || E'\n' ||
    '  if v_atividade.id is not null and v_atividade.codigo = ''garantia'' and v_descricao is null and p_tablet_sessao_id is null then' || E'\n' ||
    '    v_erros := v_erros || jsonb_build_array(jsonb_build_object(''tipo'', ''descricao'', ''mensagem'', ''Garantia pede a descrição: qual OS ou cliente e o que foi feito.''));' || E'\n' ||
    '  end if;' || E'\n\n' ||
    '  if p_cliente_id is not null and not exists (';
  v_ocorrencias integer;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_horas_internas_gravar';
  if v_oid is null then
    raise exception 'fn_horas_internas_gravar nao encontrada';
  end if;
  v_def := pg_get_functiondef(v_oid);
  if position('v_atividade.codigo = ''garantia''' in v_def) > 0 then
    raise notice 'fn_horas_internas_gravar ja pede a descricao da garantia';
    return;
  end if;
  v_ocorrencias := (length(v_def) - length(replace(v_def, v_antes, ''))) / length(v_antes);
  if v_ocorrencias <> 1 then
    raise exception 'fn_horas_internas_gravar com % ocorrencia(s) da ancora (esperada 1); conferir a definicao', v_ocorrencias;
  end if;
  execute replace(v_def, v_antes, v_depois);
end $$;
