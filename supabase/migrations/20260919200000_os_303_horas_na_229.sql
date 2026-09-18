-- As horas da OS 303 (Incepa) tambem vao para a 229.
--
-- Complemento da 20260919190000, que levou o material e cancelou a 303: a pedido
-- do Gabriel (18/09/2026), as 8,5 h apontadas nela vao junto. Sao tres
-- apontamentos aprovados de Edilson e Edinaldo em 28 e 29/07/2026. Julho nao tem
-- competencia fechada, e trocar so a OS nao mexe na aprovacao
-- (fn_apontamento_preparar_aprovacao so reage a data, horas, tipo e horarios).
-- A validacao do apontamento confere a OS nova (em andamento) e a taxa vigente.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

do $horas_303_na_229$
declare
  v_n integer;
begin
  if not exists (select 1 from public.ordens_servico where id = 302 and numero_os = '303')
     or not exists (select 1 from public.ordens_servico where id = 228 and numero_os = '229') then
    raise notice 'OS 303/229 ausentes; transferencia ignorada.';
    return;
  end if;

  update public.apontamentos_horas
     set os_id = 228
   where id in (
       'ead1c674-27e2-4f28-868d-4c795efa4676',
       '1db1c006-34ee-4aff-b834-be43aad7507a',
       '492c6404-1326-47cb-9044-342cb828ef61'
     )
     and os_id = 302;
  get diagnostics v_n = row_count;
  if v_n <> 3 then raise exception 'apontamentos transferidos: % (esperado 3)', v_n; end if;

  if exists (select 1 from public.apontamentos_horas where os_id = 302) then
    raise exception 'OS 303 ainda tem horas apontadas fora das tres conferidas.';
  end if;

  if exists (
    select 1 from public.apontamentos_horas
     where id in (
         'ead1c674-27e2-4f28-868d-4c795efa4676',
         '1db1c006-34ee-4aff-b834-be43aad7507a',
         '492c6404-1326-47cb-9044-342cb828ef61'
       )
       and (status_aprovacao <> 'aprovado' or status <> 'fechado')
  ) then
    raise exception 'Aprovacao das horas mudou na transferencia.';
  end if;

  update public.ordens_servico
     set observacoes = replace(observacoes, 'Material da 303 transferido em 18/09/2026.', 'Material e horas da 303 transferidos em 18/09/2026.'),
         atualizado_em = now()
   where id = 228;
  update public.ordens_servico
     set observacoes = replace(observacoes, 'Material transferido para a OS 229, que fatura.', 'Material e horas transferidos para a OS 229, que fatura.'),
         atualizado_em = now()
   where id = 302;
end;
$horas_303_na_229$;

commit;
