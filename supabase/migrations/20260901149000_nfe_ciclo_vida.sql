begin;

-- O historico fiscal e imutavel: cada tentativa e cada resultado geram uma
-- nova linha. O estado corrente da emissao continua na tabela de emissao.
alter table f.documento_fiscal_evento
  drop constraint if exists documento_fiscal_evento_tipo_check,
  add column if not exists destinatarios text[],
  add column if not exists sequencia integer,
  add column if not exists referencia_externa text,
  add constraint documento_fiscal_evento_tipo_check check (tipo in (
    'CANCELAMENTO', 'CARTA_CORRECAO', 'ESTORNO', 'SUBSTITUICAO',
    'REENVIO', 'CONSULTA', 'EMAIL', 'DOWNLOAD'
  ));

create or replace function f.fn_documento_fiscal_evento_append_only()
returns trigger language plpgsql set search_path = pg_catalog as $function$
begin
  raise exception using errcode = '55000',
    message = 'Eventos fiscais sao append-only; grave um novo evento em vez de alterar o historico.';
end;
$function$;

drop trigger if exists documento_fiscal_evento_append_only on f.documento_fiscal_evento;
create trigger documento_fiscal_evento_append_only
before update or delete on f.documento_fiscal_evento
for each row execute function f.fn_documento_fiscal_evento_append_only();

revoke insert, update, delete on f.documento_fiscal_evento from authenticated;
grant select on f.documento_fiscal_evento to authenticated;

create table f.nfe_inutilizacao (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  ambiente text not null default 'HOMOLOGACAO' check (ambiente = 'HOMOLOGACAO'),
  serie integer not null check (serie between 0 and 999),
  numero_inicial integer not null check (numero_inicial > 0),
  numero_final integer not null check (numero_final >= numero_inicial),
  justificativa text not null check (char_length(btrim(justificativa)) between 15 and 255),
  status text not null check (status in ('AUTORIZADA', 'REJEITADA', 'ERRO')),
  protocolo text,
  resposta jsonb not null default '{}'::jsonb,
  criado_por uuid default a.fn_current_usuario_id() references a.usuario(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint nfe_inutilizacao_empresa_fk foreign key (tenant_id, empresa_id)
    references c.empresa(tenant_id, id),
  constraint nfe_inutilizacao_faixa_uk unique (tenant_id, empresa_id, ambiente, serie, numero_inicial, numero_final)
);

alter table f.nfe_inutilizacao enable row level security;
create policy nfe_inutilizacao_select on f.nfe_inutilizacao for select to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access());
grant select on f.nfe_inutilizacao to authenticated;
grant select, insert on f.nfe_inutilizacao to service_role;

create index nfe_inutilizacao_lista_idx
  on f.nfe_inutilizacao (tenant_id, empresa_id, serie, created_at desc);

create or replace function f.fn_nfe_ciclo_contexto(p_documento_fiscal_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog set row_security = off stable
as $function$
declare
  v_scope record;
  v_result jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select jsonb_build_object(
    'documento', to_jsonb(df),
    'emissao', to_jsonb(dfe),
    'cliente', case when cl.id is null then null else jsonb_build_object(
      'id', cl.id, 'nome', cl.nome, 'email', cl.email, 'email_financeiro', cl.email_financeiro
    ) end,
    'empresa', jsonb_build_object('id', emp.id, 'cnpj', emp.cnpj, 'nome', emp.nome_fantasia),
    'empresa_fiscal', case when ef.id is null then null else jsonb_build_object(
      'email_fisco', ef.email_fisco,
      'certificado_validade_em', ef.certificado_validade_em,
      'dias_certificado', case when ef.certificado_validade_em is null then null else ef.certificado_validade_em - current_date end
    ) end,
    'cancelamento', jsonb_build_object(
      'limite_em', dfe.autorizado_em + interval '24 hours',
      'segundos_restantes', greatest(0, extract(epoch from (dfe.autorizado_em + interval '24 hours' - now()))::bigint),
      'pode_cancelar', dfe.ambiente = 'HOMOLOGACAO' and dfe.status = 'AUTORIZADA'
        and dfe.autorizado_em is not null and now() < dfe.autorizado_em + interval '24 hours',
      'deve_estornar', dfe.status = 'AUTORIZADA' and dfe.autorizado_em is not null
        and now() >= dfe.autorizado_em + interval '24 hours'
    ),
    'cfops_estorno_propostos', coalesce((
      select jsonb_agg(x.cfop order by x.cfop)
      from (
        select distinct f.fn_cfop_estorno_proposto(i.cfop) cfop
        from f.documento_fiscal_item i
        where i.tenant_id = df.tenant_id and i.empresa_id = df.empresa_id
          and i.documento_fiscal_id = df.id and i.deleted_at is null
          and f.fn_cfop_estorno_proposto(i.cfop) is not null
      ) x
    ), '[]'::jsonb),
    'eventos', coalesce((
      select jsonb_agg(to_jsonb(ev) order by ev.created_at desc)
      from f.documento_fiscal_evento ev
      where ev.tenant_id = df.tenant_id and ev.empresa_id = df.empresa_id
        and ev.documento_fiscal_id = df.id
    ), '[]'::jsonb)
  ) into v_result
  from f.documento_fiscal df
  join f.documento_fiscal_emissao dfe
    on dfe.tenant_id = df.tenant_id and dfe.empresa_id = df.empresa_id and dfe.documento_fiscal_id = df.id
  join c.empresa emp on emp.tenant_id = df.tenant_id and emp.id = df.empresa_id
  left join c.empresa_fiscal ef on ef.empresa_id = emp.id and ef.deleted_at is null
  left join public.clientes cl
    on cl.tenant_id = df.tenant_id and cl.empresa_id = df.empresa_id and cl.id = df.cliente_id
  where df.tenant_id = v_scope.tenant_id and df.empresa_id = v_scope.empresa_id
    and df.id = p_documento_fiscal_id and df.deleted_at is null;

  if v_result is null then raise exception 'Emissao de NF-e nao encontrada nesta empresa.'; end if;
  return v_result;
end;
$function$;

create or replace function f.fn_nfe_evento_registrar(
  p_documento_fiscal_id uuid,
  p_tipo text,
  p_status text,
  p_justificativa text default null,
  p_protocolo text default null,
  p_resposta jsonb default '{}'::jsonb,
  p_destinatarios text[] default null,
  p_sequencia integer default null
)
returns uuid language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_id uuid;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode registrar eventos.';
  end if;
  p_tipo := upper(btrim(coalesce(p_tipo, '')));
  p_status := upper(btrim(coalesce(p_status, '')));
  select * into v_emissao from f.documento_fiscal_emissao
   where documento_fiscal_id = p_documento_fiscal_id for update;
  if v_emissao.documento_fiscal_id is null then raise exception 'Emissao nao encontrada.'; end if;
  if v_emissao.ambiente <> 'HOMOLOGACAO' then raise exception 'Ciclo de vida liberado somente em HOMOLOGACAO.'; end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, protocolo,
    status, resposta, destinatarios, sequencia, referencia_externa
  ) values (
    p_documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, p_tipo,
    nullif(btrim(p_justificativa), ''), nullif(btrim(p_protocolo), ''), p_status,
    coalesce(p_resposta, '{}'::jsonb), p_destinatarios, p_sequencia, v_emissao.referencia_externa
  ) returning id into v_id;

  if p_tipo = 'CANCELAMENTO' and p_status = 'AUTORIZADA' then
    update f.documento_fiscal_emissao set status = 'CANCELADA', protocolo = coalesce(nullif(p_protocolo, ''), protocolo),
      resposta = coalesce(p_resposta, resposta), updated_at = now()
      where documento_fiscal_id = p_documento_fiscal_id;
    update f.documento_fiscal set nfe_status = 'CANCELADA', updated_at = now()
      where id = p_documento_fiscal_id;
    update f.solicitacao_faturamento set status = 'CANCELADA', updated_at = now()
      where id = v_emissao.solicitacao_id;
  end if;
  return v_id;
end;
$function$;

create or replace function f.fn_nfe_lacunas()
returns table (
  serie integer, numero_inicial integer, numero_final integer,
  detectada_em date, prazo_inutilizar date, alerta boolean
)
language sql security definer set search_path = pg_catalog set row_security = off stable
as $function$
  with scope as (
    select * from f.fn_operacao_assert_acesso()
  ), numeros as (
    select distinct d.serie::integer serie, d.numero::integer numero,
      coalesce(d.emissao_date, d.created_at::date) emissao
    from f.documento_fiscal d, scope s
    where d.tenant_id = s.tenant_id and d.empresa_id = s.empresa_id
      and d.modelo = '55' and d.serie ~ '^[0-9]+$' and d.numero ~ '^[0-9]+$'
      and d.deleted_at is null
  ), ordenados as (
    select n.*, lag(numero, 1, 0) over (partition by serie order by numero) anterior
    from numeros n
  )
  select o.serie, o.anterior + 1, o.numero - 1, o.emissao,
    (date_trunc('month', o.emissao)::date + interval '1 month 9 days')::date,
    current_date >= (date_trunc('month', o.emissao)::date + interval '1 month 4 days')::date
  from ordenados o
  where o.numero > o.anterior + 1
    and not exists (
      select 1 from f.nfe_inutilizacao ni, scope s
      where ni.tenant_id = s.tenant_id and ni.empresa_id = s.empresa_id
        and ni.serie = o.serie and ni.status = 'AUTORIZADA'
        and ni.numero_inicial <= o.anterior + 1 and ni.numero_final >= o.numero - 1
    )
  order by o.serie, o.anterior + 1;
$function$;

create or replace function f.fn_nfe_inutilizacao_validar(
  p_serie integer, p_numero_inicial integer, p_numero_final integer, p_justificativa text
)
returns jsonb language plpgsql security definer set search_path = pg_catalog set row_security = off stable
as $function$
declare v_scope record; v_cnpj text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if p_serie is null or p_serie not between 0 and 999 then raise exception 'Serie invalida.'; end if;
  if p_numero_inicial is null or p_numero_inicial <= 0 or p_numero_final < p_numero_inicial then raise exception 'Faixa de numeracao invalida.'; end if;
  if char_length(btrim(coalesce(p_justificativa, ''))) not between 15 and 255 then raise exception 'Justificativa deve ter entre 15 e 255 caracteres.'; end if;
  if exists (
    select 1 from f.documento_fiscal d
    where d.tenant_id = v_scope.tenant_id and d.empresa_id = v_scope.empresa_id
      and d.modelo = '55' and d.serie = p_serie::text and d.numero ~ '^[0-9]+$'
      and d.numero::integer between p_numero_inicial and p_numero_final and d.deleted_at is null
  ) then raise exception 'Faixa contem numero ja registrado (autorizado, cancelado, denegado ou rejeitado).'; end if;
  select e.cnpj into v_cnpj from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id;
  if v_cnpj !~ '^[0-9]{14}$' then raise exception 'Empresa sem CNPJ valido para inutilizacao.'; end if;
  return jsonb_build_object('tenant_id', v_scope.tenant_id, 'empresa_id', v_scope.empresa_id,
    'cnpj', v_cnpj, 'serie', p_serie, 'numero_inicial', p_numero_inicial,
    'numero_final', p_numero_final, 'justificativa', btrim(p_justificativa), 'ambiente', 'HOMOLOGACAO');
end;
$function$;

create or replace function f.fn_nfe_inutilizacao_registrar(
  p_tenant_id uuid, p_empresa_id uuid, p_serie integer, p_numero_inicial integer,
  p_numero_final integer, p_justificativa text, p_status text,
  p_protocolo text default null, p_resposta jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_id uuid;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode registrar inutilizacao.';
  end if;
  insert into f.nfe_inutilizacao (tenant_id, empresa_id, serie, numero_inicial, numero_final,
    justificativa, status, protocolo, resposta)
  values (p_tenant_id, p_empresa_id, p_serie, p_numero_inicial, p_numero_final,
    btrim(p_justificativa), upper(p_status), nullif(btrim(p_protocolo), ''), coalesce(p_resposta, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function f.fn_empresa_certificado_validade_atualizar(p_empresa_id uuid, p_validade date)
returns void language plpgsql security definer set search_path = pg_catalog set row_security = off
as $function$
declare v_scope record;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if p_empresa_id is distinct from v_scope.empresa_id then raise exception 'Empresa fora do contexto ativo.'; end if;
  if p_validade is null then raise exception 'Validade do certificado ausente.'; end if;
  update c.empresa_fiscal set certificado_validade_em = p_validade, updated_at = now(), updated_by = v_scope.usuario_id
   where empresa_id = p_empresa_id and deleted_at is null;
  if not found then raise exception 'Cadastro fiscal da empresa nao encontrado.'; end if;
end;
$function$;

create or replace function f.fn_nfe_excecoes_mensais(p_competencia date default current_date)
returns jsonb language plpgsql security definer set search_path = pg_catalog set row_security = off stable
as $function$
declare v_scope record; v_inicio date; v_fim date; v_result jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  v_inicio := date_trunc('month', coalesce(p_competencia, current_date))::date;
  v_fim := (v_inicio + interval '1 month')::date;

  with docs as (
    select d.* from f.documento_fiscal d
    where d.tenant_id = v_scope.tenant_id and d.empresa_id = v_scope.empresa_id
      and coalesce(d.emissao_date, d.created_at::date) >= v_inicio
      and coalesce(d.emissao_date, d.created_at::date) < v_fim and d.deleted_at is null
  ), duplicados as (
    select 'DUPLICIDADE' tipo, min(d.id::text) documento_id,
      format('Serie %s numero %s aparece %s vezes.', d.serie, d.numero, count(*)) detalhe
    from docs d where d.serie is not null and d.numero is not null
    group by d.serie, d.numero having count(*) > 1
  ), canceladas as (
    select 'CANCELADA_SUBSTITUIDA', d.id::text,
      format('NF-e %s/%s esta %s.', coalesce(d.numero, '?'), coalesce(d.serie, '?'), d.nfe_status)
    from docs d where d.nfe_status in ('CANCELADA', 'SUBSTITUIDA')
  ), raros as (
    select 'CFOP_CST_RARO', i.documento_fiscal_id::text,
      format('Combinacao rara CFOP %s / ICMS %s.', coalesce(i.cfop, '?'), coalesce(i.cst_icms, i.csosn, '?'))
    from f.documento_fiscal_item i join docs d on d.id = i.documento_fiscal_id
    where i.deleted_at is null and (i.cfop is not null or i.cst_icms is not null or i.csosn is not null)
      and (select count(*) from f.documento_fiscal_item x join docs dx on dx.id=x.documento_fiscal_id
           where x.deleted_at is null and x.cfop is not distinct from i.cfop
             and coalesce(x.cst_icms,x.csosn) is not distinct from coalesce(i.cst_icms,i.csosn)) <= 1
  ), ipi as (
    select distinct 'IPI_DIVERGENTE', i.documento_fiscal_id::text,
      format('NCM %s usa CST de IPI divergente no mes.', i.ncm)
    from f.documento_fiscal_item i join docs d on d.id=i.documento_fiscal_id
    where i.deleted_at is null and nullif(i.ncm,'') is not null
      and (select count(distinct x.cst_ipi) from f.documento_fiscal_item x join docs dx on dx.id=x.documento_fiscal_id
           where x.deleted_at is null and x.ncm=i.ncm and x.cst_ipi is not null) > 1
  ), reducao as (
    select distinct 'REDUCAO_APLICADA', i.documento_fiscal_id::text,
      format('Reducao de base de %s%% aplicada.', i.reducao_base_icms_percentual)
    from f.documento_fiscal_item i join docs d on d.id=i.documento_fiscal_id
    where i.deleted_at is null and coalesce(i.reducao_base_icms_percentual,0)>0
  ), remessas as (
    select 'REMESSA_ABERTA', r.operacao_remessa_id::text,
      format('Remessa %s aberta ha %s dias.', right(r.chave_remessa, 8), r.dias_decorridos)
    from f.v_remessas_abertas r
  ), uniao as (
    select * from duplicados union all select * from canceladas union all select * from raros
    union all select * from ipi union all select * from reducao union all select * from remessas
  )
  select jsonb_build_object('competencia', to_char(v_inicio,'YYYY-MM'), 'total', count(*),
    'itens', coalesce(jsonb_agg(jsonb_build_object('tipo',tipo,'documento_id',documento_id,'detalhe',detalhe) order by tipo,detalhe),'[]'::jsonb))
  into v_result from uniao;
  return v_result;
end;
$function$;

revoke all on function f.fn_nfe_ciclo_contexto(uuid) from public, anon;
revoke all on function f.fn_nfe_evento_registrar(uuid,text,text,text,text,jsonb,text[],integer) from public, anon, authenticated;
revoke all on function f.fn_nfe_lacunas() from public, anon;
revoke all on function f.fn_nfe_inutilizacao_validar(integer,integer,integer,text) from public, anon;
revoke all on function f.fn_nfe_inutilizacao_registrar(uuid,uuid,integer,integer,integer,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function f.fn_empresa_certificado_validade_atualizar(uuid,date) from public, anon;
revoke all on function f.fn_nfe_excecoes_mensais(date) from public, anon;
grant execute on function f.fn_nfe_ciclo_contexto(uuid) to authenticated, service_role;
grant execute on function f.fn_nfe_evento_registrar(uuid,text,text,text,text,jsonb,text[],integer) to service_role;
grant execute on function f.fn_nfe_lacunas() to authenticated, service_role;
grant execute on function f.fn_nfe_inutilizacao_validar(integer,integer,integer,text) to authenticated, service_role;
grant execute on function f.fn_nfe_inutilizacao_registrar(uuid,uuid,integer,integer,integer,text,text,text,jsonb) to service_role;
grant execute on function f.fn_empresa_certificado_validade_atualizar(uuid,date) to authenticated, service_role;
grant execute on function f.fn_nfe_excecoes_mensais(date) to authenticated, service_role;

commit;
