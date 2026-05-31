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

function severityClass(severity: XmlImportAnalyzerSeverity) {
  if (severity === "error") return "border-red-500/40 bg-red-500/10 text-red-200";
  if (severity === "warning") return "border-amber-500/40 bg-amber-500/10 text-amber-200";
  return "border-zinc-700 bg-zinc-900/80 text-zinc-200";
}

function severityText(severity: XmlImportAnalyzerSeverity) {
  if (severity === "error") return "Erro";
  if (severity === "warning") return "Alerta";
  return "Info";
}

function statusClass(status: XmlImportAnalyzerResult["status"]) {
  if (status === "OK") return "border-emerald-500/40 bg-emerald-500/10 text-emerald-200";
  if (status === "ATENCAO") return "border-amber-500/40 bg-amber-500/10 text-amber-200";
  return "border-red-500/40 bg-red-500/10 text-red-200";
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
  return "rounded-md border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-zinc-100 hover:bg-zinc-800";
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
    <div className="rounded-lg border border-zinc-800 bg-zinc-950/70 p-3">
      <div className="text-sm font-semibold text-zinc-100">{title}</div>
      {grouped.length === 0 ? (
        <div className="mt-2 text-sm text-zinc-500">{emptyText}</div>
      ) : (
        <div className="mt-2 space-y-2">
          {grouped.map((item) => (
            <div key={`${item.code}-${item.severity}-${item.message}`} className={`rounded-md border px-3 py-2 text-sm ${severityClass(item.severity)}`}>
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-xs uppercase tracking-wide opacity-80">{severityText(item.severity)}</span>
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
  currentPedidoRef,
  currentSolicitanteUsuarioId,
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
  const pedidoRefSugerido = pedidos.map((row) => normalizeCompare(row.codigo ?? row.pedidoId)).filter(Boolean).join(", ");
  const solicitantesSugeridos = Array.from(
    new Set(pedidos.map((row) => normalizeCompare(row.solicitanteUsuarioId)).filter(Boolean))
  );
  const solicitanteSugerido = solicitantesSugeridos.length === 1 ? solicitantesSugeridos[0] : "";
  const finalidadeJaAplicada = Boolean(finalidadeSugerida) && finalidadeSugerida === normalizeCompare(currentFinalidade);
  const motivoJaAplicado = Boolean(motivoSugerido) && motivoSugerido === normalizeCompare(currentMotivoId);
  const currentPedidoRefs = new Set(splitRefs(currentPedidoRef));
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

  return (
    <div className="border border-zinc-800 rounded-lg p-3 space-y-3 bg-zinc-950">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="text-sm font-semibold text-zinc-100">Assistente de importacao</div>
          <div className="text-xs text-zinc-500">Diagnostico local informativo. Nenhuma sugestao e aplicada automaticamente.</div>
          <div className="mt-1 text-xs text-zinc-400">{statusSummary(result.status)}</div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
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
          <span className={`rounded-md border px-2 py-1 text-xs font-medium ${statusClass(result.status)}`}>
            {result.status === "ATENCAO" ? "ATENCAO" : result.status}
          </span>
          <span className="rounded-md border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-zinc-200">
            Score {result.score}/100
          </span>
        </div>
      </div>

      <div className="grid gap-3 lg:grid-cols-2">
        <div className="rounded-lg border border-zinc-800 bg-zinc-950/70 p-3">
          <div className="text-sm font-semibold text-zinc-100">Fornecedor</div>
          <div className="mt-2 text-sm text-zinc-300">
            <span className="text-zinc-500">Status: </span>
            <span>{fornecedorLabel(fornecedor.status)}</span>
          </div>
          {fornecedor.nome && (
            <div className="mt-1 text-sm text-zinc-300">
              <span className="text-zinc-500">Nome: </span>
              <span>{fornecedor.nome}</span>
            </div>
          )}
          {fornecedor.cnpj && (
            <div className="mt-1 text-sm text-zinc-300">
              <span className="text-zinc-500">CNPJ: </span>
              <span>{fornecedor.cnpj}</span>
            </div>
          )}
          {fornecedor.finalidadePadraoSugerida && (
            <div className="mt-1 text-xs text-zinc-400">Finalidade padrao sugerida: {fornecedor.finalidadePadraoSugerida}</div>
          )}
          {fornecedor.motivoPadraoSugeridoId && (
            <div className="mt-1 text-xs text-zinc-400">Motivo padrao sugerido: {fornecedor.motivoPadraoSugeridoId}</div>
          )}
          {(finalidadeSugerida || motivoSugerido) && (
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {finalidadeSugerida && finalidadeJaAplicada && <span className="text-xs text-zinc-500">Finalidade ja aplicada</span>}
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
              {motivoSugerido && motivoJaAplicado && <span className="text-xs text-zinc-500">Motivo ja aplicado</span>}
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

        <div className="rounded-lg border border-zinc-800 bg-zinc-950/70 p-3">
          <div className="text-sm font-semibold text-zinc-100">{pedidos.length > 1 ? "Pedidos sugeridos" : "Pedido sugerido"}</div>
          {pedidos.length > 0 ? (
            <div className="mt-2 space-y-2 text-sm text-zinc-300">
              {pedidos.length === 1 ? (
                <>
                  <div>
                    <span className="text-zinc-500">Pedido: </span>
                    <span>{pedidos[0]?.codigo ?? pedidos[0]?.pedidoId}</span>
                  </div>
                  <div>
                    <span className="text-zinc-500">Score: </span>
                    <span>{pedidos[0]?.score}/100</span>
                  </div>
                </>
              ) : (
                <div className="space-y-1">
                  {pedidos.map((row) => (
                    <div key={row.pedidoId} className="flex flex-wrap items-center gap-2 text-xs text-zinc-300">
                      <span className="font-medium text-zinc-100">{row.codigo ?? row.pedidoId}</span>
                      <span className="text-zinc-500">Score {row.score}/100</span>
                      <span className="text-zinc-500">
                        {row.itemMatches.length} item{row.itemMatches.length === 1 ? "" : "s"}
                      </span>
                      {row.divergencias.length > 0 && (
                        <span className="text-amber-300">
                          {row.divergencias.length} divergencia{row.divergencias.length === 1 ? "" : "s"}
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              )}
              <div className="flex flex-wrap items-center gap-2">
                {pedidoJaAplicado ? (
                  <span className="text-xs text-zinc-500">{pedidos.length > 1 ? "Pedidos ja aplicados" : "Pedido ja aplicado"}</span>
                ) : (
                  pedidoRefSugerido &&
                  onApplyPedidoSuggestion && (
                    <button
                      type="button"
                      onClick={() => onApplyPedidoSuggestion(pedidoRefSugerido)}
                      className={actionButtonClass()}
                      title="Preenche o campo pedido. Nao vincula nem importa automaticamente."
                    >
                      {pedidos.length > 1 ? "Usar pedidos sugeridos" : "Usar pedido sugerido"}
                    </button>
                  )
                )}
                {solicitanteJaAplicado ? (
                  <span className="text-xs text-zinc-500">Solicitante ja aplicado</span>
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
                <span className="rounded-md border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-zinc-300">
                  {pedidoMatchedCount} item{pedidoMatchedCount === 1 ? "" : "s"} combinado{pedidoMatchedCount === 1 ? "" : "s"}
                </span>
                <span className="rounded-md border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-zinc-300">
                  {pedidoDivergenciasCount} divergencia{pedidoDivergenciasCount === 1 ? "" : "s"}
                </span>
                {pedidoHasParcial && (
                  <span className="rounded-md border border-sky-500/40 bg-sky-500/10 px-2 py-1 text-xs text-sky-200">
                    Quantidade parcial
                  </span>
                )}
                {pedidoHasExcesso && (
                  <span className="rounded-md border border-red-500/40 bg-red-500/10 px-2 py-1 text-xs text-red-200">
                    Quantidade em excesso
                  </span>
                )}
                {pedidoHasValorDivergente && (
                  <span className="rounded-md border border-amber-500/40 bg-amber-500/10 px-2 py-1 text-xs text-amber-200">
                    Valor divergente
                  </span>
                )}
                {pedidoHasItensManuais && (
                  <span className="rounded-md border border-violet-500/40 bg-violet-500/10 px-2 py-1 text-xs text-violet-200">
                    Itens manuais no pedido
                  </span>
                )}
              </div>
              {pedidoMotivos.length > 0 && (
                <div className="space-y-1">
                  {pedidoMotivos.map((motivo) => (
                    <div key={motivo} className="text-xs text-zinc-400">
                      {motivo}
                    </div>
                  ))}
                </div>
              )}
              {pedidoDivergencias.length > 0 && (
                <div className="space-y-1">
                  {groupDiagnostics(pedidoDivergencias).map((item) => (
                    <div key={`${item.code}-${item.message}`} className="text-xs text-amber-300">
                      {item.message}
                      {item.count > 1 ? ` (${item.count} ocorrencias)` : ""}
                    </div>
                  ))}
                </div>
              )}
            </div>
          ) : (
            <div className="mt-2 text-sm text-zinc-500">Nenhum pedido sugerido com os dados disponiveis.</div>
          )}
        </div>
      </div>

      {result.actionPlan.length > 0 && (
        <div className="rounded-lg border border-zinc-800 bg-zinc-950/70 p-3">
          <div className="text-sm font-semibold text-zinc-100">Plano de acao recomendado</div>
          <div className="mt-2 space-y-2">
            {result.actionPlan.map((item) => {
              const pedidoRef = payloadString(item.payload, "pedidoRef");
              const usuarioId = payloadString(item.payload, "usuarioId");
              const osId = payloadNumber(item.payload, "osId");
              const osNumero = payloadString(item.payload, "osNumero") || null;
              const osLabel = payloadString(item.payload, "osLabel") || null;
              const osJaAplicada = Boolean(osId && currentOsId === osId);

              return (
                <div key={item.code} className={`rounded-md border px-3 py-2 text-sm ${severityClass(item.severity)}`}>
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-xs uppercase tracking-wide opacity-80">{severityText(item.severity)}</span>
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
                          <span className="text-xs text-zinc-500">OS ja aplicada</span>
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
        <DiagnosticList title="Pendencias" items={result.findings} emptyText="Nenhuma pendencia objetiva encontrada." />
        <DiagnosticList title="Alertas" items={result.warnings} emptyText="Nenhum alerta relevante encontrado." />
        <DiagnosticList title="Sugestoes" items={result.suggestions} emptyText="Nenhuma sugestao local gerada." />
      </div>

      <div className="rounded-lg border border-zinc-800 overflow-hidden">
        <div className="bg-zinc-900/70 px-3 py-2 text-sm font-semibold text-zinc-100">Itens analisados</div>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead className="bg-zinc-900/60 text-zinc-300">
              <tr>
                <th className="px-3 py-2 text-left">Codigo XML</th>
                <th className="px-3 py-2 text-left">Codigo normalizado</th>
                <th className="px-3 py-2 text-left">Descricao</th>
                <th className="px-3 py-2 text-left">Status</th>
                <th className="px-3 py-2 text-left">Severidade</th>
                <th className="px-3 py-2 text-left">Acao recomendada</th>
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
                    <td className="px-3 py-2 text-zinc-200">{item.codigoOriginal || "-"}</td>
                    <td className="px-3 py-2 text-zinc-300">{item.codigoNormalizado || "-"}</td>
                    <td className="px-3 py-2 text-zinc-300">{item.descricao || "-"}</td>
                    <td className="px-3 py-2">
                      <span
                        className={
                          item.status === "CADASTRADO"
                            ? "rounded-md border border-emerald-500/40 px-2 py-1 text-emerald-300"
                            : "rounded-md border border-amber-500/40 px-2 py-1 text-amber-300"
                        }
                      >
                        {item.status === "CADASTRADO" ? "Cadastrado" : "Nao cadastrado"}
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
  );
}
