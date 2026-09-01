begin;

alter table m.orcamento
  drop constraint if exists ck_orcamento__status;

-- Backfill: converte status legado para o novo padrao.
update m.orcamento
set status = case upper(trim(coalesce(status, '')))
  when 'RASCUNHO' then 'ANDAMENTO'
  when 'FINALIZADO' then 'FECHADO'
  when 'CANCELADO' then 'PERDIDO'
  else upper(trim(coalesce(status, 'ANDAMENTO')))
end
where status is not null;

update m.orcamento
set status = 'ANDAMENTO'
where status is null or trim(status) = '';

-- Garantia de compatibilidade de entrada: se algum fluxo antigo enviar
-- RASCUNHO/FINALIZADO/CANCELADO, normalizamos antes da validacao.
create or replace function m.fn_orcamento_normalize_status()
returns trigger
language plpgsql
as $$
begin
  new.status := upper(trim(coalesce(new.status, '')));

  if new.status = '' then
    new.status := 'ANDAMENTO';
  elsif new.status = 'RASCUNHO' then
    new.status := 'ANDAMENTO';
  elsif new.status = 'FINALIZADO' then
    new.status := 'FECHADO';
  elsif new.status = 'CANCELADO' then
    new.status := 'PERDIDO';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_orcamento_normalize_status on m.orcamento;
create trigger trg_orcamento_normalize_status
before insert or update of status on m.orcamento
for each row
execute function m.fn_orcamento_normalize_status();

alter table m.orcamento
  alter column status set default 'ANDAMENTO';

alter table m.orcamento
  add constraint ck_orcamento__status
  check (status in ('ANDAMENTO', 'FECHADO', 'PERDIDO'));

commit;
