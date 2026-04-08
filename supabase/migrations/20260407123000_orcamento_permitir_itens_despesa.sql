begin;

alter table m.orcamento_item
  drop constraint if exists ck_orcamento_item__tipo;

alter table m.orcamento_item
  add constraint ck_orcamento_item__tipo
  check (item_tipo = any (array['PRODUTO'::text, 'SERVICO'::text, 'DESPESA'::text]));

create or replace function m.trg_orcamento_item_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public', 'a'
set row_security = off
as $$
declare
  v_orc m.orcamento%rowtype;
  v_item public.itens%rowtype;
  v_tipo text;
  v_calc record;
  v_desc_livre text;
begin
  if tg_op = 'UPDATE' and new.orcamento_id is distinct from old.orcamento_id then
    raise exception 'Nao e permitido alterar orcamento_id do item.';
  end if;

  if tg_op = 'UPDATE' and new.deleted_at is not null and old.deleted_at is null then
    new.tenant_id := old.tenant_id;
    new.empresa_id := old.empresa_id;
    return new;
  end if;

  select * into v_orc
  from m.orcamento o
  where o.id = new.orcamento_id
    and o.deleted_at is null;

  if not found then
    raise exception 'Orcamento nao encontrado (orcamento_id=%)', new.orcamento_id;
  end if;

  new.tenant_id := v_orc.tenant_id;
  new.empresa_id := v_orc.empresa_id;

  if new.seq is null or new.seq < 1 then
    select coalesce(max(seq),0) + 1
      into new.seq
    from m.orcamento_item
    where orcamento_id = new.orcamento_id;
  end if;

  select * into v_item
  from public.itens i
  where i.id = new.item_id
    and i.tenant_id = new.tenant_id
    and i.empresa_id = new.empresa_id
    and i.ativo = true;

  if not found then
    raise exception 'Item invalido para este tenant/empresa (item_id=%)', new.item_id;
  end if;

  v_tipo := lower(v_item.tipo);
  if v_tipo = 'produto' then
    new.item_tipo := 'PRODUTO';
  elsif v_tipo = 'servico' then
    new.item_tipo := 'SERVICO';
  elsif v_tipo = 'despesa' then
    new.item_tipo := 'DESPESA';
  else
    raise exception 'Item do tipo "%" nao e permitido em Orcamento (somente produto/servico/despesa)', v_item.tipo;
  end if;

  new.item_nome := upper(trim(v_item.nome));
  new.unidade := upper(trim(coalesce(v_item.unidade_medida, 'UN')));

  v_desc_livre := nullif(trim(coalesce(new.observacoes, '')), '');
  if upper(trim(coalesce(v_item.codigo_interno, ''))) = '9999' and v_desc_livre is not null then
    new.item_nome := upper(v_desc_livre);
  end if;

  new.acrescimo_cond_pag_percent := v_orc.acrescimo_cond_pag_percent;
  new.desconto_global_percent := v_orc.desconto_global_percent;

  select * into v_calc
  from m.fn_orcamento_item_calcular(
    new.quantidade,
    new.valor_unitario,
    new.desconto_item_percent,
    new.acrescimo_cond_pag_percent,
    new.desconto_global_percent
  );

  new.valor_total_bruto := v_calc.valor_total_bruto;
  new.valor_total := v_calc.valor_total;
  new.valor_unitario_liquido := v_calc.valor_unitario_liquido;

  return new;
end;
$$;

grant all on function m.trg_orcamento_item_biu() to authenticated;
grant all on function m.trg_orcamento_item_biu() to service_role;

commit;
