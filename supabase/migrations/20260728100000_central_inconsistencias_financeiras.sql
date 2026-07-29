begin;

-- Central de Inconsistencias Financeiras.
--
-- A deteccao e calculada sobre os fatos atuais. Somente a decisao de ignorar
-- ou o registro de uma correcao fica persistido. A trilha historica e gravada
-- em f.evento_financeiro, sem alterar titulo, parcela ou pagamento.

create table if not exists f.inconsistencia_financeira_tratamento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  titulo_id uuid not null,
  tipo text not null,
  status text not null,
  fingerprint text not null,
  justificativa text not null,
  dados_snapshot jsonb not null default '{}'::jsonb,
  tratado_em timestamptz not null default now(),
  tratado_por uuid default a.fn_current_usuario_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default a.fn_current_usuario_id(),
  updated_by uuid,
  deleted_at timestamptz,
  constraint fk_inconsistencia_financeira_tratamento_titulo
    foreign key (titulo_id) references f.titulo(id),
  constraint fk_inconsistencia_financeira_tratamento_empresa
    foreign key (empresa_id) references c.empresa(id),
  constraint ck_inconsistencia_financeira_tratamento_tipo
    check (
      tipo in (
        'SEM_MOTIVO_COMPRA',
        'SEM_REGRA_RATEIO',
        'SEM_RATEIO',
        'SEM_PLANO_CONTAS',
        'SEM_CENTRO_CUSTO',
        'DESP_GERAL',
        'RATEIO_PERCENTUAL_INCORRETO',
        'RATEIO_VALOR_INCORRETO',
        'PLANO_INVALIDO',
        'CENTRO_INVALIDO',
        'PLANO_DIVERGENTE_MOTIVO',
        'POSSIVEL_DUPLICIDADE'
      )
    ),
  constraint ck_inconsistencia_financeira_tratamento_status
    check (status in ('IGNORADA', 'TRATADA')),
  constraint ck_inconsistencia_financeira_tratamento_justificativa
    check (length(btrim(justificativa)) >= 10),
  constraint ck_inconsistencia_financeira_tratamento_fingerprint
    check (length(fingerprint) = 32)
);

comment on table f.inconsistencia_financeira_tratamento is
  'Estado atual de ignorado/tratado por titulo e tipo. Ignorados so permanecem validos enquanto o fingerprint dos dados nao mudar.';

create unique index if not exists
  uq_inconsistencia_financeira_tratamento_ativo
  on f.inconsistencia_financeira_tratamento (
    tenant_id,
    empresa_id,
    titulo_id,
    tipo
  )
  where deleted_at is null;

create index if not exists
  idx_inconsistencia_financeira_tratamento_escopo
  on f.inconsistencia_financeira_tratamento (
    tenant_id,
    empresa_id,
    status,
    tratado_em desc
  )
  where deleted_at is null;

create index if not exists idx_titulo_inconsistencia_financeira_escopo
  on f.titulo (
    tenant_id,
    empresa_id,
    tipo,
    competencia_date,
    emissao_date
  )
  where deleted_at is null and status <> 'CANCELADO';

create or replace function f.trg_inconsistencia_financeira_tratamento_validar()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if not exists (
    select 1
    from f.titulo t
    where t.id = new.titulo_id
      and t.tenant_id = new.tenant_id
      and t.empresa_id = new.empresa_id
      and t.tipo = 'AP'
  ) then
    raise exception using
      errcode = '23503',
      message = 'Tratamento: titulo AP invalido ou fora do tenant/empresa.';
  end if;

  if not exists (
    select 1
    from c.empresa e
    where e.id = new.empresa_id
      and e.tenant_id = new.tenant_id
      and e.deleted_at is null
  ) then
    raise exception using
      errcode = '23503',
      message = 'Tratamento: empresa invalida ou fora do tenant.';
  end if;

  new.justificativa := btrim(new.justificativa);
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.updated_by := a.fn_current_usuario_id();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_inconsistencia_financeira_tratamento_validar
  on f.inconsistencia_financeira_tratamento;

create trigger trg_inconsistencia_financeira_tratamento_validar
before insert or update
on f.inconsistencia_financeira_tratamento
for each row
execute function f.trg_inconsistencia_financeira_tratamento_validar();

alter table f.inconsistencia_financeira_tratamento
  enable row level security;

drop policy if exists inconsistencia_financeira_tratamento_select
  on f.inconsistencia_financeira_tratamento;

create policy inconsistencia_financeira_tratamento_select
on f.inconsistencia_financeira_tratamento
for select
to authenticated
using (f.pode_ler_regras_rateio(tenant_id, empresa_id));

revoke all on table f.inconsistencia_financeira_tratamento
  from public, anon, authenticated;
grant select on table f.inconsistencia_financeira_tratamento
  to authenticated, service_role;

revoke all on function
  f.trg_inconsistencia_financeira_tratamento_validar()
  from public;

-- Snapshot usado para auditoria e para afirmar que uma correcao da central
-- nao alterou valor, vencimento, saldo ou pagamento.
create or replace function f.snapshot_inconsistencia_financeira_titulo(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  select jsonb_build_object(
    'titulo', jsonb_build_object(
      'id', t.id,
      'tipo', t.tipo,
      'status', t.status,
      'origem', t.origem,
      'descricao', t.descricao,
      'fornecedorId', t.fornecedor_id,
      'documentoFiscalId', t.documento_fiscal_id,
      'emissao', t.emissao_date,
      'competencia', t.competencia_date,
      'valorTotal', t.valor_total,
      'valorAberto', t.valor_aberto,
      'motivoCompraId', t.motivo_compra_id
    ),
    'rateios', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', tr.id,
          'planoContasId', tr.plano_contas_id,
          'centroCustoId', tr.centro_custo_id,
          'osId', tr.os_id,
          'percentual', tr.percentual,
          'valor', tr.valor,
          'origemRateio', tr.origem_rateio,
          'regraRateioId', tr.regra_rateio_id,
          'regraItemId', tr.regra_item_id
        )
        order by tr.id
      )
      from f.titulo_rateio tr
      where tr.tenant_id = p_tenant_id
        and tr.titulo_id = p_titulo_id
        and tr.deleted_at is null
    ), '[]'::jsonb),
    'imutaveis', jsonb_build_object(
      'valorTotal', t.valor_total,
      'valorAberto', t.valor_aberto,
      'parcelas', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', tp.id,
            'numero', tp.numero,
            'vencimento', tp.vencimento_date,
            'valor', tp.valor,
            'valorAberto', tp.valor_aberto
          )
          order by tp.id
        )
        from f.titulo_parcela tp
        where tp.tenant_id = p_tenant_id
          and tp.titulo_id = p_titulo_id
          and tp.deleted_at is null
      ), '[]'::jsonb),
      'pagamentos', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'pagamentoItemId', pi.id,
            'pagamentoId', pag.id,
            'parcelaId', pi.titulo_parcela_id,
            'data', pag.data_pagamento,
            'valorItem', pi.valor,
            'valorPagamento', pag.valor
          )
          order by pi.id
        )
        from f.titulo_parcela tp
        join f.pagamento_item pi
          on pi.tenant_id = p_tenant_id
         and pi.titulo_parcela_id = tp.id
         and pi.deleted_at is null
        join f.pagamento pag
          on pag.tenant_id = p_tenant_id
         and pag.empresa_id = p_empresa_id
         and pag.id = pi.pagamento_id
         and pag.deleted_at is null
        where tp.tenant_id = p_tenant_id
          and tp.titulo_id = p_titulo_id
          and tp.deleted_at is null
      ), '[]'::jsonb)
    )
  )
  from f.titulo t
  where t.id = p_titulo_id
    and t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id;
$$;

revoke all on function f.snapshot_inconsistencia_financeira_titulo(
  uuid,
  uuid,
  uuid
) from public, anon, authenticated;

-- Funcao interna, somente leitura, que normaliza os tipos detectados.
create or replace function f.detectar_inconsistencias_financeiras(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_inicio date default null,
  p_data_fim date default null
)
returns table (
  titulo_id uuid,
  tipo text,
  prioridade text,
  data_referencia date,
  fornecedor_id integer,
  fornecedor_nome text,
  documento text,
  descricao text,
  valor_total numeric,
  motivo_compra_id uuid,
  motivo_codigo text,
  motivo_nome text,
  plano_atual_id uuid,
  plano_atual_codigo text,
  plano_atual_nome text,
  centro_atual_id uuid,
  centro_atual_codigo text,
  centro_atual_nome text,
  total_rateios integer,
  total_percentual numeric,
  total_rateado numeric,
  tem_rateio_explicito boolean,
  detalhe text,
  sugestao text,
  corrigivel boolean,
  pode_criar_regra boolean,
  fingerprint text,
  dados jsonb
)
language sql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  with base_inicial as (
    select
      t.id as titulo_id,
      t.fornecedor_id,
      coalesce(forn.nome, 'SEM FORNECEDOR')::text as fornecedor_nome,
      coalesce(df.numero, df.chave_acesso, t.documento_fiscal_id::text)
        as documento,
      t.documento_fiscal_id,
      t.descricao,
      t.valor_total,
      t.updated_at as titulo_updated_at,
      coalesce(
        t.competencia_date,
        t.emissao_date,
        parcelas.primeiro_vencimento,
        t.created_at::date
      ) as data_referencia,
      coalesce(aprovacao.motivo_compra_id, t.motivo_compra_id)
        as motivo_compra_id,
      mc.codigo as motivo_codigo,
      mc.nome as motivo_nome,
      mc.plano_contas_id as plano_motivo_id,
      regra.id as regra_rateio_id,
      coalesce(rateio.total_rateios, 0)::integer as total_rateios,
      coalesce(rateio.total_percentual, 0)::numeric as total_percentual,
      coalesce(rateio.total_rateado, 0)::numeric as total_rateado,
      coalesce(rateio.tem_explicito, false) as tem_rateio_explicito,
      coalesce(rateio.tem_plano_nulo, false) as tem_plano_nulo,
      coalesce(rateio.tem_centro_nulo, false) as tem_centro_nulo,
      coalesce(rateio.tem_desp_geral, false) as tem_desp_geral,
      coalesce(rateio.tem_plano_invalido, false) as tem_plano_invalido,
      coalesce(rateio.tem_centro_invalido, false) as tem_centro_invalido,
      coalesce(
        rateio.tem_plano_divergente_motivo,
        false
      ) as tem_plano_divergente_motivo,
      rateio.plano_atual_id,
      rateio.plano_atual_codigo,
      rateio.plano_atual_nome,
      rateio.centro_atual_id,
      rateio.centro_atual_codigo,
      rateio.centro_atual_nome,
      coalesce(rateio.rateios, '[]'::jsonb) as rateios,
      rateio.rateio_updated_at,
      count(*) filter (
        where t.documento_fiscal_id is not null
      ) over (
        partition by t.documento_fiscal_id
      ) as quantidade_mesmo_documento
    from f.titulo t
    left join public.fornecedores forn
      on forn.id = t.fornecedor_id
     and forn.tenant_id = t.tenant_id
     and forn.empresa_id = t.empresa_id
    left join f.documento_fiscal df
      on df.id = t.documento_fiscal_id
     and df.tenant_id = t.tenant_id
     and df.empresa_id = t.empresa_id
     and df.deleted_at is null
    left join lateral (
      select
        ta.motivo_compra_id,
        ta.os_id
      from f.titulo_aprovacao ta
      where ta.tenant_id = t.tenant_id
        and ta.titulo_id = t.id
        and ta.deleted_at is null
      order by ta.aprovado_em desc, ta.id desc
      limit 1
    ) aprovacao on true
    left join f.motivo_compra mc
      on mc.id = coalesce(
        aprovacao.motivo_compra_id,
        t.motivo_compra_id
      )
     and mc.tenant_id = t.tenant_id
     and mc.ativo
     and mc.deleted_at is null
    left join f.regra_rateio regra
      on regra.tenant_id = t.tenant_id
     and regra.empresa_id = t.empresa_id
     and regra.motivo_compra_id = mc.id
     and regra.ativo
     and regra.deleted_at is null
    left join lateral (
      select min(tp.vencimento_date) as primeiro_vencimento
      from f.titulo_parcela tp
      where tp.tenant_id = t.tenant_id
        and tp.titulo_id = t.id
        and tp.deleted_at is null
    ) parcelas on true
    left join lateral (
      select
        count(*)::integer as total_rateios,
        coalesce(sum(coalesce(tr.percentual, 0)), 0)
          as total_percentual,
        coalesce(sum(coalesce(
          tr.valor,
          round(
            t.valor_total * coalesce(tr.percentual, 0) / 100.0,
            2
          ),
          0
        )), 0) as total_rateado,
        bool_or(tr.origem_rateio = 'EXPLICITO') as tem_explicito,
        bool_or(tr.plano_contas_id is null) as tem_plano_nulo,
        bool_or(tr.centro_custo_id is null) as tem_centro_nulo,
        bool_or(pc.codigo = 'DESP_GERAL') as tem_desp_geral,
        bool_or(
          tr.plano_contas_id is not null
          and pc.id is null
        ) as tem_plano_invalido,
        bool_or(
          tr.centro_custo_id is not null
          and cc.id is null
        ) as tem_centro_invalido,
        bool_or(
          mc.plano_contas_id is not null
          and mc.codigo <> 'DESP_GERAL'
          and tr.plano_contas_id is distinct from mc.plano_contas_id
        ) as tem_plano_divergente_motivo,
        (array_agg(tr.plano_contas_id order by tr.id))[1]
          as plano_atual_id,
        min(pc.codigo) as plano_atual_codigo,
        min(pc.nome) as plano_atual_nome,
        (array_agg(tr.centro_custo_id order by tr.id))[1]
          as centro_atual_id,
        min(cc.codigo) as centro_atual_codigo,
        min(cc.nome) as centro_atual_nome,
        jsonb_agg(
          jsonb_build_object(
            'id', tr.id,
            'planoContasId', tr.plano_contas_id,
            'planoCodigo', pc.codigo,
            'planoNome', pc.nome,
            'centroCustoId', tr.centro_custo_id,
            'centroCodigo', cc.codigo,
            'centroNome', cc.nome,
            'osId', tr.os_id,
            'percentual', tr.percentual,
            'valor', tr.valor,
            'origemRateio', tr.origem_rateio
          )
          order by tr.id
        ) as rateios,
        max(tr.updated_at) as rateio_updated_at
      from f.titulo_rateio tr
      left join f.plano_contas pc
        on pc.id = tr.plano_contas_id
       and pc.tenant_id = tr.tenant_id
       and pc.tipo = 'ANALITICA'
       and pc.ativo
       and pc.deleted_at is null
      left join f.centro_custo cc
        on cc.id = tr.centro_custo_id
       and cc.tenant_id = tr.tenant_id
       and cc.empresa_id = t.empresa_id
       and cc.ativo
       and cc.deleted_at is null
      where tr.tenant_id = t.tenant_id
        and tr.titulo_id = t.id
        and tr.deleted_at is null
    ) rateio on true
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.status <> 'CANCELADO'
      and t.deleted_at is null
      and not f.titulo_eh_legado_implantacao(
        t.tenant_id,
        t.empresa_id,
        t.id
      )
  ),
  base as (
    select *
    from base_inicial b
    where (p_data_inicio is null or b.data_referencia >= p_data_inicio)
      and (p_data_fim is null or b.data_referencia <= p_data_fim)
  ),
  problemas as (
    select
      b.*,
      p.tipo,
      p.prioridade,
      p.detalhe,
      p.sugestao,
      p.corrigivel,
      p.pode_criar_regra
    from base b
    cross join lateral (
      values
        (
          'SEM_MOTIVO_COMPRA'::text,
          'ALTA'::text,
          'O titulo nao possui motivo de compra ativo.'::text,
          'Classifique o motivo antes de criar ou aplicar uma regra.'::text,
          false,
          false,
          b.motivo_compra_id is null or b.motivo_codigo is null
        ),
        (
          'SEM_REGRA_RATEIO',
          'BAIXA',
          'O motivo possui plano, mas nao existe regra ativa para esta empresa.',
          'Revise o destino e crie uma regra somente se ele for recorrente.',
          (
            b.total_rateios = 0
            or (
              b.total_rateios = 1
              and abs(b.total_percentual - 100.0000) <= 0.0001
            )
          ) and b.motivo_codigo <> 'DESP_GERAL',
          (
            b.total_rateios = 0
            or (
              b.total_rateios = 1
              and abs(b.total_percentual - 100.0000) <= 0.0001
            )
          ) and b.motivo_codigo <> 'DESP_GERAL',
          b.motivo_compra_id is not null
            and b.plano_motivo_id is not null
            and b.regra_rateio_id is null
        ),
        (
          'SEM_RATEIO',
          'ALTA',
          'O titulo nao possui rateio financeiro ativo.',
          'Informe plano e centro de custo ou aplique uma regra conferida.',
          true,
          b.motivo_compra_id is not null
            and b.motivo_codigo <> 'DESP_GERAL'
            and b.regra_rateio_id is null,
          b.total_rateios = 0
        ),
        (
          'SEM_PLANO_CONTAS',
          'ALTA',
          'Existe rateio sem plano de contas.',
          'Defina um plano analitico coerente com o motivo da compra.',
          b.total_rateios = 1
            and abs(b.total_percentual - 100.0000) <= 0.0001,
          b.motivo_compra_id is not null
            and b.motivo_codigo <> 'DESP_GERAL'
            and b.regra_rateio_id is null
            and b.total_rateios = 1,
          b.total_rateios > 0 and b.tem_plano_nulo
        ),
        (
          'SEM_CENTRO_CUSTO',
          'ALTA',
          'Existe rateio sem centro de custo.',
          'Defina o centro responsavel; evite usar Despesas Gerais.',
          b.total_rateios = 1
            and abs(b.total_percentual - 100.0000) <= 0.0001,
          b.motivo_compra_id is not null
            and b.motivo_codigo <> 'DESP_GERAL'
            and b.regra_rateio_id is null
            and b.total_rateios = 1,
          b.total_rateios > 0 and b.tem_centro_nulo
        ),
        (
          'DESP_GERAL',
          'MEDIA',
          'O titulo esta classificado em DESP_GERAL.',
          'Substitua por um plano e centro especificos quando houver evidencia.',
          b.total_rateios = 1
            and abs(b.total_percentual - 100.0000) <= 0.0001,
          false,
          b.tem_desp_geral
        ),
        (
          'RATEIO_PERCENTUAL_INCORRETO',
          'ALTA',
          format(
            'Os percentuais somam %s%%, mas deveriam somar 100%%.',
            round(b.total_percentual, 4)
          ),
          'Revise o rateio no titulo; a central nao divide linhas automaticamente.',
          false,
          false,
          b.total_rateios > 0
            and abs(b.total_percentual - 100.0000) > 0.0001
        ),
        (
          'RATEIO_VALOR_INCORRETO',
          'ALTA',
          format(
            'O rateio soma R$ %s e o titulo vale R$ %s.',
            round(b.total_rateado, 2),
            round(b.valor_total, 2)
          ),
          'Revise os valores do rateio no titulo; nenhum valor sera ajustado em lote.',
          false,
          false,
          b.total_rateios > 0
            and abs(b.total_rateado - b.valor_total) > 0.01
        ),
        (
          'PLANO_INVALIDO',
          'ALTA',
          'Existe plano ausente, inativo, sintetico ou de outro tenant.',
          'Escolha um plano analitico ativo.',
          b.total_rateios = 1
            and abs(b.total_percentual - 100.0000) <= 0.0001,
          false,
          b.tem_plano_invalido
        ),
        (
          'CENTRO_INVALIDO',
          'ALTA',
          'Existe centro inativo ou de outra empresa.',
          'Escolha um centro ativo desta empresa.',
          b.total_rateios = 1
            and abs(b.total_percentual - 100.0000) <= 0.0001,
          false,
          b.tem_centro_invalido
        ),
        (
          'PLANO_DIVERGENTE_MOTIVO',
          'MEDIA',
          'O plano do rateio diverge do plano configurado no motivo.',
          'Confirme o motivo ou ajuste o plano; a regra sempre herda o plano do motivo.',
          b.total_rateios = 1
            and abs(b.total_percentual - 100.0000) <= 0.0001,
          false,
          b.tem_plano_divergente_motivo
        ),
        (
          'POSSIVEL_DUPLICIDADE',
          'ALTA',
          'Mais de um titulo ativo referencia o mesmo documento fiscal.',
          'Confira os titulos antes de qualquer baixa ou exclusao.',
          false,
          false,
          coalesce(b.quantidade_mesmo_documento, 0) > 1
        )
    ) as p(
      tipo,
      prioridade,
      detalhe,
      sugestao,
      corrigivel,
      pode_criar_regra,
      aplica
    )
    where p.aplica
  ),
  normalizado as (
    select
      p.*,
      jsonb_build_object(
        'tipo', p.tipo,
        'tituloId', p.titulo_id,
        'motivoCompraId', p.motivo_compra_id,
        'planoMotivoId', p.plano_motivo_id,
        'regraRateioId', p.regra_rateio_id,
        'tituloUpdatedAt', p.titulo_updated_at,
        'rateioUpdatedAt', p.rateio_updated_at,
        'rateios', p.rateios,
        'documentoFiscalId', p.documento_fiscal_id,
        'quantidadeMesmoDocumento',
          coalesce(p.quantidade_mesmo_documento, 0)
      ) as dados_inconsistencia
    from problemas p
  )
  select
    n.titulo_id,
    n.tipo,
    n.prioridade,
    n.data_referencia,
    n.fornecedor_id,
    n.fornecedor_nome,
    n.documento,
    n.descricao,
    n.valor_total,
    n.motivo_compra_id,
    n.motivo_codigo,
    n.motivo_nome,
    n.plano_atual_id,
    n.plano_atual_codigo,
    n.plano_atual_nome,
    n.centro_atual_id,
    n.centro_atual_codigo,
    n.centro_atual_nome,
    n.total_rateios,
    n.total_percentual,
    n.total_rateado,
    n.tem_rateio_explicito,
    n.detalhe,
    n.sugestao,
    n.corrigivel,
    n.pode_criar_regra,
    md5(n.dados_inconsistencia::text) as fingerprint,
    n.dados_inconsistencia as dados
  from normalizado n;
$$;

revoke all on function f.detectar_inconsistencias_financeiras(
  uuid,
  uuid,
  date,
  date
) from public, anon, authenticated;

create or replace function f.listar_inconsistencias_financeiras(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_inicio date default null,
  p_data_fim date default null,
  p_tipo text default null,
  p_prioridade text default null,
  p_status text default 'ABERTA',
  p_busca text default null,
  p_limite integer default 200,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_limite integer := greatest(1, least(coalesce(p_limite, 200), 500));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_status text := upper(coalesce(nullif(btrim(p_status), ''), 'ABERTA'));
  v_tipo text := upper(nullif(btrim(p_tipo), ''));
  v_prioridade text := upper(nullif(btrim(p_prioridade), ''));
  v_busca text := lower(nullif(btrim(p_busca), ''));
  v_resultado jsonb;
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id e empresa_id sao obrigatorios.';
  end if;

  if p_data_inicio is not null
     and p_data_fim is not null
     and p_data_inicio > p_data_fim
  then
    raise exception using
      errcode = '22023',
      message = 'A data inicial nao pode ser posterior a data final.';
  end if;

  if v_status not in ('ABERTA', 'IGNORADA', 'TODAS') then
    raise exception using
      errcode = '22023',
      message = 'Status invalido. Use ABERTA, IGNORADA ou TODAS.';
  end if;

  if v_prioridade is not null
     and v_prioridade not in ('ALTA', 'MEDIA', 'BAIXA', 'TODAS')
  then
    raise exception using
      errcode = '22023',
      message = 'Prioridade invalida. Use ALTA, MEDIA ou BAIXA.';
  end if;

  if auth.uid() is null
     and coalesce(auth.role(), '') <> 'service_role'
  then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado.';
  end if;

  if auth.uid() is not null
     and not f.pode_ler_regras_rateio(p_tenant_id, p_empresa_id)
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para consultar inconsistencias desta empresa.';
  end if;

  with detectadas as (
    select *
    from f.detectar_inconsistencias_financeiras(
      p_tenant_id,
      p_empresa_id,
      p_data_inicio,
      p_data_fim
    )
  ),
  estados as (
    select
      d.*,
      case
        when trat.status = 'IGNORADA'
         and trat.fingerprint = d.fingerprint
        then 'IGNORADA'
        else 'ABERTA'
      end as status_inconsistencia,
      case
        when trat.status = 'IGNORADA'
         and trat.fingerprint = d.fingerprint
        then trat.justificativa
        else null
      end as justificativa_ignorada,
      case
        when d.tipo = 'SEM_REGRA_RATEIO'
        then 'OPORTUNIDADE_AUTOMACAO'
        else 'INCONSISTENCIA'
      end as categoria
    from detectadas d
    left join f.inconsistencia_financeira_tratamento trat
      on trat.tenant_id = p_tenant_id
     and trat.empresa_id = p_empresa_id
     and trat.titulo_id = d.titulo_id
     and trat.tipo = d.tipo
     and trat.deleted_at is null
  ),
  filtradas as (
    select *
    from estados e
    where (v_status = 'TODAS' or e.status_inconsistencia = v_status)
      and (v_tipo is null or v_tipo = 'TODAS' or e.tipo = v_tipo)
      and (
        v_prioridade is null
        or v_prioridade = 'TODAS'
        or e.prioridade = v_prioridade
      )
      and (
        v_busca is null
        or lower(concat_ws(
          ' ',
          e.fornecedor_nome,
          e.documento,
          e.descricao,
          e.motivo_codigo,
          e.motivo_nome,
          e.plano_atual_codigo,
          e.plano_atual_nome,
          e.centro_atual_codigo,
          e.centro_atual_nome,
          e.tipo
        )) like '%' || v_busca || '%'
      )
  ),
  pagina as (
    select *
    from filtradas f
    order by
      case f.prioridade
        when 'ALTA' then 1
        when 'MEDIA' then 2
        else 3
      end,
      f.valor_total desc,
      f.data_referencia desc,
      f.titulo_id,
      f.tipo
    limit v_limite
    offset v_offset
  ),
  escopo as (
    select count(*)::integer as titulos_escopo
    from (
      select
        t.id,
        coalesce(
          t.competencia_date,
          t.emissao_date,
          parcelas.primeiro_vencimento,
          t.created_at::date
        ) as data_referencia
      from f.titulo t
      left join lateral (
        select min(tp.vencimento_date) as primeiro_vencimento
        from f.titulo_parcela tp
        where tp.tenant_id = t.tenant_id
          and tp.titulo_id = t.id
          and tp.deleted_at is null
      ) parcelas on true
      where t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.tipo = 'AP'
        and t.status <> 'CANCELADO'
        and t.deleted_at is null
        and not f.titulo_eh_legado_implantacao(
          t.tenant_id,
          t.empresa_id,
          t.id
        )
    ) x
    where (p_data_inicio is null or x.data_referencia >= p_data_inicio)
      and (p_data_fim is null or x.data_referencia <= p_data_fim)
  ),
  afetados as (
    select distinct e.titulo_id, e.valor_total
    from estados e
    where e.status_inconsistencia = 'ABERTA'
      and e.categoria = 'INCONSISTENCIA'
  ),
  resumo_tipo as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'tipo', x.tipo,
        'categoria', x.categoria,
        'quantidade', x.quantidade,
        'titulos', x.titulos,
        'abertas', x.abertas,
        'ignoradas', x.ignoradas,
        'valor', x.valor
      )
      order by x.categoria desc, x.quantidade desc, x.tipo
    ), '[]'::jsonb) as itens
    from (
      select
        e.tipo,
        e.categoria,
        count(*)::integer as quantidade,
        count(distinct e.titulo_id)::integer as titulos,
        count(*) filter (
          where e.status_inconsistencia = 'ABERTA'
        )::integer as abertas,
        count(*) filter (
          where e.status_inconsistencia = 'IGNORADA'
        )::integer as ignoradas,
        round(coalesce(sum(e.valor_total) filter (
          where e.status_inconsistencia = 'ABERTA'
            and e.categoria = 'INCONSISTENCIA'
        ), 0), 2) as valor
      from estados e
      group by e.tipo, e.categoria
    ) x
  ),
  resumo_prioridade as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'prioridade', x.prioridade,
        'quantidade', x.quantidade,
        'titulos', x.titulos
      )
      order by case x.prioridade
        when 'ALTA' then 1
        when 'MEDIA' then 2
        else 3
      end
    ), '[]'::jsonb) as itens
    from (
      select
        e.prioridade,
        count(*)::integer as quantidade,
        count(distinct e.titulo_id)::integer as titulos
      from estados e
      where e.status_inconsistencia = 'ABERTA'
        and e.categoria = 'INCONSISTENCIA'
      group by e.prioridade
    ) x
  ),
  catalogo_planos as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', pc.id,
        'codigo', pc.codigo,
        'nome', pc.nome,
        'natureza', pc.natureza
      )
      order by pc.codigo, pc.nome
    ), '[]'::jsonb) as itens
    from f.plano_contas pc
    where pc.tenant_id = p_tenant_id
      and pc.tipo = 'ANALITICA'
      and pc.codigo <> 'DESP_GERAL'
      and pc.ativo
      and pc.deleted_at is null
  ),
  catalogo_centros as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', cc.id,
        'codigo', cc.codigo,
        'nome', cc.nome,
        'parentId', cc.parent_id
      )
      order by cc.codigo, cc.nome
    ), '[]'::jsonb) as itens
    from f.centro_custo cc
    where cc.tenant_id = p_tenant_id
      and cc.empresa_id = p_empresa_id
      and cc.ativo
      and cc.deleted_at is null
  )
  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'titulosEscopo', esc.titulos_escopo,
      'titulosComInconsistencia', (select count(*) from afetados),
      'titulosSemInconsistencia', greatest(
        0,
        esc.titulos_escopo - (select count(*) from afetados)
      ),
      'qualidadePercentual', case
        when esc.titulos_escopo = 0 then 100.0
        else round(
          100.0 * greatest(
            0,
            esc.titulos_escopo - (select count(*) from afetados)
          ) / esc.titulos_escopo,
          1
        )
      end,
      'totalInconsistencias', (
        select count(*)
        from estados e
        where e.status_inconsistencia = 'ABERTA'
          and e.categoria = 'INCONSISTENCIA'
      ),
      'totalAbertas', (
        select count(*)
        from estados e
        where e.status_inconsistencia = 'ABERTA'
      ),
      'totalIgnoradas', (
        select count(*)
        from estados e
        where e.status_inconsistencia = 'IGNORADA'
      ),
      'oportunidadesAutomacao', (
        select count(distinct e.titulo_id)
        from estados e
        where e.status_inconsistencia = 'ABERTA'
          and e.categoria = 'OPORTUNIDADE_AUTOMACAO'
      ),
      'valorTitulosAfetados', round(coalesce((
        select sum(a.valor_total) from afetados a
      ), 0), 2),
      'porTipo', (select rt.itens from resumo_tipo rt),
      'porPrioridade', (
        select rp.itens from resumo_prioridade rp
      )
    ),
    'paginacao', jsonb_build_object(
      'total', (select count(*) from filtradas),
      'limite', v_limite,
      'offset', v_offset
    ),
    'catalogos', jsonb_build_object(
      'planos', (select cp.itens from catalogo_planos cp),
      'centros', (select cc.itens from catalogo_centros cc)
    ),
    'itens', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'tituloId', pg.titulo_id,
          'tipo', pg.tipo,
          'categoria', pg.categoria,
          'prioridade', pg.prioridade,
          'status', pg.status_inconsistencia,
          'dataReferencia', pg.data_referencia,
          'fornecedorId', pg.fornecedor_id,
          'fornecedorNome', pg.fornecedor_nome,
          'documento', pg.documento,
          'descricao', pg.descricao,
          'valorTotal', pg.valor_total,
          'motivoCompraId', pg.motivo_compra_id,
          'motivoCodigo', pg.motivo_codigo,
          'motivoNome', pg.motivo_nome,
          'planoAtualId', pg.plano_atual_id,
          'planoAtualCodigo', pg.plano_atual_codigo,
          'planoAtualNome', pg.plano_atual_nome,
          'centroAtualId', pg.centro_atual_id,
          'centroAtualCodigo', pg.centro_atual_codigo,
          'centroAtualNome', pg.centro_atual_nome,
          'totalRateios', pg.total_rateios,
          'totalPercentual', pg.total_percentual,
          'totalRateado', pg.total_rateado,
          'temRateioExplicito', pg.tem_rateio_explicito,
          'detalhe', pg.detalhe,
          'sugestao', pg.sugestao,
          'corrigivel', pg.corrigivel,
          'podeCriarRegra', pg.pode_criar_regra,
          'fingerprint', pg.fingerprint,
          'justificativaIgnorada', pg.justificativa_ignorada,
          'dados', pg.dados
        )
        order by
          case pg.prioridade
            when 'ALTA' then 1
            when 'MEDIA' then 2
            else 3
          end,
          pg.valor_total desc,
          pg.data_referencia desc,
          pg.titulo_id,
          pg.tipo
      )
      from pagina pg
    ), '[]'::jsonb)
  )
  into v_resultado
  from escopo esc;

  return coalesce(v_resultado, jsonb_build_object(
    'resumo', '{}'::jsonb,
    'paginacao', jsonb_build_object(
      'total', 0,
      'limite', v_limite,
      'offset', v_offset
    ),
    'catalogos', jsonb_build_object(
      'planos', '[]'::jsonb,
      'centros', '[]'::jsonb
    ),
    'itens', '[]'::jsonb
  ));
end;
$$;

revoke all on function f.listar_inconsistencias_financeiras(
  uuid,
  uuid,
  date,
  date,
  text,
  text,
  text,
  text,
  integer,
  integer
) from public, anon;
grant execute on function f.listar_inconsistencias_financeiras(
  uuid,
  uuid,
  date,
  date,
  text,
  text,
  text,
  text,
  integer,
  integer
) to authenticated, service_role;

comment on function f.listar_inconsistencias_financeiras(
  uuid,
  uuid,
  date,
  date,
  text,
  text,
  text,
  text,
  integer,
  integer
) is
  'Lista APs com inconsistencias por tenant/empresa. Legado e oportunidades de automacao nao reduzem a nota de qualidade.';

create or replace function f.ignorar_inconsistencias_financeiras(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_itens jsonb,
  p_justificativa text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_item jsonb;
  v_titulo_id uuid;
  v_tipo text;
  v_detectada record;
  v_existente f.inconsistencia_financeira_tratamento%rowtype;
  v_actor uuid := a.fn_current_usuario_id();
  v_ignoradas integer := 0;
  v_ja_ignoradas integer := 0;
  v_resultados jsonb := '[]'::jsonb;
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id e empresa_id sao obrigatorios.';
  end if;

  if length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception using
      errcode = '22023',
      message = 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;

  if p_itens is null
     or jsonb_typeof(p_itens) <> 'array'
     or jsonb_array_length(p_itens) = 0
  then
    raise exception using
      errcode = '22023',
      message = 'Informe ao menos uma inconsistencia para ignorar.';
  end if;

  if jsonb_array_length(p_itens) > 500 then
    raise exception using
      errcode = '54000',
      message = 'O limite e de 500 inconsistencias por operacao.';
  end if;

  if auth.uid() is null
     and coalesce(auth.role(), '') <> 'service_role'
  then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado.';
  end if;

  if auth.uid() is not null
     and not f.pode_escrever_regras_rateio(
       p_tenant_id,
       p_empresa_id
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para ignorar inconsistencias desta empresa.';
  end if;

  if (
    select count(*)
    from jsonb_array_elements(p_itens)
  ) <> (
    select count(*)
    from (
      select distinct
        item ->> 'titulo_id',
        upper(item ->> 'tipo')
      from jsonb_array_elements(p_itens) item
    ) unicos
  ) then
    raise exception using
      errcode = '23505',
      message = 'A mesma inconsistencia foi informada mais de uma vez.';
  end if;

  for v_item in
    select value from jsonb_array_elements(p_itens)
  loop
    begin
      v_titulo_id := nullif(v_item ->> 'titulo_id', '')::uuid;
      v_tipo := upper(nullif(btrim(v_item ->> 'tipo'), ''));
    exception
      when invalid_text_representation then
        raise exception using
          errcode = '22023',
          message = 'Item para ignorar possui titulo_id invalido.';
    end;

    if v_titulo_id is null or v_tipo is null then
      raise exception using
        errcode = '22023',
        message = 'Cada item deve informar titulo_id e tipo.';
    end if;

    perform 1
    from f.titulo t
    where t.id = v_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.status <> 'CANCELADO'
      and t.deleted_at is null
    for share;

    if not found then
      raise exception using
        errcode = 'P0002',
        message = format(
          'Titulo %s nao foi encontrado nesta empresa.',
          v_titulo_id
        );
    end if;

    select d.*
      into v_detectada
    from f.detectar_inconsistencias_financeiras(
      p_tenant_id,
      p_empresa_id,
      null,
      null
    ) d
    where d.titulo_id = v_titulo_id
      and d.tipo = v_tipo
    limit 1;

    if not found then
      raise exception using
        errcode = 'P0002',
        message = format(
          'A inconsistencia %s nao esta ativa no titulo %s.',
          v_tipo,
          v_titulo_id
        );
    end if;

    select trat.*
      into v_existente
    from f.inconsistencia_financeira_tratamento trat
    where trat.tenant_id = p_tenant_id
      and trat.empresa_id = p_empresa_id
      and trat.titulo_id = v_titulo_id
      and trat.tipo = v_tipo
      and trat.deleted_at is null
    for update;

    if found
       and v_existente.status = 'IGNORADA'
       and v_existente.fingerprint = v_detectada.fingerprint
    then
      v_ja_ignoradas := v_ja_ignoradas + 1;
      v_resultados := v_resultados || jsonb_build_array(
        jsonb_build_object(
          'tituloId', v_titulo_id,
          'tipo', v_tipo,
          'status', 'JA_IGNORADA'
        )
      );
      continue;
    end if;

    insert into f.inconsistencia_financeira_tratamento (
      tenant_id,
      empresa_id,
      titulo_id,
      tipo,
      status,
      fingerprint,
      justificativa,
      dados_snapshot,
      tratado_em,
      tratado_por
    )
    values (
      p_tenant_id,
      p_empresa_id,
      v_titulo_id,
      v_tipo,
      'IGNORADA',
      v_detectada.fingerprint,
      btrim(p_justificativa),
      v_detectada.dados,
      now(),
      v_actor
    )
    on conflict (
      tenant_id,
      empresa_id,
      titulo_id,
      tipo
    ) where deleted_at is null
    do update set
      status = excluded.status,
      fingerprint = excluded.fingerprint,
      justificativa = excluded.justificativa,
      dados_snapshot = excluded.dados_snapshot,
      tratado_em = excluded.tratado_em,
      tratado_por = excluded.tratado_por,
      updated_at = now(),
      updated_by = v_actor;

    insert into f.evento_financeiro (
      tenant_id,
      empresa_id,
      evento,
      ref_table,
      ref_id,
      payload,
      created_by
    )
    values (
      p_tenant_id,
      p_empresa_id,
      'INCONSISTENCIA_FINANCEIRA_IGNORADA',
      'f.titulo',
      v_titulo_id,
      jsonb_build_object(
        'tipo', v_tipo,
        'fingerprint', v_detectada.fingerprint,
        'justificativa', btrim(p_justificativa),
        'dados', v_detectada.dados,
        'alterouTitulo', false,
        'alterouParcela', false,
        'alterouPagamento', false
      ),
      v_actor
    );

    v_ignoradas := v_ignoradas + 1;
    v_resultados := v_resultados || jsonb_build_array(
      jsonb_build_object(
        'tituloId', v_titulo_id,
        'tipo', v_tipo,
        'status', 'IGNORADA'
      )
    );
  end loop;

  return jsonb_build_object(
    'ignoradas', v_ignoradas,
    'jaIgnoradas', v_ja_ignoradas,
    'itens', v_resultados
  );
end;
$$;

revoke all on function f.ignorar_inconsistencias_financeiras(
  uuid,
  uuid,
  jsonb,
  text
) from public, anon;
grant execute on function f.ignorar_inconsistencias_financeiras(
  uuid,
  uuid,
  jsonb,
  text
) to authenticated, service_role;

create or replace function f.reabrir_inconsistencia_financeira(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid,
  p_tipo text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_tipo text := upper(nullif(btrim(p_tipo), ''));
  v_tratamento f.inconsistencia_financeira_tratamento%rowtype;
  v_actor uuid := a.fn_current_usuario_id();
begin
  if p_tenant_id is null
     or p_empresa_id is null
     or p_titulo_id is null
     or v_tipo is null
  then
    raise exception using
      errcode = '22023',
      message = 'tenant_id, empresa_id, titulo_id e tipo sao obrigatorios.';
  end if;

  if auth.uid() is null
     and coalesce(auth.role(), '') <> 'service_role'
  then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado.';
  end if;

  if auth.uid() is not null
     and not f.pode_escrever_regras_rateio(
       p_tenant_id,
       p_empresa_id
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para reabrir inconsistencias desta empresa.';
  end if;

  select trat.*
    into v_tratamento
  from f.inconsistencia_financeira_tratamento trat
  join f.titulo t
    on t.id = trat.titulo_id
   and t.tenant_id = trat.tenant_id
   and t.empresa_id = trat.empresa_id
  where trat.tenant_id = p_tenant_id
    and trat.empresa_id = p_empresa_id
    and trat.titulo_id = p_titulo_id
    and trat.tipo = v_tipo
    and trat.status = 'IGNORADA'
    and trat.deleted_at is null
  for update of trat;

  if not found then
    return jsonb_build_object(
      'tituloId', p_titulo_id,
      'tipo', v_tipo,
      'status', 'JA_ABERTA'
    );
  end if;

  update f.inconsistencia_financeira_tratamento trat
  set
    deleted_at = now(),
    updated_at = now(),
    updated_by = v_actor
  where trat.id = v_tratamento.id
    and trat.tenant_id = p_tenant_id
    and trat.empresa_id = p_empresa_id;

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload,
    created_by
  )
  values (
    p_tenant_id,
    p_empresa_id,
    'INCONSISTENCIA_FINANCEIRA_REABERTA',
    'f.titulo',
    p_titulo_id,
    jsonb_build_object(
      'tipo', v_tipo,
      'fingerprintIgnorado', v_tratamento.fingerprint,
      'justificativaAnterior', v_tratamento.justificativa,
      'alterouTitulo', false,
      'alterouParcela', false,
      'alterouPagamento', false
    ),
    v_actor
  );

  return jsonb_build_object(
    'tituloId', p_titulo_id,
    'tipo', v_tipo,
    'status', 'ABERTA'
  );
end;
$$;

revoke all on function f.reabrir_inconsistencia_financeira(
  uuid,
  uuid,
  uuid,
  text
) from public, anon;
grant execute on function f.reabrir_inconsistencia_financeira(
  uuid,
  uuid,
  uuid,
  text
) to authenticated, service_role;

create or replace function f.corrigir_inconsistencias_financeiras(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_ids uuid[],
  p_plano_contas_id uuid,
  p_centro_custo_id uuid,
  p_justificativa text,
  p_criar_regra boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo_id uuid;
  v_titulo f.titulo%rowtype;
  v_rateio f.titulo_rateio%rowtype;
  v_actor uuid := a.fn_current_usuario_id();
  v_quantidade integer;
  v_total_percentual numeric;
  v_tem_corrigivel boolean;
  v_pode_criar_regra boolean;
  v_motivo_id uuid;
  v_motivo_codigo text;
  v_plano_motivo_id uuid;
  v_motivo_regra_id uuid;
  v_os_id integer;
  v_regra_resultado jsonb;
  v_regra_id uuid;
  v_snapshot_antes jsonb;
  v_snapshot_depois jsonb;
  v_detectadas_titulo jsonb;
  v_detectadas_antes jsonb := '{}'::jsonb;
  v_snapshots_antes jsonb := '{}'::jsonb;
  v_tipos_antes text[];
  v_tipos_depois text[];
  v_tipo_resolvido text;
  v_fingerprint text;
  v_dados jsonb;
  v_corrigidos integer := 0;
  v_resultados jsonb := '[]'::jsonb;
begin
  if p_tenant_id is null
     or p_empresa_id is null
     or p_plano_contas_id is null
     or p_centro_custo_id is null
  then
    raise exception using
      errcode = '22023',
      message = 'tenant_id, empresa_id, plano e centro sao obrigatorios.';
  end if;

  if p_titulo_ids is null or cardinality(p_titulo_ids) = 0 then
    raise exception using
      errcode = '22023',
      message = 'Informe ao menos um titulo para corrigir.';
  end if;

  if cardinality(p_titulo_ids) > 200 then
    raise exception using
      errcode = '54000',
      message = 'O limite e de 200 titulos por correcao.';
  end if;

  if cardinality(p_titulo_ids) <> (
    select count(distinct ids.id)::integer
    from unnest(p_titulo_ids) as ids(id)
  ) then
    raise exception using
      errcode = '23505',
      message = 'A lista contem titulo repetido ou identificador nulo.';
  end if;

  if length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception using
      errcode = '22023',
      message = 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;

  if auth.uid() is null
     and coalesce(auth.role(), '') <> 'service_role'
  then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado.';
  end if;

  if auth.uid() is not null
     and not f.pode_escrever_regras_rateio(
       p_tenant_id,
       p_empresa_id
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para corrigir inconsistencias desta empresa.';
  end if;

  if not exists (
    select 1
    from f.plano_contas pc
    where pc.id = p_plano_contas_id
      and pc.tenant_id = p_tenant_id
      and pc.tipo = 'ANALITICA'
      and pc.codigo <> 'DESP_GERAL'
      and pc.ativo
      and pc.deleted_at is null
  ) then
    raise exception using
      errcode = '23503',
      message = 'Escolha um plano analitico ativo e especifico; DESP_GERAL nao e uma correcao.';
  end if;

  if not exists (
    select 1
    from f.centro_custo cc
    where cc.id = p_centro_custo_id
      and cc.tenant_id = p_tenant_id
      and cc.empresa_id = p_empresa_id
      and cc.ativo
      and cc.deleted_at is null
  ) then
    raise exception using
      errcode = '23503',
      message = 'Centro de custo invalido, inativo ou de outra empresa.';
  end if;

  select count(*)::integer
    into v_quantidade
  from f.titulo t
  where t.id = any(p_titulo_ids)
    and t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and t.deleted_at is null
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    );

  if v_quantidade <> cardinality(p_titulo_ids) then
    raise exception using
      errcode = 'P0002',
      message = 'Um ou mais titulos nao pertencem ao escopo, estao cancelados ou sao legado de implantacao.';
  end if;

  -- Ordem deterministica evita deadlock em correcoes concorrentes.
  perform t.id
  from f.titulo t
  where t.id = any(p_titulo_ids)
    and t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
  order by t.id
  for update;

  -- Primeira passagem: valida o lote inteiro e captura o antes.
  foreach v_titulo_id in array p_titulo_ids
  loop
    select t.*
      into strict v_titulo
    from f.titulo t
    where t.id = v_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id;

    select
      coalesce(jsonb_object_agg(
        d.tipo,
        jsonb_build_object(
          'fingerprint', d.fingerprint,
          'dados', d.dados
        )
      ), '{}'::jsonb),
      coalesce(bool_or(d.corrigivel), false),
      coalesce(bool_or(d.pode_criar_regra), false)
      into
        v_detectadas_titulo,
        v_tem_corrigivel,
        v_pode_criar_regra
    from f.detectar_inconsistencias_financeiras(
      p_tenant_id,
      p_empresa_id,
      null,
      null
    ) d
    where d.titulo_id = v_titulo_id;

    if v_detectadas_titulo = '{}'::jsonb then
      raise exception using
        errcode = 'P0002',
        message = format(
          'O titulo %s nao possui inconsistencia ativa.',
          v_titulo_id
        );
    end if;

    if not v_tem_corrigivel
       and not (coalesce(p_criar_regra, false) and v_pode_criar_regra)
    then
      raise exception using
        errcode = '23514',
        message = format(
          'O titulo %s exige revisao individual e nao aceita correcao de plano/centro em lote.',
          v_titulo_id
        );
    end if;

    select
      count(*)::integer,
      coalesce(sum(coalesce(tr.percentual, 0)), 0)
      into v_quantidade, v_total_percentual
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = v_titulo_id
      and tr.deleted_at is null;

    if v_quantidade > 1
       or (
         v_quantidade = 1
         and abs(v_total_percentual - 100.0000) > 0.0001
       )
    then
      raise exception using
        errcode = '23514',
        message = format(
          'Titulo %s possui rateio multiplo ou diferente de 100%% e exige revisao individual.',
          v_titulo_id
        );
    end if;

    select
      coalesce(aprovacao.motivo_compra_id, v_titulo.motivo_compra_id),
      mc.codigo,
      mc.plano_contas_id,
      aprovacao.os_id
      into
        v_motivo_id,
        v_motivo_codigo,
        v_plano_motivo_id,
        v_os_id
    from (select 1) base
    left join lateral (
      select ta.motivo_compra_id, ta.os_id
      from f.titulo_aprovacao ta
      where ta.tenant_id = p_tenant_id
        and ta.titulo_id = v_titulo_id
        and ta.deleted_at is null
      order by ta.aprovado_em desc, ta.id desc
      limit 1
    ) aprovacao on true
    left join f.motivo_compra mc
      on mc.id = coalesce(
        aprovacao.motivo_compra_id,
        v_titulo.motivo_compra_id
      )
     and mc.tenant_id = p_tenant_id
     and mc.ativo
     and mc.deleted_at is null;

    if v_plano_motivo_id is not null
       and v_plano_motivo_id is distinct from p_plano_contas_id
       and not (
         v_motivo_codigo = 'DESP_GERAL'
         and not coalesce(p_criar_regra, false)
       )
    then
      raise exception using
        errcode = '23514',
        message = format(
          'O plano escolhido diverge do plano do motivo no titulo %s.',
          v_titulo_id
        );
    end if;

    if coalesce(p_criar_regra, false) then
      if v_motivo_id is null or v_plano_motivo_id is null then
        raise exception using
          errcode = '23514',
          message = format(
            'Titulo %s nao possui motivo com plano valido para criar regra.',
            v_titulo_id
          );
      end if;

      if v_motivo_regra_id is null then
        v_motivo_regra_id := v_motivo_id;
      elsif v_motivo_regra_id is distinct from v_motivo_id then
        raise exception using
          errcode = '23514',
          message = 'Para criar regra, todos os titulos devem possuir o mesmo motivo de compra.';
      end if;
    end if;

    v_snapshot_antes := f.snapshot_inconsistencia_financeira_titulo(
      p_tenant_id,
      p_empresa_id,
      v_titulo_id
    );
    v_detectadas_antes := v_detectadas_antes || jsonb_build_object(
      v_titulo_id::text,
      v_detectadas_titulo
    );
    v_snapshots_antes := v_snapshots_antes || jsonb_build_object(
      v_titulo_id::text,
      v_snapshot_antes
    );
  end loop;

  if coalesce(p_criar_regra, false) then
    if exists (
      select 1
      from f.regra_rateio rr
      where rr.tenant_id = p_tenant_id
        and rr.empresa_id = p_empresa_id
        and rr.motivo_compra_id = v_motivo_regra_id
        and rr.ativo
        and rr.deleted_at is null
    ) then
      raise exception using
        errcode = '23505',
        message = 'Ja existe regra ativa para o motivo selecionado.';
    end if;

    v_regra_resultado := f.salvar_regra_rateio(
      p_tenant_id,
      p_empresa_id,
      null,
      v_motivo_regra_id,
      true,
      jsonb_build_array(jsonb_build_object(
        'plano_contas_id', p_plano_contas_id,
        'centro_custo_id', p_centro_custo_id,
        'percentual', 100.0000
      ))
    );
    v_regra_id := (v_regra_resultado ->> 'id')::uuid;

    insert into f.evento_financeiro (
      tenant_id,
      empresa_id,
      evento,
      ref_table,
      ref_id,
      payload,
      created_by
    )
    values (
      p_tenant_id,
      p_empresa_id,
      'INCONSISTENCIA_FINANCEIRA_REGRA_CRIADA',
      'f.regra_rateio',
      v_regra_id,
      jsonb_build_object(
        'motivoCompraId', v_motivo_regra_id,
        'planoContasId', p_plano_contas_id,
        'centroCustoId', p_centro_custo_id,
        'percentual', 100.0000,
        'titulosOrigem', to_jsonb(p_titulo_ids),
        'justificativa', btrim(p_justificativa)
      ),
      v_actor
    );
  end if;

  -- Segunda passagem: altera somente a classificacao permitida.
  foreach v_titulo_id in array p_titulo_ids
  loop
    select t.*
      into strict v_titulo
    from f.titulo t
    where t.id = v_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id;

    select ta.os_id
      into v_os_id
    from f.titulo_aprovacao ta
    where ta.tenant_id = p_tenant_id
      and ta.titulo_id = v_titulo_id
      and ta.deleted_at is null
    order by ta.aprovado_em desc, ta.id desc
    limit 1;

    select count(*)::integer
      into v_quantidade
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = v_titulo_id
      and tr.deleted_at is null;

    if v_quantidade = 0 then
      if v_os_id is not null
         and not exists (
           select 1
           from public.ordens_servico os
           where os.id = v_os_id
             and os.tenant_id = p_tenant_id
             and os.empresa_id = p_empresa_id
         )
      then
        raise exception using
          errcode = '23503',
          message = format(
            'A OS do titulo %s e invalida ou pertence a outra empresa.',
            v_titulo_id
          );
      end if;

      insert into f.titulo_rateio (
        tenant_id,
        titulo_id,
        plano_contas_id,
        centro_custo_id,
        os_id,
        percentual,
        valor,
        origem_rateio,
        regra_rateio_id,
        regra_item_id
      )
      values (
        p_tenant_id,
        v_titulo_id,
        p_plano_contas_id,
        p_centro_custo_id,
        v_os_id,
        100.0000,
        v_titulo.valor_total,
        'EXPLICITO',
        null,
        null
      );
    else
      select tr.*
        into strict v_rateio
      from f.titulo_rateio tr
      where tr.tenant_id = p_tenant_id
        and tr.titulo_id = v_titulo_id
        and tr.deleted_at is null
      for update;

      update f.titulo_rateio tr
      set
        plano_contas_id = p_plano_contas_id,
        centro_custo_id = p_centro_custo_id,
        origem_rateio = 'EXPLICITO',
        regra_rateio_id = null,
        regra_item_id = null,
        updated_at = now(),
        updated_by = v_actor
      where tr.id = v_rateio.id
        and tr.tenant_id = p_tenant_id
        and tr.titulo_id = v_titulo_id
        and tr.deleted_at is null;

      if not found then
        raise exception using
          errcode = '40001',
          message = format(
            'O rateio do titulo %s mudou durante a correcao.',
            v_titulo_id
          );
      end if;
    end if;

    v_snapshot_antes := v_snapshots_antes -> v_titulo_id::text;
    v_snapshot_depois := f.snapshot_inconsistencia_financeira_titulo(
      p_tenant_id,
      p_empresa_id,
      v_titulo_id
    );

    if v_snapshot_antes -> 'imutaveis'
       is distinct from v_snapshot_depois -> 'imutaveis'
    then
      raise exception using
        errcode = 'P0001',
        message = format(
          'A correcao do titulo %s tentou alterar valor, vencimento, saldo ou pagamento e foi cancelada.',
          v_titulo_id
        );
    end if;

    select coalesce(array_agg(chave.tipo order by chave.tipo), array[]::text[])
      into v_tipos_antes
    from jsonb_object_keys(
      v_detectadas_antes -> v_titulo_id::text
    ) as chave(tipo);

    select coalesce(array_agg(d.tipo order by d.tipo), array[]::text[])
      into v_tipos_depois
    from f.detectar_inconsistencias_financeiras(
      p_tenant_id,
      p_empresa_id,
      null,
      null
    ) d
    where d.titulo_id = v_titulo_id;

    foreach v_tipo_resolvido in array v_tipos_antes
    loop
      if not (v_tipo_resolvido = any(v_tipos_depois)) then
        v_fingerprint := v_detectadas_antes
          -> v_titulo_id::text
          -> v_tipo_resolvido
          ->> 'fingerprint';
        v_dados := v_detectadas_antes
          -> v_titulo_id::text
          -> v_tipo_resolvido
          -> 'dados';

        insert into f.inconsistencia_financeira_tratamento (
          tenant_id,
          empresa_id,
          titulo_id,
          tipo,
          status,
          fingerprint,
          justificativa,
          dados_snapshot,
          tratado_em,
          tratado_por
        )
        values (
          p_tenant_id,
          p_empresa_id,
          v_titulo_id,
          v_tipo_resolvido,
          'TRATADA',
          v_fingerprint,
          btrim(p_justificativa),
          coalesce(v_dados, '{}'::jsonb),
          now(),
          v_actor
        )
        on conflict (
          tenant_id,
          empresa_id,
          titulo_id,
          tipo
        ) where deleted_at is null
        do update set
          status = excluded.status,
          fingerprint = excluded.fingerprint,
          justificativa = excluded.justificativa,
          dados_snapshot = excluded.dados_snapshot,
          tratado_em = excluded.tratado_em,
          tratado_por = excluded.tratado_por,
          updated_at = now(),
          updated_by = v_actor;
      end if;
    end loop;

    insert into f.evento_financeiro (
      tenant_id,
      empresa_id,
      evento,
      ref_table,
      ref_id,
      payload,
      created_by
    )
    values (
      p_tenant_id,
      p_empresa_id,
      'INCONSISTENCIA_FINANCEIRA_CORRIGIDA',
      'f.titulo',
      v_titulo_id,
      jsonb_build_object(
        'planoContasId', p_plano_contas_id,
        'centroCustoId', p_centro_custo_id,
        'justificativa', btrim(p_justificativa),
        'inconsistenciasAntes', to_jsonb(v_tipos_antes),
        'inconsistenciasDepois', to_jsonb(v_tipos_depois),
        'regraCriadaId', v_regra_id,
        'antes', v_snapshot_antes,
        'depois', v_snapshot_depois,
        'alterouValor', false,
        'alterouVencimento', false,
        'alterouPagamento', false,
        'preservouOs', true
      ),
      v_actor
    );

    v_corrigidos := v_corrigidos + 1;
    v_resultados := v_resultados || jsonb_build_array(
      jsonb_build_object(
        'tituloId', v_titulo_id,
        'status', 'CORRIGIDO',
        'inconsistenciasAntes', to_jsonb(v_tipos_antes),
        'inconsistenciasDepois', to_jsonb(v_tipos_depois)
      )
    );
  end loop;

  return jsonb_build_object(
    'corrigidos', v_corrigidos,
    'regraCriadaId', v_regra_id,
    'titulos', v_resultados
  );
end;
$$;

revoke all on function f.corrigir_inconsistencias_financeiras(
  uuid,
  uuid,
  uuid[],
  uuid,
  uuid,
  text,
  boolean
) from public, anon;
grant execute on function f.corrigir_inconsistencias_financeiras(
  uuid,
  uuid,
  uuid[],
  uuid,
  uuid,
  text,
  boolean
) to authenticated, service_role;

comment on function f.corrigir_inconsistencias_financeiras(
  uuid,
  uuid,
  uuid[],
  uuid,
  uuid,
  text,
  boolean
) is
  'Corrige apenas plano/centro em zero ou uma linha de 100%, preservando valor, percentual, OS, parcelas e pagamentos. O lote e atomico.';

create or replace function f.listar_historico_inconsistencia_financeira(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid default null,
  p_limite integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_limite integer := greatest(1, least(coalesce(p_limite, 100), 500));
  v_resultado jsonb;
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id e empresa_id sao obrigatorios.';
  end if;

  if auth.uid() is null
     and coalesce(auth.role(), '') <> 'service_role'
  then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado.';
  end if;

  if auth.uid() is not null
     and not f.pode_ler_regras_rateio(p_tenant_id, p_empresa_id)
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para consultar a auditoria desta empresa.';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ev.id,
      'evento', ev.evento,
      'tituloId', case
        when ev.ref_table = 'f.titulo' then ev.ref_id
        else null
      end,
      'referenciaTabela', ev.ref_table,
      'referenciaId', ev.ref_id,
      'payload', ev.payload,
      'criadoEm', ev.created_at,
      'criadoPor', ev.created_by
    )
    order by ev.created_at desc, ev.id desc
  ), '[]'::jsonb)
    into v_resultado
  from (
    select evento.*
    from f.evento_financeiro evento
    where evento.tenant_id = p_tenant_id
      and evento.empresa_id = p_empresa_id
      and evento.evento like 'INCONSISTENCIA_FINANCEIRA_%'
      and (
        p_titulo_id is null
        or (
          evento.ref_table = 'f.titulo'
          and evento.ref_id = p_titulo_id
        )
        or evento.payload -> 'titulosOrigem' @> to_jsonb(
          array[p_titulo_id]::uuid[]
        )
      )
    order by evento.created_at desc, evento.id desc
    limit v_limite
  ) ev;

  return v_resultado;
end;
$$;

revoke all on function f.listar_historico_inconsistencia_financeira(
  uuid,
  uuid,
  uuid,
  integer
) from public, anon;
grant execute on function f.listar_historico_inconsistencia_financeira(
  uuid,
  uuid,
  uuid,
  integer
) to authenticated, service_role;

comment on function f.ignorar_inconsistencias_financeiras(
  uuid,
  uuid,
  jsonb,
  text
) is
  'Ignora inconsistencias detectadas com justificativa; a decisao perde efeito automaticamente se o fingerprint mudar.';

comment on function f.reabrir_inconsistencia_financeira(
  uuid,
  uuid,
  uuid,
  text
) is
  'Remove a decisao atual de ignorar e registra a reabertura na auditoria financeira.';

select pg_notify('pgrst', 'reload schema');

commit;
