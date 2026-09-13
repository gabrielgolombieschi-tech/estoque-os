# Tablet compartilhado de apontamento (PIN)

Modo do aplicativo mobile para um tablet fixo na produção: cada colaborador digita o
próprio PIN de quatro números, escolhe cliente e OS, informa a data e a duração
(horas e minutos), confere e confirma. A hora entra na mesma `apontamentos_horas`
de sempre, pendente de aprovação, e aparece nos relatórios e custos como qualquer outra.

Migrations: `supabase/migrations/20260911250000_tablet_apontamento_pin.sql` e
`supabase/migrations/20260911260000_tablet_classificacao_janela_pins.sql`.
Teste SQL: `supabase/tests/tablet_apontamento_pin.sql`.

## Como funciona

- **Conta do tablet**: uma conta do sistema só para o aparelho, com perfil **Apontador**
  ou **Painel de TV** na empresa e **sem** colaborador vinculado. É o mesmo aplicativo de
  sempre: quando essa conta entra, o app abre direto na tela do PIN, sem abas.

  Os dois perfis valem desde 13/09/2026 (`20260913120000`), por decisão do Gabriel: o
  painel de TV roda no navegador e o tablet no aplicativo, e ele quis os dois no mesmo
  login. O perfil não é por plataforma, é um por empresa no banco e vale nos dois lugares,
  então a única forma de juntar era aceitar os dois aqui. **Isso afrouxa uma proteção**:
  com Apontador, `can()` nega tudo e a senha do tablet não serve para mais nada, o que
  importa porque o aparelho fica solto na fábrica. Com Painel de TV, quem tiver essa senha
  abre as telas de televisão num navegador — e o que se vê ali já está pendurado numa TV na
  parede. Foi com esse argumento que a troca foi aceita. Qualquer outro perfil continua
  recusado, e a conta continua tendo que ser de aparelho, sem colaborador.
- **PIN**: quatro dígitos, aceita zero inicial, único por empresa (inativos contam, para
  o PIN não colidir se a pessoa voltar). Guardado só como hash bcrypt em
  `colaboradores_pin`, tabela sem policy. Só colaborador **ativo** é identificado.
  Só **Admin e Diretor** definem, redefinem ou removem PIN (a coordenação não).
- **Identificação temporária**: PIN aceito vira uma linha em `tablet_sessoes` com um
  token que fica só na memória do app. Expira (10 minutos deslizantes no servidor, teto
  de 12 horas) e é invalidado ao finalizar, ao trocar de pessoa, na inatividade e quando
  o PIN é redefinido ou removido.
- **Inatividade**: sem toque por N segundos (padrão 60, configurável por tablet entre 15
  e 900) a tela esquece a pessoa e volta ao PIN. Gravação em andamento pausa o contador.
- **Bloqueio**: 5 PINs errados seguidos bloqueiam o aparelho por 5 minutos (dobrando a
  cada erro seguinte, até 40). PIN certo zera o contador. O PIN nunca vai para log.
- **Lista de OS**: RPCs próprias do tablet (`app_tablet_os_agrupado_cliente`,
  `app_tablet_os_do_cliente`): todas as OS **em andamento** da empresa, agrupadas por
  cliente, **sem OS de HH** e sem valores comerciais. OV nunca entra.
- **Datas**: hoje e os **15 dias corridos anteriores**, inclusive, no fuso
  `America/Sao_Paulo` (no dia 20, do dia 5 ao dia 20). Abre sempre em hoje; futuro e
  datas mais antigas são bloqueados na tela e no servidor (`data_fora_da_janela`).
  Retroativo acima de 7 dias continua pedindo confirmação. Competência fechada segue
  barrada pelo trigger existente. Ao trocar a data, a tela refaz a consulta: lançamentos
  do colaborador naquela OS, subtotal da OS e total geral do dia.
- **Classificação automática da hora**: o colaborador informa só horas e minutos. O
  servidor (`fn_tablet_classificar`) aplica a mesma regra que a tela web de apontamentos
  já sugere (`app/apontamentos/page.tsx`, `suggestionFor`):

  | Data | Tipo de hora |
  |---|---|
  | Feriado (`public.feriados`) | `EXTRA_100` |
  | Domingo | `EXTRA_100` |
  | Sábado | `EXTRA_50` |
  | Dia útil, até 9 h no lançamento | `NORMAL` |
  | Dia útil, acima de 9 h | `NORMAL` 9 h + `EXTRA_50` no excedente (duas linhas) |

  Os tipos vêm de `tipos_horas` da empresa pelos códigos `NORMAL`, `EXTRA_50` e
  `EXTRA_100`. Se algum deles não existir ativo, o lançamento é recusado com a mensagem
  "Falta cadastrar o tipo de hora X ativo em Tipos de hora" — nada entra como Hora normal
  por falta de configuração. A tela mostra, ao lado da data, "Sábado · Hora extra 50%",
  "Feriado: Independência do Brasil · Hora extra 100%" etc., e a prévia das partes antes de
  confirmar.
- **Calendário de feriados**: `public.feriados` estava vazia em produção. A migration
  20260911260000 grava 2026 e 2027 com o mesmo calendário oficial que o web já usava em
  `lib/datas/feriadosJoinville.ts` (nacionais e municipais de Joinville, sem pontos
  facultativos). Efeito colateral: `home_sala_controle` e a tela de HH passam a
  considerar esses feriados nos dias úteis, como o web já fazia por conta própria. Não há
  tela para manter a tabela: 2028 em diante entra por migration ou por um admin.
- **Lançamento**: `app_tablet_lancar_horas(token, os, data, horas, minutos, chave)`.
  3h30 vira `horas = 3.50`. Valida no servidor: sessão, colaborador ativo, taxa vigente,
  OS da empresa, tipo OS, não HH, em andamento, janela de datas, 1 minuto a 24 horas.
- **Idempotência**: a tela gera uma chave (uuid) ao abrir a conferência; reenviar a mesma
  chave devolve o resultado já gravado sem criar outra linha (`tablet_lancamentos`, com
  todas as linhas do envio em `apontamento_ids`).
- **Rastreabilidade**: `apontamentos_horas.colaborador_id` = quem digitou o PIN
  (beneficiário); `criado_por_user_id` = conta do tablet (executor);
  `tablet_sessao_id` = a sessão do PIN. `audit_log` continua pelo trigger de sempre.
- **Descrição**: o tablet não pede descrição. Ao editar no app ela passa a ser exigida
  como hoje.

## OS encerrada

No tablet só OS em andamento recebe hora. Se a OS fechar enquanto a pessoa preenche, a
confirmação para com "Esta OS já foi encerrada. Procure a coordenação para lançar estas
horas." O caminho para OS encerrada é o do sistema web (Apontamentos), que aceita só
**Coordenação, Diretor, Admin ou o responsável da OS** (`web_criar_apontamentos_horas`).

## Como configurar

1. **Conta do tablet**: Admin › Usuários (ou "Novo usuário" no app). Perfil **Apontador**
   nesta empresa, sem vincular a colaborador. Se a mesma conta também vai tocar as
   televisões, use **Painel de TV** no lugar de Apontador: os dois são aceitos, e aí é um
   login só para as duas coisas. A tela de autorização lista os dois perfis.
2. **Autorizar**: sistema web, Cadastros › **Tablets de apontamento** (Admin ou Diretor).
   Escolha a conta, dê um nome ("Tablet da produção") e o tempo de inatividade.
3. **Tablet**: instale o app e entre com a conta do tablet. Ele abre na tela do PIN.
   Para desconectar o aparelho: engrenagem "Tablet" na tela do PIN e a senha da conta.
4. **PINs** (Admin ou Diretor):
   - **Pelo app**: Perfil › Configurações › **PINs do tablet**. Escolha o colaborador,
     entregue o celular; a própria pessoa digita o PIN duas vezes. Ninguém precisa saber o
     PIN dela. Ali também se remove o PIN.
   - **Pelo web**: Cadastros › Colaboradores › Editar, campo "PIN do tablet".
5. **Taxa vigente**: como em todo apontamento, o colaborador precisa ter valor/hora
   vigente na data; sem taxa o tablet diz para procurar a coordenação.
6. **Tipos de hora**: `NORMAL`, `EXTRA_50` e `EXTRA_100` ativos na empresa (hoje existem).

## Tarefas no tablet

Depois do PIN o tablet oferece **Apontar horas**, **Minhas tarefas** e **Finalizar**.
"Minhas tarefas" mostra as tarefas do colaborador identificado (agendadas e sem
data) e permite marcar como concluída, com confirmação. O tablet não cria, cancela
nem reagenda tarefa e não vê aprovações. Regras, permissões e telas do web e do app
estão em [tarefas.md](tarefas.md).

**Ele conclui a parte dele, não a tarefa.** Desde a migration
`20260912220000_tarefas_participantes_dias_e_ausencias.sql` uma tarefa pode ter
várias pessoas, e cada uma fecha a sua parte: a conclusão é gravada em
`tarefas_participantes.concluida_em`, amarrada à sessão do PIN
(`tarefas_participantes.concluida_por_sessao_id`), e a tarefa só vira `concluida`
quando a última parte fecha. Quando a tarefa tem mais gente, a tela avisa, para a
pessoa não sair pensando que fechou o serviço inteiro.

Folga, férias e outras ausências também aparecem na lista, porque moram na mesma
tabela; o tablet mostra o rótulo da ausência no lugar da OS e do cliente, e o tempo
(dias ou horas), já que não existe OS para mostrar.
