import NfeDetail from "../../../faturamento/nfe/components/NfeDetail";

export default async function EstoqueNfeImportadaDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <NfeDetail id={id} backHref="/estoque/importar" access="estoque" />;
}
