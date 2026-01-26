import Link from "next/link";

export default function ContasPagarPage() {
  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Contas a Pagar</h1>
          <p className="text-sm text-zinc-400 mt-1">Titulos a pagar, parcelas, vencimentos e baixas.</p>
        </div>
        <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
          Voltar
        </Link>
      </div>

      <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-4">
        <div className="text-lg font-semibold">Em construcao</div>
        <ul className="mt-3 list-disc list-inside text-sm text-zinc-200 space-y-1">
          <li>Lista de titulos (f.titulo) e parcelas (f.titulo_parcela)</li>
          <li>Filtros por vencimento, fornecedor, status e centro de custo</li>
          <li>Fluxo de pagamentos (f.pagamento) e baixas</li>
        </ul>
      </div>
    </div>
  );
}
