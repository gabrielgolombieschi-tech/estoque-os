import { Suspense } from "react";
import ComprasPedidosClient from "./pedidos-client";

export default function ComprasPedidosPage() {
  return (
    <Suspense fallback={<div className="py-12 text-center text-zinc-400">Carregando compras...</div>}>
      <ComprasPedidosClient />
    </Suspense>
  );
}
