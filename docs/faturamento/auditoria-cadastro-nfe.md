# Auditoria de cadastro para NF-e

## Escopo e critérios

Auditoria somente leitura executada em 31/08/2026 sobre o backup de 23/08/2026.

- Tenant: `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7`.
- Empresas ativas do tenant: `SEG` e `SGU`.
- Itens e clientes: somente registros com `ativo IS TRUE`, sempre vinculados ao mesmo `tenant_id` e `empresa_id` do escopo.
- Documentos fiscais: somente `deleted_at IS NULL`, no mesmo escopo.
- NCM válido: exatamente 8 dígitos depois de remover pontuação.
- Documento ausente: `documento` vazio ou sem dígitos.
- CNPJ inválido: documento com 14 dígitos cujo DV falha no algoritmo oficial ou tem todos os dígitos repetidos.
- Endereço incompleto: ausência de `logradouro`, `numero_endereco`, `bairro`, `cep` ou `uf`.

Os SELECTs reproduzíveis estão em [`auditoria-cadastro-nfe.sql`](./auditoria-cadastro-nfe.sql).

## Itens ativos

| Métrica | Resultado |
|---|---:|
| Total | 3.414 |
| Sem NCM ou com NCM diferente de 8 dígitos | **294** |
| Sem `unidade_medida` | 0 |
| Sem CFOP padrão | 3.254 |

Lacunas estruturais:

| Dado solicitado | Situação real |
|---|---|
| Origem da mercadoria (0–8) | **NÃO EXISTE — precisa ser criado**. |
| Unidade comercial | Existe apenas a coluna genérica `unidade_medida`; 0 ativos estão sem valor. |
| Unidade tributável | **NÃO EXISTE — precisa ser criado**. Não é possível calcular a métrica combinada comercial/tributável. |
| CST de ICMS | **NÃO EXISTE — precisa ser criado**. |
| CST de IPI | **NÃO EXISTE — precisa ser criado**. |
| CST de PIS | **NÃO EXISTE — precisa ser criado**. |
| CST de COFINS | **NÃO EXISTE — precisa ser criado**. |
| `cClassTrib` | Não. **NÃO EXISTE — precisa ser criado**. |

### Top 30 itens ativos sem NCM mais usados em `os_itens`

Ordenação por quantidade de linhas em `os_itens`, depois pela soma de quantidade. O vínculo exige coincidência de `tenant_id`, `empresa_id`, `item_id` e OS do mesmo escopo.

| Item ID | Código | Item | Linhas em OS | Quantidade total | OS distintas |
|---:|---|---|---:|---:|---:|
| 57 | 57 | Refeição | 13 | 54,602 | 9 |
| 59 | 59 | Frete/Correios/Transportadora | 10 | 10,000 | 8 |
| 2565 | 3930 | SINALEIRO A LED BRANCO 22MM 220V | 9 | 16,000 | 8 |
| 17 | 17 | Laudo NR-12 / Análise de Risco (execução) | 7 | 10,000 | 7 |
| 2952 | XPSUAF13AP | CONTROLADOR DE SEGURANCA HARMONY 24 V AC/DC | 6 | 11,000 | 5 |
| 55 | 55 | Diária (com pernoite) | 4 | 28,000 | 1 |
| 2561 | 35250 | SINALEIRO A LED 22MM AC 24V AD22-22DS LARANJA | 4 | 10,000 | 4 |
| 2505 | 13961 | A TOMADA PADRÃO AZ 10A 2P+T IP54 | 3 | 15,000 | 2 |
| 58 | 58 | Combustível (reembolso) | 3 | 6,165 | 3 |
| 2440 | CW070130V25 | MINICONTATOR | 3 | 5,000 | 3 |
| 71 | 71 | CREA-SC | 3 | 4,000 | 3 |
| 56 | 56 | Hospedagem | 3 | 3,000 | 1 |
| 69 | 69 | DESPESA COM PASSAGEM AEREA | 3 | 3,000 | 2 |
| 70 | 70 | LOCAÇÃO DE CARRO | 3 | 3,000 | 3 |
| 2577 | 3376 | SINALEIRO A LED 22MM BIVOLT 110/220VCA VERMELHO | 3 | 3,000 | 3 |
| 2861 | 13522438 | CONTATOR 3P AC-3 9 A 3NA 1NA+1NF 24 VCC CONEXÃO POR PARAFUSO | 2 | 4,000 | 2 |
| 1729 | 9999 | ITEM GENERICO ORCAMENTO | 2 | 2,000 | 1 |
| 2562 | 3527 | SINALEIRO A LED 22MM 24V VERDE | 2 | 2,000 | 2 |
| 3603 | 1070318 | ELETRODUTO NBR 5598 2\" | 1 | 60,000 | 1 |
| 3579 | 47 | TUBO RETANGULAR 40 X 60 X 3,00 | 1 | 54,800 | 1 |
| 3602 | 1070302 | ELETRODUTO NBR 5598 1\" | 1 | 30,000 | 1 |
| 2897 | 210 | FERRO MACICO TREFILADO | 1 | 25,940 | 1 |
| 2362 | CSAR05M024 | RELÉ DE SEGURANÇA | 1 | 18,000 | 1 |
| 3549 | 145 | INOX MACICO | 1 | 17,308 | 1 |
| 2478 | E21PEBZ4531 | BOTÃO DE PARADA DE EMERGÊNCIA COM DESBLOQUEIO DE TRAVA | 1 | 12,000 | 1 |
| 2408 | E2CP01S2V1 | BLOCO DE CONTATO AUTOMONITORADO, FIXAÇÃO DO PAINEL, AÇÃO LENTA 1NC | 1 | 6,000 | 1 |
| 2550 | VFAFTR8 | PARAFUSO DE FIXAÇÃO | 1 | 6,000 | 1 |
| 2517 | CP6206740 | DOBRADIÇA MONTADA NA PAREDE CP 60, SAÍDA HORIZONTAL | 1 | 5,000 | 1 |
| 2862 | 11992035 | BTWI - 2,5 CINZA/GREY | 1 | 4,000 | 1 |
| 2864 | 13021727 | CHAVE DE INTERTRAVAMENTO DE SEGURANÇA | 1 | 4,000 | 1 |

## Clientes ativos

| Métrica | Resultado |
|---|---:|
| Total | 76 |
| Sem CNPJ/CPF | 4 |
| CNPJ com dígito verificador inválido | 1 |
| Sem IE | 47 |
| Endereço incompleto | 35 |

O CNPJ inválido é o do cliente `CREMER S.A` (`82.641.352/0001-18`); os dígitos calculados seriam `95`.

Limitações estruturais:

- Marcação de ISENTO: **NÃO EXISTE — precisa ser criada**. Assim, os 47 registros sem IE não podem ser separados entre isentos e cadastros incompletos.
- Código IBGE do município: **NÃO EXISTE — precisa ser criado**. Não há contagem possível sem inventar coluna ou inferir pela cidade.

## Empresas

O escopo de negócio tem as 2 empresas esperadas. Os dois registros auxiliares de tenants de teste/padrão existentes no backup ficaram fora pelo filtro explícito de tenant.

| Empresa | CNPJ | IE | CRT | CNAE | Série NF-e | Próximo número | E-mail |
|---|---|---|---|---|---|---|---|
| `SEG` — ELÉTRICA SEGAU | Sim (`13.671.448/0001-89`) | Não; não há linha em `c.empresa_fiscal` | Não | Não | **NÃO EXISTE** | **NÃO EXISTE** | Não |
| `SGU` — SGU AUTOMAÇÃO | Sim (`35.739.220/0001-16`) | Sim (`260586307`) | Sim (`1`) | Não | **NÃO EXISTE** | **NÃO EXISTE** | Sim (`sguautomacao@outlook.com`) |

Para `SGU`, `regime_tributario` está como `Simples Nacional`. Não foi encontrada coluna de série ou próximo número de NF-e em `c.empresa`, `c.empresa_fiscal` ou nas demais tabelas fiscais; a coluna `f.documento_fiscal.serie` pertence à nota já registrada e não configura a numeração da empresa.

## Documento fiscal

| Métrica | Resultado |
|---|---:|
| Notas não excluídas | 2.250 |
| Com `os_id_import` preenchido | 296 |
| Menor data de emissão | 31/03/2016 |
| Maior data de emissão | 19/08/2026 |

## Bloqueio da fundação

A auditoria foi concluída, mas a migration de fundação não foi criada nem aplicada. O histórico do repositório não reproduz o banco: o shadow database falha em `20260306161000_fix_importacao_xml_revenda_finalidades.sql` por ausência de `public.parametro_importacao_xml`. O banco local principal também está parado em `20260306160000` e não contém as tabelas de negócio usadas nesta auditoria.

Antes de seguir, é necessário decidir qual estado é canônico (backup, remoto ou sequência completa de migrations) e reparar/ordenar o histórico para que um reset/diff local termine sem erro.

