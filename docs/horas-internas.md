# Horas internas (hora fora de OS)

Estado: **implementado em 14/09/2026** (migration `20260914140000_horas_internas.sql`,
web e aplicativo). Decidido com o Gabriel.

## O problema

Toda hora apontada é obrigada a ter uma OS: a coluna `apontamentos_horas.os_id` nem
aceita vazio. Quem aprova é o responsável daquela OS, o custo da hora vai para o custo
daquela OS, e a TV agrupa a semana por OS.

Isso deixou de servir no dia em que a TV de colaboradores entrou na parede. A meta da
semana é de 44 horas, e quem passou a segunda-feira em reunião comercial, ou o dia em
treinamento, aparece como quem faltou, porque não tem onde pendurar essa hora. Foi o
primeiro questionamento real que a TV produziu.

## A ideia

A hora passa a apontar para uma **OS ou para uma atividade interna**, nunca as duas nem
nenhuma. É a mesma regra da tarefa, que é de OS ou é ausência, então o sistema já pensa
desse jeito.

Atividade interna é um catálogo pequeno, por empresa, cadastrado pela gestão. Nasce com:

| Atividade | Para que serve |
| --- | --- |
| Comercial | visita, reunião, levantamento e orçamento para um cliente |
| Treinamento | curso, capacitação, integração de quem chega |
| Manutenção da fábrica | conserto e cuidado da estrutura própria |
| Administrativo | o resto do escritório que não é de OS nem de cliente |
| Exames | exame periódico, admissional, demissional |
| Integração | os primeiros dias de quem entra, antes de produzir |

Exames e Integração entram como itens próprios de propósito: daqui a um ano a pergunta
vai ser "para onde foram as horas", e essa resposta só existe se cada coisa tiver o seu
nome desde o começo. O catálogo continua editável para o que aparecer depois.

**Por que não uma OS de mentira chamada "Comercial".** Ela entraria em toda lista de OS,
no custo por OS, no relatório HH, na TV como "OS 999 · Comercial", e a hora viraria custo
de uma obra que não existe.

**Por que não os centros de custo do financeiro.** Eles servem para ratear despesa, e a
lista do contador não é a lista que a pessoa quer ver na hora de apontar. Começa separado.
Se um dia fizer sentido, cada atividade aponta para um centro de custo e a hora interna
vira despesa de mão de obra dele, sem refazer nada.

## Regras decididas

- **Não tem aprovação.** Hora interna nasce aprovada. Não existe responsável de OS para
  aprovar, e a gestão não quer fila para isso.
- **Quem lança:** a própria pessoa, para si; e coordenação para cima, para qualquer
  pessoa da empresa. É a mesma regra da hora em OS.
- **Vale para todo mundo que aponta hora, inclusive quem é de produção.** Treinamento,
  manutenção da fábrica, exame e integração acontecem com o soldador tanto quanto com o
  projetista. Por isso o **tablet do PIN também oferece atividade interna**, ao lado de
  Apontar horas em OS.
- **Conta na meta da semana da TV.** É hora trabalhada. O cartão do colaborador passa a
  mostrar "Comercial 6h" ao lado das linhas de OS, e a grade da semana soma junto.
- **Não tem custo.** A hora interna fica **fora** de todo relatório de custo de OS, do
  relatório HH e de qualquer soma em dinheiro. O que se vê dela é tempo: quantas horas
  foram para cada atividade, por pessoa e por mês.
- **Comercial pede cliente e orçamento.** Ao lançar hora em Comercial, a pessoa informa
  **para qual cliente** e **qual orçamento** (a descrição, em texto livre: "painel da
  linha 3", "retrofit da prensa"). O cliente pode ser um já cadastrado ou um **nome
  digitado**, sem precisar cadastrar: é o caso do primeiro contato, em que a empresa ainda
  não existe no sistema. As outras atividades não pedem nada disso.
- **Classificação da hora** (normal, extra 50, extra 100) segue a mesma regra de hoje:
  o servidor decide pela data e pela quantidade, igual à hora em OS.
- **No mesmo dia** a pessoa pode ter hora em OS e hora interna. Uma não bloqueia a outra.

## O que se ganha com o cliente no Comercial

Com cliente e orçamento na hora, dá para responder "quantas horas de engenharia foram
para o orçamento X" antes de ele virar OS, e "quanto tempo comercial foi para um cliente
que nunca fechou". Nada disso vira dinheiro nem custo; é tempo, para decidir onde a
equipe está gastando esforço. O nome digitado de cliente novo pode ser ligado ao cadastro
depois, quando ele existir; a hora não fica presa a isso.

## Onde muda

| Lugar | O que muda |
| --- | --- |
| Banco | `os_id` vira opcional; entra `atividade_id`, `cliente_id` (opcional), `cliente_nome` (texto livre, opcional) e `orcamento_descricao`; regra "OS ou atividade, uma só"; hora interna nasce `aprovado`; as visões de custo de OS e o relatório HH ignoram hora interna |
| Cadastro (web) | Cadastros › Atividades internas: código, nome, se pede cliente e orçamento, ordem, ativa. Só ADMIN, DIRETOR e COORDENACAO. Código em branco sai do nome, sem acento |
| Web — lançar | Apontamentos: **Trabalho em OS \| Atividade interna** antes de escolher o destino; em Comercial, cliente do cadastro ou nome digitado, e o orçamento. A listagem mostra a atividade, filtra por ela e a busca acha por atividade, cliente e orçamento |
| Web — relatório | Apontamentos › Horas internas ("Para onde foram as horas"): por atividade, por pessoa e, no Comercial, por cliente e orçamento. Só tempo, nenhum R$ |
| Web — resumo | OS › Resumo de horas mostra a atividade no extrato e filtra "somente atividades internas" |
| Aplicativo | atalho **Atividade interna** no Início, para quem aponta hora; tela **Hora interna** com as atividades, a data e as pessoas (coordenação para cima escolhe a equipe, os demais lançam para si); Histórico e Minhas horas mostram a atividade no lugar da OS |
| Tablet | no menu do PIN, **Atividade interna** ao lado de Apontar horas em OS: só as atividades que não pedem cliente, horas e minutos, resumo do dia |
| TV | linha da atividade no cartão do colaborador ("Comercial 3h"); a semana e o mês somam a hora interna como hora trabalhada |

## Decidido por último

- **Tablet e Comercial.** Comercial pede cliente e orçamento, e digitar isso no tablet
  da fábrica não faz sentido. O tablet oferece só as atividades que **não** pedem
  cliente. Quem faz comercial lança pelo celular.
- **Exames e Integração** entram como atividades próprias desde o começo.

## O que o banco garante (achado na revisão contra produção)

- **Hora repetida.** Lançar de novo a mesma atividade, pessoa, data e tipo de hora é
  recusado com "edite o lançamento existente", como no lote de OS. No Comercial a chave
  inclui cliente e orçamento: dois orçamentos no mesmo dia são duas coisas. O tablet não
  barra, igual ao tablet de OS; lá quem segura o reenvio é a chave do lançamento.
- **Mudar a atividade não prende a hora antiga.** "Inativa" e "pede cliente" valem para a
  hora que entra na atividade. A hora de março continua editável depois que a gestão
  desativa a atividade ou passa a pedir cliente.
- **Aprovação automática sempre.** Seja lançada pela gestão, pelo apontador ou pelo tablet,
  e depois de qualquer edição, a hora interna fica aprovada, sem aprovador, e o histórico
  diz "Aprovação automática".
- **Cancelar e restaurar** funcionam como na hora em OS (o arquivo de cancelamentos aceita
  hora sem OS). O aviso diz "em Treinamento" e abre o Histórico, nunca "na OS " vazia.
- **Quem corrige.** Como nasce aprovada, só a coordenação para cima edita ou cancela hora
  interna; a própria pessoa não. É a regra da hora em OS depois de aprovada.
