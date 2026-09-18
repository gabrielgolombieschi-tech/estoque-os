-- Quem emitiu a nota, e a data de faturamento da ordem.
--
-- 1. AUTOR DA EMISSAO. A emissao roda em Edge Function com o cliente de servico, entao nem a
--    emissao, nem o documento, nem o audit_log guardavam o usuario: o gatilho de auditoria tira o
--    autor de request.jwt.claim.*, e na conexao de servico nao ha claims. O token do usuario JA
--    chega na funcao (ela monta userClient(request) para autorizar); faltava carregar o id adiante.
--
--    Agora a emissao tem `emitido_por`, os eventos herdam esse autor quando nascem sem um, e a
--    RPC f.fn_emissao_registrar_autor grava o autor explicitamente tambem no audit_log — que e o
--    "passar o autor explicitamente nas escritas feitas pelo cliente de servico".
--
--    Isto NAO muda quem pode emitir: a autorizacao continua onde esta, nas RPCs de prontidao e
--    contexto chamadas com o cliente do usuario. Aqui so se registra.
--
-- 2. DATA DE FATURAMENTO. public.ordens_servico.faturado_em existia e ficava sempre nulo, mesmo
--    com nota autorizada. Um gatilho em f.documento_fiscal passa a preenche-la quando a ordem
--    ganha a primeira nota de saida EMITIDA e a limpa quando nao sobra nenhuma — o cancelamento da
--    NF-e 2/34 e o caso real que motivou isso.
--
--    A regra de "emitida" aqui e a estrita de f.fn_documento_esta_emitido (20260919160000):
--    cancelada nao conta e situacao vazia tambem nao.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. AUTOR DA EMISSAO ------------------------------------------------------------------------

alter table f.documento_fiscal_emissao
  add column if not exists emitido_por uuid;

do $fk$
begin
  if not exists (select 1 from pg_constraint where conname = 'documento_fiscal_emissao_emitido_por_fkey') then
    alter table f.documento_fiscal_emissao
      add constraint documento_fiscal_emissao_emitido_por_fkey
      foreign key (emitido_por) references a.usuario(id) on delete set null;
  end if;
end;
$fk$;

comment on column f.documento_fiscal_emissao.emitido_por is
  'Usuario que confirmou a emissao na tela. Vem do token que chega na Edge Function; nulo nas emissoes anteriores a 18/09/2026 e nas disparadas sem sessao.';

-- Evento que nasce sem autor herda o autor da emissao daquele documento. Cobre os eventos que a
-- Focus cria depois, pelo callback (AUTORIZACAO, DOWNLOAD), fora da requisicao do usuario.
create or replace function f.tg_documento_fiscal_evento_autor()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'f'
as $function$
begin
  if new.criado_por is null then
    select e.emitido_por into new.criado_por
    from f.documento_fiscal_emissao e
    where e.documento_fiscal_id = new.documento_fiscal_id
      and e.emitido_por is not null
    order by e.created_at desc
    limit 1;
  end if;
  return new;
end;
$function$;

drop trigger if exists documento_fiscal_evento_autor on f.documento_fiscal_evento;
create trigger documento_fiscal_evento_autor
  before insert on f.documento_fiscal_evento
  for each row execute function f.tg_documento_fiscal_evento_autor();

-- Chamada pela Edge Function com o id do usuario lido do proprio token dela.
create or replace function f.fn_emissao_registrar_autor(p_documento_fiscal_id uuid, p_usuario_id uuid)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'a', 'public'
as $function$
declare
  v_tenant uuid;
  v_email text;
  v_afetadas integer;
begin
  if p_documento_fiscal_id is null or p_usuario_id is null then
    return;
  end if;

  select u.email into v_email from a.usuario u where u.id = p_usuario_id;
  if v_email is null then
    return;
  end if;

  update f.documento_fiscal_emissao e
     set emitido_por = p_usuario_id,
         updated_at = now()
   where e.documento_fiscal_id = p_documento_fiscal_id
     and e.emitido_por is null
  returning e.tenant_id into v_tenant;
  get diagnostics v_afetadas = row_count;

  if v_afetadas = 0 then
    return;
  end if;

  -- Eventos ja gravados nesta mesma emissao ficam com o autor tambem.
  update f.documento_fiscal_evento ev
     set criado_por = p_usuario_id
   where ev.documento_fiscal_id = p_documento_fiscal_id
     and ev.criado_por is null;

  -- O autor explicito no log: o gatilho de auditoria nao consegue descobrir sozinho, porque a
  -- conexao e de servico e nao tem claims de usuario.
  insert into public.audit_log (tenant_id, table_name, action, row_pk, old_data, new_data, actor_user_id, actor_email)
  values (
    v_tenant,
    'documento_fiscal_emissao',
    'UPDATE',
    p_documento_fiscal_id::text,
    jsonb_build_object('emitido_por', null),
    jsonb_build_object('emitido_por', p_usuario_id),
    p_usuario_id,
    v_email
  );
end;
$function$;

comment on function f.fn_emissao_registrar_autor(uuid, uuid) is
  'Registra quem confirmou a emissao: grava emitido_por, propaga aos eventos sem autor e escreve o autor explicito no audit_log. Nao altera permissao de emitir.';

revoke all on function f.fn_emissao_registrar_autor(uuid, uuid) from public;
grant execute on function f.fn_emissao_registrar_autor(uuid, uuid) to service_role;

-- 2. DATA DE FATURAMENTO DA ORDEM ------------------------------------------------------------

create or replace function f.tg_documento_fiscal_faturado_em()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'public'
as $function$
declare
  v_os integer := coalesce(new.os_id_import, old.os_id_import);
  v_tenant uuid := coalesce(new.tenant_id, old.tenant_id);
  v_empresa uuid := coalesce(new.empresa_id, old.empresa_id);
  v_tem_emitida boolean;
  v_tem_cancelada boolean;
begin
  if v_os is null or v_tenant is null or v_empresa is null then
    return coalesce(new, old);
  end if;

  select
    bool_or(f.fn_documento_esta_emitido(d.modelo, d.nfe_status, d.nfse_status)),
    bool_or(upper(coalesce(d.nfe_status, d.nfse_status, '')) = 'CANCELADA')
  into v_tem_emitida, v_tem_cancelada
  from f.documento_fiscal d
  where d.tenant_id = v_tenant and d.empresa_id = v_empresa and d.os_id_import = v_os
    and d.operacao = 'SAIDA' and d.deleted_at is null;

  if coalesce(v_tem_emitida, false) then
    update public.ordens_servico os
       set faturado_em = coalesce(os.faturado_em, now())
     where os.tenant_id = v_tenant and os.empresa_id = v_empresa and os.id = v_os
       and os.faturado_em is null;
  elsif coalesce(v_tem_cancelada, false) then
    -- So o cancelamento derruba a data. Rascunho nao derruba, e ordem sem nenhum documento
    -- (faturada fora do ERP, antes do modulo fiscal) nunca passa por aqui.
    update public.ordens_servico os
       set faturado_em = null
     where os.tenant_id = v_tenant and os.empresa_id = v_empresa and os.id = v_os
       and os.faturado_em is not null;
  end if;

  return coalesce(new, old);
end;
$function$;

drop trigger if exists documento_fiscal_faturado_em on f.documento_fiscal;
create trigger documento_fiscal_faturado_em
  after insert or update of nfe_status, nfse_status, deleted_at, os_id_import on f.documento_fiscal
  for each row execute function f.tg_documento_fiscal_faturado_em();

-- Backfill: as ordens que ja tem nota emitida ganham a data da autorizacao mais antiga; as que
-- so tem nota cancelada ou nenhuma ficam com nulo.
update public.ordens_servico os
   set faturado_em = sub.autorizado_em
  from (
    select d.tenant_id, d.empresa_id, d.os_id_import as os_id,
           min(coalesce(e.autorizado_em, d.created_at)) as autorizado_em
    from f.documento_fiscal d
    left join f.documento_fiscal_emissao e
      on e.documento_fiscal_id = d.id and upper(coalesce(e.status, '')) = 'AUTORIZADA'
    where d.os_id_import is not null and d.operacao = 'SAIDA' and d.deleted_at is null
      and f.fn_documento_esta_emitido(d.modelo, d.nfe_status, d.nfse_status)
    group by d.tenant_id, d.empresa_id, d.os_id_import
  ) sub
 where os.tenant_id = sub.tenant_id and os.empresa_id = sub.empresa_id and os.id = sub.os_id
   and os.faturado_em is null;

do $assertions$
declare
  v_ov record;
begin
  if not exists (select 1 from public.ordens_servico where id = 365) then
    raise notice 'banco sem os dados de producao: asserts de dados pulados.';
    return;
  end if;

  select o.faturado_em, (select count(*) from f.documento_fiscal_emissao e where e.emitido_por is not null) as com_autor
    into v_ov
  from public.ordens_servico o where o.id = 365;

  -- A OV-012 tem a NF-e 2/35 autorizada: a data tem de estar preenchida.
  if v_ov.faturado_em is null then
    raise exception 'OV 365 tem nota emitida e ficou sem faturado_em';
  end if;

  -- Nenhuma ordem cuja unica nota foi cancelada pode ter data de faturamento. A regra vale para
  -- quem passou pelo modulo fiscal; as 141 ordens legadas, faturadas fora do ERP e sem nenhum
  -- documento, mantem a data que ja tinham — apaga-la seria perder informacao.
  if exists (
    select 1
    from public.ordens_servico os
    join f.v_os_faturamento_status v on v.os_id = os.id
    where os.faturado_em is not null
      and v.notas_emitidas = 0
      and v.notas_canceladas > 0
  ) then
    raise exception 'ha ordem com faturado_em cuja unica nota foi cancelada';
  end if;
end;
$assertions$;

commit;
