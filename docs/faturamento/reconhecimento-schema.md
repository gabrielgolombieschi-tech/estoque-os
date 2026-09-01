# Reconhecimento do schema para faturamento

## Fonte e estado do ambiente

Levantamento feito em 31/08/2026, sem consulta ou alteração de produção.

- O banco `postgres` do Supabase local está incompleto: o histórico local termina em `20260306160000` e as tabelas-alvo não existem nele.
- A fotografia usada para confirmar o schema e os dados foi o backup `C:\Users\gabri\SupabaseBackups\estoque-os\20260823_072659`, restaurado em um banco temporário isolado no Docker.
- O backup é de 23/08/2026. Migrations posteriores existentes no repositório não fazem parte desta fotografia e não estão aplicadas no banco local.
- `npx supabase db diff --local --schema public,c,m,f` não conseguiu reconstruir o schema a partir das migrations. A execução parou em `20260306161000_fix_importacao_xml_revenda_finalidades.sql`, pois `public.parametro_importacao_xml` não existe naquele ponto do histórico.
- Conforme a regra da Fase 3.1, a fundação de faturamento, o seed e o smoke test mutável **não foram executados**. O baseline também não foi criado, pois não seria seguro tratá-lo como base de uma migration aplicável enquanto o histórico não reproduz o banco.

## Relações confirmadas

As 12 relações solicitadas existem como tabelas no backup e estão com RLS habilitado.

### `public.itens`

Colunas reais, na ordem: `id integer`, `codigo_interno varchar`, `codigo_barras varchar`, `nome varchar`, `descricao text`, `tipo varchar`, `categoria varchar`, `subcategoria varchar`, `unidade_medida varchar`, `peso_bruto numeric`, `peso_liquido numeric`, `controla_estoque boolean`, `estoque_minimo integer`, `estoque_maximo integer`, `estoque_ideal integer`, `custo_ultima_compra numeric`, `custo_medio numeric`, `data_ultima_compra timestamp`, `preco_unitario numeric`, `preco_promocional numeric`, `data_atualizacao_preco timestamp`, `margem_lucro_percentual numeric`, `ncm varchar`, `cest varchar`, `cfop_padrao varchar`, `aliquota_icms numeric`, `aliquota_ipi numeric`, `aliquota_pis numeric`, `aliquota_cofins numeric`, `fornecedor_id integer`, `codigo_fornecedor varchar`, `controla_lote boolean`, `controla_validade boolean`, `dias_alerta_vencimento integer`, `ativo boolean`, `observacoes text`, `criado_em timestamp`, `criado_por varchar`, `atualizado_em timestamp`, `atualizado_por varchar`, `fabricante varchar`, `tenant_id uuid`, `finalidade public.item_finalidade`, `empresa_id uuid`, `motivo_compra_id uuid`, `created_at timestamptz`, `updated_at timestamptz`, `codigo_interno_sem_zeros text`, `codigo_fornecedor_sem_zeros text`, `mesclado_em_item_id integer`, `mesclado_em timestamptz`, `mesclado_motivo text`, `grupo_id bigint`.

Não existem colunas de origem da mercadoria, unidade comercial separada, unidade tributável, CST de ICMS/IPI/PIS/COFINS ou `cClassTrib`.

### `public.clientes`

Colunas reais, na ordem: `id integer`, `nome varchar`, `documento varchar`, `email varchar`, `telefone varchar`, `endereco text`, `observacoes text`, `ativo boolean`, `criado_em timestamp`, `atualizado_em timestamp`, `tenant_id uuid`, `habilita_hh boolean`, `empresa_id uuid`, `razao_social varchar`, `nome_fantasia varchar`, `inscricao_estadual varchar`, `inscricao_municipal varchar`, `cep varchar`, `logradouro varchar`, `numero_endereco varchar`, `complemento varchar`, `bairro varchar`, `cidade varchar`, `uf varchar`, `pais varchar`, `telefone2 varchar`, `email_financeiro varchar`, `contato_nome varchar`, `contato_email varchar`, `contato_telefone varchar`, `documento_norm text`, `documento_key text`.

Não existem coluna de marcação `ISENTO` nem código IBGE do município.

### `public.ordens_servico`

Colunas reais, na ordem: `id integer`, `numero_os varchar`, `cliente_nome varchar`, `cliente_id integer`, `descricao_servico text`, `status varchar`, `data_abertura timestamp`, `data_conclusao timestamp`, `valor_total numeric`, `observacoes text`, `criado_por varchar`, `atualizado_em timestamp`, `os_num bigint`, `pedido_compra text`, `tipo_pedido text`, `vendedor text`, `orcado numeric`, `custo numeric`, `tem_gestao boolean`, `tenant_id uuid`, `usa_relatorio_hh boolean`, `empresa_id uuid`.

- `tipo_documento`: **NÃO EXISTE — precisa ser criado** no schema auditado.
- `status_fluxo`: **NÃO EXISTE — precisa ser criado** no schema auditado; portanto, não há domínio atual a relatar. A coluna legada existente é `status`, sem `CHECK`, com valores observados no escopo auditado: `cancelada` (12), `concluida` (222) e `em_andamento` (74).
- O repositório contém migrations ainda não aplicadas que pretendem criar `status_fluxo` (`20260826120000`) e `tipo_documento` (`20260829130000`). Elas não foram tratadas como schema real.

### `public.os_itens`

Colunas reais, na ordem: `id integer`, `os_id integer`, `item_id integer`, `quantidade numeric`, `valor_unitario numeric`, `valor_total numeric`, `desconto_percentual numeric`, `desconto_valor numeric`, `baixa_estoque boolean`, `observacoes text`, `criado_em timestamp`, `tenant_id uuid`, `empresa_id uuid`, `quantidade_baixada numeric`, `registrado_em timestamptz`, `registrado_por uuid`, `registrado_por_nome text`.

### `c.empresa`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `codigo text`, `razao_social text`, `nome_fantasia text`, `cnpj text`, `email text`, `telefone text`, `site text`, `observacao text`, `ativo boolean`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`.

IE, CRT, CNAE e regime tributário ficam em `c.empresa_fiscal`, não em `c.empresa`. Série e próximo número de NF-e não existem em `c.empresa`, `c.empresa_fiscal` nem em outra tabela fiscal encontrada.

### `m.orcamento`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `empresa_id uuid`, `numero integer`, `versao integer`, `codigo text`, `status text`, `emissao_date date`, `titulo text`, `cliente_id integer`, `vendedor_usuario_id uuid`, `condicao_pagamento_id uuid`, `acrescimo_cond_pag_percent numeric`, `desconto_global_percent numeric`, `valor_frete numeric`, `total_produtos numeric`, `total_servicos numeric`, `total_bruto numeric`, `total_desconto_global numeric`, `total_liquido numeric`, `observacoes text`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`, `prazo_entrega text`, `garantia text`, `validade_proposta text`, `valor_fechado numeric`, `os_id integer`, `os_itens_importados_at timestamptz`, `solicitante_nome text`, `solicitante_setor text`, `solicitante_email text`, `solicitante_telefone text`, `drive_folder_id text`, `drive_folder_url text`, `drive_doc_id text`, `drive_doc_url text`, `drive_sync_status text`, `drive_sync_error text`, `drive_sync_requested_at timestamptz`, `drive_synced_at timestamptz`.

### `m.orcamento_item`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `empresa_id uuid`, `orcamento_id uuid`, `seq integer`, `item_id integer`, `item_tipo text`, `item_nome text`, `unidade text`, `quantidade numeric`, `valor_unitario numeric`, `desconto_item_percent numeric`, `acrescimo_cond_pag_percent numeric`, `desconto_global_percent numeric`, `valor_total_bruto numeric`, `valor_total numeric`, `valor_unitario_liquido numeric`, `observacoes text`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`, `conjunto_id uuid`, `conjunto_instancia_id uuid`, `conjunto_codigo text`, `conjunto_nome text`.

### `f.documento_fiscal`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `empresa_id uuid`, `source_nf_entrada_id bigint`, `fornecedor_id integer`, `chave_acesso text`, `modelo text`, `serie text`, `numero text`, `emissao_date date`, `competencia_date date`, `valor_total numeric`, `valor_produtos numeric`, `valor_frete numeric`, `valor_desconto numeric`, `valor_outros numeric`, `valor_seguro numeric`, `finalidade_import public.item_finalidade`, `os_id_import integer`, `pagamento_import_json jsonb`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`, `operacao text`, `natureza text`, `cliente_id integer`, `valor_servicos numeric`, `nfse_municipio_codigo text`, `nfse_codigo_verificacao text`, `nfse_status text`, `servico_discriminacao text`, `material_percent numeric`, `material_valor numeric`, `nfe_status text`.

- `origem`: **NÃO EXISTE — precisa ser criado**.
- `os_id_import` existe, é `integer`, aceita nulo e possui a FK `fk_documento_fiscal__os_id_import__ordens_servico` para `public.ordens_servico(id)`.
- O padrão de `updated_at` é o trigger `trg_documento_fiscal_set_updated_at`, que executa `a.fn_set_updated_at()` antes de `UPDATE`.

Políticas de RLS existentes:

| Política | Tipo | Papel/comando | Regra |
|---|---|---|---|
| `documento_fiscal_all` | permissiva | `authenticated`, `ALL` | Exige `tenant_id = current_tenant_id()`, `empresa_id = current_empresa_id()` e `f.has_finance_access()` em `USING` e `WITH CHECK`. |
| `enforce_active_empresa_scope` | restritiva | `authenticated`, `ALL` | Exige o mesmo tenant/empresa ativos via `public.has_active_empresa_access(...)` em `USING` e `WITH CHECK`. |

### `f.titulo`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `empresa_id uuid`, `tipo text`, `status text`, `origem text`, `fornecedor_id integer`, `cliente_id integer`, `documento_fiscal_id uuid`, `descricao text`, `emissao_date date`, `competencia_date date`, `valor_total numeric`, `valor_aberto numeric`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`, `motivo_compra_id uuid`, `classificacao_id bigint`, `arrendamento_contrato_id uuid`, `recorrencia_id uuid`, `total_parcelas_serie integer`, `os_id integer`.

### `f.titulo_parcela`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `titulo_id uuid`, `numero text`, `vencimento_date date`, `valor numeric`, `valor_aberto numeric`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`.

### `f.titulo_rateio`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `titulo_id uuid`, `plano_contas_id uuid`, `centro_custo_id uuid`, `os_id integer`, `percentual numeric`, `valor numeric`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`, `origem_rateio text`, `regra_rateio_id uuid`, `regra_item_id uuid`.

### `f.gestao_cobranca_os`

Colunas reais, na ordem: `id uuid`, `tenant_id uuid`, `empresa_id uuid`, `os_id integer`, `status text`, `pedido_compra_cliente text`, `pedido_recebido_em date`, `faturado_em date`, `documento_fiscal_id uuid`, `titulo_ar_id uuid`, `responsavel_id uuid`, `proximo_contato_date date`, `observacao text`, `created_at timestamptz`, `updated_at timestamptz`, `created_by uuid`, `updated_by uuid`, `deleted_at timestamptz`, `responsavel_cliente_nome text`.

## Funções confirmadas

| Função | Assinatura real | Retorno | Observação |
|---|---|---|---|
| `f.fn_os_saldo_a_faturar` | `(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)` | `TABLE(valor_pedido numeric, valor_faturado numeric, saldo numeric, usa_relatorio_hh boolean)` | `SECURITY DEFINER`; `row_security=off`. |
| `f.has_finance_access` | `(p_tenant uuid DEFAULT current_tenant_id(), p_empresa uuid DEFAULT current_empresa_id())` | `boolean` | Existe uma única implementação; pode ser chamada sem argumentos por causa dos defaults. |
| `public.current_tenant_id` | `()` | `uuid` | `SECURITY DEFINER`; estável. |
| `public.current_empresa_id` | `()` | `uuid` | Sobrecarga sem argumento. |
| `public.current_empresa_id` | `(p_tenant_id uuid)` | `uuid` | Sobrecarga com tenant explícito. |
| `m.fn_orcamento_atualizar_status` | `(p_orcamento_id uuid, p_status text, p_followup text, p_valor_fechado numeric, p_abrir_os boolean, p_importar_itens_os boolean)` | `TABLE(orcamento_id uuid, os_id integer, numero_os text, valor_orcado numeric, valor_fechado numeric, desconto_valor numeric, itens_importados boolean)` | Função `plpgsql`. |

## Objetos propostos que ainda não existem

No schema auditado, **NÃO EXISTEM — precisam ser criados**, depois de reparar e validar o histórico de migrations:

- `f.perfil_operacao`
- `f.solicitacao_faturamento`
- `f.solicitacao_item`
- `f.documento_fiscal_emissao`
- `f.documento_fiscal_evento`

