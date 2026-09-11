"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { formatMoneyBR } from "@/lib/decimal";
import { codigoTributacaoExigeObra } from "@/supabase/functions/_shared/fiscal/nfse-obra";

/**
 * Faturar OS: NFS-e Padrao Nacional (Focus) em HOMOLOGACAO.
 *
 * Mesma ordem da NF-e: linhas (uma OS por linha, valor = saldo) -> operacao
 * (municipio de prestacao, competencia, retencoes) -> pagamento -> previa
 * (bruto, ISS, INSS, IRRF, PCC, liquido, parcelas, discriminacao) -> emissao.
 * Os campos fiscais vem de f.fn_os_nfse_conferir_homologacao (fixture +
 * cadastro); nada e deduzido e cada lacuna volta como bloqueio com campo e rota.
 */

const R$ = (value: number) => `R$ ${formatMoneyBR(value)}`;
const field = "w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500 disabled:opacity-60";
const label = "block text-xs text-zinc-400";
const botao = "rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900 disabled:cursor-not-allowed disabled:opacity-40";
const FORMAS_PAGAMENTO: Array<[string, string]> = [
  ["15", "15 · Boleto bancário"], ["17", "17 · PIX"], ["18", "18 · Transferência bancária"], ["01", "01 · Dinheiro"], ["03", "03 · Cartão de crédito"], ["99", "99 · Outros"],
];

export type PerfilServico = {
  id: string; codigo: string; nome: string; item_servico: string | null; faixa_automacao: string; habilitado_producao: boolean; justificativa_faixa: string | null; vigencia_inicio: string | null; vigencia_fim: string | null;
  // Revisao fiscal (06/09/2026): quando revisao_fiscal_em existe, as regras vem do perfil e nao da fixture.
  revisao_fiscal_em?: string | null; codigo_tributacao_nacional?: string | null; codigo_nbs?: string | null; aliquota_iss?: number | string | null; local_prestacao_regra?: string | null; incidencia_iss_regra?: string | null;
  iss_retido_regra?: string | null; retencao_pcc_regra?: string | null; retencao_irrf_regra?: string | null; retencao_inss_regra?: string | null;
  codigo_indicador_operacao?: string | null; excecao_conserto_isolado?: boolean | null; campos_conferir?: Array<{ campo: string; motivo: string; prazo?: string }> | null;
  permite_deducao_material?: boolean | null;
};
type Fixture = { item_servico: string; codigo_tributacao_nacional: string; codigo_nbs: string | null; descricao_servico_padrao: string; local_prestacao_regra: string; aliquota_iss: number | string | null; iss_retido_regra: string; retencao_pcc_regra: string; retencao_irrf_regra: string; retencao_inss_regra: string; aliquota_pcc: number | string | null; aliquota_irrf: number | string | null; aliquota_inss: number | string | null; pendencia_contador: string | null; fonte: string | null };
type ClienteNfse = { id: number; iss_retido: boolean | null; retem_pcc: boolean | null; retem_irrf: boolean | null; retem_inss: boolean | null; email_nfse: string | null; inscricao_municipal: string | null; codigo_ibge_municipio: string | null; cep: string | null; logradouro: string | null; numero_endereco: string | null; complemento: string | null; bairro: string | null };
// Local da obra (grupo obra da DPS, E0370): CNO ou endereco. Gravado pela conferencia em obra_dados.
type LocalObra = { codigo_obra: string; cep: string; logradouro: string; numero: string; complemento: string; bairro: string };
const OBRA_VAZIA: LocalObra = { codigo_obra: "", cep: "", logradouro: "", numero: "", complemento: "", bairro: "" };
// Teto da deducao de material (f.fn_os_nfse_material_disponivel): produtos lancados nas OS, fora os de venda,
// menos o ja deduzido em NFS-e dessas OS.
type MaterialReal = { material_aplicado: number | string; deduzido_em_notas: number | string; reservado_em_solicitacoes: number | string; material_deduzido: number | string; material_disponivel: number | string };
type OsLinha = { chave: number; os_id: number; os_numero: string; descricao: string; valor: string; saldo: number };
type OsCandidata = { id: number; numero_os: string | null; descricao_servico: string | null; saldo: number };
type Parcela = { dias: string; valor: string };
type Solicitacao = { id: string; status: string; perfil_operacao_id: string | null; municipio_prestacao_ibge: string | null; data_competencia: string | null; iss_retido: boolean | null; retem_pcc: boolean | null; retem_irrf: boolean | null; retem_inss: boolean | null; retencao_justificativa: string | null; valor_deducao_material?: number | string | null; pagamento_forma: string | null; pagamento_indicador: number | null; pagamento_descricao: string | null; pagamento_parcelas: Array<{ dias: number | string; valor: number | string | null }> | null; pedido_cliente: string | null; pedido_item: string | null; observacao: string | null; obra_dados: Partial<Record<keyof LocalObra, string | null>> | null; operacao_snapshot: { servico?: Record<string, unknown>; tributacao_fonte?: string | null } | null; substitui_documento_fiscal_id: string | null; substituicao_codigo: string | null; substituicao_motivo: string | null };
type Emissao = { solicitacao_id: string; documento_fiscal_id: string; status: string; ambiente: string; chave_nfse: string | null; nfse_numero: string | null; codigo_verificacao: string | null; dps_serie: number | null; dps_numero: number | null; mensagem: string | null; codigo_status: number | null; danfe_path: string | null; xml_path: string | null; valor_liquido: number | string | null; autorizado_em: string | null };
type Pendencia = { entidade?: string; campo?: string; mensagem?: string; rota?: string };
type Previa = {
  valor_bruto: number; aliquota_iss: number; valor_iss: number; iss_retido: boolean; valor_irrf: number; valor_pcc: number; valor_inss: number; valor_liquido: number; parcelas: Array<{ numero: string; dias: number; valor: number | null }> | null; descricao_servico: string; codigo_tributacao_nacional: string; codigo_nbs: string | null; municipio_prestacao_ibge: string; data_competencia: string;
  municipio_incidencia_iss?: string | null; tributacao_fonte?: string | null; item_servico?: string | null;
  valor_deducoes?: number | null; base_iss?: number | null; base_inss?: number | null;
  ibs_cbs?: { base: number; ibs_uf: number; ibs_mun: number; cbs: number; total: number } | null;
  obra?: Partial<Record<keyof LocalObra, string | null>> | null;
  tributos_aprox?: { federal_pct: number | null; municipal_pct: number | null; federal: number; municipal: number } | null;
  campos_conferir?: Array<{ campo: string; motivo: string; prazo?: string }> | null;
};

export type FaturarNfseOsProps = {
  tenantId: string | null; empresaId: string | null; osId: number;
  os: { id: number; numero_os: string | null; cliente_id: number | null; descricao_servico: string | null; status_fluxo: string | null; pedido_compra?: string | null; conserto_isolado?: boolean | null } | null;
  cliente: { id: number; uf: string | null; codigo_ibge_municipio: string | null } | null;
  saldo: number; empresaIbge: string | null;
  perfil: PerfilServico | null; perfis: PerfilServico[];
  custoReal: number | null; motivoBloqueioOs: string | null; versao: number;
  onAtualizar: () => Promise<void> | void;
  abrirArquivo: (documentoFiscalId: string, arquivo: "XML" | "DANFE") => Promise<void>;
};

function num(value: unknown) {
  if (value === null || value === undefined || value === "") return 0;
  const n = typeof value === "number" ? value : Number(String(value).replace(/\./g, "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}
function paraNumero(value: string) {
  const s = value.trim().replace(/\./g, "").replace(",", ".");
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}
function decimal(value: unknown) {
  if (value === null || value === undefined || String(value).trim() === "") return "";
  return String(value).replace(".", ",");
}
function textoErro(cause: unknown) {
  if (cause instanceof Error) return cause.message;
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return String(cause);
}
async function erroFunction(cause: unknown) {
  if (cause && typeof cause === "object" && "context" in cause) {
    const response = (cause as { context?: unknown }).context;
    if (response instanceof Response) {
      try {
        const body = await response.clone().json() as { erro?: string; error?: string; codigo?: string | number };
        const msg = body.erro ?? body.error;
        if (msg) return body.codigo ? `${body.codigo} · ${msg}` : msg;
      } catch { /* padrao abaixo */ }
    }
  }
  return textoErro(cause);
}
function tri(value: boolean | null | undefined) { return value === true ? "sim" : value === false ? "nao" : ""; }
function deTri(value: string): boolean | null { return value === "sim" ? true : value === "nao" ? false : null; }
function regraTexto(regra: string, valorCliente: boolean | null) {
  if (regra === "NUNCA") return "nunca (regra do perfil)";
  if (regra === "SEMPRE") return "sempre (regra do perfil)";
  return valorCliente === null ? "indefinido no cadastro" : valorCliente ? "cadastro: retém" : "cadastro: não retém";
}

export default function FaturarNfseOs(props: FaturarNfseOsProps) {
  const { tenantId, empresaId, osId, os, cliente, saldo, perfil, custoReal, motivoBloqueioOs, versao, onAtualizar, abrirArquivo } = props;
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [fixtures, setFixtures] = useState<Fixture[]>([]);
  const [clienteNfse, setClienteNfse] = useState<ClienteNfse | null>(null);
  const [prazoCancelamento, setPrazoCancelamento] = useState<number | null>(null);
  // HORAS: ate N horas apos a autorizacao. MES_EMISSAO: ate o ultimo dia do mes de emissao (Joinville, Decreto 30.798/2018).
  const [prazoRegra, setPrazoRegra] = useState<"HORAS" | "MES_EMISSAO">("HORAS");
  const [candidatas, setCandidatas] = useState<OsCandidata[]>([]);
  const [linhas, setLinhas] = useState<OsLinha[]>([]);
  const [proximaChave, setProximaChave] = useState(2);
  const [municipio, setMunicipio] = useState("");
  const [competencia, setCompetencia] = useState(new Date().toISOString().slice(0, 10));
  const [issRetido, setIssRetido] = useState("");
  const [pcc, setPcc] = useState("");
  const [irrf, setIrrf] = useState("");
  const [inss, setInss] = useState("");
  // Conserto isolado (IN SRF 459/2004 art. 1 §2 II): marcado na OS, dispensa a CRF nos perfis com excecao (14.01).
  const [consertoIsolado, setConsertoIsolado] = useState<boolean>(props.os?.conserto_isolado === true);
  // Material incorporado a obra (07.02): sai da base do ISS e do INSS (LC 116/2003 art. 7 §2 I).
  const [materialDeducao, setMaterialDeducao] = useState("");
  const [obra, setObra] = useState<LocalObra>(OBRA_VAZIA);
  const [materialReal, setMaterialReal] = useState<MaterialReal | null>(null);
  const [materialSugerido, setMaterialSugerido] = useState(false);
  const [justificativa, setJustificativa] = useState("");
  const [pagamentoForma, setPagamentoForma] = useState("15");
  const [pagamentoIndicador, setPagamentoIndicador] = useState("1");
  const [pagamentoDescricao, setPagamentoDescricao] = useState("");
  const [parcelas, setParcelas] = useState<Parcela[]>([{ dias: "30", valor: "" }]);
  const [pedidoCliente, setPedidoCliente] = useState("");
  const [pedidoItem, setPedidoItem] = useState("");
  const [observacao, setObservacao] = useState("");
  const [solicitacao, setSolicitacao] = useState<Solicitacao | null>(null);
  const [emissao, setEmissao] = useState<Emissao | null>(null);
  const [previa, setPrevia] = useState<Previa | null>(null);
  const [bloqueios, setBloqueios] = useState<Pendencia[]>([]);
  const [avisos, setAvisos] = useState<Pendencia[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [carregando, setCarregando] = useState(true);
  const [justificativaCancel, setJustificativaCancel] = useState("");
  // "Nova NFS-e parcial": ignora a nota autorizada mais recente e abre uma composicao nova.
  const [novaNota, setNovaNota] = useState(false);

  const fixture = useMemo(() => fixtures.find((f) => f.item_servico === perfil?.item_servico) ?? null, [fixtures, perfil]);
  const perfilBloqueado = perfil?.faixa_automacao === "BLOQUEADO";
  const perfilRevisado = Boolean(perfil?.revisao_fiscal_em && perfil?.codigo_tributacao_nacional);
  // Regras de retencao: do perfil revisado; senao, da fixture provisoria de homologacao.
  const regras = useMemo(() => ({
    iss: (perfilRevisado ? perfil?.iss_retido_regra : fixture?.iss_retido_regra) ?? "POR_TOMADOR",
    pcc: (perfilRevisado ? perfil?.retencao_pcc_regra : fixture?.retencao_pcc_regra) ?? "POR_TOMADOR",
    irrf: (perfilRevisado ? perfil?.retencao_irrf_regra : fixture?.retencao_irrf_regra) ?? "POR_TOMADOR",
    inss: (perfilRevisado ? perfil?.retencao_inss_regra : fixture?.retencao_inss_regra) ?? "POR_TOMADOR",
    local: (perfilRevisado ? perfil?.local_prestacao_regra : fixture?.local_prestacao_regra) ?? null,
  }), [fixture, perfil, perfilRevisado]);
  // Codigo de obra (070201 e os da lista do E0370) exige o local da obra na DPS.
  const codigoTribNac = perfilRevisado ? perfil?.codigo_tributacao_nacional : fixture?.codigo_tributacao_nacional;
  const exigeObra = codigoTributacaoExigeObra(codigoTribNac);
  const camposConferir = perfil?.campos_conferir ?? [];
  const totalLinhas = useMemo(() => linhas.reduce((s, l) => s + (paraNumero(l.valor) ?? 0), 0), [linhas]);
  const municipioPadrao = regras.local ? (regras.local === "SEDE" ? props.empresaIbge ?? "" : cliente?.codigo_ibge_municipio ?? "") : "";

  const carregar = useCallback(async () => {
    if (!tenantId || !empresaId || !os) return;
    setCarregando(true);
    try {
      const [{ data: fx }, { data: cli }, { data: ef }] = await Promise.all([
        supabase.schema("f").from("tributacao_provisoria_nfse_homologacao").select("item_servico,codigo_tributacao_nacional,codigo_nbs,descricao_servico_padrao,local_prestacao_regra,aliquota_iss,iss_retido_regra,retencao_pcc_regra,retencao_irrf_regra,retencao_inss_regra,aliquota_pcc,aliquota_irrf,aliquota_inss,pendencia_contador,fonte").eq("ativo", true),
        os.cliente_id ? supabase.from("clientes").select("id,iss_retido,retem_pcc,retem_irrf,retem_inss,email_nfse,inscricao_municipal,codigo_ibge_municipio,cep,logradouro,numero_endereco,complemento,bairro").eq("id", os.cliente_id).maybeSingle() : Promise.resolve({ data: null }),
        supabase.schema("f").rpc("fn_nfse_contexto_empresa", { p_empresa_id: empresaId }),
      ]);
      setFixtures((fx as Fixture[] | null) ?? []);
      setClienteNfse((cli as ClienteNfse | null) ?? null);
      const contextoEmpresa = ef as { prazo_cancelamento_nfse_horas?: number | null; prazo_cancelamento_nfse_regra?: string | null } | null;
      setPrazoCancelamento(contextoEmpresa?.prazo_cancelamento_nfse_horas ?? null);
      setPrazoRegra(contextoEmpresa?.prazo_cancelamento_nfse_regra === "MES_EMISSAO" ? "MES_EMISSAO" : "HORAS");

      // Rascunho de NFS-e desta OS (nao cancelado, emissao ainda nao AUTORIZADA/CANCELADA) ou a NFS-e autorizada mais recente.
      const { data: itens } = await supabase.schema("f").from("solicitacao_item").select("solicitacao_id").eq("origem_tipo", "OS").eq("origem_id", String(osId)).eq("modelo", "NFSE");
      const ids = Array.from(new Set(((itens as Array<{ solicitacao_id: string }> | null) ?? []).map((r) => r.solicitacao_id)));
      let ativa: Solicitacao | null = null;
      let emissaoAtiva: Emissao | null = null;
      if (ids.length > 0) {
        const { data: sols } = await supabase.schema("f").from("solicitacao_faturamento").select("id,status,perfil_operacao_id,municipio_prestacao_ibge,data_competencia,iss_retido,retem_pcc,retem_irrf,retem_inss,retencao_justificativa,valor_deducao_material,pagamento_forma,pagamento_indicador,pagamento_descricao,pagamento_parcelas,pedido_cliente,pedido_item,observacao,obra_dados,operacao_snapshot,substitui_documento_fiscal_id,substituicao_codigo,substituicao_motivo").in("id", ids).neq("status", "CANCELADA").order("created_at", { ascending: false }).limit(8);
        const cands = (sols as Solicitacao[] | null) ?? [];
        if (cands.length > 0) {
          const { data: ems } = await supabase.schema("f").from("documento_fiscal_emissao").select("solicitacao_id,documento_fiscal_id,status,ambiente,chave_nfse,nfse_numero,codigo_verificacao,dps_serie,dps_numero,mensagem,codigo_status,danfe_path,xml_path,valor_liquido,autorizado_em").in("solicitacao_id", cands.map((c) => c.id)).order("created_at", { ascending: false });
          const emissoes = (ems as Emissao[] | null) ?? [];
          for (const c of cands) {
            const em = emissoes.find((e) => e.solicitacao_id === c.id) ?? null;
            if (!em || !["AUTORIZADA", "CANCELADA"].includes(em.status)) { ativa = c; emissaoAtiva = em; break; }
          }
          if (!ativa && !novaNota) {
            // Ultima autorizada em homologacao (para cancelar/substituir a partir daqui).
            const aut = cands.find((c) => emissoes.some((e) => e.solicitacao_id === c.id && e.status === "AUTORIZADA"));
            if (aut) { ativa = aut; emissaoAtiva = emissoes.find((e) => e.solicitacao_id === aut.id) ?? null; }
          }
        }
      }
      setSolicitacao(ativa);
      setEmissao(emissaoAtiva);
      if (ativa) {
        if (ativa.municipio_prestacao_ibge) setMunicipio(ativa.municipio_prestacao_ibge);
        if (ativa.data_competencia) setCompetencia(ativa.data_competencia);
        setIssRetido(tri(ativa.iss_retido)); setPcc(tri(ativa.retem_pcc)); setIrrf(tri(ativa.retem_irrf)); setInss(tri(ativa.retem_inss));
        setJustificativa(ativa.retencao_justificativa ?? "");
        setMaterialDeducao(ativa.valor_deducao_material != null && num(ativa.valor_deducao_material) > 0 ? decimal(ativa.valor_deducao_material) : "");
        const obraGravada = ativa.obra_dados ?? {};
        setObra({ codigo_obra: obraGravada.codigo_obra ?? "", cep: obraGravada.cep ?? "", logradouro: obraGravada.logradouro ?? "", numero: obraGravada.numero ?? "", complemento: obraGravada.complemento ?? "", bairro: obraGravada.bairro ?? "" });
        if (ativa.pagamento_forma) setPagamentoForma(ativa.pagamento_forma);
        if (ativa.pagamento_indicador != null) setPagamentoIndicador(String(ativa.pagamento_indicador));
        setPagamentoDescricao(ativa.pagamento_descricao ?? "");
        if (Array.isArray(ativa.pagamento_parcelas) && ativa.pagamento_parcelas.length > 0) setParcelas(ativa.pagamento_parcelas.map((p) => ({ dias: String(p.dias ?? ""), valor: decimal(p.valor) })));
        setPedidoCliente(ativa.pedido_cliente ?? "");
        setPedidoItem(ativa.pedido_item ?? "");
        if (ativa.observacao && !/^NFS-e de servico da OS|^Substituicao da NFS-e/i.test(ativa.observacao)) setObservacao(ativa.observacao);
        const serv = ativa.operacao_snapshot?.servico as Previa | undefined;
        // As parcelas ficam no bloco pagamento do snapshot; a previa recarregada precisa delas.
        const parcelasSnapshot = Array.isArray(ativa.pagamento_parcelas) ? ativa.pagamento_parcelas.map((p, i) => ({ numero: String(i + 1).padStart(3, "0"), dias: Number(p.dias ?? 0), valor: p.valor == null ? null : num(p.valor) })) : null;
        // A fonte da tributacao fica no topo do snapshot, fora do servico: sem ela a previa recarregada dizia "fixture" em perfil revisado.
        setPrevia(serv && serv.valor_bruto != null ? { ...serv, parcelas: serv.parcelas ?? parcelasSnapshot, tributacao_fonte: serv.tributacao_fonte ?? ativa.operacao_snapshot?.tributacao_fonte ?? null } : null);
        const { data: its } = await supabase.schema("f").from("solicitacao_item").select("origem_id,descricao_servico,valor_servico,ordem").eq("solicitacao_id", ativa.id).order("ordem");
        const rows = (its as Array<{ origem_id: string; descricao_servico: string | null; valor_servico: number | string | null; ordem: number }> | null) ?? [];
        setLinhas(rows.map((r, i) => ({ chave: i + 1, os_id: Number(r.origem_id), os_numero: r.origem_id === String(osId) ? (os.numero_os ?? String(os.id)) : r.origem_id, descricao: r.descricao_servico ?? "", valor: decimal(num(r.valor_servico).toFixed(2)), saldo: 0 })));
      } else {
        setPrevia(null);
        setLinhas((atuais) => atuais.length > 0 ? atuais : [{ chave: 1, os_id: os.id, os_numero: os.numero_os ?? String(os.id), descricao: os.descricao_servico ?? `OS ${os.numero_os ?? os.id}`, valor: decimal(Math.max(saldo, 0).toFixed(2)), saldo }]);
        setPedidoCliente((atual) => atual || (os.pedido_compra ?? ""));
      }
      setCarregando(false);

      // Outras OS do mesmo tomador (fase 3: uma linha por OS, cada uma reserva a propria). Carrega por ultimo, em paralelo.
      if (os.cliente_id && !ativa) {
        const { data: outras } = await supabase.from("ordens_servico").select("id,numero_os,descricao_servico,status_fluxo").eq("cliente_id", os.cliente_id).eq("tipo_documento", "OS").neq("id", os.id).order("id", { ascending: false }).limit(30);
        const abertas = ((outras as Array<{ id: number; numero_os: string | null; descricao_servico: string | null; status_fluxo: string | null }> | null) ?? []).filter((o) => !["cancelada", "faturada"].includes(String(o.status_fluxo ?? "").toLowerCase())).slice(0, 12);
        const saldos = await Promise.all(abertas.map(async (o) => {
          const { data: s } = await supabase.schema("f").rpc("fn_os_saldo_a_faturar", { p_tenant_id: tenantId, p_empresa_id: empresaId, p_os_id: o.id });
          const row = (Array.isArray(s) ? s[0] : s) as { saldo: number | string } | null;
          return { id: o.id, numero_os: o.numero_os, descricao_servico: o.descricao_servico, saldo: row ? num(row.saldo) : 0 };
        }));
        setCandidatas(saldos.filter((c) => c.saldo > 0));
      }
    } catch (cause) { setErro(textoErro(cause)); } finally { setCarregando(false); }
  }, [empresaId, novaNota, os, osId, saldo, supabase, tenantId]);

  useEffect(() => { void carregar(); }, [carregar, versao]);
  useEffect(() => { if (!solicitacao && !municipio && municipioPadrao) setMunicipio(municipioPadrao); }, [municipioPadrao, municipio, solicitacao]);
  // Material real da obra das OS da nota (fora a propria solicitacao, que esta sendo conferida).
  const osIdsLinhas = useMemo(() => Array.from(new Set(linhas.map((l) => l.os_id))).sort((a, b) => a - b), [linhas]);
  const chaveOsLinhas = osIdsLinhas.join(",");
  useEffect(() => {
    if (!tenantId || !empresaId || !perfil?.permite_deducao_material || !chaveOsLinhas) { setMaterialReal(null); return; }
    let ativo = true;
    void supabase.schema("f").rpc("fn_os_nfse_material_disponivel", {
      p_tenant_id: tenantId, p_empresa_id: empresaId, p_os_ids: chaveOsLinhas.split(",").map(Number), p_excluir_solicitacao: solicitacao?.id ?? null,
    }).then(({ data }) => { if (ativo) setMaterialReal((data as MaterialReal | null) ?? null); });
    return () => { ativo = false; };
  }, [chaveOsLinhas, empresaId, perfil?.permite_deducao_material, solicitacao?.id, supabase, tenantId, versao]);
  // Composicao nova: a deducao ja vem com o material real disponivel, uma vez (quem apagar o campo decide).
  // Disponivel igual ou maior que o servico nao e sugerido: a deducao precisa ser menor que o valor da nota.
  useEffect(() => {
    if (solicitacao || materialSugerido || !materialReal || materialDeducao.trim()) return;
    const disponivel = num(materialReal.material_disponivel);
    if (disponivel > 0 && disponivel < totalLinhas) setMaterialDeducao(decimal(disponivel.toFixed(2)));
    setMaterialSugerido(true);
  }, [materialDeducao, materialReal, materialSugerido, solicitacao, totalLinhas]);
  // Sugestao do local da obra: o endereco do tomador, como nas NFS-e reais da WEG Tintas. So preenche o que esta vazio.
  useEffect(() => {
    if (!exigeObra || !clienteNfse) return;
    setObra((atual) => Object.values(atual).some((v) => v.trim()) ? atual : {
      codigo_obra: "", cep: clienteNfse.cep ?? "", logradouro: clienteNfse.logradouro ?? "", numero: clienteNfse.numero_endereco ?? "",
      complemento: (clienteNfse.complemento ?? "").replace(/\s+/g, " ").trim(), bairro: clienteNfse.bairro ?? "",
    });
  }, [clienteNfse, exigeObra]);
  useEffect(() => {
    if (!emissao || !["ENVIANDO", "PROCESSANDO"].includes(emissao.status)) return;
    const timer = window.setInterval(() => void carregar(), 5000);
    return () => window.clearInterval(timer);
  }, [carregar, emissao]);

  function operacaoPayload() {
    return {
      perfil_operacao_id: perfil?.id ?? null,
      municipio_prestacao_ibge: municipio.trim() || null,
      data_competencia: competencia || null,
      iss_retido: deTri(issRetido), retem_pcc: deTri(pcc), retem_irrf: deTri(irrf), retem_inss: deTri(inss),
      conserto_isolado: consertoIsolado,
      valor_deducao_material: perfil?.permite_deducao_material ? (paraNumero(materialDeducao) ?? 0) : 0,
      obra: exigeObra ? {
        codigo_obra: obra.codigo_obra.trim() || null, cep: obra.cep.replace(/\D/g, ""), logradouro: obra.logradouro.trim(),
        numero: obra.numero.trim(), complemento: obra.complemento.trim() || null, bairro: obra.bairro.trim(),
      } : null,
      retencao_justificativa: justificativa.trim() || null,
      pagamento_forma: pagamentoForma, pagamento_indicador: Number(pagamentoIndicador), pagamento_descricao: pagamentoDescricao || null,
      pagamento_parcelas: pagamentoIndicador === "1" ? parcelas.map((p, i) => ({ numero: String(i + 1).padStart(3, "0"), dias: Number(p.dias.trim()), valor: p.valor.trim() ? paraNumero(p.valor) : null })) : null,
      // pedido_cliente vazio e enviado como "" de proposito: limpa o pedido (nao herda o texto da OS).
      pedido_cliente: pedidoCliente.trim(), pedido_item: pedidoItem.trim() || null, observacao: observacao.trim() || null,
    };
  }

  async function conferir() {
    if (!tenantId || !empresaId || !os || !perfil) return;
    setOcupado(true); setErro(null); setAviso(null); setBloqueios([]); setAvisos([]);
    try {
      let solId = solicitacao?.id ?? null;
      if (!solId) {
        const invalida = linhas.findIndex((l) => !l.descricao.trim() || (paraNumero(l.valor) ?? 0) <= 0);
        if (invalida >= 0) throw new Error(`Linha ${invalida + 1}: descrição e valor precisam estar preenchidos.`);
        const { data, error } = await supabase.schema("f").rpc("fn_solicitacao_faturamento_criar_os_servico", {
          p_tenant_id: tenantId, p_empresa_id: empresaId, p_perfil_operacao_id: perfil.id,
          p_linhas: linhas.map((l) => ({ os_id: l.os_id, descricao_servico: l.descricao.trim(), valor_servico: paraNumero(l.valor) })),
        });
        if (error) throw error;
        solId = String(data);
      }
      const { data: r, error: erroConferir } = await supabase.schema("f").rpc("fn_os_nfse_conferir_homologacao", { p_solicitacao_id: solId, p_operacao: operacaoPayload() });
      if (erroConferir) throw erroConferir;
      const res = r as { ok?: boolean; pendencias?: Pendencia[]; avisos?: Pendencia[]; previa?: Previa } | null;
      setAvisos(res?.avisos ?? []);
      if (!res?.ok) {
        setBloqueios(res?.pendencias ?? []);
        setPrevia(null);
        setAviso("Conferência salva com bloqueios. Corrija onde indicado e confira de novo.");
      } else {
        setPrevia(res.previa ?? null);
        setAviso(res.previa?.tributacao_fonte === "PERFIL"
          ? "Conferência salva: valores do perfil de serviço revisado e do cadastro do tomador. Revise a prévia e emita."
          : "Conferência salva: valores da fixture provisória de homologação e do cadastro do tomador. Revise a prévia e emita.");
      }
      await carregar();
      await onAtualizar();
    } catch (cause) { const msg = textoErro(cause); setBloqueios([{ mensagem: msg }]); setErro(msg); } finally { setOcupado(false); }
  }

  async function emitir() {
    if (!solicitacao || !previa) return;
    if (!window.confirm(`Emitir NFS-e em HOMOLOGAÇÃO (sem valor fiscal) para a OS ${os?.numero_os ?? os?.id}?\n\nBruto ${R$(num(previa.valor_bruto))} · líquido ${R$(num(previa.valor_liquido))}`)) return;
    setOcupado(true); setErro(null); setAviso(null);
    try {
      const { data, error } = await supabase.functions.invoke("nfse-emitir", { body: { solicitacao_id: solicitacao.id } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `${data.codigo} · ${data.erro}` : String(data.erro));
      setAviso(`DPS ${data?.dps_serie ?? "?"}/${data?.dps_numero ?? "?"} enviada à Focus em homologação. O saldo já está reservado; o retorno chega automaticamente.`);
    } catch (cause) { setErro(await erroFunction(cause)); } finally { await carregar(); await onAtualizar(); setOcupado(false); }
  }

  async function descartar() {
    if (!solicitacao) return;
    const autorizada = emissao?.status === "AUTORIZADA";
    // Rascunho que ja foi tentado (REJEITADA/ERRO) tem material congelado: sai pelo abandono auditado, nao pelo descarte simples.
    const tentada = Boolean(emissao && ["REJEITADA", "ERRO", "AUTORIZADA"].includes(emissao.status));
    const motivo = window.prompt(autorizada ? "Motivo do abandono da homologação (15 a 255). A NFS-e de teste continua no ambiente nacional de homologação; só o saldo volta." : "Motivo do descarte do rascunho (15 a 255):", autorizada ? "Homologacao concluida; saldo devolvido a OS" : "Rascunho refeito pela tela de faturar a OS");
    if (!motivo) return;
    setOcupado(true); setErro(null);
    try {
      const { error } = await supabase.schema("f").rpc(tentada ? "fn_nfse_abandonar_homologacao" : "fn_solicitacao_nfe_cancelar_rascunho", { p_solicitacao_id: solicitacao.id, p_motivo: motivo });
      if (error) throw error;
      setSolicitacao(null); setEmissao(null); setPrevia(null); setLinhas([]); setBloqueios([]);
      setMaterialDeducao(""); setMaterialSugerido(false);
      await carregar(); await onAtualizar();
    } catch (cause) { setErro(textoErro(cause)); } finally { setOcupado(false); }
  }

  async function emitirProducao() {
    if (!solicitacao || !emissao) return;
    if (!window.confirm(`EMITIR NFS-e REAL (produção) para a OS ${os?.numero_os ?? os?.id}?\n\nBruto ${R$(num(previa?.valor_bruto))} · líquido ${R$(num(previa?.valor_liquido))}. Gera documento fiscal válido e título a receber.`)) return;
    setOcupado(true); setErro(null); setAviso(null);
    try {
      const { data, error } = await supabase.functions.invoke("nfse-emitir", { body: { solicitacao_id: solicitacao.id, ambiente: "PRODUCAO" } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `${data.codigo} · ${data.erro}` : String(data.erro));
      setAviso(`DPS ${data?.dps_serie ?? "?"}/${data?.dps_numero ?? "?"} enviada à Focus em PRODUÇÃO. O retorno chega automaticamente.`);
    } catch (cause) { setErro(await erroFunction(cause)); } finally { await carregar(); await onAtualizar(); setOcupado(false); }
  }

  async function cancelar() {
    if (!emissao) return;
    if (justificativaCancel.trim().length < 15) { setErro("Justificativa do cancelamento: 15 a 255 caracteres."); return; }
    if (!window.confirm(emissao.ambiente === "PRODUCAO" ? "CANCELAR A NFS-e REAL no ambiente nacional? O documento e o título a receber são cancelados e o saldo da OS volta." : "Cancelar a NFS-e no ambiente nacional de homologação? O saldo da OS volta.")) return;
    setOcupado(true); setErro(null);
    try {
      const { data, error } = await supabase.functions.invoke("nfse-ciclo", { body: { acao: "CANCELAR", documento_fiscal_id: emissao.documento_fiscal_id, justificativa: justificativaCancel.trim() } });
      if (error) throw error;
      if (data?.error) throw new Error(String(data.error));
      setAviso(`NFS-e ${emissao.nfse_numero ?? ""} cancelada; saldo devolvido à OS.`);
    } catch (cause) { setErro(await erroFunction(cause)); } finally { await carregar(); await onAtualizar(); setOcupado(false); }
  }

  // E-mail pela Focus (XML + DANFSe), so em producao: em homologacao a nota nao tem valor fiscal.
  async function enviarEmail() {
    if (!emissao) return;
    const sugestao = clienteNfse?.email_nfse ?? "";
    const digitado = window.prompt("E-mails para envio da NFS-e (XML + DANFSe), separados por vírgula:", sugestao);
    if (!digitado) return;
    const emails = digitado.split(/[,;\s]+/).map((e) => e.trim().toLowerCase()).filter(Boolean);
    if (emails.length === 0) return;
    setOcupado(true); setErro(null); setAviso(null);
    try {
      const { data, error } = await supabase.functions.invoke("nfse-ciclo", { body: { acao: "EMAIL", documento_fiscal_id: emissao.documento_fiscal_id, emails } });
      if (error) throw error;
      if (data?.error) throw new Error(String(data.error));
      setAviso(`E-mail enfileirado na Focus para ${emails.join(", ")}.`);
    } catch (cause) { setErro(await erroFunction(cause)); } finally { await carregar(); setOcupado(false); }
  }

  async function substituir() {
    if (!emissao) return;
    const codigo = window.prompt("Código de justificativa da substituição: 01 desenquadramento SN · 02 enquadramento SN · 03 inclusão retroativa de imunidade · 04 exclusão retroativa · 05 rejeição pelo tomador · 99 outros", "99");
    if (!codigo) return;
    const motivo = window.prompt("Motivo da substituição (15 a 255 caracteres):", "");
    if (!motivo) return;
    setOcupado(true); setErro(null);
    try {
      const { error } = await supabase.schema("f").rpc("fn_nfse_substituir_preparar", { p_documento_fiscal_id: emissao.documento_fiscal_id, p_codigo: codigo.trim(), p_motivo: motivo.trim() });
      if (error) throw error;
      setAviso("Rascunho da NFS-e substituta criado com os mesmos dados. Ajuste o que precisar, confira e emita; a antiga passa a SUBSTITUÍDA quando a nova for autorizada.");
      setSolicitacao(null); setEmissao(null); setPrevia(null); setLinhas([]);
      await carregar(); await onAtualizar();
    } catch (cause) { setErro(textoErro(cause)); } finally { setOcupado(false); }
  }

  const autorizada = emissao?.status === "AUTORIZADA";
  const emProcessamento = emissao ? ["ENVIANDO", "PROCESSANDO"].includes(emissao.status) : false;
  const editavel = !solicitacao || !emissao || ["RASCUNHO", "REJEITADA", "ERRO"].includes(emissao.status);
  const conferida = Boolean(previa) && Boolean(solicitacao);
  const margem = custoReal !== null ? (conferida ? num(previa?.valor_bruto) : totalLinhas) - custoReal : null;
  const bloqueioLocal = !perfil ? "Escolha o perfil de serviço." : perfilBloqueado ? `Perfil ${perfil.item_servico} bloqueado: ${perfil.justificativa_faixa ?? "aguarda o contador."}` : !fixture ? `Sem fixture provisória para o item ${perfil.item_servico}.` : null;
  const producao = emissao?.ambiente === "PRODUCAO";
  const podeCancelar = autorizada && (!producao || prazoRegra === "MES_EMISSAO" || prazoCancelamento !== null);
  const textoPrazo = prazoRegra === "MES_EMISSAO"
    ? "Prazo: até o último dia do mês de emissão (Joinville, Decreto 30.798/2018); depois, só substituição."
    : prazoCancelamento === null ? null : `Prazo: ${prazoCancelamento} h após a autorização.`;
  const [producaoPronta, setProducaoPronta] = useState<{ pronta: boolean; motivo?: string } | null>(null);
  useEffect(() => {
    if (!solicitacao || !autorizada || producao) { setProducaoPronta(null); return; }
    let ativo = true;
    void supabase.schema("f").rpc("fn_nfse_producao_pronta", { p_solicitacao_id: solicitacao.id }).then(({ data }) => {
      if (ativo) setProducaoPronta((data as { pronta: boolean; motivo?: string } | null) ?? null);
    });
    return () => { ativo = false; };
  }, [autorizada, producao, solicitacao, supabase, versao]);

  return (
    <>
      {erro ? <div role="alert" className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm text-red-200">{erro}</div> : null}
      {aviso ? <div role="status" className="rounded-md border border-sky-900 bg-sky-950/30 p-3 text-sm text-sky-200">{aviso}</div> : null}
      {carregando ? <div className="text-sm text-zinc-500">Carregando dados da NFS-e...</div> : null}

      {/* 2 · Linhas de serviço */}
      <section className="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex items-center justify-between"><h2 className="font-semibold">Linhas da NFS-e (uma OS por linha)</h2>
          {!solicitacao && candidatas.length > 0 ? (
            <select className={`${field} w-auto`} value="" onChange={(e) => { const c = candidatas.find((x) => String(x.id) === e.target.value); if (!c) return; setLinhas((a) => [...a, { chave: proximaChave, os_id: c.id, os_numero: c.numero_os ?? String(c.id), descricao: c.descricao_servico ?? `OS ${c.numero_os ?? c.id}`, valor: decimal(c.saldo.toFixed(2)), saldo: c.saldo }]); setProximaChave((k) => k + 1); }}>
              <option value="">Adicionar OS do mesmo tomador…</option>
              {candidatas.filter((c) => !linhas.some((l) => l.os_id === c.id)).map((c) => <option key={c.id} value={c.id}>OS {c.numero_os ?? c.id} · {c.descricao_servico} · saldo {R$(c.saldo)}</option>)}
            </select>
          ) : null}
        </div>
        {linhas.map((linha, index) => (
          <div key={linha.chave} className="grid gap-2 rounded-lg border border-zinc-800 p-3 md:grid-cols-[110px_1fr_160px_auto]">
            <div className={label}>OS<div className="py-2 text-sm text-zinc-100">{linha.os_numero}</div>{linha.saldo > 0 && !solicitacao ? <div className="text-xs text-zinc-500">saldo {R$(linha.saldo)}</div> : null}</div>
            <label className={label}>Descrição do serviço<input className={field} value={linha.descricao} disabled={Boolean(solicitacao)} onChange={(e) => setLinhas((a) => a.map((l) => l.chave === linha.chave ? { ...l, descricao: e.target.value } : l))} /></label>
            <label className={label}>Valor (R$)<input className={field} inputMode="decimal" value={linha.valor} disabled={Boolean(solicitacao)} onChange={(e) => setLinhas((a) => a.map((l) => l.chave === linha.chave ? { ...l, valor: e.target.value } : l))} /></label>
            <div className="md:pt-5">{!solicitacao && linhas.length > 1 ? <button type="button" className="text-xs text-zinc-400 hover:text-zinc-200" onClick={() => setLinhas((a) => a.filter((l) => l.chave !== linha.chave))}>Remover</button> : <span className="text-xs text-zinc-600">linha {index + 1}</span>}</div>
          </div>
        ))}
        <div className="grid gap-2 rounded-lg border border-zinc-800 p-3 text-sm md:grid-cols-3">
          <div>Total das linhas <strong>{R$(conferida ? num(previa?.valor_bruto) : totalLinhas)}</strong>{!solicitacao && totalLinhas > linhas.reduce((s, l) => s + l.saldo, 0) + 0.005 ? <span className="ml-2 text-red-300">acima do saldo</span> : null}</div>
          <div>Custo real da OS <strong>{custoReal !== null ? R$(custoReal) : "—"}</strong></div>
          <div>Margem <strong className={margem !== null && margem < 0 ? "text-red-300" : "text-emerald-300"}>{margem !== null ? R$(margem) : "—"}</strong>{margem !== null && margem < 0 ? <span className="ml-2 text-xs text-amber-300">abaixo do custo; a decisão é do gestor</span> : null}</div>
        </div>
      </section>

      {/* 3 · Operação */}
      <section className="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <h2 className="font-semibold">Operação de serviço</h2>
        {perfil ? (
          <div className={`rounded-md border p-2 text-sm ${perfilBloqueado ? "border-red-900/60 bg-red-950/20 text-red-100" : "border-amber-900/60 bg-amber-950/20 text-amber-100"}`}>
            <div><strong>{perfil.codigo} · {perfil.nome}</strong> · {perfil.habilitado_producao ? "produção" : perfilRevisado ? "revisado; produção após homologação e liberação" : "somente homologação (perfil sem valor fiscal)"}</div>
            {perfilBloqueado ? <div className="text-xs">BLOQUEADO: {perfil.justificativa_faixa}</div>
              : perfilRevisado ? <div className="text-xs">Perfil revisado: cTribNac {perfil.codigo_tributacao_nacional}{perfil.codigo_nbs ? ` · NBS ${perfil.codigo_nbs}` : ""} · ISS {decimal(perfil.aliquota_iss) || "?"}% ({perfil.incidencia_iss_regra === "LOCAL_PRESTACAO" ? "incide no município da prestação" : "incide na sede"}) · local {regras.local === "SEDE" ? "sede" : "cliente"} · cIndOp {perfil.codigo_indicador_operacao ?? <span className="text-red-300">vazio (obrigatório desde 01/10/2026)</span>}</div>
              : fixture ? <div className="text-xs">Fixture provisória: cTribNac {fixture.codigo_tributacao_nacional}{fixture.codigo_nbs ? ` · NBS ${fixture.codigo_nbs}` : ""} · ISS {decimal(fixture.aliquota_iss) || "?"}% · local {fixture.local_prestacao_regra === "SEDE" ? "sede" : "cliente"} · fonte: {fixture.fonte}</div>
              : <div className="text-xs">Sem fixture provisória para {perfil.item_servico}.</div>}
            {!perfilRevisado && fixture?.pendencia_contador ? <div className="text-xs">Falta do contador: {fixture.pendencia_contador}</div> : null}
            {camposConferir.length > 0 ? <div className="mt-1 text-xs">Campos travados (produção bloqueada até a confirmação; homologação segue): {camposConferir.map((c) => `${c.campo} — ${c.motivo}${c.prazo ? ` (até ${c.prazo})` : ""}`).join("; ")}</div> : null}
          </div>
        ) : <div className="text-sm text-amber-300">Escolha o perfil de serviço no cabeçalho.</div>}
        <div className="grid gap-3 md:grid-cols-3">
          <label className={label}>Município de prestação (IBGE, 7 dígitos)<input className={field} value={municipio} disabled={!editavel} onChange={(e) => setMunicipio(e.target.value.replace(/\D/g, "").slice(0, 7))} placeholder={municipioPadrao || "regra do perfil"} /><span className="text-xs text-zinc-500">{regras.local === "SEDE" ? "Regra do perfil: sede da empresa" : "Regra do perfil: município do tomador"}. Editável.</span></label>
          <label className={label}>Competência<input type="date" className={field} value={competencia} disabled={!editavel} onChange={(e) => setCompetencia(e.target.value)} /></label>
          <div className={label}>Tomador<div className="py-2 text-sm text-zinc-100">IM {clienteNfse?.inscricao_municipal ?? <span className="text-amber-300">vazia</span>} · e-mail NFS-e {clienteNfse?.email_nfse ?? <span className="text-amber-300">vazio</span>}</div>{cliente ? <Link className="text-xs text-sky-300 underline" href={`/clientes/cadastro-fiscal?cliente_id=${cliente.id}`}>Cadastro fiscal do cliente</Link> : null}</div>
        </div>
        <div className="grid gap-3 md:grid-cols-4">
          {([["ISS retido pelo tomador", issRetido, setIssRetido, regras.iss, clienteNfse?.iss_retido ?? null],
             ["PIS/COFINS/CSLL retidos (4,65%)", pcc, setPcc, regras.pcc, clienteNfse?.retem_pcc ?? null],
             ["IRRF retido (1,5%)", irrf, setIrrf, regras.irrf, clienteNfse?.retem_irrf ?? null],
             ["INSS retido (11%)", inss, setInss, regras.inss, clienteNfse?.retem_inss ?? null]] as Array<[string, string, (v: string) => void, string, boolean | null]>).map(([titulo, valor, setter, regra, valorCliente]) => (
            <label key={titulo} className={label}>{titulo}<select className={field} value={valor} disabled={!editavel || regra !== "POR_TOMADOR"} onChange={(e) => setter(e.target.value)}>
              <option value="">{regraTexto(regra, valorCliente)}</option><option value="sim">Sim, retém (nesta nota)</option><option value="nao">Não retém (nesta nota)</option></select></label>
          ))}
        </div>
        {perfil?.permite_deducao_material ? (
          <label className={label}>Material fornecido e incorporado à obra (R$), deduzido da base do ISS e do INSS (LC 116/2003, art. 7º, § 2º, I)
            <input className={field} inputMode="decimal" value={materialDeducao} disabled={!editavel} onChange={(e) => setMaterialDeducao(e.target.value)} placeholder="0,00" />
            {materialReal ? (
              <span className="flex flex-wrap items-center gap-2 text-xs text-zinc-300">
                Material real da obra {R$(num(materialReal.material_aplicado))} (produtos lançados na OS, fora os de venda) · já deduzido em NFS-e desta OS {R$(num(materialReal.material_deduzido))} · <strong>disponível {R$(num(materialReal.material_disponivel))}</strong>
                {editavel && num(materialReal.material_disponivel) > 0 && paraNumero(materialDeducao) !== num(materialReal.material_disponivel) ? <button type="button" className="rounded border border-zinc-700 px-2 py-0.5 hover:bg-zinc-900" onClick={() => setMaterialDeducao(decimal(num(materialReal.material_disponivel).toFixed(2)))}>Usar {R$(num(materialReal.material_disponivel))}</button> : null}
                {editavel && (paraNumero(materialDeducao) ?? 0) > num(materialReal.material_disponivel) + 0.005 ? <span className="text-amber-300">acima do material real: a conferência bloqueia</span> : null}
              </span>
            ) : null}
            <span className="text-xs text-zinc-500">Só material que está dentro do valor desta NFS-e e saiu do estoque por NF-e de simples remessa para obra (CFOP 5.949/6.949, sem ICMS/IPI). Material vendido por NF-e de venda não entra aqui. O contrato precisa prever o fornecimento. IRRF e CRF, quando houver, seguem sobre o valor integral.</span>
          </label>
        ) : null}
        {exigeObra ? (
          <div className="space-y-2 rounded-md border border-zinc-800 bg-zinc-900/30 p-3">
            <div className="text-sm">Local da obra <span className="text-xs text-zinc-400">— obrigatório no código {codigoTribNac} (grupo obra da DPS; sem ele o ambiente nacional recusa com E0370). Sugerido: endereço do tomador. Com CNO, o endereço não vai.</span></div>
            <div className="grid gap-3 md:grid-cols-6">
              <label className={label}>CNO da obra (opcional)<input className={field} value={obra.codigo_obra} disabled={!editavel} maxLength={30} onChange={(e) => setObra((o) => ({ ...o, codigo_obra: e.target.value }))} /></label>
              <label className={label}>CEP da obra<input className={field} inputMode="numeric" value={obra.cep} disabled={!editavel} onChange={(e) => setObra((o) => ({ ...o, cep: e.target.value.replace(/\D/g, "").slice(0, 8) }))} /></label>
              <label className={`${label} md:col-span-2`}>Logradouro da obra<input className={field} value={obra.logradouro} disabled={!editavel} maxLength={255} onChange={(e) => setObra((o) => ({ ...o, logradouro: e.target.value }))} /></label>
              <label className={label}>Número da obra<input className={field} value={obra.numero} disabled={!editavel} maxLength={60} onChange={(e) => setObra((o) => ({ ...o, numero: e.target.value }))} /></label>
              <label className={label}>Bairro da obra<input className={field} value={obra.bairro} disabled={!editavel} maxLength={60} onChange={(e) => setObra((o) => ({ ...o, bairro: e.target.value }))} /></label>
              <label className={`${label} md:col-span-3`}>Complemento da obra<input className={field} value={obra.complemento} disabled={!editavel} maxLength={156} onChange={(e) => setObra((o) => ({ ...o, complemento: e.target.value }))} /></label>
            </div>
          </div>
        ) : null}
        {perfil?.excecao_conserto_isolado || perfil?.item_servico === "14.01" ? (
          <label className="flex items-start gap-2 text-sm text-zinc-200">
            <input type="checkbox" className="mt-1" checked={consertoIsolado} disabled={!editavel} onChange={(e) => setConsertoIsolado(e.target.checked)} />
            <span>Conserto isolado (IN SRF 459/2004, art. 1º, §2º, II): manutenção em caráter isolado, mero conserto de bem defeituoso. Marca a OS e dispensa a CRF de 4,65% nesta nota. <span className="text-xs text-zinc-400">Sem a marca, a CRF do 14.01 entra por padrão.</span></span>
          </label>
        ) : null}
        {(deTri(issRetido) !== null && deTri(issRetido) !== (clienteNfse?.iss_retido ?? null)) || (deTri(pcc) !== null && deTri(pcc) !== (clienteNfse?.retem_pcc ?? null)) || (deTri(irrf) !== null && deTri(irrf) !== (clienteNfse?.retem_irrf ?? null)) || (deTri(inss) !== null && deTri(inss) !== (clienteNfse?.retem_inss ?? null)) ? (
          <label className={label}>Justificativa da retenção diferente do cadastro (obrigatória, vai para a observação da nota)<input className={field} value={justificativa} disabled={!editavel} onChange={(e) => setJustificativa(e.target.value)} maxLength={255} /></label>
        ) : null}
      </section>

      {/* 4 · Pagamento e informações complementares */}
      <section className="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <h2 className="font-semibold">Pagamento e informações complementares</h2>
        <div className="grid gap-3 md:grid-cols-4">
          <label className={label}>Pedido de compra do tomador<input className={field} value={pedidoCliente} disabled={!editavel} onChange={(e) => setPedidoCliente(e.target.value)} />{!pedidoCliente.trim() ? <span className="text-xs text-amber-300">Sem OC. Não bloqueia.</span> : null}</label>
          <label className={label}>Item do pedido<input className={field} value={pedidoItem} disabled={!editavel} onChange={(e) => setPedidoItem(e.target.value)} /></label>
          <label className={label}>Forma de pagamento<select className={field} value={pagamentoForma} disabled={!editavel} onChange={(e) => setPagamentoForma(e.target.value)}>{FORMAS_PAGAMENTO.map(([c, r]) => <option key={c} value={c}>{r}</option>)}</select></label>
          <label className={label}>À vista ou a prazo<select className={field} value={pagamentoIndicador} disabled={!editavel} onChange={(e) => setPagamentoIndicador(e.target.value)}><option value="0">0 · À vista</option><option value="1">1 · A prazo</option></select></label>
          {pagamentoForma === "99" ? <label className={label}>Descrição (obrigatória no 99)<input className={field} value={pagamentoDescricao} disabled={!editavel} onChange={(e) => setPagamentoDescricao(e.target.value)} maxLength={60} /></label> : null}
        </div>
        {pagamentoIndicador === "1" ? (
          <div className="space-y-2 rounded-md border border-zinc-800 bg-zinc-900/30 p-3">
            <div className="flex items-center justify-between"><div className="text-sm">Parcelas sobre o líquido · dias após a emissão</div>{editavel ? <button type="button" className={botao} onClick={() => setParcelas((p) => [...p, { dias: "", valor: "" }])}>Adicionar parcela</button> : null}</div>
            {parcelas.map((p, i) => <div key={i} className="grid gap-2 md:grid-cols-[auto_1fr_1fr_auto] md:items-end"><div className="text-xs text-zinc-500 md:pb-2">{String(i + 1).padStart(3, "0")}</div><label className={label}>Dias<input className={field} inputMode="numeric" value={p.dias} disabled={!editavel} onChange={(e) => setParcelas((a) => a.map((x, j) => j === i ? { ...x, dias: e.target.value } : x))} /></label><label className={label}>Valor (R$)<input className={field} inputMode="decimal" value={p.valor} disabled={!editavel} onChange={(e) => setParcelas((a) => a.map((x, j) => j === i ? { ...x, valor: e.target.value } : x))} placeholder={parcelas.length === 1 ? "vazio = líquido" : "obrigatório"} /></label><button type="button" className={botao} disabled={parcelas.length === 1 || !editavel} onClick={() => setParcelas((a) => a.filter((_, j) => j !== i))}>Remover</button></div>)}
          </div>
        ) : null}
        <label className={label}>Observação livre (entra no fim da discriminação)<textarea className={`${field} min-h-16`} value={observacao} disabled={!editavel} onChange={(e) => setObservacao(e.target.value)} maxLength={400} /></label>
      </section>

      {/* 5 · Prévia e emissão */}
      <section className="space-y-3 rounded-xl border border-sky-900/60 bg-sky-950/10 p-4">
        <h2 className="font-semibold">Prévia e emissão</h2>
        {bloqueios.length > 0 ? <div className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm"><div className="font-medium text-red-200">Bloqueios</div><ul className="mt-1 list-disc pl-5 text-red-100">{bloqueios.map((b, i) => <li key={i}>{b.entidade ? `${b.entidade} · ` : ""}{b.campo ? `${b.campo}: ` : ""}{b.mensagem}{b.rota ? <> · <Link className="underline" href={b.rota}>corrigir</Link></> : null}</li>)}</ul></div> : null}
        {avisos.length > 0 ? <div className="rounded-md border border-amber-900/60 bg-amber-950/20 p-3 text-sm text-amber-100"><div className="font-medium">Avisos</div><ul className="mt-1 list-disc pl-5">{avisos.map((a, i) => <li key={i}>{a.mensagem}{a.rota ? <> · <Link className="underline" href={a.rota}>abrir</Link></> : null}</li>)}</ul></div> : null}
        {previa ? (
          <div className="space-y-2 text-sm">
            <div className="grid gap-2 md:grid-cols-4">
              <div>Bruto <strong>{R$(num(previa.valor_bruto))}</strong></div>
              <div>ISS {decimal(previa.aliquota_iss)}% {R$(num(previa.valor_iss))} <span className="text-xs text-zinc-400">({previa.iss_retido ? "retido pelo tomador" : "recolhido pela Segau"})</span></div>
              <div>INSS {R$(num(previa.valor_inss))} · IRRF {R$(num(previa.valor_irrf))} · PCC {R$(num(previa.valor_pcc))}</div>
              <div>Líquido a receber <strong>{R$(num(previa.valor_liquido))}</strong></div>
            </div>
            {previa.parcelas && previa.parcelas.length > 0 ? <div className="text-xs text-zinc-400">Parcelas do líquido: {previa.parcelas.map((p) => `${p.numero} · ${p.dias} dias · ${p.valor != null ? R$(num(p.valor)) : R$(num(previa.valor_liquido))}`).join(" | ")}</div> : <div className="text-xs text-zinc-400">Pagamento à vista.</div>}
            <div className="text-xs text-zinc-400">cTribNac {previa.codigo_tributacao_nacional}{previa.codigo_nbs ? ` · NBS ${previa.codigo_nbs}` : ""} · prestação em {previa.municipio_prestacao_ibge}{previa.municipio_incidencia_iss ? ` · ISS incide em ${previa.municipio_incidencia_iss}` : ""} · competência {previa.data_competencia}</div>
            {previa.obra ? <div className="text-xs text-zinc-400">Obra: {previa.obra.codigo_obra ? `CNO ${previa.obra.codigo_obra}` : `${previa.obra.logradouro ?? ""}, ${previa.obra.numero ?? ""}${previa.obra.complemento ? ` · ${previa.obra.complemento}` : ""} · ${previa.obra.bairro ?? ""} · CEP ${previa.obra.cep ?? ""}`}</div> : null}
            {num(previa.valor_deducoes) > 0 ? <div className="text-xs text-zinc-400">Material deduzido {R$(num(previa.valor_deducoes))} · base do ISS e do INSS {R$(num(previa.base_iss))} (LC 116/2003, art. 7º, § 2º, I)</div> : null}
            {previa.ibs_cbs ? <div className="text-xs text-zinc-400">IBS/CBS (base = serviço − ISS {R$(num(previa.ibs_cbs.base))}): IBS UF {R$(num(previa.ibs_cbs.ibs_uf))} · IBS mun {R$(num(previa.ibs_cbs.ibs_mun))} · CBS {R$(num(previa.ibs_cbs.cbs))} · total {R$(num(previa.ibs_cbs.total))} (informativo em 2026; calculado pelo ambiente nacional)</div> : null}
            {previa.tributos_aprox ? <div className="text-xs text-zinc-400">Tributos aproximados (Lei 12.741, tabela por subitem): federal {decimal(previa.tributos_aprox.federal_pct) || "?"}% {R$(num(previa.tributos_aprox.federal))} · municipal {decimal(previa.tributos_aprox.municipal_pct) || "?"}% {R$(num(previa.tributos_aprox.municipal))}</div> : null}
            <label className={label}>Discriminação (montada pelo ERP; não editável)<textarea className={`${field} min-h-24`} readOnly value={previa.descricao_servico} /></label>
            {previa.tributacao_fonte === "PERFIL"
              ? <div className="text-xs text-emerald-300">Valores do perfil de serviço revisado{previa.campos_conferir && previa.campos_conferir.length > 0 ? ` · campos travados: ${previa.campos_conferir.map((c) => c.campo).join(", ")} (produção bloqueada até a confirmação)` : ""}.</div>
              : <div className="text-xs text-amber-300">Valores da fixture provisória de homologação; este perfil ainda não foi revisado.</div>}
          </div>
        ) : <div className="text-sm text-zinc-400">Salve a conferência para ver bruto, retenções, líquido e a discriminação.</div>}
        <div className="flex flex-wrap items-center gap-2">
          {editavel ? <button type="button" className={botao} disabled={ocupado || Boolean(motivoBloqueioOs) || Boolean(bloqueioLocal)} onClick={() => void conferir()}>{solicitacao ? "Reconferir" : "Salvar rascunho e conferir"}</button> : null}
          {solicitacao && conferida && editavel ? <button type="button" className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40" disabled={ocupado || bloqueios.length > 0 || Boolean(motivoBloqueioOs) || Boolean(bloqueioLocal)} onClick={() => void emitir()}>{emissao ? "Tentar emitir novamente (nova DPS)" : "Emitir NFS-e em homologação"}</button> : null}
          {solicitacao && (editavel || (autorizada && !producao)) ? <button type="button" className={botao} disabled={ocupado} onClick={() => void descartar()}>{autorizada ? "Abandonar homologação e liberar saldo" : "Descartar rascunho"}</button> : null}
        </div>
        {bloqueioLocal ? <div className="text-xs text-amber-300">{bloqueioLocal}</div> : null}
        {emissao ? (
          <div className="rounded-md border border-zinc-800 p-3 text-sm">
            <div>Status: <strong>{emProcessamento ? "Em processamento" : autorizada ? (producao ? "AUTORIZADA · NFS-e REAL" : "Autorizada em homologação") : emissao.status}</strong> · {producao ? "PRODUÇÃO" : "homologação"} · DPS {emissao.dps_serie}/{emissao.dps_numero}{emissao.mensagem ? <span className="text-zinc-400"> · {emissao.codigo_status ? `${emissao.codigo_status} · ` : ""}{emissao.mensagem}</span> : null}</div>
            {emProcessamento ? <div className="text-xs text-zinc-400">Saldo reservado. A tela atualiza sozinha quando o ambiente nacional responder.</div> : null}
            {["REJEITADA", "ERRO"].includes(emissao.status) ? <div className="text-xs text-amber-300">DPS {emissao.dps_serie}/{emissao.dps_numero} queimada; o saldo já voltou. &ldquo;Tentar emitir novamente&rdquo; leva um número novo de DPS.</div> : null}
            {autorizada ? (
              <div className="mt-2 space-y-2">
                <div className="flex flex-wrap items-center gap-2"><span>NFS-e nº <strong>{emissao.nfse_numero}</strong> · código de verificação {emissao.codigo_verificacao ?? "—"}</span><code className="text-xs">{emissao.chave_nfse}</code></div>
                <div className="flex flex-wrap items-center gap-2">
                  <button type="button" className={botao} disabled={!emissao.danfe_path} onClick={() => void abrirArquivo(emissao.documento_fiscal_id, "DANFE")}>DANFSe</button>
                  <button type="button" className={botao} disabled={!emissao.xml_path} onClick={() => void abrirArquivo(emissao.documento_fiscal_id, "XML")}>XML</button>
                  <Link className={botao} href={`/faturamento/nfse/${emissao.documento_fiscal_id}`}>Detalhe</Link>
                  <button type="button" className={botao} disabled={ocupado} onClick={() => void substituir()}>Substituir</button>
                  {producao ? <button type="button" className={botao} disabled={ocupado} onClick={() => void enviarEmail()}>Enviar por e-mail</button> : null}
                  {!producao && saldo > 0.005 ? <button type="button" className={botao} disabled={ocupado} onClick={() => { setNovaNota(true); setSolicitacao(null); setEmissao(null); setPrevia(null); setLinhas([]); setBloqueios([]); setAvisos([]); setMaterialDeducao(""); setMaterialSugerido(false); }}>Nova NFS-e parcial (saldo {R$(saldo)})</button> : null}
                  {!producao && producaoPronta?.pronta ? <button type="button" className="rounded-md bg-emerald-700 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-40" disabled={ocupado} onClick={() => void emitirProducao()}>Emitir NFS-e real (produção)</button> : null}
                </div>
                {!producao && producaoPronta && !producaoPronta.pronta ? (
                  <div className="flex flex-wrap items-center gap-2 text-xs text-zinc-500">
                    <span>Produção: {producaoPronta.motivo}</span>
                    {/* A liberacao e por solicitacao: o link leva o perfil e esta homologacao, como na NF-e. */}
                    {perfil && solicitacao ? <Link href={`/faturamento/perfis?perfil=${encodeURIComponent(perfil.codigo)}&solicitacao=${encodeURIComponent(solicitacao.id)}&retorno=${encodeURIComponent(`/os/${osId}/faturar`)}`} className="rounded-md border border-emerald-800 px-2 py-1 text-emerald-100 hover:bg-emerald-950/60">Liberar {perfil.codigo} para esta nota</Link> : null}
                  </div>
                ) : null}
                {podeCancelar ? (
                  <div className="flex flex-wrap items-end gap-2">
                    <label className={`${label} flex-1`}>Justificativa do cancelamento (15 a 255)<input className={field} value={justificativaCancel} onChange={(e) => setJustificativaCancel(e.target.value)} maxLength={255} /></label>
                    <button type="button" className={botao} disabled={ocupado} onClick={() => void cancelar()}>{producao ? "Cancelar NFS-e real na SEFAZ" : "Cancelar NFS-e (homologação)"}</button>
                    {textoPrazo === null ? <span className="w-full text-xs text-amber-300">Prazo de cancelamento não confirmado pelo contador: em produção este botão fica oculto e só a substituição aparece.</span> : <span className="w-full text-xs text-zinc-500">{textoPrazo}</span>}
                  </div>
                ) : null}
                {producao ? <div className="text-xs text-emerald-300">NFS-e real: documento EMITIDA, título a receber líquido com as retenções por tributo e saldo da OS faturado.</div> : <div className="text-xs text-zinc-400">Homologação não gera título a receber nem consome o saldo definitivo; o saldo fica reservado até o abandono. A nota real gera o contas a receber líquido com as retenções por tributo.</div>}
              </div>
            ) : null}
          </div>
        ) : null}
        {solicitacao?.substitui_documento_fiscal_id ? <div className="text-xs text-amber-300">Esta nota substitui outra NFS-e (código {solicitacao.substituicao_codigo}: {solicitacao.substituicao_motivo}). A antiga passa a SUBSTITUÍDA quando esta for autorizada.</div> : null}
      </section>
    </>
  );
}
