// Carregamento das linhas do relatorio HH de uma OS.
//
// Extraido de app/os/[id]/components/RelatorioHHSection.tsx para que a tela e a
// rota que serve o aplicativo leiam exatamente as mesmas linhas. Se cada lado
// montasse a sua consulta, o PDF do celular poderia divergir do PDF do
// navegador sem ninguem perceber.
//
// O recorte por empresa e so por RLS (current_empresa_id), como manda
// lib/db/scopes.ts — por isso o chamador precisa ter o contexto de empresa
// ativo na conexao antes de chamar aqui.

import type { SupabaseClient } from "@supabase/supabase-js";

import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import {
  formatDateBR,
  getPercentualFromDate,
  getTipoHHLabel,
  type HhLancamentoViewRow,
} from "./relatorioHhCalculos";

const COLUNAS_HH =
  "id,os_id,data,colaborador_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,horas_trabalhadas,percentual_aplicado,tem_extra_50,horas_extra_50,tem_extra_100,horas_extra_100,observacao,criado_em,hh_tipo_id,valor_hora,valor_total,hh_especialidade_id,hh_servico_id";

type LinhaBruta = {
  id: number | string;
  os_id: number;
  data: string;
  colaborador_id?: string;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  hora_entrada?: string | null;
  hora_saida?: string | null;
  horas_trabalhadas?: number | null;
  percentual_aplicado?: number | null;
  tem_extra_50?: boolean | null;
  horas_extra_50?: number | null;
  tem_extra_100?: boolean | null;
  horas_extra_100?: number | null;
  observacao?: string | null;
  criado_em?: string | null;
  hh_tipo_id?: number | string | null;
  valor_hora?: number | null;
  valor_total?: number | null;
  hh_especialidade_id?: string | null;
  hh_servico_id?: string | null;
};

export type OsMetaRelatorioHh = {
  numero_os: string;
  cliente_nome: string | null;
  descricao_servico: string | null;
};

export async function carregarLinhasRelatorioHh(
  supabase: SupabaseClient,
  osId: number,
  tenantId: string,
  empresaId: string
): Promise<HhLancamentoViewRow[]> {
  const resultado = await applyTenantEmpresa(
    supabase.from("hh_lancamentos").select(COLUNAS_HH).eq("os_id", osId).order("criado_em", { ascending: false }),
    tenantId,
    empresaId
  );

  if (resultado.error) throw resultado.error;

  const linhas = (resultado.data ?? []) as LinhaBruta[];
  if (linhas.length === 0) return [];

  const colaboradorIds = Array.from(new Set(linhas.map((r) => String(r.colaborador_id)).filter(Boolean)));

  const colaboradorMap = new Map<string, string>();
  if (colaboradorIds.length > 0) {
    const { data, error } = await applyTenantEmpresa(
      supabase.from("colaboradores").select("id,nome").in("id", colaboradorIds),
      tenantId,
      empresaId
    );
    // Nome faltando vira "—" na tela; nao vale derrubar o relatorio inteiro.
    if (!error && data) {
      (data as Array<{ id: string; nome: string }>).forEach((c) => colaboradorMap.set(String(c.id), c.nome));
    }
  }

  const servicoIds = Array.from(
    new Set(
      linhas
        .map((r) => String(r.hh_servico_id ?? r.hh_especialidade_id ?? "").trim())
        .filter((id) => /^\d+$/.test(id))
    )
  );

  const servicoMap = new Map<string, string>();
  if (servicoIds.length > 0) {
    const { data, error } = await applyTenantEmpresa(
      supabase.from("cliente_hh_servicos").select("id,nome").in("id", servicoIds),
      tenantId,
      empresaId
    );
    if (!error && data) {
      (data as Array<{ id: string; nome: string }>).forEach((s) => servicoMap.set(String(s.id), s.nome));
    }
  }

  return linhas.map((r) => {
    const percentual = Number(r.percentual_aplicado ?? getPercentualFromDate(r.data));
    const preferServicoId = String(r.hh_servico_id ?? "").trim();
    const preferEspecialidadeId = String(r.hh_especialidade_id ?? "").trim();
    const servicoId = /^\d+$/.test(preferServicoId)
      ? preferServicoId
      : /^\d+$/.test(preferEspecialidadeId)
        ? preferEspecialidadeId
        : "";
    return {
      ...r,
      entrada_1: r.entrada_1 ?? null,
      saida_1: r.saida_1 ?? null,
      entrada_2: r.entrada_2 ?? null,
      saida_2: r.saida_2 ?? null,
      hora_entrada: r.hora_entrada ?? null,
      hora_saida: r.hora_saida ?? null,
      horas_trabalhadas: r.horas_trabalhadas ?? null,
      tem_extra_50: r.tem_extra_50 ?? null,
      horas_extra_50: r.horas_extra_50 ?? null,
      tem_extra_100: r.tem_extra_100 ?? null,
      horas_extra_100: r.horas_extra_100 ?? null,
      valor_hora: r.valor_hora ?? null,
      valor_total: r.valor_total ?? null,
      observacao: r.observacao ?? null,
      criado_em: r.criado_em ?? null,
      colaborador_nome: colaboradorMap.get(String(r.colaborador_id)) ?? "—",
      hh_tipo_descricao: getTipoHHLabel(percentual),
      especialidade_descricao: servicoId ? servicoMap.get(servicoId) ?? "—" : "—",
      hh_servico_id: servicoId,
    };
  });
}

export async function carregarOsMetaRelatorioHh(
  supabase: SupabaseClient,
  osId: number,
  tenantId: string
): Promise<OsMetaRelatorioHh> {
  const { data, error } = await applyTenant(
    supabase
      .from("ordens_servico")
      .select("numero_os, cliente_nome, descricao_servico")
      .eq("tipo_documento", "OS")
      .eq("id", osId)
      .maybeSingle(),
    tenantId
  );

  if (error) throw error;

  return {
    numero_os: data?.numero_os ? String(data.numero_os) : String(osId),
    cliente_nome: data?.cliente_nome ?? null,
    descricao_servico: data?.descricao_servico ?? null,
  };
}

/** Periodo do cabecalho: da menor a maior data lancada. */
export function periodoDoRelatorio(linhas: HhLancamentoViewRow[]): string {
  const datas = linhas
    .map((r) => String(r.data ?? "").trim())
    .filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d));
  if (!datas.length) return "—";
  const minima = datas.reduce((a, b) => (a < b ? a : b));
  const maxima = datas.reduce((a, b) => (a > b ? a : b));
  return `${formatDateBR(minima)} a ${formatDateBR(maxima)}`;
}
