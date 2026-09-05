# Perfis de operação — matriz empírica de 63 combinações

## Resumo executivo

- Foram preservadas **63 combinações**, originadas de 368 itens válidos e 279 notas da auditoria de 483 DANFEs.
- O corte empírico de recorrência ficou em **6 notas**: 11 combinações atingem o corte e representam 195/279 notas (69,9%) e 259/368 itens (70,4%).
- Antes dos XMLs: 5 `AUTOMATICO`, 22 `REVISAO` e 36 `BLOQUEADO`. Depois da reconciliação: **0 `AUTOMATICO`, 27 `REVISAO` e 36 `BLOQUEADO`**.
- Foram encontrados XMLs de saída para 27 combinações; 36 ficaram sem XML correspondente e 6 apresentaram divergência interna.
- Os **63 perfis pertencem somente à SEG**. A SGU recebeu zero perfil. Todos estão com `habilitado_producao=false`.

Fonte preservada: [regras-nfe-63-combinacoes.csv](regras-nfe-63-combinacoes.csv).

## Modelo implementado

`f.perfil_operacao_evidencia` guarda a linha original, natureza, CFOP, origem, CST completo, alíquotas observadas no DANFE, redução, NCMs, notas de exemplo, volume e justificativa. Cada linha aponta para seu perfil em `f.perfil_operacao`.

Os perfis usam códigos estáveis `CSV63-001` a `CSV63-063`. A natureza funcional foi mantida isolada como `MATRIZ_CSV63_NNN`, impedindo que a carga histórica seja selecionada acidentalmente pelo fluxo antigo.

O payload passou a validar:

- perfil bloqueado nunca monta payload;
- perfil em revisão exige confirmação humana na solicitação;
- produção exige ainda `habilitado_producao=true`;
- origem do item deve coincidir com a origem do perfil;
- CRT normal usa CST; Simples Nacional usa CSOSN;
- IPI tributado (`50` ou `99`) sem alíquota revisada na TIPI é bloqueado;
- PIS/COFINS tributados sem alíquota unânime nos XMLs são bloqueados;
- redução usa **70,588% da base integral**, equivalente a 29,412% de redução, e exige `cBenef`.

Há também trava no banco em `f.documento_fiscal_emissao`, independente da Edge Function. Portanto, habilitar a variável de produção sem liberar o perfil não abre emissão real.

## Benefício fiscal

Nos perfis que a matriz marca com base reduzida foram gravados:

- base resultante: `70,5880%` da base integral;
- redução: `29,4120%`;
- `cBenef`: `SC820006`;
- texto: `BASE DE CALCULO REDUZIDA - PRODUTOS DA INDUSTRIA DE AUTOMACAO, INFORMATICA E TELECOMUNICACOES, CONFORME DISPOE A ALINEA A DO ARTIGO 7, INCISO VII DO ANEXO 2 DO RICMS/SC.`

O NCM `85444900` permanece bloqueado quando beneficiado. A função efetiva do cabo precisa ser comprovada; NCM sozinho não basta, conforme a [Resolução Normativa COPAT 90/2025](https://legislacao.sef.sc.gov.br/Consulta/Views/Publico/DocumentoLegalViewer.ashx?id=B8014404-6557-4668-BE72-8B490501619E).

## Reconciliação dos XMLs de saída

A extração foi executada em produção somente sobre XMLs de saída da SEG, agrupando por natureza + CFOP + origem + CST de ICMS. Foram extraídos CST e alíquota de PIS/COFINS, CST de IPI, `cBenef` e presença de FCI.

Resultado:

- 27/63 combinações com XML correspondente;
- 36/63 sem XML correspondente;
- 6 combinações divergentes: `CSV63-001`, `003`, `010`, `012`, `028` e `046`;
- nenhum conjunto beneficiado apresentou `SC820006` de forma unânime; nos XMLs correspondentes o campo estava ausente;
- `CSV63-001` e `003`: PIS apareceu com 0% e 1,65%; IPI CST 50;
- `CSV63-010` e `046`: IPI alternou entre CST 50 e 51;
- `CSV63-012` e `028`: PIS alternou 0%/1,65%, COFINS 0%/7,6% e não houve CST de IPI extraível.

O `SC820006` continua cadastrado porque é a regra atual fornecida para a nova emissão, mas a ausência nos XMLs históricos ficou registrada como divergência de prática. Nenhum desses perfis está liberado em produção.

## Separações preservadas

- CST 50 (suspensão) e CST 51 (diferimento) permanecem combinações distintas.
- Conserto usa 5915/6915 e 5916/6916; industrialização usa 5901/5902.
- Estornos mantêm os CFOPs históricos 1102, 1201, 1202, 1915 e 2202 em perfis separados; não existe fallback fixo para 1102.
- Nenhuma alíquota de IPI foi copiada do DANFE para o perfil.
- O texto de industrialização referencia o [RIPI/2010, Decreto 7.212/2010](https://www.planalto.gov.br/ccivil_03/_ato2007-2010/2010/decreto/d7212.htm), em campo editável e com validação final ainda obrigatória.

## Decisões humanas por combinação

Legenda: `P` = definir produzido/revendido pelo cadastro; `I` = revisar IPI/TIPI; `C` = comprovar elegibilidade do cabo; `R` = combinação rara; `X0` = sem XML correspondente; `XD` = XML divergente; `XIPI` = recorrente rebaixada porque o XML não fechou IPI não tributado.

| Perfil | Natureza | CFOP/origem/CST | Faixa | Falta |
|---|---|---|---|---|
| CSV63-001 | Venda mercadoria terceiros | 5102/2/20 | BLOQUEADO | I, P, XD |
| CSV63-002 | Venda industrialização interna | 5101/0/00 | BLOQUEADO | P |
| CSV63-003 | Venda mercadoria terceiros | 5102/2/20 | BLOQUEADO | I, P, XD |
| CSV63-004 | Venda mercadoria terceiros | 5102/0/00 | BLOQUEADO | P |
| CSV63-005 | Retorno mercadoria industrialização | 5902/0/50 | REVISAO | XIPI, X0 |
| CSV63-006 | Remessa industrialização encomenda | 5901/0/50 | REVISAO | XIPI, X0 |
| CSV63-007 | Outras saídas fora do estado | 6949/0/90 | REVISAO | XIPI, X0 |
| CSV63-008 | Venda mercadoria terceiros | 5102/0/00 | BLOQUEADO | P |
| CSV63-009 | Outras saídas dentro do estado | 5949/0/90 | REVISAO | XIPI, X0 |
| CSV63-010 | Venda mercadoria terceiros | 5102/0/20 | BLOQUEADO | P, C, XD |
| CSV63-011 | Retorno de conserto interno | 5916/0/50 | REVISAO | XIPI, X0 |
| CSV63-012 | Venda mercadoria terceiros | 6102/0/00 | BLOQUEADO | P, XD |
| CSV63-013 | Venda mercadoria terceiros | 6102/2/00 | BLOQUEADO | I, P |
| CSV63-014 | Venda mercadoria terceiros | 6102/2/00 | BLOQUEADO | I, P |
| CSV63-015 | Remessa por conta e ordem | 6923/0/90 | REVISAO | R, X0 |
| CSV63-016 | Venda mercadoria terceiros | 5101/0/00 | BLOQUEADO | P |
| CSV63-017 | Remessa para conserto interna | 5915/0/50 | REVISAO | R, X0 |
| CSV63-018 | Remessa para conserto externa | 6915/0/50 | REVISAO | R, X0 |
| CSV63-019 | Venda industrialização interna | 5101/0/00 | BLOQUEADO | I, P |
| CSV63-020 | Venda industrialização interna | 5101/0/00 | BLOQUEADO | P |
| CSV63-021 | Venda mercadoria terceiros | 5102/0/00 | BLOQUEADO | I, P |
| CSV63-022 | Devolução compra industrialização | 5201/0/00 | BLOQUEADO | I, X0 |
| CSV63-023 | Devolução compra industrialização | 5201/0/00 | REVISAO | R, X0 |
| CSV63-024 | Devolução compra industrialização | 5201/0/20 | REVISAO | R, X0 |
| CSV63-025 | Devolução compra industrialização | 5201/0/90 | REVISAO | R, X0 |
| CSV63-026 | Venda industrialização externa | 6101/0/00 | BLOQUEADO | P |
| CSV63-027 | Venda industrialização externa | 6101/0/00 | BLOQUEADO | P |
| CSV63-028 | Venda mercadoria terceiros | 6102/0/00 | BLOQUEADO | P, XD |
| CSV63-029 | Venda por conta e ordem | 6119/2/00 | BLOQUEADO | I, P |
| CSV63-030 | Devolução compra industrialização | 6201/1/00 | REVISAO | R, X0 |
| CSV63-031 | Devolução compra industrialização | 6201/2/00 | REVISAO | R, X0 |
| CSV63-032 | Estorno fora do prazo | 1102/0/00 | REVISAO | R, X0 |
| CSV63-033 | Estorno fora do prazo | 1102/0/00 | BLOQUEADO | I, X0 |
| CSV63-034 | Devolução de venda industrializada | 1201/0/00 | REVISAO | R, X0 |
| CSV63-035 | Estorno fora do prazo | 1201/0/51 | REVISAO | R, X0 |
| CSV63-036 | Devolução de venda de terceiros | 1202/0/00 | REVISAO | R, X0 |
| CSV63-037 | Estorno fora do prazo | 1202/0/00 | REVISAO | R, X0 |
| CSV63-038 | Devolução de venda de terceiros | 1202/0/20 | BLOQUEADO | C, X0 |
| CSV63-039 | Estorno de remessa para conserto | 1915/0/50 | REVISAO | R, X0 |
| CSV63-040 | Estorno fora do prazo | 2202/1/00 | REVISAO | R, X0 |
| CSV63-041 | Estorno fora do prazo | 2202/2/00 | REVISAO | R, X0 |
| CSV63-042 | Outra entrada não especificada | 2949/0/90 | REVISAO | R, X0 |
| CSV63-043 | Venda industrialização interna | 5101/0/00 | BLOQUEADO | I, P |
| CSV63-044 | Venda mercadoria/industrialização | 5101/0/51 | BLOQUEADO | P |
| CSV63-045 | Venda industrialização interna | 5101/0/51 | BLOQUEADO | P, X0 |
| CSV63-046 | Venda mercadoria terceiros | 5102/0/20 | BLOQUEADO | I, P, XD |
| CSV63-047 | Venda mercadoria terceiros | 5102/0/51 | BLOQUEADO | P |
| CSV63-048 | Venda mercadoria terceiros | 5102/2/00 | BLOQUEADO | I, P |
| CSV63-049 | Venda mercadoria terceiros | 5102/2/00 | BLOQUEADO | I, P |
| CSV63-050 | Venda mercadoria terceiros | 5102/2/00 | BLOQUEADO | I, P |
| CSV63-051 | Venda mercadoria terceiros | 5102/2/00 | BLOQUEADO | I, P |
| CSV63-052 | Devolução compra industrialização | 5201/0/00 | BLOQUEADO | I, X0 |
| CSV63-053 | Devolução compra industrialização | 5201/1/00 | BLOQUEADO | I, X0 |
| CSV63-054 | Devolução compra industrialização | 5201/2/00 | BLOQUEADO | I, X0 |
| CSV63-055 | Devolução compra | 5553/2/20 | REVISAO | R, X0 |
| CSV63-056 | Venda industrialização externa | 6101/0/00 | BLOQUEADO | I, P |
| CSV63-057 | Venda por conta e ordem | 6119/0/00 | BLOQUEADO | P |
| CSV63-058 | Devolução compra industrialização | 6201/1/00 | BLOQUEADO | I, X0 |
| CSV63-059 | Devolução compra industrialização | 6201/1/00 | BLOQUEADO | I, X0 |
| CSV63-060 | Devolução material de uso/consumo | 6556/2/00 | REVISAO | R, X0 |
| CSV63-061 | Retorno de conserto externo | 6916/0/50 | REVISAO | R, X0 |
| CSV63-062 | Remessa para conserto externa | 6949/0/50 | REVISAO | R, X0 |
| CSV63-063 | Remessa para destruição | 6949/0/90 | REVISAO | R, X0 |

## Validação e implantação

- `supabase db reset --local`: passou do zero com as migrations até `20260901144000`.
- Smokes SQL de integridade referencial, pipeline e RLS: passaram; a evidência respeita tenant e empresa.
- Teste local do payload: passou, incluindo revisão humana, base resultante 70,588%, `SC820006`, origem e bloqueio.
- `tsc --noEmit`, ESLint dos arquivos alterados e `git diff --check`: passaram.
- `supabase db lint --local --level error`: permanecem os mesmos 10 erros preexistentes do baseline; nenhum veio destas migrations.
- Dry-run remoto conferido; migrations `142`, `143` e `144` aplicadas.
- Extração dos XMLs executada e Edge Function `nfe-emitir` republicada.
- Dry-run final deve retornar banco atualizado antes do encerramento.
