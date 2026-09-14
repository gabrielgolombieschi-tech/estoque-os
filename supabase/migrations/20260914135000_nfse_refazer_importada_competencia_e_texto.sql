-- NFS-e: refazer pela tela uma nota IMPORTADA, competencia no mes da emissao, e percentual de servico no texto.
--
-- Pedido da WEG Tintas (09/2026) sobre as NFS-e 12, 13, 14 e 15 de 03/08/2026, emitidas por outro sistema
-- (serie 70000) e que estao no ERP como documentos importados:
--   (1) a competencia deve ser o mesmo mes da emissao — as notas tinham competencia 29/07 e emissao 03/08, e o
--       tomador recolhe o ISS e o INSS retidos pela competencia, com multa e juros;
--   (2) quando ha reducao da base do INSS, a descricao traz o percentual de SERVICO e o de MATERIAL.
-- Decisoes do Gabriel (14/09/2026): refazer as quatro pelas telas, em homologacao e depois em producao, como
-- notas NOVAS (o cancelamento das antigas e feito com a prefeitura); manter a MESMA deducao de material das
-- originais, mesmo acima do material lancado na OS.
--
-- O que muda:
--  A. f.fn_data_hoje_sao_paulo(): o "hoje" fiscal. current_date do banco e UTC e vira o dia seguinte as 21h em
--     Sao Paulo (no ultimo dia do mes, o mes seguinte).
--  B. f.fn_nfse_competencia_pendencia(): competencia no mes da emissao e nao depois dela. Vale sempre: sem
--     retencao, a propria Segau atrasa o ISS pela competencia. Bloqueia na conferencia, na prontidao de producao
--     e no preparo (antes de criar documento e reservar DPS). O mes anterior, aceito desde 05/09 por causa da
--     nota 27 do emissor antigo, era o mesmo padrao que a WEG recusou.
--  C. Discriminacao: "SERVIÇO: R$ 16.700,00 (56,23% de Serviço). MATERIAL APLICADO: R$ 13.000,00 (43,77% de
--     Material), deduzido ...". O percentual de servico e 100 menos o de material ja arredondado: soma 100,00.
--  D. f.fn_nfse_documento_deducao(): a deducao de material de qualquer NFS-e (emissao do ERP, XML <vDR>,
--     material_valor, base do ISS). As importadas da serie 70000 contavam zero, porque o valor so esta no XML.
--  E. f.fn_os_nfse_material_disponivel: usa (D), nao conta a nota que a solicitacao refaz e devolve o teto da
--     deducao — o maior entre o material disponivel e a deducao da nota refeita.
--  F. f.fn_nfse_importada_dados_refazer() e f.fn_nfse_refazer_importada_criar(): o caminho da tela. O primeiro so
--     le a nota antiga (texto limpo de PEDIDO/VENCIMENTO, pedido, dias, obra, deducao, cTribNac); o segundo cria
--     a solicitacao ja marcada com substitui_documento_fiscal_id.
--  G. Conferencia: a reserva da nota refeita vale tambem sem solicitacao antiga, pelo bruto; o teto do material
--     e o de (E); competencia por (B).
--  H. Retorno autorizado em PRODUCAO de uma nota que refaz uma importada: a importada vira SUBSTITUIDA e o titulo
--     dela e cancelado (ou, com recebimento, fica registrado incidente sem abortar a gravacao). Em homologacao
--     nada toca a importada. Junto, o bloco de substituicao de notas do ERP so procura a antiga no MESMO
--     ambiente da nova: uma substituta de homologacao carrega a chave de producao e marcava a nota real.
--  I. Um refazer ou substituicao em andamento por nota (indice unico parcial).
--
-- Funcoes longas mudam por replace sobre pg_get_functiondef (a assinatura vem da definicao viva e nao vira
-- sobrecarga); cada trecho procurado precisa aparecer uma unica vez. No fim, cada nome tocado tem uma assinatura.

-- ---------------------------------------------------------------------------------------------------------
-- A e B. Hoje em Sao Paulo e regra da competencia
-- ---------------------------------------------------------------------------------------------------------
create or replace function f.fn_data_hoje_sao_paulo()
returns date
language sql
stable
set search_path to 'pg_catalog'
as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

comment on function f.fn_data_hoje_sao_paulo() is
  'Data de hoje no fuso de Sao Paulo. current_date do banco e UTC e avanca as 21h locais.';

grant execute on function f.fn_data_hoje_sao_paulo() to authenticated, service_role;

create or replace function f.fn_nfse_competencia_pendencia(p_competencia date, p_emissao date)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case
    when p_competencia is null then 'Data de competencia invalida.'
    when p_competencia > p_emissao then
      format('Competencia %s depois da data de emissao (%s): a competencia nao pode ser posterior a nota.',
        to_char(p_competencia, 'DD/MM/YYYY'), to_char(p_emissao, 'DD/MM/YYYY'))
    when to_char(p_competencia, 'YYYYMM') <> to_char(p_emissao, 'YYYYMM') then
      format('Competencia %s fora do mes da emissao (%s): use uma data de %s a %s. O tomador recolhe o ISS e o INSS retidos pela competencia, e competencia de outro mes gera multa e juros.',
        to_char(p_competencia, 'DD/MM/YYYY'), to_char(p_emissao, 'MM/YYYY'),
        to_char(date_trunc('month', p_emissao::timestamp)::date, 'DD/MM/YYYY'), to_char(p_emissao, 'DD/MM/YYYY'))
  end;
$$;

comment on function f.fn_nfse_competencia_pendencia(date, date) is
  'Pendencia da competencia da NFS-e frente a data de emissao (nula quando a competencia esta no mesmo mes e nao depois da emissao). Espelho em supabase/functions/_shared/fiscal/nfse-competencia.ts.';

grant execute on function f.fn_nfse_competencia_pendencia(date, date) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------
-- C. Discriminacao com percentual de servico e de material (mesma assinatura)
-- ---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f.fn_nfse_discriminacao(p_linhas jsonb, p_pedido text, p_pedido_item text, p_parcelas jsonb, p_base_date date, p_iss_retido boolean, p_texto_retencao text, p_observacao text, p_template text DEFAULT NULL::text, p_material numeric DEFAULT NULL::numeric, p_valor_servico numeric DEFAULT NULL::numeric)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  -- Servico e material num segmento so: aparecem e somem juntos, e o ponto entre eles e literal.
  v_template text := coalesce(nullif(btrim(coalesce(p_template, '')), ''),
    '{RESULTADO}|PEDIDO DE COMPRA: {PEDIDO}{ITEM}|VENCIMENTO: {VENCIMENTO} DDL|OS {OS}|SERVIÇO: {SERVICO} ({SERVICO_PCT} de Serviço). MATERIAL APLICADO: {MATERIAL} ({MATERIAL_PCT} de Material), deduzido da base do ISS e do INSS (LC 116/2003, art. 7º, § 2º, I)|{FRASE_LEGAL}|{OBSERVACAO}');
  v_tokens jsonb;
  v_segmento text;
  v_texto text;
  v_partes text[] := array[]::text[];
  v_linha jsonb;
  v_resultados text[] := array[]::text[];
  v_os text[] := array[]::text[];
  v_dias text[] := array[]::text[];
  v_datas text[] := array[]::text[];
  v_p jsonb;
  v_frase text := nullif(btrim(coalesce(p_texto_retencao, '')), '');
  v_chave text;
  v_valor text;
  v_vazio boolean;
  v_pct_material numeric(7,2);
  v_material_pct text;
  v_servico_pct text;
  v_servico text;
begin
  for v_linha in select * from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) loop
    if nullif(btrim(coalesce(v_linha->>'descricao', '')), '') is not null then
      v_resultados := array_append(v_resultados, upper(btrim(v_linha->>'descricao')));
    end if;
    if nullif(btrim(coalesce(v_linha->>'os_numero', '')), '') is not null and not (btrim(v_linha->>'os_numero') = any(v_os)) then
      v_os := array_append(v_os, btrim(v_linha->>'os_numero'));
    end if;
  end loop;
  if p_parcelas is not null and jsonb_typeof(p_parcelas) = 'array' then
    for v_p in select * from jsonb_array_elements(p_parcelas) loop
      v_dias := array_append(v_dias, v_p->>'dias');
      v_datas := array_append(v_datas, to_char(p_base_date + (v_p->>'dias')::integer, 'DD/MM/YYYY'));
    end loop;
  end if;
  if v_frase is not null and left(v_frase, 1) <> '"' then v_frase := '"' || v_frase || '"'; end if;
  -- 50,00 -> "50%"; 42,31 -> "42,31%"; 40,50 -> "40,5%". O de servico e o complemento exato do de material ja
  -- arredondado (arredondar os dois separados da 100,01 quando o material cai em x,xx5%).
  if coalesce(p_material, 0) > 0 and coalesce(p_valor_servico, 0) > 0 then
    v_pct_material := round(p_material / p_valor_servico * 100, 2);
    v_material_pct := replace(rtrim(rtrim(v_pct_material::text, '0'), '.'), '.', ',') || '%';
    v_servico_pct := replace(rtrim(rtrim((100 - v_pct_material)::numeric(7,2)::text, '0'), '.'), '.', ',') || '%';
    v_servico := f.fn_formatar_brl(p_valor_servico - p_material);
  end if;
  v_tokens := jsonb_build_object(
    'RESULTADO', array_to_string(v_resultados, '; '),
    'PEDIDO', nullif(btrim(coalesce(p_pedido, '')), ''),
    'ITEM', case when nullif(btrim(coalesce(p_pedido_item, '')), '') is not null then ' ITEM ' || btrim(p_pedido_item) else null end,
    'VENCIMENTO', nullif(array_to_string(v_dias, '/'), ''),
    'DATAS', nullif(array_to_string(v_datas, ', '), ''),
    'OS', nullif(array_to_string(v_os, '/'), ''),
    'MATERIAL', case when coalesce(p_material, 0) > 0 then f.fn_formatar_brl(p_material) else null end,
    'MATERIAL_PCT', v_material_pct,
    'SERVICO', v_servico,
    'SERVICO_PCT', v_servico_pct,
    'FRASE_LEGAL', v_frase,
    'ISS', case when p_iss_retido then 'ISS RETIDO PELO TOMADOR' else null end,
    'OBSERVACAO', nullif(btrim(coalesce(p_observacao, '')), '')
  );
  foreach v_segmento in array string_to_array(v_template, '|') loop
    v_texto := v_segmento;
    v_vazio := false;
    for v_chave, v_valor in select key, value #>> '{}' from jsonb_each(v_tokens) loop
      if position('{' || v_chave || '}' in v_texto) > 0 then
        if v_valor is null and v_chave <> 'ITEM' then v_vazio := true; end if;
        v_texto := replace(v_texto, '{' || v_chave || '}', coalesce(v_valor, ''));
      end if;
    end loop;
    v_texto := btrim(v_texto);
    if not v_vazio and v_texto <> '' then
      v_partes := array_append(v_partes, v_texto || case when right(v_texto, 1) in ('.', '"', ')') then '' else '.' end);
    end if;
  end loop;
  return left(regexp_replace(array_to_string(v_partes, ' '), '\s+', ' ', 'g'), 1000);
end;
$function$;

-- ---------------------------------------------------------------------------------------------------------
-- D. Deducao de material de uma NFS-e, de qualquer origem
-- ---------------------------------------------------------------------------------------------------------
create or replace function f.fn_nfse_documento_deducao(p_documento_fiscal_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $deducao$
declare
  v_doc f.documento_fiscal%rowtype;
  v_valor numeric;
  v_xml text;
  v_iss_base numeric;
begin
  select * into v_doc from f.documento_fiscal where id = p_documento_fiscal_id;
  if not found then return 0; end if;

  -- 1. Emitida pelo ERP: a deducao que foi na DPS.
  select e.valor_deducoes into v_valor
  from f.documento_fiscal_emissao e
  where e.documento_fiscal_id = v_doc.id and e.modelo = 'NFSE' and e.status = 'AUTORIZADA'
  order by e.autorizado_em desc nulls last
  limit 1;
  if found then return round(coalesce(v_valor, 0), 2); end if;

  -- 2. Importada no padrao nacional: o <vDR> (ou <pDR> sobre o <vServ>) do XML. XML nacional sem deducao = 0.
  select x.xml_raw::text into v_xml
  from f.documento_fiscal_xml x
  where x.documento_fiscal_id = v_doc.id and x.deleted_at is null
  limit 1;
  if v_xml is not null and v_xml ~ '<(\w+:)?vServ>' then
    v_valor := nullif(substring(v_xml from '<(?:\w+:)?vDR>\s*([0-9]+(?:\.[0-9]+)?)'), '')::numeric;
    if v_valor is null and v_xml ~ '<(\w+:)?pDR>' then
      v_valor := round(nullif(substring(v_xml from '<(?:\w+:)?pDR>\s*([0-9]+(?:\.[0-9]+)?)'), '')::numeric
               * nullif(substring(v_xml from '<(?:\w+:)?vServ>\s*([0-9]+(?:\.[0-9]+)?)'), '')::numeric / 100, 2);
    end if;
    return round(coalesce(v_valor, 0), 2);
  end if;

  -- 3. Importadas antigas (layout municipal): material informado no cadastro, ou a base do ISS menor que o servico.
  if coalesce(v_doc.material_valor, 0) > 0 then return round(v_doc.material_valor, 2); end if;
  select min(imp.base_calculo) into v_iss_base
  from f.documento_fiscal_imposto imp
  where imp.documento_fiscal_id = v_doc.id and imp.imposto = 'ISS';
  if v_iss_base is not null then return round(greatest(coalesce(v_doc.valor_servicos, 0) - v_iss_base, 0), 2); end if;
  return 0;
end;
$deducao$;

comment on function f.fn_nfse_documento_deducao(uuid) is
  'Deducao de material (vDR) de uma NFS-e: emissao do ERP, XML nacional (vDR ou pDR), material_valor ou base do ISS menor que o servico. As importadas da serie 70000 so tem o valor no XML.';

revoke all on function f.fn_nfse_documento_deducao(uuid) from public;
grant execute on function f.fn_nfse_documento_deducao(uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- E. Material disponivel (mesma assinatura)
-- ---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f.fn_os_nfse_material_disponivel(p_tenant_id uuid, p_empresa_id uuid, p_os_ids integer[], p_excluir_solicitacao uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_aplicado numeric(15,2);
  v_em_notas numeric(15,2);
  v_reservado numeric(15,2);
  v_refeita_id uuid;
  v_deducao_refeita numeric(15,2) := 0;
  v_disponivel numeric(15,2);
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using errcode = '22023', message = 'Tenant e empresa sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access(p_tenant_id, p_empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar o material da OS.';
  end if;

  -- A nota que a solicitacao refaz (substitui_documento_fiscal_id) sai da conta do ja deduzido: e ela que esta
  -- sendo refeita. A deducao dela vira o teto minimo, para refazer com a mesma deducao (WEG Tintas, 14/09/2026).
  if p_excluir_solicitacao is not null then
    select sf.substitui_documento_fiscal_id into v_refeita_id
    from f.solicitacao_faturamento sf
    where sf.id = p_excluir_solicitacao and sf.tenant_id = p_tenant_id and sf.empresa_id = p_empresa_id;
    if v_refeita_id is not null and exists (
      select 1 from f.documento_fiscal d
      where d.id = v_refeita_id and d.tenant_id = p_tenant_id and d.empresa_id = p_empresa_id and d.deleted_at is null
        and upper(coalesce(d.modelo, '')) = 'NFSE' and upper(coalesce(d.nfse_status, '')) = 'EMITIDA'
        and d.os_id_import = any(coalesce(p_os_ids, '{}'::integer[]))
    ) then
      v_deducao_refeita := f.fn_nfse_documento_deducao(v_refeita_id);
    else
      v_refeita_id := null;
    end if;
  end if;

  select coalesce(round(sum(coalesce(oi.valor_total, oi.quantidade * oi.valor_unitario, 0)), 2), 0)
    into v_aplicado
  from public.os_itens oi
  join public.ordens_servico os on os.id = oi.os_id and os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id
  join public.itens i on i.id = oi.item_id
  where oi.os_id = any(coalesce(p_os_ids, '{}'::integer[]))
    and i.tipo = 'produto'
    and oi.finalidade is distinct from 'venda';

  select coalesce(round(sum(f.fn_nfse_documento_deducao(d.id)), 2), 0)
    into v_em_notas
  from f.documento_fiscal d
  where d.tenant_id = p_tenant_id and d.empresa_id = p_empresa_id
    and d.os_id_import = any(coalesce(p_os_ids, '{}'::integer[]))
    and d.operacao = 'SAIDA' and d.deleted_at is null
    and upper(coalesce(d.modelo, '')) = 'NFSE' and upper(coalesce(d.nfse_status, '')) = 'EMITIDA'
    and d.id is distinct from v_refeita_id;

  select coalesce(round(sum(sf.valor_deducao_material), 2), 0)
    into v_reservado
  from f.solicitacao_faturamento sf
  where sf.tenant_id = p_tenant_id and sf.empresa_id = p_empresa_id
    and sf.status <> 'CANCELADA'
    and sf.id is distinct from p_excluir_solicitacao
    and coalesce(sf.valor_deducao_material, 0) > 0
    and exists (
      select 1 from f.solicitacao_item si
      where si.solicitacao_id = sf.id and si.origem_tipo = 'OS' and si.origem_id ~ '^[0-9]+$'
        and si.origem_id::integer = any(coalesce(p_os_ids, '{}'::integer[]))
    )
    and not exists (
      select 1 from f.documento_fiscal_emissao e
      join f.documento_fiscal d on d.id = e.documento_fiscal_id
      where e.solicitacao_id = sf.id and d.deleted_at is null and upper(coalesce(d.nfse_status, '')) = 'EMITIDA'
    )
    and coalesce((
      select e.status from f.documento_fiscal_emissao e
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
      order by e.created_at desc, e.documento_fiscal_id desc
      limit 1
    ), 'RASCUNHO') not in ('REJEITADA', 'ERRO', 'CANCELADA');

  v_disponivel := greatest(v_aplicado - v_em_notas - v_reservado, 0);
  return jsonb_build_object(
    'material_aplicado', v_aplicado,
    'deduzido_em_notas', v_em_notas,
    'reservado_em_solicitacoes', v_reservado,
    'material_deduzido', v_em_notas + v_reservado,
    'material_disponivel', v_disponivel,
    'documento_refeito_id', v_refeita_id,
    'deducao_refeita', v_deducao_refeita,
    'teto_deducao', greatest(v_disponivel, v_deducao_refeita));
end;
$function$;

-- ---------------------------------------------------------------------------------------------------------
-- I. Um refazer/substituicao em andamento por nota
-- ---------------------------------------------------------------------------------------------------------
create unique index if not exists solicitacao_faturamento_substitui_documento_aberta_uq
  on f.solicitacao_faturamento (substitui_documento_fiscal_id)
  where substitui_documento_fiscal_id is not null and status <> 'CANCELADA';

-- ---------------------------------------------------------------------------------------------------------
-- F. Caminho da tela: ler a nota importada e criar a solicitacao que a refaz
-- ---------------------------------------------------------------------------------------------------------
create or replace function f.fn_nfse_importada_dados_refazer(p_documento_fiscal_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $dados$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_doc f.documento_fiscal%rowtype;
  v_os public.ordens_servico%rowtype;
  v_xml text;
  v_obra text;
  v_linha text;
  v_m text[];
  v_partes text[] := array[]::text[];
  v_descricao text;
  v_pedido text;
  v_pedido_item text;
  v_dias text;
  v_titulo record;
  v_andamento record;
begin
  select * into v_doc from f.documento_fiscal where id = p_documento_fiscal_id;
  if not found then raise exception using errcode = 'P0002', message = 'Nota nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_doc.tenant_id
    or public.current_empresa_id() is distinct from v_doc.empresa_id
    or not f.has_finance_access(v_doc.tenant_id, v_doc.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para refazer esta nota.';
  end if;
  if upper(coalesce(v_doc.modelo, '')) <> 'NFSE' or v_doc.operacao <> 'SAIDA' or v_doc.deleted_at is not null then
    raise exception using errcode = '22023', message = 'So NFS-e de saida pode ser refeita por aqui.';
  end if;
  if exists (select 1 from f.documento_fiscal_emissao e where e.documento_fiscal_id = v_doc.id) then
    raise exception using errcode = '22023', message = 'Esta NFS-e foi emitida pelo sistema: use Substituir na tela de faturar a OS.';
  end if;
  if upper(coalesce(v_doc.nfse_status, '')) <> 'EMITIDA' then
    raise exception using errcode = '55000', message = format('A NFS-e %s/%s esta %s e nao pode ser refeita.', v_doc.serie, v_doc.numero, lower(coalesce(v_doc.nfse_status, 'sem status')));
  end if;
  if v_doc.os_id_import is null then
    raise exception using errcode = '22023', message = 'Vincule a nota a uma OS antes de refaze-la.';
  end if;
  select * into v_os from public.ordens_servico where id = v_doc.os_id_import and tenant_id = v_doc.tenant_id and empresa_id = v_doc.empresa_id;
  -- A nota refeita sai para o tomador da OS: nota vinculada a OS de outro cliente nao se refaz por aqui.
  if v_doc.cliente_id is not null and v_os.cliente_id is not null and v_doc.cliente_id <> v_os.cliente_id then
    raise exception using errcode = '22023', message = format('A NFS-e %s/%s e de outro tomador que nao o da OS %s: confira o vinculo da nota antes de refaze-la.', v_doc.serie, v_doc.numero, coalesce(v_os.numero_os, v_os.id::text));
  end if;

  select x.xml_raw::text into v_xml from f.documento_fiscal_xml x where x.documento_fiscal_id = v_doc.id and x.deleted_at is null limit 1;
  v_obra := substring(coalesce(v_xml, '') from '<(?:\w+:)?obra>(.*?)</(?:\w+:)?obra>');

  -- Descricao: o texto da nota sem as linhas de pedido e de vencimento, que a discriminacao do ERP monta sozinha.
  for v_linha in select btrim(l) from unnest(regexp_split_to_array(coalesce(v_doc.servico_discriminacao, ''), E'\\r?\\n')) as l loop
    if v_linha = '' then continue; end if;
    v_m := regexp_match(v_linha, '^(?:N[UÚ]MERO\s+DO\s+)?PEDIDO(?:\s+DE\s+COMPRA)?\s*[-:]\s*([0-9A-Za-z./-]*[0-9A-Za-z])(?:\s+ITEM\s+([0-9A-Za-z]+))?\s*\.?$', 'i');
    if v_m is not null then
      v_pedido := coalesce(v_pedido, v_m[1]);
      v_pedido_item := coalesce(v_pedido_item, v_m[2]);
      continue;
    end if;
    v_m := regexp_match(v_linha, '^VENCIMENTO\s*:\s*([0-9]+(?:\s*/\s*[0-9]+)*)\s*(?:DDL|DIAS?)?\s*\.?$', 'i');
    if v_m is not null then
      v_dias := coalesce(v_dias, regexp_replace(v_m[1], '\s', '', 'g'));
      continue;
    end if;
    v_partes := array_append(v_partes, v_linha);
  end loop;
  v_descricao := nullif(btrim(regexp_replace(array_to_string(v_partes, ' '), '\s+', ' ', 'g')), '');

  select t.id, t.status, t.valor_total, t.valor_aberto,
         exists (select 1 from f.titulo_parcela tp join f.pagamento_item pi on pi.titulo_parcela_id = tp.id and pi.deleted_at is null
                 where tp.titulo_id = t.id and tp.deleted_at is null) as com_recebimento
    into v_titulo
  from f.titulo t
  where t.tipo = 'AR' and t.documento_fiscal_id = v_doc.id and t.deleted_at is null
  limit 1;

  select s.id, s.status into v_andamento
  from f.solicitacao_faturamento s
  where s.substitui_documento_fiscal_id = v_doc.id and s.status <> 'CANCELADA'
  limit 1;

  return jsonb_build_object(
    'documento_fiscal_id', v_doc.id,
    'serie', v_doc.serie,
    'numero', v_doc.numero,
    'emissao_date', v_doc.emissao_date,
    'competencia_xml', substring(coalesce(v_xml, '') from '<(?:\w+:)?dCompet>([0-9-]+)<'),
    'os_id', v_doc.os_id_import,
    'os_numero', coalesce(v_os.numero_os, v_doc.os_id_import::text),
    'cliente_id', v_doc.cliente_id,
    'codigo_tributacao_nacional', substring(coalesce(v_xml, '') from '<(?:\w+:)?cTribNac>([0-9]{6})<'),
    'municipio_prestacao_ibge', coalesce(substring(coalesce(v_xml, '') from '<(?:\w+:)?cLocPrestacao>([0-9]{7})<'), v_doc.nfse_municipio_codigo),
    'valor_servico', v_doc.valor_servicos,
    'valor_liquido', v_doc.valor_total,
    'valor_deducao', f.fn_nfse_documento_deducao(v_doc.id),
    'valor_inss', nullif(substring(coalesce(v_xml, '') from '<(?:\w+:)?vRetCP>([0-9.]+)<'), '')::numeric,
    'obra', case when v_obra is null then null else jsonb_strip_nulls(jsonb_build_object(
      'codigo_obra', substring(v_obra from '<(?:\w+:)?cObra>([^<]+)<'),
      'cep', substring(v_obra from '<(?:\w+:)?CEP>([0-9]{8})<'),
      'logradouro', substring(v_obra from '<(?:\w+:)?xLgr>([^<]+)<'),
      'numero', substring(v_obra from '<(?:\w+:)?nro>([^<]+)<'),
      'complemento', substring(v_obra from '<(?:\w+:)?xCpl>([^<]+)<'),
      'bairro', substring(v_obra from '<(?:\w+:)?xBairro>([^<]+)<'))) end,
    'discriminacao_original', v_doc.servico_discriminacao,
    'descricao', v_descricao,
    'pedido', coalesce(v_pedido, nullif(btrim(coalesce(v_os.pedido_compra, '')), '')),
    'pedido_item', v_pedido_item,
    'dias', case when v_dias is null then null else to_jsonb(string_to_array(v_dias, '/')::integer[]) end,
    'texto_proibido', f.fn_nfse_texto_proibido(v_descricao),
    'titulo', case when v_titulo.id is null then null else jsonb_build_object(
      'id', v_titulo.id, 'status', v_titulo.status, 'valor_total', v_titulo.valor_total, 'valor_aberto', v_titulo.valor_aberto, 'com_recebimento', v_titulo.com_recebimento) end,
    'refazer_em_andamento', case when v_andamento.id is null then null else jsonb_build_object('solicitacao_id', v_andamento.id, 'status', v_andamento.status) end
  );
end;
$dados$;

comment on function f.fn_nfse_importada_dados_refazer(uuid) is
  'Le uma NFS-e importada (emitida por outro sistema) para refaze-la pela tela: descricao sem PEDIDO/VENCIMENTO, pedido, dias, obra, deducao, cTribNac, titulo e refazer em andamento. Nao grava nada.';

revoke all on function f.fn_nfse_importada_dados_refazer(uuid) from public;
grant execute on function f.fn_nfse_importada_dados_refazer(uuid) to authenticated, service_role;

create or replace function f.fn_nfse_refazer_importada_criar(p_documento_fiscal_id uuid, p_perfil_operacao_id uuid, p_linhas jsonb, p_motivo text)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $criar$
declare
  v_dados jsonb;
  v_doc f.documento_fiscal%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_linha record;
  v_proibido text;
  v_solicitacao_id uuid;
  v_andamento uuid;
begin
  -- Mesmas validacoes de acesso e de elegibilidade da leitura.
  v_dados := f.fn_nfse_importada_dados_refazer(p_documento_fiscal_id);
  select * into v_doc from f.documento_fiscal where id = p_documento_fiscal_id;
  if char_length(v_motivo) < 15 or char_length(v_motivo) > 255 then
    raise exception using errcode = '22023', message = 'O motivo de refazer a nota deve ter entre 15 e 255 caracteres.';
  end if;
  v_andamento := nullif(v_dados->'refazer_em_andamento'->>'solicitacao_id', '')::uuid;
  if v_andamento is not null then
    raise exception using errcode = '55000', message = format('Ja existe uma nota refazendo a NFS-e %s/%s (solicitacao %s). Continue nela ou descarte-a antes.', v_doc.serie, v_doc.numero, v_andamento);
  end if;
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    raise exception using errcode = '22023', message = 'Informe a linha de servico da nota refeita.';
  end if;
  for v_linha in select x.os_id, x.descricao_servico from jsonb_to_recordset(p_linhas) as x(os_id integer, descricao_servico text) loop
    if v_linha.os_id is distinct from v_doc.os_id_import then
      raise exception using errcode = '22023', message = format('A nota refeita e da OS vinculada a NFS-e %s/%s (id %s), nao da OS %s.', v_doc.serie, v_doc.numero, v_doc.os_id_import, v_linha.os_id);
    end if;
    -- Barra antes de criar: depois de salva, a linha nao se edita na tela.
    v_proibido := f.fn_nfse_texto_proibido(v_linha.descricao_servico);
    if v_proibido is not null then
      raise exception using errcode = '22023', message = format('A expressao "%s" e proibida na descricao (define cessao de mao de obra). Descreva o resultado entregue antes de salvar.', v_proibido);
    end if;
  end loop;

  v_solicitacao_id := f.fn_solicitacao_faturamento_criar_os_servico(v_doc.tenant_id, v_doc.empresa_id, p_perfil_operacao_id, p_linhas);
  update f.solicitacao_faturamento
     set substitui_documento_fiscal_id = v_doc.id,
         substitui_solicitacao_id = null,
         substituicao_codigo = null,
         substituicao_motivo = v_motivo,
         updated_at = now()
   where id = v_solicitacao_id;
  return v_solicitacao_id;
end;
$criar$;

comment on function f.fn_nfse_refazer_importada_criar(uuid, uuid, jsonb, text) is
  'Cria a solicitacao de NFS-e que refaz uma nota importada (substitui_documento_fiscal_id), pela mesma criacao das NFS-e da OS. A nota nova sai como nota comum; so a producao marca a antiga como SUBSTITUIDA.';

revoke all on function f.fn_nfse_refazer_importada_criar(uuid, uuid, jsonb, text) from public;
grant execute on function f.fn_nfse_refazer_importada_criar(uuid, uuid, jsonb, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------
-- G, B e H. Funcoes longas por replace sobre a definicao viva
-- ---------------------------------------------------------------------------------------------------------
create or replace function pg_temp.trocar_uma_vez(p_texto text, p_de text, p_para text, p_rotulo text)
returns text
language plpgsql
as $$
declare
  v_vezes integer;
begin
  v_vezes := (length(p_texto) - length(replace(p_texto, p_de, ''))) / nullif(length(p_de), 0);
  if v_vezes is distinct from 1 then
    raise exception 'Trecho "%" aparece % vez(es); esperado 1.', p_rotulo, coalesce(v_vezes, 0);
  end if;
  return replace(p_texto, p_de, p_para);
end;
$$;

-- G. Conferencia
do $conferir$
declare
  v_def text := pg_get_functiondef('f.fn_os_nfse_conferir_homologacao(uuid,jsonb)'::regprocedure);
begin
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$v_competencia := coalesce(nullif(btrim(coalesce(p_operacao->>'data_competencia', '')), '')::date, current_date);$a$,
    $a$v_competencia := coalesce(nullif(btrim(coalesce(p_operacao->>'data_competencia', '')), '')::date, f.fn_data_hoje_sao_paulo());$a$,
    'competencia padrao');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$elsif v_competencia > current_date then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Competencia no futuro nao e aceita.'));$a$,
    $a$elsif f.fn_nfse_competencia_pendencia(v_competencia, f.fn_data_hoje_sao_paulo()) is not null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem',f.fn_nfse_competencia_pendencia(v_competencia, f.fn_data_hoje_sao_paulo())));$a$,
    'competencia no mes da emissao');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$if v_deducao > (v_material->>'material_disponivel')::numeric + 0.005 then$a$,
    $a$if v_deducao > coalesce((v_material->>'teto_deducao')::numeric, (v_material->>'material_disponivel')::numeric) + 0.005 then$a$,
    'teto do material');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$f.fn_formatar_brl(v_deducao), f.fn_formatar_brl((v_material->>'material_disponivel')::numeric),$a$,
    $a$f.fn_formatar_brl(v_deducao), f.fn_formatar_brl(coalesce((v_material->>'teto_deducao')::numeric, (v_material->>'material_disponivel')::numeric)),$a$,
    'mensagem do teto do material');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$if v_sf.substitui_solicitacao_id is not null then$a$,
    $a$if v_sf.substitui_solicitacao_id is not null or v_sf.substitui_documento_fiscal_id is not null then$a$,
    'reserva da nota refeita sem solicitacao antiga');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$select v_reserva_substituida + coalesce(sum(d.valor_total), 0) into v_reserva_substituida from f.documento_fiscal d$a$,
    $a$select v_reserva_substituida + coalesce(sum(f.fn_documento_valor_faturado(d.modelo, d.valor_total, d.valor_servicos, d.valor_produtos)), 0) into v_reserva_substituida from f.documento_fiscal d$a$,
    'reserva da nota refeita pelo bruto');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$where d.id = v_sf.substitui_documento_fiscal_id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA' and d.os_id_import = v_os_total.os_id;$a$,
    $a$where d.id = v_sf.substitui_documento_fiscal_id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA' and d.os_id_import = v_os_total.os_id and d.deleted_at is null;$a$,
    'reserva da nota refeita nao apagada');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$v_parcelas, current_date, v_iss_retido$a$,
    $a$v_parcelas, f.fn_data_hoje_sao_paulo(), v_iss_retido$a$,
    'data base da discriminacao');
  execute v_def;
end;
$conferir$;

-- B. Prontidao de producao: competencia e nota refeita
do $pronta$
declare
  v_def text := pg_get_functiondef('f.fn_nfse_producao_pronta(uuid)'::regprocedure);
begin
  v_def := pg_temp.trocar_uma_vez(v_def,
    E'  v_certificado date;\n',
    E'  v_certificado date;\n  v_competencia_msg text;\n',
    'declaracao da competencia');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and (si.tributacao_fonte is distinct from 'PERFIL' or si.perfil_operacao_id is null)) then$a$,
    $a$  -- A producao repete a homologacao, inclusive a competencia: homologacao de um mes nao sai em producao no outro.
  v_competencia_msg := f.fn_nfse_competencia_pendencia(nullif(v_sf.operacao_snapshot->'servico'->>'data_competencia', '')::date, f.fn_data_hoje_sao_paulo());
  if v_competencia_msg is not null then
    return jsonb_build_object('pronta', false, 'campo', 'data_competencia', 'motivo', 'Producao bloqueada: ' || v_competencia_msg
      || ' A producao repete a homologacao, inclusive a competencia: abandone a homologacao, confira de novo com a competencia deste mes, homologue e libere o perfil para a nova nota.');
  end if;
  -- Nota que refaz uma importada: a antiga ainda precisa estar EMITIDA.
  if v_sf.substitui_documento_fiscal_id is not null and v_sf.substitui_solicitacao_id is null and not exists (
    select 1 from f.documento_fiscal d where d.id = v_sf.substitui_documento_fiscal_id and d.deleted_at is null and upper(coalesce(d.nfse_status, '')) = 'EMITIDA'
  ) then
    return jsonb_build_object('pronta', false, 'campo', 'substitui_documento_fiscal_id', 'motivo', 'A nota que esta solicitacao refaz nao esta mais EMITIDA (ja foi cancelada ou substituida).');
  end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and (si.tributacao_fonte is distinct from 'PERFIL' or si.perfil_operacao_id is null)) then$a$,
    'checagens antes da fonte da tributacao');
  execute v_def;
end;
$pronta$;

-- B. Preparo: competencia antes de criar documento e reservar DPS; datas em Sao Paulo
do $preparar$
declare
  v_def text := pg_get_functiondef('f.fn_nfse_preparar_documento_solicitacao(uuid,text)'::regprocedure);
begin
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$    raise exception using errcode = '22023', message = 'Conferencia da NFS-e ainda nao foi salva nesta solicitacao.';
  end if;$a$,
    $a$    raise exception using errcode = '22023', message = 'Conferencia da NFS-e ainda nao foi salva nesta solicitacao.';
  end if;
  -- Competencia no mes da emissao (pedido da WEG Tintas, 09/2026): barra antes de criar documento e reservar DPS.
  if f.fn_nfse_competencia_pendencia(nullif(v_sf.operacao_snapshot->'servico'->>'data_competencia', '')::date, f.fn_data_hoje_sao_paulo()) is not null then
    raise exception using errcode = 'P0001', message = f.fn_nfse_competencia_pendencia(nullif(v_sf.operacao_snapshot->'servico'->>'data_competencia', '')::date, f.fn_data_hoje_sao_paulo())
      || case when p_ambiente = 'PRODUCAO'
              then ' A producao repete a homologacao: abandone a homologacao e confira de novo com a competencia deste mes.'
              else ' Troque a competencia e confira de novo.' end;
  end if;$a$,
    'competencia no preparo');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$'PENDENTE:' || v_referencia, 'NFSE', current_date,$a$,
    $a$'PENDENTE:' || v_referencia, 'NFSE', f.fn_data_hoje_sao_paulo(),$a$,
    'emissao_date em Sao Paulo');
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$date_trunc('month', coalesce((v_serv->>'data_competencia')::date, current_date))::date,$a$,
    $a$date_trunc('month', coalesce((v_serv->>'data_competencia')::date, f.fn_data_hoje_sao_paulo()))::date,$a$,
    'competencia_date em Sao Paulo');
  execute v_def;
end;
$preparar$;

-- H. Retorno autorizado
do $retorno$
declare
  v_def text := pg_get_functiondef('f.fn_nfse_aplicar_retorno(text,jsonb,text,text,text,text,text,integer,text,text,text,text,text)'::regprocedure);
begin
  v_def := pg_temp.trocar_uma_vez(v_def,
    E'  v_titulo_id uuid;\n',
    E'  v_titulo_id uuid;\n  v_importada f.documento_fiscal%rowtype;\n  v_chave_importada text;\n',
    'declaracao da importada');
  -- A antiga de uma substituicao do ERP e procurada so no ambiente da nova.
  v_def := pg_temp.trocar_uma_vez(v_def,
    $a$and a.chave_nfse = v_emissao.chave_nfse_substituida and a.documento_fiscal_id <> v_emissao.documento_fiscal_id$a$,
    $a$and a.chave_nfse = v_emissao.chave_nfse_substituida and a.documento_fiscal_id <> v_emissao.documento_fiscal_id and a.ambiente = v_emissao.ambiente$a$,
    'substituicao no mesmo ambiente');
  v_def := pg_temp.trocar_uma_vez(v_def,
    E'    end if;\n  end if;\n  return v_emissao.documento_fiscal_id;\nend;',
    $a$    end if;

    -- Refazer de nota IMPORTADA (emitida por outro sistema, sem emissao no ERP): a nota nova sai como nota comum,
    -- sem chSubstda, e o cancelamento da antiga e feito na prefeitura. So a PRODUCAO aposenta a antiga no ERP,
    -- para faturado, saldo, material e contas a receber nao ficarem em dobro (WEG Tintas, 14/09/2026).
    if v_emissao.ambiente = 'PRODUCAO' then
      select d.* into v_importada
      from f.solicitacao_faturamento s
      join f.documento_fiscal d on d.id = s.substitui_documento_fiscal_id and d.tenant_id = s.tenant_id and d.empresa_id = s.empresa_id
      where s.id = v_emissao.solicitacao_id and s.substitui_solicitacao_id is null
        and upper(coalesce(d.modelo, '')) = 'NFSE' and d.deleted_at is null and upper(coalesce(d.nfse_status, '')) = 'EMITIDA'
        and not exists (select 1 from f.documento_fiscal_emissao ie where ie.documento_fiscal_id = d.id)
      for update of d;
      if found then
        v_chave_importada := coalesce(
          (select substring(x.xml_raw::text from 'Id="NFS([0-9]{50})"') from f.documento_fiscal_xml x
            where x.documento_fiscal_id = v_importada.id and x.deleted_at is null limit 1),
          v_importada.chave_acesso);
        update f.documento_fiscal set nfse_status = 'SUBSTITUIDA', updated_at = now()
        where id = v_importada.id and tenant_id = v_importada.tenant_id and empresa_id = v_importada.empresa_id;
        insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, justificativa, resposta, referencia_externa, chave_nova, chave_substituida)
        values
          (v_importada.id, v_importada.tenant_id, v_importada.empresa_id, 'SUBSTITUICAO', 'SUBSTITUIDA', v_emissao.substituicao_motivo,
           jsonb_build_object('papel', 'SUBSTITUIDA', 'origem', 'IMPORTADO', 'nova_referencia', v_emissao.referencia_externa,
                              'nova_nfse_numero', v_emissao.nfse_numero, 'cancelamento_na_prefeitura', 'PENDENTE'),
           v_importada.chave_acesso, v_emissao.chave_nfse, v_chave_importada),
          (v_emissao.documento_fiscal_id, v_emissao.tenant_id, v_emissao.empresa_id, 'SUBSTITUICAO', 'AUTORIZADA', v_emissao.substituicao_motivo,
           jsonb_build_object('papel', 'SUBSTITUTA', 'origem_antiga', 'IMPORTADO', 'antiga_documento_fiscal_id', v_importada.id,
                              'antiga_serie', v_importada.serie, 'antiga_numero', v_importada.numero, 'cancelamento_na_prefeitura', 'PENDENTE'),
           v_emissao.referencia_externa, v_emissao.chave_nfse, v_chave_importada);
        -- Titulo com recebimento nao pode ser cancelado automaticamente (f.fn_nfse_titulo_cancelar lanca 55000);
        -- lancar aqui desfaria a gravacao da nota ja autorizada no ambiente nacional. Fica registrado.
        if exists (
          select 1 from f.titulo t
          join f.titulo_parcela tp on tp.titulo_id = t.id and tp.deleted_at is null
          join f.pagamento_item pi on pi.titulo_parcela_id = tp.id and pi.deleted_at is null
          where t.tipo = 'AR' and t.documento_fiscal_id = v_importada.id and t.deleted_at is null
        ) then
          insert into f.documento_fiscal_evento (documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta, referencia_externa)
          values (v_importada.id, v_importada.tenant_id, v_importada.empresa_id, 'CONSULTA', 'INCIDENTE_TITULO_COM_RECEBIMENTO',
                  jsonb_build_object('nova_referencia', v_emissao.referencia_externa, 'nova_nfse_numero', v_emissao.nfse_numero,
                                     'mensagem', 'Titulo da nota refeita tem recebimento: ajuste o contas a receber a mao.'),
                  v_importada.chave_acesso);
        else
          perform f.fn_nfse_titulo_cancelar(v_importada.id, format('Refeita pela NFS-e %s', v_emissao.nfse_numero));
        end if;
      end if;
    end if;
  end if;
  return v_emissao.documento_fiscal_id;
end;$a$,
    'ramo da importada no fim do retorno autorizado');
  execute v_def;
end;
$retorno$;

-- Cada funcao tocada continua com uma assinatura so.
do $assinaturas$
declare
  v_nome text;
  v_qtd integer;
begin
  foreach v_nome in array array[
    'fn_data_hoje_sao_paulo', 'fn_nfse_competencia_pendencia', 'fn_nfse_discriminacao', 'fn_nfse_documento_deducao',
    'fn_os_nfse_material_disponivel', 'fn_nfse_importada_dados_refazer', 'fn_nfse_refazer_importada_criar',
    'fn_os_nfse_conferir_homologacao', 'fn_nfse_producao_pronta', 'fn_nfse_preparar_documento_solicitacao', 'fn_nfse_aplicar_retorno'
  ] loop
    select count(*) into v_qtd from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'f' and p.proname = v_nome;
    if v_qtd <> 1 then
      raise exception 'f.% ficou com % assinaturas.', v_nome, v_qtd;
    end if;
  end loop;
end;
$assinaturas$;
