begin;

create or replace function f.trg_sincronizar_faixa_perfil_evidencia()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
begin
  if new.evidencia_id is not null then
    update f.perfil_operacao_evidencia
       set faixa = new.faixa_automacao,
           justificativa_faixa = coalesce(new.justificativa_faixa, justificativa_faixa)
     where id = new.evidencia_id
       and tenant_id = new.tenant_id
       and empresa_id = new.empresa_id;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_sincronizar_faixa_perfil_evidencia
  on f.perfil_operacao;
create trigger trg_sincronizar_faixa_perfil_evidencia
  after update of faixa_automacao, justificativa_faixa
  on f.perfil_operacao
  for each row
  when (
    old.faixa_automacao is distinct from new.faixa_automacao
    or old.justificativa_faixa is distinct from new.justificativa_faixa
  )
  execute function f.trg_sincronizar_faixa_perfil_evidencia();

update f.perfil_operacao_evidencia ev
   set faixa = po.faixa_automacao,
       justificativa_faixa = coalesce(po.justificativa_faixa, ev.justificativa_faixa)
  from f.perfil_operacao po
 where po.evidencia_id = ev.id
   and po.tenant_id = ev.tenant_id
   and po.empresa_id = ev.empresa_id;

commit;
