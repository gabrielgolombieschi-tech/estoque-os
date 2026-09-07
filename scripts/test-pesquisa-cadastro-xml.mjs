import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import ts from "typescript";
import { createElement } from "react";
import * as jsxRuntime from "react/jsx-runtime";
import { renderToStaticMarkup } from "react-dom/server";
import * as pesquisa from "../lib/itens/pesquisaCadastroXml.ts";
import * as nomes from "../lib/itens/normalizacaoNome.ts";
import * as qualidade from "../lib/itens/qualidadeDescricao.ts";
import * as correcoes from "../lib/nfe/descricaoCorrecaoIa.ts";

const url = "https://www.sick.com/media/pdf/1/71/871/dataSheet_STR1-SACM0PR5_1112263_en.pdf";
const titulo = "STR1-SACM0PR5, Data sheet";
const pesquisaRaw = { status: "exato", modelo_referencia: "STR1-SACM0PR5", fontes_urls: [url], observacao: "Chave RFID, código e variante confirmados na ficha." };
const sugestao = {
  codigo: "1112263", descricao_padronizada: "CHAVE DE SEGURANÇA RFID STR1-SACM0PR5 SAO 10MM 2OSSD 24VCC M12 5 PINOS",
  grupo_id: 27, novo_grupo: null, justificativa: "Ficha técnica do fabricante.", dados_pendentes: [], confianca: "alta", pesquisa_tecnica: pesquisaRaw,
};
const fixture = (sugestoes = [sugestao]) => ({ status: "completed", output: [
  { type: "web_search_call", status: "completed", action: { type: "search", sources: [{ type: "url", url, title: titulo }] } },
  { type: "message", content: [{ type: "output_text", text: JSON.stringify({ sugestoes }), annotations: [] }] },
] });
const fontes = pesquisa.fontesPesquisaCadastroXml(fixture());
assert.equal(fontes.length, 1);
assert.equal(pesquisa.sanitizarPesquisaCadastroXml(pesquisaRaw, fontes).status, "exato");
assert.equal(pesquisa.sanitizarPesquisaCadastroXml({ ...pesquisaRaw, fontes_urls: ["https://www.sick.com/inventado"] }, fontes).status, "nao_confirmado");
assert.equal(pesquisa.sanitizarPesquisaCadastroXml({ ...pesquisaRaw, modelo_referencia: null }, fontes).status, "nao_confirmado");
assert.equal(pesquisa.sanitizarPesquisaCadastroXml({ ...pesquisaRaw, status: "similar" }, fontes).status, "nao_confirmado");
assert.equal(pesquisa.fontesPesquisaCadastroXml({ output: [{ type: "message", content: [{ text: url }] }] }).length, 0);
const maliciosas = fixture();
maliciosas.output[0].action.sources = ["javascript:alert(1)", "https://localhost/a", "https://192.168.1.1/a", "https://user:pass@www.sick.com/a", "https://intranet.internal/a"].map((url) => ({ url }));
assert.equal(pesquisa.fontesPesquisaCadastroXml(maliciosas).length, 0);
const falhaBusca = fixture(); falhaBusca.output[0].status = "failed";
assert.equal(pesquisa.fontesPesquisaCadastroXml(falhaBusca).length, 0);
const citacao = fixture(); citacao.output[0].action.sources = [];
citacao.output[1].content[0].annotations = [{ type: "url_citation", url, title: titulo }];
assert.equal(pesquisa.fontesPesquisaCadastroXml(citacao).length, 1);
assert.equal(pesquisa.ferramentasPesquisaCadastroXml(20).max_tool_calls, 40);
assert.equal(pesquisa.ferramentasPesquisaCadastroXml(1).tool_choice, "required");

const routeFile = "app/api/estoque/importar/normalizar-itens/route.ts";
const compilado = ts.transpileModule(fs.readFileSync(routeFile, "utf8"), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
let chamadas = 0;
let ultimoPayload;
async function executar({ resposta = fixture(), statusApi = 200, fornecedor = { id: 14, nome: "SICK" }, permitido = true, bodyExtra = {}, erroFetch = null } = {}) {
  const consultas = [];
  const db = { from(tabela) {
    const filtros = [];
    consultas.push({ tabela, filtros });
    const dados = () => {
      assert.ok(filtros.some(([c, v]) => c === "tenant_id" && v === "tenant-teste"));
      assert.ok(filtros.some(([c, v]) => c === "empresa_id" && v === "empresa-teste"));
      return { data: tabela === "fornecedores" ? fornecedor : tabela === "item_grupos" ? [{ id: 27, codigo: "CHAVES_SEGURANCA", nome: "Chaves de segurança", grupo_pai_id: null }] : [], error: null };
    };
    const chain = {
      select() { return chain; }, eq(c, v) { filtros.push([c, v]); return chain; }, is(c, v) { filtros.push([c, v]); return chain; },
      order() { return chain; }, limit() { return chain; }, maybeSingle() { return Promise.resolve(dados()); },
      then(resolve, reject) { return Promise.resolve().then(dados).then(resolve, reject); },
    };
    return chain;
  } };
  const json = (body, init = {}) => ({ status: init.status ?? 200, body });
  const imports = {
    "node:fs/promises": { readFile: async () => "versao_padrao: teste" },
    "node:path": { default: { join: (...p) => p.join("/") } },
    "next/server": { NextResponse: { json } },
    "@/app/api/compras/_lib": {
      getAuthSupabase: async () => ({ supabase: { rpc: async () => ({ data: permitido }) } }),
      resolveTenantEmpresa: async () => ({ tenantId: "tenant-teste", empresaId: "empresa-teste" }),
      jsonError: (status, error) => json({ error }, { status }),
    },
    "@/lib/supabase/admin": { supabaseAdmin: () => db },
    "@/lib/itens/normalizacaoNome": nomes,
    "@/lib/itens/qualidadeDescricao": qualidade,
    "@/lib/itens/pesquisaCadastroXml": pesquisa,
    "@/lib/nfe/descricaoCorrecaoIa": correcoes,
  };
  const exports = {};
  vm.runInNewContext(compilado, {
    exports, require: (name) => { assert.ok(imports[name], name); return imports[name]; },
    process: { cwd: () => ".", env: { OPENAI_API_KEY: "chave-ficticia", ASSISTENTE_IA_OPENAI_MODEL: "modelo-teste" } },
    AbortSignal, Error,
    fetch: async (endpoint, args) => {
      chamadas++;
      assert.equal(endpoint, "https://api.openai.com/v1/responses");
      ultimoPayload = JSON.parse(args.body);
      assert.equal(ultimoPayload.tool_choice, "required");
      assert.equal(ultimoPayload.tools[0].type, "web_search");
      assert.ok(ultimoPayload.include.includes("web_search_call.action.sources"));
      assert.ok(ultimoPayload.text.format.schema.properties.sugestoes.items.required.includes("pesquisa_tecnica"));
      assert.equal(ultimoPayload.store, false);
      if (erroFetch) throw erroFetch;
      return { ok: statusApi === 200, text: async () => JSON.stringify(resposta) };
    },
  });
  return exports.POST({ json: async () => ({ fornecedor_id: 14, itens: [{ codigo: "1112263", descricao_nf: "SWITCH DE REDE INDUSTRIAL" }], ...bodyExtra }) });
}

let result = await executar();
assert.equal(result.status, 200);
assert.equal(result.body.sugestoes[0].pesquisa_tecnica.fontes[0].url, url);
assert.equal(result.body.sugestoes[0].descricao_padronizada, sugestao.descricao_padronizada);
assert.equal(result.body.sugestoes[0].confianca, "alta");
const payloadReal = structuredClone(ultimoPayload);
result = await executar({ resposta: fixture([{ ...sugestao, pesquisa_tecnica: { ...pesquisaRaw, fontes_urls: ["https://fabricante.example/inventado"] } }]) });
assert.equal(result.body.sugestoes[0].confianca, "baixa");
assert.equal(result.body.sugestoes[0].descricao_padronizada, "SWITCH DE REDE INDUSTRIAL");
assert.equal(result.body.sugestoes[0].pesquisa_tecnica.fontes.length, 0);
result = await executar({ resposta: fixture([{ ...sugestao, pesquisa_tecnica: null }]), bodyExtra: { correcoes_descricao_locais: [{ descricao_origem: "SWITCH DE REDE INDUSTRIAL", descricao_corrigida: "CHAVE DE SEGURANÇA REVISADA" }] } });
assert.equal(result.body.sugestoes[0].descricao_padronizada, "CHAVE DE SEGURANÇA REVISADA");
assert.equal(result.body.sugestoes[0].confianca, "baixa");
result = await executar({ resposta: fixture([{ ...sugestao, codigo: "outro-item" }]) });
assert.equal(result.body.sugestoes.length, 1);
assert.equal(result.body.sugestoes[0].codigo, "1112263");
assert.equal(result.body.sugestoes[0].pesquisa_tecnica.status, "nao_confirmado");
const antes = chamadas;
assert.equal((await executar({ fornecedor: null })).status, 422);
assert.equal((await executar({ permitido: false })).status, 403);
assert.equal(chamadas, antes, "Sem fornecedor no escopo/permissão não chama IA");
assert.equal((await executar({ resposta: { status: "incomplete" } })).status, 502);
assert.equal((await executar({ resposta: { error: { message: "Indisponível" } }, statusApi: 503 })).status, 502);
const timeout = new Error("timeout"); timeout.name = "TimeoutError";
assert.equal((await executar({ erroFetch: timeout })).status, 504);
console.log("Pesquisa XML: testes de fontes, correspondência, rota, escopo, permissões, correção humana, falhas e timeout aprovados.");

const componente = ts.transpileModule(fs.readFileSync("app/estoque/importar/FontesPesquisaCadastro.tsx", "utf8"), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX } }).outputText;
const componenteExports = {};
vm.runInNewContext(componente, { exports: componenteExports, require: (name) => { assert.equal(name, "react/jsx-runtime"); return jsxRuntime; } });
const render = (value) => renderToStaticMarkup(createElement(componenteExports.FontesPesquisaCadastro, { pesquisa: value }));
assert.equal(render(undefined), "");
assert.match(render(pesquisa.sanitizarPesquisaCadastroXml(pesquisaRaw, fontes)), /href="https:\/\/www.sick.com/);
assert.match(render(pesquisa.sanitizarPesquisaCadastroXml(pesquisaRaw, fontes)), /noopener noreferrer/);
assert.match(render(pesquisa.sanitizarPesquisaCadastroXml(null, [])), /não confirmada/);
assert.doesNotMatch(render({ ...pesquisa.sanitizarPesquisaCadastroXml(null, []), fontes: [{ url: "javascript:alert(1)", titulo: "ruim", dominio: "ruim" }] }), /href=/);
console.log("Interface de fontes: links clicáveis, segurança, ausência de resultado e sugestões legadas aprovados por renderização HTML.");

// Teste opcional real: uma consulta pública SICK; não acessa nem altera o banco.
if (process.argv.includes("--live")) {
  const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")]; }));
  const key = env.OPENAI_API_KEY || env.ASSISTENTE_IA_OPENAI_API_KEY;
  if (!key) throw new Error("Chave da API não configurada.");
  payloadReal.model = env.ASSISTENTE_IA_OPENAI_MODEL || "gpt-5.4-mini";
  const contexto = JSON.parse(payloadReal.input[1].content);
  contexto.catalogo_padrao_aprovado = fs.readFileSync("docs/padroes-cadastro/catalogo-paineis-eletricos.yaml", "utf8").split("\nhistorico_decisoes:")[0];
  payloadReal.input[1].content = JSON.stringify(contexto);
  const res = await fetch("https://api.openai.com/v1/responses", { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify(payloadReal), signal: AbortSignal.timeout(150_000) });
  const data = await res.json();
  if (!res.ok) throw new Error(`API respondeu ${res.status}: ${data.error?.message ?? "erro"}`);
  const textoResposta = data.output?.filter((o) => o.type === "message").flatMap((o) => o.content ?? []).map((c) => c.text ?? "").join("");
  const resposta = JSON.parse(textoResposta);
  const item = resposta.sugestoes?.find((s) => s.codigo === "1112263");
  const fontesReais = pesquisa.fontesPesquisaCadastroXml(data);
  const verificada = pesquisa.sanitizarPesquisaCadastroXml(item?.pesquisa_tecnica, fontesReais);
  const final = await executar({ resposta: data });
  assert.equal(final.status, 200);
  console.log(JSON.stringify({ status_api: data.status, modelo: payloadReal.model, sugestao_final: final.body.sugestoes[0] }, null, 2));
  assert.equal(data.status, "completed");
  assert.equal(verificada.status, "exato");
  assert.match(item.descricao_padronizada, /RFID/i);
  assert.doesNotMatch(item.descricao_padronizada, /SWITCH DE REDE/i);
}
