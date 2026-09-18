-- Discriminacao da NFS-e: pedido uma vez so e sem aspas na frase legal.
--
-- Dois retoques pedidos pelo Gabriel em 18/09/2026, depois de validar a previa da NFS-e da OS 298
-- (CREMER, teste 21 / DPS 36):
--
--   1. A descricao digitada ja trazia "PEDIDO DE COMPRA Nº 148753" e o ERP acrescentou o
--      segmento padrao: o numero saiu duas vezes. Agora, quando a descricao digitada ja cita o
--      pedido, o segmento nao entra. Quando nao cita, entra como sempre.
--   2. A frase legal da retencao saia entre aspas ("SERVICO SUJEITO A RETENCAO..."). As aspas
--      saem; o texto continua igual, so sem elas.
--
-- O resto da funcao e a definicao de 20260914150000 (conferida no banco em 18/09/2026).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

create or replace function f.fn_nfse_discriminacao(p_linhas jsonb, p_pedido text, p_pedido_item text, p_parcelas jsonb, p_base_date date, p_iss_retido boolean, p_texto_retencao text, p_observacao text, p_template text default null::text, p_material numeric default null::numeric, p_valor_servico numeric default null::numeric)
returns text
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
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
  v_pedido text := nullif(btrim(coalesce(p_pedido, '')), '');
  v_resultado text;
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
  -- O pedido entra uma vez so: se quem escreveu a descricao ja citou o numero, o segmento padrao
  -- nao repete. A comparacao e pelo numero inteiro (nao casa 1487 dentro de 148753) e ignora
  -- pontuacao ao redor.
  v_resultado := upper(array_to_string(v_resultados, '; '));
  if v_pedido is not null and v_resultado ~ ('(^|[^0-9A-Za-z])' || regexp_replace(upper(v_pedido), '([\\^$.|?*+()\[\]{}-])', '\\\1', 'g') || '([^0-9A-Za-z]|$)') then
    v_pedido := null;
  end if;
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
    'PEDIDO', v_pedido,
    'ITEM', case when v_pedido is not null and nullif(btrim(coalesce(p_pedido_item, '')), '') is not null then ' ITEM ' || btrim(p_pedido_item) else null end,
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

comment on function f.fn_nfse_discriminacao(jsonb, text, text, jsonb, date, boolean, text, text, text, numeric, numeric) is
  'Monta a discriminacao da NFS-e a partir dos segmentos do template. O pedido entra uma vez so (nao repete quando a descricao digitada ja cita o numero) e a frase legal sai sem aspas (20260919070000).';

do $assertions$
declare
  v_linhas constant jsonb := '[{"descricao":"SERVICO X. PEDIDO DE COMPRA N 148753","os_numero":"298"}]'::jsonb;
  v_texto text;
begin
  -- Pedido ja citado na descricao: nao repete.
  v_texto := f.fn_nfse_discriminacao(v_linhas, '148753', null, '[{"dias":60}]'::jsonb, date '2026-09-18', false, 'FRASE LEGAL', null, null, null, null);
  if v_texto like '%PEDIDO DE COMPRA: 148753%' then
    raise exception 'pedido repetido na discriminacao: %', v_texto;
  end if;
  if v_texto like '%"%' then
    raise exception 'frase legal ainda sai entre aspas: %', v_texto;
  end if;
  -- Descricao sem o numero: o segmento entra.
  v_texto := f.fn_nfse_discriminacao('[{"descricao":"SERVICO X","os_numero":"298"}]'::jsonb, '148753', null, '[{"dias":60}]'::jsonb, date '2026-09-18', false, 'FRASE LEGAL', null, null, null, null);
  if v_texto not like '%PEDIDO DE COMPRA: 148753%' then
    raise exception 'pedido sumiu da discriminacao: %', v_texto;
  end if;
  -- Numero parecido nao conta como citado (1487 dentro de 148753).
  v_texto := f.fn_nfse_discriminacao('[{"descricao":"SERVICO 1487","os_numero":"298"}]'::jsonb, '148753', null, null, date '2026-09-18', false, null, null, null, null, null);
  if v_texto not like '%PEDIDO DE COMPRA: 148753%' then
    raise exception 'numero parecido derrubou o pedido: %', v_texto;
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
