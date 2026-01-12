"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ensureCurrentTenant } from "@/lib/tenant";
import { usePermissions } from "@/components/auth/PermissionsProvider";

type Colaborador = { id: string; nome: string; ativo: boolean };
type TipoHora = { id: string; codigo: string; descricao: string; fator: number; ativo: boolean };

type OSRow = {
  id: number;
  numero_os: string | null;
  cliente_nome: string | null;
  descricao_servico?: string | null;
  status: string | null;
};

type ApontamentoRow = {
  id: string;
  os_id: number;
  colaborador_id: string;
  data: string; // yyyy-mm-dd
  horas: number;
  tipo_hora_id: string | null;
  descricao: string | null;
  status: string;
  criado_em: string;
};

const feriadosCache = new Map<number, Set<string>>();
const feriadosPending = new Map<number, Promise<Set<string>>>();

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

function toNumberBR(v: string): number | null {
  const s = v.trim();
  if (!s) return null;
  const noCurrency = s.replace(/R\$\s?/gi, "").replace(/\s/g, "");
  const hasDot = noCurrency.includes(".");
  const hasComma = noCurrency.includes(",");
  let normalized = noCurrency;

  if (hasDot && hasComma) {
    const lastDot = noCurrency.lastIndexOf(".");
    const lastComma = noCurrency.lastIndexOf(",");
    if (lastComma > lastDot) {
      normalized = noCurrency.replace(/\./g, "").replace(",", ".");
    } else {
      normalized = noCurrency.replace(/,/g, "");
    }
  } else if (hasComma) {
    normalized = noCurrency.replace(",", ".");
  } else if (hasDot) {
    const dotCount = (noCurrency.match(/\./g) || []).length;
    normalized = dotCount > 1 ? noCurrency.replace(/\./g, "") : noCurrency;
  }

  const n = Number(normalized);
  return Number.isFinite(n) ? n : null;
}

function isWeekend(dateISO: string): "SAT" | "SUN" | null {
  const d = new Date(`${dateISO}T00:00:00`);
  const day = d.getDay();
  if (day === 6) return "SAT";
  if (day === 0) return "SUN";
  return null;
}

async function getNationalHolidays(year: number): Promise<Set<string>> {
  if (feriadosCache.has(year)) return feriadosCache.get(year)!;
  if (feriadosPending.has(year)) return feriadosPending.get(year)!;

  const promise = (async () => {
    try {
      const res = await fetch(`https://brasilapi.com.br/api/feriados/v1/${year}`);
      if (!res.ok) throw new Error(`BrasilAPI status ${res.status}`);
      const data = (await res.json()) as Array<{ date: string }>;
      const set = new Set<string>((data ?? []).map((f) => f.date));
      feriadosCache.set(year, set);
      return set;
    } catch (err) {
      console.error(err);
      return new Set<string>();
    } finally {
      feriadosPending.delete(year);
    }
  })();

  feriadosPending.set(year, promise);
  return promise;
}

async function isNationalHoliday(dateISO: string): Promise<boolean> {
  const year = Number(dateISO.slice(0, 4));
  if (!Number.isFinite(year)) return false;
  const set = await getNationalHolidays(year);
  return set.has(dateISO);
}

type HourPolicy =
  | { mode: "SINGLE"; items: Array<{ tipoCodigo: string; horas: number }> }
  | { mode: "SPLIT"; items: Array<{ tipoCodigo: string; horas: number }> };

async function computeHourPolicy(dateISO: string, horas: number): Promise<HourPolicy> {
  const weekend = isWeekend(dateISO);
  const holiday = await isNationalHoliday(dateISO);

  if (weekend === "SUN" || holiday) {
    return { mode: "SINGLE", items: [{ tipoCodigo: "EXTRA100", horas }] };
  }

  if (weekend === "SAT") {
    return { mode: "SINGLE", items: [{ tipoCodigo: "EXTRA50", horas }] };
  }

  if (horas > 9) {
    return {
      mode: "SPLIT",
      items: [
        { tipoCodigo: "NORMAL", horas: 9 },
        { tipoCodigo: "EXTRA50", horas: Number((horas - 9).toFixed(2)) },
      ],
    };
  }

  return { mode: "SINGLE", items: [{ tipoCodigo: "NORMAL", horas }] };
}

export default function ApontamentosPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId } = usePermissions();
  const searchParams = useSearchParams();
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  // filtros
  const [filtroOsId, setFiltroOsId] = useState<string>(""); // string p/ select
  const [filtroColabId, setFiltroColabId] = useState<string>("");

  // combos
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [tiposHoras, setTiposHoras] = useState<TipoHora[]>([]);
  const [osList, setOsList] = useState<OSRow[]>([]);

  // formulario novo apontamento
  const [osNumero, setOsNumero] = useState<string>("");
  const [osDbId, setOsDbId] = useState<number | null>(null);
  const [osDescricao, setOsDescricao] = useState<string>("");
  const [osDescLoading, setOsDescLoading] = useState(false);
  const [osDescError, setOsDescError] = useState<string | null>(null);
  const [osCliente, setOsCliente] = useState<string>("");
  const [osStatus, setOsStatus] = useState<string>("");
  const [showOsModal, setShowOsModal] = useState(false);
  const [osSearch, setOsSearch] = useState("");
  const [osSearchLoading, setOsSearchLoading] = useState(false);
  const [osSearchError, setOsSearchError] = useState<string | null>(null);
  const [osSearchResults, setOsSearchResults] = useState<OSRow[]>([]);
  const [colabId, setColabId] = useState<string>("");
  const [colabInput, setColabInput] = useState<string>("");
  const [data, setData] = useState<string>(todayISO());
  const [horasText, setHorasText] = useState<string>("");
  const [tipoHoraId, setTipoHoraId] = useState<string>(""); // empty = null
  const [descricao, setDescricao] = useState<string>("");
  const [tipoSugerido, setTipoSugerido] = useState<string>("");
  const [tipoSugeridoLoading, setTipoSugeridoLoading] = useState(false);
  const osDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const osSearchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const horasInputRef = useRef<HTMLInputElement | null>(null);

  const [apontamentos, setApontamentos] = useState<ApontamentoRow[]>([]);

  const ensureTenant = useCallback(async () => {
    try {
      await ensureCurrentTenant(supabase);
    } catch (e: unknown) {
      console.error("Erro ao garantir tenant atual:", e);
    }
  }, [supabase]);

  const carregarCombos = useCallback(async () => {
    await ensureTenant();
    const [{ data: c, error: e1 }, { data: th, error: e2 }, { data: os, error: e3 }] =
      await Promise.all([
        supabase.from("colaboradores").select("id,nome,ativo").eq("ativo", true).order("nome"),
        supabase.from("tipos_horas").select("id,codigo,descricao,fator,ativo").eq("ativo", true).order("codigo"),
        supabase
          .from("ordens_servico")
          .select("id,numero_os,cliente_nome,descricao_servico,status")
          .in("status", ["aberta", "em_andamento"])
          .order("id", { ascending: false })
          .limit(200),
      ]);

    if (e1) throw e1;
    if (e2) throw e2;
    if (e3) throw e3;

    setColaboradores((c ?? []) as Colaborador[]);
    setTiposHoras((th ?? []) as TipoHora[]);
    setOsList((os ?? []) as OSRow[]);
  }, [ensureTenant, supabase]);

  const carregarApontamentos = useCallback(async () => {
    setLoading(true);
    setMsg(null);
    try {
      await ensureTenant();
      const q = supabase
        .from("apontamentos_horas")
        .select("*")
        .order("data", { ascending: false })
        .order("criado_em", { ascending: false });

      if (osDbId) q.eq("os_id", osDbId);
      else if (filtroOsId) q.eq("os_id", Number(filtroOsId));
      if (filtroColabId) q.eq("colaborador_id", filtroColabId);

      const { data, error } = await q;
      if (error) throw error;
      setApontamentos((data ?? []) as ApontamentoRow[]);
    } catch (e: unknown) {
      console.error(e);
      setMsg(getErrorMessage(e, "Erro ao carregar apontamentos."));
    } finally {
      setLoading(false);
    }
  }, [ensureTenant, filtroColabId, filtroOsId, osDbId, supabase]);

  useEffect(() => {
    (async () => {
      try {
        setLoading(true);
        await carregarCombos();
        await carregarApontamentos();
      } catch (e: unknown) {
        console.error(e);
        setMsg(getErrorMessage(e, "Erro ao iniciar tela."));
      } finally {
        setLoading(false);
      }
    })();
  }, [carregarApontamentos, carregarCombos]);

  useEffect(() => {
    if (osDbId) {
      setFiltroOsId(String(osDbId));
      carregarApontamentos();
    }
  }, [carregarApontamentos, osDbId]);

  const fetchOsDescricao = useCallback(async (osDigitada: string) => {
    const trimmed = osDigitada.trim();

    if (!trimmed) {
      setOsDescricao("");
      setOsDbId(null);
      setOsDescError(null);
      setOsCliente("");
      setOsStatus("");
      return;
    }

    setOsDescLoading(true);
    setOsDescError(null);

    try {
      const isNumeric = /^\d+$/.test(trimmed);
      let found: OSRow | null = null;

      const base = supabase
        .from("ordens_servico")
        .select("id,numero_os,descricao_servico,cliente_nome,status");
      const byNumero = await base.eq("numero_os", trimmed).maybeSingle();
      if (byNumero.error) throw byNumero.error;
      found = byNumero.data ?? null;

      if (!found) {
        const { data: list, error: listErr } = await base
          .ilike("numero_os", `%${trimmed}%`)
          .limit(50);
        if (listErr) throw listErr;
        const rows = (list ?? []) as OSRow[];
        if (isNumeric) {
          found =
            rows.find((o) => {
              const num = String(o?.numero_os ?? "").replace(/\D/g, "").replace(/^0+/, "");
              return num === trimmed;
            }) ?? null;
        } else {
          found = rows[0] ?? null;
        }
      }

      if (!found) {
        setOsDescricao("");
        setOsDbId(null);
        setOsDescError("OS nao encontrada");
        setOsCliente("");
        setOsStatus("");
        return;
      }

      const desc = found?.descricao_servico ?? "";
      setOsDescricao(desc || "");
      setOsDbId(found?.id ?? null);
      setOsCliente(found?.cliente_nome ?? "");
      setOsStatus(found?.status ?? "");
    } catch (e: unknown) {
      console.error(e);
      setOsDescricao("");
      setOsDbId(null);
      setOsDescError("Erro ao buscar OS");
      setOsCliente("");
      setOsStatus("");
    } finally {
      setOsDescLoading(false);
    }
  }, [supabase]);

  const fetchOsById = useCallback(
    async (id: number) => {
      if (!Number.isFinite(id)) return false;
      setOsDescLoading(true);
      setOsDescError(null);

      try {
        const { data, error } = await supabase
          .from("ordens_servico")
          .select("id,numero_os,descricao_servico,cliente_nome,status")
          .eq("id", id)
          .maybeSingle();
        if (error) throw error;
        if (!data) return false;

        const numero = data.numero_os ?? String(data.id);
        setOsNumero(numero);
        setOsDescricao(data.descricao_servico ?? "");
        setOsDbId(data.id ?? null);
        setOsCliente(data.cliente_nome ?? "");
        setOsStatus(data.status ?? "");
        setOsDescError(null);
        return true;
      } catch (e: unknown) {
        console.error(e);
        setOsDescError("Erro ao buscar OS");
        setOsDescricao("");
        setOsDbId(null);
        setOsCliente("");
        setOsStatus("");
        return false;
      } finally {
        setOsDescLoading(false);
      }
    },
    [supabase]
  );

  useEffect(() => {
    const osParam = searchParams.get("os");
    if (!osParam) return;
    const normalized = osParam.trim();
    if (!normalized) return;
    const timer = setTimeout(() => {
      const isNumeric = /^\d+$/.test(normalized);
      if (isNumeric) {
        void fetchOsById(Number(normalized)).then((found) => {
          if (!found) {
            fetchOsDescricao(normalized);
          }
        });
        return;
      }
      fetchOsDescricao(normalized);
    }, 0);
    return () => clearTimeout(timer);
  }, [fetchOsById, fetchOsDescricao, searchParams]);

  const buscarOs = async (term: string) => {
    const trimmed = term.trim();
    if (!trimmed) {
      setOsSearchResults([]);
      setOsSearchError(null);
      return;
    }

    setOsSearchLoading(true);
    setOsSearchError(null);
    try {
      const { data, error } = await supabase
        .from("ordens_servico")
        .select("id,numero_os,cliente_nome,descricao_servico,status")
        .or(`numero_os.ilike.%${trimmed}%,cliente_nome.ilike.%${trimmed}%`)
        .eq("status", "em_andamento")
        .order("id", { ascending: false })
        .limit(50);
      if (error) throw error;
      setOsSearchResults((data ?? []) as OSRow[]);
    } catch (e: unknown) {
      console.error(e);
      setOsSearchError(getErrorMessage(e, "Erro ao buscar OS."));
    } finally {
      setOsSearchLoading(false);
    }
  };

  useEffect(() => {
    return () => {
      if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
      if (osSearchDebounceRef.current) clearTimeout(osSearchDebounceRef.current);
    };
  }, []);

  const totalHoras = apontamentos.reduce((acc, a) => acc + (Number(a.horas) || 0), 0);
  const osMap = useMemo(() => new Map(osList.map((o) => [o.id, o])), [osList]);
  const colMap = useMemo(() => new Map(colaboradores.map((c) => [c.id, c])), [colaboradores]);
  const tipoMap = useMemo(() => new Map(tiposHoras.map((t) => [t.id, t])), [tiposHoras]);
  const tipoByCodigo = useMemo(
    () => new Map(tiposHoras.map((t) => [t.codigo.toUpperCase(), t.id])),
    [tiposHoras]
  );
  const colabOptions = useMemo(
    () =>
      colaboradores.map((c, idx) => ({
        id: c.id,
        seq: String(idx + 1),
        nome: c.nome,
      })),
    [colaboradores]
  );

  useEffect(() => {
    let active = true;
    const horas = toNumberBR(horasText);

    if (!data || horas == null || horas <= 0) {
      setTipoSugerido("");
      return;
    }

    setTipoSugeridoLoading(true);
    (async () => {
      const policy = await computeHourPolicy(data, horas);
      if (!active) return;
      const label =
        policy.mode === "SPLIT"
          ? policy.items.map((i) => i.tipoCodigo).join(" + ")
          : policy.items[0]?.tipoCodigo ?? "";
      setTipoSugerido(label);

      const first = policy.items[0]?.tipoCodigo ?? "";
      const tipoId = tipoByCodigo.get(first);
      if (tipoId) setTipoHoraId(tipoId);
      setTipoSugeridoLoading(false);
    })();

    return () => {
      active = false;
    };
  }, [data, horasText, tipoByCodigo]);

  async function salvarApontamento(options?: { preserveHoras?: boolean; advanceDate?: boolean; keepFocus?: boolean }) {
    setMsg(null);

    if (!osDbId) return alert("Selecione uma OS.");
    if (osStatus !== "em_andamento") return alert("OS nao esta em andamento.");
    if (!colabId) return alert("Selecione um colaborador.");
    if (!data) return alert("Informe a data.");
    const horas = toNumberBR(horasText);
    if (horas == null || horas <= 0 || horas > 24) return alert("Horas invalidas (0 a 24).");

    setLoading(true);

    if (!tenantId) {
      setLoading(false);
      return alert("Tenant não encontrado. Recarregue a página.");
    }

    try {
      const { error: tenantErr } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (tenantErr) throw tenantErr;

      const policy = await computeHourPolicy(data, horas);
      const descricaoBase = descricao.trim();

      const payloadBase = {
        tenant_id: tenantId,
        os_id: osDbId,
        colaborador_id: colabId,
        data,
        status: "lancado",
      };

      const payloads = policy.items.map((item) => {
        const tipoId = tipoByCodigo.get(item.tipoCodigo);
        if (!tipoId) {
          throw new Error(`Tipo de hora nao encontrado: ${item.tipoCodigo}`);
        }
        const descFinal =
          policy.mode === "SPLIT" && descricaoBase
            ? `${descricaoBase} (${item.tipoCodigo})`
            : descricaoBase || null;
        return {
          ...payloadBase,
          horas: item.horas,
          tipo_hora_id: tipoId,
          descricao: descFinal,
        };
      });

      const { error } = await supabase.from("apontamentos_horas").insert(payloads);
      if (error) throw error;

      if (!options?.preserveHoras) {
        setHorasText("");
      }
      setDescricao("");
      setTipoHoraId("");
      if (options?.advanceDate && data) {
        const base = new Date(`${data}T00:00:00`);
        base.setDate(base.getDate() + 1);
        const yyyy = base.getFullYear();
        const mm = String(base.getMonth() + 1).padStart(2, "0");
        const dd = String(base.getDate()).padStart(2, "0");
        setData(`${yyyy}-${mm}-${dd}`);
      }
      if (options?.keepFocus) {
        setTimeout(() => {
          horasInputRef.current?.focus();
          horasInputRef.current?.select();
        }, 0);
      }
      await carregarApontamentos();
      setMsg("Apontamento lancado com sucesso.");
    } catch (e: unknown) {
      alert(getErrorMessage(e, "Erro ao salvar apontamento."));
    } finally {
      setLoading(false);
    }
  }

  async function excluirApontamento(id: string) {
    if (!confirm("Excluir este apontamento?")) return;
    setLoading(true);
    try {
      const { error } = await supabase.from("apontamentos_horas").delete().eq("id", id);
      if (error) throw error;
      await carregarApontamentos();
    } catch (e: unknown) {
      alert(getErrorMessage(e, "Erro ao excluir."));
    } finally {
      setLoading(false);
    }
  }

  const formatDateBR = (iso: string) => {
    if (!iso) return "-";
    const [yyyy, mm, dd] = iso.split("-");
    if (!yyyy || !mm || !dd) return iso;
    return `${dd}/${mm}/${yyyy}`;
  };

  return (
    <div style={{ padding: 16 }}>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginTop: 0 }}>Apontamento de horas</h1>

      {msg && (
        <div
          style={{
            marginTop: 10,
            padding: 10,
            border: "1px solid #333",
            borderRadius: 8,
            background: "rgba(255,255,255,0.04)",
          }}
        >
          {msg}
        </div>
      )}

      {/* FORM */}
      <div style={{ marginTop: 12, border: "1px solid #333", borderRadius: 10, padding: 12 }}>
        <div style={{ fontWeight: 700, marginBottom: 10 }}>Novo lancamento</div>

        <div style={{ display: "grid", gridTemplateColumns: "2fr 3fr 2fr 1fr", gap: 10 }}>
          <label>
            OS
            <input
              value={osNumero}
              onChange={(e) => {
                const value = e.target.value;
                setOsNumero(value);
                if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
                osDebounceRef.current = setTimeout(() => {
                  fetchOsDescricao(value);
                }, 300);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !osNumero.trim()) {
                  e.preventDefault();
                  setShowOsModal(true);
                  setOsSearch("");
                  setOsSearchResults([]);
                  setOsSearchError(null);
                }
              }}
              onBlur={(e) => fetchOsDescricao(e.target.value)}
              placeholder="Digite o numero da OS"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Descricao OS
            <input
              value={osDescLoading ? "Buscando..." : osDescError ? osDescError : osDescricao || "-"}
              readOnly
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Cliente
            <input
              value={osDescLoading ? "Buscando..." : osDescError ? "-" : osCliente || "-"}
              readOnly
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Status
            <input
              value={osDescLoading ? "Buscando..." : osDescError ? "-" : osStatus || "-"}
              readOnly
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr 1fr 2fr", gap: 10, marginTop: 10 }}>
          <label>
            Colaborador
            <input
              value={colabInput}
              onChange={(e) => {
                const value = e.target.value;
                setColabInput(value);
                const trimmed = value.trim();
                if (!trimmed) {
                  setColabId("");
                  return;
                }
                const seqMatch = trimmed.match(/^\d+/);
                const seq = seqMatch ? seqMatch[0] : "";
                const bySeq = colabOptions.find((c) => c.seq === seq);
                if (bySeq) {
                  setColabId(bySeq.id);
                  return;
                }
                setColabId("");
              }}
              list="colaborador-options"
              placeholder="Digite o ID sequencial do colaborador"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
            <datalist id="colaborador-options">
              {colabOptions.map((c) => (
                <option key={c.id} value={`${c.seq} - ${c.nome}`} />
              ))}
            </datalist>
          </label>

          <label>
            Data
            <input
              type="date"
              value={data}
              onChange={(e) => setData(e.target.value)}
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Horas
            <input
              ref={horasInputRef}
              value={horasText}
              onChange={(e) => setHorasText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  salvarApontamento({ preserveHoras: true, advanceDate: true, keepFocus: true });
                }
              }}
              placeholder="Ex: 8,00"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <label>
            Tipo
            <select
              value={tipoHoraId}
              onChange={(e) => setTipoHoraId(e.target.value)}
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            >
              <option value="">(Normal)</option>
              {tiposHoras.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.codigo} - {t.descricao} (x{Number(t.fator).toFixed(2)})
                </option>
              ))}
            </select>
            <div className="text-xs text-zinc-400 mt-1">
              Tipo sugerido: {tipoSugeridoLoading ? "calculando..." : tipoSugerido || "-"}
            </div>
          </label>
        </div>

        <div style={{ marginTop: 10, display: "grid", gridTemplateColumns: "1fr auto", gap: 10 }}>
          <label>
            Descricao
            <input
              value={descricao}
              onChange={(e) => setDescricao(e.target.value)}
              placeholder="Ex: Montagem painel, passagem de cabos..."
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            />
          </label>

          <button
            onClick={() => salvarApontamento()}
            disabled={loading || osStatus !== "em_andamento"}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            style={{ alignSelf: "end", height: 36 }}
          >
            Salvar
          </button>
        </div>
      </div>

      {/* FILTROS + LISTA */}
      <div style={{ marginTop: 14, border: "1px solid #333", borderRadius: 10, padding: 12 }}>
        <div style={{ display: "flex", gap: 10, alignItems: "end", flexWrap: "wrap" }}>
          <label className="flex flex-col gap-1">
            <span>Filtrar OS</span>
            <select
              value={filtroOsId}
              onChange={(e) => setFiltroOsId(e.target.value)}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            >
              <option value="">Todas</option>
              {osList.map((o) => (
                <option key={o.id} value={String(o.id)}>
                  {o.numero_os}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1">
            <span>Filtrar Colaborador</span>
            <select
              value={filtroColabId}
              onChange={(e) => setFiltroColabId(e.target.value)}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
            >
              <option value="">Todos</option>
              {colaboradores.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nome}
                </option>
              ))}
            </select>
          </label>

          <button
            onClick={carregarApontamentos}
            disabled={loading}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>

          <div style={{ marginLeft: "auto", opacity: 0.9 }}>
            Total horas no filtro: <b>{totalHoras.toFixed(2)}</b>
          </div>
        </div>

        <div style={{ marginTop: 12, border: "1px solid #222", borderRadius: 8, overflow: "hidden" }}>
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ textAlign: "left" }}>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Data</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Colaborador</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Horas</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Tipo</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>OS / Descricao</th>
                  <th style={{ padding: 10, borderBottom: "1px solid #333" }}>Cliente</th>
                </tr>
              </thead>
              <tbody>
                {apontamentos.map((a) => {
                  const os = osMap.get(a.os_id);
                  const col = colMap.get(a.colaborador_id);
                  const tipo = a.tipo_hora_id ? tipoMap.get(a.tipo_hora_id) : null;
                  const osDesc = os?.descricao_servico ?? "-";
                  const clienteNome = os?.cliente_nome ?? "-";

                  return (
                    <tr
                      key={a.id}
                      className="hover:bg-zinc-900/40 cursor-pointer"
                      title="Clique para excluir"
                      onClick={() => excluirApontamento(a.id)}
                    >
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{formatDateBR(a.data)}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{col?.nome ?? a.colaborador_id}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{Number(a.horas).toFixed(2)}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{tipo ? tipo.codigo : "NORMAL"}</td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>
                        {a.os_id} - {osDesc}
                      </td>
                      <td style={{ padding: 10, borderBottom: "1px solid #222" }}>{clienteNome}</td>
                    </tr>
                  );
                })}

                {apontamentos.length === 0 && (
                  <tr>
                    <td style={{ padding: 10 }} colSpan={6}>
                      Nenhum apontamento no periodo.
                    </td>
                  </tr>
                )}
            </tbody>
          </table>
        </div>
      </div>

      {showOsModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Buscar OS</div>
                <div className="text-sm text-zinc-400">Digite numero da OS ou cliente para buscar.</div>
              </div>
              <button
                onClick={() => setShowOsModal(false)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Buscar</div>
                <input
                  value={osSearch}
                  onChange={(e) => {
                    const value = e.target.value;
                    setOsSearch(value);
                    if (osSearchDebounceRef.current) clearTimeout(osSearchDebounceRef.current);
                    osSearchDebounceRef.current = setTimeout(() => {
                      buscarOs(value);
                    }, 300);
                  }}
                  placeholder="Ex: 43 ou nome do cliente"
                  className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                />
              </div>

              {osSearchLoading && <div className="text-sm text-zinc-400">Buscando...</div>}
              {osSearchError && <div className="text-sm text-red-400">{osSearchError}</div>}

              <div className="border border-zinc-800 rounded-lg overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/70">
                    <tr className="text-zinc-200">
                      <th className="px-3 py-2 text-left">OS</th>
                      <th className="px-3 py-2 text-left">Cliente</th>
                      <th className="px-3 py-2 text-left">Descricao</th>
                      <th className="px-3 py-2 text-center">Acao</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-800">
                    {osSearchResults.map((o) => (
                      <tr key={o.id} className="hover:bg-zinc-900/40">
                        <td className="px-3 py-2">{o.numero_os}</td>
                        <td className="px-3 py-2">{o.cliente_nome || "-"}</td>
                        <td className="px-3 py-2">{o.descricao_servico || "-"}</td>
                        <td className="px-3 py-2 text-center">
                          <button
                            onClick={() => {
                              const numero = o.numero_os ?? String(o.id);
                              setOsNumero(numero);
                              setShowOsModal(false);
                              if (o.numero_os) {
                                fetchOsDescricao(o.numero_os);
                              } else {
                                fetchOsById(o.id);
                              }
                            }}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            Selecionar
                          </button>
                        </td>
                      </tr>
                    ))}
                    {!osSearchLoading && osSearchResults.length === 0 && osSearch.trim() !== "" && (
                      <tr>
                        <td colSpan={4} className="px-3 py-4 text-zinc-400">
                          Nenhuma OS encontrada.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
