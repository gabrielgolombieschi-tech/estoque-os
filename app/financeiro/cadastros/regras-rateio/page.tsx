import { Suspense } from "react";
import RegrasRateioClient from "./RegrasRateioClient";

export default function Page() {
  return (
    <Suspense
      fallback={
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-6 text-sm text-zinc-400">
          Carregando regras de rateio…
        </div>
      }
    >
      <RegrasRateioClient />
    </Suspense>
  );
}
