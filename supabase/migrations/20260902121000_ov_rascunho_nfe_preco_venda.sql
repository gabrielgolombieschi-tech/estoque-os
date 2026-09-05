begin;

-- A linha operacional da OV guarda custo em valor_unitario. O faturamento
-- precisa preservar, separadamente, o preco comercial aprovado no orcamento.
alter table public.os_itens
  add column orcamento_item_id uuid,
  add column valor_unitario_venda numeric(15,4),
  add constraint os_itens_valor_unitario_venda_ck
    check (valor_unitario_venda is null or valor_unitario_venda >= 0);

create unique index orcamento_item_tenant_empresa_id_ux
  on m.orcamento_item (tenant_id, empresa_id, id);

alter table public.os_itens
  add constraint os_itens_orcamento_item_escopo_fk
    foreign key (tenant_id, empresa_id, orcamento_item_id)
    references m.orcamento_item (tenant_id, empresa_id, id)
    on delete set null (orcamento_item_id);

create index os_itens_orcamento_item_idx
  on public.os_itens (tenant_id, empresa_id, orcamento_item_id)
  where orcamento_item_id is not null;

-- Relaciona o legado por ocorrencia do mesmo produto dentro da OV/orcamento.
-- A ordenacao torna o pareamento deterministico mesmo quando o item se repete.
with linhas_ov as (
  select
    oi.id,
    oi.tenant_id,
    oi.empresa_id,
    oi.os_id,
    oi.item_id,
    row_number() over (
      partition by oi.tenant_id, oi.empresa_id, oi.os_id, oi.item_id
      order by oi.id
    ) as ocorrencia
  from public.os_itens oi
  join public.ordens_servico os
    on os.tenant_id = oi.tenant_id
   and os.empresa_id = oi.empresa_id
   and os.id = oi.os_id
   and os.tipo_documento = 'OV'
),
linhas_orcamento as (
  select
    mo.tenant_id,
    mo.empresa_id,
    mo.os_id,
    moi.item_id,
    moi.id as orcamento_item_id,
    moi.valor_unitario_liquido,
    row_number() over (
      partition by mo.tenant_id, mo.empresa_id, mo.os_id, moi.item_id
      order by mo.updated_at desc, moi.seq, moi.id
    ) as ocorrencia
  from m.orcamento mo
  join m.orcamento_item moi
    on moi.tenant_id = mo.tenant_id
   and moi.empresa_id = mo.empresa_id
   and moi.orcamento_id = mo.id
   and moi.deleted_at is null
  where mo.os_id is not null
    and mo.deleted_at is null
),
pares as (
  select
    ov.id as os_item_id,
    ov.tenant_id,
    ov.empresa_id,
    oc.orcamento_item_id,
    oc.valor_unitario_liquido
  from linhas_ov ov
  join linhas_orcamento oc
    on oc.tenant_id = ov.tenant_id
   and oc.empresa_id = ov.empresa_id
   and oc.os_id = ov.os_id
   and oc.item_id = ov.item_id
   and oc.ocorrencia = ov.ocorrencia
)
update public.os_itens oi
set orcamento_item_id = p.orcamento_item_id,
    valor_unitario_venda = p.valor_unitario_liquido
from pares p
where oi.tenant_id = p.tenant_id
  and oi.empresa_id = p.empresa_id
  and oi.id = p.os_item_id
  and oi.orcamento_item_id is null;

create function public.trg_ov_item_preco_venda()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_orcamento_item_id uuid;
  v_valor_unitario_venda numeric(15,4);
begin
  if not exists (
    select 1
    from public.ordens_servico os
    where os.tenant_id = new.tenant_id
      and os.empresa_id = new.empresa_id
      and os.id = new.os_id
      and os.tipo_documento = 'OV'
  ) then
    return new;
  end if;

  if new.orcamento_item_id is not null then
    select moi.id, moi.valor_unitario_liquido
    into v_orcamento_item_id, v_valor_unitario_venda
    from m.orcamento_item moi
    join m.orcamento mo
      on mo.tenant_id = moi.tenant_id
     and mo.empresa_id = moi.empresa_id
     and mo.id = moi.orcamento_id
    where moi.tenant_id = new.tenant_id
      and moi.empresa_id = new.empresa_id
      and moi.id = new.orcamento_item_id
      and moi.item_id = new.item_id
      and moi.deleted_at is null
      and mo.os_id = new.os_id
      and mo.deleted_at is null;

    if not found then
      raise exception using
        errcode = '23503',
        message = 'A linha do orcamento nao pertence a esta OV, empresa e item.';
    end if;
  elsif new.valor_unitario_venda is null then
    select moi.id, moi.valor_unitario_liquido
    into v_orcamento_item_id, v_valor_unitario_venda
    from m.orcamento mo
    join m.orcamento_item moi
      on moi.tenant_id = mo.tenant_id
     and moi.empresa_id = mo.empresa_id
     and moi.orcamento_id = mo.id
     and moi.item_id = new.item_id
     and moi.deleted_at is null
    where mo.tenant_id = new.tenant_id
      and mo.empresa_id = new.empresa_id
      and mo.os_id = new.os_id
      and mo.deleted_at is null
      and not exists (
        select 1
        from public.os_itens usada
        where usada.tenant_id = new.tenant_id
          and usada.empresa_id = new.empresa_id
          and usada.orcamento_item_id = moi.id
          and usada.id is distinct from new.id
      )
    order by mo.updated_at desc, moi.seq, moi.id
    limit 1;
  end if;

  if v_orcamento_item_id is not null then
    new.orcamento_item_id := v_orcamento_item_id;
    new.valor_unitario_venda := v_valor_unitario_venda;
  end if;
  return new;
end;
$function$;

create trigger trg_ov_item_preco_venda
  before insert or update of os_id, item_id, orcamento_item_id
  on public.os_itens
  for each row execute function public.trg_ov_item_preco_venda();

comment on column public.os_itens.valor_unitario_venda is
  'Preco comercial aprovado para faturamento da OV. valor_unitario continua sendo custo operacional.';
comment on column public.os_itens.orcamento_item_id is
  'Linha do orcamento que originou a linha da OV e seu preco comercial.';

-- Ultima defesa: uma solicitacao de OV nunca pode copiar o custo operacional.
create function f.trg_solicitacao_item_preco_ov()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_preco numeric(15,4);
begin
  if new.origem_tipo <> 'OV' then
    return new;
  end if;
  if coalesce(new.origem_item_id, '') !~ '^[0-9]+$' then
    raise exception using errcode = '22023', message = 'Linha de OV sem origem_item_id inteiro.';
  end if;

  select oi.valor_unitario_venda
  into v_preco
  from public.os_itens oi
  where oi.tenant_id = new.tenant_id
    and oi.empresa_id = new.empresa_id
    and oi.id = new.origem_item_id::integer
    and oi.os_id::text = new.origem_id;

  if v_preco is null or v_preco <= 0 then
    raise exception using
      errcode = '22023',
      message = format(
        'A linha %s da OV nao tem preco de venda aprovado. O custo nao sera usado na NF-e.',
        new.origem_item_id
      );
  end if;

  new.valor_unitario := v_preco;
  new.valor_desconto := coalesce(new.valor_desconto, 0);
  return new;
end;
$function$;

create trigger trg_solicitacao_item_preco_ov
  before insert or update of valor_unitario, origem_tipo, origem_id, origem_item_id
  on f.solicitacao_item
  for each row execute function f.trg_solicitacao_item_preco_ov();

-- Corrige somente composicoes ainda editaveis e nunca uma solicitacao congelada
-- ou que ja tenha uma emissao preparada.
update f.solicitacao_item si
set valor_unitario = oi.valor_unitario_venda,
    valor_desconto = coalesce(si.valor_desconto, 0)
from f.solicitacao_faturamento sf
join public.os_itens oi
  on oi.tenant_id = sf.tenant_id
 and oi.empresa_id = sf.empresa_id
where si.tenant_id = sf.tenant_id
  and si.empresa_id = sf.empresa_id
  and si.solicitacao_id = sf.id
  and si.origem_tipo = 'OV'
  and si.origem_item_id ~ '^[0-9]+$'
  and oi.id = si.origem_item_id::integer
  and oi.os_id::text = si.origem_id
  and oi.valor_unitario_venda > 0
  and sf.status in ('RASCUNHO', 'PREVIA', 'APROVADA')
  and sf.snapshot_cadastro_em is null
  and not exists (
    select 1
    from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = sf.tenant_id
      and dfe.empresa_id = sf.empresa_id
      and dfe.solicitacao_id = sf.id
  );

-- Salva a conferencia humana em uma unica transacao. O payload continuara
-- lendo exclusivamente a solicitacao congelada, sem fallback para perfil.
create function f.fn_solicitacao_nfe_salvar_conferencia(
  p_solicitacao_id uuid,
  p_operacao jsonb,
  p_itens jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_item record;
  v_total_itens integer;
  v_usuario_id uuid := a.fn_current_usuario_id();
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Rascunho de NF-e nao encontrado.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Esta solicitacao nao pode mais ser alterada.';
  end if;
  if exists (
    select 1 from f.documento_fiscal_emissao dfe
    where dfe.tenant_id = v_sf.tenant_id
      and dfe.empresa_id = v_sf.empresa_id
      and dfe.solicitacao_id = v_sf.id
  ) then
    raise exception using errcode = '22023', message = 'A emissao desta solicitacao ja foi preparada e seus dados estao congelados.';
  end if;
  if jsonb_typeof(p_operacao) <> 'object' or jsonb_typeof(p_itens) <> 'array' then
    raise exception using errcode = '22023', message = 'Operacao e itens da conferencia sao obrigatorios.';
  end if;

  select count(*) into v_total_itens
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if v_total_itens = 0
     or jsonb_array_length(p_itens) <> v_total_itens
     or (select count(distinct x.id) from jsonb_to_recordset(p_itens) x(id uuid)) <> v_total_itens then
    raise exception using errcode = '22023', message = 'A conferencia deve conter todas as linhas da solicitacao, sem duplicidade.';
  end if;

  update f.solicitacao_faturamento
  set finalidade_emissao = nullif(p_operacao->>'finalidade_emissao', '')::smallint,
      consumidor_final = nullif(p_operacao->>'consumidor_final', '')::smallint,
      presenca_comprador = nullif(p_operacao->>'presenca_comprador', '')::smallint,
      modalidade_frete = nullif(p_operacao->>'modalidade_frete', '')::smallint,
      valor_frete = nullif(p_operacao->>'valor_frete', '')::numeric,
      valor_seguro = nullif(p_operacao->>'valor_seguro', '')::numeric,
      valor_outras_despesas = nullif(p_operacao->>'valor_outras_despesas', '')::numeric,
      revisao_fiscal_confirmada_em = case when v_usuario_id is null then null else now() end,
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null,
      destinatario_snapshot = null,
      operacao_snapshot = null,
      snapshot_cadastro_em = null,
      status = 'PREVIA',
      updated_at = now()
  where id = v_sf.id;

  for v_item in
    select *
    from jsonb_to_recordset(p_itens) as x(
      id uuid,
      cfop text,
      cst_icms text,
      csosn text,
      cst_ipi text,
      cst_pis text,
      cst_cofins text,
      cbenef text,
      reducao_base_icms_percentual numeric,
      icms_modalidade_base_calculo text,
      aliquota_icms numeric,
      aliquota_ipi numeric,
      aliquota_pis numeric,
      aliquota_cofins numeric
    )
  loop
    update f.solicitacao_item si
    set cfop = nullif(regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g'), ''),
        cst_icms = nullif(btrim(v_item.cst_icms), ''),
        csosn = nullif(btrim(v_item.csosn), ''),
        cst_ipi = nullif(btrim(v_item.cst_ipi), ''),
        cst_pis = nullif(btrim(v_item.cst_pis), ''),
        cst_cofins = nullif(btrim(v_item.cst_cofins), ''),
        cbenef = nullif(btrim(v_item.cbenef), ''),
        reducao_base_icms_percentual = v_item.reducao_base_icms_percentual,
        icms_modalidade_base_calculo = nullif(btrim(v_item.icms_modalidade_base_calculo), ''),
        aliquota_icms = v_item.aliquota_icms,
        aliquota_ipi = v_item.aliquota_ipi,
        aliquota_pis = v_item.aliquota_pis,
        aliquota_cofins = v_item.aliquota_cofins
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item.id;

    if not found then
      raise exception using errcode = '22023', message = format('Item %s nao pertence a esta solicitacao.', v_item.id);
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'solicitacao_id', v_sf.id, 'itens', v_total_itens);
end;
$function$;

comment on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) is
  'Salva, de forma atomica, os dados fiscais e operacionais explicitamente conferidos antes da emissao em homologacao.';

revoke all on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb)
  from public, anon;
grant execute on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb)
  to authenticated, service_role;

commit;
