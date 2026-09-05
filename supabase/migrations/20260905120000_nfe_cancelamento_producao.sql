-- Cancelamento de NF-e em PRODUCAO (05/09/2026).
--
-- Ate aqui o cancelamento real era bloqueado em tres camadas (tela, guarda da
-- Edge e ausencia de funcoes de banco). A primeira NF-e real (serie 2 n. 1) foi
-- autorizada em 05/09/2026 e o responsavel pediu o cancelamento pela tela para
-- validar o fluxo. Este arquivo espelha o claim/finalizacao de homologacao para
-- PRODUCAO e aplica os efeitos que a homologacao nao tem:
--
--   * documento fiscal -> CANCELADA (numero e chave preservados: e documento
--     que existiu e entra no livro como cancelado);
--   * solicitacao -> CANCELADA (devolve o saldo comercial da OV);
--   * titulos a receber do documento -> CANCELADO, valor em aberto zerado
--     (o trigger de cobranca acompanha a mudanca de status);
--   * nenhum movimento de estoque: a baixa ocorreu na entrada do item na OV.
--
-- Guardas: janela legal de 24 horas; titulo com recebimento bloqueia o claim
-- antes de qualquer chamada a Focus; claim duravel com reconciliacao, como na
-- homologacao. O protocolo de autorizacao permanece na emissao; o protocolo do
-- cancelamento fica no evento.

create or replace function f.fn_nfe_ciclo_contexto(p_documento_fiscal_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_result jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select jsonb_build_object(
    'documento', to_jsonb(df),
    'emissao', to_jsonb(dfe),
    'cliente', case when cl.id is null then null else jsonb_build_object(
      'id', cl.id, 'nome', cl.nome, 'email', cl.email, 'email_financeiro', cl.email_financeiro
    ) end,
    'empresa', jsonb_build_object('id', emp.id, 'cnpj', emp.cnpj, 'nome', emp.nome_fantasia),
    'empresa_fiscal', case when ef.id is null then null else jsonb_build_object(
      'email_fisco', ef.email_fisco,
      'certificado_validade_em', ef.certificado_validade_em,
      'dias_certificado', case when ef.certificado_validade_em is null then null else ef.certificado_validade_em - current_date end
    ) end,
    'cancelamento', jsonb_build_object(
      'limite_em', dfe.autorizado_em + interval '24 hours',
      'segundos_restantes', greatest(0, extract(epoch from (dfe.autorizado_em + interval '24 hours' - now()))::bigint),
      -- PRODUCAO passou a poder cancelar dentro da janela legal (05/09/2026).
      'pode_cancelar', dfe.ambiente in ('HOMOLOGACAO', 'PRODUCAO') and dfe.status = 'AUTORIZADA'
        and dfe.autorizado_em is not null and now() < dfe.autorizado_em + interval '24 hours',
      'deve_estornar', dfe.status = 'AUTORIZADA' and dfe.autorizado_em is not null
        and now() >= dfe.autorizado_em + interval '24 hours'
    ),
    'cfops_estorno_propostos', coalesce((
      select jsonb_agg(x.cfop order by x.cfop)
      from (
        select distinct f.fn_cfop_estorno_proposto(i.cfop) cfop
        from f.documento_fiscal_item i
        where i.tenant_id = df.tenant_id and i.empresa_id = df.empresa_id
          and i.documento_fiscal_id = df.id and i.deleted_at is null
          and f.fn_cfop_estorno_proposto(i.cfop) is not null
      ) x
    ), '[]'::jsonb),
    'eventos', coalesce((
      select jsonb_agg(to_jsonb(ev) order by ev.created_at desc)
      from f.documento_fiscal_evento ev
      where ev.tenant_id = df.tenant_id and ev.empresa_id = df.empresa_id
        and ev.documento_fiscal_id = df.id
    ), '[]'::jsonb)
  ) into v_result
  from f.documento_fiscal df
  join f.documento_fiscal_emissao dfe
    on dfe.tenant_id = df.tenant_id and dfe.empresa_id = df.empresa_id and dfe.documento_fiscal_id = df.id
  join c.empresa emp on emp.tenant_id = df.tenant_id and emp.id = df.empresa_id
  left join c.empresa_fiscal ef on ef.empresa_id = emp.id and ef.deleted_at is null
  left join public.clientes cl
    on cl.tenant_id = df.tenant_id and cl.empresa_id = df.empresa_id and cl.id = df.cliente_id
  where df.tenant_id = v_scope.tenant_id and df.empresa_id = v_scope.empresa_id
    and df.id = p_documento_fiscal_id and df.deleted_at is null;

  if v_result is null then raise exception 'Emissao de NF-e nao encontrada nesta empresa.'; end if;
  return v_result;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Claim duravel do cancelamento em producao
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfe_cancelamento_producao_claim(
  p_documento_fiscal_id uuid,
  p_justificativa text,
  p_reconciliacao_claim_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_meta record;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_ultimo_cancelamento_id uuid;
  v_ultimo_cancelamento_status text;
  v_ultimo_cancelamento_em timestamptz;
  v_ultimo_cancelamento_justificativa text;
  v_evento_claim_id uuid;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o cancelamento.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa deve ter entre 15 e 255 caracteres.';
  end if;

  select dfe.tenant_id, dfe.empresa_id, dfe.solicitacao_id
    into v_meta
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id
   and df.empresa_id = dfe.empresa_id
   and df.id = dfe.documento_fiscal_id
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de producao nao encontrada.';
  end if;

  -- Mesma ordem de lock da promocao: solicitacao primeiro, emissao depois.
  perform 1
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_meta.tenant_id
    and sf.empresa_id = v_meta.empresa_id
    and sf.id = v_meta.solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao da producao nao encontrada no mesmo escopo.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_meta.tenant_id
    and dfe.empresa_id = v_meta.empresa_id
    and dfe.solicitacao_id = v_meta.solicitacao_id
    and dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO'
  for update;

  select ev.id, ev.status, ev.created_at, ev.justificativa
    into v_ultimo_cancelamento_id, v_ultimo_cancelamento_status,
         v_ultimo_cancelamento_em, v_ultimo_cancelamento_justificativa
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
    order by ev.created_at desc, ev.id desc
    limit 1;

  if v_ultimo_cancelamento_status = 'ENVIANDO'
     and v_ultimo_cancelamento_em >= now() - interval '2 minutes' then
    return jsonb_build_object(
      'deve_cancelar', false,
      'aguardar', true,
      'deve_reconciliar', false,
      'evento_claim_id', v_ultimo_cancelamento_id,
      'justificativa_claim', v_ultimo_cancelamento_justificativa,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', 'ENVIANDO'
    );
  end if;
  if v_ultimo_cancelamento_status = 'ENVIANDO' then
    if p_reconciliacao_claim_id is distinct from v_ultimo_cancelamento_id then
      return jsonb_build_object(
        'deve_cancelar', false,
        'aguardar', false,
        'deve_reconciliar', true,
        'evento_claim_id', v_ultimo_cancelamento_id,
        'justificativa_claim', v_ultimo_cancelamento_justificativa,
        'documento_fiscal_id', v_emissao.documento_fiscal_id,
        'referencia_externa', v_emissao.referencia_externa,
        'status', 'ENVIANDO'
      );
    end if;
    if v_ultimo_cancelamento_justificativa is distinct from v_justificativa then
      raise exception using
        errcode = '22023',
        message = 'A justificativa do retry deve ser a mesma do claim de cancelamento reconciliado.';
    end if;
  elsif p_reconciliacao_claim_id is not null then
    raise exception using
      errcode = '55000',
      message = 'O claim informado ja nao e o cancelamento pendente mais recente.';
  end if;
  if v_emissao.status <> 'AUTORIZADA' then
    raise exception using errcode = '55000', message = format('Status %s nao permite cancelamento da NF-e.', v_emissao.status);
  end if;
  if v_emissao.autorizado_em is null or now() >= v_emissao.autorizado_em + interval '24 hours' then
    raise exception using
      errcode = '55000',
      message = 'A janela legal de 24 horas para cancelamento terminou. Use a NF-e de estorno.';
  end if;

  -- Titulo com recebimento nao pode ser cancelado por aqui: estornar antes.
  if exists (
    select 1
    from f.titulo t
    left join f.titulo_parcela tp
      on tp.titulo_id = t.id
     and tp.tenant_id = t.tenant_id
     and tp.deleted_at is null
    left join f.pagamento_item pi
      on pi.titulo_parcela_id = tp.id
     and pi.deleted_at is null
    where t.tenant_id = v_emissao.tenant_id
      and t.empresa_id = v_emissao.empresa_id
      and t.documento_fiscal_id = v_emissao.documento_fiscal_id
      and t.deleted_at is null
      and (
        pi.id is not null
        or upper(coalesce(t.status, '')) = 'PAGO'
        or abs(round(coalesce(t.valor_total, 0), 2) - round(coalesce(t.valor_aberto, 0), 2)) > 0.009
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'O titulo a receber desta NF-e possui recebimento. Estorne o recebimento antes de cancelar a nota.';
  end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
    status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
    'CANCELAMENTO', v_justificativa, 'ENVIANDO',
    jsonb_build_object('claim_duravel', true, 'ambiente', 'PRODUCAO'),
    v_emissao.referencia_externa
  ) returning id into v_evento_claim_id;

  return jsonb_build_object(
    'deve_cancelar', true,
    'aguardar', false,
    'deve_reconciliar', false,
    'evento_claim_id', v_evento_claim_id,
    'justificativa_claim', v_justificativa,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', 'ENVIANDO'
  );
end;
$function$;

revoke all on function f.fn_nfe_cancelamento_producao_claim(uuid, text, uuid) from public, anon, authenticated;
grant execute on function f.fn_nfe_cancelamento_producao_claim(uuid, text, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Finalizacao do cancelamento em producao, com efeitos financeiros
-- ---------------------------------------------------------------------------
create or replace function f.fn_nfe_cancelamento_producao_finalizar(
  p_documento_fiscal_id uuid,
  p_evento_claim_id uuid,
  p_status text,
  p_justificativa text,
  p_protocolo text default null::text,
  p_resposta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_meta record;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_claim record;
  v_ultimo_cancelamento_id uuid;
  v_ultimo_cancelamento_status text;
  v_titulos integer := 0;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode concluir o cancelamento.';
  end if;
  if v_status not in ('AUTORIZADA', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status final de cancelamento invalido.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa deve ter entre 15 e 255 caracteres.';
  end if;
  select dfe.tenant_id, dfe.empresa_id, dfe.solicitacao_id
    into v_meta
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de producao nao encontrada.';
  end if;
  perform 1
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_meta.tenant_id
    and sf.empresa_id = v_meta.empresa_id
    and sf.id = v_meta.solicitacao_id
  for update;
  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_meta.tenant_id
    and dfe.empresa_id = v_meta.empresa_id
    and dfe.solicitacao_id = v_meta.solicitacao_id
    and dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO'
  for update;
  if p_evento_claim_id is null then
    raise exception using errcode = '22023', message = 'O identificador do claim de cancelamento e obrigatorio.';
  end if;
  if v_emissao.status = 'CANCELADA' and v_status = 'AUTORIZADA' then
    if exists (
      select 1
      from f.documento_fiscal_evento ev
      where ev.tenant_id = v_emissao.tenant_id
        and ev.empresa_id = v_emissao.empresa_id
        and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
        and ev.tipo = 'CANCELAMENTO'
        and ev.status = 'AUTORIZADA'
        and ev.resposta->>'claim_evento_id' = p_evento_claim_id::text
    ) then
      return jsonb_build_object('ok', true, 'idempotente', true, 'status', 'CANCELADA');
    end if;
    raise exception using errcode = '55000', message = 'Resposta tardia pertence a outro claim de cancelamento.';
  end if;
  select ev.id, ev.status
    into v_ultimo_cancelamento_id, v_ultimo_cancelamento_status
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
    order by ev.created_at desc, ev.id desc
    limit 1;
  if v_emissao.status <> 'AUTORIZADA'
     or v_ultimo_cancelamento_status is distinct from 'ENVIANDO'
     or v_ultimo_cancelamento_id is distinct from p_evento_claim_id then
    raise exception using errcode = '55000', message = 'Cancelamento sem claim duravel correspondente.';
  end if;
  select ev.id, ev.justificativa
    into v_claim
  from f.documento_fiscal_evento ev
  where ev.tenant_id = v_emissao.tenant_id
    and ev.empresa_id = v_emissao.empresa_id
    and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
    and ev.id = p_evento_claim_id
    and ev.tipo = 'CANCELAMENTO'
    and ev.status = 'ENVIANDO';
  if not found or v_claim.justificativa is distinct from v_justificativa then
    raise exception using errcode = '22023', message = 'Justificativa ou claim de cancelamento nao corresponde a reserva original.';
  end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, protocolo,
    status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
    'CANCELAMENTO', v_justificativa, nullif(btrim(p_protocolo), ''),
    v_status,
    coalesce(p_resposta, '{}'::jsonb)
      || jsonb_build_object('claim_evento_id', p_evento_claim_id, 'ambiente', 'PRODUCAO'),
    v_emissao.referencia_externa
  );

  if v_status = 'AUTORIZADA' then
    -- Emissao: o protocolo de autorizacao permanece; o do cancelamento esta no evento.
    update f.documento_fiscal_emissao dfe
    set status = 'CANCELADA',
        resposta = coalesce(p_resposta, dfe.resposta),
        mensagem = 'Cancelamento autorizado.',
        updated_at = now()
    where dfe.tenant_id = v_emissao.tenant_id
      and dfe.empresa_id = v_emissao.empresa_id
      and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;

    -- Documento: cancelado, com numero e chave preservados (entra no livro
    -- como documento cancelado; o filtro do analitico ja trata esse caso).
    update f.documento_fiscal df
    set nfe_status = 'CANCELADA', updated_at = now()
    where df.tenant_id = v_emissao.tenant_id
      and df.empresa_id = v_emissao.empresa_id
      and df.id = v_emissao.documento_fiscal_id;

    -- Solicitacao: cancelada, o que devolve a reserva/saldo da OV.
    update f.solicitacao_faturamento sf
    set status = 'CANCELADA', updated_at = now()
    where sf.tenant_id = v_emissao.tenant_id
      and sf.empresa_id = v_emissao.empresa_id
      and sf.id = v_emissao.solicitacao_id;

    -- Titulos a receber: cancelados e zerados. O claim ja garantiu que nao ha
    -- recebimento; a cobranca acompanha pelo trigger de status do titulo.
    update f.titulo_parcela tp
    set valor_aberto = 0, updated_at = now()
    from f.titulo t
    where t.id = tp.titulo_id
      and tp.tenant_id = t.tenant_id
      and t.tenant_id = v_emissao.tenant_id
      and t.empresa_id = v_emissao.empresa_id
      and t.documento_fiscal_id = v_emissao.documento_fiscal_id
      and t.tipo = 'AR'
      and t.deleted_at is null
      and tp.deleted_at is null;
    update f.titulo t
    set status = 'CANCELADO', valor_aberto = 0, updated_at = now()
    where t.tenant_id = v_emissao.tenant_id
      and t.empresa_id = v_emissao.empresa_id
      and t.documento_fiscal_id = v_emissao.documento_fiscal_id
      and t.tipo = 'AR'
      and t.deleted_at is null;
    get diagnostics v_titulos = row_count;
  else
    update f.documento_fiscal_emissao dfe
    set resposta = coalesce(p_resposta, dfe.resposta),
        mensagem = 'Cancelamento nao autorizado; NF-e permanece autorizada.',
        updated_at = now()
    where dfe.tenant_id = v_emissao.tenant_id
      and dfe.empresa_id = v_emissao.empresa_id
      and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;

  return jsonb_build_object(
    'ok', v_status = 'AUTORIZADA',
    'idempotente', false,
    'status', case when v_status = 'AUTORIZADA' then 'CANCELADA' else 'AUTORIZADA' end,
    'titulos_cancelados', v_titulos
  );
end;
$function$;

revoke all on function f.fn_nfe_cancelamento_producao_finalizar(uuid, uuid, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function f.fn_nfe_cancelamento_producao_finalizar(uuid, uuid, text, text, text, jsonb) to service_role;
