# Tarefas (agenda de colaborador com reserva de dia)

Migrations: `supabase/migrations/20260912100000_tarefas_agenda_e_tablet.sql` (o
modelo) e `supabase/migrations/20260912220000_tarefas_participantes_dias_e_ausencias.sql`
(vários colaboradores, duração em dias e ausências).
Teste: `supabase/tests/tarefas.sql` (roda em transação e faz rollback).

## O que é

Uma tarefa amarra **uma ou mais pessoas** a um trabalho, por um ou mais dias. Ela é
de uma das seis categorias:

| Categoria | O que é | Tem OS? | Duração | Desconta a meta da semana? |
| --- | --- | --- | --- | --- |
| `os` | trabalho numa ordem de serviço | obrigatória | dias | — |
| `folga` | folga combinada | não | dias **ou** horas | sim |
| `ferias` | férias | não | dias **ou** horas | sim |
| `falta_justificada` | falta **com** atestado | não | dias **ou** horas | sim |
| `falta` | falta **sem** atestado | não | dias **ou** horas | **não** |
| `outro` | qualquer outra ausência | não | dias **ou** horas | sim |

As cinco últimas são **ausência**: a pessoa não está disponível. Trabalho e ausência
moram na mesma tabela porque disputam a mesma coisa — o dia da pessoa.

A falta entrou em 16/09/2026 (`20260916100000_falta_com_e_sem_atestado.sql`), decidida
com o Gabriel depois de um funcionário faltar numa segunda e o dia dele ficar zerado, sem
ninguém saber se faltou, se esqueceu de apontar ou se o apontamento se perdeu. Ela é a
única ausência que **não** sai da cobrança: as horas continuam previstas e o buraco
aparece na televisão, que é o que a gestão quer enxergar. Com atestado, sai da cobrança
como folga e férias. Atraso e saída antes do fim do expediente são falta medida em horas.

Quem apresenta o atestado dias depois não perde o registro:
`app_tarefas_marcar_atestado(p_tarefa_id, p_com_atestado default true)` troca entre as
duas categorias sem apagar e recriar, nos dois sentidos, e mexe só na categoria — data,
horas, participantes e reservas ficam como estavam. Não digitaliza documento: é registro.

Dois tipos: **agendada**, que tem data e reserva o dia; e **sem data**, que fica
pendente sem reservar nada. Ausência é sempre agendada, porque não existe "férias
sem data" (`chk_tarefas_ausencia_agendada`).

Situações: `pendente`, `concluida`, `cancelada`. Tarefa e apontamento de horas são
independentes: concluir uma tarefa não lança hora nenhuma.

## Duração: dias ou horas

`medida = 'dias'` aceita de 1 a 60 dias e reserva **todos** os dias do intervalo,
para **cada** pessoa. `medida = 'horas'` é sempre um dia só, exige as horas (de 0,5 a
24) e **não reserva o dia**: quem tira quatro horas de folga trabalha o resto do dia,
então bloquear a agenda seria mentira. As duas regras são do banco
(`chk_tarefas_duracao`), não só das telas: escrita direta por `service_role` também
é recusada.

`data_fim` é `data + dias - 1`, e é por ela que a tarefa entra num período: uma
tarefa de 14 a 16 aparece em qualquer busca que pegue um desses três dias.

## Regra central: uma pessoa, um dia

Uma pessoa agendada numa data não pode ser agendada de novo naquela data, por
ninguém (nem quem criou, nem coordenação, nem admin), em nenhuma outra OS nem como
ausência. Várias pessoas podem ter o mesmo dia. Tarefas sem data convivem com
agendadas.

A regra mora no banco. `tarefas_participantes` diz quem está na tarefa, e
`tarefas_reservas` guarda **uma linha por pessoa e por dia**. Os índices únicos
parciais `uq_tarefas_reservas__colaborador_dia` (colaborador, data),
`uq_tarefas_reservas__usuario_dia` (usuário, data) e
`uq_tarefas_reservas__tarefa_pessoa_dia` (tarefa, colaborador, data) valem enquanto a
reserva está ativa (`liberada_em is null`). Dois pedidos ao mesmo tempo: um advisory
lock por colaborador/dia serializa, e o índice único decide o que sobra. Liberar
preenche `liberada_em`, `liberada_por_user_id` e `liberacao_motivo`; a linha fica como
histórico.

**Um dia ocupado derruba a operação inteira.** Criar uma tarefa de três pessoas por
dois dias são seis reservas; se qualquer uma falhar, nada é gravado — nem a tarefa,
nem as outras reservas. Não adianta reservar metade de uma tarefa de dois dias.

| Operação | O que faz com a reserva |
| --- | --- |
| Criar agendada | reserva todos os dias de todas as pessoas (erro `colaborador_reservado` se um só estiver ocupado) |
| Reagendar | libera o intervalo antigo de todos e reserva o novo **na mesma transação**; em conflito nada muda |
| Passar para sem data | libera (`passou_para_sem_data`) |
| Sem data → agendada | reserva; precisa dos dias livres |
| Adicionar participante | reserva o intervalo daquela pessoa |
| Remover participante | libera (`saiu_da_tarefa`); o último participante não pode sair |
| Trocar colaborador | atalho de remover um e adicionar outro; só em tarefa de uma pessoa |
| Cancelar | libera de todos (`cancelada`); a tarefa fica no histórico |
| **Concluir** | **não libera**: o dia foi usado |
| Liberar reserva | ação explícita da gestão, só em tarefa concluída, com motivo |

`tarefas_reservas.liberacao_motivo` guarda duas coisas na mesma coluna: o motivo que
uma pessoa digitou ("Terminou antes") e a marca de sistema que as RPCs escrevem
quando liberam por conta própria (`reagendada`, `saiu_da_tarefa`, …). Quem traduz é
o banco, na leitura: `fn_tarefas_motivo_texto` vira a marca em frase e deixa passar
inteiro o que a pessoa escreveu. Antes disso o histórico mostrava "· saiu_da_tarefa"
para quem estava olhando a tela.

Mensagem de conflito: "NOME já está reservado(a) em dd/mm/aaaa." O detalhe (o que
ocupa o dia) só vem quando quem pediu pode ver aquela tarefa, e diz a categoria: em
ausência não há OS para mostrar.

## Conclusão é por pessoa

Cada participante fecha **a parte dele**, e isso fica em
`tarefas_participantes.concluida_em`. A tarefa só vira `concluida` quando a última
parte fecha — `fn_tarefas_sincronizar_conclusao` cuida disso, nos dois sentidos:
quem entra depois numa tarefa já fechada reabre ela, sem apagar as partes que já
estavam concluídas.

Numa tarefa de uma pessoa só, a gestão conclui sem dizer de quem é a parte, porque
não há ambiguidade. Com duas ou mais, é preciso informar: sem isso o erro é
`participante_invalido`.

Concluir **não libera** a reserva. Quem precisa do dia de volta usa
`app_tarefas_liberar_reserva`, que é ação explícita da gestão e pede motivo.

## Quem pode o quê

Mesma hierarquia de `fn_usuario_pode_alterar_apontamento`:

| Perfil | Vê | Cria / reagenda / edita / cancela / libera | Conclui |
| --- | --- | --- | --- |
| ADMIN, DIRETOR, COORDENACAO da empresa | todas da empresa | sim, inclusive ausência | sim |
| Responsável da OS (`ordens_servico.responsavel_aprovacao_id`) | as tarefas das OS dele + as próprias | nas OS dele | nas OS dele e as próprias |
| Colaborador comum (usuário vinculado a `colaboradores.user_id`) | só as próprias | não | só a própria parte |
| Conta do tablet | nada pelas `app_tarefas_*` | não | só pelo PIN (`app_tablet_tarefa_concluir`), e só a parte dele |
| Conta de televisão (`PAINEL_TV`) | nada pelas `app_tarefas_*`; só pelo painel (`tv_colaboradores_tarefas`) | não | não |

**Ausência é só da gestão.** Não existe "responsável pelas férias de alguém": como a
ausência não tem OS, `fn_tarefas_pode_gerir` não abre para responsável de OS.

O painel de TV lê por uma porta própria, descrita em
[painel-tv-colaboradores.md](painel-tv-colaboradores.md): as `app_tarefas_*`
continuam recusando a conta da televisão, porque ela não é gestão, não é responsável
de OS e não tem colaborador vinculado.

Aprovações de horas continuam exatamente como eram (responsável da OS aprova e
recusa); só mudaram de lugar no app.

Tudo é validado no servidor, isolado por tenant e empresa. As tabelas `tarefas`,
`tarefas_participantes`, `tarefas_reservas` e `tarefas_operacoes` têm RLS ligada e
nenhuma policy: só as funções SECURITY DEFINER acessam, e a migration derruba o
deploy se alguém acrescentar uma policy ou um grant de select. `audit_trigger`
registra inserções e alterações das três primeiras (quem criou, alterou, concluiu,
cancelou, reservou, liberou) — a conclusão pelo tablet aparece em
`tarefas_participantes`, com a sessão do PIN.

Elegibilidade: OS do tipo OS (não OV) em andamento (inclusive garantia) e
colaborador ativo da empresa. OS de HH aceita tarefa (a exclusão de HH é só do
tablet de horas). Datas futuras livres; não existe janela de 15 dias.

## Idempotência e concorrência

- `app_tarefas_criar` e `app_tarefas_concluir` (e a versão do tablet) aceitam
  `p_chave uuid`. Repetir a chave devolve o resultado guardado em
  `tarefas_operacoes` com `repetido = true`, sem gravar de novo. As telas geram a
  chave uma vez por tentativa e só trocam depois do sucesso.
- Concluir também é idempotente pelo estado: concluir o que já está concluído
  devolve sucesso com `repetido`.
- Toda operação numa tarefa começa com `select ... for update` na linha.
- "Hoje" é `fn_tablet_data_hoje()` (America/Sao_Paulo). **Atrasada é cobrança de
  trabalho**: só `categoria = 'os'` pendente com `data_fim` anterior a hoje fica
  atrasada. Ninguém conclui férias, então ausência com data passada apenas terminou.

## RPCs

Todas em `public`, para `authenticated`, contexto por `set_current_tenant` /
`set_current_empresa` (web) ou pela sessão do app.

- `app_tarefas_contexto()` → `{gestao, pode_criar, papel, colaborador_id, hoje}`
- `app_tarefas_criar(p_colaboradores uuid[], p_tipo, p_data, p_dias, p_descricao, p_categoria, p_os_id, p_medida, p_horas, p_chave)`
- `app_tarefas_marcar_atestado(p_tarefa_id, p_com_atestado default true)` — troca entre
  `falta` e `falta_justificada`, nos dois sentidos, sem apagar e recriar. Só gestão.
  Recusa o que não é falta (`categoria_invalida`) e falta cancelada (`tarefa_encerrada`);
  marcar de novo o que já está devolve `repetido` sem gravar.
- `app_tarefas_criar(p_tipo, p_colaborador_id, p_os_id, p_descricao, p_data, p_chave)` —
  **atalho de compatibilidade**: uma pessoa, um dia, sempre trabalho em OS. Existe
  para o aplicativo publicado antes de 12/09/2026 não quebrar quando a migration
  chegar em produção. O teste trava as duas assinaturas; não tire o atalho antes de
  todo aparelho ter atualizado.
- `app_tarefas_alterar(p_tarefa_id, p_descricao)`
- `app_tarefas_reagendar(p_tarefa_id, p_data, p_dias)` — `p_data` nulo = sem data
- `app_tarefas_adicionar_participante(p_tarefa_id, p_colaborador_id)`
- `app_tarefas_remover_participante(p_tarefa_id, p_colaborador_id)`
- `app_tarefas_trocar_colaborador(p_tarefa_id, p_colaborador_id)` — só com uma pessoa
- `app_tarefas_cancelar(p_tarefa_id, p_motivo)`
- `app_tarefas_concluir(p_tarefa_id, p_chave, p_colaborador_id)`
- `app_tarefas_liberar_reserva(p_tarefa_id, p_motivo)`
- `app_tarefas_listar(p_secao, p_de, p_ate, p_colaborador_id, p_os_id, p_busca)` →
  `tarefa_linha`, **uma linha por participante**. Seções: `agendadas`, `sem_data`,
  `ausencias`, `historico`, `todas`. `agendadas` e `sem_data` são de **trabalho**;
  folga e férias só na seção `ausencias`, que sem período mostra o que ainda vale e
  com período mostra o período pedido. A busca acha ausência pelo que ela é
  ("folga", "férias").
- `app_tarefas_detalhe(p_tarefa_id)` → tarefa + `participantes[]` + histórico de reservas
- `app_tarefas_contar()` → contadores só do que a pessoa vê (hoje, atrasadas,
  futuras, agendadas, sem data, `ausencias`, `atencao` = hoje + atrasadas,
  `minhas_pendentes`). Os contadores de trabalho **não somam ausência**.
- `app_tarefas_agenda(p_de, p_ate)` → o que ocupa a agenda, por data e colaborador,
  com `categoria`, `reserva_dia` e `horas` (detalhe só do que a pessoa pode ver; até
  93 dias). `reserva_dia = false` é a ausência medida em horas: ela não reserva o
  dia, então a grade mostra "Folga 4h" numa célula tracejada e o dia segue livre
  para trabalho. Sem isso a folga em horas ficava invisível justamente na tela onde
  a coordenação planeja a semana.
- `app_tarefas_colaboradores(p_data)` → ativos da empresa com `ocupado` na data e o
  motivo resumido ("OS 145 · MALWEE", "Folga", "Férias")
- `app_tarefas_os_elegiveis(p_busca)` → OS em andamento onde a pessoa cria tarefa
- Tablet: `app_tablet_tarefas(p_sessao_token)`, `app_tablet_tarefa_concluir(p_sessao_token, p_tarefa_id, p_chave)`

Retorno das ações: `{sucesso, tarefa, repetido?, erros: [{tipo, mensagem}], conflito?}`.
Tipos de erro: `tipo_invalido`, `categoria_invalida`, `medida_invalida`,
`duracao_invalida`, `data_obrigatoria`, `descricao_obrigatoria`, `descricao_longa`,
`os_invalida`, `os_encerrada`, `sem_permissao`, `colaborador_invalido`,
`colaborador_reservado`, `participante_invalido`, `ultimo_participante`,
`varios_participantes`, `tarefa_nao_encontrada`, `tarefa_encerrada`,
`tarefa_concluida`, `tarefa_cancelada`, `tarefa_pendente`, `sessao_invalida` (tablet).

`app_tarefas_colaboradores` recebe **uma data**, então a tela de nova tarefa mostra
quem está ocupado no **primeiro** dia. Conflito no segundo dia em diante aparece na
mensagem do servidor ao salvar, não antes.

## Onde aparece

- **Web**: menu OS › **Tarefas** (`/tarefas`): abas Agendadas, Sem data, Ausências,
  Histórico e Agenda (grade por data e colaborador); botão Nova tarefa e ações por
  linha conforme permissão.
- **App**: aba **Tarefas** com Tarefas agendadas, Tarefas sem data, Ausências (só
  gestão), Aprovações de horas (a tela de sempre; a notificação push continua
  apontando para `/(tabs)/aprovacao`), Concluídas e canceladas, Agenda e Nova tarefa.
  Em Nova tarefa a lista de pessoas cresce com "Adicionar colaborador", a duração tem
  atalhos de dias e, em ausência, a escolha entre dias inteiros e horas do dia. O
  badge da aba soma tarefas de hoje e atrasadas que a pessoa vê com as horas pendentes
  de aprovação (conjuntos disjuntos, sem contagem dupla).
- **Tablet**: depois do PIN, Apontar horas / Minhas tarefas / Finalizar.
  "Minhas tarefas" lista e conclui **a parte da pessoa**; quando a tarefa tem mais
  gente, a tela avisa. Nada de administração nem aprovação.
- **Televisão**: `/painel-tv/colaboradores`. As listas de tarefa lá são de trabalho.
  A grade da semana tem quatro cores: trabalhado verde, ausência planejada (folga,
  férias, outro) azul, falta com atestado violeta e falta sem atestado vermelho cheio —
  a única preenchida, porque é a única que continua sendo cobrada. Cada cor vem com o
  rótulo escrito. Detalhe em `docs/painel-tv-colaboradores.md`.
