# `fiscal_itens` como fonte oficial

Decisão aplicada localmente em 01/09/2026. `public.fiscal_itens` passa a ser a fonte oficial dos atributos fiscais do produto; nenhuma migration foi enviada ao remoto.

## Resultado

- `public.itens`: cadastro comercial e de estoque. A migration de faturamento não adiciona mais origem, CST/CSOSN, CST de IPI/PIS/COFINS, `cClassTrib` ou unidade tributável nessa tabela.
- `public.fiscal_itens`: recebeu somente `unidade_tributavel`. NCM, CEST e origem já existiam no baseline.
- `f.perfil_operacao`: permanece responsável por CFOP, CST/CSOSN, IPI, PIS e COFINS de cada emissão. Nenhum perfil ou código fiscal foi semeado.
- Produção, somente leitura em 01/09/2026 às 13:49:33 BRT: **3.488 itens ativos**, **3.150 linhas fiscais no total** e **394 itens ativos sem linha fiscal**.

## Migrations

### `20260901121000_faturamento_itens_campos_fiscais.sql`

A migration ainda não aplicada foi reescrita no lugar. Agora adiciona apenas:

```sql
public.fiscal_itens.unidade_tributavel text
```

`c_class_trib` não foi criado: sua posição depende do desenho de IBS/CBS e da confirmação fiscal, não de um backfill de produto.

### `20260901124000_fiscal_itens_linhas_automaticas.sql`

1. Cria uma linha em `fiscal_itens` para cada item ativo ainda sem registro, com `ON CONFLICT DO NOTHING`.
2. Mantém NCM, CEST, origem, unidade tributável, CFOP/CST legados e alíquotas como `NULL`.
3. Cria `public.fn_itens_criar_linha_fiscal()` e o trigger `trg_itens_criar_linha_fiscal` para inserção de item ativo e ativação posterior.
4. O trigger é `SECURITY DEFINER`, pois quem pode cadastrar o produto não necessariamente possui `fiscal_itens.write`. O escopo gravado vem exclusivamente de `NEW.tenant_id`, `NEW.empresa_id` e `NEW.id`.

Os únicos `NOT NULL` fiscais além das chaves possuem defaults no baseline: `credita_icms=false`, `credita_pis=false`, `credita_cofins=false` e `ipi_entra_no_custo=true`. Nenhuma classificação, código ou alíquota é inferida. Não existe campo obrigatório sem default que impeça a linha mínima.

## Consumidores corrigidos

| Consumidor | Antes | Agora |
|---|---|---|
| Importação de XML de faturamento | Placeholder gravava NCM e CFOP do fornecedor em `itens` | Cria o item comercial e grava somente NCM em `fiscal_itens`; o CFOP da entrada continua apenas na linha documental do XML |
| Impressão de orçamento | NCM vinha de `itens.ncm` | Lê `fiscal_itens.ncm`; usa `itens.ncm` somente como fallback de transição |
| Detalhe de NF-e | Fallback de CFOP vinha de `itens.cfop_padrao` | Ordem: CFOP da linha documental, `fiscal_itens.cfop_padrao` legado e, por último, `itens.cfop_padrao` legado; NCM da linha tem precedência sobre `fiscal_itens.ncm` |

Escrita nova de cadastro fiscal ocorre somente em `fiscal_itens`. CFOP da compra não é promovido a padrão de venda.

## Perfil de operação existente

`f.perfil_operacao`, criado pela migration de fundação, já cumpre o papel principal:

- `codigo`, `nome` e `natureza_texto`: uma linha versionada para cada natureza;
- `empresa_id`: empresa emissora;
- `crt`: regime da empresa;
- `cfop_interno` e `cfop_externo`: destino dentro/fora do estado;
- CST/CSOSN e CSTs de IPI/PIS/COFINS: tributação da emissão;
- `vigencia_inicio` e `vigencia_fim`: versionamento da regra.

As nove naturezas de agosto cabem como nove códigos, separados por empresa, CRT e vigência. A tabela ainda não representa explicitamente `cBenef`, percentual/base da redução, texto legal e `cClassTrib`/IBS/CBS. Esses campos devem ser avaliados depois do portão fiscal; não foi criada outra tabela nem alterada a fundação nesta tarefa.

## Dívidas mantidas conscientemente

Os campos `cfop_padrao`, `cst_icms`, `cst_pis`, `cst_cofins`, alíquotas e flags de crédito continuam em `fiscal_itens` porque já existem em produção. Os principais consumidores são:

- tela de itens e modal do agente de cadastro;
- rotas `sugerir` e `confirmar` do agente;
- importação de estoque e lookup de IPI do pedido de compra;
- funções SQL `apply_fiscal_*` e cálculo de IPI de compras no baseline.

Também continuam no baseline os campos fiscais legados de `public.itens` (`ncm`, `cest`, `cfop_padrao` e alíquotas). Eles não receberam campos novos e agora são apenas fallback nos consumidores ajustados.

A depreciação deve ser separada: primeiro o payload de saída passa a usar `f.perfil_operacao`; depois os leitores são migrados e, só então, os campos de operação podem ser removidos do produto. O agente de cadastro também precisa deixar de sugerir CFOP/CST e de assumir origem `0` automaticamente antes dessa remoção.

## Validações

- `npx supabase db reset --local`: passou do baseline até `20260901124000`.
- Smoke da linha fiscal, com rollback: item ativo recebeu exatamente uma linha; ativação repetida não duplicou; atributos e alíquotas nasceram nulos.
- Smoke do backfill, com rollback: primeira execução criou a linha e a segunda inseriu zero linhas.
- Smoke de faturamento, com rollback: perfil sem CFOP/CST, solicitação e item foram criados e revertidos.
- `/financeiro/gestao-cobranca`: HTTP 200.
- ESLint dos três `.ts`/`.tsx` alterados: passou.
- `supabase db lint --local --level error`: os mesmos **10 erros preexistentes** do baseline; nenhum erro novo desta tarefa.
- `supabase db push` e `supabase migration repair`: **não executados**.

## Backfill futuro de origem

Não executado. Na janela acordada: interromper cadastros, gerar snapshot, atualizar somente linhas cuja origem ainda esteja nula e conferir o resultado contra o snapshot. `SELECT ... FOR UPDATE` não protege os itens sem linha; a segurança vem da condição idempotente e da conferência antes/depois.
