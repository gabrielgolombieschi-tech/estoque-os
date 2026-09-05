begin;

create or replace function f.fn_operacao_vincular_documento(
  p_operacao_id uuid,
  p_etapa smallint,
  p_documento_fiscal_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_scope record;
  v_op f.operacao_fiscal%rowtype;
  v_documento f.documento_fiscal%rowtype;
  v_referencia text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select * into v_op
  from f.operacao_fiscal o
  where o.tenant_id = v_scope.tenant_id
    and o.empresa_id = v_scope.empresa_id
    and o.id = p_operacao_id
    and o.deleted_at is null
  for update;
  if v_op.id is null then raise exception 'Operacao fiscal nao encontrada.'; end if;

  select * into v_documento
  from f.documento_fiscal d
  where d.tenant_id = v_scope.tenant_id
    and d.empresa_id = v_scope.empresa_id
    and d.id = p_documento_fiscal_id
    and d.deleted_at is null
  for update;
  if v_documento.id is null then raise exception 'Documento fiscal nao encontrado nesta empresa.'; end if;

  if p_etapa = 1 then
    if v_op.documento_primeira_nota_id is not null
       and v_op.documento_primeira_nota_id <> p_documento_fiscal_id then
      raise exception 'A primeira etapa ja esta vinculada a outro documento fiscal.';
    end if;
    v_referencia := v_op.nfe_referenciada;
    update f.operacao_fiscal
       set documento_primeira_nota_id = p_documento_fiscal_id, updated_at = now()
     where id = v_op.id;
  elsif p_etapa = 2 and v_op.tipo = 'VENDA_ORDEM' then
    if v_op.chave_primeira_nota is null then
      raise exception 'Segunda NF-e bloqueada: a primeira ainda nao possui chave autorizada.';
    end if;
    if v_op.documento_segunda_nota_id is not null
       and v_op.documento_segunda_nota_id <> p_documento_fiscal_id then
      raise exception 'A segunda etapa ja esta vinculada a outro documento fiscal.';
    end if;
    v_referencia := v_op.chave_primeira_nota;
    update f.operacao_fiscal
       set documento_segunda_nota_id = p_documento_fiscal_id, updated_at = now()
     where id = v_op.id;
  else
    raise exception 'Etapa invalida para vinculacao do documento fiscal.';
  end if;

  if v_op.tipo in ('DEVOLUCAO_COMPRA', 'RETORNO', 'ESTORNO') and v_referencia is null then
    raise exception 'Esta operacao exige NF-e referenciada antes de vincular o documento.';
  end if;

  update f.documento_fiscal
     set nfe_referenciada = v_referencia,
         updated_at = now(),
         updated_by = v_scope.usuario_id
   where tenant_id = v_scope.tenant_id
     and empresa_id = v_scope.empresa_id
     and id = p_documento_fiscal_id;
end;
$function$;

comment on function f.fn_operacao_vincular_documento(uuid, smallint, uuid) is
  'Vincula uma etapa fiscal a um documento ja materializado e copia a chave referenciada ao campo canonico do documento.';

revoke all on function f.fn_operacao_vincular_documento(uuid, smallint, uuid) from public, anon;
grant execute on function f.fn_operacao_vincular_documento(uuid, smallint, uuid) to authenticated, service_role;

commit;
