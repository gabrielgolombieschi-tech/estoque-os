import fs from "node:fs";
import * as XLSX from "xlsx";
const [, , entrada, saida] = process.argv;
const rows = fs.readFileSync(entrada, "utf8").trim().split(/\r?\n/).map((l) => {
  const [numero, data, valor, servico, inss, irrf, csll, tpret, tomador, cnpj, simples, disc] = l.split("|");
  return { numero: Number(numero), data, valor: Number(valor), servico, inss: Number(inss || 0), irrf: Number(irrf || 0), csll: Number(csll || 0), tpret, tomador, cnpj, simples, disc };
});
const fmt = (n) => Math.round(n * 100) / 100;
const cnpjFmt = (c) => c.length === 14 ? `${c.slice(0,2)}.${c.slice(2,5)}.${c.slice(5,8)}/${c.slice(8,12)}-${c.slice(12)}` : c;
const nome = { "140101": "14.01 Manutenção", "140601": "14.06 Instalação/montagem", "170901": "17.09 Laudos e perícias", "170601": "17.06 (fora do catálogo)", "070201": "07.02 Obra" };
const wb = XLSX.utils.book_new();
const add = (n, linhas, larg) => { const ws = XLSX.utils.aoa_to_sheet(linhas); ws["!cols"] = larg.map((w) => ({ wch: w })); XLSX.utils.book_append_sheet(wb, ws, n); };

const r1401 = rows.filter((r) => r.servico === "140101");
add("Auditoria 14.01", [
  ["NFS-e", "Data", "Tomador", "CNPJ", "Valor do serviço", "CRF retida na nota", "CRF que a regra manda (4,65%)", "Tomador do Simples?", "Nota acima de R$ 215,05?", "Conserto isolado? (preencher)", "Conclusão preliminar"],
  ...r1401.map((r) => [
    r.numero, r.data, r.tomador, cnpjFmt(r.cnpj), r.valor, fmt(r.csll), fmt(r.valor * 0.0465),
    r.simples === "true" ? "Sim" : r.simples === "false" ? "Não" : "Não informado no cadastro",
    r.valor > 215.05 ? "Sim" : "Não",
    "",
    r.csll > 0 ? "OK: retida" : "Saiu sem CRF. Só está certa se for conserto isolado; senão, a Segau recolhe os 4,65% no DARF.",
  ]),
  [],
  ["Total a recolher se nenhuma for conserto isolado", "", "", "", fmt(r1401.reduce((s, r) => s + r.valor, 0)), "", fmt(r1401.reduce((s, r) => s + r.valor * 0.0465, 0))],
  [],
  ["Critérios (contador, 06/09/2026)", "1) Tomador não é do Simples; 2) nota acima de R$ 215,05 (retenção acima de R$ 10,00); 3) não é conserto isolado de equipamento quebrado (foi manutenção de contrato). Se os três valem, a nota saiu errada."],
  ["Atenção", "A NFS-e 24 (Portobello, R$ 6.500,00) foi codificada como 14.06, mas a discriminação diz 'manutenção e recuperação de peças e equipamentos'. Se for 14.01 na essência, entra na mesma regra."],
], [8, 12, 26, 20, 16, 16, 24, 22, 20, 24, 70]);

add("Todas de agosto", [
  ["NFS-e", "Data", "Serviço (cTribNac)", "Tomador", "Valor", "ISS retido?", "INSS retido", "IRRF retido", "CSLL retida (= CRF)", "Discriminação (início)"],
  ...rows.map((r) => [r.numero, r.data, nome[r.servico] ?? r.servico, r.tomador, r.valor, r.tpret === "2" ? "Sim" : "Não", fmt(r.inss), fmt(r.irrf), fmt(r.csll), r.disc]),
], [8, 12, 24, 30, 14, 12, 12, 12, 16, 90]);

add("Como foi feito", [
  ["Item", "Detalhe"],
  ["Fonte", "XML das NFS-e de agosto/2026 importadas no ERP (emissor antigo): cTribNac, vRetCP, vRetIRRF, vRetCSLL, tpRetISSQN."],
  ["Regra", "IN RFB 2.141/2023: manutenção (14.01) sofre CRF 4,65% por padrão; exceções: conserto isolado, tomador do Simples, retenção até R$ 10,00."],
  ["O que falta", "Marcar 'conserto isolado' nota a nota (informação que só quem atendeu a OS sabe) e confirmar o regime dos tomadores no cadastro."],
  ["Ação", "Enviar ao contador as notas sem exceção para ele somar os 4,65% no DARF mensal da Segau."],
], [16, 120]);
XLSX.writeFile(wb, saida);
console.log("ok", r1401.map((r) => `${r.numero}: ${r.valor} -> CRF ${fmt(r.valor * 0.0465)}`).join(" | "));
