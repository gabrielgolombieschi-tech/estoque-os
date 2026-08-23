begin;

create or replace function public.fn_gerar_ou_atualizar_orcamento_de_os(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer,
  p_orcamento_id uuid,
  p_margem_materiais_percent numeric default 0,
  p_margem_mao_obra_percent numeric default 0,
  p_item_servico_hh_id integer default null
)
returns table (
  itens_materiais_criados integer,
  grupos_mao_obra_criados integer,
  hh_valor_adicionado numeric,
  cargos_sem_mapeamento text[]
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_papel text := a.fn_current_empresa_papel(p_tenant_id, p_empresa_id);
  v_os public.ordens_servico%rowtype;
  v_orc m.orcamento%rowtype;
  v_margem_mat numeric := greatest(0, coalesce(p_margem_materiais_percent, 0));
  v_margem_mo numeric := greatest(0, coalesce(p_margem_mao_obra_percent, 0));
  v_item record;
  v_new_item_id uuid;
  v_itens_mat integer := 0;
  v_grupos_mo integer := 0;
  v_hh_delta numeric := 0;
  v_hh_item_id uuid;
  v_cargos_sem_mapeamento text[] := '{}';
  v_cargo record;
  v_realizado_por text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or p_os_id is null
     or p_orcamento_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or coalesce(v_papel, '') not in (
       'ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO'
     ) then
    raise exception 'os_orcamento_gerar_access_denied';
  end if;

  select os.* into v_os
  from public.ordens_servico os
  where os.id = p_os_id and os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id;

  if not found then
    raise exception 'OS invalida ou fora do tenant/empresa atual (os_id=%)', p_os_id;
  end if;

  if not coalesce(v_os.is_fiado, false) then
    raise exception 'Esta OS nao e uma OS Fiado. Geracao de orcamento so e permitida para OS Fiado.';
  end if;

  select o.* into v_orc
  from m.orcamento o
  where o.id = p_orcamento_id
    and o.tenant_id = p_tenant_id
    and o.empresa_id = p_empresa_id
    and o.deleted_at is null;

  if not found then
    raise exception 'Orcamento invalido ou fora do tenant/empresa atual (orcamento_id=%)', p_orcamento_id;
  end if;

  if v_orc.status <> 'ANDAMENTO' then
    raise exception 'Orcamento vinculado nao esta mais em andamento (status=%). Reabra o orcamento antes de sincronizar.', v_orc.status;
  end if;

  -- 1) Materiais/despesas: os_itens ainda nao exportados para nenhum orcamento.
  for v_item in
    select oi.id, oi.item_id, oi.quantidade, oi.valor_unitario
    from public.os_itens oi
    where oi.os_id = p_os_id
      and oi.tenant_id = p_tenant_id
      and oi.empresa_id = p_empresa_id
      and not exists (
        select 1 from public.os_orcamento_export_linha e
        where e.tenant_id = p_tenant_id and e.origem = 'os_item' and e.origem_id = oi.id::text
      )
  loop
    insert into m.orcamento_item (
      tenant_id, empresa_id, orcamento_id, item_id, quantidade, valor_unitario, desconto_item_percent, observacoes
    ) values (
      p_tenant_id, p_empresa_id, p_orcamento_id, v_item.item_id, v_item.quantidade,
      round(v_item.valor_unitario * (1 + v_margem_mat / 100), 2), 0,
      'Gerado automaticamente da OS ' || v_os.numero_os
    )
    returning id into v_new_item_id;

    insert into public.os_orcamento_export_linha (
      tenant_id, empresa_id, os_id, origem, origem_id, orcamento_id, orcamento_item_id, criado_por
    ) values (
      p_tenant_id, p_empresa_id, p_os_id, 'os_item', v_item.id::text, p_orcamento_id, v_new_item_id, v_realizado_por
    );

    v_itens_mat := v_itens_mat + 1;
  end loop;

  -- 2) Mao de obra por apontamento (clientes sem HH): apontamentos aprovados/fechados,
  --    ainda nao exportados, agrupados por cargo do colaborador.
  for v_cargo in
    select
      c.cargo as cargo_nome,
      cg.item_servico_id,
      sum(vc.horas) as total_horas,
      sum(vc.custo_lancamento) as total_custo,
      array_agg(ah.id::text) as apontamento_ids
    from public.apontamentos_horas ah
    join public.colaboradores c on c.id = ah.colaborador_id
    join public.vw_apontamentos_horas_custo vc on vc.apontamento_id = ah.id
    left join public.cargos cg
      on cg.tenant_id = p_tenant_id
     and upper(trim(cg.nome)) = upper(trim(coalesce(c.cargo, '')))
    where ah.os_id = p_os_id
      and ah.tenant_id = p_tenant_id
      and ah.empresa_id = p_empresa_id
      and ah.status in ('aprovado', 'fechado')
      and not exists (
        select 1 from public.os_orcamento_export_linha e
        where e.tenant_id = p_tenant_id and e.origem = 'apontamento' and e.origem_id = ah.id::text
      )
    group by c.cargo, cg.item_servico_id
  loop
    if v_cargo.total_horas is null or v_cargo.total_horas <= 0 then
      continue;
    end if;

    if v_cargo.item_servico_id is null
       or not exists (
         select 1 from public.itens i
         where i.id = v_cargo.item_servico_id
           and i.tenant_id = p_tenant_id
           and i.empresa_id = p_empresa_id
           and i.ativo = true
       )
    then
      v_cargos_sem_mapeamento := array_append(v_cargos_sem_mapeamento, coalesce(v_cargo.cargo_nome, '(sem cargo)'));
      continue; -- fica pendente para uma proxima geracao, depois de mapear o cargo
    end if;

    insert into m.orcamento_item (
      tenant_id, empresa_id, orcamento_id, item_id, quantidade, valor_unitario, desconto_item_percent, observacoes
    ) values (
      p_tenant_id, p_empresa_id, p_orcamento_id, v_cargo.item_servico_id, v_cargo.total_horas,
      round((coalesce(v_cargo.total_custo, 0) / v_cargo.total_horas) * (1 + v_margem_mo / 100), 2), 0,
      'Gerado automaticamente da OS ' || v_os.numero_os || ' (cargo: ' || coalesce(v_cargo.cargo_nome, '(sem cargo)') || ')'
    )
    returning id into v_new_item_id;

    insert into public.os_orcamento_export_linha (
      tenant_id, empresa_id, os_id, origem, origem_id, orcamento_id, orcamento_item_id, criado_por
    )
    select p_tenant_id, p_empresa_id, p_os_id, 'apontamento', apontamento_id, p_orcamento_id, v_new_item_id, v_realizado_por
    from unnest(v_cargo.apontamento_ids) as apontamento_id;

    v_grupos_mo := v_grupos_mo + 1;
  end loop;

  -- 3) HH: valor ja e preco de venda (tabela por cliente) - passa direto, sem markup.
  --    hh_lancamentos.valor_total nao e confiavel (a tela de lancamento nunca grava esse campo),
  --    entao o valor e recalculado a partir de horas_trabalhadas/valor_hora/percentuais de extra,
  --    espelhando lib/hh/hhLancamentosCalc.ts#getValorTotalEfetivo.
  select coalesce(sum(
    greatest(0, h.horas_trabalhadas
      - case
          when coalesce(h.tem_extra_50, false) or coalesce(h.horas_extra_50, 0) > 0 then coalesce(h.horas_extra_50, 0)
          when h.percentual_aplicado = 50 then h.horas_trabalhadas
          else 0
        end
      - case
          when coalesce(h.tem_extra_100, false) or coalesce(h.horas_extra_100, 0) > 0 then coalesce(h.horas_extra_100, 0)
          when h.percentual_aplicado = 100 then h.horas_trabalhadas
          else 0
        end
    ) * h.valor_hora
    +
    case
      when coalesce(h.tem_extra_50, false) or coalesce(h.horas_extra_50, 0) > 0 then coalesce(h.horas_extra_50, 0)
      when h.percentual_aplicado = 50 then h.horas_trabalhadas
      else 0
    end * h.valor_hora * 1.5
    +
    case
      when coalesce(h.tem_extra_100, false) or coalesce(h.horas_extra_100, 0) > 0 then coalesce(h.horas_extra_100, 0)
      when h.percentual_aplicado = 100 then h.horas_trabalhadas
      else 0
    end * h.valor_hora * 2
  ), 0)
  into v_hh_delta
  from public.hh_lancamentos h
  where h.os_id = p_os_id
    and h.tenant_id = p_tenant_id
    and h.empresa_id = p_empresa_id
    and not exists (
      select 1 from public.os_orcamento_export_linha e
      where e.tenant_id = p_tenant_id and e.origem = 'hh_lancamento' and e.origem_id = h.id::text
    );

  v_hh_delta := round(coalesce(v_hh_delta, 0), 2);

  if v_hh_delta > 0 then
    select e.orcamento_item_id into v_hh_item_id
    from public.os_orcamento_export_linha e
    where e.tenant_id = p_tenant_id and e.os_id = p_os_id and e.origem = 'hh_lancamento'
    limit 1;

    if v_hh_item_id is not null then
      update m.orcamento_item
         set valor_unitario = valor_unitario + v_hh_delta
       where id = v_hh_item_id and tenant_id = p_tenant_id and empresa_id = p_empresa_id;
    else
      if p_item_servico_hh_id is null then
        raise exception 'Ha valor de HH ainda nao exportado (R$ %). Informe o servico para faturar HH.', v_hh_delta;
      end if;

      insert into m.orcamento_item (
        tenant_id, empresa_id, orcamento_id, item_id, quantidade, valor_unitario, desconto_item_percent, observacoes
      ) values (
        p_tenant_id, p_empresa_id, p_orcamento_id, p_item_servico_hh_id, 1, v_hh_delta, 0,
        'Gerado automaticamente da OS ' || v_os.numero_os || ' (total HH)'
      )
      returning id into v_hh_item_id;
    end if;

    insert into public.os_orcamento_export_linha (
      tenant_id, empresa_id, os_id, origem, origem_id, orcamento_id, orcamento_item_id, criado_por
    )
    select p_tenant_id, p_empresa_id, p_os_id, 'hh_lancamento', h.id::text, p_orcamento_id, v_hh_item_id, v_realizado_por
    from public.hh_lancamentos h
    where h.os_id = p_os_id
      and h.tenant_id = p_tenant_id
      and h.empresa_id = p_empresa_id
      and not exists (
        select 1 from public.os_orcamento_export_linha e
        where e.tenant_id = p_tenant_id and e.origem = 'hh_lancamento' and e.origem_id = h.id::text
      );
  end if;

  update public.ordens_servico
     set orcamento_gerado_id = coalesce(orcamento_gerado_id, p_orcamento_id),
         atualizado_em = now()
   where id = p_os_id and tenant_id = p_tenant_id and empresa_id = p_empresa_id;

  -- Nao recalcula totais do cabecalho de m.orcamento: o fluxo manual existente
  -- (lib/comercial/orcamentos.service.ts#addItem) tambem nunca o faz apos inserir
  -- em m.orcamento_item, entao este RPC fica consistente com o comportamento atual.

  itens_materiais_criados := v_itens_mat;
  grupos_mao_obra_criados := v_grupos_mo;
  hh_valor_adicionado := v_hh_delta;
  cargos_sem_mapeamento := v_cargos_sem_mapeamento;
  return next;
end;
$$;

revoke all on function public.fn_gerar_ou_atualizar_orcamento_de_os(uuid, uuid, integer, uuid, numeric, numeric, integer) from public, anon;
grant execute on function public.fn_gerar_ou_atualizar_orcamento_de_os(uuid, uuid, integer, uuid, numeric, numeric, integer) to authenticated, service_role;

comment on function public.fn_gerar_ou_atualizar_orcamento_de_os(uuid, uuid, integer, uuid, numeric, numeric, integer) is
  'Gera (1a chamada) ou atualiza (chamadas seguintes) um orcamento a partir de uma OS Fiado: materiais/despesas e mao de obra por apontamento recebem markup sobre custo (margens separadas), HH entra pelo valor cheio sem markup. So considera linhas de os_itens/apontamentos_horas/hh_lancamentos ainda nao registradas em os_orcamento_export_linha, entao pode ser chamado repetidas vezes com seguranca sem duplicar nem tocar em edicoes manuais do orcamento.';

notify pgrst, 'reload schema';

commit;
