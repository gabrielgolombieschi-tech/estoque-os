-- =====================================================================================
-- Terceira área do painel de TV: engenharia.
--
-- As duas primeiras são frentes de chão de fábrica. Esta é a turma do escritório
-- que trabalha em OS do mesmo jeito e aponta hora do mesmo jeito, mas não é nem
-- mecânica nem elétrica: coordenação, projeto, programação e segurança.
--
-- A tela é a mesma (`/painel-tv/colaboradores?area=engenharia`): os três layouts
-- já servem, porque essa turma aponta hora com regularidade — conferido em
-- produção antes de escrever isto, com trinta dias de lançamento para cada um dos
-- cinco.
--
-- DOUGLAS e MATHEUS saem da mecânica. Um é coordenador e o outro é projetista:
-- estavam na mecânica porque o cargo tem "MEC", e o preenchimento automático da
-- 20260912190000 olhava só isso. A partir daqui eles aparecem na TV de
-- engenharia e não na da mecânica, que é o que a frente de fábrica precisa ver.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. A coluna aceita a terceira área. ------------------------------------------------

alter table public.colaboradores drop constraint if exists chk_colaboradores_area;
alter table public.colaboradores add constraint chk_colaboradores_area
  check (area is null or area in ('mecanica', 'eletrica', 'engenharia'));

-- 2. A validação da TV também. --------------------------------------------------------

create or replace function public.fn_tv_area(p_area text)
returns text
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_area text := nullif(btrim(lower(coalesce(p_area, ''))), '');
begin
  if v_area is not null and v_area not in ('mecanica', 'eletrica', 'engenharia') then
    raise exception 'Área inválida: %. Use mecanica, eletrica, engenharia ou nenhuma.', p_area;
  end if;
  return v_area;
end;
$function$;

revoke all on function public.fn_tv_area(text) from public, anon, authenticated;

-- 3. Quem entra na engenharia. ---------------------------------------------------------
-- Por nome, porque o cargo não distingue: "COORDENADOR MECANICO" e "PROJETISTA
-- MEC" têm a mesma marca do soldador. Quem muda isso no dia a dia é o campo Área
-- no cadastro de colaboradores; este bloco só monta a turma inicial.

do $engenharia$
declare
  v_nome text;
  v_nomes text[] := array[
    'DOUGLAS WIEMENS',        -- coordenador
    'MATHEUS CAMILO',         -- projetista
    'ANALICE BATISTA MARTINS',-- técnica de segurança
    'CLARICE INES LORENZI',   -- engenheira de segurança
    'LUCAS EDUARDO MEBS'      -- programador
  ];
  v_achados integer;
begin
  foreach v_nome in array v_nomes loop
    update public.colaboradores
       set area = 'engenharia'
     where upper(btrim(nome)) = v_nome
       and ativo
       and coalesce(area, '') <> 'engenharia';
    get diagnostics v_achados = row_count;
    if v_achados = 0 then
      -- Nome que não existe naquela base (outro ambiente, ou já ajustado à mão)
      -- não derruba o deploy: a migration precisa rodar em qualquer cópia.
      raise notice 'engenharia: nao encontrei colaborador ativo "%" para vincular', v_nome;
    end if;
  end loop;
end;
$engenharia$;

do $assertions$
declare
  v_erro text;
begin
  -- A área nova é aceita e uma inventada continua recusada.
  if public.fn_tv_area('engenharia') <> 'engenharia' then
    raise exception 'fn_tv_area recusou engenharia';
  end if;
  if public.fn_tv_area(' ENGENHARIA ') <> 'engenharia' then
    raise exception 'fn_tv_area nao normalizou a area';
  end if;
  begin
    perform public.fn_tv_area('hidraulica');
    raise exception 'fn_tv_area aceitou uma area inventada';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    if v_erro not like 'Área inválida:%' then raise; end if;
  end;

  -- A restrição da coluna acompanha a função: as duas precisam concordar, senão
  -- existe área que a tela aceita e o cadastro recusa (ou o contrário).
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.colaboradores'::regclass
      and conname = 'chk_colaboradores_area'
      and pg_get_constraintdef(oid) like '%engenharia%'
  ) then
    raise exception 'chk_colaboradores_area nao aceita engenharia';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
