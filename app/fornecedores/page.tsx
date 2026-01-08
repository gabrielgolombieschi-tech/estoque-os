"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";

type Fornecedor = {
  id: number;
  nome: string;
  documento: string | null;
  email: string | null;
  telefone: string | null;
  endereco: string | null;
  observacoes: string | null;
  ativo: boolean;
};

export default function FornecedoresPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);

  const [rows, setRows] = useState<Fornecedor[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [nome, setNome] = useState("");
  const [documento, setDocumento] = useState("");

  const normalizeDocumento = (doc: string) => doc.replace(/\D/g, "").trim();

  async function load() {
    setErr(null);

    const { data, error } = await supabase
      .from("fornecedores")
      .select("id,nome,documento,email,telefone,endereco,observacoes,ativo")
      .order("id", { ascending: false });

    if (error) setErr(error.message);
    else setRows((data ?? []) as unknown as Fornecedor[]);
  }

  async function criar() {
    if (!nome.trim()) {
      setErr("Informe o nome do fornecedor.");
      return;
    }

    setBusy(true);
    setErr(null);

    const documentoNormalizado = normalizeDocumento(documento);
    const payload: any = {
      nome: nome.trim(),
      documento: documentoNormalizado || null,
      ativo: true,
    };

    const { error } = await supabase
      .from("fornecedores")
      .upsert(payload, { onConflict: "documento" });

    setBusy(false);

    if (error) {
      if ((error as any).code === "23505") {
        setErr("Fornecedor ja cadastrado para este documento.");
      } else {
        setErr(error.message);
      }
      return;
    }

    setNome("");
    setDocumento("");
    await load();
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <main className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Fornecedores</h1>
        <p className="text-sm text-zinc-400 mt-1">
          Cadastro básico de fornecedores
        </p>
      </div>

      {err && <div className="text-red-400 text-sm">{err}</div>}

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 flex gap-2">
        <input
          className="flex-1 px-3 py-2"
          placeholder="Nome do fornecedor"
          value={nome}
          onChange={(e) => setNome(e.target.value)}
        />
        <input
          className="w-56 px-3 py-2"
          placeholder="Documento (CNPJ/CPF)"
          value={documento}
          onChange={(e) => setDocumento(e.target.value)}
        />
        <button
          onClick={criar}
          disabled={busy}
          className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white"
        >
          {busy ? "Salvando..." : "Adicionar"}
        </button>
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Nome</th>
              <th className="px-4 py-3 text-center">Ativo</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="px-4 py-3">{r.nome}</td>
                <td className="px-4 py-3 text-center">
                  {r.ativo ? "✅" : "—"}
                </td>
              </tr>
            ))}

            {rows.length === 0 && (
              <tr>
                <td colSpan={2} className="px-4 py-6 text-zinc-400">
                  Nenhum fornecedor cadastrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </main>
  );
}
