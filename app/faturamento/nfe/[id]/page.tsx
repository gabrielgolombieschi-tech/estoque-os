import NfeDetail from "../components/NfeDetail";

export default async function NfeDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <NfeDetail id={id} />;
}

