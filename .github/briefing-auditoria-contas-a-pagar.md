# Briefing — Auditoria do Contas a Pagar

> **Como usar este documento:** coloque este arquivo na raiz do seu projeto no VSCode.
> Quando iniciarmos a sessão no Claude Code, me aponte para ele ("leia o briefing")
> e continuamos exatamente deste ponto, com todo o contexto preservado.
> Este documento é a fonte da verdade do projeto — vamos atualizá-lo conforme avançamos.

---

## 1. Contexto

- **Empresa:** pequena. A **diretoria é quem valida** os resultados (não há equipe de auditoria separada).
- **Onde estão os dados:** Supabase (Postgres).
- **Como vou trabalhar:** Claude Code dentro do VSCode, com acesso direto ao banco.
- **Acesso recomendado:** **somente leitura (read-only)**. Para auditar eu só preciso ler — assim não há risco de alterar nenhum dado.
- **Origem dos dados:** ERP (Totvs/SAP).

## 2. Objetivo

Auditar tecnicamente o **contas a pagar**, separando por **departamento / centro de custo**, identificando o que está **equilibrado x desequilibrado**, e **elevar o ERP a um nível profissional**.

- **Fase inicial:** auditoria do ano corrente (base ainda "crua").
- **Depois:** processo **recorrente, mês a mês**, rodando sobre uma base já saneada.

## 3. Estratégia em fases

| Fase | O quê | Resultado |
|------|-------|-----------|
| **0 — Diagnóstico de maturidade** | Mapear como o banco está modelado e onde faltam controles/estrutura | Foto do estado atual + roteiro de melhorias priorizado |
| **1 — Saneamento** | Corrigir o que o diagnóstico apontou (estrutura, dados sujos, campos faltando) | Base confiável |
| **2 — Auditoria do ano** | Rodar todas as camadas sobre o histórico do ano | Relatório completo de apontamentos |
| **3 — Recorrência** | Transformar as consultas em rotina mensal | Auditoria automática + scorecard evolutivo |

> O **primeiro entregável é o diagnóstico (Fase 0)**, não a auditoria em si. Auditar uma base bagunçada gera ruído; primeiro entendemos e organizamos.

---

## 4. As camadas da auditoria

### Camada 1 — Qualidade e estrutura dos dados
Colunas faltando ou que deveriam existir; campos críticos vazios (departamento, vencimento, valor); tipo errado (valor ou data guardados como texto); fornecedor com grafias diferentes para o mesmo CNPJ; duplicidades; valores negativos ou zerados onde não deveria.

### Camada 2 — Dados que precisam de esclarecimento
Lista objetiva dos registros que precisam de correção ou detalhamento pelo financeiro: sem centro de custo, descrição vaga, sem fornecedor, sem classificação contábil. Entregue pronta para repasse, **com o ID de cada registro**.

### Camada 3 — Análise profunda
Variação mês a mês por categoria e departamento (ex.: "energia elétrica subiu 300% no mês Y"); concentração de fornecedores; picos de vencimento; equilíbrio x desequilíbrio entre departamentos.

### Camada 4 — Prevenção (governança de dados)
Sair de "detectar erro depois" para "impedir o erro na origem". Criar *constraints* no Supabase: campo obrigatório que não aceita nulo, valor que não pode ser negativo, centro de custo restrito a uma tabela oficial, CNPJ validado por dígito.

### Camada 5 — Conciliação e integridade contábil
Contas a pagar batendo com o razão contábil e com o extrato bancário. Idealmente **three-way match**: pedido de compra × recebimento × nota fiscal. Se um dos três não fecha, o lançamento é suspeito.

### Camada 6 — Duplicidade e fraude
Mesma nota paga duas vezes; pagamentos "redondos" suspeitos; valores logo abaixo do limite de alçada (fracionamento); fornecedor novo recebendo valor alto; conta bancária de fornecedor igual à de funcionário. Possível aplicar análise estatística (Lei de Benford) para apontar números que não parecem naturais.

### Camada 7 — Trilha de auditoria e ciclo de vida
Cada registro deve ter rastreabilidade — quem criou, quem alterou, quando — e um status bem definido: aberto → aprovado → agendado → pago → conciliado. Sem isso não existe auditoria de verdade.

### Camada 8 — Camada fiscal brasileira
Validação de nota fiscal (chave de acesso); retenções (IR, ISS, PIS/COFINS, INSS); consistência com obrigações fiscais. Erro de retenção costuma ser caro e silencioso.

### Camada 9 — KPIs e alertas automáticos
DPO (prazo médio de pagamento), % pago no prazo, % vencido, concentração de fornecedores, e gatilhos de variação (o "subiu 300%" virando alerta automático acima de um limite definido).

### Camada 10 — Scorecard de maturidade
Uma nota de saúde do ERP acompanhada mês a mês. Transforma a auditoria de "lista de problemas" em "prova de evolução" — ex.: 40% no mês 1, 75% depois das correções.

---

## 5. Como validar os resultados (método de conferência)

Nada fica no "confia em mim". Todo apontamento é verificável pela diretoria, em minutos:

1. **Âncora de conciliação:** o total de contas a pagar que eu calcular **tem que bater** com o total que o ERP mostra. Se bate, a base está sólida. Se não bate, achamos o primeiro problema.
2. **Rastreabilidade:** cada apontamento aponta para os registros exatos, com ID. Não "300 lançamentos sem centro de custo", e sim *quais são*.
3. **Amostragem:** pegar 5 itens sinalizados ao acaso e conferir na mão. Se batem, confia-se no resto.
4. **Lógica aberta:** mostro a consulta/regra usada, não só a conclusão. Nada de caixa-preta.

---

## 6. Perguntas em aberto (a definir no início da Fase 0)

- [ ] **Modelagem:** é uma tabela única de contas a pagar ou várias relacionadas (fornecedores, centro de custo, lançamentos)?
- [ ] **Conexão com o Supabase:** via MCP do Supabase, connection string do Postgres, ou client? O que já está configurado?
- [ ] **Fluxo de compra:** trabalham com **pedido de compra + nota fiscal eletrônica** no fluxo, ou o contas a pagar entra de forma mais manual? (define se three-way match e camada fiscal entram já ou depois)
- [ ] **Orçamento:** existe orçamento/meta por departamento? (se sim, dá para apontar quem estourou — análise contra meta, não só proporção)
- [ ] **Retenções:** quais impostos retidos se aplicam ao negócio?
- [ ] **Limite de alçada:** existe um valor a partir do qual o pagamento precisa de aprovação? (usado na detecção de fracionamento)

---

## 7. Próximos passos

1. Definir acesso **read-only** ao Supabase e a forma de conexão.
2. Iniciar **Fase 0 — Diagnóstico de maturidade**: eu mapeio a modelagem e respondo, com dados reais, às perguntas da seção 6.
3. Entregar o diagnóstico + roteiro priorizado.
4. A partir dele, decidir juntos o que sanear primeiro.

---

## Glossário rápido

- **Centro de custo / departamento:** rótulo que diz a qual área pertence cada gasto. Campo-chave desta auditoria.
- **DPO (Days Payable Outstanding):** prazo médio que a empresa leva para pagar seus fornecedores.
- **Three-way match:** conferência cruzada entre pedido de compra, recebimento e nota fiscal antes de pagar.
- **Constraint:** regra no banco de dados que impede a gravação de um dado inválido.
- **Lei de Benford:** padrão estatístico esperado nos primeiros dígitos de números reais; desvios podem indicar manipulação.
- **Conciliação:** conferir se dois registros que deveriam bater (ex.: contas a pagar x extrato bancário) realmente batem.
