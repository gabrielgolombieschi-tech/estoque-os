-- Ajustes finais modulo Compras > Pedidos (fase 2)

create or replace function m.trg_compra_pendencia_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_item public.itens%rowtype;
  v_estoque_atual numeric(15,3) := 0;
  v_em_compra numeric(15,3) := 0;
  v_alvo numeric(15,3) := 0;
begin
  if new.item_id is null and new.item_nome is not null then
    new.item_nome := upper(trim(new.item_nome));
  end if;

  if new.origem_tipo = 'OS' and new.origem_os_id is null then
    raise exception 'origem_os_id obrigatorio quando origem_tipo=OS';
  end if;

  if new.origem_tipo = 'ESTOQUE' then
    if new.item_id is null then
      raise exception 'item_id obrigatorio quando origem_tipo=ESTOQUE';
    end if;
    if new.estoque_meta is null then
      raise exception 'estoque_meta obrigatorio quando origem_tipo=ESTOQUE';
    end if;

    select * into v_item
    from public.itens i
    where i.tenant_id = new.tenant_id
      and i.empresa_id = new.empresa_id
      and i.id = new.item_id
      and i.deleted_at is null
    limit 1;

    if not found then
      raise exception 'Item % nao encontrado para pendencia de estoque', new.item_id;
    end if;

    if new.item_nome is null or btrim(new.item_nome) = '' then
      new.item_nome := upper(trim(coalesce(v_item.nome, v_item.descricao, 'ITEM')));
    end if;
    if new.unidade is null or btrim(new.unidade) = '' then
      new.unidade := coalesce(nullif(trim(v_item.unidade_medida), ''), 'UN');
    end if;

    select coalesce(e.quantidade_atual, 0)::numeric(15,3)
      into v_estoque_atual
    from public.estoque e
    where e.tenant_id = new.tenant_id
      and e.empresa_id = new.empresa_id
      and e.item_id = new.item_id;

    select coalesce(sum(greatest(i.quantidade - i.quantidade_recebida, 0)), 0)::numeric(15,3)
      into v_em_compra
    from m.pedido_compra_item i
    join m.pedido_compra p on p.id = i.pedido_compra_id
    where p.deleted_at is null
      and i.deleted_at is null
      and p.tenant_id = new.tenant_id
      and p.empresa_id = new.empresa_id
      and i.item_id = new.item_id
      and p.status in ('RASCUNHO','AGUARDANDO_APROVACAO','APROVADO','ENVIADO','PARCIAL_RECEBIDO');

    v_alvo := case upper(trim(new.estoque_meta))
      when 'MIN' then coalesce(v_item.estoque_minimo, 0)
      when 'IDEAL' then coalesce(v_item.estoque_ideal, 0)
      when 'MAX' then coalesce(v_item.estoque_maximo, 0)
      else 0
    end;

    new.estoque_atual_qtd := v_estoque_atual;
    new.estoque_em_compra_qtd := v_em_compra;
    new.estoque_alvo_qtd := v_alvo;
    new.estoque_sugestao_qtd := greatest(0, v_alvo - (v_estoque_atual + v_em_compra));
  else
    new.estoque_atual_qtd := null;
    new.estoque_em_compra_qtd := null;
    new.estoque_alvo_qtd := null;
    new.estoque_sugestao_qtd := null;
  end if;

  return new;
end;
$$;

drop view if exists r.r_compra_pendencias_agrupadas_item;
create or replace view r.r_compra_pendencias_agrupadas_item as
with pend as (
  select
    cp.id,
    cp.tenant_id,
    cp.empresa_id,
    cp.fornecedor_id,
    cp.origem_tipo,
    cp.origem_os_id,
    cp.item_id,
    upper(trim(coalesce(cp.item_nome, i.nome, i.descricao, 'ITEM SEM NOME'))) as item_nome,
    coalesce(nullif(trim(cp.unidade),''), nullif(trim(i.unidade_medida),''), 'UN') as unidade,
    cp.quantidade,
    cp.estoque_meta,
    cp.created_at,
    os.os_num,
    os.numero_os
  from m.compra_pendencia cp
  left join public.itens i on i.tenant_id=cp.tenant_id and i.empresa_id=cp.empresa_id and i.id=cp.item_id
  left join public.ordens_servico os on os.tenant_id=cp.tenant_id and os.empresa_id=cp.empresa_id and os.id=cp.origem_os_id
  where cp.deleted_at is null and cp.status='PENDENTE'
), em_compra as (
  select p.tenant_id, p.empresa_id, i.item_id, sum(greatest(i.quantidade - i.quantidade_recebida, 0))::numeric(15,3) as qtd_em_compra_aberto
  from m.pedido_compra_item i
  join m.pedido_compra p on p.id = i.pedido_compra_id
  where p.deleted_at is null and i.deleted_at is null and p.status in ('RASCUNHO','AGUARDANDO_APROVACAO','APROVADO','ENVIADO','PARCIAL_RECEBIDO')
  group by p.tenant_id, p.empresa_id, i.item_id
)
select
  p.tenant_id,
  p.empresa_id,
  p.fornecedor_id,
  coalesce(f.nome, 'SEM FORNECEDOR') as fornecedor_nome,
  p.item_id,
  i.codigo_interno as item_codigo,
  p.item_nome,
  p.unidade,
  array_agg(p.id order by p.created_at asc) as pendencia_ids,
  coalesce(sum(p.quantidade) filter (where p.origem_tipo='OS'),0)::numeric(15,3) as qtd_os_total,
  coalesce(sum(p.quantidade) filter (where p.origem_tipo in ('OUTROS','ESTOQUE')),0)::numeric(15,3) as qtd_outros_total,
  coalesce(e.quantidade_atual,0)::numeric(15,3) as qtd_estoque_atual,
  coalesce(ec.qtd_em_compra_aberto,0)::numeric(15,3) as qtd_em_compra_aberto,
  greatest(0, coalesce(i.estoque_minimo,0)::numeric - (coalesce(e.quantidade_atual,0)+coalesce(ec.qtd_em_compra_aberto,0)))::numeric(15,3) as sugestao_min,
  greatest(0, coalesce(i.estoque_ideal,0)::numeric - (coalesce(e.quantidade_atual,0)+coalesce(ec.qtd_em_compra_aberto,0)))::numeric(15,3) as sugestao_ideal,
  greatest(0, coalesce(i.estoque_maximo,0)::numeric - (coalesce(e.quantidade_atual,0)+coalesce(ec.qtd_em_compra_aberto,0)))::numeric(15,3) as sugestao_max,
  (array_agg(p.id order by p.created_at asc) filter (where p.origem_tipo='ESTOQUE'))[1] as estoque_pendencia_id,
  max(p.estoque_meta) filter (where p.origem_tipo='ESTOQUE') as estoque_meta_atual,
  coalesce(sum(p.quantidade) filter (where p.origem_tipo='ESTOQUE'),0)::numeric(15,3) as qtd_estoque_pendencia,
  coalesce(jsonb_agg(jsonb_build_object('pendencia_id', p.id, 'os_id', p.origem_os_id, 'os_num', p.os_num, 'numero_os', p.numero_os, 'quantidade', p.quantidade) order by p.created_at asc) filter (where p.origem_tipo='OS'), '[]'::jsonb) as os_breakdown
from pend p
left join public.fornecedores f on f.tenant_id=p.tenant_id and f.empresa_id=p.empresa_id and f.id=p.fornecedor_id
left join public.itens i on i.tenant_id=p.tenant_id and i.empresa_id=p.empresa_id and i.id=p.item_id
left join public.estoque e on e.tenant_id=p.tenant_id and e.empresa_id=p.empresa_id and e.item_id=p.item_id
left join em_compra ec on ec.tenant_id=p.tenant_id and ec.empresa_id=p.empresa_id and ec.item_id=p.item_id
group by p.tenant_id,p.empresa_id,p.fornecedor_id,coalesce(f.nome,'SEM FORNECEDOR'),p.item_id,i.codigo_interno,p.item_nome,p.unidade,e.quantidade_atual,ec.qtd_em_compra_aberto,i.estoque_minimo,i.estoque_ideal,i.estoque_maximo;

grant select on r.r_compra_pendencias_agrupadas_item to authenticated, service_role;

create or replace function public.get_full_permissions(p_tenant_id uuid, p_empresa_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'a'
as $$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_empresa_papel text;
  v_perm_extra jsonb;
  v_perm_negadas jsonb;
  base_perms jsonb := '{}'::jsonb;
  extra_perms jsonb := '{}'::jsonb;
  result_perms jsonb;
begin
  select u.id into v_usuario_id
  from a.usuario u
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return '{}'::jsonb;
  end if;

  select ut.papel into v_tenant_papel
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  limit 1;

  if v_tenant_papel is null then
    return '{}'::jsonb;
  end if;

  select jsonb_object_agg(rp.permission, true) into base_perms
  from public.role_permissions rp
  where rp.role = a.fn_map_papel_tenant_to_role(v_tenant_papel);

  base_perms := coalesce(base_perms, '{}'::jsonb);

  select ue.papel, ue.permissoes_extra, ue.permissoes_negadas
    into v_empresa_papel, v_perm_extra, v_perm_negadas
  from a.usuario_empresa ue
  where ue.usuario_id = v_usuario_id
    and ue.empresa_id = p_empresa_id
    and ue.ativo = true
    and ue.deleted_at is null
  limit 1;

  if v_empresa_papel is null then
    return base_perms;
  end if;

  extra_perms := extra_perms || jsonb_build_object(
    'modulo_preferencial',
    (
      case upper(coalesce(v_empresa_papel,''))
        when 'ADMIN' then 'admin'
        when 'FINANCEIRO' then 'financeiro'
        when 'COORDENACAO' then 'projetos'
        when 'COMPRAS' then 'estoque'
        when 'ALMOXARIFADO' then 'estoque'
        when 'APONTAMENTO_RH' then 'projetos'
        else null
      end
    )
  );

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COORDENACAO') then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true,
      'os.delete', true
    );
  elsif upper(coalesce(v_empresa_papel,'')) = 'APONTAMENTO_RH' then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true
    );
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO') then
    extra_perms := extra_perms || jsonb_build_object(
      'financeiro.read', true,
      'financeiro.write', true,
      'faturamento.read', true,
      'faturamento.write', true,
      'faturamento.nfe.import_xml', true
    );
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('estoque.read', true);
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO') then
    extra_perms := extra_perms || jsonb_build_object('estoque.write', true);
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS') then
    extra_perms := extra_perms || jsonb_build_object(
      'compras.read', true,
      'compras.approve', true
    );
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COORDENACAO','COMPRAS') then
    extra_perms := extra_perms || jsonb_build_object(
      'compras.write', true,
      'compras.receive', true
    );
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.read', true);
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.write', true);
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO','FINANCEIRO') then
    extra_perms := extra_perms || jsonb_build_object(
      'xml_import.execute', true,
      'nf_entrada.import', true,
      'cad_fornecedores.write', true,
      'cad_itens.write', true
    );
  end if;

  if v_perm_extra is not null then
    extra_perms := extra_perms || v_perm_extra;
  end if;

  result_perms := base_perms || extra_perms;

  if v_perm_negadas is not null then
    result_perms := result_perms - (select array_agg(key) from jsonb_object_keys(v_perm_negadas) as key);
  end if;

  return coalesce(result_perms, '{}'::jsonb);
end;
$$;

grant execute on function public.get_full_permissions(uuid, uuid) to anon, authenticated, service_role;