-- Estrutura inicial de centros e regras de alta confianca para as duas
-- empresas do grupo. O centro responde "onde"; plano e OS continuam sendo
-- dimensoes independentes.

do $centros$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
begin
  insert into f.centro_custo (
    tenant_id,
    empresa_id,
    codigo,
    nome,
    parent_id,
    ativo
  )
  select
    v_tenant_id,
    e.id,
    estrutura.codigo,
    estrutura.nome,
    null,
    true
  from c.empresa e
  cross join (
    values
      ('ADM_FIN',   'ADMINISTRATIVO E FINANCEIRO'),
      ('PESSOAS',   'PESSOAS'),
      ('COMERCIAL',  'COMERCIAL'),
      ('PRODUCAO',   'PRODUÇÃO E ENGENHARIA'),
      ('CAMPO',      'SERVIÇOS EM CAMPO'),
      ('EST_LOG',    'ESTOQUE E LOGÍSTICA'),
      ('FROTA',      'FROTA'),
      ('TI',         'TECNOLOGIA DA INFORMAÇÃO'),
      ('ESTRUTURA',  'ESTRUTURA E UTILIDADES'),
      ('INVEST',     'INVESTIMENTOS E EXPANSÃO')
  ) as estrutura(codigo, nome)
  where e.tenant_id = v_tenant_id
    and e.id in (
      'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid,
      'de04c78a-4fed-4118-8661-52163f93bc8b'::uuid
    )
    and e.ativo
    and e.deleted_at is null
  on conflict (tenant_id, empresa_id, codigo) do nothing;
end;
$centros$;

-- Regras iniciais deliberadamente conservadoras. Motivos ambiguos, motivos
-- sem plano de contas e custos de pessoal permanecem para revisao humana.
do $regras$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa record;
  v_mapeamento record;
  v_motivo_id uuid;
  v_plano_id uuid;
  v_centro_id uuid;
  v_regra_id uuid;
begin
  for v_empresa in
    select e.id
    from c.empresa e
    where e.tenant_id = v_tenant_id
      and e.id in (
        'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid,
        'de04c78a-4fed-4118-8661-52163f93bc8b'::uuid
      )
      and e.ativo
      and e.deleted_at is null
  loop
    for v_mapeamento in
      select *
      from (
        values
          ('ESTOQUE',                  'EST_LOG'),
          ('EST_MATERIA_PRIMA',        'EST_LOG'),
          ('EST_REVENDA',              'EST_LOG'),
          ('INVESTIMENTO',             'INVEST'),
          ('IMOB_AQUISICAO',           'INVEST'),
          ('IMOB_MELHORIA',            'INVEST'),
          ('OPEX_ARRENDAMENTO',        'INVEST'),
          ('OS',                       'PRODUCAO'),
          ('OS_MATERIAL_DIRETO',       'PRODUCAO'),
          ('OS_SERVICO_TERCEIRO',      'PRODUCAO'),
          ('SERV_OS',                  'PRODUCAO'),
          ('CONSUMO_EPI',              'PRODUCAO'),
          ('EPI',                      'PRODUCAO'),
          ('CONSUMO_FERRAMENTAS',      'PRODUCAO'),
          ('FERRAMENTAS',              'PRODUCAO'),
          ('CUSTO_COMBUSTIVEL_MUNCK',  'CAMPO'),
          ('OS_FRETE',                 'CAMPO'),
          ('COMBUSTIVEL',              'FROTA'),
          ('OPEX_COMBUSTIVEL',         'FROTA'),
          ('PNEUS',                    'FROTA'),
          ('SERV_TI',                  'TI'),
          ('INFORMATICA',              'TI'),
          ('OPEX_INTERNET',            'TI'),
          ('OPEX_ENERGIA',             'ESTRUTURA'),
          ('OPEX_AGUA',                'ESTRUTURA'),
          ('LIMPEZA',                  'ESTRUTURA'),
          ('ESCRITORIO',               'ESTRUTURA'),
          ('OPEX_CONTABILIDADE',       'ADM_FIN'),
          ('SERV_CONTABIL',            'ADM_FIN'),
          ('TRIB_DIVERSOS',            'ADM_FIN'),
          ('REP_REFEI',                'COMERCIAL')
      ) as mapa(motivo_codigo, centro_codigo)
  loop
      v_motivo_id := null;
      v_plano_id := null;
      v_centro_id := null;
      v_regra_id := null;

      select mc.id, mc.plano_contas_id
        into v_motivo_id, v_plano_id
      from f.motivo_compra mc
      join f.plano_contas pc
        on pc.tenant_id = mc.tenant_id
       and pc.id = mc.plano_contas_id
       and pc.tipo = 'ANALITICA'
       and pc.ativo
       and pc.deleted_at is null
      where mc.tenant_id = v_tenant_id
        and upper(mc.codigo) = upper(v_mapeamento.motivo_codigo)
        and mc.ativo
        and mc.deleted_at is null
      limit 1;

      select cc.id
        into v_centro_id
      from f.centro_custo cc
      where cc.tenant_id = v_tenant_id
        and cc.empresa_id = v_empresa.id
        and cc.codigo = v_mapeamento.centro_codigo
        and cc.ativo
        and cc.deleted_at is null
      limit 1;

      if v_motivo_id is null
         or v_plano_id is null
         or v_centro_id is null
      then
        continue;
      end if;

      select rr.id
        into v_regra_id
      from f.regra_rateio rr
      where rr.tenant_id = v_tenant_id
        and rr.empresa_id = v_empresa.id
        and rr.motivo_compra_id = v_motivo_id
        and rr.ativo
        and rr.deleted_at is null
      limit 1;

      if v_regra_id is not null then
        continue;
      end if;

      insert into f.regra_rateio (
        tenant_id,
        empresa_id,
        motivo_compra_id,
        ativo
      )
      values (
        v_tenant_id,
        v_empresa.id,
        v_motivo_id,
        true
      )
      returning id into v_regra_id;

      insert into f.regra_rateio_item (
        tenant_id,
        regra_rateio_id,
        plano_contas_id,
        centro_custo_id,
        percentual
      )
      values (
        v_tenant_id,
        v_regra_id,
        v_plano_id,
        v_centro_id,
        100.0000
      );
    end loop;
  end loop;
end;
$regras$;
