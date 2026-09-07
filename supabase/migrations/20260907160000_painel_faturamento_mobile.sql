-- Painel de faturamento da tela Inicio do app, para COORDENACAO e acima.
-- Decisao de Gabriel em 07/09/2026.
--
-- A meta sai do codigo e vira dado. Ate aqui ela existia so como constante no
-- cliente web (FATURAMENTO_TARGETS_BY_YEAR em
-- app/faturamento/analitico/AnaliticoFaturamentoClient.tsx), onde o numero
-- guardado e a meta MENSAL de cada ano e a anual e ela vezes doze. Os valores
-- abaixo sao copia fiel daquela lista.
--
-- ATENCAO: a tela web continua lendo a constante dela. Enquanto as duas
-- existirem, mudar a meta exige mudar nos dois lugares. O certo e a web passar
-- a ler f.meta_faturamento — fica registrado aqui como pendencia.
--
-- O calculo do faturamento repete exatamente o filtro do analitico
-- (f.faturamento_analitico_documentos mais o shouldIncludeDocumento do
-- cliente), para o app e a web nunca mostrarem numeros diferentes do mesmo
-- mes: SAIDA, nao apagado, NFS-e so com nfse_status EMITIDA, NF-e com
-- nfe_status vazio ou EMITIDA e numero, fora as notas que so existem em
-- homologacao e as vendas para outra empresa do proprio grupo. A data de
-- referencia e competencia_date, caindo para emissao_date quando nao houver.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Meta -----------------------------------------------------------------

create table if not exists f.meta_faturamento (
  tenant_id uuid not null,
  ano integer not null,
  valor_mensal numeric(14, 2) not null check (valor_mensal >= 0),
  observacao text,
  criado_em timestamp with time zone not null default now(),
  atualizado_em timestamp with time zone not null default now(),
  primary key (tenant_id, ano)
);

comment on table f.meta_faturamento is
  'Meta MENSAL de faturamento por ano. A meta anual e valor_mensal * 12. Espelha FATURAMENTO_TARGETS_BY_YEAR do analitico web.';

alter table f.meta_faturamento enable row level security;

grant select, insert, update, delete on f.meta_faturamento to service_role;

insert into f.meta_faturamento (tenant_id, ano, valor_mensal, observacao)
select t.id, v.ano, v.valor, 'Copiado de FATURAMENTO_TARGETS_BY_YEAR (analitico web) em 07/09/2026.'
from public.tenants t
cross join (values
  (2017, 190000.00),
  (2018, 214700.00),
  (2019, 242611.00),
  (2020, 274150.43),
  (2021, 309789.99),
  (2022, 350062.68),
  (2023, 395570.83),
  (2024, 446995.04),
  (2025, 558743.80),
  (2026, 698429.75)
) as v(ano, valor)
where t.ativo is true
on conflict (tenant_id, ano) do nothing;

-- 2. Painel ---------------------------------------------------------------

create or replace function public.app_faturamento_painel(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'f', 'auth'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_ano integer := coalesce(p_ano, extract(year from current_date)::integer);
  v_mes integer := coalesce(p_mes, extract(month from current_date)::integer);
  v_meta numeric;
  v_meses jsonb;
  v_clientes jsonb;
  v_total_ano numeric;
  v_total_mes numeric;
  v_anos jsonb;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if not public.app_mobile_pode_ver_valores_os(v_tenant_id, v_empresa_id) then
    raise exception 'Seu perfil não tem acesso aos valores de faturamento.';
  end if;

  if v_mes < 1 or v_mes > 12 then
    raise exception 'Mês inválido.';
  end if;

  select meta.valor_mensal into v_meta
  from f.meta_faturamento as meta
  where meta.tenant_id = v_tenant_id
    and meta.ano = v_ano;

  with documento as (
    select
      coalesce(d.competencia_date, d.emissao_date) as referencia,
      d.cliente_id,
      coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado')::text as cliente_nome,
      d.valor_total
    from f.documento_fiscal as d
    left join public.clientes as cliente
      on cliente.id = d.cliente_id
     and cliente.tenant_id = d.tenant_id
    where d.tenant_id = v_tenant_id
      and d.empresa_id = v_empresa_id
      and d.operacao = 'SAIDA'
      and d.deleted_at is null
      and coalesce(d.competencia_date, d.emissao_date) >= make_date(v_ano, 1, 1)
      and coalesce(d.competencia_date, d.emissao_date) < make_date(v_ano + 1, 1, 1)
      and (
        (upper(coalesce(d.modelo, '')) = 'NFSE' and upper(coalesce(d.nfse_status, '')) = 'EMITIDA')
        or (
          upper(coalesce(d.modelo, '')) <> 'NFSE'
          and (nullif(btrim(d.nfe_status), '') is null or upper(d.nfe_status) = 'EMITIDA')
          and d.numero is not null
        )
      )
      -- Nota que so existiu em homologacao nao e faturamento.
      and not (
        exists (
          select 1 from f.documento_fiscal_emissao hom
          where hom.tenant_id = d.tenant_id
            and hom.empresa_id = d.empresa_id
            and hom.documento_fiscal_id = d.id
            and hom.ambiente = 'HOMOLOGACAO'
        )
        and not exists (
          select 1 from f.documento_fiscal_emissao prod
          where prod.tenant_id = d.tenant_id
            and prod.empresa_id = d.empresa_id
            and prod.documento_fiscal_id = d.id
            and prod.ambiente = 'PRODUCAO'
        )
      )
      -- Venda para outra empresa do proprio grupo nao e receita.
      and not exists (
        select 1
        from public.empresas as destino
        where destino.tenant_id = d.tenant_id
          and destino.id <> d.empresa_id
          and regexp_replace(coalesce(destino.cnpj, ''), '[^0-9]', '', 'g') <> ''
          and regexp_replace(coalesce(destino.cnpj, ''), '[^0-9]', '', 'g') =
              regexp_replace(coalesce(cliente.documento_norm, cliente.documento, ''), '[^0-9]', '', 'g')
      )
  ),
  por_mes as (
    select serie.mes, coalesce(sum(documento.valor_total), 0)::numeric as total
    from generate_series(1, 12) as serie(mes)
    left join documento
      on extract(month from documento.referencia)::integer = serie.mes
    group by serie.mes
  ),
  por_cliente as (
    select
      documento.cliente_id,
      documento.cliente_nome,
      sum(documento.valor_total)::numeric as total
    from documento
    where extract(month from documento.referencia)::integer = v_mes
    group by documento.cliente_id, documento.cliente_nome
    having sum(documento.valor_total) <> 0
    order by 3 desc
  )
  select
    (select jsonb_agg(jsonb_build_object('mes', mes, 'total', total) order by mes) from por_mes),
    (select coalesce(sum(total), 0) from por_mes),
    (select coalesce(sum(total), 0) from por_mes where mes = v_mes),
    (
      select coalesce(
        jsonb_agg(jsonb_build_object(
          'cliente_id', cliente_id,
          'nome', cliente_nome,
          'total', total
        )),
        '[]'::jsonb
      )
      from por_cliente
    )
    into v_meses, v_total_ano, v_total_mes, v_clientes;

  -- Anos com nota emitida nesta empresa, para a tela nao deixar navegar para
  -- um ano vazio achando que o numero e zero.
  select coalesce(jsonb_agg(distinct extract(year from coalesce(d.competencia_date, d.emissao_date))::integer), '[]'::jsonb)
    into v_anos
  from f.documento_fiscal as d
  where d.tenant_id = v_tenant_id
    and d.empresa_id = v_empresa_id
    and d.operacao = 'SAIDA'
    and d.deleted_at is null;

  return jsonb_build_object(
    'ano', v_ano,
    'mes', v_mes,
    'meta_mensal', v_meta,
    'meta_anual', case when v_meta is not null then v_meta * 12 end,
    'total_ano', coalesce(v_total_ano, 0),
    'total_mes', coalesce(v_total_mes, 0),
    'meses', coalesce(v_meses, '[]'::jsonb),
    'clientes', coalesce(v_clientes, '[]'::jsonb),
    'anos_disponiveis', coalesce(v_anos, '[]'::jsonb)
  );
end;
$function$;

revoke all on function public.app_faturamento_painel(integer, integer) from public, anon;
grant execute on function public.app_faturamento_painel(integer, integer) to authenticated;

-- 3. Conferencia ------------------------------------------------------------

do $assertions$
declare
  v_meta numeric;
begin
  select valor_mensal into v_meta
  from f.meta_faturamento
  where tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
    and ano = 2026;

  if v_meta is distinct from 698429.75 then
    raise exception 'meta_2026_nao_conferida: %', coalesce(v_meta::text, '<nulo>');
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
