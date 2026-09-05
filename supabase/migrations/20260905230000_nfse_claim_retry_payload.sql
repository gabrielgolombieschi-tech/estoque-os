-- NFS-e: o retry depois de REJEITADA/ERRO em homologacao pode levar payload
-- corrigido (a DPS rejeitada esta queimada e nada foi autorizado); antes so
-- numero_dps/data_emissao podiam mudar, o que impedia corrigir o proprio
-- payload apontado pelo ambiente nacional (ex.: cIntContrib, cIndOp).
-- Baseline: f.fn_nfse_homologacao_claimar da migration 20260905200000.
create or replace function f.fn_nfse_homologacao_claimar(p_documento_fiscal_id uuid, p_payload jsonb, p_reconciliacao_confirmada boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_tinha_claim boolean;
  v_payload_congelado jsonb;
  v_payload_alterado boolean := false;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o envio de homologacao.';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'O payload da NFS-e deve ser um objeto JSON.';
  end if;
  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.ambiente = 'HOMOLOGACAO' and dfe.modelo = 'NFSE'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de NFS-e em homologacao nao encontrada.';
  end if;
  if v_emissao.status in ('AUTORIZADA', 'PROCESSANDO', 'CANCELADA') then
    return jsonb_build_object('deve_enviar', false, 'aguardar', v_emissao.status = 'PROCESSANDO',
      'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
  end if;
  v_tinha_claim := v_emissao.status = 'ENVIANDO' or v_emissao.tentativa_count > 0 or v_emissao.payload_enviado is not null or v_emissao.enviado_em is not null;
  if v_emissao.status = 'ENVIANDO' and v_emissao.ultima_tentativa_em >= now() - interval '2 minutes' then
    return jsonb_build_object('deve_enviar', false, 'aguardar', true,
      'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
  end if;
  if v_tinha_claim and not coalesce(p_reconciliacao_confirmada, false) then
    raise exception using errcode = '55000', message = 'A referencia de homologacao ja possui tentativa; consulte a Focus antes de qualquer novo POST.';
  end if;
  if (p_payload->>'numero_dps')::bigint is distinct from v_emissao.dps_numero
     or (p_payload->>'serie_dps')::smallint is distinct from v_emissao.dps_serie then
    raise exception using errcode = '22023', message = 'O payload nao traz a serie/numero de DPS reservados para esta emissao.';
  end if;
  if v_emissao.status in ('REJEITADA', 'ERRO') then
    -- DPS rejeitada fica queimada; o retry leva numero novo e o payload atual
    -- (que pode ter sido corrigido). O que mudou fica no evento.
    v_payload_alterado := v_emissao.payload_enviado is not null
      and (v_emissao.payload_enviado - 'numero_dps' - 'data_emissao') is distinct from (p_payload - 'numero_dps' - 'data_emissao');
    v_payload_congelado := p_payload;
  else
    if v_emissao.payload_enviado is not null and v_emissao.payload_enviado is distinct from p_payload then
      raise exception using errcode = '22023', message = 'O retry de homologacao diverge do payload congelado no primeiro claim.';
    end if;
    v_payload_congelado := coalesce(v_emissao.payload_enviado, p_payload);
  end if;
  if v_emissao.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'ENVIANDO') then
    raise exception using errcode = '55000', message = format('Status %s nao aceita claim de homologacao.', v_emissao.status);
  end if;
  update f.documento_fiscal_emissao dfe
  set status = 'ENVIANDO', payload_enviado = v_payload_congelado, tentativa_count = dfe.tentativa_count + 1,
      ultima_tentativa_em = now(), enviado_em = coalesce(dfe.enviado_em, now()), codigo_status = null, mensagem = null, updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id and dfe.empresa_id = v_emissao.empresa_id and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;
  insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa)
  values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'ENVIO', 'ENVIANDO',
          jsonb_build_object('claim_duravel', true, 'ambiente', 'HOMOLOGACAO', 'modelo', 'NFSE', 'tentativa', v_emissao.tentativa_count,
                             'dps_serie', v_emissao.dps_serie, 'dps_numero', v_emissao.dps_numero,
                             'payload_alterado_apos_rejeicao', v_payload_alterado,
                             'reconciliacao_previa', coalesce(p_reconciliacao_confirmada, false)),
          v_emissao.referencia_externa);
  return jsonb_build_object('deve_enviar', true, 'aguardar', false,
    'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status, 'tentativa_count', v_emissao.tentativa_count, 'payload', v_emissao.payload_enviado);
end;
$$;
revoke all on function f.fn_nfse_homologacao_claimar(uuid, jsonb, boolean) from public;
grant execute on function f.fn_nfse_homologacao_claimar(uuid, jsonb, boolean) to service_role;
