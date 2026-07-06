"use client";

import type { EmpresaDisplayInfo } from "./empresaDisplay";
import { EMPRESA_SCOPE_ALL, type EmpresaScope } from "./empresaScope";

export default function EmpresaScopeFilter({
  options,
  value,
  onChange,
}: {
  options: EmpresaDisplayInfo[];
  value: EmpresaScope;
  onChange: (scope: EmpresaScope) => void;
}) {
  if (options.length <= 1) return null;

  const items: Array<{ value: EmpresaScope; label: string }> = [
    { value: EMPRESA_SCOPE_ALL, label: "Todas" },
    ...options.map((option) => ({ value: option.id, label: option.label })),
  ];

  return (
    <div>
      <label className="block text-xs font-medium text-zinc-400">Empresa</label>
      <div className="mt-1 flex flex-wrap gap-2">
        {items.map((item) => {
          const active = value === item.value;
          return (
            <button
              key={item.value}
              type="button"
              onClick={() => onChange(item.value)}
              className={[
                "rounded-md border px-3 py-2 text-sm transition-colors",
                active
                  ? "border-zinc-600 bg-zinc-800 text-zinc-100"
                  : "border-zinc-800 bg-zinc-950 text-zinc-300 hover:bg-zinc-900",
              ].join(" ")}
            >
              {item.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}
