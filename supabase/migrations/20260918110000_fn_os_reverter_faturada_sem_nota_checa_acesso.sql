-- f.fn_os_reverter_faturada_sem_nota (SECURITY DEFINER, RLS desligada) recebia tenant e empresa por
-- parametro e escrevia em public.ordens_servico sem conferir quem chamava: auth.uid() so aparecia como
-- autor do evento, depois do update. Levantamento de 18/09/2026 (docs/faturamento/seguranca-grants-2026-09-18.md).
-- Agora a primeira instrucao e a checagem de acesso: quem nao e o backend fiscal (service_role, como a
-- Edge que finaliza o cancelamento e dispara o gatilho trg_documento_fiscal__reverter_os_faturada, ou
-- sessao postgres sem JWT) passa por f.fn_operacao_assert_acesso() e so pode informar o tenant e a
-- empresa da propria sessao. Teste: supabase/tests/os_reverter_faturada_acesso.sql.
-- Reversao: definicao anterior (20260906xxxxxx / online ate 18/09), sem o bloco de acesso.

create or replace function f.fn_os_reverter_faturada_sem_nota(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_status text;
  v_scope record;
begin
  -- Acesso antes de qualquer leitura ou escrita. Backend fiscal = service_role (Edge) ou sessao postgres
  -- sem JWT (migration, SQL editor, gatilho disparado por elas). Qualquer sessao com usuario (JWT) passa
  -- por f.fn_operacao_assert_acesso() e so pode informar o tenant e a empresa da propria sessao.
  if not (coalesce(auth.jwt()->>'role', '') = 'service_role' or (auth.uid() is null and session_user = 'postgres')) then
    select * into v_scope from f.fn_operacao_assert_acesso();
    if p_tenant_id is distinct from v_scope.tenant_id or p_empresa_id is distinct from v_scope.empresa_id then
      raise exception using errcode = '42501', message = 'Tenant e empresa informados nao pertencem a sessao do usuario.';
    end if;
  end if;

  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    return false;
  end if;

  select os.status_fluxo into v_status
  from public.ordens_servico os
  where os.id = p_os_id and os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id
  for update;

  if not found or upper(coalesce(v_status, '')) <> 'FATURADA' then
    return false;
  end if;

  -- A OS precisa ter tido nota neste sistema. Sem nenhum documento fiscal vinculado
  -- ela foi faturada por outro caminho — 152 das 226 OS faturadas hoje sao do legado —
  -- e nao e assunto desta funcao. A guarda fica aqui, e nao so em quem chama, para que
  -- uma chamada direta tambem nao consiga desfazer o historico do legado.
  if not exists (
    select 1
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id and df.os_id_import = p_os_id
      and df.operacao = 'SAIDA' and df.deleted_at is null
  ) then
    return false;
  end if;

  -- Sobrou nota valida sustentando o faturamento: nada a fazer.
  if exists (
    select 1
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id and df.os_id_import = p_os_id
      and df.operacao = 'SAIDA' and df.deleted_at is null
      and ((upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
        or (upper(coalesce(df.modelo, '')) <> 'NFSE' and (nullif(upper(btrim(coalesce(df.nfe_status, ''))), '') is null or upper(coalesce(df.nfe_status, '')) = 'EMITIDA')))
  ) then
    return false;
  end if;

  update public.ordens_servico
     set status_fluxo = 'concluida',
         status = 'concluida',
         faturado_em = null,
         faturada_presumida_legado = false,
         atualizado_em = now()
   where id = p_os_id and tenant_id = p_tenant_id and empresa_id = p_empresa_id;

  insert into public.ordens_servico_fluxo_eventos
    (tenant_id, empresa_id, os_id, evento, status_origem, status_destino, motivo, realizado_por)
  values (p_tenant_id, p_empresa_id, p_os_id, 'reverter_faturada', 'faturada', 'concluida',
    'Nota fiscal cancelada e nenhuma outra nota emitida na OS; volta para concluida.', auth.uid());

  return true;
end;
$function$;

revoke all on function f.fn_os_reverter_faturada_sem_nota(uuid, uuid, integer) from public, anon;
grant execute on function f.fn_os_reverter_faturada_sem_nota(uuid, uuid, integer) to authenticated, service_role;

do $assert$
begin
  if pg_get_functiondef('f.fn_os_reverter_faturada_sem_nota(uuid, uuid, integer)'::regprocedure)
       not like '%fn_operacao_assert_acesso()%' then
    raise exception 'fn_os_reverter_faturada_sem_nota sem a checagem de acesso';
  end if;
end;
$assert$;
