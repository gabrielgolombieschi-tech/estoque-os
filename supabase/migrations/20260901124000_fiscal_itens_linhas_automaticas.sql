begin;

-- Cria somente a identidade da linha fiscal para os itens ativos que ainda
-- nao a possuem. Os atributos e aliquotas ficam nulos; os quatro booleanos
-- obrigatorios conservam os defaults historicos definidos no baseline.
insert into public.fiscal_itens (
  tenant_id,
  empresa_id,
  item_id,
  ncm,
  cest,
  origem,
  cfop_padrao,
  cst_icms,
  cst_pis,
  cst_cofins,
  aliq_icms,
  aliq_ipi,
  aliq_pis,
  aliq_cofins,
  unidade_tributavel
)
select
  i.tenant_id,
  i.empresa_id,
  i.id,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null
from public.itens i
where i.ativo is true
on conflict do nothing;

create or replace function public.fn_itens_criar_linha_fiscal()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if new.ativo is true then
    insert into public.fiscal_itens (
      tenant_id,
      empresa_id,
      item_id,
      ncm,
      cest,
      origem,
      cfop_padrao,
      cst_icms,
      cst_pis,
      cst_cofins,
      aliq_icms,
      aliq_ipi,
      aliq_pis,
      aliq_cofins,
      unidade_tributavel
    )
    values (
      new.tenant_id,
      new.empresa_id,
      new.id,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null
    )
    on conflict do nothing;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_itens_criar_linha_fiscal on public.itens;

create trigger trg_itens_criar_linha_fiscal
after insert or update of ativo on public.itens
for each row
execute function public.fn_itens_criar_linha_fiscal();

commit;
