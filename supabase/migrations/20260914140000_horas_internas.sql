-- =====================================================================================
-- Horas internas: hora apontada numa ATIVIDADE INTERNA em vez de numa OS.
--
-- Decidido com o Gabriel em 14/09/2026 (docs/horas-internas.md). Até aqui toda hora
-- era obrigada a ter OS: a coluna nem aceitava vazio. Quem passava a segunda em
-- reunião comercial, ou o dia em treinamento, aparecia na TV como quem faltou.
--
-- A hora passa a apontar para uma OS OU para uma atividade interna, nunca as duas
-- nem nenhuma — a mesma regra da tarefa, que é de OS ou é ausência.
--
-- Regras:
--  - hora interna NÃO tem aprovação: nasce aprovada;
--  - NÃO tem custo: fica fora de vw_apontamentos_horas_custo e de tudo que soma
--    dinheiro; o que se vê dela é tempo;
--  - NÃO exige taxa vigente: taxa é conceito de custo, e integração acontece
--    justamente antes de a pessoa ter taxa;
--  - conta na meta da semana da TV, porque é hora trabalhada;
--  - Comercial pede cliente (cadastrado ou nome digitado) e a descrição do orçamento;
--  - quem lança: a própria pessoa para si, e coordenação para cima para qualquer um,
--    igual à hora em OS;
--  - o tablet oferece só as atividades que NÃO pedem cliente.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '180s';
set local role postgres;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- Parte 1: o catálogo de atividades internas
-- ─────────────────────────────────────────────────────────────────────────────────────

create table if not exists public.atividades_internas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  codigo text not null,
  nome text not null,
  -- Comercial pede para quem foi o tempo: cliente e orçamento. As outras não.
  pede_cliente boolean not null default false,
  ativo boolean not null default true,
  ordem smallint not null default 0,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint chk_atividades_internas_codigo check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  constraint chk_atividades_internas_nome check (char_length(btrim(nome)) between 2 and 60),
  constraint uq_atividades_internas_codigo unique (tenant_id, empresa_id, codigo)
);

comment on table public.atividades_internas is
  'Onde a hora vai quando não é OS: comercial, treinamento, manutenção da fábrica, administrativo, exames, integração. Catálogo por empresa, editável pela gestão. Ver docs/horas-internas.md.';

alter table public.atividades_internas enable row level security;
revoke all on table public.atividades_internas from public, anon, authenticated;
grant select, insert, update, delete on public.atividades_internas to service_role;

drop trigger if exists trg_atividades_internas_audit on public.atividades_internas;
create trigger trg_atividades_internas_audit
after insert or update or delete on public.atividades_internas
for each row execute function public.audit_trigger();

-- As seis de partida, para toda empresa que existe. Exames e Integração entram com
-- nome próprio de propósito: daqui a um ano a pergunta vai ser "para onde foram as
-- horas", e essa resposta só existe se cada coisa tiver o seu nome desde o começo.
create or replace function public.fn_atividades_internas_semear(p_tenant_id uuid, p_empresa_id uuid)
returns void
language sql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
  insert into public.atividades_internas (tenant_id, empresa_id, codigo, nome, pede_cliente, ordem)
  values
    (p_tenant_id, p_empresa_id, 'comercial',          'Comercial',             true,  10),
    (p_tenant_id, p_empresa_id, 'treinamento',        'Treinamento',           false, 20),
    (p_tenant_id, p_empresa_id, 'manutencao_fabrica', 'Manutenção da fábrica', false, 30),
    (p_tenant_id, p_empresa_id, 'administrativo',     'Administrativo',        false, 40),
    (p_tenant_id, p_empresa_id, 'exames',             'Exames',                false, 50),
    (p_tenant_id, p_empresa_id, 'integracao',         'Integração',            false, 60)
  on conflict (tenant_id, empresa_id, codigo) do nothing;
$fn$;

revoke all on function public.fn_atividades_internas_semear(uuid, uuid) from public, anon, authenticated;

select public.fn_atividades_internas_semear(e.tenant_id, e.id) from c.empresa as e;

-- Empresa nova nasce com o catálogo, como nasce com a jornada.
create or replace function public.fn_atividades_internas_semear_empresa()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
begin
  perform public.fn_atividades_internas_semear(new.tenant_id, new.id);
  return new;
end;
$fn$;

drop trigger if exists trg_empresas_atividades_internas on public.empresas;
create trigger trg_empresas_atividades_internas
after insert on public.empresas
for each row execute function public.fn_atividades_internas_semear_empresa();

-- Leitura para o aplicativo e para a tela de lançar hora. p_para_tablet tira as que
-- pedem cliente: o tablet da fábrica não é lugar de digitar nome de cliente.
create or replace function public.app_atividades_internas(p_para_tablet boolean default false)
returns table (id uuid, codigo text, nome text, pede_cliente boolean, ordem smallint)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if auth.uid() is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  return query
  select a.id, a.codigo, a.nome, a.pede_cliente, a.ordem
  from public.atividades_internas as a
  where a.tenant_id = v_tenant_id
    and a.empresa_id = v_empresa_id
    and a.ativo
    and (not p_para_tablet or not a.pede_cliente)
  order by a.ordem, a.nome;
end;
$fn$;

revoke all on function public.app_atividades_internas(boolean) from public, anon;
grant execute on function public.app_atividades_internas(boolean) to authenticated;

-- Cadastro (web): a gestão vê tudo, inclusive inativas, e salva.
create or replace function public.web_atividades_internas_listar()
returns table (id uuid, codigo text, nome text, pede_cliente boolean, ativo boolean, ordem smallint, em_uso bigint)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $fn$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if auth.uid() is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  if coalesce(a.fn_current_empresa_papel(v_tenant_id, v_empresa_id), '') not in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    raise exception 'O cadastro de atividades internas é da gestão.';
  end if;
  return query
  select at.id, at.codigo, at.nome, at.pede_cliente, at.ativo, at.ordem,
         (select count(*) from public.apontamentos_horas as h where h.atividade_id = at.id)
  from public.atividades_internas as at
  where at.tenant_id = v_tenant_id and at.empresa_id = v_empresa_id
  order by at.ativo desc, at.ordem, at.nome;
end;
$fn$;

revoke all on function public.web_atividades_internas_listar() from public, anon;
grant execute on function public.web_atividades_internas_listar() to authenticated;

create or replace function public.web_atividade_interna_salvar(
  p_id uuid,
  p_codigo text,
  p_nome text,
  p_pede_cliente boolean,
  p_ativo boolean,
  p_ordem integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $fn$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_codigo text := lower(regexp_replace(btrim(coalesce(p_codigo, '')), '[^a-z0-9_]+', '_', 'g'));
  v_nome text := btrim(coalesce(p_nome, ''));
  v_id uuid;
begin
  if auth.uid() is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  if coalesce(a.fn_current_empresa_papel(v_tenant_id, v_empresa_id), '') not in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    raise exception 'O cadastro de atividades internas é da gestão.';
  end if;
  if v_nome = '' then
    raise exception 'Informe o nome da atividade.';
  end if;
  if v_codigo = '' then
    v_codigo := lower(regexp_replace(translate(v_nome, 'áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ', 'aaaaeeiooouc' || 'AAAAEEIOOOUC'), '[^a-zA-Z0-9]+', '_', 'g'));
  end if;

  if p_id is null then
    insert into public.atividades_internas (tenant_id, empresa_id, codigo, nome, pede_cliente, ativo, ordem)
    values (v_tenant_id, v_empresa_id, v_codigo, v_nome, coalesce(p_pede_cliente, false), coalesce(p_ativo, true), coalesce(p_ordem, 0))
    returning id into v_id;
  else
    update public.atividades_internas
       set codigo = v_codigo,
           nome = v_nome,
           pede_cliente = coalesce(p_pede_cliente, false),
           ativo = coalesce(p_ativo, true),
           ordem = coalesce(p_ordem, 0),
           atualizado_em = now()
     where id = p_id and tenant_id = v_tenant_id and empresa_id = v_empresa_id
     returning id into v_id;
    if v_id is null then
      raise exception 'Atividade não encontrada nesta empresa.';
    end if;
  end if;
  return jsonb_build_object('sucesso', true, 'id', v_id);
exception
  when unique_violation then
    raise exception 'Já existe uma atividade com o código "%".', v_codigo;
end;
$fn$;

revoke all on function public.web_atividade_interna_salvar(uuid, text, text, boolean, boolean, integer) from public, anon;
grant execute on function public.web_atividade_interna_salvar(uuid, text, text, boolean, boolean, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- Parte 2: a hora pode ir para a atividade em vez da OS
-- ─────────────────────────────────────────────────────────────────────────────────────

alter table public.apontamentos_horas alter column os_id drop not null;

alter table public.apontamentos_horas
  add column if not exists atividade_id uuid references public.atividades_internas (id),
  add column if not exists cliente_id integer references public.clientes (id),
  add column if not exists cliente_nome text,
  add column if not exists orcamento_descricao text;

comment on column public.apontamentos_horas.atividade_id is
  'Hora interna: aponta para a atividade em vez da OS. Exatamente um dos dois é preenchido (chk_apontamentos_horas_destino).';
comment on column public.apontamentos_horas.cliente_nome is
  'Cliente da hora comercial quando ele ainda não existe no cadastro: nome digitado, sem vínculo. Quando existe, vai em cliente_id.';
comment on column public.apontamentos_horas.orcamento_descricao is
  'Em Comercial: qual orçamento. Texto livre ("painel da linha 3"), para saber quanto tempo foi para cada proposta antes de virar OS.';

-- OS ou atividade, uma só. Cliente e orçamento só fazem sentido na atividade.
alter table public.apontamentos_horas drop constraint if exists chk_apontamentos_horas_destino;
alter table public.apontamentos_horas add constraint chk_apontamentos_horas_destino
  check ((os_id is not null)::integer + (atividade_id is not null)::integer = 1);

alter table public.apontamentos_horas drop constraint if exists chk_apontamentos_horas_cliente_so_interna;
alter table public.apontamentos_horas add constraint chk_apontamentos_horas_cliente_so_interna
  check (atividade_id is not null or (cliente_id is null and cliente_nome is null and orcamento_descricao is null));

create index if not exists idx_apontamentos_horas_atividade
  on public.apontamentos_horas (tenant_id, empresa_id, atividade_id, data)
  where atividade_id is not null;

-- A trilha de edição gravava a OS como obrigatória. Editar uma hora interna caía aqui.
alter table public.apontamentos_horas_edicoes alter column os_id drop not null;

-- O validador ganha o ramo da atividade. O ramo da OS é o de sempre.
create or replace function public.fn_validar_apontamento_horas()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public', 'a', 'c', 'f', 'm', 'r', 'auth', 'extensions'
as $fn$
declare
  v_status_legado text;
  v_status_fluxo text;
  v_tem_taxa boolean;
  v_atividade public.atividades_internas;
  v_permitir_os_encerrada boolean := coalesce(current_setting('app.apontamento_permite_os_encerrada', true), '') = 'on';
begin
  -- ── Hora interna ───────────────────────────────────────────────────────────────
  if new.atividade_id is not null then
    select * into v_atividade
    from public.atividades_internas as at
    where at.id = new.atividade_id
      and at.tenant_id = new.tenant_id
      and at.empresa_id = new.empresa_id;
    if v_atividade.id is null then
      raise exception 'Atividade interna não encontrada nesta empresa.';
    end if;
    if not v_atividade.ativo then
      raise exception 'A atividade "%" está inativa e não recebe mais horas.', v_atividade.nome;
    end if;

    new.cliente_nome := nullif(btrim(coalesce(new.cliente_nome, '')), '');
    new.orcamento_descricao := nullif(btrim(coalesce(new.orcamento_descricao, '')), '');

    if v_atividade.pede_cliente then
      if new.cliente_id is null and new.cliente_nome is null then
        raise exception 'Hora em % pede o cliente: escolha um do cadastro ou digite o nome.', v_atividade.nome;
      end if;
      if new.orcamento_descricao is null then
        raise exception 'Hora em % pede qual orçamento: descreva em poucas palavras.', v_atividade.nome;
      end if;
    end if;

    if new.cliente_id is not null and not exists (
      select 1 from public.clientes as cli
      where cli.id = new.cliente_id and cli.tenant_id = new.tenant_id and cli.empresa_id = new.empresa_id
    ) then
      raise exception 'Cliente não encontrado nesta empresa.';
    end if;

    -- Não tem aprovação: nasce aprovada. E não tem custo, então não exige taxa —
    -- integração acontece justamente antes de a pessoa ter taxa.
    new.status_aprovacao := 'aprovado';
    new.aprovado_automaticamente_em := coalesce(new.aprovado_automaticamente_em, now());
    return new;
  end if;

  -- ── Hora em OS (como sempre foi) ───────────────────────────────────────────────
  select os.status, os.status_fluxo
    into v_status_legado, v_status_fluxo
  from public.ordens_servico as os
  where os.id = new.os_id
    and os.tenant_id = new.tenant_id
    and os.empresa_id = new.empresa_id;

  if v_status_legado is null then
    raise exception 'OS % não encontrada.', new.os_id;
  end if;
  if v_status_legado = 'cancelada' then
    raise exception 'Não é permitido lançar horas: OS % está cancelada.', new.os_id;
  end if;

  v_status_fluxo := coalesce(v_status_fluxo, public.mapear_status_legado_para_fluxo(v_status_legado));
  if v_status_fluxo not in ('em_andamento', 'em_andamento_garantia') then
    if not (
      v_permitir_os_encerrada
      and v_status_fluxo in ('concluida', 'faturada', 'concluida_garantia')
    ) then
      raise exception 'Não é permitido lançar horas: a OS % não está em andamento.', new.os_id;
    end if;
  end if;

  if coalesce(new.gerado_por_hh, false) then
    return new;
  end if;

  select exists (
    select 1
    from public.colaborador_taxas as taxa
    where taxa.colaborador_id = new.colaborador_id
      and taxa.tenant_id = new.tenant_id
      and taxa.empresa_id = new.empresa_id
      and new.data >= taxa.vigencia_inicio
      and (taxa.vigencia_fim is null or new.data <= taxa.vigencia_fim)
  ) into v_tem_taxa;

  if not v_tem_taxa then
    raise exception 'Não é permitido lançar horas: colaborador % não possui taxa vigente em %.', new.colaborador_id, new.data;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_validar_apontamento_horas on public.apontamentos_horas;
create trigger trg_validar_apontamento_horas
before insert or update of os_id, atividade_id, colaborador_id, data
on public.apontamentos_horas
for each row execute function public.fn_validar_apontamento_horas();

-- Custo é de OS. Hora interna não entra aqui, e por tabela não entra em
-- vw_custo_mao_obra_os nem em nada que some dinheiro por OS.
create or replace view public.vw_apontamentos_horas_custo with (security_invoker = true) as
 select a.id as apontamento_id,
    a.os_id,
    a.colaborador_id,
    c.nome as colaborador_nome,
    a.data,
    a.horas,
    th.codigo as tipo_hora_codigo,
    th.descricao as tipo_hora_descricao,
    coalesce(a.fator_aplicado, th.fator, 1::numeric) as fator,
    coalesce(tx.valor_hora, 0::numeric(10,2)) as valor_hora,
    round(a.horas * coalesce(tx.valor_hora, 0::numeric(10,2)) * coalesce(a.fator_aplicado, th.fator, 1::numeric), 2) as custo_lancamento,
    a.descricao,
    a.status,
    a.criado_em
   from public.apontamentos_horas a
     join public.colaboradores c on c.id = a.colaborador_id
     left join public.tipos_horas th on th.id = a.tipo_hora_id
     left join lateral ( select t.valor_hora
           from public.colaborador_taxas t
          where t.colaborador_id = a.colaborador_id and t.tenant_id = a.tenant_id and t.empresa_id = a.empresa_id
          order by
                case
                    when a.data >= t.vigencia_inicio and (t.vigencia_fim is null or a.data <= t.vigencia_fim) then 0
                    when t.vigencia_inicio <= a.data then 1
                    else 2
                end,
                case
                    when t.vigencia_inicio <= a.data then t.vigencia_inicio
                    else null::date
                end desc nulls last,
                case
                    when t.vigencia_inicio > a.data then t.vigencia_inicio
                    else null::date
                end, t.criado_em desc
         limit 1) tx on true
  where a.os_id is not null;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- Parte 3: gravar hora interna (núcleo, aplicativo, web e tablet)
-- ─────────────────────────────────────────────────────────────────────────────────────

-- Núcleo: valida o lote, classifica cada hora pela data (mesma regra do tablet e da
-- hora em OS: feriado e domingo 100%, sábado 50%, dia útil normal até 9h e o resto
-- 50%) e grava. Quem chama já resolveu QUEM pode lançar PARA QUEM.
create or replace function public.fn_horas_internas_gravar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_atividade_id uuid,
  p_data date,
  p_lancamentos jsonb,
  p_descricao text,
  p_cliente_id integer,
  p_cliente_nome text,
  p_orcamento_descricao text,
  p_confirmar_avisos boolean,
  p_criado_por_user_id uuid,
  p_tablet_sessao_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
declare
  v_atividade public.atividades_internas;
  v_hoje date := public.fn_tablet_data_hoje();
  v_descricao text := nullif(btrim(coalesce(p_descricao, '')), '');
  v_cliente_nome text := nullif(btrim(coalesce(p_cliente_nome, '')), '');
  v_orcamento text := nullif(btrim(coalesce(p_orcamento_descricao, '')), '');
  v_erros jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
  v_item jsonb;
  v_colaborador_id uuid;
  v_horas numeric;
  v_nome text;
  v_ativo boolean;
  v_total_dia numeric;
  v_classificacao jsonb;
  v_parte jsonb;
  v_ids uuid[] := '{}'::uuid[];
  v_id uuid;
  v_vistos uuid[] := '{}'::uuid[];
begin
  select * into v_atividade
  from public.atividades_internas as at
  where at.id = p_atividade_id and at.tenant_id = p_tenant_id and at.empresa_id = p_empresa_id;
  if v_atividade.id is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'atividade', 'mensagem', 'Escolha a atividade.'));
  elsif not v_atividade.ativo then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'atividade', 'mensagem', format('A atividade "%s" está inativa.', v_atividade.nome)));
  end if;

  if p_data is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'data', 'mensagem', 'Informe a data.'));
  elsif p_data > v_hoje then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'data_futura', 'mensagem', 'Não é permitido lançar horas em data futura.'));
  end if;

  if v_atividade.id is not null and v_atividade.pede_cliente then
    if p_cliente_id is null and v_cliente_nome is null then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'cliente', 'mensagem', format('%s pede o cliente: escolha um do cadastro ou digite o nome.', v_atividade.nome)));
    end if;
    if v_orcamento is null then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'orcamento', 'mensagem', format('%s pede qual orçamento: descreva em poucas palavras.', v_atividade.nome)));
    end if;
  end if;

  if p_cliente_id is not null and not exists (
    select 1 from public.clientes as cli where cli.id = p_cliente_id and cli.tenant_id = p_tenant_id and cli.empresa_id = p_empresa_id
  ) then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'cliente', 'mensagem', 'Cliente não encontrado nesta empresa.'));
  end if;

  if p_lancamentos is null or jsonb_typeof(p_lancamentos) <> 'array' or jsonb_array_length(p_lancamentos) = 0 then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'lancamentos', 'mensagem', 'Informe ao menos um colaborador.'));
  end if;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  -- Cada pessoa do lote: existe, está ativa, horas válidas, e os avisos.
  for v_item in select value from jsonb_array_elements(p_lancamentos) loop
    begin v_colaborador_id := nullif(v_item ->> 'colaborador_id', '')::uuid; exception when others then v_colaborador_id := null; end;
    begin v_horas := round((v_item ->> 'horas')::numeric, 2); exception when others then v_horas := null; end;

    if v_colaborador_id is null then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'colaborador', 'mensagem', 'Há um lançamento sem colaborador.'));
      continue;
    end if;
    if v_colaborador_id = any(v_vistos) then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'lote_duplicado', 'mensagem', 'A mesma pessoa aparece duas vezes no lote.'));
      continue;
    end if;
    v_vistos := v_vistos || v_colaborador_id;

    select c.nome, c.ativo into v_nome, v_ativo
    from public.colaboradores as c
    where c.id = v_colaborador_id and c.tenant_id = p_tenant_id and c.empresa_id = p_empresa_id;
    if not found then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'colaborador', 'mensagem', 'Colaborador não pertence a esta empresa.'));
      continue;
    end if;
    if not coalesce(v_ativo, false) then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'colaborador_inativo', 'mensagem', format('%s está inativo(a) e não recebe apontamento.', v_nome)));
      continue;
    end if;
    if v_horas is null or v_horas <= 0 or v_horas > 24 then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'horas', 'mensagem', format('Informe entre 0 e 24 horas para %s.', v_nome)));
      continue;
    end if;

    if p_data < v_hoje - 7 then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('tipo', 'retroativo',
        'mensagem', format('Este apontamento é retroativo: a data %s tem mais de 7 dias.', to_char(p_data, 'DD/MM/YYYY'))));
    end if;
    select coalesce(sum(h.horas), 0) into v_total_dia
    from public.apontamentos_horas as h
    where h.tenant_id = p_tenant_id and h.empresa_id = p_empresa_id
      and h.colaborador_id = v_colaborador_id and h.data = p_data
      and coalesce(h.status_aprovacao, 'pendente') <> 'rejeitado';
    if v_total_dia + v_horas > 9 then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('tipo', 'jornada_maior_que_9h',
        'mensagem', format('%s ficará com %s h apontadas em %s. Verifique se o intervalo de almoço foi descontado.',
          v_nome, replace((v_total_dia + v_horas)::text, '.', ','), to_char(p_data, 'DD/MM/YYYY'))));
    end if;
  end loop;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;
  if jsonb_array_length(v_avisos) > 0 and not p_confirmar_avisos then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', '[]'::jsonb);
  end if;

  -- Grava: a classificação pode partir uma hora em duas (normal até 9h e o resto
  -- extra), então cada pessoa pode virar mais de uma linha.
  for v_item in select value from jsonb_array_elements(p_lancamentos) loop
    v_colaborador_id := (v_item ->> 'colaborador_id')::uuid;
    v_horas := round((v_item ->> 'horas')::numeric, 2);
    v_classificacao := public.fn_tablet_classificar(p_tenant_id, p_data, v_horas);
    if jsonb_array_length(v_classificacao -> 'faltando') > 0 then
      raise exception 'Falta cadastrar o tipo de hora % ativo em Tipos de hora para classificar %.',
        (select string_agg(codigo, ', ') from jsonb_array_elements_text(v_classificacao -> 'faltando') as codigo),
        lower(v_classificacao ->> 'rotulo');
    end if;
    for v_parte in select value from jsonb_array_elements(v_classificacao -> 'partes') loop
      insert into public.apontamentos_horas (
        tenant_id, empresa_id, os_id, atividade_id, colaborador_id, data, horas, tipo_hora_id,
        descricao, status, gerado_por_hh, criado_por_user_id, tablet_sessao_id,
        cliente_id, cliente_nome, orcamento_descricao
      ) values (
        p_tenant_id, p_empresa_id, null, p_atividade_id, v_colaborador_id, p_data,
        (v_parte ->> 'horas')::numeric, (v_parte ->> 'tipo_hora_id')::uuid,
        v_descricao, 'lancado', false, p_criado_por_user_id, p_tablet_sessao_id,
        p_cliente_id, v_cliente_nome, v_orcamento
      )
      returning id into v_id;
      v_ids := v_ids || v_id;
    end loop;
  end loop;

  return jsonb_build_object(
    'sucesso', true,
    'gravados', cardinality(v_ids),
    'apontamento_ids', to_jsonb(v_ids),
    'atividade_id', p_atividade_id,
    'atividade_nome', v_atividade.nome,
    'data', p_data,
    'avisos', v_avisos,
    'erros', '[]'::jsonb
  );
end;
$fn$;

revoke all on function public.fn_horas_internas_gravar(uuid, uuid, uuid, date, jsonb, text, integer, text, text, boolean, uuid, uuid) from public, anon, authenticated;

-- Quem lança para quem: a mesma regra da hora em OS.
create or replace function public.fn_horas_internas_pode_lancar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_auth_uid uuid,
  p_lancamentos jsonb
)
returns text
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $fn$
declare
  v_papel text := coalesce(a.fn_current_empresa_papel(p_tenant_id, p_empresa_id), '');
  v_proprio uuid;
  v_item jsonb;
begin
  if not public.app_papel_pode_lancar_horas(v_papel) then
    return 'Seu perfil não tem permissão para lançar horas.';
  end if;
  select c.id into v_proprio
  from public.colaboradores as c
  where c.user_id = p_auth_uid and c.tenant_id = p_tenant_id and c.empresa_id = p_empresa_id and c.ativo;

  if upper(v_papel) in ('APONTADOR', 'APONTAMENTO_RH', 'TECNICO') then
    if v_proprio is null then
      return 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
    end if;
    for v_item in select value from jsonb_array_elements(coalesce(p_lancamentos, '[]'::jsonb)) loop
      if nullif(v_item ->> 'colaborador_id', '')::uuid is distinct from v_proprio then
        return 'Seu perfil só lança hora interna para você mesmo. Quem lança para os outros é a coordenação.';
      end if;
    end loop;
  end if;
  return null;
end;
$fn$;

revoke all on function public.fn_horas_internas_pode_lancar(uuid, uuid, uuid, jsonb) from public, anon, authenticated;

-- Aplicativo e web: mesma porta.
create or replace function public.app_lancar_horas_internas(
  p_atividade_id uuid,
  p_data date,
  p_lancamentos jsonb,
  p_descricao text default null,
  p_cliente_id integer default null,
  p_cliente_nome text default null,
  p_orcamento_descricao text default null,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $fn$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_erro text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  v_erro := public.fn_horas_internas_pode_lancar(v_tenant_id, v_empresa_id, v_auth_uid, p_lancamentos);
  if v_erro is not null then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'permissao', 'mensagem', v_erro)));
  end if;
  return public.fn_horas_internas_gravar(
    v_tenant_id, v_empresa_id, p_atividade_id, p_data, p_lancamentos, p_descricao,
    p_cliente_id, p_cliente_nome, p_orcamento_descricao, coalesce(p_confirmar_avisos, false), v_auth_uid, null
  );
exception
  when others then
    -- Os gatilhos falam português; a mensagem vai direto para a tela.
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'banco', 'mensagem', sqlerrm)));
end;
$fn$;

revoke all on function public.app_lancar_horas_internas(uuid, date, jsonb, text, integer, text, text, boolean) from public, anon;
grant execute on function public.app_lancar_horas_internas(uuid, date, jsonb, text, integer, text, text, boolean) to authenticated;

-- Tablet: as atividades que ele oferece e o lançamento pela sessão do PIN.
create or replace function public.app_tablet_atividades(p_sessao_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;
  return jsonb_build_object(
    'sucesso', true,
    'atividades', coalesce((
      select jsonb_agg(jsonb_build_object('id', at.id, 'codigo', at.codigo, 'nome', at.nome) order by at.ordem, at.nome)
      from public.atividades_internas as at
      where at.tenant_id = v_sessao.tenant_id and at.empresa_id = v_sessao.empresa_id
        and at.ativo and not at.pede_cliente
    ), '[]'::jsonb)
  );
end;
$fn$;

revoke all on function public.app_tablet_atividades(text) from public, anon;
grant execute on function public.app_tablet_atividades(text) to authenticated;

create or replace function public.fn_tablet_resumo_dia_interno(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_atividade_id uuid,
  p_data date
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
  with do_dia as (
    select h.id, h.os_id, h.atividade_id, h.horas, h.descricao, h.criado_em,
           (h.tablet_sessao_id is not null) as pelo_tablet,
           tipo.descricao as tipo_hora,
           at.nome as atividade_nome,
           coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) as numero_os
    from public.apontamentos_horas as h
    left join public.tipos_horas as tipo on tipo.id = h.tipo_hora_id
    left join public.atividades_internas as at on at.id = h.atividade_id
    left join public.ordens_servico as os on os.id = h.os_id
    where h.tenant_id = p_tenant_id and h.empresa_id = p_empresa_id
      and h.colaborador_id = p_colaborador_id and h.data = p_data
  )
  select jsonb_build_object(
    'lancamentos', coalesce((
      select jsonb_agg(jsonb_build_object('id', l.id, 'horas', l.horas, 'tipo_hora', l.tipo_hora, 'descricao', l.descricao,
                                          'criado_em', l.criado_em, 'pelo_tablet', l.pelo_tablet) order by l.criado_em)
      from do_dia as l where l.atividade_id = p_atividade_id
    ), '[]'::jsonb),
    'subtotal_atividade_horas', coalesce((select sum(l.horas) from do_dia as l where l.atividade_id = p_atividade_id), 0),
    'total_dia_horas', coalesce((select sum(l.horas) from do_dia as l), 0),
    'outras_do_dia', coalesce((
      select jsonb_agg(jsonb_build_object('rotulo', r.rotulo, 'horas', r.horas) order by r.rotulo)
      from (
        select coalesce('OS ' || l.numero_os, l.atividade_nome) as rotulo, sum(l.horas) as horas
        from do_dia as l
        where l.atividade_id is distinct from p_atividade_id
        group by 1
      ) as r
    ), '[]'::jsonb)
  );
$fn$;

revoke all on function public.fn_tablet_resumo_dia_interno(uuid, uuid, uuid, uuid, date) from public, anon, authenticated;

create or replace function public.app_tablet_lancar_horas_internas(
  p_sessao_token text,
  p_atividade_id uuid,
  p_data date,
  p_horas integer,
  p_minutos integer,
  p_chave uuid,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'extensions'
set row_security to 'off'
as $fn$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
  v_hoje date := public.fn_tablet_data_hoje();
  v_repetido public.tablet_lancamentos;
  v_colaborador_nome text;
  v_colaborador_ativo boolean;
  v_atividade public.atividades_internas;
  v_minutos integer;
  v_horas numeric;
  v_resultado jsonb;
  v_ids uuid[];
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;
  if p_chave is null then
    return public.fn_tablet_erro('chave', 'Chave de envio ausente. Tente novamente.');
  end if;

  select lancamento.* into v_repetido
  from public.tablet_lancamentos as lancamento
  join public.tablet_sessoes as sessao on sessao.id = lancamento.sessao_id
  where lancamento.chave = p_chave
    and sessao.dispositivo_id = v_sessao.dispositivo_id
    and sessao.colaborador_id = v_sessao.colaborador_id;
  if found then
    return (v_repetido.resultado - 'resumo') || jsonb_build_object('repetido', true,
      'resumo', public.fn_tablet_resumo_dia_interno(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id,
                  (v_repetido.resultado ->> 'atividade_id')::uuid, (v_repetido.resultado ->> 'data')::date));
  end if;

  select colaborador.nome, colaborador.ativo into v_colaborador_nome, v_colaborador_ativo
  from public.colaboradores as colaborador
  where colaborador.id = v_sessao.colaborador_id
    and colaborador.tenant_id = v_sessao.tenant_id and colaborador.empresa_id = v_sessao.empresa_id;
  if not found or not coalesce(v_colaborador_ativo, false) then
    update public.tablet_sessoes set encerrada_em = now(), encerrada_motivo = 'colaborador_inativo' where id = v_sessao.id;
    return public.fn_tablet_erro('colaborador_inativo', 'Seu cadastro de colaborador está inativo. Procure a coordenação.');
  end if;

  select * into v_atividade from public.atividades_internas as at
  where at.id = p_atividade_id and at.tenant_id = v_sessao.tenant_id and at.empresa_id = v_sessao.empresa_id and at.ativo;
  if v_atividade.id is null then
    return public.fn_tablet_erro('atividade', 'Escolha a atividade.');
  end if;
  if v_atividade.pede_cliente then
    return public.fn_tablet_erro('atividade', format('%s pede cliente e orçamento: lance pelo celular.', v_atividade.nome));
  end if;

  if p_data is null then
    return public.fn_tablet_erro('data', 'Informe a data do trabalho.');
  elsif p_data > v_hoje then
    return public.fn_tablet_erro('data_futura', 'Não é permitido lançar horas em data futura.');
  elsif p_data < v_hoje - 15 then
    return public.fn_tablet_erro('data_fora_da_janela',
      format('Só é possível lançar de %s a %s (hoje e os 15 dias anteriores). Para datas anteriores, procure a coordenação.',
        to_char(v_hoje - 15, 'DD/MM/YYYY'), to_char(v_hoje, 'DD/MM/YYYY')))
      || jsonb_build_object('janela', public.fn_tablet_janela());
  end if;

  if p_horas is null or p_minutos is null or p_horas < 0 or p_horas > 24 or p_minutos < 0 or p_minutos > 59 then
    return public.fn_tablet_erro('duracao', 'Informe horas entre 0 e 24 e minutos entre 0 e 59.');
  end if;
  v_minutos := p_horas * 60 + p_minutos;
  if v_minutos <= 0 then
    return public.fn_tablet_erro('duracao', 'A duração precisa ser maior que zero.');
  elsif v_minutos > 24 * 60 then
    return public.fn_tablet_erro('duracao', 'A duração não pode passar de 24 horas.');
  end if;
  v_horas := round(v_minutos / 60.0, 2);

  begin
    v_resultado := public.fn_horas_internas_gravar(
      v_sessao.tenant_id, v_sessao.empresa_id, p_atividade_id, p_data,
      jsonb_build_array(jsonb_build_object('colaborador_id', v_sessao.colaborador_id, 'horas', v_horas)),
      null, null, null, null, coalesce(p_confirmar_avisos, false), auth.uid(), v_sessao.id
    );
    if not coalesce((v_resultado ->> 'sucesso')::boolean, false) then
      return v_resultado;
    end if;

    v_ids := array(select value::uuid from jsonb_array_elements_text(v_resultado -> 'apontamento_ids'));
    v_resultado := v_resultado || jsonb_build_object(
      'apontamento_id', v_ids[1],
      'horas', v_horas,
      'minutos', v_minutos,
      'colaborador_id', v_sessao.colaborador_id,
      'colaborador_nome', v_colaborador_nome
    );
    insert into public.tablet_lancamentos (chave, sessao_id, apontamento_ids, resultado)
    values (p_chave, v_sessao.id, v_ids, v_resultado);
  exception
    when unique_violation then
      select lancamento.* into v_repetido from public.tablet_lancamentos as lancamento where lancamento.chave = p_chave;
      if v_repetido.chave is not null then
        return (v_repetido.resultado - 'resumo') || jsonb_build_object('repetido', true,
          'resumo', public.fn_tablet_resumo_dia_interno(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_atividade_id, p_data));
      end if;
      return public.fn_tablet_erro('banco', sqlerrm);
    when others then
      return public.fn_tablet_erro('banco', sqlerrm);
  end;

  return v_resultado || jsonb_build_object(
    'resumo', public.fn_tablet_resumo_dia_interno(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_atividade_id, p_data)
  );
end;
$fn$;

revoke all on function public.app_tablet_lancar_horas_internas(text, uuid, date, integer, integer, uuid, boolean) from public, anon;
grant execute on function public.app_tablet_lancar_horas_internas(text, uuid, date, integer, integer, uuid, boolean) to authenticated;

-- Para onde foram as horas: por atividade, pessoa, cliente e orçamento. É tempo, não
-- dinheiro — de propósito. Gestão e quem lê apontamentos.
create or replace function public.web_horas_internas_resumo(p_de date, p_ate date)
returns table (
  atividade_id uuid,
  atividade_codigo text,
  atividade_nome text,
  colaborador_id uuid,
  colaborador_nome text,
  cliente_id integer,
  cliente_nome text,
  orcamento_descricao text,
  horas numeric,
  lancamentos bigint,
  primeiro_dia date,
  ultimo_dia date
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $fn$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if auth.uid() is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  if not public.can('apontamentos', 'read', v_tenant_id) then
    raise exception 'Sem permissão para consultar apontamentos.';
  end if;
  if p_de is null or p_ate is null or p_ate < p_de or p_ate - p_de > 400 then
    raise exception 'Informe um período de até 400 dias.';
  end if;
  return query
  select at.id, at.codigo, at.nome,
         h.colaborador_id, colab.nome::text,
         h.cliente_id, coalesce(cli.nome::text, h.cliente_nome),
         h.orcamento_descricao,
         sum(h.horas)::numeric, count(*)::bigint, min(h.data), max(h.data)
  from public.apontamentos_horas as h
  join public.atividades_internas as at on at.id = h.atividade_id
  join public.colaboradores as colab on colab.id = h.colaborador_id
  left join public.clientes as cli on cli.id = h.cliente_id
  where h.tenant_id = v_tenant_id and h.empresa_id = v_empresa_id
    and h.atividade_id is not null
    and h.data between p_de and p_ate
    and coalesce(h.status_aprovacao, 'pendente') <> 'rejeitado'
  group by at.id, at.codigo, at.nome, h.colaborador_id, colab.nome, h.cliente_id, cli.nome, h.cliente_nome, h.orcamento_descricao
  order by at.ordem, at.nome, colab.nome, 7 nulls last, 8 nulls last;
end;
$fn$;

revoke all on function public.web_horas_internas_resumo(date, date) from public, anon;
grant execute on function public.web_horas_internas_resumo(date, date) to authenticated;

-- (A Parte 4, gerada a partir das definições vivas, vem abaixo: as leituras que
-- juntavam a OS por inner join e escondiam a hora interna.)

-- ─────────────────────────────────────────────────────────────────────────────────────
-- Parte 4: as leituras que juntavam a OS por inner join
--
-- Cada uma delas esconderia toda hora interna, porque a linha nao tem OS. Viram
-- left join, e as que devolvem tabela ganham as colunas da atividade no FIM, para
-- quem le por nome continuar lendo o que lia.
-- ─────────────────────────────────────────────────────────────────────────────────────

-- A. Editar e cancelar: a gestao continua podendo tudo; o "responsavel da OS"
--    simplesmente nao existe na hora interna.
CREATE OR REPLACE FUNCTION public.fn_usuario_pode_alterar_apontamento(p_tenant_id uuid, p_empresa_id uuid, p_auth_uid uuid, p_apontamento_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a'
 SET row_security TO 'off'
AS $function$
  select coalesce((
    select case
      when coalesce(apontamento.gerado_por_hh, false) then false
      when lower(coalesce(apontamento.status, '')) = 'fechado' then false
      when coalesce(acesso.papel, '') in ('ADMIN', 'DIRETOR', 'COORDENACAO') then true
      when p_auth_uid is not null
        and ordem.responsavel_aprovacao_id = p_auth_uid then true
      when coalesce(apontamento.status_aprovacao, 'pendente') = 'aprovado' then false
      else colaborador.user_id = p_auth_uid
    end
    from public.apontamentos_horas as apontamento
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = apontamento.tenant_id
     and colaborador.empresa_id = apontamento.empresa_id
    left join public.ordens_servico as ordem
      on ordem.id = apontamento.os_id
     and ordem.tenant_id = apontamento.tenant_id
     and ordem.empresa_id = apontamento.empresa_id
    left join lateral (
      select upper(usuario_empresa.papel) as papel
      from a.usuario as usuario
      join a.usuario_empresa as usuario_empresa
        on usuario_empresa.usuario_id = usuario.id
       and usuario_empresa.empresa_id = p_empresa_id
       and usuario_empresa.ativo is true
       and usuario_empresa.deleted_at is null
      where usuario.auth_user_id = p_auth_uid
        and usuario.ativo is true
        and usuario.deleted_at is null
      limit 1
    ) as acesso on true
    where apontamento.id = p_apontamento_id
      and apontamento.tenant_id = p_tenant_id
      and apontamento.empresa_id = p_empresa_id
  ), false);
$function$;

-- B. Cancelar: a mensagem e a notificacao usam o nome da atividade onde usariam o
--    numero da OS.
CREATE OR REPLACE FUNCTION public.app_cancelar_apontamento(p_apontamento_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_cancelado_por_nome text;
  v_apontamento public.apontamentos_horas%rowtype;
  v_numero_os text;
  v_cliente_nome text;
  v_colaborador_nome text;
  v_tipo_hora_nome text;
  v_lancado_por_user_id uuid;
  v_eventos_aprovacao jsonb := '[]'::jsonb;
  v_notificacao_id uuid;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_horas_texto text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select upper(usuario_empresa.papel::text),
         coalesce(
           nullif(btrim(usuario.nome), ''),
           nullif(btrim(usuario.email), ''),
           'Usuário não identificado'
         )
    into v_papel, v_cancelado_por_nome
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = v_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  if v_motivo is null or char_length(v_motivo) < 5 then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'motivo',
        'mensagem', 'Informe o motivo do cancelamento com pelo menos 5 caracteres.'
      ))
    );
  end if;

  if char_length(v_motivo) > 500 then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'motivo',
        'mensagem', 'O motivo do cancelamento deve ter no máximo 500 caracteres.'
      ))
    );
  end if;

  select apontamento.*
    into v_apontamento
  from public.apontamentos_horas as apontamento
  where apontamento.id = p_apontamento_id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
  for update;

  if not found then
    if exists (
      select 1
      from public.apontamentos_horas_cancelamentos as cancelamento
      where cancelamento.apontamento_id = p_apontamento_id
        and cancelamento.tenant_id = v_tenant_id
        and cancelamento.empresa_id = v_empresa_id
    ) then
      return jsonb_build_object(
        'sucesso', true,
        'gravados', 0,
        'ja_cancelado', true,
        'avisos', '[]'::jsonb,
        'erros', '[]'::jsonb
      );
    end if;

    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'apontamento',
        'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.'
      ))
    );
  end if;

  perform public.assert_documento_operacional_os(v_apontamento.os_id);

  if coalesce(v_apontamento.gerado_por_hh, false) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'hh',
        'mensagem', 'Este apontamento é um espelho de HH e deve ser corrigido no módulo HH.'
      ))
    );
  end if;

  if lower(coalesce(v_apontamento.status, '')) = 'fechado' then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'status',
        'mensagem', 'Este apontamento está fechado e não pode ser cancelado.'
      ))
    );
  end if;

  if exists (
    select 1
    from public.competencias as competencia
    where competencia.tenant_id = v_tenant_id
      and competencia.empresa_id = v_empresa_id
      and competencia.ano = extract(year from v_apontamento.data)::integer
      and competencia.mes = extract(month from v_apontamento.data)::integer
      and competencia.status = 'fechada'
  ) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'competencia',
        'mensagem', format(
          'A competência %s está fechada e este apontamento não pode ser cancelado.',
          to_char(v_apontamento.data, 'MM/YYYY')
        )
      ))
    );
  end if;

  if not public.fn_usuario_pode_alterar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, v_apontamento.id) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', case
          when coalesce(v_apontamento.status_aprovacao, 'pendente') = 'aprovado'
            then 'Após a aprovação, somente o responsável da OS, Coordenação, Diretor ou Admin pode cancelar.'
          else 'Antes da aprovação, somente o próprio colaborador, o responsável da OS, Coordenação, Diretor ou Admin pode cancelar.'
        end
      ))
    );
  end if;

  select
    coalesce(nullif(btrim(ordem.numero_os), ''), ordem.os_num::text, ordem.id::text,
             (select at.nome from public.atividades_internas as at where at.id = v_apontamento.atividade_id)),
    coalesce(ordem.cliente_nome, v_apontamento.cliente_nome),
    colaborador.nome,
    tipo_hora.descricao,
    coalesce(v_apontamento.criado_por_user_id, colaborador.user_id)
    into
      v_numero_os,
      v_cliente_nome,
      v_colaborador_nome,
      v_tipo_hora_nome,
      v_lancado_por_user_id
  from public.colaboradores as colaborador
  -- Hora interna nao tem OS: a OS vira opcional e o que amarra e o colaborador.
  left join public.ordens_servico as ordem
    on ordem.id = v_apontamento.os_id
   and ordem.tenant_id = v_tenant_id
   and ordem.empresa_id = v_empresa_id
  left join public.tipos_horas as tipo_hora
    on tipo_hora.id = v_apontamento.tipo_hora_id
   and tipo_hora.tenant_id = v_tenant_id
  where colaborador.id = v_apontamento.colaborador_id
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id;

  if not found then
    raise exception 'Não foi possível localizar o colaborador do apontamento no contexto atual.';
  end if;

  select coalesce(
           jsonb_agg(to_jsonb(evento) order by evento.criado_em),
           '[]'::jsonb
         )
    into v_eventos_aprovacao
  from public.apontamentos_horas_aprovacao_eventos as evento
  where evento.apontamento_id = v_apontamento.id
    and evento.tenant_id = v_tenant_id
    and evento.empresa_id = v_empresa_id;

  insert into public.apontamentos_horas_cancelamentos (
    apontamento_id,
    tenant_id,
    empresa_id,
    os_id,
    numero_os,
    cliente_nome,
    colaborador_id,
    colaborador_nome,
    data,
    horas,
    tipo_hora_id,
    tipo_hora_nome,
    fator_aplicado,
    descricao,
    status_anterior,
    status_aprovacao_anterior,
    pendente_em,
    aprovado_em,
    rejeitado_em,
    motivo_devolucao,
    gerado_por_hh,
    lancado_por_user_id,
    criado_em,
    cancelado_por_user_id,
    cancelado_por_nome,
    cancelamento_motivo,
    dados_apontamento
  ) values (
    v_apontamento.id,
    v_apontamento.tenant_id,
    v_apontamento.empresa_id,
    v_apontamento.os_id,
    v_numero_os,
    v_cliente_nome,
    v_apontamento.colaborador_id,
    v_colaborador_nome,
    v_apontamento.data,
    v_apontamento.horas,
    v_apontamento.tipo_hora_id,
    v_tipo_hora_nome,
    v_apontamento.fator_aplicado,
    v_apontamento.descricao,
    v_apontamento.status,
    v_apontamento.status_aprovacao,
    v_apontamento.pendente_em,
    v_apontamento.aprovado_em,
    v_apontamento.rejeitado_em,
    v_apontamento.motivo_devolucao,
    v_apontamento.gerado_por_hh,
    v_lancado_por_user_id,
    v_apontamento.criado_em,
    v_auth_uid,
    v_cancelado_por_nome,
    v_motivo,
    to_jsonb(v_apontamento) || jsonb_build_object(
      'eventos_aprovacao', v_eventos_aprovacao
    )
  );

  delete from public.apontamentos_horas as apontamento
  where apontamento.id = v_apontamento.id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id;

  if not found then
    raise exception 'O apontamento mudou durante o cancelamento. Atualize a tela e tente novamente.';
  end if;

  v_horas_texto := replace(v_apontamento.horas::text, '.', ',');

  v_notificacao_id := public.app_criar_notificacao(
    v_tenant_id,
    v_empresa_id,
    v_lancado_por_user_id,
    'hora_cancelada',
    'Apontamento cancelado',
    format(
      '%s h de %s na OS %s foram canceladas por %s. Motivo: %s',
      v_horas_texto,
      to_char(v_apontamento.data, 'DD/MM/YYYY'),
      v_numero_os,
      v_cancelado_por_nome,
      v_motivo
    ),
    jsonb_build_object(
      'url', '/os/' || v_apontamento.os_id::text,
      'os_id', v_apontamento.os_id,
      'numero_os', v_numero_os,
      'apontamento_id', v_apontamento.id,
      'cancelado_por_user_id', v_auth_uid,
      'cancelado_por_nome', v_cancelado_por_nome,
      'cancelamento_motivo', v_motivo
    ),
    'hora_cancelada:' || v_apontamento.id::text
  );

  return jsonb_build_object(
    'sucesso', true,
    'gravados', 1,
    'avisos', '[]'::jsonb,
    'erros', '[]'::jsonb,
    'notificacao_enviada', v_notificacao_id is not null,
    'cancelado_por_nome', v_cancelado_por_nome
  );
end;
$function$;

-- C. Listagem do web: hora interna aparece com a atividade e, em Comercial, com o
--    cliente (cadastrado ou digitado) e o orcamento.
drop function if exists public.web_listar_apontamentos_horas(date, date, integer, uuid, uuid, text, integer);
CREATE OR REPLACE FUNCTION public.web_listar_apontamentos_horas(p_data_inicio date, p_data_fim date, p_os_id integer DEFAULT NULL::integer, p_colaborador_id uuid DEFAULT NULL::uuid, p_tipo_hora_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 5000, p_atividade_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, os_id integer, numero_os text, cliente_nome text, descricao_servico text, colaborador_id uuid, colaborador_nome text, data date, horas numeric, tipo_hora_id uuid, tipo_codigo text, tipo_descricao text, fator_aplicado numeric, descricao text, status text, status_aprovacao text, criado_em timestamp with time zone, criado_por_user_id uuid, criado_por_nome text, gerado_por_hh boolean, hh_lancamento_id bigint, entrada_1 text, saida_1 text, entrada_2 text, saida_2 text, atividade_id uuid, atividade_nome text, cliente_id integer, orcamento_descricao text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_busca text := nullif(btrim(p_busca), '');
begin
  if auth.uid() is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação, tenant e empresa ativos são obrigatórios.';
  end if;
  if not public.can('apontamentos', 'read', v_tenant_id) then
    raise exception 'Sem permissão para consultar apontamentos.';
  end if;
  if p_data_inicio is null or p_data_fim is null or p_data_inicio > p_data_fim then
    raise exception 'Período inválido.';
  end if;

  return query
  select
    apontamento.id,
    apontamento.os_id,
    os.numero_os::text,
    coalesce(os.cliente_nome::text, cli.nome::text, apontamento.cliente_nome),
    os.descricao_servico::text,
    apontamento.colaborador_id,
    colaborador.nome::text,
    apontamento.data,
    apontamento.horas,
    apontamento.tipo_hora_id,
    tipo.codigo::text,
    tipo.descricao::text,
    apontamento.fator_aplicado,
    apontamento.descricao,
    apontamento.status::text,
    apontamento.status_aprovacao::text,
    apontamento.criado_em,
    apontamento.criado_por_user_id,
    usuario.nome::text,
    coalesce(apontamento.gerado_por_hh, false),
    apontamento.hh_lancamento_id,
    to_char(apontamento.hora_entrada_1, 'HH24:MI'),
    to_char(apontamento.hora_saida_1, 'HH24:MI'),
    to_char(apontamento.hora_entrada_2, 'HH24:MI'),
    to_char(apontamento.hora_saida_2, 'HH24:MI'),
    apontamento.atividade_id,
    at.nome::text,
    apontamento.cliente_id,
    apontamento.orcamento_descricao
  from public.apontamentos_horas as apontamento
  left join public.atividades_internas as at
    on at.id = apontamento.atividade_id
  left join public.clientes as cli
    on cli.id = apontamento.cliente_id
  left join public.ordens_servico as os
    on os.id = apontamento.os_id
   and os.tenant_id = apontamento.tenant_id
   and os.empresa_id = apontamento.empresa_id
  join public.colaboradores as colaborador
    on colaborador.id = apontamento.colaborador_id
   and colaborador.tenant_id = apontamento.tenant_id
   and colaborador.empresa_id = apontamento.empresa_id
  left join public.tipos_horas as tipo
    on tipo.id = apontamento.tipo_hora_id
   and tipo.tenant_id = apontamento.tenant_id
  left join a.usuario as usuario
    on usuario.auth_user_id = apontamento.criado_por_user_id
   and usuario.deleted_at is null
  where apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
    and apontamento.data between p_data_inicio and p_data_fim
    and (p_os_id is null or apontamento.os_id = p_os_id)
    and (p_atividade_id is null or apontamento.atividade_id = p_atividade_id)
    and (p_colaborador_id is null or apontamento.colaborador_id = p_colaborador_id)
    and (p_tipo_hora_id is null or apontamento.tipo_hora_id = p_tipo_hora_id)
    and (
      v_busca is null
      or os.numero_os ilike '%' || v_busca || '%'
      or os.cliente_nome ilike '%' || v_busca || '%'
      or os.descricao_servico ilike '%' || v_busca || '%'
      or apontamento.descricao ilike '%' || v_busca || '%'
      or colaborador.nome ilike '%' || v_busca || '%'
    )
  order by apontamento.data desc, apontamento.criado_em desc
  limit least(greatest(coalesce(p_limite, 5000), 1), 5000);
end;
$function$;
revoke all on function public.web_listar_apontamentos_horas(date, date, integer, uuid, uuid, text, integer, uuid) from public, anon;
grant execute on function public.web_listar_apontamentos_horas(date, date, integer, uuid, uuid, text, integer, uuid) to authenticated;

-- D. Historico do aplicativo.
drop function if exists public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text);
CREATE OR REPLACE FUNCTION public.app_historico_lancamentos(p_tipo text DEFAULT 'tudo'::text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_colaborador_id uuid DEFAULT NULL::uuid, p_os_id integer DEFAULT NULL::integer, p_limite integer DEFAULT 40, p_cursor text DEFAULT NULL::text)
 RETURNS TABLE(tipo text, origem_id text, criado_em timestamp with time zone, data_lancamento date, os_id integer, numero_os text, cliente_nome text, descricao text, quantidade numeric, unidade text, status text, nao_cobrado boolean, autor_id uuid, autor_nome text, pode_ver_autoria boolean, aprovado_por_nome text, atividade_nome text, cursor text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_colaborador_id uuid;
  v_apontador boolean;
  v_tipo text := lower(coalesce(nullif(btrim(p_tipo), ''), 'tudo'));
  v_de date := coalesce(p_de, current_date - 29);
  v_ate date := coalesce(p_ate, current_date);
  v_limite integer := greatest(1, least(coalesce(p_limite, 40), 100));
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar o historico do app.';
  end if;

  if v_tipo not in ('tudo', 'horas', 'materiais') then
    raise exception 'Tipo de historico invalido.';
  end if;
  if v_de > v_ate then
    raise exception 'Periodo de historico invalido.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true
  limit 1;

  v_apontador := v_papel in ('TECNICO', 'APONTAMENTO_RH', 'APONTADOR');
  if v_apontador and v_colaborador_id is null then
    raise exception 'Seu usuario nao esta vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  with lancamentos as (
    select
      'hora'::text as tipo,
      apontamento.id::text as origem_id,
      apontamento.criado_em::timestamptz as criado_em,
      apontamento.data as data_lancamento,
      os.id as os_id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text as numero_os,
      coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(apontamento.cliente_nome), ''),
               case when apontamento.atividade_id is null then 'Cliente nao informado' end)::text as cliente_nome,
      coalesce(nullif(btrim(os.descricao_servico), ''), nullif(btrim(apontamento.orcamento_descricao), ''),
               nullif(btrim(apontamento.descricao), ''), 'Apontamento de horas')::text as descricao,
      apontamento.horas::numeric as quantidade,
      'h'::text as unidade,
      coalesce(nullif(btrim(apontamento.status_aprovacao), ''), nullif(btrim(apontamento.status), ''), 'pendente')::text as status,
      false as nao_cobrado,
      apontamento.colaborador_id as autor_id,
      colaborador.nome::text as autor_nome,
      case
        when apontamento.aprovado_automaticamente_em is not null and apontamento.aprovado_por is null
          then 'Aprovação automática'
        else coalesce(
          nullif(btrim(perfil.nome), ''),
          nullif(btrim(aprovador.nome), ''),
          nullif(btrim(colaborador_aprovador.nome), '')
        )
      end::text as aprovado_por_nome,
      at.nome::text as atividade_nome
    from public.apontamentos_horas as apontamento
    left join public.atividades_internas as at
      on at.id = apontamento.atividade_id
    -- Hora interna nao tem OS. O left join deixa a linha viver; o filtro logo
    -- abaixo continua barrando hora de OV, que era o que o inner join fazia.
    left join public.ordens_servico as os
      on os.id = apontamento.os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
    left join public.profiles as perfil on perfil.id = apontamento.aprovado_por
    left join a.usuario as aprovador
      on aprovador.auth_user_id = apontamento.aprovado_por
     and aprovador.ativo is true
     and aprovador.deleted_at is null
    left join public.colaboradores as colaborador_aprovador
      on colaborador_aprovador.user_id = apontamento.aprovado_por
     and colaborador_aprovador.tenant_id = v_tenant_id
     and colaborador_aprovador.empresa_id = v_empresa_id
    where apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.data between v_de and v_ate
      and v_tipo in ('tudo', 'horas')
      and (apontamento.atividade_id is not null or os.id is not null)
      and (p_os_id is null or apontamento.os_id = p_os_id)
      and (
        case when v_apontador then apontamento.colaborador_id = v_colaborador_id
             else p_colaborador_id is null or apontamento.colaborador_id = p_colaborador_id end
      )

    union all

    select
      'material'::text,
      movimentacao.id::text,
      coalesce(movimentacao.created_at, movimentacao.data_movimentacao)::timestamptz,
      movimentacao.data_movimentacao::date,
      os.id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text,
      coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text,
      (coalesce(nullif(btrim(item.nome), ''), nullif(btrim(item.descricao), ''), 'Material')
        || case when nullif(btrim(item.codigo_interno), '') is not null then ' - cod. ' || item.codigo_interno else '' end)::text,
      movimentacao.quantidade::numeric,
      coalesce(nullif(btrim(item.unidade_medida), ''), 'un')::text,
      'baixado'::text,
      coalesce(item_os.nao_cobrado, false),
      autor.id,
      autor.nome::text,
      null::text,
      null::text
    from public.movimentacoes as movimentacao
    join public.ordens_servico as os
      on os.id = movimentacao.origem_os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.itens as item
      on item.id = movimentacao.item_id
     and item.tenant_id = v_tenant_id
     and item.empresa_id = v_empresa_id
    left join lateral (
      select
        colaborador.id,
        colaborador.nome
      from public.colaboradores as colaborador
      where colaborador.tenant_id = v_tenant_id
        and colaborador.empresa_id = v_empresa_id
        and colaborador.ativo is true
        and (
          colaborador.user_id::text = movimentacao.realizado_por
          or lower(coalesce(colaborador.email, '')) = lower(coalesce(movimentacao.realizado_por, ''))
        )
      order by case when colaborador.user_id::text = movimentacao.realizado_por then 0 else 1 end
      limit 1
    ) as autor on true
    left join lateral (
      select public.os_lancamento_nao_cobrado(
        v_tenant_id,
        v_empresa_id,
        item_lancado.os_id,
        item_lancado.criado_em
      ) as nao_cobrado
      from public.os_itens as item_lancado
      where item_lancado.tenant_id = v_tenant_id
        and item_lancado.empresa_id = v_empresa_id
        and item_lancado.os_id = movimentacao.origem_os_id
        and item_lancado.item_id = movimentacao.item_id
        and abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))) <= 600
      order by abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))), item_lancado.id desc
      limit 1
    ) as item_os on true
    where movimentacao.tenant_id = v_tenant_id
      and movimentacao.empresa_id = v_empresa_id
      and movimentacao.tipo = 'saida'
      and movimentacao.motivo like 'Material lançado pelo app na OS %'
      and movimentacao.data_movimentacao::date between v_de and v_ate
      and v_tipo in ('tudo', 'materiais')
      and (p_os_id is null or movimentacao.origem_os_id = p_os_id)
      and (
        case when v_apontador then autor.id = v_colaborador_id
             else p_colaborador_id is null or autor.id = p_colaborador_id end
      )
  ), com_cursor as (
    select
      lancamento.*,
      to_char(lancamento.criado_em at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
        || '|' || lancamento.tipo || '|' || lancamento.origem_id as chave_cursor
    from lancamentos as lancamento
  )
  select
    lancamento.tipo,
    lancamento.origem_id,
    lancamento.criado_em,
    lancamento.data_lancamento,
    lancamento.os_id,
    lancamento.numero_os,
    lancamento.cliente_nome,
    lancamento.descricao,
    lancamento.quantidade,
    lancamento.unidade,
    lancamento.status,
    lancamento.nao_cobrado,
    case when v_apontador then null::uuid else lancamento.autor_id end,
    case when v_apontador then null::text else lancamento.autor_nome end,
    not v_apontador,
    case when v_apontador then null::text else lancamento.aprovado_por_nome end,
    lancamento.atividade_nome,
    lancamento.chave_cursor
  from com_cursor as lancamento
  where p_cursor is null or lancamento.chave_cursor < p_cursor
  order by lancamento.chave_cursor desc
  limit v_limite;
end;
$function$;
revoke all on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) from public, anon;
grant execute on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) to authenticated;

-- E. Televisao: a hora interna conta na semana e no mes, e o cartao mostra a
--    atividade onde mostraria a OS.
drop function if exists public.tv_horas_periodo(date, date, text);
CREATE OR REPLACE FUNCTION public.tv_horas_periodo(p_inicio date, p_fim date, p_area text DEFAULT NULL::text)
 RETURNS TABLE(colaborador_id uuid, colaborador_nome text, os_id integer, numero_os text, cliente_nome text, data date, horas numeric, status_aprovacao text, atividade_id uuid, atividade_nome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
declare
  v_ctx record;
  v_area text := public.fn_tv_area(p_area);
begin
  select * into v_ctx from public.fn_tv_contexto();

  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 366 then
    raise exception 'Informe um período de até 367 dias.';
  end if;

  return query
  select
    apontamento.colaborador_id,
    colab.nome::text,
    apontamento.os_id,
    coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text,
    case when apontamento.os_id is null then null
         else coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado') end::text,
    apontamento.data,
    sum(apontamento.horas)::numeric,
    coalesce(apontamento.status_aprovacao, 'pendente')::text,
    apontamento.atividade_id,
    at.nome::text
  from public.apontamentos_horas as apontamento
  left join public.atividades_internas as at
    on at.id = apontamento.atividade_id
  join public.colaboradores as colab
    on colab.id = apontamento.colaborador_id
   and colab.ativo is true
  left join public.ordens_servico as os on os.id = apontamento.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = apontamento.tenant_id and cli.empresa_id = apontamento.empresa_id
  where apontamento.tenant_id = v_ctx.tenant_id
    and apontamento.empresa_id = v_ctx.empresa_id
    and apontamento.data between p_inicio and p_fim
    and coalesce(apontamento.status_aprovacao, 'pendente') <> 'rejeitado'
    and (v_area is null or colab.area = v_area)
  group by
    apontamento.colaborador_id,
    colab.nome,
    apontamento.os_id,
    os.numero_os,
    os.os_num,
    os.id,
    os.cliente_nome,
    cli.nome,
    apontamento.data,
    coalesce(apontamento.status_aprovacao, 'pendente'),
    apontamento.atividade_id,
    at.nome
  order by colab.nome, apontamento.data, 4;
end;
$function$;
revoke all on function public.tv_horas_periodo(date, date, text) from public, anon;
grant execute on function public.tv_horas_periodo(date, date, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- Assercoes: o que nao pode voltar atras
-- ─────────────────────────────────────────────────────────────────────────────────────

do $assertions$
declare
  v_def text;
  v_nome text;
begin
  -- OS ou atividade, exatamente uma.
  if not exists (select 1 from pg_constraint where conrelid = 'public.apontamentos_horas'::regclass and conname = 'chk_apontamentos_horas_destino') then
    raise exception 'apontamentos_horas ficou sem a regra "OS ou atividade"';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'apontamentos_horas' and column_name = 'os_id' and is_nullable = 'NO') then
    raise exception 'apontamentos_horas.os_id continua obrigatoria';
  end if;

  -- O catalogo nasceu em toda empresa, com as seis.
  if exists (
    select 1 from c.empresa as e
    where (select count(*) from public.atividades_internas as at where at.tenant_id = e.tenant_id and at.empresa_id = e.id) < 6
  ) then
    raise exception 'existe empresa sem as seis atividades internas de partida';
  end if;

  -- Custo e de OS: a view nao pode somar hora interna.
  if pg_get_viewdef('public.vw_apontamentos_horas_custo'::regclass) not ilike '%os_id IS NOT NULL%' then
    raise exception 'vw_apontamentos_horas_custo passou a somar hora interna';
  end if;

  -- Nenhuma dessas leituras pode voltar a esconder a hora interna.
  foreach v_nome in array array[
    'public.web_listar_apontamentos_horas(date, date, integer, uuid, uuid, text, integer, uuid)',
    'public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text)',
    'public.tv_horas_periodo(date, date, text)',
    'public.fn_usuario_pode_alterar_apontamento(uuid, uuid, uuid, uuid)',
    'public.app_cancelar_apontamento(uuid, text)'
  ] loop
    v_def := pg_get_functiondef(v_nome::regprocedure);
    if v_def ~* '\m(inner\s+)?join\s+public\.ordens_servico\s+as\s+(os|ordem)\M' and v_def !~* '\mleft\s+join\s+public\.ordens_servico\s+as\s+(os|ordem)\M' then
      raise exception '% ainda junta a OS por inner join e esconde a hora interna', v_nome;
    end if;
  end loop;

  -- A restricao da tabela e a validacao da trigger precisam concordar sobre o
  -- gatilho disparar tambem quando a atividade muda.
  if not exists (
    select 1 from pg_trigger as t
    where t.tgrelid = 'public.apontamentos_horas'::regclass and t.tgname = 'trg_validar_apontamento_horas'
      and pg_get_triggerdef(t.oid) ilike '%atividade_id%'
  ) then
    raise exception 'trg_validar_apontamento_horas nao dispara quando a atividade muda';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
