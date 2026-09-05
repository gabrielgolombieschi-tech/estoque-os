# Entrega de push do app mobile

Esta Edge Function consome a fila criada pela migration `20260827190000_app_mobile_notificacoes.sql` e envia os pushes pelo Expo.

Depois de aplicar a migration, publique-a sem validar JWT do usuario (ela usa um segredo exclusivo do agendador):

```powershell
npx supabase functions deploy enviar-push-notificacoes --no-verify-jwt
npx supabase secrets set PUSH_DISPATCH_TOKEN=<gere-um-segredo-longo>
```

O agendamento (a cada minuto) é instalado pela migration `20260903140000_agendar_envio_push_notificacoes.sql` via `pg_cron` + `pg_net`. O job só dispara depois que os segredos entram no Vault:

```sql
select public.fn_push_configurar_agendador('https://<ref>.supabase.co', '<mesmo-PUSH_DISPATCH_TOKEN>');
```

O valor passado aqui (Vault, usado pelo cron) tem que ser idêntico ao `PUSH_DISPATCH_TOKEN` do `secrets set` (runtime da Function). O segredo não deve ficar no app, em migrations, nem no repositório.

O processamento e idempotente por entrega: uma chamada concorrente reserva linhas com `SKIP LOCKED`; tokens retornados pelo Expo como `DeviceNotRegistered` sao desativados automaticamente.
