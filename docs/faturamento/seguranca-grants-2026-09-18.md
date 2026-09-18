# Grants de funções expostas pela API (levantamento de 18/09/2026)

Pedido do Gabriel: fechar ao `anon` as RPCs do schema `f`, provar que as SECURITY DEFINER checam o
usuário antes de escrever, mapear as RPCs de `public`, `a` e `m` abertas ao `anon`, e fazer função
nova nascer sem EXECUTE para `anon`/PUBLIC. Consultas: `pg_proc` + `has_function_privilege`,
`pg_default_acl`; código: `app/`, `lib/`, `scripts/`, `supabase/functions/`, `estoque-os-mobile/src`,
`site-segau`.

## 1. Schema `f`: 29 RPCs fechadas (migration `20260918070000_schema_f_rpcs_fechadas_para_anon.sql`)

Antes, 29 funções `app_*`/`fn_*` de `f` (sem gatilhos) eram executáveis pelo `anon` só pelo EXECUTE
padrão do PostgreSQL (PUBLIC), nunca por grant explícito. Depois: `revoke ... from public, anon` e
`grant ... to authenticated, service_role` em cada assinatura; a migration termina com um assert que
falha se alguma continuar aberta ao `anon`.

Quem chama no código (todas com sessão do usuário):

| Função | Chamada por |
| --- | --- |
| `fn_devolucao_compra_preparar` | `app/faturamento/operacoes/DevolucaoCompraPanel.tsx` |
| `fn_estorno_criar`, `fn_operacao_registrar_chave`, `fn_operacao_validar_homologacao`, `fn_remessa_criar`, `fn_remessa_prazo_configurar`, `fn_retorno_criar`, `fn_venda_ordem_criar` | `app/faturamento/operacoes/OperacoesFiscaisClient.tsx` |
| `fn_operacao_assert_acesso` | Edge `nfse-ciclo` (`user.schema("f").rpc(...)`, com o token do usuário) |
| as outras 19 (`fn_calc_vencimento`, `fn_cfop_devolucao_proposto`, `fn_cfop_estorno_proposto`, `fn_gerar_ap_irpj_csll`, `fn_validar_pos_importacao`, ...) | só por outras funções do banco |

Lista completa com assinaturas na própria migration. Observações da varredura: `fn_cfop_devolucao_proposto`
e `fn_cfop_estorno_proposto` não têm `search_path` fixo (SECURITY INVOKER, sem escrita);
`fn_calc_vencimento`, `fn_gerar_ap_irpj_csll` e `fn_validar_pos_importacao` usam
`pg_catalog, f, public, a, c, m, r, auth, extensions`.

## 2. As 12 SECURITY DEFINER de `f` abertas ao anon: checam o usuário antes de escrever?

Todas têm `SET search_path TO 'pg_catalog'` e `row_security off`. "Linha" é a linha do corpo em
`pg_get_functiondef` (online, 18/09/2026).

| Função | Checa uid antes de escrever | Linha | 1ª escrita (linha) |
| --- | --- | --- | --- |
| `fn_devolucao_compra_criar` | sim (`f.fn_operacao_assert_acesso()`) | 14 | `insert f.operacao_fiscal` (19) |
| `fn_devolucao_compra_preparar` | sim | 13 | sem escrita |
| `fn_estorno_criar` | sim | 10 | `insert f.operacao_fiscal` (18) |
| `fn_operacao_assert_acesso` | é a própria checagem: `auth.uid() is null or not f.has_finance_access()` → 42501 | 1 | sem escrita |
| `fn_operacao_registrar_chave` | sim | 10 | `update f.operacao_fiscal` (16) |
| `fn_operacao_validar_homologacao` | sim | 10 | sem escrita |
| `fn_remessa_criar` | sim | 10 | `insert f.operacao_fiscal` (18) |
| `fn_remessa_prazo_configurar` | sim | 10 | `insert f.remessa_prazo_config` (13) |
| `fn_retorno_criar` | sim | 10 | `insert f.operacao_fiscal` (17) |
| `fn_solicitacao_nfe_resolver_perfis` | lê o papel do JWT (`auth.jwt()->>'role'`) | 9 | sem escrita |
| `fn_venda_ordem_criar` | sim | 10 | `insert f.operacao_fiscal` (17) |
| **`fn_os_reverter_faturada_sem_nota(p_tenant_id, p_empresa_id, p_os_id)`** | **não**: `auth.uid()` só aparece na linha 60, como `realizado_por` do evento, depois do `update public.ordens_servico` (49) | 60 | `update public.ordens_servico` (49) |

`fn_os_reverter_faturada_sem_nota` recebe tenant e empresa por parâmetro, roda com RLS desligada e
não confere `auth.uid()` nem o tenant do chamador: qualquer papel com EXECUTE (até 18/09, o `anon`)
podia voltar uma OS FATURADA de qualquer tenant para "concluída", desde que ela tivesse documento
fiscal de saída vinculado e nenhuma nota válida (os guards das linhas 28–47 são sobre a OS, não
sobre quem chama). Depois da migration 070000 só `authenticated` e `service_role` executam; um
usuário autenticado de outro tenant ainda passa. **Não corrigida**: aguarda o ok do Gabriel.
Correção proposta: exigir `session_user = 'postgres' or auth.jwt()->>'role' = 'service_role'`
(ela é chamada pela finalização do cancelamento da NF-e, no banco) ou validar
`p_tenant_id`/`p_empresa_id` contra `f.fn_operacao_assert_acesso()`.

## 3. Schemas `public`, `a` e `m`: RPCs abertas ao anon (só mapa, nada revogado)

Origem do EXECUTE do `anon`: em `public`, o privilégio padrão do Supabase (`pg_default_acl`:
anon/authenticated/service_role); em `a` e `m`, o PUBLIC do PostgreSQL. O `site-segau` não usa
Supabase (nenhum arquivo cita `supabase`): **não há link público** que dependa do `anon`.

| Função | Quem chama | Sessão |
| --- | --- | --- |
| `public.app_lancar_material_os`, `app_lancar_material_os_por_item_id` | mobile `app/os/[id]/lancar-material.tsx` | com sessão (as telas ficam atrás do `useSession`; `_layout` redireciona para o login) |
| `public.app_listar_apontamentos`, `app_resumo_materiais_os` | mobile `app/os/[id].tsx` | com sessão |
| `public.app_listar_os`, `app_listar_os_fluxo` | mobile `app/(tabs)/index.tsx`; `scripts/medir-acessos-mobile.mjs` (medição, com login) | com sessão |
| `public.app_orcamento_do_cliente`, `app_orcamento_agrupado_cliente` | mobile `app/(tabs)/orcamento.tsx` (aba Orçamento, `supabase.rpc(...)` depois do login) | com sessão; **não há link público** no web nem no site |
| `public.fn_calc_horas_2_periodos`, `fn_calc_horas_periodos`, `fn_documento_key`, `fn_fix_nf_entrada_pos_import`, `fn_fornecedor_upsert_por_documento`, `fn_hh_sync_apontamento_key`, `fn_nf_entrada_sync_estoque_df`, `fn_normalize_documento`, `fn_percentual_por_data`, `fn_regerar_parcelas_titulo_from_xml`, `fn_xml_strip_default_namespace` | nenhuma chamada no código; usadas dentro do banco (gatilhos e outras funções: `fn_hh_criar_apontamento`, `import_nf_entrada`, `fn_ensure_titulo_ap_from_nf_entrada`, `sync_usuario_access_projection`, ...) | — |
| `a.fn_map_papel_empresa`, `fn_map_papel_empresa_to_role`, `fn_map_papel_tenant`, `fn_map_papel_tenant_to_role` | nenhuma chamada no código; helpers de `a_is_tenant_role`/projeção de acessos | — |
| `m.fn_orcamento_item_calcular` | nenhuma chamada no código; gatilho `trg_orcamento_item_biu` e `fn_orcamento_sync_itens` | — |

Recomendação: revogar `anon` e PUBLIC das 24 e dar `authenticated` + `service_role` (mesmo desenho
da migration 070000). As oito `app_*` do mobile continuam funcionando (sessão). As helpers precisam
de `authenticated` porque gatilhos e funções SECURITY INVOKER rodam como o usuário da sessão; nada
precisa de `anon`. Ponto de atenção antes de revogar: `fn_fix_nf_entrada_pos_import` e
`fn_regerar_parcelas_titulo_from_xml` são de manutenção e podem estar em scripts fora do repositório.

## 4. Default privileges (migration `20260918080000_default_privileges_funcoes_sem_anon_public.sql`)

`ALTER DEFAULT PRIVILEGES ... IN SCHEMA` só soma ao padrão global: não tira o PUBLIC do padrão
embutido (doc do PostgreSQL: "Per-schema REVOKE is only useful to reverse the effects of a previous
per-schema GRANT"). Experimento no banco local: `revoke ... in schema f` + `create function` → `proacl`
NULL e o `anon` executa. Por isso o revoke do PUBLIC é global para o `postgres`, e cada schema recebe
de volta o que precisa.

Antes (online, `pg_default_acl` do `postgres`, funções):

| Schema | ACL |
| --- | --- |
| global | (sem entrada: PUBLIC=X) |
| `public` | `{postgres=X, anon=X, authenticated=X, service_role=X}` |
| `m` | `{authenticated=X}` |
| `f`, `c`, `a` | (sem entrada: PUBLIC=X) |
| `storage` | `{postgres=X, anon=X, authenticated=X, service_role=X}` (não mexido) |

Depois:

| Schema | ACL |
| --- | --- |
| global | `{postgres=X}` |
| `public` | `{postgres=X, authenticated=X, service_role=X}` |
| `f`, `m`, `c`, `a` | `{authenticated=X, service_role=X}` (+ dono) |
| `extensions` | `{=X}` (PUBLIC, como hoje: pgcrypto e afins instalados pelo `postgres`) |
| `storage` | inalterado |

Efeito colateral assumido: função nova do `postgres` em schema sem entrada (`r`, `vault`, `net`, ...)
nasce só com o dono; a migration que a criar dá o grant. Só objetos criados depois são afetados.

## 5. `faturamento_nfe_pipeline.sql`, linha 2108 ("Nota ja cancelada aceitou novo claim"): diagnóstico

A guarda de `f.fn_nfe_cancelamento_producao_claim` contra nota já cancelada é **por status**
(`if v_emissao.status <> 'AUTORIZADA' then raise ... 55000`, linha 106 do corpo). Mas antes dela a
função lê o último evento `CANCELAMENTO` (`order by ev.created_at desc, ev.id desc limit 1`, linhas
59–68) e, se ele estiver `ENVIANDO` há menos de 2 minutos, **retorna `aguardar`** sem exceção
(linhas 70–82). `fn_nfe_cancelamento_producao_finalizar` insere um evento novo `AUTORIZADA` e **não
muda o evento do claim**, que fica `ENVIANDO` para sempre.

O teste roda inteiro numa transação (`begin` na linha 2, `rollback` na 2169): `now()` é o mesmo
para o claim e para a finalização, os dois eventos têm o **mesmo `created_at`** e o desempate é pelo
`id`, um `gen_random_uuid()`. Quando o uuid do evento `ENVIANDO` sai maior, o claim seguinte cai no
ramo "aguardar" e o teste explode; quando o do `AUTORIZADA` sai maior, cai na guarda por status e o
teste passa. Reproduzido no banco local: dois inserts com `default now()` na mesma transação, 0,2 s
entre eles, `created_at` idêntico, e a ordem do claim devolveu `ENVIANDO`. Em produção as duas
chamadas são transações diferentes (`created_at` distintos), por isso nunca apareceu lá; é o teste
que expõe uma fragilidade real da função: a ordenação por uuid não é determinística e o claim
`ENVIANDO` nunca é fechado. Sem correção sem o ok do Gabriel. Opções: (a) `finalizar` marcar o evento
do claim como concluído; (b) o claim conferir `v_emissao.status` antes do ramo `ENVIANDO`; (c) o
teste forçar `created_at` distintos.
