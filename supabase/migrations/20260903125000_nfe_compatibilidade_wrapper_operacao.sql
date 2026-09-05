begin;

-- Mantem a composicao inicial restrita a HOMOLOGACAO, sem exigir contexto JWT
-- de chamadas internas/service_role e dos testes executados como postgres.
-- Chamadas authenticated continuam obrigadas ao tenant/empresa da sessao e ao
-- acesso financeiro.
create or replace function f.fn_faturar_documento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS',
  p_itens_quantidades jsonb default null,
  p_linhas_livres jsonb default null
)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  referencia_externa text,
  status text,
  criado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
begin
  if upper(btrim(coalesce(p_ambiente, ''))) <> 'HOMOLOGACAO' then
    raise exception using
      errcode = '42501',
      message = 'A composicao inicial cria somente rascunho em HOMOLOGACAO; PRODUCAO exige promocao fiscal auditada.';
  end if;

  if session_user <> 'postgres'
     and v_role <> 'service_role'
     and (
       public.current_tenant_id() is distinct from p_tenant_id
       or public.current_empresa_id() is distinct from p_empresa_id
       or not f.has_finance_access()
     ) then
    raise exception using errcode = '42501', message = 'Sem permissao para faturar nesta empresa.';
  end if;

  return query
  select x.documento_fiscal_id, x.solicitacao_id, x.referencia_externa, x.status, x.criado
  from f.fn_faturar_documento_impl(
    p_tenant_id, p_empresa_id, p_ov_id, p_os_item_ids,
    p_documento_fiscal_id, 'HOMOLOGACAO', p_natureza_operacao,
    p_itens_quantidades, p_linhas_livres
  ) x;
end;
$function$;

comment on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb) is
  'Wrapper SECURITY DEFINER cria somente HOMOLOGACAO; authenticated respeita o contexto e chamadas internas/service_role conservam compatibilidade.';
revoke all on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb)
  from public, anon;
grant execute on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text, jsonb, jsonb)
  to authenticated, service_role;

-- O vinculo de operacoes nao-faturamento precisa copiar a chave referenciada
-- para um rascunho HOM intocado. A excecao abaixo e estreita: somente os tres
-- campos escritos por fn_operacao_vincular_documento, com relacao ja gravada,
-- chave identica e nenhuma tentativa/PRODUCAO. Todo o restante segue bloqueado.
create or replace function f.fn_nfe_bloquear_documento_dml_direto()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_vinculado boolean := false;
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
begin
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op <> 'INSERT' then
    select exists (
      select 1
      from f.documento_fiscal_emissao dfe
      where dfe.tenant_id = old.tenant_id
        and dfe.empresa_id = old.empresa_id
        and dfe.documento_fiscal_id = old.id
    ) into v_vinculado;

    if v_vinculado then
      -- Descarte autenticado de HOM RASCUNHO nunca tentada.
      if tg_op = 'UPDATE'
         and old.nfe_status = 'RASCUNHO'
         and new.nfe_status = 'CANCELADA'
         and (to_jsonb(new) - array['nfe_status','updated_at']::text[])
             is not distinct from
             (to_jsonb(old) - array['nfe_status','updated_at']::text[])
         and exists (
           select 1
           from f.documento_fiscal_emissao hom
           where hom.tenant_id = old.tenant_id
             and hom.empresa_id = old.empresa_id
             and hom.documento_fiscal_id = old.id
             and hom.ambiente = 'HOMOLOGACAO'
             and hom.status = 'CANCELADA'
             and hom.tentativa_count = 0
             and hom.payload_enviado is null
             and hom.enviado_em is null
             and hom.ultima_tentativa_em is null
         )
         and not exists (
           select 1
           from f.documento_fiscal_emissao prod
           where prod.tenant_id = old.tenant_id
             and prod.empresa_id = old.empresa_id
             and prod.solicitacao_id = (
               select hom.solicitacao_id
               from f.documento_fiscal_emissao hom
               where hom.tenant_id = old.tenant_id
                 and hom.empresa_id = old.empresa_id
                 and hom.documento_fiscal_id = old.id
                 and hom.ambiente = 'HOMOLOGACAO'
               limit 1
             )
             and prod.ambiente = 'PRODUCAO'
         ) then
        return new;
      end if;

      -- Vinculo de operacao fiscal em rascunho, anterior a qualquer claim.
      if tg_op = 'UPDATE'
         and (to_jsonb(new) - array['nfe_referenciada','updated_at','updated_by']::text[])
             is not distinct from
             (to_jsonb(old) - array['nfe_referenciada','updated_at','updated_by']::text[])
         and exists (
           select 1
           from f.documento_fiscal_emissao hom
           where hom.tenant_id = old.tenant_id
             and hom.empresa_id = old.empresa_id
             and hom.documento_fiscal_id = old.id
             and hom.ambiente = 'HOMOLOGACAO'
             and hom.status = 'RASCUNHO'
             and hom.tentativa_count = 0
             and hom.payload_enviado is null
             and hom.enviado_em is null
             and hom.ultima_tentativa_em is null
         )
         and not exists (
           select 1
           from f.documento_fiscal_emissao prod
           where prod.tenant_id = old.tenant_id
             and prod.empresa_id = old.empresa_id
             and prod.solicitacao_id = (
               select hom.solicitacao_id
               from f.documento_fiscal_emissao hom
               where hom.tenant_id = old.tenant_id
                 and hom.empresa_id = old.empresa_id
                 and hom.documento_fiscal_id = old.id
                 and hom.ambiente = 'HOMOLOGACAO'
               limit 1
             )
             and prod.ambiente = 'PRODUCAO'
         )
         and exists (
           select 1
           from f.operacao_fiscal op
           where op.tenant_id = old.tenant_id
             and op.empresa_id = old.empresa_id
             and op.deleted_at is null
             and (
               (
                 op.documento_primeira_nota_id = old.id
                 and new.nfe_referenciada is not distinct from op.nfe_referenciada
               )
               or (
                 op.documento_segunda_nota_id = old.id
                 and new.nfe_referenciada is not distinct from op.chave_primeira_nota
               )
             )
         ) then
        return new;
      end if;

      raise exception using
        errcode = '42501',
        message = 'Documento fiscal gerenciado pelo pipeline de NF-e so pode ser alterado ou excluido por RPC fiscal.';
    end if;
  end if;

  if tg_op <> 'DELETE'
     and upper(btrim(coalesce(new.operacao, ''))) = 'SAIDA'
     and btrim(coalesce(new.modelo, '')) = '55'
     and upper(btrim(coalesce(new.nfe_status, ''))) = 'EMITIDA' then
    raise exception using
      errcode = '42501',
      message = 'NF-e de saida modelo 55 nao pode ser marcada EMITIDA diretamente; use o pipeline fiscal autorizado.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

comment on function f.fn_nfe_bloquear_documento_dml_direto() is
  'Bloqueia DML authenticated em NF-e gerenciada; permite somente descarte HOM intocado e vinculo referenciado exato de operacao antes de qualquer claim.';
revoke all on function f.fn_nfe_bloquear_documento_dml_direto()
  from public, anon, authenticated, service_role;

notify pgrst, 'reload schema';

commit;
