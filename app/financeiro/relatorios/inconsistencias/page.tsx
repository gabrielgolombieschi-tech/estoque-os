import { Suspense } from "react";
import InconsistenciasFinanceirasClient from "./InconsistenciasFinanceirasClient";

export default function Page() {
  return (
    <Suspense
      fallback={
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-6 text-sm text-zinc-400">
          Carregando a central de inconsistências…
        </div>
      }
    >
      <InconsistenciasFinanceirasClient />
    </Suspense>
  );
}
