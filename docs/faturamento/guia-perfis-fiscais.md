# Guia do usuário — Perfis fiscais da NF-e

Para quem opera o faturamento e fala com o contador. Tela: **Faturamento → Perfis fiscais** (`/faturamento/perfis`).

## O que é um perfil fiscal

Um perfil é a "receita" que o sistema usa para montar os impostos de uma NF-e. Cada perfil vale para **uma combinação**:

- empresa emitente (SEG ou SGU);
- natureza da operação (venda de mercadoria de terceiros, industrialização, devolução, remessa...);
- CFOP;
- destino (dentro de SC ou outra UF);
- origem da mercadoria (0 nacional, 2 estrangeira adquirida no mercado interno, etc.);
- destinação que o cliente dá à mercadoria (revenda, manutenção, uso e consumo...).

Na hora da conferência da nota, o sistema procura o perfil que casa com essa combinação e trava os campos fiscais com os valores dele (CFOP, CST, alíquota, PIS/COFINS, IBS/CBS). O operador não digita imposto: ele confirma o que o perfil traz.

Exemplo do primeiro perfil liberado, em 05/09/2026:

| Combinação | Valor |
|---|---|
| Código | `SEG-VENDA-TERCEIROS-SC-5102-O2-CST00` |
| Operação | venda de mercadoria de terceiros, dentro de SC, CFOP 5102 |
| Origem | 2 (estrangeira, adquirida no mercado interno) |
| Destinação | revenda, insumo, manutenção ou consignado |
| ICMS | CST 00, base integral, 12% |
| PIS / COFINS | CST 01, 1,65% e 7,6% |
| IBS / CBS 2026 | CST 000, cClassTrib 000001, IBS UF 0,10%, IBS mun. 0%, CBS 0,90% |
| Benefício | nenhum (NCM 8537.10.20 não tem redução de base) |

## O que a tela faz e o que não faz

**Faz:**

- mostra todos os perfis da empresa ativa (67 hoje) e o estado de cada um;
- registra a **revisão fiscal** dos campos de IBS/CBS, com justificativa e trilha de auditoria;
- **libera** um perfil para produção, amarrado a uma NF-e de homologação que provou a receita.

**Não faz:**

- não cadastra CFOP, não cria perfil novo, não edita CFOP, CST ou alíquota de ICMS. Esses valores nascem de cadastro controlado (migração feita pelo desenvolvimento a partir da resposta do contador). Se aparecer uma operação sem perfil, a tela de conferência da nota avisa "nenhum perfil fiscal para..." e a nota não sai. Aí o caminho é a seção "Quando pedir um perfil novo", abaixo.

## Como ler um perfil

Os oito cartões do cabeçalho:

| Cartão | O que mostra |
|---|---|
| Destino | INTERNA · SC, ou INTERESTADUAL com as UFs atendidas |
| CFOP | CFOP interno (dentro de SC) e externo (outra UF) |
| ICMS | CRT da empresa, origem da mercadoria e CST (ou CSOSN no Simples) |
| PIS / COFINS | CST e alíquotas |
| Base ICMS | modalidade da base e alíquota |
| cBenef | código do benefício fiscal, ou SEM_BENEFICIO |
| Emissão | finalidade (1 normal) e consumidor final (0 não, 1 sim) |
| Evidência | se há nota real de referência vinculada, e a faixa |

As etiquetas na lista da esquerda:

| Etiqueta | Significado |
|---|---|
| REVISAO | perfil válido, mas cada nota exige confirmação humana na conferência |
| BLOQUEADO | perfil nunca monta nota; falta decisão do contador (IPI, produzido × revendido, cabo elegível...) |
| AUTOMATICO | reservado para perfis totalmente confirmados; nenhum hoje |
| FORA DE PRODUCAO | só emite em homologação (teste) |
| PRODUCAO | liberado para nota real |

## Passo a passo para colocar um perfil em produção

Ciclo completo: **revisar → testar em homologação → liberar**. Toda vez que uma regra muda, o ciclo recomeça.

### 1. Conferir a receita com o contador

Antes de mexer na tela, confirmar com o contador, para aquela combinação:

- CFOP e CST de ICMS;
- alíquota de ICMS e de quem depende (em SC: 12% para contribuinte que revende, industrializa, usa como insumo ou manutenção; 17% para uso e consumo, ativo imobilizado ou não contribuinte);
- se o NCM tem benefício. Hoje só três NCMs têm redução de base em SC: 8536.49.00, 8536.50.90 e 8544.49.00 (cBenef SC820006). Não estender por analogia;
- CST e alíquotas de PIS/COFINS;
- CST de IPI e enquadramento (cEnq);
- CST IBS/CBS e cClassTrib (em 2026: 000 e 000001 para revenda, com 0,10% / 0% / 0,90%).

Se o contador mudar qualquer valor de ICMS, CFOP, PIS/COFINS ou IPI, pare aqui e peça ao desenvolvimento um perfil novo ou ajustado. A tela não edita esses campos.

### 2. Registrar a revisão (bloco "Campos IBS/CBS sujeitos a revisão")

Só quando os valores de IBS/CBS mudarem ou quando o perfil nunca foi revisado.

1. Selecionar o perfil na lista da esquerda (buscar pelo código, nome ou natureza).
2. Preencher os seis campos: CST IBS/CBS, cClassTrib, versão da tabela, alíquota IBS UF, IBS municipal e CBS. O botão "Aplicar referência homologada" preenche com a última referência usada; mesmo assim, conferir.
3. Escrever a **justificativa** (15 a 1.000 caracteres): a fonte (documento do contador, data), a decisão e por que os valores se aplicam.
4. Clicar em **"Salvar revisão e desabilitar produção"**.

Atenção: salvar uma revisão **sempre desliga a produção** do perfil. Isso é proposital: uma receita alterada precisa ser testada de novo antes de gerar nota real. Não clique nesse botão "para conferir".

### 3. Emitir uma NF-e de homologação com o perfil

1. Abrir uma OV que use esse perfil (mesma empresa, natureza, destino, origem e destinação).
2. Na aba Faturamento da OV: **Faturar → Salvar rascunho → Conferir e emitir em homologação**.
3. Na conferência: escolher destino, destinação da mercadoria, presença do comprador, frete, forma de pagamento. Os campos com cadeado vêm do perfil.
4. Emitir e aguardar **"Autorizada em homologação"**.

A nota de homologação não tem valor fiscal, não gera contas a receber e não consome saldo da OV enquanto não for abandonada. Ela existe só para provar a receita.

### 4. Liberar para produção (bloco "Liberação separada para produção")

1. Voltar em Perfis fiscais e selecionar o perfil.
2. Em "Solicitação da NF-e homologada", escolher a nota de homologação do passo 3. A tela confirma "autorizado em ... · posterior à última revisão". Se disser que é anterior, a nota foi emitida antes da revisão e não serve.
3. Escrever a **justificativa da liberação** (15 a 1.000 caracteres). Exemplo: "Revenda interna SC, origem 2, 12%, conferida na NF-e 2/14 de homologação em 05/09/2026".
4. Marcar **"Confirmo a equivalência com esta NF-e AUTORIZADA em homologação..."**.
5. Clicar em **"Conferir e liberar para esta homologação"**.

O sistema confere sozinho antes de aceitar: revisão registrada, nota de homologação autorizada depois dela, certificado digital válido, todos os campos do perfil preenchidos, seis valores de IBS/CBS iguais entre perfil, solicitação e XML autorizado. Se faltar algo, ele lista a pendência.

Resultado: a etiqueta vira **Liberado** e "Última decisão de produção" registra data e hora. A liberação fica amarrada àquela solicitação e àquele documento.

### 5. O que acontece depois

- A liberação do perfil **não emite nada**. A nota real só sai da OV, pelo botão de produção, com confirmação na hora.
- O botão de produção só aparece quando, além do perfil liberado, existem token de produção da Focus, certificado válido e a chave de produção ligada.
- Qualquer nova revisão do perfil desliga a produção de novo. Ciclo recomeça no passo 2.

## Quando pedir um perfil novo

Situações em que a nota vai travar por falta de perfil:

- operação nova (devolução, remessa para conserto, venda à ordem, industrialização);
- venda para outra UF que ainda não tem perfil;
- mercadoria com origem diferente (0, 1, 2, 6...) da que o perfil cobre;
- cliente não contribuinte fora de SC (exige perfil próprio de DIFAL);
- NCM com benefício que ainda não está cadastrado.

O pedido precisa levar a resposta do contador com todos os itens do passo 1. Sem isso o perfil nasce BLOQUEADO.

## Perguntas prontas para o contador

1. Nesta operação, qual CFOP e qual CST de ICMS?
2. A alíquota interna é 12% ou 17%, e depende do que o cliente declara na ordem de compra?
3. O NCM tem redução de base ou outro benefício? Qual cBenef e qual base legal deve ir nas informações complementares?
4. CST e alíquotas de PIS/COFINS na saída?
5. CST de IPI e código de enquadramento?
6. CST IBS/CBS e cClassTrib para esta natureza?
7. Há texto obrigatório nas informações complementares (suspensão, diferimento, base reduzida)?

## Perfis liberados

| Data | Perfil | Evidência | Quem |
|---|---|---|---|
| 05/09/2026 | `SEG-VENDA-TERCEIROS-SC-5102-O2-CST00` | NF-e 2/14 homologação, protocolo 342260000903496 | responsável pelo faturamento |
