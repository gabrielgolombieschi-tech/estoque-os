-- A migration 20260705120000_cadastro_empresa_sgu_automacao.sql copiou os
-- vinculos usuario_empresa da ELETRICA SEGAU para a SGU AUTOMACAO para TODOS
-- os usuarios que tinham acesso a Segau, deixando todo mundo ativo na nova
-- empresa. Isso nao era o desejado: apenas gabriel, larissa, deyvison e
-- vanessa devem ter acesso a SGU AUTOMACAO.
--
-- Esta migration desativa (ativo = false) o vinculo usuario_empresa com a
-- SGU AUTOMACAO para todos os usuarios exceto os 4 acima, identificados por
-- e-mail. Nao apaga os vinculos (mantem auditoria/reversibilidade), apenas
-- desliga o acesso, da mesma forma que a caixa "Ativo" da tela de usuarios.
--
-- Idempotente: pode ser reaplicada sem efeitos colaterais.

do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'; -- tenant "Segau"
  v_sgu_empresa_id uuid;
  v_emails_com_acesso text[] := array[
    'gabriel@segau.com.br',
    'larissa@segau.com.br',
    'deyvison@segau.com.br',
    'vanessa@segau.com.br'
  ];
  v_desativados int := 0;
begin
  select id into v_sgu_empresa_id
  from c.empresa
  where tenant_id = v_tenant_id and codigo = 'SGU' and deleted_at is null
  limit 1;

  if v_sgu_empresa_id is null then
    raise exception 'empresa SGU nao encontrada para o tenant % - abortando', v_tenant_id;
  end if;

  update a.usuario_empresa ue
  set ativo = false, updated_at = now()
  from a.usuario u
  where ue.usuario_id = u.id
    and ue.empresa_id = v_sgu_empresa_id
    and ue.deleted_at is null
    and ue.ativo = true
    and lower(u.email) not in (select lower(e) from unnest(v_emails_com_acesso) as e);

  get diagnostics v_desativados = row_count;

  raise notice 'SGU restricao ok: empresa_id=%, usuario_empresa desativados=%',
    v_sgu_empresa_id, v_desativados;
end $$;
