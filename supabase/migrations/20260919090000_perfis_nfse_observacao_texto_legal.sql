-- Por que o texto legal da retencao ficou so com a lei (observacao dos perfis de NFS-e).
--
-- A revisao fiscal de 18/09/2026 (f.fn_perfil_operacao_nfse_revisar) grava campos e justificativa,
-- mas nao a observacao do perfil — e o motivo precisa ficar visivel para quem abrir o cadastro.
--
-- Historico: em 06/09/2026 a contadora indicou a IN RFB 2.141/2023 nas frases; as NFS-e antigas do
-- emissor anterior citavam a IN SRF 459/2004. Enquanto as duas nao forem alinhadas com ela, o texto
-- cita apenas a Lei 10.833/2003, arts. 30 e 31, que e a regra da retencao de PIS/COFINS/CSLL.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

do $observacao$
declare
  v_texto constant text :=
    'Texto legal da retencao (18/09/2026): cita so a Lei 10.833/2003, arts. 30 e 31, sem instrucao normativa. '
    || 'A contadora indicou a IN RFB 2.141/2023 em 06/09/2026 e as notas do emissor anterior citavam a IN SRF 459/2004; '
    || 'o texto fica neutro ate o alinhamento com ela. Decisao de Gabriel G. Mendes, validada externamente. '
    || 'Ver docs/faturamento/nfse-os-298-cremer.md.';
  v_afetados integer;
begin
  update f.perfil_operacao po
     set observacao = concat_ws(' | ', nullif(btrim(coalesce(po.observacao, '')), ''), v_texto)
   where po.modelo = 'NFSE'
     and po.codigo in ('SEG-NFSE-1401', 'SEG-NFSE-1406', 'SEG-NFSE-1709')
     and coalesce(po.observacao, '') not like '%Texto legal da retencao (18/09/2026)%';
  get diagnostics v_afetados = row_count;
  if v_afetados = 0 then
    raise notice 'nenhum perfil de NFS-e atualizado (banco sem os perfis ou observacao ja gravada).';
  end if;
end;
$observacao$;

do $assertions$
begin
  -- Onde os perfis existem, os tres precisam ficar com a observacao e sem nenhuma IN no texto legal.
  if exists (select 1 from f.perfil_operacao where modelo = 'NFSE' and codigo = 'SEG-NFSE-1401') then
    if exists (
      select 1 from f.perfil_operacao
      where modelo = 'NFSE' and codigo in ('SEG-NFSE-1401', 'SEG-NFSE-1406', 'SEG-NFSE-1709')
        and coalesce(observacao, '') not like '%Texto legal da retencao (18/09/2026)%'
    ) then
      raise exception 'perfil de NFS-e sem a observacao do texto legal';
    end if;
    if exists (
      select 1 from f.perfil_operacao
      where modelo = 'NFSE' and codigo in ('SEG-NFSE-1401', 'SEG-NFSE-1406', 'SEG-NFSE-1709')
        and (coalesce(texto_complementar, '') ilike '%IN %' or coalesce(texto_sem_retencao, '') ilike '%IN %')
    ) then
      raise exception 'texto legal de perfil de NFS-e ainda cita instrucao normativa';
    end if;
  end if;
end;
$assertions$;

commit;
