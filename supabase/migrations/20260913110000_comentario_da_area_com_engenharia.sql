-- =====================================================================================
-- O comentário da coluna `area` ficou para trás.
--
-- Ele ainda dizia "Frente de trabalho do colaborador para os paineis de TV:
-- mecanica, eletrica ou nulo quando nao se aplica", escrito na 20260912160000. A
-- 20260913100000 abriu a terceira área e trocou a restrição e a função, mas não
-- refez o comentário.
--
-- Não quebra nada: comentário não valida. Mas é o texto que aparece no Studio, no
-- `\d+` e na geração de tipos, ou seja, é o que alguém lê justamente quando está em
-- dúvida sobre o que pode gravar ali. E "frente de trabalho" passou a estar errado:
-- engenharia é escritório, não frente de fábrica.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

comment on column public.colaboradores.area is
  'Área do colaborador para os painéis de TV: mecanica e eletrica são as frentes de chão de fábrica, engenharia é a turma de escritório que trabalha em OS (coordenação, projeto, programação, segurança), e nulo quando a pessoa não entra em painel algum. A lista vale junto com chk_colaboradores_area e public.fn_tv_area: as três precisam concordar.';

do $assertions$
declare
  v_texto text;
begin
  select col_description('public.colaboradores'::regclass, a.attnum) into v_texto
  from pg_attribute as a
  where a.attrelid = 'public.colaboradores'::regclass and a.attname = 'area';

  if v_texto is null or v_texto not like '%engenharia%' then
    raise exception 'o comentario da coluna area continua sem a engenharia: %', coalesce(v_texto, '(vazio)');
  end if;
end;
$assertions$;

commit;
