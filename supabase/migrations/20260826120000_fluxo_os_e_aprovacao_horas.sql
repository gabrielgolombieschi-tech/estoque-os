begin;

-- Frente 01 + 03. A estrutura legada permanece intacta: status da OS e do
-- apontamento continuam atendendo as telas e integrações existentes.
alter table public.ordens_servico
  add column if not exists status_fluxo text,
  add column if not exists faturado_em timestamptz,
  add column if not exists faturada_presumida_legado boolean not null default false,
  add column if not exists garantia_motivo text,
  add column if not exists garantia_reaberta_em timestamptz;

alter table public.ordens_servico
  drop constraint if exists chk_ordens_servico_status_fluxo;

alter table public.ordens_servico
  add constraint chk_ordens_servico_status_fluxo
  check (
    status_fluxo is null
    or status_fluxo in (
      'em_andamento',
      'concluida',
      'faturada',
      'em_andamento_garantia',
      'concluida_garantia'
    )
  );

create table if not exists public.ordens_servico_fluxo_eventos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  os_id integer not null references public.ordens_servico(id) on delete cascade,
  evento text not null,
  status_origem text,
  status_destino text,
  motivo text,
  realizado_por uuid references auth.users(id),
  criado_em timestamptz not null default now()
);

create index if not exists idx_os_fluxo_tenant_empresa_status
  on public.ordens_servico (tenant_id, empresa_id, status_fluxo);
create index if not exists idx_os_fluxo_eventos_os
  on public.ordens_servico_fluxo_eventos (os_id, criado_em desc);

alter table public.apontamentos_horas
  add column if not exists status_aprovacao text,
  add column if not exists pendente_em timestamptz,
  add column if not exists aprovado_automaticamente_em timestamptz,
  add column if not exists rejeitado_em timestamptz;

-- Todo o histórico fica definitivo, sem inventar data/usuário de aprovação.
update public.apontamentos_horas
set status_aprovacao = 'aprovado'
where status_aprovacao is null;

alter table public.apontamentos_horas
  alter column status_aprovacao set default 'pendente',
  alter column status_aprovacao set not null;

alter table public.apontamentos_horas
  drop constraint if exists chk_apontamentos_horas_status_aprovacao;

alter table public.apontamentos_horas
  add constraint chk_apontamentos_horas_status_aprovacao
  check (status_aprovacao in ('pendente', 'aprovado', 'rejeitado'));

create table if not exists public.apontamentos_horas_aprovacao_eventos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  apontamento_id uuid not null references public.apontamentos_horas(id) on delete cascade,
  evento text not null,
  realizado_por uuid references auth.users(id),
  motivo text,
  criado_em timestamptz not null default now()
);

create index if not exists idx_apontamentos_aprovacao_fila
  on public.apontamentos_horas (tenant_id, empresa_id, status_aprovacao, pendente_em)
  where status_aprovacao = 'pendente';
create index if not exists idx_apontamentos_aprovacao_eventos_apontamento
  on public.apontamentos_horas_aprovacao_eventos (apontamento_id, criado_em desc);

create or replace function public.mapear_status_legado_para_fluxo(p_status text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case lower(coalesce(p_status, ''))
    when 'em_andamento' then 'em_andamento'
    when 'concluida' then 'faturada'
    else null
  end;
$$;

-- Regra de classificação histórica aprovada em 26/08/2026:
-- cancelada fica fora; andamento segue andamento; toda concluída vira faturada,
-- distinguindo a nota real da faturada presumida de legado.
with notas_emitidas as (
  select
    documento.tenant_id,
    documento.empresa_id,
    documento.os_id_import as os_id,
    min(coalesce(documento.emissao_date, documento.created_at::date))::timestamptz as faturado_em
  from f.documento_fiscal as documento
  where documento.operacao = 'SAIDA'
    and documento.os_id_import is not null
    and documento.deleted_at is null
    and (
      (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
      or (
        upper(coalesce(documento.modelo, '')) <> 'NFSE'
        and (
          nullif(upper(btrim(coalesce(documento.nfe_status, ''))), '') is null
          or upper(coalesce(documento.nfe_status, '')) = 'EMITIDA'
        )
      )
    )
  group by documento.tenant_id, documento.empresa_id, documento.os_id_import
)
update public.ordens_servico as os
set status_fluxo = 'faturada',
    faturada_presumida_legado = nota.os_id is null,
    faturado_em = coalesce(
      nota.faturado_em,
      os.data_conclusao::timestamptz,
      os.atualizado_em::timestamptz,
      now()
    )
from notas_emitidas as nota
where os.status = 'concluida'
  and nota.tenant_id is not distinct from os.tenant_id
  and nota.empresa_id is not distinct from os.empresa_id
  and nota.os_id is not distinct from os.id;

-- O UPDATE acima cobre as concluídas com NF. As demais concluídas são o lote
-- inteiro de faturada presumida/legado, sem fila financeira e sem garantia.
update public.ordens_servico as os
set status_fluxo = 'faturada',
    faturada_presumida_legado = true,
    faturado_em = coalesce(os.data_conclusao::timestamptz, os.atualizado_em::timestamptz, now())
where os.status = 'concluida'
  and os.status_fluxo is null;

update public.ordens_servico
set status_fluxo = 'em_andamento',
    faturada_presumida_legado = false
where status = 'em_andamento';

create or replace function public.fn_ordens_servico_inicializar_status_fluxo()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.status_fluxo is null then
    new.status_fluxo := public.mapear_status_legado_para_fluxo(new.status);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ordens_servico_inicializar_status_fluxo on public.ordens_servico;
create trigger trg_ordens_servico_inicializar_status_fluxo
before insert on public.ordens_servico
for each row execute function public.fn_ordens_servico_inicializar_status_fluxo();

-- O status novo substitui o bloqueio do status legado do apontamento. HH continua
-- livre para o seu sincronismo próprio, mas nasce aprovado no trigger seguinte.
create or replace function public.fn_apontamento_bloquear_fechado()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists trg_apontamento_validar_aprovacao on public.apontamentos_horas;

create or replace function public.fn_apontamento_preparar_aprovacao()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_responsavel uuid;
  v_user_id_colaborador uuid;
  v_editou boolean;
begin
  if tg_op = 'INSERT' then
    new.criado_por_user_id := coalesce(new.criado_por_user_id, auth.uid());

    if coalesce(new.gerado_por_hh, false) then
      new.status_aprovacao := 'aprovado';
      new.pendente_em := null;
      new.aprovado_por := null;
      new.aprovado_em := coalesce(new.aprovado_em, now());
      new.aprovado_automaticamente_em := coalesce(new.aprovado_automaticamente_em, now());
      new.rejeitado_em := null;
      new.motivo_devolucao := null;
      return new;
    end if;

    select os.responsavel_aprovacao_id, colaborador.user_id
      into v_responsavel, v_user_id_colaborador
    from public.ordens_servico as os
    join public.colaboradores as colaborador on colaborador.id = new.colaborador_id
    where os.id = new.os_id
      and os.tenant_id = new.tenant_id
      and os.empresa_id = new.empresa_id;

    if new.criado_por_user_id is not null
       and new.criado_por_user_id = v_responsavel
       and new.criado_por_user_id = v_user_id_colaborador then
      new.status_aprovacao := 'aprovado';
      new.pendente_em := null;
      new.aprovado_por := new.criado_por_user_id;
      new.aprovado_em := coalesce(new.aprovado_em, now());
      new.aprovado_automaticamente_em := null;
      new.rejeitado_em := null;
      new.motivo_devolucao := null;
    else
      new.status_aprovacao := 'pendente';
      new.pendente_em := coalesce(new.pendente_em, now());
      new.aprovado_por := null;
      new.aprovado_em := null;
      new.aprovado_automaticamente_em := null;
      new.rejeitado_em := null;
      new.motivo_devolucao := null;
    end if;
    return new;
  end if;

  if coalesce(new.gerado_por_hh, false) then
    new.status_aprovacao := 'aprovado';
    new.pendente_em := null;
    new.aprovado_por := null;
    new.aprovado_em := coalesce(new.aprovado_em, now());
    new.aprovado_automaticamente_em := coalesce(new.aprovado_automaticamente_em, now());
    new.rejeitado_em := null;
    new.motivo_devolucao := null;
    return new;
  end if;

  v_editou := row(
    new.data, new.horas, new.tipo_hora_id, new.fator_aplicado, new.descricao,
    new.hora_entrada_1, new.hora_saida_1, new.hora_entrada_2, new.hora_saida_2
  ) is distinct from row(
    old.data, old.horas, old.tipo_hora_id, old.fator_aplicado, old.descricao,
    old.hora_entrada_1, old.hora_saida_1, old.hora_entrada_2, old.hora_saida_2
  );

  if v_editou then
    new.status_aprovacao := 'pendente';
    new.pendente_em := now();
    new.aprovado_por := null;
    new.aprovado_em := null;
    new.aprovado_automaticamente_em := null;
    new.rejeitado_em := null;
    new.motivo_devolucao := null;
  end if;

  return new;
end;
$$;

create or replace function public.fn_apontamento_registrar_evento_aprovacao()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_evento text;
  v_motivo text;
begin
  if tg_op = 'INSERT' then
    v_evento := case
      when new.gerado_por_hh then 'aprovado_hh'
      when new.status_aprovacao = 'aprovado' then 'aprovado_por_responsavel'
      else 'pendente'
    end;
  elsif old.status_aprovacao is distinct from new.status_aprovacao then
    v_evento := case new.status_aprovacao
      when 'pendente' then 'pendente'
      when 'aprovado' then case when new.aprovado_automaticamente_em is not null then 'aprovado_automaticamente' else 'aprovado' end
      when 'rejeitado' then 'rejeitado'
    end;
  else
    return new;
  end if;

  v_motivo := case when v_evento = 'rejeitado' then new.motivo_devolucao else null end;
  insert into public.apontamentos_horas_aprovacao_eventos (
    tenant_id, empresa_id, apontamento_id, evento, realizado_por, motivo
  ) values (
    new.tenant_id, new.empresa_id, new.id, v_evento, auth.uid(), v_motivo
  );
  return new;
end;
$$;

drop trigger if exists trg_apontamento_preparar_aprovacao on public.apontamentos_horas;
create trigger trg_apontamento_preparar_aprovacao
before insert or update on public.apontamentos_horas
for each row execute function public.fn_apontamento_preparar_aprovacao();

drop trigger if exists trg_apontamento_registrar_evento_aprovacao on public.apontamentos_horas;
create trigger trg_apontamento_registrar_evento_aprovacao
after insert or update on public.apontamentos_horas
for each row execute function public.fn_apontamento_registrar_evento_aprovacao();

create or replace function public.fn_validar_apontamento_horas()
returns trigger
language plpgsql
set search_path = pg_catalog, public, a, c, f, m, r, auth, extensions
as $$
declare
  v_status_legado text;
  v_status_fluxo text;
  v_tem_taxa boolean;
begin
  select status, status_fluxo
    into v_status_legado, v_status_fluxo
  from public.ordens_servico
  where id = new.os_id
    and tenant_id = new.tenant_id
    and empresa_id = new.empresa_id;

  if v_status_legado is null then
    raise exception 'OS % não encontrada.', new.os_id;
  end if;
  if v_status_legado = 'cancelada' then
    raise exception 'Não é permitido lançar horas: OS % está cancelada.', new.os_id;
  end if;
  if coalesce(v_status_fluxo, public.mapear_status_legado_para_fluxo(v_status_legado))
       not in ('em_andamento', 'em_andamento_garantia') then
    raise exception 'Não é permitido lançar horas: a OS % não está em andamento.', new.os_id;
  end if;
  if coalesce(new.gerado_por_hh, false) then
    return new;
  end if;

  select exists (
    select 1
    from public.colaborador_taxas as taxa
    where taxa.colaborador_id = new.colaborador_id
      and new.data >= taxa.vigencia_inicio
      and (taxa.vigencia_fim is null or new.data <= taxa.vigencia_fim)
  ) into v_tem_taxa;

  if not v_tem_taxa then
    raise exception 'Não é permitido lançar horas: colaborador % não possui taxa vigente em %.', new.colaborador_id, new.data;
  end if;
  return new;
end;
$$;

create or replace function public.os_concluir(p_os_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_origem text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  select ue.papel into v_papel
  from a.usuario u join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = v_auth_uid and u.ativo and u.deleted_at is null
    and ue.empresa_id = v_empresa_id and ue.ativo and ue.deleted_at is null
  limit 1;
  if upper(coalesce(v_papel, '')) not in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    raise exception 'Somente coordenação, admin ou diretor podem concluir a OS.';
  end if;
  select status_fluxo into v_origem
  from public.ordens_servico
  where id = p_os_id and tenant_id = v_tenant_id and empresa_id = v_empresa_id
  for update;
  if not found then raise exception 'OS não encontrada na empresa atual.'; end if;
  if v_origem not in ('em_andamento', 'em_andamento_garantia') then
    raise exception 'A OS não está em andamento para ser concluída.';
  end if;
  if exists (
    select 1 from public.apontamentos_horas ah
    where ah.os_id = p_os_id and ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id
      and ah.status_aprovacao = 'pendente'
  ) then
    raise exception 'A OS possui horas pendentes de aprovação e não pode ser concluída.';
  end if;

  update public.ordens_servico
  set status_fluxo = case when v_origem = 'em_andamento_garantia' then 'concluida_garantia' else 'concluida' end,
      status = 'concluida', data_conclusao = now(), atualizado_em = now()
  where id = p_os_id and tenant_id = v_tenant_id and empresa_id = v_empresa_id;
  if v_origem = 'em_andamento' then
    update public.os_gestao_itens
    set progresso_percent = 100, data_prevista = coalesce(data_prevista, current_date), updated_at = now()
    where os_id = p_os_id and tenant_id = v_tenant_id and empresa_id = v_empresa_id and habilitado
      and item_tipo in ('projeto'::public.os_gestao_tipo, 'execucao'::public.os_gestao_tipo)
      and area in ('eletrico'::public.os_gestao_area, 'seguranca'::public.os_gestao_area, 'mecanico'::public.os_gestao_area, 'software'::public.os_gestao_area)
      and coalesce(progresso_percent, 0) < 100;
  end if;
  insert into public.ordens_servico_fluxo_eventos (tenant_id, empresa_id, os_id, evento, status_origem, status_destino, realizado_por)
  values (v_tenant_id, v_empresa_id, p_os_id, case when v_origem = 'em_andamento_garantia' then 'concluir_garantia' else 'concluir' end, v_origem,
          case when v_origem = 'em_andamento_garantia' then 'concluida_garantia' else 'concluida' end, v_auth_uid);
  return jsonb_build_object('sucesso', true);
end;
$$;

create or replace function public.os_faturar(p_os_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, f, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid(); v_tenant_id uuid := public.current_tenant_id(); v_empresa_id uuid := public.current_empresa_id(); v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  if upper(coalesce(v_papel, '')) <> 'FINANCEIRO' then raise exception 'Somente financeiro pode faturar a OS.'; end if;
  if not exists (select 1 from public.ordens_servico where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and status_fluxo='concluida' for update) then raise exception 'A OS precisa estar concluída para ser faturada.'; end if;
  if not exists (
    select 1 from f.documento_fiscal documento
    where documento.tenant_id=v_tenant_id and documento.empresa_id=v_empresa_id and documento.os_id_import=p_os_id
      and documento.operacao='SAIDA' and documento.deleted_at is null
      and ((upper(coalesce(documento.modelo, ''))='NFSE' and upper(coalesce(documento.nfse_status, ''))='EMITIDA')
        or (upper(coalesce(documento.modelo, '')) <> 'NFSE' and (nullif(upper(btrim(coalesce(documento.nfe_status, ''))), '') is null or upper(coalesce(documento.nfe_status, ''))='EMITIDA')))
  ) then raise exception 'A OS só pode ser faturada com NF-e ou NFS-e emitida vinculada.'; end if;
  update public.ordens_servico set status_fluxo='faturada', status='concluida', faturado_em=now(), faturada_presumida_legado=false, atualizado_em=now() where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id;
  insert into public.ordens_servico_fluxo_eventos (tenant_id,empresa_id,os_id,evento,status_origem,status_destino,realizado_por) values (v_tenant_id,v_empresa_id,p_os_id,'faturar','concluida','faturada',v_auth_uid);
  return jsonb_build_object('sucesso', true);
end;
$$;

create or replace function public.os_reabrir_correcao(p_os_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  if upper(coalesce(v_papel,'')) not in ('ADMIN','DIRETOR','COORDENACAO') then raise exception 'Somente coordenação, admin ou diretor podem reabrir a OS.'; end if;
  if not exists (select 1 from public.ordens_servico where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and status_fluxo='concluida' for update) then raise exception 'Somente uma OS concluída pode ser reaberta para correção.'; end if;
  update public.ordens_servico set status_fluxo='em_andamento', status='em_andamento', data_conclusao=null, atualizado_em=now() where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id;
  insert into public.ordens_servico_fluxo_eventos (tenant_id,empresa_id,os_id,evento,status_origem,status_destino,realizado_por) values (v_tenant_id,v_empresa_id,p_os_id,'reabrir_correcao','concluida','em_andamento',v_auth_uid);
  return jsonb_build_object('sucesso',true);
end;
$$;

create or replace function public.os_reabrir_garantia(p_os_id integer, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_papel text; v_faturado_em timestamptz; v_presumida boolean;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  if nullif(btrim(p_motivo),'') is null then raise exception 'O motivo da garantia é obrigatório.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  if upper(coalesce(v_papel,'')) not in ('COORDENACAO','FINANCEIRO') then raise exception 'Somente coordenação ou financeiro podem reabrir uma garantia.'; end if;
  select faturado_em, faturada_presumida_legado into v_faturado_em, v_presumida from public.ordens_servico where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and status_fluxo='faturada' for update;
  if not found then raise exception 'Somente uma OS faturada pode ser reaberta como garantia.'; end if;
  if v_presumida then raise exception 'OS faturada presumida de legado não pode ser reaberta como garantia.'; end if;
  if v_faturado_em is null or v_faturado_em < now() - interval '6 months' then raise exception 'A garantia só pode ser reaberta até seis meses após o faturamento.'; end if;
  update public.ordens_servico set status_fluxo='em_andamento_garantia', status='em_andamento', garantia_motivo=nullif(btrim(p_motivo),''), garantia_reaberta_em=now(), atualizado_em=now() where id=p_os_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id;
  insert into public.ordens_servico_fluxo_eventos (tenant_id,empresa_id,os_id,evento,status_origem,status_destino,motivo,realizado_por) values (v_tenant_id,v_empresa_id,p_os_id,'reabrir_garantia','faturada','em_andamento_garantia',nullif(btrim(p_motivo),''),v_auth_uid);
  return jsonb_build_object('sucesso',true);
end;
$$;

create or replace function public.os_concluir_garantia(p_os_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  if upper(coalesce(v_papel,'')) <> 'COORDENACAO' then raise exception 'Somente coordenação pode concluir a garantia.'; end if;
  perform public.os_concluir(p_os_id);
  return jsonb_build_object('sucesso',true);
end;
$$;

-- Compatibilidade para integrações e chamadas antigas do ERP-Web.
create or replace function public.concluir_os(os_id_param integer)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.os_concluir(os_id_param);
end;
$$;

create or replace function public.aprovar_apontamento(p_apontamento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_responsavel uuid;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select os.responsavel_aprovacao_id into v_responsavel from public.apontamentos_horas ah join public.ordens_servico os on os.id=ah.os_id and os.tenant_id=ah.tenant_id and os.empresa_id=ah.empresa_id where ah.id=p_apontamento_id and ah.tenant_id=v_tenant_id and ah.empresa_id=v_empresa_id for update;
  if not found then raise exception 'Apontamento não encontrado na empresa atual.'; end if;
  if v_responsavel is distinct from v_auth_uid then raise exception 'Somente o responsável da OS pode aprovar horas.'; end if;
  update public.apontamentos_horas set status_aprovacao='aprovado', aprovado_por=v_auth_uid, aprovado_em=now(), aprovado_automaticamente_em=null, rejeitado_em=null, motivo_devolucao=null where id=p_apontamento_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and status_aprovacao='pendente';
  if not found then raise exception 'O apontamento não está pendente de aprovação.'; end if;
  return jsonb_build_object('sucesso',true);
end;
$$;

create or replace function public.rejeitar_apontamento(p_apontamento_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_responsavel uuid;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  if nullif(btrim(p_motivo),'') is null then raise exception 'Informe o motivo da rejeição.'; end if;
  select os.responsavel_aprovacao_id into v_responsavel from public.apontamentos_horas ah join public.ordens_servico os on os.id=ah.os_id and os.tenant_id=ah.tenant_id and os.empresa_id=ah.empresa_id where ah.id=p_apontamento_id and ah.tenant_id=v_tenant_id and ah.empresa_id=v_empresa_id for update;
  if not found then raise exception 'Apontamento não encontrado na empresa atual.'; end if;
  if v_responsavel is distinct from v_auth_uid then raise exception 'Somente o responsável da OS pode rejeitar horas.'; end if;
  update public.apontamentos_horas set status_aprovacao='rejeitado', aprovado_por=null, aprovado_em=null, aprovado_automaticamente_em=null, rejeitado_em=now(), motivo_devolucao=nullif(btrim(p_motivo),'') where id=p_apontamento_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and status_aprovacao='pendente';
  if not found then raise exception 'O apontamento não está pendente de aprovação.'; end if;
  return jsonb_build_object('sucesso',true);
end;
$$;

create or replace function public.aprovar_apontamentos_vencidos()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare v_total integer;
begin
  update public.apontamentos_horas
  set status_aprovacao='aprovado', aprovado_por=null, aprovado_em=now(), aprovado_automaticamente_em=now(), rejeitado_em=null, motivo_devolucao=null
  where status_aprovacao='pendente' and pendente_em <= now() - interval '7 days';
  get diagnostics v_total = row_count;
  return v_total;
end;
$$;

-- A extensão já faz parte do projeto. Nome fixo permite reexecutar a migration
-- em bancos restaurados sem criar dois jobs.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'aprovacao-horas-sla-diaria') then
      perform cron.unschedule(jobid) from cron.job where jobname = 'aprovacao-horas-sla-diaria';
    end if;
    perform cron.schedule('aprovacao-horas-sla-diaria', '15 0 * * *', 'select public.aprovar_apontamentos_vencidos();');
  end if;
end;
$$;

create or replace function public.web_criar_apontamentos_horas(p_lancamentos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_item jsonb; v_os_id integer; v_total integer:=0; v_papel text; v_colaborador_proprio_id uuid;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id
  where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  if v_papel is null then raise exception 'Não foi possível identificar seu papel na empresa atual.'; end if;
  select id into v_colaborador_proprio_id from public.colaboradores
  where user_id=v_auth_uid and tenant_id=v_tenant_id and empresa_id=v_empresa_id and ativo;
  if p_lancamentos is null or jsonb_typeof(p_lancamentos) <> 'array' or jsonb_array_length(p_lancamentos)=0 then raise exception 'Informe ao menos um apontamento.'; end if;
  for v_item in select value from jsonb_array_elements(p_lancamentos) loop
    v_os_id := nullif(v_item->>'os_id','')::integer;
    if upper(v_papel)='APONTADOR' and (v_colaborador_proprio_id is null or nullif(v_item->>'colaborador_id','')::uuid <> v_colaborador_proprio_id) then
      raise exception 'O perfil APONTADOR só pode lançar horas para o próprio colaborador.';
    end if;
    if not exists (select 1 from public.ordens_servico os where os.id=v_os_id and os.tenant_id=v_tenant_id and os.empresa_id=v_empresa_id and coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status)) in ('em_andamento','em_andamento_garantia')) then raise exception 'A OS % não está disponível para apontamentos.', v_os_id; end if;
    insert into public.apontamentos_horas (tenant_id,empresa_id,os_id,colaborador_id,data,horas,tipo_hora_id,fator_aplicado,descricao,status,hora_entrada_1,hora_saida_1,hora_entrada_2,hora_saida_2,gerado_por_hh,criado_por_user_id)
    values (v_tenant_id,v_empresa_id,v_os_id,(v_item->>'colaborador_id')::uuid,(v_item->>'data')::date,nullif(v_item->>'horas','')::numeric,nullif(v_item->>'tipo_hora_id','')::uuid,nullif(v_item->>'fator_aplicado','')::numeric,nullif(v_item->>'descricao',''),'lancado',nullif(v_item->>'hora_entrada_1','')::time,nullif(v_item->>'hora_saida_1','')::time,nullif(v_item->>'hora_entrada_2','')::time,nullif(v_item->>'hora_saida_2','')::time,false,v_auth_uid);
    v_total:=v_total+1;
  end loop;
  return jsonb_build_object('sucesso',true,'gravados',v_total);
end;
$$;

create or replace function public.web_atualizar_apontamento_horas(p_apontamento_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_papel text; v_colaborador_proprio_id uuid;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id
  where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  select id into v_colaborador_proprio_id from public.colaboradores where user_id=v_auth_uid and tenant_id=v_tenant_id and empresa_id=v_empresa_id and ativo;
  if upper(coalesce(v_papel,''))='APONTADOR' and not exists (select 1 from public.apontamentos_horas where id=p_apontamento_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and colaborador_id=v_colaborador_proprio_id) then
    raise exception 'O perfil APONTADOR só pode editar o próprio apontamento.';
  end if;
  update public.apontamentos_horas
  set data=coalesce(nullif(p_dados->>'data','')::date,data), horas=case when p_dados ? 'horas' then nullif(p_dados->>'horas','')::numeric else horas end,
      tipo_hora_id=case when p_dados ? 'tipo_hora_id' then nullif(p_dados->>'tipo_hora_id','')::uuid else tipo_hora_id end,
      descricao=case when p_dados ? 'descricao' then nullif(p_dados->>'descricao','') else descricao end,
      hora_entrada_1=case when p_dados ? 'hora_entrada_1' then nullif(p_dados->>'hora_entrada_1','')::time else hora_entrada_1 end,
      hora_saida_1=case when p_dados ? 'hora_saida_1' then nullif(p_dados->>'hora_saida_1','')::time else hora_saida_1 end,
      hora_entrada_2=case when p_dados ? 'hora_entrada_2' then nullif(p_dados->>'hora_entrada_2','')::time else hora_entrada_2 end,
      hora_saida_2=case when p_dados ? 'hora_saida_2' then nullif(p_dados->>'hora_saida_2','')::time else hora_saida_2 end
  where id=p_apontamento_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and not coalesce(gerado_por_hh,false);
  if not found then raise exception 'Apontamento não encontrado, fora da empresa atual ou gerado por HH.'; end if;
  return jsonb_build_object('sucesso',true);
end;
$$;

create or replace function public.web_excluir_apontamento_horas(p_apontamento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare v_auth_uid uuid:=auth.uid(); v_tenant_id uuid:=public.current_tenant_id(); v_empresa_id uuid:=public.current_empresa_id(); v_papel text; v_colaborador_proprio_id uuid;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null or not public.has_active_empresa_access(v_tenant_id,v_empresa_id) then raise exception 'Autenticação e contexto de empresa são obrigatórios.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id
  where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  select id into v_colaborador_proprio_id from public.colaboradores where user_id=v_auth_uid and tenant_id=v_tenant_id and empresa_id=v_empresa_id and ativo;
  if upper(coalesce(v_papel,''))='APONTADOR' and not exists (select 1 from public.apontamentos_horas where id=p_apontamento_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and colaborador_id=v_colaborador_proprio_id) then
    raise exception 'O perfil APONTADOR só pode excluir o próprio apontamento.';
  end if;
  delete from public.apontamentos_horas where id=p_apontamento_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id and not coalesce(gerado_por_hh,false);
  if not found then raise exception 'Apontamento não encontrado, fora da empresa atual ou gerado por HH.'; end if;
  return jsonb_build_object('sucesso',true);
end;
$$;

-- Mantém a assinatura usada pelo app móvel. A diferença deliberada é que uma
-- hora já aprovada pode ser corrigida: o trigger a devolve para pendente.
create or replace function public.app_editar_apontamento(
  p_apontamento_id uuid,
  p_horas numeric,
  p_tipo_hora_id uuid,
  p_descricao text default null,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_colaborador_proprio_id uuid;
  v_papel text;
  v_colaborador_id uuid;
  v_os_id integer;
  v_data date;
  v_gerado_por_hh boolean;
  v_tipo_existe boolean;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar autenticação, tenant e empresa ativos.';
  end if;
  if p_horas is null or p_horas <= 0 or p_horas > 24 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo','horas','mensagem','Informe uma quantidade de horas entre 0 e 24.')));
  end if;
  select id into v_colaborador_proprio_id from public.colaboradores
  where user_id=v_auth_uid and tenant_id=v_tenant_id and empresa_id=v_empresa_id and ativo;
  if v_colaborador_proprio_id is null then raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.'; end if;
  select ue.papel into v_papel from a.usuario u join a.usuario_empresa ue on ue.usuario_id=u.id
  where u.auth_user_id=v_auth_uid and u.ativo and u.deleted_at is null and ue.empresa_id=v_empresa_id and ue.ativo and ue.deleted_at is null limit 1;
  select ah.colaborador_id, ah.os_id, ah.data, ah.gerado_por_hh
    into v_colaborador_id, v_os_id, v_data, v_gerado_por_hh
  from public.apontamentos_horas ah
  where ah.id=p_apontamento_id and ah.tenant_id=v_tenant_id and ah.empresa_id=v_empresa_id;
  if not found then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo','apontamento','mensagem','O apontamento informado não existe ou não pertence à empresa atual.')));
  end if;
  if coalesce(v_gerado_por_hh,false) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo','hh','mensagem','Este apontamento é um espelho de HH e deve ser alterado no módulo HH.')));
  end if;
  if upper(coalesce(v_papel,''))='APONTADOR' and v_colaborador_id <> v_colaborador_proprio_id then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo','permissao','mensagem','O perfil APONTADOR só pode editar o próprio apontamento.')));
  end if;
  select exists(select 1 from public.tipos_horas th where th.id=p_tipo_hora_id and th.tenant_id=v_tenant_id and th.ativo) into v_tipo_existe;
  if not v_tipo_existe then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo','tipo_hora','mensagem','O tipo de hora informado não existe ou está inativo.')));
  end if;
  if exists (
    select 1 from public.apontamentos_horas ah
    where ah.id <> p_apontamento_id and ah.tenant_id=v_tenant_id and ah.empresa_id=v_empresa_id
      and ah.os_id=v_os_id and ah.colaborador_id=v_colaborador_id and ah.data=v_data
      and ah.tipo_hora_id=p_tipo_hora_id and not coalesce(ah.gerado_por_hh,false)
  ) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo','duplicidade','mensagem','Já existe outro apontamento para esta OS, colaborador, data e tipo de hora.')));
  end if;
  update public.apontamentos_horas
  set horas=p_horas, tipo_hora_id=p_tipo_hora_id, descricao=nullif(btrim(p_descricao),'')
  where id=p_apontamento_id and tenant_id=v_tenant_id and empresa_id=v_empresa_id;
  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', '[]'::jsonb, 'erros', '[]'::jsonb);
end;
$$;

revoke all on function public.os_concluir(integer), public.os_faturar(integer), public.os_reabrir_correcao(integer), public.os_reabrir_garantia(integer,text), public.os_concluir_garantia(integer), public.aprovar_apontamento(uuid), public.rejeitar_apontamento(uuid,text), public.aprovar_apontamentos_vencidos(), public.web_criar_apontamentos_horas(jsonb), public.web_atualizar_apontamento_horas(uuid,jsonb), public.web_excluir_apontamento_horas(uuid) from public, anon, authenticated, service_role;
grant execute on function public.os_concluir(integer), public.os_faturar(integer), public.os_reabrir_correcao(integer), public.os_reabrir_garantia(integer,text), public.os_concluir_garantia(integer), public.aprovar_apontamento(uuid), public.rejeitar_apontamento(uuid,text), public.web_criar_apontamentos_horas(jsonb), public.web_atualizar_apontamento_horas(uuid,jsonb), public.web_excluir_apontamento_horas(uuid) to authenticated;

commit;
