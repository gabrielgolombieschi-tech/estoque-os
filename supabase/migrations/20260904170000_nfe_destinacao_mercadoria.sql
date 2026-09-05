-- Destinacao da mercadoria: o campo que decide 12% ou 17% de ICMS interno.
--
-- Em SC a aliquota interna nao e caracteristica do produto, e da destinacao que
-- o adquirente da a mercadoria:
--
--   12%  contribuinte que revende, industrializa, usa como insumo, manutencao
--        ou consignado -- Lei 10.297/96, art. 19, III, "n" e Lei 17.878/2019
--   17%  uso e consumo, ativo imobilizado ou nao contribuinte -- RICMS/SC,
--        art. 26, I
--
-- A PORTOBELLO exige a aliquota certa por escrito ("aliquotas destacadas
-- divergentes das mesmas, iremos recusar a NF ate a correcao da mesma") e lista
-- as utilizacoes das OCs dela: consignado, manutencao, insumos e revenda.
--
-- Antes desta migration o sistema tinha um unico perfil interno, fixo em 12%:
-- vender para uso e consumo sairia com aliquota errada, sem ninguem perceber.
--
-- Fonte das regras: docs/faturamento/regras-icms-sc-contabilidade.md

alter table f.solicitacao_faturamento
  add column if not exists destinacao_mercadoria text;

comment on column f.solicitacao_faturamento.destinacao_mercadoria is
  'Destinacao declarada pelo destinatario (OC do cliente). Decide a aliquota interna de ICMS e vai para as informacoes complementares da NF-e.';

alter table f.perfil_operacao
  add column if not exists destinacoes_mercadoria text[];

comment on column f.perfil_operacao.destinacoes_mercadoria is
  'Destinacoes que este perfil atende. Nulo = qualquer destinacao.';

do $do$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'solicitacao_faturamento_destinacao_mercadoria_check'
  ) then
    alter table f.solicitacao_faturamento
      add constraint solicitacao_faturamento_destinacao_mercadoria_check
      check (destinacao_mercadoria is null or destinacao_mercadoria in (
        'REVENDA', 'INDUSTRIALIZACAO', 'INSUMO', 'MANUTENCAO',
        'CONSIGNADO', 'USO_CONSUMO', 'ATIVO_IMOBILIZADO'
      ));
  end if;
end
$do$;

-- Os perfis internos que ja existiam sao de 12%: valem para quem revende,
-- industrializa, consome como insumo, faz manutencao ou recebe em consignacao.
update f.perfil_operacao
set destinacoes_mercadoria = array[
      'REVENDA', 'INDUSTRIALIZACAO', 'INSUMO', 'MANUTENCAO', 'CONSIGNADO'
    ]::text[]
where codigo in (
  'SEG-VENDA-TERCEIROS-SC-5102-O0-CST00',
  'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00'
);

-- E os irmaos de 17%, para destinatario final. Sem eles, vender para uso e
-- consumo simplesmente nao acha perfil -- que e melhor que sair com 12% errado,
-- mas pior que funcionar.
insert into f.perfil_operacao (
  tenant_id, empresa_id, codigo, nome, modelo,
  natureza_operacao, natureza_texto, crt,
  cfop_interno, ambito_destino, ufs_destino, indicador_ie_destinatario,
  origem_mercadoria, destinacoes_mercadoria,
  cst_icms, aliquota_icms, icms_modalidade_base_calculo,
  reducao_base_icms_percentual, cbenef, cbenef_aplicacao,
  cst_pis, aliquota_pis, cst_cofins, aliquota_cofins,
  finalidade_emissao, consumidor_final,
  exige_referencia, exige_motivo,
  faixa_automacao, justificativa_faixa, habilitado_producao,
  vigencia_inicio, observacao
)
select
  base.tenant_id, base.empresa_id,
  'SEG-VENDA-TERCEIROS-SC-5102-O' || base.origem_mercadoria::text || '-CST00-17',
  'SEG - venda de mercadoria de terceiros em SC - CFOP 5102 - origem '
    || base.origem_mercadoria::text || ' - CST 00 - 17% destinatario final',
  'NFE',
  base.natureza_operacao, base.natureza_texto, base.crt,
  '5102', 'INTERNA', array['SC']::text[], '1',
  base.origem_mercadoria,
  array['USO_CONSUMO', 'ATIVO_IMOBILIZADO']::text[],
  '00', 17.0000, '3',
  0.0000, null, 'SEM_BENEFICIO',
  '01', 1.6500, '01', 7.6000,
  1, 1,
  false, false,
  'REVISAO',
  'Aliquota cheia de SC para destinatario final. Nunca foi exercitada em '
    || 'homologacao; exige confirmacao humana na primeira nota.',
  false,
  current_date,
  'Aliquota interna de 17% do RICMS/SC, art. 26, I, para operacao destinada a '
    || 'uso e consumo ou ativo imobilizado do adquirente. Espelha o perfil de '
    || '12% da mesma origem, trocando so a aliquota e o consumidor final.'
from f.perfil_operacao base
where base.codigo in (
    'SEG-VENDA-TERCEIROS-SC-5102-O0-CST00',
    'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00'
  )
  and not exists (
    select 1 from f.perfil_operacao existente
    where existente.tenant_id = base.tenant_id
      and existente.codigo =
        'SEG-VENDA-TERCEIROS-SC-5102-O' || base.origem_mercadoria::text || '-CST00-17'
  );

-- O resolvedor ganha a destinacao como terceiro parametro. Preciso derrubar a
-- versao de 2 argumentos: mantendo as duas, uma chamada com 2 argumentos ficaria
-- ambigua. Os chamadores antigos passam a cair no DEFAULT NULL e caem na coluna.
drop function if exists f.fn_solicitacao_nfe_resolver_perfis(uuid, text);


CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_resolver_perfis(p_solicitacao_id uuid, p_destino_uf text, p_destinacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_cliente public.clientes%rowtype;
  v_uf_emitente text;
  v_uf_destino text := upper(btrim(coalesce(p_destino_uf, '')));
  v_crt text;
  v_ambito text;
  v_destinacao text;
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

  -- Destinacao que o adquirente da a mercadoria. Em SC ela decide a aliquota
  -- interna: 12% para contribuinte que revende, industrializa, usa como insumo,
  -- manutencao ou consignado (Lei 10.297/96, art. 19, III, "n"; Lei 17.878/2019)
  -- e 17% para uso e consumo, ativo imobilizado ou nao contribuinte (RICMS/SC,
  -- art. 26, I). Ver docs/faturamento/regras-icms-sc-contabilidade.md.
  -- O parametro vence a coluna, para a tela resolver antes de gravar.
  v_destinacao := nullif(btrim(coalesce(p_destinacao, v_sf.destinacao_mercadoria, '')), '');
  if v_destinacao is null then
    return jsonb_build_object(
      'ok', false,
      'bloqueio', 'Informe a destinacao da mercadoria: ela decide a aliquota interna de ICMS.',
      'campo', 'destinacao_mercadoria'
    );
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
           px.perfil,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then px.perfil->>'cst_ipi'
             else fx.cst_ipi
           end as cst_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then px.perfil->>'ipi_codigo_enquadramento_legal'
             else fx.c_enq
           end as cenq_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then nullif(px.perfil->>'aliquota_ipi', '')::numeric
             else fx.aliquota_ipi
           end as aliquota_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then 'PERFIL_OPERACAO'
             when fx.cfop is not null then 'FIXTURE_HOMOLOGACAO'
             else null
           end as ipi_fonte
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
        and (po.destinacoes_mercadoria is null or v_destinacao = any(po.destinacoes_mercadoria))
        and (
          (v_ambito = 'INTERNA' and po.cfop_interno is not null)
          or (po.cfop_externo is not null and po.aliquota_icms = c.aliquota_referencia)
        )
        and po.faixa_automacao <> 'BLOQUEADO'
        and po.vigencia_inicio <= current_date
        and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
    ) px on true
    left join lateral (
      select fxt.cfop, fxt.cst_ipi, fxt.c_enq, fxt.aliquota_ipi
      from f.tributacao_provisoria_homologacao fxt
      where fxt.tenant_id = v_sf.tenant_id
        and fxt.empresa_id = v_sf.empresa_id
        and fxt.cfop = case
          when v_ambito = 'INTERNA' then px.perfil->>'cfop_interno'
          else px.perfil->>'cfop_externo'
        end
        and fxt.ativo is true
      limit 1
    ) fx on true
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
      'numero_fci', r.numero_fci_produto
    ),
    'ipi_operacao', jsonb_build_object(
      'cst', r.cst_ipi_operacao,
      'c_enq', r.cenq_ipi_operacao,
      'aliquota', r.aliquota_ipi_operacao,
      'fonte', r.ipi_fonte
    ),
    'aliquota_referencia_busca', r.aliquota_referencia,
    'perfis_encontrados', r.perfis_encontrados,
    'status', case
      when not r.cadastro_fiscal_existe
        or r.origem_mercadoria is null then 'PRODUTO_INCOMPLETO'
      when r.perfis_encontrados = 0 then 'SEM_PERFIL'
      when r.perfis_encontrados > 1 then 'AMBIGUO'
      when nullif(btrim(r.cst_ipi_operacao), '') is null
        or nullif(btrim(r.cenq_ipi_operacao), '') is null then 'PERFIL_INCOMPLETO'
      else 'RESOLVIDO'
    end,
    'motivo', case
      when not r.cadastro_fiscal_existe then 'O item nao possui cadastro fiscal do produto.'
      when r.origem_mercadoria is null then 'Origem da mercadoria nao informada no produto.'
      when r.perfis_encontrados = 0 then format(
        'Nenhum perfil fiscal para %s, UF %s, indicador IE %s, origem %s, destinacao %s%s.',
        v_ambito, v_uf_destino, coalesce(v_cliente.indicador_ie, '<vazio>'),
        r.origem_mercadoria, v_destinacao,
        case when r.aliquota_referencia is null then '' else ', faixa interestadual ' || r.aliquota_referencia::text || '%' end
      )
      when r.perfis_encontrados > 1 then 'Mais de um perfil fiscal se aplica a esta linha.'
      when nullif(btrim(r.cst_ipi_operacao), '') is null
        or nullif(btrim(r.cenq_ipi_operacao), '') is null
        then 'CST IPI e cEnq devem vir do perfil de operacao; a fixture provisoria cobre apenas a homologacao do CFOP 5102.'
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
    'destinacao', v_destinacao,
    'indicador_ie', v_cliente.indicador_ie,
    'cliente_id', v_cliente.id,
    'rota_cliente', '/clientes/cadastro-fiscal?cliente_id=' || v_cliente.id::text,
    'itens', v_itens
  );
end;
$function$;
CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_salvar_conferencia(p_solicitacao_id uuid, p_operacao jsonb, p_itens jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
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
  v_cst_ipi text;
  v_cenq_ipi text;
  v_aliquota_ipi numeric;
  v_ipi_fonte text;
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

  -- Forma de pagamento (grupo YA / detPag). Sem ela o provedor preenchia o
  -- default dele, e a nota saia declarando tPag 01 (dinheiro) para venda a
  -- prazo. Agora e confirmacao explicita, como frete e transportadora.
  -- Destinacao declarada pelo destinatario (vem da OC do cliente). Decide a
  -- aliquota interna e vai para as informacoes complementares da nota.
  if nullif(btrim(p_operacao->>'destinacao_mercadoria'), '') is null then
    raise exception using errcode = '22023', message = 'Informe a destinacao da mercadoria: ela decide a aliquota interna de ICMS.';
  end if;

  if nullif(btrim(p_operacao->>'pagamento_forma'), '') is null
     or nullif(btrim(p_operacao->>'pagamento_indicador'), '') is null then
    raise exception using errcode = '22023', message = 'A forma de pagamento e o indicador (a vista ou a prazo) devem ser confirmados em cada nota.';
  end if;
  if btrim(p_operacao->>'pagamento_forma') !~ '^(0[1-5]|1[0-9]|2[0-4]|9[019])$' then
    raise exception using errcode = '22023', message = 'Forma de pagamento fora da tabela da NF-e (tPag).';
  end if;
  if (p_operacao->>'pagamento_indicador')::smallint not in (0, 1) then
    raise exception using errcode = '22023', message = 'Indicador de pagamento deve ser 0 (a vista) ou 1 (a prazo).';
  end if;
  -- xPag e obrigatorio quando tPag = 99 (outros).
  if btrim(p_operacao->>'pagamento_forma') = '99'
     and nullif(btrim(p_operacao->>'pagamento_descricao'), '') is null then
    raise exception using errcode = '22023', message = 'Descreva a forma de pagamento quando escolher 99 (outros).';
  end if;

  v_resolucao := f.fn_solicitacao_nfe_resolver_perfis(
    v_sf.id, v_destino_uf, btrim(p_operacao->>'destinacao_mercadoria')
  );
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
      destinacao_mercadoria = btrim(p_operacao->>'destinacao_mercadoria'),
      pagamento_forma = btrim(p_operacao->>'pagamento_forma'),
      pagamento_indicador = (p_operacao->>'pagamento_indicador')::smallint,
      pagamento_descricao = nullif(btrim(p_operacao->>'pagamento_descricao'), ''),
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
    if nullif(btrim(v_item.numero_fci), '') is distinct from nullif(btrim(v_fiscal_item.numero_fci), '') then
      raise exception using errcode = '22023', message = format('O numero da FCI do item %s deve vir do cadastro fiscal do produto.', v_item.id);
    end if;

    v_cst_ipi := nullif(btrim(v_resolvido#>>'{ipi_operacao,cst}'), '');
    v_cenq_ipi := nullif(regexp_replace(coalesce(v_resolvido#>>'{ipi_operacao,c_enq}', ''), '[^0-9]', '', 'g'), '');
    v_aliquota_ipi := nullif(v_resolvido#>>'{ipi_operacao,aliquota}', '')::numeric;
    v_ipi_fonte := nullif(v_resolvido#>>'{ipi_operacao,fonte}', '');
    if not f.fn_nfe_cenq_compativel(v_cst_ipi, v_cenq_ipi) then
      raise exception using errcode = '22023', message = format(
        'Item %s: cEnq %s incompativel com CST IPI %s (rejeicao 388).',
        v_item.id, coalesce(v_cenq_ipi, '<vazio>'), coalesce(v_cst_ipi, '<vazio>')
      );
    end if;
    if nullif(btrim(v_item.cst_ipi), '') is distinct from v_cst_ipi
       or nullif(regexp_replace(coalesce(v_item.ipi_codigo_enquadramento_legal, ''), '[^0-9]', '', 'g'), '') is distinct from v_cenq_ipi
       or v_item.aliquota_ipi is distinct from v_aliquota_ipi then
      raise exception using errcode = '22023', message = format(
        'Item %s: CST IPI, cEnq e aliquota devem vir do perfil de operacao ou da fixture provisoria de homologacao.',
        v_item.id
      );
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
        cst_ipi = v_cst_ipi,
        ipi_codigo_enquadramento_legal = v_cenq_ipi,
        ipi_fonte = v_ipi_fonte,
        cst_pis = nullif(btrim(v_item.cst_pis), ''),
        cst_cofins = nullif(btrim(v_item.cst_cofins), ''),
        cbenef = nullif(btrim(v_item.cbenef), ''),
        reducao_base_icms_percentual = v_item.reducao_base_icms_percentual,
        icms_modalidade_base_calculo = nullif(btrim(v_item.icms_modalidade_base_calculo), ''),
        aliquota_icms = v_item.aliquota_icms,
        aliquota_ipi = v_aliquota_ipi,
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
CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_cliente public.clientes%rowtype;
  v_item record;
  v_documento text;
  v_pendencias jsonb := '[]'::jsonb;
  v_rota_cliente text;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para validar esta solicitacao.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Somente solicitacao ainda nao emitida pode congelar cadastro.';
  end if;

  select * into v_empresa
  from c.empresa e
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null
    and e.ativo;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object(
      'entidade', 'empresa', 'id', v_sf.empresa_id, 'campo', 'empresa',
      'mensagem', 'Empresa ativa nao encontrada no cadastro corporativo.', 'rota', '/configuracoes'
    ));
  else
    select * into v_fiscal
    from c.empresa_fiscal ef
    where ef.empresa_id = v_empresa.id and ef.deleted_at is null
    order by ef.updated_at desc
    limit 1;
    select * into v_endereco
    from c.empresa_endereco ee
    where ee.empresa_id = v_empresa.id and ee.deleted_at is null
    order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc
    limit 1;

    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14
       or not public.cnpj_valido(v_empresa.cnpj) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cnpj','mensagem','CNPJ do emitente e invalido.','rota','/configuracoes'));
    end if;
    if nullif(btrim(v_empresa.razao_social), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','razao_social','mensagem','Razao social do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or nullif(btrim(v_fiscal.inscricao_estadual), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','inscricao_estadual','mensagem','IE do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.crt is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','crt','mensagem','CRT do emitente nao informado.','rota','/configuracoes'));
    end if;
    if v_endereco.id is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','endereco_fiscal','mensagem','Endereco fiscal do emitente nao informado.','rota','/configuracoes'));
    else
      if nullif(btrim(v_endereco.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','logradouro','mensagem','Logradouro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.numero), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','numero','mensagem','Numero do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','bairro','mensagem','Bairro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cidade','mensagem','Municipio do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.uf::text), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','uf','mensagem','UF do emitente nao informada.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cep','mensagem','CEP do emitente deve ter 8 digitos.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','codigo_municipio_ibge','mensagem','Codigo IBGE do emitente deve ter 7 digitos.','rota','/configuracoes')); end if;
    end if;
  end if;

  v_rota_cliente := '/clientes/cadastro-fiscal?cliente_id=' || coalesce(v_sf.cliente_id::text, '');
  select * into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id
    and c.empresa_id = v_sf.empresa_id
    and c.id = v_sf.cliente_id
    and c.ativo is true;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_sf.cliente_id,'campo','cliente','mensagem','Destinatario ativo nao encontrado nesta empresa.','rota',v_rota_cliente));
  else
    v_documento := regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g');
    if not ((length(v_documento) = 14 and public.cnpj_valido(v_documento)) or (length(v_documento) = 11 and public.cpf_valido(v_documento))) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','CPF/CNPJ do destinatario e invalido.','rota',v_rota_cliente));
    end if;
    if nullif(btrim(v_cliente.razao_social), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','razao_social','mensagem','Razao social ou nome completo nao informado.','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie is null or v_cliente.indicador_ie not in ('1','2','9') then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','indicador_ie','mensagem','Confirme manualmente o indicador de IE (1, 2 ou 9).','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie = '1' and nullif(btrim(v_cliente.inscricao_estadual), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','inscricao_estadual','mensagem','Contribuinte do ICMS deve ter IE informada.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','logradouro','mensagem','Logradouro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.numero_endereco), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','numero_endereco','mensagem','Numero do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','bairro','mensagem','Bairro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cidade','mensagem','Municipio do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if coalesce(v_cliente.uf, '') !~ '^[A-Za-z]{2}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','uf','mensagem','UF do destinatario deve ter 2 letras.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cep','mensagem','CEP do destinatario deve ter 8 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','codigo_ibge_municipio','mensagem','Codigo IBGE do destinatario deve ter 7 digitos.','rota',v_rota_cliente)); end if;
  end if;

  -- Copia apenas atributos permanentes do produto. CFOP, CST/CSOSN e aliquotas
  -- continuam exclusivamente sob responsabilidade da solicitacao.
  update f.solicitacao_item si
  set codigo_produto = coalesce(si.codigo_produto, nullif(btrim(i.codigo_interno), '')),
      ncm = coalesce(si.ncm, nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '')),
      cest = coalesce(si.cest, nullif(regexp_replace(coalesce(fi.cest, ''), '[^0-9]', '', 'g'), '')),
      origem_mercadoria = coalesce(si.origem_mercadoria, fi.origem),
      unidade_tributavel = coalesce(si.unidade_tributavel, nullif(btrim(fi.unidade_tributavel), ''), nullif(btrim(si.unidade), '')),
      valor_desconto = coalesce(si.valor_desconto, 0)
  from public.itens i
  left join public.fiscal_itens fi
    on fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id and fi.item_id = i.id
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
    and i.tenant_id = si.tenant_id
    and i.empresa_id = si.empresa_id
    and i.id = si.item_id;

  if not exists (select 1 from f.solicitacao_item si where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id) then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','itens','mensagem','A solicitacao nao possui itens.','rota','/faturamento/solicitacoes/' || v_sf.id));
  end if;

  for v_item in
    select si.*
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
    order by si.ordem, si.id
  loop
    if nullif(btrim(v_item.codigo_produto), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','codigo_produto','mensagem',format('Linha %s: codigo do produto nao informado.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.descricao), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','descricao','mensagem',format('Linha %s: descricao nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.ncm, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','ncm','mensagem',format('Linha %s: NCM deve ter 8 digitos.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g') !~ '^[0-9]{4}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cfop','mensagem',format('Linha %s: CFOP nao confirmado na solicitacao.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.origem_mercadoria is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','origem_mercadoria','mensagem',format('Linha %s: origem da mercadoria nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.unidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','unidade','mensagem',format('Linha %s: unidade comercial nao informada.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.unidade_tributavel), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','unidade_tributavel','mensagem',format('Linha %s: unidade tributavel nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if v_item.quantidade <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','quantidade','mensagem',format('Linha %s: quantidade deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.valor_unitario <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_unitario','mensagem',format('Linha %s: valor unitario deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if (case when nullif(btrim(v_item.cst_icms), '') is null then 0 else 1 end + case when nullif(btrim(v_item.csosn), '') is null then 0 else 1 end) <> 1 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms_csosn','mensagem',format('Linha %s: informe CST de ICMS ou CSOSN, nunca ambos.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt = 1 and nullif(btrim(v_item.csosn), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','csosn','mensagem',format('Linha %s: emitente do Simples exige CSOSN.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt is not null and v_fiscal.crt <> 1 and nullif(btrim(v_item.cst_icms), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms','mensagem',format('Linha %s: regime normal exige CST de ICMS.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_ipi), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_ipi','mensagem',format('Linha %s: CST de IPI nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_pis), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_pis','mensagem',format('Linha %s: CST de PIS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_cofins), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_cofins','mensagem',format('Linha %s: CST de COFINS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  end loop;

  if v_sf.finalidade_emissao is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','finalidade_emissao','mensagem','Finalidade de emissao nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.consumidor_final is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','consumidor_final','mensagem','Indicador de consumidor final nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.presenca_comprador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','presenca_comprador','mensagem','Indicador de presenca do comprador nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.modalidade_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','modalidade_frete','mensagem','Modalidade do frete nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_frete','mensagem','Valor do frete nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_seguro is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_seguro','mensagem','Valor do seguro nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_outras_despesas is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_outras_despesas','mensagem','Outras despesas nao confirmadas; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if nullif(btrim(v_sf.destinacao_mercadoria), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','destinacao_mercadoria','mensagem','Destinacao da mercadoria nao confirmada; ela decide a aliquota interna de ICMS.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if nullif(btrim(v_sf.pagamento_forma), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_forma','mensagem','Forma de pagamento nao confirmada; sem ela o provedor assume dinheiro.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.pagamento_indicador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_indicador','mensagem','Indicador de pagamento (a vista ou a prazo) nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;

  if jsonb_array_length(v_pendencias) = 0 then
    update f.solicitacao_faturamento
    set emitente_snapshot = jsonb_build_object(
          'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
          'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
          'telefone', v_empresa.telefone, 'inscricao_estadual', v_fiscal.inscricao_estadual,
          'crt', v_fiscal.crt, 'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero,
          'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro,
          'cidade', v_endereco.cidade, 'uf', upper(v_endereco.uf::text),
          'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')
        ),
        destinatario_snapshot = jsonb_build_object(
          'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social,
          'inscricao_estadual', nullif(btrim(v_cliente.inscricao_estadual), ''),
          'indicador_ie', v_cliente.indicador_ie, 'email', v_cliente.email,
          'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro,
          'numero_endereco', v_cliente.numero_endereco, 'complemento', v_cliente.complemento,
          'bairro', v_cliente.bairro, 'cidade', v_cliente.cidade, 'uf', upper(v_cliente.uf),
          'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')
        ),
        operacao_snapshot = jsonb_build_object(
          'natureza_operacao', natureza_operacao, 'finalidade_emissao', finalidade_emissao,
          'consumidor_final', consumidor_final, 'presenca_comprador', presenca_comprador,
          'modalidade_frete', modalidade_frete, 'valor_frete', valor_frete,
          'valor_seguro', valor_seguro, 'valor_outras_despesas', valor_outras_despesas,
          'destinacao_mercadoria', destinacao_mercadoria,
          'pagamento', jsonb_build_object(
            'forma', pagamento_forma,
            'indicador', pagamento_indicador,
            'descricao', pagamento_descricao
          )
        ),
        snapshot_cadastro_em = now(), updated_at = now()
    where id = v_sf.id;
  else
    update f.solicitacao_faturamento
    set emitente_snapshot = null, destinatario_snapshot = null,
        operacao_snapshot = null, snapshot_cadastro_em = null, updated_at = now()
    where id = v_sf.id;
  end if;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_pendencias) = 0,
    'solicitacao_id', v_sf.id,
    'cliente_id', v_sf.cliente_id,
    'rota_cliente', v_rota_cliente,
    'pendencias', v_pendencias
  );
end;
$function$;