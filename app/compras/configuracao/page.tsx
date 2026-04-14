import CondicoesPagamentoManager from "@/components/configuracoes/CondicoesPagamentoManager";

export default function ComprasConfiguracaoPage() {
  return (
    <CondicoesPagamentoManager
      title="Configuração de Compras"
      subtitle="Cadastre e mantenha as formas de pagamento utilizadas no processo de compras."
      backHref="/compras/pedidos"
      backLabel="Voltar para Pedidos"
      entitySingular="forma de pagamento"
      entityPlural="formas de pagamento"
    />
  );
}
