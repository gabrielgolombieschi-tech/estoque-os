-- Bateria de cancelamento em homologacao (05/09/2026) revelou dois problemas.
--
-- 1. A NF-e 2/1 (fora das 24h) teve o cancelamento REJEITADO pela SEFAZ
--    (cStat 501, "Prazo de Cancelamento Superior ao Previsto na Legislacao"),
--    mas a Focus respondeu 2xx com status "erro_cancelamento" e a Edge Function
--    decidia pelo HTTP: gravou CANCELAMENTO/AUTORIZADA, marcou a emissao como
--    CANCELADA e o documento como CANCELADA. A Edge foi corrigida para decidir
--    pelo corpo ("cancelado"); aqui a 2/1 volta ao estado real (AUTORIZADA) com
--    um evento corretivo REJEITADA, ja que f.documento_fiscal_evento e
--    append-only.
--
-- 2. O cancelamento de homologacao gravava f.documento_fiscal.nfe_status =
--    'CANCELADA'. Como o documento tem numero, ele passava a entrar no livro de
--    saidas e no analitico ("CANCELADA com numero" = documento que existiu).
--    Homologacao nao tem valor fiscal: o documento permanece RASCUNHO; so a
--    emissao (f.documento_fiscal_emissao) muda para CANCELADA. A 2/12 (cancelada
--    de verdade na SEFAZ, protocolo 342260000903334) volta a RASCUNHO. O
--    analitico tambem passa a ignorar documento cuja unica emissao e de
--    homologacao, independentemente do nfe_status.

create or replace function f.fn_nfe_cancelamento_homologacao_finalizar(
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

-- Reparo da NF-e 2/1 (chave 42260913671448000189550020000000011615133155):
-- a SEFAZ rejeitou o cancelamento (501); a nota continua AUTORIZADA.
do $$
declare
  v_doc uuid := '77ebc33e-9145-48f5-83cd-8a982575fc17';
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_evento_errado f.documento_fiscal_evento%rowtype;
begin
  select * into v_emissao
  from f.documento_fiscal_emissao
  where documento_fiscal_id = v_doc and ambiente = 'HOMOLOGACAO';
  if not found then
    return; -- banco local sem os dados de producao
  end if;

  select * into v_evento_errado
  from f.documento_fiscal_evento
  where documento_fiscal_id = v_doc
    and tipo = 'CANCELAMENTO'
    and status = 'AUTORIZADA'
    and resposta->>'status' = 'erro_cancelamento'
  order by created_at desc
  limit 1;
  if not found then
    return; -- ja reparado ou nunca aconteceu
  end if;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, justificativa, protocolo,
    status, resposta, referencia_externa
  ) values (
    v_doc, v_emissao.tenant_id, v_emissao.empresa_id,
    'CANCELAMENTO', v_evento_errado.justificativa, null,
    'REJEITADA',
    (v_evento_errado.resposta - 'claim_evento_id')
      || jsonb_build_object(
           'claim_evento_id', v_evento_errado.resposta->>'claim_evento_id',
           'correcao_de_evento_id', v_evento_errado.id,
           'correcao_motivo', 'A Focus respondeu 2xx com status erro_cancelamento (cStat 501) e a Edge Function gravou AUTORIZADA pelo HTTP. A SEFAZ rejeitou o cancelamento; a NF-e permanece autorizada.'
         ),
    v_emissao.referencia_externa
  );

  update f.documento_fiscal_emissao
  set status = 'AUTORIZADA',
      mensagem = 'Cancelamento nao autorizado; NF-e de homologacao permanece autorizada.',
      updated_at = now()
  where documento_fiscal_id = v_doc and ambiente = 'HOMOLOGACAO';
end;
$$;

-- Documentos de homologacao cancelados na SEFAZ voltam a RASCUNHO (2/1 e 2/12).
update f.documento_fiscal df
set nfe_status = 'RASCUNHO', updated_at = now()
where df.nfe_status = 'CANCELADA'
  and df.numero is not null
  and exists (
    select 1 from f.documento_fiscal_emissao e
    where e.documento_fiscal_id = df.id and e.ambiente = 'HOMOLOGACAO'
  )
  and not exists (
    select 1 from f.documento_fiscal_emissao e
    where e.documento_fiscal_id = df.id and e.ambiente = 'PRODUCAO'
  );

-- Analitico: documento cuja unica emissao e de homologacao nunca e faturamento,
-- qualquer que seja o nfe_status.
CREATE OR REPLACE FUNCTION f.faturamento_analitico_documentos(p_tenant_id uuid, p_empresa_ids uuid[], p_data_inicio date, p_data_fim_exclusiva date)
 RETURNS TABLE(id uuid, emissao_date date, competencia_date date, empresa_id uuid, cliente_id integer, cliente_nome text, valor_total numeric, modelo text, nfe_status text, nfse_status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'f', 'public', 'a', 'c'
 SET row_security TO 'off'
AS $function$
declare
  v_empresa_ids uuid[];
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null
     or p_empresa_ids is null
     or cardinality(p_empresa_ids) = 0
     or p_data_inicio is null
     or p_data_fim_exclusiva is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id, empresas e periodo sao obrigatorios';
  end if;

  if public.current_tenant_id() is distinct from p_tenant_id then
    raise exception using
      errcode = '42501',
      message = 'Tenant informado nao corresponde ao contexto ativo';
  end if;

  if p_data_fim_exclusiva <= p_data_inicio
     or p_data_fim_exclusiva > (p_data_inicio + interval '20 years')::date then
    raise exception using
      errcode = '22023',
      message = 'Periodo invalido para o analitico de faturamento';
  end if;

  select array_agg(distinct requested.empresa_id order by requested.empresa_id)
    into v_empresa_ids
  from unnest(p_empresa_ids) as requested(empresa_id)
  where requested.empresa_id is not null;

  if v_empresa_ids is null or cardinality(v_empresa_ids) = 0 then
    raise exception using
      errcode = '22023',
      message = 'Informe ao menos uma empresa valida';
  end if;

  if exists (
    select 1
    from unnest(v_empresa_ids) as requested(empresa_id)
    left join c.empresa empresa
      on empresa.id = requested.empresa_id
     and empresa.tenant_id = p_tenant_id
     and empresa.deleted_at is null
    where empresa.id is null
       or not f.has_finance_access(p_tenant_id, requested.empresa_id)
  ) then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para uma ou mais empresas solicitadas';
  end if;

  return query
  select
    documento.id,
    documento.emissao_date,
    documento.competencia_date,
    documento.empresa_id,
    documento.cliente_id,
    cliente.nome::text as cliente_nome,
    documento.valor_total::numeric,
    documento.modelo,
    documento.nfe_status,
    documento.nfse_status,
    documento.created_at
  from f.documento_fiscal documento
  left join public.clientes cliente
    on cliente.id = documento.cliente_id
   and cliente.tenant_id = documento.tenant_id
  where documento.tenant_id = p_tenant_id
    and documento.empresa_id = any(v_empresa_ids)
    and documento.operacao = 'SAIDA'
    and documento.deleted_at is null
    and documento.emissao_date >= p_data_inicio
    and documento.emissao_date < p_data_fim_exclusiva
    -- Nota de homologacao nao e faturamento. O retorno de homologacao grava
    -- nfe_status = 'RASCUNHO' de proposito (f.fn_nfe_aplicar_retorno); so o
    -- retorno de producao grava 'EMITIDA'. Sem este filtro o analitico somava
    -- as notas de teste como receita. CANCELADA com numero continua entrando:
    -- foi cancelamento autorizado na SEFAZ e o documento existiu. Rascunho
    -- descartado tambem vira CANCELADA, porem sem numero.
    -- NFS-e nao usa nfe_status (fica nulo) e segue pelo nfse_status.
    and (
      documento.modelo = 'NFSE'
      or (
        documento.nfe_status in ('EMITIDA', 'CANCELADA')
        and documento.numero is not null
      )
    )
    -- Emissao somente de homologacao: nao e documento fiscal, nem cancelada.
    and not (
      exists (
        select 1 from f.documento_fiscal_emissao hom
        where hom.tenant_id = documento.tenant_id
          and hom.empresa_id = documento.empresa_id
          and hom.documento_fiscal_id = documento.id
          and hom.ambiente = 'HOMOLOGACAO'
      )
      and not exists (
        select 1 from f.documento_fiscal_emissao prod
        where prod.tenant_id = documento.tenant_id
          and prod.empresa_id = documento.empresa_id
          and prod.documento_fiscal_id = documento.id
          and prod.ambiente = 'PRODUCAO'
      )
    )
    and not exists (
      select 1
      from public.empresas empresa_destino
      where empresa_destino.tenant_id = documento.tenant_id
        and empresa_destino.id <> documento.empresa_id
        and regexp_replace(coalesce(empresa_destino.cnpj, ''), '[^0-9]', '', 'g') <> ''
        and regexp_replace(coalesce(empresa_destino.cnpj, ''), '[^0-9]', '', 'g') =
            regexp_replace(coalesce(cliente.documento_norm, cliente.documento, ''), '[^0-9]', '', 'g')
    )
  order by documento.emissao_date, documento.created_at, documento.id;
end;
$function$;
