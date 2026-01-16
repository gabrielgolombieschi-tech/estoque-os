# Correção do Fluxo de Dados HH (Labor Hours)

**Data**: 15 de janeiro de 2026  
**Objetivo**: Acertar as ligações de dados quando a OS está flagada para HH (usa_relatorio_hh = true)

## Estrutura de Dados (Correta)

A hierarquia de dados começa sempre do **cliente** e flui assim:

```
CLIENTE (clientes.id)
    ↓
CLIENTE_HH_TABELAS (cliente_hh_tabelas.cliente_id)
    ├─ Contém: tabela de preços ativa com vigência
    ├─ Chave: tenant_id + cliente_id + ano (UNIQUE)
    └─ Referencia: cliente_id via FK
    ↓
CLIENTE_HH_SERVICOS (cliente_hh_servicos.cliente_id)
    ├─ Contém: especialidades/funções com preços (base, 50%, 100%)
    ├─ Chave: tenant_id + empresa_id + cliente_id + nome (UNIQUE)
    ├─ Referencia: cliente_id via FK
    └─ RLS: tenant_id + empresa_id
    ↓
COLABORADOR_CLIENTE_FUNCAO (colaborador_cliente_funcao.cliente_id)
    ├─ Contém: vínculos entre colaborador e especialidade
    ├─ Chave: tenant_id + cliente_id + colaborador_id + hh_servico_id (UNIQUE)
    ├─ Referencia: cliente_id via FK + hh_servico_id via FK
    ├─ RLS: tenant_id
    └─ Liga: Colaborador → Especialidade (para este cliente específico)
```

## Problemas Identificados

### 1. **Cliente_ID não era garantido no contexto**
- RelatorioHHSection recebia `osDetail?.cliente_id` mas não validava sua presença
- Se ausente, todo o fluxo falhava silenciosamente
- **Solução**: Adicionar `const clienteIdContext = osDetail?.cliente_id ?? null;` e validar em cada função

### 2. **Carregar dados sem validação de prerequisitos**
- Funções como `loadColaboradores()` não verificavam se `cliente_id` era válido
- Não havia logs suficientes para debug
- **Solução**: Adicionar validações com logs informativos em cada etapa

### 3. **useEffect dependencies incorretas**
- `osDetail?.cliente_id` era referência instável (novo objeto a cada render)
- Alterado para usar `clienteIdContext` (string/número estável)
- **Solução**: Usar a constante `clienteIdContext` como dependency

### 4. **RLS Scopes inconsistentes**
- Queries a `cliente_hh_servicos` não aplicavam sempre `applyTenantEmpresa`
- Fallback apenas para `applyTenant` em alguns casos
- **Solução**: Sempre usar `applyTenantEmpresa(query, ctx.tenant, ctx.empresa)`

## Correções Implementadas

### A. Adicionar Validação do Cliente ID

```tsx
// NOVO: Garantir que cliente_id sempre vem do osDetail
const clienteIdContext = osDetail?.cliente_id ?? null;

// NOVO: Efeito que valida cliente_id antes de carregar
useEffect(() => {
  if (!clienteIdContext) {
    setHhErr("Cliente não identificado. Não é possível carregar apontamentos HH.");
    return;
  }
  void loadHhLancamentos();
}, [osId, clienteIdContext]);
```

### B. Melhorar loadTabelaAtiva()

**Antes**: Construía base query uma vez e reutilizava (erro de Supabase fluent)

**Depois**: 
- Valida `cliente_id` antes de qualquer coisa
- Separa em 2 queries: vigente (dentro do período) vs fallback (mais recente)
- Logs claros de qual foi escolhida e por quê
- Trata erro corretamente se nenhuma tabela existe

```tsx
async function loadTabelaAtiva(clienteId: number, dataISO: string): Promise<TabelaAtiva | null> {
  if (!clienteId) {
    console.warn("[loadTabelaAtiva] cliente_id não fornecido");
    return null;
  }
  
  // ... query vigente primeiro
  // ... fallback se não encontrar
}
```

### C. Melhorar loadColaboradores()

**Antes**: Carregava vínculos mas não validava

**Depois**:
- Valida `cliente_id` e `tenant` antes de query
- Carrega vínculos (colaborador_cliente_funcao) com `.eq("cliente_id", clienteId)`
- Mapeia vínculos em `vinculoEspecialidadesRef` logo durante carregamento
- Carrega dados dos colaboradores apenas se houver vínculos
- Logs descritivos de quantos colaboradores foram carregados

### D. Melhorar loadEspecialidadesParaColaborador()

**Antes**: Tentava usar queryBase reutilizada + fallback confuso

**Depois**:
- Valida `cliente_id` + `colaborador_id` + `tenant` + `empresa`
- Tenta primeira opção: vínculos do ref map (já em memória)
- Fallback: query direto em `colaborador_cliente_funcao` se ref vazio
- Carrega serviços de `cliente_hh_servicos` com `applyTenantEmpresa`
- Filtra opções por `cliente_id` (essencial!)
- Auto-seleciona se apenas 1 especialidade disponível
- Pré-carrega preços da especialidade selecionada

### E. Ajustar useEffect Dependencies

**Antes**:
```tsx
useEffect(() => {
  if (!showLancamentoForm) return;
  if (!osDetail?.cliente_id) return;
  const run = async () => { await loadTabelaAtiva(osDetail.cliente_id, ...) }
}, [showLancamentoForm, lancamentoForm.data, osDetail?.cliente_id]) // ❌ instável
```

**Depois**:
```tsx
useEffect(() => {
  if (!showLancamentoForm) return;
  if (!clienteIdContext) return;
  const run = async () => { await loadTabelaAtiva(clienteIdContext, ...) }
}, [showLancamentoForm, lancamentoForm.data, clienteIdContext]) // ✅ estável
```

## Fluxo Correto na UI

### 1. Usuário abre formulário de lançamento HH

```
useEffect(showLancamentoForm + lancamentoForm.data + clienteIdContext)
  ↓
Valida cliente_id
  ↓
loadTabelaAtiva(clienteId, data)
  └─ Query: cliente_hh_tabelas WHERE cliente_id + ativo
  └─ Retorna tabela vigente ou mais recente
  ↓
loadColaboradores(clienteId)
  └─ Query: colaborador_cliente_funcao WHERE cliente_id + ativo
  └─ Mapeia hh_servico_ids em vinculoEspecialidadesRef
  └─ Query: colaboradores WHERE id IN (colaborador_ids)
  └─ Retorna [{ id, nome, ativo }]
```

### 2. Usuário seleciona um colaborador

```
useEffect(lancamentoForm.colaborador_id + clienteIdContext + tabelaAtiva)
  ↓
loadEspecialidadesParaColaborador(clienteId, colaboradorId)
  └─ Tenta vinculoEspecialidadesRef.get(colaboradorId)
  └─ Se vazio, query direto em colaborador_cliente_funcao
  └─ Query: cliente_hh_servicos WHERE cliente_id + id IN (servicos)
  └─ Auto-seleciona se 1 apenas
  └─ Pré-carrega preços
```

### 3. Usuário completa lançamento e salva

```
salvarLancamento()
  ↓
Valida todos os campos
  ↓
Resolve hh_tipo_id (via categoria de nome do serviço)
  ↓
Query: cliente_hh_servicos.preco_base/50/100 para serviço selecionado
  ↓
Insert em hh_lancamentos com:
  - tenant_id (do context)
  - empresa_id (do context)
  - os_id, data, colaborador_id, entrada_1/2, saida_1/2
  - hh_tipo_id (resolvido)
  - percentual_aplicado (calculado da data)
  - valor_hora (do cliente_hh_servicos)
```

## RLS Scopes Aplicados

Todas as queries agora aplicam RLS corretamente:

| Tabela | Query Pattern | RLS Scope |
|--------|---------------|-----------|
| cliente_hh_tabelas | select... .eq("cliente_id", id) | `applyTenant(query, tenant)` |
| colaborador_cliente_funcao | select... .eq("cliente_id", id) | `applyTenant(query, tenant)` |
| colaboradores | select... .in("id", ids) | `applyTenant(query, tenant)` |
| cliente_hh_servicos | select... .eq("cliente_id", id) | `applyTenantEmpresa(query, tenant, empresa)` |
| hh_lancamentos | select/insert... | `applyTenantEmpresa(query, tenant, empresa)` |

## Validações Adicionadas

1. **Cliente ID Context**: Validado no componente raiz
2. **Tenant Resolution**: Via `ensureDbContext()`
3. **Empresa Resolution**: Via `ensureDbContext()` + RPC fallback
4. **Tabela Ativa**: Valida vigência ou usa fallback
5. **Colaboradores**: Valida se existem vínculos para cliente
6. **Especialidades**: Valida se colaborador tem specialidades linked
7. **Serviço**: Valida se existe em cliente_hh_servicos
8. **Preços**: Carrega de cliente_hh_servicos antes de salvar

## Logs Adicionados

Cada função agora registra seus passos:
- `[loadTabelaAtiva]`: quando tabela vigente/fallback é escolhida
- `[loadColaboradores]`: quantos colaboradores foram carregados
- `[loadEspecialidadesParaColaborador]`: quantas opções foram carregadas
- `[useEffect]`: quando carrega contexto HH

## Próximas Etapas (Recomendadas)

1. **Testar fluxo completo**:
   - Criar OS com cliente HH-habilitado
   - Abrir formulário de lançamento
   - Verificar logs no console
   - Completar lançamento

2. **Adicionar validação de permissões**:
   - `colaborador_cliente_funcao` deveria ter RLS de `empresa_id`?
   - Verificar se usuário pode ver colaboradores de outro cliente

3. **Melhorar UX**:
   - Loader enquanto carrega tabela/colaboradores
   - Mensagem se cliente sem tabela HH ativa
   - Mensagem se colaborador sem especialidades

4. **Performance**:
   - Cache de cliente_hh_tabelas (muda 1x por ano)
   - Batching de queries de colaboradores/especialidades

## Resumo das Mudanças

| Componente | Mudanças |
|-----------|----------|
| RelatorioHHSection props | Adicionar `const clienteIdContext` |
| loadTabelaAtiva | Validação + 2 queries separadas + logs |
| loadColaboradores | Validação + mapa de vínculos + logs |
| loadEspecialidadesParaColaborador | Validação + ref fallback + auto-select + preços |
| useEffect (tabela+colaboradores) | Usar `clienteIdContext` em dependencies |
| useEffect (especialidades) | Usar `clienteIdContext` + adicionar logs |

**Total de linhas**: ~150 adicionadas/modificadas  
**Arquivos afetados**: 1 (RelatorioHHSection.tsx)  
**Compatibilidade**: 100% (sem quebra de contrato)
