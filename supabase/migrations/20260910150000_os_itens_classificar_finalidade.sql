-- Classificar linha ja lancada como venda ou componente.
--
-- Gabriel em 10/09/2026, na OV-SEG-00006-026: o painel de faturamento recusou a unica
-- linha da venda com "1 linha(s) sem finalidade", e nao havia caminho nenhum para
-- resolver — so o "Adicionar" da tela da OV grava a classificacao
-- (public.add_ov_item_baixa_imediata), e ele so age na insercao. Linha lancada pela
-- Baixa de OS, pela tela da OS ou pelo app do celular entra por
-- public.add_os_item_baixa_imediata, que nao classifica, e ficava presa: a unica saida
-- era remover e lancar de novo, mexendo no estoque a toa.
--
-- Esta funcao e o caminho que faltava. Ela nao inventa a classificacao: quem decide e
-- quem fatura, na tela, linha a linha.
--
-- Duas recusas de proposito:
--   1. papel — mesma regua do botao Faturar (financeiro.gerenciar, que vira a
--      capability financeiro.write no app);
--   2. linha ja comprometida com uma solicitacao viva nao muda de lado, porque a
--      reserva de quantidade e a nota em curso partem da classificacao atual.

create or replace function public.set_os_itens_finalidade(
  p_os_id integer,
  p_classificacoes jsonb,
  p_empresa_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_os public.ordens_servico%rowtype;
  v_classificacao jsonb;
  v_linha_id integer;
  v_finalidade text;
  v_linha public.os_itens%rowtype;
  v_rotulo text;
  v_atualizadas integer := 0;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Nao autenticado.';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception using errcode = '22023', message = 'Tenant atual nao definido.';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception using errcode = '22023', message = 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;
  perform public.set_current_empresa(v_empresa);

  if not public.has_permission('financeiro.gerenciar') then
    raise exception using errcode = '42501', message = 'Sem permissao para classificar linhas de faturamento.';
  end if;

  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = v_tenant
    and os.empresa_id = v_empresa
    and os.id = p_os_id;
  if not found then
    raise exception using errcode = '22023', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;
  v_rotulo := coalesce(v_os.codigo, p_os_id::text);
  if lower(coalesce(v_os.status_fluxo, '')) = 'cancelada' then
    raise exception using errcode = '22023', message = format('%s esta cancelada; nao ha o que classificar.', v_rotulo);
  end if;

  if p_classificacoes is null
     or jsonb_typeof(p_classificacoes) <> 'array'
     or jsonb_array_length(p_classificacoes) = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos uma linha para classificar.';
  end if;

  for v_classificacao in select value from jsonb_array_elements(p_classificacoes) loop
    v_linha_id := nullif(btrim(coalesce(v_classificacao->>'os_item_id', '')), '')::integer;
    v_finalidade := nullif(btrim(lower(coalesce(v_classificacao->>'finalidade', ''))), '');

    if v_linha_id is null then
      raise exception using errcode = '22023', message = 'Cada classificacao precisa do os_item_id da linha.';
    end if;
    if v_finalidade is null or v_finalidade not in ('venda', 'componente') then
      raise exception using errcode = '22023',
        message = format('Linha %s: finalidade deve ser venda ou componente.', v_linha_id);
    end if;

    select oi.* into v_linha
    from public.os_itens oi
    where oi.tenant_id = v_tenant
      and oi.empresa_id = v_empresa
      and oi.os_id = p_os_id
      and oi.id = v_linha_id
    for update;
    if not found then
      raise exception using errcode = '22023',
        message = format('Linha %s nao pertence a %s.', v_linha_id, v_rotulo);
    end if;

    if exists (
      select 1
      from f.solicitacao_item si
      join f.solicitacao_faturamento sf on sf.id = si.solicitacao_id
      where si.tenant_id = v_tenant
        and si.empresa_id = v_empresa
        and si.origem_tipo in ('OS', 'OV')
        and si.origem_id = p_os_id::text
        and si.origem_item_id = v_linha_id::text
        and sf.status <> 'CANCELADA'
    ) then
      raise exception using errcode = '22023',
        message = format('Linha %s ja esta em uma solicitacao de faturamento; cancele a solicitacao antes de reclassificar.', v_linha_id);
    end if;

    if v_linha.finalidade is distinct from v_finalidade then
      update public.os_itens oi
      set finalidade = v_finalidade
      where oi.tenant_id = v_tenant
        and oi.empresa_id = v_empresa
        and oi.id = v_linha_id;
      v_atualizadas := v_atualizadas + 1;
    end if;
  end loop;

  return v_atualizadas;
end;
$function$;

comment on function public.set_os_itens_finalidade(integer, jsonb, uuid) is
  'Classifica linhas ja lancadas de uma OS/OV como venda ou componente. Recusa sem papel do faturamento e recusa linha presa a solicitacao nao cancelada.';

revoke all on function public.set_os_itens_finalidade(integer, jsonb, uuid) from public;
grant execute on function public.set_os_itens_finalidade(integer, jsonb, uuid) to authenticated, service_role;
