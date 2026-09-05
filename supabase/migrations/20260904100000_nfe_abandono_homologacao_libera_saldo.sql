-- Abandono auditado de emissao em HOMOLOGACAO, devolvendo o saldo da OV/OS.
--
-- PROBLEMA
-- Uma NF-e autorizada em homologacao nao tem existencia fiscal: tpAmb=2, base da
-- SEFAZ separada da de producao, numeracao independente, sem SPED/EFD, sem ICMS e
-- sem obrigacao acessoria. Nao ha o que regularizar junto ao fisco.
-- Mesmo assim ela mantinha a solicitacao em EMITIDA, e como
-- f.fn_os_itens_saldo_a_faturar so desconta reserva quando sf.status = 'CANCELADA',
-- a quantidade da OV ficava presa para sempre: o botao Faturar nunca reabilitava e
-- a OV nao fechava nem como faturada nem como pendente.
-- O estorno (f.fn_estorno_criar) nao resolve: ele grava em f.operacao_fiscal e
-- nunca toca em f.solicitacao_faturamento.status.
--
-- SOLUCAO
-- Separar a simulacao fiscal da reserva de negocio:
--   * a emissao PERMANECE AUTORIZADA -- e a verdade, ela esta autorizada na SEFAZ
--     de homologacao, e continuar exercitando o prazo de 24h e a rejeicao real
--     (f.testar cancelamento fora do prazo) e proposital;
--   * a solicitacao vai para CANCELADA, devolvendo o saldo da OV;
--   * o abandono fica registrado em f.documento_fiscal_evento.
--
-- PRODUCAO nunca entra por aqui: ha guarda na RPC e tambem na excecao do trigger.

begin;

-- 1. Excecao estreita no guard de material pos-claim -----------------------------
-- O guard barra qualquer UPDATE na solicitacao quando a emissao ja saiu do estado
-- de rascunho intocado, e dispara mesmo dentro de SECURITY DEFINER porque testa
-- auth.jwt()->>'role'. A excecao abaixo vale somente para a solicitacao que a RPC
-- de abandono marcou nesta transacao, e somente quando nao ha PRODUCAO viva.
create or replace function f.fn_nfe_bloquear_material_pos_claim()
 returns trigger
 language plpgsql
 set search_path to 'pg_catalog'
as $function$
declare
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
  v_old_solicitacao_id uuid;
  v_new_solicitacao_id uuid;
  v_old_tenant_id uuid;
  v_new_tenant_id uuid;
  v_old_empresa_id uuid;
  v_new_empresa_id uuid;
  v_alvo_abandono text;
  v_solicitacao_id uuid;
begin
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_table_name = 'solicitacao_faturamento' then
    if tg_op <> 'INSERT' then
      v_old_solicitacao_id := old.id;
      v_old_tenant_id := old.tenant_id;
      v_old_empresa_id := old.empresa_id;
    end if;
    if tg_op <> 'DELETE' then
      v_new_solicitacao_id := new.id;
      v_new_tenant_id := new.tenant_id;
      v_new_empresa_id := new.empresa_id;
    end if;
  else
    if tg_op <> 'INSERT' then
      v_old_solicitacao_id := old.solicitacao_id;
      v_old_tenant_id := old.tenant_id;
      v_old_empresa_id := old.empresa_id;
    end if;
    if tg_op <> 'DELETE' then
      v_new_solicitacao_id := new.solicitacao_id;
      v_new_tenant_id := new.tenant_id;
      v_new_empresa_id := new.empresa_id;
    end if;
  end if;

  -- Excecao auditada do abandono de homologacao.
  v_solicitacao_id := coalesce(v_new_solicitacao_id, v_old_solicitacao_id);
  v_alvo_abandono := nullif(current_setting('f.abandono_homologacao', true), '');
  if v_alvo_abandono is not null
     and v_solicitacao_id is not null
     and v_alvo_abandono = v_solicitacao_id::text
     and not exists (
       select 1
       from f.documento_fiscal_emissao prod
       where prod.solicitacao_id = v_solicitacao_id
         and prod.ambiente = 'PRODUCAO'
         and prod.status <> 'CANCELADA'
     )
  then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where (
      (dfe.tenant_id = v_old_tenant_id and dfe.empresa_id = v_old_empresa_id and dfe.solicitacao_id = v_old_solicitacao_id)
      or
      (dfe.tenant_id = v_new_tenant_id and dfe.empresa_id = v_new_empresa_id and dfe.solicitacao_id = v_new_solicitacao_id)
    )
      and (
        dfe.ambiente <> 'HOMOLOGACAO'
        or dfe.status <> 'RASCUNHO'
        or coalesce(dfe.tentativa_count, 0) > 0
        or dfe.payload_enviado is not null
        or dfe.enviado_em is not null
        or dfe.ultima_tentativa_em is not null
        or dfe.callback_recebido_em is not null
        or dfe.reconciliado_em is not null
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'Material fiscal congelado: abandone/cancele pelo fluxo auditado e crie nova solicitacao.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

-- 2. RPC de abandono -------------------------------------------------------------
create or replace function f.fn_solicitacao_nfe_abandonar_homologacao(
  p_solicitacao_id uuid,
  p_motivo text
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog'
 set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_eventos integer := 0;
  v_origem record;
begin
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de NF-e nao encontrada.';
  end if;

  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para abandonar esta solicitacao.';
  end if;

  if char_length(v_motivo) < 15 or char_length(v_motivo) > 255 then
    raise exception using errcode = '22023', message = 'O motivo deve ter entre 15 e 255 caracteres.';
  end if;

  -- Guarda dura: producao jamais entra por este fluxo.
  if exists (
    select 1
    from f.documento_fiscal_emissao prod
    where prod.tenant_id = v_sf.tenant_id
      and prod.empresa_id = v_sf.empresa_id
      and prod.solicitacao_id = v_sf.id
      and prod.ambiente = 'PRODUCAO'
      and prod.status <> 'CANCELADA'
  ) then
    raise exception using
      errcode = '55000',
      message = 'A solicitacao possui emissao de PRODUCAO: use o cancelamento no prazo ou a NF-e de estorno.';
  end if;

  if v_sf.status = 'CANCELADA' then
    return jsonb_build_object(
      'ok', true, 'idempotente', true, 'solicitacao_id', v_sf.id, 'status', 'CANCELADA'
    );
  end if;

  -- Este fluxo e para a emissao que ja passou pela SEFAZ de homologacao.
  -- Rascunho intocado continua no fluxo proprio, fn_solicitacao_nfe_cancelar_rascunho.
  if not exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.ambiente = 'HOMOLOGACAO'
      and dfe.status <> 'CANCELADA'
  ) then
    raise exception using
      errcode = '22023',
      message = 'Nenhuma emissao de homologacao viva nesta solicitacao; use o descarte de rascunho.';
  end if;

  -- Serializa com o calculo de saldo, igual ao descarte de rascunho.
  for v_origem in
    select distinct si.origem_id::integer as origem_id
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.origem_tipo in ('OS', 'OV')
      and si.origem_id ~ '^[0-9]+$'
    order by si.origem_id::integer
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      format('faturamento-parcial:%s:%s:%s', v_sf.tenant_id, v_sf.empresa_id, v_origem.origem_id),
      0
    ));
  end loop;

  -- Libera o guard apenas para esta solicitacao e apenas nesta transacao.
  perform set_config('f.abandono_homologacao', v_sf.id::text, true);

  update f.solicitacao_faturamento sf
  set status = 'CANCELADA',
      observacao = concat_ws(
        E'\n',
        nullif(btrim(sf.observacao), ''),
        'Emissao de homologacao abandonada, sem efeito fiscal: ' || v_motivo
      ),
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  -- A emissao NAO muda de status: continua AUTORIZADA porque de fato esta
  -- autorizada na SEFAZ de homologacao. O que se desfaz e a reserva de negocio.
  with eventos as (
    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
      status, resposta, referencia_externa
    )
    select
      dfe.documento_fiscal_id, dfe.tenant_id, dfe.empresa_id, 'CANCELAMENTO', v_motivo,
      'LOCAL',
      jsonb_build_object(
        'origem', 'ABANDONO_HOMOLOGACAO',
        'sem_chamada_sefaz', true,
        'ambiente', 'HOMOLOGACAO',
        'emissao_status_preservado', dfe.status,
        'saldo_devolvido', true
      ),
      dfe.referencia_externa
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.ambiente = 'HOMOLOGACAO'
      and dfe.status <> 'CANCELADA'
    returning documento_fiscal_id
  )
  select count(*) into v_eventos from eventos;

  perform set_config('f.abandono_homologacao', '', true);

  return jsonb_build_object(
    'ok', true,
    'idempotente', false,
    'solicitacao_id', v_sf.id,
    'status', 'CANCELADA',
    'eventos_registrados', v_eventos
  );
end;
$function$;

revoke all on function f.fn_solicitacao_nfe_abandonar_homologacao(uuid, text) from public;
grant execute on function f.fn_solicitacao_nfe_abandonar_homologacao(uuid, text) to authenticated, service_role;

commit;
