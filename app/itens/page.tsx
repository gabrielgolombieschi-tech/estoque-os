import ItensClient from "./ItensClient";

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function safeReturnHref(value: string | undefined) {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return undefined;
  return value;
}

export default async function ItensPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const query = await searchParams;
  const rawId = first(query.id) ?? "";
  const initialItemId = /^\d+$/.test(rawId) ? rawId : "";
  const initialOpenFiscal = first(query.editar) === "1" && first(query.aba) === "fiscal";
  const returnHref = safeReturnHref(first(query.retorno));

  return <ItensClient initialItemId={initialItemId} initialOpenFiscal={initialOpenFiscal} returnHref={returnHref} />;
}
