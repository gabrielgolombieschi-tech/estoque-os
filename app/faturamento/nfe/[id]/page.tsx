import NfeDetail from "../components/NfeDetail";

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function safeReturnHref(value: string | undefined) {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return "/faturamento/nfe";
  return value;
}

export default async function NfeDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  const query = await searchParams;
  return <NfeDetail id={id} backHref={safeReturnHref(first(query.retorno))} />;
}
