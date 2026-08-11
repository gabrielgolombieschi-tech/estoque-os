import { Suspense } from "react";
import TransferenciasClient from "./TransferenciasClient";

export default function TransferenciasPage() {
  return (
    <Suspense fallback={<div className="text-sm text-zinc-400">Carregando transferências…</div>}>
      <TransferenciasClient />
    </Suspense>
  );
}
