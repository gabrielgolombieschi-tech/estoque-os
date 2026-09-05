# Inventário — NFS-e Padrão Nacional a partir da OS, pela Focus (Parte 0)

**Data de leitura:** 05/09/2026. **Plano de referência:** o arquivo `claude/plano-nfse-os-focus.md` citado na tarefa **não existe** no repositório nem em `.claude/` (só há `settings.local.json`). O mapa do payload (§5) e os cenários (§9) foram tomados do próprio texto da tarefa e da documentação da Focus lida nesta data; as "perguntas 13 a 20 do plano" estão renumeradas no relatório de homologação.

## 1. O que a NF-e da OS gravou e o que a NFS-e reaproveita

| O quê | Onde | Observação |
|---|---|---|
| Solicitação | `f.solicitacao_faturamento` (status `RASCUNHO/PREVIA/APROVADA/EMITIDA/CANCELADA`, `cliente_id`, `natureza_operacao`, `pedido_cliente`, pagamento `pagamento_forma/indicador/parcelas`, snapshots `emitente/destinatario/operacao`, `revisao_fiscal_confirmada_em`, `perfil_operacao_id`) | Criada por `f.fn_solicitacao_faturamento_criar_os_livre(tenant, empresa, os_id, linhas, natureza)` |
| Linhas por valor | `f.solicitacao_item` (`origem_tipo='OS'`, `origem_id=os.id::text`, `item_id`, `descricao`, `quantidade`, `valor_unitario`, campos fiscais por linha, `perfil_operacao_id`, `tributacao_fonte`) | A OS de cada linha é `origem_id`; por isso "duas OS do mesmo tomador numa nota" já cabe no modelo: uma linha por OS |
| Reserva e saldo | `f.fn_os_saldo_a_faturar(tenant, empresa, os_id)` → `valor_pedido` (orçado ou HH), `valor_faturado` (documento `EMITIDA`, ou importado sem status; NFS-e conta `valor_total` quando `nfse_status='EMITIDA'`), `valor_reservado` (solicitações não canceladas cuja emissão mais recente está em `RASCUNHO/ENVIANDO/PROCESSANDO/AUTORIZADA` sem documento EMITIDA; `REJEITADA/ERRO/CANCELADA` não somam), `saldo` | Já soma `si.origem_id = os` por linha; multi-OS funciona sem mudança |
| Documento + emissão | `f.fn_nfe_preparar_documento_solicitacao`: `f.documento_fiscal` (`modelo='55'`, `natureza='PRODUTO'`, `nfe_status='RASCUNHO'`, `origem='EMITIDO'`, `os_id_import`), `f.documento_fiscal_item`, `f.documento_fiscal_emissao` (`referencia_externa='NFEH-<sol>'`, `ambiente`, `status`) | Idempotente por advisory lock na referência |
| Claim/envio/retorno | `f.fn_nfe_homologacao_claimar`, `f.fn_nfe_registrar_envio`, `f.fn_nfe_aplicar_retorno` (homologação: documento fica `RASCUNHO`, sem AR) | Genéricas sobre `documento_fiscal_emissao`; `fn_nfe_registrar_envio` e `fn_nfe_contexto_emissao` servem à NFS-e sem alteração. O claim **não** serve porque exige payload idêntico no retry, e a NFS-e precisa trocar o `numero_dps` depois de uma rejeição |
| Cancelamento | `f.fn_nfe_cancelamento_homologacao_claim/finalizar` (claim durável em `documento_fiscal_evento`) | Padrão copiado para `fn_nfse_cancelamento_*` |
| Abandono de homologação | `f.fn_solicitacao_nfe_abandonar_homologacao` | Genérica (guard `f.abandono_homologacao`); a NFS-e reaproveita e só acrescenta o log da DPS |

## 2. Como `f.documento_fiscal` distingue NFS-e de NF-e

`public.import_nfse_saida_com_os` (que valida o saldo pela mesma `fn_os_saldo_a_faturar`) delega a `public.import_nfse_saida` e grava: `modelo = 'NFSE'`, `natureza = 'SERVICO'`, `operacao = 'SAIDA'`, `origem = 'IMPORTADO'`, `nfse_status = 'EMITIDA'`, `valor_servicos` (bruto), **`valor_total` = líquido** (ex.: NFS-e 39: 10.340,00 bruto, 9.187,09 líquido), `nfse_municipio_codigo`, `nfse_codigo_verificacao`, `servico_discriminacao`, `competencia_date` (dia 1, check `ck_documento_fiscal__competencia_day1`). NF-e usa `modelo='55'`, `natureza='PRODUTO'`, `nfe_status`. Há 222 NFS-e importadas (set/2025–ago/2026). O discriminador reaproveitado é `modelo='NFSE' + natureza='SERVICO' + nfse_status`; o AR já nasce do líquido porque o trigger `trg_documento_fiscal__ar_nfse` → `f.fn_upsert_ar_from_documento_fiscal_v2` usa `valor_total`.

Guardas existentes que a NFS-e emitida herda: `aaa_nfe_bloquear_documento_dml_direto` (só bloqueia `modelo='55'` EMITIDA direto e alterações de documento vinculado a emissão por usuário autenticado), `trg_documento_fiscal_venda_credito` (reage a `nfse_status`), `trg_nfse_sync_piscofins_from_doc` (débito de PIS/COFINS a partir de `valor_servicos`).

## 3. `f.perfil_operacao` após a revisão da fundação

Já tem `modelo` (check `NFE|NFSE`), `item_servico`, `nbs`, `cst_pis/cst_cofins/aliquota_pis/aliquota_cofins`, `consumidor_final`, `cst_ibs_cbs/cclass_trib/ibs_cbs_json`, vigência, `faixa_automacao`, `habilitado_producao`, revisão/liberação auditadas. **Não tem** os campos de serviço: código de tributação nacional/municipal, NBS por código (só texto `nbs`), descrição padrão, regra de local de prestação, tributação/alíquota/retenção de ISS, regras de PCC/IRRF/INSS, dedução de material, texto complementar. Não há nenhuma linha `modelo='NFSE'`. Cabe estender a própria tabela (sem tabela irmã): as colunas novas são nulas para NF-e. Restrições relevantes ao inserir perfis vazios: `codigo`, `nome`, `modelo`, `natureza_operacao`, `crt` (`'1'|'2'|'3'`) obrigatórios; `faixa_automacao='BLOQUEADO'` exige `habilitado_producao=false`; unicidade `(tenant, empresa, codigo, vigencia_inicio)`.

## 4. `c.empresa_fiscal`

Colunas: `inscricao_municipal` (existe; **vazia** para Elétrica Segau; a linha da SGU AUTOMAÇÃO tem `152836`, o mesmo número que a tarefa atribui à Segau — conferir), `cnae_principal 4321500`, `regime_tributario 'Regime Normal'`, `crt 3`, `serie_nfe 2`, `email_fisco`, `certificado_validade_em`. **Não tem** série/número da DPS, opção Simples, regime especial nem prazo de cancelamento. O código IBGE da empresa está em `c.empresa_endereco` (tipo `FISCAL`, `codigo_municipio_ibge = 4209102`, CEP 89219600) e é o que o snapshot da NF-e já usa; não é duplicado em `empresa_fiscal`.

## 5. Retenção no título

`f.titulo` (tipo AR, `valor_total`, `valor_aberto`, `documento_fiscal_id`, `os_id`) e `f.titulo_parcela` não têm retenção. Existe `f.imposto_retencao (titulo_id, documento_fiscal_id, imposto, base_calculo, aliquota, valor_calculado, valor_ajustado, vencimento_date)`, com **zero linhas** para as NFS-e de julho/agosto, e `f.documento_fiscal_imposto` (`imposto`, `natureza DEBITO|RETENCAO`) com apenas 1 linha de ISS `RETENCAO` em 2026. A tarefa pede `f.titulo_retencao` por tributo; ela é criada nova e alimentada só pelo pipeline da NFS-e emitida. `f.imposto_retencao` continua com o uso que já tem.

## 6. Documentação da Focus (lida em 05/09/2026)

| Pergunta | Resposta | Fonte |
|---|---|---|
| `serie_dps` e `numero_dps` são obrigatórios? | **Sim, ambos obrigatórios**: `serie_dps` Integer[5], "faixa de utilização para API: 00001 a 49999"; `numero_dps` Integer[15]. A Focus não numera; o ERP numera. O emissor antigo usa série **70000**, fora da faixa da API, por isso a série do ERP é outra (proposta: 2) | https://campos.focusnfe.com.br/nfse_nacional/EmissaoDPSXml.html |
| Endpoints | `POST /v2/nfsen?ref=<ref>` (202 `processando_autorizacao`; 400 síncrono `codigo/mensagem`; 422 `erro_validacao`, ex.: "Já existe um DPS com esta referência") · `GET /v2/nfsen/<ref>` (status `processando_autorizacao|autorizado|negado|cancelado|erro_autorizacao`, campos `numero`, `codigo_verificacao`, `data_emissao`, `url`, `url_danfse`, `caminho_xml_nota_fiscal`, `caminho_xml_cancelamento`, `erros[{codigo,mensagem,correcao}]`, `numero_rps/serie_rps/tipo_rps`) · `DELETE /v2/nfsen/<ref>` corpo `{justificativa}` (síncrono: `cancelado` ou `erro_cancelamento` + `erros`; ex. `V999 NFSe fora do prazo de cancelamento permitido`) · `POST /v2/nfsen/<ref>/hook` reenvia a notificação | doc.focusnfe.com.br/reference/{emitir_dps_nacional, consultar_nfse_nacional, cancelar_nfse_nacional, reenviar_hook_nfsen}.md |
| Evento do webhook | `event = "nfsen"` em `POST /v2/hooks` (`{cnpj, event, url, authorization?, authorization_header?}` → `{id,...}`) | doc.focusnfe.com.br/reference/criar_webhook.md |
| Base URL de homologação | `https://homologacao.focusnfe.com.br/v2` (produção `https://api.focusnfe.com.br/v2`) | servers do OpenAPI |
| Substituição | Nova DPS com `chave_nfse_substituida` (String[50]), `codigo_justificativa_substituicao` (`01..05`, `99`), `motivo_substituicao` (15–255) | campos EmissaoDPSXml |
| Campos que a tarefa cita | Confirmados com o nome exato: `data_emissao`, `data_competencia`, `emitente_dps` (1), `codigo_municipio_emissora`, `codigo_municipio_prestacao`, `finalidade_emissao` (0), `consumidor_final` (0/1), `indicador_destinatario` (0), `cnpj_prestador`, `inscricao_municipal_prestador`, `razao_social_prestador`, endereço `*_prestador`, `codigo_opcao_simples_nacional` (1 = não optante), `regime_especial_tributacao` (0), `cnpj_tomador`, `inscricao_municipal_tomador`, `razao_social_tomador`, `codigo_municipio_tomador`, `cep_tomador`, `logradouro_tomador`, `numero_tomador`, `complemento_tomador`, `bairro_tomador`, `email_tomador`, `codigo_tributacao_nacional_iss`, `codigo_tributacao_municipal_iss`, `codigo_nbs`, `descricao_servico` (≤1000), `codigo_interno_contribuinte` (≤20), `pedido_compra` (≤60) + `itens_pedido_compra[{numero_item_compra}]`, `valor_servico`, `tributacao_iss` (1), `tipo_retencao_iss` (1 não retido / 2 tomador), `percentual_aliquota_relativa_municipio` (fornecida pelo sistema quando o município está no Sistema Nacional), `situacao_tributaria_pis_cofins`, `aliquota_pis`, `aliquota_cofins`, `tipo_retencao_pis_cofins` (0..9), `valor_cp` (INSS), `valor_irrf`, `valor_csll` (**soma PIS+COFINS+CSLL retidos**, por adequação à reforma), `ibs_cbs_situacao_tributaria`, `ibs_cbs_classificacao_tributaria`, `informacoes_complementares` (≤2000) | idem |
| Homologação da NFS-e Nacional | A documentação não diz se o ambiente de homologação exige habilitação no painel. A chamada fica atrás de `FOCUS_NFSE_NACIONAL_ENABLED` (Supabase secret) até o Gabriel confirmar no painel | — |

## 7. Emissor antigo e notas de referência (jul–ago/2026)

XML das NFS-e 35, 37 e 39 lidos de `f.documento_fiscal_xml`: DPS série 70000, `tpEmit 1`, `opSimpNac 1`, `regEspTrib 0`, `cLocEmi 4209102`, tomador com `endNac` (cMun+CEP) e endereço, `cTribNac` + `xDescServ` + `cNBS`, `tribISSQN 1`, `tpRetISSQN 1|2`, PIS/COFINS `CST 01` + `tpRetPisCofins 0|3`, `vRetIRRF`, `vRetCSLL` (soma), `vRetCP` (INSS 11% na 07.02), `vTotTrib*`; a 37 (obra 07.02) traz `obra/end` e grupo `IBSCBS` (`CST 000`, `cClassTrib 000001`, 0,10/0,00/0,90). Combinações observadas desde maio/2026:

| cTribNac | NBS | ISS | Onde | Retenções observadas |
|---|---|---|---|---|
| 140601 (14.06 instalação/montagem) | 120032900 | 5% (Joinville) | sede ou planta do cliente (Tijucas 4218004, Guaramirim, Bataguassu, Marechal Deodoro) | nenhuma (Portobello/Uniplast/Siemens); INSS 11% em algumas WEG |
| 170901 (17.09 laudos/perícias) | 114044900 | 5% | Joinville | ISS retido + IRRF 1,5% + PIS/COFINS/CSLL 4,65% (INCASA, TOX, Inoxsul) |
| 170601 (17.06 assessoria) | ver fixture | 5% | Joinville | INCASA (retido) |
| 140101 (14.01 manutenção) | ver fixture | 5% | Tijucas / Guaramirim | Portobello sem retenção; WEG com INSS |
| 070201 (07.02 obra) | 101069000 | 3% (São Francisco do Sul) | planta do cliente | ISS retido + INSS 11% (ArcelorMittal) — perfil nasce BLOQUEADO |

Discriminação real (ordem observada): `<DESCRIÇÃO>. PEDIDO DE COMPRA: <n>. VENCIMENTO: <n> DDL. OS <n>. "<texto de retenção>"`. O texto de retenção usado nas notas reais: sem retenção `"NÃO HÁ INCIDÊNCIA DAS RETENÇÕES FEDERAIS CONFORME IN SRF N° 459/2004"`; com retenção `"PARA OS SERVIÇOS DE LAUDOS E PERICIAS, DEVERÁ SER RETIDO IRRF A ALÍQUOTA DE 1,5% E CRF A ALÍQUOTA DE 4,65% (PIS 0,65%;COFINS 3,0%;CSLL 1%). TRIBUTOS INCIDENTES SOBRE O PREÇO LEI 12/2012"`.

## 8. Lista de ISS retido por tomador (jul–ago/2026, sem gravar `clientes.iss_retido`)

Fonte: `tpRetISSQN` e tags de retenção do XML importado. Gerada por `scripts/nfse-retencoes-por-tomador.mjs`.

| Cliente | Tomador | Notas | ISS retido | ISS não retido | IRRF | PCC | INSS | Sugestão (não gravada) |
|---|---|---|---|---|---|---|---|---|
| 1 | PORTOBELLO SA (Tijucas) | 18 | 0 | 16 | 0 | 0 | 0 | `iss_retido=false`, sem federais |
| 3 | INCASA S/A (Joinville) | 8 | 5 | 3 | 5 | 5 | 0 | retém nos laudos (17.09/17.06); não retém no 14.06 → decidir por serviço |
| 43 | WEG TINTAS (Guaramirim) | 7 | 4 | 2 | 0 | 0 | 4 | mista; INSS em obras/instalação |
| 94 | REGIONAL TELHAS (Bataguassu/MS) | 3 | 0 | 3 | 0 | 0 | 0 | `iss_retido=false` |
| 75 | TOX PRESSOTECHNIK (Joinville) | 2 | 2 | 0 | 2 | 2 | 0 | `iss_retido=true`, IRRF+PCC |
| 42 | ARCELORMITTAL (São Francisco do Sul) | 1 | 1 | 0 | 0 | 0 | 1 | `iss_retido=true`, INSS 11% (obra) |
| 89 | UNIPLAST (Joinville) | 1 | 0 | 1 | 0 | 0 | 0 | `iss_retido=false` |
| 36 | SIEMENS HEALTHCARE (Joinville) | 1 | 0 | 1 | 0 | 0 | 0 | `iss_retido=false` |
| 230 | KRONA (Marechal Deodoro/AL) | 1 | 0 | 1 | 0 | 0 | 0 | `iss_retido=false` |
| 314 | INOXSUL (Joinville) | 1 | 1 | 0 | 1 | 1 | 0 | `iss_retido=true`, IRRF+PCC |

Conclusão: a retenção depende do **serviço** tanto quanto do tomador (INCASA e WEG retêm em uns e não em outros). Por isso a regra do perfil é `POR_TOMADOR` e o cadastro do cliente decide; onde o cliente ainda não decidiu, a tela bloqueia e pede a decisão com justificativa.

## Decisões de desenho que saem deste inventário

- `f.os_faturamento` citado na tarefa não existe; os campos pedidos (perfil de serviço, município de prestação, competência, pedido/item) entram em `f.solicitacao_faturamento`, que é a tabela que a NF-e da OS já usa. `pedido_cliente` existe; `pedido_item` é criado.
- O modelo (`NFE|NFSE`) entra na **linha** (`f.solicitacao_item.modelo`) e na emissão (`f.documento_fiscal_emissao.modelo`); o documento continua distinguido por `modelo/natureza`.
- Tudo que é compartilhado (`fn_nfe_registrar_envio`, `fn_nfe_contexto_emissao`, `fn_solicitacao_nfe_abandonar_homologacao`, `nfe-ciclo ARQUIVO`, `nfe-reconciliar`) é usado sem mudar comportamento da NF-e; o que precisa de comportamento diferente (claim com renumeração da DPS, retorno, cancelamento, trava de produção) ganha função própria `fn_nfse_*`. A única função de NF-e alterada é `f.fn_nfe_producao_pronta`, que ganha um desvio no início para solicitações com linha NFS-e (baseline no cabeçalho da migration).
- Homologação continua não criando título (decisão A de 02/09/2026): o título líquido com `f.titulo_retencao` é criado pelo caminho de produção de `fn_nfse_aplicar_retorno`, provado no teste SQL com rollback, como foi feito na NF-e.
- Prazo de cancelamento vazio: em **produção** o botão não aparece; em **homologação** o cancelamento continua disponível com aviso, para os cenários poderem rodar.
