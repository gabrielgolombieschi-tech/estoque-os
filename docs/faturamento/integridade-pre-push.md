# Integridade referencial e pré-voo do faturamento

**Estado final em 01/09/2026: APLICADO E VALIDADO — histórico local/remoto alinhado.**

- `cliente_id` e `item_id` agora usam o tipo real (`integer`) e o smoke liga solicitação, emissão e documento a registros reais.
- As referências concretas novas ganharam FK com escopo de `tenant_id` e `empresa_id`; o smoke rejeitou um item da empresa errada.
- A leitura de produção encontrou **7 documentos**, envolvendo **6 clientes**, cujo cliente pertence a outra empresa do mesmo tenant. A FK passou a `NOT VALID`: protege novas escritas, mas só poderá ser validada depois do saneamento.
- As 360 migrations históricas receberam marcadores locais sem DDL; os SQLs originais continuam preservados em `_arquivo/` e o baseline continua responsável pelo reset local.
- O baseline `00000000000000` foi marcado como aplicado remotamente, sem executar seu DDL. O dry-run listou somente as migrations novas.
- O lote `120000` a `130000` e a correção `131000` de grants foram aplicados. O histórico terminou com **369 versões alinhadas, zero somente local e zero somente remota**.

## 1. Escopo e método

Foram revisadas integralmente as migrations `120000` a `124000`. Como as migrations `125000` e `130000` foram criadas depois do briefing, também entraram no lote: a `125000` tinha três referências concretas sem FK e foi corrigida; a `130000` não cria coluna de referência.

Os tipos foram conferidos no schema reconstruído do baseline e comparados com as tabelas reais. Depois do backup e do dry-run, as migrations autorizadas foram aplicadas remotamente e validadas pela API com `service_role`.

## 2. Inventário de tipos e referências

`int4` abaixo corresponde a `integer`; `int8`, a `bigint`.

| Migration | Tabela.coluna | Tipo declarado final | Alvo real | Tipo do alvo | Veredito / garantia |
|---|---|---:|---|---:|---|
| 120000 | `f.documento_fiscal.tenant_id` | `uuid` | `c.empresa.tenant_id` | `uuid` | bate; FK composta com empresa |
| 120000 | `f.documento_fiscal.empresa_id` | `uuid` | `c.empresa.id` | `uuid` | bate; FK composta |
| 120000 | `f.documento_fiscal.cliente_id` | `int4` | `public.clientes.id` | `int4` | bate; FK composta `NOT VALID` por 7 linhas legadas |
| 120000 | `f.documento_fiscal.nfe_referenciada` | `text` | chave de NF-e externa | `text(44)` lógico | bate; sem FK, com `CHECK` de 44 dígitos |
| 120000 | `f.documento_fiscal_item.id` | `uuid` | PK própria | `uuid` | bate |
| 120000 | `f.documento_fiscal_item.documento_fiscal_id` | `uuid` | `f.documento_fiscal.id` | `uuid` | bate; FK por tenant e empresa |
| 120000 | `f.documento_fiscal_item.tenant_id` | `uuid` | documento/empresa | `uuid` | bate; participa das FKs compostas |
| 120000 | `f.documento_fiscal_item.empresa_id` | `uuid` | documento/item | `uuid` | bate; preenchida a partir do documento no legado |
| 120000 | `f.documento_fiscal_item.item_id` | `int4` | `public.itens.id` | `int4` | bate; FK composta |
| 120000 | `f.perfil_operacao.id` | `uuid` | PK própria | `uuid` | bate; índice `(tenant_id,id)` para referência |
| 120000 | `f.perfil_operacao.tenant_id` | `uuid` | `c.tenant.id` | `uuid` | bate; FK |
| 120000 | `f.perfil_operacao.empresa_id` | `uuid` | `c.empresa.id` | `uuid` | bate; FK composta; nulo representa perfil global |
| 120000 | `f.solicitacao_faturamento.id` | `uuid` | PK própria | `uuid` | bate; chave composta auxiliar |
| 120000 | `f.solicitacao_faturamento.tenant_id` | `uuid` | `c.empresa.tenant_id` | `uuid` | bate; FK composta |
| 120000 | `f.solicitacao_faturamento.empresa_id` | `uuid` | `c.empresa.id` | `uuid` | bate; FK composta |
| 120000 | `f.solicitacao_faturamento.cliente_id` | `int4` | `public.clientes.id` | `int4` | corrigido de `uuid`; FK composta |
| 120000 | `f.solicitacao_faturamento.perfil_operacao_id` | `uuid` | `f.perfil_operacao.id` | `uuid` | bate; FK com tenant; empresa/global continua regido por RLS/regra da aplicação |
| 120000 | `f.solicitacao_faturamento.criado_por` | `uuid` | `a.usuario.id` | `uuid` | bate; FK. `a.fn_current_usuario_id()` retorna esse ID, não `auth.users.id` |
| 120000 | `f.solicitacao_item.id` | `uuid` | PK própria | `uuid` | bate |
| 120000 | `f.solicitacao_item.solicitacao_id` | `uuid` | `f.solicitacao_faturamento.id` | `uuid` | bate; FK por tenant e empresa |
| 120000 | `f.solicitacao_item.tenant_id` | `uuid` | solicitação/item | `uuid` | bate; participa das FKs |
| 120000 | `f.solicitacao_item.empresa_id` | `uuid` | solicitação/item | `uuid` | bate; participa das FKs |
| 120000 | `f.solicitacao_item.item_id` | `int4` | `public.itens.id` | `int4` | corrigido de `uuid`; FK composta |
| 120000 | `f.solicitacao_item.origem_id` | `text` | polimórfica | `int4`/indefinido | sem FK; decisão de modelagem pendente |
| 120000 | `f.solicitacao_item.origem_item_id` | `text` | polimórfica | `int4`/indefinido | sem FK; decisão de modelagem pendente |
| 120000 | `f.documento_fiscal_emissao.documento_fiscal_id` | `uuid` | `f.documento_fiscal.id` | `uuid` | bate; FK por tenant e empresa |
| 120000 | `f.documento_fiscal_emissao.solicitacao_id` | `uuid` | `f.solicitacao_faturamento.id` | `uuid` | bate; FK por tenant e empresa |
| 120000 | `f.documento_fiscal_emissao.tenant_id` / `empresa_id` | `uuid` | escopo dos pais | `uuid` | bate |
| 120000 | `f.documento_fiscal_evento.id` | `uuid` | PK própria | `uuid` | bate |
| 120000 | `f.documento_fiscal_evento.documento_fiscal_id` | `uuid` | `f.documento_fiscal.id` | `uuid` | bate; FK por tenant e empresa |
| 120000 | `f.documento_fiscal_evento.tenant_id` / `empresa_id` | `uuid` | escopo do documento | `uuid` | bate |
| 120000 | `f.documento_fiscal_evento.criado_por` | `uuid` | `a.usuario.id` | `uuid` | bate; FK |
| 121000 | `public.fiscal_itens.id` | `int8` | PK própria | `int8` | bate; não é referência a item |
| 121000 | `public.fiscal_itens.item_id` | **`int4`** | `public.itens.id` | `int4` | **corrigido de `int8`**; FK composta |
| 121000 | `public.fiscal_itens.tenant_id` / `empresa_id` | `uuid` | escopo de `public.itens` | `uuid` | bate; FK composta |
| 122000 | `public.clientes.codigo_ibge_municipio` | `text` | código externo IBGE | `text` | sem FK local por ser catálogo externo |
| 123000 | — | — | — | — | não cria nem altera referência |
| 124000 | `NEW.id` do trigger | `int4` | `public.fiscal_itens.item_id` | `int4` | bate após 121000 |
| 125000 | `parametro_...id` | `uuid` | PK própria | `uuid` | bate |
| 125000 | `parametro_...tenant_id` / `empresa_id` | `uuid` | `c.empresa` | `uuid` | FK composta adicionada |
| 125000 | `parametro_...corrigido_por_auth` | `uuid` | `auth.users.id` | `uuid` | FK adicionada, `ON DELETE SET NULL` |
| 130000 | — | — | — | — | somente troca índices de unicidade de fornecedor |

### Por que `fiscal_itens.item_id bigint` não falhava antes

PostgreSQL aceitava a FK entre tipos numéricos comparáveis. Portanto, a existência da FK antiga não garantia igualdade de tipo. A migration agora converte a coluna para `integer`; qualquer valor fora de `int4` falharia na conversão. A leitura remota encontrou zero valores fora do intervalo e zero itens fiscais órfãos ou fora do escopo.

## 3. FKs adicionadas e exceções

Foram adicionadas ou reforçadas FKs para:

- documento → empresa e cliente;
- item do documento → documento e item de cadastro;
- perfil → tenant e empresa;
- solicitação → empresa, cliente, perfil e usuário interno;
- item solicitado → solicitação e item de cadastro;
- emissão → documento e solicitação;
- evento → documento e usuário interno;
- `fiscal_itens` → item, sempre com tenant e empresa;
- memória de descrição da IA → empresa e usuário autenticado.

As chaves compostas exigiram índices únicos auxiliares em `c.empresa`, `f.documento_fiscal` e `f.perfil_operacao`. O escopo cruzado é, assim, inválido no banco mesmo quando a escrita usa service role.

### FK deliberadamente `NOT VALID`

```sql
alter table f.documento_fiscal
  add constraint fk_documento_fiscal__tenant_empresa_cliente__clientes
  foreign key (tenant_id, empresa_id, cliente_id)
  references public.clientes (tenant_id, empresa_id, id)
  not valid;
```

Ela valida toda inserção ou alteração nova. Apenas as 7 linhas já existentes ficam temporariamente toleradas. Depois do saneamento:

```sql
alter table f.documento_fiscal
  validate constraint fk_documento_fiscal__tenant_empresa_cliente__clientes;
```

### Referências sem FK, com motivo

| Campo | Motivo |
|---|---|
| `solicitacao_item.origem_id` | polimórfica; pode ser OS/OV, avulso ou contrato |
| `solicitacao_item.origem_item_id` | polimórfica e dependente do tipo acima |
| `documento_fiscal.nfe_referenciada` | chave de documento fiscal externo; `CHECK` de 44 dígitos |
| chaves de acesso, protocolo e referência do gateway | identificadores externos, sem tabela local soberana |
| `clientes.codigo_ibge_municipio` | catálogo oficial externo; validação deve usar catálogo/versionamento próprio se ele for internalizado |
| `solicitacao_item.pedido_linha` | identificador informado pelo cliente, não PK interna |

## 4. Referências polimórficas

Mapa verificado:

| `origem_tipo` | Pai provável | Item provável | Situação |
|---|---|---|---|
| `OS` | `public.ordens_servico.id` (`int4`) | `public.os_itens.id` (`int4`) | alvo concreto |
| `OV` | `public.ordens_servico.id` (`int4`, discriminado por `tipo_documento='OV'`) | `public.os_itens.id` (`int4`) | alvo concreto |
| `AVULSO` | nenhum | nenhum ou item cadastrado já coberto por `item_id` | texto genérico é desnecessário |
| `CONTRATO` | indefinido | indefinido | existe `f.arrendamento_contrato` (`uuid`), mas não há prova de que seja o contrato de venda pretendido |

**Recomendação, não decisão:** substituir a parte conhecida por `ordem_servico_id integer` e `ordem_servico_item_id integer`, ambas com FK composta de escopo, mantendo um `CHECK` coerente com `origem_tipo`. Só criar `contrato_id` após definir qual tabela é soberana.

Trade-off: colunas separadas aumentam o schema e exigem migração dos consumidores, mas tornam lixo e cruzamento de tenant impossíveis. Manter `text` simplifica a primeira escrita, porém transfere toda integridade para código e permite valores como `abc`, ID inexistente ou ID de outra empresa.

## 5. Snapshot fiscal e versão do `cClassTrib`

O snapshot histórico foi colocado em `f.documento_fiscal_item`, não apenas no rascunho `f.solicitacao_item`. Ele contém item interno, CST/CSOSN, IPI/PIS/COFINS, benefício, redução, unidade tributável, IBS/CBS, `cClassTrib`, versão da tabela e `snapshot_fiscal_em`.

Regras incorporadas ao schema:

- CST de ICMS e CSOSN são mutuamente exclusivos;
- `cClassTrib` exige `cclass_trib_versao` não vazia;
- os três primeiros dígitos de `cClassTrib` devem coincidir com o CST IBS/CBS quando ambos existirem;
- o comentário de `snapshot_fiscal_em` define que o congelamento ocorre no documento autorizado, nunca no rascunho.

Ainda falta ao futuro emissor preencher esses campos **na mesma transação que registra a autorização**. A migration cria a garantia estrutural; ela não afirma que a Edge Function, ainda não implementada, já realiza o ato.

## 6. Conferência somente leitura em produção

Retrato obtido durante este pré-voo; a base continuava em uso e deve ser recontada na janela:

| Conjunto | Linhas lidas |
|---|---:|
| `f.documento_fiscal` | 2.379 |
| `public.fiscal_itens` | 3.157 |
| `public.itens` (ativos e inativos) | 3.552 |
| `public.clientes` | 80 |
| `c.empresa` projetada em `public.empresas` | 4 |

| Verificação | Violações |
|---|---:|
| documento → empresa no mesmo tenant | 0 |
| documento → cliente no mesmo tenant e empresa | **7** |
| fiscal item → empresa no mesmo tenant | 0 |
| fiscal item → item no mesmo tenant e empresa | 0 |
| `fiscal_itens.item_id` fora do intervalo de `integer` | 0 |

As 7 violações de cliente apontam para clientes existentes no mesmo tenant, porém em outra empresa; são 6 IDs de cliente distintos. Não são IDs órfãos. Isso exige decisão de negócio: corrigir o `cliente_id` do documento para o cadastro equivalente da empresa emissora, criar o cadastro faltante e relinkar, ou formalizar outro modelo de cliente compartilhado. Nenhuma dessas opções foi inferida nem executada.

Antes da `131000`, `f.documento_fiscal_item` não podia ser lida por PostgREST com `service_role`. Após a migration de grants, a leitura retornou HTTP 200 e confirmou 207 linhas: zero sem empresa, sem pai ou fora do escopo.

Consulta equivalente para repetir no acesso SQL de produção:

```sql
begin read only;

select count(*) as documentos_cliente_fora_do_escopo
from f.documento_fiscal d
left join public.clientes c
  on c.tenant_id = d.tenant_id
 and c.empresa_id = d.empresa_id
 and c.id = d.cliente_id
where d.cliente_id is not null
  and c.id is null;

select count(*) as itens_documento_pai_fora_do_escopo
from f.documento_fiscal_item di
left join f.documento_fiscal d
  on d.tenant_id = di.tenant_id
 and d.id = di.documento_fiscal_id
where d.id is null;

select count(*) as fiscal_item_fora_do_escopo
from public.fiscal_itens fi
left join public.itens i
  on i.tenant_id = fi.tenant_id
 and i.empresa_id = fi.empresa_id
 and i.id = fi.item_id
where i.id is null;

rollback;
```

## 7. Pré-voo e aplicação: resultado

### Histórico de migrations

Antes do alinhamento, `supabase migration list --linked` mostrava:

- baseline local `00000000000000`: existe só localmente;
- centenas de migrations entre 2024 e `20260831144500`: existem só remotamente;
- `20260901120000` a `20260901130000`: existem só localmente.

Foram criados 360 marcadores locais com as mesmas versões remotas. Cada marcador contém apenas comentários; o SQL histórico original permanece em `_arquivo/`. Depois do backup, `migration repair --status applied 00000000000000` registrou somente o baseline no histórico remoto, sem executar DDL.

Resultado depois do alinhamento e da aplicação:

```text
ALIGNED=369
ONLY_LOCAL=0
ONLY_REMOTE=0
Remote database is up to date.
```

### Resultado de `supabase db diff --linked`

O comando foi executado somente em leitura e terminou. O retorno teve 724 linhas e aproximadamente 124 mil tokens. Entre as operações propostas estavam:

```sql
drop extension if exists "pg_net";
drop trigger if exists ...;
drop table "f"."documento_fiscal_emissao";
drop table "f"."documento_fiscal_evento";
drop table "f"."perfil_operacao";
drop table "f"."solicitacao_faturamento";
drop table "f"."solicitacao_item";
alter table "f"."documento_fiscal_item" drop column ...;
```

Isso é DDL de **convergência entre o shadow das migrations e o remoto**, na direção calculada pelo `db diff`; não é a lista de migrations que o `db push` aplicaria. Executá-lo seria destrutivo e está fora de cogitação.

A documentação oficial distingue os comandos: [`db diff`](https://supabase.com/docs/reference/cli/supabase-db-diff) compara schemas por meio de um shadow database; a prévia oficial das migrations a aplicar é `supabase db push --dry-run`, documentada em [`db push`](https://supabase.com/docs/reference/cli/supabase-db-push). Depois da autorização explícita, o dry-run foi executado e listou somente `120000` a `130000`. Após esse lote, um novo dry-run listou apenas `131000`, criada para corrigir os grants descobertos no teste pós-push.

O primeiro push aplicou somente as sete migrations previstas. A validação via PostgREST encontrou 403 nas novas tabelas `f.*`; a causa era RLS sem privilégios de tabela. A correção foi feita pela migration `20260901131000_faturamento_grants_api.sql`, aplicada e retestada antes do encerramento.

### Migrations aplicadas e hashes do lote original

| Migration | SHA-256 |
|---|---|
| `20260901120000_faturamento_fundacao.sql` | `73582d9c30a1ccbab40529f4e9eb085aa811d0d22f5bfd0cc447dd5943c4ca2c` |
| `20260901121000_faturamento_itens_campos_fiscais.sql` | `24228e7c05e4087803003301fb234b9bf21526a189749b382f9fce8a32570fe8` |
| `20260901122000_faturamento_clientes_campos_fiscais.sql` | `eb59d90616c1aef022c6b1fc50640286bae13359b1c24f3e032abee3196b788c` |
| `20260901123000_faturamento_status_fluxo_parcial.sql` | `54da68e0f8016d535a6dedbb91d3c7e663bdeffdfc36b877f086b426128ffd37` |
| `20260901124000_fiscal_itens_linhas_automaticas.sql` | `0bdb878b5424cb63d496662b86eb3695dc66eb5f982008085b48312e5da19288` |
| `20260901125000_parametro_descricao_ia_importacao_xml.sql` | `891d87114cef896be227ee53769ef62518cbf74ab1719f262829e9041092ae9f` |
| `20260901130000_fornecedores_unicidade_por_empresa.sql` | `8bb83aada8de12faeac0ec15f8eb422fa90d6f159afcd078a14e20bcd43f9e20` |
| `20260901131000_faturamento_grants_api.sql` | `ce57dfcf8f07d05feba7fc1a51ef61cc1f536acdaa91e91960965b6a130d2580` |

Se qualquer arquivo mudar, os hashes e esta análise devem ser regenerados.

## 8. DDL pretendido, locks e rollback

Esta é a análise feita antes da aplicação e mantida como roteiro de rollback.

| Migration / comando | Objeto existente afetado | Lock/impacto esperado | Inverso técnico |
|---|---|---|---|
| 120000: `ALTER TABLE f.documento_fiscal` + índices únicos | 2.379 documentos | `ACCESS EXCLUSIVE` nos alters; índice comum bloqueia escrita durante construção | remover FKs/índices e colunas `origem`, `nfe_referenciada`; recriar FKs simples originais |
| 120000: adicionar snapshot e escopo a `f.documento_fiscal_item` + `UPDATE` | tabela de itens fiscais de documento | `ACCESS EXCLUSIVE`; update e validação podem varrer a tabela | remover FKs/colunas novas e recriar FK simples do documento; valores gravados nas colunas novas seriam perdidos |
| 120000: `itens.fabricado` | 3.552 itens totais no retrato | `ACCESS EXCLUSIVE` breve; default constante tende a ser metadado em PostgreSQL atual | `alter table public.itens drop column fabricado` |
| 120000: `os_itens.finalidade` | tabela operacional | `ACCESS EXCLUSIVE` breve | `alter table public.os_itens drop column finalidade` |
| 120000: criar perfil, solicitação, emissão e evento | tabelas novas | locks de catálogo; sem varredura de legado | remover triggers e tabelas novas na ordem inversa |
| 121000: `fiscal_itens.item_id bigint → integer` | 3.157 linhas | `ACCESS EXCLUSIVE` e possível reescrita; conversão falha se sair de `int4` | remover FK, alterar de volta para `bigint`, recriar FKs antigas |
| 121000: `unidade_tributavel` | `fiscal_itens` | `ACCESS EXCLUSIVE` breve | remover coluna |
| 122000: duas colunas em `clientes` | 80 clientes | `ACCESS EXCLUSIVE` breve | remover `indicador_ie` e `codigo_ibge_municipio` |
| 123000: trocar `CHECK` de OS | `ordens_servico` | `ACCESS EXCLUSIVE`; `ADD CHECK` valida todas as linhas | restaurar check original sem `parcialmente_faturada` |
| 124000: `INSERT ... ON CONFLICT DO NOTHING` | `itens` e `fiscal_itens` | `ACCESS SHARE` na origem e `ROW EXCLUSIVE` no destino; volume deve ser recontado na janela | não há delete seguro após uso; restaurar backup se for necessário desfazer dados |
| 124000: função + trigger de linha fiscal | `itens` | criação do trigger bloqueia concorrência DDL e brevemente escrita | remover trigger e função; linhas já criadas exigem análise, não delete genérico |
| 125000: tabela de memória da descrição | tabela nova | locks de catálogo | remover policy, trigger, índice e tabela |
| 130000: substituir unicidade de fornecedor | `fornecedores` | criação de índice único comum bloqueia escrita e pode falhar se houver duplicidade | remover índices por empresa e recriar exatamente os índices legados do baseline |

O PostgreSQL usa `ACCESS EXCLUSIVE` como lock padrão de `ALTER TABLE` quando a subforma não documenta lock menor; `CREATE INDEX` comum permite leitura, mas bloqueia escrita. Referências: [`ALTER TABLE`](https://www.postgresql.org/docs/current/sql-altertable.html) e [`CREATE INDEX`](https://www.postgresql.org/docs/current/sql-createindex.html).

O tempo de execução provável, pelo volume atual, é de segundos a poucos minutos. O risco dominante é **espera por lock**, não volume. Reservar 15 minutos de sistema sem uso, backup confirmado, `lock_timeout` curto e abortar a janela se houver espera. Essa estimativa só vale depois de fechar os dois bloqueios do pré-voo.

### Roteiro de rollback

1. Se qualquer migration falhar dentro da própria transação, deixar o PostgreSQL fazer rollback; não executar compensação manual parcial.
2. Se a aplicação ainda não tiver escrito dados, usar os inversos da tabela acima em migration própria, na ordem `130000 → 120000`.
3. Se já houver snapshot fiscal, memória da IA ou linhas fiscais novas, **não usar `DROP`/`DELETE` genérico**: restaurar o backup em ambiente isolado, extrair os dados criados e decidir a reversão por chave.
4. Os índices legados de fornecedor estão transcritos no baseline nas linhas que criam `fornecedores_documento_norm_uniq`, `fornecedores_tenant_documento_key_uidx`, `fornecedores_tenant_documento_norm_uidx`, `fornecedores_tenant_documento_norm_uk` e `ux_fornecedores_tenant_documento_norm`; esses comandos, e não uma definição inventada durante a janela, são o inverso da 130000.

## 9. Smoke de integridade

Arquivo: `supabase/tests/faturamento_integridade_pre_push.sql`.

O teste:

1. abre transação;
2. cria tenant, duas empresas e suas projeções públicas;
3. cria cliente e itens reais, capturando IDs `integer` gerados pelo banco;
4. cria perfil, solicitação e item solicitado ligados a esses IDs;
5. cria `documento_fiscal` com `origem='EMITIDO'`, emissão `AUTORIZADA` e item do documento com snapshot;
6. tenta usar, na primeira empresa, o item e o cliente reais da segunda empresa e exige `foreign_key_violation`, inclusive na FK de documento marcada `NOT VALID`;
7. termina em `ROLLBACK`.

Resultado final:

```text
cliente_real_id = integer gerado pelo banco
item_real_id = integer gerado pelo banco
documento_origem = EMITIDO
emissao_status = AUTORIZADA
item_cruzado_rejeitado = true
cliente_cruzado_rejeitado = true
fk_not_valid_rejeitou_nova_escrita = true
ROLLBACK
```

O smoke desabilita temporariamente apenas o trigger contábil `trg_documento_fiscal__ar_nfe`, pois ele exige plano de contas completo. As FKs e os checks permanecem ativos durante todo o teste.

## 10. Validações executadas

| Validação | Resultado |
|---|---|
| `npx supabase db reset --local` | passou do zero com baseline + 360 marcadores + 8 migrations novas |
| smoke de integridade com rollback | passou; cruzamento de empresa rejeitado |
| `/financeiro/gestao-cobranca` | HTTP 200 |
| `npx tsc --noEmit` | passou |
| ESLint nos arquivos TypeScript alterados | passou |
| `npx supabase db lint --local` | 10 erros e 53 avisos preexistentes do baseline; nenhum foi alterado nesta tarefa |
| backup remoto | schema, dados e roles gerados e verificados por SHA-256 |
| escrita em produção | somente histórico do baseline e migrations autorizadas |
| `migration repair` | baseline `00000000000000` marcado como aplicado; nenhum DDL do baseline executado |
| `db push` | migrations `120000` a `131000` aplicadas; dry-run final informa banco atualizado |
| acesso PostgREST às tabelas novas | HTTP 200 com service role após `131000` |

## 11. Estado depois da aplicação

- [x] Backup remoto de schema, dados e roles.
- [x] 360 versões históricas representadas localmente e preservadas em `_arquivo/`.
- [x] Baseline alinhado no histórico remoto.
- [x] Dry-run contendo somente migrations novas.
- [x] Migrations `120000` a `131000` aplicadas.
- [x] 3.495 itens ativos; **zero sem linha em `fiscal_itens`**.
- [x] 207 itens de documento; zero sem empresa, sem pai ou fora do escopo.
- [x] Novas tabelas e snapshot acessíveis via PostgREST.
- [ ] Sanear, em tarefa separada, as 7 referências históricas documento → cliente fora da empresa correta. A FK `NOT VALID` já impede novos casos e essa pendência não bloqueia migrations futuras.

O fluxo normal de migrations está documentado em `docs/faturamento/fluxo-migrations.md`.
