begin;

create or replace function public.get_os_detail_operacional(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_papel text := a.fn_current_empresa_papel(p_tenant_id, p_empresa_id);
  v_os public.ordens_servico%rowtype;
  v_result jsonb;
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or p_os_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or coalesce(v_papel, '') not in (
       'ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO',
       'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH'
     ) then
    raise exception 'os_detail_access_denied';
  end if;

  select os.*
    into v_os
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id;

  if not found then
    raise exception 'os_not_found';
  end if;

  select jsonb_build_object(
    'os', jsonb_build_object(
      'id', v_os.id,
      'numero_os', v_os.numero_os,
      'cliente_nome', v_os.cliente_nome,
      'cliente_id', v_os.cliente_id,
      'status', v_os.status,
      'descricao_servico', v_os.descricao_servico,
      'valor_total', v_os.valor_total,
      'data_abertura', v_os.data_abertura,
      'orcado', v_os.orcado,
      'tipo_pedido', v_os.tipo_pedido,
      'tem_gestao', v_os.tem_gestao,
      'pedido_compra', v_os.pedido_compra,
      'vendedor', v_os.vendedor,
      'usa_relatorio_hh', v_os.usa_relatorio_hh,
      'is_fiado', coalesce(v_os.is_fiado, false),
      'orcamento_gerado_id', v_os.orcamento_gerado_id
    ),
    'cliente_habilita_hh', coalesce((
      select c.habilita_hh
      from public.clientes c
      where c.id = v_os.cliente_id
        and c.tenant_id = p_tenant_id
        and c.empresa_id = p_empresa_id
    ), false) or coalesce(v_os.usa_relatorio_hh, false),
    'itens', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', oi.id,
          'item_id', oi.item_id,
          'quantidade', oi.quantidade,
          'valor_unitario', oi.valor_unitario,
          'valor_total', oi.valor_total,
          'desconto_percentual', oi.desconto_percentual,
          'desconto_valor', oi.desconto_valor,
          'baixa_estoque', oi.baixa_estoque,
          'quantidade_baixada', oi.quantidade_baixada,
          'criado_em', oi.criado_em,
          'registrado_em', oi.registrado_em,
          'registrado_por_nome', oi.registrado_por_nome,
          'itens', case when i.id is null then null else jsonb_build_object(
            'nome', i.nome,
            'codigo_interno', i.codigo_interno,
            'tipo', i.tipo
          ) end
        ) order by oi.id desc
      )
      from public.os_itens oi
      left join public.itens i
        on i.id = oi.item_id
       and i.tenant_id = oi.tenant_id
       and i.empresa_id = oi.empresa_id
      where oi.os_id = p_os_id
        and oi.tenant_id = p_tenant_id
        and oi.empresa_id = p_empresa_id
    ), '[]'::jsonb),
    'custo_mao_obra', coalesce((
      select v.custo_mao_obra
      from public.vw_custo_mao_obra_os v
      where v.os_id = p_os_id
      limit 1
    ), 0),
    'total_hh', coalesce((
      select v.total_hh
      from public.vw_hh_total_os v
      where v.os_id = p_os_id
      limit 1
    ), 0),
    'hh_lancamentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'entrada_1', h.entrada_1,
        'saida_1', h.saida_1,
        'entrada_2', h.entrada_2,
        'saida_2', h.saida_2,
        'hora_entrada', h.hora_entrada,
        'hora_saida', h.hora_saida,
        'horas_trabalhadas', h.horas_trabalhadas,
        'percentual_aplicado', h.percentual_aplicado,
        'tem_extra_50', h.tem_extra_50,
        'horas_extra_50', h.horas_extra_50,
        'tem_extra_100', h.tem_extra_100,
        'horas_extra_100', h.horas_extra_100,
        'valor_hora', h.valor_hora,
        'valor_total', h.valor_total
      ))
      from public.hh_lancamentos h
      where h.os_id = p_os_id
        and h.tenant_id = p_tenant_id
        and h.empresa_id = p_empresa_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_os_detail_operacional(uuid, uuid, integer) from public, anon;
grant execute on function public.get_os_detail_operacional(uuid, uuid, integer) to authenticated, service_role;

comment on function public.get_os_detail_operacional(uuid, uuid, integer) is
  'Carrega o detalhe operacional de uma OS em uma unica consulta escopada e autorizada. Inclui is_fiado/orcamento_gerado_id (OS Fiado) desde 20260823175000.';

notify pgrst, 'reload schema';

commit;
