# Cadastro fiscal sem dependência do contador

Execução concluída em 01/09/2026, no tenant operacional, com snapshot anterior à escrita e duas passagens idempotentes.

- **1.512 origens**, **21 NCMs**, **819 CESTs** e **1.518 unidades tributáveis** foram preenchidos em `public.fiscal_itens` a partir de valores unânimes nos XMLs de entrada.
- A conferência posterior executou duas novas passagens e aplicou **zero** alterações: o backfill é idempotente e não sobrescreve cadastro preenchido.
- Dos 57 clientes movimentados, **40** receberam município/código IBGE validado; **17** ficaram para correção humana e não houve homônimo ambíguo.
- Foram gravadas **29 sugestões** de `indIEDest`, separadas do campo definitivo; 28 clientes continuam sem sugestão segura.
- O smoke como `authenticated` passou nas cinco tabelas: enxerga a empresa atual e oculta outra empresa do mesmo tenant.

## 1. Série, numeração e certificado

A documentação da Focus permite deixar `numero` e `serie` em branco para controle automático e recomenda esse modo. A decisão aplicada foi mais restritiva: o ERP envia a **série 2** configurada por empresa e omite somente `numero`; a Focus controla a sequência dentro da série.

Referências:

- [Campos da NF-e na Focus](https://campos.focusnfe.com.br/nfe/NotaFiscalXML.html)
- [Emissão de NF-e na Focus](https://doc.focusnfe.com.br/reference/emitir_nfe)

Foram adicionados a `c.empresa_fiscal`:

| Campo | Situação |
|---|---|
| `serie_nfe` | 2 para `SEG` e `SGU` |
| `email_fisco` | criado; permanece nulo até obter o endereço real |
| `certificado_validade_em` | criado; permanece nulo até obter a data documental |

Não existe coluna de próximo número. O payload exige uma série válida, envia `serie: 2` e o teste prova que a propriedade `numero` não existe.

A Sala de Controle consulta a validade por empresa. Com data preenchida, o alerta aparece 30 dias antes; vira crítico a 7 dias ou quando vencido. Ele é preservado entre as cinco prioridades da tela.

## 2. Backfill fiscal por XML

### Proteções

- O recorte é item ativo movimentado em OS/OV nos últimos 12 meses, sempre por `tenant_id` e `empresa_id`.
- Cada passagem cria um lote em `fiscal_backfill_lote` e uma fotografia por item em `fiscal_backfill_item` **antes** do update.
- Cada campo usa condição idempotente: origem somente quando nula; texto somente quando nulo ou vazio.
- Proposta só existe quando todos os XMLs ligados ao item concordam, depois da normalização de unidade.
- `CFOP`, `CST`, `CSOSN`, IPI, PIS, COFINS e benefício não participam do update.

### Resultado aplicado

| Campo | Aplicado com unanimidade documental |
|---|---:|
| Origem | 1.512 |
| NCM | 21 |
| CEST | 819 |
| Unidade tributável | 1.518 |

O recorte final tem **1.664 itens prioritários**. A segunda execução, novamente em duas passagens, encontrou zero proposta aplicável e zero update, confirmando a idempotência.

### Pendências finais

| Campo | Sem valor | Evidência conflitante |
|---|---:|---:|
| Origem | 151 | 16 |
| NCM | 54 | 35 |
| CEST | 845 | 19 |
| Unidade tributável | 146 | 11 |

Para origem, os 151 casos se decompõem em **135 itens sem XML ligado** e **16 com origens divergentes**. Esse é o mutirão humano real. Em NCM, os 54 vazios substituem a fotografia anterior de 51 porque o cadastro continuou recebendo itens durante o trabalho; o snapshot usado para escrever foi tirado no momento da execução.

Conflito não significa necessariamente campo vazio: a lista de conflito também chama atenção para valor já cadastrado que precisa ser comparado com documentos discordantes.

## 3. Municípios e códigos IBGE

A tabela `public.municipios_ibge` recebeu **5.571 municípios** da [API oficial de Localidades do IBGE](https://servicodados.ibge.gov.br/api/v1/localidades/municipios?orderBy=nome), com código de sete dígitos, UF, nome e nome normalizado.

O casamento principal usa nome normalizado + UF. O banco tinha ainda um legado em que o código de sete dígitos estava no campo `cidade`; 16 desses casos foram validados por código + UF, receberam o código no campo correto e recuperaram o nome oficial da cidade. Nenhuma correção foi feita por aproximação textual.

Resultado dos 57 clientes movimentados:

| Resultado | Quantidade |
|---|---:|
| Match oficial único | 40 |
| Ambíguo | 0 |
| Sem dados suficientes | 17 |

Exceções mantidas sem alteração:

| ID | Cliente | Motivo observável |
|---:|---|---|
| 71 | ARCELORMITTAL BRASIL S/A | cidade e UF ausentes |
| 199 | AZIMUTE | cidade e UF ausentes |
| 72 | BIANCOGRES CERAMICA S/A | cidade e UF ausentes |
| 40 | CLEITON PEREIRA DE LIMA | cidade e UF ausentes |
| 74 | CRANES SERVICE MANUT. E MONT. IND. LTDA | cidade e UF ausentes |
| 76 | CREMER ADESIVOS | cidade e UF ausentes |
| 77 | DEXCO REVESTIMENTOS CERAMICOS S.A | cidade e UF ausentes |
| 210 | ELETRO FORT AUTOMACAO LTDA | cidade e UF ausentes |
| 79 | FOCUS SUL TECNOLOGIA DE TERMOPLASTICOS LTDA | cidade e UF ausentes |
| 314 | INOXSUL INDUSTRIA E COMERCIO DE PRODUTOS INOXIDAVEIS LTDA | código 4209102 presente em cidade, mas UF ausente |
| 153 | JAMEC INDUSTRIA DE MAQ. E EQUIP. LTDA | cidade e UF ausentes |
| 143 | PAJOARA INDUSTRIA E COMERCIO LTDA | cidade e UF ausentes |
| 87 | SIEMENS | cidade e UF ausentes |
| 90 | STI - SOLUCOES TECNICAS IND. | cidade e UF ausentes |
| 88 | TECCIMEN INDUSTRIAL LTDA | cidade e UF ausentes |
| 213 | TERRA E MAR PARTICIPACOES LTDA | cidade e UF ausentes |
| 214 | TERRA E MAR SERVICOS EIRELI | cidade e UF ausentes |

## 4. Sugestão de `indIEDest`

As sugestões ficam em `indicador_ie_sugerido`, com regra e data, sem escrever em `indicador_ie`:

| Regra mecânica | Sugestão | Quantidade |
|---|---:|---:|
| IE somente numérica | 1 | 28 |
| IE literal `ISENTO` | 2 | 0 |
| CPF sem IE | 9 | 1 |
| Sem evidência suficiente | nenhuma | 28 |

Os 29 sugeridos dependem de confirmação humana em lote. Os outros 28 permanecem pergunta fiscal; nenhum recebeu valor definitivo por dedução.

## 5. RLS testada como a aplicação

O smoke cria duas empresas no mesmo tenant, autentica um usuário, fixa a empresa A no contexto e executa `SELECT` com o papel `authenticated`.

| Tabela | Vê empresa A | Oculta empresa B |
|---|---:|---:|
| `f.perfil_operacao` | sim | sim |
| `f.solicitacao_faturamento` | sim | sim |
| `f.solicitacao_item` | sim | sim |
| `f.documento_fiscal_emissao` | sim | sim |
| `f.documento_fiscal_evento` | sim | sim |

Resultado: **5/5** nos dois sentidos. O teste termina em rollback. A regra foi incorporada a `fluxo-migrations.md`: tabela nova leva grants no mesmo arquivo e teste de visibilidade como `authenticated`.

## 6. Por que faltam notas de saída

O caminho existente não é uma captura contínua da SEFAZ ou da Focus:

1. A interface `NfeImportModal` depende de alguém selecionar um XML.
2. O navegador chama `/api/faturamento/nfe/importar-xml`.
3. A rota valida permissões, cliente, OS, saldo e pagamentos e então chama `import_nf_entrada`, adaptando o documento para saída.
4. Se o arquivo não passar por esse fluxo, a nota não aparece em `f.documento_fiscal`.

O histórico confirma esse desenho: as saídas armazenadas começam em 17/09/2025 e as notas de setembro a dezembro/2025 foram carregadas majoritariamente em 19/03/2026. Em agosto/2026, o banco tinha 30 das 51 NF-e observadas. Portanto, não há um filtro fiscal escolhendo 30 notas; há uma **entrada manual e incompleta**, seguida de cargas retroativas pontuais.

Recomendação, sem implementação nesta tarefa:

- Durante a transição, reconciliar diariamente CNPJ + série + número/chave entre o emissor antigo e `f.documento_fiscal`, com lista explícita das ausentes.
- Importar os XMLs faltantes do emissor antigo por lote controlado, preservando o caminho atual de vínculo com OS e contas a receber.
- Para notas novas emitidas pelo ERP, manter a gravação local antes da chamada à Focus e a reconciliação assíncrona já criada; assim a existência da nota não depende de upload posterior.
- Exibir cobertura do período nos relatórios que leem `f.documento_fiscal`, para que ausência de documento não pareça faturamento zero.

## 7. Validação e aplicação

- `supabase db reset --local`: passou do zero após cada migration.
- Smoke RLS como `authenticated`: passou 5/5, nos dois sentidos.
- Pipeline NF-e: 10 cenários passaram, incluindo série presente e número ausente.
- `tsc --noEmit`: passou.
- ESLint dos arquivos alterados: passou sem erro.
- Rotas `/` e `/estoque/importar`: HTTP 200.
- `db lint`: somente os achados preexistentes do baseline; nenhum achado nas funções desta tarefa.
- `db push --dry-run` final: `Remote database is up to date.`
- Migrations `20260901140000` e `20260901141000`: aplicadas remotamente.
- `f.perfil_operacao`: nenhuma configuração fiscal foi semeada.

O script reexecutável é `npm run cadastro:sem-contador -- --compact`. Ele recarrega a tabela oficial, preserva snapshots dos lotes e executa duas passagens idempotentes.
