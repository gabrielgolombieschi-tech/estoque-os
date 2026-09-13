-- Tablet de apontamento: definicoes finais de Gabriel em 11/09/2026.
--
-- 1. Classificacao automatica da hora pela data. O colaborador so informa horas e
--    minutos; o tipo de hora sai da mesma regra que a tela web de apontamentos ja
--    aplica (app/apontamentos/page.tsx, suggestionFor): feriado ou domingo entram
--    como EXTRA_100, sabado como EXTRA_50, dia util como NORMAL — e, em dia util,
--    o que passar de 9 h num lancamento vira EXTRA_50. Nada disso e novo; a regra
--    so muda de lugar: no servidor, para o tablet nao depender da tela.
--
--    O calendario de feriados do servidor e public.feriados. Em producao ela
--    estava VAZIA (0 linhas em 11/09/2026): o web nunca a usou — ele carrega a
--    lista lib/datas/feriadosJoinville.ts, com fontes oficiais conferidas em
--    30/08/2026. Esta migration grava nessa tabela o mesmo calendario de 2026 e
--    2027 (nacionais + municipais de Joinville, sem pontos facultativos). Efeito
--    colateral, e desejado: home_sala_controle e app_verificar_feriado (tela de
--    HH) passam a enxergar esses feriados, como o web ja fazia por conta propria.
--    Nao ha tela para manter a tabela: o calendario de 2028 em diante precisa
--    ser gravado por migration (ou por um admin, que a policy permite).
--
-- 2. Janela de datas: hoje e os 15 dias corridos anteriores, inclusive, no fuso
--    da operacao. Fora disso o servidor recusa. O aviso de retroatividade acima
--    de 7 dias continua.
--
-- 3. OS de HH ficam fora da lista do tablet: RPCs proprias de listagem, so para
--    a conta do tablet, com as OS abertas (nao HH) agrupadas por cliente.
--
-- 4. PIN: so Admin e Diretor definem (a coordenacao saiu do gate); e o proprio
--    colaborador digita o PIN no celular do admin, pelo app — por isso ha uma
--    listagem de colaboradores para essa tela, que nao exige que o admin esteja
--    vinculado a um colaborador.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Calendario de feriados ------------------------------------------------------

insert into public.feriados (data, descricao, abrangencia) values
  ('2026-01-01', 'Confraternização Universal', 'NACIONAL'),
  ('2026-03-09', 'Aniversário de Joinville', 'MUNICIPAL'),
  ('2026-04-03', 'Sexta-Feira da Paixão', 'MUNICIPAL'),
  ('2026-04-21', 'Tiradentes', 'NACIONAL'),
  ('2026-05-01', 'Dia do Trabalhador', 'NACIONAL'),
  ('2026-06-04', 'Corpus Christi', 'MUNICIPAL'),
  ('2026-09-07', 'Independência do Brasil', 'NACIONAL'),
  ('2026-10-12', 'Nossa Senhora Aparecida', 'NACIONAL'),
  ('2026-11-02', 'Finados', 'NACIONAL'),
  ('2026-11-15', 'Proclamação da República', 'NACIONAL'),
  ('2026-11-20', 'Dia Nacional de Zumbi e da Consciência Negra', 'NACIONAL'),
  ('2026-12-25', 'Natal', 'NACIONAL'),
  ('2027-01-01', 'Confraternização Universal', 'NACIONAL'),
  ('2027-03-09', 'Aniversário de Joinville', 'MUNICIPAL'),
  ('2027-03-26', 'Sexta-Feira da Paixão', 'MUNICIPAL'),
  ('2027-04-21', 'Tiradentes', 'NACIONAL'),
  ('2027-05-01', 'Dia do Trabalhador', 'NACIONAL'),
  ('2027-05-27', 'Corpus Christi', 'MUNICIPAL'),
  ('2027-09-07', 'Independência do Brasil', 'NACIONAL'),
  ('2027-10-12', 'Nossa Senhora Aparecida', 'NACIONAL'),
  ('2027-11-02', 'Finados', 'NACIONAL'),
  ('2027-11-15', 'Proclamação da República', 'NACIONAL'),
  ('2027-11-20', 'Dia Nacional de Zumbi e da Consciência Negra', 'NACIONAL'),
  ('2027-12-25', 'Natal', 'NACIONAL')
on conflict (data, abrangencia) do nothing;

-- 2. Um lancamento do tablet pode virar mais de uma linha (9 h normais + extra) --

alter table public.tablet_lancamentos
  add column if not exists apontamento_ids uuid[] not null default '{}'::uuid[];

update public.tablet_lancamentos
   set apontamento_ids = array[apontamento_id]
 where cardinality(apontamento_ids) = 0
   and apontamento_id is not null;

alter table public.tablet_lancamentos drop column if exists apontamento_id;

comment on column public.tablet_lancamentos.apontamento_ids is
  'Linhas de apontamentos_horas gravadas por este envio (em dia util, acima de 9 h o excedente vira uma segunda linha em EXTRA_50).';

-- 3. Classificacao da hora pela data ----------------------------------------------

-- Espelho de suggestionFor() da tela web de apontamentos. Devolve o tipo base do
-- dia e, quando p_horas vem preenchido, as partes em que o lancamento se divide.
-- 'faltando' lista os codigos de tipo de hora que a empresa nao tem ativos.
create or replace function public.fn_tablet_classificar(p_tenant_id uuid, p_data date, p_horas numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  c_limite_normal constant numeric := 9;
  v_feriado text;
  v_dia text;
  v_rotulo text;
  v_codigo_base text;
  v_codigo_excedente text;
  v_partes jsonb := '[]'::jsonb;
  v_faltando jsonb := '[]'::jsonb;
  v_codigos text[];
  v_codigo text;
  v_tipo record;
  v_tipos jsonb := '{}'::jsonb;
begin
  select feriado.descricao::text
    into v_feriado
  from public.feriados as feriado
  where feriado.data = p_data
  order by feriado.abrangencia, feriado.descricao nulls last
  limit 1;

  if v_feriado is not null then
    v_dia := 'feriado';
    v_rotulo := 'Feriado: ' || v_feriado;
    v_codigo_base := 'EXTRA_100';
  elsif extract(dow from p_data) = 0 then
    v_dia := 'domingo';
    v_rotulo := 'Domingo';
    v_codigo_base := 'EXTRA_100';
  elsif extract(dow from p_data) = 6 then
    v_dia := 'sabado';
    v_rotulo := 'Sábado';
    v_codigo_base := 'EXTRA_50';
  else
    v_dia := 'util';
    v_rotulo := 'Dia útil';
    v_codigo_base := 'NORMAL';
    v_codigo_excedente := 'EXTRA_50';
  end if;

  v_codigos := array[v_codigo_base] || case when v_codigo_excedente is null then '{}'::text[] else array[v_codigo_excedente] end;
  foreach v_codigo in array v_codigos loop
    select tipo.id, tipo.descricao, tipo.fator
      into v_tipo
    from public.tipos_horas as tipo
    where tipo.tenant_id = p_tenant_id
      and tipo.ativo
      and upper(btrim(tipo.codigo)) = v_codigo
    order by tipo.descricao
    limit 1;
    if not found then
      v_faltando := v_faltando || to_jsonb(v_codigo);
    else
      v_tipos := v_tipos || jsonb_build_object(v_codigo, jsonb_build_object('id', v_tipo.id, 'nome', v_tipo.descricao, 'fator', v_tipo.fator));
    end if;
  end loop;

  if p_horas is not null and p_horas > 0 and jsonb_array_length(v_faltando) = 0 then
    if v_codigo_excedente is not null and p_horas > c_limite_normal then
      v_partes := jsonb_build_array(
        jsonb_build_object('codigo', v_codigo_base, 'tipo_hora_id', v_tipos -> v_codigo_base ->> 'id',
          'tipo_nome', v_tipos -> v_codigo_base ->> 'nome', 'fator', (v_tipos -> v_codigo_base ->> 'fator')::numeric, 'horas', c_limite_normal),
        jsonb_build_object('codigo', v_codigo_excedente, 'tipo_hora_id', v_tipos -> v_codigo_excedente ->> 'id',
          'tipo_nome', v_tipos -> v_codigo_excedente ->> 'nome', 'fator', (v_tipos -> v_codigo_excedente ->> 'fator')::numeric, 'horas', round(p_horas - c_limite_normal, 2))
      );
    else
      v_partes := jsonb_build_array(
        jsonb_build_object('codigo', v_codigo_base, 'tipo_hora_id', v_tipos -> v_codigo_base ->> 'id',
          'tipo_nome', v_tipos -> v_codigo_base ->> 'nome', 'fator', (v_tipos -> v_codigo_base ->> 'fator')::numeric, 'horas', p_horas)
      );
    end if;
  end if;

  return jsonb_build_object(
    'dia', v_dia,
    'rotulo', v_rotulo,
    'feriado', v_feriado,
    'codigo_base', v_codigo_base,
    'tipo_nome_base', v_tipos -> v_codigo_base ->> 'nome',
    'fator_base', (v_tipos -> v_codigo_base ->> 'fator')::numeric,
    'limite_normal_horas', case when v_codigo_excedente is null then null else c_limite_normal end,
    'codigo_excedente', v_codigo_excedente,
    'tipo_nome_excedente', case when v_codigo_excedente is null then null else v_tipos -> v_codigo_excedente ->> 'nome' end,
    'partes', v_partes,
    'faltando', v_faltando
  );
end;
$function$;

-- Janela de datas do tablet: hoje (fuso da operacao) e os 15 dias anteriores.
create or replace function public.fn_tablet_janela()
returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_build_object(
    'de', public.fn_tablet_data_hoje() - 15,
    'ate', public.fn_tablet_data_hoje(),
    'dias', 15
  );
$$;

-- 4. Consulta do dia com a classificacao e a janela ----------------------------

create or replace function public.app_tablet_apontamentos_do_dia(p_sessao_token text, p_os_id integer, p_data date)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $function$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
  v_hoje date := public.fn_tablet_data_hoje();
  v_os jsonb;
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;
  if p_os_id is null or p_data is null then
    return public.fn_tablet_erro('parametros', 'Informe a OS e a data.');
  end if;
  if p_data > v_hoje or p_data < v_hoje - 15 then
    return public.fn_tablet_erro('data_fora_da_janela',
      format('Só é possível lançar de %s a %s (hoje e os 15 dias anteriores).', to_char(v_hoje - 15, 'DD/MM/YYYY'), to_char(v_hoje, 'DD/MM/YYYY')))
      || jsonb_build_object('janela', public.fn_tablet_janela());
  end if;

  v_os := public.fn_tablet_os_situacao(v_sessao.tenant_id, v_sessao.empresa_id, p_os_id);
  if not coalesce((v_os ->> 'encontrada')::boolean, false) then
    return public.fn_tablet_erro('os', v_os ->> 'motivo_bloqueio');
  end if;

  return jsonb_build_object(
    'sucesso', true,
    'os', v_os,
    'data', p_data,
    'hoje', v_hoje,
    'janela', public.fn_tablet_janela(),
    'classificacao', public.fn_tablet_classificar(v_sessao.tenant_id, p_data, null),
    'colaborador_id', v_sessao.colaborador_id,
    'erros', '[]'::jsonb,
    'avisos', '[]'::jsonb
  ) || public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_os_id, p_data);
end;
$function$;

-- 5. Lancamento: janela, classificacao automatica, uma linha por parte ----------

create or replace function public.app_tablet_lancar_horas(
  p_sessao_token text,
  p_os_id integer,
  p_data date,
  p_horas integer,
  p_minutos integer,
  p_chave uuid,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'extensions'
set row_security to 'off'
as $function$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
  v_hoje date := public.fn_tablet_data_hoje();
  v_repetido public.tablet_lancamentos;
  v_colaborador_nome text;
  v_colaborador_ativo boolean;
  v_os jsonb;
  v_minutos integer;
  v_horas numeric;
  v_classificacao jsonb;
  v_parte jsonb;
  v_total_dia numeric;
  v_avisos jsonb := '[]'::jsonb;
  v_ids uuid[] := '{}'::uuid[];
  v_id uuid;
  v_resultado jsonb;
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;

  if p_chave is null then
    return public.fn_tablet_erro('chave', 'Chave de envio ausente. Tente novamente.');
  end if;

  -- Reenvio da mesma chave: devolve o que ja foi gravado, com o resumo atual.
  select lancamento.*
    into v_repetido
  from public.tablet_lancamentos as lancamento
  join public.tablet_sessoes as sessao on sessao.id = lancamento.sessao_id
  where lancamento.chave = p_chave
    and sessao.dispositivo_id = v_sessao.dispositivo_id
    and sessao.colaborador_id = v_sessao.colaborador_id;
  if found then
    return (v_repetido.resultado - 'resumo')
      || jsonb_build_object(
           'repetido', true,
           'resumo', public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id,
                       (v_repetido.resultado ->> 'os_id')::integer, (v_repetido.resultado ->> 'data')::date)
         );
  end if;

  select colaborador.nome, colaborador.ativo
    into v_colaborador_nome, v_colaborador_ativo
  from public.colaboradores as colaborador
  where colaborador.id = v_sessao.colaborador_id
    and colaborador.tenant_id = v_sessao.tenant_id
    and colaborador.empresa_id = v_sessao.empresa_id;
  if not found or not coalesce(v_colaborador_ativo, false) then
    update public.tablet_sessoes set encerrada_em = now(), encerrada_motivo = 'colaborador_inativo' where id = v_sessao.id;
    return public.fn_tablet_erro('colaborador_inativo', 'Seu cadastro de colaborador está inativo. Procure a coordenação.');
  end if;

  if p_data is null then
    return public.fn_tablet_erro('data', 'Informe a data do trabalho.');
  elsif p_data > v_hoje then
    return public.fn_tablet_erro('data_futura', 'Não é permitido lançar horas em data futura.');
  elsif p_data < v_hoje - 15 then
    return public.fn_tablet_erro('data_fora_da_janela',
      format('Só é possível lançar de %s a %s (hoje e os 15 dias anteriores). Para datas anteriores, procure a coordenação.',
        to_char(v_hoje - 15, 'DD/MM/YYYY'), to_char(v_hoje, 'DD/MM/YYYY')))
      || jsonb_build_object('janela', public.fn_tablet_janela());
  end if;

  if p_horas is null or p_minutos is null or p_horas < 0 or p_horas > 24 or p_minutos < 0 or p_minutos > 59 then
    return public.fn_tablet_erro('duracao', 'Informe horas entre 0 e 24 e minutos entre 0 e 59.');
  end if;
  v_minutos := p_horas * 60 + p_minutos;
  if v_minutos <= 0 then
    return public.fn_tablet_erro('duracao', 'A duração precisa ser maior que zero.');
  elsif v_minutos > 24 * 60 then
    return public.fn_tablet_erro('duracao', 'A duração não pode passar de 24 horas.');
  end if;
  v_horas := round(v_minutos / 60.0, 2);

  v_os := public.fn_tablet_os_situacao(v_sessao.tenant_id, v_sessao.empresa_id, p_os_id);
  if not coalesce((v_os ->> 'encontrada')::boolean, false) then
    return public.fn_tablet_erro('os', v_os ->> 'motivo_bloqueio');
  end if;
  -- Colaborador comum so lanca em OS aberta. Se ela fechou enquanto a pessoa
  -- preenchia, para aqui: o caminho para OS encerrada e o da coordenacao.
  if not coalesce((v_os ->> 'pode_lancar')::boolean, false) then
    return public.fn_tablet_erro('os_encerrada', v_os ->> 'motivo_bloqueio') || jsonb_build_object('os', v_os);
  end if;

  if not exists (
    select 1
    from public.colaborador_taxas as taxa
    where taxa.colaborador_id = v_sessao.colaborador_id
      and taxa.tenant_id = v_sessao.tenant_id
      and taxa.empresa_id = v_sessao.empresa_id
      and p_data >= taxa.vigencia_inicio
      and (taxa.vigencia_fim is null or p_data <= taxa.vigencia_fim)
  ) then
    return public.fn_tablet_erro('taxa_vigente',
      format('%s não possui taxa vigente em %s. Procure a coordenação.', v_colaborador_nome, to_char(p_data, 'DD/MM/YYYY')));
  end if;

  -- Tipo de hora pela data (feriado, domingo, sabado, dia util e o excedente de 9 h).
  v_classificacao := public.fn_tablet_classificar(v_sessao.tenant_id, p_data, v_horas);
  if jsonb_array_length(v_classificacao -> 'faltando') > 0 then
    return public.fn_tablet_erro('configuracao',
      format('Falta cadastrar o tipo de hora %s ativo em Tipos de hora para classificar %s. Procure a coordenação.',
        (select string_agg(codigo, ', ') from jsonb_array_elements_text(v_classificacao -> 'faltando') as codigo),
        lower(v_classificacao ->> 'rotulo')))
      || jsonb_build_object('classificacao', v_classificacao);
  end if;

  -- Mesmos avisos do app: retroativo (> 7 dias) e jornada acima de 9 h no dia.
  if p_data < v_hoje - 7 then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('tipo', 'retroativo',
      'mensagem', format('Este apontamento é retroativo: a data %s tem mais de 7 dias.', to_char(p_data, 'DD/MM/YYYY'))));
  end if;
  select coalesce(sum(apontamento.horas), 0)
    into v_total_dia
  from public.apontamentos_horas as apontamento
  where apontamento.tenant_id = v_sessao.tenant_id
    and apontamento.empresa_id = v_sessao.empresa_id
    and apontamento.colaborador_id = v_sessao.colaborador_id
    and apontamento.data = p_data;
  if v_total_dia + v_horas > 9 then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('tipo', 'jornada_maior_que_9h',
      'mensagem', format('Você ficará com %s h apontadas em %s. Verifique se o intervalo de almoço foi descontado.',
        replace((v_total_dia + v_horas)::text, '.', ','), to_char(p_data, 'DD/MM/YYYY'))));
  end if;
  if jsonb_array_length(v_avisos) > 0 and not p_confirmar_avisos then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', '[]'::jsonb, 'classificacao', v_classificacao);
  end if;

  begin
    for v_parte in select value from jsonb_array_elements(v_classificacao -> 'partes') loop
      insert into public.apontamentos_horas (
        os_id, colaborador_id, data, horas, tipo_hora_id, descricao, status,
        tenant_id, empresa_id, gerado_por_hh, criado_por_user_id, tablet_sessao_id
      ) values (
        p_os_id, v_sessao.colaborador_id, p_data, (v_parte ->> 'horas')::numeric, (v_parte ->> 'tipo_hora_id')::uuid, null, 'lancado',
        v_sessao.tenant_id, v_sessao.empresa_id, false, auth.uid(), v_sessao.id
      )
      returning id into v_id;
      v_ids := v_ids || v_id;
    end loop;

    v_resultado := jsonb_build_object(
      'sucesso', true,
      'gravados', cardinality(v_ids),
      'apontamento_ids', to_jsonb(v_ids),
      'apontamento_id', v_ids[1],
      'os_id', p_os_id,
      'data', p_data,
      'horas', v_horas,
      'minutos', v_minutos,
      'classificacao', v_classificacao,
      'partes', v_classificacao -> 'partes',
      'colaborador_id', v_sessao.colaborador_id,
      'colaborador_nome', v_colaborador_nome,
      'avisos', v_avisos,
      'erros', '[]'::jsonb
    );

    insert into public.tablet_lancamentos (chave, sessao_id, apontamento_ids, resultado)
    values (p_chave, v_sessao.id, v_ids, v_resultado);
  exception
    when unique_violation then
      -- Dois envios da mesma chave chegaram juntos: o segundo perde e devolve o
      -- que o primeiro gravou.
      select lancamento.* into v_repetido from public.tablet_lancamentos as lancamento where lancamento.chave = p_chave;
      if v_repetido.chave is not null then
        return (v_repetido.resultado - 'resumo') || jsonb_build_object('repetido', true,
          'resumo', public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_os_id, p_data));
      end if;
      return public.fn_tablet_erro('banco', sqlerrm);
    when others then
      -- Triggers do apontamento (competencia fechada, taxa, OS fora de andamento)
      -- falam portugues: a mensagem vai direto para a tela.
      return public.fn_tablet_erro('banco', sqlerrm);
  end;

  return v_resultado || jsonb_build_object(
    'resumo', public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_os_id, p_data)
  );
end;
$function$;

-- 6. Lista de OS do tablet: abertas, nao HH, agrupadas por cliente ---------------
-- Mesma busca e mesma ordem de app_os_agrupado_cliente / app_os_do_cliente, sem
-- valores comerciais e so para a conta do tablet.

create or replace function public.app_tablet_os_agrupado_cliente(p_busca text default null)
returns table (
  cliente_id integer,
  cliente_nome text,
  quantidade_os integer,
  responsaveis text[],
  total_horas numeric
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_dispositivo public.tablet_dispositivos := public.fn_tablet_dispositivo_atual();
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if v_dispositivo.id is null then
    raise exception 'Este aparelho não está autorizado como tablet de apontamento.';
  end if;

  return query
  with os_filtradas as (
    select
      os.id,
      os.cliente_id,
      coalesce(nullif(btrim(cliente.nome), ''), nullif(btrim(os.cliente_nome), ''), 'Cliente não informado')::text as cliente_nome,
      coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text as responsavel_nome,
      coalesce(horas.total_horas, 0)::numeric as total_horas
    from public.ordens_servico as os
    left join public.clientes as cliente
      on cliente.id = os.cliente_id
     and cliente.tenant_id = v_dispositivo.tenant_id
     and cliente.empresa_id = v_dispositivo.empresa_id
    left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
    left join a.usuario as usuario
      on usuario.auth_user_id = os.responsavel_aprovacao_id
     and usuario.ativo is true
     and usuario.deleted_at is null
    left join public.colaboradores as colaborador
      on colaborador.user_id = os.responsavel_aprovacao_id
     and colaborador.tenant_id = v_dispositivo.tenant_id
     and colaborador.empresa_id = v_dispositivo.empresa_id
     and colaborador.ativo is true
    left join lateral (
      select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
      from public.apontamentos_horas as apontamento
      where apontamento.os_id = os.id
        and apontamento.tenant_id = v_dispositivo.tenant_id
        and apontamento.empresa_id = v_dispositivo.empresa_id
    ) as horas on true
    where os.tenant_id = v_dispositivo.tenant_id
      and os.empresa_id = v_dispositivo.empresa_id
      and coalesce(os.tipo_documento, 'OS') = 'OS'
      and not coalesce(os.usa_relatorio_hh, false)
      and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, array['em_andamento'])
      and (
        v_busca is null
        or os.numero_os ilike '%' || v_busca || '%'
        or os.os_num::text ilike '%' || v_busca || '%'
        or os.cliente_nome ilike '%' || v_busca || '%'
        or cliente.nome ilike '%' || v_busca || '%'
        or os.descricao_servico ilike '%' || v_busca || '%'
      )
  )
  select
    filtrada.cliente_id,
    filtrada.cliente_nome,
    count(*)::integer,
    coalesce(
      array_agg(distinct filtrada.responsavel_nome order by filtrada.responsavel_nome)
        filter (where filtrada.responsavel_nome is not null),
      '{}'::text[]
    ),
    sum(filtrada.total_horas)::numeric
  from os_filtradas as filtrada
  group by filtrada.cliente_id, filtrada.cliente_nome
  order by lower(filtrada.cliente_nome), filtrada.cliente_id nulls last;
end;
$function$;

create or replace function public.app_tablet_os_do_cliente(p_cliente_id integer)
returns table (
  id integer,
  numero_os character varying,
  os_num bigint,
  cliente_id integer,
  cliente_nome text,
  descricao_servico text,
  status_fluxo text,
  usa_relatorio_hh boolean,
  total_horas numeric,
  responsavel_nome text,
  garantia_motivo text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_dispositivo public.tablet_dispositivos := public.fn_tablet_dispositivo_atual();
begin
  if v_dispositivo.id is null then
    raise exception 'Este aparelho não está autorizado como tablet de apontamento.';
  end if;

  return query
  select
    os.id,
    os.numero_os,
    os.os_num,
    os.cliente_id,
    coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cliente.nome), ''), 'Cliente não informado')::text,
    os.descricao_servico,
    coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status))::text,
    coalesce(os.usa_relatorio_hh, false),
    coalesce(horas.total_horas, 0)::numeric,
    coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text,
    os.garantia_motivo
  from public.ordens_servico as os
  left join public.clientes as cliente
    on cliente.id = os.cliente_id
   and cliente.tenant_id = v_dispositivo.tenant_id
   and cliente.empresa_id = v_dispositivo.empresa_id
  left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
  left join a.usuario as usuario
    on usuario.auth_user_id = os.responsavel_aprovacao_id
   and usuario.ativo is true
   and usuario.deleted_at is null
  left join public.colaboradores as colaborador
    on colaborador.user_id = os.responsavel_aprovacao_id
   and colaborador.tenant_id = v_dispositivo.tenant_id
   and colaborador.empresa_id = v_dispositivo.empresa_id
   and colaborador.ativo is true
  left join lateral (
    select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
    from public.apontamentos_horas as apontamento
    where apontamento.os_id = os.id
      and apontamento.tenant_id = v_dispositivo.tenant_id
      and apontamento.empresa_id = v_dispositivo.empresa_id
  ) as horas on true
  where os.tenant_id = v_dispositivo.tenant_id
    and os.empresa_id = v_dispositivo.empresa_id
    and coalesce(os.tipo_documento, 'OS') = 'OS'
    and not coalesce(os.usa_relatorio_hh, false)
    and (os.cliente_id = p_cliente_id or (os.cliente_id is null and p_cliente_id is null))
    and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, array['em_andamento'])
  order by os.data_abertura desc nulls last, os.id desc;
end;
$function$;

-- 7. PIN: so Admin e Diretor; lista de colaboradores para a tela do app ---------

create or replace function public.web_tablet_pins_listar()
returns table (colaborador_id uuid, definido_em timestamptz, definido_por_nome text)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);
  return query
  select pin.colaborador_id,
         pin.definido_em,
         coalesce(nullif(btrim(usuario.nome), ''), nullif(btrim(usuario.email), ''))::text
  from public.colaboradores_pin as pin
  left join a.usuario as usuario on usuario.auth_user_id = pin.definido_por_user_id
  where pin.tenant_id = v_ctx.tenant_id
    and pin.empresa_id = v_ctx.empresa_id;
end;
$function$;

create or replace function public.web_tablet_pin_definir(p_colaborador_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_pin text := btrim(coalesce(p_pin, ''));
  v_colaborador_nome text;
  v_colaborador_ativo boolean;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);

  if v_pin !~ '^[0-9]{4}$' then
    return public.fn_tablet_erro('pin_invalido', 'O PIN precisa ter exatamente 4 números.');
  end if;

  select colaborador.nome, colaborador.ativo
    into v_colaborador_nome, v_colaborador_ativo
  from public.colaboradores as colaborador
  where colaborador.id = p_colaborador_id
    and colaborador.tenant_id = v_ctx.tenant_id
    and colaborador.empresa_id = v_ctx.empresa_id;
  if not found then
    return public.fn_tablet_erro('colaborador', 'Colaborador não encontrado nesta empresa.');
  end if;
  if not coalesce(v_colaborador_ativo, false) then
    return public.fn_tablet_erro('colaborador_inativo', 'Ative o colaborador antes de definir o PIN.');
  end if;

  -- O PIN identifica uma unica pessoa na empresa, sem escolher nome antes.
  -- Inativos tambem contam: se voltarem, o PIN deles nao pode colidir.
  if exists (
    select 1
    from public.colaboradores_pin as pin
    where pin.tenant_id = v_ctx.tenant_id
      and pin.empresa_id = v_ctx.empresa_id
      and pin.colaborador_id <> p_colaborador_id
      and pin.pin_hash = extensions.crypt(v_pin, pin.pin_hash)
  ) then
    return public.fn_tablet_erro('pin_em_uso', 'Este PIN já está em uso por outra pessoa. Escolha outro.');
  end if;

  insert into public.colaboradores_pin (colaborador_id, tenant_id, empresa_id, pin_hash, definido_em, definido_por_user_id)
  values (p_colaborador_id, v_ctx.tenant_id, v_ctx.empresa_id, extensions.crypt(v_pin, extensions.gen_salt('bf', 6)), now(), auth.uid())
  on conflict (colaborador_id) do update
    set pin_hash = excluded.pin_hash,
        definido_em = now(),
        definido_por_user_id = auth.uid();

  -- PIN novo derruba a identificacao antiga que porventura esteja aberta.
  update public.tablet_sessoes
     set encerrada_em = now(), encerrada_motivo = 'pin_redefinido'
   where colaborador_id = p_colaborador_id
     and encerrada_em is null;

  return jsonb_build_object('sucesso', true, 'colaborador_nome', v_colaborador_nome, 'definido_em', now());
end;
$function$;

create or replace function public.web_tablet_pin_remover(p_colaborador_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);

  delete from public.colaboradores_pin
  where colaborador_id = p_colaborador_id
    and tenant_id = v_ctx.tenant_id
    and empresa_id = v_ctx.empresa_id;

  update public.tablet_sessoes
     set encerrada_em = now(), encerrada_motivo = 'pin_removido'
   where colaborador_id = p_colaborador_id
     and encerrada_em is null;

  return jsonb_build_object('sucesso', true);
end;
$function$;

-- Colaboradores ativos da empresa com a situacao do PIN, para a tela do app em
-- que o proprio colaborador digita o PIN no celular do admin. Nao exige que o
-- admin esteja vinculado a um colaborador (app_listar_colaboradores exige).
create or replace function public.app_tablet_pins_colaboradores()
returns table (id uuid, nome character varying, cargo character varying, tem_pin boolean, pin_definido_em timestamptz)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);
  return query
  select colaborador.id,
         colaborador.nome,
         colaborador.cargo,
         (pin.colaborador_id is not null),
         pin.definido_em
  from public.colaboradores as colaborador
  left join public.colaboradores_pin as pin on pin.colaborador_id = colaborador.id
  where colaborador.tenant_id = v_ctx.tenant_id
    and colaborador.empresa_id = v_ctx.empresa_id
    and colaborador.ativo is true
  order by colaborador.nome;
end;
$function$;

-- 8. Grants -----------------------------------------------------------------------

revoke all on function public.fn_tablet_classificar(uuid, date, numeric) from public, anon, authenticated;
revoke all on function public.fn_tablet_janela() from public, anon, authenticated;
revoke all on function public.app_tablet_os_agrupado_cliente(text) from public, anon;
revoke all on function public.app_tablet_os_do_cliente(integer) from public, anon;
revoke all on function public.app_tablet_pins_colaboradores() from public, anon;
grant execute on function public.app_tablet_os_agrupado_cliente(text) to authenticated;
grant execute on function public.app_tablet_os_do_cliente(integer) to authenticated;
grant execute on function public.app_tablet_pins_colaboradores() to authenticated;

-- 9. Conferencia ------------------------------------------------------------------

do $assertions$
declare
  v_acl text;
  v_teste jsonb;
begin
  if (select count(*) from public.feriados where data between '2026-01-01' and '2027-12-31') < 24 then
    raise exception 'calendario_feriados_incompleto';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tablet_lancamentos' and column_name = 'apontamento_id'
  ) then
    raise exception 'tablet_lancamentos_coluna_antiga';
  end if;

  -- A regra do dia nao depende de dados da empresa: 07/09/2026 e feriado,
  -- 06/09/2026 domingo, 05/09/2026 sabado, 04/09/2026 dia util.
  v_teste := public.fn_tablet_classificar(gen_random_uuid(), '2026-09-07');
  if v_teste ->> 'dia' <> 'feriado' or v_teste ->> 'codigo_base' <> 'EXTRA_100' then raise exception 'classificacao_feriado: %', v_teste; end if;
  v_teste := public.fn_tablet_classificar(gen_random_uuid(), '2026-09-06');
  if v_teste ->> 'dia' <> 'domingo' or v_teste ->> 'codigo_base' <> 'EXTRA_100' then raise exception 'classificacao_domingo: %', v_teste; end if;
  v_teste := public.fn_tablet_classificar(gen_random_uuid(), '2026-09-05');
  if v_teste ->> 'dia' <> 'sabado' or v_teste ->> 'codigo_base' <> 'EXTRA_50' then raise exception 'classificacao_sabado: %', v_teste; end if;
  v_teste := public.fn_tablet_classificar(gen_random_uuid(), '2026-09-04');
  if v_teste ->> 'dia' <> 'util' or v_teste ->> 'codigo_base' <> 'NORMAL' or (v_teste ->> 'limite_normal_horas')::numeric <> 9 then raise exception 'classificacao_util: %', v_teste; end if;

  for v_acl in
    select coalesce(p.proacl::text, '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'app\_tablet\_%' or p.proname like 'fn\_tablet\_%')
  loop
    if v_acl like '%anon=%' or v_acl like '{=X%' then
      raise exception 'grant_tablet_aberto: %', v_acl;
    end if;
  end loop;

  if position('''ADMIN'', ''DIRETOR'', ''COORDENACAO''' in pg_get_functiondef('public.web_tablet_pin_definir(uuid,text)'::regprocedure)) > 0 then
    raise exception 'pin_definir_ainda_libera_coordenacao';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
