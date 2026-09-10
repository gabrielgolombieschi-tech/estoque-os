-- Transportadora padrao do cliente, para nao redigitar a cada venda.
--
-- Gabriel em 10/09/2026, na tela de emissao da OV: a Portobello ja usou a mesma
-- transportadora (TEDE TRANSPORTES LTDA) em 12 conferencias dentro da OV-SEG-00004-026
-- — mas a "memoria" que ja existia (memoriaDeSolicitacao em OvNfeDraftsPanel.tsx) so
-- olha para a ultima nota conferida da MESMA OV. Numa OV nova do mesmo cliente, os
-- campos de frete e transportadora voltavam a ficar vazios.
--
-- O que se repete de fato para o mesmo cliente e a transportadora e a modalidade do
-- frete — quem transporta pra ele nao muda venda a venda. Quantidade de volumes e peso
-- continuam variando por pedido e nao entram aqui; continuam vindo so da memoria da
-- propria OV.

alter table public.clientes
  add column if not exists transportador_padrao_nome text,
  add column if not exists transportador_padrao_documento text,
  add column if not exists transportador_padrao_ie text,
  add column if not exists transportador_padrao_endereco text,
  add column if not exists transportador_padrao_municipio text,
  add column if not exists transportador_padrao_uf text,
  add column if not exists transportador_padrao_modalidade_frete smallint,
  add column if not exists transportador_padrao_atualizado_em timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clientes_transportador_padrao_modalidade_ck'
  ) then
    alter table public.clientes
      add constraint clientes_transportador_padrao_modalidade_ck
      check (transportador_padrao_modalidade_frete is null or transportador_padrao_modalidade_frete in (0, 1, 2, 3, 4, 9));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'clientes_transportador_padrao_uf_ck'
  ) then
    alter table public.clientes
      add constraint clientes_transportador_padrao_uf_ck
      check (transportador_padrao_uf is null or transportador_padrao_uf ~ '^[A-Z]{2}$');
  end if;
end
$$;

comment on column public.clientes.transportador_padrao_nome is
  'Transportadora sugerida na proxima venda deste cliente. Preenchida automaticamente ao confirmar uma operacao de NF-e com transportadora; sempre revisavel na conferencia.';
comment on column public.clientes.transportador_padrao_modalidade_frete is
  'Modalidade do frete (CFOP/NF-e modFrete) sugerida na proxima venda deste cliente. 0 emitente, 1 destinatario, 2 terceiros, 3 proprio emitente, 4 proprio destinatario, 9 sem frete.';

-- Grava o padrao do cliente. Mesma regua de quem pode emitir a NF-e da OV
-- (f.has_finance_access), porque e exatamente esse ato que alimenta o padrao.
create or replace function public.clientes_salvar_transportador_padrao(
  p_cliente_id integer,
  p_nome text,
  p_documento text,
  p_ie text,
  p_endereco text,
  p_municipio text,
  p_uf text,
  p_modalidade_frete smallint,
  p_empresa_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_tenant uuid;
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Nao autenticado.';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception using errcode = '22023', message = 'Tenant atual nao definido.';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception using errcode = '22023', message = 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;
  perform public.set_current_empresa(v_empresa);

  if not f.has_finance_access(v_tenant, v_empresa) then
    raise exception using errcode = '42501', message = 'Sem permissao para gravar dados de transporte do cliente.';
  end if;

  if p_modalidade_frete is not null and p_modalidade_frete not in (0, 1, 2, 3, 4, 9) then
    raise exception using errcode = '22023', message = format('Modalidade de frete %s invalida.', p_modalidade_frete);
  end if;

  update public.clientes c
     set transportador_padrao_nome = nullif(btrim(p_nome), ''),
         transportador_padrao_documento = nullif(btrim(coalesce(p_documento, '')), ''),
         transportador_padrao_ie = nullif(btrim(coalesce(p_ie, '')), ''),
         transportador_padrao_endereco = nullif(btrim(coalesce(p_endereco, '')), ''),
         transportador_padrao_municipio = nullif(btrim(coalesce(p_municipio, '')), ''),
         transportador_padrao_uf = nullif(upper(btrim(coalesce(p_uf, ''))), ''),
         transportador_padrao_modalidade_frete = p_modalidade_frete,
         transportador_padrao_atualizado_em = now(),
         atualizado_em = now()
   where c.tenant_id = v_tenant
     and c.empresa_id = v_empresa
     and c.id = p_cliente_id;

  if not found then
    raise exception using errcode = '22023', message = format('Cliente %s nao encontrado nesta empresa.', p_cliente_id);
  end if;
end;
$function$;

comment on function public.clientes_salvar_transportador_padrao(integer, text, text, text, text, text, text, smallint, uuid) is
  'Grava a transportadora e a modalidade de frete padrao de um cliente, para pre-preencher a proxima venda. Chamada automaticamente ao confirmar uma operacao de NF-e com transportadora preenchida.';

revoke all on function public.clientes_salvar_transportador_padrao(integer, text, text, text, text, text, text, smallint, uuid) from public;
grant execute on function public.clientes_salvar_transportador_padrao(integer, text, text, text, text, text, text, smallint, uuid) to authenticated, service_role;
