-- Perfis de venda de mercadoria de terceiros em SC para item de ORIGEM 1 (importado pela
-- propria empresa, equiparada a industrial): o IPI da TIPI sai destacado na revenda.
--
-- Pedido do Gabriel em 18/09/2026 (OV-SEG-00004-026, CPU de CLP OMRON CQM1H-CPU61, DIR
-- 260191366846, NF-e de entrada 2/24): nao existia perfil 5102 com origem 1 — os quatro
-- SEG-VENDA-TERCEIROS-SC-5102-* sao origem 0 ou 2, todos com IPI 53 (revenda nao destaca).
-- Quem importa direto e equiparado a industrial (RIPI, Decreto 7.212/2010, art. 9o, I) e
-- destaca o IPI ao revender, sem mudar o CFOP (continua 5102). Dois perfis novos, espelho dos
-- -O2-, em REVISAO e sem producao:
--
--   SEG-VENDA-TERCEIROS-SC-5102-O1-CST00     12%, indFinal 0: REVENDA, INSUMO, CONSIGNADO
--   SEG-VENDA-TERCEIROS-SC-5102-O1-CST00-17  17%, indFinal 1: MANUTENCAO, USO_CONSUMO, ATIVO
--
-- IPI no perfil: CST 50, cEnq 999, ALIQUOTA EM BRANCO — ela e do NCM (f.tipi_ncm / cadastro do
-- item), nao da operacao. Ate aqui o resolvedor (f.fn_solicitacao_nfe_resolver_perfis) so
-- aceitava a aliquota do proprio perfil quando o perfil trazia CST e cEnq; com a aliquota em
-- branco a linha sairia "CST 50 sem aliquota" e a emissao pararia. A funcao passa a completar
-- a aliquota com a do cadastro do produto e, na falta, com a da TIPI, so para CST 50 e 99.
-- Fora isso a funcao e a mesma de 20260911120000 (gerada de pg_get_functiondef).
--
-- Evidencia fiscal: copia da evidencia dos -O2-, com a fonte apontando a DIR e a NF-e 2/24.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Perfis + evidencias -----------------------------------------------------------------------
do $perfis$
declare
  v_modelo record;
  v_evidencia record;
  v_novo f.perfil_operacao%rowtype;
  v_codigo_origem text;
  v_codigo_novo text;
  v_id_novo uuid;
  v_evidencia_id uuid;
  v_sufixo text;
begin
  foreach v_sufixo in array array['', '-17'] loop
    v_codigo_origem := 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00' || v_sufixo;
    v_codigo_novo := 'SEG-VENDA-TERCEIROS-SC-5102-O1-CST00' || v_sufixo;
    v_id_novo := case when v_sufixo = '' then 'a6e1c3d2-5102-4c01-9a2b-000000000012' else 'a6e1c3d2-5102-4c01-9a2b-000000000017' end;
    v_evidencia_id := case when v_sufixo = '' then '4c0a5e1e-9f0b-4c7a-9b2e-5102a1000012' else '4c0a5e1e-9f0b-4c7a-9b2e-5102a1000017' end;

    select p.* into v_modelo from f.perfil_operacao p
    where p.codigo = v_codigo_origem and p.vigencia_fim is null
    order by p.vigencia_inicio desc limit 1;
    if v_modelo.id is null then
      raise notice 'perfil % nao existe neste banco: % nao criado.', v_codigo_origem, v_codigo_novo;
      continue;
    end if;
    if exists (select 1 from f.perfil_operacao where tenant_id = v_modelo.tenant_id and empresa_id = v_modelo.empresa_id and codigo = v_codigo_novo) then
      raise notice 'perfil % ja existe.', v_codigo_novo;
      continue;
    end if;

    -- Evidencia propria (o vinculo perfil <-> evidencia e um-para-um).
    select e.* into v_evidencia from f.perfil_operacao_evidencia e where e.id = v_modelo.evidencia_id;
    if v_evidencia.id is not null then
      insert into f.perfil_operacao_evidencia (
        id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
        aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada, itens_observados, notas_observadas,
        ncms, notas_exemplo, leitura_operacional, faixa, justificativa_faixa,
        divergencia_ipi, divergencia_fabricado_revenda, divergencia_cabo_beneficio
      ) values (
        v_evidencia_id, v_evidencia.tenant_id, v_evidencia.empresa_id,
        'DIR 260191366846 / NF-e de entrada 2/24 (importacao direta pela Segau, 17/09/2026) + ' || v_evidencia.fonte, 1,
        v_evidencia.natureza_texto, '5102', 1, '100', '00',
        v_evidencia.aliquota_icms_observada, 9.75, false, 1, 1,
        array['85371020'], array[24],
        'Revenda em SC de item importado pela propria Segau (DIR 260191366846, NF-e 2/24, CPU de CLP OMRON, NCM 8537.10.20): origem 1 e equiparacao a industrial (RIPI art. 9o, I), IPI CST 50 com a aliquota da TIPI (9,75%) destacado no CFOP 5102. ICMS como no perfil de origem 2 ('
          || v_codigo_origem || '): ' || v_evidencia.leitura_operacional,
        'REVISAO', 'Perfil novo de 18/09/2026; primeira nota assistida (OV-SEG-00004-026).',
        false, false, false
      );
    else
      v_evidencia_id := null;
    end if;

    v_novo := v_modelo;
    v_novo.id := v_id_novo;
    v_novo.codigo := v_codigo_novo;
    v_novo.nome := replace(v_modelo.nome, 'origem 2', 'origem 1');
    v_novo.origem_mercadoria := 1;
    v_novo.cst_ipi := '50';
    v_novo.ipi_codigo_enquadramento_legal := '999';
    v_novo.aliquota_ipi := null;
    v_novo.evidencia_id := v_evidencia_id;
    v_novo.vigencia_inicio := current_date;
    v_novo.vigencia_fim := null;
    v_novo.created_at := now();
    v_novo.habilitado_producao := false;
    v_novo.faixa_automacao := 'REVISAO';
    v_novo.justificativa_faixa := 'Perfil novo de 18/09/2026 para item importado pela propria empresa (equiparado a industrial); primeira nota assistida.';
    v_novo.revisao_fiscal_em := null;
    v_novo.revisao_fiscal_por := null;
    v_novo.revisao_fiscal_justificativa := null;
    v_novo.producao_decidida_em := null;
    v_novo.producao_decidida_por := null;
    v_novo.producao_decisao_justificativa := null;
    v_novo.producao_homologacao_solicitacao_id := null;
    v_novo.producao_homologacao_documento_id := null;
    v_novo.observacao := coalesce(v_modelo.observacao, '') || ' Origem 1: item importado diretamente pela Segau (DIR/DI no CNPJ dela), equiparada a industrial pelo RIPI art. 9o, I. O IPI da TIPI sai destacado (CST 50, cEnq 999) na revenda, sem mudar o CFOP; a aliquota vem do NCM (f.tipi_ncm / cadastro do item), nao do perfil. Marcacao do item pela tela fiscal ("Importado por nos", 20260918210000).';
    v_novo.rotulo_usuario := coalesce(v_modelo.rotulo_usuario, null);
    v_novo.legenda_usuario := coalesce(v_modelo.legenda_usuario, null);

    insert into f.perfil_operacao select v_novo.*;

    if v_evidencia_id is not null then
      update f.perfil_operacao_evidencia set perfil_operacao_id = v_id_novo where id = v_evidencia_id;
    end if;
  end loop;
end;
$perfis$;

-- 2. Resolvedor: aliquota do IPI vem do produto/TIPI quando o perfil so diz CST e cEnq --------------
-- (definicao de 20260911120000 com a unica troca no case de aliquota_ipi_operacao)
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
           fi.aliq_ipi as aliquota_ipi_produto,
           -- Equiparacao a industrial (RIPI art. 9o, I e IX). Declarada item a item;
           -- sem ela, revenda nao destaca IPI.
           coalesce(fi.equiparado_industrial, false) as equiparado_industrial
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
               and (
                 c.equiparado_industrial
                 or coalesce(
                      case when v_ambito = 'INTERNA' then px.perfil->>'cfop_interno'
                           else px.perfil->>'cfop_externo' end,
                      ''
                    ) not in ('5102', '6102')
               )
               then c.cst_ipi_produto
             else fx.cst_ipi
           end as cst_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then px.perfil->>'ipi_codigo_enquadramento_legal'
             when tp.aliquota > 0 and c.cst_ipi_produto is not null
               and (
                 c.equiparado_industrial
                 or coalesce(
                      case when v_ambito = 'INTERNA' then px.perfil->>'cfop_interno'
                           else px.perfil->>'cfop_externo' end,
                      ''
                    ) not in ('5102', '6102')
               )
               then coalesce(fx.c_enq, '999')
             else fx.c_enq
           end as cenq_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then coalesce(
                 nullif(px.perfil->>'aliquota_ipi', '')::numeric,
                 -- Perfil que so diz CST e cEnq (50/99): a aliquota e do NCM — cadastro do
                 -- produto e, na falta, TIPI (20260918220000, perfis de origem 1).
                 case when px.perfil->>'cst_ipi' in ('50', '99')
                      then coalesce(c.aliquota_ipi_produto, tp.aliquota) end
               )
             when tp.aliquota > 0 and c.cst_ipi_produto is not null
               and (
                 c.equiparado_industrial
                 or coalesce(
                      case when v_ambito = 'INTERNA' then px.perfil->>'cfop_interno'
                           else px.perfil->>'cfop_externo' end,
                      ''
                    ) not in ('5102', '6102')
               )
               then coalesce(c.aliquota_ipi_produto, tp.aliquota)
             else fx.aliquota_ipi
           end as aliquota_ipi_operacao,
           case
             when nullif(btrim(px.perfil->>'cst_ipi'), '') is not null
              and nullif(btrim(px.perfil->>'ipi_codigo_enquadramento_legal'), '') is not null
               then 'PERFIL_OPERACAO'
             when tp.aliquota > 0 and c.cst_ipi_produto is not null
               and (
                 c.equiparado_industrial
                 or coalesce(
                      case when v_ambito = 'INTERNA' then px.perfil->>'cfop_interno'
                           else px.perfil->>'cfop_externo' end,
                      ''
                    ) not in ('5102', '6102')
               ) then 'PRODUTO_TIPI'
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

-- 3. Conferencias: so checam. --------------------------------------------------------------------
do $assertions$
declare
  v_def text := pg_get_functiondef('f.fn_solicitacao_nfe_resolver_perfis(uuid, text, text)'::regprocedure);
  v_perfil f.perfil_operacao%rowtype;
  v_codigo text;
begin
  if v_def not like '%then coalesce(c.aliquota_ipi_produto, tp.aliquota) end%' then
    raise exception 'resolvedor sem a aliquota do produto/TIPI para perfil com CST 50/99';
  end if;
  foreach v_codigo in array array['SEG-VENDA-TERCEIROS-SC-5102-O1-CST00', 'SEG-VENDA-TERCEIROS-SC-5102-O1-CST00-17'] loop
    select * into v_perfil from f.perfil_operacao where codigo = v_codigo and vigencia_fim is null;
    if v_perfil.id is null then
      raise notice 'perfil % ausente (banco sem os perfis -O2-): assercao pulada.', v_codigo;
      continue;
    end if;
    if v_perfil.origem_mercadoria <> 1 or v_perfil.cst_ipi <> '50' or v_perfil.ipi_codigo_enquadramento_legal <> '999'
       or v_perfil.aliquota_ipi is not null or v_perfil.habilitado_producao or v_perfil.faixa_automacao <> 'REVISAO'
       or v_perfil.cfop_interno <> '5102' or v_perfil.ambito_destino <> 'INTERNA' then
      raise exception 'perfil % fora do esperado: %', v_codigo, to_jsonb(v_perfil);
    end if;
    if v_codigo like '%-17' then
      if v_perfil.aliquota_icms <> 17 or v_perfil.consumidor_final <> 1 or not ('MANUTENCAO' = any(v_perfil.destinacoes_mercadoria)) then
        raise exception 'perfil % (17%%) fora do esperado', v_codigo;
      end if;
    else
      if v_perfil.aliquota_icms <> 12 or v_perfil.consumidor_final <> 0 or ('MANUTENCAO' = any(v_perfil.destinacoes_mercadoria)) then
        raise exception 'perfil % (12%%) fora do esperado', v_codigo;
      end if;
    end if;
    if v_perfil.evidencia_id is not null and not exists (
      select 1 from f.perfil_operacao_evidencia e where e.id = v_perfil.evidencia_id and e.perfil_operacao_id = v_perfil.id and e.origem = 1
    ) then
      raise exception 'evidencia do perfil % nao aponta para ele', v_codigo;
    end if;
  end loop;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
