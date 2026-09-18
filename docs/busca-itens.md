# Busca de itens no app web

As consultas do catálogo usam todos os termos digitados, em qualquer ordem, sem
diferenciar acentos ou caixa. Vírgulas decimais entre dígitos equivalem a pontos:
`cabo 1,5`, `1.5 cabo` e `CÁBO 1.5` encontram os mesmos itens.

- Produto/nome pesquisa somente o nome; busca livre também consulta ID, códigos
  e fabricante. Campos exclusivos de ID/código preservam sua identificação exata
  ou parcial anterior; código numérico no cadastro e impressão é exato.
- Os filtros são aplicados antes de limites, contagem e paginação. Orçamento,
  OS e OV enviam a busca completa à RPC, sem recortar candidatos por uma palavra.
- `lib/itens/busca.ts` atende filtros PostgREST e comparações em memória. Os
  equivalentes SQL são `fn_item_busca_normalizar` e `fn_item_busca_corresponde`.
  As colunas geradas evitam divergência entre o nome gravado e seu texto de busca.
- Movimentações mantém RLS e pesquisa também motivo, fornecedor e OS. Funções de
  contexto nas políticas são avaliadas por consulta, preservando suas condições.
- Identificação automática por código no XML e entradas de ID permanecem exatas.

## Validação

```powershell
node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON --experimental-strip-types scripts/test-busca-itens.mjs
npx playwright test tests/e2e/busca-itens.spec.ts tests/e2e/busca-itens-direta.spec.ts --project=chromium
```

Os testes de navegador são somente leitura e usam o catálogo já existente.
As regressões SQL em `supabase/tests/busca_itens_por_termos.sql` e
`supabase/tests/busca_movimentacoes_por_termos.sql` criam fixtures transacionais e
terminam com `ROLLBACK`; executar no banco local. Cobrem isolamento entre empresas
e tenants, acesso revogado, termos em diferentes campos, paginação e resultados
que antes ficavam além do limite de candidatos.
