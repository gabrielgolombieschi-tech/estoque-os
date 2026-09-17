-- Devolucao de compra: gerar de novo passa pelo fluxo auditado, e a homologacao referencia
-- uma NF-e que a SEFAZ de teste conhece.
--
-- Dois pontos que a primeira devolucao real (NF-e 121481/3 da Acos America, 17/09/2026) mostrou:
--
-- 1. Gerar de novo depois de uma rejeicao: a solicitacao anterior ja tinha tentativa fiscal e o
--    UPDATE direto foi barrado ("Material fiscal congelado: abandone/cancele pelo fluxo
--    auditado"). Agora o rascunho anterior sai por f.fn_solicitacao_nfe_cancelar_rascunho (sem
--    tentativa) ou f.fn_solicitacao_nfe_abandonar_homologacao (com emissao de homologacao viva,
--    rejeitada ou autorizada), com o evento registrado; a operacao vira CANCELADA.
--
-- 2. A SEFAZ exige a nota de origem em NFref na devolucao (finNFe 4). Em homologacao ela nao
--    conhece a chave real (rejeicao 321 com refNFe da chave de producao e tambem com refNF da
--    nota modelo 1 lida da chave). Para a homologacao validar o resto da nota, o snapshot guarda
--    a chave da ultima NF-e AUTORIZADA em homologacao da empresa
--    (devolucao_compra.chave_referencia_homologacao); o montador usa essa chave no NFref de
--    homologacao e a chave real na nota de producao. A comparacao producao x homologacao ja
--    ignora o grupo.

do $$
declare
  v_def text;
  v_anchor_decl constant text := E'  v_fmt text;\nbegin';
  v_decl constant text := E'  v_fmt text;\n  v_prev record;\nbegin';
  v_anchor_cancel constant text := E'  update f.solicitacao_faturamento sf\n     set status = ''CANCELADA'', updated_at = now()\n   where sf.tenant_id = v_scope.tenant_id and sf.empresa_id = v_scope.empresa_id\n     and sf.status not in (''EMITIDA'', ''CANCELADA'')\n     and sf.id in (\n       select o.solicitacao_id from f.operacao_fiscal o\n        where o.tenant_id = v_scope.tenant_id and o.empresa_id = v_scope.empresa_id and o.deleted_at is null\n          and o.tipo = ''DEVOLUCAO_COMPRA'' and o.nf_entrada_origem_id = p_nf_entrada_id\n          and o.status not in (''CONCLUIDA'', ''CANCELADA'') and o.solicitacao_id is not null\n          and not exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = o.solicitacao_id and e.ambiente = ''PRODUCAO'' and e.status not in (''REJEITADA'', ''ERRO'')));\n  update f.operacao_fiscal o\n     set status = ''CANCELADA'', updated_at = now()\n   where o.tenant_id = v_scope.tenant_id and o.empresa_id = v_scope.empresa_id and o.deleted_at is null\n     and o.tipo = ''DEVOLUCAO_COMPRA'' and o.nf_entrada_origem_id = p_nf_entrada_id\n     and o.status not in (''CONCLUIDA'', ''CANCELADA'')\n     and not exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = o.solicitacao_id and e.ambiente = ''PRODUCAO'' and e.status not in (''REJEITADA'', ''ERRO''));';
  v_cancel constant text := E'  for v_prev in\n    select o.id, o.solicitacao_id from f.operacao_fiscal o\n     where o.tenant_id = v_scope.tenant_id and o.empresa_id = v_scope.empresa_id and o.deleted_at is null\n       and o.tipo = ''DEVOLUCAO_COMPRA'' and o.nf_entrada_origem_id = p_nf_entrada_id\n       and o.status not in (''CONCLUIDA'', ''CANCELADA'')\n       and not exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = o.solicitacao_id and e.ambiente = ''PRODUCAO'' and e.status not in (''REJEITADA'', ''ERRO''))\n  loop\n    -- Fluxo auditado: sem tentativa fiscal e descarte de rascunho; com emissao de homologacao\n    -- viva (rejeitada ou autorizada) e abandono, com o evento registrado.\n    if v_prev.solicitacao_id is not null\n       and exists (select 1 from f.solicitacao_faturamento sf where sf.id = v_prev.solicitacao_id and sf.status not in (''EMITIDA'', ''CANCELADA'')) then\n      if exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = v_prev.solicitacao_id and e.ambiente = ''HOMOLOGACAO'' and e.status <> ''CANCELADA'') then\n        perform f.fn_solicitacao_nfe_abandonar_homologacao(v_prev.solicitacao_id, ''Devolucao gerada de novo pela tela de operacoes'');\n      else\n        perform f.fn_solicitacao_nfe_cancelar_rascunho(v_prev.solicitacao_id, ''Devolucao gerada de novo pela tela de operacoes'');\n      end if;\n    end if;\n    update f.operacao_fiscal set status = ''CANCELADA'', updated_at = now() where id = v_prev.id;\n  end loop;';
  v_anchor_snap constant text := E'        ''itens_texto'', v_itens_texto\n      )';
  v_snap constant text := E'        ''itens_texto'', v_itens_texto,\n        ''chave_referencia_homologacao'', (\n          select e.chave_acesso from f.documento_fiscal_emissao e\n           where e.tenant_id = v_scope.tenant_id and e.empresa_id = v_scope.empresa_id\n             and e.ambiente = ''HOMOLOGACAO'' and e.status = ''AUTORIZADA'' and e.chave_acesso ~ ''^[0-9]{44}$''\n           order by e.autorizado_em desc nulls last, e.updated_at desc limit 1)\n      )';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_devolucao_compra_nfe_criar';
  if v_def is null then
    raise exception 'f.fn_devolucao_compra_nfe_criar nao encontrada';
  end if;
  if position('chave_referencia_homologacao' in v_def) > 0 then
    raise notice 'fn_devolucao_compra_nfe_criar ja tem a referencia de homologacao; nada a fazer';
    return;
  end if;
  if position(v_anchor_decl in v_def) = 0 or position(v_anchor_cancel in v_def) = 0 or position(v_anchor_snap in v_def) = 0 then
    raise exception 'ancora nao encontrada em fn_devolucao_compra_nfe_criar (decl %, cancel %, snap %)',
      position(v_anchor_decl in v_def) > 0, position(v_anchor_cancel in v_def) > 0, position(v_anchor_snap in v_def) > 0;
  end if;
  v_def := replace(v_def, v_anchor_decl, v_decl);
  v_def := replace(v_def, v_anchor_cancel, v_cancel);
  v_def := replace(v_def, v_anchor_snap, v_snap);
  execute v_def;
end $$;
