"use client";

import type {
  XmlImportAnalyzerResult,
  XmlImportAnalyzerSeverity,
  XmlImportDiagnostic,
  XmlImportPedidoSuggestion,
} from "@/lib/nfe/xmlImportAnalyzer";

type Props = {
  result: XmlImportAnalyzerResult | null;
  currentPedidoRef?: string | null;
  currentSolicitanteUsuarioId?: string | null;
  currentFinalidade?: string | null;
  currentMotivoId?: string | null;
  currentOsId?: number | null;
  hasManualPedidoItems?: boolean;
  onApplyPedidoSuggestion?: (pedidoRef: string) => void;
  onApplySolicitanteSuggestion?: (usuarioId: string) => void;
  onApplyOsSuggestion?: (osId: number, osNumero?: string | null, osLabel?: string | null) => void;
  onApplyFinalidadeSuggestion?: (finalidade: string) => void;
  onApplyMotivoSuggestion?: (motivoId: string) => void;
  onCopyDiagnostics?: () => void;
  onOpenPedidoItemLink?: (params: {
    xmlItemIndex: number;
    codigoOriginal: string;
    codigoNormalizado: string;
    descricao: string;
    pedidoId: string;
    pedidoCodigo?: string | null;
    pedidoItemId: string;
  }) => void;
};

type DiagnosticGroup = XmlImportDiagnostic & {
  count: number;
};

function severityTone(severity: XmlImportAnalyzerSeverity): BadgeTone {
  if (severity === "error") return "red";
  if (severity === "warning") return "amber";
  return "neutral";
}

function severityBlockClass(severity: XmlImportAnalyzerSeverity) {
  return `rounded-md border px-3 py-2.5 text-sm ${BADGE_TONE_CLASS[severityTone(severity)]}`;
}

function severityText(severity: XmlImportAnalyzerSeverity) {
  if (severity === "error") return "Erro";
  if (severity === "warning") return "Alerta";
  return "Info";
}

function statusTone(status: XmlImportAnalyzerResult["status"]): BadgeTone {
  if (status === "OK") return "emerald";
  if (status === "ATENCAO") return "amber";
  return "red";
}

function statusSummary(status: XmlImportAnalyzerResult["status"]) {
  if (status === "OK") return "Cenario consistente para importacao, revise antes de confirmar.";
  if (status === "ATENCAO") return "Ha pontos que precisam de conferencia antes de importar.";
  return "Existem pendencias obrigatorias antes da importacao.";
}

function fornecedorLabel(status: XmlImportAnalyzerResult["fornecedorSuggestion"]["status"]) {
  if (status === "IDENTIFICADO") return "Identificado";
  if (status === "NAO_ENCONTRADO") return "Nao encontrado";
  return "Sem CNPJ no XML";
}

function actionButtonClass() {
  return "rounded-md border border-zinc-700 bg-zinc-900 px-2.5 py-1.5 text-xs font-medium text-zinc-100 transition hover:bg-zinc-800";
}

type BadgeTone = "neutral" | "emerald" | "amber" | "red" | "sky" | "violet";

const BADGE_TONE_CLASS: Record<BadgeTone, string> = {
  neutral: "border-zinc-700 bg-zinc-900 text-zinc-300",
  emerald: "border-emerald-500/40 bg-emerald-500/10 text-emerald-200",
  amber: "border-amber-500/40 bg-amber-500/10 text-amber-200",
  red: "border-red-500/40 bg-red-500/10 text-red-200",
  sky: "border-sky-500/40 bg-sky-500/10 text-sky-200",
  violet: "border-violet-500/40 bg-violet-500/10 text-violet-200",
};

function badgeClass(tone: BadgeTone) {
  return `inline-flex items-center whitespace-nowrap rounded-full border px-2.5 py-1 text-xs font-medium ${BADGE_TONE_CLASS[tone]}`;
}

function sectionLabelClass() {
  return "text-[11px] font-medium uppercase tracking-[0.14em] text-zinc-500";
}

function subCardClass() {
  return "rounded-lg border border-zinc-800 bg-zinc-900/30 p-3.5";
}

function normalizeCompare(value: unknown) {
  return String(value ?? "").trim();
}

function splitRefs(value: unknown) {
  return String(value ?? "")
    .split(/[,;\n]+/)
    .map((ref) => normalizeCompare(ref))
    .filter(Boolean);
}

function payloadString(payload: Record<string, unknown> | undefined, key: string): string {
  const value = payload?.[key];
  return typeof value === "string" || typeof value === "number" ? String(value).trim() : "";
}

function payloadNumber(payload: Record<string, unknown> | undefined, key: string): number | null {
  const value = payload?.[key];
  const n = typeof value === "number" || typeof value === "string" ? Number(value) : NaN;
  return Number.isFinite(n) && n > 0 ? n : null;
}

function groupDiagnostics(items: XmlImportDiagnostic[]): DiagnosticGroup[] {
  const map = new Map<string, DiagnosticGroup>();

  for (const item of items) {
    const key = `${item.code}|${item.severity}|${item.message}`;
    const current = map.get(key);
    if (current) {
      current.count += 1;
      continue;
    }
    map.set(key, { ...item, count: 1 });
  }

  return Array.from(map.values());
}

function DiagnosticList({
  title,
  items,
  emptyText,
}: {
  title: string;
  items: XmlImportDiagnostic[];
  emptyText: string;
}) {
  const grouped = groupDiagnostics(items);

  return (
    <div className={subCardClass()}>
      <div className="flex items-center justify-between gap-2">
        <div className={sectionLabelClass()}>{title}</div>
        {grouped.length > 0 && <span className="text-xs text-zinc-500">{grouped.length}</span>}
      </div>
      {grouped.length === 0 ? (
        <div className="mt-2 text-sm text-zinc-500">{emptyText}</div>
      ) : (
        <div className="mt-2.5 space-y-2">
          {grouped.map((item) => (
            <div key={`${item.code}-${item.severity}-${item.message}`} className={severityBlockClass(item.severity)}>
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-xs font-semibold uppercase tracking-wide opacity-80">{severityText(item.severity)}</span>
                <span className="text-xs text-zinc-400">{item.code}</span>
                {item.count > 1 && <span className="text-xs text-zinc-400">({item.count} ocorrencias)</span>}
              </div>
              <div className="mt-1">{item.message}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function XmlImportAssistantPanel({
  result,
  currentFinalidade,
  currentMotivoId,
  currentOsId,
  hasManualPedidoItems,
  onApplyPedidoSuggestion,
  onApplySolicitanteSuggestion,
  onApplyOsSuggestion,
  onApplyFinalidadeSuggestion,
  onApplyMotivoSuggestion,
  onCopyDiagnostics,
  onOpenPedidoItemLink,
}: Props) {
  if (!result) return null;

  const fornecedor = result.fornecedorSuggestion;
  const pedido = result.pedidoSuggestion;
  const pedidos: XmlImportPedidoSuggestion[] = result.pedidoSuggestions?.length
    ? result.pedidoSuggestions
    : pedido
      ? [pedido]
      : [];
  const finalidadeSugerida = normalizeCompare(fornecedor.finalidadePadraoSugerida);
  const motivoSugerido = normalizeCompare(fornecedor.motivoPadraoSugeridoId);
  const finalidadeJaAplicada = Boolean(finalidadeSugerida) && finalidadeSugerida === normalizeCompare(currentFinalidade);
  const motivoJaAplicado = Boolean(motivoSugerido) && motivoSugerido === normalizeCompare(currentMotivoId);

  return (
    <div className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-[0_18px_50px_rgba(0,0,0,0.14)]">
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-zinc-800 px-4 py-3">
        <div>
          <div className="text-[11px] font-medium uppercase tracking-[0.18em] text-zinc-500">Assistente de importação</div>
          <div className="mt-1 text-sm text-zinc-300">{statusSummary(result.status)}</div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <span className={badgeClass("neutral")}>Score {result.score}/100</span>
          <span className={badgeClass(statusTone(result.status))}>
            {result.status === "ATENCAO" ? "ATENÇÃO" : result.status}
          </span>
          {onCopyDiagnostics && (
            <button
              type="button"
              onClick={onCopyDiagnostics}
              className={actionButtonClass()}
              title="Copia um diagnostico tecnico sem XML completo, tokens ou dados de pagamento."
            >
              Copiar diagnóstico
            </button>
          )}
        </div>
      </div>

      <div className="space-y-4 p-4">
      <div>
        <div className={subCardClass()}>
          <div className={sectionLabelClass()}>Fornecedor</div>
          <div className="mt-2.5 flex items-center gap-2 text-sm text-zinc-300">
            <span className={`h-1.5 w-1.5 rounded-full ${fornecedor.status === "IDENTIFICADO" ? "bg-emerald-400" : "bg-amber-400"}`} />
            <span>{fornecedorLabel(fornecedor.status)}</span>
          </div>
          {fornecedor.nome && (
            <div className="mt-1.5 text-sm text-zinc-300">
              <span className="text-zinc-500">Nome: </span>
              <span className="text-zinc-100">{fornecedor.nome}</span>
            </div>
          )}
          {fornecedor.cnpj && (
            <div className="mt-1 text-sm text-zinc-300">
              <span className="text-zinc-500">CNPJ: </span>
              <span>{fornecedor.cnpj}</span>
            </div>
          )}
          {fornecedor.finalidadePadraoSugerida && (
            <div className="mt-1 text-xs text-zinc-400">Finalidade padrão sugerida: {fornecedor.finalidadePadraoSugerida}</div>
          )}
          {fornecedor.motivoPadraoSugeridoId && (
            <div className="mt-1 text-xs text-zinc-400">Motivo padrão sugerido: {fornecedor.motivoPadraoSugeridoId}</div>
          )}
          {(finalidadeSugerida || motivoSugerido) && (
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {finalidadeSugerida && finalidadeJaAplicada && <span className="text-xs text-zinc-500">Finalidade já aplicada</span>}
              {finalidadeSugerida && !finalidadeJaAplicada && onApplyFinalidadeSuggestion && (
                <button
                  type="button"
                  onClick={() => onApplyFinalidadeSuggestion(finalidadeSugerida)}
                  className={actionButtonClass()}
                  title="Preenche a finalidade. Nao importa nem grava a nota."
                >
                  Usar finalidade sugerida
                </button>
              )}
              {motivoSugerido && motivoJaAplicado && <span className="text-xs text-zinc-500">Motivo já aplicado</span>}
              {motivoSugerido && !motivoJaAplicado && onApplyMotivoSuggestion && (
                <button
                  type="button"
                  onClick={() => onApplyMotivoSuggestion(motivoSugerido)}
                  className={actionButtonClass()}
                  title="Preenche o motivo/classificacao. Nao importa nem grava a nota."
                >
                  Usar motivo sugerido
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {result.actionPlan.length > 0 && (
        <div className={subCardClass()}>
          <div className={sectionLabelClass()}>Plano de ação recomendado</div>
          <div className="mt-2.5 space-y-2">
            {result.actionPlan.map((item) => {
              const pedidoRef = payloadString(item.payload, "pedidoRef");
              const usuarioId = payloadString(item.payload, "usuarioId");
              const osId = payloadNumber(item.payload, "osId");
              const osNumero = payloadString(item.payload, "osNumero") || null;
              const osLabel = payloadString(item.payload, "osLabel") || null;
              const osJaAplicada = Boolean(osId && currentOsId === osId);

              return (
                <div key={item.code} className={severityBlockClass(item.severity)}>
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-xs font-semibold uppercase tracking-wide opacity-80">{severityText(item.severity)}</span>
                        <span className="text-xs text-zinc-400">{item.code}</span>
                      </div>
                      <div className="mt-1">{item.message}</div>
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                      {item.actionType === "APPLY_PEDIDO" && pedidoRef && onApplyPedidoSuggestion && (
                        <button
                          type="button"
                          onClick={() => onApplyPedidoSuggestion(pedidoRef)}
                          className={actionButtonClass()}
                          title="Preenche o campo pedido. Nao vincula nem importa automaticamente."
                        >
                          Usar pedido
                        </button>
                      )}
                      {item.actionType === "APPLY_SOLICITANTE" && usuarioId && onApplySolicitanteSuggestion && (
                        <button
                          type="button"
                          onClick={() => onApplySolicitanteSuggestion(usuarioId)}
                          className={actionButtonClass()}
                          title="Preenche o solicitante. Nao importa nem grava a nota."
                        >
                          Usar solicitante
                        </button>
                      )}
                      {item.actionType === "APPLY_OS" &&
                        osId &&
                        (osJaAplicada ? (
                          <span className="text-xs text-zinc-500">OS já aplicada</span>
                        ) : (
                          onApplyOsSuggestion && (
                            <button
                              type="button"
                              onClick={() => onApplyOsSuggestion(osId, osNumero, osLabel)}
                              className={actionButtonClass()}
                              title="Preenche a OS. Nao importa nem grava a nota."
                            >
                              Usar OS
                            </button>
                          )
                        ))}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div className="grid gap-3 lg:grid-cols-3">
        <DiagnosticList title="Pendências" items={result.findings} emptyText="Nenhuma pendência objetiva encontrada." />
        <DiagnosticList title="Alertas" items={result.warnings} emptyText="Nenhum alerta relevante encontrado." />
        <DiagnosticList title="Sugestões" items={result.suggestions} emptyText="Nenhuma sugestão local gerada." />
      </div>

      <div className="overflow-hidden rounded-lg border border-zinc-800">
        <div className={`${sectionLabelClass()} border-b border-zinc-800 bg-zinc-900/40 px-3.5 py-2.5`}>Itens analisados</div>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="whitespace-nowrap px-3 py-2 text-left text-[10px] font-medium uppercase tracking-[0.1em]">Código XML</th>
                <th className="whitespace-nowrap px-3 py-2 text-left text-[10px] font-medium uppercase tracking-[0.1em]">Código normalizado</th>
                <th className="px-3 py-2 text-left text-[10px] font-medium uppercase tracking-[0.1em]">Descrição</th>
                <th className="whitespace-nowrap px-3 py-2 text-left text-[10px] font-medium uppercase tracking-[0.1em]">Status</th>
                <th className="whitespace-nowrap px-3 py-2 text-left text-[10px] font-medium uppercase tracking-[0.1em]">Severidade</th>
                <th className="px-3 py-2 text-left text-[10px] font-medium uppercase tracking-[0.1em]">Ação recomendada</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {result.itemSuggestions.map((item) => {
                const fallbackPedido = pedidos.length === 1 ? pedidos[0] : null;
                const linkPedidoId = item.pedidoMatchPedidoId ?? fallbackPedido?.pedidoId ?? null;
                const linkPedidoCodigo = item.pedidoMatchPedidoCodigo ?? fallbackPedido?.codigo ?? null;
                const linkPedidoItemId = item.pedidoMatchItemId ?? "";
                const hasSpecificManualMatch = item.pedidoMatchTipo === "DESCRICAO_MANUAL" && Boolean(linkPedidoItemId);
                const canChooseManualPedidoItem = item.status === "CADASTRADO" && hasManualPedidoItems && !item.pedidoMatchItemId;
                const canOpenManualLink = Boolean(
                  onOpenPedidoItemLink &&
                    linkPedidoId &&
                    (hasSpecificManualMatch || canChooseManualPedidoItem)
                );

                return (
                  <tr key={`${item.index}-${item.codigoOriginal}`} className="hover:bg-zinc-900/40">
                    <td className="whitespace-nowrap px-3 py-2 font-mono text-zinc-200">{item.codigoOriginal || "-"}</td>
                    <td className="whitespace-nowrap px-3 py-2 font-mono text-zinc-400">{item.codigoNormalizado || "-"}</td>
                    <td className="px-3 py-2 text-zinc-300">{item.descricao || "-"}</td>
                    <td className="whitespace-nowrap px-3 py-2">
                      <span className={badgeClass(item.status === "CADASTRADO" ? "emerald" : "amber")}>
                        {item.status === "CADASTRADO" ? "Cadastrado" : "Não cadastrado"}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-zinc-300">{severityText(item.severity)}</td>
                    <td className="px-3 py-2 text-zinc-300">
                      <div className="space-y-1">
                        {item.recommendedAction && <div>{item.recommendedAction}</div>}
                        {item.pedidoMatchDescricao && <div className="text-zinc-500">Pedido: {item.pedidoMatchDescricao}</div>}
                        {item.pedidoMatchOsLabel && <div className="text-zinc-500">{item.pedidoMatchOsLabel}</div>}
                        {canOpenManualLink && (
                          <button
                            type="button"
                            onClick={() =>
                              onOpenPedidoItemLink?.({
                                xmlItemIndex: item.index,
                                codigoOriginal: item.codigoOriginal,
                                codigoNormalizado: item.codigoNormalizado,
                                descricao: item.descricao,
                                pedidoId: linkPedidoId ?? "",
                                pedidoCodigo: linkPedidoCodigo,
                                pedidoItemId: linkPedidoItemId,
                              })
                            }
                            className={actionButtonClass()}
                            title="Abre a confirmacao para vincular este item a um item manual do pedido."
                          >
                            {item.status === "CADASTRADO" ? "Vincular ao pedido" : "Cadastrar e vincular"}
                          </button>
                        )}
                        {!item.recommendedAction && !item.pedidoMatchDescricao && !item.pedidoMatchOsLabel && !canOpenManualLink && "-"}
                      </div>
                    </td>
                  </tr>
                );
              })}
              {result.itemSuggestions.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-3 py-4 text-center text-zinc-500">
                    Nenhum item analisado.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
      </div>
    </div>
  );
}

export function XmlImportPedidoSuggestionCard({
  result,
  currentPedidoRef,
  currentSolicitanteUsuarioId,
  hasManualPedidoItems,
  onApplyPedidoSuggestion,
  onApplySolicitanteSuggestion,
}: Pick<
  Props,
  | "result"
  | "currentPedidoRef"
  | "currentSolicitanteUsuarioId"
  | "hasManualPedidoItems"
  | "onApplyPedidoSuggestion"
  | "onApplySolicitanteSuggestion"
>) {
  if (!result) return null;

  const pedido = result.pedidoSuggestion;
  const pedidos: XmlImportPedidoSuggestion[] = result.pedidoSuggestions?.length
    ? result.pedidoSuggestions
    : pedido
      ? [pedido]
      : [];
  const pedidoRefSugerido = pedidos.map((row) => normalizeCompare(row.codigo ?? row.pedidoId)).filter(Boolean).join(", ");
  const solicitantesSugeridos = Array.from(
    new Set(pedidos.map((row) => normalizeCompare(row.solicitanteUsuarioId)).filter(Boolean))
  );
  const solicitanteSugerido = solicitantesSugeridos.length === 1 ? solicitantesSugeridos[0] : "";
  const currentPedidoRefs = new Set(splitRefs(currentPedidoRef));
  const getPedidoRef = (row: XmlImportPedidoSuggestion) => normalizeCompare(row.codigo ?? row.pedidoId);
  const isPedidoAtual = (row: XmlImportPedidoSuggestion) =>
    [normalizeCompare(row.codigo), normalizeCompare(row.pedidoId)].filter(Boolean).some((ref) => currentPedidoRefs.has(ref));
  const pedidoJaAplicado =
    pedidos.length > 0 &&
    pedidos.every((row) =>
      [normalizeCompare(row.codigo), normalizeCompare(row.pedidoId)].filter(Boolean).some((ref) => currentPedidoRefs.has(ref))
    );
  const solicitanteJaAplicado = Boolean(solicitanteSugerido) && solicitanteSugerido === normalizeCompare(currentSolicitanteUsuarioId);
  const pedidoMatchedCount = pedidos.reduce((sum, row) => sum + row.itemMatches.length, 0);
  const pedidoDivergencias = pedidos.flatMap((row) => row.divergencias);
  const pedidoDivergenciasCount = pedidoDivergencias.length;
  const pedidoHasParcial = Boolean(
    pedidos.some((row) => row.itemMatches.some((item) => item.quantityStatus === "PARCIAL")) ||
      pedidoDivergencias.some((item) => item.code === "QUANTIDADE_PARCIAL_PEDIDO")
  );
  const pedidoHasExcesso = Boolean(
    pedidos.some((row) => row.itemMatches.some((item) => item.quantityStatus === "EXCESSO")) ||
      pedidoDivergencias.some((item) => item.code === "QUANTIDADE_EXCEDE_PEDIDO")
  );
  const pedidoHasValorDivergente = Boolean(pedidoDivergencias.some((item) => item.code === "DIVERGENCIA_VALOR_UNITARIO"));
  const pedidoHasItensManuais = Boolean(
    pedidos.some((row) => row.itemMatches.some((item) => item.manualItem)) ||
      pedidoDivergencias.some((item) => item.code === "PEDIDO_COM_ITENS_MANUAIS") ||
      hasManualPedidoItems
  );
  const pedidoMotivos = Array.from(new Set(pedidos.flatMap((row) => row.motivos)));
  const scoreLabel =
    pedidos.length === 1
      ? `Score ${pedidos[0]?.score}/100`
      : pedidos.length > 1
        ? `Score médio ${Math.round(pedidos.reduce((sum, row) => sum + row.score, 0) / pedidos.length)}/100`
        : null;

  return (
    <div className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-[0_18px_50px_rgba(0,0,0,0.14)]">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-zinc-800 px-4 py-3">
        <div className="text-[11px] font-medium uppercase tracking-[0.18em] text-zinc-500">
          {pedidos.length > 1 ? "Pedidos sugeridos" : "Pedido sugerido"}
        </div>
        {scoreLabel && <span className={badgeClass("neutral")}>{scoreLabel}</span>}
      </div>

      <div className="p-4">
        {pedidos.length > 0 ? (
          <div className="space-y-3 text-sm text-zinc-300">
            {pedidos.length === 1 ? (
              <div>
                <span className="text-zinc-500">Pedido: </span>
                <span className="font-medium text-zinc-100">{pedidos[0]?.codigo ?? pedidos[0]?.pedidoId}</span>
              </div>
            ) : (
              <div className="space-y-1.5">
                {pedidos.map((row) => (
                  <div key={row.pedidoId} className="flex flex-wrap items-center gap-2 text-xs text-zinc-300">
                    <span className="font-medium text-zinc-100">{row.codigo ?? row.pedidoId}</span>
                    <span className="text-zinc-500">Score {row.score}/100</span>
                    <span className="text-zinc-500">
                      {row.itemMatches.length} item{row.itemMatches.length === 1 ? "" : "s"}
                    </span>
                    {row.divergencias.length > 0 && (
                      <span className={row.divergencias.some((item) => item.severity !== "info") ? "text-amber-300" : "text-sky-300"}>
                        {row.divergencias.length} ocorrência{row.divergencias.length === 1 ? "" : "s"}
                      </span>
                    )}
                    {isPedidoAtual(row) ? (
                      <span className="text-zinc-500">Selecionado</span>
                    ) : (
                      onApplyPedidoSuggestion && (
                        <button
                          type="button"
                          onClick={() => onApplyPedidoSuggestion(getPedidoRef(row))}
                          className={actionButtonClass()}
                          title="Preenche apenas este pedido no campo. Nao vincula nem importa automaticamente."
                        >
                          Usar pedido
                        </button>
                      )
                    )}
                  </div>
                ))}
              </div>
            )}

            <div className="flex flex-wrap items-center gap-2">
              {pedidoJaAplicado ? (
                <span className="text-xs text-zinc-500">{pedidos.length > 1 ? "Pedidos já aplicados" : "Pedido já aplicado"}</span>
              ) : (
                pedidoRefSugerido &&
                onApplyPedidoSuggestion && (
                  <button
                    type="button"
                    onClick={() => onApplyPedidoSuggestion(pedidoRefSugerido)}
                    className={actionButtonClass()}
                    title="Preenche o campo pedido. Nao vincula nem importa automaticamente."
                  >
                    {pedidos.length > 1 ? "Usar todos sugeridos" : "Usar pedido sugerido"}
                  </button>
                )
              )}
              {solicitanteJaAplicado ? (
                <span className="text-xs text-zinc-500">Solicitante já aplicado</span>
              ) : (
                solicitanteSugerido &&
                onApplySolicitanteSuggestion && (
                  <button
                    type="button"
                    onClick={() => onApplySolicitanteSuggestion(solicitanteSugerido)}
                    className={actionButtonClass()}
                    title="Preenche o solicitante. Nao importa nem grava a nota."
                  >
                    {pedidos.length > 1 ? "Usar solicitante dos pedidos" : "Usar solicitante do pedido"}
                  </button>
                )
              )}
            </div>

            <div className="flex flex-wrap gap-2">
              <span className={badgeClass("neutral")}>
                {pedidoMatchedCount} item{pedidoMatchedCount === 1 ? "" : "s"} combinado{pedidoMatchedCount === 1 ? "" : "s"}
              </span>
              <span className={badgeClass("neutral")}>
                {pedidoDivergenciasCount} ocorrência{pedidoDivergenciasCount === 1 ? "" : "s"}
              </span>
              {pedidoHasParcial && <span className={badgeClass("sky")}>Quantidade parcial</span>}
              {pedidoHasExcesso && <span className={badgeClass("red")}>Quantidade em excesso</span>}
              {pedidoHasValorDivergente && <span className={badgeClass("amber")}>Valor divergente</span>}
              {pedidoHasItensManuais && <span className={badgeClass("violet")}>Itens manuais no pedido</span>}
            </div>

            {pedidoMotivos.length > 0 && (
              <div className="space-y-1.5 border-t border-zinc-800/80 pt-3">
                {pedidoMotivos.map((motivo) => (
                  <div key={motivo} className="flex items-start gap-2 text-xs text-zinc-400">
                    <span className="mt-1 h-1 w-1 shrink-0 rounded-full bg-zinc-600" />
                    <span>{motivo}</span>
                  </div>
                ))}
              </div>
            )}

            {pedidoDivergencias.length > 0 && (
              <div className="space-y-1.5 border-t border-zinc-800/80 pt-3">
                {groupDiagnostics(pedidoDivergencias).map((item) => (
                  <div
                    key={`${item.code}-${item.message}`}
                    className={`flex items-start gap-2 text-xs ${item.severity === "info" ? "text-sky-300" : "text-amber-300"}`}
                  >
                    <span className={`mt-1 h-1 w-1 shrink-0 rounded-full ${item.severity === "info" ? "bg-sky-400" : "bg-amber-400"}`} />
                    <span>
                      {item.message}
                      {item.count > 1 ? ` (${item.count} ocorrências)` : ""}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        ) : (
          <div className="text-sm text-zinc-500">Nenhum pedido sugerido com os dados disponíveis.</div>
        )}
      </div>
    </div>
  );
}
