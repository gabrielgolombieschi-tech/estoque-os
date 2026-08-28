# Entrega de push do app mobile

Esta Edge Function consome a fila criada pela migration `20260827190000_app_mobile_notificacoes.sql` e envia os pushes pelo Expo.

Depois de aplicar a migration, publique-a sem validar JWT do usuario (ela usa um segredo exclusivo do agendador):

```powershell
npx supabase functions deploy enviar-push-notificacoes --no-verify-jwt
npx supabase secrets set PUSH_DISPATCH_TOKEN=<gere-um-segredo-longo>
```

Configure o agendador da plataforma para chamar `POST /functions/v1/enviar-push-notificacoes` a cada minuto com o header `Authorization: Bearer <PUSH_DISPATCH_TOKEN>`. O segredo nao deve ficar no app, em migrations, nem no repositório.

O processamento e idempotente por entrega: uma chamada concorrente reserva linhas com `SKIP LOCKED`; tokens retornados pelo Expo como `DeviceNotRegistered` sao desativados automaticamente.
