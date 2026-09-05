begin;

-- A implementacao permanece inacessivel diretamente. O wrapper valida o
-- escopo do usuario e precisa executar a implementacao com o papel do dono;
-- como SECURITY INVOKER, ate o service_role parava em "permission denied".
alter function f.fn_nfe_contexto_emissao(uuid) security definer;

comment on function f.fn_nfe_contexto_emissao(uuid) is
  'Wrapper autorizado do contexto de emissao. Valida o escopo e executa a implementacao interna sem expo-la aos papeis da API.';

commit;
