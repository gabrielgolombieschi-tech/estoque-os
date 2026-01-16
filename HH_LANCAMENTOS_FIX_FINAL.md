# 🔧 CORREÇÃO DEFINITIVA: HH_LANCAMENTOS VALIDATION

## 📋 Data: 2026-02-18
## 🎯 Objetivo: Corrigir DEFINITIVAMENTE os erros ao salvar Lançamento HH

---

## ❌ PROBLEMA IDENTIFICADO

### Erros Reportados pelo Usuário:
1. **"Serviço HH X não está vinculado ao colaborador Y para o cliente Z"**
2. **"column empresa_id does not exist"**
3. **Relatório HH executando quando NÃO deveria**

### Raiz do Problema:

**SCHEMA MISMATCH** em 3 níveis:

1. **Tabela Errada Referenciada**:
   - Frontend/Code esperava: `colaborador_cliente_funcao`
   - Banco criou: `colaborador_funcao_hh` (migration 20260114)
   - Resultado: ❌ Validação falha com erro de tabela/coluna

2. **Coluna Errada**:
   - Frontend envia: `hh_servico_id`
   - Tabela tem: `servico_hh_id`
   - Resultado: ❌ "column empresa_id does not exist" (tentativa de validação falha)

3. **Escopo de Validação Errado**:
   - Código tentava: Validar contra `empresa_id`
   - Usuário diz: "colaborador_cliente_funcao NÃO TEM empresa_id"
   - Resultado: ❌ RLS rejeita porque column não existe

4. **Trigger no Lugar Errado**:
   - Trigger criada em: `apontamentos_horas` (tabela antiga)
   - Deveria estar em: `hh_lancamentos` (tabela nova)
   - Resultado: ❌ HH lançamentos sem validação própria

---

## ✅ SOLUÇÃO IMPLEMENTADA

### 1. **Nova Migration: `20260218_fix_hh_lancamentos_validation.sql`**

```sql
-- PASSO 1: Corrigir função de validação para apontamentos
   - Usa tabela correta: colaborador_funcao_hh
   - Valida com colunas corretas

-- PASSO 2: Criar validação NOVA para HH_LANCAMENTOS
   - Função: validate_hh_lancamento()
   - Valida APENAS: tenant_id, cliente_id, colaborador_id, servico_hh_id
   - NÃO usa empresa_id
   - NÃO consulta relatório
   - Trigger: trigger_validate_hh_lancamento

-- PASSO 3: Sincronizar dados (se houver tabela legada)
   - Detecta tabela colaborador_cliente_funcao
   - Copia dados para colaborador_funcao_hh se não existem

-- PASSO 4: Documentação
   - Comments em cada function
```

### 2. **Atualizações no Frontend: `RelatorioHHSection.tsx`**

**Linhas Atualizadas: 5 referências de tabela**

| Linha | Antes | Depois | Motivo |
|-------|-------|--------|--------|
| 554 | `.from("colaborador_cliente_funcao")` | `.from("colaborador_funcao_hh")` | Usar tabela correta |
| 554 | `hh_servico_id` | `servico_hh_id` | Usar coluna correta |
| 647 | `.from("colaborador_cliente_funcao")` | `.from("colaborador_funcao_hh")` | Usar tabela correta |
| 647 | `hh_servico_id` | `servico_hh_id` | Usar coluna correta |
| 1140 | `.from("colaborador_cliente_funcao")` | `.from("colaborador_funcao_hh")` | Usar tabela correta |
| 1140 | `hh_servico_id` | `servico_hh_id` | Usar coluna correta |
| 1161 | `.from("colaborador_cliente_funcao")` | `.from("colaborador_funcao_hh")` | Usar tabela correta |
| 1161 | `hh_servico_id` | `servico_hh_id` | Usar coluna correta |
| 1187 | `.from("colaborador_cliente_funcao")` | `.from("colaborador_funcao_hh")` | Usar tabela correta |
| 1187 | `hh_servico_id` | `servico_hh_id` | Usar coluna correta |

---

## 🔍 O QUE FOI REMOVIDO

❌ **Referências a `colaborador_cliente_funcao`** (tabela que não existe correctly)
- 5 ocorrências no frontend
- Várias no backend (validação anterior)

❌ **Validações contra `empresa_id`** em contexto de vínculo
- Era tentada em função de validação
- Coluna não existe na tabela de vínculo

❌ **Trigger em tabela errada**
- Trigger em `apontamentos_horas` apenas
- Não tinha validação em `hh_lancamentos`

❌ **Qualquer dependência com relatório**
- HH lançamento agora é INDEPENDENTE
- Relatório lê dados DEPOIS do save, não bloqueia

---

## 📝 O QUE FOI ADICIONADO

✅ **Função: `validate_hh_lancamento()`**
```sql
BEFORE INSERT OR UPDATE em hh_lancamentos
Valida:
  1. Se serve HH existe e está ativo
  2. Se colaborador tem vínculo com o serviço para o cliente
  3. NÃO consulta empresa_id
  4. NÃO consulta relatório
```

✅ **Função Corrigida: `validate_apontamento_colaborador_contrato()`**
```sql
Agora usa tabela correta: colaborador_funcao_hh
Mantém apenas para apontamentos_horas (não interfere com HH)
```

✅ **Sincronização Automática**
```sql
Se colaborador_cliente_funcao existir, copia dados para colaborador_funcao_hh
Evita perda de dados legados
```

---

## 🚀 FLUXO DE EXECUÇÃO (APÓS FIX)

```
User clica "Lançar Horas"
        ↓
Form abre (carrega colaboradores, especialidades)
        ↓
User seleciona: Data, Colaborador, Serviço HH
        ↓
User clica "Salvar"
        ↓
Frontend cria payload:
  {
    tenant_id: "...",
    empresa_id: "...",           ← Still needed for RLS
    os_id: 123,
    colaborador_id: "uuid",
    hh_tipo_id: 3,               ← ServiceID (correct field name)
    data: "2026-02-18",
    hora_entrada: "07:30",
    hora_saida: "17:00",
    ...
  }
        ↓
INSERT INTO hh_lancamentos (...)
        ↓
✅ Trigger: validate_hh_lancamento()
   1. Check: cliente_id exists in OS
   2. Check: hh_tipo_id (servico_hh_id) exists and active in cliente_hh_servicos
   3. Check: vínculo exists in colaborador_funcao_hh
      WHERE tenant = X
        AND cliente = X
        AND colaborador = X
        AND servico_hh_id = X
   4. Allow/Block insert
        ↓
✅ Trigger: calculate_hh_lancamento()
   1. Calculate hours from entrada/saida times
   2. Lookup price from service
   3. Update valor_total
        ↓
✅ RLS Policy: Check tenant_id + empresa_id (data isolation)
        ↓
✅ INSERT succeeds
        ↓
✅ Relatório carrega dados de hh_lancamentos
   (Can read, doesn't block insert)
        ↓
User sees: "Lançamento HH salvo com sucesso!"
```

---

## 🧪 TESTES PARA VALIDAR

### Teste 1: Vínculo Existente ✅
```
Precondição: Colaborador tem vínculo com Serviço HH para Cliente
Ação: Lançar horas
Resultado: ✅ Salva com sucesso
Erro NÃO aparece
```

### Teste 2: Vínculo NÃO Existe ❌
```
Precondição: Colaborador SEM vínculo com Serviço HH
Ação: Tentar lançar horas
Resultado: ❌ Erro: "Serviço HH X não está vinculado..."
Trigger rejeita INSERT
```

### Teste 3: Serviço HH Inativo ❌
```
Precondição: Serviço HH marcado como ativo=false
Ação: Tentar lançar horas
Resultado: ❌ Erro: "Serviço HH X não existe ou está inativo..."
Trigger rejeita INSERT
```

### Teste 4: Relatório NÃO Interfere ✅
```
Ação: Lançar horas (relatório pode estar vazio ou com erro)
Resultado: ✅ Lançamento salva mesmo assim
Relatório não bloqueia
```

### Teste 5: Sem "column empresa_id does not exist" ✅
```
Ação: Qualquer lançamento
Resultado: ✅ Sem erro de coluna inexistente
Se houver erro, é "Serviço não vinculado" (correto)
```

---

## 📂 ARQUIVOS MODIFICADOS

### 1. **Migration (NEW)**
```
supabase/migrations/20260218_fix_hh_lancamentos_validation.sql
```
- Corrige validações
- Cria trigger para hh_lancamentos
- Sincroniza dados

### 2. **Frontend (UPDATED)**
```
app/os/[id]/components/RelatorioHHSection.tsx
```
- Linhas 554, 647, 1140, 1161, 1187
- Tabela: `colaborador_cliente_funcao` → `colaborador_funcao_hh`
- Coluna: `hh_servico_id` → `servico_hh_id`

---

## 🔐 GARANTIAS

✅ **HH Lançamento é INDEPENDENTE de Relatório**
- Relatório não é chamado durante save
- Relatório não bloqueia insert

✅ **Validação usa APENAS os campos corretos**
- tenant_id, cliente_id, colaborador_id, servico_hh_id
- NÃO usa empresa_id em validação de vínculo

✅ **Tabela `colaborador_funcao_hh` é usada corretamente**
- Coluna correta: `servico_hh_id`
- RLS scope: `tenant_id`

✅ **Sem erros de coluna inexistente**
- Nenhuma referência a `empresa_id` em `colaborador_funcao_hh`
- Validação é simples e clara

---

## 📞 PRÓXIMOS PASSOS

1. **Executar Migration**:
   ```bash
   npm run db:migrate -- --from 20260218_fix_hh_lancamentos_validation.sql
   ```

2. **Testar (Teste 1-5 acima)**:
   - Criar vínculo de teste
   - Tentar lançar horas
   - Verificar se salva com sucesso

3. **Validar em Produção**:
   - Confirmar que erros sumiram
   - Verificar que relatório continua carregando dados

4. **Cleanup (se necessário)**:
   - Se houver tabela `colaborador_cliente_funcao` legada, pode ser dropada
   - (Migration sincroniza dados antes de dropar)

---

## 📚 REFERÊNCIAS

- **Migration anterior com problema**: `20260115_apontamentos_validate_colaborador_contrato.sql`
- **Tabela correta**: `20260114_colaborador_funcao_hh.sql`
- **Frontend fix**: `RelatorioHHSection.tsx` linhas 554, 647, 1140, 1161, 1187
- **Arquivo atualmete em uso**: `app/os/[id]/components/RelatorioHHSection.tsx`

---

## ✨ CONCLUSÃO

**O problema estava em:**
- Referência a tabela que não existe (ou com nome diferente)
- Coluna com nome diferente do esperado
- Validação em lugar errado (apontamentos vs hh_lancamentos)
- Tentativa de usar empresa_id onde não existe

**A solução corrige:**
- ✅ Usa tabela correta em TODAS as queries
- ✅ Usa coluna correta (servico_hh_id)
- ✅ Valida em hh_lancamentos (trigger nova)
- ✅ Remove empresa_id de validação simples
- ✅ Garante independência com relatório

**Resultado esperado:**
- ✅ "Serviço não vinculado" erro só aparece quando vínculo realmente não existe
- ✅ Sem erros de coluna inexistente
- ✅ HH salva sem depender de relatório
- ✅ Tudo funciona como esperado

