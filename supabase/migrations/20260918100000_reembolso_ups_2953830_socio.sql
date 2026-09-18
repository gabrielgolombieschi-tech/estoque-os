-- Nota de debito UPS 2953830 (R$ 557,25, 10/09/2026) da importacao 1ZJ451C10441551106 (NF-e 2/24):
-- foi paga pelo cartao pessoal do socio via PayPal, nao pela empresa. Decisao do Gabriel em 18/09/2026:
--   1. cancelar o titulo AP da UPS (258af6c2..., APROVADO) com o motivo "pago pelo socio; reembolso em
--      titulo proprio" — pelo fluxo do financeiro (f.cancelar_titulo_ap: parcelas zeradas, evento
--      financeiro e de aprovacao);
--   2. criar titulo AP MANUAL de R$ 557,25 ao fornecedor 362 (Gabriel, pessoa fisica), motivo REEMBOLSO,
--      rateio 100% em CONSUMO - MATERIAIS GERAIS (o mesmo do titulo da UPS), em aberto (PENDENTE),
--      emissao 10/09/2026 (data do pagamento pelo socio), vencimento 18/09/2026 (data do lancamento);
--   3. guardar na importacao (dados_json.ap) a referencia ao titulo novo e ao cancelamento.
-- As RPCs do financeiro exigem usuario: a transacao assume a identidade do Gabriel (auth.users
-- 8eaaa27a...) so dentro deste bloco, como o app faria. O gatilho pos-emissao da importacao nao recria o
-- titulo da UPS: ele retorna antes de tudo quando dados_json ja tem estoque_movimentacoes, e a busca de
-- titulo existente ignora CANCELADO. Reversao: reabrir o titulo da UPS (status APROVADO, valor_aberto e
-- parcela 557,25) e cancelar o titulo do reembolso; ambos ficam registrados em dados_json.ap.

do $reembolso$
declare
  v_titulo_ups uuid := '258af6c2-acca-4e71-8221-6837b11afcd9';
  v_imp uuid := '6f420998-c0b6-4a27-a2ca-c52bc5f030e1';
  v_auth uuid := '8eaaa27a-774e-4dcc-b2bb-416cb28bd2aa';   -- auth.users do Gabriel (a.usuario 7673713a...)
  v_usuario uuid := '7673713a-96b9-4064-889e-0ca685ee3a50';
  v_fornecedor integer := 362;                              -- GABRIEL GOLOMBIESCHI MENDES (CPF)
  v_motivo uuid := '64776ac3-7873-43f5-aa83-45bcef6cc671';  -- REEMBOLSO / REEMBOLSOS-GERAIS
  v_plano uuid := '1f8a219c-8800-4069-85ff-57d42a8548ac';   -- CONSUMO_GERAL / CONSUMO - MATERIAIS GERAIS
  v_motivo_cancelamento text := 'Pago pelo socio (cartao pessoal via PayPal); reembolso em titulo proprio';
  v_descricao text := 'REEMBOLSO - Nota de débito UPS 2953830, importação 1ZJ451C10441551106, NF-e 2/24. Pago via PayPal, cartão pessoal do sócio; reembolsar';
  v_ups f.titulo%rowtype;
  v_novo uuid;
  v_novo_t f.titulo%rowtype;
  v_rateios integer;
begin
  select * into v_ups from f.titulo where id = v_titulo_ups and deleted_at is null;
  if not found then
    raise notice 'assert pulado: titulo da UPS 2953830 ausente neste banco';
    return;
  end if;
  if v_ups.status = 'CANCELADO' then
    raise notice 'titulo da UPS ja cancelado (reembolso ja lancado?): nada a fazer';
    return;
  end if;
  if not exists (select 1 from public.fornecedores where id = v_fornecedor)
     or not exists (select 1 from f.motivo_compra where id = v_motivo and deleted_at is null)
     or not exists (select 1 from f.plano_contas where id = v_plano and deleted_at is null)
     or not exists (select 1 from a.usuario where id = v_usuario and auth_user_id = v_auth and deleted_at is null) then
    raise exception 'fornecedor 362, motivo REEMBOLSO, plano CONSUMO_GERAL ou usuario do Gabriel ausentes';
  end if;

  -- Identidade do Gabriel para as RPCs do financeiro (auth.uid(), tenant/empresa do contexto, permissao).
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_auth, 'role', 'authenticated')::text, true);

  -- 1. Cancela o titulo da UPS pelo fluxo do financeiro.
  perform f.cancelar_titulo_ap(v_titulo_ups, v_motivo_cancelamento);

  -- 2. Titulo do reembolso ao socio (MANUAL, PENDENTE, parcela unica).
  select r.titulo_id into v_novo
  from f.criar_titulo_ap_manual_v2(v_descricao, date '2026-09-18', 557.25, v_fornecedor, v_motivo, date '2026-09-10') r;
  select * into v_novo_t from f.titulo where id = v_novo;
  if v_novo_t.tenant_id is distinct from v_ups.tenant_id or v_novo_t.empresa_id is distinct from v_ups.empresa_id then
    raise exception 'titulo do reembolso nasceu em outro tenant/empresa (%/%)', v_novo_t.tenant_id, v_novo_t.empresa_id;
  end if;

  -- Rateio explicito de 100% no plano do titulo da UPS; rateio automatico por regra, se houver, sai do caminho.
  update f.titulo_rateio set deleted_at = now(), updated_at = now(), updated_by = v_usuario
   where titulo_id = v_novo and deleted_at is null;
  insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, percentual, valor, origem_rateio, created_by, updated_by)
  values (v_ups.tenant_id, v_novo, v_plano, 100, 557.25, 'EXPLICITO', v_usuario, v_usuario);
  select count(*) into v_rateios from f.titulo_rateio where titulo_id = v_novo and deleted_at is null;
  if v_rateios <> 1 then
    raise exception 'rateio do reembolso devia ter 1 linha, tem %', v_rateios;
  end if;

  -- 3. Referencia na importacao.
  update f.importacao_remessa
     set dados_json = dados_json || jsonb_build_object('ap',
           coalesce(dados_json->'ap', '{}'::jsonb) || jsonb_build_object(
             'titulo_status', 'CANCELADO',
             'cancelado_em', now(),
             'cancelado_motivo', v_motivo_cancelamento,
             'reembolso', jsonb_build_object(
               'titulo_id', v_novo, 'fornecedor_id', v_fornecedor, 'valor', 557.25,
               'motivo_compra_id', v_motivo, 'plano_contas_id', v_plano, 'status', 'PENDENTE',
               'criado_em', now(), 'observacao', v_descricao))),
         updated_at = now()
   where id = v_imp and deleted_at is null;
  if not found then
    raise exception 'importacao 6f420998 nao encontrada';
  end if;

  raise notice 'titulo da UPS % cancelado; reembolso ao socio criado: titulo % (R$ 557,25, PENDENTE, CONSUMO_GERAL)', v_titulo_ups, v_novo;
end;
$reembolso$;
