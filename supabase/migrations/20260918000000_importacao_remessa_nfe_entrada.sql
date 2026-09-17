-- NF-e de ENTRADA de importacao por remessa expressa (courier), emitida pelo ERP pelo pipeline
-- de NF-e de sempre (solicitacao -> nfe-emitir em homologacao -> perfil liberado -> producao).
--
-- Pedido do Gabriel em 17/09/2026: a remessa UPS 1ZJ451C10441551106 (DIR 260191366846,
-- registrada em 09/09/2026, UA 0817700 Viracopos/SP) trouxe uma CPU de CLP OMRON CQM1H-CPU61
-- (US$ 45,00 + frete US$ 41,12, cambio 5,0856). Regime de tributacao simplificada (RTS,
-- regime 7): II de 60% recolhido pelo courier (R$ 262,78), ICMS por GNRE (receita 10005-6,
-- R$ 143,53), sem IPI, PIS ou COFINS. A nota de entrada e a que da a origem fiscal a mercadoria.
--
-- O que muda no pipeline:
--   - f.importacao_remessa (+ itens e anexos) guarda a DIR e tudo o que a nota precisa;
--     uma DIR so gera uma nota (indice unico entre importacoes nao canceladas);
--   - f.fn_importacao_remessa_ler_dir le e valida o XML da DIR (Siscomex Remessa, raiz xml1702);
--   - f.fn_importacao_remessa_criar calcula (vProd = valor aduaneiro; II da DIR;
--     BC ICMS = (vProd + II) / (1 - aliquota); ICMS = BC x aliquota, conferido com a GNRE;
--     vOutro = ICMS; vNF = vProd + II + vOutro) e monta a solicitacao de NF-e com os snapshots;
--   - fn_nfe_preparar_documento_solicitacao (homologacao e producao) passam a gravar a
--     operacao ENTRADA quando o snapshot diz tpNF 0, e somam o II no total do documento;
--   - a autorizacao em PRODUCAO da entrada no estoque (custo = vProd + II + despesas do
--     courier; ICMS so nos perfis sem credito, 3556/3551) e lanca a nota de debito do courier
--     como titulo AP da importacao, sem duplicar;
--   - perfis 3101/3102/3556/3551 nascem em revisao; so o usado agora sera liberado.
-- Tributacao e textos da nota no montador (supabase/functions/_shared/fiscal/importacao-remessa.ts).

-- ---------------------------------------------------------------------------
-- 1. A NF-e de importacao aponta para a importacao pela origem do item.
-- ---------------------------------------------------------------------------
alter table f.solicitacao_item drop constraint if exists solicitacao_item_origem_tipo_check;
alter table f.solicitacao_item add constraint solicitacao_item_origem_tipo_check
  check (origem_tipo = any (array['OS'::text, 'OV'::text, 'AVULSO'::text, 'CONTRATO'::text, 'RETORNO_TERCEIROS'::text, 'DEVOLUCAO_COMPRA'::text, 'IMPORTACAO'::text]));

-- ---------------------------------------------------------------------------
-- 2. Tabelas
-- ---------------------------------------------------------------------------
create table if not exists f.importacao_remessa (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  status text not null default 'RASCUNHO'
    check (status in ('RASCUNHO', 'HOMOLOGACAO', 'HOMOLOGADA', 'CONCLUIDA', 'CANCELADA')),
  -- Remessa e DIR (do XML do Siscomex Remessa)
  awb text not null,
  master text,
  dir_numero text not null check (dir_numero ~ '^[0-9]{6,20}$'),
  dir_lote text,
  dir_data_registro timestamptz not null,
  dir_situacao text not null,
  manifesto_numero text,
  manifesto_data timestamptz,
  ua_entrada text not null,
  pais_origem_codigo text,
  destinatario_documento text not null,
  remetente_dir_nome text,
  remetente_dir_endereco text,
  remetente_dir_pais_codigo text,
  regime_tributacao text,
  moeda text,
  volumes integer,
  peso numeric(12,3),
  -- Desembaraco (para o grupo DI)
  local_desembaraco text not null,
  uf_desembaraco text not null check (uf_desembaraco ~ '^[A-Z]{2}$'),
  data_desembaraco date not null,
  via_transporte smallint not null default 4 check (via_transporte between 1 and 13),
  forma_intermedio smallint not null default 1 check (forma_intermedio in (1, 2, 3)),
  -- Valores
  cambio numeric(12,6) not null check (cambio > 0),
  valor_mercadoria_usd numeric(15,2) not null,
  frete_usd numeric(15,2) not null default 0,
  frete_modo text,
  valor_mercadoria_brl numeric(15,2) not null,
  frete_brl numeric(15,2) not null default 0,
  valor_aduaneiro_brl numeric(15,2) not null check (valor_aduaneiro_brl > 0),
  ii_valor numeric(15,2) not null check (ii_valor >= 0),
  ii_pendente numeric(15,2) not null default 0,
  aliquota_icms numeric(5,2) not null check (aliquota_icms >= 0 and aliquota_icms < 100),
  bc_icms numeric(15,2) not null,
  icms_valor numeric(15,2) not null,
  valor_nota numeric(15,2) not null,
  -- GNRE do ICMS
  gnre_numero text,
  gnre_receita text,
  gnre_uf text,
  gnre_valor numeric(15,2) not null,
  -- Courier: despesas e nota de debito
  courier_nome text,
  courier_cnpj text,
  courier_servicos numeric(15,2) not null default 0,
  courier_armazenagem numeric(15,2) not null default 0,
  nota_debito_numero text,
  nota_debito_valor numeric(15,2),
  nota_debito_emissao date,
  nota_debito_pago_em date,
  nota_debito_conta_bancaria_id uuid,
  nota_debito_forma_pagamento text,
  nota_debito_motivo_compra_id uuid,
  nota_debito_titulo_id uuid,
  -- Exportador (destinatario da nota de entrada, no exterior)
  exportador_nome text not null,
  exportador_logradouro text not null,
  exportador_numero text not null default 'S/N',
  exportador_complemento text,
  exportador_bairro text not null default 'EXTERIOR',
  exportador_pais_codigo text not null default '1600',
  exportador_pais_nome text not null default 'CHINA',
  exportador_codigo text not null,
  exportador_id_estrangeiro text,
  -- Nota
  natureza_operacao text not null,
  cfop text not null check (cfop ~ '^3[0-9]{3}$'),
  consumidor_final smallint not null default 0 check (consumidor_final in (0, 1)),
  credito_icms boolean not null default true,
  perfil_operacao_id uuid,
  solicitacao_id uuid,
  documento_fiscal_id uuid,
  chave_nfe text check (chave_nfe is null or chave_nfe ~ '^[0-9]{44}$'),
  nfe_numero integer,
  nfe_serie integer,
  nfe_autorizada_em timestamptz,
  xml_dir text not null,
  observacao text,
  dados_json jsonb not null default '{}'::jsonb,
  criado_por uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
comment on table f.importacao_remessa is 'Importacao por remessa expressa (courier): DIR do Siscomex Remessa e a NF-e de entrada emitida pelo ERP.';
create unique index if not exists importacao_remessa_dir_ativa_uq
  on f.importacao_remessa (tenant_id, empresa_id, dir_numero)
  where deleted_at is null and status <> 'CANCELADA';
create index if not exists importacao_remessa_empresa_idx on f.importacao_remessa (tenant_id, empresa_id, created_at desc);
create index if not exists importacao_remessa_solicitacao_idx on f.importacao_remessa (solicitacao_id) where solicitacao_id is not null;

create table if not exists f.importacao_remessa_item (
  id uuid primary key default gen_random_uuid(),
  importacao_id uuid not null references f.importacao_remessa (id) on delete cascade,
  tenant_id uuid not null,
  empresa_id uuid not null,
  ordem smallint not null check (ordem > 0),
  sequencia_dir text,
  item_id integer,
  codigo text not null,
  descricao text not null,
  ncm text not null check (ncm ~ '^[0-9]{8}$'),
  unidade text not null,
  quantidade numeric(15,4) not null check (quantidade > 0),
  peso numeric(12,3),
  fabricante text not null,
  valor_usd numeric(15,2) not null check (valor_usd >= 0),
  valor_mercadoria_brl numeric(15,2) not null,
  frete_brl numeric(15,2) not null default 0,
  valor_aduaneiro_brl numeric(15,2) not null check (valor_aduaneiro_brl > 0),
  valor_unitario_brl numeric(21,10) not null check (valor_unitario_brl > 0),
  ii_valor numeric(15,2) not null,
  bc_icms numeric(15,2) not null,
  icms_valor numeric(15,2) not null,
  courier_rateado numeric(15,2) not null default 0,
  custo_total numeric(15,2),
  custo_unitario numeric(21,6),
  created_at timestamptz not null default now(),
  unique (importacao_id, ordem)
);
create index if not exists importacao_remessa_item_imp_idx on f.importacao_remessa_item (importacao_id);

create table if not exists f.importacao_remessa_anexo (
  id uuid primary key default gen_random_uuid(),
  importacao_id uuid not null references f.importacao_remessa (id) on delete cascade,
  tenant_id uuid not null,
  empresa_id uuid not null,
  tipo text not null check (tipo in ('DIR_XML', 'GNRE', 'NOTA_DEBITO', 'INVOICE', 'DANFE', 'XML_NFE', 'OUTRO')),
  nome_arquivo text not null,
  storage_path text not null,
  content_type text,
  tamanho_bytes bigint,
  criado_por uuid,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists importacao_remessa_anexo_imp_idx on f.importacao_remessa_anexo (importacao_id);

-- RLS no padrao das operacoes fiscais: tenant + empresa ativos e acesso financeiro. Leitura pela
-- tela; escrita so pelas RPCs (security definer) e pelo gatilho.
alter table f.importacao_remessa enable row level security;
alter table f.importacao_remessa_item enable row level security;
alter table f.importacao_remessa_anexo enable row level security;
drop policy if exists importacao_remessa_select on f.importacao_remessa;
create policy importacao_remessa_select on f.importacao_remessa for select to authenticated
  using (tenant_id = (select public.current_tenant_id()) and empresa_id = (select public.current_empresa_id()) and (select f.has_finance_access()));
drop policy if exists importacao_remessa_item_select on f.importacao_remessa_item;
create policy importacao_remessa_item_select on f.importacao_remessa_item for select to authenticated
  using (tenant_id = (select public.current_tenant_id()) and empresa_id = (select public.current_empresa_id()) and (select f.has_finance_access()));
drop policy if exists importacao_remessa_anexo_select on f.importacao_remessa_anexo;
create policy importacao_remessa_anexo_select on f.importacao_remessa_anexo for select to authenticated
  using (tenant_id = (select public.current_tenant_id()) and empresa_id = (select public.current_empresa_id()) and (select f.has_finance_access()));
grant select on f.importacao_remessa, f.importacao_remessa_item, f.importacao_remessa_anexo to authenticated;
grant all on f.importacao_remessa, f.importacao_remessa_item, f.importacao_remessa_anexo to service_role;

-- ---------------------------------------------------------------------------
-- 3. Unidade da RFB (uaEntrada da DIR) -> local e UF do desembaraco (grupo DI).
--    Tabela minima, com as unidades por onde a Segau recebe courier; a tela deixa editar.
-- ---------------------------------------------------------------------------
create or replace function f.fn_importacao_ua_local(p_ua text)
returns table (ua text, local_desembaraco text, uf text)
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select lpad(regexp_replace(coalesce(p_ua, ''), '[^0-9]', '', 'g'), 7, '0') as ua,
         case lpad(regexp_replace(coalesce(p_ua, ''), '[^0-9]', '', 'g'), 7, '0')
           when '0817700' then 'AEROPORTO INTERNACIONAL DE VIRACOPOS - CAMPINAS'
           when '0817600' then 'AEROPORTO INTERNACIONAL DE SAO PAULO - GUARULHOS'
           when '0717600' then 'AEROPORTO INTERNACIONAL DO RIO DE JANEIRO - GALEAO'
           else null
         end as local_desembaraco,
         case lpad(regexp_replace(coalesce(p_ua, ''), '[^0-9]', '', 'g'), 7, '0')
           when '0817700' then 'SP'
           when '0817600' then 'SP'
           when '0717600' then 'RJ'
           else null
         end as uf;
$$;

-- Valor em reais como o Brasil escreve (1.234,56), para mensagens e textos da nota.
create or replace function f.fn_importacao_brl(p_valor numeric)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select replace(replace(replace(to_char(coalesce(p_valor, 0), 'FM999G999G999G990D00'), ',', '#'), '.', ','), '#', '.');
$$;

-- ---------------------------------------------------------------------------
-- 4. Ler e validar o XML da DIR (Siscomex Remessa v1, raiz xml1702)
-- ---------------------------------------------------------------------------
create or replace function f.fn_importacao_remessa_ler_dir(p_xml text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_doc xml;
  v_r record;
  v_remessas integer;
  v_itens jsonb;
  v_cnpj_empresa text;
  v_cnpj_dir text;
  v_bloqueios text[] := '{}';
  v_em_uso record;
  v_ua record;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if nullif(btrim(coalesce(p_xml, '')), '') is null then
    raise exception using errcode = '22023', message = 'Envie o XML da DIR (Siscomex Remessa).';
  end if;
  begin
    v_doc := xmlparse(document p_xml);
  exception when others then
    raise exception using errcode = '22023', message = 'O arquivo nao e um XML valido: ' || sqlerrm;
  end;

  select count(*) into v_remessas
  from xmltable(
    xmlnamespaces('http://www.siscomex.gov.br/remessa/v1' as s),
    '/s:xml1702/s:manifestos/s:manifesto/s:remessas/s:remessa' passing v_doc columns numero text path 's:numero'
  );
  if v_remessas = 0 then
    raise exception using errcode = '22023',
      message = 'O XML nao e uma DIR do Siscomex Remessa (raiz xml1702, namespace http://www.siscomex.gov.br/remessa/v1) ou nao traz remessa.';
  end if;
  if v_remessas > 1 then
    raise exception using errcode = '22023', message = format('O XML traz %s remessas; envie a DIR de uma remessa so.', v_remessas);
  end if;

  select x.* into v_r
  from xmltable(
    xmlnamespaces('http://www.siscomex.gov.br/remessa/v1' as s),
    '/s:xml1702/s:manifestos/s:manifesto' passing v_doc columns
      manifesto_numero text path 's:numero',
      manifesto_data text path 's:dataHoraManifesto',
      ua_entrada text path 's:uaEntrada',
      pais_origem text path 's:paisOrigem',
      courier_nome text path 's:nomeEmpresa',
      courier_cnpj text path 's:cnpj',
      awb text path 's:remessas/s:remessa/s:numero',
      master text path 's:remessas/s:remessa/s:master',
      destinacao_comercial text path 's:remessas/s:remessa/s:destinacaoComercial',
      volumes text path 's:remessas/s:remessa/s:volumes',
      peso text path 's:remessas/s:remessa/s:peso',
      descricao text path 's:remessas/s:remessa/s:descricao',
      valor_usd text path 's:remessas/s:remessa/s:valorRemessaDolar',
      valor_brl text path 's:remessas/s:remessa/s:valorRemessaReal',
      frete_usd text path 's:remessas/s:remessa/s:freteDolar',
      frete_brl text path 's:remessas/s:remessa/s:freteReal',
      frete_modo text path 's:remessas/s:remessa/s:freteModoPagto',
      tributavel_usd text path 's:remessas/s:remessa/s:valorTributavelDolar',
      tributavel_brl text path 's:remessas/s:remessa/s:valorTributavelReal',
      ii_real text path 's:remessas/s:remessa/s:valorIIReal',
      multas text path 's:remessas/s:remessa/s:valorMultasReal',
      situacao text path 's:remessas/s:remessa/s:situacao',
      cambio text path 's:remessas/s:remessa/s:txCambioDtRegistro',
      dir_numero text path 's:remessas/s:remessa/s:dir/s:numero',
      dir_lote text path 's:remessas/s:remessa/s:dir/s:numeroLote',
      dir_data_registro text path 's:remessas/s:remessa/s:dir/s:dataRegistro',
      dir_versao text path 's:remessas/s:remessa/s:dir/s:versaoDIR',
      dest_documento text path 's:remessas/s:remessa/s:destinatario/s:documento',
      dest_tipo_documento text path 's:remessas/s:remessa/s:destinatario/s:tipoDocumento',
      dest_nome text path 's:remessas/s:remessa/s:destinatario/s:nome',
      dest_logradouro text path 's:remessas/s:remessa/s:destinatario/s:endereco/s:logradouro',
      dest_cep text path 's:remessas/s:remessa/s:destinatario/s:endereco/s:cep',
      dest_estado text path 's:remessas/s:remessa/s:destinatario/s:endereco/s:estado',
      rem_nome text path 's:remessas/s:remessa/s:remetente/s:nome',
      rem_logradouro text path 's:remessas/s:remessa/s:remetente/s:endereco/s:logradouro',
      rem_complemento text path 's:remessas/s:remessa/s:remetente/s:endereco/s:complemento',
      rem_estado text path 's:remessas/s:remessa/s:remetente/s:endereco/s:estado',
      rem_pais text path 's:remessas/s:remessa/s:remetente/s:endereco/s:pais',
      ii_devido text path 's:remessas/s:remessa/s:ii/s:valorDevido',
      ii_pendente text path 's:remessas/s:remessa/s:ii/s:valorPendente',
      ii_recolhido text path 's:remessas/s:remessa/s:ii/s:valorRecolhido'
  ) x;

  select jsonb_agg(jsonb_build_object(
           'sequencia', m.sequencia, 'regime_tributacao', m.regime, 'valor_usd', nullif(m.valor, '')::numeric,
           'moeda', m.moeda, 'unidade_siscomex', m.unidade, 'quantidade', nullif(m.quantidade, '')::numeric,
           'peso', nullif(m.peso, '')::numeric, 'descricao', btrim(regexp_replace(coalesce(m.descricao, ''), '\s+', ' ', 'g'))
         ) order by m.sequencia)
    into v_itens
  from xmltable(
    xmlnamespaces('http://www.siscomex.gov.br/remessa/v1' as s),
    '/s:xml1702/s:manifestos/s:manifesto/s:remessas/s:remessa/s:mercadorias/s:mercadoria' passing v_doc columns
      sequencia text path 's:sequencia', regime text path 's:regimeTributacao', valor text path 's:valor',
      moeda text path 's:moeda', unidade text path 's:unidade', quantidade text path 's:quantidade',
      peso text path 's:peso', descricao text path 's:descricao'
  ) m;

  select regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') into v_cnpj_empresa
  from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id and e.deleted_at is null;
  v_cnpj_dir := regexp_replace(coalesce(v_r.dest_documento, ''), '[^0-9]', '', 'g');

  -- Bloqueios: todos de uma vez, para a tela mostrar o que falta.
  if nullif(v_r.dir_numero, '') is null then
    v_bloqueios := v_bloqueios || 'A DIR nao traz o numero (dir/numero).';
  end if;
  if v_cnpj_dir <> coalesce(v_cnpj_empresa, '') then
    v_bloqueios := v_bloqueios || format('O destinatario da DIR (CNPJ %s) nao e a empresa emitente (CNPJ %s).', coalesce(nullif(v_cnpj_dir, ''), '?'), coalesce(v_cnpj_empresa, '?'));
  end if;
  if coalesce(v_r.situacao, '') <> '25' then
    v_bloqueios := v_bloqueios || format('A remessa esta na situacao %s; so a situacao 25 (desembaracada) pode gerar a nota de entrada.', coalesce(nullif(v_r.situacao, ''), '?'));
  end if;
  if coalesce(nullif(v_r.ii_pendente, '')::numeric, 0) <> 0 then
    v_bloqueios := v_bloqueios || format('Ha II pendente de R$ %s na DIR; a nota so sai com o imposto recolhido.', f.fn_importacao_brl(nullif(v_r.ii_pendente, '')::numeric));
  end if;
  if v_itens is null then
    v_bloqueios := v_bloqueios || 'A DIR nao traz mercadorias.';
  end if;
  if coalesce(nullif(v_r.tributavel_brl, '')::numeric, 0) <= 0 then
    v_bloqueios := v_bloqueios || 'A DIR nao traz o valor tributavel em reais (valor aduaneiro).';
  end if;

  select i.id, i.status, i.chave_nfe, i.nfe_numero, i.nfe_serie, i.created_at
    into v_em_uso
  from f.importacao_remessa i
  where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id
    and i.dir_numero = v_r.dir_numero and i.deleted_at is null and i.status <> 'CANCELADA'
  order by i.created_at desc limit 1;

  select * into v_ua from f.fn_importacao_ua_local(v_r.ua_entrada);

  return jsonb_build_object(
    'awb', v_r.awb,
    'master', v_r.master,
    'dir', jsonb_build_object(
      'numero', v_r.dir_numero, 'lote', v_r.dir_lote, 'data_registro', v_r.dir_data_registro, 'versao', v_r.dir_versao,
      'situacao', v_r.situacao, 'ua_entrada', v_ua.ua, 'local_desembaraco', v_ua.local_desembaraco, 'uf_desembaraco', v_ua.uf,
      'data_desembaraco', left(v_r.dir_data_registro, 10)
    ),
    'manifesto', jsonb_build_object('numero', v_r.manifesto_numero, 'data', v_r.manifesto_data, 'pais_origem', v_r.pais_origem),
    'courier', jsonb_build_object('nome', v_r.courier_nome, 'cnpj', v_r.courier_cnpj),
    'remessa', jsonb_build_object(
      'destinacao_comercial', v_r.destinacao_comercial, 'volumes', nullif(v_r.volumes, '')::integer, 'peso', nullif(v_r.peso, '')::numeric,
      'descricao', btrim(regexp_replace(coalesce(v_r.descricao, ''), '\s+', ' ', 'g')),
      'valor_usd', nullif(v_r.valor_usd, '')::numeric, 'valor_brl', nullif(v_r.valor_brl, '')::numeric,
      'frete_usd', nullif(v_r.frete_usd, '')::numeric, 'frete_brl', nullif(v_r.frete_brl, '')::numeric, 'frete_modo', v_r.frete_modo,
      'tributavel_usd', nullif(v_r.tributavel_usd, '')::numeric, 'tributavel_brl', nullif(v_r.tributavel_brl, '')::numeric,
      'multas_brl', nullif(v_r.multas, '')::numeric, 'cambio', nullif(v_r.cambio, '')::numeric
    ),
    'ii', jsonb_build_object('valor', nullif(v_r.ii_real, '')::numeric, 'devido', nullif(v_r.ii_devido, '')::numeric,
                             'pendente', nullif(v_r.ii_pendente, '')::numeric, 'recolhido', nullif(v_r.ii_recolhido, '')::numeric),
    'destinatario', jsonb_build_object('documento', v_cnpj_dir, 'nome', v_r.dest_nome, 'logradouro', v_r.dest_logradouro, 'cep', v_r.dest_cep, 'uf', v_r.dest_estado),
    'remetente', jsonb_build_object('nome', v_r.rem_nome, 'logradouro', v_r.rem_logradouro, 'complemento', v_r.rem_complemento, 'uf', v_r.rem_estado, 'pais_codigo', v_r.rem_pais),
    'itens', coalesce(v_itens, '[]'::jsonb),
    'bloqueios', to_jsonb(v_bloqueios),
    'em_uso', case when v_em_uso.id is not null then jsonb_build_object(
      'importacao_id', v_em_uso.id, 'status', v_em_uso.status, 'chave_nfe', v_em_uso.chave_nfe,
      'nfe_numero', v_em_uso.nfe_numero, 'nfe_serie', v_em_uso.nfe_serie, 'created_at', v_em_uso.created_at) end
  );
end;
$$;
revoke all on function f.fn_importacao_remessa_ler_dir(text) from public, anon;
grant execute on function f.fn_importacao_remessa_ler_dir(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Cancelar uma importacao sem nota real (rascunho ou homologacao), pelo fluxo auditado.
-- ---------------------------------------------------------------------------
create or replace function f.fn_importacao_remessa_cancelar(p_importacao_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_imp f.importacao_remessa%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if char_length(v_motivo) < 15 or char_length(v_motivo) > 255 then
    raise exception using errcode = '22023', message = 'O motivo deve ter entre 15 e 255 caracteres.';
  end if;
  select * into v_imp from f.importacao_remessa i
   where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id and i.id = p_importacao_id and i.deleted_at is null
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Importacao nao encontrada.';
  end if;
  if v_imp.status = 'CANCELADA' then
    return jsonb_build_object('ok', true, 'idempotente', true, 'importacao_id', v_imp.id);
  end if;
  if v_imp.status = 'CONCLUIDA' or exists (
    select 1 from f.documento_fiscal_emissao e
     where e.solicitacao_id = v_imp.solicitacao_id and e.ambiente = 'PRODUCAO' and e.status not in ('REJEITADA', 'ERRO', 'CANCELADA')
  ) then
    raise exception using errcode = '55000',
      message = 'A importacao ja tem NF-e real; cancele a nota pelo ciclo de vida (Faturamento > NF-e) e a importacao acompanha.';
  end if;
  if v_imp.solicitacao_id is not null
     and exists (select 1 from f.solicitacao_faturamento sf where sf.id = v_imp.solicitacao_id and sf.status not in ('EMITIDA', 'CANCELADA')) then
    if exists (select 1 from f.documento_fiscal_emissao e where e.solicitacao_id = v_imp.solicitacao_id and e.ambiente = 'HOMOLOGACAO' and e.status <> 'CANCELADA') then
      perform f.fn_solicitacao_nfe_abandonar_homologacao(v_imp.solicitacao_id, v_motivo);
    else
      perform f.fn_solicitacao_nfe_cancelar_rascunho(v_imp.solicitacao_id, v_motivo);
    end if;
  end if;
  update f.importacao_remessa
     set status = 'CANCELADA',
         dados_json = dados_json || jsonb_build_object('cancelamento', jsonb_build_object('motivo', v_motivo, 'em', now(), 'por', v_scope.usuario_id)),
         updated_at = now()
   where id = v_imp.id;
  return jsonb_build_object('ok', true, 'importacao_id', v_imp.id, 'status', 'CANCELADA');
end;
$$;
revoke all on function f.fn_importacao_remessa_cancelar(uuid, text) from public, anon;
grant execute on function f.fn_importacao_remessa_cancelar(uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. Criar a importacao e a solicitacao de NF-e de entrada
-- ---------------------------------------------------------------------------
create or replace function f.fn_importacao_remessa_criar(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_dir jsonb;
  v_bloqueios text[];
  v_em_uso jsonb;
  v_substituir boolean := coalesce((p_dados->>'substituir')::boolean, false);
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_uf_emitente text;
  v_cfop text := regexp_replace(coalesce(p_dados->>'cfop', ''), '[^0-9]', '', 'g');
  v_natureza text;
  v_consumidor_final smallint;
  v_credito_icms boolean;
  v_aliquota numeric(5,2);
  v_cambio numeric(12,6);
  v_valor_usd numeric(15,2);
  v_frete_usd numeric(15,2);
  v_valor_brl numeric(15,2);
  v_frete_brl numeric(15,2);
  v_aduaneiro numeric(15,2);
  v_ii numeric(15,2);
  v_bc numeric(15,2);
  v_icms numeric(15,2);
  v_nota numeric(15,2);
  v_gnre_valor numeric(15,2);
  v_courier_servicos numeric(15,2) := coalesce(nullif(p_dados->'courier'->>'servicos', '')::numeric, 0);
  v_courier_armazenagem numeric(15,2) := coalesce(nullif(p_dados->'courier'->>'armazenagem', '')::numeric, 0);
  v_nd jsonb := coalesce(p_dados->'nota_debito', '{}'::jsonb);
  v_exp jsonb := coalesce(p_dados->'exportador', '{}'::jsonb);
  v_itens_req jsonb := p_dados->'itens';
  v_itens_dir jsonb;
  v_n integer;
  v_i integer;
  v_soma_usd numeric(15,2);
  v_acum_merc numeric(15,2) := 0;
  v_acum_frete numeric(15,2) := 0;
  v_acum_adu numeric(15,2) := 0;
  v_acum_ii numeric(15,2) := 0;
  v_acum_bc numeric(15,2) := 0;
  v_acum_icms numeric(15,2) := 0;
  v_acum_courier numeric(15,2) := 0;
  v_req jsonb;
  v_dir_item jsonb;
  v_item_merc numeric(15,2);
  v_item_frete numeric(15,2);
  v_item_adu numeric(15,2);
  v_item_ii numeric(15,2);
  v_item_bc numeric(15,2);
  v_item_icms numeric(15,2);
  v_item_courier numeric(15,2);
  v_item_qtd numeric(15,4);
  v_item_ncm text;
  v_item_id integer;
  v_item_codigo text;
  v_item_desc text;
  v_item_un text;
  v_item_fab text;
  v_imp_id uuid := gen_random_uuid();
  v_sol_id uuid := gen_random_uuid();
  v_perfil_id uuid;
  v_perfil_codigo text;
  v_local text;
  v_uf_desemb text;
  v_data_desemb date;
  v_via smallint := coalesce(nullif(p_dados->>'via_transporte', '')::smallint, 4);
  v_intermedio smallint := coalesce(nullif(p_dados->>'forma_intermedio', '')::smallint, 1);
  v_exp_codigo text;
  v_itens_snapshot jsonb := '[]'::jsonb;
  v_item_row f.importacao_remessa_item%rowtype;
  v_data_registro_txt text;
  v_dir_numero text;
  v_awb text;
  v_conta uuid;
  v_forma text;
  v_motivo_compra uuid;
  v_nd_valor numeric(15,2);
  v_texto_fisco text;
  v_texto_cpl text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  -- 6.1 DIR lida e validada de novo aqui: a tela nunca e a unica barreira.
  v_dir := f.fn_importacao_remessa_ler_dir(p_dados->>'xml');
  select coalesce(array_agg(b), '{}') into v_bloqueios from jsonb_array_elements_text(v_dir->'bloqueios') b;
  if cardinality(v_bloqueios) > 0 then
    raise exception using errcode = '22023', message = 'DIR bloqueada: ' || array_to_string(v_bloqueios, ' ');
  end if;
  v_em_uso := v_dir->'em_uso';
  v_dir_numero := v_dir->'dir'->>'numero';
  v_awb := v_dir->>'awb';
  if v_em_uso is not null and jsonb_typeof(v_em_uso) = 'object' then
    if not v_substituir then
      raise exception using errcode = '23505',
        message = format('A DIR %s ja esta em uso na importacao %s (status %s%s). Uma DIR so gera uma nota; cancele a anterior ou peca para gerar de novo.',
          v_dir_numero, v_em_uso->>'importacao_id', v_em_uso->>'status',
          case when v_em_uso->>'nfe_numero' is not null then format(', NF-e %s/%s', v_em_uso->>'nfe_serie', v_em_uso->>'nfe_numero') else '' end);
    end if;
    -- Gerar de novo: so sem nota real; fn_importacao_remessa_cancelar decide.
    perform f.fn_importacao_remessa_cancelar((v_em_uso->>'importacao_id')::uuid, 'Importacao gerada de novo pela tela de operacoes');
  end if;

  -- 6.2 Emitente (cadastro fiscal congelado no snapshot, como nas outras operacoes).
  select * into v_empresa from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id and e.deleted_at is null;
  select * into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  select * into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
  if v_endereco.id is null or v_fiscal.id is null then
    raise exception using errcode = '22023', message = 'Cadastro fiscal do emitente incompleto (endereco ou dados fiscais).';
  end if;
  v_uf_emitente := upper(v_endereco.uf::text);

  -- 6.3 CFOP -> natureza. Os perfis de importacao sao 3101/3102/3556/3551.
  v_natureza := case v_cfop
    when '3101' then 'IMPORTACAO_INDUSTRIALIZACAO'
    when '3102' then 'IMPORTACAO_COMERCIALIZACAO'
    when '3556' then 'IMPORTACAO_CONSUMO'
    when '3551' then 'IMPORTACAO_ATIVO'
  end;
  if v_natureza is null then
    raise exception using errcode = '22023', message = format('CFOP %s nao vale para a importacao. Use 3101 (industrializacao), 3102 (revenda), 3556 (uso e consumo) ou 3551 (ativo imobilizado).', coalesce(nullif(v_cfop, ''), '?'));
  end if;
  v_consumidor_final := case when v_cfop in ('3556', '3551') then 1 else 0 end;
  v_credito_icms := v_cfop in ('3101', '3102');

  -- 6.4 Valores da DIR e da tela.
  v_cambio := (v_dir->'remessa'->>'cambio')::numeric;
  v_valor_usd := coalesce((v_dir->'remessa'->>'valor_usd')::numeric, 0);
  v_frete_usd := coalesce((v_dir->'remessa'->>'frete_usd')::numeric, 0);
  v_valor_brl := coalesce((v_dir->'remessa'->>'valor_brl')::numeric, 0);
  v_frete_brl := coalesce((v_dir->'remessa'->>'frete_brl')::numeric, 0);
  v_aduaneiro := (v_dir->'remessa'->>'tributavel_brl')::numeric;
  v_ii := coalesce((v_dir->'ii'->>'valor')::numeric, 0);
  if v_cambio is null or v_cambio <= 0 then
    raise exception using errcode = '22023', message = 'A DIR nao traz a taxa de cambio da data de registro.';
  end if;
  if abs((v_valor_brl + v_frete_brl) - v_aduaneiro) > 0.05 then
    raise exception using errcode = '22023',
      message = format('Na DIR, mercadoria (R$ %s) + frete (R$ %s) nao fecham com o valor tributavel (R$ %s).', v_valor_brl, v_frete_brl, v_aduaneiro);
  end if;
  if (v_dir->'ii'->>'devido') is not null and abs((v_dir->'ii'->>'devido')::numeric - v_ii) > 0.005 then
    raise exception using errcode = '22023', message = format('II devido (R$ %s) difere do II informado na remessa (R$ %s).', v_dir->'ii'->>'devido', v_ii);
  end if;
  v_aliquota := nullif(p_dados->>'aliquota_icms', '')::numeric;
  if v_aliquota is null or v_aliquota < 0 or v_aliquota >= 100 then
    raise exception using errcode = '22023', message = 'Informe a aliquota do ICMS da importacao (ex.: 17).';
  end if;
  v_gnre_valor := nullif(p_dados->'gnre'->>'valor', '')::numeric;
  if v_gnre_valor is null then
    raise exception using errcode = '22023', message = 'Informe o valor da GNRE paga (ICMS da importacao).';
  end if;
  -- ICMS "por dentro": BC = (vProd + II) / (1 - aliquota); ICMS = BC x aliquota (LC 87/96, art. 13, V e par. 1o).
  v_bc := round((v_aduaneiro + v_ii) / (1 - v_aliquota / 100), 2);
  v_icms := round(v_bc * v_aliquota / 100, 2);
  if abs(v_icms - v_gnre_valor) > 0.05 then
    raise exception using errcode = '22023',
      message = format('ICMS calculado R$ %s (BC R$ %s a %s%%) difere da GNRE R$ %s em R$ %s. Confira a aliquota ou o valor da GNRE antes de gerar a nota.',
        f.fn_importacao_brl(v_icms), f.fn_importacao_brl(v_bc), f.fn_importacao_brl(v_aliquota),
        f.fn_importacao_brl(v_gnre_valor), f.fn_importacao_brl(abs(v_icms - v_gnre_valor)));
  end if;
  v_nota := round(v_aduaneiro + v_ii + v_icms, 2);
  if v_courier_servicos < 0 or v_courier_armazenagem < 0 then
    raise exception using errcode = '22023', message = 'Despesas do courier nao podem ser negativas.';
  end if;

  -- 6.5 Desembaraco: da UA quando conhecida; a tela pode informar.
  v_local := upper(nullif(btrim(coalesce(p_dados->>'local_desembaraco', v_dir->'dir'->>'local_desembaraco', '')), ''));
  v_uf_desemb := upper(nullif(btrim(coalesce(p_dados->>'uf_desembaraco', v_dir->'dir'->>'uf_desembaraco', '')), ''));
  v_data_desemb := coalesce(nullif(p_dados->>'data_desembaraco', '')::date, (v_dir->'dir'->>'data_desembaraco')::date);
  if v_local is null or v_uf_desemb !~ '^[A-Z]{2}$' or v_data_desemb is null then
    raise exception using errcode = '22023', message = format('Informe o local, a UF e a data do desembaraco (UA de entrada %s nao consta na tabela).', v_dir->'dir'->>'ua_entrada');
  end if;
  if v_via not between 1 and 13 then
    raise exception using errcode = '22023', message = 'Via de transporte fora da tabela tpViaTransp (1 a 13).';
  end if;
  if v_intermedio not in (1, 2, 3) then
    raise exception using errcode = '22023', message = 'Forma de intermediacao deve ser 1 (conta propria), 2 (conta e ordem) ou 3 (encomenda).';
  end if;

  -- 6.6 Exportador: destinatario da nota de entrada, no exterior.
  if nullif(btrim(coalesce(v_exp->>'nome', '')), '') is null or nullif(btrim(coalesce(v_exp->>'logradouro', '')), '') is null then
    raise exception using errcode = '22023', message = 'Informe o nome e o endereco do exportador (conforme a invoice).';
  end if;
  if coalesce(v_exp->>'pais_codigo', '') !~ '^[0-9]{2,4}$' or nullif(btrim(coalesce(v_exp->>'pais_nome', '')), '') is null then
    raise exception using errcode = '22023', message = 'Informe o pais do exportador (codigo BACEN e nome).';
  end if;
  if v_exp->>'pais_codigo' = '1058' then
    raise exception using errcode = '22023', message = 'O exportador nao pode estar no Brasil (pais 1058).';
  end if;
  v_exp_codigo := left(upper(nullif(btrim(coalesce(v_exp->>'codigo', '')), '')), 60);
  if v_exp_codigo is null then
    v_exp_codigo := left(regexp_replace(upper(v_exp->>'nome'), '[^A-Z0-9]+', '-', 'g'), 60);
  end if;
  if v_exp->>'id_estrangeiro' is not null and (char_length(btrim(v_exp->>'id_estrangeiro')) < 5 or char_length(btrim(v_exp->>'id_estrangeiro')) > 20) then
    raise exception using errcode = '22023', message = 'A identificacao do exportador (idEstrangeiro) deve ter de 5 a 20 caracteres.';
  end if;

  -- 6.7 Itens: um por mercadoria da DIR, com NCM, item do catalogo e fabricante da tela.
  v_itens_dir := v_dir->'itens';
  v_n := jsonb_array_length(v_itens_dir);
  if jsonb_typeof(v_itens_req) <> 'array' or jsonb_array_length(v_itens_req) <> v_n then
    raise exception using errcode = '22023', message = format('Informe os dados de cada uma das %s mercadorias da DIR.', v_n);
  end if;
  select sum((e->>'valor_usd')::numeric) into v_soma_usd from jsonb_array_elements(v_itens_dir) e;
  if coalesce(v_soma_usd, 0) <= 0 then
    raise exception using errcode = '22023', message = 'As mercadorias da DIR nao tem valor.';
  end if;

  -- 6.8 Nota de debito do courier (despesa da importacao).
  v_nd_valor := nullif(v_nd->>'valor', '')::numeric;
  if nullif(btrim(coalesce(v_nd->>'numero', '')), '') is not null and (v_nd_valor is null or v_nd_valor <= 0) then
    raise exception using errcode = '22023', message = 'Informe o valor da nota de debito do courier.';
  end if;
  v_conta := nullif(v_nd->>'conta_bancaria_id', '')::uuid;
  v_forma := nullif(upper(btrim(coalesce(v_nd->>'forma_pagamento', ''))), '');
  if v_forma is not null and v_forma not in ('PIX', 'BOLETO', 'TRANSFERENCIA', 'DINHEIRO', 'CARTAO', 'OUTROS') then
    raise exception using errcode = '22023', message = 'Forma de pagamento da nota de debito invalida (PIX, BOLETO, TRANSFERENCIA, DINHEIRO, CARTAO ou OUTROS).';
  end if;
  if v_conta is not null and not exists (
    select 1 from f.conta_bancaria cb where cb.id = v_conta and cb.tenant_id = v_scope.tenant_id and cb.empresa_id = v_scope.empresa_id and cb.deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Conta bancaria da nota de debito nao encontrada.';
  end if;
  v_motivo_compra := nullif(v_nd->>'motivo_compra_id', '')::uuid;
  if v_motivo_compra is null then
    select mc.id into v_motivo_compra from f.motivo_compra mc
     where mc.tenant_id = v_scope.tenant_id and mc.deleted_at is null and mc.ativo and mc.codigo = 'ESTOQUE'
     order by mc.favorito desc, mc.ordem limit 1;
  end if;

  -- 6.9 Perfil de operacao (so importa para os portoes de producao): natureza + CFOP + UF EX.
  select po.id, po.codigo into v_perfil_id, v_perfil_codigo
  from f.perfil_operacao po
  where po.tenant_id = v_scope.tenant_id and (po.empresa_id = v_scope.empresa_id or po.empresa_id is null)
    and po.modelo = 'NFE' and po.natureza_operacao = v_natureza and po.cfop_externo = v_cfop
    and po.faixa_automacao <> 'BLOQUEADO' and po.vigencia_inicio <= current_date and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
  order by po.habilitado_producao desc, po.revisao_fiscal_em desc nulls last
  limit 1;

  v_data_registro_txt := to_char(((v_dir->'dir'->>'data_registro')::timestamp), 'DD/MM/YYYY');

  -- 6.10 Importacao.
  insert into f.importacao_remessa (
    id, tenant_id, empresa_id, status, awb, master, dir_numero, dir_lote, dir_data_registro, dir_situacao,
    manifesto_numero, manifesto_data, ua_entrada, pais_origem_codigo, destinatario_documento,
    remetente_dir_nome, remetente_dir_endereco, remetente_dir_pais_codigo, regime_tributacao, moeda, volumes, peso,
    local_desembaraco, uf_desembaraco, data_desembaraco, via_transporte, forma_intermedio,
    cambio, valor_mercadoria_usd, frete_usd, frete_modo, valor_mercadoria_brl, frete_brl, valor_aduaneiro_brl,
    ii_valor, ii_pendente, aliquota_icms, bc_icms, icms_valor, valor_nota,
    gnre_numero, gnre_receita, gnre_uf, gnre_valor,
    courier_nome, courier_cnpj, courier_servicos, courier_armazenagem,
    nota_debito_numero, nota_debito_valor, nota_debito_emissao, nota_debito_pago_em, nota_debito_conta_bancaria_id, nota_debito_forma_pagamento, nota_debito_motivo_compra_id,
    exportador_nome, exportador_logradouro, exportador_numero, exportador_complemento, exportador_bairro,
    exportador_pais_codigo, exportador_pais_nome, exportador_codigo, exportador_id_estrangeiro,
    natureza_operacao, cfop, consumidor_final, credito_icms, perfil_operacao_id, solicitacao_id, xml_dir, observacao, dados_json, criado_por
  ) values (
    v_imp_id, v_scope.tenant_id, v_scope.empresa_id, 'RASCUNHO', v_awb, v_dir->>'master', v_dir_numero, v_dir->'dir'->>'lote',
    (v_dir->'dir'->>'data_registro')::timestamp at time zone 'America/Sao_Paulo', v_dir->'dir'->>'situacao',
    v_dir->'manifesto'->>'numero', nullif(v_dir->'manifesto'->>'data', '')::timestamp at time zone 'America/Sao_Paulo',
    v_dir->'dir'->>'ua_entrada', v_dir->'manifesto'->>'pais_origem', v_dir->'destinatario'->>'documento',
    v_dir->'remetente'->>'nome', btrim(concat_ws(', ', nullif(v_dir->'remetente'->>'logradouro', ''), nullif(v_dir->'remetente'->>'complemento', ''))), v_dir->'remetente'->>'pais_codigo',
    (v_itens_dir->0->>'regime_tributacao'), (v_itens_dir->0->>'moeda'), (v_dir->'remessa'->>'volumes')::integer, (v_dir->'remessa'->>'peso')::numeric,
    v_local, v_uf_desemb, v_data_desemb, v_via, v_intermedio,
    v_cambio, v_valor_usd, v_frete_usd, v_dir->'remessa'->>'frete_modo', v_valor_brl, v_frete_brl, v_aduaneiro,
    v_ii, coalesce((v_dir->'ii'->>'pendente')::numeric, 0), v_aliquota, v_bc, v_icms, v_nota,
    nullif(btrim(coalesce(p_dados->'gnre'->>'numero', '')), ''), nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), ''), nullif(upper(btrim(coalesce(p_dados->'gnre'->>'uf', ''))), ''), v_gnre_valor,
    v_dir->'courier'->>'nome', v_dir->'courier'->>'cnpj', v_courier_servicos, v_courier_armazenagem,
    nullif(btrim(coalesce(v_nd->>'numero', '')), ''), v_nd_valor, nullif(v_nd->>'emissao', '')::date, nullif(v_nd->>'pago_em', '')::date, v_conta, v_forma, v_motivo_compra,
    left(btrim(v_exp->>'nome'), 60), left(btrim(v_exp->>'logradouro'), 60), left(coalesce(nullif(btrim(coalesce(v_exp->>'numero', '')), ''), 'S/N'), 60),
    left(nullif(btrim(coalesce(v_exp->>'complemento', '')), ''), 60), left(coalesce(nullif(btrim(coalesce(v_exp->>'bairro', '')), ''), 'EXTERIOR'), 60),
    v_exp->>'pais_codigo', left(upper(btrim(v_exp->>'pais_nome')), 60), v_exp_codigo, nullif(btrim(coalesce(v_exp->>'id_estrangeiro', '')), ''),
    v_natureza, v_cfop, v_consumidor_final, v_credito_icms, v_perfil_id, v_sol_id, p_dados->>'xml', nullif(btrim(coalesce(p_dados->>'observacao', '')), ''),
    jsonb_build_object('dir', v_dir - 'itens' - 'bloqueios' - 'em_uso', 'perfil_codigo', v_perfil_codigo), v_scope.usuario_id
  );

  -- 6.11 Itens: rateio proporcional ao valor em dolar; o ultimo fecha as pontas dos centavos.
  for v_i in 0 .. v_n - 1 loop
    v_dir_item := v_itens_dir->v_i;
    v_req := v_itens_req->v_i;
    v_item_qtd := coalesce(nullif(v_req->>'quantidade', '')::numeric, (v_dir_item->>'quantidade')::numeric);
    v_item_ncm := regexp_replace(coalesce(v_req->>'ncm', ''), '[^0-9]', '', 'g');
    v_item_id := nullif(v_req->>'item_id', '')::integer;
    v_item_codigo := nullif(btrim(coalesce(v_req->>'codigo', '')), '');
    v_item_desc := nullif(btrim(coalesce(v_req->>'descricao', '')), '');
    v_item_un := upper(nullif(btrim(coalesce(v_req->>'unidade', '')), ''));
    v_item_fab := nullif(btrim(coalesce(v_req->>'fabricante', '')), '');
    if v_item_qtd is null or v_item_qtd <= 0 then
      raise exception using errcode = '22023', message = format('Mercadoria %s: quantidade invalida.', v_i + 1);
    end if;
    if v_item_ncm !~ '^[0-9]{8}$' then
      raise exception using errcode = '22023', message = format('Mercadoria %s: NCM deve ter 8 digitos (o HS da invoice nao serve).', v_i + 1);
    end if;
    if v_item_fab is null then
      raise exception using errcode = '22023', message = format('Mercadoria %s: informe o fabricante (cFabricante da adicao).', v_i + 1);
    end if;
    if v_item_id is not null then
      select i.id, coalesce(v_item_codigo, i.codigo_interno), coalesce(v_item_desc, i.nome), coalesce(v_item_un, upper(i.unidade_medida))
        into v_item_id, v_item_codigo, v_item_desc, v_item_un
      from public.itens i
      where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id and i.id = v_item_id and i.ativo;
      if not found then
        raise exception using errcode = '22023', message = format('Mercadoria %s: item do catalogo %s nao encontrado nesta empresa.', v_i + 1, v_req->>'item_id');
      end if;
    end if;
    if v_item_codigo is null or v_item_desc is null or v_item_un is null then
      raise exception using errcode = '22023', message = format('Mercadoria %s: informe codigo, descricao e unidade (ou escolha o item do catalogo).', v_i + 1);
    end if;
    -- O valor aduaneiro (vProd) e rateado direto do valor tributavel da DIR: mercadoria + frete
    -- podem nao fechar com ele no centavo (228,85 + 209,11 = 437,96 contra 437,97 na DIR da UPS).
    -- O ICMS de cada item e base x aliquota (a SEFAZ confere item a item); o total da nota passa
    -- a ser a soma dos itens, que pode diferir da GNRE em centavos (tolerancia de 5 centavos).
    if v_i = v_n - 1 then
      v_item_merc := v_valor_brl - v_acum_merc;
      v_item_frete := v_frete_brl - v_acum_frete;
      v_item_adu := v_aduaneiro - v_acum_adu;
      v_item_ii := v_ii - v_acum_ii;
      v_item_bc := v_bc - v_acum_bc;
      v_item_courier := (v_courier_servicos + v_courier_armazenagem) - v_acum_courier;
    else
      v_item_merc := round(v_valor_brl * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_frete := round(v_frete_brl * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_adu := round(v_aduaneiro * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_ii := round(v_ii * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_bc := round(v_bc * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
      v_item_courier := round((v_courier_servicos + v_courier_armazenagem) * (v_dir_item->>'valor_usd')::numeric / v_soma_usd, 2);
    end if;
    v_item_icms := round(v_item_bc * v_aliquota / 100, 2);
    v_acum_merc := v_acum_merc + v_item_merc; v_acum_frete := v_acum_frete + v_item_frete; v_acum_adu := v_acum_adu + v_item_adu;
    v_acum_ii := v_acum_ii + v_item_ii; v_acum_bc := v_acum_bc + v_item_bc; v_acum_icms := v_acum_icms + v_item_icms;
    v_acum_courier := v_acum_courier + v_item_courier;

    insert into f.importacao_remessa_item (
      importacao_id, tenant_id, empresa_id, ordem, sequencia_dir, item_id, codigo, descricao, ncm, unidade, quantidade, peso, fabricante,
      valor_usd, valor_mercadoria_brl, frete_brl, valor_aduaneiro_brl, valor_unitario_brl, ii_valor, bc_icms, icms_valor, courier_rateado,
      custo_total, custo_unitario
    ) values (
      v_imp_id, v_scope.tenant_id, v_scope.empresa_id, v_i + 1, v_dir_item->>'sequencia', v_item_id, left(v_item_codigo, 60), left(v_item_desc, 120), v_item_ncm,
      left(v_item_un, 6), v_item_qtd, (v_dir_item->>'peso')::numeric, left(v_item_fab, 60),
      (v_dir_item->>'valor_usd')::numeric, v_item_merc, v_item_frete, v_item_adu, round(v_item_adu / v_item_qtd, 10), v_item_ii, v_item_bc, v_item_icms, v_item_courier,
      round(v_item_adu + v_item_ii + v_item_courier + case when v_credito_icms then 0 else v_item_icms end, 2),
      round((v_item_adu + v_item_ii + v_item_courier + case when v_credito_icms then 0 else v_item_icms end) / v_item_qtd, 6)
    ) returning * into v_item_row;

    v_itens_snapshot := v_itens_snapshot || jsonb_build_object(
      'ordem', v_i + 1, 'sequencia_dir', v_dir_item->>'sequencia', 'adicao', 1, 'sequencial_adicao', v_i + 1, 'fabricante', left(v_item_fab, 60),
      'valor_aduaneiro', v_item_adu, 'ii', v_item_ii, 'bc_icms', v_item_bc, 'icms', v_item_icms, 'outras_despesas', v_item_icms
    );
  end loop;
  -- Totais da nota = soma dos itens (o ICMS pode andar centavos em relacao ao calculo pela base total).
  if v_acum_icms <> v_icms then
    v_icms := v_acum_icms;
    v_nota := round(v_aduaneiro + v_ii + v_icms, 2);
    update f.importacao_remessa set icms_valor = v_icms, valor_nota = v_nota where id = v_imp_id;
  end if;

  -- 6.12 Textos da nota (o montador tambem os conhece; ficam no snapshot para a tela e a auditoria).
  v_texto_fisco := format('NF-E DE ENTRADA DE IMPORTACAO POR REMESSA EXPRESSA (RTS, REGIME DE TRIBUTACAO SIMPLIFICADA). DIR %s DE %s. II RECOLHIDO NA DIR. ICMS RECOLHIDO POR GNRE%s.',
    v_dir_numero, v_data_registro_txt,
    case when nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), '') is not null then format(' RECEITA %s', p_dados->'gnre'->>'receita') else '' end);
  v_texto_cpl := format('IMPORTACAO POR REMESSA EXPRESSA. AWB %s%s. DIR %s REGISTRADA EM %s, UA %s (%s/%s). CAMBIO %s. MERCADORIA USD %s; FRETE USD %s; VALOR ADUANEIRO R$ %s. II R$ %s. ICMS R$ %s (BC R$ %s A %s%%), GNRE%s R$ %s. NOTA DE DEBITO %s %s. REMETENTE CONFORME DIR: %s. EXPORTADOR CONFORME INVOICE: %s. DESPESAS DO COURIER (SERVICOS R$ %s, ARMAZENAGEM R$ %s) FORA DA NOTA. SEM COBRANCA.',
    v_awb, case when v_dir->'courier'->>'nome' is not null then ' ' || (v_dir->'courier'->>'nome') else '' end,
    v_dir_numero, v_data_registro_txt, v_dir->'dir'->>'ua_entrada', v_local, v_uf_desemb,
    replace(to_char(v_cambio, 'FM990D0000'), '.', ','), f.fn_importacao_brl(v_valor_usd), f.fn_importacao_brl(v_frete_usd), f.fn_importacao_brl(v_aduaneiro),
    f.fn_importacao_brl(v_ii), f.fn_importacao_brl(v_icms), f.fn_importacao_brl(v_bc), f.fn_importacao_brl(v_aliquota),
    case when nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), '') is not null then ' RECEITA ' || (p_dados->'gnre'->>'receita') else '' end,
    f.fn_importacao_brl(v_gnre_valor),
    coalesce(v_dir->'courier'->>'nome', 'DO COURIER'), coalesce(nullif(btrim(coalesce(v_nd->>'numero', '')), ''), 'NAO INFORMADA'),
    coalesce(v_dir->'remetente'->>'nome', '?'), upper(btrim(v_exp->>'nome')),
    f.fn_importacao_brl(v_courier_servicos), f.fn_importacao_brl(v_courier_armazenagem));
  v_texto_cpl := upper(v_texto_cpl);

  -- 6.13 Solicitacao de NF-e: entrada (tpNF 0), destino exterior (idDest 3), sem cobranca.
  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, natureza_operacao, observacao, criado_por,
    finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
    valor_frete, valor_seguro, valor_outras_despesas,
    destino_uf_confirmada, destino_confirmado_em, destino_confirmado_por,
    pagamento_forma, pagamento_indicador, pagamento_parcelas, transportador_dados, volumes_dados,
    revisao_fiscal_confirmada_em, revisao_fiscal_confirmada_por, perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por,
    emitente_snapshot, destinatario_snapshot, operacao_snapshot, snapshot_cadastro_em
  ) values (
    v_sol_id, v_scope.tenant_id, v_scope.empresa_id, null, 'PREVIA', v_natureza,
    nullif(btrim(coalesce(p_dados->>'observacao', '')), ''), v_scope.usuario_id,
    1, v_consumidor_final, 9, 9,
    0, 0, v_icms,
    'EX', now(), v_scope.usuario_id,
    '90', 0, null, null, null,
    now(), v_scope.usuario_id, v_perfil_id, case when v_perfil_id is null then null else now() end, case when v_perfil_id is null then null else v_scope.usuario_id end,
    jsonb_build_object(
      'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
      'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
      'telefone', v_empresa.telefone, 'inscricao_estadual', v_fiscal.inscricao_estadual,
      'crt', v_fiscal.crt, 'serie_nfe', v_fiscal.serie_nfe,
      'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero,
      'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro,
      'cidade', coalesce((select mi.nome from public.municipios_ibge mi where mi.codigo_ibge = regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g')), v_endereco.cidade),
      'uf', v_uf_emitente,
      'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'),
      'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')
    ),
    jsonb_build_object(
      'id', null, 'documento', null, 'id_estrangeiro', nullif(btrim(coalesce(v_exp->>'id_estrangeiro', '')), ''),
      'nome', left(upper(btrim(v_exp->>'nome')), 60), 'inscricao_estadual', null, 'indicador_ie', '9',
      'email', null, 'telefone', null,
      'logradouro', left(upper(btrim(v_exp->>'logradouro')), 60), 'numero_endereco', left(coalesce(nullif(btrim(coalesce(v_exp->>'numero', '')), ''), 'S/N'), 60),
      'complemento', left(nullif(upper(btrim(coalesce(v_exp->>'complemento', ''))), ''), 60), 'bairro', left(coalesce(nullif(upper(btrim(coalesce(v_exp->>'bairro', ''))), ''), 'EXTERIOR'), 60),
      'cidade', 'EXTERIOR', 'uf', 'EX', 'codigo_ibge_municipio', '9999999', 'cep', null,
      'pais_codigo', v_exp->>'pais_codigo', 'pais_nome', left(upper(btrim(v_exp->>'pais_nome')), 60)
    ),
    jsonb_build_object(
      'natureza_operacao', v_natureza, 'finalidade_emissao', 1, 'consumidor_final', v_consumidor_final, 'presenca_comprador', 9,
      'tipo_documento', 0, 'local_destino', 3,
      'modalidade_frete', 9, 'valor_frete', 0, 'valor_seguro', 0, 'valor_outras_despesas', v_icms, 'valor_total_ii', v_ii,
      'destinacao_mercadoria', null, 'nfe_referenciada', null, 'transportador', null, 'volumes', null,
      'pagamento', jsonb_build_object('forma', '90', 'indicador', 0, 'descricao', null, 'parcelas', null, 'fatura_numero', null),
      'importacao', jsonb_build_object(
        'importacao_id', v_imp_id, 'awb', v_awb, 'courier_nome', v_dir->'courier'->>'nome', 'courier_cnpj', v_dir->'courier'->>'cnpj',
        'dir_numero', v_dir_numero, 'dir_data_registro', left(v_dir->'dir'->>'data_registro', 10), 'dir_data_registro_texto', v_data_registro_txt,
        'ua_entrada', v_dir->'dir'->>'ua_entrada', 'local_desembaraco', v_local, 'uf_desembaraco', v_uf_desemb, 'data_desembaraco', to_char(v_data_desemb, 'YYYY-MM-DD'),
        'via_transporte', v_via, 'forma_intermedio', v_intermedio, 'exportador_codigo', v_exp_codigo,
        'remetente_dir', v_dir->'remetente'->>'nome', 'regime_tributacao', (v_itens_dir->0->>'regime_tributacao'),
        'cambio', v_cambio, 'valor_mercadoria_usd', v_valor_usd, 'frete_usd', v_frete_usd,
        'valor_aduaneiro', v_aduaneiro, 'ii', v_ii, 'aliquota_icms', v_aliquota, 'bc_icms', v_bc, 'icms', v_icms, 'valor_nota', v_nota,
        'gnre', jsonb_build_object('numero', nullif(btrim(coalesce(p_dados->'gnre'->>'numero', '')), ''), 'receita', nullif(btrim(coalesce(p_dados->'gnre'->>'receita', '')), ''),
                                   'uf', nullif(upper(btrim(coalesce(p_dados->'gnre'->>'uf', ''))), ''), 'valor', v_gnre_valor),
        'nota_debito', jsonb_build_object('numero', nullif(btrim(coalesce(v_nd->>'numero', '')), ''), 'valor', v_nd_valor),
        'courier_servicos', v_courier_servicos, 'courier_armazenagem', v_courier_armazenagem, 'credito_icms', v_credito_icms,
        'itens', v_itens_snapshot,
        'texto_fisco', v_texto_fisco, 'texto_complementar', v_texto_cpl
      )
    ),
    now()
  );

  -- 6.14 Itens fiscais da solicitacao: CST 00 a 17% (modBC 3), IPI 03/999, PIS/COFINS 98, IBS/CBS 000/000001,
  --      origem 1, vUnCom = valor aduaneiro / quantidade.
  for v_item_row in select * from f.importacao_remessa_item i where i.importacao_id = v_imp_id order by i.ordem loop
    insert into f.solicitacao_item (
      id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, origem_item_id, item_id, descricao, ncm, cest, cfop,
      cst_icms, csosn, cbenef, reducao_base_icms_percentual, aliquota_icms, icms_modalidade_base_calculo,
      cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins, aliquota_pis, aliquota_cofins,
      cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json,
      quantidade, unidade, unidade_tributavel, valor_unitario, valor_desconto, ordem, codigo_produto, origem_mercadoria,
      perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por, tributacao_fonte, modelo
    ) values (
      gen_random_uuid(), v_sol_id, v_scope.tenant_id, v_scope.empresa_id, 'IMPORTACAO', v_imp_id::text, v_item_row.id::text, v_item_row.item_id,
      v_item_row.descricao, v_item_row.ncm, null, v_cfop,
      '00', null, null, 0, v_aliquota, '3',
      '03', '999', null, '98', '98', null, null,
      '000', '000001', null, jsonb_build_object('ibs_uf_aliquota', 0.1, 'ibs_mun_aliquota', 0, 'cbs_aliquota', 0.9),
      v_item_row.quantidade, v_item_row.unidade, v_item_row.unidade, v_item_row.valor_unitario_brl, 0, v_item_row.ordem, v_item_row.codigo, 1,
      v_perfil_id, case when v_perfil_id is null then null else now() end, case when v_perfil_id is null then null else v_scope.usuario_id end,
      case when v_perfil_id is null then null else 'PERFIL' end, 'NFE'
    );
  end loop;

  return jsonb_build_object(
    'importacao_id', v_imp_id, 'solicitacao_id', v_sol_id, 'cfop', v_cfop, 'natureza_operacao', v_natureza,
    'valor_aduaneiro', v_aduaneiro, 'ii', v_ii, 'bc_icms', v_bc, 'icms', v_icms, 'valor_nota', v_nota,
    'itens', v_n, 'perfil_id', v_perfil_id, 'perfil_codigo', v_perfil_codigo, 'destinatario', upper(btrim(v_exp->>'nome')),
    'substituiu', case when v_em_uso is not null and jsonb_typeof(v_em_uso) = 'object' then v_em_uso->>'importacao_id' end
  );
end;
$$;
revoke all on function f.fn_importacao_remessa_criar(jsonb) from public, anon;
grant execute on function f.fn_importacao_remessa_criar(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Anexos (GNRE, nota de debito, invoice, DIR): o arquivo vai ao bucket nfe-documentos pela
--    rota do app (service role); aqui so o registro, com a mesma checagem de acesso.
-- ---------------------------------------------------------------------------
create or replace function f.fn_importacao_remessa_anexo_registrar(
  p_importacao_id uuid, p_tipo text, p_nome_arquivo text, p_storage_path text, p_content_type text default null, p_tamanho_bytes bigint default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_id uuid;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if not exists (
    select 1 from f.importacao_remessa i
     where i.id = p_importacao_id and i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id and i.deleted_at is null
  ) then
    raise exception using errcode = 'P0002', message = 'Importacao nao encontrada.';
  end if;
  if nullif(btrim(coalesce(p_nome_arquivo, '')), '') is null or nullif(btrim(coalesce(p_storage_path, '')), '') is null then
    raise exception using errcode = '22023', message = 'Anexo sem nome ou sem caminho.';
  end if;
  insert into f.importacao_remessa_anexo (importacao_id, tenant_id, empresa_id, tipo, nome_arquivo, storage_path, content_type, tamanho_bytes, criado_por)
  values (p_importacao_id, v_scope.tenant_id, v_scope.empresa_id, upper(p_tipo), left(p_nome_arquivo, 200), p_storage_path, p_content_type, p_tamanho_bytes, v_scope.usuario_id)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function f.fn_importacao_remessa_anexo_registrar(uuid, text, text, text, text, bigint) from public, anon;
grant execute on function f.fn_importacao_remessa_anexo_registrar(uuid, text, text, text, text, bigint) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. O documento da NF-e de importacao e de ENTRADA e o total leva o II.
--    Patch por texto nas duas funcoes de preparo (homologacao e producao), idempotente.
-- ---------------------------------------------------------------------------
do $$
declare
  v_nome text;
  v_def text;
  v_anchor_op constant text := '''SAIDA'', ''PRODUTO'', v_sf.cliente_id';
  v_op constant text := 'case when v_sf.operacao_snapshot->>''tipo_documento'' = ''0'' then ''ENTRADA'' else ''SAIDA'' end, ''PRODUTO'', v_sf.cliente_id';
  v_anchor_total constant text := '+ coalesce(v_sf.valor_outras_despesas, 0),';
  v_total constant text := '+ coalesce(v_sf.valor_outras_despesas, 0) + coalesce(nullif(v_sf.operacao_snapshot->>''valor_total_ii'', '''')::numeric, 0),';
begin
  foreach v_nome in array array['fn_nfe_preparar_documento_solicitacao', 'fn_nfe_preparar_documento_solicitacao_producao'] loop
    select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'f' and p.proname = v_nome;
    if v_def is null then
      raise exception 'f.% nao encontrada', v_nome;
    end if;
    if position('tipo_documento' in v_def) > 0 then
      raise notice 'f.% ja grava a operacao pelo tipo_documento; nada a fazer', v_nome;
      continue;
    end if;
    if (length(v_def) - length(replace(v_def, v_anchor_op, ''))) / length(v_anchor_op) <> 1
       or (length(v_def) - length(replace(v_def, v_anchor_total, ''))) / length(v_anchor_total) <> 1 then
      raise exception 'ancoras nao encontradas (ou repetidas) em f.%', v_nome;
    end if;
    v_def := replace(v_def, v_anchor_op, v_op);
    v_def := replace(v_def, v_anchor_total, v_total);
    execute v_def;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 9. Depois da SEFAZ: homologacao autorizada marca HOMOLOGADA; a nota real conclui a
--    importacao, da entrada no estoque e lanca a nota de debito do courier no contas a pagar.
-- ---------------------------------------------------------------------------
create or replace function f.fn_importacao_remessa_apos_emissao()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_imp f.importacao_remessa%rowtype;
  v_item f.importacao_remessa_item%rowtype;
  v_email text;
  v_mov_id bigint;
  v_movs jsonb := '[]'::jsonb;
  v_pendencias jsonb := '[]'::jsonb;
  v_estorno jsonb := '[]'::jsonb;
  v_orig jsonb;
  v_motivo text;
  v_fornecedor_id integer;
  v_titulo_id uuid;
  v_pagamento_id uuid;
  v_ap jsonb := '{}'::jsonb;
  v_plano uuid;
  v_emissao date;
  v_courier_cnpj text;
  v_status_antes text := case when tg_op = 'UPDATE' then old.status else null end;
begin
  if new.solicitacao_id is null or new.status is not distinct from v_status_antes then
    return new;
  end if;
  select * into v_imp from f.importacao_remessa i
   where i.tenant_id = new.tenant_id and i.empresa_id = new.empresa_id and i.solicitacao_id = new.solicitacao_id and i.deleted_at is null
   limit 1;
  if not found then return new; end if;

  if new.ambiente = 'HOMOLOGACAO' then
    if new.status = 'AUTORIZADA' then
      update f.importacao_remessa set status = 'HOMOLOGADA', updated_at = now()
       where id = v_imp.id and status in ('RASCUNHO', 'HOMOLOGACAO');
    elsif v_imp.status = 'RASCUNHO' then
      update f.importacao_remessa set status = 'HOMOLOGACAO', updated_at = now() where id = v_imp.id;
    end if;
    return new;
  end if;
  if new.ambiente <> 'PRODUCAO' then return new; end if;

  select u.email into v_email from a.usuario u where u.id = v_imp.criado_por;
  v_email := coalesce(v_email, 'sistema');

  if new.status = 'AUTORIZADA' then
    if v_imp.dados_json ? 'estoque_movimentacoes' then return new; end if;

    -- 9.1 Entrada no estoque: custo = valor aduaneiro + II + despesas do courier (+ ICMS so sem credito).
    for v_item in select * from f.importacao_remessa_item i where i.importacao_id = v_imp.id order by i.ordem loop
      if v_item.item_id is null then
        v_pendencias := v_pendencias || jsonb_build_object('ordem', v_item.ordem, 'codigo', v_item.codigo, 'motivo', 'mercadoria sem item do catalogo');
        continue;
      end if;
      v_motivo := format('Entrada por importacao NF-e %s/%s (AWB %s, DIR %s) [IMPORTACAO %s]',
        coalesce(new.serie::text, '?'), coalesce(new.numero::text, '?'), v_imp.awb, v_imp.dir_numero, v_imp.id);
      insert into public.movimentacoes (
        tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, created_at,
        custo_unitario_bruto, custo_unitario_real, credito_icms, credito_pis, credito_cofins, v_ipi, v_icms, v_pis, v_cofins, v_frete_rateado
      ) values (
        v_imp.tenant_id, v_imp.empresa_id, v_item.item_id, 'entrada', v_item.quantidade, v_motivo, v_email, now(), now(),
        round(v_item.valor_aduaneiro_brl / v_item.quantidade, 6), v_item.custo_unitario,
        case when v_imp.credito_icms then v_item.icms_valor else 0 end, 0, 0, 0, v_item.icms_valor, 0, 0, v_item.frete_brl
      ) returning id into v_mov_id;
      v_movs := v_movs || jsonb_build_object('movimentacao_id', v_mov_id, 'item_id', v_item.item_id, 'quantidade', v_item.quantidade, 'custo_unitario', v_item.custo_unitario);
    end loop;

    -- 9.2 Nota de debito do courier: titulo AP da importacao, sem duplicar.
    if v_imp.nota_debito_numero is not null and coalesce(v_imp.nota_debito_valor, 0) > 0 then
      begin
        v_courier_cnpj := regexp_replace(coalesce(v_imp.courier_cnpj, ''), '[^0-9]', '', 'g');
        select fo.id into v_fornecedor_id from public.fornecedores fo
         where fo.tenant_id = v_imp.tenant_id and v_courier_cnpj <> '' and fo.cnpj_digits = v_courier_cnpj
         order by (fo.empresa_id = v_imp.empresa_id) desc, fo.id limit 1;
        if v_fornecedor_id is null then
          insert into public.fornecedores (tenant_id, empresa_id, nome, documento, cnpj, ativo, gerar_contas_pagar_auto)
          values (v_imp.tenant_id, v_imp.empresa_id, coalesce(v_imp.courier_nome, 'COURIER'), nullif(v_courier_cnpj, ''), nullif(v_courier_cnpj, ''), true, false)
          returning id into v_fornecedor_id;
        end if;
        select t.id into v_titulo_id from f.titulo t
         where t.tenant_id = v_imp.tenant_id and t.empresa_id = v_imp.empresa_id and t.tipo = 'AP' and t.deleted_at is null and t.status <> 'CANCELADO'
           and t.fornecedor_id = v_fornecedor_id
           and (t.id = v_imp.nota_debito_titulo_id or t.descricao ilike '%' || v_imp.nota_debito_numero || '%')
         order by t.created_at limit 1;
        if v_titulo_id is null then
          v_emissao := coalesce(v_imp.nota_debito_emissao, v_imp.nota_debito_pago_em, (v_imp.dir_data_registro at time zone 'America/Sao_Paulo')::date);
          insert into f.titulo (tenant_id, empresa_id, tipo, status, origem, fornecedor_id, descricao, emissao_date, competencia_date, valor_total, valor_aberto, motivo_compra_id, created_by)
          values (v_imp.tenant_id, v_imp.empresa_id, 'AP', 'APROVADO', 'IMPORTACAO', v_fornecedor_id,
                  upper(format('NOTA DE DEBITO %s %s - IMPORTACAO AWB %s (DIR %s): II, ICMS/GNRE E SERVICOS', coalesce(v_imp.courier_nome, 'COURIER'), v_imp.nota_debito_numero, v_imp.awb, v_imp.dir_numero)),
                  v_emissao, date_trunc('month', v_emissao)::date, v_imp.nota_debito_valor, v_imp.nota_debito_valor, v_imp.nota_debito_motivo_compra_id, v_imp.criado_por)
          returning id into v_titulo_id;
          insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
          values (v_imp.tenant_id, v_titulo_id, '001', coalesce(v_imp.nota_debito_pago_em, v_emissao), v_imp.nota_debito_valor, v_imp.nota_debito_valor);
          -- Rateio de 100% no plano de contas do motivo; sem plano no motivo o titulo fica sem
          -- rateio (o financeiro exige plano no rateio) e a tela de contas a pagar completa.
          select mc.plano_contas_id into v_plano from f.motivo_compra mc where mc.id = v_imp.nota_debito_motivo_compra_id and mc.deleted_at is null;
          if v_plano is not null then
            insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor, origem_rateio)
            values (v_imp.tenant_id, v_titulo_id, v_plano, 100, v_imp.nota_debito_valor, 'SISTEMA_FALLBACK');
          end if;
          v_ap := v_ap || jsonb_build_object('titulo_id', v_titulo_id, 'criado', true);
          -- Ja paga: registra o pagamento pelo fluxo do financeiro quando a tela informou conta e forma.
          if v_imp.nota_debito_pago_em is not null and v_imp.nota_debito_conta_bancaria_id is not null and v_imp.nota_debito_forma_pagamento is not null then
            v_pagamento_id := f.registrar_pagamento_ap_v2(
              v_titulo_id, v_imp.nota_debito_conta_bancaria_id, v_imp.nota_debito_pago_em, v_imp.nota_debito_forma_pagamento,
              v_imp.nota_debito_valor, 0, 0, 0,
              format('Nota de debito %s paga em %s (importacao AWB %s)', v_imp.nota_debito_numero, to_char(v_imp.nota_debito_pago_em, 'DD/MM/YYYY'), v_imp.awb),
              'Baixa automatica da nota de debito da importacao'
            );
            v_ap := v_ap || jsonb_build_object('pagamento_id', v_pagamento_id);
          end if;
        else
          v_ap := v_ap || jsonb_build_object('titulo_id', v_titulo_id, 'criado', false, 'motivo', 'titulo ja existia para esta nota de debito');
        end if;
        v_ap := v_ap || jsonb_build_object('fornecedor_id', v_fornecedor_id);
      exception when others then
        -- A SEFAZ ja autorizou: o financeiro nao pode derrubar a nota. O bloco inteiro volta
        -- atras (subtransacao) e a pendencia fica registrada para lancar a mao.
        v_titulo_id := null;
        v_ap := jsonb_build_object('erro', sqlerrm, 'criado', false);
      end;
    end if;

    update f.importacao_remessa
       set status = 'CONCLUIDA', chave_nfe = new.chave_acesso, nfe_numero = new.numero, nfe_serie = new.serie,
           nfe_autorizada_em = coalesce(new.autorizado_em, now()), documento_fiscal_id = new.documento_fiscal_id,
           nota_debito_titulo_id = coalesce(nullif(v_ap->>'titulo_id', '')::uuid, nota_debito_titulo_id),
           dados_json = dados_json || jsonb_build_object('estoque_movimentacoes', v_movs, 'estoque_pendencias', v_pendencias, 'ap', v_ap, 'concluida_em', now()),
           updated_at = now()
     where id = v_imp.id;
  elsif new.status = 'CANCELADA' then
    for v_orig in select value from jsonb_array_elements(coalesce(v_imp.dados_json->'estoque_movimentacoes', '[]'::jsonb)) loop
      insert into public.movimentacoes (tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, created_at)
      values (v_imp.tenant_id, v_imp.empresa_id, (v_orig->>'item_id')::integer, 'saida', (v_orig->>'quantidade')::numeric,
              format('Estorno da importacao: NF-e %s/%s cancelada [IMPORTACAO %s]', coalesce(new.serie::text, '?'), coalesce(new.numero::text, '?'), v_imp.id),
              v_email, now(), now())
      returning id into v_mov_id;
      v_estorno := v_estorno || jsonb_build_object('movimentacao_id', v_mov_id, 'estorna', v_orig->'movimentacao_id');
    end loop;
    update f.importacao_remessa
       set status = 'CANCELADA',
           dados_json = dados_json || jsonb_build_object('estoque_estornos', v_estorno, 'estoque_estornado_em', now(),
             'cancelamento', jsonb_build_object('motivo', 'NF-e real cancelada pelo ciclo de vida', 'em', now())),
           updated_at = now()
     where id = v_imp.id;
  end if;
  return new;
end;
$$;
revoke all on function f.fn_importacao_remessa_apos_emissao() from public, anon, authenticated;
drop trigger if exists trg_importacao_remessa_apos_emissao on f.documento_fiscal_emissao;
create trigger trg_importacao_remessa_apos_emissao
  after insert or update of status on f.documento_fiscal_emissao
  for each row execute function f.fn_importacao_remessa_apos_emissao();

-- ---------------------------------------------------------------------------
-- 10. Perfis de importacao (3101, 3102, 3556, 3551), origem 1, CST 00 a 17% por dentro, IPI 03,
--     PIS/COFINS 98, destino EX. Nascem em revisao e desabilitados; a liberacao e pela tela de
--     perfis, e so para o CFOP usado agora.
-- ---------------------------------------------------------------------------
insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
  aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa, justificativa_faixa,
  divergencia_ipi, divergencia_fabricado_revenda, divergencia_cabo_beneficio,
  xml_notas, xml_itens, xml_pis_csts, xml_cofins_csts, xml_pis_aliquotas, xml_cofins_aliquotas,
  xml_ipi_csts, xml_cbenef_valores, xml_cbenef_ausente_itens, xml_fci_itens, xml_divergente
)
-- Uma evidencia por perfil (indice unico perfil_operacao_evidencia_id_ux): a mesma DIR, uma linha por CFOP.
select
  ('a6e1c3d2-3100-4c00-9a2b-00000000' || ev.cfop)::uuid, '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7', 'f0e74f49-a127-46b4-901b-f7b37e43c690',
  'DIR 260191366846 (Siscomex Remessa, UPS AWB 1ZJ451C10441551106, 09/09/2026) + GNRE receita 10005-6 R$ 143,53 + nota de debito UPS 2953830',
  ev.linha, 'IMPORTACAO', ev.cfop, 1, '100', '00', 17, 0, false, 1, 1,
  array['85371020']::text[], '{}'::integer[],
  'Entrada de importacao por remessa expressa (RTS), CFOP ' || ev.cfop || ': vProd = valor aduaneiro, II da DIR, ICMS por dentro (BC = (vProd + II) / (1 - 17%)), vOutro = ICMS, IPI CST 03 cEnq 999, PIS/COFINS CST 98, IBS/CBS 000/000001, tpNF 0, idDest 3, destinatario no exterior, sem cobranca.',
  'REVISAO', 'Primeira importacao pelo ERP: homologar e revisar antes de liberar producao.',
  false, false, false, 0, 0, '{}'::text[], '{}'::text[], '{}'::numeric[], '{}'::numeric[], '{}'::text[], '{}'::text[], 0, 0, false
from (values (1, '3101'), (2, '3102'), (3, '3556'), (4, '3551')) as ev(linha, cfop)
where exists (select 1 from c.empresa e where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7' and e.id = 'f0e74f49-a127-46b4-901b-f7b37e43c690')
on conflict (tenant_id, empresa_id, fonte, fonte_linha) do nothing;

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_interno, cfop_externo, cst_icms, aliquota_icms, icms_modalidade_base_calculo, cbenef, cbenef_aplicacao, beneficio_texto_legal,
  cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins, aliquota_pis, aliquota_cofins, finalidade_emissao, consumidor_final,
  ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  cst_ibs_cbs, cclass_trib, ibs_cbs_json,
  exige_referencia, exige_motivo, observacao, informacoes_complementares_modelo, vigencia_inicio,
  evidencia_id, faixa_automacao, justificativa_faixa, habilitado_producao
)
select
  p.id::uuid, '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7', 'f0e74f49-a127-46b4-901b-f7b37e43c690',
  p.codigo, p.nome, 'NFE', p.natureza, p.natureza_texto, '3',
  null, p.cfop, '00', 17, '3', null, 'SEM_BENEFICIO', null,
  '03', '999', null, '98', '98', null, null, 1, p.consumidor_final,
  'INTERESTADUAL', array['EX']::text[], '9', 1,
  '000', '000001', jsonb_build_object('ibs_uf_aliquota', 0.1, 'ibs_mun_aliquota', 0, 'cbs_aliquota', 0.9),
  false, false,
  'Importacao por remessa expressa (RTS): ICMS por dentro a 17% sobre (valor aduaneiro + II), sem IPI, PIS e COFINS na entrada (RTS unifica no II de 60%). Destinatario = exportador no exterior (UF EX, municipio 9999999). ' || p.obs,
  'NF-E DE ENTRADA DE IMPORTACAO POR REMESSA EXPRESSA. II RECOLHIDO NA DIR; ICMS RECOLHIDO POR GNRE.',
  '2026-09-17', ('a6e1c3d2-3100-4c00-9a2b-00000000' || p.cfop)::uuid, 'REVISAO',
  'Primeira importacao pelo ERP: homologar e revisar antes de liberar producao.', false
from (values
  ('a6e1c3d2-3101-4c00-9a2b-000000003101', 'SEG-IMPORTACAO-3101-O1-CST00', 'SEG - importacao para industrializacao - CFOP 3101 - origem 1 - CST 00', 'IMPORTACAO_INDUSTRIALIZACAO', 'COMPRA PARA INDUSTRIALIZACAO - IMPORTACAO', '3101', 0, 'Com credito do ICMS (o custo nao leva o ICMS).'),
  ('a6e1c3d2-3102-4c00-9a2b-000000003102', 'SEG-IMPORTACAO-3102-O1-CST00', 'SEG - importacao para comercializacao - CFOP 3102 - origem 1 - CST 00', 'IMPORTACAO_COMERCIALIZACAO', 'COMPRA PARA COMERCIALIZACAO - IMPORTACAO', '3102', 0, 'Com credito do ICMS (o custo nao leva o ICMS).'),
  ('a6e1c3d2-3556-4c00-9a2b-000000003556', 'SEG-IMPORTACAO-3556-O1-CST00', 'SEG - importacao de material para uso ou consumo - CFOP 3556 - origem 1 - CST 00', 'IMPORTACAO_CONSUMO', 'COMPRA DE MATERIAL PARA USO OU CONSUMO - IMPORTACAO', '3556', 1, 'Sem credito do ICMS (o ICMS entra no custo).'),
  ('a6e1c3d2-3551-4c00-9a2b-000000003551', 'SEG-IMPORTACAO-3551-O1-CST00', 'SEG - importacao de bem para o ativo imobilizado - CFOP 3551 - origem 1 - CST 00', 'IMPORTACAO_ATIVO', 'COMPRA DE BEM PARA O ATIVO IMOBILIZADO - IMPORTACAO', '3551', 1, 'Sem credito imediato do ICMS (CIAP); o ICMS entra no custo.')
) as p(id, codigo, nome, natureza, natureza_texto, cfop, consumidor_final, obs)
where exists (select 1 from f.perfil_operacao_evidencia ev where ev.id = ('a6e1c3d2-3100-4c00-9a2b-00000000' || p.cfop)::uuid)
on conflict (tenant_id, empresa_id, codigo, vigencia_inicio) do nothing;

update f.perfil_operacao_evidencia ev
   set perfil_operacao_id = po.id
  from f.perfil_operacao po
 where po.evidencia_id = ev.id and po.codigo like 'SEG-IMPORTACAO-%' and ev.perfil_operacao_id is null;

-- ---------------------------------------------------------------------------
-- Reversao (para desfazer esta migration):
--   drop trigger trg_importacao_remessa_apos_emissao on f.documento_fiscal_emissao;
--   drop function f.fn_importacao_remessa_apos_emissao(), f.fn_importacao_remessa_anexo_registrar(uuid,text,text,text,text,bigint),
--     f.fn_importacao_remessa_criar(jsonb), f.fn_importacao_remessa_cancelar(uuid,text), f.fn_importacao_remessa_ler_dir(text),
--     f.fn_importacao_ua_local(text), f.fn_importacao_brl(numeric);
--   drop table f.importacao_remessa_anexo, f.importacao_remessa_item, f.importacao_remessa;
--   delete from f.perfil_operacao where codigo like 'SEG-IMPORTACAO-%' and vigencia_inicio = '2026-09-17';
--   delete from f.perfil_operacao_evidencia where id::text like 'a6e1c3d2-3100-4c00-9a2b-00000000%';
--   nas funcoes fn_nfe_preparar_documento_solicitacao e ..._producao, voltar o trecho
--     "case when v_sf.operacao_snapshot->>'tipo_documento' = '0' then 'ENTRADA' else 'SAIDA' end" para "'SAIDA'"
--     e tirar "+ coalesce(nullif(v_sf.operacao_snapshot->>'valor_total_ii', '')::numeric, 0)";
--   restaurar solicitacao_item_origem_tipo_check sem 'IMPORTACAO' (nenhuma linha usa o valor apos o drop das tabelas).
-- ---------------------------------------------------------------------------
