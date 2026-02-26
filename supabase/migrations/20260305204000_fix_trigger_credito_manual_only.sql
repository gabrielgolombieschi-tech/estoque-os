begin;
create or replace function f.trg_titulo__aplicar_credito_fiscal_manual()
returns trigger
language plpgsql
security definer
set search_path to 'f','public','a','c'
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  -- Escopo correto: apenas AP MANUAL sem documento fiscal.
  -- Evita bloquear importacao XML com erro "somente ADMIN/FINANCEIRO".
  if coalesce(new.tipo,'') = 'AP'
     and upper(coalesce(new.origem,'')) = 'MANUAL'
     and new.documento_fiscal_id is null
  then
    perform 1 from f.fn_aplicar_credito_fiscal_manual_titulo(new.id, 'TRIGGER_TITULO_MANUAL');
  end if;

  return new;
end;
$$;
commit;
