-- NF-e de industrializacao a partir da OS, somente HOMOLOGACAO (05/09/2026).
-- Inventario e decisoes: docs/faturamento/os-nfe-inventario.md.
--
-- O que este arquivo faz:
--   1. public.itens.origem_os_id (produto fabricado criado "da OS").
--   2. f.solicitacao_item.tributacao_fonte: de onde vieram os campos fiscais da
--      linha (PERFIL ou FIXTURE_HOMOLOGACAO). Linha de fixture nunca passa no
--      portao de producao, que exige perfil liberado por linha.
--   3. f.tributacao_provisoria_homologacao ganha ICMS/PIS/COFINS por CFOP e a
--      fonte documental; semeia 5101 e 6101 a partir das NF-e de agosto/2026.
--      NENHUM valor entra em f.perfil_operacao.
--   4. f.fn_os_saldo_a_faturar: funcao unica de saldo, reserva por emissao
--      (RASCUNHO/ENVIANDO/PROCESSANDO/AUTORIZADA sem documento EMITIDA);
--      CANCELADA, REJEITADA e ERRO nao somam.
--   5. f.fn_os_nfe_conferir_homologacao: conferencia propria da OS. Preenche
--      as linhas com fixture + cadastro fiscal do produto (sem deducao de
--      origem), valida saldo e chama o congelamento de cadastro existente.
--   6. public.criar_item_fabricado_da_os: cadastro do produto fabricado com o
--      fiscal completo, reaproveitavel em outra OS.
--   7. f.fn_os_notas: lista das notas da OS para a tela.
--   8. public.os_faturar e a listagem: "Faturada" exige documento emitido E
--      saldo zero (regra unica em f.fn_os_pronta_para_faturada).

-- ---------------------------------------------------------------------------
-- 1. Produto fabricado nascido de uma OS
-- ---------------------------------------------------------------------------
alter table public.itens
  add column if not exists origem_os_id integer references public.ordens_servico(id);
create index if not exists idx_itens_origem_os_id on public.itens (origem_os_id) where origem_os_id is not null;
comment on column public.itens.origem_os_id is
  'OS que originou o cadastro do produto fabricado (itens.fabricado = true). O produto continua reaproveitavel em outras OS.';

-- ---------------------------------------------------------------------------
-- 2. Origem dos campos fiscais da linha
-- ---------------------------------------------------------------------------
alter table f.solicitacao_item
  add column if not exists tributacao_fonte text;
alter table f.solicitacao_item
  drop constraint if exists solicitacao_item_tributacao_fonte_check;
alter table f.solicitacao_item
  add constraint solicitacao_item_tributacao_fonte_check
  check (tributacao_fonte is null or tributacao_fonte in ('PERFIL', 'FIXTURE_HOMOLOGACAO'));
comment on column f.solicitacao_item.tributacao_fonte is
  'PERFIL: campos vindos de f.perfil_operacao (perfil_operacao_id preenchido). FIXTURE_HOMOLOGACAO: campos vindos de f.tributacao_provisoria_homologacao, somente para emissao em homologacao; producao exige perfil liberado.';

-- ---------------------------------------------------------------------------
-- 3. Fixture provisoria por CFOP (homologacao)
-- ---------------------------------------------------------------------------
alter table f.tributacao_provisoria_homologacao
  add column if not exists natureza_operacao text,
  add column if not exists cst_icms text,
  add column if not exists aliquota_icms_contribuinte numeric(7,4),
  add column if not exists aliquota_icms_consumo numeric(7,4),
  add column if not exists aliquota_icms_interestadual_sul_sudeste numeric(7,4),
  add column if not exists aliquota_icms_interestadual_demais numeric(7,4),
  add column if not exists aliquota_icms_importado numeric(7,4),
  add column if not exists cst_pis text,
  add column if not exists aliquota_pis numeric(7,4),
  add column if not exists cst_cofins text,
  add column if not exists aliquota_cofins numeric(7,4),
  add column if not exists fonte text;

comment on table f.tributacao_provisoria_homologacao is
  'Valores fiscais PROVISORIOS usados apenas em HOMOLOGACAO enquanto o perfil de operacao nao esta liberado. Cada linha diz a fonte documental. Producao nunca le esta tabela.';

-- Na industrializacao o CST/aliquota de IPI vem do cadastro do produto, nao do
-- CFOP: a fixture 5101/6101 fica sem cst_ipi.
alter table f.tributacao_provisoria_homologacao alter column cst_ipi drop not null;

-- 5101: venda de producao propria dentro de SC. Fonte: NF-e reais de agosto/2026
-- (docs/faturamento/regras-nfe-63-combinacoes.csv): 34 notas CFOP 5101, origem 0,
-- CST 00, ICMS 17%, IPI 0 (NF-e 3527, 3528, 3529, 3530, 3535, 3543, 3549, 3553);
-- NF-e 3766 (NCM 8537.10.19) com IPI 9,75%. Os 12% para contribuinte que
-- revende/industrializa vem da Lei 10.297/96 art. 19 III n (mesma regra da
-- revenda). CST/aliquota de IPI NAO ficam aqui: vem do cadastro fiscal do
-- produto (pergunta 2 ao contador). Sem cEnq no produto, usa 999.
insert into f.tributacao_provisoria_homologacao (
  tenant_id, empresa_id, cfop, cst_ipi, c_enq, aliquota_ipi, ativo, pendencia_contador,
  natureza_operacao, cst_icms, aliquota_icms_contribuinte, aliquota_icms_consumo,
  aliquota_icms_interestadual_sul_sudeste, aliquota_icms_interestadual_demais, aliquota_icms_importado,
  cst_pis, aliquota_pis, cst_cofins, aliquota_cofins, fonte
)
select ef_emp.tenant_id, ef_emp.id, x.cfop, null, '999', null, true,
  'Perguntas 4 (industrializacao x revenda), 2 (IPI do 8537.10.19) e 8 (origem de produto montado com componente importado) ao contador.',
  x.natureza, '00', 12, 17, 12, 7, 4,
  '01', 1.65, '01', 7.6,
  x.fonte
from (values
  ('5101', 'VENDA_INDUSTRIALIZACAO_INTERNA',
   'NF-e 3527-3553 (34 notas, agosto/2026): CFOP 5101, origem 0, CST 00, 17%, IPI 0. NF-e 3766: IPI 9,75% no NCM 8537.10.19. 12% por destinacao: Lei 10.297/96 art. 19 III n.'),
  ('6101', 'VENDA_INDUSTRIALIZACAO_INTERESTADUAL',
   'Perfis CSV63-026/027/056 (CFOP 6101, origem 0, CST 00, 12%). 7% para as demais UFs e 4% importado: Resolucoes do Senado 22/89 e 13/2012.')
) as x(cfop, natureza, fonte)
join c.empresa ef_emp on ef_emp.deleted_at is null
join c.empresa_fiscal ef on ef.empresa_id = ef_emp.id and ef.deleted_at is null
where not exists (
  select 1 from f.tributacao_provisoria_homologacao t
  where t.tenant_id = ef_emp.tenant_id and t.empresa_id = ef_emp.id and t.cfop = x.cfop
);

-- ---------------------------------------------------------------------------
-- 4. Funcao unica de saldo
-- ---------------------------------------------------------------------------
create or replace function f.fn_os_saldo_a_faturar(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns table(valor_pedido numeric, valor_faturado numeric, valor_reservado numeric, saldo numeric, usa_relatorio_hh boolean)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_os public.ordens_servico%rowtype;
  v_valor_pedido numeric(14,2);
  v_valor_faturado numeric(14,2);
  v_valor_reservado numeric(14,2);
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS/OV sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar o faturamento desta empresa.';
  end if;

  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and os.id = p_os_id
    and os.tipo_documento in ('OS', 'OV');

  if not found then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  if v_os.usa_relatorio_hh then
    select coalesce(hh.total_hh, 0)
    into v_valor_pedido
    from public.vw_hh_total_os hh
    where hh.tenant_id = p_tenant_id
      and hh.empresa_id = p_empresa_id
      and hh.os_id = p_os_id;
    v_valor_pedido := coalesce(v_valor_pedido, 0);
  else
    v_valor_pedido := coalesce(v_os.orcado, 0);
  end if;

  -- Faturado: documentos de saida emitidos (producao) ou importados. IPI, frete,
  -- seguro e outras despesas compoem o total fiscal, nao o saldo comercial.
  select coalesce(sum(
    case
      when upper(coalesce(df.modelo, '')) = 'NFSE' then coalesce(df.valor_total, 0)
      else greatest(
        coalesce(df.valor_produtos, df.valor_total, 0) - coalesce(df.valor_desconto, 0),
        0
      )
    end
  ), 0)
  into v_valor_faturado
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.os_id_import = p_os_id
    and df.operacao = 'SAIDA'
    and df.deleted_at is null
    and (
      (upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
      or (
        upper(coalesce(df.modelo, '')) <> 'NFSE'
        and (nullif(btrim(df.nfe_status), '') is null or upper(df.nfe_status) = 'EMITIDA')
      )
    );

  -- Reservado: solicitacoes nao canceladas cuja emissao mais recente esta em
  -- RASCUNHO, ENVIANDO, PROCESSANDO ou AUTORIZADA (homologacao) e que ainda nao
  -- viraram documento EMITIDA (esses ja estao em "faturado"). REJEITADA, ERRO e
  -- CANCELADA nao somam. Antes, EMITIDA em homologacao saia da reserva sozinha.
  select coalesce(sum(round(
    greatest(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0), 0),
    2
  )), 0)
  into v_valor_reservado
  from f.solicitacao_faturamento sf
  join f.solicitacao_item si
    on si.tenant_id = sf.tenant_id
   and si.empresa_id = sf.empresa_id
   and si.solicitacao_id = sf.id
  where sf.tenant_id = p_tenant_id
    and sf.empresa_id = p_empresa_id
    and sf.status <> 'CANCELADA'
    and si.origem_tipo = v_os.tipo_documento
    and si.origem_id = p_os_id::text
    and not exists (
      select 1
      from f.documento_fiscal_emissao e
      join f.documento_fiscal d
        on d.tenant_id = e.tenant_id and d.empresa_id = e.empresa_id and d.id = e.documento_fiscal_id
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
        and d.deleted_at is null and upper(coalesce(d.nfe_status, '')) = 'EMITIDA'
    )
    and coalesce((
      select e.status
      from f.documento_fiscal_emissao e
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
      order by e.created_at desc, e.documento_fiscal_id desc
      limit 1
    ), 'RASCUNHO') not in ('REJEITADA', 'ERRO', 'CANCELADA');

  valor_pedido := round(v_valor_pedido, 2);
  valor_faturado := round(v_valor_faturado, 2);
  valor_reservado := round(v_valor_reservado, 2);
  saldo := round(v_valor_pedido - v_valor_faturado - v_valor_reservado, 2);
  usa_relatorio_hh := coalesce(v_os.usa_relatorio_hh, false);
  return next;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Conferencia propria da OS (homologacao, fixture + cadastro do produto)
-- ---------------------------------------------------------------------------
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
  v_cfop := case when v_ambito = 'INTERNA' then '5101' else '6101' end;
  v_natureza := case when v_ambito = 'INTERNA' then 'VENDA_INDUSTRIALIZACAO_INTERNA' else 'VENDA_INDUSTRIALIZACAO_INTERESTADUAL' end;
  if v_ambito = 'INTERESTADUAL' and coalesce(v_cliente.indicador_ie, '') <> '1' then
    raise exception using errcode = '22023', message = 'Operacao interestadual para nao contribuinte exige perfil proprio de DIFAL; nao ha fixture para isso.';
  end if;

  select * into v_fx
  from f.tributacao_provisoria_homologacao t
  where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.cfop = v_cfop and t.ativo;
  if not found then
    raise exception using errcode = '22023', message = format('Fixture provisoria de homologacao para o CFOP %s nao cadastrada nesta empresa.', v_cfop);
  end if;

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
      perfil_operacao_id = null,
      perfil_aplicado_em = now(),
      perfil_aplicado_por = v_usuario_id,
      revisao_fiscal_confirmada_em = now(),
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null, destinatario_snapshot = null,
      operacao_snapshot = null, snapshot_cadastro_em = null,
      updated_at = now()
  where sf.id = v_sf.id;

  -- Pedido de compra digitado na tela de faturar grava na OS.
  if nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is not null
     and nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is distinct from v_os.pedido_compra then
    update public.ordens_servico set pedido_compra = btrim(p_operacao->>'pedido_cliente'), atualizado_em = now()
    where id = v_os.id and tenant_id = v_sf.tenant_id and empresa_id = v_sf.empresa_id;
  end if;

  -- Congela emitente, destinatario, operacao e itens; devolve as pendencias de cadastro.
  return f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id)
    || jsonb_build_object('natureza_operacao', v_natureza, 'cfop', v_cfop, 'ambito', v_ambito,
                          'tributacao_fonte', 'FIXTURE_HOMOLOGACAO', 'total', v_total, 'saldo_os', v_saldo.saldo);
end;
$function$;

revoke all on function f.fn_os_nfe_conferir_homologacao(uuid, jsonb) from public, anon;
grant execute on function f.fn_os_nfe_conferir_homologacao(uuid, jsonb) to authenticated, service_role;
comment on function f.fn_os_nfe_conferir_homologacao(uuid, jsonb) is
  'Conferencia de NF-e de industrializacao (5101/6101) originada de OS, SOMENTE HOMOLOGACAO: campos fiscais da fixture provisoria + cadastro fiscal do produto, sem deducao; perfil_operacao_id fica nulo e producao permanece bloqueada.';

-- ---------------------------------------------------------------------------
-- 6. Produto fabricado criado a partir da OS
-- ---------------------------------------------------------------------------
create or replace function public.criar_item_fabricado_da_os(
  p_os_id integer,
  p_nome text,
  p_ncm text,
  p_origem integer,
  p_unidade text,
  p_cst_ipi text,
  p_aliquota_ipi numeric default null,
  p_cenq text default null
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_os public.ordens_servico%rowtype;
  v_codigo text;
  v_seq integer;
  v_item_id integer;
  v_ncm text := regexp_replace(coalesce(p_ncm, ''), '[^0-9]', '', 'g');
  v_unidade text := upper(btrim(coalesce(p_unidade, '')));
  v_cst_ipi text := btrim(coalesce(p_cst_ipi, ''));
begin
  if v_tenant is null or v_empresa is null or not f.has_finance_access(v_tenant, v_empresa) then
    raise exception using errcode = '42501', message = 'Sem permissao para cadastrar produto fabricado nesta empresa.';
  end if;
  select * into v_os from public.ordens_servico os
  where os.tenant_id = v_tenant and os.empresa_id = v_empresa and os.id = p_os_id and os.tipo_documento = 'OS';
  if not found then
    raise exception using errcode = 'P0002', message = format('OS %s nao encontrada nesta empresa.', p_os_id);
  end if;
  if nullif(btrim(coalesce(p_nome, '')), '') is null then
    raise exception using errcode = '22023', message = 'Informe a descricao do produto fabricado.';
  end if;
  if v_ncm !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'NCM deve ter 8 digitos.';
  end if;
  if p_origem is null or p_origem not between 0 and 8 then
    raise exception using errcode = '22023', message = 'Origem da mercadoria (0 a 8) e obrigatoria e nao e deduzida.';
  end if;
  if v_unidade = '' then
    raise exception using errcode = '22023', message = 'Unidade tributavel e obrigatoria.';
  end if;
  if v_cst_ipi !~ '^(0[0-5]|49|5[0-5]|99)$' then
    raise exception using errcode = '22023', message = 'CST de IPI invalido.';
  end if;
  if v_cst_ipi in ('00', '49', '50', '99') and (p_aliquota_ipi is null or p_aliquota_ipi < 0) then
    raise exception using errcode = '22023', message = 'IPI tributado exige aliquota.';
  end if;

  select coalesce(max((regexp_match(i.codigo_interno, '-([0-9]+)$'))[1]::integer), 0) + 1 into v_seq
  from public.itens i
  where i.tenant_id = v_tenant and i.empresa_id = v_empresa
    and i.codigo_interno like 'FAB-OS' || coalesce(v_os.numero_os, v_os.id::text) || '-%';
  v_codigo := 'FAB-OS' || coalesce(v_os.numero_os, v_os.id::text) || '-' || lpad(v_seq::text, 2, '0');

  insert into public.itens (tenant_id, empresa_id, codigo_interno, nome, descricao, tipo, unidade_medida, finalidade, ativo, fabricado, origem_os_id)
  values (v_tenant, v_empresa, v_codigo, upper(btrim(p_nome)), upper(btrim(p_nome)), 'produto', v_unidade, 'revenda', true, true, v_os.id)
  returning id into v_item_id;

  -- A linha fiscal nasce pelo trigger; aqui entram os campos obrigatorios.
  update public.fiscal_itens fi
  set ncm = v_ncm,
      origem = p_origem,
      unidade_tributavel = v_unidade,
      cst_ipi = v_cst_ipi,
      aliq_ipi = case when v_cst_ipi in ('00', '49', '50', '99') then p_aliquota_ipi else null end,
      ipi_codigo_enquadramento_legal = nullif(btrim(coalesce(p_cenq, '')), ''),
      atualizado_em = now()
  where fi.tenant_id = v_tenant and fi.empresa_id = v_empresa and fi.item_id = v_item_id;
  if not found then
    raise exception using errcode = '55000', message = 'A linha fiscal do produto nao foi criada pelo trigger de itens.';
  end if;
  return v_item_id;
end;
$function$;

revoke all on function public.criar_item_fabricado_da_os(integer, text, text, integer, text, text, numeric, text) from public, anon;
grant execute on function public.criar_item_fabricado_da_os(integer, text, text, integer, text, text, numeric, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Notas da OS (lista na tela)
-- ---------------------------------------------------------------------------
create or replace function f.fn_os_notas(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns table(
  documento_fiscal_id uuid, solicitacao_id uuid, ambiente text, emissao_status text, nfe_status text,
  serie text, numero text, chave_acesso text, valor_total numeric, autorizado_em timestamptz,
  danfe_path text, xml_path text, referencia_externa text, created_at timestamptz
)
language sql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
  select d.id, e.solicitacao_id, e.ambiente, e.status, d.nfe_status,
         d.serie, d.numero, d.chave_acesso, d.valor_total, e.autorizado_em,
         e.danfe_path, e.xml_path, e.referencia_externa, e.created_at
  from f.documento_fiscal d
  join f.documento_fiscal_emissao e
    on e.tenant_id = d.tenant_id and e.empresa_id = d.empresa_id and e.documento_fiscal_id = d.id
  where d.tenant_id = p_tenant_id and d.empresa_id = p_empresa_id
    and d.os_id_import = p_os_id and d.operacao = 'SAIDA' and d.deleted_at is null
    and (session_user = 'postgres' or coalesce(auth.jwt()->>'role', '') = 'service_role'
         or (public.current_tenant_id() = p_tenant_id and public.current_empresa_id() = p_empresa_id and f.has_finance_access()))
  order by e.created_at desc;
$function$;
revoke all on function f.fn_os_notas(uuid, uuid, integer) from public, anon;
grant execute on function f.fn_os_notas(uuid, uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. "Faturada" exige documento emitido E saldo zero
-- ---------------------------------------------------------------------------
create or replace function f.fn_os_pronta_para_faturada(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_saldo numeric;
begin
  if not exists (
    select 1 from f.documento_fiscal documento
    where documento.tenant_id = p_tenant_id and documento.empresa_id = p_empresa_id and documento.os_id_import = p_os_id
      and documento.operacao = 'SAIDA' and documento.deleted_at is null
      and ((upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
        or (upper(coalesce(documento.modelo, '')) <> 'NFSE' and (nullif(upper(btrim(coalesce(documento.nfe_status, ''))), '') is null or upper(coalesce(documento.nfe_status, '')) = 'EMITIDA')))
  ) then
    return false;
  end if;
  select s.saldo into v_saldo from f.fn_os_saldo_a_faturar(p_tenant_id, p_empresa_id, p_os_id) s;
  return coalesce(v_saldo, 0) <= 0.005;
end;
$function$;
revoke all on function f.fn_os_pronta_para_faturada(uuid, uuid, integer) from public, anon;
grant execute on function f.fn_os_pronta_para_faturada(uuid, uuid, integer) to authenticated, service_role;

create or replace function public.os_faturar(p_os_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'f', 'auth'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid(); v_tenant_id uuid := public.current_tenant_id(); v_empresa_id uuid := public.current_empresa_id(); v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  if upper(coalesce(v_papel, '')) <> 'FINANCEIRO' then raise exception 'Somente financeiro pode faturar a OS.'; end if;
  if not exists (select 1 from public.ordens_servico where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and status_fluxo='concluida' for update) then raise exception 'A OS precisa estar concluída para ser faturada.'; end if;
  -- Nota emitida ou importada vinculada E saldo zero (regra unica, 05/09/2026).
  if not f.fn_os_pronta_para_faturada(v_tenant_id, v_empresa_id, p_os_id) then
    raise exception 'A OS só pode ser marcada como faturada com NF-e ou NFS-e emitida vinculada e saldo a faturar zerado.';
  end if;
  update public.ordens_servico set status_fluxo='faturada', status='concluida', faturado_em=now(), faturada_presumida_legado=false, atualizado_em=now() where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id;
  insert into public.ordens_servico_fluxo_eventos (tenant_id,empresa_id,os_id,evento,status_origem,status_destino,realizado_por) values (v_tenant_id,v_empresa_id,p_os_id,'faturar','concluida','faturada',v_auth_uid);
  return jsonb_build_object('sucesso', true);
end;
$function$;

-- Listagem: pode_faturar com a mesma regra unica.
CREATE OR REPLACE FUNCTION public.app_listar_os_fluxo_unfiltered_ov_20260829(p_status_fluxo text DEFAULT 'em_andamento'::text, p_busca text DEFAULT NULL::text)
 RETURNS TABLE(id integer, numero_os character varying, os_num bigint, cliente_nome character varying, descricao_servico text, status_legado character varying, status_fluxo text, usa_relatorio_hh boolean, total_horas numeric, responsavel_nome text, situacao_margem text, sou_responsavel boolean, pendencias_aprovacao integer, garantia_motivo text, faturado_em timestamp with time zone, faturada_presumida_legado boolean, pode_concluir boolean, pode_faturar boolean, pode_reabrir_garantia boolean, pode_concluir_garantia boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_status text := lower(coalesce(nullif(btrim(p_status_fluxo), ''), 'em_andamento'));
  v_papel text;
  v_colaborador_id uuid;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if v_status not in ('em_andamento', 'concluida', 'faturada') then
    raise exception 'Filtro de status inválido.';
  end if;

  select ue.papel into v_papel
  from a.usuario u
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = v_auth_uid and u.ativo and u.deleted_at is null
    and ue.empresa_id = v_empresa_id and ue.ativo and ue.deleted_at is null
  limit 1;
  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa.';
  end if;

  if upper(v_papel) = 'APONTADOR' and v_status <> 'em_andamento' then
    raise exception 'O perfil APONTADOR só pode consultar OS em andamento.';
  end if;

  select c.id into v_colaborador_id
  from public.colaboradores c
  where c.user_id = v_auth_uid
    and c.tenant_id = v_tenant_id
    and c.empresa_id = v_empresa_id
    and c.ativo;

  if upper(v_papel) = 'APONTAMENTO_RH' and v_colaborador_id is null then
    raise exception 'Seu usuário de apontamento não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  -- Mantém o cálculo de margem da RPC existente quando há colaborador vinculado.
  -- Para perfis administrativos sem colaborador, a alternativa abaixo evita que a
  -- leitura da OS falhe por uma vinculação que não é necessária ao papel.
  if v_colaborador_id is not null and upper(v_papel) <> 'FINANCEIRO' then
    return query
  select
    base.id,
    base.numero_os,
    base.os_num,
    base.cliente_nome,
    base.descricao_servico,
    base.status,
    os.status_fluxo,
    base.usa_relatorio_hh,
    base.total_horas,
    base.responsavel_nome,
    base.situacao_margem,
    base.sou_responsavel,
    coalesce(pendencias.quantidade, 0)::integer,
    os.garantia_motivo,
    os.faturado_em,
    os.faturada_presumida_legado,
    upper(v_papel) in ('ADMIN', 'DIRETOR', 'COORDENACAO'),
    -- Faturada exige documento emitido E saldo zero (f.fn_os_pronta_para_faturada, 05/09/2026).
    upper(v_papel) = 'FINANCEIRO' and f.fn_os_pronta_para_faturada(v_tenant_id, v_empresa_id, os.id),
    upper(v_papel) in ('COORDENACAO', 'FINANCEIRO')
      and os.status_fluxo = 'faturada'
      and not coalesce(os.faturada_presumida_legado, false)
      and os.faturado_em is not null
      and os.faturado_em >= now() - interval '6 months',
    upper(coalesce(v_papel, '')) = 'COORDENACAO'
  from public.app_listar_os(true, p_busca) as base
  join public.ordens_servico as os
    on os.id = base.id
   and os.tenant_id = v_tenant_id
   and os.empresa_id = v_empresa_id
  left join lateral (
    select count(*)::integer as quantidade
    from public.apontamentos_horas as ah
    where ah.os_id = os.id
      and ah.tenant_id = v_tenant_id
      and ah.empresa_id = v_empresa_id
      and ah.status_aprovacao = 'pendente'
  ) as pendencias on true
  where case v_status
    when 'em_andamento' then os.status_fluxo in ('em_andamento', 'em_andamento_garantia')
    when 'concluida' then os.status_fluxo in ('concluida', 'concluida_garantia')
    when 'faturada' then os.status_fluxo = 'faturada'
  end
  order by os.data_abertura desc nulls last, os.id desc;
    return;
  end if;

  return query
  select
    os.id,
    os.numero_os,
    os.os_num,
    os.cliente_nome,
    os.descricao_servico,
    os.status,
    os.status_fluxo,
    os.usa_relatorio_hh,
    coalesce(horas.total_horas, 0)::numeric,
    coalesce(nullif(perfil_responsavel.nome, ''), nullif(usuario_responsavel.nome, ''), nullif(colaborador_responsavel.nome, ''))::text,
    null::text,
    (os.responsavel_aprovacao_id is not distinct from v_auth_uid),
    coalesce(pendencias.quantidade, 0)::integer,
    os.garantia_motivo,
    os.faturado_em,
    os.faturada_presumida_legado,
    upper(v_papel) in ('ADMIN', 'DIRETOR', 'COORDENACAO'),
    -- Faturada exige documento emitido E saldo zero (f.fn_os_pronta_para_faturada, 05/09/2026).
    upper(v_papel) = 'FINANCEIRO' and f.fn_os_pronta_para_faturada(v_tenant_id, v_empresa_id, os.id),
    upper(v_papel) in ('COORDENACAO', 'FINANCEIRO')
      and os.status_fluxo = 'faturada'
      and not coalesce(os.faturada_presumida_legado, false)
      and os.faturado_em is not null
      and os.faturado_em >= now() - interval '6 months',
    upper(v_papel) = 'COORDENACAO'
  from public.ordens_servico os
  left join lateral (
    select sum(ah.horas)::numeric as total_horas
    from public.apontamentos_horas ah
    where ah.os_id = os.id and ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id
  ) horas on true
  left join lateral (
    select count(*)::integer as quantidade
    from public.apontamentos_horas ah
    where ah.os_id = os.id and ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id and ah.status_aprovacao = 'pendente'
  ) pendencias on true
  left join public.profiles perfil_responsavel on perfil_responsavel.id = os.responsavel_aprovacao_id
  left join a.usuario usuario_responsavel on usuario_responsavel.auth_user_id = os.responsavel_aprovacao_id and usuario_responsavel.ativo and usuario_responsavel.deleted_at is null
  left join public.colaboradores colaborador_responsavel on colaborador_responsavel.user_id = os.responsavel_aprovacao_id and colaborador_responsavel.tenant_id = v_tenant_id and colaborador_responsavel.empresa_id = v_empresa_id
  where os.tenant_id = v_tenant_id and os.empresa_id = v_empresa_id
    and (p_busca is null or os.numero_os ilike '%' || btrim(p_busca) || '%' or os.os_num::text ilike '%' || btrim(p_busca) || '%' or os.cliente_nome ilike '%' || btrim(p_busca) || '%')
    and case v_status
      when 'em_andamento' then os.status_fluxo in ('em_andamento', 'em_andamento_garantia')
      when 'concluida' then os.status_fluxo in ('concluida', 'concluida_garantia')
      when 'faturada' then os.status_fluxo = 'faturada'
    end
  order by os.data_abertura desc nulls last, os.id desc;
end;
$function$;
