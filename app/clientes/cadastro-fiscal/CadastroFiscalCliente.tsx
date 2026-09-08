"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import {
  INDICADOR_IE_OPTIONS,
  somenteDigitos,
  validarClienteFiscal,
  type ClienteFiscal,
  type IndicadorIe,
  type PendenciaClienteFiscal,
} from "@/lib/nfe/clienteFiscal";

type ClienteRow = ClienteFiscal & {
  id: number;
  nome: string;
  email: string | null;
  ativo: boolean;
};

type ClienteForm = {
  nome: string;
  razao_social: string;
  documento: string;
  email: string;
  // Destinatario preferido do XML + DANFE da NF-e (tela de ciclo de vida); vazio = usa o e-mail principal.
  email_financeiro: string;
  inscricao_estadual: string;
  indicador_ie: "" | IndicadorIe;
  cep: string;
  logradouro: string;
  numero_endereco: string;
  complemento: string;
  bairro: string;
  cidade: string;
  uf: string;
  codigo_ibge_municipio: string;
  // NFS-e (tomador): decisoes humanas, nunca deduzidas. "" = nao decidido.
  inscricao_municipal: string;
  email_nfse: string;
  iss_retido: "" | "sim" | "nao";
  retem_pcc: "" | "sim" | "nao";
  retem_irrf: "" | "sim" | "nao";
  retem_inss: "" | "sim" | "nao";
  // Regime do tomador: optante do Simples nao sofre CRF (Lei 10.833/2003 art. 30 §2). "" = nao informado (aviso na nota).
  optante_simples: "" | "sim" | "nao";
  // Substituto tributario do ISS (orgao publico, banco, hospital, concessionaria): retem o ISS nos servicos 14.01/14.06 (contador, 06/09/2026).
  iss_substituto_tributario: boolean;
  // Template da discriminacao da NFS-e deste tomador (segmentos "|", tokens {RESULTADO} {PEDIDO} {ITEM} {VENCIMENTO} {DATAS} {OS} {FRASE_LEGAL} {ISS} {OBSERVACAO}).
  nfse_discriminacao_template: string;
};
type ClienteNfseRow = { email_financeiro?: string | null; inscricao_municipal?: string | null; email_nfse?: string | null; iss_retido?: boolean | null; retem_pcc?: boolean | null; retem_irrf?: boolean | null; retem_inss?: boolean | null; optante_simples?: boolean | null; iss_substituto_tributario?: boolean | null; nfse_discriminacao_template?: string | null };
function triTexto(value: boolean | null | undefined): "" | "sim" | "nao" { return value === true ? "sim" : value === false ? "nao" : ""; }
function triValor(value: "" | "sim" | "nao"): boolean | null { return value === "sim" ? true : value === "nao" ? false : null; }

type Municipio = { codigo_ibge: string; nome: string; uf: string };
type FiltroStatus = "pendentes" | "todos" | "prontos";

const CLIENTE_FIELDS = [
  "id",
  "nome",
  "razao_social",
  "documento",
  "email",
  "email_financeiro",
  "inscricao_estadual",
  "indicador_ie",
  "cep",
  "logradouro",
  "numero_endereco",
  "complemento",
  "bairro",
  "cidade",
  "uf",
  "codigo_ibge_municipio",
  "ativo",
  "inscricao_municipal",
  "email_nfse",
  "iss_retido",
  "retem_pcc",
  "retem_irrf",
  "retem_inss",
  "optante_simples",
  "iss_substituto_tributario",
  "nfse_discriminacao_template",
].join(",");

function texto(value: unknown): string {
  return String(value ?? "").trim();
}

function formFromRow(row: ClienteRow): ClienteForm {
  return {
    nome: texto(row.nome),
    razao_social: texto(row.razao_social),
    documento: texto(row.documento),
    email: texto(row.email),
    email_financeiro: texto((row as ClienteNfseRow).email_financeiro),
    inscricao_estadual: texto(row.inscricao_estadual),
    indicador_ie: (["1", "2", "9"] as string[]).includes(texto(row.indicador_ie))
      ? (texto(row.indicador_ie) as IndicadorIe)
      : "",
    cep: texto(row.cep),
    logradouro: texto(row.logradouro),
    numero_endereco: texto(row.numero_endereco),
    complemento: texto(row.complemento),
    bairro: texto(row.bairro),
    cidade: texto(row.cidade),
    uf: texto(row.uf),
    codigo_ibge_municipio: texto(row.codigo_ibge_municipio),
    inscricao_municipal: texto((row as ClienteNfseRow).inscricao_municipal),
    email_nfse: texto((row as ClienteNfseRow).email_nfse),
    iss_retido: triTexto((row as ClienteNfseRow).iss_retido),
    retem_pcc: triTexto((row as ClienteNfseRow).retem_pcc),
    retem_irrf: triTexto((row as ClienteNfseRow).retem_irrf),
    retem_inss: triTexto((row as ClienteNfseRow).retem_inss),
    optante_simples: triTexto((row as ClienteNfseRow).optante_simples),
    iss_substituto_tributario: (row as ClienteNfseRow).iss_substituto_tributario === true,
    nfse_discriminacao_template: texto((row as ClienteNfseRow).nfse_discriminacao_template),
  };
}

function vazio(): ClienteForm {
  return formFromRow({ id: 0, nome: "", email: null, ativo: true });
}

function pendencias(row: ClienteFiscal): PendenciaClienteFiscal[] {
  return validarClienteFiscal(row);
}

function labelPendencia(total: number): string {
  if (total === 0) return "Pronto para a solicitação";
  return `${total} ${total === 1 ? "pendência" : "pendências"}`;
}

export default function CadastroFiscalCliente() {
  const supabase = useMemo(() => getSupabaseBrowser(), []);
  const te = useTenantEmpresa();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const clienteParam = Number(searchParams.get("cliente_id"));
  const filtro = (["pendentes", "todos", "prontos"] as string[]).includes(searchParams.get("status") ?? "")
    ? (searchParams.get("status") as FiltroStatus)
    : "pendentes";
  const busca = searchParams.get("q") ?? "";

  const [rows, setRows] = useState<ClienteRow[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(Number.isInteger(clienteParam) && clienteParam > 0 ? clienteParam : null);
  const [form, setForm] = useState<ClienteForm>(vazio());
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [municipios, setMunicipios] = useState<Municipio[]>([]);
  const [buscandoMunicipio, setBuscandoMunicipio] = useState(false);
  const [pilotClienteId, setPilotClienteId] = useState<number | null>(null);

  const setUrl = useCallback((changes: Record<string, string | null>) => {
    const next = new URLSearchParams(searchParams.toString());
    for (const [key, value] of Object.entries(changes)) {
      if (value) next.set(key, value); else next.delete(key);
    }
    const query = next.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  }, [pathname, router, searchParams]);

  const load = useCallback(async () => {
    if (!tenantId || !empresaId) return;
    setLoading(true);
    setError(null);

    const [clientesResult, pilotoResult] = await Promise.all([
      supabase
        .from("clientes")
        .select(CLIENTE_FIELDS)
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("ativo", true)
        .order("nome", { ascending: true })
        .limit(1000),
      supabase
        .schema("f")
        .from("solicitacao_faturamento")
        .select("cliente_id")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .in("status", ["RASCUNHO", "PREVIA", "APROVADA"])
        .not("cliente_id", "is", null)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);

    if (clientesResult.error) {
      setError(clientesResult.error.message);
      setLoading(false);
      return;
    }

    const list = (clientesResult.data ?? []) as unknown as ClienteRow[];
    const pilotId = pilotoResult.error ? null : Number(pilotoResult.data?.cliente_id ?? 0) || null;
    setRows(list);
    setPilotClienteId(pilotId);

    const requested = Number.isInteger(clienteParam) && clienteParam > 0 ? clienteParam : null;
    const preferred = requested && list.some((row) => row.id === requested)
      ? requested
      : pilotId && list.some((row) => row.id === pilotId)
        ? pilotId
        : list.find((row) => pendencias(row).length > 0)?.id ?? list[0]?.id ?? null;

    setSelectedId((current) => current && list.some((row) => row.id === current) ? current : preferred);
    setLoading(false);
  }, [clienteParam, empresaId, supabase, tenantId]);

  useEffect(() => {
    // A consulta assíncrona sincroniza a tela com a empresa ativa.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const selected = useMemo(() => rows.find((row) => row.id === selectedId) ?? null, [rows, selectedId]);

  useEffect(() => {
    if (!selected) return;
    // Trocar o cliente substitui o formulário inteiro; não há estado parcial a preservar.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setForm(formFromRow(selected));
    setMunicipios([]);
    if (clienteParam !== selected.id) setUrl({ cliente_id: String(selected.id) });
  }, [clienteParam, selected, setUrl]);

  const rowsFiltradas = useMemo(() => {
    const term = busca.trim().toLocaleLowerCase("pt-BR");
    return rows.filter((row) => {
      const total = pendencias(row).length;
      if (filtro === "pendentes" && total === 0) return false;
      if (filtro === "prontos" && total > 0) return false;
      if (!term) return true;
      return `${row.nome} ${row.razao_social ?? ""} ${row.documento ?? ""}`.toLocaleLowerCase("pt-BR").includes(term);
    });
  }, [busca, filtro, rows]);

  const formPendencias = useMemo(() => pendencias(form), [form]);
  const errosPorCampo = useMemo(() => new Map(formPendencias.map((item) => [item.campo, item.mensagem])), [formPendencias]);

  function selecionar(row: ClienteRow) {
    setError(null);
    setSuccess(null);
    setMunicipios([]);
    setSelectedId(row.id);
    setUrl({ cliente_id: String(row.id) });
  }

  function update<K extends keyof ClienteForm>(key: K, value: ClienteForm[K]) {
    setForm((current) => ({ ...current, [key]: value }));
    setSuccess(null);
  }

  async function buscarMunicipio() {
    const uf = form.uf.trim().toUpperCase();
    const cidade = form.cidade.trim();
    if (!/^[A-Z]{2}$/.test(uf) || cidade.length < 2) {
      setError("Informe a UF e ao menos 2 letras do município para consultar o IBGE.");
      return;
    }

    setBuscandoMunicipio(true);
    setError(null);
    const { data, error: municipioError } = await supabase
      .from("municipios_ibge")
      .select("codigo_ibge,nome,uf")
      .eq("uf", uf)
      .ilike("nome", `%${cidade}%`)
      .order("nome")
      .limit(15);
    setBuscandoMunicipio(false);

    if (municipioError) {
      setError(municipioError.message);
      return;
    }
    setMunicipios((data ?? []) as Municipio[]);
    if (!data?.length) setError("Nenhum município encontrado. Confira o nome/UF ou informe o código IBGE manualmente.");
  }

  function escolherMunicipio(municipio: Municipio) {
    setForm((current) => ({
      ...current,
      cidade: municipio.nome.toUpperCase(),
      uf: municipio.uf,
      codigo_ibge_municipio: municipio.codigo_ibge,
    }));
    setMunicipios([]);
    setError(null);
  }

  async function salvar() {
    if (!tenantId || !empresaId || !selectedId) {
      setError("Contexto de tenant, empresa ou cliente não carregado.");
      return;
    }
    if (formPendencias.length > 0) {
      setError("Corrija os campos destacados antes de concluir o cadastro fiscal.");
      return;
    }

    setSaving(true);
    setError(null);
    setSuccess(null);
    const payload = {
      nome: form.nome.trim().toUpperCase(),
      razao_social: form.razao_social.trim().toUpperCase(),
      documento: somenteDigitos(form.documento),
      email: form.email.trim() || null,
      email_financeiro: form.email_financeiro.trim().toLowerCase() || null,
      inscricao_estadual: form.inscricao_estadual.trim().toUpperCase() || null,
      indicador_ie: form.indicador_ie,
      cep: somenteDigitos(form.cep),
      logradouro: form.logradouro.trim().toUpperCase(),
      numero_endereco: form.numero_endereco.trim().toUpperCase(),
      complemento: form.complemento.trim().toUpperCase() || null,
      bairro: form.bairro.trim().toUpperCase(),
      cidade: form.cidade.trim().toUpperCase(),
      uf: form.uf.trim().toUpperCase(),
      codigo_ibge_municipio: somenteDigitos(form.codigo_ibge_municipio),
      inscricao_municipal: somenteDigitos(form.inscricao_municipal) || null,
      email_nfse: form.email_nfse.trim().toLowerCase() || null,
      iss_retido: triValor(form.iss_retido),
      retem_pcc: triValor(form.retem_pcc),
      retem_irrf: triValor(form.retem_irrf),
      retem_inss: triValor(form.retem_inss),
      optante_simples: triValor(form.optante_simples),
      iss_substituto_tributario: form.iss_substituto_tributario,
      nfse_discriminacao_template: form.nfse_discriminacao_template.trim() || null,
      atualizado_em: new Date().toISOString(),
    };

    const { data, error: saveError } = await supabase
      .from("clientes")
      .update(payload)
      .eq("id", selectedId)
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .select("id")
      .maybeSingle();

    if (saveError) {
      setError(saveError.message);
      setSaving(false);
      return;
    }
    if (!data?.id) {
      setError("O cliente não foi alterado. Confira a empresa selecionada e sua permissão de cadastro.");
      setSaving(false);
      return;
    }

    await load();
    setSuccess("Cadastro fiscal salvo. Estes dados já podem ser congelados na solicitação do piloto.");
    setSaving(false);
  }

  function proximoPendente() {
    const pending = rows.filter((row) => row.id !== selectedId && pendencias(row).length > 0);
    if (pending[0]) selecionar(pending[0]);
  }

  const fieldClass = (campo: keyof ClienteFiscal) =>
    `w-full px-3 py-2 ${errosPorCampo.has(campo) ? "border-red-500/70 focus:border-red-400" : "border-zinc-700"}`;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="text-xs text-zinc-500">Clientes › NF-e</div>
          <h1 className="mt-1 text-2xl font-semibold">Correção cadastral para NF-e</h1>
          <p className="mt-1 text-sm text-zinc-400">Complete e confirme um destinatário por vez. Nenhum valor de IE é inferido.</p>
        </div>
        <div className="flex gap-2">
          <Link href="/clientes" className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 hover:bg-zinc-800">Clientes</Link>
          <button type="button" onClick={() => void load()} className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 hover:bg-zinc-800">Atualizar</button>
        </div>
      </div>

      <div className="rounded-xl border border-sky-500/30 bg-sky-500/10 p-4 text-sm text-sky-100">
        <div className="font-semibold">Como confirmar o indicador de IE</div>
        <p className="mt-1 text-sky-100/80">
          Use o cadastro fiscal do cliente ou uma consulta oficial. Ter IE preenchida não prova que ele é contribuinte, e o código 9 pode possuir IE.
          A escolha abaixo é humana e será a fonte mestre do cadastro.
        </p>
      </div>

      <div className="grid gap-4 xl:grid-cols-[360px_minmax(0,1fr)]">
        <aside className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
          <div className="space-y-3 border-b border-zinc-800 p-4">
            <div className="flex items-center justify-between gap-2">
              <div className="font-medium">Fila de clientes</div>
              <span className="text-xs text-zinc-500">{rowsFiltradas.length} exibidos</span>
            </div>
            <input
              className="w-full px-3 py-2"
              value={busca}
              onChange={(event) => setUrl({ q: event.target.value || null })}
              placeholder="Nome ou CPF/CNPJ"
            />
            <div className="grid grid-cols-3 gap-1 rounded-lg bg-zinc-900 p-1 text-xs">
              {(["pendentes", "todos", "prontos"] as FiltroStatus[]).map((value) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setUrl({ status: value === "pendentes" ? null : value })}
                  className={`rounded-md px-2 py-2 capitalize ${filtro === value ? "bg-zinc-700 text-white" : "text-zinc-400 hover:text-zinc-200"}`}
                >
                  {value}
                </button>
              ))}
            </div>
          </div>
          <div className="max-h-[680px] overflow-y-auto">
            {loading && <div className="p-4 text-sm text-zinc-500">Carregando...</div>}
            {!loading && rowsFiltradas.map((row) => {
              const total = pendencias(row).length;
              const isPilot = pilotClienteId === row.id;
              return (
                <button
                  key={row.id}
                  type="button"
                  onClick={() => selecionar(row)}
                  className={`block w-full border-b border-zinc-900 px-4 py-3 text-left hover:bg-zinc-900/70 ${selectedId === row.id ? "bg-zinc-900 ring-1 ring-inset ring-sky-500/50" : ""}`}
                >
                  <div className="flex items-start justify-between gap-2">
                    <span className="font-medium text-zinc-100">{row.nome}</span>
                    {isPilot && <span className="rounded-full border border-sky-500/40 bg-sky-500/10 px-2 py-0.5 text-[10px] text-sky-300">PILOTO</span>}
                  </div>
                  <div className="mt-1 text-xs text-zinc-500">#{row.id} · {row.documento || "sem documento"}</div>
                  <div className={`mt-2 text-xs ${total === 0 ? "text-emerald-300" : "text-amber-300"}`}>{labelPendencia(total)}</div>
                </button>
              );
            })}
            {!loading && rowsFiltradas.length === 0 && <div className="p-6 text-center text-sm text-zinc-500">Nenhum cliente neste filtro.</div>}
          </div>
        </aside>

        <main className="rounded-xl border border-zinc-800 bg-zinc-950">
          {!selected ? (
            <div className="p-8 text-sm text-zinc-500">Selecione um cliente para corrigir.</div>
          ) : (
            <>
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-zinc-800 p-4">
                <div>
                  <div className="font-semibold">{selected.nome}</div>
                  <div className="mt-1 text-xs text-zinc-500">Cliente #{selected.id} · alteração limitada à empresa ativa</div>
                </div>
                <span className={`rounded-full border px-3 py-1 text-xs ${formPendencias.length === 0 ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-300" : "border-amber-500/30 bg-amber-500/10 text-amber-300"}`}>
                  {labelPendencia(formPendencias.length)}
                </span>
              </div>

              <div className="space-y-6 p-4 md:p-6">
                {error && <div role="alert" className="rounded-md border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error}</div>}
                {success && <div role="status" className="rounded-md border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-200">{success}</div>}

                <section className="space-y-3">
                  <div>
                    <h2 className="font-semibold">Identificação</h2>
                    <p className="text-xs text-zinc-500">Dados que identificarão o destinatário no XML.</p>
                  </div>
                  <div className="grid gap-3 md:grid-cols-2">
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-400">Nome de exibição</span>
                      <input className="w-full px-3 py-2" value={form.nome} onChange={(event) => update("nome", event.target.value)} />
                    </label>
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-400">Razão social / nome completo *</span>
                      <input className={fieldClass("razao_social")} value={form.razao_social} onChange={(event) => update("razao_social", event.target.value)} />
                      {errosPorCampo.get("razao_social") && <span className="text-xs text-red-300">{errosPorCampo.get("razao_social")}</span>}
                    </label>
                    <label className="space-y-1">
                      <span className="text-xs text-zinc-400">CPF/CNPJ *</span>
                      <input className={fieldClass("documento")} value={form.documento} onChange={(event) => update("documento", event.target.value)} inputMode="numeric" />
                      {errosPorCampo.get("documento") && <span className="text-xs text-red-300">{errosPorCampo.get("documento")}</span>}
                    </label>
                    <label className="space-y-1">
                      <span className="text-xs text-zinc-400">E-mail para envio</span>
                      <input className="w-full px-3 py-2" type="email" value={form.email} onChange={(event) => update("email", event.target.value)} />
                    </label>
                    <label className="space-y-1">
                      <span className="text-xs text-zinc-400">E-mail financeiro (XML e DANFE da NF-e)</span>
                      <input className="w-full px-3 py-2" type="email" value={form.email_financeiro} onChange={(event) => update("email_financeiro", event.target.value)} placeholder="recebimento@cliente.com.br" />
                      <span className="text-[11px] text-zinc-500">A tela da NF-e sugere este endereço primeiro; vazio, usa o e-mail para envio.</span>
                    </label>
                  </div>
                </section>

                <section className="rounded-xl border border-sky-500/30 bg-sky-950/20 p-4">
                  <h2 className="font-semibold text-sky-100">Situação perante o ICMS</h2>
                  <div className="mt-3 grid gap-3 md:grid-cols-2">
                    <label className="space-y-1">
                      <span className="text-xs text-zinc-300">Indicador de IE (indIEDest) *</span>
                      <select
                        className={fieldClass("indicador_ie")}
                        value={form.indicador_ie}
                        onChange={(event) => update("indicador_ie", event.target.value as ClienteForm["indicador_ie"])}
                      >
                        <option value="">Selecione manualmente...</option>
                        {INDICADOR_IE_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                      </select>
                      {errosPorCampo.get("indicador_ie") && <span className="text-xs text-red-300">{errosPorCampo.get("indicador_ie")}</span>}
                    </label>
                    <label className="space-y-1">
                      <span className="text-xs text-zinc-300">Inscrição estadual {form.indicador_ie === "1" ? "*" : "(se houver)"}</span>
                      <input className={fieldClass("inscricao_estadual")} value={form.inscricao_estadual} onChange={(event) => update("inscricao_estadual", event.target.value)} />
                      {errosPorCampo.get("inscricao_estadual") && <span className="text-xs text-red-300">{errosPorCampo.get("inscricao_estadual")}</span>}
                    </label>
                  </div>
                  <div className="mt-3 rounded-lg border border-zinc-800 bg-zinc-950/60 p-3 text-xs text-zinc-400">
                    <strong className="text-zinc-200">Não inferir:</strong> IE preenchida não determina o indicador. O código 9 significa não contribuinte e pode ser usado mesmo quando existe IE por outra finalidade. Para o código 2, a NF-e não envia a tag IE.
                  </div>
                </section>

                <section className="space-y-3">
                  <div>
                    <h2 className="font-semibold">Endereço fiscal</h2>
                    <p className="text-xs text-zinc-500">O município e o código IBGE devem representar o mesmo endereço.</p>
                  </div>
                  <div className="grid gap-3 md:grid-cols-6">
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-400">CEP *</span>
                      <input className={fieldClass("cep")} value={form.cep} onChange={(event) => update("cep", event.target.value)} inputMode="numeric" />
                      {errosPorCampo.get("cep") && <span className="text-xs text-red-300">{errosPorCampo.get("cep")}</span>}
                    </label>
                    <label className="space-y-1 md:col-span-3">
                      <span className="text-xs text-zinc-400">Logradouro *</span>
                      <input className={fieldClass("logradouro")} value={form.logradouro} onChange={(event) => update("logradouro", event.target.value)} />
                      {errosPorCampo.get("logradouro") && <span className="text-xs text-red-300">{errosPorCampo.get("logradouro")}</span>}
                    </label>
                    <label className="space-y-1 md:col-span-1">
                      <span className="text-xs text-zinc-400">Número *</span>
                      <input className={fieldClass("numero_endereco")} value={form.numero_endereco} onChange={(event) => update("numero_endereco", event.target.value)} />
                    </label>
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-400">Complemento</span>
                      <input className="w-full px-3 py-2" value={form.complemento} onChange={(event) => update("complemento", event.target.value)} />
                    </label>
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-400">Bairro *</span>
                      <input className={fieldClass("bairro")} value={form.bairro} onChange={(event) => update("bairro", event.target.value)} />
                    </label>
                    <label className="space-y-1 md:col-span-1">
                      <span className="text-xs text-zinc-400">UF *</span>
                      <input className={fieldClass("uf")} value={form.uf} maxLength={2} onChange={(event) => update("uf", event.target.value.toUpperCase())} />
                    </label>
                    <div className="space-y-1 md:col-span-3">
                      <label className="text-xs text-zinc-400" htmlFor="cidade-fiscal">Município *</label>
                      <div className="flex gap-2">
                        <input id="cidade-fiscal" className={fieldClass("cidade")} value={form.cidade} onChange={(event) => update("cidade", event.target.value)} />
                        <button type="button" disabled={buscandoMunicipio} onClick={() => void buscarMunicipio()} className="shrink-0 rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm hover:bg-zinc-800">
                          {buscandoMunicipio ? "Buscando..." : "Conferir IBGE"}
                        </button>
                      </div>
                    </div>
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-400">Código IBGE *</span>
                      <input className={fieldClass("codigo_ibge_municipio")} value={form.codigo_ibge_municipio} maxLength={7} inputMode="numeric" onChange={(event) => update("codigo_ibge_municipio", somenteDigitos(event.target.value).slice(0, 7))} />
                      {errosPorCampo.get("codigo_ibge_municipio") && <span className="text-xs text-red-300">{errosPorCampo.get("codigo_ibge_municipio")}</span>}
                    </label>
                  </div>
                  {municipios.length > 0 && (
                    <div className="rounded-lg border border-zinc-700 bg-zinc-900 p-2">
                      <div className="px-2 pb-2 text-xs text-zinc-500">Escolha o município oficial:</div>
                      <div className="grid gap-1 md:grid-cols-2">
                        {municipios.map((municipio) => (
                          <button key={municipio.codigo_ibge} type="button" onClick={() => escolherMunicipio(municipio)} className="rounded-md px-3 py-2 text-left text-sm hover:bg-zinc-800">
                            {municipio.nome} / {municipio.uf} <span className="text-zinc-500">· {municipio.codigo_ibge}</span>
                          </button>
                        ))}
                      </div>
                    </div>
                  )}
                </section>

                <section className="rounded-lg border border-zinc-800 bg-zinc-900/40 p-4">
                  <div className="text-sm font-semibold text-zinc-100">NFS-e · tomador de serviço</div>
                  <p className="mt-1 text-xs text-zinc-400">Decisões do responsável, nunca deduzidas pelo sistema. Vazio = não decidido: a NFS-e de um perfil &ldquo;por tomador&rdquo; fica bloqueada até aqui ser preenchido (ou até a decisão com justificativa na própria nota).</p>
                  <div className="mt-3 grid gap-3 md:grid-cols-3">
                    <label className="space-y-1">
                      <span className="text-xs text-zinc-300">Inscrição municipal {somenteDigitos(form.codigo_ibge_municipio) === "4209102" ? "* (Joinville)" : "(se houver)"}</span>
                      <input className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm" value={form.inscricao_municipal} onChange={(event) => update("inscricao_municipal", somenteDigitos(event.target.value).slice(0, 15))} />
                    </label>
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-300">E-mail para envio da NFS-e</span>
                      <input className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm" value={form.email_nfse} onChange={(event) => update("email_nfse", event.target.value)} placeholder="fiscal@tomador.com.br" />
                    </label>
                    {([["iss_retido", "ISS retido pelo tomador"], ["retem_pcc", "Retém PIS/COFINS/CSLL (4,65%)"], ["retem_irrf", "Retém IRRF (1,5%)"], ["retem_inss", "Retém INSS (11%)"]] as Array<["iss_retido" | "retem_pcc" | "retem_irrf" | "retem_inss", string]>).map(([campo, titulo]) => (
                      <label key={campo} className="space-y-1">
                        <span className="text-xs text-zinc-300">{titulo}</span>
                        <select className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm" value={form[campo]} onChange={(event) => update(campo, event.target.value as "" | "sim" | "nao")}>
                          <option value="">Não decidido</option><option value="sim">Sim, retém</option><option value="nao">Não retém</option>
                        </select>
                      </label>
                    ))}
                    <label className="space-y-1">
                      <span className="text-xs text-zinc-300">Optante do Simples Nacional (tomador)</span>
                      <select className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm" value={form.optante_simples} onChange={(event) => update("optante_simples", event.target.value as "" | "sim" | "nao")}>
                        <option value="">Não informado (a nota avisa)</option><option value="sim">Sim: a CRF de 4,65% não se aplica (Lei 10.833/2003 art. 30 §2)</option><option value="nao">Não</option>
                      </select>
                    </label>
                    <label className="flex items-start gap-2 md:col-span-2">
                      <input type="checkbox" className="mt-1" checked={form.iss_substituto_tributario} onChange={(event) => update("iss_substituto_tributario", event.target.checked)} />
                      <span className="text-xs text-zinc-300">Substituto tributário do ISS (órgão público, banco, hospital, concessionária de energia, água ou pedágio). Com a marca, a NFS-e de manutenção e instalação (14.01 e 14.06) sai com o ISS retido pelo tomador; sem ela, a Segau recolhe. Regra do contador de 06/09/2026.</span>
                    </label>
                    <label className="space-y-1 md:col-span-2">
                      <span className="text-xs text-zinc-300">Template da discriminação da NFS-e (vazio = padrão)</span>
                      <textarea className="min-h-16 w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm" value={form.nfse_discriminacao_template} onChange={(event) => update("nfse_discriminacao_template", event.target.value)} placeholder="{RESULTADO}|PEDIDO DE COMPRA: {PEDIDO}{ITEM}|VENCIMENTO: {VENCIMENTO} DDL|OS {OS}|{FRASE_LEGAL}|{OBSERVACAO}" />
                      <span className="text-xs text-zinc-500">Segmentos separados por &ldquo;|&rdquo;; segmento com campo vazio some. Tokens: {"{RESULTADO} {PEDIDO} {ITEM} {VENCIMENTO} {DATAS} {OS} {FRASE_LEGAL} {ISS} {OBSERVACAO}"}. &ldquo;MÃO DE OBRA&rdquo; é recusado.</span>
                    </label>
                  </div>
                </section>

                {formPendencias.length > 0 && (
                  <section className="rounded-lg border border-amber-500/30 bg-amber-500/10 p-4">
                    <div className="text-sm font-semibold text-amber-200">O que falta neste cliente</div>
                    <ul className="mt-2 grid gap-1 text-xs text-amber-100/80 md:grid-cols-2">
                      {formPendencias.map((item) => <li key={item.campo}>• {item.mensagem}</li>)}
                    </ul>
                  </section>
                )}

                <div className="flex flex-wrap items-center justify-between gap-3 border-t border-zinc-800 pt-4">
                  <div className="text-xs text-zinc-500">A gravação altera somente o cliente #{selected.id}; nenhum outro cadastro é preenchido em lote.</div>
                  <div className="flex gap-2">
                    <button type="button" onClick={proximoPendente} className="rounded-md border border-zinc-700 bg-zinc-900 px-4 py-2 hover:bg-zinc-800">Próximo pendente</button>
                    <button type="button" disabled={saving || formPendencias.length > 0} onClick={() => void salvar()} className="rounded-md bg-zinc-100 px-4 py-2 font-medium text-zinc-900 hover:bg-white">
                      {saving ? "Salvando..." : "Salvar e liberar cliente"}
                    </button>
                  </div>
                </div>
              </div>
            </>
          )}
        </main>
      </div>
    </div>
  );
}
