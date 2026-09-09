import fs from "node:fs";
import { diretorio } from "./lib/controle-revisoes.mjs";
import { validarCinquenta, assinatura } from "./lib/lotes-cinquenta.mjs";
const celula = (s) => String(s ?? "—").replace(/\|/g, "/").replace(/\r?\n/g, "<br>");
for (const n of ["003", "004", "005", "006"]) {
  const m = JSON.parse(fs.readFileSync(`${diretorio}/lote-${n}-cinquenta-itens.json`, "utf8"));
  validarCinquenta(m);
  const evento = `${diretorio}/eventos-${m.lote}.json`;
  const aplicados = fs.existsSync(evento) ? JSON.parse(fs.readFileSync(evento, "utf8")) : [];
  const aplicado = aplicados.length === 50;
  const status = aplicado ? "APLICADO E VERIFICADO" : m.autorizacao === "aguardando_aprovacao_humana" ? "AGUARDANDO SUA APROVAÇÃO — NÃO APLICADO" : "AUTORIZADO — APLICAÇÃO AINDA NÃO CONFIRMADA";
  const composicao = { "003": "45 minidisjuntores Siemens + 5 contatores Siemens.", "004": "35 minidisjuntores WEG (27 MDW + 8 MDWP) + 15 disjuntores-motor Siemens.", "005": "50 Siemens: 9 disjuntores-motor, 9 relés de sobrecarga, 4 contatores auxiliares, 9 acessórios de contatores, 15 acessórios de disjuntores-motor e 4 acessórios de minidisjuntores." };
  composicao["006"] = "50 Siemens, todos com grupo: 10 disjuntores em caixa moldada, 12 acessórios de caixa moldada, 1 disjuntor aberto, 8 contatores, 1 minidisjuntor, 2 bornes de barramento, 3 disjuntores-motor, 1 disjuntor magnético para partida, 4 bases NH, 2 fusíveis NH, 1 seccionadora porta-fusível, 1 suporte de relé, 2 seccionadoras e 2 acessórios de seccionadoras.";
  const linhas = [
    `# Lote ${n} — 50 itens`, "", status, "",
    `Data da revisão: ${m.data}. Escopo: tenant ${m.tenant_id}; empresa ${m.empresa_id}.`, "",
    `${composicao[n]} Alterações somente em nome e descrição complementar. ${aplicado ? "Todos os 50 foram aplicados e verificados." : "A tabela é uma proposta: nenhum destes 50 foi alterado por este lote."}`, "",
    "Grupo, código, fabricante, fornecedor, unidades, multiplicadores, preço, saldo e dados fiscais permanecem iguais. Cada comparação usa o cadastro real capturado, não um exemplo inventado.", "",
    aplicado ? "As fontes técnicas e os registros de aplicação estão vinculados por ID. A ficha não substitui a conferência da placa/versão do item físico para dimensionamento." : `Para aprovar: informe “aprovo o lote ${n}” ou indique os IDs e ajustes desejados. Antes de aplicar, reconferir alterações concorrentes; este relatório não autoriza lotes seguintes. A ficha atual não substitui a conferência da placa/versão física para dimensionamento.`, "",
    ...(n === "005" ? ["Pontos para sua atenção: ID 2902 passa de 9-12A para 9-12,5A conforme ficha exata; ID 917 passa de 690V para IEC 1000VCA/1500VCC, com limite UL separado no complemento; ID 1621 recebe somente os dados disponíveis, sem inventar tensão/conexão/rearme. Os barramentos 802/806/810 não recebem tensão ausente na fonte. Aprovação é das alterações propostas, não certificação de todos os atributos possíveis.", "", "Fora destes 50: IDs 955, 966 e 918 tiveram ficha indisponível nesta consulta; ID 1541 tem resumo 9-12A e tabela 9-12,5A na mesma ficha, portanto não foi alterado. Consultar pesquisa-adiada-005.json antes de retomar, buscando nova evidência.", ""] : []),
    "## Antes e depois dos 50", "",
    "| Nº | ID / código | Antes | Depois " + (aplicado ? "aplicado" : "proposto") + " |",
    "| ---: | --- | --- | --- |",
    ...m.itens.map((i,k) => `| ${k+1} | ${i.id}<br>${celula(i.antes.codigo_interno)} | ${celula(i.antes.nome)} | ${celula(i.nome)} |`), "",
    "## Descrição complementar e evidências por item", "",
  ];
  if (n === "006") linhas.splice(linhas.indexOf("## Antes e depois dos 50"), 0,
    "## Pontos que precisam da sua atenção", "",
    "- IDs 733 e 2460: proteção magnética, sem proteção térmica. ID 960: unidade fornecida sem disparador ETU; não é proteção completa.",
    "- ID 791: 4 polos principais 2NA+2NF e auxiliares 1NA+1NF. IDs 772/775/813/3231: potência por parafuso, comando/auxiliares por mola.",
    "- IDs 195/196/197/198: revisão PARCIAL. A proposta retira 690VCA do nome porque as fichas atuais não confirmam essa tensão; preserva o valor antigo, identificado como não confirmado, no complemento. Isso não demonstra que 690VCA esteja errado. Tensão, polos e conexão precisam de placa ou documentação histórica antes do dimensionamento. Você pode pedir que esses quatro aguardem nova evidência.",
    "- ID 942: largura de trilho 35mm do cadastro anterior não confirmada na ficha atual. ID 2992: material/IP não inferidos. ID 953: valores inconsistentes em 500V na ficha não utilizados; proposta limitada à capacidade em 400VCA.",
    "- IDs 1620 e 2459 ficam fora: ficha resumida insuficiente e HTTP 404, respectivamente. Não presumir produto inexistente nem completar dados por similaridade.",
    "", "Aprovar as alterações não certifica atributos ausentes. Este lote não foi incorporado aos modelos humanos aprovados do agente. As novas famílias têm critério provisório de proposta, sem evento de aprovação.", "");
  for (const i of m.itens) linhas.push(`### ID ${i.id} — ${i.referencia}`, "", `Antes: ${i.antes.descricao ?? "(sem descrição complementar)"}`, "", `Depois: ${i.depois.descricao.split("\n\nFontes técnicas")[0]}`, "", ...i.fontes.map((f) => `Fonte: [documento técnico da referência](${f}).`), "", `Páginas conferidas: ${(i.evidencia.paginas_impressas ?? i.evidencia.paginas).join(", ")}. SHA-256 do documento: ${i.evidencia.sha256}.`, "");
  linhas.push("## Controle", "", `Assinatura SHA-256 do manifesto: ${assinatura(m)}.`, "", `Manifesto: lote-${m.lote}.json.`, "", `Eventos de aplicação confirmados: ${aplicados.length}.`, "");
  fs.writeFileSync(`${diretorio}/lote-${m.lote}.md`, linhas.join("\n"));
}
