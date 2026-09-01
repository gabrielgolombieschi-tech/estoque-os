-- Expõe a descrição do título na listagem de AP (coluna nova) e cria RPC para
-- editar a descrição/observação direto no popup de contas a pagar.

-- ─── 1. View r_ap_aging_detalhe + descricao ─────────────────────────────────
do $$
begin
  if to_regclass('f.titulo') is not null
    and to_regclass('f.titulo_parcela') is not null then
    execute $v$
      create or replace view f.r_ap_aging_detalhe as
      select
        t.tenant_id,
        t.empresa_id,
        t.id                                              as titulo_id,
        tp.id                                             as parcela_id,
        tp.numero                                         as parcela_numero,
        t.fornecedor_id,
        coalesce(forn.nome, 'SEM FORNECEDOR')             as fornecedor_nome,
        coalesce(mc.codigo, 'NAO_CLASSIFICADO')           as motivo_codigo,
        coalesce(mc.nome,   'NAO CLASSIFICADO')           as motivo_nome,
        tp.vencimento_date,
        (current_date - tp.vencimento_date)               as dias_atraso,
        tp.valor                                          as valor_parcela,
        tp.valor_aberto,
        t.status,
        t.emissao_date,
        t.competencia_date,
        coalesce(
          t.total_parcelas_serie::bigint,
          (select count(*)
             from f.titulo_parcela tp2
            where tp2.titulo_id = t.id
              and tp2.deleted_at is null)
        )                                                 as total_parcelas,
        t.descricao                                       as descricao
      from f.titulo_parcela tp
      join f.titulo t on t.id = tp.titulo_id
      left join f.titulo_aprovacao ta
        on  ta.tenant_id  = t.tenant_id
        and ta.titulo_id  = t.id
        and ta.deleted_at is null
      left join f.motivo_compra mc
        on  mc.id         = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
        and mc.deleted_at is null
      left join public.fornecedores forn on forn.id = t.fornecedor_id
      where tp.deleted_at  is null
        and t.deleted_at   is null
        and t.tipo         = 'AP'
        and tp.valor_aberto > 0
    $v$;
  end if;
end$$;

-- ─── 2. RPC: editar descrição/observação do título ──────────────────────────
create or replace function f.atualizar_titulo_descricao(
  p_titulo_id uuid,
  p_descricao text,
  p_change_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_t f.titulo%rowtype;
  v_user uuid;
begin
  if p_titulo_id is null then
    raise exception 'p_titulo_id obrigatorio';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_t
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_t.tenant_id, v_t.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  update f.titulo
     set descricao  = nullif(btrim(p_descricao), ''),
         updated_at = now(),
         updated_by = v_user
   where id = p_titulo_id;
end;
$function$;

grant execute on function f.atualizar_titulo_descricao(uuid, text, text) to authenticated;
