import { Suspense } from "react";
import RequireCap from "@/components/auth/RequireCap";
import CadastroFiscalCliente from "./CadastroFiscalCliente";

export default function CadastroFiscalClientePage() {
  return (
    <RequireCap cap="cad_clientes.write">
      <Suspense fallback={<div className="text-sm text-zinc-400">Carregando cadastro fiscal...</div>}>
        <CadastroFiscalCliente />
      </Suspense>
    </RequireCap>
  );
}

