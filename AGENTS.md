# Instruções do Projeto

## Contexto
- Projeto: `estoque-os`
- Stack principal: Next.js (App Router) + Supabase + PostgreSQL
- Tema UI predominante: dark
- Idioma de negócio e interface: PT-BR

## Regras obrigatórias
- Sempre respeitar escopo por `tenant_id` e `empresa_id` em queries, RPCs e scripts.
- Evitar qualquer alteração destrutiva sem solicitação explícita.
- Não remover compatibilidade existente sem alinhamento.
- Em telas e relatórios, manter consistência visual e terminologia já usada no sistema.

## Banco e migrações
- Toda mudança estrutural deve ser feita por migration em `supabase/migrations`.
- Preferir `create or replace function` para ajustes de função.
- Se mudar assinatura/retorno de função SQL, usar `drop function ...` antes.
- Validar migrações localmente e depois aplicar no remoto com:
  - `npx supabase db push`

## Padrões de relatórios
- Formatação numérica e monetária em PT-BR.
- Números alinhados à direita, textos à esquerda.
- Filtros devem refletir em URL quando a tela usar filtros compartilháveis.
- Exportações (CSV/PDF) devem refletir os mesmos dados/estado visual da tela.

## Fluxos críticos de estoque
- Entrada por XML (com ou sem OS).
- Entrada manual (ajustes e inventário).
- Baixa de estoque por OS.
- Inclusão/remoção/edição de item em OS com reflexo correto em movimentações.
- Evitar saldo negativo sem tratamento explícito.

## Qualidade e validação
- Rodar lint nos arquivos alterados.
- Validar cenário funcional mínimo após mudanças:
  - Carregamento da tela afetada.
  - Filtros principais.
  - Exportação (quando houver).
  - Ausência de erro de RPC/SQL no console.

## Comandos úteis
- Desenvolvimento: `npm run dev`
- Lint: `npx eslint <arquivos>`
- Migrações remotas: `npx supabase db push`
- Reset local (quando necessário): `npx supabase db reset`

## Diretriz de implementação
- Fazer mudanças pequenas e rastreáveis.
- Priorizar correção de causa raiz.
- Documentar decisões curtas no PR/commit quando houver trade-off.
