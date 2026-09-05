# NF-e — homologação, auditoria e preparação de produção

**Estado em 02/09/2026:** a NF-e piloto foi autorizada em homologação e o caminho de produção está implantado, porém permanece protegido. Produção não foi habilitada porque faltam três dados reais: credencial própria da Focus, validade do certificado digital e perfil fiscal explicitamente aprovado.

## Resultado do piloto

- OV: `OV-SEG-00004-026` (ID 344), cliente Portobello S.A.
- Solicitação: `bd138fb9-126f-4396-a228-b957c6ad3669`.
- Referência idempotente: `NFEH-bd138fb9-126f-4396-a228-b957c6ad3669`.
- Resultado: `AUTORIZADA`, `cStat 100`, série 2, número 1.
- Chave: `42260913671448000189550020000000011615133155`.
- Protocolo: `342260000892595`.
- Valor: R$ 4.563,40, lido do preço de venda salvo no rascunho — não do custo de R$ 1.650,00 da linha da OV.
- XML: 7.891 bytes; hash do banco igual ao arquivo do Storage; protocolo, IBS e CBS presentes.
- DANFE: 7.778 bytes, cabeçalho PDF válido, armazenado em bucket privado.

## Conferências do efeito contábil e operacional

Homologação é sem valor fiscal. Por isso, a autorização piloto:

- não alterou `f.documento_fiscal.nfe_status` para `EMITIDA`;
- não criou Contas a Receber nem Contas a Pagar;
- não consumiu o saldo comercial da OV;
- não criou outra movimentação de estoque — a única baixa já ocorreu quando o material foi lançado na OV;
- gravou o snapshot tributário e cinco grupos: ICMS, PIS, COFINS, IBS e CBS.

Valores auditados no piloto:

| Tributo | Base | Alíquota | Valor |
|---|---:|---:|---:|
| ICMS | R$ 4.563,40 | 12,00% | R$ 547,61 |
| PIS | R$ 4.563,40 | 1,65% | R$ 75,30 |
| COFINS | R$ 4.563,40 | 7,60% | R$ 346,82 |
| IBS | R$ 4.563,40 | 0,0999% efetiva | R$ 4,56 |
| CBS | R$ 4.563,40 | 0,90% | R$ 41,07 |

O cenário transacional de produção foi executado localmente com `ROLLBACK`. Ele provou:

- autorização idempotente, inclusive após uma rejeição e nova conferência;
- exatamente um Contas a Receber e zero Contas a Pagar;
- documento com `nfe_status='EMITIDA'` e competência preenchida;
- XML único e cinco grupos tributários;
- saldo por item e por valor zerados;
- nenhuma baixa duplicada de estoque.

Uma NF-e de saída gera **Contas a Receber**. Contas a Pagar pertence ao fluxo de compra/entrada por XML; criar AP nessa venda seria erro.

## Separação entre homologação e produção

- Homologação usa apenas `FOCUS_NFE_TOKEN_HOMOLOGACAO`, `FOCUS_NFE_HOMOLOGACAO_ENABLED` e a URL `https://homologacao.focusnfe.com.br`.
- Produção usa apenas `FOCUS_NFE_TOKEN_PRODUCAO`, `FOCUS_NFE_PRODUCAO_ENABLED` e a URL `https://api.focusnfe.com.br`.
- `FOCUS_NFE_AMBIENTE` não escolhe mais o destino e não permite fallback entre ambientes.
- O callback de produção tem endpoint e secret próprios: `nfe-callback-producao` e `FOCUS_NFE_WEBHOOK_TOKEN_PRODUCAO`.
- A mesma solicitação pode possuir uma emissão por ambiente. A referência é `NFEH-...` em homologação e `NFEP-...` em produção.
- O payload de homologação usa a razão social obrigatória de “sem valor fiscal”. O payload de produção usa o nome real do destinatário; há teste automatizado para essa separação.

## O que ainda bloqueia produção

Leitura remota feita em 02/09/2026:

1. `FOCUS_NFE_TOKEN_PRODUCAO` não existe.
2. `FOCUS_NFE_PRODUCAO_ENABLED` não existe/está desligada.
3. A validade do certificado digital da SEG não está registrada em `c.empresa_fiscal.certificado_validade_em`.
4. Existem 0 perfis com `habilitado_producao=true` e nenhum perfil para `VENDA_MERCADORIA_TERCEIROS`.

Enquanto qualquer item estiver pendente, o botão de produção não aparece. A tela informa o motivo atual. Não se deve copiar o token de homologação, inventar validade de certificado nem converter os campos digitados no piloto em aprovação fiscal permanente.

Quando os dados reais estiverem disponíveis, a liberação é:

```powershell
npx supabase secrets set FOCUS_NFE_TOKEN_PRODUCAO="<token-real>" FOCUS_NFE_PRODUCAO_ENABLED=true FOCUS_NFE_WEBHOOK_TOKEN_PRODUCAO="<token-aleatorio>"
```

Depois: registrar a validade real do A1, aprovar um perfil fiscal vigente para a empresa/natureza/CRT e repetir a consulta de prontidão. A primeira emissão real continua exigindo confirmação humana na própria OV.

## Validações finais

- Backup físico remoto `COMPLETED` em 02/09/2026 13:27:25 UTC.
- `supabase db reset --local`: passou do zero até a migration `20260902133000`.
- Cinco testes SQL: pipeline, faturamento parcial, OS × OV, ciclo de vida e RLS autenticada — todos passaram e terminaram em `ROLLBACK`.
- Teste isolado do builder: 16 cenários, incluindo destinatário distinto por ambiente — passou.
- `tsc --noEmit` e ESLint dos arquivos do fluxo — passaram.
- `db lint --linked --level error`: os mesmos 10 erros do baseline, nenhum erro novo.
- Migrations remotas alinhadas até `20260902133000`.
- Functions ativas: `nfe-emitir`, `nfe-emitir-producao`, `nfe-reconciliar`, `nfe-callback`, `nfe-callback-producao` e `nfe-ciclo`.
- Rotas validadas sem erro de runtime: central NF-e, importação de NF-e, OS, Gestão de Cobranças e OVs.
- Auditoria remota pós-push: saldo da OV piloto voltou a 1 unidade/R$ 4.563,40; XML e DANFE continuam íntegros; nenhuma escrita de teste foi feita em produção.

## Contrato externo consultado

- [Emitir NF-e](https://doc.focusnfe.com.br/reference/emitir_nfe)
- [Consultar NF-e](https://doc.focusnfe.com.br/reference/consultar_nfe)
- [Ambientes Focus](https://doc.focusnfe.com.br/reference/ambiente)
- [Autenticação HTTP Basic](https://doc.focusnfe.com.br/reference/autenticacao)
- [Campos da NF-e](https://campos.focusnfe.com.br/nfe/NotaFiscalXML.html)

## Revisão da NF-e série 2 nº 1 — 03/09/2026

A revisão do XML autorizado da chave `42260913671448000189550020000000011615133155` confirmou, sem qualquer nova implementação de IBS/CBS:

- o grupo `gIBSCBS` foi enviado;
- a tag `cClassTrib` foi enviada com o valor `000001`;
- o snapshot auditável registrou `cst_ibs_cbs=000` e versão `NT 2025.002 v1.34`;
- os grupos `gIBSUF` e `gCBS` também estão presentes;
- o XML armazenado possui 7.891 bytes e SHA-256 idêntico ao registro auditado no banco.

Correções implementadas no pipeline de homologação:

- `dhEmi` e `dhSaiEnt` são gerados em `America/Sao_Paulo`, com offset explícito `-03:00`; o teste fixa `2026-09-02T21:56:09Z` e comprova a saída `2026-09-02T18:56:09-03:00`;
- `natOp` é resolvida por uma fixture provisória com as nove naturezas observadas no levantamento de agosto/2026, todas com texto humano de no máximo 60 caracteres;
- não existe fallback para origem da mercadoria: ausência bloqueia a emissão identificando o código do item e o campo;
- `infCpl` reúne o texto de benefício fiscal da fixture, o pedido de compra da OV e a chave referenciada quando houver;
- no CFOP `5102`, a fixture provisória define `CST IPI=53` e `cEnq=999`; o cadastro do item permanece sem `cEnq` e tentativas de gravá-lo ali falham nomeando item e campo;
- a compatibilidade CST IPI × `cEnq` aplica a regra da rejeição 388: `02/52 → 301–399`, `04/54 → 001–099`, `05/55 → 101–199` e demais CST → `601–608` ou `999`;
- sem ocorrência de transporte, `modFrete` é `9`, transportador e volumes ficam nulos e o grupo `vol` não é enviado;
- a função de auditoria confirmou explicitamente o estado de `gIBSCBS` e `cClassTrib` no XML autorizado.

O DANFE é o PDF produzido e disponibilizado pela Focus NFe em `caminho_danfe`; o arquivo auditado declara `Producer=Prawn` e este projeto não possui template próprio. A API pública consultada documenta os campos do XML/payload e a pré-visualização, mas não oferece parâmetros para formatar o número, mudar a opacidade da tarja, estender a grade de produtos ou forçar a linha de volumes. Esses desvios foram encerrados como **limitação externa**, não como pendência do pipeline.

O painel Focus foi verificado em 03/09/2026 em **Minhas Empresas → ELETRICA SEGAU LTDA → Editar → Identificação**. Existe o botão **“Anexar logo da Empresa”**; o botão **“Remover logo”** estava desabilitado, indicando que nenhum logotipo estava anexado naquele momento. Nenhuma alteração foi feita no painel.

### Decisões para a segunda emissão

1. `cEnq` não é atributo do produto. Ele pertence ao grupo IPI do perfil de operação; a fixture `tributacao-provisoria.json`, espelhada pela fixture operacional de homologação, cobre provisoriamente apenas `CFOP 5102 → CST IPI 53 / cEnq 999`. A promoção ao perfil continua sendo a pergunta 4 ao contador e o portão fiscal permanece fechado.
2. Com `modFrete=9`, não será enviado o grupo `vol`. Os pesos do item 3629 permanecem nulos e não foram estimados. O suporte a frete real foi movido para o backlog de expedição.
3. A NF-e série 2 nº 1 permanecerá `AUTORIZADA`. Homologação não tem valor fiscal nem consome numeração de produção; a substituta será uma nova NF-e série 2 nº 2.
4. Os cenários de cancelamento são independentes da substituta: um caminho feliz deverá emitir e cancelar uma nota recente, registrando o protocolo; o caminho fora do prazo deverá tentar cancelar a 2/1 após 03/09/2026 18:56 e registrar a rejeição em português. Este segundo caso fundamenta a natureza `999 - ESTORNO DE NF-E NAO CANCELADA NO PRAZO LEGAL`. A tela de ciclo ganhou uma ação exclusiva de HOMOLOGAÇÃO, disponível apenas depois das 24 horas e executável uma única vez, para fazer essa tentativa real sem retirar o bloqueio do cancelamento normal nem abrir qualquer caminho em PRODUÇÃO.

Backlog relacionado: `docs/faturamento/backlog-expedicao-danfe.md`.

### Validações desta revisão

- teste isolado do builder e das guardas de ambiente: 60 cenários aprovados;
- `tsc --noEmit`: aprovado;
- ESLint dos arquivos alterados do fluxo: aprovado;
- `npm run build`: aprovado;
- migrations `20260903134000_nfe_ipi_fixture_sem_volumes.sql` e `20260903141000_nfe_fixture_tenant_canonico.sql`: aplicadas localmente;
- smoke SQL `supabase/tests/faturamento_nfe_pipeline.sql`: aprovado individualmente e encerrado com `ROLLBACK`;
- Edge Functions `nfe-emitir` e `nfe-emitir-producao`: implantadas no projeto vinculado;
- nenhuma NF-e de produção foi transmitida e nenhum token foi gravado no repositório.

### Estado da substituta 2/2 em 03/09/2026

A conferência do rascunho `35b72661-2612-4180-9e5d-52f7d2c3c243` foi reaberta pela tela da OV 344 depois do deploy. Foram confirmados:

- destino interno em SC;
- item 3629 com origem `2`, NCM `85371020` e unidade tributável `UN` (a unidade ausente foi cadastrada pela tela do item);
- perfil `SEG-VENDA-TERCEIROS-SC-5102-O2-CST00` resolvido;
- `CST IPI 53 / cEnq 999` identificado como fixture provisória da operação;
- modalidade `9 - Sem frete`, sem campos de transportadora ou volume no payload.

Depois das confirmações não tributárias, restaram exatamente seis campos obrigatórios: CST IBS/CBS, `cClassTrib`, versão da tabela, alíquota IBS UF, alíquota IBS municipal e alíquota CBS. Eles permanecem vazios conforme a decisão anterior de não implementar/configurar IBS/CBS sem confirmação fiscal. A auditoria da 2/1 recuperou os valores usados (`000`, `000001`, `NT 2025.002 v1.34`, `0,1%`, `0%`, `0,9%`), mas a NF-e 2/2 ainda não foi transmitida; copiá-los silenciosamente contrariaria o portão fiscal e a regra de manter valores tributários somente em fixture provisória aprovada.

O cadastro do item também deixou de oferecer edição de `cEnq`. Salvamentos e cópias limpam eventual valor legado, enquanto o trigger do banco rejeita qualquer tentativa de gravar valor não nulo, identificando o item e o campo.

O primeiro lint remoto pós-push encontrou uma falha temporária de autenticação do pooler (`SQLSTATE 28P01`); a repetição concluiu e listou apenas os nove erros legados do baseline, sem erro novo do fluxo fiscal. O push e a consulta do histórico remoto concluíram normalmente, com migrations alinhadas até `20260903141000`; testes locais, TypeScript, ESLint e build permaneceram aprovados.

## Autorização IBS/CBS para o exercício de 2026 — 03/09/2026

Foram aprovados como regra legal, e não como valores da fixture tributária provisória:

- natureza `VENDA_MERCADORIA_TERCEIROS`, CFOP `5102`: CST IBS/CBS `000` e `cClassTrib 000001`;
- `pIBSUF=0,1000%`, `pIBSMun=0,0000%` e `pCBS=0,9000%`;
- vigência fechada entre `01/01/2026` e `31/12/2026`.

A fonte de verdade foi separada em `supabase/functions/_shared/fiscal/ibs-cbs-transicao-2026.ts`. O builder e a tela resolvem os valores pela natureza da operação. Não existe fallback global para `000001`: devolução (`5201/6201`), remessa por conta e ordem (`6923`), industrialização (`5901/5902`) e outras saídas (`6949`) falham com o nome da natureza até receberem classificação própria. A virada para outro exercício também falha explicitamente até revisão da tabela.

Base legal registrada no código: ADCT art. 125 (EC 132/2023), que fixa em 2026 IBS estadual de 0,1% e CBS de 0,9%; ADCT art. 125, § 4º, e LC 214/2025 art. 348, sobre dispensa de recolhimento mediante cumprimento das obrigações acessórias e compensação com PIS/COFINS.

O teste da nota real usa base de R$ 4.563,40 e comprova `vIBSUF=R$ 4,56`, `vIBSMun=R$ 0,00` e `vCBS=R$ 41,07`. O teste SQL confirma que a nova conferência não persiste a versão da NT no snapshot e que o portão de produção não a trata como sexto valor tributário.

### Versão da NT 2025.002 — observação do fornecedor

Leitura registrada em 03/09/2026: a NF-e 2/1 expôs historicamente `NT 2025.002 v1.34` no snapshot interno. Esse dado foi recusado como configuração fiscal: não foi incluído em `tributacao-provisoria.json`, não é enviado no payload e deixou de ser requisito de conferência/equivalência. A versão identifica o leiaute implementado pela Focus, não a tributação do item.

A `v1.34` está defasada. A `v1.40` fixou a obrigatoriedade em 03/08/2026 e a `v1.51` adiou o início das validações para 01/09/2026. Pergunta aberta ao suporte da Focus: **qual versão da NT 2025.002 a API implementa hoje e qual é o plano/data de atualização?**

### Resultado das NF-e série 2 nº 2 a 13 — 04/09/2026

Todas autorizadas em homologação (`cStat 100`) na OV 344, item 3629, base R$ 4.563,40. As solicitações de 2 a 12 foram abandonadas pela ação de homologação, que devolve o saldo da OV e registra evento `CANCELAMENTO/LOCAL`; a 2/13 permanece como solicitação `EMITIDA` e é a evidência atual para a liberação do perfil. Auditoria detalhada em [auditoria-danfe-homologacao.md](auditoria-danfe-homologacao.md).

| NF-e | Protocolo | Autorizada | Perfil | Destinação | tPag | O que provou |
|---|---|---|---|---|---|---|
| 2/2 | 342260000899612 | 04/09 12:26 | O2-CST00 | — | — | substituta da 2/1 com `dhEmi` em `-03:00`, IPI 53/999, sem `vol` |
| 2/3 | 342260000899617 | 04/09 12:27 | O2-CST00 | — | — | repetição idempotente do ciclo pela tela |
| 2/4 | 342260000899735 | 04/09 13:14 | O2-CST00 | — | — | abandono de homologação libera saldo |
| 2/5 a 2/7 | 342260000900000 / 019 / 035 | 04/09 14:14 a 14:18 | O2-CST00 | — | — | frete modalidade 1 com transportadora e volumes sem espécie/marca/numeração |
| 2/8 | 342260000900693 | 04/09 15:08 | O2-CST00 | — | — | nota auditada: revelou `tPag 01` e texto de benefício indevido |
| 2/9 | 342260000901022 | 04/09 15:47 | O2-CST00 | — | 15 | grupo `pag` confirmado na conferência (`indPag 1`, `tPag 15`) |
| 2/10 | 342260000901373 | 04/09 16:34 | O0-CST00 | — | 15 | perfil de origem nacional (0) |
| 2/11 | 342260000901509 | 04/09 16:54 | O0-CST00 | REVENDA | 15 | destinação confirmada, ICMS 12% (R$ 547,61) |
| 2/12 | 342260000901518 | 04/09 16:56 | O0-CST00-17 | USO_CONSUMO | 15 | mesma OV e item com ICMS 17% (R$ 775,78) |
| 2/13 | 342260000901624 | 04/09 17:09 | O0-CST00 | MANUTENCAO | 15 | destinação de manutenção a 12%, conforme exigência da Portobello |

Chaves: `4226091367144800018955002000000002...` até `...0000000131184824570`; a lista completa está em `f.documento_fiscal_emissao`.

## Fechamento de 05/09/2026

- As nove migrations de 04/09 aplicadas por `db-apply-migration.js` (`100000`, `101000`, `110000`, `130000` a `180000`) estavam no banco remoto, mas fora de `supabase_migrations.schema_migrations`. O histórico foi reparado com `migration repair --status applied` após conferir que cada objeto existia; `db push --dry-run` voltou a responder `Remote database is up to date`.
- `indPres 0` deixou de ser aceito em venda normal: o builder recusa presença 0 quando a finalidade não é 2 (complementar) ou 3 (ajuste) e a tela só oferece a opção nessas finalidades. A 2/8 tinha saído com 0.
- A `observacao` da solicitação passou a compor o `infCpl`, por último e com espaços normalizados; o conjunto respeita 5.000 caracteres.
- Pendências que continuam abertas nesta data: bateria de cancelamento real na SEFAZ (`CAN-HOM-01/02`), CC-e e e-mail com anexos ainda sem evento na Focus; decisão do contador sobre manutenção 12% × 17%; promoção do `cEnq` da fixture para o perfil; numeração de produção na conta Focus; credenciais reais de produção.
