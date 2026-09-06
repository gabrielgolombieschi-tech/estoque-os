/**
 * Monta o manual das tres operacoes de emissao (NF-e de revenda pela OV, NF-e
 * de industrializacao pela OS e NFS-e pela OS) com as capturas de tela reais
 * de 06/09/2026, e renderiza o PDF.
 *
 *   node scripts/gerar-manual-emissao.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const capturas = path.join(raiz, "tests", "e2e", ".saida");
const html = path.join(raiz, "docs", "faturamento", "manual-emissao-notas-2026-09-06.html");
const pdf = path.join(raiz, "docs", "faturamento", "manual-emissao-notas-2026-09-06.pdf");

function img(rel, legenda) {
  const arquivo = path.join(capturas, rel);
  if (!fs.existsSync(arquivo)) return `<figure class="falta"><figcaption>${legenda}</figcaption><div>captura não encontrada: ${rel}</div></figure>`;
  const b64 = fs.readFileSync(arquivo).toString("base64");
  return `<figure><img src="data:image/png;base64,${b64}" alt=""><figcaption>${legenda}</figcaption></figure>`;
}
const passo = (n, titulo, texto) => `<div class="passo"><span class="n">${n}</span><div><strong>${titulo}</strong><div>${texto}</div></div></div>`;

const secoes = [];

secoes.push(`
<section class="capa">
  <h1>Manual de emissão de notas pelo ERP</h1>
  <div class="sub">NF-e de revenda pela OV · NF-e de industrialização pela OS · NFS-e pela OS</div>
  <div class="sub">Elétrica Segau · 06/09/2026 · ciclos reais executados em produção e cancelados em seguida</div>
  <table class="reg">
    <tr><th>Operação</th><th>Origem</th><th>Homologação</th><th>Nota real</th><th>E-mail</th><th>Cancelada</th></tr>
    <tr><td>NF-e de revenda</td><td>OV-SEG-00004-026 (Portobello)</td><td>NF-e 2/20 · 14:29</td><td>NF-e 2/3 · 15:49</td><td>financeiro@segau.com.br</td><td>15:58</td></tr>
    <tr><td>NF-e de industrialização</td><td>OS 319 (Portobello)</td><td>NF-e 2/21 · 15:53</td><td>NF-e 2/4 · 16:04</td><td>financeiro@segau.com.br</td><td>16:10</td></tr>
    <tr><td>NFS-e de serviço</td><td>OS 280 (Portobello)</td><td>NFS-e 10 · DPS 2/19 · 14:22</td><td>NFS-e 51 · DPS 2/2 · 14:23</td><td>financeiro@segau.com.br</td><td>14:28</td></tr>
  </table>
  <h2>O que vale para as três</h2>
  <ul>
    <li><strong>Homologação primeiro.</strong> Toda nota real nasce de uma homologação autorizada da mesma solicitação. Sem ela o botão de produção não existe.</li>
    <li><strong>Perfil liberado para aquela homologação.</strong> A liberação do perfil fiscal é amarrada à solicitação homologada. Cada nota nova exige homologar e liberar de novo enquanto durar o período assistido.</li>
    <li><strong>Cadastro fiscal do cliente completo.</strong> CNPJ, IE e indicador de IE, endereço, CEP e IBGE. O que faltar vira bloqueio com o campo e o atalho para corrigir.</li>
    <li><strong>Nada é deduzido.</strong> Destinação da mercadoria, retenções, forma de pagamento e parcelas são confirmados na tela a cada nota.</li>
    <li><strong>E-mail e cancelamento</strong> ficam na tela de ciclo de vida da NF-e e nos botões da NFS-e. Cancelamento exige justificativa de 15 caracteres ou mais.</li>
  </ul>
</section>`);

secoes.push(`
<section>
  <h1>1 · NF-e de revenda pela OV</h1>
  <p class="intro">Tela: Comercial → Vendas → abrir a OV → aba <em>Faturamento</em>. Perfil usado: revenda em SC a 12% (destinação manutenção), já liberado.</p>
  ${passo(1, "Faturar e salvar o rascunho", "Na aba Faturamento, clique em <em>Faturar</em>. O rascunho reserva a quantidade do item.")}
  ${passo(2, "Conferir: destino e destinação", "Confirme se a mercadoria vai para SC ou outra UF e a destinação declarada pelo cliente (revenda, manutenção, uso e consumo…). É a destinação que decide 12% ou 17%.")}
  ${img("evidencia/01-pronto-para-emitir.png", "Conferência fiscal da OV com o perfil resolvido por linha e os campos confirmados.")}
  ${passo(3, "Emitir em homologação", "Clique em <em>Emitir em homologação</em>. A tela acompanha o retorno da SEFAZ sozinha.")}
  ${img("evidencia/03-autorizada.png", "NF-e autorizada em homologação (sem valor fiscal). O saldo fica reservado.")}
  ${passo(4, "Liberar o perfil para esta homologação", "Faturamento → Perfis fiscais → buscar o perfil → colar o id da solicitação homologada → justificativa → confirmar a equivalência → <em>Conferir e liberar para esta homologação</em>.")}
  ${img("perfis/SEG-VENDA-TERCEIROS-SC-5102-O2-CST00-liberar-02.png", "Perfil liberado, vinculado ao documento homologado.")}
  ${passo(5, "Conferir e emitir em produção", "De volta à OV, o botão <em>Conferir e emitir em produção</em> abre a conferência de produção. A etapa 1 já vem preenchida pelo snapshot homologado; siga para a conferência fiscal.")}
  ${img("producao/02-modal-producao.png", "Conferência em produção, etapa 1 (destino e destinação vindos da homologação).")}
  ${img("producao/03-modal-etapa-2.png", "Etapa 2: impostos por linha e total conferido.")}
  ${passo(6, "Confirmar a emissão real", "O ERP mostra destinatário, CNPJ mascarado e total. Só depois do OK a NF-e é transmitida com validade fiscal.")}
  ${img("manual/ov344-final.png", "OV com a NF-e real autorizada em produção; o item fica faturado e o saldo zera.")}
  ${passo(7, "Enviar por e-mail", "Abrir detalhes e ciclo da NF-e → <em>Enviar por e-mail</em> → informar o destinatário. Exige XML e DANFE já arquivados.")}
  ${passo(8, "Cancelar (até 24 h)", "Na mesma tela, justificativa de 15 a 255 caracteres → <em>Cancelar</em>. O título a receber é cancelado e o saldo da OV volta.")}
  ${img("manual/ciclo-nfe-revenda.png", "Ciclo de vida da NF-e real: autorização, e-mail e cancelamento registrados no histórico.")}
</section>`);

secoes.push(`
<section>
  <h1>2 · NF-e de industrialização pela OS</h1>
  <p class="intro">Tela: OS → <em>Faturar</em> → operação <em>Dentro de SC · CFOP 5101</em>. Perfil usado: produção própria em SC, 17%, consumidor final (criado e revisado hoje). O produto fabricado é criado na hora com NCM, origem, unidade e CST de IPI.</p>
  ${passo(1, "Linha da nota e produto fabricado", "Informe o valor e crie o produto pela OS (<em>Criar da OS</em>): descrição, NCM (9032.89.29), origem 0, unidade UN, CST IPI 51 (alíquota zero). O IPI é atributo do NCM, não do perfil.")}
  ${passo(2, "Destinação e pagamento", "Escolha a destinação declarada pelo cliente (uso e consumo próprio = 17%), presença, frete, forma e parcelas.")}
  ${img("os-nfe-318/02-preenchido.png", "Linha com o produto vinculado, destinação e pagamento preenchidos.")}
  ${passo(3, "Salvar rascunho e conferir", "A conferência aplica o perfil vigente (ou a fixture, se não houver perfil) e mostra ICMS, IPI, PIS/COFINS, IBS/CBS e bloqueios.")}
  ${img("os-nfe-318/03-conferido.png", "Prévia dos impostos calculados pela conferência.")}
  ${passo(4, "Emitir em homologação", "Clique em <em>Emitir em homologação</em> e aguarde a autorização.")}
  ${img("os-nfe-318/05-final.png", "NF-e autorizada em homologação.")}
  ${passo(5, "Liberar o perfil para esta homologação", "Faturamento → Perfis fiscais → perfil 5101 → solicitação homologada → justificativa → confirmar → liberar.")}
  ${img("perfis/SEG-IND-SC-5101-O0-CST00-17-liberar-02.png", "Perfil de industrialização liberado para a homologação da OS 319.")}
  ${passo(6, "Emitir NF-e real (produção)", "De volta à OS, a homologação autorizada reaparece com o botão <em>Emitir NF-e real (produção)</em>. O ERP mostra destinatário e total antes de transmitir.")}
  ${img("os-nfe-318/02-producao-antes.png", "Botão de produção liberado na tela da OS.")}
  ${img("manual/os319-final.png", "OS com a nota real em <em>Notas desta OS</em>, ao lado da homologação.")}
  ${passo(7, "E-mail e cancelamento", "Pelo link <em>Ciclo de vida</em> da nota real: enviar por e-mail e cancelar com justificativa, como na revenda.")}
  ${img("manual/ciclo-nfe-industrializacao.png", "Ciclo de vida da NF-e de industrialização: e-mail enfileirado e cancelamento autorizado.")}
</section>`);

secoes.push(`
<section>
  <h1>3 · NFS-e pela OS</h1>
  <p class="intro">Tela: OS → <em>Faturar</em> → operação com o perfil de serviço (14.01, 14.06, 17.09 ou 07.02). Caso executado: 14.01 com conserto isolado (peça projetada e fabricada para resolver um problema, sem contrato contínuo).</p>
  ${passo(1, "Escolher o perfil e as linhas", "No cabeçalho, escolha o perfil de serviço. Cada linha é uma OS do mesmo tomador; a descrição vira a discriminação. A expressão “mão de obra” é recusada.")}
  ${img("os-nfse-279/01-inicio.png", "Tela da NFS-e com o perfil 14.01 escolhido.")}
  ${passo(2, "Município, competência, retenções e exceções", "Município de prestação e competência vêm da regra do perfil e podem ser editados. As retenções seguem o perfil; a tela só libera o que é decisão por tomador. Marque <em>Conserto isolado</em> quando for o caso: a CRF cai e a frase legal muda.")}
  ${img("os-nfse-279/02-preenchido.png", "Operação de serviço preenchida, com conserto isolado marcado.")}
  ${passo(3, "Salvar rascunho e conferir", "A prévia mostra bruto, ISS, retenções, líquido, IBS/CBS e a discriminação montada pelo ERP.")}
  ${img("os-nfse-279/03-conferido.png", "Prévia da NFS-e com a discriminação e a frase legal do motivo.")}
  ${passo(4, "Emitir em homologação", "A DPS é numerada pelo ERP e enviada ao ambiente nacional de homologação. Aguarde a autorização na própria tela.")}
  ${img("os-nfse-279/05-final.png", "NFS-e autorizada em homologação; a produção ainda pede o perfil liberado.")}
  ${passo(5, "Liberar o perfil de serviço", "Hoje a liberação do perfil de serviço é feita por comando (fn_perfil_operacao_nfse_liberar_producao), amarrada à solicitação homologada. A tela de perfis ainda só lista perfis de NF-e.")}
  ${passo(6, "Emitir NFS-e real (produção)", "Com o perfil liberado, o botão <em>Emitir NFS-e real (produção)</em> aparece. A DPS de produção tem numeração própria. A nota real gera o título a receber com as retenções.")}
  ${img("os-nfse-279/02-producao-final.png", "NFS-e real 51 autorizada, listada em <em>Notas desta OS</em> ao lado da homologação 10.")}
  ${passo(7, "Enviar por e-mail", "Botão <em>Enviar por e-mail</em> da nota real: XML e DANFSe vão pela Focus para os endereços informados.")}
  ${img("os-nfse-279/02-email-enviado.png", "E-mail enfileirado para financeiro@segau.com.br.")}
  ${passo(8, "Cancelar", "Justificativa → <em>Cancelar NFS-e real na SEFAZ</em>. Vale até o fim do mês de emissão (Joinville); depois, só substituição. O título é cancelado e o saldo da OS volta.")}
  ${img("os-nfse-279/02-cancelada.png", "NFS-e 51 cancelada e saldo devolvido.")}
</section>`);

secoes.push(`
<section>
  <h1>4 · O que foi corrigido no caminho</h1>
  <table class="reg">
    <tr><th>Trava encontrada</th><th>Correção</th></tr>
    <tr><td>A NF-e de industrialização pela OS só conhecia a fixture de homologação; produção fechada.</td><td>A conferência da OS passou a resolver o perfil vigente (natureza, âmbito, UF, indicador de IE, origem, destinação, CRT) e a gravar a fonte PERFIL. Perfil 5101 criado, revisado e liberado.</td></tr>
    <tr><td>A tela da OS não reabria a homologação autorizada, então não havia onde emitir a nota real.</td><td>A homologação autorizada sem nota real volta como ativa, com o botão <em>Emitir NF-e real (produção)</em> e o mesmo fluxo de confirmação da OV.</td></tr>
    <tr><td>A liberação do perfil 5101 exigia evidência fiscal vinculada.</td><td>Evidência criada a partir das 34 NF-e reais de agosto e das respostas do contador.</td></tr>
    <tr><td>Linha do perfil gravava uma fonte de IPI fora da lista aceita.</td><td>Fonte ajustada para PERFIL_OPERACAO.</td></tr>
    <tr><td>A NFS-e não tinha botão de e-mail.</td><td>Botão <em>Enviar por e-mail</em> na nota real, com a ação da Focus.</td></tr>
    <tr><td>Liberação do perfil de serviço sem tela.</td><td>Feita por comando hoje; tela fica como pendência.</td></tr>
  </table>
  <h2>Pendências</h2>
  <ul>
    <li>Tela para liberar perfis de serviço (NFS-e), como já existe para NF-e.</li>
    <li>O acompanhamento automático da tela da OS após a emissão real pode demorar; a nota aparece em <em>Notas desta OS</em> ao recarregar.</li>
    <li>Nenhum perfil fica liberado de forma permanente: cada nota real exige homologar e liberar de novo durante o período assistido.</li>
  </ul>
</section>`);

const pagina = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Manual de emissão de notas</title>
<style>
  @page { size: A4 portrait; margin: 12mm; }
  body { font-family: "Segoe UI", Arial, sans-serif; color: #111; font-size: 11px; margin: 0; }
  section { page-break-after: always; }
  section:last-child { page-break-after: auto; }
  h1 { font-size: 20px; color: #0f4c81; margin: 0 0 6px; border-bottom: 2px solid #0f4c81; padding-bottom: 4px; }
  h2 { font-size: 14px; margin: 14px 0 6px; }
  .capa h1 { font-size: 26px; border: 0; }
  .sub { color: #555; font-size: 12px; margin-bottom: 6px; }
  .intro { background: #eef3f8; padding: 6px 8px; border-left: 3px solid #0f4c81; margin: 6px 0 10px; }
  .passo { display: flex; gap: 8px; margin: 8px 0 4px; page-break-inside: avoid; }
  .passo .n { flex: 0 0 22px; height: 22px; border-radius: 11px; background: #0f4c81; color: #fff; font-weight: 700; text-align: center; line-height: 22px; }
  figure { margin: 4px 0 10px; page-break-inside: avoid; text-align: center; }
  figure img { max-width: 100%; max-height: 225mm; width: auto; border: 1px solid #ccc; }
  figcaption { font-size: 10px; color: #444; margin-top: 3px; }
  figure.falta { color: #900; }
  table.reg { border-collapse: collapse; width: 100%; margin: 8px 0; }
  table.reg th, table.reg td { border: 1px solid #bbb; padding: 4px 6px; text-align: left; vertical-align: top; }
  table.reg th { background: #0f4c81; color: #fff; }
  ul { margin: 4px 0 0 18px; padding: 0; }
  li { margin: 3px 0; }
</style></head><body>${secoes.join("\n")}</body></html>`;
fs.writeFileSync(html, pagina);
execFileSync("node", [path.join(raiz, "scripts", "render-pdf-html.mjs"), html, pdf, "--retrato"], { stdio: "inherit" });
console.log("Manual:", pdf, Math.round(fs.statSync(pdf).size / 1024), "KB");
