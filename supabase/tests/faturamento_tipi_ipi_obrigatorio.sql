\set ON_ERROR_STOP on

-- TIPI: NCM tributado nao sai sem IPI destacado (contabilidade, 09/09/2026, NF-e 2/33).
-- Cobre os tres casos: NCM tributado sem IPI trava, com IPI passa, e NCM com TIPI zero
-- continua livre com CST 51.

begin;

do $tipi$
declare
  v_aliquota numeric;
begin
  -- 1) A tabela responde pelos NCMs que a contabilidade declarou.
  select aliquota into v_aliquota from f.tipi_ncm where ncm = '90328989';
  if coalesce(v_aliquota, -1) <> 9.7500 then
    raise exception 'TIPI de 90328989 deveria ser 9,75 e veio %.', v_aliquota;
  end if;

  select aliquota into v_aliquota from f.tipi_ncm where ncm = '84798190';
  if coalesce(v_aliquota, -1) <> 0 then
    raise exception 'TIPI de 84798190 deveria ser zero e veio %.', v_aliquota;
  end if;

  -- 2) NCM fora da tabela nao trava: nao ha o que afirmar sobre ele.
  select aliquota into v_aliquota from f.tipi_ncm where ncm = '99999999';
  if found then
    raise exception 'NCM inexistente nao deveria ter registro na TIPI.';
  end if;

  -- 3) A coluna que leva a aliquota ate o builder existe.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'f' and table_name = 'solicitacao_item' and column_name = 'ipi_tipi_aliquota'
  ) then
    raise exception 'solicitacao_item.ipi_tipi_aliquota nao existe; o builder nao consegue repetir a trava.';
  end if;

  -- 4) A conferencia carrega a trava.
  if position('tipi_ncm' in (
    select pg_get_functiondef(p.oid)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'fn_os_nfe_conferir_homologacao' and n.nspname = 'f'
  )) = 0 then
    raise exception 'A conferencia nao consulta f.tipi_ncm.';
  end if;
end
$tipi$;

-- A restricao de formato protege o cadastro da tabela.
do $formato$
begin
  begin
    insert into f.tipi_ncm (ncm, aliquota, fonte) values ('9032', 9.75, 'teste');
    raise exception 'Aceitou NCM com menos de 8 digitos.';
  exception when check_violation then null;
  end;
  -- Aliquota fora de faixa: numeric(6,4) ja estoura antes do check, e as duas recusas
  -- servem — o que nao pode e a linha entrar.
  begin
    insert into f.tipi_ncm (ncm, aliquota, fonte) values ('12345678', 120, 'teste');
    raise exception 'Aceitou aliquota acima de 100%%.';
  exception when check_violation or numeric_value_out_of_range then null;
  end;
end
$formato$;

rollback;
