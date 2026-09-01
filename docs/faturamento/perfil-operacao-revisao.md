# Revisão de `f.perfil_operacao` antes do primeiro `db push`

## Resumo

- A fundação **já separava** `cst_icms` de `csosn`; não havia a mistura apontada como risco no briefing.
- Faltavam `cbenef`, redução de base, `cst_ibs_cbs`, `cclass_trib` e o snapshot fiscal completo por item. A migration foi ajustada sem cadastrar qualquer regra fiscal.
- `natureza_operacao`, `itens.fabricado`, `os_itens.finalidade` e `documento_fiscal.nfe_referenciada` agora têm lugar explícito.
- O trigger fiscal **já cobria** item ativo no `INSERT` e ativação posterior por `UPDATE OF ativo`; ele foi mantido e testado.
- Foram corrigidos três tipos incompatíveis com o schema real: `cliente_id` e `item_id` eram `uuid`, embora os cadastros usem `integer`; as referências polimórficas de OS/OV passaram a `text`.

Escopo observado: baseline local mais as migrations `20260901120000` a `20260901125000`. Nenhuma consulta de produção e nenhum valor de CFOP, CST, CSOSN ou benefício foi gravado.

## 1. Retrato atual das cinco tabelas

O retrato abaixo é o resultado de `db reset --local` seguido de `\d+` nas cinco tabelas. É a definição **depois desta revisão**, ainda não aplicada em produção.

### `f.perfil_operacao`

| Coluna | Tipo / nulabilidade | Papel |
|---|---|---|
| `id` | `uuid not null`, PK | Identidade |
| `tenant_id` | `uuid not null`, default do contexto | Escopo |
| `empresa_id` | `uuid null` | Emissora específica; `null` permite perfil comum |
| `codigo`, `nome` | `text not null` | Identidade funcional do perfil |
| `modelo` | `text not null` | `NFE` ou `NFSE` |
| `natureza_operacao` | `text not null` | Código controlado da natureza |
| `natureza_texto` | `text not null` | Texto literal enviado ao documento |
| `crt` | `text null` | `1`, `2` ou `3` |
| `cfop_interno`, `cfop_externo` | `text null` | Par dentro/fora do estado |
| `item_servico`, `nbs` | `text null` | Classificação de serviço |
| `cst_icms`, `csosn` | `text null`, mutuamente exclusivos | ICMS de regime normal × Simples Nacional |
| `cst_ipi`, `cst_pis`, `cst_cofins` | `text null` | Tributação federal por operação |
| `cbenef` | `text null` | Código de benefício em campo próprio da NF-e |
| `reducao_base_icms_percentual` | `numeric(7,4) null` | Percentual entre 0 e 100 |
| `beneficio_texto_legal` | `text null` | Fundamentação complementar |
| `cst_ibs_cbs` | `text null` | Três dígitos |
| `cclass_trib` | `text null` | Seis dígitos; prefixo deve coincidir com `cst_ibs_cbs` |
| `exige_referencia`, `exige_motivo` | `boolean not null default false` | Requisitos do fluxo |
| `observacao` | `text null` | Nota interna |
| `vigencia_inicio`, `vigencia_fim` | `date` | Intervalo válido e ordenado |
| `created_at` | `timestamptz not null` | Auditoria |

Chaves e índices:

- PK `perfil_operacao_pkey (id)`.
- `UNIQUE NULLS NOT DISTINCT (tenant_id, empresa_id, codigo, vigencia_inicio)`. A cláusula `NULLS NOT DISTINCT` impede duplicidade de perfil global; a versão anterior aceitava várias linhas iguais com `empresa_id null`.
- FK recebida de `f.solicitacao_faturamento.perfil_operacao_id`.

Checks: modelo, CRT, percentual 0–100, formato de `cst_ibs_cbs`/`cclass_trib`, prefixo coerente entre ambos, vigência ordenada e impossibilidade de preencher CST e CSOSN juntos.

RLS: habilitada. A policy permissiva exige tenant corrente e `f.has_finance_access()`; a policy restritiva exige tenant, empresa ativa e limita perfil específico à empresa corrente. Perfil com `empresa_id null` é visível às empresas ativas do mesmo tenant.

### `f.solicitacao_faturamento`

| Coluna | Tipo / nulabilidade |
|---|---|
| `id` | `uuid not null`, PK |
| `tenant_id`, `empresa_id` | `uuid not null`, defaults do contexto |
| `cliente_id` | `integer null` |
| `perfil_operacao_id` | `uuid null`, FK para `f.perfil_operacao` |
| `status` | `text not null default 'RASCUNHO'` |
| `pedido_cliente`, `condicao_pagamento`, `observacao` | `text null` |
| `criado_por` | `uuid null` |
| `created_at`, `updated_at` | `timestamptz not null` |

PK em `id`; índice em `status`; check de status (`RASCUNHO`, `PREVIA`, `APROVADA`, `EMITIDA`, `CANCELADA`); FKs recebidas de solicitação-item e emissão. RLS exige tenant/empresa correntes, acesso financeiro e empresa ativa. Trigger de `updated_at` ativo.

### `f.solicitacao_item`

| Grupo | Colunas |
|---|---|
| Identidade/escopo | `id uuid` PK, `solicitacao_id uuid` FK, `tenant_id uuid` |
| Origem | `origem_tipo text`, `origem_id text`, `origem_item_id text`, `pedido_linha text` |
| Produto | `item_id integer`, `descricao text`, `ncm text` |
| ICMS atual | `cfop`, `cst_icms`, `csosn`, `cbenef`, `reducao_base_icms_percentual` |
| Tributos federais | `cst_ipi`, `cst_pis`, `cst_cofins` |
| Reforma | `cst_ibs_cbs`, `cclass_trib`, `ibs_cbs_json` |
| Valores | `quantidade numeric`, `unidade text`, `valor_unitario numeric`, `ordem integer` |

PK em `id`; FK para solicitação com `ON DELETE CASCADE`; índices em `solicitacao_id` e `origem_id`. Checks: origem `OS/OV/AVULSO/CONTRATO`, CST/CSOSN mutuamente exclusivos, redução 0–100, formatos e prefixo IBS/CBS, e `ibs_cbs_json` como objeto. RLS herda empresa pela solicitação-pai e exige acesso financeiro/empresa ativa.

`ibs_cbs_json` é snapshot do grupo calculado para o item, não configuração fiscal livre. A configuração controlada permanece em `cst_ibs_cbs`/`cclass_trib`; os indicadores da tabela oficial determinam quais subgrupos são exigidos.

### `f.documento_fiscal_emissao`

Colunas: `documento_fiscal_id uuid` (PK/FK), `solicitacao_id uuid` (FK), `tenant_id`, `empresa_id`, `referencia_externa`, `provedor`, `ambiente`, `status`, `chave_acesso`, `protocolo`, `numero`, `serie`, `codigo_status`, `mensagem`, `payload_enviado`, `resposta`, `xml_path`, `danfe_path`, `enviado_em`, `autorizado_em`, `created_at`, `updated_at`.

Índices: único por `(tenant_id, empresa_id, referencia_externa)` e índices de status, solicitação e chave. Checks de ambiente e status. RLS exige tenant/empresa correntes, acesso financeiro e empresa ativa. Trigger de `updated_at` ativo.

### `f.documento_fiscal_evento`

Colunas: `id uuid` PK, `documento_fiscal_id uuid` FK, `tipo`, `justificativa`, `documento_referenciado_chave`, `protocolo`, `status`, `resposta jsonb`, `criado_por`, `created_at`.

Índice em `status`; check de tipo (`CANCELAMENTO`, `CARTA_CORRECAO`, `ESTORNO`, `SUBSTITUICAO`, `REENVIO`, `CONSULTA`). A RLS deriva tenant/empresa do documento-pai e exige acesso financeiro/empresa ativa.

## 2. Confronto com os requisitos conhecidos

| Precisa representar | Resultado | Coluna(s) e ressalva |
|---|---|---|
| CST **e** CSOSN separados | **Cabe** | `perfil_operacao.cst_icms` e `.csosn`; mesmos campos no snapshot de `solicitacao_item`. Check impede ambos simultaneamente. |
| `cBenef` | **Cabe** | `perfil_operacao.cbenef` e `solicitacao_item.cbenef`. O nome SQL é minúsculo; o adaptador do XML deve mapear para `cBenef`. |
| `cClassTrib` e grupos IBS/CBS | **Cabe com ressalva** | `cst_ibs_cbs` + `cclass_trib` guardam classificação; `solicitacao_item.ibs_cbs_json` guarda o grupo calculado. A lista de subgrupos não foi cristalizada no perfil porque sua exigência é dirigida pelos indicadores da tabela oficial vigente. |
| Natureza de operação e texto literal | **Cabe** | `natureza_operacao` + `natureza_texto`. `codigo` continua identificando o perfil, sem acumular dois significados. |
| Dentro × fora do estado | **Cabe** | `cfop_interno` + `cfop_externo`. O perfil não escolhe sozinho: o payload ainda precisa comparar UF do emitente/destinatário. |
| Empresa emissora e regime | **Cabe com ressalva** | `empresa_id` + `crt`. Perfil global (`empresa_id null`) só é seguro quando não houver diferença entre empresas; decidir se perfis NF-e globais serão permitidos continua pendente. |
| CST de IPI, PIS e COFINS | **Cabe** | `cst_ipi`, `cst_pis`, `cst_cofins` no perfil e no snapshot do item. |
| Redução de base e texto legal | **Cabe com ressalva** | `reducao_base_icms_percentual`, `cbenef`, `beneficio_texto_legal`; o snapshot do item recebe percentual e `cbenef`. A elegibilidade por item/NCM ainda depende do fechamento de `BEN-01/02`. |

Referência técnica usada para não congelar os grupos IBS/CBS no perfil: o Informe Técnico 2025.002 define que os três primeiros dígitos de `cClassTrib` coincidem com o CST IBS/CBS e que indicadores da tabela determinam exigência/permissão/vedação de grupos. A implementação deve versionar/carregar essa tabela, não duplicar os indicadores em colunas booleanas do perfil.

## 3. Campos do §8

| Campo | Situação depois da revisão | Decisão |
|---|---|---|
| `natureza_operacao` | `f.perfil_operacao.natureza_operacao` | Criado como código separado de `natureza_texto`. |
| `itens.fabricado` | `public.itens.fabricado boolean not null default false` | Criado; é atributo permanente do produto, sem decidir tributação sozinho. |
| `os_itens.finalidade` | `public.os_itens.finalidade text null` | Criado com domínio `componente/venda`. O legado fica `null`; não foi presumido como componente. |
| `documento_fiscal.nfe_referenciada` | `f.documento_fiscal.nfe_referenciada text null` | Criado com check de 44 dígitos. Eventos continuam usando `documento_referenciado_chave` para a referência do evento. |

Além do §8, foram corrigidos tipos que impediriam consumir o schema real:

- `solicitacao_faturamento.cliente_id`: `uuid` → `integer`, como `public.clientes.id` e `f.documento_fiscal.cliente_id`.
- `solicitacao_item.item_id`: `uuid` → `integer`, como `public.itens.id`.
- `solicitacao_item.origem_id` e `origem_item_id`: `uuid` → `text`, pois OS/OV usam IDs inteiros e contrato pode usar UUID. O tipo polimórfico não pode ser FK sem uma tabela de origem comum.

## 4. Trigger de linha fiscal

Nenhuma alteração foi necessária. A versão atual já é:

```sql
create trigger trg_itens_criar_linha_fiscal
after insert or update of ativo on public.itens
for each row
execute function public.fn_itens_criar_linha_fiscal();
```

A função testa `new.ativo is true` e faz `insert ... on conflict do nothing`. Portanto cobre:

- item criado ativo;
- item criado inativo e ativado depois;
- repetição de update em item ativo sem duplicar linha.

Smoke local: item inativo começou com `0` linhas fiscais; após `ativo=true`, ficou com `1` linha.

## 5. Fallback legado: condição objetiva de remoção

Hoje o orçamento impresso lê `itens.ncm` e o substitui por `fiscal_itens.ncm` quando o fiscal está preenchido. O detalhe da NF-e usa `nf_entrada_itens.ncm/cfop`, depois `fiscal_itens` e, para CFOP, ainda cai em `itens.cfop_padrao`.

O fallback para `public.itens` pode ser removido quando a consulta abaixo retornar zero nas três dependências:

```sql
select
  count(*) filter (where fi.item_id is null) as ativos_sem_linha_fiscal,
  count(*) filter (
    where nullif(btrim(fi.ncm), '') is null
      and nullif(btrim(i.ncm), '') is not null
  ) as ncm_dependente_do_legado,
  count(*) filter (
    where nullif(btrim(fi.cfop_padrao), '') is null
      and nullif(btrim(i.cfop_padrao), '') is not null
  ) as cfop_dependente_do_legado
from public.itens i
left join public.fiscal_itens fi
  on fi.tenant_id = i.tenant_id
 and fi.empresa_id = i.empresa_id
 and fi.item_id = i.id
where i.ativo is true;
```

Procedimento de saída:

1. Executar o backfill sobre snapshot obtido na própria janela.
2. Exigir `0/0/0` na consulta para o tenant/empresa alvo (acrescentar os dois filtros na execução real).
3. Remover dos consumidores as seleções de `itens.ncm`/`itens.cfop_padrao` e seus `coalesce`/fallbacks.
4. Reexecutar a consulta e os testes de orçamento/detalhe da NF-e.
5. Só em tarefa posterior avaliar remoção física das colunas legadas; retirar o fallback de leitura não autoriza apagar dado.

## 6. Decisões ainda abertas

- A lista de nove valores de `natureza_operacao` e qualquer linha de perfil aguardam o contador. Não foi criado enum/check com valores ainda não confirmados.
- Elegibilidade do benefício por item/NCM (`BEN-01/02`) ainda não tem regra semeada. O perfil suporta a saída e o item guarda snapshot, mas não decide sozinho quem tem direito.
- Perfis NF-e globais (`empresa_id null`) podem ser proibidos depois se o contador confirmar diferenças obrigatórias entre SEG e SGU.
- As linhas legadas de `os_itens` precisam ser classificadas antes de tornar `finalidade` obrigatória.
- O carregamento/versionamento da tabela oficial `cClassTrib` e o builder dos grupos IBS/CBS são tarefas de payload; `ibs_cbs_json` não deve virar cadastro manual livre.
- A coluna singular `nfe_referenciada` atende o levantamento atual. Se uma operação exigir várias referências, será necessário normalizar em tabela filha antes do payload.

## 7. Validações

- `supabase db reset --local`: aprovado do baseline até `20260901125000`.
- Smoke de fundação com rollback: perfil, solicitação, item, documento e emissão inseridos sem valor fiscal; aprovado.
- Smoke do trigger: `0` linhas antes da ativação e `1` depois; aprovado.
- Verificação de semente fiscal no smoke: `0`; aprovado.
- `npx tsc --noEmit`: aprovado.
- ESLint dos sete arquivos TypeScript alterados no worktree: aprovado, sem avisos.
- `GET /financeiro/gestao-cobranca`: HTTP `200` no servidor local.
- `git diff --check`: aprovado; apenas avisos de normalização futura LF/CRLF do Git.
- `supabase db lint --local`: reproduziu os **10 erros preexistentes do baseline**, todos em funções antigas (`f.gerar_ap_por_nf_entrada`, `f.fn_sync_apuracao_irpj_csll`, `public.admin_merge_fornecedores`, `public.can__legacy_56548`, `public.gerar_relatorio_hh_os_unscoped_20260810`, `public.get_default_tenant_id`, `public.import_nf_entrada`, `public.import_nf_entrada_v2`, `public.list_user_empresas` e `public.merge_fornecedores`). Nenhum erro aponta para as tabelas, checks, índices, RLS ou trigger revisados nesta tarefa; não foram corrigidos por estarem fora do escopo.
- `db push`: **não executado**.
- `migration repair`: **não executado**.
