"use client";

import { useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";
import { parseDecimalBR } from "@/lib/decimal";
import { upperTrim } from "@/lib/text";

type Tabela = {
  id: number;
  cliente_id: number;
  ano: number;
  nome: string;
  vigencia_inicio: string;
  vigencia_fim: string;
  ativo: boolean;
  clientes?: { nome: string | null } | null;
};

type Especialidade = {
  id: number;
  descricao: string;
  ativo: boolean;
};

type TabelaItem = {
  id: number;
  tabela_id: number;
  especialidade_id: number;
  valor_base: number;
  hh_especialidades?: { descricao: string | null } | null;
};

type ItemForm = {
  especialidade_id: number | null;
  valor_base: number;
};

type ImportResult = {
  criadas: number;
  atualizadas: number;
  erros: Array<{ linha: number; erro: string }>;
};

function parseMoedaBR(value: string): number {
  const cleaned = value.replace(/[^\d,.-]/g, "").replace(".", "").replace(",", ".");
  return Number.parseFloat(cleaned) || 0;
}

export default function TabelaDetalheHHPage() {
  const router = useRouter();
  const params = useParams();
  const tabelaId = Number(params.id);
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId } = useTenantEmpresa();
  const fixedTenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
  const effectiveTenantId = useMemo(() => tenantId ?? fixedTenantId, [tenantId]);
  const { has, loading: permLoading, ready } = usePermissions();
  const canView = has("os.read");
  const canEdit = has("os.write");
  const canDelete = has("os.delete");

  const [tabela, setTabela] = useState<Tabela | null>(null);
  const [itens, setItens] = useState<TabelaItem[]>([]);
  const [especialidades, setEspecialidades] = useState<Especialidade[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [showItemForm, setShowItemForm] = useState(false);
  const [editingItemId, setEditingItemId] = useState<number | null>(null);
  const [itemForm, setItemForm] = useState<ItemForm>({ especialidade_id: null, valor_base: 0 });

  const [showImport, setShowImport] = useState(false);
  const [csvText, setCsvText] = useState("");
  const [importResult, setImportResult] = useState<ImportResult | null>(null);

  async function loadTabela() {
    const { data, error } = await applyTenant(
      supabase.from("cliente_hh_tabelas").select("*,clientes:cliente_id(nome)").eq("id", tabelaId).single(),
      effectiveTenantId
    );

    if (error) {
      setErr(error.message);
      return;
    }

    setTabela(data as Tabela);
  }

  async function loadItens() {
    const { data, error } = await applyTenant(
      supabase
        .from("cliente_hh_tabela_itens")
        .select("*,hh_especialidades:especialidade_id(descricao)")
        .eq("tabela_id", tabelaId)
        .order("id", { ascending: true }),
      effectiveTenantId
    );

    if (error) {
      setErr(error.message);
      return;
    }

    setItens((data ?? []) as TabelaItem[]);
  }

  async function loadEspecialidades() {
    const { data } = await applyTenant(
      supabase.from("hh_especialidades").select("*").eq("ativo", true).order("descricao", { ascending: true }),
      effectiveTenantId
    );

    setEspecialidades((data ?? []) as Especialidade[]);
  }

  useEffect(() => {
    loadTabela();
    loadItens();
    loadEspecialidades();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, effectiveTenantId, tabelaId]);

  function startNewItem() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para adicionar itens.");
      return;
    }
    setEditingItemId(null);
    setItemForm({ especialidade_id: null, valor_base: 0 });
    setShowItemForm(true);
  }

  function startEditItem(item: TabelaItem) {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para editar itens.");
      return;
    }
    setEditingItemId(item.id);
    setItemForm({ especialidade_id: item.especialidade_id, valor_base: item.valor_base });
    setShowItemForm(true);
  }

  function closeItemForm() {
    setShowItemForm(false);
    setEditingItemId(null);
    setItemForm({ especialidade_id: null, valor_base: 0 });
  }

  async function saveItem() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para salvar itens.");
      return;
    }

    if (!itemForm.especialidade_id) return setErr("Especialidade é obrigatória.");
    if (!Number.isFinite(itemForm.valor_base) || itemForm.valor_base <= 0)
      return setErr("Valor base deve ser maior que zero.");

    setBusy(true);

    const payload = {
      tabela_id: tabelaId,
      especialidade_id: itemForm.especialidade_id,
      valor_base: itemForm.valor_base,
      atualizado_em: new Date().toISOString(),
    };

    if (!tenantId) {
      setBusy(false);
      return setErr("Tenant não carregado.");
    }

    let error: { message?: string } | null = null;

    if (editingItemId) {
      const res = await applyTenant(
        supabase.from("cliente_hh_tabela_itens").update(payload),
        tenantId
      ).eq("id", editingItemId);
      error = res.error;
    } else {
      const res = await supabase
        .from("cliente_hh_tabela_itens")
        .insert({ ...payload, tenant_id: tenantId, criado_em: new Date().toISOString() });
      error = res.error;
    }

    setBusy(false);
    if (error) return setErr(error.message ?? "Erro ao salvar.");

    setOk(editingItemId ? "Item atualizado!" : "Item adicionado!");
    closeItemForm();
    await loadItens();
  }

  async function deleteItem(id: number) {
    if (!canDelete) {
      setErr("Sem permissão para excluir itens.");
      return;
    }

    const ok = confirm("Tem certeza que deseja excluir este item?");
    if (!ok) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    if (!tenantId) {
      setBusy(false);
      return setErr("Tenant não carregado.");
    }

    const { error } = await applyTenant(
      supabase.from("cliente_hh_tabela_itens").delete(),
      tenantId
    ).eq("id", id);

    setBusy(false);
    if (error) return setErr(error.message);

    setOk("Item excluído.");
    await loadItens();
  }

  async function handleImportCSV() {
    setErr(null);
    setOk(null);
    setImportResult(null);

    if (!canEdit) {
      setErr("Sem permissão para importar.");
      return;
    }

    if (!csvText.trim()) {
      setErr("Cole o conteúdo do CSV.");
      return;
    }

    setBusy(true);

    const lines = csvText.split("\n").map((l) => l.trim()).filter(Boolean);
    if (lines.length === 0) {
      setBusy(false);
      setErr("CSV vazio.");
      return;
    }

    const firstLine = lines[0];
    const hasHeader =
      firstLine.toLowerCase().includes("descricao") || firstLine.toLowerCase().includes("preco");
    const dataLines = hasHeader ? lines.slice(1) : lines;

    const result: ImportResult = { criadas: 0, atualizadas: 0, erros: [] };

    for (let i = 0; i < dataLines.length; i++) {
      const line = dataLines[i];
      const lineNum = i + (hasHeader ? 2 : 1);

      const separator = line.includes(";") ? ";" : ",";
      const parts = line.split(separator).map((p) => p.trim());

      if (parts.length < 2) {
        result.erros.push({ linha: lineNum, erro: "Linha com menos de 2 colunas" });
        continue;
      }

      const descricao = upperTrim(parts[0]);
      const precoStr = parts[1];

      if (!descricao) {
        result.erros.push({ linha: lineNum, erro: "Descrição vazia" });
        continue;
      }

      const valorBase = parseMoedaBR(precoStr);
      if (!Number.isFinite(valorBase) || valorBase <= 0) {
        result.erros.push({ linha: lineNum, erro: `Valor inválido: ${precoStr}` });
        continue;
      }

      try {
        if (!tenantId) {
          result.erros.push({ linha: lineNum, erro: "Tenant não carregado" });
          continue;
        }

        // Buscar ou criar especialidade
        const { data: espData } = await applyTenant(
          supabase.from("hh_especialidades").select("id").ilike("descricao", descricao).limit(1),
          tenantId
        );

        let especialidadeId: number | null = null;

        if (espData && espData.length > 0) {
          especialidadeId = (espData[0] as { id: number }).id;
        } else {
          const { data: newEsp, error: espErr } = await supabase
            .from("hh_especialidades")
            .insert({ tenant_id: tenantId, descricao, ativo: true, criado_em: new Date().toISOString() })
            .select("id")
            .single();

          if (espErr || !newEsp) {
            result.erros.push({ linha: lineNum, erro: `Erro ao criar especialidade: ${espErr?.message}` });
            continue;
          }

          especialidadeId = (newEsp as { id: number }).id;
        }

        if (!especialidadeId) {
          result.erros.push({ linha: lineNum, erro: "Especialidade não encontrada/criada" });
          continue;
        }

        // Upsert item
        const { data: existing } = await applyTenant(
          supabase
            .from("cliente_hh_tabela_itens")
            .select("id")
            .eq("tabela_id", tabelaId)
            .eq("especialidade_id", especialidadeId)
            .limit(1),
          tenantId
        );

        if (existing && existing.length > 0) {
          const itemId = (existing[0] as { id: number }).id;
          const { error: updateErr } = await applyTenant(
            supabase
              .from("cliente_hh_tabela_itens")
              .update({ valor_base: valorBase, atualizado_em: new Date().toISOString() }),
            tenantId
          ).eq("id", itemId);

          if (updateErr) {
            result.erros.push({ linha: lineNum, erro: `Erro ao atualizar: ${updateErr.message}` });
          } else {
            result.atualizadas++;
          }
        } else {
          const { error: insertErr } = await supabase.from("cliente_hh_tabela_itens").insert({
            tenant_id: tenantId,
            tabela_id: tabelaId,
            especialidade_id: especialidadeId,
            valor_base: valorBase,
            criado_em: new Date().toISOString(),
            atualizado_em: new Date().toISOString(),
          });

          if (insertErr) {
            result.erros.push({ linha: lineNum, erro: `Erro ao inserir: ${insertErr.message}` });
          } else {
            result.criadas++;
          }
        }
      } catch (e: unknown) {
        const message = e instanceof Error ? e.message : "Erro desconhecido";
        result.erros.push({ linha: lineNum, erro: message });
      }
    }

    setBusy(false);
    setImportResult(result);
    await loadItens();
    await loadEspecialidades();
  }

  function formatDate(dateStr: string) {
    const d = new Date(dateStr);
    return d.toLocaleDateString("pt-BR");
  }

  function formatMoney(value: number) {
    return Number(value || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  if (!ready && permLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  if (!canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  if (!tabela) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando tabela...
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <button
          onClick={() => router.back()}
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          ← Voltar
        </button>
        <div>
          <h1 className="text-2xl font-semibold">Detalhe da Tabela HH</h1>
          <p className="text-sm text-zinc-400 mt-1">Itens com valores base por especialidade.</p>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 space-y-2">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-sm">
          <div>
            <div className="text-xs text-zinc-400">Cliente</div>
            <div className="font-medium">{tabela.clientes?.nome ?? `ID ${tabela.cliente_id}`}</div>
          </div>
          <div>
            <div className="text-xs text-zinc-400">Ano</div>
            <div className="font-medium">{tabela.ano}</div>
          </div>
          <div>
            <div className="text-xs text-zinc-400">Nome</div>
            <div className="font-medium">{tabela.nome}</div>
          </div>
          <div>
            <div className="text-xs text-zinc-400">Vigência início</div>
            <div className="font-medium">{formatDate(tabela.vigencia_inicio)}</div>
          </div>
          <div>
            <div className="text-xs text-zinc-400">Vigência fim</div>
            <div className="font-medium">{formatDate(tabela.vigencia_fim)}</div>
          </div>
          <div>
            <div className="text-xs text-zinc-400">Ativo</div>
            <div className="font-medium">{tabela.ativo ? "Sim" : "Não"}</div>
          </div>
        </div>
      </div>

      <div className="flex items-center justify-between gap-3">
        <div className="text-sm text-zinc-400">
          {itens.length} {itens.length === 1 ? "item" : "itens"}
        </div>
        <div className="flex items-center gap-2">
          <Can perm="os.write">
            <button
              onClick={() => setShowImport(true)}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Importar CSV
            </button>
          </Can>
          <Can perm="os.write">
            <button
              onClick={startNewItem}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              Adicionar Item
            </button>
          </Can>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">ID</th>
              <th className="px-4 py-3 text-left">Especialidade</th>
              <th className="px-4 py-3 text-right">Valor Base (R$)</th>
              <th className="px-4 py-3 text-center">Ações</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {itens.map((item) => (
              <tr key={item.id} className="hover:bg-zinc-900/40">
                <td className="px-4 py-3 text-zinc-400 tabular-nums">{item.id}</td>
                <td className="px-4 py-3 font-medium">
                  {item.hh_especialidades?.descricao ?? `ID ${item.especialidade_id}`}
                </td>
                <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoney(item.valor_base)}</td>
                <td className="px-4 py-3 text-center">
                  <div className="flex items-center justify-center gap-2">
                    <Can perm="os.write">
                      <button
                        onClick={() => startEditItem(item)}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                      >
                        Editar
                      </button>
                    </Can>
                    <Can perm="os.delete">
                      <button
                        onClick={() => deleteItem(item.id)}
                        disabled={busy}
                        className="px-3 py-1.5 rounded-md border border-red-700 bg-red-900/30 hover:bg-red-900/50 text-red-300"
                      >
                        Remover
                      </button>
                    </Can>
                  </div>
                </td>
              </tr>
            ))}

            {itens.length === 0 && (
              <tr>
                <td colSpan={4} className="px-4 py-6 text-zinc-400">
                  Nenhum item cadastrado. Adicione itens ou importe de um CSV.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {showItemForm && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">
                  {editingItemId ? "Editar Item" : "Adicionar Item"}
                </div>
                <div className="text-sm text-zinc-400">Preencha os campos abaixo.</div>
              </div>
              <button
                onClick={closeItemForm}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Especialidade *</div>
                <select
                  aria-label="Especialidade"
                  className="w-full px-3 py-2"
                  value={itemForm.especialidade_id ?? ""}
                  onChange={(e) =>
                    setItemForm((s) => ({ ...s, especialidade_id: e.target.value ? Number(e.target.value) : null }))
                  }
                >
                  <option value="">Selecione</option>
                  {especialidades.map((esp) => (
                    <option key={esp.id} value={esp.id}>
                      {esp.descricao}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Valor Base (R$) *</div>
                <input
                  aria-label="Valor base"
                  type="text"
                  inputMode="decimal"
                  className="w-full px-3 py-2"
                  value={itemForm.valor_base}
                  onChange={(e) => setItemForm((s) => ({ ...s, valor_base: parseDecimalBR(e.target.value) || 0 }))}
                  placeholder="0,00"
                />
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 flex justify-end gap-2">
              <button
                onClick={closeItemForm}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={saveItem}
                disabled={busy || !canEdit}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {busy ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}

      {showImport && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50 overflow-y-auto">
          <div className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl my-4">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Importar CSV</div>
                <div className="text-sm text-zinc-400">Cole o conteúdo do CSV abaixo.</div>
              </div>
              <button
                onClick={() => {
                  setShowImport(false);
                  setCsvText("");
                  setImportResult(null);
                }}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="border border-amber-700/50 bg-amber-500/10 rounded-lg p-3 text-sm text-amber-200">
                <div className="font-semibold mb-1">Formato esperado:</div>
                <ul className="list-disc list-inside space-y-1 text-xs">
                  <li>Cabeçalho opcional (descricao, preco)</li>
                  <li>Separador: ; ou ,</li>
                  <li>Colunas: descricao, preco (ex: &quot;Engenheiro;R$ 49,65&quot;)</li>
                  <li>Especialidades não existentes serão criadas automaticamente</li>
                  <li>Valores duplicados serão atualizados (upsert)</li>
                </ul>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Conteúdo do CSV</div>
                <textarea
                  aria-label="CSV"
                  className="w-full px-3 py-2 min-h-[200px] font-mono text-xs"
                  value={csvText}
                  onChange={(e) => setCsvText(e.target.value)}
                  placeholder="descricao;preco&#10;Engenheiro Eletricista;R$ 49,65&#10;Projetista Elétrico;R$ 38,00"
                />
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}

              {importResult && (
                <div className="border border-zinc-800 rounded-lg p-4 space-y-2">
                  <div className="font-semibold text-sm">Resultado da Importação</div>
                  <div className="grid grid-cols-2 gap-2 text-sm">
                    <div className="text-emerald-300">Criadas: {importResult.criadas}</div>
                    <div className="text-blue-300">Atualizadas: {importResult.atualizadas}</div>
                  </div>

                  {importResult.erros.length > 0 && (
                    <div className="space-y-1">
                      <div className="text-red-400 text-sm font-semibold">
                        Erros ({importResult.erros.length}):
                      </div>
                      <div className="max-h-32 overflow-y-auto space-y-1 text-xs">
                        {importResult.erros.map((e, i) => (
                          <div key={i} className="text-red-300">
                            Linha {e.linha}: {e.erro}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 flex justify-end gap-2">
              <button
                onClick={() => {
                  setShowImport(false);
                  setCsvText("");
                  setImportResult(null);
                }}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
              <button
                onClick={handleImportCSV}
                disabled={busy || !canEdit}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {busy ? "Importando..." : "Importar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
