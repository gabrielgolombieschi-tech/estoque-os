-- Cliente que exige o numero do pedido de compra no corpo da nota.
--
-- Pedido do Gabriel em 18/09/2026, na NFS-e da OS 298 (CREMER): alguns clientes recusam a nota
-- que nao cita a OC. O cadastro passa a dizer isso, e a tela de faturar NFS-e cobra o numero
-- antes de deixar conferir. Hoje o campo do pedido e opcional ("Sem OC. Nao bloqueia.").
--
-- A CREMER (cliente 178) ja entra marcada: a OC 148753 tem clausula de prazo e exige o numero
-- na nota.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

alter table public.clientes
  add column if not exists exige_pedido_compra boolean not null default false;

comment on column public.clientes.exige_pedido_compra is
  'Cliente exige o numero do pedido de compra (OC) no corpo da nota: a tela de faturar cobra o campo antes da conferencia (20260919050000).';

do $marcar$
declare
  v_nome text;
begin
  select c.nome into v_nome from public.clientes c where c.id = 178;
  if v_nome is null then
    raise notice 'cliente 178 nao existe neste banco: nada a marcar.';
    return;
  end if;
  if v_nome !~* 'CREMER' then
    raise exception 'cliente 178 deveria ser a CREMER, encontrado %', v_nome;
  end if;
  -- Optante do Simples ficou "nao informado" no cadastro e isso vira aviso na nota: a CREMER S.A.
  -- nao e optante (conferido com o Gabriel em 18/09/2026), e sem essa marca a dispensa da CRF
  -- (Lei 10.833/2003, art. 30, § 2º) fica em aberto na conferencia.
  update public.clientes
     set exige_pedido_compra = true,
         optante_simples = coalesce(optante_simples, false),
         atualizado_em = now()
   where id = 178;
end;
$marcar$;

do $assertions$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'clientes' and column_name = 'exige_pedido_compra'
  ) then
    raise exception 'coluna exige_pedido_compra nao criada';
  end if;
  -- Ninguem mais e marcado por esta migration.
  if (select count(*) from public.clientes where exige_pedido_compra) > 1 then
    raise exception 'mais de um cliente marcado como exige_pedido_compra';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
