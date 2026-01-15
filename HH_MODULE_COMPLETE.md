# Módulo Tabelas HH - Implementação Completa

## ✅ Status: CONCLUÍDO

### 📋 Resumo da Implementação

Módulo completo de gestão de Tabelas HH (Homem-Hora) criado com 3 telas principais + integração com colaboradores + navegação.

---

## 🗂️ Arquivos Criados

### 1. **app/cadastros/hh/especialidades/page.tsx** (280 linhas)
**Função:** CRUD completo de especialidades HH (tipos de trabalho/especialidades profissionais)

**Recursos:**
- ✅ Listagem com busca por descrição (case-insensitive)
- ✅ Criar/editar especialidades com modal
- ✅ Validação de exclusão (verifica uso em tabelas HH e colaboradores)
- ✅ Filtro ativo/inativo
- ✅ Guards de permissão: `os.read` (visualizar), `os.write` (criar/editar), `os.delete` (excluir)
- ✅ Multi-tenant via `applyTenant()`

**Campos:**
- `descricao` (texto, obrigatório)
- `ativo` (boolean)

**Validações:**
- Não permite deletar se houver itens de tabela HH vinculados
- Não permite deletar se houver colaboradores com esta especialidade

---

### 2. **app/cadastros/hh/tabelas/page.tsx** (340 linhas)
**Função:** Listagem e CRUD de tabelas HH por cliente/ano

**Recursos:**
- ✅ Filtros: cliente (dropdown), ano (número), ativo (sim/não/todos)
- ✅ Botão "Aplicar filtros" manual (otimização de queries)
- ✅ Modal criar/editar com validações
- ✅ Auto-preenchimento de vigência (início/fim do ano selecionado)
- ✅ Navegação para detalhe via botão "Abrir"
- ✅ Join com tabela `clientes` para exibir nome

**Campos:**
- `cliente_id` (FK para clientes, obrigatório)
- `ano` (número, obrigatório)
- `nome` (texto, obrigatório)
- `vigencia_inicio` (date, padrão: 1º de janeiro do ano)
- `vigencia_fim` (date, padrão: 31 de dezembro do ano)
- `ativo` (boolean)

**Validações:**
- Cliente obrigatório
- Ano obrigatório
- Nome obrigatório

---

### 3. **app/cadastros/hh/tabelas/[id]/page.tsx** (580 linhas)
**Função:** Gestão de itens da tabela HH + importação CSV

**Recursos Principais:**
- ✅ Grid de itens (especialidade + valor base)
- ✅ Criar/editar/excluir itens individualmente
- ✅ **Importação CSV com recursos avançados:**
  - Auto-detecção de cabeçalho (keywords: descricao, preco, valor, especialidade)
  - Auto-detecção de separador (; ou ,)
  - Parser pt-BR para moeda: `parseMoedaBR("R$ 49,65")` → `49.65`
  - **Auto-criação de especialidades não existentes** (ativo=true)
  - Upsert por `(tabela_id, especialidade_id)` - evita duplicatas
  - Relatório de importação: criadas/atualizadas/erros

**Campos do Item:**
- `especialidade_id` (FK para hh_especialidades, obrigatório)
- `valor_base` (decimal, obrigatório)

**Formato CSV Recomendado:**
```csv
descricao;preco
Engenheiro Eletricista;R$ 120,50
Tecnico Mecanico;85,00
Supervisor de Obra;95,75
```

**Validações:**
- Especialidade obrigatória
- Valor base > 0
- CSV: linhas vazias ignoradas, erros registrados linha-por-linha

---

## 🔧 Arquivos Modificados

### 4. **app/colaboradores/page.tsx**
**Mudanças:**
- ✅ Adicionado tipo `Especialidade` (id, descricao, ativo)
- ✅ Estado `especialidades: Especialidade[]` para dropdown
- ✅ Campo `hh_especialidade_id` no formulário
- ✅ Query modificada para carregar especialidades ativas
- ✅ Select "Especialidade HH" no modal com texto helper: *"Usada para cálculo de Relatórios HH"*
- ✅ Insert/Update incluem `hh_especialidade_id`

**Uso:** Atribuir especialidade a colaboradores para cálculo automático de HH nos relatórios

---

### 5. **app/components/AppShell.tsx**
**Mudanças:**
- ✅ Tipo `openMenu` estendido com `"cadastros"`
- ✅ Variável `canAccessTabelasHH = can("os.read")`
- ✅ Funções `toggleMenu()` e `openWithHover()` aceitam `"cadastros"`
- ✅ **Menu dropdown "Cadastros" adicionado** com links:
  - `/cadastros/hh/especialidades` - Especialidades HH
  - `/cadastros/hh/tabelas` - Tabelas HH

**Guarda de permissão:** Menu aparece apenas se `os.read` estiver ativo

---

## 🗄️ Migrations Aplicadas (Supabase Produção)

### 1. **20260214_fix_empresa_memberships_rls.sql** ✅
- Permite coordenadores ler `empresa_memberships`
- Corrige SELECT policy para roles com `empresas_acesso=true`

### 2. **20260214_gerar_relatorio_hh_os.sql** ✅
- RPC `gerar_relatorio_hh_os(p_os_id BIGINT)` para snapshot de HH
- Calcula custos usando `cliente_hh_tabelas` + `cliente_hh_tabela_itens`
- Armazena snapshot em `apontamentos_horas`

### 3. **20260214_rpc_list_allowed_empresas.sql** ✅
- RPC `list_user_empresas(p_tenant_id TEXT)` para listar empresas do usuário
- Fallback seguro quando RLS bloqueia `empresa_memberships`
- Corrigido para usar `nome_fantasia` ao invés de `nome`

---

## 🎯 Permissões Utilizadas

Todas as telas HH usam guards consistentes:
- `os.read` - Visualizar listas/dados
- `os.write` - Criar/editar registros
- `os.delete` - Excluir registros (apenas especialidades)

**Componente Helper:** `<Can perm="os.write">...</Can>`

---

## 🧪 Testes Recomendados

### Teste 1: Especialidades
1. Navegar para `/cadastros/hh/especialidades`
2. Criar especialidade "Engenheiro Eletricista" (ativo)
3. Criar especialidade "Técnico Mecânico" (ativo)
4. Buscar "eng" → deve filtrar
5. Tentar deletar especialidade em uso (deve bloquear)

### Teste 2: Tabelas HH
1. Navegar para `/cadastros/hh/tabelas`
2. Selecionar cliente existente
3. Criar tabela ano 2025
4. Verificar vigência auto-preenchida (01/01/2025 - 31/12/2025)
5. Clicar "Abrir" → redirecionar para detalhe

### Teste 3: Itens + CSV Import
1. Na tela de detalhe da tabela
2. Adicionar item manual: "Engenheiro Eletricista" - R$ 120,00
3. Preparar CSV:
   ```csv
   descricao;preco
   Tecnico Mecanico;85,50
   Supervisor de Obra;R$ 95,75
   Nova Especialidade;110,00
   ```
4. Importar CSV via modal
5. Verificar:
   - "Nova Especialidade" criada automaticamente em especialidades
   - 3 itens criados/atualizados
   - Relatório mostra: "3 criadas, 0 atualizadas"

### Teste 4: Colaboradores
1. Navegar para `/colaboradores`
2. Editar colaborador existente
3. Selecionar especialidade "Engenheiro Eletricista"
4. Salvar → campo `hh_especialidade_id` gravado

### Teste 5: Integração End-to-End
1. Criar OS para cliente com tabela HH 2025
2. Criar apontamento de horas com colaborador (com especialidade atribuída)
3. Chamar RPC `gerar_relatorio_hh_os(os_id)`
4. Verificar `apontamentos_horas` contém snapshot com `valor_base` da tabela

---

## 📐 Arquitetura Técnica

### Pattern: App Router (Next.js 14)
- Client components com `"use client"`
- Dynamic routes: `[id]/page.tsx` para detalhe
- `useParams()` para route params
- `useRouter()` para navegação programática

### Pattern: Multi-Tenant
- `useTenantEmpresa()` hook para obter `tenantId`
- `applyTenant(query, tenantId)` para todas as queries
- RPC `set_current_tenant()` no boot

### Pattern: Permissions
- `usePermissions()` hook → `has(capability)`
- `<Can perm="os.write">` wrapper component
- Guard em handlers: `if (!canEdit) return setErr("Sem permissão")`

### Pattern: CSV Import (Client-Side)
- FileReader API para ler arquivo
- Regex para detectar separador e cabeçalho
- `parseMoedaBR()` para converter valores pt-BR
- Transaction-like: auto-create missing FKs antes do upsert

### Pattern: Modal Forms
- Estado `showModal` booleano
- `editingId` para create vs update
- `setErr()` / `setOk()` para feedback visual
- `backdrop-blur-sm` overlay com click-outside to close

---

## 🔗 Navegação Criada

### Menu Principal (AppShell)
```
Home | OS | Estoque | Financeiro | Cadastros ⮟ | Usuarios
                                      │
                                      ├─ Especialidades HH
                                      └─ Tabelas HH
```

### Fluxo de Navegação
1. `/cadastros/hh/especialidades` → Criar especialidades
2. `/cadastros/hh/tabelas` → Listar tabelas → Clicar "Abrir"
3. `/cadastros/hh/tabelas/[id]` → Gerenciar itens + CSV import
4. `/colaboradores` → Atribuir especialidade a pessoas
5. (Futuro) Relatórios HH usarão estes dados

---

## 📊 Estrutura de Dados

### Tabelas (Schema)
```sql
hh_especialidades (
  id SERIAL,
  tenant_id TEXT,
  descricao TEXT NOT NULL,
  ativo BOOLEAN DEFAULT true,
  criado_em TIMESTAMP,
  atualizado_em TIMESTAMP
)

cliente_hh_tabelas (
  id SERIAL,
  tenant_id TEXT,
  cliente_id BIGINT NOT NULL,  -- FK clientes
  ano INT NOT NULL,
  nome TEXT NOT NULL,
  vigencia_inicio DATE,
  vigencia_fim DATE,
  ativo BOOLEAN DEFAULT true,
  criado_em TIMESTAMP,
  atualizado_em TIMESTAMP
)

cliente_hh_tabela_itens (
  id SERIAL,
  tenant_id TEXT,
  tabela_id BIGINT NOT NULL,          -- FK cliente_hh_tabelas
  especialidade_id BIGINT NOT NULL,   -- FK hh_especialidades
  valor_base DECIMAL(10,2) NOT NULL,
  criado_em TIMESTAMP,
  atualizado_em TIMESTAMP,
  UNIQUE(tabela_id, especialidade_id)
)

colaboradores (
  id SERIAL,
  ...
  hh_especialidade_id BIGINT,  -- FK hh_especialidades
  ...
)
```

### Relacionamentos
- `cliente_hh_tabelas.cliente_id` → `clientes.id`
- `cliente_hh_tabela_itens.tabela_id` → `cliente_hh_tabelas.id`
- `cliente_hh_tabela_itens.especialidade_id` → `hh_especialidades.id`
- `colaboradores.hh_especialidade_id` → `hh_especialidades.id`

---

## 🚀 Próximos Passos (Sugeridos)

1. **Browser Testing:** Testar todas as telas no navegador
2. **CSV Templates:** Criar exemplos de CSV para usuários
3. **Validação de Vigência:** Bloquear overlap de tabelas HH para mesmo cliente/ano
4. **Relatório Visual:** Dashboard de HH por OS (usando snapshots)
5. **Export CSV:** Permitir download de itens de tabela como CSV
6. **Histórico:** Registrar alterações em tabelas HH para auditoria

---

## 💡 Decisões Técnicas

### Por que CSV client-side?
- Evita complexidade de RPC server-side
- Feedback visual imediato de parsing
- Facilita debug (erros mostrados linha-por-linha)
- Não sobrecarrega banco com transações grandes

### Por que auto-criar especialidades?
- UX simplificado: importar CSV "just works"
- Reduce atrito para onboarding de novos clientes
- Especialidade é criada como `ativo=true` por padrão

### Por que upsert nos itens?
- Permite re-importar CSV corrigido sem duplicar
- Update de valores é comum (reajuste anual)
- Unique constraint `(tabela_id, especialidade_id)` garante integridade

### Por que usar `os.read` para menu HH?
- HH é contextual a Ordens de Serviço
- Quem acessa OS precisa ver tabelas HH
- Evita criar nova capability apenas para menu

---

## 📝 Notas de Implementação

- **TypeScript:** Todos os tipos definidos inline (sem arquivos separados)
- **Error Handling:** `setErr(error.message)` em todos os catches
- **Success Feedback:** `setOk("...")` após mutations
- **Loading States:** `busy` boolean para disable de botões
- **Confirmations:** `confirm()` antes de delete
- **Acessibilidade:** `aria-label` em inputs críticos
- **Mobile:** Grid responsivo com `md:grid-cols-*`

---

## ✅ Checklist de Entrega

- [x] Criar `app/cadastros/hh/especialidades/page.tsx`
- [x] Criar `app/cadastros/hh/tabelas/page.tsx`
- [x] Criar `app/cadastros/hh/tabelas/[id]/page.tsx`
- [x] Modificar `app/colaboradores/page.tsx` (campo especialidade)
- [x] Modificar `app/components/AppShell.tsx` (menu Cadastros)
- [x] Aplicar migrations no Supabase (3 arquivos)
- [x] Documentar módulo completo
- [ ] Testar no browser
- [ ] Criar dados de exemplo (seed)
- [ ] Treinar usuários finais

---

**Desenvolvedor:** GitHub Copilot (Claude Sonnet 4.5)  
**Data:** 2025-01-XX  
**Versão:** 1.0.0  
