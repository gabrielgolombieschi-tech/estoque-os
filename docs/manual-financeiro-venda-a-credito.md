# Manual rápido — Venda a Crédito

## Objetivo da tela

A tela **Venda a Crédito** controla serviços e materiais já entregues ao cliente, mas que ainda podem estar sem ordem de compra, sem nota fiscal ou sem título no Contas a Receber.

Fluxo normal:

**Aberto → OC recebida → Faturado → Recebido**

Depois da emissão da nota, a cobrança financeira do título também pode ser acompanhada em **Gestão de Cobrança**.

## Rotina diária do Financeiro

1. Abra **Financeiro → Venda a Crédito**.
2. Filtre primeiro por **Aberto** e pelas idades **30+ dias** e **60+ dias**.
3. Nas linhas sem retorno do cliente, clique em **Contato / nota** e registre:
   - próximo contato;
   - nome do contato no cliente;
   - observação da cobrança;
   - valor acordado, quando confirmado.
4. Quando receber a ordem de compra, clique em **OC** e informe número, data e, se houver, valor acordado.
5. Quando a nota for emitida, confira se o registro mudou automaticamente para **Faturado**. Se não mudou, use **NF** para vinculá-la.
6. Após a baixa integral do título no Contas a Receber, o status passa automaticamente para **Recebido**.

## Significado dos status

| Status | Significado | Ação esperada |
|---|---|---|
| **Aberto** | Serviço/material entregue e ainda sem OC. | Cobrar a OC e registrar o próximo contato. |
| **OC recebida** | A OC do cliente já foi informada. | Providenciar e acompanhar o faturamento. |
| **Faturado** | A nota fiscal ou o título a receber já foi vinculado. | Acompanhar o recebimento em Gestão de Cobrança. |
| **Recebido** | O título foi integralmente recebido. | Nenhuma ação. |
| **Perdido** | O valor não será recuperado. | Usar somente após confirmação do responsável. |
| **Cancelado** | O lançamento deixou de ser válido. | Manter apenas para histórico. |

## Valores exibidos

- **Estimado:** valor calculado pelo sistema a partir do orçamento ou de HH e materiais.
- **Acordado:** valor confirmado com o cliente ou recebido na OC.
- **Exposição:** usa o valor acordado; se ele não existir, usa o estimado.

O botão **Recalcular** atualiza somente o valor estimado da OS. Ele deve ser usado quando orçamento, horas ou materiais forem alterados. Um valor acordado já informado continua prevalecendo na exposição.

## Indicadores do topo

- **Exposição aberta:** total ainda em Aberto ou OC recebida.
- **Sem OC:** total no status Aberto.
- **OC recebida:** total aguardando faturamento após a chegada da OC.
- **Grupos expostos:** quantidade de grupos econômicos com exposição aberta.
- **Parados há 30+ dias:** lançamentos abertos sem solução por 30 dias ou mais.

Os indicadores respeitam os filtros aplicados na tela.

## Filtros e pesquisa

É possível pesquisar por cliente, OS, OC ou NF e filtrar por:

- grupo econômico;
- cliente;
- unidade/fábrica;
- origem;
- status;
- idade do lançamento.

Os filtros ficam registrados na URL. Assim, a visão filtrada pode ser copiada e compartilhada.

## Botões de cada lançamento

- **OC:** registra a ordem de compra e muda Aberto para OC recebida.
- **NF:** vincula uma nota fiscal de saída do mesmo cliente. A janela mostra as notas mais recentes; copie o UUID exibido ao final da nota escolhida.
- **Recalcular:** recalcula a estimativa da OS.
- **Contato / nota:** registra contato, próxima data, observação e valor acordado.
- **Perdido:** encerra como valor não recuperável, mantendo o histórico.
- **Cancelar:** cancela o lançamento, mantendo o histórico.
- **Excluir:** remoção lógica disponível somente para Admin/Diretor. Não deve ser usada no lugar de Cancelar.

## Lançamento manual

Use **Lançar / importar → Lançamento avulso** somente para saldo legado ou exceção sem OS.

Campos obrigatórios:

- cliente;
- descrição;
- valor;
- competência.

A unidade é opcional. Selecione **Avulso legado** para valores anteriores ao módulo ou **Outro** para uma exceção atual justificada.

## Importação CSV

O arquivo pode usar `;` ou `,` como separador. Cada linha precisa identificar o cliente e conter descrição e valor.

Colunas aceitas:

- cliente: `cliente_id`, `cnpj`, `documento`, `cliente` ou `cliente_nome`;
- descrição: `descricao`, `historico` ou `observacao`;
- valor: `valor` ou `valor_confirmado`;
- data: `data_competencia` ou `data`;
- unidade opcional: `unidade_id` ou `unidade`.

Exemplo:

```csv
cnpj;descricao;valor;data_competencia;unidade
83475913000272;Serviço emergencial sem OS;1500,00;2026-08-29;Fábrica 1 — Tijucas
```

Após a importação, confira a mensagem com a quantidade importada e as linhas rejeitadas.

## Exportação

O botão **Exportar CSV** baixa exatamente os lançamentos que estão aparecendo após os filtros. Antes de exportar, confirme status, cliente e período desejados.

## Cuidados importantes

- Não crie lançamento manual para uma OS normal; o sistema gera esse registro automaticamente.
- Não use **Cancelar**, **Perdido** ou **Excluir** sem confirmar o motivo.
- Sempre registre uma nova data em **Contato / nota** quando a pendência continuar aberta.
- Antes de vincular uma NF, confira cliente, número, data e valor.
- Não informe valor acordado enquanto ele não estiver confirmado pelo cliente.

## Prioridade recomendada

Trabalhe nesta ordem:

1. **Aberto 60+ dias**;
2. **Aberto 30+ dias**;
3. **OC recebida ainda não faturada**;
4. demais lançamentos em Aberto;
5. conferência de Faturado e Recebido.
