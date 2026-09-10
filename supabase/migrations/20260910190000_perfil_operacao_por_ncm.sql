-- Perfil fiscal por NCM: o que faltava para o beneficio de automacao sair na nota.
--
-- Gabriel em 10/09/2026, na OV-SEG-00007-026 (Portobello, CHAVE SEG FD2083, item
-- 20973, NCM 8536.50.90): emitiu em homologacao e o rascunho ficou preso, sem numero
-- e sem chave. Reproduzido rodando o proprio builder sobre o contexto real:
--
--   "item 20973, NCM 85365090 tem reducao de base do Anexo 2, Art. 7o, VII e exige
--    o cBenef SC820006 - a SEFAZ rejeita beneficio de ICMS sem codigo desde
--    03/02/2025."
--
-- O builder esta certo: 8536.50.90 e um dos tres NCM do Art. 7o, VII (com 8536.49.00
-- e 8544.49.00) e a carga de 12% ali e beneficio, nao aliquota. Quem resolveu a linha
-- foi o perfil SEG-VENDA-TERCEIROS-SC-5102-O2-CST00, que aplica 12% direto e nao tem
-- cBenef nenhum — correto para a revenda comum, errado para esses tres NCM.
--
-- O perfil certo ja existe e ja esta revisado: CSV63-001 (CST 20, 17% com base
-- reduzida em 29,412%, cBenef SC820006, origem 2) — exatamente a NF-e 3607 de
-- 07/04/2026 que o Gabriel anexou, mesma chave FD2083: base 557,10 sobre 789,21 e
-- ICMS 94,71. Faltava poder liberar esse perfil sem quebrar o resto: o resolvedor
-- escolhe por CFOP, origem, destinacao e UF, nunca por NCM, entao os dois perfis
-- passariam a valer para a mesma linha e tudo cairia em AMBIGUO.
--
-- Esta migration da ao perfil uma lista opcional de NCM e ensina o resolvedor a
-- preferir o especifico. Regra: perfil com lista so vale para os NCM dela; perfil
-- sem lista e o generico, e sai de cena na linha em que um especifico casa.

alter table f.perfil_operacao
  add column if not exists ncms_elegiveis text[];

comment on column f.perfil_operacao.ncms_elegiveis is
  'NCM (8 digitos, sem pontuacao) que este perfil atende. Nulo = perfil generico, usado quando nenhum perfil com lista casa com o NCM da linha.';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'perfil_operacao_ncms_elegiveis_ck') then
    alter table f.perfil_operacao
      add constraint perfil_operacao_ncms_elegiveis_ck
      -- array_to_string e imutavel; CHECK nao aceita subconsulta. A regex cobre as
      -- duas regras de uma vez: pelo menos um elemento, e todo elemento com 8 digitos.
      check (
        ncms_elegiveis is null
        or array_to_string(ncms_elegiveis, ',') ~ '^[0-9]{8}(,[0-9]{8})*$'
      );
  end if;
end
$$;

-- Os tres NCM do Art. 7o, VII, os mesmos ja listados em
-- supabase/functions/_shared/fiscal/icms-sc-destinacao.ts (REDUCAO_AUTOMACAO_SC).
update f.perfil_operacao
   set ncms_elegiveis = array['85364900', '85365090', '85444900']
 where cbenef = 'SC820006'
   and cst_icms = '20';

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

-- Libera o CSV63-001 (origem 2, o caso da OV-SEG-00007-026). Ja tinha revisao fiscal
-- salva; o que faltava era a lista de NCM que agora o resolvedor respeita. Fica em
-- REVISAO e sem producao: homologacao primeiro, como todo perfil novo nesta fase.
update f.perfil_operacao
   set faixa_automacao = 'REVISAO',
       justificativa_faixa = 'Liberado em 10/09/2026 para os tres NCM do Anexo 2, Art. 7o, VII, com a lista de NCM do perfil. Espelha a NF-e 3607 de 07/04/2026 (mesmo item FD2083): CST 20, base reduzida 29,412%, 17% nominais, cBenef SC820006.',
       vigencia_inicio = least(vigencia_inicio, current_date)
 where codigo = 'CSV63-001';

do $conferir$
declare
  v_lista text[];
  v_faixa text;
begin
  select ncms_elegiveis, faixa_automacao into v_lista, v_faixa
  from f.perfil_operacao where codigo = 'CSV63-001';

  if not found then
    raise notice 'CSV63-001 nao existe neste banco; nada a conferir.';
    return;
  end if;
  if v_lista is null or not ('85365090' = any(v_lista)) or v_faixa = 'BLOQUEADO' then
    raise exception 'CSV63-001 ficou com ncms_elegiveis=% e faixa=%; esperado a lista dos tres NCM e fora de BLOQUEADO.',
      v_lista, v_faixa;
  end if;
  raise notice 'CSV63-001 liberado para % NCM; perfil generico segue valendo no resto.', array_length(v_lista, 1);
end
$conferir$;
