import CondicoesPagamentoManager from "@/components/configuracoes/CondicoesPagamentoManager";

export default function CondicoesPagamentoPage() {
  return (
    <CondicoesPagamentoManager
      title="Condições de Pagamento"
      subtitle="Cadastro de condições usadas nos orçamentos da empresa."
      backHref="/configuracoes/comercial/orcamentos"
      backLabel="Voltar"
      entitySingular="condição"
      entityPlural="condições"
    />
  );
}
