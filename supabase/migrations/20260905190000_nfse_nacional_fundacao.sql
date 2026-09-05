-- NFS-e Padrao Nacional a partir da OS, pela Focus. Parte 1: fundacao (05/09/2026).
-- Inventario e decisoes: docs/faturamento/nfse-inventario.md.
--
-- O que este arquivo faz:
--   1. c.empresa_fiscal: serie/numero da DPS, opcao Simples, regime especial,
--      prazo de cancelamento (vazio ate o contador confirmar), id do webhook.
--   2. public.clientes: inscricao_municipal ja existia; iss_retido, retem_pcc,
--      retem_irrf, retem_inss (nulos = nao decidido) e email_nfse.
--   3. f.perfil_operacao: campos de servico; cinco perfis SEM valor fiscal
--      (14.06, 17.09, 17.06, 14.01 e 07.02; o 07.02 nasce BLOQUEADO).
--   4. f.tributacao_provisoria_nfse_homologacao: fixture provisoria por item
--      de servico, com a fonte (NFS-e 12-40 de agosto/2026, XML importado).
--   5. f.solicitacao_faturamento / f.solicitacao_item: municipio de prestacao,
--      competencia, pedido_item, decisoes de retencao, substituicao; linha
--      com modelo (NFE|NFSE), descricao_servico, valor_servico e campos de ISS.
--   6. f.documento_fiscal_emissao: modelo, dps_serie/numero, nfse_numero,
--      chave_nfse (50), codigo_verificacao, ISS, retencoes, liquido,
--      substituicao. f.documento_fiscal_evento: codigo_motivo, chave_nova,
--      chave_substituida.
--   7. f.dps_numero_log + f.fn_proximo_numero_dps (numero nunca reutilizado).
--   8. f.titulo_retencao (retencao por tributo do titulo a receber).
--   9. f.fn_os_notas ganha a coluna modelo.
--
-- Baselines (producao, 05/09/2026), objetos alterados:
--   c.empresa_fiscal: id, empresa_id, ie_isento, inscricao_estadual,
--     inscricao_municipal, cnae_principal, regime_tributario, crt, created_at,
--     updated_at, created_by, updated_by, deleted_at, serie_nfe, email_fisco,
--     certificado_validade_em. Checks ck_empresa_fiscal__{cnae_digits,crt_range,
--     ie_digits,ie_isento_regra,im_digits}, empresa_fiscal_email_fisco_ck,
--     empresa_fiscal_serie_nfe_ck. RLS codex_empresa_fiscal_context_all
--     (authenticated). Grant: select authenticated.
--   public.clientes: sem colunas de retencao; policies clientes_select/insert/
--     update/delete + enforce_active_empresa_scope (authenticated).
--   f.perfil_operacao: sem colunas de servico; 0 linhas modelo='NFSE';
--     check perfil_operacao_modelo_check (NFE|NFSE); unique
--     (tenant_id, empresa_id, codigo, vigencia_inicio).
--   f.solicitacao_faturamento e f.solicitacao_item: sem modelo/servico.
--     Grants: select authenticated; all service_role.
--   f.documento_fiscal_emissao: sem dps_*/nfse_*; grant select authenticated,
--     all service_role; policies documento_fiscal_emissao_all +
--     enforce_active_empresa_scope.
--   f.documento_fiscal_evento: tipo check ja inclui SUBSTITUICAO; sem
--     codigo_motivo/chave_nova/chave_substituida.
--   f.fn_os_notas(uuid,uuid,integer): migration 20260905180000 (sem modelo).

-- ---------------------------------------------------------------------------
-- 1. Empresa fiscal
-- ---------------------------------------------------------------------------
alter table c.empresa_fiscal
  add column if not exists serie_dps smallint,
  add column if not exists proximo_numero_dps bigint not null default 1,
  add column if not exists codigo_opcao_simples_nacional smallint,
  add column if not exists regime_especial_tributacao smallint,
  add column if not exists prazo_cancelamento_nfse_horas integer,
  add column if not exists focus_webhook_nfsen_id text,
  add column if not exists focus_webhook_nfsen_registrado_em timestamptz;
alter table c.empresa_fiscal drop constraint if exists empresa_fiscal_serie_dps_ck;
alter table c.empresa_fiscal add constraint empresa_fiscal_serie_dps_ck
  check (serie_dps is null or (serie_dps >= 1 and serie_dps <= 49999));
alter table c.empresa_fiscal drop constraint if exists empresa_fiscal_proximo_numero_dps_ck;
alter table c.empresa_fiscal add constraint empresa_fiscal_proximo_numero_dps_ck
  check (proximo_numero_dps >= 1);
alter table c.empresa_fiscal drop constraint if exists empresa_fiscal_opcao_simples_ck;
alter table c.empresa_fiscal add constraint empresa_fiscal_opcao_simples_ck
  check (codigo_opcao_simples_nacional is null or codigo_opcao_simples_nacional in (1, 2, 3));
alter table c.empresa_fiscal drop constraint if exists empresa_fiscal_regime_especial_ck;
alter table c.empresa_fiscal add constraint empresa_fiscal_regime_especial_ck
  check (regime_especial_tributacao is null or regime_especial_tributacao in (0, 1, 2, 3, 4, 5, 6, 9));
alter table c.empresa_fiscal drop constraint if exists empresa_fiscal_prazo_cancel_nfse_ck;
alter table c.empresa_fiscal add constraint empresa_fiscal_prazo_cancel_nfse_ck
  check (prazo_cancelamento_nfse_horas is null or prazo_cancelamento_nfse_horas > 0);
comment on column c.empresa_fiscal.serie_dps is 'Serie da DPS (NFS-e Nacional) numerada pelo ERP. Faixa da API Focus: 1 a 49999. O emissor antigo usa 70000.';
comment on column c.empresa_fiscal.proximo_numero_dps is 'Proximo numero de DPS. Incrementado por f.fn_proximo_numero_dps dentro da transacao do rascunho; numero nunca reutilizado (f.dps_numero_log).';
comment on column c.empresa_fiscal.codigo_opcao_simples_nacional is 'opSimpNac: 1 nao optante, 2 MEI, 3 ME/EPP.';
comment on column c.empresa_fiscal.regime_especial_tributacao is 'regEspTrib: 0 nenhum, 1 cooperativa, 2 estimativa, 3 microempresa municipal, 4 notario, 5 autonomo, 6 sociedade de profissionais, 9 outros.';
comment on column c.empresa_fiscal.prazo_cancelamento_nfse_horas is 'Prazo de cancelamento da NFS-e Nacional em horas. Vazio = nao confirmado pelo contador: em producao o cancelamento nao aparece, so a substituicao.';

-- Valores da Eletrica Segau (tarefa de 05/09/2026): serie 2 (proposta, a
-- confirmar pelo Gabriel), proximo 1, nao optante do Simples, sem regime
-- especial, IM 152836. Nada e sobrescrito onde ja existe valor.
update c.empresa_fiscal ef
set serie_dps = coalesce(ef.serie_dps, 2),
    codigo_opcao_simples_nacional = coalesce(ef.codigo_opcao_simples_nacional, 1),
    regime_especial_tributacao = coalesce(ef.regime_especial_tributacao, 0),
    inscricao_municipal = coalesce(nullif(btrim(ef.inscricao_municipal), ''), '152836'),
    updated_at = now()
from c.empresa e
where e.id = ef.empresa_id
  and ef.deleted_at is null
  and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') = '13671448000189';

-- ---------------------------------------------------------------------------
-- 2. Clientes (tomadores)
-- ---------------------------------------------------------------------------
alter table public.clientes
  add column if not exists iss_retido boolean,
  add column if not exists retem_pcc boolean,
  add column if not exists retem_irrf boolean,
  add column if not exists retem_inss boolean,
  add column if not exists email_nfse text;
alter table public.clientes drop constraint if exists clientes_email_nfse_ck;
alter table public.clientes add constraint clientes_email_nfse_ck
  check (email_nfse is null or email_nfse ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$');
comment on column public.clientes.iss_retido is 'Decisao humana: o tomador retem o ISS? Nulo = nao decidido (a tela bloqueia quando a regra do perfil e POR_TOMADOR). Nunca gravado por deducao.';
comment on column public.clientes.retem_pcc is 'Decisao humana: o tomador retem PIS/COFINS/CSLL (4,65%)? Nulo = nao decidido.';
comment on column public.clientes.retem_irrf is 'Decisao humana: o tomador retem IRRF (1,5%)? Nulo = nao decidido.';
comment on column public.clientes.retem_inss is 'Decisao humana: o tomador retem INSS (11%)? Nulo = nao decidido.';
comment on column public.clientes.email_nfse is 'E-mail para envio da NFS-e (email_tomador). Vazio gera aviso, nao bloqueio.';

-- ---------------------------------------------------------------------------
-- 3. Perfis de servico (sem valor fiscal)
-- ---------------------------------------------------------------------------
alter table f.perfil_operacao
  add column if not exists codigo_tributacao_nacional text,
  add column if not exists codigo_tributacao_municipal text,
  add column if not exists codigo_nbs text,
  add column if not exists descricao_servico_padrao text,
  add column if not exists local_prestacao_regra text,
  add column if not exists tributacao_iss smallint,
  add column if not exists aliquota_iss numeric(5,2),
  add column if not exists iss_retido_regra text,
  add column if not exists retencao_pcc_regra text,
  add column if not exists aliquota_pcc numeric(5,2),
  add column if not exists retencao_irrf_regra text,
  add column if not exists aliquota_irrf numeric(5,2),
  add column if not exists retencao_inss_regra text,
  add column if not exists aliquota_inss numeric(5,2),
  add column if not exists permite_deducao_material boolean,
  add column if not exists texto_complementar text;
alter table f.perfil_operacao drop constraint if exists perfil_operacao_servico_codigos_ck;
alter table f.perfil_operacao add constraint perfil_operacao_servico_codigos_ck check (
  (codigo_tributacao_nacional is null or codigo_tributacao_nacional ~ '^[0-9]{6}$')
  and (codigo_tributacao_municipal is null or codigo_tributacao_municipal ~ '^[0-9A-Za-z]{1,3}$')
  and (codigo_nbs is null or codigo_nbs ~ '^[0-9]{9}$')
  and (local_prestacao_regra is null or local_prestacao_regra in ('SEDE', 'CLIENTE'))
  and (tributacao_iss is null or tributacao_iss in (1, 2, 3, 4))
  and (iss_retido_regra is null or iss_retido_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR'))
  and (retencao_pcc_regra is null or retencao_pcc_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR'))
  and (retencao_irrf_regra is null or retencao_irrf_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR'))
  and (retencao_inss_regra is null or retencao_inss_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR'))
);
comment on column f.perfil_operacao.codigo_tributacao_nacional is 'cTribNac (6 digitos). Vazio ate o contador confirmar; homologacao usa f.tributacao_provisoria_nfse_homologacao.';
comment on column f.perfil_operacao.local_prestacao_regra is 'SEDE: municipio da empresa. CLIENTE: municipio do tomador. Editavel na tela.';
comment on column f.perfil_operacao.iss_retido_regra is 'NUNCA, SEMPRE ou POR_TOMADOR (decide clientes.iss_retido; nulo bloqueia).';

insert into f.perfil_operacao (
  tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  item_servico, faixa_automacao, justificativa_faixa, habilitado_producao, vigencia_inicio, observacao
)
select e.tenant_id, e.id, p.codigo, p.nome, 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO',
       coalesce(ef.crt::text, '3'), p.item_servico, p.faixa, p.justificativa, false, current_date,
       'Perfil de NFS-e Nacional criado sem valor fiscal em 05/09/2026. Codigo de tributacao, NBS, ISS, PIS/COFINS, retencoes e cClassTrib aguardam o contador; a homologacao usa a fixture provisoria.'
from c.empresa e
join c.empresa_fiscal ef on ef.empresa_id = e.id and ef.deleted_at is null
cross join (values
  ('SEG-NFSE-1406', 'Servico 14.06 - Instalacao e montagem', '14.06', 'REVISAO', null),
  ('SEG-NFSE-1709', 'Servico 17.09 - Laudos, pericias e analises tecnicas', '17.09', 'REVISAO', null),
  ('SEG-NFSE-1706', 'Servico 17.06 - Assessoria (codigo usado pelo emissor antigo; confirmar)', '17.06', 'REVISAO', null),
  ('SEG-NFSE-1401', 'Servico 14.01 - Manutencao e conservacao', '14.01', 'REVISAO', null),
  ('SEG-NFSE-0702', 'Servico 07.02 - Execucao de obra (eletrica)', '07.02', 'BLOQUEADO',
   'Obra de construcao civil: exige endereco da obra, INSS sobre mao de obra e regras proprias de retencao; bloqueado ate o contador definir.')
) as p(codigo, nome, item_servico, faixa, justificativa)
where e.deleted_at is null
  and not exists (
    select 1 from f.perfil_operacao po
    where po.tenant_id = e.tenant_id and po.empresa_id = e.id and po.codigo = p.codigo
  );

-- ---------------------------------------------------------------------------
-- 4. Fixture provisoria de servico (homologacao)
-- ---------------------------------------------------------------------------
create table if not exists f.tributacao_provisoria_nfse_homologacao (
  tenant_id uuid not null,
  empresa_id uuid not null,
  item_servico text not null,
  codigo_tributacao_nacional text not null check (codigo_tributacao_nacional ~ '^[0-9]{6}$'),
  codigo_tributacao_municipal text,
  codigo_nbs text check (codigo_nbs is null or codigo_nbs ~ '^[0-9]{9}$'),
  descricao_servico_padrao text not null,
  local_prestacao_regra text not null check (local_prestacao_regra in ('SEDE', 'CLIENTE')),
  tributacao_iss smallint not null default 1 check (tributacao_iss in (1, 2, 3, 4)),
  aliquota_iss numeric(5,2),
  iss_retido_regra text not null check (iss_retido_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')),
  cst_pis_cofins text not null default '01',
  aliquota_pis numeric(5,2) not null,
  aliquota_cofins numeric(5,2) not null,
  retencao_pcc_regra text not null check (retencao_pcc_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')),
  aliquota_pcc numeric(5,2),
  retencao_irrf_regra text not null check (retencao_irrf_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')),
  aliquota_irrf numeric(5,2),
  retencao_inss_regra text not null check (retencao_inss_regra in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')),
  aliquota_inss numeric(5,2),
  cst_ibs_cbs text not null default '000',
  cclass_trib text not null default '000001',
  ibs_uf_aliquota numeric(7,4) not null default 0.1000,
  ibs_mun_aliquota numeric(7,4) not null default 0.0000,
  cbs_aliquota numeric(7,4) not null default 0.9000,
  consumidor_final smallint not null default 0 check (consumidor_final in (0, 1)),
  texto_sem_retencao text,
  texto_com_retencao text,
  ativo boolean not null default true,
  pendencia_contador text not null,
  fonte text not null,
  criado_em timestamptz not null default now(),
  primary key (tenant_id, empresa_id, item_servico)
);
comment on table f.tributacao_provisoria_nfse_homologacao is
  'Fixture provisoria de NFS-e para HOMOLOGACAO. Valores lidos das NFS-e importadas (12-40 de agosto/2026, f.documento_fiscal_xml). Nenhum valor daqui entra em f.perfil_operacao; producao exige perfil liberado.';
grant select on f.tributacao_provisoria_nfse_homologacao to authenticated;
grant all on f.tributacao_provisoria_nfse_homologacao to service_role;

insert into f.tributacao_provisoria_nfse_homologacao (
  tenant_id, empresa_id, item_servico, codigo_tributacao_nacional, codigo_nbs, descricao_servico_padrao,
  local_prestacao_regra, aliquota_iss, iss_retido_regra, aliquota_pis, aliquota_cofins,
  retencao_pcc_regra, aliquota_pcc, retencao_irrf_regra, aliquota_irrf, retencao_inss_regra, aliquota_inss,
  texto_sem_retencao, texto_com_retencao, pendencia_contador, fonte
)
select e.tenant_id, e.id, x.item, x.ctrib, x.nbs, x.descricao, x.local, x.aliq, x.iss_regra, 1.65, 7.60,
       x.pcc_regra, 4.65, x.irrf_regra, 1.50, x.inss_regra, 11.00,
       'NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004',
       'PARA OS SERVICOS DE LAUDOS E PERICIAS, DEVERA SER RETIDO IRRF A ALIQUOTA DE 1,5% E CRF A ALIQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1%). TRIBUTOS INCIDENTES SOBRE O PRECO LEI 12/2012',
       x.pendencia, x.fonte
from c.empresa e
join c.empresa_fiscal ef on ef.empresa_id = e.id and ef.deleted_at is null
cross join (values
  ('14.06', '140601', '120032900', 'SERVICOS DE INSTALACAO E MONTAGEM', 'CLIENTE', 5.00::numeric,
   'POR_TOMADOR', 'POR_TOMADOR', 'POR_TOMADOR', 'POR_TOMADOR',
   'Confirmar NBS (120032900 em 14 notas; 101061900 e 101026900 em 3), alíquota por municipio de incidencia e quando ha INSS (WEG).',
   'NFS-e 31-38 de ago/2026: cTribNac 140601, cNBS 120032900, ISS 5% Joinville, PIS/COFINS CST 01; Portobello sem retencao; WEG com INSS 11%.'),
  ('17.09', '170901', '114044900', 'LAUDO TECNICO', 'SEDE', 5.00::numeric,
   'POR_TOMADOR', 'POR_TOMADOR', 'POR_TOMADOR', 'NUNCA',
   'Confirmar retencoes de IRRF 1,5% e CRF 4,65% em todos os laudos e o texto legal.',
   'NFS-e 29, 30, 36, 39 e 40 de ago/2026: cTribNac 170901, cNBS 114044900, ISS retido pelo tomador, IRRF 1,5%, PIS/COFINS/CSLL 4,65%.'),
  ('17.06', '170601', '114044900', 'SERVICO DE ASSESSORIA TECNICA', 'SEDE', 5.00::numeric,
   'POR_TOMADOR', 'POR_TOMADOR', 'POR_TOMADOR', 'NUNCA',
   'Na LC 116 o item 17.06 e propaganda e publicidade; o emissor antigo usou 170601 para assessoria (INCASA). Confirmar se o correto e 17.01 (assessoria/consultoria).',
   'Uma NFS-e de 2026 para INCASA com cTribNac 170601 e cNBS 114044900, ISS retido.'),
  ('14.01', '140101', null, 'SERVICO DE MANUTENCAO', 'CLIENTE', 5.00::numeric,
   'POR_TOMADOR', 'POR_TOMADOR', 'POR_TOMADOR', 'POR_TOMADOR',
   'Sem NBS observado nas notas recentes; confirmar NBS e se manutencao em planta do cliente recolhe ISS no municipio do tomador.',
   'NFS-e de Portobello/WEG com cTribNac 140101 (jul-ago/2026); Portobello sem retencao, WEG com INSS.'),
  ('07.02', '070201', '101069000', 'EXECUCAO DE OBRA ELETRICA', 'CLIENTE', null::numeric,
   'POR_TOMADOR', 'POR_TOMADOR', 'POR_TOMADOR', 'SEMPRE',
   'Perfil BLOQUEADO: obra exige endereco da obra, INSS 11% sobre mao de obra, aliquota do municipio da obra (3% em Sao Francisco do Sul) e possivel deducao de material.',
   'NFS-e 37 de ago/2026 (ArcelorMittal): cTribNac 070201, cNBS 101069000, ISS 3% retido, INSS 11%, grupo IBSCBS 000/000001.')
) as x(item, ctrib, nbs, descricao, local, aliq, iss_regra, pcc_regra, irrf_regra, inss_regra, pendencia, fonte)
where e.deleted_at is null
on conflict (tenant_id, empresa_id, item_servico) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Solicitacao e linhas
-- ---------------------------------------------------------------------------
alter table f.solicitacao_faturamento
  add column if not exists municipio_prestacao_ibge text,
  add column if not exists data_competencia date,
  add column if not exists pedido_item text,
  add column if not exists iss_retido boolean,
  add column if not exists retem_pcc boolean,
  add column if not exists retem_irrf boolean,
  add column if not exists retem_inss boolean,
  add column if not exists retencao_justificativa text,
  add column if not exists substitui_solicitacao_id uuid,
  add column if not exists substitui_documento_fiscal_id uuid,
  add column if not exists substituicao_codigo text,
  add column if not exists substituicao_motivo text;
alter table f.solicitacao_faturamento drop constraint if exists solicitacao_faturamento_nfse_ck;
alter table f.solicitacao_faturamento add constraint solicitacao_faturamento_nfse_ck check (
  (municipio_prestacao_ibge is null or municipio_prestacao_ibge ~ '^[0-9]{7}$')
  and (substituicao_codigo is null or substituicao_codigo in ('01', '02', '03', '04', '05', '99'))
  and (substituicao_motivo is null or char_length(btrim(substituicao_motivo)) between 15 and 255)
);
comment on column f.solicitacao_faturamento.iss_retido is 'Decisao aplicada nesta nota (cliente ou override com retencao_justificativa).';

alter table f.solicitacao_item
  add column if not exists modelo text not null default 'NFE',
  add column if not exists descricao_servico text,
  add column if not exists valor_servico numeric(15,2),
  add column if not exists codigo_tributacao_nacional text,
  add column if not exists codigo_tributacao_municipal text,
  add column if not exists codigo_nbs text,
  add column if not exists tributacao_iss smallint,
  add column if not exists aliquota_iss numeric(5,2),
  add column if not exists iss_retido boolean,
  add column if not exists aliquota_irrf numeric(5,2),
  add column if not exists aliquota_inss numeric(5,2),
  add column if not exists aliquota_pcc numeric(5,2),
  add column if not exists local_prestacao_ibge text;
alter table f.solicitacao_item drop constraint if exists solicitacao_item_modelo_check;
alter table f.solicitacao_item add constraint solicitacao_item_modelo_check check (modelo in ('NFE', 'NFSE'));
alter table f.solicitacao_item drop constraint if exists solicitacao_item_servico_ck;
alter table f.solicitacao_item add constraint solicitacao_item_servico_ck check (
  (modelo = 'NFE' and valor_servico is null)
  or (modelo = 'NFSE' and valor_servico is not null and valor_servico > 0)
);
comment on column f.solicitacao_item.modelo is 'NFE: linha de mercadoria. NFSE: linha de servico por valor (origem OS por linha).';

-- ---------------------------------------------------------------------------
-- 6. Emissao e eventos
-- ---------------------------------------------------------------------------
alter table f.documento_fiscal_emissao
  add column if not exists modelo text not null default 'NFE',
  add column if not exists dps_serie smallint,
  add column if not exists dps_numero bigint,
  add column if not exists nfse_numero text,
  add column if not exists chave_nfse text,
  add column if not exists codigo_verificacao text,
  add column if not exists municipio_prestacao_ibge text,
  add column if not exists iss_retido boolean,
  add column if not exists valor_iss numeric(15,2),
  add column if not exists valor_deducoes numeric(15,2),
  add column if not exists retencoes jsonb,
  add column if not exists valor_liquido numeric(15,2),
  add column if not exists chave_nfse_substituida text,
  add column if not exists substituicao_codigo text,
  add column if not exists substituicao_motivo text;
alter table f.documento_fiscal_emissao drop constraint if exists documento_fiscal_emissao_modelo_check;
alter table f.documento_fiscal_emissao add constraint documento_fiscal_emissao_modelo_check check (modelo in ('NFE', 'NFSE'));
alter table f.documento_fiscal_emissao drop constraint if exists documento_fiscal_emissao_nfse_ck;
alter table f.documento_fiscal_emissao add constraint documento_fiscal_emissao_nfse_ck check (
  (chave_nfse is null or char_length(chave_nfse) <= 50)
  and (chave_nfse_substituida is null or char_length(chave_nfse_substituida) <= 50)
  and (retencoes is null or jsonb_typeof(retencoes) = 'array')
  and (modelo = 'NFE' or (dps_serie is not null and dps_numero is not null))
);
create index if not exists idx_documento_fiscal_emissao_chave_nfse on f.documento_fiscal_emissao (chave_nfse) where chave_nfse is not null;
comment on column f.documento_fiscal_emissao.retencoes is 'Lista [{tributo, base, aliquota, valor}] congelada na preparacao; origem de f.titulo_retencao em producao.';

alter table f.documento_fiscal_evento
  add column if not exists codigo_motivo text,
  add column if not exists chave_nova text,
  add column if not exists chave_substituida text;

-- ---------------------------------------------------------------------------
-- 7. Numeracao da DPS
-- ---------------------------------------------------------------------------
create table if not exists f.dps_numero_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  serie smallint not null,
  numero bigint not null,
  documento_fiscal_id uuid,
  referencia_externa text,
  resultado text not null check (resultado in ('RESERVADO', 'AUTORIZADO', 'REJEITADO', 'ERRO', 'CANCELADO', 'SUBSTITUIDO', 'ABANDONADO')),
  mensagem text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, empresa_id, serie, numero)
);
comment on table f.dps_numero_log is 'Cada numero de DPS reservado pelo ERP e seu destino. Um numero rejeitado fica queimado; o retry recebe outro numero.';
alter table f.dps_numero_log enable row level security;
drop policy if exists dps_numero_log_select on f.dps_numero_log;
create policy dps_numero_log_select on f.dps_numero_log for select to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access());
grant select on f.dps_numero_log to authenticated;
grant all on f.dps_numero_log to service_role;
create index if not exists idx_dps_numero_log_documento on f.dps_numero_log (documento_fiscal_id);

create or replace function f.fn_proximo_numero_dps(p_empresa_id uuid)
returns table (serie smallint, numero bigint)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_fiscal c.empresa_fiscal%rowtype;
begin
  -- Chamada somente de dentro das funcoes fiscais (security definer) ou do backend.
  if current_user not in ('postgres', 'service_role') and session_user <> 'postgres' then
    raise exception using errcode = '42501', message = 'A numeracao da DPS e reservada ao pipeline fiscal.';
  end if;
  select ef.* into v_fiscal
  from c.empresa_fiscal ef
  where ef.empresa_id = p_empresa_id and ef.deleted_at is null
  order by ef.updated_at desc
  limit 1
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'Empresa sem cadastro fiscal; nao ha serie de DPS.';
  end if;
  if v_fiscal.serie_dps is null then
    raise exception using errcode = '22023', message = 'Serie da DPS nao configurada em c.empresa_fiscal.serie_dps.';
  end if;
  serie := v_fiscal.serie_dps;
  numero := v_fiscal.proximo_numero_dps;
  update c.empresa_fiscal set proximo_numero_dps = v_fiscal.proximo_numero_dps + 1, updated_at = now()
  where id = v_fiscal.id;
  return next;
end;
$$;
revoke all on function f.fn_proximo_numero_dps(uuid) from public;
grant execute on function f.fn_proximo_numero_dps(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 8. Retencao por tributo no titulo
-- ---------------------------------------------------------------------------
create table if not exists f.titulo_retencao (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  titulo_id uuid not null references f.titulo(id),
  documento_fiscal_id uuid,
  tributo text not null check (tributo in ('ISS', 'INSS', 'IRRF', 'PIS', 'COFINS', 'CSLL')),
  base numeric(15,2) not null,
  aliquota numeric(7,4) not null,
  valor numeric(15,2) not null,
  created_at timestamptz not null default now(),
  unique (titulo_id, tributo)
);
comment on table f.titulo_retencao is 'Retencoes por tributo do titulo a receber gerado por NFS-e emitida: titulo.valor_total = bruto - soma(valor).';
alter table f.titulo_retencao enable row level security;
drop policy if exists titulo_retencao_select on f.titulo_retencao;
create policy titulo_retencao_select on f.titulo_retencao for select to authenticated
  using (tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and f.has_finance_access());
grant select on f.titulo_retencao to authenticated;
grant all on f.titulo_retencao to service_role;
create index if not exists idx_titulo_retencao_titulo on f.titulo_retencao (titulo_id);

-- ---------------------------------------------------------------------------
-- 9. Lista de notas da OS com o modelo
-- ---------------------------------------------------------------------------
drop function if exists f.fn_os_notas(uuid, uuid, integer);
create function f.fn_os_notas(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  solicitacao_status text,
  modelo text,
  ambiente text,
  emissao_status text,
  nfe_status text,
  serie text,
  numero text,
  chave_acesso text,
  valor_total numeric,
  autorizado_em timestamptz,
  danfe_path text,
  xml_path text,
  referencia_externa text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select d.id, e.solicitacao_id, s.status,
         case when upper(coalesce(d.modelo, '')) = 'NFSE' then 'NFSE' else 'NFE' end,
         e.ambiente, e.status,
         case when upper(coalesce(d.modelo, '')) = 'NFSE' then d.nfse_status else d.nfe_status end,
         coalesce(e.dps_serie::text, d.serie), coalesce(e.nfse_numero, d.numero),
         coalesce(e.chave_nfse, d.chave_acesso), d.valor_total, e.autorizado_em,
         e.danfe_path, e.xml_path, e.referencia_externa, e.created_at
  from f.documento_fiscal d
  join f.documento_fiscal_emissao e
    on e.tenant_id = d.tenant_id and e.empresa_id = d.empresa_id and e.documento_fiscal_id = d.id
  left join f.solicitacao_faturamento s
    on s.tenant_id = e.tenant_id and s.empresa_id = e.empresa_id and s.id = e.solicitacao_id
  where d.tenant_id = p_tenant_id and d.empresa_id = p_empresa_id
    and d.operacao = 'SAIDA' and d.deleted_at is null
    and (
      d.os_id_import = p_os_id
      or exists (
        select 1 from f.solicitacao_item si
        where si.tenant_id = e.tenant_id and si.empresa_id = e.empresa_id and si.solicitacao_id = e.solicitacao_id
          and si.origem_tipo = 'OS' and si.origem_id = p_os_id::text
      )
    )
    and (session_user = 'postgres' or coalesce(auth.jwt()->>'role', '') = 'service_role'
         or (public.current_tenant_id() = p_tenant_id and public.current_empresa_id() = p_empresa_id and f.has_finance_access()))
  order by e.created_at desc;
$$;
revoke all on function f.fn_os_notas(uuid, uuid, integer) from public;
grant execute on function f.fn_os_notas(uuid, uuid, integer) to authenticated, service_role;
