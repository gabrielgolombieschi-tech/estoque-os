"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";

type Phase = "checking" | "invalid" | "ready" | "success";

type Props = {
  redirectTo?: string;
};

export default function ResetPasswordClient({ redirectTo = "/login" }: Props) {
  const router = useRouter();

  const [phase, setPhase] = useState<Phase>("checking");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");

  const canSubmit = useMemo(() => {
    return password.length >= 8 && password === confirmPassword && !busy;
  }, [busy, confirmPassword, password]);

  useEffect(() => {
    let active = true;

    const run = async () => {
      try {
        const supabase = getSupabaseBrowser();
        const { data, error: sessErr } = await supabase.auth.getSession();

        if (!active) return;

        if (sessErr || !data.session) {
          setPhase("invalid");
          return;
        }

        setPhase("ready");
      } catch {
        if (!active) return;
        setPhase("invalid");
      }
    };

    void run();

    return () => {
      active = false;
    };
  }, []);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (password.length < 8) {
      setError("A senha deve ter pelo menos 8 caracteres.");
      return;
    }

    if (password !== confirmPassword) {
      setError("As senhas não conferem.");
      return;
    }

    setBusy(true);
    try {
      const supabase = getSupabaseBrowser();
      const { error: updateErr } = await supabase.auth.updateUser({ password });

      if (updateErr) {
        setError(updateErr.message || "Não foi possível atualizar a senha.");
        setBusy(false);
        return;
      }

      setPhase("success");
      setBusy(false);

      setTimeout(() => {
        router.push(redirectTo);
      }, 1200);
    } catch {
      setError("Não foi possível atualizar a senha.");
      setBusy(false);
    }
  }

  return (
    <div className="min-h-[calc(100dvh-0px)] flex items-center justify-center p-4">
      <div className="w-full max-w-md rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl">
        <div className="p-5 border-b border-zinc-800">
          <div className="text-lg font-semibold text-zinc-100">Redefinir senha</div>
          <div className="text-sm text-zinc-400">Defina uma nova senha para sua conta.</div>
        </div>

        <div className="p-5">
          {phase === "checking" && <div className="text-sm text-zinc-300">Validando link...</div>}

          {phase === "invalid" && (
            <div className="space-y-3">
              <div className="text-sm text-red-300">Link inválido ou expirado. Solicite novamente.</div>
              <button
                type="button"
                onClick={() => router.push(redirectTo)}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
              >
                Ir para login
              </button>
            </div>
          )}

          {phase === "success" && (
            <div className="space-y-2">
              <div className="text-sm text-emerald-300">Senha atualizada com sucesso</div>
              <div className="text-xs text-zinc-500">Redirecionando para o login...</div>
            </div>
          )}

          {phase === "ready" && (
            <form onSubmit={onSubmit} className="space-y-4">
              <div className="space-y-1">
                <label className="text-xs text-zinc-400" htmlFor="password">
                  Nova senha
                </label>
                <input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                  placeholder="Mínimo 8 caracteres"
                  autoComplete="new-password"
                  disabled={busy}
                />
              </div>

              <div className="space-y-1">
                <label className="text-xs text-zinc-400" htmlFor="confirmPassword">
                  Confirmar senha
                </label>
                <input
                  id="confirmPassword"
                  type="password"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                  placeholder="Repita a senha"
                  autoComplete="new-password"
                  disabled={busy}
                />
              </div>

              {error && <div className="text-sm text-red-300">{error}</div>}

              <button
                type="submit"
                disabled={!canSubmit}
                className="w-full px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium disabled:opacity-60"
              >
                {busy ? "Salvando..." : "Atualizar senha"}
              </button>

              <button
                type="button"
                onClick={() => router.push(redirectTo)}
                className="w-full px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
                disabled={busy}
              >
                Cancelar
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
