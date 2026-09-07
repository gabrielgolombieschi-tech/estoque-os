-- SMOKE TEST — termina em rollback, nao altera nada.
-- Aprova de verdade a hora pendente do colaborador de teste na OS 303 e mostra
-- a notificacao que o gatilho gerou, para confirmar que o ramo novo
-- ('hora_aprovada') roda sem erro de array nulo.

begin;

set local role postgres;

update public.apontamentos_horas
   set status_aprovacao = 'aprovado',
       aprovado_em = now()
 where id = '662e6d2e-2f1e-4174-8aa7-b47756fad8e6';

select n.tipo, n.titulo, n.corpo, u.email as destinatario
from public.app_notificacoes n
join auth.users u on u.id = n.usuario_id
where n.criado_em > now() - interval '1 minute'
order by n.criado_em desc;

rollback;
