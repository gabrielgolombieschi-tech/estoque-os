"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

type PerfilFiscal = {
  id: string;
  codigo: string;
  nome: string;
  modelo: "NFE" | "NFSE";
  natureza_operacao: string;
  natureza_texto: string;
  crt: string | null;
  cfop_interno: string | null;
  cfop_externo: string | null;
  cst_icms: string | null;
  csosn: string | null;
  origem_mercadoria: number | null;
  icms_modalidade_base_calculo: string | null;
  aliquota_icms: number | null;
  reducao_base_icms_percentual: number | null;
  cbenef: string | null;
  cbenef_aplicacao: "NAO_CONFIRMADO" | "SEM_BENEFICIO" | "COM_BENEFICIO";
  cst_pis: string | null;
  aliquota_pis: number | null;
  cst_cofins: string | null;
  aliquota_cofins: number | null;
  ambito_destino: "INTERNA" | "INTERESTADUAL" | null;
  ufs_destino: string[] | null;
  indicador_ie_destinatario: string | null;
  finalidade_emissao: number | null;
  consumidor_final: number | null;
  faixa_automacao: "AUTOMATICO" | "REVISAO" | "BLOQUEADO";
  justificativa_faixa: string | null;
  evidencia_id: string | null;
  vigencia_inicio: string;
  vigencia_fim: string | null;
  vigente: boolean;
  cst_ibs_cbs: string | null;
  cclass_trib: string | null;
  cclass_trib_versao: string | null;
  ibs_uf_aliquota: number | string | null;
  ibs_mun_aliquota: number | string | null;
  cbs_aliquota: number | string | null;
  habilitado_producao: boolean;
  revisao_fiscal_em: string | null;
  revisao_fiscal_por: string | null;
  revisao_fiscal_justificativa: string | null;
  producao_decidida_em: string | null;
  producao_decidida_por: string | null;
  // Perfil de servico (NFS-e). A revisao destes campos continua por script
  // (scripts/nfse-perfil-revisar.mjs), com a justificativa do contador versionada;
  // aqui eles aparecem somente para leitura, antes da liberacao para producao.
  item_servico?: string | null;
  codigo_tributacao_nacional?: string | null;
  codigo_nbs?: string | null;
  descricao_servico_padrao?: string | null;
  local_prestacao_regra?: string | null;
  incidencia_iss_regra?: string | null;
  aliquota_iss?: number | string | null;
  iss_retido_regra?: string | null;
  retencao_pcc_regra?: string | null;
  aliquota_pcc?: number | string | null;
  retencao_irrf_regra?: string | null;
  aliquota_irrf?: number | string | null;
  retencao_inss_regra?: string | null;
  aliquota_inss?: number | string | null;
  permite_deducao_material?: boolean | null;
  excecao_conserto_isolado?: boolean | null;
  codigo_indicador_operacao?: string | null;
  tributos_aprox_federal_pct?: number | string | null;
  tributos_aprox_municipal_pct?: number | string | null;
  campos_conferir?: Array<{ campo: string; motivo: string; prazo?: string }> | null;
  texto_complementar?: string | null;
  texto_sem_retencao?: string | null;
};

type ListaPerfis = {
  tenant_id: string;
  empresa_id: string;
  perfis: PerfilFiscal[];
};

type FormState = {
  cstIbsCbs: string;
  cclassTrib: string;
  cclassTribVersao: string;
  ibsUfAliquota: string;
  ibsMunAliquota: string;
  cbsAliquota: string;
  justificativa: string;
};

type Homologacao = {
  solicitacao_id: string;
  documento_fiscal_id: string;
  referencia_externa: string;
  autorizado_em: string;
  cancelamento_em_andamento: boolean;
  apos_ultima_revisao: boolean;
};

type ListaHomologacoes = {
  tenant_id: string;
  empresa_id: string;
  perfil_id: string;
  homologacoes: Homologacao[];
};

type ReleaseState = {
  solicitacaoId: string;
  justificativa: string;
  confirmou: boolean;
};

type Notice = { kind: "success" | "error"; text: string };

type Props = {
  retorno: string;
  perfilInicial: string | null;
  solicitacaoInicial: string | null;
};

const PERFIL_PILOTO = "SEG-VENDA-TERCEIROS-SC-5102-O2-CST00";
const REFERENCIA_HOMOLOGADA = {
  cstIbsCbs: "000",
  cclassTrib: "000001",
  cclassTribVersao: "Informe Técnico 2025.002 v1.60",
  ibsUfAliquota: "0,1",
  ibsMunAliquota: "0",
  cbsAliquota: "0,9",
};

const inputClass =
  "w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2.5 text-sm text-zinc-100 outline-none transition placeholder:text-zinc-600 focus:border-sky-500 disabled:cursor-not-allowed disabled:opacity-50";
const buttonClass =
  "inline-flex items-center justify-center rounded-lg border border-zinc-700 bg-zinc-900 px-4 py-2.5 text-sm font-medium text-zinc-100 transition hover:border-zinc-600 hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40";

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) {
    return String(error.message);
  }
  return String(error ?? "Erro inesperado.");
}

function toInputValue(value: number | string | null) {
  if (value === null || value === undefined) return "";
  return String(value).replace(".", ",");
}

function parseRate(value: string) {
  const compact = value.trim().replace(/\s/g, "");
  if (!compact) return null;
  const normalized = compact.includes(",")
    ? compact.replaceAll(".", "").replace(",", ".")
    : compact;
  if (!/^\d+(?:\.\d{1,4})?$/.test(normalized)) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
}

function formFromProfile(perfil: PerfilFiscal): FormState {
  return {
    cstIbsCbs: perfil.cst_ibs_cbs ?? "",
    cclassTrib: perfil.cclass_trib ?? "",
    cclassTribVersao: perfil.cclass_trib_versao ?? "",
    ibsUfAliquota: toInputValue(perfil.ibs_uf_aliquota),
    ibsMunAliquota: toInputValue(perfil.ibs_mun_aliquota),
    cbsAliquota: toInputValue(perfil.cbs_aliquota),
    justificativa: "",
  };
}

function formFiscalIgualAoPerfil(form: FormState, perfil: PerfilFiscal) {
  const taxaPerfil = (value: number | string | null) => value === null ? null : Number(value);
  return form.cstIbsCbs.trim() === (perfil.cst_ibs_cbs ?? "").trim()
    && form.cclassTrib.trim() === (perfil.cclass_trib ?? "").trim()
    && form.cclassTribVersao.trim() === (perfil.cclass_trib_versao ?? "").trim()
    && parseRate(form.ibsUfAliquota) === taxaPerfil(perfil.ibs_uf_aliquota)
    && parseRate(form.ibsMunAliquota) === taxaPerfil(perfil.ibs_mun_aliquota)
    && parseRate(form.cbsAliquota) === taxaPerfil(perfil.cbs_aliquota);
}

function readPayload(data: unknown): ListaPerfis {
  const value = typeof data === "string" ? JSON.parse(data) : data;
  if (!value || typeof value !== "object" || !("perfis" in value)) {
    throw new Error("A listagem de perfis retornou um formato inesperado.");
  }
  const payload = value as Partial<ListaPerfis>;
  if (!Array.isArray(payload.perfis)) {
    throw new Error("A listagem de perfis nao retornou uma colecao valida.");
  }
  return payload as ListaPerfis;
}

function readHomologacoes(data: unknown): ListaHomologacoes {
  const value = typeof data === "string" ? JSON.parse(data) : data;
  if (!value || typeof value !== "object" || !("homologacoes" in value)) {
    throw new Error("A listagem de homologacoes retornou um formato inesperado.");
  }
  const payload = value as Partial<ListaHomologacoes>;
  if (!Array.isArray(payload.homologacoes)) {
    throw new Error("A listagem de homologacoes nao retornou uma colecao valida.");
  }
  return payload as ListaHomologacoes;
}

function formatDate(value: string | null) {
  if (!value) return "Nao informado";
  const date = new Date(value.includes("T") ? value : `${value}T12:00:00`);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString("pt-BR");
}

function formatDateTime(value: string | null) {
  if (!value) return "Ainda nao revisado";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function display(value: string | number | null | undefined) {
  return value === null || value === undefined || value === "" ? "Nao informado" : String(value);
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="rounded-lg border border-zinc-800 bg-black/20 p-3">
      <div className="text-[11px] font-medium uppercase tracking-wide text-zinc-500">{label}</div>
      <div className="mt-1 text-sm text-zinc-200">{children}</div>
    </div>
  );
}

function productionBlockers(perfil: PerfilFiscal) {
  const blockers: string[] = [];
  if (!perfil.vigente) blockers.push("O perfil esta fora da vigencia.");
  if (perfil.faixa_automacao === "BLOQUEADO") blockers.push("A faixa de automacao esta bloqueada.");
  // Perfil de servico: os campos fiscais sao os do ISS e das retencoes, e a evidencia
  // e a propria NFS-e de homologacao. Os campos travados (CONFERIR_08_09) barram a producao.
  if (perfil.modelo === "NFSE") {
    if (!perfil.revisao_fiscal_em) blockers.push("O perfil de servico ainda nao foi revisado.");
    if (!perfil.codigo_tributacao_nacional) blockers.push("O codigo de tributacao nacional do servico nao esta confirmado.");
    if (perfil.aliquota_iss === null || perfil.aliquota_iss === undefined) blockers.push("A aliquota de ISS nao esta confirmada.");
    if (!perfil.iss_retido_regra) blockers.push("A regra de retencao do ISS nao esta confirmada.");
    if (!perfil.codigo_indicador_operacao) blockers.push("O cIndOp nao esta confirmado (obrigatorio no grupo IBS/CBS).");
    if (perfil.campos_conferir?.length) {
      blockers.push(`Campos travados aguardando confirmacao: ${perfil.campos_conferir.map((c) => c.campo).join(", ")}.`);
    }
    return blockers;
  }
  if (!perfil.evidencia_id) blockers.push("Nao ha evidencia fiscal vinculada.");
  if (!perfil.ambito_destino || !perfil.ufs_destino?.length) {
    blockers.push("Ambito e UFs de destino ainda nao foram confirmados.");
  }
  if (perfil.ambito_destino === "INTERNA" && !/^\d{4}$/.test(perfil.cfop_interno ?? "")) {
    blockers.push("O CFOP interno nao esta confirmado.");
  }
  if (perfil.ambito_destino === "INTERESTADUAL" && !/^\d{4}$/.test(perfil.cfop_externo ?? "")) {
    blockers.push("O CFOP interestadual nao esta confirmado.");
  }
  if (perfil.origem_mercadoria === null) blockers.push("A origem da mercadoria nao esta confirmada.");
  if (!/^[123]$/.test(perfil.crt ?? "")) blockers.push("O CRT nao esta confirmado.");
  if (perfil.crt === "3" && !/^\d{2}$/.test(perfil.cst_icms ?? "")) {
    blockers.push("O CST ICMS do regime normal nao esta confirmado.");
  }
  if (["1", "2"].includes(perfil.crt ?? "") && !/^\d{3}$/.test(perfil.csosn ?? "")) {
    blockers.push("O CSOSN do Simples Nacional nao esta confirmado.");
  }
  if (perfil.cbenef_aplicacao === "NAO_CONFIRMADO") {
    blockers.push("A aplicacao de cBenef nao foi decidida.");
  }
  if (!/^\d{2}$/.test(perfil.cst_pis ?? "") || !/^\d{2}$/.test(perfil.cst_cofins ?? "")) {
    blockers.push("Os CSTs de PIS e COFINS nao estao confirmados.");
  }
  if (perfil.finalidade_emissao === null || perfil.consumidor_final === null) {
    blockers.push("Finalidade da emissao e consumidor final nao estao confirmados.");
  }
  return blockers;
}

function validationIssues(form: FormState) {
  const issues: string[] = [];
  if (!/^\d{3}$/.test(form.cstIbsCbs)) issues.push("Informe o CST IBS/CBS com 3 digitos.");
  if (!/^\d{6}$/.test(form.cclassTrib)) issues.push("Informe o cClassTrib com 6 digitos.");
  if (
    /^\d{3}$/.test(form.cstIbsCbs) &&
    /^\d{6}$/.test(form.cclassTrib) &&
    !form.cclassTrib.startsWith(form.cstIbsCbs)
  ) {
    issues.push("O prefixo do cClassTrib deve coincidir com o CST IBS/CBS.");
  }
  if (form.cclassTribVersao.trim().length < 3 || form.cclassTribVersao.trim().length > 100) {
    issues.push("Informe a versao da tabela cClassTrib.");
  }
  if (parseRate(form.ibsUfAliquota) === null) issues.push("Revise a aliquota IBS UF.");
  if (parseRate(form.ibsMunAliquota) === null) issues.push("Revise a aliquota IBS municipal.");
  if (parseRate(form.cbsAliquota) === null) issues.push("Revise a aliquota CBS.");
  const justificationLength = form.justificativa.trim().length;
  if (justificationLength < 15 || justificationLength > 1000) {
    issues.push("A justificativa deve ter entre 15 e 1000 caracteres.");
  }
  return issues;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default function PerfisFiscaisClient({ retorno, perfilInicial, solicitacaoInicial }: Props) {
  const scope = useTenantEmpresa();
  const router = useRouter();
  const supabase = useMemo(() => supabaseBrowser(), []);
  const selectedIdRef = useRef("");
  const [perfis, setPerfis] = useState<PerfilFiscal[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [form, setForm] = useState<FormState | null>(null);
  const [homologacoes, setHomologacoes] = useState<Homologacao[]>([]);
  const [homologacoesLoading, setHomologacoesLoading] = useState(false);
  const [release, setRelease] = useState<ReleaseState>({
    solicitacaoId: solicitacaoInicial ?? "",
    justificativa: "",
    confirmou: false,
  });
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);

  const empresaRole = useMemo(() => {
    const role = scope.empresa?.papel ?? scope.empresas.find((e) => e.id === scope.empresaId)?.papel;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [scope.empresa?.papel, scope.empresaId, scope.empresas]);

  const roleAllowsWrite = ["ADMIN", "DIRETOR", "FINANCEIRO", "FATURAMENTO"].includes(empresaRole);
  const canRead =
    roleAllowsWrite ||
    Boolean(scope.capabilities?.["financeiro.read"]) ||
    Boolean(scope.capabilities?.["financeiro.write"]) ||
    Boolean(scope.capabilities?.["faturamento.read"]) ||
    Boolean(scope.capabilities?.["faturamento.write"]);
  const canWrite =
    roleAllowsWrite ||
    Boolean(scope.capabilities?.["financeiro.write"]) ||
    Boolean(scope.capabilities?.["faturamento.write"]);

  useEffect(() => {
    if (!scope.loading && scope.capabilities !== null && !canRead) {
      router.replace("/forbidden");
    }
  }, [canRead, router, scope.capabilities, scope.loading]);

  const loadHomologacoes = useCallback(
    async (perfilId: string | null) => {
      if (!perfilId || !scope.tenantId || !scope.empresaId || !canRead) {
        setHomologacoes([]);
        return;
      }
      setHomologacoesLoading(true);
      try {
        const { data, error } = await supabase
          .schema("f")
          .rpc("fn_perfil_operacao_nfe_homologacoes_listar", { p_perfil_id: perfilId });
        if (error) throw error;
        const payload = readHomologacoes(data);
        if (
          payload.tenant_id !== scope.tenantId ||
          payload.empresa_id !== scope.empresaId ||
          payload.perfil_id !== perfilId
        ) {
          throw new Error("A homologacao retornada nao corresponde ao escopo e perfil ativos.");
        }
        setHomologacoes(payload.homologacoes);
      } catch (error) {
        setHomologacoes([]);
        setNotice({ kind: "error", text: errorMessage(error) });
      } finally {
        setHomologacoesLoading(false);
      }
    },
    [canRead, scope.empresaId, scope.tenantId, supabase]
  );

  const reload = useCallback(
    async (preferred?: string | null) => {
      if (!scope.tenantId || !scope.empresaId || !canRead) return;
      setLoading(true);
      setLoadError(null);
      try {
        const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfe_listar");
        if (error) throw error;
        const payload = readPayload(data);
        if (payload.tenant_id !== scope.tenantId || payload.empresa_id !== scope.empresaId) {
          throw new Error("O escopo retornado nao corresponde ao tenant e empresa ativos.");
        }
        const rows = payload.perfis;
        const key = preferred ?? selectedIdRef.current ?? perfilInicial;
        // Sem perfil pedido, abre num perfil que ainda pode ser trabalhado: o primeiro da
        // lista e uma linha BLOQUEADA da matriz CSV63, que so mostra bloqueios sem saida.
        const selected =
          rows.find((perfil) => perfil.id === key || perfil.codigo === key) ??
          rows.find((perfil) => perfil.id === selectedIdRef.current) ??
          rows.find((perfil) => perfil.faixa_automacao !== "BLOQUEADO") ??
          rows[0] ??
          null;
        setPerfis(rows);
        setSelectedId(selected?.id ?? "");
        selectedIdRef.current = selected?.id ?? "";
        setForm(selected ? formFromProfile(selected) : null);
        await loadHomologacoes(selected?.id ?? null);
      } catch (error) {
        setLoadError(errorMessage(error));
      } finally {
        setLoading(false);
      }
    },
    [canRead, loadHomologacoes, perfilInicial, scope.empresaId, scope.tenantId, supabase]
  );

  useEffect(() => {
    if (scope.loading || !scope.tenantId || !scope.empresaId || !canRead) return;
    void reload(perfilInicial);
  }, [canRead, perfilInicial, reload, scope.empresaId, scope.loading, scope.tenantId]);

  const selected = useMemo(
    () => perfis.find((perfil) => perfil.id === selectedId) ?? null,
    [perfis, selectedId]
  );

  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase("pt-BR");
    if (!query) return perfis;
    return perfis.filter((perfil) =>
      [perfil.codigo, perfil.nome, perfil.natureza_operacao, perfil.natureza_texto]
        .join(" ")
        .toLocaleLowerCase("pt-BR")
        .includes(query)
    );
  }, [perfis, search]);

  const issues = useMemo(
    () => (form ? validationIssues(form) : []),
    [form]
  );

  const blockers = useMemo(() => (selected ? productionBlockers(selected) : []), [selected]);
  const formFiscalAlterado = useMemo(
    () => Boolean(selected && form && !formFiscalIgualAoPerfil(form, selected)),
    [form, selected]
  );
  const selectedHomologacao = useMemo(
    () => homologacoes.find((homologacao) => homologacao.solicitacao_id === release.solicitacaoId) ?? null,
    [homologacoes, release.solicitacaoId]
  );
  const ehServico = selected?.modelo === "NFSE";
  const releaseIssues = useMemo(() => {
    if (!selected) return ["Selecione um perfil."];
    const next = [...blockers];
    // Perfil de servico nao tem formulario de revisao nesta tela: nada a salvar antes de liberar.
    if (formFiscalAlterado && selected.modelo !== "NFSE") next.push("Salve ou descarte as alteracoes fiscais do formulario antes de liberar producao.");
    if (!selected.revisao_fiscal_em) next.push("Salve a revisao do perfil antes da homologacao.");
    if (!UUID.test(release.solicitacaoId)) next.push("Informe o UUID da solicitacao homologada.");
    const documento = selected.modelo === "NFSE" ? "NFS-e" : "NF-e";
    if (UUID.test(release.solicitacaoId) && !selectedHomologacao) {
      next.push(`A solicitacao ainda nao possui ${documento} AUTORIZADA em homologacao para este perfil.`);
    }
    if (selectedHomologacao && !selectedHomologacao.apos_ultima_revisao) {
      next.push(`A ${documento} de homologacao e anterior a ultima revisao; emita uma nova homologacao.`);
    }
    if (selectedHomologacao?.cancelamento_em_andamento) {
      next.push(`A ${documento} de homologacao possui cancelamento em andamento.`);
    }
    const length = release.justificativa.trim().length;
    if (length < 15 || length > 1000) next.push("A justificativa da liberacao deve ter entre 15 e 1000 caracteres.");
    if (!release.confirmou) next.push("Confirme conscientemente a liberacao vinculada a esta homologacao.");
    return next;
  }, [blockers, formFiscalAlterado, release, selected, selectedHomologacao]);

  useEffect(() => {
    if (!formFiscalAlterado || !release.confirmou) return;
    setRelease((current) => ({ ...current, confirmou: false }));
  }, [formFiscalAlterado, release.confirmou]);

  function selectProfile(perfil: PerfilFiscal) {
    selectedIdRef.current = perfil.id;
    setSelectedId(perfil.id);
    setForm(formFromProfile(perfil));
    setRelease((current) => ({ ...current, justificativa: "", confirmou: false }));
    void loadHomologacoes(perfil.id);
    setNotice(null);
  }

  function applyHomologatedReference() {
    setForm((current) =>
      current
        ? {
            ...current,
            ...REFERENCIA_HOMOLOGADA,
          }
        : current
    );
    setRelease((current) => ({ ...current, confirmou: false }));
    setNotice({
      kind: "success",
      text: "Referencia da NF-e homologada aplicada somente ao formulario. Revise e justifique antes de salvar.",
    });
  }

  async function save() {
    if (!selected || !form || !canWrite) return;
    const ibsUf = parseRate(form.ibsUfAliquota);
    const ibsMun = parseRate(form.ibsMunAliquota);
    const cbs = parseRate(form.cbsAliquota);
    if (issues.length || ibsUf === null || ibsMun === null || cbs === null) {
      setNotice({ kind: "error", text: "Corrija as pendencias antes de salvar a revisao." });
      return;
    }

    setBusy(true);
    setNotice(null);
    try {
      const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfe_revisar", {
        p_perfil_id: selected.id,
        p_cst_ibs_cbs: form.cstIbsCbs,
        p_cclass_trib: form.cclassTrib,
        p_cclass_trib_versao: form.cclassTribVersao.trim(),
        p_ibs_uf_aliquota: ibsUf,
        p_ibs_mun_aliquota: ibsMun,
        p_cbs_aliquota: cbs,
        p_justificativa: form.justificativa.trim(),
      });
      if (error) throw error;
      const response = data && typeof data === "object" ? (data as { mensagem?: unknown }) : null;
      await reload(selected.id);
      setNotice({
        kind: "success",
        text:
          typeof response?.mensagem === "string"
            ? response.mensagem
            : "Perfil fiscal revisado com sucesso.",
      });
    } catch (error) {
      setNotice({ kind: "error", text: errorMessage(error) });
    } finally {
      setBusy(false);
    }
  }

  async function releaseProduction() {
    if (!selected || !canWrite || releaseIssues.length) return;
    setBusy(true);
    setNotice(null);
    try {
      const { data, error } = await supabase.schema("f").rpc(
        selected.modelo === "NFSE" ? "fn_perfil_operacao_nfse_liberar_producao" : "fn_perfil_operacao_nfe_liberar_producao",
        {
          p_perfil_id: selected.id,
          p_solicitacao_id: release.solicitacaoId,
          p_justificativa: release.justificativa.trim(),
          p_confirmacao: release.confirmou,
        },
      );
      if (error) throw error;
      const response = data && typeof data === "object" ? (data as { mensagem?: unknown }) : null;
      setRelease((current) => ({ ...current, justificativa: "", confirmou: false }));
      await reload(selected.id);
      setNotice({
        kind: "success",
        text:
          typeof response?.mensagem === "string"
            ? response.mensagem
            : "Perfil liberado apos conferencia da homologacao autorizada.",
      });
    } catch (error) {
      setNotice({ kind: "error", text: errorMessage(error) });
    } finally {
      setBusy(false);
    }
  }

  const empresaNome = scope.empresa?.nome_fantasia ?? scope.empresa?.razao_social ?? "Empresa ativa";
  const returnLabel = retorno.startsWith("/comercial/vendas/") ? "Voltar para a OV" : retorno.startsWith("/os/") ? "Voltar para a OS" : "Voltar para NF-e";

  if (scope.loading || (scope.capabilities === null && !roleAllowsWrite)) {
    return <main className="mx-auto max-w-[1500px] p-6 text-sm text-zinc-400">Carregando escopo fiscal...</main>;
  }

  if (!canRead) {
    return <main className="mx-auto max-w-[1500px] p-6 text-sm text-zinc-400">Validando permissao de acesso...</main>;
  }

  return (
    <main className="mx-auto max-w-[1500px] space-y-6 p-4 text-zinc-100 sm:p-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="text-xs text-zinc-500">Faturamento › Perfis fiscais</div>
          <h1 className="mt-1 text-2xl font-semibold">Perfis fiscais: revisao da NF-e e liberacao para producao</h1>
          <p className="mt-1 text-sm text-zinc-400">
            {empresaNome} · somente perfis do tenant e da empresa ativos.
          </p>
        </div>
        <Link href={retorno} className={buttonClass}>
          {returnLabel}
        </Link>
      </header>

      {!canWrite && (
        <div className="rounded-xl border border-amber-800/60 bg-amber-950/20 p-4 text-sm text-amber-200">
          Seu acesso permite consultar os perfis, mas nao registrar revisao ou liberar producao.
        </div>
      )}

      {notice && (
        <div
          className={`rounded-xl border p-4 text-sm ${
            notice.kind === "error"
              ? "border-rose-800/60 bg-rose-950/20 text-rose-200"
              : "border-emerald-800/60 bg-emerald-950/20 text-emerald-200"
          }`}
        >
          {notice.text}
        </div>
      )}

      {loadError && (
        <div className="rounded-xl border border-rose-800/60 bg-rose-950/20 p-4 text-sm text-rose-200">
          <div>{loadError}</div>
          <button className={`${buttonClass} mt-3`} type="button" onClick={() => void reload()}>
            Tentar novamente
          </button>
        </div>
      )}

      <div className="grid gap-5 lg:grid-cols-[360px_minmax(0,1fr)]">
        <aside className="self-start rounded-xl border border-zinc-800 bg-zinc-950/60 p-4 lg:sticky lg:top-4">
          <div className="flex items-center justify-between gap-3">
            <h2 className="font-semibold">Perfis da empresa</h2>
            <span className="rounded-full bg-zinc-900 px-2 py-1 text-xs text-zinc-400">{perfis.length}</span>
          </div>
          <input
            aria-label="Buscar perfil fiscal"
            className={`${inputClass} mt-4`}
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Codigo, nome ou natureza"
          />
          <div className="mt-3 max-h-[68vh] space-y-2 overflow-y-auto pr-1">
            {loading && <div className="py-6 text-center text-sm text-zinc-500">Carregando perfis...</div>}
            {!loading &&
              filtered.map((perfil) => (
                <button
                  key={perfil.id}
                  type="button"
                  onClick={() => selectProfile(perfil)}
                  className={`w-full rounded-lg border p-3 text-left transition ${
                    perfil.id === selectedId
                      ? "border-sky-600 bg-sky-950/30"
                      : "border-zinc-800 bg-black/20 hover:border-zinc-700"
                  }`}
                >
                  <div className="break-all text-xs font-semibold text-zinc-200">{perfil.codigo}</div>
                  <div className="mt-1 line-clamp-2 text-xs text-zinc-500">{perfil.nome}</div>
                  <div className="mt-2 flex flex-wrap gap-1.5 text-[10px] uppercase tracking-wide">
                    <span className={`rounded-full border px-2 py-0.5 ${perfil.modelo === "NFSE" ? "border-violet-700 text-violet-300" : "border-sky-800 text-sky-300"}`}>
                      {perfil.modelo === "NFSE" ? `NFS-e ${perfil.item_servico ?? ""}`.trim() : "NF-e"}
                    </span>
                    <span className="rounded-full border border-zinc-700 px-2 py-0.5 text-zinc-400">
                      {perfil.faixa_automacao}
                    </span>
                    <span
                      className={`rounded-full border px-2 py-0.5 ${
                        perfil.habilitado_producao
                          ? "border-emerald-700 text-emerald-300"
                          : "border-zinc-700 text-zinc-500"
                      }`}
                    >
                      {perfil.habilitado_producao ? "Producao" : "Fora de producao"}
                    </span>
                  </div>
                </button>
              ))}
            {!loading && filtered.length === 0 && (
              <div className="py-6 text-center text-sm text-zinc-500">Nenhum perfil encontrado.</div>
            )}
          </div>
        </aside>

        <section className="min-w-0 space-y-5">
          {!selected || !form ? (
            <div className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-8 text-center text-sm text-zinc-500">
              Selecione um perfil fiscal (NF-e ou NFS-e) da empresa ativa.
            </div>
          ) : (
            <>
              <section className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-5">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="break-all text-xs font-semibold text-sky-300">{selected.codigo}</div>
                    <h2 className="mt-1 text-xl font-semibold">{selected.nome}</h2>
                    <p className="mt-1 text-sm text-zinc-500">{selected.natureza_texto}</p>
                  </div>
                  <div className="text-right text-xs text-zinc-500">
                    <div>Vigencia: {formatDate(selected.vigencia_inicio)} a {formatDate(selected.vigencia_fim)}</div>
                    <div className="mt-1">Ultima revisao: {formatDateTime(selected.revisao_fiscal_em)}</div>
                  </div>
                </div>

                {ehServico ? (
                  <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                    <Fact label="Servico">
                      Subitem {display(selected.item_servico)} · cTribNac {display(selected.codigo_tributacao_nacional)}
                    </Fact>
                    <Fact label="NBS">{display(selected.codigo_nbs)}</Fact>
                    <Fact label="ISS">
                      {display(selected.aliquota_iss)}% · incide{" "}
                      {selected.incidencia_iss_regra === "LOCAL_PRESTACAO" ? "no municipio da prestacao" : "na sede"}
                    </Fact>
                    <Fact label="Local da prestacao">
                      {selected.local_prestacao_regra === "SEDE" ? "Sede da empresa" : "Municipio do tomador"}
                    </Fact>
                    <Fact label="ISS retido">{display(selected.iss_retido_regra)}</Fact>
                    <Fact label="CRF (PIS/COFINS/CSLL)">
                      {display(selected.retencao_pcc_regra)} · {display(selected.aliquota_pcc)}%
                      {selected.excecao_conserto_isolado ? " · excecao de conserto isolado" : ""}
                    </Fact>
                    <Fact label="IRRF / INSS">
                      {display(selected.retencao_irrf_regra)} {display(selected.aliquota_irrf)}% ·{" "}
                      {display(selected.retencao_inss_regra)} {display(selected.aliquota_inss)}%
                    </Fact>
                    <Fact label="cIndOp / IBS/CBS">
                      {display(selected.codigo_indicador_operacao)} · CST {display(selected.cst_ibs_cbs)} /{" "}
                      {display(selected.cclass_trib)}
                    </Fact>
                    <Fact label="Tributos aproximados">
                      Federal {display(selected.tributos_aprox_federal_pct)}% · municipal{" "}
                      {display(selected.tributos_aprox_municipal_pct)}%
                    </Fact>
                    <Fact label="Deducao de material">
                      {selected.permite_deducao_material ? "Permitida (obra)" : "Nao permitida"}
                    </Fact>
                    <Fact label="Campos travados">
                      {selected.campos_conferir?.length
                        ? selected.campos_conferir.map((c) => c.campo).join(", ")
                        : "Nenhum"}
                    </Fact>
                    <Fact label="Faixa">{selected.faixa_automacao}</Fact>
                  </div>
                ) : (
                <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                  <Fact label="Destino">
                    {display(selected.ambito_destino)} · {selected.ufs_destino?.join(", ") || "UF nao informada"}
                  </Fact>
                  <Fact label="CFOP">
                    Interno {display(selected.cfop_interno)} · Externo {display(selected.cfop_externo)}
                  </Fact>
                  <Fact label="ICMS">
                    CRT {display(selected.crt)} · origem {display(selected.origem_mercadoria)} · CST/CSOSN{" "}
                    {display(selected.cst_icms ?? selected.csosn)}
                  </Fact>
                  <Fact label="PIS / COFINS">
                    {display(selected.cst_pis)} a {display(selected.aliquota_pis)}% · {display(selected.cst_cofins)} a{" "}
                    {display(selected.aliquota_cofins)}%
                  </Fact>
                  <Fact label="Base ICMS">
                    Modalidade {display(selected.icms_modalidade_base_calculo)} · aliquota {display(selected.aliquota_icms)}%
                  </Fact>
                  <Fact label="cBenef">
                    {selected.cbenef_aplicacao} · {display(selected.cbenef)}
                  </Fact>
                  <Fact label="Emissao">
                    Finalidade {display(selected.finalidade_emissao)} · consumidor final {display(selected.consumidor_final)}
                  </Fact>
                  <Fact label="Evidencia">
                    {selected.evidencia_id ? "Vinculada" : "Nao vinculada"} · faixa {selected.faixa_automacao}
                  </Fact>
                </div>
                )}
                {ehServico && (selected.texto_complementar || selected.texto_sem_retencao) ? (
                  <div className="mt-4 space-y-2 rounded-lg border border-zinc-800 bg-zinc-950/60 p-3 text-xs text-zinc-400">
                    {selected.texto_complementar ? <div><span className="text-zinc-500">Frase com retencao: </span>{selected.texto_complementar}</div> : null}
                    {selected.texto_sem_retencao ? <div><span className="text-zinc-500">Frase sem retencao: </span>{selected.texto_sem_retencao}</div> : null}
                  </div>
                ) : null}
              </section>

              {ehServico ? (
                <section className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-5">
                  <h2 className="font-semibold">Revisao fiscal do perfil de servico</h2>
                  <p className="mt-1 max-w-3xl text-sm text-zinc-400">
                    Os campos acima nao sao editados aqui. Eles vem de{" "}
                    <code className="text-zinc-300">scripts/nfse-perfil-revisar.mjs</code>, onde cada valor fica ao lado da
                    justificativa do contador e passa por revisao antes de ser aplicado — a mesma disciplina dos campos de
                    NF-e, que vem de migration. Esta tela cuida da liberacao para producao, que se repete a cada nota.
                  </p>
                  {selected.revisao_fiscal_justificativa ? (
                    <div className="mt-3 rounded-lg border border-zinc-800 bg-zinc-950 p-3 text-xs text-zinc-400">
                      <div className="text-zinc-500">Ultima revisao ({formatDateTime(selected.revisao_fiscal_em)}):</div>
                      <div className="mt-1">{selected.revisao_fiscal_justificativa}</div>
                    </div>
                  ) : (
                    <div className="mt-3 text-sm text-amber-300">Perfil ainda sem revisao fiscal.</div>
                  )}
                </section>
              ) : (
              <section className="rounded-xl border border-sky-900/70 bg-sky-950/10 p-5">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <h2 className="font-semibold">Campos IBS/CBS sujeitos a revisao</h2>
                    <p className="mt-1 text-sm text-zinc-400">
                      Os seis valores sao gravados juntos; nenhum deles recebe fallback no banco.
                    </p>
                  </div>
                  {selected.codigo === PERFIL_PILOTO && (
                    <button
                      type="button"
                      className={buttonClass}
                      disabled={!canWrite || busy}
                      onClick={applyHomologatedReference}
                    >
                      Aplicar referencia homologada
                    </button>
                  )}
                </div>

                {selected.codigo === PERFIL_PILOTO && (
                  <div className="mt-4 rounded-lg border border-cyan-900/70 bg-cyan-950/20 p-3 text-xs text-cyan-200">
                    Referencia oficial atual: CST 000, cClassTrib 000001, Informe Técnico 2025.002 v1.60,
                    IBS UF 0,1%, IBS municipal 0% e CBS 0,9%. A aplicacao ao formulario ainda exige revisao humana.
                  </div>
                )}

                <div className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                  <label className="space-y-1.5 text-sm text-zinc-300" htmlFor="cst-ibs-cbs">
                    <span>CST IBS/CBS</span>
                    <input
                      id="cst-ibs-cbs"
                      className={inputClass}
                      inputMode="numeric"
                      maxLength={3}
                      disabled={!canWrite || busy}
                      value={form.cstIbsCbs}
                      onChange={(event) =>
                        setForm({ ...form, cstIbsCbs: event.target.value.replace(/\D/g, "").slice(0, 3) })
                      }
                      placeholder="000"
                    />
                  </label>
                  <label className="space-y-1.5 text-sm text-zinc-300" htmlFor="cclass-trib">
                    <span>cClassTrib</span>
                    <input
                      id="cclass-trib"
                      className={inputClass}
                      inputMode="numeric"
                      maxLength={6}
                      disabled={!canWrite || busy}
                      value={form.cclassTrib}
                      onChange={(event) =>
                        setForm({ ...form, cclassTrib: event.target.value.replace(/\D/g, "").slice(0, 6) })
                      }
                      placeholder="000001"
                    />
                  </label>
                  <label className="space-y-1.5 text-sm text-zinc-300" htmlFor="cclass-versao">
                    <span>Versao da tabela cClassTrib</span>
                    <input
                      id="cclass-versao"
                      className={inputClass}
                      maxLength={100}
                      disabled={!canWrite || busy}
                      value={form.cclassTribVersao}
                      onChange={(event) => setForm({ ...form, cclassTribVersao: event.target.value })}
                      placeholder="Informe Técnico 2025.002 v1.60"
                    />
                  </label>
                  <label className="space-y-1.5 text-sm text-zinc-300" htmlFor="ibs-uf">
                    <span>Aliquota IBS UF (%)</span>
                    <input
                      id="ibs-uf"
                      className={inputClass}
                      inputMode="decimal"
                      disabled={!canWrite || busy}
                      value={form.ibsUfAliquota}
                      onChange={(event) => setForm({ ...form, ibsUfAliquota: event.target.value })}
                      placeholder="0,1"
                    />
                  </label>
                  <label className="space-y-1.5 text-sm text-zinc-300" htmlFor="ibs-municipal">
                    <span>Aliquota IBS municipal (%)</span>
                    <input
                      id="ibs-municipal"
                      className={inputClass}
                      inputMode="decimal"
                      disabled={!canWrite || busy}
                      value={form.ibsMunAliquota}
                      onChange={(event) => setForm({ ...form, ibsMunAliquota: event.target.value })}
                      placeholder="0"
                    />
                  </label>
                  <label className="space-y-1.5 text-sm text-zinc-300" htmlFor="cbs">
                    <span>Aliquota CBS (%)</span>
                    <input
                      id="cbs"
                      className={inputClass}
                      inputMode="decimal"
                      disabled={!canWrite || busy}
                      value={form.cbsAliquota}
                      onChange={(event) => setForm({ ...form, cbsAliquota: event.target.value })}
                      placeholder="0,9"
                    />
                  </label>
                </div>

                <label className="mt-5 block space-y-1.5 text-sm text-zinc-300" htmlFor="justificativa-revisao">
                  <span>Justificativa da revisao</span>
                  <textarea
                    id="justificativa-revisao"
                    className={`${inputClass} min-h-28 resize-y`}
                    maxLength={1000}
                    disabled={!canWrite || busy}
                    value={form.justificativa}
                    onChange={(event) => setForm({ ...form, justificativa: event.target.value })}
                    placeholder="Informe a fonte conferida, a decisao fiscal e por que estes valores se aplicam ao perfil."
                  />
                  <div className="text-right text-xs text-zinc-600">{form.justificativa.trim().length}/1000</div>
                </label>

                <div className="mt-5 flex flex-wrap items-end justify-between gap-4 border-t border-sky-900/50 pt-5">
                  <div className="max-w-2xl text-xs text-zinc-500">
                    Salvar uma revisao sempre desabilita a producao. Depois disso, emita uma nova NF-e em homologacao
                    com esta mesma solicitacao e volte aqui para conferir a equivalencia autorizada.
                    {issues.length > 0 && <div className="mt-2 text-amber-300">{issues.length} pendencia(s) no formulario.</div>}
                  </div>
                  <button
                    type="button"
                    onClick={() => void save()}
                    disabled={!canWrite || busy || issues.length > 0}
                    className="rounded-lg bg-sky-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-sky-500 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    {busy ? "Salvando revisao..." : "Salvar revisao e desabilitar producao"}
                  </button>
                </div>
              </section>
              )}

              <section
                className={`rounded-xl border p-5 ${
                  selected.habilitado_producao
                    ? "border-emerald-700/70 bg-emerald-950/20"
                    : "border-amber-800/60 bg-amber-950/10"
                }`}
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <h2 className="font-semibold">Liberacao separada para producao</h2>
                    <p className="mt-1 max-w-3xl text-sm text-zinc-400">
                      A RPC confere tenant, empresa, perfil e os seis campos no item da solicitacao, snapshot fiscal e
                      payload da nota AUTORIZADA em homologacao. Esta etapa nao emite a nota de producao.
                    </p>
                  </div>
                  <span
                    className={`rounded-full border px-3 py-1 text-xs font-medium ${
                      selected.habilitado_producao
                        ? "border-emerald-700 text-emerald-300"
                        : "border-zinc-700 text-zinc-400"
                    }`}
                  >
                    {selected.habilitado_producao ? "Liberado" : "Nao liberado"}
                  </span>
                </div>

                {blockers.length > 0 && (
                  <div className="mt-4 rounded-lg border border-rose-800/60 bg-rose-950/20 p-3 text-sm text-rose-200">
                    <div className="font-medium">A liberacao continua bloqueada:</div>
                    <ul className="mt-2 list-disc space-y-1 pl-5">
                      {blockers.map((blocker) => (
                        <li key={blocker}>{blocker}</li>
                      ))}
                    </ul>
                  </div>
                )}

                <div className="mt-5 grid gap-4 lg:grid-cols-2">
                  <div>
                    <div className="flex items-center justify-between gap-3">
                      <label className="text-sm text-zinc-300" htmlFor="solicitacao-homologada">
                        Solicitacao da {ehServico ? "NFS-e" : "NF-e"} homologada
                      </label>
                      <button
                        type="button"
                        className="text-xs text-sky-400 hover:text-sky-300 disabled:opacity-40"
                        disabled={homologacoesLoading || busy}
                        onClick={() => void loadHomologacoes(selected.id)}
                      >
                        {homologacoesLoading ? "Atualizando..." : "Atualizar homologacoes"}
                      </button>
                    </div>
                    <input
                      id="solicitacao-homologada"
                      className={`${inputClass} mt-1.5 font-mono`}
                      list="homologacoes-autorizadas"
                      disabled={!canWrite || busy}
                      value={release.solicitacaoId}
                      onChange={(event) =>
                        setRelease({ ...release, solicitacaoId: event.target.value.trim(), confirmou: false })
                      }
                      placeholder="UUID da solicitacao"
                    />
                    <datalist id="homologacoes-autorizadas">
                      {homologacoes.map((homologacao) => (
                        <option key={homologacao.documento_fiscal_id} value={homologacao.solicitacao_id}>
                          {homologacao.referencia_externa} · {formatDateTime(homologacao.autorizado_em)}
                        </option>
                      ))}
                    </datalist>
                    <div className="mt-2 text-xs text-zinc-500">
                      {homologacoes.length
                        ? `${homologacoes.length} solicitacao(oes) com homologacao autorizada para este perfil.`
                        : "Nenhuma homologacao autorizada encontrada para este perfil."}
                    </div>
                  </div>
                  <label className="space-y-1.5 text-sm text-zinc-300" htmlFor="justificativa-liberacao">
                    <span>Justificativa da liberacao</span>
                    <textarea
                      id="justificativa-liberacao"
                      className={`${inputClass} min-h-24 resize-y`}
                      maxLength={1000}
                      disabled={!canWrite || busy}
                      value={release.justificativa}
                      onChange={(event) =>
                        setRelease({ ...release, justificativa: event.target.value, confirmou: false })
                      }
                      placeholder="Registre a conferencia da homologacao autorizada e a decisao de liberar."
                    />
                  </label>
                </div>

                {selectedHomologacao && (
                  <div
                    className={`mt-4 rounded-lg border p-3 text-xs ${
                      selectedHomologacao.apos_ultima_revisao &&
                      !selectedHomologacao.cancelamento_em_andamento
                        ? "border-emerald-800/60 bg-emerald-950/20 text-emerald-200"
                        : "border-rose-800/60 bg-rose-950/20 text-rose-200"
                    }`}
                  >
                    Documento {selectedHomologacao.documento_fiscal_id} · autorizado em{" "}
                    {formatDateTime(selectedHomologacao.autorizado_em)} ·{" "}
                    {selectedHomologacao.cancelamento_em_andamento
                      ? "cancelamento em andamento; nao pode liberar"
                      : selectedHomologacao.apos_ultima_revisao
                      ? "posterior a ultima revisao"
                      : "anterior a ultima revisao; nao pode liberar"}
                  </div>
                )}

                <label className="mt-4 flex cursor-pointer items-start gap-3 rounded-lg border border-amber-700/60 bg-black/20 p-3">
                  <input
                    type="checkbox"
                    className="mt-1 h-4 w-4 accent-amber-500"
                    disabled={!canWrite || busy}
                    checked={release.confirmou}
                    onChange={(event) => setRelease({ ...release, confirmou: event.target.checked })}
                  />
                  <span className="text-sm text-amber-100">
                    Confirmo a equivalencia com esta nota AUTORIZADA em homologacao e quero vincular a liberacao somente
                    a esta solicitacao e documento.
                  </span>
                </label>

                {releaseIssues.length > 0 && (
                  <div className="mt-4 rounded-lg border border-zinc-800 bg-black/20 p-3 text-xs text-zinc-400">
                    <div>{releaseIssues.length} pendencia(s) impedem a liberacao:</div>
                    <ul className="mt-2 list-disc space-y-1 pl-5">
                      {releaseIssues.map((issue) => <li key={issue}>{issue}</li>)}
                    </ul>
                  </div>
                )}

                <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-zinc-800 pt-5">
                  <div className="text-xs text-zinc-500">
                    Ultima decisao de producao: {formatDateTime(selected.producao_decidida_em)}
                  </div>
                  <button
                    type="button"
                    onClick={() => void releaseProduction()}
                    disabled={!canWrite || busy || releaseIssues.length > 0}
                    className="rounded-lg bg-amber-500 px-5 py-2.5 text-sm font-semibold text-black transition hover:bg-amber-400 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    {busy ? "Conferindo homologacao..." : "Conferir e liberar para esta homologacao"}
                  </button>
                </div>
              </section>
            </>
          )}
        </section>
      </div>
    </main>
  );
}
