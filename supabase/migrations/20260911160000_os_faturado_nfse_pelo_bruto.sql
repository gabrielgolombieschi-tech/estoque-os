-- O faturado da OS conta a NFS-e pelo valor BRUTO do servico, nao pelo liquido.
--
-- Caso que expos (11/09/2026, OS 139 / pedido WEG Tintas 4518572701): a NFS-e A1
-- 202600000001843 foi de R$ 87.500,00 de servico, com R$ 5.687,50 de retencoes. O
-- `valor_total` da NFS-e guarda o liquido (81.812,50), e era ele que abatia do pedido: a
-- tela mostrava saldo de 93.187,50 quando o certo e 87.500,00.
--
-- A retencao (ISS, INSS, IR, CSRF) e imposto da Segau que o tomador recolhe por ela; e
-- parte do preco, nao desconto. O pedido do cliente e bruto, entao o que o consome e o
-- bruto da nota.
--
-- Efeito colateral do erro, alem do numero na tela: OS ja faturada por inteiro seguia com
-- um "saldo" igual a retencao — nao passava em `f.fn_os_pronta_para_faturada` e deixava
-- emitir a diferenca de novo. Em 11/09/2026 eram 19 OS nessa situacao; as 307, 308, 277 e
-- 241 tem bruto exatamente igual ao orcado.
--
-- Levantamento das 227 NFS-e de saida emitidas: todas tem `valor_servicos` preenchido e
-- nenhuma tem bruto menor que o liquido. A NF-e segue pelo vNF (`valor_total`), que ja
-- traz o IPI e e o que o cliente deve — regra da 20260909 (saldo com IPI).
--
-- A regra fica numa funcao so, usada pelo saldo e pelas duas listagens de OS do app. O
-- espelho no web e `lib/os/faturadoPorOs.ts`.

create or replace function f.fn_documento_valor_faturado(
  p_modelo text,
  p_valor_total numeric,
  p_valor_servicos numeric,
  p_valor_produtos numeric
)
returns numeric
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select round(greatest(
    case
      when upper(coalesce(p_modelo, '')) = 'NFSE' then coalesce(nullif(p_valor_servicos, 0), p_valor_total, 0)
      else coalesce(p_valor_total, p_valor_produtos, 0)
    end,
    0
  ), 2);
$$;

comment on function f.fn_documento_valor_faturado(text, numeric, numeric, numeric) is
  'Quanto um documento de saida consome do pedido da OS: NFS-e pelo valor bruto do servico (as retencoes sao imposto, nao desconto); NF-e pelo vNF, que ja traz o IPI.';

revoke all on function f.fn_documento_valor_faturado(text, numeric, numeric, numeric) from public;
grant execute on function f.fn_documento_valor_faturado(text, numeric, numeric, numeric) to authenticated, service_role;

CREATE OR REPLACE FUNCTION f.fn_os_saldo_a_faturar(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
 RETURNS TABLE(valor_pedido numeric, valor_faturado numeric, valor_reservado numeric, saldo numeric, usa_relatorio_hh boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_os public.ordens_servico%rowtype;
  v_valor_pedido numeric(14,2);
  v_valor_faturado numeric(14,2);
  v_valor_reservado numeric(14,2);
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS/OV sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar o faturamento desta empresa.';
  end if;

  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id and os.id = p_os_id and os.tipo_documento in ('OS', 'OV');
  if not found then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  if v_os.usa_relatorio_hh then
    select coalesce(hh.total_hh, 0) into v_valor_pedido
    from public.vw_hh_total_os hh
    where hh.tenant_id = p_tenant_id and hh.empresa_id = p_empresa_id and hh.os_id = p_os_id;
    v_valor_pedido := coalesce(v_valor_pedido, 0);
  else
    v_valor_pedido := coalesce(v_os.orcado, 0);
  end if;

  -- O que o documento consome do pedido: NF-e pelo vNF (traz o IPI e ja esta liquido de
  -- desconto — nao subtrair valor_desconto, seria descontar duas vezes); NFS-e pelo bruto
  -- do servico, porque as retencoes sao imposto e nao desconto.
  select coalesce(sum(f.fn_documento_valor_faturado(df.modelo, df.valor_total, df.valor_servicos, df.valor_produtos)), 0)
  into v_valor_faturado
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id and df.os_id_import = p_os_id
    and df.operacao = 'SAIDA' and df.deleted_at is null
    and (
      (upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
      or (upper(coalesce(df.modelo, '')) <> 'NFSE' and (nullif(btrim(df.nfe_status), '') is null or upper(df.nfe_status) = 'EMITIDA'))
    );

  -- Reserva do rascunho na mesma moeda do faturado: mercadoria + IPI previsto.
  -- Mesma regra do builder (supabase/functions/_shared/nfe-payload.ts): so ha IPI
  -- quando o CST e tributado e a aliquota esta preenchida.
  select coalesce(sum(
    (case when si.cst_ipi in ('00', '49', '50', '99') and si.aliquota_ipi is not null
       then round(round(greatest(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0), 0), 2) * si.aliquota_ipi / 100, 2)
       else 0 end)
    + round(greatest(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0), 0), 2)
  ), 0)
  into v_valor_reservado
  from f.solicitacao_faturamento sf
  join f.solicitacao_item si
    on si.tenant_id = sf.tenant_id and si.empresa_id = sf.empresa_id and si.solicitacao_id = sf.id
  where sf.tenant_id = p_tenant_id and sf.empresa_id = p_empresa_id
    and sf.status <> 'CANCELADA'
    and si.origem_tipo = v_os.tipo_documento
    and si.origem_id = p_os_id::text
    and not exists (
      select 1
      from f.documento_fiscal_emissao e
      join f.documento_fiscal d on d.tenant_id = e.tenant_id and d.empresa_id = e.empresa_id and d.id = e.documento_fiscal_id
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
        and d.deleted_at is null and upper(coalesce(d.nfe_status, d.nfse_status, '')) = 'EMITIDA'
    )
    and coalesce((
      select e.status
      from f.documento_fiscal_emissao e
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
      order by e.created_at desc, e.documento_fiscal_id desc
      limit 1
    ), 'RASCUNHO') not in ('REJEITADA', 'ERRO', 'CANCELADA');

  valor_pedido := round(v_valor_pedido, 2);
  valor_faturado := round(v_valor_faturado, 2);
  valor_reservado := round(v_valor_reservado, 2);
  saldo := round(v_valor_pedido - v_valor_faturado - v_valor_reservado, 2);
  usa_relatorio_hh := coalesce(v_os.usa_relatorio_hh, false);
  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.app_os_agrupado_cliente(p_status text[] DEFAULT ARRAY['em_andamento'::text], p_busca text DEFAULT NULL::text)
 RETURNS TABLE(cliente_id integer, cliente_nome text, quantidade_os integer, quantidade_sem_oc integer, responsaveis text[], quantidade_faturadas integer, total_horas numeric, valor_total numeric, valor_faturado numeric, valor_gasto numeric, pode_ver_valores boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'f', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_valores boolean;
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar ordens de servico no app.';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_status, '{}'::text[])) as filtro(status)
    where lower(filtro.status) not in ('em_andamento', 'concluida', 'faturada')
  ) then
    raise exception 'Filtro de status invalido.';
  end if;

  v_pode_ver_valores := public.app_mobile_pode_ver_valores_os(v_tenant_id, v_empresa_id);

  return query
  with os_filtradas as (
    select
      os.id,
      os.cliente_id,
      coalesce(nullif(btrim(cliente.nome), ''), nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text as cliente_nome,
      os.pedido_compra,
      coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) as status_fluxo,
      coalesce(horas.total_horas, 0)::numeric as total_horas,
      coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text as responsavel_nome,
      case
        when coalesce(os.usa_relatorio_hh, false) then coalesce(valor_hh.total_hh, 0)
        else coalesce(os.orcado, 0)
      end::numeric as valor_pedido,
      coalesce(documentos.valor_faturado, 0)::numeric as valor_faturado
    from public.ordens_servico as os
    left join public.clientes as cliente
      on cliente.id = os.cliente_id
     and cliente.tenant_id = v_tenant_id
     and cliente.empresa_id = v_empresa_id
    left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
    left join a.usuario as usuario
      on usuario.auth_user_id = os.responsavel_aprovacao_id
     and usuario.ativo is true
     and usuario.deleted_at is null
    left join public.colaboradores as colaborador
      on colaborador.user_id = os.responsavel_aprovacao_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
     and colaborador.ativo is true
    left join lateral (
      select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
      from public.apontamentos_horas as apontamento
      where apontamento.os_id = os.id
        and apontamento.tenant_id = v_tenant_id
        and apontamento.empresa_id = v_empresa_id
    ) as horas on true
    left join lateral (
      select coalesce(sum(resumo.total_hh), 0)::numeric as total_hh
      from public.vw_hh_total_os as resumo
      where resumo.os_id = os.id
        and resumo.tenant_id = v_tenant_id
        and resumo.empresa_id = v_empresa_id
    ) as valor_hh on true
    left join lateral (
      select coalesce(sum(f.fn_documento_valor_faturado(documento.modelo, documento.valor_total, documento.valor_servicos, documento.valor_produtos)), 0)::numeric as valor_faturado
      from f.documento_fiscal as documento
      where documento.tenant_id = v_tenant_id
        and documento.empresa_id = v_empresa_id
        and documento.os_id_import = os.id
        and documento.operacao = 'SAIDA'
        and documento.deleted_at is null
        and (
          (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
          or (
            upper(coalesce(documento.modelo, '')) <> 'NFSE'
            and (nullif(btrim(documento.nfe_status), '') is null or upper(documento.nfe_status) = 'EMITIDA')
          )
        )
    ) as documentos on true
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and coalesce(os.tipo_documento, 'OS') = 'OS'
      and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, p_status)
      and (
        v_busca is null
        or os.numero_os ilike '%' || v_busca || '%'
        or os.os_num::text ilike '%' || v_busca || '%'
        or os.cliente_nome ilike '%' || v_busca || '%'
        or cliente.nome ilike '%' || v_busca || '%'
        or os.descricao_servico ilike '%' || v_busca || '%'
      )
  ),
  ids_filtrados as (
    select coalesce(array_agg(os_filtrada.id), '{}'::integer[]) as lista
    from os_filtradas as os_filtrada
  ),
  custos as (
    select custo.os_id, custo.custo_total
    from ids_filtrados,
         public.fn_os_custo_operacional_unscoped(v_tenant_id, v_empresa_id, ids_filtrados.lista) as custo
  )
  select
    filtrada.cliente_id,
    filtrada.cliente_nome,
    count(*)::integer as quantidade_os,
    count(*) filter (where nullif(btrim(filtrada.pedido_compra), '') is null)::integer as quantidade_sem_oc,
    coalesce(
      array_agg(distinct filtrada.responsavel_nome order by filtrada.responsavel_nome)
        filter (where filtrada.responsavel_nome is not null),
      '{}'::text[]
    ) as responsaveis,
    count(*) filter (where filtrada.status_fluxo = 'faturada')::integer as quantidade_faturadas,
    sum(filtrada.total_horas)::numeric as total_horas,
    case when v_pode_ver_valores then sum(filtrada.valor_pedido)::numeric else null::numeric end as valor_total,
    case when v_pode_ver_valores then sum(filtrada.valor_faturado)::numeric else null::numeric end as valor_faturado,
    case when v_pode_ver_valores then sum(coalesce(custo.custo_total, 0))::numeric else null::numeric end as valor_gasto,
    v_pode_ver_valores as pode_ver_valores
  from os_filtradas as filtrada
  left join custos as custo on custo.os_id = filtrada.id
  group by filtrada.cliente_id, filtrada.cliente_nome
  order by lower(filtrada.cliente_nome), filtrada.cliente_id nulls last;
end;
$function$;

CREATE OR REPLACE FUNCTION public.app_os_do_cliente(p_cliente_id integer, p_status text[] DEFAULT ARRAY['em_andamento'::text])
 RETURNS TABLE(id integer, numero_os character varying, os_num bigint, cliente_id integer, cliente_nome text, descricao_servico text, status_legado character varying, status_fluxo text, usa_relatorio_hh boolean, total_horas numeric, responsavel_nome text, situacao_margem text, pedido_compra text, pendencias_aprovacao integer, garantia_motivo text, faturado_em timestamp with time zone, faturada_presumida_legado boolean, pode_concluir boolean, pode_faturar boolean, pode_reabrir_garantia boolean, pode_concluir_garantia boolean, valor_total numeric, valor_faturado numeric, valor_gasto numeric, pode_ver_valores boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'f', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_valores boolean;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar ordens de servico no app.';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_status, '{}'::text[])) as filtro(status)
    where lower(filtro.status) not in ('em_andamento', 'concluida', 'faturada')
  ) then
    raise exception 'Filtro de status invalido.';
  end if;

  v_pode_ver_valores := public.app_mobile_pode_ver_valores_os(v_tenant_id, v_empresa_id);

  return query
  select
    os.id,
    os.numero_os,
    os.os_num,
    os.cliente_id,
    coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cliente.nome), ''), 'Cliente nao informado')::text,
    os.descricao_servico,
    os.status,
    coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status))::text,
    coalesce(os.usa_relatorio_hh, false),
    coalesce(horas.total_horas, 0)::numeric,
    coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text,
    null::text,
    os.pedido_compra::text,
    coalesce(pendencias.quantidade, 0)::integer,
    os.garantia_motivo,
    os.faturado_em,
    os.faturada_presumida_legado,
    v_papel in ('ADMIN', 'DIRETOR', 'COORDENACAO'),
    v_papel = 'FINANCEIRO' and documentos.valor_faturado > 0,
    v_papel in ('COORDENACAO', 'FINANCEIRO')
      and os.status_fluxo = 'faturada'
      and not coalesce(os.faturada_presumida_legado, false)
      and os.faturado_em is not null
      and os.faturado_em >= now() - interval '6 months',
    v_papel = 'COORDENACAO',
    case
      when v_pode_ver_valores then
        case when coalesce(os.usa_relatorio_hh, false) then coalesce(valor_hh.total_hh, 0) else coalesce(os.orcado, 0) end
      else null::numeric
    end::numeric,
    case when v_pode_ver_valores then documentos.valor_faturado else null::numeric end::numeric,
    case when v_pode_ver_valores then coalesce(custo.custo_total, 0) else null::numeric end::numeric,
    v_pode_ver_valores
  from public.ordens_servico as os
  left join public.clientes as cliente
    on cliente.id = os.cliente_id
   and cliente.tenant_id = v_tenant_id
   and cliente.empresa_id = v_empresa_id
  left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
  left join a.usuario as usuario
    on usuario.auth_user_id = os.responsavel_aprovacao_id
   and usuario.ativo is true
   and usuario.deleted_at is null
  left join public.colaboradores as colaborador
    on colaborador.user_id = os.responsavel_aprovacao_id
   and colaborador.tenant_id = v_tenant_id
   and colaborador.empresa_id = v_empresa_id
   and colaborador.ativo is true
  left join lateral (
    select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
    from public.apontamentos_horas as apontamento
    where apontamento.os_id = os.id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
  ) as horas on true
  left join lateral (
    select count(*)::integer as quantidade
    from public.apontamentos_horas as apontamento
    where apontamento.os_id = os.id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.status_aprovacao = 'pendente'
  ) as pendencias on true
  left join lateral (
    select coalesce(sum(resumo.total_hh), 0)::numeric as total_hh
    from public.vw_hh_total_os as resumo
    where resumo.os_id = os.id
      and resumo.tenant_id = v_tenant_id
      and resumo.empresa_id = v_empresa_id
  ) as valor_hh on true
  left join lateral (
    select coalesce(sum(f.fn_documento_valor_faturado(documento.modelo, documento.valor_total, documento.valor_servicos, documento.valor_produtos)), 0)::numeric as valor_faturado
    from f.documento_fiscal as documento
    where documento.tenant_id = v_tenant_id
      and documento.empresa_id = v_empresa_id
      and documento.os_id_import = os.id
      and documento.operacao = 'SAIDA'
      and documento.deleted_at is null
      and (
        (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
        or (
          upper(coalesce(documento.modelo, '')) <> 'NFSE'
          and (nullif(btrim(documento.nfe_status), '') is null or upper(documento.nfe_status) = 'EMITIDA')
        )
      )
  ) as documentos on true
  left join lateral (
    select item.custo_total
    from public.fn_os_custo_operacional_unscoped(v_tenant_id, v_empresa_id, array[os.id]) as item
    limit 1
  ) as custo on true
  where os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and coalesce(os.tipo_documento, 'OS') = 'OS'
    and (os.cliente_id = p_cliente_id or (os.cliente_id is null and p_cliente_id is null))
    and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, p_status)
  order by os.data_abertura desc nulls last, os.id desc;
end;
$function$;
