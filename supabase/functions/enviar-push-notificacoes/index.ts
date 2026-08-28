import { createClient } from 'npm:@supabase/supabase-js@2';

const expoPushUrl = 'https://exp.host/--/api/v2/push/send';

type Entrega = {
  entrega_id: string;
  expo_push_token: string;
  titulo: string;
  corpo: string;
  dados: Record<string, unknown>;
};

type ExpoTicket = {
  status: 'ok' | 'error';
  message?: string;
  details?: { error?: string };
};

function chunks<T>(items: T[], tamanho: number) {
  return Array.from({ length: Math.ceil(items.length / tamanho) }, (_, indice) => items.slice(indice * tamanho, (indice + 1) * tamanho));
}

Deno.serve(async (request) => {
  // Esta Function e chamada pelo agendador usando um segredo proprio. Nunca
  // aceite o JWT do aplicativo aqui: o cliente nao pode consumir a fila.
  const segredo = Deno.env.get('PUSH_DISPATCH_TOKEN');
  if (!segredo || request.headers.get('authorization') !== `Bearer ${segredo}`) {
    return new Response('Não autorizado.', { status: 401 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response('Configuração do Supabase ausente.', { status: 500 });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const { data, error } = await supabase.rpc('internal_reservar_push_notificacoes', { p_limite: 100 });
  if (error) {
    console.error(error);
    return new Response('Não foi possível reservar a fila.', { status: 500 });
  }

  const entregas = (data ?? []) as Entrega[];
  for (const lote of chunks(entregas, 100)) {
    let tickets: ExpoTicket[];
    try {
      const resposta = await fetch(expoPushUrl, {
        method: 'POST',
        headers: { Accept: 'application/json', 'Accept-Encoding': 'gzip, deflate', 'Content-Type': 'application/json' },
        body: JSON.stringify(lote.map((entrega) => ({
          to: entrega.expo_push_token,
          title: entrega.titulo,
          body: entrega.corpo,
          data: entrega.dados,
          sound: 'default',
          channelId: 'operacao',
        }))),
      });
      const corpo = await resposta.json() as { data?: ExpoTicket[] };
      tickets = resposta.ok && Array.isArray(corpo.data) ? corpo.data : lote.map(() => ({ status: 'error', message: `Expo respondeu HTTP ${resposta.status}` }));
    } catch (erro) {
      const mensagem = erro instanceof Error ? erro.message : 'Falha de rede ao enviar push.';
      tickets = lote.map(() => ({ status: 'error', message: mensagem }));
    }

    await Promise.all(lote.map((entrega, indice) => {
      const ticket = tickets[indice] ?? { status: 'error', message: 'Resposta incompleta do Expo.' };
      const desativarDispositivo = ticket.details?.error === 'DeviceNotRegistered';
      return supabase.rpc('internal_finalizar_push_notificacao', {
        p_entrega_id: entrega.entrega_id,
        p_sucesso: ticket.status === 'ok',
        p_erro: ticket.status === 'ok' ? null : ticket.message ?? ticket.details?.error ?? 'Expo rejeitou a notificação.',
        p_desativar_dispositivo: desativarDispositivo,
      });
    }));
  }

  return Response.json({ reservadas: entregas.length });
});
