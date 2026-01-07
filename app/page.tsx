export default function HomePage() {
  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Sistema de Estoque e OS</h1>
      <p className="text-zinc-400">
        Gestao rapida para itens, estoque, movimentacoes e ordens de servico.
      </p>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
        <a href="/os" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Ordens de Servico</div>
          <div className="text-sm text-zinc-400 mt-1">Criar, adicionar itens e baixar estoque</div>
        </a>

        <a href="/execucao" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Execucao</div>
          <div className="text-sm text-zinc-400 mt-1">Acompanhar frentes eletrico/mecanico</div>
        </a>

        <a href="/projetos" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Projetos</div>
          <div className="text-sm text-zinc-400 mt-1">Planejar e distribuir itens de projeto</div>
        </a>

        <a href="/itens" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Itens</div>
          <div className="text-sm text-zinc-400 mt-1">Produtos, servicos e despesas</div>
        </a>

        <a href="/estoque" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Estoque</div>
          <div className="text-sm text-zinc-400 mt-1">Saldo atual por produto</div>
        </a>

        <a href="/estoque/importar" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Importar XML</div>
          <div className="text-sm text-zinc-400 mt-1">Importe NF-e (XML) para estoque</div>
        </a>

        <a href="/mov" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Movimentacoes</div>
          <div className="text-sm text-zinc-400 mt-1">Entradas/saidas/ajustes</div>
        </a>

        <a href="/colaboradores" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Colaboradores</div>
          <div className="text-sm text-zinc-400 mt-1">Cadastro e valor/hora</div>
        </a>

        <a href="/apontamentos" className="border border-zinc-800 rounded-xl p-4 hover:bg-zinc-900">
          <div className="font-medium">Apontamentos</div>
          <div className="text-sm text-zinc-400 mt-1">Apontamento de horas por OS</div>
        </a>
      </div>
    </div>
  );
}
