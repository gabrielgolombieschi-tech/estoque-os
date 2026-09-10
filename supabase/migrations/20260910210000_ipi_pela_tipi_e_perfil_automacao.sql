-- IPI da revenda passa a respeitar a TIPI, e nasce o perfil do beneficio de automacao.
--
-- Fecha a OV-SEG-00007-026 (Portobello, CHAVE SEG FD2083, item 20973, NCM 8536.50.90),
-- que ficou com o rascunho preso porque o perfil generico da revenda aplica 12% direto
-- sem cBenef e o builder recusa: para os NCM do Anexo 2, Art. 7o, VII, os 12% sao
-- beneficio, e a SEFAZ exige o codigo desde 03/02/2025.
--
-- Referencia: NF-e 3607 de 07/04/2026, da propria Segau, mesmo item FD2083 —
-- base 557,10 sobre 789,21 (reducao de 29,412%), ICMS 94,71 a 17% (carga efetiva
-- 12%) e IPI 76,95 a 9,75%.
--
-- Tres partes:
--
-- 1. TIPI dos NCM de automacao, lidos da planilha oficial da RFB
--    (tipi.xlsx, TIPI 2022 / Decreto 11.158/2022 atualizada pelo ADE RFB 1/2026).
--    Eles NAO tem a mesma aliquota, ao contrario do que a familia sugere:
--      8536.49.00 = 3,25%   8536.50.90 = 9,75%   8544.49.00 = 0%
--    O 9,75% do 8536.50.90 bate com o IPI destacado na NF-e 3607.
--
-- 2. O IPI da revenda deixa de sair sempre da fixture do CFOP. A hierarquia passa a
--    ser: perfil (quando traz CST e cEnq) > cadastro do produto, se a TIPI disser que
--    o NCM e tributado > fixture do CFOP. NCM sem registro na TIPI nao muda nada.
--    Isso e o que a fixture do 5102 ja avisava ser provisorio ("pergunta 4 ao
--    contador"): ela zerava o IPI de todo item revendido, inclusive os tributados.
--
-- 3. O perfil operacional do beneficio de automacao, que ate agora so existia como
--    linha de catalogo (CSV63-001, sem natureza/ambito/UF/destinacao, e por isso
--    inelegivel). Nasce com a lista de NCM da 20260910190000, em REVISAO e sem
--    producao: homologacao primeiro, e a liberacao para producao continua sendo um
--    clique na tela de perfis.

insert into f.tipi_ncm (ncm, aliquota, descricao, fonte) values
  ('85364900', 3.2500, 'Outros aparelhos para interrupcao/protecao de circuitos, ate 1.000 V', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB'),
  ('85365090', 9.7500, 'Outros interruptores, seccionadores e comutadores - outros', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB; confere com o IPI de 9,75% da NF-e 3607 de 07/04/2026'),
  ('85444900', 0.0000, 'Outros condutores eletricos, ate 1.000 V, sem pecas de conexao', 'TIPI Decreto 11.158/2022 (ADE RFB 1/2026), planilha oficial da RFB')
on conflict (ncm) do nothing;

-- O item 20973 ja tinha a aliquota de 9,75 no cadastro fiscal, mas sem CST: sem ele
-- o IPI nunca seria destacado, nem com a TIPI cadastrada.
-- So o CST: o cEnq e da operacao e o cadastro do item tem trigger que recusa.
update public.fiscal_itens fi
   set cst_ipi = '50',
       atualizado_em = now()
  from public.itens i
 where i.id = fi.item_id
   and i.codigo_interno = '20973'
   and coalesce(nullif(btrim(fi.cst_ipi), ''), '') = ''
   and fi.aliq_ipi = 9.7500;

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
           fi.cest as cest_produto,
           -- IPI do cadastro do produto: entra quando a TIPI diz que o NCM e
           -- tributado (mais abaixo). O IPI e do produto, o ICMS e da operacao.
           -- O cEnq nao vem daqui de proposito: ele e da operacao, e o cadastro do
           -- item tem trigger que recusa grava-lo.
           nullif(btrim(coalesce(fi.cst_ipi, '')), '') as cst_ipi_produto,
           fi.aliq_ipi as aliquota_ipi_produto
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
             when tp.aliquota > 0 and c.cst_ipi_produto is not null
               then c.cst_ipi_produto
             else fx.cst_ipi
           end as cst_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then px.perfil->>'ipi_codigo_enquadramento_legal'
             when tp.aliquota > 0 and c.cst_ipi_produto is not null
               then coalesce(fx.c_enq, '999')
             else fx.c_enq
           end as cenq_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then nullif(px.perfil->>'aliquota_ipi', '')::numeric
             when tp.aliquota > 0 and c.cst_ipi_produto is not null
               then coalesce(c.aliquota_ipi_produto, tp.aliquota)
             else fx.aliquota_ipi
           end as aliquota_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then 'PERFIL_OPERACAO'
             when tp.aliquota > 0 and c.cst_ipi_produto is not null then 'PRODUTO_TIPI'
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
        -- Perfil por NCM. Um perfil com lista so vale para os NCM dela; um perfil
        -- sem lista e o generico e so entra quando nenhum perfil com lista casa
        -- com o NCM da linha. Sem isso, liberar o perfil do beneficio de automacao
        -- (CSV63-001, CST 20 com base reduzida e cBenef SC820006) deixava DOIS
        -- perfis validos para toda revenda origem 2 em SC e a conferencia parava
        -- em AMBIGUO — e sem liberar, o NCM 8536.50.90 nao tinha como sair com o
        -- cBenef que o builder (e a SEFAZ, desde 03/02/2025) exige.
        and (
          case
            when po.ncms_elegiveis is not null then c.ncm = any(po.ncms_elegiveis)
            else not exists (
              select 1
              from f.perfil_operacao esp
              where esp.tenant_id = po.tenant_id
                and (esp.empresa_id = po.empresa_id or (esp.empresa_id is null and po.empresa_id is null))
                and esp.modelo = po.modelo
                and esp.natureza_operacao = po.natureza_operacao
                and esp.ambito_destino = po.ambito_destino
                and coalesce(esp.origem_mercadoria, -1) = coalesce(po.origem_mercadoria, -1)
                and esp.ncms_elegiveis is not null
                and c.ncm = any(esp.ncms_elegiveis)
                and esp.faixa_automacao <> 'BLOQUEADO'
                and esp.vigencia_inicio <= current_date
                and (esp.vigencia_fim is null or esp.vigencia_fim >= current_date)
                and (esp.destinacoes_mercadoria is null or v_destinacao = any(esp.destinacoes_mercadoria))
            )
          end
        )
    ) px on true
    left join lateral (
      -- TIPI por NCM: e ela que diz se o produto e tributado. Sem registro, nada
      -- muda e a fixture do CFOP segue mandando, como antes.
      select t.aliquota
      from f.tipi_ncm t
      where t.ncm = c.ncm
        and t.vigencia_inicio <= current_date
        and (t.vigencia_fim is null or t.vigencia_fim >= current_date)
      order by t.vigencia_inicio desc
      limit 1
    ) tp on true
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

-- Perfil do beneficio de automacao. Numeros identicos aos da NF-e 3607 e aos da
-- linha de catalogo CSV63-001, so que agora como perfil que o resolvedor alcanca.
-- Sem cst_ipi no perfil de proposito: o IPI vem do produto pela TIPI, porque os
-- tres NCM desta lista tem aliquotas diferentes (3,25 / 9,75 / 0).
insert into f.perfil_operacao (
  tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_interno, ambito_destino, ufs_destino, indicador_ie_destinatario, destinacoes_mercadoria,
  origem_mercadoria, cst_icms, aliquota_icms, reducao_base_icms_percentual, cbenef,
  beneficio_texto_legal, percentual_base_calculo,
  icms_modalidade_base_calculo, cst_pis, aliquota_pis, cst_cofins, aliquota_cofins,
  ncms_elegiveis, faixa_automacao, habilitado_producao, vigencia_inicio, justificativa_faixa
)
select po.tenant_id, po.empresa_id,
       'SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO',
       'SEG - venda de mercadoria de terceiros em SC - CFOP 5102 - origem 2 - CST 20 - base reduzida do Anexo 2, Art. 7o, VII',
       po.modelo, po.natureza_operacao, po.natureza_texto, po.crt,
       po.cfop_interno, po.ambito_destino, po.ufs_destino, po.indicador_ie_destinatario,
       po.destinacoes_mercadoria, po.origem_mercadoria,
       '20', 17.0000, 29.4120, 'SC820006',
       -- Texto legal e percentual da base vem da propria linha de catalogo, que a
       -- contabilidade ja revisou; a constraint perfil_operacao_beneficio_completo_ck
       -- exige os tres juntos com a reducao.
       matriz.beneficio_texto_legal, matriz.percentual_base_calculo, '3',
       po.cst_pis, po.aliquota_pis, po.cst_cofins, po.aliquota_cofins,
       array['85364900', '85365090', '85444900'],
       'REVISAO', false, current_date,
       'Criado em 10/09/2026 sobre a NF-e 3607 de 07/04/2026 (mesmo item FD2083, NCM 8536.50.90): CST 20, 17% com base reduzida em 29,412% (carga efetiva 12%) e cBenef SC820006. Vale so para os tres NCM do Anexo 2, Art. 7o, VII. Producao ainda nao liberada.'
from f.perfil_operacao po
join f.perfil_operacao matriz
  on matriz.tenant_id = po.tenant_id
 and matriz.codigo = 'CSV63-001'
where po.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00'
on conflict do nothing;

do $conferir$
declare
  v record;
begin
  select cst_icms, aliquota_icms, reducao_base_icms_percentual, cbenef, ncms_elegiveis, faixa_automacao
    into v
  from f.perfil_operacao
  where codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO';

  if not found then
    raise notice 'Perfil de automacao nao foi criado (o generico de origem 2 nao existe neste banco).';
    return;
  end if;
  if v.cst_icms <> '20' or v.aliquota_icms <> 17 or v.reducao_base_icms_percentual <> 29.4120
     or v.cbenef <> 'SC820006' or not ('85365090' = any(v.ncms_elegiveis)) then
    raise exception 'Perfil de automacao saiu com CST=%, aliquota=%, reducao=%, cBenef=%, NCM=%.',
      v.cst_icms, v.aliquota_icms, v.reducao_base_icms_percentual, v.cbenef, v.ncms_elegiveis;
  end if;
  raise notice 'Perfil de automacao criado em % para % NCM; IPI vem do produto pela TIPI.',
    v.faixa_automacao, array_length(v.ncms_elegiveis, 1);
end
$conferir$;
