// Dados e formatacao do PDF do orcamento.
//
// Extraido de app/comercial/orcamentos/[id]/imprimir/page.tsx para a tela e a
// rota que serve o aplicativo lerem exatamente as mesmas linhas. Se cada lado
// montasse a sua consulta, o PDF do celular poderia divergir do da tela sem
// ninguem perceber.

import type { SupabaseClient } from "@supabase/supabase-js";

import { applyTenantEmpresa } from "@/lib/db/scopes";
import { getOrcamento } from "@/lib/comercial/orcamentos.service";
import type { OrcamentoItemRow, OrcamentoRow } from "@/lib/comercial/types";
import { upperTrim } from "@/lib/comercial/utils";

export type EmpresaRow = {
  id: string;
  tenant_id: string;
  cnpj: string;
  razao_social: string;
  nome_fantasia: string | null;
  ie: string | null;
  uf: string | null;
  cidade: string | null;
  endereco: string | null;
};

export type ClienteRow = {
  id: number;
  nome: string;
  razao_social: string | null;
  documento: string | null;
  email: string | null;
  telefone: string | null;
  logradouro: string | null;
  numero_endereco: string | null;
  complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  uf: string | null;
  cep: string | null;
};

export type UsuarioRow = { id: string; nome: string | null; email: string | null };

export type ItemMetaRow = {
  id: number;
  codigo_interno: string | null;
  fabricante: string | null;
  ncm: string | null;
  unidade_medida: string | null;
};

type FiscalItemNcmRow = { item_id: number; ncm: string | null };
type EstoqueRow = { item_id: number; quantidade_atual: number | null };

export type ClienteContatoPrintInfo = {
  nome: string;
  setor: string;
  email: string;
  telefone: string;
};

/** Tudo que o gerador do PDF precisa, ja resolvido. */
export type DadosOrcamentoPdf = {
  orcamento: OrcamentoRow;
  itens: OrcamentoItemRow[];
  empresa: EmpresaRow | null;
  cliente: ClienteRow | null;
  vendedor: UsuarioRow | null;
  condicaoNome: string | null;
  itemMetaById: Record<number, ItemMetaRow>;
  estoqueByItemId: Record<number, number>;
};

export function formatDateBR(iso?: string | null) {
  if (!iso) return "-";
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

export function addDays(dateLike: string | null | undefined, days: number): Date | null {
  const base = dateLike ? new Date(dateLike) : null;
  if (!base || Number.isNaN(base.getTime())) return null;
  const out = new Date(base);
  out.setDate(out.getDate() + days);
  return out;
}

export function joinNonEmpty(parts: Array<string | null | undefined>, sep: string) {
  return parts
    .map((p) => String(p ?? "").trim())
    .filter(Boolean)
    .join(sep);
}

export function formatEnderecoCliente(cli: ClienteRow | null) {
  if (!cli) return "-";
  const linha1 = joinNonEmpty(
    [
      cli.logradouro,
      cli.numero_endereco ? `, ${cli.numero_endereco}` : null,
      cli.complemento ? ` - ${cli.complemento}` : null,
    ],
    ""
  ).trim();
  const linha2 = joinNonEmpty([cli.bairro, cli.cidade, cli.uf], " - ");
  const cep = cli.cep ? `CEP: ${cli.cep}` : "";
  return joinNonEmpty([linha1 || null, linha2 || null, cep || null], " | ") || "-";
}

function lowerTrim(value: string | null | undefined) {
  return String(value ?? "").trim().toLocaleLowerCase("pt-BR");
}

export function getClienteContatoPrintInfo(orc: OrcamentoRow | null, cli: ClienteRow | null): ClienteContatoPrintInfo {
  return {
    nome: upperTrim(String(orc?.solicitante_nome ?? "")) || "-",
    setor: upperTrim(String(orc?.solicitante_setor ?? "")) || "-",
    email: lowerTrim(orc?.solicitante_email) || lowerTrim(cli?.email) || "-",
    telefone: String(orc?.solicitante_telefone ?? "").trim() || String(cli?.telefone ?? "").trim() || "-",
  };
}

/** Validade impressa no cabecalho: 30 dias a partir da ultima alteracao. */
export function validadeDoOrcamento(orc: OrcamentoRow | null): string {
  const ate = addDays(orc?.updated_at, 30);
  if (!ate) return "30 DIAS.";
  return `ATE ${ate.toLocaleDateString("pt-BR")}.`;
}

export const GARANTIA_PADRAO = "1 ANO CONTRA DEFEITOS DE FABRICACAO.";

/** Nome do arquivo — o mesmo que a tela ja baixava. */
export function nomeArquivoOrcamentoPdf(orc: OrcamentoRow, idParam: string): string {
  const base = (upperTrim(orc.codigo) || `orcamento-${idParam}` || "orcamento")
    .replace(/[\\/:*?"<>|]+/g, "-")
    .replace(/\s+/g, " ")
    .trim();
  return `${base || "orcamento"}.pdf`;
}

export async function carregarDadosOrcamentoPdf(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; idOrCodigo: string }
): Promise<DadosOrcamentoPdf> {
  const { tenantId, empresaId, idOrCodigo } = params;

  const { orcamento } = await getOrcamento(supabase, { tenantId, empresaId, idOrCodigo });

  const { data: itensRows, error: itensErr } = await applyTenantEmpresa(
    supabase.schema("r").from("r_orcamento_itens").select("*").eq("orcamento_id", orcamento.id).order("seq", { ascending: true }),
    tenantId,
    empresaId
  ).returns<OrcamentoItemRow[]>();
  if (itensErr) throw itensErr;
  const itens = (itensRows ?? []) as OrcamentoItemRow[];

  const { data: emp, error: empErr } = await supabase
    .from("empresas")
    .select("id,tenant_id,cnpj,razao_social,nome_fantasia,ie,uf,cidade,endereco")
    .eq("tenant_id", tenantId)
    .eq("id", empresaId)
    .maybeSingle<EmpresaRow>();
  if (empErr) throw empErr;
  const empresa = emp?.id ? (emp as EmpresaRow) : null;

  let cliente: ClienteRow | null = null;
  const clienteId = Number(orcamento.cliente_id ?? 0);
  if (Number.isFinite(clienteId) && clienteId > 0) {
    const { data: cli, error: cliErr } = await applyTenantEmpresa(
      supabase
        .from("clientes")
        .select("id,nome,razao_social,documento,email,telefone,logradouro,numero_endereco,complemento,bairro,cidade,uf,cep")
        .eq("id", clienteId)
        .maybeSingle<ClienteRow>(),
      tenantId,
      empresaId
    );
    if (cliErr) throw cliErr;
    cliente = cli?.id ? (cli as ClienteRow) : null;
  }

  let vendedor: UsuarioRow | null = null;
  const vendedorId = String(orcamento.vendedor_usuario_id ?? "").trim();
  if (vendedorId) {
    const { data: vend, error: vendErr } = await supabase
      .schema("a")
      .from("usuario")
      .select("id,nome,email")
      .eq("id", vendedorId)
      .is("deleted_at", null)
      .maybeSingle<UsuarioRow>();
    // Vendedor sem cadastro nao impede a proposta; o campo cai para o id.
    if (!vendErr) vendedor = vend?.id ? (vend as UsuarioRow) : null;
  }

  let condicaoNome: string | null = null;
  const condId = String(orcamento.condicao_pagamento_id ?? "").trim();
  if (condId) {
    const { data: cp, error: cpErr } = await applyTenantEmpresa(
      supabase.schema("c").from("condicao_pagamento").select("id,nome").eq("id", condId).maybeSingle<{ id: string; nome: string | null }>(),
      tenantId,
      empresaId
    );
    condicaoNome = !cpErr ? cp?.nome ?? condId : condId;
  }

  // Enriquecimento dos itens: dados comerciais em itens e NCM oficial em
  // fiscal_itens. itens.ncm permanece somente como fallback durante a transicao.
  let itemMetaById: Record<number, ItemMetaRow> = {};
  let estoqueByItemId: Record<number, number> = {};

  try {
    const itemIds = Array.from(
      new Set(itens.map((it) => Number(it.item_id)).filter((v) => Number.isFinite(v) && v > 0))
    );

    if (itemIds.length > 0) {
      const { data: metas, error: metasErr } = await applyTenantEmpresa(
        supabase.from("itens").select("id,codigo_interno,fabricante,ncm,unidade_medida").in("id", itemIds),
        tenantId,
        empresaId
      ).returns<ItemMetaRow[]>();

      if (!metasErr && metas) {
        const map: Record<number, ItemMetaRow> = {};
        for (const r of metas) {
          const id = Number(r.id);
          if (Number.isFinite(id) && id > 0) map[id] = r;
        }

        const { data: fiscais, error: fiscaisErr } = await applyTenantEmpresa(
          supabase.from("fiscal_itens").select("item_id,ncm").in("item_id", itemIds),
          tenantId,
          empresaId
        ).returns<FiscalItemNcmRow[]>();

        if (!fiscaisErr) {
          for (const fiscal of fiscais ?? []) {
            const itemId = Number(fiscal.item_id);
            const atual = map[itemId];
            if (atual && fiscal.ncm) map[itemId] = { ...atual, ncm: fiscal.ncm };
          }
        }

        itemMetaById = map;
      }

      const { data: estoqueRows, error: estoqueErr } = await applyTenantEmpresa(
        supabase.from("estoque").select("item_id,quantidade_atual").in("item_id", itemIds),
        tenantId,
        empresaId
      ).returns<EstoqueRow[]>();

      if (!estoqueErr && estoqueRows) {
        const estoqueMap: Record<number, number> = {};
        for (const row of estoqueRows) {
          const itemId = Number(row.item_id);
          const qtd = Number(row.quantidade_atual ?? 0);
          if (Number.isFinite(itemId) && itemId > 0) estoqueMap[itemId] = Number.isFinite(qtd) ? qtd : 0;
        }
        estoqueByItemId = estoqueMap;
      }
    }
  } catch {
    // best-effort: sem estoque o prazo da linha vira "A CONFIRMAR"
    estoqueByItemId = {};
  }

  return { orcamento, itens, empresa, cliente, vendedor, condicaoNome, itemMetaById, estoqueByItemId };
}
