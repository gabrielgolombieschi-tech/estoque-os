-- Lista de e-mails do cliente para a entrega da NF-e (XML + DANFE).
--
-- Pedido do Gabriel em 18/09/2026, na entrega da NF-e 2/33 da OV-SEG-00004-026: no campo
-- "Entregar ao cliente", apertar Enter deve abrir a lista de e-mails daquele cliente para
-- escolher; e todo e-mail novo digitado ali e enviado pelo botao entra na lista.
--
-- A lista ja existe: public.cliente_contatos (nome, setor, e-mail, telefone, vezes_usado,
-- ultimo_uso_em), usada pelo orcamento. Aqui ela ganha duas RPCs proprias do faturamento,
-- porque quem fatura nem sempre tem acesso comercial (a RLS da tabela exige
-- c.has_comercial_access) — as funcoes sao SECURITY DEFINER e conferem acesso financeiro OU
-- comercial na empresa ativa.
--
--   public.clientes_emails_nfe(cliente)            -> lista para o campo
--   public.clientes_registrar_emails_nfe(cliente, emails) -> marca o uso e cadastra o que faltava
--
-- O indice unico por (tenant, empresa, cliente, e-mail em minusculas) e novo: hoje nao ha
-- duplicidade, e ele e o que deixa o upsert seguro.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create unique index if not exists cliente_contatos_email_unico
  on public.cliente_contatos (tenant_id, empresa_id, cliente_id, lower(btrim(email)))
  where email is not null and btrim(email) <> '';

comment on index public.cliente_contatos_email_unico is
  'Um contato por e-mail em cada cliente: base do upsert de clientes_registrar_emails_nfe (20260919040000).';

-- Acesso: empresa ativa do usuario e o cliente precisam bater, e a pessoa precisa de acesso
-- financeiro ou comercial. Devolve tenant/empresa ja conferidos.
create or replace function public.clientes_emails_nfe_assert_acesso(p_cliente_id integer)
returns table (tenant_id uuid, empresa_id uuid)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
begin
  if p_cliente_id is null or p_cliente_id <= 0 then
    raise exception using errcode = '22023', message = 'Informe o cliente.';
  end if;
  -- Mesma disciplina do orcamento (public.app_orcamento_assert_acesso): sem atalho para
  -- postgres nem service_role, porque quem chama e sempre a tela, com a sessao da pessoa.
  if auth.uid() is null or v_tenant is null or v_empresa is null
     or not public.has_active_empresa_access(v_tenant, v_empresa) then
    raise exception using errcode = '42501', message = 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;
  if not (f.has_finance_access(v_tenant, v_empresa) or c.has_comercial_access(v_tenant, v_empresa)) then
    raise exception using errcode = '42501', message = 'Sem permissao para ver os contatos deste cliente.';
  end if;
  if not exists (
    select 1 from public.clientes cl
    where cl.id = p_cliente_id and cl.tenant_id = v_tenant and cl.empresa_id = v_empresa
  ) then
    raise exception using errcode = 'P0002', message = 'Cliente nao encontrado nesta empresa.';
  end if;
  tenant_id := v_tenant;
  empresa_id := v_empresa;
  return next;
end;
$$;

comment on function public.clientes_emails_nfe_assert_acesso(integer) is
  'Confere empresa ativa e acesso financeiro ou comercial ao cliente; usada pelas RPCs de e-mail da NF-e (20260919040000).';

revoke all on function public.clientes_emails_nfe_assert_acesso(integer) from public, anon;
grant execute on function public.clientes_emails_nfe_assert_acesso(integer) to authenticated, service_role;

-- Lista do campo "Entregar ao cliente": contatos ativos com e-mail, na ordem em que a pessoa
-- costuma escolher (o principal, depois o mais recente, depois o mais usado, depois alfabetica).
create or replace function public.clientes_emails_nfe(p_cliente_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
begin
  select * into v_scope from public.clientes_emails_nfe_assert_acesso(p_cliente_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', contato.id,
      'email', contato.email,
      'nome', contato.nome,
      'setor', contato.setor,
      'principal', contato.principal,
      'vezes_usado', contato.vezes_usado,
      'ultimo_uso_em', contato.ultimo_uso_em
    ))
    from (
      select ct.id, btrim(ct.email) as email, ct.nome, ct.setor, ct.principal, ct.vezes_usado, ct.ultimo_uso_em
      from public.cliente_contatos ct
      where ct.tenant_id = v_scope.tenant_id
        and ct.empresa_id = v_scope.empresa_id
        and ct.cliente_id = p_cliente_id
        and ct.ativo is true
        and ct.email is not null
        and btrim(ct.email) <> ''
      order by ct.principal desc nulls last,
               ct.ultimo_uso_em desc nulls last,
               ct.vezes_usado desc nulls last,
               ct.nome
      limit 50
    ) as contato
  ), '[]'::jsonb);
end;
$$;

comment on function public.clientes_emails_nfe(integer) is
  'E-mails do cliente para a entrega da NF-e, na ordem de uso (20260919040000).';

revoke all on function public.clientes_emails_nfe(integer) from public, anon;
grant execute on function public.clientes_emails_nfe(integer) to authenticated, service_role;

-- Depois do envio: marca o uso de quem ja estava na lista e cadastra os e-mails novos.
-- O nome do contato novo e a parte antes do @ em maiusculas, e o setor fica NF-E — quem
-- cuida do cadastro pode renomear depois pela tela do cliente. Devolve a lista atualizada.
create or replace function public.clientes_registrar_emails_nfe(p_cliente_id integer, p_emails text[])
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_email text;
  v_limpo text;
begin
  select * into v_scope from public.clientes_emails_nfe_assert_acesso(p_cliente_id);

  foreach v_email in array coalesce(p_emails, array[]::text[]) loop
    v_limpo := lower(btrim(coalesce(v_email, '')));
    -- E-mail invalido nao entra na lista; o envio em si e validado pelo provedor.
    continue when v_limpo !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or length(v_limpo) > 254;

    insert into public.cliente_contatos as ct (
      tenant_id, empresa_id, cliente_id, nome, setor, email, ativo, principal, vezes_usado, ultimo_uso_em
    ) values (
      v_scope.tenant_id, v_scope.empresa_id, p_cliente_id,
      upper(split_part(v_limpo, '@', 1)), 'NF-E', v_limpo, true, false, 1, now()
    )
    -- O predicado repete o do indice parcial: sem ele o Postgres nao reconhece o alvo.
    on conflict (tenant_id, empresa_id, cliente_id, lower(btrim(email)))
      where email is not null and btrim(email) <> ''
    do update
      set vezes_usado = coalesce(ct.vezes_usado, 0) + 1,
          ultimo_uso_em = now(),
          ativo = true,
          updated_at = now();
  end loop;

  return public.clientes_emails_nfe(p_cliente_id);
end;
$$;

comment on function public.clientes_registrar_emails_nfe(integer, text[]) is
  'Marca o uso dos e-mails da entrega da NF-e e cadastra os que ainda nao estavam na lista do cliente (20260919040000).';

revoke all on function public.clientes_registrar_emails_nfe(integer, text[]) from public, anon;
grant execute on function public.clientes_registrar_emails_nfe(integer, text[]) to authenticated, service_role;

do $assertions$
begin
  if not exists (select 1 from pg_class where relname = 'cliente_contatos_email_unico') then
    raise exception 'indice unico de e-mail do contato nao criado';
  end if;
  if exists (
    select 1 from (
      select tenant_id, empresa_id, cliente_id, lower(btrim(email)) as e
      from public.cliente_contatos
      where email is not null and btrim(email) <> ''
      group by 1, 2, 3, 4 having count(*) > 1
    ) x
  ) then
    raise exception 'ha e-mail repetido no mesmo cliente';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
