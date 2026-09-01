begin;

-- Mantém a assinatura anterior intacta e acrescenta o responsável apenas ao
-- fluxo que cria/atualiza a OS a partir do fechamento do orçamento.
create or replace function m.fn_orcamento_atualizar_status_com_responsavel(
  p_orcamento_id uuid,
  p_status text,
  p_followup text default null,
  p_valor_fechado numeric default null,
  p_abrir_os boolean default false,
  p_importar_itens_os boolean default false,
  p_responsavel_aprovacao_id uuid default null
)
returns table (
  orcamento_id uuid,
  os_id integer,
  numero_os text,
  valor_orcado numeric,
  valor_fechado numeric,
  desconto_valor numeric,
  itens_importados boolean
)
language plpgsql
as $$
declare
  v_result record;
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Contexto tenant/empresa nao encontrado para atualizar status do orcamento.';
  end if;

  select *
    into v_result
  from m.fn_orcamento_atualizar_status(
    p_orcamento_id,
    p_status,
    p_followup,
    p_valor_fechado,
    p_abrir_os,
    p_importar_itens_os
  );

  if coalesce(p_abrir_os, false)
     and p_responsavel_aprovacao_id is not null
     and v_result.os_id is not null then
    update public.ordens_servico
       set responsavel_aprovacao_id = p_responsavel_aprovacao_id,
           atualizado_em = now()
     where id = v_result.os_id
       and tenant_id = v_tenant_id
       and empresa_id = v_empresa_id;
  end if;

  orcamento_id := v_result.orcamento_id;
  os_id := v_result.os_id;
  numero_os := v_result.numero_os;
  valor_orcado := v_result.valor_orcado;
  valor_fechado := v_result.valor_fechado;
  desconto_valor := v_result.desconto_valor;
  itens_importados := v_result.itens_importados;
  return next;
end;
$$;

grant all on function m.fn_orcamento_atualizar_status_com_responsavel(uuid, text, text, numeric, boolean, boolean, uuid) to authenticated;
grant all on function m.fn_orcamento_atualizar_status_com_responsavel(uuid, text, text, numeric, boolean, boolean, uuid) to service_role;

-- Correção do histórico: quando quem abriu a OS ainda existe no Auth pelo
-- mesmo e-mail gravado em criado_por, essa pessoa passa a ser a responsável.
update public.ordens_servico as os
   set responsavel_aprovacao_id = usuario.id,
       atualizado_em = now()
  from auth.users as usuario
 where os.responsavel_aprovacao_id is null
   and nullif(lower(trim(coalesce(os.criado_por, ''))), '') = lower(trim(usuario.email));

commit;
