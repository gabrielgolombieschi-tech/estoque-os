-- Modo de tablet compartilhado para apontamento de horas por PIN.
--
-- O tablet fica na producao com UMA sessao Supabase (a "conta do tablet"), que
-- so autoriza o aparelho. Quem lanca a hora e o colaborador identificado pelo
-- PIN de 4 digitos — e essa identificacao e temporaria: vira uma sessao de
-- tablet no banco, com token que expira e e invalidado ao finalizar.
--
-- Por que nao usar auth.uid() como colaborador, como nas RPCs app_*: todas elas
-- exigem colaboradores.user_id = auth.uid() (um usuario, uma pessoa). No tablet
-- a pessoa muda a cada PIN, entao as RPCs app_tablet_* recebem o token da
-- sessao do tablet e resolvem o colaborador no servidor. Nada de colaborador_id
-- vindo da interface.
--
-- A conta do tablet precisa ter papel APONTADOR na empresa (can() nega tudo
-- para ele — e o perfil mais restrito que existe) e estar em
-- tablet_dispositivos. Sem as duas coisas, nenhuma app_tablet_* funciona.
--
-- O que entra no ERP e a mesma apontamentos_horas de sempre: colaborador_id e o
-- beneficiario (quem digitou o PIN), criado_por_user_id e a conta do tablet
-- (quem executou), e tablet_sessao_id amarra a linha a sessao do PIN. Custos,
-- relatorios, aprovacao (pendente, porque o executor e APONTADOR), competencia
-- fechada e taxa vigente seguem valendo pelos triggers existentes.
--
-- Regras de seguranca do PIN: hash bcrypt em tabela sem policy (so as funcoes
-- SECURITY DEFINER leem), 5 erros seguidos bloqueiam o aparelho por 5 minutos
-- (dobrando a cada novo erro), sem log do PIN em lugar nenhum.
--
-- De carona, duas regras existentes ganham o aperto que o modo tablet exige:
-- web_criar_apontamentos_horas so aceita OS encerrada de Coordenacao, Diretor,
-- Admin ou do responsavel da OS (antes barrava so APONTADOR), e
-- app_editar_apontamento so acusa duplicidade quando o tipo de hora muda —
-- porque o tablet pode gravar mais de uma linha na mesma OS/data (a pessoa
-- confere o que ja tem e "adiciona" horas), e sem isso nenhuma das linhas
-- poderia ser editada depois.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Todas as funcoes do banco pertencem a postgres. Sem isto, as funcoes novas
-- ficariam com o dono da conexao do CLI e mudariam o efeito do SECURITY DEFINER.
set local role postgres;

-- 1. Tabelas -------------------------------------------------------------------

create table if not exists public.tablet_dispositivos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  auth_user_id uuid not null,
  nome text not null,
  inatividade_segundos integer not null default 60,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por_user_id uuid,
  atualizado_em timestamptz not null default now(),
  atualizado_por_user_id uuid,
  constraint chk_tablet_dispositivos_nome check (char_length(btrim(nome)) between 2 and 80),
  constraint chk_tablet_dispositivos_inatividade check (inatividade_segundos between 15 and 900),
  constraint uq_tablet_dispositivos_conta unique (auth_user_id)
);

comment on table public.tablet_dispositivos is
  'Contas (auth.users) autorizadas a operar como tablet compartilhado de apontamento. A conta precisa ter papel APONTADOR na empresa.';
comment on column public.tablet_dispositivos.inatividade_segundos is
  'Segundos sem toque ate o tablet esquecer o colaborador identificado e voltar ao PIN.';

create index if not exists idx_tablet_dispositivos_empresa
  on public.tablet_dispositivos (tenant_id, empresa_id);

create table if not exists public.colaboradores_pin (
  colaborador_id uuid primary key references public.colaboradores (id) on delete cascade,
  tenant_id uuid not null,
  empresa_id uuid not null,
  pin_hash text not null,
  definido_em timestamptz not null default now(),
  definido_por_user_id uuid
);

comment on table public.colaboradores_pin is
  'PIN de 4 digitos do colaborador para o tablet, guardado so como hash bcrypt. Sem policy: apenas as funcoes SECURITY DEFINER leem e escrevem.';

create index if not exists idx_colaboradores_pin_empresa
  on public.colaboradores_pin (tenant_id, empresa_id);

create table if not exists public.tablet_pin_tentativas (
  dispositivo_id uuid primary key references public.tablet_dispositivos (id) on delete cascade,
  falhas_consecutivas integer not null default 0,
  ultima_falha_em timestamptz,
  bloqueado_ate timestamptz,
  total_falhas bigint not null default 0
);

comment on table public.tablet_pin_tentativas is
  'Contador de PINs errados por tablet: 5 erros seguidos bloqueiam o aparelho por 5 minutos, dobrando a cada erro seguinte.';

create table if not exists public.tablet_sessoes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  dispositivo_id uuid not null references public.tablet_dispositivos (id),
  colaborador_id uuid not null references public.colaboradores (id),
  token_hash text not null unique,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  ultimo_uso_em timestamptz not null default now(),
  encerrada_em timestamptz,
  encerrada_motivo text
);

comment on table public.tablet_sessoes is
  'Identificacao temporaria do colaborador no tablet (um PIN aceito = uma sessao). O token fica so no aparelho; aqui vai o hash.';

create index if not exists idx_tablet_sessoes_dispositivo
  on public.tablet_sessoes (dispositivo_id, criado_em desc);

create index if not exists idx_tablet_sessoes_colaborador
  on public.tablet_sessoes (colaborador_id, criado_em desc);

create table if not exists public.tablet_lancamentos (
  chave uuid primary key,
  sessao_id uuid not null references public.tablet_sessoes (id),
  apontamento_id uuid not null,
  resultado jsonb not null,
  criado_em timestamptz not null default now()
);

comment on table public.tablet_lancamentos is
  'Chave de idempotencia dos lancamentos do tablet: repetir a mesma chave devolve o mesmo resultado em vez de gravar de novo.';

alter table public.apontamentos_horas
  add column if not exists tablet_sessao_id uuid references public.tablet_sessoes (id);

comment on column public.apontamentos_horas.tablet_sessao_id is
  'Quando preenchido, a hora foi lancada pelo tablet compartilhado nesta sessao de PIN (colaborador_id e quem digitou o PIN; criado_por_user_id e a conta do tablet).';

create index if not exists idx_apontamentos_horas_tablet_sessao
  on public.apontamentos_horas (tablet_sessao_id)
  where tablet_sessao_id is not null;

-- Mesma postura de apontamentos_horas_cancelamentos: RLS ligada e sem policy,
-- entao so as funcoes SECURITY DEFINER (row_security off) enxergam as tabelas.
alter table public.tablet_dispositivos enable row level security;
alter table public.colaboradores_pin enable row level security;
alter table public.tablet_pin_tentativas enable row level security;
alter table public.tablet_sessoes enable row level security;
alter table public.tablet_lancamentos enable row level security;

revoke all on table public.tablet_dispositivos from public, anon, authenticated;
revoke all on table public.colaboradores_pin from public, anon, authenticated;
revoke all on table public.tablet_pin_tentativas from public, anon, authenticated;
revoke all on table public.tablet_sessoes from public, anon, authenticated;
revoke all on table public.tablet_lancamentos from public, anon, authenticated;

grant select, insert, update, delete, truncate, references, trigger
  on public.tablet_dispositivos, public.colaboradores_pin, public.tablet_pin_tentativas,
     public.tablet_sessoes, public.tablet_lancamentos
  to service_role;

-- Autorizar e revogar tablet e acao administrativa: vai para a auditoria.
-- colaboradores_pin fica de fora de proposito, para o hash nao ir parar em
-- audit_log; a propria linha ja diz quem definiu e quando.
drop trigger if exists trg_tablet_dispositivos_audit on public.tablet_dispositivos;
create trigger trg_tablet_dispositivos_audit
after insert or update or delete on public.tablet_dispositivos
for each row execute function public.audit_trigger();

-- 2. Apoio -------------------------------------------------------------------

-- Dia de hoje no fuso da operacao. As datas de apontamento sao "dia de trabalho"
-- e o banco roda em UTC: as 22h em Guaramirim ja e amanha em UTC.
create or replace function public.fn_tablet_data_hoje()
returns date
language sql
stable
set search_path to 'pg_catalog'
as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

-- A conta logada e um tablet autorizado? Devolve a linha ou nulo — nunca levanta,
-- porque app_tablet_contexto() e chamada por toda sessao do app para decidir o
-- modo, inclusive por quem nao e tablet.
create or replace function public.fn_tablet_dispositivo_atual()
returns public.tablet_dispositivos
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_dispositivo public.tablet_dispositivos;
begin
  if v_auth_uid is null then
    return null;
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  if v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    return null;
  end if;

  -- APONTADOR e o unico papel aceito na conta do tablet: can() nega tudo para
  -- ele, entao a conta nao abre nenhum outro modulo do ERP.
  if coalesce(a.fn_current_empresa_papel(v_tenant_id, v_empresa_id), '') <> 'APONTADOR' then
    return null;
  end if;

  select dispositivo.*
    into v_dispositivo
  from public.tablet_dispositivos as dispositivo
  where dispositivo.auth_user_id = v_auth_uid
    and dispositivo.tenant_id = v_tenant_id
    and dispositivo.empresa_id = v_empresa_id
    and dispositivo.ativo;

  if not found then
    return null;
  end if;

  return v_dispositivo;
end;
$function$;

-- Valida o token da sessao do PIN para o tablet logado e renova a validade
-- (janela deslizante de 10 minutos, teto de 12 horas). Nulo = pedir o PIN de novo.
create or replace function public.fn_tablet_validar_sessao(p_sessao_token text)
returns public.tablet_sessoes
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $function$
declare
  v_dispositivo public.tablet_dispositivos := public.fn_tablet_dispositivo_atual();
  v_sessao public.tablet_sessoes;
begin
  if v_dispositivo.id is null or nullif(btrim(coalesce(p_sessao_token, '')), '') is null then
    return null;
  end if;

  select sessao.*
    into v_sessao
  from public.tablet_sessoes as sessao
  where sessao.token_hash = encode(extensions.digest(btrim(p_sessao_token), 'sha256'), 'hex')
    and sessao.dispositivo_id = v_dispositivo.id
    and sessao.tenant_id = v_dispositivo.tenant_id
    and sessao.empresa_id = v_dispositivo.empresa_id
    and sessao.encerrada_em is null
    and sessao.expira_em > now()
    and sessao.criado_em > now() - interval '12 hours'
  for update;

  if not found then
    return null;
  end if;

  update public.tablet_sessoes
     set ultimo_uso_em = now(),
         expira_em = now() + interval '10 minutes'
   where id = v_sessao.id
  returning * into v_sessao;

  return v_sessao;
end;
$function$;

create or replace function public.fn_tablet_erro(p_tipo text, p_mensagem text)
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select jsonb_build_object(
    'sucesso', false,
    'erros', jsonb_build_array(jsonb_build_object('tipo', p_tipo, 'mensagem', p_mensagem)),
    'avisos', '[]'::jsonb
  );
$$;

create or replace function public.fn_tablet_erro_sessao()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog', 'public'
as $$
  select public.fn_tablet_erro('sessao_invalida', 'Sua identificação expirou. Digite o PIN novamente.');
$$;

-- Situacao da OS para o tablet: so OS (nao OV), sem HH e em andamento aceita hora.
create or replace function public.fn_tablet_os_situacao(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_os record;
  v_status_fluxo text;
  v_pode_lancar boolean := false;
  v_motivo text;
begin
  select os.id,
         coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) as numero,
         coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cliente.nome), ''), 'Cliente não informado') as cliente_nome,
         os.descricao_servico,
         coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) as status_fluxo,
         coalesce(os.usa_relatorio_hh, false) as usa_relatorio_hh,
         coalesce(os.tipo_documento, 'OS') as tipo_documento
    into v_os
  from public.ordens_servico as os
  left join public.clientes as cliente
    on cliente.id = os.cliente_id
   and cliente.tenant_id = p_tenant_id
   and cliente.empresa_id = p_empresa_id
  where os.id = p_os_id
    and os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id;

  if not found then
    return jsonb_build_object('encontrada', false, 'pode_lancar', false,
      'motivo_bloqueio', 'A OS informada não existe ou não pertence a esta empresa.');
  end if;

  v_status_fluxo := v_os.status_fluxo;

  if v_os.tipo_documento <> 'OS' then
    v_motivo := 'Este documento é uma venda (OV) e não recebe horas.';
  elsif v_os.usa_relatorio_hh then
    v_motivo := 'Esta OS é de HH e usa lançamento por horários. Use o aplicativo no celular.';
  elsif v_status_fluxo in ('em_andamento', 'em_andamento_garantia') then
    v_pode_lancar := true;
  else
    v_motivo := 'Esta OS já foi encerrada. Procure a coordenação para lançar estas horas.';
  end if;

  return jsonb_build_object(
    'encontrada', true,
    'id', v_os.id,
    'numero', v_os.numero,
    'cliente_nome', v_os.cliente_nome,
    'descricao_servico', v_os.descricao_servico,
    'status_fluxo', v_status_fluxo,
    'usa_relatorio_hh', v_os.usa_relatorio_hh,
    'pode_lancar', v_pode_lancar,
    'motivo_bloqueio', v_motivo
  );
end;
$function$;

-- O que o colaborador ja tem no dia: linhas da OS pedida, subtotal da OS e total
-- geral do dia (todas as OS, HH incluido — e o mesmo total que a regra das 9h usa).
create or replace function public.fn_tablet_resumo_dia(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_os_id integer,
  p_data date
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
  with do_dia as (
    select apontamento.id,
           apontamento.os_id,
           apontamento.horas,
           apontamento.descricao,
           apontamento.status_aprovacao,
           apontamento.criado_em,
           coalesce(apontamento.gerado_por_hh, false) as gerado_por_hh,
           (apontamento.tablet_sessao_id is not null) as pelo_tablet,
           tipo.descricao as tipo_hora,
           coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) as numero_os
    from public.apontamentos_horas as apontamento
    left join public.tipos_horas as tipo on tipo.id = apontamento.tipo_hora_id
    left join public.ordens_servico as os on os.id = apontamento.os_id
    where apontamento.tenant_id = p_tenant_id
      and apontamento.empresa_id = p_empresa_id
      and apontamento.colaborador_id = p_colaborador_id
      and apontamento.data = p_data
  )
  select jsonb_build_object(
    'lancamentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', linha.id,
        'horas', linha.horas,
        'tipo_hora', linha.tipo_hora,
        'descricao', linha.descricao,
        'status_aprovacao', linha.status_aprovacao,
        'criado_em', linha.criado_em,
        'pelo_tablet', linha.pelo_tablet,
        'gerado_por_hh', linha.gerado_por_hh
      ) order by linha.criado_em)
      from do_dia as linha
      where linha.os_id = p_os_id
    ), '[]'::jsonb),
    'subtotal_os_horas', coalesce((select sum(linha.horas) from do_dia as linha where linha.os_id = p_os_id), 0),
    'total_dia_horas', coalesce((select sum(linha.horas) from do_dia as linha), 0),
    'outras_os_dia', coalesce((
      select jsonb_agg(jsonb_build_object('os_id', resumo.os_id, 'numero_os', resumo.numero_os, 'horas', resumo.horas) order by resumo.numero_os)
      from (
        select linha.os_id, min(linha.numero_os) as numero_os, sum(linha.horas) as horas
        from do_dia as linha
        where linha.os_id <> p_os_id
        group by linha.os_id
      ) as resumo
    ), '[]'::jsonb)
  );
$$;

-- Registra um PIN errado e decide o bloqueio: 5 erros seguidos (dentro de 15
-- minutos) bloqueiam por 5 minutos; cada erro a mais dobra, ate 40 minutos.
create or replace function public.fn_tablet_registrar_falha(p_dispositivo_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_falhas integer;
  v_bloqueado_ate timestamptz;
begin
  insert into public.tablet_pin_tentativas (dispositivo_id, falhas_consecutivas, ultima_falha_em, total_falhas)
  values (p_dispositivo_id, 1, now(), 1)
  on conflict (dispositivo_id) do update
    set falhas_consecutivas = case
          when tablet_pin_tentativas.ultima_falha_em is null
            or tablet_pin_tentativas.ultima_falha_em < now() - interval '15 minutes'
          then 1
          else tablet_pin_tentativas.falhas_consecutivas + 1
        end,
        ultima_falha_em = now(),
        total_falhas = tablet_pin_tentativas.total_falhas + 1
  returning falhas_consecutivas into v_falhas;

  if v_falhas >= 5 then
    v_bloqueado_ate := now() + make_interval(mins => 5 * power(2, least(v_falhas - 5, 3))::integer);
    update public.tablet_pin_tentativas
       set bloqueado_ate = v_bloqueado_ate
     where dispositivo_id = p_dispositivo_id;
  end if;

  return jsonb_build_object(
    'falhas', v_falhas,
    'tentativas_restantes', greatest(5 - v_falhas, 0),
    'bloqueado_ate', v_bloqueado_ate
  );
end;
$function$;

-- 3. RPCs do tablet -------------------------------------------------------------

-- Toda sessao do app chama isto ao abrir: {tablet:false} para gente normal,
-- {tablet:true, ...} para a conta autorizada. Nunca levanta excecao.
create or replace function public.app_tablet_contexto()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'c'
set row_security to 'off'
as $function$
declare
  v_dispositivo public.tablet_dispositivos := public.fn_tablet_dispositivo_atual();
  v_empresa_nome text;
begin
  if v_dispositivo.id is null then
    return jsonb_build_object('tablet', false);
  end if;

  select coalesce(nullif(btrim(empresa.nome_fantasia), ''), empresa.razao_social)
    into v_empresa_nome
  from c.empresa as empresa
  where empresa.id = v_dispositivo.empresa_id
    and empresa.tenant_id = v_dispositivo.tenant_id;

  return jsonb_build_object(
    'tablet', true,
    'dispositivo_id', v_dispositivo.id,
    'dispositivo_nome', v_dispositivo.nome,
    'empresa_nome', coalesce(v_empresa_nome, 'Empresa'),
    'inatividade_segundos', v_dispositivo.inatividade_segundos,
    'hoje', public.fn_tablet_data_hoje(),
    'fuso', 'America/Sao_Paulo'
  );
end;
$function$;

-- PIN -> sessao. Nunca diz qual colaborador tem o PIN errado; conta as falhas
-- por aparelho; nao registra o PIN em lugar nenhum.
create or replace function public.app_tablet_identificar(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $function$
declare
  v_dispositivo public.tablet_dispositivos := public.fn_tablet_dispositivo_atual();
  v_pin text := btrim(coalesce(p_pin, ''));
  v_bloqueado_ate timestamptz;
  v_candidatos uuid[];
  v_colaborador_id uuid;
  v_colaborador_nome text;
  v_falha jsonb;
  v_token text;
  v_sessao public.tablet_sessoes;
begin
  if v_dispositivo.id is null then
    return public.fn_tablet_erro('tablet_nao_autorizado', 'Este aparelho não está autorizado como tablet de apontamento.');
  end if;

  select tentativa.bloqueado_ate
    into v_bloqueado_ate
  from public.tablet_pin_tentativas as tentativa
  where tentativa.dispositivo_id = v_dispositivo.id;

  if v_bloqueado_ate is not null and v_bloqueado_ate > now() then
    return public.fn_tablet_erro('bloqueado',
      format('Muitas tentativas. Aguarde %s minuto(s) para tentar de novo.',
        greatest(ceil(extract(epoch from (v_bloqueado_ate - now())) / 60)::integer, 1)))
      || jsonb_build_object('bloqueado_ate', v_bloqueado_ate);
  end if;

  if v_pin !~ '^[0-9]{4}$' then
    return public.fn_tablet_erro('pin_invalido', 'O PIN tem exatamente 4 números.');
  end if;

  -- So colaboradores ativos da empresa do tablet entram na comparacao.
  select array_agg(colaborador.id)
    into v_candidatos
  from public.colaboradores_pin as pin
  join public.colaboradores as colaborador
    on colaborador.id = pin.colaborador_id
   and colaborador.tenant_id = pin.tenant_id
   and colaborador.empresa_id = pin.empresa_id
   and colaborador.ativo
  where pin.tenant_id = v_dispositivo.tenant_id
    and pin.empresa_id = v_dispositivo.empresa_id
    and pin.pin_hash = extensions.crypt(v_pin, pin.pin_hash);

  if coalesce(cardinality(v_candidatos), 0) <> 1 then
    v_falha := public.fn_tablet_registrar_falha(v_dispositivo.id);
    if coalesce(cardinality(v_candidatos), 0) > 1 then
      return public.fn_tablet_erro('pin_ambiguo', 'Este PIN está em uso por mais de uma pessoa. Procure a coordenação.') || v_falha;
    end if;
    if (v_falha ->> 'bloqueado_ate') is not null then
      return public.fn_tablet_erro('bloqueado',
        format('PIN não reconhecido. Muitas tentativas: aguarde %s minuto(s) para tentar de novo.',
          greatest(ceil(extract(epoch from ((v_falha ->> 'bloqueado_ate')::timestamptz - now())) / 60)::integer, 1))) || v_falha;
    end if;
    return public.fn_tablet_erro('pin_nao_reconhecido',
      format('PIN não reconhecido. %s tentativa(s) restante(s).', v_falha ->> 'tentativas_restantes')) || v_falha;
  end if;

  v_colaborador_id := v_candidatos[1];
  select colaborador.nome into v_colaborador_nome
  from public.colaboradores as colaborador
  where colaborador.id = v_colaborador_id;

  -- PIN certo: zera o contador do aparelho e derruba qualquer sessao anterior
  -- que tenha ficado aberta (a pessoa anterior nao finalizou, por exemplo).
  delete from public.tablet_pin_tentativas where dispositivo_id = v_dispositivo.id;
  update public.tablet_sessoes
     set encerrada_em = now(), encerrada_motivo = 'nova_identificacao'
   where dispositivo_id = v_dispositivo.id
     and encerrada_em is null;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.tablet_sessoes (tenant_id, empresa_id, dispositivo_id, colaborador_id, token_hash, expira_em)
  values (
    v_dispositivo.tenant_id, v_dispositivo.empresa_id, v_dispositivo.id, v_colaborador_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    now() + interval '10 minutes'
  )
  returning * into v_sessao;

  return jsonb_build_object(
    'sucesso', true,
    'sessao_token', v_token,
    'sessao_id', v_sessao.id,
    'colaborador_id', v_colaborador_id,
    'colaborador_nome', v_colaborador_nome,
    'expira_em', v_sessao.expira_em,
    'hoje', public.fn_tablet_data_hoje(),
    'erros', '[]'::jsonb,
    'avisos', '[]'::jsonb
  );
end;
$function$;

-- Finalizar / trocar de colaborador / inatividade: invalida o token. Idempotente.
create or replace function public.app_tablet_encerrar(p_sessao_token text, p_motivo text default 'finalizado')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $function$
declare
  v_dispositivo public.tablet_dispositivos := public.fn_tablet_dispositivo_atual();
  v_motivo text := case
    when lower(coalesce(p_motivo, '')) in ('finalizado', 'inatividade', 'troca', 'cancelado') then lower(p_motivo)
    else 'finalizado'
  end;
  v_encerradas integer := 0;
begin
  if v_dispositivo.id is null or nullif(btrim(coalesce(p_sessao_token, '')), '') is null then
    return jsonb_build_object('sucesso', true, 'encerradas', 0);
  end if;

  update public.tablet_sessoes
     set encerrada_em = now(), encerrada_motivo = v_motivo
   where dispositivo_id = v_dispositivo.id
     and token_hash = encode(extensions.digest(btrim(p_sessao_token), 'sha256'), 'hex')
     and encerrada_em is null;
  get diagnostics v_encerradas = row_count;

  return jsonb_build_object('sucesso', true, 'encerradas', v_encerradas);
end;
$function$;

-- Lancamentos do colaborador identificado na OS e na data, mais o total do dia.
-- Tambem devolve a situacao da OS, para a tela saber se ela fechou no meio.
create or replace function public.app_tablet_apontamentos_do_dia(p_sessao_token text, p_os_id integer, p_data date)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $function$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
  v_os jsonb;
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;
  if p_os_id is null or p_data is null then
    return public.fn_tablet_erro('parametros', 'Informe a OS e a data.');
  end if;

  v_os := public.fn_tablet_os_situacao(v_sessao.tenant_id, v_sessao.empresa_id, p_os_id);
  if not coalesce((v_os ->> 'encontrada')::boolean, false) then
    return public.fn_tablet_erro('os', v_os ->> 'motivo_bloqueio');
  end if;

  return jsonb_build_object(
    'sucesso', true,
    'os', v_os,
    'data', p_data,
    'hoje', public.fn_tablet_data_hoje(),
    'colaborador_id', v_sessao.colaborador_id,
    'erros', '[]'::jsonb,
    'avisos', '[]'::jsonb
  ) || public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_os_id, p_data);
end;
$function$;

-- O lancamento. Duracao em horas + minutos (3h30 = p_horas 3, p_minutos 30),
-- gravada em apontamentos_horas.horas como decimal (3.50), que e o formato de
-- sempre. p_chave e a chave de idempotencia gerada pela tela: reenviar a mesma
-- chave (toque repetido, rede que caiu depois de gravar) devolve o resultado
-- ja gravado em vez de criar outra linha.
create or replace function public.app_tablet_lancar_horas(
  p_sessao_token text,
  p_os_id integer,
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
as $function$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
  v_hoje date := public.fn_tablet_data_hoje();
  v_repetido public.tablet_lancamentos;
  v_colaborador_nome text;
  v_colaborador_ativo boolean;
  v_os jsonb;
  v_minutos integer;
  v_horas numeric;
  v_tipo_hora_id uuid;
  v_tipo_hora_nome text;
  v_total_dia numeric;
  v_avisos jsonb := '[]'::jsonb;
  v_apontamento_id uuid;
  v_resultado jsonb;
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;

  if p_chave is null then
    return public.fn_tablet_erro('chave', 'Chave de envio ausente. Tente novamente.');
  end if;

  -- Reenvio da mesma chave: devolve o que ja foi gravado, com o resumo atual.
  select lancamento.*
    into v_repetido
  from public.tablet_lancamentos as lancamento
  join public.tablet_sessoes as sessao on sessao.id = lancamento.sessao_id
  where lancamento.chave = p_chave
    and sessao.dispositivo_id = v_sessao.dispositivo_id
    and sessao.colaborador_id = v_sessao.colaborador_id;
  if found then
    return (v_repetido.resultado - 'resumo')
      || jsonb_build_object(
           'repetido', true,
           'resumo', public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id,
                       (v_repetido.resultado ->> 'os_id')::integer, (v_repetido.resultado ->> 'data')::date)
         );
  end if;

  select colaborador.nome, colaborador.ativo
    into v_colaborador_nome, v_colaborador_ativo
  from public.colaboradores as colaborador
  where colaborador.id = v_sessao.colaborador_id
    and colaborador.tenant_id = v_sessao.tenant_id
    and colaborador.empresa_id = v_sessao.empresa_id;
  if not found or not coalesce(v_colaborador_ativo, false) then
    update public.tablet_sessoes set encerrada_em = now(), encerrada_motivo = 'colaborador_inativo' where id = v_sessao.id;
    return public.fn_tablet_erro('colaborador_inativo', 'Seu cadastro de colaborador está inativo. Procure a coordenação.');
  end if;

  if p_data is null then
    return public.fn_tablet_erro('data', 'Informe a data do trabalho.');
  elsif p_data > v_hoje then
    return public.fn_tablet_erro('data_futura', 'Não é permitido lançar horas em data futura.');
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

  v_os := public.fn_tablet_os_situacao(v_sessao.tenant_id, v_sessao.empresa_id, p_os_id);
  if not coalesce((v_os ->> 'encontrada')::boolean, false) then
    return public.fn_tablet_erro('os', v_os ->> 'motivo_bloqueio');
  end if;
  -- Colaborador comum so lanca em OS aberta. Se ela fechou enquanto a pessoa
  -- preenchia, para aqui: o caminho para OS encerrada e o da coordenacao.
  if not coalesce((v_os ->> 'pode_lancar')::boolean, false) then
    return public.fn_tablet_erro('os_encerrada', v_os ->> 'motivo_bloqueio') || jsonb_build_object('os', v_os);
  end if;

  if not exists (
    select 1
    from public.colaborador_taxas as taxa
    where taxa.colaborador_id = v_sessao.colaborador_id
      and taxa.tenant_id = v_sessao.tenant_id
      and taxa.empresa_id = v_sessao.empresa_id
      and p_data >= taxa.vigencia_inicio
      and (taxa.vigencia_fim is null or p_data <= taxa.vigencia_fim)
  ) then
    return public.fn_tablet_erro('taxa_vigente',
      format('%s não possui taxa vigente em %s. Procure a coordenação.', v_colaborador_nome, to_char(p_data, 'DD/MM/YYYY')));
  end if;

  -- Tipo de hora: o tablet nao pergunta; entra como "Hora normal" (o mesmo
  -- padrao do app). Sabado, domingo ou feriado ficam para a coordenacao ajustar.
  select tipo.id, tipo.descricao
    into v_tipo_hora_id, v_tipo_hora_nome
  from public.tipos_horas as tipo
  where tipo.tenant_id = v_sessao.tenant_id
    and tipo.ativo
  order by (upper(coalesce(tipo.codigo, '')) = 'NORMAL') desc,
           (lower(tipo.descricao) like 'hora normal%') desc,
           (tipo.fator = 1) desc,
           tipo.descricao
  limit 1;
  if v_tipo_hora_id is null then
    return public.fn_tablet_erro('tipo_hora', 'Nenhum tipo de hora ativo está cadastrado. Procure a coordenação.');
  end if;

  -- Mesmos avisos do app: retroativo (> 7 dias) e jornada acima de 9 h no dia.
  if p_data < v_hoje - 7 then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('tipo', 'retroativo',
      'mensagem', format('Este apontamento é retroativo: a data %s tem mais de 7 dias.', to_char(p_data, 'DD/MM/YYYY'))));
  end if;
  select coalesce(sum(apontamento.horas), 0)
    into v_total_dia
  from public.apontamentos_horas as apontamento
  where apontamento.tenant_id = v_sessao.tenant_id
    and apontamento.empresa_id = v_sessao.empresa_id
    and apontamento.colaborador_id = v_sessao.colaborador_id
    and apontamento.data = p_data;
  if v_total_dia + v_horas > 9 then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('tipo', 'jornada_maior_que_9h',
      'mensagem', format('Você ficará com %s h apontadas em %s. Verifique se o intervalo de almoço foi descontado.',
        replace((v_total_dia + v_horas)::text, '.', ','), to_char(p_data, 'DD/MM/YYYY'))));
  end if;
  if jsonb_array_length(v_avisos) > 0 and not p_confirmar_avisos then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', '[]'::jsonb);
  end if;

  begin
    insert into public.apontamentos_horas (
      os_id, colaborador_id, data, horas, tipo_hora_id, descricao, status,
      tenant_id, empresa_id, gerado_por_hh, criado_por_user_id, tablet_sessao_id
    ) values (
      p_os_id, v_sessao.colaborador_id, p_data, v_horas, v_tipo_hora_id, null, 'lancado',
      v_sessao.tenant_id, v_sessao.empresa_id, false, auth.uid(), v_sessao.id
    )
    returning id into v_apontamento_id;

    v_resultado := jsonb_build_object(
      'sucesso', true,
      'gravados', 1,
      'apontamento_id', v_apontamento_id,
      'os_id', p_os_id,
      'data', p_data,
      'horas', v_horas,
      'minutos', v_minutos,
      'tipo_hora', v_tipo_hora_nome,
      'colaborador_id', v_sessao.colaborador_id,
      'colaborador_nome', v_colaborador_nome,
      'avisos', v_avisos,
      'erros', '[]'::jsonb
    );

    insert into public.tablet_lancamentos (chave, sessao_id, apontamento_id, resultado)
    values (p_chave, v_sessao.id, v_apontamento_id, v_resultado);
  exception
    when unique_violation then
      -- Dois envios da mesma chave chegaram juntos: o segundo perde e devolve o
      -- que o primeiro gravou.
      select lancamento.* into v_repetido from public.tablet_lancamentos as lancamento where lancamento.chave = p_chave;
      if v_repetido.chave is not null then
        return (v_repetido.resultado - 'resumo') || jsonb_build_object('repetido', true,
          'resumo', public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_os_id, p_data));
      end if;
      return public.fn_tablet_erro('banco', sqlerrm);
    when others then
      -- Triggers do apontamento (competencia fechada, taxa, OS fora de andamento)
      -- falam portugues: a mensagem vai direto para a tela.
      return public.fn_tablet_erro('banco', sqlerrm);
  end;

  return v_resultado || jsonb_build_object(
    'resumo', public.fn_tablet_resumo_dia(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, p_os_id, p_data)
  );
end;
$function$;

-- 4. Administracao (sistema web) ---------------------------------------------

-- PIN e assunto de quem gerencia hora: a mesma hierarquia de
-- fn_usuario_pode_alterar_apontamento (Admin, Diretor, Coordenacao).
create or replace function public.fn_tablet_contexto_admin(p_papeis text[])
returns table (tenant_id uuid, empresa_id uuid, papel text)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  v_papel := coalesce(a.fn_current_empresa_papel(v_tenant_id, v_empresa_id), '');
  if not (v_papel = any (p_papeis)) then
    raise exception 'Seu perfil não pode administrar o tablet de apontamento.';
  end if;
  tenant_id := v_tenant_id;
  empresa_id := v_empresa_id;
  papel := v_papel;
  return next;
end;
$function$;

create or replace function public.web_tablet_pins_listar()
returns table (colaborador_id uuid, definido_em timestamptz, definido_por_nome text)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR', 'COORDENACAO']);
  return query
  select pin.colaborador_id,
         pin.definido_em,
         coalesce(nullif(btrim(usuario.nome), ''), nullif(btrim(usuario.email), ''))::text
  from public.colaboradores_pin as pin
  left join a.usuario as usuario on usuario.auth_user_id = pin.definido_por_user_id
  where pin.tenant_id = v_ctx.tenant_id
    and pin.empresa_id = v_ctx.empresa_id;
end;
$function$;

create or replace function public.web_tablet_pin_definir(p_colaborador_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_pin text := btrim(coalesce(p_pin, ''));
  v_colaborador_nome text;
  v_colaborador_ativo boolean;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR', 'COORDENACAO']);

  if v_pin !~ '^[0-9]{4}$' then
    return public.fn_tablet_erro('pin_invalido', 'O PIN precisa ter exatamente 4 números.');
  end if;

  select colaborador.nome, colaborador.ativo
    into v_colaborador_nome, v_colaborador_ativo
  from public.colaboradores as colaborador
  where colaborador.id = p_colaborador_id
    and colaborador.tenant_id = v_ctx.tenant_id
    and colaborador.empresa_id = v_ctx.empresa_id;
  if not found then
    return public.fn_tablet_erro('colaborador', 'Colaborador não encontrado nesta empresa.');
  end if;
  if not coalesce(v_colaborador_ativo, false) then
    return public.fn_tablet_erro('colaborador_inativo', 'Ative o colaborador antes de definir o PIN.');
  end if;

  -- O PIN identifica uma unica pessoa na empresa, sem escolher nome antes.
  -- Inativos tambem contam: se voltarem, o PIN deles nao pode colidir.
  if exists (
    select 1
    from public.colaboradores_pin as pin
    where pin.tenant_id = v_ctx.tenant_id
      and pin.empresa_id = v_ctx.empresa_id
      and pin.colaborador_id <> p_colaborador_id
      and pin.pin_hash = extensions.crypt(v_pin, pin.pin_hash)
  ) then
    return public.fn_tablet_erro('pin_em_uso', 'Este PIN já está em uso por outro colaborador. Escolha outro.');
  end if;

  insert into public.colaboradores_pin (colaborador_id, tenant_id, empresa_id, pin_hash, definido_em, definido_por_user_id)
  values (p_colaborador_id, v_ctx.tenant_id, v_ctx.empresa_id, extensions.crypt(v_pin, extensions.gen_salt('bf', 6)), now(), auth.uid())
  on conflict (colaborador_id) do update
    set pin_hash = excluded.pin_hash,
        definido_em = now(),
        definido_por_user_id = auth.uid();

  -- PIN novo derruba a identificacao antiga que porventura esteja aberta.
  update public.tablet_sessoes
     set encerrada_em = now(), encerrada_motivo = 'pin_redefinido'
   where colaborador_id = p_colaborador_id
     and encerrada_em is null;

  return jsonb_build_object('sucesso', true, 'colaborador_nome', v_colaborador_nome, 'definido_em', now());
end;
$function$;

create or replace function public.web_tablet_pin_remover(p_colaborador_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR', 'COORDENACAO']);

  delete from public.colaboradores_pin
  where colaborador_id = p_colaborador_id
    and tenant_id = v_ctx.tenant_id
    and empresa_id = v_ctx.empresa_id;

  update public.tablet_sessoes
     set encerrada_em = now(), encerrada_motivo = 'pin_removido'
   where colaborador_id = p_colaborador_id
     and encerrada_em is null;

  return jsonb_build_object('sucesso', true);
end;
$function$;

-- Contas que podem virar tablet: APONTADOR na empresa e sem colaborador
-- vinculado (a conta e do aparelho, nao de uma pessoa).
create or replace function public.web_tablet_contas_elegiveis()
returns table (auth_user_id uuid, nome text, email text, ja_autorizado boolean)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);
  return query
  select usuario.auth_user_id,
         coalesce(nullif(btrim(usuario.nome), ''), usuario.email)::text,
         usuario.email::text,
         exists (select 1 from public.tablet_dispositivos as dispositivo where dispositivo.auth_user_id = usuario.auth_user_id)
  from a.usuario as usuario
  join a.usuario_empresa as vinculo
    on vinculo.usuario_id = usuario.id
   and vinculo.empresa_id = v_ctx.empresa_id
   and vinculo.ativo
   and vinculo.deleted_at is null
  where usuario.ativo
    and usuario.deleted_at is null
    and usuario.auth_user_id is not null
    and upper(coalesce(vinculo.papel, '')) = 'APONTADOR'
    and not exists (
      select 1 from public.colaboradores as colaborador
      where colaborador.user_id = usuario.auth_user_id
    )
  order by 2;
end;
$function$;

create or replace function public.web_tablet_listar()
returns table (
  id uuid,
  nome text,
  auth_user_id uuid,
  usuario_nome text,
  usuario_email text,
  inatividade_segundos integer,
  ativo boolean,
  criado_em timestamptz,
  ultima_identificacao_em timestamptz,
  identificacoes_hoje integer
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);
  return query
  select dispositivo.id,
         dispositivo.nome,
         dispositivo.auth_user_id,
         coalesce(nullif(btrim(usuario.nome), ''), usuario.email)::text,
         usuario.email::text,
         dispositivo.inatividade_segundos,
         dispositivo.ativo,
         dispositivo.criado_em,
         (select max(sessao.criado_em) from public.tablet_sessoes as sessao where sessao.dispositivo_id = dispositivo.id),
         (select count(*)::integer from public.tablet_sessoes as sessao
           where sessao.dispositivo_id = dispositivo.id
             and (sessao.criado_em at time zone 'America/Sao_Paulo')::date = public.fn_tablet_data_hoje())
  from public.tablet_dispositivos as dispositivo
  left join a.usuario as usuario on usuario.auth_user_id = dispositivo.auth_user_id
  where dispositivo.tenant_id = v_ctx.tenant_id
    and dispositivo.empresa_id = v_ctx.empresa_id
  order by dispositivo.ativo desc, dispositivo.nome;
end;
$function$;

create or replace function public.web_tablet_salvar(
  p_auth_user_id uuid,
  p_nome text,
  p_inatividade_segundos integer default 60,
  p_ativo boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_ctx record;
  v_nome text := btrim(coalesce(p_nome, ''));
  v_papel text;
  v_id uuid;
begin
  select * into v_ctx from public.fn_tablet_contexto_admin(array['ADMIN', 'DIRETOR']);

  if char_length(v_nome) < 2 or char_length(v_nome) > 80 then
    return public.fn_tablet_erro('nome', 'Dê um nome ao tablet com 2 a 80 caracteres (ex.: Tablet da produção).');
  end if;
  if p_inatividade_segundos is null or p_inatividade_segundos < 15 or p_inatividade_segundos > 900 then
    return public.fn_tablet_erro('inatividade', 'O tempo de inatividade precisa ficar entre 15 e 900 segundos.');
  end if;

  select upper(coalesce(vinculo.papel, ''))
    into v_papel
  from a.usuario as usuario
  join a.usuario_empresa as vinculo
    on vinculo.usuario_id = usuario.id
   and vinculo.empresa_id = v_ctx.empresa_id
   and vinculo.ativo
   and vinculo.deleted_at is null
  where usuario.auth_user_id = p_auth_user_id
    and usuario.ativo
    and usuario.deleted_at is null
  limit 1;
  if v_papel is null then
    return public.fn_tablet_erro('conta', 'A conta informada não está ativa nesta empresa.');
  end if;
  if v_papel <> 'APONTADOR' then
    return public.fn_tablet_erro('conta_papel', 'A conta do tablet precisa ter o perfil Apontador nesta empresa.');
  end if;
  if exists (select 1 from public.colaboradores as colaborador where colaborador.user_id = p_auth_user_id) then
    return public.fn_tablet_erro('conta_vinculada', 'A conta do tablet não pode estar vinculada a um colaborador: ela é do aparelho, não de uma pessoa.');
  end if;

  insert into public.tablet_dispositivos (tenant_id, empresa_id, auth_user_id, nome, inatividade_segundos, ativo, criado_por_user_id, atualizado_por_user_id)
  values (v_ctx.tenant_id, v_ctx.empresa_id, p_auth_user_id, v_nome, p_inatividade_segundos, coalesce(p_ativo, true), auth.uid(), auth.uid())
  on conflict (auth_user_id) do update
    set nome = excluded.nome,
        inatividade_segundos = excluded.inatividade_segundos,
        ativo = excluded.ativo,
        atualizado_em = now(),
        atualizado_por_user_id = auth.uid()
    where tablet_dispositivos.tenant_id = excluded.tenant_id
      and tablet_dispositivos.empresa_id = excluded.empresa_id
  returning id into v_id;

  if v_id is null then
    return public.fn_tablet_erro('conta_outra_empresa', 'Esta conta já é tablet de outra empresa.');
  end if;

  if not coalesce(p_ativo, true) then
    update public.tablet_sessoes
       set encerrada_em = now(), encerrada_motivo = 'tablet_desativado'
     where dispositivo_id = v_id
       and encerrada_em is null;
  end if;

  return jsonb_build_object('sucesso', true, 'id', v_id);
end;
$function$;

-- 5. Grants -------------------------------------------------------------------

revoke all on function public.fn_tablet_data_hoje() from public, anon, authenticated;
revoke all on function public.fn_tablet_dispositivo_atual() from public, anon, authenticated;
revoke all on function public.fn_tablet_validar_sessao(text) from public, anon, authenticated;
revoke all on function public.fn_tablet_erro(text, text) from public, anon, authenticated;
revoke all on function public.fn_tablet_erro_sessao() from public, anon, authenticated;
revoke all on function public.fn_tablet_os_situacao(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.fn_tablet_resumo_dia(uuid, uuid, uuid, integer, date) from public, anon, authenticated;
revoke all on function public.fn_tablet_registrar_falha(uuid) from public, anon, authenticated;
revoke all on function public.fn_tablet_contexto_admin(text[]) from public, anon, authenticated;

revoke all on function public.app_tablet_contexto() from public, anon;
revoke all on function public.app_tablet_identificar(text) from public, anon;
revoke all on function public.app_tablet_encerrar(text, text) from public, anon;
revoke all on function public.app_tablet_apontamentos_do_dia(text, integer, date) from public, anon;
revoke all on function public.app_tablet_lancar_horas(text, integer, date, integer, integer, uuid, boolean) from public, anon;
revoke all on function public.web_tablet_pins_listar() from public, anon;
revoke all on function public.web_tablet_pin_definir(uuid, text) from public, anon;
revoke all on function public.web_tablet_pin_remover(uuid) from public, anon;
revoke all on function public.web_tablet_contas_elegiveis() from public, anon;
revoke all on function public.web_tablet_listar() from public, anon;
revoke all on function public.web_tablet_salvar(uuid, text, integer, boolean) from public, anon;

grant execute on function public.app_tablet_contexto() to authenticated;
grant execute on function public.app_tablet_identificar(text) to authenticated;
grant execute on function public.app_tablet_encerrar(text, text) to authenticated;
grant execute on function public.app_tablet_apontamentos_do_dia(text, integer, date) to authenticated;
grant execute on function public.app_tablet_lancar_horas(text, integer, date, integer, integer, uuid, boolean) to authenticated;
grant execute on function public.web_tablet_pins_listar() to authenticated;
grant execute on function public.web_tablet_pin_definir(uuid, text) to authenticated;
grant execute on function public.web_tablet_pin_remover(uuid) to authenticated;
grant execute on function public.web_tablet_contas_elegiveis() to authenticated;
grant execute on function public.web_tablet_listar() to authenticated;
grant execute on function public.web_tablet_salvar(uuid, text, integer, boolean) to authenticated;

-- 6. OS encerrada no web: so coordenacao para cima ou responsavel da OS --------
-- O corpo da funcao segue identico; a troca e feita sobre a definicao instalada,
-- como nas migrations anteriores.

do $patch_web_criar$
declare
  v_definition text;
  v_needle text := $needle$
    elsif v_status_fluxo in ('concluida', 'faturada', 'concluida_garantia') and v_confirmar_os_encerrada then
      perform set_config('app.apontamento_permite_os_encerrada', 'on', true);
$needle$;
  v_replacement text := $replacement$
    elsif v_status_fluxo in ('concluida', 'faturada', 'concluida_garantia') and v_confirmar_os_encerrada then
      -- Hora em OS encerrada e excecao de quem gerencia hora (mesma hierarquia
      -- de fn_usuario_pode_alterar_apontamento) ou do responsavel da OS.
      if upper(coalesce(v_papel, '')) not in ('ADMIN', 'DIRETOR', 'COORDENACAO')
         and not exists (
           select 1
           from public.ordens_servico as ordem
           where ordem.id = v_os_id
             and ordem.tenant_id = v_tenant_id
             and ordem.empresa_id = v_empresa_id
             and ordem.responsavel_aprovacao_id = v_auth_uid
         ) then
        raise exception 'A OS % está encerrada: somente Coordenação, Diretor, Admin ou o responsável da OS pode lançar horas nela.', v_os_id;
      end if;
      perform set_config('app.apontamento_permite_os_encerrada', 'on', true);
$replacement$;
begin
  select pg_get_functiondef('public.web_criar_apontamentos_horas(jsonb)'::regprocedure)
    into v_definition;

  if position('responsavel_aprovacao_id = v_auth_uid' in v_definition) > 0 then
    return; -- ja aplicado
  end if;
  if position(v_needle in v_definition) = 0 then
    raise exception 'web_criar_apontamentos_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_web_criar$;

-- 7. Editar apontamento: duplicidade so quando o tipo de hora muda ------------

do $patch_editar$
declare
  v_definition text;
  v_needle text := $needle$
      and apontamento.tipo_hora_id = p_tipo_hora_id
      and not coalesce(apontamento.gerado_por_hh, false)
  ) then
$needle$;
  v_replacement text := $replacement$
      and apontamento.tipo_hora_id = p_tipo_hora_id
      and not coalesce(apontamento.gerado_por_hh, false)
  ) and p_tipo_hora_id is distinct from v_tipo_hora_antes then
$replacement$;
begin
  select pg_get_functiondef('public.app_editar_apontamento(uuid,numeric,uuid,text,boolean,text)'::regprocedure)
    into v_definition;

  if position('p_tipo_hora_id is distinct from v_tipo_hora_antes' in v_definition) > 0 then
    return; -- ja aplicado
  end if;
  if position(v_needle in v_definition) = 0 then
    raise exception 'editar_apontamento_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_editar$;

-- 8. Conferencia --------------------------------------------------------------

do $assertions$
declare
  v_web_criar text := pg_get_functiondef('public.web_criar_apontamentos_horas(jsonb)'::regprocedure);
  v_editar text := pg_get_functiondef('public.app_editar_apontamento(uuid,numeric,uuid,text,boolean,text)'::regprocedure);
  v_acl text;
begin
  if to_regclass('public.tablet_dispositivos') is null
     or to_regclass('public.colaboradores_pin') is null
     or to_regclass('public.tablet_sessoes') is null
     or to_regclass('public.tablet_lancamentos') is null
     or to_regclass('public.tablet_pin_tentativas') is null then
    raise exception 'tabelas_tablet_ausentes';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'apontamentos_horas' and column_name = 'tablet_sessao_id'
  ) then
    raise exception 'coluna_tablet_sessao_id_ausente';
  end if;

  if position('responsavel_aprovacao_id = v_auth_uid' in v_web_criar) = 0 then
    raise exception 'web_criar_apontamentos_patch_invalido';
  end if;

  if position('p_tipo_hora_id is distinct from v_tipo_hora_antes' in v_editar) = 0 then
    raise exception 'editar_apontamento_patch_invalido';
  end if;

  for v_acl in
    select coalesce(p.proacl::text, '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'app\_tablet\_%'
  loop
    if v_acl like '%anon=%' or v_acl like '{=X%' then
      raise exception 'grant_tablet_aberto: %', v_acl;
    end if;
  end loop;

  -- pgcrypto precisa estar em extensions para crypt/gen_salt/digest.
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'extensions' and p.proname = 'gen_salt'
  ) then
    raise exception 'pgcrypto_ausente_em_extensions';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
