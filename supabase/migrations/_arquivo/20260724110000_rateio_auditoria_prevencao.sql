-- Etapa 2 da saude financeira:
-- 1) disponibiliza uma auditoria segura dos rateios inconsistentes;
-- 2) elimina a causa de duplicidade criada pelo rateio automatico executado
--    antes de rotinas que gravam a classificacao definitiva.
--
-- Esta migration nao altera rateios existentes.

create or replace function f.preview_inconsistencias_rateio(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns table (
  titulo_id uuid,
  tipo text,
  status text,
  origem text,
  descricao text,
  competencia_date date,
  emissao_date date,
  valor_titulo numeric,
  quantidade_rateios bigint,
  percentual_total numeric,
  valor_rateado numeric,
  excesso_valor numeric,
  duplicidades_dimensao bigint,
  duplicidades_exatas bigint,
  motivo_plano_id uuid,
  rateios jsonb
)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception 'Tenant e empresa sao obrigatorios.';
  end if;

  if auth.uid() is not null then
    if p_tenant_id is distinct from public.current_tenant_id()
       or p_empresa_id is distinct from public.current_empresa_id()
       or not f.has_finance_access(p_tenant_id, p_empresa_id)
    then
      raise exception 'Sem permissao para auditar rateios deste escopo.';
    end if;
  elsif coalesce(auth.role(), '') <> 'service_role'
        and session_user not in ('postgres', 'service_role')
  then
    raise exception 'Usuario nao autenticado.';
  end if;

  return query
  with titulos as (
    select
      t.id,
      t.tipo,
      t.status,
      t.origem,
      t.descricao,
      t.competencia_date,
      t.emissao_date,
      t.valor_total,
      mc.plano_contas_id as motivo_plano_id
    from f.titulo t
    left join f.motivo_compra mc
      on mc.tenant_id = p_tenant_id
     and mc.id = t.motivo_compra_id
     and mc.deleted_at is null
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.deleted_at is null
  ),
  rateios_detalhe as (
    select
      t.id as titulo_id,
      tr.id as rateio_id,
      tr.plano_contas_id,
      tr.centro_custo_id,
      tr.os_id,
      tr.percentual,
      tr.valor,
      tr.created_at,
      tr.updated_at,
      tr.created_by,
      pc.codigo as plano_codigo,
      pc.nome as plano_nome,
      cc.codigo as centro_codigo,
      cc.nome as centro_nome
    from titulos t
    join f.titulo_rateio tr
      on tr.tenant_id = p_tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    left join f.plano_contas pc
      on pc.tenant_id = p_tenant_id
     and pc.id = tr.plano_contas_id
     and pc.deleted_at is null
    left join f.centro_custo cc
      on cc.tenant_id = p_tenant_id
     and cc.empresa_id = p_empresa_id
     and cc.id = tr.centro_custo_id
     and cc.deleted_at is null
  ),
  estatisticas as (
    select
      t.id as titulo_id,
      count(rd.rateio_id) as quantidade_rateios,
      coalesce(sum(rd.percentual), 0)::numeric as percentual_total,
      coalesce(sum(coalesce(
        rd.valor,
        round(t.valor_total * coalesce(rd.percentual, 0) / 100.0, 2),
        0
      )), 0)::numeric as valor_rateado,
      (
        count(rd.rateio_id)
        - count(distinct row(
            rd.plano_contas_id,
            rd.centro_custo_id,
            rd.os_id
          ))
      )::bigint as duplicidades_dimensao,
      (
        count(rd.rateio_id)
        - count(distinct row(
            rd.plano_contas_id,
            rd.centro_custo_id,
            rd.os_id,
            rd.percentual,
            rd.valor
          ))
      )::bigint as duplicidades_exatas,
      jsonb_agg(
        jsonb_build_object(
          'id', rd.rateio_id,
          'planoId', rd.plano_contas_id,
          'planoCodigo', rd.plano_codigo,
          'planoNome', rd.plano_nome,
          'centroId', rd.centro_custo_id,
          'centroCodigo', rd.centro_codigo,
          'centroNome', rd.centro_nome,
          'osId', rd.os_id,
          'percentual', rd.percentual,
          'valor', rd.valor,
          'createdAt', rd.created_at,
          'updatedAt', rd.updated_at,
          'createdBy', rd.created_by
        )
        order by rd.created_at, rd.rateio_id
      ) filter (where rd.rateio_id is not null) as rateios
    from titulos t
    left join rateios_detalhe rd on rd.titulo_id = t.id
    group by t.id, t.valor_total
  )
  select
    t.id,
    t.tipo,
    t.status,
    t.origem,
    t.descricao,
    t.competencia_date,
    t.emissao_date,
    t.valor_total,
    e.quantidade_rateios,
    round(e.percentual_total, 4),
    round(e.valor_rateado, 2),
    round(e.valor_rateado - t.valor_total, 2),
    e.duplicidades_dimensao,
    e.duplicidades_exatas,
    t.motivo_plano_id,
    coalesce(e.rateios, '[]'::jsonb)
  from titulos t
  join estatisticas e on e.titulo_id = t.id
  where e.quantidade_rateios > 0
    and (
      e.percentual_total > 100.0001
      or e.valor_rateado > t.valor_total + 0.01
      or e.duplicidades_dimensao > 0
      or e.duplicidades_exatas > 0
    )
  order by
    greatest(e.valor_rateado - t.valor_total, 0) desc,
    t.id;
end;
$$;

comment on function f.preview_inconsistencias_rateio(uuid, uuid) is
  'Auditoria somente leitura de rateios duplicados ou superiores ao titulo, sempre limitada a tenant e empresa.';

revoke all on function f.preview_inconsistencias_rateio(uuid, uuid) from public;
grant execute on function f.preview_inconsistencias_rateio(uuid, uuid)
  to authenticated, service_role;

-- O trigger anterior era AFTER INSERT imediato. Rotinas que criavam um titulo
-- e, em seguida, o rateio definitivo recebiam antes um rateio automatico de
-- 100%, produzindo 200%. No modo diferido, o fallback somente e criado no fim
-- da transacao e apenas quando nenhuma classificacao explicita foi gravada.
drop trigger if exists tg_titulo_ap_auto_rateio_por_motivo on f.titulo;

create constraint trigger tg_titulo_ap_auto_rateio_por_motivo
after insert on f.titulo
deferrable initially deferred
for each row
execute function f.trg_titulo_ap_auto_rateio_por_motivo();

comment on trigger tg_titulo_ap_auto_rateio_por_motivo on f.titulo is
  'Cria rateio AP padrao somente no fim da transacao e apenas se nao existir rateio explicito.';
