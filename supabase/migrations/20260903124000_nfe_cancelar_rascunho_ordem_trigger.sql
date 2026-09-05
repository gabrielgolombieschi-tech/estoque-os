begin;

-- A 123 passou a proteger solicitacao_faturamento contra qualquer mutacao
-- authenticated depois que a emissao deixa de ser um HOM RASCUNHO intocado.
-- O descarte legitimo atualizava DFE primeiro e, ao chegar na solicitacao, a
-- propria barreira o bloqueava. Atualizar SF primeiro preserva a barreira;
-- tudo continua na mesma transacao e qualquer falha posterior desfaz o lote.
create or replace function f.fn_solicitacao_nfe_cancelar_rascunho(
  p_solicitacao_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_emissoes_canceladas integer := 0;
  v_documentos_cancelados integer := 0;
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
    raise exception using errcode = '42501', message = 'Sem permissao para cancelar esta solicitacao.';
  end if;
  if char_length(v_motivo) < 15 or char_length(v_motivo) > 255 then
    raise exception using errcode = '22023', message = 'O motivo deve ter entre 15 e 255 caracteres.';
  end if;

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
      message = 'A solicitacao possui emissao de PRODUCAO e nao pode ser cancelada pelo fluxo de rascunho.';
  end if;
  if v_sf.status = 'CANCELADA' then
    return jsonb_build_object(
      'ok', true,
      'idempotente', true,
      'solicitacao_id', v_sf.id,
      'status', 'CANCELADA'
    );
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Somente uma solicitacao editavel pode ser cancelada por este fluxo.';
  end if;

  -- So e descartavel a ausencia de emissao ou HOM RASCUNHO nunca claimada.
  -- REJEITADA/ERRO podem representar POST aceito e exigem reconciliacao.
  if exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.ambiente = 'HOMOLOGACAO'
      and (
        dfe.status not in ('RASCUNHO', 'CANCELADA')
        or (
          dfe.status = 'RASCUNHO'
          and (
            dfe.tentativa_count <> 0
            or dfe.payload_enviado is not null
            or dfe.enviado_em is not null
            or dfe.ultima_tentativa_em is not null
          )
        )
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'A solicitacao possui tentativa fiscal; reconcilie/cancele pelo fluxo proprio antes de devolver o saldo.';
  end if;

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

  -- Precisa ocorrer enquanto a DFE ainda e HOM/RASCUNHO/intocada, que e a
  -- unica situacao autorizada pelo trigger de material pos-claim da 123.
  update f.solicitacao_faturamento sf
  set status = 'CANCELADA',
      observacao = concat_ws(E'\n', nullif(btrim(sf.observacao), ''), 'Cancelada antes da autorizacao: ' || v_motivo),
      updated_at = now()
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  with canceladas as (
    update f.documento_fiscal_emissao dfe
    set status = 'CANCELADA',
        mensagem = 'Solicitacao cancelada localmente antes de qualquer autorizacao.',
        updated_at = now()
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
      and dfe.ambiente = 'HOMOLOGACAO'
      and dfe.status = 'RASCUNHO'
      and dfe.tentativa_count = 0
      and dfe.payload_enviado is null
      and dfe.enviado_em is null
      and dfe.ultima_tentativa_em is null
    returning dfe.documento_fiscal_id, dfe.tenant_id, dfe.empresa_id, dfe.referencia_externa
  ), eventos as (
    insert into f.documento_fiscal_evento (
      documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
      status, resposta, referencia_externa
    )
    select
      c.documento_fiscal_id, c.tenant_id, c.empresa_id, 'CANCELAMENTO', v_motivo,
      'LOCAL', jsonb_build_object('origem', 'RASCUNHO', 'sem_chamada_sefaz', true), c.referencia_externa
    from canceladas c
    returning documento_fiscal_id
  )
  select count(*) into v_emissoes_canceladas from eventos;

  -- A guarda de documento da 123 permite esta transicao exata somente depois
  -- que a HOM correspondente ja foi marcada CANCELADA e nunca foi tentada.
  with documentos as (
    update f.documento_fiscal df
    set nfe_status = 'CANCELADA', updated_at = now()
    where df.tenant_id = v_sf.tenant_id
      and df.empresa_id = v_sf.empresa_id
      and df.id in (
        select dfe.documento_fiscal_id
        from f.documento_fiscal_emissao dfe
        where dfe.tenant_id = v_sf.tenant_id
          and dfe.empresa_id = v_sf.empresa_id
          and dfe.solicitacao_id = v_sf.id
          and dfe.ambiente = 'HOMOLOGACAO'
          and dfe.status = 'CANCELADA'
      )
      and df.nfe_status = 'RASCUNHO'
    returning df.id
  )
  select count(*) into v_documentos_cancelados from documentos;

  return jsonb_build_object(
    'ok', true,
    'idempotente', false,
    'solicitacao_id', v_sf.id,
    'status', 'CANCELADA',
    'emissoes_canceladas', v_emissoes_canceladas,
    'documentos_cancelados', v_documentos_cancelados
  );
end;
$function$;

comment on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text) is
  'Cancela SF antes da DFE para respeitar a barreira pos-claim; depois cancela somente HOM RASCUNHO intocada e seu documento, tudo atomicamente.';
revoke all on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text)
  from public, anon;
grant execute on function f.fn_solicitacao_nfe_cancelar_rascunho(uuid, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
