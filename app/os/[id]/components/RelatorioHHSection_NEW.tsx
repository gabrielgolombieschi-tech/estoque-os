"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";

type HHTipoPreco = {
  id: number;
  descricao: string;
  nivel: string;
  categoria: string;
  preco_base: number;
  preco_50: number;
  preco_100: number;
};

type Colaborador = {
  id: string;
  nome: string;
  ativo: boolean;
};

type HHLancamento = {
  id: number;
  colaborador_id: string;
  colaborador_nome: string | null;
  hh_tipo_id: number;
  hh_tipo_descricao: string | null;
  hh_tipo_nivel: string | null;
  data: string;
  hora_entrada: string;
  hora_saida: string;
  horas_trabalhadas: number;
  percentual_aplicado: number;
  valor_hora: number;
  valor_total: number;
  observacao: string | null;
};

function formatMoneyBR(value: number | null | undefined) {
  const n = Number(value ?? 0);
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDateBR(isoDate: string | null | undefined) {
  if (!isoDate) return "--";
  const d = new Date(isoDate + "T00:00:00");
  return d.toLocaleDateString("pt-BR");
}

export default function RelatorioHHSection({ osId }: { osId: number }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId, loading: tenantLoading } = useTenantEmpresa();
  const { has } = usePermissions();

  const canRead = Boolean(has("os.read"));
  const canWrite = Boolean(has("os.write"));

  const [lancamentos, setLancamentos] = useState<HHLancamento[]>([]);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [hhTipos, setHhTipos] = useState<HHTipoPreco[]>([]);

  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState({
    data: new Date().toISOString().slice(0, 10),
    hora_entrada: "08:00",
    hora_saida: "17:00",
    colaborador_id: "",
    hh_tipo_id: "",
    percentual_aplicado: "0",
    observacao: "",
  });

  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function loadColaboradores() {
    if (!tenantId) return;
    const { data } = await supabase
      .from("colaboradores")
      .select("id,nome,ativo")
      .eq("tenant_id", tenantId)
      .eq("ativo", true)
      .order("nome", { ascending: true });
    
    setColaboradores((data ?? []) as Colaborador[]);
  }

  async function loadHHTipos() {
    const { data } = await supabase
      .from("hh_tabela_precos")
      .select("*")
      .eq("ativo", true)
      .order("categoria", { ascending: true })
      .order("nivel", { ascending: true });
    
    setHhTipos((data ?? []) as HHTipoPreco[]);
  }

  async function loadLancamentos() {
    if (tenantLoading || !tenantId || !empresaId) return;
    
    setLoading(true);
    setErr(null);

    const { data, error } = await supabase
      .from("vw_hh_lancamentos")
      .select("*")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .eq("os_id", osId)
      .order("data", { ascending: false })
      .order("hora_entrada", { ascending: true });

    if (error) {
      setErr(error.message);
    } else {
      setLancamentos((data ?? []) as HHLancamento[]);
    }

    setLoading(false);
  }

  useEffect(() => {
    if (tenantLoading) return;
    loadColaboradores();
    loadHHTipos();
    loadLancamentos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [osId, tenantId, empresaId, tenantLoading]);

  async function salvarLancamento() {
    if (!canWrite) {
      setErr("Sem permissão para lançar HH.");
      return;
    }

    if (!tenantId || !empresaId) {
      setErr("Tenant ou empresa não carregados.");
      return;
    }

    if (!formData.colaborador_id || !formData.hh_tipo_id) {
      setErr("Selecione colaborador e tipo de mão-de-obra.");
      return;
    }

    setLoading(true);
    setErr(null);
    setOk(null);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const { error } = await supabase.from("hh_lancamentos").insert({
      tenant_id: tenantId,
      empresa_id: empresaId,
      os_id: osId,
      colaborador_id: formData.colaborador_id,
      hh_tipo_id: Number(formData.hh_tipo_id),
      data: formData.data,
      hora_entrada: formData.hora_entrada,
      hora_saida: formData.hora_saida,
      percentual_aplicado: Number(formData.percentual_aplicado),
      observacao: formData.observacao.trim() || null,
      criado_por: userEmail,
    });

    setLoading(false);

    if (error) {
      setErr(error.message);
      return;
    }

    setOk("Lançamento HH criado!");
    setShowForm(false);
    setFormData({
      data: new Date().toISOString().slice(0, 10),
      hora_entrada: "08:00",
      hora_saida: "17:00",
      colaborador_id: "",
      hh_tipo_id: "",
      percentual_aplicado: "0",
      observacao: "",
    });

    await loadLancamentos();
  }

  async function deletarLancamento(id: number) {
    if (!canWrite) {
      setErr("Sem permissão para deletar HH.");
      return;
    }

    const confirm = window.confirm("Deletar este lançamento HH?");
    if (!confirm) return;

    setLoading(true);
    setErr(null);

    const { error } = await supabase
      .from("hh_lancamentos")
      .delete()
      .eq("id", id);

    setLoading(false);

    if (error) {
      setErr(error.message);
      return;
    }

    setOk("Lançamento HH deletado!");
    await loadLancamentos();
  }

  const totalHoras = lancamentos.reduce((sum, l) => sum + Number(l.horas_trabalhadas || 0), 0);
  const totalValor = lancamentos.reduce((sum, l) => sum + Number(l.valor_total || 0), 0);

  if (!canRead) {
    return (
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 text-zinc-400">
        Sem permissão para visualizar HH.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div>
            <h2 className="text-lg font-semibold">Lançamentos HH</h2>
            <p className="text-sm text-zinc-400 mt-1">
              Geração e consulta de lançamentos HH (entrada/saída) para esta OS.
            </p>
          </div>

          {canWrite && (
            <button
              onClick={() => setShowForm(true)}
              disabled={loading}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              Novo Lançamento HH
            </button>
          )}
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}

        <div className="grid grid-cols-2 gap-4 mt-4">
          <div className="border border-zinc-800 rounded-lg p-3">
            <div className="text-xs text-zinc-400">Total de Horas</div>
            <div className="text-2xl font-semibold text-zinc-100 mt-1">
              {totalHoras.toFixed(2)}h
            </div>
          </div>

          <div className="border border-zinc-800 rounded-lg p-3">
            <div className="text-xs text-zinc-400">Custo Total HH</div>
            <div className="text-2xl font-semibold text-emerald-300 mt-1">
              R$ {formatMoneyBR(totalValor)}
            </div>
          </div>
        </div>
      </div>

      {/* Tabela de lançamentos */}
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Data</th>
              <th className="px-4 py-3 text-left">Colaborador</th>
              <th className="px-4 py-3 text-left">Tipo HH</th>
              <th className="px-4 py-3 text-center">Entrada</th>
              <th className="px-4 py-3 text-center">Saída</th>
              <th className="px-4 py-3 text-right">Horas</th>
              <th className="px-4 py-3 text-center">% Adicional</th>
              <th className="px-4 py-3 text-right">Valor/h</th>
              <th className="px-4 py-3 text-right">Total</th>
              <th className="px-4 py-3 text-center">Ações</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-zinc-800">
            {lancamentos.map((l) => (
              <tr key={l.id} className="hover:bg-zinc-900/40">
                <td className="px-4 py-3">{formatDateBR(l.data)}</td>
                <td className="px-4 py-3">{l.colaborador_nome || l.colaborador_id}</td>
                <td className="px-4 py-3">
                  <div className="font-medium">{l.hh_tipo_descricao}</div>
                  <div className="text-xs text-zinc-400">Nível {l.hh_tipo_nivel}</div>
                </td>
                <td className="px-4 py-3 text-center tabular-nums">{l.hora_entrada}</td>
                <td className="px-4 py-3 text-center tabular-nums">{l.hora_saida}</td>
                <td className="px-4 py-3 text-right tabular-nums">{l.horas_trabalhadas.toFixed(2)}h</td>
                <td className="px-4 py-3 text-center">
                  {l.percentual_aplicado === 0 ? "—" : `${l.percentual_aplicado}%`}
                </td>
                <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoneyBR(l.valor_hora)}</td>
                <td className="px-4 py-3 text-right tabular-nums font-semibold">
                  R$ {formatMoneyBR(l.valor_total)}
                </td>
                <td className="px-4 py-3 text-center">
                  {canWrite && (
                    <button
                      onClick={() => deletarLancamento(l.id)}
                      disabled={loading}
                      className="px-3 py-1.5 rounded-md border border-red-700 bg-red-900/20 text-red-300 hover:bg-red-900/40"
                    >
                      Deletar
                    </button>
                  )}
                </td>
              </tr>
            ))}

            {lancamentos.length === 0 && (
              <tr>
                <td colSpan={10} className="px-4 py-6 text-zinc-400 text-center">
                  Nenhum lançamento HH ainda. Clique em "Novo Lançamento HH" para começar.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Modal de novo lançamento */}
      {showForm && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Novo Lançamento HH</div>
                <div className="text-sm text-zinc-400">Informe entrada, saída e tipo de mão-de-obra</div>
              </div>
              <button
                onClick={() => setShowForm(false)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Data</div>
                  <input
                    type="date"
                    aria-label="Data"
                    className="w-full px-3 py-2"
                    value={formData.data}
                    onChange={(e) => setFormData((s) => ({ ...s, data: e.target.value }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Hora de Entrada</div>
                  <input
                    type="time"
                    aria-label="Hora de entrada"
                    className="w-full px-3 py-2"
                    value={formData.hora_entrada}
                    onChange={(e) => setFormData((s) => ({ ...s, hora_entrada: e.target.value }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Hora de Saída</div>
                  <input
                    type="time"
                    aria-label="Hora de saída"
                    className="w-full px-3 py-2"
                    value={formData.hora_saida}
                    onChange={(e) => setFormData((s) => ({ ...s, hora_saida: e.target.value }))}
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Colaborador</div>
                  <select
                    aria-label="Colaborador"
                    className="w-full px-3 py-2"
                    value={formData.colaborador_id}
                    onChange={(e) => setFormData((s) => ({ ...s, colaborador_id: e.target.value }))}
                  >
                    <option value="">Selecione...</option>
                    {colaboradores.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.nome}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Tipo de Mão-de-Obra HH</div>
                  <select
                    aria-label="Tipo de mão-de-obra"
                    className="w-full px-3 py-2"
                    value={formData.hh_tipo_id}
                    onChange={(e) => setFormData((s) => ({ ...s, hh_tipo_id: e.target.value }))}
                  >
                    <option value="">Selecione...</option>
                    {hhTipos.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.descricao} - R$ {formatMoneyBR(t.preco_base)}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Percentual Adicional</div>
                <select
                  aria-label="Percentual adicional"
                  className="w-full px-3 py-2"
                  value={formData.percentual_aplicado}
                  onChange={(e) => setFormData((s) => ({ ...s, percentual_aplicado: e.target.value }))}
                >
                  <option value="0">Normal (0%)</option>
                  <option value="50">50% (adicional noturno/hora extra)</option>
                  <option value="100">100% (feriado/domingo)</option>
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Observação (opcional)</div>
                <textarea
                  aria-label="Observação"
                  className="w-full px-3 py-2 min-h-[60px]"
                  value={formData.observacao}
                  onChange={(e) => setFormData((s) => ({ ...s, observacao: e.target.value }))}
                  placeholder="Ex: horas extras, trabalho noturno, etc."
                />
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 flex justify-end gap-2">
              <button
                onClick={() => setShowForm(false)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={salvarLancamento}
                disabled={loading}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {loading ? "Salvando..." : "Salvar Lançamento"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
