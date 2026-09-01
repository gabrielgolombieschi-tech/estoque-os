"use client";
import type { SupabaseClient } from "@supabase/supabase-js";

// Helper para resolver o mapping correto de hh_tipo_id
async function resolveHhTipoMappingId(
  supabase: SupabaseClient,
  tenantId: string,
  percentual: 0 | 50 | 100
): Promise<number> {
  const codigoTipo = percentual === 0 ? "NORMAL" : percentual === 50 ? "EXTRA_50" : "EXTRA_100";
  
  // 1. Buscar tipos_horas.id (UUID)
  const { data: tipoHoras, error: tipoHorasErr } = await applyTenant(
    supabase.from("tipos_horas").select("id").eq("codigo", codigoTipo).eq("ativo", true).maybeSingle(),
    tenantId
  );
  if (tipoHorasErr || !tipoHoras?.id) {
    throw new Error(`Não foi possível resolver tipos_horas para ${codigoTipo}`);
  }
  const tipoHorasId = tipoHoras.id; // UUID
  
  // 2. Buscar mapping em hh_tipos_mapping (tipo_hora_id → hh_tipo_id)
  const { data: mapping, error: mappingErr } = await supabase
    .from("hh_tipos_mapping")
    .select("hh_tipo_id")
    .eq("tipo_hora_id", tipoHorasId)
    .eq("tenant_id", tenantId)
    .eq("ativo", true)
    .maybeSingle();
  
  if (mappingErr) {
    console.error("[resolveHhTipoMappingId] Erro ao buscar mapping:", mappingErr);
    const msg =
      typeof mappingErr === "object" && mappingErr && "message" in mappingErr
        ? String((mappingErr as { message?: unknown }).message ?? "")
        : String(mappingErr);
    throw new Error(`Erro ao buscar mapping: ${msg}`);
  }
  
  if (mapping && mapping.hh_tipo_id) {
    return Number(mapping.hh_tipo_id);
  }
  
  // Se não encontrou mapping, retornar erro (não criar automático)
  throw new Error(`Mapping não encontrado para tipo ${codigoTipo} (percentual ${percentual}%). Configure em hh_tipos_mapping.`);
}

import { useEffect, useMemo, useRef, useState } from "react";
import NextImage from "next/image";
import type { CellHookData, RowInput } from "jspdf-autotable";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { syncHhToApontamentos } from "@/lib/hh/syncHhToApontamentos";

function getDbErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error && err.message) return err.message;
  if (typeof err === "string" && err.trim()) return err.trim();
  if (err && typeof err === "object") {
    const obj = err as Record<string, unknown>;
    const message = typeof obj.message === "string" ? obj.message : null;
    const details = typeof obj.details === "string" ? obj.details : null;
    const hint = typeof obj.hint === "string" ? obj.hint : null;
    const parts = [message, details, hint].filter((v): v is string => Boolean(v && v.trim()));
    if (parts.length > 0) return parts.join(" — ");
  }
  return fallback;
}


type EspecialidadeOption = { id: string; descricao: string | null };
type TabelaAtiva = {
  id: number;
  cliente_id: number;
  nome?: string | null;
  vigencia_inicio?: string | null;
  vigencia_fim?: string | null;
  ativo?: boolean | null;
};

type HhLancamentoViewRow = {
  id: string | number;
  os_id: number;
  data: string;
  colaborador_nome: string | null;
  especialidade_descricao: string | null;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  hora_entrada: string | null;
  hora_saida: string | null;
  horas_trabalhadas: number | null;
  hh_tipo_descricao?: string | null;
  hh_tipo_id?: string | number | null;
  hh_servico_id?: string | number | null;
  percentual_aplicado?: number | null;
  tem_extra_50?: boolean | null;
  horas_extra_50?: number | null;
  tem_extra_100?: boolean | null;
  horas_extra_100?: number | null;
  valor_hora: number | null;
  valor_total: number | null;
  observacao: string | null;
  criado_em: string | null;
};

type HhLancamentoSyncRow = {
  data: string;
  colaborador_id?: string | null;
  entrada_1?: string | null;
  saida_1?: string | null;
  entrada_2?: string | null;
  saida_2?: string | null;
  hora_entrada?: string | null;
  hora_saida?: string | null;
  percentual_aplicado?: number | null;
  tem_extra_50?: boolean | null;
  horas_extra_50?: number | null;
  tem_extra_100?: boolean | null;
  horas_extra_100?: number | null;
  observacao?: string | null;
};

type Colaborador = {
  id: string;
  nome: string;
  ativo: boolean;
};

function formatHoursBR(value: number | null | undefined) {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0,00";
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatHorasInputBR(value: number | null | undefined): string {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n) || n <= 0) return "";
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function parseHorasInputBR(value: string): number | null {
  const raw = String(value ?? "").trim();
  if (!raw) return 0;

  const hhmm = /^(\d{1,2}):([0-5]\d)$/.exec(raw);
  if (hhmm) {
    const horas = Number(hhmm[1]);
    const minutos = Number(hhmm[2]);
    if (!Number.isFinite(horas) || !Number.isFinite(minutos)) return null;
    return Number((horas + minutos / 60).toFixed(2));
  }

  const normalized = raw.replace(",", ".");
  if (!/^\d{1,2}(\.\d{1,2})?$/.test(normalized)) return null;
  const n = Number(normalized);
  if (!Number.isFinite(n)) return null;
  return Number(n.toFixed(2));
}

function formatTimeHHMM(value: string | null | undefined): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  // Pode vir "HH:MM" ou "HH:MM:SS".
  if (/^\d{2}:\d{2}/.test(raw)) return raw.slice(0, 5);
  return raw;
}

function formatDateBR(isoDate: string | null | undefined) {
  if (!isoDate) return "--";
  const d = new Date(isoDate + "T00:00:00");
  return d.toLocaleDateString("pt-BR");
}

function formatDateDDMMAA(isoDate: string | null | undefined): string {
  const raw = String(isoDate ?? "").trim();
  if (!raw) return "--";

  // Prefer ISO yyyy-mm-dd (avoid timezone issues)
  const m = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) {
    const yy = m[1].slice(-2);
    return `${m[3]}/${m[2]}/${yy}`;
  }

  const d = new Date(raw);
  if (!Number.isFinite(d.getTime())) return "--";
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yy = String(d.getFullYear()).slice(-2);
  return `${dd}/${mm}/${yy}`;
}

function getPercentualFromDate(dateISO: string): 0 | 50 | 100 {
  const raw = String(dateISO ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return 0;
  const d = new Date(raw + "T00:00:00");
  const dow = d.getDay();
  if (dow === 0) return 100;
  if (dow === 6) return 50;
  return 0;
}

function normalizePercentualHh(value: unknown, dateISO: string): 0 | 50 | 100 {
  const percentual = Number(value);
  if (percentual === 50 || percentual === 100) return percentual;
  if (percentual === 0) return 0;
  return getPercentualFromDate(dateISO);
}

function buildPeriodosSyncFromHhRows(rows: HhLancamentoSyncRow[]): Array<{ entrada: string; saida: string }> {
  const periodos: Array<{ entrada: string; saida: string }> = [];

  for (const row of rows) {
    const entrada1 = formatTimeHHMM(row.entrada_1) || formatTimeHHMM(row.hora_entrada);
    const saida1 = formatTimeHHMM(row.saida_1) || formatTimeHHMM(row.hora_saida);
    const entrada2 = formatTimeHHMM(row.entrada_2);
    const saida2 = formatTimeHHMM(row.saida_2);

    if (entrada1 && saida1) {
      periodos.push({ entrada: entrada1, saida: saida1 });
    }
    if (entrada2 && saida2) {
      periodos.push({ entrada: entrada2, saida: saida2 });
    }
  }

  return periodos;
}

function calcHorasFromSyncRow(row: HhLancamentoSyncRow): number {
  const periodos = buildPeriodosSyncFromHhRows([row]);
  let total = 0;
  for (const periodo of periodos) {
    const entrada = parseHHMM(periodo.entrada);
    const saida = parseHHMM(periodo.saida);
    if (entrada === null || saida === null || saida <= entrada) continue;
    total += calcHorasDecimalFromMinutes(entrada, saida);
  }
  return normalizeHorasNumber(total);
}

function getSyncHorasSplit(rows: HhLancamentoSyncRow[]) {
  return rows.reduce(
    (acc, row) => {
      const horas = calcHorasFromSyncRow(row);
      const extra50Manual = Boolean(row.tem_extra_50) || Number(row.horas_extra_50 ?? 0) > 0;
      const extra100Manual = Boolean(row.tem_extra_100) || Number(row.horas_extra_100 ?? 0) > 0;
      const percentual = Number(row.percentual_aplicado ?? 0);

      if (extra50Manual || extra100Manual) {
        const extra50 = normalizeHorasNumber(Number(row.horas_extra_50 ?? 0));
        const extra100 = normalizeHorasNumber(Number(row.horas_extra_100 ?? 0));
        acc.extra50 += extra50;
        acc.extra100 += extra100;
        acc.normais += normalizeHorasNumber(horas - extra50 - extra100);
      } else if (percentual === 50) {
        acc.extra50 += horas;
      } else if (percentual === 100) {
        acc.extra100 += horas;
      } else {
        acc.normais += horas;
      }

      return acc;
    },
    { normais: 0, extra50: 0, extra100: 0 }
  );
}

function getTipoHHLabel(percentual: number): string {
  if (percentual === 50) return "Extra 50%";
  if (percentual === 100) return "Extra 100%";
  return "Normal";
}

function formatSupabaseError(err: unknown): string {
  if (!err || typeof err !== "object") return "Erro ao salvar lançamento HH.";
  const e = err as { message?: string; details?: string; hint?: string };
  const parts = [e.message ?? "Erro ao salvar lançamento HH.", e.details, e.hint].filter(Boolean);
  return parts.join(" | ");
}

function parseHHMM(value: string): number | null {
  const raw = String(value ?? "").trim();
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(raw);
  if (!m) return null;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  return hh * 60 + mm;
}

function calcHorasDecimalFromMinutes(inicioMin: number, fimMin: number): number {
  let diff = fimMin - inicioMin;
  if (diff < 0) diff = 1440 - inicioMin + fimMin; // virada de dia
  return Number((diff / 60).toFixed(2));
}

function getHorasTrabalhadasEfetivas(row: HhLancamentoViewRow): number {
  const e1 = formatTimeHHMM(row.entrada_1) || formatTimeHHMM(row.hora_entrada);
  const s1 = formatTimeHHMM(row.saida_1) || formatTimeHHMM(row.hora_saida);
  const e2 = formatTimeHHMM(row.entrada_2);
  const s2 = formatTimeHHMM(row.saida_2);

  // Se houver 2 períodos completos, soma os dois (não conta almoço).
  if (e1 && s1 && e2 && s2) {
    const e1Min = parseHHMM(e1);
    const s1Min = parseHHMM(s1);
    const e2Min = parseHHMM(e2);
    const s2Min = parseHHMM(s2);
    if (e1Min !== null && s1Min !== null && e2Min !== null && s2Min !== null) {
      return Number((calcHorasDecimalFromMinutes(e1Min, s1Min) + calcHorasDecimalFromMinutes(e2Min, s2Min)).toFixed(2));
    }
  }

  // Fallback: 1 período (entrada/saída) 
  if (e1 && s1) {
    const e1Min = parseHHMM(e1);
    const s1Min = parseHHMM(s1);
    if (e1Min !== null && s1Min !== null) return calcHorasDecimalFromMinutes(e1Min, s1Min);
  }

  const fallback = Number(row.horas_trabalhadas ?? 0);
  return Number.isFinite(fallback) ? fallback : 0;
}

function normalizeHorasNumber(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Number(Math.max(0, value).toFixed(2));
}

function hasManualExtra(row: HhLancamentoViewRow): boolean {
  return Boolean(row.tem_extra_50 || row.tem_extra_100) || Number(row.horas_extra_50 ?? 0) > 0 || Number(row.horas_extra_100 ?? 0) > 0;
}

function getHorasSplitEfetivo(row: HhLancamentoViewRow, horasEfetivas: number) {
  const total = normalizeHorasNumber(horasEfetivas);
  const percentualAplicado = Number(row.percentual_aplicado ?? 0);

  if (hasManualExtra(row)) {
    const extra50 = normalizeHorasNumber(Number(row.horas_extra_50 ?? 0));
    const extra100 = normalizeHorasNumber(Number(row.horas_extra_100 ?? 0));
    const normais = normalizeHorasNumber(total - extra50 - extra100);
    return { normais, extra50, extra100 };
  }

  if (percentualAplicado === 50) return { normais: 0, extra50: total, extra100: 0 };
  if (percentualAplicado === 100) return { normais: 0, extra50: 0, extra100: total };
  return { normais: total, extra50: 0, extra100: 0 };
}

function getTipoHHLabelFromSplit(row: HhLancamentoViewRow, horasEfetivas: number): string {
  const split = getHorasSplitEfetivo(row, horasEfetivas);
  const parts: string[] = [];
  if (split.normais > 0) parts.push("Normal");
  if (split.extra50 > 0) parts.push("Extra 50%");
  if (split.extra100 > 0) parts.push("Extra 100%");
  return parts.length > 0 ? parts.join(" + ") : getTipoHHLabel(Number(row.percentual_aplicado ?? 0));
}

function getValorTotalEfetivo(row: HhLancamentoViewRow, horasEfetivas: number): number {
  const totalDb = Number(row.valor_total ?? 0);
  const percentualAplicado = Number(row.percentual_aplicado ?? 0);
  if ((hasManualExtra(row) || percentualAplicado === 50 || percentualAplicado === 100) && Number.isFinite(totalDb) && totalDb > 0) {
    return totalDb;
  }

  const valorHora = Number(row.valor_hora ?? 0);
  if (Number.isFinite(valorHora) && valorHora > 0 && Number.isFinite(horasEfetivas) && horasEfetivas > 0) {
    const split = getHorasSplitEfetivo(row, horasEfetivas);
    return Number(
      (split.normais * valorHora + split.extra50 * valorHora * 1.5 + split.extra100 * valorHora * 2).toFixed(2)
    );
  }
  return Number.isFinite(totalDb) ? totalDb : 0;
}

function isMissingColumnError(err: unknown): boolean {
  const message =
    err && typeof err === "object" && "message" in err ? String((err as { message?: unknown }).message ?? "") : "";
  return (
    /column\s+"?\w+"?\s+does not exist/i.test(message) ||
    /could not find the '\w+' column/i.test(message)
  );
}

function addOneDayISO(dateStr: string): string {
  const raw = String(dateStr ?? "").trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!m) return raw;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  if (!Number.isFinite(y) || !Number.isFinite(mo) || !Number.isFinite(d)) return raw;
  const utc = Date.UTC(y, mo - 1, d);
  if (!Number.isFinite(utc)) return raw;
  const next = new Date(utc + 24 * 60 * 60 * 1000);
  return next.toISOString().slice(0, 10);
}

function formatCurrencyBRL(value: number): string {
  const v = Number(value ?? 0);
  const safe = Number.isFinite(v) ? v : 0;
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(safe);
}

async function fetchImageAsDataUrl(url: string): Promise<string | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const blob = await res.blob();
    const dataUrl = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error("reader error"));
      reader.onload = () => resolve(String(reader.result ?? ""));
      reader.readAsDataURL(blob);
    });
    return dataUrl || null;
  } catch {
    return null;
  }
}

async function getImageNaturalSize(dataUrl: string): Promise<{ width: number; height: number } | null> {
  try {
    return await new Promise((resolve) => {
      const img = new globalThis.Image();
      img.onload = () => {
        const width = Number(img.naturalWidth || img.width || 0);
        const height = Number(img.naturalHeight || img.height || 0);
        if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
          resolve(null);
          return;
        }
        resolve({ width, height });
      };
      img.onerror = () => resolve(null);
      img.src = dataUrl;
    });
  } catch {
    return null;
  }
}

async function gerarRelatorioPDF(
  hhRows: HhLancamentoViewRow[],
  osId: number,
  header?: {
    empresaNome?: string;
    clienteNome?: string;
    numeroOS?: string;
    osDescricao?: string;
    periodoLabel?: string;
    emissaoLabel?: string;
  }
) {
  try {
    // Importa jsPDF dinamicamente
    const { jsPDF } = await import("jspdf");
    const autoTable = await import("jspdf-autotable");

    const doc = new jsPDF({
      orientation: "landscape",
      unit: "mm",
      format: "a4",
    });

    const margin = 12;
    const headerHeight = 28;
    const topStartY = margin + headerHeight + 4;

    // Paleta e fontes
    const titleColor: [number, number, number] = [20, 20, 20];
    const subtitleColor: [number, number, number] = [60, 60, 60];
    const tableHeadFill: [number, number, number] = [32, 32, 32];
    const tableHeadText: [number, number, number] = [240, 240, 240];
    const tableBodyText: [number, number, number] = [40, 40, 40];
    const zebraFill: [number, number, number] = [248, 248, 248];

    const empresaNome = header?.empresaNome?.trim() || "—";
    const clienteNome = header?.clienteNome?.trim() || "—";
    const numeroOS = header?.numeroOS?.trim() || String(osId);
    const osDescricao = header?.osDescricao?.trim() || "";
    const periodoLabel = header?.periodoLabel?.trim() || "—";
    const emissaoLabel = header?.emissaoLabel?.trim() || new Date().toLocaleString("pt-BR");

    const osLine = osDescricao ? `OS ${numeroOS} - ${osDescricao}` : `OS ${numeroOS}`;
    const logoDataUrl = await fetchImageAsDataUrl("/Segau2.png");
    const logoSize = logoDataUrl ? await getImageNaturalSize(logoDataUrl) : null;
    const logoBox = { w: 18, h: 18 };

    const truncateToWidth = (text: string, maxWidth: number) => {
      const clean = String(text ?? "").replace(/\s+/g, " ").trim();
      if (!clean) return "";
      if (maxWidth <= 0) return "";
      if (doc.getTextWidth(clean) <= maxWidth) return clean;

      const ellipsis = "…";
      if (doc.getTextWidth(ellipsis) > maxWidth) return ellipsis;

      let lo = 0;
      let hi = clean.length;
      while (lo < hi) {
        const mid = Math.ceil((lo + hi) / 2);
        const candidate = clean.slice(0, mid) + ellipsis;
        if (doc.getTextWidth(candidate) <= maxWidth) lo = mid;
        else hi = mid - 1;
      }
      const finalLen = Math.max(0, lo);
      return clean.slice(0, finalLen) + ellipsis;
    };

    const wrapTwoLines = (text: string, maxWidth: number) => {
      const clean = String(text ?? "").replace(/\s+/g, " ").trim();
      if (!clean) return [""];
      const lines = doc.splitTextToSize(clean, Math.max(10, maxWidth)) as string[];
      if (lines.length <= 1) return [truncateToWidth(lines[0] ?? clean, maxWidth)];
      if (lines.length === 2) return [truncateToWidth(lines[0], maxWidth), truncateToWidth(lines[1], maxWidth)];
      return [truncateToWidth(lines[0], maxWidth), truncateToWidth(lines.slice(1).join(" "), maxWidth)];
    };

    const drawHeader = (pageNumber: number, pageCount: number) => {
      const pageSize = doc.internal.pageSize;
      const pageWidth = pageSize.getWidth();
      const rightX = pageWidth - margin;
      const leftX = margin + 22;
      const gap = 6;

      // Linha superior
      doc.setDrawColor(17, 24, 39);
      doc.setLineWidth(0.6);
      doc.line(margin, margin + headerHeight + 1, pageWidth - margin, margin + headerHeight + 1);

      // Logo (opcional)
      if (logoDataUrl) {
        try {
          let drawW = logoBox.w;
          let drawH = logoBox.h;
          if (logoSize) {
            const ratio = logoSize.width / logoSize.height;
            drawW = logoBox.w;
            drawH = drawW / ratio;
            if (drawH > logoBox.h) {
              drawH = logoBox.h;
              drawW = drawH * ratio;
            }
          }
          const x = margin + (logoBox.w - drawW) / 2;
          const y = margin + (logoBox.h - drawH) / 2;
          doc.addImage(logoDataUrl, "PNG", x, y, drawW, drawH);
        } catch {
          // ignora se falhar
        }
      }

      // Bloco empresa/cliente (esquerda)
      // Primeiro mede o título para reservar espaço e impedir sobreposição
      doc.setFont("helvetica", "bold");
      doc.setFontSize(15);
      const titulo = "Relatório de Horas Lançadas";
      const tituloWidth = doc.getTextWidth(titulo);
      const tituloLeftEdge = pageWidth / 2 - tituloWidth / 2;
      const tituloRightEdge = pageWidth / 2 + tituloWidth / 2;

      // Mede o bloco da direita e limita para não invadir o título
      doc.setFont("helvetica", "normal");
      doc.setFontSize(9);
      const rightLines = [`Emissão: ${emissaoLabel}`, `Período: ${periodoLabel}`, `Página ${pageNumber} de ${pageCount}`];
      const measuredRightWidth = Math.max(...rightLines.map((t) => doc.getTextWidth(t)));
      const maxRightWidth = Math.max(40, rightX - (tituloRightEdge + gap));
      const rightColWidth = Math.min(Math.max(55, measuredRightWidth + 2), maxRightWidth);
      const rightBlockStart = rightX - rightColWidth;

      // Calcula a largura máxima do bloco esquerdo sem invadir o título
      doc.setFont("helvetica", "bold");
      doc.setFontSize(11);
      const leftMaxEnd = tituloLeftEdge - gap;
      const leftMaxWidth = Math.max(20, leftMaxEnd - leftX);

      doc.setTextColor(titleColor[0], titleColor[1], titleColor[2]);
      doc.text(truncateToWidth(empresaNome, leftMaxWidth), leftX, margin + 7);

      doc.setFont("helvetica", "normal");
      doc.setFontSize(9);
      doc.setTextColor(subtitleColor[0], subtitleColor[1], subtitleColor[2]);
      doc.text(truncateToWidth(`Cliente: ${clienteNome}`, leftMaxWidth), leftX, margin + 13);

      // Título (centro)
      doc.setFont("helvetica", "bold");
      doc.setFontSize(15);
      doc.setTextColor(titleColor[0], titleColor[1], titleColor[2]);
      doc.text(titulo, pageWidth / 2, margin + 8, { align: "center" });

      // Linha de OS (centro) com quebra/truncamento e respeitando blocos esquerda/direita
      const centerLeftBound = leftX + leftMaxWidth + gap;
      const centerRightBound = rightBlockStart - gap;
      const centerMaxWidth = Math.max(60, centerRightBound - centerLeftBound);

      doc.setFontSize(11);
      doc.setFont("helvetica", "normal");
      doc.setTextColor(subtitleColor[0], subtitleColor[1], subtitleColor[2]);
      const osLines = wrapTwoLines(osLine, centerMaxWidth);
      doc.text(osLines[0] ?? "", pageWidth / 2, margin + 14, { align: "center" });
      if (osLines.length > 1 && osLines[1]) {
        doc.text(osLines[1], pageWidth / 2, margin + 18.5, { align: "center" });
      }

      // Metas (direita)
      doc.setFontSize(9);
      doc.setTextColor(subtitleColor[0], subtitleColor[1], subtitleColor[2]);
      doc.text(truncateToWidth(`Emissão: ${emissaoLabel}`, rightColWidth), rightX, margin + 7, { align: "right" });
      doc.text(truncateToWidth(`Período: ${periodoLabel}`, rightColWidth), rightX, margin + 13, { align: "right" });
      doc.text(truncateToWidth(`Página ${pageNumber} de ${pageCount}`, rightColWidth), rightX, margin + 19, { align: "right" });
    };

    // Tabela 1: Lançamentos
    const headRowLancamentos: RowInput = [
      "Funcionário",
      "Data",
      "Entrada 1",
      "Saída 1",
      "Entrada 2",
      "Saída 2",
      "Horas",
      "Tipo",
      "Horas Normais",
      "Extra 50%",
      "Extra 100%",
      "R$ Total",
    ];

    const bodyLancamentos: RowInput[] = [];

    let totalGeral = 0;
    let totalHoras = 0;
    let totalHorasNormais = 0;
    let totalHorasExtra50 = 0;
    let totalHorasExtra100 = 0;

    hhRows.forEach((r) => {
      const horas = getHorasTrabalhadasEfetivas(r);
      const split = getHorasSplitEfetivo(r, horas);
      const tipo = getTipoHHLabelFromSplit(r, horas);
      const total = getValorTotalEfetivo(r, horas);

      totalGeral += total;
      totalHoras += horas;
      totalHorasNormais += split.normais;
      totalHorasExtra50 += split.extra50;
      totalHorasExtra100 += split.extra100;

      bodyLancamentos.push([
        r.colaborador_nome ?? "—",
        formatDateDDMMAA(r.data),
        formatTimeHHMM(r.entrada_1) || formatTimeHHMM(r.hora_entrada) || "—",
        formatTimeHHMM(r.saida_1) || formatTimeHHMM(r.hora_saida) || "—",
        formatTimeHHMM(r.entrada_2) || "—",
        formatTimeHHMM(r.saida_2) || "—",
        formatHoursBR(horas),
        tipo,
        formatHoursBR(split.normais),
        formatHoursBR(split.extra50),
        formatHoursBR(split.extra100),
        formatCurrencyBRL(total),
      ]);
    });

    // Linha de TOTAL
    bodyLancamentos.push([
      "",
      "",
      "",
      "",
      "",
      "",
      formatHoursBR(totalHoras),
      "TOTAL",
      formatHoursBR(totalHorasNormais),
      formatHoursBR(totalHorasExtra50),
      formatHoursBR(totalHorasExtra100),
      formatCurrencyBRL(totalGeral),
    ]);

    // Tabela 1
    const totalRowIndex = bodyLancamentos.length - 1;
    autoTable.default(doc, {
      startY: topStartY,
      head: [headRowLancamentos],
      body: bodyLancamentos,
      margin: { top: topStartY, left: margin, right: margin, bottom: 10 },
      styles: {
        cellPadding: 1.6,
        lineWidth: 0.1,
        lineColor: [220, 220, 220],
        overflow: "linebreak",
      },
      didParseCell: (data: CellHookData) => {
        // Destaque profissional na linha TOTAL
        if (data?.section !== "body") return;
        if (data?.row?.index !== totalRowIndex) return;
        data.cell.styles.fontStyle = "bold";
        // Cinza bem suave (mais perceptível, porém profissional)
        data.cell.styles.fillColor = [238, 240, 243];
        data.cell.styles.textColor = [20, 20, 20];
        data.cell.styles.lineWidth = 0.2;
        data.cell.styles.fontSize = 9;
      },
      didDrawCell: (data: CellHookData) => {
        // Linha superior mais grossa para separar o TOTAL
        if (data?.section !== "body") return;
        if (data?.row?.index !== totalRowIndex) return;
        if (data?.column?.index !== 0) return;

        const tableMeta = data.table as unknown as { startX?: number; width?: number };
        const startX = Number(tableMeta.startX ?? 0);
        const width = Number(tableMeta.width ?? 0);
        const y = Number(data.cell?.y ?? 0);
        if (!Number.isFinite(startX) || !Number.isFinite(width) || !Number.isFinite(y) || width <= 0) return;

        doc.setDrawColor(140, 140, 140);
        doc.setLineWidth(0.6);
        doc.line(startX, y, startX + width, y);
      },
      columnStyles: {
        0: { cellWidth: 54 }, // Funcionário
        1: { cellWidth: 16, halign: "center" }, // Data (ddMMyy)
        2: { cellWidth: 16, halign: "center" }, // Entrada 1
        3: { cellWidth: 16, halign: "center" }, // Saída 1
        4: { cellWidth: 16, halign: "center" }, // Entrada 2
        5: { cellWidth: 16, halign: "center" }, // Saída 2
        6: { cellWidth: 16, halign: "right" }, // Horas
        7: { cellWidth: 30 }, // Tipo
        8: { cellWidth: 18, halign: "right" }, // Horas Normais
        9: { cellWidth: 18, halign: "right" }, // Extra 50%
        10: { cellWidth: 18, halign: "right" }, // Extra 100%
        11: { cellWidth: 23, halign: "right" }, // R$ Total
      },
      headStyles: {
        fillColor: tableHeadFill,
        textColor: tableHeadText,
        fontSize: 9,
        fontStyle: "bold",
        lineWidth: 0.2,
        lineColor: [220, 220, 220],
        halign: "center",
      },
      bodyStyles: {
        fontSize: 8.6,
        textColor: tableBodyText,
      },
      alternateRowStyles: {
        fillColor: zebraFill,
      },
    });

    // Tabela 2: Valores por funcionário/função
    const uniqueValores = new Map<string, { funcionario: string; funcao: string; valorHora: number }>();
    hhRows.forEach((r) => {
      const funcionario = (r.colaborador_nome ?? "—").trim() || "—";
      const funcao =
        r.especialidade_descricao && r.especialidade_descricao.trim() ? r.especialidade_descricao.trim() : "—";
      const valorHora = Number(r.valor_hora ?? 0);
      const key = `${funcionario}||${funcao}||${valorHora}`;
      if (!uniqueValores.has(key)) uniqueValores.set(key, { funcionario, funcao, valorHora });
    });

    const valoresSorted = Array.from(uniqueValores.values()).sort((a, b) => {
      const byFunc = a.funcionario.localeCompare(b.funcionario, "pt-BR", { sensitivity: "base" });
      if (byFunc !== 0) return byFunc;
      return a.funcao.localeCompare(b.funcao, "pt-BR", { sensitivity: "base" });
    });

    const headRowValores: RowInput = ["Funcionário", "Função", "V. Hora Normal", "V. Hora 50%", "V. Hora 100%"];
    const bodyValores: RowInput[] = valoresSorted.map((v) => {
      const v50 = v.valorHora * 1.5;
      const v100 = v.valorHora * 2.0;
      return [v.funcionario, v.funcao, formatCurrencyBRL(v.valorHora), formatCurrencyBRL(v50), formatCurrencyBRL(v100)];
    });

    if (bodyValores.length > 0) {
      const lastY =
        (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY ?? topStartY;

      autoTable.default(doc, {
        startY: lastY + 8,
        head: [headRowValores],
        body: bodyValores,
        margin: { top: topStartY, left: margin, right: margin, bottom: 10 },
        styles: {
          cellPadding: 1.6,
          lineWidth: 0.1,
          lineColor: [220, 220, 220],
          overflow: "linebreak",
        },
        columnStyles: {
          0: { cellWidth: 75 }, // Funcionário
          1: { cellWidth: 75 }, // Função
          2: { cellWidth: 25, halign: "right" }, // V. Hora Normal
          3: { cellWidth: 25, halign: "right" }, // V. Hora 50%
          4: { cellWidth: 25, halign: "right" }, // V. Hora 100%
        },
        headStyles: {
          fillColor: tableHeadFill,
          textColor: tableHeadText,
          fontSize: 9,
          fontStyle: "bold",
          lineWidth: 0.2,
          lineColor: [220, 220, 220],
          halign: "center",
        },
        bodyStyles: {
          fontSize: 8.6,
          textColor: tableBodyText,
        },
        alternateRowStyles: {
          fillColor: zebraFill,
        },
      });
    }

    // Tabelas 3+: Resumo por função (Normal / Extra 50% / Extra 100%)
    type ResumoAgg = { funcao: string; valorHoraBase: number; horas: number; total: number };
    const resumoNormal = new Map<string, ResumoAgg>();
    const resumo50 = new Map<string, ResumoAgg>();
    const resumo100 = new Map<string, ResumoAgg>();

    for (const r of hhRows) {
      const funcao =
        r.especialidade_descricao && r.especialidade_descricao.trim() ? r.especialidade_descricao.trim() : "—";
      const valorHoraBase = Number(r.valor_hora ?? 0);
      const horas = getHorasTrabalhadasEfetivas(r);
      const split = getHorasSplitEfetivo(r, horas);

      const addBucket = (bucket: Map<string, ResumoAgg>, horasBucket: number, multiplier: number) => {
        if (!Number.isFinite(horasBucket) || horasBucket <= 0) return;
        const key = `${funcao}||${valorHoraBase}`;
        const cur = bucket.get(key) ?? { funcao, valorHoraBase, horas: 0, total: 0 };
        cur.horas += horasBucket;
        cur.total += Number((horasBucket * valorHoraBase * multiplier).toFixed(2));
        bucket.set(key, cur);
      };

      addBucket(resumoNormal, split.normais, 1);
      addBucket(resumo50, split.extra50, 1.5);
      addBucket(resumo100, split.extra100, 2);
    }

    const addResumoTable = (title: string, map: Map<string, ResumoAgg>, multiplier: number) => {
      const rows = Array.from(map.values()).filter((x) => (Number(x.horas) || 0) !== 0 || (Number(x.total) || 0) !== 0);
      if (!rows.length) return;

      rows.sort((a, b) => {
        const byFuncao = a.funcao.localeCompare(b.funcao, "pt-BR", { sensitivity: "base" });
        if (byFuncao !== 0) return byFuncao;
        return a.valorHoraBase - b.valorHoraBase;
      });

      const body: RowInput[] = [];
      let sumHoras = 0;
      let sumTotal = 0;

      for (const row of rows) {
        sumHoras += Number(row.horas ?? 0) || 0;
        sumTotal += Number(row.total ?? 0) || 0;
        body.push([
          row.funcao,
          formatHoursBR(row.horas),
          formatCurrencyBRL((Number(row.valorHoraBase ?? 0) || 0) * multiplier),
          formatCurrencyBRL(row.total),
        ]);
      }

      body.push(["TOTAL", formatHoursBR(sumHoras), "", formatCurrencyBRL(sumTotal)]);

      const lastY =
        (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY ?? topStartY;

      // Title row (keeps title with table across page breaks)
      const titleRow =
        [
          {
            content: title,
            colSpan: 4,
            styles: {
              fillColor: [255, 255, 255],
              textColor: titleColor,
              fontStyle: "bold",
              halign: "left",
              fontSize: 10,
            },
          },
        ] as unknown as RowInput;

      const head: RowInput[] = [titleRow, ["Função", "Total horas", "Valor hora", "Total"]];

      autoTable.default(doc, {
        startY: lastY + 8,
        head,
        body,
        margin: { top: topStartY, left: margin, right: margin, bottom: 10 },
        styles: {
          cellPadding: 1.6,
          lineWidth: 0.1,
          lineColor: [220, 220, 220],
          overflow: "linebreak",
        },
        columnStyles: {
          0: { cellWidth: 120 }, // Função
          1: { cellWidth: 26, halign: "right" }, // Total horas
          2: { cellWidth: 28, halign: "right" }, // Valor hora
          3: { cellWidth: 28, halign: "right" }, // Total
        },
        headStyles: {
          fillColor: tableHeadFill,
          textColor: tableHeadText,
          fontSize: 9,
          fontStyle: "bold",
          lineWidth: 0.2,
          lineColor: [220, 220, 220],
          halign: "center",
        },
        bodyStyles: {
          fontSize: 8.6,
          textColor: tableBodyText,
        },
        alternateRowStyles: {
          fillColor: zebraFill,
        },
      });
    };

    addResumoTable("Resumo por função — Horas Normais", resumoNormal, 1);
    addResumoTable("Resumo por função — Extras 50%", resumo50, 1.5);
    addResumoTable("Resumo por função — Extras 100%", resumo100, 2);

    // Cabeçalho com paginação correta
    const pageCount = doc.getNumberOfPages();
    for (let page = 1; page <= pageCount; page += 1) {
      doc.setPage(page);
      drawHeader(page, pageCount);
    }

    // Download
    const dataStr = new Date().toISOString().slice(0, 10);
    doc.save(`relatorio-hh-os-${osId}-${dataStr}.pdf`);
  } catch (e) {
    console.error("Erro ao gerar PDF:", e);
    alert("Erro ao gerar PDF");
  }
}



export default function RelatorioHHSection({
  osId,
  osDetail,
  osStatus = null,
  usaRelatorioHh = null,
  enabled = true,
  effectiveTenantId = null,
  effectiveEmpresaId = null,
}: {
  osId: number;
  osDetail?: { cliente_id: number | null } | null;
  osStatus?: "aberta" | "em_andamento" | "concluida" | "cancelada" | null;
  usaRelatorioHh?: boolean | null;
  enabled?: boolean;
  clienteHabilitaHH?: boolean;
  effectiveTenantId?: string | null;
  effectiveEmpresaId?: string | null;
}) {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const tenantEmpresa = useTenantEmpresa();
  const { tenantId, empresaId } = tenantEmpresa;
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canRead = Boolean(has("os.read"));
  const canWrite = Boolean(has("os.write"));
  const canDelete = Boolean(has("os.delete"));

  const resolvedEmpresaId = effectiveEmpresaId ?? empresaId ?? null;
  const empresaPapel = useMemo(() => {
    if (!resolvedEmpresaId) return null;
    const byId = (tenantEmpresa.empresas ?? []).find((e) => e.id === resolvedEmpresaId) ?? null;
    if (byId?.papel) return String(byId.papel);
    if (tenantEmpresa.empresa?.id === resolvedEmpresaId && tenantEmpresa.empresa?.papel) return String(tenantEmpresa.empresa.papel);
    return tenantEmpresa.empresa?.papel ? String(tenantEmpresa.empresa.papel) : null;
  }, [resolvedEmpresaId, tenantEmpresa.empresa, tenantEmpresa.empresas]);
  const hideEspecialidadeValores = (empresaPapel ?? "").trim().toUpperCase() === "APONTAMENTO_RH";
  
  // Garantir que cliente_id sempre vem do osDetail (requerido para todo fluxo HH)
  const clienteIdContext = osDetail?.cliente_id ?? null;
  const hhOs = Boolean(usaRelatorioHh);
  const showHhStatusWarning = hhOs && osStatus !== null && osStatus !== "em_andamento";
  const canShowNovoLancamento = hhOs && enabled && osStatus === "em_andamento" && canWrite;

  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function ensureDbContext() {
    // Prioriza props recebidas
    const resolvedTenant = effectiveTenantId ?? tenantId ?? null;
    const resolvedEmpresa = effectiveEmpresaId ?? empresaId ?? null;
    return { tenant: resolvedTenant, empresa: resolvedEmpresa } as const;
  }

  const [osMeta, setOsMeta] = useState<{ numero_os: string | null; cliente_nome: string | null; descricao_servico: string | null } | null>(null);

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!supabase) return;
      const { tenant } = await ensureDbContext();
      if (!tenant) return;

      const { data, error } = await applyTenant(
        supabase
          .from("ordens_servico")
          .select("numero_os, cliente_nome, descricao_servico")
          .eq("tipo_documento", "OS")
          .eq("id", osId)
          .maybeSingle(),
        tenant
      );

      if (!active) return;
      if (error) return;
      setOsMeta({
        numero_os: data?.numero_os ? String(data.numero_os) : String(osId),
        cliente_nome: data?.cliente_nome ?? null,
        descricao_servico: data?.descricao_servico ?? null,
      });
    };

    void run();
    return () => {
      active = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supabase, osId, tenantId, empresaId, effectiveTenantId, effectiveEmpresaId]);

  // Estados para tabela de lançamentos HH (cobrança) desta OS
  const [hhRows, setHhRows] = useState<HhLancamentoViewRow[]>([]);
  const [loadingHh, setLoadingHh] = useState(false);
  const [hhErr, setHhErr] = useState<string | null>(null);

  const printHeader = useMemo(() => {
    const empresaNome =
      tenantEmpresa.empresa?.nome_fantasia ?? tenantEmpresa.empresa?.razao_social ?? "";

    const clienteNome = osMeta?.cliente_nome ?? "";
    const numeroOS = osMeta?.numero_os ?? String(osId);
    const osDescricao = osMeta?.descricao_servico ?? "";
    const emissao = new Date();

    const dates = hhRows
      .map((r) => String(r.data ?? "").trim())
      .filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d));
    const minDate = dates.length ? dates.reduce((a, b) => (a < b ? a : b)) : null;
    const maxDate = dates.length ? dates.reduce((a, b) => (a > b ? a : b)) : null;
    const periodo =
      minDate && maxDate
        ? `${formatDateBR(minDate)} a ${formatDateBR(maxDate)}`
        : "—";

    const totals = hhRows.reduce(
      (acc, r) => {
        const horas = getHorasTrabalhadasEfetivas(r);
        acc.horas += Number.isFinite(horas) ? horas : 0;
        acc.valor += getValorTotalEfetivo(r, horas);
        return acc;
      },
      { horas: 0, valor: 0 }
    );

    return {
      empresaNome: empresaNome.trim() || "—",
      clienteNome: clienteNome.trim() || "—",
      numeroOS,
      osDescricao: osDescricao.trim() || "",
      emissaoLabel: emissao.toLocaleString("pt-BR"),
      periodoLabel: periodo,
      totalHoras: totals.horas,
      totalValor: totals.valor,
    };
  }, [hhRows, osId, osMeta, tenantEmpresa.empresa?.nome_fantasia, tenantEmpresa.empresa?.razao_social]);

  // Estados para lançamento/edição de horas
  const [showLancamentoForm, setShowLancamentoForm] = useState(false);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [especialidadesOptions, setEspecialidadesOptions] = useState<EspecialidadeOption[]>([]);
  const [especialidadeLocked, setEspecialidadeLocked] = useState(false);
  const [tabelaAtiva, setTabelaAtiva] = useState<TabelaAtiva | null>(null);
  const [precoServicoSelecionado, setPrecoServicoSelecionado] = useState<{ preco_base: number; preco_50: number; preco_100: number } | null>(null);
  const vinculoEspecialidadesRef = useRef<Map<string, string[]>>(new Map());
  const [horaEntrada1, setHoraEntrada1] = useState("07:30");
  const [horaSaida1, setHoraSaida1] = useState("12:00");
  const [horaEntrada2, setHoraEntrada2] = useState("13:00");
  const [horaSaida2, setHoraSaida2] = useState("17:00");
  const [temExtra50, setTemExtra50] = useState(false);
  const [horasExtra50Input, setHorasExtra50Input] = useState("");
  const [temExtra100, setTemExtra100] = useState(false);
  const [horasExtra100Input, setHorasExtra100Input] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [lancamentoForm, setLancamentoForm] = useState({
    data: new Date().toISOString().slice(0, 10),
    colaborador_id: "",
    hh_servico_id: "",
    observacao: "",
  });
  const [percentualManual, setPercentualManual] = useState<"" | "0" | "50" | "100">("");
  const [lancamentoBusy, setLancamentoBusy] = useState(false);
  const lancamentoDateRef = useRef<HTMLInputElement | null>(null);
  const lancamentoSubmitLockRef = useRef(false);
  const editingOriginalKeyRef = useRef<{ data: string; colaborador_id: string } | null>(null);

  useEffect(() => {
    if (!showLancamentoForm) return;
    const t = setTimeout(() => {
      lancamentoDateRef.current?.focus();
    }, 0);
    return () => clearTimeout(t);
  }, [showLancamentoForm]);

  useEffect(() => {
    if (!clienteIdContext) {
      setHhErr("Cliente não identificado. Não é possível carregar apontamentos HH.");
      return;
    }
    void loadHhLancamentos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [osId, clienteIdContext]);

  async function loadRelatorios() {
    // DEPRECATED: Tabela os_relatorios_hh foi removida.
    // Relatórios agora são gerados direto de hh_lancamentos em tempo real.
    // Esta função é um no-op para compatibilidade.
    return;
  }

  async function loadTabelaAtiva(clienteId: number, dataISO: string): Promise<TabelaAtiva | null> {
    if (!clienteId) {
      console.warn("[loadTabelaAtiva] cliente_id não fornecido");
      return null;
    }
    const ctx = await ensureDbContext();
    if (!ctx.tenant || !ctx.empresa) {
      console.warn("[loadTabelaAtiva] tenant/empresa não resolvido");
      return null;
    }
    const empresaId = ctx.empresa ?? "";
    try {
      // 1. Tentar tabela vigente (dentro do período)
      const { data: vigente, error: vigenteErr } = await applyTenantEmpresa(
        supabase
          .from("cliente_hh_tabelas")
          .select("id,cliente_id,nome,vigencia_inicio,vigencia_fim,ativo")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .lte("vigencia_inicio", dataISO)
          .gte("vigencia_fim", dataISO)
          .order("vigencia_inicio", { ascending: false })
          .limit(1)
          .maybeSingle(),
        ctx.tenant ?? "",
        empresaId ?? ""
      );
      if (!vigenteErr && vigente) {
        console.log("[loadTabelaAtiva] Tabela vigente encontrada:", vigente.id);
        return vigente as TabelaAtiva;
      }
      // 2. Fallback: tabela mais recente (mesmo se fora do período)
      const { data: recent, error: recentErr } = await applyTenantEmpresa(
        supabase
          .from("cliente_hh_tabelas")
          .select("id,cliente_id,nome,vigencia_inicio,vigencia_fim,ativo")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .order("vigencia_inicio", { ascending: false })
          .limit(1)
          .maybeSingle(),
        ctx.tenant ?? "",
        ctx.empresa ?? ""
      );
      if (!recentErr && recent) {
        console.warn("[loadTabelaAtiva] Usando tabela fora do período (fallback):", recent.id);
        return recent as TabelaAtiva;
      }
      if (recentErr) throw recentErr;
      console.warn("[loadTabelaAtiva] Nenhuma tabela HH encontrada para cliente:", clienteId);
      return null;
    } catch (e) {
      console.error("[loadTabelaAtiva] Erro:", e);
      return null;
    }
  }

  async function loadColaboradores(clienteId: number) {
    if (!clienteId) {
      console.warn("[loadColaboradores] cliente_id não fornecido");
      setColaboradores([]);
      return;
    }
    
    const ctx = await ensureDbContext();
    if (!ctx.tenant) {
      console.warn("[loadColaboradores] tenant não resolvido");
      setColaboradores([]);
      return;
    }

    vinculoEspecialidadesRef.current = new Map();

    try {
      console.log("[loadColaboradores] Carregando colaboradores para cliente:", clienteId);
      // Carregar vínculos colaborador-cliente-função
      const { data: vinculosData, error: vinculosErr } = await applyTenantEmpresa(
        supabase
          .from("colaborador_cliente_funcao")
          .select("colaborador_id,hh_servico_id,ativo,cliente_id")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .order("colaborador_id", { ascending: true }),
        ctx.tenant ?? "",
        ctx.empresa ?? ""
      );
      if (vinculosErr) throw vinculosErr;
      const vinculos = (vinculosData ?? []).filter((v) => v.colaborador_id) as Array<{
        colaborador_id: string;
        hh_servico_id?: string | number | null;
      }>;
      if (vinculos.length === 0) {
        console.warn("[loadColaboradores] Nenhum colaborador vinculado ao cliente:", clienteId);
        setColaboradores([]);
        return;
      }
      // Mapear vínculos: colaborador_id → [hh_servico_ids]
      vinculoEspecialidadesRef.current = new Map();
      vinculos.forEach((v) => {
        const colabId = String(v.colaborador_id);
        const servicoId = v.hh_servico_id ?? null;
        if (!servicoId || servicoId === "" || servicoId === null) return;
        const list = vinculoEspecialidadesRef.current.get(colabId) ?? [];
        const servicoStr = String(servicoId);
        if (!list.includes(servicoStr)) list.push(servicoStr);
        vinculoEspecialidadesRef.current.set(colabId, list);
      });
      const colaboradorIds = Array.from(new Set(vinculos.map((v) => String(v.colaborador_id))));
      // Carregar dados dos colaboradores
      const { data: colaboradoresData, error: colaboradoresErr } = await applyTenantEmpresa(
        supabase
          .from("colaboradores")
          .select("id,nome,ativo")
          .in("id", colaboradorIds)
          .eq("ativo", true)
          .order("nome", { ascending: true }),
        ctx.tenant ?? "",
        ctx.empresa ?? ""
      );
      if (colaboradoresErr) throw colaboradoresErr;
      const mapped = (colaboradoresData ?? []).map((c: { id: string; nome: string; ativo: boolean }) => ({
        id: String(c.id),
        nome: String(c.nome ?? ""),
        ativo: Boolean(c.ativo),
      }));
      console.log("[loadColaboradores] Carregados", mapped.length, "colaboradores");
      setColaboradores(mapped);
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : JSON.stringify(e);
      console.error("[loadColaboradores] Erro:", message);
      setErr(`Erro ao carregar colaboradores: ${message}`);
      setColaboradores([]);
    }
  }

  async function loadEspecialidadesParaColaborador(clienteId: number, colaboradorId: string) {
    if (!clienteId || !colaboradorId) {
      console.warn("[loadEspecialidadesParaColaborador] cliente_id ou colaborador_id não fornecido");
      setEspecialidadesOptions([]);
      setEspecialidadeLocked(false);
      return;
    }
    
    const ctx = await ensureDbContext();
    if (!ctx.tenant || !ctx.empresa) {
      console.warn("[loadEspecialidadesParaColaborador] tenant/empresa não resolvido");
      setEspecialidadesOptions([]);
      return;
    }

    setEspecialidadesOptions([]);
    setEspecialidadeLocked(false);
    setLancamentoForm((prev) => ({ ...prev, hh_servico_id: "" }));
    setPrecoServicoSelecionado(null);

    try {
      console.log("[loadEspecialidadesParaColaborador] Carregando para", { clienteId, colaboradorId });
      
      // 1. Vínculos via ref map (já carregado em loadColaboradores)
      let servicoIds = vinculoEspecialidadesRef.current.get(colaboradorId) ?? [];

      // 2. Fallback: reconsulta direto se ref não tem (ainda não carregado)
      if (servicoIds.length === 0) {
        const { data, error } = await applyTenantEmpresa(
          supabase
            .from("colaborador_cliente_funcao")
            .select("hh_servico_id,ativo")
            .eq("colaborador_id", colaboradorId)
            .eq("cliente_id", clienteId)
            .eq("ativo", true),
          ctx.tenant,
          ctx.empresa
        );
        if (error) throw error;
        const rows = (data ?? []) as Array<{ hh_servico_id?: string | number | null }>;
        servicoIds = Array.from(new Set(rows.map((r) => String(r.hh_servico_id ?? "")).filter((v) => v && v !== "" && v !== "null")));
        if (servicoIds.length > 0) {
          console.log("[loadEspecialidadesParaColaborador] Serviços encontrados via fallback:", servicoIds);
        }
      }

      if (servicoIds.length === 0) {
        console.warn("[loadEspecialidadesParaColaborador] Nenhum serviço vinculado");
        setEspecialidadesOptions([]);
        setEspecialidadeLocked(false);
        return;
      }

      // 3. Carregar dados dos serviços (cliente_hh_servicos)
      // IMPORTANTE: empresa é escopada por RLS (current_empresa_id). Não filtrar empresa_id manualmente.
      console.log("[loadEspecialidadesParaColaborador] Buscando serviços com:", {
        tenant_id: ctx.tenant,
        empresa_id: ctx.empresa,
        cliente_id: clienteId,
        servico_ids: servicoIds,
      });

      const { data, error } = await applyTenantEmpresa(
        supabase
          .from("cliente_hh_servicos")
          .select("id,nome,ativo,preco_base,preco_50,preco_100,cliente_id,empresa_id")
          .eq("cliente_id", clienteId)
          .eq("ativo", true)
          .in("id", servicoIds)
          .order("nome", { ascending: true }),
        ctx.tenant ?? "",
        ctx.empresa ?? ""
      );
      if (error) throw error;

      // Mapear mantendo EXATAMENTE o id (bigint) como string
      const mappedOptions: EspecialidadeOption[] = ((data ?? []) as Array<{ id: string | number; nome?: string | null; preco_base?: number; preco_50?: number; preco_100?: number }>).map(
        (o) => ({
          id: String(o.id),
          descricao: o.nome ?? null,
        })
      );
      console.log("[loadEspecialidadesParaColaborador] Serviços mapeados:", mappedOptions);

      console.log("[loadEspecialidadesParaColaborador] Opções carregadas:", mappedOptions.length);
      setEspecialidadesOptions(mappedOptions);

      // Se apenas 1 especialidade, auto-selecionar
      if (mappedOptions.length === 1) {
        const servicoId = String(mappedOptions[0].id);
        setEspecialidadeLocked(true);
        setLancamentoForm((prev) => ({ ...prev, hh_servico_id: servicoId }));
        
        // Pré-carregar preços da especialidade selecionada
        const servicoRows = (data ?? []) as Array<{
          id: string | number;
          preco_base?: number | null;
          preco_50?: number | null;
          preco_100?: number | null;
        }>;
        const servicoData = servicoRows.find((r) => String(r.id) === servicoId) ?? null;
        if (servicoData) {
          setPrecoServicoSelecionado({
            preco_base: Number(servicoData.preco_base ?? 0),
            preco_50: Number(servicoData.preco_50 ?? 0),
            preco_100: Number(servicoData.preco_100 ?? 0),
          });
        }
      } else if (mappedOptions.length > 1) {
        setEspecialidadeLocked(false);
        
        // Auto-selecionar baseado no tipo de dia SOMENTE se não tem serviço selecionado
        const percentual = percentualManual !== "" 
          ? Number(percentualManual) as 0 | 50 | 100
          : getPercentualFromDate(lancamentoForm.data);
        
        // Buscar serviço com preço configurado para o percentual
        // IMPORTANTE: Só buscar entre os serviços que o colaborador tem vínculo (mappedOptions)
        const servicoRows = (data ?? []) as Array<{
          id: string | number;
          preco_base?: number | null;
          preco_50?: number | null;
          preco_100?: number | null;
        }>;
        
        // Filtrar apenas serviços que estão em mappedOptions (vínculos válidos)
        const servicosVinculados = servicoRows.filter((s) => 
          mappedOptions.some((opt) => String(opt.id) === String(s.id))
        );
        
        console.log("[loadEspecialidadesParaColaborador] DEBUG auto-select:", {
          percentual,
          totalServicos: servicoRows.length,
          servicosVinculados: servicosVinculados.length,
          idsVinculados: servicosVinculados.map(s => s.id),
          mappedOptionsIds: mappedOptions.map(o => o.id),
        });
        
        let servicoEncontrado: typeof servicoRows[0] | null = null;
        if (percentual === 0) {
          servicoEncontrado = servicosVinculados.find((s) => (s.preco_base ?? 0) > 0) ?? null;
        } else if (percentual === 50) {
          servicoEncontrado = servicosVinculados.find((s) => (s.preco_50 ?? 0) > 0) ?? null;
        } else if (percentual === 100) {
          servicoEncontrado = servicosVinculados.find((s) => (s.preco_100 ?? 0) > 0) ?? null;
        }

        if (servicoEncontrado) {
          const servicoId = String(servicoEncontrado.id);
          console.log("[loadEspecialidadesParaColaborador] Auto-selecionando por percentual:", { percentual, servicoId });
          setLancamentoForm((prev) => ({ ...prev, hh_servico_id: servicoId }));
          setPrecoServicoSelecionado({
            preco_base: Number(servicoEncontrado.preco_base ?? 0),
            preco_50: Number(servicoEncontrado.preco_50 ?? 0),
            preco_100: Number(servicoEncontrado.preco_100 ?? 0),
          });
        } else {
          // Se não encontrou, limpa seleção
          console.warn("[loadEspecialidadesParaColaborador] Nenhum serviço com preço para percentual:", percentual);
          setLancamentoForm((prev) => {
            const current = String(prev.hh_servico_id ?? "").trim();
            const valid = mappedOptions.some((opt) => String(opt.id) === current);
            return valid ? prev : { ...prev, hh_servico_id: "" };
          });
        }
      }
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : JSON.stringify(e);
      console.error("[loadEspecialidadesParaColaborador] Erro:", message);
      setErr(`Erro ao carregar especialidades: ${message}`);
      setEspecialidadesOptions([]);
      setEspecialidadeLocked(false);
    }
  }

  async function loadHhLancamentos() {
    if (!Number.isFinite(osId)) return;
    setLoadingHh(true);
    setHhErr(null);
    try {
      const ctx = await ensureDbContext();
      if (!ctx.tenant || !ctx.empresa) {
        setHhErr("Tenant/empresa não carregados.");
        setHhRows([]);
        return;
      }

      console.log("[loadHhLancamentos] Carregando dados de hh_lancamentos...", { osId });

      // Carrega direto da tabela hh_lancamentos (sem view)
      const result = await applyTenantEmpresa(
        supabase
          .from("hh_lancamentos")
          .select(
            "id,os_id,data,colaborador_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,horas_trabalhadas,percentual_aplicado,tem_extra_50,horas_extra_50,tem_extra_100,horas_extra_100,observacao,criado_em,hh_tipo_id,valor_hora,valor_total,hh_especialidade_id,hh_servico_id"
          )
          .eq("os_id", osId)
          .order("criado_em", { ascending: false }),
        ctx.tenant,
        ctx.empresa
      );

      if (result.error) {
        console.error("[loadHhLancamentos] Erro ao carregar tabela:", result.error);
        throw result.error;
      }

      const rows = (result.data ?? []) as Array<{
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
      }>;

      console.log("[loadHhLancamentos] Carregados", rows.length, "registros da tabela");

      if (rows.length === 0) {
        setHhRows([]);
        return;
      }

      // Carrega colaboradores que faltam
      const colaboradorIds = Array.from(
        new Set(rows.map((r) => String(r.colaborador_id)).filter(Boolean))
      );

      const colaboradorMap = new Map<string, string>();
      if (colaboradorIds.length > 0) {
        console.log("[loadHhLancamentos] Carregando", colaboradorIds.length, "colaboradores...");
        const { data: colabData, error: colabErr } = await applyTenantEmpresa(
          supabase.from("colaboradores").select("id,nome").in("id", colaboradorIds),
          ctx.tenant,
          ctx.empresa
        );

        if (colabErr) {
          console.warn("[loadHhLancamentos] Erro ao carregar colaboradores:", colabErr);
        } else if (colabData) {
          (colabData as Array<{ id: string; nome: string }>).forEach((c) => {
            colaboradorMap.set(String(c.id), c.nome);
          });
          console.log("[loadHhLancamentos] Colaboradores carregados:", colaboradorMap.size);
        }
      }



      // Carrega serviços (especialidades) que faltam via hh_especialidade_id ou hh_servico_id
      const servicoIds = Array.from(
        new Set(
          rows
            .map((r) => String(r.hh_servico_id ?? r.hh_especialidade_id ?? "").trim())
            .filter((id) => /^\d+$/.test(id))
        )
      );

      const servicoMap = new Map<string, string>();
      if (servicoIds.length > 0) {
        console.log("[loadHhLancamentos] Carregando", servicoIds.length, "serviços...");
        const { data: svcData, error: svcErr } = await applyTenantEmpresa(
          supabase.from("cliente_hh_servicos").select("id,nome").in("id", servicoIds),
          ctx.tenant,
          ctx.empresa
        );

        if (svcErr) {
          console.warn("[loadHhLancamentos] Erro ao carregar serviços:", svcErr);
        } else if (svcData) {
          (svcData as Array<{ id: string; nome: string }>).forEach((s) => {
            servicoMap.set(String(s.id), s.nome);
          });
          console.log("[loadHhLancamentos] Serviços carregados:", servicoMap.size);
        }
      }

      // Mapeia dados para formato HhLancamentoViewRow
      const mapped: HhLancamentoViewRow[] = rows.map((r) => {
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

      console.log("[loadHhLancamentos] Dados prontos para exibição:", mapped.length, "registros");
      setHhRows(mapped);
    } catch (e: unknown) {
      let message = "Erro ao carregar lançamentos HH.";

      if (e instanceof Error) {
        message = e.message;
      } else if (typeof e === "object" && e !== null) {
        const err = e as Record<string, unknown>;
        if (typeof err.message === "string") {
          message = err.message;
        }
      }

      console.error("loadHhLancamentos error:", { osId, message, fullError: e });
      setHhErr(message);
      setHhRows([]);
    } finally {
      setLoadingHh(false);
    }
  }

  function closeLancamentoForm() {
    setShowLancamentoForm(false);
    setEditingId(null);
    editingOriginalKeyRef.current = null;
    setErr(null);
    setOk(null);
  }

  async function openEditHhLancamento(rowId: string) {
    if (!canWrite) return;
    setErr(null);
    setOk(null);
    setEditingId(rowId);
    setShowLancamentoForm(true);

    try {
      const ctx = await ensureDbContext();
      if (!ctx.tenant || !ctx.empresa) {
        setErr("Tenant/empresa não carregados.");
        return;
      }


      // Busca na tabela base para garantir IDs (colaborador_id, etc.) e especialidade
      const selectBase = "id,data,colaborador_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,percentual_aplicado,tem_extra_50,horas_extra_50,tem_extra_100,horas_extra_100,observacao,hh_especialidade_id,hh_servico_id";
      let data: Record<string, unknown> | null = null;
      let error: unknown = null;
      try {
        const res = await supabase.from("hh_lancamentos").select(selectBase).eq("id", rowId).maybeSingle();
        data = (res.data ?? null) as Record<string, unknown> | null;
        error = res.error;
      } catch (e) {
        data = null;
        error = e;
      }
      // Fallback para schema antigo
      if (error && isMissingColumnError(error)) {
        const res2 = await supabase.from("hh_lancamentos").select("id,data,colaborador_id,hora_entrada,hora_saida,percentual_aplicado,observacao,hh_servico_id").eq("id", rowId).maybeSingle();
        data = (res2.data ?? null) as Record<string, unknown> | null;
        error = res2.error;
      }
      if (error) throw error;
      if (!data) {
        setErr("Lançamento não encontrado.");
        return;
      }

      const percentualRaw = data.percentual_aplicado;
      const percentualStr = percentualRaw === null || percentualRaw === undefined ? "" : String(percentualRaw);
      const percentualSafe: "" | "0" | "50" | "100" =
        percentualStr === "0" || percentualStr === "50" || percentualStr === "100" ? percentualStr : "";

      setLancamentoForm({
        data: String(data.data ?? new Date().toISOString().slice(0, 10)),
        colaborador_id: String(data.colaborador_id ?? ""),
        hh_servico_id: String(data.hh_especialidade_id ?? data.hh_servico_id ?? ""),
        observacao: String(data.observacao ?? ""),
      });
      setPercentualManual(percentualSafe);
      const extra50 = Number(data.horas_extra_50 ?? 0);
      const extra100 = Number(data.horas_extra_100 ?? 0);
      setTemExtra50(Boolean(data.tem_extra_50) || extra50 > 0);
      setHorasExtra50Input(formatHorasInputBR(extra50));
      setTemExtra100(Boolean(data.tem_extra_100) || extra100 > 0);
      setHorasExtra100Input(formatHorasInputBR(extra100));

      editingOriginalKeyRef.current = {
        data: String(data.data ?? ""),
        colaborador_id: String(data.colaborador_id ?? ""),
      };

      const toStringOrNull = (v: unknown): string | null => (v === null || v === undefined ? null : String(v));

      const e1 = formatTimeHHMM(toStringOrNull(data.entrada_1)) || "";
      const s1 = formatTimeHHMM(toStringOrNull(data.saida_1)) || "";
      const e2 = formatTimeHHMM(toStringOrNull(data.entrada_2)) || "";
      const s2 = formatTimeHHMM(toStringOrNull(data.saida_2)) || "";

      // Fallback de schema antigo (hora_entrada/hora_saida) para preencher UI
      const oldE = formatTimeHHMM(toStringOrNull(data.hora_entrada)) || "";
      const oldS = formatTimeHHMM(toStringOrNull(data.hora_saida)) || "";

      // Se for schema antigo (apenas hora_entrada/hora_saida), preenche o 1º período e deixa o 2º vazio.
      const temDoisPeriodos = Boolean(e1 || s1 || e2 || s2);
      setHoraEntrada1(e1 || oldE || "07:30");
      setHoraSaida1(s1 || oldS || "12:00");
      setHoraEntrada2(temDoisPeriodos ? (e2 || "13:00") : "");
      setHoraSaida2(temDoisPeriodos ? (s2 || "17:00") : "");
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao carregar lançamento para edição.";
      setErr(message);
    }
  }

  async function excluirHhLancamento(id: string) {
    if (!canDelete) return;
    const okConfirm = confirm("Excluir este lançamento de HH?");
    if (!okConfirm) return;

    try {
      setErr(null);
      setOk(null);
      const ctx = await ensureDbContext();
      if (!ctx.tenant || !ctx.empresa) {
        setErr("Tenant/empresa não carregados.");
        return;
      }
      const tenantId = ctx.tenant;
      const empresaId = ctx.empresa;
      const del = await applyTenantEmpresa(
        supabase
          .from("hh_lancamentos")
          .delete()
          .eq("id", id)
          .eq("os_id", osId)
          .eq("empresa_id", empresaId)
          .select("id,data,colaborador_id,percentual_aplicado,observacao"),
        tenantId,
        empresaId
      );

      const deletedRow = (del.data?.[0] ?? null) as HhLancamentoSyncRow | null;
      const deletedData = String(deletedRow?.data ?? "").trim();
      const deletedColaboradorId = String(deletedRow?.colaborador_id ?? "").trim();
      const syncDeletedLancamento = async (): Promise<string | null> => {
        if (!enabled || !deletedData || !deletedColaboradorId) return null;

        try {
          const remaining = await applyTenantEmpresa(
            supabase
              .from("hh_lancamentos")
              .select("data,colaborador_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,percentual_aplicado,tem_extra_50,horas_extra_50,tem_extra_100,horas_extra_100,observacao")
              .eq("os_id", osId)
              .eq("empresa_id", empresaId)
              .eq("data", deletedData)
              .eq("colaborador_id", deletedColaboradorId)
              .order("criado_em", { ascending: false }),
            tenantId,
            empresaId
          );

          if (remaining.error) throw remaining.error;

          const remainingRows = (remaining.data ?? []) as HhLancamentoSyncRow[];
          const rowWithObservacao = remainingRows.find((row) => String(row.observacao ?? "").trim());
          const split = getSyncHorasSplit(remainingRows);

          await syncHhToApontamentos({
            supabase,
            tenantId,
            empresaId,
            osId,
            colaboradorId: deletedColaboradorId,
            dataISO: deletedData,
            periodos: buildPeriodosSyncFromHhRows(remainingRows),
            descricao: String(rowWithObservacao?.observacao ?? deletedRow?.observacao ?? "").trim() || "HH lancado na OS",
            percentual: normalizePercentualHh(
              remainingRows[0]?.percentual_aplicado ?? deletedRow?.percentual_aplicado,
              deletedData
            ),
            horasNormais: split.normais,
            horasExtra50: split.extra50,
            horasExtra100: split.extra100,
          });

          return null;
        } catch (syncErr: unknown) {
          console.error("[HH] Falha ao sincronizar apontamentos_horas apos excluir HH", syncErr);
          return getDbErrorMessage(syncErr, "Erro ao sincronizar apontamentos.");
        }
      };

      if (del.error) throw del.error;
      if (!del.data || del.data.length === 0) {
        throw new Error("Lançamento não encontrado ou sem permissão para excluir.");
      }
      setOk("Lançamento excluído.");
      const syncError = await syncDeletedLancamento();
      await loadHhLancamentos();
      await loadRelatorios();
      if (syncError) {
        setOk(null);
        setErr(`Lancamento HH excluido, mas falhou ao sincronizar apontamentos: ${syncError}`);
        return;
      }
    } catch (e: unknown) {
      const message = getDbErrorMessage(e, "Erro ao excluir lançamento.");
      if (process.env.NODE_ENV !== "production") {
        console.debug("[excluirHhLancamento] Falha ao excluir", { osId, id, error: e });
      }
      setErr(message);
    }
  }

  async function salvarLancamento(): Promise<boolean> {
    setOk(null);
    setErr(null);
    const ctx = await ensureDbContext();
    if (!ctx.tenant || !ctx.empresa || !canWrite) {
      setErr("Sem permissão ou contexto (tenant/empresa) não carregado.");
      return false;
    }

    if (!lancamentoForm.data || !lancamentoForm.colaborador_id) {
      setErr("Informe data e colaborador.");
      return false;
    }

    const entrada1 = parseHHMM(horaEntrada1);
    const saida1 = parseHHMM(horaSaida1);
    const e2Raw = String(horaEntrada2 ?? "").trim();
    const s2Raw = String(horaSaida2 ?? "").trim();
    const entrada2 = parseHHMM(e2Raw);
    const saida2 = parseHHMM(s2Raw);

    if (entrada1 === null) {
      setErr("Entrada 1 inválida (use HH:MM). Ex: 07:30");
      return false;
    }
    if (saida1 === null) {
      setErr("Saída 1 inválida (use HH:MM). Ex: 12:00");
      return false;
    }

    // Validar períodos
    if (entrada1 >= saida1) {
      setErr("Entrada 1 deve ser menor que Saída 1.");
      return false;
    }
    const usandoSegundoPeriodo = Boolean(e2Raw) || Boolean(s2Raw);
    const usandoDoisPeriodos = Boolean(e2Raw) && Boolean(s2Raw);

    if (usandoSegundoPeriodo && !usandoDoisPeriodos) {
      setErr("Preencha Entrada 2 e Saída 2 ou deixe ambos em branco.");
      return false;
    }

    if (usandoDoisPeriodos) {
      if (entrada2 === null) {
        setErr("Entrada 2 inválida (use HH:MM). Ex: 13:00");
        return false;
      }
      if (saida2 === null) {
        setErr("Saída 2 inválida (use HH:MM). Ex: 17:00");
        return false;
      }
      if (entrada2 >= saida2) {
        setErr("Entrada 2 deve ser menor que Saída 2.");
        return false;
      }
      if (saida1 > entrada2) {
        setErr("Saída 1 deve ser menor ou igual a Entrada 2 (sem sobreposição).");
        return false;
      }
    }

    // Converter minutos para HH:MM para payload
    const minutosParaHHMM = (minutos: number): string => {
      const hh = Math.floor(minutos / 60);
      const mm = minutos % 60;
      return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    };

    const calcHorasDecimal = (inicioMin: number, fimMin: number): number => calcHorasDecimalFromMinutes(inicioMin, fimMin);

    if (especialidadesOptions.length > 0 && !String(lancamentoForm.hh_servico_id ?? "").trim()) {
      setErr("Selecione a especialidade.");
      return false;
    }
    if (especialidadesOptions.length === 0) {
      setErr("Nenhuma especialidade vinculada a este colaborador.");
      return false;
    }

    setLancamentoBusy(true);
    setErr(null);
    try {
      const descRaw = String(lancamentoForm.observacao ?? "").trim();
      const hhServicoId = String(lancamentoForm.hh_servico_id ?? "").trim();
      // DEBUG LOG: Mostrar exatamente o que foi recebido
      console.warn("[salvarLancamento] VALIDAÇÃO DE ENTRADA:", {
        timestamp: new Date().toISOString(),
        colaborador_id: lancamentoForm.colaborador_id,
        data: lancamentoForm.data,
        hh_servico_id_form: lancamentoForm.hh_servico_id,
        hh_servico_id_string: hhServicoId,
        especialidadesOptionosCount: especialidadesOptions.length,
        opcoesDisponiveis: especialidadesOptions.map((opt) => ({
          id: opt.id,
          descricao: opt.descricao,
        })),
      });
      // Validação: hh_servico_id pode ser UUID ou número (bigint)
      if (!hhServicoId) {
        setErr("Especialidade inválida.");
        return false;
      }
      
      // Aceitar UUID (36 chars com hífen) OU número
      const isUUID = hhServicoId.length >= 32 && hhServicoId.includes("-");
      const isNumeric = /^\d+$/.test(hhServicoId);
      
      if (!isUUID && !isNumeric) {
        setErr("Especialidade inválida (formato incorreto).");
        return false;
      }

      // Validação prática: serviço HH precisa existir/estar ativo.
      try {
        const svcBase = supabase.from("cliente_hh_servicos").select("id,ativo").eq("id", hhServicoId);
        const svcQ = ctx.empresa ? applyTenantEmpresa(svcBase, ctx.tenant, ctx.empresa) : applyTenant(svcBase, ctx.tenant);
        const { data: svcData, error: svcErr } = await svcQ.maybeSingle();
        if (svcErr) throw svcErr;
        if (!svcData) {
          setErr("Especialidade (serviço HH) não encontrada.");
          return false;
        }
      } catch (svcE) {
        console.warn("Falha ao validar serviço HH:", svcE);
      }

      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      // VALIDAÇÃO CRÍTICA: Verificar se o colaborador tem vínculo com este serviço neste cliente
      if (!clienteIdContext) {
        setErr("Cliente não identificado na OS. Não é possível lançar horas.");
        setLancamentoBusy(false);
        return false;
      }

      // hhServicoId já foi validado acima (UUID ou numérico), não precisa validar novamente
      if (!hhServicoId) {
        setErr("Serviço HH inválido ou não selecionado.");
        setLancamentoBusy(false);
        return false;
      }

      if (!lancamentoForm.colaborador_id) {
        setErr("Colaborador não selecionado.");
        setLancamentoBusy(false);
        return false;
      }

      console.warn("[salvarLancamento] PRÉ-VALIDAÇÃO:", {
        colaborador_id: lancamentoForm.colaborador_id,
        hh_servico_id_string: hhServicoId,
        hh_servico_id_number: Number(hhServicoId),
        cliente_id: clienteIdContext,
        especialidadesOptions: especialidadesOptions.map(e => ({ id: e.id, descricao: e.descricao })),
        vinculoEspecialidadesRef: vinculoEspecialidadesRef.current.get(lancamentoForm.colaborador_id),
      });

      // VALIDAÇÃO EXTRA: Verificar se o serviço selecionado está nos vínculos carregados
      const servicosVinculados = vinculoEspecialidadesRef.current.get(lancamentoForm.colaborador_id) ?? [];
      if (servicosVinculados.length === 0) {
        setErr("Colaborador não possui serviços HH vinculados. Verifique o cadastro de vínculos.");
        setLancamentoBusy(false);
        return false;
      }
      
      if (!servicosVinculados.includes(String(hhServicoId))) {
        console.error("[salvarLancamento] ERRO DE VÍNCULO:", {
          servicoSelecionado: hhServicoId,
          servicosVinculados: servicosVinculados,
          colaborador: lancamentoForm.colaborador_id,
        });
        setErr(`Serviço HH ${hhServicoId} não está vinculado ao colaborador. Serviços disponíveis: ${servicosVinculados.join(', ')}`);
        setLancamentoBusy(false);
        return false;
      }

      console.warn("[salvarLancamento] VALIDANDO vínculo:", {
        tenant_id: ctx.tenant,
        cliente_id: clienteIdContext,
        colaborador_id: lancamentoForm.colaborador_id,
        hh_servico_id: hhServicoId,
      });

      // 1. Verificar se o vínculo existe na tabela colaborador_cliente_funcao
      const { data: vinculoExistente, error: checkVinculoErr } = await applyTenantEmpresa(
        supabase
          .from("colaborador_cliente_funcao")
          .select("id,ativo")
          .eq("cliente_id", clienteIdContext)
          .eq("colaborador_id", lancamentoForm.colaborador_id)
          .eq("hh_servico_id", hhServicoId)
          .maybeSingle(),
        ctx.tenant,
        ctx.empresa
      );

      if (checkVinculoErr) {
        console.error("[salvarLancamento] Erro ao validar vínculo:", checkVinculoErr);
        setErr(`Erro ao validar vínculo: ${checkVinculoErr.message}`);
        setLancamentoBusy(false);
        return false;
      }

      // 2. Se não existe, bloquear e exibir erro (NÃO criar automático)
      if (!vinculoExistente) {
        setErr("Colaborador não possui vínculo ativo com este serviço neste cliente. Cadastre o vínculo antes de lançar HH.");
        setLancamentoBusy(false);
        return false;
      }
      if (vinculoExistente && !vinculoExistente.ativo) {
        setErr("Vínculo do colaborador com este serviço está inativo. Ative o vínculo antes de lançar HH.");
        setLancamentoBusy(false);
        return false;
      }

      const percentual = (percentualManual ? Number(percentualManual) : getPercentualFromDate(lancamentoForm.data)) as 0 | 50 | 100;

      // Carregar os preços diretos de cliente_hh_servicos para usar na gravação
      const { data: svcData, error: svcErr } = await supabase
        .from("cliente_hh_servicos")
        .select("preco_base,preco_50,preco_100")
        .eq("id", hhServicoId)
        .maybeSingle();

      if (svcErr || !svcData) {
        setErr("Serviço HH não encontrado ou sem preços configurados.");
        setLancamentoBusy(false);
        return false;
      }

      // Usar o preço correto baseado no percentual
      const preco_base = Number(svcData.preco_base ?? 0);
      const valorHoraAplicado = preco_base;

      // Resolve mapping correto para hh_tipo_id
      const hhTipoMappingId = await resolveHhTipoMappingId(supabase, ctx.tenant, percentual);
      console.warn("[salvarLancamento] mappingId/hh_tipo_id:", hhTipoMappingId, "servicoId:", hhServicoId);
      
      // Monta payload (hh_lancamentos tem hh_tipo_id + hh_servico_id)
      const usaDoisPeriodos = usandoDoisPeriodos && entrada2 !== null && saida2 !== null;
      const horasManual = usaDoisPeriodos
        ? Number((calcHorasDecimal(entrada1, saida1) + calcHorasDecimal(entrada2!, saida2!)).toFixed(2))
        : calcHorasDecimal(entrada1, saida1);
      const horasExtra50 = temExtra50 ? parseHorasInputBR(horasExtra50Input) : 0;
      const horasExtra100 = temExtra100 ? parseHorasInputBR(horasExtra100Input) : 0;

      if (horasExtra50 === null) {
        setErr("Horas extra 50% inválidas. Use decimal (1,50) ou HH:MM (1:30).");
        setLancamentoBusy(false);
        return false;
      }
      if (horasExtra100 === null) {
        setErr("Horas extra 100% inválidas. Use decimal (1,50) ou HH:MM (1:30).");
        setLancamentoBusy(false);
        return false;
      }
      if (temExtra50 && horasExtra50 <= 0) {
        setErr("Informe a quantidade de horas extra 50%.");
        setLancamentoBusy(false);
        return false;
      }
      if (temExtra100 && horasExtra100 <= 0) {
        setErr("Informe a quantidade de horas extra 100%.");
        setLancamentoBusy(false);
        return false;
      }
      if (Number((horasExtra50 + horasExtra100).toFixed(2)) > horasManual) {
        setErr("Horas extras não podem exceder o total de horas do lançamento.");
        setLancamentoBusy(false);
        return false;
      }

      const horasNormais = normalizeHorasNumber(horasManual - horasExtra50 - horasExtra100);
      const payloadHH: Record<string, unknown> = {
        tenant_id: ctx.tenant,
        empresa_id: ctx.empresa,
        os_id: osId,
        colaborador_id: lancamentoForm.colaborador_id,
        hh_tipo_id: hhTipoMappingId,
        hh_servico_id: Number(hhServicoId), // ID do serviço específico do cliente
        data: lancamentoForm.data,
        // IMPORTANTE: o trigger do banco exige ou 2 períodos completos ou nenhum.
        // Para dias parciais (sem 2º período), salvamos via hora_entrada/hora_saida + horas_trabalhadas.
        entrada_1: usaDoisPeriodos ? minutosParaHHMM(entrada1) : null,
        saida_1: usaDoisPeriodos ? minutosParaHHMM(saida1) : null,
        entrada_2: usaDoisPeriodos ? minutosParaHHMM(entrada2!) : null,
        saida_2: usaDoisPeriodos ? minutosParaHHMM(saida2!) : null,
        hora_entrada: minutosParaHHMM(entrada1),
        hora_saida: usaDoisPeriodos ? minutosParaHHMM(saida2!) : minutosParaHHMM(saida1),
        horas_trabalhadas: horasManual,
        percentual_aplicado: percentual,
        tem_extra_50: temExtra50 && horasExtra50 > 0,
        horas_extra_50: horasExtra50,
        tem_extra_100: temExtra100 && horasExtra100 > 0,
        horas_extra_100: horasExtra100,
        observacao: descRaw || null,
        valor_hora: valorHoraAplicado,
        criado_por: userEmail,
      };

      console.warn("[HH_SAVE_PAYLOAD] ANTES DE GRAVAR:", {
        payloadHH,
        vinculoDeveTerNoClienteId: clienteIdContext,
        colaboradorId: lancamentoForm.colaborador_id,
        hhServicoIdEnviado: Number(hhServicoId),
        especialidadesOpcoesIds: especialidadesOptions.map(e => e.id),
      });

      console.warn("[HH_SAVE_PAYLOAD] Payload a ser enviado:", payloadHH);

      if (editingId) {
        // UPDATE
        const { error } = await supabase
          .from("hh_lancamentos")
          .update(payloadHH)
          .eq("id", editingId)
          .eq("tenant_id", ctx.tenant);
        if (error) throw error;
        setOk("Lançamento HH atualizado!");
      } else {
        // INSERT
        const { error } = await supabase
          .from("hh_lancamentos")
          .insert(payloadHH);
        if (error) throw error;
        setOk("Lançamento HH salvo com sucesso!");
      }

      // Sincronizar com apontamentos_horas se habilitado
      if (enabled) {
        try {
          const baseDate = lancamentoForm.data;
          const colabId = String(lancamentoForm.colaborador_id);

          // Se mudou colaborador/data durante a edição, apagar possíveis lançamentos antigos (D e D+1).
          if (editingId && editingOriginalKeyRef.current) {
            const prevKey = editingOriginalKeyRef.current;
            if (prevKey.data && prevKey.colaborador_id && (prevKey.data !== baseDate || prevKey.colaborador_id !== colabId)) {
              await syncHhToApontamentos({
                supabase,
                tenantId: ctx.tenant,
                empresaId: ctx.empresa,
                osId,
                colaboradorId: prevKey.colaborador_id,
                dataISO: prevKey.data,
                periodos: [],
                percentual,
              });
            }
          }

          const periodosSync: Array<{ entrada: string; saida: string }> = [
            { entrada: minutosParaHHMM(entrada1), saida: minutosParaHHMM(saida1) },
          ];
          if (usaDoisPeriodos) {
            periodosSync.push({ entrada: minutosParaHHMM(entrada2!), saida: minutosParaHHMM(saida2!) });
          }

          await syncHhToApontamentos({
            supabase,
            tenantId: ctx.tenant,
            empresaId: ctx.empresa,
            osId,
            colaboradorId: colabId,
            dataISO: baseDate,
            periodos: periodosSync,
            descricao: descRaw || "HH lançado na OS",
            percentual,
            horasNormais,
            horasExtra50,
            horasExtra100,
          });
        } catch (syncErr: unknown) {
          console.error("[HH] Falha ao sincronizar apontamentos_horas (gerado_por_hh)", syncErr);
          const msg = getDbErrorMessage(syncErr, "Erro ao sincronizar apontamentos.");
          setErr(`Lançamento HH salvo, mas falhou ao sincronizar apontamentos: ${msg}`);
        }
      }

      await loadHhLancamentos();
      await loadRelatorios();
      return true;
    } catch (e: unknown) {
      const errorMsg = e instanceof Error ? e.message : JSON.stringify(e);
      // Corrigido: não usar colabId fora do escopo try/catch
      console.error("Erro ao salvar lançamento HH:", errorMsg, {
        osId,
        editingId,
        payload: {
          colaborador_id: lancamentoForm.colaborador_id,
          data: lancamentoForm.data,
          hora_entrada: horaEntrada1,
          hora_saida: horaSaida2,
          entrada_1: horaEntrada1,
          saida_1: horaSaida1,
          hh_servico_id: lancamentoForm.hh_servico_id,
        },
      });
      setErr(formatSupabaseError(e));
      return false;
    } finally {
      setLancamentoBusy(false);
    }
  }

  async function submitAndAdvance(): Promise<void> {
    if (lancamentoBusy) return;
    if (lancamentoSubmitLockRef.current) return;
    lancamentoSubmitLockRef.current = true;
    try {
      const okSave = await salvarLancamento();
      if (!okSave) return;

      setErr(null);

      if (editingId) {
        closeLancamentoForm();
        return;
      }

      setLancamentoForm((prev) => {
        const nextDate = addOneDayISO(prev.data);
        return {
          ...prev,
          data: nextDate,
        };
      });
      setTimeout(() => {
        lancamentoDateRef.current?.focus();
      }, 0);
    } finally {
      lancamentoSubmitLockRef.current = false;
    }
  }

  function handleLancamentoKeyDownCapture(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== "Enter") return;
    if (e.shiftKey || e.altKey || e.metaKey || e.ctrlKey) return;
    if (lancamentoBusy) return;

    const target = e.target as HTMLElement | null;
    if (target?.tagName === "TEXTAREA") return;

    e.preventDefault();
    e.stopPropagation();
    void submitAndAdvance();
  }

  // DEPRECATED: geração de relatório via RPC removida.
  // Mantido apenas o fluxo de lançamento HH + exportação em PDF.

  useEffect(() => {
    void loadRelatorios();
    void loadHhLancamentos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, osId, osDetail?.cliente_id]);

  // Quando abre formulário ou muda a data: carregar tabela e colaboradores
  useEffect(() => {
    if (!showLancamentoForm) return;
    if (!clienteIdContext) {
      console.warn("[useEffect] cliente_id não disponível");
      setTabelaAtiva(null);
      setColaboradores([]);
      return;
    }

    const run = async () => {
      console.log("[useEffect] Carregando contexto HH para data:", lancamentoForm.data);
      
      // 1. Carregar tabela ativa para a data
      const tabela = await loadTabelaAtiva(clienteIdContext, lancamentoForm.data);
      setTabelaAtiva(tabela);
      
      if (!tabela) {
        console.warn("[useEffect] Tabela HH não encontrada para cliente:", clienteIdContext);
        setColaboradores([]);
        setEspecialidadesOptions([]);
        setEspecialidadeLocked(false);
        return;
      }
      
      // 2. Carregar colaboradores vinculados ao cliente
      await loadColaboradores(clienteIdContext);
    };

    void run();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showLancamentoForm, lancamentoForm.data, clienteIdContext]);

  // Quando colaborador muda: carregar especialidades vinculadas
  useEffect(() => {
    if (!showLancamentoForm) return;
    if (!tabelaAtiva?.id) {
      console.warn("[useEffect] Tabela HH não está ativa");
      return;
    }
    if (!clienteIdContext) {
      console.warn("[useEffect] cliente_id não disponível");
      return;
    }
    
    const colabId = String(lancamentoForm.colaborador_id ?? "").trim();
    if (!colabId) {
      setEspecialidadesOptions([]);
      setEspecialidadeLocked(false);
      setLancamentoForm((prev) => ({ ...prev, hh_servico_id: "" }));
      return;
    }

    void loadEspecialidadesParaColaborador(clienteIdContext, colabId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showLancamentoForm, tabelaAtiva?.id, lancamentoForm.colaborador_id, clienteIdContext]);

  if (!ready && permissionsLoading) {
    return (
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 text-sm text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  if (!canRead) return null;

  return (
    <>
      <section className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold">Relatório HH</h2>
          <p className="text-sm text-zinc-400">
            Geração e consulta do relatório de horas da OS.{" "}
            <a
              href="/cadastros/hh/servicos-cliente"
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-400 hover:underline text-xs"
            >
              Cadastrar serviços →
            </a>
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => void loadHhLancamentos()}
            disabled={loadingHh}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            {loadingHh ? "Atualizando..." : "Atualizar"}
          </button>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      {showHhStatusWarning && (
        <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
          OS precisa estar EM ANDAMENTO para lançar HH.
        </div>
      )}

      {canShowNovoLancamento && !clienteIdContext && (
        <div className="text-sm text-red-400">Cliente não identificado na OS.</div>
      )}

      {/* Botão Novo lançamento HH */}
      {canShowNovoLancamento && clienteIdContext && !showLancamentoForm && (
        <button
          type="button"
          className="px-3 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
          onClick={() => {
            setEditingId(null);
            editingOriginalKeyRef.current = null;
            setLancamentoForm({
              data: new Date().toISOString().slice(0, 10),
              colaborador_id: "",
              hh_servico_id: "",
              observacao: "",
            });
            setHoraEntrada1("07:30");
            setHoraSaida1("12:00");
            setHoraEntrada2("13:00");
            setHoraSaida2("17:00");
            setTemExtra50(false);
            setHorasExtra50Input("");
            setTemExtra100(false);
            setHorasExtra100Input("");
            setPrecoServicoSelecionado(null);
            setEspecialidadesOptions([]);
            setEspecialidadeLocked(false);
            setShowLancamentoForm(true);
            setErr(null);
            setOk(null);
          }}
        >
          Novo lançamento HH
        </button>
      )}

      {/* Formulário de Lançamento */}
      {showLancamentoForm && (
        <div
          className="border border-zinc-800 rounded-lg p-4 bg-zinc-900/40 space-y-3"
          onKeyDownCapture={handleLancamentoKeyDownCapture}
        >
          <div className="flex items-center justify-between">
            <h3 className="font-semibold">{editingId ? "Editar Lançamento HH" : "Novo Lançamento HH"}</h3>
            <button
              onClick={closeLancamentoForm}
              className="text-zinc-400 hover:text-zinc-200"
            >
              ✕
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Colaborador *</label>
              <select
                aria-label="Selecionar colaborador"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.colaborador_id}
                onChange={(e) => {
                  const colaboradorId = e.target.value;
                  setLancamentoForm((prev) => ({ ...prev, colaborador_id: colaboradorId }));
                  
                  // Auto-carregar especialidades e selecionar baseado no tipo de dia
                  if (colaboradorId && clienteIdContext) {
                    void loadEspecialidadesParaColaborador(clienteIdContext, colaboradorId);
                  } else {
                    setEspecialidadesOptions([]);
                    setEspecialidadeLocked(false);
                  }
                }}
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
              <label className="text-xs text-zinc-400">Tipo HH <span className="text-[10px] text-zinc-500">(editável)</span></label>
              <select
                aria-label="Tipo HH"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-300"
                value={percentualManual}
                onChange={e => {
                  setPercentualManual(e.target.value as "" | "0" | "50" | "100");
                  
                  // Re-selecionar serviço baseado no novo percentual manual
                  if (lancamentoForm.colaborador_id && clienteIdContext && especialidadesOptions.length > 1) {
                    void loadEspecialidadesParaColaborador(clienteIdContext, lancamentoForm.colaborador_id);
                  }
                }}
              >
                <option value="">Automático ({getTipoHHLabel(getPercentualFromDate(lancamentoForm.data))})</option>
                <option value="0">Normal (0%)</option>
                <option value="50">Extra 50%</option>
                <option value="100">Extra 100%</option>
              </select>
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Data *</label>
              <input
                type="date"
                aria-label="Data do lançamento"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                ref={lancamentoDateRef}
                value={lancamentoForm.data}
                onChange={(e) => {
                  const nextDate = e.target.value;
                  setLancamentoForm((prev) => ({
                    ...prev,
                    data: nextDate,
                  }));
                  
                  // Re-selecionar serviço baseado no novo tipo de dia
                  if (lancamentoForm.colaborador_id && clienteIdContext && especialidadesOptions.length > 1) {
                    void loadEspecialidadesParaColaborador(clienteIdContext, lancamentoForm.colaborador_id);
                  }
                }}
              />
              <div className="text-[11px] text-zinc-500">
                {(() => {
                  const p = getPercentualFromDate(lancamentoForm.data);
                  if (p === 50) return "Sábado (50%)";
                  if (p === 100) return "Domingo (100%)";
                  return "Dias de semana (0%)";
                })()}
              </div>
            </div>

            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Especialidade</label>
              <select
                aria-label="Selecionar especialidade"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={lancamentoForm.hh_servico_id}
                onChange={(e) => {
                  const servicoId = e.target.value;
                  console.warn("[dropdown onChange] Seleção de serviço HH:", {
                    servicoId_string: servicoId,
                    servicoId_number: servicoId ? Number(servicoId) : null,
                    isValid: servicoId && /^\d+$/.test(servicoId),
                    optionsCount: especialidadesOptions.length,
                    opcoesValidas: especialidadesOptions.map((o) => ({ id: String(o.id), descricao: o.descricao })),
                  });

                  setLancamentoForm((prev) => ({ ...prev, hh_servico_id: servicoId }));
                  
                  // Carregar preços do serviço selecionado
                  if (servicoId && /^\d+$/.test(servicoId)) {
                    const servicoIdNum = Number(servicoId);
                    const servicoData = especialidadesOptions.find((opt) => String(opt.id) === servicoId);
                    
                    console.warn("[dropdown onChange] Validação do serviço:", {
                      servicoIdNum,
                      encontradoEmOptions: Boolean(servicoData),
                      descricao: servicoData?.descricao,
                    });

                    // Se não temos os preços já carregados no option, fazer uma query direta
                    if (servicoData) {
                      // Tentar buscar os preços diretamente se disponível
                      (async () => {
                        try {
                          const ctx = await ensureDbContext();
                          if (!ctx.tenant) {
                            console.warn("[dropdown onChange] Tenant não carregado");
                            return;
                          }
                          
                          console.warn("[dropdown onChange] Consultando preços de serviço HH:", {
                            servicoId: servicoIdNum,
                            tenant_id: ctx.tenant,
                          });

                          const { data, error } = await applyTenant(
                            supabase
                              .from("cliente_hh_servicos")
                              .select("id,preco_base,preco_50,preco_100")
                              .eq("id", servicoIdNum),  // ← CORRIGIDO: usar number
                            ctx.tenant
                          );
                          
                          if (error) {
                            console.warn("[dropdown onChange] Erro ao carregar preços:", error);
                            return;
                          }

                          if (data && data.length > 0) {
                            const row = (data[0] ?? null) as {
                              id: string | number;
                              preco_base?: number | null;
                              preco_50?: number | null;
                              preco_100?: number | null;
                            } | null;
                            if (!row) return;
                            console.warn("[dropdown onChange] Preços carregados:", {
                              id: row.id,
                              preco_base: row.preco_base,
                              preco_50: row.preco_50,
                              preco_100: row.preco_100,
                            });
                            
                            setPrecoServicoSelecionado({
                              preco_base: Number(row.preco_base ?? 0),
                              preco_50: Number(row.preco_50 ?? 0),
                              preco_100: Number(row.preco_100 ?? 0),
                            });
                          } else {
                            console.warn("[dropdown onChange] Nenhum serviço encontrado com id:", servicoIdNum);
                          }
                        } catch (e) {
                          console.error("[dropdown onChange] Erro inesperado:", e);
                        }
                      })();
                    }
                  } else {
                    setPrecoServicoSelecionado(null);
                  }
                }}
                disabled={especialidadeLocked}
              >
                {especialidadesOptions.length === 0 && <option value="">(Sem)</option>}
                {especialidadesOptions.map((esp) => (
                  <option key={esp.id} value={esp.id}>
                    {esp.descricao ?? esp.id}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {precoServicoSelecionado && !hideEspecialidadeValores && (
            <div className="bg-zinc-900/60 border border-zinc-700 rounded-lg p-4 space-y-2">
              <div className="text-xs font-semibold text-zinc-300 uppercase">Valores de hora para esta especialidade:</div>
              <div className="grid grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-[11px] text-zinc-400">Normal (0%)</div>
                  <div className="text-sm font-medium text-emerald-300">
                    R$ {Number(precoServicoSelecionado.preco_base).toFixed(2).replace(".", ",")}
                  </div>
                </div>
                <div className="space-y-1">
                  <div className="text-[11px] text-zinc-400">Extra 50%</div>
                  <div className="text-sm font-medium text-amber-300">
                    R$ {Number(precoServicoSelecionado.preco_50).toFixed(2).replace(".", ",")}
                  </div>
                </div>
                <div className="space-y-1">
                  <div className="text-[11px] text-zinc-400">Extra 100%</div>
                  <div className="text-sm font-medium text-red-300">
                    R$ {Number(precoServicoSelecionado.preco_100).toFixed(2).replace(".", ",")}
                  </div>
                </div>
              </div>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <label className="rounded-lg border border-zinc-700 bg-zinc-900/60 p-3">
              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  aria-label="Marcar hora extra 50%"
                  className="h-4 w-4 accent-emerald-300"
                  checked={temExtra50}
                  onChange={(e) => {
                    const checked = e.target.checked;
                    setTemExtra50(checked);
                    if (!checked) setHorasExtra50Input("");
                  }}
                />
                <span className="text-sm font-medium text-zinc-100">Hora extra 50%</span>
              </div>
              <input
                type="text"
                aria-label="Quantidade de horas extra 50%"
                inputMode="decimal"
                className="mt-2 w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 disabled:opacity-50"
                value={horasExtra50Input}
                onChange={(e) => setHorasExtra50Input(e.target.value)}
                disabled={!temExtra50}
                placeholder="1,50"
              />
            </label>

            <label className="rounded-lg border border-zinc-700 bg-zinc-900/60 p-3">
              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  aria-label="Marcar hora extra 100%"
                  className="h-4 w-4 accent-emerald-300"
                  checked={temExtra100}
                  onChange={(e) => {
                    const checked = e.target.checked;
                    setTemExtra100(checked);
                    if (!checked) setHorasExtra100Input("");
                  }}
                />
                <span className="text-sm font-medium text-zinc-100">Hora extra 100%</span>
              </div>
              <input
                type="text"
                aria-label="Quantidade de horas extra 100%"
                inputMode="decimal"
                className="mt-2 w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 disabled:opacity-50"
                value={horasExtra100Input}
                onChange={(e) => setHorasExtra100Input(e.target.value)}
                disabled={!temExtra100}
                placeholder="1,50"
              />
            </label>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Entrada 1 *</label>
              <input
                type="time"
                aria-label="Entrada 1"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaEntrada1}
                onChange={(e) => setHoraEntrada1(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Saída 1 *</label>
              <input
                type="time"
                aria-label="Saída 1"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaSaida1}
                onChange={(e) => setHoraSaida1(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Entrada 2 <span className="text-[10px] text-zinc-500">(opcional)</span></label>
              <input
                type="time"
                aria-label="Entrada 2"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaEntrada2}
                onChange={(e) => setHoraEntrada2(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs text-zinc-400">Saída 2 <span className="text-[10px] text-zinc-500">(opcional)</span></label>
              <input
                type="time"
                aria-label="Saída 2"
                className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                value={horaSaida2}
                onChange={(e) => setHoraSaida2(e.target.value)}
              />
            </div>
          </div>

          <div className="flex items-end justify-end">
            <button
              onClick={submitAndAdvance}
              disabled={lancamentoBusy}
              className="px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium disabled:opacity-60"
            >
              {lancamentoBusy ? "Salvando..." : editingId ? "Salvar alterações" : "Salvar"}
            </button>
          </div>

          <div className="space-y-1">
            <label className="text-xs text-zinc-400">Observação</label>
            <textarea
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm min-h-[60px]"
              value={lancamentoForm.observacao}
              onChange={(e) =>
                setLancamentoForm((prev) => ({ ...prev, observacao: e.target.value }))
              }
              onKeyDown={(e) => {
                // Enter deve quebrar linha no textarea.
                // Opcional: Ctrl+Enter salva.
                if (e.key !== "Enter") return;
                if (lancamentoBusy) return;
                if (e.ctrlKey || e.metaKey) {
                  e.preventDefault();
                  e.stopPropagation();
                  void submitAndAdvance();
                }
              }}
              placeholder="Observações opcionais..."
            />
          </div>
        </div>
      )}

      {/* Tabela: lançamentos HH (cobrança) desta OS */}
      <div className="flex items-center justify-between gap-3 mb-3">
        <div>
          <h3 className="text-lg font-semibold">Lançamentos HH</h3>
          <p className="text-xs text-zinc-400 mt-0.5">{hhRows.length} registro(s)</p>
        </div>
        {!loadingHh && !hhErr && hhRows.length > 0 && (
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => window.print()}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 font-medium"
            >
              Imprimir
            </button>
            <button
              type="button"
              onClick={() =>
                void gerarRelatorioPDF(hhRows, osId, {
                  empresaNome: printHeader.empresaNome,
                  clienteNome: printHeader.clienteNome,
                  numeroOS: printHeader.numeroOS,
                  osDescricao: printHeader.osDescricao,
                  periodoLabel: printHeader.periodoLabel,
                  emissaoLabel: printHeader.emissaoLabel,
                })
              }
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              Exportar PDF
            </button>
          </div>
        )}
      </div>
      
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[1180px]">
            <thead className="bg-zinc-900/60">
              <tr className="text-left text-zinc-200">
                <th className="px-3 py-2">Data</th>
                <th className="px-3 py-2">Colaborador</th>
                <th className="px-3 py-2">Entrada 1</th>
                <th className="px-3 py-2">Saída 1</th>
                <th className="px-3 py-2">Entrada 2</th>
                <th className="px-3 py-2">Saída 2</th>
                <th className="px-3 py-2 text-right">Horas</th>
                <th className="px-3 py-2 text-right">Normais</th>
                <th className="px-3 py-2 text-right">Extra 50%</th>
                <th className="px-3 py-2 text-right">Extra 100%</th>
                <th className="px-3 py-2 text-right">Ações</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {loadingHh && (
                <tr>
                  <td colSpan={11} className="px-3 py-6 text-zinc-400">
                    Carregando lançamentos HH...
                  </td>
                </tr>
              )}

              {!loadingHh && hhErr && (
                <tr>
                  <td colSpan={11} className="px-3 py-6 text-red-400">
                    {hhErr}
                  </td>
                </tr>
              )}

              {!loadingHh && !hhErr && hhRows.length === 0 && (
                <tr>
                  <td colSpan={11} className="px-3 py-6 text-zinc-400">
                    Nenhum lançamento HH ainda.
                  </td>
                </tr>
              )}

              {!loadingHh && !hhErr &&
                hhRows.map((r) => {
                  const canEditRow = canWrite;
                  const canDeleteRow = canDelete;
                  const idStr = String(r.id);
                  const horas = getHorasTrabalhadasEfetivas(r);
                  const split = getHorasSplitEfetivo(r, horas);
                  return (
                    <tr key={idStr} className="hover:bg-zinc-900/40">
                      <td className="px-3 py-2 text-zinc-300 whitespace-nowrap">{formatDateBR(r.data)}</td>
                      <td className="px-3 py-2 text-zinc-200">
                        <div className="font-medium">{r.colaborador_nome ?? "—"}</div>
                        {r.observacao ? <div className="text-xs text-zinc-500 truncate max-w-[260px]">{r.observacao}</div> : null}
                      </td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.entrada_1) || formatTimeHHMM(r.hora_entrada) || "—"}</td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.saida_1) || formatTimeHHMM(r.hora_saida) || "—"}</td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.entrada_2) || "—"}</td>
                      <td className="px-3 py-2 text-zinc-300 tabular-nums">{formatTimeHHMM(r.saida_2) || "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-zinc-200">{formatHoursBR(horas)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-zinc-300">{formatHoursBR(split.normais)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-amber-200">{formatHoursBR(split.extra50)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-red-200">{formatHoursBR(split.extra100)}</td>
                      <td className="px-3 py-2 text-right whitespace-nowrap">
                        <div className="inline-flex items-center gap-2">
                          <button
                            type="button"
                            onClick={() => void openEditHhLancamento(idStr)}
                            disabled={!canEditRow}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
                          >
                            Editar
                          </button>
                          <button
                            type="button"
                            onClick={() => void excluirHhLancamento(idStr)}
                            disabled={!canDeleteRow}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
                          >
                            Excluir
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
            </tbody>
          </table>
        </div>
      </div>
      </section>

      {/* Print-only layout: impressão profissional (A4 paisagem) */}
      <div className="hh-print-only" aria-hidden="true">
        <div className="hh-print">
          <div className="hh-print__header">
            <div className="hh-print__brand">
              <NextImage className="hh-print__logo" src="/Segau2.png" alt="Logo" width={160} height={64} />
              <div className="hh-print__brandText">
                <div className="hh-print__empresa">{printHeader.empresaNome}</div>
                <div className="hh-print__cliente">Cliente: {printHeader.clienteNome}</div>
              </div>
            </div>

              <div className="hh-print__title">
                <div className="hh-print__titleMain">Relatório de Horas Lançadas</div>
                <div className="hh-print__titleSub">
                  OS {printHeader.numeroOS}
                  {printHeader.osDescricao ? ` - ${printHeader.osDescricao}` : ""}
                </div>
              </div>

            <div className="hh-print__meta">
              <div>
                <span>Emissão</span>
                <strong>{printHeader.emissaoLabel}</strong>
              </div>
              <div>
                <span>Período</span>
                <strong>{printHeader.periodoLabel}</strong>
              </div>
              <div>
                <span>Registros</span>
                <strong>{hhRows.length}</strong>
              </div>
            </div>
          </div>

          <table className="hh-print__table">
            <thead>
              <tr>
                <th>Funcionário</th>
                <th>Função</th>
                <th>Data</th>
                <th>Ent. 1</th>
                <th>Saída 1</th>
                <th>Ent. 2</th>
                <th>Saída 2</th>
                <th className="num">Horas</th>
                <th className="num">Normais</th>
                <th className="num">Extra 50%</th>
                <th className="num">Extra 100%</th>
                <th>Tipo</th>
                <th className="num">V. Hora</th>
                <th className="num">V. Hora 50%</th>
                <th className="num">V. Hora 100%</th>
                <th className="num">R$ Total</th>
              </tr>
            </thead>
            <tbody>
              {hhRows.map((r) => {
                const valorHoraNormal = Number(r.valor_hora ?? 0);
                const valorHora50 = valorHoraNormal * 1.5;
                const valorHora100 = valorHoraNormal * 2.0;
                const horas = getHorasTrabalhadasEfetivas(r);
                const split = getHorasSplitEfetivo(r, horas);
                const tipo = getTipoHHLabelFromSplit(r, horas);
                const total = getValorTotalEfetivo(r, horas);
                return (
                  <tr key={String(r.id)}>
                    <td>{r.colaborador_nome ?? "—"}</td>
                    <td>{r.especialidade_descricao && r.especialidade_descricao.trim() ? r.especialidade_descricao : "—"}</td>
                    <td className="center">{formatDateBR(r.data)}</td>
                    <td className="center">{formatTimeHHMM(r.entrada_1) || formatTimeHHMM(r.hora_entrada) || "—"}</td>
                    <td className="center">{formatTimeHHMM(r.saida_1) || formatTimeHHMM(r.hora_saida) || "—"}</td>
                    <td className="center">{formatTimeHHMM(r.entrada_2) || "—"}</td>
                    <td className="center">{formatTimeHHMM(r.saida_2) || "—"}</td>
                    <td className="num">{formatHoursBR(horas)}</td>
                    <td className="num">{formatHoursBR(split.normais)}</td>
                    <td className="num">{formatHoursBR(split.extra50)}</td>
                    <td className="num">{formatHoursBR(split.extra100)}</td>
                    <td>{tipo}</td>
                    <td className="num">{formatCurrencyBRL(valorHoraNormal)}</td>
                    <td className="num">{formatCurrencyBRL(valorHora50)}</td>
                    <td className="num">{formatCurrencyBRL(valorHora100)}</td>
                    <td className="num">{formatCurrencyBRL(total)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>

          <div className="hh-print__totals">
            <div>
              <span>Horas totais</span>
              <strong>{formatHoursBR(printHeader.totalHoras)}</strong>
            </div>
            <div>
              <span>Total geral</span>
              <strong>{formatCurrencyBRL(printHeader.totalValor)}</strong>
            </div>
          </div>

          <div className="hh-print__footer">
            <div>Sistema Estoque-OS</div>
            <div>Gerado automaticamente a partir dos lançamentos HH</div>
          </div>
        </div>
      </div>

      <style jsx global>{`
        .hh-print-only {
          display: none;
        }

        @media print {
          @page {
            size: A4 landscape;
            margin: 10mm;
          }

          body {
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
          }

          body * {
            visibility: hidden !important;
          }

          .hh-print-only,
          .hh-print-only * {
            visibility: visible !important;
          }

          .hh-print-only {
            display: block;
            position: absolute;
            left: 0;
            top: 0;
            width: 100%;
            background: white;
          }

          .hh-print {
            font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial, "Noto Sans", "Liberation Sans";
            color: #111827;
            padding: 0;
          }

          .hh-print__header {
            display: grid;
            grid-template-columns: 1fr 1fr 1fr;
            gap: 12px;
            align-items: start;
            padding: 8px 0 10px 0;
            border-bottom: 2px solid #111827;
            margin-bottom: 10px;
          }

          .hh-print__brand {
            display: flex;
            gap: 10px;
            align-items: center;
            min-height: 56px;
          }

          .hh-print__logo {
            width: 52px;
            height: 52px;
            object-fit: contain;
          }

          .hh-print__empresa {
            font-size: 14px;
            font-weight: 700;
            line-height: 1.2;
          }

          .hh-print__cliente {
            margin-top: 2px;
            font-size: 11px;
            color: #374151;
          }

          .hh-print__title {
            text-align: center;
          }

          .hh-print__titleMain {
            font-size: 16px;
            font-weight: 800;
          }

          .hh-print__titleSub {
            margin-top: 2px;
            font-size: 12px;
            font-weight: 600;
            color: #374151;
          }

          .hh-print__meta {
            display: grid;
            gap: 6px;
            justify-items: end;
            font-size: 11px;
          }

          .hh-print__meta span {
            display: block;
            font-size: 10px;
            color: #6b7280;
            line-height: 1.1;
          }

          .hh-print__meta strong {
            font-weight: 700;
            color: #111827;
          }

          .hh-print__table {
            width: 100%;
            border-collapse: collapse;
            font-size: 10px;
          }

          .hh-print__table thead {
            display: table-header-group;
          }

          .hh-print__table th {
            background: #111827;
            color: #ffffff;
            text-align: left;
            padding: 6px 6px;
            border: 1px solid #111827;
            white-space: nowrap;
          }

          .hh-print__table td {
            padding: 5px 6px;
            border: 1px solid #e5e7eb;
            vertical-align: top;
          }

          .hh-print__table tr {
            break-inside: avoid;
            page-break-inside: avoid;
          }

          .hh-print__table tbody tr:nth-child(even) td {
            background: #f9fafb;
          }

          .hh-print__table .num {
            text-align: right;
            font-variant-numeric: tabular-nums;
            white-space: nowrap;
          }

          .hh-print__table .center {
            text-align: center;
            white-space: nowrap;
          }

          .hh-print__totals {
            margin-top: 10px;
            display: flex;
            gap: 16px;
            justify-content: flex-end;
            border-top: 2px solid #111827;
            padding-top: 8px;
            break-inside: avoid;
            page-break-inside: avoid;
          }

          .hh-print__totals span {
            display: block;
            font-size: 10px;
            color: #6b7280;
          }

          .hh-print__totals strong {
            display: block;
            font-size: 12px;
            font-weight: 800;
          }

          .hh-print__footer {
            margin-top: 8px;
            padding-top: 6px;
            border-top: 1px solid #e5e7eb;
            display: flex;
            justify-content: space-between;
            font-size: 9px;
            color: #6b7280;
          }
        }
      `}</style>
    </>
  );
}
