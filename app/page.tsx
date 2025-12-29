export default function HomePage() {
  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Sistema de Estoque e OS</h1>
      <p className="text-zinc-400">
        Gestão rápida para itens, estoque, movimentações e ordens de serviço.
      </p>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <a href="/os" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Ordens de Serviço</div>
          <div className="text-sm text-zinc-400 mt-1">Criar, adicionar itens e baixar estoque</div>
        </a>

        <a href="/itens" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Itens</div>
          <div className="text-sm text-zinc-400 mt-1">Produtos, serviços e despesas</div>
        </a>

        <a href="/estoque" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Estoque</div>
          <div className="text-sm text-zinc-400 mt-1">Saldo atual por produto</div>
        </a>

        <a href="/mov" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Movimentações</div>
          <div className="text-sm text-zinc-400 mt-1">Entradas/saídas/ajustes</div>
        </a>
      </div>
    </div>
  );
}
