# Emissão de NF-e em homologação

Levantamento realizado em 02/09/2026. As decisões A/B/C foram confirmadas pelo responsável em 02/09/2026. Nenhuma chamada foi feita à Focus e nenhuma NF-e foi emitida nesta etapa.

## Resultado executivo

- **A — confirmado:** em homologação, `f.documento_fiscal.nfe_status` permanece `RASCUNHO`; a autorização existe somente em `f.documento_fiscal_emissao.status='AUTORIZADA'`.
- **B — confirmado:** criar o documento com `chave_acesso='PENDENTE:' || referencia_externa` e trocar atomicamente pela chave de 44 dígitos quando a autorização chegar.
- **C — confirmado:** normalizar número e série para `integer` na borda da Focus; guardar inteiros em `documento_fiscal_emissao` e fazer a única conversão para `text` dentro da função SQL que atualiza `documento_fiscal`.
- O XML autorizado também deve ser persistido em `f.documento_fiscal_xml` antes da troca da chave provisória.
- O endpoint será exclusivo de homologação, não enviará série/número e montará o payload somente a partir do snapshot da solicitação, sem fallback em perfil ou cadastro.
- A implementação aplica A, B e C integralmente. A migration `20260902120000` foi aplicada em produção em 02/09/2026, após backup físico concluído e dry-run; `migration repair` não foi executado.

## A · Isolamento financeiro da homologação

### O que os triggers realmente fazem

Os três triggers executam no `INSERT` de `f.documento_fiscal`, mas as funções internas têm guardas diferentes:

| Trigger | Com `nfe_status='RASCUNHO'` | Ao mudar para `EMITIDA` |
| --- | --- | --- |
| `trg_documento_fiscal__ar_nfe` | executa, mas `fn_upsert_ar_from_nfe_venda` retorna sem criar título | cria/atualiza título AR para saída de produto |
| `trg_documento_fiscal_venda_credito` | executa, mas não altera cobrança | marca a OS/OV como faturada na gestão de cobrança |
| `trg_documento_fiscal__sync_xml_pendencia` | ignora o placeholder porque ele não tem 44 caracteres | verifica se o XML existe no banco e pode abrir `XML_FALTANDO` |

A guarda do crédito usa `coalesce(nfe_status, nfse_status, 'EMITIDA')`. Portanto, deixar `nfe_status` nulo **não é seguro**: o fallback é `EMITIDA`. Ele precisa ser explicitamente `RASCUNHO`.

### Prova local, com rollback

O cenário do pipeline foi executado com os mesmos dados nas duas etapas:

```text
documento criado com nfe_status=RASCUNHO -> 0 títulos
retorno aplicado com nfe_status=EMITIDA  -> 1 título
```

O teste terminou em `ROLLBACK`. Isso confirma que a implementação local atual, em `fn_nfe_aplicar_retorno`, não é segura para homologação: ela sempre promove o documento para `EMITIDA` quando a Focus autoriza.

### Implementação A

Para `documento_fiscal_emissao.ambiente='HOMOLOGACAO'`:

1. manter `documento_fiscal.nfe_status='RASCUNHO'`, inclusive após autorização;
2. registrar `AUTORIZADA`, chave, protocolo, número, série, resposta, XML e DANFE somente em `documento_fiscal_emissao`;
3. manter a atualização da solicitação para `EMITIDA`, conforme o briefing, mas excluir emissões de homologação dos cálculos de saldo comercial para que o teste não consuma saldo real de OS/OV;
4. em produção futura, a promoção de `documento_fiscal.nfe_status` para `EMITIDA` continua sendo o ato que libera os efeitos financeiros.

Isso foi implementado sem mudar os triggers. `fn_nfe_aplicar_retorno` mantém o documento em `RASCUNHO`, e `fn_os_itens_saldo_a_faturar` deixa de reservar quantidade depois que a emissão de homologação fica `AUTORIZADA`.

### XML e o falso `XML_FALTANDO`

O trigger não consulta `documento_fiscal_emissao.xml_path`; ele considera apenas `f.documento_fiscal_xml.xml_raw` ou o XML de uma entrada. Em teste:

```text
placeholder sem 44 dígitos -> 0 pendências XML
chave real de 44 dígitos   -> 1 pendência XML
```

Guardar o XML somente no Storage não satisfaz essa regra. A implementação baixa o XML e, antes de substituir a chave, grava também o conteúdo em `f.documento_fiscal_xml`. Assim o trigger vigente encontra o XML e nenhuma alteração nele é necessária.

## B · Chave provisória antes da autorização

`f.documento_fiscal.chave_acesso` é `text NOT NULL`. Não há check de 44 dígitos nessa coluna; o check de formato existe somente em `nfe_referenciada`. A unicidade ativa é:

```sql
create unique index uq_documento_fiscal__tenant_chave_ativo
on f.documento_fiscal (tenant_id, chave_acesso)
where deleted_at is null;
```

### Implementação B

Usar o formato já iniciado no código local:

```text
PENDENTE:<referencia_externa>
```

A referência contém o identificador idempotente da emissão e já possui `unique (tenant_id, empresa_id, referencia_externa)`. O documento e a linha de emissão são gravados antes da chamada externa. Na autorização, uma única função transacional troca o placeholder pela chave real tanto em `documento_fiscal` quanto em `documento_fiscal_emissao`.

Se a chave real já existir para o tenant, o índice rejeita a troca e a transação inteira volta; isso é preferível a associar duas notas ao mesmo documento silenciosamente. O caso deve ficar como exceção manual, preservando a resposta bruta da Focus.

Não é necessária mudança estrutural para esta decisão.

## C · Série e número

Tipos confirmados no schema:

| Tabela | `serie` | `numero` |
| --- | --- | --- |
| `f.documento_fiscal` | `text` | `text` |
| `f.documento_fiscal_emissao` | `integer` | `integer` |

### Implementação C

1. o builder não envia `serie` nem `numero`;
2. o normalizador da resposta da Focus converte ambos uma única vez para `integer`, rejeitando valor não numérico;
3. `fn_nfe_aplicar_retorno` recebe `integer`, grava diretamente em `documento_fiscal_emissao` e usa `p_serie::text`/`p_numero::text` ao atualizar `documento_fiscal`;
4. nenhum outro ponto faz conversão.

O parse está centralizado em `_shared/focus-nfe.ts`, o cast em `fn_nfe_aplicar_retorno`, e o builder não possui campos `serie` nem `numero`.

## Diagnóstico dos clientes ativos

Leitura de produção via API em 02/09/2026, sem escrita, limitada ao tenant do ERP e às duas empresas ativas. Foram avaliados **76 clientes ativos**. Documento inválido inclui o documento vazio; não foi encontrado documento preenchido com dígito verificador inválido.

| Campo incompleto | Elétrica Segau (74) | SGU Automação (2) | Total (76) |
| --- | ---: | ---: | ---: |
| Documento vazio/inválido | 1 (1,4%) | 0 | **1 (1,3%)** |
| Razão social vazia | 19 (25,7%) | 1 (50,0%) | **20 (26,3%)** |
| Logradouro vazio | 33 (44,6%) | 1 (50,0%) | **34 (44,7%)** |
| Número vazio | 33 (44,6%) | 1 (50,0%) | **34 (44,7%)** |
| Bairro vazio | 33 (44,6%) | 1 (50,0%) | **34 (44,7%)** |
| CEP vazio | 33 (44,6%) | 1 (50,0%) | **34 (44,7%)** |
| Município vazio | 33 (44,6%) | 1 (50,0%) | **34 (44,7%)** |
| UF vazia | 34 (45,9%) | 1 (50,0%) | **35 (46,1%)** |
| Código IBGE vazio | 34 (45,9%) | 2 (100%) | **36 (47,4%)** |
| `indicador_ie` vazio | 74 (100%) | 2 (100%) | **76 (100%)** |
| IE e indicador ambos ausentes | 46 (62,2%) | 1 (50,0%) | **47 (61,8%)** |

O maior bloqueio universal é `indicador_ie`: hoje nenhum cliente ativo passa pelo novo validador sem preenchimento ou confirmação. Para o primeiro piloto, a correção pode ser limitada ao destinatário escolhido; o mutirão completo não precisa bloquear a homologação de uma única solicitação.

## Validador e snapshot da solicitação

O validador deve rodar na composição/transição da solicitação e devolver uma lista estruturada, não uma mensagem única:

```text
entidade · id · campo · mensagem · rota de correção
```

- cliente: documento com dígito verificador, razão social, endereço, IBGE e IE/indicador;
- item: descrição, NCM, unidade, quantidade e valor unitário positivos e CFOP;
- emitente: CNPJ, razão social, endereço fiscal, IBGE, IE/isenção e CRT;
- cada erro deve apontar para `/clientes/<id>`, `/estoque/itens/<id>` ou cadastro da empresa.

A validação fiscal lê os campos de `f.solicitacao_item`. A função `f.fn_solicitacao_nfe_congelar_cadastro` copia apenas atributos permanentes do produto (código, NCM, CEST, origem e unidade tributável), valida todos os campos e só então grava os snapshots. CFOP, CST/CSOSN, tributos e os dados da operação não recebem fallback de perfil.

## Contrato implementado do endpoint

O body aceito por `nfe-emitir` é somente:

```json
{ "solicitacao_id": "uuid" }
```

O endpoint prepara documento, itens e referência idempotente antes da chamada. A URL e o secret da Focus são exclusivamente de homologação. O contexto entregue ao builder contém apenas emissão, documento, solicitação e suas linhas; não contém cliente vivo, empresa viva, produto fiscal nem perfil de operação.

Na autorização, XML e DANFE vão para o Storage privado e o XML bruto também é gravado em `f.documento_fiscal_xml` antes da troca de `PENDENTE:<referencia_externa>` pela chave real.

## Decisão sobre `indicador_ie`

`indicador_ie` representa o `indIEDest` da NF-e e pertence ao estabelecimento destinatário. A fonte mestre é `public.clientes.indicador_ie`, escolhida e confirmada por uma pessoa com base no cadastro fiscal do cliente ou em consulta oficial. A presença, ausência ou conteúdo da IE não autoriza inferência automática.

- `1`: contribuinte do ICMS; a IE deve ser informada;
- `2`: contribuinte isento de inscrição; a tag IE não é enviada;
- `9`: não contribuinte, que pode ou não possuir IE.

Na composição da solicitação, o valor confirmado deve ser copiado para o snapshot do destinatário. O emissor lê apenas esse snapshot: não consulta novamente `clientes` e não usa `indicador_ie_sugerido`. A correção individual foi criada em `/clientes/cadastro-fiscal`; a URL aceita `cliente_id` para abrir diretamente o cliente do piloto.

## Preço unitário da OV no rascunho

O builder do payload lê `f.documento_fiscal_item.valor_unitario`. Essa linha é criada por `f.fn_nfe_preparar_documento_solicitacao` copiando `f.solicitacao_item.valor_unitario`; o builder não consulta `public.os_itens`.

Antes da correção, `f.fn_solicitacao_faturamento_criar_ov_impl` preenchia `f.solicitacao_item.valor_unitario` com `public.os_itens.valor_unitario`. Na OV, esse campo é custo operacional. Portanto, embora o builder estivesse lendo a tabela certa, o rascunho era criado com a origem errada e a NF-e poderia sair pelo custo.

O fluxo corrigido exige `valor_unitario` em cada linha enviada pela composição e grava exatamente o preço digitado. A tela sugere um rateio proporcional do valor total da OV usando o custo apenas como peso matemático; o custo nunca é persistido como preço da NF-e. A diferença entre a soma das linhas e o cabeçalho da OV é exibida, mas não bloqueia o rascunho.

### Pendência registrada — não implementada

`public.os_itens` ainda precisa de um `valor_unitario_venda` próprio, preenchido na criação da OV. Enquanto isso não for modelado, o preço comercial nasce apenas na composição do faturamento e fica preservado em `f.solicitacao_item.valor_unitario`.

## Validações locais

- `supabase db reset --local`: passou do zero com a nova migration.
- smoke do pipeline: preparação idempotente, autorização repetida, XML único em `f.documento_fiscal_xml`, snapshot por item, conversão de número/série e **zero títulos financeiros**.
- testes de faturamento parcial, separação OS/OV, ciclo de vida e RLS autenticada: passaram com rollback.
- 15 cenários unitários do builder: passaram, incluindo bloqueio de produção, ausência de snapshot, regras da IE, valor positivo e imunidade a cadastro/perfil vivo.
- teste da validação fiscal do cliente, TypeScript e ESLint dos arquivos alterados: passaram.
- composição de OV: preço digitado preservado, custo/orçamento ignorados como fonte fiscal, ausência de preço recusada e rateio visual conferido com divergência não bloqueante.
- `db lint`: permanecem os 10 erros preexistentes do baseline; nenhum novo erro foi introduzido.
- Nenhuma chamada real foi feita à Focus; por isso não há uma NF-e autorizada real nesta rodada.

## Aplicação remota em 02/09/2026

- backup físico `COMPLETED` de 02/09/2026 às 13:27 UTC confirmado antes da janela;
- `db push --dry-run` listou somente `20260901151000`, `20260901152000` e `20260902120000`;
- as três migrations foram aplicadas com sucesso e o histórico local/remoto ficou alinhado;
- nove RPCs do fluxo foram confirmadas no OpenAPI remoto, inclusive as novas rotas de composição e snapshot;
- `fn_os_saldo_a_faturar` respondeu para uma OS e uma OV reais, e `fn_os_itens_saldo_a_faturar` calculou uma linha real de OV, sem escrita;
- OS, lista de OVs, detalhe da venda com a aba Faturamento e importação de NF-e carregaram no ambiente publicado sem erro de console;
- o lint remoto manteve exatamente os 10 erros de baseline conhecidos; `public.cpf_valido` acrescenta somente avisos de variável de laço, não erro;
- nenhuma emissão ou chamada à Focus foi executada.
- a migration corretiva `20260902122000_ov_rascunho_preco_editavel.sql` foi aplicada depois: removeu os campos temporários de preço da linha operacional e passou a exigir o valor digitado na composição;
- na OV piloto `OV-SEG-00004-026`, a tela sugeriu R$ 4.563,40 contra custo de R$ 1.650,00; ao editar para R$ 4.000,00, mostrou diferença de R$ 563,40 e manteve o salvamento habilitado, sem gravar o rascunho no teste.
