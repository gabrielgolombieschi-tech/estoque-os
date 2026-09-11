-- Discriminacao da NFS-e: o percentual do material passa a ler "de Material", nao "do servico".
--
-- Pedido do Gabriel em 11/09/2026, lendo o DANFSe da NFS-e 12 de homologacao da OS 139:
-- "MATERIAL APLICADO: R$ 565,28 (0,76% do servico)" vira "MATERIAL APLICADO: R$ 565,28 (0,76% de Material)".
-- So o texto padrao muda; o calculo do percentual (material / valor do servico) e o mesmo.

CREATE OR REPLACE FUNCTION f.fn_nfse_discriminacao(p_linhas jsonb, p_pedido text, p_pedido_item text, p_parcelas jsonb, p_base_date date, p_iss_retido boolean, p_texto_retencao text, p_observacao text, p_template text DEFAULT NULL::text, p_material numeric DEFAULT NULL::numeric, p_valor_servico numeric DEFAULT NULL::numeric)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_template text := coalesce(nullif(btrim(coalesce(p_template, '')), ''),
    '{RESULTADO}|PEDIDO DE COMPRA: {PEDIDO}{ITEM}|VENCIMENTO: {VENCIMENTO} DDL|OS {OS}|MATERIAL APLICADO: {MATERIAL} ({MATERIAL_PCT} de Material), deduzido da base do ISS e do INSS (LC 116/2003, art. 7º, § 2º, I)|{FRASE_LEGAL}|{OBSERVACAO}');
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
  v_material_pct text;
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
  -- 50,00 -> "50%"; 42,31 -> "42,31%"; 40,50 -> "40,5%".
  if coalesce(p_material, 0) > 0 and coalesce(p_valor_servico, 0) > 0 then
    v_material_pct := replace(rtrim(rtrim(round(p_material / p_valor_servico * 100, 2)::text, '0'), '.'), '.', ',') || '%';
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
