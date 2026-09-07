-- SMOKE TEST — termina em rollback, nao altera nada.
-- Confere que app_faturamento_painel enxerga SO a empresa em que a pessoa
-- esta (ELETRICA SEGAU), e nao o tenant inteiro.

begin;

set local role postgres;
select set_config(
  'request.jwt.claims',
  '{"sub":"8eaaa27a-774e-4dcc-b2bb-416cb28bd2aa","role":"authenticated"}',
  true
);
set local role authenticated;

select
  public.current_tenant_id() as tenant_do_contexto,
  public.current_empresa_id() as empresa_do_contexto,
  (select razao_social from c.empresa where id = public.current_empresa_id()) as empresa;

-- 1. O que o painel devolve.
select
  (public.app_faturamento_painel(2026, 8) ->> 'total_ano')::numeric as painel_2026,
  (public.app_faturamento_painel(2026, 8) ->> 'total_mes')::numeric as painel_agosto,
  (public.app_faturamento_painel(2026, 8) ->> 'meta_mensal')::numeric as meta_mensal;

reset role;
set local role postgres;

-- 2. O mesmo periodo somado direto na tabela, separando as duas empresas do
--    tenant. painel_2026 tem que bater com ELETRICA SEGAU e ignorar a SGU.
select
  e.razao_social,
  round(sum(d.valor_total), 2) as total_bruto_2026
from f.documento_fiscal d
join c.empresa e on e.id = d.empresa_id
where d.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and d.operacao = 'SAIDA'
  and d.deleted_at is null
  and coalesce(d.competencia_date, d.emissao_date) >= '2026-01-01'
  and coalesce(d.competencia_date, d.emissao_date) < '2027-01-01'
group by 1
order by 1;

-- 3. Metas gravadas: so pode existir linha da ELETRICA SEGAU.
select
  coalesce(e.razao_social, '(empresa desconhecida)') as empresa,
  count(*) as anos_com_meta,
  min(m.ano) as de,
  max(m.ano) as ate
from f.meta_faturamento m
left join c.empresa e on e.id = m.empresa_id
group by 1;

rollback;
