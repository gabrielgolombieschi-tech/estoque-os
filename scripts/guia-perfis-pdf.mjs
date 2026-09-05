/**
 * Gera docs/faturamento/guia-perfis-fiscais.pdf a partir das capturas em
 * docs/faturamento/guia-perfis-fiscais-imagens (ver guia-perfis-capturas.mjs).
 *
 *   node scripts/guia-perfis-pdf.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const pasta = path.join(raiz, "docs", "faturamento", "guia-perfis-fiscais-imagens");
const destino = path.join(raiz, "docs", "faturamento", "guia-perfis-fiscais.pdf");

const img = (nome, alt, opts = {}) => {
  const b64 = fs.readFileSync(path.join(pasta, nome)).toString("base64");
  const corte = opts.semCabecalho === false ? "" : "sem-cabecalho";
  return `<figure class="shot ${corte}"><div class="janela"><img src="data:image/png;base64,${b64}" alt="${alt}"></div><figcaption>${alt}</figcaption></figure>`;
};

const html = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>Guia — Perfis fiscais da NF-e</title>
<style>
  @page { size: A4; margin: 16mm 14mm 18mm 14mm; }
  * { box-sizing: border-box; }
  body { font-family: "Segoe UI", Arial, sans-serif; color: #1f2937; font-size: 11pt; line-height: 1.45; margin: 0; }
  h1 { font-size: 24pt; margin: 0 0 4pt; color: #0f172a; }
  h2 { font-size: 16pt; margin: 22pt 0 8pt; color: #0f172a; border-bottom: 2px solid #0ea5e9; padding-bottom: 3pt; page-break-after: avoid; }
  h3 { font-size: 12.5pt; margin: 14pt 0 6pt; color: #0369a1; page-break-after: avoid; }
  p { margin: 0 0 7pt; }
  .sub { color: #64748b; font-size: 10.5pt; margin-bottom: 14pt; }
  .capa { border: 1px solid #e2e8f0; border-radius: 10px; padding: 14pt 16pt; background: #f8fafc; margin-bottom: 14pt; }
  .capa ul { margin: 6pt 0 0 16pt; padding: 0; }
  .passo { display: flex; gap: 10pt; align-items: flex-start; margin: 8pt 0; page-break-inside: avoid; }
  .num { flex: 0 0 24pt; height: 24pt; border-radius: 50%; background: #0ea5e9; color: #fff; font-weight: 700; display: flex; align-items: center; justify-content: center; font-size: 12pt; }
  .passo p { margin: 2pt 0; }
  .aviso { border-left: 4px solid #f59e0b; background: #fffbeb; padding: 7pt 10pt; margin: 8pt 0; page-break-inside: avoid; }
  .ok { border-left: 4px solid #10b981; background: #ecfdf5; padding: 7pt 10pt; margin: 8pt 0; page-break-inside: avoid; }
  .nao { border-left: 4px solid #ef4444; background: #fef2f2; padding: 7pt 10pt; margin: 8pt 0; page-break-inside: avoid; }
  table { border-collapse: collapse; width: 100%; margin: 6pt 0 10pt; font-size: 10pt; page-break-inside: avoid; }
  th, td { border: 1px solid #e2e8f0; padding: 5pt 7pt; text-align: left; vertical-align: top; }
  th { background: #f1f5f9; }
  code { font-family: Consolas, "Courier New", monospace; font-size: 9.5pt; background: #f1f5f9; padding: 1pt 3pt; border-radius: 3px; }
  .shot { margin: 8pt 0 12pt; page-break-inside: avoid; }
  .shot .janela { border: 1px solid #cbd5e1; border-radius: 8px; overflow: hidden; background: #000; }
  .shot img { width: 100%; display: block; }
  .shot.sem-cabecalho img { margin-top: -6.7%; }
  figcaption { font-size: 9.5pt; color: #64748b; margin-top: 4pt; }
  .quebra { page-break-before: always; }
  .rodape { font-size: 9pt; color: #94a3b8; margin-top: 20pt; border-top: 1px solid #e2e8f0; padding-top: 6pt; }
</style></head><body>

<h1>Perfis fiscais da NF-e</h1>
<p class="sub">Guia do usuário · Faturamento → Perfis fiscais · Elétrica Segau · versão de 05/09/2026</p>

<div class="capa">
  <p><strong>Para quem é:</strong> quem opera o faturamento e conversa com o contador.</p>
  <p><strong>O que você vai aprender:</strong></p>
  <ul>
    <li>o que é um perfil fiscal e como ler a tela;</li>
    <li>o ciclo completo para colocar um perfil em produção: <strong>revisar → testar em homologação → liberar</strong>;</li>
    <li>o que perguntar ao contador antes de mexer;</li>
    <li>quando pedir um perfil novo ao desenvolvimento.</li>
  </ul>
</div>

<h2>1. O que é um perfil fiscal</h2>
<p>Um perfil é a <strong>receita de impostos</strong> que o sistema usa para montar uma NF-e. Cada perfil vale para uma combinação de:</p>
<table>
  <tr><th>Elemento</th><th>Exemplo do primeiro perfil liberado</th></tr>
  <tr><td>Empresa emitente</td><td>SEG (Elétrica Segau)</td></tr>
  <tr><td>Natureza da operação</td><td>venda de mercadoria adquirida de terceiros (revenda)</td></tr>
  <tr><td>CFOP</td><td>5102 (venda dentro de SC)</td></tr>
  <tr><td>Destino</td><td>interna · SC</td></tr>
  <tr><td>Origem da mercadoria</td><td>2 · estrangeira, adquirida no mercado interno</td></tr>
  <tr><td>Destinação que o cliente declara</td><td>revenda, insumo, manutenção ou consignado → ICMS 12%</td></tr>
</table>
<p>Na conferência da nota, o sistema procura o perfil que casa com essa combinação e <strong>trava</strong> os campos fiscais com os valores dele: CFOP, CST, alíquota de ICMS, PIS/COFINS, IPI e IBS/CBS. O operador não digita imposto; ele confirma o que o perfil traz.</p>

<div class="aviso"><strong>Esta tela não cadastra CFOP nem cria perfil.</strong> CFOP, CST, alíquota de ICMS, PIS/COFINS e IPI nascem de um cadastro controlado, feito pelo desenvolvimento a partir da resposta escrita do contador. A tela só faz duas coisas: registrar a <em>revisão</em> dos campos de IBS/CBS e <em>liberar</em> o perfil para produção.</div>

<h2>2. Como ler a tela</h2>
${img("02-perfil-cabecalho.png", "Tela Perfis fiscais: lista à esquerda, perfil selecionado à direita com os oito cartões da receita.")}
<h3>Os oito cartões</h3>
<table>
  <tr><th>Cartão</th><th>O que mostra</th></tr>
  <tr><td>Destino</td><td>INTERNA · SC, ou INTERESTADUAL com as UFs atendidas</td></tr>
  <tr><td>CFOP</td><td>CFOP interno (dentro de SC) e externo (outra UF)</td></tr>
  <tr><td>ICMS</td><td>CRT da empresa, origem da mercadoria e CST (ou CSOSN no Simples)</td></tr>
  <tr><td>PIS / COFINS</td><td>CST e alíquotas</td></tr>
  <tr><td>Base ICMS</td><td>modalidade da base e alíquota</td></tr>
  <tr><td>cBenef</td><td>código do benefício fiscal, ou SEM_BENEFICIO</td></tr>
  <tr><td>Emissão</td><td>finalidade (1 = normal) e consumidor final (0 = não, 1 = sim)</td></tr>
  <tr><td>Evidência</td><td>se há nota real de referência vinculada, e a faixa</td></tr>
</table>
<h3>As etiquetas da lista</h3>
${img("05-lista-etiquetas.png", "Lista de perfis com as etiquetas de faixa (REVISAO / BLOQUEADO) e de produção (PRODUCAO / FORA DE PRODUCAO).")}
<table>
  <tr><th>Etiqueta</th><th>Significado</th></tr>
  <tr><td>REVISAO</td><td>perfil válido; cada nota exige confirmação humana na conferência</td></tr>
  <tr><td>BLOQUEADO</td><td>perfil nunca monta nota; falta decisão do contador (IPI, produzido × revendido, cabo elegível...)</td></tr>
  <tr><td>AUTOMATICO</td><td>reservado para perfis totalmente confirmados; nenhum hoje</td></tr>
  <tr><td>FORA DE PRODUCAO</td><td>só emite em homologação (teste, sem valor fiscal)</td></tr>
  <tr><td>PRODUCAO</td><td>liberado para nota real</td></tr>
</table>

<h2 class="quebra">3. Passo a passo: colocar um perfil em produção</h2>
<p>O ciclo é sempre o mesmo: <strong>revisar → testar em homologação → liberar</strong>. Toda vez que uma regra muda, o ciclo recomeça do início.</p>

<h3>Passo 1 · Conferir a receita com o contador</h3>
<p>Antes de mexer na tela, confirmar com o contador, para aquela combinação:</p>
<div class="passo"><div class="num">a</div><div><p>CFOP e CST de ICMS.</p></div></div>
<div class="passo"><div class="num">b</div><div><p>Alíquota de ICMS e de quem ela depende. Em SC: <strong>12%</strong> para contribuinte que revende, industrializa, usa como insumo ou manutenção; <strong>17%</strong> para uso e consumo, ativo imobilizado ou não contribuinte.</p></div></div>
<div class="passo"><div class="num">c</div><div><p>Se o NCM tem benefício. Hoje só três NCMs têm redução de base em SC: <code>8536.49.00</code>, <code>8536.50.90</code> e <code>8544.49.00</code> (cBenef SC820006). <strong>Não estender por analogia.</strong></p></div></div>
<div class="passo"><div class="num">d</div><div><p>CST e alíquotas de PIS/COFINS. CST de IPI e enquadramento (cEnq).</p></div></div>
<div class="passo"><div class="num">e</div><div><p>CST IBS/CBS e cClassTrib. Em 2026: <code>000</code> e <code>000001</code> para revenda, com IBS UF 0,10%, IBS municipal 0% e CBS 0,90%.</p></div></div>
<div class="nao"><strong>Se o contador mudar qualquer valor de ICMS, CFOP, PIS/COFINS ou IPI, pare aqui.</strong> Peça ao desenvolvimento um perfil novo ou ajustado. A tela não edita esses campos.</div>

<h3>Passo 2 · Registrar a revisão (bloco "Campos IBS/CBS sujeitos a revisão")</h3>
<p>Só quando os valores de IBS/CBS mudarem, ou quando o perfil nunca foi revisado.</p>
${img("03-bloco-revisao-ibs-cbs.png", "Bloco de revisão: seis campos de IBS/CBS, justificativa e o botão que salva e desliga a produção.")}
<div class="passo"><div class="num">1</div><div><p>Selecionar o perfil na lista da esquerda. Dá para buscar por código, nome ou natureza.</p></div></div>
<div class="passo"><div class="num">2</div><div><p>Preencher os seis campos: CST IBS/CBS, cClassTrib, versão da tabela, alíquota IBS UF, IBS municipal e CBS. O botão <strong>Aplicar referência homologada</strong> preenche com a última referência usada; mesmo assim, conferir.</p></div></div>
<div class="passo"><div class="num">3</div><div><p>Escrever a <strong>justificativa</strong> (15 a 1.000 caracteres): a fonte (documento do contador e data), a decisão e por que os valores se aplicam a este perfil.</p></div></div>
<div class="passo"><div class="num">4</div><div><p>Clicar em <strong>Salvar revisão e desabilitar produção</strong>.</p></div></div>
<div class="aviso"><strong>Salvar uma revisão sempre desliga a produção do perfil.</strong> É proposital: uma receita alterada precisa ser testada de novo antes de gerar nota real. Não clique nesse botão "só para conferir".</div>

<h3 class="quebra">Passo 3 · Emitir uma NF-e de homologação com o perfil</h3>
<p>Abrir uma OV que use esse perfil (mesma empresa, natureza, destino, origem e destinação) e ir na aba <strong>Faturamento</strong>.</p>
${img("06-ov-aba-faturamento.png", "Aba Faturamento da OV: saldo a faturar, cartão da NF-e e os botões de ação.")}
<div class="passo"><div class="num">1</div><div><p><strong>Faturar → Salvar rascunho da NF-e</strong>. Isso cria a solicitação; ainda não emite nada.</p></div></div>
<div class="passo"><div class="num">2</div><div><p><strong>Conferir e emitir em homologação</strong>. Na etapa 1, escolher o destino (dentro de SC ou outra UF) e a <strong>destinação da mercadoria</strong> declarada pelo cliente.</p></div></div>
<div class="passo"><div class="num">3</div><div><p>Na etapa 2, confirmar presença do comprador, forma de pagamento, frete e valores. Os campos com cadeado vêm do perfil e não podem ser alterados.</p></div></div>
${img("09-conferencia-nfe.png", "Conferência da NF-e, etapa 2: campos com cadeado vêm do perfil; pagamento e frete são confirmados em cada nota.")}
<div class="passo"><div class="num">4</div><div><p>Clicar em <strong>Emitir em homologação</strong> e aguardar o status <strong>Autorizada em homologação</strong>. O retorno chega sozinho; não precisa ficar na tela.</p></div></div>
<div class="ok">A nota de homologação <strong>não tem valor fiscal</strong>, não gera contas a receber e serve só para provar a receita. Ela reserva o saldo da OV até ser abandonada pelo botão <em>Abandonar homologação e liberar saldo</em>.</div>

<h3>Passo 4 · Liberar para produção (bloco "Liberação separada para produção")</h3>
${img("04-bloco-liberacao.png", "Bloco de liberação: solicitação homologada, justificativa, caixa de confirmação e o botão de liberar.")}
<div class="passo"><div class="num">1</div><div><p>Voltar em <strong>Faturamento → Perfis fiscais</strong> e selecionar o perfil.</p></div></div>
<div class="passo"><div class="num">2</div><div><p>Em <strong>Solicitação da NF-e homologada</strong>, escolher a nota do passo 3. A tela confirma "autorizado em ... · posterior à última revisão". Se disser que é anterior, a nota foi emitida antes da revisão e não serve: volte ao passo 3.</p></div></div>
<div class="passo"><div class="num">3</div><div><p>Escrever a <strong>justificativa da liberação</strong>. Exemplo: "Revenda interna SC, origem 2, 12%, conferida na NF-e 2/14 de homologação em 05/09/2026".</p></div></div>
<div class="passo"><div class="num">4</div><div><p>Marcar a caixa <strong>Confirmo a equivalência com esta NF-e AUTORIZADA em homologação...</strong></p></div></div>
<div class="passo"><div class="num">5</div><div><p>Clicar em <strong>Conferir e liberar para esta homologação</strong>.</p></div></div>
<p>Antes de aceitar, o sistema confere sozinho: revisão registrada, nota de homologação autorizada depois dela, certificado digital válido, todos os campos do perfil preenchidos e os seis valores de IBS/CBS iguais entre perfil, solicitação e XML autorizado. Se faltar algo, ele lista a pendência.</p>
<div class="ok"><strong>Resultado:</strong> a etiqueta vira <strong>Liberado</strong> e "Última decisão de produção" registra data e hora. A liberação fica amarrada àquela solicitação e àquele documento.</div>

<h3>Passo 5 · O que acontece depois</h3>
<p>A liberação do perfil <strong>não emite nada</strong>. A nota real só sai pela OV, pelo botão de produção, com confirmação na hora. Esse botão só aparece quando, além do perfil liberado, existem a credencial de produção da Focus, o certificado digital válido e a chave de produção ligada.</p>
${img("07-ov-cartao-nfe.png", "Cartão da NF-e na OV depois da liberação do perfil: o aviso mostra o que ainda falta do lado da credencial.")}
<p>Qualquer nova revisão do perfil desliga a produção de novo. O ciclo recomeça no passo 2.</p>

<h2 class="quebra">4. Depois da nota: o ciclo de vida</h2>
${img("08-nfe-ciclo-vida.png", "Detalhe da NF-e: cancelamento dentro de 24 horas, carta de correção, download de XML e DANFE, histórico imutável.")}
<table>
  <tr><th>Ação</th><th>Quando</th></tr>
  <tr><td>Cancelar na SEFAZ</td><td>até 24 horas depois da autorização, com justificativa de 15 a 255 caracteres</td></tr>
  <tr><td>NF-e de estorno</td><td>depois das 24 horas; a SEFAZ rejeita o cancelamento (comprovado em homologação com o código 501)</td></tr>
  <tr><td>Carta de correção</td><td>para dados acessórios; nunca para valor, quantidade, imposto, destinatário ou data</td></tr>
  <tr><td>XML e DANFE</td><td>download pelos botões; envio ao cliente por e-mail só em nota de produção</td></tr>
</table>

<h2>5. Quando pedir um perfil novo</h2>
<p>A nota vai travar por falta de perfil nestas situações. O pedido ao desenvolvimento precisa levar a resposta do contador com todos os itens do passo 1; sem isso o perfil nasce BLOQUEADO.</p>
<ul>
  <li>operação nova: devolução, remessa para conserto, venda à ordem, industrialização;</li>
  <li>venda para outra UF que ainda não tem perfil;</li>
  <li>mercadoria com origem diferente da que o perfil cobre (0, 1, 2, 6...);</li>
  <li>cliente não contribuinte fora de SC (exige perfil próprio de DIFAL);</li>
  <li>NCM com benefício que ainda não está cadastrado.</li>
</ul>

<h2>6. Perguntas prontas para o contador</h2>
<ol>
  <li>Nesta operação, qual CFOP e qual CST de ICMS?</li>
  <li>A alíquota interna é 12% ou 17%, e depende do que o cliente declara na ordem de compra?</li>
  <li>O NCM tem redução de base ou outro benefício? Qual cBenef e qual base legal deve ir nas informações complementares?</li>
  <li>CST e alíquotas de PIS/COFINS na saída?</li>
  <li>CST de IPI e código de enquadramento?</li>
  <li>CST IBS/CBS e cClassTrib para esta natureza?</li>
  <li>Há texto obrigatório nas informações complementares (suspensão, diferimento, base reduzida)?</li>
</ol>

<h2>7. Perfis liberados</h2>
<table>
  <tr><th>Data</th><th>Perfil</th><th>Evidência</th></tr>
  <tr><td>05/09/2026</td><td><code>SEG-VENDA-TERCEIROS-SC-5102-O2-CST00</code></td><td>NF-e 2/14 de homologação, protocolo 342260000903496</td></tr>
</table>

<p class="rodape">Fonte das regras: "Apresentação dos tributos incidentes no Lucro Real — Elétrica Segau", Status Contabilidade, 24/11/2021; e-mails sobre cBenef obrigatório; carta da Portobello (Lei 17.878/2019). Documento técnico correspondente: docs/faturamento/guia-perfis-fiscais.md.</p>
</body></html>`;

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage();
await pagina.setContent(html, { waitUntil: "load" });
await pagina.pdf({ path: destino, format: "A4", printBackground: true, margin: { top: "16mm", right: "14mm", bottom: "18mm", left: "14mm" } });
// Previa em PNG para conferencia visual (a maquina nao tem renderizador de PDF).
if (process.argv.includes("--previa")) {
  const previa = process.argv[process.argv.indexOf("--previa") + 1];
  await pagina.setViewportSize({ width: 794, height: 1123 });
  await pagina.emulateMedia({ media: "print" });
  await pagina.screenshot({ path: previa, fullPage: true });
  console.log("previa:", previa);
}
await navegador.close();
console.log("PDF gerado:", destino, Math.round(fs.statSync(destino).size / 1024), "KB");
