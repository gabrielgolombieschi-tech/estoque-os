import { Suspense } from "react";
import VendasClient from "./VendasClient";

export default function VendasPage() {
  return (
    <Suspense fallback={<div className="py-12 text-center text-zinc-400">Carregando vendas...</div>}>
      <VendasClient />
    </Suspense>
  );
}
