"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";

type RowView = {
  id: string;
  nome: string;
  cargo: string | null;
  ativo: boolean;
  criado_em: string;

  taxa_id: string | null;
  valor_hora: number | null;
  vigencia_inicio: string | null;
  vigencia_fim: string | null;
};

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

function todayISO() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function isValidISODate(dateStr: string) {
  // simples e suficiente: YYYY-MM-DD
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return false;
  const d = new Date(dateStr + "T00:00:00");
  return !Number.isNaN(d.getTime());
}

function toNumberBR(v: string): number | null {
  const s = v.trim();
  if (!s) return null;
  const hasDot = s.includes(".");
  const hasComma = s.includes(",");
  let normalized = s;

  if (hasDot && hasComma) {
    const lastDot = s.lastIndexOf(".");
    const lastComma = s.lastIndexOf(",");
    if (lastComma > lastDot) {
      normalized = s.replace(/\./g, "").replace(",", ".");
    } else {
      normalized = s.replace(/,/g, "");
    }
  } else if (hasComma) {
    normalized = s.replace(",", ".");
  } else if (hasDot) {
    const dotCount = (s.match(/\./g) || []).length;
    normalized = dotCount > 1 ? s.replace(/\./g, "") : s;
  }

  const n = Number(normalized);
  return Number.isFinite(n) ? n : null;
}

function sameMoney(a: number | null, b: number | null) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return Math.abs(a - b) < 0.0001;
}

export default function ColaboradoresPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const { tenantId } = usePermissions();

  const [rows, setRows] = useState<RowView[]>([]);

  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);

  const [nome, setNome] = useState("");
  const [cargo, setCargo] = useState("");
  const [ativo, setAtivo] = useState(true);

  // taxa / vigencia
  const [valorHora, setValorHora] = useState<string>("");
  const [vigenciaInicio, setVigenciaInicio] = useState<string>(todayISO());

  // controle p/ evitar duplicar taxa ao editar sem mudanca
  const [valorHoraOriginal, setValorHoraOriginal] = useState<number | null>(null);

  const carregar = useCallback(async () => {
    setLoading(true);
    setErrorMsg(null);
    try {
      if (!tenantId) {
        throw new Error("Tenant não carregado.");
      }
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;
      
      const { data, error } = await supabase
        .from("vw_colaboradores_taxa_atual")
        .select("*")
        .order("nome", { ascending: true });

      if (error) throw error;
      setRows((data ?? []) as RowView[]);

    } catch (e: unknown) {
      setErrorMsg(getErrorMessage(e, "Falha ao carregar colaboradores."));
    } finally {
      setLoading(false);
    }
  }, [supabase, tenantId]);

  useEffect(() => {
    carregar();
  }, [carregar]);

  function abrirNovo() {
    setEditId(null);
    setNome("");
    setCargo("");
    setAtivo(true);

    setValorHora("");
    setVigenciaInicio(todayISO());

    setValorHoraOriginal(null);

    setModalOpen(true);
  }

  function abrirEditar(r: RowView) {
    setEditId(r.id);
    setNome(r.nome);
    setCargo(r.cargo ?? "");
    setAtivo(!!r.ativo);

    setValorHoraOriginal(r.valor_hora ?? null);

    // preenche apenas para o usuǭrio ver
    setValorHora(r.valor_hora != null ? String(r.valor_hora) : "");
    setVigenciaInicio(todayISO()); // se mudar taxa, a nova taxa entra a partir de hoje (ou voce pode alterar)

    setModalOpen(true);
  }

  async function criarTaxaNova(params: {
    tenantId: string;
    colaboradorId: string;
    valor: number;
    vInicio: string;
    taxaAbertaId: string | null;
    taxaAbertaInicio: string | null;
  }) {
    const { tenantId, colaboradorId, valor, vInicio, taxaAbertaId, taxaAbertaInicio } = params;
    const taxaInicio = taxaAbertaInicio ?? null;

    if (taxaInicio && vInicio <= taxaInicio) {
      throw new Error("Vigencia inicio precisa ser maior que a vigencia atual.");
    }

    // garante contexto de tenant (necessário para RLS)
    {
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;
    }

    // fecha a taxa aberta (se existir) com a vespera da vigencia nova
    if (taxaAbertaId && taxaInicio) {
      const d = new Date(vInicio + "T00:00:00");
      d.setDate(d.getDate() - 1);

      const yyyy = d.getFullYear();
      const mm = String(d.getMonth() + 1).padStart(2, "0");
      const dd = String(d.getDate()).padStart(2, "0");
      const vFim = `${yyyy}-${mm}-${dd}`;

      // nao fecha se vFim ficar antes do inicio antigo (protecao)
      if (vFim >= taxaInicio) {
        const { error: eClose } = await supabase
          .from("colaborador_taxas")
          .update({ vigencia_fim: vFim })
          .eq("id", taxaAbertaId);

        if (eClose) throw eClose;
      }
    }

    // cria nova taxa
    const { error: eNew } = await supabase.from("colaborador_taxas").insert([
      {
        tenant_id: tenantId,
        colaborador_id: colaboradorId,
        valor_hora: valor,
        vigencia_inicio: vInicio,
        vigencia_fim: null,
      },
    ]);

    if (eNew) throw eNew;
  }

  async function salvar() {
    setErrorMsg(null);

    if (!nome.trim()) {
      alert("Informe o nome.");
      return;
    }

    const valor = toNumberBR(valorHora);
    const vIni = vigenciaInicio;

    // valida data se for usar taxa
    if (valor !== null && !isValidISODate(vIni)) {
      alert("Vigencia inicio invalida.");
      return;
    }

    // regra: no NOVO, exigir taxa (para evitar colaborador �?oinutilizǭvel�??)
    if (!editId) {
      if (valor === null || valor <= 0) {
        alert("Para criar colaborador, informe um Valor/hora vǭlido.");
        return;
      }
    } else {
      // no EDITAR, taxa so cria se o valor mudou
      if (valor !== null && valor <= 0) {
        alert("Valor/hora invǭlido.");
        return;
      }
    }

    setLoading(true);
    try {
      if (!tenantId) {
        throw new Error("Tenant não carregado.");
      }
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;
      if (!editId) {
        // cria colaborador
        const { data: novo, error } = await supabase
          .from("colaboradores")
          .insert([{ 
            tenant_id: tenantId, 
            nome: nome.trim(), 
            cargo: cargo.trim() || null, 
            ativo
          }])
          .select("id")
          .single();

        if (error) throw error;

        // cria taxa inicial (obrigatoria aqui)
        await criarTaxaNova({
          tenantId: tenantId,
          colaboradorId: novo.id,
          valor: valor!, // já validado
          vInicio: vIni,
          taxaAbertaId: null,
          taxaAbertaInicio: null,
        });
      } else {
        // atualiza colaborador
        const { error: tenantErr2 } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
        if (tenantErr2) throw tenantErr2;
        const { error } = await supabase
          .from("colaboradores")
          .update({ 
            nome: nome.trim(), 
            cargo: cargo.trim() || null, 
            ativo
          })
          .eq("id", editId);

        if (error) throw error;

        // Obs. So cria nova taxa se o valor mudou DE VERDADE
        const valorNovo = valor; // pode ser null (sem alterar taxa)
        const mudou =
          valorNovo !== null && !sameMoney(valorNovo, valorHoraOriginal);

        if (mudou) {
          // precisamos do inicio da taxa atual aberta (para validar fechamento)
          const rowAtual = rows.find((r) => r.id === editId) ?? null;

          await criarTaxaNova({
            tenantId: tenantId,
            colaboradorId: editId,
            valor: valorNovo!,
            vInicio: vIni,
            taxaAbertaId: rowAtual?.taxa_id ?? null,
            taxaAbertaInicio: rowAtual?.vigencia_inicio ?? null,
          });
        }
      }

      setModalOpen(false);
      await carregar();
    } catch (e: unknown) {
      const msg = getErrorMessage(e, "Erro ao salvar.");
      setErrorMsg(msg);
      alert(msg);
    } finally {
      setLoading(false);
    }
  }

  async function toggleAtivo(r: RowView) {
    if (!confirm(`Deseja ${r.ativo ? "desativar" : "ativar"} ${r.nome}?`)) return;
    setLoading(true);
    setErrorMsg(null);
    try {
      if (!tenantId) {
        throw new Error("Tenant não carregado.");
      }
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;
      const { error } = await supabase
        .from("colaboradores")
        .update({ ativo: !r.ativo })
        .eq("id", r.id);

      if (error) throw error;
      await carregar();
    } catch (e: unknown) {
      const msg = getErrorMessage(e, "Erro ao atualizar.");
      setErrorMsg(msg);
      alert(msg);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold">
          Colaboradores
        </h1>
        <button
          onClick={abrirNovo}
          disabled={loading}
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          + Novo
        </button>
        {loading && <span className="text-zinc-400">Carregando...</span>}
      </div>

      {errorMsg && (
        <div className="mt-3 p-3 border border-lime-600/50 rounded-lg bg-lime-900/10 text-lime-300 text-sm">
          {errorMsg}
        </div>
      )}

      <div className="border border-zinc-800 rounded-lg overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/50">
            <tr className="text-left">
              <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">
                ID
              </th>
              <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">
                Nome
              </th>
              <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">
                Cargo
              </th>
              <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">
                Valor/hora (vigente)
              </th>
              <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">
                Ativo
              </th>
              <th className="px-3 py-2 border-b border-zinc-800 text-zinc-300">
                Ações
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {rows.map((r, idx) => (
              <tr key={r.id} className="hover:bg-zinc-900/40">
                <td className="px-3 py-2 text-zinc-400">
                  {idx + 1}
                </td>
                <td className="px-3 py-2 text-zinc-200">
                  {r.nome}
                </td>
                <td className="px-3 py-2 text-zinc-300">
                  {r.cargo ?? "-"}
                </td>
                <td className="px-3 py-2 text-zinc-300">
                  {r.valor_hora != null ? `R$ ${Number(r.valor_hora).toFixed(2)}` : "-"}
                </td>
                <td className="px-3 py-2 text-zinc-300">
                  {r.ativo ? "Sim" : "Não"}
                </td>
                <td className="px-3 py-2 space-x-2">
                  <button
                    onClick={() => abrirEditar(r)}
                    disabled={loading}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                  >
                    Editar
                  </button>
                  <button
                    onClick={() => toggleAtivo(r)}
                    disabled={loading}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                  >
                    {r.ativo ? "Desativar" : "Ativar"}
                  </button>
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr>
                <td className="px-3 py-4 text-zinc-400 text-center" colSpan={6}>
                  Nenhum colaborador cadastrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {modalOpen && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4">
          <div className="w-full max-w-xl bg-zinc-900 border border-zinc-700 rounded-xl p-6 space-y-4 shadow-xl">
            <h2 className="text-lg font-semibold text-zinc-100">
              {editId ? "Editar colaborador" : "Novo colaborador"}
            </h2>

            <div className="space-y-3">
              <div className="space-y-1">
                <label className="text-sm text-zinc-300">
                  Nome*
                </label>
                <input
                  value={nome}
                  onChange={(e) => setNome(e.target.value)}
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                  aria-label="Nome do colaborador"
                />
              </div>

              <div className="space-y-1">
                <label className="text-sm text-zinc-300">
                  Cargo
                </label>
                <select
                  value={cargo}
                  onChange={(e) => setCargo(e.target.value)}
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                  aria-label="Cargo do colaborador"
                >
                  <option value="">Selecione</option>
                  <option value="AUXILIAR MEC">AUXILIAR MEC</option>
                  <option value="AUXILIAR ELE">AUXILIAR ELE</option>
                  <option value="MECANICO">MECANICO</option>
                  <option value="ELETRICISTA">ELETRICISTA</option>
                  <option value="PROJETISTA MEC">PROJETISTA MEC</option>
                  <option value="PROJETISTA ELE">PROJETISTA ELE</option>
                  <option value="PROGRAMADOR">PROGRAMADOR</option>
                  <option value="ENGENHEIRO">ENGENHEIRO</option>
                  <option value="COORDENADOR">COORDENADOR</option>
                  <option value="TEC. SEGURANÇA">TEC. SEGURANÇA</option>
                </select>
              </div>

              <div className="space-y-1">
                <label className="text-sm text-zinc-300">
                  Valor/hora (para custo)
                </label>
                <input
                  value={valorHora}
                  onChange={(e) => setValorHora(e.target.value)}
                  placeholder="Ex: 85,00"
                  aria-label="Valor hora do colaborador"
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                />
                {editId && (
                  <small className="text-zinc-400 block mt-1">
                    * Ao editar, só cria nova taxa se você realmente mudar o valor.
                  </small>
                )}
                {!editId && (
                  <small className="text-zinc-400 block mt-1">
                    * No cadastro, o valor/hora é obrigatório.
                  </small>
                )}
              </div>

              <div className="space-y-1">
                <label className="text-sm text-zinc-300">
                  Vigência início (para nova taxa)
                </label>
                <input
                  type="date"
                  value={vigenciaInicio}
                  onChange={(e) => setVigenciaInicio(e.target.value)}
                  aria-label="Data de vigência inicial"
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded text-zinc-100"
                />
              </div>

              <label className="flex items-center gap-2 text-sm text-zinc-300">
                <input
                  type="checkbox"
                  checked={ativo}
                  onChange={(e) => setAtivo(e.target.checked)}
                  className="w-4 h-4"
                />
                Ativo
              </label>
            </div>

            <div className="border-t border-zinc-700 pt-4 flex justify-end gap-2">
              <button
                onClick={() => setModalOpen(false)}
                disabled={loading}
                className="px-4 py-2 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
              >
                Cancelar
              </button>
              <button
                onClick={salvar}
                disabled={loading}
                className="px-4 py-2 rounded bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm"
              >
                Salvar
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}


