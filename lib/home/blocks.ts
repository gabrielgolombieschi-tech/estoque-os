import type { CapabilityKey } from "@/lib/auth/capabilities";

export type HomeBlockId =
  | "os_em_andamento"
  | "horas_proprias"
  | "caixa"
  | "estoque_baixo"
  | "horas_equipe"
  | "posicao_liquida"
  | "movimentacoes_hoje"
  | "dias_regulares"
  | "os_proprias";

export type VitalBlockDefinition = {
  id: HomeBlockId;
  slot: 1 | 2 | 3 | 4;
  priority: number;
  permission?: CapabilityKey;
  title: string;
  href: string;
  tone: "neutral" | "blue" | "amber" | "green";
};

export const VITAL_BLOCKS: readonly VitalBlockDefinition[] = [
  { id: "os_em_andamento", slot: 1, priority: 1, permission: "os.read", title: "OS em andamento", href: "/os", tone: "blue" },
  { id: "horas_proprias", slot: 2, priority: 1, title: "Suas horas no mês", href: "/apontamentos", tone: "neutral" },

  { id: "caixa", slot: 3, priority: 1, permission: "financeiro.read", title: "Caixa hoje", href: "/financeiro", tone: "green" },
  { id: "estoque_baixo", slot: 3, priority: 2, permission: "estoque.read", title: "Estoque abaixo do mínimo", href: "/estoque/relatorios?tab=saldo&a_abaixo_minimo=1", tone: "amber" },
  { id: "horas_equipe", slot: 3, priority: 3, permission: "apontamentos.read", title: "Horas da equipe", href: "/apontamentos/resumo-mensal", tone: "neutral" },
  { id: "dias_regulares", slot: 3, priority: 99, title: "Dias com apontamento", href: "/apontamentos", tone: "neutral" },

  { id: "posicao_liquida", slot: 4, priority: 1, permission: "financeiro.read", title: "A receber − a pagar", href: "/financeiro/contas_pagar_receber", tone: "neutral" },
  { id: "horas_equipe", slot: 4, priority: 2, permission: "apontamentos.read", title: "Horas da equipe", href: "/apontamentos/resumo-mensal", tone: "neutral" },
  { id: "movimentacoes_hoje", slot: 4, priority: 3, permission: "estoque.read", title: "Movimentações hoje", href: "/mov", tone: "neutral" },
  { id: "os_proprias", slot: 4, priority: 99, title: "OS sob sua atuação", href: "/os", tone: "neutral" },
] as const;

export type HomeShortcutDefinition = {
  id: string;
  title: string;
  description: string;
  href: string;
  icon: "os" | "clock" | "execution" | "stock" | "move" | "finance" | "credit" | "billing" | "purchase";
  permission?: CapabilityKey;
};

export const HOME_SHORTCUTS: readonly HomeShortcutDefinition[] = [
  { id: "os", title: "Ordens de Serviço", description: "Abrir carteira operacional", href: "/os", icon: "os", permission: "os.read" },
  { id: "apontamentos", title: "Lançar horas", description: "Registrar seu apontamento", href: "/apontamentos", icon: "clock" },
  { id: "execucao", title: "Execução", description: "Acompanhar frentes da OS", href: "/execucao", icon: "execution", permission: "os.read" },
  { id: "estoque", title: "Estoque", description: "Consultar saldos e mínimos", href: "/estoque", icon: "stock", permission: "estoque.read" },
  { id: "movimentacoes", title: "Movimentações", description: "Entradas, saídas e ajustes", href: "/mov", icon: "move", permission: "estoque.read" },
  { id: "compras", title: "Compras", description: "Pedidos e pendências", href: "/compras/pedidos", icon: "purchase", permission: "compras.read" },
  { id: "financeiro", title: "Financeiro", description: "Contas a pagar e receber", href: "/financeiro/contas_pagar_receber", icon: "finance", permission: "financeiro.read" },
  { id: "credito", title: "Venda a Crédito", description: "Exposição antes da nota", href: "/financeiro/venda-a-credito", icon: "credit", permission: "financeiro.read" },
  { id: "faturamento", title: "Faturamento", description: "Notas e OS a faturar", href: "/faturamento/nfe", icon: "billing", permission: "faturamento.read" },
] as const;

export function selectVitalBlocks(has: (permission: CapabilityKey) => boolean) {
  const selected: VitalBlockDefinition[] = [];
  const used = new Set<HomeBlockId>();

  for (const slot of [1, 2, 3, 4] as const) {
    const candidate = VITAL_BLOCKS
      .filter((block) => block.slot === slot)
      .sort((a, b) => a.priority - b.priority)
      .find((block) => !used.has(block.id) && (!block.permission || has(block.permission)));

    if (candidate) {
      selected.push(candidate);
      used.add(candidate.id);
    }
  }

  return selected;
}

