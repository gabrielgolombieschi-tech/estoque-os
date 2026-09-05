begin;

-- O perfil passa a declarar o contexto em que pode ser usado. A tela apenas
-- resolve esse cadastro; ela nao cria CFOP, CST ou aliquota por conta propria.
alter table f.perfil_operacao
  add column ambito_destino text
    check (ambito_destino is null or ambito_destino in ('INTERNA', 'INTERESTADUAL')),
  add column ufs_destino text[],
  add column indicador_ie_destinatario text
    check (indicador_ie_destinatario is null or indicador_ie_destinatario in ('1', '2', '9')),
  add column icms_modalidade_base_calculo text,
  add column finalidade_emissao smallint
    check (finalidade_emissao is null or finalidade_emissao between 1 and 4),
  add column consumidor_final smallint
    check (consumidor_final is null or consumidor_final in (0, 1)),
  add column cbenef_aplicacao text not null default 'NAO_CONFIRMADO'
    check (cbenef_aplicacao in ('NAO_CONFIRMADO', 'SEM_BENEFICIO', 'COM_BENEFICIO')),
  add column ibs_cbs_json jsonb,
  add constraint perfil_operacao_cbenef_aplicacao_ck
    check (
      cbenef_aplicacao = 'NAO_CONFIRMADO'
      or (cbenef_aplicacao = 'SEM_BENEFICIO' and nullif(btrim(cbenef), '') is null)
      or (cbenef_aplicacao = 'COM_BENEFICIO' and nullif(btrim(cbenef), '') is not null)
    ),
  add constraint perfil_operacao_ufs_destino_ck
    check (ufs_destino is null or cardinality(ufs_destino) > 0),
  add constraint perfil_operacao_ibs_cbs_json_ck
    check (ibs_cbs_json is null or jsonb_typeof(ibs_cbs_json) = 'object');

update f.perfil_operacao
set cbenef_aplicacao = 'COM_BENEFICIO'
where nullif(btrim(cbenef), '') is not null;

comment on column f.perfil_operacao.ambito_destino is
  'Escopo territorial explicito do perfil. NULL significa perfil legado ainda nao classificado.';
comment on column f.perfil_operacao.ufs_destino is
  'UFs para as quais o perfil foi confirmado. NULL nao autoriza fallback territorial.';
comment on column f.perfil_operacao.cbenef_aplicacao is
  'Distingue perfil sem revisao, sem beneficio e com beneficio; NULL em cBenef deixa de ser ambiguo.';
comment on column f.perfil_operacao.ibs_cbs_json is
  'Aliquotas IBS UF, IBS municipal e CBS confirmadas no perfil. Nunca recebe defaults da tela.';

alter table f.solicitacao_faturamento
  add column destino_uf_confirmada text
    check (destino_uf_confirmada is null or destino_uf_confirmada ~ '^[A-Z]{2}$'),
  add column destino_confirmado_em timestamptz,
  add column destino_confirmado_por uuid references a.usuario(id) on delete set null,
  add column perfil_aplicado_em timestamptz,
  add column perfil_aplicado_por uuid references a.usuario(id) on delete set null,
  add constraint solicitacao_destino_confirmacao_par_ck
    check (
      (destino_uf_confirmada is null and destino_confirmado_em is null and destino_confirmado_por is null)
      or (destino_uf_confirmada is not null and destino_confirmado_em is not null)
    ),
  add constraint solicitacao_snapshot_destino_confirmado_ck
    check (snapshot_cadastro_em is null or destino_uf_confirmada is not null) not valid;

alter table f.solicitacao_item
  add column perfil_operacao_id uuid,
  add column perfil_aplicado_em timestamptz,
  add column perfil_aplicado_por uuid references a.usuario(id) on delete set null,
  add constraint solicitacao_item_perfil_escopo_fk
    foreign key (tenant_id, perfil_operacao_id)
    references f.perfil_operacao(tenant_id, id);

create index solicitacao_item_perfil_idx
  on f.solicitacao_item (tenant_id, empresa_id, perfil_operacao_id)
  where perfil_operacao_id is not null;

-- IPI e FCI pertencem ao produto, nao ao perfil da operacao.
alter table public.fiscal_itens
  add column cst_ipi text
    check (cst_ipi is null or cst_ipi ~ '^[0-9]{2}$'),
  add column ipi_codigo_enquadramento_legal text
    check (
      ipi_codigo_enquadramento_legal is null
      or ipi_codigo_enquadramento_legal ~ '^[0-9]{3}$'
    ),
  add column numero_fci text;

alter table f.solicitacao_item
  add column numero_fci text;

comment on column public.fiscal_itens.cst_ipi is 'CST de IPI proprio do produto.';
comment on column public.fiscal_itens.ipi_codigo_enquadramento_legal is
  'cEnq do IPI proprio do produto; nunca recebe 999 por fallback.';
comment on column public.fiscal_itens.numero_fci is
  'Numero da FCI do produto quando aplicavel. Ausencia nao e interpretada como dispensa.';

-- Corrige somente o perfil criado na migration anterior. A evidencia conserva
-- o IPI observado na nota; o perfil de operacao deixa de propaga-lo a produtos.
update f.perfil_operacao
set ambito_destino = 'INTERNA',
    ufs_destino = array['SC']::text[],
    indicador_ie_destinatario = '1',
    icms_modalidade_base_calculo = '3',
    finalidade_emissao = 1,
    consumidor_final = 0,
    reducao_base_icms_percentual = 0,
    cbenef_aplicacao = 'SEM_BENEFICIO',
    cst_ipi = null,
    aliquota_ipi = null
where tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
  and codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00';

-- O CST 53 fica no produto que efetivamente constou na homologacao. O cEnq
-- antigo nao e copiado porque havia sido criado pelo fallback removido.
update public.fiscal_itens fi
set cst_ipi = si.cst_ipi,
    atualizado_em = now()
from f.solicitacao_item si
join f.documento_fiscal_emissao dfe
  on dfe.tenant_id = si.tenant_id
 and dfe.empresa_id = si.empresa_id
 and dfe.solicitacao_id = si.solicitacao_id
where dfe.chave_acesso = '42260913671448000189550020000000011615133155'
  and dfe.status = 'AUTORIZADA'
  and si.item_id is not null
  and fi.tenant_id = si.tenant_id
  and fi.empresa_id = si.empresa_id
  and fi.item_id = si.item_id
  and nullif(btrim(si.cst_ipi), '') is not null;

create or replace function f.fn_solicitacao_nfe_resolver_perfis(
  p_solicitacao_id uuid,
  p_destino_uf text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_cliente public.clientes%rowtype;
  v_uf_emitente text;
  v_uf_destino text := upper(btrim(coalesce(p_destino_uf, '')));
  v_crt text;
  v_ambito text;
  v_itens jsonb;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Rascunho de NF-e nao encontrado.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para resolver o perfil fiscal desta NF-e.';
  end if;

  select * into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id
    and c.empresa_id = v_sf.empresa_id
    and c.id = v_sf.cliente_id
    and c.ativo is true;
  if not found then
    return jsonb_build_object('ok', false, 'bloqueio', 'Destinatario ativo nao encontrado nesta empresa.');
  end if;

  select upper(ee.uf::text), ef.crt::text
    into v_uf_emitente, v_crt
  from c.empresa e
  join c.empresa_fiscal ef on ef.empresa_id = e.id and ef.deleted_at is null
  join lateral (
    select x.uf
    from c.empresa_endereco x
    where x.empresa_id = e.id and x.deleted_at is null
    order by (x.tipo = 'FISCAL') desc, x.updated_at desc
    limit 1
  ) ee on true
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null;

  if v_uf_destino !~ '^[A-Z]{2}$' then
    return jsonb_build_object(
      'ok', false, 'bloqueio', 'Confirme uma UF de destino valida.',
      'uf_cliente', upper(nullif(btrim(v_cliente.uf), '')),
      'indicador_ie', v_cliente.indicador_ie
    );
  end if;
  if upper(coalesce(v_cliente.uf, '')) <> v_uf_destino then
    return jsonb_build_object(
      'ok', false,
      'bloqueio', 'A UF informada nao corresponde ao cadastro do destinatario.',
      'uf_emitente', v_uf_emitente, 'uf_cliente', upper(nullif(btrim(v_cliente.uf), '')),
      'uf_confirmada', v_uf_destino, 'indicador_ie', v_cliente.indicador_ie,
      'rota_cliente', '/clientes/cadastro-fiscal?cliente_id=' || v_cliente.id::text
    );
  end if;
  if v_uf_emitente is null then
    return jsonb_build_object('ok', false, 'bloqueio', 'A UF fiscal do emitente nao esta cadastrada.');
  end if;

  v_ambito := case when v_uf_destino = v_uf_emitente then 'INTERNA' else 'INTERESTADUAL' end;
  if v_ambito = 'INTERESTADUAL' and coalesce(v_cliente.indicador_ie, '') <> '1' then
    return jsonb_build_object(
      'ok', false,
      'bloqueio', 'Operacao interestadual para nao contribuinte exige perfil proprio de DIFAL.',
      'uf_emitente', v_uf_emitente, 'uf_cliente', upper(v_cliente.uf),
      'uf_confirmada', v_uf_destino, 'ambito', v_ambito,
      'indicador_ie', v_cliente.indicador_ie,
      'rota_cliente', '/clientes/cadastro-fiscal?cliente_id=' || v_cliente.id::text
    );
  end if;

  with itens_base as (
    select si.id, si.item_id, si.ordem, si.descricao,
           fi.item_id is not null as cadastro_fiscal_existe,
           coalesce(fi.origem, si.origem_mercadoria) as origem_mercadoria,
           coalesce(fi.ncm, si.ncm) as ncm,
           coalesce(fi.unidade_tributavel, si.unidade_tributavel) as unidade_tributavel,
           coalesce(fi.cst_ipi, si.cst_ipi) as cst_ipi_produto,
           coalesce(fi.ipi_codigo_enquadramento_legal, si.ipi_codigo_enquadramento_legal) as cenq_ipi_produto,
           coalesce(fi.aliq_ipi, si.aliquota_ipi) as aliquota_ipi_produto,
           coalesce(fi.numero_fci, si.numero_fci) as numero_fci_produto,
           fi.cest as cest_produto
    from f.solicitacao_item si
    left join public.fiscal_itens fi
      on fi.tenant_id = si.tenant_id
     and fi.empresa_id = si.empresa_id
     and fi.item_id = si.item_id
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
  ), classificados as (
    select ib.*,
      case
        when v_ambito <> 'INTERESTADUAL' then null::numeric
        when ib.origem_mercadoria in (1, 2, 6) then 4::numeric
        when v_uf_destino in ('PR', 'RS', 'SP', 'RJ', 'MG') then 12::numeric
        else 7::numeric
      end as aliquota_referencia
    from itens_base ib
  ), resolvidos as (
    select c.*,
           coalesce(px.quantidade, 0) as perfis_encontrados,
           px.perfil
    from classificados c
    left join lateral (
      select count(*)::integer as quantidade,
             (jsonb_agg(to_jsonb(po) order by
                (po.empresa_id is not null) desc,
                (po.origem_mercadoria is not null) desc,
                po.vigencia_inicio desc,
                po.id
              )->0) as perfil
      from f.perfil_operacao po
      where po.tenant_id = v_sf.tenant_id
        and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
        and po.modelo = 'NFE'
        and po.natureza_operacao = v_sf.natureza_operacao
        and (po.crt is null or po.crt = v_crt)
        and po.ambito_destino = v_ambito
        and po.ufs_destino is not null
        and v_uf_destino = any(po.ufs_destino)
        and (po.indicador_ie_destinatario is null or po.indicador_ie_destinatario = v_cliente.indicador_ie)
        and (po.origem_mercadoria is null or po.origem_mercadoria = c.origem_mercadoria)
        and (
          (v_ambito = 'INTERNA' and po.cfop_interno is not null)
          or (po.cfop_externo is not null and po.aliquota_icms = c.aliquota_referencia)
        )
        and po.faixa_automacao <> 'BLOQUEADO'
        and po.vigencia_inicio <= current_date
        and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
    ) px on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'solicitacao_item_id', r.id,
    'item_id', r.item_id,
    'ordem', r.ordem,
    'descricao', r.descricao,
    'origem_mercadoria', r.origem_mercadoria,
    'produto', jsonb_build_object(
      'ncm', r.ncm,
      'cest', r.cest_produto,
      'unidade_tributavel', r.unidade_tributavel,
      'cst_ipi', r.cst_ipi_produto,
      'ipi_codigo_enquadramento_legal', r.cenq_ipi_produto,
      'aliquota_ipi', r.aliquota_ipi_produto,
      'numero_fci', r.numero_fci_produto
    ),
    'aliquota_referencia_busca', r.aliquota_referencia,
    'perfis_encontrados', r.perfis_encontrados,
    'status', case
      when not r.cadastro_fiscal_existe
        or r.origem_mercadoria is null
        or nullif(btrim(r.cst_ipi_produto), '') is null
        or nullif(btrim(r.cenq_ipi_produto), '') is null then 'PRODUTO_INCOMPLETO'
      when r.perfis_encontrados = 0 then 'SEM_PERFIL'
      when r.perfis_encontrados > 1 then 'AMBIGUO'
      else 'RESOLVIDO'
    end,
    'motivo', case
      when not r.cadastro_fiscal_existe then 'O item nao possui cadastro fiscal do produto.'
      when r.origem_mercadoria is null then 'Origem da mercadoria nao informada no produto.'
      when nullif(btrim(r.cst_ipi_produto), '') is null then 'CST IPI nao informado no cadastro fiscal do produto.'
      when nullif(btrim(r.cenq_ipi_produto), '') is null then 'cEnq IPI nao informado no cadastro fiscal do produto.'
      when r.perfis_encontrados = 0 then format(
        'Nenhum perfil fiscal para %s, UF %s, indicador IE %s, origem %s%s.',
        v_ambito, v_uf_destino, coalesce(v_cliente.indicador_ie, '<vazio>'),
        r.origem_mercadoria,
        case when r.aliquota_referencia is null then '' else ', faixa interestadual ' || r.aliquota_referencia::text || '%' end
      )
      when r.perfis_encontrados > 1 then 'Mais de um perfil fiscal se aplica a esta linha.'
      else null
    end,
    'perfil_id', case when r.perfis_encontrados = 1 then r.perfil->>'id' else null end,
    'perfil_codigo', case when r.perfis_encontrados = 1 then r.perfil->>'codigo' else null end,
    'perfil', case when r.perfis_encontrados = 1 then r.perfil else null end
  ) order by r.ordem, r.id), '[]'::jsonb)
  into v_itens
  from resolvidos r;

  return jsonb_build_object(
    'ok', true,
    'uf_emitente', v_uf_emitente,
    'uf_cliente', upper(v_cliente.uf),
    'uf_confirmada', v_uf_destino,
    'ambito', v_ambito,
    'indicador_ie', v_cliente.indicador_ie,
    'cliente_id', v_cliente.id,
    'rota_cliente', '/clientes/cadastro-fiscal?cliente_id=' || v_cliente.id::text,
    'itens', v_itens
  );
end;
$function$;

comment on function f.fn_solicitacao_nfe_resolver_perfis(uuid, text) is
  'Confirma a UF do destinatario e procura perfis por empresa, CRT, natureza, destino, IE e origem por item. A faixa 4/7/12 classifica a busca; nunca vira tributo sem perfil.';
revoke all on function f.fn_solicitacao_nfe_resolver_perfis(uuid, text) from public, anon;
grant execute on function f.fn_solicitacao_nfe_resolver_perfis(uuid, text) to authenticated, service_role;

create or replace function f.fn_solicitacao_nfe_salvar_conferencia(
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
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_item record;
  v_total_itens integer;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_destino_uf text := upper(btrim(coalesce(p_operacao->>'destino_uf_confirmada', '')));
  v_resolucao jsonb;
  v_resolvido jsonb;
  v_perfil f.perfil_operacao%rowtype;
  v_fiscal_item public.fiscal_itens%rowtype;
  v_perfil_esperado uuid;
  v_cfop_esperado text;
  v_ambito text;
  v_perfis_distintos integer;
  v_perfil_unico uuid;
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

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
  order by case when dfe.ambiente = 'PRODUCAO' then 0 else 1 end,
           dfe.created_at desc, dfe.documento_fiscal_id
  limit 1
  for update;
  if found and v_emissao.status not in ('REJEITADA', 'ERRO', 'RASCUNHO') then
    raise exception using errcode = '22023', message = 'Somente uma emissao rejeitada, com erro ou ainda em rascunho pode ser corrigida.';
  end if;
  if jsonb_typeof(p_operacao) <> 'object' or jsonb_typeof(p_itens) <> 'array' then
    raise exception using errcode = '22023', message = 'Operacao e itens da conferencia sao obrigatorios.';
  end if;
  if v_destino_uf !~ '^[A-Z]{2}$' then
    raise exception using errcode = '22023', message = 'A UF de destino precisa ser confirmada antes da conferencia fiscal.';
  end if;
  if nullif(btrim(p_operacao->>'finalidade_emissao'), '') is null
     or nullif(btrim(p_operacao->>'consumidor_final'), '') is null
     or nullif(btrim(p_operacao->>'presenca_comprador'), '') is null
     or nullif(btrim(p_operacao->>'modalidade_frete'), '') is null
     or nullif(btrim(p_operacao->>'valor_frete'), '') is null
     or nullif(btrim(p_operacao->>'valor_seguro'), '') is null
     or nullif(btrim(p_operacao->>'valor_outras_despesas'), '') is null then
    raise exception using errcode = '22023', message = 'Finalidade, consumidor, presenca, frete, seguro e outras despesas devem ser confirmados explicitamente.';
  end if;

  v_resolucao := f.fn_solicitacao_nfe_resolver_perfis(v_sf.id, v_destino_uf);
  if not coalesce((v_resolucao->>'ok')::boolean, false) then
    raise exception using errcode = '22023', message = coalesce(v_resolucao->>'bloqueio', 'Destino fiscal invalido.');
  end if;
  v_ambito := v_resolucao->>'ambito';

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
      destino_uf_confirmada = v_destino_uf,
      destino_confirmado_em = now(),
      destino_confirmado_por = v_usuario_id,
      perfil_aplicado_em = now(),
      perfil_aplicado_por = v_usuario_id,
      revisao_fiscal_confirmada_em = case when v_usuario_id is null then null else now() end,
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null, destinatario_snapshot = null,
      operacao_snapshot = null, snapshot_cadastro_em = null,
      status = 'PREVIA', updated_at = now()
  where tenant_id = v_sf.tenant_id
    and empresa_id = v_sf.empresa_id
    and id = v_sf.id;

  for v_item in
    select *
    from jsonb_to_recordset(p_itens) as x(
      id uuid, perfil_operacao_id uuid, cfop text, cst_icms text, csosn text,
      cst_ipi text, ipi_codigo_enquadramento_legal text, cst_pis text,
      cst_cofins text, cbenef text, reducao_base_icms_percentual numeric,
      icms_modalidade_base_calculo text, aliquota_icms numeric, aliquota_ipi numeric,
      aliquota_pis numeric, aliquota_cofins numeric, cst_ibs_cbs text,
      cclass_trib text, cclass_trib_versao text, ibs_cbs_json jsonb,
      numero_fci text
    )
  loop
    select x.value into v_resolvido
    from jsonb_array_elements(v_resolucao->'itens') x(value)
    where x.value->>'solicitacao_item_id' = v_item.id::text;
    if v_resolvido is null then
      raise exception using errcode = '22023', message = format('Item %s nao pertence a esta solicitacao.', v_item.id);
    end if;
    if v_resolvido->>'status' is distinct from 'RESOLVIDO' then
      raise exception using errcode = '22023', message = coalesce(
        v_resolvido->>'motivo',
        format('O perfil fiscal do item %s nao foi resolvido pelo servidor.', v_item.id)
      );
    end if;

    v_perfil_esperado := nullif(v_resolvido->>'perfil_id', '')::uuid;
    if v_item.perfil_operacao_id is distinct from v_perfil_esperado then
      raise exception using errcode = '22023', message = format('O perfil fiscal do item %s nao corresponde ao perfil resolvido pelo servidor.', v_item.id);
    end if;

    select fi.* into v_fiscal_item
    from f.solicitacao_item si
    join public.fiscal_itens fi
      on fi.tenant_id = si.tenant_id
     and fi.empresa_id = si.empresa_id
     and fi.item_id = si.item_id
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item.id;
    if not found then
      raise exception using errcode = '22023', message = format('O item %s nao possui cadastro fiscal do produto.', v_item.id);
    end if;
    if nullif(btrim(v_fiscal_item.cst_ipi), '') is null
       or nullif(btrim(v_fiscal_item.ipi_codigo_enquadramento_legal), '') is null then
      raise exception using errcode = '22023', message = format('Complete CST IPI e cEnq no cadastro fiscal do produto antes de emitir o item %s.', v_item.id);
    end if;
    if nullif(btrim(v_item.cst_ipi), '') is distinct from nullif(btrim(v_fiscal_item.cst_ipi), '')
       or nullif(regexp_replace(coalesce(v_item.ipi_codigo_enquadramento_legal, ''), '[^0-9]', '', 'g'), '')
          is distinct from nullif(regexp_replace(coalesce(v_fiscal_item.ipi_codigo_enquadramento_legal, ''), '[^0-9]', '', 'g'), '')
       or (v_fiscal_item.aliq_ipi is not null and v_item.aliquota_ipi is distinct from v_fiscal_item.aliq_ipi)
       or nullif(btrim(v_item.numero_fci), '') is distinct from nullif(btrim(v_fiscal_item.numero_fci), '') then
      raise exception using errcode = '22023', message = format('Os dados de IPI/FCI do item %s devem vir do cadastro fiscal do produto.', v_item.id);
    end if;

    v_perfil := null;
    if v_perfil_esperado is not null then
      select * into v_perfil
      from f.perfil_operacao po
      where po.tenant_id = v_sf.tenant_id
        and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
        and po.id = v_perfil_esperado;
      v_cfop_esperado := case when v_ambito = 'INTERNA' then v_perfil.cfop_interno else v_perfil.cfop_externo end;

      if nullif(regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g'), '') is distinct from v_cfop_esperado
         or nullif(btrim(v_item.cst_icms), '') is distinct from v_perfil.cst_icms
         or nullif(btrim(v_item.csosn), '') is distinct from v_perfil.csosn
         or (v_perfil.icms_modalidade_base_calculo is not null and nullif(btrim(v_item.icms_modalidade_base_calculo), '') is distinct from v_perfil.icms_modalidade_base_calculo)
         or (v_perfil.aliquota_icms is not null and v_item.aliquota_icms is distinct from v_perfil.aliquota_icms)
         or (v_perfil.reducao_base_icms_percentual is not null and v_item.reducao_base_icms_percentual is distinct from v_perfil.reducao_base_icms_percentual)
         or (v_perfil.cst_pis is not null and nullif(btrim(v_item.cst_pis), '') is distinct from v_perfil.cst_pis)
         or (v_perfil.cst_cofins is not null and nullif(btrim(v_item.cst_cofins), '') is distinct from v_perfil.cst_cofins)
         or (v_perfil.aliquota_pis is not null and v_item.aliquota_pis is distinct from v_perfil.aliquota_pis)
         or (v_perfil.aliquota_cofins is not null and v_item.aliquota_cofins is distinct from v_perfil.aliquota_cofins)
         or (v_perfil.cbenef_aplicacao = 'SEM_BENEFICIO' and nullif(btrim(v_item.cbenef), '') is not null)
         or (v_perfil.cbenef_aplicacao = 'COM_BENEFICIO' and nullif(btrim(v_item.cbenef), '') is distinct from v_perfil.cbenef)
         or (v_perfil.cst_ibs_cbs is not null and nullif(regexp_replace(coalesce(v_item.cst_ibs_cbs, ''), '[^0-9]', '', 'g'), '') is distinct from v_perfil.cst_ibs_cbs)
         or (v_perfil.cclass_trib is not null and nullif(regexp_replace(coalesce(v_item.cclass_trib, ''), '[^0-9]', '', 'g'), '') is distinct from v_perfil.cclass_trib)
         or (v_perfil.cclass_trib_versao is not null and nullif(btrim(v_item.cclass_trib_versao), '') is distinct from v_perfil.cclass_trib_versao)
         or (v_perfil.ibs_cbs_json ? 'ibs_uf_aliquota' and (v_item.ibs_cbs_json->>'ibs_uf_aliquota')::numeric is distinct from (v_perfil.ibs_cbs_json->>'ibs_uf_aliquota')::numeric)
         or (v_perfil.ibs_cbs_json ? 'ibs_mun_aliquota' and (v_item.ibs_cbs_json->>'ibs_mun_aliquota')::numeric is distinct from (v_perfil.ibs_cbs_json->>'ibs_mun_aliquota')::numeric)
         or (v_perfil.ibs_cbs_json ? 'cbs_aliquota' and (v_item.ibs_cbs_json->>'cbs_aliquota')::numeric is distinct from (v_perfil.ibs_cbs_json->>'cbs_aliquota')::numeric) then
        raise exception using errcode = '22023', message = format('Um campo bloqueado do perfil %s foi alterado no item %s.', v_perfil.codigo, v_item.id);
      end if;
      if v_perfil.finalidade_emissao is not null
         and (p_operacao->>'finalidade_emissao')::smallint is distinct from v_perfil.finalidade_emissao then
        raise exception using errcode = '22023', message = format('A finalidade deve permanecer igual ao perfil %s.', v_perfil.codigo);
      end if;
      if v_perfil.consumidor_final is not null
         and (p_operacao->>'consumidor_final')::smallint is distinct from v_perfil.consumidor_final then
        raise exception using errcode = '22023', message = format('O consumidor final deve permanecer igual ao perfil %s.', v_perfil.codigo);
      end if;
    end if;

    if v_item.reducao_base_icms_percentual is null then
      raise exception using errcode = '22023', message = 'A reducao da base de ICMS deve ser confirmada em cada item; informe zero quando nao houver reducao.';
    end if;
    if v_item.reducao_base_icms_percentual not between 0 and 100 then
      raise exception using errcode = '22023', message = 'Reducao da base de ICMS deve estar entre 0 e 100.';
    end if;
    if nullif(btrim(v_item.cst_ibs_cbs), '') is null
       or nullif(btrim(v_item.cclass_trib), '') is null
       or nullif(btrim(v_item.cclass_trib_versao), '') is null
       or jsonb_typeof(v_item.ibs_cbs_json) is distinct from 'object'
       or v_item.ibs_cbs_json->>'ibs_uf_aliquota' is null
       or v_item.ibs_cbs_json->>'ibs_mun_aliquota' is null
       or v_item.ibs_cbs_json->>'cbs_aliquota' is null then
      raise exception using errcode = '22023', message = 'CST, cClassTrib, versao e aliquotas de IBS/CBS sao obrigatorios em cada item.';
    end if;

    update f.solicitacao_item si
    set perfil_operacao_id = v_perfil_esperado,
        perfil_aplicado_em = now(),
        perfil_aplicado_por = v_usuario_id,
        ncm = nullif(regexp_replace(coalesce(v_fiscal_item.ncm, ''), '[^0-9]', '', 'g'), ''),
        cest = nullif(regexp_replace(coalesce(v_fiscal_item.cest, ''), '[^0-9]', '', 'g'), ''),
        origem_mercadoria = v_fiscal_item.origem,
        unidade_tributavel = nullif(btrim(v_fiscal_item.unidade_tributavel), ''),
        cfop = nullif(regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g'), ''),
        cst_icms = nullif(btrim(v_item.cst_icms), ''),
        csosn = nullif(btrim(v_item.csosn), ''),
        cst_ipi = nullif(btrim(v_fiscal_item.cst_ipi), ''),
        ipi_codigo_enquadramento_legal = nullif(regexp_replace(coalesce(v_fiscal_item.ipi_codigo_enquadramento_legal, ''), '[^0-9]', '', 'g'), ''),
        cst_pis = nullif(btrim(v_item.cst_pis), ''),
        cst_cofins = nullif(btrim(v_item.cst_cofins), ''),
        cbenef = nullif(btrim(v_item.cbenef), ''),
        reducao_base_icms_percentual = v_item.reducao_base_icms_percentual,
        icms_modalidade_base_calculo = nullif(btrim(v_item.icms_modalidade_base_calculo), ''),
        aliquota_icms = v_item.aliquota_icms,
        aliquota_ipi = v_fiscal_item.aliq_ipi,
        aliquota_pis = v_item.aliquota_pis,
        aliquota_cofins = v_item.aliquota_cofins,
        numero_fci = nullif(btrim(v_fiscal_item.numero_fci), ''),
        cst_ibs_cbs = nullif(regexp_replace(coalesce(v_item.cst_ibs_cbs, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib = nullif(regexp_replace(coalesce(v_item.cclass_trib, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib_versao = nullif(btrim(v_item.cclass_trib_versao), ''),
        ibs_cbs_json = v_item.ibs_cbs_json
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item.id;
  end loop;

  select count(distinct si.perfil_operacao_id),
         (array_agg(distinct si.perfil_operacao_id) filter (where si.perfil_operacao_id is not null))[1]
    into v_perfis_distintos, v_perfil_unico
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  update f.solicitacao_faturamento sf
  set perfil_operacao_id = case
        when v_perfis_distintos = 1
         and not exists (
           select 1 from f.solicitacao_item x
           where x.tenant_id = sf.tenant_id
             and x.empresa_id = sf.empresa_id
             and x.solicitacao_id = sf.id
             and x.perfil_operacao_id is null
         ) then v_perfil_unico
        else null
      end
  where sf.tenant_id = v_sf.tenant_id
    and sf.empresa_id = v_sf.empresa_id
    and sf.id = v_sf.id;

  if v_emissao.documento_fiscal_id is not null then
    update f.documento_fiscal_emissao
    set status = 'RASCUNHO', codigo_status = null, mensagem = null, updated_at = now()
    where tenant_id = v_sf.tenant_id
      and empresa_id = v_sf.empresa_id
      and documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'solicitacao_id', v_sf.id, 'itens', v_total_itens,
    'destino_uf_confirmada', v_destino_uf,
    'perfil_operacao_id', case when v_perfis_distintos = 1 then v_perfil_unico else null end
  );
end;
$function$;

comment on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) is
  'Confirma destino, salva valores explicitos e impede alteracao de campos fornecidos pelo perfil fiscal resolvido no servidor.';
revoke all on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) from public, anon;
grant execute on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function f.fn_nfe_producao_pronta(p_solicitacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
stable
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_certificado_validade date;
  v_invalidos integer;
  v_revisao integer;
  v_perfis jsonb;
begin
  select * into v_sf from f.solicitacao_faturamento sf where sf.id = p_solicitacao_id;
  if not found then return jsonb_build_object('pronta', false, 'motivo', 'Solicitacao nao encontrada.'); end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;

  select ef.certificado_validade_em into v_certificado_validade
  from c.empresa_fiscal ef
  where ef.empresa_id = v_sf.empresa_id and ef.deleted_at is null;
  if not found or v_certificado_validade is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.');
  end if;
  if v_certificado_validade < current_date then
    return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.');
  end if;
  if v_sf.destino_uf_confirmada is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A UF de destino ainda nao foi confirmada.');
  end if;

  select count(*) filter (
           where si.perfil_operacao_id is null
              or po.id is null
              or not po.habilitado_producao
              or po.faixa_automacao = 'BLOQUEADO'
         ),
         count(*) filter (where po.faixa_automacao = 'REVISAO'),
         coalesce(jsonb_agg(distinct po.id) filter (where po.id is not null), '[]'::jsonb)
    into v_invalidos, v_revisao, v_perfis
  from f.solicitacao_item si
  left join f.perfil_operacao po
    on po.tenant_id = si.tenant_id
   and (po.empresa_id = si.empresa_id or po.empresa_id is null)
   and po.id = si.perfil_operacao_id
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if v_invalidos > 0 then
    return jsonb_build_object('pronta', false, 'motivo', 'Todos os itens precisam de perfil fiscal vigente e explicitamente liberado para producao.');
  end if;
  if v_revisao > 0 and v_sf.revisao_fiscal_confirmada_em is null then
    return jsonb_build_object('pronta', false, 'motivo', 'A conferencia fiscal desta solicitacao ainda nao foi confirmada.');
  end if;
  if v_sf.snapshot_cadastro_em is null
     or jsonb_typeof(v_sf.emitente_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.destinatario_snapshot) is distinct from 'object'
     or jsonb_typeof(v_sf.operacao_snapshot) is distinct from 'object' then
    return jsonb_build_object('pronta', false, 'motivo', 'O cadastro fiscal ainda nao foi validado e congelado.');
  end if;
  return jsonb_build_object('pronta', true, 'perfil_operacao_ids', v_perfis);
end;
$function$;

revoke all on function f.fn_nfe_producao_pronta(uuid) from public, anon;
grant execute on function f.fn_nfe_producao_pronta(uuid) to authenticated, service_role;

create or replace function f.trg_bloquear_nfe_producao_sem_perfil_liberado()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_prontidao jsonb;
begin
  if new.ambiente <> 'PRODUCAO' then return new; end if;
  v_prontidao := f.fn_nfe_producao_pronta(new.solicitacao_id);
  if not coalesce((v_prontidao->>'pronta')::boolean, false) then
    raise exception 'Producao bloqueada: %', coalesce(v_prontidao->>'motivo', 'perfil fiscal nao liberado.');
  end if;
  return new;
end;
$function$;

revoke all on function f.trg_bloquear_nfe_producao_sem_perfil_liberado() from public, anon, authenticated, service_role;

commit;
