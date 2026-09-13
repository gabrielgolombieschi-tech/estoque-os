"use client";

import { useSearchParams } from "next/navigation";
import {
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type Ref,
} from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

/* -------------------------------------------------------------------------- */
/* Ciclo                                                                       */
/* -------------------------------------------------------------------------- */

// A televisao fica ligada o dia inteiro sem ninguem por perto: nada aqui depende
// de clique. Cada layout tem o seu tempo de tela.
const MS_CARTOES = 15_000; // layout A, por pagina de colaboradores
const MS_BARRAS = 30_000; // layout B, por pagina
// Oito pessoas por tela no layout B. Acima disso as linhas ficam apertadas numa
// TV de 1080p e as barras deixam de ser legiveis de longe.
const COLABORADORES_POR_PAGINA_B = 8;
const MS_TAREFAS = 60_000; // layout C, quando cabe numa pagina so
const MS_TAREFAS_SUB = 15_000; // layout C dividido em subpaginas
const SUBPAGINAS_TAREFAS = Math.round(MS_TAREFAS / MS_TAREFAS_SUB); // 4
const FADE_MS = 380;
const RECARGA_MS = 120_000;

/* -------------------------------------------------------------------------- */
/* Medicao                                                                     */
/* -------------------------------------------------------------------------- */

// Quantos cartoes cabem lado a lado. Sao 2 por padrao e 3 quando a largura
// medida comporta, como pede a maquete 1.
const CARTOES_MIN = 2;
const CARTOES_MAX = 3;
const CARTAO_GAP_PX = 24;
const CARTAO_LARGURA_MIN_PX = 512;

// Altura de uma linha do layout C. E FIXA, e isso e a regra, nao um detalhe: a
// pagina e cortada por "quantas linhas cabem na altura da area", e a linha era
// medida da primeira da pagina. Como a linha de tarefa tem duas linhas de texto
// (servico e cliente) e a de quem esta sem tarefa tem uma, a medida mudava de
// pagina para pagina: a pagina 1 media 101px e mostrava 8, a pagina 2 media 84px
// e comecava a contar da linha 10. Duas pessoas caiam no vao e NUNCA apareciam na
// televisao. Com altura fixa as paginas encaixam.
const ALTURA_LINHA_TAREFA_PX = 104;
const LINHAS_TAREFA_PADRAO = 6;

const MAX_OS_NO_CARTAO = 3;
const MAX_TAREFAS_NO_CARTAO = 2;

/* -------------------------------------------------------------------------- */
/* Cores (zinc, como as outras TVs)                                            */
/* -------------------------------------------------------------------------- */

const FUNDO = "#18181B"; // zinc-900
const CARTAO = "#27272A"; // zinc-800
const DIVISORIA = "#3F3F46"; // zinc-700
const BARRA_VAZIA = "#27272A"; // zinc-800
// Teto da barra do layout B, em pixels. Sem ele, numa area com poucas pessoas a
// linha fica alta e a barra cresce ate virar uma parede — o desenho da maquete
// tem barras baixas, do tamanho de um cartao de dia.
const BARRA_ALTURA_MAX_PX = 104;
const TEXTO = "#E4E4E7"; // zinc-200
const TEXTO_2 = "#A1A1AA"; // zinc-400
const TEXTO_3 = "#71717A"; // zinc-500
const VERDE = "#57A882";
const AMARELO = "#EFC15E";
const VERMELHO = "#F87171"; // texto de alerta
const VERMELHO_BORDA = "#EF4444";
const VERMELHO_FUNDO = "#3B1B1B";
// Ausencia (folga, ferias, outro) e azul: nao e falta, e dia que saiu da conta.
const AZUL = "#4F8FD1";

// Cor do circulo de iniciais: deterministica pelo id, para o mesmo colaborador
// manter a cor entre recargas e entre os tres layouts.
const PALETA_INICIAIS = [
  "#38BDF8",
  "#34D399",
  "#FBBF24",
  "#A78BFA",
  "#F472B6",
  "#22D3EE",
  "#FB923C",
  "#4ADE80",
];

const ROTULO_AUSENCIA: Record<string, string> = {
  folga: "Folga",
  ferias: "Férias",
  outro: "Ausente",
};

const DOW_ABREV = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"];
const DOW_EXTENSO = [
  "segunda-feira",
  "terça-feira",
  "quarta-feira",
  "quinta-feira",
  "sexta-feira",
  "sábado",
  "domingo",
];

/* -------------------------------------------------------------------------- */
/* Tipos                                                                       */
/* -------------------------------------------------------------------------- */

type DiaPeriodo = {
  data: string;
  dow: number;
  eh_util: boolean;
  feriado: string | null;
  passado: boolean;
  horas_previstas: number;
};

type Periodos = {
  hoje: string;
  inicio_semana: string;
  inicio_mes: string;
  papel: string;
  dias: DiaPeriodo[];
};

type ColaboradorTv = {
  id: string;
  nome: string;
  cargo: string | null;
  area: string | null;
};

type AusenciaLinha = {
  colaborador_id: string;
  colaborador_nome: string;
  data: string;
  categoria: "folga" | "ferias" | "outro";
  medida: "dias" | "horas";
  horas: number | string | null;
  descricao: string | null;
};

type HoraLinha = {
  colaborador_id: string;
  colaborador_nome: string;
  os_id: number;
  numero_os: string;
  cliente_nome: string;
  data: string;
  horas: number | string | null;
  status_aprovacao: string | null;
};

type TarefaLinha = {
  id: string;
  tipo: "agendada" | "sem_data";
  data: string | null;
  situacao: "pendente" | "concluida" | "cancelada";
  // 'os' e trabalho; folga, ferias e outro sao ausencia e nao entram nas listas
  // de tarefa da televisao.
  categoria: "os" | "folga" | "ferias" | "outro";
  colaborador_id: string;
  colaborador_nome: string;
  os_id: number;
  numero_os: string;
  cliente_nome: string;
  os_descricao: string | null;
  descricao: string | null;
  atrasada: boolean;
  hoje: boolean;
  // Quando a PESSOA da linha fechou a parte dela. A tarefa continua 'pendente'
  // enquanto sobrar alguem, entao e por aqui que se sabe quem ja acabou.
  participante_concluida_em: string | null;
  participantes: number;
};

type OsDaSemana = {
  osId: number;
  numeroOs: string;
  clienteNome: string;
  horas: number;
  pendente: boolean;
};

type DiaDoColaborador = {
  horas: number;
  pendente: boolean;
};

type AusenciaDoDia = {
  categoria: "folga" | "ferias" | "outro";
  medida: "dias" | "horas";
  horas: number;
};

type ResumoColaborador = {
  id: string;
  nome: string;
  primeiroNome: string;
  horasSemana: number;
  horasMes: number;
  osSemana: OsDaSemana[];
  porDia: Map<string, DiaDoColaborador>;
  ausenciaPorDia: Map<string, AusenciaDoDia>;
  // Previsto da semana ja descontando folga e ferias: e o que a pessoa ainda
  // deve. Ausencia nao conta como hora cumprida, so sai da cobranca.
  metaSemana: number;
  // Resumo curto do que saiu da cobranca nesta semana, ja pronto para a tela:
  // "Férias · 3 dias", "Folga · 4h".
  ausenciaDaSemana: string | null;
  faltasEmDiaUtil: number;
  tarefasPendentes: TarefaLinha[];
  tarefasComData: TarefaLinha[];
  tarefasSemData: number;
};

type LinhaDoDia =
  | { chave: string; tipo: "tarefa"; tarefa: TarefaLinha; diasAtraso: number }
  | {
      chave: string;
      tipo: "ocioso";
      resumo: ResumoColaborador;
      concluidasHoje: number;
      // Quem esta de folga ou de ferias hoje nao esta "sem tarefa": esta fora.
      ausenciaHoje?: AusenciaDoDia;
    };

type Quadro = {
  layout: "cartoes" | "barras" | "tarefas";
  pagina: number;
  totalPaginas: number;
  ms: number;
};

const QUADRO_PADRAO: Quadro = {
  layout: "cartoes",
  pagina: 0,
  totalPaginas: 1,
  ms: MS_CARTOES,
};

/* -------------------------------------------------------------------------- */
/* Datas: sempre em cima da string 'AAAA-MM-DD'                                */
/* -------------------------------------------------------------------------- */

// Numero do dia no calendario civil (algoritmo days_from_civil), feito so com os
// inteiros da string. Nao existe new Date() aqui de proposito: o relogio da
// maquina da televisao pode estar em outro fuso e puxaria a data um dia para
// tras. Semana, mes e dia util continuam vindo do banco (tv_periodos); isto aqui
// so serve para dizer quantos dias uma tarefa esta atrasada e que dia da semana
// cai uma data futura.
function serialDoDia(data: string | null): number | null {
  if (!data) return null;
  const partes = data.split("-");
  if (partes.length < 3) return null;
  const ano = Number(partes[0]);
  const mes = Number(partes[1]);
  const dia = Number(partes[2].slice(0, 2));
  if (!Number.isFinite(ano) || !Number.isFinite(mes) || !Number.isFinite(dia)) return null;
  const anoAjustado = mes <= 2 ? ano - 1 : ano;
  const era = Math.floor(anoAjustado / 400);
  const anoNaEra = anoAjustado - era * 400;
  const diaNoAno = Math.floor((153 * (mes + (mes > 2 ? -3 : 9)) + 2) / 5) + dia - 1;
  const diaNaEra =
    anoNaEra * 365 + Math.floor(anoNaEra / 4) - Math.floor(anoNaEra / 100) + diaNoAno;
  return era * 146097 + diaNaEra - 719468;
}

// 1 = segunda … 7 = domingo (mesmo isodow que o banco devolve em tv_periodos).
// 1970-01-01 (serial 0) foi uma quinta, isodow 4, que e de onde sai o +3.
function isodowDaData(data: string | null): number | null {
  const serial = serialDoDia(data);
  if (serial === null) return null;
  return ((((serial + 3) % 7) + 7) % 7) + 1;
}

function diferencaEmDias(de: string | null, ate: string | null): number {
  const a = serialDoDia(de);
  const b = serialDoDia(ate);
  if (a === null || b === null) return 0;
  return b - a;
}

function diaEMes(data: string | null): string {
  if (!data) return "";
  const partes = data.split("-");
  if (partes.length < 3) return data;
  return `${partes[2].slice(0, 2)}/${partes[1]}`;
}

function apenasDia(data: string | null): string {
  if (!data) return "";
  const partes = data.split("-");
  if (partes.length < 3) return data;
  return partes[2].slice(0, 2);
}

function mesDaData(data: string | null): string {
  if (!data) return "";
  const partes = data.split("-");
  if (partes.length < 2) return "";
  return partes[1];
}

// "07 a 12/09" quando o periodo cabe no mesmo mes; "28/08 a 03/09" quando vira.
function rotuloPeriodo(inicio: string, fim: string): string {
  if (!inicio || !fim) return "";
  const mesInicio = mesDaData(inicio);
  const mesFim = mesDaData(fim);
  if (mesInicio && mesInicio === mesFim) return `${apenasDia(inicio)} a ${diaEMes(fim)}`;
  return `${diaEMes(inicio)} a ${diaEMes(fim)}`;
}

/* -------------------------------------------------------------------------- */
/* Texto                                                                       */
/* -------------------------------------------------------------------------- */

function corDoColaborador(id: string): string {
  let soma = 0;
  for (let i = 0; i < id.length; i += 1) soma += id.charCodeAt(i);
  return PALETA_INICIAIS[soma % PALETA_INICIAIS.length];
}

function iniciaisDoNome(nome: string): string {
  const partes = nome.trim().split(/\s+/).filter(Boolean);
  if (partes.length === 0) return "?";
  const primeira = partes[0]?.charAt(0) ?? "";
  const segunda = partes[1]?.charAt(0) ?? "";
  return `${primeira}${segunda}`.toUpperCase() || "?";
}

function primeiroNomeDe(nome: string): string {
  const partes = nome.trim().split(/\s+/).filter(Boolean);
  return partes[0] ?? nome.trim();
}

// "32h" quando fecha na hora cheia e "32h30" quando sobra minuto: quem le de
// longe nao converte 32,5 de cabeca.
// "Férias · 3 dias" ou "Folga · 4h": o que saiu da cobranca da pessoa nesta
// semana. Junta por categoria, porque na televisao o que importa e o motivo.
function resumirAusencia(
  porDia: Map<string, AusenciaDoDia>,
  dias: DiaPeriodo[]
): string | null {
  const emDias = new Map<string, number>();
  const emHoras = new Map<string, number>();
  for (const dia of dias) {
    const ausencia = porDia.get(dia.data);
    if (!ausencia) continue;
    if (ausencia.medida === "dias") {
      emDias.set(ausencia.categoria, (emDias.get(ausencia.categoria) ?? 0) + 1);
    } else {
      emHoras.set(ausencia.categoria, (emHoras.get(ausencia.categoria) ?? 0) + ausencia.horas);
    }
  }
  const partes: string[] = [];
  for (const [categoria, quantos] of emDias) {
    partes.push(
      `${ROTULO_AUSENCIA[categoria] ?? "Ausente"} · ${quantos} ${quantos === 1 ? "dia" : "dias"}`
    );
  }
  for (const [categoria, horas] of emHoras) {
    if (horas <= 0) continue;
    partes.push(`${ROTULO_AUSENCIA[categoria] ?? "Ausente"} · ${formatarHoras(horas)}`);
  }
  return partes.length ? partes.join(" · ") : null;
}

function formatarHoras(horas: number): string {
  const minutos = Math.round(horas * 60);
  if (!Number.isFinite(minutos) || minutos <= 0) return "0h";
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return m === 0 ? `${h}h` : `${h}h${String(m).padStart(2, "0")}`;
}

function rotuloArea(area: string | null): string {
  if (area === "mecanica") return "Mecânica";
  if (area === "eletrica") return "Elétrica";
  if (!area) return "Todas as áreas";
  return area;
}

function descricaoDaTarefa(tarefa: TarefaLinha): string {
  const texto = tarefa.descricao?.trim();
  if (texto) return texto;
  const daOs = tarefa.os_descricao?.trim();
  return daOs || "Sem descrição";
}

// "Hoje · OS 4812 trocar rolamento (atrasada)" / "Seg 14 · OS 4830 alinhamento".
function prefixoDaTarefa(tarefa: TarefaLinha): string {
  if (tarefa.atrasada || tarefa.hoje) return "Hoje";
  const dow = isodowDaData(tarefa.data);
  const abrev = dow ? DOW_ABREV[dow - 1] : "";
  const rotulo = abrev ? abrev.charAt(0).toUpperCase() + abrev.slice(1) : "";
  const dia = apenasDia(tarefa.data);
  return rotulo && dia ? `${rotulo} ${dia}` : diaEMes(tarefa.data) || "Sem data";
}

/* -------------------------------------------------------------------------- */
/* Normalizacao das respostas                                                  */
/* -------------------------------------------------------------------------- */

function normalizarPeriodos(valor: unknown): Periodos {
  const bruto = (valor ?? {}) as Record<string, unknown>;
  const dias = Array.isArray(bruto.dias)
    ? (bruto.dias as unknown[]).map((item) => {
        const dia = (item ?? {}) as Record<string, unknown>;
        return {
          data: typeof dia.data === "string" ? dia.data : "",
          dow: Number(dia.dow ?? 0),
          eh_util: dia.eh_util === true,
          feriado: typeof dia.feriado === "string" ? dia.feriado : null,
          passado: dia.passado === true,
          // Jornada do dia, ja zerada pelo banco em feriado e fim de semana.
          horas_previstas: Number(dia.horas_previstas ?? 0) || 0,
        } satisfies DiaPeriodo;
      })
    : [];
  return {
    hoje: typeof bruto.hoje === "string" ? bruto.hoje : "",
    inicio_semana: typeof bruto.inicio_semana === "string" ? bruto.inicio_semana : "",
    inicio_mes: typeof bruto.inicio_mes === "string" ? bruto.inicio_mes : "",
    papel: typeof bruto.papel === "string" ? bruto.papel : "",
    dias: dias.filter((dia) => dia.data.length > 0),
  };
}

/* -------------------------------------------------------------------------- */
/* Pagina                                                                      */
/* -------------------------------------------------------------------------- */

export default function PainelTvColaboradoresPage() {
  // Suspense por causa do useSearchParams.
  return (
    <Suspense fallback={<TelaMensagem titulo="Carregando painel…" />}>
      <PainelColaboradores />
    </Suspense>
  );
}

function PainelColaboradores() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId } = useTenantEmpresa();
  const searchParams = useSearchParams();

  // A area vai crua para o banco: quem valida "mecanica"/"eletrica" e a funcao
  // fn_tv_area, e a mensagem dela e a que a tela mostra.
  const areaParam = useMemo(() => {
    const bruto = searchParams.get("area");
    const limpo = typeof bruto === "string" ? bruto.trim().toLowerCase() : "";
    return limpo.length > 0 ? limpo : null;
  }, [searchParams]);

  const [periodos, setPeriodos] = useState<Periodos | null>(null);
  const [colaboradores, setColaboradores] = useState<ColaboradorTv[]>([]);
  const [tarefas, setTarefas] = useState<TarefaLinha[]>([]);
  const [horasSemana, setHorasSemana] = useState<HoraLinha[]>([]);
  const [horasMes, setHorasMes] = useState<HoraLinha[]>([]);
  const [ausencias, setAusencias] = useState<AusenciaLinha[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(true);
  const [pronto, setPronto] = useState(false);
  const [atualizadoEm, setAtualizadoEm] = useState<Date | null>(null);

  const [quadroIndex, setQuadroIndex] = useState(0);
  const [fadeVisivel, setFadeVisivel] = useState(true);
  const [cartoesPorPagina, setCartoesPorPagina] = useState(CARTOES_MIN);
  const [linhasPorPagina, setLinhasPorPagina] = useState(LINHAS_TAREFA_PADRAO);
  const [agora, setAgora] = useState(() => new Date());

  const pedidoRef = useRef(0);
  const areaRef = useRef<HTMLDivElement | null>(null);
  const linhaAmostraRef = useRef<HTMLDivElement | null>(null);
  // A altura real da linha do layout C so pode ser medida enquanto ele esta na
  // tela. Guardada aqui, ela sobrevive ao desmonte: sem isto a conta voltava
  // para o chute toda vez que o layout A ou B entrava, e o numero de subpaginas
  // (logo, a duracao do bloco C) ficava oscilando.
  const alturaLinhaRef = useRef(ALTURA_LINHA_TAREFA_PX);
  // Em que volta o bloco de tarefas esta. Com mais paginas do que as quatro
  // fatias de 15s, cada volta comeca de onde a anterior parou.
  const [volta, setVolta] = useState(0);
  const quadrosRef = useRef<Quadro[]>([]);
  const indiceRef = useRef(0);

  // Relogio proprio: a TV nao recarrega a pagina, entao a hora anda sozinha.
  useEffect(() => {
    const id = window.setInterval(() => setAgora(new Date()), 1000);
    return () => window.clearInterval(id);
  }, []);

  /* ---------------------------------------------------------------------- */
  /* Leitura                                                                 */
  /* ---------------------------------------------------------------------- */

  const carregar = useCallback(async () => {
    if (!tenantId || !empresaId) return;

    // Guarda de corrida: so a leitura mais nova escreve no estado.
    const pedido = pedidoRef.current + 1;
    pedidoRef.current = pedido;
    const desatualizado = () => pedidoRef.current !== pedido;

    try {
      const { error: erroTenant } = await supabase.rpc("set_current_tenant", {
        p_tenant_id: tenantId,
      });
      if (desatualizado()) return;
      if (erroTenant) throw new Error(erroTenant.message ?? "Erro ao definir tenant atual.");

      const { error: erroEmpresa } = await supabase.rpc("set_current_empresa", {
        p_empresa_id: empresaId,
      });
      if (desatualizado()) return;
      if (erroEmpresa) throw new Error(erroEmpresa.message ?? "Erro ao definir empresa atual.");

      // Semana, mes, feriado e dia util vem daqui. A tela nao decide nada disso.
      const { data: periodosBrutos, error: erroPeriodos } = await supabase.rpc("tv_periodos", {});
      if (desatualizado()) return;
      if (erroPeriodos) throw new Error(erroPeriodos.message ?? "Erro ao carregar o período.");

      const periodo = normalizarPeriodos(periodosBrutos);
      if (!periodo.hoje || !periodo.inicio_semana || !periodo.inicio_mes) {
        throw new Error("O período do painel veio incompleto do banco.");
      }

      // As quatro leituras nao dependem uma da outra: vao juntas para a TV nao
      // ficar meio minuto com dado pela metade.
      const [respColabs, respTarefas, respSemana, respMes, respAusencias] = await Promise.all([
        supabase.rpc("tv_colaboradores", { p_area: areaParam }),
        supabase.rpc("tv_colaboradores_tarefas", { p_area: areaParam }),
        supabase.rpc("tv_horas_periodo", {
          p_inicio: periodo.inicio_semana,
          p_fim: periodo.hoje,
          p_area: areaParam,
        }),
        supabase.rpc("tv_horas_periodo", {
          p_inicio: periodo.inicio_mes,
          p_fim: periodo.hoje,
          p_area: areaParam,
        }),
        // Folga, ferias e outros da semana: e o que sai da cobranca.
        supabase.rpc("tv_ausencias_periodo", {
          p_inicio: periodo.inicio_semana,
          p_fim: periodo.dias[periodo.dias.length - 1]?.data ?? periodo.hoje,
          p_area: areaParam,
        }),
      ]);
      if (desatualizado()) return;

      const primeiroErro =
        respColabs.error ?? respTarefas.error ?? respSemana.error ?? respMes.error ?? respAusencias.error;
      if (primeiroErro) throw new Error(primeiroErro.message ?? "Erro ao carregar o painel.");

      setPeriodos(periodo);
      setColaboradores((respColabs.data ?? []) as ColaboradorTv[]);
      setTarefas((respTarefas.data ?? []) as TarefaLinha[]);
      setHorasSemana((respSemana.data ?? []) as HoraLinha[]);
      setHorasMes((respMes.data ?? []) as HoraLinha[]);
      setAusencias((respAusencias.data ?? []) as AusenciaLinha[]);
      setErro(null);
      setAtualizadoEm(new Date());
      // Vira true na primeira leitura boa e nunca mais muda: e o que solta a
      // rotacao sem que as recargas seguintes reiniciem o ciclo.
      setPronto(true);
    } catch (e: unknown) {
      if (desatualizado()) return;
      // Mantem na tela o ultimo dado bom: uma falha de rede nao pode apagar o
      // painel do chao de fabrica. A proxima recarga tenta de novo.
      setErro(e instanceof Error ? e.message : "Erro inesperado ao carregar o painel.");
    } finally {
      if (!desatualizado()) setCarregando(false);
    }
  }, [supabase, tenantId, empresaId, areaParam]);

  useEffect(() => {
    if (!tenantId || !empresaId) return;
    void carregar();
    const id = window.setInterval(() => {
      void carregar();
    }, RECARGA_MS);
    return () => window.clearInterval(id);
  }, [carregar, tenantId, empresaId]);

  /* ---------------------------------------------------------------------- */
  /* Contas da tela                                                          */
  /* ---------------------------------------------------------------------- */

  const dias = useMemo(() => periodos?.dias ?? [], [periodos]);
  const hoje = periodos?.hoje ?? "";

  // As listas de tarefa da televisao sao sobre TRABALHO. Folga, ferias e outros
  // chegam pela mesma tabela, mas quem mostra ausencia e a grade da semana (o
  // azul) e a linha do dia — nao faz sentido cobrar "ferias atrasada 5 dias".
  const tarefasPendentes = useMemo(
    () =>
      tarefas.filter(
        (tarefa) =>
          tarefa.situacao === "pendente" &&
          tarefa.categoria === "os" &&
          // Numa tarefa de varias pessoas, quem ja fechou a parte dela nao deve
          // mais aparecer como devendo o trabalho de hoje.
          tarefa.participante_concluida_em === null
      ),
    [tarefas]
  );

  const resumos = useMemo<ResumoColaborador[]>(() => {
    const totalSemana = new Map<string, number>();
    const totalMes = new Map<string, number>();
    const porOs = new Map<string, Map<number, OsDaSemana>>();
    const porDia = new Map<string, Map<string, DiaDoColaborador>>();

    for (const linha of horasSemana) {
      const horas = Number(linha.horas ?? 0);
      if (!Number.isFinite(horas)) continue;
      const pendente = (linha.status_aprovacao ?? "pendente") === "pendente";

      totalSemana.set(linha.colaborador_id, (totalSemana.get(linha.colaborador_id) ?? 0) + horas);

      const osDoColaborador = porOs.get(linha.colaborador_id) ?? new Map<number, OsDaSemana>();
      const os = osDoColaborador.get(linha.os_id);
      osDoColaborador.set(linha.os_id, {
        osId: linha.os_id,
        numeroOs: linha.numero_os,
        clienteNome: linha.cliente_nome,
        horas: (os?.horas ?? 0) + horas,
        pendente: (os?.pendente ?? false) || pendente,
      });
      porOs.set(linha.colaborador_id, osDoColaborador);

      const diasDoColaborador =
        porDia.get(linha.colaborador_id) ?? new Map<string, DiaDoColaborador>();
      const dia = diasDoColaborador.get(linha.data);
      diasDoColaborador.set(linha.data, {
        horas: (dia?.horas ?? 0) + horas,
        pendente: (dia?.pendente ?? false) || pendente,
      });
      porDia.set(linha.colaborador_id, diasDoColaborador);
    }

    for (const linha of horasMes) {
      const horas = Number(linha.horas ?? 0);
      if (!Number.isFinite(horas)) continue;
      totalMes.set(linha.colaborador_id, (totalMes.get(linha.colaborador_id) ?? 0) + horas);
    }

    const tarefasDoColaborador = new Map<string, TarefaLinha[]>();
    for (const tarefa of tarefasPendentes) {
      const lista = tarefasDoColaborador.get(tarefa.colaborador_id) ?? [];
      lista.push(tarefa);
      tarefasDoColaborador.set(tarefa.colaborador_id, lista);
    }

    // Folga, ferias e outros, por pessoa e por dia. Ausencia em dias tira o dia
    // inteiro da cobranca; em horas, tira so aquelas horas.
    const ausenciaPorPessoa = new Map<string, Map<string, AusenciaDoDia>>();
    for (const linha of ausencias) {
      const mapa = ausenciaPorPessoa.get(linha.colaborador_id) ?? new Map<string, AusenciaDoDia>();
      const horas = Number(linha.horas ?? 0);
      mapa.set(linha.data, {
        categoria: linha.categoria,
        medida: linha.medida,
        horas: Number.isFinite(horas) ? horas : 0,
      });
      ausenciaPorPessoa.set(linha.colaborador_id, mapa);
    }

    // Dia util ja passado sem apontamento: o banco ja disse quais dias sao uteis
    // (fim de semana e feriado municipal incluidos) e quais ja passaram.
    //
    // HOJE nao entra na cobranca. O apontamento chega ao longo do dia, pelo
    // tablet: se o proprio dia contasse, a fabrica inteira amanheceria com o
    // quadrado vermelho e o total em vermelho, e o alerta que deveria denunciar
    // quem esqueceu de apontar ontem viraria ruido diario.
    const diasCobrados = dias.filter(
      (dia) => dia.eh_util && dia.passado && dia.data !== hoje
    );

    return colaboradores.map((colaborador) => {
      const diasDoColaborador = porDia.get(colaborador.id) ?? new Map<string, DiaDoColaborador>();
      const listaTarefas = tarefasDoColaborador.get(colaborador.id) ?? [];
      const osSemana = Array.from(porOs.get(colaborador.id)?.values() ?? []).sort((a, b) => {
        if (b.horas !== a.horas) return b.horas - a.horas;
        return a.numeroOs.localeCompare(b.numeroOs, "pt-BR", { numeric: true });
      });

      const ausenciaDoColaborador =
        ausenciaPorPessoa.get(colaborador.id) ?? new Map<string, AusenciaDoDia>();

      // Meta da semana: o previsto de cada dia menos o que a ausencia tirou.
      let metaSemana = 0;
      for (const dia of dias) {
        const previsto = Number(dia.horas_previstas ?? 0);
        if (previsto <= 0) continue;
        const ausencia = ausenciaDoColaborador.get(dia.data);
        if (!ausencia) {
          metaSemana += previsto;
          continue;
        }
        if (ausencia.medida === "dias") continue; // o dia inteiro saiu
        metaSemana += Math.max(0, previsto - ausencia.horas);
      }

      return {
        id: colaborador.id,
        nome: colaborador.nome,
        primeiroNome: primeiroNomeDe(colaborador.nome),
        horasSemana: totalSemana.get(colaborador.id) ?? 0,
        horasMes: totalMes.get(colaborador.id) ?? 0,
        osSemana,
        porDia: diasDoColaborador,
        ausenciaPorDia: ausenciaDoColaborador,
        metaSemana,
        ausenciaDaSemana: resumirAusencia(ausenciaDoColaborador, dias),
        // Dia de folga ou ferias nao e falta: saiu da cobranca por decisao do
        // Gabriel ("desconta da semana, tira da cobranca").
        faltasEmDiaUtil: diasCobrados.filter(
          (dia) =>
            (diasDoColaborador.get(dia.data)?.horas ?? 0) <= 0 &&
            ausenciaDoColaborador.get(dia.data)?.medida !== "dias"
        ).length,
        tarefasPendentes: listaTarefas,
        tarefasComData: listaTarefas.filter((tarefa) => tarefa.data !== null),
        tarefasSemData: listaTarefas.filter((tarefa) => tarefa.data === null).length,
      } satisfies ResumoColaborador;
    });
  }, [colaboradores, horasSemana, horasMes, tarefasPendentes, dias, hoje, ausencias]);

  // Escala das barras do layout B: a maior hora de um dia, entre todos.
  const maiorHoraDoDia = useMemo(() => {
    let maior = 0;
    for (const resumo of resumos) {
      for (const dia of resumo.porDia.values()) {
        if (dia.horas > maior) maior = dia.horas;
      }
    }
    return maior;
  }, [resumos]);

  // Layout C: as tarefas de hoje e as atrasadas, atrasadas em cima (o banco ja
  // devolve nessa ordem), e no fim quem esta ativo e nao tem nada para hoje.
  const linhasDoDia = useMemo<LinhaDoDia[]>(() => {
    const doDia = tarefasPendentes.filter((tarefa) => tarefa.atrasada || tarefa.hoje);
    const ocupados = new Set(doDia.map((tarefa) => tarefa.colaborador_id));
    const linhas: LinhaDoDia[] = doDia.map((tarefa) => ({
      // A tarefa vem uma vez por participante: a chave e o par tarefa+pessoa,
      // senao uma tarefa de tres pessoas repete a chave tres vezes e o React
      // descarta duas das linhas.
      chave: `tarefa-${tarefa.id}-${tarefa.colaborador_id}`,
      tipo: "tarefa",
      tarefa,
      diasAtraso: tarefa.atrasada ? diferencaEmDias(tarefa.data, hoje) : 0,
    }));
    // A RPC tambem devolve o que foi concluido hoje. Sem isto, quem fechou
    // todas as tarefas do dia aparecia como "Sem tarefa hoje", que e a leitura
    // errada para a coordenacao.
    // A RPC devolve as pendentes e o que foi fechado hoje. Contar pela parte da
    // PESSOA pega os dois casos: a tarefa que fechou inteira e a tarefa de varias
    // pessoas em que ela fez a parte dela e os outros ainda nao.
    const concluidasPorColaborador = new Map<string, number>();
    for (const tarefa of tarefas) {
      if (tarefa.participante_concluida_em === null || tarefa.categoria !== "os") continue;
      concluidasPorColaborador.set(
        tarefa.colaborador_id,
        (concluidasPorColaborador.get(tarefa.colaborador_id) ?? 0) + 1
      );
    }
    for (const resumo of resumos) {
      if (ocupados.has(resumo.id)) continue;
      linhas.push({
        chave: `ocioso-${resumo.id}`,
        tipo: "ocioso",
        resumo,
        concluidasHoje: concluidasPorColaborador.get(resumo.id) ?? 0,
        ausenciaHoje: resumo.ausenciaPorDia.get(hoje),
      });
    }
    return linhas;
  }, [tarefasPendentes, tarefas, resumos, hoje]);

  const temTarefaDoDia = useMemo(
    () => linhasDoDia.some((linha) => linha.tipo === "tarefa"),
    [linhasDoDia]
  );

  /* ---------------------------------------------------------------------- */
  /* Sequencia de quadros                                                    */
  /* ---------------------------------------------------------------------- */

  const quadros = useMemo<Quadro[]>(() => {
    const lista: Quadro[] = [];

    // A: uma pagina a cada 15s ate percorrer todos os colaboradores da area.
    const paginasCartoes =
      resumos.length === 0 ? 0 : Math.max(1, Math.ceil(resumos.length / cartoesPorPagina));
    for (let i = 0; i < paginasCartoes; i += 1) {
      lista.push({ layout: "cartoes", pagina: i, totalPaginas: paginasCartoes, ms: MS_CARTOES });
    }

    // B: pagina unica, 30s. So entra se houver alguem para desenhar linha.
    if (resumos.length > 0) {
      const paginasBarras = Math.max(1, Math.ceil(resumos.length / COLABORADORES_POR_PAGINA_B));
      for (let i = 0; i < paginasBarras; i += 1) {
        lista.push({ layout: "barras", pagina: i, totalPaginas: paginasBarras, ms: MS_BARRAS });
      }
    }

    // C: 60s. Sem tarefa de hoje nem atrasada o layout fica fora do ciclo.
    if (temTarefaDoDia) {
      const paginasTarefas = Math.max(1, Math.ceil(linhasDoDia.length / linhasPorPagina));
      if (paginasTarefas <= 1) {
        lista.push({ layout: "tarefas", pagina: 0, totalPaginas: 1, ms: MS_TAREFAS });
      } else {
        // Nao coube numa pagina: quatro subpaginas de 15s DENTRO dos 60s, nunca
        // mais que isso. Com mais de quatro paginas, a volta seguinte comeca de
        // onde esta parou, entao com o tempo todas aparecem sem
        // o bloco esticar.
        const inicio = volta % paginasTarefas;
        for (let i = 0; i < SUBPAGINAS_TAREFAS; i += 1) {
          lista.push({
            layout: "tarefas",
            pagina: (inicio + i) % paginasTarefas,
            totalPaginas: paginasTarefas,
            ms: MS_TAREFAS_SUB,
          });
        }
      }
    }

    return lista;
  }, [resumos.length, cartoesPorPagina, temTarefaDoDia, linhasDoDia.length, linhasPorPagina, volta]);

  // A rotacao le a lista por esta referencia, nunca pelas dependencias de um
  // efeito: e isso que faz a recarga de 2 minutos (que pode mudar o numero de
  // quadros) nao reiniciar o ciclo nem piscar a tela.
  useEffect(() => {
    quadrosRef.current = quadros;
  }, [quadros]);

  useEffect(() => {
    // Quadro unico (ou nenhum): sem troca para acender de volta, entao a
    // opacidade tem de voltar aqui. Sem isto a televisao apagaria e so voltaria
    // se alguem recarregasse a pagina.
    if (quadros.length <= 1) setFadeVisivel(true);
  }, [quadros.length]);

  useEffect(() => {
    if (!pronto) return;

    let vivo = true;
    let timerQuadro: number | null = null;
    let timerFade: number | null = null;

    function agendar(ms: number) {
      timerQuadro = window.setTimeout(tique, Math.max(1_000, ms));
    }

    function tique() {
      if (!vivo) return;
      const lista = quadrosRef.current;
      if (lista.length <= 1) {
        // Nada para girar agora. Nao apaga nada e reconfere no proximo tempo de
        // quadro: quando a recarga trouxer mais conteudo, a rotacao volta
        // sozinha, sem reiniciar o ciclo.
        setFadeVisivel(true);
        agendar(lista[0]?.ms ?? MS_CARTOES);
        return;
      }
      setFadeVisivel(false);
      timerFade = window.setTimeout(() => {
        if (!vivo) return;
        const atual = quadrosRef.current;
        const total = Math.max(1, atual.length);
        const base = indiceRef.current >= total ? total - 1 : indiceRef.current;
        const proximo = (base + 1) % total;
        // Fechou a volta inteira: o bloco de tarefas comeca na proxima pagina,
        // para quem tem mais de quatro paginas nao ficar sem aparecer nunca.
        if (proximo === 0) setVolta((atual) => atual + 1);
        indiceRef.current = proximo;
        setQuadroIndex(proximo);
        setFadeVisivel(true);
        agendar(atual[proximo]?.ms ?? MS_CARTOES);
      }, FADE_MS);
    }

    agendar(quadrosRef.current[indiceRef.current]?.ms ?? MS_CARTOES);

    return () => {
      vivo = false;
      if (timerQuadro) window.clearTimeout(timerQuadro);
      if (timerFade) window.clearTimeout(timerFade);
      // Toda saida deste efeito devolve a opacidade: se a troca for abortada no
      // meio do fade, sem isto o conteudo ficaria preso em opacity 0.
      setFadeVisivel(true);
    };
  }, [pronto]);

  // O indice so e limitado na hora de desenhar. Nada de zerar quando a lista
  // encolhe: a proxima troca ja normaliza, e o ciclo segue de onde estava.
  const quadroAtual =
    quadros.length === 0
      ? QUADRO_PADRAO
      : quadros[Math.min(quadroIndex, quadros.length - 1)] ?? QUADRO_PADRAO;

  /* ---------------------------------------------------------------------- */
  /* Medicao                                                                 */
  /* ---------------------------------------------------------------------- */

  // A area util esta sempre montada, qualquer que seja o layout: medir por ela
  // deixa a paginacao pronta antes de o layout aparecer pela primeira vez, e o
  // numero de quadros nao muda no meio do giro.
  const medir = useCallback(() => {
    const area = areaRef.current;
    if (!area) return;

    const largura = area.clientWidth;
    if (largura > 0) {
      const cabem = Math.floor(
        (largura + CARTAO_GAP_PX) / (CARTAO_LARGURA_MIN_PX + CARTAO_GAP_PX)
      );
      const proximo = Math.min(CARTOES_MAX, Math.max(CARTOES_MIN, cabem));
      setCartoesPorPagina((atual) => (atual === proximo ? atual : proximo));
    }

    const altura = area.clientHeight;
    if (altura > 0) {
      const medida = linhaAmostraRef.current?.getBoundingClientRect().height ?? 0;
      if (medida > 0) alturaLinhaRef.current = medida;
      const alturaLinha = alturaLinhaRef.current;
      const proximo = Math.max(1, Math.floor(altura / Math.max(alturaLinha, 40)));
      setLinhasPorPagina((atual) => (atual === proximo ? atual : proximo));
    }
  }, []);

  useEffect(() => {
    medir();
  }, [medir, quadroAtual.layout, quadroAtual.pagina, resumos.length, linhasDoDia.length]);

  useEffect(() => {
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(medir);
    if (areaRef.current) observer?.observe(areaRef.current);
    if (linhaAmostraRef.current) observer?.observe(linhaAmostraRef.current);
    window.addEventListener("resize", medir);
    return () => {
      observer?.disconnect();
      window.removeEventListener("resize", medir);
    };
  }, [medir, quadroAtual.layout]);

  const barrasDaPagina = useMemo(() => {
    const inicio = quadroAtual.pagina * COLABORADORES_POR_PAGINA_B;
    return resumos.slice(inicio, inicio + COLABORADORES_POR_PAGINA_B);
  }, [resumos, quadroAtual.pagina]);

  const cartoesDaPagina = useMemo(() => {
    const inicio = quadroAtual.pagina * cartoesPorPagina;
    return resumos.slice(inicio, inicio + cartoesPorPagina);
  }, [resumos, quadroAtual.pagina, cartoesPorPagina]);

  const linhasDaPagina = useMemo(() => {
    const inicio = quadroAtual.pagina * linhasPorPagina;
    return linhasDoDia.slice(inicio, inicio + linhasPorPagina);
  }, [linhasDoDia, quadroAtual.pagina, linhasPorPagina]);

  /* ---------------------------------------------------------------------- */
  /* Cabecalho e rodape                                                      */
  /* ---------------------------------------------------------------------- */

  const horaAgora = agora.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  const horaAtualizacao = atualizadoEm
    ? atualizadoEm.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })
    : null;
  const areaExibida = rotuloArea(areaParam);

  const dowDeHoje = useMemo(() => {
    const noPeriodo = dias.find((dia) => dia.data === hoje)?.dow;
    if (noPeriodo && noPeriodo >= 1 && noPeriodo <= 7) return noPeriodo;
    return isodowDaData(hoje);
  }, [dias, hoje]);

  const titulo = useMemo(() => {
    if (!periodos) return areaExibida;
    if (quadroAtual.layout === "barras") return `${areaExibida} · horas da semana`;
    if (quadroAtual.layout === "tarefas") {
      const extenso = dowDeHoje ? DOW_EXTENSO[dowDeHoje - 1] : "";
      return extenso
        ? `${areaExibida} · hoje, ${extenso} ${diaEMes(hoje)}`
        : `${areaExibida} · hoje, ${diaEMes(hoje)}`;
    }
    return `${areaExibida} · semana ${rotuloPeriodo(periodos.inicio_semana, periodos.hoje)}`;
  }, [periodos, areaExibida, quadroAtual.layout, dowDeHoje, hoje]);

  const legenda = useMemo(() => {
    if (quadroAtual.layout === "barras") {
      return "vermelho = dia útil sem apontamento · amarelo = hora pendente de aprovação · azul = folga ou férias";
    }
    if (quadroAtual.layout === "tarefas") return "vermelho = atrasada";
    return "hora pendente de aprovação";
  }, [quadroAtual.layout]);

  return (
    <div
      className="h-[calc(100dvh-3rem)] overflow-hidden flex flex-col rounded-2xl"
      style={{ background: FUNDO, color: TEXTO }}
    >
      <header className="shrink-0 flex items-baseline gap-6 px-8 pt-6 pb-4">
        <h1 className="min-w-0 truncate text-3xl font-medium" style={{ color: TEXTO_2 }}>
          {titulo}
        </h1>
        <div className="flex-1" />
        <div className="text-3xl font-medium tabular-nums" style={{ color: TEXTO_2 }}>
          {horaAgora}
        </div>
      </header>

      {erro && (
        <div
          className="shrink-0 mx-8 mb-4 rounded-xl px-6 py-4 text-3xl font-semibold"
          style={{ background: VERMELHO_FUNDO, color: VERMELHO }}
        >
          {erro}
        </div>
      )}

      <div
        ref={areaRef}
        className="flex-1 min-h-0 px-8"
        style={{ opacity: fadeVisivel ? 1 : 0, transition: `opacity ${FADE_MS / 1000}s ease` }}
      >
        {!periodos ? (
          <div className="h-full flex items-center justify-center text-4xl" style={{ color: TEXTO_2 }}>
            {carregando ? "Carregando painel…" : "Não foi possível carregar o painel."}
          </div>
        ) : quadroAtual.layout === "cartoes" ? (
          <LayoutCartoes
            cartoes={cartoesDaPagina}
            porPagina={cartoesPorPagina}
            vazio={resumos.length === 0}
          />
        ) : quadroAtual.layout === "barras" ? (
          <LayoutBarras resumos={barrasDaPagina} dias={dias} maiorHoraDoDia={maiorHoraDoDia} />
        ) : (
          <LayoutTarefas linhas={linhasDaPagina} amostraRef={linhaAmostraRef} />
        )}
      </div>

      <footer
        className="shrink-0 flex items-baseline gap-6 px-8 pt-4 pb-6 text-xl"
        style={{ color: TEXTO_3 }}
      >
        <span className="flex items-center gap-2 min-w-0 truncate">
          {quadroAtual.layout === "cartoes" && (
            <span
              className="inline-block h-2.5 w-2.5 rounded-full shrink-0"
              style={{ background: AMARELO }}
            />
          )}
          {legenda}
        </span>
        <div className="flex-1" />
        <span className="shrink-0 tabular-nums">
          {quadroAtual.totalPaginas > 1 && (
            <>
              página {quadroAtual.pagina + 1} de {quadroAtual.totalPaginas}
              {" · "}
            </>
          )}
          {horaAtualizacao ? `atualizado ${horaAtualizacao}` : "aguardando primeira leitura"}
        </span>
      </footer>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Layout A — cartoes por colaborador                                          */
/* -------------------------------------------------------------------------- */

function LayoutCartoes({
  cartoes,
  porPagina,
  vazio,
}: {
  cartoes: ResumoColaborador[];
  porPagina: number;
  vazio: boolean;
}) {
  if (vazio) {
    return (
      <div className="h-full flex items-center justify-center text-4xl" style={{ color: TEXTO_2 }}>
        Nenhum colaborador ativo nesta área.
      </div>
    );
  }

  return (
    <div
      className="h-full grid items-stretch"
      style={{
        gridTemplateColumns: `repeat(${Math.max(1, porPagina)}, minmax(0, 1fr))`,
        gap: `${CARTAO_GAP_PX}px`,
      }}
    >
      {cartoes.map((resumo) => (
        <CartaoColaborador key={resumo.id} resumo={resumo} />
      ))}
    </div>
  );
}

function CartaoColaborador({ resumo }: { resumo: ResumoColaborador }) {
  const cor = corDoColaborador(resumo.id);
  const osVisiveis = resumo.osSemana.slice(0, MAX_OS_NO_CARTAO);
  const osRestantes = resumo.osSemana.length - osVisiveis.length;
  const tarefasVisiveis = resumo.tarefasComData.slice(0, MAX_TAREFAS_NO_CARTAO);

  return (
    <article
      className="min-w-0 overflow-hidden rounded-2xl px-7 py-6 flex flex-col"
      style={{ background: CARTAO }}
    >
      <div className="flex items-center gap-4">
        <span
          className="shrink-0 grid place-items-center rounded-full h-14 w-14 text-xl font-bold"
          style={{ background: cor, color: FUNDO }}
        >
          {iniciaisDoNome(resumo.nome)}
        </span>
        <span className="min-w-0 truncate text-4xl font-semibold" style={{ color: TEXTO }}>
          {resumo.primeiroNome}
        </span>
      </div>

      <div className="mt-5 flex items-baseline gap-3">
        <span className="text-7xl font-black leading-none tabular-nums" style={{ color: TEXTO }}>
          {formatarHoras(resumo.horasSemana)}
        </span>
        <span className="text-2xl" style={{ color: TEXTO_2 }}>
          semana
        </span>
      </div>
      <div className="mt-2 text-2xl tabular-nums" style={{ color: TEXTO_2 }}>
        {formatarHoras(resumo.horasMes)} no mês
      </div>
      {/* Meta da semana pela jornada da fabrica (44h), ja descontando folga e
          ferias. Some quando nao ha jornada cadastrada para a empresa. */}
      {/* Por que a meta caiu: folga e ferias tiram o dia (ou as horas) da
          cobranca, e sem dizer isso o numero menor parece defeito. */}
      {resumo.ausenciaDaSemana ? (
        <div className="mt-1 text-xl" style={{ color: AZUL }}>
          {resumo.ausenciaDaSemana}
        </div>
      ) : null}
      {resumo.metaSemana > 0 ? (
        <div className="mt-1 text-xl tabular-nums" style={{ color: resumo.horasSemana >= resumo.metaSemana ? VERDE : AMARELO }}>
          {resumo.horasSemana >= resumo.metaSemana
            ? `meta de ${formatarHoras(resumo.metaSemana)} cumprida`
            : `meta ${formatarHoras(resumo.metaSemana)} · faltam ${formatarHoras(resumo.metaSemana - resumo.horasSemana)}`}
        </div>
      ) : null}

      <div className="my-5 h-px shrink-0" style={{ background: DIVISORIA }} />

      {resumo.osSemana.length === 0 ? (
        <div className="text-2xl" style={{ color: TEXTO_2 }}>
          Sem apontamento nesta semana
        </div>
      ) : (
        <ul className="space-y-2">
          {osVisiveis.map((os) => (
            <li key={os.osId} className="flex items-baseline gap-4">
              <span className="min-w-0 flex-1 truncate text-2xl" style={{ color: TEXTO }}>
                <span className="tabular-nums font-semibold">OS {os.numeroOs}</span>
                <span style={{ color: TEXTO_2 }}> · {os.clienteNome}</span>
              </span>
              <span
                className="shrink-0 text-2xl font-semibold tabular-nums"
                style={{ color: TEXTO }}
              >
                {formatarHoras(os.horas)}
              </span>
              {/* Ponto amarelo: aquela OS tem hora esperando aprovacao. */}
              <span
                className="shrink-0 inline-block h-2.5 w-2.5 rounded-full"
                style={{ background: os.pendente ? AMARELO : "transparent" }}
              />
            </li>
          ))}
          {osRestantes > 0 && (
            <li className="text-xl" style={{ color: TEXTO_3 }}>
              +{osRestantes} OS
            </li>
          )}
        </ul>
      )}

      <div className="my-5 h-px shrink-0" style={{ background: DIVISORIA }} />

      {resumo.tarefasPendentes.length === 0 ? (
        <div className="text-2xl" style={{ color: TEXTO_2 }}>
          Sem tarefa pendente
        </div>
      ) : (
        <>
          <div className="text-2xl" style={{ color: TEXTO_2 }}>
            Tarefas pendentes · {resumo.tarefasPendentes.length}
          </div>
          <ul className="mt-2 space-y-1">
            {tarefasVisiveis.map((tarefa) => (
              <li
                key={tarefa.id}
                className="text-2xl leading-snug"
                style={{ color: tarefa.atrasada ? VERMELHO : TEXTO }}
              >
                {prefixoDaTarefa(tarefa)} · <span className="tabular-nums">OS {tarefa.numero_os}</span>{" "}
                {descricaoDaTarefa(tarefa)}
                {tarefa.atrasada ? " (atrasada)" : ""}
              </li>
            ))}
            {resumo.tarefasSemData > 0 && (
              <li className="text-2xl" style={{ color: TEXTO_3 }}>
                Sem data · {resumo.tarefasSemData}
              </li>
            )}
          </ul>
        </>
      )}
    </article>
  );
}

/* -------------------------------------------------------------------------- */
/* Layout B — barras da semana                                                 */
/* -------------------------------------------------------------------------- */

function LayoutBarras({
  resumos,
  dias,
  maiorHoraDoDia,
}: {
  resumos: ResumoColaborador[];
  dias: DiaPeriodo[];
  maiorHoraDoDia: number;
}) {
  // A grade dos sete dias vem do banco (tv_periodos): dia util, feriado e o que
  // ja passou sao decisao dele, nao da televisao.
  const grade = `minmax(8rem, 14rem) repeat(${Math.max(1, dias.length)}, minmax(0, 1fr)) 8rem`;

  return (
    <div className="h-full flex flex-col">
      <div className="shrink-0 grid items-baseline gap-4 pb-3" style={{ gridTemplateColumns: grade }}>
        <span />
        {dias.map((dia) => (
          <span key={dia.data} className="text-xl text-center" style={{ color: TEXTO_3 }}>
            {DOW_ABREV[(dia.dow || 1) - 1] ?? ""}
          </span>
        ))}
        <span className="text-xl text-right" style={{ color: TEXTO_3 }}>
          total
        </span>
      </div>

      <div className="flex-1 min-h-0 overflow-hidden flex flex-col">
        {resumos.map((resumo) => (
          <div
            key={resumo.id}
            // items-stretch de proposito: a celula do dia precisa da altura da
            // linha para desenhar a barra proporcional e o quadrado vermelho.
            className="flex-1 min-h-0 grid items-stretch gap-4 py-2"
            style={{ gridTemplateColumns: grade, borderTop: `1px solid ${DIVISORIA}` }}
          >
            <span className="self-center min-w-0 truncate text-3xl" style={{ color: TEXTO }}>
              {resumo.primeiroNome}
            </span>

            {dias.map((dia) => (
              <CelulaDoDia
                key={dia.data}
                dia={dia}
                lancamento={resumo.porDia.get(dia.data)}
                ausencia={resumo.ausenciaPorDia.get(dia.data)}
                maiorHoraDoDia={maiorHoraDoDia}
              />
            ))}

            <span
              className="self-center text-right text-4xl font-bold tabular-nums"
              style={{ color: resumo.faltasEmDiaUtil > 0 ? VERMELHO : TEXTO }}
            >
              {formatarHoras(resumo.horasSemana)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function CelulaDoDia({
  dia,
  lancamento,
  ausencia,
  maiorHoraDoDia,
}: {
  dia: DiaPeriodo;
  lancamento: DiaDoColaborador | undefined;
  ausencia: AusenciaDoDia | undefined;
  maiorHoraDoDia: number;
}) {
  const horas = lancamento?.horas ?? 0;

  // Folga ou ferias do dia inteiro: azul, sem cobranca. Nao e falta, e dia que
  // saiu da conta da semana.
  if (ausencia && ausencia.medida === "dias") {
    return (
      <div className="h-full flex items-end">
        <div
          className="w-full rounded-md grid place-items-center text-lg font-semibold"
          style={{
            height: "100%",
            maxHeight: `${BARRA_ALTURA_MAX_PX}px`,
            border: `2px solid ${AZUL}`,
            background: "rgba(79,143,209,0.16)",
            color: AZUL,
          }}
        >
          {ROTULO_AUSENCIA[ausencia.categoria] ?? "Ausente"}
        </div>
      </div>
    );
  }

  if (horas > 0) {
    const proporcao = maiorHoraDoDia > 0 ? horas / maiorHoraDoDia : 1;
    const altura = Math.min(100, Math.max(22, Math.round(proporcao * 100)));
    return (
      <div className="h-full flex items-end justify-center">
        <div
          className="w-full rounded-md"
          style={{
            height: `${altura}%`,
            minHeight: "0.75rem",
            maxHeight: `${BARRA_ALTURA_MAX_PX}px`,
            background: lancamento?.pendente ? AMARELO : VERDE,
          }}
          title={formatarHoras(horas)}
        />
      </div>
    );
  }

  // Dia util que ja passou e ninguem apontou: e o que a coordenacao precisa ver.
  // Com folga em horas no dia, o alerta continua valendo (a pessoa trabalhou o
  // resto do dia e mesmo assim nao apontou nada), mas a marca fica azul para a
  // coordenacao saber que parte do dia estava liberada.
  if (dia.eh_util && dia.passado) {
    if (ausencia) {
      return (
        <div className="h-full flex items-end">
          <div
            className="w-full rounded-md grid place-items-center text-lg font-semibold"
            style={{
              height: "100%",
              maxHeight: `${BARRA_ALTURA_MAX_PX}px`,
              border: `2px solid ${AZUL}`,
              color: AZUL,
            }}
          >
            {formatarHoras(ausencia.horas)}
          </div>
        </div>
      );
    }
    return (
      <div className="h-full flex items-end">
        <div
          className="w-full rounded-md grid place-items-center text-xl font-semibold"
          style={{
            height: "100%",
            maxHeight: `${BARRA_ALTURA_MAX_PX}px`,
            border: `2px solid ${VERMELHO_BORDA}`,
            color: VERMELHO,
          }}
        >
          0h
        </div>
      </div>
    );
  }

  // Fim de semana, feriado ou dia que ainda nao chegou: barrinha baixa, sem
  // alerta nenhum.
  return (
    <div className="h-full flex items-end">
      <div className="w-full rounded-md h-2.5" style={{ background: BARRA_VAZIA }} />
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Layout C — tarefas do dia                                                   */
/* -------------------------------------------------------------------------- */

function LayoutTarefas({
  linhas,
  amostraRef,
}: {
  linhas: LinhaDoDia[];
  amostraRef: Ref<HTMLDivElement> | null;
}) {
  return (
    <div className="h-full overflow-hidden flex flex-col">
      {linhas.map((linha, indice) =>
        linha.tipo === "tarefa" ? (
          <LinhaTarefaDoDia
            key={linha.chave}
            ref={indice === 0 ? amostraRef : null}
            tarefa={linha.tarefa}
            diasAtraso={linha.diasAtraso}
            primeira={indice === 0}
          />
        ) : (
          <LinhaSemTarefa
            key={linha.chave}
            ref={indice === 0 ? amostraRef : null}
            resumo={linha.resumo}
            concluidasHoje={linha.concluidasHoje}
            ausenciaHoje={linha.ausenciaHoje}
            primeira={indice === 0}
          />
        )
      )}
    </div>
  );
}

const GRADE_TAREFA = "minmax(9rem, 14rem) 9rem minmax(0, 1fr)";

function LinhaTarefaDoDia({
  tarefa,
  diasAtraso,
  primeira,
  ref,
}: {
  tarefa: TarefaLinha;
  diasAtraso: number;
  primeira: boolean;
  ref: Ref<HTMLDivElement> | null;
}) {
  const atrasada = tarefa.atrasada;
  // Tarefa de mais de uma pessoa: a linha e por pessoa, entao diz com quantas
  // mais ela divide o servico.
  const acompanhados = Math.max(0, (tarefa.participantes ?? 1) - 1);
  const sufixo =
    (atrasada && diasAtraso > 0
      ? ` · atrasada ${diasAtraso} ${diasAtraso === 1 ? "dia" : "dias"}`
      : atrasada
        ? " · atrasada"
        : "") +
    (acompanhados > 0
      ? ` · com mais ${acompanhados} ${acompanhados === 1 ? "pessoa" : "pessoas"}`
      : "");

  return (
    <div
      ref={ref}
      className="shrink-0 grid items-center gap-6 px-4 py-4 rounded-xl"
      style={{
        gridTemplateColumns: GRADE_TAREFA,
        height: `${ALTURA_LINHA_TAREFA_PX}px`,
        background: atrasada ? VERMELHO_FUNDO : "transparent",
        // A borda de cima some na primeira linha e na faixa vermelha, mas
        // continua ocupando o mesmo 1px: assim a altura da linha e sempre a
        // mesma e a conta de quantas cabem na pagina nao oscila.
        borderTop:
          primeira || atrasada ? "1px solid transparent" : `1px solid ${DIVISORIA}`,
      }}
    >
      <span className="min-w-0 truncate text-3xl" style={{ color: atrasada ? VERMELHO : TEXTO }}>
        {primeiroNomeDe(tarefa.colaborador_nome)}
      </span>

      <span
        className="text-4xl font-semibold tabular-nums truncate"
        style={{ color: atrasada ? VERMELHO : TEXTO }}
      >
        {tarefa.numero_os}
      </span>

      <span className="min-w-0">
        <span
          className="block truncate text-3xl"
          style={{ color: atrasada ? VERMELHO : TEXTO }}
        >
          {descricaoDaTarefa(tarefa)}
          {sufixo}
        </span>
        <span className="block truncate text-2xl" style={{ color: atrasada ? VERMELHO : TEXTO_3 }}>
          {tarefa.cliente_nome}
        </span>
      </span>
    </div>
  );
}

function LinhaSemTarefa({
  resumo,
  concluidasHoje,
  ausenciaHoje,
  primeira,
  ref,
}: {
  resumo: ResumoColaborador;
  concluidasHoje: number;
  ausenciaHoje?: AusenciaDoDia;
  primeira: boolean;
  ref: Ref<HTMLDivElement> | null;
}) {
  // Ausencia do dia inteiro: a linha e azul e diz o motivo. Quem esta de ferias
  // nao esta "sem tarefa hoje" — nao e cobranca, e informacao.
  const foraHoje = ausenciaHoje?.medida === "dias";
  const cor = foraHoje ? AZUL : TEXTO_3;

  return (
    <div
      ref={ref}
      className="shrink-0 grid items-center gap-6 px-4 py-4"
      style={{
        gridTemplateColumns: GRADE_TAREFA,
        height: `${ALTURA_LINHA_TAREFA_PX}px`,
        borderTop: primeira ? "1px solid transparent" : `1px solid ${DIVISORIA}`,
      }}
    >
      <span className="min-w-0 truncate text-3xl" style={{ color: cor }}>
        {resumo.primeiroNome}
      </span>
      <span className="text-4xl" style={{ color: cor }}>
        —
      </span>
      <span className="min-w-0 truncate text-3xl" style={{ color: cor }}>
        {foraHoje
          ? (ROTULO_AUSENCIA[ausenciaHoje.categoria] ?? "Ausente")
          : concluidasHoje > 0
            ? `Concluiu ${concluidasHoje} hoje`
            : "Sem tarefa hoje"}
        {ausenciaHoje && !foraHoje
          ? ` · ${ROTULO_AUSENCIA[ausenciaHoje.categoria] ?? "Ausente"} de ${formatarHoras(ausenciaHoje.horas)}`
          : ""}
        {resumo.tarefasSemData > 0 ? ` · ${resumo.tarefasSemData} sem data` : ""}
      </span>
    </div>
  );
}

/* -------------------------------------------------------------------------- */

function TelaMensagem({ titulo }: { titulo: string }) {
  return (
    <div
      className="h-[calc(100dvh-3rem)] flex items-center justify-center rounded-2xl text-4xl"
      style={{ background: FUNDO, color: TEXTO_2 }}
    >
      {titulo}
    </div>
  );
}
