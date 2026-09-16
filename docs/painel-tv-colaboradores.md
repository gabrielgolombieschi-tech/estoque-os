# Painel de TV por colaborador

Migrations: `supabase/migrations/20260912160000_tv_colaboradores_area.sql` (as funções
`tv_*` e a coluna `area`), `20260912190000_tv_jornada_e_area_por_cargo.sql` (a jornada
e a área pelo cargo), `20260912220000_tarefas_participantes_dias_e_ausencias.sql`
(`tv_ausencias_periodo`, e a tarefa por participante),
`20260913100000_tv_area_engenharia.sql` (a terceira área) e
`20260916100000_falta_com_e_sem_atestado.sql` (as categorias `falta_justificada` e
`falta`).
Teste: `supabase/tests/tv_colaboradores.sql` (roda em transação e faz rollback).
Tela: `/painel-tv/colaboradores?area=mecanica|eletrica|engenharia`.

## O que mostra

Por colaborador ativo de uma área, as horas apontadas na semana e no mês e as
tarefas pendentes. A tela gira sozinha entre três layouts (as maquetes estão em
`docs/tv-maquetes/`):

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
| `tv_ausencias_periodo(p_inicio, p_fim, p_area)` | uma linha por pessoa e por dia de ausência — folga, férias, outro, falta com atestado ou falta sem atestado — com `medida` e `horas` |

A tela chama `tv_periodos()`, `tv_colaboradores(area)`,
`tv_colaboradores_tarefas(area)`, `tv_horas_periodo(inicio_semana, hoje, area)`,
`tv_horas_periodo(inicio_mes, hoje, area)` e
`tv_ausencias_periodo(inicio_semana, fim_semana, area)`.

O `p_area` das quatro que recebem área passa por `public.fn_tv_area`, que corta
espaço, baixa a caixa e aceita `mecanica`, `eletrica`, `engenharia` ou vazio —
vazio é "todas". Qualquer outra coisa vira `Área inválida: X. Use mecanica,
eletrica, engenharia ou nenhuma.` A tela manda o `?area=` da URL cru, de
propósito: a validação é uma só, no banco, e é essa mensagem que aparece na
televisão. `fn_tv_area` não tem grant para `authenticated`; só as funções
`SECURITY DEFINER` a chamam.

**Ausência não é tarefa na televisão.** `tv_colaboradores_tarefas` devolve folga,
férias e as duas faltas porque elas moram na mesma tabela, mas a tela filtra
`categoria = 'os'` nas listas de tarefa: quem está de férias não deve trabalho. A
ausência entra pela `tv_ausencias_periodo`, e aparece como a cor da grade e como a
linha do dia. Pelo mesmo motivo `atrasada` só vale para trabalho — ninguém conclui
férias nem uma falta, então ausência com data passada apenas terminou.

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

## As quatro cores

Decisão do Gabriel, 16/09/2026: *"na televisão, quando é folga é uma cor, quando
trabalhado é outra, e vazio é quando não trabalhou. Falta com atestado tem que ficar
uma cor, falta sem atestado outra cor. Então vão ser quatro cores diferentes."*

| O que é | Cor | Onde aparece |
| --- | --- | --- |
| Trabalhado | verde `#57A882` | a barra do dia na grade |
| Ausência planejada — folga, férias, outro | azul `#4F8FD1` | caixa de borda azul com fundo apagado |
| Falta **com** atestado (`falta_justificada`) | violeta `#A78BFA` | caixa de borda violeta com fundo apagado |
| Falta **sem** atestado (`falta`) | vermelho `#EF4444` | bloco **cheio**, texto escuro por cima |

A falta sem atestado é a única desenhada cheia, e isso é a regra: ela é a única que
**continua cobrada**, então tem de ser a marca mais forte da tela. É o mesmo vermelho
do dia útil vazio de propósito — nas duas o recado é "esse dia a pessoa deve" —, e o
que separa as duas marcas é o preenchimento e a palavra escrita.

Hora aguardando aprovação continua saindo em amarelo `#EFC15E`: é um modificador do
verde (a hora está lá, falta aprovar), não uma quinta cor de estado.

**Cor sozinha não basta.** Toda marca traz o rótulo por escrito, porque quem não
enxerga cor não distingue violeta de vermelho numa TV a dez metros. Na grade, onde a
célula tem uns 200 px, vai o rótulo curto — `Folga`, `Férias`, `Ausente`, `Atestado`,
`Falta`. Em todo o resto — cartão, linha do dia, legenda — vai o rótulo por extenso:
**"Falta com atestado"** e **"Falta sem atestado"**.

O rodapé mostra a legenda das cores do quadro que está no ar, com o quadradinho
colorido e o nome ao lado. Ela **nunca quebra linha**: se o rodapé crescesse, a área
útil encolheria e a conta de quantas linhas cabem no layout C oscilaria de quadro
para quadro.

### A grade da semana, célula por célula

| Estado do dia | Como aparece |
| --- | --- |
| Com hora apontada | barra verde, proporcional às horas |
| Com hora aguardando aprovação | barra amarela |
| Dia útil que já passou, sem apontamento | quadrado de borda vermelha com "0h", e o total da semana em vermelho |
| Ausência do dia inteiro | caixa na cor da categoria, com o rótulo curto; a falta sem atestado vem cheia |
| Ausência em horas, no dia em que a pessoa não apontou nada | caixa na cor da categoria, com o rótulo e as horas ("Folga 4h", "Falta 2h") |
| Ausência em horas num dia trabalhado | a barra verde ganha um **anel** na cor da ausência — sem ele, o atraso de duas horas de quem trabalhou o resto do dia sumia da grade |
| Fim de semana, feriado ou dia que ainda não chegou | barrinha baixa, sem alerta |

**O total da semana fica vermelho** quando sobrou dia útil já passado sem apontamento.
Folga, férias e falta com atestado tiram o dia dessa conta; falta sem atestado **não
tira**, então o dia dela deixa o total vermelho como qualquer dia vazio.

Se caírem duas ausências no mesmo dia da mesma pessoa, fica a **mais grave** (falta
sem atestado > falta com atestado > folga/férias/outro) e, entre iguais, a que pega o
dia inteiro. Enquanto as três categorias antigas se comportavam igual tanto fazia qual
ficava; agora a escolha muda a meta, e precisa ser a mesma entre uma recarga e outra.

A grade mostra **oito pessoas por tela**. Acima disso ela pagina, 30 segundos por
página, porque numa TV de 1080p mais que isso deixa as linhas ilegíveis de longe.

### A lista de categorias também vive em mais de um lugar

Como a lista de áreas, esta precisa concordar ponta a ponta — categoria nova que o
cadastro grave e a televisão não conheça vira "Ausente" azul, em silêncio:

| Onde | Decide |
| --- | --- |
| `chk_tarefas_categoria`, em `public.tarefas` | o que o banco aceita gravar |
| `public.app_tarefas_criar` | o que o cadastro consegue criar, e a mensagem de erro |
| `CATEGORIAS_AUSENCIA`, no topo de `app/painel-tv/colaboradores/page.tsx` | o rótulo, a cor e se desconta da meta |

`tv_ausencias_periodo` não precisa de mudança para uma categoria nova: ela devolve
tudo que **não** é `'os'`. Quem precisa saber o nome de cada uma é a tela. Categoria
que a tela não conhece cai em `'outro'` de propósito — é melhor mostrar "Ausente" do
que perder a linha.

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

**Ausência desconta da semana — menos a falta sem atestado.** Folga, férias, outros e
a falta **com** atestado tiram o dia, ou as horas, da meta daquela pessoa: quem tirou
férias na quarta passa a dever 35 horas em vez de 44. Não conta como hora cumprida,
apenas sai da cobrança. O cartão do layout A mostra a meta e quanto falta, já com esse
desconto, e a função `tv_ausencias_periodo` é a fonte.

A falta **sem** atestado é a exceção, e é o motivo de ela existir: as horas **continuam
previstas**. Quem faltou três dias sem atestado segue devendo as 44 horas da semana, e
o buraco aparece escrito no cartão ("meta 44h · faltam 44h") e no total vermelho da
grade. Vale igual quando a falta é medida em horas: duas horas de atraso sem atestado
não saem da meta, então quem apontou 7h num dia de 9h aparece devendo as 2h.

O par que a tela foi feita para mostrar lado a lado:

| | Ausência | Horas apontadas | Meta da semana | Total |
| --- | --- | --- | --- | --- |
| falta com atestado | 3 dias | 0h | **17h** (44 − 27) | normal |
| falta sem atestado | 3 dias | 0h | **44h** | vermelho |

**Empresa nova nasce com jornada.** A `20260912190000` só semeou as empresas que
existiam naquele dia, e `tv_periodos` usa `coalesce(jornada.horas, 0)`: uma empresa
criada depois mostraria meta de 0h em todo dia e nunca ficaria vermelha, em silêncio.
A Parte 6 da `20260912220000` pôs um gatilho em `public.empresas` que dá a jornada da
fábrica a quem nasce, e preencheu quem tinha ficado sem.

Mudar horário não exige migration: é `update` na tabela. Ela tem RLS ligada e nenhuma
policy, como as demais; só as funções `SECURITY DEFINER` leem — nem
`authenticated` tem select, então o `update` é por `service_role`.

## Área do colaborador

`public.colaboradores.area` aceita `mecanica`, `eletrica`, `engenharia` ou vazio, e
tem campo próprio no cadastro de colaboradores, ao lado do cargo. A área não descreve
o que a pessoa faz: ela diz **em qual televisão a pessoa aparece**.

| Área | Quem é |
| --- | --- |
| `mecanica` | frente de chão de fábrica |
| `eletrica` | frente de chão de fábrica |
| `engenharia` | a turma do escritório que trabalha em OS: coordenação, projeto, programação e segurança |

Engenharia não é chão de fábrica, mas aponta hora e tem tarefa de OS igual às outras
duas, e por isso ganhou TV própria em vez de um painel novo: a tela é a mesma, só
filtrada (`/painel-tv/colaboradores?area=engenharia`), e os três layouts serviram sem
mudança.

Sem `?area` na URL a tela mostra **todos** os ativos da empresa, inclusive quem está
sem área. As TVs penduradas usam os atalhos por área do lançador `/painel-tv`.

### De onde veio a área de cada um

A migration `20260912190000` preencheu a coluna a partir do cargo que já existia: quem
tem MEC no cargo virou mecânica, quem tem ELE virou elétrica, e segurança e programação
ficaram sem área. Cargo com as duas marcas, ou com nenhuma, fica sem área de propósito,
porque é melhor a pessoa não aparecer em nenhuma TV de área do que aparecer na errada.
O preenchimento nunca sobrescreve área já definida à mão, e não há gatilho: mudar o
cargo depois não mexe na área.

A `20260913100000` abriu a engenharia e montou a turma **por nome**, não por cargo,
porque o cargo não distingue — "COORDENADOR MECANICO" e "PROJETISTA MEC" têm a mesma
marca MEC do soldador.

**DOUGLAS WIEMENS e MATHEUS CAMILO saíram da mecânica.** Um é coordenador, o outro é
projetista; estavam na mecânica só por causa do MEC no cargo. A TV da mecânica passou a
mostrar duas pessoas a menos, e isso é o esperado: quem a frente de fábrica precisa ver
é quem está na fábrica. Quem procurar por eles acha na TV da engenharia.

### A lista de áreas vive em três lugares

Os três precisam concordar, senão existe área que um aceita e o outro recusa:

| Onde | Decide |
| --- | --- |
| `chk_colaboradores_area`, em `public.colaboradores` | o que o cadastro consegue gravar |
| `public.fn_tv_area` | o que a televisão consegue ler |
| `ROTULO_AREA`, no topo de `app/colaboradores/page.tsx` | como a área aparece escrita na lista de colaboradores |

Os dois primeiros o banco confere no deploy: as asserções da `20260913100000` exigem
que `fn_tv_area` aceite `engenharia` e que `chk_colaboradores_area` também aceite —
se uma tivesse ficado para trás, a migration não subiria. O terceiro é revisão, e não
é o único pedaço de tela: o seletor de Área do mesmo arquivo tem as opções escritas à
mão, o cabeçalho da TV tem a própria cópia dos rótulos (`rotuloArea`, em
`app/painel-tv/colaboradores/page.tsx`) e o lançador `app/painel-tv/page.tsx` tem um
atalho por área. Área nova passa por todos eles.

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

## O cartão do colaborador, por dentro

O cartão do layout A mostra as horas da semana e do mês, a ausência da semana, a meta
já com o desconto, as OS em que a pessoa lançou hora, e então a lista de tarefas.

A linha da ausência junta por categoria e sai **cada pedaço na cor dele**: "Férias ·
3 dias" em azul, "Falta com atestado · 3 dias" em violeta, "Falta sem atestado · 2h"
em vermelho. Ela existe para explicar a meta: sem dizer o motivo, uma meta de 35h
parece defeito. E quando o pedaço é falta sem atestado, a meta **não** caiu — daí a
importância de o motivo vir escrito, e não só colorido.

A lista de tarefas segue três regras:

- **As pendentes vêm todas**, com data primeiro e as sem data no fim. A tarefa sem
  data não ganha rótulo: o que interessa é o serviço, e escrever "Sem data" só
  gastava linha. Antes o cartão listava no máximo duas com data e resumia o resto
  num contador, então uma tarefa sem data existia sem dizer o que era.
- **As concluídas na semana aparecem com um ✓ verde**, em texto mais apagado. A
  janela é a semana corrente, contada da segunda-feira — a mesma de
  `horas_previstas`, para o cartão inteiro falar do mesmo período. Antes só entrava
  o que tinha sido fechado no próprio dia, e quem fechou três tarefas na segunda
  aparecia na quinta como se não tivesse feito nada (`20260913130000`).
- **A lista rola sozinha quando não cabe.** Fica parada um quinto do tempo no topo,
  desce até o fim no tempo restante e para lá até o quadro trocar. Sem isso, o que
  passasse da borda simplesmente nunca apareceria — ninguém está na frente da TV
  para rolar com o dedo.

## Hora interna na televisão

Desde `20260914100000` a hora pode ir para uma **atividade interna** (comercial,
treinamento, manutenção da fábrica, administrativo, exames, integração) em vez de uma
OS — ver `docs/horas-internas.md`. Para a televisão ela é hora trabalhada como qualquer
outra:

- **conta na semana e no mês**, e por isso conta na meta. Foi exatamente o primeiro
  questionamento que a TV produziu: quem passou a segunda em reunião comercial aparecia
  como quem faltou, porque não tinha onde pendurar essa hora;
- **no cartão** aparece com o nome da atividade onde apareceria a OS: "Comercial 3h",
  "Treinamento 2h", ao lado das linhas "OS 145 · MALWEE 34h". Sem cliente, porque na
  televisão o que importa é para onde o tempo foi, não para quem;
- **na grade da semana** a barra do dia soma as duas.

`tv_horas_periodo` devolve `atividade_id` e `atividade_nome` no fim, com `os_id`,
`numero_os` e `cliente_nome` nulos nessas linhas. A tela agrupa por uma chave que é a OS
ou a atividade, porque `os_id` nulo colapsaria toda hora interna numa entrada só.
