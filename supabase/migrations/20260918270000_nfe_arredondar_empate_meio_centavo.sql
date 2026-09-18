-- Ajuste de meio centavo, por item da solicitacao (pedido do Gabriel, 18/09/2026).
--
-- A regra geral de arredondamento do montador (nfe-payload.ts, round(): meio para cima) NAO
-- muda. O que nasce aqui e uma marca por linha, "arredondar empate para baixo", que so pode
-- ser ligada quando o valor exato do tributo cai em empate de meio centavo (terceira casa 5 e
-- nada depois, com tolerancia de ponto flutuante). Ligada, aquele tributo daquele item
-- arredonda para baixo — diferenca maxima de R$ 0,01 — e a nota fecha com o pedido do
-- cliente. Caso que motivou: OV-SEG-00004-026, vProd 4.158,00 x IPI 9,75% = 405,405; a OC
-- 1309011 fecha em 4.563,40 (IPI 405,40) e o padrao daria 4.563,41.
--
-- Generico o bastante para ICMS (coluna aceita 'IPI' e 'ICMS'); ativo so para IPI agora — a
-- RPC recusa ICMS. O motivo e obrigatorio e ficam quem/quando. Nenhum snapshot existente muda:
-- a coluna nasce false para todas as linhas e o montador so desvia quando ela e true.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

alter table f.solicitacao_item
  add column if not exists arredondar_empate_para_baixo boolean not null default false,
  add column if not exists arredondar_empate_tributo text,
  add column if not exists arredondar_empate_motivo text,
  add column if not exists arredondar_empate_por uuid,
  add column if not exists arredondar_empate_em timestamptz;

comment on column f.solicitacao_item.arredondar_empate_para_baixo is
  'Ajuste de meio centavo (20260918270000): true so quando o valor exato do tributo cai em empate de meio centavo; o montador arredonda aquele tributo para baixo (diferenca maxima R$ 0,01).';
comment on column f.solicitacao_item.arredondar_empate_tributo is 'Tributo do ajuste: IPI (ativo) ou ICMS (reservado).';

do $ck$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'f.solicitacao_item'::regclass and conname = 'solicitacao_item_arredondar_empate_ck') then
    alter table f.solicitacao_item add constraint solicitacao_item_arredondar_empate_ck check (
      (not arredondar_empate_para_baixo
        and arredondar_empate_tributo is null and arredondar_empate_motivo is null
        and arredondar_empate_por is null and arredondar_empate_em is null)
      or (arredondar_empate_para_baixo
        and arredondar_empate_tributo in ('IPI', 'ICMS')
        and char_length(btrim(coalesce(arredondar_empate_motivo, ''))) >= 10
        and arredondar_empate_em is not null)
    );
  end if;
end;
$ck$;

-- Empate de meio centavo: terceira casa 5 e nada depois. Numeric e exato, mas a tolerancia
-- protege o valor que chega de fora ja convertido de ponto flutuante.
create or replace function f.fn_nfe_empate_meio_centavo(p_valor numeric)
returns boolean
language sql
immutable
strict
set search_path to 'pg_catalog'
as $$
  select abs(p_valor * 1000 - round(p_valor * 1000)) < 0.000001
     and mod(round(p_valor * 1000)::bigint, 10) = 5;
$$;

comment on function f.fn_nfe_empate_meio_centavo(numeric) is
  'True quando o valor cai em empate de meio centavo (ex.: 405,405). Tolerancia 1e-6 na terceira casa.';

revoke all on function f.fn_nfe_empate_meio_centavo(numeric) from public, anon;
grant execute on function f.fn_nfe_empate_meio_centavo(numeric) to authenticated, service_role;

-- Liga/desliga o ajuste de um item. Recusa fora do empate; exige motivo; guarda quem/quando.
create or replace function f.fn_solicitacao_item_arredondar_empate(
  p_solicitacao_item_id uuid,
  p_tributo text,
  p_ativar boolean,
  p_motivo text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_si f.solicitacao_item%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao_status text;
  v_tributo text := upper(btrim(coalesce(p_tributo, '')));
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_usuario_id uuid := a.fn_current_usuario_id();
  v_base numeric;
  v_aliquota numeric;
  v_exato numeric;
  v_padrao numeric;
  v_para_baixo numeric;
begin
  select * into v_si from f.solicitacao_item si where si.id = p_solicitacao_item_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Item da solicitacao nao encontrado.';
  end if;
  select * into v_sf from f.solicitacao_faturamento sf where sf.id = v_si.solicitacao_id for update;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access(v_sf.tenant_id, v_sf.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para alterar o arredondamento desta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = format('Solicitacao em %s: o arredondamento nao pode mais ser alterado.', v_sf.status);
  end if;
  -- Homologacao autorizada nao trava (obriga a homologar de novo); producao ou envio em andamento trava.
  select e.status into v_emissao_status
  from f.documento_fiscal_emissao e
  where e.tenant_id = v_sf.tenant_id and e.empresa_id = v_sf.empresa_id and e.solicitacao_id = v_sf.id
    and (
      (e.ambiente = 'PRODUCAO' and e.status not in ('RASCUNHO', 'REJEITADA', 'ERRO'))
      or e.status not in ('RASCUNHO', 'REJEITADA', 'ERRO', 'AUTORIZADA', 'CANCELADA')
    )
  order by e.created_at desc
  limit 1;
  if v_emissao_status is not null then
    raise exception using errcode = '55000', message = format('A NF-e desta solicitacao esta em %s; o arredondamento nao pode mais ser alterado.', v_emissao_status);
  end if;
  if v_tributo not in ('IPI', 'ICMS') then
    raise exception using errcode = '22023', message = 'Tributo do ajuste invalido: use IPI.';
  end if;
  if v_tributo = 'ICMS' then
    raise exception using errcode = '22023', message = 'O ajuste de meio centavo so vale para o IPI por enquanto.';
  end if;

  if not p_ativar then
    update f.solicitacao_item
       set arredondar_empate_para_baixo = false,
           arredondar_empate_tributo = null,
           arredondar_empate_motivo = null,
           arredondar_empate_por = null,
           arredondar_empate_em = null
     where id = v_si.id;
    return jsonb_build_object('ativo', false, 'solicitacao_item_id', v_si.id);
  end if;

  if v_usuario_id is null and session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'Usuario sem cadastro: o ajuste precisa registrar quem confirmou.';
  end if;
  if v_motivo is null or char_length(v_motivo) < 10 then
    raise exception using errcode = '22023', message = 'Informe o motivo do ajuste de meio centavo (10 caracteres ou mais).';
  end if;
  if char_length(v_motivo) > 300 then
    raise exception using errcode = '22023', message = 'O motivo do ajuste pode ter no maximo 300 caracteres.';
  end if;

  -- Mesma conta do montador: base = round(qtd x unitario, 2) - desconto; IPI = base x aliquota / 100.
  if v_si.aliquota_ipi is null or v_si.aliquota_ipi <= 0 or coalesce(v_si.cst_ipi, '') not in ('50', '99') then
    raise exception using errcode = '22023', message = 'Este item nao destaca IPI: nao ha o que arredondar.';
  end if;
  v_base := round(coalesce(v_si.quantidade, 0) * coalesce(v_si.valor_unitario, 0), 2) - coalesce(v_si.valor_desconto, 0);
  v_aliquota := v_si.aliquota_ipi;
  v_exato := v_base * v_aliquota / 100;
  if not f.fn_nfe_empate_meio_centavo(v_exato) then
    raise exception using errcode = '22023', message = format(
      'O IPI deste item nao cai em empate de meio centavo (valor exato %s): o ajuste nao se aplica.',
      translate(to_char(v_exato, 'FM999,999,990.0000'), ',.', '.,'));
  end if;
  v_padrao := round(v_exato, 2);
  v_para_baixo := (round(v_exato * 1000) - 5) / 1000;

  update f.solicitacao_item
     set arredondar_empate_para_baixo = true,
         arredondar_empate_tributo = v_tributo,
         arredondar_empate_motivo = v_motivo,
         arredondar_empate_por = v_usuario_id,
         arredondar_empate_em = now()
   where id = v_si.id;

  return jsonb_build_object(
    'ativo', true, 'solicitacao_item_id', v_si.id, 'tributo', v_tributo,
    'valor_exato', v_exato, 'valor_padrao', v_padrao, 'valor_para_baixo', v_para_baixo,
    'motivo', v_motivo, 'confirmado_por', v_usuario_id, 'confirmado_em', now()
  );
end;
$$;

comment on function f.fn_solicitacao_item_arredondar_empate(uuid, text, boolean, text) is
  'Liga/desliga o ajuste de meio centavo de um item (so IPI por enquanto): exige empate exato de meio centavo e motivo; grava quem/quando (20260918270000).';

revoke all on function f.fn_solicitacao_item_arredondar_empate(uuid, text, boolean, text) from public, anon;
grant execute on function f.fn_solicitacao_item_arredondar_empate(uuid, text, boolean, text) to authenticated, service_role;

do $assertions$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'f' and table_name = 'solicitacao_item' and column_name = 'arredondar_empate_para_baixo'
  ) then
    raise exception 'coluna arredondar_empate_para_baixo nao criada';
  end if;
  if exists (select 1 from f.solicitacao_item where arredondar_empate_para_baixo) then
    raise exception 'nenhuma linha existente devia nascer com o ajuste ligado';
  end if;
  if not f.fn_nfe_empate_meio_centavo(405.405) or f.fn_nfe_empate_meio_centavo(405.4051) or f.fn_nfe_empate_meio_centavo(405.41) then
    raise exception 'fn_nfe_empate_meio_centavo com resultado errado';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
