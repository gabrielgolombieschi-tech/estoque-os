"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import NfeImportModal from "./NfeImportModal";

export default function NfeImportPageClient() {
  const router = useRouter();
  const [open, setOpen] = useState(true);

  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="text-sm text-zinc-400">Importação de XML</div>
      <NfeImportModal
        open={open}
        onClose={() => {
          setOpen(false);
          router.replace("/faturamento/nfe");
        }}
      />
    </div>
  );
}

