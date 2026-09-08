-- Quem fatura a OS tambem fecha a OS.
--
-- Decisao de Gabriel em 08/09/2026, na primeira NF-e real da OS 319: depois de
-- enviar XML + DANFE ao cliente, a tela de faturar pergunta se conclui a OS e a
-- marca como faturada num passo so. Isso esbarrava em duas regras antigas:
--   - os_concluir aceitava so ADMIN, DIRETOR e COORDENACAO;
--   - os_faturar aceitava SO FINANCEIRO — nem ADMIN nem DIRETOR passavam.
-- Na pratica ninguem conseguia os dois passos: Vanessa (FATURAMENTO) nao fazia
-- nenhum, Larissa (ADMIN) concluia mas nao faturava.
--
-- Agora: os_concluir aceita tambem FINANCEIRO e FATURAMENTO; os_faturar aceita
-- FINANCEIRO, FATURAMENTO, ADMIN e DIRETOR. As demais regras (OS em andamento,
-- sem horas pendentes, nota emitida vinculada e saldo zero) ficam iguais.

create or replace function public.os_concluir(p_os_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'auth'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_origem text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  select ue.papel into v_papel
  from a.usuario u join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = v_auth_uid and u.ativo and u.deleted_at is null
    and ue.empresa_id = v_empresa_id and ue.ativo and ue.deleted_at is null
  limit 1;
  -- FINANCEIRO e FATURAMENTO entram porque concluem a OS ao faturar (08/09/2026).
  if upper(coalesce(v_papel, '')) not in ('ADMIN', 'DIRETOR', 'COORDENACAO', 'FINANCEIRO', 'FATURAMENTO') then
    raise exception 'Somente coordenação, financeiro, faturamento, admin ou diretor podem concluir a OS.';
  end if;
  select status_fluxo into v_origem
  from public.ordens_servico
  where id = p_os_id and tenant_id = v_tenant_id and empresa_id = v_empresa_id
  for update;
  if not found then raise exception 'OS não encontrada na empresa atual.'; end if;
  if v_origem not in ('em_andamento', 'em_andamento_garantia') then
    raise exception 'A OS não está em andamento para ser concluída.';
  end if;
  if exists (
    select 1 from public.apontamentos_horas ah
    where ah.os_id = p_os_id and ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id
      and ah.status_aprovacao = 'pendente'
  ) then
    raise exception 'A OS possui horas pendentes de aprovação e não pode ser concluída.';
  end if;

  update public.ordens_servico
  set status_fluxo = case when v_origem = 'em_andamento_garantia' then 'concluida_garantia' else 'concluida' end,
      status = 'concluida', data_conclusao = now(), atualizado_em = now()
  where id = p_os_id and tenant_id = v_tenant_id and empresa_id = v_empresa_id;
  if v_origem = 'em_andamento' then
    update public.os_gestao_itens
    set progresso_percent = 100, data_prevista = coalesce(data_prevista, current_date), updated_at = now()
    where os_id = p_os_id and tenant_id = v_tenant_id and empresa_id = v_empresa_id and habilitado
      and item_tipo in ('projeto'::public.os_gestao_tipo, 'execucao'::public.os_gestao_tipo)
      and area in ('eletrico'::public.os_gestao_area, 'seguranca'::public.os_gestao_area, 'mecanico'::public.os_gestao_area, 'software'::public.os_gestao_area)
      and coalesce(progresso_percent, 0) < 100;
  end if;
  insert into public.ordens_servico_fluxo_eventos (tenant_id, empresa_id, os_id, evento, status_origem, status_destino, realizado_por)
  values (v_tenant_id, v_empresa_id, p_os_id, case when v_origem = 'em_andamento_garantia' then 'concluir_garantia' else 'concluir' end, v_origem,
          case when v_origem = 'em_andamento_garantia' then 'concluida_garantia' else 'concluida' end, v_auth_uid);
  return jsonb_build_object('sucesso', true);
end;
$function$;

create or replace function public.os_faturar(p_os_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'f', 'auth'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid(); v_tenant_id uuid := public.current_tenant_id(); v_empresa_id uuid := public.current_empresa_id(); v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  -- FATURAMENTO, ADMIN e DIRETOR entram junto com FINANCEIRO (08/09/2026).
  if upper(coalesce(v_papel, '')) not in ('FINANCEIRO', 'FATURAMENTO', 'ADMIN', 'DIRETOR') then raise exception 'Somente financeiro, faturamento, admin ou diretor podem faturar a OS.'; end if;
  if not exists (select 1 from public.ordens_servico where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and status_fluxo='concluida' for update) then raise exception 'A OS precisa estar concluída para ser faturada.'; end if;
  -- Nota emitida ou importada vinculada E saldo zero (regra unica, 05/09/2026).
  if not f.fn_os_pronta_para_faturada(v_tenant_id, v_empresa_id, p_os_id) then
    raise exception 'A OS só pode ser marcada como faturada com NF-e ou NFS-e emitida vinculada e saldo a faturar zerado.';
  end if;
  update public.ordens_servico set status_fluxo='faturada', status='concluida', faturado_em=now(), faturada_presumida_legado=false, atualizado_em=now() where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id;
  insert into public.ordens_servico_fluxo_eventos (tenant_id,empresa_id,os_id,evento,status_origem,status_destino,realizado_por) values (v_tenant_id,v_empresa_id,p_os_id,'faturar','concluida','faturada',v_auth_uid);
  return jsonb_build_object('sucesso', true);
end;
$function$;
