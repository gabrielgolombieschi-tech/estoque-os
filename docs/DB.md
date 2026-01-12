# Processo de banco (migrations + backup/restore)

## Requisitos
- `pg_dump`, `pg_restore` e `psql` instalados (PostgreSQL client tools).
- Variavel `DATABASE_URL` apontando para o banco.

Exemplo (PowerShell):
```
$env:DATABASE_URL="postgres://user:pass@host:5432/dbname"
```

## Backups
Gera um arquivo `.dump` em `backups/` (formato custom do PostgreSQL).
```
npm run db:backup
```

Opcionalmente escolha o arquivo:
```
npm run db:backup -- --file backups/backup_dev.dump
```

## Restore (ambiente dev)
Protecao: so permite restore se `DB_ENV=dev`, `NODE_ENV=development` ou `ALLOW_DB_RESTORE=true`.

```
$env:DB_ENV="dev"
npm run db:restore:dev -- --file backups/backup_dev.dump
```

Se o backup for `.sql`, o script usa `psql`. Para `.dump`, usa `pg_restore`.

## Aplicar migrations
Aplica todos os arquivos `.sql` em ordem alfabetica de `supabase/migrations`:
```
npm run db:migrate
```

Se quiser aplicar a partir de uma migration especifica:
```
npm run db:migrate -- --from 20260109_rls_multiempresa.sql
```

## Boas praticas
- Toda mudanca de schema deve ir para `supabase/migrations`.
- Migrations devem ser idempotentes quando possivel (use `if exists`/`if not exists`).
- Nao versionar arquivos de backup em git (mantenha `backups/` fora do repo).
