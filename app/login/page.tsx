"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";

export default function LoginPage() {
  const supabase = supabaseBrowser();
  const router = useRouter();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    setMsg(null);
    setLoading(true);

    const { error } = await supabase.auth.signInWithPassword({ email, password });

    setLoading(false);
    if (error) return setMsg(error.message);

    router.push("/");
  }

  return (
    <main className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-sm border border-zinc-800 bg-zinc-950 rounded-xl p-5">
        <h1 className="text-xl font-semibold">Login</h1>
        <p className="text-sm text-zinc-400 mt-1">
          Acesse para gerenciar OS e estoque.
        </p>

        <form onSubmit={signIn} className="mt-4 space-y-3">
          <div className="space-y-1">
            <label className="text-xs text-zinc-400">Email</label>
            <input
              className="w-full px-3 py-2"
              placeholder="seu@email.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="email"
            />
          </div>

          <div className="space-y-1">
            <label className="text-xs text-zinc-400">Senha</label>
            <input
              className="w-full px-3 py-2"
              placeholder="••••••••"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
            />
          </div>

          <button
            disabled={loading}
            className="w-full px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 font-medium hover:bg-white"
          >
            {loading ? "Entrando..." : "Entrar"}
          </button>

          {msg && <p className="text-sm text-red-400">{msg}</p>}
        </form>
      </div>
    </main>
  );
}
