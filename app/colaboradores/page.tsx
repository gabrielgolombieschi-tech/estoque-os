"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

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
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

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
      const { data, error } = await supabase
        .from("vw_colaboradores_taxa_atual")
        .select("*")
        .order("nome", { ascending: true });

      if (error) throw error;
      setRows((data ?? []) as RowView[]);
    } catch (e: unknown) {
      console.error(e);
      setErrorMsg(getErrorMessage(e, "Falha ao carregar colaboradores."));
    } finally {
      setLoading(false);
    }
  }, [supabase]);

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
    colaboradorId: string;
    valor: number;
    vInicio: string;
    taxaAbertaId: string | null;
    taxaAbertaInicio: string | null;
  }) {
    const { colaboradorId, valor, vInicio, taxaAbertaId, taxaAbertaInicio } = params;
    const taxaInicio = taxaAbertaInicio ?? null;

    if (taxaInicio && vInicio <= taxaInicio) {
      throw new Error("Vigencia inicio precisa ser maior que a vigencia atual.");
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
      if (!editId) {
        // cria colaborador
        const { data: novo, error } = await supabase
          .from("colaboradores")
          .insert([{ nome: nome.trim(), cargo: cargo.trim() || null, ativo }])
          .select("id")
          .single();

        if (error) throw error;

        // cria taxa inicial (obrigatoria aqui)
        await criarTaxaNova({
          colaboradorId: novo.id,
          valor: valor!, // jǭ validado
          vInicio: vIni,
          taxaAbertaId: null,
          taxaAbertaInicio: null,
        });
      } else {
        // atualiza colaborador
        const { error } = await supabase
          .from("colaboradores")
          .update({ nome: nome.trim(), cargo: cargo.trim() || null, ativo })
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
      console.error(e);
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
      const { error } = await supabase
        .from("colaboradores")
        .update({ ativo: !r.ativo })
        .eq("id", r.id);

      if (error) throw error;
      await carregar();
    } catch (e: unknown) {
      console.error(e);
      const msg = getErrorMessage(e, "Erro ao atualizar.");
      setErrorMsg(msg);
      alert(msg);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div style={{ padding: 16 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <h1 style={{ fontSize: 22, fontWeight: 700, margin: 0 }}>
          Colaboradores
        </h1>
        <button
          onClick={abrirNovo}
          disabled={loading}
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          + Novo
        </button>
        {loading && <span>Carregando...</span>}
      </div>

      {errorMsg && (
        <div
          style={{
            marginTop: 10,
            padding: 10,
            border: "1px solid #7a2",
            borderRadius: 8,
            background: "rgba(120,160,40,0.12)",
          }}
        >
          {errorMsg}
        </div>
      )}

      <div style={{ marginTop: 12, border: "1px solid #333", borderRadius: 8 }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left" }}>
              <th style={{ padding: 10, borderBottom: "1px solid #333" }}>
                ID
              </th>
              <th style={{ padding: 10, borderBottom: "1px solid #333" }}>
                Nome
              </th>
              <th style={{ padding: 10, borderBottom: "1px solid #333" }}>
                Cargo
              </th>
              <th style={{ padding: 10, borderBottom: "1px solid #333" }}>
                Valor/hora (vigente)
              </th>
              <th style={{ padding: 10, borderBottom: "1px solid #333" }}>
                Ativo
              </th>
              <th style={{ padding: 10, borderBottom: "1px solid #333" }}>
                Acoes
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, idx) => (
              <tr key={r.id}>
                <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                  {idx + 1}
                </td>
                <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                  {r.nome}
                </td>
                <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                  {r.cargo ?? "-"}
                </td>
                <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                  {r.valor_hora != null ? `R$ ${Number(r.valor_hora).toFixed(2)}` : "-"}
                </td>
                <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                  {r.ativo ? "Sim" : "Nǜo"}
                </td>
                <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                  <button
                    onClick={() => abrirEditar(r)}
                    disabled={loading}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  >
                    Editar
                  </button>{" "}
                  <button
                    onClick={() => toggleAtivo(r)}
                    disabled={loading}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  >
                    {r.ativo ? "Desativar" : "Ativar"}
                  </button>
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr>
                <td style={{ padding: 10 }} colSpan={6}>
                  Nenhum colaborador cadastrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {modalOpen && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.6)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: 16,
          }}
        >
          <div
            style={{
              width: 520,
              maxWidth: "100%",
              background: "#111",
              border: "1px solid #333",
              borderRadius: 12,
              padding: 16,
            }}
          >
            <h2 style={{ marginTop: 0 }}>
              {editId ? "Editar colaborador" : "Novo colaborador"}
            </h2>

            <div style={{ display: "grid", gap: 10 }}>
              <label>
                Nome*
                <input
                  value={nome}
                  onChange={(e) => setNome(e.target.value)}
                  style={{ width: "100%" }}
                />
              </label>

              <label>
                Cargo
                <select
                  value={cargo}
                  onChange={(e) => setCargo(e.target.value)}
                  style={{ width: "100%" }}
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
              </label>

              <label>
                Valor/hora (para custo)
                <input
                  value={valorHora}
                  onChange={(e) => setValorHora(e.target.value)}
                  placeholder="Ex: 85,00"
                  style={{ width: "100%" }}
                />
                {editId && (
                  <small style={{ opacity: 0.8 }}>
                    * Ao editar, so cria nova taxa se voce realmente mudar o valor.
                  </small>
                )}
                {!editId && (
                  <small style={{ opacity: 0.8 }}>
                    * No cadastro, o valor/hora e obrigatorio.
                  </small>
                )}
              </label>

              <label>
                Vigencia inicio (para nova taxa)
                <input
                  type="date"
                  value={vigenciaInicio}
                  onChange={(e) => setVigenciaInicio(e.target.value)}
                />
              </label>

              <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <input
                  type="checkbox"
                  checked={ativo}
                  onChange={(e) => setAtivo(e.target.checked)}
                />
                Ativo
              </label>
            </div>

            <div
              style={{
                marginTop: 14,
                display: "flex",
                justifyContent: "flex-end",
                gap: 8,
              }}
            >
              <button onClick={() => setModalOpen(false)} disabled={loading}>
                Cancelar
              </button>
              <button onClick={salvar} disabled={loading}>
                Salvar
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}



