# Bateria de homologação — cancelamento de NF-e

Os dois cenários abaixo são independentes da NF-e substituta série 2 nº 2. Todas as ações devem ocorrer pela tela **NF-e → Ciclo de vida**, sempre em `HOMOLOGACAO`.

## CAN-HOM-01 — cancelamento dentro do prazo

Pré-condições:

- usar uma NF-e de homologação criada exclusivamente para este cenário;
- status `AUTORIZADA` e menos de 24 horas desde a autorização;
- não usar a NF-e série 2 nº 1 nem a substituta série 2 nº 2.

Execução:

1. Abrir a NF-e recém-autorizada na tela de detalhe.
2. Informar justificativa entre 15 e 255 caracteres.
3. Acionar **Cancelar homologação na SEFAZ** e confirmar o diálogo.
4. Atualizar a tela e conferir o histórico.

Resultado esperado:

- Focus/SEFAZ retorna cancelamento autorizado;
- emissão e solicitação ficam `CANCELADA`;
- evento imutável `CANCELAMENTO/AUTORIZADA` contém o protocolo de cancelamento;
- a evidência é transcrita em `homologacao-execucao.md`.

## CAN-HOM-02 — cancelamento fora do prazo

Pré-condições:

- NF-e série 2 nº 1 permanece `AUTORIZADA`;
- executar somente depois de **03/09/2026 18:56:10 (America/Sao_Paulo)**;
- confirmar que a tela informa o encerramento da janela de 24 horas.

Execução:

1. Abrir a série 2 nº 1 na tela de detalhe.
2. Acionar **Testar rejeição fora do prazo (homologação)**.
3. Ler o alerta e confirmar a chamada real somente para este cenário.
4. Atualizar a tela e conferir o histórico.

Resultado esperado:

- Focus/SEFAZ rejeita o cancelamento por prazo excedido;
- a NF-e série 2 nº 1 continua `AUTORIZADA`;
- evento imutável `CANCELAMENTO/REJEITADA` preserva a resposta do provedor com `cenario_homologacao=CANCELAMENTO_FORA_PRAZO`;
- a mensagem é exibida em português e a ação especial deixa de ser oferecida;
- a tela mantém o caminho para `999 - ESTORNO DE NF-E NAO CANCELADA NO PRAZO LEGAL`.

Se a consulta à Focus ficar inconclusiva, o evento permanece `ENVIANDO` e o mesmo botão deve reconciliar o estado antes de qualquer novo `DELETE`. Se, de forma inesperada, a SEFAZ autorizar o cancelamento, o sistema deve refletir o estado real como `CANCELADA` em vez de esconder o resultado.

## Execução em 05/09/2026

Ambos os cenários foram executados pela tela, dirigida por `scripts/chrome-nfe-cancelamento-hom.mjs`.

### CAN-HOM-02 na NF-e 2/1 — SEFAZ rejeitou, sistema errou e foi corrigido

- Chamada real às 08:20 (America/Sao_Paulo), 38 horas depois da autorização.
- Resposta da Focus: `status=erro_cancelamento`, `status_sefaz=501`, `Rejeicao: Prazo de Cancelamento Superior ao Previsto na Legislacao`. É exatamente o resultado esperado e fundamenta a natureza `999 - ESTORNO DE NF-E NAO CANCELADA NO PRAZO LEGAL`.
- **Defeito encontrado:** a Focus devolveu esse corpo com HTTP 2xx, e `nfe-ciclo` decidia pelo HTTP. O evento foi gravado como `CANCELAMENTO/AUTORIZADA`, a emissão virou `CANCELADA` e o documento virou `CANCELADA`. Além disso, `normalizarFocus` classificava qualquer status contendo `cancel` (inclusive `erro_cancelamento`) como `CANCELADA`.
- **Correções:** a decisão passou a ser pelo corpo (`status = "cancelado"`), o normalizador testa `erro`/`rejeit` antes de `cancel`, e a migration `20260905100000` acrescentou o evento corretivo `CANCELAMENTO/REJEITADA` (com `correcao_de_evento_id`) e devolveu a emissão a `AUTORIZADA`. A NF-e 2/1 permanece autorizada na SEFAZ.

### CAN-HOM-01 na NF-e 2/12 — cancelada na SEFAZ

- Chamada real às 08:21, dentro da janela (autorizada em 04/09 16:56).
- Resposta: `status=cancelado`, `status_sefaz=135`, `Evento registrado e vinculado a NF-e`, `numero_protocolo=342260000903334`, XML de cancelamento disponível na Focus.
- Emissão e solicitação ficaram `CANCELADA`. O protocolo ficou apenas dentro de `resposta.numero_protocolo` porque a Edge não lia essa chave; passou a ler.

### Regra nova: cancelamento de homologação não toca o documento

O cancelamento gravava `f.documento_fiscal.nfe_status='CANCELADA'`; como o documento tem número, ele passava a contar como "documento que existiu" no livro de saídas e no analítico. Homologação não tem valor fiscal: a partir da migration `20260905100000` o documento permanece `RASCUNHO`, só a emissão muda, e o analítico ignora qualquer documento cuja única emissão seja de homologação. As 2/1 e 2/12 foram devolvidas a `RASCUNHO`.

### Pendente

- Repetir CAN-HOM-02 com a Edge corrigida: a tela já mostra o cenário como executado (o evento corretivo carrega `cenario_homologacao`), então uma nova tentativa exige outra NF-e fora da janela. Opcional.
- CC-e executada de verdade na NF-e 2/13 às 08:32: `CARTA_CORRECAO #1`, `AUTORIZADA`, `status_sefaz=135`, "Evento registrado e vinculado a NF-e". Script: `scripts/chrome-nfe-cce-hom.mjs`.
- E-mail com anexos não é testável em homologação por desenho: a tela nunca envia documento de teste ao cliente. Fica para a primeira nota real.
