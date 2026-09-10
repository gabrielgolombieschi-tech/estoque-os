-- vItem da NF-e passa a levar o IPI, e a conferencia de producao acompanha.
--
-- Achado na auditoria da NF-e 2/35 (homologacao, OS 287, 10/09/2026): a correcao do
-- vNFTot feita em 09/09 mexeu so no total. O XML autorizado saiu com vNFTot 21.303,95
-- contra 19.411,34 de soma dos <vItem> — os 1.892,61 de IPI de diferenca. Pela
-- NT 2025.002-RTC o vNFTot e a soma dos vItem, e a rejeicao 1094 confere isso; hoje a
-- validacao esta dormente na SVRS (a 2/7 saiu em producao com vNFTot 194,11), mas o
-- documento fica com dois totais que se contradizem para quem auditar.
--
-- O builder passou a mandar valor_total_item = mercadoria + IPI
-- (supabase/functions/_shared/nfe-payload.ts). Esta funcao recusava exatamente isso:
-- comparava o campo com quantidade x preco - desconto e derrubava a emissao real com
-- "Quantidade/valor/desconto dos itens do payload divergem da solicitacao congelada".
--
-- Duas mudancas, nada mais:
--   1. a conferencia soma o ipi_valor do proprio payload antes de comparar;
--   2. f.documento_fiscal_item.valor_total continua recebendo a mercadoria da linha,
--      para a coluna nao mudar de significado no meio do caminho.

create or replace function f.fn_nfe_producao_preparar_e_claimar(
  p_solicitacao_id uuid,
  p_payload jsonb,
  p_homologacao_documento_id uuid,
  p_contexto_hash text,
  p_reconciliacao_confirmada boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
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
         order by ev.created_at desc, ev.id desc
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
     or (v_homologacao_payload - array['data_emissao','data_entrada_saida','nome_destinatario','ambiente','ambiente_emissao']::text[])
        is distinct from
        (p_payload - array['data_emissao','data_entrada_saida','nome_destinatario','ambiente','ambiente_emissao']::text[]) then
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
  v_total_esperado := round(v_produtos - v_desconto + v_frete + v_seguro + v_outros + v_ipi, 2);
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
             + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, 'ipi_valor'), 0), 2)
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
