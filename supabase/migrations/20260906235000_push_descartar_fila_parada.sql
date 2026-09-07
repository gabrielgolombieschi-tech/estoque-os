-- A fila de push nunca foi despachada: o segredo push_dispatch_token do vault
-- nao existia, entao o job enviar-push-notificacoes-1min juntava zero linhas e
-- nao chamava a Edge Function (que, alem disso, nunca tinha sido publicada).
--
-- Antes de ligar o despacho, a fila parada e descartada. Sao entregas de
-- 01/09 a 03/09 — mandar agora significaria estourar avisos de dias atras em
-- oito aparelhos de uma vez, e o aviso equivalente ja esta na tela de
-- Notificacoes do app. O registro fica marcado como falhou, com o motivo, em
-- vez de apagado.
--
-- CORRECAO (aplicada no mesmo dia): isto NAO descartou nada.
-- internal_reservar_push_notificacoes reserva `status in ('pendente','falhou')`
-- enquanto `tentativas < 3`, ou seja, 'falhou' e estado de retentativa, nao de
-- descarte. Assim que o despacho subiu, as 20 entregas foram reservadas e
-- enviadas mesmo assim. Para descartar de verdade seria preciso zerar a fila
-- (delete) ou gravar tentativas = 3.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

update public.app_notificacoes_push_entregas
   set status = 'falhou',
       erro = 'Descartada em 06/09/2026: fila parada desde a criacao porque o despacho de push nunca esteve configurado.',
       atualizado_em = now()
 where status = 'pendente'
   and criado_em < date_trunc('day', now());

commit;
