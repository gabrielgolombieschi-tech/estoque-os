import NfseForm from "../components/NfseForm";

export default async function NfseEditPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <NfseForm mode="edit" id={id} />;
}

