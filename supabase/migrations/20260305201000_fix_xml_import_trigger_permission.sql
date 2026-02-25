begin;

create or replace function f.fn_nf_entrada__auto_fix_ap_from_xml()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'f', 'a'
set row_security to 'off'
as $$
declare
  v_titulo_id uuid;
  v_parc_cnt int;
  v_dup_cnt int;
  v_emissao_date date;
  v_xml xml;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if new.xml_raw is null or nullif(btrim(new.xml_raw), '') is null then
    return new;
  end if;

  -- so quando o XML "chega" (INSERT ou antes estava vazio)
  if tg_op = 'UPDATE' and old.xml_raw is not null and nullif(btrim(old.xml_raw), '') is not null then
    return new;
  end if;

  -- Importacao XML por usuarios nao-financeiros nao deve quebrar.
  -- O fluxo da API ja garante AP em etapa posterior via rotina privilegiada.
  if auth.uid() is not null and not f.has_finance_access(new.tenant_id, new.empresa_id) then
    return new;
  end if;

  v_emissao_date := (new.data_emissao at time zone 'America/Sao_Paulo')::date;
  v_xml := xmlparse(document new.xml_raw);
  v_dup_cnt := coalesce(array_length(xpath('//*[local-name()="cobr"]/*[local-name()="dup"]', v_xml), 1), 0);

  select t.id
    into v_titulo_id
  from f.documento_fiscal df
  join f.titulo t
    on t.tenant_id = df.tenant_id
   and t.documento_fiscal_id = df.id
   and t.tipo = 'AP'
   and t.deleted_at is null
  where df.tenant_id = new.tenant_id
    and df.source_nf_entrada_id = new.id
    and df.deleted_at is null
  limit 1;

  -- se ainda nao tem titulo/AP, cria/ajusta tudo
  if v_titulo_id is null then
    begin
      perform 1 from public.fn_fix_nf_entrada_pos_import(new.id);
    exception when others then
      return new;
    end;
    return new;
  end if;

  -- se ja teve baixa/pagamento, nao mexe
  if exists (
    select 1
    from f.titulo_parcela p
    where p.tenant_id = new.tenant_id
      and p.titulo_id = v_titulo_id
      and p.deleted_at is null
      and coalesce(p.valor_aberto, p.valor) <> p.valor
  ) then
    return new;
  end if;

  select count(*) into v_parc_cnt
  from f.titulo_parcela p
  where p.tenant_id = new.tenant_id
    and p.titulo_id = v_titulo_id
    and p.deleted_at is null;

  -- so corrige quando detecta "placeholder" 1x e o XML diz que e parcelado
  if v_dup_cnt > 1 and v_parc_cnt = 1 and exists (
    select 1
    from f.titulo_parcela p
    join f.titulo t on t.tenant_id = p.tenant_id and t.id = p.titulo_id
    where p.tenant_id = new.tenant_id
      and p.titulo_id = v_titulo_id
      and p.deleted_at is null
      and p.vencimento_date = v_emissao_date
      and abs(p.valor - t.valor_total) <= 0.01
  ) then
    begin
      perform 1 from public.fn_fix_nf_entrada_pos_import(new.id);
    exception when others then
      return new;
    end;
  end if;

  return new;
end;
$$;

commit;

