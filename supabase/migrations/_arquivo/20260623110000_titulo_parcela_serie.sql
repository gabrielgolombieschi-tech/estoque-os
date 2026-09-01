-- Adiciona total_parcelas_serie em f.titulo para registrar o denominador
-- em parcelamentos onde cada titulo = 1 mês (impostos, financiamentos).
-- Atualiza os títulos PRONAMP já inseridos e recria a view para expor o campo.

-- ─── 1. Nova coluna ──────────────────────────────────────────────────────────
alter table f.titulo
  add column if not exists total_parcelas_serie integer;

-- ─── 2. Corrige os títulos PRONAMP: numero = posição real na série ───────────
update f.titulo_parcela
set numero = '47'
where titulo_id = '492cd713-0511-49a2-bd64-a9759490323a'
  and deleted_at is null;

update f.titulo_parcela
set numero = '48'
where titulo_id = '88430e96-6fe2-4e3b-9602-c5e5aaf9a457'
  and deleted_at is null;

update f.titulo
set total_parcelas_serie = 48
where id in (
  '492cd713-0511-49a2-bd64-a9759490323a',
  '88430e96-6fe2-4e3b-9602-c5e5aaf9a457'
);

-- ─── 3. Recria view com total_parcelas já existente + total_parcelas_serie ───
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
        -- total_parcelas: usa serie quando explícito, senão conta parcelas reais do titulo
        coalesce(
          t.total_parcelas_serie::bigint,
          (select count(*)
             from f.titulo_parcela tp2
            where tp2.titulo_id = t.id
              and tp2.deleted_at is null)
        )                                                 as total_parcelas
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
