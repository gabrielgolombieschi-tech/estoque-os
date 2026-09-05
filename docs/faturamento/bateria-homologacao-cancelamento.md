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
