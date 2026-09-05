import NfeList from "./components/NfeList";
import Link from "next/link";

export default function NfePage() {
  return <>
    <div className="mx-auto flex max-w-[1500px] justify-end gap-2 px-6 pt-4">
      <Link href="/faturamento/nfe/excecoes" className="rounded border border-amber-800 bg-amber-950/20 px-4 py-2 text-sm text-amber-100 hover:bg-amber-950/40">
        Exceções e rotinas mensais
      </Link>
      <Link href="/faturamento/operacoes" className="rounded border border-zinc-700 bg-zinc-900 px-4 py-2 text-sm text-zinc-100 hover:bg-zinc-800">
        Operações fora do faturamento
      </Link>
    </div>
    <NfeList />
  </>;
}
