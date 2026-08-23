"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

export type UsuarioResponsavelOption = {
  auth_user_id: string;
  nome: string;
  email: string;
};

type ApiResponse = {
  usuarios?: Array<{ auth_user_id?: string | null; nome?: string | null; email?: string | null }>;
  error?: string;
};

export function normalizeNomePessoa(value: string | null | undefined) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9]+/g, " ")
    .trim()
    .toLocaleUpperCase("pt-BR");
}

export function sugerirUsuarioPorNome(
  nome: string | null | undefined,
  usuarios: UsuarioResponsavelOption[]
): UsuarioResponsavelOption | null {
  const alvo = normalizeNomePessoa(nome);
  if (!alvo) return null;

  const exato = usuarios.find((usuario) => normalizeNomePessoa(usuario.nome) === alvo);
  if (exato) return exato;

  const partesAlvo = alvo.split(" ").filter(Boolean);
  const primeiro = partesAlvo[0];
  const ultimo = partesAlvo.at(-1) ?? null;

  if (partesAlvo.length >= 2) {
    const porPrimeiroEUltimo = usuarios.find((usuario) => {
      const partesUsuario = normalizeNomePessoa(usuario.nome).split(" ").filter(Boolean);
      return partesUsuario[0] === primeiro && partesUsuario.at(-1) === ultimo;
    });
    if (porPrimeiroEUltimo) return porPrimeiroEUltimo;
  }

  // Perfis de sistema frequentemente usam apenas o primeiro nome. Só sugere
  // quando ele identifica uma única pessoa, sem gravar o vínculo automaticamente.
  const porPrimeiroNome = usuarios.filter((usuario) => {
    const partesUsuario = normalizeNomePessoa(usuario.nome).split(" ").filter(Boolean);
    return partesUsuario[0] === primeiro;
  });
  return porPrimeiroNome.length === 1 ? porPrimeiroNome[0] : null;
}

export default function ResponsavelAprovacaoSelect({
  tenantId,
  empresaId,
  value,
  onChange,
  disabled = false,
  label = "Responsável pela aprovação",
  defaultToCurrentUser = false,
  className = "",
}: {
  tenantId: string | null | undefined;
  empresaId: string | null | undefined;
  value: string | null;
  onChange: (userId: string | null, usuario: UsuarioResponsavelOption | null) => void;
  disabled?: boolean;
  label?: string;
  defaultToCurrentUser?: boolean;
  className?: string;
}) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [usuarios, setUsuarios] = useState<UsuarioResponsavelOption[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const load = async () => {
      if (!tenantId || !empresaId) return;
      setLoading(true);
      setError(null);
      try {
        const { data: sessionData } = await supabase.auth.getSession();
        const session = sessionData.session;
        if (!session) throw new Error("Sessão expirada. Faça login novamente.");
        if (active) setCurrentUserId(session.user.id);

        const response = await fetch(
          `/api/estoque/usuarios-solicitantes?tenantId=${encodeURIComponent(tenantId)}&empresaId=${encodeURIComponent(empresaId)}`,
          { headers: { authorization: `Bearer ${session.access_token}` } }
        );
        const payload = (await response.json().catch(() => null)) as ApiResponse | null;
        if (!response.ok) throw new Error(payload?.error || "Não foi possível carregar os usuários.");
        const next = (payload?.usuarios ?? [])
          .map((usuario) => ({
            auth_user_id: String(usuario.auth_user_id ?? "").trim(),
            nome: String(usuario.nome ?? "").trim(),
            email: String(usuario.email ?? "").trim(),
          }))
          .filter((usuario) => usuario.auth_user_id && usuario.nome)
          .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR", { sensitivity: "base" }));
        if (active) setUsuarios(next);
      } catch (cause: unknown) {
        if (active) setError(cause instanceof Error ? cause.message : "Não foi possível carregar os usuários.");
      } finally {
        if (active) setLoading(false);
      }
    };
    void load();
    return () => {
      active = false;
    };
  }, [empresaId, supabase, tenantId]);

  useEffect(() => {
    if (!defaultToCurrentUser || value || !currentUserId) return;
    const usuario = usuarios.find((item) => item.auth_user_id === currentUserId) ?? null;
    onChange(currentUserId, usuario);
  }, [currentUserId, defaultToCurrentUser, onChange, usuarios, value]);

  return (
    <div className={`space-y-1 ${className}`.trim()}>
      <div className="text-xs text-zinc-400">{label}</div>
      <select
        className="w-full px-3 py-2"
        value={value ?? ""}
        onChange={(event) => {
          const userId = event.target.value || null;
          onChange(userId, usuarios.find((usuario) => usuario.auth_user_id === userId) ?? null);
        }}
        disabled={disabled || loading}
        aria-label={label}
      >
        <option value="">{loading ? "Carregando usuários..." : "Sem responsável definido"}</option>
        {usuarios.map((usuario) => (
          <option key={usuario.auth_user_id} value={usuario.auth_user_id}>
            {usuario.nome}{usuario.email ? ` (${usuario.email})` : ""}
          </option>
        ))}
      </select>
      {error ? <div className="text-xs text-amber-300">{error}</div> : null}
    </div>
  );
}
