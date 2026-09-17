-- Nota de producao cancelada encerra a operacao fiscal que a gerou.
--
-- A NF-e 2/19 (remessa para conserto das cortinas SICK, 16/09/2026) saiu com o item 1
-- errado e foi cancelada para ser refeita. Ate aqui o cancelamento pelo ciclo de vida so
-- mexia na nota: a operacao REMESSA continuava AGUARDANDO_RETORNO e a remessa seguia em
-- "Remessas em aberto" cobrando um retorno de uma nota que nao existe mais.
--
-- Agora, quando a emissao de PRODUCAO de uma operacao (remessa, retorno, devolucao...)
-- passa a CANCELADA, a operacao vira CANCELADA com a justificativa e o controle de
-- retorno da remessa e cancelado. A remessa de terceiros (retorno) ja tinha o seu
-- gatilho proprio, que reabre a remessa; ele continua igual.

create or replace function f.fn_operacao_fiscal_apos_cancelamento()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_op f.operacao_fiscal%rowtype;
begin
  if new.status <> 'CANCELADA' or coalesce(old.status, '') = 'CANCELADA'
     or new.ambiente <> 'PRODUCAO' or new.solicitacao_id is null then
    return new;
  end if;
  select * into v_op
  from f.operacao_fiscal op
  where op.tenant_id = new.tenant_id and op.empresa_id = new.empresa_id
    and op.solicitacao_id = new.solicitacao_id and op.deleted_at is null
  for update;
  if not found or v_op.status = 'CANCELADA' then return new; end if;

  update f.operacao_fiscal
     set status = 'CANCELADA',
         justificativa_fisco = coalesce(justificativa_fisco || ' | ', '')
           || format('NF-e %s/%s cancelada na SEFAZ em %s', coalesce(new.serie::text, '?'), coalesce(new.numero::text, '?'),
                     to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')),
         updated_at = now()
   where id = v_op.id;

  if v_op.tipo = 'REMESSA' and new.chave_acesso ~ '^[0-9]{44}$' then
    update f.remessa_controle
       set status = 'CANCELADA', updated_at = now()
     where tenant_id = v_op.tenant_id and empresa_id = v_op.empresa_id
       and chave_remessa = new.chave_acesso and status = 'ABERTA';
  end if;
  return new;
end;
$$;
revoke all on function f.fn_operacao_fiscal_apos_cancelamento() from public, anon, authenticated;

drop trigger if exists trg_operacao_fiscal_apos_cancelamento on f.documento_fiscal_emissao;
create trigger trg_operacao_fiscal_apos_cancelamento
  after update of status on f.documento_fiscal_emissao
  for each row execute function f.fn_operacao_fiscal_apos_cancelamento();
