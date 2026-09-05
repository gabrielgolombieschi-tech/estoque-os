-- O trigger de congelamento de transporte roda BEFORE UPDATE OF operacao_snapshot
-- e reconstroi o bloco 'pagamento' do snapshot. Ele nasceu antes das parcelas
-- (20260904140000) e sobrescrevia o bloco montado por
-- fn_solicitacao_nfe_congelar_cadastro, derrubando 'parcelas' e 'fatura_numero'
-- no mesmo UPDATE. Descoberto na nota de evidencia de 05/09/2026 12:48:
-- a Edge recusou a emissao por "venda a prazo exige ao menos uma parcela".
--
-- Agora o trigger monta o bloco completo, com a mesma regra da funcao de
-- congelamento, e preserva chaves extras que o snapshot ja tenha.

create or replace function f.tg_solicitacao_nfe_congelar_transporte()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $function$
declare
  v_pagamento_anterior jsonb := coalesce(new.operacao_snapshot->'pagamento', '{}'::jsonb);
begin
  if jsonb_typeof(new.operacao_snapshot) = 'object' then
    new.operacao_snapshot := new.operacao_snapshot || jsonb_build_object(
      'transportador', new.transportador_dados,
      'volumes', new.volumes_dados,
      'pagamento', v_pagamento_anterior || jsonb_build_object(
        'forma', new.pagamento_forma,
        'indicador', new.pagamento_indicador,
        'descricao', new.pagamento_descricao,
        'parcelas', case when new.pagamento_indicador = 1 then new.pagamento_parcelas else null end,
        'fatura_numero', coalesce(
          v_pagamento_anterior->>'fatura_numero',
          (
            select os.codigo
            from f.solicitacao_item si
            join public.ordens_servico os on os.id::text = si.origem_id
            where si.tenant_id = new.tenant_id and si.empresa_id = new.empresa_id
              and si.solicitacao_id = new.id and si.origem_tipo = 'OV'
            order by si.ordem limit 1
          )
        )
      )
    );
  end if;
  return new;
end;
$function$;

-- Solicitacoes ja congeladas com o bloco antigo (a prazo, sem parcelas no
-- snapshot) sao recongeladas pela reconferencia; nao ha nota autorizada
-- dependendo delas. A unica no momento e a 4749bdbe (evidencia do perfil O0),
-- que sera reconferida pela tela.
