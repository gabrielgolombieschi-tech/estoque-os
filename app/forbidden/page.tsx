import React from "react";

export default function ForbiddenPage() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center">
        <h1 className="text-2xl font-bold">403 — Acesso Negado</h1>
        <p className="mt-2 text-zinc-400">Você não tem permissão para acessar esta página.</p>
      </div>
    </div>
  );
}
