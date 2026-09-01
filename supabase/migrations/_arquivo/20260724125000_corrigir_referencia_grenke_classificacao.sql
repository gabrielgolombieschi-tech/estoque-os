-- Corrige somente a referencia documental do titulo Grenke legado usada na
-- conciliacao historica. Os dois titulos possuem o mesmo valor; a categoria,
-- os saldos, as parcelas e os demais dados financeiros permanecem inalterados.

do $correcao$
declare
  v_tenant constant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa constant uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_lote_id constant uuid := '7a53fa77-0a85-4a9b-82f2-98f75e52fd5a';
  v_titulo_legado constant uuid :=
    'e3c7421e-51d2-45e0-90d5-f53628f88f10';
  v_titulo_incorreto constant uuid :=
    '95bde27d-38c4-4d8b-abf7-0f287f7f58a3';
begin
  if not exists (
    select 1
    from f.titulo_legado_implantacao li
    where li.tenant_id = v_tenant
      and li.empresa_id = v_empresa
      and li.titulo_id = v_titulo_legado
      and li.desmarcado_em is null
  ) then
    raise exception
      'Correcao abortada: titulo Grenke legado ativo nao encontrado.';
  end if;

  update f.compromisso_classificacao_lote l
  set metadata = jsonb_set(
    l.metadata,
    '{reconciliacaoReferencia,grenkeLegadoTituloId}',
    to_jsonb(v_titulo_legado::text),
    false
  )
  where l.id = v_lote_id
    and l.tenant_id = v_tenant
    and l.empresa_id = v_empresa
    and l.codigo = 'COMPROMISSOS_SEG_20260724'
    and l.metadata #>> '{reconciliacaoReferencia,grenkeLegadoTituloId}'
      = v_titulo_incorreto::text;

  if not found then
    raise exception
      'Correcao abortada: lote ou referencia anterior nao conferem.';
  end if;
end;
$correcao$;
