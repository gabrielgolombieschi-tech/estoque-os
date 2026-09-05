# Inventário — NF-e de industrialização a partir da OS (Parte 0)

Levantamento feito em 05/09/2026 contra o banco remoto e o código, antes de qualquer alteração. Responde aos cinco itens da tarefa e registra três achados que mudam o desenho.

## Achados que mudam o desenho

1. **A "OS 304" do plano é a linha `id = 303`** de `public.ordens_servico` (`numero_os = '304'`, código `OS 304`, ArcelorMittal, "ADICIONAL BARRA NO CARRO", orçado R$ 5.266,10, `em_andamento`). A `id = 304` é outra OS (Portobello, HH). A rota da tela usa o `id`; a página de faturar fica em `/os/303/faturar`.
2. **O vínculo nota ↔ OS já é uma coluna só.** Não há unificação a fazer (item 2 abaixo).
3. **O pipeline de conferência recusa por construção qualquer natureza que não seja revenda.** `f.fn_solicitacao_nfe_salvar_conferencia_2026` bloqueia `natureza_operacao <> 'VENDA_MERCADORIA_TERCEIROS'` e CFOP `<> 5102`; `f.fn_solicitacao_nfe_resolver_perfis` exige perfil vigente e não bloqueado por linha, e os dez perfis 5101/6101 (`CSV63-002/016/019/020/026/027/043/044/045/056`) estão `BLOQUEADO` com a justificativa "5101/5102 depende de item.fabricado confirmado". Como a tarefa proíbe semear valor fiscal nesses perfis, a emissão da OS em homologação precisa de uma conferência própria que preencha as linhas a partir da fixture provisória, com `perfil_operacao_id` nulo e marca de origem. O portão de produção (`fn_nfe_producao_pronta` e o trigger `trg_bloquear_nfe_producao_sem_perfil_liberado`) já recusa linha sem perfil liberado, então produção continua fechada sem nenhuma mudança.

## 1. O bloco "Faturamento da OS por valor" (tela `/os/[id]`)

Componente: `components/faturamento/FaturamentoParcialPanel.tsx`, modo `tipo="OS"`, montado em `app/os/[id]/page.tsx` com `podeCompor = papel FINANCEIRO && OS não cancelada`.

| Número na tela | Origem |
|---|---|
| Orçado / HH | `f.fn_os_saldo_a_faturar(...).valor_pedido`: `ordens_servico.orcado`, ou `vw_hh_total_os.total_hh` quando `usa_relatorio_hh` |
| Já faturado | `.valor_faturado`: soma de `f.documento_fiscal` com `os_id_import = OS`, `operacao = 'SAIDA'`, `nfe_status` nulo (importada) ou `EMITIDA`; NF-e conta `valor_produtos − valor_desconto`, NFS-e conta `valor_total` |
| Reservado em aberto | `.valor_reservado`: soma de `quantidade × valor_unitario − desconto` de `f.solicitacao_item` cujas solicitações estão em `RASCUNHO`, `PREVIA` ou `APROVADA`, com `origem_tipo = 'OS'` e `origem_id = OS` |
| Saldo | `valor_pedido − valor_faturado − valor_reservado` |

"Atualizar saldo" chama `f.fn_os_saldo_a_faturar(p_tenant_id, p_empresa_id, p_os_id)`. "Faturar" (dentro do bloco) grava um rascunho por `f.fn_solicitacao_faturamento_criar_os_livre(tenant, empresa, os, p_linhas, 'FATURAMENTO_OS')`, com linhas `{descricao, quantidade, unidade, valor_unitario, item_id}`; produto é opcional na composição. **Não existe caminho de emissão para esse rascunho**: `OvNfeDraftsPanel` só é montado na OV.

Lacuna na regra de saldo: uma solicitação de OS que chega a `EMITIDA` em homologação sai da reserva (não está em RASCUNHO/PREVIA/APROVADA) e não entra no faturado (documento fica `RASCUNHO`), então o saldo volta sozinho depois da autorização em homologação. Na OV isso é tratado pela ação "Abandonar homologação e liberar saldo". A função única desta tarefa corrige: reserva = solicitações não canceladas cuja emissão mais recente está em `RASCUNHO/ENVIANDO/PROCESSANDO/AUTORIZADA` sem documento `EMITIDA`; `CANCELADA`, `REJEITADA` e `ERRO` não somam.

## 2. Coluna de vínculo nota ↔ documento comercial

Uma coluna só: **`f.documento_fiscal.os_id_import`**.

- Importação de XML: grava `os_id_import`.
- NF-e emitida pela OV/OS: `f.fn_nfe_preparar_documento_solicitacao` grava `os_id_import = min(origem_id)` das linhas com `origem_tipo in ('OS','OV')`.
- `f.fn_os_saldo_a_faturar`, `f.fn_os_itens_saldo_a_faturar`, `public.os_faturar` e `lib/os/faturadoPorOs.ts` leem `os_id_import`.

Nenhuma unificação necessária. A tarefa mantém essa coluna.

## 3. O que `f.fn_faturar_documento` aceita hoje

Assinatura: `(p_tenant_id, p_empresa_id, p_ov_id, p_os_item_ids int[], p_documento_fiscal_id, p_ambiente, p_natureza_operacao, p_itens_quantidades jsonb, p_linhas_livres jsonb)`.

- OV: `p_os_item_ids` + `p_itens_quantidades` vêm de `public.os_itens` (`fn_solicitacao_faturamento_criar_ov_impl`).
- OS: `p_linhas_livres` obrigatório; cria a solicitação por `fn_solicitacao_faturamento_criar_os_livre` e o documento com `os_id_import`, `nfe_status = 'RASCUNHO'`, `origem = 'EMITIDO'` e a emissão com referência idempotente (`pg_advisory_xact_lock` na referência) antes de qualquer chamada externa.

Ou seja, **linhas por valor já são aceitas**. O que falta: (a) a natureza (`FATURAMENTO_OS` hoje) não é uma natureza fiscal; (b) nenhuma função preenche os campos fiscais de `f.solicitacao_item` para uma linha de OS, porque a conferência é exclusiva da revenda; (c) `p_linhas_livres` aceita linha sem `item_id`, e uma NF-e modelo 55 precisa de produto com NCM, origem e unidade tributável. A tela desta tarefa usa a rota `solicitação → conferência própria da OS → nfe-emitir`, a mesma da OV; `fn_faturar_documento` continua servindo ao caminho completo/teste.

## 4. `itens.fabricado` e `itens.origem_os_id`

- `public.itens.fabricado boolean not null default false` **existe**; nenhum item está marcado (0 de 3.594).
- `public.itens.origem_os_id` **não existe**. Criada nesta tarefa, com FK para `ordens_servico`, índice e comentário.
- `fiscal_itens` nasce pelo trigger `trg_itens_criar_linha_fiscal` (AFTER INSERT/UPDATE OF ativo) com campos fiscais nulos; a tarefa preenche NCM, origem, unidade tributável, CST/alíquota de IPI e cEnq no ato de "criar da OS", sem dedução.
- Políticas de escrita em `itens` para `authenticated` existem (`itens_insert`, `itens_update`); a criação pelo faturamento passa por RPC `security definer` com checagem de papel, para não depender da permissão de almoxarifado.

## 5. Como `pode_faturar` e `faturadoPorOs.ts` verificam "NF vinculada"

- `public.os_faturar(p_os_id)` (ação "Marcar OS faturada"): exige papel `FINANCEIRO`, `status_fluxo = 'concluida'` e existência de `f.documento_fiscal` com `os_id_import = OS`, `SAIDA`, e `nfe_status` nulo **ou** `EMITIDA` (NFS-e: `nfse_status = 'EMITIDA'`). Já aceita nota emitida. **Não exige saldo zero.**
- `public.app_listar_os_fluxo` devolve `pode_faturar` a partir de `app_listar_os_fluxo_unfiltered_ov_20260829`, com a mesma regra de documento vinculado.
- `lib/os/faturadoPorOs.ts` (`shouldIncludeFaturamentoDocumento`): NFS-e `EMITIDA`; NF-e com `nfe_status` nulo ou `EMITIDA`. Já aceita emitida.

Mudança conjunta desta tarefa: `os_faturar` e `pode_faturar` passam a exigir `f.fn_os_saldo_a_faturar(...).saldo <= 0,005` além do documento; `faturadoPorOs.ts` não muda de critério (já é o mesmo), só ganha o comentário da regra.

## Outros pontos conferidos

| Item | Situação |
|---|---|
| Papéis existentes em `a.usuario_empresa` | `FATURAMENTO` (2 usuários), `FINANCEIRO` (3), `DIRETOR` (2), `ADMIN` não aparece como papel de empresa (é papel de tenant); o botão usa os quatro nomes da tarefa |
| Cadastro fiscal da ArcelorMittal (cliente 42) | CNPJ 17.469.701/0106-44, IE 255633025, IBGE 4216206, endereço completo; **`indicador_ie` vazio** (sugestão mecânica 1). Bloqueia a emissão até confirmação humana em `/clientes/cadastro-fiscal?cliente_id=42` |
| Custo real da OS | Calculado na própria página (`get_os_detail_operacional` para mão de obra; despesas e materiais das linhas; impostos por regra de 15%/27%). A margem da tela de faturar reaproveita `public.get_os_lista_custos_operacionais` |
| Fixture provisória | `f.tributacao_provisoria_homologacao` só tem IPI por CFOP (5102). Ganha ICMS/PIS/COFINS por CFOP e fonte, com 5101 e 6101 a partir das NF-e de agosto/2026 (`regras-nfe-63-combinacoes.csv`: 34 notas 5101 · CST 00 · 17% · IPI 0; NF-e 3766 · IPI 9,75%; 6101 · 12%) |
| IBS/CBS 2026 | Só `VENDA_MERCADORIA_TERCEIROS` mapeada. As naturezas `VENDA_INDUSTRIALIZACAO_INTERNA/INTERESTADUAL` entram na mesma regra legal (CST 000, cClassTrib 000001, 0,10 / 0 / 0,90), marcadas como fixture de homologação |
| Realtime | `OvNfeDraftsPanel` assina `postgres_changes` em `f.documento_fiscal_emissao` filtrado por empresa e faz polling de 5 s enquanto `ENVIANDO/PROCESSANDO`; a tela da OS reaproveita |
| Migrations | Pasta com baseline `00000000000000_baseline_producao.sql`, 360 arquivos antigos em `_arquivo/` e as novas na raiz; `db push --dry-run` responde atualizado. O fluxo normal continua: `migration up --local` → testes → push |

## Decisão sobre o título a receber em homologação

O critério da tarefa cita "título AR criado". A decisão A de 02/09/2026, confirmada pelo responsável, é que homologação **não** cria título nem consome saldo real: o documento fica `RASCUNHO` e só o retorno de produção grava `EMITIDA` e gera o AR. Esta tarefa mantém a decisão A: em homologação, a criação do AR é provada pelo teste SQL do cenário de produção; a reserva/faturamento do saldo em homologação é tratada pela função única de saldo (reserva enquanto a emissão de homologação está autorizada, devolve no abandono ou cancelamento).

## Execução (05/09/2026)

Tudo acima foi implementado nas migrations `20260905170000` e `20260905180000`, na página `/os/[id]/faturar`, no botão Faturar da OS e no painel "Faturamento da OS por valor". Os cenários de homologação, as chaves das notas e as perguntas que sobraram para o contador estão em [homologacao-os-nfe.md](homologacao-os-nfe.md).
