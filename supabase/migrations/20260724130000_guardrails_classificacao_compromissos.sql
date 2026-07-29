-- Endurece a governanca da classificacao sem alterar a composicao aplicada:
-- chaves de escopo ficam imutaveis, reversoes auditadas continuam possiveis
-- mesmo se o titulo for cancelado posteriormente e clientes nao gravam direto.

create or replace function f.trg_titulo_classificacao_compromisso_validar()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_legado boolean;
begin
  if tg_op = 'UPDATE'
     and (
       new.tenant_id,
       new.empresa_id,
       new.titulo_id,
       new.lote_id
     ) is distinct from (
       old.tenant_id,
       old.empresa_id,
       old.titulo_id,
       old.lote_id
     )
  then
    raise exception
      'Classificacao: chaves de escopo e origem sao imutaveis.';
  end if;

  if tg_op = 'INSERT' and new.deleted_at is not null then
    raise exception 'Classificacao nao pode nascer revertida.';
  end if;

  if new.deleted_at is null then
    if not exists (
      select 1
      from f.titulo t
      where t.id = new.titulo_id
        and t.tenant_id = new.tenant_id
        and t.empresa_id = new.empresa_id
        and t.tipo = 'AP'
        and t.deleted_at is null
        and t.status <> 'CANCELADO'
    ) then
      raise exception
        'Classificacao: titulo AP invalido ou fora do tenant/empresa.';
    end if;

    if not exists (
      select 1
      from f.compromisso_classificacao_lote l
      where l.id = new.lote_id
        and l.tenant_id = new.tenant_id
        and l.empresa_id = new.empresa_id
    ) then
      raise exception
        'Classificacao: lote invalido ou fora do tenant/empresa.';
    end if;

    select exists (
      select 1
      from f.titulo_legado_implantacao li
      where li.tenant_id = new.tenant_id
        and li.empresa_id = new.empresa_id
        and li.titulo_id = new.titulo_id
        and li.desmarcado_em is null
    )
    into v_legado;

    if new.categoria = 'AJUSTE' and not v_legado then
      raise exception
        'Classificacao: AJUSTE exige marcacao ativa de legado de implantacao.';
    end if;

    if new.categoria <> 'AJUSTE' and v_legado then
      raise exception
        'Classificacao: titulo legado deve permanecer exclusivamente em AJUSTE.';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke insert, update, delete, truncate, references, trigger
  on table f.compromisso_classificacao_lote
  from authenticated, anon;

revoke insert, update, delete, truncate, references, trigger
  on table f.titulo_classificacao_compromisso
  from authenticated, anon;

grant select on table f.compromisso_classificacao_lote
  to authenticated, service_role;

grant select on table f.titulo_classificacao_compromisso
  to authenticated, service_role;
