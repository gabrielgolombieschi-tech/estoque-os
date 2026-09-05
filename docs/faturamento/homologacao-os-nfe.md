# Homologação — NF-e de industrialização a partir da OS (botão Faturar)

**Data:** 05/09/2026 · **Ambiente:** somente `HOMOLOGACAO` (Focus/SEFAZ SC de teste, sem valor fiscal) · **Migrations:** `20260905170000_os_nfe_industrializacao_homologacao.sql` e `20260905180000_os_notas_status_solicitacao.sql` · **Inventário prévio:** [os-nfe-inventario.md](os-nfe-inventario.md).

Todas as notas abaixo saíram pela tela `/os/[id]/faturar`, aberta pelo botão **Faturar** da OS, com Chrome headless logado como usuário do faturamento (`scripts/chrome-os-nfe-homologacao.mjs`). Nenhum valor fiscal foi gravado em `f.perfil_operacao` para 5101/6101: CFOP, CST, alíquotas, IPI e IBS/CBS vieram da fixture `f.tributacao_provisoria_homologacao` (fonte: NF-e 3527–3553 e 3766 de agosto/2026, `regras-nfe-63-combinacoes.csv`), e cada linha ficou marcada `tributacao_fonte = 'FIXTURE_HOMOLOGACAO'`. Nenhuma origem de mercadoria foi deduzida: o produto foi criado pela ação "Criar da OS" com NCM, origem, unidade tributável e CST IPI informados na tela.

## O que "OS 304" é no banco

A OS que a tela mostra como **OS 304** é `ordens_servico.id = 303` (`numero_os = '304'`, ArcelorMittal Brasil S/A, "Adicional barra no carro", orçado/HH R$ 5.266,10). O cenário fora de SC usou `ordens_servico.id = 302` (INCEPA Revestimentos Cerâmicos, Paraná). As chaves e URLs abaixo usam o `id`.

## Cenários executados na SEFAZ de homologação

| # | Cenário | Nota | Enviado | Voltou | Chave |
|---|---|---|---|---|---|
| 1 | OS 304, uma linha, saldo zerado | 2/16 | 1 × "ADICIONAL BARRA NO CARRO" (FAB-OS304-01, NCM 7326.90.90, origem 0), R$ 5.266,10, natOp `VENDA INDUSTRIALIZACAO DENTRO ESTADO`, CFOP 5101, CST 00, ICMS 17% (destinação uso e consumo), IPI CST 53, PIS/COFINS 01 1,65%/7,6%, IBS/CBS 000/000001 0,10%/0,90%, duplicata 001 em 30 dias, tPag 15 | `cStat 100`, protocolo `342260000903944`, emissão `AUTORIZADA`; saldo da OS foi a 0,00 (reservado 5.266,10) e a tela ofereceu "Marcar OS como Faturada" | `42260913671448000189550020000000161888234683` |
| 2 | Cancelamento devolvendo o saldo | 2/16 | Evento de cancelamento pela tela de ciclo de vida, justificativa de homologação | `cStat 135` ("Evento registrado e vinculado a NF-e"), protocolo `342260000903949`; emissão `CANCELADA`; saldo voltou a 5.266,10, reservado 0,00 | idem |
| 3 | OS faturada em duas notas, parcial A | 2/17 | 1 × FAB-OS304-01, R$ 2.000,00, 5101, 17%, IPI 53, duplicata 30 dias, infCpl "nota parcial A da OS 304" | `cStat 100`, protocolo `342260000903955`, ICMS 340,00, IBS 2,00, CBS 18,00, vNF 2.000,00; saldo 3.266,10, OS continua **em andamento** | `42260913671448000189550020000000171462106939` |
| 4 | Parcial B + painel com IPI (caso NF-e 3766) | 2/18 | 1 × "ADICIONAL BARRA NO CARRO" (FAB-OS304-02, NCM 8537.10.19, origem 0, CST IPI 50, 9,75%), R$ 3.266,10, 5101, 17% | `cStat 100`, protocolo `342260000903957`, ICMS 555,24, IPI 318,44, vNF 3.584,54, duplicata 001 = 3.584,54; saldo da OS 0,00 com as duas parciais reservadas | `42260913671448000189550020000000181585345866` |
| 5 | Destinatário fora de SC (6101) | 2/19 | OS 302, INCEPA (PR, indIEDest 1), 1 × "PROTEÇÕES LINHA ESTEIRA" (FAB-OS303-01, NCM 8537.10.19, origem 0), R$ 1.500,00, natOp `VENDA INDUSTRIALIZACAO FORA DO ESTADO`, CFOP 6101, idDest 2, ICMS 12% | `cStat 100`, protocolo `342260000903966`, ICMS 180,00, IBS 1,50, CBS 13,50, vNF 1.500,00 | `42260913671448000189550020000000191843336870` |

Após a bateria, as homologações 2/17, 2/18 e 2/19 foram **abandonadas** pela ação "abandonar homologação" da lista de notas da OS (`f.fn_solicitacao_nfe_abandonar_homologacao`): a NF-e de teste continua autorizada na SEFAZ de homologação, a solicitação vai a `CANCELADA`, um evento `CANCELAMENTO/LOCAL` com `origem = ABANDONO_HOMOLOGACAO` fica no histórico e o saldo volta. Estado final: OS 304 (id 303) orçado 5.266,10 · faturado 0,00 · reservado 0,00; OS 302 orçado 11.752,34 · reservado 0,00. Nenhuma das duas está `Faturada`.

Arquivos: DANFE e XML de cada nota estão no bucket privado em `<tenant>/<empresa>/NFEH-<solicitacao>/danfe.pdf|nfe.xml` e abrem pela tela da OS (`nfe-ciclo`, ação `ARQUIVO`). O XML da 2/18 confere com o DANFE: `natOp`, `idDest 1`, `indFinal 1`, `indPres 9`, `CFOP 5101`, `CST 00`, `pICMS 17`, `CST IPI 50`, `pIPI 9.75`, `vIPI 318.44`, `cEnq 999`, `nDup 001`, `dVenc 2026-10-05`, `indPag 1`, `tPag 15`, protocolo e `cStat 100` no `protNFe`.

## Cenários cobertos por teste automatizado (sem chamar a Focus)

Estão em `supabase/tests/faturamento_os_nfe_homologacao.sql` (roda no banco local, passa) e `scripts/test-nfe-pipeline.mjs` (77 cenários, passa):

| Cenário | Onde | Resultado |
|---|---|---|
| Rejeição proposital com NCM vazio | teste SQL, produto `SEM-NCM` | A conferência recusa antes da Focus: `Linha 1: produto SEM-NCM sem NCM de 8 dígitos no cadastro fiscal (corrija em /itens)`. Não existe rascunho de emissão, logo nada chega à SEFAZ |
| Valor acima do saldo | teste SQL | `Total das linhas (R$ 1.200,00) acima do saldo da OS (R$ 1.000,00)`; bloqueia antes da Focus |
| Retry com a mesma referência | teste SQL (`fn_nfe_preparar_documento_solicitacao` duas vezes) | A segunda chamada devolve o mesmo `documento_fiscal_id` e a mesma referência `NFEH-<solicitacao>`; uma emissão só |
| Webhook duplicado / callback tardio | `test-nfe-pipeline.mjs` (cenários de callback repetido e tardio) e `fn_nfe_aplicar_retorno` idempotente por referência | O segundo retorno não cria evento nem altera a emissão já autorizada |
| Retorno de homologação não cria título nem consome saldo real | teste SQL | Documento fica `RASCUNHO`, nenhum `financeiro_titulo`, reserva de 600 até o abandono |
| Faturada só com documento emitido e saldo zero | teste SQL (`os_faturar` + `fn_os_pronta_para_faturada`) | Documento importado + saldo zero → Faturada; nota parcial → OS em andamento |
| RLS por empresa | teste SQL | `fn_os_notas` de outra empresa devolve zero linhas; `criar_item_fabricado_da_os` exige papel do faturamento |
| Origem vazia bloqueia | teste SQL | `Origem da mercadoria obrigatória` na criação do produto; conferência recusa `fiscal_itens.origem` nula |
| UF confirmada ≠ UF do cliente, presença 0, destinação em branco | teste SQL | Recusados com o nome do campo |

## Cenário não executado

**Pedido 749919 como quatro produtos em quatro notas.** Nenhuma OS, documento fiscal ou pedido de compra com `749919` existe no banco (`ordens_servico.pedido_compra`, `descricao_servico`, `observacoes`, `f.documento_fiscal`). Sem a OS de referência o cenário não foi rodado. O mecanismo já está provado pelos cenários 3 e 4 (duas notas parciais na mesma OS, cada uma com produto próprio, saldo entre elas): quatro notas usam o mesmo caminho, uma linha por nota. Quando a OS for indicada, `scripts/chrome-os-nfe-homologacao.mjs --os <id> --valor <parcela> --criar "..."` quatro vezes reproduz o cenário.

## O que a tela faz e o que ainda não faz

- Cabeçalho, linhas por valor, busca/criação de produto fabricado, operação (perfil vigente ou fixture com pendência do contador), destinação, presença, frete, pagamento com parcelas, observação, prévia com impostos e bloqueios nomeados, emissão, acompanhamento por Realtime + polling, lista de notas com DANFE/XML/detalhe, abandono de homologação e "Marcar OS como Faturada".
- Bloqueios do botão Faturar na OS: papel sem permissão, OS cancelada, OS interna (cliente Elétrica Segau), OS faturada, saldo zero sem rascunho aberto.
- Homologação não cria título a receber (decisão A de 02/09/2026 mantida); o AR do retorno de produção continua provado pelo teste de produção do pipeline.
- Produção continua fechada para 5101/6101: `fn_nfe_producao_pronta` responde `false` e o trigger `trg_bloquear_nfe_producao_sem_perfil_liberado` recusa.
- Decisão operacional registrada: `indicador_ie = 1` foi confirmado na tela `/clientes/cadastro-fiscal` para ArcelorMittal (cliente 42) e INCEPA (cliente 193) para permitir a homologação; ambos têm IE ativa no cadastro. Confirmar com o cliente antes da primeira nota real.

## Perguntas que sobraram para o contador

A lista numerada da "rodada 2" não chegou nesta sessão (só o preâmbulo que cita a correção nº 4). Os itens abaixo estão redigidos com o que se sabe deles; conferir a numeração com o documento original.

1. **Item 4 da rodada 2 — benefício/redução amarrado ao CFOP.** Hoje o ERP decide o benefício SC820006 por NCM elegível (três NCM do documento) mais carga efetiva de 12%, nunca pelo CFOP. As notas de industrialização (5101/6101) saíram **sem** `cBenef` e sem redução. Confirmar: o benefício se aplica a produto fabricado pela Segau (painel NCM 8537.10.19/8537.10.20) ou só à revenda?
2. **Item 2 da rodada 2 — alíquota interna 12% × 17%.** Manutenção ficou em 12% por decisão do responsável; venda para uso e consumo/ativo do adquirente ficou em 17% (RICMS/SC art. 26, I). Precisa da confirmação formal para o perfil 5101, inclusive para contribuinte que compra painel para o próprio ativo.
3. **Item 8 da rodada 2 — cEnq e CST do IPI do produto fabricado.** As notas de agosto usam `cEnq 999`. Para painel fabricado saiu CST 50 com 9,75% (NF-e 3766) e para a maioria CST 53. Qual o `cEnq` correto para cada caso e quando o produto fabricado é tributado (50) ou não (53)?
4. **NCM do sistema.** Lista completa da Seção XIX (e demais) para os produtos que a Segau fabrica e vende hoje, para o cadastro fiscal e para a lista de NCM elegíveis. Não foi acrescentado nenhum NCM por analogia.
5. **Redução de base para produto fabricado.** Painéis e proteções fabricados (8537.10.19) entram em alguma redução de base (automação/informática) ou seguem 17%/12% cheios?
6. **Interestadual para consumidor final contribuinte (6101, PR).** A nota 2/19 saiu com 12% e `indFinal 1`. Há DIFAL a destacar ou recolher pela Segau, ou fica por conta do destinatário contribuinte?
7. **NCM da linha "Adicional barra no carro".** Foi usado 7326.90.90 (obra em ferro/aço) na homologação. Confirmar a classificação da peça fabricada.
8. Pendências anteriores que continuam abertas: Lucro Real anual × trimestral (IRPJ/CSLL), valor aproximado dos tributos (IBPT) no DANFE, promoção do `cEnq` da fixture para os perfis.

## Como reproduzir

```
node scripts/chrome-os-nfe-homologacao.mjs --os 303 --cliente 42 --valor 2000 --destinacao USO_CONSUMO --produto FAB-OS304-01 --dias 30 --obs "Homologacao: nota parcial A"
node scripts/chrome-os-nfe-homologacao.mjs --os 303 --valor 3266,10 --criar "ADICIONAL BARRA NO CARRO|85371019|0|UN|50|9,75" --obs "painel com IPI"
node scripts/chrome-os-nfe-homologacao.mjs --os 302 --cliente 193 --valor 1500 --criar "PROTEÇÕES LINHA ESTEIRA|85371019|0|UN|53|"
node scripts/chrome-os-nfe-abandonar.mjs 303        # devolve o saldo das homologações da OS
node scripts/chrome-os-nfe-arquivos.mjs 303 <pasta> 17 18   # baixa DANFE/XML pela tela
docker run --rm -i -e PGPASSWORD=postgres postgres:16-alpine psql -h host.docker.internal -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -q < supabase/tests/faturamento_os_nfe_homologacao.sql
node scripts/test-nfe-pipeline.mjs
```
