-- Observacao interna da solicitacao de faturamento: fica no ERP e NAO vai para a nota.
--
-- Pedido do Gabriel em 18/09/2026 (NFS-e da OS 298, CREMER): registrar por que o material da OS
-- entrou como insumo do servico. O campo "Observacao livre" que ja existia entra na discriminacao
-- da NFS-e (o cliente le), entao nao serve para decisao interna.
--
-- A RPC e o unico caminho de escrita: quem fatura na empresa ativa, com a solicitacao ainda
-- aberta (rascunho, previa ou aprovada). Depois de emitida, a observacao fica como estava.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

alter table f.solicitacao_faturamento
  add column if not exists observacao_interna text;

comment on column f.solicitacao_faturamento.observacao_interna is
  'Observacao interna da solicitacao: decisao de quem faturou. Nunca entra no documento fiscal (20260919060000).';

create or replace function f.fn_solicitacao_observacao_interna(p_solicitacao_id uuid, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_texto text := nullif(btrim(coalesce(p_texto, '')), '');
begin
  select * into v_sf from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para anotar nesta solicitacao.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s: a observacao interna nao muda mais.', v_sf.status);
  end if;
  if v_texto is not null and char_length(v_texto) > 1000 then
    raise exception using errcode = '22023', message = 'A observacao interna pode ter no maximo 1000 caracteres.';
  end if;

  update f.solicitacao_faturamento
     set observacao_interna = v_texto, updated_at = now()
   where id = v_sf.id;

  return jsonb_build_object('solicitacao_id', v_sf.id, 'observacao_interna', v_texto);
end;
$$;

comment on function f.fn_solicitacao_observacao_interna(uuid, text) is
  'Grava a observacao interna da solicitacao (nao vai na nota); exige acesso financeiro e solicitacao aberta (20260919060000).';

revoke all on function f.fn_solicitacao_observacao_interna(uuid, text) from public, anon;
grant execute on function f.fn_solicitacao_observacao_interna(uuid, text) to authenticated, service_role;

do $assertions$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'f' and table_name = 'solicitacao_faturamento' and column_name = 'observacao_interna'
  ) then
    raise exception 'coluna observacao_interna nao criada';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
