\set ON_ERROR_STOP on

-- Discriminacao da NFS-e (f.fn_nfse_discriminacao), com os retoques de 18/09/2026
-- (supabase/migrations/20260919070000_nfse_discriminacao_pedido_e_aspas.sql):
--   1  pedido ja citado na descricao digitada: o segmento automatico nao entra
--   2  descricao sem o pedido: o segmento entra, como sempre
--   3  numero parecido (1487 dentro de 148753) nao conta como citado
--   4  frase legal sai sem aspas
--   5  o resto do texto continua igual: OS, vencimento, ISS retido e observacao
--
-- A funcao e IMMUTABLE e nao le tabelas: da para testar sem fixture.

begin;

do $b1$
declare
  v_com_pedido constant jsonb := '[{"descricao":"ADEQUACAO DE MAQUINA A NR-12. PEDIDO DE COMPRA N 148753","os_numero":"298"}]'::jsonb;
  v_sem_pedido constant jsonb := '[{"descricao":"ADEQUACAO DE MAQUINA A NR-12","os_numero":"298"}]'::jsonb;
  v_parcela constant jsonb := '[{"dias":60}]'::jsonb;
  v_frase constant text := 'Serviço sujeito à retenção de PIS/COFINS/CSLL à alíquota de 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1,0%) conforme Lei 10.833/2003, arts. 30 e 31.';
  v_texto text;
begin
  -- 1. Pedido ja citado: nao repete.
  v_texto := f.fn_nfse_discriminacao(v_com_pedido, '148753', null, v_parcela, date '2026-09-18', false, v_frase, null, null, null, null);
  if v_texto like '%PEDIDO DE COMPRA: 148753%' then
    raise exception 'pedido repetido: %', v_texto;
  end if;
  if v_texto not like '%PEDIDO DE COMPRA N 148753%' then
    raise exception 'a descricao digitada perdeu o pedido: %', v_texto;
  end if;

  -- 2. Descricao sem o pedido: o segmento entra.
  v_texto := f.fn_nfse_discriminacao(v_sem_pedido, '148753', null, v_parcela, date '2026-09-18', false, v_frase, null, null, null, null);
  if v_texto not like '%PEDIDO DE COMPRA: 148753%' then
    raise exception 'pedido sumiu: %', v_texto;
  end if;
  -- Item do pedido acompanha o segmento.
  v_texto := f.fn_nfse_discriminacao(v_sem_pedido, '148753', '10', v_parcela, date '2026-09-18', false, v_frase, null, null, null, null);
  if v_texto not like '%PEDIDO DE COMPRA: 148753 ITEM 10%' then
    raise exception 'item do pedido sumiu: %', v_texto;
  end if;

  -- 3. Numero parecido nao derruba o segmento.
  v_texto := f.fn_nfse_discriminacao('[{"descricao":"SERVICO 1487 E 48753","os_numero":"298"}]'::jsonb, '148753', null, v_parcela, date '2026-09-18', false, v_frase, null, null, null, null);
  if v_texto not like '%PEDIDO DE COMPRA: 148753%' then
    raise exception 'numero parecido derrubou o pedido: %', v_texto;
  end if;

  -- 4. Frase legal sem aspas.
  v_texto := f.fn_nfse_discriminacao(v_sem_pedido, '148753', null, v_parcela, date '2026-09-18', false, v_frase, null, null, null, null);
  if position('"' in v_texto) > 0 then
    raise exception 'frase legal saiu entre aspas: %', v_texto;
  end if;
  if v_texto not like '%conforme Lei 10.833/2003, arts. 30 e 31.%' then
    raise exception 'frase legal sumiu: %', v_texto;
  end if;

  -- 5. O resto do texto continua igual.
  v_texto := f.fn_nfse_discriminacao(v_sem_pedido, '148753', null, v_parcela, date '2026-09-18', true, v_frase, 'OBSERVACAO DO CLIENTE', null, null, null);
  if v_texto not like '%VENCIMENTO: 60 DDL%' then raise exception 'vencimento sumiu: %', v_texto; end if;
  if v_texto not like '%OS 298%' then raise exception 'OS sumiu: %', v_texto; end if;
  if v_texto not like '%OBSERVACAO DO CLIENTE%' then raise exception 'observacao sumiu: %', v_texto; end if;
  -- ISS retido so aparece quando o template do cliente pede {ISS}; no padrao ele nao entra.
  if v_texto not like '%ADEQUACAO DE MAQUINA A NR-12%' then raise exception 'descricao sumiu: %', v_texto; end if;
end;
$b1$;

rollback;
