-- Correcao da 20260906160000: ipi_fonte so aceita PERFIL_OPERACAO ou FIXTURE_HOMOLOGACAO
-- (check solicitacao_item_ipi_fonte_check). A linha resolvida por perfil grava PERFIL_OPERACAO:
-- o IPI continua vindo do cadastro do item, mas a fonte fiscal da linha e o perfil.
-- Baseline: f.fn_os_nfe_conferir_homologacao (20260906160000).

create or replace function f.fn_os_nfe_conferir_homologacao(p_solicitacao_id uuid, p_operacao jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_os public.ordens_servico%rowtype;
  v_cliente public.clientes%rowtype;
  v_uf_emitente text;
  v_ambito text;
  v_cfop text;
  v_natureza text;
  v_fx f.tributacao_provisoria_homologacao%rowtype;
  v_destinacao text;
  v_destino_uf text;
  v_consumidor_final smallint;
  v_aliquota numeric;
  v_item record;
  v_fi public.fiscal_itens%rowtype;
  v_item_cad public.itens%rowtype;
  v_total numeric(14,2);
  v_saldo record;
  v_reserva_propria numeric(14,2);
  v_parcelas jsonb;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_emissao_status text;
  v_linhas integer := 0;
  v_po f.perfil_operacao%rowtype;
  v_po_id uuid;
  v_po_unico uuid;
  v_po_misto boolean := false;
  v_crt text;
  v_fonte text;
begin
  select * into v_sf from f.solicitacao_faturamento where id = p_solicitacao_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s nao pode ser conferida.', v_sf.status);
  end if;

  select e.status into v_emissao_status
  from f.documento_fiscal_emissao e
  where e.tenant_id = v_sf.tenant_id and e.empresa_id = v_sf.empresa_id and e.solicitacao_id = v_sf.id
  order by e.created_at desc limit 1;
  if v_emissao_status is not null and v_emissao_status not in ('RASCUNHO', 'REJEITADA', 'ERRO') then
    raise exception using errcode = '55000', message = format('A NF-e desta solicitacao ja esta em %s; a conferencia nao pode mais ser alterada.', v_emissao_status);
  end if;

  -- Origem: todas as linhas de uma OS (nao OV).
  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id
    and os.tipo_documento = 'OS'
    and os.id::text = (
      select si.origem_id from f.solicitacao_item si
      where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
        and si.origem_tipo = 'OS'
      order by si.ordem limit 1
    );
  if not found then
    raise exception using errcode = '22023', message = 'Esta conferencia e exclusiva de solicitacoes originadas de OS.';
  end if;
  if lower(coalesce(v_os.status_fluxo, v_os.status, '')) = 'cancelada' then
    raise exception using errcode = '22023', message = format('A OS %s esta cancelada e nao pode ser faturada.', coalesce(v_os.numero_os, v_os.id::text));
  end if;

  select c.* into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Destinatario da OS nao encontrado nesta empresa.';
  end if;
  if exists (
    select 1 from public.empresas e
    where e.tenant_id = v_sf.tenant_id
      and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') <> ''
      and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') = regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g')
  ) then
    raise exception using errcode = '22023', message = 'OS interna (cliente e uma empresa do grupo) nao emite NF-e por este fluxo.';
  end if;

  select upper(ee.uf::text) into v_uf_emitente
  from c.empresa_endereco ee
  where ee.empresa_id = v_sf.empresa_id and ee.tipo = 'FISCAL' and ee.deleted_at is null
  order by ee.created_at limit 1;
  if v_uf_emitente is null then
    raise exception using errcode = '22023', message = 'A UF fiscal do emitente nao esta cadastrada.';
  end if;

  -- Destino confirmado pela pessoa, conferido contra o cadastro do cliente.
  v_destino_uf := upper(btrim(coalesce(p_operacao->>'destino_uf_confirmada', '')));
  if v_destino_uf = '' then
    raise exception using errcode = '22023', message = 'Confirme a UF de destino da mercadoria.';
  end if;
  if v_destino_uf is distinct from upper(btrim(coalesce(v_cliente.uf, ''))) then
    raise exception using errcode = '22023', message = format(
      'UF confirmada (%s) diverge da UF do cadastro do cliente (%s). Corrija em /clientes/cadastro-fiscal?cliente_id=%s.',
      v_destino_uf, coalesce(v_cliente.uf, '<vazia>'), v_cliente.id);
  end if;
  v_ambito := case when v_destino_uf = v_uf_emitente then 'INTERNA' else 'INTERESTADUAL' end;
  select ef.crt::text into v_crt from c.empresa_fiscal ef where ef.empresa_id = v_sf.empresa_id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  v_cfop := case when v_ambito = 'INTERNA' then '5101' else '6101' end;
  v_natureza := case when v_ambito = 'INTERNA' then 'VENDA_INDUSTRIALIZACAO_INTERNA' else 'VENDA_INDUSTRIALIZACAO_INTERESTADUAL' end;
  if v_ambito = 'INTERESTADUAL' and coalesce(v_cliente.indicador_ie, '') <> '1' then
    raise exception using errcode = '22023', message = 'Operacao interestadual para nao contribuinte exige perfil proprio de DIFAL; nao ha fixture para isso.';
  end if;

  select * into v_fx
  from f.tributacao_provisoria_homologacao t
  where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.cfop = v_cfop and t.ativo;
  -- Sem fixture nao e erro se todas as linhas resolverem um perfil vigente (validado por linha).

  -- Destinacao declarada pelo destinatario: decide a aliquota interna.
  v_destinacao := upper(btrim(coalesce(p_operacao->>'destinacao_mercadoria', '')));
  if v_destinacao not in ('REVENDA', 'INSUMO', 'MANUTENCAO', 'CONSIGNADO', 'USO_CONSUMO', 'ATIVO_IMOBILIZADO') then
    raise exception using errcode = '22023', message = 'Informe a destinacao da mercadoria: ela decide a aliquota interna de ICMS.';
  end if;
  v_consumidor_final := case when v_destinacao in ('USO_CONSUMO', 'ATIVO_IMOBILIZADO') then 1 else 0 end;

  -- Operacao: presenca, frete, pagamento e parcelas (mesmas regras da OV).
  if nullif(btrim(coalesce(p_operacao->>'presenca_comprador', '')), '') is null
     or (p_operacao->>'presenca_comprador')::smallint not in (1, 2, 3, 4, 5, 9) then
    raise exception using errcode = '22023', message = 'Presenca do comprador deve ser 1 a 5 ou 9 em venda normal.';
  end if;
  if nullif(btrim(coalesce(p_operacao->>'pagamento_forma', '')), '') is null
     or btrim(p_operacao->>'pagamento_forma') !~ '^(0[1-5]|1[0-9]|2[0-4]|9[019])$' then
    raise exception using errcode = '22023', message = 'Forma de pagamento (tPag) invalida ou nao confirmada.';
  end if;
  if nullif(btrim(coalesce(p_operacao->>'pagamento_indicador', '')), '') is null
     or (p_operacao->>'pagamento_indicador')::smallint not in (0, 1) then
    raise exception using errcode = '22023', message = 'Indicador de pagamento deve ser 0 (a vista) ou 1 (a prazo).';
  end if;
  if btrim(p_operacao->>'pagamento_forma') = '99'
     and nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), '') is null then
    raise exception using errcode = '22023', message = 'Descreva a forma de pagamento quando escolher 99 (outros).';
  end if;
  v_parcelas := case when (p_operacao->>'pagamento_indicador')::smallint = 1
    then f.fn_nfe_normalizar_parcelas(p_operacao->'pagamento_parcelas') else null end;

  -- Linhas: total contra o saldo (a reserva desta propria solicitacao conta a favor).
  select round(coalesce(sum(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0)), 0), 2), count(*)
    into v_total, v_linhas
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id;
  if v_linhas = 0 then
    raise exception using errcode = '22023', message = 'A solicitacao nao tem linhas.';
  end if;
  if v_total <= 0 then
    raise exception using errcode = '22023', message = 'O total da nota precisa ser maior que zero.';
  end if;
  select * into v_saldo from f.fn_os_saldo_a_faturar(v_sf.tenant_id, v_sf.empresa_id, v_os.id);
  v_reserva_propria := case when v_sf.status <> 'CANCELADA' then v_total else 0 end;
  if v_saldo.valor_pedido > 0 and v_total > v_saldo.saldo + v_reserva_propria + 0.005 then
    raise exception using errcode = '22023', message = format(
      'Total das linhas R$ %s acima do saldo da OS R$ %s.',
      to_char(v_total, 'FM999G999G990D00'), to_char(v_saldo.saldo + v_reserva_propria, 'FM999G999G990D00'));
  end if;

  -- Cada linha: produto fabricado com cadastro fiscal completo. Nada deduzido.
  for v_item in
    select si.* from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
    order by si.ordem
  loop
    if v_item.quantidade is null or v_item.quantidade <= 0 or v_item.valor_unitario is null or v_item.valor_unitario <= 0 then
      raise exception using errcode = '22023', message = format('Linha %s: quantidade e valor unitario precisam ser positivos.', v_item.ordem);
    end if;
    if v_item.item_id is null then
      raise exception using errcode = '22023', message = format('Linha %s: vincule um produto fabricado (campo produto).', v_item.ordem);
    end if;
    select * into v_item_cad from public.itens i where i.tenant_id = v_sf.tenant_id and i.id = v_item.item_id;
    if not found then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s nao encontrado.', v_item.ordem, v_item.item_id);
    end if;
    select * into v_fi from public.fiscal_itens fi
    where fi.tenant_id = v_sf.tenant_id and fi.empresa_id = v_sf.empresa_id and fi.item_id = v_item.item_id;
    if not found or regexp_replace(coalesce(v_fi.ncm, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem NCM (campo ncm em /itens).', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if v_fi.origem is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem origem da mercadoria (campo origem em /itens). Nao e deduzida.', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if nullif(btrim(coalesce(v_fi.unidade_tributavel, '')), '') is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem unidade tributavel (campo unidade_tributavel em /itens).', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if nullif(btrim(coalesce(v_fi.cst_ipi, '')), '') is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s sem CST de IPI (campo cst_ipi em /itens); a fixture 5101 nao presume IPI.', v_item.ordem, v_item_cad.codigo_interno);
    end if;
    if v_fi.cst_ipi in ('00', '49', '50', '99') and v_fi.aliq_ipi is null then
      raise exception using errcode = '22023', message = format('Linha %s: produto %s com IPI tributado (CST %s) sem aliquota (campo aliq_ipi em /itens).', v_item.ordem, v_item_cad.codigo_interno, v_fi.cst_ipi);
    end if;

    select po.* into v_po from f.perfil_operacao po
    where po.tenant_id = v_sf.tenant_id and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null)
      and po.modelo = 'NFE' and po.natureza_operacao = v_natureza and po.ambito_destino = v_ambito
      and po.ufs_destino is not null and v_destino_uf = any(po.ufs_destino)
      and coalesce(po.indicador_ie_destinatario, '') = coalesce(v_cliente.indicador_ie, '')
      and po.origem_mercadoria = v_fi.origem
      and (po.destinacoes_mercadoria is null or v_destinacao = any(po.destinacoes_mercadoria))
      and (po.crt is null or po.crt = v_crt)
      and po.faixa_automacao <> 'BLOQUEADO' and po.vigencia_inicio <= current_date and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
      and po.revisao_fiscal_em is not null and po.cst_icms is not null and po.aliquota_icms is not null
    order by po.habilitado_producao desc, po.revisao_fiscal_em desc limit 1;
    if found then
      v_po_id := v_po.id; v_fonte := 'PERFIL';
      if v_po_unico is null then v_po_unico := v_po.id; elsif v_po_unico <> v_po.id then v_po_misto := true; end if;
      update f.solicitacao_item si
      set cfop = coalesce(case when v_ambito = 'INTERNA' then v_po.cfop_interno else v_po.cfop_externo end, v_cfop),
          cst_icms = v_po.cst_icms, csosn = v_po.csosn,
          icms_modalidade_base_calculo = coalesce(v_po.icms_modalidade_base_calculo, '3'),
          aliquota_icms = v_po.aliquota_icms,
          reducao_base_icms_percentual = coalesce(v_po.reducao_base_icms_percentual, 0),
          cbenef = case when v_po.cbenef_aplicacao = 'COM_BENEFICIO' then v_po.cbenef else null end,
          cst_pis = v_po.cst_pis, aliquota_pis = v_po.aliquota_pis,
          cst_cofins = v_po.cst_cofins, aliquota_cofins = v_po.aliquota_cofins,
          cst_ipi = v_fi.cst_ipi,
          aliquota_ipi = case when v_fi.cst_ipi in ('00', '49', '50', '99') then v_fi.aliq_ipi else null end,
          ipi_codigo_enquadramento_legal = coalesce(nullif(btrim(v_fi.ipi_codigo_enquadramento_legal), ''), v_po.ipi_codigo_enquadramento_legal, '999'),
          ipi_fonte = 'PERFIL_OPERACAO',
          ncm = regexp_replace(v_fi.ncm, '[^0-9]', '', 'g'),
          cest = nullif(regexp_replace(coalesce(v_fi.cest, ''), '[^0-9]', '', 'g'), ''),
          origem_mercadoria = v_fi.origem,
          unidade_tributavel = upper(btrim(v_fi.unidade_tributavel)),
          codigo_produto = coalesce(nullif(btrim(v_item_cad.codigo_interno), ''), v_item_cad.id::text),
          numero_fci = v_fi.numero_fci,
          cst_ibs_cbs = v_po.cst_ibs_cbs, cclass_trib = v_po.cclass_trib,
          ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_po.ibs_cbs_json, 'ibs_uf_aliquota'), 'ibs_mun_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_po.ibs_cbs_json, 'ibs_mun_aliquota'), 'cbs_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_po.ibs_cbs_json, 'cbs_aliquota')),
          perfil_operacao_id = v_po.id, perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id,
          tributacao_fonte = 'PERFIL'
      where si.id = v_item.id;
      continue;
    end if;
    if v_fx.cfop is null then
      raise exception using errcode = '22023', message = format('Linha %s: nenhum perfil vigente para %s/%s (origem %s, destinacao %s) e sem fixture de homologacao para o CFOP %s.', v_item.ordem, v_natureza, v_ambito, v_fi.origem, v_destinacao, v_cfop);
    end if;
    v_fonte := coalesce(v_fonte, 'FIXTURE_HOMOLOGACAO');
    v_aliquota := case
      when v_ambito = 'INTERNA' then
        case when v_destinacao in ('USO_CONSUMO', 'ATIVO_IMOBILIZADO') then v_fx.aliquota_icms_consumo else v_fx.aliquota_icms_contribuinte end
      when v_fi.origem in (1, 2, 6) then v_fx.aliquota_icms_importado
      when v_destino_uf in ('PR', 'RS', 'SP', 'RJ', 'MG') then v_fx.aliquota_icms_interestadual_sul_sudeste
      else v_fx.aliquota_icms_interestadual_demais
    end;
    if v_aliquota is null then
      raise exception using errcode = '22023', message = format('Fixture %s sem aliquota de ICMS para o ambito %s.', v_cfop, v_ambito);
    end if;

    update f.solicitacao_item si
    set cfop = v_cfop,
        cst_icms = v_fx.cst_icms,
        csosn = null,
        icms_modalidade_base_calculo = '3',
        aliquota_icms = v_aliquota,
        reducao_base_icms_percentual = 0,
        cbenef = null,
        cst_pis = v_fx.cst_pis, aliquota_pis = v_fx.aliquota_pis,
        cst_cofins = v_fx.cst_cofins, aliquota_cofins = v_fx.aliquota_cofins,
        cst_ipi = v_fi.cst_ipi,
        aliquota_ipi = case when v_fi.cst_ipi in ('00', '49', '50', '99') then v_fi.aliq_ipi else null end,
        ipi_codigo_enquadramento_legal = coalesce(nullif(btrim(v_fi.ipi_codigo_enquadramento_legal), ''), v_fx.c_enq, '999'),
        ipi_fonte = 'FIXTURE_HOMOLOGACAO',
        ncm = regexp_replace(v_fi.ncm, '[^0-9]', '', 'g'),
        cest = nullif(regexp_replace(coalesce(v_fi.cest, ''), '[^0-9]', '', 'g'), ''),
        origem_mercadoria = v_fi.origem,
        unidade_tributavel = upper(btrim(v_fi.unidade_tributavel)),
        codigo_produto = coalesce(nullif(btrim(v_item_cad.codigo_interno), ''), v_item_cad.id::text),
        numero_fci = v_fi.numero_fci,
        cst_ibs_cbs = '000',
        cclass_trib = '000001',
        ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', 0.1000, 'ibs_mun_aliquota', 0.0000, 'cbs_aliquota', 0.9000),
        perfil_operacao_id = null,
        perfil_aplicado_em = now(),
        perfil_aplicado_por = v_usuario_id,
        tributacao_fonte = 'FIXTURE_HOMOLOGACAO'
    where si.id = v_item.id;
  end loop;

  update f.solicitacao_faturamento sf
  set natureza_operacao = v_natureza,
      finalidade_emissao = 1,
      consumidor_final = v_consumidor_final,
      presenca_comprador = (p_operacao->>'presenca_comprador')::smallint,
      modalidade_frete = coalesce(nullif(p_operacao->>'modalidade_frete', '')::smallint, 9),
      valor_frete = coalesce(nullif(p_operacao->>'valor_frete', '')::numeric, 0),
      valor_seguro = coalesce(nullif(p_operacao->>'valor_seguro', '')::numeric, 0),
      valor_outras_despesas = coalesce(nullif(p_operacao->>'valor_outras_despesas', '')::numeric, 0),
      destinacao_mercadoria = v_destinacao,
      pagamento_forma = btrim(p_operacao->>'pagamento_forma'),
      pagamento_indicador = (p_operacao->>'pagamento_indicador')::smallint,
      pagamento_descricao = nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''),
      pagamento_parcelas = v_parcelas,
      transportador_dados = null,
      volumes_dados = null,
      pedido_cliente = coalesce(nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), ''), sf.pedido_cliente, v_os.pedido_compra),
      observacao = coalesce(nullif(btrim(coalesce(p_operacao->>'observacao', '')), ''), sf.observacao),
      destino_uf_confirmada = v_destino_uf,
      destino_confirmado_em = now(),
      destino_confirmado_por = v_usuario_id,
      perfil_operacao_id = case when v_po_unico is not null and not v_po_misto and v_fonte = 'PERFIL' then v_po_unico else null end,
      perfil_aplicado_em = now(),
      perfil_aplicado_por = v_usuario_id,
      revisao_fiscal_confirmada_em = now(),
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null, destinatario_snapshot = null,
      operacao_snapshot = null, snapshot_cadastro_em = null,
      updated_at = now()
  where sf.id = v_sf.id;

  if v_fonte = 'PERFIL' and exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and si.tributacao_fonte is distinct from 'PERFIL') then
    raise exception using errcode = '22023', message = 'Linhas com perfil vigente e linhas na fixture na mesma nota: cadastre o perfil que falta ou separe as notas.';
  end if;

  -- Pedido de compra digitado na tela de faturar grava na OS.
  if nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is not null
     and nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is distinct from v_os.pedido_compra then
    update public.ordens_servico set pedido_compra = btrim(p_operacao->>'pedido_cliente'), atualizado_em = now()
    where id = v_os.id and tenant_id = v_sf.tenant_id and empresa_id = v_sf.empresa_id;
  end if;

  -- Congela emitente, destinatario, operacao e itens; devolve as pendencias de cadastro.
  return f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id)
    || jsonb_build_object('natureza_operacao', v_natureza, 'cfop', v_cfop, 'ambito', v_ambito,
                          'tributacao_fonte', coalesce(v_fonte, 'FIXTURE_HOMOLOGACAO'), 'perfil_operacao_id', case when v_po_misto then null else v_po_unico end, 'total', v_total, 'saldo_os', v_saldo.saldo);
end;
$function$;


