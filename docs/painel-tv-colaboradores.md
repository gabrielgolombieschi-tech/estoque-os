# Painel de TV por colaborador

Migrations: `supabase/migrations/20260912160000_tv_colaboradores_area.sql` (as funções
`tv_*` e a coluna `area`), `20260912190000_tv_jornada_e_area_por_cargo.sql` (a jornada
e a área pelo cargo) e `20260912220000_tarefas_participantes_dias_e_ausencias.sql`
(`tv_ausencias_periodo`, e a tarefa por participante).
Teste: `supabase/tests/tv_colaboradores.sql` (roda em transação e faz rollback).
Tela: `/painel-tv/colaboradores?area=mecanica|eletrica`.

## O que mostra

Por colaborador ativo de uma frente de trabalho, as horas apontadas na semana e no
mês e as tarefas pendentes. A tela gira sozinha entre três layouts (as maquetes
estão em `docs/tv-maquetes/`):

| Layout | O que é | Tempo |
| --- | --- | --- |
| A — cartões por colaborador | 2 cartões por página (3 quando a largura medida comporta), um por colaborador ativo, mesmo zerado | 15 s **por página**, até percorrer todo mundo |
| B — barras da semana | uma linha por colaborador, todos numa página só, sete dias e o total | 30 s |
| C — tarefas do dia | atrasadas no topo, depois as de hoje, e no fim quem não tem nada para hoje | 60 s; quando não cabe numa página, subpáginas de 15 s |

A linha do layout C tem **altura fixa**, e isso é regra, não detalhe. A página é
cortada por "quantas linhas cabem na altura da área", e a altura vinha da primeira
linha da página: como a linha de tarefa tem duas linhas de texto (serviço e cliente) e
a de quem está sem tarefa tem uma, a medida mudava de página para página — a página 1
mostrava 8 e a 2 começava na linha 10, e duas pessoas caíam no vão e **nunca**
apareciam na televisão. Com altura fixa as páginas encaixam.

Depois do C volta para o A. A troca tem fade de 380 ms, o relógio do cabeçalho anda
de segundo em segundo e os dados são relidos a cada 2 minutos **sem interromper a
rotação**: a lista de quadros é lida por referência dentro do temporizador, então
uma recarga que muda o número de páginas não reinicia o ciclo nem pisca a tela.
Layout sem conteúdo fica fora do giro — sem tarefa de hoje nem atrasada, o C não
entra.

## Por que tem funções próprias

A conta da televisão tem papel `PAINEL_TV`, não é pessoa e não tem colaborador
vinculado. As leituras que já existiam são todas "de alguém":

- as `app_tarefas_*` passam por `fn_tarefas_contexto`, que só abre para gestão,
  responsável da OS ou o próprio colaborador;
- `apontamentos_horas` tem policy restritiva que exige `can('apontamentos','read')`,
  falso para esse papel.

Antes desta migration, a conta da televisão lia zero linha de tarefa e zero linha
de hora. As funções abaixo são autorizadas **pelo papel**, não pela pessoa.

## Funções

Todas exigem contexto de empresa (`set_current_tenant` e `set_current_empresa`) e
papel em `PAINEL_TV`, `ADMIN`, `DIRETOR` ou `COORDENACAO`. Qualquer outro perfil
recebe "Este painel é restrito ao perfil de painel de TV e à gestão."

| Função | Devolve |
| --- | --- |
| `tv_periodos(p_inicio, p_fim)` | `hoje`, `inicio_semana` (segunda), `inicio_mes` (dia 1), `papel`, `horas_previstas`, `horas_previstas_ate_hoje` e `dias[]` com `data`, `dow`, `eh_util`, `feriado`, `passado` e `horas_previstas`; sem argumentos, a semana corrente |
| `tv_colaboradores(p_area)` | os ativos da empresa na área, por nome, inclusive quem não tem hora nem tarefa |
| `tv_colaboradores_tarefas(p_area)` | `setof tarefa_linha`, **uma linha por participante**, com as pendentes e as concluídas hoje, atrasadas primeiro |
| `tv_horas_periodo(p_inicio, p_fim, p_area)` | uma linha por colaborador, OS e dia, com a soma das horas |
| `tv_ausencias_periodo(p_inicio, p_fim, p_area)` | uma linha por pessoa e por dia de folga, férias ou outro, com `medida` e `horas` |

A tela chama `tv_periodos()`, `tv_colaboradores(area)`,
`tv_colaboradores_tarefas(area)`, `tv_horas_periodo(inicio_semana, hoje, area)`,
`tv_horas_periodo(inicio_mes, hoje, area)` e
`tv_ausencias_periodo(inicio_semana, fim_semana, area)`.

**Ausência não é tarefa na televisão.** `tv_colaboradores_tarefas` devolve folga e
férias porque elas moram na mesma tabela, mas a tela filtra `categoria = 'os'` nas
listas de tarefa: quem está de férias não deve trabalho. A ausência entra pela
`tv_ausencias_periodo`, e aparece como o azul da grade e como a linha do dia. Pelo
mesmo motivo `atrasada` só vale para trabalho — ninguém conclui férias, então
ausência com data passada apenas terminou.

Numa tarefa de várias pessoas, quem já fechou a própria parte sai das listas de
pendente (é o `participante_concluida_em` que diz isso, porque a tarefa continua
`pendente` enquanto sobrar alguém) e passa a contar em "Concluiu N hoje".

As datas da semana e do mês vêm do banco, no fuso da operação
(`fn_tablet_data_hoje`), e nunca do relógio da televisão. **Dia útil também é
decisão do banco**: `eh_util` já considera o fim de semana e o calendário de
feriados, o mesmo que classifica a hora extra do colaborador. O navegador da TV
nunca passa uma data `AAAA-MM-DD` por `new Date()` — corta a string, e a única
conta de data que faz é a diferença em dias de uma tarefa atrasada, em aritmética
inteira sobre a própria string.

## Cores da grade da semana

| Estado do dia | Como aparece |
| --- | --- |
| Com hora apontada | barra verde, proporcional às horas |
| Com hora aguardando aprovação | barra amarela |
| Dia útil que já passou, sem apontamento | quadrado de borda vermelha com "0h", e o total da semana em vermelho |
| Folga, férias ou outra ausência do dia inteiro | quadrado azul com o rótulo, **sem** deixar o total vermelho |
| Folga em horas, no dia em que a pessoa não apontou nada | quadrado azul com as horas liberadas |
| Fim de semana, feriado ou dia que ainda não chegou | barrinha baixa, sem alerta |

O azul existe porque ausência **não é falta**: o dia saiu da conta. Qualquer dia útil
sem apontamento, um só que seja, deixa o total da semana em vermelho.

A grade mostra **oito pessoas por tela**. Acima disso ela pagina, 30 segundos por
página, porque numa TV de 1080p mais que isso deixa as linhas ilegíveis de longe.

## Jornada: quanto falta fechar na semana

`public.jornada_padrao` guarda as horas previstas por dia da semana em cada empresa,
e nasceu com a jornada da fábrica: segunda a quinta das 7:30 às 12:00 e das 13:00 às
17:30, nove horas, e sexta até as 16:30, oito horas. A semana fecha em **44 horas**.

A previsão é por dia e respeita o calendário: feriado e fim de semana valem zero,
mesmo que a tabela diga outra coisa. Numa semana com feriado na segunda, por exemplo,
a previsão cai para 35 horas. `tv_periodos` devolve `horas_previstas` (a semana
inteira) e `horas_previstas_ate_hoje` (só os dias que já passaram), que é a conta
honesta para a televisão cobrar: ela compara o apontado com o que já deveria ter sido
apontado, não com o que ainda vai acontecer.

**Ausência desconta da semana.** Folga, férias e outros tiram o dia, ou as horas, da
meta daquela pessoa: quem tirou férias na quarta passa a dever 35 horas em vez de 44.
Não conta como hora cumprida, apenas sai da cobrança. O cartão do layout A mostra a
meta e quanto falta, já com esse desconto, e a função `tv_ausencias_periodo` é a fonte.

**Empresa nova nasce com jornada.** A `20260912190000` só semeou as empresas que
existiam naquele dia, e `tv_periodos` usa `coalesce(jornada.horas, 0)`: uma empresa
criada depois mostraria meta de 0h em todo dia e nunca ficaria vermelha, em silêncio.
A Parte 6 da `20260912220000` pôs um gatilho em `public.empresas` que dá a jornada da
fábrica a quem nasce, e preencheu quem tinha ficado sem.

Mudar horário não exige migration: é `update` na tabela. Ela tem RLS ligada e nenhuma
policy, como as demais; só as funções `SECURITY DEFINER` leem — nem
`authenticated` tem select, então o `update` é por `service_role`.

## Área do colaborador

`public.colaboradores.area` aceita `mecanica`, `eletrica` ou vazio, e agora tem campo
próprio no cadastro de colaboradores, ao lado do cargo. A migration
`20260912190000` preencheu a coluna a partir do cargo que já existia: quem tem MEC no
cargo virou mecânica, quem tem ELE virou elétrica, e segurança e programação ficaram
sem área. Cargo com as duas marcas, ou com nenhuma, fica sem área de propósito, porque
é melhor a pessoa não aparecer em TV nenhuma do que aparecer na errada. O preenchimento
nunca sobrescreve área já definida à mão.

## Regras que a tela herda

- **Hora recusada não soma.** `status_aprovacao = 'rejeitado'` fica de fora; a
  pendente entra e vem marcada, para o painel cobrar a aprovação sem mudar o total
  que a pessoa já vê no aplicativo.
- **Nada de dinheiro.** As funções não tocam em `valor_hora`, `custo_lancamento`
  nem `fator_aplicado`, e o bloco de asserções da migration derruba o deploy se
  alguma delas passar a tocar.
- **Colaborador ativo sem hora e sem tarefa aparece assim mesmo**, com zero. É o
  cartão que a coordenação precisa enxergar.
- **Tarefa concluída continua ocupando o dia** (regra de `docs/tarefas.md`); o
  painel mostra as pendentes e, à parte, o que foi concluído hoje.
- As tabelas de tarefas seguem com RLS ligada e sem policy. O painel lê por função
  `SECURITY DEFINER`, como todo o resto.
