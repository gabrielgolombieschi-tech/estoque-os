export type AcaoCicloFiscal =
  | "CANCELAR"
  | "TESTAR_CANCELAMENTO_FORA_PRAZO"
  | "CARTA_CORRECAO"
  | "EMAIL"
  | "INUTILIZAR"
  | "ARQUIVO";
export type AmbienteCicloFiscal = "HOMOLOGACAO" | "PRODUCAO";

export function validarAcaoCicloPorAmbiente(
  acao: AcaoCicloFiscal,
  ambiente: AmbienteCicloFiscal,
) {
  if (ambiente === "HOMOLOGACAO" && acao === "EMAIL") {
    throw new Error("Envio por e-mail exige NF-e AUTORIZADA em PRODUCAO com XML e DANFE arquivados.");
  }
  if (
    ambiente === "PRODUCAO"
    && (
      acao === "CANCELAR"
      || acao === "TESTAR_CANCELAMENTO_FORA_PRAZO"
      || acao === "CARTA_CORRECAO"
      || acao === "INUTILIZAR"
    )
  ) {
    throw new Error(
      `${acao === "CANCELAR" || acao === "TESTAR_CANCELAMENTO_FORA_PRAZO" ? "Cancelamento" : acao === "CARTA_CORRECAO" ? "Carta de correcao" : "Inutilizacao"} em PRODUCAO esta bloqueado antes da chamada ao provedor.`,
    );
  }
}
