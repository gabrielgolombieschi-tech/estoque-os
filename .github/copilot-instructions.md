# Padrões do ERP (obrigatório)

## Banco (Postgres/Supabase)
- Schemas por área: a (geral), c (cadastros), m (movimentos), f (fiscal), r (relatórios)
- Multi-tenant obrigatório: toda tabela de negócio tem tenant_id uuid
- PK padrão: id uuid default gen_random_uuid()
- Auditoria mínima: created_at, updated_at timestamptz
- Auditoria autor quando fizer sentido: created_by, updated_by uuid
- Soft delete preferencial: deleted_at timestamptz
- Log de auditoria: audit_log com old_data/new_data jsonb (+ change_reason quando aplicável)

## Normalização de texto
- Cadastros funcionais em MAIÚSCULO: nomes/descrições/endereço/classificações
- Texto livre preservado: observação/comentário/notas
- Campos web em minúsculo: email/username/slug/url
- Documentos/telefone somente números: cpf/cnpj/ie/telefone
- Quando necessário: coluna *_norm = trim + upper + unaccent

## Datas/valores
- date para datas puras; timestamptz para eventos
- timezone: America/Sao_Paulo
- moeda: numeric(15,2); percentual: numeric(7,4)
- guardar base_calculo, aliquota, valor_calculado, valor_ajustado

## Unicidade e naming
- codigo obrigatório em cadastros
- unique (tenant_id, codigo); às vezes unique (tenant_id, nome)
- documentos: modelo, serie, numero e unique (tenant_id, modelo, serie, numero)
- constraints/index:
  - pk_<schema>_<tabela>
  - fk_<tabela>__<coluna>__<ref>
  - uq_<tabela>__<colunas>
  - idx_<tabela>__<colunas>

## Relatórios
- Views de relatório começam com r_ e são read-only


Você está trabalhando no projeto "Criação ERP Completo para lucro real".

REGRAS OBRIGATÓRIAS:
1) Siga integralmente deste arquivo
2) Banco: Postgres/Supabase. Use schemas a/c/m/f/r e multi-tenant com tenant_id uuid em toda tabela de negócio.
3) PK uuid default gen_random_uuid(); auditoria created_at/updated_at timestamptz; soft delete deleted_at.
4) Texto de cadastro em MAIÚSCULO; email/username/url em minúsculo; documentos/telefone só números.
5) Moeda numeric(15,2); percentuais numeric(7,4); datas: date; eventos: timestamptz.
6) Naming de constraints e índices conforme standards.
7) Entregue código pronto e consistente. Se houver tradeoff, explique rápido e escolha a opção mais alinhada ao standards.

CHECKLIST antes de finalizar:
- [ ] Todas tabelas de negócio têm tenant_id?
- [ ] PK uuid + auditoria + soft delete?
- [ ] UQ/IDX nomeados?
- [ ] Normalização de texto aplicada?
- [ ] Datas/valores com tipos corretos?