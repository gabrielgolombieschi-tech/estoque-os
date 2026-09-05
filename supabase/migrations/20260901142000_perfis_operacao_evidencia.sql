begin;

create table f.perfil_operacao_evidencia (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references c.tenant(id),
  empresa_id uuid not null,
  fonte text not null,
  fonte_linha integer not null check (fonte_linha > 0),
  natureza_texto text not null,
  cfop text not null check (cfop ~ '^[0-9]{4}$'),
  origem smallint not null check (origem between 0 and 8),
  cst_completo text not null check (cst_completo ~ '^[0-9]{3}$'),
  cst_icms text not null check (cst_icms ~ '^[0-9]{2}$'),
  aliquota_icms_observada numeric(7,4) not null check (aliquota_icms_observada between 0 and 100),
  aliquota_ipi_observada numeric(7,4) not null check (aliquota_ipi_observada between 0 and 100),
  base_reduzida_observada boolean not null,
  itens_observados integer not null check (itens_observados > 0),
  notas_observadas integer not null check (notas_observadas > 0),
  ncms text[] not null,
  notas_exemplo integer[] not null,
  leitura_operacional text not null,
  faixa text not null check (faixa in ('AUTOMATICO', 'REVISAO', 'BLOQUEADO')),
  justificativa_faixa text not null,
  divergencia_ipi boolean not null default false,
  divergencia_fabricado_revenda boolean not null default false,
  divergencia_cabo_beneficio boolean not null default false,
  perfil_operacao_id uuid,
  xml_notas integer not null default 0,
  xml_itens integer not null default 0,
  xml_pis_csts text[] not null default '{}',
  xml_cofins_csts text[] not null default '{}',
  xml_pis_aliquotas numeric[] not null default '{}',
  xml_cofins_aliquotas numeric[] not null default '{}',
  xml_ipi_csts text[] not null default '{}',
  xml_cbenef_valores text[] not null default '{}',
  xml_cbenef_ausente_itens integer not null default 0,
  xml_fci_itens integer not null default 0,
  xml_divergente boolean not null default false,
  xml_extraido_em timestamptz,
  created_at timestamptz not null default now(),
  constraint perfil_operacao_evidencia_empresa_fk
    foreign key (tenant_id, empresa_id) references c.empresa(tenant_id, id),
  unique (tenant_id, empresa_id, fonte, fonte_linha)
);

alter table f.perfil_operacao
  add column evidencia_id uuid,
  add column faixa_automacao text not null default 'REVISAO'
    check (faixa_automacao in ('AUTOMATICO', 'REVISAO', 'BLOQUEADO')),
  add column justificativa_faixa text,
  add column origem_mercadoria smallint check (origem_mercadoria is null or origem_mercadoria between 0 and 8),
  add column aliquota_icms numeric(7,4) check (aliquota_icms is null or aliquota_icms between 0 and 100),
  add column aliquota_ipi numeric(7,4) check (aliquota_ipi is null or aliquota_ipi between 0 and 100),
  add column aliquota_pis numeric(7,4) check (aliquota_pis is null or aliquota_pis between 0 and 100),
  add column aliquota_cofins numeric(7,4) check (aliquota_cofins is null or aliquota_cofins between 0 and 100),
  add column percentual_base_calculo numeric(7,4)
    check (percentual_base_calculo is null or percentual_base_calculo between 0 and 100),
  add column informacoes_complementares_modelo text,
  add column habilitado_producao boolean not null default false,
  add constraint perfil_operacao_evidencia_fk
    foreign key (evidencia_id) references f.perfil_operacao_evidencia(id),
  add constraint perfil_operacao_beneficio_completo_ck
    check (
      coalesce(reducao_base_icms_percentual, 0) = 0
      or (
        nullif(btrim(cbenef), '') is not null
        and nullif(btrim(beneficio_texto_legal), '') is not null
        and percentual_base_calculo is not null
      )
    ),
  add constraint perfil_operacao_bloqueado_producao_ck
    check (faixa_automacao <> 'BLOQUEADO' or habilitado_producao is false);

alter table f.perfil_operacao_evidencia
  add constraint perfil_operacao_evidencia_perfil_fk
    foreign key (perfil_operacao_id) references f.perfil_operacao(id);

alter table f.solicitacao_faturamento
  add column revisao_fiscal_confirmada_em timestamptz,
  add column revisao_fiscal_confirmada_por uuid references a.usuario(id) on delete set null,
  add constraint solicitacao_revisao_fiscal_par_ck
    check (
      (revisao_fiscal_confirmada_em is null) =
      (revisao_fiscal_confirmada_por is null)
    );

comment on column f.perfil_operacao.aliquota_ipi is
  'Permanece nula ate revisao na TIPI. Zero observado em DANFE nao e regra automatica.';
comment on column f.perfil_operacao.percentual_base_calculo is
  'Percentual da base integral que permanece tributavel. Para o beneficio SC: 70,5880.';
comment on column f.perfil_operacao.habilitado_producao is
  'Liberacao explicita posterior. Os perfis empiricos entram false e nao abrem producao.';
comment on column f.perfil_operacao_evidencia.xml_fci_itens is
  'Quantidade de itens de XML com nFCI preenchido; FCI continua atributo/controle por item.';

create index perfil_operacao_evidencia_busca_idx
  on f.perfil_operacao_evidencia (tenant_id, empresa_id, natureza_texto, cfop, origem, cst_icms);
create index perfil_operacao_evidencia_faixa_idx
  on f.perfil_operacao_evidencia (tenant_id, empresa_id, faixa);
create unique index perfil_operacao_evidencia_id_ux
  on f.perfil_operacao (evidencia_id)
  where evidencia_id is not null;

alter table f.perfil_operacao_evidencia enable row level security;
create policy perfil_operacao_evidencia_select
  on f.perfil_operacao_evidencia
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access()
  );

grant select on f.perfil_operacao_evidencia to authenticated;
grant select, insert, update, delete on f.perfil_operacao_evidencia to service_role;

create or replace function f.fn_extrair_perfis_operacao_xml_saida(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_evidencias integer := 0;
  v_com_xml integer := 0;
  v_divergentes integer := 0;
  v_beneficio_ok integer := 0;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception 'Apenas service_role pode extrair evidencia fiscal dos XMLs.';
  end if;
  if not exists (
    select 1 from c.empresa e
    where e.tenant_id = p_tenant_id and e.id = p_empresa_id
      and e.codigo = 'SEG' and e.ativo and e.deleted_at is null
  ) then
    raise exception 'A extracao desta matriz e exclusiva da empresa SEG.';
  end if;

  with documentos as materialized (
    select df.id, xmlparse(document dfx.xml_raw) as doc
    from f.documento_fiscal df
    join f.documento_fiscal_xml dfx
      on dfx.tenant_id = df.tenant_id
     and dfx.documento_fiscal_id = df.id
     and dfx.deleted_at is null
    where df.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and df.deleted_at is null
      and df.operacao = 'SAIDA'
      and coalesce(df.modelo, '55') = '55'
      and nullif(btrim(dfx.xml_raw), '') is not null
  ), linhas as materialized (
    select d.id as documento_id,
      public.normalizar_nome_municipio(x.natureza) as natureza_normalizada,
      btrim(x.cfop) as cfop,
      case when btrim(x.origem) ~ '^[0-8]$' then btrim(x.origem)::smallint end as origem,
      lpad(btrim(x.cst_icms), 2, '0') as cst_icms,
      nullif(lpad(btrim(x.cst_pis), 2, '0'), '00') as cst_pis,
      nullif(lpad(btrim(x.cst_cofins), 2, '0'), '00') as cst_cofins,
      nullif(lpad(btrim(x.cst_ipi), 2, '0'), '00') as cst_ipi,
      case when btrim(x.aliquota_pis) ~ '^[0-9]+([.,][0-9]+)?$'
        then replace(btrim(x.aliquota_pis), ',', '.')::numeric end as aliquota_pis,
      case when btrim(x.aliquota_cofins) ~ '^[0-9]+([.,][0-9]+)?$'
        then replace(btrim(x.aliquota_cofins), ',', '.')::numeric end as aliquota_cofins,
      nullif(btrim(x.cbenef), '') as cbenef,
      nullif(btrim(x.nfci), '') as nfci
    from documentos d
    cross join lateral xmltable(
      xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
      '//n:det' passing d.doc columns
        natureza text path 'string(../n:ide/n:natOp)',
        cfop text path 'string(n:prod/n:CFOP)',
        origem text path 'string(n:imposto/n:ICMS/*/n:orig)',
        cst_icms text path 'string(n:imposto/n:ICMS/*/n:CST)',
        cst_pis text path 'string(n:imposto/n:PIS/*/n:CST)',
        cst_cofins text path 'string(n:imposto/n:COFINS/*/n:CST)',
        cst_ipi text path 'string(n:imposto/n:IPI/*/n:CST)',
        aliquota_pis text path 'string(n:imposto/n:PIS/*/n:pPIS)',
        aliquota_cofins text path 'string(n:imposto/n:COFINS/*/n:pCOFINS)',
        cbenef text path 'string(n:imposto/n:ICMS/*/n:cBenef)',
        nfci text path 'string(n:prod/n:nFCI)'
    ) x
  ), agregado as materialized (
    select e.id as evidencia_id,
      count(distinct l.documento_id)::integer as xml_notas,
      count(*)::integer as xml_itens,
      coalesce(array_agg(distinct l.cst_pis order by l.cst_pis)
        filter (where l.cst_pis is not null), '{}') as pis_csts,
      coalesce(array_agg(distinct l.cst_cofins order by l.cst_cofins)
        filter (where l.cst_cofins is not null), '{}') as cofins_csts,
      coalesce(array_agg(distinct l.aliquota_pis order by l.aliquota_pis)
        filter (where l.aliquota_pis is not null), '{}') as pis_aliquotas,
      coalesce(array_agg(distinct l.aliquota_cofins order by l.aliquota_cofins)
        filter (where l.aliquota_cofins is not null), '{}') as cofins_aliquotas,
      coalesce(array_agg(distinct l.cst_ipi order by l.cst_ipi)
        filter (where l.cst_ipi is not null), '{}') as ipi_csts,
      coalesce(array_agg(distinct l.cbenef order by l.cbenef)
        filter (where l.cbenef is not null), '{}') as cbenef_valores,
      count(*) filter (where l.cbenef is null)::integer as cbenef_ausente,
      count(*) filter (where l.nfci is not null)::integer as fci_itens
    from f.perfil_operacao_evidencia e
    join linhas l
      on l.natureza_normalizada = public.normalizar_nome_municipio(e.natureza_texto)
     and l.cfop = e.cfop
     and l.origem = e.origem
     and l.cst_icms = e.cst_icms
    where e.tenant_id = p_tenant_id
      and e.empresa_id = p_empresa_id
    group by e.id
  )
  update f.perfil_operacao_evidencia e
     set xml_notas = coalesce(a.xml_notas, 0),
         xml_itens = coalesce(a.xml_itens, 0),
         xml_pis_csts = coalesce(a.pis_csts, '{}'),
         xml_cofins_csts = coalesce(a.cofins_csts, '{}'),
         xml_pis_aliquotas = coalesce(a.pis_aliquotas, '{}'),
         xml_cofins_aliquotas = coalesce(a.cofins_aliquotas, '{}'),
         xml_ipi_csts = coalesce(a.ipi_csts, '{}'),
         xml_cbenef_valores = coalesce(a.cbenef_valores, '{}'),
         xml_cbenef_ausente_itens = coalesce(a.cbenef_ausente, 0),
         xml_fci_itens = coalesce(a.fci_itens, 0),
         xml_divergente = coalesce(
           cardinality(a.pis_csts) > 1
           or cardinality(a.cofins_csts) > 1
           or cardinality(a.pis_aliquotas) > 1
           or cardinality(a.cofins_aliquotas) > 1
           or cardinality(a.ipi_csts) > 1
           or cardinality(a.cbenef_valores) > 1
           or (cardinality(a.cbenef_valores) > 0 and a.cbenef_ausente > 0),
           false
         ),
         xml_extraido_em = now()
    from (select e0.id, a0.* from f.perfil_operacao_evidencia e0 left join agregado a0 on a0.evidencia_id = e0.id
          where e0.tenant_id = p_tenant_id and e0.empresa_id = p_empresa_id) a
   where e.id = a.id;

  update f.perfil_operacao po
     set cst_pis = case when cardinality(e.xml_pis_csts) = 1 then e.xml_pis_csts[1] else null end,
         cst_cofins = case when cardinality(e.xml_cofins_csts) = 1 then e.xml_cofins_csts[1] else null end,
         cst_ipi = case when cardinality(e.xml_ipi_csts) = 1 then e.xml_ipi_csts[1] else null end,
         aliquota_pis = case when cardinality(e.xml_pis_aliquotas) = 1 then e.xml_pis_aliquotas[1] else null end,
         aliquota_cofins = case when cardinality(e.xml_cofins_aliquotas) = 1 then e.xml_cofins_aliquotas[1] else null end,
         faixa_automacao = case
           when po.faixa_automacao = 'AUTOMATICO'
             and (
               cardinality(e.xml_ipi_csts) <> 1
               or e.xml_ipi_csts[1] in ('50', '99')
               or e.xml_divergente
             ) then 'REVISAO'
           else po.faixa_automacao
         end,
         justificativa_faixa = case
           when po.faixa_automacao = 'AUTOMATICO'
             and (
               cardinality(e.xml_ipi_csts) <> 1
               or e.xml_ipi_csts[1] in ('50', '99')
               or e.xml_divergente
             ) then po.justificativa_faixa || '; XML nao fechou IPI nao tributado de forma unanime'
           else po.justificativa_faixa
         end
    from f.perfil_operacao_evidencia e
   where po.evidencia_id = e.id
     and e.tenant_id = p_tenant_id
     and e.empresa_id = p_empresa_id;

  select count(*),
         count(*) filter (where xml_itens > 0),
         count(*) filter (where xml_divergente),
         count(*) filter (
           where base_reduzida_observada
             and xml_cbenef_valores = array['SC820006']::text[]
             and xml_cbenef_ausente_itens = 0
         )
    into v_evidencias, v_com_xml, v_divergentes, v_beneficio_ok
  from f.perfil_operacao_evidencia
  where tenant_id = p_tenant_id and empresa_id = p_empresa_id;

  return jsonb_build_object(
    'evidencias', v_evidencias,
    'com_xml', v_com_xml,
    'divergentes', v_divergentes,
    'beneficio_sc820006_unanime', v_beneficio_ok
  );
end;
$function$;

revoke all on function f.fn_extrair_perfis_operacao_xml_saida(uuid, uuid)
  from public, anon, authenticated;
grant execute on function f.fn_extrair_perfis_operacao_xml_saida(uuid, uuid)
  to service_role;

create or replace function f.trg_bloquear_nfe_producao_sem_perfil_liberado()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_perfil_id uuid;
  v_habilitado_producao boolean;
  v_faixa_automacao text;
  v_confirmada timestamptz;
begin
  if new.ambiente <> 'PRODUCAO' then
    return new;
  end if;

  select po.id,
         po.habilitado_producao,
         po.faixa_automacao,
         sf.revisao_fiscal_confirmada_em
    into v_perfil_id,
         v_habilitado_producao,
         v_faixa_automacao,
         v_confirmada
  from f.solicitacao_faturamento sf
  left join lateral (
    select x.id, x.habilitado_producao, x.faixa_automacao
    from f.perfil_operacao x
    where x.tenant_id = sf.tenant_id
      and (x.empresa_id = sf.empresa_id or x.empresa_id is null)
      and x.modelo = 'NFE'
      and (
        x.id = sf.perfil_operacao_id
        or (
          sf.perfil_operacao_id is null
          and x.natureza_operacao = sf.natureza_operacao
        )
      )
      and x.vigencia_inicio <= current_date
      and (x.vigencia_fim is null or x.vigencia_fim >= current_date)
    order by
      (x.id = sf.perfil_operacao_id) desc,
      (x.empresa_id is not null) desc,
      x.vigencia_inicio desc
    limit 1
  ) po on true
  where sf.tenant_id = new.tenant_id
    and sf.empresa_id = new.empresa_id
    and sf.id = new.solicitacao_id;

  if v_perfil_id is null or not v_habilitado_producao then
    raise exception 'Producao bloqueada: perfil fiscal explicito e liberado e obrigatorio.';
  end if;
  if v_faixa_automacao = 'BLOQUEADO' then
    raise exception 'Producao bloqueada: a combinacao fiscal ainda depende de decisao.';
  end if;
  if v_faixa_automacao = 'REVISAO' and v_confirmada is null then
    raise exception 'Producao bloqueada: a revisao fiscal desta solicitacao nao foi confirmada.';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_bloquear_nfe_producao_sem_perfil_liberado
  on f.documento_fiscal_emissao;
create trigger trg_bloquear_nfe_producao_sem_perfil_liberado
  before insert or update of ambiente, solicitacao_id
  on f.documento_fiscal_emissao
  for each row execute function f.trg_bloquear_nfe_producao_sem_perfil_liberado();

commit;
