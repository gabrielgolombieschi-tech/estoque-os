-- Cancelamento de NF-e: claim e finalizacao (pedido do Gabriel em 18/09/2026, diagnostico em
-- docs/faturamento/seguranca-grants-2026-09-18.md, item 5):
--   (a) fn_nfe_cancelamento_{producao,homologacao}_claim: a guarda "nota ja cancelada" (status da
--       emissao <> AUTORIZADA -> 55000) passa a ser a primeira verificacao depois do lock da emissao,
--       antes do ramo "aguardar" (claim ENVIANDO < 2 min) e da reconciliacao;
--   (b) o claim ENVIANDO conta como encerrado assim que existe o evento do resultado que o referencia
--       (resposta.claim_evento_id, gravado pela finalizacao). Os eventos sao append-only (gatilho
--       documento_fiscal_evento_append_only recusa UPDATE), entao o encerramento nao e gravado no
--       claim: as sete leituras de "ultimo cancelamento" (claims, finalizacoes, fn_nfe_producao_pronta,
--       fn_nfe_producao_preparar_e_claimar e o gatilho de homologacao pendente) ignoram claims com
--       resultado, em qualquer ordem;
--   (c) desempate deterministico: f.documento_fiscal_evento ganha seq (ordem de insercao, sequencia) e
--       as 12 funcoes que ordenavam "created_at desc, id desc" (uuid aleatorio) passam a
--       "created_at desc, seq desc". Na mesma transacao now() empata, e o uuid decidia na sorte
--       (faturamento_nfe_pipeline.sql, linha 2108, passava ou falhava conforme o rebuild).
-- As 12 definicoes foram copiadas do banco (local = online, md5 conferido) e alteradas so nesses pontos.
-- Reversao: definicoes anteriores (sem seq) e drop column seq.

-- 1. Ordem de insercao dos eventos. O preenchimento unico da coluna nova nas linhas existentes (pela
--    ordem created_at, id) passa pelo gatilho append-only desligado so nesta transacao: a coluna e
--    tecnica e nenhum campo do historico (tipo, status, resposta, protocolo) muda.
alter table f.documento_fiscal_evento add column if not exists seq bigint;
create sequence if not exists f.documento_fiscal_evento_seq_seq as bigint;
alter sequence f.documento_fiscal_evento_seq_seq owned by f.documento_fiscal_evento.seq;
alter table f.documento_fiscal_evento disable trigger documento_fiscal_evento_append_only;
update f.documento_fiscal_evento ev
   set seq = o.rn
  from (select id, row_number() over (order by created_at, id) as rn from f.documento_fiscal_evento) o
 where o.id = ev.id and ev.seq is null;
alter table f.documento_fiscal_evento enable trigger documento_fiscal_evento_append_only;
select setval('f.documento_fiscal_evento_seq_seq', coalesce((select max(seq) from f.documento_fiscal_evento), 0) + 1, false);
alter table f.documento_fiscal_evento alter column seq set default nextval('f.documento_fiscal_evento_seq_seq');
alter table f.documento_fiscal_evento alter column seq set not null;
comment on column f.documento_fiscal_evento.seq is 'Ordem de insercao (desempate deterministico de eventos com o mesmo created_at).';
create index if not exists documento_fiscal_evento_doc_tipo_ordem_idx on f.documento_fiscal_evento (documento_fiscal_id, tipo, created_at desc, seq desc);

-- 2. Funcoes.

-- 2.1 fn_nfe_cancelamento_producao_claim
CREATE OR REPLACE FUNCTION f.fn_nfe_cancelamento_producao_claim(p_documento_fiscal_id uuid, p_justificativa text, p_reconciliacao_claim_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
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

  -- Nota ja cancelada (ou nunca autorizada) e recusada antes de qualquer ramo de espera/reconciliacao.
  if v_emissao.status <> 'AUTORIZADA' then
    raise exception using errcode = '55000', message = format('Status %s nao permite cancelamento da NF-e.', v_emissao.status);
  end if;

  select ev.id, ev.status, ev.created_at, ev.justificativa
    into v_ultimo_cancelamento_id, v_ultimo_cancelamento_status,
         v_ultimo_cancelamento_em, v_ultimo_cancelamento_justificativa
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
      and not exists (
        select 1 from f.documento_fiscal_evento r
        where r.documento_fiscal_id = ev.documento_fiscal_id and r.tipo = 'CANCELAMENTO' and r.id <> ev.id
          and r.resposta->>'claim_evento_id' = ev.id::text
      )
    order by ev.created_at desc, ev.seq desc
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

-- 2.2 fn_nfe_cancelamento_producao_finalizar
CREATE OR REPLACE FUNCTION f.fn_nfe_cancelamento_producao_finalizar(p_documento_fiscal_id uuid, p_evento_claim_id uuid, p_status text, p_justificativa text, p_protocolo text DEFAULT NULL::text, p_resposta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
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
      and not exists (
        select 1 from f.documento_fiscal_evento r
        where r.documento_fiscal_id = ev.documento_fiscal_id and r.tipo = 'CANCELAMENTO' and r.id <> ev.id
          and r.resposta->>'claim_evento_id' = ev.id::text
      )
    order by ev.created_at desc, ev.seq desc
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

-- 2.3 fn_nfe_cancelamento_homologacao_claim
CREATE OR REPLACE FUNCTION f.fn_nfe_cancelamento_homologacao_claim(p_documento_fiscal_id uuid, p_justificativa text, p_reconciliacao_claim_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
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
    and dfe.ambiente = 'HOMOLOGACAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de homologacao nao encontrada.';
  end if;

  -- Mesma ordem de lock da promocao: solicitacao primeiro, emissao depois.
  perform 1
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_meta.tenant_id
    and sf.empresa_id = v_meta.empresa_id
    and sf.id = v_meta.solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao da homologacao nao encontrada no mesmo escopo.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_meta.tenant_id
    and dfe.empresa_id = v_meta.empresa_id
    and dfe.solicitacao_id = v_meta.solicitacao_id
    and dfe.documento_fiscal_id = p_documento_fiscal_id
    and dfe.ambiente = 'HOMOLOGACAO'
  for update;

  -- Nota ja cancelada (ou nunca autorizada) e recusada antes de qualquer ramo de espera/reconciliacao.
  if v_emissao.status <> 'AUTORIZADA' then
    raise exception using errcode = '55000', message = format('Status %s nao permite cancelamento da homologacao.', v_emissao.status);
  end if;

  if exists (
    select 1
    from f.documento_fiscal_emissao prod
    where prod.tenant_id = v_emissao.tenant_id
      and prod.empresa_id = v_emissao.empresa_id
      and prod.solicitacao_id = v_emissao.solicitacao_id
      and prod.ambiente = 'PRODUCAO'
      and prod.status <> 'CANCELADA'
  ) then
    raise exception using errcode = '55000', message = 'A homologacao nao pode ser cancelada depois que a promocao para producao foi iniciada.';
  end if;

  select ev.id, ev.status, ev.created_at, ev.justificativa
    into v_ultimo_cancelamento_id, v_ultimo_cancelamento_status,
         v_ultimo_cancelamento_em, v_ultimo_cancelamento_justificativa
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_emissao.tenant_id
      and ev.empresa_id = v_emissao.empresa_id
      and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
      and not exists (
        select 1 from f.documento_fiscal_evento r
        where r.documento_fiscal_id = ev.documento_fiscal_id and r.tipo = 'CANCELAMENTO' and r.id <> ev.id
          and r.resposta->>'claim_evento_id' = ev.id::text
      )
    order by ev.created_at desc, ev.seq desc
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

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa,
    status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id,
    'CANCELAMENTO', v_justificativa, 'ENVIANDO',
    jsonb_build_object('claim_duravel', true, 'sem_promocao_concorrente', true),
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

-- 2.4 fn_nfe_cancelamento_homologacao_finalizar
CREATE OR REPLACE FUNCTION f.fn_nfe_cancelamento_homologacao_finalizar(p_documento_fiscal_id uuid, p_evento_claim_id uuid, p_status text, p_justificativa text, p_protocolo text DEFAULT NULL::text, p_resposta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_meta record;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_claim record;
  v_ultimo_cancelamento_id uuid;
  v_ultimo_cancelamento_status text;
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
    and dfe.ambiente = 'HOMOLOGACAO';
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de homologacao nao encontrada.';
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
    and dfe.ambiente = 'HOMOLOGACAO'
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
      and not exists (
        select 1 from f.documento_fiscal_evento r
        where r.documento_fiscal_id = ev.documento_fiscal_id and r.tipo = 'CANCELAMENTO' and r.id <> ev.id
          and r.resposta->>'claim_evento_id' = ev.id::text
      )
    order by ev.created_at desc, ev.seq desc
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
    coalesce(p_resposta, '{}'::jsonb) || jsonb_build_object('claim_evento_id', p_evento_claim_id),
    v_emissao.referencia_externa
  );
  if v_status = 'AUTORIZADA' then
    -- Somente a emissao muda. O documento de homologacao continua RASCUNHO:
    -- nao e faturamento nem antes nem depois do cancelamento.
    update f.documento_fiscal_emissao dfe
    set status = 'CANCELADA',
        protocolo = coalesce(nullif(btrim(p_protocolo), ''), dfe.protocolo),
        resposta = coalesce(p_resposta, dfe.resposta),
        mensagem = 'Cancelamento autorizado.',
        updated_at = now()
    where dfe.tenant_id = v_emissao.tenant_id
      and dfe.empresa_id = v_emissao.empresa_id
      and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
    update f.solicitacao_faturamento sf
    set status = 'CANCELADA', updated_at = now()
    where sf.tenant_id = v_emissao.tenant_id
      and sf.empresa_id = v_emissao.empresa_id
      and sf.id = v_emissao.solicitacao_id;
  else
    update f.documento_fiscal_emissao dfe
    set resposta = coalesce(p_resposta, dfe.resposta),
        mensagem = 'Cancelamento nao autorizado; NF-e de homologacao permanece autorizada.',
        updated_at = now()
    where dfe.tenant_id = v_emissao.tenant_id
      and dfe.empresa_id = v_emissao.empresa_id
      and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;
  return jsonb_build_object(
    'ok', v_status = 'AUTORIZADA',
    'idempotente', false,
    'status', case when v_status = 'AUTORIZADA' then 'CANCELADA' else 'AUTORIZADA' end
  );
end;
$function$;

-- 2.5 fn_nfe_producao_preparar_e_claimar
CREATE OR REPLACE FUNCTION f.fn_nfe_producao_preparar_e_claimar(p_solicitacao_id uuid, p_payload jsonb, p_homologacao_documento_id uuid, p_contexto_hash text, p_reconciliacao_confirmada boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_preparada record;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_prontidao jsonb;
  v_tinha_claim boolean;
  v_material jsonb;
  v_contexto_hash_atual text;
  v_contexto_hash_primeiro_claim text;
  v_homologacao_primeiro_claim uuid;
  v_homologacao_payload jsonb;
  v_sf f.solicitacao_faturamento%rowtype;
  v_produtos numeric;
  v_desconto numeric;
  v_desconto_fonte numeric;
  v_frete numeric;
  v_seguro numeric;
  v_outros numeric;
  v_total numeric;
  v_ipi numeric;
  v_total_esperado numeric;
  v_itens_payload integer;
  v_itens_solicitacao integer;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o envio de producao.';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'O payload fiscal de producao deve ser um objeto JSON.';
  end if;
  if p_homologacao_documento_id is null
     or coalesce(p_contexto_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Documento HOM e hash do preflight sao obrigatorios.';
  end if;

  -- A chamada aninhada participa desta mesma transacao: se qualquer gate ou
  -- claim falhar, uma emissao criada agora e integralmente revertida.
  select * into v_preparada
  from f.fn_nfe_preparar_documento_solicitacao_producao(p_solicitacao_id);

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = (select sf.tenant_id from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id)
    and dfe.empresa_id = (select sf.empresa_id from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id)
    and dfe.solicitacao_id = p_solicitacao_id
    and dfe.documento_fiscal_id = v_preparada.documento_fiscal_id
    and dfe.ambiente = 'PRODUCAO'
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao de producao preparada nao encontrada no mesmo escopo.';
  end if;
  if v_emissao.status in ('AUTORIZADA', 'PROCESSANDO') then
    return jsonb_build_object(
      'deve_enviar', false,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status,
      'tentativa_count', v_emissao.tentativa_count,
      'payload', v_emissao.payload_enviado
    );
  end if;

  v_tinha_claim := v_emissao.status = 'ENVIANDO'
    or v_emissao.tentativa_count > 0
    or v_emissao.payload_enviado is not null
    or v_emissao.enviado_em is not null;

  -- Compare-and-set: um concorrente que perdeu a corrida nao consulta nem
  -- reenvia enquanto o vencedor ainda pode estar entre o COMMIT e o POST.
  if v_emissao.status = 'ENVIANDO'
     and v_emissao.ultima_tentativa_em >= now() - interval '2 minutes' then
    return jsonb_build_object(
      'deve_enviar', false,
      'aguardar', true,
      'documento_fiscal_id', v_emissao.documento_fiscal_id,
      'referencia_externa', v_emissao.referencia_externa,
      'status', v_emissao.status,
      'tentativa_count', v_emissao.tentativa_count,
      'payload', v_emissao.payload_enviado
    );
  end if;
  if v_tinha_claim and not coalesce(p_reconciliacao_confirmada, false) then
    raise exception using
      errcode = '55000',
      message = 'A referencia ja possui claim; consulte a Focus antes de qualquer novo POST.';
  end if;

  -- Congela todas as fontes que alimentam o contexto/payload. Se uma escrita
  -- venceu antes destes locks, o hash abaixo detecta; se vier depois, aguarda.
  select sf.* into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  perform 1
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
  order by si.id
  for update;
  perform 1
  from f.documento_fiscal_emissao hom
  where hom.tenant_id = v_sf.tenant_id
    and hom.empresa_id = v_sf.empresa_id
    and hom.solicitacao_id = v_sf.id
    and hom.documento_fiscal_id = p_homologacao_documento_id
    and hom.ambiente = 'HOMOLOGACAO'
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'A homologacao do preflight nao pertence a solicitacao e escopo atuais.';
  end if;
  perform 1
  from f.documento_fiscal df
  where df.tenant_id = v_sf.tenant_id
    and df.empresa_id = v_sf.empresa_id
    and df.id = p_homologacao_documento_id
  for update;
  perform 1
  from f.documento_fiscal_item dfi
  where dfi.tenant_id = v_sf.tenant_id
    and dfi.empresa_id = v_sf.empresa_id
    and dfi.documento_fiscal_id = p_homologacao_documento_id
    and dfi.deleted_at is null
  order by dfi.id
  for update;
  perform po.id
  from f.perfil_operacao po
  where po.tenant_id = v_sf.tenant_id
    and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
    and exists (
      select 1 from f.solicitacao_item si
      where si.tenant_id = v_sf.tenant_id
        and si.empresa_id = v_sf.empresa_id
        and si.solicitacao_id = v_sf.id
        and si.perfil_operacao_id = po.id
    )
  order by po.id
  for update;
  perform ef.id
  from c.empresa_fiscal ef
  where ef.empresa_id = v_sf.empresa_id
    and ef.deleted_at is null
  order by ef.id
  for update;

  select nullif(ev.resposta->>'homologacao_documento_fiscal_id', '')::uuid,
         ev.resposta->>'contexto_hash'
    into v_homologacao_primeiro_claim, v_contexto_hash_primeiro_claim
  from f.documento_fiscal_evento ev
  where ev.tenant_id = v_emissao.tenant_id
    and ev.empresa_id = v_emissao.empresa_id
    and ev.documento_fiscal_id = v_emissao.documento_fiscal_id
    and ev.tipo = 'ENVIO'
    and coalesce((ev.resposta->>'claim_duravel')::boolean, false)
    and ev.resposta ? 'contexto_hash'
  order by ev.created_at, ev.id
  limit 1;

  if v_tinha_claim and v_contexto_hash_primeiro_claim is not null then
    -- O primeiro claim capturou a liberacao exata. Uma liberacao posterior do
    -- mesmo perfil para outra solicitacao nao pode encalhar a reconciliacao
    -- desta referencia; continuam obrigatorios HOM autorizada, certificado,
    -- ausencia de cancelamento e o material fiscal originalmente congelado.
    if v_homologacao_primeiro_claim is distinct from p_homologacao_documento_id
       or v_contexto_hash_primeiro_claim is distinct from lower(p_contexto_hash) then
      raise exception using errcode = '40001', message = 'Retry diverge da homologacao/hash capturados no primeiro claim de producao.';
    end if;
    if v_sf.status = 'CANCELADA'
       or not exists (
         select 1
         from f.documento_fiscal_emissao hom
         where hom.tenant_id = v_sf.tenant_id
           and hom.empresa_id = v_sf.empresa_id
           and hom.solicitacao_id = v_sf.id
           and hom.documento_fiscal_id = p_homologacao_documento_id
           and hom.ambiente = 'HOMOLOGACAO'
           and hom.status = 'AUTORIZADA'
       )
       or coalesce((
         select ev.status = 'ENVIANDO'
         from f.documento_fiscal_evento ev
         where ev.tenant_id = v_sf.tenant_id
           and ev.empresa_id = v_sf.empresa_id
           and ev.documento_fiscal_id = p_homologacao_documento_id
           and ev.tipo = 'CANCELAMENTO'
           and not exists (
             select 1 from f.documento_fiscal_evento r
             where r.documento_fiscal_id = ev.documento_fiscal_id and r.tipo = 'CANCELAMENTO' and r.id <> ev.id
               and r.resposta->>'claim_evento_id' = ev.id::text
           )
         order by ev.created_at desc, ev.seq desc
         limit 1
       ), false)
       or not exists (
         select 1
         from c.empresa e
         join c.empresa_fiscal ef
           on ef.empresa_id = e.id
          and ef.deleted_at is null
         where e.tenant_id = v_sf.tenant_id
           and e.id = v_sf.empresa_id
           and e.deleted_at is null
           and ef.certificado_validade_em >= current_date
       ) then
      raise exception using errcode = 'P0001', message = 'Retry bloqueado: homologacao, cancelamento ou certificado deixou de ser valido.';
    end if;
  else
    -- Primeiro claim (ou legado sem evidencia) exige os gates mutaveis atuais.
    v_prontidao := f.fn_nfe_producao_pronta(p_solicitacao_id);
    if not coalesce((v_prontidao->>'pronta')::boolean, false) then
      raise exception using errcode = 'P0001', message = coalesce(v_prontidao->>'motivo', 'Producao bloqueada antes do envio.');
    end if;
    if nullif(v_prontidao->>'homologacao_documento_fiscal_id', '')::uuid
       is distinct from p_homologacao_documento_id then
      raise exception using errcode = '40001', message = 'A homologacao autorizada mudou depois do preflight; recarregue antes de emitir.';
    end if;
  end if;

  v_material := f.fn_nfe_producao_contexto_material(p_solicitacao_id, p_homologacao_documento_id);
  if v_material is null then
    raise exception using errcode = '40001', message = 'O contexto fiscal deixou de existir depois do preflight; nenhuma emissao foi criada ou enviada.';
  end if;
  v_contexto_hash_atual := encode(extensions.digest(convert_to(v_material::text, 'utf8'), 'sha256'), 'hex');
  if v_contexto_hash_atual is distinct from lower(p_contexto_hash) then
    raise exception using errcode = '40001', message = 'O contexto fiscal mudou depois do preflight; nenhuma emissao foi criada ou enviada.';
  end if;
  if v_contexto_hash_primeiro_claim is not null
     and v_contexto_hash_primeiro_claim is distinct from v_contexto_hash_atual then
    raise exception using errcode = '40001', message = 'O contexto fiscal diverge daquele congelado no primeiro claim de producao.';
  end if;

  select hom.payload_enviado into v_homologacao_payload
  from f.documento_fiscal_emissao hom
  where hom.tenant_id = v_sf.tenant_id
    and hom.empresa_id = v_sf.empresa_id
    and hom.solicitacao_id = v_sf.id
    and hom.documento_fiscal_id = p_homologacao_documento_id
    and hom.ambiente = 'HOMOLOGACAO'
    and hom.status = 'AUTORIZADA';
  if jsonb_typeof(v_homologacao_payload) is distinct from 'object'
     or btrim(coalesce(v_homologacao_payload->>'nome_destinatario', ''))
        <> 'NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL'
     or nullif(btrim(coalesce(p_payload->>'nome_destinatario', '')), '') is null
     or btrim(p_payload->>'nome_destinatario')
        = 'NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL'
     or f.fn_nfe_payload_comparavel(v_homologacao_payload)
        is distinct from
        f.fn_nfe_payload_comparavel(p_payload) then
    raise exception using errcode = '22023', message = 'O payload de producao diverge do payload HOM autorizado fora das diferencas legitimas de ambiente.';
  end if;
  if v_emissao.payload_enviado is not null and v_emissao.payload_enviado is distinct from p_payload then
    raise exception using
      errcode = '22023',
      message = 'O payload de retry diverge do payload de producao congelado no primeiro claim.';
  end if;
  if v_emissao.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'ENVIANDO') then
    raise exception using errcode = '55000', message = format('Status %s nao aceita novo claim de envio.', v_emissao.status);
  end if;

  v_produtos := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_produtos');
  v_desconto := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_desconto');
  v_frete := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_frete');
  v_seguro := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_seguro');
  v_outros := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_outras_despesas');
  v_total := f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_total');
  if v_produtos is null or v_desconto is null or v_frete is null
     or v_seguro is null or v_outros is null or v_total is null
     or jsonb_typeof(p_payload->'items') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Payload sem totais monetarios completos para congelar o documento de producao.';
  end if;

  select round(coalesce(sum(si.quantidade * si.valor_unitario), 0), 2),
         round(coalesce(sum(si.valor_desconto), 0), 2), count(*)
    into v_total_esperado, v_desconto_fonte, v_itens_solicitacao
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;
  if v_produtos is distinct from v_total_esperado or v_desconto is distinct from v_desconto_fonte
     or v_frete is distinct from coalesce(v_sf.valor_frete, 0)
     or v_seguro is distinct from coalesce(v_sf.valor_seguro, 0)
     or v_outros is distinct from coalesce(v_sf.valor_outras_despesas, 0) then
    raise exception using errcode = '22023', message = 'Totais do payload divergem dos itens/frete/seguro/despesas congelados na solicitacao.';
  end if;
  select count(*), round(coalesce(sum(coalesce(
           f.fn_perfil_operacao_jsonb_numeric_seguro(x.item, 'ipi_valor'), 0
         )), 0), 2)
    into v_itens_payload, v_ipi
  from jsonb_array_elements(p_payload->'items') x(item);
  if v_itens_payload <> v_itens_solicitacao then
    raise exception using errcode = '22023', message = 'Quantidade de itens do payload diverge da solicitacao congelada.';
  end if;
  -- II (importacao): parcela do vNF, congelada no snapshot da solicitacao (valor_total_ii).
  if coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_total_ii'), 0)
     is distinct from coalesce(nullif(v_sf.operacao_snapshot->>'valor_total_ii', '')::numeric, 0) then
    raise exception using errcode = '22023', message = 'Valor total do II do payload diverge do congelado na solicitacao.';
  end if;
  v_total_esperado := round(v_produtos - v_desconto + v_frete + v_seguro + v_outros + v_ipi
    + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, 'valor_total_ii'), 0), 2);
  if v_total is distinct from v_total_esperado then
    raise exception using errcode = '22023', message = 'Valor total do payload nao fecha produtos/desconto/frete/seguro/despesas/IPI.';
  end if;
  if exists (
    select 1
    from f.solicitacao_item si
    left join lateral (
      select p.item
      from jsonb_array_elements(p_payload->'items') p(item)
      where f.fn_perfil_operacao_jsonb_numeric_seguro(p.item, 'numero_item') = si.ordem
      limit 1
    ) px on true
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and (
        px.item is null
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'quantidade_comercial') is distinct from si.quantidade
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_unitario_comercial') is distinct from si.valor_unitario
        or coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_desconto'), 0) is distinct from si.valor_desconto
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_bruto') is distinct from round(si.quantidade * si.valor_unitario, 2)
        -- vItem leva o IPI desde 10/09/2026 (NT 2025.002-RTC: vNFTot e a soma dos
        -- vItem, rejeicao 1094). O congelamento continua sendo sobre a solicitacao:
        -- quantidade, preco e desconto vem dela, e o IPI vem do proprio payload, que
        -- ja e conferido contra o total logo acima.
        or f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_total_item') is distinct from round(
             si.quantidade * si.valor_unitario - si.valor_desconto
             + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'ipi_valor'), 0)
             -- Importacao (18/09/2026): vItem = vProd + vIPI + vII + vOutro do item.
             + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'ii_valor'), 0)
             + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_outras_despesas'), 0), 2)
      )
  ) then
    raise exception using errcode = '22023', message = 'Quantidade/valor/desconto dos itens do payload divergem da solicitacao congelada.';
  end if;

  update f.documento_fiscal df
  set valor_total = v_total,
      valor_produtos = v_produtos,
      valor_frete = v_frete,
      valor_seguro = v_seguro,
      valor_desconto = v_desconto,
      valor_outros = v_outros,
      updated_at = now()
  where df.tenant_id = v_emissao.tenant_id
    and df.empresa_id = v_emissao.empresa_id
    and df.id = v_emissao.documento_fiscal_id;
  update f.documento_fiscal_item dfi
  -- A coluna continua sendo a mercadoria da linha (o que ela sempre guardou, e o que
  -- a entrada por XML grava): o IPI da nota fica em f.documento_fiscal.valor_total.
  set valor_total = round(
        f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_bruto')
        - coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'valor_desconto'), 0), 2),
      updated_at = now()
  from jsonb_array_elements(p_payload->'items') px(item)
  where dfi.tenant_id = v_emissao.tenant_id
    and dfi.empresa_id = v_emissao.empresa_id
    and dfi.documento_fiscal_id = v_emissao.documento_fiscal_id
    and dfi.item_n = f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'numero_item')::integer;

  update f.documento_fiscal_emissao dfe
  set status = 'ENVIANDO',
      payload_enviado = coalesce(dfe.payload_enviado, p_payload),
      tentativa_count = dfe.tentativa_count + 1,
      ultima_tentativa_em = now(),
      enviado_em = coalesce(dfe.enviado_em, now()),
      codigo_status = null,
      mensagem = null,
      updated_at = now()
  where dfe.tenant_id = v_emissao.tenant_id
    and dfe.empresa_id = v_emissao.empresa_id
    and dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa
  ) values (
    v_emissao.documento_fiscal_id,
    v_emissao.tenant_id,
    v_emissao.empresa_id,
    'ENVIO',
    'ENVIANDO',
    jsonb_build_object(
      'claim_duravel', true,
      'tentativa', v_emissao.tentativa_count,
      'reconciliacao_previa', coalesce(p_reconciliacao_confirmada, false),
      'homologacao_documento_fiscal_id', p_homologacao_documento_id,
      'contexto_hash', v_contexto_hash_atual
    ),
    v_emissao.referencia_externa
  );

  return jsonb_build_object(
    'deve_enviar', true,
    'aguardar', false,
    'criado', v_preparada.criado,
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status,
    'tentativa_count', v_emissao.tentativa_count,
    'payload', v_emissao.payload_enviado
  );
end;
$function$;

-- 2.6 fn_nfe_producao_pronta
CREATE OR REPLACE FUNCTION f.fn_nfe_producao_pronta(p_solicitacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_certificado_validade date;
  v_crt text;
  v_ambito text;
  v_homologacao_documento_id uuid;
  v_homologacao_payload jsonb;
  v_homologacao_autorizado_em timestamptz;
  v_total_itens integer;
  v_invalidos integer;
  v_perfis jsonb;
  v_perfil_unico uuid;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id;

  if not found then
    return jsonb_build_object('pronta', false, 'motivo', 'Solicitacao nao encontrada.');
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;
  if v_sf.status = 'CANCELADA' then
    return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao esta cancelada.');
  end if;
  -- NFS-e (05/09/2026): solicitacao com linha de servico usa o portao proprio.
  if exists (
    select 1 from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id and si.modelo = 'NFSE'
  ) then
    return f.fn_nfse_producao_pronta(p_solicitacao_id);
  end if;

  select dfe.documento_fiscal_id, dfe.payload_enviado, dfe.autorizado_em
    into v_homologacao_documento_id, v_homologacao_payload, v_homologacao_autorizado_em
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.status = 'AUTORIZADA'
  order by dfe.autorizado_em desc nulls last, dfe.updated_at desc, dfe.documento_fiscal_id desc
  limit 1;

  if v_homologacao_documento_id is null then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.'
    );
  end if;
  if coalesce((
    select ev.status = 'ENVIANDO'
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_sf.tenant_id
      and ev.empresa_id = v_sf.empresa_id
      and ev.documento_fiscal_id = v_homologacao_documento_id
      and ev.tipo = 'CANCELAMENTO'
      and not exists (
        select 1 from f.documento_fiscal_evento r
        where r.documento_fiscal_id = ev.documento_fiscal_id and r.tipo = 'CANCELAMENTO' and r.id <> ev.id
          and r.resposta->>'claim_evento_id' = ev.id::text
      )
    order by ev.created_at desc, ev.seq desc
    limit 1
  ), false) then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A NF-e de homologacao vinculada possui cancelamento em andamento.'
    );
  end if;
  if jsonb_typeof(v_homologacao_payload) is distinct from 'object'
     or jsonb_typeof(v_homologacao_payload->'items') is distinct from 'array' then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'A homologacao autorizada nao possui o payload fiscal enviado para comparacao.'
    );
  end if;

  select ef.certificado_validade_em, ef.crt::text
    into v_certificado_validade, v_crt
  from c.empresa e
  join c.empresa_fiscal ef
    on ef.empresa_id = e.id
   and ef.deleted_at is null
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null;

  if not found or v_certificado_validade is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.');
  end if;
  if v_certificado_validade < current_date then
    return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.');
  end if;
  if v_sf.destino_uf_confirmada is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A UF de destino ainda nao foi confirmada.');
  end if;
  if v_sf.revisao_fiscal_confirmada_em is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A conferencia fiscal desta solicitacao ainda nao foi confirmada.');
  end if;
  if v_sf.snapshot_cadastro_em is null
     or jsonb_typeof(v_sf.emitente_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.destinatario_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.operacao_snapshot) is distinct from 'object' then
    return jsonb_build_object('pronta', false, 'motivo', 'O cadastro fiscal ainda nao foi validado e congelado.');
  end if;
  if upper(nullif(btrim(v_sf.destinatario_snapshot->>'uf'), '')) is distinct from v_sf.destino_uf_confirmada
     or nullif(btrim(v_sf.emitente_snapshot->>'uf'), '') is null then
    return jsonb_build_object('pronta', false, 'motivo', 'As UFs do snapshot fiscal nao correspondem ao destino confirmado.');
  end if;
  v_ambito := case
    when upper(btrim(v_sf.emitente_snapshot->>'uf')) = v_sf.destino_uf_confirmada then 'INTERNA'
    else 'INTERESTADUAL'
  end;

  select
    count(*),
    count(*) filter (
      where si.perfil_operacao_id is null
         or po.id is null
         or po.modelo <> 'NFE'
         or po.natureza_operacao <> v_sf.natureza_operacao
         or (po.crt is not null and po.crt is distinct from v_crt)
         or po.ambito_destino is distinct from v_ambito
         or not po.habilitado_producao
         or po.faixa_automacao = 'BLOQUEADO'
         or po.vigencia_inicio > current_date
         or (po.vigencia_fim is not null and po.vigencia_fim < current_date)
         or po.ufs_destino is null
         or not (v_sf.destino_uf_confirmada = any(po.ufs_destino))
         or po.revisao_fiscal_em is null
         or v_homologacao_autorizado_em is null
         or v_homologacao_autorizado_em <= po.revisao_fiscal_em
         or po.producao_decidida_em is null
         or po.producao_decidida_em < po.revisao_fiscal_em
         or po.producao_homologacao_solicitacao_id is distinct from v_sf.id
         or po.producao_homologacao_documento_id is distinct from v_homologacao_documento_id
         or nullif(btrim(po.producao_decisao_justificativa), '') is null
         or not exists (
           select 1
           from f.perfil_operacao_revisao_evento le
           where le.tenant_id = po.tenant_id
             and le.empresa_id = po.empresa_id
             and le.perfil_operacao_id = po.id
             and le.tipo = 'LIBERACAO'
             and le.homologacao_solicitacao_id = v_sf.id
             and le.homologacao_documento_id = v_homologacao_documento_id
             and le.created_at = po.producao_decidida_em
             and le.criado_por is not distinct from po.producao_decidida_por
             and le.justificativa = po.producao_decisao_justificativa
             and le.depois->>'habilitado_producao' = 'true'
             and le.depois->>'producao_homologacao_solicitacao_id' = v_sf.id::text
             and le.depois->>'producao_homologacao_documento_id' = v_homologacao_documento_id::text
             and le.depois->>'cst_ibs_cbs' is not distinct from po.cst_ibs_cbs
             and le.depois->>'cclass_trib' is not distinct from po.cclass_trib
             and f.fn_perfil_operacao_jsonb_numeric_seguro(
               le.depois->'ibs_cbs_json', 'ibs_uf_aliquota'
             ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
               po.ibs_cbs_json, 'ibs_uf_aliquota'
             )
             and f.fn_perfil_operacao_jsonb_numeric_seguro(
               le.depois->'ibs_cbs_json', 'ibs_mun_aliquota'
             ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
               po.ibs_cbs_json, 'ibs_mun_aliquota'
             )
             and f.fn_perfil_operacao_jsonb_numeric_seguro(
               le.depois->'ibs_cbs_json', 'cbs_aliquota'
             ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
               po.ibs_cbs_json, 'cbs_aliquota'
             )
         )
         or (po.indicador_ie_destinatario is not null
             and po.indicador_ie_destinatario is distinct from v_sf.destinatario_snapshot->>'indicador_ie')
         or (po.origem_mercadoria is not null
             and po.origem_mercadoria is distinct from si.origem_mercadoria)
         or (v_ambito = 'INTERNA' and po.cfop_interno is distinct from si.cfop)
         or (v_ambito = 'INTERESTADUAL' and po.cfop_externo is distinct from si.cfop)
         or (po.finalidade_emissao is not null
             and po.finalidade_emissao is distinct from (v_sf.operacao_snapshot->>'finalidade_emissao')::smallint)
         or (po.consumidor_final is not null
             and not (v_sf.operacao_snapshot ? 'excecao_aliquota_destinatario')
             and po.consumidor_final is distinct from (v_sf.operacao_snapshot->>'consumidor_final')::smallint)
         -- Com a excecao o indFinal e 1 por forca dela, nao do perfil.
         or ((v_sf.operacao_snapshot ? 'excecao_aliquota_destinatario')
             and (v_sf.operacao_snapshot->>'consumidor_final')::smallint is distinct from 1)
         or si.cst_ibs_cbs is distinct from po.cst_ibs_cbs
         or si.cclass_trib is distinct from po.cclass_trib
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_uf_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_uf_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_mun_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_mun_aliquota')
         or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'cbs_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'cbs_aliquota')
         or dfi.id is null
         or dfi.cst_ibs_cbs is distinct from po.cst_ibs_cbs
         or dfi.cclass_trib is distinct from po.cclass_trib
         or (po.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_uf_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_uf_aliquota'))
         or (po.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_mun_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_mun_aliquota'))
         or (po.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'cbs_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'cbs_aliquota'))
         or hp.item is null
         or hp.item->>'ibs_cbs_situacao_tributaria' is distinct from po.cst_ibs_cbs
         or hp.item->>'ibs_cbs_classificacao_tributaria' is distinct from po.cclass_trib
         or (po.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_uf_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_uf_aliquota'))
         or (po.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_mun_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'ibs_mun_aliquota'))
         or (po.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'cbs_aliquota')
            is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(po.ibs_cbs_json, 'cbs_aliquota'))
    ),
    coalesce(jsonb_agg(distinct po.id) filter (where po.id is not null), '[]'::jsonb)
  into v_total_itens, v_invalidos, v_perfis
  from f.solicitacao_item si
  left join f.perfil_operacao po
    on po.tenant_id = si.tenant_id
   and (po.empresa_id = si.empresa_id or po.empresa_id is null)
   and po.id = si.perfil_operacao_id
  left join f.documento_fiscal_item dfi
    on dfi.tenant_id = si.tenant_id
   and dfi.empresa_id = si.empresa_id
   and dfi.documento_fiscal_id = v_homologacao_documento_id
   and dfi.item_n = si.ordem
  left join lateral (
    select p.item
    from jsonb_array_elements(v_homologacao_payload->'items') p(item)
    where p.item->>'numero_item' = si.ordem::text
    limit 1
  ) hp on true
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if v_total_itens = 0 then
    return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao nao possui itens fiscais.');
  end if;
  if v_invalidos > 0 then
    return jsonb_build_object(
      'pronta', false,
      'motivo', 'Perfis precisam estar liberados para esta homologacao e coincidir exatamente com os campos fiscais autorizados.'
    );
  end if;

  if jsonb_array_length(v_perfis) = 1 then
    v_perfil_unico := (v_perfis->>0)::uuid;
  end if;

  return jsonb_build_object(
    'pronta', true,
    'tenant_id', v_sf.tenant_id,
    'empresa_id', v_sf.empresa_id,
    'homologacao_documento_fiscal_id', v_homologacao_documento_id,
    'perfil_operacao_id', v_perfil_unico,
    'perfil_operacao_ids', v_perfis
  );
end;
$function$;

-- 2.7 fn_nfse_cancelamento_claim
CREATE OR REPLACE FUNCTION f.fn_nfse_cancelamento_claim(p_documento_fiscal_id uuid, p_justificativa text, p_reconciliacao_claim_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_prazo integer;
  v_regra text;
  v_limite timestamptz;
  v_ult record;
  v_evento_claim_id uuid;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode reservar o cancelamento.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 255 then
    raise exception using errcode = '22023', message = 'A justificativa deve ter entre 15 e 255 caracteres.';
  end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE';
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  perform 1 from f.solicitacao_faturamento sf where sf.id = v_emissao.solicitacao_id for update;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id for update;

  select ef.prazo_cancelamento_nfse_horas, ef.prazo_cancelamento_nfse_regra into v_prazo, v_regra
  from c.empresa_fiscal ef where ef.empresa_id = v_emissao.empresa_id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  v_limite := case when v_emissao.autorizado_em is null then null else f.fn_nfse_cancelamento_limite(v_emissao.empresa_id, v_emissao.autorizado_em) end;
  if v_emissao.ambiente = 'PRODUCAO' and v_regra = 'HORAS' and v_prazo is null then
    raise exception using errcode = '55000', message = 'Prazo de cancelamento da NFS-e nao confirmado pelo contador; em producao use a substituicao.';
  end if;
  if v_limite is not null and now() > v_limite then
    raise exception using errcode = '55000', message = case when v_regra = 'MES_EMISSAO'
      then format('Prazo de cancelamento encerrado (ate %s, fim do mes de emissao); use a substituicao.', to_char(v_limite at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'))
      else format('Prazo de cancelamento (%s h) encerrado; use a substituicao.', v_prazo) end;
  end if;

  select ev.id, ev.status, ev.created_at, ev.justificativa into v_ult
  from f.documento_fiscal_evento ev
  where ev.tenant_id = v_emissao.tenant_id and ev.empresa_id = v_emissao.empresa_id and ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.tipo = 'CANCELAMENTO'
  order by ev.created_at desc, ev.seq desc limit 1;
  if v_ult.status = 'ENVIANDO' and v_ult.created_at >= now() - interval '2 minutes' then
    return jsonb_build_object('deve_cancelar', false, 'aguardar', true, 'deve_reconciliar', false, 'evento_claim_id', v_ult.id,
      'justificativa_claim', v_ult.justificativa, 'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa, 'status', 'ENVIANDO');
  end if;
  if v_ult.status = 'ENVIANDO' then
    if p_reconciliacao_claim_id is distinct from v_ult.id then
      return jsonb_build_object('deve_cancelar', false, 'aguardar', false, 'deve_reconciliar', true, 'evento_claim_id', v_ult.id,
        'justificativa_claim', v_ult.justificativa, 'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa, 'status', 'ENVIANDO');
    end if;
    if v_ult.justificativa is distinct from v_justificativa then
      raise exception using errcode = '22023', message = 'A justificativa do retry deve ser a mesma do claim reconciliado.';
    end if;
  elsif p_reconciliacao_claim_id is not null then
    raise exception using errcode = '55000', message = 'O claim informado ja nao e o cancelamento pendente mais recente.';
  end if;
  if v_emissao.status <> 'AUTORIZADA' then
    raise exception using errcode = '55000', message = format('Status %s nao permite cancelamento.', v_emissao.status);
  end if;
  insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, status, resposta, referencia_externa)
  values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'CANCELAMENTO', v_justificativa, 'ENVIANDO',
          jsonb_build_object('claim_duravel', true, 'modelo', 'NFSE', 'ambiente', v_emissao.ambiente, 'prazo_horas', v_prazo, 'prazo_regra', v_regra, 'prazo_limite', v_limite), v_emissao.referencia_externa)
  returning id into v_evento_claim_id;
  return jsonb_build_object('deve_cancelar', true, 'aguardar', false, 'deve_reconciliar', false, 'evento_claim_id', v_evento_claim_id,
    'justificativa_claim', v_justificativa, 'documento_fiscal_id', v_emissao.documento_fiscal_id, 'referencia_externa', v_emissao.referencia_externa, 'status', 'ENVIANDO');
end;
$function$;

-- 2.8 fn_nfse_cancelamento_finalizar
CREATE OR REPLACE FUNCTION f.fn_nfse_cancelamento_finalizar(p_documento_fiscal_id uuid, p_evento_claim_id uuid, p_status text, p_justificativa text, p_protocolo text DEFAULT NULL::text, p_resposta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_status text := upper(btrim(coalesce(p_status, '')));
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_claim record;
  v_ult record;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal pode concluir o cancelamento.';
  end if;
  if v_status not in ('AUTORIZADA', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '22023', message = 'Status final de cancelamento invalido.';
  end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE';
  if not found then raise exception using errcode = 'P0002', message = 'Emissao de NFS-e nao encontrada.'; end if;
  perform 1 from f.solicitacao_faturamento sf where sf.id = v_emissao.solicitacao_id for update;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id for update;
  if p_evento_claim_id is null then
    raise exception using errcode = '22023', message = 'O identificador do claim de cancelamento e obrigatorio.';
  end if;
  if v_emissao.status = 'CANCELADA' and v_status = 'AUTORIZADA' then
    if exists (select 1 from f.documento_fiscal_evento ev where ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.tipo = 'CANCELAMENTO' and ev.status = 'AUTORIZADA' and ev.resposta->>'claim_evento_id' = p_evento_claim_id::text) then
      return jsonb_build_object('ok', true, 'idempotente', true, 'status', 'CANCELADA');
    end if;
    raise exception using errcode = '55000', message = 'Resposta tardia pertence a outro claim de cancelamento.';
  end if;
  select ev.id, ev.status into v_ult from f.documento_fiscal_evento ev
  where ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.tipo = 'CANCELAMENTO' order by ev.created_at desc, ev.seq desc limit 1;
  if v_emissao.status <> 'AUTORIZADA' or v_ult.status is distinct from 'ENVIANDO' or v_ult.id is distinct from p_evento_claim_id then
    raise exception using errcode = '55000', message = 'Cancelamento sem claim duravel correspondente.';
  end if;
  select ev.id, ev.justificativa into v_claim from f.documento_fiscal_evento ev
  where ev.documento_fiscal_id = v_emissao.documento_fiscal_id and ev.id = p_evento_claim_id and ev.tipo = 'CANCELAMENTO' and ev.status = 'ENVIANDO';
  if not found or v_claim.justificativa is distinct from v_justificativa then
    raise exception using errcode = '22023', message = 'Justificativa ou claim de cancelamento nao corresponde a reserva original.';
  end if;
  insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, protocolo, status, resposta, referencia_externa)
  values (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'CANCELAMENTO', v_justificativa, nullif(btrim(p_protocolo), ''), v_status,
          coalesce(p_resposta, '{}'::jsonb) || jsonb_build_object('claim_evento_id', p_evento_claim_id, 'modelo', 'NFSE'), v_emissao.referencia_externa);
  if v_status = 'AUTORIZADA' then
    update f.documento_fiscal_emissao dfe set status = 'CANCELADA', protocolo = coalesce(nullif(btrim(p_protocolo), ''), dfe.protocolo),
      resposta = coalesce(p_resposta, dfe.resposta), mensagem = 'Cancelamento autorizado.', updated_at = now()
    where dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
    update f.solicitacao_faturamento sf set status = 'CANCELADA', updated_at = now() where sf.id = v_emissao.solicitacao_id;
    update f.dps_numero_log set resultado = 'CANCELADO', mensagem = v_justificativa, updated_at = now()
    where documento_fiscal_id = v_emissao.documento_fiscal_id and serie = v_emissao.dps_serie and numero = v_emissao.dps_numero;
    if v_emissao.ambiente = 'PRODUCAO' then
      update f.documento_fiscal set nfse_status = 'CANCELADA', updated_at = now() where id = v_emissao.documento_fiscal_id;
      perform f.fn_nfse_titulo_cancelar(v_emissao.documento_fiscal_id, 'NFS-e cancelada: ' || v_justificativa);
    end if;
    -- Homologacao: documento continua RASCUNHO; o saldo volta porque a emissao esta CANCELADA.
  else
    update f.documento_fiscal_emissao dfe set resposta = coalesce(p_resposta, dfe.resposta),
      mensagem = 'Cancelamento nao autorizado; NFS-e permanece autorizada.', updated_at = now()
    where dfe.documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;
  return jsonb_build_object('ok', v_status = 'AUTORIZADA', 'idempotente', false, 'status', case when v_status = 'AUTORIZADA' then 'CANCELADA' else 'AUTORIZADA' end);
end;
$function$;

-- 2.9 fn_perfil_operacao_nfe_homologacoes_listar
CREATE OR REPLACE FUNCTION f.fn_perfil_operacao_nfe_homologacoes_listar(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_homologacoes jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select po.* into v_perfil
  from f.perfil_operacao po
  where po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
    and po.id = p_perfil_id
    and po.modelo in ('NFE', 'NFSE');

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Perfil fiscal nao encontrado no tenant e empresa ativos.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'solicitacao_id', h.solicitacao_id,
        'documento_fiscal_id', h.documento_fiscal_id,
        'referencia_externa', h.referencia_externa,
        'autorizado_em', h.autorizado_em,
        'cancelamento_em_andamento', h.cancelamento_em_andamento,
        'apos_ultima_revisao', (
          v_perfil.revisao_fiscal_em is not null
          and h.autorizado_em > v_perfil.revisao_fiscal_em
        )
      )
      order by h.autorizado_em desc
    ),
    '[]'::jsonb
  ) into v_homologacoes
  from (
    select distinct on (sf.id)
      sf.id as solicitacao_id,
      dfe.documento_fiscal_id,
      dfe.referencia_externa,
      dfe.autorizado_em,
      coalesce((
        select ev.status = 'ENVIANDO'
        from f.documento_fiscal_evento ev
        where ev.tenant_id = dfe.tenant_id
          and ev.empresa_id = dfe.empresa_id
          and ev.documento_fiscal_id = dfe.documento_fiscal_id
          and ev.tipo = 'CANCELAMENTO'
        order by ev.created_at desc, ev.seq desc
        limit 1
      ), false) as cancelamento_em_andamento
    from f.solicitacao_faturamento sf
    join f.solicitacao_item si
      on si.tenant_id = sf.tenant_id
     and si.empresa_id = sf.empresa_id
     and si.solicitacao_id = sf.id
     and si.perfil_operacao_id = v_perfil.id
    join f.documento_fiscal_emissao dfe
      on dfe.tenant_id = sf.tenant_id
     and dfe.empresa_id = sf.empresa_id
     and dfe.solicitacao_id = sf.id
     and dfe.ambiente = 'HOMOLOGACAO'
     and dfe.status = 'AUTORIZADA'
     and dfe.autorizado_em is not null
    where sf.tenant_id = v_scope.tenant_id
      and sf.empresa_id = v_scope.empresa_id
      and sf.status <> 'CANCELADA'
    order by sf.id, dfe.autorizado_em desc, dfe.updated_at desc, dfe.documento_fiscal_id desc
  ) h;

  return jsonb_build_object(
    'tenant_id', v_scope.tenant_id,
    'empresa_id', v_scope.empresa_id,
    'perfil_id', v_perfil.id,
    'homologacoes', v_homologacoes
  );
end;
$function$;

-- 2.10 fn_perfil_operacao_nfe_liberar_producao
CREATE OR REPLACE FUNCTION f.fn_perfil_operacao_nfe_liberar_producao(p_perfil_id uuid, p_solicitacao_id uuid, p_justificativa text, p_confirmacao boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_solicitacao f.solicitacao_faturamento%rowtype;
  v_homologacao f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_itens integer;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '')
       in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao de escrita para liberar perfis fiscais.';
  end if;
  if p_perfil_id is null or p_solicitacao_id is null then
    raise exception using errcode = '22023', message = 'Perfil e solicitacao de homologacao sao obrigatorios.';
  end if;
  if not coalesce(p_confirmacao, false) then
    raise exception using errcode = '22023', message = 'Confirme explicitamente a liberacao para producao.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then
    raise exception using errcode = '22023', message = 'A justificativa da liberacao deve ter entre 15 e 1000 caracteres.';
  end if;

  select po.* into v_perfil
  from f.perfil_operacao po
  where po.id = p_perfil_id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
    and po.modelo = 'NFE'
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Perfil NF-e nao encontrado no tenant e empresa ativos.';
  end if;
  if v_perfil.revisao_fiscal_em is null
     or v_perfil.revisao_fiscal_por is null
     or nullif(btrim(v_perfil.revisao_fiscal_justificativa), '') is null then
    raise exception using errcode = '22023', message = 'O perfil precisa ser revisado antes da homologacao e da liberacao.';
  end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' then
    raise exception using errcode = '22023', message = 'Perfil bloqueado nao pode ser liberado para producao.';
  end if;
  if v_perfil.vigencia_inicio > current_date
     or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date) then
    raise exception using errcode = '22023', message = 'Somente perfil vigente pode ser liberado para producao.';
  end if;
  if v_perfil.evidencia_id is null then
    raise exception using errcode = '22023', message = 'A evidencia fiscal do perfil precisa estar vinculada antes da producao.';
  end if;
  if v_perfil.ambito_destino is null
     or v_perfil.ufs_destino is null
     or cardinality(v_perfil.ufs_destino) = 0 then
    raise exception using errcode = '22023', message = 'Ambito e UFs de destino precisam estar confirmados antes da producao.';
  end if;
  if v_perfil.ambito_destino = 'INTERNA' and coalesce(v_perfil.cfop_interno, '') !~ '^[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'CFOP interno valido e obrigatorio para este perfil.';
  end if;
  if v_perfil.ambito_destino = 'INTERESTADUAL' and coalesce(v_perfil.cfop_externo, '') !~ '^[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'CFOP interestadual valido e obrigatorio para este perfil.';
  end if;
  if v_perfil.origem_mercadoria is null then
    raise exception using errcode = '22023', message = 'Origem da mercadoria precisa estar confirmada antes da producao.';
  end if;
  if coalesce(v_perfil.crt, '') !~ '^[123]$' then
    raise exception using errcode = '22023', message = 'CRT precisa estar confirmado antes da producao.';
  end if;
  if v_perfil.crt = '3' and coalesce(v_perfil.cst_icms, '') !~ '^[0-9]{2}$' then
    raise exception using errcode = '22023', message = 'CST ICMS valido e obrigatorio para regime normal.';
  end if;
  if v_perfil.crt in ('1', '2') and coalesce(v_perfil.csosn, '') !~ '^[0-9]{3}$' then
    raise exception using errcode = '22023', message = 'CSOSN valido e obrigatorio para Simples Nacional.';
  end if;
  if v_perfil.cbenef_aplicacao = 'NAO_CONFIRMADO' then
    raise exception using errcode = '22023', message = 'A aplicacao de cBenef precisa estar confirmada antes da producao.';
  end if;
  if coalesce(v_perfil.cst_pis, '') !~ '^[0-9]{2}$'
     or coalesce(v_perfil.cst_cofins, '') !~ '^[0-9]{2}$' then
    raise exception using errcode = '22023', message = 'CST de PIS e COFINS precisam estar confirmados antes da producao.';
  end if;
  if v_perfil.finalidade_emissao is null or v_perfil.consumidor_final is null then
    raise exception using errcode = '22023', message = 'Finalidade da emissao e consumidor final precisam estar confirmados antes da producao.';
  end if;
  if v_perfil.cst_ibs_cbs !~ '^[0-9]{3}$'
     or v_perfil.cclass_trib !~ '^[0-9]{6}$'
     or left(v_perfil.cclass_trib, 3) <> v_perfil.cst_ibs_cbs
     or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota') is null
     or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota') is null
     or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota') is null then
    raise exception using errcode = '22023', message = 'Os cinco campos IBS/CBS precisam estar completos antes da liberacao.';
  end if;
  if not exists (
    select 1
    from f.perfil_operacao_revisao_evento re
    where re.tenant_id = v_scope.tenant_id
      and re.empresa_id = v_scope.empresa_id
      and re.perfil_operacao_id = v_perfil.id
      and re.tipo = 'REVISAO'
      and re.created_at = v_perfil.revisao_fiscal_em
      and re.criado_por is not distinct from v_perfil.revisao_fiscal_por
      and re.justificativa = v_perfil.revisao_fiscal_justificativa
      and re.depois->>'habilitado_producao' = 'false'
      and re.depois->>'cst_ibs_cbs' is not distinct from v_perfil.cst_ibs_cbs
      and re.depois->>'cclass_trib' is not distinct from v_perfil.cclass_trib
      and f.fn_perfil_operacao_jsonb_numeric_seguro(
        re.depois->'ibs_cbs_json', 'ibs_uf_aliquota'
      ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
        v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'
      )
      and f.fn_perfil_operacao_jsonb_numeric_seguro(
        re.depois->'ibs_cbs_json', 'ibs_mun_aliquota'
      ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
        v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'
      )
      and f.fn_perfil_operacao_jsonb_numeric_seguro(
        re.depois->'ibs_cbs_json', 'cbs_aliquota'
      ) is not distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(
        v_perfil.ibs_cbs_json, 'cbs_aliquota'
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'A ultima revisao do perfil nao possui evento de auditoria equivalente.';
  end if;

  select sf.* into v_solicitacao
  from f.solicitacao_faturamento sf
  where sf.tenant_id = v_scope.tenant_id
    and sf.empresa_id = v_scope.empresa_id
    and sf.id = p_solicitacao_id
    and sf.status <> 'CANCELADA';

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao ativa nao encontrada no tenant e empresa atuais.';
  end if;
  if v_solicitacao.natureza_operacao is distinct from v_perfil.natureza_operacao then
    raise exception using errcode = '22023', message = 'A natureza da solicitacao nao corresponde ao perfil selecionado.';
  end if;

  select dfe.* into v_homologacao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_scope.tenant_id
    and dfe.empresa_id = v_scope.empresa_id
    and dfe.solicitacao_id = v_solicitacao.id
    and dfe.ambiente = 'HOMOLOGACAO'
    and dfe.status = 'AUTORIZADA'
    and dfe.autorizado_em is not null
    and dfe.autorizado_em > v_perfil.revisao_fiscal_em
  order by dfe.autorizado_em desc, dfe.updated_at desc, dfe.documento_fiscal_id desc
  limit 1;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'A solicitacao precisa de NF-e AUTORIZADA em homologacao depois da ultima revisao do perfil.';
  end if;
  if coalesce((
    select ev.status = 'ENVIANDO'
    from f.documento_fiscal_evento ev
    where ev.tenant_id = v_scope.tenant_id
      and ev.empresa_id = v_scope.empresa_id
      and ev.documento_fiscal_id = v_homologacao.documento_fiscal_id
      and ev.tipo = 'CANCELAMENTO'
    order by ev.created_at desc, ev.seq desc
    limit 1
  ), false) then
    raise exception using
      errcode = '55000',
      message = 'A NF-e de homologacao selecionada possui cancelamento em andamento.';
  end if;
  if jsonb_typeof(v_homologacao.payload_enviado) is distinct from 'object'
     or jsonb_typeof(v_homologacao.payload_enviado->'items') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'O payload autorizado em homologacao nao permite conferir os itens.';
  end if;

  select count(*) into v_itens
  from f.solicitacao_item si
  where si.tenant_id = v_scope.tenant_id
    and si.empresa_id = v_scope.empresa_id
    and si.solicitacao_id = v_solicitacao.id
    and si.perfil_operacao_id = v_perfil.id;

  if v_itens = 0 then
    raise exception using errcode = '22023', message = 'A solicitacao homologada nao possui item ligado a este perfil.';
  end if;

  if exists (
    select 1
    from f.solicitacao_item si
    left join f.documento_fiscal_item dfi
      on dfi.tenant_id = si.tenant_id
     and dfi.empresa_id = si.empresa_id
     and dfi.documento_fiscal_id = v_homologacao.documento_fiscal_id
     and dfi.item_n = si.ordem
    left join lateral (
      select p.item
      from jsonb_array_elements(v_homologacao.payload_enviado->'items') p(item)
      where p.item->>'numero_item' = si.ordem::text
      limit 1
    ) hp on true
    where si.tenant_id = v_scope.tenant_id
      and si.empresa_id = v_scope.empresa_id
      and si.solicitacao_id = v_solicitacao.id
      and si.perfil_operacao_id = v_perfil.id
      and (
        si.cst_ibs_cbs is distinct from v_perfil.cst_ibs_cbs
        or si.cclass_trib is distinct from v_perfil.cclass_trib
        or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_uf_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'ibs_mun_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota')
        or f.fn_perfil_operacao_jsonb_numeric_seguro(si.ibs_cbs_json, 'cbs_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota')
        or dfi.id is null
        or dfi.cst_ibs_cbs is distinct from v_perfil.cst_ibs_cbs
        or dfi.cclass_trib is distinct from v_perfil.cclass_trib
        or (v_perfil.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_uf_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'))
        or (v_perfil.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'ibs_mun_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'))
        or (v_perfil.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(dfi.ibs_cbs_json, 'cbs_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota'))
        or hp.item is null
        or hp.item->>'ibs_cbs_situacao_tributaria' is distinct from v_perfil.cst_ibs_cbs
        or hp.item->>'ibs_cbs_classificacao_tributaria' is distinct from v_perfil.cclass_trib
        or (v_perfil.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_uf_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'))
        or (v_perfil.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'ibs_mun_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'))
        or (v_perfil.cst_ibs_cbs <> '410' and f.fn_perfil_operacao_jsonb_numeric_seguro(hp.item, 'cbs_aliquota')
           is distinct from f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota'))
      )
  ) then
    raise exception using
      errcode = '22023',
      message = 'Os cinco campos IBS/CBS nao coincidem exatamente entre perfil, solicitacao, snapshot e payload homologado.';
  end if;

  update f.perfil_operacao po
  set habilitado_producao = true,
      producao_decidida_em = now(),
      producao_decidida_por = v_scope.usuario_id,
      producao_decisao_justificativa = v_justificativa,
      producao_homologacao_solicitacao_id = v_solicitacao.id,
      producao_homologacao_documento_id = v_homologacao.documento_fiscal_id
  where po.id = v_perfil.id
    and po.tenant_id = v_scope.tenant_id
    and po.empresa_id = v_scope.empresa_id
  returning po.* into v_depois;

  insert into f.perfil_operacao_revisao_evento (
    tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois,
    homologacao_solicitacao_id, homologacao_documento_id,
    justificativa, criado_por
  ) values (
    v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'LIBERACAO',
    to_jsonb(v_perfil), to_jsonb(v_depois),
    v_solicitacao.id, v_homologacao.documento_fiscal_id,
    v_justificativa, v_scope.usuario_id
  );

  return jsonb_build_object(
    'perfil_id', v_perfil.id,
    'solicitacao_id', v_solicitacao.id,
    'homologacao_documento_fiscal_id', v_homologacao.documento_fiscal_id,
    'habilitado_producao', true,
    'mensagem', 'Perfil liberado para esta solicitacao apos equivalencia exata com a NF-e homologada.'
  );
end;
$function$;

-- 2.11 listar_historico_inconsistencia_financeira
CREATE OR REPLACE FUNCTION f.listar_historico_inconsistencia_financeira(p_tenant_id uuid, p_empresa_id uuid, p_titulo_id uuid DEFAULT NULL::uuid, p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'f', 'public', 'a', 'c'
 SET row_security TO 'off'
AS $function$
declare
  v_limite integer := greatest(1, least(coalesce(p_limite, 100), 500));
  v_resultado jsonb;
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id e empresa_id sao obrigatorios.';
  end if;

  if auth.uid() is null
     and coalesce(auth.role(), '') <> 'service_role'
  then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado.';
  end if;

  if auth.uid() is not null
     and not f.pode_ler_regras_rateio(p_tenant_id, p_empresa_id)
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para consultar a auditoria desta empresa.';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ev.id,
      'evento', ev.evento,
      'tituloId', case
        when ev.ref_table = 'f.titulo' then ev.ref_id
        else null
      end,
      'referenciaTabela', ev.ref_table,
      'referenciaId', ev.ref_id,
      'payload', ev.payload,
      'criadoEm', ev.created_at,
      'criadoPor', ev.created_by
    )
    order by ev.created_at desc, ev.seq desc
  ), '[]'::jsonb)
    into v_resultado
  from (
    select evento.*
    from f.evento_financeiro evento
    where evento.tenant_id = p_tenant_id
      and evento.empresa_id = p_empresa_id
      and evento.evento like 'INCONSISTENCIA_FINANCEIRA_%'
      and (
        p_titulo_id is null
        or (
          evento.ref_table = 'f.titulo'
          and evento.ref_id = p_titulo_id
        )
        or evento.payload -> 'titulosOrigem' @> to_jsonb(
          array[p_titulo_id]::uuid[]
        )
      )
    order by evento.created_at desc, evento.id desc
    limit v_limite
  ) ev;

  return v_resultado;
end;
$function$;

-- 2.12 trg_nfe_bloquear_producao_cancelamento_hom_pendente
CREATE OR REPLACE FUNCTION f.trg_nfe_bloquear_producao_cancelamento_hom_pendente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_status text;
begin
  if new.ambiente <> 'PRODUCAO' or new.status = 'CANCELADA' or new.solicitacao_id is null then
    return new;
  end if;

  select ev.status into v_status
  from f.documento_fiscal_emissao hom
  join f.documento_fiscal_evento ev
    on ev.tenant_id = hom.tenant_id
   and ev.empresa_id = hom.empresa_id
   and ev.documento_fiscal_id = hom.documento_fiscal_id
   and ev.tipo = 'CANCELAMENTO'
   and not exists (
     select 1 from f.documento_fiscal_evento r
     where r.documento_fiscal_id = ev.documento_fiscal_id and r.tipo = 'CANCELAMENTO' and r.id <> ev.id
       and r.resposta->>'claim_evento_id' = ev.id::text
   )
  where hom.tenant_id = new.tenant_id
    and hom.empresa_id = new.empresa_id
    and hom.solicitacao_id = new.solicitacao_id
    and hom.ambiente = 'HOMOLOGACAO'
  order by ev.created_at desc, ev.seq desc
  limit 1;

  if v_status = 'ENVIANDO' then
    raise exception using
      errcode = '55000',
      message = 'Promocao bloqueada: o cancelamento da homologacao esta em andamento.';
  end if;
  return new;
end;
$function$;

-- 3. Conferencia.
do $assert$
declare
  v_fn text;
  v_def text;
  v_guarda integer;
  v_espera integer;
begin
  foreach v_fn in array array['fn_nfe_cancelamento_producao_claim', 'fn_nfe_cancelamento_producao_finalizar', 'fn_nfe_cancelamento_homologacao_claim', 'fn_nfe_cancelamento_homologacao_finalizar', 'fn_nfe_producao_preparar_e_claimar', 'fn_nfe_producao_pronta', 'fn_nfse_cancelamento_claim', 'fn_nfse_cancelamento_finalizar', 'fn_perfil_operacao_nfe_homologacoes_listar', 'fn_perfil_operacao_nfe_liberar_producao', 'listar_historico_inconsistencia_financeira', 'trg_nfe_bloquear_producao_cancelamento_hom_pendente'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'f' and p.proname = v_fn;
    if v_def is null then raise exception 'funcao f.% ausente', v_fn; end if;
    if v_def like '%order by ev.created_at desc, ev.id desc%' then raise exception 'f.% ainda desempata por uuid', v_fn; end if;
    if v_def not like '%order by ev.created_at desc, ev.seq desc%' then raise exception 'f.% nao ordena por seq', v_fn; end if;
  end loop;
  foreach v_fn in array array['fn_nfe_cancelamento_producao_claim', 'fn_nfe_cancelamento_homologacao_claim'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'f' and p.proname = v_fn;
    v_guarda := position('nao permite cancelamento' in v_def);
    v_espera := position('interval ''2 minutes''' in v_def);
    if v_guarda = 0 or v_espera = 0 or v_guarda > v_espera then
      raise exception 'f.%: a guarda por status nao vem antes do ramo de espera (% / %)', v_fn, v_guarda, v_espera;
    end if;
  end loop;
  foreach v_fn in array array['fn_nfe_cancelamento_producao_claim', 'fn_nfe_cancelamento_homologacao_claim',
      'fn_nfe_cancelamento_producao_finalizar', 'fn_nfe_cancelamento_homologacao_finalizar', 'fn_nfe_producao_pronta',
      'fn_nfe_producao_preparar_e_claimar', 'trg_nfe_bloquear_producao_cancelamento_hom_pendente'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'f' and p.proname = v_fn;
    if v_def not like '%r.resposta->>''claim_evento_id'' = ev.id::text%' then raise exception 'f.% ainda le claim com resultado como pendente', v_fn; end if;
  end loop;
  if exists (select 1 from f.documento_fiscal_evento where seq is null) then raise exception 'eventos sem seq'; end if;
end;
$assert$;
