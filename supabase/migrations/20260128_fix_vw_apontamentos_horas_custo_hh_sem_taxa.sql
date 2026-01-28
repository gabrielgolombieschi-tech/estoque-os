begin;

-- Fix: vw_custo_mao_obra_os estava retornando 0h / R$ 0,00 quando os apontamentos
-- eram gerados via HH (gerado_por_hh=true) e o colaborador não possuía taxa vigente
-- na data (colaborador_taxas). O view vw_apontamentos_horas_custo fazia JOIN LATERAL
-- (inner) em colaborador_taxas, removendo as linhas.
--
-- Ajuste:
-- - LEFT JOIN LATERAL em colaborador_taxas (não elimina apontamentos)
-- - Fallback de taxa: tenta taxa vigente; senão, usa a mais recente anterior; senão, a próxima futura
-- - Se não houver nenhuma taxa cadastrada, valor_hora/custo ficam 0, mas as horas aparecem.

create or replace view public.vw_apontamentos_horas_custo as
select
  a.id as apontamento_id,
  a.os_id,
  a.colaborador_id,
  c.nome as colaborador_nome,
  a.data,
  a.horas,
  th.codigo as tipo_hora_codigo,
  th.descricao as tipo_hora_descricao,
  coalesce(a.fator_aplicado, th.fator, (1)::numeric) as fator,
  coalesce(tx.valor_hora, (0)::numeric(10,2)) as valor_hora,
  round(((a.horas * coalesce(tx.valor_hora, (0)::numeric(10,2))) * coalesce(a.fator_aplicado, th.fator, (1)::numeric)), 2) as custo_lancamento,
  a.descricao,
  a.status,
  a.criado_em
from public.apontamentos_horas a
join public.colaboradores c
  on c.id = a.colaborador_id
left join public.tipos_horas th
  on th.id = a.tipo_hora_id
left join lateral (
  select t.valor_hora
  from public.colaborador_taxas t
  where t.colaborador_id = a.colaborador_id
    and t.tenant_id = a.tenant_id
    and t.empresa_id = a.empresa_id
  order by
    case
      when a.data >= t.vigencia_inicio and (t.vigencia_fim is null or a.data <= t.vigencia_fim) then 0 -- vigente
      when t.vigencia_inicio <= a.data then 1 -- taxa anterior
      else 2 -- taxa futura
    end,
    -- para taxas anteriores/vigentes: pega a mais recente
    case when t.vigencia_inicio <= a.data then t.vigencia_inicio end desc nulls last,
    -- para taxas futuras: pega a mais próxima
    case when t.vigencia_inicio > a.data then t.vigencia_inicio end asc nulls last,
    t.criado_em desc
  limit 1
) tx on true;

commit;
