-- Apontador nao lanca material na OS — ele ve o que foi lancado, e so.
-- Decisao de Gabriel em 06/09/2026, junto da separacao entre APONTADOR e
-- TECNICO no app (o tecnico continua lancando).
--
-- Ate aqui a trava existia so na tela: a lista de papeis das duas RPCs de
-- lancamento incluia todos os papeis que existem, entao a guarda nunca
-- recusava ninguem. APONTADOR sai da lista; o resto fica como estava.
--
-- Observacao para depois: PAINEL_TV tambem esta na lista e e uma conta de
-- painel de TV, que nao deveria lancar nada. Deixei fora deste ajuste por nao
-- fazer parte do que foi pedido.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

do $patch_material$
declare
  v_definition text;
  v_alvo text;
  v_needle text := $needle$('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO', 'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH', 'PAINEL_TV', 'APONTADOR')$needle$;
  v_replacement text := $replacement$('ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO', 'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH', 'PAINEL_TV')$replacement$;
  v_msg_needle text := $needle$'Somente técnico, coordenação, diretor ou admin podem lançar material na OS.'$needle$;
  v_msg_replacement text := $replacement$'Seu perfil não lança material na OS. Peça ao técnico ou à coordenação.'$replacement$;
begin
  foreach v_alvo in array array[
    'public.app_lancar_material_os_unfiltered_ov_20260829(integer,text,numeric,text)',
    'public.app_lancar_material_os_por_item_id_unfiltered_ov_20260829(integer,integer,numeric,text)'
  ]
  loop
    v_definition := pg_get_functiondef(v_alvo::regprocedure);

    if position(v_needle in v_definition) = 0 then
      raise exception 'material_papeis_token_not_found: %', v_alvo;
    end if;
    if position(v_msg_needle in v_definition) = 0 then
      raise exception 'material_mensagem_token_not_found: %', v_alvo;
    end if;

    v_definition := replace(v_definition, v_needle, v_replacement);
    v_definition := replace(v_definition, v_msg_needle, v_msg_replacement);
    execute v_definition;
  end loop;
end;
$patch_material$;

do $assertions$
declare
  v_alvo text;
  v_definition text;
begin
  foreach v_alvo in array array[
    'public.app_lancar_material_os_unfiltered_ov_20260829(integer,text,numeric,text)',
    'public.app_lancar_material_os_por_item_id_unfiltered_ov_20260829(integer,integer,numeric,text)'
  ]
  loop
    v_definition := pg_get_functiondef(v_alvo::regprocedure);
    if position('''APONTADOR''' in v_definition) > 0 then
      raise exception 'apontador_ainda_lanca_material: %', v_alvo;
    end if;
    if position('''TECNICO''' in v_definition) = 0 then
      raise exception 'tecnico_perdeu_o_lancamento: %', v_alvo;
    end if;
  end loop;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
