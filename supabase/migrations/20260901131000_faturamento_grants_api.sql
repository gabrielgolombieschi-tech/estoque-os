begin;

-- Policies RLS nao concedem privilegios de tabela. Sem estes grants, tanto o
-- usuario autenticado quanto Edge Functions com service role recebem 403 no
-- PostgREST, mesmo quando a policy permitir a operacao.
grant usage on schema f to authenticated, service_role;

grant select, insert, update, delete
  on table
    f.perfil_operacao,
    f.solicitacao_faturamento,
    f.solicitacao_item,
    f.documento_fiscal_emissao,
    f.documento_fiscal_evento
  to authenticated, service_role;

-- Tabela preexistente que recebeu o snapshot fiscal da NF-e autorizada. O
-- papel authenticated ja possuia DML no baseline; faltava o service role que
-- sera usado pela emissao server-side.
grant select, insert, update, delete
  on table f.documento_fiscal_item
  to service_role;

commit;
