-- Orcamento no app: condicao de pagamento e solicitante na criacao, e o painel
-- de orcamentos da tela Inicio. Pedido de Gabriel em 07/09/2026.
--
-- 1. Condicao de pagamento deixa de ficar de fora. Ela nao e enfeite: o gatilho
--    m.trg_orcamento_biu le c.condicao_pagamento.acrescimo_percent e grava em
--    acrescimo_cond_pag_percent, que entra no calculo de cada item
--    (m.fn_orcamento_item_calcular). Criar sem ela era criar com custo
--    financeiro zero.
--
-- 2. Solicitante. Os campos ja existiam em m.orcamento e sao exatamente o
--    cabecalho da proposta tecnica (nome, setor, e-mail, telefone). A web
--    sugere contatos de public.cliente_contatos, ordenados por principal,
--    ultimo uso e frequencia, e grava de volta o contato usado. O app passa a
--    fazer os dois.
--
-- 3. Painel de orcamentos para a Home.
--    ATENCAO ao que "fechado no mes" significa aqui: nao existe tabela de
--    historico de status nem coluna com a data do fechamento — so status e
--    emissao_date, e updated_at muda em qualquer edicao. Entao os dois numeros
--    olham a MESMA safra: dos orcamentos emitidos naquele mes, quanto foi
--    orcado e quanto ja fechou. E a leitura que responde "do que propus em
--    agosto, quanto virou venda", e da a taxa de conversao. Se um dia for
--    preciso "fechado na data em que fechou", o caminho e gravar a data da
--    mudanca de status.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Condicoes de pagamento ----------------------------------------------------

create or replace function public.app_orcamento_condicoes_pagamento()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'c'
set row_security to 'off'
as $function$
declare
  v_scope record;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', condicao.id,
      'nome', condicao.nome,
      'dias', condicao.dias,
      'acrescimo_percent', condicao.acrescimo_percent
    ) order by condicao.acrescimo_percent, condicao.nome)
    from c.condicao_pagamento as condicao
    where condicao.tenant_id = v_scope.tenant_id
      and condicao.empresa_id = v_scope.empresa_id
      and condicao.ativo is true
      and condicao.deleted_at is null
  ), '[]'::jsonb);
end;
$function$;

-- 2. Contatos ja usados com aquele cliente -------------------------------------

create or replace function public.app_orcamento_contatos_cliente(p_cliente_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_scope record;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', contato.id,
      'nome', contato.nome,
      'setor', contato.setor,
      'email', contato.email,
      'telefone', contato.telefone,
      'principal', contato.principal
    ))
    from (
      select ct.id, ct.nome, ct.setor, ct.email, ct.telefone, ct.principal
      from public.cliente_contatos as ct
      where ct.tenant_id = v_scope.tenant_id
        and ct.empresa_id = v_scope.empresa_id
        and ct.cliente_id = p_cliente_id
        and ct.ativo is true
      -- Mesma ordem da web: principal, quem foi usado por ultimo, quem mais
      -- se repete, e so entao alfabetica.
      order by ct.principal desc nulls last,
               ct.ultimo_uso_em desc nulls last,
               ct.vezes_usado desc nulls last,
               ct.nome
      limit 25
    ) as contato
  ), '[]'::jsonb);
end;
$function$;

-- 3. Criacao com condicao e solicitante ----------------------------------------

create or replace function public.app_orcamento_criar(
  p_cliente_id integer,
  p_titulo text,
  p_condicao_pagamento_id uuid default null,
  p_solicitante_nome text default null,
  p_solicitante_setor text default null,
  p_solicitante_email text default null,
  p_solicitante_telefone text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'c', 'a'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_titulo text := nullif(btrim(p_titulo), '');
  v_nome text := nullif(btrim(p_solicitante_nome), '');
  v_setor text := nullif(btrim(p_solicitante_setor), '');
  v_email text := lower(nullif(btrim(p_solicitante_email), ''));
  v_telefone text := nullif(btrim(p_solicitante_telefone), '');
  v_id uuid;
  v_codigo text;
  v_contato_id bigint;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  if v_titulo is null or char_length(v_titulo) < 3 then
    raise exception 'Informe um título com pelo menos 3 caracteres.';
  end if;
  if p_cliente_id is null then
    raise exception 'Selecione o cliente do orçamento.';
  end if;
  if p_condicao_pagamento_id is null then
    raise exception 'Selecione a condição de pagamento.';
  end if;
  if v_nome is null then
    raise exception 'Informe o nome do solicitante.';
  end if;

  if not exists (
    select 1
    from c.condicao_pagamento as condicao
    where condicao.id = p_condicao_pagamento_id
      and condicao.tenant_id = v_scope.tenant_id
      and condicao.empresa_id = v_scope.empresa_id
      and condicao.ativo is true
      and condicao.deleted_at is null
  ) then
    raise exception 'Condição de pagamento inválida para esta empresa.';
  end if;

  -- numero, versao, codigo e o acrescimo da condicao saem do gatilho
  -- m.trg_orcamento_biu, que tambem recusa cliente ou vendedor invalidos.
  insert into m.orcamento (
    tenant_id, empresa_id, titulo, cliente_id, vendedor_usuario_id,
    condicao_pagamento_id, solicitante_nome, solicitante_setor,
    solicitante_email, solicitante_telefone
  )
  values (
    v_scope.tenant_id, v_scope.empresa_id, v_titulo, p_cliente_id, v_scope.usuario_id,
    p_condicao_pagamento_id, upper(v_nome), upper(v_setor),
    v_email, v_telefone
  )
  returning id, codigo into v_id, v_codigo;

  -- Guarda o contato para a proxima vez, como a web faz. Sem e-mail nao da
  -- para casar com um contato existente, entao nao grava.
  if v_email is not null then
    select ct.id into v_contato_id
    from public.cliente_contatos as ct
    where ct.tenant_id = v_scope.tenant_id
      and ct.empresa_id = v_scope.empresa_id
      and ct.cliente_id = p_cliente_id
      and lower(btrim(ct.email)) = v_email
    limit 1;

    if v_contato_id is null then
      insert into public.cliente_contatos (
        tenant_id, empresa_id, cliente_id, nome, setor, email, telefone,
        ativo, principal, vezes_usado, ultimo_uso_em
      )
      values (
        v_scope.tenant_id, v_scope.empresa_id, p_cliente_id, upper(v_nome), upper(v_setor),
        v_email, v_telefone, true, false, 1, now()
      );
    else
      update public.cliente_contatos
         set nome = coalesce(upper(v_nome), nome),
             setor = coalesce(upper(v_setor), setor),
             telefone = coalesce(v_telefone, telefone),
             ativo = true,
             vezes_usado = coalesce(vezes_usado, 0) + 1,
             ultimo_uso_em = now(),
             updated_at = now()
       where id = v_contato_id;
    end if;
  end if;

  return jsonb_build_object('id', v_id, 'codigo', v_codigo);
end;
$function$;

-- 4. Detalhe passa a mostrar condicao e solicitante ----------------------------

do $patch_detalhe$
declare
  v_definition text;
  v_needle text := $needle$    'desconto_global_percent', orcamento.desconto_global_percent,$needle$;
  v_replacement text := $replacement$    'desconto_global_percent', orcamento.desconto_global_percent,
    'acrescimo_cond_pag_percent', orcamento.acrescimo_cond_pag_percent,
    'condicao_pagamento', (
      select condicao.nome
      from c.condicao_pagamento as condicao
      where condicao.id = orcamento.condicao_pagamento_id
    ),
    'solicitante_nome', orcamento.solicitante_nome,
    'solicitante_setor', orcamento.solicitante_setor,
    'solicitante_email', orcamento.solicitante_email,
    'solicitante_telefone', orcamento.solicitante_telefone,$replacement$;
begin
  select pg_get_functiondef('public.app_orcamento_detalhe(uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'detalhe_orcamento_token_not_found';
  end if;

  -- A funcao precisa enxergar o schema c para ler a condicao.
  v_definition := replace(
    v_definition,
    $antigo$SET search_path TO 'pg_catalog', 'public', 'm'$antigo$,
    $novo$SET search_path TO 'pg_catalog', 'public', 'm', 'c'$novo$
  );
  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_detalhe$;

-- 5. Painel de orcamentos da Home ----------------------------------------------

create or replace function public.app_orcamento_painel(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_ano integer := coalesce(p_ano, extract(year from current_date)::integer);
  v_mes integer := coalesce(p_mes, extract(month from current_date)::integer);
  v_meses jsonb;
  v_clientes jsonb;
  v_orcado_ano numeric;
  v_fechado_ano numeric;
  v_orcado_mes numeric;
  v_fechado_mes numeric;
  v_qtd_mes integer;
  v_qtd_fechada_mes integer;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  if v_mes < 1 or v_mes > 12 then
    raise exception 'Mês inválido.';
  end if;

  with base as (
    select
      extract(month from orcamento.emissao_date)::integer as mes,
      orcamento.cliente_id,
      coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado')::text as cliente_nome,
      orcamento.total_liquido,
      orcamento.status
    from m.orcamento as orcamento
    left join public.clientes as cliente
      on cliente.id = orcamento.cliente_id
     and cliente.tenant_id = orcamento.tenant_id
    where orcamento.tenant_id = v_scope.tenant_id
      and orcamento.empresa_id = v_scope.empresa_id
      and orcamento.deleted_at is null
      and orcamento.emissao_date >= make_date(v_ano, 1, 1)
      and orcamento.emissao_date < make_date(v_ano + 1, 1, 1)
  ),
  por_mes as (
    select
      serie.mes,
      coalesce(sum(base.total_liquido), 0)::numeric as orcado,
      coalesce(sum(base.total_liquido) filter (where base.status = 'FECHADO'), 0)::numeric as fechado,
      count(base.cliente_id) as quantidade,
      count(*) filter (where base.status = 'FECHADO') as quantidade_fechada
    from generate_series(1, 12) as serie(mes)
    left join base on base.mes = serie.mes
    group by serie.mes
  ),
  por_cliente as (
    select
      base.cliente_id,
      base.cliente_nome,
      sum(base.total_liquido)::numeric as orcado,
      coalesce(sum(base.total_liquido) filter (where base.status = 'FECHADO'), 0)::numeric as fechado
    from base
    where base.mes = v_mes
    group by base.cliente_id, base.cliente_nome
    having sum(base.total_liquido) <> 0
    order by 3 desc
    limit 15
  )
  select
    (select jsonb_agg(jsonb_build_object('mes', mes, 'orcado', orcado, 'fechado', fechado) order by mes) from por_mes),
    (select coalesce(sum(orcado), 0) from por_mes),
    (select coalesce(sum(fechado), 0) from por_mes),
    (select coalesce(sum(orcado), 0) from por_mes where mes = v_mes),
    (select coalesce(sum(fechado), 0) from por_mes where mes = v_mes),
    (select coalesce(sum(quantidade), 0)::integer from por_mes where mes = v_mes),
    (select coalesce(sum(quantidade_fechada), 0)::integer from por_mes where mes = v_mes),
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'cliente_id', cliente_id,
        'nome', cliente_nome,
        'orcado', orcado,
        'fechado', fechado
      )), '[]'::jsonb)
      from por_cliente
    )
    into v_meses, v_orcado_ano, v_fechado_ano, v_orcado_mes, v_fechado_mes,
         v_qtd_mes, v_qtd_fechada_mes, v_clientes;

  return jsonb_build_object(
    'ano', v_ano,
    'mes', v_mes,
    'orcado_ano', coalesce(v_orcado_ano, 0),
    'fechado_ano', coalesce(v_fechado_ano, 0),
    'orcado_mes', coalesce(v_orcado_mes, 0),
    'fechado_mes', coalesce(v_fechado_mes, 0),
    'quantidade_mes', coalesce(v_qtd_mes, 0),
    'quantidade_fechada_mes', coalesce(v_qtd_fechada_mes, 0),
    'meses', coalesce(v_meses, '[]'::jsonb),
    'clientes', coalesce(v_clientes, '[]'::jsonb)
  );
end;
$function$;

-- 6. Grants ---------------------------------------------------------------------

do $grants$
declare
  v_assinatura text;
begin
  foreach v_assinatura in array array[
    'public.app_orcamento_condicoes_pagamento()',
    'public.app_orcamento_contatos_cliente(integer)',
    'public.app_orcamento_criar(integer, text, uuid, text, text, text, text)',
    'public.app_orcamento_painel(integer, integer)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', v_assinatura);
    execute format('grant execute on function %s to authenticated', v_assinatura);
  end loop;
end;
$grants$;

-- A assinatura antiga de app_orcamento_criar sai: era ela que deixava criar sem
-- condicao de pagamento e sem solicitante, justamente o que este ajuste veio
-- proibir. Nenhuma versao publicada do app usava — a de duas colunas foi criada
-- hoje e ainda nao saiu em build.
drop function if exists public.app_orcamento_criar(integer, text);

do $assertions$
begin
  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_orcamento_criar'
  ) <> 1 then
    raise exception 'app_orcamento_criar_com_assinatura_duplicada';
  end if;

  if position('solicitante_nome' in pg_get_functiondef('public.app_orcamento_detalhe(uuid)'::regprocedure)) = 0 then
    raise exception 'detalhe_sem_solicitante';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
