"use client";

import { useContext } from "react";
import { EmpresaContext } from "@/app/components/EmpresaProvider";

export function useEmpresa() {
  const ctx = useContext(EmpresaContext);
  if (!ctx) {
    throw new Error("EmpresaProvider nao encontrado.");
  }
  if (!ctx.empresaId && !ctx.loading) {
    throw new Error("Empresa ativa nao definida.");
  }
  return ctx;
}
