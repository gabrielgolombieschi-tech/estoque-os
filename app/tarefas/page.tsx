"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { supabaseBrowser } from "@/lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";

// Tarefas: agenda de colaborador com reserva do dia inteiro. Quem decide e o
// banco (app_tarefas_*): a tela so mostra o que as flags pode_criar /
// pode_gerir / pode_concluir permitem e repassa a mensagem do servidor quando
// algo falha. Nunca mostra sucesso sem o servidor devolver sucesso = true, e
// criar/concluir mandam uma chave por tentativa para o toque repetido nao
// duplicar (a mesma chave e reenviada em falha; nova chave so depois do sucesso).

type ErroRpc = { tipo: string; mensagem: string };

type Contexto = {
  gestao: boolean;
  pode_criar: boolean;
  papel: string;
  colaborador_id: string | null;
  hoje: string;
};

type Contadores = {
  hoje: number;
  atrasadas: number;
  futuras: number;
  agendadas: number;
  sem_data: number;
  ausencias: number;
  atencao: number;
  minhas_pendentes: number;
  gestao: boolean;
  pode_criar: boolean;
  hoje_data: string;
};

// 'falta_justificada' e a falta COM atestado e 'falta' a falta SEM atestado: e a
// mesma ausencia, o que muda e o documento. A justificada desconta da meta da
// semana, como folga e ferias; a sem atestado nao desconta (conta da TV, que e
// outra frente). O atestado que chega dias depois troca uma pela outra na mesma
// linha, por app_tarefas_marcar_atestado — nada e apagado nem recadastrado.
type Categoria = "os" | "folga" | "ferias" | "falta_justificada" | "falta" | "outro";
type Medida = "dias" | "horas";

// Uma linha por PARTICIPANTE: a tarefa de tres pessoas vem tres vezes e cada
// linha fala da parte daquela pessoa. Em ausencia (categoria <> 'os') o banco
// manda os campos de OS nulos.
type Tarefa = {
  id: string;
  tipo: "agendada" | "sem_data";
  data: string | null;
  situacao: "pendente" | "concluida" | "cancelada";
  colaborador_id: string;
  colaborador_nome: string;
  minha: boolean;
  os_id: number | null;
  numero_os: string | null;
  cliente_id: number | null;
  cliente_nome: string | null;
  os_descricao: string | null;
  os_status_fluxo: string | null;
  descricao: string;
  criado_em: string;
  criado_por_nome: string | null;
  atualizado_em: string;
  concluida_em: string | null;
  concluida_por_nome: string | null;
  concluida_pelo_tablet: boolean;
  cancelada_em: string | null;
  cancelada_por_nome: string | null;
  cancelamento_motivo: string | null;
  reserva_ativa: boolean;
  reserva_liberada_em: string | null;
  reserva_liberada_por_nome: string | null;
  reserva_liberacao_motivo: string | null;
  atrasada: boolean;
  hoje: boolean;
  pode_gerir: boolean;
  pode_concluir: boolean;
  categoria: Categoria;
  medida: Medida;
  dias: number | null;
  horas: number | null;
  data_fim: string | null;
  participantes: number;
  participante_concluida_em: string | null;
};

type Participante = {
  colaborador_id: string;
  nome: string;
  concluida_em: string | null;
  concluida_por_nome: string | null;
  concluida_pelo_tablet: boolean;
};

type Colaborador = {
  id: string;
  nome: string;
  cargo: string | null;
  sou_eu: boolean;
  ocupado: boolean;
  ocupado_tarefa_id: string | null;
  ocupado_resumo: string | null;
};

type OsElegivel = {
  id: number;
  numero_os: string;
  os_num: number | null;
  cliente_id: number | null;
  cliente_nome: string;
  descricao_servico: string | null;
  status_fluxo: string | null;
  usa_relatorio_hh: boolean;
  responsavel_nome: string | null;
  tarefas_pendentes: number;
};

type AgendaItem = {
  data: string;
  colaborador_id: string;
  colaborador_nome: string;
  tarefa_id: string;
  situacao: string;
  detalhe_visivel: boolean;
  numero_os: string | null;
  cliente_nome: string | null;
  descricao: string | null;
  categoria: Categoria;
  // false so na ausencia medida em HORAS: a pessoa tem parte do dia fora, mas o
  // dia continua livre para trabalho. Folga de 4h nao reserva nada, e por isso
  // ela nao vinha nesta grade — ficava invisivel na tela onde se planeja.
  reserva_dia: boolean;
  horas: number | string | null;
};

type Conflito = {
  tarefa_id: string;
  categoria: Categoria;
  numero_os: string | null;
  cliente_nome: string | null;
  descricao: string;
  situacao: string;
};

type RetornoAcao = {
  sucesso: boolean;
  repetido?: boolean;
  tarefa?: Tarefa;
  erros?: ErroRpc[];
  conflito?: Conflito | null;
};

type Reserva = {
  id: string;
  data: string;
  colaborador_id: string;
  colaborador_nome: string;
  criado_em: string;
  criado_por_nome: string | null;
  ativa: boolean;
  liberada_em: string | null;
  liberada_por_nome: string | null;
  liberacao_motivo: string | null;
};

type Detalhe = {
  sucesso: boolean;
  tarefa?: Tarefa;
  participantes?: Participante[];
  reservas?: Reserva[];
  erros?: ErroRpc[];
};

type Aba = "agendadas" | "sem_data" | "ausencias" | "historico" | "agenda";

type Modal =
  | { tipo: "nova" }
  | { tipo: "reagendar"; tarefa: Tarefa }
  | { tipo: "trocar"; tarefa: Tarefa }
  | { tipo: "participantes"; tarefa: Tarefa }
  | { tipo: "editar"; tarefa: Tarefa }
  | { tipo: "cancelar"; tarefa: Tarefa }
  | { tipo: "liberar"; tarefa: Tarefa }
  // comAtestado = true e o atestado que chegou depois; false e o desfazer de quem
  // marcou na falta errada. O banco aceita os dois sentidos (p_com_atestado).
  | { tipo: "atestado"; tarefa: Tarefa; comAtestado: boolean }
  | { tipo: "detalhe"; tarefa: Tarefa };

// Motivos gravados pelo banco na reserva liberada; a tela so traduz.
const MOTIVOS_LIBERACAO: Record<string, string> = {
  passou_para_sem_data: "passou para sem data",
  reagendada: "reagendada",
  troca_de_colaborador: "troca de colaborador",
  saiu_da_tarefa: "saiu da tarefa",
  cancelada: "tarefa cancelada",
  liberada_pela_gestao: "liberada pela gestão",
};

// O que a tarefa e. 'os' e trabalho; o resto e ausencia, nao tem OS e so a
// gestao cria.
const CATEGORIAS: { valor: Categoria; rotulo: string }[] = [
  { valor: "os", rotulo: "Trabalho em OS" },
  { valor: "folga", rotulo: "Folga" },
  { valor: "ferias", rotulo: "Férias" },
  { valor: "falta_justificada", rotulo: "Falta com atestado" },
  { valor: "falta", rotulo: "Falta sem atestado" },
  { valor: "outro", rotulo: "Outro" },
];

// Confirmacao de ausencia criada. O rotulo cru dava "Férias registrada." e
// "Outro registrada." (achado em 12/09/2026 navegando pela tela): cada categoria
// tem a frase escrita por extenso.
const CONFIRMACAO_AUSENCIA: Record<Exclude<Categoria, "os">, string> = {
  folga: "Folga registrada.",
  ferias: "Férias registradas.",
  falta_justificada: "Falta com atestado registrada.",
  falta: "Falta sem atestado registrada.",
  outro: "Ausência registrada.",
};

const ROTULO_CATEGORIA: Record<Categoria, string> = {
  os: "Trabalho",
  folga: "Folga",
  ferias: "Férias",
  // Escrito por extenso em toda parte (lista, agenda, detalhe, conflito): "Falta"
  // sozinho nao diz o que importa, que e ter ou nao o atestado.
  falta_justificada: "Falta com atestado",
  falta: "Falta sem atestado",
  outro: "Outro",
};

function mensagemErro(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim()) return msg;
  }
  return fallback;
}

// Datas 'AAAA-MM-DD' viram Date local: new Date('2026-09-12') seria UTC e
// mostraria o dia anterior no Brasil.
function dataLocal(iso: string) {
  const [ano, mes, dia] = iso.split("-").map(Number);
  return new Date(ano, (mes || 1) - 1, dia || 1);
}

function isoLocal(d: Date) {
  const mes = String(d.getMonth() + 1).padStart(2, "0");
  const dia = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${mes}-${dia}`;
}

function hojeLocal() {
  return isoLocal(new Date());
}

function somarDias(iso: string, dias: number) {
  const d = dataLocal(iso);
  d.setDate(d.getDate() + dias);
  return isoLocal(d);
}

function dataBr(iso: string | null | undefined) {
  if (!iso) return "—";
  const d = dataLocal(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" }).format(d);
}

function diaSemana(iso: string) {
  const d = dataLocal(iso);
  if (Number.isNaN(d.getTime())) return "";
  return new Intl.DateTimeFormat("pt-BR", { weekday: "short" }).format(d).replace(".", "");
}

function fimDeSemana(iso: string) {
  const dia = dataLocal(iso).getDay();
  return dia === 0 || dia === 6;
}

function dataHoraBr(iso: string | null | undefined) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(d);
}

function textoCurto(texto: string | null | undefined, max: number) {
  const limpo = (texto ?? "").replace(/\s+/g, " ").trim();
  if (limpo.length <= max) return limpo;
  return `${limpo.slice(0, max - 1).trimEnd()}…`;
}

function motivoLegivel(motivo: string | null | undefined) {
  if (!motivo) return "";
  return MOTIVOS_LIBERACAO[motivo] ?? motivo;
}

function rotuloCategoria(categoria: Categoria | null | undefined) {
  return ROTULO_CATEGORIA[(categoria ?? "os") as Categoria] ?? "Trabalho";
}

// Horas com virgula, como a pessoa escreve: 2,5h e nao 2.5h.
function textoHoras(horas: number | null | undefined) {
  if (horas === null || horas === undefined) return "—";
  return `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(horas)}h`;
}

function ehAusencia(t: Tarefa) {
  return t.categoria !== "os";
}

function ehFalta(categoria: Categoria | null | undefined) {
  return categoria === "falta" || categoria === "falta_justificada";
}

// O que a falta faz com a meta da semana, dito na tela onde a coordenacao marca:
// com atestado desconta, como folga e ferias; sem atestado nao desconta.
function textoMetaDaFalta(categoria: Categoria) {
  if (categoria === "falta_justificada") return "Falta com atestado: desconta da meta da semana, como folga e férias.";
  if (categoria === "falta") return "Falta sem atestado: não desconta da meta da semana.";
  return "";
}

// A duracao em texto: um dia, um intervalo ou um punhado de horas num dia.
function textoDuracao(t: Tarefa) {
  if (!t.data) return "Sem data";
  if (t.medida === "horas") return `${dataBr(t.data)} · ${textoHoras(t.horas)}`;
  const dias = t.dias ?? 1;
  if (dias > 1 && t.data_fim) return `${dataBr(t.data)} a ${dataBr(t.data_fim)} · ${dias} dias`;
  return dataBr(t.data);
}

// Referencia da tarefa nas confirmacoes e nos resumos: a OS quando e trabalho,
// o que a ausencia e quando nao tem OS.
function referenciaTarefa(t: Tarefa) {
  if (ehAusencia(t)) return rotuloCategoria(t.categoria);
  return `OS ${t.numero_os ?? "—"}`;
}

// Chave de idempotencia de criar/concluir. Navegador sem randomUUID (http sem
// TLS, por exemplo) monta o uuid v4 com getRandomValues.
function novaChave() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// Mensagem de falha vinda do servidor; em conflito de reserva junta o detalhe
// quando o banco deixou ver a tarefa que ocupa o dia.
function descreverFalha(retorno: RetornoAcao | null | undefined, fallback: string) {
  const erro = retorno?.erros?.[0];
  let msg = erro?.mensagem?.trim() || fallback;
  if (erro?.tipo === "colaborador_reservado" && retorno?.conflito) {
    const c = retorno.conflito;
    // O dia pode estar ocupado por trabalho (tem OS) ou por ausencia (nao tem).
    const quem = c.categoria === "os" ? `OS ${c.numero_os ?? "—"} · ${c.cliente_nome ?? "—"}` : rotuloCategoria(c.categoria);
    msg += ` Ocupado por ${quem}: ${c.descricao}`;
  }
  return msg;
}

function textoReserva(t: Tarefa) {
  if (t.reserva_ativa) return "Ativa";
  if (t.reserva_liberada_em) {
    const por = t.reserva_liberada_por_nome ? ` por ${t.reserva_liberada_por_nome}` : "";
    const motivo = t.reserva_liberacao_motivo ? ` (${motivoLegivel(t.reserva_liberacao_motivo)})` : "";
    return `Liberada em ${dataHoraBr(t.reserva_liberada_em)}${por}${motivo}`;
  }
  return "—";
}

// Encerramento da linha: concluida_por_nome e cancelada_* falam da PESSOA da
// linha, porque a linha e de um participante.
function textoEncerramento(t: Tarefa) {
  if (t.situacao === "concluida") {
    const nome = t.concluida_por_nome ?? "—";
    const tablet = t.concluida_pelo_tablet && !/tablet/i.test(nome) ? " (pelo tablet)" : "";
    return `Concluída por ${nome}${tablet} em ${dataHoraBr(t.concluida_em)}`;
  }
  if (t.situacao === "cancelada") {
    return `Cancelada por ${t.cancelada_por_nome ?? "—"} em ${dataHoraBr(t.cancelada_em)}`;
  }
  return "";
}

const BASE_BADGE = "px-2 py-0.5 rounded-full text-xs border whitespace-nowrap";

const CLASSE_BADGE_CATEGORIA: Record<Categoria, string> = {
  os: "bg-zinc-800 text-zinc-300 border-zinc-700",
  folga: "bg-violet-900/40 text-violet-300 border-violet-800",
  ferias: "bg-teal-900/40 text-teal-300 border-teal-800",
  // A falta sem atestado fica em rosa, e nao no vermelho da situacao "Atrasada":
  // as duas tarjas aparecem lado a lado na mesma linha e nao podem se confundir.
  // A com atestado fica em amarelo, perto mas separada dela.
  falta_justificada: "bg-yellow-900/40 text-yellow-300 border-yellow-800",
  falta: "bg-rose-900/40 text-rose-300 border-rose-800",
  outro: "bg-orange-900/40 text-orange-300 border-orange-800",
};

// Mesma celula da agenda quando a ausencia e medida em HORAS: borda tracejada e
// sem fundo, porque o dia nao esta tomado, mas com a cor da categoria — um atraso
// de 2h e falta e tem de parecer falta, nao trabalho pendente.
const CLASSE_CELULA_HORAS: Record<Categoria, string> = {
  os: "bg-transparent text-sky-300 border-sky-800 border-dashed",
  folga: "bg-transparent text-violet-300 border-violet-800 border-dashed",
  ferias: "bg-transparent text-teal-300 border-teal-800 border-dashed",
  falta_justificada: "bg-transparent text-yellow-300 border-yellow-800 border-dashed",
  falta: "bg-transparent text-rose-300 border-rose-800 border-dashed",
  outro: "bg-transparent text-orange-300 border-orange-800 border-dashed",
};

function BadgeCategoria({ categoria }: { categoria: Categoria }) {
  return <span className={`${BASE_BADGE} ${CLASSE_BADGE_CATEGORIA[categoria] ?? CLASSE_BADGE_CATEGORIA.os}`}>{rotuloCategoria(categoria)}</span>;
}

function BadgeSituacao({ tarefa }: { tarefa: Tarefa }) {
  const base = BASE_BADGE;
  if (tarefa.situacao === "concluida") {
    return <span className={`${base} bg-green-900/40 text-green-400 border-green-800`}>Concluída</span>;
  }
  if (tarefa.situacao === "cancelada") {
    return <span className={`${base} bg-zinc-800 text-zinc-400 border-zinc-700`}>Cancelada</span>;
  }
  // A tarefa segue pendente, mas a parte desta pessoa ja fechou: falta outro
  // participante. So a ultima conclusao fecha a tarefa.
  if (tarefa.participante_concluida_em) {
    return <span className={`${base} bg-emerald-900/30 text-emerald-300 border-emerald-800`}>Parte concluída</span>;
  }
  if (tarefa.atrasada) {
    return <span className={`${base} bg-red-900/40 text-red-300 border-red-800`}>Atrasada</span>;
  }
  if (tarefa.hoje) {
    return <span className={`${base} bg-amber-900/40 text-amber-300 border-amber-800`}>Hoje</span>;
  }
  return <span className={`${base} bg-sky-900/40 text-sky-300 border-sky-800`}>Pendente</span>;
}

function BotaoAcao({
  children,
  onClick,
  disabled,
  title,
}: {
  children: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
  title?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={title}
      className="px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs disabled:opacity-50 whitespace-nowrap"
    >
      {children}
    </button>
  );
}

const CLASSE_INPUT = "w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100 disabled:opacity-60";
const CLASSE_INPUT_FILTRO = "px-2 py-1.5 bg-zinc-900 border border-zinc-700 rounded text-zinc-100 text-sm";

export default function TarefasPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId } = usePermissions();
  const { empresaId } = useTenantEmpresa();

  const [contexto, setContexto] = useState<Contexto | null>(null);
  const [contadores, setContadores] = useState<Contadores | null>(null);
  const [erroContexto, setErroContexto] = useState<string | null>(null);
  const [carregandoBase, setCarregandoBase] = useState(false);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);

  const [aba, setAba] = useState<Aba>("agendadas");
  const [de, setDe] = useState("");
  const [ate, setAte] = useState("");
  const [colaboradorFiltro, setColaboradorFiltro] = useState("");
  const [busca, setBusca] = useState("");
  const [buscaAplicada, setBuscaAplicada] = useState("");
  const [tarefas, setTarefas] = useState<Tarefa[]>([]);
  const [carregandoLista, setCarregandoLista] = useState(false);

  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  const [agendaInicio, setAgendaInicio] = useState("");
  const [agendaDias, setAgendaDias] = useState<7 | 14>(7);
  const [agendaItens, setAgendaItens] = useState<AgendaItem[]>([]);
  const [carregandoAgenda, setCarregandoAgenda] = useState(false);

  const [modal, setModal] = useState<Modal | null>(null);
  const [modalErro, setModalErro] = useState<string | null>(null);
  // O modal de participantes continua aberto depois de cada acao; o aviso de
  // sucesso precisa aparecer dentro dele, nao atras.
  const [modalOk, setModalOk] = useState<string | null>(null);
  const [campoData, setCampoData] = useState("");
  const [campoDias, setCampoDias] = useState("1");
  const [campoColaborador, setCampoColaborador] = useState("");
  const [campoTexto, setCampoTexto] = useState("");
  const [modalColaboradores, setModalColaboradores] = useState<Colaborador[]>([]);
  const [carregandoColabs, setCarregandoColabs] = useState(false);
  const [detalhe, setDetalhe] = useState<Detalhe | null>(null);

  const [novoTipo, setNovoTipo] = useState<"agendada" | "sem_data">("agendada");
  const [novaCategoria, setNovaCategoria] = useState<Categoria>("os");
  const [novaMedida, setNovaMedida] = useState<Medida>("dias");
  const [novasHoras, setNovasHoras] = useState("8");
  const [novosColaboradores, setNovosColaboradores] = useState<string[]>([]);
  const [novaOsId, setNovaOsId] = useState("");
  const [buscaOs, setBuscaOs] = useState("");
  const [osElegiveis, setOsElegiveis] = useState<OsElegivel[]>([]);
  const [carregandoOs, setCarregandoOs] = useState(false);

  // Chave da tarefa nova: vale ate o servidor confirmar, inclusive se o modal
  // for fechado e reaberto no meio. Gerar uma chave nova a cada abertura faria a
  // tentativa que o servidor ja gravou, e cuja resposta se perdeu, virar uma
  // segunda tarefa. Concluir tem uma chave por tarefa.
  const chaveNovaRef = useRef("");
  const chavesConcluirRef = useRef<Map<string, string>>(new Map());
  // Criar falhou e o modal ainda esta aberto: ao fechar, recarrega a lista para
  // a pessoa ver se a tarefa entrou mesmo assim.
  const criarFalhouRef = useRef(false);
  // Espelho de quem esta escolhido na tarefa nova. O efeito que recarrega os
  // colaboradores precisa saber quem sai quando a data muda, e depender do
  // estado faria uma consulta nova a cada pessoa acrescentada.
  const novosColabsRef = useRef<string[]>([]);
  const pedidoColabsRef = useRef(0);
  const pedidoOsRef = useRef(0);
  // Sequencia de cada consulta: filtro e aba disparam uma chamada por mudanca e
  // a resposta antiga pode chegar por ultimo; fora de sequencia ela e descartada
  // em vez de sobrescrever a lista da secao/filtro atual.
  const pedidoListaRef = useRef(0);
  const pedidoAgendaRef = useRef(0);

  const hoje = contexto?.hoje ?? hojeLocal();
  const podeCriar = contexto?.pode_criar ?? false;

  const carregarBase = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) return;
    setCarregandoBase(true);
    setErroContexto(null);
    setContexto(null);
    try {
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;
      const { error: empresaErr } = await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
      if (empresaErr) throw empresaErr;

      const ctxRes = await supabase.rpc("app_tarefas_contexto");
      if (ctxRes.error) throw ctxRes.error;
      const ctx = ctxRes.data as Contexto;

      const [contRes, colabRes] = await Promise.all([
        supabase.rpc("app_tarefas_contar"),
        ctx.pode_criar ? supabase.rpc("app_tarefas_colaboradores", { p_data: null }) : Promise.resolve(null),
      ]);
      if (contRes.error) throw contRes.error;
      if (colabRes?.error) throw colabRes.error;

      setContadores(contRes.data as Contadores);
      setColaboradores((colabRes?.data ?? []) as Colaborador[]);
      setAgendaInicio((atual) => atual || ctx.hoje);
      setContexto(ctx);
    } catch (e: unknown) {
      setErroContexto(mensagemErro(e, "Falha ao carregar as tarefas."));
    } finally {
      setCarregandoBase(false);
    }
  }, [empresaId, supabase, tenantId]);

  useEffect(() => {
    const timer = window.setTimeout(() => void carregarBase(), 0);
    return () => window.clearTimeout(timer);
  }, [carregarBase]);

  const recarregarContadores = useCallback(async () => {
    if (!supabase || !contexto) return;
    const { data, error } = await supabase.rpc("app_tarefas_contar");
    if (!error && data) setContadores(data as Contadores);
  }, [contexto, supabase]);

  const carregarLista = useCallback(async () => {
    // Conta tambem a chamada que nao consulta nada (ida para a agenda, por
    // exemplo): o que estava em voo deixa de valer do mesmo jeito.
    const pedido = ++pedidoListaRef.current;
    if (!supabase || !contexto || aba === "agenda") {
      // Sem consulta nova, quem estava em voo deixou de valer e o finally dele
      // nao vai rodar: e aqui que o "Carregando..." se apaga.
      setCarregandoLista(false);
      return;
    }
    setCarregandoLista(true);
    setErro(null);
    try {
      const { data, error } = await supabase.rpc("app_tarefas_listar", {
        p_secao: aba,
        p_de: de || null,
        p_ate: ate || null,
        p_colaborador_id: colaboradorFiltro || null,
        p_os_id: null,
        p_busca: buscaAplicada || null,
      });
      if (pedido !== pedidoListaRef.current) return;
      if (error) throw error;
      setTarefas((data ?? []) as Tarefa[]);
    } catch (e: unknown) {
      if (pedido !== pedidoListaRef.current) return;
      setErro(mensagemErro(e, "Falha ao listar as tarefas."));
    } finally {
      if (pedido === pedidoListaRef.current) setCarregandoLista(false);
    }
  }, [aba, ate, buscaAplicada, colaboradorFiltro, contexto, de, supabase]);

  useEffect(() => {
    const timer = window.setTimeout(() => void carregarLista(), 0);
    return () => window.clearTimeout(timer);
  }, [carregarLista]);

  // A busca so vai ao servidor depois de a pessoa parar de digitar.
  useEffect(() => {
    const timer = window.setTimeout(() => setBuscaAplicada(busca.trim()), 400);
    return () => window.clearTimeout(timer);
  }, [busca]);

  const carregarAgenda = useCallback(async () => {
    const pedido = ++pedidoAgendaRef.current;
    if (!supabase || !contexto || aba !== "agenda" || !agendaInicio) {
      setCarregandoAgenda(false);
      return;
    }
    setCarregandoAgenda(true);
    setErro(null);
    try {
      const { data, error } = await supabase.rpc("app_tarefas_agenda", {
        p_de: agendaInicio,
        p_ate: somarDias(agendaInicio, agendaDias - 1),
      });
      if (pedido !== pedidoAgendaRef.current) return;
      if (error) throw error;
      setAgendaItens((data ?? []) as AgendaItem[]);
    } catch (e: unknown) {
      if (pedido !== pedidoAgendaRef.current) return;
      setErro(mensagemErro(e, "Falha ao carregar a agenda."));
    } finally {
      if (pedido === pedidoAgendaRef.current) setCarregandoAgenda(false);
    }
  }, [aba, agendaDias, agendaInicio, contexto, supabase]);

  useEffect(() => {
    const timer = window.setTimeout(() => void carregarAgenda(), 0);
    return () => window.clearTimeout(timer);
  }, [carregarAgenda]);

  // Aba e carregadores de agora num ref: recarregarTudo roda depois de uma acao,
  // quando a pessoa ja pode ter trocado de aba, e recarregar a secao capturada
  // no clique deixaria a tela com as linhas da aba antiga.
  const abaRef = useRef<Aba>(aba);
  const carregarListaRef = useRef(carregarLista);
  const carregarAgendaRef = useRef(carregarAgenda);
  useEffect(() => {
    abaRef.current = aba;
    carregarListaRef.current = carregarLista;
    carregarAgendaRef.current = carregarAgenda;
  }, [aba, carregarAgenda, carregarLista]);

  // Colaboradores do modal (nova tarefa, trocar colaborador e participantes),
  // com o dia ocupado ou nao conforme a data escolhida. Refaz a consulta quando
  // a data muda. Em horas o dia nao e reservado, entao ninguem fica ocupado por
  // isso e a consulta vai sem data.
  const dataParaColabs: string | null | undefined =
    modal?.tipo === "nova"
      ? novoTipo === "agendada" && novaMedida === "dias"
        ? campoData || null
        : null
      : modal?.tipo === "trocar" || modal?.tipo === "participantes"
        ? modal.tarefa.medida === "horas"
          ? null
          : modal.tarefa.data
        : undefined;

  // Na troca e ao mexer nos participantes, quem ja esta na tarefa aparece
  // "ocupado" por ela mesma; qualquer outro ocupado sai da selecao quando a
  // lista muda.
  const tarefaIdModal = modal?.tipo === "trocar" || modal?.tipo === "participantes" ? modal.tarefa.id : null;
  const ehModalNova = modal?.tipo === "nova";

  useEffect(() => {
    novosColabsRef.current = novosColaboradores;
  }, [novosColaboradores]);

  useEffect(() => {
    if (dataParaColabs === undefined || !supabase) return;
    const pedido = ++pedidoColabsRef.current;
    const timer = window.setTimeout(async () => {
      setCarregandoColabs(true);
      try {
        const { data, error } = await supabase.rpc("app_tarefas_colaboradores", { p_data: dataParaColabs });
        if (pedido !== pedidoColabsRef.current) return;
        if (error) throw error;
        const lista = (data ?? []) as Colaborador[];
        setModalColaboradores(lista);
        // Quem ficou ocupado depois de a data mudar sai da lista de escolhidos da
        // tarefa nova: mandar um ocupado derrubaria a criacao inteira. Sair em
        // silencio deixava a pessoa diante de "Escolha pelo menos um colaborador"
        // sem saber quem tinha sumido (achado em 12/09/2026 navegando pela tela):
        // agora a tela diz o nome de quem saiu, o dia e o que ocupa o dia.
        const sairam = novosColabsRef.current
          .map((id) => lista.find((c) => c.id === id))
          .filter((c): c is Colaborador => Boolean(c?.ocupado));
        setNovosColaboradores((atual) =>
          atual.filter((id) => {
            const escolhido = lista.find((c) => c.id === id);
            return !escolhido || !escolhido.ocupado;
          })
        );
        if (ehModalNova && dataParaColabs && sairam.length > 0) {
          setModalErro(
            sairam
              .map(
                (c) =>
                  `${c.nome} saiu da escolha: ${dataBr(dataParaColabs)} já está ocupado${c.ocupado_resumo ? ` por ${c.ocupado_resumo}` : ""}.`
              )
              .join(" ")
          );
        }
        setCampoColaborador((atual) => {
          const escolhido = lista.find((c) => c.id === atual);
          if (!escolhido || !escolhido.ocupado) return atual;
          // Na troca e nos participantes (tarefaIdModal preenchido) quem esta
          // ocupado pela propria tarefa continua escolhivel. Na nova tarefa
          // qualquer ocupado sai da selecao, inclusive quem esta ocupado por uma
          // tarefa que a pessoa nao pode ver: nesse caso o servidor manda
          // ocupado_tarefa_id nulo, que um "!== tarefaIdModal" nulo deixaria passar.
          if (tarefaIdModal !== null && escolhido.ocupado_tarefa_id === tarefaIdModal) return atual;
          return "";
        });
      } catch (e: unknown) {
        if (pedido !== pedidoColabsRef.current) return;
        setModalErro(mensagemErro(e, "Falha ao carregar os colaboradores."));
      } finally {
        if (pedido === pedidoColabsRef.current) setCarregandoColabs(false);
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [dataParaColabs, supabase, tarefaIdModal, ehModalNova]);

  // OS elegiveis do modal de nova tarefa; a busca refaz a consulta no servidor.
  // Ausencia nao tem OS, entao nem consulta.
  const precisaOs = modal?.tipo === "nova" && novaCategoria === "os";
  useEffect(() => {
    if (!precisaOs || !supabase) return;
    const pedido = ++pedidoOsRef.current;
    const timer = window.setTimeout(async () => {
      setCarregandoOs(true);
      try {
        const { data, error } = await supabase.rpc("app_tarefas_os_elegiveis", { p_busca: buscaOs.trim() || null });
        if (pedido !== pedidoOsRef.current) return;
        if (error) throw error;
        setOsElegiveis((data ?? []) as OsElegivel[]);
      } catch (e: unknown) {
        if (pedido !== pedidoOsRef.current) return;
        setModalErro(mensagemErro(e, "Falha ao carregar as OS."));
      } finally {
        if (pedido === pedidoOsRef.current) setCarregandoOs(false);
      }
    }, 350);
    return () => window.clearTimeout(timer);
  }, [buscaOs, precisaOs, supabase]);

  const osPorCliente = useMemo(() => {
    const grupos = new Map<string, OsElegivel[]>();
    for (const os of osElegiveis) {
      const lista = grupos.get(os.cliente_nome) ?? [];
      lista.push(os);
      grupos.set(os.cliente_nome, lista);
    }
    return Array.from(grupos, ([cliente, lista]) => ({ cliente, lista }));
  }, [osElegiveis]);

  const diasAgenda = useMemo(
    () => (agendaInicio ? Array.from({ length: agendaDias }, (_, i) => somarDias(agendaInicio, i)) : []),
    [agendaDias, agendaInicio]
  );

  // Linhas da agenda: quem cria tarefas ve todos os colaboradores ativos; o
  // colaborador comum ve so quem aparece nas proprias reservas.
  const linhasAgenda = useMemo(() => {
    const mapa = new Map<string, string>();
    if (podeCriar) colaboradores.forEach((c) => mapa.set(c.id, c.nome));
    agendaItens.forEach((item) => {
      if (!mapa.has(item.colaborador_id)) mapa.set(item.colaborador_id, item.colaborador_nome);
    });
    return Array.from(mapa, ([id, nome]) => ({ id, nome })).sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
  }, [agendaItens, colaboradores, podeCriar]);

  const celulasAgenda = useMemo(() => {
    const mapa = new Map<string, AgendaItem[]>();
    for (const item of agendaItens) {
      const chave = `${item.colaborador_id}|${item.data}`;
      const lista = mapa.get(chave) ?? [];
      lista.push(item);
      mapa.set(chave, lista);
    }
    return mapa;
  }, [agendaItens]);

  function mudarAba(nova: Aba) {
    setAba(nova);
    setErro(null);
    setOk(null);
    if (nova === "historico") {
      setDe(somarDias(hoje, -30));
      setAte(hoje);
    } else {
      setDe("");
      setAte("");
    }
  }

  async function recarregarTudo() {
    await Promise.all([
      recarregarContadores(),
      abaRef.current === "agenda" ? carregarAgendaRef.current() : carregarListaRef.current(),
    ]);
  }

  // Chama uma RPC de acao e so devolve o retorno quando sucesso = true. Em
  // qualquer falha (rede, exception ou sucesso = false) grava a mensagem do
  // servidor no lugar certo e devolve null: quem chamou nunca mostra sucesso.
  async function chamarAcao(
    rpc: string,
    params: Record<string, unknown>,
    fallback: string,
    onde: "modal" | "pagina"
  ): Promise<RetornoAcao | null> {
    if (!supabase) return null;
    try {
      const { data, error } = await supabase.rpc(rpc, params);
      if (error) throw error;
      const retorno = (data ?? {}) as RetornoAcao;
      if (!retorno.sucesso) throw new Error(descreverFalha(retorno, fallback));
      return retorno;
    } catch (e: unknown) {
      const msg = mensagemErro(e, fallback);
      if (onde === "modal") setModalErro(msg);
      else setErro(msg);
      return null;
    }
  }

  async function carregarDetalhe(tarefaId: string) {
    if (!supabase) return;
    setDetalhe(null);
    try {
      const { data, error } = await supabase.rpc("app_tarefas_detalhe", { p_tarefa_id: tarefaId });
      if (error) throw error;
      const retorno = (data ?? {}) as Detalhe;
      if (!retorno.sucesso) throw new Error(retorno.erros?.[0]?.mensagem ?? "Tarefa não encontrada.");
      setDetalhe(retorno);
    } catch (e: unknown) {
      setModalErro(mensagemErro(e, "Falha ao carregar o detalhe da tarefa."));
    }
  }

  function abrirModal(novo: Modal) {
    setModal(novo);
    setModalErro(null);
    setModalOk(null);
    setErro(null);
    setOk(null);
    setDetalhe(null);
    setModalColaboradores([]);
    switch (novo.tipo) {
      case "nova":
        // So gera chave nova quando a anterior ja foi consumida por um sucesso.
        if (!chaveNovaRef.current) chaveNovaRef.current = novaChave();
        criarFalhouRef.current = false;
        setNovoTipo("agendada");
        setNovaCategoria("os");
        setNovaMedida("dias");
        setNovasHoras("8");
        setCampoData(hoje);
        setCampoDias("1");
        setCampoColaborador("");
        setNovosColaboradores([]);
        setNovaOsId("");
        setBuscaOs("");
        setOsElegiveis([]);
        setCampoTexto("");
        break;
      case "reagendar":
        setCampoData(novo.tarefa.data ?? hoje);
        setCampoDias(String(novo.tarefa.dias ?? 1));
        break;
      case "trocar":
        setCampoColaborador(novo.tarefa.colaborador_id);
        break;
      case "participantes":
        setCampoColaborador("");
        void carregarDetalhe(novo.tarefa.id);
        break;
      case "editar":
        setCampoTexto(novo.tarefa.descricao);
        break;
      case "cancelar":
      case "liberar":
      case "atestado":
        setCampoTexto("");
        break;
      case "detalhe":
        void carregarDetalhe(novo.tarefa.id);
        break;
    }
  }

  function fecharModal() {
    if (salvando) return;
    // Criar falhou sem o servidor confirmar: a tarefa pode ter sido gravada e so
    // a resposta se perdeu. Recarrega a lista para a pessoa ver se ela entrou em
    // vez de fechar o modal achando que nada aconteceu.
    const recarregar = modal?.tipo === "nova" && criarFalhouRef.current;
    criarFalhouRef.current = false;
    setModal(null);
    setModalErro(null);
    setModalOk(null);
    if (recarregar) void recarregarTudo();
  }

  // Concluir e SEMPRE por pessoa: cada linha da lista e a parte de um
  // participante e a tarefa fecha quando o ultimo fecha a parte dele. A chave de
  // idempotencia e por tarefa + pessoa, senao a segunda pessoa receberia o
  // resultado guardado da primeira e nao concluiria nada.
  async function concluirParte(tarefa: Tarefa, colaboradorId: string, nome: string, onde: "pagina" | "modal") {
    const alvo = tarefa.participantes > 1 ? `a parte de ${nome}` : `a tarefa de ${nome}`;
    const quando = tarefa.data ? ` (${textoDuracao(tarefa)})` : "";
    if (
      !confirm(`Concluir ${alvo} em ${referenciaTarefa(tarefa)}${quando}?\n\nIsso registra a execução. A reserva do dia continua.`)
    ) {
      return;
    }
    const chaves = chavesConcluirRef.current;
    const chaveId = `${tarefa.id}|${colaboradorId}`;
    const chave = chaves.get(chaveId) ?? novaChave();
    chaves.set(chaveId, chave);
    setSalvando(true);
    if (onde === "modal") {
      setModalErro(null);
      setModalOk(null);
    } else {
      setErro(null);
      setOk(null);
    }
    const retorno = await chamarAcao(
      "app_tarefas_concluir",
      { p_tarefa_id: tarefa.id, p_chave: chave, p_colaborador_id: colaboradorId },
      "Não foi possível concluir a tarefa.",
      onde
    );
    setSalvando(false);
    if (!retorno) return;
    chaves.delete(chaveId);
    // O servidor devolve a tarefa como ficou: quando esta era a ultima parte a
    // tarefa fechou e a linha sai das agendadas. Repetir "a tarefa fecha quando o
    // ultimo concluir" bem na hora em que ela fechou fazia a linha sumir sem
    // explicacao (achado em 12/09/2026 navegando pela tela).
    const fechou = retorno.tarefa?.situacao === "concluida";
    const msg = retorno.repetido
      ? `A parte de ${nome} já estava concluída.`
      : tarefa.participantes > 1
        ? fechou
          ? `Parte de ${nome} concluída — era a última: a tarefa está concluída e saiu das agendadas. A reserva do dia continua.`
          : `Parte de ${nome} concluída. A tarefa fecha quando o último participante concluir; a reserva do dia continua.`
        : "Tarefa concluída. A reserva do dia continua.";
    if (onde === "modal") {
      setModalOk(msg);
      await carregarDetalhe(tarefa.id);
    } else {
      setOk(msg);
    }
    await recarregarTudo();
  }

  async function passarParaSemData(tarefa: Tarefa) {
    const pessoas = tarefa.participantes > 1 ? `${tarefa.participantes} pessoas` : tarefa.colaborador_nome;
    if (
      !confirm(
        `Passar a tarefa de ${pessoas} (${referenciaTarefa(tarefa)}) para sem data?\n\nOs dias reservados (${textoDuracao(tarefa)}) ficam livres para outra tarefa.`
      )
    ) {
      return;
    }
    setSalvando(true);
    setErro(null);
    setOk(null);
    const retorno = await chamarAcao(
      "app_tarefas_reagendar",
      { p_tarefa_id: tarefa.id, p_data: null },
      "Não foi possível passar a tarefa para sem data.",
      "pagina"
    );
    setSalvando(false);
    if (!retorno) return;
    setOk(retorno.repetido ? "A tarefa já estava sem data." : "Tarefa passou para sem data. Os dias reservados foram liberados.");
    await recarregarTudo();
  }

  async function criarTarefa() {
    // Ausencia sempre tem data; so trabalho em OS pode ficar sem data.
    const tipo = novaCategoria === "os" ? novoTipo : "agendada";
    const medida = novaCategoria !== "os" && tipo === "agendada" ? novaMedida : "dias";
    const dias = medida === "horas" || tipo === "sem_data" ? 1 : Number(campoDias);
    const horas = medida === "horas" ? Number(novasHoras.replace(",", ".")) : null;
    if (tipo === "agendada" && !campoData) {
      setModalErro(
        novaCategoria === "os" ? "Tarefa agendada precisa de uma data." : "Folga, férias, falta e outras ausências precisam de data."
      );
      return;
    }
    if (medida === "dias" && tipo === "agendada" && (!Number.isInteger(dias) || dias < 1 || dias > 60)) {
      setModalErro("A duração vai de 1 a 60 dias.");
      return;
    }
    if (medida === "horas" && (!Number.isFinite(horas) || (horas ?? 0) <= 0 || (horas ?? 0) > 24)) {
      setModalErro("Em horas, informe de 0,5 a 24 horas.");
      return;
    }
    if (novosColaboradores.length === 0) {
      setModalErro("Escolha pelo menos um colaborador.");
      return;
    }
    if (novaCategoria === "os" && !novaOsId) {
      setModalErro("Escolha a OS.");
      return;
    }
    // Na falta a observacao e opcional; nas outras categorias a descricao continua
    // obrigatoria (e o banco recusa vazio de qualquer jeito).
    const descricao = campoTexto.trim() || (ehFalta(novaCategoria) ? "Falta" : "");
    if (!descricao) {
      setModalErro(novaCategoria === "os" ? "Descreva a tarefa." : "Descreva a ausência.");
      return;
    }
    setSalvando(true);
    setModalErro(null);
    const retorno = await chamarAcao(
      "app_tarefas_criar",
      {
        // Manda todos os parametros da assinatura nova: o banco ainda tem o
        // atalho antigo de um colaborador so, e e o conjunto de nomes que diz
        // ao PostgREST qual das duas chamar.
        p_colaboradores: novosColaboradores,
        p_tipo: tipo,
        p_data: tipo === "agendada" ? campoData : null,
        p_dias: dias,
        p_descricao: descricao,
        p_categoria: novaCategoria,
        p_os_id: novaCategoria === "os" ? Number(novaOsId) : null,
        p_medida: medida,
        p_horas: horas,
        p_chave: chaveNovaRef.current,
      },
      "Não foi possível criar a tarefa.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) {
      criarFalhouRef.current = true;
      return;
    }
    // Servidor confirmou: a chave foi consumida e a proxima tarefa comeca outra.
    chaveNovaRef.current = "";
    criarFalhouRef.current = false;
    setModal(null);
    setOk(
      retorno.repetido
        ? "Essa tarefa já tinha sido criada."
        : novaCategoria === "os"
          ? novosColaboradores.length > 1
            ? `Tarefa criada para ${novosColaboradores.length} colaboradores.`
            : "Tarefa criada."
          : CONFIRMACAO_AUSENCIA[novaCategoria]
    );
    await recarregarTudo();
  }

  async function salvarReagendar(tarefa: Tarefa) {
    if (!campoData) {
      setModalErro("Informe a data.");
      return;
    }
    // Em horas a tarefa e sempre de um dia; nos outros casos a duracao pode ser
    // mudada junto com a data.
    const dias = tarefa.medida === "horas" ? 1 : Number(campoDias);
    if (tarefa.medida !== "horas" && (!Number.isInteger(dias) || dias < 1 || dias > 60)) {
      setModalErro("A duração vai de 1 a 60 dias.");
      return;
    }
    setSalvando(true);
    setModalErro(null);
    const retorno = await chamarAcao(
      "app_tarefas_reagendar",
      { p_tarefa_id: tarefa.id, p_data: campoData, p_dias: dias },
      "Não foi possível reagendar a tarefa.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setModal(null);
    const periodo = dias > 1 ? `${dataBr(campoData)} a ${dataBr(somarDias(campoData, dias - 1))}` : dataBr(campoData);
    setOk(
      retorno.repetido
        ? `A tarefa já estava em ${periodo}.`
        : tarefa.tipo === "sem_data"
          ? `Tarefa agendada para ${periodo}.`
          : `Tarefa reagendada para ${periodo}.`
    );
    await recarregarTudo();
  }

  // Entrar e sair da tarefa. O modal continua aberto para a pessoa mexer em
  // varios participantes de uma vez, e o detalhe e recarregado para a lista de
  // dentro do modal acompanhar.
  async function adicionarParticipante(tarefa: Tarefa) {
    if (!campoColaborador) {
      setModalErro("Escolha quem vai entrar na tarefa.");
      return;
    }
    const nome = modalColaboradores.find((c) => c.id === campoColaborador)?.nome ?? "a pessoa";
    setSalvando(true);
    setModalErro(null);
    setModalOk(null);
    const retorno = await chamarAcao(
      "app_tarefas_adicionar_participante",
      { p_tarefa_id: tarefa.id, p_colaborador_id: campoColaborador },
      "Não foi possível adicionar a pessoa à tarefa.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setCampoColaborador("");
    setModalOk(retorno.repetido ? `${nome} já participava desta tarefa.` : `${nome} entrou na tarefa.`);
    await carregarDetalhe(tarefa.id);
    await recarregarTudo();
  }

  async function removerParticipante(tarefa: Tarefa, participante: Participante) {
    if (
      !confirm(
        `Tirar ${participante.nome} desta tarefa (${referenciaTarefa(tarefa)})?\n\nOs dias reservados para ${participante.nome} ficam livres. A tarefa continua com os outros participantes.`
      )
    ) {
      return;
    }
    setSalvando(true);
    setModalErro(null);
    setModalOk(null);
    const retorno = await chamarAcao(
      "app_tarefas_remover_participante",
      { p_tarefa_id: tarefa.id, p_colaborador_id: participante.colaborador_id },
      "Não foi possível tirar a pessoa da tarefa.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setModalOk(`${participante.nome} saiu da tarefa e os dias dele(a) foram liberados.`);
    await carregarDetalhe(tarefa.id);
    await recarregarTudo();
  }

  async function salvarTrocaColaborador(tarefa: Tarefa) {
    if (!campoColaborador) {
      setModalErro("Escolha o colaborador.");
      return;
    }
    setSalvando(true);
    setModalErro(null);
    const retorno = await chamarAcao(
      "app_tarefas_trocar_colaborador",
      { p_tarefa_id: tarefa.id, p_colaborador_id: campoColaborador },
      "Não foi possível trocar o colaborador.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setModal(null);
    setOk(retorno.repetido ? "A tarefa já era desse colaborador." : "Colaborador da tarefa trocado.");
    await recarregarTudo();
  }

  async function salvarDescricao(tarefa: Tarefa) {
    if (!campoTexto.trim()) {
      setModalErro("Descreva a tarefa.");
      return;
    }
    setSalvando(true);
    setModalErro(null);
    const retorno = await chamarAcao(
      "app_tarefas_alterar",
      { p_tarefa_id: tarefa.id, p_descricao: campoTexto.trim() },
      "Não foi possível alterar a descrição.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setModal(null);
    setOk("Descrição alterada.");
    await recarregarTudo();
  }

  async function salvarCancelamento(tarefa: Tarefa) {
    setSalvando(true);
    setModalErro(null);
    const retorno = await chamarAcao(
      "app_tarefas_cancelar",
      { p_tarefa_id: tarefa.id, p_motivo: campoTexto.trim() || null },
      "Não foi possível cancelar a tarefa.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setModal(null);
    setOk(
      retorno.repetido
        ? "A tarefa já estava cancelada."
        : tarefa.tipo === "agendada"
          ? "Tarefa cancelada. Os dias reservados foram liberados."
          : "Tarefa cancelada."
    );
    await recarregarTudo();
  }

  async function salvarLiberacao(tarefa: Tarefa) {
    setSalvando(true);
    setModalErro(null);
    const retorno = await chamarAcao(
      "app_tarefas_liberar_reserva",
      { p_tarefa_id: tarefa.id, p_motivo: campoTexto.trim() || null },
      "Não foi possível liberar a reserva.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setModal(null);
    setOk(retorno.repetido ? "A reserva já estava liberada." : `Reserva de ${textoDuracao(tarefa)} liberada.`);
    await recarregarTudo();
  }

  // Atestado apresentado dias depois: a falta sem atestado vira falta com
  // atestado na MESMA linha — nada e cancelado nem recadastrado, a reserva do dia
  // continua e o historico da tarefa fica inteiro. O sentido contrario desfaz quem
  // marcou na falta errada. Quem decide e o banco; a tela so pede e repassa.
  async function marcarAtestado(tarefa: Tarefa, comAtestado: boolean) {
    setSalvando(true);
    setModalErro(null);
    const retorno = await chamarAcao(
      "app_tarefas_marcar_atestado",
      { p_tarefa_id: tarefa.id, p_com_atestado: comAtestado },
      comAtestado ? "Não foi possível marcar o atestado." : "Não foi possível tirar o atestado.",
      "modal"
    );
    setSalvando(false);
    if (!retorno) return;
    setModal(null);
    // O nome da pessoa entra no meio da frase e nao pode ser rebaixado: nada de
    // toLowerCase na frase inteira, que fazia "jonas montador" (achado em
    // 16/09/2026 navegando pela tela).
    const dequem = `a falta de ${tarefa.colaborador_nome} em ${textoDuracao(tarefa)}`;
    setOk(
      retorno.repetido
        ? `A falta de ${tarefa.colaborador_nome} em ${textoDuracao(tarefa)} já estava ${comAtestado ? "com" : "sem"} atestado.`
        : comAtestado
          ? `Atestado registrado: ${dequem} passou a ser falta com atestado e desconta da meta da semana. O registro é o mesmo e a reserva do dia continua.`
          : `Atestado retirado: ${dequem} voltou a ser falta sem atestado e não desconta da meta da semana.`
    );
    await recarregarTudo();
  }

  function confirmarModal() {
    if (!modal) return;
    switch (modal.tipo) {
      case "nova":
        void criarTarefa();
        break;
      case "reagendar":
        void salvarReagendar(modal.tarefa);
        break;
      case "trocar":
        void salvarTrocaColaborador(modal.tarefa);
        break;
      case "participantes":
        void adicionarParticipante(modal.tarefa);
        break;
      case "editar":
        void salvarDescricao(modal.tarefa);
        break;
      case "cancelar":
        void salvarCancelamento(modal.tarefa);
        break;
      case "liberar":
        void salvarLiberacao(modal.tarefa);
        break;
      case "atestado":
        void marcarAtestado(modal.tarefa, modal.comAtestado);
        break;
      case "detalhe":
        break;
    }
  }

  function tituloModal(m: Modal) {
    switch (m.tipo) {
      case "nova":
        return "Nova tarefa";
      case "reagendar":
        return m.tarefa.tipo === "sem_data" ? "Agendar tarefa" : "Reagendar tarefa";
      case "trocar":
        return "Trocar colaborador";
      case "participantes":
        return "Participantes da tarefa";
      case "editar":
        return "Editar descrição";
      case "cancelar":
        return "Cancelar tarefa";
      case "liberar":
        return "Liberar reserva do dia";
      case "atestado":
        return m.comAtestado ? "Marcar atestado da falta" : "Tirar o atestado da falta";
      case "detalhe":
        return "Detalhe da tarefa";
    }
  }

  function rotuloConfirmar(m: Modal) {
    switch (m.tipo) {
      case "nova":
        return "Criar tarefa";
      case "reagendar":
        return m.tarefa.tipo === "sem_data" ? "Agendar" : "Reagendar";
      case "trocar":
        return "Trocar";
      case "participantes":
        return "Adicionar";
      case "editar":
        return "Salvar";
      case "cancelar":
        return "Cancelar tarefa";
      case "liberar":
        return "Liberar reserva";
      case "atestado":
        return m.comAtestado ? "Marcar atestado" : "Tirar atestado";
      case "detalhe":
        return "";
    }
  }

  function classeAba(valor: Aba) {
    const ativa = aba === valor;
    return `px-3 py-2 rounded-md border text-sm flex items-center gap-2 disabled:opacity-50 ${
      ativa ? "border-zinc-500 bg-zinc-800 text-zinc-100" : "border-zinc-800 bg-zinc-950 text-zinc-400 hover:bg-zinc-900"
    }`;
  }

  function classeLinha(t: Tarefa) {
    if (t.situacao !== "pendente") return "hover:bg-zinc-900/40";
    // A parte desta pessoa ja fechou: a linha nao precisa mais chamar a atencao,
    // mesmo que a tarefa ainda espere outro participante.
    if (t.participante_concluida_em) return "hover:bg-zinc-900/40";
    if (t.atrasada) return "bg-red-950/30 hover:bg-red-950/40";
    if (t.hoje) return "bg-amber-950/20 hover:bg-amber-950/30";
    return "hover:bg-zinc-900/40";
  }

  function classeCelulaAgenda(item: AgendaItem) {
    // Ausencia em horas: borda tracejada, porque o dia NAO esta tomado. Sem o
    // detalhe a celula fica neutra, para nao contar pela cor o que o banco
    // escondeu.
    if (!item.reserva_dia) {
      if (!item.detalhe_visivel) return "bg-transparent text-zinc-400 border-zinc-600 border-dashed";
      return CLASSE_CELULA_HORAS[item.categoria] ?? CLASSE_CELULA_HORAS.outro;
    }
    if (!item.detalhe_visivel) return "bg-zinc-800 text-zinc-400 border-zinc-700";
    // Ausencia tem a cor da categoria: na grade, folga nao pode parecer trabalho.
    if (item.categoria !== "os") return CLASSE_BADGE_CATEGORIA[item.categoria] ?? CLASSE_BADGE_CATEGORIA.outro;
    if (item.situacao === "concluida") return "bg-green-900/40 text-green-300 border-green-800";
    if (item.situacao === "pendente") return "bg-sky-900/40 text-sky-200 border-sky-800";
    return "bg-zinc-800 text-zinc-300 border-zinc-700";
  }

  function resumoTarefa(t: Tarefa) {
    const quem = t.participantes > 1 ? `${t.colaborador_nome} e mais ${t.participantes - 1}` : t.colaborador_nome;
    // Em ausencia nao existe OS nem cliente: o resumo diz o que ela e.
    const cabeca = ehAusencia(t) ? rotuloCategoria(t.categoria) : `OS ${t.numero_os ?? "—"} · ${t.cliente_nome ?? "—"}`;
    return `${cabeca}${t.data ? ` · ${textoDuracao(t)}` : ""} · ${quem}`;
  }

  // Na agenda a celula so tem o resumo; o detalhe completo vem do servidor.
  // Monta uma linha minima para o cabecalho do modal e deixa app_tarefas_detalhe
  // preencher o resto.
  function abrirDetalheDaAgenda(item: AgendaItem) {
    const linha: Tarefa = {
      id: item.tarefa_id,
      tipo: "agendada",
      data: item.data,
      situacao: item.situacao as Tarefa["situacao"],
      colaborador_id: item.colaborador_id,
      colaborador_nome: item.colaborador_nome,
      minha: false,
      os_id: null,
      numero_os: item.numero_os,
      cliente_id: null,
      cliente_nome: item.cliente_nome,
      os_descricao: null,
      os_status_fluxo: null,
      descricao: item.descricao ?? "",
      criado_em: "",
      criado_por_nome: null,
      atualizado_em: "",
      concluida_em: null,
      concluida_por_nome: null,
      concluida_pelo_tablet: false,
      cancelada_em: null,
      cancelada_por_nome: null,
      cancelamento_motivo: null,
      reserva_ativa: true,
      reserva_liberada_em: null,
      reserva_liberada_por_nome: null,
      reserva_liberacao_motivo: null,
      atrasada: false,
      hoje: item.data === hoje,
      pode_gerir: false,
      pode_concluir: false,
      categoria: item.categoria,
      medida: "dias",
      dias: 1,
      horas: null,
      data_fim: item.data,
      participantes: 1,
      participante_concluida_em: null,
    };
    abrirModal({ tipo: "detalhe", tarefa: linha });
  }

  const ocupado = salvando || carregandoBase;
  const mostraPeriodo = aba === "agendadas" || aba === "historico" || aba === "ausencias";
  const historico = aba === "historico";
  const colunas = historico ? 10 : 9;
  const gestao = contexto?.gestao ?? false;

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center gap-3 flex-wrap">
        <h1 className="text-2xl font-bold">Tarefas</h1>
        {podeCriar && (
          <button
            type="button"
            onClick={() => abrirModal({ tipo: "nova" })}
            disabled={ocupado}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
          >
            + Nova tarefa
          </button>
        )}
        {(carregandoBase || carregandoLista || carregandoAgenda) && <span className="text-zinc-400">Carregando...</span>}
      </div>

      <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-300 space-y-1">
        <p>
          Uma tarefa amarra <strong>uma ou mais pessoas</strong> a uma OS, por <strong>um ou mais dias</strong>. <strong>Agendada</strong>{" "}
          reserva o <strong>dia inteiro</strong> de cada participante em todos os dias do intervalo: nesses dias ninguém consegue agendá-los
          em outra tarefa, em nenhuma OS. <strong>Sem data</strong> fica pendente sem reservar nada e convive com as agendadas.
        </p>
        <p className="text-zinc-400">
          Concluir é <strong>por pessoa</strong>: a tarefa fecha quando o último participante conclui a parte dele. Concluir{" "}
          <strong>não libera o dia</strong>: o dia foi usado. Para liberar o dia de uma tarefa concluída, a coordenação ou o responsável da
          OS usa &quot;Liberar reserva&quot;. Tarefa e apontamento de horas são independentes.
        </p>
        <p className="text-zinc-400">
          A coordenação também registra <strong>folga</strong>, <strong>férias</strong>, <strong>falta com atestado</strong>,{" "}
          <strong>falta sem atestado</strong> e <strong>outras ausências</strong>: não têm OS, sempre têm data e aparecem na aba Ausências.
          Ausência medida em <strong>horas</strong> não reserva o dia — a pessoa trabalha o resto dele, e é assim que entram o atraso e a
          saída antes do fim do expediente.
        </p>
        <p className="text-zinc-400">
          Falta <strong>com atestado</strong> desconta da meta da semana, como folga e férias; falta <strong>sem atestado</strong> não
          desconta. Quem apresenta o atestado dias depois não recadastra nada: a coordenação usa &quot;Marcar atestado&quot; na própria
          falta, na aba Ausências. O documento não é anexado no sistema.
        </p>
      </div>

      {erroContexto && (
        <div className="p-3 border border-red-700 rounded-lg bg-red-900/20 text-red-300 text-sm">{erroContexto}</div>
      )}

      {contexto && (
        <>
          {/* Trocar de aba enquanto uma acao salva deixaria o recarregar posterior
              chegando numa secao que a pessoa ja abandonou; durante o salvar as abas
              ficam travadas. */}
          <div className="flex items-center gap-2 flex-wrap">
            <button
              type="button"
              onClick={() => mudarAba("agendadas")}
              disabled={salvando}
              className={classeAba("agendadas")}
              title={
                contadores
                  ? `Hoje: ${contadores.hoje} · Atrasadas: ${contadores.atrasadas} · Próximas: ${contadores.futuras}`
                  : undefined
              }
            >
              Agendadas
              {contadores && <span className="text-xs text-zinc-400">{contadores.agendadas}</span>}
              {contadores && contadores.hoje > 0 && (
                <span className="px-1.5 py-0.5 rounded-full text-xs bg-amber-900/40 text-amber-300 border border-amber-800">
                  {contadores.hoje} hoje
                </span>
              )}
              {contadores && contadores.atrasadas > 0 && (
                <span className="px-1.5 py-0.5 rounded-full text-xs bg-red-900/40 text-red-300 border border-red-800">
                  {contadores.atrasadas} atrasada{contadores.atrasadas === 1 ? "" : "s"}
                </span>
              )}
              {contadores && contadores.futuras > 0 && (
                <span className="text-xs text-zinc-500">{contadores.futuras} próxima{contadores.futuras === 1 ? "" : "s"}</span>
              )}
            </button>
            <button type="button" onClick={() => mudarAba("sem_data")} disabled={salvando} className={classeAba("sem_data")}>
              Sem data
              {contadores && <span className="text-xs text-zinc-400">{contadores.sem_data}</span>}
            </button>
            {/* Folga, ferias, falta e outras ausencias sao da coordenacao: so a gestao ve a aba. */}
            {gestao && (
              <button
                type="button"
                onClick={() => mudarAba("ausencias")}
                disabled={salvando}
                className={classeAba("ausencias")}
                title="Folgas, férias, faltas e outras ausências que ainda não terminaram. Para achar uma falta já passada, informe o período."
              >
                Ausências
                {contadores && <span className="text-xs text-zinc-400">{contadores.ausencias}</span>}
              </button>
            )}
            <button type="button" onClick={() => mudarAba("historico")} disabled={salvando} className={classeAba("historico")}>
              Histórico
            </button>
            <button type="button" onClick={() => mudarAba("agenda")} disabled={salvando} className={classeAba("agenda")}>
              Agenda
            </button>
            {contadores && !contexto.gestao && contadores.minhas_pendentes > 0 && (
              <span className="text-xs text-zinc-500">
                Você tem {contadores.minhas_pendentes} tarefa{contadores.minhas_pendentes === 1 ? "" : "s"} pendente
                {contadores.minhas_pendentes === 1 ? "" : "s"}.
              </span>
            )}
          </div>

          {erro && !modal && (
            <div className="p-3 border border-red-700 rounded-lg bg-red-900/20 text-red-300 text-sm">{erro}</div>
          )}
          {ok && <div className="p-3 border border-green-700 rounded-lg bg-green-900/20 text-green-300 text-sm">{ok}</div>}

          {aba !== "agenda" && (
            <>
              <div className="flex items-end gap-3 flex-wrap">
                {mostraPeriodo && (
                  <>
                    <label className="text-xs text-zinc-400 flex flex-col gap-1">
                      {historico ? "Encerradas de" : "De"}
                      <input type="date" value={de} onChange={(e) => setDe(e.target.value)} className={CLASSE_INPUT_FILTRO} />
                    </label>
                    <label className="text-xs text-zinc-400 flex flex-col gap-1">
                      Até
                      <input type="date" value={ate} onChange={(e) => setAte(e.target.value)} className={CLASSE_INPUT_FILTRO} />
                    </label>
                  </>
                )}
                {podeCriar && (
                  <label className="text-xs text-zinc-400 flex flex-col gap-1">
                    Colaborador
                    <select
                      value={colaboradorFiltro}
                      onChange={(e) => setColaboradorFiltro(e.target.value)}
                      className={`${CLASSE_INPUT_FILTRO} min-w-48`}
                    >
                      <option value="">Todos</option>
                      {colaboradores.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.nome}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                <label className="text-xs text-zinc-400 flex flex-col gap-1 grow max-w-md">
                  Busca
                  <input
                    value={busca}
                    onChange={(e) => setBusca(e.target.value)}
                    placeholder="OS, cliente, descrição, colaborador, folga, férias, falta, atestado"
                    className={CLASSE_INPUT_FILTRO}
                  />
                </label>
                {(de || ate || colaboradorFiltro || busca) && (
                  <button
                    type="button"
                    onClick={() => {
                      setColaboradorFiltro("");
                      setBusca("");
                      if (historico) {
                        setDe(somarDias(hoje, -30));
                        setAte(hoje);
                      } else {
                        setDe("");
                        setAte("");
                      }
                    }}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                  >
                    Limpar
                  </button>
                )}
              </div>

              <div className="border border-zinc-800 rounded-lg overflow-x-auto bg-zinc-950">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/50">
                    <tr className="text-left">
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300 whitespace-nowrap">Data</th>
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Tipo</th>
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Colaborador</th>
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Cliente</th>
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">OS</th>
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Descrição</th>
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Situação</th>
                      {historico && <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Encerramento</th>}
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Reserva</th>
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">Ações</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-800">
                    {tarefas.map((t) => {
                      const pendente = t.situacao === "pendente";
                      const varios = (t.dias ?? 1) > 1;
                      return (
                        // A lista vem com uma linha por participante: a chave junta
                        // tarefa e pessoa, senao duas linhas da mesma tarefa colidem.
                        <tr key={`${t.id}|${t.colaborador_id}`} className={classeLinha(t)}>
                          <td className="px-3 py-2 text-zinc-200 whitespace-nowrap">
                            {t.data ? (
                              <>
                                <div>{dataBr(t.data)}</div>
                                {varios && t.data_fim ? (
                                  <div className="text-xs text-zinc-400">
                                    até {dataBr(t.data_fim)} · {t.dias} dias
                                  </div>
                                ) : (
                                  <div className="text-xs text-zinc-500">{diaSemana(t.data)}</div>
                                )}
                                {t.medida === "horas" && (
                                  <div className="text-xs text-zinc-400" title="Não reserva o dia: a pessoa trabalha o resto dele">
                                    {textoHoras(t.horas)}
                                  </div>
                                )}
                              </>
                            ) : (
                              <span className="text-zinc-500">Sem data</span>
                            )}
                          </td>
                          <td className="px-3 py-2">
                            <BadgeCategoria categoria={t.categoria} />
                          </td>
                          <td className="px-3 py-2 text-zinc-200">
                            {t.colaborador_nome}
                            {t.minha && <span className="ml-1 text-xs text-zinc-500">(você)</span>}
                            {t.participantes > 1 && (
                              <div className="text-xs text-zinc-400" title="Tarefa com vários participantes; cada um conclui a parte dele">
                                com mais {t.participantes - 1} {t.participantes - 1 === 1 ? "pessoa" : "pessoas"}
                              </div>
                            )}
                          </td>
                          {/* Em ausencia o banco manda OS e cliente nulos: traco, e nao
                              "Cliente não informado". */}
                          <td className="px-3 py-2 text-zinc-300">{t.cliente_nome ?? <span className="text-zinc-600">—</span>}</td>
                          <td className="px-3 py-2 whitespace-nowrap">
                            {t.os_id === null ? (
                              <span className="text-zinc-600">—</span>
                            ) : (
                              <Link href={`/os/${t.os_id}`} className="text-sky-400 hover:text-sky-300 underline" title={t.os_descricao ?? undefined}>
                                {t.numero_os}
                              </Link>
                            )}
                          </td>
                          <td className="px-3 py-2 text-zinc-200 max-w-md">
                            <button
                              type="button"
                              onClick={() => abrirModal({ tipo: "detalhe", tarefa: t })}
                              className="text-left hover:underline"
                              title="Ver detalhe e histórico de reservas"
                            >
                              {textoCurto(t.descricao, 140)}
                            </button>
                          </td>
                          <td className="px-3 py-2">
                            <BadgeSituacao tarefa={t} />
                          </td>
                          {historico && (
                            <td className="px-3 py-2 text-xs text-zinc-400 max-w-xs">
                              <div>{textoEncerramento(t)}</div>
                              {t.situacao === "cancelada" && t.cancelamento_motivo && (
                                <div className="text-zinc-500">Motivo: {t.cancelamento_motivo}</div>
                              )}
                            </td>
                          )}
                          <td className="px-3 py-2 text-xs text-zinc-400 max-w-xs">
                            {t.reserva_ativa ? <span className="text-sky-300">Ativa</span> : textoReserva(t)}
                          </td>
                          <td className="px-3 py-2">
                            <div className="flex flex-wrap gap-1">
                              {/* O atestado chega dias depois: a falta ja registrada troca
                                  de "sem atestado" para "com atestado" sem perder nada.
                                  Vem antes das outras acoes porque e o que se procura ao
                                  voltar numa falta antiga. */}
                              {ehFalta(t.categoria) && t.pode_gerir && t.situacao !== "cancelada" && (
                                <BotaoAcao
                                  onClick={() => abrirModal({ tipo: "atestado", tarefa: t, comAtestado: t.categoria === "falta" })}
                                  disabled={ocupado}
                                  title={
                                    t.categoria === "falta"
                                      ? "A pessoa apresentou o atestado depois: esta falta passa a ser falta com atestado"
                                      : "Marcou o atestado na falta errada: volta a ser falta sem atestado"
                                  }
                                >
                                  {t.categoria === "falta" ? "Marcar atestado" : "Tirar atestado"}
                                </BotaoAcao>
                              )}
                              {pendente && t.pode_concluir && (
                                <BotaoAcao
                                  onClick={() => void concluirParte(t, t.colaborador_id, t.colaborador_nome, "pagina")}
                                  disabled={ocupado}
                                  title={
                                    t.participantes > 1
                                      ? `Conclui a parte de ${t.colaborador_nome}; a tarefa fecha quando o último concluir`
                                      : "Registra a execução; não libera o dia"
                                  }
                                >
                                  {t.participantes > 1 ? "Concluir a parte" : "Concluir"}
                                </BotaoAcao>
                              )}
                              {pendente && t.pode_gerir && (
                                <>
                                  <BotaoAcao onClick={() => abrirModal({ tipo: "reagendar", tarefa: t })} disabled={ocupado}>
                                    {t.tipo === "agendada" ? "Reagendar" : "Agendar"}
                                  </BotaoAcao>
                                  {/* Folga, ferias e outras ausencias precisam de data: nao passam para sem data. */}
                                  {t.tipo === "agendada" && !ehAusencia(t) && (
                                    <BotaoAcao onClick={() => void passarParaSemData(t)} disabled={ocupado} title="Tira a data e libera os dias">
                                      Sem data
                                    </BotaoAcao>
                                  )}
                                  <BotaoAcao
                                    onClick={() => abrirModal({ tipo: "participantes", tarefa: t })}
                                    disabled={ocupado}
                                    title="Adicionar ou remover quem participa da tarefa"
                                  >
                                    Participantes ({t.participantes})
                                  </BotaoAcao>
                                  {/* Com uma pessoa so a troca direta continua sendo o caminho
                                      curto; com duas ou mais o banco recusa e manda usar
                                      adicionar/remover. */}
                                  {t.participantes === 1 && (
                                    <BotaoAcao onClick={() => abrirModal({ tipo: "trocar", tarefa: t })} disabled={ocupado}>
                                      Trocar colaborador
                                    </BotaoAcao>
                                  )}
                                  <BotaoAcao onClick={() => abrirModal({ tipo: "editar", tarefa: t })} disabled={ocupado}>
                                    Editar descrição
                                  </BotaoAcao>
                                  <BotaoAcao onClick={() => abrirModal({ tipo: "cancelar", tarefa: t })} disabled={ocupado}>
                                    Cancelar
                                  </BotaoAcao>
                                </>
                              )}
                              {t.situacao === "concluida" && t.pode_gerir && t.reserva_ativa && (
                                <BotaoAcao
                                  onClick={() => abrirModal({ tipo: "liberar", tarefa: t })}
                                  disabled={ocupado}
                                  title={
                                    t.participantes > 1
                                      ? "Libera os dias de todos os participantes; concluir não libera"
                                      : "Libera o dia do colaborador; concluir não libera"
                                  }
                                >
                                  Liberar reserva
                                </BotaoAcao>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                    {tarefas.length === 0 && (
                      <tr>
                        <td className="px-3 py-4 text-zinc-400 text-center" colSpan={colunas}>
                          {carregandoLista
                            ? "Carregando..."
                            : aba === "agendadas"
                              ? "Nenhuma tarefa agendada pendente."
                              : aba === "sem_data"
                                ? "Nenhuma tarefa sem data pendente."
                                : aba === "ausencias"
                                  ? "Nenhuma folga, férias, falta ou outra ausência em aberto. Para ver ausências já passadas, informe o período acima."
                                  : "Nenhuma tarefa concluída ou cancelada no período."}
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </>
          )}

          {aba === "agenda" && (
            <>
              <div className="flex items-end gap-3 flex-wrap">
                <button
                  type="button"
                  onClick={() => setAgendaInicio((atual) => somarDias(atual || hoje, -agendaDias))}
                  className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                >
                  ← Anterior
                </button>
                <label className="text-xs text-zinc-400 flex flex-col gap-1">
                  A partir de
                  <input
                    type="date"
                    value={agendaInicio}
                    onChange={(e) => {
                      if (e.target.value) setAgendaInicio(e.target.value);
                    }}
                    className={CLASSE_INPUT_FILTRO}
                  />
                </label>
                <button
                  type="button"
                  onClick={() => setAgendaInicio((atual) => somarDias(atual || hoje, agendaDias))}
                  className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                >
                  Próximo →
                </button>
                <button
                  type="button"
                  onClick={() => setAgendaInicio(hoje)}
                  className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                >
                  Hoje
                </button>
                <div className="flex items-center gap-1 text-sm">
                  {([7, 14] as const).map((dias) => (
                    <button
                      key={dias}
                      type="button"
                      onClick={() => setAgendaDias(dias)}
                      className={`px-3 py-1.5 rounded-md border text-sm ${
                        agendaDias === dias ? "border-zinc-500 bg-zinc-800 text-zinc-100" : "border-zinc-700 bg-zinc-900 text-zinc-400 hover:bg-zinc-800"
                      }`}
                    >
                      {dias} dias
                    </button>
                  ))}
                </div>
                <span className="text-xs text-zinc-500">
                  <span className="inline-block w-3 h-3 rounded-sm bg-sky-900/70 border border-sky-800 align-middle mr-1" />
                  pendente
                  <span className="inline-block w-3 h-3 rounded-sm bg-green-900/70 border border-green-800 align-middle ml-3 mr-1" />
                  concluída
                  <span className="inline-block w-3 h-3 rounded-sm bg-zinc-800 border border-zinc-700 align-middle ml-3 mr-1" />
                  reservado (sem detalhe)
                  <span className="inline-block w-3 h-3 rounded-sm border border-dashed border-zinc-500 align-middle ml-3 mr-1" />
                  tracejado = ausência em horas (o dia segue livre)
                </span>
                {/* A ausencia vem com a cor da categoria; sem legenda o rosa da falta
                    passava por "atrasada", que e vermelha na lista. */}
                <span className="text-xs text-zinc-500">
                  <span className="inline-block w-3 h-3 rounded-sm bg-violet-900/70 border border-violet-800 align-middle mr-1" />
                  folga
                  <span className="inline-block w-3 h-3 rounded-sm bg-teal-900/70 border border-teal-800 align-middle ml-3 mr-1" />
                  férias
                  <span className="inline-block w-3 h-3 rounded-sm bg-yellow-900/70 border border-yellow-800 align-middle ml-3 mr-1" />
                  falta com atestado
                  <span className="inline-block w-3 h-3 rounded-sm bg-rose-900/70 border border-rose-800 align-middle ml-3 mr-1" />
                  falta sem atestado
                </span>
              </div>

              <div className="border border-zinc-800 rounded-lg overflow-x-auto bg-zinc-950">
                <table className="w-full text-xs">
                  <thead className="bg-zinc-900/50">
                    <tr className="text-left">
                      <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300 whitespace-nowrap sticky left-0 bg-zinc-900">
                        Colaborador
                      </th>
                      {diasAgenda.map((dia) => (
                        <th
                          key={dia}
                          className={`px-2 py-2 border-b border-zinc-800 text-center whitespace-nowrap ${
                            dia === hoje ? "text-amber-300" : "text-zinc-300"
                          } ${fimDeSemana(dia) ? "bg-zinc-900/80" : ""}`}
                        >
                          <div>{diaSemana(dia)}</div>
                          <div className="font-normal text-zinc-500">{dataBr(dia).slice(0, 5)}</div>
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-800">
                    {linhasAgenda.map((linha) => (
                      <tr key={linha.id} className="hover:bg-zinc-900/40">
                        <td className="px-3 py-2 text-zinc-200 whitespace-nowrap sticky left-0 bg-zinc-950">{linha.nome}</td>
                        {diasAgenda.map((dia) => {
                          const itens = celulasAgenda.get(`${linha.id}|${dia}`) ?? [];
                          return (
                            <td
                              key={dia}
                              className={`px-1 py-1 align-top min-w-28 ${fimDeSemana(dia) ? "bg-zinc-900/60" : ""} ${
                                dia === hoje ? "border-x border-amber-900/40" : ""
                              }`}
                            >
                              {itens.map((item) => {
                                const horasFora = Number(item.horas ?? 0);
                                const rotulo = !item.detalhe_visivel
                                  ? "Reservado"
                                  : !item.reserva_dia
                                    ? `${rotuloCategoria(item.categoria)} ${textoHoras(horasFora)}`
                                    : item.categoria === "os"
                                      ? `OS ${item.numero_os ?? "—"} · ${item.cliente_nome ?? "—"}`
                                      : rotuloCategoria(item.categoria);
                                const conteudo = (
                                  <span className={`block px-1.5 py-1 rounded border ${classeCelulaAgenda(item)}`}>{rotulo}</span>
                                );
                                return item.detalhe_visivel ? (
                                  <button
                                    key={`${item.tarefa_id}|${item.reserva_dia}`}
                                    type="button"
                                    title={item.descricao ?? undefined}
                                    onClick={() => abrirDetalheDaAgenda(item)}
                                    className="w-full text-left"
                                  >
                                    {conteudo}
                                  </button>
                                ) : (
                                  <span key={`${item.tarefa_id}|${item.reserva_dia}`} title="Reservado por uma tarefa que você não pode ver">
                                    {conteudo}
                                  </span>
                                );
                              })}
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                    {linhasAgenda.length === 0 && (
                      <tr>
                        <td className="px-3 py-4 text-zinc-400 text-center" colSpan={diasAgenda.length + 1}>
                          {carregandoAgenda ? "Carregando..." : "Nada marcado no período."}
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </>
      )}

      {modal && (
        <div className="fixed inset-0 z-50 bg-black/60 flex justify-center p-4 overflow-y-auto">
          <div
            className={`w-full ${
              modal.tipo === "nova" || modal.tipo === "detalhe" || modal.tipo === "participantes" ? "max-w-2xl" : "max-w-lg"
            } bg-zinc-900 border border-zinc-700 rounded-xl p-6 space-y-4 shadow-xl my-auto h-fit`}
          >
            <h2 className="text-lg font-semibold text-zinc-100">{tituloModal(modal)}</h2>

            {modal.tipo !== "nova" && (
              <div className="text-sm text-zinc-400">
                {resumoTarefa(modal.tarefa)}
                {modal.tipo !== "detalhe" && modal.tipo !== "editar" && (
                  <div className="text-zinc-500 mt-1">{textoCurto(modal.tarefa.descricao, 160)}</div>
                )}
              </div>
            )}

            {modalErro && <div className="p-3 border border-red-700 rounded-lg bg-red-900/20 text-red-300 text-sm">{modalErro}</div>}
            {modalOk && <div className="p-3 border border-green-700 rounded-lg bg-green-900/20 text-green-300 text-sm">{modalOk}</div>}

            {modal.tipo === "nova" && (
              <div className="space-y-3">
                <div className="space-y-1">
                  <label className="text-sm text-zinc-300" htmlFor="tarefa-categoria">
                    Tipo de registro *
                  </label>
                  <select
                    id="tarefa-categoria"
                    value={novaCategoria}
                    onChange={(e) => {
                      const valor = e.target.value as Categoria;
                      setNovaCategoria(valor);
                      // Ausencia sempre tem data e nao tem OS; em horas a duracao e
                      // de um dia. Volta tudo ao estado que o banco aceita.
                      if (valor !== "os") {
                        setNovoTipo("agendada");
                        setNovaOsId("");
                        if (!campoData) setCampoData(hoje);
                      } else {
                        setNovaMedida("dias");
                      }
                    }}
                    className={CLASSE_INPUT}
                  >
                    <option value="os">Trabalho em OS</option>
                    {/* Ausencia — falta inclusive — e so da coordenacao para cima: quem
                        nao e gestao nem enxerga as opcoes, e o banco recusa de qualquer
                        jeito (fn_tarefas_criar exige v_ctx.gestao). */}
                    {gestao && (
                      <optgroup label="Ausência (só a coordenação)">
                        {CATEGORIAS.filter((c) => c.valor !== "os").map((c) => (
                          <option key={c.valor} value={c.valor}>
                            {c.rotulo}
                          </option>
                        ))}
                      </optgroup>
                    )}
                  </select>
                  <small className="text-zinc-500 block">
                    {novaCategoria === "os"
                      ? "Trabalho em OS: precisa de uma OS em andamento."
                      : novaCategoria === "falta_justificada"
                        ? "Falta com atestado: desconta da meta da semana, como folga e férias. O documento não é anexado no sistema."
                        : novaCategoria === "falta"
                          ? "Falta sem atestado: não desconta da meta da semana. Se o atestado chegar depois, use “Marcar atestado” na aba Ausências — não registre a falta de novo."
                          : "Folga, férias e outras ausências não têm OS e só a coordenação registra."}
                  </small>
                </div>

                {novaCategoria === "os" && (
                  <div className="space-y-1">
                    <span className="text-sm text-zinc-300">Tipo *</span>
                    <div className="flex gap-4 text-sm text-zinc-200 flex-wrap">
                      <label className="flex items-center gap-2">
                        <input type="radio" name="tipo" checked={novoTipo === "agendada"} onChange={() => setNovoTipo("agendada")} />
                        Agendada (reserva o dia inteiro)
                      </label>
                      <label className="flex items-center gap-2">
                        <input type="radio" name="tipo" checked={novoTipo === "sem_data"} onChange={() => setNovoTipo("sem_data")} />
                        Sem data (só pendente)
                      </label>
                    </div>
                  </div>
                )}

                {novaCategoria !== "os" && (
                  <div className="space-y-1">
                    <span className="text-sm text-zinc-300">Medir em *</span>
                    <div className="flex gap-4 text-sm text-zinc-200 flex-wrap">
                      <label className="flex items-center gap-2">
                        <input type="radio" name="medida" checked={novaMedida === "dias"} onChange={() => setNovaMedida("dias")} />
                        {ehFalta(novaCategoria) ? "Dia inteiro (reserva o dia)" : "Dias (reserva o dia inteiro)"}
                      </label>
                      <label className="flex items-center gap-2">
                        <input type="radio" name="medida" checked={novaMedida === "horas"} onChange={() => setNovaMedida("horas")} />
                        Horas de um dia
                      </label>
                    </div>
                    <small className="text-zinc-500 block">
                      Em horas o dia <strong>não</strong> fica reservado: a pessoa trabalha o resto dele.
                      {ehFalta(novaCategoria) ? " Atraso ou saída antes do fim do expediente é falta em horas." : ""}
                    </small>
                  </div>
                )}

                {novoTipo === "agendada" && (
                  <div className="flex gap-3 flex-wrap">
                    <div className="space-y-1 grow">
                      <label className="text-sm text-zinc-300" htmlFor="tarefa-data">
                        {novaMedida === "horas" || novaCategoria === "os" ? "Data *" : "Primeiro dia *"}
                      </label>
                      <input
                        id="tarefa-data"
                        type="date"
                        value={campoData}
                        onChange={(e) => setCampoData(e.target.value)}
                        className={CLASSE_INPUT}
                      />
                    </div>
                    {novaMedida === "dias" ? (
                      <div className="space-y-1 w-36">
                        <label className="text-sm text-zinc-300" htmlFor="tarefa-dias">
                          Quantos dias *
                        </label>
                        <input
                          id="tarefa-dias"
                          type="number"
                          min={1}
                          max={60}
                          step={1}
                          value={campoDias}
                          onChange={(e) => setCampoDias(e.target.value)}
                          className={CLASSE_INPUT}
                        />
                      </div>
                    ) : (
                      <div className="space-y-1 w-36">
                        <label className="text-sm text-zinc-300" htmlFor="tarefa-horas">
                          Quantas horas *
                        </label>
                        <input
                          id="tarefa-horas"
                          type="number"
                          min={0.5}
                          max={24}
                          step={0.5}
                          value={novasHoras}
                          onChange={(e) => setNovasHoras(e.target.value)}
                          className={CLASSE_INPUT}
                        />
                      </div>
                    )}
                  </div>
                )}

                {novoTipo === "agendada" && (
                  <small className="text-zinc-500 block">
                    {novaMedida === "horas"
                      ? "Um dia só, com as horas informadas."
                      : Number(campoDias) > 1 && campoData
                        ? `De ${dataBr(campoData)} a ${dataBr(somarDias(campoData, Number(campoDias) - 1))}: todos esses dias ficam reservados para cada participante.`
                        : "Datas futuras são permitidas. O dia inteiro fica reservado para cada participante."}
                  </small>
                )}

                <div className="space-y-1">
                  <label className="text-sm text-zinc-300" htmlFor="tarefa-colaborador">
                    Colaboradores *
                  </label>
                  <select
                    id="tarefa-colaborador"
                    value=""
                    onChange={(e) => {
                      const id = e.target.value;
                      if (!id) return;
                      setNovosColaboradores((atual) => (atual.includes(id) ? atual : [...atual, id]));
                    }}
                    className={CLASSE_INPUT}
                    disabled={carregandoColabs}
                  >
                    <option value="">{carregandoColabs ? "Carregando..." : "Acrescentar colaborador"}</option>
                    {modalColaboradores
                      .filter((c) => !novosColaboradores.includes(c.id))
                      .map((c) => (
                        <option key={c.id} value={c.id} disabled={c.ocupado}>
                          {c.nome}
                          {c.cargo ? ` · ${c.cargo}` : ""}
                          {c.sou_eu ? " (você)" : ""}
                          {c.ocupado ? ` (ocupado: ${c.ocupado_resumo ?? "neste dia"})` : ""}
                        </option>
                      ))}
                  </select>
                  {novosColaboradores.length === 0 ? (
                    <div className="text-sm text-zinc-500">Nenhum colaborador escolhido ainda.</div>
                  ) : (
                    <ul className="flex flex-wrap gap-2">
                      {novosColaboradores.map((id) => {
                        const c = modalColaboradores.find((x) => x.id === id);
                        return (
                          <li
                            key={id}
                            className="flex items-center gap-2 px-2 py-1 rounded-full border border-zinc-700 bg-zinc-800 text-sm text-zinc-200"
                          >
                            <span>{c?.nome ?? "Colaborador"}</span>
                            <button
                              type="button"
                              onClick={() => setNovosColaboradores((atual) => atual.filter((x) => x !== id))}
                              className="text-zinc-400 hover:text-zinc-100"
                              title={`Tirar ${c?.nome ?? "o colaborador"} da tarefa`}
                              aria-label={`Tirar ${c?.nome ?? "o colaborador"} da tarefa`}
                            >
                              ×
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                  <small className="text-zinc-500 block">
                    {novoTipo === "agendada" && novaMedida === "dias"
                      ? "Quem já tem algum dia reservado aparece desabilitado, com o motivo. Um dia ocupado de qualquer um derruba a criação inteira."
                      : "Pelo menos uma pessoa, sem repetir."}
                  </small>
                </div>

                {novaCategoria === "os" && (
                  <div className="space-y-1">
                    <label className="text-sm text-zinc-300">OS *</label>
                    <input
                      value={buscaOs}
                      onChange={(e) => setBuscaOs(e.target.value)}
                      placeholder="Buscar OS por número, cliente ou descrição"
                      className={CLASSE_INPUT}
                      aria-label="Buscar OS"
                    />
                    <select
                      value={novaOsId}
                      onChange={(e) => setNovaOsId(e.target.value)}
                      className={CLASSE_INPUT}
                      aria-label="OS"
                    >
                      <option value="">{carregandoOs ? "Carregando..." : osElegiveis.length === 0 ? "Nenhuma OS em andamento encontrada" : "Selecione"}</option>
                      {osPorCliente.map((grupo) => (
                        <optgroup key={grupo.cliente} label={grupo.cliente}>
                          {grupo.lista.map((os) => (
                            <option key={os.id} value={String(os.id)}>
                              OS {os.numero_os}
                              {os.descricao_servico ? ` · ${textoCurto(os.descricao_servico, 60)}` : ""}
                              {` · resp.: ${os.responsavel_nome ?? "—"}`}
                              {os.tarefas_pendentes > 0 ? ` · ${os.tarefas_pendentes} pendente${os.tarefas_pendentes === 1 ? "" : "s"}` : ""}
                            </option>
                          ))}
                        </optgroup>
                      ))}
                    </select>
                    <small className="text-zinc-500 block">Só OS em andamento onde você pode criar tarefas.</small>
                  </div>
                )}

                <div className="space-y-1">
                  {/* Na falta a observacao e opcional: o que importa e o registro do
                      dia, com ou sem atestado. O banco continua exigindo descricao,
                      entao em branco a tela grava "Falta" — texto que continua certo
                      quando o atestado chegar depois e a categoria mudar. */}
                  <label className="text-sm text-zinc-300">{ehFalta(novaCategoria) ? "Observação" : "Descrição *"}</label>
                  <textarea
                    value={campoTexto}
                    onChange={(e) => setCampoTexto(e.target.value)}
                    rows={3}
                    maxLength={2000}
                    placeholder={
                      novaCategoria === "os"
                        ? "O que os colaboradores vão fazer"
                        : ehFalta(novaCategoria)
                          ? "Opcional: motivo ou observação da falta"
                          : "Motivo ou observação da ausência"
                    }
                    className={CLASSE_INPUT}
                    aria-label={ehFalta(novaCategoria) ? "Observação" : "Descrição"}
                  />
                  {ehFalta(novaCategoria) && (
                    <small className="text-zinc-500 block">Pode ficar em branco: sem observação a falta fica registrada como “Falta”.</small>
                  )}
                </div>
              </div>
            )}

            {modal.tipo === "reagendar" && (
              <div className="space-y-2">
                <div className="flex gap-3 flex-wrap">
                  <div className="space-y-1 grow">
                    <label className="text-sm text-zinc-300" htmlFor="reagendar-data">
                      {(modal.tarefa.dias ?? 1) > 1 ? "Novo primeiro dia *" : "Nova data *"}
                    </label>
                    <input
                      id="reagendar-data"
                      type="date"
                      value={campoData}
                      onChange={(e) => setCampoData(e.target.value)}
                      className={CLASSE_INPUT}
                    />
                  </div>
                  {/* Em horas a tarefa e sempre de um dia: nao ha o que escolher. */}
                  {modal.tarefa.medida === "dias" && (
                    <div className="space-y-1 w-36">
                      <label className="text-sm text-zinc-300" htmlFor="reagendar-dias">
                        Quantos dias *
                      </label>
                      <input
                        id="reagendar-dias"
                        type="number"
                        min={1}
                        max={60}
                        step={1}
                        value={campoDias}
                        onChange={(e) => setCampoDias(e.target.value)}
                        className={CLASSE_INPUT}
                      />
                    </div>
                  )}
                </div>
                <small className="text-zinc-500 block">
                  {modal.tarefa.medida === "horas"
                    ? `${textoHoras(modal.tarefa.horas)} num dia só; o dia não fica reservado.`
                    : Number(campoDias) > 1 && campoData
                      ? `De ${dataBr(campoData)} a ${dataBr(somarDias(campoData, Number(campoDias) - 1))}: todos esses dias ficam reservados para cada participante.`
                      : "O dia inteiro fica reservado para cada participante."}
                </small>
                <small className="text-zinc-500 block">
                  {modal.tarefa.tipo === "agendada"
                    ? `Os dias de agora (${textoDuracao(modal.tarefa)}) são liberados e os novos ficam reservados para ${
                        modal.tarefa.participantes > 1 ? `os ${modal.tarefa.participantes} participantes` : modal.tarefa.colaborador_nome
                      }.`
                    : `A tarefa passa a ser agendada e os dias ficam reservados para ${
                        modal.tarefa.participantes > 1 ? `os ${modal.tarefa.participantes} participantes` : modal.tarefa.colaborador_nome
                      }.`}
                </small>
              </div>
            )}

            {modal.tipo === "trocar" && (
              <div className="space-y-1">
                <label className="text-sm text-zinc-300">Novo colaborador *</label>
                <select
                  value={campoColaborador}
                  onChange={(e) => setCampoColaborador(e.target.value)}
                  className={CLASSE_INPUT}
                  aria-label="Novo colaborador"
                  disabled={carregandoColabs}
                >
                  <option value="">{carregandoColabs ? "Carregando..." : "Selecione"}</option>
                  {modalColaboradores.map((c) => {
                    const indisponivel = c.ocupado && c.ocupado_tarefa_id !== modal.tarefa.id;
                    return (
                      <option key={c.id} value={c.id} disabled={indisponivel}>
                        {c.nome}
                        {c.cargo ? ` · ${c.cargo}` : ""}
                        {c.id === modal.tarefa.colaborador_id ? " (atual)" : ""}
                        {indisponivel ? ` (reservado: ${c.ocupado_resumo ?? "neste dia"})` : ""}
                      </option>
                    );
                  })}
                </select>
                {modal.tarefa.data && (
                  <small className="text-zinc-500 block">
                    A reserva de {textoDuracao(modal.tarefa)} passa para o novo colaborador; quem já tem algum desses dias reservado aparece
                    desabilitado.
                  </small>
                )}
              </div>
            )}

            {modal.tipo === "participantes" && (
              <div className="space-y-4">
                <div className="space-y-1">
                  <div className="text-sm text-zinc-300 font-medium">Quem está na tarefa</div>
                  {!detalhe && !modalErro && <div className="text-sm text-zinc-400">Carregando...</div>}
                  {detalhe && (detalhe.participantes ?? []).length === 0 && (
                    <div className="text-sm text-zinc-500">Nenhum participante.</div>
                  )}
                  <ul className={(detalhe?.participantes ?? []).length === 0 ? "hidden" : "divide-y divide-zinc-800 border border-zinc-800 rounded-lg"}>
                    {(detalhe?.participantes ?? []).map((p) => {
                      const total = (detalhe?.participantes ?? []).length;
                      const pendenteDele = p.concluida_em === null;
                      return (
                        <li key={p.colaborador_id} className="px-3 py-2 flex items-center justify-between gap-3 flex-wrap">
                          <div className="text-sm">
                            <div className="text-zinc-200">{p.nome}</div>
                            <div className="text-xs text-zinc-500">
                              {p.concluida_em
                                ? `Concluiu em ${dataHoraBr(p.concluida_em)}${p.concluida_por_nome ? ` · ${p.concluida_por_nome}` : ""}`
                                : "Parte em aberto"}
                            </div>
                          </div>
                          <div className="flex gap-1 flex-wrap">
                            {pendenteDele && modal.tarefa.situacao !== "cancelada" && (
                              <BotaoAcao
                                onClick={() => void concluirParte(modal.tarefa, p.colaborador_id, p.nome, "modal")}
                                disabled={salvando}
                                title="Conclui a parte desta pessoa; não libera o dia"
                              >
                                Concluir a parte
                              </BotaoAcao>
                            )}
                            {/* A tarefa nunca fica sem ninguem: com uma pessoa so o banco
                                recusa e o caminho e cancelar ou trocar. */}
                            <BotaoAcao
                              onClick={() => void removerParticipante(modal.tarefa, p)}
                              disabled={salvando || total <= 1}
                              title={
                                total <= 1
                                  ? "A tarefa precisa de pelo menos uma pessoa. Cancele a tarefa ou troque o colaborador."
                                  : `Tira ${p.nome} da tarefa e libera os dias dele(a)`
                              }
                            >
                              Remover
                            </BotaoAcao>
                          </div>
                        </li>
                      );
                    })}
                  </ul>
                </div>

                <div className="space-y-1">
                  <label className="text-sm text-zinc-300" htmlFor="participante-novo">
                    Adicionar participante
                  </label>
                  <select
                    id="participante-novo"
                    value={campoColaborador}
                    onChange={(e) => setCampoColaborador(e.target.value)}
                    className={CLASSE_INPUT}
                    disabled={carregandoColabs}
                  >
                    <option value="">{carregandoColabs ? "Carregando..." : "Selecione"}</option>
                    {modalColaboradores
                      .filter((c) => !(detalhe?.participantes ?? []).some((p) => p.colaborador_id === c.id))
                      .map((c) => {
                        const indisponivel = c.ocupado && c.ocupado_tarefa_id !== modal.tarefa.id;
                        return (
                          <option key={c.id} value={c.id} disabled={indisponivel}>
                            {c.nome}
                            {c.cargo ? ` · ${c.cargo}` : ""}
                            {indisponivel ? ` (ocupado: ${c.ocupado_resumo ?? "neste dia"})` : ""}
                          </option>
                        );
                      })}
                  </select>
                  <small className="text-zinc-500 block">
                    {modal.tarefa.data
                      ? `Quem entrar fica com ${textoDuracao(modal.tarefa)} reservado${modal.tarefa.medida === "horas" ? " (horas não reservam o dia)" : ""}; quem já tem algum desses dias ocupado aparece desabilitado.`
                      : "A tarefa está sem data: ninguém fica com dia reservado."}
                  </small>
                </div>
              </div>
            )}

            {modal.tipo === "editar" && (
              <div className="space-y-1">
                <label className="text-sm text-zinc-300">Descrição *</label>
                <textarea
                  value={campoTexto}
                  onChange={(e) => setCampoTexto(e.target.value)}
                  rows={4}
                  maxLength={2000}
                  className={CLASSE_INPUT}
                  aria-label="Descrição"
                />
              </div>
            )}

            {modal.tipo === "cancelar" && (
              <div className="space-y-1">
                <label className="text-sm text-zinc-300">Motivo (opcional)</label>
                <textarea
                  value={campoTexto}
                  onChange={(e) => setCampoTexto(e.target.value)}
                  rows={3}
                  className={CLASSE_INPUT}
                  aria-label="Motivo do cancelamento"
                />
                <small className="text-zinc-500 block">
                  {modal.tarefa.tipo === "agendada"
                    ? `Cancelar libera ${textoDuracao(modal.tarefa)} de ${
                        modal.tarefa.participantes > 1 ? `todos os ${modal.tarefa.participantes} participantes` : modal.tarefa.colaborador_nome
                      }.`
                    : "A tarefa sai das pendentes e vai para o histórico."}
                </small>
              </div>
            )}

            {modal.tipo === "liberar" && (
              <div className="space-y-2">
                <p className="text-sm text-zinc-300">
                  Concluir uma tarefa registra a execução, mas <strong>não libera o dia</strong>: {textoDuracao(modal.tarefa)} de{" "}
                  {modal.tarefa.participantes > 1 ? `todos os ${modal.tarefa.participantes} participantes` : modal.tarefa.colaborador_nome}{" "}
                  continua reservado. Liberar deixa os dias livres para outra tarefa. A conclusão fica registrada do mesmo jeito.
                </p>
                <label className="text-sm text-zinc-300">Motivo (opcional)</label>
                <textarea
                  value={campoTexto}
                  onChange={(e) => setCampoTexto(e.target.value)}
                  rows={3}
                  className={CLASSE_INPUT}
                  aria-label="Motivo da liberação"
                />
              </div>
            )}

            {modal.tipo === "atestado" && (
              <div className="space-y-2 text-sm text-zinc-300">
                <p>
                  {modal.comAtestado ? "A pessoa apresentou o atestado depois. " : "O atestado foi marcado nesta falta por engano. "}A
                  falta de{" "}
                  <strong>
                    {modal.tarefa.participantes > 1
                      ? `${modal.tarefa.participantes} participantes`
                      : modal.tarefa.colaborador_nome}
                  </strong>{" "}
                  em <strong>{textoDuracao(modal.tarefa)}</strong> passa de{" "}
                  <strong>{modal.comAtestado ? "falta sem atestado" : "falta com atestado"}</strong> para{" "}
                  <strong>{modal.comAtestado ? "falta com atestado" : "falta sem atestado"}</strong>.
                </p>
                <p className="text-zinc-400">
                  É o mesmo registro: nada é cancelado nem cadastrado de novo, a reserva do dia continua como está e o histórico da falta
                  fica inteiro. O que muda é a meta da semana —{" "}
                  {modal.comAtestado
                    ? "com atestado a falta passa a descontar, como folga e férias"
                    : "sem atestado a falta deixa de descontar"}
                  . O documento não é anexado no sistema.
                </p>
              </div>
            )}

            {modal.tipo === "detalhe" && (
              <div className="space-y-3 text-sm">
                {!detalhe && !modalErro && <div className="text-zinc-400">Carregando...</div>}
                {detalhe?.tarefa && (
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-1 text-zinc-300">
                    <div>
                      <span className="text-zinc-500">Tipo de registro:</span> <BadgeCategoria categoria={detalhe.tarefa.categoria} />
                    </div>
                    <div>
                      <span className="text-zinc-500">Agendamento:</span> {detalhe.tarefa.tipo === "agendada" ? "Agendada" : "Sem data"}
                    </div>
                    <div>
                      <span className="text-zinc-500">Duração:</span>{" "}
                      {detalhe.tarefa.data
                        ? `${textoDuracao(detalhe.tarefa)} (${diaSemana(detalhe.tarefa.data)})`
                        : "Sem data"}
                    </div>
                    <div>
                      <span className="text-zinc-500">Situação:</span> <BadgeSituacao tarefa={detalhe.tarefa} />
                    </div>
                    {detalhe.tarefa.medida === "horas" && (
                      <div className="sm:col-span-2 text-zinc-400">
                        Medida em horas: {textoHoras(detalhe.tarefa.horas)} de um dia só, sem reservar o dia.
                      </div>
                    )}
                    {ehFalta(detalhe.tarefa.categoria) && (
                      <div className="sm:col-span-2 text-zinc-400">
                        {textoMetaDaFalta(detalhe.tarefa.categoria)}
                        {detalhe.tarefa.categoria === "falta" && detalhe.tarefa.pode_gerir
                          ? " Se a pessoa apresentar o atestado depois, use “Marcar atestado” na linha desta falta, na aba Ausências: o registro é o mesmo."
                          : ""}
                      </div>
                    )}
                    <div>
                      <span className="text-zinc-500">Reserva:</span> {textoReserva(detalhe.tarefa)}
                    </div>
                    <div>
                      <span className="text-zinc-500">OS:</span>{" "}
                      {detalhe.tarefa.os_id === null ? (
                        <span className="text-zinc-500">— (ausência não tem OS)</span>
                      ) : (
                        <>
                          <Link href={`/os/${detalhe.tarefa.os_id}`} className="text-sky-400 hover:text-sky-300 underline">
                            {detalhe.tarefa.numero_os}
                          </Link>{" "}
                          · {detalhe.tarefa.cliente_nome ?? "—"}
                        </>
                      )}
                    </div>
                    <div className="sm:col-span-2">
                      <span className="text-zinc-500">Descrição:</span> <span className="whitespace-pre-wrap">{detalhe.tarefa.descricao}</span>
                    </div>
                    <div>
                      <span className="text-zinc-500">Criada:</span> {dataHoraBr(detalhe.tarefa.criado_em)}
                      {detalhe.tarefa.criado_por_nome ? ` por ${detalhe.tarefa.criado_por_nome}` : ""}
                    </div>
                    {detalhe.tarefa.situacao !== "pendente" && (
                      <div className="sm:col-span-2">
                        {textoEncerramento(detalhe.tarefa)}
                        {detalhe.tarefa.cancelamento_motivo ? ` — motivo: ${detalhe.tarefa.cancelamento_motivo}` : ""}
                      </div>
                    )}
                  </div>
                )}
                {detalhe && (
                  <div className="space-y-1">
                    <div className="text-zinc-300 font-medium">
                      Participantes ({(detalhe.participantes ?? []).length})
                      <span className="ml-2 text-xs font-normal text-zinc-500">
                        A tarefa fecha quando o último participante conclui a parte dele.
                      </span>
                    </div>
                    {(detalhe.participantes ?? []).length === 0 ? (
                      <div className="text-zinc-500">Nenhum participante.</div>
                    ) : (
                      <div className="border border-zinc-800 rounded-lg overflow-x-auto">
                        <table className="w-full text-xs">
                          <thead className="bg-zinc-900/50">
                            <tr className="text-left">
                              <th className="px-2 py-1.5 border-b border-zinc-800 text-zinc-300">Pessoa</th>
                              <th className="px-2 py-1.5 border-b border-zinc-800 text-zinc-300">Situação</th>
                              <th className="px-2 py-1.5 border-b border-zinc-800 text-zinc-300">Conclusão</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-zinc-800">
                            {(detalhe.participantes ?? []).map((p) => (
                              <tr key={p.colaborador_id}>
                                <td className="px-2 py-1.5 text-zinc-200">{p.nome}</td>
                                <td className="px-2 py-1.5">
                                  {p.concluida_em ? (
                                    <span className="text-green-400">Concluiu a parte</span>
                                  ) : (
                                    <span className="text-sky-300">Em aberto</span>
                                  )}
                                </td>
                                <td className="px-2 py-1.5 text-zinc-400">
                                  {p.concluida_em
                                    ? `${dataHoraBr(p.concluida_em)}${p.concluida_por_nome ? ` por ${p.concluida_por_nome}` : ""}`
                                    : "—"}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </div>
                )}
                {detalhe && (
                  <div className="space-y-1">
                    <div className="text-zinc-300 font-medium">Histórico de reservas</div>
                    {(detalhe.reservas ?? []).length === 0 ? (
                      <div className="text-zinc-500">Esta tarefa nunca reservou um dia.</div>
                    ) : (
                      <div className="border border-zinc-800 rounded-lg overflow-x-auto">
                        <table className="w-full text-xs">
                          <thead className="bg-zinc-900/50">
                            <tr className="text-left">
                              <th className="px-2 py-1.5 border-b border-zinc-800 text-zinc-300">Dia</th>
                              <th className="px-2 py-1.5 border-b border-zinc-800 text-zinc-300">Colaborador</th>
                              <th className="px-2 py-1.5 border-b border-zinc-800 text-zinc-300">Reservado</th>
                              <th className="px-2 py-1.5 border-b border-zinc-800 text-zinc-300">Situação</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-zinc-800">
                            {(detalhe.reservas ?? []).map((r) => (
                              <tr key={r.id}>
                                <td className="px-2 py-1.5 text-zinc-200 whitespace-nowrap">{dataBr(r.data)}</td>
                                <td className="px-2 py-1.5 text-zinc-300">{r.colaborador_nome}</td>
                                <td className="px-2 py-1.5 text-zinc-400">
                                  {dataHoraBr(r.criado_em)}
                                  {r.criado_por_nome ? ` por ${r.criado_por_nome}` : ""}
                                </td>
                                <td className="px-2 py-1.5 text-zinc-400">
                                  {r.ativa ? (
                                    <span className="text-sky-300">Ativa</span>
                                  ) : (
                                    <>
                                      Liberada em {dataHoraBr(r.liberada_em)}
                                      {r.liberada_por_nome ? ` por ${r.liberada_por_nome}` : ""}
                                      {r.liberacao_motivo ? ` (${motivoLegivel(r.liberacao_motivo)})` : ""}
                                    </>
                                  )}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}

            <div className="border-t border-zinc-700 pt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={fecharModal}
                disabled={salvando}
                className="px-4 py-2 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm disabled:opacity-50"
              >
                {modal.tipo === "detalhe" || modal.tipo === "participantes" ? "Fechar" : "Voltar"}
              </button>
              {modal.tipo !== "detalhe" && (
                <button
                  type="button"
                  onClick={confirmarModal}
                  disabled={
                    salvando ||
                    ((modal.tipo === "nova" || modal.tipo === "trocar" || modal.tipo === "participantes") && carregandoColabs)
                  }
                  className="px-4 py-2 rounded bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm disabled:opacity-50"
                >
                  {salvando ? "Salvando..." : rotuloConfirmar(modal)}
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
