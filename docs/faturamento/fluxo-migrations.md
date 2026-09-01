# Fluxo canônico de migrations

Estado estabelecido em 01/09/2026. Este é o procedimento normal do projeto a partir de agora.

## Organização do diretório

- `00000000000000_baseline_producao.sql`: reconstrói o schema acumulado no ambiente local.
- migrations entre `20240102` e `20260831144500`: marcadores históricos sem DDL, correspondentes às versões já aplicadas remotamente.
- `supabase/migrations/_arquivo/`: SQL original e imutável das 360 migrations históricas.
- migrations posteriores a `20260901120000`: mudanças incrementais reais, executadas no local e no remoto.

Os marcadores históricos não devem receber SQL e não devem ser apagados. Eles existem para que `migration list --linked` tenha a mesma sequência local e remota sem reaplicar sobre o baseline o DDL já acumulado.

## Criar e aplicar uma mudança

```powershell
npx supabase migration new nome_da_mudanca
```

Editar somente o novo arquivo gerado e então validar:

```powershell
npx supabase db reset --local
npx supabase db lint --local
npx tsc --noEmit
```

Executar os testes funcionais específicos da mudança. Para faturamento e integridade fiscal:

```powershell
Get-Content supabase/tests/faturamento_integridade_pre_push.sql -Raw |
  docker exec -i supabase_db_estoque-os psql -v ON_ERROR_STOP=1 -U postgres -d postgres
```

Antes de aplicar remotamente:

```powershell
npx supabase migration list --linked
npx supabase db push --linked --dry-run
```

O `migration list` deve ter zero versões somente remotas. O dry-run deve listar exclusivamente as migrations novas esperadas. Estando correto:

```powershell
npx supabase db push --linked
npx supabase db push --linked --dry-run
```

O último comando deve responder `Remote database is up to date.`

## Regras operacionais

1. Correção estrutural ou de dados controlada sempre vira nova migration; não editar manualmente produção.
2. Migration já aplicada remotamente é imutável. Correção posterior recebe novo timestamp.
3. Não mover novamente migrations aplicadas para fora do diretório ativo; os marcadores fazem parte do histórico canônico.
4. Não criar migration dentro de `_arquivo/`.
5. `migration repair` não faz parte do fluxo normal. O baseline já foi alinhado; novo uso exige diagnóstico específico.
6. `db diff --linked` serve para investigar deriva de schema, não para substituir a prévia do push.
7. Toda query, FK ou backfill deve respeitar `tenant_id` e `empresa_id`.
8. Mudança em tabela operacional deve considerar lock, backup e janela proporcional ao risco.

## Estado confirmado após o alinhamento

```text
369 versões alinhadas
0 somente local
0 somente remota
Remote database is up to date.
```

O lote de faturamento aplicado foi `20260901120000` a `20260901131000`. A `131000` concede os privilégios de API que faltavam nas novas tabelas protegidas por RLS.

## Backup da janela de alinhamento

Local externo ao repositório:

```text
C:\Users\gabri\Dropbox\Projeto_Estoque\backups\estoque-os\20260901_pre_alinhamento_faturamento
```

Arquivos:

| Arquivo | Tamanho | SHA-256 |
|---|---:|---|
| `schema.sql` | 2.302.483 bytes | `80502fecd7e729990cb5c764ac4de3c91459411c7ec94381ebf42b791e06673f` |
| `data.sql` | 904.345.475 bytes | `66b53f5f99fed856fc890aa555962053c7dd955b028d92215894b979720c1a0c` |
| `roles.sql` | 297 bytes | `25873cec56a2cc6514e204f420231777f85c03da818caa7090cdcdfa89776ecd` |

O dump de dados contém tabelas com FKs circulares. Uma restauração deve carregar schema e dados de forma coordenada, desabilitando triggers durante a carga quando necessário; não executar o `data.sql` isoladamente sobre uma base em uso.
