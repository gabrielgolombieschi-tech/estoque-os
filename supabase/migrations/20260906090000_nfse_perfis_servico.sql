-- Perfis de servico da NFS-e (06/09/2026). Base: estudo das 29 NFS-e e 8 NF-e
-- de industrializacao de agosto/2026 + documento do contador de 24/11/2021 +
-- legislacao vigente em 05/09/2026 (tarefa "perfis de servico da NFS-e").
--
-- O que este arquivo faz:
--   1. Perfil: campos travados (campos_conferir, CONFERIR_08_09), regra de
--      incidencia do ISS, excecao "conserto isolado" (IN SRF 459/2004 art. 1 §2 II).
--      Cliente: optante do Simples (Lei 10.833 art. 30 §2) e template de
--      discriminacao. OS: flag conserto_isolado.
--   2. f.nfse_aliquota_iss (municipio de incidencia x subitem) e
--      f.nfse_tributos_aproximados (tabela IBPT por subitem, com vigencia).
--   3. f.fn_nfse_nbs_compativel (capitulo do NBS x grupo do subitem),
--      f.fn_nfse_texto_proibido ("MAO DE OBRA"), f.fn_round_half_even
--      (arredondamento do ambiente nacional no IBS/CBS).
--   4. f.fn_nfse_discriminacao composta por segmentos, com template por cliente;
--      segmento com campo vazio some do texto.
--   5. Revisao/liberacao/portao de producao: NBS x subitem, 17.06 fora do
--      catalogo, campos travados bloqueiam a producao (nao a homologacao),
--      f.fn_perfil_operacao_nfse_confirmar_campo destrava com auditoria.
--   6. Conferencia: ISS por incidencia, vTotTrib por tabela, CRF padrao no
--      14.01 com excecao na OS, Simples do tomador, dispensa <= R$ 10, IBS/CBS
--      na previa (base = servico - ISS), cIndOp obrigatorio a partir de 01/10/2026.
--   7. Fixture: frase legal corrigida (LEI 12.741/2012); 17.06 desativado.
--
-- Baselines (06/09/2026): fn_nfse_discriminacao(jsonb,text,text,jsonb,date,boolean,text,text)
-- e fn_os_nfse_conferir_homologacao da migration 20260905240000; revisar/liberar/
-- producao_pronta da mesma migration. Nenhuma funcao de NF-e alterada.

-- ---------------------------------------------------------------------------
-- 1. Colunas
-- ---------------------------------------------------------------------------
alter table f.perfil_operacao
  add column if not exists campos_conferir jsonb,
  add column if not exists incidencia_iss_regra text,
  add column if not exists excecao_conserto_isolado boolean not null default false;
alter table f.perfil_operacao drop constraint if exists perfil_operacao_nfse_conferir_ck;
alter table f.perfil_operacao add constraint perfil_operacao_nfse_conferir_ck check (
  (campos_conferir is null or jsonb_typeof(campos_conferir) = 'array')
  and (incidencia_iss_regra is null or incidencia_iss_regra in ('PRESTADOR', 'LOCAL_PRESTACAO'))
);
comment on column f.perfil_operacao.campos_conferir is 'Campos com valor gravado mas travados (ex.: CONFERIR_08_09): [{campo, motivo, prazo}]. Homologacao segue; liberacao para producao exige confirmacao explicita (fn_perfil_operacao_nfse_confirmar_campo).';
comment on column f.perfil_operacao.incidencia_iss_regra is 'PRESTADOR: ISS incide no municipio do estabelecimento (LC 116 art. 3 caput). LOCAL_PRESTACAO: no municipio da obra/prestacao (art. 3 III, 07.02).';
comment on column f.perfil_operacao.excecao_conserto_isolado is 'Quando true, a CRF do perfil nao se aplica se a OS estiver marcada como conserto isolado (IN SRF 459/2004, art. 1, §2, II).';

alter table public.clientes
  add column if not exists optante_simples boolean,
  add column if not exists nfse_discriminacao_template text;
comment on column public.clientes.optante_simples is 'Tomador optante do Simples Nacional: a CRF (PIS/COFINS/CSLL 4,65%) nao se aplica (Lei 10.833/2003 art. 30 §2). Nulo = nao informado (aviso).';
comment on column public.clientes.nfse_discriminacao_template is 'Template da discriminacao da NFS-e para este tomador: segmentos separados por "|", tokens {RESULTADO} {PEDIDO} {ITEM} {VENCIMENTO} {DATAS} {OS} {FRASE_LEGAL} {ISS} {OBSERVACAO}. Segmento com token vazio some. Nulo = padrao.';

alter table public.ordens_servico add column if not exists conserto_isolado boolean not null default false;
comment on column public.ordens_servico.conserto_isolado is 'Manutencao em carater isolado, mero conserto de bem defeituoso (IN SRF 459/2004 art. 1 §2 II): dispensa a CRF no 14.01. Marcada na OS, nunca deduzida.';

-- ---------------------------------------------------------------------------
-- 2. Tabelas de aliquota por incidencia e de tributos aproximados
-- ---------------------------------------------------------------------------
create table if not exists f.nfse_aliquota_iss (
  tenant_id uuid not null,
  empresa_id uuid not null,
  item_servico text not null,
  municipio_ibge text not null check (municipio_ibge ~ '^[0-9]{7}$'),
  aliquota numeric(5,2) not null check (aliquota >= 0 and aliquota <= 100),
  fonte text not null,
  criado_em timestamptz not null default now(),
  primary key (tenant_id, empresa_id, item_servico, municipio_ibge)
);
comment on table f.nfse_aliquota_iss is 'Aliquota de ISS por (municipio de incidencia x subitem). Usada na previa/retencao local; o ambiente nacional parametriza a aliquota na DPS.';
grant select on f.nfse_aliquota_iss to authenticated;
grant all on f.nfse_aliquota_iss to service_role;

create table if not exists f.nfse_tributos_aproximados (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  item_servico text not null,
  vigencia_inicio date not null,
  federal_pct numeric(5,2) not null check (federal_pct >= 0 and federal_pct <= 100),
  estadual_pct numeric(5,2) not null default 0 check (estadual_pct >= 0 and estadual_pct <= 100),
  municipal_pct numeric(5,2) not null check (municipal_pct >= 0 and municipal_pct <= 100),
  fonte text not null,
  criado_em timestamptz not null default now(),
  unique (tenant_id, empresa_id, item_servico, vigencia_inicio)
);
comment on table f.nfse_tributos_aproximados is 'Percentuais aproximados de tributos (Lei 12.741/2012, tabela IBPT) por subitem e vigencia. Nunca derivados do calculo proprio.';
grant select on f.nfse_tributos_aproximados to authenticated;
grant all on f.nfse_tributos_aproximados to service_role;

insert into f.nfse_aliquota_iss (tenant_id, empresa_id, item_servico, municipio_ibge, aliquota, fonte)
select e.tenant_id, e.id, x.item, x.mun, x.aliq, x.fonte
from c.empresa e join c.empresa_fiscal ef on ef.empresa_id = e.id and ef.deleted_at is null
cross join (values
  ('14.01', '4209102', 5.00::numeric, 'NFS-e 31-32 de ago/2026, Joinville'),
  ('14.06', '4209102', 5.00::numeric, 'NFS-e 21-38 de ago/2026, Joinville'),
  ('17.09', '4209102', 5.00::numeric, 'NFS-e 27-40 de ago/2026, Joinville'),
  ('07.02', '4216206', 3.00::numeric, 'NFS-e 37 de ago/2026, Sao Francisco do Sul (municipio da obra)'),
  ('07.02', '4209102', 5.00::numeric, 'LC 155/2003 Joinville (obra em Joinville)')
) as x(item, mun, aliq, fonte)
where e.deleted_at is null
on conflict do nothing;

insert into f.nfse_tributos_aproximados (tenant_id, empresa_id, item_servico, vigencia_inicio, federal_pct, estadual_pct, municipal_pct, fonte)
select e.tenant_id, e.id, x.item, date '2026-08-01', 13.45, 0, x.mun, 'Tabela IBPT observada nas 29 NFS-e de ago/2026 (federal uniforme 13,45%)'
from c.empresa e join c.empresa_fiscal ef on ef.empresa_id = e.id and ef.deleted_at is null
cross join (values ('14.01', 4.69::numeric), ('14.06', 4.69::numeric), ('17.09', 3.64::numeric), ('07.02', 2.11::numeric)) as x(item, mun)
where e.deleted_at is null
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. Funcoes de apoio
-- ---------------------------------------------------------------------------
create or replace function f.fn_round_half_even(p_valor numeric, p_casas integer default 2)
returns numeric language sql immutable set search_path = pg_catalog as $$
  select case
    when p_valor is null then null
    -- Exatamente no meio: arredonda para o par (comportamento observado no IBS/CBS do ambiente nacional: 3,325 -> 3,32; 29,925 -> 29,92).
    when abs(p_valor * power(10, p_casas) - trunc(p_valor * power(10, p_casas))) = 0.5
      then (case when mod(trunc(p_valor * power(10, p_casas))::bigint, 2) = 0
                 then trunc(p_valor * power(10, p_casas))
                 else trunc(p_valor * power(10, p_casas)) + sign(p_valor) end) / power(10, p_casas)
    else round(p_valor, p_casas) end;
$$;

create or replace function f.fn_nfse_nbs_compativel(p_item_servico text, p_nbs text)
returns boolean language sql immutable set search_path = pg_catalog as $$
  -- NBS 9 digitos "1CCppssff": capitulo = posicoes 2-3. 14.xx -> capitulo 20 (servicos de manutencao/instalacao),
  -- 17.09 -> capitulo 14 (servicos tecnicos), 07.02 -> capitulo 01 (obras). Nota 21 real (14.06 com 1.0102.69.00) fica barrada.
  select case
    when p_nbs is null or p_nbs !~ '^[0-9]{9}$' then true
    when p_item_servico like '14.%' then substring(p_nbs from 2 for 2) = '20'
    when p_item_servico like '17.%' then substring(p_nbs from 2 for 2) = '14'
    when p_item_servico like '07.%' then substring(p_nbs from 2 for 2) = '01'
    else true end;
$$;

create or replace function f.fn_nfse_texto_proibido(p_texto text)
returns text language sql immutable set search_path = pg_catalog as $$
  -- "MAO DE OBRA" e a definicao literal de cessao de mao de obra (INSS 11%, IRRF 1%, CRF 4,65%).
  select case
    when p_texto is null then null
    when upper(translate(p_texto, 'ãâáàÃÂÁÀ', 'aaaaAAAA')) ~ 'M[AÃ]O[ \-]+DE[ \-]+OBRA' then 'MAO DE OBRA'
    else null end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Discriminacao composta por segmentos
-- ---------------------------------------------------------------------------
drop function if exists f.fn_nfse_discriminacao(jsonb, text, text, jsonb, date, boolean, text, text);
create function f.fn_nfse_discriminacao(
  p_linhas jsonb,            -- [{descricao, os_numero}]
  p_pedido text,
  p_pedido_item text,
  p_parcelas jsonb,          -- [{numero, dias, valor}] ou null (a vista)
  p_base_date date,
  p_iss_retido boolean,
  p_texto_retencao text,     -- frase legal do perfil (com ou sem aspas)
  p_observacao text,
  p_template text default null
) returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_template text := coalesce(nullif(btrim(coalesce(p_template, '')), ''),
    '{RESULTADO}|PEDIDO DE COMPRA: {PEDIDO}{ITEM}|VENCIMENTO: {VENCIMENTO} DDL|OS {OS}|{FRASE_LEGAL}|{OBSERVACAO}');
  v_tokens jsonb;
  v_segmento text;
  v_texto text;
  v_partes text[] := array[]::text[];
  v_linha jsonb;
  v_resultados text[] := array[]::text[];
  v_os text[] := array[]::text[];
  v_dias text[] := array[]::text[];
  v_datas text[] := array[]::text[];
  v_p jsonb;
  v_frase text := nullif(btrim(coalesce(p_texto_retencao, '')), '');
  v_chave text;
  v_valor text;
  v_vazio boolean;
begin
  for v_linha in select * from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) loop
    if nullif(btrim(coalesce(v_linha->>'descricao', '')), '') is not null then
      v_resultados := array_append(v_resultados, upper(btrim(v_linha->>'descricao')));
    end if;
    if nullif(btrim(coalesce(v_linha->>'os_numero', '')), '') is not null and not (btrim(v_linha->>'os_numero') = any(v_os)) then
      v_os := array_append(v_os, btrim(v_linha->>'os_numero'));
    end if;
  end loop;
  if p_parcelas is not null and jsonb_typeof(p_parcelas) = 'array' then
    for v_p in select * from jsonb_array_elements(p_parcelas) loop
      v_dias := array_append(v_dias, v_p->>'dias');
      v_datas := array_append(v_datas, to_char(p_base_date + (v_p->>'dias')::integer, 'DD/MM/YYYY'));
    end loop;
  end if;
  if v_frase is not null and left(v_frase, 1) <> '"' then v_frase := '"' || v_frase || '"'; end if;
  v_tokens := jsonb_build_object(
    'RESULTADO', array_to_string(v_resultados, '; '),
    'PEDIDO', nullif(btrim(coalesce(p_pedido, '')), ''),
    'ITEM', case when nullif(btrim(coalesce(p_pedido_item, '')), '') is not null then ' ITEM ' || btrim(p_pedido_item) else null end,
    'VENCIMENTO', nullif(array_to_string(v_dias, '/'), ''),
    'DATAS', nullif(array_to_string(v_datas, ', '), ''),
    'OS', nullif(array_to_string(v_os, '/'), ''),
    'FRASE_LEGAL', v_frase,
    'ISS', case when p_iss_retido then 'ISS RETIDO PELO TOMADOR' else null end,
    'OBSERVACAO', nullif(btrim(coalesce(p_observacao, '')), '')
  );
  foreach v_segmento in array string_to_array(v_template, '|') loop
    v_texto := v_segmento;
    v_vazio := false;
    for v_chave, v_valor in select key, value #>> '{}' from jsonb_each(v_tokens) loop
      if position('{' || v_chave || '}' in v_texto) > 0 then
        -- {ITEM} e opcional dentro do segmento do pedido: vazio nao derruba o segmento.
        if v_valor is null and v_chave <> 'ITEM' then v_vazio := true; end if;
        v_texto := replace(v_texto, '{' || v_chave || '}', coalesce(v_valor, ''));
      end if;
    end loop;
    v_texto := btrim(v_texto);
    if not v_vazio and v_texto <> '' then
      v_partes := array_append(v_partes, v_texto || case when right(v_texto, 1) in ('.', '"') then '' else '.' end);
    end if;
  end loop;
  return left(regexp_replace(array_to_string(v_partes, ' '), '\s+', ' ', 'g'), 1000);
end;
$$;
revoke all on function f.fn_nfse_discriminacao(jsonb, text, text, jsonb, date, boolean, text, text, text) from public;
grant execute on function f.fn_nfse_discriminacao(jsonb, text, text, jsonb, date, boolean, text, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Revisao, confirmacao de campo travado, liberacao e portao de producao
-- ---------------------------------------------------------------------------
create or replace function f.fn_perfil_operacao_nfse_revisar(p_perfil_id uuid, p_campos jsonb, p_justificativa text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  c jsonb := coalesce(p_campos, '{}'::jsonb);
  v_flag jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '') in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao de escrita para revisar perfis fiscais.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then
    raise exception using errcode = '22023', message = 'A justificativa da revisao deve ter entre 15 e 1000 caracteres.';
  end if;
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = p_perfil_id and po.tenant_id = v_scope.tenant_id and po.empresa_id = v_scope.empresa_id and po.modelo = 'NFSE'
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Perfil de servico nao encontrado no tenant e empresa ativos.'; end if;
  if v_perfil.item_servico = '17.06' then
    raise exception using errcode = '22023', message = 'O subitem 17.06 (propaganda e publicidade) nao existe no catalogo de servicos da Segau; laudos e documentacao tecnica sao 17.09.';
  end if;
  if coalesce(c->>'codigo_tributacao_nacional', '') !~ '^[0-9]{6}$' then raise exception using errcode = '22023', message = 'codigo_tributacao_nacional deve ter 6 digitos.'; end if;
  if left(c->>'codigo_tributacao_nacional', 4) <> replace(v_perfil.item_servico, '.', '') then
    raise exception using errcode = '22023', message = format('codigo_tributacao_nacional %s nao corresponde ao subitem %s do perfil.', c->>'codigo_tributacao_nacional', v_perfil.item_servico);
  end if;
  if nullif(c->>'codigo_nbs', '') is not null and (c->>'codigo_nbs') !~ '^[0-9]{9}$' then raise exception using errcode = '22023', message = 'codigo_nbs deve ter 9 digitos.'; end if;
  if not f.fn_nfse_nbs_compativel(v_perfil.item_servico, nullif(c->>'codigo_nbs', '')) then
    raise exception using errcode = '22023', message = format('NBS %s e de outro capitulo; incompativel com o subitem %s (ex.: nota 21 real, 14.06 com 1.0102.69.00).', c->>'codigo_nbs', v_perfil.item_servico);
  end if;
  if coalesce(c->>'local_prestacao_regra', '') not in ('SEDE', 'CLIENTE') then raise exception using errcode = '22023', message = 'local_prestacao_regra deve ser SEDE ou CLIENTE.'; end if;
  if coalesce(c->>'incidencia_iss_regra', 'PRESTADOR') not in ('PRESTADOR', 'LOCAL_PRESTACAO') then raise exception using errcode = '22023', message = 'incidencia_iss_regra deve ser PRESTADOR ou LOCAL_PRESTACAO.'; end if;
  if coalesce((c->>'tributacao_iss')::int, 0) not in (1, 2, 3, 4) then raise exception using errcode = '22023', message = 'tributacao_iss deve ser 1 a 4.'; end if;
  if (c->>'aliquota_iss')::numeric is null or (c->>'aliquota_iss')::numeric < 0 or (c->>'aliquota_iss')::numeric > 100 then raise exception using errcode = '22023', message = 'aliquota_iss obrigatoria (0 a 100).'; end if;
  if coalesce(c->>'iss_retido_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')
     or coalesce(c->>'retencao_pcc_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')
     or coalesce(c->>'retencao_irrf_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR')
     or coalesce(c->>'retencao_inss_regra', '') not in ('NUNCA', 'SEMPRE', 'POR_TOMADOR') then
    raise exception using errcode = '22023', message = 'Regras de retencao (ISS, PCC, IRRF, INSS) devem ser NUNCA, SEMPRE ou POR_TOMADOR.';
  end if;
  if coalesce(c->>'cst_pis', '') !~ '^[0-9]{2}$' or coalesce(c->>'cst_cofins', '') !~ '^[0-9]{2}$' then raise exception using errcode = '22023', message = 'CST de PIS e COFINS devem ter 2 digitos.'; end if;
  if coalesce(c->>'cst_ibs_cbs', '') !~ '^[0-9]{3}$' or coalesce(c->>'cclass_trib', '') !~ '^[0-9]{6}$' or left(c->>'cclass_trib', 3) <> (c->>'cst_ibs_cbs') then
    raise exception using errcode = '22023', message = 'CST IBS/CBS (3 digitos) e cClassTrib (6 digitos, mesmo prefixo) obrigatorios.';
  end if;
  if nullif(c->>'codigo_indicador_operacao', '') is not null and (c->>'codigo_indicador_operacao') !~ '^[0-9]{6}$' then raise exception using errcode = '22023', message = 'codigo_indicador_operacao (cIndOp) deve ter 6 digitos.'; end if;
  if (c->>'ibs_uf_aliquota')::numeric is null or (c->>'ibs_mun_aliquota')::numeric is null or (c->>'cbs_aliquota')::numeric is null then
    raise exception using errcode = '22023', message = 'Aliquotas IBS UF, IBS municipal e CBS obrigatorias.';
  end if;
  if c ? 'campos_conferir' and jsonb_typeof(c->'campos_conferir') <> 'array' then raise exception using errcode = '22023', message = 'campos_conferir deve ser uma lista [{campo, motivo, prazo}].'; end if;
  for v_flag in select * from jsonb_array_elements(coalesce(c->'campos_conferir', '[]'::jsonb)) loop
    if nullif(v_flag->>'campo', '') is null or nullif(v_flag->>'motivo', '') is null then
      raise exception using errcode = '22023', message = 'Cada campo travado precisa de campo e motivo.';
    end if;
  end loop;
  if f.fn_nfse_texto_proibido(c->>'descricao_servico_padrao') is not null or f.fn_nfse_texto_proibido(c->>'texto_complementar') is not null then
    raise exception using errcode = '22023', message = 'A expressao MAO DE OBRA e proibida na descricao padrao e no texto complementar (cessao de mao de obra: INSS 11%, IRRF 1%, CRF 4,65%).';
  end if;

  update f.perfil_operacao po
  set codigo_tributacao_nacional = c->>'codigo_tributacao_nacional',
      codigo_tributacao_municipal = nullif(c->>'codigo_tributacao_municipal', ''),
      codigo_nbs = nullif(c->>'codigo_nbs', ''),
      descricao_servico_padrao = nullif(c->>'descricao_servico_padrao', ''),
      local_prestacao_regra = c->>'local_prestacao_regra',
      incidencia_iss_regra = coalesce(c->>'incidencia_iss_regra', 'PRESTADOR'),
      tributacao_iss = (c->>'tributacao_iss')::smallint,
      aliquota_iss = (c->>'aliquota_iss')::numeric,
      iss_retido_regra = c->>'iss_retido_regra',
      retencao_pcc_regra = c->>'retencao_pcc_regra', aliquota_pcc = nullif(c->>'aliquota_pcc', '')::numeric,
      retencao_irrf_regra = c->>'retencao_irrf_regra', aliquota_irrf = nullif(c->>'aliquota_irrf', '')::numeric,
      retencao_inss_regra = c->>'retencao_inss_regra', aliquota_inss = nullif(c->>'aliquota_inss', '')::numeric,
      excecao_conserto_isolado = coalesce((c->>'excecao_conserto_isolado')::boolean, false),
      permite_deducao_material = coalesce((c->>'permite_deducao_material')::boolean, false),
      texto_complementar = nullif(c->>'texto_complementar', ''),
      cst_pis = c->>'cst_pis', cst_cofins = c->>'cst_cofins',
      aliquota_pis = nullif(c->>'aliquota_pis', '')::numeric, aliquota_cofins = nullif(c->>'aliquota_cofins', '')::numeric,
      consumidor_final = coalesce((c->>'consumidor_final')::smallint, 0),
      cst_ibs_cbs = c->>'cst_ibs_cbs', cclass_trib = c->>'cclass_trib',
      cclass_trib_versao = coalesce(nullif(c->>'cclass_trib_versao', ''), po.cclass_trib_versao, 'NFS-e ago/2026'),
      ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', (c->>'ibs_uf_aliquota')::numeric, 'ibs_mun_aliquota', (c->>'ibs_mun_aliquota')::numeric, 'cbs_aliquota', (c->>'cbs_aliquota')::numeric),
      codigo_indicador_operacao = nullif(c->>'codigo_indicador_operacao', ''),
      tributos_aprox_federal_pct = nullif(c->>'tributos_aprox_federal_pct', '')::numeric,
      tributos_aprox_municipal_pct = nullif(c->>'tributos_aprox_municipal_pct', '')::numeric,
      campos_conferir = case when jsonb_array_length(coalesce(c->'campos_conferir', '[]'::jsonb)) = 0 then null else c->'campos_conferir' end,
      cbenef_aplicacao = 'SEM_BENEFICIO', cbenef = null,
      revisao_fiscal_em = now(), revisao_fiscal_por = v_scope.usuario_id, revisao_fiscal_justificativa = v_justificativa,
      habilitado_producao = false, producao_decidida_em = null, producao_decidida_por = null,
      producao_decisao_justificativa = null, producao_homologacao_solicitacao_id = null, producao_homologacao_documento_id = null
  where po.id = v_perfil.id
  returning po.* into v_depois;

  insert into f.perfil_operacao_revisao_evento (tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois, justificativa, criado_por, created_at)
  values (v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'REVISAO', to_jsonb(v_perfil), to_jsonb(v_depois), v_justificativa, v_scope.usuario_id, v_depois.revisao_fiscal_em);
  return jsonb_build_object('perfil_id', v_perfil.id, 'revisao_fiscal_em', v_depois.revisao_fiscal_em, 'habilitado_producao', false, 'campos_conferir', v_depois.campos_conferir);
end;
$$;

create or replace function f.fn_perfil_operacao_nfse_confirmar_campo(p_perfil_id uuid, p_campo text, p_justificativa text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
  v_restantes jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '') in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao de escrita para confirmar campos do perfil.';
  end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then
    raise exception using errcode = '22023', message = 'A justificativa da confirmacao deve ter entre 15 e 1000 caracteres.';
  end if;
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = p_perfil_id and po.tenant_id = v_scope.tenant_id and po.empresa_id = v_scope.empresa_id and po.modelo = 'NFSE' for update;
  if not found then raise exception using errcode = 'P0002', message = 'Perfil de servico nao encontrado.'; end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(v_perfil.campos_conferir, '[]'::jsonb)) x where x->>'campo' = p_campo) then
    raise exception using errcode = '22023', message = format('O campo %s nao esta travado neste perfil.', p_campo);
  end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_restantes from jsonb_array_elements(v_perfil.campos_conferir) x where x->>'campo' <> p_campo;
  update f.perfil_operacao set campos_conferir = case when jsonb_array_length(v_restantes) = 0 then null else v_restantes end where id = v_perfil.id returning * into v_depois;
  insert into f.perfil_operacao_revisao_evento (tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois, justificativa, criado_por)
  values (v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'REVISAO', to_jsonb(v_perfil), to_jsonb(v_depois), 'CONFIRMACAO DO CAMPO ' || p_campo || ': ' || v_justificativa, v_scope.usuario_id);
  return jsonb_build_object('perfil_id', v_perfil.id, 'campo', p_campo, 'campos_conferir', v_depois.campos_conferir);
end;
$$;
revoke all on function f.fn_perfil_operacao_nfse_confirmar_campo(uuid, text, text) from public;
grant execute on function f.fn_perfil_operacao_nfse_confirmar_campo(uuid, text, text) to authenticated, service_role;

create or replace function f.fn_perfil_operacao_nfse_liberar_producao(p_perfil_id uuid, p_solicitacao_id uuid, p_justificativa text, p_confirmacao boolean)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_scope record;
  v_perfil f.perfil_operacao%rowtype;
  v_depois f.perfil_operacao%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_hom f.documento_fiscal_emissao%rowtype;
  v_justificativa text := btrim(coalesce(p_justificativa, ''));
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if not (
    coalesce(public.can('faturamento', 'write', v_scope.tenant_id), false)
    or coalesce(public.can('financeiro', 'write', v_scope.tenant_id), false)
    or coalesce(a.fn_current_empresa_papel(v_scope.tenant_id, v_scope.empresa_id), '') in ('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO')
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao de escrita para liberar perfis fiscais.';
  end if;
  if not coalesce(p_confirmacao, false) then raise exception using errcode = '22023', message = 'Confirme explicitamente a liberacao para producao.'; end if;
  if char_length(v_justificativa) < 15 or char_length(v_justificativa) > 1000 then raise exception using errcode = '22023', message = 'A justificativa da liberacao deve ter entre 15 e 1000 caracteres.'; end if;
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = p_perfil_id and po.tenant_id = v_scope.tenant_id and po.empresa_id = v_scope.empresa_id and po.modelo = 'NFSE' for update;
  if not found then raise exception using errcode = 'P0002', message = 'Perfil de servico nao encontrado.'; end if;
  if v_perfil.campos_conferir is not null and jsonb_array_length(v_perfil.campos_conferir) > 0 then
    raise exception using errcode = '55000', message = format('Perfil com campos travados (%s): confirme cada um com fn_perfil_operacao_nfse_confirmar_campo antes da producao.',
      (select string_agg(x->>'campo', ', ') from jsonb_array_elements(v_perfil.campos_conferir) x));
  end if;
  if v_perfil.revisao_fiscal_em is null or v_perfil.codigo_tributacao_nacional is null or v_perfil.aliquota_iss is null or v_perfil.iss_retido_regra is null
     or v_perfil.cst_ibs_cbs is null or v_perfil.cclass_trib is null or v_perfil.codigo_indicador_operacao is null then
    raise exception using errcode = '22023', message = 'O perfil de servico precisa ser revisado (codigo, ISS, retencoes, IBS/CBS, cIndOp) antes da liberacao.';
  end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' then raise exception using errcode = '22023', message = 'Perfil bloqueado nao pode ser liberado.'; end if;
  if not exists (select 1 from f.perfil_operacao_revisao_evento re where re.perfil_operacao_id = v_perfil.id and re.tipo = 'REVISAO' and re.created_at = v_perfil.revisao_fiscal_em and re.justificativa = v_perfil.revisao_fiscal_justificativa) then
    raise exception using errcode = '55000', message = 'A ultima revisao do perfil nao possui evento de auditoria equivalente.';
  end if;
  select sf.* into v_sf from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id and sf.tenant_id = v_scope.tenant_id and sf.empresa_id = v_scope.empresa_id and sf.status <> 'CANCELADA';
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao ativa nao encontrada.'; end if;
  if v_sf.perfil_operacao_id is distinct from v_perfil.id then raise exception using errcode = '22023', message = 'A solicitacao nao usa este perfil de servico.'; end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and (si.modelo <> 'NFSE' or si.tributacao_fonte is distinct from 'PERFIL' or si.perfil_operacao_id is distinct from v_perfil.id
              or si.codigo_tributacao_nacional is distinct from v_perfil.codigo_tributacao_nacional or si.cst_ibs_cbs is distinct from v_perfil.cst_ibs_cbs or si.cclass_trib is distinct from v_perfil.cclass_trib)) then
    raise exception using errcode = '22023', message = 'As linhas da solicitacao homologada precisam ter sido conferidas com este perfil (tributacao_fonte = PERFIL) e coincidir com ele.';
  end if;
  select dfe.* into v_hom from f.documento_fiscal_emissao dfe
  where dfe.solicitacao_id = v_sf.id and dfe.ambiente = 'HOMOLOGACAO' and dfe.modelo = 'NFSE' and dfe.status = 'AUTORIZADA'
    and dfe.autorizado_em is not null and dfe.autorizado_em > v_perfil.revisao_fiscal_em
  order by dfe.autorizado_em desc limit 1;
  if not found then raise exception using errcode = '22023', message = 'A solicitacao precisa de NFS-e AUTORIZADA em homologacao depois da ultima revisao do perfil.'; end if;
  if v_hom.payload_enviado->>'codigo_tributacao_nacional_iss' is distinct from v_perfil.codigo_tributacao_nacional
     or v_hom.payload_enviado->>'ibs_cbs_situacao_tributaria' is distinct from v_perfil.cst_ibs_cbs
     or v_hom.payload_enviado->>'ibs_cbs_classificacao_tributaria' is distinct from v_perfil.cclass_trib
     or v_hom.payload_enviado->>'codigo_indicador_operacao' is distinct from v_perfil.codigo_indicador_operacao then
    raise exception using errcode = '22023', message = 'O payload autorizado em homologacao nao coincide com o perfil (codigo, IBS/CBS, cIndOp).';
  end if;
  update f.perfil_operacao po
  set habilitado_producao = true, producao_decidida_em = now(), producao_decidida_por = v_scope.usuario_id,
      producao_decisao_justificativa = v_justificativa, producao_homologacao_solicitacao_id = v_sf.id, producao_homologacao_documento_id = v_hom.documento_fiscal_id
  where po.id = v_perfil.id returning po.* into v_depois;
  insert into f.perfil_operacao_revisao_evento (tenant_id, empresa_id, perfil_operacao_id, tipo, antes, depois, homologacao_solicitacao_id, homologacao_documento_id, justificativa, criado_por, created_at)
  values (v_scope.tenant_id, v_scope.empresa_id, v_perfil.id, 'LIBERACAO', to_jsonb(v_perfil), to_jsonb(v_depois), v_sf.id, v_hom.documento_fiscal_id, v_justificativa, v_scope.usuario_id, v_depois.producao_decidida_em);
  return jsonb_build_object('perfil_id', v_perfil.id, 'solicitacao_id', v_sf.id, 'homologacao_documento_fiscal_id', v_hom.documento_fiscal_id, 'habilitado_producao', true);
end;
$$;

create or replace function f.fn_nfse_producao_pronta(p_solicitacao_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_perfil f.perfil_operacao%rowtype;
  v_hom_doc uuid;
  v_hom_autorizado_em timestamptz;
  v_certificado date;
begin
  select * into v_sf from f.solicitacao_faturamento where id = p_solicitacao_id;
  if not found then return jsonb_build_object('pronta', false, 'motivo', 'Solicitacao nao encontrada.'); end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar a liberacao de producao.';
  end if;
  if v_sf.status = 'CANCELADA' then return jsonb_build_object('pronta', false, 'motivo', 'A solicitacao esta cancelada.'); end if;
  select dfe.documento_fiscal_id, dfe.autorizado_em into v_hom_doc, v_hom_autorizado_em
  from f.documento_fiscal_emissao dfe
  where dfe.solicitacao_id = v_sf.id and dfe.ambiente = 'HOMOLOGACAO' and dfe.status = 'AUTORIZADA' and dfe.modelo = 'NFSE'
  order by dfe.autorizado_em desc nulls last limit 1;
  if v_hom_doc is null then return jsonb_build_object('pronta', false, 'motivo', 'A mesma solicitacao precisa estar AUTORIZADA em homologacao antes da producao.'); end if;
  select ef.certificado_validade_em into v_certificado from c.empresa_fiscal ef where ef.empresa_id = v_sf.empresa_id and ef.deleted_at is null order by ef.updated_at desc limit 1;
  if v_certificado is null then return jsonb_build_object('pronta', false, 'motivo', 'A validade do certificado digital da empresa ainda nao foi registrada.'); end if;
  if v_certificado < current_date then return jsonb_build_object('pronta', false, 'motivo', 'O certificado digital registrado esta vencido.'); end if;
  if v_sf.snapshot_cadastro_em is null or jsonb_typeof(v_sf.operacao_snapshot->'servico') is distinct from 'object' then
    return jsonb_build_object('pronta', false, 'motivo', 'A conferencia da NFS-e ainda nao foi salva.');
  end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and (si.tributacao_fonte is distinct from 'PERFIL' or si.perfil_operacao_id is null)) then
    return jsonb_build_object('pronta', false, 'motivo', 'Linhas de servico com valores da fixture de homologacao; producao exige perfil de servico revisado e liberado.');
  end if;
  select po.* into v_perfil from f.perfil_operacao po where po.id = v_sf.perfil_operacao_id;
  if not found or v_perfil.modelo <> 'NFSE' then return jsonb_build_object('pronta', false, 'motivo', 'Perfil de servico nao encontrado.'); end if;
  if v_perfil.campos_conferir is not null and jsonb_array_length(v_perfil.campos_conferir) > 0 then
    return jsonb_build_object('pronta', false, 'motivo', 'Perfil com campos travados (' || (select string_agg(x->>'campo', ', ') from jsonb_array_elements(v_perfil.campos_conferir) x) || '): producao exige confirmacao explicita.');
  end if;
  if v_perfil.codigo_indicador_operacao is null then
    return jsonb_build_object('pronta', false, 'motivo', 'Perfil sem cIndOp: obrigatorio no grupo IBS/CBS (Ato Conjunto RFB/CGIBS 4/2026).');
  end if;
  if v_perfil.faixa_automacao = 'BLOQUEADO' or not v_perfil.habilitado_producao
     or v_perfil.vigencia_inicio > current_date or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date)
     or v_perfil.revisao_fiscal_em is null or v_perfil.producao_decidida_em is null
     or v_perfil.producao_homologacao_solicitacao_id is distinct from v_sf.id
     or v_perfil.producao_homologacao_documento_id is distinct from v_hom_doc
     or v_hom_autorizado_em <= v_perfil.revisao_fiscal_em
     or v_perfil.codigo_tributacao_nacional is null or v_perfil.aliquota_iss is null or v_perfil.iss_retido_regra is null
     or v_perfil.cst_ibs_cbs is null or v_perfil.cclass_trib is null
     or not exists (
       select 1 from f.perfil_operacao_revisao_evento le
       where le.perfil_operacao_id = v_perfil.id and le.tipo = 'LIBERACAO'
         and le.homologacao_solicitacao_id = v_sf.id and le.homologacao_documento_id = v_hom_doc
         and le.depois->>'habilitado_producao' = 'true'
     ) then
    return jsonb_build_object('pronta', false, 'motivo', 'Perfil de servico precisa estar liberado para esta homologacao (revisao + liberacao auditadas).');
  end if;
  return jsonb_build_object('pronta', true, 'tenant_id', v_sf.tenant_id, 'empresa_id', v_sf.empresa_id,
    'homologacao_documento_fiscal_id', v_hom_doc, 'perfil_operacao_id', v_perfil.id, 'perfil_operacao_ids', jsonb_build_array(v_perfil.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Conferencia
-- ---------------------------------------------------------------------------
create or replace function f.fn_os_nfse_conferir_homologacao(p_solicitacao_id uuid, p_operacao jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_perfil f.perfil_operacao%rowtype;
  v_fx f.tributacao_provisoria_nfse_homologacao%rowtype;
  v_cliente public.clientes%rowtype;
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_item record;
  v_os public.ordens_servico%rowtype;
  v_pend jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
  v_rota_cliente text;
  v_rota_perfil text := '/faturamento/perfis';
  v_documento text;
  v_municipio text;
  v_municipio_incidencia text;
  v_sede_ibge text;
  v_competencia date;
  v_iss_retido boolean; v_pcc boolean; v_irrf boolean; v_inss boolean;
  v_iss_override boolean; v_pcc_override boolean; v_irrf_override boolean; v_inss_override boolean;
  v_justificativa text;
  v_bruto numeric(15,2) := 0; v_valor_iss numeric(15,2) := 0; v_v_irrf numeric(15,2) := 0; v_v_pcc numeric(15,2) := 0; v_v_inss numeric(15,2) := 0;
  v_liquido numeric(15,2);
  v_retencoes jsonb := '[]'::jsonb;
  v_parcelas jsonb;
  v_pag_forma text; v_pag_indicador smallint;
  v_saldo record; v_reserva_propria numeric(15,2); v_reserva_substituida numeric(15,2); v_os_total record;
  v_linhas_desc jsonb := '[]'::jsonb;
  v_os_numeros text[] := array[]::text[];
  v_discriminacao text; v_texto_retencao text; v_proibido text;
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_emissao_status text;
  v_linhas integer := 0;
  v_consumidor_final smallint;
  v_pedido text; v_pedido_item text; v_observacao text; v_obs_composta text;
  v_conserto_isolado boolean;
  v_todas_conserto boolean := true;
  v_tem_federal boolean;
  v_ibs_base numeric(15,2); v_ibs_uf numeric(15,2); v_ibs_mun numeric(15,2); v_cbs numeric(15,2);
  v_fonte text;
  f_ctrib text; f_ctrib_mun text; f_nbs text; f_desc text; f_local text; f_incid text; f_trib_iss smallint; f_aliq_iss numeric;
  f_iss_regra text; f_pcc_regra text; f_irrf_regra text; f_inss_regra text; f_aliq_pcc numeric; f_aliq_irrf numeric; f_aliq_inss numeric;
  f_cst_pis text; f_cst_cofins text; f_aliq_pis numeric; f_aliq_cofins numeric; f_cst_ibs text; f_cclass text;
  f_ibs_uf numeric; f_ibs_mun numeric; f_cbs numeric; f_cindop text; f_pct_fed numeric; f_pct_mun numeric; f_pct_est numeric;
  f_texto_sem text; f_texto_com text; f_item text; f_excecao_conserto boolean := false;
begin
  select * into v_sf from f.solicitacao_faturamento where id = p_solicitacao_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.'; end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NFS-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s nao pode ser conferida.', v_sf.status);
  end if;
  select e.status into v_emissao_status from f.documento_fiscal_emissao e
  where e.tenant_id = v_sf.tenant_id and e.empresa_id = v_sf.empresa_id and e.solicitacao_id = v_sf.id order by e.created_at desc limit 1;
  if v_emissao_status is not null and v_emissao_status not in ('RASCUNHO') then
    raise exception using errcode = '55000', message = format('A NFS-e desta solicitacao ja esta em %s; a conferencia nao pode mais ser alterada. Para refazer, descarte e crie outra.', v_emissao_status);
  end if;
  if exists (select 1 from f.solicitacao_item si where si.solicitacao_id = v_sf.id and si.modelo <> 'NFSE') then
    raise exception using errcode = '22023', message = 'Esta conferencia e exclusiva de linhas de servico (NFS-e).';
  end if;
  v_rota_cliente := '/clientes/cadastro-fiscal?cliente_id=' || coalesce(v_sf.cliente_id::text, '');

  -- Perfil escolhido; valores do perfil quando revisado, senao da fixture provisoria.
  select po.* into v_perfil from f.perfil_operacao po
  where po.id = coalesce(nullif(p_operacao->>'perfil_operacao_id', '')::uuid, v_sf.perfil_operacao_id)
    and po.tenant_id = v_sf.tenant_id and (po.empresa_id = v_sf.empresa_id or po.empresa_id is null);
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','campo','perfil_operacao_id','mensagem','Escolha o perfil de servico da NFS-e.','rota',v_rota_perfil));
  else
    if v_perfil.modelo <> 'NFSE' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','modelo','mensagem',format('Perfil %s nao e de servico.', v_perfil.codigo),'rota',v_rota_perfil)); end if;
    if v_perfil.item_servico = '17.06' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','item_servico','mensagem','O subitem 17.06 (propaganda) nao existe no catalogo da Segau; laudos e documentacao tecnica sao 17.09.','rota',v_rota_perfil)); end if;
    if v_perfil.faixa_automacao = 'BLOQUEADO' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','faixa_automacao','mensagem',format('Perfil %s bloqueado: %s', v_perfil.codigo, coalesce(v_perfil.justificativa_faixa, 'aguarda o contador.')),'rota',v_rota_perfil)); end if;
    if v_perfil.vigencia_inicio > current_date or (v_perfil.vigencia_fim is not null and v_perfil.vigencia_fim < current_date) then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','vigencia','mensagem',format('Perfil %s fora da vigencia.', v_perfil.codigo),'rota',v_rota_perfil)); end if;
    if v_perfil.revisao_fiscal_em is not null and v_perfil.codigo_tributacao_nacional is not null and v_perfil.aliquota_iss is not null and v_perfil.iss_retido_regra is not null then
      v_fonte := 'PERFIL';
      f_item := v_perfil.item_servico; f_ctrib := v_perfil.codigo_tributacao_nacional; f_ctrib_mun := v_perfil.codigo_tributacao_municipal; f_nbs := v_perfil.codigo_nbs;
      f_desc := v_perfil.descricao_servico_padrao; f_local := coalesce(v_perfil.local_prestacao_regra, 'SEDE'); f_incid := coalesce(v_perfil.incidencia_iss_regra, 'PRESTADOR');
      f_trib_iss := coalesce(v_perfil.tributacao_iss, 1); f_aliq_iss := v_perfil.aliquota_iss;
      f_iss_regra := v_perfil.iss_retido_regra; f_pcc_regra := coalesce(v_perfil.retencao_pcc_regra, 'NUNCA'); f_irrf_regra := coalesce(v_perfil.retencao_irrf_regra, 'NUNCA'); f_inss_regra := coalesce(v_perfil.retencao_inss_regra, 'NUNCA');
      f_aliq_pcc := v_perfil.aliquota_pcc; f_aliq_irrf := v_perfil.aliquota_irrf; f_aliq_inss := v_perfil.aliquota_inss;
      f_cst_pis := v_perfil.cst_pis; f_cst_cofins := v_perfil.cst_cofins; f_aliq_pis := v_perfil.aliquota_pis; f_aliq_cofins := v_perfil.aliquota_cofins;
      f_cst_ibs := v_perfil.cst_ibs_cbs; f_cclass := v_perfil.cclass_trib;
      f_ibs_uf := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'); f_ibs_mun := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'); f_cbs := f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota');
      f_cindop := v_perfil.codigo_indicador_operacao; f_pct_fed := v_perfil.tributos_aprox_federal_pct; f_pct_mun := v_perfil.tributos_aprox_municipal_pct;
      f_texto_sem := v_perfil.texto_complementar; f_texto_com := v_perfil.texto_complementar; f_excecao_conserto := coalesce(v_perfil.excecao_conserto_isolado, false);
      v_consumidor_final := coalesce(v_perfil.consumidor_final, 0);
      if f_cindop is null then
        if current_date >= date '2026-10-01' then
          v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','codigo_indicador_operacao','mensagem','Perfil sem cIndOp: obrigatorio no grupo IBS/CBS desde 01/10/2026 (Ato Conjunto RFB/CGIBS 4/2026).','rota',v_rota_perfil));
        else
          v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','codigo_indicador_operacao','mensagem','Perfil sem cIndOp; obrigatorio a partir de 01/10/2026.','rota',v_rota_perfil));
        end if;
      end if;
      if v_perfil.campos_conferir is not null and jsonb_array_length(v_perfil.campos_conferir) > 0 then
        v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','campos_conferir','mensagem','Perfil com campos travados (' || (select string_agg(x->>'campo' || ': ' || (x->>'motivo'), '; ') from jsonb_array_elements(v_perfil.campos_conferir) x) || '). Homologacao segue; producao bloqueada ate a confirmacao.','rota',v_rota_perfil));
      end if;
    else
      select t.* into v_fx from f.tributacao_provisoria_nfse_homologacao t
      where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.item_servico = v_perfil.item_servico and t.ativo;
      if not found then
        v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','item_servico','mensagem',format('Perfil %s sem revisao fiscal e sem fixture provisoria de homologacao.', coalesce(v_perfil.item_servico, '?')),'rota',v_rota_perfil));
      elsif v_fx.aliquota_iss is null then
        v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','aliquota_iss','mensagem',format('Fixture do item %s sem aliquota de ISS: %s', v_fx.item_servico, v_fx.pendencia_contador),'rota',v_rota_perfil));
      else
        v_fonte := 'FIXTURE_HOMOLOGACAO';
        f_item := v_fx.item_servico; f_ctrib := v_fx.codigo_tributacao_nacional; f_ctrib_mun := v_fx.codigo_tributacao_municipal; f_nbs := v_fx.codigo_nbs;
        f_desc := v_fx.descricao_servico_padrao; f_local := v_fx.local_prestacao_regra; f_incid := case when v_fx.item_servico like '07.%' then 'LOCAL_PRESTACAO' else 'PRESTADOR' end;
        f_trib_iss := v_fx.tributacao_iss; f_aliq_iss := v_fx.aliquota_iss;
        f_iss_regra := v_fx.iss_retido_regra; f_pcc_regra := v_fx.retencao_pcc_regra; f_irrf_regra := v_fx.retencao_irrf_regra; f_inss_regra := v_fx.retencao_inss_regra;
        f_aliq_pcc := v_fx.aliquota_pcc; f_aliq_irrf := v_fx.aliquota_irrf; f_aliq_inss := v_fx.aliquota_inss;
        f_cst_pis := v_fx.cst_pis_cofins; f_cst_cofins := v_fx.cst_pis_cofins; f_aliq_pis := v_fx.aliquota_pis; f_aliq_cofins := v_fx.aliquota_cofins;
        f_cst_ibs := v_fx.cst_ibs_cbs; f_cclass := v_fx.cclass_trib; f_ibs_uf := v_fx.ibs_uf_aliquota; f_ibs_mun := v_fx.ibs_mun_aliquota; f_cbs := v_fx.cbs_aliquota;
        f_cindop := case when v_fx.item_servico = '07.02' then '040101' else '050103' end; f_pct_fed := null; f_pct_mun := null;
        f_texto_sem := v_fx.texto_sem_retencao; f_texto_com := v_fx.texto_com_retencao;
        v_consumidor_final := coalesce(v_perfil.consumidor_final, v_fx.consumidor_final, 0);
      end if;
    end if;
    if v_fonte is not null and not f.fn_nfse_nbs_compativel(f_item, f_nbs) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','perfil','id',v_perfil.id,'campo','codigo_nbs','mensagem',format('NBS %s incompativel com o subitem %s (capitulo errado; caso da nota 21 real).', f_nbs, f_item),'rota',v_rota_perfil));
    end if;
  end if;

  -- Emitente (prestador).
  select e.* into v_empresa from c.empresa e where e.tenant_id = v_sf.tenant_id and e.id = v_sf.empresa_id and e.deleted_at is null and e.ativo;
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','empresa','mensagem','Empresa ativa nao encontrada.','rota','/configuracoes'));
  else
    select ef.* into v_fiscal from c.empresa_fiscal ef where ef.empresa_id = v_empresa.id and ef.deleted_at is null order by ef.updated_at desc limit 1;
    select ee.* into v_endereco from c.empresa_endereco ee where ee.empresa_id = v_empresa.id and ee.deleted_at is null order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc limit 1;
    v_sede_ibge := regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g');
    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14 then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','cnpj','mensagem','CNPJ do prestador invalido.','rota','/configuracoes')); end if;
    if v_fiscal.id is null or v_fiscal.serie_dps is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','serie_dps','mensagem','Serie da DPS nao configurada no cadastro fiscal da empresa.','rota','/configuracoes')); end if;
    if v_fiscal.id is null or v_fiscal.codigo_opcao_simples_nacional is null or v_fiscal.regime_especial_tributacao is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_opcao_simples_nacional','mensagem','Opcao pelo Simples e regime especial nao informados no cadastro fiscal da empresa.','rota','/configuracoes')); end if;
    if v_sede_ibge !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','empresa','campo','codigo_municipio_ibge','mensagem','Codigo IBGE do endereco fiscal do prestador deve ter 7 digitos.','rota','/configuracoes')); end if;
  end if;

  -- Tomador.
  select c.* into v_cliente from public.clientes c where c.tenant_id = v_sf.tenant_id and c.empresa_id = v_sf.empresa_id and c.id = v_sf.cliente_id and c.ativo is true;
  if not found then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_sf.cliente_id,'campo','cliente','mensagem','Tomador ativo nao encontrado nesta empresa.','rota',v_rota_cliente));
  else
    v_documento := regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g');
    if not ((length(v_documento) = 14 and public.cnpj_valido(v_documento)) or (length(v_documento) = 11 and public.cpf_valido(v_documento))) then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','CNPJ/CPF do tomador invalido.','rota',v_rota_cliente)); end if;
    if exists (select 1 from public.empresas e where e.tenant_id = v_sf.tenant_id and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') <> '' and regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g') = v_documento) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','OS interna (tomador e uma empresa do grupo) nao emite NFS-e por este fluxo.'));
    end if;
    if nullif(btrim(v_cliente.razao_social), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','razao_social','mensagem','Razao social do tomador nao informada.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.logradouro), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','logradouro','mensagem','Logradouro do tomador nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.numero_endereco), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','numero_endereco','mensagem','Numero do endereco do tomador nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.bairro), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','bairro','mensagem','Bairro do tomador nao informado.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cep','mensagem','CEP do tomador deve ter 8 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','codigo_ibge_municipio','mensagem','Codigo IBGE do tomador deve ter 7 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') = '4209102' and nullif(btrim(v_cliente.inscricao_municipal), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','inscricao_municipal','mensagem','Tomador de Joinville sem inscricao municipal (nao enviada na DPS; as NFS-e reais tambem nao levam).','rota',v_rota_cliente));
    end if;
    if nullif(btrim(coalesce(v_cliente.email_nfse, '')), '') is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','email_nfse','mensagem','Tomador sem e-mail de NFS-e; a nota nao sera enviada por e-mail.','rota',v_rota_cliente));
    end if;
  end if;

  -- Municipio de prestacao, incidencia do ISS e competencia (pode ser de mes anterior).
  v_municipio := regexp_replace(coalesce(p_operacao->>'municipio_prestacao_ibge', ''), '[^0-9]', '', 'g');
  if v_municipio = '' and f_local is not null then
    v_municipio := case when f_local = 'SEDE' then v_sede_ibge else regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') end;
  end if;
  if v_municipio !~ '^[0-9]{7}$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','municipio_prestacao_ibge','mensagem','Municipio de prestacao vazio ou invalido (7 digitos IBGE).')); end if;
  v_municipio_incidencia := case when f_incid = 'LOCAL_PRESTACAO' then v_municipio else v_sede_ibge end;
  begin
    v_competencia := coalesce(nullif(btrim(coalesce(p_operacao->>'data_competencia', '')), '')::date, current_date);
  exception when others then v_competencia := null; end;
  if v_competencia is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Data de competencia invalida.'));
  elsif v_competencia > current_date then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','data_competencia','mensagem','Competencia no futuro nao e aceita.'));
  end if;

  -- Aliquota de ISS por (municipio de incidencia x subitem); tabela IBPT por subitem e vigencia.
  if v_fonte is not null then
    select a.aliquota into f_aliq_iss from f.nfse_aliquota_iss a
    where a.tenant_id = v_sf.tenant_id and a.empresa_id = v_sf.empresa_id and a.item_servico = f_item and a.municipio_ibge = v_municipio_incidencia;
    if not found then f_aliq_iss := coalesce(v_perfil.aliquota_iss, v_fx.aliquota_iss); end if;
    select t.federal_pct, t.municipal_pct, t.estadual_pct into f_pct_fed, f_pct_mun, f_pct_est
    from f.nfse_tributos_aproximados t
    where t.tenant_id = v_sf.tenant_id and t.empresa_id = v_sf.empresa_id and t.item_servico = f_item and t.vigencia_inicio <= coalesce(v_competencia, current_date)
    order by t.vigencia_inicio desc limit 1;
    if not found then f_pct_fed := v_perfil.tributos_aprox_federal_pct; f_pct_mun := v_perfil.tributos_aprox_municipal_pct; f_pct_est := 0; end if;
  end if;

  -- Retencoes: override da tela (com justificativa) > regra do perfil (SEMPRE/NUNCA) > cadastro do tomador (POR_TOMADOR).
  v_justificativa := nullif(btrim(coalesce(p_operacao->>'retencao_justificativa', '')), '');
  v_iss_override := case when jsonb_typeof(p_operacao->'iss_retido') = 'boolean' then (p_operacao->>'iss_retido')::boolean end;
  v_pcc_override := case when jsonb_typeof(p_operacao->'retem_pcc') = 'boolean' then (p_operacao->>'retem_pcc')::boolean end;
  v_irrf_override := case when jsonb_typeof(p_operacao->'retem_irrf') = 'boolean' then (p_operacao->>'retem_irrf')::boolean end;
  v_inss_override := case when jsonb_typeof(p_operacao->'retem_inss') = 'boolean' then (p_operacao->>'retem_inss')::boolean end;
  v_conserto_isolado := case when jsonb_typeof(p_operacao->'conserto_isolado') = 'boolean' then (p_operacao->>'conserto_isolado')::boolean end;
  if v_fonte is not null and v_cliente.id is not null then
    v_iss_retido := coalesce(v_iss_override, case f_iss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.iss_retido end);
    v_pcc := coalesce(v_pcc_override, case f_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end);
    v_irrf := coalesce(v_irrf_override, case f_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end);
    v_inss := coalesce(v_inss_override, case f_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end);
    if v_iss_retido is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','iss_retido','mensagem','ISS retido indefinido para este tomador: decida no cadastro fiscal do cliente ou aqui, com justificativa.','rota',v_rota_cliente)); end if;
    if v_pcc is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_pcc','mensagem','Retencao de PIS/COFINS/CSLL indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if v_irrf is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_irrf','mensagem','Retencao de IRRF indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if v_inss is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','retem_inss','mensagem','Retencao de INSS indefinida para este tomador.','rota',v_rota_cliente)); end if;
    if ((v_iss_override is not null and v_iss_override is distinct from case f_iss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.iss_retido end)
        or (v_pcc_override is not null and v_pcc_override is distinct from case f_pcc_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_pcc end)
        or (v_irrf_override is not null and v_irrf_override is distinct from case f_irrf_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_irrf end)
        or (v_inss_override is not null and v_inss_override is distinct from case f_inss_regra when 'NUNCA' then false when 'SEMPRE' then true else v_cliente.retem_inss end))
       and (v_justificativa is null or char_length(v_justificativa) < 15) then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','retencao_justificativa','mensagem','Retencao diferente da regra do perfil/cadastro exige justificativa (15 caracteres ou mais), gravada na observacao.'));
    end if;
    -- CRF nao se aplica a tomador optante do Simples (Lei 10.833/2003, art. 30, §2).
    if coalesce(v_pcc, false) and v_cliente.optante_simples is true then
      v_pcc := false;
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_pcc','mensagem','Tomador optante do Simples Nacional: CRF (PIS/COFINS/CSLL) nao se aplica (Lei 10.833/2003 art. 30 §2).'));
    elsif coalesce(v_pcc, false) and v_cliente.optante_simples is null then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','optante_simples','mensagem','Regime do tomador nao informado: se for optante do Simples, a CRF nao se aplica.','rota',v_rota_cliente));
    end if;
  end if;

  -- Pagamento e parcelas.
  v_pag_forma := nullif(btrim(coalesce(p_operacao->>'pagamento_forma', '')), '');
  if v_pag_forma is null or v_pag_forma !~ '^(0[1-5]|1[0-9]|2[0-4]|9[019])$' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_forma','mensagem','Forma de pagamento invalida ou nao confirmada.')); end if;
  begin v_pag_indicador := nullif(btrim(coalesce(p_operacao->>'pagamento_indicador', '')), '')::smallint; exception when others then v_pag_indicador := null; end;
  if v_pag_indicador is null or v_pag_indicador not in (0, 1) then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_indicador','mensagem','Indique a vista (0) ou a prazo (1).')); end if;
  begin
    v_parcelas := case when v_pag_indicador = 1 then f.fn_nfe_normalizar_parcelas(p_operacao->'pagamento_parcelas') else null end;
  exception when others then
    v_parcelas := null;
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','pagamento_parcelas','mensagem',sqlerrm));
  end;

  -- Linhas, OS e saldo por OS. "MAO DE OBRA" e proibido na descricao.
  for v_item in select si.* from f.solicitacao_item si where si.solicitacao_id = v_sf.id order by si.ordem loop
    v_linhas := v_linhas + 1;
    if v_item.valor_servico is null or v_item.valor_servico <= 0 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_servico','mensagem',format('Linha %s: valor do servico deve ser maior que zero.', v_item.ordem))); continue;
    end if;
    if nullif(btrim(coalesce(v_item.descricao_servico, '')), '') is null then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','descricao_servico','mensagem',format('Linha %s: descricao do servico obrigatoria.', v_item.ordem))); end if;
    v_proibido := f.fn_nfse_texto_proibido(v_item.descricao_servico);
    if v_proibido is not null then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','descricao_servico','mensagem',format('Linha %s: a expressao "%s" e proibida na discriminacao (define cessao de mao de obra: INSS 11%%, IRRF 1%%, CRF 4,65%%). Descreva o resultado entregue.', v_item.ordem, v_proibido)));
    end if;
    select os.* into v_os from public.ordens_servico os where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id and os.tipo_documento = 'OS' and os.id::text = v_item.origem_id;
    if not found then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','origem_id','mensagem',format('Linha %s: OS %s nao encontrada.', v_item.ordem, v_item.origem_id))); continue; end if;
    if lower(coalesce(v_os.status_fluxo, v_os.status::text, '')) = 'cancelada' then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','status','mensagem',format('Linha %s: a OS %s esta cancelada.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id)); end if;
    if v_os.cliente_id is distinct from v_sf.cliente_id then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os.id,'campo','cliente_id','mensagem',format('Linha %s: a OS %s e de outro tomador.', v_item.ordem, coalesce(v_os.numero_os, v_os.id::text)),'rota','/os/' || v_os.id)); end if;
    if lower(coalesce(v_os.status_fluxo, '')) = 'em_andamento' then v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','status_fluxo','mensagem',format('OS %s ainda em andamento.', coalesce(v_os.numero_os, v_os.id::text)))); end if;
    -- Conserto isolado: a flag da tela grava na OS; a excecao vale so se todas as OS da nota forem conserto isolado.
    if v_conserto_isolado is not null and v_conserto_isolado is distinct from v_os.conserto_isolado then
      update public.ordens_servico set conserto_isolado = v_conserto_isolado, atualizado_em = now() where id = v_os.id;
      v_os.conserto_isolado := v_conserto_isolado;
    end if;
    if not coalesce(v_os.conserto_isolado, false) then v_todas_conserto := false; end if;
    v_bruto := v_bruto + v_item.valor_servico;
    v_linhas_desc := v_linhas_desc || jsonb_build_object('descricao', coalesce(v_item.descricao_servico, f_desc), 'os_numero', coalesce(v_os.numero_os, v_os.id::text));
    if not (coalesce(v_os.numero_os, v_os.id::text) = any(v_os_numeros)) then v_os_numeros := v_os_numeros || coalesce(v_os.numero_os, v_os.id::text); end if;
  end loop;
  if v_linhas = 0 then v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','itens','mensagem','A solicitacao nao tem linhas.')); v_todas_conserto := false; end if;
  if coalesce(v_pcc, false) and f_excecao_conserto and v_todas_conserto then
    v_pcc := false;
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','conserto_isolado','mensagem','OS marcada como conserto isolado (IN SRF 459/2004 art. 1 §2 II): CRF nao retida nesta nota.'));
  end if;

  for v_os_total in
    select si.origem_id::integer as os_id, round(sum(si.valor_servico), 2) as total from f.solicitacao_item si
    where si.solicitacao_id = v_sf.id and si.origem_id ~ '^[0-9]+$' group by si.origem_id
  loop
    begin select * into v_saldo from f.fn_os_saldo_a_faturar(v_sf.tenant_id, v_sf.empresa_id, v_os_total.os_id); exception when others then v_saldo := null; end;
    if v_saldo is null then continue; end if;
    v_reserva_propria := case when v_sf.status <> 'CANCELADA' then v_os_total.total else 0 end;
    v_reserva_substituida := 0;
    if v_sf.substitui_solicitacao_id is not null then
      select coalesce(round(sum(si.valor_servico), 2), 0) into v_reserva_substituida
      from f.solicitacao_item si join f.solicitacao_faturamento s on s.id = si.solicitacao_id
      where si.solicitacao_id = v_sf.substitui_solicitacao_id and si.origem_id = v_os_total.os_id::text and s.status <> 'CANCELADA'
        and not exists (select 1 from f.documento_fiscal_emissao e join f.documento_fiscal d on d.id = e.documento_fiscal_id where e.solicitacao_id = s.id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA');
      select v_reserva_substituida + coalesce(sum(d.valor_total), 0) into v_reserva_substituida from f.documento_fiscal d
      where d.id = v_sf.substitui_documento_fiscal_id and upper(coalesce(d.nfse_status, '')) = 'EMITIDA' and d.os_id_import = v_os_total.os_id;
    end if;
    if v_saldo.valor_pedido > 0 and v_os_total.total > v_saldo.saldo + v_reserva_propria + v_reserva_substituida + 0.005 then
      v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','os','id',v_os_total.os_id,'campo','valor_servico','mensagem',format('OS %s: total das linhas R$ %s acima do saldo da OS R$ %s.', v_os_total.os_id, to_char(v_os_total.total, 'FM999G999G990D00'), to_char(v_saldo.saldo + v_reserva_propria + v_reserva_substituida, 'FM999G999G990D00')),'rota','/os/' || v_os_total.os_id));
    end if;
  end loop;

  v_pedido := case when p_operacao ? 'pedido_cliente' then nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') else v_sf.pedido_cliente end;
  v_pedido_item := nullif(btrim(coalesce(p_operacao->>'pedido_item', '')), '');
  v_observacao := nullif(btrim(coalesce(p_operacao->>'observacao', '')), '');
  if v_pedido is null then v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','pedido_cliente','mensagem','Sem pedido de compra do tomador.')); end if;
  if f.fn_nfse_texto_proibido(v_observacao) is not null then
    v_pend := v_pend || jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','observacao','mensagem','A expressao MAO DE OBRA e proibida na observacao da nota.'));
  end if;

  if jsonb_array_length(v_pend) > 0 then
    update f.solicitacao_faturamento set emitente_snapshot = null, destinatario_snapshot = null, operacao_snapshot = null, snapshot_cadastro_em = null,
        revisao_fiscal_confirmada_em = null, revisao_fiscal_confirmada_por = null, updated_at = now() where id = v_sf.id;
    return jsonb_build_object('ok', false, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente, 'pendencias', v_pend, 'avisos', v_avisos);
  end if;

  -- Valores. Base de toda retencao = valor integral do servico. Dispensa quando o valor retido <= R$ 10,00
  -- (Lei 9.430/1996 art. 67; Lei 10.833/2003 art. 31 §3).
  v_valor_iss := round(v_bruto * f_aliq_iss / 100, 2);
  v_v_irrf := case when v_irrf then round(v_bruto * coalesce(f_aliq_irrf, 0) / 100, 2) else 0 end;
  v_v_pcc := case when v_pcc then round(v_bruto * coalesce(f_aliq_pcc, 0) / 100, 2) else 0 end;
  v_v_inss := case when v_inss then round(v_bruto * coalesce(f_aliq_inss, 0) / 100, 2) else 0 end;
  if v_irrf and v_v_irrf <= 10 then v_irrf := false; v_v_irrf := 0; v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_irrf','mensagem','IRRF dispensado: valor retido <= R$ 10,00 (Lei 9.430/1996 art. 67).')); end if;
  if v_pcc and v_v_pcc <= 10 then v_pcc := false; v_v_pcc := 0; v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_pcc','mensagem','CRF dispensada: valor retido <= R$ 10,00 (Lei 10.833/2003 art. 31 §3).')); end if;
  if v_inss and v_v_inss <= 10 then v_inss := false; v_v_inss := 0; v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('campo','retem_inss','mensagem','INSS dispensado: valor retido <= R$ 10,00.')); end if;
  v_liquido := v_bruto - (case when v_iss_retido then v_valor_iss else 0 end) - v_v_irrf - v_v_pcc - v_v_inss;
  if v_iss_retido then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'ISS', 'base', v_bruto, 'aliquota', f_aliq_iss, 'valor', v_valor_iss); end if;
  if v_irrf then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'IRRF', 'base', v_bruto, 'aliquota', f_aliq_irrf, 'valor', v_v_irrf); end if;
  if v_pcc then
    v_retencoes := v_retencoes
      || jsonb_build_object('tributo', 'PIS', 'base', v_bruto, 'aliquota', 0.65, 'valor', round(v_bruto * 0.65 / 100, 2))
      || jsonb_build_object('tributo', 'COFINS', 'base', v_bruto, 'aliquota', 3.00, 'valor', round(v_bruto * 3.00 / 100, 2))
      || jsonb_build_object('tributo', 'CSLL', 'base', v_bruto, 'aliquota', 1.00, 'valor', v_v_pcc - round(v_bruto * 0.65 / 100, 2) - round(v_bruto * 3.00 / 100, 2));
  end if;
  if v_inss then v_retencoes := v_retencoes || jsonb_build_object('tributo', 'INSS', 'base', v_bruto, 'aliquota', f_aliq_inss, 'valor', v_v_inss); end if;
  v_tem_federal := v_irrf or v_pcc or v_inss;
  -- IBS/CBS (LC 214/2025 art. 12 §2): base = servico - ISS; arredondamento meio-par como o ambiente nacional.
  v_ibs_base := v_bruto - v_valor_iss;
  v_ibs_uf := f.fn_round_half_even(v_ibs_base * coalesce(f_ibs_uf, 0) / 100, 2);
  v_ibs_mun := f.fn_round_half_even(v_ibs_base * coalesce(f_ibs_mun, 0) / 100, 2);
  v_cbs := f.fn_round_half_even(v_ibs_base * coalesce(f_cbs, 0) / 100, 2);
  v_texto_retencao := case when v_tem_federal then coalesce(f_texto_com, f_texto_sem) else f_texto_sem end;
  v_obs_composta := concat_ws(' ', v_observacao,
    case when v_justificativa is not null then 'RETENCAO AJUSTADA: ' || v_justificativa end,
    case when f_excecao_conserto and v_todas_conserto then 'MANUTENCAO EM CARATER ISOLADO (IN SRF 459/2004, ART. 1, §2, II)' end);
  v_discriminacao := f.fn_nfse_discriminacao(v_linhas_desc, v_pedido, v_pedido_item, v_parcelas, current_date, v_iss_retido, v_texto_retencao,
    nullif(v_obs_composta, ''), v_cliente.nfse_discriminacao_template);
  v_proibido := f.fn_nfse_texto_proibido(v_discriminacao);
  if v_proibido is not null then
    update f.solicitacao_faturamento set emitente_snapshot = null, destinatario_snapshot = null, operacao_snapshot = null, snapshot_cadastro_em = null, updated_at = now() where id = v_sf.id;
    return jsonb_build_object('ok', false, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente,
      'pendencias', jsonb_build_array(jsonb_build_object('entidade','solicitacao','campo','descricao_servico','mensagem','A discriminacao composta contem "' || v_proibido || '" (proibido).')), 'avisos', v_avisos);
  end if;

  update f.solicitacao_item si
  set codigo_tributacao_nacional = f_ctrib, codigo_tributacao_municipal = f_ctrib_mun, codigo_nbs = f_nbs,
      tributacao_iss = f_trib_iss, aliquota_iss = f_aliq_iss, iss_retido = v_iss_retido,
      aliquota_irrf = case when v_irrf then f_aliq_irrf end, aliquota_pcc = case when v_pcc then f_aliq_pcc end, aliquota_inss = case when v_inss then f_aliq_inss end,
      local_prestacao_ibge = v_municipio,
      cst_pis = f_cst_pis, aliquota_pis = f_aliq_pis, cst_cofins = f_cst_cofins, aliquota_cofins = f_aliq_cofins,
      cst_ibs_cbs = f_cst_ibs, cclass_trib = f_cclass,
      ibs_cbs_json = jsonb_build_object('ibs_uf_aliquota', f_ibs_uf, 'ibs_mun_aliquota', f_ibs_mun, 'cbs_aliquota', f_cbs),
      perfil_operacao_id = v_perfil.id, perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id,
      tributacao_fonte = v_fonte, descricao = coalesce(si.descricao_servico, si.descricao)
  where si.solicitacao_id = v_sf.id;

  update f.solicitacao_faturamento sf
  set perfil_operacao_id = v_perfil.id, natureza_operacao = 'PRESTACAO_SERVICO', consumidor_final = v_consumidor_final,
      municipio_prestacao_ibge = v_municipio, data_competencia = v_competencia,
      iss_retido = v_iss_retido, retem_pcc = v_pcc, retem_irrf = v_irrf, retem_inss = v_inss, retencao_justificativa = v_justificativa,
      pagamento_forma = v_pag_forma, pagamento_indicador = v_pag_indicador, pagamento_descricao = nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''), pagamento_parcelas = v_parcelas,
      pedido_cliente = v_pedido, pedido_item = v_pedido_item, observacao = coalesce(v_observacao, sf.observacao),
      modalidade_frete = null, transportador_dados = null, volumes_dados = null,
      destino_uf_confirmada = upper(v_cliente.uf), destino_confirmado_em = now(), destino_confirmado_por = v_usuario_id,
      perfil_aplicado_em = now(), perfil_aplicado_por = v_usuario_id, revisao_fiscal_confirmada_em = now(), revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = jsonb_build_object(
        'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'), 'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
        'telefone', v_empresa.telefone, 'email', v_empresa.email, 'inscricao_municipal', nullif(btrim(coalesce(v_fiscal.inscricao_municipal, '')), ''),
        'codigo_opcao_simples_nacional', v_fiscal.codigo_opcao_simples_nacional, 'regime_especial_tributacao', v_fiscal.regime_especial_tributacao, 'serie_dps', v_fiscal.serie_dps,
        'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero, 'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro, 'cidade', v_endereco.cidade, 'uf', upper(v_endereco.uf::text),
        'codigo_municipio_ibge', v_sede_ibge, 'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')),
      destinatario_snapshot = jsonb_build_object(
        'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social, 'inscricao_municipal', nullif(btrim(coalesce(v_cliente.inscricao_municipal, '')), ''),
        'email', coalesce(nullif(btrim(coalesce(v_cliente.email_nfse, '')), ''), nullif(btrim(coalesce(v_cliente.email_financeiro, '')), '')),
        'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro, 'numero_endereco', v_cliente.numero_endereco, 'complemento', v_cliente.complemento,
        'bairro', v_cliente.bairro, 'cidade', v_cliente.cidade, 'uf', upper(v_cliente.uf), 'optante_simples', v_cliente.optante_simples,
        'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'), 'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')),
      operacao_snapshot = jsonb_build_object(
        'natureza_operacao', 'PRESTACAO_SERVICO', 'modelo', 'NFSE', 'tributacao_fonte', v_fonte, 'consumidor_final', v_consumidor_final,
        'servico', jsonb_build_object(
          'perfil_operacao_id', v_perfil.id, 'perfil_codigo', v_perfil.codigo, 'item_servico', f_item,
          'codigo_tributacao_nacional', f_ctrib, 'codigo_tributacao_municipal', f_ctrib_mun, 'codigo_nbs', f_nbs,
          'municipio_prestacao_ibge', v_municipio, 'municipio_incidencia_iss', v_municipio_incidencia, 'data_competencia', v_competencia,
          'tributacao_iss', f_trib_iss, 'aliquota_iss', f_aliq_iss, 'iss_retido', v_iss_retido, 'retem_pcc', v_pcc, 'retem_irrf', v_irrf, 'retem_inss', v_inss,
          'conserto_isolado', (f_excecao_conserto and v_todas_conserto),
          'valor_bruto', v_bruto, 'valor_iss', v_valor_iss, 'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss, 'valor_liquido', v_liquido, 'retencoes', v_retencoes,
          'cst_pis_cofins', f_cst_pis, 'aliquota_pis', f_aliq_pis, 'aliquota_cofins', f_aliq_cofins,
          'cst_ibs_cbs', f_cst_ibs, 'cclass_trib', f_cclass, 'ibs_uf_aliquota', f_ibs_uf, 'ibs_mun_aliquota', f_ibs_mun, 'cbs_aliquota', f_cbs,
          'ibs_cbs', jsonb_build_object('base', v_ibs_base, 'ibs_uf', v_ibs_uf, 'ibs_mun', v_ibs_mun, 'cbs', v_cbs, 'total', v_ibs_uf + v_ibs_mun + v_cbs, 'municipio_incidencia', v_municipio),
          'codigo_indicador_operacao', f_cindop, 'tributos_aprox_federal_pct', f_pct_fed, 'tributos_aprox_municipal_pct', f_pct_mun, 'tributos_aprox_estadual_pct', coalesce(f_pct_est, 0),
          'descricao_servico', v_discriminacao, 'texto_retencao', v_texto_retencao, 'os_numeros', to_jsonb(v_os_numeros)),
        'pedido', jsonb_build_object('pedido_cliente', v_pedido, 'pedido_item', v_pedido_item),
        'substituicao', case when v_sf.substitui_documento_fiscal_id is null then null else jsonb_build_object(
          'documento_fiscal_id', v_sf.substitui_documento_fiscal_id, 'solicitacao_id', v_sf.substitui_solicitacao_id, 'codigo', v_sf.substituicao_codigo, 'motivo', v_sf.substituicao_motivo,
          'chave', (select e.chave_nfse from f.documento_fiscal_emissao e where e.documento_fiscal_id = v_sf.substitui_documento_fiscal_id limit 1)) end,
        'pagamento', jsonb_build_object('forma', v_pag_forma, 'indicador', v_pag_indicador, 'descricao', nullif(btrim(coalesce(p_operacao->>'pagamento_descricao', '')), ''), 'parcelas', v_parcelas, 'fatura_numero', null)),
      snapshot_cadastro_em = now(), updated_at = now()
  where sf.id = v_sf.id;

  if nullif(btrim(coalesce(p_operacao->>'pedido_cliente', '')), '') is not null then
    update public.ordens_servico os set pedido_compra = btrim(p_operacao->>'pedido_cliente'), atualizado_em = now()
    where os.tenant_id = v_sf.tenant_id and os.empresa_id = v_sf.empresa_id
      and os.id::text in (select si.origem_id from f.solicitacao_item si where si.solicitacao_id = v_sf.id)
      and os.pedido_compra is distinct from btrim(p_operacao->>'pedido_cliente');
  end if;

  return jsonb_build_object(
    'ok', true, 'solicitacao_id', v_sf.id, 'cliente_id', v_sf.cliente_id, 'rota_cliente', v_rota_cliente, 'pendencias', '[]'::jsonb, 'avisos', v_avisos,
    'previa', jsonb_build_object(
      'item_servico', f_item, 'codigo_tributacao_nacional', f_ctrib, 'codigo_nbs', f_nbs, 'municipio_prestacao_ibge', v_municipio, 'municipio_incidencia_iss', v_municipio_incidencia, 'data_competencia', v_competencia,
      'valor_bruto', v_bruto, 'aliquota_iss', f_aliq_iss, 'valor_iss', v_valor_iss, 'iss_retido', v_iss_retido,
      'valor_irrf', v_v_irrf, 'valor_pcc', v_v_pcc, 'valor_inss', v_v_inss, 'valor_liquido', v_liquido,
      'ibs_cbs', jsonb_build_object('base', v_ibs_base, 'ibs_uf', v_ibs_uf, 'ibs_mun', v_ibs_mun, 'cbs', v_cbs, 'total', v_ibs_uf + v_ibs_mun + v_cbs),
      'tributos_aprox', jsonb_build_object('federal_pct', f_pct_fed, 'municipal_pct', f_pct_mun, 'federal', round(v_bruto * coalesce(f_pct_fed, 0) / 100, 2), 'municipal', round(v_bruto * coalesce(f_pct_mun, 0) / 100, 2)),
      'retencoes', v_retencoes, 'parcelas', v_parcelas, 'descricao_servico', v_discriminacao, 'tributacao_fonte', v_fonte,
      'campos_conferir', v_perfil.campos_conferir));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Fixture: frase legal corrigida; 17.06 fora do catalogo
-- ---------------------------------------------------------------------------
update f.tributacao_provisoria_nfse_homologacao
set texto_com_retencao = 'PARA OS SERVICOS DE LAUDOS E PERICIAS, DEVERA SER RETIDO IRRF A ALIQUOTA DE 1,5% E CRF A ALIQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1%). TRIBUTOS INCIDENTES SOBRE O PRECO LEI 12.741/2012'
where texto_com_retencao like '%LEI 12/2012%';
update f.tributacao_provisoria_nfse_homologacao set ativo = false, pendencia_contador = 'Subitem 17.06 (propaganda e publicidade) retirado do catalogo: a NFS-e 39 usou 17.06 por erro; documentacao tecnica e laudos sao 17.09.'
where item_servico = '17.06';
update f.perfil_operacao set faixa_automacao = 'BLOQUEADO', habilitado_producao = false,
  justificativa_faixa = 'Subitem 17.06 (propaganda e publicidade) nao existe no catalogo de servicos da Segau; laudos e documentacao tecnica sao 17.09 (nota 39 real usou 17.06 por erro).'
where modelo = 'NFSE' and item_servico = '17.06';
