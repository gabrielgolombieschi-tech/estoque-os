-- Saneamento dos parcelamentos SEFAZ/SC pagos pela CAIXA que ficaram de fora do
-- saneamento de 23/06 (20260623140000): PIS/COFINS 48x, INSS PATRONAL 60x e
-- PIS/COFINS 51x. Fornecedor 298 = SECRETARIA DE ESTADO DA FAZENDA.
--
-- Decisões (confirmadas com a diretoria):
--   * PIS/COFINS 48x  -> parcela final = 12/2027 (igual à tela). As 6 parcelas
--     lançadas além disso (jan..jun/2028, R$ 2.533,31 cada = R$ 15.199,86) são
--     EXCEDENTES e ficam canceladas (soft-delete + status CANCELADO).
--   * PIS/COFINS 51x  -> valor R$ 719,22/parcela já está correto no banco
--     (a tela exibia 713,87); nada a alterar no valor.
--
-- Em todos: renumera as parcelas (X real na série), preenche total_parcelas_serie
-- e padroniza a descrição no padrão "PARCELAMENTO <tributo> - CAIXA <N>x".
-- Modelo: 1 título por mês, cada um com 1 titulo_parcela (mesmo do restante da base).

do $$
declare
  v_tenant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
begin
  -- ════════════════════════════════════════════════════════════════════════
  -- PIS/COFINS 48x — final 12/2027 (R$ 2.533,31)
  -- Identificação: fornecedor 298 + descrição "PARCELAMENTO PIS/COFINS - 24/48"
  -- (título manual) OU "PIS/COFINS" genérico de valor 2.533,31 (24 títulos XML).
  -- ════════════════════════════════════════════════════════════════════════

  -- 1) Cancela as 6 parcelas excedentes (vencimento >= jan/2028).
  update f.titulo_parcela p
     set deleted_at = now(), updated_at = now()
   where p.deleted_at is null
     and p.vencimento_date >= date '2028-01-01'
     and p.titulo_id in (
       select t.id from f.titulo t
        where t.tenant_id = v_tenant and t.fornecedor_id = 298
          and ( t.descricao = 'PARCELAMENTO PIS/COFINS - 24/48'
                or (t.descricao = 'PIS/COFINS' and t.valor_total = 2533.31) )
     );

  update f.titulo t
     set status = 'CANCELADO', deleted_at = now(), updated_at = now()
   where t.tenant_id = v_tenant and t.deleted_at is null and t.status <> 'CANCELADO'
     and t.fornecedor_id = 298
     and ( t.descricao = 'PARCELAMENTO PIS/COFINS - 24/48'
           or (t.descricao = 'PIS/COFINS' and t.valor_total = 2533.31) )
     and exists (
       select 1 from f.titulo_parcela p
        where p.titulo_id = t.id and p.vencimento_date >= date '2028-01-01'
     );

  -- 2) Renumera as parcelas remanescentes: numero = 48 - meses(venc -> 2027-12).
  update f.titulo_parcela p
     set numero = (48 - ((extract(year from date '2027-12-01')::int - extract(year from p.vencimento_date)::int)*12
                       + (extract(month from date '2027-12-01')::int - extract(month from p.vencimento_date)::int)))::text,
         updated_at = now()
    from f.titulo t
   where p.titulo_id = t.id and p.deleted_at is null
     and t.deleted_at is null and t.status <> 'CANCELADO'
     and t.tenant_id = v_tenant and t.fornecedor_id = 298
     and ( t.descricao = 'PARCELAMENTO PIS/COFINS - 24/48'
           or (t.descricao = 'PIS/COFINS' and t.valor_total = 2533.31) );

  -- 3) Padroniza descrição + total da série (somente os ativos remanescentes).
  update f.titulo t
     set descricao = 'PARCELAMENTO PIS/COFINS - CAIXA 48x',
         total_parcelas_serie = 48, updated_at = now()
   where t.tenant_id = v_tenant and t.deleted_at is null and t.status <> 'CANCELADO'
     and t.fornecedor_id = 298
     and ( t.descricao = 'PARCELAMENTO PIS/COFINS - 24/48'
           or (t.descricao = 'PIS/COFINS' and t.valor_total = 2533.31) );

  -- ════════════════════════════════════════════════════════════════════════
  -- INSS PATRONAL 60x — final 12/2027 (R$ 2.327,60)
  -- ════════════════════════════════════════════════════════════════════════

  update f.titulo_parcela p
     set numero = (60 - ((extract(year from date '2027-12-01')::int - extract(year from p.vencimento_date)::int)*12
                       + (extract(month from date '2027-12-01')::int - extract(month from p.vencimento_date)::int)))::text,
         updated_at = now()
    from f.titulo t
   where p.titulo_id = t.id and p.deleted_at is null
     and t.deleted_at is null and t.status <> 'CANCELADO'
     and t.tenant_id = v_tenant and t.fornecedor_id = 298
     and t.descricao = 'PARCELAMENTO INSS PATRONAL 60X';

  update f.titulo t
     set descricao = 'PARCELAMENTO INSS PATRONAL - CAIXA 60x',
         total_parcelas_serie = 60, updated_at = now()
   where t.tenant_id = v_tenant and t.deleted_at is null and t.status <> 'CANCELADO'
     and t.fornecedor_id = 298
     and t.descricao = 'PARCELAMENTO INSS PATRONAL 60X';

  -- ════════════════════════════════════════════════════════════════════════
  -- PIS/COFINS 51x — final 01/2027 (R$ 719,22) — valor já correto
  -- ════════════════════════════════════════════════════════════════════════

  update f.titulo_parcela p
     set numero = (51 - ((extract(year from date '2027-01-01')::int - extract(year from p.vencimento_date)::int)*12
                       + (extract(month from date '2027-01-01')::int - extract(month from p.vencimento_date)::int)))::text,
         updated_at = now()
    from f.titulo t
   where p.titulo_id = t.id and p.deleted_at is null
     and t.deleted_at is null and t.status <> 'CANCELADO'
     and t.tenant_id = v_tenant and t.fornecedor_id = 298
     and t.descricao = 'PARCELAMENTO PIS/COFINS 51X';

  update f.titulo t
     set descricao = 'PARCELAMENTO PIS/COFINS - CAIXA 51x',
         total_parcelas_serie = 51, updated_at = now()
   where t.tenant_id = v_tenant and t.deleted_at is null and t.status <> 'CANCELADO'
     and t.fornecedor_id = 298
     and t.descricao = 'PARCELAMENTO PIS/COFINS 51X';

end$$;
