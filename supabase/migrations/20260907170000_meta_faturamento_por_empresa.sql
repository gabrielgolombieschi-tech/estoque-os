-- Correcao da 20260907160000, depois da conferencia de escopo pedida por
-- Gabriel em 07/09/2026.
--
-- Dois problemas na primeira versao:
--
-- 1. A meta ficou gravada por TENANT, mas o painel mostra o faturamento de UMA
--    empresa (public.app_faturamento_painel usa current_empresa_id). O tenant
--    Segau tem duas empresas — ELETRICA SEGAU e SGU AUTOMACAO — e as duas
--    faturam: em 2026, R$ 6.437.331,16 e R$ 2.181.283,05. Comparar o
--    faturamento de uma so contra uma meta do grupo compara coisas diferentes.
--    A meta passa a ser por empresa, no mesmo recorte do que aparece na tela.
--
-- 2. O seed usou "cross join public.tenants where ativo" e por isso escreveu
--    meta tambem no tenant "Minha Empresa", que nao tem nada a ver com o
--    assunto. Essas linhas saem.
--
-- O valor de 2017 a 2026 fica so na ELETRICA SEGAU, que e onde a coordenacao
-- trabalha e o recorte que o analitico web ja usa por padrao. A SGU fica SEM
-- meta de proposito: o painel mostra "Sem meta cadastrada" em vez de comparar
-- com um numero que talvez nao seja dela. Quando Gabriel disser o valor da SGU
-- (ou confirmar que os R$ 698.429,75/mes de 2026 sao do grupo), basta inserir.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Meta passa a ser por empresa ---------------------------------------------

delete from f.meta_faturamento;

alter table f.meta_faturamento
  drop constraint meta_faturamento_pkey;

alter table f.meta_faturamento
  add column if not exists empresa_id uuid not null;

alter table f.meta_faturamento
  add constraint meta_faturamento_pkey primary key (tenant_id, empresa_id, ano);

comment on table f.meta_faturamento is
  'Meta MENSAL de faturamento por empresa e ano. A meta anual e valor_mensal * 12. Mesmo recorte do painel do app: uma empresa por vez.';

-- 2. Seed apenas da ELETRICA SEGAU --------------------------------------------

insert into f.meta_faturamento (tenant_id, empresa_id, ano, valor_mensal, observacao)
select
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid,
  v.ano,
  v.valor,
  'Copiado de FATURAMENTO_TARGETS_BY_YEAR (analitico web) em 07/09/2026.'
from (values
  (2017, 190000.00),
  (2018, 214700.00),
  (2019, 242611.00),
  (2020, 274150.43),
  (2021, 309789.99),
  (2022, 350062.68),
  (2023, 395570.83),
  (2024, 446995.04),
  (2025, 558743.80),
  (2026, 698429.75)
) as v(ano, valor)
on conflict (tenant_id, empresa_id, ano) do nothing;

-- 3. O painel le a meta da empresa em que a pessoa esta -----------------------

do $patch_painel$
declare
  v_definition text;
  v_needle text := $needle$  select meta.valor_mensal into v_meta
  from f.meta_faturamento as meta
  where meta.tenant_id = v_tenant_id
    and meta.ano = v_ano;$needle$;
  v_replacement text := $replacement$  select meta.valor_mensal into v_meta
  from f.meta_faturamento as meta
  where meta.tenant_id = v_tenant_id
    and meta.empresa_id = v_empresa_id
    and meta.ano = v_ano;$replacement$;
begin
  select pg_get_functiondef('public.app_faturamento_painel(integer,integer)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'painel_meta_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_painel$;

-- 4. Conferencia --------------------------------------------------------------

do $assertions$
declare
  v_meta numeric;
  v_linhas_fora integer;
  v_painel text := pg_get_functiondef('public.app_faturamento_painel(integer,integer)'::regprocedure);
begin
  select valor_mensal into v_meta
  from f.meta_faturamento
  where tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
    and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
    and ano = 2026;

  if v_meta is distinct from 698429.75 then
    raise exception 'meta_segau_2026_nao_conferida: %', coalesce(v_meta::text, '<nulo>');
  end if;

  select count(*) into v_linhas_fora
  from f.meta_faturamento
  where tenant_id <> '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
     or empresa_id <> 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;

  if v_linhas_fora > 0 then
    raise exception 'meta_gravada_fora_da_segau: % linhas', v_linhas_fora;
  end if;

  if position('meta.empresa_id = v_empresa_id' in v_painel) = 0 then
    raise exception 'painel_nao_filtra_meta_por_empresa';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
