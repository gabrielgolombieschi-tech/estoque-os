# Ciclo de vida da NF-e

Implementado em 01/09/2026. Todas as ações externas desta entrega recusam qualquer emissão cujo `ambiente` não seja `HOMOLOGACAO`. Nenhum perfil de operação foi habilitado para produção.

## O que ficou disponível

- Na nota emitida, o cartão **Ciclo de vida da NF-e** mostra o estado da Focus, o relógio regressivo das 24 horas e o histórico de eventos.
- Antes do limite, o cancelamento exige justificativa de 15 a 255 caracteres. Depois do limite, o botão deixa de existir e a tela encaminha para o estorno.
- O estorno usa a implementação fiscal existente: entrada, finalidade 3, chave referenciada, valores e impostos espelhados. O CFOP é derivado da nota original e precisa ser confirmado por uma pessoa.
- A CC-e informa na própria tela o que pode e não pode ser corrigido, exige 15 a 1.000 caracteres e controla a sequência máxima de 20 eventos.
- XML e DANFE são entregues por URL assinada de 60 segundos a partir do bucket privado `nfe-documentos`. O envio por e-mail da Focus só é liberado quando os dois arquivos já estão arquivados; destinatários e data ficam no evento.
- `email_fisco` vazio gera aviso visível, sem interromper downloads ou ocultar a pendência.
- O `.pfx/.p12` pode ser enviado ao servidor apenas para leitura da validade. Arquivo e senha não são persistidos; somente `certificado_validade_em` é atualizado. O alerta aparece a 30 dias do vencimento.
- `/faturamento/nfe/excecoes` reúne as seis verificações mensais e as lacunas de série. O alerta de inutilização acende cinco dias antes do dia 10 do mês seguinte.

## Integridade e histórico

`f.documento_fiscal_evento` passou a ser append-only: `UPDATE` e `DELETE` são rejeitados por trigger. O navegador tem somente leitura; cancelamento, CC-e, e-mail e download são acrescentados pelo backend fiscal. O estado corrente da emissão continua em `f.documento_fiscal_emissao`, sem apagar as tentativas anteriores.

A inutilização tem tabela própria, `f.nfe_inutilizacao`, porque não existe documento fiscal para uma faixa nunca utilizada. A validação rejeita uma faixa se qualquer número já estiver registrado, independentemente do estado da nota, e também rejeita sobreposição com uma inutilização anterior. Uma inutilização parcial retira somente seus números da lacuna e mantém os trechos restantes no painel. Isso cobre autorizado, cancelado, denegado ou rejeitado sem tentar reinterpretar o histórico.

## Endpoints da Focus usados

| Ação | Método e rota |
| --- | --- |
| Cancelar | `DELETE /v2/nfe/{referencia}` |
| Carta de correção | `POST /v2/nfe/{referencia}/carta_correcao` |
| Inutilizar | `POST /v2/nfe/inutilizacao` |
| Enviar e-mail | `POST /v2/nfe/{referencia}/email` |

Todas as chamadas passam pela Edge Function `nfe-ciclo`, validam sessão, tenant, empresa e acesso financeiro antes de usar o token da Focus.

## Cenários validados

| Cenário | Resultado |
| --- | --- |
| Cancelamento dentro da janela | Contexto calculou `pode_cancelar=true` para autorização de uma hora; a ação externa só aparece nessa condição. |
| Cancelamento fora da janela | Contexto calculou `deve_estornar=true` para autorização de 25 horas; o botão de cancelar não é renderizado. |
| Estorno de venda interna | CFOP original `5102` derivou `1202`, foi confirmado e o snapshot foi espelhado. |
| Estorno de venda interestadual | CFOP original `6102` derivou `2202`, provando que não há CFOP fixo. |
| Carta de correção | Contrato da função compilado localmente; validações de estado, tamanho, sequência e histórico estão ativas. Chamada real à Focus depende de uma NF-e autorizada no tenant de homologação. |
| Inutilização | Lacuna 2 entre números 1 e 3 foi detectada; faixa ocupada é rejeitada e a faixa livre passou pela validação. Chamada real à Focus depende do token de homologação. |
| E-mail com anexos | A ação recusa emissão sem XML/DANFE no Storage e registra destinatários/anexos quando enfileirada. Chamada real depende de NF-e autorizada. |
| `email_fisco` vazio | O contexto e a tela mostraram aviso, sem falha silenciosa. |
| Certificado | A função de atualização e o alerta de 30 dias passaram; a rota de leitura do PFX compilou no build de produção. |
| Histórico append-only | Tentativa de `UPDATE` foi rejeitada pelo trigger. |
| Painel mensal | As seis categorias retornaram estrutura válida e a tela renderizou sem erros no console. |

Não foi fabricada uma autorização da SEFAZ para simular os quatro eventos externos. O teste local prova os portões, os cálculos, os snapshots e a persistência; o aceite ponta a ponta na Focus deve usar uma nota realmente autorizada em homologação.

## Validações executadas

- `supabase db reset --local`: passou do baseline até `20260901150000_nfe_inutilizacao_guardas.sql`.
- `supabase/tests/faturamento_ciclo_vida.sql`: passou com rollback.
- `supabase/tests/faturamento_rls_authenticated.sql`: passou com isolamento 6/6.
- `npm run test:nfe-pipeline`: 14 cenários passaram.
- `npx tsc --noEmit`: passou.
- ESLint dos arquivos alterados: passou sem erros ou avisos.
- `npm run build`: compilou e gerou `/faturamento/nfe/excecoes` e `/api/faturamento/certificado-validade`.
- `supabase functions serve nfe-ciclo`: função carregou no runtime local; preflight CORS retornou 200.
- Navegador: `/faturamento/nfe` e `/faturamento/nfe/excecoes` renderizaram; seis cartões, alerta de certificado e lacunas apareceram sem erro no console.

A suíte geral `supabase test db` ainda acusa uma falha preexistente e fora deste trabalho em `xml_import_nf_entrada_xml_integridade.sql`: a fixture tenta inserir `membership_roles.membership_id` sem a linha correspondente em `tenant_memberships`. Os dois smokes fiscais foram executados separadamente e passaram.
