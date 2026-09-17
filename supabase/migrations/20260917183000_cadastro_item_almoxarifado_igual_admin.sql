-- Cadastro de item pelo agente: quem cadastra grava o fiscal e le a nota de entrada,
-- como o ADMIN.
--
-- Pedido do Gabriel em 17/09/2026: "todos que tem acesso [ao cadastro] tem que ser igual ao
-- meu". A Ellen (ALMOXARIFADO, estoque@segau.com.br) tinha cad_itens.write mas nao
-- fiscal_itens.write nem fiscal_nf.read. Efeito no agente de cadastro (web e app):
--   - a sugestao vinha sem NCM/CST/aliquotas e com a pendencia "Voce nao possui permissao
--     para gravar dados fiscais neste cadastro", e o confirmar gravava o item sem fiscal;
--   - as linhas de nota de entrada (nf_entrada_itens) nao entravam como referencia fiscal,
--     porque a RLS delas exige fiscal_nf.read.
-- Para o ADMIN as duas permissoes sao verdadeiras e o cadastro sai completo.
--
-- public.can() -> public.can_unscoped_20260810() e a lista por papel. O ALMOXARIFADO ganha
-- fiscal_itens.write e fiscal_nf.read; a lista de menus (get_full_permissions_unscoped_20260810)
-- recebe as mesmas chaves para o web mostrar o mesmo que mostra ao ADMIN.

do $$
declare
  v_def text;
  v_anchor constant text := E'  if p_resource = ''cad_itens'' and p_action = ''write'' then\n    if v_papel_empresa in (''ALMOXARIFADO'', ''ADMIN'') then';
  v_novo constant text := E'  -- Cadastro de item completo para quem cadastra (17/09/2026): o fiscal do item e a leitura\n  -- da nota de entrada acompanham cad_itens.write.\n  if p_resource = ''fiscal_itens'' and p_action = ''write'' then\n    if v_papel_empresa in (''ALMOXARIFADO'', ''ADMIN'') then\n      return true;\n    end if;\n  end if;\n\n  if p_resource = ''fiscal_nf'' and p_action = ''read'' then\n    if v_papel_empresa in (''ALMOXARIFADO'', ''ADMIN'') then\n      return true;\n    end if;\n  end if;\n\n';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'can_unscoped_20260810';
  if v_def is null then
    raise exception 'public.can_unscoped_20260810 nao encontrada';
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'ancora do bloco cad_itens nao encontrada em can_unscoped_20260810';
  end if;
  if position('p_resource = ''fiscal_itens'' and p_action = ''write''' in v_def) > 0 then
    raise notice 'can_unscoped_20260810 ja tem a regra de fiscal_itens; nada a fazer';
    return;
  end if;
  v_def := replace(v_def, v_anchor, v_novo || v_anchor);
  execute v_def;
end $$;

do $$
declare
  v_def text;
  v_anchor constant text := E'  -- Emissao de nota (NF-e da OV, NF-e da OS e NFS-e) e liberacao de perfil fiscal para producao:';
  v_novo constant text := E'  -- Cadastro de item completo para quem cadastra (17/09/2026): mesmas chaves do ADMIN.\n  if v_empresa_papel_norm = ''ALMOXARIFADO'' then\n    extra_perms := extra_perms || jsonb_build_object(\n      ''fiscal_itens.write'', true,\n      ''fiscal_nf.read'', true\n    );\n  end if;\n\n';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_full_permissions_unscoped_20260810';
  if v_def is null then
    raise exception 'public.get_full_permissions_unscoped_20260810 nao encontrada';
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'ancora da emissao de nota nao encontrada em get_full_permissions_unscoped_20260810';
  end if;
  if position('Cadastro de item completo para quem cadastra' in v_def) > 0 then
    raise notice 'get_full_permissions_unscoped_20260810 ja tem o bloco do cadastro; nada a fazer';
    return;
  end if;
  v_def := replace(v_def, v_anchor, v_novo || v_anchor);
  execute v_def;
end $$;
