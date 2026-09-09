-- Cancelar a nota tira a OS do estado de faturamento.
--
-- Decisao de Gabriel em 09/09/2026, depois de cancelar as NF-e 2/5 a 2/8 por erro na
-- base de PIS/COFINS. O os_faturar marcava a OS como faturada, mas nada desmarcava
-- quando a unica nota que sustentava a marcacao era cancelada: a OS 287 ficou
-- "faturada", com R$ 21.303,95 de saldo aberto e sem nota valida, e a tela de faturar
-- a recusava com "OS ja faturada". Nao havia saida — os_reabrir_correcao so aceita OS
-- em "concluida".
--
-- Regra: cancelou a nota e nao sobrou nenhuma nota valida vinculada, a OS sai do
-- faturamento e volta para CONCLUIDA (nao para em andamento) — pronta para refaturar,
-- sem perder a conclusao que ja tinha. O saldo ja se refaz sozinho, porque a funcao de
-- saldo so conta nota emitida.
--
-- A checagem e "nao resta nota valida", e nao "saldo zerou", de proposito: e objetiva,
-- nao depende do contexto de permissao de fn_os_saldo_a_faturar e e conservadora —
-- havendo outra nota emitida na OS, nada e revertido e a decisao fica com quem fatura.
--
-- O saneamento no fim e restrito a OS que TIVERAM nota e a perderam por cancelamento.
-- Um saneamento amplo seria desastroso: 152 das 226 OS faturadas hoje sao do legado e
-- nunca tiveram documento fiscal vinculado — elas nao podem ser tocadas. Com o filtro,
-- alcanca exatamente a OS 287.

create or replace function f.fn_os_reverter_faturada_sem_nota(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_status text;
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    return false;
  end if;

  select os.status_fluxo into v_status
  from public.ordens_servico os
  where os.id = p_os_id and os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id
  for update;

  if not found or upper(coalesce(v_status, '')) <> 'FATURADA' then
    return false;
  end if;

  -- A OS precisa ter tido nota neste sistema. Sem nenhum documento fiscal vinculado
  -- ela foi faturada por outro caminho — 152 das 226 OS faturadas hoje sao do legado —
  -- e nao e assunto desta funcao. A guarda fica aqui, e nao so em quem chama, para que
  -- uma chamada direta tambem nao consiga desfazer o historico do legado.
  if not exists (
    select 1
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id and df.os_id_import = p_os_id
      and df.operacao = 'SAIDA' and df.deleted_at is null
  ) then
    return false;
  end if;

  -- Sobrou nota valida sustentando o faturamento: nada a fazer.
  if exists (
    select 1
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id and df.os_id_import = p_os_id
      and df.operacao = 'SAIDA' and df.deleted_at is null
      and ((upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
        or (upper(coalesce(df.modelo, '')) <> 'NFSE' and (nullif(upper(btrim(coalesce(df.nfe_status, ''))), '') is null or upper(coalesce(df.nfe_status, '')) = 'EMITIDA')))
  ) then
    return false;
  end if;

  update public.ordens_servico
     set status_fluxo = 'concluida',
         status = 'concluida',
         faturado_em = null,
         faturada_presumida_legado = false,
         atualizado_em = now()
   where id = p_os_id and tenant_id = p_tenant_id and empresa_id = p_empresa_id;

  insert into public.ordens_servico_fluxo_eventos
    (tenant_id, empresa_id, os_id, evento, status_origem, status_destino, motivo, realizado_por)
  values (p_tenant_id, p_empresa_id, p_os_id, 'reverter_faturada', 'faturada', 'concluida',
    'Nota fiscal cancelada e nenhuma outra nota emitida na OS; volta para concluida.', auth.uid());

  return true;
end;
$function$;

create or replace function f.trg_documento_fiscal__reverter_os_faturada()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  perform f.fn_os_reverter_faturada_sem_nota(new.tenant_id, new.empresa_id, new.os_id_import);
  return null;
end;
$function$;

-- AFTER UPDATE: a nota ja esta cancelada quando a checagem roda. Cobre NF-e, NFS-e e a
-- exclusao logica, que sao os tres jeitos de uma nota deixar de valer.
drop trigger if exists trg_documento_fiscal__reverter_os_faturada on f.documento_fiscal;
create trigger trg_documento_fiscal__reverter_os_faturada
after update on f.documento_fiscal
for each row
when (
  new.os_id_import is not null
  and (
    (coalesce(old.nfe_status, '') is distinct from coalesce(new.nfe_status, '') and upper(coalesce(new.nfe_status, '')) = 'CANCELADA')
    or (coalesce(old.nfse_status, '') is distinct from coalesce(new.nfse_status, '') and upper(coalesce(new.nfse_status, '')) = 'CANCELADA')
    or (old.deleted_at is null and new.deleted_at is not null)
  )
)
execute function f.trg_documento_fiscal__reverter_os_faturada();

-- Saneamento restrito: so OS que tiveram nota e a perderam por cancelamento.
do $sanear$
declare
  r record;
  v_total integer := 0;
begin
  for r in
    select o.id, o.os_num, o.tenant_id, o.empresa_id
    from public.ordens_servico o
    where o.status_fluxo = 'faturada'
      and exists (
        select 1 from f.documento_fiscal df
        where df.tenant_id = o.tenant_id and df.empresa_id = o.empresa_id and df.os_id_import = o.id
          and df.operacao = 'SAIDA' and df.deleted_at is null
          and upper(coalesce(df.nfe_status, df.nfse_status, '')) = 'CANCELADA'
      )
  loop
    if f.fn_os_reverter_faturada_sem_nota(r.tenant_id, r.empresa_id, r.id) then
      v_total := v_total + 1;
      raise notice 'OS %: saiu do faturamento (nota cancelada, sem outra nota valida).', r.os_num;
    end if;
  end loop;
  raise notice 'Saneamento concluido: % OS revertidas.', v_total;
end
$sanear$;
