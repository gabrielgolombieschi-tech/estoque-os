-- Ajuste de meio centavo (20260918270000): a RPC passa a aceitar o CST e a aliquota de IPI que
-- a conferencia da OV ja resolveu na tela mas ainda nao gravou na linha.
--
-- Na OV o rascunho nasce sem cst_ipi/aliquota_ipi em f.solicitacao_item: a conferencia resolve
-- o perfil (fn_solicitacao_nfe_resolver_perfis, so leitura) e so grava na linha ao emitir
-- (fn_solicitacao_nfe_salvar_conferencia_2026). Sem isto, o aviso do empate aparecia na tela e
-- o banco recusava a confirmacao com "este item nao destaca IPI". Com p_cst_ipi/p_aliquota_ipi
-- informados, a RPC grava os dois na linha — o mesmo que a conferencia gravaria — e confere o
-- empate com eles. O montador reconfere o empate na emissao com o que estiver gravado.
--
-- A assinatura de 4 parametros sai para o PostgREST nao ficar ambiguo; a chamada sem os dois
-- novos continua valendo pelo default.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

drop function if exists f.fn_solicitacao_item_arredondar_empate(uuid, text, boolean, text);

create or replace function f.fn_solicitacao_item_arredondar_empate(
  p_solicitacao_item_id uuid,
  p_tributo text,
  p_ativar boolean,
  p_motivo text default null,
  p_cst_ipi text default null,
  p_aliquota_ipi numeric default null
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
  v_cst_ipi text := nullif(btrim(coalesce(p_cst_ipi, '')), '');
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

  -- CST e aliquota que a conferencia resolveu na tela e ainda nao gravou: entram na linha.
  if v_cst_ipi is not null or p_aliquota_ipi is not null then
    if v_cst_ipi is null or p_aliquota_ipi is null then
      raise exception using errcode = '22023', message = 'Informe o CST e a aliquota do IPI juntos.';
    end if;
    update f.solicitacao_item set cst_ipi = v_cst_ipi, aliquota_ipi = p_aliquota_ipi where id = v_si.id;
    v_si.cst_ipi := v_cst_ipi;
    v_si.aliquota_ipi := p_aliquota_ipi;
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

comment on function f.fn_solicitacao_item_arredondar_empate(uuid, text, boolean, text, text, numeric) is
  'Liga/desliga o ajuste de meio centavo de um item (so IPI): exige empate exato e motivo; grava quem/quando. Aceita CST/aliquota de IPI resolvidos na conferencia e ainda nao gravados (20260919020000).';

revoke all on function f.fn_solicitacao_item_arredondar_empate(uuid, text, boolean, text, text, numeric) from public, anon;
grant execute on function f.fn_solicitacao_item_arredondar_empate(uuid, text, boolean, text, text, numeric) to authenticated, service_role;

do $assertions$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'f' and p.proname = 'fn_solicitacao_item_arredondar_empate' and p.pronargs = 4) then
    raise exception 'assinatura antiga de 4 parametros ainda existe';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
