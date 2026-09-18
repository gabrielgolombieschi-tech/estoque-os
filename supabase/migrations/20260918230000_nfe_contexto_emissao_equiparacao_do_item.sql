-- O contexto de emissao passa a levar a equiparacao a industrial do cadastro fiscal do item.
--
-- O montador (nfe-payload.ts) le `equiparado_industrial` na linha da solicitacao para decidir
-- se a revenda de item de origem 1 destaca IPI (RIPI art. 9o, I) — e bloqueia origem 1 sem a
-- marca. So que f.solicitacao_item nao tem essa coluna e f.fn_nfe_contexto_emissao_impl
-- serializava to_jsonb(si) puro: a marca gravada em public.fiscal_itens (pela importacao
-- 3101/3102 ou pela tela "Importado por nos", 20260918210000) nunca chegava ao montador, e
-- todo item de origem 1 parava em "sem a marca de equiparado a industrial". Foi o que travou
-- a homologacao da OV-SEG-00004-026 em 18/09/2026, com o item 3629 ja marcado.
--
-- Aqui a linha ganha, do cadastro fiscal do item: equiparado_industrial, origem_entrada e a
-- DIR da marcacao. Sem item do catalogo (linha livre de OS) os campos ficam nulos/false.
-- O resto da funcao e o de 20260902120000 (identico ao online em 18/09/2026, md5 39863f17).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

create or replace function f.fn_nfe_contexto_emissao_impl(p_documento_fiscal_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
  select jsonb_build_object(
    'emissao', to_jsonb(dfe),
    'documento', to_jsonb(df),
    'solicitacao', to_jsonb(sf),
    'itens', coalesce(it.itens, '[]'::jsonb)
  )
  from f.documento_fiscal_emissao dfe
  join f.documento_fiscal df
    on df.tenant_id = dfe.tenant_id and df.empresa_id = dfe.empresa_id and df.id = dfe.documento_fiscal_id
  join f.solicitacao_faturamento sf
    on sf.tenant_id = dfe.tenant_id and sf.empresa_id = dfe.empresa_id and sf.id = dfe.solicitacao_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'documento_item', to_jsonb(dfi),
        -- A equiparacao e fato do produto (cadastro fiscal), nao da linha: vai junto para o
        -- montador decidir o IPI da revenda de item importado pela propria empresa.
        'solicitacao_item', to_jsonb(si) || jsonb_build_object(
          'equiparado_industrial', coalesce(fi.equiparado_industrial, false),
          'origem_entrada', fi.origem_entrada,
          'importado_por_nos_dir', fi.importado_por_nos_dir
        )
      )
      order by si.ordem, si.id
    ) as itens
    from f.solicitacao_item si
    left join f.documento_fiscal_item dfi
      on dfi.tenant_id = si.tenant_id and dfi.empresa_id = si.empresa_id
     and dfi.documento_fiscal_id = df.id and dfi.item_n = si.ordem and dfi.deleted_at is null
    left join public.fiscal_itens fi
      on fi.tenant_id = si.tenant_id and fi.empresa_id = si.empresa_id and fi.item_id = si.item_id
    where si.tenant_id = sf.tenant_id and si.empresa_id = sf.empresa_id and si.solicitacao_id = sf.id
  ) it on true
  where dfe.documento_fiscal_id = p_documento_fiscal_id;
$function$;

comment on function f.fn_nfe_contexto_emissao_impl(uuid) is
  'Contexto da emissao (emissao, documento, solicitacao e itens). Cada solicitacao_item leva equiparado_industrial, origem_entrada e importado_por_nos_dir do cadastro fiscal do item (20260918230000).';

revoke all on function f.fn_nfe_contexto_emissao_impl(uuid) from public, anon, authenticated;

do $assertions$
begin
  if pg_get_functiondef('f.fn_nfe_contexto_emissao_impl(uuid)'::regprocedure) not like '%''equiparado_industrial'', coalesce(fi.equiparado_industrial, false)%' then
    raise exception 'fn_nfe_contexto_emissao_impl sem a equiparacao do item';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
